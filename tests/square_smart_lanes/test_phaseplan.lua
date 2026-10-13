-- square_smart_lanes: designed traffic light phase plans (sl_phaseplan.lua, pure): patterns and their
-- selection, maximal phases, crosswalks, timing (pedestrian minimum, cycle range, sliders), validation.

local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local C = Rules.conn

--- The pattern tests below check the plan structure before the in-game calibration (2026-10-12):
-- no all-red clearance, "turns" skip rule, green = 10 s x weight, skip minimum 5 s. The calibrated
-- defaults (clearance, every phase skippable, the game's green range) have their own tests at the end.
local LEGACY = { allRed = 0, skip = "turns", greenBase = 0, greenPerLane = 10, skipMinGreen = 5 }
local function legacy(opts)
	local o = {}
	for k, v in pairs(LEGACY) do o[k] = v end
	for k, v in pairs(opts or {}) do o[k] = v end
	return o
end
local function planL(M, info, opts) return PP.plan(M, info, legacy(opts)) end

---------------------------------------------------------------------------
-- Helpers

--- Independent plan checks: every state conflict-free (P.phaseConflicts), every entry green
-- somewhere, sliders respected, and the pedestrian minimum: for a crosswalk green in phase p, the
-- guaranteed time from the start of p to the end of its run of green phases (p itself: duration, or
-- minDuration when it may skip; later phases: duration unless they may skip) >= need[k].
--- A phase's conflicts (P.phaseConflicts) less the merges with a kerb turn (step 4b, as "When safe":
-- class "kerb" in cls / M.cls, or listed in plan.kerb).
local function hardConflicts(M, plan, locked, cls)
	local c = cls or M.cls or {}
	local function kerb(x) return c[x + 1] == "kerb" or (plan.kerb ~= nil and plan.kerb[x] == true) end
	local out = {}
	for _, x in ipairs(P.phaseConflicts(M, locked) or {}) do
		if not (x[3] == P.MERGE and x[1] < M.n and x[2] < M.n and (kerb(x[1]) or kerb(x[2]))) then out[#out + 1] = x end
	end
	return out
end

local function checkPlan(M, plan, tag, need, cls)
	ok(plan ~= nil, tag .. ": a plan")
	if plan == nil then return end
	local okV, why = PP.validatePlan(M, plan, M.n, M.nCross)
	ok(okV, tag .. ": validates (" .. tostring(why) .. ")")
	local np = #plan.states
	local seen = {}
	for s, st in ipairs(plan.states) do
		eq(hardConflicts(M, plan, st.locked, cls), {}, tag .. ": phase " .. s .. " conflict-free (kerb merges allowed)")
		eq(#st.locked + #st.green, M.size, tag .. ": locked + green = all")
		for _, x in ipairs(st.green) do seen[x] = true end
		ok(st.duration >= 1 and st.duration <= 60 and st.duration == math.floor(st.duration), tag .. ": duration " .. st.duration)
		ok(st.minDuration >= 0 and st.minDuration <= st.duration and st.minDuration <= 30, tag .. ": minDuration")
		if not st.canSkip then eq(st.minDuration, 0, tag .. ": minDuration only with canSkip") end
	end
	for x = 0, M.size - 1 do ok(seen[x], tag .. ": entry " .. x .. " green somewhere") end
	-- a non-turn connection or a crosswalk is green in a phase that never skips (not with skip "all":
	-- every phase but the all-red clearances may skip)
	local allSkip = true
	for _, st in ipairs(plan.states) do
		if not st.canSkip and #st.green > 0 then allSkip = false end
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
		if count < np then
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

local function seedsOf(plan, conns, cls, s)
	-- the movement classes per approach green in state s: "seg:cls" set
	local set = {}
	for _, x in ipairs(plan.states[s].green) do
		local c = conns[x + 1]
		if c then set[c.segment0 .. ":" .. tostring(cls[x + 1])] = true end
	end
	return set
end

---------------------------------------------------------------------------
-- Patterns

test("2x2 X (shared lanes): split phasing, one approach per phase, both rules and traffic sides", function()
	for _, which in ipairs({ "rule", "default" }) do
		for _, mir in ipairs({ false, true }) do
			local tag = "2x2 " .. which .. (mir and " left" or " right")
			local M, info, conns, cws = fixture(false, mir, nil, nil, which)
			local plan = planL(M, info)
			checkPlan(M, plan, tag, pedNeed(info, cws))
			eq(plan.kind, "x4_split", tag)
			-- four approach phases (every movement of one approach) + the pedestrian phase
			local tags = {}
			for s, st in ipairs(plan.states) do tags[s] = st.tag end
			eq(tags, { "approach", "approach", "approach", "approach", "walk" }, tag)
			for s = 1, 4 do
				local own = 0
				for _, x in ipairs(plan.states[s].green) do
					local c = conns[x + 1]
					if c and info.cls[x + 1] == "far" then own = own + 1 end
				end
				ok(own >= 1, tag .. ": phase " .. s .. " has its approach's far turn")
			end
			-- the pedestrian phase: every vehicle red, every crosswalk green
			eq(#plan.states[5].green, #cws, tag .. ": walk phase")
			eq(plan.states[5].duration, 18, tag .. ": 2+2 lanes x 4.5 m / 1.2 + 3 = 18 s")
			ok(plan.cycle >= 40 and plan.cycle <= 90, tag .. ": cycle " .. plan.cycle)
			if which == "rule" and not mir then
				print("2x2 X rule, right-hand traffic: " .. PP.planText(plan, #conns))
				for _, line in ipairs(phaseText(plan, conns, info.cls)) do print("  " .. line) end
			end
		end
	end
end)

test("2x2 X with pedYield: no pedestrian phase, crosswalks green beside their traffic", function()
	local M, info, conns, cws = fixture(false, false, nil, nil, "rule")
	local plan = planL(M, info, { pedYield = true })
	ok(PP.validatePlan(M, plan, M.n, M.nCross, legacy({ pedYield = true })))
	eq(#plan.states, 4)
	eq(plan.kind, "x4_split")
	-- without pedYield the same plan is refused by validation (turns vs crosswalks)
	local okV, why = PP.validatePlan(M, plan, M.n, M.nCross)
	eq(okV, false)
	ok(tostring(why):find(":ped", 1, true) ~= nil, tostring(why))
end)

test("3x3 X with dedicated far-turn lanes: 4-phase protected (leading opposing turns, then straights + kerb turns)", function()
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	for _, a0 in ipairs({ 0, 37 }) do
		local M, info, conns = synthMap(spec, { a0 = a0 })
		local plan = planL(M, info)
		local cls = PP.classesFromArms(conns, info.arms, "right")
		checkPlan(M, plan, "3x3 protected " .. a0)
		eq(plan.kind, "x4_protected")
		eq(#plan.states, 4)
		local tags = {}
		for s, st in ipairs(plan.states) do tags[s] = st.tag end
		eq(tags, { "turn", "axis", "turn", "axis" })
		-- axis 1 = arms 1 and 3 (equal lanes: the first pair by angle)
		local s1, s2 = seedsOf(plan, conns, cls, 1), seedsOf(plan, conns, cls, 2)
		ok(s1["1:far"] and s1["3:far"], "phase 1: opposing far turns")
		ok(not s1["1:straight"] and not s1["3:straight"], "phase 1: no straight of the axis")
		ok(s2["1:straight"] and s2["3:straight"] and s2["1:kerb"] and s2["3:kerb"], "phase 2: straights + kerb turns")
		ok(not s2["1:far"] and not s2["3:far"], "phase 2: no far turn")
		local s3, s4 = seedsOf(plan, conns, cls, 3), seedsOf(plan, conns, cls, 4)
		ok(s3["2:far"] and s3["4:far"] and s4["2:straight"] and s4["4:straight"], "the cross road the same")
		-- the turn phases may skip (only turn movements green only there), the straight phases never
		eq({ plan.states[1].canSkip, plan.states[2].canSkip, plan.states[3].canSkip, plan.states[4].canSkip },
			{ true, false, true, false })
		eq(plan.states[1].minDuration, 5)
		-- weights: 1 lane (far) vs 2 lanes (kerb + straight): the straight phase gets more green
		ok(plan.states[2].duration > plan.states[1].duration, "straights longer than the arrows")
		if a0 == 0 then
			print("3x3 X protected: " .. PP.planText(plan, #conns))
			for _, line in ipairs(phaseText(plan, conns, cls)) do print("  " .. line) end
		end
	end
end)

test("3x3 X with dedicated far-turn lanes and crosswalks: each parallel crosswalk takes the straight phase from the kerb turn", function()
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	local M, info, conns = synthMap(spec, { cws = { 1, 2, 3, 4 } })
	info.roadLanes = { [1] = 6, [2] = 6, [3] = 6, [4] = 6 }
	local plan = planL(M, info)
	local need = {}
	for k = 1, 4 do need[k] = 6 * 4.5 / 1.2 + 3 end
	checkPlan(M, plan, "3x3 protected crosswalks", need)
	eq(plan.kind, "x4_protected")
	eq(#plan.states, 4, "no pedestrian phase: the kerb turns keep other phases")
	-- the crosswalks across arms 2 and 4 are green in the axis 1-3 straight phase
	local g = greenSet(plan.states[2])
	ok(g[M.n + 1] and g[M.n + 3], "crosswalks on arms 2 and 4 with the 1-3 straights")
	ok(not g[M.n] and not g[M.n + 2])
	for _, line in ipairs(phaseText(plan, conns, PP.classesFromArms(conns, info.arms, "right"))) do print("  " .. line) end
end)

test("skewed X: axes within 180 +- 45 deg keep the x4 pattern, beyond fall back to generic", function()
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	for _, cs in ipairs({ { { 0, 70, 180, 250 }, "x4_protected" }, { { 0, 90, 200, 300 }, "x4_protected" },
		{ { 0, 90, 180, 330 }, "generic" } }) do
		local conns, arms = synth(spec)
		-- classes from the square layout, the arm angles skewed
		local cls = PP.classesFromArms(conns, arms, "right")
		for s = 1, 4 do arms[s].angle = cs[1][s] end
		local M = assert(P.build({ conns = conns, arms = arms, cls = cls }))
		local plan = planL(M, { conns = conns, arms = arms, cls = cls })
		checkPlan(M, plan, "skew " .. table.concat(cs[1], "/"), nil, cls)
		eq(plan.kind, cs[2], table.concat(cs[1], "/"))
	end
end)

test("3x3 x 2x2 X: protected on the main road, split on the side road (shared lanes)", function()
	local spec = {
		[1] = { out = 3, lanes = { "R", "S", "L" } }, [3] = { out = 3, lanes = { "R", "S", "L" } },
		[2] = { out = 2, lanes = { "RS", "SL" } }, [4] = { out = 2, lanes = { "RS", "SL" } },
	}
	local M, info, conns = synthMap(spec)
	local plan = planL(M, info)
	checkPlan(M, plan, "3x3 x 2x2")
	eq(plan.kind, "x4_mixed")
	eq(plan.axes, { "protected", "split" })
	local tags = {}
	for s, st in ipairs(plan.states) do tags[s] = st.tag end
	eq(tags, { "turn", "axis", "approach", "approach" })
end)

test("3x3 X and 3x3 x 2x2 X from sl_cross (Smart Lanes' far lane goes straight too): split", function()
	for _, fx in ipairs({ { F.TPL.large, F.TPL.large }, { F.TPL.large, F.TPL.medium } }) do
		for _, mir in ipairs({ false, true }) do
			local M, info, conns, cws = fixture(false, mir, fx[1], fx[2], "rule")
			local plan = planL(M, info)
			checkPlan(M, plan, "sl_cross 3x3", pedNeed(info, cws))
			eq(plan.kind, "x4_split")
			-- the main road (6 lanes) goes first
			local first = conns[plan.states[1].green[1] + 1]
			ok(first.segment0 == 11 or first.segment0 == 12, "main road first")
		end
	end
end)

test("lead-lag: chosen when demand makes it cheaper (shared lead approach, dedicated lag turn); split with lane counts", function()
	local spec = {
		[1] = { out = 3, lanes = { "RS", "SL" } },     -- shares (far lane straight + far)
		[3] = { out = 2, lanes = { "RS", "S", "L" } }, -- dedicated far lane
		[2] = { out = 2, lanes = { "RS", "SL" } }, [4] = { out = 2, lanes = { "RS", "SL" } },
	}
	local M, info, conns = synthMap(spec)
	local plan = planL(M, info)
	checkPlan(M, plan, "lane counts")
	eq(plan.kind, "x4_split", "lane counts: split (one phase change less)")
	-- the far lanes carry little, the straights much: lead-lag serves the straights twice
	local demand = { ["1:1"] = 4, ["1:2"] = 1, ["3:1"] = 4, ["3:2"] = 4, ["3:3"] = 1 }
	local M2, info2 = synthMap(spec, { laneDemand = demand })
	local plan2 = planL(M2, info2)
	checkPlan(M2, plan2, "demand")
	eq(plan2.kind, "x4_mixed")
	eq(plan2.axes, { "leadlag", "split" })
	local tags = {}
	for s, st in ipairs(plan2.states) do tags[s] = st.tag end
	eq(tags, { "approach", "axis", "turn", "approach", "approach" })
	ok(plan2.why:find("best of 2", 1, true) ~= nil, plan2.why)
	-- the shared lane's straight runs with the opposite straights in phase 2 while its far turn is red
	-- (head-of-line); the lag arrow and the lead phase may skip, the overlap never
	eq({ plan2.states[1].canSkip, plan2.states[2].canSkip, plan2.states[3].canSkip }, { true, false, true })
end)

test("T-junction: main straights -> lead far turn into the side road with its straight -> side road", function()
	for _, which in ipairs({ "rule", "default" }) do
		for _, fx in ipairs({ { nil, nil, "2x2" }, { F.TPL.large, F.TPL.large, "3x3" } }) do
			for _, mir in ipairs({ false, true }) do
				local tag = "T " .. fx[3] .. " " .. which .. (mir and " left" or " right")
				local M, info, conns, cws = fixture(true, mir, fx[1], fx[2], which)
				local plan = planL(M, info)
				checkPlan(M, plan, tag, pedNeed(info, cws))
				eq(plan.kind, "t3", tag)
				local tags = {}
				for s, st in ipairs(plan.states) do tags[s] = st.tag end
				eq({ tags[1], tags[2], tags[3] }, { "main", "turn", "side" }, tag)
				-- phase 1: both main straights, no far turn; phase 2: the far turn into 13 + its straight
				local s1, s2, s3 = seedsOf(plan, conns, info.cls, 1), seedsOf(plan, conns, info.cls, 2), seedsOf(plan, conns, info.cls, 3)
				ok(s1["11:straight"] and s1["12:straight"] and not s1["11:far"] and not s1["12:far"], tag .. ": phase 1")
				ok((s2["11:far"] and s2["11:straight"]) or (s2["12:far"] and s2["12:straight"]), tag .. ": phase 2 lead")
				ok(s3["13:far"], tag .. ": phase 3 side road")
				ok(not plan.states[1].canSkip, tag .. ": the main phase never skips")
				if which == "rule" and fx[3] == "2x2" and not mir then
					print("T 2x2 rule, right-hand traffic: " .. PP.planText(plan, #conns))
					for _, line in ipairs(phaseText(plan, conns, info.cls)) do print("  " .. line) end
					local plan2 = planL(M, info, { pedYield = true })
					print("  with pedYield: " .. PP.planText(plan2, #conns))
					for _, line in ipairs(phaseText(plan2, conns, info.cls)) do print("  " .. line) end
				end
			end
		end
	end
end)

test("LHT mirrors: the same kind, phase count, durations and green counts", function()
	for _, fx in ipairs({ { false, nil, nil }, { false, F.TPL.large, F.TPL.large }, { false, F.TPL.large, F.TPL.medium },
		{ true, nil, nil }, { true, F.TPL.large, F.TPL.large } }) do
		for _, which in ipairs({ "rule", "default" }) do
			local function summary(mir)
				local M, info = fixture(fx[1], mir, fx[2], fx[3], which)
				local plan = assert(planL(M, info))
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

test("one-way arms (in only, out only): valid, every movement green, the in-only arm alone on its axis", function()
	-- east 1 / west 3 two-way, north 2 one-way into the node, south 4 one-way out (test_phases fixture)
	local conns = {
		C(1, 1, 3, 4), C(1, 2, 3, 3), C(3, 1, 1, 4), C(3, 2, 1, 3),
		C(2, 1, 3, 4), C(2, 2, 1, 3), C(3, 1, 4, 2), C(1, 2, 4, 1),
	}
	local arms = { { seg = 1, angle = 0 }, { seg = 2, angle = 90 }, { seg = 3, angle = 180 }, { seg = 4, angle = 270 } }
	for _, side in ipairs({ "right" }) do
		local cls = PP.classesFromArms(conns, arms, side)
		eq(cls, { "straight", "straight", "straight", "straight", "kerb", "far", "kerb", "far" })
		local M = assert(P.build({ conns = conns, arms = arms, crosswalks = { 2, 4 }, cls = cls }))
		local plan = planL(M, { conns = conns, arms = arms, side = side })
		checkPlan(M, plan, "one-way")
		ok(plan.kind:find("^x4_") ~= nil, plan.kind)
		print("one-way: " .. PP.planText(plan, #conns) .. " | " .. plan.why)
	end
end)

test("5-way: generic greedy colouring, every movement green, bounded by maxPhases", function()
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
	local plan = planL(M, info)
	local need = {}
	for k = 1, 5 do need[k] = 2 * 4.5 / 1.2 + 3 end
	checkPlan(M, plan, "5-way", need)
	eq(plan.kind, "generic")
	ok(#plan.states <= 8, "phases " .. #plan.states)
	print("5-way: " .. PP.planText(plan, #conns))
	eq({ planL(M, info, { maxPhases = 2 }) }, { nil, "too_many_phases" })
	-- without crosswalks too: the generic colouring's own phases count
	local M0 = assert(P.build({ conns = conns, arms = arms }))
	local info0 = { conns = conns, arms = arms, side = "right" }
	ok(#assert(planL(M0, info0)).states > 2)
	eq({ planL(M0, info0, { maxPhases = 2 }) }, { nil, "too_many_phases" })
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
	local plan = planL(M, info)
	checkPlan(M, plan, "tram", pedNeed(info, { 11, 12, 13, 14 }))
	for t, i in pairs(twin) do
		for s, st in ipairs(plan.states) do
			local g = greenSet(st)
			eq(g[t - 1] == true, g[i - 1] == true, "tram twin " .. t .. " phase " .. s)
		end
	end
end)

test("unknown crosswalks: an all-walk phase with every vehicle red (default), or no plan (refuse)", function()
	local M, info, conns = fixture(true, false, nil, nil, "rule", { 13, 999 })
	ok(M.cwSeg[2] == false)
	local plan = planL(M, info)
	checkPlan(M, plan, "unknown cw")
	local last = plan.states[#plan.states]
	eq(last.tag, "walk")
	eq(last.green, { #conns, #conns + 1 }, "only the crosswalks green")
	-- the unknown crosswalk takes the widest arm: 4 lanes x 4.5 / 1.2 + 3
	eq(last.duration, 18)
	eq({ planL(M, info, { unknownCrosswalk = "refuse" }) }, { nil, "crosswalk_unplaced" })
	-- no crosswalk data at all: no crossing length, the default 14 m
	local M2 = assert(P.build({ conns = conns, arms = info.arms, crosswalks = { 999 }, cls = info.cls }))
	local plan2 = planL(M2, { conns = conns, arms = info.arms, cls = info.cls })
	near(PP.pedMin(M2, { o = PP.options(), info = {}, arms = {} }, 1), 14 / 1.2 + 3, 1e-9)
	eq(plan2.states[#plan2.states].duration, math.ceil(14 / 1.2 + 3))
end)

test("all-red option: a fully locked phase after every phase", function()
	local M, info = fixture(true, false, nil, nil, "rule")
	local plan = planL(M, info, { allRed = 2 })
	checkPlan(M, plan, "all red")
	ok(#plan.states % 2 == 0)
	for s = 2, #plan.states, 2 do
		eq(plan.states[s].tag, "all_red")
		eq(#plan.states[s].green, 0)
		eq(plan.states[s].duration, 2)
		eq(plan.states[s].canSkip, false)
	end
end)

---------------------------------------------------------------------------
-- Timing

test("timing: whole seconds, floors (min green, pedestrians), cycle range, skip minimum in 0.5 s steps", function()
	local M, info, conns, cws = fixture(false, false, F.TPL.large, F.TPL.large, "rule")
	local plan = planL(M, info)
	checkPlan(M, plan, "3x3 rule", pedNeed(info, cws))
	-- the 6-lane crosswalks need 25.5 s each and sit in four different phases: over the 90 s cap
	eq(plan.warnings, { "cycle_over_max" })
	-- a short cycle where the floors allow
	local M2, info2 = synthMap({ [1] = { out = 3, lanes = { "R", "S", "L" } }, [3] = { out = 3, lanes = { "R", "S", "L" } },
		[2] = { out = 3, lanes = { "R", "S", "L" } }, [4] = { out = 3, lanes = { "R", "S", "L" } } })
	local p2 = planL(M2, info2)
	ok(p2.cycle >= 40 and p2.cycle <= 90, "cycle " .. p2.cycle)
	eq(p2.warnings, {})
	local p3 = planL(M2, info2, { cycleMin = 60, cycleMax = 60 })
	eq(p3.cycle, 60)
	local p4 = planL(M2, info2, { minGreen = 12, cycleMin = 10, cycleMax = 10 })
	for _, st in ipairs(p4.states) do ok(st.duration >= 12, "min green " .. st.duration) end
	eq(p4.warnings, { "cycle_over_max" })
	local p5 = planL(M2, info2, { skipMinGreen = 3.3 })
	eq(p5.states[1].minDuration, 3.5, "rounded up to 0.5 s")
	local p6 = planL(M2, info2, { skip = "none" })
	for _, st in ipairs(p6.states) do eq(st.canSkip, false) end
end)

test("timing: a skippable phase whose crosswalk needs more than 30 s never skips", function()
	-- T with the side road's crosswalk only in the lead phase is not reachable with real data; use
	-- huge crossing lengths: every crosswalk needs > 30 s
	local M, info, conns, cws = fixture(true, false, nil, nil, "rule")
	info.crossLen = { [11] = 50, [12] = 50, [13] = 50 }
	local plan = planL(M, info, { pedYield = true })
	ok(PP.validatePlan(M, plan, M.n, M.nCross, legacy({ pedYield = true })))
	for _, st in ipairs(plan.states) do
		if st.canSkip then ok(st.minDuration <= 30) end
	end
	-- every crosswalk is green everywhere here (pedYield): no run ends, no constraint
	local plan2 = planL(M, info)
	checkPlan(M, plan2, "long crossings", { 50 / 1.2 + 3, 50 / 1.2 + 3, 50 / 1.2 + 3 })
end)

---------------------------------------------------------------------------
-- Validation, determinism, bounds

test("validatePlan catches every defect class", function()
	local M, info = fixture(true, false, nil, nil, "rule")
	local plan = assert(planL(M, info))
	ok(PP.validatePlan(M, plan, M.n, M.nCross))
	local function copy(p)
		local out = { states = {}, kerb = p.kerb }
		for s, st in ipairs(p.states) do
			local l = {}
			for i, x in ipairs(st.locked) do l[i] = x end
			out.states[s] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
		end
		return out
	end
	local function bad(fn, want)
		local p = copy(plan)
		fn(p)
		local okV, why = PP.validatePlan(M, p, M.n, M.nCross, LEGACY)
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
	bad(function(p) for _, st in ipairs(p.states) do st.canSkip = true end end, "all_skip")
	bad(function(p) p.states = {} end, "no_states")
	-- a connection red everywhere
	bad(function(p)
		for _, st in ipairs(p.states) do
			local has = false
			for _, x in ipairs(st.locked) do if x == 0 then has = true end end
			if not has then table.insert(st.locked, 0) end
		end
	end, "never_green:0")
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
	local a, b = planL(M, info), planL(M, info)
	eq(a, b)
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	local M1, i1 = synthMap(spec, { a0 = 0 })
	local M2, i2 = synthMap(spec, { a0 = 123 })
	local p1, p2 = planL(M1, i1), planL(M2, i2)
	eq(p1.states, p2.states)
	eq(p1.kind, p2.kind)
end)

test("bounds and bad input: nil map, mismatched connections, empty junction", function()
	local M, info = fixture(true, false, nil, nil, "rule")
	eq({ planL(nil, info) }, { nil, "no_map" })
	local short = { conns = { info.conns[1] }, arms = info.arms }
	eq({ planL(M, short) }, { nil, "conns_mismatch" })
	local E = assert(P.build({}))
	eq({ planL(E, { conns = {} }) }, { nil, "no_conns" })
	-- every plan stays within the sliders and the state bound
	for _, fx in ipairs({ { false }, { true }, { false, F.TPL.large, F.TPL.large }, { false, F.TPL.small, F.TPL.small } }) do
		for _, which in ipairs({ "rule", "default" }) do
			local M2, info2, _, cws = fixture(fx[1], false, fx[2], fx[3], which)
			local plan = planL(M2, info2)
			checkPlan(M2, plan, "bounds " .. tostring(fx[1]) .. " " .. which, pedNeed(info2, cws))
			ok(#plan.states <= PP.DEFAULTS.maxPhases)
		end
	end
end)

test("planText: one line with kind, cycle, durations, skips and green entries", function()
	local M, info, conns = fixture(true, false, nil, nil, "rule")
	local plan = planL(M, info)
	local text = PP.planText(plan, #conns)
	ok(text:find("^t3 cycle=%d+ 1:%d+s%[") ~= nil, text)
	ok(text:find("/skip5", 1, true) ~= nil, text)
	ok(text:find("w1", 1, true) ~= nil, text)
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
		for _, py in ipairs({ false, true }) do
			local M2, info2, conns2 = fixture(fx[1], false, fx[2], fx[3], "default")
			local t = PP.planText(planL(M2, info2, { pedYield = py }), #conns2)
			ok(#t <= 190, #t .. ": " .. t)
			ok(t:find("+", 1, true) == nil, "every phase fits: " .. t)
		end
	end
end)

---------------------------------------------------------------------------
-- Calibrated defaults (the game's measured phases, findings.md "Default traffic light phases,
-- measured in game"): all-red clearance after every phase, every other phase skippable with the
-- game's 1.5 s minimum (or the pedestrian need), greens in the game's 19..27 s range.

--- Tags of a plan's states.
local function tagsOf(plan)
	local out = {}
	for s, st in ipairs(plan.states) do out[s] = st.tag end
	return out
end

--- Every all-red state fully locked, never skipping; every other state skippable with the game's 1.5 s.
local function checkCalibrated(M, plan, tag)
	for s, st in ipairs(plan.states) do
		if st.tag == "all_red" then
			eq(#st.green, 0, tag .. ": all-red " .. s .. " fully locked")
			eq({ st.canSkip, st.minDuration }, { false, 0 }, tag .. ": all-red " .. s .. " never skips")
		else
			eq({ st.canSkip, st.minDuration }, { true, 1.5 }, tag .. ": phase " .. s .. " skippable, min 1.5 s (the game's)")
			eq(plan.states[s % #plan.states + 1].tag, "all_red", tag .. ": a clearance after phase " .. s)
		end
	end
end

test("calibrated 2x2 X: split approaches with 2 s clearances, pedestrian phase 15 s + 3 s, cycle 90 s (75 s without pedestrians)", function()
	for _, which in ipairs({ "rule", "default" }) do
		for _, mir in ipairs({ false, true }) do
			local tag = "2x2 " .. which .. (mir and " left" or " right")
			local M, info, conns, cws = fixture(false, mir, nil, nil, which)
			local plan = PP.plan(M, info)
			checkPlan(M, plan, tag, pedNeed(info, cws))
			checkCalibrated(M, plan, tag)
			eq(plan.kind, "x4_split", tag)
			eq(tagsOf(plan), { "approach", "all_red", "approach", "all_red", "approach", "all_red", "approach", "all_red",
				"walk", "all_red" }, tag)
			-- 4 driving lanes x 4.5 m = 18 m / 8 m/s = 2.25 -> 2 s
			for _, s in ipairs({ 2, 4, 6, 8 }) do eq(plan.states[s].duration, 2, tag .. ": vehicle clearance") end
			-- pedestrians: 18 m / 1.2 m/s = 15 s walk + 3 s clearance (the pedestrian floor 18 s)
			eq({ plan.states[9].duration, plan.states[10].duration }, { 15, 3 }, tag .. ": walk + clearance")
			eq(#plan.states[9].green, #cws)
			-- 4 approach phases of 2 lanes would get 23 s each (the game's 23.7 s), scaled into 90 s
			for _, s in ipairs({ 1, 3, 5, 7 }) do eq(plan.states[s].duration, 16, tag) end
			eq(plan.cycle, 90, tag)
			if which == "rule" and not mir then print("2x2 X: " .. PP.planText(plan, #conns)) end
		end
	end
end)

test("calibrated 3x3 X (sl_cross): crosswalks beside the approaches, 3 s clearances, the pedestrian floor in the green", function()
	for _, mir in ipairs({ false, true }) do
		local M, info, conns, cws = fixture(false, mir, F.TPL.large, F.TPL.large, "rule")
		local plan = PP.plan(M, info)
		checkPlan(M, plan, "3x3", pedNeed(info, cws))
		checkCalibrated(M, plan, "3x3")
		eq(plan.kind, "x4_split")
		eq(#plan.states, 8, "no pedestrian phase")
		-- 6 lanes x 4.5 = 27 m / 8 = 3.4 -> 3 s; 27 / 1.2 + 3 = 25.5 s per crosswalk, 3 s of it the clearance
		for s = 2, 8, 2 do eq(plan.states[s].duration, 3) end
		for s = 1, 7, 2 do eq(plan.states[s].duration, 23) end
		eq(plan.warnings, { "cycle_over_max" })
		if not mir then print("3x3 X: " .. PP.planText(plan, #conns)) end
	end
end)

test("calibrated T: main road 23 s (the game's 23.7 s for 2 lanes), lead turn, side road, pedestrians", function()
	for _, fx in ipairs({ { nil, nil, "T 2x2", 2 }, { F.TPL.large, F.TPL.large, "T 3x3", 3 } }) do
		for _, mir in ipairs({ false, true }) do
			local tag = fx[3] .. (mir and " left" or " right")
			local M, info, conns, cws = fixture(true, mir, fx[1], fx[2], "rule")
			local plan = PP.plan(M, info)
			checkPlan(M, plan, tag, pedNeed(info, cws))
			checkCalibrated(M, plan, tag)
			eq(plan.kind, "t3", tag)
			eq(tagsOf(plan), { "main", "all_red", "turn", "all_red", "side", "all_red", "walk", "all_red" }, tag)
			eq(plan.states[2].duration, fx[4], tag .. ": clearance")
			ok(plan.cycle <= 91, tag .. ": cycle " .. plan.cycle)
			if fx[3] == "T 2x2" then
				eq(plan.states[1].duration, 23, tag)
				-- 85 s before step 4b: kerb turn 5 now also goes in the main road's phase (it only
				-- merges there), so the turn phase needs 17 s instead of 19 s
				eq(plan.cycle, 83, tag)
			end
			if not mir then print(fx[3] .. ": " .. PP.planText(plan, #conns)) end
		end
	end
end)

test("calibrated: green targets 15 s + 4 s per lane (19 / 23 / 27 s), scaled down only past the 90 s cycle", function()
	for lanes, want in pairs({ [1] = 19, [2] = 23, [3] = 27 }) do
		local spec = {}
		local list = {}
		for k = 1, lanes do list[k] = "S" end
		for s = 1, 4 do spec[s] = { out = lanes, lanes = list } end
		local M, info = synthMap(spec)
		local plan = PP.plan(M, info)
		checkPlan(M, plan, "plain " .. lanes)
		eq(plan.kind, "x4_plain")
		eq(tagsOf(plan), { "axis", "all_red", "axis", "all_red" })
		eq({ plan.states[1].duration, plan.states[3].duration }, { want, want }, lanes .. " lanes")
		-- no road width known: the default 3 s clearance
		eq(plan.states[2].duration, 3)
	end
	-- the 3x3 protected plan (dedicated far lanes): arrows 1 lane, straights + kerb 2 lanes, scaled into 90 s
	local spec = {}
	for s = 1, 4 do spec[s] = { out = 3, lanes = { "R", "S", "L" } } end
	local M, info, conns = synthMap(spec, { cws = { 1, 2, 3, 4 } })
	info.roadLanes = { [1] = 6, [2] = 6, [3] = 6, [4] = 6 }
	local plan = PP.plan(M, info)
	checkPlan(M, plan, "3x3 protected", { 25.5, 25.5, 25.5, 25.5 })
	checkCalibrated(M, plan, "3x3 protected")
	eq(plan.kind, "x4_protected")
	eq(plan.cycle, 90)
	ok(plan.states[3].duration > plan.states[1].duration, "straights longer than the arrows")
	print("3x3 X far lanes: " .. PP.planText(plan, #conns))
end)

test("calibrated: vehicle clearance clamp(round(width / 8 m/s), 2, 4) s; allRed = seconds or 0 overrides", function()
	local M, info = fixture(true, false, nil, nil, "rule")
	local function clear(i)
		local plan = assert(PP.plan(M, i))
		return plan.states[2].duration
	end
	eq(clear(info), 2)
	local wide = { conns = info.conns, arms = info.arms, cls = info.cls, side = info.side, crossLen = { [11] = 50, [12] = 50, [13] = 50 } }
	eq(clear(wide), 4, "50 m / 8 = 6.25 -> 4 s (max)")
	local narrow = { conns = info.conns, arms = info.arms, cls = info.cls, side = info.side, crossLen = { [11] = 6, [12] = 6, [13] = 6 } }
	eq(clear(narrow), 2, "6 m / 8 = 0.75 -> 2 s (min)")
	local none = { conns = info.conns, arms = info.arms, cls = info.cls, side = info.side }
	eq(clear(none), 3, "no road width known: 3 s")
	local p0 = assert(PP.plan(M, info, { allRed = 0 }))
	for _, st in ipairs(p0.states) do ok(st.tag ~= "all_red") end
	eq(PP.validatePlan(M, p0, M.n, M.nCross), true, "every phase skippable: valid with skip all")
	eq({ PP.validatePlan(M, p0, M.n, M.nCross, { skip = "turns" }) }, { false, "all_skip" })
	local p5 = assert(PP.plan(M, info, { allRed = 5 }))
	for s = 2, #p5.states, 2 do eq(p5.states[s].duration, 5) end
end)

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
					ok(why == "too_many_phases", "random " .. round .. ": " .. tostring(why))
				end
			end
		end
	end
end)

test("step 4b: kerb turns also go where they only merge (as When safe); kerbMerge = false is the strict plan; never a crossing or a green crosswalk", function()
	local any = 0
	for _, fx in ipairs({ { false, nil, nil, "2x2 X" }, { false, F.TPL.large, F.TPL.large, "3x3 X" }, { true, nil, nil, "T" } }) do
		for _, mir in ipairs({ false, true }) do
			local tag = fx[4] .. (mir and " left" or " right")
			local M, info = fixture(fx[1], mir, fx[2], fx[3], "rule")
			local plan = assert(PP.plan(M, info))
			local strict = assert(PP.plan(M, info, { kerbMerge = false }))
			checkPlan(M, plan, tag)
			eq(strict.kerb, nil, tag .. ": the strict plan lists no kerb turns")
			for s, st in ipairs(strict.states) do eq(P.phaseConflicts(M, st.locked), {}, tag .. ": strict phase " .. s .. " has no merge") end
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
				local green = {}
				for x in pairs(now) do green[x] = true end
				for x in pairs(now) do
					if not was[x] then
						eq(M.cls[x + 1], "kerb", tag .. ": phase " .. s .. " adds only kerb turns (" .. x .. ")")
						local merges = 0
						for j, kind in pairs(M.kinds[x] or {}) do
							if green[j] then
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
			local okV, why = PP.validatePlan(M, plan, M.n, M.nCross, { kerbMerge = false })
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
	local bad = { states = plan.states, kerb = { [straight] = true } }
	eq({ PP.validatePlan(M, bad, M.n, M.nCross) }, { false, "kerb_class:" .. straight })
	-- fan plans keep their own rule: no kerb list
	eq(PP.plan(M, info, { fan = true }) and PP.plan(M, info, { fan = true }).kerb, nil, "fan: no kerb merges")
end)
