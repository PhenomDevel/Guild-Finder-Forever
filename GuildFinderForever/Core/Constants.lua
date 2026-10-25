-- luacheck: read globals GetNumClasses GetClassInfo LOCALIZED_CLASS_NAMES_MALE
local _, ns = ...

local L = ns.L

-- Shared enumerations of the ad model. Bit values are part of the protocol and
-- the saved data: never renumber them.
local C = {}
ns.Constants = C

C.AD_LIFETIME = 14 * 24 * 3600
C.MAX_TEXT = 200

C.FACTIONS = { "Alliance", "Horde" }

C.ROLE = { TANK = 1, HEALER = 2, DAMAGE = 4 }
C.ROLES = {
	{ bit = C.ROLE.TANK, key = "TANK", label = L.ROLE_TANK, short = L.ROLE_TANK_SHORT, color = { 0.18, 0.35, 0.66 } },
	{ bit = C.ROLE.HEALER, key = "HEALER", label = L.ROLE_HEALER, short = L.ROLE_HEALER_SHORT, color = { 0.18, 0.48, 0.2 } },
	{ bit = C.ROLE.DAMAGE, key = "DAMAGE", label = L.ROLE_DAMAGE, short = L.ROLE_DAMAGE_SHORT, color = { 0.56, 0.16, 0.12 } },
}
C.ALL_ROLES = 7

-- Each goal has an icon and colour so chips are told apart at a glance.
C.GOALS = {
	{ bit = 1, key = "RAID", label = L.GOAL_RAID, icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", color = { 0.85, 0.45, 0.12 } },
	{ bit = 2, key = "PVP", label = L.GOAL_PVP, icon = "Interface\\Icons\\Ability_DualWield", color = { 0.8, 0.2, 0.2 } },
	{ bit = 4, key = "LEVELING", label = L.GOAL_LEVELING, icon = "Interface\\Icons\\INV_Misc_Map_01", color = { 0.3, 0.68, 0.3 } },
	{ bit = 8, key = "SOCIAL", label = L.GOAL_SOCIAL, icon = "Interface\\Icons\\INV_Drink_05", color = { 0.4, 0.55, 0.95 } },
}
C.ALL_GOALS = 15

-- Play times: 7 days × 3 slots, bit (day - 1) * 3 + (slot - 1). Day 1 is Monday.
C.DAYS = { L.DAY_MON, L.DAY_TUE, L.DAY_WED, L.DAY_THU, L.DAY_FRI, L.DAY_SAT, L.DAY_SUN }
C.SLOTS = { L.SLOT_AFTERNOON, L.SLOT_EVENING, L.SLOT_NIGHT }
C.ALL_TIMES = 2 ^ 21 - 1

-- Raid details of a guild ad, only with the raid goal set:
--   ps = style, cl = wanted classes, cr = their roles, rd = raid days (bit day - 1),
--   rn = raids per week, rs/re = start/end in minutes after midnight
--   (realm time; end < start runs past midnight). Missing = not stated.
C.GOAL_RAID = 1
C.ALL_DAYS = 2 ^ 7 - 1
C.TIME_STEP = 30
function C.DayBit(day)
	return 2 ^ (day - 1)
end
function C.FormatTime(minutes)
	return ("%02d:%02d"):format(math.floor(minutes / 60), minutes % 60)
end

-- Raid play style (ps).
C.STYLES = {
	{ value = 1, key = "CASUAL", label = L.STYLE_CASUAL },
	{ value = 2, key = "SEMI", label = L.STYLE_SEMI },
	{ value = 3, key = "HARDCORE", label = L.STYLE_HARDCORE },
}
function C.StyleName(value)
	for _, style in ipairs(C.STYLES) do
		if style.value == value then
			return style.label
		end
	end
end

-- Wanted classes (cl): bit (classID - 1); 0 = any class. Room for 20 IDs.
-- Wanted roles per class (cr): one digit per class ID, the role mask
-- (0–7, 0 = any role), e.g. "1004" = class 1 as tank, class 4 as damage.
C.MAX_CLASS_ID = 20
C.ALL_CLASSES = 2 ^ C.MAX_CLASS_ID - 1
function C.ClassBit(classID)
	return 2 ^ (classID - 1)
end

function C.GetClassRoles(classRoles, classID)
	return tonumber((classRoles or ""):sub(classID, classID)) or 0
end

-- Returns the new cr string, nil when no class has roles set.
function C.SetClassRoles(classRoles, classID, mask)
	local digits = classRoles or ""
	digits = digits .. ("0"):rep(math.max(0, classID - #digits))
	digits = digits:sub(1, classID - 1) .. mask .. digits:sub(classID + 1)
	digits = digits:gsub("0+$", "")
	return digits ~= "" and digits or nil
end

-- Whether a guild ad wants this class (and, when both sides name roles,
-- one of these roles).
function C.WantsClass(ad, classID, roles)
	local classes = ad.cl or 0
	if classes == 0 then
		return true
	end
	if not C.HasBit(classes, C.ClassBit(classID)) then
		return false
	end
	local wanted = C.GetClassRoles(ad.cr, classID)
	return wanted == 0 or (roles or 0) == 0 or C.CommonBits(wanted, roles) > 0
end

-- Roles a guild ad wants this class in: the stated ones, or all the class
-- can play when none are stated; 0 when the class is not wanted.
function C.WantedRoles(ad, class)
	if not C.HasBit(ad.cl or 0, C.ClassBit(class.id)) then
		return 0
	end
	local roles = C.GetClassRoles(ad.cr, class.id)
	return roles > 0 and roles or C.ClassRoles(class.key)
end

-- { [roleBit] = { class, ... } } of a guild ad's wanted classes.
function C.NeedsByRole(ad)
	local needs = {}
	for _, role in ipairs(C.ROLES) do
		needs[role.bit] = {}
	end
	for _, class in ipairs(C.GetClasses()) do
		local roles = C.WantedRoles(ad, class)
		for _, role in ipairs(C.ROLES) do
			if C.HasBit(roles, role.bit) then
				local list = needs[role.bit]
				list[#list + 1] = class
			end
		end
	end
	return needs
end

-- "Mi · Do · So" for a raid days mask.
function C.DaysText(days)
	local parts = {}
	for day, name in ipairs(C.DAYS) do
		if C.HasBit(days or 0, C.DayBit(day)) then
			parts[#parts + 1] = name
		end
	end
	return table.concat(parts, " · ")
end

-- "19:30–23:00", "19:30" or nil.
function C.RaidTimeText(ad)
	if not ad.rs then
		return nil
	end
	return C.FormatTime(ad.rs) .. (ad.re and ("–" .. C.FormatTime(ad.re)) or "")
end

function C.TimeBit(day, slot)
	return 2 ^ ((day - 1) * 3 + (slot - 1))
end

-- Further languages of an ad (la): two-letter keys after the main
-- one (l), concatenated, e.g. "enfr".
C.MAX_MORE_LANGS = 6

-- { "de", "en", ... } of an ad, main language first.
function C.AdLanguages(ad)
	local list = { ad.l }
	for key in (ad.la or ""):gmatch("%l%l") do
		list[#list + 1] = key
	end
	return list
end

function C.SpeaksLanguage(ad, key)
	if ad.l == key then
		return true
	end
	for other in (ad.la or ""):gmatch("%l%l") do
		if other == key then
			return true
		end
	end
	return false
end

C.LANGUAGES = {
	{ key = "de", label = L.LANG_DE },
	{ key = "en", label = L.LANG_EN },
	{ key = "fr", label = L.LANG_FR },
	{ key = "es", label = L.LANG_ES },
	{ key = "it", label = L.LANG_IT },
	{ key = "pt", label = L.LANG_PT },
	{ key = "ru", label = L.LANG_RU },
}
-- Further EU languages without a client locale, after the ones above,
-- sorted by their localized name.
local MORE_LANGUAGES = {
	{ key = "nl", label = L.LANG_NL },
	{ key = "pl", label = L.LANG_PL },
	{ key = "sv", label = L.LANG_SV },
	{ key = "da", label = L.LANG_DA },
	{ key = "no", label = L.LANG_NO },
	{ key = "fi", label = L.LANG_FI },
	{ key = "cs", label = L.LANG_CS },
	{ key = "hu", label = L.LANG_HU },
	{ key = "ro", label = L.LANG_RO },
	{ key = "el", label = L.LANG_EL },
	{ key = "tr", label = L.LANG_TR },
	{ key = "uk", label = L.LANG_UK },
}
table.sort(MORE_LANGUAGES, function(a, b)
	return a.label < b.label
end)
for _, lang in ipairs(MORE_LANGUAGES) do
	C.LANGUAGES[#C.LANGUAGES + 1] = lang
end
C.LANGUAGE_BY_KEY = {}
for _, lang in ipairs(C.LANGUAGES) do
	C.LANGUAGE_BY_KEY[lang.key] = lang
end

-- Client locale → ad language preselected in a new ad.
local LOCALE_LANGUAGE = {
	deDE = "de", enUS = "en", enGB = "en", frFR = "fr", esES = "es", esMX = "es",
	itIT = "it", ptBR = "pt", ruRU = "ru",
}
function C.DefaultLanguage()
	return LOCALE_LANGUAGE[GetLocale()] or "en"
end

-- Roles each class can fill; classes missing here may pick any role.
local CLASS_ROLES = {
	WARRIOR = 5, PALADIN = 7, HUNTER = 4, ROGUE = 4, PRIEST = 6, SHAMAN = 6,
	MAGE = 4, WARLOCK = 4, DRUID = 7, DEATHKNIGHT = 5, MONK = 7,
	DEMONHUNTER = 5, EVOKER = 6,
}
function C.ClassRoles(classFile)
	return CLASS_ROLES[classFile] or 7
end

-- Classes available in this client, from the game data.
local classes
function C.GetClasses()
	if classes then
		return classes
	end
	classes = {}
	local count = GetNumClasses and GetNumClasses() or 0
	for classID = 1, count do
		local name, classFile = GetClassInfo(classID)
		if name and classFile then
			classes[#classes + 1] = { key = classFile, label = name, id = classID }
		end
	end
	table.sort(classes, function(a, b)
		return a.label < b.label
	end)
	return classes
end

-- Class ID for a class file ("MAGE" → 8), from the game data.
function C.ClassId(classFile)
	for _, class in ipairs(C.GetClasses()) do
		if class.key == classFile then
			return class.id
		end
	end
end

function C.ClassName(classFile)
	local names = LOCALIZED_CLASS_NAMES_MALE
	return names and names[classFile] or classFile or "?"
end

-- Bit helpers without the bit library: values stay below 2^21.
function C.HasBit(value, flag)
	return value % (flag + flag) >= flag
end

function C.SetBit(value, flag, on)
	local has = C.HasBit(value, flag)
	if on and not has then
		return value + flag
	elseif not on and has then
		return value - flag
	end
	return value
end

function C.CountBits(value)
	local count = 0
	while value > 0 do
		count = count + value % 2
		value = math.floor(value / 2)
	end
	return count
end

function C.CommonBits(a, b)
	local count, flag = 0, 1
	while flag <= a and flag <= b do
		if C.HasBit(a, flag) and C.HasBit(b, flag) then
			count = count + 1
		end
		flag = flag * 2
	end
	return count
end

-- "Tank, Damage" for a roles mask.
function C.RoleNames(roles)
	local parts = {}
	for _, role in ipairs(C.ROLES) do
		if C.HasBit(roles or 0, role.bit) then
			parts[#parts + 1] = role.label
		end
	end
	return table.concat(parts, ", ")
end

-- "Raid, Social" for a goals mask.
function C.GoalsText(goals)
	local parts = {}
	for _, goal in ipairs(C.GOALS) do
		if C.HasBit(goals or 0, goal.bit) then
			parts[#parts + 1] = goal.label
		end
	end
	return table.concat(parts, ", ")
end

-- Short play time summary for the result list, e.g. "Wed, Sun evening".
function C.TimesText(times)
	times = times or 0
	if times == 0 then
		return "–"
	end
	local parts = {}
	for slot = 1, #C.SLOTS do
		local days = {}
		for day = 1, #C.DAYS do
			if C.HasBit(times, C.TimeBit(day, slot)) then
				days[#days + 1] = day
			end
		end
		if #days > 0 then
			local dayText
			if #days == 7 then
				dayText = L.DAILY
			elseif #days == 2 and days[1] == 6 and days[2] == 7 then
				dayText = L.WEEKEND
			else
				local names = {}
				for i, day in ipairs(days) do
					names[i] = C.DAYS[day]
				end
				dayText = table.concat(names, ", ")
			end
			parts[#parts + 1] = dayText .. " " .. C.SLOTS[slot]
		end
	end
	return table.concat(parts, "; ")
end
