std = "lua51"
max_line_length = false
codes = true
exclude_files = {
	".release/",
	-- Third-party libraries (.pkgmeta externals, tools/fetch-libs.sh).
	"GuildFinderForever/Libs/",
}

-- Ignore unused `self` and unused arguments starting with an underscore.
self = false
unused_args = true
ignore = { "212/_.*" }

-- Globals the addon defines.
globals = {
	"GuildFinderForever",
	"GuildFinderForeverDB",
	"GuildFinderForeverCharDB",
	"SLASH_GUILDFINDERFOREVER1",
	"SLASH_GUILDFINDERFOREVER2",
	"SlashCmdList",
}

-- WoW API shared by most files. Everything else is declared inline:
--   -- luacheck: read globals SomeApiFunction C_Something
read_globals = {
	-- Lua extensions provided by the client
	"wipe",
	"date",
	"time",
	"strtrim",
	"strsplit",
	"issecretvalue",

	-- Libraries
	"LibStub",

	-- Frames & UI
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",

	-- General API
	"C_AddOns",
	"C_ChatInfo",
	"C_Timer",
	"Enum",
	"GetAddOnMetadata",
	"GetBuildInfo",
	"GetLocale",
	"GetServerTime",
	"GetTime",
	"UnitFullName",
}
