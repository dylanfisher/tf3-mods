-- square_smart_lanes: which junctions lose their traffic lights (sl_lights.lua, pure).

local L = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local E = { YES = 0, NO = 1, AUTO = 2 }

test("ringNodes: handled arm junctions only", function()
	local plan = { nodes = {
		{ node = 1, status = "apply", view = { kind = "arm" } },
		{ node = 2, status = "same", view = { kind = "arm" } },
		{ node = 3, status = "skip", view = { kind = "skip" } }, -- road through the centre keeps its lights
		{ node = 4, status = "untouched", view = { kind = "arm" } }, -- not part of this build
	} }
	eq(L.ringNodes(plan), { 1, 2 })
	eq(L.ringNodes({}), {})
end)

test("slipNode: apply and same, never skip or none", function()
	ok(L.slipNode({ status = "apply" }))
	ok(L.slipNode({ status = "same" }))
	ok(not L.slipNode({ status = "skip" }))
	ok(not L.slipNode({ status = "none" }))
	ok(not L.slipNode(nil))
	-- crossroads and plain lane drops / gains keep the game's lights
	ok(not L.slipNode({ status = "apply", view = { case = "X" } }))
	ok(not L.slipNode({ status = "apply", view = { case = "D" } }))
	ok(not L.slipNode({ status = "same", view = { case = "D" } }))
	ok(L.slipNode({ status = "apply", view = { case = "B" } }))
	ok(L.keepsLights("D") and L.keepsLights("X") and not L.keepsLights("A") and not L.keepsLights(nil))
end)

test("needs: off sends anything not NO or with a standing light; auto sends anything not AUTO", function()
	ok(L.needs({ pref = E.AUTO, light = false }, L.OFF, E))
	ok(L.needs({ pref = E.YES, light = true }, L.OFF, E))
	ok(L.needs({ pref = E.NO, light = true }, L.OFF, E), "light still standing")
	ok(not L.needs({ pref = E.NO, light = false }, L.OFF, E))
	ok(L.needs({ pref = E.NO }, L.AUTO, E))
	ok(not L.needs({ pref = E.AUTO, light = true }, L.AUTO, E))
	ok(not L.needs(nil, L.OFF, E), "no config")
	ok(not L.needs({ pref = E.AUTO }, L.OFF, nil), "no enum")
end)

test("prefFor / prefName", function()
	eq(L.prefFor(L.OFF, E), E.NO)
	eq(L.prefFor(L.AUTO, E), E.AUTO)
	eq(L.prefFor(L.OFF, nil), nil)
	eq(L.prefName(E.YES, E), "yes")
	eq(L.prefName(E.NO, E), "no")
	eq(L.prefName(E.AUTO, E), "auto")
	eq(L.prefName(7, E), "7")
end)

test("litOf: YES or AUTO with a light standing = lit; NO = unlit; AUTO without a light = unknown", function()
	eq(L.litOf({ pref = E.YES, light = false }, E), true, "YES: the game puts a light there")
	eq(L.litOf({ pref = E.YES, light = true }, E), true)
	eq(L.litOf({ pref = E.AUTO, light = true }, E), true, "AUTO with a light standing")
	eq(L.litOf({ pref = E.AUTO, light = false }, E), nil, "AUTO without a light: unknown (it may come)")
	eq(L.litOf({ pref = E.NO, light = false }, E), false, "NO")
	eq(L.litOf({ pref = E.NO, light = true }, E), false, "NO with a light still standing: going")
	eq(L.litOf(nil, E), nil, "no config")
	eq(L.litOf({ pref = E.NO }, nil), nil, "no enum")
	eq(L.litOf({ pref = 7, light = true }, E), true, "unknown preference value, light standing")
	eq(L.litOf({ pref = 7 }, E), nil)
	-- a partial enum (no NO) and a config without a preference: unknown, never unlit by nil == nil
	eq(L.litOf({ pref = nil, light = false }, { YES = 1, AUTO = 3 }), nil, "nil pref, enum without NO")
	eq(L.litOf({ pref = nil, light = true }, E), nil, "nil pref")
end)

---------------------------------------------------------------------------
-- Free kerb turn at traffic lights (L.kerbIndices, L.kerbPhases, sl_cross X.kerbPairs)

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

--- Crossroads at node 1 (as test_cross.lua crossing): 11 west, 12 east (main road), 13 north,
-- 14 south (side road; none when t). mirror: left-hand traffic.
local function crossing(t, mirror, main, side)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	local segs = { [11] = { 1, 2, main or F.TPL.medium }, [12] = { 1, 3, main or F.TPL.medium }, [13] = { 1, 4, side or F.TPL.medium } }
	if not t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, side or F.TPL.medium }
	end
	local world = F.build(nodes, segs, mirror)
	local v = Slip.classify(world, 1)
	assert(v.case == "X", "crossing fixture is case X")
	return v
end

local function keys(set)
	local out = {}
	for k in pairs(set or {}) do out[#out + 1] = k end
	table.sort(out)
	return table.concat(out, ",")
end

local function setOf(list)
	local s = {}
	for _, x in ipairs(list) do s[x] = true end
	return s
end

--- The game's default style of phases (findings.md: the kerb turn red together with its approach):
-- phase 1 = the main road (11, 12) goes, phase 2 = the side road (13, 14); every connection of the
-- other road is red, plus crosswalk 1 in phase 1 and crosswalk 2 in phase 2.
local function defaultPhases(conns, nCross)
	local p1, p2 = {}, {}
	for i, c in ipairs(conns) do
		if c.segment0 == 13 or c.segment0 == 14 then p1[#p1 + 1] = i - 1 else p2[#p2 + 1] = i - 1 end
	end
	if nCross >= 2 then
		p1[#p1 + 1] = #conns
		p2[#p2 + 1] = #conns + 1
	end
	return { p1, p2 }
end

test("kerbPairs: the kerb turn per approach, right in right-hand traffic, left in left-hand traffic; T and X", function()
	-- right-hand traffic: from the west (11, heading east) right is south (14), from the east (12) north
	-- (13), from the north (13) west (11), from the south (14) east (12). Mirrored (left-hand traffic,
	-- x -> -x): the same segments, the turn now to the left
	for _, mirror in ipairs({ false, true }) do
		local side = mirror and "left" or "right"
		local vx = crossing(false, mirror)
		eq(vx.side, side)
		local set, n = Cross.kerbPairs(vx)
		eq(keys(set), "11>14,12>13,13>11,14>12", "X " .. side)
		eq(n, 4)
		local vt = crossing(true, mirror)
		eq(keys(Cross.kerbPairs(vt)), "12>13,13>11", "T " .. side .. ": the main road's far approach has no kerb turn")
		eq(keys(Slip.kerbPairs(vt)), "12>13,13>11")
	end
	eq(Slip.kerbPairs({ case = "B" }), nil, "slip nodes: none")
	eq(Slip.kerbPairs(nil), nil)
	eq(keys(Cross.kerbPairs({})), "", "no approaches")
end)

test("kerbIndices: road connections of a kerb pair only; tram connections keep the signal", function()
	local conns = {
		Rules.conn(11, 1, 14, 3, true, false), -- kerb
		Rules.conn(11, 2, 12, 3, true, false), -- straight
		Rules.conn(11, 1, 14, 4, true, true),  -- kerb, road + tram
		Rules.conn(11, 1, 14, 3, false, true), -- kerb, tram only
		Rules.conn(12, 1, 13, 3, true, false), -- kerb
	}
	local kerb = { ["11>14"] = true, ["12>13"] = true }
	eq(L.kerbIndices(conns, kerb), { 0, 4 })
	eq(L.kerbIndices(conns, nil), {})
	eq(L.kerbIndices(nil, kerb), {})
end)

test("kerbPhases FREE: kerb turns out of every phase, crosswalks and the rest in place; T and X, both sides", function()
	for _, mirror in ipairs({ false, true }) do
		for _, t in ipairs({ false, true }) do
			local tag = (t and "T " or "X ") .. (mirror and "left" or "right")
			local v = crossing(t, mirror)
			local conns = Slip.roadConns(v)
			local nCross = 2
			local states = defaultPhases(conns, nCross)
			local idx = L.kerbIndices(conns, Cross.kerbPairs(v))
			ok(#idx > 0, tag .. ": kerb connections found")
			local isKerb = setOf(idx)
			local res, n, why = L.kerbPhases(conns, idx, nCross, states, L.FREE)
			eq(why, nil, tag)
			eq(#res, #states, tag .. ": no phase added or removed")
			eq(n, #idx, tag .. ": every kerb connection was red in a phase")
			for s, list in ipairs(res) do
				local want = {}
				for _, l in ipairs(states[s]) do
					if not isKerb[l] then want[#want + 1] = l end
				end
				eq(list, want, tag .. " phase " .. s .. ": only the kerb connections left, order kept")
				for _, l in ipairs(list) do ok(l >= 0 and l <= #conns + nCross - 1, tag .. " index in range") end
			end
			ok(setOf(res[1])[#conns] and setOf(res[2])[#conns + 1], tag .. ": crosswalk indices kept")
			-- every kerb connection is a turn towards the driving side, never straight or the far turn
			for _, j in ipairs(idx) do
				local c = conns[j + 1]
				local found = false
				for _, ap in ipairs(v.approaches) do
					if ap.seg == c.segment0 then
						for _, ex in ipairs(ap.allExits) do
							if ex.seg == c.segment1 then found = ex.cat == "kerb" end
						end
					end
				end
				ok(found, tag .. ": " .. Rules.connsText({ c }) .. " is a kerb turn")
			end
			-- already free: a no-op
			local again, n2 = L.kerbPhases(conns, idx, nCross, res, L.FREE)
			eq(again, res, tag .. ": already free")
			eq(n2, 0)
			-- LOCK puts them back where their approach is red (the game's default)
			local back, n3 = L.kerbPhases(conns, idx, nCross, res, L.LOCK)
			eq(n3, #idx, tag)
			for s = 1, #states do
				eq(keys(setOf(back[s])), keys(setOf(states[s])), tag .. " phase " .. s .. ": the default again")
			end
		end
	end
end)

test("kerbPhases: a phase left with nothing red is kept; LOCK leaves a lone kerb approach and green approaches alone", function()
	local conns = {
		Rules.conn(1, 1, 2, 1, true, false), -- kerb, the only connection of approach 1
		Rules.conn(3, 1, 4, 1, true, false), -- kerb of approach 3
		Rules.conn(3, 2, 5, 1, true, false), -- straight of approach 3
	}
	local idx = { 0, 1 }
	local res, n = L.kerbPhases(conns, idx, 0, { { 0 }, { 1, 2 }, {} }, L.FREE)
	eq(res, { {}, { 2 }, {} }, "phase 1 had only a kerb turn: kept, empty")
	eq(n, 2)
	-- LOCK: approach 1 has no other connection (left as it is); approach 3's kerb turn joins its
	-- straight's red only where that is red
	local back = L.kerbPhases(conns, idx, 0, { {}, { 2 }, {} }, L.LOCK)
	eq(back, { {}, { 2, 1 }, {} })
	local keep = L.kerbPhases(conns, idx, 0, { { 0 }, { 2, 1 } }, L.LOCK)
	eq(keep, { { 0 }, { 2, 1 } }, "already red: unchanged, no duplicate")
end)

test("kerbPhases: stale or bad input writes nothing; nothing to change is a no-op", function()
	local conns = { Rules.conn(1, 1, 2, 1, true, false), Rules.conn(1, 2, 3, 1, true, false) }
	local res, n, why = L.kerbPhases(conns, { 0 }, 1, { { 0, 3 } }, L.FREE)
	eq(res, nil)
	eq(n, 0)
	eq(why, "stale_phases", "index 3 is past 2 connections + 1 crosswalk")
	eq(select(3, L.kerbPhases(conns, { 0 }, 1, { { -1 } }, L.FREE)), "stale_phases", "negative index")
	eq(select(3, L.kerbPhases(conns, { 0 }, 1, { { 0.5 } }, L.FREE)), "stale_phases", "not an integer")
	eq(select(3, L.kerbPhases(conns, { 0 }, 1, { { 0 } }, "other")), "mode")
	-- a kerb index outside the connections (crosswalk 0-based 2) is ignored: crosswalks never change
	eq(L.kerbPhases(conns, { 2, 5 }, 1, { { 0, 2 } }, L.FREE), { { 0, 2 } })
	-- no kerb connection, no phases
	local same, n2 = L.kerbPhases(conns, {}, 1, { { 0, 1, 2 } }, L.FREE)
	eq(same, { { 0, 1, 2 } })
	eq(n2, 0)
	eq(L.kerbPhases(conns, { 0 }, 1, {}, L.FREE), {})
	eq(L.kerbPhases(conns, { 0 }, 1, nil, L.FREE), {})
end)

---------------------------------------------------------------------------
-- "When safe" (L.SAFE, L.kerbConflict): a kerb turn goes green only where nothing green conflicts

--- One phase per approach (only that approach's connections green), every crosswalk red unless
-- `greenCross` = { [phase approach] = {crosswalk numbers 1-based} }. Returns states, approaches.
local function perApproach(conns, nCross, approaches, greenCross)
	local states = {}
	for s, a in ipairs(approaches) do
		local list = {}
		for i, c in ipairs(conns) do
			if c.segment0 ~= a then list[#list + 1] = i - 1 end
		end
		local g = setOf((greenCross or {})[a] or {})
		for k = 1, nCross do
			if not g[k] then list[#list + 1] = #conns + k - 1 end
		end
		states[s] = list
	end
	return states
end

--- The category of movement a -> e in view v (sl_cross ap.allExits), nil when none.
local function catOf(v, a, e)
	for _, ap in ipairs(v.approaches) do
		if ap.seg == a then
			for _, ex in ipairs(ap.allExits) do
				if ex.seg == e then return ex.cat end
			end
		end
	end
	return nil
end

test("kerbPhases SAFE: X, one phase per approach: kerb turns go green everywhere, also where the green straight feeds their lane (merge allowed); both sides", function()
	for _, mirror in ipairs({ false, true }) do
		local tag = "X " .. (mirror and "left" or "right")
		local v = crossing(false, mirror)
		local conns = Slip.roadConns(v)
		local kerb = Cross.kerbPairs(v)
		local idx = L.kerbIndices(conns, kerb)
		eq(#idx, 4, tag .. ": one kerb connection per approach (2-lane roads)")
		local aps = { 11, 12, 13, 14 }
		-- crosswalks on the node's four roads, all red
		local ctx = { kerb = kerb, crosswalks = { 11, 12, 13, 14 } }
		local states = perApproach(conns, 4, aps)
		local res, n, why, st = L.kerbPhases(conns, idx, 4, states, L.SAFE, ctx)
		eq(why, nil, tag)
		eq(#res, 4, tag .. ": no phase added or removed")
		for s, a in ipairs(aps) do
			local red = setOf(res[s])
			for _, j in ipairs(idx) do
				local c = conns[j + 1]
				if c.segment0 == a then
					ok(not red[j], tag .. ": own approach's kerb turn stays green")
				elseif catOf(v, a, c.segment1) == "straight" then
					ok(not red[j], tag .. " phase " .. a .. ": " .. Rules.connsText({ c }) .. " green, merging into the green straight from " .. a)
				else
					ok(not red[j], tag .. " phase " .. a .. ": " .. Rules.connsText({ c }) .. " green (" .. tostring(catOf(v, a, c.segment1)) .. " from " .. a .. " ends in another lane)")
				end
			end
			-- every other index stays: the other approaches' connections and all crosswalks
			local want = {}
			for _, l in ipairs(states[s]) do
				local c = conns[l + 1]
				local isK = false
				for _, j in ipairs(idx) do if j == l then isK = true end end
				if not isK then want[#want + 1] = l end
			end
			local got = {}
			for _, l in ipairs(res[s]) do
				local isK = false
				for _, j in ipairs(idx) do if j == l then isK = true end end
				if not isK then got[#got + 1] = l end
			end
			eq(got, want, tag .. " phase " .. s .. ": non-kerb indices and crosswalks in place, order kept")
			for k = 1, 4 do ok(red[#conns + k - 1], tag .. ": crosswalk " .. k .. " still red") end
		end
		eq(n, 4, tag .. ": every kerb connection freed in some phase")
		eq(st.phases, 12, tag .. ": the three other approaches' phases each")
		eq({ st.merge, st.cross, st.ped }, { 0, 0, 0 }, tag .. ": nothing kept red")
		eq(st.merged, 4, tag .. ": one phase per kerb turn with a green straight into its lane")
		eq(L.keptText(st), "-")
		-- again: nothing more to change
		local again, n2 = L.kerbPhases(conns, idx, 4, res, L.SAFE, ctx)
		eq(again, res, tag .. ": idempotent")
		eq(n2, 0)
		-- Always (FREE) frees the merging ones too: the old behaviour
		local all = L.kerbPhases(conns, idx, 4, states, L.FREE)
		for s = 1, 4 do
			for _, j in ipairs(idx) do ok(not setOf(all[s])[j], tag .. ": Always frees every phase") end
		end
	end
end)

test("kerbPhases SAFE: T with the game's phases: the side road's kerb turn goes green with the main road's straight it merges into", function()
	for _, mirror in ipairs({ false, true }) do
		local tag = "T " .. (mirror and "left" or "right")
		local v = crossing(true, mirror)
		local conns = Slip.roadConns(v)
		local kerb = Cross.kerbPairs(v)
		local idx = L.kerbIndices(conns, kerb)
		-- crosswalk 1 on the side road (13), 2 on the west arm (11), 3 on the east arm (12): all red
		local states = defaultPhases(conns, 0)
		for _, list in ipairs(states) do
			for k = 1, 3 do list[#list + 1] = #conns + k - 1 end
		end
		local ctx = { kerb = kerb, crosswalks = { 13, 11, 12 } }
		local res, n, _, st = L.kerbPhases(conns, idx, 3, states, L.SAFE, ctx)
		local side, main = {}, {}
		for _, j in ipairs(idx) do
			if conns[j + 1].segment0 == 13 then side[#side + 1] = j else main[#main + 1] = j end
		end
		ok(#side > 0 and #main > 0, tag)
		-- phase 1 (main road green): the side road's kerb turn into 11 merges into 12's straight -> green
		for _, j in ipairs(side) do ok(not setOf(res[1])[j], tag .. ": side kerb turn green in the main road's phase") end
		-- phase 2 (side road green): the main road's kerb turn into 13: nothing green ends there -> green
		for _, j in ipairs(main) do ok(not setOf(res[2])[j], tag .. ": main kerb turn green in the side road's phase") end
		eq(n, #main + #side, tag)
		eq({ st.merge, st.cross, st.ped }, { 0, 0, 0 }, tag)
		eq(st.merged, #side, tag .. ": the side road's turns merged")
		eq(#res, 2)
	end
end)

test("kerbPhases SAFE: a green crosswalk on the approach or the exit keeps the kerb turn red; others do not", function()
	local v = crossing(false, false)
	local conns = Slip.roadConns(v)
	local kerb = Cross.kerbPairs(v)
	local idx = L.kerbIndices(conns, kerb)
	local aps = { 11, 12, 13, 14 }
	local function kerbOf(a)
		for _, j in ipairs(idx) do if conns[j + 1].segment0 == a then return j, conns[j + 1].segment1 end end
	end
	-- in 13's phase the kerb turns 12>13 and 14>12 go green (see the X test): now a green crosswalk
	local j12, e12 = kerbOf(12) -- 12 -> 13
	local j14, e14 = kerbOf(14) -- 14 -> 12
	eq({ e12, e14 }, { 13, 12 })
	local function run(cws, green)
		local states = perApproach(conns, #cws, aps, { [13] = green })
		local res, _, _, st = L.kerbPhases(conns, idx, #cws, states, L.SAFE, { kerb = kerb, crosswalks = cws })
		return setOf(res[3]), st, res, states
	end
	-- crosswalk entities = the four roads; crosswalk 2 = road 12
	local red, st = run({ 11, 12, 13, 14 }, { 2 })
	ok(red[j12], "12's kerb turn drives over the crosswalk on its own road 12 (A)")
	ok(red[j14], "14's kerb turn drives over the crosswalk on road 12 (E)")
	eq(st.ped, 2)
	red = run({ 11, 12, 13, 14 }, { 3 }) -- road 13: 12's exit
	ok(red[j12], "crosswalk on 12's exit 13 green: red")
	ok(not red[j14], "14 -> 12 does not cross road 13: green")
	red = run({ 11, 12, 13, 14 }, { 1 }) -- road 11: neither
	ok(not red[j12] and not red[j14], "a crosswalk on another road: no conflict")
	-- a crosswalk entity that is none of the node's roads: every kerb turn stays red (conservative)
	red, st = run({ 11, 12, 13, 999 }, { 4 })
	ok(red[j12] and red[j14], "unmapped crosswalk green: red")
	ok(st.ped >= 2)
	-- a missing crosswalk list counts as unmapped
	local states = perApproach(conns, 2, aps, { [13] = { 1 } })
	local res = L.kerbPhases(conns, idx, 2, states, L.SAFE, { kerb = kerb })
	ok(setOf(res[3])[j12] and setOf(res[3])[j14], "no crosswalk entities: green crosswalk keeps them red")
	-- crosswalk indices themselves never change, in any mode
	for _, mode in ipairs({ L.SAFE, L.FREE, L.LOCK }) do
		local _, _, sts = run({ 11, 12, 13, 14 }, { 2 })
		local r2 = L.kerbPhases(conns, idx, 4, sts, mode, { kerb = kerb, crosswalks = { 11, 12, 13, 14 } })
		for s = 1, #sts do
			for k = 1, 4 do
				eq(setOf(r2[s])[#conns + k - 1] == true, setOf(sts[s])[#conns + k - 1] == true, mode .. ": crosswalk " .. k .. " phase " .. s)
			end
		end
	end
end)

test("kerbPhases SAFE: lane order: a stream into a lane nearer the kerb crosses, one farther out does not; trams count; no order = conservative", function()
	-- kerb turn 1 -> 2 into exit lane 7 (position 2); exit 2's lanes kerb first: 6, 7, 8
	local kerb = { ["1>2"] = { [6] = 1, [7] = 2, [8] = 3 } }
	local function run(other, k)
		local conns = { Rules.conn(1, 1, 2, 7, true, false), other }
		local res, n, _, st = L.kerbPhases(conns, { 0 }, 0, { { 0 } }, L.SAFE, { kerb = k or kerb, crosswalks = {} })
		return res[1], n, st
	end
	local r, n, st = run(Rules.conn(3, 1, 2, 7, true, false))
	eq({ r, n, st.merge, st.merged }, { {}, 1, 0, 1 }, "same lane: merge, allowed: green, counted as merged")
	r, n, st = run(Rules.conn(3, 1, 2, 6, true, false))
	eq({ r, n, st.cross }, { { 0 }, 0, 1 }, "a lane nearer the kerb: the turner crosses it, red")
	r, n = run(Rules.conn(3, 1, 2, 8, true, false))
	eq({ r, n }, { {}, 1 }, "a lane farther out: beside it, green")
	r, n, st = run(Rules.conn(3, 1, 2, 7, false, true))
	eq({ r, n, st.merge, st.merged }, { {}, 1, 0, 1 }, "a tram into the same lane: merge, green")
	r, n = run(Rules.conn(1, 2, 2, 7, true, false))
	eq({ r, n }, { {}, 1 }, "the kerb turn's own approach: never a conflict")
	r, n = run(Rules.conn(3, 1, 4, 7, true, false))
	eq({ r, n }, { {}, 1 }, "another exit: no conflict")
	-- no lane order known (value true): every other green lane of the exit counts
	r, n, st = run(Rules.conn(3, 1, 2, 8, true, false), { ["1>2"] = true })
	eq({ r, n, st.cross }, { { 0 }, 0, 1 }, "no order: conservative")
	-- a red stream is no conflict
	local conns = { Rules.conn(1, 1, 2, 7, true, false), Rules.conn(3, 1, 2, 7, true, false) }
	eq(L.kerbPhases(conns, { 0 }, 0, { { 0, 1 } }, L.SAFE, { kerb = kerb }), { { 1 } }, "the merging stream red: green")
	-- a kerb turn freed earlier in the phase counts as green for the next one into the same lane
	local two = { Rules.conn(1, 1, 2, 7, true, false), Rules.conn(3, 1, 2, 7, true, false), Rules.conn(9, 1, 5, 1, true, false) }
	local both = { ["1>2"] = kerb["1>2"], ["3>2"] = kerb["1>2"] }
	local res, n2, _, st2 = L.kerbPhases(two, { 0, 1 }, 0, { { 0, 1 } }, L.SAFE, { kerb = both })
	eq({ res[1], n2, st2.merge }, { {}, 2, 0 }, "two kerb turns into one lane: a merge, both go green")
	-- a merge and a crossing at once: the crossing keeps it red (kept as cross, not merged)
	local three = { Rules.conn(1, 1, 2, 7, true, false), Rules.conn(3, 1, 2, 7, true, false), Rules.conn(4, 1, 2, 6, true, false) }
	local r3, n3, _, st3 = L.kerbPhases(three, { 0 }, 0, { { 0 } }, L.SAFE, { kerb = kerb })
	eq({ r3[1], n3, st3.cross, st3.merged }, { { 0 }, 0, 1, 0 }, "merge + cross: red as a crossing")
end)

test("kerbPhases SAFE: two kerb turns into one exit never both go green across each other, in either order", function()
	-- exit 2's lanes kerb first: 6, 7. Kerb turn 1 -> 2:7 and kerb turn 3 -> 2:6 (kerbward of 7):
	-- 1 -> 2:7 would cross 3 -> 2:6; 3 -> 2:6 alone sees 1 -> 2:7 farther out (one-sided)
	local ord = { [6] = 1, [7] = 2 }
	local kerb = { ["1>2"] = ord, ["3>2"] = ord }
	local a, b = Rules.conn(1, 1, 2, 7, true, false), Rules.conn(3, 1, 2, 6, true, false)
	for _, order in ipairs({ { a, b }, { b, a } }) do
		local res, n, _, st = L.kerbPhases(order, { 0, 1 }, 0, { { 0, 1 } }, L.SAFE, { kerb = kerb })
		eq({ #res[1], n, st.cross }, { 1, 1, 1 }, "exactly one freed, the other kept red as a crossing")
	end
end)

test("kerbDiff: kerb connections and (connection, phase) pairs whose red differs", function()
	eq({ L.kerbDiff({ 0, 1 }, { { 0, 1 }, { 0 } }, { { 1 }, { 0 } }) }, { 1, 1 })
	eq({ L.kerbDiff({ 0, 1 }, { { 0 }, { 1 } }, { { 1 }, { 0 } }) }, { 2, 4 })
	eq({ L.kerbDiff({ 0 }, { { 0 } }, { { 0 } }) }, { 0, 0 })
	eq({ L.kerbDiff(nil, nil, nil) }, { 0, 0 })
end)

test("kerbPhases SAFE: stale input refused, already-green kept, empty phases kept", function()
	local conns = { Rules.conn(1, 1, 2, 1, true, false), Rules.conn(3, 1, 4, 1, true, false) }
	local kerb = { ["1>2"] = true }
	eq(select(3, L.kerbPhases(conns, { 0 }, 1, { { 0, 3 } }, L.SAFE, { kerb = kerb })), "stale_phases")
	eq(select(3, L.kerbPhases(conns, { 0 }, 1, { { -1 } }, L.SAFE, { kerb = kerb })), "stale_phases")
	local res, n = L.kerbPhases(conns, { 0 }, 1, { {}, { 1, 2 }, { 0, 1, 2 } }, L.SAFE, { kerb = kerb, crosswalks = { 3 } })
	eq(res, { {}, { 1, 2 }, { 1, 2 } }, "phase 1 empty stays; phase 2 already green; phase 3 freed")
	eq(n, 1)
	eq(L.kerbPhases(conns, { 0 }, 1, {}, L.SAFE), {})
	eq(L.kerbPhases(conns, { 0 }, 1, nil, L.SAFE), {})
end)

test("kerbPhases SAFE: in-game node 381095 (log 2026-10-12): the south kerb turn merging with a green straight goes green; cross and ped still red; both sides", function()
	-- [SQRL] PROBE phases node=381095: arms A=381154@0 (east, 2+2 lanes), B=381149@90, C=381147@180,
	-- D=381148@270 (3+3 each), crosswalks=381147 (one, west arm C); phases_conns list (config order):
	-- C1>D6,B3>D4,B2>D5,A2>D4,D1>A4,C3>A3,C2>A4,B3>A3,A1>B6,D3>B4,D2>B5,C3>B4,B1>C6,A2>C4,A1>C5,D3>C4;
	-- phase 1 locked=1,2,4,9,10,15,16. Kerb turns (right turns): 0 C1>D6, 4 D1>A4, 8 A1>B6, 12 B1>C6.
	-- D1>A4 ends in A's kerb lane 4, where the green straight 6 C2>A4 also ends: a merge.
	local A, B, C, D = 381154, 381149, 381147, 381148
	local seg = { A = A, B = B, C = C, D = D }
	local lanes = { [A] = 4, [B] = 6, [C] = 6, [D] = 6 }
	local list = "C1>D6,B3>D4,B2>D5,A2>D4,D1>A4,C3>A3,C2>A4,B3>A3,A1>B6,D3>B4,D2>B5,C3>B4,B1>C6,A2>C4,A1>C5,D3>C4"
	-- the outgoing lanes kerb first (right-hand traffic: the highest index is the kerb lane)
	local out = { [A] = { 4, 3 }, [B] = { 6, 5, 4 }, [C] = { 6, 5, 4 }, [D] = { 6, 5, 4 } }
	for _, mirror in ipairs({ false, true }) do
		local tag = "381095 " .. (mirror and "left (mirrored)" or "right")
		-- mirrored (x -> -x, left-hand traffic): the same segments and kerb pairs, lane indices reversed
		local function ln(s, l) return mirror and (lanes[s] + 1 - l) or l end
		local conns = {}
		for a, la, e, le in list:gmatch("(%u)(%d)>(%u)(%d)") do
			local s0, s1 = seg[a], seg[e]
			conns[#conns + 1] = Rules.conn(s0, ln(s0, tonumber(la)), s1, ln(s1, tonumber(le)), true, false)
		end
		eq(#conns, 16, tag)
		local function ord(e)
			local o = {}
			for p, l in ipairs(out[e]) do o[ln(e, l)] = p end
			return o
		end
		local kerb = { [C .. ">" .. D] = ord(D), [D .. ">" .. A] = ord(A), [A .. ">" .. B] = ord(B), [B .. ">" .. C] = ord(C) }
		local idx = L.kerbIndices(conns, kerb)
		eq(idx, { 0, 4, 8, 12 }, tag .. ": kerb turns")
		local phase1 = { 1, 2, 4, 9, 10, 15, 16 }
		-- merge: freed (the user's decision), counted as merged
		local res, n, why, st = L.kerbPhases(conns, idx, 1, { phase1 }, L.SAFE, { kerb = kerb, crosswalks = { C } })
		eq(why, nil, tag)
		eq(res[1], { 1, 2, 9, 10, 15, 16 }, tag .. ": D1>A4 green in phase 1, the rest as read")
		eq({ n, st.phases, st.merged, st.merge, st.cross, st.ped }, { 1, 1, 1, 0, 0, 0 }, tag .. ": one merge freed")
		eq(L.keptText(st), "-", tag)
		-- ped: the crosswalk on A (D1>A4's exit) green in the phase: red
		local p2 = { 1, 2, 4, 9, 10, 15 }
		res, n, _, st = L.kerbPhases(conns, idx, 1, { p2 }, L.SAFE, { kerb = kerb, crosswalks = { A } })
		eq({ res[1], n, st.ped, st.merged }, { p2, 0, 1, 0 }, tag .. ": green crosswalk on its exit: red")
		-- the crosswalk on C (none of D1>A4's roads) green: it goes (merging)
		res, n = L.kerbPhases(conns, idx, 1, { p2 }, L.SAFE, { kerb = kerb, crosswalks = { C } })
		eq({ res[1], n }, { { 1, 2, 9, 10, 15 }, 1 }, tag .. ": green crosswalk elsewhere: green")
		-- cross: D1>A4 moved to A's inner lane 3 (synthetic): the green straight C2>A4 ends kerbward of
		-- it, so the turner would cut across it (C3>A3 merging as well): red, kept as a crossing
		local moved = {}
		for i, c in ipairs(conns) do moved[i] = c end
		moved[5] = Rules.conn(D, ln(D, 1), A, ln(A, 3), true, false)
		res, n, _, st = L.kerbPhases(moved, idx, 1, { phase1 }, L.SAFE, { kerb = kerb, crosswalks = { C } })
		eq({ res[1], n, st.cross, st.merged }, { phase1, 0, 1, 0 }, tag .. ": a green stream nearer the kerb: red")
		eq(L.keptText(st), "cross:1", tag)
		-- Always frees all three cases
		eq(L.kerbPhases(moved, idx, 1, { phase1 }, L.FREE), { { 1, 2, 9, 10, 15, 16 } }, tag .. ": Always")
	end
end)

test("kerbPhases with kerbLaneOnly (the exit fan): only the kerb-lane connection is freed, the others stay red with their approach", function()
	local function c(a, l0, b, l1) return { segment0 = a, lane0 = l0, segment1 = b, lane1 = l1, withRoad = true, withTram = false } end
	-- approach 1: kerb turn into exit 2 (lane 4 = kerb lane, lane 3 = far lane), straight to 3; approach 5 straight
	-- into exit 2 (both lanes); phase 1: approach 1 green; phase 2: approach 5 green; one crosswalk (index 5)
	local conns = { c(1, 1, 2, 4), c(1, 1, 2, 3), c(1, 1, 3, 4), c(5, 1, 2, 4), c(5, 2, 2, 3) }
	local pos = { [4] = 1, [3] = 2 }
	local plain = { ["1>2"] = pos }
	local only = { ["1>2"] = pos, kerbLaneOnly = true }
	local states = { { 3, 4, 5 }, { 0, 1, 2 } }
	eq({ L.splitKerb(conns, { 0, 1 }, only) }, { { 0 }, { 1 } })
	eq({ L.splitKerb(conns, { 0, 1 }, plain) }, { { 0, 1 }, {} }, "without the flag: every kerb connection")
	eq({ L.splitKerb(conns, { 0, 1 }, { ["1>2"] = true, kerbLaneOnly = true }) }, { { 0, 1 }, {} }, "no positions: as before")
	-- FREE: today every kerb connection leaves every phase; with the flag only 0, 1 stays red in phase 2
	local idx = L.kerbIndices(conns, only)
	eq(idx, { 0, 1 })
	eq((L.kerbPhases(conns, idx, 1, states, L.FREE, { kerb = plain })), { { 3, 4, 5 }, { 2 } })
	eq((L.kerbPhases(conns, idx, 1, states, L.FREE, { kerb = only })), { { 3, 4, 5 }, { 1, 2 } })
	-- held one freed before (a hand edit): locked back with its approach
	eq((L.kerbPhases(conns, idx, 1, { { 3, 4, 5 }, { 2 } }, L.FREE, { kerb = only })), { { 3, 4, 5 }, { 2, 1 } })
	-- SAFE: the kerb-lane one merges with approach 5's straight in phase 2 (allowed) unless the crosswalk is green
	local safe = L.kerbPhases(conns, idx, 1, { { 3, 4, 5 }, { 0, 1, 2, 5 } }, L.SAFE, { kerb = only, crosswalks = { 1 } })
	eq(safe, { { 3, 4, 5 }, { 1, 2, 5 } }, "SAFE frees 0 only; 1 (into the far lane, crossing 5's straight into lane 4) stays red")
	-- LOCK: every kerb connection, as before
	eq((L.kerbPhases(conns, idx, 1, { { 3, 4, 5 }, { 2 } }, L.LOCK, { kerb = only })),
		(L.kerbPhases(conns, idx, 1, { { 3, 4, 5 }, { 2 } }, L.LOCK, { kerb = plain })))
	-- indices stay in range, stale input refused as ever
	eq({ L.kerbPhases(conns, idx, 1, { { 9 } }, L.FREE, { kerb = only }) }, { nil, 0, "stale_phases" })
end)

test("splitKerb fails closed: a kerb connection into a lane the positions do not list is held", function()
	local function c(a, l0, b, l1) return { segment0 = a, lane0 = l0, segment1 = b, lane1 = l1, withRoad = true, withTram = false } end
	local conns = { c(1, 1, 2, 4), c(1, 1, 2, 9), c(1, 1, 2, 3) }
	local only = { ["1>2"] = { [4] = 1, [3] = 2 }, kerbLaneOnly = true }
	eq({ L.splitKerb(conns, { 0, 1, 2 }, only) }, { { 0 }, { 1, 2 } })
	eq({ L.splitKerb(conns, { 0, 1, 2, 7 }, only) }, { { 0 }, { 1, 2, 7 } }, "an index without a connection: held")
	-- without the flag nothing changes
	eq({ L.splitKerb(conns, { 0, 1, 2 }, { ["1>2"] = { [4] = 1, [3] = 2 } }) }, { { 0, 1, 2 }, {} })
end)
