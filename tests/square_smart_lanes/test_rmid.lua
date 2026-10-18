-- square_smart_lanes: the mid-node lane changes sl_rmid (sl_rules M.variantConns "sl_rmid", M.midBothConns, planRing;
-- PLAN.md "Mid-node lane changes (sl_rmid)"). No lane change at an arm junction (outer lane exit-only, inner lanes
-- straight, entries into their own lane); every lane change, inwards and outwards, at the ring's mid nodes. Rings
-- without mid nodes get sl_rspiral. Reachability of every entry -> exit pair without lane changes on segments.

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

local M2 = "o1>o1 o1>o2 o2>o1 o2>o2"
local M3 = "o1>o1 o1>o2 o2>o1 o2>o2 o2>o3 o3>o2 o3>o3"
local M4 = "o1>o1 o1>o2 o2>o1 o2>o2 o2>o3 o3>o2 o3>o3 o3>o4 o4>o3 o4>o4"
-- "R:armLanes:mids per stretch" (4 arms) -> { junction roles, mid node roles }. X = min(E, floor(R / 2), mids) exit-only lanes.
local WANT = {
	-- the bench ring (bench_rb2tm): no lane change at the arm
	["2:1:1"] = { "o1>x1 o2>o2 e1>o1", M2 },
	["2:2:1"] = { "o1>x1 o1>x2 o2>o2 e1>o1 e2>o2", M2 },
	["3:1:1"] = { "o1>x1 o2>o2 o3>o3 e1>o1", M3 },
	["3:3:1"] = { "o1>x1 o1>x2 o1>x3 o2>o2 o3>o3 e1>o1 e2>o2 e3>o3", M3 },
	-- the 3-lane bench ring (bench_rb3m: 3 + 3 arms, 1 mid node per stretch): o1 exits into all three, o2 and o3 circulate
	["3:3:2"] = { "o1>x1 o1>x2 o1>x3 o2>o2 o3>o3 e1>o1 e2>o2 e3>o3", M3 },
	["4:2:1"] = { "o1>x1 o1>x2 o2>o2 o3>o3 o4>o4 e1>o1 e2>o2", M4 },
	["4:3:2"] = { "o1>x1 o2>x2 o2>x3 o3>o3 o4>o4 e1>o1 e2>o2 e3>o3", M4 },
	-- the 4-lane bench ring (bench_rb4lm: 3 + 3 arms, 2 mid nodes per stretch): two exit lanes, o3 and o4 circulate
	["4:3:3"] = { "o1>x1 o2>x2 o2>x3 o3>o3 o4>o4 e1>o1 e2>o2 e3>o3", M4 },
}

local function planMid(W, seeds, conns)
	return planOf(W, "sl_rmid", seeds, conns)
end

test("sl_rmid: no lane change at the junctions, neighbouring lanes both ways at the mid nodes; 2/3/4 lanes, 1-3 mid nodes, both sides; reachable", function()
	local n = 0
	for key, want in pairs(WANT) do
		local R, A, m = key:match("^(%d):(%d):(%d)$")
		R, A, m = tonumber(R), tonumber(A), tonumber(m)
		for _, o in ipairs(SIDES) do
			local msg = string.format("R=%d arms=%d mids=%d %s%s", R, A, m, o.dir, o.mirror and " mirror" or "")
			local W = ringWorld(R, A, 4, o, m)
			local p, ring = planMid(W)
			eq({ p.variant, p.layout, p.split, p.mids, p.midsPerStretch, #p.nodes }, { "sl_rmid", "sl_rmid", nil, 4 * m, m, 4 + 4 * m }, msg)
			for _, r in ipairs(p.nodes) do
				eq(r.status, "apply", msg)
				eq(roles(r.view, r.conns), sorted(r.mid and want[2] or want[1]), msg .. " node " .. r.node)
				if not r.mid then
					-- no ring lane into another ring lane at a junction
					for w in roles(r.view, r.conns):gmatch("%S+") do
						local a, b = w:match("^o(%d)>o(%d)$")
						ok(a == nil or a == b, msg .. " lane change at a junction: " .. w)
					end
				end
			end
			assertReach(W, ring, p, msg)
			n = n + 1
		end
	end
	eq(n, 8 * 4)
end)

test("sl_rmid: every entry lane reaches every exit, and a car entering in the outer lane gets past the next arm (lane by lane, 2/3/4 lanes)", function()
	-- per entry lane: the exits it reaches with node connections only (the planner picks its entry lane by exit, so
	-- reaching every exit from some lane is the rule's test; here each lane on its own, as a car that took it)
	for _, c in ipairs({ { 2, 1, 1 }, { 3, 3, 1 }, { 3, 3, 2 }, { 4, 3, 1 }, { 4, 3, 2 }, { 4, 3, 3 } }) do
		local R, A, m = c[1], c[2], c[3]
		local W = ringWorld(R, A, 4, { dir = "ccw" }, m)
		local p, ring = planMid(W)
		local conns = {}
		for _, r in ipairs(p.nodes) do conns[r.node] = r.conns end
		local msg = string.format("R=%d arms=%d mids=%d", R, A, m)
		-- walk lane states from one entry lane: (seg, lane at the node it arrives at)
		for _, r in ipairs(p.nodes) do
			local v = r.view
			if not r.mid and #v.e > 0 then
				for j, l in ipairs(v.e) do
					local exits, seen, stack, steps = {}, {}, { { node = v.node, seg = v.arm, lane = l } }, 0
					while #stack > 0 and steps < 10000 do
						steps = steps + 1
						local st = table.remove(stack)
						local k = st.node .. "|" .. st.seg .. "|" .. st.lane
						if not seen[k] then
							seen[k] = true
							for _, cc in ipairs(conns[st.node] or {}) do
								if cc.withRoad and cc.segment0 == st.seg and cc.lane0 == st.lane then
									if ring.segSet[cc.segment1] then
										local s1 = W.seg(cc.segment1)
										local _, b = Ring.travel(s1)
										stack[#stack + 1] = { node = b, seg = cc.segment1, lane = Ring.otherEndIndex(s1, cc.lane1) }
									else
										exits[cc.segment1] = true
									end
								end
							end
						end
					end
					ok(steps < 10000, msg .. " walk capped")
					local nEx = 0
					for _ in pairs(exits) do nEx = nEx + 1 end
					eq(nEx, 4, msg .. " entry lane " .. j .. " of node " .. v.node .. " reaches every exit (the U-turn included)")
				end
			end
		end
	end
end)

test("sl_rmid: the bench ring's counts (junction 3, mid node 4) and how they differ from sl_rsplit", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local p = planMid(W)
	local s = planOf(W, "sl_rsplit")
	for i, r in ipairs(p.nodes) do
		eq(r.after, r.mid and 4 or 3)
		eq(s.nodes[i].after, r.mid and 3 or 4)
		if not r.mid then ok(not roles(r.view, r.conns):find("o2>o1", 1, true), "no inner -> outer at the junction") end
		if r.mid then ok(roles(r.view, r.conns):find("o2>o1", 1, true), "inner -> outer at the mid node") end
	end
end)

test("sl_rmid: reachable on few-exit rings: 2 and 3 arms, an entry-only and an exit-only ramp, a single exit", function()
	local big = { tpl = "large" }
	local cases = {
		{ "2 arms", F.ring({ ringTpl = "one_way_small", arms = { { tpl = "small" }, { tpl = "small" } }, extraNodes = 1 }) },
		{ "3 arms", ringWorld(2, 1, 3, { dir = "ccw" }, 1) },
		{ "3 arms cw", ringWorld(3, 2, 3, { dir = "cw" }, 1) },
		-- an exit-only ramp (lanes leave the ring) and an entry-only ramp (flip: lanes enter the ring)
		{ "ramps", F.ring({ ringTpl = "one_way_small", arms = { big, { tpl = "highway_ramp2" }, big, { tpl = "highway_ramp2", flip = true } },
			extraNodes = 1 }) },
		-- one exit only: an exit-only ramp plus three entry-only ramps (every trip leaves at the one exit)
		{ "one exit", F.ring({ ringTpl = "one_way_small", arms = { { tpl = "highway_ramp2" }, { tpl = "highway_ramp2", flip = true },
			{ tpl = "highway_ramp2", flip = true }, { tpl = "highway_ramp2", flip = true } }, extraNodes = 1 }) },
	}
	for _, c in ipairs(cases) do
		local W = c[2]
		local p, ring = planMid(W)
		eq(p.layout, "sl_rmid", c[1])
		ok((p.mids or 0) >= 2, c[1])
		for _, r in ipairs(p.nodes) do
			if not r.mid and #r.view.x == 0 then
				-- a junction without exits: the outer lane goes straight on (nothing would leave it otherwise)
				ok(roles(r.view, r.conns):find("o1>o1", 1, true), c[1] .. " entry-only junction keeps o1 straight")
			end
		end
		assertReach(W, ring, p, c[1])
	end
end)

test("sl_rmid without mid nodes: sl_rspiral, why in res.split; other rules leave the mid nodes alone", function()
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 0)
	local p = planMid(W)
	local s = planOf(W, "sl_rspiral")
	eq({ p.variant, p.layout, p.split, p.mids, #p.nodes }, { "sl_rmid", "sl_rspiral", "no_mid_nodes", nil, 4 })
	for i, r in ipairs(p.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(s.nodes[i].conns)) end
	eq(planMid(ringWorld(1, 1, 4, { dir = "ccw" }, 1)).split, "one_lane_ring")
	-- written once: every node "same" on the next plan
	local Wm = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local whole = planMid(Wm)
	local cur = {}
	for _, r in ipairs(whole.nodes) do cur[r.node] = r.conns end
	for _, r in ipairs(planMid(Wm, nil, cur).nodes) do eq(r.status, "same") end
	eq(#planOf(Wm, "sl_rspiral").nodes, 4)
end)

---------------------------------------------------------------------------
-- The script: an sl_rmid zone on a ring with mid nodes

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

test("script: an sl_rmid zone writes 4 junctions and 4 mid nodes (layout=sl_rmid, mid=yes after=4, RSPLIT line)", function()
	local G, ring = runZone("sl_rmid")
	eq(#G.kinds("ERROR"), 0)
	local a = G.kinds("APPLY")
	eq(#a, 8)
	local mids = 0
	for _, l in ipairs(a) do
		ok(l:find(" layout=sl_rmid", 1, true) and l:find(" zid=s4g1n$"), l)
		if l:find(" mid=yes", 1, true) then
			mids = mids + 1
			ok(l:find(" before=2 after=4 ", 1, true), l)
		else
			ok(l:find(" after=3 ", 1, true), l)
		end
	end
	eq(mids, 4)
	local rs = G.kinds("RSPLIT")
	eq(#rs, 1)
	ok(rs[1]:find("mids=4 per_stretch=1 nodes=[%d,]+ zid=s4g1n$"), rs[1])
	local want = Rules.planRing(G.world, ring, all(G.world), "sl_rmid", function() return {} end)
	for _, r in ipairs(want.nodes) do
		eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), "node " .. r.node)
	end
	ok(table.concat(G.kinds("VERIFY"), "\n"):find("VERIFY ring=%d+ same=8 nodes=8"))
end)

test("sl_rmid: moves per stretch: a car entering in o1 reaches the circulating lanes, one in the innermost lane an exit lane, within one stretch", function()
	-- per ring lane at the end of a junction: the ring lanes it can be in on arriving at the next junction (one lane per
	-- mid node); X exit-only lanes, so o1 needs X moves to circulate and o_R needs R - X to leave there
	for _, c in ipairs({ { 2, 1, 1, 1 }, { 3, 3, 1, 1 }, { 4, 3, 2, 2 }, { 4, 3, 1, 1 } }) do
		local R, A, m, X = c[1], c[2], c[3], c[4]
		local W = ringWorld(R, A, 4, { dir = "ccw" }, m)
		local p = planMid(W)
		local nExitOnly = 0
		for _, r in ipairs(p.nodes) do
			if not r.mid then
				nExitOnly = 0
				for w in roles(r.view, r.conns):gmatch("%S+") do
					local i = w:match("^o(%d)>x%d$")
					if i and tonumber(i) > nExitOnly then nExitOnly = tonumber(i) end
				end
				break
			end
		end
		eq(nExitOnly, X, string.format("R=%d mids=%d: exit lanes", R, m))
		ok(X <= m, "o1 can reach the circulating lanes in one stretch")
		local innerOk = (R - X) <= m
		print(string.format("R=%d arms %d+%d mids/stretch=%d: X=%d exit lanes; o1 -> o%d in one stretch: yes; o%d -> o%d in one stretch: %s",
			R, A, A, m, X, X + 1, R, X, innerOk and "yes" or "no (it leaves one arm later)"))
	end
end)

test("the default on 2-lane rings with one-lane exits is sl_rmid: exact arm and mid rules; reachable on 3-6 arms, splitters, ramps; partial mid nodes fall back to sl_rspiral", function()
	-- the bench ring: arm o1 -> x1 only, o2 -> o2 only, e1 -> o1 only; mid node both straight + both ways
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local p, ring = planMid(W)
	local d = Rules.planRing(W, ring, all(W), "two_lane", function() return {} end)
	eq({ d.default, d.layout }, { true, "sl_rmid" })
	for i, r in ipairs(d.nodes) do
		eq(Rules.connsText(r.conns), Rules.connsText(p.nodes[i].conns))
		eq(roles(r.view, r.conns), sorted(r.mid and "o1>o1 o1>o2 o2>o1 o2>o2" or "o1>x1 o2>o2 e1>o1"))
	end
	local function check(Wx, msg, want)
		local rx = assert(Ring.findRing(Wx, 1), msg)
		local px = Rules.planRing(Wx, rx, all(Wx), "two_lane", function() return {} end)
		eq(px.layout, want, msg)
		assertReach(Wx, rx, px, msg)
	end
	for nArms = 3, 6 do
		for _, o in ipairs(SIDES) do check(ringWorld(2, 1, nArms, o, 1), nArms .. " arms " .. o.dir, "sl_rmid") end
	end
	-- splitter rings (one-lane legs)
	F.TPL.leg1 = "BS FV FS"
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "small", splitter = true, legTpl = "leg1" } end
	check(F.ring({ ringTpl = "one_way_small", arms = arms, extraNodes = 1 }), "splitter", "sl_rmid")
	-- an exit-only and an entry-only one-lane ramp among one-lane town arms
	F.TPL.ramp1 = "B- FV F-"
	check(F.ring({ ringTpl = "one_way_small", arms = { { tpl = "small" }, { tpl = "ramp1" }, { tpl = "small" }, { tpl = "ramp1", flip = true } },
		extraNodes = 1 }), "ramps", "sl_rmid")
	-- a stretch without its mid node (a split refused there): the whole ring sl_rspiral, still reachable
	local arm = { tpl = "small" }
	check(F.ring({ ringTpl = "one_way_small", arms = { arm, false, arm, arm } }), "partial", "sl_rspiral")
end)
