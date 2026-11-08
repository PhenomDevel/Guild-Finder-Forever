-- luacheck: read globals GameTooltip
local _, ns = ...

-- Minimap button via LibDBIcon, so minimap addons (SexyMap, Leatrix Plus,
-- button collectors …) can hide, fade or collect it like other addons'
-- buttons. Left click toggles the window, right click opens "My ad", drag
-- moves it around the minimap. The addon compartment entry (.toc) does the same.
local MinimapButton = {}
ns.MinimapButton = MinimapButton

local L = ns.L

local NAME = "GuildFinderForever"
local ICON = "Interface\\AddOns\\GuildFinderForever\\Media\\Logo"

ns.dbDefaults.settings.minimapHidden = false
ns.dbDefaults.settings.minimapAngle = 200

local LibDBIcon = LibStub("LibDBIcon-1.0")

-- LibDBIcon's db keys mapped onto the existing saved settings.
local DB_KEYS = { minimapPos = "minimapAngle", hide = "minimapHidden" }

local function ShowTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.title, 1, 1, 1)
	local newMatches = ns.Filters.newMatches
	if newMatches > 0 then
		GameTooltip:AddLine(L.MINIMAP_NEW:format(newMatches), 1, 0.82, 0)
	end
	local ad = ns.MyAds.GetPlayerAd()
	if ad then
		GameTooltip:AddLine(L.MINIMAP_AD_ACTIVE:format(ns.Widgets.Duration(ns.Ads.ExpiresIn(ad))), 1, 1, 1)
	else
		GameTooltip:AddLine(L.MINIMAP_AD_NONE, 0.62, 0.62, 0.62)
	end
	GameTooltip:AddLine(L.STATUS_CACHED:format(ns.Store.CountByKind()), 0.62, 0.62, 0.62)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.MINIMAP_LEFT, 0.12, 1, 0)
	GameTooltip:AddLine(L.MINIMAP_RIGHT, 0.12, 1, 0)
	GameTooltip:Show()
end

local function OnClick(mouseButton)
	if mouseButton == "RightButton" then
		ns.UI.Show(3)
	else
		ns.UI.Toggle()
	end
end

local function Register()
	local object = LibStub("LibDataBroker-1.1"):NewDataObject(NAME, {
		type = "launcher",
		icon = ICON,
		OnClick = function(_, mouseButton)
			OnClick(mouseButton)
		end,
		OnEnter = ShowTooltip,
		OnLeave = function()
			GameTooltip:Hide()
		end,
	})
	local db = setmetatable({}, {
		__index = function(_, key)
			local settingsKey = DB_KEYS[key]
			return settingsKey and ns.db.settings[settingsKey]
		end,
		__newindex = function(store, key, value)
			local settingsKey = DB_KEYS[key]
			if settingsKey then
				ns.db.settings[settingsKey] = value
			else
				rawset(store, key, value)
			end
		end,
	})
	LibDBIcon:Register(NAME, object, db)
end

function MinimapButton.Update()
	if not LibDBIcon:IsRegistered(NAME) then
		Register()
	end
	if ns.db.settings.minimapHidden then
		LibDBIcon:Hide(NAME)
	else
		LibDBIcon:Show(NAME)
	end
end

ns.RegisterCallback(MinimapButton, "GFF_DB_READY", MinimapButton.Update)

-- Addon compartment (.toc AddonCompartmentFunc*).
function GuildFinderForever_OnAddonCompartmentClick(_, mouseButton)
	OnClick(mouseButton)
end

function GuildFinderForever_OnAddonCompartmentEnter(_, menuButton)
	ShowTooltip(menuButton)
end

function GuildFinderForever_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
