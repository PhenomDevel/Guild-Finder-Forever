-- luacheck: read globals C_FriendList ChatFrameUtil ChatFrame_SendTell
local _, ns = ...

-- "Contact": runs a /who on the poster and opens a whisper. The /who result
-- checks the ad: a guild ad needs the poster in that guild, a player ad the
-- advertised class. A mismatch marks the ad suspicious (hidden from search);
-- an offline poster gives no verdict.
local Verify = {}
ns.Verify = Verify

local Ads = ns.Ads
local Store = ns.Store

local TIMEOUT = 6

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
