-- luacheck: read globals UnitName UnitLevel UnitClass UnitFactionGroup GetGuildInfo GetNormalizedRealmName IsInGuild CanGuildInvite C_GuildInfo C_GameRules GetNumGuildMembers GetBuildInfo GetRealmName Enum
local _, ns = ...

-- Ad model: building own ads and validating received ones. Ads are flat
-- tables with short keys, the same in the saved data and on the wire:
--   i id         k kind ("P" player, "G" guild)   v version (server time)
--   o owner (Name-Realm, who posted this version)   f faction ("A"/"H")
--   l language   g goals mask   t play times mask   x text   m game mode
--   d deleted (tombstone: only i, k, v, o)
--   player: c class file, lv level, r roles mask
--   guild:  n guild name, gm member count, r wanted roles mask
-- Ids: "P:<Name-Realm>" per character, "G:<Guild>-<Realm>" per guild.
local Ads = {}
ns.Ads = Ads

local C = ns.Constants

Ads.KIND_PLAYER = "P"
Ads.KIND_GUILD = "G"

-- Accepted clock skew for versions from the future.
local MAX_FUTURE = 3600

local MAX_NAME = 64
local MAX_GUILD = 64

--------------------------------------------------------------------------------
-- Own character
--------------------------------------------------------------------------------

function Ads.GetFactionCode()
	local faction = UnitFactionGroup("player")
	if faction == "Alliance" then
		return "A"
	elseif faction == "Horde" then
		return "H"
	end
end

-- Game mode (ruleset) id as the client reports it, or nil where the API is
-- missing. Ads of other modes are filtered out by default.
function Ads.GetGameMode()
	if not (C_GameRules and C_GameRules.GetActiveGameMode) then
		return nil
	end
	local ok, mode = pcall(C_GameRules.GetActiveGameMode)
	if ok and type(mode) == "number" and not (issecretvalue and issecretvalue(mode)) then
		return mode
	end
end

-- Forever builds use interface numbers below retail's (16001 vs. 12xxxx).
function Ads.IsForever()
	local _, _, _, interface = GetBuildInfo()
	return type(interface) == "number" and interface < 100000
end

-- Enum key of the active game mode ("Standard", ...), or nil.
function Ads.GetGameModeName()
	local mode = Ads.GetGameMode()
	if not mode or not (Enum and Enum.GameMode) then
		return nil
	end
	for name, value in pairs(Enum.GameMode) do
		if value == mode then
			return name
		end
	end
	return tostring(mode)
end

-- Where ads come from: the ruleset on Forever (no realm list there), the
-- realm (plus its connected realms) on retail.
function Ads.GetScopeText()
	local L = ns.L
	if Ads.IsForever() then
		return L.STATUS_RULESET:format(Ads.GetGameModeName() or "?")
	end
	return L.STATUS_REALM:format(GetRealmName() or Ads.GetRealm() or "?")
end

function Ads.GetRealm()
	return GetNormalizedRealmName()
end

function Ads.GetGuild()
	if not IsInGuild() then
		return nil
	end
	local name = GetGuildInfo("player")
	if type(name) == "string" and name ~= "" then
		return name
	end
end

function Ads.CanInvite()
	local check = C_GuildInfo and C_GuildInfo.CanGuildInvite or CanGuildInvite
	return check ~= nil and check() and true or false
end

function Ads.PlayerAdId(owner)
	return "P:" .. owner
end

function Ads.GuildAdId(guild, realm)
	return "G:" .. guild .. "-" .. realm
end

function Ads.GetOwnPlayerAdId()
	local me = ns:GetPlayerFullName()
	return me and Ads.PlayerAdId(me)
end

function Ads.GetOwnGuildAdId()
	local guild, realm = Ads.GetGuild(), Ads.GetRealm()
	return guild and realm and Ads.GuildAdId(guild, realm)
end

-- Realm part of "Name-Realm".
function Ads.OwnerRealm(owner)
	return owner and owner:match("^[^%-]+%-(.+)$")
end

function Ads.OwnerName(owner)
	return owner and owner:match("^([^%-]+)") or owner
end

--------------------------------------------------------------------------------
-- Building own ads
--------------------------------------------------------------------------------

local function Common(ad, form)
	ad.v = GetServerTime()
	ad.o = ns:GetPlayerFullName()
	ad.f = Ads.GetFactionCode()
	ad.l = form.lang
	ad.g = form.goals
	ad.t = form.times
	ad.x = form.text
	ad.m = Ads.GetGameMode()
	return ad
end

-- form: { roles, goals, times, lang, text } (the character's draft).
function Ads.BuildPlayerAd(form)
	local _, classFile = UnitClass("player")
	local ad = Common({
		k = Ads.KIND_PLAYER,
		c = classFile,
		lv = UnitLevel("player"),
		r = form.roles,
	}, form)
	ad.i = Ads.PlayerAdId(ad.o)
	return Ads.Sanitize(ad)
end

function Ads.BuildGuildAd(form)
	local guild, realm = Ads.GetGuild(), Ads.GetRealm()
	if not (guild and realm and Ads.CanInvite()) then
		return nil
	end
	local members = GetNumGuildMembers()
	local ad = Common({
		k = Ads.KIND_GUILD,
		n = guild,
		gm = type(members) == "number" and members > 0 and members or nil,
		r = form.roles,
	}, form)
	if C.HasBit(ad.g or 0, C.GOAL_RAID) then
		ad.ps, ad.cl, ad.rd, ad.rn = form.style, form.classes, form.raidDays, form.raidsPerWeek
		ad.rs, ad.re = form.raidStart, form.raidEnd
	end
	ad.i = Ads.GuildAdId(guild, realm)
	return Ads.Sanitize(ad)
end

function Ads.BuildTombstone(ad)
	return {
		i = ad.i,
		k = ad.k,
		v = math.max(GetServerTime(), (ad.v or 0) + 1),
		o = ns:GetPlayerFullName() or ad.o,
		d = true,
	}
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function Str(value, maxLen)
	if type(value) ~= "string" or IsSecret(value) or #value == 0 or #value > maxLen then
		return nil
	end
	return value
end

local function Int(value, min, max)
	if type(value) ~= "number" or IsSecret(value) or value ~= math.floor(value) or value < min or value > max then
		return nil
	end
	return value
end

-- Free text: drop "|" (UI escape sequences: colors, links, textures) and
-- control characters, collapse whitespace, cut at C.MAX_TEXT characters
-- without splitting a UTF-8 sequence.
function Ads.CleanText(text)
	if type(text) ~= "string" or IsSecret(text) then
		return ""
	end
	text = text:gsub("|", ""):gsub("[%c]", " "):gsub("%s+", " ")
	text = strtrim(text)
	local chars, cut = 0, #text
	for pos in text:gmatch("()[^\128-\191]") do
		chars = chars + 1
		if chars > C.MAX_TEXT then
			cut = pos - 1
			break
		end
	end
	return text:sub(1, cut)
end

-- Names may not contain "|" or control characters either.
local function CleanName(value, maxLen)
	value = Str(value, maxLen)
	if not value or value:find("[|%c]") then
		return nil
	end
	return value
end

-- Returns a validated copy holding only known fields, or nil. Never trusts
-- the input table itself.
function Ads.Sanitize(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local now = GetServerTime()
	local ad = {}
	ad.k = (raw.k == Ads.KIND_PLAYER or raw.k == Ads.KIND_GUILD) and raw.k or nil
	ad.i = CleanName(raw.i, MAX_NAME + MAX_GUILD + 4)
	ad.v = Int(raw.v, now - C.AD_LIFETIME, now + MAX_FUTURE)
	ad.o = CleanName(raw.o, MAX_NAME)
	if not (ad.k and ad.i and ad.v and ad.o) or not Ads.OwnerRealm(ad.o) then
		return nil
	end
	if raw.d == true then
		ad.d = true
		return ad
	end

	ad.f = (raw.f == "A" or raw.f == "H") and raw.f or nil
	-- Any two-letter key, so ads in languages added later still pass.
	ad.l = type(raw.l) == "string" and raw.l:match("^%l%l$") or nil
	ad.g = Int(raw.g, 0, C.ALL_GOALS) or 0
	ad.t = Int(raw.t, 0, C.ALL_TIMES) or 0
	ad.x = Ads.CleanText(raw.x)
	ad.m = Int(raw.m, 0, 1000000)
	ad.r = Int(raw.r, 0, 7) or 0
	if not (ad.f and ad.l) then
		return nil
	end

	if ad.k == Ads.KIND_PLAYER then
		ad.c = CleanName(raw.c, 32)
		ad.lv = Int(raw.lv, 1, 200)
		if not (ad.c and ad.lv) or ad.i ~= Ads.PlayerAdId(ad.o) then
			return nil
		end
	else
		ad.n = CleanName(raw.n, MAX_GUILD)
		ad.gm = Int(raw.gm, 1, 10000)
		if C.HasBit(ad.g, C.GOAL_RAID) then
			ad.ps = Int(raw.ps, 1, #C.STYLES)
			ad.cl = Int(raw.cl, 0, C.ALL_CLASSES)
			ad.rd = Int(raw.rd, 0, C.ALL_DAYS)
			ad.rn = Int(raw.rn, 1, 7)
			ad.rs = Int(raw.rs, 0, 24 * 60 - 1)
			ad.re = ad.rs and Int(raw.re, 0, 24 * 60 - 1)
		end
		if not ad.n or ad.i ~= Ads.GuildAdId(ad.n, Ads.OwnerRealm(ad.o)) then
			return nil
		end
	end
	return ad
end

function Ads.IsExpired(ad, now)
	return (ad.v or 0) + C.AD_LIFETIME < (now or GetServerTime())
end

function Ads.ExpiresIn(ad)
	return (ad.v or 0) + C.AD_LIFETIME - GetServerTime()
end
