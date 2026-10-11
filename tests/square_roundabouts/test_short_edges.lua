-- Short edges and availability (PHASE5.md Phase 5a), on the construction result each entry's
-- updateFn returns for shipped params (no sqrb_dev_* overrides):
--   * no edge has a chord or Hermite length under 1 m, and no two distinct nodes lie within 0.5 m
--     of each other (checks.shortEdges);
--   * the entry's availability.yearFrom is exactly the latest yearFrom of any base template it
--     emits (checks.latestYear): as early as its templates allow, never before one exists.
-- New entries add a sweep to ENTRIES.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local channel = ug_require(DIR .. "square_roundabouts_channel.lua")
local interchange = ug_require(DIR .. "square_roundabouts_interchange.lua")
local highway = ug_require(DIR .. "square_roundabouts_highway.lua")
local K = geom.PARAM_KEYS
local MK = magic.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local G = loadfile(here .. "golden.lua", "t", _ENV)()

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end

local function range(n) local t = {}; for i = 1, n do t[i] = i end; return t end

--- Calls fn(params) for the cartesian product of the value lists in grid (keys are param keys).
local function each(grid, fn)
	local keys = {}
	for k in pairs(grid) do keys[#keys + 1] = k end
	table.sort(keys)
	local function rec(i, p)
		if i > #keys then
			local copy = {}
			for k, v in pairs(p) do copy[k] = v end
			return fn(copy)
		end
		for _, v in ipairs(grid[keys[i]]) do
			p[keys[i]] = v
			rec(i + 1, p)
		end
	end
	rec(1, {})
end

local function label(p)
	local keys, parts = {}, {}
	for k in pairs(p) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do parts[#parts + 1] = k:gsub("^sqrb_", "") .. "=" .. tostring(p[k]) end
	return table.concat(parts, " ")
end

-- Shipped-param sweeps per entry. Main: the golden fingerprint grid (every feature, 3 shapes,
-- 3 radii, arms T / Y / 5 / none, 3 arm roads) plus every radius with 4 and 6 arms (the shortest
-- ring edges), round and 2:1, every lane count, splitter, through road, the other 3 arm roads;
-- the Phase 5c through roads (Road + traffic lights x every other through road).
local function mainSweep(fn)
	local groups, order = G.mainGroups(K)
	for _, name in ipairs(order) do
		for _, p in ipairs(groups[name]) do fn(p) end
	end
	each({
		[K.radius] = range(#geom.RADII), [K.arms] = { 3, 5 }, [K.shape] = { 1, #geom.SHAPE_RATIOS },
		[K.lanes] = { 1, 2, 3 }, [K.splitter] = { 1, 2 }, [K.armType] = { 2, 4, 6 }, [K.centre] = { 1, 2, 3 },
		[K.direction] = { 2 },
	}, fn)
	-- Phase 5c: Road + traffic lights (the Road geometry) with every other through road
	each({
		[K.radius] = { 1, geom.DEFAULT_RADIUS, #geom.RADII }, [K.arms] = { 1, 3, 6 }, [K.shape] = { 1, #geom.SHAPE_RATIOS },
		[K.lanes] = { 1, 2, 3 }, [K.splitter] = { 1, 2 }, [K.armType] = { 1, 4 }, [K.centre] = { 4 },
		[K.throughRoad] = { 2, 3, 4, 5, 6, 7 },
	}, function(p)
		if p[K.throughRoad] ~= p[K.armType] + 1 then fn(p) end
	end)
end

-- Magic: every value of every param.
local function magicSweep(fn)
	each({
		[MK.size] = range(#magic.SIZES), [MK.armType] = range(#geom.ARM_TEMPLATES), [MK.direction] = { 1, 2 },
		[MK.lanes] = range(magic.LANE_CHOICES), [MK.island] = range(5),
	}, fn)
end

-- Channelized junction: every value of every param (Islands None / Paved: Grass has the same roads)
-- at Scale XS (the grid lives in golden.lua, shared with test_entries_unchanged_channel.lua), then
-- Scale S-XL (revision 6): every layout x main x side x slips x splitter x traffic side, the
-- shortest and longest arm, Islands Paved.
local function channelSweep(fn)
	G.channelSweep(channel, geom, fn)
	local CK = channel.PARAM_KEYS
	G.each({
		[CK.scale] = { 2, 3, 4, 5 }, [CK.layout] = { 1, 2 }, [CK.main] = range(#geom.ARM_TEMPLATES),
		[CK.side] = range(#geom.ARM_TEMPLATES), [CK.slips] = { 1, 2, 3 }, [CK.splitter] = { 1, 2 },
		[CK.armLength] = { 1, #channel.ARM_LENGTHS }, [CK.direction] = { 1, 2 }, [CK.island] = { 3 },
	}, fn)
end

-- Roundabout interchange: every layout x highway x level x lanes x traffic side, the extreme
-- radii, four cross roads, the shortest and longest slip roads, Centre island None / Fountain
-- (golden.lua G.interchangeSweep, shared with test_entries_unchanged_interchange.lua).
-- params.year = 1969 (steel bridges, the 1940 type; concrete is checked in test_interchange.lua):
-- with the year missing the updateFn builds concrete bridges (1970), as the base interchanges do.
local function interchangeSweep(fn)
	G.interchangeSweep(interchange, 1969, fn)
end

-- Highway Interchange (Phases 7b / 7c / 7c2): every type x highway x level x side x Scale, four cross
-- roads, the extreme ramp lengths (golden.lua G.highwaySweep), params.year = 1969 (steel bridges).
local function highwaySweep(fn)
	G.highwaySweep(highway, 1969, fn)
end

local ENTRIES = {
	{ name = "main", con = "square_roundabouts.con.lua", script = "square_roundabouts.script.lua", sweep = mainSweep },
	{ name = "magic", con = "square_roundabouts_magic.con.lua", script = "square_roundabouts_magic.script.lua", sweep = magicSweep },
	{ name = "channel", con = "square_roundabouts_channel.con.lua", script = "square_roundabouts_channel.script.lua", sweep = channelSweep },
	{ name = "interchange", con = "square_roundabouts_interchange.con.lua", script = "square_roundabouts_interchange.script.lua", sweep = interchangeSweep },
	{ name = "highway", con = "square_roundabouts_highway_parclo.con.lua", script = "square_roundabouts_highway.script.lua", sweep = highwaySweep },
}

for _, entry in ipairs(ENTRIES) do
	test(entry.name .. ": no edge under 1 m, no nodes within 0.5 m; yearFrom = latest template year", function()
		local yearFrom = entry.yearFrom or loadData(entry.con).availability.yearFrom
		local updateFn = entry.updateFn or loadData(entry.script).updateFn
		local latest, builds, seen, stats = 0, 0, {}, {}
		entry.sweep(function(p)
			local res = updateFn({}, p)
			builds = builds + 1
			checks.report(checks.shortEdges(res, 1.0, 0.5, stats), label(p))
			local y, unknown = checks.latestYear(res, seen)
			checks.report(unknown, label(p))
			latest = math.max(latest, y)
		end)
		eq(latest, yearFrom, "availability.yearFrom vs the latest template yearFrom")
		local names = {}
		for n in pairs(seen) do names[#names + 1] = n end
		print(string.format("    %d builds, %d templates, latest yearFrom %d; shortest edge %.1f m, closest nodes %.1f m apart",
			builds, #names, latest, stats.len, stats.gap))
	end)
end

test("shortEdges: catches a short edge, a near node and keeps tagged merges", function()
	local function el(edges) return { edgeLists = { { params = { type = "x" }, edges = edges } } } end
	local t = { 1, 0, 0 }
	eq(#checks.shortEdges(el({ { { 0, 0, 0 }, t }, { { 10, 0, 0 }, t } })), 0)
	-- chord 0.8 m
	ok(#checks.shortEdges(el({ { { 0, 0, 0 }, t }, { { 0.8, 0, 0 }, t } })) > 0)
	-- chord 2 m: fine
	eq(#checks.shortEdges(el({ { { 0, 0, 0 }, { 2, 0, 0 } }, { { 2, 0, 0 }, { 2, 0, 0 } } })), 0)
	-- two edges whose ends lie 0.3 m apart (untagged): not merged, on top of each other
	local p = checks.shortEdges(el({
		{ { 0, 0, 0 }, t }, { { 10, 0, 0 }, t },
		{ { 10.3, 0, 0 }, t }, { { 20, 0, 0 }, t },
	}))
	eq(#p, 1); ok(p[1]:find("0.30 m apart", 1, true), p[1])
	-- same position, same tag (or both untagged): one node
	eq(#checks.shortEdges(el({
		{ { 0, 0, 0 }, t }, { { 10, 0, 0 }, t, "a" },
		{ { 10, 0, 0 }, t, "a" }, { { 20, 0, 0 }, t },
		{ { 20, 0, 0 }, t }, { { 30, 0, 0 }, t },
	})), 0)
	-- same position, tagged and untagged: the engine does not merge them (basics.md "Edge Lists")
	ok(#checks.shortEdges(el({
		{ { 0, 0, 0 }, t }, { { 10, 0, 0 }, t, "a" },
		{ { 10, 0, 0 }, t }, { { 20, 0, 0 }, t },
	})) > 0)
	-- stacked levels (a bridge 8 m above a road node) are far apart in 3D
	eq(#checks.shortEdges(el({
		{ { 0, 0, 0 }, t }, { { 10, 0, 0 }, t },
		{ { 10, 0, 8 }, t }, { { 20, 0, 8 }, t },
	})), 0)
	local latest, unknown = checks.latestYear({ edgeLists = {
		{ params = { type = geom.TRAM_THROUGH.template } },
		{ params = { type = "::/nope.street_template" }, edgeTypeName = "::/infrastructure/bridge/steel.bridge" },
	} })
	eq(latest, 1940); eq(#unknown, 1)
end)
