-- luacheck: read globals UIParent UISpecialFrames C_Timer
local _, ns = ...

-- Welcome dialog on the first start: the addon only knows what other players
-- running it share, so the lists start out nearly empty. Development
-- checkouts (ns.DEV) show it on every login.
local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local WIDTH = 460
local PAD = 22
local TEXT_WIDTH = WIDTH - 2 * PAD - 18
local SHOW_DELAY = 3 -- after the loading screen and login chat spam

ns.dbDefaults.settings.seenWelcome = false

local dialog

local function Close()
	ns.db.settings.seenWelcome = true
	dialog:Hide()
end

local function Create()
	dialog = W.Panel(UIParent, { 0.07, 0.065, 0.06, 0.98 }, { 0.79, 0.635, 0.29, 1 })
	-- Named so Escape closes it.
	_G.GuildFinderForeverWelcome = dialog
	table.insert(UISpecialFrames, "GuildFinderForeverWelcome")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetPoint("CENTER", 0, 80)
	dialog:EnableMouse(true)
	dialog:SetMovable(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:SetScript("OnHide", function()
		ns.db.settings.seenWelcome = true
	end)

	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", Close)

	local emblem = W.GuildEmblem(dialog, 44)
	emblem:SetPoint("TOPLEFT", PAD, -PAD)
	emblem:SetGuild(ns.title)

	local title = W.Text(dialog, "GameFontNormalLarge", W.GOLD)
	title:SetPoint("LEFT", emblem, "RIGHT", 12, 8)
	title:SetText(L.WELCOME_TITLE)
	local subtitle = W.Text(dialog, "GameFontHighlightSmall", W.MUTED)
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	subtitle:SetText(L.WELCOME_SUBTITLE)

	-- Paragraphs with a gold heading each, stacked below the title.
	dialog.blocks = {}
	for i = 1, 3 do
		local dot = W.Dot(dialog, 8, W.GOLD)
		local header = W.Header(dialog, L["WELCOME_HEAD" .. i])
		header:SetPoint("LEFT", dot, "RIGHT", 10, 0)
		local text = W.Text(dialog, "GameFontHighlight", W.TEXT)
		text:SetWidth(TEXT_WIDTH)
		text:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
		text:SetSpacing(2)
		text:SetText(L["WELCOME_TEXT" .. i])
		dialog.blocks[i] = { dot = dot, header = header, text = text }
	end

	dialog.dev = W.Text(dialog, "GameFontDisableSmall", W.MUTED)
	dialog.dev:SetWidth(WIDTH - 2 * PAD)
	dialog.dev:SetText(L.WELCOME_DEV)

	dialog.ok = W.Button(dialog, L.WELCOME_OK, 120, Close)
	dialog.ok:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	dialog.create = W.Button(dialog, L.INTRO_CREATE, nil, function()
		Close()
		UI.Show(3)
	end)
	dialog.create:SetPoint("RIGHT", dialog.ok, "LEFT", -8, 0)
end

-- Text heights are known only once the strings are laid out.
local function Layout()
	local y = -PAD - 44 - 20
	for _, block in ipairs(dialog.blocks) do
		block.dot:ClearAllPoints()
		block.dot:SetPoint("TOPLEFT", PAD, y - 4)
		y = y - block.header:GetStringHeight() - 4 - block.text:GetStringHeight() - 16
	end
	dialog.dev:ClearAllPoints()
	dialog.dev:SetShown(ns.DEV == true)
	if ns.DEV then
		dialog.dev:SetPoint("TOPLEFT", PAD, y)
		y = y - dialog.dev:GetStringHeight() - 12
	end
	dialog:SetSize(WIDTH, -y + 24 + 2 * PAD - 8)
end

local function Show()
	if not dialog then
		Create()
	end
	dialog:Show()
	Layout()
end

ns:RegisterEvent("PLAYER_LOGIN", function()
	if ns.DEV or not ns.db.settings.seenWelcome then
		C_Timer.After(SHOW_DELAY, Show)
	end
end)
