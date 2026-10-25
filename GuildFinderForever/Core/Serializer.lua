local _, ns = ...

-- Compact serializer for protocol messages. Strings are length-prefixed, so
-- no escaping is needed and any byte is allowed:
--   s<len>:<bytes>   string        n<number>;   number
--   T / F            boolean       { key value ... }   table
-- Deserialize never runs code and rejects anything malformed, too deep or
-- too large; received data is untrusted.
local Serializer = {}
ns.Serializer = Serializer

local MAX_DEPTH = 6
local MAX_ITEMS = 4000

local concat, type, pairs = table.concat, type, pairs

local function Write(out, value, depth)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = "s" .. #value .. ":" .. value
	elseif kind == "number" then
		-- %.17g keeps doubles exact; integers stay short.
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			out[#out + 1] = ("n%d;"):format(value)
		else
			out[#out + 1] = "n" .. ("%.17g"):format(value) .. ";"
		end
	elseif kind == "boolean" then
		out[#out + 1] = value and "T" or "F"
	elseif kind == "table" then
		if depth >= MAX_DEPTH then
			error("Serializer: table too deep")
		end
		out[#out + 1] = "{"
		for key, item in pairs(value) do
			Write(out, key, depth + 1)
			Write(out, item, depth + 1)
		end
		out[#out + 1] = "}"
	else
		error("Serializer: cannot write " .. kind)
	end
end

function Serializer.Serialize(value)
	local out = {}
	Write(out, value, 0)
	return concat(out)
end

-- Reader state is kept in locals of Deserialize; Read returns value, nextPos
-- or nil on any error.
function Serializer.Deserialize(text)
	if type(text) ~= "string" then
		return nil
	end
	local len = #text
	local items = 0
	local Read

	local function ReadTable(pos, depth)
		if depth >= MAX_DEPTH then
			return nil
		end
		local result = {}
		while true do
			if pos > len then
				return nil
			end
			if text:byte(pos) == 125 then -- "}"
				return result, pos + 1
			end
			local key, value
			key, pos = Read(pos, depth + 1)
			if key == nil then
				return nil
			end
			value, pos = Read(pos, depth + 1)
			if value == nil then
				return nil
			end
			if (type(key) == "number" and key ~= key) or type(key) == "table" then
				return nil
			end
			result[key] = value
		end
	end

	function Read(pos, depth)
		items = items + 1
		if items > MAX_ITEMS or pos > len then
			return nil
		end
		local tag = text:sub(pos, pos)
		if tag == "s" then
			local digits, colon = text:match("^(%d+)():", pos + 1)
			if not digits or #digits > 6 then
				return nil
			end
			local size = tonumber(digits)
			local first = colon + 1
			local last = first + size - 1
			if last > len then
				return nil
			end
			return text:sub(first, last), last + 1
		elseif tag == "n" then
			local raw, nextPos = text:match("^([%d%.eE+%-]+);()", pos + 1)
			local number = raw and #raw <= 24 and tonumber(raw)
			if not number or number ~= number or number == math.huge or number == -math.huge then
				return nil
			end
			return number, nextPos
		elseif tag == "T" then
			return true, pos + 1
		elseif tag == "F" then
			return false, pos + 1
		elseif tag == "{" then
			return ReadTable(pos + 1, depth)
		end
		return nil
	end

	local ok, value, pos = pcall(Read, 1, 0)
	if not ok or value == nil or pos ~= len + 1 then
		return nil
	end
	return value
end

--------------------------------------------------------------------------------
-- Hashing
--------------------------------------------------------------------------------
-- 32-bit polynomial string hash without the bit library (doubles stay exact
-- below 2^53). Used for the sync bucket summaries, not for security.

local MOD = 4294967296

function Serializer.Hash(text, seed)
	local hash = seed or 5381
	for i = 1, #text do
		hash = (hash * 33 + text:byte(i)) % MOD
	end
	return hash
end

-- Combines unordered values: the sum is independent of iteration order.
function Serializer.Combine(a, b)
	return (a + b) % MOD
end
