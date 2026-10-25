-- luacheck: read globals tinsert UIParent UISpecialFrames PanelTemplates_SetNumTabs PanelTemplates_SetTab
local _, ns = ...

-- Main window: portrait frame with three tabs at the bottom and a status
-- line. Tabs register themselves with UI.RegisterTab and are built on first
-- show.
local UI = {}
ns.UI = UI

local L = ns.L
local W = ns.Widgets
local Store = ns.Store
local Sync = ns.Sync

local FRAME_NAME = "GuildFinderForeverFrame"
local WIDTH, HEIGHT = 900, 580
local PORTRAIT = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
-- Delay that bundles bursts of ad changes into one refresh.
local REFRESH_DELAY = 0.5

ns.dbDefaults.settings = {
	window = {},
	tab = 1,
}

local tabDefs = {}
local frame

-- builder(content) returns a tab object with :Refresh() and optionally
-- :OnShow() and :OnAdsChanged() (instead of a full refresh); called once, on
-- first show of the tab.
function UI.RegisterTab(index, label, builder)
	tabDefs[index] = { label = label, builder = builder }
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint()
	local saved = ns.db.settings.window
	saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
end

local function RestorePosition()
	local saved = ns.db.settings.window
	frame:ClearAllPoints()
	if saved.point then
		frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
	else
		frame:SetPoint("CENTER")
	end
end

local status = {}

function UI.SetMatchCount(text)
	status.matchText = text
	UI.UpdateStatus()
end

function UI.UpdateStatus()
	if not frame then
		return
	end
	local parts = {}
	if ns.Channel.ready then
		parts[#parts + 1] = "|TInterface\\COMMON\\Indicator-Green:14|t" .. L.STATUS_CONNECTED
	else
		parts[#parts + 1] = "|TInterface\\COMMON\\Indicator-Red:14|t" .. L.STATUS_DISCONNECTED
	end
	parts[#parts + 1] = "|cffffd100" .. ns.Ads.GetScopeText() .. "|r"
	-- The addon channel is per faction: say so, the other one never shows up live.
	local faction = ns.Ads.GetFactionCode()
	if faction then
		parts[#parts + 1] = L.STATUS_FACTION_ONLY:format(W.FactionText(faction, ns.Filters.FactionName(faction)))
	end
	local live = Store.Count()
	parts[#parts + 1] = L.STATUS_CACHED:format(live)
	if status.matchText then
		parts[#parts + 1] = "|cffffffff" .. status.matchText .. "|r"
	end
	if ns.Comm.InLockdown() then
		parts[#parts + 1] = "|cffffd100" .. L.STATUS_LOCKDOWN .. "|r"
	end
	frame.statusLeft:SetText(table.concat(parts, "    "))
	if Sync.lastSync then
		frame.statusRight:SetText(L.STATUS_SYNC:format(W.Duration(GetServerTime() - Sync.lastSync)))
	else
		frame.statusRight:SetText(L.STATUS_NO_SYNC)
	end
end

-- Tabs as wide as their label: the template's own sizing truncates longer
-- (translated) labels. Runs again after selection changes the font.
local TAB_SIDES, TAB_MIN = 40, 80
local function FitTab(tab)
	local text = tab:GetFontString()
	text:SetWidth(0)
	tab:SetWidth(math.max(TAB_MIN, text:GetStringWidth() + TAB_SIDES))
end

local function SelectTab(index)
	ns.db.settings.tab = index
	PanelTemplates_SetTab(frame, index)
	for _, tab in ipairs(frame.Tabs) do
		FitTab(tab)
	end
	for i, def in ipairs(tabDefs) do
		local content = frame.contents[i]
		if i == index then
			if not def.object then
				def.object = def.builder(content)
			end
			content:Show()
			if def.object.OnShow then
				def.object:OnShow()
			end
			def.object:Refresh()
		else
			content:Hide()
		end
	end
	status.matchText = nil
	if tabDefs[index].object.GetStatusText then
		status.matchText = tabDefs[index].object:GetStatusText()
	end
	UI.UpdateStatus()
end

function UI.GetFrame()
	return frame
end

function UI.GetCurrentTab()
	local def = frame and tabDefs[frame.selectedTab]
	return def and def.object
end

local refreshTimer
local function RefreshSoon()
	if not frame or not frame:IsShown() or refreshTimer then
		return
	end
	refreshTimer = C_Timer.NewTimer(REFRESH_DELAY, function()
		refreshTimer = nil
		if frame:IsShown() then
			local tab = UI.GetCurrentTab()
			if tab and tab.OnAdsChanged then
				tab:OnAdsChanged()
			elseif tab then
				tab:Refresh()
			end
			UI.UpdateStatus()
		end
	end)
end

local function Create()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	if frame.SetTitle then
		frame:SetTitle(ns.title)
	end
	if frame.SetPortraitToAsset then
		frame:SetPortraitToAsset(PORTRAIT)
	end
	-- Escape closes the window.
	tinsert(UISpecialFrames, FRAME_NAME)
	RestorePosition()

	frame.contents = {}
	frame.Tabs = {}
	for i, def in ipairs(tabDefs) do
		local content = CreateFrame("Frame", nil, frame)
		-- Left gutter keeps the portrait clear.
		content:SetPoint("TOPLEFT", 58, -30)
		content:SetPoint("BOTTOMRIGHT", -12, 28)
		content:Hide()
		frame.contents[i] = content

		local tab = CreateFrame("Button", FRAME_NAME .. "Tab" .. i, frame, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(def.label)
		if i == 1 then
			tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
		else
			tab:SetPoint("TOPLEFT", frame.Tabs[i - 1], "TOPRIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function(self)
			SelectTab(self:GetID())
		end)
		tab:HookScript("OnShow", FitTab)
		FitTab(tab)
		frame.Tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(frame, #tabDefs)

	local statusBar = CreateFrame("Frame", nil, frame)
	statusBar:SetPoint("BOTTOMLEFT", 60, 6)
	statusBar:SetPoint("BOTTOMRIGHT", -14, 6)
	statusBar:SetHeight(18)
	frame.statusLeft = W.Text(statusBar, "GameFontHighlightSmall", W.MUTED)
	frame.statusLeft:SetPoint("LEFT")
	frame.statusRight = W.Text(statusBar, "GameFontHighlightSmall", W.MUTED)
	frame.statusRight:SetPoint("RIGHT")

	frame:SetScript("OnShow", function()
		ns.Filters.newMatches = 0
		local tab = UI.GetCurrentTab()
		if tab then
			if tab.OnShow then
				tab:OnShow()
			end
			tab:Refresh()
		end
		UI.UpdateStatus()
	end)
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed > 15 then
			elapsed = 0
			UI.UpdateStatus()
		end
	end)

	local saved = ns.db.settings.tab
	SelectTab(tabDefs[saved] and saved or 1)
end

function UI.Show(tabIndex)
	if not ns.db then
		return
	end
	if not frame then
		Create()
	end
	frame:Show()
	ns.Filters.newMatches = 0
	if tabIndex and tabDefs[tabIndex] then
		SelectTab(tabIndex)
	end
end

function UI.Hide()
	if frame then
		frame:Hide()
	end
end

function UI.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		UI.Show()
	end
end

ns.RegisterCallback(UI, "GFF_ADS_CHANGED", RefreshSoon)
ns.RegisterCallback(UI, "GFF_CHANNEL_READY", function()
	UI.UpdateStatus()
end)
ns.RegisterCallback(UI, "GFF_CHANNEL_LEFT", function()
	UI.UpdateStatus()
end)
