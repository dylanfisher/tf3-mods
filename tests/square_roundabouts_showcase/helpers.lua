-- Shared test helpers for square_roundabouts_showcase (loaded with loadfile, not a test file),
-- adapted from tests/square_roundabouts_probe/helpers.lua.
-- rbRequire(path): a real square_roundabouts module (the harness only resolves the showcase's own
-- modules, so they are loaded from mods/square_roundabouts/content here and registered with
-- stub_module). entries(): the entry models of every square_roundabouts entry, built from the
-- .con.lua data() exactly as the game's rep would give them. fakeFp(w, h, cx, cy): a footprint.
-- loadCon(name): data() of a square_roundabouts .con.lua. readJson(path): a small JSON decoder.

local H = {}
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local RB_CONTENT = here .. "../../mods/square_roundabouts/content"
local MOD_ROOT = here .. "../../mods/square_roundabouts_showcase/"
local PREFIX = "square_roundabouts::"
H.MOD_ROOT = MOD_ROOT

local cache = {}
local function rbRequire(path)
	if cache[path] ~= nil then return cache[path] end
	assert(path:sub(1, #PREFIX) == PREFIX, "unexpected module " .. path)
	local file = RB_CONTENT .. path:sub(#PREFIX + 1)
	local env = setmetatable({ ug_require = rbRequire }, { __index = _ENV })
	local chunk = assert(loadfile(file, "t", env))
	local v = chunk()
	if v == nil then v = true end
	cache[path] = v
	stub_module(path, v)
	return v
end

H.rbRequire = rbRequire

local DIR = PREFIX .. "/infrastructure/street_construction/"
function H.loadRoundabouts()
	return {
		geom = rbRequire(DIR .. "square_roundabouts_geometry.lua"),
		magic = rbRequire(DIR .. "square_roundabouts_magic.lua"),
		channel = rbRequire(DIR .. "square_roundabouts_channel.lua"),
		interchange = rbRequire(DIR .. "square_roundabouts_interchange.lua"),
		highway = rbRequire(DIR .. "square_roundabouts_highway.lua"),
		ramps = rbRequire(DIR .. "square_roundabouts_ramps.lua"),
	}
end

function H.loadCon(name)
	local env = setmetatable({ ug_require = rbRequire, _ = function(s) return s end }, { __index = _ENV })
	local chunk = assert(loadfile(RB_CONTENT .. "/infrastructure/street_construction/" .. name, "t", env))
	chunk()
	return env.data()
end

-- Minimal JSON decoder (objects, arrays, strings without unicode escapes, numbers, true/false/null).
function H.decodeJson(s)
	local pos = 1
	local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
	local value
	local function str()
		local out = {}
		pos = pos + 1
		while true do
			local c = s:sub(pos, pos)
			if c == '"' then pos = pos + 1 break end
			if c == "\\" then
				local n = s:sub(pos + 1, pos + 1)
				out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n
				pos = pos + 2
			else
				out[#out + 1] = c
				pos = pos + 1
			end
		end
		return table.concat(out)
	end
	function value()
		ws()
		local c = s:sub(pos, pos)
		if c == "{" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
			while true do
				ws()
				local k = str()
				ws()
				assert(s:sub(pos, pos) == ":", "json: ':' expected at " .. pos)
				pos = pos + 1
				t[k] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "}" then return t end
				assert(d == ",", "json: ',' expected at " .. pos)
			end
		elseif c == "[" then
			local t = {}
			pos = pos + 1
			ws()
			if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
			while true do
				t[#t + 1] = value()
				ws()
				local d = s:sub(pos, pos)
				pos = pos + 1
				if d == "]" then return t end
				assert(d == ",", "json: ',' expected at " .. pos)
			end
		elseif c == '"' then
			return str()
		elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
		elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
		elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			assert(num and #num > 0, "json: bad value at " .. pos)
			pos = pos + #num
			return tonumber(num)
		end
	end
	return value()
end

function H.readJson(rel)
	local f = assert(io.open(MOD_ROOT .. rel, "r"))
	local s = f:read("a")
	f:close()
	return H.decodeJson(s)
end

--- The entry models of the showcase's config.ENTRIES (every square_roundabouts entry).
function H.entries(ids)
	local config = ug_require "/showcase/sc_config.lua"
	local combos = ug_require "/showcase/sc_combos.lua"
	local out = {}
	for _, e in ipairs(config.ENTRIES) do
		local want = ids == nil
		for _, id in ipairs(ids or {}) do if id == e.id then want = true end end
		if want then
			local con = H.loadCon(e.file:match("([^/]+)$") .. ".lua")
			out[#out + 1] = combos.entryFromCon(e, con, "square_roundabouts::/" .. e.file)
		end
	end
	return out
end

--- Full width of a base street template, read offline from the extracted game files
-- (.cache/game/base/content/<path>.lua: the sum of laneConfigs widths, as sc_engine reads the rep),
-- nil when the file is missing (fresh clone without `make docs`).
local GAME_CONTENT = here .. "../../.cache/game/base/content/"
local widthCache = {}
function H.widthOf(template)
	if widthCache[template] ~= nil then return widthCache[template] or nil end
	local rel = tostring(template):gsub("^::/", "")
	local env = setmetatable({ _ = function(x) return x end }, { __index = _ENV })
	local chunk = loadfile(GAME_CONTENT .. rel .. ".lua", "t", env)
	local w = nil
	if chunk and pcall(chunk) and env.data then
		local ok, t = pcall(env.data)
		if ok and type(t) == "table" then
			local sum = 0
			for _, lc in ipairs(t.laneConfigs or {}) do sum = sum + (lc.width or 0) end
			if sum > 0 then w = sum end
		end
	end
	widthCache[template] = w or false
	return w
end
H.FP_OPTS = { widthOf = H.widthOf }

--- A footprint of w x h with its bbox centre at (cx, cy) in the construction frame.
function H.fakeFp(w, h, cx, cy)
	local fpMod = ug_require "/showcase/sc_footprint.lua"
	cx, cy = cx or 0, cy or 0
	return fpMod.box(cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2, "fake", 1)
end

return H
