-- luacheck: read globals IsTrialAccount IsVeteranTrialAccount
local _, ns = ...

-- Transport for all addon traffic: compress + encode with LibDeflate, send via
-- AceComm over the hidden channel. Messages are held while the channel isn't
-- joined or chat messaging is locked down (encounters etc.) and sent
-- afterwards in order. ChatThrottleLib would drop them instead: it only
-- retries on AddonMessageThrottle, not on lockdown.
-- Whisper mode: Forever's server drops addon messages to any chat channel
-- (NOT_ALLOWED_IN_CHANNEL). There a broadcast goes as addon whispers to a
-- few random channel members (ns.Channel peers) and the sync protocol
-- forwards fresh ads (gossip).
local Comm = {}
ns.Comm = Comm

local LibDeflate = LibStub("LibDeflate")
LibStub("AceComm-3.0"):Embed(Comm)

Comm.PREFIX = "GFF"
-- Received messages above this (encoded) size are dropped unread.
Comm.MAX_MESSAGE_SIZE = 32 * 1024
-- Deliver own messages to the handlers too. The server echoes CHANNEL
-- messages back to the sender, so this allows testing with a single account.
Comm.loopback = false

-- One ChatThrottleLib priority for everything. CTL keeps a separate queue
-- per priority and interleaves them, but AceComm reassembles multipart
-- messages per prefix + distribution + sender only: two multipart messages
-- to the same receiver in different priorities got mixed up and arrived
-- undecodable. The only other sender, Comm.SendWhisper, stays ALERT: its
-- pings are single-part, which AceComm passes through without the spool.
local PRIO = "NORMAL"

local MAX_QUEUE = 100
local FLUSH_INTERVAL = 1
-- Peers one broadcast is whispered to.
Comm.FANOUT = 5

-- Set when the server rejected a channel message; Forever starts in
-- whisper mode right away.
local channelBlocked = false

local queue = {}
local ticker
local handlers = {}

function Comm.InLockdown()
	local check = C_ChatInfo.InChatMessagingLockdown
	return check ~= nil and check() and true or false
end

-- Forever doesn't let (veteran) trial accounts send addon messages at all;
-- receiving still works.
function Comm.IsRestricted()
	if not ns.Ads.IsForever() then
		return false
	end
	return (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) or false
end

function Comm.UsesWhisper()
	return channelBlocked or ns.Ads.IsForever()
end

function Comm.CanSend()
	if Comm.InLockdown() then
		return false
	end
	if Comm.UsesWhisper() then
		return ns.Channel.GetNumPeers() > 0
	end
	return ns.Channel.GetNumber() ~= nil
end

function Comm.GetQueueLength()
	return #queue
end

local function Transmit(entry)
	local callback = entry.callback
	local progress = callback and function(_, sent, total, didSend)
		callback(sent, total, didSend)
	end
	if not Comm.UsesWhisper() then
		Comm:SendCommMessage(Comm.PREFIX, entry.data, "CHANNEL", ns.Channel.GetNumber(), PRIO, progress)
		return
	end
	local targets = entry.target and { entry.target } or ns.Channel.PickPeers(Comm.FANOUT, entry.except)
	for i, target in ipairs(targets) do
		Comm:SendCommMessage(Comm.PREFIX, entry.data, "WHISPER", ns:WhisperTarget(target), PRIO, i == 1 and progress or nil)
	end
end

local function Flush()
	while queue[1] and Comm.CanSend() do
		Transmit(table.remove(queue, 1))
	end
	if not queue[1] and ticker then
		ticker:Cancel()
		ticker = nil
		ns:Fire("GFF_COMM_FLUSHED")
	end
end

-- Sends text to everyone in the channel. callback(sentBytes, totalBytes, didSend)
-- runs per transmitted chunk. Returns the encoded size and whether the
-- message was held for later; nothing on a restricted account.
-- options (whisper mode only): target = one recipient instead of random
-- peers, except = peer to leave out (the one a forwarded ad came from).
-- In channel mode everything is broadcast, so others can overhear answers.
function Comm.Send(text, callback, options)
	if Comm.IsRestricted() then
		return
	end
	local data = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(text))
	local entry = { data = data, callback = callback,
		target = options and options.target, except = options and options.except }
	if not queue[1] and (Comm.CanSend() or entry.target and Comm.UsesWhisper() and not Comm.InLockdown()) then
		Transmit(entry)
		return #data, false
	end
	if #queue >= MAX_QUEUE then
		table.remove(queue, 1)
	end
	queue[#queue + 1] = entry
	if not ticker then
		ticker = C_Timer.NewTicker(FLUSH_INTERVAL, Flush)
	end
	ns:Fire("GFF_COMM_HELD", #queue)
	return #data, true
end

-- Sends text to one player (whisper). Not queued: returns false when it
-- can't go out right now (lockdown, restricted account).
function Comm.SendWhisper(target, text)
	if Comm.InLockdown() or Comm.IsRestricted() then
		return false
	end
	local data = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(text))
	Comm:SendCommMessage(Comm.PREFIX, data, "WHISPER", ns:WhisperTarget(target), "ALERT")
	return true
end

-- handler(text, sender, distribution) receives every valid message of other
-- players (and own ones while Comm.loopback is set); distribution is
-- "CHANNEL" or "WHISPER".
function Comm.RegisterHandler(handler)
	handlers[#handlers + 1] = handler
end

local function IsSelf(sender)
	return sender == ns:GetPlayerFullName()
end

function Comm:OnCommReceived(_, data, distribution, sender)
	if distribution ~= "CHANNEL" and distribution ~= "WHISPER" then
		return
	end
	if issecretvalue and (issecretvalue(data) or issecretvalue(sender)) then
		return
	end
	if type(data) ~= "string" or type(sender) ~= "string" or #data > Comm.MAX_MESSAGE_SIZE then
		return
	end
	sender = ns:NormalizeName(sender)
	if IsSelf(sender) and not Comm.loopback then
		return
	end
	-- Whoever whispers us runs the addon: a peer for future broadcasts.
	if distribution == "WHISPER" and Comm.UsesWhisper() then
		ns.Channel.AddPeer(sender)
	end
	local decoded = LibDeflate:DecodeForWoWAddonChannel(data)
	local text = decoded and LibDeflate:DecompressDeflate(decoded)
	if type(text) ~= "string" then
		ns:Fire("GFF_COMM_INVALID", sender)
		return
	end
	for i = 1, #handlers do
		handlers[i](text, sender, distribution)
	end
end

Comm:RegisterComm(Comm.PREFIX)

ns.RegisterCallback(Comm, "GFF_CHANNEL_READY", Flush)
ns.RegisterCallback(Comm, "GFF_PEERS_CHANGED", function()
	if queue[1] and not ticker then
		ticker = C_Timer.NewTicker(FLUSH_INTERVAL, Flush)
	end
end)

ns.RegisterCallback(Comm, "GFF_CHANNEL_BLOCKED", function()
	if channelBlocked or ns.Ads.IsForever() then
		return
	end
	channelBlocked = true
	ns:Fire("GFF_COMM_WHISPER_MODE")
end)
