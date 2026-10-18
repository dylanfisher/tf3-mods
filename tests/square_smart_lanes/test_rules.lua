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

test("2-lane ring, medium arms: matched set at node 19132 (the default since 2026-10-15)", function()
	-- until 2026-10-15 turbo: "20359:1>20602:4:R-,20359:2>20602:3:R-,20359:2>19600:1:R-,20602:1>19600:2:R-,20602:2>19600:1:R-"
	-- (5; the outer lane exit only). Matched adds the outer lane straight on (20359:1>19600:2), 6.
	local W = F.PROBE_2LANE_MEDIUM.world()
	local p, ring = plan(W, 19132, F.PROBE_2LANE_MEDIUM.conns)
	eq({ p.turbo, p.turboReason, p.defaultWhy, p.layout }, { false, "two_lane_ring", "two_lane_exits", "matched" })
	local r = byNode(p)[19132]
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(
		"20359:1>20602:4:R-,20359:1>19600:2:R-,20359:2>20602:3:R-,20359:2>19600:1:R-,20602:1>19600:2:R-,20602:2>19600:1:R-")))
	assertReach(W, ring, result(p, nil, W, ring), "2-lane medium")
end)

test("2-lane ring, small arms: the default spiral (no mid nodes: sl_rspiral), entry into both lanes", function()
	-- before 2026-10-14 matched lanes ("18144:1>18141:2,18144:1>18164:2,18144:2>18141:1,18164:1>18141:2", 4)
	local W = F.PROBE_2LANE_SMALL.world()
	local p, ring = plan(W, 17955, F.PROBE_2LANE_SMALL.conns)
	eq(p.turbo, false)
	eq({ p.default, p.layout }, { true, "sl_rspiral" })
	local r = byNode(p)[17955]
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(
		"18144:1>18164:2:R-,18144:2>18141:1:R-,18144:2>18141:2:R-,18164:1>18141:1:R-,18164:1>18141:2:R-")))
	eq(r.before, 5)
	eq(r.after, 5)
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
				-- no merges of two ring lanes into one ring lane (at junctions: a mid node's inward move merges by design)
				for _, r in ipairs(p.nodes) do
					if r.mid then goto continue end
					local into = {}
					for _, cn in ipairs(r.conns) do
						if cn.segment0 == r.view.ringIn and cn.segment1 == r.view.ringOut then
							ok(not into[cn.lane1], "ring merge at " .. r.node)
							into[cn.lane1] = true
						end
					end
					::continue::
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
		-- a 2-lane ring with 2-lane exit legs: matched lanes (until 2026-10-15 turbo)
		eq({ p.turbo, p.defaultWhy }, { false, "two_lane_exits" })
		-- exit node: outer lane -> kerb leg lane or straight on, lane 2 -> other leg lane or straight on
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

test("bus lanes: an arm with a bus lane is handled (its car lanes), a bus-lane ring is no ring", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium_bus" }, { tpl = "medium" }, { tpl = "medium" } } })
	local p = plan(W, 1)
	local reasons = {}
	for _, r in ipairs(p.nodes) do if r.status == "skip" then reasons[#reasons + 1] = r.reason end end
	eq(reasons, {}, "no junction skipped (bus connections kept: test_bus.lua)")
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
			if cn.segment0 == v.ringIn and cn.lane0 == v.o_in[2] and cn.segment1 == v.ringOut and cn.lane1 == v.o_out[2] then roadOnTramPair = cn end
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

-- planRing on seeds alone (the automatic pass seeds whole rings, Rules.autoSeeds; seeds alone only beside a
-- hand-edited junction: test_wholering.lua)
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
	eq(l[1], { forward = false, road = false, car = false, tram = false, walk = true }, "sidewalk (PERSON)")
	eq(l[2], { forward = true, road = true, car = true, tram = false, walk = false })
	eq(l[3], { forward = true, road = true, car = false, tram = false, walk = false })
	eq(l[4], { forward = true, road = true, car = true, tram = true, walk = false })
end)

---------------------------------------------------------------------------
-- Params and log

test("mod params: 1-based indices and defaults", function()
	eq(Rules.fromModParams(nil), { auto = true, lights = true, freeTurn = "always", phases = "game", ring = "two_lane" })
	eq(Rules.fromModParams({ sqrl_auto = 2 }), { auto = false, lights = true, freeTurn = "always", phases = "game", ring = "two_lane" })
	eq(Rules.fromModParams({ sqrl_auto = 9, sqrl_ring_rule = 2 }), { auto = true, lights = true, freeTurn = "always", phases = "game", ring = "two_lane" }, "old setting ignored")
	eq(Rules.fromModParams({ sqrl_lights = 2 }), { auto = true, lights = false, freeTurn = "always", phases = "game", ring = "two_lane" })
	-- Free kerb turn: 1 Off, 2 When safe, 3 Always (default)
	eq(Rules.fromModParams({ sqrl_free_turn = 1 }), { auto = true, lights = true, freeTurn = "off", phases = "game", ring = "two_lane" })
	eq(Rules.fromModParams({ sqrl_free_turn = 2 }).freeTurn, "safe")
	eq(Rules.fromModParams({ sqrl_free_turn = 3 }).freeTurn, "always")
	eq(Rules.fromModParams({ sqrl_free_turn = 3.0 }).freeTurn, "always", "a double index")
	eq(Rules.fromModParams({ sqrl_free_turn = 1.5 }).freeTurn, "always", "not an index: default Always")
	eq(Rules.fromModParams({ sqrl_free_turn = 0 }).freeTurn, "always", "out of range: default Always")
	eq(Rules.fromModParams({ sqrl_free_turn = 4 }).freeTurn, "always", "out of range: default Always")
	-- Light phases: 1 Game default (default), 2 Smart Lanes
	eq(Rules.fromModParams({ sqrl_light_phases = 2 }).phases, "sl")
	eq(Rules.fromModParams({ sqrl_light_phases = 1.0 }).phases, "game")
	eq(Rules.fromModParams({ sqrl_light_phases = 3 }).phases, "game", "out of range: default Game default")
	local L = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
	eq(L.modeFor("off"), nil, "Off: no phase change")
	eq(L.modeFor("safe"), L.SAFE)
	eq(L.modeFor("always"), L.FREE)
	eq(L.modeFor(nil), nil)
end)

test("mod.json params match KEYS / VALUES and severities stay None", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	ok(s:find('"key": "sqrl_auto"', 1, true))
	ok(s:find('"key": "sqrl_lights"', 1, true))
	ok(s:find('"key": "sqrl_free_turn"', 1, true))
	ok(s:find('"values": %["On", "Off"%]'))
	-- Free kerb turn: three values in Rules.VALUES order, default Always (0-based defaultIndex 2)
	ok(s:find('"values": %["Off", "When safe", "Always"%],%s*"defaultIndex": 2'), "free turn values and default")
	eq(Rules.VALUES.freeTurn, { "off", "safe", "always" })
	eq(Rules.DEFAULTS.freeTurn, 3)
	ok(s:find('"key": "sqrl_light_phases"', 1, true))
	ok(s:find('"values": %["Game default", "Smart Lanes"%],%s*"defaultIndex": 0'), "light phases values and default")
	eq(Rules.VALUES.phases, { "game", "sl" })
	eq(Rules.DEFAULTS.phases, 1)
	ok(not s:find('sqrl_ring_rule', 1, true), "one setting only")
	ok(s:find('"severityAdd": "None"', 1, true))
	ok(s:find('"severityRemove": "None"', 1, true))
end)

test("log line format", function()
	eq(Rules.line("APPLY", { { "node", 5 }, { "x", "a b" } }), "[SQRL] APPLY node=5 x=a_b")
end)

test("countsText: most frequent first, ties by name, '-' when empty, '+N' past the cap", function()
	eq(Rules.countsText({}), "-")
	eq(Rules.countsText(nil), "-")
	eq(Rules.countsText({ ambiguous = 1, branch_turn = 2, bus_lane = 1 }), "branch_turn:2,ambiguous:1,bus_lane:1")
	-- cap 20: "aaaa:3,bbbb:2" (13) fits with room for "+N"; "cccc:1" would leave none
	eq(Rules.countsText({ aaaa = 3, bbbb = 2, cccc = 1, dddd = 1 }, 20), "aaaa:3,bbbb:2,+2")
	-- the last entry needs no room for a tail
	eq(Rules.countsText({ aaaa = 3, bbbb = 2 }, 13), "aaaa:3,bbbb:2")
	local many = {}
	for i = 1, 60 do many["reason_" .. i] = i end
	local s = Rules.countsText(many)
	ok(#s <= 190, #s)
	ok(s:find("^reason_60:60,reason_59:59"), s)
	ok(s:find(",%+%d+$"), s)
	eq(Rules.line("SUMMARY", { { "skips", s } }), "[SQRL] SUMMARY skips=" .. s, "under the 200 cap: not cut")
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
			-- the default spiral (2-lane ring, 1-lane exits) merges the entry into the shifted stream by design
			if not p.default then assertNoMerges(p, c.ring .. "/" .. c.arm) end
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

test("remapLocked: phases follow connections by identity, movement, incoming segment; crosswalks shift", function()
	local C = Rules.conn
	local old = { C(1, 1, 2, 3), C(1, 2, 3, 3), C(2, 1, 1, 3), C(2, 1, 3, 4) }
	-- locked: old 0 (1:1>2:3), old 2 (2:1>1:3), crosswalk 1 (index 5 = 4 + 1)
	local locked = { 0, 2, 5 }
	local new = { C(2, 1, 3, 4), C(1, 1, 2, 3), C(1, 2, 2, 4), C(1, 2, 3, 3), C(4, 1, 1, 3) }
	local got = Rules.remapLocked(old, new, 2, locked)
	-- new 0 = old 3 (unlocked); new 1 = old 0 (locked); new 2: movement 1>2 all locked -> locked;
	-- new 3 = old 1 (unlocked); new 4: unknown segment -> unlocked; crosswalk 1 -> 5 + 1 = 6
	eq(table.concat(got, ","), "1,2,6")
	-- movement mixed (one locked, one not): unlocked
	local mixed = Rules.remapLocked({ C(1, 1, 2, 3), C(1, 2, 2, 4) }, { C(1, 1, 2, 4) }, 0, { 0 })
	eq(#mixed, 0)
	-- nothing locked, no crosswalks
	eq(#Rules.remapLocked(old, new, 0, {}), 0)
end)

test("remapper: the same lockedLanes as the per-state string-keyed remap on random connection lists", function()
	-- the remap before PERF_REVIEW.md 2026-10-12 (three string-keyed maps per state), kept here as the reference
	local function key(c)
		return string.format("%s:%s>%s:%s", tostring(c.segment0), tostring(c.lane0), tostring(c.segment1), tostring(c.lane1))
	end
	local function reference(old, new, crosswalks, locked)
		local isLocked = {}
		for _, i in ipairs(locked or {}) do isLocked[i] = true end
		local byKey, byPair, bySeg = {}, {}, {}
		local function all(map, k, v)
			if map[k] == nil then map[k] = v else map[k] = map[k] and v end
		end
		for i, c in ipairs(old) do
			local l = isLocked[i - 1] == true
			byKey[key(c)] = l
			all(byPair, tostring(c.segment0) .. ">" .. tostring(c.segment1), l)
			all(bySeg, c.segment0, l)
		end
		local out = {}
		for j, c in ipairs(new) do
			local l = byKey[key(c)]
			if l == nil then l = byPair[tostring(c.segment0) .. ">" .. tostring(c.segment1)] end
			if l == nil then l = bySeg[c.segment0] end
			if l then out[#out + 1] = j - 1 end
		end
		for k = 0, (crosswalks or 0) - 1 do
			if isLocked[#old + k] then out[#out + 1] = #new + k end
		end
		return out
	end
	local seed = 12345
	local function rnd(n) -- deterministic LCG, 1..n
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local function randConn(segs)
		local c = Rules.conn(segs[rnd(#segs)], rnd(4) - 1, segs[rnd(#segs)], rnd(4) - 1, rnd(4) > 1, rnd(3) == 1)
		return c
	end
	for _ = 1, 3000 do
		local segs = {}
		for k = 1, rnd(5) do segs[k] = 1000 + k end
		local old = {}
		for k = 1, rnd(40) - 1 do
			old[k] = randConn(segs)
			-- duplicates and tram twins (the same lanes, other flags)
			if rnd(6) == 1 and k > 1 then
				local p = old[rnd(k - 1)]
				old[k] = Rules.conn(p.segment0, p.lane0, p.segment1, p.lane1, not p.withRoad, not p.withTram)
			end
		end
		-- new: some old ones kept (shuffled), some removed, some added (also on a segment the old list lacks)
		local new = {}
		for _, c in ipairs(old) do
			if rnd(3) > 1 then table.insert(new, rnd(#new + 1), Rules.conn(c.segment0, c.lane0, c.segment1, c.lane1, c.withRoad, c.withTram)) end
		end
		local segs2 = { segs[1], 2000 }
		for _ = 1, rnd(8) - 1 do table.insert(new, rnd(#new + 1), randConn(rnd(4) == 1 and segs2 or segs)) end
		local nCross = rnd(5) - 1
		local remap = Rules.remapper(old, new, nCross)
		-- several states through one remapper (as W.remapLights): no state leaks into the next
		for _ = 1, 4 do
			local locked = {}
			for _ = 1, rnd(#old + nCross + 3) - 1 do locked[#locked + 1] = rnd(#old + nCross + 4) - 2 end -- also -1 and past the end
			local want = reference(old, new, nCross, locked)
			local got = remap(locked)
			eq(table.concat(got, ","), table.concat(want, ","))
			eq(table.concat(Rules.remapLocked(old, new, nCross, locked), ","), table.concat(want, ","))
			for _, l in ipairs(got) do ok(l >= 0 and l < #new + nCross, "index in range: " .. l) end
		end
	end
end)

---------------------------------------------------------------------------
-- Ramp entry-only junctions (user's hand edit 2026-10-11, Roundabout Interchange ring 63759, node 63772):
-- the on-ramp takes the outer ring lane(s), the circulating lanes zip into the inner ones.

local SIDES = { { dir = "ccw" }, { dir = "cw" }, { dir = "ccw", mirror = true }, { dir = "cw", mirror = true } }

local function sideName(o) return o.dir .. (o.mirror and " mirror" or "") end

--- planRing over the interchange fixture; returns the plan, ring, world, the entry-only junction's result
-- and the next junction downstream's result.
local function interchange(opt, variant, seeds, current)
	local W = F.interchange(opt)
	local ring = assert(Ring.findRing(W, 1))
	local p = Rules.planRing(W, ring, seeds or all(W), variant or "two_lane", function(n) return (current or {})[n] or {} end)
	local js, ramp = {}, nil
	for _, r in ipairs(p.nodes) do
		js[#js + 1] = r
		if r.view.kind == "arm" and #r.view.x == 0 and #r.view.e > 0 then ramp = #js end
	end
	return p, ring, W, js[ramp], js[(ramp % #js) + 1]
end

--- Road conns of a node result as "from>to" pairs in view terms: ring lanes "i<k>" (o_in), "o<k>"
-- (o_out), entry "e<k>", exit "x<k>" (all outer / kerb first), sorted.
local function viewPairs(r)
	local v, names = r.view, {}
	local function name(seg, lane, list, prefix)
		for k, l in ipairs(list) do if l == lane then return prefix .. k end end
		return prefix .. "?" .. tostring(lane) .. "@" .. tostring(seg)
	end
	for _, c in ipairs(r.conns) do
		if c.withRoad then
			local a = c.segment0 == v.ringIn and name(c.segment0, c.lane0, v.o_in, "i") or name(c.segment0, c.lane0, v.e, "e")
			local b = c.segment1 == v.ringOut and name(c.segment1, c.lane1, v.o_out, "o") or name(c.segment1, c.lane1, v.x, "x")
			names[#names + 1] = a .. ">" .. b
		end
	end
	table.sort(names)
	return table.concat(names, ",")
end

--- Own-lane entry invariants: every incoming ring lane continues or exits, every entry lane is
-- connected, and no two connections cross: along the sources from the kerb side in (entry lanes kerb
-- first, then the ring lanes outer first) the ring-out targets never go back outwards.
local function assertRampInvariants(r, msg)
	local v = r.view
	local from = {}
	for _, c in ipairs(r.conns) do
		if c.withRoad then
			local k = c.segment0 .. ":" .. c.lane0
			from[k] = from[k] or {}
			from[k][#from[k] + 1] = c
		end
	end
	for _, l in ipairs(v.o_in) do ok(from[v.ringIn .. ":" .. l], msg .. " ring lane " .. l .. " continues or exits") end
	for _, l in ipairs(v.e) do ok(from[v.arm .. ":" .. l], msg .. " entry lane " .. l .. " connected") end
	-- order of sources (entries kerb first, then ring lanes outer first) vs. their ring-out targets
	local pos = {}
	for k, l in ipairs(v.o_out) do pos[l] = k end
	local seq = {}
	for _, l in ipairs(v.e) do seq[#seq + 1] = v.arm .. ":" .. l end
	for _, l in ipairs(v.o_in) do seq[#seq + 1] = v.ringIn .. ":" .. l end
	local last = 0
	for _, k in ipairs(seq) do
		local lo, hi = math.huge, 0
		for _, c in ipairs(from[k] or {}) do
			if c.segment1 == v.ringOut then lo, hi = math.min(lo, pos[c.lane1]), math.max(hi, pos[c.lane1]) end
		end
		if hi > 0 then
			ok(lo >= last, msg .. " connections cross at " .. k)
			last = hi
		end
	end
end

for _, o in ipairs(SIDES) do
	for _, variant in ipairs({ "two_lane", "turbo" }) do
		test("ramp entry-only junction takes its own ring lane, circulating lanes zip (" .. sideName(o) .. ", " .. variant .. ")", function()
			local p, ring, W, r, nx = interchange(o, variant)
			eq(p.turbo, false)
			eq(p.turboReason, "narrow_exit", "1-lane off-ramp on the ring, as in game")
			eq(r.entry, "own_lane", sideName(o))
			eq(r.entryWhy, nil)
			eq(r.status, "apply")
			-- the user's 63772: 63640:1 -> 63650:1, 63640:2 -> 63650:1, 63644:1 -> 63650:2
			eq(viewPairs(r), "e1>o1,i1>o2,i2>o2")
			eq(r.after, 3)
			assertRampInvariants(r, sideName(o))
			-- the user's 63771: outer -> outer + kerb exit lane, inner -> inner + the two other exit lanes,
			-- entry 1 -> outer, 2 and 3 -> inner
			eq(#nx.view.x, 3)
			eq(viewPairs(nx), "e1>o1,e2>o2,e3>o2,i1>o1,i1>x1,i2>o2,i2>x2,i2>x3")
			eq(nx.entry, nil, "a junction with exits gets no entry decision")
			assertReach(W, ring, result(p, nil, W, ring), sideName(o), true)
		end)
	end
end

test("ramp entry: the exact connection indices of the user's edit (ccw, right-hand traffic)", function()
	local _, _, _, r, nx = interchange({ dir = "ccw" }, "turbo")
	local v = r.view
	-- fixture lane indices equal the game's: ring lanes 1/2 (sidewalk 0), ramp lane 1 (shoulder 0)
	local exp = string.format("%d:1>%d:1:R-,%d:2>%d:1:R-,%d:1>%d:2:R-", v.ringIn, v.ringOut, v.ringIn, v.ringOut, v.arm, v.ringOut)
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(exp)))
	-- 63771 as logged in game (63650 in, 63649 out, 127589 the 3-lane arm)
	local a, i, u = nx.view.arm, nx.view.ringIn, nx.view.ringOut
	local exp2 = (("I:1>U:2:R-,I:2>U:1:R-,I:1>A:6:R-,I:2>A:5:R-,I:2>A:4:R-,A:1>U:2:R-,A:2>U:1:R-,A:3>U:1:R-")
		:gsub("I", tostring(i)):gsub("U", tostring(u)):gsub("A", tostring(a)))
	eq(Rules.connsText(nx.conns), Rules.connsText(F.parseConns(exp2)))
end)

test("ramp entry: badge input: the user's edit equals the Smart lanes plan, the engine model is unchanged", function()
	local _, ring, W, r = interchange({ dir = "ccw" }, "turbo")
	local cur = { [r.node] = r.conns }
	local again = Rules.planRing(W, ring, { [r.node] = true }, "turbo", function(n) return cur[n] or {} end)
	for _, x in ipairs(again.nodes) do
		if x.node == r.node then
			eq(x.status, "same", "the user's edit reads Smart lanes")
			eq(x.entry, "own_lane")
		end
	end
	-- Reset (engine model) and matched lanes: no entry decision, the old connections
	for _, variant in ipairs({ "engine", "matched" }) do
		local q = Rules.planRing(W, ring, all(W), variant, function() return {} end)
		for _, x in ipairs(q.nodes) do
			if x.node == r.node then
				eq(x.entry, nil, variant)
				ok(viewPairs(x) ~= "e1>o1,i1>o2,i2>o2", variant)
			end
		end
	end
end)

--- Plan of the same junction under the give-way rule (twoLaneConns), as view pairs.
local function giveWayPairs(r, p)
	return viewPairs({ view = r.view, conns = Rules.twoLaneConns(r.view, { turbo = p.turbo }) })
end

for _, o in ipairs(SIDES) do
	test("ramp entry kept as give-way: town arm, 1-lane ring, wide ramp, narrow next exit (" .. sideName(o) .. ")", function()
		local cases = {
			{ opt = { rampTpl = "one_way_town1" }, why = "not_ramp" },
			{ opt = { ringTpl = "highway_small" }, why = "one_lane_ring" },
			{ opt = { rampTpl = "highway_ramp2" }, why = "wide_entry" },
			{ opt = { nextTpl = "highway_small" }, why = "narrow_next_exit" },          -- 1-lane next exit
			{ opt = { nextTpl = "highway_small", nextFlip = true }, why = "narrow_next_exit" }, -- next is entry-only
		}
		for _, c in ipairs(cases) do
			for k, v in pairs(o) do c.opt[k] = v end
			for _, variant in ipairs({ "two_lane", "turbo" }) do
				local p, ring, W, r = interchange(c.opt, variant)
				local msg = c.why .. " " .. variant
				eq(r.entry, "give_way", msg)
				eq(r.entryWhy, c.why, msg)
				eq(viewPairs(r), giveWayPairs(r, p), msg .. ": today's rule")
				assertNoMerges(p, msg) -- today's invariants (an entry lane meets its ring lane: the give-way)
				assertReach(W, ring, result(p, nil, W, ring), msg, true)
			end
		end
	end)
end

test("ramp entry kept as give-way when reachability would break (an untouched junction downstream)", function()
	for _, o in ipairs(SIDES) do
		local _, _, _, r0, nx0 = interchange(o, "turbo")
		-- the next junction (not a seed) keeps a hand edit without ring continuation: nothing behind it is
		-- reachable from the ramp, so the ramp keeps today's give-way entry
		local cut = {}
		for _, c in ipairs(Rules.engineDefault(nx0.view)) do
			if c.segment1 ~= nx0.view.ringOut or c.segment0 == nx0.view.arm then cut[#cut + 1] = c end
		end
		local p, _, _, r = interchange(o, "turbo", { [r0.node] = true }, { [nx0.node] = cut })
		eq(r.entry, "give_way", sideName(o))
		eq(r.entryWhy, "reachability", sideName(o))
		eq(viewPairs(r), giveWayPairs(r, p), sideName(o))
	end
end)

test("ramp entry: a 1-lane ramp on a 4-lane ring folds the outer lanes into lane 2, the inner ones stay", function()
	for _, o in ipairs(SIDES) do
		local _, ring, _, r = interchange({ dir = o.dir, mirror = o.mirror, ringTpl = "one_way_medium" }, "turbo")
		eq(ring.lanes, 4)
		eq(r.entry, "own_lane", sideName(o))
		eq(viewPairs(r), "e1>o1,i1>o2,i2>o2,i3>o3,i4>o4")
		assertRampInvariants(r, sideName(o))
	end
	-- a 2-lane ramp on a 4-lane ring: e1 -> o1, e2 -> o2, the circulating lanes into o3 / o4
	local v = { o_in = { 11, 12, 13, 14 }, o_out = { 21, 22, 23, 24 }, e = { 31, 32 }, x = {}, ringIn = 1, ringOut = 2, arm = 3 }
	eq(viewPairs({ view = v, conns = Rules.rampEntryConns(v) }), "e1>o1,e2>o2,i1>o3,i2>o3,i3>o3,i4>o4")
end)

test("ramp entry: APPLY fields carry entry= and why=", function()
	eq(Rules.line("APPLY", Rules.withEntry({ { "node", 1 } }, { entry = "own_lane" })), "[SQRL] APPLY node=1 entry=own_lane")
	eq(Rules.line("APPLY", Rules.withEntry({ { "node", 1 } }, { entry = "give_way", entryWhy = "not_ramp" })),
		"[SQRL] APPLY node=1 entry=give_way why=not_ramp")
	eq(Rules.line("APPLY", Rules.withEntry({ { "node", 1 } }, {})), "[SQRL] APPLY node=1")
end)

--- A 2-lane ring with two 1-lane on-ramps, each followed by a 3-lane arm (review 2026-10-11): every exit has
-- 3 lanes, so until 2026-10-15 the ring also got the exit-only outer lane (turbo); since then a 2-lane ring with
-- wide exits gets matched lanes (Rules.matchedDefault), the ramps keep their own lane (rule 5).
local function twoRamps(o)
	return F.ring({ ringTpl = "one_way_small", dir = o.dir, mirror = o.mirror,
		arms = { { tpl = "large" }, { tpl = "highway_small", flip = true }, { tpl = "large" }, { tpl = "highway_small", flip = true } } })
end

for _, o in ipairs(SIDES) do
	test("ramp entry on a 2-lane ring with wide exits (matched default), two ramps: no dead lane, every entry connected (" .. sideName(o) .. ")", function()
		local W = twoRamps(o)
		for _, variant in ipairs({ "two_lane", "turbo" }) do
			local ring = assert(Ring.findRing(W, 1))
			local p = Rules.planRing(W, ring, all(W), variant, none)
			local msg = sideName(o) .. " " .. variant
			eq({ p.turbo, p.defaultWhy }, { false, "two_lane_exits" }, msg)
			local own = 0
			for _, r in ipairs(p.nodes) do
				if r.entry ~= nil then
					eq(r.entry, "own_lane", msg)
					eq(viewPairs(r), "e1>o1,i1>o2,i2>o2", msg)
					assertRampInvariants(r, msg)
					own = own + 1
				elseif r.view.kind == "arm" then
					-- the 3-lane arm right after a ramp: the outer lane (the ramp's traffic) exits or goes on (matched;
					-- turbo until 2026-10-15: "e1>o1,e2>o2,e3>o2,i1>x1,i2>o2,i2>x2,i2>x3")
					eq(viewPairs(r), "e1>o1,e2>o2,e3>o2,i1>o1,i1>x1,i2>o2,i2>x2,i2>x3", msg)
				end
			end
			eq(own, 2, msg)
			assertReach(W, ring, result(p, nil, W, ring), msg, true)
		end
	end)

	test("ramp entry: the plan does not depend on the ring's start node or on the other ramp's state (" .. sideName(o) .. ")", function()
		local W = twoRamps(o)
		local ring = assert(Ring.findRing(W, 1))
		local whole = byNode(Rules.planRing(W, ring, all(W), "turbo", none))
		-- candidates are tried in travel order: another start node gives another order, the same plan
		for _, start in ipairs(ring.nodes) do
			local ring2 = assert(Ring.findRing(W, start))
			for _, r in ipairs(Rules.planRing(W, ring2, all(W), "turbo", none).nodes) do
				eq(Rules.connsText(r.conns), Rules.connsText(whole[r.node].conns), sideName(o) .. " start " .. start)
			end
		end
		-- the tool's single-junction Apply (only that node a seed, the others as they are now: engine
		-- default, or the other ramp already own_lane) writes what the badge's whole-ring plan expects
		local default, planned = {}, {}
		for _, n in ipairs(ring.nodes) do
			default[n] = Rules.engineDefault(Ring.nodeView(W, ring, n))
			planned[n] = whole[n].conns or default[n]
		end
		for _, n in ipairs(ring.nodes) do
			if whole[n].entry ~= nil then
				for _, cur in ipairs({ default, planned }) do
					local single = byNode(Rules.planRing(W, ring, { [n] = true }, "turbo", function(m) return cur[m] end))
					eq(single[n].entry, "own_lane", sideName(o))
					eq(Rules.connsText(single[n].conns), Rules.connsText(whole[n].conns), sideName(o) .. " node " .. n)
				end
			end
		end
	end)

	test("ramp entry: the ramp's own traffic reaches every exit without lane changes (non-turbo ring) (" .. sideName(o) .. ")", function()
		local p, ring, W, r = interchange(o, "two_lane")
		eq(p.turbo, false)
		eq(r.entry, "own_lane")
		local reach = Rules.reachability(W, ring, result(p, nil, W, ring), false)
		for _, vout in ipairs(armSegs(W, ring, "out")) do
			ok(reach[r.view.arm] and reach[r.view.arm][vout.arm], sideName(o) .. " ramp -> exit " .. vout.arm)
		end
	end)
end

---------------------------------------------------------------------------
-- The ring decision table (PLAN.md "Default: matched lanes on 2-lane rings with wide exits", user decision
-- 2026-10-15 after bench s5): 2-lane ring with 2+-lane exits -> matched; 3- / 4-lane rings -> turbo; 2-lane ring with
-- one-lane exits -> sl_rmid (with mid nodes); mixed exits -> matched (narrow_exit, as always)

F.TPL.one_way3 = F.TPL.one_way3 or "BS FV FV FV FS"

for _, o in ipairs(SIDES) do
	test("ring decision table: 2-lane/wide exits matched, 3-/4-lane turbo, 2-lane/1-lane exits sl_rmid, mixed matched; 3-6 arms (" .. sideName(o) .. ")", function()
		local cases = {
			{ ring = "one_way_small", arm = "medium", turbo = false, why = "two_lane_exits", layout = "matched" },
			{ ring = "one_way_small", arm = "large", turbo = false, why = "two_lane_exits", layout = "matched" },
			{ ring = "one_way3", arm = "medium", turbo = true },
			{ ring = "one_way_medium", arm = "medium", turbo = true },
			{ ring = "one_way_medium", arm = "large", turbo = true },
			{ ring = "one_way_small", arm = "small", turbo = false, why = "one_lane_exits", layout = "sl_rmid", extra = 1 },
			{ ring = "one_way_small", arm = "medium", mixed = "small", turbo = false, reason = "narrow_exit" },
		}
		for _, c in ipairs(cases) do
			for A = 3, 6 do
				local arms = {}
				for k = 1, A do arms[k] = { tpl = (c.mixed and k == 2) and c.mixed or c.arm } end
				local W = F.ring({ ringTpl = c.ring, arms = arms, dir = o.dir, mirror = o.mirror,
					extraNodes = c.extra })
				local ring = assert(Ring.findRing(W, 1))
				for _, variant in ipairs({ "two_lane", "turbo" }) do
					local msg = sideName(o) .. " " .. c.ring .. "/" .. c.arm .. (c.mixed and "+mixed" or "") .. " A=" .. A .. " " .. variant
					local p = Rules.planRing(W, ring, all(W), variant, none)
					eq({ p.turbo, p.defaultWhy, p.layout }, { c.turbo, c.why, c.layout }, msg)
					if c.reason then eq(p.turboReason, c.reason, msg) end
					if c.layout == "sl_rmid" then eq(p.mids, A, msg) end
					for _, r in ipairs(p.nodes) do
						local v = r.view
						if not r.mid and v.kind == "arm" and #v.x > 0 then
							local cont = false
							for _, cn in ipairs(r.conns) do
								if cn.segment0 == v.ringIn and cn.lane0 == v.o_in[1] and cn.segment1 == v.ringOut then cont = true end
							end
							-- the outer lane goes on at an exit with matched lanes, exits only with turbo and sl_rmid
							eq(cont, not c.turbo and c.layout ~= "sl_rmid", msg .. " outer lane at " .. r.node)
							if c.layout == "matched" then
								eq(Rules.roadText(r.conns), Rules.roadText(Rules.twoLaneConns(v, { turbo = false })), msg)
							end
						end
					end
					-- 2-lane rings (matched, sl_rmid): every entry reaches every exit through node connections alone;
					-- wider rings and mixed exits with lane changes between the junctions, as the engine's own default
					assertReach(W, ring, result(p, nil, W, ring), msg, c.mixed ~= nil or c.ring ~= "one_way_small" or nil)
				end
			end
		end
	end)
end
