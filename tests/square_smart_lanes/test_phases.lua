-- square_smart_lanes: conflict map of a lit junction's movements (sl_phases.lua, pure) and the
-- read-only PROBE phases dump (sl_write.lua W.probePhases).

local P = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local L = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local C = Rules.conn

--- Every conflict of M as a sorted "i-j:kind" list (i < j), for readable comparisons.
local function pairsText(M)
	local out = {}
	for i = 0, M.size - 1 do
		for _, c in ipairs(P.conflictsOf(M, i)) do
			if c[1] > i then out[#out + 1] = i .. "-" .. c[1] .. ":" .. c[2] end
		end
	end
	return out
end

--- Symmetric, never with itself.
local function checkSym(M, tag)
	for i = 0, M.size - 1 do
		eq(P.kind(M, i, i), nil, tag .. ": " .. i .. " with itself")
		for j = 0, M.size - 1 do
			if P.kind(M, i, j) ~= P.kind(M, j, i) then
				ok(false, tag .. ": asymmetric " .. i .. "/" .. j)
				return
			end
		end
	end
end

local function arms4(a0)
	a0 = a0 or 0
	return { { seg = 1, angle = a0 }, { seg = 2, angle = a0 + 90 }, { seg = 3, angle = a0 + 180 }, { seg = 4, angle = a0 + 270 } }
end

--- Mirror image (left-hand traffic): angles reflected, lane indices reversed per segment (lane
-- counts incl. sidewalks: total[seg]).
local function mirror(arms, conns, total)
	local a2, c2 = {}, {}
	for i, a in ipairs(arms) do a2[i] = { seg = a.seg, angle = 180 - a.angle } end
	for i, c in ipairs(conns) do
		c2[i] = C(c.segment0, total[c.segment0] - 1 - c.lane0, c.segment1, total[c.segment1] - 1 - c.lane1, c.withRoad, c.withTram)
	end
	return a2, c2
end

--- Hand-checked relative table: tbl[m][d][m'] = kind of movement m of approach a against movement
-- m' of the approach d arms counter-clockwise (d = 0..n-1); absent = no conflict. Builds the
-- connections of every approach (movement order `names`) with mk(a, m) and compares every pair.
local function checkTable(tag, names, mk, tbl, arms, nArms)
	local conns, who = {}, {}
	for a = 0, nArms - 1 do
		for _, m in ipairs(names) do
			conns[#conns + 1] = mk(a, m)
			who[#conns] = { a = a, m = m }
		end
	end
	local M = assert(P.build({ conns = conns, arms = arms }))
	checkSym(M, tag)
	for i = 1, #conns do
		for j = 1, #conns do
			if i ~= j then
				local d = (who[j].a - who[i].a) % nArms
				local want = ((tbl[who[i].m] or {})[d] or {})[who[j].m]
				eq(P.kind(M, i - 1, j - 1), want, tag .. ": " .. who[i].m .. "@" .. who[i].a .. " vs " .. who[j].m .. "@" .. who[j].a)
			end
		end
	end
	return M, conns
end

--- Independent check of the rim rule: ports as points on a unit circle (arm angle, lanes spread
-- 3 deg apart, the index falling counter-clockwise), connections as straight chords; two chords
-- with four different ports cross when the segments intersect.
local function oracleCross(arms, a, b)
	local ang = {}
	for _, x in ipairs(arms) do ang[x.seg] = x.angle end
	local function pt(seg, lane)
		local t = math.rad(ang[seg] + (8 - lane) * 3)
		return { math.cos(t), math.sin(t) }
	end
	local p1, q1, p2, q2 = pt(a.segment0, a.lane0), pt(a.segment1, a.lane1), pt(b.segment0, b.lane0), pt(b.segment1, b.lane1)
	local function orient(o, u, v) return (u[1] - o[1]) * (v[2] - o[2]) - (u[2] - o[2]) * (v[1] - o[1]) end
	local d1, d2 = orient(p1, q1, p2), orient(p1, q1, q2)
	local d3, d4 = orient(p2, q2, p1), orient(p2, q2, q1)
	return d1 * d2 < 0 and d3 * d4 < 0
end

local function samePort(s0, l0, s1, l1) return s0 == s1 and l0 == l1 end

--- Compares every pair of M (connections only) with the oracle: shared exit = merge, shared entry
-- = none, else the chord intersection. U-turns are left out (their own rule).
local function checkOracle(M, conns, arms, tag)
	for i = 1, #conns do
		for j = i + 1, #conns do
			local a, b = conns[i], conns[j]
			if a.segment0 ~= a.segment1 and b.segment0 ~= b.segment1 then
				local want
				if samePort(a.segment0, a.lane0, b.segment0, b.lane0) then want = nil
				elseif samePort(a.segment1, a.lane1, b.segment1, b.lane1) then want = "merge"
				elseif oracleCross(arms, a, b) then want = "cross" end
				eq(P.kind(M, i - 1, j - 1), want, tag .. ": " .. Rules.connsText({ a }) .. " vs " .. Rules.connsText({ b }))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Hand-checked matrices

-- 2x2 crossroads, right-hand traffic. Each road "BS BV BV FV FV FS" seen from the node: 0 and 5
-- sidewalks, 1 and 2 incoming (1 = kerb lane), 3 and 4 outgoing (4 = kerb lane). Arms 1..4 at 0,
-- 90, 180, 270 deg; the right turn goes to the next arm counter-clockwise, the left to the next
-- clockwise. Movements: R kerb lane -> right arm's kerb lane, S1 kerb lane -> opposite kerb lane,
-- S2 far lane -> opposite far lane, L far lane -> left arm's far lane. Rim positions (4 ports per
-- arm, counter-clockwise o4 o3 i2 i1 = 4k .. 4k+3), worked by hand per row:
local T2 = {
	-- R: i1(0)=3 -> o4(1)=4 encloses no port; only S1 from the left arm ends in its lane
	R = { [3] = { S1 = "merge" } },
	-- S1: 3 -> 8 encloses arm 1 (every movement from the right arm: its R merges into S1's lane),
	-- the opposite left turn ends in arm 1, the left arm's straights end there
	S1 = { [1] = { R = "merge", S1 = "cross", S2 = "cross", L = "cross" }, [2] = { L = "cross" }, [3] = { S1 = "cross", S2 = "cross" } },
	-- S2: 2 -> 9 encloses i1(0), arm 1, o4(2): the right arm's R runs beside it (both inside)
	S2 = { [1] = { S1 = "cross", S2 = "cross", L = "cross" }, [2] = { L = "cross" }, [3] = { S1 = "cross", S2 = "cross", L = "merge" } },
	-- L: 2 -> 13 encloses arms 1, 2 and o4(3): opposing lefts pass, the opposite straights cross
	L = { [1] = { S2 = "merge", L = "cross" }, [2] = { S1 = "cross", S2 = "cross" }, [3] = { S1 = "cross", S2 = "cross", L = "cross" } },
}

local function mk2(a, m)
	local s = a + 1
	local function arm(d) return (a + d) % 4 + 1 end
	if m == "R" then return C(s, 1, arm(1), 4) end
	if m == "S1" then return C(s, 1, arm(2), 4) end
	if m == "S2" then return C(s, 2, arm(2), 3) end
	return C(s, 2, arm(3), 3)
end

test("conflict map: 2x2 crossroads, hand-checked matrix (right-hand traffic), any rotation", function()
	for _, a0 in ipairs({ 0, 17, 200 }) do
		local M, conns = checkTable("2x2 rot " .. a0, { "R", "S1", "S2", "L" }, mk2, T2, arms4(a0), 4)
		-- per approach 18 crossing and 4 merging (ordered) entries
		eq(M.counts, { cross = 36, merge = 8, ped = 0 }, "2x2 rot " .. a0 .. ": pair counts")
		checkOracle(M, conns, arms4(a0), "2x2 oracle")
	end
end)

test("conflict map: left-hand traffic mirror gives the same matrix", function()
	local conns = {}
	for a = 0, 3 do
		for _, m in ipairs({ "R", "S1", "S2", "L" }) do conns[#conns + 1] = mk2(a, m) end
	end
	local arms = arms4(0)
	local M = assert(P.build({ conns = conns, arms = arms }))
	local a2, c2 = mirror(arms, conns, { 6, 6, 6, 6 })
	-- in the mirror the kerb lane of the approach is the highest incoming index: index 4 in, 1 out
	eq({ c2[1].lane0, c2[1].lane1 }, { 4, 1 }, "mirrored R: kerb lane 4 -> kerb lane 1")
	local M2 = assert(P.build({ conns = c2, arms = a2 }))
	eq(pairsText(M2), pairsText(M), "LHT mirror: same conflicts")
	checkOracle(M2, c2, a2, "LHT oracle")
end)

-- 3x3 crossroads with a dedicated kerb turn lane: "BS BV BV BV FV FV FV FS": 1-3 incoming (1 kerb),
-- 4-6 outgoing (6 kerb). R: 1 -> right arm's 6; Sa: 2 -> opposite 5; Sb: 3 -> opposite 4; L: 3 ->
-- left arm's 4 (the far lane goes straight and left, sl_cross). Rim positions 6 per arm (o6 o5 o4
-- i3 i2 i1 = 6k .. 6k+5).
local T3 = {
	-- R: 5 -> 6 encloses nothing and nobody else enters o6 of the right arm: no conflict at all
	-- (the exit's kerb lane is left free for the turn, sl_cross "a free kerb-side turn")
	R = {},
	-- Sa: 4 -> 13 encloses i1(0), arm 1, o6(2)
	Sa = { [1] = { Sa = "cross", Sb = "cross", L = "cross" }, [2] = { L = "cross" }, [3] = { Sa = "cross", Sb = "cross" } },
	-- Sb: 3 -> 14 encloses i2(0), i1(0), arm 1, o6(2), o5(2); the left arm's L ends in o4(2) too
	Sb = { [1] = { Sa = "cross", Sb = "cross", L = "cross" }, [2] = { L = "cross" }, [3] = { Sa = "cross", Sb = "cross", L = "merge" } },
	-- L: 3 -> 20 encloses i2/i1(0), arms 1 and 2, o6(3), o5(3)
	L = { [1] = { Sb = "merge", L = "cross" }, [2] = { Sa = "cross", Sb = "cross" }, [3] = { Sa = "cross", Sb = "cross", L = "cross" } },
}

local function mk3(a, m)
	local s = a + 1
	local function arm(d) return (a + d) % 4 + 1 end
	if m == "R" then return C(s, 1, arm(1), 6) end
	if m == "Sa" then return C(s, 2, arm(2), 5) end
	if m == "Sb" then return C(s, 3, arm(2), 4) end
	return C(s, 3, arm(3), 4)
end

test("conflict map: 3x3 crossroads with a kerb turn lane, hand-checked matrix, both traffic sides", function()
	local M, conns = checkTable("3x3", { "R", "Sa", "Sb", "L" }, mk3, T3, arms4(0), 4)
	eq(M.counts, { cross = 36, merge = 4, ped = 0 })
	checkOracle(M, conns, arms4(0), "3x3 oracle")
	local a2, c2 = mirror(arms4(0), conns, { 8, 8, 8, 8 })
	local M2 = assert(P.build({ conns = c2, arms = a2 }))
	eq(pairsText(M2), pairsText(M), "3x3 LHT mirror")
end)

-- T-junction, right-hand traffic, 2x2 roads: 1 east (0 deg), 2 north (90, the side road), 3 west
-- (180). Rim positions: east 0-3, north 4-7, west 8-11.
local function tConns()
	return {
		C(1, 1, 2, 4), -- 0 R_E   east kerb lane right into north:      3 -> 4
		C(1, 1, 3, 4), -- 1 S1_E  east straight (kerb lane):            3 -> 8
		C(1, 2, 3, 3), -- 2 S2_E  east straight (far lane):             2 -> 9
		C(3, 1, 1, 4), -- 3 S1_W  west straight (kerb lane):           11 -> 0
		C(3, 2, 1, 3), -- 4 S2_W  west straight (far lane):            10 -> 1
		C(3, 2, 2, 3), -- 5 L_W   west far lane left into north:       10 -> 5
		C(2, 1, 3, 4), -- 6 R_N   side road right into west:            7 -> 8
		C(2, 2, 1, 3), -- 7 L_N   side road left into east:             6 -> 1
	}
end
local T_ARMS = { { seg = 1, angle = 0 }, { seg = 2, angle = 90 }, { seg = 3, angle = 180 } }

test("conflict map: T-junction, hand-checked pairs, both traffic sides", function()
	local conns = tConns()
	local M = assert(P.build({ conns = conns, arms = T_ARMS }))
	checkSym(M, "T")
	eq(pairsText(M), {
		"1-5:cross", -- east straight vs west left (opposite left turn across it)
		"1-6:merge", -- east straight (kerb lane) and the side road's right turn into the west kerb lane
		"1-7:cross", -- east straight vs side road left
		"2-5:cross",
		"2-7:cross",
		"4-7:merge", -- west straight (far lane) and the side road's left into the east far lane
		"5-7:cross", -- west left vs side road left
	})
	-- R_E (east into north kerb lane) conflicts with nothing: the west left ends in the far lane
	eq(P.conflictsOf(M, 0), {})
	checkOracle(M, conns, T_ARMS, "T oracle")
	local a2, c2 = mirror(T_ARMS, conns, { 6, 6, 6 })
	eq(pairsText(assert(P.build({ conns = c2, arms = a2 }))), pairsText(M), "T LHT mirror")
end)

-- One-way arms: 1 east and 3 west two-way 2x2; 2 north one-way into the node "BS FV FV FS" (lanes
-- 1, 2 incoming; 1 = west = kerb for traffic heading south); 4 south one-way out of the node (lanes
-- 1, 2 outgoing; 2 = west = kerb for traffic heading south). Rim: east 0-3, north i2=4 i1=5, west
-- 6-9, south o2=10 o1=11.
test("conflict map: one-way arms (in only, out only), hand-checked, both traffic sides", function()
	local conns = {
		C(1, 1, 3, 4), -- 0 S1_E  3 -> 6
		C(1, 2, 3, 3), -- 1 S2_E  2 -> 7
		C(3, 1, 1, 4), -- 2 S1_W  9 -> 0
		C(3, 2, 1, 3), -- 3 S2_W  8 -> 1
		C(2, 1, 3, 4), -- 4 R_N   north (in only) right into the west kerb lane: 5 -> 6
		C(2, 2, 1, 3), -- 5 L_N   north left into the east far lane:            4 -> 1
		C(3, 1, 4, 2), -- 6 R_W   west right into south's kerb lane:            9 -> 10
		C(1, 2, 4, 1), -- 7 L_E   east left into south's far lane:              2 -> 11
	}
	local arms = arms4(0)
	local M = assert(P.build({ conns = conns, arms = arms }))
	checkSym(M, "one-way")
	eq(pairsText(M), {
		"0-4:merge", -- east straight and north's right turn into the west kerb lane
		"0-5:cross",
		"1-5:cross",
		"2-7:cross", -- west straight vs east left
		"3-5:merge",
		"3-7:cross",
		"5-7:cross", -- the two left turns from adjacent arms
	})
	eq(P.conflictsOf(M, 6), {}, "R_W: kerb turn into the out-only arm's kerb lane, beside L_E")
	checkOracle(M, conns, arms, "one-way oracle")
	local a2, c2 = mirror(arms, conns, { 6, 4, 6, 4 })
	eq(pairsText(assert(P.build({ conns = c2, arms = a2 }))), pairsText(M), "one-way LHT mirror")
end)

test("conflict map: 5-way, every movement of 1-lane roads, against the chord oracle; rotation and mirror invariant", function()
	-- "BS BV FV FS": 1 incoming, 2 outgoing (right-hand traffic)
	local arms, conns = {}, {}
	for k = 1, 5 do arms[k] = { seg = 10 + k, angle = 72 * (k - 1) + 5 } end
	for a = 1, 5 do
		for b = 1, 5 do
			if a ~= b then conns[#conns + 1] = C(10 + a, 1, 10 + b, 2) end
		end
	end
	local M = assert(P.build({ conns = conns, arms = arms }))
	checkSym(M, "5-way")
	checkOracle(M, conns, arms, "5-way")
	-- rotated by one arm: the same relation on the renamed connections
	local rot = {}
	for k = 1, 5 do rot[k] = { seg = 10 + k, angle = arms[(k % 5) + 1].angle } end
	local Mr = assert(P.build({ conns = conns, arms = rot }))
	local function key(c) return (c.segment0 - 10) .. ">" .. (c.segment1 - 10) end
	local idx = {}
	for i, c in ipairs(conns) do idx[key(c)] = i - 1 end
	for i, c in ipairs(conns) do
		for j, d in ipairs(conns) do
			-- renaming k -> k-1: connection a>b in the rotated map sits where (a+1)>(b+1) sat
			local function sh(x) return (x % 5) + 1 end
			local i2 = idx[sh(c.segment0 - 10) .. ">" .. sh(c.segment1 - 10)]
			local j2 = idx[sh(d.segment0 - 10) .. ">" .. sh(d.segment1 - 10)]
			eq(P.kind(Mr, i - 1, j - 1), P.kind(M, i2, j2), "5-way rotation " .. key(c) .. " / " .. key(d))
		end
	end
	local total = {}
	for k = 1, 5 do total[10 + k] = 4 end
	local a2, c2 = mirror(arms, conns, total)
	eq(pairsText(assert(P.build({ conns = c2, arms = a2 }))), pairsText(M), "5-way LHT mirror")
end)

test("conflict map: random junctions (3-5 arms, 1-4 lanes each way, random movements) agree with the chord oracle", function()
	local seed = 12345
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	for round = 1, 40 do
		local nArms = 2 + rnd(3)
		local arms, ins, outs, total = {}, {}, {}, {}
		local base = rnd(360)
		for k = 1, nArms do
			local seg = 100 + k
			arms[k] = { seg = seg, angle = base + (k - 1) * (360 / nArms) + rnd(20) }
			local ni, no = rnd(5) - 1, rnd(5) - 1
			if ni + no == 0 then ni = 1 end
			-- right-hand layout seen from the node: sidewalk 0, incoming 1..ni, outgoing ni+1..ni+no
			ins[seg], outs[seg] = {}, {}
			for l = 1, ni do ins[seg][#ins[seg] + 1] = l end
			for l = ni + 1, ni + no do outs[seg][#outs[seg] + 1] = l end
			total[seg] = ni + no + 2
		end
		local conns = {}
		for _ = 1, 4 + rnd(20) do
			local a, b = arms[rnd(nArms)].seg, arms[rnd(nArms)].seg
			if a ~= b and #ins[a] > 0 and #outs[b] > 0 then
				conns[#conns + 1] = C(a, ins[a][rnd(#ins[a])], b, outs[b][rnd(#outs[b])])
			end
		end
		local M = assert(P.build({ conns = conns, arms = arms }))
		checkSym(M, "random " .. round)
		checkOracle(M, conns, arms, "random " .. round)
		local a2, c2 = mirror(arms, conns, total)
		eq(pairsText(assert(P.build({ conns = c2, arms = a2 }))), pairsText(M), "random " .. round .. " mirror")
	end
end)

---------------------------------------------------------------------------
-- Crosswalks, trams, U-turns, unknowns, bounds

test("conflict map: crosswalks conflict with connections entering or leaving their arm; unknown ones with all", function()
	local conns = tConns()
	-- crosswalk 1 on the side road (2), 2 on the west arm (3), 3 an entity that is no arm, 4 nil-free
	local M = assert(P.build({ conns = conns, arms = T_ARMS, crosswalks = { 2, 3, 999 } }))
	checkSym(M, "crosswalks")
	eq(M.size, #conns + 3)
	eq(M.cwSeg, { 2, 3, false })
	local function pedOf(k)
		local list = {}
		for _, c in ipairs(P.conflictsOf(M, #conns + k - 1)) do
			eq(c[2], "ped")
			list[#list + 1] = c[1]
		end
		return list
	end
	eq(pedOf(1), { 0, 5, 6, 7 }, "side road crosswalk: R_E and L_W into it, R_N and L_N out of it")
	eq(pedOf(2), { 1, 2, 3, 4, 5, 6 }, "west crosswalk: everything into or out of the west arm")
	eq(pedOf(3), { 0, 1, 2, 3, 4, 5, 6, 7 }, "unmapped crosswalk: every connection (conservative)")
	eq(P.kind(M, #conns, #conns + 1), nil, "two crosswalks never conflict")
	eq(M.counts.ped, 18)
end)

test("conflict map: trams: a tram connection on a road lane pair follows the same rule; the same path twice is no conflict", function()
	local conns = tConns()
	conns[#conns + 1] = C(1, 1, 3, 4, false, true) -- 8: tram on the east straight's kerb lanes (same path as 1)
	conns[#conns + 1] = C(2, 1, 1, 4, false, true) -- 9: tram from the side road into the east kerb lane: 7 -> 0
	local M = assert(P.build({ conns = conns, arms = T_ARMS }))
	checkSym(M, "trams")
	eq(P.kind(M, 1, 8), nil, "road and tram on the same lane pair: one path")
	eq(P.kind(M, 8, 5), "cross", "the tram crosses the west left turn like the road connection")
	eq(P.kind(M, 9, 3), "merge", "tram into the east kerb lane merges with the west straight")
	eq(P.kind(M, 9, 1), "cross", "tram out of the side road crosses the east straight")
end)

test("conflict map: U-turns cross every other approach's non-kerb movement; kerb turns and the chord option keep the rim rule", function()
	local conns = tConns()
	conns[#conns + 1] = C(1, 2, 1, 3) -- 8: U-turn at the east arm, far lane into the far lane: 2 -> 1
	conns[#conns + 1] = C(2, 1, 1, 3) -- 9: side road right... (a kerb turn into east's far lane, made up): 7 -> 1
	local cls = { "kerb", "straight", "straight", "straight", "straight", "far", "kerb", "far", "u_turn", "kerb" }
	local M = assert(P.build({ conns = conns, arms = T_ARMS, cls = cls }))
	checkSym(M, "U-turn")
	eq(P.kind(M, 8, 0), nil, "own approach: rim rule (R_E from the kerb lane runs outside it)")
	eq(P.kind(M, 8, 1), nil, "own approach straight from the kerb lane: beside")
	eq(P.kind(M, 8, 2), nil, "own approach, same entry lane: queued")
	eq(P.kind(M, 8, 3), "cross", "west straight into the east kerb lane: strict (the U-turn swings through the middle)")
	eq(P.kind(M, 8, 4), "merge", "west straight into the same far lane")
	eq(P.kind(M, 8, 9), "merge", "a kerb turn into the same lane: rim rule (merge)")
	eq(P.kind(M, 8, 6), nil, "a kerb turn of another approach elsewhere: rim rule, no conflict")
	local Mc = assert(P.build({ conns = conns, arms = T_ARMS, cls = cls, uTurn = "chord" }))
	eq(P.kind(Mc, 8, 3), nil, "chord option: the rim rule only")
	eq(P.kind(Mc, 8, 4), "merge")
end)

test("conflict map: a connection on a segment without an arm crosses everything but its own entry lane", function()
	local conns = tConns()
	conns[#conns + 1] = C(77, 1, 3, 4) -- 8: unknown arm 77
	conns[#conns + 1] = C(77, 1, 1, 4) -- 9: same entry lane
	conns[#conns + 1] = C(1, 1, 3, 2000) -- 10: lane index out of range
	local M = assert(P.build({ conns = conns, arms = T_ARMS }))
	checkSym(M, "unknown")
	for i = 0, 7 do eq(P.kind(M, 8, i), "cross", "unknown arm vs " .. i) end
	eq(P.kind(M, 8, 9), nil, "same entry lane")
	ok(M.unknown[8] and M.unknown[9] and M.unknown[10])
	eq(P.kind(M, 10, 1), nil, "unknown lane but the same entry lane as S1_E: queued")
	eq(P.kind(M, 10, 3), "cross")
end)

test("conflict map: bounds and stale phases", function()
	local many = {}
	for i = 1, P.MAX_CONNS + 1 do many[i] = C(1, 1, 2, 4) end
	eq({ P.build({ conns = many, arms = T_ARMS }) }, { nil, "conns" })
	local cws = {}
	for i = 1, P.MAX_CROSS + 1 do cws[i] = 1 end
	eq({ P.build({ conns = {}, arms = T_ARMS, crosswalks = cws }) }, { nil, "crosswalks" })
	local arms = {}
	for i = 1, P.MAX_ARMS + 1 do arms[i] = { seg = i, angle = i * 10 } end
	eq({ P.build({ conns = {}, arms = arms }) }, { nil, "arms" })
	local M = assert(P.build({ conns = tConns(), arms = T_ARMS, crosswalks = { 2 } }))
	eq({ P.phaseConflicts(M, { 0, 9 }) }, { nil, "stale_phases" }, "index past conns + crosswalks")
	eq({ P.phaseConflicts(M, { 0.5 }) }, { nil, "stale_phases" })
	eq({ P.checkPhases(M, { { 0 }, { -1 } }) }, { nil, "stale_phases" })
	-- an empty map
	local E = assert(P.build({}))
	eq({ E.size, E.counts }, { 0, { cross = 0, merge = 0, ped = 0 } })
	eq(P.phaseConflicts(E, {}), {})
end)

test("phaseConflicts / checkPhases: green pairs only; all red is conflict-free", function()
	local conns = tConns()
	local M = assert(P.build({ conns = conns, arms = T_ARMS, crosswalks = { 2 } }))
	local all = {}
	for i = 0, M.size - 1 do all[#all + 1] = i end
	eq(P.phaseConflicts(M, all), {}, "all red")
	-- only east straight (1) and west left (5) green
	local red = {}
	for i = 0, M.size - 1 do if i ~= 1 and i ~= 5 then red[#red + 1] = i end end
	eq(P.phaseConflicts(M, red), { { 1, 5, "cross" } })
	-- west left (5) and the side road crosswalk (8) green
	red = {}
	for i = 0, M.size - 1 do if i ~= 5 and i ~= 8 then red[#red + 1] = i end end
	local per, counts = P.checkPhases(M, { red, all })
	eq(per, { { { 5, 8, "ped" } }, {} })
	eq(counts, { cross = 0, merge = 0, ped = 1 })
end)

---------------------------------------------------------------------------
-- Real views (sl_cross): arms from the view and the world, agreement with L.kerbConflict, the
-- game's default phases

--- Crossroads at node 1 (as test_lights.lua crossing): 11 west, 12 east (main road), 13 north,
-- 14 south (side road; none when t). mirror: left-hand traffic. Returns view, world.
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

local function cyclic(arms)
	local list = {}
	for _, a in ipairs(arms) do list[#list + 1] = a end
	table.sort(list, function(p, q) return p.angle < q.angle end)
	local out = {}
	for i, a in ipairs(list) do out[i] = a.seg end
	-- rotate so the smallest segment id comes first
	local k = 1
	for i, s in ipairs(out) do if s < out[k] then k = i end end
	local r = {}
	for i = 0, #out - 1 do r[#r + 1] = out[(k - 1 + i) % #out + 1] end
	return r
end

local FIXTURES = {
	{ "2x2 X", false, nil, nil },
	{ "3x3 X", false, F.TPL.large, F.TPL.large },
	{ "3x3 / 2x2 X", false, F.TPL.large, F.TPL.medium },
	{ "2x2 T", true, nil, nil },
	{ "3x3 T", true, F.TPL.large, F.TPL.large },
	{ "1x1 X", false, F.TPL.small, F.TPL.small },
}

test("armsFromView and armsFromWorld give the same order around the node, both traffic sides", function()
	for _, fx in ipairs(FIXTURES) do
		for _, mir in ipairs({ false, true }) do
			local tag = fx[1] .. (mir and " left" or " right")
			local v, world = crossing(fx[2], mir, fx[3], fx[4])
			local av, aw = P.armsFromView(v), P.armsFromWorld(world, 1)
			eq(#av, fx[2] and 3 or 4, tag)
			eq(cyclic(av), cyclic(aw), tag .. ": same cyclic order")
			-- the view's angles are relative: differences match the world's
			local wa = {}
			for _, a in ipairs(aw) do wa[a.seg] = a.angle end
			local base = av[1]
			for _, a in ipairs(av) do
				local d1 = P.norm(a.angle - base.angle)
				local d2 = P.norm(wa[a.seg] - wa[base.seg])
				near(d1, d2, 1e-6, tag .. ": spacing of " .. a.seg)
			end
		end
	end
end)

--- The map of a view's connections: arms from the world, crosswalks on every arm (segment ids).
local function viewMap(v, world, conns, cws)
	return assert(P.build({ conns = conns, arms = P.armsFromWorld(world, 1), crosswalks = cws,
		cls = P.classesFromView(conns, v) }))
end

test("kerb turns: the map agrees with L.kerbConflict pair by pair (rule and game-default connections, crosswalks, both sides)", function()
	local checked = 0
	for _, fx in ipairs(FIXTURES) do
		for _, mir in ipairs({ false, true }) do
			for _, which in ipairs({ "rule", "default" }) do
				local tag = fx[1] .. (mir and " left " or " right ") .. which
				local v, world = crossing(fx[2], mir, fx[3], fx[4])
				local conns = which == "rule" and Slip.roadConns(v) or Cross.defaultConns(v)
				local kerb = Cross.kerbPairs(v)
				local idx = L.kerbIndices(conns, kerb)
				ok(#idx > 0, tag .. ": has kerb turns")
				local segs, cws = {}, {}
				for _, sid in ipairs(world.node(1).segs) do
					segs[sid] = true
					cws[#cws + 1] = sid
				end
				cws[#cws + 1] = 999 -- an unmapped crosswalk
				local M = viewMap(v, world, conns, cws)
				local ctx = { kerb = kerb, crosswalks = cws, segs = segs }
				for _, j in ipairs(idx) do
					for i = 0, M.size - 1 do
						if i ~= j then
							local function green(x) return x == j or x == i end
							local want = L.kerbConflict(conns, j, #cws, green, ctx)
							eq(P.kind(M, j, i), want, tag .. ": kerb " .. Rules.connsText({ conns[j + 1] }) .. " vs index " .. i
								.. (i < #conns and (" " .. Rules.connsText({ conns[i + 1] })) or " (crosswalk)"))
							checked = checked + 1
						end
					end
				end
				checkSym(M, tag)
			end
		end
	end
	ok(checked > 1000, "pairs checked: " .. checked)
end)

test("kerb turns: the map is stricter than L.kerbConflict only for an in-only arm inside the kerb corner", function()
	-- right-hand traffic: A = 1 at 0 deg, a one-way street 2 entering at 40 deg, E = 3 at 90 deg (A's
	-- kerb exit), W = 4 at 180. The one-way street's movements start inside the kerb turn's corner.
	local arms = { { seg = 1, angle = 0 }, { seg = 2, angle = 40 }, { seg = 3, angle = 90 }, { seg = 4, angle = 180 } }
	local conns = {
		C(1, 1, 3, 4), -- 0: kerb turn A -> E kerb lane
		C(2, 1, 4, 4), -- 1: one-way street -> W
		C(4, 1, 3, 3), -- 2: W -> E far lane (beside the kerb turn)
	}
	local M = assert(P.build({ conns = conns, arms = arms }))
	eq(P.kind(M, 0, 1), "cross", "the map: the one-way street's traffic crosses the kerb turn")
	eq(P.kind(M, 0, 2), nil)
	local kerb = { ["1>3"] = { [4] = 1, [3] = 2 } }
	local function green(x) return x == 0 or x == 1 end
	eq(L.kerbConflict(conns, 0, 0, green, { kerb = kerb, segs = { [1] = true, [2] = true, [3] = true, [4] = true } }), nil,
		"L.kerbConflict looks only at streams ending in E")
end)

--- The game's default style of phases (findings.md; test_lights defaultPhases): phase 1 = the main
-- road (11, 12) goes, phase 2 = the side road (13, 14); every connection of the other road red.
-- Crosswalks (one per arm, cws order): the ones across the side road green with the main road and
-- the other way round (pedestrians walk beside the green traffic).
local function gamePhases(conns, cws)
	local p1, p2 = {}, {}
	for i, c in ipairs(conns) do
		if c.segment0 == 13 or c.segment0 == 14 then p1[#p1 + 1] = i - 1 else p2[#p2 + 1] = i - 1 end
	end
	for k, cw in ipairs(cws) do
		if cw == 13 or cw == 14 then p2[#p2 + 1] = #conns + k - 1 else p1[#p1 + 1] = #conns + k - 1 end
	end
	return { p1, p2 }
end

test("the game's default phases under the map: only the permissive turns conflict, never two straights (printed per fixture)", function()
	local report = {}
	for _, fx in ipairs(FIXTURES) do
		for _, mir in ipairs({ false, true }) do
			local tag = fx[1] .. (mir and " left" or " right")
			local v, world = crossing(fx[2], mir, fx[3], fx[4])
			local conns = Cross.defaultConns(v)
			local cws = {}
			for _, sid in ipairs(world.node(1).segs) do cws[#cws + 1] = sid end
			local M = viewMap(v, world, conns, cws)
			local per = assert(P.checkPhases(M, gamePhases(conns, cws)))
			local hist = {}
			for _, list in ipairs(per) do
				for _, c in ipairs(list) do
					local a = M.cls[c[1] + 1] or "?"
					local b = c[2] < #conns and (M.cls[c[2] + 1] or "?") or "walk"
					if a > b and b ~= "walk" then a, b = b, a end
					local k = a .. "/" .. b .. ":" .. c[3]
					-- two connections of one approach: only the modelled side road of a T without a
					-- straight exit, whose lanes 2..N all turn far into every exit lane (X.defaultConns,
					-- extrapolated: TESTING.md K), merge and cross among themselves
					if c[2] < #conns and conns[c[1] + 1].segment0 == conns[c[2] + 1].segment0 then
						ok(k == "far/far:merge" or k == "far/far:cross", tag .. ": same approach " .. k)
						k = "own_" .. k
					end
					hist[k] = (hist[k] or 0) + 1
				end
			end
			for k in pairs(hist) do
				local allowed = k == "far/straight:cross" or k == "far/kerb:merge" or k == "far/kerb:cross"
					or k == "own_far/far:merge" or k == "own_far/far:cross" or k == "kerb/walk:ped" or k == "far/walk:ped"
				ok(allowed, tag .. ": conflict kind " .. k)
				ok(k:find("straight/straight", 1, true) == nil and k ~= "straight/walk:ped", tag .. ": " .. k)
			end
			report[#report + 1] = tag .. " " .. Rules.countsText(hist)
		end
	end
	for _, line in ipairs(report) do print(line) end
end)

---------------------------------------------------------------------------
-- PROBE phases (sl_write.lua W.probePhases): read-only, gated, once per node, capped

local function probeApi(configs, lights)
	local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_NODE_CONFIG = "BNC", BASE_NODE_TRAFFIC_LIGHT = "BNTL" }
	local sent = 0
	local api = {
		type = { ComponentType = CT, enum = { TrafficLightPreference = { YES = 0, NO = 1, AUTO = 2 } } },
		engine = {
			getComponent = function(e, ct)
				if ct == CT.BASE_NODE_CONFIG then return configs[e] end
				if ct == CT.BASE_NODE_TRAFFIC_LIGHT then return lights[e] end
				return nil
			end,
		},
		cmd = { sendCommand = function() sent = sent + 1 end },
	}
	return api, function() return sent end
end

test("PROBE phases: gated by the debug setting, once per lit node, unlit nodes left for later, nothing sent", function()
	local v, world = crossing(true, false)
	local conns = Slip.roadConns(v)
	local cfg = {
		laneConnections = conns, crosswalks = { 13, 11, 999 }, trafficLightPreference = 2,
		userModifiedTrafficLightStates = false, userModifiedLaneConnections = true,
		trafficLightConfig = { trafficLightType = 1, states = {
			{ lockedLanes = { 0, 1, 2 }, duration = 20, minDuration = 2.5, canSkip = true },
			{ lockedLanes = { 3, 4, #conns + 2 }, duration = 30.5, minDuration = 0, canSkip = false },
		} },
	}
	local light = { state = 1, time = 4.25, stateTimes = { 20, 30 },
		trafficLightData = { state2duration = { 20, 30.5 }, state2lockedLanes = { { 0, 1, 2 }, { 3, 4, #conns + 2 } },
			state2redLightModelIndices = { { 1 }, { 2, 3 } }, animatedModels = { 7, 8, 9 } } }
	local configs, lights = { [1] = cfg, [2] = { laneConnections = {}, trafficLightConfig = { states = {} } } }, { [1] = light }
	local api, sentCount = probeApi(configs, lights)
	local logs, on = {}, false
	local W = Write.new(api, function(kind, fields) logs[#logs + 1] = Rules.line(kind, fields) end,
		{ probeOn = function() return on end })
	eq(W.probePhases(1, world), false, "off: nothing")
	eq(#logs, 0)
	on = true
	eq(W.probePhases(2, world), false, "unlit node (no light, no phases): not logged")
	eq(W.probePhases(1, world), true)
	eq(W.probePhases(1, world), false, "once per node")
	eq(sentCount(), 0, "read-only")
	local head = logs[1]
	ok(head:find("^%[SQRL%] PROBE phases node=1 type=1 pref=auto user_modified=false user_lanes=true states=2 durations=20,30.5 min=2.5,0 skip=true,false conns=" .. #conns, 1) ~= nil, head)
	ok(head:find("arms=A=12@0.0,B=13@90.0,C=11@180.0", 1, true) ~= nil, "arms lettered by angle: " .. head)
	ok(head:find("crosswalks=13,11,999 cw_is_edge=y,y,n light=true", 1, true) ~= nil, head)
	ok(head:find("light_state=1 light_time=4.25 state_times=20,30 data_durations=20,30.5 data_locked=3,3 data_same=true data_red=1,2 data_models=3", 1, true) ~= nil, head)
	-- connections in config order with arm letters, chunked under the field cap
	local list = {}
	for _, l in ipairs(logs) do
		local p = l:match("PROBE phases_conns node=1 part=%d+/%d+ list=(%S+)")
		if p then
			ok(#p <= Write.PROBE_CHUNK, "chunk length")
			list[#list + 1] = p
		end
	end
	local want = {}
	local letter = { [12] = "A", [13] = "B", [11] = "C" }
	for _, c in ipairs(conns) do want[#want + 1] = letter[c.segment0] .. c.lane0 .. ">" .. letter[c.segment1] .. c.lane1 end
	eq(table.concat(list, ","), table.concat(want, ","))
	local st = {}
	for _, l in ipairs(logs) do
		if l:find("PROBE phases_state", 1, true) then st[#st + 1] = l end
	end
	eq(st, { "[SQRL] PROBE phases_state node=1 state=1 part=1/1 duration=20 min=2.5 skip=true n=3 locked=0,1,2",
		"[SQRL] PROBE phases_state node=1 state=2 part=1/1 duration=30.5 min=0 skip=false n=3 locked=3,4," .. (#conns + 2) })
	-- the light comes later at node 2: logged then
	configs[2].trafficLightConfig.states = { { lockedLanes = {}, duration = 10, minDuration = 0, canSkip = false } }
	eq(W.probePhases(2, nil), true, "lit now")
end)

test("PROBE phases: capped at PROBE_PHASES_MAX nodes; broken reads never throw (one ERROR line)", function()
	local configs, lights = {}, {}
	for n = 1, Write.PROBE_PHASES_MAX + 5 do
		configs[n] = { laneConnections = {}, trafficLightConfig = { states = { { lockedLanes = {}, duration = 1 } } } }
	end
	local api = probeApi(configs, lights)
	local logs = {}
	local W = Write.new(api, function(kind, fields) logs[#logs + 1] = Rules.line(kind, fields) end,
		{ probeOn = function() return true end })
	local n = 0
	for node = 1, Write.PROBE_PHASES_MAX + 5 do
		if W.probePhases(node, nil) then n = n + 1 end
	end
	eq(n, Write.PROBE_PHASES_MAX)
	-- a light component whose fields throw: read as missing
	local bad = setmetatable({}, { __index = function() error("boom") end })
	-- a connection list whose reads throw: one ERROR line, no throw
	local api2 = probeApi({ [1] = { laneConnections = {}, trafficLightConfig = { states = {} } },
		[2] = { laneConnections = bad, trafficLightConfig = { states = {} } } }, { [1] = bad, [2] = {} })
	local logs2 = {}
	local W2 = Write.new(api2, function(kind, fields) logs2[#logs2 + 1] = Rules.line(kind, fields) end,
		{ probeOn = function() return true end })
	eq(W2.probePhases(1, nil), true)
	ok(logs2[1]:find("PROBE phases node=1 ", 1, true) ~= nil and logs2[1]:find("light=true light_state=nil", 1, true) ~= nil, logs2[1])
	eq(W2.probePhases(2, nil), true)
	ok(logs2[#logs2]:find("ERROR where=probe_phases node=2", 1, true) ~= nil, logs2[#logs2])
	-- no probeOn: never
	local W3 = Write.new(api, function() error("must not log") end)
	eq(W3.probePhases(1, nil), false)
end)

test("PROBE phases: a 0-based trafficLightData map is read from key 0", function()
	local cfg = { laneConnections = {}, crosswalks = {}, trafficLightConfig = { states = {
		{ lockedLanes = { 0 }, duration = 20 }, { lockedLanes = { 1, 2 }, duration = 30 } } } }
	local light = { state = 0, time = 1, stateTimes = { [0] = 20, [1] = 30 },
		trafficLightData = { state2duration = { [0] = 20, [1] = 30 }, state2lockedLanes = { [0] = { 0 }, [1] = { 1, 2 } },
			state2redLightModelIndices = {}, animatedModels = {} } }
	local api = probeApi({ [1] = cfg }, { [1] = light })
	local logs = {}
	local W = Write.new(api, function(kind, fields) logs[#logs + 1] = Rules.line(kind, fields) end,
		{ probeOn = function() return true end })
	eq(W.probePhases(1, nil), true)
	ok(logs[1]:find("state_times=20,30 data_durations=20,30 data_locked=1,2 data_same=true", 1, true) ~= nil, logs[1])
end)
