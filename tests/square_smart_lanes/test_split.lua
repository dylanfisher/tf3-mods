-- square_smart_lanes: Smart Lanes adds a ring's mid nodes itself (sl_split.lua, sl_write W.sendSplit, the automatic
-- pass and the tool; PLAN.md "Smart Lanes adds the mid nodes"). A 2-lane ring with one-lane exits placed from the
-- construction menu loses its plain ring nodes (docs/findings/roads.md "Menu placements join short ring pieces"):
-- Smart Lanes splits each entry-to-exit stretch's edge into its two exact halves, then writes the mid-node spiral.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Split = ug_require "square_smart_lanes::/smart_lanes/sl_split.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local function ringWorld(opt)
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = opt and opt.armTpl or "small" } end
	return F.ring({ ringTpl = "one_way_small", arms = arms, radius = opt and opt.radius or 30, extraNodes = opt and opt.extra or 0,
		dir = opt and opt.dir or "ccw", flipRing = opt and opt.flipRing })
end

local function views(W, ring)
	local v = {}
	for _, n in ipairs(ring.nodes) do v[n] = Ring.nodeView(W, ring, n) end
	return v
end

test("halves: the two halves are the exact sub-curves of the edge (same points at every parameter), 3D", function()
	local p0, t0, p1, t1 = { x = 0, y = 0, z = 1 }, { x = 30, y = 5, z = 2 }, { x = 20, y = 25, z = 3 }, { x = -10, y = 35, z = -1 }
	local h = Split.halves(p0, t0, p1, t1)
	for i = 0, 10 do
		local s = i / 10
		local a = Split.hermite(p0, t0, p1, t1, s / 2)
		local b = Split.hermite(h.first.p0, h.first.t0, h.first.p1, h.first.t1, s)
		local c = Split.hermite(p0, t0, p1, t1, 0.5 + s / 2)
		local d = Split.hermite(h.second.p0, h.second.t0, h.second.p1, h.second.t1, s)
		for _, k in ipairs({ "x", "y", "z" }) do
			near(a[k], b[k], 1e-9, "first half at " .. s)
			near(c[k], d[k], 1e-9, "second half at " .. s)
		end
	end
	-- continuous at the middle: the same point and tangent on both sides
	for _, k in ipairs({ "x", "y", "z" }) do
		near(h.first.p1[k], h.second.p0[k], 1e-12)
		near(h.first.t1[k], h.second.t0[k], 1e-12)
	end
	near(Split.length(h.first) + Split.length(h.second), Split.length({ p0 = p0, t0 = t0, p1 = p1, t1 = t1 }), 0.05)
end)

test("edges: every entry-to-exit stretch of one edge; none with mid nodes; short and splitter cases", function()
	local W = ringWorld()
	local ring = assert(Ring.findRing(W, 1))
	local list = assert(Split.edges(W, ring, views(W, ring)))
	eq(#list, 4)
	for i, it in ipairs(list) do
		eq(it.seg, ring.segs[i])
		eq(it.from, ring.nodes[i])
		eq(it.to, ring.nodes[i % 4 + 1])
	end
	local Wm = ringWorld({ extra = 1 })
	local rm = assert(Ring.findRing(Wm, 1))
	eq({ Split.edges(Wm, rm, views(Wm, rm)) }, { nil, "no_stretch" })
	-- a tiny ring: halves under MIN_PIECE
	local Ws = ringWorld({ radius = 6 })
	local rs = assert(Ring.findRing(Ws, 1))
	eq({ Split.edges(Ws, rs, views(Ws, rs)) }, { nil, "short" })
	-- splitter arms: only the stretches from an entry leg to the next exit leg
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "small", splitter = true } end
	local Wx = F.ring({ ringTpl = "one_way_small", arms = arms })
	local rx = assert(Ring.findRing(Wx, 1))
	local lx = assert(Split.edges(Wx, rx, views(Wx, rx)))
	eq(#lx, 4)
	for _, it in ipairs(lx) do
		local vf, vt = Ring.nodeView(Wx, rx, it.from), Ring.nodeView(Wx, rx, it.to)
		ok(#vf.e > 0 and #vt.x > 0, "entry leg to exit leg")
	end
	-- the cap
	local counts = {}
	ok(Split.allowed(counts, 7))
	counts[7] = Split.MAX_PER_RING
	ok(not Split.allowed(counts, 7))
end)

---------------------------------------------------------------------------
-- The automatic pass (the fake game applies street proposals: temp ids become entities, configs re-pointed)

local BASE = 22767

local function fixture(opt)
	local W = F.shift(ringWorld(opt), BASE, 0, 0)
	return { world = function() return W end, conns = {} }
end

local function buildAll(G)
	local ring = assert(Ring.findRing(G.world, BASE + 1))
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(ring.nodes) do sp.addedNodes[#sp.addedNodes + 1] = { entity = n } end
	for _, sid in ipairs(ring.segs) do
		local s = G.world.segs[sid]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = sid, comp = { node0 = s.node0, node1 = s.node1 } }
	end
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
end

local function game(opt)
	local G = makeGame(nil, fixture(opt))
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G
end

test("automatic pass: a 2-lane ring with one-lane exits and no mid nodes is split (SPLIT, WRITE kind=split), then written as the mid-node spiral", function()
	local G = game()
	local ring0 = assert(Ring.findRing(G.world, BASE + 1))
	local before = {}
	for i, sid in ipairs(ring0.segs) do
		local s = G.world.segs[sid]
		before[i] = { p0 = s.p0, t0 = s.t0, p1 = s.p1, t1 = s.t1 }
	end
	buildAll(G)
	G.frames(80)
	eq(#G.kinds("ERROR"), 0)
	local sp = G.kinds("SPLIT")
	eq(#sp, 1)
	ok(sp[1]:find("^%[SQRL%] SPLIT ring=%d+ node=%d+ len=%d+ edges=[%d,]+ nodes_added=4$"), sp[1])
	ok(table.concat(G.kinds("WRITE"), "\n"):find("WRITE kind=split ring=%d+ success=true"), "split answered")
	-- the street proposal: 4 edges out, 8 halves and 4 nodes in, configs for the 4 old and 4 new nodes, cleanup off
	local splitCmd
	for _, c in ipairs(G.sent) do if c.proposal.streetProposal.edgesToAdd ~= nil then splitCmd = c end end
	ok(splitCmd ~= nil)
	local p = splitCmd.proposal.streetProposal
	eq({ #p.edgesToRemove, #p.edgesToAdd, #p.nodesToAdd, #p.nodeConfigsToAdd, #p.nodeConfigsToRemove }, { 4, 8, 4, 8, 4 })
	eq(splitCmd.ctx.cleanupStreetGraph, false)
	for _, sg in ipairs(p.edgesToAdd) do ok(sg.entity < 0 and sg.entity >= -8, "edge temp id " .. sg.entity) end
	for _, ne in ipairs(p.nodesToAdd) do ok(ne.entity < -8, "node temp id " .. ne.entity) end
	-- the world now: 8 ring edges, the same curve (each half's ends on the old curve)
	local ring = assert(Ring.findRing(G.world, BASE + 1))
	eq(#ring.nodes, 8)
	eq(#ring.segs, 8)
	local function onOld(pt)
		for _, b in ipairs(before) do
			for i = 0, 40 do
				local q = Split.hermite({ x = b.p0.x, y = b.p0.y }, { x = b.t0.x, y = b.t0.y }, { x = b.p1.x, y = b.p1.y }, { x = b.t1.x, y = b.t1.y }, i / 40)
				if math.abs(q.x - pt.x) < 1e-6 and math.abs(q.y - pt.y) < 1e-6 then return true end
			end
		end
		return false
	end
	for _, sid in ipairs(ring.segs) do
		local s = G.world.segs[sid]
		ok(onOld(s.p0) and onOld(s.p1), "half ends on the old curve")
	end
	-- then the ring with its new nodes: the mid-node spiral, verified
	local rs = G.kinds("RSPLIT")
	ok(#rs >= 1 and rs[#rs]:find(" mids=4 per_stretch=1 ", 1, true), tostring(rs[#rs]))
	local a = G.kinds("APPLY")
	local mids, junctions = 0, 0
	for _, l in ipairs(a) do
		ok(l:find(" layout=sl_rmid default=one_lane_exits", 1, true), l)
		if l:find(" mid=yes", 1, true) then
			mids = mids + 1
			ok(l:find(" before=2 after=4 ", 1, true), l)
		else
			junctions = junctions + 1
			ok(l:find(" after=3 ", 1, true), l)
		end
	end
	eq({ junctions, mids }, { 4, 4 })
	ok(table.concat(G.kinds("VERIFY"), "\n"):find("VERIFY ring=%d+ same=8 nodes=8"), "verified")
	local want = Rules.planRing(G.world, ring, (function() local t = {} for _, n in ipairs(ring.nodes) do t[n] = true end return t end)(),
		"two_lane", function() return {} end)
	for _, r in ipairs(want.nodes) do eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), "node " .. r.node) end
	-- no second split of that ring
	eq(#G.kinds("SPLIT"), 1)
end)

test("split proposal: the old end nodes' configs re-pointed in order (same count, segment ids swapped), the new nodes straight on", function()
	local G = game()
	local ring0 = assert(Ring.findRing(G.world, BASE + 1))
	-- the engine's lanes before (as the game makes them)
	local cfg0 = {}
	for _, n in ipairs(ring0.nodes) do cfg0[n] = #G.configs[n].laneConnections end
	G.defer = true
	buildAll(G)
	G.frames(15)
	local splitCmd
	for _, c in ipairs(G.sent) do if c.proposal.streetProposal.edgesToAdd ~= nil then splitCmd = c end end
	ok(splitCmd ~= nil)
	local p = splitCmd.proposal.streetProposal
	local removed = {}
	for _, e in ipairs(p.edgesToRemove) do removed[e] = true end
	for _, e in ipairs(p.nodeConfigsToAdd) do
		local lcs = e.comp.laneConnections
		if e.entity > 0 then
			eq(#lcs, cfg0[e.entity], "node " .. e.entity .. ": same connections")
			for _, lc in ipairs(lcs) do ok(not removed[lc.segment0] and not removed[lc.segment1], "no removed edge named") end
		else
			-- 2 road lanes straight on, from the first half into the second
			eq(#lcs, 2, "new node " .. e.entity)
			for _, lc in ipairs(lcs) do ok(lc.segment0 < 0 and lc.segment1 < 0 and lc.segment0 ~= lc.segment1) end
		end
	end
	G.flush()
	G.frames(60)
	eq(#G.kinds("ERROR"), 0)
end)

test("refusals: an edge with an object (a stop), a tiny ring: SPLIT refused, the spiral without mid nodes written", function()
	local G = game()
	local ring0 = assert(Ring.findRing(G.world, BASE + 1))
	G.world.segs[ring0.segs[2]].objects = { { 1, 1 } }
	buildAll(G)
	G.frames(60)
	local sp = G.kinds("SPLIT")
	eq(#sp, 1)
	ok(sp[1]:find(" refused=edge_objects", 1, true), sp[1])
	ok(G.kinds("RSPLIT")[1]:find("mids=0 fallback=sl_rspiral reason=no_mid_nodes", 1, true))
	for _, l in ipairs(G.kinds("APPLY")) do ok(l:find(" layout=sl_rspiral default=one_lane_exits", 1, true), l) end
	eq(G.streetCmds, nil, "no street proposal")
	local Gs = game({ radius = 6 })
	buildAll(Gs)
	Gs.frames(60)
	ok(Gs.kinds("SPLIT")[1] and Gs.kinds("SPLIT")[1]:find(" refused=short", 1, true), tostring(Gs.kinds("SPLIT")[1]))
end)

test("refused split proposal: the ring is planned again without splitting (noSplit), at most MAX_PER_RING splits a session", function()
	local G = game()
	G.refuse = function(cmd) return cmd.proposal.streetProposal.edgesToAdd ~= nil end
	for _ = 1, 4 do
		buildAll(G)
		G.frames(80)
	end
	eq(#G.kinds("ERROR"), 0)
	local sent, capped = 0, 0
	for _, l in ipairs(G.kinds("SPLIT")) do
		if l:find(" edges=", 1, true) then sent = sent + 1 end
		if l:find(" refused=cap", 1, true) then capped = capped + 1 end
	end
	eq(sent, Split.MAX_PER_RING)
	ok(capped >= 1, "capped")
	ok(table.concat(G.kinds("WRITE"), "\n"):find("WRITE kind=split ring=%d+ success=false"))
	-- every pass after a refused split writes the spiral without mid nodes
	ok(#G.kinds("APPLY") >= 4)
end)

test("other rings are never split: 2-lane exits (turbo), a ring that has its mid nodes, Apply automatically's default only", function()
	local G = game({ armTpl = "medium" })
	buildAll(G)
	G.frames(60)
	eq(#G.kinds("SPLIT"), 0)
	local Gm = game({ extra = 1 })
	buildAll(Gm)
	Gm.frames(60)
	eq(#Gm.kinds("SPLIT"), 0)
	eq(Gm.streetCmds, nil)
end)
