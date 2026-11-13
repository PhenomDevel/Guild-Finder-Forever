-- luacheck: read globals GetNormalizedRealmName
local addonName, ns = ...

ns.name = addonName
ns.title = "Guild Finder Forever"
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
	DEFAULT_CHAT_FRAME:AddMessage(("|cff%s%s|r: %s"):format(self.color, self.title, text))
end

--------------------------------------------------------------------------------
-- Player
--------------------------------------------------------------------------------

-- Own realm, normalized ("CAMWOWEU4Realm1PvE" on Forever).
local function OwnRealm()
	local realm = GetNormalizedRealmName()
	if type(realm) == "string" and realm ~= "" then
		return realm
	end
end

-- Character name as the server writes it in chat and addon messages.
-- Forever names are "First Surname": UnitFullName returns them as name and
-- realm ("Phenom", "Shira"), so a "realm" that isn't ours is the surname.
-- Also returns the surname, if any.
function ns:GetPlayerName()
	local name, second = UnitFullName("player")
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local realm = OwnRealm()
	if type(second) == "string" and second ~= "" and realm and second ~= realm then
		return name .. " " .. second, second
	end
	return name
end

-- "Name-Realm", the format ads store owners in. Nil before the realm is
-- known (early in the loading process).
function ns:GetPlayerFullName()
	local name = ns:GetPlayerName()
	local realm = OwnRealm()
	if name and realm then
		return name .. "-" .. realm
	end
end

-- Name to whisper "Name-Realm" by. Forever's chat only accepts "First
-- Surname" (any realm suffix gives "No player named ..."), elsewhere only
-- the own realm is dropped.
function ns:WhisperTarget(name)
	if type(name) ~= "string" then
		return name
	end
	if ns.Ads.IsForever() then
		return name:match("^([^%-]+)") or name
	end
	local realm = OwnRealm()
	if realm and name:sub(-#realm - 1) == "-" .. realm then
		return name:sub(1, -#realm - 2)
	end
	return name
end

-- Adds the own realm to a name without one (senders on Forever).
function ns:NormalizeName(name)
	if type(name) ~= "string" or name:find("-", 1, true) then
		return name
	end
	local realm = OwnRealm()
	return realm and (name .. "-" .. realm) or name
end
