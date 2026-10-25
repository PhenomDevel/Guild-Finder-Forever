-- luacheck: read globals Settings
local _, ns = ...

-- Options → AddOns → Guild Finder Forever.
local L = ns.L

ns.dbDefaults.settings.notifyNew = true

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

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns:OpenSettings()
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end

ns.RegisterCallback({}, "GFF_DB_READY", Register)
