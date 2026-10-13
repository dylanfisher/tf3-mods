-- square_smart_lanes: fan mode (sl_fan zones, PHASES_PLAN.md "Fan mode"): sl_cross X.fanConns (every entry
-- lane to every exit lane of every other arm) and the fan phase plan (sl_phaseplan opts.fan: one approach
-- per phase, conflicts within an approach accepted, never between approaches or with a crosswalk), both
-- traffic sides, 2x2 / 3x3 / 3x2 crossroads and T-junctions. Zone routing: test_script.lua / test_tool.lua
-- "fan".

local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PP = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

--- Crossroads (or a T without 14) at node 1: 11 west, 12 east (main), 13 north, 14 south; lit (a light
-- stands) unless lit is given. Returns view, world.
local function crossing(t, mirror_, main, side, lit)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	local segs = { [11] = { 1, 2, main or F.TPL.medium }, [12] = { 1, 3, main or F.TPL.medium }, [13] = { 1, 4, side or F.TPL.medium } }
	if not t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, side or F.TPL.medium }
	end
	local world = F.build(nodes, segs, mirror_)
	if lit ~= "unknown" then
		world.lit = function() return lit ~= false end
	end
	local v = Slip.classify(world, 1)
	assert(v.case == "X", "crossing fixture is case X")
	return v, world
end

-- 2x2, 3x3, 3x2 (3x3 main road, 2x2 side road) crossroads and T-junctions
local SHAPES = {
	{ name = "2x2 X", t = false },
	{ name = "3x3 X", t = false, main = F.TPL.large, side = F.TPL.large },
	{ name = "3x2 X", t = false, main = F.TPL.large, side = F.TPL.medium },
	{ name = "2x2 T", t = true },
	{ name = "3x2 T", t = true, main = F.TPL.large, side = F.TPL.medium },
}

--- Independent of sl_ring: whether lane index idx of segment s at node is a road lane arriving
-- (incoming = true) or leaving there.
local function roadLane(s, node, idx, incoming)
	local e = Ring.endAt(s, node)
	if e == nil or type(idx) ~= "number" or idx < 0 or idx >= #s.lanes then return false end
	local k0 = e == 0 and idx or (#s.lanes - 1 - idx)
	local l = s.lanes[k0 + 1]
	if not l.road or l.walk then return false end
	local leaving = (e == 0 and l.forward) or (e == 1 and not l.forward)
	return leaving ~= incoming
end

--- Road lanes of a segment at the node, counted from its lane list: in, out.
local function laneCounts(s)
	local f, b = 0, 0
	for _, l in ipairs(s.lanes) do
		if l.road then
			if l.forward then f = f + 1 else b = b + 1 end
		end
	end
	return f, b
end

local function fanMap(v, world, conns, cws)
	if cws == nil then
		cws = {}
		for _, sid in ipairs(world.node(1).segs) do cws[#cws + 1] = sid end
	end
	local info = PP.infoFromView(v, world, 1, conns)
	local M = assert(P.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls }))
	return M, info, cws
end

--- Independent plan checks for a fan plan: indices in range, locked + green = all, no conflict between
-- two approaches (or with a crosswalk) green together, every connection and crosswalk green somewhere,
-- each approach's whole fan green together in one phase, sliders respected.
local function checkFanPlan(M, plan, conns, tag)
	ok(plan ~= nil, tag .. ": a plan")
	if plan == nil then return end
	local seen = {}
	local whole = {}
	for s, st in ipairs(plan.states) do
		eq(#st.locked + #st.green, M.size, tag .. ": locked + green = all")
		local red = {}
		for _, l in ipairs(st.locked) do
			ok(type(l) == "number" and l == math.floor(l) and l >= 0 and l < M.size, tag .. ": index " .. tostring(l) .. " in range")
			red[l] = true
		end
		for _, x in ipairs(st.green) do seen[x] = true end
		for _, c in ipairs(P.phaseConflicts(M, st.locked)) do
			local a, b = c[1], c[2]
			local intra = a < M.n and b < M.n and conns[a + 1].segment0 == conns[b + 1].segment0 and c[3] ~= P.PED
			ok(intra, string.format("%s: phase %d: %d-%d %s only within one approach", tag, s, a, b, c[3]))
		end
		-- approaches whose every connection is green here
		local per = {}
		for i, c in ipairs(conns) do
			local k = c.segment0
			if per[k] == nil then per[k] = true end
			if red[i - 1] then per[k] = false end
		end
		for k, all in pairs(per) do if all then whole[k] = true end end
		ok(st.duration >= 1 and st.duration <= 60 and st.duration == math.floor(st.duration), tag .. ": duration")
		ok(st.minDuration >= 0 and st.minDuration <= st.duration and st.minDuration <= 30, tag .. ": minDuration")
	end
	for x = 0, M.size - 1 do ok(seen[x], tag .. ": entry " .. x .. " green somewhere") end
	for _, c in ipairs(conns) do ok(whole[c.segment0], tag .. ": approach " .. c.segment0 .. " green as a whole") end
end

local function tagsOf(plan)
	local out = {}
	for s, st in ipairs(plan.states) do out[s] = st.tag end
	return out
end

---------------------------------------------------------------------------
-- Connections

test("fanConns: every entry lane to every exit lane of every other arm; road lanes only; no U-turn; both sides", function()
	for _, sh in ipairs(SHAPES) do
		for _, mir in ipairs({ false, true }) do
			local tag = sh.name .. (mir and " left" or " right")
			local v, world = crossing(sh.t, mir, sh.main, sh.side)
			local conns = Cross.fanConns(v)
			-- the expected count from the lane lists alone: per approach (in lanes) x (out lanes of the other arms)
			local want = 0
			local segs = world.node(1).segs
			local inOf, outOf = {}, {}
			for _, sid in ipairs(segs) do
				local s = world.seg(sid)
				local f, b = laneCounts(s)
				-- at node 1 (node0 of every fixture segment): forward lanes leave, backward ones arrive
				assert(s.node0 == 1)
				inOf[sid], outOf[sid] = b, f
			end
			for _, a in ipairs(segs) do
				local outs = 0
				for _, b in ipairs(segs) do if b ~= a then outs = outs + outOf[b] end end
				want = want + inOf[a] * outs
			end
			eq(#conns, want, tag .. ": count")
			local seen = {}
			for _, c in ipairs(conns) do
				ok(c.segment0 ~= c.segment1, tag .. ": no U-turn")
				ok(c.withRoad == true and c.withTram == false, tag .. ": road connection")
				ok(roadLane(world.seg(c.segment0), 1, c.lane0, true), tag .. ": lane0 an incoming road lane " .. c.lane0)
				ok(roadLane(world.seg(c.segment1), 1, c.lane1, false), tag .. ": lane1 an outgoing road lane " .. c.lane1)
				local k = c.segment0 .. ":" .. c.lane0 .. ">" .. c.segment1 .. ":" .. c.lane1
				ok(not seen[k], tag .. ": no duplicate " .. k)
				seen[k] = true
			end
		end
	end
end)

test("fanConns: 2x2 X = 48, 3x3 X = 108, 3x2 X = 74, 2x2 T = 24; deterministic order (approach, exit, lanes)", function()
	local counts = {}
	for _, sh in ipairs(SHAPES) do
		local v = crossing(sh.t, false, sh.main, sh.side)
		counts[sh.name] = #Cross.fanConns(v)
		eq(Rules.connsText(Cross.fanConns(v)), Rules.connsText(Cross.fanConns(crossing(sh.t, false, sh.main, sh.side))), sh.name)
	end
	eq(counts, { ["2x2 X"] = 48, ["3x3 X"] = 108, ["3x2 X"] = 74, ["2x2 T"] = 24, ["3x2 T"] = 42 })
end)

test("Slip.plan opts.fan: the fan only at a lit crossroads (mode=fan); unlit / unknown keep the rule (fan=unlit|lit_unknown)", function()
	for _, mir in ipairs({ false, true }) do
		local v, world = crossing(false, mir)
		local r = Slip.plan(world, 1, function() return {} end, { fan = true })
		eq(r.fan, true)
		eq(Rules.connsText(r.conns), Rules.connsText(Cross.fanConns(v)))
		local text = Rules.line("APPLY", Slip.logFields(r))
		ok(text:find(" lit=yes mode=fan", 1, true) ~= nil, text)
		-- without the option: the rule, as always
		local plain = Slip.plan(world, 1, function() return {} end)
		eq(plain.fan, nil)
		eq(Rules.connsText(plain.conns), Rules.connsText(Slip.roadConns(v)))
		for _, lit in ipairs({ false, "unknown" }) do
			local v2, w2 = crossing(false, mir, nil, nil, lit)
			local r2 = Slip.plan(w2, 1, function() return {} end, { fan = true })
			eq(r2.fan, nil)
			eq(r2.fanWait, lit == false and "unlit" or "lit_unknown")
			eq(Rules.connsText(r2.conns), Rules.connsText(Slip.roadConns(v2)), "the rule")
			local t2 = Rules.line("APPLY", Slip.logFields(r2))
			ok(t2:find(" fan=" .. r2.fanWait, 1, true) ~= nil and not t2:find("mode=fan", 1, true), t2)
		end
	end
end)

test("fanConns + tram: the engine's tram connections are kept beside the fan (Rules.mergeTram)", function()
	local v, world = crossing(false, false, F.TPL.small_tram, F.TPL.medium)
	local fan = Cross.fanConns(v)
	local tram = { Rules.conn(11, 1, 12, 2, false, true), Rules.conn(12, 1, 11, 2, false, true) }
	local r = Slip.plan(world, 1, function() return tram end, { fan = true })
	eq(r.fan, true)
	local trams = 0
	for _, c in ipairs(r.conns) do if c.withTram then trams = trams + 1 end end
	eq(trams, 2, "tram connections kept")
	eq(Rules.roadCount(r.conns), #fan)
end)

---------------------------------------------------------------------------
-- Plans

test("fan plans: one approach per phase (whole fan green), pedestrian phase, valid, both sides, all shapes", function()
	for _, sh in ipairs(SHAPES) do
		for _, mir in ipairs({ false, true }) do
			local tag = sh.name .. (mir and " left" or " right")
			local v, world = crossing(sh.t, mir, sh.main, sh.side)
			local conns = Cross.fanConns(v)
			local M, info, cws = fanMap(v, world, conns)
			local plan, why = PP.plan(M, info, { fan = true })
			ok(plan ~= nil, tag .. ": " .. tostring(why))
			checkFanPlan(M, plan, conns, tag)
			eq(plan.fan, true, tag)
			eq(plan.kind, sh.t and "t3_fan" or "x4_fan", tag)
			local nAp = sh.t and 3 or 4
			local want = {}
			for _ = 1, nAp do
				want[#want + 1] = "approach"
				want[#want + 1] = "all_red"
			end
			want[#want + 1] = "walk"
			want[#want + 1] = "all_red"
			eq(tagsOf(plan), want, tag)
			-- the pedestrian phase: every crosswalk, no vehicle (every arm is used by every fan)
			local walk = plan.states[#plan.states - 1]
			eq(#walk.green, #cws, tag .. ": walk phase")
			ok(PP.validatePlan(M, plan, M.n, M.nCross, { fan = true }), tag .. ": validates as a fan plan")
			-- the flag is explicit: without it the same plan is refused (the fan's own crossings)
			local okV, whyV = PP.validatePlan(M, plan, M.n, M.nCross)
			eq(okV, false, tag)
			ok(tostring(whyV):find("^conflict:") ~= nil, tag .. ": " .. tostring(whyV))
			ok(plan.cycle >= 40, tag .. ": cycle " .. plan.cycle)
			if not mir then print(tag .. " fan: " .. PP.planText(plan, #conns)) end
		end
	end
end)

test("fan plans: an approach's movement joins another phase only when it crosses nothing of the active approach", function()
	-- a one-way arm out (no approach): its exit-only arm leaves room; synthetic: 3x3 X with 14 one-way out
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local segs = { [11] = { 1, 2, F.TPL.medium }, [12] = { 1, 3, F.TPL.medium }, [13] = { 1, 4, F.TPL.medium },
		[14] = { 1, 5, F.TPL.one_way_small } }
	for _, mir in ipairs({ false, true }) do
		local world = F.build(nodes, segs, mir)
		world.lit = function() return true end
		local v = Slip.classify(world, 1)
		eq(v.case, "X", "one-way out: case X (" .. tostring(v.reason) .. ")")
		if v.case == "X" then
			local conns = Cross.fanConns(v)
			local M, info = fanMap(v, world, conns, {})
			local plan = PP.plan(M, info, { fan = true })
			checkFanPlan(M, plan, conns, "one-way out " .. tostring(mir))
			eq(#plan.states, 6, "3 approaches + clearances, no crosswalks")
		end
	end
	-- the validator never accepts an inter-approach conflict, even flagged fan
	local v, world = crossing(false, false)
	local conns = Cross.fanConns(v)
	local M, info = fanMap(v, world, conns)
	local plan = assert(PP.plan(M, info, { fan = true }))
	-- open two opposing approaches together in phase 1
	local st = plan.states[1]
	local s0 = conns[st.green[1] + 1].segment0
	local other = nil
	for i, c in ipairs(conns) do
		if c.segment0 ~= s0 and P.kind(M, st.green[1], i - 1) ~= nil then other = i - 1 break end
	end
	ok(other ~= nil)
	local locked = {}
	for _, l in ipairs(st.locked) do if l ~= other then locked[#locked + 1] = l end end
	local bad = { states = { { locked = locked, duration = 20, minDuration = 0, canSkip = false } } }
	for s = 2, #plan.states do bad.states[s] = plan.states[s] end
	local okV, why = PP.validatePlan(M, bad, M.n, M.nCross, { fan = true })
	eq(okV, false)
	ok(tostring(why):find("^conflict:1:") ~= nil, tostring(why))
	-- a crosswalk green with a fan touching its arm: refused too
	local cwIdx = M.n -- crosswalk 1
	local locked2 = {}
	for _, l in ipairs(st.locked) do if l ~= cwIdx then locked2[#locked2 + 1] = l end end
	local bad2 = { states = { { locked = locked2, duration = 20, minDuration = 0, canSkip = false } } }
	for s = 2, #plan.states do bad2.states[s] = plan.states[s] end
	local okV2, why2 = PP.validatePlan(M, bad2, M.n, M.nCross, { fan = true })
	eq(okV2, false)
	ok(tostring(why2):find(":ped$") ~= nil, tostring(why2))
end)

test("fan plans: index range property over templates, shapes, sides and crosswalk kinds", function()
	local n = 0
	for _, tpl in ipairs({ F.TPL.small, F.TPL.medium, F.TPL.large }) do
		for _, side in ipairs({ F.TPL.small, F.TPL.medium, F.TPL.large }) do
			for _, t in ipairs({ false, true }) do
				for _, mir in ipairs({ false, true }) do
					for _, cwKind in ipairs({ "edges", "unknown", "none", "partial" }) do
						local v, world = crossing(t, mir, tpl, side)
						local conns = Cross.fanConns(v)
						local cws = nil
						if cwKind == "unknown" then cws = { 1, 2 }
						elseif cwKind == "none" then cws = {}
						elseif cwKind == "partial" then cws = { 11, 13 } end
						local M, info = fanMap(v, world, conns, cws)
						local plan = PP.plan(M, info, { fan = true })
						checkFanPlan(M, plan, conns, "variant")
						if plan ~= nil then
							ok(PP.validatePlan(M, plan, M.n, M.nCross, { fan = true }))
							n = n + 1
						end
					end
				end
			end
		end
	end
	eq(n, 3 * 3 * 2 * 2 * 4)
end)

test("fan plan vs Smart Lanes / game lanes on the same 2x2 X: printed for the measurement notes", function()
	local v, world = crossing(false, false)
	for _, which in ipairs({ "rule", "default", "fan" }) do
		local conns = (which == "fan" and Cross.fanConns(v)) or (which == "default" and Cross.defaultConns(v)) or Slip.roadConns(v)
		local M, info = fanMap(v, world, conns)
		local plan = assert(PP.plan(M, info, which == "fan" and { fan = true } or nil))
		print(string.format("2x2 X %-7s conns=%3d %s", which, #conns, PP.planText(plan, #conns)))
	end
end)
