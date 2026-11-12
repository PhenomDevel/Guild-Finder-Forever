-- luacheck: read globals Settings MinimalSliderWithSteppersMixin
local _, ns = ...

-- Options → AddOns → Guild Finder Forever.
local L = ns.L

ns.dbDefaults.settings.notifyNew = true
ns.dbDefaults.settings.staleDays = ns.Constants.STALE_DAYS
ns.dbDefaults.settings.removeDays = ns.Constants.REMOVE_DAYS

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

local function Register()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then
		return
	end
	local category = Settings.RegisterVerticalLayoutCategory(ns.title)
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

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns:OpenSettings()
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end

ns.RegisterCallback({}, "GFF_DB_READY", Register)
