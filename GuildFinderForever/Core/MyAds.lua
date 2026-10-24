-- luacheck: read globals IsInGuild
local _, ns = ...

-- The character's own player ad and the guild ad it may post. Drafts live in
-- GuildFinderForeverCharDB; the published versions in the shared cache.
local MyAds = {}
ns.MyAds = MyAds

local Ads = ns.Ads
local Store = ns.Store
local Sync = ns.Sync
local C = ns.Constants

-- Own ads are re-sent with a new version when older than this, which also
-- pushes their expiry out.
local RENEW_AGE = 24 * 3600
local LEVEL_UPDATE_AGE = 3600
local GUILD_CHECK_DELAY = 10

ns.charDbDefaults.playerDraft = {
	roles = 0,
	goals = 0,
	times = 0,
	text = "",
}

local function NewDraft()
	return { roles = 0, goals = 0, times = 0, text = "", lang = C.DefaultLanguage() }
end

function MyAds.GetPlayerDraft()
	local draft = ns.charDb.playerDraft
	draft.lang = draft.lang or C.DefaultLanguage()
	return draft
end

-- Draft for the guild ad: the published ad when there is one.
function MyAds.GetGuildDraft()
	local ad = MyAds.GetGuildAd()
	if ad then
		return { roles = ad.r or 0, goals = ad.g or 0, times = ad.t or 0, text = ad.x or "", lang = ad.l }
	end
	local draft = ns.charDb.guildDraft or NewDraft()
	ns.charDb.guildDraft = draft
	return draft
end

-- Live (not withdrawn) published ads, or nil.
function MyAds.GetPlayerAd()
	local id = Ads.GetOwnPlayerAdId()
	local ad = id and Store.Get(id)
	if ad and not ad.d and not Ads.IsExpired(ad) then
		return ad
	end
end

function MyAds.GetGuildAd()
	local id = Ads.GetOwnGuildAdId()
	local ad = id and Store.Get(id)
	if ad and not ad.d and not Ads.IsExpired(ad) then
		return ad
	end
end

-- Returns the published ad, or nil plus an error text.
function MyAds.PublishPlayer(draft)
	local ad = Ads.BuildPlayerAd(draft)
	if not ad then
		return nil, ns.L.ERROR_AD_INVALID
	end
	Sync.Publish(ad)
	return ad
end

function MyAds.PublishGuild(draft)
	if not Ads.GetGuild() then
		return nil, ns.L.ERROR_NO_GUILD
	end
	if not Ads.CanInvite() then
		return nil, ns.L.ERROR_NO_INVITE_RIGHTS
	end
	local ad = Ads.BuildGuildAd(draft)
	if not ad then
		return nil, ns.L.ERROR_AD_INVALID
	end
	ns.charDb.guildDraft = draft
	Sync.Publish(ad)
	return ad
end

local function Withdraw(ad)
	if ad then
		Sync.Publish(Ads.BuildTombstone(ad))
	end
end

function MyAds.WithdrawPlayer()
	Withdraw(MyAds.GetPlayerAd())
end

-- Any member with invite rights may withdraw the guild ad.
function MyAds.WithdrawGuild()
	if Ads.CanInvite() then
		Withdraw(MyAds.GetGuildAd())
	end
end

--------------------------------------------------------------------------------
-- Renewal and guild changes
--------------------------------------------------------------------------------

local function Age(ad)
	return GetServerTime() - ad.v
end

local function RenewPlayer(maxAge)
	local ad = MyAds.GetPlayerAd()
	if ad and Age(ad) > maxAge then
		MyAds.PublishPlayer(MyAds.GetPlayerDraft())
	end
end

-- Guild ads are renewed by the member who posted the current version.
local function RenewGuild()
	local ad = MyAds.GetGuildAd()
	if ad and ad.o == ns:GetPlayerFullName() and Age(ad) > RENEW_AGE and Ads.CanInvite() then
		MyAds.PublishGuild(MyAds.GetGuildDraft())
	end
end

-- Withdraws guild ads this character posted for a guild it is no longer in.
local function CheckGuildAds()
	local me = ns:GetPlayerFullName()
	if not me then
		return
	end
	local inGuild = IsInGuild()
	local guild = Ads.GetGuild()
	if inGuild and not guild then
		-- Guild info not loaded yet.
		return
	end
	for _, ad in Store.Each(Ads.KIND_GUILD) do
		if ad.o == me and ad.n ~= guild then
			Withdraw(ad)
		end
	end
end

ns.RegisterCallback(MyAds, "GFF_SYNC_STARTED", function()
	C_Timer.After(GUILD_CHECK_DELAY, function()
		CheckGuildAds()
		RenewPlayer(RENEW_AGE)
		RenewGuild()
	end)
end)

local guildTimer
ns:RegisterEvent("PLAYER_GUILD_UPDATE", function(_, unit)
	if unit and unit ~= "player" then
		return
	end
	if guildTimer then
		guildTimer:Cancel()
	end
	guildTimer = C_Timer.NewTimer(2, function()
		guildTimer = nil
		if ns.Channel.ready then
			CheckGuildAds()
		end
	end)
end)

ns:RegisterEvent("PLAYER_LEVEL_UP", function()
	-- UnitLevel lags behind the event a little.
	C_Timer.After(1, function()
		RenewPlayer(LEVEL_UPDATE_AGE)
	end)
end)
