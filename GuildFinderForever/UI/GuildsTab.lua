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
local MIN_CARD_HEIGHT = 100
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
-- width, wraps to a second line when needed), the full description, footer
-- (goal tags left, score right). Raid details live in the tooltip. Each grid
-- row is as tall as its taller card needs.
local PAD = 10
local META_Y = -27
local META_MAX_LINES = 2
local ROW_GAP = 5
local FOOTER_HEIGHT = 18
local BOTTOM_PAD = 8
local TEXT_SPACING = 2
local META_LEFT = PAD + 2 + 32 + 8

-- Own class fit for raid ads: "✓ Class · Roles", "not your class", or nil.
local function FitText(ad)
	local fit, roles = Filters.ClassFit(ad)
	if fit == "fit" then
		local _, classFile = UnitClass("player")
		local label = C.ClassName(classFile)
		if roles ~= C.ClassRoles(classFile) then
			label = label .. " · " .. C.RoleNames(roles)
		end
		return W.CHECK .. " |cff1eff00" .. label .. "|r", fit
	elseif fit == "no" then
		return "|cff9d9d9d" .. L.FIT_NO_SHORT .. "|r", fit
	end
end

local function SomeRoles(ad)
	local roles = ad.r or 0
	return roles > 0 and roles ~= C.ALL_ROLES
end

-- Meta line: faction, languages, members, age; outdated first so it is
-- never cut off.
local function MetaText(result)
	local ad = result.ad
	local meta = { W.FactionText(ad.f, Filters.FactionName(ad.f)), Filters.LanguagesText(ad) }
	if ad.gm then
		meta[#meta + 1] = L.MEMBERS:format(ad.gm)
	end
	local age = L.AGO:format(W.Duration(GetServerTime() - ad.v))
	local stale = not result.own and Ads.IsStale(ad)
	if stale then
		age = "|c" .. W.STALE_HEX .. L.STALE .. " · " .. age .. "|r"
	end
	table.insert(meta, stale and 1 or #meta + 1, age)
	return table.concat(meta, " · "), stale
end

local function RaidSchedule(ad)
	local schedule = {}
	if (ad.rd or 0) > 0 then
		schedule[#schedule + 1] = C.DaysText(ad.rd)
	end
	local time = C.RaidTimeText(ad)
	if time and time ~= "" then
		schedule[#schedule + 1] = time
	end
	if ad.rn then
		schedule[#schedule + 1] = L.PER_WEEK:format(ad.rn)
	end
	return #schedule > 0 and table.concat(schedule, " · ") or nil
end

-- Card tooltip: match score, outdated notice, raid style and schedule, the
-- wanted classes per role (own class marked) or roles, and the own fit.
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
	local raid = C.HasBit(ad.g or 0, C.GOAL_RAID)
	local style = raid and C.StyleName(ad.ps)
	local schedule = raid and RaidSchedule(ad)
	if style or schedule then
		GameTooltip:AddLine(" ")
		if style then
			GameTooltip:AddDoubleLine(L.FILTER_STYLE, style, W.GOLD[1], W.GOLD[2], W.GOLD[3], 1, 1, 1)
		end
		if schedule then
			GameTooltip:AddDoubleLine(L.RAID_SCHEDULE, schedule, W.GOLD[1], W.GOLD[2], W.GOLD[3], 1, 1, 1)
		end
	end
	if raid and (ad.cl or 0) > 0 then
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
	elseif raid or SomeRoles(ad) then
		GameTooltip:AddLine(" ")
		local wanted = SomeRoles(ad) and (L.ANY_CLASS_AS .. " " .. C.RoleNames(ad.r)) or L.ANY_CLASS
		GameTooltip:AddLine(L.NEEDS_LABEL .. " |cffffffff" .. wanted .. "|r", W.GOLD[1], W.GOLD[2], W.GOLD[3], true)
	end
	local fit = raid and FitText(ad)
	if fit then
		GameTooltip:AddLine(fit)
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
	card.meta:SetPoint("TOPLEFT", card.emblem, "TOPRIGHT", 8, META_Y + 8)
	card.meta:SetPoint("RIGHT", -PAD, 0)
	card.meta:SetJustifyV("TOP")
	card.meta:SetMaxLines(META_MAX_LINES)

	card.text = W.Text(card, "GameFontHighlightSmall", W.TEXT)
	card.text:SetJustifyV("TOP")
	card.text:SetSpacing(TEXT_SPACING)

	card.tags = W.GoalTags(card)
	card.tags:SetPoint("BOTTOMLEFT", PAD + 2, 8)
	card.score = W.Text(card, "GameFontNormal")
	card.score:SetPoint("BOTTOMRIGHT", -PAD, 10)
	card.scoreLabel = W.Text(card, "GameFontDisableSmall")
	card.scoreLabel:SetPoint("BOTTOMRIGHT", card.score, "BOTTOMLEFT", -4, 0)
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

	function card:UpdatePresence()
		local result = self.result
		local online
		if result and not result.own then
			online = Presence.IsOnline(result.ad.o)
		end
		self.status:SetOnline(online)
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
		local meta, stale = MetaText(result)
		self.meta:SetText(meta)
		self:SetAlpha(stale and W.STALE_ALPHA or 1)

		local _, metaFont = self.meta:GetFont()
		local metaLines = math.max(1, math.min(META_MAX_LINES, self.meta:GetNumLines()))
		local y = META_Y - metaLines * (math.floor((metaFont or 10) + 0.5) + 2) - ROW_GAP
		self.text:ClearAllPoints()
		self.text:SetPoint("TOPLEFT", PAD + 2, y + 1)
		self.text:SetPoint("RIGHT", -PAD, 0)
		self.text:SetText(ad.x or "")
		self.text:SetShown((ad.x or "") ~= "")

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

	-- Invisible copies of the card's meta and description text, used to
	-- measure how tall a card must be to show both in full.
	local measure = CreateFrame("Frame", nil, panel)
	measure:SetSize(1, 1)
	measure:SetPoint("TOPLEFT")
	measure:SetAlpha(0)
	local measureMeta = W.Text(measure, "GameFontDisableSmall")
	measureMeta:SetPoint("TOPLEFT")
	local measureText = W.Text(measure, "GameFontHighlightSmall")
	measureText:SetPoint("TOPLEFT")
	measureText:SetSpacing(TEXT_SPACING)

	local function CardHeight(result, width)
		if not result then
			return 0
		end
		measureMeta:SetWidth(width - META_LEFT - PAD)
		measureMeta:SetText(MetaText(result))
		local _, metaFont = measureMeta:GetFont()
		local metaLines = math.max(1, math.min(META_MAX_LINES, measureMeta:GetNumLines()))
		local height = -META_Y + metaLines * (math.floor((metaFont or 10) + 0.5) + 2) + ROW_GAP
		local text = result.ad.x or ""
		if text ~= "" then
			measureText:SetWidth(width - 2 * PAD - 2)
			measureText:SetText(text)
			height = height + math.ceil(measureText:GetStringHeight()) + ROW_GAP
		end
		return height + FOOTER_HEIGHT + BOTTOM_PAD
	end

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, pair)
		-- Card width as anchored in the row below.
		local width = scrollBox:GetWidth() / 2 - CARD_GAP / 2
		if width <= 0 then
			return MIN_CARD_HEIGHT + CARD_GAP
		end
		local height = math.max(MIN_CARD_HEIGHT, CardHeight(pair[1], width), CardHeight(pair[2], width))
		return math.ceil(height) + CARD_GAP
	end)
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
		-- Then the posters of hidden outdated ads: an answer brings them back.
		for _, ad in ipairs(self.results and self.results.stale or {}) do
			owners[#owners + 1] = ad.o
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
