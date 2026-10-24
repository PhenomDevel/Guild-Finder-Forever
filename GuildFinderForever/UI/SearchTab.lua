-- luacheck: read globals CreateScrollBoxListLinearView ScrollUtil CreateDataProvider GetMaxLevelForPlayerExpansion
local _, ns = ...

-- The two search tabs ("Find guilds", "Find players"): filters on the left,
-- result list with match score, detail view of the selected ad below.
local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local Store = ns.Store
local Search = ns.Search
local MyAds = ns.MyAds
local Verify = ns.Verify

local FILTER_WIDTH = 190
local LIST_HEIGHT = 262
local ROW_HEIGHT = 22
local GAP = 8

ns.dbDefaults.filters = {}

local function MaxLevel()
	return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
end

local function DefaultFilter(kind)
	local faction = Ads.GetFactionCode()
	local filter = {
		kind = kind,
		text = "",
		factions = { A = faction ~= "H", H = faction == "H" },
		lang = C.DefaultLanguage(),
		goals = 0,
		myTimes = false,
		sameMode = true,
	}
	if kind == Ads.KIND_PLAYER then
		filter.roles = 0
		filter.minLevel = 1
		filter.maxLevel = MaxLevel()
	end
	return filter
end

local function GetFilter(kind)
	local saved = ns.db.filters[kind]
	if type(saved) ~= "table" then
		saved = DefaultFilter(kind)
		ns.db.filters[kind] = saved
	end
	saved.kind = kind
	-- The player search always looks at the own faction (the guild's).
	if kind == Ads.KIND_PLAYER then
		local faction = Ads.GetFactionCode()
		saved.factions = { A = faction == "A", H = faction == "H" }
	end
	return saved
end

-- What the searcher brings, for the match score: the player draft when
-- looking for a guild, the guild draft when looking for players.
local function GetProfile(kind)
	local draft
	if kind == Ads.KIND_GUILD then
		draft = MyAds.GetPlayerDraft()
	elseif Ads.GetGuild() then
		draft = MyAds.GetGuildDraft()
	end
	draft = draft or {}
	return { goals = draft.goals or 0, times = draft.times or 0, roles = draft.roles or 0, lang = draft.lang }
end

local function FactionName(code)
	return code == "H" and L.FACTION_HORDE or L.FACTION_ALLIANCE
end

local function LanguageName(key)
	local lang = C.LANGUAGE_BY_KEY[key]
	return lang and lang.label or "?"
end

local function LanguageShort(key)
	return key and key:upper() or "?"
end

--------------------------------------------------------------------------------
-- Columns
--------------------------------------------------------------------------------

local function ScoreText(score)
	if not score then
		return "–"
	end
	local color = score >= 75 and "4fb34a" or score >= 50 and "e6b43a" or "a8a090"
	return ("|cff%s%d %%|r"):format(color, score)
end

local GUILD_COLUMNS = {
	{ label = L.COL_GUILD, width = 196, text = function(r)
		local check = Store.GetCheck(r.ad.i)
		local mark = check and check.verified and " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t" or ""
		return "|cffffffff<" .. r.ad.n .. ">|r" .. mark
	end },
	{ label = L.COL_FACTION, width = 72, text = function(r) return FactionName(r.ad.f) end, muted = true },
	{ label = L.COL_LANGUAGE, width = 50, text = function(r) return LanguageShort(r.ad.l) end },
	{ label = L.COL_GOALS, width = 120, text = function(r) return C.GoalsText(r.ad.g) end },
	{ label = L.COL_TIMES, width = 112, text = function(r) return C.TimesText(r.ad.t) end, muted = true },
	{ label = L.COL_MATCH, width = 50, text = function(r) return ScoreText(r.score) end },
}

local PLAYER_COLUMNS = {
	{ label = L.COL_NAME, width = 110, text = function(r)
		return "|c" .. W.ClassColorHex(r.ad.c) .. Ads.OwnerName(r.ad.o) .. "|r"
	end },
	{ label = L.COL_CLASS_LEVEL, width = 104, text = function(r) return C.ClassName(r.ad.c) .. " · " .. r.ad.lv end, muted = true },
	{ label = L.COL_ROLES, width = 62, roles = true },
	{ label = L.COL_LANGUAGE_SHORT, width = 34, text = function(r) return LanguageShort(r.ad.l) end },
	{ label = L.COL_GOALS, width = 112, text = function(r) return C.GoalsText(r.ad.g) end },
	{ label = L.COL_TIMES, width = 108, text = function(r) return C.TimesText(r.ad.t) end, muted = true },
	{ label = L.COL_MATCH, width = 50, text = function(r) return ScoreText(r.score) end },
}

--------------------------------------------------------------------------------
-- Filter panel
--------------------------------------------------------------------------------

local function BuildFilters(tab, panel, kind)
	local controls = {}
	local y = -10

	local function Place(widget, height, x)
		widget:SetPoint("TOPLEFT", panel, "TOPLEFT", x or 10, y)
		y = y - height
	end

	local function Changed()
		tab:Refresh()
	end

	local function Heading(label)
		y = y - 4
		Place(W.Header(panel, label), 16)
	end

	Heading(L.FILTER_SEARCH)
	controls.text = W.EditBox(panel, FILTER_WIDTH - 26, function(text)
		tab.filter.text = text
		Changed()
	end)
	Place(controls.text, 26, 16)

	if kind == Ads.KIND_GUILD then
		Heading(L.FILTER_FACTION)
		controls.factionA = W.Checkbox(panel, L.FACTION_ALLIANCE, function(on)
			tab.filter.factions.A = on
			Changed()
		end)
		Place(controls.factionA, 22)
		controls.factionH = W.Checkbox(panel, L.FACTION_HORDE, function(on)
			tab.filter.factions.H = on
			Changed()
		end)
		Place(controls.factionH, 22)
	else
		Heading(L.FILTER_CLASS)
		controls.class = W.Dropdown(panel, FILTER_WIDTH - 20, function()
			local list = { { value = false, label = L.ALL_CLASSES } }
			for _, class in ipairs(C.GetClasses()) do
				list[#list + 1] = { value = class.key, label = class.label }
			end
			return list
		end, function()
			return tab.filter.class or false
		end, function(value)
			tab.filter.class = value or nil
			Changed()
		end)
		Place(controls.class, 28)

		Heading(L.FILTER_ROLE)
		controls.roles = {}
		for i, role in ipairs(C.ROLES) do
			local check = W.Checkbox(panel, role.label, function(on)
				tab.filter.roles = C.SetBit(tab.filter.roles, role.bit, on)
				Changed()
			end)
			check.bit = role.bit
			-- Three role boxes side by side.
			check:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + (i - 1) * 60, y)
			controls.roles[i] = check
			check.label:SetText(role.short)
			W.Tooltip(check, role.label)
		end
		y = y - 24

		Heading(L.FILTER_LEVEL)
		controls.minLevel = W.EditBox(panel, 40, function(text)
			tab.filter.minLevel = tonumber(text)
			Changed()
		end)
		controls.minLevel:SetNumeric(true)
		controls.minLevel:SetMaxLetters(3)
		controls.maxLevel = W.EditBox(panel, 40, function(text)
			tab.filter.maxLevel = tonumber(text)
			Changed()
		end)
		controls.maxLevel:SetNumeric(true)
		controls.maxLevel:SetMaxLetters(3)
		controls.minLevel:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
		local to = W.Text(panel, "GameFontHighlightSmall", W.MUTED)
		to:SetPoint("LEFT", controls.minLevel, "RIGHT", 6, 0)
		to:SetText(L.LEVEL_TO)
		controls.maxLevel:SetPoint("LEFT", to, "RIGHT", 10, 0)
		y = y - 26
	end

	Heading(L.FILTER_LANGUAGE)
	controls.lang = W.Dropdown(panel, FILTER_WIDTH - 20, function()
		local list = { { value = false, label = L.ALL_LANGUAGES } }
		for _, lang in ipairs(C.LANGUAGES) do
			list[#list + 1] = { value = lang.key, label = lang.label }
		end
		return list
	end, function()
		return tab.filter.lang or false
	end, function(value)
		tab.filter.lang = value or nil
		Changed()
	end)
	Place(controls.lang, 28)

	Heading(L.FILTER_GOALS)
	controls.goals = {}
	for i, goal in ipairs(C.GOALS) do
		local check = W.Checkbox(panel, goal.label, function(on)
			tab.filter.goals = C.SetBit(tab.filter.goals, goal.bit, on)
			Changed()
		end)
		check.bit = goal.bit
		-- Two columns.
		local column = (i - 1) % 2
		check:SetPoint("TOPLEFT", panel, "TOPLEFT", 10 + column * 86, y)
		if column == 1 or i == #C.GOALS then
			y = y - 22
		end
		controls.goals[i] = check
	end

	Heading(L.FILTER_OTHER)
	controls.myTimes = W.Checkbox(panel, L.FILTER_MY_TIMES, function(on)
		tab.filter.myTimes = on
		Changed()
	end)
	W.Tooltip(controls.myTimes, L.FILTER_MY_TIMES, L.FILTER_MY_TIMES_TIP)
	Place(controls.myTimes, 22)
	controls.sameMode = W.Checkbox(panel, L.FILTER_SAME_MODE, function(on)
		tab.filter.sameMode = on
		Changed()
	end)
	W.Tooltip(controls.sameMode, L.FILTER_SAME_MODE, L.FILTER_SAME_MODE_TIP)
	Place(controls.sameMode, 26)

	local reset = W.Button(panel, L.FILTER_RESET, FILTER_WIDTH - 20, function()
		ns.db.filters[kind] = DefaultFilter(kind)
		tab.filter = GetFilter(kind)
		tab:SyncFilters()
		Changed()
	end)
	reset:SetPoint("BOTTOMLEFT", 10, 36)

	controls.unhide = W.Button(panel, L.SHOW_HIDDEN, FILTER_WIDTH - 20, function()
		Store.ClearHidden()
	end)
	controls.unhide:SetPoint("BOTTOMLEFT", 10, 10)

	-- Pushes the filter values into the controls.
	function tab:SyncFilters()
		local filter = self.filter
		controls.text:SetText(filter.text or "")
		if controls.factionA then
			controls.factionA:SetChecked(filter.factions.A)
			controls.factionH:SetChecked(filter.factions.H)
		end
		if controls.class then
			controls.class:Refresh()
			for _, check in ipairs(controls.roles) do
				check:SetChecked(C.HasBit(filter.roles, check.bit))
			end
			controls.minLevel:SetText(filter.minLevel and tostring(filter.minLevel) or "")
			controls.maxLevel:SetText(filter.maxLevel and tostring(filter.maxLevel) or "")
		end
		controls.lang:Refresh()
		for _, check in ipairs(controls.goals) do
			check:SetChecked(C.HasBit(filter.goals, check.bit))
		end
		controls.myTimes:SetChecked(filter.myTimes)
		controls.sameMode:SetChecked(filter.sameMode)
	end

	function tab:UpdateHiddenButton()
		local count = 0
		for _ in pairs(ns.db.hidden) do
			count = count + 1
		end
		controls.unhide:SetText(L.SHOW_HIDDEN_COUNT:format(count))
		controls.unhide:SetEnabled(count > 0)
	end
end

--------------------------------------------------------------------------------
-- Result list
--------------------------------------------------------------------------------

local function BuildList(tab, panel, columns)
	local header = CreateFrame("Frame", nil, panel)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(22)
	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	headerBg:SetColorTexture(0.137, 0.11, 0.07, 1)
	local x = 10
	for _, column in ipairs(columns) do
		local text = W.Text(header, "GameFontNormalSmall", W.GOLD)
		text:SetPoint("LEFT", x, 0)
		text:SetWidth(column.width)
		text:SetText(column.label)
		x = x + column.width + 6
	end

	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	scrollBox:SetPoint("BOTTOMRIGHT", -16, 1)
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", function(row, result)
		if not row.cells then
			row.cells = {}
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			row.selected = row:CreateTexture(nil, "BORDER")
			row.selected:SetAllPoints()
			row.selected:SetColorTexture(0.79, 0.635, 0.29, 0.25)
			row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
			row:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.08)
			local cx = 10
			for i, column in ipairs(columns) do
				if column.roles then
					local badges = W.RoleBadges(row, 16)
					badges:SetPoint("LEFT", cx, 0)
					row.cells[i] = badges
				else
					local text = W.Text(row, "GameFontHighlightSmall", column.muted and W.MUTED or W.TEXT)
					text:SetPoint("LEFT", cx, 0)
					text:SetWidth(column.width)
					text:SetWordWrap(false)
					row.cells[i] = text
				end
				cx = cx + column.width + 6
			end
			row:SetScript("OnClick", function(self)
				tab:Select(self.result and self.result.ad.i)
			end)
		end
		row.result = result
		for i, column in ipairs(columns) do
			if column.roles then
				row.cells[i]:SetRoles(result.ad.r)
			else
				row.cells[i]:SetText(column.text(result))
			end
		end
		local index = result.index or 0
		row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
		row.selected:SetShown(result.ad.i == tab.selectedId)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	local empty = W.Text(panel, "GameFontDisable")
	empty:SetPoint("CENTER", scrollBox, "CENTER")
	empty:SetText(L.NO_RESULTS)

	function tab:SetResults(results)
		for i, result in ipairs(results) do
			result.index = i
		end
		scrollBox:SetDataProvider(CreateDataProvider(results), true)
		empty:SetShown(#results == 0)
	end

	function tab:RefreshRows()
		scrollBox:ForEachFrame(function(row)
			if row.result then
				row.selected:SetShown(row.result.ad.i == self.selectedId)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Detail view
--------------------------------------------------------------------------------

local function BuildDetail(tab, panel, kind)
	local detail = {}
	local left = CreateFrame("Frame", nil, panel)
	left:SetPoint("TOPLEFT", 12, -10)
	left:SetPoint("BOTTOMRIGHT", -250, 10)

	detail.title = W.Text(left, "GameFontNormalLarge", W.GOLD)
	detail.title:SetPoint("TOPLEFT")
	detail.check = W.Text(left, "GameFontHighlightSmall", W.GREEN)
	detail.check:SetPoint("LEFT", detail.title, "RIGHT", 10, 0)
	detail.info = W.Text(left, "GameFontHighlightSmall", W.MUTED)
	detail.info:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -6)
	detail.info:SetPoint("RIGHT", left, "RIGHT")
	detail.roles = W.RoleBadges(left, 18)
	detail.roles:SetPoint("TOPLEFT", detail.info, "BOTTOMLEFT", 0, -6)
	detail.rolesText = W.Text(left, "GameFontHighlightSmall", W.MUTED)
	detail.rolesText:SetPoint("LEFT", detail.roles, "LEFT", 66, 0)
	detail.text = W.Text(left, "GameFontHighlight", W.TEXT)
	detail.text:SetPoint("TOPLEFT", detail.roles, "BOTTOMLEFT", 0, -8)
	detail.text:SetPoint("RIGHT", left, "RIGHT")
	detail.text:SetJustifyV("TOP")
	detail.text:SetSpacing(2)
	detail.text:SetMaxLines(4)
	detail.goals = W.Text(left, "GameFontNormalSmall", { 0.94, 0.85, 0.56 })
	detail.goals:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 0, -8)
	detail.meta = W.Text(left, "GameFontDisableSmall")
	detail.meta:SetPoint("TOPLEFT", detail.goals, "BOTTOMLEFT", 0, -6)

	local contact = W.Button(left, L.CONTACT, 150, function()
		local ad = tab.selected
		if ad then
			Verify.Contact(ad)
		end
	end)
	contact:SetPoint("BOTTOMLEFT")
	W.Tooltip(contact, L.CONTACT, L.CONTACT_TIP)
	local hide = W.Button(left, L.HIDE, 100, function()
		if tab.selected then
			Store.SetHidden(tab.selected.i, true)
			tab:Select(nil)
		end
	end)
	hide:SetPoint("LEFT", contact, "RIGHT", 8, 0)
	W.Tooltip(hide, L.HIDE, L.HIDE_TIP)
	local block = W.Button(left, L.BLOCK, 100, function()
		if tab.selected then
			Store.Block(tab.selected)
			tab:Select(nil)
		end
	end)
	block:SetPoint("LEFT", hide, "RIGHT", 8, 0)
	W.Tooltip(block, L.BLOCK, kind == Ads.KIND_GUILD and L.BLOCK_GUILD_TIP or L.BLOCK_PLAYER_TIP)

	local right = CreateFrame("Frame", nil, panel)
	right:SetPoint("TOPRIGHT", -12, -10)
	right:SetSize(226, 120)
	local timesHeader = W.Header(right, kind == Ads.KIND_GUILD and L.RAID_TIMES or L.PLAY_TIMES)
	timesHeader:SetPoint("TOPLEFT")
	detail.grid = W.TimeGrid(right, 22, 14, false)
	detail.grid:SetPoint("TOPLEFT", timesHeader, "BOTTOMLEFT", 0, -6)

	local empty = W.Text(panel, "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText(L.SELECT_AD)

	local verifying
	ns.RegisterCallback(detail, "GFF_VERIFY_STARTED", function(_, ad)
		verifying = ad.i
		tab:ShowDetail()
	end)
	ns.RegisterCallback(detail, "GFF_VERIFY_DONE", function(_, ad, result)
		verifying = nil
		if result == "suspicious" then
			ns:Print(L.VERIFY_SUSPICIOUS, ad.k == Ads.KIND_GUILD and ("<" .. ad.n .. ">") or Ads.OwnerName(ad.o))
		elseif result == "offline" then
			ns:Print(L.VERIFY_OFFLINE, Ads.OwnerName(ad.o))
		end
		tab:Refresh()
	end)

	function tab:ShowDetail()
		local ad = self.selected
		left:SetShown(ad ~= nil)
		right:SetShown(ad ~= nil)
		empty:SetShown(ad == nil)
		if not ad then
			return
		end
		local poster = Ads.OwnerName(ad.o)
		local age = W.Duration(GetServerTime() - ad.v)
		if ad.k == Ads.KIND_GUILD then
			detail.title:SetText("<" .. ad.n .. ">")
			local parts = { FactionName(ad.f), LanguageName(ad.l) }
			if ad.gm then
				parts[#parts + 1] = L.MEMBERS:format(ad.gm)
			end
			parts[#parts + 1] = L.POSTED_BY:format(poster, age)
			detail.info:SetText(table.concat(parts, " · "))
			detail.roles:SetRoles(ad.r)
			detail.rolesText:SetText((ad.r or 0) > 0 and L.WANTED_ROLES or "")
		else
			detail.title:SetText("|c" .. W.ClassColorHex(ad.c) .. poster .. "|r")
			detail.info:SetText(table.concat({ C.ClassName(ad.c), L.LEVEL:format(ad.lv), FactionName(ad.f), LanguageName(ad.l) }, " · "))
			detail.roles:SetRoles(ad.r)
			detail.rolesText:SetText("")
		end
		detail.text:SetText(ad.x ~= "" and ad.x or ("|cffa8a090" .. L.NO_TEXT .. "|r"))
		detail.goals:SetText(C.GoalsText(ad.g))
		detail.meta:SetText(L.AD_META:format(age, W.Duration(Ads.ExpiresIn(ad))))
		detail.grid:SetMask(ad.t)

		local check = Store.GetCheck(ad.i)
		if verifying == ad.i then
			detail.check:SetText(L.VERIFYING)
			detail.check:SetTextColor(W.MUTED[1], W.MUTED[2], W.MUTED[3])
		elseif check and check.verified then
			detail.check:SetText(L.VERIFIED)
			detail.check:SetTextColor(W.GREEN[1], W.GREEN[2], W.GREEN[3])
		else
			detail.check:SetText(L.NOT_VERIFIED)
			detail.check:SetTextColor(W.MUTED[1], W.MUTED[2], W.MUTED[3])
		end
	end
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

local function BuildTab(content, kind, columns)
	local tab = { kind = kind }
	tab.filter = GetFilter(kind)

	local filters = W.Panel(content)
	filters:SetPoint("TOPLEFT")
	filters:SetPoint("BOTTOMLEFT")
	filters:SetWidth(FILTER_WIDTH)
	BuildFilters(tab, filters, kind)

	local list = W.Panel(content)
	list:SetPoint("TOPLEFT", filters, "TOPRIGHT", GAP, 0)
	list:SetPoint("TOPRIGHT")
	list:SetHeight(LIST_HEIGHT)
	BuildList(tab, list, columns)

	local detailPanel = W.Panel(content)
	detailPanel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -GAP)
	detailPanel:SetPoint("BOTTOMRIGHT")
	BuildDetail(tab, detailPanel, kind)

	function tab:Select(id)
		self.selectedId = id
		self.selected = id and Store.Get(id) or nil
		if self.selected and (self.selected.d or Store.IsFiltered(self.selected)) then
			self.selected, self.selectedId = nil, nil
		end
		self:RefreshRows()
		self:ShowDetail()
	end

	function tab:Refresh()
		local results = Search.Run(self.filter, GetProfile(kind))
		self.count = #results
		self:SetResults(results)
		self:UpdateHiddenButton()
		-- Keep the selection while it is still in the results.
		local keep
		for _, result in ipairs(results) do
			if result.ad.i == self.selectedId then
				keep = true
				break
			end
		end
		self:Select(keep and self.selectedId or (results[1] and results[1].ad.i))
		UI.SetMatchCount(self:GetStatusText())
	end

	function tab:GetStatusText()
		if not self.count then
			return nil
		end
		return (kind == Ads.KIND_GUILD and L.STATUS_MATCHES_GUILDS or L.STATUS_MATCHES_PLAYERS):format(self.count)
	end

	function tab:OnShow()
		self.filter = GetFilter(kind)
		self:SyncFilters()
	end

	return tab
end

UI.RegisterTab(1, L.TAB_FIND_GUILDS, function(content)
	return BuildTab(content, Ads.KIND_GUILD, GUILD_COLUMNS)
end)

UI.RegisterTab(2, L.TAB_FIND_PLAYERS, function(content)
	return BuildTab(content, Ads.KIND_PLAYER, PLAYER_COLUMNS)
end)

--------------------------------------------------------------------------------
-- Chat notice for new matching ads
--------------------------------------------------------------------------------
-- Only while the own side is posted: a player ad → new guild ads, a guild
-- ad → new player ads. At most one line per NOTIFY_INTERVAL.

local NOTIFY_INTERVAL = 60
local pendingNotice = {}
local noticeTimer

local function FlushNotice()
	noticeTimer = nil
	local count = #pendingNotice
	if count == 0 then
		return
	end
	local first = pendingNotice[1]
	local name = first.k == Ads.KIND_GUILD and ("<" .. first.n .. ">") or Ads.OwnerName(first.o)
	if count == 1 then
		ns:Print(first.k == Ads.KIND_GUILD and L.NOTIFY_GUILD or L.NOTIFY_PLAYER, name)
	else
		ns:Print(first.k == Ads.KIND_GUILD and L.NOTIFY_GUILDS or L.NOTIFY_PLAYERS, name, count - 1)
	end
	wipe(pendingNotice)
end

ns.RegisterCallback({}, "GFF_AD_RECEIVED", function(_, ad, isNew)
	if not isNew or not ns.db.settings.notifyNew then
		return
	end
	local looking
	if ad.k == Ads.KIND_GUILD then
		looking = MyAds.GetPlayerAd()
	else
		looking = MyAds.GetGuildAd()
	end
	if not looking or not Search.Accepts(ad, GetFilter(ad.k), GetProfile(ad.k)) then
		return
	end
	pendingNotice[#pendingNotice + 1] = ad
	-- The first notice goes out right away, later ones are bundled.
	if not noticeTimer then
		FlushNotice()
		noticeTimer = C_Timer.NewTimer(NOTIFY_INTERVAL, FlushNotice)
	end
end)
