local addonName, ns = ...

ns.name = addonName
ns.title = "Guild Finder Forever"
ns.shortTitle = "GFF"
ns.color = "e6b43a"

local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local version = getMetadata and getMetadata(addonName, "Version")
if not version or version:find("@project%-version@") then
	version = ns.L.UNKNOWN_VERSION
end
ns.version = version

-- Public handle, mainly for debugging with /dump GuildFinderForever.
_G.GuildFinderForever = ns

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
-- Game events go to plain callbacks; several files may listen to the same
-- event. Internal messages between files use CallbackHandler:
--   ns.RegisterCallback(owner, "GFF_SOMETHING", func)  /  ns:Fire("GFF_SOMETHING", ...)

local eventFrame = CreateFrame("Frame")
local eventCallbacks = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = eventCallbacks[event]
	if not list then
		return
	end
	-- Iterate over a snapshot so callbacks may unregister themselves.
	local snapshot = { unpack(list) }
	for i = 1, #snapshot do
		snapshot[i](event, ...)
	end
end)

function ns:RegisterEvent(event, callback)
	local list = eventCallbacks[event]
	if not list then
		list = {}
		eventCallbacks[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = callback
end

function ns:UnregisterEvent(event, callback)
	local list = eventCallbacks[event]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == callback then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		eventCallbacks[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

ns.callbacks = LibStub("CallbackHandler-1.0"):New(ns)

function ns:Fire(message, ...)
	self.callbacks:Fire(message, ...)
end

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

function ns:Print(text, ...)
	if select("#", ...) > 0 then
		text = text:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage(("|cff%s%s|r: %s"):format(self.color, self.shortTitle, text))
end

--------------------------------------------------------------------------------
-- Player
--------------------------------------------------------------------------------

-- "Name-Realm", the format CHAT_MSG_ADDON reports senders in. Nil before the
-- realm is known (early in the loading process).
function ns:GetPlayerFullName()
	local name, realm = UnitFullName("player")
	if name and realm and realm ~= "" then
		return name .. "-" .. realm
	end
end
