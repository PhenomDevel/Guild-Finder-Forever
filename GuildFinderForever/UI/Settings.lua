-- luacheck: read globals Settings SettingsPanel CreateSettingsButtonInitializer
local _, ns = ...

-- Settings tab of the main window. The game's own options (Options →
-- AddOns) only hold a button that opens it.
local L = ns.L
local UI = ns.UI
local W = ns.Widgets
local Ads = ns.Ads

local TAB_INDEX = 4
local COLUMN_WIDTH = 380
local COLUMN_GAP = 40
local INDENT = 30

ns.dbDefaults.settings.notifyNew = true
ns.dbDefaults.settings.staleDays = ns.Constants.STALE_DAYS
ns.dbDefaults.settings.removeDays = ns.Constants.REMOVE_DAYS
ns.dbDefaults.settings.whisperPrefill = false
ns.dbDefaults.settings.whisperText = ""

-- Muted explanation under an option, as wide as the column allows.
local function Note(parent, anchor, text, indent)
	local note = W.Text(parent, "GameFontHighlightSmall", W.MUTED)
	note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", indent or 0, -2)
	note:SetWidth(COLUMN_WIDTH - INDENT)
	note:SetWordWrap(true)
	note:SetText(text)
	return note
end

-- Checkbox with its label to the right and the explanation below.
-- Returns the checkbox and the region the next option anchors to.
local function Checkbox(parent, anchor, offset, label, tip, get, set)
	local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	box:SetSize(26, 26)
	box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor.indented and -INDENT or 0, offset)
	local text = W.Text(parent, "GameFontHighlight")
	text:SetPoint("LEFT", box, "RIGHT", 4, 0)
	text:SetText(label)
	box:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	function box:Refresh()
		self:SetChecked(get() and true or false)
	end
	local note = Note(parent, box, tip, INDENT)
	note.indented = true
	return box, note
end

local function Build(content)
	local page = {}
	local saved = ns.db.settings
	local controls = {}

	local left = CreateFrame("Frame", nil, content)
	left:SetPoint("TOPLEFT", 16, -16)
	left:SetSize(COLUMN_WIDTH, 1)

	local general = W.Header(left, L.SETTINGS_GENERAL)
	general:SetPoint("TOPLEFT")

	local anchor
	controls[#controls + 1], anchor = Checkbox(left, general, -8, L.SETTING_MINIMAP, L.SETTING_MINIMAP_TIP, function()
		return not saved.minimapHidden
	end, function(value)
		saved.minimapHidden = not value
		ns.MinimapButton.Update()
	end)
	controls[#controls + 1], anchor = Checkbox(left, anchor, -10, L.SETTING_NOTIFY, L.SETTING_NOTIFY_TIP, function()
		return saved.notifyNew
	end, function(value)
		saved.notifyNew = value
	end)

	-- "Outdated after" must stay below "removed after"; stepping one past
	-- the other pushes the other along.
	local maxDays = ns.Constants.AD_LIFETIME / ns.Constants.DAY
	local outdated = W.Header(left, L.SETTINGS_OUTDATED)
	outdated:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -INDENT, -24)

	local staleStepper, removeStepper
	local function Days(above, offset, label, tip, min, max, get, set)
		local text = W.Text(left, "GameFontHighlight")
		text:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, offset)
		text:SetText(label)
		local stepper = W.Stepper(left, min, max, get, function(value)
			-- Below the minimum the stepper hands over nil ("no value").
			set(value or min)
			staleStepper:Refresh()
			removeStepper:Refresh()
			ns:Fire("GFF_ADS_CHANGED", nil)
		end, L.SETTING_DAYS, 110)
		stepper:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -6)
		controls[#controls + 1] = stepper
		return stepper, Note(left, stepper, tip)
	end
	staleStepper, anchor = Days(outdated, -10, L.SETTING_STALE, L.SETTING_STALE_TIP, 1, maxDays - 1, Ads.GetStaleDays, function(value)
		saved.staleDays = value
		if Ads.GetRemoveDays() <= value then
			saved.removeDays = value + 1
		end
	end)
	anchor:SetPoint("TOPLEFT", staleStepper, "BOTTOMLEFT", 0, -6)
	removeStepper, anchor = Days(anchor, -14, L.SETTING_REMOVE, L.SETTING_REMOVE_TIP:format(maxDays), 2, maxDays, Ads.GetRemoveDays, function(value)
		saved.removeDays = value
		if Ads.GetStaleDays() >= value then
			saved.staleDays = value - 1
		end
	end)
	anchor:SetPoint("TOPLEFT", removeStepper, "BOTTOMLEFT", 0, -6)

	local right = CreateFrame("Frame", nil, content)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", COLUMN_GAP, 0)
	right:SetSize(COLUMN_WIDTH, 1)

	local whisper = W.Header(right, L.SETTINGS_WHISPER)
	whisper:SetPoint("TOPLEFT")
	controls[#controls + 1], anchor = Checkbox(right, whisper, -8, L.SETTING_WHISPER, L.SETTING_WHISPER_TIP, function()
		return saved.whisperPrefill
	end, function(value)
		saved.whisperPrefill = value
	end)

	local messageLabel = W.Text(right, "GameFontHighlight")
	messageLabel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -INDENT, -18)
	messageLabel:SetText(L.SETTING_WHISPER_TEXT)
	local message = W.TextArea(right, COLUMN_WIDTH, 90, ns.Greetings.MAX_LENGTH, function(text)
		saved.whisperText = text
	end)
	message:SetPoint("TOPLEFT", messageLabel, "BOTTOMLEFT", 0, -6)
	-- The whisper limit counts bytes, not letters.
	message.editBox:SetMaxBytes(ns.Greetings.MAX_LENGTH + 1)
	local hint = Note(right, message, L.SETTING_WHISPER_TEXT_HINT)
	hint:SetPoint("TOPLEFT", message, "BOTTOMLEFT", 0, -8)

	function page:Refresh()
		for _, control in ipairs(controls) do
			control:Refresh()
		end
		if not message.editBox:HasFocus() then
			message:SetText(saved.whisperText)
		end
	end

	return page
end

UI.RegisterTab(TAB_INDEX, L.TAB_SETTINGS, Build)

function ns:OpenSettings()
	UI.Show(TAB_INDEX)
end

-- Options → AddOns → Guild Finder Forever: where players look first.
local function Register()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and CreateSettingsButtonInitializer) then
		return
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)
	layout = layout or SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)
	if not (layout and layout.AddInitializer) then
		return
	end
	layout:AddInitializer(CreateSettingsButtonInitializer(ns.title, L.TAB_SETTINGS, function()
		ns:OpenSettings()
	end, L.SETTINGS_MOVED_TIP, true))
	Settings.RegisterAddOnCategory(category)
end

ns.RegisterCallback({}, "GFF_DB_READY", Register)
