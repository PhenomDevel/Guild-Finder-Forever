local addonName, ns = ...

-- GuildFinderForeverDB (account) holds settings and the ad cache,
-- GuildFinderForeverCharDB (character) the character's own state.
-- ns.dbLoaded / ns.charDbLoaded tell whether the client handed over saved
-- data at all; a known Forever beta bug sometimes skips loading it.

local DB_VERSION = 1

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = {}
				ApplyDefaults(target[key], value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			ApplyDefaults(target[key], value)
		end
	end
end

ns.dbDefaults = {
	version = DB_VERSION,
}

ns.charDbDefaults = {
	version = DB_VERSION,
}

local function OnAddonLoaded(event, name)
	if name ~= addonName then
		return
	end
	ns:UnregisterEvent(event, OnAddonLoaded)

	ns.dbLoaded = GuildFinderForeverDB ~= nil
	ns.charDbLoaded = GuildFinderForeverCharDB ~= nil
	GuildFinderForeverDB = GuildFinderForeverDB or {}
	GuildFinderForeverCharDB = GuildFinderForeverCharDB or {}
	ApplyDefaults(GuildFinderForeverDB, ns.dbDefaults)
	ApplyDefaults(GuildFinderForeverCharDB, ns.charDbDefaults)
	ns.db = GuildFinderForeverDB
	ns.charDb = GuildFinderForeverCharDB

	ns:Fire("GFF_DB_READY")
end

ns:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
