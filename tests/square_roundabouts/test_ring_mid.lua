-- Dev override ringMid (sqrb_dev_ring_mid = 1): a plain ring node half way between every two neighbouring
-- arms (geom.ringParams minPieces), for square_smart_lanes' sl_rsplit layout on the Stress Test bench (Sheet 4
-- v3, bench_rb2tm). Without the override every ring is as before (test_default_unchanged / golden tests).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local K = geom.PARAM_KEYS

local PI = math.pi
local atan2 = math.atan2 or math.atan

-- the bench's ring (square_stress_test stress_bench.tl VARIANTS.rb2t): 2 ring lanes, XS, 4 arms, town small arms
local BENCH = { sqrb_shape = 1, sqrb_centre = 1, sqrb_lanes = 2, sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1,
	sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1, sqrb_arm_type = 1 }

local function params(over, mid)
	local p = {}
	for k, v in pairs(BENCH) do p[k] = v end
	for k, v in pairs(over or {}) do p[k] = v end
	if mid ~= nil then p[geom.DEV_KEYS.ringMid] = mid end
	return p
end

local function build(over, mid) return geom.build(geom.readParams(params(over, mid))) end

local function angleOf(p)
	local a = atan2(p[2], p[1])
	if a < 0 then a = a + 2 * PI end
	return a
end

-- ring node angles (deg, ascending) and which of them an arm starts at
local function ringNodes(built)
	local armAt = {}
	for _, e in ipairs(built.arms.edges) do armAt[string.format("%.3f,%.3f", e.p0[1], e.p0[2])] = true end
	local out = {}
	for _, n in ipairs(built.ring.nodes) do
		out[#out + 1] = { deg = angleOf(n.pos) * 180 / PI, arm = armAt[string.format("%.3f,%.3f", n.pos[1], n.pos[2])] == true, pos = n.pos }
	end
	table.sort(out, function(a, b) return a.deg < b.deg end)
	return out
end

test("ringParams: minPieces splits every gap between different groups, evenly", function()
	local ts, armAt = geom.ringParams({ 0, PI / 2, PI, 3 * PI / 2 }, nil, 2, { 1, 2, 3, 4 })
	eq(#ts, 8)
	for i, t in ipairs(ts) do near(t, (i - 1) * PI / 4, 1e-9) end
	eq(armAt[1], 1); eq(armAt[3], 2); eq(armAt[5], 3); eq(armAt[7], 4)
	eq(armAt[2], nil); eq(armAt[4], nil)
	-- without minPieces: as before (one edge per 90 degree gap)
	local ts0 = geom.ringParams({ 0, PI / 2, PI, 3 * PI / 2 })
	eq(#ts0, 4)
	-- a gap already split by maxAngle (180 degrees: 2 edges) keeps its count; the 90 degree ones get 2
	local tsT = geom.ringParams({ 0, PI / 2, PI }, nil, 2, { 1, 2, 3 })
	eq(#tsT, 6)
	-- the two legs of one arm (same group) stay one edge apart, the gaps to other arms are split
	local tsS = geom.ringParams({ 0, 0.2, PI, PI + 0.2 }, nil, 2, { 1, 1, 2, 2 })
	eq(#tsS, 6)
	near(tsS[2], 0.2, 1e-9)
end)

test("readDev: sqrb_dev_ring_mid 1 is read, other values ignored", function()
	eq(geom.readDev({ sqrb_dev_ring_mid = 1 }).ringMid, 1)
	eq(geom.readDev({ sqrb_dev_ring_mid = 0 }).ringMid, 0)
	eq(geom.readDev({ sqrb_dev_ring_mid = 2 }).ringMid, 2)
	eq(geom.readDev({ sqrb_dev_ring_mid = 0.5 }), nil)
	eq(geom.readDev({}), nil)
end)

test("bench ring with ringMid: 8 ring nodes, a plain node half way between neighbouring arms, same radius", function()
	local plain = build(nil, nil)
	local mid = build(nil, 1)
	local off = build(nil, 0)
	eq(#plain.ring.nodes, 4)
	eq(#off.ring.nodes, 4)
	eq(#mid.ring.nodes, 8)
	eq(#mid.ring.edges, 8)
	-- identical geometry otherwise: radius, ellipse, arms
	eq(mid.radius, plain.radius)
	near(mid.a, plain.a, 1e-9)
	near(mid.b, plain.b, 1e-9)
	eq(#mid.arms.edges, #plain.arms.edges)
	for i, e in ipairs(plain.arms.edges) do
		near(mid.arms.edges[i].p0[1], e.p0[1], 1e-9)
		near(mid.arms.edges[i].p0[2], e.p0[2], 1e-9)
	end
	-- alternating arm / plain nodes, the plain ones at 45 degrees from both neighbours
	local nodes = ringNodes(mid)
	local arms = 0
	for i, n in ipairs(nodes) do
		local nxt = nodes[i % #nodes + 1]
		ok(n.arm ~= nxt.arm, "arm and plain nodes alternate")
		local d = (nxt.deg - n.deg) % 360
		near(d, 45, 1e-6, "45 degrees apart")
		if n.arm then arms = arms + 1 end
	end
	eq(arms, 4)
	-- every ring edge at least MIN_EDGE long (the chord rule) and the offline plan accepted it
	for _, e in ipairs(mid.ring.edges) do
		local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
		ok(math.sqrt(dx * dx + dy * dy) >= geom.MIN_EDGE - 1e-9, "edge chord >= MIN_EDGE")
	end
	print(string.format("bench ring: radius %g, a %.2f, ring edge chord %.2f m, forced=%s offline=%s engine=%s",
		mid.radius, mid.a, math.sqrt((mid.ring.edges[1].p1[1] - mid.ring.edges[1].p0[1]) ^ 2 + (mid.ring.edges[1].p1[2] - mid.ring.edges[1].p0[2]) ^ 2),
		tostring(mid.forced), tostring(mid.offline), tostring(mid.engine)))
end)

test("ringMid on other rings: 1 and 4 lanes, 3 / 5 / 6 arms, CW; arms None gets 2 nodes", function()
	for _, lanes in ipairs({ 1, 2, 3 }) do
		for _, arms in ipairs({ 1, 2, 3, 4, 5 }) do
			for _, dir in ipairs({ 1, 2 }) do
				local b = build({ sqrb_lanes = lanes, sqrb_arms = arms, sqrb_direction = dir }, 1)
				local nodes = ringNodes(b)
				local nArms = 0
				for i, n in ipairs(nodes) do
					if n.arm then
						nArms = nArms + 1
						ok(not nodes[i % #nodes + 1].arm, "a plain node after every arm node")
					end
				end
				eq(nArms, #b.arms.edges)
			end
		end
	end
	local none = build({ sqrb_arms = 6 }, 1)
	ok(#none.ring.nodes >= 4)
end)

test("ringMid with splitter islands: the legs of one arm stay neighbours, plain nodes between arms", function()
	local b = build({ sqrb_splitter = 2, sqrb_arm_type = 2 }, 1)
	local b0 = build({ sqrb_splitter = 2, sqrb_arm_type = 2 }, nil)
	eq(#b.ring.nodes, 4 * 2 + 4)
	eq(#b0.ring.nodes, 8)
end)

test("ringMid 2 and 3: that many plain nodes evenly between neighbouring arms; the bench's 4-lane ring (country large arms)", function()
	for _, n in ipairs({ 2, 3 }) do
		local b = build(nil, n)
		eq(#b.ring.nodes, 4 * (n + 1))
		local nodes = ringNodes(b)
		for i, nd in ipairs(nodes) do
			local nxt = nodes[i % #nodes + 1]
			near((nxt.deg - nd.deg) % 360, 90 / (n + 1), 1e-6)
		end
	end
	-- bench_rb4lm: square_stress_test VARIANTS.rb4l (4 ring lanes, XS, 4 arms, Country large) with 3 mid nodes per gap
	local over = { sqrb_lanes = 3, sqrb_arm_type = 6 }
	local plain, mid = build(over, nil), build(over, 3)
	eq(#mid.ring.nodes, 16)
	for _, e in ipairs(mid.ring.edges) do
		local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
		ok(math.sqrt(dx * dx + dy * dy) >= geom.MIN_EDGE - 1e-9, "edge chord >= MIN_EDGE")
	end
	print(string.format("rb4l: radius %g without mid nodes, %g with 3 per gap (forced=%s offline=%s engine=%s); edge chord %.1f m",
		plain.radius, mid.radius, tostring(mid.forced), tostring(mid.offline), tostring(mid.engine),
		math.sqrt((mid.ring.edges[1].p1[1] - mid.ring.edges[1].p0[1]) ^ 2 + (mid.ring.edges[1].p1[2] - mid.ring.edges[1].p0[2]) ^ 2)))
	ok(mid.forced ~= true, "not a forced plan")
	eq(geom.readDev({ sqrb_dev_ring_mid = 3 }).ringMid, 3)
	eq(geom.readDev({ sqrb_dev_ring_mid = 4 }), nil)
end)

test("no menu param for it: the menu's rings are as before (Smart Lanes splits the ring itself); the dev override only", function()
	ug_require(DIR .. "square_roundabouts.con.lua")
	for _, p in ipairs(data().params) do ok(not p.key:find("ring_mid", 1, true), p.key) end
	eq(geom.PARAM_KEYS.ringMid, nil)
	-- the menu's 2-lane Town small ring: 4 ring nodes at every Scale; with the override 8, smooth (no corner)
	for size = 1, 5 do
		local base = { sqrb_shape = 1, sqrb_lanes = 2, sqrb_radius_size = size, sqrb_arms = 3, sqrb_splitter = 1, sqrb_arm_type = 1 }
		eq(#geom.build(geom.readParams(base)).ring.nodes, 4)
		base.sqrb_dev_ring_mid = 1
		local b = geom.build(geom.readParams(base))
		eq(#b.ring.nodes, 8)
		for i, e in ipairs(b.ring.edges) do
			local nxt = b.ring.edges[i % #b.ring.edges + 1]
			local c = (e.t1[1] * nxt.t0[1] + e.t1[2] * nxt.t0[2]) / (math.sqrt(e.t1[1] ^ 2 + e.t1[2] ^ 2) * math.sqrt(nxt.t0[1] ^ 2 + nxt.t0[2] ^ 2))
			near(c, 1, 1e-9, "smooth at every ring node")
		end
	end
end)
