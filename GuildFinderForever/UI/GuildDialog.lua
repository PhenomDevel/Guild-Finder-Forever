-- luacheck: read globals GameTooltip UnitClass
local _, ns = ...

-- Guild details: a dialog over the dimmed main window. Left the text, goals
-- and online times (compared with the own ones), right what the guild is
-- looking for: raid style and schedule plus wanted classes grouped by
-- role, or just the wanted roles. Actions at the bottom.
local GuildDialog = {}
ns.GuildDialog = GuildDialog

local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local UI = ns.UI
local Ads = ns.Ads
local Store = ns.Store
local Verify = ns.Verify
local Filters = ns.Filters

local WIDTH, HEIGHT = 720, 470
local PAD = 20
local SIDE_WIDTH = 300 -- right column
local SIDE_X = WIDTH - SIDE_WIDTH
local ROLE_LABEL = 76 -- role column in the needs list
local CHIP_SIZE = 24
local CHIP_GAP = 3

local overlay, dialog
local current -- { id, score, onClose }
local verifying

local function Close()
	if overlay then
		overlay:Hide()
	end
end

-- Also runs when the main window closes; the dialog stays closed then.
local function OnHide()
	overlay:Hide()
	local onClose = current and current.onClose
	current = nil
	if onClose then
		onClose()
	end
end

local function Create()
	local main = UI.GetFrame()
	overlay = CreateFrame("Frame", nil, main)
	overlay:SetPoint("TOPLEFT", 2, -22)
	overlay:SetPoint("BOTTOMRIGHT", -2, 2)
	overlay:SetFrameStrata("DIALOG")
	overlay:EnableMouse(true)
	local dim = overlay:CreateTexture(nil, "BACKGROUND")
	dim:SetAllPoints()
	dim:SetColorTexture(0, 0, 0, 0.6)
	overlay:SetScript("OnMouseDown", Close)
	overlay:SetScript("OnHide", OnHide)

	dialog = W.Panel(overlay, { 0.07, 0.065, 0.06, 0.98 }, { 0.79, 0.635, 0.29, 1 })
	dialog:SetSize(WIDTH, HEIGHT)
	dialog:SetPoint("CENTER", 0, 10)
	dialog:EnableMouse(true)

	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", Close)

	-- Header
	local header = dialog:CreateTexture(nil, "BACKGROUND", nil, 1)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(96)
	header:SetColorTexture(0.12, 0.1, 0.06, 1)
	local headerLine = W.Divider(dialog)
	headerLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
	headerLine:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT")

	dialog.emblem = W.GuildEmblem(dialog, 60)
	dialog.emblem:SetPoint("TOPLEFT", PAD, -18)
	dialog.name = W.Text(dialog, "GameFontNormalHuge", W.GOLD)
	dialog.name:SetPoint("TOPLEFT", dialog.emblem, "TOPRIGHT", 14, 0)
	dialog.name:SetPoint("RIGHT", -110, 0)
	dialog.name:SetWordWrap(false)
	dialog.meta = W.Text(dialog, "GameFontHighlight", W.MUTED)
	dialog.meta:SetPoint("TOPLEFT", dialog.name, "BOTTOMLEFT", 0, -4)

	dialog.pill = W.Panel(dialog)
	dialog.pill:SetHeight(20)
	dialog.pill:SetPoint("TOPLEFT", dialog.meta, "BOTTOMLEFT", 0, -6)
	dialog.pillText = W.Text(dialog.pill, "GameFontHighlightSmall")
	dialog.pillText:SetPoint("LEFT", 8, 0)
	dialog.age = W.Text(dialog, "GameFontDisableSmall")
	dialog.age:SetPoint("LEFT", dialog.pill, "RIGHT", 10, 0)

	dialog.score = W.Text(dialog, "GameFontNormalHuge")
	dialog.score:SetPoint("TOPRIGHT", -36, -20)
	dialog.scoreLabel = W.Text(dialog, "GameFontDisableSmall")
	dialog.scoreLabel:SetPoint("TOPRIGHT", dialog.score, "BOTTOMRIGHT", 0, -2)
	dialog.scoreLabel:SetText(L.FITS_YOU)

	-- Body, left column
	local leftWidth = SIDE_X - 2 * PAD
	dialog.text = W.Text(dialog, "GameFontHighlight", W.TEXT)
	dialog.text:SetPoint("TOPLEFT", PAD, -112)
	dialog.text:SetWidth(leftWidth)
	dialog.text:SetJustifyV("TOP")
	dialog.text:SetSpacing(3)
	dialog.text:SetHeight(62)

	local goalsHeader = W.Header(dialog, L.FILTER_GOALS, "GameFontNormalLarge")
	goalsHeader:SetPoint("TOPLEFT", PAD, -184)
	dialog.tags = W.GoalTags(dialog)
	dialog.tags:SetPoint("TOPLEFT", goalsHeader, "BOTTOMLEFT", 0, -6)

	local timesHeader = W.Header(dialog, L.ONLINE_TIMES, "GameFontNormalLarge")
	timesHeader:SetPoint("TOPLEFT", PAD, -240)
	dialog.grid = W.TimeGrid(dialog, 38, 16, false)
	dialog.grid:SetPoint("TOPLEFT", timesHeader, "BOTTOMLEFT", 0, -6)
	local legendOn = dialog:CreateTexture(nil, "ARTWORK")
	legendOn:SetSize(10, 10)
	legendOn:SetPoint("TOPLEFT", dialog.grid, "BOTTOMLEFT", 0, -6)
	legendOn:SetColorTexture(0.79, 0.635, 0.29, 1)
	local legendOnText = W.Text(dialog, "GameFontDisableSmall")
	legendOnText:SetPoint("LEFT", legendOn, "RIGHT", 4, 0)
	legendOnText:SetText(L.LEGEND_GUILD)
	local legendBoth = W.Panel(dialog, { 0, 0, 0, 0 }, { W.GREEN[1], W.GREEN[2], W.GREEN[3], 1 })
	legendBoth:SetSize(10, 10)
	legendBoth:SetPoint("LEFT", legendOnText, "RIGHT", 14, 0)
	local legendBothText = W.Text(dialog, "GameFontDisableSmall")
	legendBothText:SetPoint("LEFT", legendBoth, "RIGHT", 4, 0)
	legendBothText:SetText(L.LEGEND_YOU)

	-- Right column
	local side = W.Panel(dialog, { 0.055, 0.055, 0.05, 1 }, { 0.16, 0.16, 0.16, 1 })
	side:SetPoint("TOPLEFT", SIDE_X, -97)
	side:SetPoint("BOTTOMRIGHT", -1, 53)
	dialog.side = side
	local sideWidth = SIDE_WIDTH - 2 * 16

	dialog.raidHeader = W.Header(side, L.RAID_DETAILS, "GameFontNormalLarge")
	dialog.raidHeader:SetPoint("TOPLEFT", 16, -14)
	dialog.style = W.Tag(side)
	dialog.style:SetPoint("TOPRIGHT", -16, -12)
	dialog.days = {}
	for day, name in ipairs(C.DAYS) do
		local tag = W.Panel(side)
		tag:SetSize(32, 20)
		tag:SetPoint("TOPLEFT", 16 + (day - 1) * 35, -40)
		tag.text = W.Text(tag, "GameFontHighlightSmall")
		tag.text:SetPoint("CENTER")
		tag.text:SetText(name)
		dialog.days[day] = tag
	end
	dialog.schedule = W.Text(side, "GameFontHighlight", W.TEXT)
	dialog.schedule:SetPoint("TOPLEFT", 16, -68)
	dialog.schedule:SetWidth(sideWidth)
	dialog.schedule:SetWordWrap(false)
	dialog.raidLine = W.Divider(side)
	dialog.raidLine:SetPoint("TOPLEFT", 16, -90)
	dialog.raidLine:SetPoint("TOPRIGHT", -16, -90)

	dialog.wantedHeader = W.Header(side, L.WANTED, "GameFontNormalLarge")
	dialog.fit = W.Text(side, "GameFontHighlightSmall")
	dialog.fit:SetPoint("TOPLEFT", dialog.wantedHeader, "BOTTOMLEFT", 0, -5)
	dialog.fit:SetWidth(sideWidth)
	dialog.fit:SetWordWrap(false)
	dialog.needRows = {}
	for i, role in ipairs(C.ROLES) do
		local label = CreateFrame("Frame", nil, side)
		label:SetSize(ROLE_LABEL, CHIP_SIZE)
		local icon = W.RoleIcon(label, 16, role.bit)
		icon:SetPoint("LEFT")
		local text = W.Text(label, "GameFontNormalSmall", W.TAG)
		text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
		text:SetText(role.label)
		dialog.needRows[i] = { label = label, bit = role.bit, chips = {} }
	end
	dialog.anyClass = W.Text(side, "GameFontHighlight", W.MUTED)
	dialog.chipWidth = sideWidth - ROLE_LABEL

	-- Footer
	local footerLine = W.Divider(dialog)
	footerLine:SetPoint("BOTTOMLEFT", 1, 52)
	footerLine:SetPoint("BOTTOMRIGHT", -1, 52)
	dialog.contact = W.Button(dialog, L.CONTACT, 180, function()
		local ad = current and Store.Get(current.id)
		if ad then
			Verify.Contact(ad)
		end
	end)
	dialog.contact:SetPoint("BOTTOMLEFT", PAD, 16)
	W.Tooltip(dialog.contact, L.CONTACT, L.CONTACT_TIP)
	local hide = W.Button(dialog, L.HIDE, 110, function()
		if current then
			Store.SetHidden(current.id, true)
		end
		Close()
	end)
	hide:SetPoint("LEFT", dialog.contact, "RIGHT", 10, 0)
	W.Tooltip(hide, L.HIDE, L.HIDE_TIP)
	local block = W.LinkButton(dialog, L.BLOCK_GUILD, function()
		local ad = current and Store.Get(current.id)
		if ad then
			Store.Block(ad)
		end
		Close()
	end)
	block:SetPoint("BOTTOMRIGHT", -PAD, 20)
	W.Tooltip(block, L.BLOCK_GUILD, L.BLOCK_GUILD_TIP)
	local unfit = W.Text(dialog, "GameFontDisableSmall")
	unfit:SetPoint("RIGHT", block, "LEFT", -6, 0)
	unfit:SetText(L.UNFIT)
end

-- Class chip: class icon, name in the tooltip.
local function ClassChip(parent)
	local chip = CreateFrame("Frame", nil, parent)
	chip:SetSize(CHIP_SIZE, CHIP_SIZE)
	chip.icon = W.ClassIcon(chip, CHIP_SIZE)
	chip.icon:SetAllPoints()
	chip:EnableMouse(true)
	chip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("|c" .. W.ClassColorHex(self.class.key) .. self.class.label .. "|r")
		GameTooltip:Show()
	end)
	chip:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	function chip:SetClass(class)
		self.class = class
		self.icon:SetClass(class.key)
	end
	return chip
end

-- Wanted classes grouped by role, chips wrapping in the right column;
-- returns the y below the list.
local function LayoutNeeds(ad, top)
	local needs = C.NeedsByRole(ad)
	local y = top
	for _, row in ipairs(dialog.needRows) do
		local list = needs[row.bit]
		row.label:SetShown(#list > 0)
		local x, lineY = 0, y
		for i, class in ipairs(list) do
			local chip = row.chips[i]
			if not chip then
				chip = ClassChip(dialog.side)
				row.chips[i] = chip
			end
			chip:SetClass(class)
			if x > 0 and x + CHIP_SIZE > dialog.chipWidth then
				x, lineY = 0, lineY - CHIP_SIZE - CHIP_GAP
			end
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", 16 + ROLE_LABEL + x, lineY)
			chip:Show()
			x = x + CHIP_SIZE + CHIP_GAP
		end
		for i = #list + 1, #row.chips do
			row.chips[i]:Hide()
		end
		if #list > 0 then
			row.label:ClearAllPoints()
			row.label:SetPoint("TOPLEFT", 16, y)
			y = lineY - CHIP_SIZE - 8
		end
	end
	return y
end

local function Update()
	local ad = current and Store.Get(current.id)
	if not ad or ad.d or Store.IsFiltered(ad) then
		Close()
		return
	end
	local poster = Ads.OwnerName(ad.o)
	dialog.emblem:SetGuild(ad.n, ad.f)
	dialog.name:SetText("<" .. ad.n .. ">")
	local meta = { W.FactionText(ad.f, Filters.FactionName(ad.f)), Filters.LanguagesText(ad) }
	if ad.gm then
		meta[#meta + 1] = L.MEMBERS:format(ad.gm)
	end
	dialog.meta:SetText(table.concat(meta, " · "))

	local check = Store.GetCheck(ad.i)
	if verifying == ad.i then
		dialog.pillText:SetText(L.VERIFYING)
		W.Color(dialog.pillText, W.MUTED)
		dialog.pill:SetBackdropColor(0.12, 0.12, 0.12, 1)
		dialog.pill:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	elseif check and check.verified then
		dialog.pillText:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " .. L.VERIFIED_MEMBER:format(poster))
		W.Color(dialog.pillText, W.SOFT_GREEN)
		dialog.pill:SetBackdropColor(0.06, 0.16, 0.05, 1)
		dialog.pill:SetBackdropBorderColor(0.2, 0.45, 0.15, 1)
	else
		dialog.pillText:SetText(L.NOT_VERIFIED_BY:format(poster))
		W.Color(dialog.pillText, W.MUTED)
		dialog.pill:SetBackdropColor(0.12, 0.12, 0.12, 1)
		dialog.pill:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
	end
	dialog.pill:SetWidth(dialog.pillText:GetStringWidth() + 16)
	dialog.age:SetText(L.AD_META:format(W.Duration(GetServerTime() - ad.v), W.Duration(Ads.ExpiresIn(ad))))

	local score = current.score
	if score then
		local color = W.ScoreColor(score)
		dialog.score:SetText(score .. " %")
		W.Color(dialog.score, color)
		dialog.scoreLabel:Show()
	else
		dialog.score:SetText("")
		dialog.scoreLabel:Hide()
	end

	dialog.text:SetText(ad.x ~= "" and ad.x or ("|cff9d9d9d" .. L.NO_TEXT .. "|r"))
	dialog.tags:SetGoals(ad.g)

	local myTimes = Filters.Profile(Ads.KIND_GUILD).times
	local raid = C.HasBit(ad.g or 0, C.GOAL_RAID)
	dialog.raidHeader:SetShown(raid)
	dialog.schedule:SetShown(raid)
	dialog.raidLine:SetShown(raid)
	local style = raid and C.StyleName(ad.ps)
	dialog.style:SetShown(style ~= nil and style ~= false)
	if style then
		dialog.style:SetLabel(style)
	end
	for day, tag in ipairs(dialog.days) do
		tag:SetShown(raid)
		local on = C.HasBit(ad.rd or 0, C.DayBit(day))
		local mine = false
		for slot = 1, #C.SLOTS do
			mine = mine or C.HasBit(myTimes or 0, C.TimeBit(day, slot))
		end
		if on then
			tag:SetBackdropColor(0.24, 0.19, 0.09, 1)
			tag:SetBackdropBorderColor(mine and W.GREEN[1] or 0.79, mine and W.GREEN[2] or 0.635, mine and W.GREEN[3] or 0.29, 1)
			W.Color(tag.text, W.GOLD)
		else
			tag:SetBackdropColor(0.08, 0.08, 0.08, 1)
			tag:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
			W.Color(tag.text, { 0.4, 0.4, 0.4 })
		end
	end
	local wantedTop = -14
	if raid then
		local schedule = {}
		local time = C.RaidTimeText(ad)
		if time then
			schedule[#schedule + 1] = "|cffffffff" .. time .. "|r |cff9d9d9d" .. L.REALM_TIME .. "|r"
		end
		if ad.rn then
			schedule[#schedule + 1] = L.PER_WEEK:format(ad.rn)
		end
		dialog.schedule:SetText(#schedule > 0 and table.concat(schedule, " · ") or ("|cff9d9d9d" .. L.RAID_NO_DETAILS .. "|r"))
		wantedTop = -102
	end
	dialog.wantedHeader:ClearAllPoints()
	dialog.wantedHeader:SetPoint("TOPLEFT", 16, wantedTop)

	local fit, fitRoles = Filters.ClassFit(ad)
	local _, myClass = UnitClass("player")
	if fit == "fit" then
		dialog.fit:SetText(W.CHECK .. " |cff1eff00" .. L.FIT_YES:format(C.ClassName(myClass), C.RoleNames(fitRoles)) .. "|r")
	elseif fit == "no" then
		dialog.fit:SetText("|cff9d9d9d" .. L.FIT_NO:format(C.ClassName(myClass)) .. "|r")
	end
	dialog.fit:SetShown(fit ~= nil)
	local listTop = wantedTop - 24 - (fit and 18 or 0)

	dialog.anyClass:ClearAllPoints()
	dialog.anyClass:SetPoint("TOPLEFT", 16, listTop)
	if raid and (ad.cl or 0) > 0 then
		dialog.anyClass:Hide()
		LayoutNeeds(ad, listTop)
	else
		-- No class needs: the general wanted roles as rows without chips.
		for _, row in ipairs(dialog.needRows) do
			for _, chip in ipairs(row.chips) do
				chip:Hide()
			end
			row.label:Hide()
		end
		-- Raid ads: every class, in some roles (rows) or in all (text only).
		local roles = ad.r or 0
		local y = listTop
		if raid then
			local someRoles = roles > 0 and roles ~= C.ALL_ROLES
			dialog.anyClass:SetText(someRoles and L.ANY_CLASS_ROLES or L.ANY_CLASS)
			dialog.anyClass:Show()
			y = y - 22
			if not someRoles then
				roles = 0
			end
		else
			dialog.anyClass:SetText(L.ANY_ROLE)
			dialog.anyClass:SetShown(roles == 0)
		end
		for _, row in ipairs(dialog.needRows) do
			if C.HasBit(roles, row.bit) then
				row.label:ClearAllPoints()
				row.label:SetPoint("TOPLEFT", 16, y)
				row.label:Show()
				y = y - 24
			end
		end
	end

	dialog.grid:SetMask(ad.t, Filters.Profile(Ads.KIND_GUILD).times)
	dialog.contact:SetText(L.CONTACT_NAME:format(poster))
	dialog.contact:SetWidth(math.max(150, dialog.contact:GetFontString():GetStringWidth() + 30))
end

-- onClose runs when the dialog closes (any way).
function GuildDialog.Open(ad, score, onClose)
	if not overlay then
		Create()
	end
	if current and current.onClose and current.id ~= ad.i then
		current.onClose()
	end
	current = { id = ad.i, score = score, onClose = onClose }
	overlay:Show()
	Update()
	Verify.Ping(ad)
end

function GuildDialog.Close()
	Close()
end

ns.RegisterCallback(GuildDialog, "GFF_ADS_CHANGED", function(_, id)
	if current and overlay:IsShown() and (id == nil or id == current.id) then
		Update()
	end
end)
ns.RegisterCallback(GuildDialog, "GFF_VERIFY_STARTED", function(_, ad)
	verifying = ad.i
	if current and current.id == ad.i then
		Update()
	end
end)
ns.RegisterCallback(GuildDialog, "GFF_VERIFY_DONE", function(_, ad)
	verifying = nil
	if current and overlay:IsShown() and current.id == ad.i then
		Update()
	end
end)
