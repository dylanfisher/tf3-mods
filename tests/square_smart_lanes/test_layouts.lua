-- square_smart_lanes Phase 2: tool layouts (Matched lanes / Turbo / Game default), the Reset
-- decision (sl_rules.lua) and the pick helpers (sl_pick.lua).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local function all(world)
	local s = {}
	for id in pairs(world.nodes) do s[id] = true end
	return s
end

local function byNode(p)
	local m = {}
	for _, r in ipairs(p.nodes) do m[r.node] = r end
	return m
end

local function hasConn(list, s0, l0, s1, l1)
	for _, c in ipairs(list) do
		if c.segment0 == s0 and c.lane0 == l0 and c.segment1 == s1 and (l1 == nil or c.lane1 == l1) then return true end
	end
	return false
end

--- Does the outer ring lane continue at node r (any connection ringIn:o1 -> ringOut)?
local function outerContinues(r)
	return hasConn(r.conns, r.view.ringIn, r.view.o_in[1], r.view.ringOut)
end

---------------------------------------------------------------------------
-- Layouts

test("the tool has one layout: Smart lanes (turbo where the ring qualifies)", function()
	eq(Rules.LAYOUTS, { "turbo" })
	eq(Rules.layoutFromValue(1), "turbo")
	eq(Rules.layoutFromValue(nil), "turbo")
	eq(Rules.LAYOUT_NAMES.turbo, "Smart lanes")
end)

test("Matched lanes never makes the outer lane exit-only, even on a fresh qualifying ring", function()
	local W = F.PROBE_4LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 22768)
	local p = Rules.planRing(W, ring, all(W), "matched", function() return {} end)
	eq(p.turbo, false)
	eq(p.turboReason, "matched")
	for _, r in ipairs(p.nodes) do
		eq(r.status, "apply")
		ok(outerContinues(r), "outer lane continues at " .. r.node)
		ok(hasConn(r.conns, r.view.ringIn, r.view.o_in[1], r.view.arm, r.view.x[1]), "outer lane exits")
	end
end)

test("Turbo on a single junction of a qualifying ring: exit-only outer lane although not fresh", function()
	local W = F.PROBE_4LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 22768)
	local auto = Rules.planRing(W, ring, { [22768] = true }, "two_lane", function() return {} end)
	-- planRing's automatic rule on seeds alone (the automatic pass seeds whole rings, Rules.autoSeeds, and
	-- plans only the seeds like this beside a hand-edited junction)
	eq(auto.turbo, false, "automatic rule: not fresh -> safe rule")
	eq(auto.turboReason, "not_fresh")
	local p = Rules.planRing(W, ring, { [22768] = true }, "turbo", function() return {} end)
	eq(p.fresh, false)
	eq(p.turbo, true)
	local r = byNode(p)[22768]
	eq(r.status, "apply")
	eq(outerContinues(r), false)
	for _, x in ipairs(p.nodes) do
		if x.node ~= 22768 then eq(x.status, "untouched") end
	end
end)

test("Turbo equals the automatic rule on a fresh ring", function()
	-- a 4-lane ring (until 2026-10-15 this used the 2-lane probe ring 19132, which now gets matched lanes: next test)
	local W = F.PROBE_4LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 22768)
	local a = Rules.planRing(W, ring, all(W), "two_lane", function() return {} end)
	local t = Rules.planRing(W, ring, all(W), "turbo", function() return {} end)
	eq(a.turbo, true)
	eq(t.turbo, true)
	eq({ a.default, t.default }, { nil, nil })
	for i, r in ipairs(a.nodes) do eq(Rules.connsText(t.nodes[i].conns), Rules.connsText(r.conns)) end
end)

test("2-lane ring with 2-lane exits: the automatic rule and the tool's Apply give matched lanes (user decision 2026-10-15)", function()
	local W = F.PROBE_2LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 19132)
	local m = Rules.planRing(W, ring, all(W), "matched", function() return {} end)
	for _, variant in ipairs({ "two_lane", "turbo" }) do
		local p = Rules.planRing(W, ring, all(W), variant, function() return {} end)
		eq(p.turbo, false, variant)
		eq({ p.turboReason, p.default, p.defaultWhy, p.layout }, { "two_lane_ring", true, "two_lane_exits", "matched" }, variant)
		eq({ p.split, p.splitWanted, p.mids }, { nil, nil, nil }, variant)
		for i, r in ipairs(p.nodes) do
			eq(r.status, "apply")
			ok(outerContinues(r), variant .. ": outer lane continues at " .. r.node)
			eq(Rules.connsText(r.conns), Rules.connsText(m.nodes[i].conns), variant)
		end
	end
	-- not fresh (the automatic rule beside a hand-edited junction): the same matched lanes on the seed
	local p = Rules.planRing(W, ring, { [19132] = true }, "two_lane", function() return {} end)
	eq(p.turbo, false)
	ok(outerContinues(byNode(p)[19132]), "seed alone: matched")
	-- the bench's turbo twin (zone mode sl_rturbo) still builds turbo on the same ring
	local z = Rules.planRing(W, ring, all(W), "sl_rturbo", function() return {} end)
	eq(z.layout, "sl_rturbo")
	for _, r in ipairs(z.nodes) do
		if #r.view.x > 0 then eq(outerContinues(r), false, "sl_rturbo: exit-only outer lane at " .. r.node) end
	end
end)

test("Turbo falls back with a reason: 1-lane exits (2-lane ring: the spiral since 2026-10-14), single-lane ring, skipped junction", function()
	-- small arms: 1 exit lane on a 2-lane ring without mid nodes: the default spiral sl_rspiral (PLAN.md "Default: the
	-- mid-node spiral"; before 2026-10-14 matched lanes)
	local W = F.PROBE_2LANE_SMALL.world()
	local ring = Ring.findRing(W, 17955)
	local p = Rules.planRing(W, ring, all(W), "turbo", function() return {} end)
	eq(p.turbo, false)
	eq(p.turboReason, "narrow_exit")
	eq({ p.default, p.layout, p.split }, { true, "sl_rspiral", "no_mid_nodes" })
	local m = Rules.planRing(W, ring, all(W), "sl_rspiral", function() return {} end)
	for i, r in ipairs(p.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(m.nodes[i].conns)) end
	-- single-lane ring
	local W1 = F.ring({ ringTpl = "highway_small", arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local p1 = Rules.planRing(W1, Ring.findRing(W1, 1), all(W1), "turbo", function() return {} end)
	eq(p1.turboReason, "one_lane_ring")
	-- road through the centre: skipped junctions
	local W2 = F.ring({ ringTpl = "one_way_small",
		arms = { { tpl = "medium", through = true }, { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local p2 = Rules.planRing(W2, Ring.findRing(W2, 2), all(W2), "turbo", function() return {} end)
	eq(p2.turbo, false)
	eq(p2.turboReason, "skip_node")
end)

test("automatic setting Game default is never planned; the tool's engine variant writes the model", function()
	local W = F.PROBE_4LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 22768)
	local p = Rules.planRing(W, ring, all(W), "game", function() return {} end)
	for _, r in ipairs(p.nodes) do eq(r.status, "skip") end
	local e = Rules.planRing(W, ring, all(W), "engine", function() return {} end)
	for _, r in ipairs(e.nodes) do
		eq(r.status, "apply")
		eq(Rules.connsText(r.conns), Rules.connsText(Rules.defaultConns(r.view, {})))
	end
end)

test("defaultConns: the engine default model plus the node's tram connections", function()
	local W = F.ring({ ringTpl = "one_way_small_tram", arms = { { tpl = "small_tram" }, { tpl = "small_tram" }, { tpl = "small_tram" } } })
	local ring = Ring.findRing(W, 1)
	local v = Ring.nodeView(W, ring, 1)
	local tram = Rules.conn(v.ringIn, v.o_in[2], v.ringOut, v.o_out[2], false, true)
	local d = Rules.defaultConns(v, { tram })
	eq(Rules.roadCount(d), #Rules.engineDefault(v))
	local trams = 0
	for _, c in ipairs(d) do if c.withTram then trams = trams + 1 end end
	eq(trams, 1)
end)


---------------------------------------------------------------------------
-- Picking

test("promote: edge hits near an end become that node, the middle stays the edge", function()
	local e = { node0 = 10, node1 = 11, p0 = { x = 0, y = 0 }, p1 = { x = 90, y = 0 } }
	-- 90 m segment: snap radius min(15, 30) = 15
	local n, d, r = Pick.promote({ x = 5, y = 3 }, e)
	eq(n, 10)
	near(r, 15)
	near(d, math.sqrt(34))
	eq((Pick.promote({ x = 80, y = 0 }, e)), 11)
	eq((Pick.promote({ x = 45, y = 0 }, e)), nil)
	eq((Pick.promote({ x = 16, y = 0 }, e)), nil)
	-- 12 m segment: radius 4, middle (6 m from both ends) is the edge
	local s = { node0 = 1, node1 = 2, p0 = { x = 0, y = 0 }, p1 = { x = 12, y = 0 } }
	local n2, _, r2 = Pick.promote({ x = 6, y = 0 }, s)
	eq(n2, nil)
	near(r2, 4)
	eq((Pick.promote({ x = 3, y = 0 }, s)), 1)
	eq((Pick.promote({ x = 9.5, y = 0 }, s)), 2)
	-- equidistant inside the radius: node0 wins
	eq((Pick.promote({ x = 1, y = 0 }, { node0 = 1, node1 = 2, p0 = { x = 0, y = 0 }, p1 = { x = 2, y = 0 } }, 15)), nil)
	eq((Pick.promote({ x = 0.3, y = 0 }, { node0 = 1, node1 = 2, p0 = { x = 0, y = 0 }, p1 = { x = 3, y = 0 } }, 15)), 1)
end)

test("colorIndices: one colour per outgoing segment, stable by segment id", function()
	local conns = F.parseConns("5:1>9:1:R-,5:1>7:2:R-,6:1>9:2:R-,6:2>7:1:R-")
	eq(Pick.colorIndices(conns), { 2, 1, 2, 1 })
	eq(Pick.colorIndices({}), {})
	local many = {}
	for i = 1, #Pick.PALETTE + 1 do many[i] = { segment0 = 1, lane0 = 1, segment1 = 100 + i, lane1 = 1 } end
	local idx = Pick.colorIndices(many)
	eq(idx[#many], 1, "palette wraps")
end)

test("status texts and target keys", function()
	eq(Pick.targetKey(nil), "none")
	eq(Pick.targetKey({ kind = "node", node = 5 }), "node:5")
	eq(Pick.targetKey({ kind = "ring", ringKey = 3 }), "ring:3")
	local ringNode = { kind = "node", node = 22768, ringKey = 22768, ringLanes = 4, junctions = 4, conns = 10,
		nodeKind = "arm", exits = 2, entries = 2, roads = 3 }
	eq(Pick.describe(ringNode), "Roundabout junction (4 lanes, 4 arms)")
	eq(Pick.detail(ringNode), "10 lane connections, 2 exit, 2 entry lanes")
	eq(Pick.describe({ kind = "node", node = 7, roads = 4, conns = 12 }), "Junction, 4 roads")
	eq(Pick.detail({ kind = "node", node = 7, roads = 4, conns = 12 }), "not handled: no rule for this junction shape")
	eq(Pick.detail({ kind = "node", node = 7, roads = 2, conns = 2 }), "2 lane connections, no junction here")
	-- skip reasons read as phrases, never as log ids
	eq(Pick.detail({ kind = "node", node = 7, roads = 3, conns = 16, slipReason = "bus_lane_ring" }),
		"not handled: the ring has a bus lane")
	eq(Pick.detail({ kind = "node", node = 7, roads = 5, conns = 20, slipReason = "roads_5" }),
		"not handled: 5 roads meet (at most 4)")
	eq(Pick.reasonText("one_way_4"), "one-way roads only")
	eq(Pick.reasonText("something_new"), "no rule for this junction shape")
	eq(Pick.detail({ kind = "node", node = 7, ringKey = 3, nodeKind = "skip", reason = "multi_arm", conns = 9 }),
		"not handled: two or more roads join here")
	-- not handled: the reason alone, no Smart lights line repeating it (user 2026-10-17)
	eq(Pick.detail({ kind = "node", node = 7, roads = 4, conns = 12, slipReason = "bus_road", lights = { why = "shape" } }),
		"not handled: a road has only bus lanes")
	eq(Pick.exitOnlyText("narrow_exit"), "an exit has only one lane")
	eq(Pick.exitOnlyText(nil), "the roundabout does not qualify")
	-- slip-lane junctions: shape in the head, lane counts in words in the detail
	local slip = { kind = "node", node = 8, roads = 3, conns = 6, nodeKind = "slip", slipShape = "diverge", slipLanes = 2,
		slipCounts = { { shape = "diverge", main = 2, through = 2, branch = 1 } } }
	eq(Pick.describe(slip), "Slip lane leaving the road, 2 lanes")
	eq(Pick.detail(slip), "2 lanes in: 2 straight on, 1 into the slip lane, 6 lane connections")
	eq(Pick.slipText({ { shape = "merge", through = 2, branch = 1, out = 2 } }), "2 straight on and 1 from the slip lane into 2 lanes")
	eq(Pick.describe({ kind = "ring", ringKey = 3, ringLanes = 2, junctions = 1 }), "Roundabout: 2 lanes, 1 arm")
	local st = Pick.status(nil, "Smart lanes", nil)
	eq(st.head, "Nothing selected")
	eq(st.detail, "Click a junction or a roundabout")
	st = Pick.status(ringNode, "Smart lanes", nil)
	eq(st.detail, "10 lane connections, 2 exit, 2 entry lanes")
	st = Pick.status(ringNode, "Smart lanes", "Smart lanes applied to 4 junctions")
	eq(st.detail, "Smart lanes applied to 4 junctions")
end)

test("allow: logs a change at most every gap seconds, never the same key twice in a row", function()
	local lim = {}
	ok(Pick.allow(lim, "a", 0, 0.3))
	eq(Pick.allow(lim, "a", 5, 0.3), false)
	eq(Pick.allow(lim, "b", 0.1, 0.3), false)
	ok(Pick.allow(lim, "b", 0.4, 0.3))
	ok(Pick.allow(lim, "a", 0.8, 0.3))
end)

---------------------------------------------------------------------------
-- Lane status badge (pure)

test("badge: smart / default / partial / custom / not handled, slip never claims custom", function()
	local function b(info) local r = Pick.badge(info) return r.key, r.label, r.class end
	eq({ b({ kind = "ring", total = 4, smart = 4, default = 0 }) }, { "smart", "Smart lanes", "positive" })
	eq({ b({ kind = "node", total = 1, smart = 1, default = 1 }) }, { "smart", "Smart lanes (= game default)", "positive" })
	-- the reason when every road has one car lane each way (a player's report 2026-10-14), and the bus lanes
	eq({ b({ kind = "slip", total = 1, smart = 1, default = 1, oneLane = true }) },
		{ "smart", "Smart lanes = game default (one car lane per road)", "positive" })
	eq({ b({ kind = "slip", total = 1, smart = 1, default = 1, oneLane = true, bus = true }) },
		{ "smart", "Smart lanes = game default (one car lane per road; bus lanes kept)", "positive" })
	eq({ b({ kind = "street", total = 2, smart = 2, default = 2, oneLane = false, bus = true }) },
		{ "smart", "Smart lanes (= game default)", "positive" }, "not every junction one lane: no reason given")
	eq({ b({ kind = "slip", total = 1, smart = 1, oneLane = true }) }, { "smart", "Smart lanes", "positive" }, "no model: plain smart")
	eq({ b({ kind = "ring", total = 4, smart = 0, default = 4 }) }, { "default", "Game default", nil })
	eq({ b({ kind = "ring", total = 6, smart = 3, default = 3 }) }, { "partial", "Smart lanes on 3 of 6 junctions", "warning" })
	eq({ b({ kind = "ring", total = 4, smart = 0, default = 2 }) }, { "custom", "Custom lanes", "warning" })
	eq({ b({ kind = "node", total = 1, smart = 0, default = 0 }) }, { "custom", "Custom lanes", "warning" })
	eq({ b({ kind = "slip", total = 1, smart = 1 }) }, { "smart", "Smart lanes", "positive" })
	eq({ b({ kind = "slip", total = 1, smart = 0 }) }, { "custom", "Game or custom lanes", nil })
	-- crossroads / T-junctions (kind "slip" with a game-default model): Game default when it matches, else
	-- the neutral label (the model misses some game-built shapes: never claim a hand edit there)
	eq({ b({ kind = "slip", total = 1, smart = 0, default = 1 }) }, { "default", "Game default", nil })
	eq({ b({ kind = "slip", total = 1, smart = 0, default = 0 }) }, { "custom", "Game or custom lanes", nil })
	eq({ b({ kind = "na" }) }, { "na", "Not handled", nil })
	eq({ b(nil) }, { "na", "Not handled", nil })
	eq({ b({ kind = "ring", total = 0, smart = 0, default = 0 }) }, { "na", "Not handled", nil })
	-- labels stay short enough for the toolbar (tooltipWhenClipped shows the rest)
	ok(#Pick.badge({ kind = "ring", total = 12, smart = 10, default = 0 }).label <= 33)
end)

test("oneLaneEach: every approach enters on one lane (road connections, bus-lane ones left out)", function()
	eq(Rules.oneLaneEach(F.parseConns("1:1>2:1:R-,1:1>3:1:R-,2:1>1:1:R-")), true)
	eq(Rules.oneLaneEach(F.parseConns("1:1>2:1:R-,1:2>3:1:R-")), false, "two lanes from road 1")
	eq(Rules.oneLaneEach(F.parseConns("1:1>2:1:R-,1:2>3:1:-T")), true, "a tram-only connection does not count")
	eq(Rules.oneLaneEach(F.parseConns("1:1>2:1:R-,1:2>3:1:R-"), { [1] = { [2] = true } }), true, "lane 2 a bus lane")
	eq(Rules.oneLaneEach({}), false)
	eq(Rules.oneLaneEach(nil), false)
end)

test("roadText ignores tram flags and tram-only connections", function()
	local a = F.parseConns("1:1>2:1:R-,1:2>2:2:RT,3:1>4:1:-T")
	local b = F.parseConns("1:2>2:2:R-,1:1>2:1:R-")
	eq(Rules.roadText(a), Rules.roadText(b))
	ok(Rules.connsText(a) ~= Rules.connsText(b))
end)
