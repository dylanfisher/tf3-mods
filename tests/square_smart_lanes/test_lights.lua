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
-- 14 south (side road; none when t). mirror: left-hand traffic. Default roads: 3 lanes each way
-- (town_new_large), whose kerb lane only turns (sl_cross): a dedicated kerb lane, so the kerb turn may be
-- freed. On 1- and 2-lane roads the kerb lane goes straight too: shared, never freed (L.sharedKerb).
local function crossing(t, mirror, main, side)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	local segs = { [11] = { 1, 2, main or F.TPL.large }, [12] = { 1, 3, main or F.TPL.large }, [13] = { 1, 4, side or F.TPL.large } }
	if not t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, side or F.TPL.large }
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

test("kerbPhases SAFE: X, one phase per approach: dedicated kerb turns go green everywhere, also where the green straight feeds their lane (merge allowed); shared-lane ones stay with their lane; both sides", function()
	for _, mirror in ipairs({ false, true }) do
		local tag = "X " .. (mirror and "left" or "right")
		-- main road 3 lanes each way (kerb lane turns only: dedicated), side road 2 lanes (kerb lane also
		-- goes straight: shared). The main road's kerb turn into the side road ends in its kerb lane, where
		-- the opposite side approach's straight ends too: a merge
		local v = crossing(false, mirror, F.TPL.large, F.TPL.medium)
		local conns = Slip.roadConns(v)
		local kerb = Cross.kerbPairs(v)
		local idx = L.kerbIndices(conns, kerb)
		eq(#idx, 4, tag .. ": one kerb connection per approach")
		local _, sharedIdx = L.sharedKerb(conns, idx)
		local isShared = setOf(sharedIdx)
		for _, j in ipairs(idx) do
			local a = conns[j + 1].segment0
			eq(isShared[j] == true, a == 13 or a == 14, tag .. ": " .. Rules.connsText({ conns[j + 1] }) .. " shared only on the 2-lane side road")
		end
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
				elseif isShared[j] then
					ok(red[j], tag .. " phase " .. a .. ": " .. Rules.connsText({ c }) .. " red: its lane's straight is red (shared lane)")
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
		eq(n, 2, tag .. ": the two dedicated kerb connections freed in some phase")
		eq(st.phases, 6, tag .. ": the three other approaches' phases each")
		eq({ st.merge, st.cross, st.ped }, { 0, 0, 0 }, tag .. ": nothing kept red by a conflict")
		eq(st.merged, 2, tag .. ": one phase per dedicated kerb turn with a green straight into its lane")
		eq(st.shared, 2, tag .. ": the side road's two shared-lane kerb turns held")
		eq(L.keptText(st), "-")
		-- again: nothing more to change
		local again, n2 = L.kerbPhases(conns, idx, 4, res, L.SAFE, ctx)
		eq(again, res, tag .. ": idempotent")
		eq(n2, 0)
		-- Always (FREE) frees the dedicated ones in every phase; shared-lane ones stay with their lane
		local all, nAll, _, stAll = L.kerbPhases(conns, idx, 4, states, L.FREE)
		for s, a in ipairs(aps) do
			for _, j in ipairs(idx) do
				local own = conns[j + 1].segment0 == a
				eq(setOf(all[s])[j] == true, isShared[j] == true and not own, tag .. ": Always: dedicated green in every phase, shared red with its lane")
			end
		end
		eq({ nAll, stAll.shared }, { 2, 2 }, tag .. ": Always")
	end
end)

test("kerbPhases SAFE: T with the game's phases: the side road's kerb turn goes green with the main road's straight it merges into; the main road's shared-lane one stays with its lane", function()
	for _, mirror in ipairs({ false, true }) do
		local tag = "T " .. (mirror and "left" or "right")
		-- 2-lane roads: the side road's kerb lane turns only (dedicated), the main road's kerb lane goes
		-- straight too (shared)
		local v = crossing(true, mirror, F.TPL.medium, F.TPL.medium)
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
		-- phase 2 (side road green): the main road's kerb turn into 13 shares its lane with 12's straight,
		-- red there: stays red (before 2026-10-14 it went green, nothing green ending in 13)
		for _, j in ipairs(main) do ok(setOf(res[2])[j], tag .. ": main kerb turn red with its lane in the side road's phase") end
		eq(n, #side, tag)
		eq({ st.merge, st.cross, st.ped }, { 0, 0, 0 }, tag)
		eq(st.merged, #side, tag .. ": the side road's turns merged")
		eq(st.shared, #main, tag .. ": the main road's kerb turn held with its lane")
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
	-- (the straight from lane 2: the kerb lane 1 is a dedicated kerb lane, else nothing is freed: L.sharedKerb)
	local conns = { c(1, 1, 2, 4), c(1, 1, 2, 3), c(1, 2, 3, 4), c(5, 1, 2, 4), c(5, 2, 2, 3) }
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

test("sharedKerb: a kerb turn whose entry lane carries another movement (straight, far, tram, bus) is shared; other kerb turns are no mates", function()
	local function c(a, l0, b, l1, road, tram)
		return { segment0 = a, lane0 = l0, segment1 = b, lane1 = l1, withRoad = road ~= false, withTram = tram == true }
	end
	local conns = {
		c(1, 1, 2, 4),            -- 0 kerb, lane 1 of 1: shares with 1 (straight)
		c(1, 1, 3, 4),            -- 1 straight from the same lane
		c(5, 1, 6, 4),            -- 2 kerb, lane 1 of 5: alone (dedicated)
		c(5, 2, 7, 4),            -- 3 straight from lane 2
		c(8, 1, 9, 4),            -- 4 kerb, lane 1 of 8: a tram goes straight from it
		c(8, 1, 10, 4, false, true), -- 5 tram
		c(11, 1, 12, 4),          -- 6 kerb into exit lane 4 and
		c(11, 1, 12, 3),          -- 7 into exit lane 3 (exit fan): both kerb, dedicated
		c(13, 0, 14, 0, false, false), -- 8 neither road nor tram (a walkway): ignored
		c(13, 1, 14, 4),          -- 9 kerb, its lane has only the walkway's segment (other lane): dedicated
	}
	local idx = { 0, 2, 4, 6, 7, 9 }
	local ded, sh, mates = L.sharedKerb(conns, idx)
	eq(ded, { 2, 6, 7, 9 })
	eq(sh, { 0, 4 })
	eq(mates[0], { 1 })
	eq(mates[4], { 5 }, "a tram straight from the lane shares it (trams keep the signal)")
	-- only a part of the kerb set asked (the exit fan's free ones): the others still count as kerb, no mates
	eq({ L.sharedKerb(conns, { 6 }) }, { {}, { 6 }, { [6] = { 7 } } }, "without the full set the other kerb connection looks like a mate")
	eq({ L.sharedKerb(conns, { 6 }, idx) }, { { 6 }, {}, {} })
	eq({ L.sharedKerb(nil, nil) }, { {}, {}, {} })
	eq({ L.sharedKerb(conns, { 42 }) }, { {}, {}, {} }, "an unknown index is left out")
	-- freeable: the exit fan's free ones on a dedicated lane
	local only = { ["11>12"] = { [4] = 1, [3] = 2 }, ["1>2"] = true, kerbLaneOnly = true }
	eq(L.freeable(conns, { 0, 6, 7 }, only), { 6 }, "0 shared; 7 into the far lane held by the exit fan")
end)

test("kerbPhases beside a bus lane (a player's report 2026-10-14): a dedicated kerb turn is freed only in phases where its approach's bus lane is green; When safe and Always", function()
	local function c(a, l0, b, l1) return { segment0 = a, lane0 = l0, segment1 = b, lane1 = l1, withRoad = true, withTram = false } end
	local conns = {
		c(1, 1, 3, 6), -- 0 bus lane 1 of approach 1, straight on
		c(1, 2, 2, 4), -- 1 kerb turn from the dedicated kerb car lane 2
		c(1, 3, 3, 5), -- 2 straight from car lane 3
		c(3, 2, 1, 5), -- 3 the opposite straight
	}
	local states = {
		{ 3 },       -- approach 1 green, bus lane too
		{ 0, 1, 2 }, -- the opposite approach only: bus lane red
		{ 1, 2, 3 }, -- the bus lane alone
	}
	local bus = { [1] = { [1] = true }, [3] = { [6] = true } }
	local withBus = { kerb = { ["1>2"] = true, bus = bus }, crosswalks = {} }
	local noBus = { kerb = { ["1>2"] = true }, crosswalks = {} }
	local idx = L.kerbIndices(conns, withBus.kerb)
	eq(idx, { 1 }, "the bus straight is no kerb turn")
	for _, mode in ipairs({ L.SAFE, L.FREE }) do
		local res = L.kerbPhases(conns, idx, 0, states, mode, withBus)
		eq(res, { { 3 }, { 0, 1, 2 }, { 2, 3 } }, mode .. ": freed only where the bus lane is green")
		local plain = L.kerbPhases(conns, idx, 0, states, mode, noBus)
		eq(plain, { { 3 }, { 0, 2 }, { 2, 3 } }, mode .. ": without a bus lane freed in every phase")
		-- left-hand traffic numbering (bus lane on the other side, index 4): the same
		local lht = {
			c(1, 4, 3, 1), c(1, 3, 2, 1), c(1, 2, 3, 2), c(3, 3, 1, 2),
		}
		local ctxL = { kerb = { ["1>2"] = true, bus = { [1] = { [4] = true }, [3] = { [1] = true } } }, crosswalks = {} }
		eq(L.kerbPhases(lht, L.kerbIndices(lht, ctxL.kerb), 0, states, mode, ctxL), { { 3 }, { 0, 1, 2 }, { 2, 3 } }, mode .. " left")
	end
	-- LOCK (Reset) is unchanged: red where every other road connection of the approach (the bus lane's too) is red
	eq(L.kerbPhases(conns, idx, 0, { {}, { 0, 2 }, { 2, 3 } }, L.LOCK, withBus), { {}, { 0, 2, 1 }, { 2, 3 } })
end)

test("1-lane crossroads (a player's report 2026-10-14): no kerb turn is freed, When safe or Always; one freed earlier goes back with its lane; with bus lanes too; both sides", function()
	for _, mirror in ipairs({ false, true }) do
		for _, case in ipairs({ { "1-lane", F.TPL.small, F.TPL.small }, { "bus-lane main road", F.TPL.medium_bus, F.TPL.small } }) do
			local tag = case[1] .. (mirror and " left" or " right")
			local v = crossing(false, mirror, case[2], case[3])
			local conns = Slip.roadConns(v)
			local kerb = Cross.kerbPairs(v)
			local idx = L.kerbIndices(conns, kerb)
			eq(#idx, 4, tag .. ": a kerb turn per approach")
			local ded, sh = L.sharedKerb(conns, idx)
			eq({ #ded, #sh }, { 0, 4 }, tag .. ": every kerb turn shares its approach's one car lane")
			local aps = { 11, 12, 13, 14 }
			local states = perApproach(conns, 4, aps)
			local ctx = { kerb = kerb, crosswalks = { 11, 12, 13, 14 } }
			for _, mode in ipairs({ L.SAFE, L.FREE }) do
				local res, n, why, st = L.kerbPhases(conns, idx, 4, states, mode, ctx)
				eq(why, nil, tag)
				eq(n, 0, tag .. " " .. mode .. ": nothing freed")
				eq(res, states, tag .. " " .. mode .. ": phases as they were")
				eq(st.shared, 4, tag .. " " .. mode .. ": shared_held")
				eq(st.merged, 0, tag)
				-- a kerb turn freed earlier (Always before 2026-10-14, or by hand): red again where its lane is red
				local freed = {}
				for s, list in ipairs(states) do
					freed[s] = {}
					for _, l in ipairs(list) do
						if l ~= idx[1] then freed[s][#freed[s] + 1] = l end
					end
				end
				local back, n2 = L.kerbPhases(conns, idx, 4, freed, mode, ctx)
				eq(n2, 1, tag .. " " .. mode .. ": the freed one changed")
				for s = 1, #states do
					eq(setOf(back[s])[idx[1]] == true, setOf(states[s])[idx[1]] == true, tag .. " " .. mode .. " phase " .. s .. ": red exactly with its lane")
				end
			end
		end
	end
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
