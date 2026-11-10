-- luacheck: read globals ChatFrameUtil ChatFrame_AddMessageEventFilter ERR_CHAT_PLAYER_NOT_FOUND_S
local _, ns = ...

-- Online status of ad posters, in memory only. Sources:
-- * any addon message from a player, a join of the addon channel: online
-- * leaving the channel, "No player named ..." after any whisper: offline
-- * Presence.Watch: pings the posters shown in a list (the ping of
--   ns.Verify, answered by every addon version since 1.0) one after another;
--   an answer means online, a bounce offline, silence leaves it unknown.
-- Also the guild posters are in (saved): from ping answers and /who.
local Presence = {}
ns.Presence = Presence

local Ads = ns.Ads
local Comm = ns.Comm
local Serializer = ns.Serializer
local C = ns.Constants

local ONLINE_TTL = 600 -- seconds a sign of life counts
local OFFLINE_TTL = 300 -- seconds until an offline poster is asked again
local PING_INTERVAL = 0.5
local PING_TIMEOUT = 5
local CHANGED_DELAY = 0.3
local MAX_GUILD = 64

-- [lowercase name without realm] = { g = guild name, at = server time },
-- only posters seen in a guild; good as long as an ad lives.
ns.dbDefaults.posterGuilds = {}

-- [lowercase name without realm] = { online = bool, at = GetTime() }
local states = {}
-- [key] = GetTime() sent, pings without a reply or bounce yet
local pending = {}
local queue, queued = {}, {}
local ticker, changedTimer
local watcher -- who called Watch last

-- Forever names have no realm part, retail ones are matched without it
-- (like the /who check).
local function Key(name)
	if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" or name == "" then
		return nil
	end
	return Ads.OwnerName(name):lower()
end

local function Changed()
	if changedTimer then
		return
	end
	changedTimer = C_Timer.NewTimer(CHANGED_DELAY, function()
		changedTimer = nil
		ns:Fire("GFF_PRESENCE_CHANGED")
	end)
end

local function Set(name, online)
	local key = Key(name)
	if not key or key == Key(ns:GetPlayerFullName()) then
		return
	end
	local state = states[key]
	if state and state.online == online then
		state.at = GetTime()
		return
	end
	states[key] = { online = online, at = GetTime() }
	Changed()
end

-- true online, false offline, nil unknown.
function Presence.IsOnline(owner)
	local key = Key(owner)
	if key and key == Key(ns:GetPlayerFullName()) then
		return true
	end
	local state = key and states[key]
	if not state then
		return nil
	end
	if GetTime() - state.at > (state.online and ONLINE_TTL or OFFLINE_TTL) then
		return nil
	end
	return state.online
end

-- guild nil: seen without a guild. Anything but a short string without
-- escape sequences is ignored (the name is shown in the list).
function Presence.SetGuild(name, guild)
	local key = Key(name)
	if not key or not ns.db or key == Key(ns:GetPlayerFullName()) then
		return
	end
	if guild == "" then
		guild = nil
	elseif guild ~= nil and (type(guild) ~= "string" or (issecretvalue and issecretvalue(guild))
		or #guild > MAX_GUILD or guild:find("|", 1, true)) then
		return
	end
	local guilds = ns.db.posterGuilds
	local entry = guilds[key]
	if entry and entry.g == guild then
		entry.at = GetServerTime()
		return
	end
	if not entry and not guild then
		return
	end
	guilds[key] = guild and { g = guild, at = GetServerTime() } or nil
	Changed()
end

-- Guild the poster was last seen in; nil without one or when unknown.
function Presence.GetGuild(owner)
	local key = Key(owner)
	local entry = key and ns.db and ns.db.posterGuilds[key]
	if not entry or GetServerTime() - entry.at > C.AD_LIFETIME then
		return nil
	end
	return entry.g
end

ns.RegisterCallback(Presence, "GFF_DB_READY", function()
	local now = GetServerTime()
	local guilds = ns.db.posterGuilds
	for key, entry in pairs(guilds) do
		if type(key) ~= "string" or type(entry) ~= "table" or type(entry.g) ~= "string"
			or type(entry.at) ~= "number" or now - entry.at > C.AD_LIFETIME then
			guilds[key] = nil
		end
	end
end)

local function Stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function PingNext()
	if Comm.InLockdown() then
		return
	end
	while queue[1] do
		local owner = table.remove(queue, 1)
		local key = Key(owner)
		queued[owner] = nil
		if key and not pending[key] and Presence.IsOnline(owner) == nil then
			if not Comm.SendWhisper(owner, Serializer.Serialize({ y = "P", n = math.random(1, 2 ^ 30) })) then
				Stop()
				return
			end
			local sent = GetTime()
			pending[key] = sent
			C_Timer.After(PING_TIMEOUT, function()
				if pending[key] == sent then
					pending[key] = nil
				end
			end)
			return
		end
	end
	Stop()
end

-- Asks the posters of owners (in that order) whose status is unknown;
-- replaces the previous list, also another source's. Call again when the
-- list changes.
function Presence.Watch(owners, source)
	watcher = source
	wipe(queue)
	wipe(queued)
	for _, owner in ipairs(owners) do
		if type(owner) == "string" and not queued[owner] and Presence.IsOnline(owner) == nil then
			queued[owner] = true
			queue[#queue + 1] = owner
		end
	end
	if queue[1] and not ticker then
		ticker = C_Timer.NewTicker(PING_INTERVAL, PingNext)
		PingNext()
	elseif not queue[1] then
		Stop()
	end
end

-- Only stops source's list: a tab being hidden must not stop the list of
-- the tab shown in its place (shown first).
function Presence.StopWatching(source)
	if source ~= watcher then
		return
	end
	watcher = nil
	wipe(queue)
	wipe(queued)
	Stop()
end

Comm.RegisterHandler(function(_, sender)
	Set(sender, true)
end)

-- Channel members (joins, /chatlist) are online.
ns.RegisterCallback(Presence, "GFF_PEER_SEEN", function(_, name)
	Set(name, true)
end)

ns.RegisterCallback(Presence, "GFF_PEER_LEFT", function(_, name)
	Set(name, false)
end)

-- Event, not chat filter: other filters (Channel, Verify) may hide the line
-- before ours sees it.
local notFound = ERR_CHAT_PLAYER_NOT_FOUND_S
	and "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"

local function BouncedName(text)
	if not notFound or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return nil
	end
	return text:match(notFound)
end

ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text)
	local name = BouncedName(text)
	if name then
		Set(name, false)
	end
end)

-- Hide the bounce of own pings. Chat frames get the event before the
-- handler above; pending entries expire by timeout only.
local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
if AddFilter then
	AddFilter("CHAT_MSG_SYSTEM", function(_, _, text)
		local key = Key(BouncedName(text))
		return key ~= nil and pending[key] ~= nil
	end)
end
