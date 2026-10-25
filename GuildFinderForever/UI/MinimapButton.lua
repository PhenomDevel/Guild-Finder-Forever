-- luacheck: read globals Minimap GameTooltip GetCursorPosition
local _, ns = ...

-- Own minimap button: left click toggles the window, drag moves it around
-- the minimap. The addon compartment entry (.toc) does the same.
local MinimapButton = {}
ns.MinimapButton = MinimapButton

local L = ns.L

local RADIUS_OFFSET = 10
local ICON = "Interface\\AddOns\\GuildFinderForever\\Media\\Logo"

ns.dbDefaults.settings.minimapHidden = false
ns.dbDefaults.settings.minimapAngle = 200

local button

local function UpdatePosition()
	local angle = math.rad(ns.db.settings.minimapAngle or 200)
	local radius = Minimap:GetWidth() / 2 + RADIUS_OFFSET
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	ns.db.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	UpdatePosition()
end

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

local function Create()
	button = CreateFrame("Button", "GuildFinderForeverMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(ICON)
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			ns.UI.Show(3)
		else
			ns.UI.Toggle()
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	UpdatePosition()
end

function MinimapButton.Update()
	if ns.db.settings.minimapHidden then
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		Create()
	end
	button:Show()
end

ns.RegisterCallback(MinimapButton, "GFF_DB_READY", MinimapButton.Update)

-- Addon compartment (.toc AddonCompartmentFunc*).
function GuildFinderForever_OnAddonCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.UI.Show(3)
	else
		ns.UI.Toggle()
	end
end

function GuildFinderForever_OnAddonCompartmentEnter(_, menuButton)
	ShowTooltip(menuButton)
end

function GuildFinderForever_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
