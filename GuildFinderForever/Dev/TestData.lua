local _, ns = ...

-- /gff testdata: fills the cache with made-up guild and player ads for
-- trying out the UI alone. They live only in this session (Store test
-- ads): never saved, synced or served to others; /reload removes them.
local L = ns.L
local C = ns.Constants
local Ads = ns.Ads
local Store = ns.Store

local HOUR = 3600

-- Role bits
local T, H, D = C.ROLE.TANK, C.ROLE.HEALER, C.ROLE.DAMAGE

-- Play times from { day, slot } pairs; day 1 = Monday, slot 1–3.
local function Times(...)
	local mask = 0
	for i = 1, select("#", ...) do
		local entry = select(i, ...)
		mask = C.SetBit(mask, C.TimeBit(entry[1], entry[2]), true)
	end
	return mask
end

local function Days(...)
	local mask = 0
	for i = 1, select("#", ...) do
		mask = C.SetBit(mask, C.DayBit((select(i, ...))), true)
	end
	return mask
end

local function Goals(...)
	local mask = 0
	for i = 1, select("#", ...) do
		local key = select(i, ...)
		for _, goal in ipairs(C.GOALS) do
			if goal.key == key then
				mask = C.SetBit(mask, goal.bit, true)
			end
		end
	end
	return mask
end

-- Wanted classes: { "PALADIN", roles }, roles 0 = any. Classes this client
-- doesn't have are skipped.
local function Needs(list)
	local classes, classRoles = 0, nil
	for _, entry in ipairs(list) do
		local id = C.ClassId(entry[1])
		if id then
			classes = C.SetBit(classes, C.ClassBit(id), true)
			classRoles = C.SetClassRoles(classRoles, id, entry[2])
		end
	end
	return classes, classRoles
end

local EVENINGS = { { 1, 2 }, { 2, 2 }, { 3, 2 }, { 4, 2 }, { 5, 2 } }
local WEEKEND = { { 6, 1 }, { 6, 2 }, { 7, 1 }, { 7, 2 } }

local GUILDS = {
	{ name = "Silberne Raben", owner = "Lyrandel", lang = "de", members = 87, age = 2,
		goals = { "RAID", "SOCIAL" }, times = Times({ 3, 2 }, { 4, 2 }, { 7, 2 }, { 7, 1 }),
		text = "Entspannt, aber zielstrebig. Wir suchen verlässliche Heiler und einen Offtank.",
		style = 2, days = Days(3, 4, 7), perWeek = 2, start = 19 * 60 + 30, stop = 23 * 60,
		needs = { { "WARRIOR", T }, { "PALADIN", T + H }, { "PRIEST", H }, { "SHAMAN", H + D }, { "DRUID", H },
			{ "MAGE", 0 }, { "HUNTER", 0 }, { "WARLOCK", 0 }, { "EVOKER", D } } },
	{ name = "Eisenwacht", owner = "Brogan", lang = "de", members = 41, age = 20,
		goals = { "RAID" }, times = Times({ 2, 2 }, { 5, 2 }, { 2, 3 }, { 5, 3 }),
		text = "Kleine Truppe mit Mythic-Ambitionen. Heiler dringend gesucht.",
		style = 3, days = Days(2, 5), perWeek = 2, start = 20 * 60, stop = 23 * 60 + 30,
		needs = { { "DEATHKNIGHT", T }, { "PALADIN", H }, { "MONK", H } } },
	{ name = "Nachtschwingen", owner = "Mirelle", lang = "en", members = 120, age = 70,
		goals = { "RAID", "PVP" }, times = Times({ 1, 2 }, { 3, 2 }, { 4, 2 }),
		text = "Ranged-heavy roster, looking for melee damage dealers.",
		style = 2, days = Days(1, 3, 4), perWeek = 3, start = 19 * 60, stop = 22 * 60,
		needs = { { "ROGUE", 0 }, { "DEMONHUNTER", D }, { "WARRIOR", D } } },
	{ name = "Hort der Gefährten", owner = "Tamsin", lang = "de", members = 210, age = 5,
		goals = { "RAID", "SOCIAL", "LEVELING" }, times = Times(unpack(WEEKEND)),
		text = "Gemütlicher Raid am Sonntag, jeder ist willkommen.",
		style = 1, days = Days(7), perWeek = 1, start = 18 * 60, stop = 21 * 60, needs = {} },
	{ name = "Klingen des Ostens", owner = "Corvin", lang = "fr", members = 64, age = 30,
		goals = { "PVP", "SOCIAL" }, times = Times(unpack(EVENINGS)), roles = D,
		text = "Guilde PvP, champs de bataille chaque soir." },
	{ name = "Laternenträger", owner = "Wenna", lang = "de", members = 18, age = 1,
		goals = { "LEVELING", "SOCIAL" }, times = Times({ 6, 1 }, { 7, 1 }, { 3, 2 }), roles = T + H + D,
		text = "Neue Gilde für Twinks und Wiedereinsteiger. Gemeinsam leveln, quatschen, Dungeons." },
	{ name = "Sturmfeste", owner = "Haldor", lang = "de", members = 95, age = 48, other = true,
		goals = { "RAID" }, times = Times({ 3, 2 }, { 5, 2 }),
		text = "Raidgilde der anderen Fraktion, nur zum Testen des Fraktionsfilters.",
		style = 3, days = Days(3, 5), perWeek = 2, start = 20 * 60, stop = 23 * 60,
		needs = { { "PRIEST", H }, { "MAGE", 0 } } },
	{ name = "Glutherz", owner = "Ysolde", lang = "de", members = 33, age = 100, other = true,
		goals = { "SOCIAL" }, times = Times(unpack(WEEKEND)), roles = 0,
		text = "Feierabendgilde der anderen Fraktion." },
}

local PLAYERS = {
	{ name = "Aldric", class = "PALADIN", level = 80, roles = T + H, lang = "de", age = 3,
		goals = { "RAID" }, times = Times({ 3, 2 }, { 4, 2 }, { 7, 2 }),
		text = "Heiler mit Raiderfahrung, suche feste Raidgilde Mi/Do." },
	{ name = "Fenja", class = "MAGE", level = 80, roles = D, lang = "de", age = 10,
		goals = { "RAID", "SOCIAL" }, times = Times(unpack(EVENINGS)),
		text = "Suche nette Gilde zum Raiden unter der Woche." },
	{ name = "Gorrim", class = "WARRIOR", level = 78, roles = T + D, lang = "de", age = 26,
		goals = { "RAID", "PVP" }, times = Times({ 2, 2 }, { 5, 2 }, { 5, 3 }),
		text = "Tank, gern auch Hardcore-Progress." },
	{ name = "Liora", class = "PRIEST", level = 64, roles = H + D, lang = "en", age = 4,
		goals = { "LEVELING", "SOCIAL" }, times = Times(unpack(WEEKEND)),
		text = "Returning player, looking for a friendly levelling guild." },
	{ name = "Maelis", class = "DRUID", level = 80, roles = T + H + D, lang = "de", age = 50,
		goals = { "RAID" }, times = Times({ 1, 2 }, { 3, 2 }, { 4, 2 }, { 7, 2 }),
		text = "Flexibler Druide, spiele jede Rolle." },
	{ name = "Torvik", class = "HUNTER", level = 80, roles = D, lang = "de", age = 8,
		goals = { "PVP" }, times = Times({ 6, 2 }, { 6, 3 }, { 7, 3 }),
		text = "PvP am Wochenende, abends." },
	{ name = "Selwyn", class = "SHAMAN", level = 72, roles = H + D, lang = "fr", age = 90,
		goals = { "RAID", "LEVELING" }, times = Times({ 2, 2 }, { 4, 2 }),
		text = "Chaman soigneur, cherche guilde francophone." },
	{ name = "Brannoc", class = "ROGUE", level = 80, roles = D, lang = "de", age = 15, other = true,
		goals = { "RAID" }, times = Times({ 3, 2 }, { 4, 2 }),
		text = "Andere Fraktion: nur sichtbar, wenn der Fraktionsfilter das erlaubt." },
}

local function Build()
	local realm = Ads.GetRealm() or "Test"
	local faction = Ads.GetFactionCode() or "A"
	local otherFaction = faction == "A" and "H" or "A"
	local mode = Ads.GetGameMode()
	local now = GetServerTime()
	local list = {}
	local function Add(raw)
		local ad = Ads.Sanitize(raw)
		if ad then
			list[#list + 1] = ad
		end
	end
	for _, g in ipairs(GUILDS) do
		local classes, classRoles = Needs(g.needs or {})
		local raw = {
			k = Ads.KIND_GUILD, i = Ads.GuildAdId(g.name, realm), v = now - g.age * HOUR,
			o = g.owner .. "-" .. realm, f = g.other and otherFaction or faction, l = g.lang, m = mode,
			g = Goals(unpack(g.goals)), t = g.times, x = g.text, n = g.name, gm = g.members, r = g.roles or 0,
			ps = g.style, rd = g.days, rn = g.perWeek, rs = g.start, re = g.stop, cl = classes, cr = classRoles,
		}
		-- Wanted roles of raid ads follow their needs, like the form does.
		if classes > 0 then
			local roles = 0
			for _, class in ipairs(C.GetClasses()) do
				local wanted = C.WantedRoles(raw, class)
				for _, role in ipairs(C.ROLES) do
					if C.HasBit(wanted, role.bit) then
						roles = C.SetBit(roles, role.bit, true)
					end
				end
			end
			raw.r = roles
		end
		Add(raw)
	end
	for _, p in ipairs(PLAYERS) do
		local owner = p.name .. "-" .. realm
		Add({
			k = Ads.KIND_PLAYER, i = Ads.PlayerAdId(owner), v = now - p.age * HOUR, o = owner,
			f = p.other and otherFaction or faction, l = p.lang, m = mode, g = Goals(unpack(p.goals)),
			t = p.times, x = p.text, c = p.class, lv = p.level, r = p.roles,
		})
	end
	return list
end

ns:RegisterCommand("testdata", function()
	if Store.HasTestAds() then
		Store.SetTestAds(nil)
		ns:Print(L.TESTDATA_REMOVED)
		return
	end
	local list = Build()
	Store.SetTestAds(list)
	ns:Print(L.TESTDATA_ADDED, #list)
end, "testdata", L.CMD_TESTDATA)
