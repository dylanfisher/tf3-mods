-- square_smart_lanes: slip-lane junctions (sl_slip.lua): node classification, the lane rule and
-- its invariants (no crossing, every lane connected / fed, tram kept), both traffic sides, the
-- Channelized Junction's geometry (hand-made fixture mirroring square_roundabouts_channel.lua).

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

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

--- Invariants straight on the pairs for every count combination 1..4.
test("rule invariants for all lane counts: no crossing, every lane connected and fed", function()
	local function check(shape, a, b, c, pr)
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
	-- the centre (T of two-way roads) and the arm ends are no slip nodes
	eq(Slip.classify(W, 1).kind, "none")
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
					-- the far side (crossing oncoming traffic) is not a slip lane
					local Wf = tee({ main = main, branch = branch, join = join, side = "left", angle = 35, mirror = mirror })
					local vf = Slip.classify(Wf, 1)
					eq(vf.kind, "skip", name .. " far side")
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

test("not slip nodes: crossroads, T of two-way roads, plain road, Y fork, 5 roads, bus lane", function()
	-- crossroads of two-way roads: no one-way segment
	local X = build({ [1] = { 0, 0 }, [2] = { 50, 0 }, [3] = { 0, 50 }, [4] = { -50, 0 }, [5] = { 0, -50 } },
		{ [1] = { 1, 2, TPL.two2 }, [2] = { 1, 3, TPL.two2 }, [3] = { 1, 4, TPL.two2 }, [4] = { 1, 5, TPL.two2 } })
	eq(Slip.classify(X, 1).kind, "none")
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
	-- bus lane on the main road
	local bus = tee({ main = TPL.two2_bus, branch = TPL.one2, side = "right" })
	eq(Slip.classify(bus, 1).reason, "bus_lane")
	-- a one-way branch on a two-way road that turns too sharply (a side street, not a slip lane)
	local sharp = tee({ main = TPL.two2, branch = TPL.one2, side = "right", angle = 95 })
	eq(Slip.classify(sharp, 1).kind, "skip")
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
	eq(Slip.plan(W, 1, function() return {} end).status, "none")
end)
