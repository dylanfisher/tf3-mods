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
local function checkAxes(axes, con, keys, inOrder)
	local byKey = {}
	for _, p in ipairs(con.params) do byKey[p.key] = p end
	local real = 0
	for _, axis in ipairs(axes) do if not axis.pseudo then real = real + 1 end end
	eq(real, #con.params, "axis count")
	for i, axis in ipairs(axes) do
		if axis.pseudo then goto continue end
		local p = inOrder and i < #axes and con.params[i] or byKey[axis.param]
		if inOrder and i < #axes and axis.param ~= p.key then p = byKey[axis.param] end
		ok(p ~= nil, "axis " .. axis.key .. " has no .con.lua param")
		eq(axis.param, p.key, "axis " .. axis.key .. " order")
		eq(#axis.labels, #p.values, "axis " .. axis.key .. " values")
		eq(axis.default, p.defaultIndex, "axis " .. axis.key .. " default")
		::continue::
	end
	for name, key in pairs(keys) do
		local found = false
		for _, axis in ipairs(axes) do if axis.param == key then found = true end end
		ok(found, "PARAM_KEYS." .. name .. " (" .. key .. ") has no axis")
	end
end

test("main axes match square_roundabouts.con.lua and geom.PARAM_KEYS", function()
	local rb = H.loadRoundabouts()
	checkAxes(grid.MAIN_AXES, H.loadCon("square_roundabouts.con.lua"), rb.geom.PARAM_KEYS, true)
	-- order: the .con.lua order without the through road, which comes last
	local con = H.loadCon("square_roundabouts.con.lua")
	local order = {}
	for _, p in ipairs(con.params) do if p.key ~= "sqrb_through_road" then order[#order + 1] = p.key end end
	order[#order + 1] = "sqrb_through_road"
	for i, axis in ipairs(grid.MAIN_AXES) do eq(axis.param, order[i], "main axis " .. i) end
	-- labels that name a value must agree with the geometry tables
	for i, r in ipairs(rb.geom.RADII) do eq(grid.MAIN_AXES[3].labels[i], tostring(r)) end
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
