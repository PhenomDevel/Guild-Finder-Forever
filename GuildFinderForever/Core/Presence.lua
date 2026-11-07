-- luacheck: read globals ChatFrameUtil ChatFrame_AddMessageEventFilter ERR_CHAT_PLAYER_NOT_FOUND_S
local _, ns = ...

-- Online status of ad posters, in memory only. Sources:
-- * any addon message from a player, a join of the addon channel: online
-- * leaving the channel, "No player named ..." after any whisper: offline
-- * Presence.Watch: pings the posters shown in a list (the ping of
--   ns.Verify, answered by every addon version since 1.0) one after another;
--   an answer means online, a bounce offline, silence leaves it unknown.
local Presence = {}
ns.Presence = Presence

local Ads = ns.Ads
local Comm = ns.Comm
local Serializer = ns.Serializer

local ONLINE_TTL = 600 -- seconds a sign of life counts
local OFFLINE_TTL = 300 -- seconds until an offline poster is asked again
local PING_INTERVAL = 0.5
local PING_TIMEOUT = 5
local CHANGED_DELAY = 0.3

-- [lowercase name without realm] = { online = bool, at = GetTime() }
local states = {}
-- [key] = GetTime() sent, pings without a reply or bounce yet
local pending = {}
local queue, queued = {}, {}
local ticker, changedTimer

-- Forever names have no realm part, retail ones are matched without it
-- (like the /who check).
local function Key(name)
	if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then
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
-- replaces the previous list. Call again when the list changes.
function Presence.Watch(owners)
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

function Presence.StopWatching()
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
