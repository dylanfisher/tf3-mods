-- Structure: Embankment / Bridge (square_roundabouts_result.lua "Structure", PLAN.md open work 6).
-- The param on every menu entry, Bridge mode on every entry's updateFn (every edge list a bridge, the
-- interchanges' own bridges keep their type, the type by year, no islands, the same roads), and the
-- mod's short-span concrete bridge file (a copy of base concrete with "::/" paths).
-- Embankment = the result as before: test_structure_embankment.lua.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")
local K = geom.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local G = loadfile(here .. "golden.lua", "t", _ENV)()

local function loadData(file)
	-- the file defines a global data(); each load replaces it
	ug_require(DIR .. file)
	return data()
end

local CONS = {
	"square_roundabouts.con.lua",
	"square_roundabouts_magic.con.lua",
	"square_roundabouts_channel.con.lua",
	"square_roundabouts_interchange.con.lua",
	"square_roundabouts_highway_parclo.con.lua",
	"square_roundabouts_highway_parclo2.con.lua",
	"square_roundabouts_highway_diamond.con.lua",
}
-- the interchanges default to Bridge (their ramps climb to the upper level anyway), the rest to Embankment
local BRIDGE_DEFAULT = {
	["square_roundabouts_interchange.con.lua"] = true,
	["square_roundabouts_highway_parclo.con.lua"] = true,
	["square_roundabouts_highway_parclo2.con.lua"] = true,
	["square_roundabouts_highway_diamond.con.lua"] = true,
}

test("every entry: Structure is the last param (Embankment / Bridge; Bridge default on the interchanges), in the toolbar", function()
	for _, file in ipairs(CONS) do
		local con = loadData(file)
		local p = con.params[#con.params]
		eq(p.key, result.STRUCTURE_KEY, file .. ": last param")
		eq(p.name, "Structure", file)
		eq(p.uiType, "ComboBox", file)
		eq(p.values, { "Embankment", "Bridge" }, file)
		eq(p.defaultIndex, BRIDGE_DEFAULT[file] and result.STRUCTURE_BRIDGE or result.STRUCTURE_EMBANKMENT, file)
		eq(p.location, "Toolbar", file)
		ok(p.tooltip:find("Height control", 1, true) ~= nil, file .. ": tooltip names the Height control")
		for line in p.tooltip:gmatch("[^\n]+") do ok(#line <= 60, file .. ": tooltip line: " .. line) end
		local n = 0
		for _, q in ipairs(con.params) do if q.key == result.STRUCTURE_KEY then n = n + 1 end end
		eq(n, 1, file .. ": once")
	end
	eq(result.STRUCTURE_EMBANKMENT, 1); eq(result.STRUCTURE_BRIDGE, 2) -- saved indices keep their meaning
end)

test("readStructure / structureBridgeType: Bridge only for value 2; stone before 1970, short-span concrete from 1970", function()
	eq(result.readStructure({}), nil)
	eq(result.readStructure(nil), nil)
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 1 }), nil)
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 3 }), nil, "unknown value: Embankment")
	eq(result.readStructure({ [result.STRUCTURE_KEY] = "x" }), nil)
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 2 }).bridge, result.BRIDGE_SHORT_CONCRETE, "no year")
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 2, year = 1850 }).bridge, result.BRIDGE_STONE)
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 2, year = 1969 }).bridge, result.BRIDGE_STONE)
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 2, year = 1970 }).bridge, result.BRIDGE_SHORT_CONCRETE)
	eq(result.readStructure({ [result.STRUCTURE_KEY] = 2, year = 2050 }).bridge, result.BRIDGE_SHORT_CONCRETE)
	eq(result.BRIDGE_STONE, "::/infrastructure/bridge/stone.bridge")
	eq(result.BRIDGE_SHORT_CONCRETE, "square_roundabouts::/infrastructure/bridge/square_roundabouts_concrete_short.bridge")
end)

-- Every entry's updateFn and a sweep of its params (the golden groups' params, flattened): a quick
-- run checks every STRIDE-th case plus the first of each param value (checks.pick), --full all.
local function updateFnOf(file) return loadData(file).updateFn end
local ENTRY_FNS = {
	main = updateFnOf("square_roundabouts.script.lua"),
	magic = updateFnOf("square_roundabouts_magic.script.lua"),
	channel = updateFnOf("square_roundabouts_channel.script.lua"),
	interchange = updateFnOf("square_roundabouts_interchange.script.lua"),
	highway = updateFnOf("square_roundabouts_highway.script.lua"),
}
local MODS = {
	channel = ug_require(DIR .. "square_roundabouts_channel.lua"),
	interchange = ug_require(DIR .. "square_roundabouts_interchange.lua"),
	highway = ug_require(DIR .. "square_roundabouts_highway.lua"),
}
local YEARS = { 1950, 1969, 1970, 2020, false }

local function cases(entry)
	local groups, order
	if entry == "main" then groups, order = G.mainGroups(K)
	elseif entry == "magic" then groups, order = G.magicGroups(K)
	else groups, order = G.entryGroups(entry, MODS[entry], geom) end
	local all = {}
	for _, name in ipairs(order) do
		for _, p in ipairs(groups[name]) do
			local c = {}
			for k, v in pairs(p) do c[k] = v end
			-- the year cycles through both bridge types (the interchanges' own ones too)
			c.year = YEARS[#all % #YEARS + 1] or nil
			all[#all + 1] = c
		end
	end
	return all
end

-- quick: one test per entry over a sample (checks.pick, every param value); --full: every case, in
-- PARTS slices per entry so each test stays under 8 s (the runner shards by test)
local PARTS = checks.FULL and 12 or 1
local function slice(entry, part, parts)
	local all = cases(entry)
	local idx = checks.pick(#all, entry == "magic" and 3 or 61, function(i) return checks.values(all[i]) end)
	local per = math.ceil(#idx / parts)
	local out = {}
	for k = (part - 1) * per + 1, math.min(#idx, part * per) do out[#out + 1] = all[idx[k]] end
	return out
end

local function text(v) return table.concat(G.serializeExact(v)) end

for _, entry in ipairs({ "main", "magic", "channel", "interchange", "highway" }) do
	for part = 1, entry == "magic" and 1 or PARTS do
	test("Bridge: every edge list a bridge of the year's type, own bridges kept, same roads, no islands: " .. entry
			.. (PARTS > 1 and entry ~= "magic" and string.format(", part %d/%d", part, PARTS) or ""), function()
		local fn = ENTRY_FNS[entry]
		local n, kept, stone, short, islands = 0, 0, 0, 0, 0
		for _, p in ipairs(entry == "magic" and slice(entry, 1, 1) or slice(entry, part, PARTS)) do
			local emb = fn({}, p)
			local q = {}
			for k, v in pairs(p) do q[k] = v end
			q[result.STRUCTURE_KEY] = result.STRUCTURE_BRIDGE
			local br = fn({}, q)
			local want = (p.year and p.year < 1970) and result.BRIDGE_STONE or result.BRIDGE_SHORT_CONCRETE
			local label = entry .. " " .. table.concat(checks.values(p), ",")
			eq(#br.edgeLists, #emb.edgeLists, label .. ": edge lists")
			for i, el in ipairs(br.edgeLists) do
				local e = emb.edgeLists[i]
				eq(el.edgeType, "BRIDGE", label .. ": list " .. i)
				if e.edgeType then
					eq(el.edgeTypeName, e.edgeTypeName, label .. ": own bridge kept")
					kept = kept + 1
				else
					eq(el.edgeTypeName, want, label .. ": bridge type by year")
					if want == result.BRIDGE_STONE then stone = stone + 1 else short = short + 1 end
				end
				-- the same roads, bit for bit (-0 included: geometry is untouched)
				eq(text(el.edges), text(e.edges), label .. ": edges")
				eq(text(el.params), text(e.params), label .. ": params")
				eq(el.freeNodes, e.freeNodes); eq(el.snapNodes, {}); eq(el.type, "STREET")
				eq(text(el.trafficLightYes or {}), text(e.trafficLightYes or {}))
			end
			if emb.subconstructions then islands = islands + 1 end
			eq(br.subconstructions, nil, label .. ": no islands")
			eq(br.models, {}); eq(br.groundFaces, {}); eq(br.terrainAlignmentLists, nil)
			eq(br.cost, 0)
			n = n + 1
		end
		ok(n > 0 and stone > 0 and short > 0, "both bridge types")
		if entry == "interchange" or entry == "highway" then ok(kept > 0, "own bridges seen") end
		if entry ~= "highway" then ok(islands > 0, "island builds seen") end
		print(string.format("    %d builds: %d lists stone, %d short-span concrete, %d own bridges kept; %d with islands dropped",
			n, stone, short, kept, islands))
	end)
	end
end

-- The bridge file: base concrete.bridge.lua with only the marked lines changed, every path "::/".
local MOD_ROOT = here:gsub("tests/square_roundabouts/$", "") .. "mods/square_roundabouts/content/"
local BRIDGE_FILE = MOD_ROOT .. "infrastructure/bridge/square_roundabouts_concrete_short.bridge.lua"

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("a")
	f:close()
	return s
end

test("short-span concrete bridge: file named by BRIDGE_SHORT_CONCRETE, pillars 12-24 m, hidden, every path ::/", function()
	local rel = result.BRIDGE_SHORT_CONCRETE:match("^square_roundabouts::/(.*)$")
	ok(rel ~= nil, "a square_roundabouts:: resource")
	local src = readFile(MOD_ROOT .. rel .. ".lua")
	ok(src ~= nil, "file exists: " .. MOD_ROOT .. rel .. ".lua")
	eq(MOD_ROOT .. rel .. ".lua", BRIDGE_FILE)
	ok(src:find("pillarMinDist = 12.0,", 1, true) ~= nil, "pillarMinDist 12")
	ok(src:find("pillarTargetDist = 16.0,", 1, true) ~= nil, "pillarTargetDist 16")
	ok(src:find("pillarMaxDist = 24.0,", 1, true) ~= nil, "pillarMaxDist 24")
	ok(src:find("yearFrom = -1,", 1, true) ~= nil and src:find("yearTo = -1,", 1, true) ~= nil,
		"hidden from the bridge menu (as base placeholder.bridge.lua)")
	ok(src:find('name = _("Concrete, short spans")', 1, true) ~= nil, "translated name")
	-- every string literal outside comments that names a resource starts with "::/"
	local paths = 0
	for line in src:gmatch("[^\n]+") do
		-- comments out; model names appended to newdir ("::/infrastructure/bridge/concrete/") out
		local code = line:gsub("%-%-.*$", ""):gsub('newdir %.%. "[^"]*"', "")
		for s in code:gmatch('"([^"]*)"') do
			if s:find("/", 1, true) or s:find("%.%a+$") or s:find("@", 1, true) then
				paths = paths + 1
				ok(s:sub(1, 3) == "::/", "base path with ::/: " .. s)
			end
		end
	end
	ok(paths >= 13, "paths checked: " .. paths)
end)

test("short-span concrete bridge: only the marked lines differ from base concrete.bridge.lua", function()
	local src = readFile(BRIDGE_FILE)
	local base = readFile(here .. "../../.cache/game/base/content/infrastructure/bridge/concrete.bridge.lua")
	if not base then
		print("    skipped: .cache/game missing (make docs)")
		return
	end
	local function lines(s)
		local t = {}
		for l in (s:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end
		return t
	end
	local a, b = lines(base), lines(src)
	-- skip our header comment
	local off = 0
	while b[off + 1] and b[off + 1]:sub(1, 2) == "--" do off = off + 1 end
	local changed, i, j = 0, 1, off + 1
	while i <= #a and j <= #b do
		if a[i] == b[j] then
			i, j = i + 1, j + 1
		elseif b[j]:find("%-%- changed") then
			changed = changed + 1
			i, j = i + 1, j + 1
		else
			ok(false, string.format("unmarked difference at base line %d: %q vs %q", i, a[i], b[j]))
			return
		end
	end
	eq(i > #a and j > #b, true, "same length")
	eq(changed, 10, "marked lines")
end)
