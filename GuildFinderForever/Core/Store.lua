local _, ns = ...

-- Local ad cache (GuildFinderForeverDB.ads, keyed by id) plus local-only
-- state that is never sent: hidden ads, blocked posters, /who results.
-- Fires GFF_ADS_CHANGED(id) after every change (id nil for bulk changes).
local Store = {}
ns.Store = Store

local Ads = ns.Ads
local Serializer = ns.Serializer

Store.MAX_ADS = 3000
Store.NUM_BUCKETS = 16

ns.dbDefaults.ads = {}
-- [id] = { verified = true | suspicious = true, checked = time }
ns.dbDefaults.checks = {}
-- [id] = true
ns.dbDefaults.hidden = {}
-- [owner or "G:<guild>-<realm>"] = time blocked
ns.dbDefaults.blocked = {}

local ads, checks
-- Test ads (/gff testdata): session only, never saved, synced or served.
local testAds = {}
-- Bucket summaries, rebuilt lazily after changes.
local buckets, dirty = nil, true

ns.RegisterCallback(Store, "GFF_DB_READY", function()
	ads = ns.db.ads
	checks = ns.db.checks
	-- Drop entries a newer build would reject; saved data is not trusted
	-- more than the network.
	for id, ad in pairs(ads) do
		local clean = Ads.Sanitize(ad)
		if not clean or clean.i ~= id then
			ads[id] = nil
		else
			ads[id] = clean
		end
	end
	Store.Prune()
end)

local function Changed(id)
	dirty = true
	ns:Fire("GFF_ADS_CHANGED", id)
end

function Store.Get(id)
	return ads and ads[id] or testAds[id]
end

-- Iterates over live (not deleted, not expired) ads, test ads last.
function Store.Each(kind)
	local now = GetServerTime()
	local source, id, ad = ads, nil, nil
	return function()
		while true do
			id, ad = next(source, id)
			if id == nil and source == ads then
				source = testAds
				id, ad = next(source, nil)
			end
			if id == nil or (not ad.d and (not kind or ad.k == kind) and not Ads.IsExpired(ad, now)) then
				return id, ad
			end
		end
	end
end

-- Replaces the test ads; list = sanitized ads or nil to remove them.
function Store.SetTestAds(list)
	wipe(testAds)
	for _, ad in ipairs(list or {}) do
		if not ads[ad.i] then
			testAds[ad.i] = ad
		end
	end
	Changed(nil)
end

function Store.HasTestAds()
	return next(testAds) ~= nil
end

function Store.IsTestAd(id)
	return testAds[id] ~= nil
end

function Store.Count()
	local live, total = 0, 0
	for _, ad in pairs(ads or {}) do
		total = total + 1
		if not ad.d then
			live = live + 1
		end
	end
	return live, total
end

-- Stores ad if it is newer than the cached version. Returns true when the
-- cache changed. ad must come from Ads.Sanitize.
function Store.Put(ad)
	if not ads or Ads.IsExpired(ad) then
		return false
	end
	local current = ads[ad.i]
	if current and current.v >= ad.v then
		return false
	end
	-- A changed ad needs a new /who check.
	if current and not current.d and (ad.d or current.o ~= ad.o or current.n ~= ad.n) then
		checks[ad.i] = nil
	end
	ads[ad.i] = ad
	if not current then
		Store.EnforceLimit()
	end
	Changed(ad.i)
	return true
end

-- Removes expired ads and tombstones.
function Store.Prune()
	if not ads then
		return
	end
	local now = GetServerTime()
	local removed = false
	for id, ad in pairs(ads) do
		if Ads.IsExpired(ad, now) then
			ads[id] = nil
			checks[id] = nil
			removed = true
		end
	end
	for id in pairs(checks) do
		if not ads[id] then
			checks[id] = nil
		end
	end
	if removed then
		Changed(nil)
	end
end

-- Keeps the cache below MAX_ADS by dropping the oldest entries, tombstones
-- first. Own ads are never dropped.
function Store.EnforceLimit()
	local count = 0
	for _ in pairs(ads) do
		count = count + 1
	end
	if count <= Store.MAX_ADS then
		return
	end
	local own = { [Ads.GetOwnPlayerAdId() or ""] = true, [Ads.GetOwnGuildAdId() or ""] = true }
	local list = {}
	for id, ad in pairs(ads) do
		if not own[id] then
			list[#list + 1] = ad
		end
	end
	table.sort(list, function(a, b)
		if (a.d or false) ~= (b.d or false) then
			return a.d == true
		end
		return a.v < b.v
	end)
	for i = 1, count - Store.MAX_ADS do
		local ad = list[i]
		if ad then
			ads[ad.i] = nil
			checks[ad.i] = nil
		end
	end
	dirty = true
end

--------------------------------------------------------------------------------
-- Sync summaries
--------------------------------------------------------------------------------
-- Every id falls into one of NUM_BUCKETS buckets; a bucket's summary is the
-- order-independent sum of hash(id .. version) over its entries. Two caches
-- whose summaries match for a bucket hold the same versions there.

function Store.BucketOf(id)
	return Serializer.Hash(id) % Store.NUM_BUCKETS + 1
end

local function EntryHash(ad)
	return Serializer.Hash(ad.i .. "\0" .. ad.v)
end

function Store.GetBuckets()
	if dirty or not buckets then
		buckets = {}
		for i = 1, Store.NUM_BUCKETS do
			buckets[i] = 0
		end
		local now = GetServerTime()
		for id, ad in pairs(ads or {}) do
			if not Ads.IsExpired(ad, now) then
				local b = Store.BucketOf(id)
				buckets[b] = Serializer.Combine(buckets[b], EntryHash(ad))
			end
		end
		dirty = false
	end
	return buckets
end

-- Flat list { id1, version1, id2, version2, ... } of the entries in the
-- given buckets ({ [bucket] = true }).
function Store.GetInventory(wanted)
	local list = {}
	local now = GetServerTime()
	for id, ad in pairs(ads or {}) do
		if wanted[Store.BucketOf(id)] and not Ads.IsExpired(ad, now) then
			list[#list + 1] = id
			list[#list + 1] = ad.v
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Local state: hide, block, /who checks
--------------------------------------------------------------------------------

-- Key used for blocking: the guild for guild ads (any officer), else the
-- character.
function Store.BlockKey(ad)
	if ad.k == Ads.KIND_GUILD then
		return ad.i
	end
	return ad.o
end

function Store.IsBlocked(ad)
	local blocked = ns.db.blocked
	return blocked[Store.BlockKey(ad)] ~= nil or blocked[ad.o] ~= nil
end

function Store.Block(ad)
	ns.db.blocked[Store.BlockKey(ad)] = GetServerTime()
	Changed(ad.i)
end

function Store.Unblock(key)
	ns.db.blocked[key] = nil
	Changed(nil)
end

function Store.IsHidden(id)
	return ns.db.hidden[id] ~= nil
end

function Store.SetHidden(id, hidden)
	ns.db.hidden[id] = hidden and true or nil
	Changed(id)
end

function Store.ClearHidden()
	wipe(ns.db.hidden)
	Changed(nil)
end

function Store.GetCheck(id)
	return checks and checks[id]
end

function Store.SetCheck(id, verified)
	checks[id] = { verified = verified or nil, suspicious = not verified or nil, checked = GetServerTime() }
	Changed(id)
end

-- Hidden, blocked or found suspicious by /who: left out of search results.
function Store.IsFiltered(ad)
	if Store.IsHidden(ad.i) or Store.IsBlocked(ad) then
		return true
	end
	local check = checks[ad.i]
	return check ~= nil and check.suspicious == true
end
