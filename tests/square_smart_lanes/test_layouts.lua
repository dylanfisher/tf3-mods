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
	local W = F.PROBE_2LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 19132)
	local a = Rules.planRing(W, ring, all(W), "two_lane", function() return {} end)
	local t = Rules.planRing(W, ring, all(W), "turbo", function() return {} end)
	eq(a.turbo, true)
	eq(t.turbo, true)
	for i, r in ipairs(a.nodes) do eq(Rules.connsText(t.nodes[i].conns), Rules.connsText(r.conns)) end
end)

test("Turbo falls back to Matched lanes with a reason: 1-lane exits, single-lane ring, skipped junction", function()
	-- small arms: 1 exit lane
	local W = F.PROBE_2LANE_SMALL.world()
	local ring = Ring.findRing(W, 17955)
	local p = Rules.planRing(W, ring, all(W), "turbo", function() return {} end)
	eq(p.turbo, false)
	eq(p.turboReason, "narrow_exit")
	local m = Rules.planRing(W, ring, all(W), "matched", function() return {} end)
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
	eq(Pick.describe(ringNode), "Junction 22768 on roundabout 22768 (4 lanes, 4 arms)")
	eq(Pick.detail(ringNode), "10 lane connections, 2 exit, 2 entry lanes")
	eq(Pick.describe({ kind = "node", node = 7, roads = 4, conns = 12 }), "Junction 7 (4 roads, not a roundabout)")
	ok(Pick.detail({ kind = "node", node = 7, roads = 4, conns = 12 }):find("not handled yet", 1, true))
	eq(Pick.describe({ kind = "ring", ringKey = 3, ringLanes = 2, junctions = 1 }), "Roundabout 3: 2 lanes, 1 arm")
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
	eq({ b({ kind = "ring", total = 4, smart = 0, default = 4 }) }, { "default", "Game default", nil })
	eq({ b({ kind = "ring", total = 6, smart = 3, default = 3 }) }, { "partial", "Smart lanes on 3 of 6 junctions", "warning" })
	eq({ b({ kind = "ring", total = 4, smart = 0, default = 2 }) }, { "custom", "Custom lanes", "warning" })
	eq({ b({ kind = "node", total = 1, smart = 0, default = 0 }) }, { "custom", "Custom lanes", "warning" })
	eq({ b({ kind = "slip", total = 1, smart = 1 }) }, { "smart", "Smart lanes", "positive" })
	eq({ b({ kind = "slip", total = 1, smart = 0 }) }, { "custom", "Custom", nil })
	eq({ b({ kind = "na" }) }, { "na", "Not handled", nil })
	eq({ b(nil) }, { "na", "Not handled", nil })
	eq({ b({ kind = "ring", total = 0, smart = 0, default = 0 }) }, { "na", "Not handled", nil })
	-- labels stay short enough for the toolbar (tooltipWhenClipped shows the rest)
	ok(#Pick.badge({ kind = "ring", total = 12, smart = 10, default = 0 }).label <= 33)
end)

test("roadText ignores tram flags and tram-only connections", function()
	local a = F.parseConns("1:1>2:1:R-,1:2>2:2:RT,3:1>4:1:-T")
	local b = F.parseConns("1:2>2:2:R-,1:1>2:1:R-")
	eq(Rules.roadText(a), Rules.roadText(b))
	ok(Rules.connsText(a) ~= Rules.connsText(b))
end)
