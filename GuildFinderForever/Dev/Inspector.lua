-- luacheck: read globals CreateScrollBoxListLinearView ScrollUtil CreateDataProvider GameTooltip GetNormalizedRealmName
local _, ns = ...

-- Data inspector tab (development checkouts only, see Dev.lua): everything
-- the addon holds, saved and in memory, as a filterable text tree with every
-- timestamp spelled out. Times are local time, plus the distance to now.
local L = ns.L
local UI = ns.UI
local W = ns.Widgets
local C = ns.Constants
local Ads = ns.Ads
local Store = ns.Store

local TAB_INDEX = 6
local ROW_HEIGHT = 15
local INDENT = 14
-- Numbers in this range are shown as dates (server time, 2017–2049).
local STAMP_MIN, STAMP_MAX = 1.5e9, 2.5e9

local LABEL = "|cff9d9d9d%s:|r %s"
local FLAG_COLORS = {
	OWN = "ff40c0ff", TEST = "ffb070ff", DELETED = "ffff4040", EXPIRED = "ffff4040",
	OUTDATED = "ffff9933", REMOVED = "ffff6020", HIDDEN = "ffa0a0a0", BLOCKED = "ffff4040",
	SUSPICIOUS = "ffff4040", VERIFIED = "ff20ff20",
}

--------------------------------------------------------------------------------
-- Session trace
--------------------------------------------------------------------------------

-- [id] = { at, from, state } of the last copy the sync handed over;
-- [id] = server time of the last cache change. This session only.
local received, changed = {}, {}

ns.Sync.OnAdTrace = function(ad, sender, state)
	received[ad.i] = { at = GetServerTime(), from = sender, state = state }
end

ns.RegisterCallback(received, "GFF_ADS_CHANGED", function(_, id)
	if id then
		changed[id] = GetServerTime()
	end
end)

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

local function Span(seconds)
	seconds = math.floor(math.abs(seconds))
	if seconds < 60 then
		return seconds .. "s"
	elseif seconds < 3600 then
		return ("%dm %ds"):format(math.floor(seconds / 60), seconds % 60)
	elseif seconds < 86400 then
		return ("%dh %dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end
	return ("%dd %dh"):format(math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600))
end

-- Server time as "2026-11-17 22:39:15 (3h 12m ago)".
local function Stamp(t)
	if type(t) ~= "number" then
		return "|cff9d9d9d–|r"
	end
	local delta = GetServerTime() - t
	local relative = delta >= 0 and (Span(delta) .. " ago") or ("in " .. Span(delta))
	return ("%s |cff9d9d9d(%s)|r"):format(date("%Y-%m-%d %H:%M:%S", t), relative)
end

-- GetTime() value (session clock) as a server time stamp.
local function SessionStamp(at)
	if type(at) ~= "number" then
		return Stamp(nil)
	end
	return Stamp(GetServerTime() - math.floor(GetTime() - at + 0.5))
end

-- Received strings may hold escape sequences: shown literally.
local function Escape(text)
	return (tostring(text):gsub("|", "||"):gsub("[\r\n]+", " / "))
end

local function Value(value)
	if type(value) == "number" and value >= STAMP_MIN and value <= STAMP_MAX and value % 1 == 0 then
		return value .. "  " .. Stamp(value)
	elseif type(value) == "string" then
		return '"' .. Escape(value) .. '"'
	end
	return Escape(value)
end

local function SortedKeys(tbl)
	local keys = {}
	for key in pairs(tbl) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then
			return a < b
		end
		return type(a) < type(b)
	end)
	return keys
end

-- Generic dump of a table into lines ({ text, depth }).
local function Dump(lines, tbl, depth, seen)
	seen = seen or {}
	if seen[tbl] then
		lines[#lines + 1] = { "|cffff4040<cycle>|r", depth }
		return
	end
	seen[tbl] = true
	local keys = SortedKeys(tbl)
	if not keys[1] then
		lines[#lines + 1] = { "|cff9d9d9d{}|r", depth }
	end
	for _, key in ipairs(keys) do
		local value = tbl[key]
		if type(value) == "table" then
			lines[#lines + 1] = { LABEL:format(Escape(key), next(value) and "" or "{}"), depth }
			if next(value) then
				Dump(lines, value, depth + 1, seen)
			end
		else
			lines[#lines + 1] = { LABEL:format(Escape(key), Value(value)), depth }
		end
	end
end

local function Line(lines, label, text, depth)
	lines[#lines + 1] = { LABEL:format(label, text), depth or 1 }
end

local function YesNo(value)
	if value == nil then
		return "|cff9d9d9dunknown|r"
	end
	return value and "|cff20ff20yes|r" or "|cffff4040no|r"
end

--------------------------------------------------------------------------------
-- Sections: each returns a list of blocks { title, lines }
--------------------------------------------------------------------------------

local function Flags(ad, now)
	local mine = ad.o ~= nil and ad.o == ns:GetPlayerFullName()
	local check = Store.GetCheck(ad.i)
	local flags = {}
	local function Add(flag, on)
		if on then
			flags[#flags + 1] = "|c" .. FLAG_COLORS[flag] .. flag .. "|r"
		end
	end
	Add("OWN", mine)
	Add("TEST", Store.IsTestAd(ad.i))
	Add("DELETED", ad.d)
	Add("EXPIRED", Ads.IsExpired(ad, now))
	Add("REMOVED", not ad.d and Ads.IsRemoved(ad, now))
	Add("OUTDATED", not ad.d and not Ads.IsRemoved(ad, now) and Ads.IsStale(ad, now))
	Add("HIDDEN", Store.IsHidden(ad.i))
	Add("BLOCKED", Store.IsBlocked(ad))
	Add("SUSPICIOUS", check and check.suspicious)
	Add("VERIFIED", check and check.verified)
	return table.concat(flags, " ")
end

local function AdBlock(ad, now)
	local Presence = ns.Presence
	local lines = {}
	local mine = ad.o ~= nil and ad.o == ns:GetPlayerFullName()
	Line(lines, "id", Escape(ad.i))
	Line(lines, "owner", Escape(ad.o))
	Line(lines, "version (posted)", Stamp(ad.v))
	Line(lines, "expires (cache drops it)", Stamp((ad.v or 0) + C.AD_LIFETIME))
	if not ad.d then
		local seen = Presence.LastSeen(ad.o)
		local sign = Ads.LastSign(ad)
		Line(lines, "last sign of life", Stamp(sign) .. ((seen and seen > (ad.v or 0)) and "  · poster seen" or "  · ad version"))
		if mine then
			Line(lines, "outdated / removed", "never (own ad)")
		else
			Line(lines, "outdated from", Stamp(sign + Ads.GetStaleDays() * C.DAY))
			Line(lines, "removed from lists", Stamp(sign + Ads.GetRemoveDays() * C.DAY))
		end
		Line(lines, "poster last seen online", Stamp(seen))
		Line(lines, "poster online now", YesNo(Presence.IsOnline(ad.o)))
		local guildEntry = ns.db.posterGuilds[(Ads.OwnerName(ad.o) or ""):lower()]
		if guildEntry then
			Line(lines, "poster seen in guild", ("<%s>  %s"):format(Escape(guildEntry.g), Stamp(guildEntry.at)))
		end
	end
	local check = Store.GetCheck(ad.i)
	if check then
		Line(lines, "poster check", (check.verified and "verified" or "suspicious") .. "  " .. Stamp(check.checked))
	end
	local blocked = ns.db.blocked[Store.BlockKey(ad)] or ns.db.blocked[ad.o]
	if blocked then
		Line(lines, "blocked", Stamp(blocked))
	end
	local trace = received[ad.i]
	if trace then
		Line(lines, "last received", ("%s from %s (%s)"):format(Stamp(trace.at), Escape(trace.from), trace.state))
	end
	if changed[ad.i] then
		Line(lines, "cache changed", Stamp(changed[ad.i]))
	end
	Line(lines, "sync bucket", Store.BucketOf(ad.i))
	lines[#lines + 1] = { "|cff9d9d9dfields:|r", 1 }
	Dump(lines, ad, 2)

	local label
	if ad.k == Ads.KIND_GUILD then
		label = ("|cffffd100[G]|r <%s>"):format(Escape(ad.n or Ads.OwnerName(ad.o) or "?"))
	else
		local class = ad.c and ("|c%s%s|r"):format(W.ClassColorHex(ad.c), ad.c) or ""
		label = ("|cffffd100[P]|r %s %s %s"):format(Escape(Ads.OwnerName(ad.o) or "?"), class, ad.lv or "")
	end
	return { title = label .. "  " .. Flags(ad, now), lines = lines, sort = ad.v or 0 }
end

local function AdsSection()
	local now = GetServerTime()
	local cache, test = Store.GetRaw()
	local blocks = {}
	for _, source in ipairs({ cache, test }) do
		for _, ad in pairs(source) do
			blocks[#blocks + 1] = AdBlock(ad, now)
		end
	end
	table.sort(blocks, function(a, b)
		return a.sort > b.sort
	end)
	local live, total = Store.Count()
	local guilds, players = Store.CountByKind()
	local settings = {}
	Line(settings, "cache entries", ("%d (%d not withdrawn), limit %d"):format(total, live, Store.MAX_ADS))
	Line(settings, "live guild / player ads", ("%d / %d"):format(guilds, players))
	Line(settings, "outdated after / removed after", ("%d d / %d d"):format(Ads.GetStaleDays(), Ads.GetRemoveDays()))
	Line(settings, "ad lifetime", Span(C.AD_LIFETIME))
	Line(settings, "own player / guild ad id", ("%s / %s"):format(Escape(Ads.GetOwnPlayerAdId() or "–"),
		Escape(Ads.GetOwnGuildAdId() or "–")))
	table.insert(blocks, 1, { title = "|cffffd100Overview|r", lines = settings })
	return blocks
end

local function PostersSection()
	local states, pending, queue = ns.Presence.GetDebugState()
	local seen, guilds = ns.db.posterSeen, ns.db.posterGuilds
	local keys = {}
	for _, source in ipairs({ seen, guilds, states, pending }) do
		for key in pairs(source) do
			keys[key] = true
		end
	end
	local blocks = {}
	for key in pairs(keys) do
		local lines = {}
		Line(lines, "last seen online (saved)", Stamp(seen[key]))
		local guild = guilds[key]
		if guild then
			Line(lines, "guild (saved)", ("<%s>  %s"):format(Escape(guild.g), Stamp(guild.at)))
		end
		local state = states[key]
		if state then
			Line(lines, "session state", (state.online and "online" or "offline") .. "  " .. SessionStamp(state.at))
		end
		Line(lines, "online now", YesNo(ns.Presence.IsOnline(key)))
		if pending[key] then
			Line(lines, "ping pending since", SessionStamp(pending[key]))
		end
		blocks[#blocks + 1] = { title = Escape(key), lines = lines, sort = seen[key] or 0 }
	end
	table.sort(blocks, function(a, b)
		return a.sort > b.sort
	end)
	local overview = {}
	Line(overview, "posters", #blocks)
	local queued = {}
	for i, owner in ipairs(queue) do
		queued[i] = Escape(owner)
	end
	Line(overview, "ping queue", #queue > 0 and table.concat(queued, ", ") or "empty")
	table.insert(blocks, 1, { title = "|cffffd100Overview|r", lines = overview })
	return blocks
end

local function PeersSection()
	local Channel = ns.Channel
	local blocks = {}
	local overview = {}
	Line(overview, "channel", ("%s, #%s, ready %s, hidden %s"):format(Channel.NAME, tostring(Channel.GetNumber() or "–"),
		YesNo(Channel.ready), YesNo(Channel.hidden)))
	Line(overview, "members this session", Channel.GetNumPeers())
	blocks[1] = { title = "|cffffd100Overview|r", lines = overview }

	local current = {}
	for _, name in ipairs(SortedKeys(Channel.GetPeers())) do
		current[#current + 1] = { Escape(name), 1 }
	end
	if not current[1] then
		current[1] = { "|cff9d9d9dnone|r", 1 }
	end
	blocks[2] = { title = "|cffffd100Members this session|r", lines = current }

	local own = GetNormalizedRealmName()
	for realm, known in pairs(ns.db.knownPeers) do
		if type(known) == "table" then
			local list = {}
			for name, at in pairs(known) do
				list[#list + 1] = { name = name, at = at }
			end
			table.sort(list, function(a, b)
				return (tonumber(a.at) or 0) > (tonumber(b.at) or 0)
			end)
			local lines = {}
			for _, entry in ipairs(list) do
				Line(lines, Escape(entry.name), Stamp(tonumber(entry.at)))
			end
			blocks[#blocks + 1] = {
				title = ("|cffffd100Remembered on %s|r%s (%d)"):format(Escape(realm), realm == own and " · own realm" or "", #list),
				lines = lines,
			}
		end
	end
	return blocks
end

local function SyncSection()
	local Sync, Comm, Channel = ns.Sync, ns.Comm, ns.Channel
	local versions, hellos = Sync.GetDebugState()

	local client = {}
	local _, build, _, interface = GetBuildInfo()
	Line(client, "addon version", Escape(ns.version))
	Line(client, "client", ("%s (%s), Forever %s"):format(tostring(interface), tostring(build), YesNo(Ads.IsForever())))
	Line(client, "game mode", Escape(Ads.GetGameModeName() or "–"))
	Line(client, "player", Escape(ns:GetPlayerFullName() or "–"))
	Line(client, "faction / realm", ("%s / %s"):format(tostring(Ads.GetFactionCode()), Escape(Ads.GetRealm() or "–")))
	Line(client, "guild", Escape(Ads.GetGuild() or "–"))
	Line(client, "now (server time)", Stamp(GetServerTime()))

	local sync = {}
	Line(sync, "last sync", Stamp(Sync.lastSync))
	Line(sync, "messages received / sent / dropped", ("%d / %d / %d"):format(Sync.stats.received, Sync.stats.sent,
		Sync.stats.dropped))
	local nonces = SortedKeys(hellos)
	Line(sync, "open hellos", #nonces > 0 and table.concat(nonces, ", ") or "none")
	local buckets = Store.GetBuckets()
	for i = 1, Store.NUM_BUCKETS do
		Line(sync, "bucket " .. i, tostring(buckets[i]), 2)
	end

	local comm = {}
	Line(comm, "whisper mode", YesNo(Comm.UsesWhisper()))
	Line(comm, "can send", YesNo(Comm.CanSend()))
	Line(comm, "chat lockdown", YesNo(Comm.InLockdown()))
	Line(comm, "trial restricted", YesNo(Comm.IsRestricted()))
	Line(comm, "send queue", Comm.GetQueueLength())
	Line(comm, "fan-out", Comm.FANOUT)
	Line(comm, "loopback", YesNo(Comm.loopback))
	Line(comm, "channel members", Channel.GetNumPeers())

	local peers = {}
	for _, sender in ipairs(SortedKeys(versions)) do
		Line(peers, Escape(sender), Escape(versions[sender]))
	end
	if not peers[1] then
		peers[1] = { "|cff9d9d9dnone yet|r", 1 }
	end

	return {
		{ title = "|cffffd100Client|r", lines = client },
		{ title = "|cffffd100Sync|r", lines = sync },
		{ title = "|cffffd100Comm|r", lines = comm },
		{ title = "|cffffd100Addon versions seen this session|r", lines = peers },
	}
end

-- Saved variables, minus what the other sections already show.
local SHOWN_ELSEWHERE = { ads = "Ads", posterSeen = "Posters", posterGuilds = "Posters", knownPeers = "Peers" }

local function SavedSection()
	local account = {}
	for _, key in ipairs(SortedKeys(ns.db)) do
		local value = ns.db[key]
		if SHOWN_ELSEWHERE[key] then
			Line(account, Escape(key), ("|cff9d9d9dsee %s|r"):format(SHOWN_ELSEWHERE[key]))
		elseif type(value) == "table" then
			Line(account, Escape(key), next(value) and "" or "{}")
			if next(value) then
				Dump(account, value, 2)
			end
		else
			Line(account, Escape(key), Value(value))
		end
	end
	local character = {}
	Dump(character, ns.charDb, 1)
	return {
		{ title = ("|cffffd100GuildFinderForeverDB|r (account, loaded %s)"):format(YesNo(ns.dbLoaded)), lines = account },
		{ title = ("|cffffd100GuildFinderForeverCharDB|r (character, loaded %s)"):format(YesNo(ns.charDbLoaded)), lines = character },
	}
end

local SECTIONS = {
	{ label = "DEV_ADS", build = AdsSection },
	{ label = "DEV_POSTERS", build = PostersSection },
	{ label = "DEV_PEERS", build = PeersSection },
	{ label = "DEV_SYNC", build = SyncSection },
	{ label = "DEV_SAVED", build = SavedSection },
}

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

local function Matches(block, needle)
	if needle == "" then
		return true
	end
	if block.title:lower():find(needle, 1, true) then
		return true
	end
	for _, line in ipairs(block.lines) do
		if line[1]:lower():find(needle, 1, true) then
			return true
		end
	end
	return false
end

local function Build(content)
	local tab = { section = 1, filter = "" }

	local buttons = {}
	local previous
	for i, section in ipairs(SECTIONS) do
		local button = W.Button(content, L[section.label], nil, function()
			tab.section = i
			tab:Refresh()
		end)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		else
			button:SetPoint("TOPLEFT", 8, -8)
		end
		buttons[i] = button
		previous = button
	end

	local refresh = W.Button(content, L.DEV_REFRESH, nil, function()
		tab:Refresh()
	end)
	refresh:SetPoint("TOPRIGHT", -8, -8)

	local search = W.SearchBox(content, 200, L.DEV_FILTER, function(text)
		tab.filter = strtrim(text):lower()
		tab:Refresh()
	end)
	search:SetPoint("RIGHT", refresh, "LEFT", -10, 0)

	local summary = W.Text(content, "GameFontDisableSmall")
	summary:SetPoint("TOPLEFT", buttons[1], "BOTTOMLEFT", 0, -6)

	local panel = W.Panel(content)
	panel:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -4)
	panel:SetPoint("BOTTOMRIGHT", -4, 4)

	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 6, -4)
	scrollBox:SetPoint("BOTTOMRIGHT", -22, 4)
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Frame", function(row, line)
		if not row.text then
			row.text = W.Text(row, "GameFontHighlightSmall")
			row.text:SetPoint("RIGHT")
			row.text:SetWordWrap(false)
			row:EnableMouse(true)
			-- Long lines are cut: the tooltip shows them whole.
			row:SetScript("OnEnter", function(self)
				if self.text:IsTruncated() then
					GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
					GameTooltip:SetText(self.text:GetText(), 1, 1, 1, 1, true)
					GameTooltip:Show()
				end
			end)
			row:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end
		row.text:SetPoint("LEFT", line[2] * INDENT, 0)
		row.text:SetFontObject(line[2] == 0 and "GameFontHighlight" or "GameFontHighlightSmall")
		row.text:SetText(line[1])
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	local shownSection
	function tab:Refresh()
		for i, button in ipairs(buttons) do
			button:SetEnabled(i ~= self.section)
		end
		local blocks = SECTIONS[self.section].build()
		local rows, shown = {}, 0
		for _, block in ipairs(blocks) do
			if Matches(block, self.filter) then
				shown = shown + 1
				rows[#rows + 1] = { block.title, 0 }
				for _, line in ipairs(block.lines) do
					rows[#rows + 1] = line
				end
				rows[#rows + 1] = { "", 0 }
			end
		end
		-- Same section: keep the scroll position (auto refresh on changes).
		scrollBox:SetDataProvider(CreateDataProvider(rows), shownSection == self.section)
		shownSection = self.section
		summary:SetText(L.DEV_SUMMARY:format(shown, #blocks, date("%H:%M:%S")))
	end

	return tab
end

UI.RegisterTab(TAB_INDEX, L.DEV_TAB, Build)
