-- Probe grid: subset sizes, unique replay keys, and that every axis matches the real .con.lua
-- params (key, number of values, default) and geom.PARAM_KEYS.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local grid = ug_require "/probe/probe_grid.lua"

local EXPECTED = {
	splitter6 = 2 * 3 * 4 * 1 * 1 * 3 * 6,
	main = 2 * 3 * 4 * 6 * 2 * 3 * 6 * 2,
	main_cw = 6 * 2 * 3 * 6,
	magic = 5 * 6 * 2,
}
EXPECTED.all = EXPECTED.main + EXPECTED.main_cw + EXPECTED.magic

test("subset sizes", function()
	for name, n in pairs(EXPECTED) do
		eq(#grid.expand(name), n, name)
		eq(grid.size(name), n, name .. " (size)")
	end
	eq(#grid.expand("main"), 10368)
	eq(#grid.expand("all"), 10644)
	local smoke = #grid.expand("smoke")
	ok(smoke >= 10 and smoke <= 40, "smoke has " .. smoke)
end)

test("every subset in the mod param order exists, and every subset is in it", function()
	local seen = {}
	for _, name in ipairs(grid.SUBSET_ORDER) do
		ok(grid.SUBSETS[name], name)
		seen[name] = true
	end
	for name in pairs(grid.SUBSETS) do ok(seen[name], name .. " missing from SUBSET_ORDER") end
end)

test("replay keys are unique and combos carry every param", function()
	local combos = grid.expand("all")
	local keys = {}
	for _, c in ipairs(combos) do
		ok(not keys[c.key], "duplicate " .. c.key)
		keys[c.key] = true
		local axes = grid.ENTRIES[c.entry].axes
		eq(#c.indices, #axes)
		for i, axis in ipairs(axes) do
			eq(c.params[axis.param], c.indices[i])
			eq(c.labels[i], axis.labels[c.indices[i]])
		end
	end
end)

test("main grid: only CCW, island None, signals Off; CW sample only CW", function()
	for _, c in ipairs(grid.expand("main")) do
		eq(c.params.sqrb_direction, 1)
		eq(c.params.sqrb_island, 1)
		eq(c.params.sqrb_signals, 1)
	end
	for _, c in ipairs(grid.expand("main_cw")) do eq(c.params.sqrb_direction, 2) end
end)

test("default block = the .con.lua defaults", function()
	local c = grid.expand({ { entry = "main" } })
	eq(#c, 1)
	eq(c[1].key, "m:1,2,5,3,1,1,1,1,1,1,1,1")
	local g = grid.expand({ { entry = "magic" } })
	eq(g[1].key, "g:3,1,1,1,1")
	eq(grid.expand({ { entry = "channel" } })[1].key, "c:1,2,1,1,1,1,1,1")
	local x = grid.expand({ { entry = "interchange" } })[1]
	eq(x.key, "x:1,2,1,2,2,2,2,1,1,1,2")
	eq(x.params.year, 2020, "pseudo axis: the value, not the index")
	local h = grid.expand({ { entry = "highway" } })[1]
	eq(h.key, "h:1,2,1,2,2,1,1,1,2")
	eq(h.params.year, 2020)
end)

test("main through axis: last (older 11-value keys keep their positions); old subsets stay Same as arms", function()
	local last = grid.MAIN_AXES[#grid.MAIN_AXES]
	eq(last.key, "through"); eq(last.param, "sqrb_through_road"); eq(last.default, 1)
	for _, name in ipairs(grid.SUBSET_ORDER) do
		if name:sub(1, 2) ~= "p5" and name ~= "smoke" then
			for _, c in ipairs(grid.expand(name)) do
				if c.entry == "main" then
					eq(c.params.sqrb_through_road, 1, name .. " " .. c.key)
					ok(c.params.sqrb_centre <= 3, name .. " " .. c.key)
				end
			end
		end
	end
end)

test("magic lanes axis: last (older 4-value keys keep their positions); old subsets stay 1 lane", function()
	local last = grid.MAGIC_AXES[#grid.MAGIC_AXES]
	eq(last.key, "lanes"); eq(last.param, "sqrb_magic_lanes"); eq(last.default, 1)
	for _, name in ipairs(grid.SUBSET_ORDER) do
		if name ~= "search_magic2" and name ~= "search_magic_sizes" then
			for _, c in ipairs(grid.expand(name)) do
				if c.entry == "magic" then
					eq(c.params.sqrb_magic_lanes, 1, name .. " " .. c.key)
					ok(c.key:sub(-2) == ",1", name .. " " .. c.key)
				end
			end
		end
	end
	local jobs = grid.expand("search_magic2")
	eq(#jobs, 12)
	local seen = {}
	for _, j in ipairs(jobs) do
		eq(j.entry, "magic"); eq(j.search.kind, "magic_size"); eq(j.params.sqrb_magic_lanes, 2)
		eq(j.params.sqrb_magic_size, 3); eq(#j.search.cands, 5)
		seen[j.params.sqrb_arm_type .. "," .. j.params.sqrb_direction] = true
	end
	for arm = 1, 6 do for dir = 1, 2 do ok(seen[arm .. "," .. dir], "arm " .. arm .. " dir " .. dir) end end
	eq(grid.SUBSET_ORDER[15], "search_magic_sizes")
	eq(#grid.expand("search_magic_sizes"), 24)
end)

test("unknown labels, axes and subsets raise", function()
	raises(function() grid.expand({ { entry = "main", radius = { "9" } } }) end, "unknown value '9'")
	raises(function() grid.expand({ { entry = "main", size = "*" } }) end, "has no axis 'size'")
	raises(function() grid.expand("nope") end, "unknown subset")
	raises(function() grid.expand({ { entry = "other" } }) end, "unknown entry")
	raises(function() grid.expand({ { entry = "channel", radius = { "20" } } }) end, "has no axis 'radius'")
end)

-- inOrder: the axes are in .con.lua param order (main). Magic is matched by key: its lanes axis
-- is appended last (replay keys) though the .con.lua shows it after the arm road.
-- Main: in order up to the through road, which is appended last (replay keys). Pseudo axes
-- (the interchange's year) are not .con.lua params.
-- 2026-10-09 (user: every size menu defaults to its smallest value): these .con.lua defaults moved
-- to 1, but the probe axes keep their old defaults, because recorded subsets, replay keys and the
-- "default block" / smoke tests expand omitted axes to them. Their menu default is asserted as 1.
local SMALLEST_MENU_DEFAULT = { sqrb_radius = true, sqrb_magic_size = true, sqrb_ix_radius = true, sqrb_hx_scale = true }

-- Params the probe never sweeps (no axis; combos build their default): Structure (sqrb_structure,
-- every entry's last param, default Embankment = the result the probe always measured; the bridge
-- probe has its own Probe structure). Appending an axis would change every recorded replay key.
local NOT_SWEPT = { sqrb_structure = true }

local function checkAxes(axes, con, keys, inOrder)
	local byKey = {}
	local params = {}
	for _, p in ipairs(con.params) do
		if not NOT_SWEPT[p.key] then byKey[p.key] = p; params[#params + 1] = p end
	end
	con = { params = params }
	local real = 0
	for _, axis in ipairs(axes) do if not axis.pseudo then real = real + 1 end end
	eq(real, #con.params, "axis count")
	for i, axis in ipairs(axes) do
		if axis.pseudo then goto continue end
		-- Phase 7c3: a full-range axis whose .con.lua param is a row of presets on another key
		local want = axis.menu and axis.menu.key or axis.param
		local p = inOrder and i < #axes and con.params[i] or byKey[want]
		if inOrder and i < #axes and want ~= p.key then p = byKey[want] end
		ok(p ~= nil, "axis " .. axis.key .. " has no .con.lua param")
		eq(want, p.key, "axis " .. axis.key .. " order")
		if SMALLEST_MENU_DEFAULT[axis.param] then
			eq(p.defaultIndex, 1, "axis " .. axis.key .. ": menu default = the smallest")
		end
		if axis.menu then
			eq(#axis.menu.presets, #p.values, "axis " .. axis.key .. " presets")
			if not SMALLEST_MENU_DEFAULT[axis.param] then
				eq(axis.menu.presets[p.defaultIndex], axis.default, "axis " .. axis.key .. " default preset")
			end
			eq(byKey[axis.param], nil, "axis " .. axis.key .. ": no slider left")
		else
			eq(#axis.labels, #p.values, "axis " .. axis.key .. " values")
			if not SMALLEST_MENU_DEFAULT[axis.param] then eq(axis.default, p.defaultIndex, "axis " .. axis.key .. " default") end
		end
		::continue::
	end
	for name, key in pairs(keys) do
		local found = false
		for _, axis in ipairs(axes) do if axis.param == key then found = true end end
		ok(found, "PARAM_KEYS." .. name .. " (" .. key .. ") has no axis")
	end
end

-- The main axes are in REPLAY KEY order, which is frozen: every recorded `m:` key (probe_*.csv,
-- tools/gen_roundabouts_tuning.py MAIN_ORDER, tests/square_roundabouts/verdicts.lua MAIN_ORDER)
-- has Through the centre before the arm road. The .con.lua later moved "Arm road" above "Through
-- the centre" (menu order only), so the axes are matched by key, not by position.
local function tuningMainOrder()
	local f = assert(io.open(here .. "../../tools/gen_roundabouts_tuning.py", "r"))
	local src = f:read("a")
	f:close()
	local list = assert(src:match("\nMAIN_ORDER = %[([^%]]*)%]"), "MAIN_ORDER in gen_roundabouts_tuning.py")
	local out = {}
	for name in list:gmatch('"(%w+)"') do out[#out + 1] = name end
	return out
end

test("main axes match square_roundabouts.con.lua and geom.PARAM_KEYS; replay key order frozen", function()
	local rb = H.loadRoundabouts()
	checkAxes(grid.MAIN_AXES, H.loadCon("square_roundabouts.con.lua"), rb.geom.PARAM_KEYS, false)
	-- order: the replay key order of the tuning generator (geom.PARAM_KEYS names), then the
	-- through road (appended in Phase 5c)
	local order = {}
	for _, name in ipairs(tuningMainOrder()) do order[#order + 1] = rb.geom.PARAM_KEYS[name] end
	eq(#order, 11)
	order[#order + 1] = rb.geom.PARAM_KEYS.throughRoad
	eq(#grid.MAIN_AXES, #order)
	for i, axis in ipairs(grid.MAIN_AXES) do eq(axis.param, order[i], "main axis " .. i) end
	eq(grid.MAIN_AXES[6].key, "centre"); eq(grid.MAIN_AXES[7].key, "arm")
	-- labels that name a value must agree with the geometry tables
	for i, r in ipairs(rb.geom.RADII) do eq(grid.MAIN_AXES[3].labels[i], tostring(r)) end
	eq(grid.MAIN_AXES[3].menu.key, rb.geom.RADIUS_PRESET_KEY); eq(grid.MAIN_AXES[3].menu.presets, rb.geom.RADIUS_PRESETS)
	eq(#grid.MAIN_AXES[1].labels, #rb.geom.SHAPE_RATIOS)
	eq(rb.geom.SHAPE_RATIOS[5], 2.0) -- "oval2"
	eq(#rb.geom.ARM_LAYOUTS[5], 6)   -- "6"
end)

test("magic axes match square_roundabouts_magic.con.lua and magic.PARAM_KEYS", function()
	local rb = H.loadRoundabouts()
	checkAxes(grid.MAGIC_AXES, H.loadCon("square_roundabouts_magic.con.lua"), rb.magic.PARAM_KEYS)
	eq(#grid.MAGIC_AXES[1].labels, #rb.magic.SIZES)
end)

test("channel and interchange axes match their .con.lua (in order) and PARAM_KEYS", function()
	local rb = H.loadRoundabouts()
	checkAxes(grid.CHANNEL_AXES, H.loadCon("square_roundabouts_channel.con.lua"), rb.channel.PARAM_KEYS, true)
	checkAxes(grid.INTERCHANGE_AXES, H.loadCon("square_roundabouts_interchange.con.lua"), rb.interchange.PARAM_KEYS, true)
	for i, r in ipairs(rb.interchange.RADII) do eq(grid.INTERCHANGE_AXES[5].labels[i], tostring(r)) end
	eq(grid.INTERCHANGE_AXES[5].menu.key, rb.interchange.RADIUS_PRESET_KEY)
	eq(grid.INTERCHANGE_AXES[5].menu.presets, rb.interchange.RADIUS_PRESETS)
	for i, r in ipairs(rb.interchange.SLIP_LENGTHS) do eq(grid.INTERCHANGE_AXES[7].labels[i], tostring(r)) end
	for i, r in ipairs(rb.channel.ARM_LENGTHS) do eq(grid.CHANNEL_AXES[6].labels[i], tostring(r)) end
	local year = grid.INTERCHANGE_AXES[#grid.INTERCHANGE_AXES]
	eq(year.pseudo, true)
	eq(rb.interchange.bridgeType(year.values[1]), rb.interchange.BRIDGE_STEEL)
	eq(rb.interchange.bridgeType(year.values[2]), rb.interchange.BRIDGE_CONCRETE)
	for _, name in ipairs(grid.ENTRY_ORDER) do ok(grid.ENTRIES[name], name) end
	local tags = {}
	for name, e in pairs(grid.ENTRIES) do
		ok(not tags[e.tag], "tag " .. e.tag .. " twice")
		tags[e.tag] = name
	end
end)

-- Phase 5e sweeps (combos)
local P5 = {
	p5_hamburger = 2 * (3 * 2 * 6 * 2 * 5),
	p5_channel = 2 * 6 * 6 * 3 * 2 * 2 + 2 * 3 * 2 * 2 * 2 * 2 + 2 * 2 * 2,
	p5_interchange = 3 * 3 * 2 * 3 * 2 + 3 * 3 * 2 * 3 * 2 + 3 * 3 * 2 * 3 + 3 * 2 + 3 * 2,
}
P5.p5_all = P5.p5_hamburger + P5.p5_channel + P5.p5_interchange

test("Phase 5e sweeps: sizes, unique keys, what each covers", function()
	for name, n in pairs(P5) do
		local combos = grid.expand(name)
		eq(#combos, n, name)
		eq(grid.size(name), n, name .. " (size)")
		local keys = {}
		for _, c in ipairs(combos) do
			ok(not keys[c.key], name .. ": duplicate " .. c.key)
			keys[c.key] = true
			ok(c.search == nil, name .. ": a sweep")
		end
	end
	-- hamburger: Road and Road + traffic lights, never Same as arms or the arm road itself
	local seen = {}
	for _, c in ipairs(grid.expand("p5_hamburger")) do
		local l = grid.labelsByKey(c.entry, c)
		ok(l.centre == "road" or l.centre == "lights", c.key)
		ok(l.through ~= "same" and l.through ~= l.arm, c.key)
		ok(l.radius == "8" or l.radius == "20", c.key)
		seen[l.arm .. ">" .. l.through] = true
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	eq(n, 10)
	-- interchange: both bridge types, every layout x highway x level x lanes, at the 15 m slider
	local years, sets = {}, {}
	for _, c in ipairs(grid.expand("p5_interchange")) do
		local l = grid.labelsByKey(c.entry, c)
		eq(l.radius, "15")
		years[l.year] = true
		sets[l.layout .. l.highway .. l.level .. l.lanes] = true
	end
	ok(years["1969"] and years["2020"], "both years")
	n = 0
	for _ in pairs(sets) do n = n + 1 end
	eq(n, 54)
end)

-- Phase 5f sweep (combos): the 4-lane two-bridge interchange, 2:1 splitter ovals, the channel with
-- both slip lane sets and traffic sides, the hamburger sweep again
test("Phase 5f sweep: size, unique keys, what it covers", function()
	local n = 3 * 2 * 2 * 2 * 2 * 2 + 3 * 2 * 2 * 2 + 2 * 6 * 6 * 2 * 2 * 2 + P5.p5_hamburger
	local combos = grid.expand("p5f_all")
	eq(#combos, n)
	eq(grid.size("p5f_all"), n)
	local keys, by = {}, {}
	for _, c in ipairs(combos) do
		ok(not keys[c.key], "duplicate " .. c.key)
		keys[c.key] = true
		ok(c.search == nil, "a sweep")
		by[c.entry] = (by[c.entry] or 0) + 1
		local l = grid.labelsByKey(c.entry, c)
		if c.entry == "interchange" then eq(l.layout, "two_bridge"); eq(l.lanes, "4") end
		if c.entry == "channel" then ok(l.slips ~= "none", c.key) end
	end
	eq(by.channel, 576); eq(by.interchange, 96); eq(by.main, 24 + P5.p5_hamburger)
end)

-- Phase 5g sweep: the 81 retuned channel combos x both slip lane sets x both traffic sides, and
-- the 4-lane two-bridge ring over every cross road / slip road / year p5_all and p5f_all used
test("Phase 5g verify sweep: size, unique keys, what it covers", function()
	local combos = grid.expand("p5g_verify")
	eq(#combos, 81 * 2 * 2 + 3 * 2 * 2 * 3 * 2 * 2)
	eq(grid.size("p5g_verify"), #combos)
	local keys, by, bases = {}, {}, {}
	for _, c in ipairs(combos) do
		ok(not keys[c.key], "duplicate " .. c.key)
		keys[c.key] = true
		ok(c.search == nil, "a sweep")
		by[c.entry] = (by[c.entry] or 0) + 1
		local l = grid.labelsByKey(c.entry, c)
		if c.entry == "interchange" then eq(l.layout, "two_bridge"); eq(l.lanes, "4") end
		if c.entry == "channel" then
			ok(l.slips == "near" or l.slips == "main", c.key)
			bases[l.layout .. "," .. l.main .. "," .. l.side .. "," .. l.splitter] = true
		end
	end
	eq(by.channel, 324); eq(by.interchange, 144)
	-- exactly the base combos p5f_search searched
	local searched = {}
	for _, j in ipairs(grid.expand("p5f_search")) do
		if j.entry == "channel" then
			local l = grid.labelsByKey(j.entry, j)
			searched[l.layout .. "," .. l.main .. "," .. l.side .. "," .. l.splitter] = true
		end
	end
	eq(bases, searched)
end)

-- Phase 7d: the Highway Interchange; since Phase 7c2 one entry per type (no Type param: the type
-- axis picks the file, ENTRIES.highway.files, and still rides in the params as sqrb_hx_type)
-- Phase 7c3: three entries; the parclos' Layout button row picks the type (ENTRIES.highway.layouts)
local HX_IDS = { "parclo", "parclo", "parclo2", "parclo2", "parclo2", "diamond" }
test("highway axes match the three square_roundabouts_highway_<id>.con.lua (in order), hx.PARAM_KEYS and hx's tables", function()
	local rb = H.loadRoundabouts()
	local hx = rb.highway
	eq(grid.HIGHWAY_AXES[1].key, "type"); eq(grid.HIGHWAY_AXES[1].param, hx.PARAM_KEYS.type)
	local axes, keys = {}, {}
	for i = 2, #grid.HIGHWAY_AXES do axes[#axes + 1] = grid.HIGHWAY_AXES[i] end
	for name, key in pairs(hx.PARAM_KEYS) do if name ~= "type" then keys[name] = key end end
	local e = grid.ENTRIES.highway
	eq(#e.files, #hx.TYPES); eq(e.fileAxis, hx.PARAM_KEYS.type); eq(e.file, e.files[1])
	eq(e.layoutKey, hx.LAYOUT_KEY)
	for t, id in ipairs(HX_IDS) do
		eq(e.files[t], "infrastructure/street_construction/square_roundabouts_highway_" .. id .. ".con", id)
		local con = H.loadCon("square_roundabouts_highway_" .. id .. ".con.lua")
		local types = con.updateScript.params.types
		-- the Layout button the probe sends picks this type in game (hx.specFor)
		eq(types[e.layouts[t] or 1], t, id .. ": layout " .. tostring(e.layouts[t]))
		local cp = { [hx.PARAM_KEYS.type] = t }
		if e.layouts[t] then cp[hx.LAYOUT_KEY] = e.layouts[t] end
		eq(hx.specFor(con.updateScript.params, cp).type, t, id .. ": specFor")
		-- the Layout row (when there is one) is first and has no axis (the type axis covers it)
		local params = {}
		for _, p in ipairs(con.params) do
			ok(p.key ~= hx.PARAM_KEYS.type, id .. ": no Type param")
			if p.key == hx.LAYOUT_KEY then eq(#p.values, #types)
			elseif not NOT_SWEPT[p.key] then params[#params + 1] = p end
		end
		eq(#params, #con.params - (#types > 1 and 1 or 0) - 1)
		local view = { params = params }
		checkAxes(axes, view, keys, true)
		for i, p in ipairs(params) do eq(axes[i].param, p.key, id .. " highway axis " .. (i + 1)) end
	end
	local A = {}
	for _, axis in ipairs(grid.HIGHWAY_AXES) do A[axis.key] = axis end
	for i, t in ipairs(hx.TYPES) do eq(A.type.labels[i]:lower(), t.name:lower()) end
	eq(A.size.labels, { "small", "medium", "large" }); eq(#A.size.labels, #hx.LOOP_RADII); eq(#A.size.labels, #hx.TERMINAL_DISTANCES)
	for i, v in ipairs(hx.RAMP_EXTRAS) do eq(A.ramp.labels[i], tostring(v)) end
	for i, v in ipairs(hx.ARM_LENGTHS) do eq(A.armlen.labels[i], tostring(v)) end
	eq(#A.highway.labels, #rb.ramps.HIGHWAYS)
	eq(A.level.labels[hx.LEVEL_ROAD_OVER], "road_over"); eq(A.level.labels[hx.LEVEL_HIGHWAY_OVER], "hw_over")
	-- the highway / cross / direction keys are shared with the Roundabout Interchange:
	-- same labels
	local IX = {}
	for _, axis in ipairs(grid.INTERCHANGE_AXES) do IX[axis.param] = axis end
	for _, axis in ipairs(grid.HIGHWAY_AXES) do
		if IX[axis.param] then eq(axis.labels, IX[axis.param].labels, axis.key) end
	end
	local year = A.year
	eq(year.pseudo, true)
	eq(rb.ramps.bridgeType(year.values[1]), rb.ramps.bridgeType(1969))
	ok(rb.ramps.bridgeType(year.values[1]) ~= rb.ramps.bridgeType(year.values[2]), "steel / concrete")
	eq(grid.ENTRIES.highway.tag, "h")
	eq(grid.ENTRY_ORDER[5], "highway")
	-- Phase 8: the DEV Bridge probe entries resolve last, in this mod
	eq(grid.ENTRY_ORDER[6], "bridge_main"); eq(grid.ENTRY_ORDER[7], "bridge_ix")
	eq(grid.ENTRIES.bridge_main.mod, "square_roundabouts_probe")
end)

-- Phase 7e: the large-highway parclos, highway over road (since 7c2 Scale Small / Medium = 25 / 45 m
-- loops; hx.BRIDGE_PIECE): every cross road x year, the longer ramps, left-hand traffic
test("Phase 7e verify sweep p7_verify: size, unique keys, what it covers", function()
	local combos = grid.expand("p7_verify")
	local n = 5 * 2 * 6 * 2 + 5 * 2 * 2 + 5 * 2
	eq(#combos, n); eq(n, 150)
	eq(grid.size("p7_verify"), n)
	local keys = {}
	for _, c in ipairs(combos) do
		ok(not keys[c.key], "duplicate " .. c.key)
		keys[c.key] = true
		eq(c.entry, "highway"); ok(c.search == nil, "a sweep")
		local l = grid.labelsByKey(c.entry, c)
		eq(l.highway, "large", c.key); eq(l.level, "hw_over", c.key)
		ok(l.size == "small" or l.size == "medium", c.key)
		ok(l.type ~= "diamond", c.key)
	end
	-- every p7_hx_all combo of that kind is in it
	local covered = 0
	for _, c in ipairs(grid.expand("p7_hx_all")) do
		local l = grid.labelsByKey(c.entry, c)
		if l.highway == "large" and l.level == "hw_over" and l.type ~= "diamond" and (l.size == "small" or l.size == "medium") then
			ok(keys[c.key], "not re-run: " .. c.key)
			covered = covered + 1
		end
	end
	eq(covered, 5 * 2 * 3 * 2 + 5) -- the shortest-ramp sweep, plus +60 m ramps at Scale Medium
end)

test("Phase 7d sweep p7_hx_all: size, unique keys, what it covers; smoke has the highway default", function()
	local combos = grid.expand("p7_hx_all")
	local n = 6 * 3 * 2 * 3 * 3 * 2 + 6 * 3 * 2 + 6 * 2
	eq(#combos, n); eq(n, 696)
	eq(grid.size("p7_hx_all"), n)
	local keys, sets, years, ramp60, lht = {}, {}, {}, 0, 0
	for _, c in ipairs(combos) do
		ok(not keys[c.key], "duplicate " .. c.key)
		keys[c.key] = true
		eq(c.entry, "highway"); ok(c.search == nil, "a sweep")
		ok(c.key:sub(1, 2) == "h:", c.key)
		local l = grid.labelsByKey(c.entry, c)
		years[l.year] = true
		if l.ramp == "60" then ramp60 = ramp60 + 1 end
		if l.dir == "lht" then lht = lht + 1 end
		if l.ramp == "0" and l.dir == "rht" then
			sets[l.type .. l.highway .. l.level .. l.size .. l.cross .. l.year] = true
			ok(l.cross == "town_m" or l.cross == "town_l" or l.cross == "country_l", c.key)
		end
	end
	local nsets = 0
	for _ in pairs(sets) do nsets = nsets + 1 end
	eq(nsets, 648)
	ok(years["1969"] and years["2020"], "both years")
	eq(ramp60, 36); eq(lht, 12)
	local smoke = grid.expand("smoke")
	local found = false
	for _, c in ipairs(smoke) do if c.key == "h:1,2,1,2,2,1,1,1,2" then found = true end end
	ok(found, "smoke: the highway default")
end)

-- Phase 7e fix-up (INTERCHANGES.md "Phase 7e fix-up: placement in game"): p7_spot places the user's
-- refused combo, the highway default and the diamond at one real spot under every rotation x
-- context, plus origin shifts; the Roundabout Interchange is the control.
test("Phase 7e fix-up spot run p7_spot: combos, places, labels, R line fields", function()
	local combos = grid.expand("p7_spot")
	local per = #grid.SPOT_ROTS * #grid.SPOT_CONTEXTS + 2 * #grid.SPOT_SHIFTS
	eq(per, 34)
	eq(#combos, 3 * per + #grid.SPOT_CONTROL)
	eq(grid.size("p7_spot"), #combos)
	local byKey, ids = {}, {}
	for _, c in ipairs(combos) do
		ok(c.place, c.key)
		local id = c.key .. "@" .. grid.placeLabel(c.place)
		ok(not ids[id], "duplicate " .. id)
		ids[id] = true
		byKey[c.key] = (byKey[c.key] or 0) + 1
		ok(c.place.ctx == "none" or c.place.ctx == "player" or c.place.ctx == "terrain" or c.place.ctx == "full", id)
	end
	eq(byKey["h:2,1,1,6,1,1,1,1,2"], per, "the 7e report's B4 small / road over / country large / 25 m loops")
	eq(byKey["h:1,2,1,2,2,1,1,1,2"], per, "the highway default")
	eq(byKey["h:6,2,1,2,2,1,1,1,2"], per, "the diamond")
	eq(byKey["x:1,2,1,2,2,2,2,1,1,1,2"], #grid.SPOT_CONTROL, "the interchange control")
	eq(grid.placeLabel({ rot = 0.5, ctx = "full", dx = 20, dy = 0 }), "r0.50_full_20_0")
	local _, f = H.parseLine(grid.resultLine(1, 1, combos[1], { ok = false, messages = { "Construction Not Possible" } }))
	eq(f.rot, "0"); eq(f.ctx, "none"); eq(f.dx, "0"); eq(f.dy, "0"); eq(f.key, "h:2,1,1,6,1,1,1,1,2")
	-- every other subset stays without places (their R lines are unchanged); p7_hx_scale (7d2) places
	-- only its rotation block (its own test); p8_bridge (Phase 8) places every combo (test_bridge.lua)
	for _, name in ipairs(grid.SUBSET_ORDER) do
		if name:sub(1, 7) ~= "p7_spot" and name ~= "p7_hx_scale" and name ~= "p8_bridge" then
			for _, c in ipairs(grid.expand(name)) do ok(c.place == nil, name) end
		end
	end
end)

test("Phase 7e fix-up p7_spot2: B4 at 0 degrees, 0-8 m shifts in 0.5 m steps, contexts none / full", function()
	local combos = grid.expand("p7_spot2")
	eq(#combos, 17 * 17 * 2); eq(grid.size("p7_spot2"), #combos)
	local ids, maxD = {}, 0
	for _, c in ipairs(combos) do
		eq(c.key, "h:2,1,1,6,1,1,1,1,2"); eq(c.place.rot, 0)
		ok(c.place.ctx == "none" or c.place.ctx == "full")
		ok(c.place.dx * 2 == math.floor(c.place.dx * 2) and c.place.dy >= 0)
		maxD = math.max(maxD, c.place.dx, c.place.dy)
		local id = grid.placeLabel(c.place)
		ok(not ids[id], id); ids[id] = true
	end
	eq(maxD, 8)
end)


-- Phase 7d2 (INTERCHANGES.md "Phase 7d2 notes"): Scale Small / Medium / Large on the three highway
-- entries at the builder's 0 degree transf, the length extremes at Large, rotations 90 / 180.
test("Phase 7d2 p7_hx_scale: size, unique ids, 0-degree coverage, extremes at Large, rotations", function()
	local combos = grid.expand("p7_hx_scale")
	local n0 = 6 * 3 * 3 * 2 * 2 * 2 * 2
	local nExt = 6 * 3 * 2 * 3 * 2
	local nRot = 6 * 2 * 3 * 2 * #grid.HX_SCALE_ROTS
	eq(n0, 864); eq(nExt, 216); eq(nRot, 144)
	eq(#combos, n0 + nExt + nRot); eq(grid.size("p7_hx_scale"), #combos)
	ok(#combos <= 1500, "about 1500 calls at most")
	eq(grid.maxCalls(combos), #combos)
	local ids, flat, sets, ext, rots = {}, {}, {}, {}, {}
	for _, c in ipairs(combos) do
		eq(c.entry, "highway"); ok(c.search == nil, "a sweep")
		local id = c.key .. (c.place and ("@" .. grid.placeLabel(c.place)) or "")
		ok(not ids[id], "duplicate " .. id); ids[id] = true
		local l = grid.labelsByKey(c.entry, c)
		if c.place then
			eq(c.place.ctx, "none"); eq(c.place.dx, 0); eq(c.place.dy, 0)
			ok(c.place.rot == 90 or c.place.rot == 180, id)
			eq(l.highway, "medium"); eq(l.cross, "town_m"); eq(l.year, "2020"); eq(l.ramp, "0"); eq(l.armlen, "30")
			rots[c.place.rot] = (rots[c.place.rot] or 0) + 1
		else
			ok(not flat[c.key], "duplicate key " .. c.key); flat[c.key] = true
			if l.ramp == "0" and l.armlen == "30" then
				ok(l.cross == "town_m" or l.cross == "country_l", c.key)
				sets[l.type .. l.size .. l.highway .. l.level .. l.cross .. l.dir .. l.year] = true
			else
				eq(l.size, "large", c.key); eq(l.cross, "country_l", c.key); eq(l.year, "2020", c.key)
				ext[l.ramp .. "/" .. l.armlen] = (ext[l.ramp .. "/" .. l.armlen] or 0) + 1
			end
		end
	end
	local nsets = 0
	for _ in pairs(sets) do nsets = nsets + 1 end
	eq(nsets, n0)
	eq(ext["60/30"], 72); eq(ext["60/60"], 72); eq(ext["0/60"], 72)
	eq(rots[90], 72); eq(rots[180], 72)
	-- every Layout button of the three entries: the types map to the entries' files and Layout indices
	local files = {}
	for _, c in ipairs(combos) do
		local t = c.params[grid.ENTRIES.highway.fileAxis]
		files[grid.ENTRIES.highway.files[t] .. "#" .. tostring(grid.ENTRIES.highway.layouts[t])] = true
	end
	local nf = 0
	for _ in pairs(files) do nf = nf + 1 end
	eq(nf, 6)
end)

test("Phase 7d2 p7_presets: the released entries' button rows, preset keys sent, both sides, 0 degrees", function()
	local combos = grid.expand("p7_presets")
	eq(#combos, 30 + 24 + 24 + 10); eq(grid.size("p7_presets"), #combos)
	local per, radii, chXlht = {}, {}, 0
	for _, c in ipairs(combos) do
		ok(c.place == nil and c.search == nil, c.key)
		per[c.entry] = (per[c.entry] or 0) + 1
		local l = grid.labelsByKey(c.entry, c)
		if c.entry == "main" then
			local p = c.params.sqrb_radius_size
			eq(grid.MAIN_AXES[3].menu.presets[p], c.params.sqrb_radius, c.key)
			radii[l.radius] = true
		elseif c.entry == "interchange" then
			local p = c.params.sqrb_ix_radius_size
			eq(grid.INTERCHANGE_AXES[5].menu.presets[p], c.params.sqrb_ix_radius, c.key)
			radii["x" .. l.radius] = true
		else
			eq(c.params.sqrb_radius_size, nil); eq(c.params.sqrb_ix_radius_size, nil)
			if c.entry == "channel" and l.layout == "X" and l.dir == "lht" then chXlht = chXlht + 1 end
		end
	end
	eq(per.main, 30); eq(per.interchange, 24); eq(per.channel, 24); eq(per.magic, 10)
	for _, r in ipairs({ "10", "15", "20", "35", "60", "x15", "x20", "x30", "x45" }) do ok(radii[r], r) end
	eq(chXlht, 6)
	-- older subsets never send a preset key (their replay keys build from the full-range index)
	for _, name in ipairs(grid.SUBSET_ORDER) do
		if name ~= "p7_presets" then
			for _, c in ipairs(grid.expand(name)) do
				ok(c.params.sqrb_radius_size == nil and c.params.sqrb_ix_radius_size == nil, name)
			end
		end
	end
	-- a value that is not a preset raises
	local okCall, err = pcall(grid.expand, { { entry = "main", radius = { "12" }, menu = true } })
	ok(not okCall and tostring(err):find("not a menu preset", 1, true), tostring(err))
end)

-- Phase 7e2 (INTERCHANGES.md "Phase 7e2 notes"): every combo p7_hx_scale refused, plus 30 capped /
-- unprobed ones (town medium, +30 m ramps, 45 m arms, right-hand, 2020), at the builder's 0 degrees.
test("Phase 7e2 p7_hx_scale_verify: size, unique keys, covers every p7_hx_scale refusal", function()
	local combos = grid.expand("p7_hx_scale_verify")
	local nCore, nRamp, nArm, nMid = 5 * 2 * 2 * 2, 5 * 3 * 2 * 2 * 2, 5 * 3 * 2, 5 * 3 * 2
	eq(#combos, nCore + nRamp + nArm + nMid); eq(#combos, 220); eq(grid.size("p7_hx_scale_verify"), 220)
	local keys = {}
	for _, c in ipairs(combos) do
		eq(c.entry, "highway"); ok(c.search == nil and c.place == nil, c.key)
		ok(not keys[c.key], "duplicate " .. c.key); keys[c.key] = true
		local l = grid.labelsByKey(c.entry, c)
		eq(l.size, "large", c.key); ok(l.type ~= "diamond", c.key)
	end
	-- the user's p7_hx_scale run: every refused key is in the subset
	local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
	local f = io.open(here .. "../../plans/square_roundabouts/probe_p7_hx_scale.csv", "r")
	ok(f, "plans/square_roundabouts/probe_p7_hx_scale.csv (make probe-report)")
	if f then
		local header, refused, covered = nil, 0, 0
		for line in f:lines() do
			if not header then
				header = {}
				for name in line:gmatch("[^,]+") do header[#header + 1] = name end
			else
				local okv = line:match("^[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,[^,]*,([^,]*),")
				local key = line:match('"(h:[%d,]+)"')
				if okv == "false" and key then
					refused = refused + 1
					if keys[key] then covered = covered + 1 else ok(false, "refused key not in the subset: " .. key) end
				end
			end
		end
		f:close()
		eq(header[13], "ok"); eq(refused, 190); eq(covered, 190)
	end
end)
