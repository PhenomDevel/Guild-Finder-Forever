-- luacheck: read globals GameTooltip
local _, ns = ...

-- Guild details: a dialog over the dimmed main window with the full ad,
-- the time grid compared with the own play times, and the actions.
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

local WIDTH, HEIGHT = 580, 430
local RAID_HEIGHT = 72 -- extra height of the raid section
local PAD = 20

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

	-- Body
	dialog.text = W.Text(dialog, "GameFontHighlight", W.TEXT)
	dialog.text:SetPoint("TOPLEFT", PAD, -112)
	dialog.text:SetPoint("RIGHT", -PAD, 0)
	dialog.text:SetJustifyV("TOP")
	dialog.text:SetSpacing(3)
	dialog.text:SetHeight(50)

	local goalsHeader = W.Header(dialog, L.FILTER_GOALS, "GameFontNormalLarge")
	goalsHeader:SetPoint("TOPLEFT", PAD, -172)
	dialog.tags = W.GoalTags(dialog)
	dialog.tags:SetPoint("TOPLEFT", goalsHeader, "BOTTOMLEFT", 0, -6)

	local rolesHeader = W.Header(dialog, L.WANTED, "GameFontNormalLarge")
	rolesHeader:SetPoint("TOPLEFT", 300, -172)
	dialog.roles = {}
	for i, role in ipairs(C.ROLES) do
		local icon = W.RoleIcon(dialog, 18, role.bit)
		local label = W.Text(dialog, "GameFontHighlight")
		label:SetText(role.label)
		label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
		dialog.roles[i] = { icon = icon, label = label, bit = role.bit }
	end
	dialog.rolesHeader = rolesHeader
	dialog.noRoles = W.Text(dialog, "GameFontDisable")
	dialog.noRoles:SetPoint("TOPLEFT", rolesHeader, "BOTTOMLEFT", 0, -8)
	dialog.noRoles:SetText(L.ANY_ROLE)

	-- Raid details, only for ads with the raid goal.
	local raid = CreateFrame("Frame", nil, dialog)
	raid:SetPoint("TOPLEFT", PAD, -224)
	raid:SetPoint("RIGHT", -PAD, 0)
	raid:SetHeight(RAID_HEIGHT)
	dialog.raid = raid
	local raidHeader = W.Header(raid, L.RAID_DETAILS, "GameFontNormalLarge")
	raidHeader:SetPoint("TOPLEFT")
	dialog.raidInfo = W.Text(raid, "GameFontHighlight", W.TEXT)
	dialog.raidInfo:SetPoint("TOPLEFT", raidHeader, "BOTTOMLEFT", 0, -6)
	dialog.raidInfo:SetPoint("RIGHT")
	dialog.raidInfo:SetWordWrap(false)
	dialog.classesLabel = W.Text(raid, "GameFontNormalSmall", W.GOLD)
	dialog.classesLabel:SetPoint("TOPLEFT", dialog.raidInfo, "BOTTOMLEFT", 0, -9)
	dialog.classesLabel:SetText(L.WANTED_CLASSES .. ":")
	dialog.classIcons = {}
	dialog.anyClass = W.Text(raid, "GameFontHighlightSmall", W.MUTED)
	dialog.anyClass:SetPoint("LEFT", dialog.classesLabel, "RIGHT", 6, 0)
	dialog.anyClass:SetText(L.ANY_CLASS)

	local timesHeader = W.Header(dialog, L.RAID_TIMES, "GameFontNormalLarge")
	timesHeader:SetPoint("TOPLEFT", PAD, -224)
	dialog.timesHeader = timesHeader
	dialog.grid = W.TimeGrid(dialog, 64, 16, false)
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

local function Update()
	local ad = current and Store.Get(current.id)
	if not ad or ad.d or Store.IsFiltered(ad) then
		Close()
		return
	end
	local poster = Ads.OwnerName(ad.o)
	dialog.emblem:SetGuild(ad.n, ad.f)
	dialog.name:SetText("<" .. ad.n .. ">")
	local meta = { W.FactionText(ad.f, Filters.FactionName(ad.f)), Filters.LanguageName(ad.l) }
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

	local x = 0
	for _, role in ipairs(dialog.roles) do
		local wanted = C.HasBit(ad.r or 0, role.bit)
		role.icon:SetShown(wanted)
		role.label:SetShown(wanted)
		if wanted then
			role.icon:ClearAllPoints()
			role.icon:SetPoint("TOPLEFT", dialog.rolesHeader, "BOTTOMLEFT", x, -6)
			x = x + 18 + 4 + role.label:GetStringWidth() + 16
		end
	end
	dialog.noRoles:SetShown(x == 0)

	local count = 0
	if (ad.cl or 0) > 0 then
		for _, class in ipairs(C.GetClasses()) do
			if C.HasBit(ad.cl, C.ClassBit(class.id)) then
				count = count + 1
				local icon = dialog.classIcons[count]
				if not icon then
					icon = W.ClassIcon(dialog.raid, 20)
					icon:SetPoint("LEFT", dialog.classesLabel, "RIGHT", 6 + (count - 1) * 23, 0)
					icon:EnableMouse(true)
					icon:SetScript("OnEnter", function(self)
						GameTooltip:SetOwner(self, "ANCHOR_TOP")
						GameTooltip:SetText(self.label)
						GameTooltip:Show()
					end)
					icon:SetScript("OnLeave", function()
						GameTooltip:Hide()
					end)
					dialog.classIcons[count] = icon
				end
				icon:SetClass(class.key)
				icon.label = class.label
				icon:Show()
			end
		end
	end
	for i = count + 1, #dialog.classIcons do
		dialog.classIcons[i]:Hide()
	end
	dialog.anyClass:SetShown(count == 0)

	local hasRaid = C.HasBit(ad.g or 0, C.GOAL_RAID)
	dialog.raid:SetShown(hasRaid)
	dialog.timesHeader:SetPoint("TOPLEFT", PAD, hasRaid and -224 - RAID_HEIGHT or -224)
	dialog:SetHeight(HEIGHT + (hasRaid and RAID_HEIGHT or 0))
	if hasRaid then
		local info = {}
		info[#info + 1] = C.StyleName(ad.ps)
		if (ad.rd or 0) > 0 then
			local days = {}
			for day, name in ipairs(C.DAYS) do
				if C.HasBit(ad.rd, C.DayBit(day)) then
					days[#days + 1] = name
				end
			end
			info[#info + 1] = table.concat(days, ", ")
		end
		if ad.rn then
			info[#info + 1] = L.PER_WEEK:format(ad.rn)
		end
		if ad.rs then
			info[#info + 1] = C.FormatTime(ad.rs) .. (ad.re and ("–" .. C.FormatTime(ad.re)) or "")
				.. " " .. L.REALM_TIME
		end
		dialog.raidInfo:SetText(#info > 0 and table.concat(info, " · ") or ("|cff9d9d9d" .. L.RAID_NO_DETAILS .. "|r"))
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
