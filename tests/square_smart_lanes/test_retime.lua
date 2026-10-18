-- square_smart_lanes Re-time (rev 8, PLAN.md "Re-time: phase lengths from measured traffic"): the pure part
-- (sl_retime.lua): a driver's path through a junction, phase kinds, movements per phase, new durations from
-- measured passes and queues (cycle, floors, pedestrians, hysteresis), both traffic sides.

local R = ug_require "square_smart_lanes::/smart_lanes/sl_retime.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local C = Rules.conn

--- Crossroads at node 1 (as test_phaseplan.lua): 11 west, 12 east (the main road), 13 north, 14 south.
local function crossing(mirror_)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local segs = { [11] = { 1, 2, F.TPL.medium }, [12] = { 1, 3, F.TPL.medium }, [13] = { 1, 4, F.TPL.medium },
		[14] = { 1, 5, F.TPL.medium } }
	local world = F.build(nodes, segs, mirror_)
	local v = Slip.classify(world, 1)
	assert(v.case == "X", "crossing fixture is case X")
	return v, world
end

--- The game's six phases over the crossroads' default connections (crosswalks 11..14): main axis green, all-red
-- 6 s, side axis green, all-red 6 s, pedestrians only 3 s, all-red 9 s.
local function gamePhases(conns, nCross, main, side)
	local function phase(green, cw, d)
		local l = {}
		for i, c in ipairs(conns) do
			if not green[c.segment0] then l[#l + 1] = i - 1 end
		end
		if not cw then
			for k = 1, nCross do l[#l + 1] = #conns + k - 1 end
		end
		return { locked = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	return { phase({ [11] = true, [12] = true }, false, main or 23.7), phase({}, false, 6),
		phase({ [13] = true, [14] = true }, false, side or 23.7), phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) }
end

local function fixture(mirror_)
	local v = crossing(mirror_)
	local conns = Cross.defaultConns(v)
	return conns, gamePhases(conns, 4)
end

local function input(conns, states, passes, queue, extra)
	local t = { conns = conns, nCross = 4, states = states, passes = passes or {}, queue = queue or {}, windowS = 180,
		samples = 60 }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

---------------------------------------------------------------------------
-- The path

test("pathAt: the junction ahead (or inside it), behind after passing, the movement around it, look limits", function()
	-- elements: far node 2, edge 11, junction 1, edge 12, far node 3
	local path = { 2, 11, 1, 12, 3 }
	local reads = 0
	local function get(i)
		reads = reads + 1
		return path[i + 1]
	end
	local st, a, b = R.pathAt(get, #path, 1, 1, 8, false)
	eq({ st, a, b }, { "ahead", 11, 12 })
	st, a, b = R.pathAt(get, #path, 2, 1, 8, false)
	eq({ st, a, b }, { "ahead", 11, 12 }, "inside the junction: not passed yet")
	st = R.pathAt(get, #path, 3, 1, 8, false)
	eq(st, nil, "behind, but not looked for")
	st, a, b = R.pathAt(get, #path, 3, 1, 8, true)
	eq({ st, a, b }, { "behind", 11, 12 })
	st = R.pathAt(get, #path, 0, 1, 1, true)
	eq(st, nil, "two elements ahead, look 1")
	-- the junction at the path's start / end: no movement there
	st, a, b = R.pathAt(get, 3, 0, 2, 8, false)
	eq({ st, a, b }, { "ahead", nil, 11 })
	eq(R.pathAt(get, 0, 0, 1, 8, true), nil, "an empty path")
	reads = 0
	R.pathAt(get, 100, 50, 999, 8, true)
	ok(reads <= 17, "reads " .. reads .. " within the look window")
	eq(R.moveKey(11, 12), "11>12")
	eq(R.approachOf("11>12"), 11)
end)

test("rerouteClass: same / exit_changed / dropped / gone", function()
	eq(R.rerouteClass(12, "ahead", 12, false), "same")
	eq(R.rerouteClass(12, "behind", 12, false), "same")
	eq(R.rerouteClass(12, "ahead", 14, false), "exit_changed")
	eq(R.rerouteClass(12, nil, nil, false), "dropped")
	eq(R.rerouteClass(12, "ahead", 12, true), "gone")
end)

---------------------------------------------------------------------------
-- Phases and movements

test("kinds and served: the game's six phases; a movement is served where one of its connections is green", function()
	local conns, states = fixture(false)
	eq(R.kinds(#conns, 4, states), { "veh", "all_red", "veh", "all_red", "walk", "all_red" })
	local served, lanes = R.served(conns, states, R.kinds(#conns, 4, states))
	eq(served["11>12"], { [1] = true })
	eq(served["13>14"], { [3] = true })
	eq(served["11>13"] ~= nil, true)
	for s = 11, 14 do ok((lanes[s] or 0) >= 1, "entry lanes of " .. s) end
	-- a shared lane: one of the movement's connections green is enough
	local cs = { C(1, 1, 2, 3), C(1, 1, 3, 4), C(1, 2, 3, 3) }
	local st = { { locked = { 1 } }, { locked = { 0, 2 } } }
	local sv = R.served(cs, st, R.kinds(3, 0, st))
	eq(sv["1>3"], { [1] = true, [2] = true }, "green in phase 1 by its second lane, in phase 2 by its first")
	eq(sv["1>2"], { [1] = true })
end)

---------------------------------------------------------------------------
-- Timing

test("plan: the busy main road gets the longer green, the fixed phases stay, the cycle from the traffic, both traffic sides", function()
	for _, mir in ipairs({ false, true }) do
		local tag = mir and "left" or "right"
		local conns, states = fixture(mir)
		-- main road 60 cars each way over 180 s on 2 entry lanes (600 cars / lane / h), side road 10 one way
		local passes = { ["11>12"] = 60, ["12>11"] = 60, ["13>14"] = 10 }
		local p = R.plan(input(conns, states, passes))
		eq(p.reason, "write", tag)
		eq(p.changed, true, tag)
		eq({ p.durations[2], p.durations[4], p.durations[5], p.durations[6] }, { 6, 6, 3, 9 }, tag .. ": pauses and walk kept")
		ok(p.durations[1] >= 30 and p.durations[3] <= 16, tag .. ": " .. R.listText(p.durations))
		eq(p.cycleReason, "webster", tag)
		-- Y = (600 + 100) / 1800, L = 24 s of pauses + 2 x 2 s start-up: C = (1.5 x 28 + 5) / (1 - Y) = 76.9 s
		near(p.y, 700 / 1800, 1e-9, tag)
		eq(p.lost, 28, tag)
		eq(p.satSrc, "opt", tag)
		ok(math.abs(p.cycle - 77) <= 1, tag .. ": cycle " .. p.cycle)
		for i = 1, 6 do eq(p.minDurations[i], 1.5, tag) end
		eq(p.total, 130, tag)
		eq(p.unmapped, 0, tag)
		-- the side road busy instead: the other way round
		local q = R.plan(input(conns, states, { ["11>12"] = 10, ["13>14"] = 60, ["14>13"] = 60 }))
		ok(q.durations[3] >= 30 and q.durations[1] <= 16, tag .. ": " .. R.listText(q.durations))
	end
	-- the same numbers on both sides
	local cR, sR = fixture(false)
	local cL, sL = fixture(true)
	local passes = { ["11>12"] = 50, ["12>11"] = 40, ["13>14"] = 10, ["11>13"] = 8 }
	eq(R.plan(input(cR, sR, passes)).durations, R.plan(input(cL, sL, passes)).durations)
end)

test("plan: the cycle from the measurement: Webster's optimum, 40 s at least, 120 s when saturated or queued all the time", function()
	local conns, states = fixture(false)
	-- quiet: Webster's optimum with the game's 24 s of pauses (L = 28 s): (1.5 x 28 + 5) / (1 - 0.089) = 51.6 s
	-- (keepLoadedOnShrink off: the cycle rule alone)
	local NOKEEP = { keepLoadedOnShrink = false }
	local quiet = R.plan(input(conns, states, { ["11>12"] = 8, ["12>11"] = 8, ["13>14"] = 8, ["14>13"] = 8 }), NOKEEP)
	eq(quiet.cycleReason, "webster", R.listText(quiet.durations))
	eq(quiet.cycle, 52, R.listText(quiet.durations))
	-- by default a shorter cycle for light traffic never cuts a phase with an equal share of the loads below
	-- min(its current, the game's green for its lanes): both roads light alike -> the game's greens stay (fits)
	local quietK = R.plan(input(conns, states, { ["11>12"] = 8, ["12>11"] = 8, ["13>14"] = 8, ["14>13"] = 8 }))
	eq({ quietK.reason, math.floor(quietK.cycleWanted + 0.5), quietK.keptLoaded }, { "fits", 52, true }, R.listText(quietK.durations))
	-- one road light, the other idle: only the idle road's green shortens
	local oneK = R.plan(input(conns, states, { ["11>12"] = 8, ["12>11"] = 8, ["13>14"] = 0, ["14>13"] = 1 }))
	ok(oneK.durations[1] >= 23 and oneK.durations[3] < 20, R.listText(oneK.durations))
	-- fewer pauses (an axis plan's two 6 s pedestrian phases, L = 16 s) and little traffic: the 40 s minimum
	local axisLike = gamePhases(conns, 4)
	table.remove(axisLike, 6)
	table.remove(axisLike, 5)
	axisLike[2].duration, axisLike[4].duration = 3, 3
	local pm = R.plan(input(conns, axisLike, { ["11>12"] = 8, ["12>11"] = 8, ["13>14"] = 8, ["14>13"] = 8 }), NOKEEP)
	eq(pm.cycleReason, "min", R.listText(pm.durations))
	eq(pm.cycle, 40, R.listText(pm.durations))
	-- even, moderate: about the game's own cycle (71.4 s): its equal greens fit
	local even = R.plan(input(conns, states, { ["11>12"] = 31, ["12>11"] = 31, ["13>14"] = 31, ["14>13"] = 31 }))
	eq(even.reason, "fits", R.listText(even.durations) .. " cycle " .. even.cycle)
	eq(even.cycleReason, "webster")
	-- saturated (Y >= 0.9), one road busier (share 0.73, not balanced): the longest cycle, greens at most 60 s
	local sat = R.plan(input(conns, states, { ["11>12"] = 400, ["12>11"] = 400, ["13>14"] = 150, ["14>13"] = 150 }))
	eq(sat.cycleReason, "saturated")
	ok(sat.y >= 0.9, tostring(sat.y))
	eq(sat.cycle, 120, R.listText(sat.durations))
	ok(sat.durations[1] > sat.durations[3] and sat.durations[1] <= 60, R.listText(sat.durations))
	-- light flows but a standing queue on a critical approach (5 cars per lane at every sample): the longest
	-- cycle, and the saturation flow estimated from that approach's passes over its green seconds
	local qd = R.plan(input(conns, states, { ["11>12"] = 30, ["12>11"] = 20, ["13>14"] = 20, ["14>13"] = 20 },
		{ ["11>12"] = 10 }))
	eq(qd.cycleReason, "queues")
	eq(qd.cycle, 120, R.listText(qd.durations))
	eq(qd.satSrc, "est")
	-- 15 passes per lane in 180 x 23.7 / 71.4 = 59.7 s of green: 904 cars / lane / h, clamped to satMin 1200
	eq(qd.sat, 1200)
	-- the option range: a lower cycleMax caps it
	eq(R.plan(input(conns, states, { ["11>12"] = 400, ["12>11"] = 400, ["13>14"] = 150 }), { cycleMax = 90 }).cycle, 90)
	-- both roads saturated alike (300 / 280: share 0.52): balanced, the cycle at most max(75 s, the current 71.4 s)
	local bal = R.plan(input(conns, states, { ["11>12"] = 300, ["12>11"] = 300, ["13>14"] = 280, ["14>13"] = 280 }))
	eq({ bal.balanced, bal.cycleReason, bal.cycleWanted }, { true, "balanced", 120 })
	ok(bal.cycle >= 74 and bal.cycle <= 76, tostring(bal.cycle))
end)

test("plan: queues add demand; a queue alone on the side road lengthens its green", function()
	local conns, states = fixture(false)
	local even = { ["11>12"] = 31, ["12>11"] = 31, ["13>14"] = 31, ["14>13"] = 31 }
	local p = R.plan(input(conns, states, even))
	eq(p.reason, "fits", "even traffic: the game's equal greens fit")
	local q = R.plan(input(conns, states, even, { ["13>14"] = 6 }))
	eq(q.reason, "write")
	ok(q.durations[3] > q.durations[1], R.listText(q.durations))
	-- demand = passes + 0.5 x mean queue x (window / cycle)
	near(q.demand["13>14"], 31 + 0.5 * 6 * 180 / 71.4, 1e-9)
end)

test("plan: too small a sample, nothing mapped, no vehicle phase: keep", function()
	local conns, states = fixture(false)
	eq(R.plan(input(conns, states, { ["11>12"] = 5 })).reason, "small_sample")
	eq(R.plan(input(conns, states, { ["11>12"] = 300 }, nil, { samples = 10 })).reason, "small_sample", "few samples")
	eq(R.plan(input(conns, states, {}, { ["11>12"] = 4 })).keep, nil, "queues alone are enough")
	-- traffic only on movements no phase serves (not a connection of the node)
	local p = R.plan(input(conns, states, { ["11>99"] = 300 }))
	eq(p.reason, "no_mapped_traffic")
	eq(p.unmapped, 300)
	-- a movement green in every vehicle phase (a curb turn freed all cycle) sets no phase's length
	local st = { { locked = { 1 }, duration = 20 }, { locked = { 0 }, duration = 20 } }
	local cs = { C(1, 1, 2, 3), C(3, 1, 4, 3), C(1, 2, 5, 3) }
	local q = R.plan({ conns = cs, nCross = 0, states = st, passes = { ["1>5"] = 300 }, windowS = 180, samples = 60 })
	eq(q.reason, "no_mapped_traffic")
	eq(q.always, 300)
	-- every phase all-red / walk
	local w = R.plan({ conns = cs, nCross = 0, states = { { locked = { 0, 1, 2 }, duration = 5 } }, passes = { ["1>2"] = 300 },
		windowS = 180, samples = 60 })
	eq(w.reason, "no_vehicle_phase")
end)

test("plan: floors (min green, a shorter phase the player set, pedestrians), cycle range, minDuration, 1..60 s", function()
	local conns, states = fixture(false)
	local heavy = { ["11>12"] = 600, ["12>11"] = 600, ["13>14"] = 1 }
	-- (a 72 s cycle: the quiet phase's share falls under its floor)
	local p = R.plan(input(conns, states, heavy), { cycleMax = 72 })
	eq(p.durations[3], 6, "the quiet phase at min green " .. R.listText(p.durations))
	-- a 4 s phase the player made stays at least 4, not raised to 6
	local s2 = gamePhases(conns, 4, 23.7, 4)
	local p2 = R.plan(input(conns, s2, heavy), { cycleMax = 72 })
	eq(p2.durations[3], 4, R.listText(p2.durations))
	-- cycle range: whatever the current cycle (130 s or 39 s), within 40..120 s
	local long = gamePhases(conns, 4, 50, 56)
	local pl = R.plan(input(conns, long, { ["11>12"] = 300, ["13>14"] = 100 }))
	eq(pl.cycle, 120, R.listText(pl.durations))
	local short = gamePhases(conns, 4, 3, 3)
	local ps = R.plan(input(conns, short, { ["11>12"] = 8, ["13>14"] = 8 }))
	ok(ps.cycle >= 40 and ps.cycle <= 52, "quiet: Webster's cycle " .. R.listText(ps.durations))
	-- every veh phase within 1..60 s and whole seconds
	for _, d in ipairs(pl.durations) do ok(d >= 1 and d <= 60, tostring(d)) end
	for i, k in ipairs(pl.kinds) do
		if k == "veh" then eq(pl.durations[i], math.floor(pl.durations[i]), "whole seconds") end
	end
	-- a crosswalk green with the side road: that phase keeps the crossing time (4 lanes x 4.5 m / 1.2 m/s + 3 s = 18 s)
	-- less the 3 s it is green in the walk phase
	local cw = gamePhases(conns, 4)
	local l = {}
	for _, x in ipairs(cw[3].locked) do
		if x ~= #conns then l[#l + 1] = x end
	end
	cw[3].locked = l
	local need = R.pedNeed({ 11, 12, 13, 14 }, { [11] = 4, [12] = 4, [13] = 4, [14] = 4 })
	eq(need[1], 4 * 4.5 / 1.2 + 3)
	local pc = R.plan(input(conns, cw, heavy, nil, { pedNeed = need }), { cycleMax = 72 })
	eq(pc.durations[3], 15, "pedestrian floor: " .. R.listText(pc.durations))
	-- minDuration never above the duration
	local sm = gamePhases(conns, 4)
	sm[3].minDuration = 20
	local pm = R.plan(input(conns, sm, heavy), { cycleMax = 90 })
	ok(pm.minDurations[3] <= pm.durations[3], R.listText(pm.minDurations))
	eq(pm.minDurations[3], pm.durations[3])
end)

test("plan: hysteresis: small changes are not written", function()
	local conns, states = fixture(false)
	-- a little more on the main road: within 3 s / 15 %
	local p = R.plan(input(conns, states, { ["11>12"] = 33, ["12>11"] = 33, ["13>14"] = 31, ["14>13"] = 31 }))
	eq(p.changed, false, R.listText(p.durations))
	eq(p.reason, "fits")
	ok(p.maxDelta < 3, tostring(p.maxDelta))
	-- a lot more: written
	local q = R.plan(input(conns, states, { ["11>12"] = 70, ["12>11"] = 70, ["13>14"] = 31, ["14>13"] = 31 }))
	eq(q.changed, true, R.listText(q.durations))
	-- a stricter threshold (step B) keeps it
	local r = R.plan(input(conns, states, { ["11>12"] = 70, ["12>11"] = 70, ["13>14"] = 31, ["14>13"] = 31 }),
		{ hystAbs = 60 })
	eq(r.changed, false)
end)

test("mapText / listText", function()
	eq(R.mapText({ b = 2, a = 1.25 }), "a:1.2,b:2")
	eq(R.mapText({}), "-")
	eq(R.mapText({ a = 1, b = 2, c = 3 }, 2), "a:1,b:2,+1")
	eq(R.listText({ 23.7, 6, 3 }), "23.7/6/3")
end)

test("plan on a Smart Lanes axis plan (rev 8 default): pedestrian phases walk (kept), road phases veh, a head start veh; the busy road longer", function()
	local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
	local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
	for _, mir in ipairs({ false, true }) do
		local tag = mir and "left" or "right"
		local v, world = crossing(mir)
		local conns = Cross.defaultConns(v)
		local cws = { 11, 12, 13, 14 }
		local info = PP.infoFromView(v, world, 1, conns)
		local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
		local plan = assert(PP.plan(M, info))
		eq(plan.kind, "x4_axis", tag)
		eq(R.kinds(#conns, 4, plan.states), { "veh", "walk", "veh", "walk" }, tag)
		local main = plan.axis[1][1]
		local cross = plan.axis[3][1]
		local other = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
		local passes = { [R.moveKey(main, other[main])] = 60, [R.moveKey(other[main], main)] = 60,
			[R.moveKey(cross, other[cross])] = 10 }
		local p = R.plan(input(conns, plan.states, passes))
		eq(p.reason, "write", tag)
		eq({ p.durations[2], p.durations[4] }, { 6, 6 }, tag .. ": pedestrian phases kept")
		ok(p.durations[1] > p.durations[3], tag .. ": the busy road longer: " .. R.listText(p.durations))
		-- the cycle from the traffic: L = 12 s of pedestrian phases + 2 x 2 s, Y = 700 / 1800: (1.5 x 16 + 5) / 0.61 = 47.5 s
		eq(p.cycleReason, "webster", tag)
		ok(math.abs(p.cycle - 47.5) <= 1, tag .. ": " .. R.listText(p.durations))
		-- the pedestrian phases skip after their 3 s clearance (rev 8): minDuration kept as read
		eq({ p.minDurations[1], p.minDurations[2] }, { 1.5, 3 }, tag)
		-- a head start (measured demand) is a vehicle phase too
		local demand = {}
		for _, c in ipairs(conns) do
			if c.segment0 == 11 then demand["11:" .. c.lane0] = 3 end
		end
		local ph = assert(PP.plan(M, info, { laneDemand = demand }))
		eq(R.kinds(#conns, 4, ph.states), { "veh", "veh", "walk", "veh", "walk" }, tag .. ": head start")
	end
end)

test("plan: a player's saturated 1-lane crossroads (node 498446, 2026-10-14): balanced, so the cycle grows to 75 s (120 s before v3)", function()
	-- the measured run: q_arm=498198:28.9,498258:28.6,498390:23.4,5903:21.7 total=169 load=1:89.1,3:91.1
	-- old=19/6/19/6 (an axis plan), "fits" under the old rule (the cycle kept). Approaches here 11 / 12 (road 1)
	-- and 13 / 14 (road 2), straights only, passes 37 / 37 / 49 / 46 (169) with those queues.
	local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
	local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local segs = { [11] = { 1, 2, F.TPL.small }, [12] = { 1, 3, F.TPL.small }, [13] = { 1, 4, F.TPL.small },
		[14] = { 1, 5, F.TPL.small } }
	local world = F.build(nodes, segs, false)
	local v = Slip.classify(world, 1)
	local conns = Cross.defaultConns(v)
	local info = PP.infoFromView(v, world, 1, conns)
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = { 11, 12, 13, 14 }, cls = info.cls }))
	local plan = assert(PP.plan(M, info))
	local d = {}
	for i, st in ipairs(plan.states) do d[i] = st.duration end
	eq(d, { 19, 6, 19, 6 }, "the 1-lane axis plan: 19 s greens (the game's 1-lane floor 18.9 s)")
	local a1, a3 = plan.axis[1][1], plan.axis[3][1]
	local opp = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
	local passes = { [R.moveKey(a1, opp[a1])] = 37, [R.moveKey(opp[a1], a1)] = 37, [R.moveKey(a3, opp[a3])] = 49,
		[R.moveKey(opp[a3], a3)] = 46 }
	local queue = { [R.moveKey(a1, opp[a1])] = 28.9, [R.moveKey(opp[a1], a1)] = 28.6, [R.moveKey(a3, opp[a3])] = 23.4,
		[R.moveKey(opp[a3], a3)] = 21.7 }
	local p = R.plan(input(conns, plan.states, passes, queue))
	print(string.format("node 498446: result=%s old=19/6/19/6 new=%s cycle=%d y=%.2f lost=%d sat=%.0f(%s) reason=%s load=%s",
		p.reason, R.listText(p.durations), p.cycle, p.y, p.lost, p.sat, p.satSrc, p.cycleReason, R.mapText(p.load)))
	eq(p.reason, "write")
	-- both roads about equally loaded (89 / 91: share 0.51): the cycle stops at balancedCycle (v3, run 2)
	eq(p.balanced, true)
	eq(p.cycleReason, "balanced")
	eq(p.cycleWanted, 120)
	eq(p.cycle, 75)
	eq(p.lost, 16)
	eq({ p.durations[2], p.durations[4] }, { 6, 6 })
	ok(p.durations[1] >= 30 and p.durations[3] >= 30, R.listText(p.durations))
	-- without the balanced rule (as rev 8 before v3): straight to 120 s
	local q = R.plan(input(conns, plan.states, passes, queue), { balanceRatio = 0 })
	eq(q.cycleReason, "saturated")
	eq(q.cycle, 120)
	ok(q.durations[1] >= 50 and q.durations[3] >= 50, R.listText(q.durations))
end)

test("plan with maxCycleStep (step B, automatic re-timing): the saturated crossroads walks 50 -> 70 -> 90 -> 110 s, then fits", function()
	local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
	local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local segs = { [11] = { 1, 2, F.TPL.small }, [12] = { 1, 3, F.TPL.small }, [13] = { 1, 4, F.TPL.small },
		[14] = { 1, 5, F.TPL.small } }
	local world = F.build(nodes, segs, false)
	local v = Slip.classify(world, 1)
	local conns = Cross.defaultConns(v)
	local info = PP.infoFromView(v, world, 1, conns)
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = { 11, 12, 13, 14 }, cls = info.cls }))
	local plan = assert(PP.plan(M, info))
	local a1, a3 = plan.axis[1][1], plan.axis[3][1]
	local opp = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
	local passes = { [R.moveKey(a1, opp[a1])] = 37, [R.moveKey(opp[a1], a1)] = 37, [R.moveKey(a3, opp[a3])] = 49,
		[R.moveKey(opp[a3], a3)] = 46 }
	local queue = { [R.moveKey(a1, opp[a1])] = 28.9, [R.moveKey(opp[a1], a1)] = 28.6, [R.moveKey(a3, opp[a3])] = 23.4,
		[R.moveKey(opp[a3], a3)] = 21.7 }
	-- the manual Re-time (no option): unchanged, straight to 120 s
	-- (balanceRatio = 0: these balanced loads would stop at 75 s; this test is about the steps)
	local manual = R.plan(input(conns, plan.states, passes, queue), { balanceRatio = 0 })
	eq(manual.cycle, 120)
	eq(manual.cycleStepped, nil)
	-- the automatic one: at most 20 s per write, the same traffic each time
	local states = plan.states
	local cycles = {}
	for _ = 1, 6 do
		local p = R.plan(input(conns, states, passes, queue), { maxCycleStep = 20, balanceRatio = 0 })
		if p.keep or not p.changed then break end
		eq(p.cycleWanted, 120)
		ok(math.abs(p.cycle - p.oldCycle) <= 20 + 1, "a step of at most 20 s (whole seconds): " .. p.oldCycle .. ">" .. p.cycle)
		eq({ p.durations[2], p.durations[4] }, { 6, 6 }, "pedestrian phases kept")
		cycles[#cycles + 1] = p.cycle
		local nx = {}
		for i, st in ipairs(states) do
			nx[i] = { lockedLanes = st.lockedLanes, locked = st.locked, duration = p.durations[i], minDuration = p.minDurations[i],
				canSkip = st.canSkip }
		end
		states = nx
	end
	-- the last 10 s (110 -> 120) move each green by 5 s, under the hysteresis (max(3 s, 15 %) of ~52 s): fits
	eq(cycles, { 70, 90, 110 })
	-- a quiet junction shortens by at most 20 s too
	local quiet = { [R.moveKey(a1, opp[a1])] = 10, [R.moveKey(opp[a1], a1)] = 10, [R.moveKey(a3, opp[a3])] = 3 }
	local long = {}
	for i, st in ipairs(plan.states) do
		long[i] = { lockedLanes = st.lockedLanes, locked = st.locked, duration = (i % 2 == 1) and 50 or 6,
			minDuration = st.minDuration, canSkip = st.canSkip }
	end
	local q = R.plan(input(conns, long, quiet), { maxCycleStep = 20 })
	eq(q.oldCycle, 112)
	ok(q.cycleWanted < 92, "Webster wants much shorter: " .. q.cycleWanted)
	eq(q.cycleStepped, true)
	ok(q.cycle >= 92 - 1 and q.cycle <= 92 + 1, "112 -> 92 s: " .. q.cycle)
end)

test("pathAtMulti: every junction of the set on the path, ahead nearest first, behind ones only with behind = true", function()
	-- elements alternate nodes and edges: 101 (node) 1 (edge) 102 (node) 2 103 3 104
	local path = { 101, 1, 102, 2, 103, 3, 104 }
	local reads = 0
	local function get(i)
		reads = reads + 1
		return path[i + 1]
	end
	local set = { [101] = true, [103] = true, [104] = true }
	local hits, n = R.pathAtMulti(get, #path, 2, set, 8, true)
	eq(hits, { { node = 103, i = 4, state = "ahead", inSeg = 2, outSeg = 3 }, { node = 104, i = 6, state = "ahead", inSeg = 3 },
		{ node = 101, i = 0, state = "behind", outSeg = 1 } })
	eq(n, 7, "each element read once")
	eq(reads, 7)
	-- without behind: only the ones ahead; the look limit
	hits = R.pathAtMulti(get, #path, 2, set, 8, false)
	eq(#hits, 2)
	hits = R.pathAtMulti(get, #path, 2, set, 2, false)
	eq(hits, { { node = 103, i = 4, state = "ahead", inSeg = 2, outSeg = 3 } })
	-- the same answers as pathAt, junction by junction
	for node in pairs(set) do
		local st, a, b = R.pathAt(get, #path, 2, node, 8, true)
		local hit
		for _, h in ipairs(R.pathAtMulti(get, #path, 2, { [node] = true }, 8, true)) do hit = h end
		eq({ hit and hit.state, hit and hit.inSeg, hit and hit.outSeg }, { st, a, b }, "node " .. node)
	end
	eq(R.pathAtMulti(get, 0, 0, set, 8, true), {})
	eq(R.pathAtMulti(get, nil, 0, set, 8, true), {})
	-- an unreadable element: skipped, never read twice
	reads = 0
	local holes = { 101, 1, false, 2, 103 }
	local function get2(i)
		reads = reads + 1
		return holes[i + 1] or nil
	end
	hits = R.pathAtMulti(get2, #holes, 0, set, 8, true)
	eq(#hits, 2)
	eq(reads, 5)
end)

test("roadRates: cars per minute per road (approaches joined by a shared phase), in phase order", function()
	local conns, states = fixture(false)
	local r = R.roadRates(conns, states, nil, { ["11>12"] = 60, ["12>11"] = 30, ["13>14"] = 18, ["11>13"] = 6 }, 180)
	eq(#r, 2)
	near(r[1], 32, 1e-9)
	near(r[2], 6, 1e-9)
	eq(R.roadRates(conns, states, nil, {}, 180), { 0, 0 })
end)

---------------------------------------------------------------------------
-- Cycle rule v3 and damping (Light plans A/B run 2, RETIME_PLAN.md "Cycle rule v3"): a replay of the six sl_auto
-- junctions' measured windows (retime_run2.lua, every op=plan line of session 2026-10-15_0509_light-plans-auto-863105)

local RUN2 = dofile(here .. "retime_run2.lua")

--- A crossroads reduced to what a logged plan line holds: approach 11 (phase 1) and 13 (phase 3) carry the logged
-- critical loads (one entry lane each: the load is per lane), 12 and 14 nothing; phases 2 and 4 all-red. durs: "a/b/c/d".
local function run2States(durs)
	local d = {}
	for v in tostring(durs):gmatch("%d+") do d[#d + 1] = tonumber(v) end
	local function st(locked, dur) return { locked = locked, duration = dur, minDuration = 1, canSkip = false } end
	return { st({ 2, 3 }, d[1]), st({ 0, 1, 2, 3 }, d[2]), st({ 0, 1 }, d[3]), st({ 0, 1, 2, 3 }, d[4]) }, d
end
local RUN2_CONNS = {
	{ segment0 = 11, lane0 = 0, segment1 = 12, lane1 = 0 }, { segment0 = 12, lane0 = 0, segment1 = 11, lane1 = 0 },
	{ segment0 = 13, lane0 = 0, segment1 = 14, lane1 = 0 }, { segment0 = 14, lane0 = 0, segment1 = 13, lane1 = 0 },
}

--- R.plan on a logged window with the phases `durs`; the saturation flow pinned to the one the log implies (y =
-- sum of the loads per hour / s), a standing queue on approach 11 where the log says cycle_reason=queues (its demand
-- taken off the passes, so the load stays as logged). opts: R.plan options on top.
local function run2Plan(row, durs, opts, prev)
	local states, d = run2States(durs)
	local cycle = 0
	for _, v in ipairs(d) do cycle = cycle + v end
	local s = (row.load[1] + row.load[2]) * 20 / row.y
	local o = { maxCycleStep = 20, satFlow = s, satMin = s, satMax = s }
	for k, v in pairs(opts or {}) do o[k] = v end
	local queue, q1 = {}, 0
	if row.reason == "queues" then
		q1 = 5
		queue["11>12"] = q1
	end
	local passes = { ["11>12"] = row.load[1] - 0.5 * q1 * 180 / cycle, ["13>14"] = row.load[2] }
	return R.plan({ conns = RUN2_CONNS, nCross = 0, states = states, passes = passes, queue = queue, windowS = 180,
		samples = row.samples, prev = prev }, o)
end

local function cycleOf(durs)
	local c = 0
	for v in tostring(durs):gmatch("%d+") do c = c + tonumber(v) end
	return c
end

test("replay run 2 (old rule): the fixture reproduces every logged decision of the six junctions", function()
	local n = 0
	for _, zid in ipairs({ "g1v", "g2v", "g3v", "g4v", "g5v", "g6v" }) do
		for i, row in ipairs(RUN2[zid]) do
			local p = run2Plan(row, row.old, { balanceRatio = 0, keepLoadedOnShrink = false })
			local tag = zid .. " window " .. i
			eq(p.reason, row.result, tag)
			local want = {}
			for v in row.new:gmatch("%d+") do want[#want + 1] = tonumber(v) end
			for k = 1, 4 do
				ok(math.abs(p.durations[k] - want[k]) <= 1, tag .. ": " .. R.listText(p.durations) .. " vs logged " .. row.new)
			end
			n = n + 1
		end
	end
	eq(n, 34)
end)

--- The new rule over a junction's logged windows: each window starts from the phases the previous decision left (the
-- measured loads as logged: a counterfactual, the traffic would have answered the new timing). Returns the rows
-- { old cycle, new cycle, reason, greens } and the text.
local function run2Chain(zid)
	local rows, durs, prev = {}, RUN2[zid][1].old, nil
	for _, row in ipairs(RUN2[zid]) do
		local p = run2Plan(row, durs, { smooth = 0.5, confirmLong = true }, prev)
		local before = durs
		if p.changed then durs = R.listText(p.durations) end
		prev = { load = p.load, long = p.long }
		local g = {}
		for v in durs:gmatch("%d+") do g[#g + 1] = v end
		local lg = {}
		for v in row.new:gmatch("%d+") do lg[#lg + 1] = v end
		rows[#rows + 1] = { from = cycleOf(before), to = cycleOf(durs), reason = p.cycleReason, share = p.share,
			text = string.format("%s>%d %s %s/%s (share %.2f) | logged %s %s/%s", cycleOf(before), cycleOf(durs),
				p.cycleReason, g[1], g[3], p.share, row.cycle, lg[1], lg[3]) }
	end
	return rows
end

local function reversals(rows)
	local n, dir = 0, 0
	for _, r in ipairs(rows) do
		local d = r.to > r.from and 1 or (r.to < r.from and -1 or 0)
		if d ~= 0 then
			if dir ~= 0 and d ~= dir then n = n + 1 end
			dir = d
		end
	end
	return n
end

local function loggedRows(zid)
	local rows = {}
	for _, row in ipairs(RUN2[zid]) do
		local a, b = row.cycle:match("(%d+)>(%d+)")
		rows[#rows + 1] = { from = tonumber(a), to = row.result == "write" and tonumber(b) or tonumber(a) }
	end
	return rows
end

test("replay run 2 (v3): balanced saturated junctions (g1v, g4v, g5v) stop at 75 s instead of 112-120 s", function()
	for _, zid in ipairs({ "g1v", "g4v", "g5v" }) do
		local rows = run2Chain(zid)
		local top, logTop = 0, 0
		for i, r in ipairs(rows) do
			print(zid .. " " .. i .. ": " .. r.text)
			if r.to > top then top = r.to end
			ok(r.share <= 0.625, zid .. " balanced in every window: " .. r.text)
		end
		for _, r in ipairs(loggedRows(zid)) do if r.to > logTop then logTop = r.to end end
		ok(logTop >= 112, zid .. " logged up to " .. logTop)
		ok(top <= 75 and top >= 72, zid .. ": at most max(75, current), reached: " .. top)
		-- the first window is saturated but unconfirmed: the cycle holds
		eq(rows[1].reason, "unconfirmed", zid)
		eq(rows[1].to, rows[1].from, zid)
	end
end)

test("replay run 2 (v3): unbalanced junctions keep Webster (g6v, g3v); the flip-flop of g2v is damped", function()
	-- g6v (3x3, E/W 600 vs N 150): logged 62 > 42 > 53 > 73 > 53 > 49 > 50; the one-window saturation (y 1.06) no
	-- longer lengthens
	local g6 = run2Chain("g6v")
	for i, r in ipairs(g6) do print("g6v " .. i .. ": " .. r.text) end
	-- the light first window shortens (Webster: 40 s; 42 before the 2026-10-15 shrink guard: 24/12; with it 49: 24/19,
	-- the side road's quarter of the loads keeps min(its current, the game's green for the fixture's 1 lane, 18.9 s))
	ok(g6[1].to >= 42 and g6[1].to <= 50 and g6[1].to < g6[1].from, "the light first window shortens: " .. g6[1].text)
	for _, r in ipairs(g6) do ok(r.to <= 55, "g6v never stretched: " .. r.text) end
	eq(reversals(loggedRows("g6v")) >= 2, true)
	ok(reversals(g6) <= 1, "g6v reversals")
	-- g3v (2x2 unbalanced, queues every window): still lengthens toward 120 s once confirmed, 20 s per write
	local g3 = run2Chain("g3v")
	for i, r in ipairs(g3) do print("g3v " .. i .. ": " .. r.text) end
	eq(g3[1].reason, "unconfirmed")
	ok(g3[#g3].to >= 100, "g3v long once confirmed: " .. g3[#g3].text)
	-- g2v (3x3 unbalanced): logged 62 > 62 > 82 > 62 > 82 > 62 > 50 > 63 (4 reversals)
	local g2 = run2Chain("g2v")
	for i, r in ipairs(g2) do print("g2v " .. i .. ": " .. r.text) end
	eq(reversals(loggedRows("g2v")), 4)
	ok(reversals(g2) <= 1, "g2v reversals: " .. reversals(g2))
	for _, r in ipairs(g2) do
		ok(r.to <= 66, "g2v never stretched by a one-window saturation: " .. r.text)
		ok(r.to >= 50, r.text)
	end
end)

test("plan v3: smoothing, confirmation and the balanced cap, one by one", function()
	local row = { load = { 60, 58 }, y = 1.2, reason = "saturated", samples = 60 }
	-- manual Re-time (no smoothing, no confirmation): balanced -> 75 s at once
	local m = run2Plan(row, "24/2/24/2", { maxCycleStep = false })
	eq({ m.cycleReason, m.cycleWanted }, { "balanced", 120 })
	ok(m.cycle >= 74 and m.cycle <= 76, tostring(m.cycle))
	-- a longer current cycle is kept, not shortened by the rule
	local k = run2Plan(row, "50/2/50/2", { maxCycleStep = false })
	eq(k.cycle, 104)
	eq(k.cycleReason, "balanced")
	-- unbalanced: Webster's long cycle, as before
	local u = run2Plan({ load = { 90, 30 }, y = 1.2, reason = "saturated", samples = 60 }, "24/2/24/2", { maxCycleStep = false })
	eq({ u.balanced, u.cycleReason, u.cycle }, { false, "saturated", 120 })
	-- step B: unconfirmed first, then confirmed by a second long window
	local a = run2Plan({ load = { 90, 30 }, y = 1.2, reason = "saturated", samples = 60 }, "24/2/24/2", { confirmLong = true })
	eq({ a.cycleReason, a.cycle, a.long }, { "unconfirmed", 52, true })
	local b = run2Plan({ load = { 90, 30 }, y = 1.2, reason = "saturated", samples = 60 }, "24/2/24/2",
		{ confirmLong = true, maxCycleStep = false },
		{ load = a.load, long = a.long })
	eq({ b.cycleReason, b.cycle }, { "saturated", 120 })
	-- smoothing: half of the previous window's loads
	local s = run2Plan({ load = { 40, 20 }, y = 0.5, reason = "webster", samples = 60 }, "24/2/24/2", { smooth = 0.5 },
		{ load = { [1] = 60, [3] = 20 } })
	eq({ s.loadRaw[1], s.load[1], s.load[3], s.smoothed }, { 40, 50, 20, true })
	-- a malformed previous window is ignored
	local z = run2Plan({ load = { 40, 20 }, y = 0.5, reason = "webster", samples = 60 }, "24/2/24/2", { smooth = 0.5 },
		{ load = { [1] = "x" } })
	eq(z.load[1], 40)
end)

test("pathAtTrack: a tracked driver is placed by the indices it was read at; new junctions read as they come in view", function()
	-- elements: 101 (node) 1 102 2 103 3 104 4 105 5 106 (0-based 0..10)
	local path = { 101, 1, 102, 2, 103, 3, 104, 4, 105, 5, 106 }
	local reads = 0
	local function get(i)
		reads = reads + 1
		return path[i + 1]
	end
	local set = { [103] = true, [106] = true }
	-- first sight at element 1, look 4: 103 ahead (i = 4)
	local hits, r, t, how = R.pathAtTrack(get, #path, 1, set, 4, nil)
	eq(how, "full")
	eq(#hits, 1)
	eq({ hits[1].node, hits[1].i, hits[1].state, hits[1].inSeg, hits[1].outSeg }, { 103, 4, "ahead", 2, 3 })
	eq(t.hi, 5)
	-- next sample at element 3: one read to confirm 103, then elements 6..7 (no member)
	reads = 0
	hits, r, t, how = R.pathAtTrack(get, #path, 3, set, 4, t)
	eq(how, "inc")
	eq(r, 3)
	eq(reads, 3)
	eq({ hits[1].node, hits[1].state }, { 103, "ahead" })
	-- at element 6: 103 behind (a pass, its movement known: 2 > 3), 106 comes in view at 10
	hits, r, t, how = R.pathAtTrack(get, #path, 6, set, 4, t)
	eq(how, "inc")
	eq(#hits, 2)
	eq({ hits[1].node, hits[1].state, hits[1].inSeg, hits[1].outSeg }, { 103, "behind", 2, 3 })
	eq({ hits[2].node, hits[2].state, hits[2].inSeg, hits[2].outSeg }, { 106, "ahead", 5, nil })
	eq(t.at[103], nil, "only nodes ahead are carried")
	-- a re-route (the path changed length): the full read with behind
	local path2 = { 101, 1, 102, 2, 103, 9, 109 }
	local function get2(i) return path2[i + 1] end
	hits, r, t, how = R.pathAtTrack(get2, #path2, 5, set, 4, { n = #path, hi = 7, at = { [103] = { i = 4, inS = 2, outS = 3 } } })
	eq(how, "full")
	eq({ hits[1].node, hits[1].state, hits[1].outSeg }, { 103, "behind", 9 })
	-- the same length but the node moved (re-route): the verify read fails -> full
	local path3 = { 101, 1, 102, 2, 107, 3, 103, 4, 105, 5, 106 }
	local function get3(i) return path3[i + 1] end
	hits, r, t, how = R.pathAtTrack(get3, #path3, 3, set, 4, { n = #path3, hi = 5, at = { [103] = { i = 4, inS = 2, outS = 3 } } })
	eq(how, "full")
	eq({ hits[1].node, hits[1].i, hits[1].state }, { 103, 6, "ahead" })
	-- the same answers as pathAtMulti on a fresh read
	local m = R.pathAtMulti(get3, #path3, 3, set, 4, false)
	eq(m[1].i, 6)
end)

---------------------------------------------------------------------------
-- Step B v4: queue snapshots (the automatic mode)

test("timingOf / arrivalOf: the red of each approach from the phases; the queue model gives the arrivals back", function()
	local conns, states = fixture(false)
	local tm = R.timingOf(conns, 4, states)
	near(tm.cycle, 71.4, 1e-9)
	near(tm.red[11], 71.4 - 23.7, 1e-9)
	near(tm.red[13], 71.4 - 23.7, 1e-9)
	eq({ tm.phases[11], tm.phases[12], tm.phases[13], tm.phases[14] }, { { 1 }, { 1 }, { 3 }, { 3 } })
	eq(tm.lanes[11], 2)
	-- 0.15 cars per s and lane (540 / h) at s = 0.5 (1800 / h): lambda' = 0.15 / 0.7; a fixed-time queue of
	-- lambda' x re^2 / (2 C) cars per lane (re = the red less the 5 s a car stands before it counts)
	local lp = 0.15 / (1 - 0.15 / 0.5)
	local re = tm.red[11] - 5
	local q = lp * re * re / (2 * tm.cycle) * 2
	near(R.arrivalOf(q, tm.cycle, tm.red[11]), 2 * lp, 1e-9)
	eq(R.arrivalOf(0, tm.cycle, tm.red[11]), 0)
	eq(R.arrivalOf(q, 0, 10), nil)
	eq(R.arrivalOf(1000, 60, 3), 10, "capped (a red shorter than the stand time: the least effective red)")
	-- planQueue turns lambda' back into lambda per lane: 540 cars per lane and hour
	local p = R.planQueue({ conns = conns, nCross = 4, states = states, arrive = { [11] = 2 * lp, [12] = 2 * lp, [13] = 0.05 },
		queue = { [11] = q, [12] = q, [13] = 0.3 }, snaps = 10 })
	near(p.arrive[11], 540, 1e-6)
	-- a curb turn freed all cycle gives its approach no phase (it never waits for one)
	local free = {}
	for i, st in ipairs(states) do
		local l = {}
		for _, x in ipairs(st.locked) do
			local c = conns[x + 1]
			if not (c ~= nil and c.segment0 == 11 and c.segment1 == 14) then l[#l + 1] = x end
		end
		free[i] = { locked = l, duration = st.duration }
	end
	eq(R.timingOf(conns, 4, free).phases[11], { 1 }, "its other movements still wait for phase 1")
end)

test("planQueue: few snapshots and quiet junctions keep; the queued road gets the green; the v3 cycle rule and damping; both sides", function()
	for _, mir in ipairs({ false, true }) do
		local tag = mir and "left" or "right"
		local conns, states = fixture(mir)
		local function plan(arrive, queue, snaps, opts, prev)
			return R.planQueue({ conns = conns, nCross = 4, states = states, arrive = arrive, queue = queue, snaps = snaps or 10,
				prev = prev }, opts)
		end
		local busy = { [11] = 0.43, [12] = 0.43, [13] = 0.03 }
		local busyQ = { [11] = 5.5, [12] = 5.5, [13] = 0.2 }
		eq(plan(busy, busyQ, 7).reason, "few_snapshots", tag)
		eq(plan({ [11] = 0.01 }, { [11] = 0.4, [13] = 0.3 }).reason, "quiet", tag)
		eq(plan({}, { [99] = 3 }).reason, "no_mapped_traffic", tag)
		-- the main road queues: its green longer, the pauses and the walk phase kept
		local p = plan(busy, busyQ)
		eq(p.reason, "write", tag)
		eq({ p.durations[2], p.durations[4], p.durations[5], p.durations[6] }, { 6, 6, 3, 9 }, tag)
		ok(p.durations[1] > p.durations[3] + 10, tag .. ": " .. R.listText(p.durations))
		eq(p.satSrc, "opt", tag)
		-- both roads saturated alike: balanced, the cycle stops at 75 s
		local b = plan({ [11] = 6, [12] = 6, [13] = 6, [14] = 6 }, { [11] = 14, [12] = 14, [13] = 14, [14] = 14 })
		eq({ b.balanced, b.cycleReason }, { true, "balanced" }, tag)
		ok(b.cycle >= 74 and b.cycle <= 76, tag .. ": " .. b.cycle)
		-- one road saturated, damping on (step B): the first long decision holds the cycle; confirmed by the next
		local damp = { confirmLong = true, maxCycleStep = 20, smooth = 0.5 }
		local u = plan({ [11] = 6, [12] = 6, [13] = 0.05 }, { [11] = 14, [12] = 14, [13] = 0.5 }, 10, damp)
		eq({ u.balanced, u.cycleReason }, { false, "unconfirmed" }, tag)
		local u2 = plan({ [11] = 6, [12] = 6, [13] = 0.05 }, { [11] = 14, [12] = 14, [13] = 0.5 }, 10, damp,
			{ load = u.load, long = u.long })
		ok(u2.cycle > u.oldCycle and u2.cycle <= u.oldCycle + 20.5 and u2.cycleStepped, tag .. ": " .. u2.cycle)
		-- hysteresis: a near-even queue at the game's even split changes nothing
		local f = plan({ [11] = 0.2, [12] = 0.2, [13] = 0.19, [14] = 0.19 }, { [11] = 2, [12] = 2, [13] = 2, [14] = 2 }, 10,
			{ hystAbs = 4, hystRel = 0.2 })
		eq(f.reason, "fits", tag .. ": " .. R.listText(f.durations or {}))
	end
end)

test("planQueue: an approach split over phases (a lead turn phase) counts in every phase it has green in", function()
	local conns, states = fixture(false)
	-- phase 1: 11 and 12 straight and curb turns; phase 3 the side road; a lead phase 7 for 11's far turn only
	local function phase(green, d)
		local l = {}
		for i, c in ipairs(conns) do
			if not green(c) then l[#l + 1] = i - 1 end
		end
		for k = 1, 4 do l[#l + 1] = #conns + k - 1 end
		return { locked = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	local split = {
		phase(function(c) return (c.segment0 == 11 or c.segment0 == 12) and not (c.segment0 == 11 and c.segment1 == 13) end, 24),
		phase(function() return false end, 4),
		phase(function(c) return c.segment0 == 13 or c.segment0 == 14 end, 20),
		phase(function() return false end, 4),
		phase(function(c) return c.segment0 == 11 and c.segment1 == 13 end, 8),
		phase(function() return false end, 3),
	}
	local tm = R.timingOf(conns, 4, split)
	eq(tm.phases[11], { 1, 5 })
	near(tm.red[11], 63 - 32, 1e-9)
	local p = R.planQueue({ conns = conns, nCross = 4, states = split, arrive = { [11] = 0.4, [12] = 0.1, [13] = 0.1, [14] = 0.1 },
		queue = { [11] = 4, [12] = 1, [13] = 1, [14] = 1 }, snaps = 10 })
	-- the lead phase's load is approach 11's whole flow (approach-level queues can't tell which movement waits)
	near(p.load[5], p.arrive[11], 1e-9)
	near(p.load[1], p.arrive[11], 1e-9, "11 is the critical approach of phase 1 too")
end)

--- The live city run's 3-lane crossroads (session live 2026-10-15, node 9500 and others: lanes k|s|sf on each of four
-- approaches, Free curb turn Always): the game's six phases 27.1/6/27.1/6/3/9 with every curb turn freed in every
-- phase (pauses and the pedestrian phase included), crosswalks green only in phase 5, pedNeed of a 6-lane road 25.5 s.
-- Approaches 11 / 12 (phase 1) and 13 / 14 (phase 3); right turns 11>14, 12>13, 13>11, 14>12.
local function liveCross()
	local right = { [11] = 14, [12] = 13, [13] = 11, [14] = 12 }
	local left = { [11] = 13, [12] = 14, [13] = 12, [14] = 11 }
	local opp = { [11] = 12, [12] = 11, [13] = 14, [14] = 13 }
	local conns = {}
	for _, a in ipairs({ 11, 12, 13, 14 }) do
		conns[#conns + 1] = C(a, 1, right[a], 1)
		conns[#conns + 1] = C(a, 2, opp[a], 2)
		conns[#conns + 1] = C(a, 3, opp[a], 3)
		conns[#conns + 1] = C(a, 3, left[a], 3)
	end
	local function phase(roads, cw, d)
		local l = {}
		for i, c in ipairs(conns) do
			local curb = right[c.segment0] == c.segment1
			if not curb and not roads[c.segment0] then l[#l + 1] = i - 1 end
		end
		if not cw then
			for k = 1, 4 do l[#l + 1] = #conns + k - 1 end
		end
		return { locked = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	local states = { phase({ [11] = true, [12] = true }, false, 27.1), phase({}, false, 6),
		phase({ [13] = true, [14] = true }, false, 27.1), phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) }
	return conns, states, R.pedNeed({ 11, 12, 13, 14 }, { [11] = 6, [12] = 6, [13] = 6, [14] = 6 })
end

-- the automatic runtime's options (sl_autoretime planOpts)
local AUTO_OPTS = { maxCycleStep = 20, smooth = 0.5, confirmLong = true, hystAbs = 4, hystRel = 0.2, minSnaps = 8,
	queueStand = 5 }

--- arrive (cars per s, all 3 lanes) for a logged flow (cars per lane per h; light: lambda ~ lambda')
local function lam(flow) return flow / 3600 * 3 end

-- logged cases: queue, flows per approach, the logged result
local LIVE_CASES = {
	{ node = 9500, queue = { [11] = 0, [12] = 0.1, [13] = 0.4, [14] = 0.5 }, arrive = { [12] = 11, [13] = 33, [14] = 43 },
		logged = "6/6/9/6/26/6" },
	{ node = 9118, queue = { [13] = 1.1, [14] = 0.5 }, arrive = { [13] = 94, [14] = 43 }, logged = "6/6/9/6/26/6" },
	{ node = 9106, queue = { [11] = 0.8, [12] = 0.8, [13] = 1.4, [14] = 0.3 },
		arrive = { [11] = 64, [12] = 64, [13] = 114, [14] = 22 }, logged = "6/6/9/6/26/6" },
	{ node = 9095, queue = { [11] = 0.4, [12] = 0.3, [13] = 0.4, [14] = 0.1 },
		arrive = { [11] = 33, [12] = 22, [13] = 33, [14] = 11 }, logged = "7/6/7/6/26/6" },
}

test("live city run 2026-10-15: freed curb turns no longer make the game's pauses and pedestrian phase vehicle phases; loaded greens keep the game's 27.1 s", function()
	local conns, states, ped = liveCross()
	near(ped[1], 25.5, 1e-9, "the crosswalk's need (the logged 26 s)")
	eq(R.kinds(#conns, 4, states), { "veh", "all_red", "veh", "all_red", "walk", "all_red" })
	-- the freed turns: green in all six phases
	local always = R.alwaysGreen(#conns, states)
	eq({ always[0], always[1], always[4], always[8], always[12] }, { true, nil, true, true, true })
	-- the old classification reproduces the logged writes (the fixture is faithful)
	local kinds0, ag0 = R.kinds, R.alwaysGreen
	R.alwaysGreen = function() return {} end
	local okOld, eOld = pcall(function()
		local c = LIVE_CASES[1]
		local a = {}
		for k, v in pairs(c.arrive) do a[k] = lam(v) end
		local opts = {}
		for k, v in pairs(AUTO_OPTS) do opts[k] = v end
		opts.keepLoadedOnShrink = false
		opts.idleCrosswalkCap = false
		opts.freedQueueOut = false
		local p = R.planQueue({ conns = conns, nCross = 4, states = states, arrive = a, queue = c.queue, snaps = 8,
			pedNeed = ped }, opts)
		eq(R.listText(p.durations), c.logged)
		eq(p.cycleReason, "min")
	end)
	R.kinds, R.alwaysGreen = kinds0, ag0
	if not okOld then error(eOld, 0) end
	for _, c in ipairs(LIVE_CASES) do
		local a = {}
		for k, v in pairs(c.arrive) do a[k] = lam(v) end
		local p = R.planQueue({ conns = conns, nCross = 4, states = states, arrive = a, queue = c.queue, snaps = 8,
			pedNeed = ped }, AUTO_OPTS)
		local d = p.durations or {}
		local tag = c.node .. ": " .. R.listText(d) .. " (logged " .. c.logged .. ")"
		-- the pauses and the pedestrian phase keep their seconds
		eq({ d[2], d[4], d[5], d[6] }, { 6, 6, 3, 9 }, tag)
		-- the busier road keeps at least the game's green; the other too with at least half an equal share (a quarter
		-- of the loads for two roads), else it may only shorten
		local busy = (p.load[1] or 0) >= (p.load[3] or 0) and 1 or 3
		local other = busy == 1 and 3 or 1
		ok(d[busy] >= 27.1, tag)
		ok(d[other] <= 28 and d[other] >= 6, tag)
		if (p.load[other] or 0) * 4 >= (p.load[1] or 0) + (p.load[3] or 0) then ok(d[other] >= 27.1, tag) end
		ok(d[1] + d[3] >= 34, tag)
		print(string.format("  %d: 27.1/6/27.1/6/3/9 -> %s (%s, cycle %s) | logged %s", c.node, R.listText(d), p.reason,
			tostring(p.cycle), c.logged))
	end
	-- the even light junctions (9106, 9095) fit: nothing written
	local c = LIVE_CASES[4]
	local a = {}
	for k, v in pairs(c.arrive) do a[k] = lam(v) end
	eq(R.planQueue({ conns = conns, nCross = 4, states = states, arrive = a, queue = c.queue, snaps = 8, pedNeed = ped },
		AUTO_OPTS).reason, "fits")
	-- the manual Re-time (R.plan) on the same phases: the same kinds, the walk phase kept
	local m = R.plan({ conns = conns, nCross = 4, states = states, windowS = 180, samples = 60, pedNeed = ped,
		passes = { ["11>12"] = 2, ["12>11"] = 1, ["13>14"] = 6, ["14>13"] = 8, ["13>11"] = 2 }, queue = {} })
	eq({ m.durations[2], m.durations[4], m.durations[5], m.durations[6] }, { 6, 6, 3, 9 }, R.listText(m.durations))
	ok(m.durations[3] >= 27.1, R.listText(m.durations))
end)

--- The manual Re-time's case of the same run (stdout 07:57:27Z, node 9594): main road 12084 (west) / 12085 (east), 3
-- lanes each way, phase 3; side roads 7448 (north) / 7559 (south), 2 lanes, phase 1; every curb turn (12084>7559,
-- 12085>7448, 7448>12084, 7559>12085) freed in all six phases (Free curb turn Always); crosswalks green in phase 5 only.
local function liveRetime()
	local right = { [12084] = 7559, [12085] = 7448, [7448] = 12084, [7559] = 12085 }
	local left = { [12084] = 7448, [12085] = 7559, [7448] = 12085, [7559] = 12084 }
	local opp = { [12084] = 12085, [12085] = 12084, [7448] = 7559, [7559] = 7448 }
	local nl = { [12084] = 3, [12085] = 3, [7448] = 2, [7559] = 2 }
	local conns = {}
	for _, a in ipairs({ 12084, 12085, 7448, 7559 }) do
		conns[#conns + 1] = C(a, 1, right[a], 1)
		for l = 2, nl[a] do conns[#conns + 1] = C(a, l, opp[a], l) end
		conns[#conns + 1] = C(a, nl[a], left[a], nl[a])
	end
	local function phase(roads, cw, d)
		local l = {}
		for i, c in ipairs(conns) do
			if right[c.segment0] ~= c.segment1 and not roads[c.segment0] then l[#l + 1] = i - 1 end
		end
		if not cw then
			for k = 1, 4 do l[#l + 1] = #conns + k - 1 end
		end
		return { locked = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	local states = { phase({ [7448] = true, [7559] = true }, false, 27.1), phase({}, false, 6),
		phase({ [12084] = true, [12085] = true }, false, 27.1), phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) }
	local ped = R.pedNeed({ 12084, 12085, 7448, 7559 }, { [12084] = 6, [12085] = 6, [7448] = 4, [7559] = 4 })
	-- RETIME op=measured: passes and mean queues as logged (12084>nil: a queued car whose exit was not read yet)
	local passes = { ["12084>12085"] = 10, ["12084>7559"] = 1, ["12085>12084"] = 15, ["7448>12084"] = 2, ["7559>12085"] = 27 }
	local queue = { ["12084>12085"] = 7.1, ["12084>nil"] = 4.5, ["12085>12084"] = 6.0, ["12085>7448"] = 20.1,
		["7448>12084"] = 1.8, ["7559>12085"] = 0.9 }
	return { conns = conns, nCross = 4, states = states, passes = passes, queue = queue, windowS = 182, samples = 56,
		pedNeed = ped }
end

test("live city run 2026-10-15, manual Re-time (node 9594): the freed curb turns' passes are 'always'; phase 5 got the crosswalk floor, not a queue's need", function()
	local input = liveRetime()
	-- the old classification reproduces the logged plan: kinds all veh, always=30, phase 5 = the 25.5 s crosswalk floor
	local ag0 = R.alwaysGreen
	R.alwaysGreen = function() return {} end
	local okOld, eOld = pcall(function()
		local p = R.plan(input, { keepLoadedOnShrink = false, idleCrosswalkCap = false, freedQueueOut = false })
		eq({ R.listText(p.kinds), p.always, p.total }, { "veh/veh/veh/veh/veh/veh", 30, 55 })
		eq(p.durations[5], 26, R.listText(p.durations))
		eq(p.load[5], 0, "no traffic in phase 5: its 26 s is the pedestrian floor")
		eq(p.cycleReason, "queues")
		print("  9594 old: " .. R.listText(p.durations) .. " (logged 16/6/60/6/26/6)")
	end)
	R.alwaysGreen = ag0
	if not okOld then error(eOld, 0) end
	-- now: the pauses and the walk phase keep their seconds; the freed turns stay 'always' (their 20-car queue on
	-- 12085>7448 is not a phase's: the turn is green all cycle)
	local p = R.plan(input)
	eq(R.listText(p.kinds), "veh/all_red/veh/all_red/walk/all_red")
	eq(p.always, 30)
	eq({ p.durations[2], p.durations[4], p.durations[5], p.durations[6] }, { 6, 6, 3, 9 }, R.listText(p.durations))
	ok(p.durations[3] >= 27.1, "the main road keeps at least the game's green: " .. R.listText(p.durations))
	print("  9594 new: " .. R.listText(p.durations) .. " (" .. p.reason .. ", " .. tostring(p.cycleReason) .. ")")
end)

test("a phase without traffic is not lengthened for a crosswalk; R.alwaysGreen needs a majority of at least two phases", function()
	eq(R.alwaysGreen(2, { { locked = {} } }), {}, "one phase: nothing is 'always'")
	eq(R.alwaysGreen(2, { { locked = {} }, { locked = { 1 } } }), { [0] = true })
	eq(R.alwaysGreen(2, { { locked = {} }, { locked = { 1 } }, { locked = { 0, 1 } }, { locked = { 0, 1 } } }), {},
		"green in 2 of 4: a lead turn, not freed")
	-- the live crossroads with the crosswalks green in the pauses' place: phase 2 a vehicle phase (a turn of road 11)
	-- with no traffic and the crosswalks green only there: kept at most at its current 6 s
	local conns, states, ped = liveCross()
	local l = {}
	for i, cn in ipairs(conns) do
		if not (cn.segment0 == 11 and cn.segment1 == 13) then l[#l + 1] = i - 1 end
	end
	states[2] = { locked = l, duration = 6, minDuration = 1.5, canSkip = true }
	for k = 1, 4 do
		local st = states[5].locked
		for i = #st, 1, -1 do
			if st[i] == #conns + k - 1 then table.remove(st, i) end
		end
	end
	states[5] = { locked = states[5].locked, duration = 3, minDuration = 1.5, canSkip = true }
	local p = R.planQueue({ conns = conns, nCross = 4, states = states, arrive = { [13] = lam(90), [14] = lam(40) },
		queue = { [13] = 1, [14] = 0.5 }, snaps = 8, pedNeed = ped }, AUTO_OPTS)
	ok(p.durations[2] <= 6, R.listText(p.durations))
end)

test("onCorridor / queueIndex / queueHits: the inbound half of each arm's strip; a car between two junctions counts at the one it queues for", function()
	local east = { ux = 1, uy = 0, len = 150, half = 12, box = 6, side = 1 }
	-- right-hand traffic: cars driving west into the junction keep to the north of the east arm's axis
	eq(R.onCorridor(east, 30, 3), true)
	eq(R.onCorridor(east, 30, 0), true, "on the axis: inbound")
	eq(R.onCorridor(east, 30, -3), false, "the outbound lanes")
	eq(R.onCorridor(east, 3, 2), false, "inside the junction")
	eq(R.onCorridor(east, 160, 2), false, "beyond the corridor")
	eq(R.onCorridor(east, 30, 13), false, "beside the road")
	eq(R.onCorridor(east, -30, 3), false, "the other side of the junction")
	local left = { ux = 1, uy = 0, len = 150, half = 12, box = 6, side = -1 }
	eq({ R.onCorridor(left, 30, 3), R.onCorridor(left, 30, -3) }, { false, true })
	local both = { ux = 1, uy = 0, len = 150, half = 12, box = 6, side = 0 }
	eq({ R.onCorridor(both, 30, 3), R.onCorridor(both, 30, -3) }, { true, true })
	-- J1 at (0, 0) with its east arm, J2 at (100, 0) with its west arm (len 100: the link between them)
	local j1 = { key = "j1", x = 0, y = 0, arms = { { seg = 1, ux = 1, uy = 0, len = 100, half = 12, box = 6, side = 1 } } }
	local j2 = { key = "j2", x = 100, y = 0, arms = { { seg = 2, ux = -1, uy = 0, len = 100, half = 12, box = 6, side = 1 },
		{ seg = 3, ux = 0, uy = 1, len = 150, half = 12, box = 6, side = 1 } } }
	local idx = R.queueIndex({ j1, j2 }, 200)
	local out = {}
	local n = R.queueHits(idx, 50, 3, out)
	eq(n, 1)
	eq({ out[1].j.key, out[1].arm.seg }, { "j1", 1 }, "heading west: queued for J1")
	n = R.queueHits(idx, 50, -3, out)
	eq({ n, out[1].j.key, out[1].arm.seg }, { 1, "j2", 2 }, "heading east: queued for J2")
	eq(R.queueHits(idx, 98, 60, out), 1, "J2's north arm (x = 98: west of its axis, inbound)")
	eq(R.queueHits(idx, -500, 0, out), 0)
	-- negative coordinates and -0 land in the same cells
	local j3 = { key = "j3", x = -0.0, y = -150, arms = { { seg = 4, ux = 0, uy = 1, len = 150, half = 12, box = 6, side = 0 } } }
	eq(R.queueHits(R.queueIndex({ j3 }, 200), 0, -100, out), 1)
end)

test("phasesEngineMade: the engine's phases of any shape (7-phase 1-lane T, flagged) pass; whole-second greens and odd shapes fail", function()
	local function rd(durs, flag, skip, minD)
		local st = {}
		for i, d in ipairs(durs) do
			st[i] = { duration = d, minDuration = minD or 1.5, canSkip = skip ~= false, lockedLanes = {} }
		end
		return { cfg = { userModifiedTrafficLightStates = flag }, tlc = { states = st } }
	end
	eq(R.phasesEngineMade(rd({ 23.70, 6, 23.70, 6, 3, 9 })), true, "the measured 6-phase default")
	eq(R.phasesEngineMade(rd({ 18.86, 6, 16.43, 6, 18.86, 3, 9 }, true)), true, "7 phases, flagged")
	eq(select(2, R.phasesEngineMade(rd({ 24, 6, 19, 6 }))), "whole_s", "Smart lights' own plan")
	eq(select(2, R.phasesEngineMade(rd({ 23.70, 6, 30, 6, 3, 9 }))), "whole_s", "one green set by hand")
	eq(select(2, R.phasesEngineMade(rd({ 6, 3, 9 }))), "whole_s", "pauses only")
	eq(select(2, R.phasesEngineMade(rd({ 23.70, 6 }, nil, false))), "shape", "canSkip off")
	eq(select(2, R.phasesEngineMade(rd({ 23.70, 6 }, nil, true, 4))), "shape", "minDuration changed")
	eq(select(2, R.phasesEngineMade(rd({ 23.70 }))), "shape", "one phase")
	local nine = {}
	for i = 1, 9 do nine[i] = 20.5 end
	eq(select(2, R.phasesEngineMade(rd(nine))), "shape", "more than 8")
	eq(select(2, R.phasesEngineMade(nil)), "no_phases")
end)
