-- luacheck: read globals CreateScrollBoxListLinearView ScrollUtil CreateDataProvider UnitClass UnitLevel
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
local CARD_HEIGHT = 140
local CARD_GAP = 8
local VERIFIED_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"

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

local NEED_ICON = 14 -- class icons in the needs line
local NEED_GAP = 2
local GROUP_GAP = 10

-- Class icon from the card's pool, created on demand.
local function NeedIcon(card, index)
	local icon = card.needIcons[index]
	if not icon then
		icon = W.ClassIcon(card.raid, NEED_ICON)
		card.needIcons[index] = icon
	end
	return icon
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
	card.name:SetPoint("RIGHT", card, "RIGHT", -64, 0)
	card.name:SetWordWrap(false)
	card.meta = W.Text(card, "GameFontDisableSmall")
	card.meta:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.meta:SetPoint("RIGHT", card, "RIGHT", -64, 0)
	card.meta:SetWordWrap(false)

	-- Raid line: style, days, time; needs line: classes per role + fit.
	card.raid = CreateFrame("Frame", nil, card)
	card.raid:SetPoint("TOPLEFT", 12, -58)
	card.raid:SetPoint("RIGHT", -10, 0)
	card.raid:SetHeight(36)
	card.style = W.Tag(card.raid)
	card.style:SetPoint("TOPLEFT")
	card.schedule = W.Text(card.raid, "GameFontHighlightSmall", W.TEXT)
	card.schedule:SetPoint("LEFT", card.style, "RIGHT", 8, 0)
	card.schedule:SetPoint("RIGHT", card.raid, "RIGHT", 0, 0)
	card.schedule:SetWordWrap(false)
	card.roleIcons, card.needIcons = {}, {}
	for i, role in ipairs(C.ROLES) do
		card.roleIcons[i] = W.RoleIcon(card.raid, 16, role.bit)
	end
	card.more = W.Text(card.raid, "GameFontDisableSmall")
	card.fit = W.Text(card.raid, "GameFontHighlightSmall")
	card.fit:SetPoint("TOPRIGHT", 0, -20)

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

	-- Role icon followed by the wanted classes' icons, per role; what doesn't
	-- fit next to the fit text is summed up as "+n".
	function card:LayoutNeeds(ad, hasNeeds)
		for _, icon in ipairs(self.needIcons) do
			icon:Hide()
		end
		self.more:Hide()
		for _, icon in ipairs(self.roleIcons) do
			icon:SetShown(hasNeeds)
		end
		if not hasNeeds then
			return
		end
		local width = self.raid:GetWidth()
		local limit = (width > 0 and width or 420) - self.fit:GetStringWidth() - 30
		local needs = C.NeedsByRole(ad)
		local x, used, hidden = 0, 0, 0
		for i, role in ipairs(C.ROLES) do
			local list = needs[role.bit]
			local roleIcon = self.roleIcons[i]
			roleIcon:SetShown(#list > 0)
			if #list > 0 then
				if x + 16 + NEED_ICON > limit then
					roleIcon:Hide()
					hidden = hidden + #list
				else
					roleIcon:ClearAllPoints()
					roleIcon:SetPoint("TOPLEFT", x, -20)
					x = x + 16 + 4
					for _, class in ipairs(list) do
						if x + NEED_ICON > limit then
							hidden = hidden + 1
						else
							used = used + 1
							local icon = NeedIcon(self, used)
							icon:SetClass(class.key)
							icon:ClearAllPoints()
							icon:SetPoint("TOPLEFT", x, -21)
							icon:Show()
							x = x + NEED_ICON + NEED_GAP
						end
					end
					x = x + GROUP_GAP - NEED_GAP
				end
			end
		end
		if hidden > 0 then
			self.more:SetText("+" .. hidden)
			self.more:ClearAllPoints()
			self.more:SetPoint("LEFT", self.raid, "TOPLEFT", x, -28)
			self.more:Show()
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
		local check = Store.GetCheck(ad.i)
		self.name:SetText(ad.n .. (check and check.verified and (" " .. VERIFIED_ICON) or ""))
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
				self.schedule:SetPoint("TOPLEFT", self.raid, "TOPLEFT", 0, -3)
			end
			self.schedule:SetPoint("RIGHT", self.raid, "RIGHT", 0, 0)
			self.schedule:SetText(#schedule > 0 and table.concat(schedule, "   ") or ("|cff9d9d9d" .. L.RAID_NO_DETAILS .. "|r"))

			local hasNeeds = (ad.cl or 0) > 0
			local fit, roles = Filters.ClassFit(ad)
			if fit == "fit" then
				local _, classFile = UnitClass("player")
				-- Roles only when not every role of the class is wanted: keeps
				-- room for the class icons.
				local label = C.ClassName(classFile)
				if roles ~= C.ClassRoles(classFile) then
					label = label .. " · " .. C.RoleNames(roles)
				end
				self.fit:SetText(W.CHECK .. " |cff1eff00" .. label .. "|r")
			elseif fit == "no" then
				self.fit:SetText("|cff9d9d9d" .. L.FIT_NO_SHORT .. "|r")
			else
				self.fit:SetText("|cff9d9d9d" .. L.ANY_CLASS .. "|r")
			end
			self.fit:ClearAllPoints()
			if hasNeeds then
				self.fit:SetPoint("TOPRIGHT", self.raid, "TOPRIGHT", 0, -21)
			else
				self.fit:SetPoint("TOPLEFT", self.raid, "TOPLEFT", 0, -21)
			end
			self:LayoutNeeds(ad, hasNeeds)
		end

		self.text:ClearAllPoints()
		self.text:SetPoint("TOPLEFT", 12, raid and -98 or -60)
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
