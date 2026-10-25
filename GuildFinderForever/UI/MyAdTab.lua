-- luacheck: read globals UnitClass UnitLevel GetNumGuildMembers GameTooltip MenuUtil
local _, ns = ...

-- "My ad" tab: the player ad of this character as four numbered steps or,
-- with invite rights, the guild's ad step by step (with a raid page for the
-- raid goal). On the right a live preview of how others see the ad and the
-- publish controls.
local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local Search = ns.Search
local MyAds = ns.MyAds
local Filters = ns.Filters

local SIDE_WIDTH = 282
local GAP = 8
local STEP_X = 48
local VERY_GOOD = 75

local MODE_PLAYER, MODE_GUILD = "player", "guild"

local CONTENT_WIDTH = 512 -- form width minus padding
local PAGE_TOP = -88 -- guild wizard: below mode switch and step bar
local CELL_W, CELL_H, ROW_H = 30, 18, 22

local function HasRaid(mode, draft)
	return mode == MODE_GUILD and C.HasBit(draft.goals or 0, C.GOAL_RAID)
end

local function SameRaid(draft, ad)
	local start = draft.raidStart
	return draft.style == ad.ps and (draft.classes or 0) == (ad.cl or 0) and draft.classRoles == ad.cr
		and (draft.raidDays or 0) == (ad.rd or 0)
		and draft.raidsPerWeek == ad.rn and start == ad.rs and (start and draft.raidEnd) == ad.re
end

local function SameDraft(mode, draft, ad)
	return ad ~= nil and draft.roles == (ad.r or 0) and draft.goals == ad.g and draft.times == ad.t
		and draft.lang == ad.l and draft.moreLangs == ad.la and Ads.CleanText(draft.text) == ad.x
		and (not HasRaid(mode, draft) or SameRaid(draft, ad))
end

-- { value, label } list for the raid time dropdowns; nil = not stated.
local function TimeOptions()
	local list = { { value = nil, label = "–" } }
	for minutes = 0, 24 * 60 - 1, C.TIME_STEP do
		list[#list + 1] = { value = minutes, label = C.FormatTime(minutes) }
	end
	return list
end

-- Gold pill with role icon and label.
local function RolePill(parent, role, onToggle)
	local pill = W.Chip(parent, function(self)
		self:SetActive(not self.active)
		onToggle(self.active)
	end)
	pill:SetHeight(26)
	local icon = W.RoleIcon(pill, 18, role.bit)
	icon:SetPoint("LEFT", 5, 0)
	pill.text:ClearAllPoints()
	pill.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	pill.text:SetText(role.label)
	pill:SetWidth(5 + 18 + 6 + pill.text:GetStringWidth() + 12)
	pill.bit = role.bit
	function pill:SetAllowed(allowed)
		self:SetEnabled(allowed)
		self:SetAlpha(allowed and 1 or 0.4)
	end
	return pill
end

local function Build(content)
	local tab = { mode = MODE_PLAYER }
	local controls = {}

	local form = W.Panel(content)
	form:SetPoint("TOPLEFT")
	form:SetPoint("BOTTOMRIGHT", -(SIDE_WIDTH + GAP), 0)

	local function Draft()
		return tab.mode == MODE_GUILD and tab.guildDraft or MyAds.GetPlayerDraft()
	end

	local function Changed()
		tab:UpdateLive()
	end

	-- Mode switch and identity
	controls.playerMode = W.Chip(form, function()
		tab.mode = MODE_PLAYER
		tab:Refresh()
	end)
	controls.playerMode:SetLabel(L.MODE_PLAYER)
	controls.playerMode:SetWidth(124)
	controls.playerMode:SetHeight(26)
	controls.playerMode:SetPoint("TOPLEFT", 14, -12)
	controls.guildMode = W.Chip(form, function()
		tab.mode = MODE_GUILD
		tab.page = 1
		tab.guildDraft = MyAds.GetGuildDraft()
		tab:Refresh()
	end)
	controls.guildMode:SetLabel(L.MODE_GUILD)
	controls.guildMode:SetWidth(124)
	controls.guildMode:SetHeight(26)
	controls.guildMode:SetPoint("LEFT", controls.playerMode, "RIGHT", -1, 0)
	controls.guildMode:SetMotionScriptsWhileDisabled(true)
	controls.guildMode:HookScript("OnEnter", function(self)
		if not self:IsEnabled() then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L.MODE_GUILD, 1, 1, 1)
			GameTooltip:AddLine(Ads.GetGuild() and L.NOTE_OTHER_GUILD_CANNOT or L.NOTE_OTHER_GUILD_NONE, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	controls.guildMode:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	controls.identity = W.Text(form, "GameFontHighlight", W.MUTED)
	controls.identity:SetPoint("LEFT", controls.guildMode, "RIGHT", 14, 0)
	controls.identity:SetPoint("RIGHT", form, "RIGHT", -14, 0)

	-- Sections: stacked with numbered steps for the player ad, one page
	-- each in the guild ad's step-by-step form.
	controls.sections = {}
	local function Section(key)
		local section = CreateFrame("Frame", nil, form)
		section:SetHeight(40)
		section.circle = W.StepCircle(section, "", 24)
		section.circle:SetPoint("TOPLEFT")
		section.header = W.Header(section, "", "GameFontNormalLarge")
		section.hint = W.Text(section, "GameFontDisableSmall")
		section.hint:SetPoint("BOTTOMLEFT", section.header, "BOTTOMRIGHT", 8, 1)
		section.hint:SetPoint("RIGHT", section, "RIGHT", 0, 0)
		section.hint:SetWordWrap(false)
		-- Content starts at (section.x, -32) relative to the section.
		function section:SetNumbered(number)
			self.circle:SetShown(number ~= nil)
			self.header:ClearAllPoints()
			if number then
				self.circle.text:SetText(number)
				self.header:SetPoint("LEFT", self.circle, "RIGHT", 10, 0)
			else
				self.header:SetPoint("TOPLEFT", 0, -4)
			end
		end
		section.x = STEP_X - 14
		controls.sections[key] = section
		return section
	end

	-- Roles
	local secRoles = Section("roles")
	controls.roles = {}
	local x = STEP_X - 14
	for i, role in ipairs(C.ROLES) do
		local pill = RolePill(secRoles, role, function(on)
			local draft = Draft()
			draft.roles = C.SetBit(draft.roles, role.bit, on)
			Changed()
		end)
		pill:SetPoint("TOPLEFT", x, -32)
		x = x + pill:GetWidth() + 8
		controls.roles[i] = pill
	end
	secRoles:SetHeight(62)

	-- Goals and language
	local secGoals = Section("goals")
	controls.goals = {}
	x = STEP_X - 14
	for i, goal in ipairs(C.GOALS) do
		local chip = W.Chip(secGoals, function(self)
			self:SetActive(not self.active)
			local draft = Draft()
			draft.goals = C.SetBit(draft.goals, goal.bit, self.active)
			Changed()
		end)
		chip:SetLabel(W.GoalIconMarkup(goal) .. " " .. goal.label)
		chip:SetHeight(26)
		chip:SetWidth(math.max(64, chip:GetWidth()))
		chip:SetPoint("TOPLEFT", x, -32)
		chip.bit = goal.bit
		x = x + chip:GetWidth() + 6
		controls.goals[i] = chip
	end
	local langHeader = W.Header(secGoals, L.FILTER_LANGUAGE, "GameFontNormalLarge")
	langHeader:SetPoint("TOPLEFT", 332, -2)
	-- Several languages: the first ticked (in list order) becomes the main
	-- one (l), the others go to la. At least one stays ticked.
	local function SetLanguages(draft, ticked)
		local keys = {}
		for _, lang in ipairs(C.LANGUAGES) do
			if ticked[lang.key] and #keys <= C.MAX_MORE_LANGS then
				keys[#keys + 1] = lang.key
			end
		end
		draft.lang = keys[1]
		draft.moreLangs = #keys > 1 and table.concat(keys, "", 2) or nil
	end
	local function Ticked(draft)
		local ticked = {}
		for _, key in ipairs(C.AdLanguages({ l = draft.lang, la = draft.moreLangs })) do
			ticked[key] = true
		end
		return ticked
	end
	controls.lang = W.Menu(secGoals, 150, function(root)
		if root.SetScrollMode then
			root:SetScrollMode(20 * 20)
		end
		for _, lang in ipairs(C.LANGUAGES) do
			root:CreateCheckbox(lang.label, function()
				return Ticked(Draft())[lang.key] == true
			end, function()
				local draft = Draft()
				local ticked = Ticked(draft)
				local count = 0
				for _ in pairs(ticked) do
					count = count + 1
				end
				if ticked[lang.key] and count == 1 then
					return
				end
				ticked[lang.key] = not ticked[lang.key] or nil
				SetLanguages(draft, ticked)
				Changed()
			end)
		end
	end)
	local refreshLang = controls.lang.Refresh
	function controls.lang:Refresh()
		refreshLang(self)
		if self.OverrideText then
			local draft = Draft()
			self:OverrideText(Filters.LanguagesText({ l = draft.lang, la = draft.moreLangs }))
		end
	end
	controls.lang:SetPoint("TOPLEFT", 332, -28)
	secGoals:SetHeight(62)

	-- Play times with presets
	local secTimes = Section("times")
	controls.grid = W.TimeGrid(secTimes, 34, 18, true, function(mask)
		Draft().times = mask
		Changed()
	end)
	controls.grid:SetPoint("TOPLEFT", STEP_X - 14, -30)
	local weekend, evenings = 0, 0
	for slot = 1, #C.SLOTS do
		weekend = C.SetBit(C.SetBit(weekend, C.TimeBit(6, slot), true), C.TimeBit(7, slot), true)
	end
	for day = 1, #C.DAYS do
		evenings = C.SetBit(evenings, C.TimeBit(day, 2), true)
	end
	local presets = {
		{ L.PRESET_WEEKEND, weekend },
		{ L.PRESET_EVENINGS, evenings },
		{ L.PRESET_NONE, 0 },
	}
	for slot, preset in ipairs(presets) do
		local link = W.LinkButton(secTimes, preset[1], function()
			Draft().times = preset[2]
			controls.grid:SetMask(preset[2])
			Changed()
		end)
		local rowEnd = controls.grid.rowEnds[slot]
		link:SetPoint("TOPLEFT", controls.grid, "TOPLEFT", rowEnd.x + 4, rowEnd.y - 2)
	end
	secTimes:SetHeight(112)

	-- Text
	local secText = Section("text")
	controls.text = W.TextArea(secText, 400, 64, C.MAX_TEXT, function(text)
		Draft().text = text
		Changed()
	end)
	controls.text:SetPoint("TOPLEFT", STEP_X - 14, -32)
	controls.text:SetPoint("RIGHT", 0, 0)
	local textHint = W.Text(secText, "GameFontDisableSmall")
	textHint:SetPoint("TOPLEFT", controls.text, "BOTTOMLEFT", 0, -4)
	textHint:SetText(L.TEXT_HINT)
	secText:SetHeight(116)

	--------------------------------------------------------------------------
	-- Raid (guild ads with the raid goal): style, schedule, needs per class
	--------------------------------------------------------------------------

	local secRaid = Section("raid")
	secRaid:SetHeight(350)
	local raidTop = -30
	local function SubHeader(text, y)
		local header = W.Header(secRaid, text, "GameFontNormal")
		header:SetPoint("TOPLEFT", 0, y)
		return header
	end

	SubHeader(L.FILTER_STYLE, raidTop)
	controls.styles = {}
	local styleWidth = (CONTENT_WIDTH - 2 * 8) / #C.STYLES
	for i, style in ipairs(C.STYLES) do
		local card = CreateFrame("Button", nil, secRaid, "BackdropTemplate")
		card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		card:SetSize(styleWidth, 40)
		card:SetPoint("TOPLEFT", (i - 1) * (styleWidth + 8), raidTop - 18)
		card:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
		card:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.06)
		card.title = W.Text(card, "GameFontNormal")
		card.title:SetPoint("TOPLEFT", 10, -6)
		card.title:SetText(style.label)
		card.desc = W.Text(card, "GameFontDisableSmall")
		card.desc:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
		card.desc:SetPoint("RIGHT", -8, 0)
		card.desc:SetWordWrap(false)
		card.desc:SetText(L["STYLE_" .. style.key .. "_DESC"])
		card.value = style.value
		function card:SetActive(active)
			if active then
				self:SetBackdropColor(0.16, 0.13, 0.06, 1)
				self:SetBackdropBorderColor(0.79, 0.635, 0.29, 1)
				W.Color(self.title, W.GOLD)
			else
				self:SetBackdropColor(0.1, 0.1, 0.1, 1)
				self:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
				W.Color(self.title, W.WHITE)
			end
		end
		card:SetScript("OnClick", function()
			local draft = Draft()
			draft.style = draft.style ~= style.value and style.value or nil
			tab:UpdateRaid()
			Changed()
		end)
		controls.styles[i] = card
	end

	local scheduleTop = raidTop - 70
	local scheduleHeader = SubHeader(L.RAID_SCHEDULE, scheduleTop)
	local realmHint = W.Text(secRaid, "GameFontDisableSmall")
	realmHint:SetPoint("BOTTOMLEFT", scheduleHeader, "BOTTOMRIGHT", 6, 0)
	realmHint:SetText(L.REALM_TIME)
	controls.perWeek = W.Stepper(secRaid, 1, 7, function()
		return Draft().raidsPerWeek
	end, function(value)
		Draft().raidsPerWeek = value
		Changed()
	end)
	controls.perWeek:SetPoint("TOPRIGHT", secRaid, "TOPRIGHT", 0, scheduleTop + 2)
	local perWeekLabel = W.Text(secRaid, "GameFontNormalSmall", W.TAG)
	perWeekLabel:SetPoint("RIGHT", controls.perWeek, "LEFT", -6, 0)
	perWeekLabel:SetText(L.RAIDS_PER_WEEK)

	controls.raidDays = {}
	for day, name in ipairs(C.DAYS) do
		local chip = W.Chip(secRaid, function(self)
			self:SetActive(not self.active)
			local draft = Draft()
			draft.raidDays = C.SetBit(draft.raidDays or 0, C.DayBit(day), self.active)
			Changed()
		end)
		chip:SetLabel(name)
		chip:SetSize(34, 26)
		chip:SetPoint("TOPLEFT", (day - 1) * 38, scheduleTop - 20)
		chip.bit = C.DayBit(day)
		controls.raidDays[day] = chip
	end
	controls.raidStart = W.Dropdown(secRaid, 76, TimeOptions, function()
		return Draft().raidStart
	end, function(value)
		Draft().raidStart = value
		Changed()
	end)
	controls.raidStart:SetPoint("TOPLEFT", 7 * 38 + 14, scheduleTop - 21)
	local dash = W.Text(secRaid, "GameFontHighlight")
	dash:SetPoint("LEFT", controls.raidStart, "RIGHT", 4, 0)
	dash:SetText("–")
	controls.raidEnd = W.Dropdown(secRaid, 76, TimeOptions, function()
		return Draft().raidEnd
	end, function(value)
		Draft().raidEnd = value
		Changed()
	end)
	controls.raidEnd:SetPoint("LEFT", dash, "RIGHT", 4, 0)
	W.Tooltip(controls.raidStart, L.RAID_TIME, L.RAID_TIME_TIP)
	W.Tooltip(controls.raidEnd, L.RAID_TIME, L.RAID_TIME_TIP)

	-- Needs: classes × roles. A cell = class wanted in that role; a class
	-- with all its roles marked is stored like "any role".
	local needsTop = scheduleTop - 58
	local needsHeader = SubHeader(L.RAID_NEEDS, needsTop)
	local needsHint = W.Text(secRaid, "GameFontDisableSmall")
	needsHint:SetPoint("BOTTOMLEFT", needsHeader, "BOTTOMRIGHT", 6, 0)
	needsHint:SetPoint("RIGHT", secRaid, "RIGHT", 0, 0)
	needsHint:SetWordWrap(false)
	needsHint:SetText(L.RAID_NEEDS_HINT)

	local function SetClassRoles(class, roles)
		local draft = Draft()
		local possible = C.ClassRoles(class.key)
		roles = C.CommonBits(roles, possible) > 0 and roles or 0
		draft.classes = C.SetBit(draft.classes or 0, C.ClassBit(class.id), roles > 0)
		draft.classRoles = C.SetClassRoles(draft.classRoles, class.id, roles == possible and 0 or roles)
	end

	-- The roles of the wanted classes become the ad's wanted roles.
	local function NeedsChanged()
		local draft = Draft()
		if (draft.classes or 0) > 0 then
			local roles = 0
			for _, class in ipairs(C.GetClasses()) do
				local wanted = C.WantedRoles({ cl = draft.classes, cr = draft.classRoles }, class)
				for _, role in ipairs(C.ROLES) do
					if C.HasBit(wanted, role.bit) then
						roles = C.SetBit(roles, role.bit, true)
					end
				end
			end
			draft.roles = roles
		end
		tab:UpdateRaid()
		Changed()
	end

	local classes = C.GetClasses()
	local half = math.ceil(#classes / 2)
	local halfWidth = (CONTENT_WIDTH - 16) / 2
	local nameWidth = halfWidth - #C.ROLES * (CELL_W + 6)
	controls.cells = {}
	controls.columns = {}
	local gridTop = needsTop - 20
	for column = 1, 2 do
		local left = (column - 1) * (halfWidth + 16)
		for r, role in ipairs(C.ROLES) do
			local head = CreateFrame("Button", nil, secRaid)
			head:SetSize(CELL_W, 16)
			head:SetPoint("TOPLEFT", left + nameWidth + (r - 1) * (CELL_W + 6), gridTop)
			local icon = W.RoleIcon(head, 16, role.bit)
			icon:SetPoint("CENTER")
			head:SetScript("OnClick", function()
				-- Whole column: on unless every class that can is already on.
				local draft = Draft()
				local all = true
				for _, class in ipairs(classes) do
					if C.HasBit(C.ClassRoles(class.key), role.bit)
						and not C.HasBit(C.WantedRoles({ cl = draft.classes, cr = draft.classRoles }, class), role.bit) then
						all = false
					end
				end
				for _, class in ipairs(classes) do
					if C.HasBit(C.ClassRoles(class.key), role.bit) then
						local current = C.WantedRoles({ cl = draft.classes, cr = draft.classRoles }, class)
						SetClassRoles(class, C.SetBit(current, role.bit, not all))
					end
				end
				NeedsChanged()
			end)
			W.Tooltip(head, role.label, L.COLUMN_TIP)
		end
	end
	for i, class in ipairs(classes) do
		local column = i <= half and 1 or 2
		local row = column == 1 and i or i - half
		local left = (column - 1) * (halfWidth + 16)
		local y = gridTop - 18 - (row - 1) * ROW_H
		local line = secRaid:CreateTexture(nil, "BACKGROUND")
		line:SetColorTexture(1, 1, 1, 0.05)
		line:SetPoint("TOPLEFT", left, y + 2)
		line:SetSize(halfWidth, 1)
		local icon = W.ClassIcon(secRaid, 16)
		icon:SetClass(class.key)
		icon:SetPoint("TOPLEFT", left, y - 2)
		local name = W.Text(secRaid, "GameFontHighlightSmall")
		name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
		name:SetWidth(nameWidth - 26)
		name:SetWordWrap(false)
		name:SetText("|c" .. W.ClassColorHex(class.key) .. class.label .. "|r")
		local possible = C.ClassRoles(class.key)
		for r, role in ipairs(C.ROLES) do
			local cx = left + nameWidth + (r - 1) * (CELL_W + 6)
			if C.HasBit(possible, role.bit) then
				local cell = CreateFrame("Button", nil, secRaid, "BackdropTemplate")
				cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
				cell:SetSize(CELL_W, CELL_H)
				cell:SetPoint("TOPLEFT", cx, y)
				cell.check = W.Text(cell, "GameFontNormalSmall")
				cell.check:SetPoint("CENTER")
				cell.check:SetTextColor(0.1, 0.07, 0.02)
				cell.check:SetText(W.CHECK)
				cell.class, cell.bit = class, role.bit
				function cell:SetOn(on)
					self.check:SetShown(on)
					if on then
						self:SetBackdropColor(0.79, 0.635, 0.29, 1)
						self:SetBackdropBorderColor(1, 0.82, 0, 1)
					else
						self:SetBackdropColor(0.11, 0.11, 0.11, 1)
						self:SetBackdropBorderColor(0.26, 0.26, 0.26, 1)
					end
				end
				cell:SetScript("OnClick", function(self)
					local draft = Draft()
					local current = C.WantedRoles({ cl = draft.classes, cr = draft.classRoles }, class)
					SetClassRoles(class, C.SetBit(current, self.bit, not C.HasBit(current, self.bit)))
					NeedsChanged()
				end)
				cell:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_TOP")
					GameTooltip:SetText(class.label .. " · " .. role.label, 1, 1, 1)
					GameTooltip:Show()
				end)
				cell:SetScript("OnLeave", function()
					GameTooltip:Hide()
				end)
				controls.cells[#controls.cells + 1] = cell
			else
				local na = W.Text(secRaid, "GameFontDisableSmall")
				na:SetPoint("TOPLEFT", cx, y - 3)
				na:SetWidth(CELL_W)
				na:SetJustifyH("CENTER")
				na:SetText("–")
			end
		end
	end

	local summaryTop = gridTop - 18 - half * ROW_H - 6
	controls.needsSummary = W.Text(secRaid, "GameFontNormalSmall", W.TAG)
	controls.needsSummary:SetPoint("TOPLEFT", 0, summaryTop)
	local clearLink = W.LinkButton(secRaid, L.NEEDS_CLEAR, function()
		local draft = Draft()
		draft.classes, draft.classRoles = 0, nil
		NeedsChanged()
	end)
	clearLink:SetPoint("TOPRIGHT", secRaid, "TOPRIGHT", 0, summaryTop)
	local allLink = W.LinkButton(secRaid, L.NEEDS_ALL, function()
		local draft = Draft()
		draft.classes, draft.classRoles = 0, nil
		for _, class in ipairs(classes) do
			draft.classes = C.SetBit(draft.classes, C.ClassBit(class.id), true)
		end
		NeedsChanged()
	end)
	allLink:SetPoint("RIGHT", clearLink, "LEFT", -12, 0)
	secRaid:SetHeight(-summaryTop + 18)

	--------------------------------------------------------------------------
	-- Guild wizard: step bar and footer
	--------------------------------------------------------------------------

	local PAGE_LABELS = { general = L.WIZ_GENERAL, raid = L.WIZ_RAID }
	controls.wizChips = {}
	local wizBar = CreateFrame("Frame", nil, form)
	wizBar:SetPoint("TOPLEFT", 14, -48)
	wizBar:SetPoint("RIGHT", form, "RIGHT", -14, 0)
	wizBar:SetHeight(24)
	controls.wizBar = wizBar
	for i = 1, 2 do
		local chip = W.Chip(wizBar, function(self)
			tab.page = self.pageIndex
			tab:UpdateLayout()
		end)
		chip:SetHeight(22)
		controls.wizChips[i] = chip
	end
	local wizLine = form:CreateTexture(nil, "BORDER")
	wizLine:SetColorTexture(1, 1, 1, 0.08)
	wizLine:SetPoint("TOPLEFT", wizBar, "BOTTOMLEFT", 0, -6)
	wizLine:SetPoint("TOPRIGHT", wizBar, "BOTTOMRIGHT", 0, -6)
	wizLine:SetHeight(1)
	controls.wizLine = wizLine

	local footer = CreateFrame("Frame", nil, form)
	footer:SetPoint("BOTTOMLEFT", 14, 10)
	footer:SetPoint("BOTTOMRIGHT", -14, 10)
	footer:SetHeight(24)
	controls.footer = footer
	controls.back = W.Button(footer, L.BACK, 100, function()
		tab.page = math.max(1, (tab.page or 1) - 1)
		tab:UpdateLayout()
	end)
	controls.back:SetPoint("LEFT")
	controls.next = W.Button(footer, L.NEXT, 100, function()
		tab.page = (tab.page or 1) + 1
		tab:UpdateLayout()
	end)
	controls.next:SetPoint("RIGHT")
	controls.pageText = W.Text(footer, "GameFontDisableSmall")
	controls.pageText:SetPoint("CENTER")

	--------------------------------------------------------------------------
	-- Preview
	--------------------------------------------------------------------------

	local preview = W.Panel(content)
	preview:SetPoint("TOPRIGHT")
	preview:SetSize(SIDE_WIDTH, 214)
	controls.previewHeader = W.Header(preview, "", "GameFontNormalLarge")
	controls.previewHeader:SetPoint("TOPLEFT", 14, -14)

	local card = W.Panel(preview, { 0.1, 0.1, 0.1, 1 }, { 0.79, 0.635, 0.29, 1 })
	card:SetPoint("TOPLEFT", 12, -40)
	card:SetPoint("TOPRIGHT", -12, -40)
	card:SetHeight(112)
	controls.cardClass = W.ClassIcon(card, 36)
	controls.cardClass:SetPoint("TOPLEFT", 10, -10)
	controls.cardEmblem = W.GuildEmblem(card, 36)
	controls.cardEmblem:SetPoint("TOPLEFT", 10, -10)
	controls.cardName = W.Text(card, "GameFontNormal")
	controls.cardName:SetPoint("TOPLEFT", 54, -10)
	controls.cardName:SetPoint("RIGHT", -10, 0)
	controls.cardName:SetWordWrap(false)
	controls.cardText = W.Text(card, "GameFontHighlightSmall", W.TEXT)
	controls.cardText:SetPoint("TOPLEFT", controls.cardName, "BOTTOMLEFT", 0, -5)
	controls.cardText:SetPoint("RIGHT", -10, 0)
	controls.cardText:SetJustifyV("TOP")
	controls.cardText:SetMaxLines(3)
	controls.cardText:SetSpacing(2)
	controls.cardTags = W.GoalTags(card)
	controls.cardTags:SetPoint("BOTTOMLEFT", 54, 8)
	controls.cardStrip = W.WeekStrip(card, 8)
	controls.cardStrip:SetPoint("BOTTOMRIGHT", -10, 14)

	controls.matches = W.Text(preview, "GameFontHighlightSmall", W.MUTED)
	controls.matches:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2, -10)
	controls.matches:SetPoint("RIGHT", preview, "RIGHT", -14, 0)
	controls.matches:SetSpacing(2)

	--------------------------------------------------------------------------
	-- Publish
	--------------------------------------------------------------------------

	local side = W.Panel(content)
	side:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", 0, -GAP)
	side:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 0, -GAP)
	side:SetPoint("BOTTOM", content, "BOTTOM")

	controls.badge = W.Panel(side)
	controls.badge:SetHeight(22)
	controls.badge:SetPoint("TOPLEFT", 14, -14)
	controls.badgeDot = W.Dot(controls.badge, 8, W.GOLD)
	controls.badgeDot:SetPoint("LEFT", 8, 0)
	controls.badgeText = W.Text(controls.badge, "GameFontNormalSmall")
	controls.badgeText:SetPoint("LEFT", controls.badgeDot, "RIGHT", 6, 0)

	controls.info = W.Text(side, "GameFontHighlightSmall", W.MUTED)
	controls.info:SetPoint("TOPLEFT", controls.badge, "BOTTOMLEFT", 0, -8)
	controls.info:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.info:SetSpacing(3)

	local buttonWidth = SIDE_WIDTH - 28
	controls.publish = W.Button(side, L.PUBLISH, buttonWidth, function()
		local draft = Draft()
		draft.text = Ads.CleanText(controls.text:GetText())
		local ad, err
		if tab.mode == MODE_GUILD then
			ad, err = MyAds.PublishGuild(draft)
		else
			ad, err = MyAds.PublishPlayer(draft)
		end
		if ad then
			ns.db.settings.seenIntro = true
			ns:Print(L.PUBLISHED)
		else
			ns:Print(err)
		end
		tab:Refresh()
	end)
	controls.publish:SetPoint("TOPLEFT", controls.info, "BOTTOMLEFT", 0, -12)

	local function PublishedAd()
		if tab.mode == MODE_GUILD then
			return MyAds.GetGuildAd()
		end
		return MyAds.GetPlayerAd()
	end

	controls.discard = W.Button(side, L.DISCARD, (buttonWidth - 8) / 2, function()
		local ad = PublishedAd()
		if ad then
			local draft = Draft()
			draft.roles, draft.goals, draft.times, draft.lang, draft.text = ad.r or 0, ad.g, ad.t, ad.l, ad.x
			draft.moreLangs = ad.la
			if tab.mode == MODE_GUILD then
				MyAds.CopyRaid(draft, ad)
			end
			tab:Refresh()
		end
	end)
	controls.discard:SetPoint("TOPLEFT", controls.publish, "BOTTOMLEFT", 0, -8)
	controls.withdraw = W.Button(side, L.WITHDRAW, (buttonWidth - 8) / 2, function()
		if tab.mode == MODE_GUILD then
			MyAds.WithdrawGuild()
		else
			MyAds.WithdrawPlayer()
		end
		ns:Print(L.WITHDRAWN)
		tab:Refresh()
	end)
	controls.withdraw:SetPoint("TOPRIGHT", controls.publish, "BOTTOMRIGHT", 0, -8)

	controls.otherNote = W.Text(side, "GameFontDisableSmall")
	controls.otherNote:SetPoint("BOTTOMLEFT", 14, 14)
	controls.otherNote:SetPoint("RIGHT", side, "RIGHT", -14, 0)
	controls.otherNote:SetSpacing(2)

	--------------------------------------------------------------------------
	-- Updates
	--------------------------------------------------------------------------

	local function SetBadge(label, color)
		controls.badgeText:SetText(label)
		W.Color(controls.badgeText, color)
		controls.badgeDot:SetColor(color)
		controls.badge:SetBackdropColor(color[1] * 0.2, color[2] * 0.2, color[3] * 0.2, 1)
		controls.badge:SetBackdropBorderColor(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 1)
		controls.badge:SetWidth(controls.badgeText:GetStringWidth() + 30)
	end

	function tab:UpdatePublish()
		local ad = PublishedAd()
		local draft = Draft()
		local canEdit = self.mode == MODE_PLAYER or Ads.CanInvite()
		if ad then
			local dirty = not SameDraft(self.mode, draft, ad)
			if dirty then
				SetBadge(L.STATUS_CHANGED, W.GOLD)
			else
				SetBadge(L.STATUS_ACTIVE, W.GREEN)
			end
			local lines = {
				L.INFO_ACTIVE:format(W.Duration(GetServerTime() - ad.v), W.Duration(Ads.ExpiresIn(ad))),
			}
			if self.mode == MODE_GUILD then
				lines[#lines + 1] = L.INFO_CHANGED_BY:format(Ads.OwnerName(ad.o))
				lines[#lines + 1] = L.NOTE_GUILD_AD
			else
				lines[#lines + 1] = L.NOTE_RENEW
			end
			controls.info:SetText(table.concat(lines, "\n"))
			controls.publish:SetText(L.PUBLISH_CHANGES)
			controls.publish:SetEnabled(canEdit and dirty)
			controls.discard:SetEnabled(dirty)
			controls.withdraw:SetEnabled(canEdit)
		else
			SetBadge(L.STATUS_NOT_PUBLISHED, W.MUTED)
			controls.info:SetText(L.INFO_NOT_PUBLISHED .. "\n" .. (self.mode == MODE_GUILD and L.NOTE_GUILD_AD or L.NOTE_RENEW))
			controls.publish:SetText(L.PUBLISH)
			controls.publish:SetEnabled(canEdit)
			controls.discard:SetEnabled(false)
			controls.withdraw:SetEnabled(false)
		end
	end

	function tab:UpdatePreview()
		local draft = Draft()
		local text = Ads.CleanText(draft.text or "")
		if self.mode == MODE_GUILD then
			controls.cardClass:Hide()
			controls.cardEmblem:Show()
			local guild = Ads.GetGuild() or "?"
			controls.cardEmblem:SetGuild(guild, Ads.GetFactionCode())
			local style = HasRaid(self.mode, draft) and C.StyleName(draft.style)
			controls.cardName:SetText("|cffffd100" .. guild .. "|r" .. (style and ("  |cff9d9d9d" .. style .. "|r") or ""))
		else
			controls.cardEmblem:Hide()
			controls.cardClass:Show()
			local _, classFile = UnitClass("player")
			controls.cardClass:SetClass(classFile)
			controls.cardName:SetText("|c" .. W.ClassColorHex(classFile) .. Ads.OwnerName(ns:GetPlayerFullName() or "?")
				.. "|r  |cff9d9d9d" .. C.ClassName(classFile) .. " · " .. UnitLevel("player") .. "|r")
		end
		controls.cardText:SetText(text ~= "" and text or ("|cff9d9d9d" .. L.NO_TEXT .. "|r"))
		controls.cardTags:SetGoals(draft.goals)
		controls.cardStrip:SetMask(draft.times)

		-- What the other side has on offer, scored against the draft.
		local otherKind = self.mode == MODE_GUILD and Ads.KIND_PLAYER or Ads.KIND_GUILD
		local faction = Ads.GetFactionCode()
		local filter = { kind = otherKind, factions = { [faction] = true }, sameMode = true }
		local profile = {
			goals = draft.goals or 0, times = draft.times or 0, roles = draft.roles or 0, lang = draft.lang,
			moreLangs = draft.moreLangs,
			classes = HasRaid(self.mode, draft) and draft.classes or 0,
			classRoles = HasRaid(self.mode, draft) and draft.classRoles or nil,
			classId = self.mode == MODE_PLAYER and select(3, UnitClass("player")) or nil,
		}
		local results = Search.Run(filter, profile)
		local good = 0
		for _, result in ipairs(results) do
			if (result.score or 0) >= VERY_GOOD then
				good = good + 1
			end
		end
		local format = self.mode == MODE_GUILD and L.PREVIEW_MATCHES_PLAYERS or L.PREVIEW_MATCHES_GUILDS
		controls.matches:SetText(format:format(#results, good))
	end

	-- Guild ads with the raid goal get two pages (the ad, the raid); all
	-- other ads are one page.
	local function Pages(mode, draft)
		if HasRaid(mode, draft) then
			return { "general", "raid" }
		end
	end

	local function SectionDone(key, draft)
		if key == "roles" then
			return (draft.roles or 0) > 0
		elseif key == "goals" then
			return (draft.goals or 0) > 0 and draft.lang ~= nil
		elseif key == "raid" then
			return draft.style ~= nil or (draft.raidDays or 0) > 0 or (draft.classes or 0) > 0
		elseif key == "times" then
			return (draft.times or 0) > 0
		elseif key == "general" then
			return (draft.goals or 0) > 0
		end
		return Ads.CleanText(draft.text or "") ~= ""
	end

	local function Place(section, y)
		section:ClearAllPoints()
		section:SetPoint("TOPLEFT", form, "TOPLEFT", 14, y)
		section:SetPoint("RIGHT", form, "RIGHT", -14, 0)
		section:Show()
	end

	function tab:UpdateSteps()
		local draft = Draft()
		for key, section in pairs(controls.sections) do
			section.circle:SetDone(SectionDone(key, draft))
		end
		local pages = Pages(self.mode, draft)
		if pages then
			self.page = math.max(1, math.min(self.page or 1, #pages))
			for i, chip in ipairs(controls.wizChips) do
				local key = pages[i]
				if key then
					chip:SetLabel((SectionDone(key, draft) and W.CHECK .. " " or (i .. "  ")) .. PAGE_LABELS[key])
					chip:SetActive(i == self.page)
				end
			end
		end
	end

	-- One page of four numbered sections; a raid guild ad drops the roles
	-- (the needs table sets them) and moves the raid to a second page, with
	-- the page bar on top and back/next below.
	-- Shows exactly the given sections ({ key = y }). Sections that stay
	-- visible are not hidden in between: that would take the focus from the
	-- text field on every keystroke.
	local function ShowSections(visible)
		for key, section in pairs(controls.sections) do
			if visible[key] then
				Place(section, visible[key])
			else
				section:Hide()
			end
		end
	end

	function tab:UpdateLayout()
		self:UpdateSteps()
		local draft = Draft()
		local sections = controls.sections
		local pages = Pages(self.mode, draft)
		controls.wizBar:SetShown(pages ~= nil)
		controls.wizLine:SetShown(pages ~= nil)
		controls.footer:SetShown(pages ~= nil)
		if not pages then
			local order = { { "roles", -52 }, { "goals", -122 }, { "times", -192 }, { "text", -310 } }
			local visible = {}
			for i, entry in ipairs(order) do
				sections[entry[1]]:SetNumbered(i)
				visible[entry[1]] = entry[2]
			end
			ShowSections(visible)
			return
		end

		self.page = math.max(1, math.min(self.page or 1, #pages))
		local left = 0
		for i, chip in ipairs(controls.wizChips) do
			chip:SetShown(pages[i] ~= nil)
			if pages[i] then
				chip:ClearAllPoints()
				chip:SetPoint("LEFT", controls.wizBar, "LEFT", left, 0)
				left = left + chip:GetWidth() + 6
				chip.pageIndex = i
			end
		end
		if pages[self.page] == "raid" then
			ShowSections({ raid = PAGE_TOP })
		else
			local order = { { "goals", PAGE_TOP }, { "times", PAGE_TOP - 70 }, { "text", PAGE_TOP - 188 } }
			local visible = {}
			for i, entry in ipairs(order) do
				sections[entry[1]]:SetNumbered(i)
				visible[entry[1]] = entry[2]
			end
			ShowSections(visible)
		end
		controls.back:SetEnabled(self.page > 1)
		controls.next:SetShown(self.page < #pages)
		controls.pageText:SetText(L.WIZ_STEP:format(self.page, #pages))
	end

	function tab:UpdateRaid()
		local draft = Draft()
		for _, styleCard in ipairs(controls.styles) do
			styleCard:SetActive(draft.style == styleCard.value)
		end
		for _, chip in ipairs(controls.raidDays) do
			chip:SetActive(C.HasBit(draft.raidDays or 0, chip.bit))
		end
		local wanted = { cl = draft.classes, cr = draft.classRoles }
		for _, cell in ipairs(controls.cells) do
			cell:SetOn(C.HasBit(C.WantedRoles(wanted, cell.class), cell.bit))
		end
		if (draft.classes or 0) == 0 then
			controls.needsSummary:SetText(L.ANY_CLASS)
		else
			local needs = C.NeedsByRole(wanted)
			local parts = { L.NEEDS_LABEL }
			for _, role in ipairs(C.ROLES) do
				parts[#parts + 1] = ("%s %s"):format(role.label, L.NEEDS_COUNT:format(#needs[role.bit]))
			end
			controls.needsSummary:SetText(table.concat(parts, "  "))
		end
		controls.perWeek:Refresh()
		controls.raidStart:Refresh()
		controls.raidEnd:Refresh()
	end

	-- Everything that follows the form while typing.
	function tab:UpdateLive()
		self:UpdateLayout()
		self:UpdatePreview()
		self:UpdatePublish()
	end

	function tab:Refresh()
		local guild = Ads.GetGuild()
		local canInvite = Ads.CanInvite()
		local guildAllowed = guild ~= nil and canInvite
		controls.guildMode:SetEnabled(guildAllowed)
		controls.guildMode:SetAlpha(guildAllowed and 1 or 0.5)
		if self.mode == MODE_GUILD and not guildAllowed then
			self.mode = MODE_PLAYER
		end
		if self.mode == MODE_GUILD and not self.guildDraft then
			self.guildDraft = MyAds.GetGuildDraft()
		end
		controls.playerMode:SetActive(self.mode == MODE_PLAYER)
		controls.guildMode:SetActive(self.mode == MODE_GUILD)

		local draft = Draft()
		local faction = Filters.FactionName(Ads.GetFactionCode())
		local sections = controls.sections
		if self.mode == MODE_GUILD then
			local members = GetNumGuildMembers()
			controls.identity:SetText("|cffffd100<" .. guild .. ">|r · " .. faction
				.. ((members or 0) > 0 and (" · " .. L.MEMBERS:format(members)) or "") .. " " .. L.GUILD_LOCKED)
			sections.roles.header:SetText(L.STEP_ROLES_GUILD)
			sections.roles.hint:SetText(L.STEP_ROLES_GUILD_HINT)
			sections.goals.header:SetText(L.STEP_GOALS_GUILD)
			sections.times.header:SetText(L.STEP_TIMES_GUILD)
			sections.text.header:SetText(L.STEP_TEXT_GUILD)
			controls.previewHeader:SetText(L.PREVIEW_GUILD)
			controls.otherNote:SetText(L.NOTE_OTHER_PLAYER)
		else
			local name = ns:GetPlayerFullName() or "?"
			local _, classFile = UnitClass("player")
			controls.identity:SetText("|c" .. W.ClassColorHex(classFile) .. Ads.OwnerName(name) .. "|r · "
				.. C.ClassName(classFile) .. " " .. UnitLevel("player") .. " · " .. faction .. " · "
				.. (guild and ("<" .. guild .. ">") or L.NO_GUILD) .. " " .. L.FROM_CHARACTER)
			sections.roles.header:SetText(L.STEP_ROLES)
			sections.roles.hint:SetText(L.STEP_ROLES_HINT)
			sections.goals.header:SetText(L.STEP_GOALS)
			sections.times.header:SetText(L.STEP_TIMES)
			sections.text.header:SetText(L.STEP_TEXT)
			controls.previewHeader:SetText(L.PREVIEW_PLAYER)
			controls.otherNote:SetText(guild and (canInvite and L.NOTE_OTHER_GUILD_CAN or L.NOTE_OTHER_GUILD_CANNOT)
				or L.NOTE_OTHER_GUILD_NONE)
		end
		sections.times.hint:SetText(self.mode == MODE_GUILD and L.STEP_TIMES_GUILD_HINT or L.STEP_TIMES_HINT)
		sections.raid.header:SetText(L.STEP_RAID)

		local classRoles = self.mode == MODE_PLAYER and C.ClassRoles(select(2, UnitClass("player"))) or 7
		for _, pill in ipairs(controls.roles) do
			local possible = C.HasBit(classRoles, pill.bit)
			if not possible and C.HasBit(draft.roles, pill.bit) then
				draft.roles = C.SetBit(draft.roles, pill.bit, false)
			end
			pill:SetActive(C.HasBit(draft.roles, pill.bit))
			pill:SetAllowed(possible)
		end
		for _, chip in ipairs(controls.goals) do
			chip:SetActive(C.HasBit(draft.goals, chip.bit))
		end
		controls.lang:Refresh()
		self:UpdateRaid()
		controls.grid:SetMask(draft.times)
		controls.text:SetText(draft.text)
		self:UpdateLive()
	end

	-- Keeps the form as typed; only status and preview follow new versions.
	function tab:OnAdsChanged()
		self:UpdatePreview()
		self:UpdatePublish()
	end

	return tab
end

UI.RegisterTab(3, L.TAB_MY_AD, Build)
