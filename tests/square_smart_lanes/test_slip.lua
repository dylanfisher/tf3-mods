-- square_smart_lanes: slip-lane junctions (sl_slip.lua): node classification, the lane rule and
-- its invariants (no crossing, every lane connected / fed, tram kept), both traffic sides, the
-- Channelized Junction's geometry (hand-made fixture mirroring square_roundabouts_channel.lua).

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

-- the remembered driving side is module state (one per Lua state): every test starts without one
before_each(function() Slip.resetSide() end)

local TPL = {
	one1 = "B- FV F-",                  -- highway_new_small (1 lane, Roundabout Interchange slip roads)
	one2 = "BS FV FV FS",               -- town_new_one_way_xsmall / small (2 lanes, channel slip lanes)
	one3 = "BS FV FV FV FS",            -- 3-lane one-way (no base template; a highway carriageway)
	one4 = "BS FV FV FV FV FS",         -- town_new_one_way_medium
	two1 = F.TPL.small,                 -- 1 lane per direction
	two2 = F.TPL.medium,                -- 2
	two3 = F.TPL.large,                 -- 3
	two1_tram = F.TPL.small_tram,
	two2_bus = F.TPL.medium_bus,
}

local build, dir, channelT = F.build, F.dir, F.channelT

--- A straight main road through node 1 (west 2 -> 1 -> east 3) with one branch at node 1 leaving
-- (or joining) at `angle` degrees to the `side` ("right"/"left" of eastbound traffic).
-- main: template of both main segments (drawn west to east); branch: one-way template.
-- join: the branch arrives (merge) instead of leaving (diverge). mirror: left-hand traffic.
-- Node ids: 1 slip node, 2 west, 3 east, 4 branch end; segments 31 (2 -> 1), 32 (1 -> 3), 33 branch.
local function tee(opt)
	local ang = opt.angle or 30
	local s = (opt.side == "left") and 1 or -1
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 } }
	local segs = { [31] = { 2, 1, opt.main }, [32] = { 1, 3, opt.main } }
	if opt.join then
		-- comes from behind on that side, heading east turned towards the road
		local d = dir(-s * ang)
		nodes[4] = { -50 * d[1], -50 * d[2] }
		segs[33] = { 4, 1, opt.branch, d, d }
	else
		local d = dir(s * ang)
		nodes[4] = { 50 * d[1], 50 * d[2] }
		segs[33] = { 1, 4, opt.branch, d, d }
	end
	return build(nodes, segs, opt.mirror)
end

---------------------------------------------------------------------------
-- Invariant checks

--- Kerb-first physical positions of a stream's lanes: inputs and outputs (diverge outputs:
-- branch lanes first, then through lanes; merge inputs: branch lanes first, then through lanes).
local function positions(st)
	local inPos, outPos = {}, {}
	local function put(map, seg, lanes, offset)
		for i, l in ipairs(lanes) do map[seg .. ":" .. l] = offset + i end
	end
	if st.shape == "straight" then
		put(inPos, st.inSeg, st.m, 0)
		put(outPos, st.outSeg, st.o, 0)
	elseif st.shape == "diverge" then
		put(inPos, st.inSeg, st.m, 0)
		put(outPos, st.branchSeg, st.b, 0)
		put(outPos, st.throughSeg, st.t, #st.b)
	else
		put(inPos, st.branchSeg, st.q, 0)
		put(inPos, st.throughSeg, st.p, #st.q)
		put(outPos, st.outSeg, st.o, 0)
	end
	return inPos, outPos
end

--- Checks every invariant of the rule on a view and its road connections; returns per-stream
-- maps (inPos -> {outPos...}).
local function checkInvariants(v, conns, msg)
	msg = msg or ""
	local claimed = {}
	for si, st in ipairs(v.streams) do
		local inPos, outPos = positions(st)
		local outsOf, fed = {}, {}
		for ci, c in ipairs(conns) do
			if c.withRoad then
				local ip = inPos[c.segment0 .. ":" .. c.lane0]
				local op = outPos[c.segment1 .. ":" .. c.lane1]
				if ip and op then
					claimed[ci] = true
					outsOf[ip] = outsOf[ip] or {}
					table.insert(outsOf[ip], op)
					fed[op] = true
				elseif ip or op then
					-- a lane of this stream connected outside it: a U-turn or a cross-stream move
					ok(false, msg .. " stream " .. si .. " leaks: " .. Rules.connsText({ c }))
				end
			end
		end
		local nIn, nOut = 0, 0
		for _ in pairs(inPos) do nIn = nIn + 1 end
		for _ in pairs(outPos) do nOut = nOut + 1 end
		for i = 1, nIn do ok(outsOf[i] ~= nil, msg .. " stream " .. si .. " (" .. st.shape .. ") in lane " .. i .. " connected") end
		for j = 1, nOut do ok(fed[j], msg .. " stream " .. si .. " (" .. st.shape .. ") out lane " .. j .. " fed") end
		-- no crossing: for in lanes a < b, every target of a is at or before every target of b
		for a = 1, nIn do
			for b = a + 1, nIn do
				for _, x in ipairs(outsOf[a] or {}) do
					for _, y in ipairs(outsOf[b] or {}) do
						ok(x <= y, string.format("%s stream %d (%s) crossing: in %d -> %d, in %d -> %d", msg, si, st.shape, a, x, b, y))
					end
				end
			end
		end
	end
	for ci, c in ipairs(conns) do
		if c.withRoad then
			ok(claimed[ci], msg .. " connection outside every stream: " .. Rules.connsText({ c }))
			ok(c.segment0 ~= c.segment1, msg .. " U-turn " .. Rules.connsText({ c }))
		end
	end
end

local function pairsText(list)
	local out = {}
	for _, p in ipairs(list) do out[#out + 1] = p.from .. p.i .. ">" .. p.to .. p.j end
	table.sort(out)
	return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- The rule on lane counts

test("rule tables: 2-lane main road, 1-lane slip (diverge and merge), and the Channelized 2 + 2", function()
	-- diverge N=2 -> T=2 + B=1: kerb lane shared (slip or straight), lane 2 straight
	eq(pairsText(Slip.pairs("diverge", 2, 2, 1)), "m1>b1 m1>t1 m2>t2")
	-- merge T=2 + B=1 -> O=2: the slip joins the kerb lane (give way), through lanes 1:1
	eq(pairsText(Slip.pairs("merge", 2, 1, 2)), "p1>o1 p2>o2 q1>o1")
	-- merge into a lane gain (O=3): nobody shares
	eq(pairsText(Slip.pairs("merge", 2, 1, 3)), "p1>o2 p2>o3 q1>o1")
	-- Channelized Junction, medium main road, 2-lane slip: diverge 2 -> 2 + 2: through keeps both
	-- lanes, the kerb lane feeds both slip lanes (m2 -> b2 would cross m1 -> t1)
	eq(pairsText(Slip.pairs("diverge", 2, 2, 2)), "m1>b1 m1>b2 m1>t1 m2>t2")
	-- merge 2 + 2 -> 2: both slip lanes into the kerb lane
	eq(pairsText(Slip.pairs("merge", 2, 2, 2)), "p1>o1 p2>o2 q1>o1 q2>o1")
	-- road narrows: 3 -> 2 + 2: m1 slip only, m2 option lane, m3 straight
	eq(pairsText(Slip.pairs("diverge", 3, 2, 2)), "m1>b1 m2>b2 m2>t1 m3>t2")
	-- 2 -> 1 + 1: lane drop, dedicated kerb lane
	eq(pairsText(Slip.pairs("diverge", 2, 1, 1)), "m1>b1 m2>t1")
	-- 3 -> 1 + 2
	eq(pairsText(Slip.pairs("diverge", 3, 1, 2)), "m1>b1 m2>b2 m3>t1")
	-- 1 + 1 -> 2: lane gain merge
	eq(pairsText(Slip.pairs("merge", 1, 1, 2)), "p1>o2 q1>o1")
	-- straight 2 -> 2 and 2 -> 3 (fan on the kerb side), 3 -> 2 (fold on the kerb side)
	eq(pairsText(Slip.pairs("straight", 2, 2)), "m1>o1 m2>o2")
	eq(pairsText(Slip.pairs("straight", 2, 3)), "m1>o1 m1>o2 m2>o3")
	eq(pairsText(Slip.pairs("straight", 3, 2)), "m1>o1 m2>o1 m3>o2")
end)

--- Checks the pairs of one shape on counts (a, b, c as S.pairs): every position in range, every input
-- connected, every output fed, no crossing. Returns outs (input position -> output positions).
local function checkPairs(shape, a, b, c, pr)
	local name = string.format("%s %d,%d,%s", shape, a, b, tostring(c))
	-- positions: inputs / outputs kerb first
	local function inPos(p)
		if shape == "merge" then return p.from == "q" and p.i or b + p.i end
		return p.i
	end
	local function outPos(p)
		if shape == "diverge" then return p.to == "b" and p.j or c + p.j end
		return p.j
	end
	local nIn = shape == "merge" and (a + b) or a
	local nOut = shape == "diverge" and (b + c) or (shape == "merge" and c or b)
	local outs, fed = {}, {}
	for _, p in ipairs(pr) do
		local i, j = inPos(p), outPos(p)
		ok(i >= 1 and i <= nIn and j >= 1 and j <= nOut, name .. " range")
		outs[i] = outs[i] or {}
		table.insert(outs[i], j)
		fed[j] = true
	end
	for i = 1, nIn do ok(outs[i], name .. " in " .. i) end
	for j = 1, nOut do ok(fed[j], name .. " out " .. j) end
	for x = 1, nIn do
		for y = x + 1, nIn do
			for _, p in ipairs(outs[x] or {}) do
				for _, q in ipairs(outs[y] or {}) do ok(p <= q, name .. " crossing") end
			end
		end
	end
	return outs
end

--- Invariants straight on the pairs for every count combination 1..4.
test("rule invariants for all lane counts: no crossing, every lane connected and fed", function()
	local check = checkPairs
	for N = 1, 4 do
		for T = 1, 4 do
			for B = 1, 3 do
				local pr = Slip.pairs("diverge", N, T, B)
				check("diverge", N, T, B, pr)
				-- the branch gets min(B, N, f) dedicated-or-shared feeders; through keeps min(N, T) lanes
				local tFeed, bFeed = {}, {}
				for _, p in ipairs(pr) do
					if p.to == "t" then tFeed[p.i] = true else bFeed[p.i] = true end
				end
				local nt, nb = 0, 0
				for _ in pairs(tFeed) do nt = nt + 1 end
				for _ in pairs(bFeed) do nb = nb + 1 end
				ok(nt >= math.min(N, T), string.format("diverge %d,%d,%d through keeps lanes", N, T, B))
				if N > T then
					eq(nb, math.min(B, N, N - T + 1), string.format("diverge %d,%d,%d branch feeders", N, T, B))
				else
					eq(nb, 1, string.format("diverge %d,%d,%d only the kerb lane feeds the branch", N, T, B))
				end
				pr = Slip.pairs("merge", N, B, T)
				check("merge", N, B, T, pr)
				if N + B <= T then
					-- nobody shares an outgoing lane
					local into = {}
					for _, p in ipairs(pr) do
						into[p.j] = (into[p.j] or 0) + 1
					end
					for j, k in pairs(into) do eq(k, 1, string.format("merge %d+%d->%d out %d single", N, B, T, j)) end
				end
			end
			check("straight", N, T, nil, Slip.pairs("straight", N, T))
		end
	end
end)

---------------------------------------------------------------------------
-- Classification and connections on worlds

local function slipConns(world, n, current)
	local r = Slip.plan(world, n, function() return current or {} end)
	return r, r.view
end

test("Channelized Junction T (medium main, small side, 2-lane slips): diverge, merge, side node both", function()
	local W = channelT()
	local r2, v2 = slipConns(W, 2)
	eq(v2.kind, "slip")
	eq(v2.case, "B")
	eq(v2.side, "right")
	eq(v2.shape, "diverge")
	eq(r2.status, "apply")
	checkInvariants(v2, r2.conns, "east node")
	-- westbound (12 -> 11) diverges into the slip 21; eastbound (11 -> 12) straight
	local dv, st
	for _, s in ipairs(v2.streams) do
		if s.shape == "diverge" then dv = s else st = s end
	end
	eq(dv.inSeg, 12)
	eq(dv.throughSeg, 11)
	eq(dv.branchSeg, 21)
	eq(st.inSeg, 11)
	eq(st.outSeg, 12)
	-- exact connections (lane indices count the sidewalks; findings.md): seg 12 at node 2 is its
	-- node0 end, westbound lanes 1 (kerb, north) and 2; seg 11 ends at node 2, westbound out lanes
	-- 4 (kerb) and 3; slip 21 starts here, lanes 2 (kerb, right) and 1. Eastbound: 11:1,2 -> 12:3,4.
	eq(Rules.connsText(r2.conns), Rules.connsText(F.parseConns(
		"12:1>21:2:R-,12:1>21:1:R-,12:1>11:4:R-,12:2>11:3:R-,11:1>12:4:R-,11:2>12:3:R-")))

	local r3, v3 = slipConns(W, 3)
	eq(v3.kind, "slip")
	eq(v3.shape, "merge")
	checkInvariants(v3, r3.conns, "west node")

	local r4, v4 = slipConns(W, 4)
	eq(v4.kind, "slip", v4.reason)
	eq(v4.shape, "diverge+merge")
	eq(v4.roads, 4)
	checkInvariants(v4, r4.conns, "north node")
	-- the slip from the east joins northbound traffic, the slip to the west leaves southbound
	for _, s in ipairs(v4.streams) do
		if s.shape == "merge" then
			eq(s.branchSeg, 21)
			eq(s.outSeg, 16)
		else
			eq(s.shape, "diverge")
			eq(s.branchSeg, 22)
			eq(s.inSeg, 16)
		end
	end
	-- the centre (T of two-way roads) gets the crossing rule (sl_cross); the arm ends are no slip nodes
	eq(Slip.classify(W, 1).case, "X")
	eq(Slip.classify(W, 1).shape, "t_junction")
	eq(Slip.classify(W, 5).kind, "none")
end)

test("Channelized Junction for every main/side/slip template and slip angle, both traffic sides", function()
	local mains = { TPL.two1, TPL.two2, TPL.two3 }
	local slips = { TPL.one1, TPL.one2, TPL.one4 }
	for _, mirror in ipairs({ false, true }) do
		for _, main in ipairs(mains) do
			for _, side in ipairs(mains) do
				for _, slip in ipairs(slips) do
					for _, ang in ipairs({ 40, 50, 65, 80 }) do
						local W = channelT({ main = main, side = side, slip = slip, angle = ang, mirror = mirror })
						for n, shape in pairs({ [2] = "diverge", [3] = "merge", [4] = "diverge+merge" }) do
							local name = string.format("%s main=%s side=%s slip=%s %d deg node %d", mirror and "LHT" or "RHT",
								main, side, slip, ang, n)
							local r, v = slipConns(W, n)
							eq(v.kind, "slip", name .. " " .. tostring(v.reason))
							eq(v.shape, shape, name)
							eq(v.side, mirror and "left" or "right", name)
							if r.conns then checkInvariants(v, r.conns, name) end
						end
					end
				end
			end
		end
	end
end)

test("left-hand traffic: the mirrored Channelized Junction gets the mirrored connections", function()
	for _, main in ipairs({ TPL.two1, TPL.two2, TPL.two3 }) do
		local R, L = channelT({ main = main }), channelT({ main = main, mirror = true })
		for _, n in ipairs({ 2, 3, 4 }) do
			local rr = Slip.plan(R, n, function() return {} end)
			local rl = Slip.plan(L, n, function() return {} end)
			local mirrored = {}
			for _, c in ipairs(rr.conns) do
				local L0, L1 = #R.seg(c.segment0).lanes, #R.seg(c.segment1).lanes
				mirrored[#mirrored + 1] = Rules.conn(c.segment0, L0 - 1 - c.lane0, c.segment1, L1 - 1 - c.lane1, true, false)
			end
			eq(Rules.connsText(rl.conns), Rules.connsText(mirrored), "node " .. n)
		end
	end
end)

test("two-way main roads with 1-3 lanes, 1- and 2-lane slips, diverge and merge, both sides", function()
	for _, mirror in ipairs({ false, true }) do
		for _, main in ipairs({ TPL.two1, TPL.two2, TPL.two3 }) do
			for _, branch in ipairs({ TPL.one1, TPL.one2 }) do
				for _, join in ipairs({ false, true }) do
					-- the kerb side of eastbound traffic: right in right-hand traffic; the mirror
					-- flips the geometry, so "right" in the unmirrored frame is the kerb in both
					local W = tee({ main = main, branch = branch, join = join, side = "right", angle = 35, mirror = mirror })
					local name = string.format("%s %s %s %s", mirror and "LHT" or "RHT", main, branch, join and "merge" or "diverge")
					local r, v = slipConns(W, 1)
					eq(v.kind, "slip", name .. " " .. tostring(v.reason))
					eq(v.shape, join and "merge" or "diverge", name)
					eq(#v.streams, 2, name)
					checkInvariants(v, r.conns, name)
					-- the far side (crossing oncoming traffic) is not a slip lane: an ordinary junction
					local Wf = tee({ main = main, branch = branch, join = join, side = "left", angle = 35, mirror = mirror })
					local vf = Slip.classify(Wf, 1)
					eq(vf.case, "X", name .. " far side: crossing rule")
					eq(vf.slipReason, "far_side_branch", name .. " far side")
				end
			end
		end
	end
end)

test("one-way main roads with 1-3 lanes: diverge / merge to either side (kerb = branch side)", function()
	for _, mirror in ipairs({ false, true }) do
		for _, main in ipairs({ TPL.one1, TPL.one2, TPL.one3, TPL.one4 }) do
			for _, branch in ipairs({ TPL.one1, TPL.one2 }) do
				for _, join in ipairs({ false, true }) do
					for _, side in ipairs({ "right", "left" }) do
						local W = tee({ main = main, branch = branch, join = join, side = side, angle = 30, mirror = mirror })
						local name = string.format("%s %s %s %s %s", mirror and "LHT" or "RHT", main, branch, join and "merge" or "diverge", side)
						local r, v = slipConns(W, 1)
						eq(v.kind, "slip", name .. " " .. tostring(v.reason))
						eq(v.case, "A", name)
						eq(v.side, nil, name)
						eq(#v.streams, 1, name)
						local expectKerb = side
						if mirror then expectKerb = side == "right" and "left" or "right" end
						eq(v.streams[1].kerb, expectKerb, name)
						checkInvariants(v, r.conns, name)
					end
				end
			end
		end
	end
end)

test("one-way 2-lane main, 1-lane slip to the right: exact connections", function()
	local W = tee({ main = TPL.one2, branch = TPL.one1, side = "right", angle = 30 })
	local r = Slip.plan(W, 1, function() return {} end)
	-- 31 ends at node 1: lanes k=1,2 -> idx 2,1; incoming kerb first (right) = ascending: 1, 2
	-- 32 starts at node 1: outgoing 1, 2, kerb first (right) = 2, 1; branch 33 (B- FV F-) lane 1
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns("31:1>33:1:R-,31:1>32:2:R-,31:2>32:1:R-")))
	local Wm = tee({ main = TPL.one2, branch = TPL.one1, side = "right", angle = 30, join = true })
	local rm = Slip.plan(Wm, 1, function() return {} end)
	-- merge: 33 joins the kerb lane 32:2; 31:1 -> 32:2 and 31:2 -> 32:1
	eq(Rules.connsText(rm.conns), Rules.connsText(F.parseConns("33:1>32:2:R-,31:1>32:2:R-,31:2>32:1:R-")))
end)

test("not slip nodes: plain road, Y fork, 5 roads, bus lane; crossroads go to sl_cross", function()
	-- crossroads of two-way roads: no one-way segment, the crossing rule (case X, test_cross.lua)
	local X = build({ [1] = { 0, 0 }, [2] = { 50, 0 }, [3] = { 0, 50 }, [4] = { -50, 0 }, [5] = { 0, -50 } },
		{ [1] = { 1, 2, TPL.two2 }, [2] = { 1, 3, TPL.two2 }, [3] = { 1, 4, TPL.two2 }, [4] = { 1, 5, TPL.two2 } })
	eq(Slip.classify(X, 1).case, "X")
	eq(Slip.classify(X, 2).kind, "none")
	-- symmetric one-way Y fork: no through road
	local Y = build({ [1] = { 0, 0 }, [2] = { -50, 0 }, [3] = { 50, 30 }, [4] = { 50, -30 } },
		{ [1] = { 2, 1, TPL.one2 }, [2] = { 1, 3, TPL.one2, dir(30), dir(30) }, [3] = { 1, 4, TPL.one2, dir(-30), dir(-30) } })
	local vy = Slip.classify(Y, 1)
	eq(vy.kind, "skip")
	eq(vy.reason, "ambiguous")
	-- one-way T: the branch goes off at 90 degrees both ways (no through road)
	local T = build({ [1] = { 0, 0 }, [2] = { -50, 0 }, [3] = { 0, 50 }, [4] = { 0, -50 } },
		{ [1] = { 2, 1, TPL.one2 }, [2] = { 1, 3, TPL.one2 }, [3] = { 1, 4, TPL.one2 } })
	eq(Slip.classify(T, 1).reason, "no_through")
	-- 5 road segments
	local five = build({ [1] = { 0, 0 }, [2] = { 50, 0 }, [3] = { 0, 50 }, [4] = { -50, 0 }, [5] = { 0, -50 }, [6] = { 40, 40 } },
		{ [1] = { 1, 2, TPL.two2 }, [2] = { 1, 3, TPL.two2 }, [3] = { 1, 4, TPL.two2 }, [4] = { 1, 5, TPL.two2 }, [5] = { 1, 6, TPL.one2 } })
	eq(Slip.classify(five, 1).kind, "skip")
	eq(Slip.classify(five, 1).reason, "roads_5")
	-- bus lane on the main road: a slip node of its car lanes (bus connections kept, test_bus.lua)
	local bus = tee({ main = TPL.two2_bus, branch = TPL.one2, side = "right" })
	eq(Slip.classify(bus, 1).case, "B")
	-- a one-way branch on a two-way road that turns too sharply (a side street, not a slip lane):
	-- the crossing rule
	local sharp = tee({ main = TPL.two2, branch = TPL.one2, side = "right", angle = 95 })
	eq(Slip.classify(sharp, 1).case, "X")
	ok(Slip.classify(sharp, 1).slipReason ~= nil, "not a slip lane")
	-- a two-way road splitting into a one-way pair (the roundabout splitter's split node)
	local split = build({ [1] = { 0, 0 }, [2] = { -50, 0 }, [3] = { 50, 10 }, [4] = { 50, -10 } },
		{ [1] = { 2, 1, TPL.two2 }, [2] = { 3, 1, TPL.one2 }, [3] = { 1, 4, TPL.one2 } })
	eq(Slip.classify(split, 1).kind, "none")
	eq(Slip.classify(split, 1).reason, "mixed_one_way")
end)

test("tram connections are kept untouched, road connections replaced", function()
	local W = tee({ main = TPL.two1_tram, branch = TPL.one2, side = "right", angle = 30 })
	local v = Slip.classify(W, 1)
	eq(v.kind, "slip")
	-- engine connections: tram straight through both ways, cars fanning out (crossing)
	local cur = F.parseConns("31:1>32:2:RT,32:1>31:2:RT,31:1>33:1:R-,31:1>33:2:R-")
	local r = Slip.plan(W, 1, function() return cur end)
	local tram = {}
	for _, c in ipairs(r.conns) do
		if c.withTram then tram[#tram + 1] = c end
	end
	eq(#tram, 2)
	for _, c in ipairs(tram) do ok(c.withRoad, "tram lane is also a road lane, straight on") end
	checkInvariants(v, r.conns, "tram")
	-- a tram-only track at the node does not count as a road
	local W2 = tee({ main = TPL.two2, branch = TPL.one2, side = "right", angle = 30 })
	W2.nodes[9] = { id = 9, x = 0, y = -50, segs = { 99 } }
	W2.segs[99] = { id = 99, node0 = 1, node1 = 9, p0 = { x = 0, y = 0 }, p1 = { x = 0, y = -50 },
		t0 = { x = 0, y = -50 }, t1 = { x = 0, y = -50 }, lanes = F.lanes(F.TPL.tram_only) }
	table.insert(W2.nodes[1].segs, 99)
	local cur2 = F.parseConns("99:1>31:1:-T")
	local r2 = Slip.plan(W2, 1, function() return cur2 end)
	eq(r2.view.kind, "slip")
	ok(Rules.connsText(r2.conns):find("99:1>31:1:-T", 1, true), "tram-only connection kept")
end)

test("plan: same when already applied; log fields carry kind=slip", function()
	local W = channelT()
	local r = Slip.plan(W, 2, function() return {} end)
	eq(r.status, "apply")
	local again = Slip.plan(W, 2, function() return r.conns end)
	eq(again.status, "same")
	local line = Rules.line("APPLY", Slip.logFields(r))
	ok(line:find("kind=slip node=2 shape=diverge case=B side=right", 1, true), line)
	ok(line:find("lanes=2_->_2_+_2_slip", 1, true), line)
	eq(Slip.plan(W, 5, function() return {} end).status, "none")
end)

---------------------------------------------------------------------------
-- Tangential ramps (in game 2026-10-11: every highway gore was skipped "ambiguous")

--- A highway gore: 2-lane carriageway west 2 -> 1 -> east 3, a 1-lane ramp leaving (or joining) at
-- node 1 with the highway's own direction there, curving to its far end at (x4, y4).
local function gore(x4, y4, join, throughEnd)
	local nodes = { [1] = { 0, 0 }, [2] = { -80, 0 }, [3] = throughEnd or { 80, 0 }, [4] = { x4, y4 } }
	local segs = { [31] = { 2, 1, TPL.one2 }, [32] = { 1, 3, TPL.one2, dir(0), dir(0) } }
	if join then
		segs[33] = { 4, 1, TPL.one1, dir(0), dir(0) }
	else
		segs[33] = { 1, 4, TPL.one1, dir(0), dir(0) }
	end
	return build(nodes, segs)
end

test("tangential off-ramp: the far ends decide; kerb on the ramp's side", function()
	local v = Slip.classify(gore(60, -8), 1)
	eq(v.kind, "slip")
	eq(v.splitBy, "far")
	eq(v.shape, "diverge")
	eq(v.streams[1].branchSeg, 33)
	eq(v.streams[1].throughSeg, 32)
	eq(v.streams[1].kerb, "right")
	local vl = Slip.classify(gore(60, 8), 1)
	eq(vl.streams[1].kerb, "left", "a left exit")
	checkInvariants(v, Slip.roadConns(v), "off-ramp")
end)

test("tangential on-ramp: the far ends decide", function()
	local v = Slip.classify(gore(-60, -8, true), 1)
	eq(v.kind, "slip")
	eq(v.splitBy, "far")
	eq(v.shape, "merge")
	eq(v.streams[1].branchSeg, 33)
	eq(v.streams[1].kerb, "right")
end)

test("far ends mirror each other: the lane count picks the through road", function()
	-- the carriageway bends 2 deg left, the ramp 2 deg right: same size of turn
	local d = dir(2)
	local v = Slip.classify(gore(60, -60 * math.tan(math.rad(2)), false, { 80 * d[1], 80 * d[2] }), 1)
	eq(v.kind, "slip")
	eq(v.splitBy, "lanes")
	eq(v.streams[1].throughSeg, 32, "the 2-lane road goes on")
	eq(v.streams[1].kerb, "right")
end)

test("a ramp that never leaves the highway's line stays ambiguous", function()
	local v = Slip.classify(gore(60, -0.2), 1)
	eq(v.kind, "skip")
	eq(v.reason, "ambiguous")
end)

test("merge: a ramp keeps its own lane when the through road still has two (3 + 1 -> 3), else it gives way", function()
	-- 3 + 1 -> 3: ramp q1 -> o1 alone; through p1 and p2 fold into o2, p3 -> o3
	eq(pairsText(Slip.pairs("merge", 3, 1, 3)), "p1>o2 p2>o2 p3>o3 q1>o1")
	-- 4 + 2 -> 4: two ramp lanes keep o1, o2; through 4 into o3, o4
	eq(pairsText(Slip.pairs("merge", 4, 2, 4)), "p1>o3 p2>o3 p3>o3 p4>o4 q1>o1 q2>o2")
	-- 2 + 1 -> 2: the through road would keep one lane: the ramp gives way into the kerb lane
	eq(pairsText(Slip.pairs("merge", 2, 1, 2)), "p1>o1 p2>o2 q1>o1")
	-- 2 + 1 -> 3: room for everyone, unchanged
	eq(pairsText(Slip.pairs("merge", 2, 1, 3)), "p1>o2 p2>o3 q1>o1")
end)

---------------------------------------------------------------------------
-- Merge look-ahead (PHASE7.md step 1): does the ramp keep its own lane? (sl_walk.lua, S.mergeLook)

--- The merge stream's look-ahead decision at node 1 of a F.mergeLine world, and the plan.
local function look(opt)
	local W = F.mergeLine(opt)
	local r = Slip.plan(W, 1, function() return {} end)
	local st
	for _, s in ipairs(r.view.streams or {}) do
		if s.shape == "merge" then st = s end
	end
	return st and st.look, r, st
end

test("merge look-ahead: each rule, one-way and two-way roads, both traffic sides", function()
	local cases = {
		-- the through road had 2 lanes 60 m back (the kerb lane was added): the ramp keeps its lane
		{ "lane_added", "own_lane", { up = { { "one3", 60 }, { "one2", 150 } }, down = { { "one3", 300 } } } },
		-- a real 3-lane road all the way back: the ramp gives way
		{ "through_road", "give_way", { up = { { "one3", 200 }, { "one3", 250 } }, down = { { "one3", 300 } } } },
		-- previous junction 50 m back: no room for the road's lanes to merge
		{ "junction_close", "give_way", { up = { { "one3", 50 } }, upJunction = true, down = { { "one3", 300 } } } },
		-- previous junction 120 m back: room, but a real 3-lane road
		{ "through_road", "give_way", { up = { { "one3", 120 } }, upJunction = true, down = { { "one3", 300 } } } },
		-- the kerb lane was added, but the out road drops a lane 100 m on: give way
		{ "drop_ahead", "give_way", { up = { { "one3", 60 }, { "one2", 150 } }, down = { { "one3", 100 }, { "one2", 200 } } } },
		-- the drop is 200 m on: the ramp keeps its lane
		{ "lane_added", "own_lane", { up = { { "one3", 60 }, { "one2", 150 } }, down = { { "one3", 200 }, { "one2", 200 } } } },
		-- a real 3-lane road with an off-ramp on the kerb side 250 m on: ramp traffic wants the kerb lane
		{ "exit_ahead", "own_lane", { up = { { "one3", 400 } }, down = { { "one3", 150 }, { "one3", 100 } }, downExit = "right" } },
		-- an exit on the far side does not count
		{ "through_road", "give_way", { up = { { "one3", 400 } }, down = { { "one3", 250 } }, downExit = "left" } },
		-- an exit beyond the walk (500 m) does not count
		{ "through_road", "give_way", { up = { { "one3", 400 } }, down = { { "one3", 500 } }, downExit = "right" } },
		-- lanes added AND the previous junction close: lane_added wins (rule 2 before rule 3)
		{ "lane_added", "own_lane", { up = { { "one3", 30 }, { "one2", 30 } }, upJunction = true, down = { { "one3", 300 } } } },
		-- rule 5: 4 + 2 -> 4, the through road had 3 lanes back (more than O - B = 2, fewer than T = 4)
		{ "lane_added", "own_lane", { up = { { "one4", 60 }, { "one3", 150 } }, down = { { "one4", 300 } }, ramp = "one2" } },
		-- two-way roads (case B): the same rules on the main road's eastbound lanes
		{ "lane_added", "own_lane", { up = { { "two3", 60 }, { "two2", 150 } }, down = { { "two3", 300 } } } },
		{ "through_road", "give_way", { up = { { "two3", 450 } }, down = { { "two3", 300 } } } },
		{ "junction_close", "give_way", { up = { { "two3", 40 } }, upJunction = true, down = { { "two3", 300 } } } },
		{ "drop_ahead", "give_way", { up = { { "two3", 60 }, { "two2", 100 } }, down = { { "two3", 80 }, { "two2", 100 } } } },
		{ "exit_ahead", "own_lane", { up = { { "two3", 450 } }, down = { { "two3", 200 } }, downExit = "right" } },
	}
	for ci, c in ipairs(cases) do
		for _, mirror in ipairs({ false, true }) do
			local opt = { up = {}, down = {}, upJunction = c[3].upJunction, downExit = c[3].downExit, mirror = mirror,
				ramp = c[3].ramp and TPL[c[3].ramp] }
			for _, sp in ipairs(c[3].up) do opt.up[#opt.up + 1] = { TPL[sp[1]], sp[2] } end
			for _, sp in ipairs(c[3].down) do opt.down[#opt.down + 1] = { TPL[sp[1]], sp[2] } end
			local name = string.format("case %d %s %s", ci, c[1], mirror and "LHT" or "RHT")
			local lk, r, st = look(opt)
			eq(r.view.kind, "slip", name .. " " .. tostring(r.view.reason))
			ok(lk ~= nil, name .. ": look-ahead ran")
			if lk then
				eq(lk.why, c[1], name)
				eq(lk.merge, c[2], name)
				eq(st.giveWay, c[2] == "give_way", name)
			end
			checkInvariants(r.view, r.conns, name)
			-- the connections follow the decision: 3 + 1 -> 3, the ramp alone in the kerb lane or not
			local into = {}
			local kerbOut = st.outSeg .. ":" .. st.o[1]
			for _, cn in ipairs(r.conns) do
				if cn.segment1 .. ":" .. cn.lane1 == kerbOut then into[#into + 1] = cn.segment0 end
			end
			if c[2] == "own_lane" then
				eq(#into, 1, name .. ": only the ramp into the kerb lane")
			else
				eq(#into, 2, name .. ": ramp and through kerb lane share it")
			end
			local line = Rules.line("APPLY", Slip.logFields(r))
			ok(line:find("merge=" .. c[2] .. " why=" .. c[1], 1, true), line)
		end
	end
end)

test("merge look-ahead: only merges whose counts allow the own lane; pairs follow giveWay", function()
	-- 2 + 1 -> 2: give way by the counts, no look-ahead, no merge= field
	local lk, r = look({ up = { { TPL.one2, 300 } }, down = { { TPL.one2, 300 } } })
	eq(lk, nil)
	ok(not Rules.line("APPLY", Slip.logFields(r)):find("merge=", 1, true), "no merge field")
	-- 2 + 1 -> 3: room for both, no look-ahead
	eq((look({ up = { { TPL.one2, 300 } }, down = { { TPL.one3, 300 } } })), nil)
	-- the pairs: giveWay true keeps the give-way merge, nil / false the count rule
	eq(pairsText(Slip.pairs("merge", 3, 1, 3, true)), "p1>o1 p2>o2 p3>o3 q1>o1")
	eq(pairsText(Slip.pairs("merge", 3, 1, 3, false)), "p1>o2 p2>o2 p3>o3 q1>o1")
	eq(pairsText(Slip.pairs("merge", 4, 2, 4, true)), "p1>o1 p2>o2 p3>o3 p4>o4 q1>o1 q2>o1")
end)

test("merge look-ahead: walks stay bounded on a long road and a loop back to the merge node", function()
	-- a 3-lane road of 60 x 10 m segments both ways: capped, decided as a real 3-lane road
	local up, down = {}, {}
	for k = 1, 60 do up[k] = { TPL.one3, 10 } end
	for k = 1, 60 do down[k] = { TPL.one3, 10 } end
	local lk = look({ up = up, down = down })
	eq(lk.why, "through_road")
	eq(lk.up.stop, "max_nodes")
	eq(lk.down.stop, "max_nodes")
	-- the out road loops back into the through road (a closed one-way circuit through the merge node)
	local d = F.dir(30)
	local nodes = { [1] = { 0, 0 }, [4] = { -50 * d[1], -50 * d[2] }, [2] = { 50, 0 }, [3] = { 50, 50 },
		[5] = { -50, 50 }, [6] = { -50, 0 } } -- 300 m round
	local segs = { [33] = { 4, 1, TPL.one1, d, d }, [41] = { 1, 2, TPL.one3 }, [42] = { 2, 3, TPL.one3 },
		[43] = { 3, 5, TPL.one3 }, [44] = { 5, 6, TPL.one3 }, [45] = { 6, 1, TPL.one3 } }
	local W = F.build(nodes, segs)
	local r = Slip.plan(W, 1, function() return {} end)
	eq(r.view.kind, "slip")
	local st = r.view.streams[1]
	eq(st.look.up.stop, "loop")
	eq(st.look.down.stop, "loop")
	eq(st.look.why, "through_road")
end)

test("exitAhead: kerb-side exits and turns at the out road's next junction, independent of segment order", function()
	-- J = node 1, traffic arriving from the west on segment 10 (3-lane one-way); two roads leave J,
	-- spec = { {far x, far y, tangent deg or nil}, ... }, drawn with ids 11, 12 and again as 12, 11
	local function J(spec, mirror, swap)
		local nodes = { [1] = { 0, 0 }, [2] = { -100, 0 } }
		local segs = { [10] = { 2, 1, TPL.one3 } }
		for k, sp in ipairs(spec) do
			local id = swap and (13 - k) or (10 + k)
			nodes[20 + k] = { sp[1], sp[2] }
			segs[id] = { 1, 20 + k, TPL.one2, sp[3] and dir(sp[3]), sp[3] and dir(sp[3]) }
		end
		return build(nodes, segs, mirror)
	end
	local cases = {
		{ "T end: right turn", { { 0, -60 }, { 0, 60 } }, true },
		{ "L corner: right 60 deg, left 90 deg", { { 30, -52 }, { 0, 60 } }, true },
		{ "L corner: left turns only", { { 30, 52 }, { 0, 60 } }, false },
		{ "symmetric fork +-20 deg", { { 94, -34 }, { 94, 34 } }, true },
		{ "straight on, exit right 30 deg", { { 100, 0 }, { 87, -50 } }, true },
		{ "straight on, exit left 30 deg", { { 100, 0 }, { 87, 50 } }, false },
		{ "tangential exit right", { { 100, 0, 0 }, { 60, -8, 0 } }, true },
		{ "tangential exit left", { { 100, 0, 0 }, { 60, 8, 0 } }, false },
	}
	for _, c in ipairs(cases) do
		for _, mirror in ipairs({ false, true }) do
			for _, swap in ipairs({ false, true }) do
				local name = string.format("%s %s%s", c[1], mirror and "LHT" or "RHT", swap and " swapped" or "")
				eq(Slip.exitAhead(J(c[2], mirror, swap), 1, 10, mirror and "left" or "right"), c[3], name)
			end
		end
	end
	-- missing pieces: no exit, never an error
	local W = J({ { 100, 0 }, { 87, -50 } })
	eq(Slip.exitAhead(W, 1, 77, "right"), false, "unknown in segment")
	eq(Slip.exitAhead(W, 99, 10, "right"), false, "unknown node")
end)

---------------------------------------------------------------------------
-- Plain lane drops and gains (PHASE7.md step 2): case "D"

--- A straight road through the plain node 1: west 2 -> 1 (segment 31, template `w`), 1 -> east 3
-- (segment 32, template `e`), both drawn west to east. opt.twoWayEast: a two-way medium road on from
-- node 3 (segment 33 to node 5; tells one-way roads the driving side). mirror: left-hand traffic.
local function line(w, e, opt)
	opt = opt or {}
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 } }
	local segs = { [31] = { 2, 1, w }, [32] = { 1, 3, e } }
	if opt.twoWayEast then
		nodes[5] = { 150, 0 }
		segs[33] = { 3, 5, TPL.two2 }
	end
	return build(nodes, segs, opt.mirror)
end

--- Mirrored connections of `conns` (lane indices reversed on every segment of world R).
local function mirrorConns(R, conns)
	local out = {}
	for _, c in ipairs(conns) do
		if c.withRoad then
			local L0, L1 = #R.seg(c.segment0).lanes, #R.seg(c.segment1).lanes
			out[#out + 1] = Rules.conn(c.segment0, L0 - 1 - c.lane0, c.segment1, L1 - 1 - c.lane1, true, false)
		end
	end
	return out
end

local TWO23 = "BS BV BV FV FV FV FS" -- two-way: 2 lanes westbound, 3 eastbound

test("lane drop: one-way 3 -> 2 and 2 -> 3, exact connections, both traffic sides", function()
	-- right-hand traffic: 31 ends at node 1, incoming 1, 2, 3 kerb first (right = ascending);
	-- 32 starts there, outgoing kerb first 2, 1. Drop: m1, m2 -> o1 (kerb lane ends), m3 -> o2.
	local W = line(TPL.one3, TPL.one2, { twoWayEast = true })
	local r = Slip.plan(W, 1, function() return {} end)
	eq(r.view.kind, "slip", tostring(r.view.reason))
	eq(r.view.case, "D")
	eq(r.view.shape, "lane_drop")
	eq(r.view.side, "right")
	eq(r.view.sideFrom, "walk")
	eq(r.status, "apply")
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns("31:1>32:2:R-,31:2>32:2:R-,31:3>32:1:R-")))
	checkInvariants(r.view, r.conns, "3 -> 2")
	-- gain 2 -> 3: the kerb lane feeds both kerb-side lanes
	local Wg = line(TPL.one2, TPL.one3, { twoWayEast = true })
	local rg = Slip.plan(Wg, 1, function() return {} end)
	eq(rg.view.shape, "lane_gain")
	eq(Rules.connsText(rg.conns), Rules.connsText(F.parseConns("31:1>32:3:R-,31:1>32:2:R-,31:2>32:1:R-")))
	checkInvariants(rg.view, rg.conns, "2 -> 3")
	-- left-hand traffic: the mirror image
	for _, pair in ipairs({ { TPL.one3, TPL.one2 }, { TPL.one2, TPL.one3 }, { TPL.one4, TPL.one2 }, { TPL.one1, TPL.one3 } }) do
		local R = line(pair[1], pair[2], { twoWayEast = true })
		local L = line(pair[1], pair[2], { twoWayEast = true, mirror = true })
		local rr = Slip.plan(R, 1, function() return {} end)
		local rl = Slip.plan(L, 1, function() return {} end)
		eq(rl.view.side, "left")
		eq(Rules.connsText(rl.conns), Rules.connsText(mirrorConns(R, rr.conns)), pair[1] .. " -> " .. pair[2])
		checkInvariants(rl.view, rl.conns, "LHT " .. pair[1] .. " -> " .. pair[2])
	end
end)

test("lane drop: one-way counts 1-4 both ways, both traffic sides: invariants, shape, side from the two-way road", function()
	local ones = { TPL.one1, TPL.one2, TPL.one3, TPL.one4 }
	for _, mirror in ipairs({ false, true }) do
		for i, w in ipairs(ones) do
			for j, e in ipairs(ones) do
				local name = string.format("%s %d -> %d", mirror and "LHT" or "RHT", i, j)
				local r = Slip.plan(line(w, e, { twoWayEast = true, mirror = mirror }), 1, function() return {} end)
				if i == j then
					eq(r.status, "none", name)
					eq(r.reason, "roads_2", name)
				else
					eq(r.view.case, "D", name)
					eq(r.view.shape, i > j and "lane_drop" or "lane_gain", name)
					eq(r.view.side, mirror and "left" or "right", name)
					checkInvariants(r.view, r.conns, name)
				end
			end
		end
	end
end)

test("lane drop: two-way roads, one or both directions changing, both traffic sides", function()
	local cases = {
		-- west, east, shape
		{ TPL.two3, TPL.two2, "lane_drop+gain" }, -- eastbound 3 -> 2, westbound 2 -> 3
		{ TPL.two1, TPL.two2, "lane_drop+gain" },
		{ TWO23, TPL.two2, "lane_drop" },        -- eastbound 3 -> 2, westbound 2 -> 2
		{ TPL.two2, TWO23, "lane_gain" },        -- eastbound 2 -> 3
		{ TWO23, TPL.two3, "lane_drop" },        -- westbound 3 -> 2, eastbound 3 -> 3
	}
	for _, mirror in ipairs({ false, true }) do
		for _, c in ipairs(cases) do
			local name = string.format("%s %s | %s", mirror and "LHT" or "RHT", c[1], c[2])
			local W = line(c[1], c[2], { mirror = mirror })
			local r = Slip.plan(W, 1, function() return {} end)
			eq(r.view.case, "D", name .. " " .. tostring(r.view.reason))
			eq(r.view.shape, c[3], name)
			eq(r.view.side, mirror and "left" or "right", name)
			eq(r.view.sideFrom, "two_way", name)
			eq(#r.view.streams, 2, name)
			checkInvariants(r.view, r.conns, name)
			if mirror then
				local rr = Slip.plan(line(c[1], c[2]), 1, function() return {} end)
				eq(Rules.connsText(r.conns), Rules.connsText(mirrorConns(line(c[1], c[2]), rr.conns)), name .. " mirrored")
			end
		end
	end
	-- 3 + 3 -> 2 + 2 exact (right-hand traffic)
	local W = line(TPL.two3, TPL.two2)
	local r = Slip.plan(W, 1, function() return {} end)
	-- 31 ends at node 1: eastbound (forward) lanes k=4..6 -> idx 3..1, kerb (right) first = ascending 1, 2, 3;
	-- 32 starts at node 1: eastbound out idx 3, 4, kerb first = 4, 3. Westbound: 32 in idx 1, 2 (kerb
	-- first ascending 1, 2), 31 out idx 4, 5, 6 (kerb first 6, 5, 4): gain fed by the kerb lane.
	eq(Rules.connsText(r.conns), Rules.connsText(F.parseConns(
		"31:1>32:4:R-,31:2>32:4:R-,31:3>32:3:R-,32:1>31:6:R-,32:1>31:5:R-,32:2>31:4:R-")))
	eq(Slip.summary(r.view), "3 -> 2; 2 -> 3")
	eq(Slip.mainLanes(r.view), 3)
end)

test("lane drop: nothing changes -> none (cheap); odd and unsafe nodes are left alone", function()
	-- equal counts: the common plain node
	for _, tpl in ipairs({ TPL.one2, TPL.two1, TPL.two2, TPL.two3, TWO23, TPL.two2_bus, TPL.two1_tram }) do
		local v = Slip.classify(line(tpl, tpl), 1)
		eq(v.kind, "none", tpl)
		eq(v.reason, "roads_2", tpl)
		eq(v.case, nil, tpl)
	end
	-- a two-way road going on as a one-way road: one direction has nowhere to go
	local v = Slip.classify(line(TPL.two2, TPL.one3), 1)
	eq(v.kind, "none")
	eq(v.reason, "one_way_end")
	-- two one-way roads against each other
	local clash = build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 } },
		{ [31] = { 2, 1, TPL.one3 }, [32] = { 3, 1, TPL.one2 } })
	eq(Slip.classify(clash, 1).reason, "one_way_clash")
	-- one-way roads with no two-way road nearby: the kerb side is unknown (the two-way roads above were
	-- remembered: forget them, as on a map where none was read yet)
	Slip.resetSide()
	local lone = Slip.classify(line(TPL.one3, TPL.one2), 1)
	eq(lone.kind, "none")
	eq(lone.reason, "no_side")
	-- bus lanes: the car lanes count (1 car lane + bus lane into 3 car lanes: a gain and a drop, test_bus.lua)
	local bus = Slip.classify(line(TPL.two2_bus, TPL.two3), 1)
	eq(bus.kind, "slip")
	eq(bus.shape, "lane_drop+gain")
	-- the two two-way roads disagree on the driving side
	local mixed = build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 } },
		{ [31] = { 2, 1, TPL.two3 }, [32] = { 1, 3, TPL.two2 } })
	mixed.segs[32].lanes = F.mirrorLanes(mixed.segs[32].lanes)
	eq(Slip.classify(mixed, 1).reason, "mixed_sides")
end)

test("lane drop: a one-way loop through the node (a refused ring) is never handled", function()
	-- square one-way loop, one side 3 lanes, the rest 2 (Ring.findRing refuses mixed_ring_lanes), with a
	-- two-way arm at node 3 telling the side
	local nodes = { [1] = { 0, 0 }, [2] = { 60, 0 }, [3] = { 60, 60 }, [4] = { 0, 60 }, [9] = { 120, 60 } }
	local segs = { [41] = { 1, 2, TPL.one3 }, [42] = { 2, 3, TPL.one2 }, [43] = { 3, 4, TPL.one2 }, [44] = { 4, 1, TPL.one2 },
		[45] = { 3, 9, TPL.two2 } }
	local W = build(nodes, segs)
	for _, n in ipairs({ 1, 2 }) do
		local v = Slip.classify(W, n)
		eq(v.kind, "none", "node " .. n)
		eq(v.reason, "loop", "node " .. n)
	end
	-- the probe roundabout's plain ring nodes and arm junctions are unchanged by the drop rule
	local R = F.PROBE_4LANE_MEDIUM.world()
	for _, n in ipairs({ 22768, 23292, 23293, 23294 }) do ok(Slip.classify(R, n).case ~= "D", "ring node " .. n) end
end)

test("lane drop: tram connections kept, road connections replaced; log kind=drop", function()
	-- two-way 1 + 1 with tram on both lanes, then 1 westbound + 2 eastbound (tram in the kerb lane)
	local W = line(TPL.two1_tram, "BS BT FV FT FS")
	local v = Slip.classify(W, 1)
	eq(v.case, "D")
	eq(v.shape, "lane_gain")
	-- engine: tram straight through both ways (eastbound tram lane 31:1 -> 32:3), cars fanned
	local cur = F.parseConns("31:1>32:3:RT,32:1>31:2:RT,31:1>32:2:R-,99:1>31:1:-T")
	local r = Slip.plan(W, 1, function() return cur end)
	local text = Rules.connsText(r.conns)
	ok(text:find("99:1>31:1:-T", 1, true), "tram-only connection kept: " .. text)
	ok(text:find("31:1>32:3:RT", 1, true), "tram flag kept on the road pair: " .. text)
	ok(text:find("32:1>31:2:RT", 1, true), text)
	checkInvariants(v, Rules.mergeTram(Slip.roadConns(v), {}), "tram")
	local line1 = Rules.line("APPLY", Slip.logFields(r))
	ok(line1:find("kind=drop node=1 shape=lane_gain case=D side=right side_from=two_way lanes=1_->_2;_1_->_1", 1, true), line1)
	eq(Slip.defaultConns(v), nil, "no game-default model: snapshot Reset")
	local again = Slip.plan(W, 1, function() return r.conns end)
	eq(again.status, "same")
end)

test("lane drop cost: unchanged plain nodes never walk; one-way drops into a big one-way grid stay bounded", function()
	local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
	--- Counts world reads (node / seg lookups) of a world.
	local function counted(W)
		local c = { node = 0, seg = 0 }
		local n0, s0 = W.node, W.seg
		W.node = function(id) c.node = c.node + 1; return n0(id) end
		W.seg = function(id) c.seg = c.seg + 1; return s0(id) end
		return W, c
	end
	-- cheap path: a long two-way road and a one-way road of equal counts: 4 segment reads per node
	for _, tpl in ipairs({ TPL.two2, TPL.one2 }) do
		local nodes, segs = {}, {}
		for i = 0, 160 do nodes[i + 1] = { i * 40, 0 } end
		for i = 1, 160 do segs[100 + i] = { i, i + 1, tpl } end
		local W, c = counted(build(nodes, segs))
		for n = 2, 160 do eq(Slip.classify(W, n).reason, "roads_2", tpl) end
		eq(c.node, 159, tpl .. ": one node read per node")
		eq(c.seg, 2 * 159, tpl .. ": two segment reads per node (no walk, no cycle search)")
	end
	-- worst case for a one-way drop: the out road feeds a 20 x 20 grid of one-way streets (all east /
	-- north, so no cycle closes) and no two-way road anywhere (sideNear walks every road to its cap)
	local function grid(alternate)
		local nodes, segs = { [1] = { -40, 0 }, [2] = { -100, 0 } }, { [11] = { 2, 1, TPL.one3 }, [12] = { 1, 1000, TPL.one2 } }
		local G = 20
		local function id(i, j) return 1000 + i * G + j end
		for i = 0, G - 1 do
			for j = 0, G - 1 do nodes[id(i, j)] = { i * 40, j * 40 } end
		end
		local sid = 5000
		for i = 0, G - 1 do
			for j = 0, G - 1 do
				-- alternate: rows / columns alternate direction (one-way blocks: cycles everywhere)
				if i < G - 1 then
					sid = sid + 1
					if alternate and j % 2 == 1 then segs[sid] = { id(i + 1, j), id(i, j), TPL.one2 }
					else segs[sid] = { id(i, j), id(i + 1, j), TPL.one2 } end
				end
				if j < G - 1 then
					sid = sid + 1
					if alternate and i % 2 == 1 then segs[sid] = { id(i, j + 1), id(i, j), TPL.one2 }
					else segs[sid] = { id(i, j), id(i, j + 1), TPL.one2 } end
				end
			end
		end
		return build(nodes, segs)
	end
	Slip.resetSide() -- the two-way road above was remembered; this is the worst case without a side
	local W, c = counted(grid(false))
	local t0 = os.clock()
	local v = Slip.classify(W, 1)
	local dt = os.clock() - t0
	eq(v.reason, "no_side")
	ok(c.node <= Ring.MAX_SEARCH_NODES + 2 * 14, "node reads bounded by the cycle search and walk caps: " .. c.node)
	local Wl, cl = counted(grid(true))
	t0 = os.clock()
	local vl = Slip.classify(Wl, 1)
	local dtl = os.clock() - t0
	ok(vl.reason == "loop" or vl.reason == "no_side", tostring(vl.reason))
	ok(cl.node <= Ring.MAX_SEARCH_NODES + 2 * 14, "node reads: " .. cl.node)
	-- 160 such nodes (a whole job of them, the world's reads cached as in game)
	local Wj = grid(false)
	t0 = os.clock()
	for _ = 1, 160 do Slip.classify(Wj, 1) end
	local job = os.clock() - t0
	print(string.format("lane drop worst case: %.3f ms (%d node / %d seg reads) acyclic grid, %.3f ms (%d / %d) one-way blocks; 160 in a row %.1f ms",
		dt * 1000, c.node, c.seg, dtl * 1000, cl.node, cl.seg, job * 1000))
end)

test("lane drop: a node with a road U-turn (a turnaround) is skipped, never wiped", function()
	local W = line(TPL.two3, TPL.two2)
	local cur = F.parseConns("31:1>32:4:R-,31:2>32:3:R-,31:3>31:4:R-,32:1>31:6:R-,32:2>31:5:R-")
	local r = Slip.plan(W, 1, function() return cur end)
	eq(r.status, "skip")
	eq(r.reason, "u_turn")
	eq(r.conns, nil, "nothing to write")
	-- a tram-only U-turn connection does not count (tram connections are kept anyway)
	local rt = Slip.plan(W, 1, function() return F.parseConns("31:1>32:4:R-,31:3>31:4:-T") end)
	eq(rt.status, "apply")
end)

test("lane drop: a segment with both ends at the node (self-loop) is left alone", function()
	local W = build({ [1] = { 0, 0 }, [2] = { 60, 0 } }, { [31] = { 1, 1, TWO23 } })
	W.nodes[1].segs = { 31, 31 }
	W.segs[31].p1 = { x = 60, y = 10 }
	local v = Slip.classify(W, 1)
	eq(v.kind, "none")
	eq(v.reason, "self_loop")
end)

---------------------------------------------------------------------------
-- Exit-only kerb lanes before a diverge (PHASE7.md step 3): S.exitLanes, S.divergeLook, pairs flag

test("exit-only diverge: counts and pairs tables (3->3+1, 3->2+1, 4->3+1, 2->2+1, 4->4+1, 2-lane branch)", function()
	-- S.exitLanes: N <= T and through keeps 2+ lanes; N > T is dedicated by the counts already
	eq(Slip.exitLanes(3, 3, 1), 1)
	eq(Slip.exitLanes(4, 4, 1), 1)
	eq(Slip.exitLanes(3, 4, 1), 1)
	eq(Slip.exitLanes(3, 3, 2), 1, "a 2-lane branch off 3 lanes: one exit-only lane (through keeps 2)")
	eq(Slip.exitLanes(4, 4, 2), 2)
	eq(Slip.exitLanes(5, 5, 3), 3)
	eq(Slip.exitLanes(2, 2, 1), 0, "2 lanes: through would keep one")
	eq(Slip.exitLanes(1, 1, 1), 0)
	eq(Slip.exitLanes(3, 2, 1), 0, "3 -> 2 + 1: dedicated by the counts")
	eq(Slip.exitLanes(4, 3, 1), 0, "4 -> 3 + 1: dedicated by the counts")
	eq(Slip.exitLanes(3, 3, 0), 0)
	eq(Slip.exitLanes(nil, 3, 1), 0)
	-- 3 -> 3 + 1: shared (count rule) vs exit-only (m2 also feeds the kerb through lane)
	eq(pairsText(Slip.pairs("diverge", 3, 3, 1)), "m1>b1 m1>t1 m2>t2 m3>t3")
	eq(pairsText(Slip.pairs("diverge", 3, 3, 1, false)), "m1>b1 m1>t1 m2>t2 m3>t3")
	eq(pairsText(Slip.pairs("diverge", 3, 3, 1, true)), "m1>b1 m2>t1 m2>t2 m3>t3")
	-- 3 -> 2 + 1 and 4 -> 3 + 1: the flag changes nothing (kerb lane exit-only by the counts)
	eq(pairsText(Slip.pairs("diverge", 3, 2, 1, true)), "m1>b1 m2>t1 m3>t2")
	eq(pairsText(Slip.pairs("diverge", 3, 2, 1, true)), pairsText(Slip.pairs("diverge", 3, 2, 1)))
	eq(pairsText(Slip.pairs("diverge", 4, 3, 1, true)), "m1>b1 m2>t1 m3>t2 m4>t3")
	eq(pairsText(Slip.pairs("diverge", 4, 3, 1, true)), pairsText(Slip.pairs("diverge", 4, 3, 1)))
	-- 2 -> 2 + 1: unchanged, shared
	eq(pairsText(Slip.pairs("diverge", 2, 2, 1, true)), "m1>b1 m1>t1 m2>t2")
	-- 4 -> 4 + 1, 3 -> 4 + 1 (the through road widens: m2 feeds the kerb-side through lanes)
	eq(pairsText(Slip.pairs("diverge", 4, 4, 1, true)), "m1>b1 m2>t1 m2>t2 m3>t3 m4>t4")
	eq(pairsText(Slip.pairs("diverge", 3, 4, 1, true)), "m1>b1 m2>t1 m2>t2 m2>t3 m3>t4")
	-- 2-lane branch: 3 -> 3 + 2 one exit-only lane feeding both branch lanes; 4 -> 4 + 2 two
	eq(pairsText(Slip.pairs("diverge", 3, 3, 2, true)), "m1>b1 m1>b2 m2>t1 m2>t2 m3>t3")
	eq(pairsText(Slip.pairs("diverge", 4, 4, 2, true)), "m1>b1 m2>b2 m3>t1 m3>t2 m3>t3 m4>t4")
	-- merges ignore the meaning of the flag for diverges (the same 5th argument is giveWay there)
	eq(pairsText(Slip.pairs("merge", 3, 1, 3, true)), "p1>o1 p2>o2 p3>o3 q1>o1")
end)

test("exit-only diverge: invariants for all lane counts; exit lanes feed only the branch, through keeps 2+", function()
	for N = 1, 5 do
		for T = 1, 5 do
			for B = 1, 3 do
				local name = string.format("diverge %d -> %d + %d", N, T, B)
				local pr = Slip.pairs("diverge", N, T, B, true)
				local outs = checkPairs("diverge", N, T, B, pr)
				local E = Slip.exitLanes(N, T, B)
				if E == 0 then
					eq(pairsText(pr), pairsText(Slip.pairs("diverge", N, T, B)), name .. ": unchanged")
				else
					ok(N >= 3 and N <= T and N - E >= 2, name)
					for i = 1, N do
						local toBranch, toThrough = false, false
						for _, j in ipairs(outs[i] or {}) do
							if j <= B then toBranch = true else toThrough = true end
						end
						if i <= E then
							ok(toBranch and not toThrough, name .. ": lane " .. i .. " exit-only")
						else
							ok(toThrough and not toBranch, name .. ": lane " .. i .. " through only")
						end
					end
				end
			end
		end
	end
end)

--- The diverge stream's look-ahead decision at node 1 of a F.divergeLine world, and the plan.
local function dlook(opt)
	local W = F.divergeLine(opt)
	local r = Slip.plan(W, 1, function() return {} end)
	local st
	for _, s in ipairs(r.view.streams or {}) do
		if s.shape == "diverge" then st = s end
	end
	return st and st.look, r, st
end

--- Segments the kerb-first in lanes 1..k of a diverge stream connect to: { [i] = { [seg] = true } }.
local function kerbTargets(conns, st, k)
	local out = {}
	for i = 1, k do
		out[i] = {}
		local key = st.inSeg .. ":" .. st.m[i]
		for _, c in ipairs(conns) do
			if c.withRoad and c.segment0 .. ":" .. c.lane0 == key then out[i][c.segment1] = true end
		end
	end
	return out
end

test("exit-only diverge look-ahead: each rule, one-way and two-way roads, left exits, both traffic sides", function()
	local cases = {
		-- why, decision, exit lanes, world
		-- a long 3-lane road (all lanes the whole walk): exit-only by the counts
		{ "through_road", "exit_only", 1, { up = { { "one3", 200 }, { "one3", 250 } }, down = { { "one3", 300 } } } },
		-- the kerb lane was added 60 m back (an auxiliary lane): exit-only
		{ "lane_added", "exit_only", 1, { up = { { "one3", 60 }, { "one2", 150 } }, down = { { "one3", 300 } } } },
		-- the previous junction 50 m back: shared (no room to move out of the kerb lane)
		{ "junction_close", "shared", 1, { up = { { "one3", 50 } }, upJunction = true, down = { { "one3", 300 } } } },
		-- the previous junction 120 m back: room; exit-only
		{ "through_road", "exit_only", 1, { up = { { "one3", 120 } }, upJunction = true, down = { { "one3", 300 } } } },
		-- the lane was added 30 m back, junction 60 m back: lane_added wins (rule 1 before rule 2)
		{ "lane_added", "exit_only", 1, { up = { { "one3", 30 }, { "one2", 30 } }, upJunction = true, down = { { "one3", 300 } } } },
		-- 4 -> 4 + 2: two exit lanes; the road had 3 lanes back (one of the two added): exit-only
		{ "lane_added", "exit_only", 2, { up = { { "one4", 60 }, { "one3", 150 } }, down = { { "one4", 300 } }, ramp = "one2" } },
		-- the same, its junction close: shared (only one of the exit lanes was added)
		{ "junction_close", "shared", 2, { up = { { "one4", 30 }, { "one3", 30 } }, upJunction = true, down = { { "one4", 300 } }, ramp = "one2" } },
		-- 4 -> 4 + 2 with both exit lanes added (2 lanes back): exit-only although the junction is close
		{ "lane_added", "exit_only", 2, { up = { { "one4", 30 }, { "one2", 30 } }, upJunction = true, down = { { "one4", 300 } }, ramp = "one2" } },
		-- a 2-lane branch off 3 lanes: one exit-only lane feeding both branch lanes
		{ "through_road", "exit_only", 1, { up = { { "one3", 400 } }, down = { { "one3", 300 } }, ramp = "one2" } },
		-- 3 -> 4 + 1 (the through road widens at the exit)
		{ "through_road", "exit_only", 1, { up = { { "one3", 400 } }, down = { { "one4", 300 } } } },
		-- a left exit (case A: the kerb is the branch's side)
		{ "through_road", "exit_only", 1, { up = { { "one3", 400 } }, down = { { "one3", 300 } }, branch = "left" } },
		{ "junction_close", "shared", 1, { up = { { "one3", 40 } }, upJunction = true, down = { { "one3", 300 } }, branch = "left" } },
		-- two-way roads (case B): the same rules on the main road's eastbound lanes
		{ "through_road", "exit_only", 1, { up = { { "two3", 450 } }, down = { { "two3", 300 } } } },
		{ "lane_added", "exit_only", 1, { up = { { "two3", 60 }, { "two2", 150 } }, down = { { "two3", 300 } } } },
		{ "junction_close", "shared", 1, { up = { { "two3", 40 } }, upJunction = true, down = { { "two3", 300 } } } },
	}
	for ci, c in ipairs(cases) do
		for _, mirror in ipairs({ false, true }) do
			local opt = { up = {}, down = {}, upJunction = c[4].upJunction, branch = c[4].branch, mirror = mirror,
				ramp = c[4].ramp and TPL[c[4].ramp] }
			for _, sp in ipairs(c[4].up) do opt.up[#opt.up + 1] = { TPL[sp[1]], sp[2] } end
			for _, sp in ipairs(c[4].down) do opt.down[#opt.down + 1] = { TPL[sp[1]], sp[2] } end
			local name = string.format("case %d %s %s", ci, c[1], mirror and "LHT" or "RHT")
			local lk, r, st = dlook(opt)
			eq(r.view.kind, "slip", name .. " " .. tostring(r.view.reason))
			ok(lk ~= nil, name .. ": look-ahead ran")
			if lk and st then
				eq(lk.why, c[1], name)
				eq(lk.diverge, c[2], name)
				eq(lk.exits, c[3], name)
				eq(st.exitOnly, c[2] == "exit_only", name)
				local kerb = c[4].branch == "left" and (mirror and "right" or "left") or (mirror and "left" or "right")
				eq(st.kerb, kerb, name .. ": kerb side")
				checkInvariants(r.view, r.conns, name)
				-- the connections follow the decision
				local tg = kerbTargets(r.conns, st, #st.m)
				for i = 1, #st.m do
					local b, t = tg[i][st.branchSeg] == true, tg[i][st.throughSeg] == true
					if c[2] == "exit_only" and i <= c[3] then
						ok(b and not t, name .. ": lane " .. i .. " exit-only")
					elseif c[2] == "shared" and i == 1 then
						ok(b and t, name .. ": kerb lane shared")
					else
						ok(t and not b, name .. ": lane " .. i .. " through only")
					end
				end
				local line = Rules.line("APPLY", Slip.logFields(r))
				ok(line:find("diverge=" .. c[2] .. " why=" .. c[1], 1, true), line)
				ok(not line:find("merge=", 1, true), line)
			end
		end
	end
end)

test("exit-only diverge: no look-ahead where the counts decide (2->2+1 shared, 3->2+1 and 4->3+1 dedicated)", function()
	for _, mirror in ipairs({ false, true }) do
		local side = mirror and "LHT" or "RHT"
		-- 2 -> 2 + 1 (one-way and two-way): the kerb lane stays shared, no diverge= field
		for _, tpl in ipairs({ TPL.one2, TPL.two2 }) do
			local lk, r, st = dlook({ up = { { tpl, 400 } }, down = { { tpl, 300 } }, mirror = mirror })
			eq(lk, nil, side .. " 2 -> 2 + 1")
			eq(st.exitOnly, nil)
			local tg = kerbTargets(r.conns, st, 1)
			ok(tg[1][st.branchSeg] and tg[1][st.throughSeg], side .. " 2 -> 2 + 1 kerb lane shared")
			checkInvariants(r.view, r.conns, side .. " 2 -> 2 + 1")
			ok(not Rules.line("APPLY", Slip.logFields(r)):find("diverge=", 1, true), "no diverge field")
		end
		-- 3 -> 2 + 1 and 4 -> 3 + 1: the kerb lane is the branch's alone already
		for _, pair in ipairs({ { TPL.one3, TPL.one2 }, { TPL.one4, TPL.one3 }, { TPL.two3, TPL.two2 } }) do
			local name = side .. " " .. pair[1] .. " -> " .. pair[2]
			local lk, r, st = dlook({ up = { { pair[1], 400 } }, down = { { pair[2], 300 } }, mirror = mirror })
			eq(r.view.kind, "slip", name)
			eq(lk, nil, name)
			local tg = kerbTargets(r.conns, st, 1)
			ok(tg[1][st.branchSeg] and not tg[1][st.throughSeg], name .. ": kerb lane exit-only by the counts")
			checkInvariants(r.view, r.conns, name)
		end
	end
	-- the Channelized Junction on a 3-lane road: 3 -> 3 + 2 slip lane, exit-only (its arm ends 30 m on:
	-- a dead end, not a junction); the merge node and the 2-lane version unchanged
	for _, mirror in ipairs({ false, true }) do
		local W = channelT({ main = TPL.two3, mirror = mirror })
		local r = Slip.plan(W, 2, function() return {} end)
		eq(r.view.shape, "diverge")
		local st = r.view.streams[1].shape == "diverge" and r.view.streams[1] or r.view.streams[2]
		eq(st.look.diverge, "exit_only")
		eq(st.look.why, "through_road")
		checkInvariants(r.view, r.conns, "channel 3-lane")
		local W2 = channelT({ mirror = mirror })
		local v2 = Slip.classify(W2, 2)
		for _, s in ipairs(v2.streams) do eq(s.look, nil, "2-lane channel: no look-ahead") end
	end
end)

test("exit-only diverge: log of a node with both a diverge and a merge decision, walks bounded, nil-safe", function()
	-- logFields: diverge=, merge=, then why= with the diverge's reason first
	local function lanes(k) local l = {} for i = 1, k do l[i] = i end return l end
	local r = { node = 7, before = 6, after = 6, view = { case = "B", shape = "diverge+merge", side = "right", streams = {
		{ shape = "merge", p = lanes(3), q = lanes(1), o = lanes(3), look = { merge = "own_lane", why = "lane_added" } },
		{ shape = "diverge", m = lanes(3), t = lanes(3), b = lanes(1), look = { diverge = "shared", why = "junction_close" } },
	} } }
	local line = Rules.line("APPLY", Slip.logFields(r))
	ok(line:find("diverge=shared merge=own_lane why=junction_close,lane_added", 1, true), line)
	-- a 3-lane road of 60 x 10 m segments back: the walk stops at its node cap, exit-only by the counts
	local up = {}
	for k = 1, 60 do up[k] = { TPL.one3, 10 } end
	local lk = dlook({ up = up, down = { { TPL.one3, 300 } } })
	eq(lk.why, "through_road")
	eq(lk.up.stop, "max_nodes")
	-- a missing in segment (bulldozed): the walk ends, no error
	local W = F.divergeLine({ up = { { TPL.one3, 200 } }, down = { { TPL.one3, 200 } } })
	local look2 = Slip.divergeLook(W, 1, { m = lanes(3), t = lanes(3), b = lanes(1), inSeg = 999 })
	eq(look2.up.stop, "no_seg")
	eq(look2.diverge, "exit_only")
end)

---------------------------------------------------------------------------
-- Remembered driving side (PHASE7.md step 3): one-way roads far from any two-way road

test("remembered side: a two-way road read anywhere tells a lone one-way lane drop its side; reset forgets", function()
	for _, mirror in ipairs({ false, true }) do
		local want = mirror and "left" or "right"
		Slip.resetSide()
		local lone = line(TPL.one3, TPL.one2, { mirror = mirror })
		eq(Slip.rememberedSide(lone), nil)
		eq(Slip.classify(lone, 1).reason, "no_side", "nothing remembered yet")
		-- any classified node with a two-way road remembers it as the anchor (here the dead end 61 of a
		-- two-way road far away in the same world, not connected to the lone one-way roads)
		F.merge(lone, build({ [61] = { 0, 500 }, [62] = { 60, 500 } }, { [71] = { 61, 62, TPL.two2 } }, mirror))
		eq(Slip.classify(lone, 61).reason, "roads_1")
		eq(Slip.rememberedSide(lone), want)
		local an, as = Slip.rememberedAnchor()
		eq(an, 61)
		eq(as, 71)
		local r = Slip.plan(lone, 1, function() return {} end)
		eq(r.view.case, "D")
		eq(r.view.side, want)
		eq(r.view.sideFrom, "remembered")
		checkInvariants(r.view, r.conns, "remembered " .. want)
		-- the same connections as with a two-way road nearby
		local near = Slip.plan(line(TPL.one3, TPL.one2, { mirror = mirror, twoWayEast = true }), 1, function() return {} end)
		eq(near.view.sideFrom, "walk")
		eq(Rules.connsText(r.conns), Rules.connsText(near.conns))
		ok(Rules.line("APPLY", Slip.logFields(r)):find("side_from=remembered", 1, true))
		Slip.resetSide()
		eq(Slip.classify(lone, 1).reason, "no_side", "forgotten")
		-- sideNear's walk remembers what it finds
		local near2 = line(TPL.one3, TPL.one2, { mirror = mirror, twoWayEast = true })
		Slip.classify(near2, 1)
		eq(Slip.rememberedSide(near2), want)
	end
end)

test("remembered side: only reliable readings count; case A ignores it; junk ignored", function()
	Slip.rememberSide(nil, 31)
	eq(Slip.rememberedAnchor(), nil, "no node: ignored")
	-- a left-hand road far from the junctions below (nodes 61-62, segment 71) is the anchor
	local function withLeft(W)
		return F.merge(W, build({ [61] = { 0, 500 }, [62] = { 60, 500 } }, { [71] = { 61, 62, TPL.two2 } }, true))
	end
	Slip.rememberSide(61, 71)
	-- two two-way roads that disagree (skip mixed_sides) leave the anchor alone
	local mixed = build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 } },
		{ [31] = { 2, 1, TPL.two3 }, [32] = { 1, 3, TPL.two2 } })
	mixed.segs[32].lanes = F.mirrorLanes(mixed.segs[32].lanes)
	withLeft(mixed)
	eq(Slip.classify(mixed, 1).reason, "mixed_sides")
	eq(Slip.rememberedSide(mixed), "left")
	-- case A (all one-way): the kerb is the branch's side, whatever is remembered
	local A = withLeft(F.divergeLine({ up = { { TPL.one3, 400 } }, down = { { TPL.one3, 300 } } }))
	local v = Slip.classify(A, 1)
	eq(v.case, "A")
	eq(v.sideFrom, "branch")
	eq(v.streams[1].kerb, "right")
	eq(Slip.rememberedSide(A), "left", "case A tells nothing")
	-- a two-way road that does tell (right-hand traffic) overwrites it
	local T = tee({ main = TPL.two2, branch = TPL.one1 })
	Slip.classify(T, 1)
	eq(Slip.rememberedSide(T), "right")
	local an, as = Slip.rememberedAnchor()
	eq(an, 1)
	ok(as == 31 or as == 32, tostring(as))
end)

test("remembered side: the anchor is re-read in the current world (gone, now one-way, another save)", function()
	--- A lone one-way lane drop (node 1, segments 31-32) plus a separate road 61 -> 62 (segment 71,
	-- template tpl, mirrored when lht), not connected to it.
	local function world(tpl, lht, mirror)
		local W = line(TPL.one3, TPL.one2, { mirror = mirror })
		return F.merge(W, build({ [61] = { 0, 500 }, [62] = { 60, 500 } }, { [71] = { 61, 62, tpl } }, lht))
	end
	for _, mirror in ipairs({ false, true }) do
		local want = mirror and "left" or "right"
		local name = mirror and "LHT" or "RHT"
		-- the anchor (61, 71) read in a world where it is a two-way road
		local W1 = world(TPL.two2, mirror, mirror)
		Slip.classify(W1, 61)
		eq(Slip.rememberedSide(W1), want, name)
		-- anchor gone: its node bulldozed (another world without nodes 61 / 62): nil, and dropped
		local gone = line(TPL.one3, TPL.one2, { mirror = mirror })
		local v = Slip.classify(gone, 1)
		eq(v.reason, "no_side", name .. ": anchor node gone")
		eq(Slip.rememberedAnchor(), nil, name .. ": anchor dropped")
		eq(Slip.rememberedSide(W1), nil, name .. ": stays dropped")
		-- the node still there but the segment no longer attached to it (replaced by segment 72)
		Slip.rememberSide(61, 71)
		local W2 = world(TPL.two2, mirror, mirror)
		W2.segs[72], W2.segs[71] = W2.segs[71], nil
		W2.nodes[61].segs, W2.nodes[62].segs = { 72 }, { 72 }
		eq(Slip.classify(W2, 1).reason, "no_side", name .. ": anchor segment detached")
		eq(Slip.rememberedAnchor(), nil)
		-- anchor now a one-way road (the same ids rebuilt one-way): nil
		Slip.rememberSide(61, 71)
		local W3 = world(TPL.one2, mirror, mirror)
		eq(Slip.classify(W3, 1).reason, "no_side", name .. ": anchor now one-way")
		eq(Slip.rememberedAnchor(), nil)
		-- another save: the same ids form a road of the other driving side; its side is used
		local other = mirror and "right" or "left"
		Slip.rememberSide(61, 71)
		local W4 = world(TPL.two2, not mirror, mirror)
		eq(Slip.rememberedSide(W4), other, name .. ": re-read in the other save")
		-- (the lone drop itself keeps its own geometry; only the side comes from the anchor)
		local r = Slip.plan(W4, 1, function() return {} end)
		eq(r.view.sideFrom, "remembered")
		eq(r.view.side, other, name .. ": the other save's side, never the old one")
		checkInvariants(r.view, r.conns, name .. " other save")
	end
end)

test("remembered side: setting the anchor costs no world reads; using it one node and one segment read", function()
	local W = line(TPL.two2, TPL.two2)
	local c = { node = 0, seg = 0 }
	local n0, s0 = W.node, W.seg
	W.node = function(id) c.node = c.node + 1; return n0(id) end
	W.seg = function(id) c.seg = c.seg + 1; return s0(id) end
	eq(Slip.classify(W, 1).reason, "roads_2")
	eq(c.node, 1)
	eq(c.seg, 2, "the classify reads only, the anchor adds none")
	c.node, c.seg = 0, 0
	eq(Slip.rememberedSide(W), "right")
	eq(c.node, 1)
	eq(c.seg, 1)
end)

test("exit-only diverge and merge look-ahead on one node: the Channelized side node on a 3-lane side road", function()
	-- side node 4: southbound 3 -> 3 + 1 (slip 22 leaves: exit-only, its arm a 30 m dead end, no junction
	-- behind), northbound 3 + 1 -> 3 (slip 21 joins 35 m after the centre junction: give way); each stream
	-- decides on its own and the log names both
	for _, mirror in ipairs({ false, true }) do
		local name = mirror and "LHT" or "RHT"
		local W = channelT({ main = TPL.two3, side = TPL.two3, slip = TPL.one1, mirror = mirror })
		local r = Slip.plan(W, 4, function() return {} end)
		eq(r.view.shape, "diverge+merge", name)
		local d, m
		for _, st in ipairs(r.view.streams) do
			if st.shape == "diverge" then d = st elseif st.shape == "merge" then m = st end
		end
		eq(d.look.diverge, "exit_only", name)
		eq(d.look.why, "through_road", name)
		eq(d.exitOnly, true)
		eq(m.look.merge, "give_way", name)
		eq(m.look.why, "junction_close", name)
		eq(m.giveWay, true)
		checkInvariants(r.view, r.conns, name)
		local tg = kerbTargets(r.conns, d, #d.m)
		ok(tg[1][d.branchSeg] and not tg[1][d.throughSeg], name .. ": kerb lane exit-only")
		local text = Rules.line("APPLY", Slip.logFields(r))
		ok(text:find("diverge=exit_only merge=give_way why=through_road,junction_close", 1, true), text)
	end
end)

---------------------------------------------------------------------------
-- Shallow ramps on a two-way road (sl_cross X.shallowRamps; in game 2026-10-11: an interchange whose
-- ramps leave and join a 3+3 road alongside it, tangents 80-100 deg off the road at the node)

--- Connections from segment a into segment b.
local function connsFromTo(conns, a, b)
	local out = {}
	for _, c in ipairs(conns) do
		if c.withRoad and c.segment0 == a and c.segment1 == b then out[#out + 1] = c end
	end
	return out
end

test("shallow ramps, node 60274 layout: 4-lane ramp out and in, tangents 85 / 95 deg: slip lanes, nothing across", function()
	for _, mirror in ipairs({ false, true }) do
		for _, a in ipairs({ 85, 95 }) do
			local name = string.format("%s tangent %d", mirror and "LHT" or "RHT", a)
			-- 60103@-40(0,4) out on the kerb side of the 60804 direction, 60882@130(4,0) in on the other
			-- side (the main road 45 / -135 turned onto the x axis: -40 -> -85, 130 -> 85)
			local W = F.rampNode({ mirror = mirror, ramps = {
				{ id = 33, leaving = true, tan = -a, far = -20, tpl = F.RAMP4 },
				{ id = 34, leaving = false, tan = a, far = 20, tpl = F.RAMP4 } } })
			local r, v = slipConns(W, 1)
			eq(v.case, "B", name .. " " .. tostring(v.reason) .. " " .. tostring(v.slipReason))
			eq(v.shape, "diverge+merge", name)
			eq(v.splitBy or "node", a < 90 and "node" or "shallow", name .. " decided by")
			checkInvariants(v, r.conns, name)
			eq(#connsFromTo(r.conns, 12, 33), 0, name .. ": no turn across into the ramp out")
			eq(#connsFromTo(r.conns, 34, 12), 0, name .. ": the joining ramp never turns across the road")
			ok(#connsFromTo(r.conns, 11, 33) > 0 and #connsFromTo(r.conns, 34, 11) > 0, name .. ": ramps used on their own side")
			-- only the kerb lane peels off (3 lanes, exit-only), the other two go straight
			local d
			for _, st in ipairs(v.streams) do if st.shape == "diverge" then d = st end end
			for _, c in ipairs(connsFromTo(r.conns, 11, 33)) do eq(c.lane0, d.m[1], name .. ": kerb lane into the ramp") end
			if a >= 90 then
				local text = Rules.line("APPLY", Slip.logFields(r))
				ok(text:find("split=shallow", 1, true) and text:find("ramp_deg=33:", 1, true), text)
			end
		end
	end
end)

test("shallow ramps, nodes 60950 / 64312 layout: a ramp out on each side, both diverges, none across", function()
	for _, mirror in ipairs({ false, true }) do
		for _, a in ipairs({ 80, 90, 100 }) do
			local name = string.format("%s tangent %d", mirror and "LHT" or "RHT", a)
			-- 60343@-35(0,2) and 64315@125(0,2) on a 3+3 road 45 / -135 (turned: -80 and +80); each
			-- peels off alongside its own carriageway (by the tangents both lean towards one direction)
			local W = F.rampNode({ mirror = mirror, ramps = {
				{ id = 33, leaving = true, tan = -a, far = -20 },
				{ id = 34, leaving = true, tan = a, far = 160 } } })
			local r, v = slipConns(W, 1)
			eq(v.case, "B", name .. " " .. tostring(v.reason) .. " " .. tostring(v.slipReason))
			eq(v.shape, "diverge", name)
			eq(v.splitBy, "shallow", name)
			checkInvariants(v, r.conns, name)
			eq(#connsFromTo(r.conns, 12, 33), 0, name .. ": westbound never into the eastbound ramp")
			eq(#connsFromTo(r.conns, 11, 34), 0, name .. ": eastbound never into the westbound ramp")
			for _, st in ipairs(v.streams) do
				eq(st.exitOnly, true, name .. " exit-only")
				local own = st.inSeg == 11 and 33 or 34
				eq(st.branchSeg, own, name .. " ramp on its own side")
				for _, c in ipairs(connsFromTo(r.conns, st.inSeg, own)) do eq(c.lane0, st.m[1], name .. ": kerb lane only") end
				-- the other two lanes go straight
				eq(#connsFromTo(r.conns, st.inSeg, st.throughSeg), 3, name .. " through lanes")
			end
		end
	end
end)

test("shallow ramps: the chord decides, 60 deg off the road at most; steeper stays the crossing rule", function()
	for _, mirror in ipairs({ false, true }) do
		for _, far in ipairs({ -45, -75 }) do
			local name = string.format("%s far %d", mirror and "LHT" or "RHT", far)
			-- tangent 95 deg off at the node: by the tangents a far-side branch of the other direction
			local W = F.rampNode({ mirror = mirror, ramps = { { id = 33, leaving = true, tan = -95, far = far, stub = 4 } } })
			local v = Slip.classify(W, 1)
			local deg = tonumber(table.concat(v.rampDeg or {}, ","):match("^33:(%d+)$"))
			ok(deg ~= nil, name .. " measured")
			if far == -45 then
				ok(deg <= Cross.SHALLOW_MAX_DEG, name .. " shallow " .. deg)
				eq(v.case, "B", name)
				eq(v.splitBy, "shallow", name)
			else
				ok(deg > Cross.SHALLOW_MAX_DEG, name .. " steep " .. deg)
				eq(v.case, "X", name)
				eq(#v.shallowBlocked, 0, name .. ": terminal rule")
				local r = Slip.plan(W, 1, function() return {} end)
				ok(#connsFromTo(r.conns, 12, 33) > 0, name .. ": the far turn kept")
			end
		end
	end
end)

test("ramp terminals: tangent 80-89 deg passes the tangents, chord over 60 deg: crossing rule, both turns kept", function()
	for _, mirror in ipairs({ false, true }) do
		for _, a in ipairs({ 80, 85, 89 }) do
			for _, far in ipairs({ a, 90 }) do
				-- off-ramp end leaving eastbound's kerb side, and an on-ramp end joining it from that side
				for _, leaving in ipairs({ true, false }) do
					local name = string.format("%s %s tangent %d chord %d", mirror and "LHT" or "RHT",
						leaving and "ramp out" or "ramp in", a, far)
					local spec = leaving and { id = 33, leaving = true, tan = -a, far = -far }
						or { id = 34, leaving = false, tan = -(180 - a), far = -(180 - far) }
					local W = F.rampNode({ mirror = mirror, ramps = { spec } })
					local r, v = slipConns(W, 1)
					eq(v.case, "X", name .. " " .. tostring(v.reason))
					eq(v.slipReason, "terminal", name)
					ok(Rules.line("APPLY", Slip.logFields(r)):find(" case=X via=terminal side=", 1, true), name .. " via logged")
					eq(#v.shallowBlocked, 0, name .. ": nothing blocked " .. table.concat(v.rampDeg or {}, ","))
					local deg = tonumber(table.concat(v.rampDeg or {}, ","):match(":(%d+)$"))
					ok(deg ~= nil and deg > Cross.SHALLOW_MAX_DEG, name .. " chord " .. tostring(deg))
					if leaving then
						ok(#connsFromTo(r.conns, 11, 33) > 0, name .. ": eastbound turns into it")
						ok(#connsFromTo(r.conns, 12, 33) > 0, name .. ": westbound keeps its left turn")
					else
						ok(#connsFromTo(r.conns, 34, 12) > 0, name .. ": joins eastbound")
						ok(#connsFromTo(r.conns, 34, 11) > 0, name .. ": keeps its left turn onto westbound")
					end
				end
			end
		end
	end
end)

test("ramp terminals: the same ramp curving to 60 deg or less stays a slip node; town one-way streets stay too", function()
	for _, mirror in ipairs({ false, true }) do
		for _, a in ipairs({ 80, 89 }) do
			for _, leaving in ipairs({ true, false }) do
				local name = string.format("%s %s tangent %d", mirror and "LHT" or "RHT", leaving and "ramp out" or "ramp in", a)
				local spec = leaving and { id = 33, leaving = true, tan = -a, far = -30 }
					or { id = 34, leaving = false, tan = -(180 - a), far = -150 }
				local r, v = slipConns(F.rampNode({ mirror = mirror, ramps = { spec } }), 1)
				eq(v.case, "B", name .. " " .. tostring(v.reason) .. " " .. tostring(v.slipReason))
				eq(v.shape, leaving and "diverge" or "merge", name)
				checkInvariants(v, r.conns, name)
				if leaving then
					eq(#connsFromTo(r.conns, 12, 33), 0, name .. ": no turn across into the ramp")
				else
					eq(#connsFromTo(r.conns, 34, 11), 0, name .. ": no turn across the road")
				end
				-- a town one-way street (sidewalks) meeting the road square is no ramp: still a slip node
				spec.far, spec.tpl = leaving and -a or -(180 - a), F.TPL.one_way_small
				local rs, vs = slipConns(F.rampNode({ mirror = mirror, ramps = { spec } }), 1)
				eq(vs.case, "B", name .. " one-way street " .. tostring(vs.slipReason))
				checkInvariants(vs, rs.conns, name .. " one-way street")
			end
		end
	end
end)

test("review step 7: a world memo keeps no 'no_side' view, so a side remembered later is used", function()
	-- a game world (sl_write W.makeWorld) carries world.memo and an atMemo per segment table
	local function memoWorld(w)
		w.memo = {}
		for _, s in pairs(w.segs) do s.atMemo = {} end
		return w
	end
	for _, mirror in ipairs({ false, true }) do
		local want = mirror and "left" or "right"
		Slip.resetSide()
		local lone = memoWorld(line(TPL.one3, TPL.one2, { mirror = mirror }))
		eq(Slip.classify(lone, 1).reason, "no_side", "nothing remembered yet")
		F.merge(lone, build({ [61] = { 0, 500 }, [62] = { 60, 500 } }, { [71] = { 61, 62, TPL.two2 } }, mirror))
		Slip.classify(lone, 61)
		local v = Slip.classify(lone, 1)
		eq(v.kind, "slip", "the no_side view was not kept")
		eq(v.side, want)
		eq(v.sideFrom, "remembered")
		eq(Slip.classify(lone, 1), v, "a view with a side is kept")
		-- planning twice from the kept view gives the same connections (nothing writes into it)
		local r1 = Slip.plan(lone, 1, function() return {} end)
		local r2 = Slip.plan(lone, 1, function() return {} end)
		eq(Rules.connsText(r1.conns), Rules.connsText(r2.conns))
		checkInvariants(r2.view, r2.conns, "memo " .. want)
	end
	Slip.resetSide()
end)

test("case A: three one-way roads all leaving (or all arriving) are skipped (one_way_dir), never an error", function()
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	for _, out in ipairs({ true, false }) do
		local segs = {}
		for i, far in ipairs({ 2, 3, 4 }) do
			segs[40 + i] = out and { 1, far, F.TPL.highway_ramp2 } or { far, 1, F.TPL.highway_ramp2 }
		end
		local w = build(P, segs)
		local ok1, v = pcall(Slip.classify, w, 1)
		ok(ok1, tostring(v))
		eq(v.kind, "skip", out and "all out" or "all in")
		eq(v.reason, "one_way_dir")
		local ok2, r = pcall(Slip.plan, w, 1, function() return {} end)
		ok(ok2, tostring(r))
		eq(r.status, "skip")
	end
end)
