-- luacheck: read globals UnitName
local _, ns = ...

-- Ad exchange between clients over ns.Comm. Messages are serialized tables
-- with the type in field y:
--   H hello      { n = nonce, b = bucket summaries }
--                sent after joining the channel and every HELLO_INTERVAL.
--   I inventory  { n = nonce, to = hello sender, b = own summaries,
--                  k = { covered buckets }, e = { id, version, ... } }
--                answer to a hello whose summaries differ; sent after a
--                random delay, cancelled if an equal cache answered first.
--   R request    { to = inventory sender, ids = { ... } }
--   A ads        { a = { ad, ... } }   requested ads, own new ads, pushes.
-- Everything is broadcast on the channel, so every listener can pick up
-- ads it was missing from any A message.
local Sync = {}
ns.Sync = Sync

local Comm = ns.Comm
local Store = ns.Store
local Serializer = ns.Serializer
local Ads = ns.Ads
local L = ns.L

local HELLO_DELAY_MIN, HELLO_DELAY_MAX = 3, 8
local HELLO_INTERVAL = 15 * 60
local ANSWER_DELAY_MIN, ANSWER_DELAY_MAX = 1.5, 6
-- Answers per hello after which nobody else answers.
local MAX_ANSWERS = 2
local MAX_INVENTORY = 400
local MAX_REQUEST = 100
local ADS_PER_MESSAGE = 15
-- Ads served to one requester per SERVE_WINDOW.
local MAX_SERVED = 400
local SERVE_WINDOW = 600
-- Per-sender token bucket for incoming messages.
local RATE_CAPACITY = 40
local RATE_REFILL = 0.5 -- tokens per second

Sync.lastSync = nil
Sync.stats = { received = 0, sent = 0, dropped = 0 }

-- Chat trace of the sync traffic, switched with /gff debug.
local function Debugging()
	return ns.db and ns.db.settings and ns.db.settings.debug
end

local function Debug(text, ...)
	if Debugging() then
		ns:Print("|cff9d9d9d[debug]|r " .. text, ...)
	end
end
Sync.Debug = Debug

local function FactionName(code)
	return code == "H" and L.FACTION_HORDE or code == "A" and L.FACTION_ALLIANCE or "?"
end

local function AdLabel(ad)
	local name = ad.k == Ads.KIND_GUILD and ("<" .. tostring(ad.n) .. ">") or Ads.OwnerName(ad.o)
	if ad.d then
		return L.DEBUG_AD_WITHDRAWN:format(name)
	end
	return ("%s (%s)"):format(name, FactionName(ad.f))
end

-- Whether a received ad shows up in the own search, and why not.
local function Visibility(ad)
	local Filters, Search = ns.Filters, ns.Search
	if ad.d or not (Filters and Search) then
		return ""
	end
	if ad.i == Ads.GetOwnPlayerAdId() or ad.i == Ads.GetOwnGuildAdId() then
		return L.DEBUG_OWN
	end
	local filter = Filters.Get(ad.k)
	if Search.Accepts(ad, filter, Filters.Profile(ad.k)) then
		return L.DEBUG_VISIBLE
	end
	if filter.factions and not filter.factions[ad.f] then
		return L.DEBUG_HIDDEN_FACTION
	end
	return L.DEBUG_HIDDEN_FILTER
end

local function IsMe(name)
	return type(name) == "string" and (name == ns:GetPlayerFullName() or name == UnitName("player"))
end

local function Send(message, prio)
	Sync.stats.sent = Sync.stats.sent + 1
	Comm.Send(Serializer.Serialize(message), prio)
end

-- Ads are sent in chunks; prio "NORMAL" for own changes, "BULK" for sync.
local function SendAds(list, prio)
	for first = 1, #list, ADS_PER_MESSAGE do
		local chunk = {}
		for i = first, math.min(first + ADS_PER_MESSAGE - 1, #list) do
			chunk[#chunk + 1] = list[i]
		end
		if Debugging() then
			local names = {}
			for _, ad in ipairs(chunk) do
				names[#names + 1] = AdLabel(ad)
			end
			Debug(L.DEBUG_SEND_ADS, #chunk, table.concat(names, ", "))
		end
		Send({ y = "A", a = chunk }, prio or "BULK")
	end
end

--------------------------------------------------------------------------------
-- Rate limiting
--------------------------------------------------------------------------------

local rates = {}

local function Allow(sender)
	local now = GetTime()
	local rate = rates[sender]
	if not rate then
		rate = { tokens = RATE_CAPACITY, time = now }
		rates[sender] = rate
	end
	rate.tokens = math.min(RATE_CAPACITY, rate.tokens + (now - rate.time) * RATE_REFILL)
	rate.time = now
	if rate.tokens < 1 then
		return false
	end
	rate.tokens = rate.tokens - 1
	return true
end

local served = {}

local function ServeBudget(requester, count)
	local now = GetTime()
	local entry = served[requester]
	if not entry or now - entry.time > SERVE_WINDOW then
		entry = { time = now, count = 0 }
		served[requester] = entry
	end
	local allowed = math.max(0, math.min(count, MAX_SERVED - entry.count))
	entry.count = entry.count + allowed
	return allowed
end

--------------------------------------------------------------------------------
-- Hello / inventory
--------------------------------------------------------------------------------

local function NewNonce()
	return ("%x%04x"):format(GetServerTime() % 0x10000000, math.random(0, 0xffff))
end

function Sync.SendHello()
	Debug(L.DEBUG_SEND_HELLO, (Store.Count()))
	Send({ y = "H", n = NewNonce(), b = Store.GetBuckets() })
end

local function ValidBuckets(b)
	if type(b) ~= "table" then
		return nil
	end
	for i = 1, Store.NUM_BUCKETS do
		if type(b[i]) ~= "number" then
			return nil
		end
	end
	return b
end

local function SameBuckets(a, b)
	for i = 1, Store.NUM_BUCKETS do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- [nonce] = { timer, answers }
local pending = {}

local function SendInventory(nonce, target, theirs)
	local ours = Store.GetBuckets()
	-- Buckets the other side has nothing in get the ads right away; the rest
	-- as (id, version) lists, grouped so one message stays small.
	local direct, groups, group, groupSize = {}, {}, nil, 0
	for i = 1, Store.NUM_BUCKETS do
		if ours[i] ~= theirs[i] then
			if theirs[i] == 0 then
				direct[i] = true
			else
				local entries = Store.GetInventory({ [i] = true })
				if not group or groupSize + #entries / 2 > MAX_INVENTORY then
					group = { k = {}, e = {} }
					groups[#groups + 1] = group
					groupSize = 0
				end
				group.k[#group.k + 1] = i
				for j = 1, #entries do
					group.e[#group.e + 1] = entries[j]
				end
				groupSize = groupSize + #entries / 2
			end
		end
	end
	if next(direct) then
		local list = {}
		for id, ad in pairs(ns.db.ads) do
			if direct[Store.BucketOf(id)] and not Ads.IsExpired(ad) then
				list[#list + 1] = ad
			end
		end
		local allowed = ServeBudget(target, #list)
		for i = #list, allowed + 1, -1 do
			list[i] = nil
		end
		SendAds(list, "BULK")
	end
	for _, g in ipairs(groups) do
		Debug(L.DEBUG_SEND_INVENTORY, target, math.floor(#g.e / 2))
		Send({ y = "I", n = nonce, to = target, b = ours, k = g.k, e = g.e }, "BULK")
	end
end

local function OnHello(message, sender)
	local theirs = ValidBuckets(message.b)
	local nonce = type(message.n) == "string" and #message.n <= 16 and message.n
	if not theirs or not nonce then
		return
	end
	if SameBuckets(theirs, Store.GetBuckets()) then
		Debug(L.DEBUG_RECV_HELLO_SAME, sender)
		return
	end
	Debug(L.DEBUG_RECV_HELLO, sender)
	if pending[nonce] then
		return
	end
	local entry = { answers = 0 }
	pending[nonce] = entry
	local delay = ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN)
	entry.timer = C_Timer.NewTimer(delay, function()
		entry.timer = nil
		SendInventory(nonce, sender, theirs)
	end)
	-- Forget the nonce after a while.
	C_Timer.After(120, function()
		if pending[nonce] == entry then
			pending[nonce] = nil
		end
	end)
end

local function OnInventory(message, sender)
	local nonce = message.n
	local theirs = ValidBuckets(message.b)
	if type(nonce) ~= "string" or not theirs then
		return
	end
	-- Someone else answered a hello we were about to answer.
	local entry = pending[nonce]
	if entry and entry.timer and not IsMe(message.to) then
		entry.answers = entry.answers + 1
		if entry.answers >= MAX_ANSWERS or SameBuckets(theirs, Store.GetBuckets()) then
			entry.timer:Cancel()
			entry.timer = nil
		end
	end
	if not IsMe(message.to) or type(message.e) ~= "table" or type(message.k) ~= "table" then
		return
	end
	Debug(L.DEBUG_RECV_INVENTORY, sender, math.floor(#message.e / 2))

	-- What they have that we lack or hold in an older version.
	local listed = {}
	local missing = {}
	local e = message.e
	for i = 1, math.min(#e, MAX_INVENTORY * 2), 2 do
		local id, version = e[i], e[i + 1]
		if type(id) == "string" and type(version) == "number" and #id <= 140 then
			listed[id] = version
			local ad = Store.Get(id)
			if (not ad or ad.v < version) and #missing < MAX_REQUEST * 4 then
				missing[#missing + 1] = id
			end
		end
	end
	for first = 1, #missing, MAX_REQUEST do
		local ids = {}
		for i = first, math.min(first + MAX_REQUEST - 1, #missing) do
			ids[#ids + 1] = missing[i]
		end
		Debug(L.DEBUG_SEND_REQUEST, sender, #ids)
		Send({ y = "R", to = sender, ids = ids }, "BULK")
	end

	-- What we have that they lack or hold in an older version, in the
	-- buckets this message covers completely.
	local covered = {}
	for _, bucket in ipairs(message.k) do
		if type(bucket) == "number" then
			covered[bucket] = true
		end
	end
	local push = {}
	for id, ad in pairs(ns.db.ads) do
		if covered[Store.BucketOf(id)] and not Ads.IsExpired(ad) then
			local version = listed[id]
			if not version or version < ad.v then
				push[#push + 1] = ad
			end
		end
	end
	SendAds(push, "BULK")
	Sync.lastSync = GetServerTime()
end

local function OnRequest(message, sender)
	if not IsMe(message.to) or type(message.ids) ~= "table" then
		return
	end
	local list = {}
	for i = 1, math.min(#message.ids, MAX_REQUEST) do
		local ad = Store.Get(message.ids[i])
		if ad and not Ads.IsExpired(ad) then
			list[#list + 1] = ad
		end
	end
	Debug(L.DEBUG_RECV_REQUEST, sender, #message.ids)
	local allowed = ServeBudget(sender, #list)
	for i = #list, allowed + 1, -1 do
		list[i] = nil
	end
	SendAds(list, "BULK")
end

local function OnAds(message, sender)
	if type(message.a) ~= "table" then
		return
	end
	local changed = false
	local count = math.min(#message.a, ADS_PER_MESSAGE)
	-- Debug: one line per ad the sender posted itself, totals for the rest.
	local totals = { new = 0, updated = 0, known = 0, invalid = 0 }
	local details = {}
	for i = 1, count do
		local ad = Ads.Sanitize(message.a[i])
		if not ad then
			totals.invalid = totals.invalid + 1
		else
			-- A newer copy of an own ad comes from another install (saved
			-- data is per machine); it is taken over and shows in "My ad".
			local previous = Store.Get(ad.i)
			local stored = Store.Put(ad)
			if Debugging() then
				local state = not stored and "known" or previous and "updated" or "new"
				totals[state] = totals[state] + 1
				if ad.o == sender then
					local visible = stored and Visibility(ad) or ""
					details[#details + 1] = ("  %s: %s%s"):format(AdLabel(ad), L["DEBUG_AD_" .. state:upper()],
						visible ~= "" and (" · " .. visible) or "")
				end
			end
			if stored then
				changed = true
				if ad.o == sender and not ad.d then
					-- First-hand: the sender posted this version. isNew: not
					-- known before (no renewal or edit).
					ns:Fire("GFF_AD_RECEIVED", ad, previous == nil or previous.d == true)
				end
			end
		end
	end
	Debug(L.DEBUG_RECV_ADS, count, sender, totals.new, totals.updated, totals.known, totals.invalid)
	for _, line in ipairs(details) do
		Debug(line)
	end
	if changed then
		Sync.lastSync = GetServerTime()
	end
end

local HANDLERS = { H = OnHello, I = OnInventory, R = OnRequest, A = OnAds }

Comm.RegisterHandler(function(text, sender)
	if not ns.db then
		return
	end
	if not Allow(sender) then
		Sync.stats.dropped = Sync.stats.dropped + 1
		Debug(L.DEBUG_DROP_RATE, sender)
		return
	end
	local message = Serializer.Deserialize(text)
	local handler = type(message) == "table" and HANDLERS[message.y]
	if not handler then
		Sync.stats.dropped = Sync.stats.dropped + 1
		Debug(L.DEBUG_DROP_INVALID, sender)
		return
	end
	Sync.stats.received = Sync.stats.received + 1
	handler(message, sender)
end)

--------------------------------------------------------------------------------
-- Publishing
--------------------------------------------------------------------------------

-- Stores and broadcasts an own ad or tombstone.
function Sync.Publish(ad)
	Store.Put(ad)
	SendAds({ ad }, "NORMAL")
end

local helloTicker
ns.RegisterCallback(Sync, "GFF_CHANNEL_READY", function(_, number)
	Debug(L.DEBUG_CHANNEL, number or 0)
	C_Timer.After(HELLO_DELAY_MIN + math.random() * (HELLO_DELAY_MAX - HELLO_DELAY_MIN), Sync.SendHello)
	if not helloTicker then
		helloTicker = C_Timer.NewTicker(HELLO_INTERVAL, function()
			Store.Prune()
			Sync.SendHello()
		end)
	end
	ns:Fire("GFF_SYNC_STARTED")
end)

ns.RegisterCallback(Sync, "GFF_COMM_HELD", function(_, count)
	Debug(L.DEBUG_HELD, count)
end)

ns.RegisterCallback(Sync, "GFF_COMM_INVALID", function(_, sender)
	Debug(L.DEBUG_DROP_INVALID, sender)
end)
