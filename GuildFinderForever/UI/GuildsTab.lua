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

local KIND = Ads.KIND_GUILD
local BANNER_HEIGHT = 30
local CARD_HEIGHT = 156
local RAID_TOP = -56 -- raid box below name and meta
local RAID_PAD = 8
local CARD_GAP = 8

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

local NEED_Y = -30 -- second line of the raid box
local GROUP_GAP = 12

-- Card tooltip of raid guilds: the wanted classes per role, own class marked.
local function ShowCardTooltip(card)
	local ad = card.result and card.result.ad
	if not (ad and C.HasBit(ad.g or 0, C.GOAL_RAID) and (ad.cl or 0) > 0) then
		return
	end
	GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
	GameTooltip:SetText(ad.n, W.GOLD[1], W.GOLD[2], W.GOLD[3])
	local _, myClass = UnitClass("player")
	local needs = C.NeedsByRole(ad)
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
	card.emblem = W.GuildEmblem(card, 40)
	card.emblem:SetPoint("TOPLEFT", 12, -10)

	card.score = W.Text(card, "GameFontNormalLarge")
	card.score:SetPoint("TOPRIGHT", -10, -10)
	card.scoreLabel = W.Text(card, "GameFontDisableSmall")
	card.scoreLabel:SetPoint("TOPRIGHT", card.score, "BOTTOMRIGHT", 0, -1)
	card.scoreLabel:SetText(L.FITS_YOU)

	card.name = W.Text(card, "GameFontNormalLarge", W.GOLD)
	card.name:SetPoint("TOPLEFT", card.emblem, "TOPRIGHT", 10, 0)
	card.name:SetPoint("RIGHT", card.score, "LEFT", -8, 0)
	card.name:SetWordWrap(false)
	card.meta = W.Text(card, "GameFontDisableSmall")
	card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.meta:SetPoint("RIGHT", card.scoreLabel, "LEFT", -8, 0)
	card.meta:SetWordWrap(false)

	-- Raid box: style and schedule on top; below, the number of wanted
	-- classes per role (names in the tooltip) and whether your class fits.
	card.raid = W.Panel(card, { 0.07, 0.07, 0.07, 1 }, { 0.16, 0.16, 0.16, 1 })
	card.raid:SetPoint("TOPLEFT", 12, RAID_TOP)
	card.raid:SetPoint("RIGHT", -10, 0)
	card.raid:SetHeight(50)
	card.style = W.Tag(card.raid)
	card.style:SetPoint("TOPLEFT", RAID_PAD, -6)
	card.schedule = W.Text(card.raid, "GameFontHighlightSmall", W.TEXT)
	card.schedule:SetWordWrap(false)
	card.needsLabel = W.Text(card.raid, "GameFontDisableSmall")
	card.needsLabel:SetPoint("TOPLEFT", RAID_PAD, NEED_Y - 2)
	card.needsLabel:SetText(L.NEEDS_LABEL)
	card.roleIcons, card.roleCounts = {}, {}
	for i, role in ipairs(C.ROLES) do
		card.roleIcons[i] = W.RoleIcon(card.raid, 16, role.bit)
		card.roleCounts[i] = W.Text(card.raid, "GameFontHighlightSmall")
	end
	card.fit = W.Text(card.raid, "GameFontHighlightSmall")
	card.fit:SetPoint("TOPRIGHT", -RAID_PAD, NEED_Y - 2)
	card.fit:SetWordWrap(false)

	card.text = W.Text(card, "GameFontHighlightSmall", W.TEXT)
	card.text:SetPoint("RIGHT", -10, 0)
	card.text:SetJustifyV("TOP")
	card.text:SetSpacing(2)

	card.tags = W.GoalTags(card)
	card.tags:SetPoint("BOTTOMLEFT", 12, 8)
	card.roles = W.RoleIcons(card, 16)
	card.roles:SetPoint("BOTTOMRIGHT", -10, 9)

	card:SetScript("OnClick", function(self)
		if self.result then
			tab:Open(self.result)
		end
	end)
	card:SetScript("OnEnter", ShowCardTooltip)
	card:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Second line of the raid box: role icon and class count per role, or
	-- "any class" when the guild names none.
	-- Without a class list: "any class as" plus the wanted roles' icons, or
	-- only "all classes welcome" when every role is wanted.
	function card:LayoutNeeds(ad)
		local needs = (ad.cl or 0) > 0 and C.NeedsByRole(ad)
		local roles = not needs and ad.r or 0
		local someRoles = roles > 0 and roles ~= C.ALL_ROLES
		local label = L.NEEDS_LABEL
		if not needs then
			label = label .. " |cff9d9d9d" .. (someRoles and L.ANY_CLASS_AS or L.ANY_CLASS) .. "|r"
		end
		self.needsLabel:SetText(label)
		local x = RAID_PAD + self.needsLabel:GetStringWidth() + 6
		for i, role in ipairs(C.ROLES) do
			local count = needs and #needs[role.bit] or 0
			local shown = count > 0 or (someRoles and C.HasBit(roles, role.bit))
			local icon, text = self.roleIcons[i], self.roleCounts[i]
			icon:SetShown(shown)
			text:SetShown(count > 0)
			if shown then
				icon:ClearAllPoints()
				icon:SetPoint("TOPLEFT", x, NEED_Y)
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

	function card:SetResult(result)
		self.result = result
		if not result then
			self:Hide()
			return
		end
		local ad = result.ad
		self:Show()
		self.emblem:SetGuild(ad.n, ad.f)
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
		meta[#meta + 1] = L.AGO:format(W.Duration(GetServerTime() - ad.v))
		self.meta:SetText(table.concat(meta, " · "))

		if result.score then
			self.score:SetText(result.score .. " %")
			W.Color(self.score, W.ScoreColor(result.score))
		end
		self.score:SetShown(result.score ~= nil)
		self.scoreLabel:SetShown(result.score ~= nil)

		local raid = C.HasBit(ad.g or 0, C.GOAL_RAID)
		self.raid:SetShown(raid)
		if raid then
			local style = C.StyleName(ad.ps)
			self.style:SetShown(style ~= nil)
			if style then
				self.style:SetLabel(style)
			end
			local schedule = {}
			if (ad.rd or 0) > 0 then
				schedule[#schedule + 1] = "|cffffffff" .. C.DaysText(ad.rd) .. "|r"
			end
			schedule[#schedule + 1] = C.RaidTimeText(ad)
			if ad.rn then
				schedule[#schedule + 1] = "|cff9d9d9d" .. L.PER_WEEK:format(ad.rn) .. "|r"
			end
			self.schedule:ClearAllPoints()
			if style then
				self.schedule:SetPoint("LEFT", self.style, "RIGHT", 8, 0)
			else
				self.schedule:SetPoint("TOPLEFT", self.raid, "TOPLEFT", RAID_PAD, -9)
			end
			self.schedule:SetPoint("RIGHT", self.raid, "RIGHT", -RAID_PAD, 0)
			self.schedule:SetText(#schedule > 0 and table.concat(schedule, "   ") or ("|cff9d9d9d" .. L.RAID_NO_DETAILS .. "|r"))

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
			self:LayoutNeeds(ad)
		end

		self.text:ClearAllPoints()
		self.text:SetPoint("TOPLEFT", 12, raid and (RAID_TOP - self.raid:GetHeight() - 8) or -60)
		self.text:SetPoint("RIGHT", -10, 0)
		self.text:SetMaxLines(raid and 1 or 3)
		self.text:SetText(ad.x ~= "" and ad.x or ("|cff9d9d9d" .. L.NO_TEXT .. "|r"))
		self.tags:SetGoals(ad.g)
		-- Non-raid ads show their general wanted roles at the bottom.
		self.roles:SetShown(not raid)
		self.roles:SetRoles(ad.r or 0)
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

	function tab:SetResults(results)
		local rows = {}
		for i = 1, #results, 2 do
			rows[#rows + 1] = { results[i], results[i + 1] }
		end
		scrollBox:SetDataProvider(CreateDataProvider(rows), true)
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
		ns.GuildDialog.Open(result.ad, result.score, function()
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
