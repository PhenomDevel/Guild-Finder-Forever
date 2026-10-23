-- luacheck: read globals JoinTemporaryChannel JoinChannelByName LeaveChannelByName GetChannelName GetChannelList ChatFrameUtil ChatFrame_AddMessageEventFilter ChatFrame_AddChannel ChatFrame_RemoveChannel Constants NUM_CHAT_WINDOWS
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
}

local function Filter(_, _, ...)
	if not Channel.hidden then
		return false
	end
	local baseName = select(9, ...)
	return type(baseName) == "string" and baseName:lower() == lowerName
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
ns:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE", function(_, notice, ...)
	local baseName = select(8, ...)
	if type(baseName) ~= "string" or baseName:lower() ~= lowerName then
		return
	end
	if notice == "YOU_JOINED" or notice == "YOU_CHANGED" then
		SetReady()
	elseif notice == "YOU_LEFT" then
		Channel.ready = false
		ns:Fire("GFF_CHANNEL_LEFT")
	end
	ns:Fire("GFF_CHANNEL_NOTICE", notice)
end)
