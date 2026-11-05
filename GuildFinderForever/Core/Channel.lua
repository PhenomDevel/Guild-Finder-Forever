-- luacheck: read globals JoinTemporaryChannel JoinChannelByName LeaveChannelByName ListChannelByName GetChannelName GetChannelList UnitName GetNormalizedRealmName ERR_CHAT_PLAYER_NOT_FOUND_S ChatFrameUtil ChatFrame_AddMessageEventFilter ChatFrame_AddChannel ChatFrame_RemoveChannel Constants NUM_CHAT_WINDOWS
local _, ns = ...

-- The hidden chat channel all ads travel through. It is joined after login,
-- once the client has joined its default channels (otherwise ours could take
-- slot 1 and shift General/Trade), and removed from every chat frame.
local Channel = {}
ns.Channel = Channel

Channel.NAME = "GuildFinderForever"

-- Delay after entering the world before the first join attempt, and the
-- number of attempts to wait for the default channels / our channel.
local JOIN_DELAY = 5
local RETRY_DELAY = 3
local MAX_ATTEMPTS = 8

local lowerName = Channel.NAME:lower()
local maxWindows = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows or NUM_CHAT_WINDOWS or 10
local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter

-- While false, the channel and its notices are shown in chat (debugging).
Channel.hidden = true

-- Local channel index, or nil while not joined.
function Channel.GetNumber()
	local id = GetChannelName(Channel.NAME)
	if type(id) == "number" and id > 0 then
		return id
	end
end

local function ForEachChatFrame(func)
	for i = 1, maxWindows do
		local frame = _G["ChatFrame" .. i]
		if frame then
			func(frame)
		end
	end
end

-- Which API removes/adds channels on chat frames; reported by the probe.
function Channel.GetChatFrameApi()
	local frame = _G.ChatFrame1
	if frame and frame.RemoveChannel then
		return "ChatFrame:RemoveChannel"
	elseif ChatFrame_RemoveChannel then
		return "ChatFrame_RemoveChannel"
	end
	return "none"
end

function Channel.RemoveFromChatFrames()
	ForEachChatFrame(function(frame)
		if frame.RemoveChannel then
			frame:RemoveChannel(Channel.NAME)
		elseif ChatFrame_RemoveChannel then
			ChatFrame_RemoveChannel(frame, Channel.NAME)
		end
	end)
end

function Channel.SetHidden(hidden)
	Channel.hidden = hidden
	if hidden then
		Channel.RemoveFromChatFrames()
	else
		local frame = DEFAULT_CHAT_FRAME
		if frame.AddChannel then
			frame:AddChannel(Channel.NAME)
		elseif ChatFrame_AddChannel then
			ChatFrame_AddChannel(frame, Channel.NAME)
		end
	end
end

--------------------------------------------------------------------------------
-- Chat filter
--------------------------------------------------------------------------------
-- Drops chat text and notices of our channel, should it still be shown in a
-- frame or someone types into it. The 9th event argument is the channel's
-- base name. Blizzard skips filters for messages with secret values.

local FILTER_EVENTS = {
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_CHANNEL_NOTICE",
	"CHAT_MSG_CHANNEL_NOTICE_USER",
	"CHAT_MSG_CHANNEL_JOIN",
	"CHAT_MSG_CHANNEL_LEAVE",
	"CHAT_MSG_CHANNEL_LIST",
}

-- Member lists are only hidden shortly after the addon asked for one, so a
-- manual /chatlist still shows.
local LIST_HIDE_TIME = 5
local hideListUntil = 0

-- Whether chat event arguments 4 (display name "5. Name") and 9 (base name)
-- belong to our channel.
local function IsOurs(channelName, baseName)
	if issecretvalue and (issecretvalue(channelName) or issecretvalue(baseName)) then
		return false
	end
	if type(baseName) == "string" and baseName ~= "" then
		return baseName:lower() == lowerName
	end
	return type(channelName) == "string" and (channelName:lower() == lowerName
		or channelName:lower():match("^%d+%.%s*(.-)$") == lowerName)
end

local function Filter(_, event, ...)
	if not Channel.hidden then
		return false
	end
	local channelName, baseName = select(4, ...), select(9, ...)
	if event == "CHAT_MSG_CHANNEL_LIST" and GetTime() > hideListUntil then
		return false
	end
	return IsOurs(channelName, baseName)
end

if AddFilter then
	for _, event in ipairs(FILTER_EVENTS) do
		AddFilter(event, Filter)
	end
end
Channel.hasChatFilter = AddFilter ~= nil

--------------------------------------------------------------------------------
-- Joining
--------------------------------------------------------------------------------

local attempts = 0
local joinRequested = false

-- The channel number can change when other channels are left or joined, so
-- callers look it up with GetNumber() on every send.
Channel.ready = false

local function RemoveIfHidden()
	if Channel.hidden then
		Channel.RemoveFromChatFrames()
	end
end

local function SetReady()
	RemoveIfHidden()
	-- The chat frames may add the channel after our handler for the join
	-- notice has run.
	C_Timer.After(1, RemoveIfHidden)
	if not Channel.ready then
		Channel.ready = true
		ns:Fire("GFF_CHANNEL_READY", Channel.GetNumber())
	end
end

local function TryJoin()
	if Channel.GetNumber() then
		SetReady()
		return
	end
	attempts = attempts + 1
	-- Wait for the default channels unless there are none here (e.g. in an
	-- instance), then give up waiting.
	local hasDefaultChannels = select("#", GetChannelList()) > 0
	if hasDefaultChannels or attempts >= MAX_ATTEMPTS / 2 then
		if not joinRequested then
			joinRequested = true
			-- Temporary: not stored in the client's channel list, so the
			-- addon stays in control of when it is joined.
			local join = JoinTemporaryChannel or JoinChannelByName
			join(Channel.NAME)
		end
	end
	if attempts < MAX_ATTEMPTS then
		C_Timer.After(RETRY_DELAY, TryJoin)
	else
		ns:Fire("GFF_CHANNEL_FAILED")
	end
end

function Channel.Join()
	attempts = 0
	joinRequested = false
	TryJoin()
end

function Channel.Leave()
	LeaveChannelByName(Channel.NAME)
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
	if isLogin or isReload then
		C_Timer.After(JOIN_DELAY, Channel.Join)
	end
end)

-- Notices for our channel: YOU_JOINED/YOU_CHANGED, YOU_LEFT, errors such as
-- WRONG_PASSWORD or BANNED, owner changes. Forwarded for logging.
-- NOT_ALLOWED_IN_CHANNEL: the server dropped an addon message sent to the
-- channel (Forever since launch); ns.Comm switches to whispers.
ns:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", function(_, notice, ...)
	local channelName, baseName = select(3, ...), select(8, ...)
	if not IsOurs(channelName, baseName) then
		return
	end
	if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
		SetReady()
	elseif notice == "YOU_LEFT" then
		Channel.ready = false
		ns:Fire("GFF_CHANNEL_LEFT")
	elseif notice == "NOT_ALLOWED_IN_CHANNEL" then
		ns:Fire("GFF_CHANNEL_BLOCKED")
	end
	ns:Fire("GFF_CHANNEL_NOTICE", notice)
end)

--------------------------------------------------------------------------------
-- Members
--------------------------------------------------------------------------------
-- Where addon messages to the channel are dropped, the channel only serves
-- to find the other addon users: its member list (/chatlist) plus join and
-- leave events. ns.Comm whispers them instead.

-- [name as the server lists it, whisper target] = true
local peers = {}
local numPeers = 0
local ROSTER_INTERVAL = 5 * 60
local lastRoster = 0

local function IsSelf(name)
	local full = UnitFullName("player")
	return name == full or name == UnitName("player") or name == ns:GetPlayerFullName()
end

-- Peers are keyed by whisper target: same-realm names without the realm,
-- as the member list shows them.
local function PeerKey(name)
	local realm = GetNormalizedRealmName()
	if type(realm) == "string" and realm ~= "" and name:sub(-#realm - 1) == "-" .. realm then
		return name:sub(1, -#realm - 2)
	end
	return name
end

function Channel.AddPeer(name)
	if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then
		return
	end
	name = PeerKey(name)
	if IsSelf(name) or peers[name] then
		return
	end
	peers[name] = true
	numPeers = numPeers + 1
	ns:Fire("GFF_PEERS_CHANGED", numPeers)
end

function Channel.RemovePeer(name)
	if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then
		return
	end
	name = PeerKey(name)
	if peers[name] then
		peers[name] = nil
		numPeers = numPeers - 1
		ns:Fire("GFF_PEERS_CHANGED", numPeers)
	end
end

function Channel.GetNumPeers()
	return numPeers
end

-- Up to count random members, without the given name.
function Channel.PickPeers(count, except)
	except = type(except) == "string" and PeerKey(except) or nil
	local list = {}
	for name in pairs(peers) do
		if name ~= except then
			list[#list + 1] = name
		end
	end
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	for i = #list, count + 1, -1 do
		list[i] = nil
	end
	return list
end

-- Asks the server for the member list (answered with CHAT_MSG_CHANNEL_LIST,
-- hidden by the chat filter). Throttled unless forced.
function Channel.RequestMembers(force)
	if not ListChannelByName or not Channel.GetNumber() then
		return
	end
	local now = GetTime()
	if not force and now - lastRoster < ROSTER_INTERVAL then
		return
	end
	lastRoster = now
	hideListUntil = now + LIST_HIDE_TIME
	ListChannelByName(Channel.NAME)
end

-- The list arrives as "Name One, *Owner Name, @Moderator", possibly split
-- over several events for large channels.
ns:RegisterEvent("CHAT_MSG_CHANNEL_LIST", function(_, text, _, _, channelName, ...)
	local baseName = select(5, ...)
	if not IsOurs(channelName, baseName) or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return
	end
	for entry in text:gmatch("[^,]+") do
		local name = entry:gsub("^%s*[%*@]*", ""):gsub("%s+$", "")
		Channel.AddPeer(name)
	end
end)

ns:RegisterEvent("CHAT_MSG_CHANNEL_JOIN", function(_, _, name, _, channelName, ...)
	if IsOurs(channelName, select(5, ...)) then
		Channel.AddPeer(name)
	end
end)

ns:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE", function(_, _, name, _, channelName, ...)
	if IsOurs(channelName, select(5, ...)) then
		Channel.RemovePeer(name)
	end
end)

-- A whisper to a member who went offline makes the server print "No player
-- named ..."; hide that line and drop the member.
local notFound = ERR_CHAT_PLAYER_NOT_FOUND_S
	and "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%s", "(.+)") .. "$"
if AddFilter and notFound then
	AddFilter("CHAT_MSG_SYSTEM", function(_, _, text)
		if numPeers == 0 or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
			return false
		end
		local name = text:match(notFound)
		if name and peers[PeerKey(name)] then
			Channel.RemovePeer(name)
			return true
		end
		return false
	end)
end
