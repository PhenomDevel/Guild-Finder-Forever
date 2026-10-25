-- luacheck: read globals CreateScrollBoxListLinearView ScrollUtil CreateDataProvider
local _, ns = ...

-- "Find players" tab: role/level/class filters in a toolbar, a dense
-- list like the group finder, the selected row expands inline with the
-- text and the actions.
local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local Store = ns.Store
local Verify = ns.Verify
local Filters = ns.Filters

local KIND = Ads.KIND_PLAYER
local ROW_HEIGHT = 30
local EXPANDED_HEIGHT = 136
local TOOLBAR_HEIGHT = 34

-- value(result) is what a click on the column header sorts by; numeric
-- columns start descending.
local COLUMNS = {
	{ key = "icon", x = 10, width = 22 },
	{ key = "name", x = 42, width = 130, label = L.COL_NAME, value = function(r) return Ads.OwnerName(r.ad.o):lower() end },
	{ key = "class", x = 176, width = 100, label = L.COL_CLASS, value = function(r) return C.ClassName(r.ad.c) end },
	{ key = "level", numeric = true, x = 280, width = 40, label = L.COL_LEVEL, value = function(r) return r.ad.lv or 0 end },
	{ key = "roles", numeric = true, x = 324, width = 64, label = L.COL_ROLES, value = function(r) return C.CountBits(r.ad.r or 0) end },
	{ key = "lang", x = 392, width = 46, label = L.COL_LANGUAGE_SHORT, value = function(r) return r.ad.l or "" end },
	{ key = "goals", numeric = true, x = 442, width = 96, label = L.COL_GOALS, value = function(r) return C.CountBits(r.ad.g or 0) end },
	{ key = "strip", numeric = true, x = 542, width = 100, label = L.COL_EVENINGS, value = function(r) return C.CountBits(r.ad.t or 0) end },
	{ key = "match", numeric = true, x = 650, width = 56, label = L.COL_MATCH, value = function(r) return r.score or -1 end },
}
local ARROW_UP = "|TInterface\\Buttons\\Arrow-Up-Up:0|t"

local function Column(key)
	for _, column in ipairs(COLUMNS) do
		if column.key == key then
			return column
		end
	end
end

local function RolesText(mask)
	local parts = {}
	for _, role in ipairs(C.ROLES) do
		if C.HasBit(mask or 0, role.bit) then
			parts[#parts + 1] = role.label
		end
	end
	return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

local function BuildToolbar(tab, content, changed)
	local controls = {}
	local rolesLabel = W.Text(content, "GameFontHighlight", W.MUTED)
	rolesLabel:SetPoint("TOPLEFT", 0, -8)
	rolesLabel:SetText(L.ROLES)
	controls.roles = {}
	local previous = rolesLabel
	for i, role in ipairs(C.ROLES) do
		local toggle = W.RoleToggle(content, 24, role.bit, function(on)
			local filter = Filters.Get(KIND)
			filter.roles = C.SetBit(filter.roles or 0, role.bit, on)
			changed()
		end)
		toggle:SetPoint("LEFT", previous, "RIGHT", i == 1 and 8 or 4, 0)
		controls.roles[i] = toggle
		previous = toggle
	end

	local levelLabel = W.Text(content, "GameFontHighlight", W.MUTED)
	levelLabel:SetPoint("LEFT", previous, "RIGHT", 16, 0)
	levelLabel:SetText(L.FILTER_LEVEL)
	local function LevelBox(field)
		local box = W.EditBox(content, 30, function(text)
			Filters.Get(KIND)[field] = tonumber(text)
			changed()
		end)
		box:SetNumeric(true)
		box:SetMaxLetters(3)
		return box
	end
	controls.minLevel = LevelBox("minLevel")
	controls.minLevel:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)
	local dash = W.Text(content, "GameFontHighlight", W.MUTED)
	dash:SetPoint("LEFT", controls.minLevel, "RIGHT", 4, 0)
	dash:SetText("–")
	controls.maxLevel = LevelBox("maxLevel")
	controls.maxLevel:SetPoint("LEFT", dash, "RIGHT", 10, 0)

	controls.class = W.Dropdown(content, 130, function()
		local list = { { value = false, label = L.ALL_CLASSES } }
		for _, class in ipairs(C.GetClasses()) do
			list[#list + 1] = { value = class.key, label = class.label }
		end
		return list
	end, function()
		return Filters.Get(KIND).class or false
	end, function(value)
		Filters.Get(KIND).class = value or nil
		changed()
	end)
	controls.class:SetPoint("LEFT", controls.maxLevel, "RIGHT", 10, 0)

	controls.chips = Filters.ChipBar(content, KIND, changed)
	controls.chips:SetPoint("LEFT", controls.class, "RIGHT", 10, 0)

	controls.search = W.SearchBox(content, 150, L.SEARCH_PLAYERS, function(text)
		Filters.Get(KIND).text = text
		changed()
	end)
	controls.search:SetPoint("TOPRIGHT", 0, -2)

	function tab:SyncToolbar()
		local filter = Filters.Get(KIND)
		for i, role in ipairs(C.ROLES) do
			controls.roles[i]:SetOn(C.HasBit(filter.roles or 0, role.bit))
		end
		controls.minLevel:SetText(filter.minLevel and tostring(filter.minLevel) or "")
		controls.maxLevel:SetText(filter.maxLevel and tostring(filter.maxLevel) or "")
		controls.class:Refresh()
		controls.chips:Update()
		if controls.search:GetText() ~= (filter.text or "") then
			controls.search:SetText(filter.text or "")
		end
	end
end

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local function BuildRow(tab, row)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetPoint("TOPLEFT")
	row.bg:SetPoint("TOPRIGHT")
	row.bg:SetHeight(ROW_HEIGHT)
	row.selectedBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.selectedBg:SetAllPoints()
	row.selectedBg:SetColorTexture(0.79, 0.635, 0.29, 0.1)
	row.selectedTop = row:CreateTexture(nil, "BORDER")
	row.selectedTop:SetPoint("TOPLEFT")
	row.selectedTop:SetPoint("TOPRIGHT")
	row.selectedTop:SetHeight(ROW_HEIGHT)
	row.selectedTop:SetColorTexture(0.79, 0.635, 0.29, 0.15)
	row.line = W.Divider(row)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	row.line:SetColorTexture(1, 1, 1, 0.05)

	local hit = CreateFrame("Button", nil, row)
	hit:SetPoint("TOPLEFT")
	hit:SetPoint("TOPRIGHT")
	hit:SetHeight(ROW_HEIGHT)
	hit:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
	hit:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.06)
	hit:SetScript("OnClick", function()
		if row.result then
			tab:Select(row.result.ad.i)
		end
	end)

	local function Cell(key, font, color)
		local column = Column(key)
		local text = W.Text(hit, font or "GameFontHighlight", color)
		text:SetPoint("LEFT", hit, "LEFT", column.x, 0)
		text:SetWidth(column.width)
		text:SetWordWrap(false)
		return text
	end
	row.icon = W.ClassIcon(hit, 22)
	row.icon:SetPoint("LEFT", Column("icon").x, 0)
	row.name = Cell("name", "GameFontNormal")
	row.class = Cell("class", "GameFontHighlight", W.MUTED)
	row.level = Cell("level", "GameFontHighlight")
	row.roles = W.RoleIcons(hit, 16)
	row.roles:SetPoint("LEFT", Column("roles").x, 0)
	row.lang = Cell("lang")
	row.goals = W.GoalIcons(hit, 18)
	row.goals:SetPoint("LEFT", Column("goals").x, 0)
	row.strip = W.WeekStrip(hit, 12)
	row.strip:SetPoint("LEFT", Column("strip").x, 0)
	row.match = Cell("match", "GameFontNormal")

	-- Expanded part
	local detail = CreateFrame("Frame", nil, row)
	detail:SetPoint("TOPLEFT", 0, -ROW_HEIGHT)
	detail:SetPoint("BOTTOMRIGHT")
	row.detail = detail
	row.text = W.Text(detail, "GameFontHighlight", W.TEXT)
	row.text:SetPoint("TOPLEFT", 42, -8)
	row.text:SetPoint("RIGHT", -190, 0)
	row.text:SetJustifyV("TOP")
	row.text:SetSpacing(3)
	row.text:SetMaxLines(3)
	row.tags = W.GoalTags(detail)
	row.tags:SetPoint("BOTTOMLEFT", 42, 10)
	row.note = W.Text(detail, "GameFontDisableSmall")
	row.note:SetWordWrap(false)
	-- Languages get their own line above the goals: an ad can name up to seven.
	row.langs = W.Text(detail, "GameFontDisableSmall")
	row.langs:SetPoint("BOTTOMLEFT", row.tags, "TOPLEFT", 0, 8)
	row.langs:SetPoint("RIGHT", row.text, "RIGHT", 0, 0)
	row.langs:SetWordWrap(false)

	row.contact = W.Button(detail, L.CONTACT_SHORT, 168, function()
		if row.result then
			Verify.Contact(row.result.ad)
		end
	end)
	row.contact:SetPoint("TOPRIGHT", -12, -6)
	W.Tooltip(row.contact, L.CONTACT, L.CONTACT_TIP)
	row.hide = W.Button(detail, L.HIDE, 82, function()
		if row.result then
			Store.SetHidden(row.result.ad.i, true)
		end
	end)
	row.hide:SetPoint("TOPLEFT", row.contact, "BOTTOMLEFT", 0, -6)
	W.Tooltip(row.hide, L.HIDE, L.HIDE_TIP)
	row.block = W.Button(detail, L.BLOCK, 82, function()
		if row.result then
			Store.Block(row.result.ad)
		end
	end)
	row.block:SetPoint("TOPRIGHT", row.contact, "BOTTOMRIGHT", 0, -6)
	W.Tooltip(row.block, L.BLOCK, L.BLOCK_PLAYER_TIP)
end

local function FillRow(tab, row, result)
	local ad = result.ad
	row.result = result
	local selected = ad.i == tab.selectedId
	row.bg:SetColorTexture(1, 1, 1, (result.index or 0) % 2 == 0 and 0.025 or 0)
	row.selectedBg:SetShown(selected)
	row.selectedTop:SetShown(selected)

	row.icon:SetClass(ad.c)
	row.name:SetText("|c" .. W.ClassColorHex(ad.c) .. Ads.OwnerName(ad.o) .. "|r")
	row.class:SetText(C.ClassName(ad.c))
	row.level:SetText(ad.lv)
	row.roles:SetRoles(ad.r)
	local langs = C.AdLanguages(ad)
	if #langs > 2 then
		row.lang:SetText(langs[1]:upper() .. " +" .. (#langs - 1))
	else
		row.lang:SetText(table.concat(langs, "/"):upper())
	end
	row.goals:SetGoals(ad.g)
	row.strip:SetMask(ad.t)
	if result.score then
		row.match:SetText(result.score .. " %")
		W.Color(row.match, W.ScoreColor(result.score))
	else
		row.match:SetText("–")
		W.Color(row.match, W.MUTED)
	end

	row.detail:SetShown(selected)
	if selected then
		row.text:SetText(ad.x ~= "" and ad.x or ("|cff9d9d9d" .. L.NO_TEXT .. "|r"))
		local width = row.tags:SetGoals(ad.g)
		row.note:ClearAllPoints()
		row.note:SetPoint("LEFT", row.tags, "LEFT", math.max(0, width) + 10, 0)
		row.note:SetPoint("RIGHT", row.text, "RIGHT", 0, 0)
		row.langs:SetText(L.FILTER_LANGUAGE .. ": |cffffffff" .. Filters.LanguagesText(ad) .. "|r")
		local note = L.UPDATED_AGO:format(W.Duration(GetServerTime() - ad.v))
		if (ad.r or 0) > 0 then
			note = RolesText(ad.r) .. " · " .. note
		end
		row.note:SetText(note)
	end
end

local function BuildList(tab, panel)
	local header = CreateFrame("Frame", nil, panel)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(24)
	local headerBg = header:CreateTexture(nil, "BACKGROUND")
	headerBg:SetAllPoints()
	headerBg:SetColorTexture(0.12, 0.1, 0.06, 1)
	-- Clickable headers: first click sorts (text ascending, numbers
	-- descending), the next one reverses; the arrow marks the column.
	local headers = {}
	local function UpdateHeaders()
		for _, entry in ipairs(headers) do
			local sort = tab.sort
			local arrow = ""
			if sort and sort.key == entry.column.key then
				arrow = " " .. (sort.desc and W.ARROW_DOWN or ARROW_UP)
			end
			entry.text:SetText(entry.column.label .. arrow)
		end
	end
	for _, column in ipairs(COLUMNS) do
		if column.label then
			local button = CreateFrame("Button", nil, header)
			button:SetPoint("LEFT", column.x, 0)
			button:SetSize(column.width, 24)
			button:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
			button:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.08)
			local text = W.Text(button, "GameFontNormalSmall", W.GOLD)
			text:SetPoint("LEFT")
			text:SetWidth(column.width)
			text:SetWordWrap(false)
			button:SetScript("OnClick", function()
				local sort = tab.sort
				if sort and sort.key == column.key then
					sort.desc = not sort.desc
				else
					tab.sort = { key = column.key, desc = column.numeric == true }
				end
				UpdateHeaders()
				tab:SetResults(tab.results or {})
			end)
			headers[#headers + 1] = { column = column, text = text }
		end
	end
	UpdateHeaders()

	-- Stable sort by the chosen column; ties keep the filter's order.
	local function Sort(results)
		local sort = tab.sort
		local column = sort and Column(sort.key)
		if not column then
			return
		end
		for i, result in ipairs(results) do
			result.order = i
		end
		table.sort(results, function(a, b)
			local va, vb = column.value(a), column.value(b)
			if va ~= vb then
				if sort.desc then
					return va > vb
				end
				return va < vb
			end
			return a.order < b.order
		end)
	end

	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	scrollBox:SetPoint("BOTTOMRIGHT", -18, 1)
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, result)
		return result.ad.i == tab.selectedId and EXPANDED_HEIGHT or ROW_HEIGHT
	end)
	view:SetElementInitializer("Frame", function(row, result)
		if not row.detail then
			BuildRow(tab, row)
		end
		FillRow(tab, row, result)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	local empty = W.Text(panel, "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetJustifyH("CENTER")
	empty:SetWidth(420)

	function tab:SetResults(results)
		local count = 0
		for _ in Store.Each(KIND) do
			count = count + 1
		end
		Sort(results)
		for i, result in ipairs(results) do
			result.index = i
		end
		self.results = results
		scrollBox:SetDataProvider(CreateDataProvider(results), true)
		empty:SetShown(#results == 0)
		empty:SetText(count == 0 and L.NO_PLAYER_ADS_YET or L.NO_RESULTS)
	end
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

local function Build(content)
	local tab = {}

	local function Changed()
		tab:Refresh()
	end
	BuildToolbar(tab, content, Changed)

	local panel = W.Panel(content)
	panel:SetPoint("TOPLEFT", 0, -TOOLBAR_HEIGHT - 6)
	panel:SetPoint("BOTTOMRIGHT")
	BuildList(tab, panel)

	-- Clicking the open row closes it again.
	function tab:Select(id)
		self.selectedId = self.selectedId ~= id and id or nil
		self:SetResults(self.results or {})
		if self.selectedId then
			Verify.Ping(Store.Get(self.selectedId))
		end
	end

	function tab:Refresh()
		self:SyncToolbar()
		local results = Filters.Run(KIND)
		local keep
		for _, result in ipairs(results) do
			if result.ad.i == self.selectedId then
				keep = true
				break
			end
		end
		if not keep then
			self.selectedId = nil
		end
		self.count = #results
		self:SetResults(results)
		UI.SetMatchCount(self:GetStatusText())
	end

	function tab:GetStatusText()
		if not self.count then
			return nil
		end
		local faction = Filters.FactionName(Ads.GetFactionCode())
		return L.STATUS_MATCHES_PLAYERS:format(self.count) .. "    |cff9d9d9d"
			.. (Ads.GetGuild() and L.STATUS_FACTION_GUILD or L.STATUS_FACTION):format(faction) .. "|r"
	end

	return tab
end

UI.RegisterTab(2, L.TAB_FIND_PLAYERS, Build)
