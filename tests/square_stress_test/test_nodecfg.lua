-- stress_nodecfg.tl: node configs (BASE_NODE_CONFIG) for script street proposals. Every node a proposal
-- adds gets one (empty on a 1-edge node), an existing node that gains an edge a full new one (remove + add
-- only when it has a config), lane indices from each segment's own lanes and direction.

local edges, configs, map

-- laneConfigs fixtures: index 1 and the last are sidewalks (PERSON), the rest road lanes (CAR, BUS, TRUCK)
local function lane(forward, road, tram)
	local tm = road and { [2] = true, [3] = true, [4] = true } or { [0] = true }
	if tram then tm[5] = true end
	return { forward = forward, transportModes = tm }
end
local TWO4 = { lane(false), lane(false, true), lane(true, true), lane(true) }
local TWO8 = { lane(false), lane(false, true), lane(false, true), lane(false, true), lane(true, true), lane(true, true), lane(true, true), lane(true) }
local ONE4 = { lane(true), lane(true, true), lane(true, true), lane(true) }
local TRAM4 = { lane(false), lane(false, true, true), lane(true, true, true), lane(true) }

local function fakeApi()
	return {
		type = {
			ComponentType = { BASE_EDGE = "BASE_EDGE", BASE_NODE_CONFIG = "BASE_NODE_CONFIG" },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			LaneConnection = { new = function() return { ctor = true } end },
			TrafficLightState = { new = function() return { ctor = true } end },
		},
		engine = {
			getComponent = function(e, ct)
				if ct == "BASE_EDGE" then return edges[e] end
				if ct == "BASE_NODE_CONFIG" then return configs[e] end
			end,
			system = { streetSystem = { getNode2StreetEdgeMap = function() return map end } },
		},
	}
end

local nc
before_each(function()
	edges, configs, map = {}, {}, {}
	reset_modules()
	set_global("api", fakeApi())
	nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
end)

local function seg(id, n0, n1, lanes, t)
	return { entity = id, comp = { node0 = n0, node1 = n1, laneConfigs = lanes, tangent0 = t or { x = 1, y = 0, z = 0 }, tangent1 = t or { x = 1, y = 0, z = 0 } } }
end

local function conns(entry)
	local out = {}
	for _, c in ipairs(entry.comp.laneConnections) do
		out[#out + 1] = string.format("%d.%d>%d.%d%s", c.segment0, c.lane0, c.segment1, c.lane1, c.withTram and "t" or "")
	end
	table.sort(out)
	return table.concat(out, " ")
end

local function entryOf(list, node)
	for _, e in ipairs(list) do if e.entity == node then return e end end
end

test("side: two-way lanes arrive on the left half, leave on the right, the same from both ends", function()
	for _, atEnd in ipairs({ 0, 1 }) do
		local s = nc.side(TWO4, atEnd)
		eq(s.ins, { 1 })
		eq(s.outs, { 2 })
		eq(s.lanes, 4)
		local w = nc.side(TWO8, atEnd)
		eq(w.ins, { 1, 2, 3 })
		eq(w.outs, { 6, 5, 4 }, "outer lane first")
	end
	-- one-way: all lanes leave at node0, all arrive at node1 (outer = driver's right first)
	eq(nc.side(ONE4, 0).outs, { 2, 1 })
	eq(nc.side(ONE4, 0).ins, {})
	eq(nc.side(ONE4, 1).ins, { 1, 2 })
	eq(nc.side(ONE4, 1).outs, {})
	-- unreadable lanes: a two-way street of the given count (4 by default)
	eq(nc.side(nil, 0).ins, { 1 })
	eq(nc.side(nil, 1, 8).outs, { 6, 5, 4 })
	-- lanes without modes (plain fixtures): every lane but the sidewalks is a road lane
	local plain = nc.side({ { forward = false }, { forward = false }, { forward = true }, { forward = true } }, 0)
	eq({ plain.ins, plain.outs }, { { 1 }, { 2 } })
	eq(nc.side(TRAM4, 0).tram, { [1] = true, [2] = true })
end)

test("pattern: the engine's town junction (a.1 > b.2 per ordered pair); a two-street joint of different widths fans the far lane", function()
	local s4 = nc.side(TWO4, 0)
	local p = nc.pattern({ 10, 11, 12 }, { [10] = s4, [11] = s4, [12] = s4 })
	eq(#p, 6)
	for _, c in ipairs(p) do ok(c[1] ~= c[3] and c[2] == 1 and c[4] == 2, "a.1 > b.2") end
	-- a joint: 8-lane street (3 each way) meets a 4-lane one (1 each way): the three arriving lanes all merge into
	-- the single leaving one, and the single arriving lane fans into all three (kerb first, no crossing)
	local q = nc.pattern({ 1, 2 }, { [1] = nc.side(TWO8, 0), [2] = s4 })
	eq(q, { { 1, 1, 2, 2, 0 }, { 1, 2, 2, 2, 0 }, { 1, 3, 2, 2, 0 }, { 2, 1, 1, 6, 0 }, { 2, 1, 1, 5, 0 }, { 2, 1, 1, 4, 0 } })
	-- the rig's case (2026-10-13 lane audit): a 2-lane arm (6 lanes incl. sidewalks) joins the 3-lane link (8):
	-- arm lanes 1 > link 6 (kerb), 2 > link 5 and 4 (the far lane fans); link 1 > arm 4, link 2 and 3 > arm 3
	local two6 = nc.side(TWO8, 0)
	local arm = nc.side({ TWO8[1], TWO8[2], TWO8[3], TWO8[6], TWO8[7], TWO8[8] }, 0)
	local r = nc.pattern({ 7, 8 }, { [7] = arm, [8] = two6 })
	local fromArm, intoArm = {}, {}
	for _, c in ipairs(r) do
		if c[1] == 7 then fromArm[#fromArm + 1] = c[2] .. ">" .. c[4] else intoArm[#intoArm + 1] = c[2] .. ">" .. c[4] end
	end
	eq(fromArm, { "1>6", "2>5", "2>4" })
	eq(intoArm, { "1>4", "2>3", "3>3" })
	-- at a junction (3+ streets) still one-to-one for the smaller count
	local j = nc.pattern({ 1, 2, 3 }, { [1] = nc.side(TWO8, 0), [2] = s4, [3] = s4 })
	for _, c in ipairs(j) do
		if c[1] == 1 and c[3] == 2 then eq({ c[2], c[4] }, { 1, 2 }) end
	end
	-- the junctionConns wrapper by counts (the depot gate): the same
	local lcs = nc.junctionConns({ 60, -3 }, { [60] = 4, [-3] = 4 })
	eq(#lcs, 2)
	ok(lcs[1].ctor, "LaneConnection.new")
	eq({ lcs[1].segment0, lcs[1].lane0, lcs[1].segment1, lcs[1].lane1, lcs[1].withRoad, lcs[1].withTram }, { 60, 1, -3, 2, true, false })
	eq(#nc.junctionConns({ 5 }, {}), 0, "a dead end has none")
end)

test("pattern: one-way continuation lane i > m + 1 - i; no reversal between segments leaving side by side", function()
	local inS, outS = nc.side(ONE4, 1), nc.side(ONE4, 0)
	eq(nc.pattern({ 1, 2 }, { [1] = inS, [2] = outS }), { { 1, 1, 2, 2, 0 }, { 1, 2, 2, 1, 0 } })
	-- a highway's merge node: carriageway A arrives, B leaves, both lie towards the junction (dirs 10 deg
	-- apart); the two-way street on leads away. A > street, street > B, never A > B (a U-turn).
	local a, b, st = nc.side(ONE4, 1), nc.side(ONE4, 0), nc.side(TWO4, 0)
	a.dir = { -1, 0 }
	b.dir = { -math.cos(math.rad(10)), math.sin(math.rad(10)) }
	st.dir = { 1, 0 }
	local p = nc.pattern({ 1, 2, 3 }, { [1] = a, [2] = b, [3] = st })
	eq(p, { { 1, 1, 3, 2, 0 }, { 3, 1, 2, 2, 0 } })
	-- covered pairs (kept from an old config) are left out
	local s4 = nc.side(TWO4, 0)
	eq(#nc.pattern({ 1, 2, 3 }, { [1] = s4, [2] = s4, [3] = s4 }, { [1] = true, [2] = true }), 4)
	-- tram only where both lanes carry the track
	local t = nc.side(TRAM4, 0)
	eq(nc.pattern({ 1, 2 }, { [1] = t, [2] = t })[1][5], 1)
	eq(nc.pattern({ 1, 2 }, { [1] = t, [2] = s4 })[1][5], 0)
end)

test("configs: new nodes get the pattern, a 1-edge new node an empty config, none of them removed", function()
	local list = {
		seg(-1, -4, -5, TWO4),
		seg(-2, -5, -6, TWO4),
		seg(-3, -5, -7, TWO8, { x = 0, y = 1, z = 0 }),
	}
	local add, rm = nc.configs(list, {}, {})
	eq(rm, {})
	eq(#add, 4)
	eq(#entryOf(add, -4).comp.laneConnections, 0, "dead end: empty")
	eq(#entryOf(add, -6).comp.laneConnections, 0)
	eq(conns(entryOf(add, -5)), "-1.1>-2.2 -1.1>-3.6 -2.1>-1.2 -2.1>-3.6 -3.1>-1.2 -3.1>-2.2")
	ok(entryOf(add, -5).comp.laneConnections[1].ctor, "LaneConnection.new")
	eq(nc.problems({ edgesToAdd = list, nodeConfigsToAdd = add, nodeConfigsToRemove = rm }), {})
	-- `have` nodes are left to the caller
	local add2 = nc.configs(list, {}, { [-5] = true })
	eq(#add2, 3)
	eq(entryOf(add2, -5), nil)
end)

test("configs: an existing node that gains an edge: its config kept + the new segment's pairs, remove + add", function()
	-- node 7: edges 70 (to 8) and 71 (to 9), a config 70 <> 71 and a crosswalk; a new edge -1 joins it
	edges[70] = { node0 = 7, node1 = 8, laneConfigs = TWO4, tangent0 = { x = 1, y = 0 }, tangent1 = { x = 1, y = 0 } }
	edges[71] = { node0 = 9, node1 = 7, laneConfigs = TWO4, tangent0 = { x = 1, y = 0 }, tangent1 = { x = 1, y = 0 } }
	map[7] = { 70, 71 }
	configs[7] = { laneConnections = {
		{ segment0 = 70, lane0 = 1, segment1 = 71, lane1 = 2, withRoad = true, withTram = false },
		{ segment0 = 71, lane0 = 1, segment1 = 70, lane1 = 2, withRoad = true, withTram = false },
	}, crosswalks = { 70 } }
	local add, rm = nc.configs({ seg(-1, 7, -2, TWO4, { x = 0, y = 1, z = 0 }) }, {}, {})
	eq(rm, { 7 })
	local e = entryOf(add, 7)
	eq(conns(e), "-1.1>70.2 -1.1>71.2 70.1>-1.2 70.1>71.2 71.1>-1.2 71.1>70.2")
	eq(e.comp.crosswalks, { 70 })
	eq(#entryOf(add, -2).comp.laneConnections, 0)
	-- a removed edge is dropped from the kept config and from the pattern
	add, rm = nc.configs({ seg(-1, 7, -2, TWO4, { x = 0, y = 1, z = 0 }) }, { 71 }, {})
	eq(conns(entryOf(add, 7)), "-1.1>70.2 70.1>-1.2")
	eq(entryOf(add, 7).comp.crosswalks, { 70 })
end)

test("configs: an existing node without a config gets a fresh one, add only (removing a missing one asserts)", function()
	edges[70] = { node0 = 7, node1 = 8, laneConfigs = TWO4, tangent0 = { x = 1, y = 0 }, tangent1 = { x = 1, y = 0 } }
	map[7] = { 70 }
	local list = { seg(-1, 7, -2, TWO4, { x = 0, y = 1, z = 0 }) }
	local add, rm = nc.configs(list, {}, {})
	eq(rm, {})
	eq(conns(entryOf(add, 7)), "-1.1>70.2 70.1>-1.2")
	eq(nc.problems({ edgesToAdd = list, nodeConfigsToAdd = add, nodeConfigsToRemove = rm }), {})
end)

test("configs: a replacement node (seed) carries the old node's config over to the copies, plus the link's pairs", function()
	-- old node 7 (a grid corner: 70, 71 with 70 <> 71) is replaced by -10; copies -1 (of 70), -2 (of 71);
	-- the link piece -3 joins it
	configs[7] = { laneConnections = {
		{ segment0 = 70, lane0 = 1, segment1 = 71, lane1 = 2, withRoad = true, withTram = false },
		{ segment0 = 71, lane0 = 1, segment1 = 70, lane1 = 2, withRoad = true, withTram = false },
	}, crosswalks = { 71 } }
	local list = { seg(-1, -10, 8, TWO4), seg(-2, 9, -10, TWO4), seg(-3, -10, -11, TWO4, { x = 0, y = 1, z = 0 }) }
	local add = nc.configs(list, { 70, 71 }, { [8] = true, [9] = true }, { [-10] = { node = 7, newIds = { [70] = -1, [71] = -2 } } })
	local e = entryOf(add, -10)
	eq(conns(e), "-1.1>-2.2 -1.1>-3.2 -2.1>-1.2 -2.1>-3.2 -3.1>-1.2 -3.1>-2.2")
	eq(e.comp.crosswalks, { -2 })
	-- a dead end's seed has no connections: the full pattern
	configs[7] = { laneConnections = {}, crosswalks = { 70 } }
	add = nc.configs({ seg(-1, -10, 8, TWO4), seg(-3, -10, -11, TWO4, { x = 0, y = 1, z = 0 }) }, { 70 }, { [8] = true },
		{ [-10] = { node = 7, newIds = { [70] = -1 } } })
	eq(conns(entryOf(add, -10)), "-1.1>-3.2 -3.1>-1.2")
	eq(entryOf(add, -10).comp.crosswalks, { -1 })
end)

-- a node config's light phases: lockedLanes per phase; clone() as the engine's TrafficLightConfig
local function lights(locked)
	local function clone(self)
		local c = { states = {}, clone = clone, trafficLightType = self.trafficLightType }
		for i, st in ipairs(self.states) do c.states[i] = st end
		return c
	end
	local tlc = { states = {}, clone = clone, trafficLightType = -1 }
	for i, l in ipairs(locked) do tlc.states[i] = { lockedLanes = l, duration = 10 + i, minDuration = 1.5, canSkip = true } end
	return tlc
end

local function phases(entry)
	local out = {}
	for i, st in ipairs(entry.comp.trafficLightConfig.states) do
		local l = {}
		for _, x in ipairs(st.lockedLanes) do l[#l + 1] = x end
		table.sort(l)
		out[i] = l
	end
	return out
end

test("configs: a lit node that gains an edge gets its phases re-pointed (connections, then crosswalks)", function()
	-- node 7: A = 70.1>71.2 (index 0), B = 71.1>70.2 (1), crosswalks 70 (2) and 71 (3)
	edges[70] = { node0 = 7, node1 = 8, laneConfigs = TWO4, tangent0 = { x = 1, y = 0 }, tangent1 = { x = 1, y = 0 } }
	edges[71] = { node0 = 9, node1 = 7, laneConfigs = TWO4, tangent0 = { x = 1, y = 0 }, tangent1 = { x = 1, y = 0 } }
	map[7] = { 70, 71 }
	local tlc = lights({ { 0, 3 }, { 1, 2 } })
	configs[7] = { laneConnections = {
		{ segment0 = 70, lane0 = 1, segment1 = 71, lane1 = 2, withRoad = true, withTram = false },
		{ segment0 = 71, lane0 = 1, segment1 = 70, lane1 = 2, withRoad = true, withTram = false },
	}, crosswalks = { 70, 71 }, trafficLightConfig = tlc }
	local list = { seg(-1, 7, -2, TWO4, { x = 0, y = 1, z = 0 }) }
	local add, rm = nc.configs(list, {}, {})
	local e = entryOf(add, 7)
	-- new list: A, B, 70.1>-1.2 (2), 71.1>-1.2 (3), -1.1>70.2 (4), -1.1>71.2 (5); crosswalks at 6, 7.
	-- Phase 1: A, its approach 70's new turn, crosswalk 71; phase 2: B, 71's new turn, crosswalk 70.
	-- The new approach -1 has no history: unlocked.
	eq(phases(e), { { 0, 2, 7 }, { 1, 3, 6 } })
	eq(e.comp.trafficLightConfig.states[1].duration, 11, "durations kept")
	ok(e.comp.trafficLightConfig.states[1].ctor, "TrafficLightState.new")
	ok(e.comp.trafficLightConfig ~= tlc, "a clone, not the read config")
	eq(tlc.states[1].lockedLanes, { 0, 3 }, "the read phases untouched")
	eq(nc.problems({ edgesToAdd = list, nodeConfigsToAdd = add, nodeConfigsToRemove = rm }), {})
	-- 71 removed: A, B and crosswalk 71 dropped; crosswalk 70 moves to index 2 (a fresh read: the fake
	-- entry.comp is the read table itself)
	configs[7] = { laneConnections = {
		{ segment0 = 70, lane0 = 1, segment1 = 71, lane1 = 2, withRoad = true, withTram = false },
		{ segment0 = 71, lane0 = 1, segment1 = 70, lane1 = 2, withRoad = true, withTram = false },
	}, crosswalks = { 70, 71 }, trafficLightConfig = lights({ { 0, 3 }, { 1, 2 } }) }
	add, rm = nc.configs(list, { 71 }, {})
	e = entryOf(add, 7)
	eq(conns(e), "-1.1>70.2 70.1>-1.2")
	eq(phases(e), { {}, { 2 } })
	eq(nc.problems({ edgesToAdd = list, nodeConfigsToAdd = add, nodeConfigsToRemove = rm }), {})
end)

test("configs: a replaced lit node's phases follow the copies; a node without phases gets none written", function()
	configs[7] = { laneConnections = {
		{ segment0 = 70, lane0 = 1, segment1 = 71, lane1 = 2, withRoad = true, withTram = false },
		{ segment0 = 71, lane0 = 1, segment1 = 70, lane1 = 2, withRoad = true, withTram = false },
	}, crosswalks = { 70, 71 }, trafficLightConfig = lights({ { 1, 3 } }) }
	local list = { seg(-1, -10, 8, TWO4), seg(-2, 9, -10, TWO4), seg(-3, -10, -11, TWO4, { x = 0, y = 1, z = 0 }) }
	local add = nc.configs(list, { 70, 71 }, { [8] = true, [9] = true }, { [-10] = { node = 7, newIds = { [70] = -1, [71] = -2 } } })
	-- B (-2.1>-1.2) stays index 1, its approach's new turn -2.1>-3.2 is index 3; crosswalk -2 moves 3 -> 7
	eq(phases(entryOf(add, -10)), { { 1, 3, 7 } })
	configs[7] = { laneConnections = {}, crosswalks = { 70, 71 }, trafficLightConfig = { states = {} } }
	add = nc.configs(list, { 70, 71 }, { [8] = true, [9] = true }, { [-10] = { node = 7, newIds = { [70] = -1, [71] = -2 } } })
	eq(#entryOf(add, -10).comp.trafficLightConfig.states, 0)
end)

-- A lit T at node 7 before the town entry removes its north leg 72: 70 (east), 71 (west), 72 (north).
-- Connections 0 70>71, 1 70>72, 2 71>70, 3 71>72, 4 72>70, 5 72>71; crosswalks 70 (6), 71 (7), 72 (8).
-- Phase 1 east-west green (72's approach and the east/west crosswalks red), phase 2 north green, phase 3 all red.
local function litT()
	local function lc(a, b) return { segment0 = a, lane0 = 1, segment1 = b, lane1 = 2, withRoad = true, withTram = false } end
	return { laneConnections = { lc(70, 71), lc(70, 72), lc(71, 70), lc(71, 72), lc(72, 70), lc(72, 71) }, crosswalks = { 70, 71, 72 },
		trafficLightConfig = lights({ { 4, 5, 6, 7 }, { 0, 1, 2, 3, 8 }, { 0, 1, 2, 3, 4, 5, 6, 7, 8 } }) }
end

-- node 7 after the entry: 70 <> 71 (0, 1), crosswalks 70 (2), 71 (3), the phases re-pointed (rt.nodeConfigEntry)
local function afterEntry()
	local function lc(a, b) return { segment0 = a, lane0 = 1, segment1 = b, lane1 = 2, withRoad = true, withTram = false } end
	return { laneConnections = { lc(70, 71), lc(71, 70) }, crosswalks = { 70, 71 },
		trafficLightConfig = lights({ { 2, 3 }, { 0, 1 }, { 0, 1, 2, 3 } }) }
end

-- the join: 7 replaced by -10, copies -1 (70) and -2 (71), the roundabout arm's piece -3 going north (wider: 8 lanes)
local function joinList()
	return { seg(-1, -10, 8, TWO4), seg(-2, 9, -10, TWO4), seg(-3, -10, -11, TWO8, { x = 0, y = 1, z = 0 }) }
end

--- Per phase: the locked connections as "s0>s1" (one per movement) and crosswalks as "cw:id", sorted.
local function lockedByMovement(e)
	local out = {}
	local nC = #e.comp.laneConnections
	for i, st in ipairs(e.comp.trafficLightConfig.states) do
		local set = {}
		for _, l in ipairs(st.lockedLanes) do
			if l < nC then
				local c = e.comp.laneConnections[l + 1]
				set[c.segment0 .. ">" .. c.segment1] = true
			else
				set["cw:" .. e.comp.crosswalks[l - nC + 1]] = true
			end
		end
		local list = {}
		for k in pairs(set) do list[#list + 1] = k end
		table.sort(list)
		out[i] = table.concat(list, " ")
	end
	return out
end

test("ghost: a lit node's config before a leg is removed; nil without phases, without a config or for a leg it does not use", function()
	configs[7] = litT()
	local g = nc.ghost(7, 72)
	eq(g.leg, 72)
	eq(#g.conns, 6)
	eq(g.conns[2], { 70, 1, 72, 2 })
	eq(g.cws, { 70, 71, 72 })
	eq(g.locked[2], { 0, 1, 2, 3, 8 })
	eq(nc.ghost(7, 99), nil, "a leg the node does not use")
	configs[7].trafficLightConfig = lights({})
	eq(nc.ghost(7, 72), nil, "no phases: unlit")
	configs[7].trafficLightConfig = nil
	eq(nc.ghost(7, 72), nil, "no light config")
	eq(nc.ghost(6, 72), nil, "no node config")
end)

test("configs: a seed's ghost gives the joined leg the removed leg's states per movement and re-adds its crosswalk", function()
	configs[7] = litT()
	local g = nc.ghost(7, 72)
	configs[7] = afterEntry()
	local list = joinList()
	local add = nc.configs(list, { 70, 71 }, {},
		{ [-10] = { node = 7, newIds = { [70] = -1, [71] = -2 }, ghost = g } })
	local e = entryOf(add, -10)
	eq(g.result, "carried")
	eq(e.comp.crosswalks, { -1, -2, -3 })
	-- old: east/west green in phase 1 (incl. their turns into the north leg), north green in phase 2, all red in 3
	eq(lockedByMovement(e), {
		"-3>-1 -3>-2 cw:-1 cw:-2",
		"-1>-2 -1>-3 -2>-1 -2>-3 cw:-3",
		"-1>-2 -1>-3 -2>-1 -2>-3 -3>-1 -3>-2 cw:-1 cw:-2 cw:-3",
	})
	eq(e.comp.trafficLightConfig.states[2].duration, 12, "durations kept")
	eq(nc.problems({ edgesToAdd = list, nodeConfigsToAdd = add, nodeConfigsToRemove = {} }), {})
	-- without the ghost (before the fix) the new leg had no history: green in every phase, no crosswalk
	configs[7] = afterEntry()
	add = nc.configs(list, { 70, 71 }, {}, { [-10] = { node = 7, newIds = { [70] = -1, [71] = -2 } } })
	eq(entryOf(add, -10).comp.crosswalks, { -1, -2 })
	ok(not lockedByMovement(entryOf(add, -10))[2]:find("-3>", 1, true), "the north approach green in its red phase")
end)

test("configs: a ghost that no longer fits the node (phases changed, a new connection) is not applied; the result says why", function()
	configs[7] = litT()
	local g = nc.ghost(7, 72)
	local list = joinList()
	local seeds = { [-10] = { node = 7, newIds = { [70] = -1, [71] = -2 }, ghost = g } }
	configs[7] = afterEntry()
	configs[7].trafficLightConfig = lights({ { 2, 3 }, { 0, 1 } })
	local add = nc.configs(list, { 70, 71 }, {}, seeds)
	eq(g.result, "unmapped (phases 2, were 3)")
	eq(entryOf(add, -10).comp.crosswalks, { -1, -2 })
	eq(nc.problems({ edgesToAdd = list, nodeConfigsToAdd = add, nodeConfigsToRemove = {} }), {})
	configs[7] = afterEntry()
	configs[7].laneConnections[2].lane1 = 1
	nc.configs(list, { 70, 71 }, {}, seeds)
	eq(g.result, "unmapped (connection -2:1>-1:1 is new)")
	-- an unlit node keeps no phases, whatever the seed
	configs[7] = afterEntry()
	configs[7].trafficLightConfig = nil
	add = nc.configs(list, { 70, 71 }, {}, seeds)
	eq(entryOf(add, -10).comp.trafficLightConfig, nil)
end)

test("relight: phases that cannot be re-pointed are reset to the game's default (states = {}), never left stale", function()
	api.type.TrafficLightState = { new = function() error("no ctor") end }
	local cfg = { trafficLightConfig = lights({ { 0, 5 } }) }
	local entry = { comp = cfg }
	eq(nc.relight(entry, cfg, { [1] = { 1, 1, 2, 2 } }, 1, { { 1, 1, 2, 2 } }, {}, 0), -1)
	eq(#entry.comp.trafficLightConfig.states, 0)
	eq(nc.relight({ comp = {} }, {}, {}, 0, {}, {}, 0), 0, "no light: nothing written")
end)

test("problems: a light phase locking an index past the connections and crosswalks", function()
	local sp = { edgesToAdd = {}, nodeConfigsToAdd = { { entity = 4, comp = {
		laneConnections = { { segment0 = 40, lane0 = 1, segment1 = 41, lane1 = 2 } }, crosswalks = { 40 },
		trafficLightConfig = lights({ { 0, 1 }, { 2 } }) } } } }
	local p = nc.problems(sp, function() return 4 end)
	eq(p, { "node 4: phase 2 locks index 2 past 2 connections + crosswalks" })
end)

test("complete: appends to the caller's lists and skips nodes it already configured", function()
	local cfgAdd = { { entity = 5, comp = { laneConnections = {} } } }
	local cfgRm = { 5 }
	nc.complete({ seg(-1, 5, -2, TWO4) }, {}, cfgAdd, cfgRm)
	eq(#cfgAdd, 2)
	eq(cfgAdd[2].entity, -2)
	eq(cfgRm, { 5 })
end)

test("problems: a new node without a config, a remove without an add, a lane past a segment's lanes", function()
	local sp = {
		nodesToAdd = { { entity = -3 } },
		edgesToAdd = { seg(-1, -2, -3, TWO4) },
		nodeConfigsToAdd = { { entity = -2, comp = { laneConnections = { { segment0 = -1, lane0 = 1, segment1 = -1, lane1 = 6 } } } } },
		nodeConfigsToRemove = { 9 },
	}
	local p = table.concat(nc.problems(sp), "\n")
	ok(p:find("node 9: config removed without a new one", 1, true), p)
	ok(p:find("node -3: no config", 1, true), p)
	ok(p:find("node -2: lane 6 of segment -1 out of range (4 lanes)", 1, true), p)
	-- existing segments' lane counts come from lanesOf
	sp = { edgesToAdd = {}, nodeConfigsToAdd = { { entity = 4, comp = { laneConnections = { { segment0 = 40, lane0 = 5, segment1 = 41, lane1 = 1 } } } } } }
	eq(#nc.problems(sp, function() return 8 end), 0)
	eq(#nc.problems(sp, function() return 4 end), 1)
end)

test("loading the module calls no engine API", function()
	reset_modules()
	set_global("api", {})
	ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
end)
