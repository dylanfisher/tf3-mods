-- square_smart_lanes: bounded road walks (sl_walk.lua): through plain nodes, lane counts per travel
-- direction, every stop reason, and the caps (a long chain and a loop of plain nodes terminate).

local Walk = ug_require "square_smart_lanes::/smart_lanes/sl_walk.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local TPL = { one1 = "B- FV F-", one2 = "BS FV FV FS", one3 = "BS FV FV FV FS", two2 = F.TPL.medium, two3 = F.TPL.large }

local function lanesText(w)
	local out = {}
	for _, st in ipairs(w.steps) do out[#out + 1] = tostring(st.lanes) end
	return table.concat(out, ",")
end

--- A straight chain of `n` segments of `len` m along +x: nodes 1..n+1, segment k from node k to k+1.
-- tpls: one template for all, or a list per segment.
local function chain(n, len, tpls, mirror)
	local nodes, segs = {}, {}
	for k = 1, n + 1 do nodes[k] = { (k - 1) * len, 0 } end
	for k = 1, n do
		segs[k] = { k, k + 1, type(tpls) == "table" and tpls[k] or tpls }
	end
	return F.build(nodes, segs, mirror)
end

test("walk: downstream and upstream through plain nodes, lane counts per travel direction", function()
	for _, mirror in ipairs({ false, true }) do
		local W = chain(4, 50, { TPL.one3, TPL.one2, TPL.one2, TPL.one3 }, mirror)
		local w = Walk.follow(W, 1, 1, { dir = "out" })
		eq(lanesText(w), "3,2,2,3")
		eq(w.stop, "dead_end")
		eq(w.node, 5)
		eq(w.dist, 200)
		eq(Walk.minLanes(w), 2)
		eq(Walk.firstBelow(w, 3), 50, "first node with fewer lanes")
		eq(Walk.firstBelow(w, 2), nil)
		eq(Walk.junctionDist(w), nil)
		eq(Walk.lastSeg(w), 4)
		-- against the one-way direction, nothing travels: stop before the first segment
		local back = Walk.follow(W, 5, 4, { dir = "out" })
		eq(back.stop, "no_lanes")
		eq(#back.steps, 0)
		-- upstream from node 5: the traffic arriving there
		local upw = Walk.follow(W, 5, 4, { dir = "in" })
		eq(lanesText(upw), "3,2,2,3")
		eq(upw.node, 1)
		-- a two-way road: both directions have lanes
		local T = chain(3, 40, { TPL.two3, TPL.two2, TPL.two3 }, mirror)
		eq(lanesText(Walk.follow(T, 1, 1, { dir = "out" })), "3,2,3")
		eq(lanesText(Walk.follow(T, 4, 3, { dir = "in" })), "3,2,3")
		eq(lanesText(Walk.follow(T, 4, 3, { dir = "out" })), "3,2,3")
	end
end)

test("walk: stops at a junction (3 road segments), not at a tram-only track", function()
	local W = chain(3, 50, TPL.one2)
	-- side road at node 3
	W.nodes[9] = { id = 9, x = 100, y = 50, segs = { 99 } }
	W.segs[99] = { id = 99, node0 = 3, node1 = 9, p0 = { x = 100, y = 0 }, p1 = { x = 100, y = 50 },
		lanes = F.lanes(F.TPL.small) }
	table.insert(W.nodes[3].segs, 99)
	local w = Walk.follow(W, 1, 1, { dir = "out" })
	eq(w.stop, "junction")
	eq(w.node, 3)
	eq(w.roads, 3)
	eq(Walk.junctionDist(w), 100)
	-- a tram-only track instead: still a plain node
	W.segs[99].lanes = F.lanes(F.TPL.tram_only)
	local w2 = Walk.follow(W, 1, 1, { dir = "out" })
	eq(w2.stop, "dead_end")
	eq(w2.node, 4)
end)

test("walk caps: a long chain stops at the distance or the node cap", function()
	local W = chain(40, 50, TPL.one2) -- 2 km
	local w = Walk.follow(W, 1, 1, { dir = "out" })
	eq(w.stop, "max_dist")
	eq(w.dist, Walk.MAX_DIST)
	eq(#w.steps, 8)
	local short = chain(40, 5, TPL.one2) -- 5 m segments
	local ws = Walk.follow(short, 1, 1, { dir = "out" })
	eq(ws.stop, "max_nodes")
	eq(#ws.steps, Walk.MAX_NODES)
	-- caps passed in never exceed the hard caps
	local wh = Walk.follow(short, 1, 1, { dir = "out", maxNodes = 1e9, maxDist = 1e9 })
	eq(#wh.steps, 40, "the chain's end comes first")
	eq(wh.stop, "dead_end")
	local long = chain(100, 5, TPL.one2)
	local wl = Walk.follow(long, 1, 1, { dir = "out", maxNodes = 1e9, maxDist = 1e9 })
	eq(wl.stop, "max_nodes")
	eq(#wl.steps, Walk.HARD_NODES)
end)

test("walk caps: a loop of plain nodes terminates (one-way ring and two-way circle)", function()
	for _, tpl in ipairs({ TPL.one2, TPL.two2 }) do
		local nodes, segs = {}, {}
		local n = 10
		for k = 1, n do
			local a = 2 * math.pi * (k - 1) / n
			nodes[k] = { 30 * math.cos(a), 30 * math.sin(a) }
		end
		for k = 1, n do segs[k] = { k, (k % n) + 1, tpl } end
		local W = F.build(nodes, segs)
		local w = Walk.follow(W, 1, 1, { dir = "out", maxNodes = 1e9, maxDist = 1e9 })
		eq(w.stop, "loop", tpl)
		eq(#w.steps, n, tpl)
		eq(w.node, 1)
		-- upstream round the same ring
		local u = Walk.follow(W, 1, n, { dir = "in", maxNodes = 1e9, maxDist = 1e9 })
		eq(u.stop, "loop", tpl)
		eq(#u.steps, n, tpl)
	end
	-- a self-loop segment at a node
	local W = chain(1, 50, TPL.two2)
	W.segs[7] = { id = 7, node0 = 2, node1 = 2, p0 = { x = 50, y = 0 }, p1 = { x = 50, y = 0 },
		t0 = { x = 0, y = 40 }, t1 = { x = 0, y = -40 }, lanes = F.lanes(TPL.two2) }
	table.insert(W.nodes[2].segs, 7)
	table.insert(W.nodes[2].segs, 7)
	local w = Walk.follow(W, 1, 1, { dir = "out", maxNodes = 1e9, maxDist = 1e9 })
	ok(#w.steps <= 3, "self-loop stops: " .. tostring(w.stop))
end)

test("walk: a missing node or segment ends the walk, never indexes nil", function()
	local W = chain(3, 50, TPL.one2)
	-- segment 2 bulldozed but still listed at its nodes
	W.segs[2] = nil
	local w = Walk.follow(W, 1, 1, { dir = "out" })
	eq(w.stop, "no_seg")
	eq(#w.steps, 1)
	-- the start segment missing
	eq(Walk.follow(W, 1, 77, { dir = "out" }).stop, "no_seg")
	eq(Walk.follow(W, 1, nil, { dir = "out" }).stop, "no_seg")
	-- a segment not attached to the start node
	eq(Walk.follow(W, 1, 3, { dir = "out" }).stop, "no_seg")
	-- the far node missing
	local W2 = chain(2, 50, TPL.one2)
	W2.nodes[2] = nil
	local w2 = Walk.follow(W2, 1, 1, { dir = "out" })
	eq(w2.stop, "no_node")
	eq(w2.node, 2)
	eq(Walk.roadSegs(W2, 2), nil)
end)

--- Redraws segment id of world W from its other end (same road: node0/node1, ends and tangents
-- swapped, laneConfigs reversed with forward flipped), as the game may store any segment.
local function flip(W, id)
	local s = W.segs[id]
	s.node0, s.node1 = s.node1, s.node0
	s.p0, s.p1 = s.p1, s.p0
	s.t0, s.t1 = { x = -s.t1.x, y = -s.t1.y }, { x = -s.t0.x, y = -s.t0.y }
	local l = {}
	for i = #s.lanes, 1, -1 do
		local c = s.lanes[i]
		l[#l + 1] = { forward = not c.forward, road = c.road, car = c.car, tram = c.tram, walk = c.walk }
	end
	s.lanes = l
end

test("walk: segments drawn either way round give the same lane counts and stops", function()
	for _, mirror in ipairs({ false, true }) do
		for _, tpls in ipairs({ { TPL.one3, TPL.one2, TPL.one2, TPL.one3 }, { TPL.two3, TPL.two2, TPL.two2, TPL.two3 } }) do
			local W = chain(4, 50, tpls, mirror)
			flip(W, 2)
			flip(W, 4)
			local w = Walk.follow(W, 1, 1, { dir = "out" })
			eq(lanesText(w), "3,2,2,3")
			eq(w.stop, "dead_end")
			eq(w.node, 5)
			local u = Walk.follow(W, 5, 4, { dir = "in" })
			eq(lanesText(u), "3,2,2,3")
			eq(u.node, 1)
			-- the two-way road's other direction from node 5
			if tpls[1] == TPL.two3 then eq(lanesText(Walk.follow(W, 5, 4, { dir = "out" })), "3,2,2,3") end
			-- a one-way segment flipped against travel: the walk stops before it
			if tpls[1] == TPL.one3 then
				local X = chain(3, 50, TPL.one2, mirror)
				for _, l in ipairs(X.segs[2].lanes) do l.forward = not l.forward end
				local x = Walk.follow(X, 1, 1, { dir = "out" })
				eq(x.stop, "no_lanes")
				eq(x.node, 2)
				eq(#x.steps, 1)
			end
		end
	end
end)

test("walk: two segments between the same two nodes (a 2-node loop) stop as a loop", function()
	local W = chain(1, 50, TPL.two2)
	W.segs[8] = { id = 8, node0 = 2, node1 = 1, p0 = { x = 50, y = 0 }, p1 = { x = 0, y = 0 },
		t0 = { x = -50, y = 30 }, t1 = { x = -50, y = -30 }, lanes = F.lanes(TPL.two2) }
	table.insert(W.nodes[1].segs, 8)
	table.insert(W.nodes[2].segs, 8)
	local w = Walk.follow(W, 1, 1, { dir = "out", maxNodes = 1e9, maxDist = 1e9 })
	eq(w.stop, "loop")
	eq(#w.steps, 2)
	eq(w.node, 1)
	eq(w.roads, nil)
end)
