-- luacheck: read globals UnitName UnitLevel UnitFactionGroup GetGuildInfo GetNormalizedRealmName CanGuildInvite C_GuildInfo C_FriendList C_GameRules IsEncounterInProgress
local _, ns = ...

-- Phase 1 feasibility test (/gff probe): checks the hidden channel, raw and
-- AceComm messaging, reach, throttling, saved data and the lockdown in-game.
-- Raw tests call SendAddonMessage directly to see the bare result codes;
-- everything else goes through ns.Comm like the real addon will.
-- With loopback on (default), own messages are handled like those of another
-- player, so every test that only needs a sender and a receiver runs on a
-- single account. Test guide: docs/FEASIBILITY.md.

local Probe = {}
ns.Probe = Probe

local L = ns.L
local LibDeflate = LibStub("LibDeflate")

local PREFIX = "GFFProbe"
local SEP = "\t"
local LOG_SIZE = 300
-- Seconds without a further burst message before a burst is evaluated.
local BURST_QUIET = 5
local MAX_REPLY_DELAY = 3
local WHO_TIMEOUT = 10
local MAX_MESSAGE = 255
local ECHO_TIMEOUT = 5

ns.dbDefaults.probe = {
	loginCount = 0,
	loopback = true,
	log = {},
	filler = {},
}
ns.charDbDefaults.probe = {
	loginCount = 0,
}

local db, charDb

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function SafeString(value)
	if issecretvalue and issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

-- Every probe event is printed and kept in the saved log, so the results of
-- all accounts can be compared afterwards (WTF\…\SavedVariables).
-- Missing fields of malformed messages are logged as "?".
local function Log(text, ...)
	local count = select("#", ...)
	if count > 0 then
		local args = { ... }
		for i = 1, count do
			if args[i] == nil then
				args[i] = "?"
			end
		end
		text = text:format(unpack(args, 1, count))
	end
	if db then
		local log = db.log
		log[#log + 1] = date("%m-%d %H:%M:%S ") .. text
		while #log > LOG_SIZE do
			table.remove(log, 1)
		end
	end
	ns:Print(text)
end

local function ReverseLookup(enum, value)
	for name, enumValue in pairs(enum or {}) do
		if enumValue == value then
			return name
		end
	end
	return tostring(value)
end

-- Older clients returned a boolean, current ones Enum.SendAddonMessageResult.
local function ResultName(result)
	if result == true then
		return "Success"
	elseif result == false or result == nil then
		return tostring(result)
	end
	return ReverseLookup(Enum.SendAddonMessageResult, result)
end

local function IsSelf(sender)
	return sender == ns:GetPlayerFullName() or sender == UnitName("player")
end

local function GetRealm()
	return GetNormalizedRealmName() or "?"
end

local function GetFaction()
	return UnitFactionGroup("player") or "?"
end

local function GetGuild()
	return GetGuildInfo("player") or "-"
end

local function YesNo(value)
	return value and L.YES or L.NO
end

local function SendRaw(...)
	local number = ns.Channel.GetNumber()
	if not number then
		return "NoChannel"
	end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, table.concat({ ... }, SEP), "CHANNEL", number)
	if not ok then
		return "Error: " .. tostring(result)
	end
	return ResultName(result)
end

local function LockdownSuffix()
	return ns.Comm.InLockdown() and L.PROBE_IN_LOCKDOWN or ""
end

-- Deterministic ad-like text that compresses about as well as real ads.
local WORDS = {
	"raid", "guild", "casual", "evenings", "weekend", "heroic", "leveling",
	"pvp", "social", "tank", "healer", "damage", "german", "english",
	"friendly", "progress", "dungeon", "alliance", "horde", "hardcore",
}

local function MakeSampleText(length, seed)
	seed = seed or 1
	local parts, size = {}, 0
	while size < length do
		seed = (seed * 16807) % 2147483647
		local word = WORDS[seed % #WORDS + 1]
		if seed % 7 == 0 then
			word = word .. (seed % 1000)
		end
		parts[#parts + 1] = word
		size = size + #word + 1
	end
	return table.concat(parts, " "):sub(1, length)
end

local prefixResult = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
prefixResult = type(prefixResult) == "number" and ReverseLookup(Enum.RegisterAddonMessagePrefixResult, prefixResult) or tostring(prefixResult)

--------------------------------------------------------------------------------
-- Received raw messages
--------------------------------------------------------------------------------

local rawHandlers = {}
local bursts = {}
local awaitingEcho = {}

-- PING id sentTime realm faction level guild
function rawHandlers.PING(sender, isSelf, id, sentTime, realm, faction, level, guild)
	if IsSelf(sender) then
		awaitingEcho[tostring(id)] = nil
		Log(L.PROBE_ECHO, id)
		if isSelf then
			return
		end
	end
	local delay = GetServerTime() - (tonumber(sentTime) or 0)
	Log(L.PROBE_PING_RECEIVED, sender, realm, faction, level, guild, delay)
	C_Timer.After(math.random() * MAX_REPLY_DELAY, function()
		local result = SendRaw("PONG", id, sender, GetRealm(), GetFaction())
		if result ~= "Success" then
			Log(L.PROBE_PONG_FAILED, sender, result)
		end
	end)
end

-- PONG id target realm faction
function rawHandlers.PONG(sender, isSelf, id, target, realm, faction)
	if not isSelf and IsSelf(target) then
		Log(L.PROBE_PONG_RECEIVED, sender, realm, faction, id)
	end
end

local function EvaluateBurst(key, sender, id)
	local burst = bursts[key]
	bursts[key] = nil
	Log(L.PROBE_BURST_RECEIVED, sender, id, burst.received, burst.count, burst.last - burst.first)
	SendRaw("BURSTACK", id, sender, burst.received, burst.count)
end

-- BURST id seq count padding
function rawHandlers.BURST(sender, isSelf, id, seq, count)
	if isSelf then
		return
	end
	local key = sender .. ":" .. tostring(id)
	local burst = bursts[key]
	if not burst then
		burst = { count = tonumber(count) or 0, received = 0, seen = {}, first = GetTime() }
		bursts[key] = burst
	end
	if not burst.seen[seq] then
		burst.seen[seq] = true
		burst.received = burst.received + 1
	end
	burst.last = GetTime()
	if burst.timer then
		burst.timer:Cancel()
	end
	burst.timer = C_Timer.NewTimer(BURST_QUIET, function()
		EvaluateBurst(key, sender, id)
	end)
end

-- BURSTACK id target received count
function rawHandlers.BURSTACK(sender, isSelf, id, target, received, count)
	if not isSelf and IsSelf(target) then
		Log(L.PROBE_BURST_ACK, sender, id, received, count)
	end
end

-- BIGACK id target ok
function rawHandlers.BIGACK(sender, isSelf, id, target, ok)
	if not isSelf and IsSelf(target) then
		Log(L.PROBE_BIG_ACK, sender, id, ok == "1" and L.PROBE_INTACT or L.PROBE_DAMAGED)
	end
end

local secretSeen = false

ns:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
	if issecretvalue and (issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender) or issecretvalue(channel)) then
		if not secretSeen then
			secretSeen = true
			Log(L.PROBE_SECRET_MESSAGE)
		end
		return
	end
	if prefix ~= PREFIX or channel ~= "CHANNEL" or type(text) ~= "string" then
		return
	end
	local fields = { strsplit(SEP, text) }
	local handler = rawHandlers[fields[1]]
	if handler then
		-- isSelf: own message to be ignored (false for own ones in loopback).
		handler(sender, IsSelf(sender) and not ns.Comm.loopback, unpack(fields, 2))
	end
end)

--------------------------------------------------------------------------------
-- Received AceComm messages (via ns.Comm)
--------------------------------------------------------------------------------

ns.Comm.RegisterHandler(function(text, sender)
	local header, body = text:match("^([^\n]*)\n(.*)$")
	if not header then
		return
	end
	local kind, id, a, b, c = strsplit(SEP, header)
	if kind == "BIG" then
		-- BIG id length adler32 sentTime \n data
		local ok = #body == tonumber(a) and LibDeflate:Adler32(body) == tonumber(b)
		Log(L.PROBE_BIG_RECEIVED, sender, id, #body, ok and L.PROBE_INTACT or L.PROBE_DAMAGED, GetServerTime() - (tonumber(c) or 0))
		SendRaw("BIGACK", id, sender, ok and "1" or "0")
	elseif kind == "Q" then
		-- Q id createdTime \n
		Log(L.PROBE_QUEUED_RECEIVED, sender, id, GetServerTime() - (tonumber(a) or 0))
	end
end)

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local commands = {}
local order = {}
local nextId = 0

local function AddCommand(name, usage, description, handler)
	order[#order + 1] = name
	commands[name] = { usage = usage, description = description, handler = handler }
end

local function NextId()
	nextId = nextId + 1
	return nextId
end

local function StatusLine(label, value, ...)
	if select("#", ...) > 0 then
		value = value:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage(("  |cffffd100%s:|r %s"):format(label, tostring(value)))
end

local function GetGameMode()
	if not (C_GameRules and C_GameRules.GetActiveGameMode) then
		return "-"
	end
	local ok, mode = pcall(C_GameRules.GetActiveGameMode)
	return ok and ReverseLookup(Enum.GameMode, mode) or "-"
end

local function CanInvite()
	local check = C_GuildInfo and C_GuildInfo.CanGuildInvite or CanGuildInvite
	if not check then
		return "-"
	end
	local ok, result = pcall(check)
	return ok and YesNo(result) or "-"
end

AddCommand("status", "status", L.PROBE_HELP_STATUS, function()
	local _, build, _, interface = GetBuildInfo()
	local number = ns.Channel.GetNumber()
	ns:Print(L.PROBE_STATUS_HEADER)
	StatusLine(L.PROBE_STATUS_VERSION, "%s, interface %s, build %s", ns.version, tostring(interface), tostring(build))
	StatusLine(L.PROBE_STATUS_PLAYER, "%s, %s, %s %d", ns:GetPlayerFullName() or "?", GetFaction(), L.PROBE_LEVEL, UnitLevel("player"))
	StatusLine(L.PROBE_STATUS_GUILD, "%s (%s: %s)", GetGuild(), L.PROBE_CAN_INVITE, CanInvite())
	StatusLine(L.PROBE_STATUS_GAME_MODE, GetGameMode())
	StatusLine(L.PROBE_STATUS_SERVER_TIME, "%d (%s)", GetServerTime(), date("%Y-%m-%d %H:%M:%S", GetServerTime()))
	StatusLine(L.PROBE_STATUS_CHANNEL, number and ("%s #%d, %s"):format(ns.Channel.NAME, number, ns.Channel.hidden and L.PROBE_HIDDEN or L.PROBE_VISIBLE) or L.PROBE_NOT_JOINED)
	StatusLine(L.PROBE_STATUS_LOCKDOWN, "%s (%s: %s, %s: %s)", YesNo(ns.Comm.InLockdown()), "API", YesNo(C_ChatInfo.InChatMessagingLockdown), L.PROBE_ENCOUNTER, YesNo(IsEncounterInProgress and IsEncounterInProgress()))
	StatusLine(L.PROBE_STATUS_QUEUE, ns.Comm.GetQueueLength())
	StatusLine(L.PROBE_STATUS_LOOPBACK, YesNo(ns.Comm.loopback))
	StatusLine("API", "prefix %s, chat frame %s, chat filter %s, SendWho %s", tostring(prefixResult), ns.Channel.GetChatFrameApi(), YesNo(ns.Channel.hasChatFilter), YesNo(C_FriendList and C_FriendList.SendWho))
	StatusLine(L.PROBE_STATUS_SAVED, L.PROBE_SAVED_SUMMARY, db.loginCount, charDb.loginCount, #db.filler, #db.log)
end)

AddCommand("ping", "ping", L.PROBE_HELP_PING, function()
	local id = NextId()
	local result = SendRaw("PING", id, GetServerTime(), GetRealm(), GetFaction(), UnitLevel("player"), GetGuild())
	Log(L.PROBE_PING_SENT, id, result, LockdownSuffix())
	if result == "Success" then
		local key = tostring(id)
		awaitingEcho[key] = true
		C_Timer.After(ECHO_TIMEOUT, function()
			if awaitingEcho[key] then
				awaitingEcho[key] = nil
				Log(L.PROBE_NO_ECHO, id, ECHO_TIMEOUT)
			end
		end)
	end
end)

AddCommand("burst", "burst [count] [bytes]", L.PROBE_HELP_BURST, function(args)
	local count, size = args:match("^(%d*)%s*(%d*)$")
	count = math.min(tonumber(count) or 20, 200)
	size = math.min(tonumber(size) or 200, MAX_MESSAGE)
	local id = NextId()
	local results, resultOrder = {}, {}
	for seq = 1, count do
		local header = table.concat({ "BURST", id, seq, count, "" }, SEP)
		local result = SendRaw("BURST", id, seq, count, ("x"):rep(math.max(size - #header, 0)))
		if not results[result] then
			results[result] = 0
			resultOrder[#resultOrder + 1] = result
		end
		results[result] = results[result] + 1
	end
	local summary = {}
	for _, result in ipairs(resultOrder) do
		summary[#summary + 1] = ("%s=%d"):format(result, results[result])
	end
	Log(L.PROBE_BURST_SENT, id, count, size, table.concat(summary, ", "))
end)

AddCommand("big", "big [KB]", L.PROBE_HELP_BIG, function(args)
	local kb = math.min(math.max(tonumber(args) or 4, 1), 24)
	local id = NextId()
	local data = MakeSampleText(kb * 1024, id)
	local text = table.concat({ "BIG", id, #data, LibDeflate:Adler32(data), GetServerTime() }, SEP) .. "\n" .. data
	-- Includes the time the message was held, if it was.
	local started = GetTime()
	local failed = false
	local size, held = ns.Comm.Send(text, "BULK", function(sent, total, didSend)
		if not failed and not didSend then
			failed = true
			Log(L.PROBE_BIG_CHUNK_FAILED, id, sent, total)
		end
		if sent >= total then
			Log(L.PROBE_BIG_DONE, id, total, GetTime() - started)
		end
	end)
	Log(L.PROBE_BIG_SENT, id, #data, size, math.ceil(size / (MAX_MESSAGE - 1)), held and L.PROBE_HELD or "")
end)

local function SendQueued()
	local id = NextId()
	local _, held = ns.Comm.Send(table.concat({ "Q", id, GetServerTime() }, SEP) .. "\n")
	Log(L.PROBE_QUEUED_SENT, id, held and L.PROBE_HELD or "")
end

AddCommand("queue", "queue", L.PROBE_HELP_QUEUE, SendQueued)

local autoTicker

AddCommand("auto", "auto [seconds|off]", L.PROBE_HELP_AUTO, function(args)
	if autoTicker then
		autoTicker:Cancel()
		autoTicker = nil
	end
	if args == "off" then
		Log(L.PROBE_AUTO_OFF)
		return
	end
	local interval = math.max(tonumber(args) or 20, 5)
	autoTicker = C_Timer.NewTicker(interval, function()
		commands.ping.handler("")
		SendQueued()
	end)
	Log(L.PROBE_AUTO_ON, interval)
end)

local whoSent

AddCommand("who", "who <name>", L.PROBE_HELP_WHO, function(name)
	if name == "" then
		ns:Print("/gff probe who <name>")
		return
	end
	whoSent = GetTime()
	local ok, err = pcall(C_FriendList.SendWho, ('n-"%s"'):format(name))
	Log(L.PROBE_WHO_SENT, name, ok and "ok" or tostring(err))
end)

AddCommand("loopback", "loopback [on|off]", L.PROBE_HELP_LOOPBACK, function(args)
	local enabled
	if args == "on" then
		enabled = true
	elseif args == "off" then
		enabled = false
	else
		enabled = not ns.Comm.loopback
	end
	db.loopback = enabled
	ns.Comm.loopback = enabled
	Log(enabled and L.PROBE_LOOPBACK_ON or L.PROBE_LOOPBACK_OFF)
end)

AddCommand("join", "join", L.PROBE_HELP_JOIN, function()
	ns.Channel.Join()
end)

AddCommand("leave", "leave", L.PROBE_HELP_LEAVE, function()
	ns.Channel.Leave()
end)

AddCommand("show", "show | hide", L.PROBE_HELP_SHOW, function()
	ns.Channel.SetHidden(false)
	Log(L.PROBE_CHANNEL_SHOWN)
end)

commands.hide = {
	handler = function()
		ns.Channel.SetHidden(true)
		Log(L.PROBE_CHANNEL_HIDDEN)
	end,
}

AddCommand("fill", "fill <count>", L.PROBE_HELP_FILL, function(args)
	local count = math.min(tonumber(args) or 0, 5000)
	wipe(db.filler)
	for i = 1, count do
		db.filler[i] = { id = i, version = GetServerTime(), text = MakeSampleText(400, i) }
	end
	Log(L.PROBE_FILLED, count)
end)

AddCommand("log", "log [lines]", L.PROBE_HELP_LOG, function(args)
	local log = db.log
	local count = math.min(tonumber(args) or 20, #log)
	for i = #log - count + 1, #log do
		DEFAULT_CHAT_FRAME:AddMessage("  " .. log[i])
	end
end)

AddCommand("clear", "clear", L.PROBE_HELP_CLEAR, function()
	wipe(db.log)
	ns:Print(L.PROBE_LOG_CLEARED)
end)

ns:RegisterCommand("probe", function(args)
	local name, rest = args:match("^(%S*)%s*(.-)$")
	local command = commands[name:lower()]
	if command then
		command.handler(rest)
		return
	end
	ns:Print(L.PROBE_HELP_HEADER)
	for _, commandName in ipairs(order) do
		local entry = commands[commandName]
		DEFAULT_CHAT_FRAME:AddMessage(("  |cffffd100/gff probe %s|r – %s"):format(entry.usage, entry.description))
	end
end, "probe <command>", L.PROBE_HELP)

--------------------------------------------------------------------------------
-- Observers
--------------------------------------------------------------------------------

ns:RegisterEvent("WHO_LIST_UPDATE", function()
	if not whoSent or GetTime() - whoSent > WHO_TIMEOUT then
		return
	end
	whoSent = nil
	local shown, total = C_FriendList.GetNumWhoResults()
	Log(L.PROBE_WHO_RESULTS, shown or 0, total or 0)
	for i = 1, math.min(shown or 0, 5) do
		local info = C_FriendList.GetWhoInfo(i)
		if info then
			Log("  %s, %s, %s %s, %s", SafeString(info.fullName), SafeString(info.fullGuildName), L.PROBE_LEVEL, SafeString(info.level), SafeString(info.area))
		end
	end
end)

-- Few /who results are printed to chat instead of WHO_LIST_UPDATE.
ns:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text)
	if whoSent and GetTime() - whoSent <= WHO_TIMEOUT then
		Log(L.PROBE_WHO_SYSTEM, SafeString(text))
	end
end)

ns.RegisterCallback(Probe, "GFF_CHANNEL_READY", function(_, number)
	Log(L.PROBE_CHANNEL_READY, ns.Channel.NAME, tostring(number))
end)

ns.RegisterCallback(Probe, "GFF_CHANNEL_FAILED", function()
	Log(L.PROBE_CHANNEL_FAILED, ns.Channel.NAME)
end)

ns.RegisterCallback(Probe, "GFF_CHANNEL_NOTICE", function(_, notice)
	Log(L.PROBE_CHANNEL_NOTICE, SafeString(notice))
end)

ns.RegisterCallback(Probe, "GFF_COMM_HELD", function(_, length)
	Log(L.PROBE_COMM_HELD, length)
end)

ns.RegisterCallback(Probe, "GFF_COMM_FLUSHED", function()
	Log(L.PROBE_COMM_FLUSHED)
end)

ns.RegisterCallback(Probe, "GFF_COMM_INVALID", function(_, sender)
	Log(L.PROBE_COMM_INVALID, sender)
end)

ns:RegisterEvent("ENCOUNTER_START", function(_, _, encounterName)
	Log(L.PROBE_ENCOUNTER_START, SafeString(encounterName), YesNo(ns.Comm.InLockdown()))
end)

ns:RegisterEvent("ENCOUNTER_END", function(_, _, encounterName)
	Log(L.PROBE_ENCOUNTER_END, SafeString(encounterName), YesNo(ns.Comm.InLockdown()))
end)

-- Lockdown has no event we rely on; poll and log transitions.
local wasLockdown = false
C_Timer.NewTicker(1, function()
	local lockdown = ns.Comm.InLockdown()
	if lockdown ~= wasLockdown then
		wasLockdown = lockdown
		Log(lockdown and L.PROBE_LOCKDOWN_START or L.PROBE_LOCKDOWN_END)
	end
end)

--------------------------------------------------------------------------------
-- Saved data check
--------------------------------------------------------------------------------

ns:RegisterEvent("PLAYER_LOGIN", function()
	db = ns.db.probe
	charDb = ns.charDb.probe
	ns.Comm.loopback = db.loopback
	db.loginCount = db.loginCount + 1
	charDb.loginCount = charDb.loginCount + 1
	local lastLogout = db.lastLogout and date("%Y-%m-%d %H:%M:%S", db.lastLogout) or L.PROBE_NEVER
	Log(L.PROBE_SAVED_LOGIN, db.loginCount, charDb.loginCount, lastLogout, #db.filler)
	if ns.dbLoaded ~= ns.charDbLoaded then
		Log(L.PROBE_SAVED_MISMATCH, YesNo(ns.dbLoaded), YesNo(ns.charDbLoaded))
	elseif not ns.dbLoaded then
		Log(L.PROBE_SAVED_NONE)
	end
end)

ns:RegisterEvent("PLAYER_LOGOUT", function()
	if db then
		db.lastLogout = time()
		charDb.lastLogout = time()
	end
end)
