-- square_smart_lanes: the mid-node spiral sl_rsplit (sl_rules M.variantConns "sl_rsplit", M.splitMidConns,
-- M.splitMids, planRing; PLAN.md "Mid-node spiral (sl_rsplit)"). Rings with a plain node between their junctions
-- (square_roundabouts' dev override ringMid, the Stress Test bench's bench_rb2tm) get the spiral with the inward
-- lane change at that node; rings without one get sl_rspiral. The script part: zone lines (layout=, mid=yes, RSPLIT).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

F.TPL.one_way3 = "BS FV FV FV FS"
local RING_TPL = { [1] = "one_way_town1", [2] = "one_way_small", [3] = "one_way3", [4] = "one_way_medium" }
local ARM_TPL = { [1] = "small", [2] = "medium", [3] = "large" }
local SIDES = { { dir = "ccw" }, { dir = "cw" }, { dir = "ccw", mirror = true }, { dir = "cw", mirror = true } }

local function all(world)
	local s = {}
	for id in pairs(world.nodes) do s[id] = true end
	return s
end

--- A ring of R lanes, nArms arms of armLanes lanes each way and `extra` plain ring nodes between neighbouring arms.
local function ringWorld(R, armLanes, nArms, o, extra)
	local arms = {}
	for k = 1, nArms do arms[k] = { tpl = ARM_TPL[armLanes] } end
	return F.ring({ ringTpl = RING_TPL[R], arms = arms, dir = o.dir, mirror = o.mirror, extraNodes = extra })
end

local function planOf(W, variant, seeds, conns)
	local ring = assert(Ring.findRing(W, 1))
	return Rules.planRing(W, ring, seeds or all(W), variant, function(n) return conns and conns[n] or {} end), ring
end

--- Road connections in lane roles, sorted ("o2>o1", "o1>x1", "e1>o1"; o1 = outer ring lane, kerb first).
local function roles(v, conns)
	local pos = {}
	for i, l in ipairs(v.o_in) do pos[v.ringIn .. ":" .. l] = "o" .. i end
	for i, l in ipairs(v.e) do pos[v.arm .. ":" .. l] = "e" .. i end
	local outPos = {}
	for i, l in ipairs(v.o_out) do outPos[v.ringOut .. ":" .. l] = "o" .. i end
	for i, l in ipairs(v.x) do outPos[v.arm .. ":" .. l] = "x" .. i end
	local out = {}
	for _, c in ipairs(conns) do
		if c.withRoad then out[#out + 1] = (pos[c.segment0 .. ":" .. c.lane0] or "?") .. ">" .. (outPos[c.segment1 .. ":" .. c.lane1] or "?") end
	end
	table.sort(out)
	return table.concat(out, " ")
end

local function sorted(s)
	local t = {}
	for w in s:gmatch("%S+") do t[#t + 1] = w end
	table.sort(t)
	return table.concat(t, " ")
end

--- Every entry reaches every exit with node connections only (no lane change on a segment), no dead ring lane.
local function assertReach(W, ring, p, msg)
	local m = {}
	for _, r in ipairs(p.nodes) do m[r.node] = r.conns end
	-- ring nodes the plan leaves alone keep the game's connections (a plain node: straight on)
	for _, n in ipairs(ring.nodes) do
		if m[n] == nil then m[n] = Rules.engineDefault(Ring.nodeView(W, ring, n)) end
	end
	local reach, dead = Rules.reachability(W, ring, m, false)
	local ins, outs = {}, {}
	for _, r in ipairs(p.nodes) do
		local v = r.view
		if #v.e > 0 then ins[#ins + 1] = v.arm end
		if #v.x > 0 then outs[#outs + 1] = v.arm end
	end
	ok(#ins > 0 and #outs > 0, msg)
	for _, a in ipairs(ins) do
		for _, b in ipairs(outs) do ok(reach[a] and reach[a][b], msg .. " entry " .. a .. " -> exit " .. b) end
	end
	eq(next(dead), nil, msg .. " dead ring lanes")
end

-- "R:armLanes" (4 arms) -> { junction roles, mid node roles }
local WANT = {
	-- the bench ring (bench_rb2tm): outer lane exit-only, inner lane shifts out or stays, the entry joins the outer
	-- lane only; at the mid node the outer lane may move in
	["2:1"] = { "o1>x1 o2>o1 o2>o2 e1>o1", "o1>o1 o1>o2 o2>o2" },
	["2:2"] = { "o1>x1 o1>x2 o2>o1 o2>o2 e1>o1 e2>o2", "o1>o1 o1>o2 o2>o2" },
	["3:1"] = { "o1>x1 o2>o1 o3>o2 o3>o3 e1>o1", "o1>o1 o1>o2 o2>o2 o2>o3 o3>o3" },
	["4:2"] = { "o1>x1 o1>x2 o2>o1 o3>o2 o4>o3 e1>o1 e2>o2", "o1>o1 o1>o2 o2>o2 o2>o3 o3>o3 o3>o4 o4>o4" },
}

test("sl_rsplit: junction and mid node connections, both directions and traffic sides; reachable without lane changes", function()
	local n = 0
	for key, want in pairs(WANT) do
		local R, A = key:match("^(%d):(%d)$")
		R, A = tonumber(R), tonumber(A)
		for _, o in ipairs(SIDES) do
			local msg = string.format("R=%d arms=%d %s%s", R, A, o.dir, o.mirror and " mirror" or "")
			local W = ringWorld(R, A, 4, o, 1)
			local p, ring = planOf(W, "sl_rsplit")
			eq(#ring.nodes, 8, msg)
			eq(p.variant, "sl_rsplit", msg)
			eq(p.layout, "sl_rsplit", msg)
			eq(p.split, nil, msg)
			eq(p.mids, 4, msg)
			eq(#p.nodes, 8, msg)
			local mids, junctions = 0, 0
			for _, r in ipairs(p.nodes) do
				eq(r.status, "apply", msg)
				if r.mid then
					mids = mids + 1
					eq(r.view.kind, "plain", msg)
					eq(roles(r.view, r.conns), sorted(want[2]), msg .. " mid " .. r.node)
				else
					junctions = junctions + 1
					eq(r.view.kind, "arm", msg)
					eq(roles(r.view, r.conns), sorted(want[1]), msg .. " junction " .. r.node)
				end
			end
			eq(mids, 4, msg)
			eq(junctions, 4, msg)
			-- mids come after the junctions, each between two of them in ring order
			for i = 1, #ring.nodes do
				local a, b = ring.nodes[i], ring.nodes[i % #ring.nodes + 1]
				local va, vb = Ring.nodeView(W, ring, a), Ring.nodeView(W, ring, b)
				ok(va.kind ~= vb.kind, msg .. " junction and plain alternate")
			end
			assertReach(W, ring, p, msg)
			n = n + 1
		end
	end
	eq(n, 4 * 4)
end)

test("sl_rsplit vs sl_rspiral on the bench ring: the entry no longer joins the inner lane at the junction", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local split = planOf(W, "sl_rsplit")
	local spiral = planOf(W, "sl_rspiral")
	-- sl_rspiral on the same ring: junctions only (the mid nodes stay the game's), the entry into both lanes
	eq(#spiral.nodes, 4)
	for _, r in ipairs(spiral.nodes) do eq(roles(r.view, r.conns), sorted("o1>x1 o2>o1 o2>o2 e1>o1 e1>o2")) end
	for _, r in ipairs(split.nodes) do
		if not r.mid then
			ok(not roles(r.view, r.conns):find("e1>o2", 1, true), "no entry into the inner lane")
			eq(r.after, 4)
		else
			eq(r.after, 3)
		end
	end
end)

test("sl_rsplit without a plain node on every stretch: sl_rspiral at the junctions, why in res.split", function()
	-- no plain node at all
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 0)
	local p = planOf(W, "sl_rsplit")
	local s = planOf(W, "sl_rspiral")
	eq(p.variant, "sl_rsplit")
	eq(p.layout, "sl_rspiral")
	eq(p.split, "no_mid_nodes")
	eq(p.mids, nil)
	eq(#p.nodes, 4)
	for i, r in ipairs(p.nodes) do
		ok(not r.mid)
		eq(Rules.connsText(r.conns), Rules.connsText(s.nodes[i].conns))
	end
	-- a plain node on one stretch only (arms at 0, 180 and 270 degrees, a plain node at 90)
	local arm = { tpl = "small" }
	local W2 = F.ring({ ringTpl = "one_way_small", arms = { arm, false, arm, arm } })
	local p2 = planOf(W2, "sl_rsplit")
	eq(p2.split, "no_mid_nodes")
	eq(p2.layout, "sl_rspiral")
	-- a 1-lane ring: nothing to change lanes to (matched lanes, as every variant)
	local W1 = ringWorld(1, 1, 4, { dir = "ccw" }, 1)
	local p1 = planOf(W1, "sl_rsplit")
	eq(p1.split, "one_lane_ring")
	for _, r in ipairs(p1.nodes) do ok(not r.mid) end
	-- Rules.splitMids directly: a ring without junctions
	local W0 = F.ring({ ringTpl = "one_way_small", arms = { false, false, false, false } })
	local ring0 = assert(Ring.findRing(W0, 1))
	local views = {}
	for _, n in ipairs(ring0.nodes) do views[n] = Ring.nodeView(W0, ring0, n) end
	local set, why = Rules.splitMids(W0, ring0, views)
	eq(set, nil)
	eq(why, "no_junction")
end)

test("sl_rsplit: every plain node of a stretch is a mid node (one inward lane change each)", function()
	-- two arms (0 and 180 degrees) with three plain nodes on each stretch (45, 90, 135): all six
	local arm = { tpl = "small" }
	local W = F.ring({ ringTpl = "one_way_small", arms = { arm, false, false, false, arm, false, false, false } })
	local p, ring = planOf(W, "sl_rsplit")
	eq(p.layout, "sl_rsplit")
	eq(p.mids, 6)
	eq(p.midsPerStretch, 3)
	local mids = {}
	for _, r in ipairs(p.nodes) do
		if r.mid then
			local nd = W.node(r.node)
			local deg = math.deg(math.atan(nd.y, nd.x)) % 360
			mids[#mids + 1] = math.floor(deg + 0.5)
		end
	end
	table.sort(mids)
	eq(mids, { 45, 90, 135, 225, 270, 315 })
	eq(#ring.nodes, 8)
	-- 2 junctions: D = min(2, 2) = 2, every exit reachable without lane changes
	assertReach(W, ring, p, "2 arms, 3 plain nodes per stretch")
end)

test("sl_rsplit: seeds, same, tram; the default rules and other variants never touch the plain ring nodes", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local whole = planOf(W, "sl_rsplit")
	-- only the seeds are planned; the rest is untouched (the zone seeds every ring node, the tool its pick)
	local ring = assert(Ring.findRing(W, 1))
	local p = Rules.planRing(W, ring, { [ring.nodes[1]] = true, [ring.nodes[2]] = true }, "sl_rsplit", function() return {} end)
	local planned = 0
	for _, r in ipairs(p.nodes) do
		if r.status ~= "untouched" then planned = planned + 1 end
	end
	eq(planned, 2)
	-- the written state again: every node "same"
	local cur = {}
	for _, r in ipairs(whole.nodes) do cur[r.node] = r.conns end
	local again = planOf(W, "sl_rsplit", nil, cur)
	for _, r in ipairs(again.nodes) do eq(r.status, "same", tostring(r.node)) end
	-- a tram connection at a mid node is kept
	local mid = nil
	for _, r in ipairs(whole.nodes) do if r.mid then mid = r end end
	local v = mid.view
	local tram = Rules.conn(v.ringIn, v.o_in[2], v.ringOut, v.o_out[2], false, true)
	local withTram = planOf(W, "sl_rsplit", nil, { [mid.node] = { tram } })
	for _, r in ipairs(withTram.nodes) do
		if r.node == mid.node then
			local t = 0
			for _, c in ipairs(r.conns) do if c.withTram then t = t + 1 end end
			eq(t, 1)
		end
	end
	-- every other rule plans the junctions only
	-- (two_lane / turbo: the default spiral on this ring since 2026-10-14, the test below)
	for _, variant in ipairs({ "matched", "engine", "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread" }) do
		local q = planOf(W, variant)
		eq(#q.nodes, 4, variant)
		for _, r in ipairs(q.nodes) do ok(not r.mid and r.view.kind ~= "plain", variant) end
		eq(q.mids, nil, variant)
	end
end)

---------------------------------------------------------------------------
-- The script: an sl_rsplit zone on a ring with mid nodes (the fake game's ring node 22768 is junction 1)

local BASE = 22767

local function midFixture()
	local W = F.shift(ringWorld(2, 1, 4, { dir = "ccw" }, 1), BASE, 0, 0)
	return { world = function() return W end, conns = {} }
end

local function ringBuildAll(G)
	local ring = assert(Ring.findRing(G.world, BASE + 1))
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(ring.nodes) do sp.addedNodes[#sp.addedNodes + 1] = { entity = n } end
	for _, sid in ipairs(ring.segs) do
		local s = G.world.segs[sid]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = sid, comp = { node0 = s.node0, node1 = s.node1 } }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }, ring
end

local function runZone(ab)
	local G = makeGame(nil, midFixture())
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", Zones.EVENT_ID, Zones.EV_ZONES,
		{ op = "set", run = "rs", zones = { { x = 0, y = 0, r = 60, ab = ab, id = "s4g1n" } } })
	local build, ring = ringBuildAll(G)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build)
	G.frames(60)
	return G, ring
end

test("script: an sl_rsplit zone writes the junctions and the mid nodes (layout=sl_rsplit, mid=yes, RSPLIT line)", function()
	local G, ring = runZone("sl_rsplit")
	eq(#G.kinds("ERROR"), 0)
	local a = G.kinds("APPLY")
	eq(#a, 8)
	local mids = 0
	for _, l in ipairs(a) do
		ok(l:find(" layout=sl_rsplit", 1, true), l)
		ok(l:find(" zid=s4g1n$"), l)
		if l:find(" mid=yes", 1, true) then
			mids = mids + 1
			ok(l:find(" exits=0 entries=0 ", 1, true), l)
			ok(l:find(" before=2 after=3 ", 1, true), l)
		end
	end
	eq(mids, 4)
	local rs = G.kinds("RSPLIT")
	eq(#rs, 1)
	ok(rs[1]:find("^%[SQRL%] RSPLIT ring=%d+ node=%d+ len=%d+ mids=4 per_stretch=1 nodes=[%d,]+ zid=s4g1n$"), rs[1])
	-- the proposal landed: every ring node holds the plan's connections
	local want = Rules.planRing(G.world, ring, all(G.world), "sl_rsplit", function() return {} end)
	for _, r in ipairs(want.nodes) do
		eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), "node " .. r.node)
	end
	local w = G.kinds("WRITE")
	ok(#w >= 1 and w[#w]:find("success=true", 1, true), tostring(w[#w]))
	local vfy = table.concat(G.kinds("VERIFY"), "\n")
	ok(vfy:find("VERIFY ring=%d+ same=8 nodes=8"), vfy)
	ok(G.kinds("SUMMARY")[1]:find(" zone_ring=1", 1, true), G.kinds("SUMMARY")[1])
end)

test("script: the other twins on the same ring leave the mid nodes as the game made them", function()
	for _, ab in ipairs({ "sl_rspiral", "game", "sl_rmatch" }) do
		local G = runZone(ab)
		eq(#G.kinds("ERROR"), 0, ab)
		eq(#G.kinds("RSPLIT"), 0, ab)
		for _, l in ipairs(G.kinds("APPLY")) do ok(not l:find("mid=yes", 1, true), l) end
		-- the mid nodes keep their straight-on connections (2 each)
		local ring = assert(Ring.findRing(G.world, BASE + 1))
		for _, n in ipairs(ring.nodes) do
			local v = Ring.nodeView(G.world, ring, n)
			if v.kind == "plain" then eq(#G.configs[n].laneConnections, 2, ab .. " node " .. n) end
		end
	end
end)

test("sl_rsplit on the wider bench rings: 3 lanes with 1 mid node, 4 lanes with 2 per stretch; reachable, inward moves at every mid node", function()
	for _, c in ipairs({ { 3, 3, 1 }, { 4, 3, 2 }, { 4, 3, 3 } }) do
		local R, A, m = c[1], c[2], c[3]
		local W = ringWorld(R, A, 4, { dir = "ccw" }, m)
		local p, ring = planOf(W, "sl_rsplit")
		local msg = string.format("R=%d arms=%d mids=%d", R, A, m)
		eq({ p.layout, p.mids, p.midsPerStretch }, { "sl_rsplit", 4 * m, m }, msg)
		for _, r in ipairs(p.nodes) do
			local t = roles(r.view, r.conns)
			if r.mid then
				-- inwards only: no o(i+1) -> o(i) at a mid node
				for w in t:gmatch("%S+") do
					local a, b = w:match("^o(%d)>o(%d)$")
					ok(a == nil or tonumber(b) >= tonumber(a), msg .. " " .. w)
				end
			end
		end
		assertReach(W, ring, p, msg)
	end
end)

---------------------------------------------------------------------------
-- The default rule (2026-10-14, user: "make split spiral lane change at mid nodes default for that situation"):
-- a 2-lane ring whose every exit has one lane gets sl_rsplit (sl_rspiral without mid nodes); others as before

test("default: a 2-lane ring with one-lane exits gets sl_rmid with its mid nodes (two_lane and the tool's turbo), whole ring", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local split = planOf(W, "sl_rmid")
	for _, variant in ipairs({ "two_lane", "turbo" }) do
		local p = planOf(W, variant)
		eq({ p.default, p.defaultWhy, p.layout, p.variant, p.turboReason, p.mids }, { true, "one_lane_exits", "sl_rmid", nil, "narrow_exit", 4 }, variant)
		eq(#p.nodes, 8, variant)
		for i, r in ipairs(p.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(split.nodes[i].conns), variant) end
	end
	-- one junction alone (the tool's node Apply, a seed the automatic pass does not make whole): the mid nodes stay
	local ring = assert(Ring.findRing(W, 1))
	local one = Rules.planRing(W, ring, { [1] = true }, "turbo", function() return {} end)
	for _, r in ipairs(one.nodes) do
		if r.mid then eq(r.status, "untouched") end
	end
	-- no mid nodes: sl_rspiral
	local W0 = ringWorld(2, 1, 4, { dir = "ccw" }, 0)
	local p0 = planOf(W0, "two_lane")
	eq({ p0.default, p0.layout, p0.split }, { true, "sl_rspiral", "no_mid_nodes" })
end)

test("default: no spiral where it does not apply (2-lane ring with 2-lane exits: matched since 2026-10-15; mixed exits; 3- and 4-lane rings; 1-lane ring)", function()
	local function check(W, msg, why)
		local p = planOf(W, "two_lane")
		eq(p.defaultWhy, why, msg)
		local m = planOf(W, "turbo")
		eq(m.defaultWhy, why, msg)
		eq({ p.split, p.splitWanted, p.mids }, { nil, nil, nil }, msg)
		for _, r in ipairs(p.nodes) do ok(not r.mid, msg) end
	end
	-- 2-lane exits on a 2-lane ring: the matched default (until 2026-10-15 turbo), never mid nodes
	check(ringWorld(2, 2, 4, { dir = "ccw" }, 1), "2-lane exits", "two_lane_exits")
	check(ringWorld(3, 1, 4, { dir = "ccw" }, 1), "3-lane ring")
	check(ringWorld(4, 1, 4, { dir = "ccw" }, 1), "4-lane ring")
	check(ringWorld(1, 1, 4, { dir = "ccw" }, 1), "1-lane ring")
	-- mixed: one 2-lane arm among 1-lane arms
	check(F.ring({ ringTpl = "one_way_small", arms = { { tpl = "medium" }, { tpl = "small" }, { tpl = "small" }, { tpl = "small" } }, extraNodes = 1 }), "mixed")
	-- exit-only and entry-only 2-lane ramps with 3-lane arms (the Roundabout Interchange): every exit has 2+ lanes, so
	-- the matched default (until 2026-10-15 turbo)
	check(F.ring({ ringTpl = "one_way_small", arms = { { tpl = "large" }, { tpl = "highway_ramp2" }, { tpl = "large" },
		{ tpl = "highway_ramp2", flip = true } }, extraNodes = 1 }), "ramps", "two_lane_exits")
	-- a 1-lane exit ramp beside 3-lane arms (mixed exits): matched lanes as always (narrow_exit), no default
	check(F.ring({ ringTpl = "one_way_small", arms = { { tpl = "large" }, { tpl = "highway_small" }, { tpl = "large" },
		{ tpl = "highway_ramp2", flip = true } }, extraNodes = 1 }), "1-lane ramp")
end)

test("default: Reset (engine) gives mid nodes the game's straight-on lanes back; ringForm knows the spiral forms", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local p, ring = planOf(W, "two_lane")
	local cur = {}
	for _, r in ipairs(p.nodes) do cur[r.node] = r.conns end
	local e = planOf(W, "engine", nil, cur)
	local mids = 0
	for _, r in ipairs(e.nodes) do
		if r.mid then
			mids = mids + 1
			eq({ r.status, r.before, r.after }, { "apply", 4, 2 })
			eq(Rules.roadText(r.conns), Rules.roadText(Rules.engineDefault(r.view)))
		end
	end
	eq(mids, 4)
	-- straight-on mid nodes: nothing to reset there
	local e2 = planOf(W, "engine")
	for _, r in ipairs(e2.nodes) do ok(not r.mid) end
	-- the automatic pass's hand-edit guard accepts the spiral junctions as Smart Lanes' own
	for _, r in ipairs(p.nodes) do
		if not r.mid then eq(Rules.ringForm(r.view, r.conns, { A = 4 }), "mid") end
	end
	for _, r in ipairs(planOf(W, "sl_rsplit").nodes) do
		if not r.mid then eq(Rules.ringForm(r.view, r.conns, { A = 4 }), "split") end
	end
	local sp = planOf(W, "sl_rspiral")
	for _, r in ipairs(sp.nodes) do eq(Rules.ringForm(r.view, r.conns, { A = 4 }), "spiral") end
	local auto = Rules.autoSeeds(W, ring, { [ring.nodes[1]] = true }, function(n) return cur[n] end)
	eq(#auto.handEdit, 0)
	eq(auto.whole, true)
end)

test("script: the automatic pass (and an sl zone) writes the default with its mid nodes (layout=sl_rmid default=one_lane_exits)", function()
	for _, ab in ipairs({ "none", "sl" }) do
		local G = makeGame(nil, midFixture())
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		if ab ~= "none" then
			G.gs.handleEvent({}, G.state, "", Zones.EVENT_ID, Zones.EV_ZONES,
				{ op = "set", run = "rs", zones = { { x = 0, y = 0, r = 60, ab = ab, id = "s4g1a" } } })
		end
		local build, ring = ringBuildAll(G)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build)
		G.frames(60)
		eq(#G.kinds("ERROR"), 0, ab)
		local a = G.kinds("APPLY")
		eq(#a, 8, ab)
		local mids = 0
		for _, l in ipairs(a) do
			ok(l:find(" layout=sl_rmid default=one_lane_exits", 1, true), l)
			if l:find(" mid=yes", 1, true) then
				mids = mids + 1
				ok(l:find(" before=2 after=4 ", 1, true), l)
			else
				ok(l:find(" after=3 ", 1, true), l)
			end
		end
		eq(mids, 4, ab)
		local rs = G.kinds("RSPLIT")
		eq(#rs, 1, ab)
		ok(rs[1]:find("mids=4 per_stretch=1 nodes=", 1, true), rs[1])
		ok(table.concat(G.kinds("VERIFY"), "\n"):find("VERIFY ring=%d+ same=8 nodes=8"), ab)
		-- the audit: the entry merging with the shifted stream is forced (no avoidable finding)
		eq(#G.kinds("AUDIT"), 0, ab)
		ok(G.kinds("AUDIT_SUMMARY")[1]:find(" flagged=0 ", 1, true), G.kinds("AUDIT_SUMMARY")[1])
		-- a later build at one arm: nothing changes (the spiral is Smart Lanes' own form, not a hand edit)
		local before = {}
		for _, n in ipairs(ring.nodes) do before[n] = Rules.connsText(G.configs[n].laneConnections) end
		local sp = { addedNodes = { { entity = ring.nodes[1] } }, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
		local node = G.world.nodes[ring.nodes[1]]
		for _, sid in ipairs(node.segs) do
			if not ring.segSet[sid] then
				local s = G.world.segs[sid]
				sp.addedSegments[1] = { entity = sid, comp = { node0 = s.node0, node1 = s.node1 } }
			end
		end
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
		G.frames(60)
		for _, n in ipairs(ring.nodes) do eq(Rules.connsText(G.configs[n].laneConnections), before[n], ab .. " node " .. n) end
		for _, l in ipairs(G.kinds("SKIP")) do ok(not l:find("hand_edit", 1, true), l) end
	end
end)

test("script: a 2-lane ring with 2-lane exits gets matched lanes (layout=matched default=two_lane_exits), no split and no mid node written", function()
	for _, extra in ipairs({ 0, 1 }) do
		for _, ab in ipairs({ "none", "sl" }) do
			local W = F.shift(ringWorld(2, 2, 4, { dir = "ccw" }, extra), BASE, 0, 0)
			local G = makeGame(nil, { world = function() return W end, conns = {} })
			G.gs.update({}, G.state, 0.1)
			G.frames(1)
			if ab ~= "none" then
				G.gs.handleEvent({}, G.state, "", Zones.EVENT_ID, Zones.EV_ZONES,
					{ op = "set", run = "rs", zones = { { x = 0, y = 0, r = 60, ab = ab, id = "s5g1a" } } })
			end
			local build, ring = ringBuildAll(G)
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build)
			G.frames(60)
			local msg = ab .. " extra=" .. extra
			eq(#G.kinds("ERROR"), 0, msg)
			local a = G.kinds("APPLY")
			eq(#a, 4, msg)
			for _, l in ipairs(a) do
				ok(l:find(" turbo=false fresh=true ", 1, true) and l:find(" layout=matched default=two_lane_exits", 1, true), l)
				ok(not l:find(" mid=yes", 1, true), l)
			end
			eq({ #G.kinds("RSPLIT"), #G.kinds("SPLIT") }, { 0, 0 }, msg)
			for _, n in ipairs(ring.nodes) do
				local v = Ring.nodeView(G.world, ring, n)
				if v.kind == "arm" then
					eq(Rules.roadText(G.configs[n].laneConnections), Rules.roadText(Rules.twoLaneConns(v, { turbo = false })), msg .. " node " .. n)
				end
			end
		end
	end
end)

test("sl_midview: one curve per road connection of a mid node, from the lane it leaves to the lane it enters, lane offsets used", function()
	local MidView = ug_require "square_smart_lanes::/smart_lanes/sl_midview.lua"
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local p = planOf(W, "sl_rsplit")
	local mid
	for _, r in ipairs(p.nodes) do if r.mid then mid = r break end end
	local cv = MidView.curves(W, mid.node, mid.conns)
	eq(#cv, 3)
	local changes = 0
	for _, c in ipairs(cv) do
		if c.change then changes = changes + 1 end
		-- the ends lie LEAD m before / after the node, one lane apart at most
		local nd = W.node(mid.node)
		local da = math.sqrt((c.a.x - nd.x) ^ 2 + (c.a.y - nd.y) ^ 2)
		ok(da > MidView.LEAD - 0.1 and da < MidView.LEAD + MidView.LANE_W, "a near the node")
		local L = math.sqrt((c.b.x - c.a.x) ^ 2 + (c.b.y - c.a.y) ^ 2)
		ok(L > 2 * MidView.LEAD - 0.5 and L < 2 * MidView.LEAD + MidView.LANE_W + 0.5, "length " .. L)
		-- tangents along travel (the ring runs counterclockwise: a -> b turns left a little)
		ok(c.ta.x * (c.b.x - c.a.x) + c.ta.y * (c.b.y - c.a.y) > 0, "ta along travel")
	end
	eq(changes, 1)
	-- lateral from offsets (laneConfig offset, sl_ring lanesFromConfigs), sign by order; without: LANE_W apart
	eq(MidView.lateral({ lanes = { { offset = -6 }, { offset = -2 }, { offset = 2 }, { offset = 6 } } }, 1), -2)
	eq(MidView.lateral({ lanes = { { offset = 6 }, { offset = 2 }, { offset = -2 }, { offset = -6 } } }, 1), -2)
	eq(MidView.lateral({ lanes = { {}, {}, {}, {} } }, 0), -1.5 * MidView.LANE_W)
	-- a connection naming a segment not at the node: left out; a missing node: none
	eq(#MidView.curves(W, mid.node, { Rules.conn(999999, 1, 999998, 1, true, false) }), 0)
	eq(#MidView.curves(W, -5, mid.conns), 0)
end)

test("splitter rings: mid nodes needed only from an entry to the next exit (not between one arm's exit and entry legs)", function()
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "small", splitter = true } end
	local W = F.ring({ ringTpl = "one_way_small", arms = arms, extraNodes = 1 })
	local ring = assert(Ring.findRing(W, 1))
	eq(#ring.nodes, 12)
	for _, variant in ipairs({ "sl_rsplit", "sl_rmid" }) do
		local p = planOf(W, variant)
		eq({ p.layout, p.mids, p.midsPerStretch }, { variant, 4, 1 }, variant)
		assertReach(W, ring, p, variant .. " splitter")
	end
	-- the default: one_way_leg legs have 2 lanes, so a 2 + 2 splitter ring is no spiral ring: the matched default
	-- (until 2026-10-15 turbo)
	local p = planOf(W, "two_lane")
	eq({ p.default, p.layout, p.mids }, { true, "matched", nil })
end)

test("a ring whose nodes between the arms have a small corner (R&I's menu setting: 4 degrees) is still a ring with mid nodes", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local ring0 = assert(Ring.findRing(W, 1))
	local h = math.rad(2)
	local function rot(t, a)
		local c, s = math.cos(a), math.sin(a)
		return { x = t.x * c - t.y * s, y = t.x * s + t.y * c }
	end
	for _, n in ipairs(ring0.nodes) do
		if Ring.nodeView(W, ring0, n).kind == "plain" then
			for _, sid in ipairs(W.nodes[n].segs) do
				local s = W.segs[sid]
				if s.node1 == n then s.t1 = rot(s.t1, -h) else s.t0 = rot(s.t0, h) end
			end
		end
	end
	local p, ring = planOf(W, "two_lane")
	eq(#ring.nodes, 8)
	eq({ p.default, p.layout, p.mids }, { true, "sl_rmid", 4 })
	assertReach(W, ring, p, "kinked")
end)
