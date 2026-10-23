local _, ns = ...

if GetLocale() ~= "deDE" then
	return
end

local L = ns.L

-- General
L.ADDON_LOADED = "Version %s geladen. Gib |cffffd100/gff|r für die Befehle ein."
L.UNKNOWN_COMMAND = "Unbekannter Befehl |cffffd100%s|r."
L.HELP_HEADER = "Befehle:"
