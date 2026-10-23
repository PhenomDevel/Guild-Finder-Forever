local _, ns = ...

local L = ns.L

-- Subcommands register themselves with ns:RegisterCommand; `/gff` without a
-- known subcommand prints the list.
local commands = {}
local order = {}

-- handler(args) receives the rest of the line, trimmed.
-- usage and description are shown in the help, e.g. "probe <cmd>".
function ns:RegisterCommand(name, handler, usage, description)
	if not commands[name] then
		order[#order + 1] = name
	end
	commands[name] = { handler = handler, usage = usage or name, description = description }
end

local function PrintHelp()
	ns:Print(L.HELP_HEADER)
	for _, name in ipairs(order) do
		local command = commands[name]
		DEFAULT_CHAT_FRAME:AddMessage(("  |cffffd100/gff %s|r – %s"):format(command.usage, command.description or ""))
	end
end

SLASH_GUILDFINDERFOREVER1 = "/gff"
SLASH_GUILDFINDERFOREVER2 = "/guildfinder"
SlashCmdList.GUILDFINDERFOREVER = function(input)
	local name, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	name = name:lower()
	local command = commands[name]
	if command then
		command.handler(rest)
	else
		if name ~= "" and name ~= "help" then
			ns:Print(L.UNKNOWN_COMMAND, name)
		end
		PrintHelp()
	end
end

ns:RegisterEvent("PLAYER_LOGIN", function()
	ns:Print(L.ADDON_LOADED, ns.version)
end)
