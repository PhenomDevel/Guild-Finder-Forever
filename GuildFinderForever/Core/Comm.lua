-- luacheck: read globals UnitName
local _, ns = ...

-- Transport for all addon traffic: compress + encode with LibDeflate, send via
-- AceComm over the hidden channel. Messages are held while the channel isn't
-- joined or chat messaging is locked down (encounters etc.) and sent
-- afterwards in order. ChatThrottleLib would drop them instead: it only
-- retries on AddonMessageThrottle, not on lockdown.
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

local MAX_QUEUE = 100
local FLUSH_INTERVAL = 1

local queue = {}
local ticker
local handlers = {}

function Comm.InLockdown()
	local check = C_ChatInfo.InChatMessagingLockdown
	return check ~= nil and check() and true or false
end

function Comm.CanSend()
	return ns.Channel.GetNumber() ~= nil and not Comm.InLockdown()
end

function Comm.GetQueueLength()
	return #queue
end

local function Transmit(entry)
	local callback = entry.callback
	Comm:SendCommMessage(Comm.PREFIX, entry.data, "CHANNEL", ns.Channel.GetNumber(), entry.prio, callback and function(_, sent, total, didSend)
		callback(sent, total, didSend)
	end)
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

-- Sends text to everyone in the channel. prio: ChatThrottleLib priority
-- ("BULK", "NORMAL", "ALERT"). callback(sentBytes, totalBytes, didSend)
-- runs per transmitted chunk. Returns the encoded size and whether the
-- message was held for later.
function Comm.Send(text, prio, callback)
	local data = LibDeflate:EncodeForWoWAddonChannel(LibDeflate:CompressDeflate(text))
	local entry = { data = data, prio = prio or "NORMAL", callback = callback }
	if not queue[1] and Comm.CanSend() then
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

-- handler(text, sender) receives every valid message of other players
-- (and own ones while Comm.loopback is set).
function Comm.RegisterHandler(handler)
	handlers[#handlers + 1] = handler
end

local function IsSelf(sender)
	return sender == ns:GetPlayerFullName() or sender == UnitName("player")
end

function Comm:OnCommReceived(_, data, distribution, sender)
	if distribution ~= "CHANNEL" then
		return
	end
	if issecretvalue and (issecretvalue(data) or issecretvalue(sender)) then
		return
	end
	if type(data) ~= "string" or type(sender) ~= "string" or #data > Comm.MAX_MESSAGE_SIZE or (IsSelf(sender) and not Comm.loopback) then
		return
	end
	local decoded = LibDeflate:DecodeForWoWAddonChannel(data)
	local text = decoded and LibDeflate:DecompressDeflate(decoded)
	if type(text) ~= "string" then
		ns:Fire("GFF_COMM_INVALID", sender)
		return
	end
	for i = 1, #handlers do
		handlers[i](text, sender)
	end
end

Comm:RegisterComm(Comm.PREFIX)

ns.RegisterCallback(Comm, "GFF_CHANNEL_READY", Flush)
