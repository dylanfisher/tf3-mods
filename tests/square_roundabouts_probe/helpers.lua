-- Shared test helpers for square_roundabouts_probe (loaded with loadfile, not a test file).
-- loadRoundabouts(): the real square_roundabouts geometry modules (the harness only resolves the
-- probe's own modules, so they are loaded from mods/square_roundabouts/content here and
-- registered with stub_module so the probe's ug_require calls find them too).
-- loadCon(name): data() of a square_roundabouts .con.lua. readJson(path): a small JSON decoder.

local H = {}
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local RB_CONTENT = here .. "../../mods/square_roundabouts/content"
local PROBE_ROOT = here .. "../../mods/square_roundabouts_probe/"
local PREFIX = "square_roundabouts::"
H.PROBE_ROOT = PROBE_ROOT

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
	local f = assert(io.open(PROBE_ROOT .. rel, "r"))
	local s = f:read("a")
	f:close()
	return H.decodeJson(s)
end

--- Parses a [SQRB_PROBE] line like tools/parse_probe.py: kind and key=value fields.
function H.parseLine(line)
	local rest = line:match("%[SQRB_PROBE%] (.*)$")
	if not rest then return nil end
	local kind, body = rest:match("^(%S+)%s*(.*)$")
	local fields, order = {}, {}
	local i = 1
	while i <= #body do
		local k, j = body:match("^(%w+)=()", i)
		if not k then
			i = (body:find(" ", i, true) or #body) + 1
		else
			local v
			if body:sub(j, j) == '"' then
				local close = body:find('"', j + 1, true)
				v = body:sub(j + 1, close - 1)
				i = close + 2
			else
				local stop = body:find(" ", j, true) or #body + 1
				v = body:sub(j, stop - 1)
				i = stop + 1
			end
			fields[k] = v
			order[#order + 1] = k
		end
	end
	return kind, fields, order
end

return H
