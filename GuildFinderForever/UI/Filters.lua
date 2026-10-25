-- luacheck: read globals MenuUtil GetMaxLevelForPlayerExpansion UnitClass
local _, ns = ...

-- Filter state of the two search tabs (saved per account), the chip bar
-- showing active filters, the "+ Filter" and sort menus, and the chat
-- notice for new matching ads.
local Filters = {}
ns.Filters = Filters

local L = ns.L
local W = ns.Widgets
local C = ns.Constants
local Ads = ns.Ads
local Store = ns.Store
local Search = ns.Search
local MyAds = ns.MyAds

ns.dbDefaults.filters = {}

Filters.SORTS = {
	{ value = "match", label = L.SORT_MATCH },
	{ value = "new", label = L.SORT_NEW },
	{ value = "name", label = L.SORT_NAME },
}

function Filters.MaxLevel()
	return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
end

function Filters.Default(kind)
	local faction = Ads.GetFactionCode()
	local filter = {
		kind = kind,
		text = "",
		factions = { A = faction ~= "H", H = faction == "H" },
		lang = C.DefaultLanguage(),
		goals = 0,
		myTimes = false,
		sameMode = true,
		sort = "match",
	}
	if kind == Ads.KIND_PLAYER then
		filter.roles = 0
		filter.minLevel = 1
		filter.maxLevel = Filters.MaxLevel()
	end
	return filter
end

function Filters.Get(kind)
	local saved = ns.db.filters[kind]
	if type(saved) ~= "table" then
		saved = Filters.Default(kind)
		ns.db.filters[kind] = saved
	end
	saved.kind = kind
	saved.sort = saved.sort or "match"
	-- The player search always looks at the own faction (the guild's).
	if kind == Ads.KIND_PLAYER then
		local faction = Ads.GetFactionCode()
		saved.factions = { A = faction == "A", H = faction == "H" }
	end
	return saved
end

-- What the searcher brings, for the match score: the player draft when
-- looking for a guild, the guild draft when looking for players.
function Filters.Profile(kind)
	local draft
	if kind == Ads.KIND_GUILD then
		draft = MyAds.GetPlayerDraft()
	elseif Ads.GetGuild() then
		draft = MyAds.GetGuildDraft()
	end
	draft = draft or {}
	local classId
	if kind == Ads.KIND_GUILD then
		classId = select(3, UnitClass("player"))
	end
	return {
		goals = draft.goals or 0, times = draft.times or 0, roles = draft.roles or 0, lang = draft.lang,
		moreLangs = draft.moreLangs,
		classes = kind == Ads.KIND_PLAYER and draft.classes or 0, classId = classId,
		classRoles = kind == Ads.KIND_PLAYER and draft.classRoles or nil,
	}
end

function Filters.Run(kind)
	local filter = Filters.Get(kind)
	local results = Search.Run(filter, Filters.Profile(kind))
	if filter.sort == "new" then
		table.sort(results, function(a, b)
			return a.ad.v > b.ad.v
		end)
	elseif filter.sort == "name" then
		table.sort(results, function(a, b)
			local na = (a.ad.n or Ads.OwnerName(a.ad.o)):lower()
			local nb = (b.ad.n or Ads.OwnerName(b.ad.o)):lower()
			return na < nb
		end)
	end
	return results
end

-- Whether a raid guild ad wants the own class in a role the own player ad
-- names (all roles of the class if it names none). Returns nil (no raid
-- ad), "fit" plus roles mask, or "no".
function Filters.ClassFit(ad)
	if not C.HasBit(ad.g or 0, C.GOAL_RAID) then
		return nil
	end
	local _, classFile, classId = UnitClass("player")
	if not classId then
		return nil
	end
	-- No class list: every class is welcome in the ad's general roles.
	local wanted
	if (ad.cl or 0) > 0 then
		wanted = C.WantedRoles(ad, { id = classId, key = classFile })
	else
		wanted = (ad.r or 0) > 0 and ad.r or C.ClassRoles(classFile)
	end
	local mine = MyAds.GetPlayerDraft().roles or 0
	if mine == 0 then
		mine = C.ClassRoles(classFile)
	end
	local match = 0
	for _, role in ipairs(C.ROLES) do
		if C.HasBit(wanted, role.bit) and C.HasBit(mine, role.bit) then
			match = match + role.bit
		end
	end
	if match == 0 then
		return "no"
	end
	return "fit", match
end

function Filters.FactionName(code)
	return code == "H" and L.FACTION_HORDE or L.FACTION_ALLIANCE
end

-- "Deutsch, English" for all languages of an ad.
function Filters.LanguagesText(ad)
	local names = {}
	for i, key in ipairs(C.AdLanguages(ad)) do
		names[i] = Filters.LanguageName(key)
	end
	return table.concat(names, ", ")
end

function Filters.LanguageName(key)
	local lang = C.LANGUAGE_BY_KEY[key]
	return lang and lang.label or (key and key:upper()) or "?"
end

local function HiddenCount()
	local count = 0
	for _ in pairs(ns.db.hidden) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------------

-- Fills a filter menu; changed() runs after every change.
local function BuildFilterMenu(root, kind, changed)
	local filter = Filters.Get(kind)
	if kind == Ads.KIND_GUILD then
		root:CreateTitle(L.FILTER_FACTION)
		for _, code in ipairs({ "A", "H" }) do
			root:CreateCheckbox(Filters.FactionName(code), function()
				return filter.factions[code]
			end, function()
				filter.factions[code] = not filter.factions[code]
				changed()
			end)
		end
	end
	local langMenu = root:CreateButton(L.FILTER_LANGUAGE)
	langMenu:CreateRadio(L.ALL_LANGUAGES, function()
		return filter.lang == nil
	end, function()
		filter.lang = nil
		changed()
	end)
	for _, lang in ipairs(C.LANGUAGES) do
		langMenu:CreateRadio(lang.label, function()
			return filter.lang == lang.key
		end, function()
			filter.lang = lang.key
			changed()
		end)
	end
	root:CreateTitle(L.FILTER_GOALS)
	for _, goal in ipairs(C.GOALS) do
		root:CreateCheckbox(goal.label, function()
			return C.HasBit(filter.goals, goal.bit)
		end, function()
			filter.goals = C.SetBit(filter.goals, goal.bit, not C.HasBit(filter.goals, goal.bit))
			changed()
		end)
	end
	if kind == Ads.KIND_GUILD then
		local styleMenu = root:CreateButton(L.FILTER_STYLE)
		styleMenu:CreateRadio(L.ANY_STYLE, function()
			return filter.style == nil
		end, function()
			filter.style = nil
			changed()
		end)
		for _, style in ipairs(C.STYLES) do
			styleMenu:CreateRadio(style.label, function()
				return filter.style == style.value
			end, function()
				filter.style = style.value
				changed()
			end)
		end
	end
	root:CreateTitle(L.FILTER_OTHER)
	if C.SHOW_TIMES then
		root:CreateCheckbox(L.FILTER_MY_TIMES, function()
			return filter.myTimes
		end, function()
			filter.myTimes = not filter.myTimes
			changed()
		end)
	end
	if kind == Ads.KIND_GUILD then
		root:CreateCheckbox(L.FILTER_MY_CLASS, function()
			return filter.myClass
		end, function()
			filter.myClass = not filter.myClass
			changed()
		end)
	end
	-- Rulesets exist only on Forever.
	if Ads.IsForever() then
		root:CreateCheckbox(L.FILTER_SAME_MODE, function()
			return filter.sameMode
		end, function()
			filter.sameMode = not filter.sameMode
			changed()
		end)
	end
	root:CreateDivider()
	root:CreateButton(L.FILTER_RESET, function()
		ns.db.filters[kind] = Filters.Default(kind)
		changed()
	end)
	local hidden = HiddenCount()
	if hidden > 0 then
		root:CreateButton(L.SHOW_HIDDEN_COUNT:format(hidden), function()
			Store.ClearHidden()
		end)
	end
end

local function OpenMenu(owner, generator)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, generator)
	end
end

--------------------------------------------------------------------------------
-- Chip bar
--------------------------------------------------------------------------------

-- Chips for the active filters (click removes the filter), then "+ Filter".
-- Returns a bar frame with :Update(); changed() runs after every change.
function Filters.ChipBar(parent, kind, changed)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(22)
	local pool = {}
	local addChip = W.Chip(bar, function(self)
		OpenMenu(self, function(_, root)
			BuildFilterMenu(root, kind, function()
				changed()
				bar:Update()
			end)
		end)
	end)
	addChip:SetLabel(L.ADD_FILTER)

	local function Remove(self)
		self.remove()
		changed()
		bar:Update()
	end

	function bar:Update()
		local filter = Filters.Get(kind)
		local items = {}
		if kind == Ads.KIND_GUILD and filter.factions.A ~= filter.factions.H then
			items[#items + 1] = { Filters.FactionName(filter.factions.A and "A" or "H"), function()
				filter.factions.A, filter.factions.H = true, true
			end }
		end
		if filter.lang then
			items[#items + 1] = { Filters.LanguageName(filter.lang), function()
				filter.lang = nil
			end }
		end
		for _, goal in ipairs(C.GOALS) do
			if C.HasBit(filter.goals, goal.bit) then
				items[#items + 1] = { goal.label, function()
					filter.goals = C.SetBit(filter.goals, goal.bit, false)
				end }
			end
		end
		if filter.style then
			items[#items + 1] = { C.StyleName(filter.style) or "?", function()
				filter.style = nil
			end }
		end
		if filter.myTimes and C.SHOW_TIMES then
			items[#items + 1] = { L.CHIP_MY_TIMES, function()
				filter.myTimes = false
			end }
		end
		if filter.myClass then
			items[#items + 1] = { L.CHIP_MY_CLASS, function()
				filter.myClass = false
			end }
		end
		local shown = {}
		for i, item in ipairs(items) do
			local chip = pool[i]
			if not chip then
				chip = W.Chip(bar, Remove)
				pool[i] = chip
			end
			chip:SetLabel(item[1], true)
			chip:SetActive(true)
			chip.remove = item[2]
			chip:Show()
			shown[#shown + 1] = chip
		end
		for i = #items + 1, #pool do
			pool[i]:Hide()
		end
		shown[#shown + 1] = addChip
		local width = W.FlowChips(shown, bar, 0, 0, 6)
		bar:SetWidth(math.max(1, width))
	end

	bar:Update()
	return bar
end

-- Chip-styled sort button.
function Filters.SortButton(parent, kind, changed)
	local chip
	local function Label()
		local filter = Filters.Get(kind)
		for _, sort in ipairs(Filters.SORTS) do
			if sort.value == filter.sort then
				return sort.label
			end
		end
		return Filters.SORTS[1].label
	end
	chip = W.Chip(parent, function(self)
		OpenMenu(self, function(_, root)
			root:CreateTitle(L.SORT)
			for _, sort in ipairs(Filters.SORTS) do
				root:CreateRadio(sort.label, function()
					return Filters.Get(kind).sort == sort.value
				end, function()
					Filters.Get(kind).sort = sort.value
					chip:SetLabel(Label() .. " " .. W.ARROW_DOWN)
					changed()
				end)
			end
		end)
	end)
	function chip:Update()
		self:SetLabel(Label() .. " " .. W.ARROW_DOWN)
	end
	chip:Update()
	return chip
end

--------------------------------------------------------------------------------
-- Chat notices
--------------------------------------------------------------------------------
-- Only while the own side is posted: a player ad → new guild ads, a guild
-- ad → new player ads. At most one line per NOTIFY_INTERVAL. The count also
-- shows in the minimap tooltip until the window is opened.

local NOTIFY_INTERVAL = 60
local pendingNotice = {}
local noticeTimer

Filters.newMatches = 0

local function FlushNotice()
	noticeTimer = nil
	local count = #pendingNotice
	if count == 0 then
		return
	end
	local first = pendingNotice[1]
	local name = first.k == Ads.KIND_GUILD and ("<" .. first.n .. ">") or Ads.OwnerName(first.o)
	if count == 1 then
		ns:Print(first.k == Ads.KIND_GUILD and L.NOTIFY_GUILD or L.NOTIFY_PLAYER, name)
	else
		ns:Print(first.k == Ads.KIND_GUILD and L.NOTIFY_GUILDS or L.NOTIFY_PLAYERS, name, count - 1)
	end
	wipe(pendingNotice)
end

ns.RegisterCallback(Filters, "GFF_AD_RECEIVED", function(_, ad, isNew)
	if not isNew then
		return
	end
	local looking
	if ad.k == Ads.KIND_GUILD then
		looking = MyAds.GetPlayerAd()
	else
		looking = MyAds.GetGuildAd()
	end
	if not looking or not Search.Accepts(ad, Filters.Get(ad.k), Filters.Profile(ad.k)) then
		return
	end
	Filters.newMatches = Filters.newMatches + 1
	if not ns.db.settings.notifyNew then
		return
	end
	pendingNotice[#pendingNotice + 1] = ad
	-- The first notice goes out right away, later ones are bundled.
	if not noticeTimer then
		FlushNotice()
		noticeTimer = C_Timer.NewTimer(NOTIFY_INTERVAL, FlushNotice)
	end
end)

-- Chat line when contacting found something worth knowing.
ns.RegisterCallback(Filters, "GFF_VERIFY_DONE", function(_, ad, result)
	if result == "suspicious" then
		ns:Print(L.VERIFY_SUSPICIOUS, ad.k == Ads.KIND_GUILD and ("<" .. ad.n .. ">") or Ads.OwnerName(ad.o))
	elseif result == "offline" then
		ns:Print(L.VERIFY_OFFLINE, Ads.OwnerName(ad.o))
	end
end)
