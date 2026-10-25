local _, ns = ...

-- Slash commands of the finder itself (/gff probe lives in Probe/).
local L = ns.L
local UI = ns.UI
local Store = ns.Store
local Sync = ns.Sync

ns.defaultCommand = UI.Toggle

ns:RegisterCommand("show", function()
	UI.Show()
end, "show", L.CMD_SHOW)

ns:RegisterCommand("ad", function()
	UI.Show(3)
end, "ad", L.CMD_AD)

ns:RegisterCommand("settings", function()
	ns:OpenSettings()
end, "settings", L.CMD_SETTINGS)

ns:RegisterCommand("sync", function()
	Sync.SendHello()
	ns:Print(L.CMD_SYNC_SENT)
end, "sync", L.CMD_SYNC)

ns:RegisterCommand("debug", function(arg)
	local settings = ns.db.settings
	if arg == "on" then
		settings.debug = true
	elseif arg == "off" then
		settings.debug = false
	else
		settings.debug = not settings.debug
	end
	ns:Print(settings.debug and L.DEBUG_ON or L.DEBUG_OFF)
end, "debug [on|off]", L.CMD_DEBUG)

ns:RegisterCommand("status", function()
	local live, total = Store.Count()
	ns:Print(L.CMD_STATUS_LINE, live, total - live, ns.Channel.ready and L.YES or L.NO,
		Sync.stats.received, Sync.stats.sent, Sync.stats.dropped, ns.Comm.GetQueueLength())
end, "status", L.CMD_STATUS)

ns:RegisterCommand("blocked", function()
	local any = false
	for key in pairs(ns.db.blocked) do
		any = true
		ns:Print("  %s", key)
	end
	if not any then
		ns:Print(L.CMD_BLOCKED_NONE)
	end
end, "blocked", L.CMD_BLOCKED)

ns:RegisterCommand("unblock", function(key)
	if key == "" then
		ns:Print("/gff unblock <%s>", L.CMD_UNBLOCK_ARG)
		return
	end
	-- Accept "Name" for "Name-Realm" and "Guild" for "G:Guild-Realm".
	local lowered = key:lower()
	for blockedKey in pairs(ns.db.blocked) do
		local k = blockedKey:lower()
		if k == lowered or k:match("^([^%-]+)%-") == lowered or k:match("^g:(.+)%-[^%-]+$") == lowered then
			Store.Unblock(blockedKey)
			ns:Print(L.CMD_UNBLOCKED, blockedKey)
			return
		end
	end
	ns:Print(L.CMD_UNBLOCK_UNKNOWN, key)
end, "unblock <name>", L.CMD_UNBLOCK)
