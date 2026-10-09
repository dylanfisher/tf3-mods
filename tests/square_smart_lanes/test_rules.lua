-- square_smart_lanes: ring detection, lane convention, rules and reachability (sl_ring.lua, sl_rules.lua).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local MOD_ROOT = here .. "../../mods/square_smart_lanes/"

local function all(world)
	local s = {}
	for id in pairs(world.nodes) do s[id] = true end
	return s
end

local function none() return {} end

--- Plans the ring through `start` with every node as a seed (a fresh build).
local function plan(world, start, current, seeds)
	local ring = assert(Ring.findRing(world, start))
	local p = Rules.planRing(world, ring, seeds or all(world), "two_lane", function(n) return (current or {})[n] or {} end)
	return p, ring
end

local function byNode(p)
	local m = {}
	for _, r in ipairs(p.nodes) do m[r.node] = r end
	return m
end

--- connsByNode for reachability: the planned conns where applied, else the current ones, else the
-- engine default (plain ring nodes between arms: straight on; skipped nodes).
local function result(p, current, world, ring)
	local m = {}
	if world then
		for _, n in ipairs(ring.nodes) do m[n] = Rules.engineDefault(Ring.nodeView(world, ring, n)) end
	end
	for _, r in ipairs(p.nodes) do
		local c = r.conns or (current or {})[r.node]
		if c then m[r.node] = c end
	end
	return m
end

local function armSegs(world, ring, want)
	local list = {}
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(world, ring, n)
		if v.kind == "arm" and ((want == "in" and #v.e > 0) or (want == "out" and #v.x > 0)) then list[#list + 1] = v end
	end
	return list
end

--- Every entry reaches every exit, and no ring lane fed from an entry is a dead end. Through node
-- connections alone, or with laneChange also by changing lanes between nodes. Arms are matched by
-- far node, so splitter legs count as one arm.
local function assertReach(world, ring, conns, msg, laneChange)
	local reach, dead = Rules.reachability(world, ring, conns, laneChange)
	for _, vin in ipairs(armSegs(world, ring, "in")) do
		for _, vout in ipairs(armSegs(world, ring, "out")) do
			ok(reach[vin.arm] and reach[vin.arm][vout.arm], (msg or "") .. " entry " .. vin.arm .. " -> exit " .. vout.arm)
		end
	end
	eq(next(dead), nil, (msg or "") .. " dead ring lanes")
end

---------------------------------------------------------------------------
-- Lane convention and engine default (probe log fixtures)

test("lane index convention: node0 end keeps the laneConfig index, node1 end reverses it", function()
	local W = F.PROBE_2LANE_SMALL.world()
	local inRing = Ring.lanesAt(W.seg(18144), 17955) -- ends at 17955
	eq(inRing.e, 1)
	eq(inRing.incoming, { 1, 2 })
	eq(inRing.outgoing, {})
	local arm = Ring.lanesAt(W.seg(18164), 17955) -- starts at 17955, two-way
	eq(arm.incoming, { 1 })
	eq(arm.outgoing, { 2 })
	eq(Ring.otherEndIndex(W.seg(18141), 2), 1)
end)

test("probe rings are found, counterclockwise, with the right lane count", function()
	for _, fx in ipairs({ { F.PROBE_2LANE_SMALL, 17955, 2 }, { F.PROBE_2LANE_MEDIUM, 19132, 2 }, { F.PROBE_4LANE_MEDIUM, 22768, 4 } }) do
		local W = fx[1].world()
		local ring = assert(Ring.findRing(W, fx[2]))
		eq(ring.side, 1)
		eq(ring.lanes, fx[3])
		eq(#ring.segs, 4)
		eq(ring.nodes[1], fx[2])
	end
end)

test("CCW ring: incoming lane 1 is outer, outgoing lane 1 is inner (findings.md)", function()
	local W = F.PROBE_4LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 22768)
	local v = Ring.nodeView(W, ring, 22768)
	eq(v.kind, "arm")
	eq(v.o_in, { 1, 2, 3, 4 })
	eq(v.o_out, { 4, 3, 2, 1 })
	eq(v.x, { 4, 3 }) -- kerb exit lane first
	eq(v.e, { 1, 2 }) -- kerb entry lane first
end)

test("engine default model reproduces the probe log (2-lane small, 2-lane medium, 4-lane medium)", function()
	for _, fx in ipairs({ F.PROBE_2LANE_SMALL, F.PROBE_2LANE_MEDIUM, F.PROBE_4LANE_MEDIUM }) do
		local W = fx.world()
		for node, conns in pairs(fx.conns) do
			local ring = Ring.findRing(W, node)
			local v = Ring.nodeView(W, ring, node)
			eq(Rules.connsText(Rules.engineDefault(v)), Rules.connsText(conns), "node " .. node)
		end
	end
end)

---------------------------------------------------------------------------
-- The two-lane-exit rule on the probe rings (exact sets)

test("4-lane ring, medium arms: outer lane exits only, lane 2 exits or continues, entries 1:1", function()
	local W = F.PROBE_4LANE_MEDIUM.world()
	local p, ring = plan(W, 22768, F.PROBE_4LANE_MEDIUM.conns)
	ok(p.fresh)
	ok(p.turbo)
	local r = byNode(p)[22768]
	eq(r.status, "apply")
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(
		"23302:1>23303:4:R-,23302:2>23303:3:R-,23302:2>23299:3:R-,23302:3>23299:2:R-,23302:4>23299:1:R-," ..
		"23303:1>23299:4:R-,23303:2>23299:3:R-")))
	eq(r.before, 10)
	eq(r.after, 7)
	assertReach(W, ring, result(p, nil, W, ring), "4-lane")
end)

test("2-lane ring, medium arms: turbo set at node 19132", function()
	local W = F.PROBE_2LANE_MEDIUM.world()
	local p, ring = plan(W, 19132, F.PROBE_2LANE_MEDIUM.conns)
	ok(p.turbo)
	local r = byNode(p)[19132]
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(
		"20359:1>20602:4:R-,20359:2>20602:3:R-,20359:2>19600:1:R-,20602:1>19600:2:R-,20602:2>19600:1:R-")))
	assertReach(W, ring, result(p, nil, W, ring), "2-lane medium")
end)

test("2-lane ring, small arms: fallback, outer lane exits or continues, entry 1:1", function()
	local W = F.PROBE_2LANE_SMALL.world()
	local p, ring = plan(W, 17955, F.PROBE_2LANE_SMALL.conns)
	eq(p.turbo, false)
	local r = byNode(p)[17955]
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(
		"18144:1>18141:2:R-,18144:1>18164:2:R-,18144:2>18141:1:R-,18164:1>18141:2:R-")))
	eq(r.before, 5)
	eq(r.after, 4)
	assertReach(W, ring, result(p, nil, W, ring), "2-lane small")
end)

test("engine default on a 4-lane ring leaves dead lanes without lane changes (why the rule matters)", function()
	local W = F.PROBE_4LANE_MEDIUM.world()
	local ring = Ring.findRing(W, 22768)
	local m = {}
	for _, n in ipairs(ring.nodes) do m[n] = Rules.engineDefault(Ring.nodeView(W, ring, n)) end
	local _, dead = Rules.reachability(W, ring, m)
	ok(next(dead) ~= nil, "inner lanes fed by entries never exit through node connections")
end)

---------------------------------------------------------------------------
-- Generated rings: lanes x arms x direction

local CASES = {
	{ ring = "highway_small", arm = "small" },
	{ ring = "one_way_small", arm = "small" },
	{ ring = "one_way_small", arm = "medium" },
	{ ring = "one_way_small", arm = "large" },
	{ ring = "one_way_medium", arm = "small" },
	{ ring = "one_way_medium", arm = "medium" },
	{ ring = "one_way_medium", arm = "large" },
}

for _, c in ipairs(CASES) do
	for _, dir in ipairs({ "ccw", "cw" }) do
		for _, nArms in ipairs({ 3, 4 }) do
			test(string.format("ring %s, %d %s arms, %s: detected, every entry reaches every exit", c.ring, nArms, c.arm, dir), function()
				local arms = {}
				for k = 1, nArms do arms[k] = { tpl = c.arm, flip = (k % 2 == 0) } end
				local W = F.ring({ ringTpl = c.ring, arms = arms, dir = dir, extraNodes = (nArms == 3) and 1 or 0 })
				local p, ring = plan(W, 1)
				eq(ring.side, dir == "ccw" and 1 or -1)
				eq(#armSegs(W, ring, "in"), nArms)
				for _, r in ipairs(p.nodes) do ok(r.status == "apply" or r.status == "same", "status " .. r.status) end
				assertReach(W, ring, result(p, nil, W, ring), c.ring .. "/" .. c.arm)
				-- no merges of two ring lanes into one ring lane
				for _, r in ipairs(p.nodes) do
					local into = {}
					for _, cn in ipairs(r.conns) do
						if cn.segment0 == r.view.ringIn and cn.segment1 == r.view.ringOut then
							ok(not into[cn.lane1], "ring merge at " .. r.node)
							into[cn.lane1] = true
						end
					end
				end
			end)
		end
	end
end

test("1-lane ring with small arms: the rule equals the engine default (nothing written)", function()
	local W = F.ring({ ringTpl = "highway_small", arms = { { tpl = "small" }, { tpl = "small" }, { tpl = "small" } } })
	local ring = Ring.findRing(W, 1)
	local cur = {}
	for _, n in ipairs(ring.nodes) do cur[n] = Rules.engineDefault(Ring.nodeView(W, ring, n)) end
	local p = plan(W, 1, cur)
	for _, r in ipairs(p.nodes) do eq(r.status, "same") end
end)

test("ring segments drawn against travel (forward=false lanes) give the same physical result", function()
	local A = F.ring({ ringTpl = "one_way_medium", arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local B = F.ring({ ringTpl = "one_way_medium", flipRing = true,
		arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local pa = plan(A, 1)
	local pb, rb = plan(B, 1)
	eq(rb.side, 1)
	-- compare per node: map B's ring lanes (drawn reversed) back to A's indices
	local ma, mb = byNode(pa), byNode(pb)
	for n, ra in pairs(ma) do
		local rbn = mb[n]
		eq(#rbn.conns, #ra.conns, "node " .. n)
		local function phys(world, cn)
			-- physical lane = (segment, laneConfig index counted from the travel-left side)
			local function p(seg, idx)
				local s = world.seg(seg)
				local e = Ring.endAt(s, n)
				local k = (e == 0) and idx or (#s.lanes - 1 - idx)
				if s.node0 ~= n and s.node1 ~= n then error("bad seg") end
				if Ring.oneWay(s) == "bwd" then k = #s.lanes - 1 - k end
				return seg .. "#" .. k
			end
			return p(cn.segment0, cn.lane0) .. ">" .. p(cn.segment1, cn.lane1)
		end
		local sa, sb = {}, {}
		for _, cn in ipairs(ra.conns) do sa[#sa + 1] = phys(A, cn) end
		for _, cn in ipairs(rbn.conns) do sb[#sb + 1] = phys(B, cn) end
		table.sort(sa)
		table.sort(sb)
		eq(sb, sa, "node " .. n)
	end
end)

test("left-hand traffic (mirror image): clockwise ring, connections are the mirror of the right-hand ones", function()
	local arms = { { tpl = "medium" }, { tpl = "small" }, { tpl = "large" }, { tpl = "medium" } }
	local A = F.ring({ ringTpl = "one_way_medium", arms = arms })
	local B = F.ring({ ringTpl = "one_way_medium", arms = arms, mirror = true })
	local pa, ra = plan(A, 1)
	local pb, rb = plan(B, 1)
	eq(ra.side, 1)
	eq(rb.side, -1)
	local mb = byNode(pb)
	for _, r in ipairs(pa.nodes) do
		local mirrored = {}
		for _, cn in ipairs(r.conns) do
			local s0, s1 = A.seg(cn.segment0), A.seg(cn.segment1)
			mirrored[#mirrored + 1] = Rules.conn(cn.segment0, #s0.lanes - 1 - cn.lane0, cn.segment1, #s1.lanes - 1 - cn.lane1)
		end
		eq(Rules.connsText(mb[r.node].conns), Rules.connsText(mirrored), "node " .. r.node)
	end
	assertReach(B, rb, result(pb, nil, B, rb), "mirror")
end)

test("T ring (3 arms): mixed small and medium arms, no turbo, still every entry reaches every exit", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium" }, { tpl = "small" }, { tpl = "medium" } } })
	local p, ring = plan(W, 1)
	eq(p.turbo, false, "a 1-lane exit arm disables exit-only outer lanes")
	assertReach(W, ring, result(p, nil, W, ring), "T mixed")
end)

test("splitter islands: separate exit and entry nodes on the ring", function()
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "medium", splitter = true } end
	for _, dir in ipairs({ "ccw", "cw" }) do
		local W = F.ring({ ringTpl = "one_way_small", arms = arms, dir = dir })
		local p, ring = plan(W, 1)
		eq(#ring.segs, 8, "the ring, not a loop through a splitter leg")
		eq(#p.nodes, 8)
		local exits, entries = 0, 0
		for _, r in ipairs(p.nodes) do
			eq(r.view.kind, "arm")
			if #r.view.x > 0 then exits = exits + 1 end
			if #r.view.e > 0 then entries = entries + 1 end
		end
		eq(exits, 4)
		eq(entries, 4)
		ok(p.turbo)
		-- exit node: outer lane -> kerb leg lane, lane 2 -> other leg lane or straight on
		local X = p.nodes[1].view.x[1] and p.nodes[1] or p.nodes[2]
		local cnt = 0
		for _, cn in ipairs(X.conns) do if cn.segment1 == X.view.arm then cnt = cnt + 1 end end
		eq(cnt, 2)
		-- reachability: entry legs reach every exit leg
		local reach, dead = Rules.reachability(W, ring, result(p, nil, W, ring))
		for _, vin in ipairs(armSegs(W, ring, "in")) do
			for _, vout in ipairs(armSegs(W, ring, "out")) do ok(reach[vin.arm][vout.arm], dir .. " leg") end
		end
		eq(next(dead), nil)
	end
end)

test("4-segment node (road through the centre) is skipped and disables turbo", function()
	local W = F.ring({ ringTpl = "one_way_small",
		arms = { { tpl = "medium", through = true }, { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local p, ring = plan(W, 2)
	local skipped = 0
	for _, r in ipairs(p.nodes) do
		if r.status == "skip" then
			skipped = skipped + 1
			eq(r.reason, "multi_arm")
		end
	end
	eq(skipped, 1)
	eq(p.turbo, false)
	-- the skipped node keeps the engine default (modelled for its regular arm): every arm entry
	-- still reaches every arm exit (the through road is ignored here)
	local m = result(p, nil, W, ring)
	local armOf = {}
	for _, r in ipairs(p.nodes) do
		if r.status == "skip" then
			local v = r.view
			v.arm = 2000 + r.node
			local la = Ring.lanesAt(W.seg(v.arm), r.node)
			v.x = Ring.outerFirst(la.outgoing, false, ring.side)
			v.e = Ring.outerFirst(la.incoming, true, ring.side)
			m[r.node] = Rules.engineDefault(v)
		elseif r.view.arm then
			armOf[#armOf + 1] = r.view.arm
		end
	end
	local reach = Rules.reachability(W, ring, m)
	for _, a in ipairs(armOf) do
		for _, b in ipairs(armOf) do ok(reach[a] and reach[a][b], a .. " -> " .. b) end
	end
end)

test("bus lanes: an arm with a bus lane is skipped, a bus-lane ring is no ring", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium_bus" }, { tpl = "medium" }, { tpl = "medium" } } })
	local p = plan(W, 1)
	local reasons = {}
	for _, r in ipairs(p.nodes) do if r.status == "skip" then reasons[#reasons + 1] = r.reason end end
	eq(reasons, { "bus_lane_arm" })
	local B = F.ring({ ringTpl = "one_way_small_bus", arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local ring, why = Ring.findRing(B, 1)
	eq(ring, nil)
	eq(why, "bus_lane_ring")
end)

test("tram ring: road connections follow the rule, the engine's tram connections stay untouched", function()
	local W = F.ring({ ringTpl = "one_way_small_tram",
		arms = { { tpl = "small_tram" }, { tpl = "small_tram" }, { tpl = "small_tram" }, { tpl = "small_tram" } } })
	local ring = Ring.findRing(W, 1)
	local cur = {}
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(W, ring, n)
		local list = Rules.engineDefault(v)
		-- engine tram conns: inner (tram) ring lane straight on, plus a tram-only turn into the arm
		local tramIn = v.o_in[2]
		for _, c in ipairs(list) do
			if c.segment0 == v.ringIn and c.lane0 == tramIn and c.segment1 == v.ringOut then c.withTram = true end
		end
		list[#list + 1] = Rules.conn(v.ringIn, tramIn, v.arm, v.x[1], false, true)
		cur[n] = list
	end
	local p = plan(W, 1, cur)
	for _, r in ipairs(p.nodes) do
		local v = r.view
		local tram, roadOnTramPair = 0, nil
		for _, cn in ipairs(r.conns) do
			if cn.withTram then tram = tram + 1 end
			if cn.segment0 == v.ringIn and cn.lane0 == v.o_in[2] and cn.segment1 == v.ringOut then roadOnTramPair = cn end
		end
		eq(tram, 2, "both tram connections kept at " .. r.node)
		ok(roadOnTramPair and roadOnTramPair.withRoad and roadOnTramPair.withTram, "shared pair keeps both flags")
		local tramTurn = false
		for _, cn in ipairs(r.conns) do
			if cn.segment1 == v.arm and cn.lane0 == v.o_in[2] and cn.withTram and not cn.withRoad then tramTurn = true end
		end
		ok(tramTurn, "tram-only turn kept")
	end
end)

test("tram-only track at a ring node is not an arm", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "tram_only" }, { tpl = "medium" }, { tpl = "medium" } } })
	local ring = Ring.findRing(W, 1)
	local kinds = {}
	for _, n in ipairs(ring.nodes) do kinds[#kinds + 1] = Ring.nodeView(W, ring, n).kind end
	ok(kinds[1] == "plain" or kinds[2] == "plain" or kinds[3] == "plain")
end)

test("only seed nodes are written; a partly rebuilt ring gets the safe rule (no exit-only lane)", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local p = plan(W, 1, nil, { [1] = true, [101] = true })
	eq(p.fresh, false)
	eq(p.turbo, false)
	for _, r in ipairs(p.nodes) do
		if r.node == 1 then eq(r.status, "apply") else eq(r.status, "untouched") end
	end
	-- outer lane continues at node 1
	local r = byNode(p)[1]
	local cont = false
	for _, cn in ipairs(r.conns) do
		if cn.segment0 == r.view.ringIn and cn.lane0 == r.view.o_in[1] and cn.segment1 == r.view.ringOut then cont = true end
	end
	ok(cont)
end)

test("variant Game default never applies", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local ring = Ring.findRing(W, 1)
	local p = Rules.planRing(W, ring, all(W), "game", none)
	for _, r in ipairs(p.nodes) do eq(r.status, "skip") end
end)

---------------------------------------------------------------------------
-- Ring detection limits

test("two-way streets and a straight one-way street are not rings", function()
	local nodes = { [1] = { x = 0, y = 0 }, [2] = { x = 50, y = 0 }, [3] = { x = 100, y = 0 } }
	local segs = { [10] = { node0 = 1, node1 = 2, lanes = F.lanes(F.TPL.small) },
		[11] = { node0 = 2, node1 = 3, lanes = F.lanes(F.TPL.one_way_small) } }
	local W = F.world(nodes, segs)
	eq(Ring.findRing(W, 2), nil)
end)

test("a square block of one-way streets (90 degree corners) is not a roundabout", function()
	local nodes = { [1] = { x = 0, y = 0 }, [2] = { x = 80, y = 0 }, [3] = { x = 80, y = 80 }, [4] = { x = 0, y = 80 } }
	local segs = {}
	for i = 1, 4 do segs[10 + i] = { node0 = i, node1 = (i % 4) + 1, lanes = F.lanes(F.TPL.one_way_small) } end
	local W = F.world(nodes, segs)
	local ring, why = Ring.findRing(W, 1)
	eq(ring, nil)
	eq(why, "kink")
end)

test("a huge one-way loop is not a roundabout", function()
	local W = F.ring({ ringTpl = "one_way_small", radius = 400, arms = { { tpl = "small" }, { tpl = "small" }, { tpl = "small" } } })
	eq(Ring.findRing(W, 1), nil)
end)

test("two-way magic-roundabout link ring is not a one-way ring", function()
	local W = F.ring({ ringTpl = "small", arms = { { tpl = "small" }, { tpl = "small" }, { tpl = "small" } } })
	local ring, why = Ring.findRing(W, 1)
	eq(ring, nil)
	eq(why, "no_cycle")
end)

test("lanesFromConfigs reads transport modes keyed by enum value", function()
	local M = Ring.MODES
	local l = Ring.lanesFromConfigs({
		{ forward = false, transportModes = { [0] = true, [1] = true } },
		{ forward = true, transportModes = { [M.CAR] = true, [M.BUS] = true, [M.TRUCK] = true } },
		{ forward = true, transportModes = { [M.BUS] = true, [M.TRUCK] = true } },
		{ forward = true, transportModes = { [M.CAR] = true, [M.TRAM] = false, [M.ELECTRIC_TRAM] = true } },
	})
	eq(l[1], { forward = false, road = false, car = false, tram = false })
	eq(l[2], { forward = true, road = true, car = true, tram = false })
	eq(l[3], { forward = true, road = true, car = false, tram = false })
	eq(l[4], { forward = true, road = true, car = true, tram = true })
end)

---------------------------------------------------------------------------
-- Params and log

test("mod params: 1-based indices and defaults", function()
	eq(Rules.fromModParams(nil), { auto = true, ring = "two_lane" })
	eq(Rules.fromModParams({ sqrl_auto = 2 }), { auto = false, ring = "two_lane" })
	eq(Rules.fromModParams({ sqrl_auto = 9, sqrl_ring_rule = 2 }), { auto = true, ring = "two_lane" }, "old setting ignored")
end)

test("mod.json params match KEYS / VALUES and severities stay None", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	ok(s:find('"key": "sqrl_auto"', 1, true))
	ok(s:find('"values": %["On", "Off"%]'))
	ok(not s:find('sqrl_ring_rule', 1, true), "one setting only")
	ok(s:find('"severityAdd": "None"', 1, true))
	ok(s:find('"severityRemove": "None"', 1, true))
end)

test("log line format", function()
	eq(Rules.line("APPLY", { { "node", 5 }, { "x", "a b" } }), "[SQRL] APPLY node=5 x=a_b")
end)

---------------------------------------------------------------------------
-- Merges (2026-10-08 in-game report: 4 entry lanes all fed one ring lane on a ring without exits)

--- Per node: entry lanes go to distinct ring lanes (merging only the extra lanes when the arm is
-- wider than the ring), ring lanes go to distinct exit lanes, no two ring lanes merge.
local function assertNoMerges(p, msg)
	for _, r in ipairs(p.nodes) do
		if r.conns then
			local v = r.view
			local Rn, N, E = #v.o_in, #v.e, #v.x
			local entryInto, exitFrom, ringInto = {}, {}, {}
			for _, cn in ipairs(r.conns) do
				if cn.segment0 == v.arm and cn.segment1 == v.ringOut then
					entryInto[cn.lane1] = (entryInto[cn.lane1] or 0) + 1
				elseif cn.segment0 == v.ringIn and cn.segment1 == v.arm then
					exitFrom[cn.lane1] = (exitFrom[cn.lane1] or 0) + 1
				elseif cn.segment0 == v.ringIn and cn.segment1 == v.ringOut then
					ok(not ringInto[cn.lane1], msg .. " ring lanes merge at " .. r.node)
					ringInto[cn.lane1] = true
				end
			end
			local fed, worst = 0, 0
			for _, k in pairs(entryInto) do fed = fed + 1; worst = math.max(worst, k) end
			eq(fed, math.min(N, Rn), msg .. " ring lanes fed at " .. r.node)
			eq(worst, math.max(1, N - Rn + 1) * (N > 0 and 1 or 0), msg .. " entry lanes per ring lane at " .. r.node)
			for _, k in pairs(exitFrom) do eq(k, 1, msg .. " exit lane fed twice at " .. r.node) end
			local nx = 0
			for _ in pairs(exitFrom) do nx = nx + 1 end
			eq(nx, E, msg .. " every exit lane used at " .. r.node)
		end
	end
end

for _, c in ipairs(CASES) do
	for _, dir in ipairs({ "ccw", "cw" }) do
		test(string.format("no merges: ring %s, %s arms, %s", c.ring, c.arm, dir), function()
			local arms = {}
			for k = 1, 4 do arms[k] = { tpl = c.arm, flip = (k % 2 == 0) } end
			local W = F.ring({ ringTpl = c.ring, arms = arms, dir = dir })
			local p, ring = plan(W, 1)
			assertNoMerges(p, c.ring .. "/" .. c.arm)
			assertReach(W, ring, result(p, nil, W, ring), c.ring .. "/" .. c.arm, true)
		end)
	end
end

test("ring without exits (hand-built, one-way stem in): 4 entry lanes -> 4 ring lanes, 2 -> 2", function()
	for _, c in ipairs({ { ring = "one_way_medium", arm = "one_way_medium", n = 4 }, { ring = "one_way_small", arm = "one_way_small", n = 2 } }) do
		for _, dir in ipairs({ "ccw", "cw" }) do
			local W = F.ring({ ringTpl = c.ring, arms = { { tpl = c.arm, flip = true } }, dir = dir, extraNodes = 2 })
			local p = plan(W, 1)
			local applied = 0
			for _, r in ipairs(p.nodes) do
				if r.conns and #r.view.e > 0 then
					applied = applied + 1
					eq(#r.view.e, c.n)
					eq(#r.view.x, 0)
				end
			end
			eq(applied, 1, c.ring .. " " .. dir)
			assertNoMerges(p, c.ring .. " " .. dir)
		end
	end
end)

test("3-lane arms on a 4-lane ring: three ring lanes exit, three entry lanes feed three ring lanes", function()
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "large" } end
	local W = F.ring({ ringTpl = "one_way_medium", arms = arms })
	local p, ring = plan(W, 1)
	ok(p.turbo)
	for _, r in ipairs(p.nodes) do
		local v = r.view
		eq(#v.x, 3)
		eq(#v.e, 3)
		local exiting, straight = {}, {}
		for _, cn in ipairs(r.conns) do
			if cn.segment0 == v.ringIn and cn.segment1 == v.arm then exiting[cn.lane0] = true end
			if cn.segment0 == v.ringIn and cn.segment1 == v.ringOut then straight[cn.lane0] = true end
		end
		ok(exiting[v.o_in[1]] and exiting[v.o_in[2]] and exiting[v.o_in[3]] and not exiting[v.o_in[4]])
		ok(not straight[v.o_in[1]], "outer lane exit only")
		ok(straight[v.o_in[2]] and straight[v.o_in[3]] and straight[v.o_in[4]])
	end
	assertNoMerges(p, "large on 4-lane")
	assertReach(W, ring, result(p, nil, W, ring), "large on 4-lane")
end)

test("a 3-lane arm on a 2-lane ring merges only its extra entry lane", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "large" }, { tpl = "small" }, { tpl = "large" } } })
	local p = plan(W, 1)
	assertNoMerges(p, "large on 2-lane")
end)

test("ring search on a large one-way network without rings stays cheap", function()
	-- worst case for the search: a 40 x 40 one-way grid (every street east- or northbound, 30 m
	-- apart), so nothing ever loops back and the search runs until its length / node limits
	local N, D = 40, 30
	local nodes, segs = {}, {}
	local function id(i, j) return i * 100 + j + 1 end
	for i = 0, N - 1 do
		for j = 0, N - 1 do nodes[id(i, j)] = { x = i * D, y = j * D } end
	end
	local sid = 100000
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if i < N - 1 then
				sid = sid + 1
				segs[sid] = { node0 = id(i, j), node1 = id(i + 1, j), lanes = F.lanes(F.TPL.one_way_small) }
			end
			if j < N - 1 then
				sid = sid + 1
				segs[sid] = { node0 = id(i, j), node1 = id(i, j + 1), lanes = F.lanes(F.TPL.one_way_small) }
			end
		end
	end
	local W = F.world(nodes, segs)
	-- a job's worth of seeds (sl_lanes MAX_SEEDS) in the middle of the grid
	local seeds = {}
	for i = 10, 29 do
		for j = 10, 17 do seeds[#seeds + 1] = id(i, j) end
	end
	local t0 = os.clock()
	for _, n in ipairs(seeds) do
		local ring, why = Ring.ringThrough(W, n)
		eq(ring, nil)
		eq(why, "no_cycle")
	end
	print(string.format("ring search: %d seeds on a %dx%d one-way grid: %.1f ms", #seeds, N, N, (os.clock() - t0) * 1000))
end)
