local _, ns = ...

-- enUS is the base locale, other locales override what they translate.
-- Missing keys resolve to the key itself, so typos are visible in-game.
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

-- General
L.UNKNOWN_VERSION = "dev"
L.ADDON_LOADED = "Version %s loaded. Type |cffffd100/gff|r for commands."
L.UNKNOWN_COMMAND = "Unknown command |cffffd100%s|r."
L.HELP_HEADER = "Commands:"
