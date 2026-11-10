-- luacheck: read globals GameTooltip
local _, ns = ...

-- About page: who made the addon, version and links. The same page (content
-- and layout) exists in all addons by Phenom; only the values below differ.
local L = ns.L
local UI = ns.UI
local W = ns.Widgets

local ABOUT = {
	logo = "Interface\\AddOns\\GuildFinderForever\\Media\\Logo",
	discord = "https://discord.gg/4fSVKCVJWy",
	curseforge = "https://www.curseforge.com/projects/1765174",
	wago = "https://addons.wago.io/addons/Q6aqwa6W",
	github = "https://github.com/PhenomDevel/Guild-Finder-Forever",
	tip = "https://streamlabs.com/phenombutbetter/tip",
	-- The other addons by Phenom, as { name, locale key of the description }.
	others = {
		{ "AskAzeroth", "ABOUT_ADDON_ASKAZEROTH" },
		{ "BlizzHUDTweaks", "ABOUT_ADDON_BLIZZHUDTWEAKS" },
		{ "PhenomRaidTools", "ABOUT_ADDON_PHENOMRAIDTOOLS" },
		{ "Quality of Life Forever", "ABOUT_ADDON_QOL" },
	},
}

local COLUMN_WIDTH = 380
local COLUMN_GAP = 40
local FIELD_WIDTH = 250
local LABEL_WIDTH = 120

-- Read-only field: a click selects the whole text, ready for Ctrl+C;
-- typing puts the text back.
local function CopyField(parent, text)
	local box = W.EditBox(parent, FIELD_WIDTH)
	box:SetText(text)
	box:SetCursorPosition(0)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(text)
			self:HighlightText()
		end
	end)
	box:HookScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:HookScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		self:SetCursorPosition(0)
	end)
	box:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.ABOUT_COPY_TOOLTIP, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	box:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return box
end

local function Build(content)
	local page = {}

	-- Left column: addon, author, version, Discord.
	local left = CreateFrame("Frame", nil, content)
	left:SetPoint("TOPLEFT", 16, -16)
	left:SetSize(COLUMN_WIDTH, 1)

	local logo = left:CreateTexture(nil, "ARTWORK")
	logo:SetSize(56, 56)
	logo:SetPoint("TOPLEFT")
	logo:SetTexture(ABOUT.logo)

	local title = W.Text(left, "GameFontNormalHuge", W.GOLD)
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -6)
	title:SetText(ns.title)

	local madeBy = W.Text(left, "GameFontHighlight")
	madeBy:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	madeBy:SetText(L.ABOUT_MADE_BY)

	local tagline = W.Text(left, "GameFontHighlight")
	tagline:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
	tagline:SetWidth(COLUMN_WIDTH)
	tagline:SetWordWrap(true)
	tagline:SetText(L.ABOUT_TAGLINE)

	local details = W.Text(left, "GameFontHighlight")
	details:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -14)
	details:SetWidth(COLUMN_WIDTH)
	details:SetSpacing(4)
	details:SetText(L.ABOUT_DETAILS:format(ns.version))

	local discordHeader = W.Header(left, "Discord")
	discordHeader:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -24)

	local discordText = W.Text(left, "GameFontHighlight")
	discordText:SetPoint("TOPLEFT", discordHeader, "BOTTOMLEFT", 0, -6)
	discordText:SetWidth(COLUMN_WIDTH)
	discordText:SetWordWrap(true)
	discordText:SetText(L.ABOUT_DISCORD)

	local discordField = CopyField(left, ABOUT.discord)
	discordField:SetPoint("TOPLEFT", discordText, "BOTTOMLEFT", 4, -8)

	-- Right column: links and the other addons.
	local right = CreateFrame("Frame", nil, content)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", COLUMN_GAP, 0)
	right:SetSize(COLUMN_WIDTH, 1)

	local linksHeader = W.Header(right, L.ABOUT_LINKS)
	linksHeader:SetPoint("TOPLEFT")

	local linksNote = W.Text(right, "GameFontDisableSmall")
	linksNote:SetPoint("TOPLEFT", linksHeader, "BOTTOMLEFT", 0, -4)
	linksNote:SetText(L.ABOUT_LINKS_NOTE)

	local links = {
		{ "Discord", ABOUT.discord },
		{ "CurseForge", ABOUT.curseforge },
		{ "Wago", ABOUT.wago },
		{ "GitHub", ABOUT.github },
		{ L.ABOUT_REPORT_BUG, ABOUT.github .. "/issues" },
		{ L.ABOUT_SUPPORT, ABOUT.tip },
	}
	local anchor, offset = linksNote, -10
	for _, link in ipairs(links) do
		local label = W.Text(right, "GameFontNormal")
		label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
		label:SetSize(LABEL_WIDTH, 24)
		label:SetJustifyV("MIDDLE")
		label:SetText(link[1])
		local field = CopyField(right, link[2])
		field:SetPoint("LEFT", label, "RIGHT", 4, 0)
		anchor, offset = label, -6
	end

	local moreHeader = W.Header(right, L.ABOUT_MORE_ADDONS)
	moreHeader:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -24)
	anchor = moreHeader
	for _, other in ipairs(ABOUT.others) do
		local name = W.Text(right, "GameFontNormal")
		name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, anchor == moreHeader and -8 or -10)
		name:SetText(other[1])
		local note = W.Text(right, "GameFontHighlightSmall")
		note:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
		note:SetWidth(COLUMN_WIDTH)
		note:SetWordWrap(true)
		note:SetText(L[other[2]])
		anchor = note
	end

	function page:Refresh() end

	return page
end

UI.RegisterTab(4, L.ABOUT, Build)
