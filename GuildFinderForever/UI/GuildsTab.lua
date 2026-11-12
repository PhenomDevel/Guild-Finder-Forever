-- luacheck: read globals CreateScrollBoxListLinearView ScrollUtil CreateDataProvider UnitClass UnitLevel GameTooltip
local _, ns = ...

-- "Find guilds" tab: status banner of the own player ad, search + filter
-- chips + sort, and the guild ads as a two-column card grid. A first-run
-- screen explains the addon until the player has seen it once.
local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local Store = ns.Store
local MyAds = ns.MyAds
local Filters = ns.Filters
local Presence = ns.Presence

local KIND = Ads.KIND_GUILD
local BANNER_HEIGHT = 30
local CARD_HEIGHT = 132
local CARD_GAP = 6
local REWATCH_INTERVAL = 60

local function GuildCount()
	local count = 0
	for _ in Store.Each(KIND) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- Banner
--------------------------------------------------------------------------------

local function BuildBanner(tab, content)
	local banner = W.Panel(content)
	banner:SetPoint("TOPLEFT")
	banner:SetPoint("TOPRIGHT")
	banner:SetHeight(BANNER_HEIGHT)
	local icon = banner:CreateTexture(nil, "ARTWORK")
	icon:SetSize(16, 16)
	icon:SetPoint("LEFT", 10, 0)
	local text = W.Text(banner, "GameFontHighlight")
	text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	text:SetPoint("RIGHT", -120, 0)
	text:SetWordWrap(false)
	local button = W.Button(banner, L.EDIT, 100, function()
		UI.Show(3)
	end)
	button:SetPoint("RIGHT", -4, 0)

	function tab:UpdateBanner()
		local ad = MyAds.GetPlayerAd()
		if ad then
			banner:SetBackdropColor(0.07, 0.13, 0.05, 1)
			banner:SetBackdropBorderColor(0.2, 0.4, 0.15, 1)
			icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
			local _, classFile = UnitClass("player")
			text:SetText(L.BANNER_ACTIVE:format(Ads.OwnerName(ad.o), C.ClassName(classFile), UnitLevel("player"),
				W.Duration(Ads.ExpiresIn(ad))))
			button:SetText(L.EDIT)
		else
			banner:SetBackdropColor(0.13, 0.1, 0.04, 1)
			banner:SetBackdropBorderColor(0.45, 0.36, 0.16, 1)
			icon:SetTexture("Interface\\COMMON\\help-i")
			text:SetText(L.BANNER_NONE)
			button:SetText(L.CREATE_AD)
		end
	end
end

--------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------

-- Card layout, top to bottom: header (emblem, name, meta line over the full
-- width), raid plan row (style + schedule, only when given), wanted row,
-- description filling the remaining lines, footer (goal tags left, score
-- right).
local PAD = 10
local BODY_Y = -44
local PLAN_HEIGHT = 18
local NEEDS_HEIGHT = 16
local ROW_GAP = 4
local FOOTER_HEIGHT = 18
local TEXT_SPACING = 2
local TEXT_MAX_LINES = 4
local GROUP_GAP = 12

-- Card tooltip: match score, outdated notice, and for raid guilds the wanted
-- classes per role, own class marked.
local function ShowCardTooltip(card)
	local result = card.result
	local ad = result and result.ad
	if not ad then
		return
	end
	GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
	GameTooltip:SetText(ad.n, W.GOLD[1], W.GOLD[2], W.GOLD[3])
	if not result.own and result.score then
		local color = W.ScoreColor(result.score)
		GameTooltip:AddLine(result.score .. " % " .. L.FITS_YOU, color[1], color[2], color[3])
	end
	if not result.own and Ads.IsStale(ad) then
		GameTooltip:AddLine(W.StaleText(ad))
		GameTooltip:AddLine(L.STALE_TIP, 1, 1, 1, true)
	end
	if C.HasBit(ad.g or 0, C.GOAL_RAID) and (ad.cl or 0) > 0 then
		local _, myClass = UnitClass("player")
		local needs = C.NeedsByRole(ad)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.RAID_NEEDS, 1, 1, 1)
		for _, role in ipairs(C.ROLES) do
			local names = {}
			for _, class in ipairs(needs[role.bit]) do
				local name = "|c" .. W.ClassColorHex(class.key) .. class.label .. "|r"
				names[#names + 1] = class.key == myClass and (W.CHECK .. name) or name
			end
			if #names > 0 then
				GameTooltip:AddLine(role.label .. " (" .. #names .. ")", W.GOLD[1], W.GOLD[2], W.GOLD[3])
				GameTooltip:AddLine(table.concat(names, ", "), 1, 1, 1, true)
			end
		end
	end
	GameTooltip:Show()
end

local function BuildCard(tab, row)
	local card = CreateFrame("Button", nil, row, "BackdropTemplate")
	card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	card:SetBackdropColor(0.1, 0.1, 0.1, 1)
	card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
	card:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
	card:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.05)

	-- Faction stripe along the left edge.
	card.stripe = card:CreateTexture(nil, "BORDER")
	card.stripe:SetPoint("TOPLEFT", 1, -1)
	card.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	card.stripe:SetWidth(3)
	card.emblem = W.GuildEmblem(card, 32)
	card.emblem:SetPoint("TOPLEFT", PAD + 2, -8)
	-- Online status of the poster, the one "Whisper" in the details reaches.
	card.status = W.StatusDot(card.emblem)

	card.name = W.Text(card, "GameFontNormalLarge", W.GOLD)
	card.name:SetPoint("TOPLEFT", card.emblem, "TOPRIGHT", 8, 0)
	card.name:SetPoint("RIGHT", -PAD, 0)
	card.name:SetWordWrap(false)
	card.meta = W.Text(card, "GameFontDisableSmall")
	card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.meta:SetPoint("RIGHT", -PAD, 0)
	card.meta:SetWordWrap(false)

	-- Raid plan row: style tag and schedule.
	card.plan = CreateFrame("Frame", nil, card)
	card.plan:SetHeight(PLAN_HEIGHT)
	card.style = W.Tag(card.plan)
	card.style:SetPoint("LEFT")
	card.schedule = W.Text(card.plan, "GameFontHighlightSmall", W.TEXT)
	card.schedule:SetPoint("RIGHT")
	card.schedule:SetJustifyH("LEFT")
	card.schedule:SetWordWrap(false)

	-- Wanted row: number of wanted classes per role (names in the tooltip),
	-- or the wanted roles, and whether your class fits.
	card.needs = CreateFrame("Frame", nil, card)
	card.needs:SetHeight(NEEDS_HEIGHT)
	card.needsLabel = W.Text(card.needs, "GameFontDisableSmall")
	card.needsLabel:SetPoint("LEFT")
	card.roleIcons, card.roleCounts = {}, {}
	for i, role in ipairs(C.ROLES) do
		card.roleIcons[i] = W.RoleIcon(card.needs, 16, role.bit)
		card.roleCounts[i] = W.Text(card.needs, "GameFontHighlightSmall")
	end
	card.fit = W.Text(card.needs, "GameFontHighlightSmall")
	card.fit:SetPoint("RIGHT")
	card.fit:SetWordWrap(false)

	card.text = W.Text(card, "GameFontHighlightSmall", W.TEXT)
	card.text:SetJustifyV("TOP")
	card.text:SetSpacing(TEXT_SPACING)

	card.tags = W.GoalTags(card)
	card.tags:SetPoint("BOTTOMLEFT", PAD + 2, 8)
	card.score = W.Text(card, "GameFontNormalLarge")
	card.score:SetPoint("BOTTOMRIGHT", -PAD, 8)
	card.scoreLabel = W.Text(card, "GameFontDisableSmall")
	card.scoreLabel:SetPoint("BOTTOMRIGHT", card.score, "BOTTOMLEFT", -4, 1)
	card.scoreLabel:SetText(L.FITS_YOU)

	card:SetScript("OnClick", function(self)
		if self.result then
			tab:Open(self.result)
		end
	end)
	card:SetScript("OnEnter", ShowCardTooltip)
	card:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Role icon and class count per role, or "any class" when the guild
	-- names none. Without a class list: "any class as" plus the wanted
	-- roles' icons, or only "all classes welcome" when every role is wanted.
	function card:LayoutNeeds(ad)
		local needs = (ad.cl or 0) > 0 and C.NeedsByRole(ad)
		local roles = not needs and ad.r or 0
		local someRoles = roles > 0 and roles ~= C.ALL_ROLES
		local label = L.NEEDS_LABEL
		if not needs then
			label = label .. " |cff9d9d9d" .. (someRoles and L.ANY_CLASS_AS or L.ANY_CLASS) .. "|r"
		end
		self.needsLabel:SetText(label)
		local x = self.needsLabel:GetStringWidth() + 6
		for i, role in ipairs(C.ROLES) do
			local count = needs and #needs[role.bit] or 0
			local shown = count > 0 or (someRoles and C.HasBit(roles, role.bit))
			local icon, text = self.roleIcons[i], self.roleCounts[i]
			icon:SetShown(shown)
			text:SetShown(count > 0)
			if shown then
				icon:ClearAllPoints()
				icon:SetPoint("LEFT", x, 0)
				x = x + 16 + GROUP_GAP / 2
			end
			if count > 0 then
				text:ClearAllPoints()
				text:SetPoint("LEFT", icon, "RIGHT", 3, 0)
				text:SetText(count)
				x = x + 3 + text:GetStringWidth() + GROUP_GAP / 2
			end
		end
	end

	-- Places a body row below the previous one; returns the next free y.
	function card:PlaceRow(frame, y, height)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", PAD + 2, y)
		frame:SetPoint("RIGHT", -PAD, 0)
		frame:Show()
		return y - height - ROW_GAP
	end

	function card:UpdatePresence()
		local result = self.result
		local online
		if result and not result.own then
			online = Presence.IsOnline(result.ad.o)
		end
		self.status:SetOnline(online)
	end

	-- Raid style and schedule; false when the ad gives neither.
	function card:SetPlan(ad)
		local style = C.StyleName(ad.ps)
		self.style:SetShown(style ~= nil)
		if style then
			self.style:SetLabel(style)
		end
		local schedule = {}
		if (ad.rd or 0) > 0 then
			schedule[#schedule + 1] = "|cffffffff" .. C.DaysText(ad.rd) .. "|r"
		end
		local time = C.RaidTimeText(ad)
		if time and time ~= "" then
			schedule[#schedule + 1] = time
		end
		if ad.rn then
			schedule[#schedule + 1] = "|cff9d9d9d" .. L.PER_WEEK:format(ad.rn) .. "|r"
		end
		self.schedule:SetText(table.concat(schedule, "   "))
		self.schedule:SetPoint("LEFT", style and self.style or self.plan, style and "RIGHT" or "LEFT", style and 8 or 0, 0)
		return style ~= nil or #schedule > 0
	end

	function card:SetFit(ad)
		local fit, roles = Filters.ClassFit(ad)
		if fit == "fit" then
			local _, classFile = UnitClass("player")
			local label = C.ClassName(classFile)
			if roles ~= C.ClassRoles(classFile) then
				label = label .. " · " .. C.RoleNames(roles)
			end
			self.fit:SetText(W.CHECK .. " |cff1eff00" .. label .. "|r")
		elseif fit == "no" then
			self.fit:SetText("|cff9d9d9d" .. L.FIT_NO_SHORT .. "|r")
		end
		self.fit:SetShown(fit ~= nil)
	end

	function card:SetResult(result)
		self.result = result
		if not result then
			self:Hide()
			return
		end
		local ad = result.ad
		self:Show()
		self.emblem:SetGuild(ad.n, ad.f)
		self:UpdatePresence()
		local faction = W.FACTION[ad.f]
		self.stripe:SetShown(faction ~= nil)
		if faction then
			self.stripe:SetColorTexture(faction.color[1], faction.color[2], faction.color[3], 1)
		end
		self.name:SetText(ad.n)
		local meta = { W.FactionText(ad.f, Filters.FactionName(ad.f)), Filters.LanguagesText(ad) }
		if ad.gm then
			meta[#meta + 1] = L.MEMBERS:format(ad.gm)
		end
		local age = L.AGO:format(W.Duration(GetServerTime() - ad.v))
		local stale = not result.own and Ads.IsStale(ad)
		if stale then
			age = "|c" .. W.STALE_HEX .. L.STALE .. " · " .. age .. "|r"
		end
		-- Outdated first: the meta line may be cut off on the right.
		table.insert(meta, stale and 1 or #meta + 1, age)
		self.meta:SetText(table.concat(meta, " · "))
		self:SetAlpha(stale and W.STALE_ALPHA or 1)

		-- Body rows: empty ones are left out and the description moves up.
		local y = BODY_Y
		local raid = C.HasBit(ad.g or 0, C.GOAL_RAID)
		self.plan:Hide()
		if raid and self:SetPlan(ad) then
			y = self:PlaceRow(self.plan, y, PLAN_HEIGHT)
		end
		-- Outside raids only worth a row when the guild limits the roles.
		local roles = ad.r or 0
		self.needs:Hide()
		if raid or (roles > 0 and roles ~= C.ALL_ROLES) then
			self:LayoutNeeds(ad)
			self:SetFit(ad)
			y = self:PlaceRow(self.needs, y, NEEDS_HEIGHT)
		end

		local textTop = y + ROW_GAP - 2
		local textBottom = -(CARD_HEIGHT - 8 - FOOTER_HEIGHT - ROW_GAP)
		local _, fontHeight = self.text:GetFont()
		local lineHeight = math.floor((fontHeight or 10) + 0.5) + TEXT_SPACING
		local lines = math.min(TEXT_MAX_LINES, math.floor((textTop - textBottom + TEXT_SPACING) / lineHeight))
		self.text:ClearAllPoints()
		self.text:SetPoint("TOPLEFT", PAD + 2, textTop)
		self.text:SetPoint("RIGHT", -PAD, 0)
		self.text:SetMaxLines(math.max(1, lines))
		self.text:SetText(ad.x or "")
		self.text:SetShown(lines > 0 and (ad.x or "") ~= "")

		local tagsRight = self.tags:SetGoals(ad.g)
		if result.own then
			self.score:SetText(L.OWN_GUILD)
			W.Color(self.score, W.GOLD)
		elseif result.score then
			self.score:SetText(result.score .. " %")
			W.Color(self.score, W.ScoreColor(result.score))
		end
		self.score:SetShown(result.own or result.score ~= nil)
		-- The label gives way to wide goal tags; the tooltip still has it.
		local width = self:GetWidth()
		local free = width - 2 * PAD - 2 - tagsRight - self.score:GetStringWidth() - 4
		self.scoreLabel:SetShown(not result.own and result.score ~= nil
			and (width == 0 or self.scoreLabel:GetStringWidth() + 12 <= free))

		if ad.i == tab.selectedId then
			self:SetBackdropBorderColor(0.79, 0.635, 0.29, 1)
		else
			self:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
		end
	end
	return card
end

local function BuildGrid(tab, panel)
	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 8, -8)
	scrollBox:SetPoint("BOTTOMRIGHT", -22, 8)
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(CARD_HEIGHT + CARD_GAP)
	view:SetElementInitializer("Frame", function(row, pair)
		if not row.cards then
			row.cards = { BuildCard(tab, row), BuildCard(tab, row) }
			row.cards[1]:SetPoint("TOPLEFT")
			row.cards[1]:SetPoint("BOTTOMRIGHT", row, "BOTTOM", -CARD_GAP / 2, CARD_GAP)
			row.cards[2]:SetPoint("TOPLEFT", row, "TOP", CARD_GAP / 2, 0)
			row.cards[2]:SetPoint("BOTTOMRIGHT", 0, CARD_GAP)
		end
		row.cards[1]:SetResult(pair[1])
		row.cards[2]:SetResult(pair[2])
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	local empty = W.Text(panel, "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetJustifyH("CENTER")
	empty:SetWidth(420)

	-- Only while the tab is shown: pings every listed poster, top first;
	-- once a minute again for those whose status expired.
	local rewatch
	function tab:WatchPresence()
		if not panel:IsVisible() then
			return
		end
		rewatch = rewatch or C_Timer.NewTicker(REWATCH_INTERVAL, function()
			tab:UpdatePresence()
			tab:WatchPresence()
		end)
		local owners = {}
		for _, result in ipairs(self.results or {}) do
			if not result.own then
				owners[#owners + 1] = result.ad.o
			end
		end
		Presence.Watch(owners, tab)
	end

	function tab:UpdatePresence()
		scrollBox:ForEachFrame(function(row)
			if row.cards then
				row.cards[1]:UpdatePresence()
				row.cards[2]:UpdatePresence()
			end
		end)
	end

	panel:SetScript("OnShow", function()
		tab:WatchPresence()
	end)
	panel:SetScript("OnHide", function()
		if rewatch then
			rewatch:Cancel()
			rewatch = nil
		end
		Presence.StopWatching(tab)
	end)
	ns.RegisterCallback(tab, "GFF_PRESENCE_CHANGED", function()
		if panel:IsVisible() then
			tab:UpdatePresence()
		end
	end)

	function tab:SetResults(results)
		self.results = results
		local rows = {}
		for i = 1, #results, 2 do
			rows[#rows + 1] = { results[i], results[i + 1] }
		end
		scrollBox:SetDataProvider(CreateDataProvider(rows), true)
		self:WatchPresence()
		empty:SetShown(#results == 0)
		empty:SetText(GuildCount() == 0 and L.NO_ADS_YET or L.NO_RESULTS)
	end

	function tab:RepaintCards()
		scrollBox:ForEachFrame(function(row)
			if row.cards then
				row.cards[1]:SetResult(row.cards[1].result)
				row.cards[2]:SetResult(row.cards[2].result)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- First-run screen
--------------------------------------------------------------------------------

local function BuildIntro(tab, content)
	local intro = W.Panel(content)
	intro:SetAllPoints()
	intro:Hide()

	local icon = intro:CreateTexture(nil, "ARTWORK")
	icon:SetSize(56, 56)
	icon:SetPoint("TOP", 0, -36)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local title = W.Text(intro, "GameFontNormalHuge", W.GOLD)
	title:SetPoint("TOP", icon, "BOTTOM", 0, -16)
	title:SetText(L.INTRO_TITLE)
	local sub = W.Text(intro, "GameFontHighlight", W.MUTED)
	sub:SetPoint("TOP", title, "BOTTOM", 0, -10)
	sub:SetWidth(560)
	sub:SetJustifyH("CENTER")
	sub:SetText(L.INTRO_TEXT)

	local syncBox = W.Panel(intro, { 0.08, 0.08, 0.08, 1 }, { 0.25, 0.25, 0.25, 1 })
	syncBox:SetSize(420, 26)
	syncBox:SetPoint("TOP", sub, "BOTTOM", 0, -16)
	local syncDot = W.Dot(syncBox, 8, W.GOLD)
	syncDot:SetPoint("LEFT", 12, 0)
	local syncText = W.Text(syncBox, "GameFontHighlightSmall", W.TEXT)
	syncText:SetPoint("LEFT", syncDot, "RIGHT", 8, 0)
	local syncCount = W.Text(syncBox, "GameFontHighlightSmall", W.WHITE)
	syncCount:SetPoint("RIGHT", -12, 0)

	local steps = {
		{ L.INTRO_STEP1_TITLE, L.INTRO_STEP1_TEXT },
		{ L.INTRO_STEP2_TITLE, L.INTRO_STEP2_TEXT },
		{ L.INTRO_STEP3_TITLE, L.INTRO_STEP3_TEXT },
	}
	local stepWidth, stepGap = 210, 12
	local totalWidth = #steps * stepWidth + (#steps - 1) * stepGap
	for i, step in ipairs(steps) do
		local box = W.Panel(intro, { 0.1, 0.1, 0.1, 1 }, { 0.25, 0.25, 0.25, 1 })
		box:SetSize(stepWidth, 108)
		box:SetPoint("TOPLEFT", syncBox, "BOTTOM", -totalWidth / 2 + (i - 1) * (stepWidth + stepGap), -18)
		local circle = W.StepCircle(box, i, 24)
		circle:SetPoint("TOPLEFT", 12, -12)
		local header = W.Header(box, step[1], "GameFontNormalLarge")
		header:SetPoint("TOPLEFT", circle, "BOTTOMLEFT", 0, -8)
		local text = W.Text(box, "GameFontHighlightSmall", W.MUTED)
		text:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
		text:SetPoint("RIGHT", -12, 0)
		text:SetSpacing(2)
		text:SetText(step[2])
	end

	local create = W.Button(intro, L.INTRO_CREATE, 190, function()
		ns.db.settings.seenIntro = true
		UI.Show(3)
	end)
	create:SetPoint("TOPRIGHT", syncBox, "BOTTOM", -6, -144)
	local browse = W.Button(intro, L.INTRO_BROWSE, 150, function()
		ns.db.settings.seenIntro = true
		tab:Refresh()
	end)
	browse:SetPoint("LEFT", create, "RIGHT", 12, 0)

	function tab:UpdateIntro()
		local count = Store.Count()
		if ns.Channel.ready then
			syncDot:SetColor(W.GOLD)
			syncText:SetText(L.INTRO_SYNCING)
		else
			syncDot:SetColor({ 0.8, 0.2, 0.1 })
			syncText:SetText(L.STATUS_DISCONNECTED)
		end
		syncCount:SetText(L.INTRO_COUNT:format(count))
	end

	return intro
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

local function Build(content)
	local tab = {}

	local main = CreateFrame("Frame", nil, content)
	main:SetAllPoints()
	BuildBanner(tab, main)

	local function Changed()
		tab:Refresh()
	end

	local search = W.SearchBox(main, 200, L.SEARCH_GUILDS, function(text)
		Filters.Get(KIND).text = text
		Changed()
	end)
	search:SetPoint("TOPLEFT", 6, -(BANNER_HEIGHT + 8))
	local sort = Filters.SortButton(main, KIND, Changed)
	sort:SetPoint("TOPRIGHT", 0, -(BANNER_HEIGHT + 8))
	local chips = Filters.ChipBar(main, KIND, Changed)
	chips:SetPoint("LEFT", search, "RIGHT", 10, 0)

	local panel = W.Panel(main)
	panel:SetPoint("TOPLEFT", 0, -(BANNER_HEIGHT + 40))
	panel:SetPoint("BOTTOMRIGHT")
	BuildGrid(tab, panel)

	local intro = BuildIntro(tab, content)

	function tab:Open(result)
		self.selectedId = result.ad.i
		self:RepaintCards()
		ns.GuildDialog.Open(result.ad, result.score, result.own, function()
			self.selectedId = nil
			self:RepaintCards()
		end)
	end

	local function ShowIntro()
		return not ns.db.settings.seenIntro and not MyAds.GetPlayerAd()
	end

	function tab:Refresh()
		if ShowIntro() then
			main:Hide()
			intro:Show()
			self:UpdateIntro()
			self.count = nil
			UI.SetMatchCount(nil)
			return
		end
		intro:Hide()
		main:Show()
		self:UpdateBanner()
		chips:Update()
		sort:Update()
		local filter = Filters.Get(KIND)
		if search:GetText() ~= (filter.text or "") then
			search:SetText(filter.text or "")
		end
		local results = Filters.Run(KIND)
		self.count = #results
		self:SetResults(results)
		UI.SetMatchCount(self:GetStatusText())
	end

	function tab:GetStatusText()
		return self.count and L.STATUS_MATCHES_GUILDS:format(self.count)
	end

	return tab
end

UI.RegisterTab(1, L.TAB_FIND_GUILDS, Build)
