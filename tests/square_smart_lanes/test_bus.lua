-- square_smart_lanes: bus lanes (user request 2026-10-13: "make the tool ignore bus lanes but set all the
-- other lanes correctly; I'll add the bus lane connections / bus priority light phases myself").
-- Bus-only lanes (a road lane without CAR) are in no lane list of the rules (sl_ring R.lanesAt): slip
-- nodes, crossroads / T-junctions (case X), lane drops (case D) and ring arms plan their car lanes, and
-- every connection touching a bus-only lane is kept exactly as it is (Rules.mergeTram with the view's
-- bus set); the status checks, the free kerb turn and the audit leave those connections out.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Lights = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local Phases = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

before_each(function() Slip.resetSide() end)

local C = Rules.conn
-- 2 car lanes and a kerb bus lane per direction (town_new_large with its kerb lanes as bus lanes)
local LARGE_BUS = "BS BU BV BV FV FV FU FS"
-- car lanes eastbound (forward) only, the other direction a bus lane: one-way for cars
local CONTRAFLOW_BUS = "BS BU FV FV FS"

--- Every connection of `list` touching a bus-only lane at the view's node.
local function busConns(list, bus)
	local out = {}
	for _, c in ipairs(list) do
		if Rules.touchesBus(c, bus) then out[#out + 1] = c end
	end
	return out
end

--- The connections a rule made (not touching a bus lane) must name car lanes only, both ends.
local function noBusInRule(rule, bus, msg)
	for _, c in ipairs(rule) do
		ok(not Rules.touchesBus(c, bus), (msg or "") .. " rule connection touches a bus lane: " .. Rules.connsText({ c }))
	end
end

--- `kept`'s connections are in `conns` exactly (both flags).
local function keptExactly(conns, kept, msg)
	local have = {}
	for _, c in ipairs(conns) do have[Rules.connsText({ c })] = true end
	for _, c in ipairs(kept) do ok(have[Rules.connsText({ c })], (msg or "") .. " kept " .. Rules.connsText({ c })) end
end

---------------------------------------------------------------------------

test("lanesAt: bus-only lanes are in no lane list, their indices in bus; busLanes per node", function()
	local w = F.build({ [1] = { 0, 0 }, [2] = { 60, 0 } }, { [11] = { 1, 2, F.TPL.medium_bus } })
	-- BS BU BV FV FU FS from node 1 (node0): 0 S, 1 bus in, 2 car in, 3 car out, 4 bus out
	local a = Ring.lanesAt(w.seg(11), 1)
	eq(a.incoming, { 2 })
	eq(a.outgoing, { 3 })
	eq(a.bus, { 1, 4 })
	local b = Ring.lanesAt(w.seg(11), 2)
	eq(b.incoming, { 2 })
	eq(b.outgoing, { 3 })
	eq(b.bus, { 1, 4 })
	eq(Ring.busLanes(w, 1), { [11] = { [1] = true, [4] = true } })
	local plain = F.build({ [1] = { 0, 0 }, [2] = { 60, 0 } }, { [11] = { 1, 2, F.TPL.medium } })
	eq(Ring.busLanes(plain, 1), nil, "no bus lane: nil")
	eq(Ring.lanesAt(plain.seg(11), 1).bus, {})
	-- the ring search still counts every road lane: a one-way road with a contraflow bus lane is two-way
	local cf = F.build({ [1] = { 0, 0 }, [2] = { 60, 0 } }, { [11] = { 1, 2, CONTRAFLOW_BUS } })
	eq(Ring.oneWay(cf.seg(11)), nil)
	eq(#Ring.lanesAt(cf.seg(11), 1).incoming, 0, "no car lane arrives")
end)

test("mergeTram / roadText / keepBus: bus connections kept exactly, ignored by the status texts", function()
	local bus = { [1] = { [4] = true }, [2] = { [1] = true } }
	local cur = {
		C(1, 2, 2, 3, true, false),       -- car, replaced by the rule
		C(1, 4, 2, 1, true, false),       -- bus lane straight on: kept
		C(1, 3, 2, 1, true, true),        -- a car lane into the bus lane, with a tram flag: kept as it is
		C(1, 5, 2, 5, false, true),       -- tram only: kept (as before)
	}
	local rule = { C(1, 2, 2, 2, true, false), C(1, 3, 2, 3, true, false) }
	local out = Rules.mergeTram(rule, cur, bus)
	eq(Rules.connsText(out), "1:2>2:2:R-,1:3>2:1:RT,1:3>2:3:R-,1:4>2:1:R-,1:5>2:5:-T")
	eq(out.bus, bus, "the list carries its bus set")
	eq(Rules.roadText(out, bus), Rules.roadText(rule))
	eq(Rules.carText(out, bus), "1:2>2:2:R-,1:3>2:3:R-,1:5>2:5:-T")
	-- without a bus set: as before (tram flags kept, the rest replaced)
	eq(Rules.connsText(Rules.mergeTram(rule, cur)), "1:2>2:2:R-,1:3>2:1:-T,1:3>2:3:R-,1:5>2:5:-T")
	-- a snapshot reset: the old car lanes, today's bus connections
	local snap = { C(1, 2, 2, 3, true, false), C(1, 4, 2, 1, true, false) }
	local now = { C(1, 2, 2, 2, true, false), C(1, 4, 2, 1, true, false), C(1, 4, 2, 4, true, false) }
	eq(Rules.connsText(Rules.keepBus(snap, now, bus)), "1:2>2:3:R-,1:4>2:1:R-,1:4>2:4:R-")
	eq(Rules.keepBus(snap, now, nil), snap, "no bus lane: the snapshot itself")
end)

test("slip node with a bus lane on the main road: car lanes planned, bus connections kept, same stays same", function()
	-- main road west 2 -> 1 -> east 3 (medium_bus: 1 car lane + kerb bus lane per direction), a 2-lane
	-- one-way branch leaving to the right
	local d = F.dir(-30)
	local w = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 50 * d[1], 50 * d[2] } },
		{ [31] = { 2, 1, F.TPL.medium_bus }, [32] = { 1, 3, F.TPL.medium_bus }, [33] = { 1, 4, "BS FV FV FS", d, d } })
	local v = Slip.classify(w, 1)
	eq(v.kind, "slip")
	eq(v.case, "B")
	eq(v.bus, { [31] = { [1] = true, [4] = true }, [32] = { [1] = true, [4] = true } })
	-- at node 1: 31 car in 2, bus in 1; 32 car out 3, bus out 4; westbound 32:2 -> 31:3, bus 32:1 -> 31:4
	local cur = {
		C(31, 1, 32, 4, true, false), -- bus lane straight on (game)
		C(32, 1, 31, 4, true, false), -- westbound bus lane (game)
		C(31, 1, 33, 1, true, false), -- the player's bus turn into the slip lane
		C(31, 2, 32, 4, true, false), -- the game's car lane into the bus lane
		C(31, 2, 33, 2, true, false), -- car, replaced
	}
	local r = Slip.plan(w, 1, function() return cur end)
	eq(r.status, "apply")
	keptExactly(r.conns, busConns(cur, v.bus), "slip")
	eq(#busConns(r.conns, v.bus), 4, "no bus connection added or lost")
	local rule = Rules.withoutBus(r.conns, v.bus)
	noBusInRule(rule, v.bus, "slip")
	local text = Rules.connsText(rule)
	ok(text:find("31:2>32:3:R-", 1, true) ~= nil, "eastbound car lane straight on: " .. text)
	ok(text:find("31:2>33:", 1, true) ~= nil, "the kerb car lane (next to the bus lane) feeds the branch: " .. text)
	ok(text:find("32:2>31:3:R-", 1, true) ~= nil, "westbound car lane straight on: " .. text)
	-- applied once: same; a bus connection the player adds afterwards keeps it same
	local again = Slip.plan(w, 1, function() return r.conns end)
	eq(again.status, "same")
	local edited = {}
	for _, c in ipairs(r.conns) do edited[#edited + 1] = c end
	edited[#edited + 1] = C(31, 1, 33, 2, true, false)
	local after = Slip.plan(w, 1, function() return edited end)
	eq(after.status, "same", "a player's bus connection: still smart lanes")
	eq(Rules.roadText(edited, v.bus), Rules.roadText(r.conns, v.bus), "badge text unchanged")
	-- a node with a bus lane keeps its lights (bus priority is the player's)
	ok(not Lights.slipNode(r), "slip node with a bus lane keeps its lights")
	ok(Lights.keepsLights("B", v.bus) and not Lights.keepsLights("B", nil))
end)

--- Crossroads at node 1: main road west (11) / east (12) with `main` lanes, side road north (13) /
-- south (14) with `side` lanes (all drawn from node 1 out). t: no south arm.
local function crossing(main, side, t)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	local segs = { [11] = { 1, 2, main }, [12] = { 1, 3, main }, [13] = { 1, 4, side } }
	if not t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, side }
	end
	return F.build(nodes, segs)
end

test("crossroads with bus lanes: car lanes planned (kerb lane next to the bus lane), bus kept; default, Reset, kerb turn", function()
	local w = crossing(LARGE_BUS, F.TPL.medium)
	local v = Slip.classify(w, 1)
	eq(v.kind, "slip")
	eq(v.case, "X")
	-- LARGE_BUS from node 1: 1 bus in, 2-3 car in, 4-5 car out, 6 bus out; the kerb car lane is 2
	for _, ap in ipairs(v.approaches) do
		if ap.seg == 11 or ap.seg == 12 then
			eq(ap.m, { 2, 3 }, "approach " .. ap.seg .. ": car lanes kerb first")
		end
		for _, ex in ipairs(ap.exits) do
			if ex.seg == 11 or ex.seg == 12 then eq(ex.o, { 5, 4 }, "exit " .. ex.seg .. ": car lanes kerb first") end
		end
	end
	-- the game's bus connections (bus lane straight on both ways, a bus turn into the side road) and the
	-- player's (bus lane into the side road's kerb lane, a bus right turn from the side road into the bus lane)
	local busCur = {
		C(11, 1, 12, 6, true, false), C(12, 1, 11, 6, true, false),
		C(11, 1, 14, 4, true, false), C(13, 2, 11, 6, true, false),
	}
	local cur = Cross.defaultConns(v)
	for _, c in ipairs(busCur) do cur[#cur + 1] = c end
	ok(Cross.isDefault(v, cur), "the game's car lanes plus bus connections still read as the game default")
	local r = Slip.plan(w, 1, function() return cur end)
	eq(r.status, "apply")
	keptExactly(r.conns, busCur, "crossroads")
	eq(#busConns(r.conns, v.bus), #busCur)
	noBusInRule(Rules.withoutBus(r.conns, v.bus), v.bus, "crossroads")
	-- the kerb turn of the west approach (11 -> 14, right in right-hand traffic) leaves from car lane 2
	local kerbFrom = {}
	for _, c in ipairs(Rules.withoutBus(r.conns, v.bus)) do
		if c.segment0 == 11 and c.segment1 == 14 then kerbFrom[c.lane0] = true end
	end
	eq(kerbFrom, { [2] = true }, "west approach turns right from the kerb car lane")
	-- Reset: the game-default model for the car lanes, the bus connections as they are
	local reset = Rules.mergeTram(Slip.defaultConns(v), r.conns, v.bus)
	keptExactly(reset, busCur, "reset")
	ok(Cross.isDefault(v, reset), "Reset reads as the game default")
	eq(Rules.roadText(reset, v.bus), Rules.roadText(Cross.defaultConns(v)))
	-- free kerb turn: bus connections are no kerb turn, whatever their movement
	local kerb = Slip.kerbPairs(v)
	eq(kerb.bus, v.bus)
	local idx = Lights.kerbIndices(r.conns, kerb)
	ok(#idx > 0, "car kerb turns found")
	for _, j in ipairs(idx) do
		ok(not Rules.touchesBus(r.conns[j + 1], v.bus), "kerb index " .. j .. " is a car connection")
	end
	local busKerb = false
	for _, c in ipairs(r.conns) do
		if c.segment0 == 11 and c.lane0 == 1 and c.segment1 == 14 then busKerb = true end
	end
	ok(busKerb, "fixture: a bus connection on a kerb movement")
	-- the audit looks at the car lanes: the bus connections are no "bad" connection
	local res = Audit.audit(w, 1, r.conns, { view = v })
	eq(res.skipped, nil)
	eq(res.counts.bad, nil, "bus connections are not stale")
end)

test("crossroads with bus lanes: game phases re-point the bus connections, the Smart Lanes plan gives each a phase", function()
	local w = crossing(LARGE_BUS, F.TPL.medium)
	local v = Slip.classify(w, 1)
	local busCur = { C(11, 1, 12, 6, true, false), C(12, 1, 11, 6, true, false), C(11, 1, 14, 4, true, false) }
	local cur = Cross.defaultConns(v)
	for _, c in ipairs(busCur) do cur[#cur + 1] = c end
	local r = Slip.plan(w, 1, function() return cur end)
	-- "Game default" phases: every new connection takes its old state; a kept bus connection its own
	local nOld = #cur
	local locked = {}
	for i = 1, nOld do
		local c = cur[i]
		-- one phase: the main road green, the side road red (the bus lane 11 -> 14 turn held red)
		if c.segment0 == 13 or c.segment0 == 14 or (c.segment0 == 11 and c.lane0 == 1 and c.segment1 == 14) then
			locked[#locked + 1] = i - 1
		end
	end
	local newLocked = Rules.remapLocked(cur, r.conns, 0, locked)
	local isLocked = {}
	for _, j in ipairs(newLocked) do isLocked[j] = true end
	for j, c in ipairs(r.conns) do
		if Rules.touchesBus(c, v.bus) then
			local was = c.segment0 == 11 and c.lane0 == 1 and c.segment1 == 14
			eq(isLocked[j - 1] == true, was, "bus connection " .. Rules.connsText({ c }) .. " keeps its state")
		end
	end
	-- Light phases = Smart Lanes: the plan covers every connection, the kept bus ones included
	local cws = {}
	for _, sid in ipairs(w.node(1).segs) do cws[#cws + 1] = sid end
	local info = PP.infoFromView(v, w, 1, r.conns)
	local M = assert(Phases.build({ conns = r.conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
	local plan, why = PP.plan(M, info)
	ok(plan ~= nil, "a plan: " .. tostring(why))
	if plan then
		for j, c in ipairs(r.conns) do
			if Rules.touchesBus(c, v.bus) then
				local green = false
				for _, st in ipairs(plan.states) do
					for _, x in ipairs(st.green) do if x == j - 1 then green = true end end
				end
				ok(green, "bus connection " .. Rules.connsText({ c }) .. " is green in a phase")
			end
		end
	end
end)

test("a direction whose road lanes are all bus-only has no car lanes: the road is one-way for cars", function()
	-- crossroads whose north road (drawn from node 1 out) has car lanes northbound only, leaving the
	-- junction, and a southbound bus lane arriving
	local w = crossing(F.TPL.medium, F.TPL.medium)
	w.segs[13].lanes = F.lanes(CONTRAFLOW_BUS)
	local v = Slip.classify(w, 1)
	eq(v.kind, "slip")
	eq(v.case, "X", "three two-way roads and one (for cars) one-way road: the crossing rule")
	for _, ap in ipairs(v.approaches) do
		ok(ap.seg ~= 13, "no car approach on the bus-only direction")
	end
	local cur = { C(13, 1, 12, 3, true, false) } -- the bus lane arriving, turning left into the east road
	local r = Slip.plan(w, 1, function() return cur end)
	keptExactly(r.conns, cur, "contraflow bus lane")
	noBusInRule(Rules.withoutBus(r.conns, v.bus), v.bus, "contraflow")
	-- a road whose lanes are all bus-only is no road for the rules (as a tram-only track): a T of the rest
	local ww = crossing(F.TPL.medium, F.TPL.medium)
	ww.segs[13].lanes = F.lanes("BS BU FU FS")
	local vt = Slip.classify(ww, 1)
	eq(vt.case, "X")
	eq(vt.shape, "t_junction")
end)

test("lane drop next to a bus lane: car lanes fold into the car lane, bus connections kept (a bus U-turn is no turnaround)", function()
	-- 3 + 3 car lanes (large) meeting 1 car lane + bus lane per direction (medium_bus): for cars a drop
	-- eastbound and a gain westbound (case D)
	local w = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 } },
		{ [31] = { 2, 1, F.TPL.large }, [32] = { 1, 3, F.TPL.medium_bus } })
	local v = Slip.classify(w, 1)
	eq(v.kind, "slip")
	eq(v.case, "D")
	eq(v.shape, "lane_drop+gain")
	-- 31 at node 1 (node1 end): car in 1..3, out 4..6; 32 at node 1 (node0): bus in 1, car in 2, car out 3, bus out 4
	local busCur = {
		C(31, 1, 32, 4, true, false), -- the game's kerb car lane into the bus lane
		C(32, 1, 31, 6, true, false), -- the bus lane on into the kerb lane
		C(32, 1, 32, 4, true, false), -- the player's bus U-turn
	}
	local r = Slip.plan(w, 1, function() return busCur end)
	eq(r.status, "apply", "a bus U-turn does not make it a turnaround (u_turn)")
	keptExactly(r.conns, busCur, "drop")
	local rule = Rules.withoutBus(r.conns, v.bus)
	noBusInRule(rule, v.bus, "drop")
	-- eastbound: the three car lanes all into 32's car lane 3; westbound: 32:2 into all three
	local ins, outs = {}, {}
	for _, c in ipairs(rule) do
		if c.segment0 == 31 then
			eq(c.segment1, 32)
			eq(c.lane1, 3)
			ins[c.lane0] = true
		else
			eq(c.lane0, 2)
			outs[c.lane1] = true
		end
	end
	eq(ins, { [1] = true, [2] = true, [3] = true })
	eq(outs, { [4] = true, [5] = true, [6] = true })
	-- a road car U-turn still skips the node
	local turn = Slip.plan(w, 1, function() return { C(32, 2, 32, 3, true, false) } end)
	eq(turn.status, "skip")
	eq(turn.reason, "u_turn")
end)

test("ring arm with a bus lane: car lanes planned, bus connections kept, ringForm and autoSeeds ignore them", function()
	local W = F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium_bus" }, { tpl = "medium" }, { tpl = "medium" } } })
	local ring = assert(Ring.findRing(W, 1))
	local busNode, bv = nil, nil
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(W, ring, n)
		if v.bus ~= nil then busNode, bv = n, v end
	end
	ok(busNode ~= nil, "the bus arm's junction")
	eq(bv.kind, "arm")
	eq(#bv.x, 1, "one car exit lane")
	eq(#bv.e, 1, "one car entry lane")
	local arm = bv.arm
	local busIdx = {}
	for idx in pairs(bv.bus[arm]) do busIdx[#busIdx + 1] = idx end
	table.sort(busIdx)
	eq(#busIdx, 2)
	-- current: the engine default plus bus connections (outer ring lane into the bus lane, the bus lane in)
	local cur = {}
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(W, ring, n)
		if v.kind == "arm" then cur[n] = Rules.engineDefault(v) end
	end
	local la = Ring.lanesAt(W.seg(arm), busNode)
	local busOut, busIn = nil, nil
	for _, idx in ipairs(la.bus) do
		-- the arm is drawn from the ring node out: the bus lane leaving the node is the forward one
		if idx == busIdx[#busIdx] then busOut = idx else busIn = idx end
	end
	local busCur = { C(bv.ringIn, bv.o_in[1], arm, busOut, true, false), C(arm, busIn, bv.ringOut, bv.o_out[1], true, false) }
	for _, c in ipairs(busCur) do table.insert(cur[busNode], c) end
	local all = {}
	for _, n in ipairs(ring.nodes) do all[n] = true end
	local p = Rules.planRing(W, ring, all, "two_lane", function(n) return cur[n] or {} end)
	local skips = 0
	for _, r in ipairs(p.nodes) do
		if r.status == "skip" then skips = skips + 1 end
		if r.node == busNode then
			eq(r.status, "apply")
			keptExactly(r.conns, busCur, "ring arm")
			eq(#busConns(r.conns, bv.bus), 2)
			noBusInRule(Rules.withoutBus(r.conns, bv.bus), bv.bus, "ring arm")
			-- the planned form with the bus connections is still a form the automatic pass accepts
			ok(Rules.ringForm(bv, r.conns) ~= nil, "ringForm with bus connections: " .. tostring(Rules.ringForm(bv, r.conns)))
			eq(Rules.ringForm(bv, cur[busNode]), "engine", "the engine default plus bus connections")
			cur[busNode] = r.conns
		end
	end
	eq(skips, 0, "no junction skipped")
	-- the player adds a bus connection: still no hand edit (autoSeeds adds the junction)
	table.insert(cur[busNode], C(bv.ringIn, bv.o_in[1], arm, busOut, true, true))
	local seeds = {}
	for _, n in ipairs(ring.nodes) do if n ~= busNode then seeds[n] = true end end
	local s = Rules.autoSeeds(W, ring, seeds, function(n) return cur[n] or {} end)
	eq(s.handEdit, {})
	eq(s.whole, true)
	-- lights: the bus arm keeps its (the player's bus priority); the others follow the setting
	for _, n in ipairs(Lights.ringNodes(p)) do ok(n ~= busNode, "bus arm junction keeps its lights") end
	eq(#Lights.ringNodes(p), 2)
end)

test("a ring with a bus lane stays skipped: no ring, and its junctions are not slip nodes either", function()
	local B = F.ring({ ringTpl = "one_way_small_bus", arms = { { tpl = "medium" }, { tpl = "medium" }, { tpl = "medium" } } })
	local ring, why = Ring.findRing(B, 1)
	eq(ring, nil)
	eq(why, "bus_lane_ring")
	for _, n in ipairs({ 1, 2, 3 }) do
		local v = Slip.classify(B, n)
		eq(v.kind, "skip", "ring node " .. n)
		eq(v.reason, "bus_lane_ring")
	end
	eq(Pick.reasonText("bus_lane_ring"), "the ring has a bus lane")
end)

test("a crossroads whose cross road has bus-only lanes (no car lane): busRoad, and the status says so (user 2026-10-17)", function()
	-- node 1: a two-way car road west-east (2 -> 1 -> 3), a bus-only road north-south (4 -> 1 -> 5)
	local W = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } },
		{ [10] = { 2, 1, F.TPL.medium }, [11] = { 1, 3, F.TPL.medium }, [12] = { 4, 1, "BS BU FU FS" },
			[13] = { 1, 5, "BS BU FU FS" } })
	local v = Slip.classify(W, 1)
	eq(v.busRoad, true)
	ok(v.kind ~= "slip", "not handled: " .. tostring(v.kind))
	eq(Pick.reasonText("bus_road"), "a road has only bus lanes")
	-- a bus lane beside car lanes is no bus road
	local W2 = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } },
		{ [10] = { 2, 1, F.TPL.medium }, [11] = { 1, 3, F.TPL.medium }, [12] = { 4, 1, F.TPL.medium_bus },
			[13] = { 1, 5, F.TPL.medium_bus } })
	eq(Slip.classify(W2, 1).busRoad, nil)
end)

test("status line: a handled junction with a bus lane says its bus lanes stay", function()
	eq(Pick.detail({ kind = "node", node = 7, roads = 4, conns = 30, nodeKind = "slip", slipShape = "crossroads", busKept = true }),
		"30 lane connections, bus lanes kept as they are")
	eq(Pick.detail({ kind = "node", node = 7, ringKey = 3, nodeKind = "arm", exits = 1, entries = 1, conns = 6, busKept = true }),
		"6 lane connections, 1 exit, 1 entry lanes, bus lanes kept as they are")
	eq(Pick.detail({ kind = "node", node = 7, roads = 3, conns = 9, slipReason = "bus_lane_ring", busKept = true }),
		"not handled: the ring has a bus lane", "not handled: no bus note")
end)
