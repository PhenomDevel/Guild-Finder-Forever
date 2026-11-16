-- luacheck: read globals Settings MinimalSliderWithSteppersMixin SettingsPanel CreateSettingsButtonInitializer UIParent UISpecialFrames SAVE CANCEL
local _, ns = ...

-- Options → AddOns → Guild Finder Forever.
local L = ns.L

ns.dbDefaults.settings.notifyNew = true
ns.dbDefaults.settings.staleDays = ns.Constants.STALE_DAYS
ns.dbDefaults.settings.removeDays = ns.Constants.REMOVE_DAYS
ns.dbDefaults.settings.whisperPrefill = false
ns.dbDefaults.settings.whisperText = ""

-- "Outdated after" must stay below "removed after"; moving one slider past
-- the other pushes the other along.
local function AddAgeSliders(category, saved)
	if not (Settings.CreateSlider and Settings.CreateSliderOptions) then
		return
	end
	local Ads = ns.Ads
	local maxDays = ns.Constants.AD_LIFETIME / ns.Constants.DAY
	local staleSetting, removeSetting

	local function Options(low, high)
		local options = Settings.CreateSliderOptions(low, high, 1)
		if MinimalSliderWithSteppersMixin and options.SetLabelFormatter then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				return L.SETTING_DAYS:format(value)
			end)
		end
		return options
	end

	staleSetting = Settings.RegisterProxySetting(category, "GFF_STALE_DAYS", Settings.VarType.Number, L.SETTING_STALE,
		ns.Constants.STALE_DAYS, Ads.GetStaleDays, function(value)
			saved.staleDays = math.floor(value + 0.5)
			if Ads.GetRemoveDays() <= value and removeSetting then
				removeSetting:SetValue(value + 1)
			end
			ns:Fire("GFF_ADS_CHANGED", nil)
		end)
	Settings.CreateSlider(category, staleSetting, Options(1, maxDays - 1), L.SETTING_STALE_TIP)

	removeSetting = Settings.RegisterProxySetting(category, "GFF_REMOVE_DAYS", Settings.VarType.Number, L.SETTING_REMOVE,
		ns.Constants.REMOVE_DAYS, Ads.GetRemoveDays, function(value)
			saved.removeDays = math.floor(value + 0.5)
			if Ads.GetStaleDays() >= value and staleSetting then
				staleSetting:SetValue(value - 1)
			end
			ns:Fire("GFF_ADS_CHANGED", nil)
		end)
	Settings.CreateSlider(category, removeSetting, Options(2, maxDays), L.SETTING_REMOVE_TIP:format(maxDays))
end

-- The settings panel has no text input, so the own whisper message is
-- edited in a small dialog on top of it.
local messageDialog

local function OpenMessageDialog(saved)
	local W = ns.Widgets
	if not messageDialog then
		local dialog = W.Panel(UIParent, { 0.06, 0.06, 0.06, 0.98 }, { 0.3, 0.3, 0.3, 1 })
		dialog:SetSize(440, 220)
		dialog:SetPoint("CENTER")
		dialog:SetFrameStrata("FULLSCREEN_DIALOG")
		dialog:EnableMouse(true)
		_G.GuildFinderForeverWhisperText = dialog
		table.insert(UISpecialFrames, "GuildFinderForeverWhisperText")

		local title = W.Header(dialog, L.SETTING_WHISPER_TEXT)
		title:SetPoint("TOPLEFT", 16, -14)
		local hint = W.Text(dialog, "GameFontHighlightSmall", W.MUTED)
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
		hint:SetWidth(408)
		hint:SetText(L.SETTING_WHISPER_TEXT_HINT)

		dialog.area = W.TextArea(dialog, 408, 80, ns.Greetings.MAX_LENGTH)
		dialog.area:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
		-- The whisper limit counts bytes, not letters.
		dialog.area.editBox:SetMaxBytes(ns.Greetings.MAX_LENGTH + 1)

		local cancel = W.Button(dialog, CANCEL, 100, function()
			dialog:Hide()
		end)
		cancel:SetPoint("BOTTOMRIGHT", -16, 14)
		local save = W.Button(dialog, SAVE, 100, function()
			-- One line: a line break would end the whisper early.
			local text = dialog.area:GetText():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
			dialog.saved.whisperText = text
			dialog:Hide()
		end)
		save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)
		messageDialog = dialog
	end
	messageDialog.saved = saved
	messageDialog.area:SetText(saved.whisperText)
	messageDialog:Show()
	messageDialog.area.editBox:SetFocus()
end

local function AddWhisperSettings(category, layout, saved)
	local prefill = Settings.RegisterProxySetting(category, "GFF_WHISPER_PREFILL", Settings.VarType.Boolean, L.SETTING_WHISPER, false, function()
		return saved.whisperPrefill
	end, function(value)
		saved.whisperPrefill = value
	end)
	Settings.CreateCheckbox(category, prefill, L.SETTING_WHISPER_TIP)

	layout = layout or SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)
	if layout and layout.AddInitializer and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer(L.SETTING_WHISPER_TEXT, L.SETTING_WHISPER_TEXT_EDIT, function()
			OpenMessageDialog(saved)
		end, L.SETTING_WHISPER_TEXT_TIP, true))
	end
end

local function Register()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)
	local saved = ns.db.settings

	local showMinimap = Settings.RegisterProxySetting(category, "GFF_SHOW_MINIMAP", Settings.VarType.Boolean, L.SETTING_MINIMAP, true, function()
		return not saved.minimapHidden
	end, function(value)
		saved.minimapHidden = not value
		ns.MinimapButton.Update()
	end)
	Settings.CreateCheckbox(category, showMinimap, L.SETTING_MINIMAP_TIP)

	local notify = Settings.RegisterProxySetting(category, "GFF_NOTIFY_NEW", Settings.VarType.Boolean, L.SETTING_NOTIFY, true, function()
		return saved.notifyNew
	end, function(value)
		saved.notifyNew = value
	end)
	Settings.CreateCheckbox(category, notify, L.SETTING_NOTIFY_TIP)

	AddAgeSliders(category, saved)
	AddWhisperSettings(category, layout, saved)

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns:OpenSettings()
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end

ns.RegisterCallback({}, "GFF_DB_READY", Register)
