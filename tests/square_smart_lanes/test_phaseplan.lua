-- square_smart_lanes: designed traffic light phase plans (sl_phaseplan.lua, pure): the axis plan (the only
-- Smart Lanes plan since 2026-10-16: no classic fallback, other shapes get no plan), the fan plan, whole lanes,
-- bus lanes, curb merges, crosswalks, timing (pedestrian minimum, cycle range, sliders), validation.

local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local C = Rules.conn

---------------------------------------------------------------------------
-- Helpers

--- Independent plan checks: every state conflict-free (P.phaseConflicts), every entry green
-- somewhere, sliders respected, and the pedestrian minimum: for a crosswalk green in phase p, the
-- guaranteed time from the start of p to the end of its run of green phases (p itself: duration, or
-- minDuration when it may skip; later phases: duration unless they may skip) >= need[k].
--- A phase's conflicts (P.phaseConflicts) less the merges with a kerb turn (step 4b, as "When safe":
-- class "kerb" in cls / M.cls, or listed in plan.kerb) and a bus-lane connection's conflicts with its
-- own approach (step 2b: plan.bus).
local function hardConflicts(M, plan, locked, cls, s)
	local c = cls or M.cls or {}
	local function kerb(x) return c[x + 1] == "kerb" or (plan.kerb ~= nil and plan.kerb[x] == true) end
	local function busOwn(x)
		return plan.bus ~= nil and x[3] ~= P.PED and x[2] < M.n and (plan.bus[x[1]] or plan.bus[x[2]]) and M.seg0[x[1]] == M.seg0[x[2]]
	end
	-- an axis plan: conflicts between connections of the state's road (plan.axis[s]: its approaches)
	local road = {}
	for _, seg in ipairs((s and plan.axis and plan.axis[s]) or {}) do road[seg] = true end
	local function inRoad(x)
		return x[3] ~= P.PED and x[2] < M.n and road[M.seg0[x[1]]] == true and road[M.seg0[x[2]]] == true
	end
	local out = {}
	for _, x in ipairs(P.phaseConflicts(M, locked) or {}) do
		if not (x[3] == P.MERGE and x[1] < M.n and x[2] < M.n and (kerb(x[1]) or kerb(x[2]))) and not busOwn(x) and not inRoad(x) then
			out[#out + 1] = x
		end
	end
	return out
end

--- Whole lanes (independent of PP): in every state the connections of one entry lane (segment0,
-- lane0) are all green or all red. Returns the first part-green lane as "state:seg:lane", or nil.
local function partLane(plan, conns)
	for s, st in ipairs(plan.states) do
		local g = {}
		for _, x in ipairs(st.green) do g[x] = true end
		local on = {}
		for i, c in ipairs(conns) do
			local key = c.segment0 .. ":" .. c.lane0
			local v = g[i - 1] == true
			if on[key] == nil then on[key] = v elseif on[key] ~= v then return s .. ":" .. key end
		end
	end
	return nil
end

local function checkPlan(M, plan, tag, need, cls)
	ok(plan ~= nil, tag .. ": a plan")
	if plan == nil then return end
	-- an axis plan validates with the explicit flag (its within-road conflicts), and only with it when it has any
	local okV, why = PP.validatePlan(M, plan, M.n, M.nCross, plan.axis ~= nil and { axis = true } or nil)
	ok(okV, tag .. ": validates (" .. tostring(why) .. ")")
	local np = #plan.states
	local seen = {}
	for s, st in ipairs(plan.states) do
		eq(hardConflicts(M, plan, st.locked, cls, s), {}, tag .. ": phase " .. s .. " conflict-free (kerb merges, bus own approach, axis road allowed)")
		eq(#st.locked + #st.green, M.size, tag .. ": locked + green = all")
		for _, x in ipairs(st.green) do seen[x] = true end
		ok(st.duration >= 1 and st.duration <= 60 and st.duration == math.floor(st.duration), tag .. ": duration " .. st.duration)
		ok(st.minDuration >= 0 and st.minDuration <= st.duration and st.minDuration <= 30, tag .. ": minDuration")
		if not st.canSkip then eq(st.minDuration, 0, tag .. ": minDuration only with canSkip") end
	end
	for x = 0, M.size - 1 do ok(seen[x], tag .. ": entry " .. x .. " green somewhere") end
	-- a non-turn connection or a crosswalk is green in a phase that never skips (not with skip "all":
	-- every phase with a vehicle green may skip; the all-red clearances and the axis plan's pedestrian
	-- phases never do)
	local allSkip = true
	for _, st in ipairs(plan.states) do
		local veh = false
		for _, x in ipairs(st.green) do if x < M.n then veh = true end end
		if not st.canSkip and veh then allSkip = false end
	end
	cls = cls or M.cls
	if cls and next(cls) ~= nil and not allSkip then
		for x = 0, M.size - 1 do
			if x >= M.n or (cls[x + 1] ~= "far" and cls[x + 1] ~= "u_turn") then
				local fixed = false
				for _, st in ipairs(plan.states) do
					if not st.canSkip then
						for _, g in ipairs(st.green) do if g == x then fixed = true end end
					end
				end
				ok(fixed, tag .. ": entry " .. x .. " green in a phase that never skips")
			end
		end
	end
	for k = 1, M.nCross do
		local x = M.n + k - 1
		local on = {}
		local count = 0
		for s, st in ipairs(plan.states) do
			for _, g in ipairs(st.green) do if g == x then on[s] = true end end
			if on[s] then count = count + 1 end
		end
		if plan.pattern == "axis" then
			-- the axis plan: crosswalks only in its pedestrian phases (every vehicle red, skippable after the
			-- 3 s clearance (rev 8, user 2026-10-14), opts.pedPhase s: the player's 6 s, not the crossing time)
			for s = 1, np do
				if on[s] then
					local st = plan.states[s]
					eq({ st.tag, st.canSkip, st.minDuration }, { "ped", true, math.min(3, st.duration) },
						tag .. ": crosswalk " .. k .. " only in a pedestrian phase (" .. s .. ")")
					for _, g in ipairs(st.green) do ok(g >= M.n, tag .. ": pedestrian phase " .. s .. " has every vehicle red") end
				end
			end
		elseif count < np then
			for s = 1, np do
				if on[s] then
					local st = plan.states[s]
					-- skip "all": the crossing time is in the green (a phase does not end early under
					-- pedestrians); else a skippable phase guarantees only its minDuration
					local t = (st.canSkip and not allSkip) and st.minDuration or st.duration
					local q = s % np + 1
					while on[q] and q ~= s do
						if allSkip or not plan.states[q].canSkip then t = t + plan.states[q].duration end
						q = q % np + 1
					end
					-- an all-red clearance right after the run clears the crossing too
					if q ~= s and #plan.states[q].green == 0 then t = t + plan.states[q].duration end
					ok(t >= (need and need[k] or 0) - 1e-9, string.format("%s: crosswalk %d in phase %d: %.1f s >= %.1f s",
						tag, k, s, t, need and need[k] or 0))
				end
			end
		end
	end
end

--- Green connections of a state as a set.
local function greenSet(st)
	local set = {}
	for _, x in ipairs(st.green) do set[x] = true end
	return set
end

--- Which seed group every phase carries (by the conns' approach + class), for readable checks.
local function phaseText(plan, conns, cls)
	local out = {}
	for s, st in ipairs(plan.states) do
		local g = {}
		for _, x in ipairs(st.green) do
			local c = conns[x + 1]
			if c then g[#g + 1] = c.segment0 .. ":" .. c.lane0 .. ">" .. c.segment1 .. ":" .. c.lane1 .. "/" .. tostring(cls[x + 1])
			else g[#g + 1] = "w" .. (x - #conns + 1) end
		end
		out[#out + 1] = string.format("%d %s %ds%s: %s", s, st.tag, st.duration,
			st.canSkip and (" skip>=" .. st.minDuration) or "", table.concat(g, " "))
	end
	return out
end

--- Crossroads at node 1 (as test_phases.lua): 11 west, 12 east (main), 13 north, 14 south (none
-- when t). Returns view, world.
local function crossing(t, mirror_, main, side)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	local segs = { [11] = { 1, 2, main or F.TPL.medium }, [12] = { 1, 3, main or F.TPL.medium }, [13] = { 1, 4, side or F.TPL.medium } }
	if not t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, side or F.TPL.medium }
	end
	local world = F.build(nodes, segs, mirror_)
	local v = Slip.classify(world, 1)
	assert(v.case == "X", "crossing fixture is case X")
	return v, world
end

--- Map + info of a fixture: conns "rule" (Smart Lanes) or "default" (the game's model), one
-- crosswalk per arm (segment ids in node order) unless cws is given.
local function fixture(t, mirror_, main, side, which, cws)
	local v, world = crossing(t, mirror_, main, side)
	local conns = which == "default" and Cross.defaultConns(v) or Slip.roadConns(v)
	if cws == nil then
		cws = {}
		for _, sid in ipairs(world.node(1).segs) do cws[#cws + 1] = sid end
	end
	local info = PP.infoFromView(v, world, 1, conns)
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
	return M, info, conns, cws
end

--- Pedestrian need per crosswalk for a fixture (independent of PP): crossed road's driving lanes x
-- 4.5 m / 1.2 m/s + 3 s; an unmapped crosswalk takes the widest arm.
local function pedNeed(info, cws)
	local widest = 0
	for _, n in pairs(info.roadLanes) do widest = math.max(widest, n) end
	local out = {}
	for k, cw in ipairs(cws) do out[k] = (info.roadLanes[cw] or widest) * 4.5 / 1.2 + 3 end
	return out
end

--- Synthetic crossroads, right-hand traffic: arms 1..4 at a0 + 0/90/180/270 deg. spec[seg] = { out =
-- outgoing lanes, lanes = { "RS", "SL", ... } kerb lane first } (R kerb turn to the next arm
-- counter-clockwise, S straight, L far turn). Lane indices seen from the node: 0 sidewalk, 1..ni
-- incoming (1 = kerb), ni+1..ni+no outgoing (ni+no = kerb). R enters the exit's kerb lane, L its far
-- lane, the k-th straight lane from the kerb the k-th lane from the kerb (after the kerb lane when the
-- exit's road also has a kerb turn into it... kept simple: k-th from the kerb). Returns conns, arms.
local function synth(spec, a0)
	a0 = a0 or 0
	local arms = {}
	for s = 1, 4 do arms[s] = { seg = s, angle = a0 + (s - 1) * 90 } end
	local conns = {}
	local function ni(s) return spec[s] and #spec[s].lanes or 0 end
	local function no(s) return spec[s] and spec[s].out or 0 end
	for s = 1, 4 do
		if spec[s] then
			local k = 0
			for li, lane in ipairs(spec[s].lanes) do
				local hasS = lane:find("S", 1, true) ~= nil
				if hasS then k = k + 1 end
				for m in lane:gmatch(".") do
					local e = (m == "R" and s % 4 + 1) or (m == "S" and (s + 1) % 4 + 1) or ((s + 2) % 4 + 1)
					if no(e) > 0 then
						local lane1
						if m == "R" then lane1 = ni(e) + no(e)
						elseif m == "L" then lane1 = ni(e) + 1
						else lane1 = math.max(ni(e) + 1, ni(e) + no(e) - k + 1) end
						conns[#conns + 1] = C(s, li, e, lane1)
					end
				end
			end
		end
	end
	return conns, arms
end

local function synthMap(spec, opts)
	opts = opts or {}
	local conns, arms = synth(spec, opts.a0)
	local info = { conns = conns, arms = arms, side = "right", laneDemand = opts.laneDemand }
	local M = assert(P.build({ conns = conns, arms = arms, crosswalks = opts.cws, cls = PP.classesFromArms(conns, arms, "right") }))
	return M, info, conns
end

---------------------------------------------------------------------------
-- Shapes: the axis plan or none (no classic fallback, PLAN.md "No classic fallback", user 2026-10-16)

--- Tags of a plan's states.
local function tagsOf(plan)
	local out = {}
	for s, st in ipairs(plan.states) do out[s] = st.tag end
	return out
end

--- The conflicts of state s that lie outside its road (an axis plan's plan.axis[s]): every conflict
-- P.phaseConflicts lists, less those between two connections of the road's approaches.
local function outsideRoad(M, plan, s)
	local road = {}
	for _, seg in ipairs((plan.axis and plan.axis[s]) or {}) do road[seg] = true end
	local out = {}
	for _, x in ipairs(P.phaseConflicts(M, plan.states[s].locked) or {}) do
		local inRoad = x[3] ~= P.PED and x[2] < M.n and road[M.seg0[x[1]]] == true and road[M.seg0[x[2]]] == true
		if not inRoad then out[#out + 1] = x end
	end
	return out
end

test("no classic fallback: x4 within 180 +- 45 deg and t3 get the axis plan; other shapes (skewed beyond, no main road, 5 arms) no plan (no_axis_shape); the fan plan still plans them", function()
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	-- node 32350 (user 2026-10-17 log): A / C 16 deg off a road, B / D 52 deg: no axis plan; D at 282 deg (44 deg): one
	for _, cs in ipairs({ { { 0, 70, 180, 250 }, "x4_axis" }, { { 0, 90, 200, 300 }, "x4_axis" },
		{ { 0, 90, 180, 330 }, nil }, { { 20.1, 146.2, 184.0, 274.0 }, nil }, { { 20.1, 146.2, 184.0, 282.0 }, "x4_axis" } }) do
		local conns, arms = synth(spec)
		-- classes from the square layout, the arm angles skewed
		local cls = PP.classesFromArms(conns, arms, "right")
		for s = 1, 4 do arms[s].angle = cs[1][s] end
		local M = assert(P.build({ conns = conns, arms = arms, cls = cls }))
		local tag = "skew " .. table.concat(cs[1], "/")
		local plan, why = PP.plan(M, { conns = conns, arms = arms, cls = cls })
		if cs[2] == nil then
			eq({ plan, why }, { nil, "no_axis_shape" }, tag)
			eq(PP.patternName(plan), "none", tag)
		else
			checkPlan(M, plan, tag, nil, cls)
			eq(plan.kind, cs[2], tag)
			eq(PP.patternName(plan), "axis", tag)
		end
	end
	-- a Y: three arms 120 deg apart, no straight movement and no pair within 45 deg of 180: no main road
	local yArms = { { seg = 1, angle = 0 }, { seg = 2, angle = 120 }, { seg = 3, angle = 240 } }
	local yConns = { C(1, 1, 2, 2), C(1, 1, 3, 2), C(2, 1, 3, 2), C(2, 1, 1, 2), C(3, 1, 1, 2), C(3, 1, 2, 2) }
	local yCls = PP.classesFromArms(yConns, yArms, "right")
	for _, c in ipairs(yCls) do ok(c ~= "straight", "Y: no straight " .. tostring(c)) end
	local MY = assert(P.build({ conns = yConns, arms = yArms, cls = yCls }))
	eq({ PP.plan(MY, { conns = yConns, arms = yArms, side = "right" }) }, { nil, "no_axis_shape" }, "Y")
	-- 5 arms
	local arms, conns = {}, {}
	for k = 1, 5 do arms[k] = { seg = 10 + k, angle = 72 * (k - 1) + 5 } end
	for a = 1, 5 do
		for b = 1, 5 do
			if a ~= b then conns[#conns + 1] = C(10 + a, 1, 10 + b, 2) end
		end
	end
	local cws = { 11, 12, 13, 14, 15 }
	local M = assert(P.build({ conns = conns, arms = arms, crosswalks = cws }))
	local info = { conns = conns, arms = arms, side = "right", roadLanes = { [11] = 2, [12] = 2, [13] = 2, [14] = 2, [15] = 2 } }
	eq({ PP.plan(M, info) }, { nil, "no_axis_shape" }, "5-way")
	-- the fan plan (sl_fan zones) has no shape rule: one phase per approach, bounded by maxPhases
	local fan = assert(PP.plan(M, info, { fan = true }))
	eq(fan.kind, "fan")
	eq(PP.patternName(fan), "fan")
	ok(PP.validatePlan(M, fan, M.n, M.nCross, { fan = true }), "5-way fan validates")
	ok(#fan.states <= PP.MAX_STATES, "phases " .. #fan.states)
	eq({ PP.plan(M, info, { fan = true, maxPhases = 2 }) }, { nil, "too_many_phases" })
	-- the option of the classic patterns is gone: pattern = "classic" plans the axis plan
	local M2, info2 = fixture(false, false, nil, nil, "rule")
	eq(PP.plan(M2, info2, { pattern = "classic" }).kind, "x4_axis")
	eq(PP.DEFAULTS.pattern, nil)
	eq(PP.score, nil)
end)

test("LHT mirrors: the same kind, phase count, durations and green counts", function()
	for _, fx in ipairs({ { false, nil, nil }, { false, F.TPL.large, F.TPL.large }, { false, F.TPL.large, F.TPL.medium },
		{ true, nil, nil }, { true, F.TPL.large, F.TPL.large } }) do
		for _, which in ipairs({ "rule", "default" }) do
			local function summary(mir)
				local M, info = fixture(fx[1], mir, fx[2], fx[3], which)
				local plan = assert(PP.plan(M, info))
				local out = { plan.kind, plan.cycle }
				for _, st in ipairs(plan.states) do
					out[#out + 1] = st.tag .. "/" .. st.duration .. "/" .. #st.green .. "/" .. tostring(st.canSkip) .. "/" .. st.minDuration
				end
				return out
			end
			eq(summary(true), summary(false), "mirror " .. tostring(fx[1]) .. " " .. which)
		end
	end
end)

test("one-way arms (in only, out only): valid, every movement green, the in-only arm alone on its road", function()
	-- east 1 / west 3 two-way, north 2 one-way into the node, south 4 one-way out (test_phases fixture)
	local conns = {
		C(1, 1, 3, 4), C(1, 2, 3, 3), C(3, 1, 1, 4), C(3, 2, 1, 3),
		C(2, 1, 3, 4), C(2, 2, 1, 3), C(3, 1, 4, 2), C(1, 2, 4, 1),
	}
	local arms = { { seg = 1, angle = 0 }, { seg = 2, angle = 90 }, { seg = 3, angle = 180 }, { seg = 4, angle = 270 } }
	local cls = PP.classesFromArms(conns, arms, "right")
	eq(cls, { "straight", "straight", "straight", "straight", "kerb", "far", "kerb", "far" })
	local M = assert(P.build({ conns = conns, arms = arms, crosswalks = { 2, 4 }, cls = cls }))
	local plan = PP.plan(M, { conns = conns, arms = arms, side = "right" })
	checkPlan(M, plan, "one-way")
	eq(plan.kind, "x4_axis")
	local roads = {}
	for s = 1, #plan.states do
		if plan.axis[s] ~= nil then roads[#roads + 1] = table.concat(plan.axis[s], "-") end
	end
	eq(roads, { "1-3", "2" }, "the two-way road first, the in-only arm alone")
	print("one-way: " .. PP.planText(plan, #conns) .. " | " .. plan.why)
end)

test("tram crossing: a tram connection on a road lane pair is green exactly with its road twin", function()
	local v, world = crossing(false, false, F.TPL.small_tram, F.TPL.medium)
	local road = Slip.roadConns(v)
	local conns = {}
	for _, c in ipairs(road) do conns[#conns + 1] = c end
	local twin = {}
	for i, c in ipairs(road) do
		if c.segment0 == 11 or c.segment0 == 12 then
			conns[#conns + 1] = C(c.segment0, c.lane0, c.segment1, c.lane1, false, true)
			twin[#conns] = i
		end
	end
	local info = PP.infoFromView(v, world, 1, conns)
	-- the tram twins have the class of their road connection
	for t, i in pairs(twin) do eq(info.cls[t], info.cls[i]) end
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = { 11, 12, 13, 14 }, cls = info.cls }))
	local plan = PP.plan(M, info)
	checkPlan(M, plan, "tram", pedNeed(info, { 11, 12, 13, 14 }))
	for t, i in pairs(twin) do
		for s, st in ipairs(plan.states) do
			local g = greenSet(st)
			eq(g[t - 1] == true, g[i - 1] == true, "tram twin " .. t .. " phase " .. s)
		end
	end
end)

test("unknown crosswalks: green in the axis plan's pedestrian phases like the others; no crossing data: the default 14 m", function()
	local M, info, conns = fixture(true, false, nil, nil, "rule", { 13, 999 })
	ok(M.cwSeg[2] == false)
	local plan = PP.plan(M, info)
	checkPlan(M, plan, "unknown cw")
	eq(tagsOf(plan), { "axis", "ped", "axis", "ped" })
	for _, s in ipairs({ 2, 4 }) do eq(plan.states[s].green, { #conns, #conns + 1 }, "only the crosswalks green") end
	-- no crosswalk data at all: no crossing length, the default 14 m
	near(PP.pedMin(M, { o = PP.options(), info = {}, arms = {} }, 1), 14 / 1.2 + 3, 1e-9)
end)

test("fan plans: an all-red after every phase (allRed seconds), an unplaceable crosswalk gets a walk phase or no plan (refuse)", function()
	local M, info, conns = fixture(true, false, nil, nil, "rule", { 13, 999 })
	local plan = assert(PP.plan(M, info, { fan = true, allRed = 2 }))
	ok(PP.validatePlan(M, plan, M.n, M.nCross, { fan = true }), "fan validates")
	ok(#plan.states % 2 == 0)
	for s = 2, #plan.states, 2 do
		eq(plan.states[s].tag, "all_red")
		eq(#plan.states[s].green, 0)
		eq(plan.states[s].duration, 2)
		eq(plan.states[s].canSkip, false)
	end
	-- the unknown crosswalk conflicts with every connection: a walk phase with every vehicle red
	local walk = nil
	for _, st in ipairs(plan.states) do if st.tag == "walk" then walk = st end end
	ok(walk ~= nil, "a walk phase")
	for _, x in ipairs(walk.green) do ok(x >= #conns, "walk phase: only crosswalks green") end
	eq({ PP.plan(M, info, { fan = true, unknownCrosswalk = "refuse" }) }, { nil, "crosswalk_unplaced" })
end)

---------------------------------------------------------------------------
-- Timing

test("timing: whole seconds, the game's green floor, cycle range, skip minimum in 0.5 s steps", function()
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	local M2, info2, conns2 = synthMap(spec)
	local p2 = PP.plan(M2, info2)
	checkPlan(M2, p2, "3x3 far lanes")
	ok(p2.cycle >= 40 and p2.cycle <= 90, "cycle " .. p2.cycle)
	eq(p2.warnings, {})
	-- a road phase at least the game's 3-lane green (27.1 s), the target 15 + 4 x 3 = 27 s
	eq({ p2.states[1].duration, p2.states[3].duration }, { 28, 28 })
	-- without the floor a fixed cycle scales the greens (the pedestrian / clearance phases keep their length)
	local p3 = PP.plan(M2, info2, { cycleMin = 70, cycleMax = 70 })
	eq(p3.cycle, 70)
	-- a cycle cap the floors can't meet: kept over it, with a warning
	local p4 = PP.plan(M2, info2, { cycleMin = 10, cycleMax = 10 })
	for _, s in ipairs({ 1, 3 }) do ok(p4.states[s].duration >= 28, "the game's green floor " .. p4.states[s].duration) end
	eq(p4.warnings, { "cycle_over_max" })
	local p5 = PP.plan(M2, info2, { skipMinGreen = 3.3 })
	eq(p5.states[1].minDuration, 3.5, "rounded up to 0.5 s")
	local p6 = PP.plan(M2, info2, { skip = "none" })
	for _, st in ipairs(p6.states) do eq(st.canSkip, false) end
	ok(PP.validatePlan(M2, p6, M2.n, M2.nCross, { axis = true }))
	print("3x3 far lanes: " .. PP.planText(p2, #conns2))
end)

test("timing: green targets 15 s + 4 s per lane (19 / 23 / 27 s), at least the game's green (19 / 24 / 28 s)", function()
	for lanes, want in pairs({ [1] = { 19, 19 }, [2] = { 23, 24 }, [3] = { 27, 28 } }) do
		local spec = {}
		local list = {}
		for k = 1, lanes do list[k] = "S" end
		for s = 1, 4 do spec[s] = { out = lanes, lanes = list } end
		local M, info = synthMap(spec)
		local raw = PP.plan(M, info, { gameGreenFloor = false })
		checkPlan(M, raw, "plain " .. lanes)
		eq(raw.kind, "x4_axis")
		-- no crosswalks: an all-red clearance between the roads, no road width known: the default 3 s
		eq(tagsOf(raw), { "axis", "all_red", "axis", "all_red" })
		eq(raw.states[2].duration, 3)
		eq({ raw.states[1].duration, raw.states[3].duration }, { want[1], want[1] }, lanes .. " lanes")
		local plan = PP.plan(M, info)
		eq({ plan.states[1].duration, plan.states[3].duration }, { want[2], want[2] }, lanes .. " lanes, floored")
	end
end)

test("timing: the clearance without crosswalks is clamp(round(width / 8 m/s), 2, 4) s", function()
	local M, info = fixture(true, false, nil, nil, "rule", {})
	local function clear(i)
		local plan = assert(PP.plan(M, i))
		eq(plan.states[2].tag, "all_red")
		return plan.states[2].duration
	end
	eq(clear(info), 2)
	local wide = { conns = info.conns, arms = info.arms, cls = info.cls, side = info.side, crossLen = { [11] = 50, [12] = 50, [13] = 50 } }
	eq(clear(wide), 4, "50 m / 8 = 6.25 -> 4 s (max)")
	local narrow = { conns = info.conns, arms = info.arms, cls = info.cls, side = info.side, crossLen = { [11] = 6, [12] = 6, [13] = 6 } }
	eq(clear(narrow), 2, "6 m / 8 = 0.75 -> 2 s (min)")
	local none = { conns = info.conns, arms = info.arms, cls = info.cls, side = info.side }
	eq(clear(none), 3, "no road width known: 3 s")
end)

---------------------------------------------------------------------------
-- Validation, determinism, bounds

test("validatePlan catches every defect class", function()
	local M, info = fixture(true, false, nil, nil, "rule")
	local plan = assert(PP.plan(M, info))
	local AX = { axis = true }
	ok(PP.validatePlan(M, plan, M.n, M.nCross, AX))
	local function copy(p)
		local out = { states = {}, kerb = p.kerb, bus = p.bus, axis = {} }
		for s, list in pairs(p.axis or {}) do
			local l = {}
			for i, seg in ipairs(list) do l[i] = seg end
			out.axis[s] = l
		end
		for s, st in ipairs(p.states) do
			local l = {}
			for i, x in ipairs(st.locked) do l[i] = x end
			out.states[s] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
		end
		return out
	end
	local function bad(fn, want, opts)
		local p = copy(plan)
		fn(p)
		local okV, why = PP.validatePlan(M, p, M.n, M.nCross, opts or AX)
		eq(okV, false, want)
		ok(tostring(why):find(want, 1, true) == 1, want .. " -> " .. tostring(why))
	end
	bad(function(p) table.insert(p.states[1].locked, M.size) end, "index:1")
	bad(function(p) table.insert(p.states[1].locked, -1) end, "index:1")
	bad(function(p) table.insert(p.states[1].locked, 0.5) end, "index:1")
	bad(function(p) local l = p.states[1].locked table.insert(l, l[1]) end, "duplicate:1")
	bad(function(p) p.states[1].locked = {} end, "conflict:1:")
	bad(function(p) p.states[2].duration = 0 end, "duration:2")
	bad(function(p) p.states[2].duration = 61 end, "duration:2")
	bad(function(p) p.states[2].duration = 7.5 end, "duration:2")
	bad(function(p) p.states[2].canSkip, p.states[2].minDuration = true, 0.3 end, "min_duration:2")
	bad(function(p) p.states[2].minDuration = p.states[2].duration + 1 end, "min_duration:2")
	bad(function(p) p.states[1].canSkip = nil end, "can_skip:1")
	-- every phase skippable: all_skip unless skip "all" (the default)
	bad(function() end, "all_skip", { axis = true, skip = "turns" })
	-- a skippable clearance (every vehicle red) with no minDuration could end at once: refused
	bad(function(p)
		for _, st in ipairs(p.states) do
			local red = {}
			for _, x in ipairs(st.locked) do red[x] = true end
			local veh = false
			for x = 0, M.n - 1 do if not red[x] then veh = true end end
			if not veh then st.canSkip, st.minDuration = true, 0 end
		end
	end, "clear_min:")
	bad(function(p) p.states = {} end, "no_states")
	-- the road's conflicts only with the explicit flag and the plan's road list
	bad(function() end, "conflict:", {})
	bad(function(p) p.axis = nil end, "conflict:")
	bad(function(p) p.axis[1] = { 11, 13 } end, "axis_road:1")
	-- a connection red everywhere (its whole lane: else the lane check comes first)
	bad(function(p)
		for _, st in ipairs(p.states) do
			local has = {}
			for _, x in ipairs(st.locked) do has[x] = true end
			for x = 0, M.n - 1 do
				if M.seg0[x] == M.seg0[0] and M.lane0[x] == M.lane0[0] and not has[x] then table.insert(st.locked, x) end
			end
		end
	end, "never_green:0")
	-- part of a lane green (whole lanes, 2026-10-14): a shared lane's straight green, its far turn red
	local shared = nil
	for x = 0, M.n - 1 do
		for y = 0, M.n - 1 do
			if x ~= y and M.seg0[x] == M.seg0[y] and M.lane0[x] == M.lane0[y] and M.cls[x + 1] == "far" then shared = shared or { x, y } end
		end
	end
	ok(shared ~= nil, "fixture: a shared lane with a far turn")
	bad(function(p)
		for _, st in ipairs(p.states) do
			local red = {}
			for _, l in ipairs(st.locked) do red[l] = true end
			if not red[shared[2]] then
				-- lock only the far turn where its lane mate is green
				if not red[shared[1]] then table.insert(st.locked, shared[1]) end
			end
		end
	end, "part_lane:")
	-- a crosswalk red everywhere
	bad(function(p)
		local x = M.n
		for _, st in ipairs(p.states) do
			local has = false
			for _, y in ipairs(st.locked) do if y == x then has = true end end
			if not has then table.insert(st.locked, x) end
		end
	end, "crosswalk_never_green:" .. M.n)
	eq({ PP.validatePlan(M, plan, M.n + 1, M.nCross) }, { false, "size_mismatch" })
	eq({ PP.validatePlan(M, nil, M.n, M.nCross) }, { false, "no_plan" })
	local many = { states = {} }
	for s = 1, PP.MAX_STATES + 1 do many.states[s] = plan.states[1] end
	eq({ PP.validatePlan(M, many, M.n, M.nCross) }, { false, "too_many_states" })
end)

test("determinism: the same input gives the same plan; rotation of the whole junction does not change it", function()
	local M, info = fixture(false, false, nil, nil, "rule")
	local a, b = PP.plan(M, info), PP.plan(M, info)
	eq(a, b)
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	local M1, i1 = synthMap(spec, { a0 = 0 })
	local M2, i2 = synthMap(spec, { a0 = 123 })
	local p1, p2 = PP.plan(M1, i1), PP.plan(M2, i2)
	eq(p1.states, p2.states)
	eq(p1.kind, p2.kind)
end)

test("bounds and bad input: nil map, mismatched connections, empty junction", function()
	local M, info = fixture(true, false, nil, nil, "rule")
	eq({ PP.plan(nil, info) }, { nil, "no_map" })
	local short = { conns = { info.conns[1] }, arms = info.arms }
	eq({ PP.plan(M, short) }, { nil, "conns_mismatch" })
	local E = assert(P.build({}))
	eq({ PP.plan(E, { conns = {} }) }, { nil, "no_conns" })
	-- every plan stays within the sliders and the state bound
	for _, fx in ipairs({ { false }, { true }, { false, F.TPL.large, F.TPL.large }, { false, F.TPL.small, F.TPL.small } }) do
		for _, which in ipairs({ "rule", "default" }) do
			local M2, info2, _, cws = fixture(fx[1], false, fx[2], fx[3], which)
			local plan = PP.plan(M2, info2)
			checkPlan(M2, plan, "bounds " .. tostring(fx[1]) .. " " .. which, pedNeed(info2, cws))
			ok(#plan.states <= PP.DEFAULTS.maxPhases)
		end
	end
end)

test("planText: one line with kind, cycle, durations, skips and green entries", function()
	local M, info, conns = fixture(true, false, nil, nil, "rule")
	local plan = PP.plan(M, info)
	local text = PP.planText(plan, #conns)
	ok(text:find("^t3_axis cycle=%d+ 1:%d+s/skip1.5%[") ~= nil, text)
	ok(text:find("/skip3[w1", 1, true) ~= nil, text)
	eq(PP.planText(nil), "none")
	-- runs of indices as a-b, crosswalks as w<k>, minDuration without a trailing .0
	local fake = { kind = "k", cycle = 30, states = {
		{ green = { 0, 1, 2, 4, 6, 7, 10, 11, 12, 13 }, duration = 20, canSkip = false, minDuration = 0 },
		{ green = { 3, 5, 8, 9, 14, 15, 16 }, duration = 10, canSkip = true, minDuration = 5 } } }
	eq(PP.planText(fake, 14), "k cycle=30 1:20s[0-2,4,6,7,10-13] 2:10s/skip5[3,5,8,9,w1-w3]")
	-- at most maxLen characters (Rules.line cuts a field at 200): phases that do not fit become +N
	eq(PP.planText(fake, 14, 40), "k cycle=30 1:20s[0-2,4,6,7,10-13] +1")
	eq(PP.planText(fake, 14, 12), "k cycle=30 +2")
	for _, fx in ipairs({ { false, F.TPL.large, F.TPL.large }, { true, F.TPL.large, F.TPL.large } }) do
		local M2, info2, conns2 = fixture(fx[1], false, fx[2], fx[3], "default")
		local t = PP.planText(PP.plan(M2, info2), #conns2)
		ok(#t <= 190, #t .. ": " .. t)
		ok(t:find("+", 1, true) == nil, "every phase fits: " .. t)
	end
end)

---------------------------------------------------------------------------
-- Random fixtures, curb merges, shared and whole lanes, bus lanes

test("calibrated: random fixtures: every plan valid, indices in range, durations within the sliders", function()
	local seed = 12345
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local lanesets = { { "RS", "SL" }, { "R", "S", "L" }, { "RSL" }, { "RS", "S", "SL" }, { "S", "S" }, { "R", "SL" } }
	for round = 1, 60 do
		local spec = {}
		local nArms = 0
		for s = 1, 4 do
			if rnd(5) > 1 then
				spec[s] = { out = rnd(3), lanes = lanesets[rnd(#lanesets)] }
				nArms = nArms + 1
			end
		end
		if nArms >= 2 then
			local cws = {}
			for s = 1, 4 do
				if spec[s] and rnd(3) > 1 then cws[#cws + 1] = s end
			end
			if rnd(10) == 1 then cws[#cws + 1] = 999 end
			local conns, arms = synth(spec, rnd(360))
			if #conns > 0 then
				local cls = PP.classesFromArms(conns, arms, "right")
				local M = assert(P.build({ conns = conns, arms = arms, crosswalks = cws, cls = cls }))
				local plan, why = PP.plan(M, { conns = conns, arms = arms, side = "right", cls = cls })
				if plan ~= nil then
					checkPlan(M, plan, "random " .. round, nil, cls)
					for _, st in ipairs(plan.states) do
						for _, l in ipairs(st.locked) do ok(l >= 0 and l <= #conns + #cws - 1, "index range") end
					end
				else
					ok(why == "too_many_phases" or why == "axis_extra" or why == "no_axis_shape", "random " .. round .. ": " .. tostring(why))
				end
			end
		end
	end
end)

test("step 4b: curb turns of the other road also go where they only merge (as When safe); kerbMerge = false is the strict plan; never a crossing or a green crosswalk", function()
	local any = 0
	for _, fx in ipairs({ { false, nil, nil, "2x2 X" }, { false, F.TPL.large, F.TPL.large, "3x3 X" }, { true, nil, nil, "T" },
		{ true, F.TPL.large, F.TPL.large, "3x3 T" } }) do
		for _, mir in ipairs({ false, true }) do
			local tag = fx[4] .. (mir and " left" or " right")
			local M, info = fixture(fx[1], mir, fx[2], fx[3], "rule")
			local plan = assert(PP.plan(M, info))
			local strict = assert(PP.plan(M, info, { kerbMerge = false }))
			checkPlan(M, plan, tag)
			eq(strict.kerb, nil, tag .. ": the strict plan lists no kerb turns")
			for s = 1, #strict.states do eq(outsideRoad(M, strict, s), {}, tag .. ": strict phase " .. s .. " has no merge across roads") end
			ok(plan.kerb ~= nil, tag .. ": kerb turns listed")
			for x in pairs(plan.kerb) do eq(M.cls[x + 1], "kerb", tag .. ": listed " .. x .. " is a kerb turn") end
			eq(#plan.states, #strict.states, tag .. ": no phase added")
			local added = 0
			for s, st in ipairs(plan.states) do
				local was = {}
				for _, x in ipairs(strict.states[s].green) do was[x] = true end
				local now = {}
				for _, x in ipairs(st.green) do now[x] = true end
				for x in pairs(was) do ok(now[x], tag .. ": phase " .. s .. " keeps " .. x) end
				for x in pairs(now) do
					if not was[x] then
						eq(M.cls[x + 1], "kerb", tag .. ": phase " .. s .. " adds only kerb turns (" .. x .. ")")
						local merges = 0
						for j, kind in pairs(M.kinds[x] or {}) do
							if now[j] then
								eq(kind, P.MERGE, tag .. ": added " .. x .. " only merges (with " .. j .. ")")
								merges = merges + 1
							end
						end
						ok(merges > 0, tag .. ": added " .. x .. " because of a merge")
						added = added + 1
					end
				end
			end
			-- the validator takes the merges only with the kerb rule on
			local okV, why = PP.validatePlan(M, plan, M.n, M.nCross, { kerbMerge = false, axis = true })
			any = any + added
			if added > 0 then
				ok(okV == false and tostring(why):find(":merge", 1, true) ~= nil, tag .. ": kerbMerge=false refuses (" .. tostring(why) .. ")")
			end
		end
	end
	ok(any > 0, "some kerb turn merges somewhere")
	-- a plan.kerb entry that M.cls calls something else is refused
	local M, info = fixture(false, false, nil, nil, "rule")
	local plan = assert(PP.plan(M, info))
	local straight = nil
	for i, c in pairs(M.cls) do if c == "straight" then straight = i - 1 break end end
	local bad = { states = plan.states, kerb = { [straight] = true }, axis = plan.axis }
	eq({ PP.validatePlan(M, bad, M.n, M.nCross, { axis = true }) }, { false, "kerb_class:" .. straight })
	-- fan plans keep their own rule: no kerb list
	eq(PP.plan(M, info, { fan = true }) and PP.plan(M, info, { fan = true }).kerb, nil, "fan: no kerb merges")
end)

test("shared lanes (a player's report 2026-10-14): a kerb turn whose lane also goes straight or far is green only with a lane mate, never alone in another approach's phase; 1-lane and 2-lane X, T, both sides", function()
	for _, mir in ipairs({ false, true }) do
		for _, fx in ipairs({ { false, F.TPL.small, F.TPL.small, "1x1 X" }, { false, F.TPL.medium_bus, F.TPL.small, "bus x 1 X" },
			{ false, nil, nil, "2x2 X" }, { true, F.TPL.small, F.TPL.small, "1x1 T" }, { false, F.TPL.large, F.TPL.medium, "3x3 x 2x2 X" } }) do
			local tag = fx[4] .. (mir and " left" or " right")
			local M, info, conns, cws = fixture(fx[1], mir, fx[2], fx[3], "rule")
			local plan = assert(PP.plan(M, info), tag)
			checkPlan(M, plan, tag, pedNeed(info, cws))
			local kerbSeen = 0
			for s, st in ipairs(plan.states) do
				local g = greenSet(st)
				for x in pairs(g) do
					local c = conns[x + 1]
					if c ~= nil and info.cls[x + 1] == "kerb" then
						kerbSeen = kerbSeen + 1
						local alone, mate = true, false
						for y, d in ipairs(conns) do
							if y - 1 ~= x and d.segment0 == c.segment0 and d.lane0 == c.lane0 then
								alone = false
								if g[y - 1] then mate = true end
							end
						end
						ok(alone or mate, string.format("%s phase %d: kerb turn %s green with its lane", tag, s, Rules.connsText({ c })))
					end
				end
			end
			ok(kerbSeen > 0, tag .. ": kerb turns are green somewhere")
		end
	end
	-- the 1-lane X: one phase per road, each with exactly its own road's movements (no other kerb turn joins)
	local M, info, conns = fixture(false, false, F.TPL.small, F.TPL.small, "rule")
	local plan = PP.plan(M, info)
	eq(plan.kind, "x4_axis")
	for s, st in ipairs(plan.states) do
		if plan.axis[s] ~= nil then
			local road = {}
			for _, seg in ipairs(plan.axis[s]) do road[seg] = true end
			for _, x in ipairs(st.green) do
				if x < #conns then ok(road[conns[x + 1].segment0], "1x1 X: a phase serves its road only: " .. PP.planText(plan, #conns)) end
			end
		end
	end
end)

--- The player's case (2026-10-14): a lit crossroads, main road 11-12 "BS BU BV FV FU FS" (one car lane
-- and a curbside bus lane each way) x a 1-lane street (13-14). Connections: the rule's car lanes plus
-- the bus lanes' own (kept as read): straight on into the opposite bus lane, a curb turn into the side
-- street's car lane, with far = true also a far turn. Returns M, info, conns, busSet (0-based).
local function busCross(mir, far, main, which)
	local v, world = crossing(false, mir, main or F.TPL.medium_bus, F.TPL.small)
	local conns = which == "default" and Cross.defaultConns(v) or Slip.roadConns(v)
	-- bus-only lane ends at node 1, in / out per segment (template order seen from the node)
	local busIn, busOut = {}, {}
	for _, sid in ipairs(world.node(1).segs) do
		local sg = world.seg(sid)
		local e = sg.node0 == 1 and 0 or 1
		for k0 = 0, #sg.lanes - 1 do
			local lc = sg.lanes[k0 + 1]
			if lc.road and not lc.car then
				local idx = e == 0 and k0 or (#sg.lanes - 1 - k0)
				local leaving = (e == 0 and lc.forward) or (e == 1 and not lc.forward)
				if leaving then busOut[sid] = idx else busIn[sid] = idx end
			end
		end
	end
	local busSet = {}
	for _, ap in ipairs(v.approaches) do
		local lane = busIn[ap.seg]
		if lane ~= nil then
			for _, ex in ipairs(ap.allExits or ap.exits) do
				local to = nil
				if ex.cat == "straight" then to = busOut[ex.seg] or ex.o[1]
				elseif ex.cat == "kerb" then to = busOut[ex.seg] or ex.o[1]
				elseif ex.cat == "far" and far then to = ex.o[#ex.o] end
				if to ~= nil then
					conns[#conns + 1] = Rules.conn(ap.seg, lane, ex.seg, to, true, false)
					busSet[#conns - 1] = true
				end
			end
		end
	end
	local cws = {}
	for _, sid in ipairs(world.node(1).segs) do cws[#cws + 1] = sid end
	local info = PP.infoFromView(v, world, 1, conns)
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
	return M, info, conns, busSet, cws
end

test("whole lanes (a player's report 2026-10-14): every lane all green or all red in every phase; 1-lane X / T, 2-lane shared X, 3x3 x 2x2, bus lanes, both sides, both lane rules", function()
	for _, mir in ipairs({ false, true }) do
		for _, which in ipairs({ "rule", "default" }) do
			for _, fx in ipairs({ { false, F.TPL.small, F.TPL.small, "1-lane X" }, { true, F.TPL.small, F.TPL.small, "1-lane T" },
				{ false, nil, nil, "2-lane X" }, { true, nil, nil, "2-lane T" }, { false, F.TPL.large, F.TPL.medium, "3x3 x 2x2 X" } }) do
				local tag = fx[4] .. " " .. which .. (mir and " left" or " right")
				local M, info, conns, cws = fixture(fx[1], mir, fx[2], fx[3], which)
				for _, opts in ipairs({ {}, { kerbMerge = false } }) do
					local plan = assert(PP.plan(M, info, opts), tag)
					checkPlan(M, plan, tag, pedNeed(info, cws))
					eq(partLane(plan, conns), nil, tag .. ": whole lanes " .. PP.planText(plan, #conns))
				end
			end
		end
		-- the fan plans keep whole lanes too (the validator checks them with the fan flag)
		for _, t in ipairs({ false, true }) do
			local v, world = crossing(t, mir)
			local fan = Cross.fanConns(v)
			local fi = PP.infoFromView(v, world, 1, fan)
			local Mf = assert(P.build({ conns = fan, arms = fi.arms, crosswalks = world.node(1).segs, cls = fi.cls }))
			local pf = assert(PP.plan(Mf, fi, { fan = true }))
			eq(partLane(pf, fan), nil, "fan: whole lanes")
			ok(PP.validatePlan(Mf, pf, Mf.n, Mf.nCross, { fan = true }), "fan validates")
		end
	end
end)

test("bus lanes (a player's report 2026-10-14): a curbside bus lane is green, whole, in every phase where a car lane of its approach is green; its own approach's crossings accepted, other approaches' never; both sides", function()
	-- 3 car lanes and a curbside bus lane each way
	local XL_BUS = "BS BU BV BV BV FV FV FV FU FS"
	for _, mir in ipairs({ false, true }) do
		for _, fx in ipairs({ { false, nil, "bus" }, { true, nil, "bus far turn" }, { false, XL_BUS, "3-lane bus" }, { true, XL_BUS, "3-lane bus far turn" },
			{ false, XL_BUS, "3-lane bus (game lanes)", "default" }, { true, XL_BUS, "3-lane bus far turn (game lanes)", "default" } }) do
			local far = fx[1]
			local tag = fx[3] .. (mir and " left" or " right")
			local M, info, conns, busSet, cws = busCross(mir, far, fx[2], fx[4])
			ok(next(busSet) ~= nil, tag .. ": fixture has bus connections")
			-- the fixture's point: a bus connection crosses or merges with a car connection of its own approach
			local own = 0
			for x in pairs(busSet) do
				for j, kind in pairs(M.kinds[x]) do
					if j < M.n and not busSet[j] and kind ~= P.PED and M.seg0[j] == M.seg0[x] then own = own + 1 end
				end
			end
			ok(own > 0, tag .. ": bus lane crosses its own approach's car lanes in the map")
			local plan = assert(PP.plan(M, info), tag)
			checkPlan(M, plan, tag, pedNeed(info, cws))
			eq(partLane(plan, conns), nil, tag .. ": whole lanes")
			eq(plan.bus, busSet, tag .. ": plan.bus lists the bus-lane connections")
			if not mir and not fx[2] and not far then print("      " .. tag .. ": " .. PP.planText(plan, #conns)) end
			for s, st in ipairs(plan.states) do
				local g = greenSet(st)
				for x in pairs(busSet) do
					local a = conns[x + 1].segment0
					local car = false
					for i, c in ipairs(conns) do
						if g[i - 1] and c.segment0 == a and not busSet[i - 1] then car = true end
					end
					if car and not g[x] then
						-- red beside a green car lane only when a connection of its lane crosses another
						-- approach's green entry or a green crosswalk
						local why = false
						for i, c in ipairs(conns) do
							if busSet[i - 1] and c.segment0 == a and c.lane0 == conns[x + 1].lane0 then
								for j in pairs(M.kinds[i - 1]) do
									if g[j] and (j >= M.n or M.seg0[j] ~= a) then why = true end
								end
							end
						end
						ok(why, string.format("%s phase %d: bus %s red beside its green car lane", tag, s, Rules.connsText({ conns[x + 1] })))
					elseif car then
						ok(g[x], tag)
					end
				end
			end
			-- without the plan's bus list the validator refuses the bus lane's own-approach crossings outside
			-- its road phase (or, in it, ...): at least it is no longer the same valid plan
			local okV, why = PP.validatePlan(M, { states = plan.states, kerb = plan.kerb }, M.n, M.nCross, { axis = true })
			eq(okV, false, tag .. ": refused without plan.bus / plan.axis")
			ok(tostring(why):find("^conflict:") ~= nil, tag .. ": " .. tostring(why))
		end
	end
	-- a bus conflict with another approach is never accepted, even listed
	local M, info, conns, busSet = busCross(false, true)
	local plan = assert(PP.plan(M, info))
	local bx, other = nil, nil
	for x in pairs(busSet) do
		for j, kind in pairs(M.kinds[x]) do
			if j < M.n and kind == P.CROSS and M.seg0[j] ~= M.seg0[x] and bx == nil then bx, other = x, j end
		end
	end
	ok(bx ~= nil, "fixture: a bus far turn crosses another approach")
	local lane = {}
	for i, c in ipairs(conns) do
		if c.segment0 == conns[bx + 1].segment0 and c.lane0 == conns[bx + 1].lane0 then lane[i - 1] = true end
		if c.segment0 == conns[other + 1].segment0 and c.lane0 == conns[other + 1].lane0 then lane[i - 1] = true end
	end
	local locked = {}
	for x = 0, M.size - 1 do if not lane[x] then locked[#locked + 1] = x end end
	local bad = { states = { { locked = locked, duration = 20, minDuration = 0, canSkip = false } }, bus = plan.bus }
	for s = 1, #plan.states do bad.states[s + 1] = plan.states[s] end
	local okV, why = PP.validatePlan(M, bad, M.n, M.nCross)
	eq(okV, false)
	ok(tostring(why):find("^conflict:1:") ~= nil, tostring(why))
end)

test("validatePlan whole lanes: a part-green lane is refused; a road + tram lane counts as one lane; a bus-only lane is its own", function()
	-- tram on the car lanes: a road and a tram connection of one lane pair are one lane (green together)
	local M, info, conns = fixture(false, false, F.TPL.small_tram, F.TPL.small, "rule")
	local n0 = #conns
	local extra = {}
	for _, c in ipairs(conns) do
		if (c.segment0 == 11 or c.segment0 == 12) and info.cls[_] == "straight" then
			extra[#extra + 1] = Rules.conn(c.segment0, c.lane0, c.segment1, c.lane1, false, true)
		end
	end
	ok(#extra > 0, "fixture: tram connections")
	for _, c in ipairs(extra) do conns[#conns + 1] = c end
	local v, world = crossing(false, false, F.TPL.small_tram, F.TPL.small)
	local cws = {}
	for _, sid in ipairs(world.node(1).segs) do cws[#cws + 1] = sid end
	info = PP.infoFromView(v, world, 1, conns)
	M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
	local plan = assert(PP.plan(M, info))
	checkPlan(M, plan, "tram")
	eq(partLane(plan, conns), nil, "tram: whole lanes")
	ok(PP.validatePlan(M, plan, M.n, M.nCross, { axis = true }))
	-- lock only the tram twin where its road connection is green: part of a lane
	local tx = n0 -- the first tram connection (0-based)
	local s = nil
	for k, st in ipairs(plan.states) do
		if greenSet(st)[tx] then s = k break end
	end
	local states = {}
	for k, st in ipairs(plan.states) do
		local l = {}
		for i, x in ipairs(st.locked) do l[i] = x end
		if k == s then l[#l + 1] = tx end
		states[k] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
	end
	eq({ PP.validatePlan(M, { states = states, kerb = plan.kerb, axis = plan.axis }, M.n, M.nCross, { axis = true }) },
		{ false, string.format("part_lane:%d:%d:%d", s, conns[tx + 1].segment0, conns[tx + 1].lane0) })
	-- the bus fixture: the bus lane's own key; red with its car lane green is no part lane
	local Mb, _, connsb, busSet = busCross(false, false)
	local laneOf = {}
	for i, c in ipairs(connsb) do laneOf[i - 1] = c.segment0 .. ":" .. c.lane0 end
	for x in pairs(busSet) do
		for i, c in ipairs(connsb) do
			if not busSet[i - 1] and c.segment0 == connsb[x + 1].segment0 then
				ok(laneOf[i - 1] ~= laneOf[x], "bus lane is a lane of its own")
			end
		end
	end
	ok(Mb.lane0 ~= nil)
	-- bad bus list entries
	local planb = assert(PP.plan(Mb, (select(2, busCross(false, false)))))
	eq({ PP.validatePlan(Mb, { states = planb.states, bus = { [Mb.n] = true } }, Mb.n, Mb.nCross) }, { false, "bus_index" })
end)

---------------------------------------------------------------------------
-- Axis plan (default since rev 8; PHASES_PLAN.md "Axis plan (default since rev 8)"): per road both
-- directions whole, a pedestrian phase after each road, an optional head start with measured demand.

--- The player's crossroads (report 2026-10-14): both roads one car lane and a curbside bus lane each way
-- ("BS BU BV FV FU FS"), the main road (11-12) with tram tracks on its car lanes ("BS BU BT FT FU FS"):
-- the rule's (or the game's) car connections, the bus lanes' own (straight on into the opposite bus lane,
-- a curb turn into the cross road's bus lane), the tram twins of the main road's straights. Returns M,
-- info, conns, busSet (0-based), cws.
local PLAYER_MAIN, PLAYER_SIDE = "BS BU BT FT FU FS", F.TPL.medium_bus
local function playerCross(mir, which)
	local v, world = crossing(false, mir, PLAYER_MAIN, PLAYER_SIDE)
	local conns = which == "default" and Cross.defaultConns(v) or Slip.roadConns(v)
	local busIn, busOut = {}, {}
	for _, sid in ipairs(world.node(1).segs) do
		local sg = world.seg(sid)
		local e = sg.node0 == 1 and 0 or 1
		for k0 = 0, #sg.lanes - 1 do
			local lc = sg.lanes[k0 + 1]
			if lc.road and not lc.car then
				local idx = e == 0 and k0 or (#sg.lanes - 1 - k0)
				local leaving = (e == 0 and lc.forward) or (e == 1 and not lc.forward)
				if leaving then busOut[sid] = idx else busIn[sid] = idx end
			end
		end
	end
	local busSet = {}
	local n0 = #conns
	for i = 1, n0 do
		local c = conns[i]
		-- the tram twin of a straight on the main road's car lanes
		if (c.segment0 == 11 or c.segment0 == 12) and (c.segment1 == 11 or c.segment1 == 12) then
			conns[#conns + 1] = Rules.conn(c.segment0, c.lane0, c.segment1, c.lane1, false, true)
		end
	end
	for _, ap in ipairs(v.approaches) do
		local lane = busIn[ap.seg]
		if lane ~= nil then
			for _, ex in ipairs(ap.allExits or ap.exits) do
				local to = nil
				if ex.cat == "straight" or ex.cat == "kerb" then to = busOut[ex.seg] or ex.o[1] end
				if to ~= nil then
					conns[#conns + 1] = Rules.conn(ap.seg, lane, ex.seg, to, true, false)
					busSet[#conns - 1] = true
				end
			end
		end
	end
	local cws = {}
	for _, sid in ipairs(world.node(1).segs) do cws[#cws + 1] = sid end
	local info = PP.infoFromView(v, world, 1, conns)
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
	return M, info, conns, busSet, cws
end

--- Checks of every axis plan: tags, every connection of the road's approaches green in its phase (whole
-- approaches), crosswalks only in the pedestrian phases, the pedestrian phases every vehicle red and
-- skippable after their 3 s clearance, the vehicle phases skippable with the game's 1.5 s, whole lanes, valid only with the axis flag
-- when the road has an inner conflict.
local function checkAxis(M, plan, conns, tag, pedSec)
	checkPlan(M, plan, tag)
	eq(plan.pattern, "axis", tag)
	eq(partLane(plan, conns), nil, tag .. ": whole lanes")
	for s, st in ipairs(plan.states) do
		local g = greenSet(st)
		if st.tag == "ped" then
			-- skippable after the 3 s clearance (rev 8, user 2026-10-14; the game's phases all skip)
			eq({ st.canSkip, st.minDuration, st.duration }, { true, 3, pedSec or 6 }, tag .. ": pedestrian phase " .. s)
			eq(#st.green, M.nCross, tag .. ": every crosswalk green, every vehicle red in " .. s)
		else
			ok(st.tag == "axis" or st.tag == "head", tag .. ": phase " .. s .. " tag " .. tostring(st.tag))
			eq({ st.canSkip, st.minDuration }, { true, 1.5 }, tag .. ": phase " .. s .. " skippable, min 1.5 s")
			for x = M.n, M.size - 1 do ok(not g[x], tag .. ": crosswalk red in vehicle phase " .. s) end
			local road = {}
			for _, seg in ipairs(plan.axis[s]) do road[seg] = true end
			for i, c in ipairs(conns) do
				if road[c.segment0] then ok(g[i - 1], tag .. ": phase " .. s .. " greens its road's " .. Rules.connsText({ c })) end
			end
			-- a pedestrian phase after every road phase, none after a head start
			local nxt = plan.states[s % #plan.states + 1]
			eq(nxt.tag, st.tag == "axis" and "ped" or "axis", tag .. ": after phase " .. s)
		end
	end
	local okStrict = PP.validatePlan(M, plan, M.n, M.nCross)
	local inner = 0
	for s, st in ipairs(plan.states) do inner = inner + #P.phaseConflicts(M, st.locked) end
	if inner > 0 then eq(okStrict, false, tag .. ": not valid without the axis flag") end
end

test("axis plan: the player's crossroads (1 car lane + curbside bus lane each way, tram): road by road, both directions whole, pedestrians between", function()
	for _, which in ipairs({ "rule", "default" }) do
		for _, mir in ipairs({ false, true }) do
			local tag = "player " .. which .. (mir and " left" or " right")
			local M, info, conns, busSet = playerCross(mir, which)
			local plan = assert(PP.plan(M, info))
			checkAxis(M, plan, conns, tag)
			eq(plan.kind, "x4_axis", tag)
			eq(tagsOf(plan), { "axis", "ped", "axis", "ped" }, tag)
			-- every bus-lane connection green with its road
			for x in pairs(busSet) do
				local any = false
				for _, st in ipairs(plan.states) do if greenSet(st)[x] then any = true end end
				ok(any, tag .. ": bus connection " .. x .. " green")
			end
			-- greens: 15 s + 4 s x 2 lanes (car + bus) = 23 s per road, raised to the game's 2-lane default 23.7 s
			-- (whole seconds: 24; the player's 23.7 / 21.6 s), 6 s walks
			eq({ plan.states[1].duration, plan.states[3].duration }, { 24, 24 }, tag)
			eq(plan.cycle, 60, tag)
			-- the main road (more lanes: the tram twins share the car lanes, so equal: lower segment id) first
			eq(plan.axis[1], { 11, 12 }, tag)
			if which == "rule" and not mir then
				print("player's crossroads: " .. PP.planText(plan, #conns))
				for _, line in ipairs(phaseText(plan, conns, info.cls)) do print("  " .. line) end
			end
		end
	end
end)

test("axis plan: 2x2 X, 3x3 X, 3x3 x 2x2 X and T (2x2, 1-lane), both lane rules and traffic sides", function()
	local cases = {
		-- greens never under the game's default for the lanes (PP.gameGreen: 2 lanes 23.7 s, 3 lanes 27.1 s, 1 lane 18.9 s)
		{ false, nil, nil, "2x2 X", "x4_axis", { "axis", "ped", "axis", "ped" }, { 24, 6, 24, 6 } },
		{ false, F.TPL.large, F.TPL.large, "3x3 X", "x4_axis", { "axis", "ped", "axis", "ped" }, { 28, 6, 28, 6 } },
		{ false, F.TPL.large, F.TPL.medium, "3x3 x 2x2 X", "x4_axis", { "axis", "ped", "axis", "ped" }, { 28, 6, 24, 6 } },
		{ true, nil, nil, "T 2x2", "t3_axis", { "axis", "ped", "axis", "ped" }, { 24, 6, 24, 6 } },
		{ true, F.TPL.small, F.TPL.small, "T 1-lane", "t3_axis", { "axis", "ped", "axis", "ped" }, { 19, 6, 19, 6 } },
	}
	for _, fx in ipairs(cases) do
		for _, which in ipairs({ "rule", "default" }) do
			local out = {}
			for _, mir in ipairs({ false, true }) do
				local tag = fx[4] .. " " .. which .. (mir and " left" or " right")
				local M, info, conns = fixture(fx[1], mir, fx[2], fx[3], which)
				local plan = assert(PP.plan(M, info), tag)
				checkAxis(M, plan, conns, tag)
				eq(plan.kind, fx[5], tag)
				eq(tagsOf(plan), fx[6], tag)
				local d = {}
				for s, st in ipairs(plan.states) do d[s] = st.duration end
				eq(d, fx[7], tag)
				if fx[1] then
					-- the T: the main road (11-12, straights between them) first, then the side road alone
					local main = { plan.axis[1][1], plan.axis[1][2] }
					table.sort(main)
					eq({ main, plan.axis[3] }, { { 11, 12 }, { 13 } }, tag)
				else
					-- the road with more lanes first
					eq(plan.axis[1], { 11, 12 }, tag)
				end
				out[#out + 1] = { plan.kind, plan.cycle, #plan.states }
				if which == "rule" and not mir then print(fx[4] .. ": " .. PP.planText(plan, #conns)) end
			end
			eq(out[1], out[2], fx[4] .. " " .. which .. ": mirrored the same")
		end
	end
end)

test("axis plan: an asymmetric 3-lane road (2 lanes one way, 1 the other) x a 1-lane street", function()
	-- arms 1 and 3 the main road: 1 enters with 2 lanes (curb + straight, straight + far), 3 with 1 lane
	local spec = { [1] = { out = 1, lanes = { "RS", "SL" } }, [3] = { out = 2, lanes = { "RSL" } },
		[2] = { out = 1, lanes = { "RSL" } }, [4] = { out = 1, lanes = { "RSL" } } }
	for _, a0 in ipairs({ 0, 37 }) do
		local M, info, conns = synthMap(spec, { a0 = a0, cws = { 1, 2, 3, 4 } })
		local plan = assert(PP.plan(M, info))
		local tag = "2+1 " .. a0
		checkAxis(M, plan, conns, tag)
		eq(plan.kind, "x4_axis", tag)
		eq(plan.axis[1], { 1, 3 }, tag .. ": the 3-lane road first")
		-- weights: the road's larger approach (2 lanes: 23 s, raised to the game's 23.7: 24 s), the street 1 lane (19 s)
		eq({ plan.states[1].duration, plan.states[3].duration }, { 24, 19 }, tag)
		eq(plan.cycle, 55, tag)
		if a0 == 0 then print("2+1 road x street: " .. PP.planText(plan, #conns)) end
	end
end)

test("axis plan: a head start only with measured demand (laneDemand ratio >= headStartRatio 1.5), never from lane counts", function()
	local spec = { [1] = { out = 1, lanes = { "RS", "SL" } }, [3] = { out = 2, lanes = { "RSL" } },
		[2] = { out = 1, lanes = { "RSL" } }, [4] = { out = 1, lanes = { "RSL" } } }
	local M, info, conns = synthMap(spec, { cws = { 1, 2, 3, 4 } })
	-- lane counts alone (2 lanes vs 1 lane: ratio 2): no head start
	eq(tagsOf(assert(PP.plan(M, info))), { "axis", "ped", "axis", "ped" }, "lane counts: no head start")
	-- measured: approach 3 (1 lane) carries 3 units, approach 1 (2 lanes) 1: ratio 3
	local demand = { ["1:1"] = 0.5, ["1:2"] = 0.5, ["3:1"] = 3, ["2:1"] = 1, ["4:1"] = 1 }
	local plan = assert(PP.plan(M, info, { laneDemand = demand }))
	checkAxis(M, plan, conns, "head start")
	eq(tagsOf(plan), { "head", "axis", "ped", "axis", "ped" })
	eq(plan.axis[1], { 3 }, "the dominant approach alone")
	local g = greenSet(plan.states[1])
	for i, c in ipairs(conns) do
		if c.segment0 == 3 then ok(g[i - 1], "head start: every movement of approach 3") end
		if c.segment0 == 1 then ok(not g[i - 1], "head start: the opposite approach red") end
	end
	-- head start 4 s x the excess (3 - 1 = 2): 8 s; the road then 15 + 4 x 1 = 19 s, raised to the game's default
	-- for its 2-lane approach (23.7: 24 s); the street 19 s
	eq({ plan.states[1].duration, plan.states[2].duration, plan.states[4].duration }, { 8, 24, 19 })
	eq({ plan.states[1].canSkip, plan.states[1].minDuration }, { true, 1.5 })
	print("head start: " .. PP.planText(plan, #conns))
	-- below the ratio (1.2), the option off: no head start
	local even = { ["1:1"] = 0.5, ["1:2"] = 0.5, ["3:1"] = 1.2, ["2:1"] = 1, ["4:1"] = 1 }
	eq(tagsOf(assert(PP.plan(M, info, { laneDemand = even }))), { "axis", "ped", "axis", "ped" }, "ratio 1.2: none")
	eq(tagsOf(assert(PP.plan(M, info, { laneDemand = demand, headStartRatio = false }))), { "axis", "ped", "axis", "ped" }, "off")
	-- demand also orders the roads: a busy street goes first
	local busySide = { ["2:1"] = 4, ["4:1"] = 4 }
	local p2 = assert(PP.plan(M, info, { laneDemand = busySide }))
	eq(p2.axis[1], { 2, 4 }, "the busier road first")
	-- the T's main road gets a head start the same way (the side road never: one approach)
	local Mt, it, ct = fixture(true, false, nil, nil, "rule")
	local dt = {}
	for _, c in ipairs(ct) do
		if c.segment0 == 12 then dt[c.segment0 .. ":" .. c.lane0] = 3 end
	end
	local pt = assert(PP.plan(Mt, it, { laneDemand = dt }))
	checkAxis(Mt, pt, ct, "T head start")
	eq(tagsOf(pt), { "head", "axis", "ped", "axis", "ped" }, "T head start")
	eq(pt.axis[1], { 12 })
end)

test("axis plan: options: pedPhase sets the pedestrian phase; no crosswalks: an all-red clearance between the roads", function()
	local M, info, conns = fixture(false, false, nil, nil, "rule")
	local p9 = assert(PP.plan(M, info, { pedPhase = 9 }))
	checkAxis(M, p9, conns, "pedPhase 9", 9)
	local M0, info0, conns0 = fixture(false, false, nil, nil, "rule", {})
	local p0 = assert(PP.plan(M0, info0))
	eq(tagsOf(p0), { "axis", "all_red", "axis", "all_red" })
	-- 4 driving lanes x 4.5 m = 18 m / 8 m/s -> 2 s; skippable after its clearance (the 3 s option, at most the phase: 2 s)
	eq({ p0.states[2].duration, p0.states[2].canSkip, p0.states[2].minDuration, #p0.states[2].green }, { 2, true, 2, 0 })
	-- pedClearance: the pedestrian phase's minDuration (0.5 s steps)
	local pc = assert(PP.plan(M, info, { pedClearance = 4.3 }))
	eq({ pc.states[2].canSkip, pc.states[2].minDuration }, { true, 4.5 })
	-- the game green floor: off (gameGreenFloor = false) the calibration alone (23 s at a 2x2), on 24 s
	eq(assert(PP.plan(M, info, { gameGreenFloor = false })).states[1].duration, 23)
	eq({ PP.gameGreen(1), PP.gameGreen(2), PP.gameGreen(3), PP.gameGreen(4), PP.gameGreen(0), PP.gameGreen(99) },
		{ 18.9, 23.7, 27.1, 27.1 + 3.4, 18.9, 60 })
	ok(PP.validatePlan(M0, p0, M0.n, M0.nCross, { axis = true }))
	eq(partLane(p0, conns0), nil)
end)

test("validatePlan axis: within-road conflicts only with the explicit flag and the plan's road list; never across roads or with a crosswalk", function()
	local M, info = fixture(false, false, nil, nil, "rule")
	local plan = assert(PP.plan(M, info))
	eq(plan.kind, "x4_axis")
	ok(#P.phaseConflicts(M, plan.states[1].locked) > 0, "fixture: the road phase has inner conflicts (far turn vs opposite straight)")
	-- without the flag: refused; with it: valid
	local okV, why = PP.validatePlan(M, plan, M.n, M.nCross)
	eq(okV, false)
	ok(tostring(why):find("^conflict:1:") ~= nil, tostring(why))
	eq({ PP.validatePlan(M, plan, M.n, M.nCross, { axis = true }) }, { true })
	local function copy(p)
		local out = { states = {}, kerb = p.kerb, axis = {} }
		for s, st in ipairs(p.states) do
			local l = {}
			for i, x in ipairs(st.locked) do l[i] = x end
			out.states[s] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
		end
		for s, list in pairs(p.axis) do out.axis[s] = { list[1], list[2] } end
		return out
	end
	local function unlock(st, x)
		for i = #st.locked, 1, -1 do
			if st.locked[i] == x then table.remove(st.locked, i) end
		end
	end
	-- the flag without a road list: refused
	local p = copy(plan)
	p.axis = nil
	eq((PP.validatePlan(M, p, M.n, M.nCross, { axis = true })), false, "no road list")
	-- a road list naming two arms of different roads (11 and 13): axis_road
	p = copy(plan)
	p.axis[1] = { 11, 13 }
	eq({ PP.validatePlan(M, p, M.n, M.nCross, { axis = true }) }, { false, "axis_road:1" })
	p = copy(plan)
	p.axis[1] = { 11, 11 }
	eq({ PP.validatePlan(M, p, M.n, M.nCross, { axis = true }) }, { false, "axis_road:1" })
	-- a cross road's lane green in the road phase (a cross-road conflict): refused with the flag too
	p = copy(plan)
	local key = nil
	for x = 0, M.n - 1 do
		if M.seg0[x] == 13 and M.cls[x + 1] == "straight" then key = key or { M.seg0[x], M.lane0[x] } end
	end
	for x = 0, M.n - 1 do
		if M.seg0[x] == key[1] and M.lane0[x] == key[2] then unlock(p.states[1], x) end
	end
	okV, why = PP.validatePlan(M, p, M.n, M.nCross, { axis = true })
	eq(okV, false)
	ok(tostring(why):find("^conflict:1:") ~= nil, "cross road: " .. tostring(why))
	-- a crosswalk green in the road phase: refused
	p = copy(plan)
	unlock(p.states[1], M.n)
	okV, why = PP.validatePlan(M, p, M.n, M.nCross, { axis = true })
	eq(okV, false)
	ok(tostring(why):find(":ped", 1, true) ~= nil, "crosswalk: " .. tostring(why))
	-- the road list of the other state: the conflicts of state 1 are not accepted by state 3's road
	p = copy(plan)
	p.axis[1] = nil
	eq((PP.validatePlan(M, p, M.n, M.nCross, { axis = true })), false, "state 1 without its road")
	-- the T: the main road pair is a road (opposite arms / straights between them)
	local Mt, it = fixture(true, false, nil, nil, "rule")
	ok(PP.roadPair(Mt, 11, 12))
	ok(not PP.roadPair(Mt, 11, 13))
	ok(PP.validatePlan(Mt, assert(PP.plan(Mt, it)), Mt.n, Mt.nCross, { axis = true }))
end)

test("axis plan: random fixtures: every plan valid with the flag, whole lanes, indices in range", function()
	local seed = 777
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local lanesets = { { "RS", "SL" }, { "R", "S", "L" }, { "RSL" }, { "RS", "S", "SL" }, { "S", "S" }, { "R", "SL" } }
	local axisN = 0
	for round = 1, (os.getenv("TEST_FULL") and 120 or 40) do
		local spec = {}
		for s = 1, 4 do
			if rnd(5) > 1 then spec[s] = { out = rnd(3), lanes = lanesets[rnd(#lanesets)] } end
		end
		local conns, arms = synth(spec, rnd(360))
		if #conns > 0 then
			local cws = {}
			for s = 1, 4 do
				if spec[s] and rnd(3) > 1 then cws[#cws + 1] = s end
			end
			local cls = PP.classesFromArms(conns, arms, "right")
			local M = assert(P.build({ conns = conns, arms = arms, crosswalks = cws, cls = cls }))
			local plan = PP.plan(M, { conns = conns, arms = arms, side = "right", cls = cls })
			if plan ~= nil then
				checkPlan(M, plan, "axis random " .. round, nil, cls)
				eq(partLane(plan, conns), nil, "axis random " .. round .. ": whole lanes")
				if plan.pattern == "axis" then axisN = axisN + 1 end
			end
		end
	end
	ok(axisN > 10, "axis plans made: " .. axisN)
end)
