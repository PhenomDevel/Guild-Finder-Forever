local _, ns = ...

-- Filtering and match score for the search tabs.
--   filter = { kind, text, factions = { A = bool, H = bool }, lang, goals,
--              roles, class, minLevel, maxLevel, myTimes, sameMode,
--              style, myClass }
--   profile = { goals, times, roles, lang, classes, classId }: what the
--              searcher wants (own draft), the base of the match score.
-- sameMode only applies on Forever: retail has no rulesets to compare.
local Search = {}
ns.Search = Search

local Ads = ns.Ads
local Store = ns.Store
local C = ns.Constants

local function Lower(text)
	return text and text:lower() or ""
end

local function Matches(ad, filter, profile, myMode)
	if filter.factions and not filter.factions[ad.f] then
		return false
	end
	if filter.lang and ad.l ~= filter.lang then
		return false
	end
	if filter.goals and filter.goals > 0 and C.CommonBits(filter.goals, ad.g) == 0 then
		return false
	end
	if filter.roles and filter.roles > 0 and C.CommonBits(filter.roles, ad.r) == 0 then
		return false
	end
	if filter.myTimes and profile.times > 0 and C.CommonBits(profile.times, ad.t) == 0 then
		return false
	end
	if filter.sameMode and myMode and ad.m and ad.m ~= myMode then
		return false
	end
	if ad.k == Ads.KIND_GUILD then
		if filter.style and ad.ps ~= filter.style then
			return false
		end
		if filter.myClass and profile.classId and (ad.cl or 0) > 0
			and not C.HasBit(ad.cl, C.ClassBit(profile.classId)) then
			return false
		end
	elseif ad.k == Ads.KIND_PLAYER then
		if filter.class and ad.c ~= filter.class then
			return false
		end
		if filter.minLevel and ad.lv < filter.minLevel then
			return false
		end
		if filter.maxLevel and ad.lv > filter.maxLevel then
			return false
		end
	end
	if filter.text and filter.text ~= "" then
		local needle = Lower(filter.text)
		local haystack = Lower(ad.n) .. "\n" .. Lower(Ads.OwnerName(ad.o)) .. "\n" .. Lower(ad.x)
		if not haystack:find(needle, 1, true) then
			return false
		end
	end
	return true
end

-- Own ruleset for the sameMode filter; nil (no filtering) outside Forever.
function Search.MyMode()
	return Ads.IsForever() and Ads.GetGameMode() or nil
end

-- 0–100, or nil when there is nothing to compare.
function Search.Score(ad, filter, profile)
	local total, weight = 0, 0
	local function Add(value, w)
		total = total + value * w
		weight = weight + w
	end

	local goals = (filter.goals and filter.goals > 0) and filter.goals or profile.goals or 0
	if goals > 0 then
		Add(C.CommonBits(goals, ad.g) / C.CountBits(goals), 3)
	end
	local times = profile.times or 0
	if times > 0 then
		local common = C.CommonBits(times, ad.t)
		Add(math.min(1, common / math.min(C.CountBits(times), math.max(C.CountBits(ad.t), 1))), 3)
	end
	local roles = (filter.roles and filter.roles > 0) and filter.roles or profile.roles or 0
	if roles > 0 and ad.r and ad.r > 0 then
		Add(C.CommonBits(roles, ad.r) > 0 and 1 or 0, 2)
	end
	-- Raid days of a guild ad: share the player has any play time on.
	if ad.k == Ads.KIND_GUILD and (ad.rd or 0) > 0 and times > 0 then
		local days, free = 0, 0
		for day = 1, #C.DAYS do
			if C.HasBit(ad.rd, C.DayBit(day)) then
				days = days + 1
				for slot = 1, #C.SLOTS do
					if C.HasBit(times, C.TimeBit(day, slot)) then
						free = free + 1
						break
					end
				end
			end
		end
		Add(free / days, 2)
	end
	-- Wanted classes: guild ad vs. own class, own guild draft vs. player ad.
	if ad.k == Ads.KIND_GUILD and (ad.cl or 0) > 0 and profile.classId then
		Add(C.HasBit(ad.cl, C.ClassBit(profile.classId)) and 1 or 0, 2)
	elseif ad.k == Ads.KIND_PLAYER and (profile.classes or 0) > 0 then
		local classId = C.ClassId(ad.c)
		if classId then
			Add(C.HasBit(profile.classes, C.ClassBit(classId)) and 1 or 0, 2)
		end
	end
	local lang = filter.lang or profile.lang
	if lang then
		Add(ad.l == lang and 1 or 0, 1)
	end
	if weight == 0 then
		return nil
	end
	return math.floor(total / weight * 100 + 0.5)
end

-- Whether a single ad passes the filter (search rules, hidden/blocked).
function Search.Accepts(ad, filter, profile)
	if ad.d or ad.k ~= filter.kind or Store.IsFiltered(ad) or Ads.IsExpired(ad) then
		return false
	end
	return Matches(ad, filter, profile, Search.MyMode())
end

-- Returns the matching ads, best score first, each as
-- { ad = ad, score = n|nil }.
function Search.Run(filter, profile)
	local results = {}
	local myMode = Search.MyMode()
	local own = { [Ads.GetOwnPlayerAdId() or ""] = true, [Ads.GetOwnGuildAdId() or ""] = true }
	for id, ad in Store.Each(filter.kind) do
		if not own[id] and not Store.IsFiltered(ad) and Matches(ad, filter, profile, myMode) then
			results[#results + 1] = { ad = ad, score = Search.Score(ad, filter, profile) }
		end
	end
	table.sort(results, function(a, b)
		local sa, sb = a.score or -1, b.score or -1
		if sa ~= sb then
			return sa > sb
		end
		return a.ad.v > b.ad.v
	end)
	return results
end
