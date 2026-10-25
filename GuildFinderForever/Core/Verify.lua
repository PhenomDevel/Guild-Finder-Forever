-- luacheck: read globals C_FriendList ChatFrameUtil ChatFrame_SendTell ChatFrame_AddMessageEventFilter ERR_CHAT_PLAYER_NOT_FOUND_S GetGuildInfo UnitClass
local _, ns = ...

-- Checks that an ad's poster exists and matches the ad: a guild ad needs
-- the poster in that guild, a player ad the advertised class. A mismatch
-- marks the ad suspicious (hidden from search); an unreachable poster gives
-- no verdict.
-- * Ping (in the background, when details open): an addon whisper the
--   poster's client answers with its guild and class. Proves the character
--   exists, is online and runs the addon; guild and class are self-reported.
-- * "Contact": opens a whisper and runs a /who on the poster (needs a click).
local Verify = {}
ns.Verify = Verify

local Ads = ns.Ads
local Store = ns.Store
local Comm = ns.Comm
local Serializer = ns.Serializer

local TIMEOUT = 6
local PING_TIMEOUT = 5
local RECHECK_AFTER = 3600 -- seconds a ping result stays good
local PONG_INTERVAL = 2 -- per asker

-- { ad, sent }
local current

local function OpenWhisper(name)
	if ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(name)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(name)
	end
end

-- Whisper target: same-realm names without the realm.
local function WhisperName(owner)
	local realm = Ads.OwnerRealm(owner)
	if realm and realm == Ads.GetRealm() then
		return Ads.OwnerName(owner)
	end
	return owner
end

local function Finish(result)
	local ad = current and current.ad
	current = nil
	if ad then
		ns:Fire("GFF_VERIFY_DONE", ad, result)
	end
end

-- Must run from a click: /who needs a hardware event.
function Verify.Contact(ad)
	OpenWhisper(WhisperName(ad.o))
	if not (C_FriendList and C_FriendList.SendWho) then
		return
	end
	local name = Ads.OwnerName(ad.o)
	current = { ad = ad, sent = GetTime() }
	-- Results to the who list (WHO_LIST_UPDATE), not as chat lines.
	if C_FriendList.SetWhoToUi then
		C_FriendList.SetWhoToUi(true)
	end
	local ok = pcall(C_FriendList.SendWho, ('n-"%s"'):format(name))
	if not ok then
		Finish("error")
		return
	end
	ns:Fire("GFF_VERIFY_STARTED", ad)
	local request = current
	C_Timer.After(TIMEOUT, function()
		if current == request then
			Finish("timeout")
		end
	end)
end

local function Evaluate(info, ad)
	if ad.k == Ads.KIND_GUILD then
		return info.fullGuildName == ad.n
	end
	return info.filename == nil or info.filename == ad.c
end

ns:RegisterEvent("WHO_LIST_UPDATE", function()
	if not current then
		return
	end
	local ad = current.ad
	local wanted = Ads.OwnerName(ad.o)
	local shown = C_FriendList.GetNumWhoResults() or 0
	for i = 1, shown do
		local info = C_FriendList.GetWhoInfo(i)
		local fullName = info and info.fullName
		if type(fullName) == "string" and not (issecretvalue and issecretvalue(fullName)) then
			if fullName == ad.o or Ads.OwnerName(fullName) == wanted then
				local verified = Evaluate(info, ad)
				Store.SetCheck(ad.i, verified)
				Finish(verified and "verified" or "suspicious")
				return
			end
		end
	end
	Finish("offline")
end)

--------------------------------------------------------------------------------
-- Ping
--------------------------------------------------------------------------------

-- [owner] = { ad, nonce, target }
local pings = {}
local ponged = {}

local function FinishPing(owner, result, verified)
	local entry = pings[owner]
	if not entry then
		return
	end
	pings[owner] = nil
	if result ~= "unreachable" then
		Store.SetCheck(entry.ad.i, verified)
	end
	ns:Fire("GFF_VERIFY_DONE", entry.ad, result)
end

-- Background check of an ad's poster; skipped for own ads and recent checks.
function Verify.Ping(ad)
	if not ad or ad.o == ns:GetPlayerFullName() or pings[ad.o] then
		return
	end
	local check = Store.GetCheck(ad.i)
	if check and GetServerTime() - (check.checked or 0) < RECHECK_AFTER then
		return
	end
	local nonce = math.random(1, 2 ^ 30)
	local target = WhisperName(ad.o)
	if not Comm.SendWhisper(target, Serializer.Serialize({ y = "P", n = nonce })) then
		return
	end
	local entry = { ad = ad, nonce = nonce, target = target:lower() }
	pings[ad.o] = entry
	ns:Fire("GFF_VERIFY_STARTED", ad)
	C_Timer.After(PING_TIMEOUT, function()
		if pings[ad.o] == entry then
			FinishPing(ad.o, "unreachable")
		end
	end)
end

Comm.RegisterHandler(function(text, sender, distribution)
	if distribution ~= "WHISPER" then
		return
	end
	local message = Serializer.Deserialize(text)
	if type(message) ~= "table" or type(message.n) ~= "number" then
		return
	end
	if message.y == "P" then
		local now = GetTime()
		if ponged[sender] and now - ponged[sender] < PONG_INTERVAL then
			return
		end
		ponged[sender] = now
		local _, classFile = UnitClass("player")
		Comm.SendWhisper(sender, Serializer.Serialize({ y = "Q", n = message.n, g = GetGuildInfo("player"), c = classFile }))
	elseif message.y == "Q" then
		local name = Ads.OwnerName(sender)
		for owner, entry in pairs(pings) do
			if entry.nonce == message.n and Ads.OwnerName(owner) == name then
				local ad = entry.ad
				local verified
				if ad.k == Ads.KIND_GUILD then
					verified = type(message.g) == "string" and message.g == ad.n
				else
					verified = type(message.c) == "string" and message.c == ad.c
				end
				FinishPing(owner, verified and "verified" or "suspicious", verified)
				return
			end
		end
	end
end)

-- An addon whisper to someone offline makes the server print "No player
-- named ..."; hide that line for own pings and count it as unreachable.
local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local notFound = ERR_CHAT_PLAYER_NOT_FOUND_S
	and "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"
if AddFilter and notFound then
	AddFilter("CHAT_MSG_SYSTEM", function(_, _, text)
		if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or not next(pings) then
			return false
		end
		local name = text:match(notFound)
		if not name then
			return false
		end
		name = name:lower()
		for owner, entry in pairs(pings) do
			if entry.target == name then
				FinishPing(owner, "unreachable")
				return true
			end
		end
		return false
	end)
end
