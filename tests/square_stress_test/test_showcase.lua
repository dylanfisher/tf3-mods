-- Showcase (Towns tab, plans/square_stress_test/SHOWCASE.md "Showcase v2"): stress_logic's seeded PRNG,
-- param draws (checked against the square_roundabouts construction files and our plain crossing), arm
-- directions, reach estimates, the group layout with its A/B twins and zones, bus routes, and
-- stress_junctions.tl jn.buildShowcase against a fake api: towns first, then every group's junction
-- (twins back to back), one settle, the reads (zone lines) and one town link per arm.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl"

local function allTypes()
	local out = {}
	for _, t in ipairs(logic.SHOWCASE_IX_TYPES) do out[#out + 1] = t end
	for _, t in ipairs(logic.SHOWCASE_RB_TYPES) do out[#out + 1] = t end
	for _, t in ipairs(logic.SHOWCASE_PLAIN_TYPES) do out[#out + 1] = t end
	for _, t in ipairs(logic.LIGHTS_SHAPES) do out[#out + 1] = t end
	return out
end

---------------------------------------------------------------------------
-- PRNG

test("rng: the minimal standard sequence, exact; same seed same sequence", function()
	local r = logic.newRng(1)
	-- C++ std::minstd_rand from seed 1
	eq({ logic.rngNext(r), logic.rngNext(r), logic.rngNext(r), logic.rngNext(r), logic.rngNext(r) },
		{ 48271, 182605794, 1291394886, 1914720637, 2078669041 })
	local a, b = logic.newRng(424242), logic.newRng(424242)
	for _ = 1, 1000 do eq(logic.rngNext(a), logic.rngNext(b)) end
	local c, d = logic.newRng(1), logic.newRng(2)
	ok(logic.rngNext(c) ~= logic.rngNext(d))
	-- 0, negatives and fractions still give a valid state
	for _, s in ipairs({ 0, -5, 2.7, 2147483647, 1e12 }) do
		local g = logic.newRng(s)
		local v = logic.rngNext(g)
		ok(v >= 1 and v < 2147483647 and v == math.floor(v), tostring(s))
	end
end)

test("rngInt: 1..n, every value reached; seeds 1..999999", function()
	local r = logic.newRng(7)
	local seen = {}
	for _ = 1, 600 do
		local v = logic.rngInt(r, 6)
		ok(v >= 1 and v <= 6 and v == math.floor(v))
		seen[v] = true
	end
	for v = 1, 6 do ok(seen[v], "value " .. v) end
	eq(logic.rngInt(r, 1), 1)
	for _, c in ipairs({ 0, 1, 999998, 999999, 1e15 + 3, -12 }) do
		local s = logic.showcaseSeed(c)
		ok(s >= 1 and s <= 999999, tostring(c))
	end
end)

---------------------------------------------------------------------------
-- Types and draws against the square_roundabouts construction files

local RB_DIR = "mods/square_roundabouts/content/infrastructure/street_construction/"

--- key -> number of values of every param of a square_roundabouts .con.lua (nil when not run from the
--- repo root). Its ug_require'd modules are loaded from the files as the game would.
local function conParams(file)
	if file == logic.SHOWCASE_PLAIN_FILE then
		-- our own crossing construction
		local h = assert(io.open("mods/square_stress_test/content/infrastructure/street_construction/" .. file .. ".lua"))
		local src = h:read("a")
		h:close()
		local env = setmetatable({ ug_require = ug_require }, { __index = _G })
		assert(load(src, "@" .. file, "t", env))()
		local out, labels = {}, {}
		for _, p in ipairs(env.data().params) do out[p.key] = #p.values labels[p.key] = p.values end
		return out, labels
	end
	local f = io.open(RB_DIR .. file .. ".lua")
	if f == nil then return nil end
	f:close()
	local cache = {}
	local env
	local function req(path)
		local rel = path:match("^square_roundabouts::/(.*)$")
		assert(rel, path)
		if cache[rel] == nil then
			local h = assert(io.open("mods/square_roundabouts/content/" .. rel))
			local src = h:read("a")
			h:close()
			cache[rel] = assert(load(src, "@" .. rel, "t", env))()
		end
		return cache[rel]
	end
	env = setmetatable({ ug_require = req, _ = function(s) return s end }, { __index = _G })
	local h = assert(io.open(RB_DIR .. file .. ".lua"))
	local src = h:read("a")
	h:close()
	assert(load(src, "@" .. file, "t", env))()
	local con = env.data()
	local out, labels = {}, {}
	for _, p in ipairs(con.params) do out[p.key] = #p.values labels[p.key] = p.values end
	return out, labels
end

test("types: every key a param of its construction, every value one of its indices", function()
	local checked = 0
	for _, t in ipairs(allTypes()) do
		local counts = conParams(t.file)
		ok(counts ~= nil, "square_roundabouts' " .. t.file .. ".lua not found (run from the repo root: make test)")
		if counts == nil then return end
		for k, v in pairs(t.fixed) do
			ok(counts[k] ~= nil, t.id .. ": fixed " .. k)
			ok(v >= 1 and v <= (counts[k] or 0), t.id .. ": " .. k .. "=" .. v)
		end
		for _, r in ipairs(t.ranges) do
			ok(counts[r.key] ~= nil, t.id .. ": " .. r.key)
			for _, v in ipairs(r.values) do
				ok(v >= 1 and v <= (counts[r.key] or 0) and v == math.floor(v), t.id .. ": " .. r.key .. "=" .. v)
			end
			checked = checked + 1
		end
		if t.armKey then eq(counts[t.armKey], 6, t.id .. " arm road") end
		if t.kind == "ix" then eq(t.armKey, "sqrb_ix_cross", t.id .. ": the cross road is the arm road (Country large in the layout)") end
		-- right-hand traffic only: Direction / Traffic side is never drawn
		for _, r in ipairs(t.ranges) do ok(r.key ~= "sqrb_direction", t.id) end
	end
	ok(checked > 40)
	-- Arms "None" (6) and "Through the centre" on plain rings are never drawn
	for _, t in ipairs(logic.SHOWCASE_RB_TYPES) do
		for _, r in ipairs(t.ranges) do
			if r.key == "sqrb_arms" then for _, v in ipairs(r.values) do ok(v <= 5, t.id) end end
		end
	end
end)

test("types: every interchange and roundabout file of the collection and the plain crossing, ids unique", function()
	local files, ids = {}, {}
	for _, t in ipairs(allTypes()) do
		files[t.file] = true
		ok(not ids[t.id], t.id)
		ids[t.id] = true
		ok(t.kind == "ix" or t.kind == "rb" or t.kind == "plain")
		eq(logic.showcaseTypes(t.kind)[1].kind, t.kind)
	end
	for _, f in ipairs({ "square_roundabouts.con", "square_roundabouts_magic.con", "square_roundabouts_channel.con",
		"square_roundabouts_interchange.con", "square_roundabouts_highway_parclo.con", "square_roundabouts_highway_parclo2.con",
		"square_roundabouts_highway_diamond.con", "square_stress_test_crossing.con" }) do
		ok(files[f], f)
	end
end)

test("showcaseDraw: fixed params kept, every range value drawn over many seeds, arm road as asked", function()
	for _, t in ipairs(allTypes()) do
		local seen = {}
		local rng = logic.newRng(99)
		for _ = 1, 400 do
			local c = logic.showcaseDraw(rng, t, t.armKey and 6 or nil)
			eq(c.id, t.id)
			eq(c.file, t.file)
			for k, v in pairs(t.fixed) do eq(c.params[k], v) end
			for _, r in ipairs(t.ranges) do
				local v = c.params[r.key]
				local okV = false
				for _, w in ipairs(r.values) do if w == v then okV = true end end
				ok(okV, t.id .. " " .. r.key .. "=" .. tostring(v))
				seen[r.key .. "=" .. v] = true
			end
			if t.armKey then eq(c.params[t.armKey], 6) end
		end
		for _, r in ipairs(t.ranges) do
			for _, w in ipairs(r.values) do ok(seen[r.key .. "=" .. w], t.id .. " never drew " .. r.key .. "=" .. w) end
		end
		-- groups draw the arm road too
		if t.armKey then
			local roads = {}
			for _ = 1, 200 do roads[logic.showcaseDraw(rng, t, nil).params[t.armKey]] = true end
			for v = 1, 6 do ok(roads[v], t.id .. " arm road " .. v) end
		end
	end
	-- the same seed draws the same params
	local a = logic.showcaseDraw(logic.newRng(5), logic.SHOWCASE_RB_TYPES[1], nil)
	local b = logic.showcaseDraw(logic.newRng(5), logic.SHOWCASE_RB_TYPES[1], nil)
	eq(a.params, b.params)
	eq(logic.showcaseParamText({ params = { b = 2, a = 1.5 } }), "a=1.5 b=2")
end)

test("showcaseArms: ring layouts, Magic's five, Channelized T / X, interchanges' four, plain crossings by angle", function()
	local function arms(file, params) return logic.showcaseArms({ file = file, params = params }) end
	eq(arms("square_roundabouts.con", { sqrb_arms = 1 }), { 0, 90, 180 })
	eq(arms("square_roundabouts.con", { sqrb_arms = 2 }), { 90, 210, 330 })
	eq(arms("square_roundabouts.con", { sqrb_arms = 4 }), { 18, 90, 162, 234, 306 })
	eq(#arms("square_roundabouts.con", { sqrb_arms = 5 }), 6)
	eq(arms("square_roundabouts_magic.con", { sqrb_magic_size = 1 }), { 18, 90, 162, 234, 306 })
	eq(arms("square_roundabouts_channel.con", { sqrb_ch_layout = 1 }), { 0, 90, 180 })
	eq(arms("square_roundabouts_channel.con", { sqrb_ch_layout = 2 }), { 0, 90, 180, 270 })
	eq(arms("square_roundabouts_interchange.con", { sqrb_ix_layout = 1, sqrb_ix_highway = 2 }), { 0, 90, 180, 270 })
	eq(arms("square_roundabouts_highway_diamond.con", { sqrb_ix_highway = 1, sqrb_hx_scale = 2 }), { 0, 90, 180, 270 })
	eq(arms(logic.SHOWCASE_PLAIN_FILE, { sqst_x_shape = 1, sqst_x_angle = 2 }), { 0, 60, 180, 240 })
	eq(arms(logic.SHOWCASE_PLAIN_FILE, { sqst_x_shape = 2, sqst_x_angle = 5 }), { 0, 120, 180 })
	eq(arms(logic.SHOWCASE_PLAIN_FILE, { sqst_x_shape = 1 }), { 0, 90, 180, 270 })
	eq(arms("nope.con", {}), nil)
	-- the angles are the crossing construction's
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	eq(logic.SHOWCASE_PLAIN_ANGLES, cross.ANGLES)
	-- a one-way side road: its two arms (X only)
	eq(logic.showcaseOneWay({ params = { sqst_x_shape = 1, sqst_x_angle = 4, sqst_x_side = 7 } }), { [2] = true, [4] = true })
	eq(logic.showcaseOneWay({ params = { sqst_x_shape = 1, sqst_x_angle = 2, sqst_x_side = 8 } }), { [2] = true, [4] = true })
	eq(logic.showcaseOneWay({ params = { sqst_x_shape = 1, sqst_x_side = 6 } }), {})
	eq(logic.showcaseOneWay({ params = { sqrb_arms = 3 } }), {})
	-- every draw has its arms at least 60 deg apart (group towns apart); T sides never one-way, a one-way
	-- X side road keeps one road on both side arms
	local rng = logic.newRng(3)
	local oneWays = 0
	for _, t in ipairs(logic.SHOWCASE_PLAIN_TYPES) do
		for _ = 1, 300 do
			local c = logic.showcaseDraw(rng, t, nil)
			if c.params.sqst_x_shape == 2 then ok(c.params.sqst_x_side <= 6) end
			if c.params.sqst_x_side >= 7 then
				oneWays = oneWays + 1
				eq(c.params.sqst_x_side2, 1)
			end
		end
	end
	ok(oneWays > 10 and oneWays < 90, "one-way side roads now and then: " .. oneWays)
	for _, t in ipairs(allTypes()) do
		for _ = 1, 50 do
			local a = logic.showcaseArms(logic.showcaseDraw(rng, t, nil))
			ok(#a >= 3, t.id)
			for k = 1, #a do
				local d = (a[k % #a + 1] - a[k]) % 360
				ok(d >= 60 - 1e-9, t.id .. " gap " .. d)
			end
		end
	end
end)

test("showcaseReach: per type and size, roundabouts grow with size, never over the band maxima", function()
	local ix = logic.showcaseReach({ file = "square_roundabouts_interchange.con", params = { sqrb_ix_highway = 1, sqrb_ix_arm_length = 1 } })
	local parclo = logic.showcaseReach({ file = "square_roundabouts_highway_parclo.con",
		params = { sqrb_ix_highway = 1, sqrb_hx_layout = 1, sqrb_hx_scale = 3, sqrb_hx_arm_length = 3 } })
	local diamond = logic.showcaseReach({ file = "square_roundabouts_highway_diamond.con",
		params = { sqrb_ix_highway = 1, sqrb_hx_scale = 3, sqrb_hx_arm_length = 3 } })
	ok(ix < diamond and diamond < parclo, ix .. " " .. diamond .. " " .. parclo)
	eq(parclo, logic.SHOWCASE_IX_R, "the largest Parclo sets the band's room")
	local small = logic.showcaseReach({ params = { sqrb_radius_size = 1, sqrb_shape = 1, sqrb_lanes = 1, sqrb_splitter = 1 } })
	local big = logic.showcaseReach({ params = { sqrb_radius_size = 5, sqrb_shape = 5, sqrb_lanes = 3, sqrb_splitter = 1 } })
	ok(small < big)
	ok(small >= 60, "arms included: " .. small)
	-- splitters and a road through the centre grow the ring (2026-10-12: the old estimate was up to 96 m short)
	ok(logic.showcaseReach({ params = { sqrb_radius_size = 1, sqrb_shape = 4, sqrb_splitter = 2 } }) > 250)
	ok(logic.showcaseReach({ params = { sqrb_radius_size = 2, sqrb_shape = 5, sqrb_splitter = 1, sqrb_centre = 2 } })
		> logic.showcaseReach({ params = { sqrb_radius_size = 2, sqrb_shape = 5, sqrb_splitter = 1, sqrb_centre = 1 } }))
	ok(logic.showcaseReach({ params = { sqrb_magic_size = 1, sqrb_magic_lanes = 2 } })
		> logic.showcaseReach({ params = { sqrb_magic_size = 1, sqrb_magic_lanes = 1 } }), "2 lanes are wider")
	local rng = logic.newRng(11)
	eq(logic.showcaseReach({ params = { sqst_x_shape = 1 } }), 88, "plain: 60 m arms + 16 m half width + 12 m")
	for _, list in ipairs({ { logic.SHOWCASE_RB_TYPES, logic.SHOWCASE_RB_MAX }, { logic.SHOWCASE_IX_TYPES, logic.SHOWCASE_IX_R },
		{ logic.SHOWCASE_PLAIN_TYPES, 88 } }) do
		for _, t in ipairs(list[1]) do
			for _ = 1, 50 do
				local r = logic.showcaseReach(logic.showcaseDraw(rng, t, nil))
				ok(r > 0 and r <= list[2], t.id .. " " .. r)
			end
		end
	end
end)

--- A square_roundabouts construction's updateFn and the captureParams the game passes it (its
--- .con's updateScript params), loaded from the repo as the game would; nil when not run from the root.
local function rbUpdateFn(file)
	local f = io.open(RB_DIR .. file .. ".lua")
	if f == nil then return nil end
	f:close()
	local function loader()
		local cache = {}
		local env
		local function req(path)
			local rel = assert(path:match("^square_roundabouts::/(.*)$"), path)
			if cache[rel] == nil then
				local h = assert(io.open("mods/square_roundabouts/content/" .. rel))
				local src = h:read("a")
				h:close()
				cache[rel] = assert(load(src, "@" .. rel, "t", env))()
			end
			return cache[rel]
		end
		env = setmetatable({ ug_require = req, _ = function(x) return x end }, { __index = _G })
		return function(name)
			local h = assert(io.open(RB_DIR .. name))
			local src = h:read("a")
			h:close()
			assert(load(src, "@" .. name, "t", env))()
			return env.data()
		end
	end
	local con = loader()(file .. ".lua")
	local script = loader()(con.updateScript.fileName:match("^(.-)@") .. ".lua")
	return script.updateFn, con.updateScript.params or {}
end

--- A road's half width by its street template (base templates; square_roundabouts ramps.HIGHWAYS).
local function halfWidth(t)
	t = t or ""
	if t:find("highway") then
		if t:find("large") then return 11.5 elseif t:find("medium") then return 9 else return 4.5 end
	end
	if t:find("tram/") then return 5.5 end
	if t:find("xsmall") then return 7 end
	if t:find("large") then return 16 elseif t:find("medium") then return 12 else return 8 end
end

--- The real footprint of an updateFn result: the farthest point of any edge (Hermite, 9 samples) from
--- the centre plus its road's half width.
local function footprint(res)
	local far = 0
	for _, el in ipairs(res.edgeLists or {}) do
		local hw = halfWidth(el.params and el.params.type)
		local e = el.edges
		for i = 1, #e, 2 do
			local p0, t0, p1, t1 = e[i][1], e[i][2], e[i + 1][1], e[i + 1][2]
			for k = 0, 8 do
				local u = k / 8
				local u2, u3 = u * u, u * u * u
				local a, b, c, d = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
				local x = a * p0[1] + b * t0[1] + c * p1[1] + d * t1[1]
				local y = a * p0[2] + b * t0[2] + c * p1[2] + d * t1[2]
				far = math.max(far, math.sqrt(x * x + y * y) + hw)
			end
		end
	end
	return far
end

test("showcaseReach covers the real footprint of every type (square_roundabouts' own updateFn)", function()
	local checked = 0
	-- our plain crossing: stress_crossing.result
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	for _, list in ipairs({ logic.SHOWCASE_IX_TYPES, logic.SHOWCASE_RB_TYPES, logic.SHOWCASE_PLAIN_TYPES, logic.LIGHTS_SHAPES }) do
		for ti, t in ipairs(list) do
			local update, capture
			if t.kind == "plain" then
				update, capture = function(_c, p) return cross.result(p) end, {}
			else
				update, capture = rbUpdateFn(t.file)
			end
			ok(update ~= nil, "square_roundabouts' " .. t.file .. ".lua not found (run from the repo root: make test)")
			if update == nil then return end
			local rng = logic.newRng(1000 + ti)
			for i = 1, 30 do
				local c = logic.showcaseDraw(rng, t, (t.kind == "rb" and i % 2 == 0) and 6 or nil)
				local okU, res = pcall(update, capture, c.params)
				ok(okU, t.id .. ": " .. tostring(res))
				if okU then
					local f = footprint(res)
					local r = logic.showcaseReach(c)
					ok(f <= r, string.format("%s footprint %.0f m > reach %d m [%s]", t.id, f, r, logic.showcaseParamText(c)))
					ok(r - f < 260, string.format("%s reach %d m far above the footprint %.0f m", t.id, r, f))
					checked = checked + 1
				end
			end
		end
	end
	eq(checked, 30 * #allTypes())
	-- the in-game misses of 2026-10-12 (seed 204313) are covered now
	local hamburger = { file = "square_roundabouts.con", params = { sqrb_arm_type = 6, sqrb_arms = 5, sqrb_centre = 2, sqrb_island = 5,
		sqrb_lanes = 2, sqrb_radius_size = 2, sqrb_shape = 5, sqrb_signals = 1, sqrb_splitter = 1, sqrb_through_road = 5, sqrb_tram = 2 } }
	local update = rbUpdateFn(hamburger.file)
	local f = footprint(update({}, hamburger.params))
	ok(f > 94 and logic.showcaseReach(hamburger) >= f, string.format("Hamburger 12/35: footprint %.0f m, reach %d m (was 94 m)", f,
		logic.showcaseReach(hamburger)))
end)


---------------------------------------------------------------------------
-- Layout (groups only, A/B twins)

local MAP, MARGIN = 16384, 400

local function segDist(p, q, a, b)
	-- shortest distance between segments p-q and a-b (2D; 0 when they cross)
	local function cross(o, u, v) return (u[1] - o[1]) * (v[2] - o[2]) - (u[2] - o[2]) * (v[1] - o[1]) end
	local d1, d2 = cross(a, b, p), cross(a, b, q)
	local d3, d4 = cross(p, q, a), cross(p, q, b)
	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then return 0 end
	return math.min(logic.distToSegment(p, a, b), logic.distToSegment(q, a, b), logic.distToSegment(a, p, q), logic.distToSegment(b, p, q))
end

--- A town's clearance: its streets (its size's spacing x SHOWCASE_TOWN_R) + SHOWCASE_GAP.
local function clear(t)
	return logic.TOWN_SIZES[t.size].spacing * logic.SHOWCASE_TOWN_R + logic.SHOWCASE_GAP
end

--- size: the one TOWN_SIZES index every town must have (default the Showcase's, SHOWCASE_SIZE).
local function checkLayout(L, w, h, size)
	local hw, hh = w / 2 - MARGIN, h / 2 - MARGIN
	local want = size or logic.SHOWCASE_SIZE
	for i, t in ipairs(L.towns) do
		ok(math.abs(t.x) <= hw + 1e-6 and math.abs(t.y) <= hh + 1e-6, t.name .. " inside the map")
		ok(logic.isTestTownName(t.name), t.name)
		eq(t.size, want, t.name .. " the spec's one size")
		for j = i + 1, #L.towns do
			local u = L.towns[j]
			ok(math.sqrt((t.x - u.x) ^ 2 + (t.y - u.y) ^ 2) >= clear(t) + clear(u) - 1e-6, t.name .. " / " .. u.name .. " overlap")
		end
	end
	local roads = {}
	for gi, g in ipairs(L.groups) do
		local p = g.place
		ok(math.abs(p.x) + p.reach <= hw + 1e-6 and math.abs(p.y) + p.reach <= hh + 1e-6, g.name .. " inside the map")
		eq(#g.towns, #logic.showcaseArms(p.case_), g.name .. " one town per arm")
		-- every town clear of every junction (its own: reach + clearance)
		for _, gg in ipairs(L.groups) do
			for _, ti in ipairs(gg.towns) do
				local t = L.towns[ti]
				ok(math.sqrt((p.x - t.x) ^ 2 + (p.y - t.y) ^ 2) >= p.reach + clear(t) - 1e-6, g.name .. " clear of " .. t.name)
			end
		end
		-- groups (their circles) apart
		for j = gi + 1, #L.groups do
			local q = L.groups[j]
			ok(math.sqrt((p.x - q.place.x) ^ 2 + (p.y - q.place.y) ^ 2) >= g.R + q.R - 1e-6, g.name .. " / " .. q.name)
		end
		for _, ti in ipairs(g.towns) do roads[#roads + 1] = { a = { p.x, p.y }, b = { L.towns[ti].x, L.towns[ti].y }, owner = gi } end
	end
	-- roads of different groups never come close
	for i, a in ipairs(roads) do
		for j = i + 1, #roads do
			local b = roads[j]
			if a.owner ~= b.owner then ok(segDist(a.a, a.b, b.a, b.b) > 200, a.owner .. " road near " .. b.owner) end
		end
	end
end

--- The twin sets of a layout: set -> its groups in order.
local function sets(L)
	local out = {}
	for _, g in ipairs(L.groups) do
		out[g.set] = out[g.set] or {}
		table.insert(out[g.set], g)
	end
	return out
end

test("layout, 16 km map: every kind in turn, twins side by side, nothing overlaps", function()
	local L = logic.showcaseLayout(MAP, MAP, MARGIN, 4242)
	local n, nTowns, by, ab = logic.showcaseCounts(L)
	ok(n >= 16, "groups: " .. n)
	ok(by.ix >= 4 and by.rb >= 4 and by.plain >= 4, string.format("ix %d rb %d plain %d", by.ix, by.rb, by.plain))
	eq(ab.sl, ab.game, "every set has an sl and a game twin")
	eq(by.ix + by.rb + by.plain, n)
	local towns = 0
	for _, g in ipairs(L.groups) do towns = towns + #g.towns end
	eq(towns, nTowns)
	-- the sets take turns by kind (ix, rb, plain first), each kind starting at its first type
	local S = sets(L)
	eq(S[1][1].kind, "ix")
	eq(S[2][1].kind, "rb")
	eq(S[3][1].kind, "plain")
	eq(S[1][1].place.case_.id, logic.SHOWCASE_IX_TYPES[1].id)
	eq(S[2][1].place.case_.id, logic.SHOWCASE_RB_TYPES[1].id)
	eq(S[3][1].place.case_.id, logic.SHOWCASE_PLAIN_TYPES[1].id)
	-- interchanges cross on a large country road; plain crossings draw their lights
	for _, g in ipairs(L.groups) do
		if g.kind == "ix" then eq(g.place.case_.params.sqrb_ix_cross, 6) end
		if g.kind ~= "plain" then eq(g.place.lightsOff, false) end
	end
	checkLayout(L, MAP, MAP)
end)

test("layout: twins get identical draws (params, angle, town sizes, relative towns); modes per SHOWCASE_AB", function()
	for _, seed in ipairs({ 1, 777, 4242 }) do
		local L = logic.showcaseLayout(MAP, MAP, MARGIN, seed)
		local lit = 0
		for si, list in pairs(sets(L)) do
			local first = list[1]
			local modes = logic.showcaseModes(first.kind, first.place.lightsOff)
			eq(#list, #modes, "set " .. si)
			if first.kind == "plain" and not first.place.lightsOff then
				lit = lit + 1
				eq(#list, 3, "a lit plain crossing gets the sl_phases twin")
			end
			for t, g in ipairs(list) do
				eq(g.ab, modes[t].ab)
				eq(g.twin, modes[t].twin)
				eq(g.name, string.format("Group %d%s", si, modes[t].twin))
				eq(logic.showcaseParamText(g.place.case_), logic.showcaseParamText(first.place.case_))
				eq(g.place.case_.id, first.place.case_.id)
				eq(g.place.angle, first.place.angle)
				eq(g.place.reach, first.place.reach)
				eq(g.place.lightsOff, first.place.lightsOff)
				eq(g.oneWay, first.oneWay)
				for k, ti in ipairs(g.towns) do
					local t0, t1 = L.towns[first.towns[k]], L.towns[ti]
					eq(t1.size, t0.size, "same town size")
					near(t1.x - g.place.x, t0.x - first.place.x, 1e-6)
					near(t1.y - g.place.y, t0.y - first.place.y, 1e-6)
				end
				-- side by side: the same row, 2 R apart
				near(g.place.y, first.place.y, 1e-9)
				near(g.place.x - first.place.x, (t - 1) * 2 * first.R, 1e-6)
			end
		end
		checkLayout(L, MAP, MAP)
	end
	eq(logic.showcaseModes("plain", false)[3].ab, "sl_phases")
	eq(#logic.showcaseModes("plain", true), 2)
	eq(#logic.showcaseModes("rb", false), 2)
	eq(#logic.showcaseModes("ix", false), 2)
	eq({ logic.showcaseModes("ix", false)[1].ab, logic.showcaseModes("ix", false)[2].ab }, { "sl", "game" })
end)

test("layout: the variant list is one table (SHOWCASE_AB): changing it changes every set", function()
	local saved = logic.SHOWCASE_AB
	logic.SHOWCASE_AB = { { ab = "sl", twin = "a", label = "Smart lanes" } }
	local L = logic.showcaseLayout(MAP, MAP, MARGIN, 1)
	logic.SHOWCASE_AB = saved
	for _, g in ipairs(L.groups) do eq(g.ab, "sl") end
	eq(L.groups[#L.groups].set, #L.groups, "one group per set")
	checkLayout(L, MAP, MAP)
end)

test("layout: town distances = reach + clearance, pushed out together when two towns would come too close", function()
	-- a plain crossroads at 60 deg with Small towns: reach + clearance 88 + 520 = 608 m, too close at 60 deg
	local d = logic.showcaseTownDists(88, { 0, 60, 180, 240 }, { 1200, 1200, 1200, 1200 })
	near(d[1], d[2], 1e-9)
	near(d[1], 1040, 1e-6, "60 deg apart: the chord is the distance, 2 x 520")
	-- an interchange (90 deg) is far enough out already
	local e = logic.showcaseTownDists(505, { 0, 90, 180, 270 }, { 1200, 1500, 1200, 1500 })
	near(e[1], 505 + 520, 1e-9)
	near(e[2], 505 + 625, 1e-9)
end)

test("layout: the same seed gives the same layout, another seed other params", function()
	local a = logic.showcaseLayout(MAP, MAP, MARGIN, 31337)
	local b = logic.showcaseLayout(MAP, MAP, MARGIN, 31337)
	eq(a, b)
	local c = logic.showcaseLayout(MAP, MAP, MARGIN, 31338)
	ok(logic.showcaseParamText(a.groups[1].place.case_) ~= logic.showcaseParamText(c.groups[1].place.case_)
		or a.groups[1].place.angle ~= c.groups[1].place.angle, "params differ")
end)

test("layout: smaller and tall maps still get variety; a tiny one nothing; never -0", function()
	local L = logic.showcaseLayout(12000, 9000, MARGIN, 1)
	local _, _, by = logic.showcaseCounts(L)
	ok(by.ix > 0 and by.rb > 0 and by.plain > 0, string.format("ix %d rb %d plain %d", by.ix, by.rb, by.plain))
	checkLayout(L, 12000, 9000)
	local T = logic.showcaseLayout(8000, 16000, MARGIN, 777)
	ok(#T.groups >= 6)
	checkLayout(T, 8000, 16000)
	eq(#logic.showcaseLayout(2500, 2500, MARGIN, 5).groups, 0)
	eq(#logic.showcaseLayout(600, 600, MARGIN, 5).groups, 0)
	local function noNegZero(v, what) ok(not (v == 0 and 1 / v < 0), what) end
	for _, M in ipairs({ L, T, logic.showcaseLayout(MAP, MAP, MARGIN, 5) }) do
		for _, t in ipairs(M.towns) do noNegZero(t.x, t.name) noNegZero(t.y, t.name) end
		for _, g in ipairs(M.groups) do noNegZero(g.place.x, g.name) noNegZero(g.place.y, g.name) noNegZero(g.place.angle, g.name) end
	end
end)

test("showcaseZones: one zone per group with its pair and mode; zones apart; the zone line", function()
	local L = logic.showcaseLayout(MAP, MAP, MARGIN, 777)
	local Z = logic.showcaseZones(L, 100, -50)
	eq(#Z, #L.groups)
	local ids = {}
	for i, z in ipairs(Z) do
		local g = L.groups[i]
		eq(z.id, string.format("g%d%s", g.set, g.twin))
		eq(z.pair, string.format("g%d", g.set))
		eq(z.ab, g.ab)
		eq(z.kind, g.kind)
		eq(z.towns, #g.towns)
		near(z.x, 100 + g.place.x, 1e-9)
		near(z.y, -50 + g.place.y, 1e-9)
		eq(z.r, g.place.reach)
		ok(not ids[z.id], z.id)
		ids[z.id] = true
		for j = i + 1, #Z do
			local w = Z[j]
			ok(math.sqrt((z.x - w.x) ^ 2 + (z.y - w.y) ^ 2) >= z.r + w.r, z.id .. " / " .. w.id)
		end
	end
	eq(logic.showcaseZoneLine({ id = "g3b", pair = "g3", ab = "game", kind = "rb", label = "Magic Roundabout", x = 1200.4, y = -3400, r = 167,
		towns = 5 }, true), "[SQST] showcase zone id=g3b pair=g3 ab=game kind=roundabout type=Magic_Roundabout x=1200 y=-3400 r=167 r_from=measured towns=5 match=yes")
	eq(logic.showcaseZoneLine({ id = "g1a", pair = "g1", ab = "sl", kind = "ix", label = "Parclo, two quadrants", x = 0, y = 0, r = 400,
		towns = 4 }, false), "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=interchange type=Parclo_two_quadrants x=0 y=0 r=400 r_from=est towns=4 match=yes")
	eq(logic.showcaseZoneLine({ id = "g2b", pair = "g2", ab = "game", kind = "plain", label = "Crossroads", x = 5, y = 6, r = 90,
		towns = 3, reason = "town,redrawn" }, true), "[SQST] showcase zone id=g2b pair=g2 ab=game kind=plain type=Crossroads x=5 y=6 r=90 r_from=measured towns=3 match=no reason=town,redrawn")
end)

test("showcaseMatch: twins match unless one lost a town or was redrawn differently from the others", function()
	local function tw(built, redrawn, params) return { built = built, redrawn = redrawn, params = params } end
	eq(logic.showcaseMatch({ tw(true, false, "a"), tw(true, false, "a") }, false), nil)
	-- one twin redrawn, its sibling built with the original draw: no longer identical
	eq(logic.showcaseMatch({ tw(true, true, "b"), tw(true, false, "a") }, false), "redrawn")
	eq(logic.showcaseMatch({ tw(true, false, "a"), tw(true, true, "b"), tw(true, false, "a") }, false), "redrawn")
	-- every twin redrawn the same way and built: still identical
	eq(logic.showcaseMatch({ tw(true, true, "b"), tw(true, true, "b") }, false), nil)
	-- a redrawn twin refused again (not built), or redraws that differ
	eq(logic.showcaseMatch({ tw(false, true, nil), tw(false, true, nil) }, false), "redrawn")
	eq(logic.showcaseMatch({ tw(true, true, "b"), tw(true, true, "c") }, false), "redrawn")
	-- a twin lost a town (skipped: no land)
	eq(logic.showcaseMatch({ tw(true, false, "a"), tw(true, false, "a") }, true), "town")
	eq(logic.showcaseMatch({ tw(true, true, "b"), tw(true, false, "a") }, true), "town,redrawn")
	eq(logic.showcaseMatch({}, false), nil)
end)

test("layout: SHOWCASE_MAX_GROUPS is never exceeded, and sets stay whole under it", function()
	local keep = logic.SHOWCASE_MAX_GROUPS
	local okAll, err = pcall(function()
		for _, seed in ipairs({ 1, 777, 4242 }) do
			for cap = 1, 12 do
				logic.SHOWCASE_MAX_GROUPS = cap
				local L = logic.showcaseLayout(MAP, MAP, MARGIN, seed)
				ok(#L.groups <= cap, string.format("seed %d cap %d: %d groups", seed, cap, #L.groups))
				for si, list in pairs(sets(L)) do
					eq(#list, #logic.showcaseModes(list[1].kind, list[1].place.lightsOff), "set " .. si .. " whole")
				end
				if cap >= 3 then ok(#L.groups >= cap - 2, string.format("seed %d cap %d: only %d groups", seed, cap, #L.groups)) end
			end
		end
	end)
	logic.SHOWCASE_MAX_GROUPS = keep
	assert(okAll, err)
end)

test("showcaseRoutes: across each ring, the same arm pairs in every twin, one-way arms none, whole sets under the cap", function()
	local L = {
		groups = {
			{ set = 1, towns = { 1, 2, 3 } }, { set = 1, towns = { 4, 5, 6 } },
			{ set = 2, towns = { 7, 8, 9, 10 } }, { set = 2, towns = { 11, 12, 13, 14 } },
			{ set = 3, towns = { 15, 16, 17, 18 }, oneWay = { [2] = true, [4] = true } }, { set = 3, towns = { 19, 20, 21, 22 }, oneWay = { [2] = true, [4] = true } },
		},
	}
	local all3, all4 = { true, true, true }, { true, true, true, true }
	local linked = { all3, all3, all4, all4, all4, all4 }
	eq(logic.showcaseRoutes(L, linked, 40), {
		{ 1, 2, 1 }, { 4, 5, 2 }, { 7, 9, 3 }, { 11, 13, 4 }, { 15, 17, 5 }, { 19, 21, 6 },
		{ 2, 3, 1 }, { 5, 6, 2 }, { 8, 10, 3 }, { 12, 14, 4 },
	})
	-- a pair not linked in one twin is left out in every twin of the set
	local partial = { all3, all3, all4, { true, true, nil, true }, all4, all4 }
	local r = logic.showcaseRoutes(L, partial, 40)
	for _, x in ipairs(r) do ok(x[3] ~= 3 and x[3] ~= 4 or (x[1] ~= 7 and x[1] ~= 11), "set 2's first pair dropped") end
	eq(#r, 8)
	-- the cap takes whole sets
	eq(#logic.showcaseRoutes(L, linked, 5), 4)
	eq(logic.showcaseRoutes(L, nil, 40), {})
end)

test("showcaseSummary: per kind and per twin mode", function()
	eq(logic.showcaseSummary({ ix = 4, rb = 3, plain = 5 }, { ix = 4, rb = 4, plain = 5 }, { sl = 5, game = 5, sl_phases = 2 },
		{ sl = 5, game = 5, sl_phases = 3 }, 40, 41, 12, 777),
		"Showcase done: 4 of 4 interchanges, 3 of 4 roundabouts, 5 of 5 plain junctions built (sl 5/5, game 5/5, sl_phases 2/3), 40 of 41 links; every town then grows x10 in 3 build-out passes, locked to its grid; 12 bus lines queued. Seed 777.")
	ok(logic.showcaseSummary({}, {}, {}, {}, 0, 0, 0, 1):find("; no bus lines", 1, true))
end)

test("no line code paths left: no lines, shifts, nudges, bends or Showcase options", function()
	eq(logic.showcaseShift, nil)
	eq(logic.showcaseNudge, nil)
	eq(logic.bendPoint, nil)
	eq(logic.SHOWCASE_SEEDS, nil)
	eq(logic.SHOWCASE_BAND_GAP, nil)
	eq(logic.showcaseLayout(MAP, MAP, MARGIN, 1).lines, nil)
	local h = assert(io.open("mods/square_stress_test/content/stress/gui/stress_junctions.tl"))
	local src = h:read("a")
	h:close()
	for _, word in ipairs({ "llink", "splitLine", "shiftStop", "SHOW_BENDS", "showToArm", "showUi", "SHOW_NUDGE" }) do
		ok(not src:find(word, 1, true), word)
	end
	-- the Showcase has no up-front money warning (it turns Keep balance on itself)
	local body = src:sub(src:find("function jn.buildShowcase", 1, true))
	ok(not body:find("moneyWarn", 1, true))
end)

test("assignArms: by measured heading when known (an oval's arm leaves off its nominal direction); leftovers take the nearest free arm", function()
	-- an arm end due east of the centre whose road heads north-east, and one due north heading north
	local clusters = { { members = { 1 }, x = 100, y = 0, hx = math.cos(math.rad(50)), hy = math.sin(math.rad(50)) },
		{ members = { 2 }, x = 0, y = 100, hx = 0, hy = 1 } }
	local towns = { { 1200, 0 }, { 900, 900 }, { 0, 1200 } }
	local a = logic.assignArms(0, 0, clusters, towns, 60)
	eq(a[1], 2, "east end heading north-east: the north-east town")
	eq(a[2], 3)
	local plain = { { members = { 1 }, x = 100, y = 0 }, { members = { 2 }, x = 0, y = 100 } }
	eq(logic.assignArms(0, 0, plain, towns, 60), { 1, 3 })
	local three = { { members = { 1 }, x = 100, y = 0 }, { members = { 2 }, x = 0, y = 100 }, { members = { 3 }, x = -70, y = -70 } }
	local corners = { { 1200, 0 }, { 0, 1200 }, { 0, -1200 } }
	local got = logic.assignArms(0, 0, three, corners, 30)
	eq(got, { 1, 2 })
	local extra = logic.assignLeftovers(0, 0, three, corners, got)
	eq(#extra, 1)
	eq({ extra[1][1], extra[1][2] }, { 3, 3 })
	near(extra[1][3], 45, 1e-9)
	eq(logic.assignLeftovers(0, 0, three, corners, got), {}, "nothing left")
	-- a skipped town (no land) takes no leftover arm
	eq(logic.assignLeftovers(0, 0, three, corners, logic.assignArms(0, 0, three, corners, 30), { [3] = true }), {})
end)

test("showcaseRedraw keeps the type, arms, angle, side road and arm road and fits the reach", function()
	local rng = logic.newRng(5)
	for _, list in ipairs({ logic.SHOWCASE_RB_TYPES, logic.SHOWCASE_PLAIN_TYPES, logic.SHOWCASE_IX_TYPES }) do
		for _, t in ipairs(list) do
			for i = 1, 10 do
				local c = logic.showcaseDraw(rng, t, t.kind == "ix" and 6 or nil)
				local r = logic.showcaseReach(c)
				local d = logic.showcaseRedraw(c, r, 100 + i)
				if t.kind == "plain" then ok(d ~= nil, t.id) end
				if d ~= nil then
					eq(d.id, c.id); eq(d.file, c.file)
					eq(d.params.sqrb_arms, c.params.sqrb_arms)
					eq(d.params.sqst_x_angle, c.params.sqst_x_angle)
					eq(d.params.sqst_x_side, c.params.sqst_x_side)
					if t.armKey then eq(d.params[t.armKey], c.params[t.armKey]) end
					ok(logic.showcaseReach(d) <= r)
					ok(logic.showcaseParamText(d) ~= logic.showcaseParamText(c))
					eq(logic.showcaseArms(d), logic.showcaseArms(c))
					eq(logic.showcaseOneWay(d), logic.showcaseOneWay(c))
				end
			end
		end
	end
	eq(logic.showcaseRedraw({ id = "nope", params = {} }, 300, 1), nil)
end)

test("crossing construction: side road angle and an own road per arm (Showcase), as before without them", function()
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	-- X at 60 deg: side arms at 60 and 240 deg
	local r = cross.result({ sqst_x_shape = 1, sqst_x_main = 3, sqst_x_side = 2, sqst_x_angle = 2 })
	eq(#r.edgeLists, 2)
	local side = r.edgeLists[2].edges
	near(side[1][1][1], 60 * math.cos(math.rad(60)), 1e-9)
	near(side[1][1][2], 60 * math.sin(math.rad(60)), 1e-9)
	near(side[4][1][2], 60 * math.sin(math.rad(240)), 1e-9)
	-- own roads for the east main arm and the second side arm: lists of their own, one edge each
	local q = cross.result({ sqst_x_shape = 1, sqst_x_main = 3, sqst_x_side = 2, sqst_x_main2 = 6, sqst_x_side2 = 1 })
	eq(#q.edgeLists, 3)
	eq(#q.edgeLists[1].edges, 2)
	ok(q.edgeLists[2].params.type:find("country_new_medium", 1, true), q.edgeLists[2].params.type)
	eq(q.edgeLists[2].edges[1][1][1], 0, "from the centre (outward, as the east arm)")
	eq(q.edgeLists[2].edges[2][1][1], cross.ARM)
	eq(#q.edgeLists[3].edges, 4, "side2 = 1: the same road")
	local t = cross.result({ sqst_x_shape = 2, sqst_x_side2 = 4, sqst_x_angle = 5 })
	eq(#t.edgeLists, 2, "a T has no second side arm")
	near(t.edgeLists[2].edges[1][1][1], 60 * math.cos(math.rad(120)), 1e-9)
	for _, res in ipairs({ r, q, t }) do
		for _, el in ipairs(res.edgeLists) do
			for _, e in ipairs(el.edges) do
				for _, v in ipairs({ e[1][1], e[1][2], e[2][1], e[2][2] }) do ok(1 / v ~= -math.huge, "no -0") end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Lights showcase (SHOWCASE.md "Lights showcase"): the same layout code with LIGHTS_SPEC

-- one shape, four twins (lightsSpec(1)): the single-shape Lights showcase the older tests cover; the mixed
-- default (LIGHTS_SPEC) has its own tests below
local LS = logic.lightsSpec(1)

test("crossing construction: Traffic light Yes lists the centre node in both light fields of every list; default none", function()
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	eq(cross.KEYS.lights, "sqst_x_lights")
	local plain = cross.result({ sqst_x_shape = 1, sqst_x_main2 = 6 })
	for _, el in ipairs(plain.edgeLists) do
		eq(el.trafficLightYes, nil)
		eq(el.trafficLightNodePreference, nil)
	end
	for _, shape in ipairs({ 1, 2 }) do
		local r = cross.result({ sqst_x_shape = shape, sqst_x_lights = 2, sqst_x_main2 = 6, sqst_x_angle = 3 })
		ok(#r.edgeLists >= 2)
		for _, el in ipairs(r.edgeLists) do
			ok(#el.trafficLightYes >= 1, "every list names the centre")
			eq(#el.trafficLightNodePreference, #el.trafficLightYes)
			for k, i in ipairs(el.trafficLightYes) do
				local e = el.edges[i + 1]
				eq({ e[1][1], e[1][2] }, { 0, 0 }, "a centre entry (0-based index)")
				eq(el.trafficLightNodePreference[k], { i, "YES" })
			end
			-- only the centre: arm ends stay unlit dead ends
			for i, e in ipairs(el.edges) do
				if e[1][1] ~= 0 or e[1][2] ~= 0 then
					for _, j in ipairs(el.trafficLightYes) do ok(j ~= i - 1) end
				end
			end
		end
	end
end)

test("lights shapes: one lit 90 deg junction per press (2x2 X, 3x3 X, 3x2 X, T 2x2), country roads of the named lanes, nothing drawn", function()
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	eq(#logic.LIGHTS_SHAPES, 4)
	-- label -> shape, main lanes, side lanes (each way)
	local want = { { "2x2 X", 1, 2, 2, "x" }, { "3x3 X", 1, 3, 3, "x" }, { "3x2 X", 1, 3, 2, "x" }, { "T 2x2", 2, 2, 2, "t" } }
	for k, w in ipairs(want) do
		local sp = logic.lightsSpec(k)
		eq(sp.shape, k)
		eq(sp.shapeLabel, w[1])
		eq(logic.specKinds(sp), { w[5] }, "one slot")
		local types = logic.specTypes(sp, w[5])
		eq(#types, 1, "one type: every set the same junction")
		local t = types[1]
		eq(t.label, w[1])
		eq(t.kind, "plain")
		eq(t.file, logic.SHOWCASE_PLAIN_FILE)
		eq(t.ranges, {}, "nothing drawn")
		eq(t.fixed.sqst_x_shape, w[2])
		eq(t.fixed.sqst_x_lights, 2)
		eq(t.fixed.sqst_x_angle, 1)
		eq(cross.ANGLES[1], 90)
		eq(t.fixed.sqst_x_main2, 1, "the same road on both main arms")
		if w[2] == 2 then eq(t.fixed.sqst_x_side2, nil) else eq(t.fixed.sqst_x_side2, 1) end
		local main, side = cross.ROADS[t.fixed.sqst_x_main], cross.ROADS[t.fixed.sqst_x_side]
		eq({ main.lanes, side.lanes }, { w[3], w[4] }, w[1])
		for _, road in ipairs({ main, side }) do
			ok(not road.oneWay)
			ok(road.template:find("/country/country_new_", 1, true), w[1] .. " country roads")
		end
		-- every draw the same, lit, two-way
		local rng = logic.newRng(3)
		local first = logic.showcaseParamText(logic.showcaseDraw(rng, t, nil))
		for _ = 1, 20 do
			local c = logic.showcaseDraw(rng, t, nil)
			eq(logic.showcaseParamText(c), first)
			eq(c.params.sqst_x_lights, 2)
			eq(logic.showcaseOneWay(c), {})
		end
		-- the crossing construction builds it: lanes per arm as named
		local r = cross.result(t.fixed)
		ok(#r.edgeLists >= 2)
		-- the spec: four twins, Medium towns only, one size command for about 400 people each, no bus lines, locked, square
		eq(sp.size, 2)
		eq(sp.growFactor, logic.LIGHTS_GROW_FACTOR)
		eq(sp.growTarget, 400)
		eq(sp.growPasses, 1)
		eq(sp.noBusLines, true)
		eq(sp.lockStreets, true)
		eq(sp.square, true)
		eq(sp.denseWeights, logic.DENSE_WEIGHTS)
	end
	eq(logic.lightsSpec(5).shapeLabel, "2x2 X", "wraps")
	eq(logic.lightsSpec(1).shapeLabel, "2x2 X")
	eq(logic.LIGHTS_SPEC.shapeLabel, nil, "the default: every shape")
	local LS1 = logic.lightsSpec(1)
	local modes = logic.showcaseModes("plain", false, LS1)
	eq(#modes, 4)
	for i, w in ipairs({ { "sl", "a" }, { "game", "b" }, { "sl_phases", "c" }, { "sl_lock", "d" } }) do
		eq({ modes[i].ab, modes[i].twin }, w)
	end
	-- one fixed size per spec (user 2026-10-12): Medium for both Showcases
	eq(logic.specSize(LS1), logic.LIGHTS_SIZE)
	eq(logic.specSize(nil), logic.SHOWCASE_SIZE)
	eq(logic.specSizeText(LS1), "Medium")
	eq(logic.specSizeText(nil), "Medium")
	eq(logic.specSizeText(logic.SHOWCASE_SPEC), "Medium")
end)

test("lights layout, 16 km map, every shape: one junction in every set, sets of 4 identical twins in a row, square, nothing overlaps", function()
	for k = 1, #logic.LIGHTS_SHAPES do
		local LSk = logic.lightsSpec(k)
		local slot = LSk.kinds[1]
		for _, seed in ipairs({ 1, 12, 4242 }) do
			local L = logic.showcaseLayout(MAP, MAP, MARGIN, seed, LSk)
			local n, nTowns, by, ab = logic.showcaseCounts(L, LSk)
			ok(n >= 12, string.format("shape %d seed %d: %d groups", k, seed, n))
			eq(n % 4, 0, "whole sets")
			eq(by[slot], n, "every group the one shape")
			for _, m in ipairs(logic.LIGHTS_AB) do eq(ab[m.ab], n / 4, m.ab) end
			local text = logic.showcaseParamText(L.groups[1].place.case_)
			for _, g in ipairs(L.groups) do
				eq(logic.showcaseParamText(g.place.case_), text, "the same junction in every set")
				eq(g.place.case_.label, LSk.shapeLabel)
			end
			local S = sets(L)
			for si, list in pairs(S) do
				eq(#list, 4, "set " .. si)
				local first = list[1]
				for t, g in ipairs(list) do
					eq(g.kind, "plain")
					eq(g.ab, logic.LIGHTS_AB[t].ab)
					eq(g.name, string.format("Group %d%s", si, logic.LIGHTS_AB[t].twin))
					eq(g.place.lightsOff, false, "never drawn without lights")
					eq(g.place.angle, 0)
					local dist
					for kk, ti in ipairs(g.towns) do
						local tw = L.towns[ti]
						local dx, dy = tw.x - g.place.x, tw.y - g.place.y
						ok(dx == 0 or dy == 0, string.format("%s on an axis of %s (%g, %g)", tw.name, g.name, dx, dy))
						local d = math.abs(dx) + math.abs(dy)
						if dist then near(d, dist, 1e-6, "one distance") else dist = d end
						local u = logic.axisUnit(logic.showcaseArms(g.place.case_)[kk])
						near(dx, u[1] * d, 1e-9)
						near(dy, u[2] * d, 1e-9)
					end
					for kk, ti in ipairs(g.towns) do
						local t0, t1 = L.towns[first.towns[kk]], L.towns[ti]
						eq(t1.size, t0.size, "same town size")
						near(t1.x - g.place.x, t0.x - first.place.x, 1e-6)
						near(t1.y - g.place.y, t0.y - first.place.y, 1e-6)
					end
					near(g.place.y, first.place.y, 1e-9)
					near(g.place.x - first.place.x, (t - 1) * 2 * first.R, 1e-6)
				end
			end
			checkLayout(L, MAP, MAP, logic.LIGHTS_SIZE)
			eq(nTowns, #L.towns)
		end
	end
	local LS1 = logic.lightsSpec(1)
	eq(logic.showcaseLayout(MAP, MAP, MARGIN, 9, LS1), logic.showcaseLayout(MAP, MAP, MARGIN, 9, LS1))
	eq(logic.showcaseLayout(MAP, MAP, MARGIN, 9), logic.showcaseLayout(MAP, MAP, MARGIN, 9, logic.SHOWCASE_SPEC))
	ok(#logic.showcaseLayout(MAP, 8000, MARGIN, 1, LS1).groups >= 8)
	eq(#logic.showcaseLayout(2500, 2500, MARGIN, 5, LS1).groups, 0)
end)

test("one town size per spec (user 2026-10-12: Medium in both); sets per 16 km and 20 km map", function()
	local SEEDS = { 1, 12, 777, 4242, 31337 }
	for _, M in ipairs({ 16384, 20480 }) do
		for _, sp in ipairs({ logic.SHOWCASE_SPEC, logic.lightsSpec(1), logic.lightsSpec(4) }) do
			local lo, hi, tlo, thi = math.huge, 0, math.huge, 0
			for _, seed in ipairs(SEEDS) do
				local L = logic.showcaseLayout(M, M, MARGIN, seed, sp)
				for _, t in ipairs(L.towns) do eq(t.size, 2, string.format("%s %s Medium", sp.id, t.name)) end
				local nSets = #L.groups > 0 and L.groups[#L.groups].set or 0
				lo, hi = math.min(lo, nSets), math.max(hi, nSets)
				tlo, thi = math.min(tlo, #L.towns), math.max(thi, #L.towns)
			end
			print(string.format("      %s %s %d m: sets %d-%d towns %d-%d", sp.id, sp.shapeLabel or "", M, lo, hi, tlo, thi))
			-- offline 2026-10-12 (Medium): Showcase 9-10 sets on 16 km, 14-17 on 20 km; Lights showcase one
			-- set of 4 per row: 6 sets on 16 km, 7 on 20 km, whatever the seed
			if sp.id == "showcase" then
				ok(lo >= (M == 16384 and 9 or 14), string.format("Showcase %d m: %d sets", M, lo))
			else
				eq({ lo, hi }, M == 16384 and { 6, 6 } or { 7, 7 }, string.format("Lights showcase %d m sets", M))
			end
		end
	end
end)

test("lights zones: four modes per pair, sl_lock (not sl_fan) accepted by Smart Lanes' validator with its labels; by_ab counts sl_lock as Smart Lanes does", function()
	local L = logic.showcaseLayout(MAP, MAP, MARGIN, 12, LS)
	local Z = logic.showcaseZones(L, 100, -50)
	local p, dropped = logic.slZonesPayload(Z, "s12-1-1")
	eq(dropped, 0)
	eq(#p.zones, #L.groups)
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local op, list = Zl.validate(p)
	eq(op, "set")
	eq(#list, #Z)
	local fan = 0
	for i, z in ipairs(Z) do
		eq(list[i].ab, z.ab)
		eq(list[i].id, z.id)
		eq(list[i].pair, z.pair)
		if z.ab == "sl_lock" then
			fan = fan + 1
			ok(z.id:match("^g%d+d$"), z.id)
		end
		ok(z.ab ~= "sl_fan", "no sl_fan twin any more")
	end
	eq(fan, #L.groups / 4)
	-- the same by_ab text as Smart Lanes logs on receipt (sl_lock after sl_fan, only when > 0)
	eq(logic.slZonesByAb(p.zones), Zl.byAbText(list))
	ok(logic.slZonesByAb(p.zones):find(",sl_lock:" .. fan .. "$"), logic.slZonesByAb(p.zones))
	ok(not logic.slZonesByAb(p.zones):find("sl_fan", 1, true))
	ok(logic.SL_ZONE_AB.sl_fan and logic.SL_ZONE_AB.sl_lock)
	-- both together, as Smart Lanes orders them
	local both = { { ab = "game" }, { ab = "sl_lock" }, { ab = "sl_fan" }, { ab = "sl_fan" } }
	eq(logic.slZonesByAb(both), "game:1,sl:0,sl_phases:0,sl_fan:2,sl_lock:1")
end)

test("lights: nothing to redraw (fixed shape); summary per kind and per mode, x3 once, no bus lines", function()
	for k, t in ipairs(logic.LIGHTS_SHAPES) do
		local c = logic.showcaseDraw(logic.newRng(8), t, nil)
		eq(logic.showcaseRedraw(c, logic.showcaseReach(c), 100, logic.lightsSpec(k)), nil, t.id .. ": no other draw")
	end
	eq(logic.showcaseSummary({ x = 15 }, { x = 16 }, { sl = 4, game = 4, sl_phases = 4, sl_lock = 3 },
		{ sl = 4, game = 4, sl_phases = 4, sl_lock = 4 }, 50, 52, 0, 99, nil, logic.lightsSpec(2)),
		"Lights showcase done: 15 of 16 lit 3x3 X crossroads built (sl 4/4, game 4/4, sl_phases 4/4, sl_lock 3/4), 50 of 52 links; every town then grows to about 400 people (one size command, no build-out passes), locked to its grid; no bus lines (the towns' own traffic). Seed 99.")
	eq(logic.showcaseSummary({ t = 8 }, { t = 8 }, {}, {}, 24, 24, 0, 5, nil, logic.lightsSpec(4)):sub(1, 47),
		"Lights showcase done: 8 of 8 lit T 2x2 junction")
	-- the passes are a Grow UI option; the factor is sized for LIGHTS_TARGET_POP people (Medium: initial capacity 400)
	local inP = false
	for _, p in ipairs(logic.GROW_PASSES) do if p == logic.LIGHTS_GROW_PASSES then inP = true end end
	ok(inP)
	eq(logic.LIGHTS_GROW_FACTOR, logic.growFactorFor(logic.LIGHTS_TARGET_POP, logic.TOWN_SIZES[logic.LIGHTS_SIZE].caps, 1.0))
	eq(logic.LIGHTS_GROW_FACTOR * logic.TOWN_SIZES[logic.LIGHTS_SIZE].caps, logic.LIGHTS_TARGET_POP, "Medium: x1 fills 400")
end)

test("batch helpers: segDist, groupLinks (non-touching footprints, at most N, every link once), matchNearest, timing line", function()
	near(logic.segDist({ 0, 0 }, { 10, 0 }, { 0, 5 }, { 10, 5 }), 5, 1e-9)
	eq(logic.segDist({ 0, 0 }, { 10, 10 }, { 0, 10 }, { 10, 0 }), 0.0, "crossing")
	near(logic.segDist({ 0, 0 }, { 10, 0 }, { 13, 4 }, { 20, 4 }), 5, 1e-9)
	-- three links far apart, two of them close to each other (one junction's arms)
	local items = {
		{ 0, 0, 1000, 0, 100 },        -- 1
		{ 0, 50, 0, 1000, 100 },       -- 2: touches 1 (same junction)
		{ 5000, 0, 6000, 0, 100 },     -- 3: far
		{ 10000, 0, 11000, 0, 100 },   -- 4: far
		{ 5000, 60, 5000, 1000, 100 }, -- 5: touches 3
	}
	local g = logic.groupLinks(items, 200, 8)
	eq(g, { { 1, 3, 4 }, { 2, 5 } })
	eq(logic.groupLinks(items, 200, 2), { { 1, 3 }, { 2, 4 }, { 5 } }, "at most 2")
	eq(logic.groupLinks(items, 200, 1), { { 1 }, { 2 }, { 3 }, { 4 }, { 5 } })
	eq(logic.groupLinks({}, 200, 8), {})
	-- one to one, nearest pairs first, within the limit
	eq(logic.matchNearest({ { 0, 0 }, { 100, 0 }, { 5000, 0 } }, { { 98, 3 }, { 2, 1 } }, 50), { [1] = 2, [2] = 1 })
	eq(logic.matchNearest({ { 0, 0 } }, { { 10, 0 }, { 5, 0 } }, 50), { [1] = 2 })
	eq(logic.matchNearest({ { 0, 0 }, { 1, 0 } }, { { 0.5, 0 } }, 50), { [1] = 1 }, "a tie goes to the lower index")
	eq(logic.timingLine("lights_showcase", { towns = 1200.4, links = 5000, density = 61000 }, 125000),
		"[SQST] lights_showcase timing towns=1200ms grids=0ms locks=0ms junctions=0ms links=5000ms depots=0ms density=61000ms total=125000ms (2.1 min)")
	eq(logic.minutesText(90000), "1.5")
end)

---------------------------------------------------------------------------
-- jn.buildShowcase against a fake api

local T = 0
local sent, nodes, edges, nextId, refuseCheck, created, box
local afterBuild        -- run(): called with each construction after its callback (town growth meanwhile)
local lateNodes         -- run(): a construction's nodes appear only after its callback
local zoneEvents        -- the SmartLanes.zones events sent: { cmd, t, before (builds sent before it) }
local slParams          -- getModParams()["square_smart_lanes"] (nil: Smart Lanes absent)
local slZrun            -- function(): Smart Lanes' saved zrun (the acknowledgement), nil: none
local parcelsOf, buildingOn   -- the fake's parcels per edge and town buildings per parcel (nil: none)
local beforeCb          -- function(cmd): the engine's part of an answered command before its callback (a test applies a removal)
local extraArm, twist   -- buildJunction hooks: an extra arm this far out along local y; roundabout arms turned (deg)
local lightPref         -- function(node): a node config's trafficLightPreference (nil: none read)
local gameYearV         -- api.engine.util.getYear's answer (nil: no such function)
local growCalls         -- towns.densify calls: { factor, passes, weights, areas, name, t, sent (commands sent so far) }
local lockCalls         -- towns.lockTowns calls: { name, areas, opts, t, sent, links (link proposals sent so far) }
local litNode           -- function(node): its config has the game's default-like phases (nil: no node lit)
local cfgOverride       -- node -> a config written by an applied proposal (applyStreet), read instead of the made-up one
local firstCfg          -- node -> its made-up config at the first read (lit nodes: before any proposal changed them)
local townCentres       -- town centre node ids (townStreets)

--- A lit node's phases, by the axis of each leg's far node (|dx| >= |dy|: x): x green (y approaches and
--- every crosswalk locked), y green (x approaches and crosswalks locked), pedestrians only (every
--- connection locked). Connection k is lcs[k] (0-based k - 1), crosswalk j at #lcs + j - 1.
local function fakeLights(e, list, lcs, cws)
	local axis = {}
	for _, x in ipairs(list) do
		local ed = edges[x]
		local o = nodes[ed.n0 == e and ed.n1 or ed.n0]
		axis[x] = math.abs(o.x - nodes[e].x) >= math.abs(o.y - nodes[e].y) and "x" or "y"
	end
	local function clone(self)
		local c = { states = {}, clone = clone, trafficLightType = self.trafficLightType }
		for i, st in ipairs(self.states) do c.states[i] = st end
		return c
	end
	local tlc = { states = {}, clone = clone, trafficLightType = -1 }
	for p, green in ipairs({ "x", "y", "walk" }) do
		local l = {}
		for k, c in ipairs(lcs) do
			if axis[c.segment0] ~= green then l[#l + 1] = k - 1 end
		end
		if green ~= "walk" then
			for j = 1, #cws do l[#l + 1] = #lcs + j - 1 end
		end
		tlc.states[p] = { lockedLanes = l, duration = 20 + p, minDuration = 1.5, canSkip = true }
	end
	return tlc
end

local function copyCfg(c)
	local out = { laneConnections = {}, crosswalks = {}, trafficLightConfig = c.trafficLightConfig, trafficLightPreference = c.trafficLightPreference }
	for k, x in ipairs(c.laneConnections or {}) do
		out.laneConnections[k] = { segment0 = x.segment0, lane0 = x.lane0, segment1 = x.segment1, lane1 = x.lane1, withRoad = x.withRoad, withTram = x.withTram }
	end
	for k, x in ipairs(c.crosswalks or {}) do out.crosswalks[k] = x end
	return out
end

--- Applies a street proposal's removals and written node configs to the fake (the engine's part).
local function applyStreet(sp)
	for _, e in ipairs(sp.edgesToRemove or {}) do edges[e] = nil end
	for _, n in ipairs(sp.nodesToRemove or {}) do nodes[n] = nil end
	for _, en in ipairs(sp.nodeConfigsToAdd or {}) do cfgOverride[en.entity] = copyCfg(en.comp) end
end

local function node2edges()
	local m = {}
	for e, ed in pairs(edges) do
		for _, n in ipairs({ ed.n0, ed.n1 }) do
			m[n] = m[n] or {}
			table.insert(m[n], e)
		end
	end
	return m
end

local function newNode(x, y)
	nextId = nextId + 1
	nodes[nextId] = { x = x, y = y, z = 0 }
	return nextId
end

local function newEdge(a, b)
	nextId = nextId + 1
	edges[nextId] = { n0 = a, n1 = b }
	return nextId
end

-- laneConfigs of the fake's highway carriageways (one-way, two road lanes) and two-way streets (stress_nodecfg
-- reads directions from them): index 1 and the last are sidewalks
local function lanesOf(forwards)
	local out = { { forward = forwards[1], transportModes = { [0] = true } } }
	for k = 2, #forwards - 1 do out[#out + 1] = { forward = forwards[k], transportModes = { [2] = true, [3] = true, [4] = true } } end
	out[#out + 1] = { forward = forwards[#forwards], transportModes = { [0] = true } }
	return out
end
local ONE_WAY = lanesOf({ true, true, true, true })
local TWO_WAY = lanesOf({ false, false, true, true })
local TWO_WAY3 = lanesOf({ false, false, false, false, true, true, true, true })
local sameDropLanes  -- a bench test: the lane drop built with one road on both arms (its geometry check fails)
local noRing         -- a bench test: the roundabout built without one-way streets
local benchGeo       -- bench tests: rings and channelized junctions get one-way streets at their centre

--- What is wrong with a link proposal's node configs (stress_nodecfg.problems, plus: an existing node
--- that keeps a config is listed for removal, and no connection uses a sidewalk lane). {} when nothing.
local function cfgProblems(sp)
	local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
	local out = nc.problems(sp, function(e) return edges[e] and edges[e].lanes and #edges[e].lanes or 4 end)
	local rm = {}
	for _, n in ipairs(sp.nodeConfigsToRemove or {}) do rm[n] = true end
	local lanes = {}
	for _, seg in ipairs(sp.edgesToAdd or {}) do lanes[seg.entity] = seg.comp.laneConfigs and #seg.comp.laneConfigs or 4 end
	for _, e in ipairs(sp.nodeConfigsToAdd or {}) do
		if e.entity >= 0 and nodes[e.entity] and not rm[e.entity] then out[#out + 1] = "existing node " .. e.entity .. " not removed first" end
		for _, c in ipairs(e.comp.laneConnections or {}) do
			for _, pr in ipairs({ { c.segment0, c.lane0 }, { c.segment1, c.lane1 } }) do
				local n = lanes[pr[1]] or (edges[pr[1]] and edges[pr[1]].lanes and #edges[pr[1]].lanes) or 4
				if pr[2] < 1 or pr[2] > n - 2 then out[#out + 1] = string.format("node %d: sidewalk lane %d of %d", e.entity, pr[2], pr[1]) end
			end
		end
	end
	return out
end

local function fakeApi()
	local function vec(x, y, z) return { x = x, y = y, z = z } end
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = { BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", BASE_NODE = "BASE_NODE",
				BASE_NODE_CONFIG = "BASE_NODE_CONFIG", TOWN = "TOWN", GAME_SCRIPT = "GAME_SCRIPT",
				BASE_NODE_TRAFFIC_LIGHT = "BASE_NODE_TRAFFIC_LIGHT" },
			SimpleProposal = setmetatable({ ConstructionEntity = { new = function() return {} end } },
				{ __index = { new = function() return { streetProposal = {} } end } }),
			Context = { new = function() return {} end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = vec },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
			Mat4f = { new = function(a, b, c, d) return { a, b, c, d } end },
			NodeAndEntity = { new = function() return { comp = {} } end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			LaneConnection = { new = function() return { ctor = true } end },
			SegmentAndEntity = { new = function() return {} end },
			TrafficLightState = { new = function() return { ctor = true } end },
			enum = { TrafficLightPreference = { YES = 0, NO = 1, AUTO = 2 } },
		},
		res = { streetTemplateRep = {
			find = function(name) return name end,
			-- a template's lanes: two sidewalks + 2 / 4 / 6 road lanes by its size
			get = function(name)
				local n = name:find("_large", 1, true) and 3 or (name:find("_medium", 1, true) and 2 or 1)
				local f = { false }
				for _ = 1, n do f[#f + 1] = false end
				for _ = 1, n do f[#f + 1] = true end
				f[#f + 1] = true
				return { laneConfigs = lanesOf(f), streetStyle = "style:" .. name }
			end,
		}, constructionRep = { find = function(name)
			if name:sub(1, #"square_stress_test::/") == "square_stress_test::/" then return 2 end
		return name:sub(1, #"square_roundabouts::/") == "square_roundabouts::/" and 1 or -1
		end } },
		cmd = {
			sendCommand = function(cmd, cb)
				-- the Smart Lanes zones events go to zoneEvents (with the time and the build count so far)
				if cmd.event then
					zoneEvents[#zoneEvents + 1] = { cmd = cmd, t = T, before = #sent }
					return
				end
				sent[#sent + 1] = { cmd = cmd, cb = cb, t = T }
			end,
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { p = p, ctx = ctx, ignore = ignore, player = player, dust = dust }
			end,
			makeScriptingSendEventCmd = function(src, id, name, param) return { event = true, src = src, id = id, name = name, param = param } end,
		},
		gui = { camera = { getCameraData = function() return { x = 0, y = 0 } end } },
		engine = {
			getComponent = function(e, ct)
				if ct == "GAME_SCRIPT" then
					if e ~= 777 then return nil end
					return { state_native = { find = function(_, k) if k == "zrun" and slZrun then return slZrun() end end } }
				end
				if ct == "BASE_EDGE" then
					local ed = edges[e]
					return ed and { node0 = ed.n0, node1 = ed.n1, tag = "edge" .. e, roadTemplate = ed.template, laneConfigs = ed.lanes,
						roadDevelopmentLocked = ed.locked } or nil
				elseif ct == "BASE_EDGE_STREET" then
					return edges[e] and { tag = "street" .. e } or nil
				elseif ct == "BASE_NODE" then
					local n = nodes[e]
					return n and { position = vec(n.x, n.y, n.z) } or nil
				elseif ct == "BASE_NODE_CONFIG" then
					if not nodes[e] then return nil end
					if cfgOverride[e] then return copyCfg(cfgOverride[e]) end
					local list = node2edges()[e] or {}
					local lit = litNode ~= nil and litNode(e)
					if lit then table.sort(list) end
					local lcs = {}
					for i = 1, #list do
						for j = 1, #list do
							if i ~= j then lcs[#lcs + 1] = { segment0 = list[i], lane0 = 1, segment1 = list[j], lane1 = 2, withRoad = true, withTram = false } end
						end
					end
					local cfg = { laneConnections = lcs, crosswalks = lit and list or { list[1] }, trafficLightPreference = lightPref and lightPref(e) or nil }
					if lit then cfg.trafficLightConfig = fakeLights(e, list, lcs, cfg.crosswalks) end
					if not firstCfg[e] then firstCfg[e] = copyCfg(cfg) end
					return cfg
				end
			end,
			terrain = {
				getHeightAt = function() return 0 end,
				getBoundingBox = function() return box end,
			},
			util = {
				getYear = gameYearV and function() return gameYearV end or nil,
				getPlayer = function() return 7 end,
				finance = { getPlayersBalance = function() return 1e9 end },
				-- the engine's octree matches an edge by its position (the midpoint), not its extent: a small circle
				-- on a node misses its long streets (Lights showcase seed 4951, 2026-10-12: a 15 m search on each
				-- side-middle node found none of its 75 m streets, 96 of 96 entries). An endpoint test hid that.
				octree = { findEntitiesInCircle = function(c, r, ct)
					local out = {}
					for e, ed in pairs(edges) do
						local p0, p1 = nodes[ed.n0], nodes[ed.n1]
						local mx, my = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
						if (mx - c.x) ^ 2 + (my - c.y) ^ 2 <= r * r then out[#out + 1] = e end
					end
					table.sort(out)
					return out
				end },
				proposal = {
					createTrafficLightProposal = function(node, tlc, pref)
						return { streetProposal = {}, lights = { node = node, pref = pref } }
					end,
					makeProposalData = function(p)
						local ce = p.constructionsToAdd and p.constructionsToAdd[1]
						local bad, hits
						if ce then bad, hits = refuseCheck(ce) end
						local ci = nil
						if hits then
							ci = { collisionEntities = {} }
							for k, e in ipairs(hits) do ci.collisionEntities[k] = { entity = e } end
						end
						return { errorState = { critical = bad and true or false, messages = bad and { bad } or {} }, collisionInfo = ci }
					end,
				},
				construction = { getGlobalConstructionParams = function() return { year = 1990 } end },
			},
			config = { getModParams = function() return { square_smart_lanes = slParams, [""] = {} } end },
			system = {
				streetSystem = { getNode2StreetEdgeMap = node2edges },
				gameScriptSystem = { getEntityForGameScript = function(name)
					assert(name == "square_smart_lanes::/smart_lanes/sl_lanes.gs", name)
					return 777
				end },
				streetConnectorSystem = { getConstructionEntityForNode = function() return -1 end },
				-- parcels: parcelsOf[edge] = { left parcels }, buildingOn[parcel] = a town building (stray street checks)
				parcelSystem = { getSegment2ParcelData = function()
					local m = {}
					for e, list in pairs(parcelsOf or {}) do m[e] = { leftEntities = list, rightParcels = {} } end
					return m
				end },
				townBuildingSystem = { getParcel2BuildingMap = function() return buildingOn or {} end },
			},
		},
	}
end

--- Plays the engine for a construction, in world space by its transf: an interchange is a highway
--- (two one-way carriageways along local x, 600 m, 2 x (4 + 3 x its highway size) m apart) and a
--- cross road along local y; a roundabout or plain crossing has one arm per direction of logic.showcaseArms (each turned
--- by twist(ce, deg) degrees when set), 60 m out (a town entry roundabout's: logic.ENTRY_REACH, as the real
--- one), all from one centre node; extraArm(ce) adds an arm that far out along local y.
local function buildJunction(ce)
	local m = ce.transf
	local ux, uy = m[1][1], m[1][2]
	local vx, vy = m[2][1], m[2][2]
	local ox, oy = m[4][1], m[4][2]
	local function at(lx, ly) return newNode(ox + ux * lx + vx * ly, oy + uy * lx + vy * ly) end
	local base = ce.fileName:match("([^/]+)$")
	local extra = extraArm and extraArm(ce)
	if ce.params.sqrb_ix_highway then
		local hg = 4 + 3 * ce.params.sqrb_ix_highway
		-- benchIx (bench tests): the highway and cross road end inside the construction's reach estimate, as built
		local L = benchIx and (logic.showcaseReach({ file = base, params = ce.params }) - 12) or 300
		local w1, c1, e1 = at(-L, -hg), at(0, -hg), at(L, -hg)
		local cw = { newEdge(w1, c1), newEdge(c1, e1) }
		local e2, c2, w2 = at(L, hg), at(0, hg), at(-L, hg)
		cw[3], cw[4] = newEdge(e2, c2), newEdge(c2, w2)
		for _, e in ipairs(cw) do edges[e].lanes = ONE_WAY end
		local cl = benchIx and math.min(150, L) or 150
		local s, c3, n = at(0, -cl), at(0, 0), at(0, cl)
		edges[newEdge(s, c3)].lanes = TWO_WAY
		edges[newEdge(c3, n)].lanes = TWO_WAY
		return
	end
	local arms = logic.showcaseArms({ file = base, params = ce.params })
	if base == logic.ENTRY_FILE then
		-- the entry roundabout as built: four ring nodes at its radius, the ring, an arm from each ring node out along
		-- its axis to the reach (the inward one shorter: stress_entry_streets.inward)
		local geo = ug_require "square_stress_test::/stress/stress_entry_streets.lua"
		local inAxis, inReach = geo.inward(ce.params)
		local rr = geo.ring(ce.params).radius
		local axes = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
		local ring = {}
		for k, ax in ipairs(axes) do ring[k] = at(ax[1] * rr, ax[2] * rr) end
		for k = 1, 4 do edges[newEdge(ring[k], ring[k % 4 + 1])].lanes = ONE_WAY end
		for k, ax in ipairs(axes) do
			local reach = (inAxis == k and inReach) or logic.ENTRY_REACH
			edges[newEdge(ring[k], at(ax[1] * reach, ax[2] * reach))].lanes = TWO_WAY
		end
		return
	end
	local c = at(0, 0)
	local len = base == logic.ENTRY_FILE and logic.ENTRY_REACH or 60
	-- the entry roundabout's shorter inward arm (stress_entry_streets.inward: axis 1..4 = 0, 90, 180, 270 deg)
	local inAxis, inReach
	if base == logic.ENTRY_FILE then
		inAxis, inReach = (ug_require "square_stress_test::/stress/stress_entry_streets.lua").inward(ce.params)
	end
	for k, d in ipairs(arms) do
		local len = (inAxis == k and inReach) or len
		local a = math.rad(d + (twist and twist(ce, d) or 0))
		local e = newEdge(c, at(len * math.cos(a), len * math.sin(a)))
		edges[e].lanes = TWO_WAY
		-- the bench's lane drop (crossing shape 4): the west arm (180 deg) the large road, 3 lanes each way
		if ce.params.sqst_x_shape == 4 and d == 180 and not sameDropLanes then edges[e].lanes = TWO_WAY3 end
	end
	-- a square_roundabouts ring / channelized junction: one-way streets at its centre (the bench's geometry check)
	if benchGeo and base:find("^square_roundabouts") and not noRing then
		local r1, r2, r3 = at(10, 0), at(0, 10), at(-10, 0)
		for _, pr in ipairs({ { r1, r2 }, { r2, r3 }, { r3, r1 } }) do edges[newEdge(pr[1], pr[2])].lanes = ONE_WAY end
		edges[newEdge(c, r1)].lanes = TWO_WAY
	end
	if extra then newEdge(c, at(0, extra)) end
end

--- A town's streets: a "+" from its centre to the middle of each side of its grid (half by its size,
--- 200 m without one): dead ends there, where the square layout's links join.
--- ring (Lights showcase towns): each side's middle also gets the perimeter ring both ways (a 75 m piece to a
--- dead end each side, a Medium grid's block), so it is the 3-street node a town entry roundabout replaces.
local entryLocks     -- towns.lockEdgeList calls (an entry's own streets locked after its build)
local lockRefuse     -- function(label) -> true: that lock is refused (none of its edges locked); nil: none
local lockDelay      -- function(label) -> ms until the lock answers (nil: at once)
local townLanes      -- laneConfigs of the fake towns' streets (nil: none, the driving side unreadable)
local sideShift      -- metres every side-middle node (with its ring pieces) lies outwards of the side's middle (nil: 0)
local function townStreets(points, ring)
	for _, p in ipairs(points) do
		local c = newNode(p.x, p.y)
		townCentres[c] = true
		local h = p.size and logic.gridHalfOfSize(p.size) or 200
		local f = (h + (sideShift or 0)) / h
		for _, d0 in ipairs({ { h, 0 }, { 0, h }, { -h, 0 }, { 0, -h } }) do
			local d = { d0[1] * f, d0[2] * f }
			local m = newNode(p.x + d[1], p.y + d[2])
			edges[newEdge(c, m)].lanes = townLanes
			if ring then
				local ax, ay = d[2] ~= 0 and 1 or 0, d[1] ~= 0 and 1 or 0
				edges[newEdge(m, newNode(p.x + d[1] + 75 * ax, p.y + d[2] + 75 * ay))].lanes = townLanes
				edges[newEdge(m, newNode(p.x + d[1] - 75 * ax, p.y + d[2] - 75 * ay))].lanes = townLanes
			end
		end
	end
end

local rt, jn, gridOpts, failCmd, routeCalls, skipTowns, depotCalls, jlogic
local entryRing      -- Lights showcase towns get the ring at their side middles (a town entry roundabout there); false: crossroads
local benchIx         -- bench tests: interchange arms within the reach estimate (buildJunction)
before_each(function()
	entryRing = true
	benchIx, sameDropLanes, noRing, benchGeo = nil, nil, nil, nil
	townLanes, sideShift = nil, nil
	entryLocks, lockRefuse, lockDelay = {}, nil, nil
	T, sent, nodes, edges, nextId = 0, {}, {}, {}, 1000
	zoneEvents, slParams, slZrun = {}, nil, nil
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	refuseCheck = function() return nil end
	failCmd = nil
	extraArm, twist, afterBuild, lateNodes = nil, nil, nil, nil
	beforeCb = nil
	parcelsOf, buildingOn = nil, nil
	lightPref, gameYearV, growCalls, lockCalls = nil, nil, {}, {}
	litNode, cfgOverride, firstCfg, townCentres = nil, {}, {}, {}
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	gridOpts = nil
	routeCalls = {}
	skipTowns = {}
	depotCalls = {}
	stub_module("square_stress_test::/stress/gui/stress_buslines.tl", {
		addRouteLines = function(name, title, routes)
			routeCalls[#routeCalls + 1] = { name = name, title = title, routes = routes }
			return #routes
		end,
		prebuildDepots = function(name, routes, onDone)
			depotCalls[#depotCalls + 1] = { name = name, routes = routes, onDone = onDone, t = T, grows = #growCalls }
		end,
	})
	stub_module("square_stress_test::/stress/gui/stress_towns.tl", {
		grow = function() error("the Showcase grows through densify") end,
		densify = function(name, areas, opts)
			growCalls[#growCalls + 1] = { factor = opts.factor, target = opts.target, passes = opts.passes, weights = opts.weights, areas = areas, name = name,
				t = T, sent = #sent, onDone = opts.onDone }
		end,
		-- as the engine's lock: every edge swapped for a copy with a new id (same nodes, lanes, template), so the
		-- reads and joins must use fresh ids; lockRefuse(label) -> how many of the edges stay unlocked (refused)
		lockEdgeList = function(name, label, list, done)
			entryLocks[#entryLocks + 1] = { name = name, label = label, list = list, t = T, sent = #sent }
			-- a refused lock refuses its whole batch (one proposal), as the game does
			local bad = (lockRefuse and lockRefuse(label)) and #list or 0
			for _, e in ipairs(list) do
				local ed = edges[e]
				if ed and bad == 0 then
					edges[e] = nil
					nextId = nextId + 1
					edges[nextId] = { n0 = ed.n0, n1 = ed.n1, lanes = ed.lanes, template = ed.template, locked = true }
				end
			end
			-- lockDelay(label): answer that much later (ms; an async build-time lock)
			local delay = lockDelay and lockDelay(label) or nil
			if delay then rt.later("lockstub", delay, function() done(#list - bad, bad) end) else done(#list - bad, bad) end
		end,
		lockTowns = function(name, areas, opts)
			local links = 0
			for _, x in ipairs(sent) do if x.cmd.p.streetProposal.edgesToAdd then links = links + 1 end end
			lockCalls[#lockCalls + 1] = { name = name, areas = areas, opts = opts, t = T, sent = #sent, links = links }
		end,
		createGrid = function(opts, onDone)
			gridOpts = opts
			local pts = logic.gridPositions(0, 0, opts.cols, opts.rows, opts.spacing)   -- the Junction test (busy test)
			if opts.points then
				pts = {}
				for k, q in ipairs(opts.points) do pts[k] = { x = (opts.cx or 0) + q.x, y = (opts.cy or 0) + q.y, name = q.name, size = q.size } end
			end
			-- skipTowns: points that fail the land check (opts.skipNoLand): nothing of them built
			local skipped, live = {}, {}
			for i, p in ipairs(pts) do
				if skipTowns[i] and opts.skipNoLand then skipped[i] = true else live[#live + 1] = p end
			end
			local nm = opts.name or ""
			townStreets(live, entryRing and (nm:sub(1, #"lights_showcase") == "lights_showcase" or nm:sub(1, #"bench_") == "bench_"))
			created = {}
			for i = 1, #pts do
				if not skipped[i] then created[i] = 500 + i end
			end
			onDone(created, pts, skipped)
		end,
	})
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	jn = ug_require "square_stress_test::/stress/gui/stress_junctions.tl"
	-- one link per proposal unless a test groups them (the counts below are per link; "link groups" tests set it)
	jlogic = ug_require "square_stress_test::/stress/stress_logic.tl"
	jlogic.LINK_GROUP_MAX = 1
end)

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.msg end
	return table.concat(out, "\n")
end

local function run(rounds, untilText)
	local seen = 0
	for _ = 1, rounds do
		T = T + 600000
		rt.tick()
		for _, s in ipairs(sent) do
			if not s.answered then
				s.answered = true
				local ce = s.cmd.p.constructionsToAdd and s.cmd.p.constructionsToAdd[1]
				local fail = failCmd ~= nil and failCmd(s.cmd)
				if ce and not fail and not lateNodes then buildJunction(ce) end
				if not fail and beforeCb then beforeCb(s.cmd) end
				s.cb(s.cmd, not fail)
				if ce and not fail and lateNodes then buildJunction(ce) end
				if ce and not fail and afterBuild then afterBuild(ce) end
			end
		end
		if untilText then
			-- only the lines logged since the last look (a full logText() per round grew quadratic with the entries' lines)
			local list = log_entries()
			for k = seen + 1, #list do
				if list[k].msg:find(untilText, 1, true) then return end
			end
			seen = #list
		end
	end
end

local ENTRY_NAME = "SQST Entry roundabout"

--- The junction constructions sent (the Lights showcase's town entry roundabouts left out: entryCons).
local function constructions()
	local out = {}
	for _, s in ipairs(sent) do
		local ce = s.cmd.p.constructionsToAdd and s.cmd.p.constructionsToAdd[1]
		if ce and ce.name ~= ENTRY_NAME then out[#out + 1] = ce end
	end
	return out
end

--- The town entry roundabout proposals sent (Lights showcase).
local function entryCmds()
	local out = {}
	for _, s in ipairs(sent) do
		local ce = s.cmd.p.constructionsToAdd and s.cmd.p.constructionsToAdd[1]
		if ce and ce.name == ENTRY_NAME then out[#out + 1] = s.cmd end
	end
	return out
end

--- Whether a street proposal is a town entry's joins: it replaces an entry roundabout's arm end (ENTRY_REACH
--- from its centre) and adds no new country piece (joins are copies of the roundabout's arm road;
--- a town link's new pieces are country roads).
local function isEntryJoin(sp)
	if #entryCmds() == 0 or not sp.edgesToAdd then return false end
	for _, seg in ipairs(sp.edgesToAdd) do
		if seg.comp.roadTemplate and seg.comp.roadTemplate:find("/country/", 1, true) then return false end
	end
	for _, id in ipairs(sp.nodesToRemove or {}) do
		local p = nodes[id]
		for _, cmd in ipairs(entryCmds()) do
			local r = cmd.p.constructionsToAdd[1].transf[4]
			if p and math.abs(math.sqrt((p.x - r[1]) ^ 2 + (p.y - r[2]) ^ 2) - logic.ENTRY_REACH) < 0.5 then return true end
		end
	end
	return false
end

local function linkCount()
	local n = 0
	for _, s in ipairs(sent) do
		local sp = s.cmd.p.streetProposal
		if sp.edgesToAdd and not isEntryJoin(sp) then n = n + 1 end
	end
	return n
end

--- Links made (one "linked ms=" line each, alone or in a group's proposal), whatever the proposals (entry joins left out).
local function linkedLines()
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find(" linked ms=", 1, true) and not e.msg:find(" entry ", 1, true) then n = n + 1 end
	end
	return n
end


local SEED = 12
local CX, CY = 7000, 6500

--- A 12 x 9 km map (centre 7000, 6500): a few sets of every kind, plain crossings with and without lights; built with seed 12.
local function smallMap()
	box = { min = { x = 1000, y = 2000 }, max = { x = 13000, y = 11000 } }
	return logic.showcaseLayout(12000, 9000, 400, SEED)
end

--- Wraps rt.later: every delayed step queued, with its name, delay and the time (T) it was queued.
local function recordLater()
	local calls = {}
	local later = rt.later
	rt.later = function(name, ms, fn)
		calls[#calls + 1] = { name = name, ms = ms, t = T }
		return later(name, ms, fn)
	end
	return calls
end

--- The rt.later calls named `name`, and the names of all the others.
local function laterNamed(calls, name)
	local hit, other = {}, {}
	for _, c in ipairs(calls) do
		if c.name == name then hit[#hit + 1] = c else other[#other + 1] = c.name end
	end
	return hit, other
end

local function townTotal(L)
	local n = 0
	for _, g in ipairs(L.groups) do n = n + #g.towns end
	return n
end

--- The first group of a kind.
local function firstOf(L, kind)
	for gi, g in ipairs(L.groups) do
		if g.kind == kind then return g, gi end
	end
end

--- The params of a construction entity without the global ones (year, seed).
local function ownParams(ce)
	local p = {}
	for k, v in pairs(ce.params) do if k:sub(1, 5) == "sqrb_" or k:sub(1, 5) == "sqst_" then p[k] = v end end
	return logic.showcaseParamText({ params = p })
end

--- The map position of a construction entity's transf (Mat4f of Vec4f rows, the fake api's tables).
local function cePos(ce)
	local r = ce.transf[4] or ce.transf
	return r.x or r[1], r.y or r[2]
end

local function at(ce, g)
	local x, y = cePos(ce)
	return math.abs(x - CX - g.place.x) < 1 and math.abs(y - CY - g.place.y) < 1
end

test("Showcase: Keep balance on, towns with their sizes, every group's junction once (+0), every arm linked, zones, bus lines", function()
	local L = smallMap()
	local n, nTowns, by = logic.showcaseCounts(L)
	ok(by.ix > 0 and by.rb > 0 and by.plain > 0)
	ok(not rt.keepBalance)
	jn.buildShowcase(SEED)
	ok(rt.keepBalance, "the build turns Keep balance on")
	ok(logText():find("[SQST] showcase keep_balance=on (was off)", 1, true), logText())
	eq(#gridOpts.points, nTowns)
	for k, p in ipairs(gridOpts.points) do eq(p.size, L.towns[k].size) end
	eq(gridOpts.connect, 1)
	eq(gridOpts.streets, 3, "the grid built locked")
	eq(gridOpts.cx, CX)
	eq(gridOpts.cy, CY)
	run(3000, "Showcase done")
	local cons = constructions()
	eq(#cons, n)
	for k, ce in ipairs(cons) do
		for _, row in ipairs(ce.transf) do
			for _, v in ipairs(row) do ok(1 / v ~= -math.huge, "no -0 in transform " .. k) end
		end
		eq(ce.params.year, 1990, "global params")
		local g = L.groups[k]
		ok(at(ce, g), "layout order: " .. g.name)
		eq(ownParams(ce), logic.showcaseParamText(g.place.case_), g.name)
		if g.kind == "plain" then
			ok(ce.fileName == "square_stress_test::/infrastructure/street_construction/square_stress_test_crossing.con", ce.fileName)
		else
			ok(ce.fileName:find("^square_roundabouts::/infrastructure/street_construction/"), ce.fileName)
		end
	end
	eq(linkCount(), nTowns, "one link per town")
	local all = logText()
	ok(all:find(string.format("showcase summary seed=12 groups=%d built=%d refused=0 interchanges=%d/%d roundabouts=%d/%d plain=%d/%d ", n, n,
		by.ix, by.ix, by.rb, by.rb, by.plain, by.plain), 1, true), all)
	ok(all:find(string.format(" links=%d linked=%d unlinked=0", nTowns, nTowns), 1, true), all)
	ok(all:find("[SQST] Showcase done: ", 1, true) and all:find(" Seed 12.", 1, true), all)
	ok(all:find(string.format("showcase: seed=12 map=12000x9000m groups=%d ", n), 1, true), all)
	-- one zone line per group (its A/B mode) and one built line per group
	local zones = 0
	for line in all:gmatch("[^\n]+") do
		local id, pair, ab = line:match("%[SQST%] showcase zone id=(g%d+%a) pair=(g%d+) ab=(%S+) kind=")
		if id then
			zones = zones + 1
			eq(pair, id:sub(1, -2))
			ok(ab == "sl" or ab == "game" or ab == "sl_phases", ab)
			ok(line:find(" r_from=measured towns=", 1, true), line)
		end
	end
	eq(zones, n)
	local _, built = all:gsub("%[SQST%] showcase Group %d+%a [^\n]* built ms=", "")
	eq(built, n)
	ok(all:find("Group 1a Roundabout Interchange at ", 1, true), all)
	eq(#rt.warnings, 0)
	-- bus lines always, across every group, the same pairs in every twin
	run(20)
	eq(#routeCalls, 1)
	eq(routeCalls[1].name, "bus_lines_showcase")
	local linked = {}
	for gi, g in ipairs(L.groups) do
		linked[gi] = {}
		for k = 1, #g.towns do linked[gi][k] = true end
	end
	local want = logic.showcaseRoutes(L, linked, logic.TEST_ROUTES_MAX)
	eq(#routeCalls[1].routes, #want)
	local zoneList = logic.showcaseZones(L)
	for k, r in ipairs(routeCalls[1].routes) do
		eq({ r.a.id, r.b.id }, { 500 + want[k][1], 500 + want[k][2] })
		eq(r.net, "group " .. want[k][3])
		-- stops and depots stay on each town's own street grid and out of every junction zone
		eq(r.a.half, logic.gridHalfOfSize(L.towns[want[k][1]].size))
		eq(r.b.half, logic.gridHalfOfSize(L.towns[want[k][2]].size))
		eq(#r.zones, #zoneList)
		ok(type(r.zones[1][1]) == "number" and r.zones[1][3] > 0, "zones are {x, y, r}")
	end
	ok(all:find(string.format("; %d bus lines queued", #want), 1, true), all)
end)

test("Showcase: town streets locked: grid built locked, a lock pass after the towns and one after the links (stubs), every link edge locked, then the growth", function()
	local L = smallMap()
	local _, nTowns = logic.showcaseCounts(L)
	jn.buildShowcase(SEED)
	eq(gridOpts.streets, 3)
	-- pass 1: queued with the towns, before any junction or link
	eq(#lockCalls, 1)
	eq({ lockCalls[1].name, lockCalls[1].opts.pass, lockCalls[1].opts.stubs or false, lockCalls[1].sent }, { "showcase_lock", "towns", false, 0 })
	eq(#lockCalls[1].areas, nTowns)
	for k, a in ipairs(lockCalls[1].areas) do
		eq(a.town, 500 + k)
		eq({ a.x, a.y }, { gridOpts.points[k].x + CX, gridOpts.points[k].y + CY })
		eq(a.half, logic.gridHalfOfSize(L.towns[k].size))
		eq(a.label, L.towns[k].name)
	end
	run(3000, "Showcase done")
	-- every edge a link adds goes out locked, with complete node configs
	local links = 0
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd then
			links = links + 1
			for _, seg in ipairs(sp.edgesToAdd) do eq(seg.comp.roadDevelopmentLocked, true, "link " .. links) end
			eq(cfgProblems(sp), {}, "link " .. links)
		end
	end
	eq(links, nTowns)
	-- pass 2 after the last link, with the stubs; then the growth (level weights, x10 in 3 passes)
	eq(#lockCalls, 2)
	eq({ lockCalls[2].opts.pass, lockCalls[2].opts.stubs, lockCalls[2].links }, { "links", true, nTowns })
	eq(#growCalls, 1)
	eq({ growCalls[1].name, growCalls[1].factor, growCalls[1].passes }, { "showcase_grow", 10, 3 })
	eq(growCalls[1].weights, logic.DENSE_WEIGHTS)
	eq(#growCalls[1].areas, nTowns)
	ok(lockCalls[2].sent <= growCalls[1].sent)
	ok(logText():find(string.format("[SQST] showcase grow queued towns=%d factor=x10 passes=3 weights={0,0.1,0.5,1} locked=true", nTowns), 1, true), logText())
end)

test("Showcase: a town skipped for want of land is in neither lock pass nor the growth", function()
	smallMap()
	skipTowns[2] = true
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	for _, c in ipairs(lockCalls) do
		for _, a in ipairs(c.areas) do ok(a.town ~= 502, c.opts.pass) end
	end
	for _, a in ipairs(growCalls[1].areas) do ok(a.town ~= 502) end
end)

test("Showcase: twins are built back to back with identical params and construction seeds", function()
	local L = smallMap()
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local cons = constructions()
	for k = 2, #cons do
		local g, p = L.groups[k], L.groups[k - 1]
		if g.set == p.set then
			eq(ownParams(cons[k]), ownParams(cons[k - 1]), g.name)
			eq(cons[k].params.seed, cons[k - 1].params.seed, g.name .. " construction seed")
			eq(cons[k].transf[1], cons[k - 1].transf[1], g.name .. " rotation")
			ok(not at(cons[k], p), "its own spot")
		else
			ok(cons[k].params.seed ~= cons[k - 1].params.seed)
		end
	end
end)

test("Showcase: Keep balance already on is logged as such; no up-front money dialog", function()
	smallMap()
	local bls = ug_require "square_stress_test::/stress/gui/stress_buslines.tl"
	bls.moneyWarning = function() return "Keep balance is off." end
	rt.keepBalance = true
	jn.buildShowcase(SEED)
	ok(logText():find("[SQST] showcase keep_balance=on (was on)", 1, true), logText())
	run(3000, "Showcase done")
	for _, w in ipairs(rt.warnings) do ok(not w.body:find("Keep balance is off", 1, true), w.body) end
end)

test("Showcase seed: a fresh one per press (logged); a given seed builds that layout", function()
	smallMap()
	jn.buildShowcase()
	local first = jn.lastSeed
	ok(first ~= nil and first >= 1 and first <= 999999)
	ok(logText():find("showcase: seed=" .. first .. " ", 1, true), logText())
	eq(jn.showcaseSignature(), tostring(first))
	run(3000, "Showcase done")
	run(20)
	jn.buildShowcase()
	ok(jn.lastSeed ~= first, "a new seed per press")
	run(3000, "Seed " .. jn.lastSeed .. ".")
	run(20)
	jn.buildShowcase(4242)
	eq(jn.lastSeed, 4242)
	ok(logText():find("showcase: seed=4242 ", 1, true))
end)

test("Showcase: a placement refused by the check is left out (no move); its towns stay unlinked, the dialog lists it", function()
	local L = smallMap()
	local n, nTowns = logic.showcaseCounts(L)
	local victim = L.groups[3]
	local checks = 0
	refuseCheck = function(ce)
		if at(ce, victim) then
			checks = checks + 1
			return "Collision"
		end
		return nil
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	eq(checks, 1, "a group gets no second chance after a collision")
	eq(#constructions(), n - 1)
	local all = logText()
	ok(all:find(victim.name .. " " .. victim.place.case_.label .. " at [^\n]* refused by the check: Collision"), all)
	ok(not all:find("moved ", 1, true), all)
	ok(all:find(string.format(" refused=1 "), 1, true), all)
	ok(all:find(string.format(" links=%d linked=%d unlinked=0", nTowns - #victim.towns, nTowns - #victim.towns), 1, true), all)
	ok(not all:find("zone id=g" .. victim.set .. victim.twin .. " ", 1, true), "no zone for a refused placement")
	eq(#rt.warnings, 1)
	ok(rt.warnings[1].body:find("Showcase done: ", 1, true), rt.warnings[1].body)
	ok(rt.warnings[1].body:find(victim.name .. " " .. victim.place.case_.label .. ": Collision", 1, true), rt.warnings[1].body)
	-- the twin of the refused one loses its routes too (identical routes in every twin)
	run(20)
	for _, r in ipairs(routeCalls[1].routes) do
		local gi = tonumber(r.net:match("group (%d+)"))
		ok(L.groups[gi].set ~= victim.set, "no route in the refused one's set")
	end
end)

test("Showcase: a Collision names the other entities by component type, probing at most 20 of them", function()
	local L = smallMap()
	local victim = L.groups[2]
	refuseCheck = function(ce)
		if at(ce, victim) then
			local ids = {}
			for id in pairs(nodes) do
				if #ids < 25 then ids[#ids + 1] = id end
			end
			table.sort(ids)
			ids[#ids + 1] = 987654321
			return "Collision", ids
		end
		return nil
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("Collision %(hits 20 other BASE_NODE e%.g%. #%d+, 6 other e%.g%. #%d+%)") ~= nil, all)
end)

test("Showcase: a placement refused with Construction Not Possible is redrawn once; its twins stay identical", function()
	local L = smallMap()
	local n = logic.showcaseCounts(L)
	local g = L.groups[1]
	local want = logic.showcaseParamText(g.place.case_)
	local seen = 0
	refuseCheck = function(ce)
		if ownParams(ce) == want then
			seen = seen + 1
			return "Construction Not Possible"
		end
		return nil
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	ok(seen >= 2, "both twins refused once")
	eq(#constructions(), n, "every placement built (redrawn)")
	local all = logText()
	local _, k = all:gsub("refused by the check: Construction Not Possible; redrawn", "")
	ok(k >= 2, all)
	ok(all:find("(redrawn) built ms=", 1, true), all)
	ok(all:find(" refused=0 ", 1, true), all)
	ok(all:find(" unlinked=0", 1, true), all)
	local cons = constructions()
	eq(ownParams(cons[1]), ownParams(cons[2]), "the twins' redraws are the same")
	ok(ownParams(cons[1]) ~= want)
	-- both twins redrawn the same way: still a match
	ok(all:find("showcase zone id=g1a pair=g1 [^\n]* match=yes"), all)
	ok(all:find("showcase zone id=g1b pair=g1 [^\n]* match=yes"), all)
	ok(all:find(" sets_mismatch=0", 1, true), all)
end)

--- The zone lines of a run: id -> the line.
local function zoneLines(all)
	local out = {}
	for line in all:gmatch("[^\n]+") do
		local id = line:match("%[SQST%] showcase zone id=(g%d+%a) ")
		if id then out[id] = line end
	end
	return out
end

test("Showcase: one twin redrawn, its sibling built with the original draw -> the whole set match=no reason=redrawn", function()
	local L = smallMap()
	local n = logic.showcaseCounts(L)
	local g = L.groups[1]
	local want = logic.showcaseParamText(g.place.case_)
	local seen = 0
	refuseCheck = function(ce)
		if ownParams(ce) == want then
			seen = seen + 1
			if seen == 1 then return "Construction Not Possible" end   -- twin a only
		end
		return nil
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	eq(#constructions(), n)
	local cons = constructions()
	ok(ownParams(cons[1]) ~= ownParams(cons[2]), "twin a redrawn, twin b original")
	eq(ownParams(cons[2]), want)
	local all = logText()
	local Z = zoneLines(all)
	local nZ = 0
	for id, line in pairs(Z) do
		nZ = nZ + 1
		if id:match("^g1%a$") then
			ok(line:find(" match=no reason=redrawn$"), line)
		else
			ok(line:find(" match=yes$"), line)
		end
	end
	eq(nZ, n)
	ok(Z.g1a and Z.g1b, all)
	ok(all:find(" sets_mismatch=1", 1, true), all)
	ok(all:find(" unlinked=0", 1, true), all)
end)

test("Showcase: a town without land is skipped, the build goes on; its set match=no reason=town, that arm pair's bus line dropped in every twin", function()
	local L = smallMap()
	local n, nTowns = logic.showcaseCounts(L)
	-- the first town of group 1 (twin a of set 1)
	local g1 = L.groups[1]
	local lostTi = g1.towns[1]
	skipTowns = { [lostTi] = true }
	ok(not rt.keepBalance)
	jn.buildShowcase(SEED)
	ok(rt.keepBalance, "Keep balance on either way")
	eq(gridOpts.skipNoLand, true, "the Showcase asks createGrid to skip, not cancel")
	run(3000, "Showcase done")
	eq(#constructions(), n, "every junction built")
	eq(linkCount(), nTowns - 1, "every town but the skipped one linked")
	local all = logText()
	ok(all:find(string.format(" links=%d linked=%d unlinked=0 towns_skipped=1 sets_mismatch=1", nTowns - 1, nTowns - 1), 1, true), all)
	ok(all:find(", 1 town skipped (no land)", 1, true), all)
	ok(not all:find("towns without an arm", 1, true), all)
	local Z = zoneLines(all)
	for id, line in pairs(Z) do
		if id:match("^g1%a$") then
			ok(line:find(" match=no reason=town$"), line)
		else
			ok(line:find(" match=yes$"), line)
		end
	end
	ok(Z.g1a:find(string.format(" towns=%d ", #g1.towns - 1), 1, true), Z.g1a)
	ok(Z.g1b:find(string.format(" towns=%d ", #g1.towns), 1, true), Z.g1b)
	ok(all:find("towns=" .. (#g1.towns - 1) .. " reached=" .. (#g1.towns - 1) .. " skipped=1", 1, true), all)
	-- the dialog lists the skipped town
	eq(#rt.warnings, 1)
	ok(rt.warnings[1].body:find("1 town skipped: no land (" .. L.towns[lostTi].name .. ")", 1, true), rt.warnings[1].body)
	-- bus lines: no line to the arm pair of the lost town's position in any twin of set 1, the rest as before
	run(20)
	eq(#routeCalls, 1)
	local linked = {}
	for gi, g in ipairs(L.groups) do
		linked[gi] = {}
		for k = 1, #g.towns do linked[gi][k] = true end
	end
	linked[1][1] = nil
	local want = logic.showcaseRoutes(L, linked, logic.TEST_ROUTES_MAX)
	eq(#routeCalls[1].routes, #want)
	for k, r in ipairs(routeCalls[1].routes) do
		eq({ r.a.id, r.b.id }, { 500 + want[k][1], 500 + want[k][2] })
	end
	local set1 = {}
	for gi, g in ipairs(L.groups) do
		if g.set == 1 then set1[gi] = true end
	end
	for _, r in ipairs(want) do
		if set1[r[3]] then
			local g = L.groups[r[3]]
			ok(r[1] ~= g.towns[1] and r[2] ~= g.towns[1], "no route at position 1 in " .. g.name)
		end
	end
end)

test("Showcase: a refused link is sent again a few seconds later", function()
	smallMap()
	local failed = 0
	failCmd = function(cmd)
		local sp = cmd.p.streetProposal
		if sp and sp.edgesToAdd and failed < 2 then
			failed = failed + 1
			return true
		end
		return false
	end
	local calls = recordLater()
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	eq(failed, 2)
	local relinks = laterNamed(calls, "showcase:relink")
	eq(#relinks, 2, "each refusal retried once, 3 s later")
	for _, c in ipairs(relinks) do eq(c.ms, 3000) end
	eq(#laterNamed(calls, "showcase:settle"), 1)
	local all = logText()
	ok(all:find("link refused (", 1, true) and all:find("trying again in 3 s (2/3)", 1, true), all)
	ok(all:find(" unlinked=0", 1, true), all)
end)

--- A fake answer refused with the given message (errText reads it).
local function refuse(cmd, msg)
	cmd.resultProposalData = { errorState = { critical = false, messages = { msg } } }
	return true
end

--- Whether a link proposal replaces a node within r of (x, y) (map coordinates).
local function touches(cmd, x, y, r)
	local sp = cmd.p.streetProposal
	if not sp or not sp.nodesToRemove or cmd.p.constructionsToAdd then return false end
	for _, id in ipairs(sp.nodesToRemove) do
		local p = nodes[id]
		if p and (p.x - x) ^ 2 + (p.y - y) ^ 2 < r * r then return true end
	end
	return false
end

test("Showcase: a town link refused with a collision takes the nearest node, along the arm first", function()
	local L = smallMap()
	local g = firstOf(L, "rb")
	local town = L.towns[g.towns[1]]
	local tries = 0
	failCmd = function(cmd)
		-- the fake town's dead ends lie at its grid half (Medium: 300 m) from its centre
		if touches(cmd, CX + town.x, CY + town.y, logic.gridHalfOfSize(town.size) + 50) and touches(cmd, CX + g.place.x, CY + g.place.y, 100) then
			tries = tries + 1
			if tries == 1 then return refuse(cmd, "Collision") end
		end
		return false
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("-> " .. town.name .. ": link refused (critical=false messages={Collision}); trying again in 3 s (2/3)", 1, true), all)
	ok(all:find("-> " .. town.name .. " linked ms=0 (nearest town node, 60m along the arm first)", 1, true), all)
	ok(all:find(" unlinked=0", 1, true), all)
end)

test("Showcase: a town link refused every time leaves that town unlinked; the rest goes on", function()
	local L = smallMap()
	local g = L.groups[1]
	local town = L.towns[g.towns[2]]
	failCmd = function(cmd) return touches(cmd, CX + town.x, CY + town.y, 350) end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("-> " .. town.name .. ": link refused 3 times", 1, true), all)
	ok(all:find(" unlinked=1", 1, true), all)
end)

test("Showcase groups: towns matched to the arms' measured directions; a town without an arm within 60 deg takes the nearest free one", function()
	local L = smallMap()
	local nTowns = townTotal(L)
	local g = firstOf(L, "rb")
	local first = logic.showcaseArms(g.place.case_)[1]
	twist = function(ce, d)
		if at(ce, g) and d == first then return 140 end
		return 0
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("has no arm within 60 deg; linked to the nearest free arm (", 1, true), all)
	ok(all:find(string.format("towns=%d reached=%d (1 by the nearest arm)", #g.towns, #g.towns), 1, true), all)
	ok(all:find(string.format(" links=%d linked=%d unlinked=0", nTowns, nTowns), 1, true), all)
end)

test("Showcase: interchange highway arms reach their towns as carriageway pairs merging into one street", function()
	local L = smallMap()
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local _, n = logic.showcaseCounts(L)
	local _, _, by = logic.showcaseCounts(L)
	-- the fake: each interchange has two highway arms (2 ends each); a pair link replaces both ends and the town node
	local pairLinks = 0
	for _, s in ipairs(sent) do
		local sp = s.cmd.p.streetProposal
		if sp.edgesToAdd and sp.nodesToRemove and #sp.nodesToRemove == 3 then pairLinks = pairLinks + 1 end
	end
	eq(pairLinks, 2 * by.ix)
	ok(n > 0)
	-- every link (to towns, carriageway pairs) gives each node it adds or touches a config
	local nLinks = 0
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd then
			nLinks = nLinks + 1
			eq(cfgProblems(sp), {}, "link " .. nLinks)
		end
	end
	ok(nLinks > 0)
end)

test("Showcase: footprints are measured after each build and logged with the estimate", function()
	local L = smallMap()
	local g = firstOf(L, "rb")
	extraArm = function(ce)
		if at(ce, g) then return 150 end
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find(string.format("%s %s at [^\n]*reach est=%dm measured=162m", g.name, g.place.case_.label:gsub("%p", "%%%0"), g.place.reach)), all)
	ok(all:find("[SQST] showcase reach: Roundabout Interchange ", 1, true), all)
	ok(all:find(" over the estimate (worst ", 1, true), all)
	ok(all:find("zone id=g" .. g.set .. g.twin .. " [^\n]* r=162 r_from=measured"), all)
end)

test("Showcase: nodes not visible at the build callback are measured at the read (later builds' nodes left out)", function()
	local L = smallMap()
	lateNodes = true
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("measured=72m (at the read)", 1, true), all)
	ok(all:find(" unlinked=0", 1, true), all)
	ok(not all:find("measured=?", 1, true), all)
	local _, n = all:gsub("%(at the read%)", "")
	eq(n, #L.groups)
end)

test("Showcase: arm ends count only within the measured footprint (town streets grown before the read are left out)", function()
	local L = smallMap()
	local g = firstOf(L, "rb")
	afterBuild = function(ce)
		if at(ce, g) then
			local x, y = cePos(ce)
			newEdge(newNode(x, y - 100), newNode(x, y - 400))
		end
	end
	ok(g.place.reach + 40 > 100)
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local arms = #logic.showcaseArms(g.place.case_)
	local all = logText()
	ok(all:find(string.format("%s %s at [^\n]* ends=%d arms=%d towns=", g.name, g.place.case_.label:gsub("%p", "%%%0"), arms, arms)), all)
	ok(all:find(" unlinked=0", 1, true), all)
end)

test("Showcase: an error reading a placement's arms still finishes its step (no serial timeout)", function()
	local L = smallMap()
	local lg = ug_require "square_stress_test::/stress/stress_logic.tl"
	local assign, thrown = lg.assignArms, false
	lg.assignArms = function(...)
		if not thrown then
			thrown = true
			error("boom")
		end
		return assign(...)
	end
	jn.buildShowcase(SEED)
	run(400, "Showcase done")
	lg.assignArms = assign
	local all = logText()
	ok(thrown)
	ok(all:find("arms error: ", 1, true), all)
	ok(all:find(string.format(" built=%d ", #L.groups), 1, true), all)
	ok(all:find("Showcase done", 1, true), "done within 400 rounds of 0.6 s, before the 120 s timeout")
end)

test("Showcase: placements back to back, exactly one settle, then the arms read and linked", function()
	local L = smallMap()
	local calls = recordLater()
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local settles, other = laterNamed(calls, "showcase:settle")
	eq(#settles, 1)
	eq(settles[1].ms, 3000)
	local others = {}
	for _, o in ipairs(other) do if o ~= "showcase:traffic" then others[#others + 1] = o end end
	eq(others, {}, "no wait per placement, no refused link")
	local lastBuild, firstLink
	for k, x in ipairs(sent) do
		if x.cmd.p.constructionsToAdd then
			ok(firstLink == nil, "construction " .. k .. " after a link")
			if lastBuild then ok(x.t - sent[lastBuild].t <= 600000, "back to back: " .. (x.t - sent[lastBuild].t)) end
			lastBuild = k
		elseif firstLink == nil and x.cmd.p.streetProposal.edgesToAdd then
			firstLink = k
		end
	end
	eq(#constructions(), #L.groups)
	ok(settles[1].t >= sent[lastBuild].t, "the settle after the last build")
	ok(sent[firstLink].t - sent[lastBuild].t >= 3000000, "first link 3 s after the last build")
	local text = logText()
	local settleAt = text:find(string.format("showcase: %d junctions built; reading their arms in 3 s", #L.groups), 1, true)
	ok(settleAt ~= nil, text)
	ok(text:find("built ms=", 1, true) > settleAt, "arms read after the settle")
end)

test("Showcase: neighbours closer than their scan circles each keep their own arms", function()
	smallMap()
	local jl = ug_require "square_stress_test::/stress/stress_logic.tl"
	local layout = jl.showcaseLayout
	local moved = 0
	jl.showcaseLayout = function(...)
		local L = layout(...)
		-- every roundabout / plain group squeezed 150 m apart from the first one (interchanges stay)
		local x0, y0
		for _, g in ipairs(L.groups) do
			if g.kind ~= "ix" then
				if x0 == nil then x0, y0 = g.place.x, g.place.y end
				g.place = { case_ = g.place.case_, x = x0 + 150 * moved, y = y0, angle = g.place.angle, reach = 30, lightsOff = g.place.lightsOff }
				moved = moved + 1
			end
		end
		return L
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	jl.showcaseLayout = layout
	ok(moved >= 3, moved)
	local seen = 0
	for line in logText():gmatch("[^\n]+") do
		if line:find("showcase Group %d+%a .- built ms=") and not line:find("Interchange", 1, true) and not line:find("Parclo", 1, true)
			and not line:find("Diamond", 1, true) then
			seen = seen + 1
			local nn, ends = line:match("nodes=(%d+) ends=(%d+)")
			eq(tonumber(nn), tonumber(ends) + 1, line)
		end
	end
	eq(seen, moved)
end)

test("Showcase: the read logs how many of its new nodes the build's resultEntities named", function()
	smallMap()
	jn.buildShowcase(SEED)
	for _ = 1, 3000 do
		T = T + 600000
		rt.tick()
		for _, x in ipairs(sent) do
			if not x.answered then
				x.answered = true
				local ce = x.cmd.p.constructionsToAdd and x.cmd.p.constructionsToAdd[1]
				local res = {}
				local first = nextId
				if ce then buildJunction(ce) end
				for id = first + 1, nextId do res[#res + 1] = { id, 1 } end
				x.cb(x.cmd, true, res)
			end
		end
		if logText():find("Showcase done", 1, true) then break end
	end
	local seen = 0
	for line in logText():gmatch("[^\n]+") do
		if line:find("built ms=", 1, true) and line:find("showcase ", 1, true) then
			seen = seen + 1
			local nn, inRes = line:match("nodes=(%d+) .- res_nodes=(%d+)")
			eq(inRes, nn, line)
		end
	end
	ok(seen > 0)
end)

test("Showcase: nothing built -> no settle, no links, no bus lines", function()
	smallMap()
	refuseCheck = function() return "Collision" end
	local calls = recordLater()
	jn.buildShowcase(SEED)
	run(400, "Showcase done")
	eq(#laterNamed(calls, "showcase:settle"), 0)
	eq(#constructions(), 0)
	eq(linkCount(), 0)
	local all = logText()
	ok(all:find(" built=0 ", 1, true), all)
	ok(all:find("no bus lines", 1, true), all)
end)

test("Showcase: the lights go off at plain crossings drawn without lights, nowhere else", function()
	local L = smallMap()
	local want = 0
	for _, g in ipairs(L.groups) do if g.place.lightsOff then want = want + 1 end end
	ok(want > 0, "seed 12 has an unlit plain crossing")
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local n = 0
	for _, x in ipairs(sent) do if x.cmd.p.lights then n = n + 1 end end
	-- the fake: one junction node per crossing
	eq(n, want)
	local all = logText()
	ok(all:find("lights=off [", 1, true) and all:find(" lights off at 1", 1, true), all)
end)

test("Showcase: nothing fits a tiny map -> a warning, no towns, Keep balance untouched", function()
	box = { min = { x = 0, y = 0 }, max = { x = 1500, y = 1500 } }
	jn.buildShowcase()
	eq(gridOpts, nil)
	eq(#rt.warnings, 1)
	ok(rt.warnings[1].body:find("Nothing fits this map", 1, true), rt.warnings[1].body)
	ok(not rt.keepBalance)
end)

test("Showcase: constructions missing -> a warning, nothing built", function()
	api.res.constructionRep.find = function() return -1 end
	jn.buildShowcase()
	eq(gridOpts, nil)
	ok(rt.warnings[1].body:find("Constructions not found", 1, true))
end)

test("busy: the Showcase refuses while a test runs, the other tests refuse while it runs", function()
	smallMap()
	jn.buildShowcase(SEED)
	jn.build()
	jn.buildCrossings()
	jn.buildShowcase(SEED)
	local all = logText()
	ok(all:find("Junction test: A test is already running (showcase", 1, true), all)
	ok(all:find("Crossing test: A test is already running (showcase", 1, true), all)
	ok(all:find("Showcase: A test is already running (showcase", 1, true), all)
	run(3000, "Showcase done")
	run(20)
	jn.ui.set = 2
	jn.build()
	jn.buildShowcase(SEED)
	all = logText()
	ok(all:find("Showcase: A test is already running (", 1, true), all)
end)

test("clean-up: every Showcase town is a test town (Remove towns > Grid towns)", function()
	local L = logic.showcaseLayout(MAP, MAP, MARGIN, 1)
	for _, t in ipairs(L.towns) do ok(logic.isTestTownName(t.name), t.name) end
	ok(#L.towns > 40)
	for _, t in ipairs(logic.showcaseLayout(MAP, MAP, MARGIN, 1, logic.lightsSpec(4)).towns) do ok(logic.isTestTownName(t.name), t.name) end
end)

test("town names say the test: Showcase '<type> <set> <side> (<mode>)', Lights showcase '<mode> <set> <side>'; unique, short", function()
	eq(logic.compassOf(90), "N")
	eq(logic.compassOf(0), "E")
	eq(logic.compassOf(270), "S")
	eq(logic.compassOf(180), "W")
	eq(logic.compassOf(-90), "S")
	eq(logic.compassOf(45), "NE")
	eq(logic.compassOf(225), "SW")
	eq(logic.compassOf(375), "E", "15 deg off east")
	eq(logic.compassOf(112), "N", "22 deg off north")
	-- Lights showcase: every twin's mode, N / E / S / W of its crossing (a T: E, N, W)
	local words = { sl = "Smart lanes", game = "Game default", sl_phases = "Smart phases", sl_lock = "Kerb locked" }
	for k, sides in ipairs({ { "E", "N", "W", "S" }, [4] = { "E", "N", "W" } }) do
		local L = logic.showcaseLayout(MAP, MAP, MARGIN, 12, logic.lightsSpec(k))
		local g = L.groups[1]
		for i, ti in ipairs(g.towns) do eq(L.towns[ti].name, string.format("%s 1 %s", words[g.ab], sides[i])) end
		for _, gg in ipairs(L.groups) do
			for i, ti in ipairs(gg.towns) do
				local t = L.towns[ti]
				eq(t.name, string.format("%s %d %s", words[gg.ab], gg.set, sides[i]))
				-- the side is where the town really lies (map +y north, +x east)
				local dx, dy = t.x - gg.place.x, t.y - gg.place.y
				eq(t.name:sub(-1), dy > 0 and "N" or dy < 0 and "S" or dx > 0 and "E" or "W")
			end
		end
	end
	eq(logic.showcaseLayout(MAP, MAP, MARGIN, 12, logic.lightsSpec(1)).towns[1].name, "Smart lanes 1 E")
	-- Showcase: the type's short word, the set, the compass point the arm points to, the twin's mode
	for _, seed in ipairs({ 1, 777, 4242 }) do
		local L = logic.showcaseLayout(MAP, MAP, MARGIN, seed)
		local seen = {}
		for _, g in ipairs(L.groups) do
			local t0 = g.place.case_
			local short
			for _, list in ipairs({ logic.SHOWCASE_IX_TYPES, logic.SHOWCASE_RB_TYPES, logic.SHOWCASE_PLAIN_TYPES }) do
				for _, ty in ipairs(list) do if ty.id == t0.id then short = ty.short end end
			end
			ok(short ~= nil, t0.id .. " has a short word")
			local arms = logic.showcaseArms(t0)
			local rot = math.deg(g.place.angle)
			for i, ti in ipairs(g.towns) do
				local t = L.towns[ti]
				eq(t.name, string.format("%s %d %s (%s)", short, g.set, logic.compassOf(rot + arms[i]), words[g.ab]))
				ok(#t.name <= 31, t.name .. ": short")
				ok(not seen[t.name], t.name .. " unique")
				seen[t.name] = true
			end
		end
	end
	-- every Showcase type has its short word, at most 10 characters
	for _, list in ipairs({ logic.SHOWCASE_IX_TYPES, logic.SHOWCASE_RB_TYPES, logic.SHOWCASE_PLAIN_TYPES }) do
		for _, ty in ipairs(list) do ok(ty.short ~= nil and #ty.short <= 10, ty.id) end
	end
end)

test("the build step stays well within Lua 5.1's 60 upvalues per function", function()
	smallMap()
	local captured = {}
	local enqueue = rt.enqueue
	rt.enqueue = function(name, total, step, opts)
		captured[name] = step
		return enqueue(name, total, step, opts)
	end
	jn.buildShowcase(SEED)
	local step = captured.showcase
	ok(step ~= nil)
	-- Lua 5.4 counts _ENV as an upvalue too (5.1 reads globals without one), so this is one above the
	-- game's count. The hard limit is 60; keep 10 spare so a later edit can't reach it unnoticed
	-- (move state into the run's table `s`, or helpers out of the step, before raising this).
	local n = debug.getinfo(step, "u").nups
	local names = {}
	for k = 1, n do names[k] = debug.getupvalue(step, k) end
	ok(n <= 50, "upvalues: " .. n .. " (" .. table.concat(names, " ") .. ")")
end)

---------------------------------------------------------------------------
-- The twin zones to Smart Lanes (stress_slzones.tl; Smart Lanes sl_zones.lua receives them)

--- Smart Lanes' own validation (its pure module, loaded from the file: the test only, the mods never
--- require each other).
local function slValidate(payload)
	local Z = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	return Z.validate(payload)
end

test("slZonesPayload: every twin with its mode, r = reach + pad (capped), rounded; bad zones dropped; capped at 400", function()
	local L = smallMap()
	local zones = logic.showcaseZones(L, CX, CY)
	local p, dropped = logic.slZonesPayload(zones, "s12-1-1")
	eq(dropped, 0)
	eq(p.op, "set")
	eq(p.run, "s12-1-1")
	eq(#p.zones, #zones)
	for i, z in ipairs(zones) do
		local q = p.zones[i]
		eq(q.ab, z.ab)
		near(q.x, z.x, 0.051)
		near(q.y, z.y, 0.051)
		near(q.r, math.min(logic.SL_ZONE_R_MAX, z.r + logic.SL_ZONE_PAD), 0.051)
		eq(q.id, z.id, "twin id label")
		eq(q.pair, z.pair, "pair label")
	end
	-- the payload passes Smart Lanes' validation unchanged, labels included (read back after a reload)
	local op, list, run = slValidate(p)
	eq(op, "set")
	eq(run, "s12-1-1")
	eq(#list, #zones)
	for i, z in ipairs(zones) do
		eq(list[i].id, z.id)
		eq(list[i].pair, z.pair)
	end
	eq(logic.slZoneLabel("g12c"), "g12c")
	eq(logic.slZoneLabel("g 1"), nil)
	eq(logic.slZoneLabel(string.rep("g", 13)), nil)
	eq(logic.slZoneLabel(nil), nil)
	-- bad entries are left out, counted; the cap holds
	local bad = { { x = 0, y = 0, r = 10, ab = "other" }, { x = 0 / 0, y = 0, r = 10, ab = "sl" }, { x = 0, y = 0, r = 0, ab = "sl" },
		{ x = 1, y = 1, r = 5000, ab = "game" } }
	local q, d = logic.slZonesPayload(bad, "r")
	eq(d, 3)
	eq(q.zones, { { x = 1, y = 1, r = logic.SL_ZONE_R_MAX, ab = "game" } })
	local many = {}
	for i = 1, 450 do many[i] = { x = i, y = 0, r = 10, ab = "sl" } end
	local m, md = logic.slZonesPayload(many, "r")
	eq(#m.zones, logic.SL_ZONES_MAX)
	eq(md, 50)
	eq((slValidate(m)), "set")
	-- run ids: Smart Lanes' character set, at most 40
	local r = logic.slZoneRun(999999, 2000000000, 99999)
	ok(#r <= 40 and r:match("^[%w%.%-]+$") ~= nil, r)
	eq(logic.slZonesByAb(p.zones):match("^game:%d+,sl:%d+,sl_phases:%d+$") ~= nil, true)
end)

test("Showcase zones, Smart Lanes absent: sent once before anything is built (harmless), no wait (ack=absent)", function()
	local L = smallMap()
	jn.buildShowcase(SEED)
	eq(#zoneEvents, 1)
	local ev = zoneEvents[1]
	eq(ev.before, 0, "before any build")
	eq({ ev.cmd.src, ev.cmd.id, ev.cmd.name, ev.cmd.param.op }, { "", "square_smart_lanes", "SmartLanes.zones", "set" })
	eq(#ev.cmd.param.zones, #L.groups)
	local all = logText()
	ok(all:find(string.format("[SQST] showcase zones sent n=%d run=%s by_ab=", #L.groups, ev.cmd.param.run), 1, true), all)
	ok(all:find("smart_lanes=no", 1, true), all)
	run(3000, "Showcase done")
	all = logText()
	ok(all:find("[SQST] showcase zones ack=absent run=" .. ev.cmd.param.run .. " ms=0", 1, true), all)
	eq(#constructions(), #L.groups, "built as before")
	-- the zone lines' ab and the zones sent agree group by group
	local byAb = {}
	for _, z in ipairs(ev.cmd.param.zones) do byAb[z.ab] = (byAb[z.ab] or 0) + 1 end
	local _, _, _, ab = logic.showcaseCounts(L)
	for k, v in pairs(ab) do eq(byAb[k] or 0, v, k) end
end)

test("Showcase zones, Smart Lanes present: the first junction waits until Smart Lanes holds the run (ack=yes)", function()
	local L = smallMap()
	slParams = {}
	local ackAt = nil
	slZrun = function()
		-- Smart Lanes stores it a while after the send (an older run id until then)
		if ackAt ~= nil and T >= ackAt then return zoneEvents[1].cmd.param.run end
		return "s1-1-1"
	end
	jn.buildShowcase(SEED)
	ackAt = T + 2000000 -- 2 s after the send
	ok(logText():find("smart_lanes=yes", 1, true))
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("[SQST] showcase zones ack=yes run=" .. zoneEvents[1].cmd.param.run, 1, true), all)
	local first = nil
	for _, s in ipairs(sent) do
		if s.cmd.p.constructionsToAdd then first = first or s end
	end
	ok(first ~= nil and first.t >= ackAt, "first junction after the acknowledgement")
	eq(#constructions(), #L.groups)
end)

test("Showcase zones, Smart Lanes present but never acknowledging (older Smart Lanes): builds after the timeout (ack=timeout)", function()
	local L = smallMap()
	slParams = {}
	slZrun = function() return nil end
	jn.buildShowcase(SEED)
	local t0 = T
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find("[SQST] showcase zones ack=timeout", 1, true), all)
	local first = nil
	for _, s in ipairs(sent) do
		if s.cmd.p.constructionsToAdd then first = first or s end
	end
	ok(first ~= nil and first.t - t0 >= 5000 * 1000, "waited the timeout")
	eq(#constructions(), #L.groups)
end)

---------------------------------------------------------------------------
-- jn.buildLightsShowcase: the same build with LIGHTS_SPEC (SHOWCASE.md "Lights showcase")

--- The 16 km map (centre 0, 0) and its Lights showcase layout for seed 12.
local function lightsMap()
	box = { min = { x = -8192, y = -8192 }, max = { x = 8192, y = 8192 } }
	return logic.showcaseLayout(MAP, MAP, MARGIN, SEED, logic.lightsSpec(1))
end

local function lightProposals(pref)
	local n = 0
	for _, x in ipairs(sent) do
		if x.cmd.p.lights and (pref == nil or x.cmd.p.lights.pref == pref) then n = n + 1 end
	end
	return n
end

test("Lights showcase: one lit shape in every set, four identical twins back to back, links grouped, zones with sl_lock, growth x3 once, no bus lines, timing", function()
	local L = lightsMap()
	local LS1 = logic.lightsSpec(1)
	local n, nTowns, by, ab = logic.showcaseCounts(L, LS1)
	ok(n >= 12 and by.x == n, n)
	jlogic.LINK_GROUP_MAX = 8
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end   -- the construction's Yes took
	jn.buildLightsShowcase(SEED, 1)
	ok(rt.keepBalance)
	eq(jn.lastLightsSeed, SEED)
	eq(jn.lightsSignature(), tostring(SEED))
	eq(jn.lastSeed, nil, "the Showcase's seed untouched")
	eq(gridOpts.name, "lights_showcase_towns")
	eq(gridOpts.batch, true, "towns, grids and locks batched")
	eq(gridOpts.streets, 3)
	eq(#gridOpts.points, nTowns)
	for k, p in ipairs(gridOpts.points) do
		eq(p.size, L.towns[k].size)
		eq(p.size, 2, "Medium, every town")
	end
	local all = logText()
	ok(all:find(string.format("[SQST] lights_showcase: seed=12 map=16384x16384m groups=%d sets=%d crossroads=%d twins sl=%d game=%d sl_phases=%d sl_lock=%d towns=%d (Medium) lights=yes year=? grow=x1 passes=1 grow_target=400 shape=1/4 (2x2 X) bus_lines=no",
		n, n / 4, by.x, ab.sl, ab.game, ab.sl_phases, ab.sl_lock, nTowns), 1, true), all)
	-- the zones: before anything is built, sl_lock included, passing Smart Lanes' validation
	eq(#zoneEvents, 1)
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local op, list = Zl.validate(zoneEvents[1].cmd.param)
	eq(op, "set")
	eq(#list, n)
	run(4000, "Lights showcase done")
	local cons = constructions()
	eq(#cons, n)
	for k, ce in ipairs(cons) do
		local g = L.groups[k]
		local x, y = cePos(ce)
		ok(math.abs(x - g.place.x) < 1 and math.abs(y - g.place.y) < 1, "layout order: " .. g.name)
		eq(ce.fileName, "square_stress_test::/infrastructure/street_construction/square_stress_test_crossing.con")
		eq({ ce.params.sqst_x_shape, ce.params.sqst_x_main, ce.params.sqst_x_side, ce.params.sqst_x_lights }, { 1, 5, 5, 2 }, "2x2 X, lit")
		eq(ownParams(ce), ownParams(cons[1]), "the same junction in every set")
	end
	-- every town linked, in fewer proposals (far-apart links share one), each proposal's node configs complete
	eq(linkedLines(), nTowns, "one link per town")
	ok(linkCount() < nTowns / 2, string.format("%d proposals for %d links", linkCount(), nTowns))
	local grouped = 0
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd then
			eq(cfgProblems(sp), {})
			for _, seg in ipairs(sp.edgesToAdd) do eq(seg.comp.roadDevelopmentLocked, true) end
			-- temp ids: edges -1..-E first, then the new nodes, each once
			local ids = {}
			for _, seg in ipairs(sp.edgesToAdd) do ids[#ids + 1] = -seg.entity end
			for _, nd in ipairs(sp.nodesToAdd) do ids[#ids + 1] = -nd.entity end
			for k2, id in ipairs(ids) do eq(id, k2, "temp ids in order") end
			if #sp.nodesToRemove > 2 then grouped = grouped + 1 end
		end
	end
	ok(grouped > 0, "some proposals carry several links")
	eq(lightProposals(), 0, "lit at the read: nothing forced")
	all = logText()
	ok(all:find(string.format("[SQST] lights_showcase summary seed=12 groups=%d built=%d refused=0 crossroads=%d/%d sl=%d/%d game=%d/%d sl_phases=%d/%d sl_lock=%d/%d links=%d linked=%d unlinked=0",
		n, n, by.x, by.x, ab.sl, ab.sl, ab.game, ab.game, ab.sl_phases, ab.sl_phases, ab.sl_lock, ab.sl_lock, nTowns, nTowns), 1, true), all)
	ok(all:find(" minutes=%d+%.%d") ~= nil, all)
	ok(all:find("one proposal of 8 links", 1, true), all)
	ok(all:find(string.format("[SQST] lights_showcase links: %d in ", nTowns), 1, true), all)
	ok(all:find(" lit=%d+:pref=yes,light=no") ~= nil, all)
	local zones, fan = 0, 0
	for line in all:gmatch("[^\n]+") do
		local id, ab_ = line:match("%[SQST%] showcase zone id=(g%d+%a) pair=g%d+ ab=(%S+) kind=plain ")
		if id then
			zones = zones + 1
			if ab_ == "sl_lock" then fan = fan + 1 ok(id:sub(-1) == "d", id) end
			ok(ab_ ~= "sl_fan", "no sl_fan twin")
		end
	end
	eq(zones, n)
	eq(fan, n / 4)
	ok(all:find("[SQST] Lights showcase done: ", 1, true) and all:find("; every town then grows to about 400 people (one size command, no build-out passes), locked to its grid; no bus lines", 1, true), all)
	ok(all:find(" Built in %d+%.%d min %(the growth follows%)%.") ~= nil, all)
	-- growth: every town, x3 (about 1000 people) in ONE pass with the level weights, queued after the last link (after the lock pass)
	eq(#growCalls, 1)
	local gc = growCalls[1]
	eq({ gc.factor, gc.passes, gc.name }, { logic.LIGHTS_GROW_FACTOR, 1, "lights_showcase_grow" })
	eq(gc.weights, logic.DENSE_WEIGHTS)
	eq(#gc.areas, nTowns)
	eq(gc.sent, #sent, "no command after the growth was queued")
	ok(all:find(string.format("[SQST] lights_showcase grow queued towns=%d factor=x1 passes=1 weights={0,0.1,0.5,1} locked=true target=400", nTowns), 1, true), all)
	-- the lock passes: after the towns (before any junction) and after the links (with the stubs)
	eq(#lockCalls, 2)
	eq({ lockCalls[1].name, lockCalls[1].opts.pass, lockCalls[1].sent }, { "lights_showcase_lock", "towns", 0 })
	eq({ lockCalls[2].name, lockCalls[2].opts.pass, lockCalls[2].opts.stubs }, { "lights_showcase_lock", "links", true })
	for k, a in ipairs(lockCalls[2].areas) do
		eq(a.town, 500 + k)
		eq(a.half, logic.gridHalfOfSize(L.towns[k].size))
	end
	-- no bus lines, no depots
	run(20)
	eq(#routeCalls, 0)
	eq(#depotCalls, 0)
	-- the timing line once the lock passes and the growth are through (their onDone)
	ok(not logText():find("lights_showcase timing", 1, true), "not before the growth is through")
	lockCalls[1].opts.onDone(2000)
	lockCalls[2].opts.onDone(3000)
	ok(not logText():find("lights_showcase timing", 1, true))
	gc.onDone(60000)
	all = logText()
	ok(all:find("%[SQST%] lights_showcase timing towns=0ms grids=0ms locks=5000ms junctions=%d+ms links=%d+ms depots=0ms density=60000ms total=%d+ms %(%d+%.%d min%)") ~= nil, all)
	ok(all:find("%[SQST%] lights_showcase finished in %d+%.%d min %(seed 12%)") ~= nil, all)
	eq(#rt.warnings, 0)
end)

test("mixed Lights showcase layout: every shape x 3 sets x three twins (sl a, game b, sl_exitfan e) on a 20 km map (135 towns); a 16 km map holds 6 sets", function()
	local sp = logic.LIGHTS_SPEC
	eq(sp.perType, 3)
	eq(#sp.modes, 3)
	eq({ sp.modes[1].ab, sp.modes[1].twin, sp.modes[2].ab, sp.modes[2].twin, sp.modes[3].ab, sp.modes[3].twin, sp.modes[3].label },
		{ "sl", "a", "game", "b", "sl_exitfan", "e", "Exit fan" })
	for _, seed in ipairs({ 12, 777, 4242 }) do
		-- 16 km: one set of three twins per row (9 km wide), 6 sets, every shape at least once
		local L16 = logic.showcaseLayout(16384, 16384, MARGIN, seed, sp)
		local n16, nt16 = logic.showcaseCounts(L16, sp)
		eq({ n16, nt16 }, { 18, 69 }, "16 km / " .. seed)
		local m = 20480
		local L = logic.showcaseLayout(m, m, MARGIN, seed, sp)
		local n, nt = logic.showcaseCounts(L, sp)
		eq({ n, nt }, { 36, 135 }, m .. "/" .. seed)
		local per, sets = {}, {}
		for _, g in ipairs(L.groups) do
			local lbl = g.place.case_.label
			per[lbl] = (per[lbl] or 0) + 1
			sets[g.set] = sets[g.set] or {}
			table.insert(sets[g.set], g)
			eq(#g.towns, lbl == "T 2x2" and 3 or 4, lbl)
		end
		eq(per, { ["2x2 X"] = 9, ["3x3 X"] = 9, ["3x2 X"] = 9, ["T 2x2"] = 9 })
		eq(#sets, 12)
		local tys = {}
		local pos = {}   -- shape -> ab -> { count in the west, middle, east position }
		for k, list in ipairs(sets) do
			eq(#list, 3, "three twins in set " .. k)
			eq({ list[1].ab, list[2].ab, list[3].ab }, { "sl", "game", "sl_exitfan" })
			local lbl = list[1].place.case_.label
			for _, g in ipairs(list) do eq(g.place.case_.label, lbl, "the same shape in every twin") end
			local xs = {}
			for _, g in ipairs(list) do xs[#xs + 1] = g.place.x end
			table.sort(xs)
			pos[lbl] = pos[lbl] or {}
			for _, g in ipairs(list) do
				pos[lbl][g.ab] = pos[lbl][g.ab] or { 0, 0, 0 }
				local slot = g.place.x == xs[1] and 1 or (g.place.x == xs[2] and 2 or 3)
				pos[lbl][g.ab][slot] = pos[lbl][g.ab][slot] + 1
			end
			if lbl == "T 2x2" then tys[#tys + 1] = list[1].place.y end
		end
		-- per shape every twin sits once in each of the three positions
		for lbl, byAb in pairs(pos) do
			for ab, c in pairs(byAb) do eq(c, { 1, 1, 1 }, lbl .. " " .. ab) end
		end
		table.sort(tys)
		eq(#tys, 3)
		local ylo, yhi = math.huge, -math.huge
		for _, g in ipairs(L.groups) do ylo, yhi = math.min(ylo, g.place.y), math.max(yhi, g.place.y) end
		ok(tys[3] - tys[1] >= 0.5 * (yhi - ylo), string.format("T sets y %.0f..%.0f of the sets' %.0f..%.0f", tys[1], tys[3], ylo, yhi))
	end
	-- the zones carry the shape as their label (flow_report groups by it) and the three modes
	local Z = logic.showcaseZones(logic.showcaseLayout(20480, 20480, MARGIN, 12, sp), 0, 0)
	for _, z in ipairs(Z) do
		ok(z.label == "2x2 X" or z.label == "3x3 X" or z.label == "3x2 X" or z.label == "T 2x2", z.label)
		ok(z.ab == "sl" or z.ab == "game" or z.ab == "sl_exitfan", z.ab)
		if z.ab == "sl_exitfan" then ok(z.id:match("^g%d+e$"), z.id) end
	end
	-- the by_ab text Smart Lanes logs on receipt, byte for byte
	local p = logic.slZonesPayload(Z, "s12-1-1")
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local op, list = Zl.validate(p)
	eq(op, "set")
	eq(logic.slZonesByAb(p.zones), Zl.byAbText(list))
	eq(logic.slZonesByAb(p.zones), "game:12,sl:12,sl_phases:0,sl_exitfan:12")
	local every = { { ab = "game" }, { ab = "sl_fan" }, { ab = "sl_lock" }, { ab = "sl_exitfan" }, { ab = "sl_exitfan" } }
	eq(logic.slZonesByAb(every), "game:1,sl:0,sl_phases:0,sl_fan:1,sl_lock:1,sl_exitfan:2")
	eq(logic.slZonesByAb(every), Zl.byAbText(every))
	ok(logic.SL_ZONE_AB.sl_exitfan)
	ok(logic.isTestTownName("Exit fan 4 N"))
end)

test("layout guards: a kind without types, or with no twin to build (every mode lit-plain only), ends the layout (no endless loop, no division by zero)", function()
	local sp = logic.lightsSpec(1)
	sp.kinds = { "x", "t" }
	sp.types = { x = { logic.LIGHTS_SHAPES[1] }, t = {} }
	sp.perType = nil
	local L = logic.showcaseLayout(MAP, MAP, MARGIN, 12, sp)
	ok(#L.groups > 0)
	for _, g in ipairs(L.groups) do eq(g.slot, "x") end
	-- no twin at all: only litPlainOnly modes and a kind that is not a lit plain crossing
	local sp2 = logic.lightsSpec(1)
	sp2.modes = { { ab = "sl_phases", twin = "c", label = "Smart phases", litPlainOnly = true } }
	sp2.kinds = { "rb" }
	sp2.types = { rb = logic.showcaseTypes("rb") }
	sp2.square, sp2.litOnly = false, false
	sp2.perType = nil
	local L2 = logic.showcaseLayout(MAP, MAP, MARGIN, 12, sp2)
	eq(#L2.groups, 0)
	sp2.perType = 3
	eq(#logic.showcaseLayout(MAP, MAP, MARGIN, 12, sp2).groups, 0)
end)

test("mixed Lights showcase build (20 km): all four shapes, three twins, T sets with 3 towns, every town entered and linked, sl / game / sl_exitfan zones, towns at about 400 each", function()
	box = { min = { x = -10240, y = -10240 }, max = { x = 10240, y = 10240 } }
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	jn.buildLightsShowcase(SEED)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find(" shapes=2x2_X,3x3_X,3x2_X,T_2x2 per_shape=3", 1, true), all)
	ok(all:find(" twins sl=12 game=12 sl_exitfan=12 towns=135 (Medium)", 1, true), all)
	-- the summary counts each kind once, then per shape
	local sum = all:match("%[SQST%] lights_showcase summary [^\n]*")
	ok(sum and sum:find(" crossroads=27/27 t_junctions=9/9 shapes 2x2_X=9/9 3x3_X=9/9 3x2_X=9/9 T_2x2=9/9 ", 1, true), sum)
	local _, nCross = sum:gsub(" crossroads=", "")
	eq(nCross, 1)
	local shapes = {}
	for _, ce in ipairs(constructions()) do shapes[(ce.params.sqst_x_shape or 0) .. "/" .. (ce.params.sqst_x_main or 0) .. "/" .. (ce.params.sqst_x_side or 0)] = true end
	eq(shapes, { ["1/5/5"] = true, ["1/6/6"] = true, ["1/6/5"] = true, ["2/5/5"] = true })
	eq(#entryCmds(), 135, "an entry roundabout for every town, T sets' towns too")
	eq(linkedLines(), 135)
	ok(all:find("[SQST] lights_showcase entries roundabout=135 crossroads=0 broken=0 joins=405/405", 1, true), all)
	ok(all:find("by_ab=game:12,sl:12,sl_phases:0,sl_exitfan:12", 1, true), all)
	local slz = ug_require "square_stress_test::/stress/gui/stress_slzones.tl"
	local nE = 0
	for _, z in ipairs(slz.current.zones) do
		ok(z.ab == "sl" or z.ab == "game" or z.ab == "sl_exitfan", z.ab)
		if z.ab == "sl_exitfan" then nE = nE + 1 end
	end
	eq(nE, 12)
	eq(#growCalls, 1)
	eq(growCalls[1].target, 400)
	ok(all:find(" target=400 ", 1, true), all)
	ok(all:find(" sets_mismatch=0", 1, true), all)
end)

test("Lights showcase: a given shape builds that one shape with its four twins (lightsSpec), the default press every shape", function()
	lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	local want = { { 1, 5, 5, "2x2 X" }, { 1, 6, 6, "3x3 X" }, { 1, 6, 5, "3x2 X" }, { 2, 5, 5, "T 2x2" } }
	for k, w in ipairs(want) do
		clear_logs()
		sent = {}
		nodes, edges = {}, {}   -- a fresh map per press (the fake's reads scan every edge)
		jn.buildLightsShowcase(SEED, k)
		ok(logText():find(string.format("shape=%d/4 (%s)", k, w[4]), 1, true), logText())
		run(4000, "Lights showcase done")
		local cons = constructions()
		ok(#cons >= 12)
		for _, ce in ipairs(cons) do
			eq({ ce.params.sqst_x_shape, ce.params.sqst_x_main, ce.params.sqst_x_side }, { w[1], w[2], w[3] }, w[4])
		end
		run(20)
	end
end)

test("Showcase link groups: far-apart links share one proposal (at most 8); a refused group goes one by one, its failing link logged with its hits", function()
	local L = smallMap()
	jlogic.LINK_GROUP_MAX = 8
	local nTowns = townTotal(L)
	-- one town link collides wherever it goes (into town S3): its group is refused, then it alone, every try
	failCmd = function(cmd) return cmd.touchesS3 == true end
	local send = api.cmd.makeWorldBuildProposalCmd
	api.cmd.makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
		local cmd = send(p, ctx, ignore, player, dust)
		local t3 = gridOpts and gridOpts.points and gridOpts.points[3]
		for _, nd in ipairs((p.streetProposal or {}).nodesToRemove or {}) do
			local q = nodes[nd]
			if q and t3 and math.abs(q.x - (CX + t3.x)) < 500 and math.abs(q.y - (CY + t3.y)) < 500 then cmd.touchesS3 = true end
		end
		return cmd
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	local all = logText()
	ok(all:find(string.format("[SQST] showcase links: %d in ", nTowns), 1, true), all)
	ok(all:find("%[SQST%] showcase link group of %d+ refused %(") ~= nil, all)
	ok(all:find("one by one: [^\n]*%-> " .. L.towns[3].name:gsub("%p", "%%%0")) ~= nil, all)
	-- every other link made (in groups or alone after the refusal); S3's refused on its own too
	eq(linkedLines(), nTowns - 1)
	ok(all:find("-> " .. L.towns[3].name .. ": link refused", 1, true), all)
	ok(linkCount() < nTowns, "fewer proposals than links")
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd then eq(cfgProblems(sp), {}) end
	end
	ok(all:find("unlinked=1", 1, true), all)
end)

test("Showcase: depots for the bus routes before the growth (after the lock pass), then the bus lines", function()
	smallMap()
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	eq(#depotCalls, 1)
	local dc = depotCalls[1]
	eq(dc.name, "showcase_depots")
	ok(#dc.routes > 0)
	eq(dc.grows, 0, "queued before the growth")
	eq(#growCalls, 1)
	eq(lockCalls[2].opts.pass, "links")
	ok(lockCalls[2].t <= dc.t, "after the lock pass")
	run(20)
	eq(#routeCalls, 1)
	eq(#routeCalls[1].routes, #dc.routes, "the same routes")
	-- the timing waits for the depots too
	lockCalls[1].opts.onDone(1)
	lockCalls[2].opts.onDone(1)
	growCalls[1].onDone(1)
	ok(not logText():find("showcase timing", 1, true))
	dc.onDone(4000)
	ok(logText():find("%[SQST%] showcase timing towns=0ms grids=0ms locks=2ms junctions=%d+ms links=%d+ms depots=4000ms density=1ms total=") ~= nil, logText())
end)

test("Lights showcase: a junction without a light at the read is set to Yes (every twin), logged and listed", function()
	local L = lightsMap()
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	eq(lightProposals(api.type.enum.TrafficLightPreference.YES), #L.groups, "one Yes per junction node")
	eq(lightProposals(api.type.enum.TrafficLightPreference.NO), 0)
	local all = logText()
	ok(all:find(" lit=%d+:pref=%?,light=no lights forced on at 1") ~= nil, all)
	eq(#rt.warnings, 1)
	ok(rt.warnings[1].title == "Lights showcase" and rt.warnings[1].body:find("no light at the read; set to Yes", 1, true), rt.warnings[1].body)
	-- the links still all went
	eq(linkCount(), #L.towns)
end)

test("Lights showcase: before 1950 a dialog up front (no automatic lights), the build goes on", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	api.engine.util.getYear = function() return 1920 end
	jn.buildLightsShowcase(SEED, 1)
	eq(#rt.warnings, 1)
	ok(rt.warnings[1].body:find("The year is 1920", 1, true) and rt.warnings[1].body:find("1950", 1, true), rt.warnings[1].body)
	ok(logText():find("[SQST] lights_showcase year=1920 before 1950", 1, true))
	ok(logText():find(" lights=yes year=1920 ", 1, true))
	run(4000, "Lights showcase done")
	eq(#constructions(), #L.groups)
	-- before 1940 the entry roundabout's streets don't exist yet: every entry stays the crossroads, logged
	eq(#entryCmds(), 0)
	local _, n = logText():gsub("kind=crossroads %(before 1940: no one%-way ring street yet%)", "")
	eq(n, townTotal(L))
	-- from 1950 on: no dialog
	clear_logs()
	rt.warnings = {}
	api.engine.util.getYear = function() return 1950 end
	run(20)
	jn.buildLightsShowcase(SEED, 1)
	eq(#rt.warnings, 0)
end)

test("Lights showcase: busy guards both ways; the Showcase's own run is unchanged by it", function()
	lightsMap()
	jn.buildLightsShowcase(SEED, 1)
	jn.buildShowcase(SEED)
	jn.build()
	local all = logText()
	ok(all:find("Showcase: A test is already running (lights_showcase", 1, true), all)
	ok(all:find("Junction test: A test is already running (lights_showcase", 1, true), all)
	run(4000, "Lights showcase done")
	-- growth and bus lines are test jobs too (the traffic log restarts only after them)
	for _, j in ipairs({ "lights_showcase_grow", "bus_lines_lights_showcase", "lights_showcase:traffic" }) do
		local hit = false
		for _, p in ipairs(rt.TEST_JOBS) do if j:sub(1, #p) == p then hit = true end end
		ok(hit, j)
	end
	run(20)
	smallMap()
	jn.buildShowcase(SEED)
	jn.buildLightsShowcase(SEED, 1)
	ok(logText():find("Lights showcase: A test is already running (showcase", 1, true), logText())
	run(3000, "Showcase done")
	eq(#growCalls, 2, "the Showcase grows too, under its own name")
	eq({ growCalls[2].name, growCalls[2].factor, growCalls[2].passes }, { "showcase_grow", 10, 3 })
end)

test("Lights showcase: zones replace the session's list (the traffic log restarts on it)", function()
	local slz = ug_require "square_stress_test::/stress/gui/stress_slzones.tl"
	smallMap()
	jn.buildShowcase(SEED)
	local first = slz.current
	run(3000, "Showcase done")
	run(20)
	local L = lightsMap()
	jn.buildLightsShowcase(SEED, 1)
	ok(slz.current ~= first and slz.current.seq == first.seq + 1)
	eq(#slz.current.zones, #L.groups)
	eq(slz.current.zones[4].ab, "sl_lock")
end)

test("Lights showcase: its build step stays well within Lua 5.1's 60 upvalues per function", function()
	lightsMap()
	local captured = {}
	local enqueue = rt.enqueue
	rt.enqueue = function(name, total, step, opts)
		captured[name] = step
		return enqueue(name, total, step, opts)
	end
	jn.buildLightsShowcase(SEED, 1)
	local step = captured.lights_showcase
	ok(step ~= nil)
	local n = debug.getinfo(step, "u").nups
	print("lights_showcase step upvalues (Lua 5.4, +1 for _ENV): " .. n)
	ok(n <= 50, "upvalues: " .. n)
end)

---------------------------------------------------------------------------
-- Square layout and own-town links (SHOWCASE.md "Square layout", user 2026-10-12, seed 718344)

test("sideCentre / nodeAt / axisUnit / ownTownNodes: the grid side facing the junction; never another town's node", function()
	eq(logic.sideCentre(1000, 0, 300, 0, 0), { 700, 0 }, "junction west of the town: the west side")
	eq(logic.sideCentre(0, 0, 400, 0, 1131), { 0, 400 })
	eq(logic.sideCentre(0, 0, 400, 0, -1131), { 0, -400 })
	eq(logic.sideCentre(0, 0, 400, 1131, 5), { 400, 0 })
	eq(logic.axisUnit(0), { 1, 0 })
	eq(logic.axisUnit(90), { 0, 1 })
	eq(logic.axisUnit(180), { -1, 0 })
	eq(logic.axisUnit(270), { 0, -1 })
	eq(logic.axisUnit(-90), { 0, -1 })
	eq(logic.axisUnit(45), nil)
	local cands = { { id = 5, x = 703, y = 2 }, { id = 4, x = 690, y = 0 }, { id = 9, x = 900, y = 0 } }
	eq(logic.nodeAt(cands, { 700, 0 }, 15).id, 5)
	eq(logic.nodeAt(cands, { 800, 0 }, 15), nil)
	eq(logic.nodeAt({ { id = 7, x = 1, y = 0 }, { id = 3, x = -1, y = 0 } }, { 0, 0 }, 15).id, 3, "a tie: the lower id")
	-- seed 718344, Group 1a: north town S4 (Large, centre 7792), east town S3 (Medium, -5752,6661); S3's NW
	-- corner stub tip lay nearer the north arm than any S4 node and inside S4's search circle
	local s4 = { town = 4, x = -6661, y = 7792, half = 400 }
	local stubS3 = { id = 1, x = -6052 - 42, y = 6961 + 42 }
	local s4Node = { id = 2, x = -6661, y = 7392 }
	eq(#logic.ownTownNodes({ stubS3, s4Node }, s4), 1)
	eq(logic.ownTownNodes({ stubS3, s4Node }, s4)[1].id, 2)
	-- its own corner stubs (42 m out diagonally) still count
	eq(#logic.ownTownNodes({ { id = 3, x = -6661 + 442, y = 7792 + 442 } }, s4), 1)
end)

test("countryTemplate: the country road of a two-way street's lanes and era; none for other counts", function()
	eq(logic.countryTemplate(2, 2020), "::/infrastructure/street/country/country_new_small.street_template")
	eq(logic.countryTemplate(4, nil), "::/infrastructure/street/country/country_new_medium.street_template")
	eq(logic.countryTemplate(6, 1900), "::/infrastructure/street/country/country_old_large.street_template")
	eq(logic.countryTemplate(6, 1940), "::/infrastructure/street/country/country_new_large.street_template")
	eq(logic.countryTemplate(3, 2020), nil)
	eq(logic.countryTemplate(nil, 2020), nil)
	-- the base templates exist (game files, when extracted)
	for _, era in ipairs({ "new", "old" }) do
		for _, size in ipairs({ "small", "medium", "large" }) do
			local f = io.open(string.format(".cache/game/base/content/infrastructure/street/country/country_%s_%s.street_template.lua", era, size))
			if f then
				local text = f:read("a")
				f:close()
				ok(text:find("country = true", 1, true), era .. " " .. size .. " is a country road")
			end
		end
	end
end)

test("showcaseMatch / zone_match line: an unlinked arm makes the set match=no reason=link", function()
	local twins = { { built = true, params = "a" }, { built = true, params = "a" } }
	eq(logic.showcaseMatch(twins, false, true), "link")
	eq(logic.showcaseMatch(twins, true, true), "town,link")
	eq(logic.showcaseMatch(twins, false, false), nil)
	eq(logic.showcaseZoneMatchLine({ id = "g1b", pair = "g1", reason = "link" }), "[SQST] showcase zone_match id=g1b pair=g1 match=no reason=link")
end)

--- The link proposals sent (street proposals without a construction or lights), in order.
local function linkProposals()
	local out = {}
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp and sp.edgesToAdd and not x.cmd.p.constructionsToAdd and not x.cmd.p.lights and not isEntryJoin(sp) then out[#out + 1] = x.cmd end
	end
	return out
end

test("Lights showcase, crossroads entries (no ring at the side middle): every link is one straight locked large country road from the arm end to the middle of its own town's facing side", function()
	entryRing = false
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	-- node positions before they are replaced (the fake removes nothing, so ids stay readable)
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local links = linkProposals()
	local nTowns = 0
	for _, g in ipairs(L.groups) do nTowns = nTowns + #g.towns end
	eq(#links, nTowns)
	local targets = {}
	for _, g in ipairs(L.groups) do
		local jx, jy = g.place.x, g.place.y
		for _, ti in ipairs(g.towns) do
			local t = L.towns[ti]
			local half = logic.gridHalfOfSize(t.size)
			local sc = logic.sideCentre(t.x, t.y, half, jx, jy)
			targets[#targets + 1] = { x = sc[1], y = sc[2], name = t.name, jx = jx, jy = jy }
		end
	end
	for _, cmd in ipairs(links) do
		local sp = cmd.p.streetProposal
		-- the town node it replaces: one of the side centres, and the junction arm end on the same axis
		local hit
		for _, id in ipairs(sp.nodesToRemove) do
			local p = nodes[id]
			for _, tg in ipairs(targets) do
				if p and math.abs(p.x - tg.x) < 1e-6 and math.abs(p.y - tg.y) < 1e-6 then hit = tg end
			end
		end
		ok(hit, "the link ends at the middle of a grid side")
		-- every new node lies on the straight line from the junction to that point (one axis)
		for _, ne in ipairs(sp.nodesToAdd) do
			local q = ne.comp.position
			ok(math.abs(q.x - hit.x) < 1e-6 or math.abs(q.y - hit.y) < 1e-6, "on the axis")
			ok(math.abs(q.x - hit.jx) < 1e-6 or math.abs(q.y - hit.jy) < 1e-6, "on the junction's axis")
		end
		-- the new pieces: country, locked; the copies of the existing edges keep their own type
		local country = 0
		for _, seg in ipairs(sp.edgesToAdd) do
			eq(seg.comp.roadDevelopmentLocked, true)
			if seg.comp.roadTemplate and seg.comp.roadTemplate:find("/country/country_new_large", 1, true) then country = country + 1 end
		end
		ok(country >= 1, "country pieces")
		eq(#sp.edgesToAdd - country, 2, "only the two copies at the replaced nodes are not new country pieces")
		eq(cfgProblems(sp), {})
	end
	local all = logText()
	ok(not all:find("zone_match", 1, true), "every arm linked: no late verdict")
	-- the lock pass after the links and the growth's leak checks take every town's junction zone along
	local linksPass
	for _, lc in ipairs(lockCalls) do if lc.opts.pass == "links" then linksPass = lc end end
	ok(linksPass, "a lock pass after the links")
	for _, a in ipairs({ linksPass.areas[1], growCalls[1].areas[1] }) do
		eq(#a.zones, 1, a.label .. ": its junction's zone")
		local z = a.zones[1]
		near(math.sqrt((z[1] - a.x) ^ 2 + (z[2] - a.y) ^ 2), a.reach, 1e-6, "streets looked for out to the junction")
		ok(z[3] > 0)
	end
end)

test("Lights showcase, crossroads entries: a link refused every time leaves that arm unlinked (no other node, no bend); its set match=no reason=link", function()
	entryRing = false
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	local g = L.groups[2]   -- Group 1b
	local town = L.towns[g.towns[1]]
	local half = logic.gridHalfOfSize(town.size)
	failCmd = function(cmd)
		if touches(cmd, town.x, town.y, half + 60) then return refuse(cmd, "Collision") end
		return false
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find("-> " .. town.name .. ": link refused 3 times", 1, true), all)
	ok(not all:find("nearest town node", 1, true), "no fallback in the square layout")
	-- the three tries all aimed at the same node (the side's middle)
	local aimed = {}
	for _, cmd in ipairs(linkProposals()) do
		if touches(cmd, town.x, town.y, half + 60) then
			for _, id in ipairs(cmd.p.streetProposal.nodesToRemove) do
				local p = nodes[id]
				if p and math.sqrt((p.x - town.x) ^ 2 + (p.y - town.y) ^ 2) < half + 60 then aimed[id] = true end
			end
		end
	end
	local nAimed = 0
	for _ in pairs(aimed) do nAimed = nAimed + 1 end
	eq(nAimed, 1)
	-- every twin of set 1 gets the late verdict
	for _, t in ipairs({ "a", "b", "c", "d" }) do
		ok(all:find("[SQST] showcase zone_match id=g1" .. t .. " pair=g1 match=no reason=link", 1, true), all)
	end
	ok(not all:find("zone_match id=g2", 1, true), "other sets untouched")
	ok(all:find(" unlinked=1 towns_skipped=0 sets_mismatch=1", 1, true), all)
end)

test("Lights showcase, crossroads entries: no node at the middle of a town's side -> that arm stays unlinked, logged, never linked elsewhere", function()
	entryRing = false
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	local g = L.groups[1]
	local town = L.towns[g.towns[2]]
	local half = logic.gridHalfOfSize(town.size)
	-- after the first junction build, the town's side node facing the junction is gone (its "+" arm cut)
	local cut = false
	afterBuild = function()
		if cut then return end
		cut = true
		local sc = logic.sideCentre(town.x, town.y, half, g.place.x, g.place.y)
		for id, p in pairs(nodes) do
			if math.abs(p.x - sc[1]) < 1e-6 and math.abs(p.y - sc[2]) < 1e-6 then
				nodes[id] = nil
				for e, ed in pairs(edges) do if ed.n0 == id or ed.n1 == id then edges[e] = nil end end
			end
		end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find("-> " .. town.name .. ": not linked (no node of " .. town.name .. " at the middle of its grid's side", 1, true), all)
	for _, cmd in ipairs(linkProposals()) do ok(not touches(cmd, town.x, town.y, half + 300), "nothing else of that town taken") end
	ok(all:find("[SQST] showcase zone_match id=g1a pair=g1 match=no reason=link", 1, true), all)
end)

---------------------------------------------------------------------------
-- Town entries (SHOWCASE.md "Town entries must not be the bottleneck")

local function negZero(v) return v == 0 and 1 / v < 0 end

test("entry helpers: outward axis exactly 0 / +-1 (no -0); roles out / in / left / right; the log line", function()
	eq(logic.entryOutward(0, 0, 300, 0), { 1, 0 })
	eq(logic.entryOutward(0, 0, -300, 0), { -1, 0 })
	eq(logic.entryOutward(100, 100, 100, 400), { 0, 1 })
	eq(logic.entryOutward(100, 100, 100, -200), { 0, -1 })
	for _, o in ipairs({ logic.entryOutward(0, 0, 0, -300), logic.entryOutward(0, 0, -300, 0) }) do
		ok(not negZero(o[1]) and not negZero(o[2]), "no -0")
	end
	-- an east side's middle at (300, 0): out = +x, in = -x, left (looking out) = +y, right = -y
	local roles = logic.entryRoles(300, 0, { 1, 0 }, { { 362, 1 }, { 300, 62 }, { 238, 0 }, { 300, -62 } })
	eq(roles, { out = 1, left = 2, ["in"] = 3, right = 4 })
	local r2, why = logic.entryRoles(300, 0, { 1, 0 }, { { 340, 40 } })
	eq(r2, nil)
	ok(why:find("off the axes", 1, true), why)
	eq(select(2, logic.entryRoles(0, 0, { 0, 1 }, { { 0, 60 }, { 0, 70 } })), "two points out")
	eq(logic.entryLine("lights_showcase", "Smart lanes 1 N", "crossroads", "(why)"), "[SQST] lights_showcase entry Smart lanes 1 N kind=crossroads (why)")
	-- the spec: entries and large links only in the Lights showcase
	eq({ logic.LIGHTS_SPEC.entries, logic.LIGHTS_SPEC.linkLanes }, { true, 6 })
	eq({ logic.SHOWCASE_SPEC.entries, logic.SHOWCASE_SPEC.linkLanes }, { nil, nil })
	eq(logic.countryTemplate(logic.ENTRY_LINK_LANES, 2000), "::/infrastructure/street/country/country_new_large.street_template")
	-- a Medium grid's block leaves room for the roundabout's arms, the far node's junction area and a join
	local _, step = (dofile("mods/square_stress_test/content/stress/stress_grid_streets.lua")).lines(logic.gridHalfOfSize(logic.LIGHTS_SIZE))
	ok(step >= logic.ENTRY_REACH + logic.ENTRY_FAR_CLEAR + logic.ENTRY_MIN_JOIN, "block " .. step)
	eq(logic.showcaseMatch({}, false, false, true), "entry")
end)

test("Lights showcase entries: a roundabout at every town's side middle (rotation 0, no -0, node + 3 edges removed, configs paired), identical in every twin, joined to the grid, the link to its outer arm", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	ok(all:find(" entries=roundabout link_lanes=6", 1, true), all)
	ok(all:find("[SQST] lights_showcase entries: driving side not read (no two-way street), right assumed, ring anticlockwise", 1, true), all)
	local _, nSide = all:gsub("entries: driving side", "")
	eq(nSide, 1, "read once per run")
	local ents = entryCmds()
	eq(#ents, nTowns, "one entry per town")
	-- the real spec's layout (Medium, grid half 300 m), and no entry fell back to the crossroads (in game seed
	-- 4951 every one did: "no grid node at the side's middle", a 15 m octree search on the node)
	for _, t in ipairs(L.towns) do eq(logic.gridHalfOfSize(t.size), 300, t.name .. " Medium grid") end
	ok(not all:find("kind=crossroads", 1, true), all)
	-- every entry before the first junction build
	local firstJ, lastE
	for k, x in ipairs(sent) do
		local ce = x.cmd.p.constructionsToAdd and x.cmd.p.constructionsToAdd[1]
		if ce and ce.name == ENTRY_NAME then lastE = k elseif ce and not firstJ then firstJ = k end
	end
	ok(lastE < firstJ, "entries first")
	local zones = logic.showcaseZones(L, 0, 0)
	local rel = {}   -- per set: each twin's entries relative to its junction
	for gi, g in ipairs(L.groups) do
		local list = {}
		for _, ti in ipairs(g.towns) do
			local t = L.towns[ti]
			local sc = logic.sideCentre(t.x, t.y, logic.gridHalfOfSize(t.size), g.place.x, g.place.y)
			local cmd
			for _, c in ipairs(ents) do
				local r = c.p.constructionsToAdd[1].transf[4]
				if r[1] == sc[1] and r[2] == sc[2] then cmd = c end
			end
			ok(cmd, "an entry at the side middle of " .. t.name)
			local ce = cmd.p.constructionsToAdd[1]
			eq(ce.fileName, "square_stress_test::/infrastructure/street_construction/square_stress_test_entry.con")
			eq(ce.params.sqst_entry_dir, 1, "anticlockwise: the driving side not read, right assumed")
			eq(ce.params.sqst_entry_in_reach, 1, "the inward arm at its first reach (46 m) when the check passes")
			-- the inward arm is the one pointing at the town centre
			local ax = ce.params.sqst_entry_in_axis - 1
			local dirs = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
			near(sc[1] + dirs[ax][1] * 300, t.x, 1e-6)
			near(sc[2] + dirs[ax][2] * 300, t.y, 1e-6)
			-- rotation exactly 0, every zero +0
			eq({ ce.transf[1][1], ce.transf[1][2], ce.transf[2][1], ce.transf[2][2] }, { 1, 0, 0, 1 })
			for _, row in ipairs(ce.transf) do
				for _, v in ipairs(row) do ok(not negZero(v), "no -0 in the transform") end
			end
			-- the side-middle node and its three edges go in the same proposal; far node configs removed AND added
			local sp = cmd.p.streetProposal
			eq(#sp.nodesToRemove, 1)
			eq(#sp.edgesToRemove, 3)
			local added = {}
			for _, e in ipairs(sp.nodeConfigsToAdd or {}) do added[e.entity] = true end
			for _, n in ipairs(sp.nodeConfigsToRemove or {}) do ok(added[n], "config removed and added") end
			-- outside the twin zones, even as the traffic log measures them (r + 200 m)
			local d = math.sqrt((sc[1] - g.place.x) ^ 2 + (sc[2] - g.place.y) ^ 2)
			ok(d - logic.ENTRY_REACH > zones[gi].r + 200, "entry outside the measured zone")
			list[#list + 1] = string.format("%.0f,%.0f", sc[1] - g.place.x, sc[2] - g.place.y)
		end
		table.sort(list)
		local key = table.concat(list, ";")
		if rel[g.set] then eq(key, rel[g.set], "the same entries in every twin of set " .. g.set) else rel[g.set] = key end
	end
	-- every entry joined to its grid in one proposal, node configs complete
	local joins = 0
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd and isEntryJoin(sp) then
			joins = joins + 1
			eq(cfgProblems(sp), {})
			eq(#sp.nodesToRemove, 6, "3 arm ends + 3 grid nodes replaced")
			for _, seg in ipairs(sp.edgesToAdd) do eq(seg.comp.roadDevelopmentLocked, true) end
		end
	end
	eq(joins, nTowns)
	ok(all:find(string.format("[SQST] lights_showcase entries roundabout=%d crossroads=0 broken=0 joins=%d/%d", nTowns, 3 * nTowns, 3 * nTowns), 1, true), all)
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, nTowns)
	-- every town link ends at its entry's outer arm end: ENTRY_REACH out from the side middle on the axis
	local links = linkProposals()
	ok(#links > 0)
	local ends = 0
	for _, cmd in ipairs(links) do
		eq(cfgProblems(cmd.p.streetProposal), {})
		for _, id in ipairs(cmd.p.streetProposal.nodesToRemove) do
			local p = nodes[id]
			for _, c in ipairs(ents) do
				local r = c.p.constructionsToAdd[1].transf[4]
				if p and math.abs(math.sqrt((p.x - r[1]) ^ 2 + (p.y - r[2]) ^ 2) - logic.ENTRY_REACH) < 1e-6 then ends = ends + 1 end
			end
		end
		for _, seg in ipairs(cmd.p.streetProposal.edgesToAdd) do
			if seg.comp.roadTemplate then ok(seg.comp.roadTemplate:find("country_new_large", 1, true), "large country link") end
		end
	end
	eq(ends, nTowns, "every link at an outer arm end")
	-- the zones carry their arms' measured headings (the traffic log measures out along them)
	local slz = ug_require "square_stress_test::/stress/gui/stress_slzones.tl"
	for _, z in ipairs(slz.current.zones) do
		eq(#z.arms, 4, z.id)
		for _, a in ipairs(z.arms) do near(math.abs(a[1]) + math.abs(a[2]), 1, 1e-9) end
	end
	eq(linkedLines(), nTowns)
	ok(all:find(" sets_mismatch=0", 1, true), all)
	ok(not all:find("kind=crossroads", 1, true), all)
	eq(#rt.warnings, 0)
end)

local function drivingSideCase(c)
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	townLanes = c.lanes
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find("[SQST] lights_showcase entries: driving side " .. c.side .. ", ring " .. c.ring, 1, true), all)
	local ents = entryCmds()
	eq(#ents, townTotal(L))
	for _, cmd in ipairs(ents) do eq(cmd.p.constructionsToAdd[1].params.sqst_entry_dir, c.dir) end
	ok(all:find("joins=" .. 3 * townTotal(L) .. "/" .. 3 * townTotal(L), 1, true), all)
end

test("Lights showcase entries: right-hand lanes on the grid streets -> every entry ring anticlockwise", function()
	drivingSideCase({ lanes = lanesOf({ false, false, false, true, true, true }), side = "right", dir = 1, ring = "anticlockwise" })
end)

test("Lights showcase entries: left-hand lanes on the grid streets -> every entry ring clockwise, in every twin", function()
	drivingSideCase({ lanes = lanesOf({ false, true, true, false, false, true }), side = "left", dir = 2, ring = "clockwise" })
end)

test("Lights showcase entries: a side-middle node off the side's middle (10 m, within SIDE_TOL) -> the roundabout centred on that node, read and joined there", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	sideShift = 10
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	local ents = entryCmds()
	eq(#ents, nTowns)
	for gi, g in ipairs(L.groups) do
		for _, ti in ipairs(g.towns) do
			local t = L.towns[ti]
			local h = logic.gridHalfOfSize(t.size)
			local sc = logic.sideCentre(t.x, t.y, h, g.place.x, g.place.y)
			local cx, cy = t.x + (sc[1] - t.x) * (h + 10) / h, t.y + (sc[2] - t.y) * (h + 10) / h
			local hit = 0
			for _, c in ipairs(ents) do
				local r = c.p.constructionsToAdd[1].transf[4]
				if math.abs(r[1] - cx) < 1e-6 and math.abs(r[2] - cy) < 1e-6 then hit = hit + 1 end
			end
			eq(hit, 1, t.name .. " centred on its node")
			ok(all:find(string.format("entry %s kind=roundabout at %.0f,%.0f ", t.name, cx, cy), 1, true), t.name)
		end
	end
	ok(all:find(string.format("[SQST] lights_showcase entries roundabout=%d crossroads=0 broken=0 joins=%d/%d", nTowns, 3 * nTowns, 3 * nTowns), 1, true), all)
end)

test("Lights showcase entries: the inward arm refused by the check at 46 and 42 m -> 38 m for every entry (logged once), every twin alike, joined", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local asked = {}
	refuseCheck = function(ce)
		if ce.name ~= ENTRY_NAME then return nil end
		asked[#asked + 1] = ce.params.sqst_entry_in_reach
		-- as in game 2026-10-13: the inward arm's end inside the inward crossroads' area
		if ce.params.sqst_entry_in_reach < 3 then return "Collision", { 4242 } end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	ok(all:find("[SQST] lights_showcase entries: 3 lanes 46m refused by the check (3 lanes 46m, 3 lanes 42m), 3 lanes 38m from now on", 1, true), all)
	local _, nLower = all:gsub("entries: %d lanes %d+m refused by the check", "")
	eq(nLower, 1, "logged once")
	eq(#asked, nTowns + 2, "the first entry tried 46, 42, 38; every later one starts at 38")
	local ents = entryCmds()
	eq(#ents, nTowns)
	for _, cmd in ipairs(ents) do
		eq(cmd.p.constructionsToAdd[1].params.sqst_entry_in_reach, 3)
		eq(cmd.p.constructionsToAdd[1].params.sqst_entry_ring, 2, "the 3-lane ring")
	end
	local _, n38 = all:gsub("kind=roundabout at [^\n]* reach=46m in_reach=38m ring_lanes=3", "")
	eq(n38, nTowns)
	ok(all:find(string.format("[SQST] lights_showcase entries roundabout=%d crossroads=0 broken=0 joins=%d/%d", nTowns, 3 * nTowns, 3 * nTowns), 1, true), all)
	ok(all:find(" sets_mismatch=0", 1, true), all)
end)

test("Lights showcase entries: the 3-lane ring refused at every reach -> the 2-lane ring (46 m) for every entry, logged once, joined", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local asked = 0
	refuseCheck = function(ce)
		if ce.name ~= ENTRY_NAME then return nil end
		asked = asked + 1
		if ce.params.sqst_entry_ring == 2 then return "Construction Not Possible" end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	ok(all:find("entries: 3 lanes 46m refused by the check (3 lanes 46m, 3 lanes 42m, 3 lanes 38m, 3 lanes 36m), 2 lanes 46m from now on", 1, true), all)
	eq(asked, nTowns + 4, "the first entry tried the whole 3-lane ladder; the rest start at the 2-lane ring")
	for _, cmd in ipairs(entryCmds()) do eq(cmd.p.constructionsToAdd[1].params.sqst_entry_ring, 1) end
	local _, n = all:gsub("kind=roundabout at [^\n]* in_reach=46m ring_lanes=2", "")
	eq(n, nTowns)
	ok(all:find(string.format("[SQST] lights_showcase entries roundabout=%d crossroads=0 broken=0 joins=%d/%d", nTowns, 3 * nTowns, 3 * nTowns), 1, true), all)
	ok(all:find(" sets_mismatch=0", 1, true), all)
end)

test("Lights showcase entries: an entry that needs a shorter inward arm than the ones before -> those sets no match (reason=entry), the later entries start there", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	-- the last-built entry of the run is the one that needs 42 m
	local g = L.groups[#L.groups]
	local town = L.towns[g.towns[#g.towns]]
	local sc = logic.sideCentre(town.x, town.y, logic.gridHalfOfSize(town.size), g.place.x, g.place.y)
	refuseCheck = function(ce)
		local r = ce.transf[4]
		if ce.name == ENTRY_NAME and r[1] == sc[1] and r[2] == sc[2] and ce.params.sqst_entry_in_reach < 2 then return "Collision" end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find("entries: 3 lanes 46m refused by the check (3 lanes 46m), 3 lanes 42m from now on", 1, true), all)
	ok(all:find("entry " .. town.name .. " kind=roundabout at [^\n]* in_reach=42m") ~= nil, all)
	ok(all:find("showcase zone id=g" .. g.set .. "%a pair=g" .. g.set .. " [^\n]* match=no reason=entry") ~= nil, all)
	ok(not all:find(" sets_mismatch=0", 1, true), all)
end)

test("Lights showcase entries: the entry construction missing -> every entry stays the crossroads (logged per town), links to the side middles", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	local find = api.res.constructionRep.find
	api.res.constructionRep.find = function(name)
		if name:find(logic.ENTRY_FILE, 1, true) then return -1 end
		return find(name)
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find(" entries=crossroads (entry construction not found) link_lanes=6", 1, true), all)
	eq(#entryCmds(), 0)
	local _, n = all:gsub("kind=crossroads %(entry construction not found%)", "")
	eq(n, townTotal(L))
	eq(#constructions(), #L.groups, "the junctions are still built (our own crossing)")
	eq(linkedLines(), townTotal(L))
	ok(all:find(" sets_mismatch=0", 1, true), all)
end)

test("Lights showcase entries: a roundabout refused in one twin -> that town keeps its crossroads (why logged), its set match=no reason=entry, the others unchanged", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	local g = L.groups[2]
	local town = L.towns[g.towns[1]]
	local sc = logic.sideCentre(town.x, town.y, logic.gridHalfOfSize(town.size), g.place.x, g.place.y)
	refuseCheck = function(ce)
		local r = ce.transf[4]
		if ce.name == ENTRY_NAME and r[1] == sc[1] and r[2] == sc[2] then return "Collision" end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find("entry " .. town.name .. " kind=crossroads (roundabout refused by the check: Collision (tried 3 lanes 46m, 3 lanes 42m, 3 lanes 38m, 3 lanes 36m, 2 lanes 46m, 2 lanes 42m, 2 lanes 38m, 2 lanes 36m))", 1, true), all)
	eq(#entryCmds(), townTotal(L) - 1)
	-- its link still ends at the side middle (the crossroads), all towns linked
	eq(linkedLines(), townTotal(L))
	local hit = false
	for _, cmd in ipairs(linkProposals()) do
		for _, id in ipairs(cmd.p.streetProposal.nodesToRemove) do
			local p = nodes[id]
			if p and p.x == sc[1] and p.y == sc[2] then hit = true end
		end
	end
	ok(hit, "linked to the crossroads")
	for _, t in ipairs({ "a", "b", "c", "d" }) do
		ok(all:find("showcase zone id=g1" .. t .. " pair=g1 ab=%S+ kind=plain .* match=no reason=entry") ~= nil, t)
	end
	ok(all:find(" sets_mismatch=1", 1, true), all)
	ok(rt.warnings[1] and rt.warnings[1].body:find(town.name .. " entry: crossroads", 1, true), "listed in the dialog")
end)

test("Lights showcase entries: a Collision names the entry's own nodes it hits (12 hits on 3 far nodes: distinct count, known roles)", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	local g = L.groups[1]
	local town = L.towns[g.towns[1]]
	local sc = logic.sideCentre(town.x, town.y, logic.gridHalfOfSize(town.size), g.place.x, g.place.y)
	refuseCheck = function(ce)
		local r = ce.transf[4]
		if ce.name ~= ENTRY_NAME or r[1] ~= sc[1] or r[2] ~= sc[2] then return nil end
		-- the far nodes (the ring pieces' ends 75 m along, the town centre inwards), each hit 4 times, as in game
		local far = {}
		for id, p in pairs(nodes) do
			local d = math.sqrt((p.x - sc[1]) ^ 2 + (p.y - sc[2]) ^ 2)
			if d > 1 and d < logic.gridHalfOfSize(town.size) + 1 then far[#far + 1] = id end
		end
		table.sort(far)
		local ids = {}
		for _ = 1, 4 do for _, id in ipairs(far) do ids[#ids + 1] = id end end
		return "Collision", ids
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local line = all:match("entry " .. town.name:gsub("%p", "%%%0") .. " kind=crossroads %(roundabout refused by the check: [^\n]*")
	ok(line, all)
	ok(line:find("Collision (hits 12 other BASE_NODE (3 distinct) e.g. #", 1, true), line)
	for _, role in ipairs({ "in far node", "left far node", "right far node" }) do ok(line:find(role, 1, true), role .. ": " .. line) end
	ok(line:find("; known: #", 1, true), line)
	eq(#entryCmds(), townTotal(L) - 1)
end)

test("Lights showcase entries: each entry's own streets (ring + arms, both ends new) are locked a moment after its build, before its read; nothing else", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local nTowns = townTotal(L)
	eq(#entryLocks, nTowns)
	local firstJoin
	for k, x in ipairs(sent) do
		if not firstJoin and x.cmd.p.streetProposal and x.cmd.p.streetProposal.edgesToAdd and isEntryJoin(x.cmd.p.streetProposal) then firstJoin = k end
	end
	for _, lk in ipairs(entryLocks) do
		eq(lk.name, "lights_showcase")
		ok(lk.label:find(" entry$") ~= nil, lk.label)
		-- the fake's construction as built: the ring (4) and the arms (4)
		eq(#lk.list, 8, lk.label)
		ok(lk.sent < firstJoin, "locked before the joins")
	end
	ok(not logText():find("its streets not all locked", 1, true), logText())
end)

test("Lights showcase entries: a lit far node whose light states can't be carried (it lost its phases, as the ring corners in game) gets its light switched off after the join, logged", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	litNode = function(n) return townCentres[n] == true end
	afterBuild = function(ce)
		if ce.name ~= ENTRY_NAME then return end
		for _, x in ipairs(sent) do
			if x.cmd.p.constructionsToAdd and x.cmd.p.constructionsToAdd[1] == ce then
				applyStreet(x.cmd.p.streetProposal)
				-- the engine dropped the node's phases after the removal (2026-10-13: "phases 0, were 6")
				for _, en in ipairs(x.cmd.p.streetProposal.nodeConfigsToAdd or {}) do
					if cfgOverride[en.entity] and cfgOverride[en.entity].trafficLightConfig then
						cfgOverride[en.entity].trafficLightConfig = { states = {} }
					end
				end
			end
		end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	local _, nOff = all:gsub(" kind=roundabout joined=3/3 lights=in:off %(unmapped %(phases 0, were %d+%)%)", "")
	eq(nOff, nTowns, all)
	local offs = {}
	for _, x in ipairs(sent) do
		if x.cmd.p.lights and x.cmd.p.lights.pref == api.type.enum.TrafficLightPreference.NO then offs[x.cmd.p.lights.node] = true end
	end
	local n = 0
	for c in pairs(townCentres) do if offs[c] then n = n + 1 end end
	eq(n, nTowns, "every town centre (the in far node) switched off")
	ok(not all:find("lights at the in join", 1, true), "not listed as a problem")
end)

test("Lights showcase entries: a town street hung on an arm end before the read -> that stub removed (logged), the arms read again, joined", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local hit, stub
	afterBuild = function(ce)
		if ce.name ~= ENTRY_NAME or hit then return end
		local r = ce.transf[4]
		for id, p in pairs(nodes) do
			if math.abs(p.x - r[1]) < 1e-6 and math.abs(p.y - (r[2] + logic.ENTRY_REACH)) < 1e-6 then
				stub = newEdge(id, newNode(p.x + 30, p.y + 30))   -- the town's street off the dead end
				hit = true
			end
		end
	end
	-- the engine applies a street removal (the stray street's proposal)
	local removed = {}
	beforeCb = function(cmd)
		local sp = cmd.p and cmd.p.streetProposal
		if sp and sp.edgesToRemove and not sp.edgesToAdd and not (cmd.p.constructionsToAdd and cmd.p.constructionsToAdd[1]) then
			for _, e in ipairs(sp.edgesToRemove) do removed[#removed + 1] = e end
			applyStreet(sp)
		end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(hit)
	ok(all:find(" kind=roundabout stray street " .. stub .. " (arm end ", 1, true) and all:find(") removed", 1, true), all)
	eq(removed, { stub })
	ok(not all:find("arms not read", 1, true), all)
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, townTotal(L))
end)

local function strayCase(dx, dy, withBuilding)
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local hit, stub
	afterBuild = function(ce)
		if ce.name ~= ENTRY_NAME or hit then return end
		local r = ce.transf[4]
		for id, p in pairs(nodes) do
			if math.abs(p.x - r[1]) < 1e-6 and math.abs(p.y - (r[2] + logic.ENTRY_REACH)) < 1e-6 then
				stub = newEdge(id, newNode(p.x + dx, p.y + dy))
				if withBuilding then
					parcelsOf = { [stub] = { 9001 } }
					buildingOn = { [9001] = 9100 }
				end
				hit = true
			end
		end
	end
	local removed = {}
	beforeCb = function(cmd)
		local sp = cmd.p and cmd.p.streetProposal
		if sp and sp.edgesToRemove and not sp.edgesToAdd and not (cmd.p.constructionsToAdd and cmd.p.constructionsToAdd[1]) then
			for _, e in ipairs(sp.edgesToRemove) do removed[#removed + 1] = e end
			applyStreet(sp)
		end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	ok(hit)
	return logText(), stub, removed, L
end

test("Lights showcase entries: a short sideways town stub (20 m, both ends near the centre) on an arm end -> removed, joined", function()
	local all, stub, removed, L = strayCase(20, 0)
	ok(all:find(" kind=roundabout stray street " .. stub .. " (arm end ", 1, true), all)
	eq(removed, { stub })
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, townTotal(L))
end)

test("Lights showcase entries: a short outward town stub (15 m) on an arm end -> removed, joined", function()
	local all, stub, removed, L = strayCase(0, 15)
	ok(all:find(" kind=roundabout stray street " .. stub .. " (arm end ", 1, true), all)
	eq(removed, { stub })
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, townTotal(L))
end)

test("Lights showcase entries: a town stub with a town building on its parcels is never removed (said why), arms not read", function()
	local all, stub, removed = strayCase(20, 0, true)
	eq(removed, {})
	ok(all:find("stray street not removed: ", 1, true) and all:find("town buildings on it", 1, true), all)
	ok(all:find(" kind=roundabout arms not read (ends=3 found=", 1, true), all)
end)

test("Lights showcase entries: an arm end with a longer town street (not a stub) is left alone -> arms not read, nothing removed", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local hit
	afterBuild = function(ce)
		if ce.name ~= ENTRY_NAME or hit then return end
		local r = ce.transf[4]
		for id, p in pairs(nodes) do
			if math.abs(p.x - r[1]) < 1e-6 and math.abs(p.y - (r[2] + logic.ENTRY_REACH)) < 1e-6 then
				local m = newNode(p.x + 30, p.y + 30)
				newEdge(id, m)
				newEdge(m, newNode(p.x + 60, p.y + 60))
				newEdge(m, newNode(p.x + 60, p.y))
				hit = true
			end
		end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(hit)
	ok(all:find(" kind=roundabout stray street not removed: ", 1, true) and all:find("does not end in a dead end", 1, true), all)
	ok(all:find(" kind=roundabout arms not read (ends=3 found=", 1, true), all)
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, townTotal(L) - 1)
end)

test("Lights showcase entries: build-time locks that answer late and refused: the closing lock step waits for them, then locks them; none left unlocked", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local tries = {}
	lockRefuse = function(label)
		tries[label] = (tries[label] or 0) + 1
		return tries[label] == 1 and label:find(" entry$") ~= nil
	end
	lockDelay = function(label) return (tries[label] or 0) <= 1 and label:find(" entry$") and 5000 or nil end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(not all:find("its streets not all locked", 1, true), all)
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, townTotal(L))
end)

test("Lights showcase entries: each entry's streets are locked in its own build callback; one that can't lock there is locked later; the last ones in one lock", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	-- every first lock refused (as if the streets were still the construction's): the later lock takes them
	local tries = {}
	lockRefuse = function(label)
		tries[label] = (tries[label] or 0) + 1
		return tries[label] == 1 and label:find(" entry$") ~= nil
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	local firstAtBuild, many = 0, 0
	for _, lk in ipairs(entryLocks) do
		if lk.label:find(" entry$") then firstAtBuild = firstAtBuild + 1 end
		if lk.label:find("^%d+ entries$") then many = many + 1 end
	end
	ok(firstAtBuild >= nTowns, "a lock at every build")
	ok(many >= 1, "the closing lock step locks the rest in one call")
	ok(not all:find("its streets not all locked", 1, true), all)
	local _, nJoined = all:gsub(" kind=roundabout joined=3/3", "")
	eq(nJoined, nTowns)
end)

test("Lights showcase entries: a lock refused for one entry -> said at its read, listed, its set no match; still read and joined", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local g = L.groups[1]
	local town = L.towns[g.towns[1]]
	lockRefuse = function(label) return label == town.name .. " entry" end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(all:find("entry " .. town.name .. " kind=roundabout locked=0 of 8 streets failed=8 age=", 1, true), all)
	ok(all:find("entry " .. town.name .. " kind=roundabout its streets not all locked (0 locked)", 1, true), all)
	ok(all:find("entry " .. town.name .. " kind=roundabout joined=3/3", 1, true), all)
	ok(all:find("showcase zone id=g" .. g.set .. "%a pair=g" .. g.set .. " [^\n]* match=no reason=entry") ~= nil, all)
	ok(rt.warnings[1] and rt.warnings[1].body:find(town.name .. " entry: its streets not all locked", 1, true), "listed")
end)

test("Lights showcase entries: an arm end that gains a street between the read and the join is not joined (said why), never copied stale", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	local g = L.groups[1]
	local town = L.towns[g.towns[1]]
	local sc = logic.sideCentre(town.x, town.y, logic.gridHalfOfSize(town.size), g.place.x, g.place.y)
	-- the junction reads come after every entry read and before the joins: a town street hung on one of the
	-- entry's 46 m arm ends then
	local oct = api.engine.util.octree.findEntitiesInCircle
	local done = false
	api.engine.util.octree.findEntitiesInCircle = function(c, r, ct)
		local afterReads = false
		for _, en in ipairs(log_entries()) do
			if en.msg:find(" kind=roundabout read ends=", 1, true) then afterReads = true break end
		end
		if not done and afterReads and math.abs(c.x - g.place.x) < 1 and math.abs(c.y - g.place.y) < 1 then
			for id, p in pairs(nodes) do
				local d = math.sqrt((p.x - sc[1]) ^ 2 + (p.y - sc[2]) ^ 2)
				if not done and math.abs(d - logic.ENTRY_REACH) < 1e-6 then
					local m = node2edges()[id]
					if m and #m == 1 then
						newEdge(id, newNode(p.x + 30, p.y + 30))
						done = true
					end
				end
			end
		end
		return oct(c, r, ct)
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	ok(done, "hung after the read")
	ok(all:find("entry " .. town.name .. " kind=roundabout read", 1, true) or not all:find("entry " .. town.name .. " kind=roundabout arms not read", 1, true), all)
	ok(all:find("has 2 streets now, not 1", 1, true), all)
	ok(not all:find("can't be cast", 1, true))
	ok(all:find("entry " .. town.name .. " kind=roundabout joined=2/3", 1, true), all)
end)

test("Lights showcase entries: a light switch-off refused is tried once more; refused twice -> listed, its set no match", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	litNode = function(n) return townCentres[n] == true end
	afterBuild = function(ce)
		if ce.name ~= ENTRY_NAME then return end
		for _, x in ipairs(sent) do
			if x.cmd.p.constructionsToAdd and x.cmd.p.constructionsToAdd[1] == ce then
				applyStreet(x.cmd.p.streetProposal)
				for _, en in ipairs(x.cmd.p.streetProposal.nodeConfigsToAdd or {}) do
					if cfgOverride[en.entity] and cfgOverride[en.entity].trafficLightConfig then
						cfgOverride[en.entity].trafficLightConfig = { states = {} }
					end
				end
			end
		end
	end
	local offTries = 0
	failCmd = function(cmd)
		if cmd.p and cmd.p.lights and cmd.p.lights.pref == api.type.enum.TrafficLightPreference.NO then
			offTries = offTries + 1
			return true
		end
		return false
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	eq(offTries, 2 * nTowns, "each tried twice")
	local _, n = all:gsub("kind=roundabout lights off refused twice at ", "")
	eq(n, nTowns)
	ok(rt.warnings[1] and rt.warnings[1].body:find("lights not switched off at node", 1, true), "listed")
	ok(not all:find(" sets_mismatch=0", 1, true), all)
end)

test("Lights showcase entries: a lit far grid node gets the removed leg's light states back on the joined leg (movement by movement, its crosswalk re-added); unlit far nodes unchanged", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	jlogic.LINK_GROUP_MAX = 8
	litNode = function(n) return townCentres[n] == true end
	-- the engine applies each entry's removal and written configs (the joins read the far nodes after them)
	afterBuild = function(ce)
		if ce.name ~= ENTRY_NAME then return end
		for _, x in ipairs(sent) do
			if x.cmd.p.constructionsToAdd and x.cmd.p.constructionsToAdd[1] == ce then applyStreet(x.cmd.p.streetProposal) end
		end
	end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local nTowns = townTotal(L)
	local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
	-- the entry proposals drop the removed leg from the lit centre, phases in range
	for _, cmd in ipairs(entryCmds()) do
		eq(nc.problems(cmd.p.streetProposal, function() return 4 end), {})
	end
	-- every join line: the lit centre ("in") carried, the unlit ring dead ends not listed
	local carried = 0
	for _, en in ipairs(log_entries()) do
		if en.msg:find(" kind=roundabout joined=", 1, true) then
			ok(en.msg:find(" joined=3/3 lights=in:carried$") ~= nil, en.msg)
			carried = carried + 1
		end
	end
	eq(carried, nTowns)
	local checked = 0
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd and isEntryJoin(sp) then
			eq(cfgProblems(sp), {})
			local centre
			for _, n in ipairs(sp.nodesToRemove) do if townCentres[n] then centre = n end end
			ok(centre, "the join replaces the town centre")
			local before = firstCfg[centre]
			-- the replacement node (same spot) and its config
			local temp
			for _, ne in ipairs(sp.nodesToAdd) do
				if ne.comp.position.x == nodes[centre].x and ne.comp.position.y == nodes[centre].y then temp = ne.entity end
			end
			local cfg
			for _, en in ipairs(sp.nodeConfigsToAdd) do
				if en.entity == temp then cfg = en.comp
				else eq(en.comp.trafficLightConfig, nil, "an unlit node stays unlit") end
			end
			-- temp edges back to the legs they stand for: copies to their source, the joined piece to the removed leg
			local legs, removed = {}, nil
			for _, e in ipairs(before.crosswalks) do
				legs[e] = true
				if edges[e] == nil then removed = e end
			end
			ok(removed, "a removed leg")
			local orig = {}
			for _, seg in ipairs(sp.edgesToAdd) do
				local src = tonumber(seg.comp.tag:match("^edge(%d+)$"))
				orig[seg.entity] = legs[src] and src or removed
			end
			local function key(c) return tostring(orig[c.segment0] or c.segment0) .. ">" .. tostring(orig[c.segment1] or c.segment1) end
			eq(#cfg.crosswalks, #before.crosswalks, "the removed leg's crosswalk re-added")
			eq(#cfg.trafficLightConfig.states, #before.trafficLightConfig.states)
			local sawNew = false
			for i, st in ipairs(cfg.trafficLightConfig.states) do
				local was, wasCw = {}, {}
				local bl = {}
				for _, l in ipairs(before.trafficLightConfig.states[i].lockedLanes) do bl[l] = true end
				for k, c in ipairs(before.laneConnections) do was[c.segment0 .. ">" .. c.segment1] = bl[k - 1] == true end
				for j, cw in ipairs(before.crosswalks) do wasCw[cw] = bl[#before.laneConnections + j - 1] == true end
				local now = {}
				for _, l in ipairs(st.lockedLanes) do now[l] = true end
				for k, c in ipairs(cfg.laneConnections) do
					if orig[c.segment0] == removed or orig[c.segment1] == removed then sawNew = true end
					eq(now[k - 1] == true, was[key(c)], string.format("phase %d %s", i, key(c)))
				end
				for j, cw in ipairs(cfg.crosswalks) do
					eq(now[#cfg.laneConnections + j - 1] == true, wasCw[orig[cw]], string.format("phase %d crosswalk %s", i, tostring(orig[cw])))
				end
			end
			ok(sawNew, "the joined leg's connections")
			checked = checked + 1
		end
	end
	eq(checked, nTowns)
	ok(all:find(" sets_mismatch=0", 1, true), all)
	eq(#rt.warnings, 0)
end)

test("Lights showcase entries: the settle waits when only town entries were built (every junction refused), before their arms are read", function()
	local L = lightsMap()
	lightPref = function() return api.type.enum.TrafficLightPreference.YES end
	refuseCheck = function(ce) if ce.name ~= ENTRY_NAME then return "Collision" end end
	jn.buildLightsShowcase(SEED, 1)
	run(4000, "Lights showcase done")
	local all = logText()
	local at = all:find(string.format("lights_showcase: 0 junctions built (and %d town entries); reading their arms in 3 s", townTotal(L)), 1, true)
	ok(at, all)
	local readAt = all:find(" kind=roundabout read ends=4", 1, true)
	ok(readAt and readAt > at, "entries read after the settle")
end)

test("Showcase: a link never ends on another town's node, even when it lies nearer the arm inside this town's search circle", function()
	local L = smallMap()
	local g = firstOf(L, "plain")
	local ti = g.towns[1]
	local town = L.towns[ti]
	local half = logic.gridHalfOfSize(town.size)
	-- a dead end of another town, between the arm and this town: outside this town's grid, inside its
	-- search circle (spacing x 0.5), nearer the arm than any of its own nodes
	local decoy
	afterBuild = function()
		if decoy then return end
		local dx, dy = g.place.x - town.x, g.place.y - town.y
		local d = math.sqrt(dx * dx + dy * dy)
		local r = half + logic.OWN_TOWN_MARGIN + 60
		local x, y = CX + town.x + dx / d * r, CY + town.y + dy / d * r
		decoy = newNode(x, y)
		newEdge(newNode(x + 30, y + 30), decoy)
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	ok(decoy, "decoy placed")
	for _, cmd in ipairs(linkProposals()) do
		for _, id in ipairs(cmd.p.streetProposal.nodesToRemove or {}) do ok(id ~= decoy, "the decoy is never a link target") end
	end
	ok(logText():find("-> " .. town.name .. " linked", 1, true), logText())
end)

test("Showcase: a refused link logs what it collided with (entity kinds)", function()
	local L = smallMap()
	local g = firstOf(L, "rb")
	local town = L.towns[g.towns[1]]
	local first = true
	failCmd = function(cmd)
		if first and touches(cmd, CX + town.x, CY + town.y, 350) then
			first = false
			refuse(cmd, "Collision")
			cmd.resultProposalData.collisionInfo = { collisionEntities = { { entity = 1001 } } }
			return true
		end
		return false
	end
	jn.buildShowcase(SEED)
	run(3000, "Showcase done")
	ok(logText():find("-> " .. town.name .. ": link refused (critical=false messages={Collision} (hits 1 other BASE_NODE e.g. #1001)); trying again", 1, true), logText())
end)

---------------------------------------------------------------------------
-- Bench sheets (plans/square_stress_test/BENCH.md): built by the shared Showcase code

local benchlib = ug_require "square_stress_test::/stress/stress_bench.tl"

--- Sheet 1 as it was in version 1 (roundabouts and lane drops; the lane drop left the real sheet in version 2): the
--- build tests keep both junction kinds and the lane drop's geometry path covered.
local function oldSheet1()
	local V = benchlib.VARIANTS
	return { id = "bench_s1", key = "s1", title = "Bench sheet 1: roundabouts and lane drops", version = 1, minKm = 16, slLights = true,
		tests = {
			{ id = "rb4", title = "Roundabout", variants = { V.rb4 }, towns = { "N", "E", "S", "W" }, twins = { "game", "sl", "sl_keeplights" },
				compare = { { "sl", "game" }, { "sl", "sl_keeplights" } }, sets = 9, linkLanes = 0 },
			{ id = "drop", title = "Lane drop", variants = { V.drop }, towns = { "E", "W" }, twins = { "game", "sl" },
				compare = { { "sl", "game" } }, sets = 6, linkLanes = 0 },
		} }
end

--- Every link piece's template (entry joins left out), per proposal.
local function linkTemplates()
	local out = {}
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd and not isEntryJoin(sp) then
			for _, seg in ipairs(sp.edgesToAdd) do
				if seg.comp.roadTemplate and seg.comp.roadTemplate:find("/country/", 1, true) then out[seg.comp.roadTemplate] = (out[seg.comp.roadTemplate] or 0) + 1 end
			end
		end
	end
	return out
end

local function finishTimed()
	-- the lock pass and the growth answer (the stubs keep their onDone): the run's timing, then its finished hook
	for _, c in ipairs(lockCalls) do if c.opts and c.opts.onDone then c.opts.onDone(10) end end
	for _, c in ipairs(growCalls) do if c.onDone then c.onDone(10) end end
end

test("bench sheet 1 (16 km): 9 roundabout sets x game / sl / sl_keeplights and 6 lane-drop sets x game / sl, every town entered and linked at its arm's lanes, zones and BENCH_TWIN lines, the finished hook", function()
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	benchGeo = true
	jlogic.LINK_GROUP_MAX = 8
	local sheet = oldSheet1()
	local fin = {}
	jn.onRunFinished = function(name, seed, layout, zones) fin[#fin + 1] = { name = name, seed = seed, groups = #layout.groups, zones = #zones } end
	ok(jn.buildBench(sheet, SEED))
	run(4000, sheet.title .. " done")
	local all = logText()
	ok(all:find("[SQST] bench_s1: seed=12 map=16000x16000m groups=39 sets=15 rb4=27 drop=12 twins game=15 sl=15 sl_keeplights=9 towns=132 (Medium)", 1, true), all:sub(1, 3000))
	ok(all:find("by_ab=game:15,sl:15,sl_phases:0,sl_keeplights:9", 1, true), all)
	local kinds = {}
	for _, ce in ipairs(constructions()) do
		local k = ce.params.sqrb_arms and "rb4" or (ce.params.sqst_x_shape == 4 and "drop" or "?")
		kinds[k] = (kinds[k] or 0) + 1
		eq(ce.transf[1][1], 1, "rotation 0")
	end
	eq(kinds, { rb4 = 27, drop = 12 })
	eq(#entryCmds(), 132)
	eq(linkedLines(), 132)
	-- links at the arm's own lanes: the fake arms are 2-lane roads, the lane drop's west arm 3 lanes each way: a large
	-- link only there (12 twins)
	local large = 0
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp.edgesToAdd and not isEntryJoin(sp) then
			for _, seg in ipairs(sp.edgesToAdd) do
				if (seg.comp.roadTemplate or ""):find("country_new_large", 1, true) then large = large + 1 break end
			end
		end
	end
	ok(large >= 1 and large <= 12, "large links: " .. large)
	ok(all:find(" sets_mismatch=0", 1, true), all)
	-- zones: test and variant, sl_keeplights twins with letter f, town names say the mode
	local slz = ug_require "square_stress_test::/stress/gui/stress_slzones.tl"
	local nF = 0
	for _, z in ipairs(slz.current.zones) do
		ok(z.test == "rb4" or z.test == "drop", tostring(z.test))
		ok(z.approach ~= nil and z.approach > 300 and z.approach < 600, tostring(z.approach))
		if z.ab == "sl_keeplights" then
			nF = nF + 1
			ok(z.id:match("^s1g%d+f$"), z.id)
		end
	end
	eq(nF, 9)
	ok(all:find("[SQST] showcase zone id=s1g1", 1, true) and all:find(" pair=s1g1 ", 1, true) and all:find(" test=rb4 variant=RB4_2L approach=", 1, true), all)
	local _, nTwin = all:gsub("%[SQST%] BENCH_TWIN id=s1g%d+%a test=%w+ ab=[%w_]+ nodes=%d+ lit_nodes=%d+ phase=read geometry=ok", "")
	eq(nTwin, 39)
	ok(all:find("geometry=ok what=lane_drop two_street_nodes=1 lanes=6>2", 1, true), all:match("BENCH_TWIN id=s1g1[0-9]a[^\n]*"))
	ok(all:find("geometry=ok what=one_way_streets n=3", 1, true), "the ring's one-way streets")
	ok(all:find("Keep lights 1 N", 1, true) or all:find("Keep lights 1 E", 1, true), "town names")
	-- the settle waited for Smart Lanes (absent here: at once)
	ok(all:find("[SQST] bench_s1 smart_lanes idle=absent", 1, true), all)
	eq(#fin, 0, "not finished before the lock pass and the growth answered")
	finishTimed()
	eq(#fin, 1)
	eq(fin[1], { name = "bench_s1", seed = 12, groups = 39, zones = 39 })
	jn.onRunFinished = nil
end)

test("bench sheet 2 (16 km): channelized T and diamond twins; the diamond's highway arms reach their towns as carriageway pairs merging into a 2 + 2 country road, its S arm without a town", function()
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	benchGeo = true
	benchIx = true
	jlogic.LINK_GROUP_MAX = 8
	local sheet = benchlib.sheet("s2")
	ok(jn.buildBench(sheet, SEED))
	run(4000, sheet.title .. " done")
	local all = logText()
	ok(all:find(" groups=39 sets=15 cht=27 dia=12 twins game=15 sl=15 sl_keeplights=9 towns=117 (Medium)", 1, true), all:sub(1, 3000))
	eq(#entryCmds(), 117)
	eq(linkedLines(), 117)
	local tpl = linkTemplates()
	ok((tpl["::/infrastructure/street/country/country_new_medium.street_template"] or tpl["country/country_new_medium.street_template"] or 0) > 0
		or next(tpl) ~= nil, "templates")
	local medium = 0
	for t, n in pairs(tpl) do
		ok(not t:find("_large", 1, true), t)
		if t:find("country_new_medium", 1, true) then medium = medium + n end
	end
	ok(medium >= 24, "every diamond highway arm's merge piece is country medium: " .. medium)
	ok(all:find(" sets_mismatch=0", 1, true), all)
	-- every street proposal's node configs complete (Engine.h:323: no config-less script node), no -0 anywhere
	for _, x in ipairs(sent) do
		local sp = x.cmd.p.streetProposal
		if sp and sp.edgesToAdd then eq(cfgProblems(sp), {}) end
		local ce = x.cmd.p.constructionsToAdd and x.cmd.p.constructionsToAdd[1]
		if ce then
			for _, row in ipairs(ce.transf) do
				for _, v in ipairs(row) do ok(not (v == 0 and 1 / v < 0), "no -0 in a transform") end
			end
		end
	end
end)

test("bench: a busy test refuses a sheet (false, dialog), nothing sent", function()
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	rt.enqueue("lights_showcase", 1, function() end)
	eq(jn.buildBench(benchlib.sheet("s3"), SEED), false)
	eq(#sent, 0)
end)

test("bench variants: every fixed param one of its construction's values, with the label the bench means", function()
	local want = {
		bench_rb4 = { sqrb_arms = "4", sqrb_arm_type = "Country, medium", sqrb_signals = "Off", sqrb_lanes = "2" },
		bench_cht = { sqrb_ch_layout = "T", sqrb_ch_main = "Country, medium", sqrb_ch_side = "Country, medium", sqrb_ch_slips = "Near-side corners" },
		bench_dia = { sqrb_ix_highway = "M", sqrb_ix_cross = "Country, large", sqrb_hx_scale = "S" },
		bench_drop = { sqst_x_shape = "Straight", sqst_x_main = "Country large", sqst_x_main2 = "Country medium", sqst_x_lights = "Game decides" },
	}
	for _, v in pairs(benchlib.VARIANTS) do
		local counts, labels = conParams(v.file)
		ok(counts ~= nil, v.file)
		if counts == nil then return end
		for k, x in pairs(v.fixed) do
			ok(counts[k] ~= nil, v.id .. ": " .. k)
			ok(x >= 1 and x <= (counts[k] or 0), v.id .. ": " .. k .. "=" .. x)
		end
		for k, label in pairs(want[v.id]) do eq(labels[k][v.fixed[k]], label, v.id .. " " .. k) end
	end
end)

test("bench: Smart Lanes not acknowledging the twins' zones stops the bench build at once (onRunAborted, no junction); the Showcases go on as before", function()
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	slParams = {}
	slZrun = function() return "someone-else" end
	local why
	jn.onRunAborted = function(name, w) why = { name, w } end
	ok(jn.buildBench(benchlib.sheet("s3"), SEED))
	run(400)
	local all = logText()
	ok(all:find("[SQST] bench_s3 zones ack=timeout", 1, true), all:sub(1, 2000))
	ok(all:find("[SQST] bench_s3 stopped: Smart Lanes did not acknowledge the zones (ack=timeout)", 1, true), all:sub(1, 2000))
	eq(why, { "bench_s3", "Smart Lanes did not take the twins' zones (ack=timeout)" })
	eq(#constructions(), 0, "no junction built")
	jn.onRunAborted = nil
end)

test("bench: while a bench run is active the Showcases refuse (dialog), the bench's own build does not", function()
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	jn.benchActive = true
	eq(jn.buildLightsShowcase(SEED), nil)
	eq(#sent, 0)
	ok(logText():find("A bench run is in progress", 1, true))
	ok(jn.buildBench(benchlib.sheet("s3"), SEED))
	jn.benchActive = false
end)

test("bench geometry check: a lane drop built with one road on both arms, a ring without one-way streets: BENCH_TWIN geometry=bad, the sets no match (reason=geometry, zone_match lines), listed", function()
	box = { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } }
	benchGeo, sameDropLanes, noRing = true, true, true
	jlogic.LINK_GROUP_MAX = 8
	local sheet = oldSheet1()
	ok(jn.buildBench(sheet, SEED))
	run(4000, sheet.title .. " done")
	local all = logText()
	ok(all:find("geometry=bad what=lane_drop two_street_nodes=1 lanes=same", 1, true), all:sub(1, 2000))
	ok(all:find("geometry=bad what=one_way_streets n=0", 1, true))
	ok(all:find(" sets_mismatch=15", 1, true), "every set no match")
	ok(all:find("[SQST] showcase zone_match id=s1g1a pair=s1g1 match=no reason=geometry", 1, true), "late verdict for twins read before the bad one")
	ok(all:find("geometry does not present its test", 1, true))
end)

test("bench lane drop variant: the crossing's own geometry has the large road (3 + 3) on the west arm and the medium road (2 + 2) on the east arm (main2 6 = ROADS[5]: main2 / side2 values are offset by one, 1 = the same road)", function()
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	local r = cross.result(benchlib.VARIANTS.drop.fixed)
	eq(#r.edgeLists, 2)
	local byX = {}
	for _, el in ipairs(r.edgeLists) do
		for k = 1, #el.edges, 2 do
			local a, b = el.edges[k][1], el.edges[k + 1][1]
			byX[(a[1] + b[1]) < 0 and "west" or "east"] = el.params.type
		end
	end
	ok(byX.west:find("country_new_large", 1, true), byX.west)
	ok(byX.east:find("country_new_medium", 1, true), byX.east)
	-- and the rings' / channel's arm roads, the diamond's cross road (the variants' labels are checked above)
	eq(benchlib.VARIANTS.rb4.fixed.sqrb_arm_type, 5)
	eq(benchlib.VARIANTS.cht.fixed.sqrb_ch_main, 5)
	eq(benchlib.VARIANTS.dia.fixed.sqrb_ix_cross, 6)
end)
