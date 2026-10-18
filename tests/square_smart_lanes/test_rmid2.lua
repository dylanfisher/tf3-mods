-- square_smart_lanes: ring lane use (PLAN.md "Ring lane use (in progress)"): the zone modes sl_rmid2 (sl_rmid for wider
-- exits: the first circulating lane also leaves; Smart Lanes adds the missing mid nodes) and sl_rturbo_in (turbo with
-- the inner ring lanes fed by the innermost entry lane and leaving by a one-lane shift outwards at each arm). Exact
-- connections, reachability without lane changes on segments (both traffic sides), no two ring lanes into one lane,
-- and the script's split + write in an sl_rmid2 zone.

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

local function ringWorld(R, armLanes, nArms, o, extra)
	local arms = {}
	for k = 1, nArms do arms[k] = { tpl = ARM_TPL[armLanes] } end
	return F.ring({ ringTpl = RING_TPL[R], arms = arms, dir = o.dir, mirror = o.mirror, extraNodes = extra })
end

local function planOf(W, variant)
	local ring = assert(Ring.findRing(W, 1))
	return Rules.planRing(W, ring, all(W), variant, function() return {} end), ring
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

--- Every entry reaches every exit with node connections only, no dead ring lane.
local function assertReach(W, ring, p, msg)
	local m = {}
	for _, r in ipairs(p.nodes) do m[r.node] = r.conns end
	for _, n in ipairs(ring.nodes) do
		if m[n] == nil then m[n] = Rules.engineDefault(Ring.nodeView(W, ring, n)) end
	end
	local reach, dead = Rules.reachability(W, ring, m, false)
	local ins, outs = {}, {}
	for _, r in ipairs(p.nodes) do
		if #r.view.e > 0 then ins[#ins + 1] = r.view.arm end
		if #r.view.x > 0 then outs[#outs + 1] = r.view.arm end
	end
	ok(#ins > 0 and #outs > 0, msg)
	for _, a in ipairs(ins) do
		for _, b in ipairs(outs) do ok(reach[a] and reach[a][b], msg .. " entry " .. a .. " -> exit " .. b) end
	end
	eq(next(dead), nil, msg .. " dead ring lanes")
end

--- At a junction: every exit lane fed by exactly one ring lane, every ring-out lane by at most one ring-in lane (no two
-- ring lanes into one; an entry joining a ring stream is the roundabout's give-way).
local function assertNoMerge(r, msg)
	local intoX, intoO = {}, {}
	for w in roles(r.view, r.conns):gmatch("%S+") do
		local a, kind, b = w:match("^(o%d)>([xo])(%d)$")
		if a then
			local t = kind == "x" and intoX or intoO
			t[b] = (t[b] or 0) + 1
		end
	end
	for b, n in pairs(intoX) do eq(n, 1, msg .. " exit lane x" .. b .. " fed by one ring lane") end
	for i = 1, #r.view.x do ok(intoX[tostring(i)] ~= nil, msg .. " exit lane x" .. i .. " fed") end
	for b, n in pairs(intoO) do ok(n <= 1, msg .. " ring lane o" .. b .. " fed by " .. n .. " ring lanes") end
end

--- Per entry lane of each junction: how many exits it reaches with node connections only (a car keeps the lane it took).
local function exitsPerLane(W, ring, p)
	local conns = {}
	for _, r in ipairs(p.nodes) do conns[r.node] = r.conns end
	local res = {}
	for _, r in ipairs(p.nodes) do
		local v = r.view
		if not r.mid and #v.e > 0 then
			res[v.node] = {}
			for j, l in ipairs(v.e) do
				local exits, seen, stack, steps = {}, {}, { { node = v.node, seg = v.arm, lane = l } }, 0
				while #stack > 0 and steps < 10000 do
					steps = steps + 1
					local st = table.remove(stack)
					local k = st.node .. "|" .. st.seg .. "|" .. st.lane
					if not seen[k] then
						seen[k] = true
						for _, c in ipairs(conns[st.node] or Rules.engineDefault(Ring.nodeView(W, ring, st.node))) do
							if c.withRoad and c.segment0 == st.seg and c.lane0 == st.lane then
								if ring.segSet[c.segment1] then
									local s1 = W.seg(c.segment1)
									local _, b = Ring.travel(s1)
									stack[#stack + 1] = { node = b, seg = c.segment1, lane = Ring.otherEndIndex(s1, c.lane1) }
								else
									exits[c.segment1] = true
								end
							end
						end
					end
				end
				assert(steps < 10000, "walk capped")
				local n = 0
				for _ in pairs(exits) do n = n + 1 end
				res[v.node][j] = n
			end
		end
	end
	return res
end

---------------------------------------------------------------------------
-- sl_rmid2

local M2 = "o1>o1 o1>o2 o2>o1 o2>o2"
local M3 = "o1>o1 o1>o2 o2>o1 o2>o2 o2>o3 o3>o2 o3>o3"
local M4 = "o1>o1 o1>o2 o2>o1 o2>o2 o2>o3 o3>o2 o3>o3 o3>o4 o4>o3 o4>o4"
-- "R:armLanes:mids per stretch" (4 arms) -> { junction roles, mid node roles }
local WANT2 = {
	-- the 2-lane ring with 2-lane exits: the turbo junction, lane changes both ways at the mid nodes
	["2:2:1"] = { "o1>x1 o2>o2 o2>x2 e1>o1 e2>o2", M2 },
	["2:2:2"] = { "o1>x1 o2>o2 o2>x2 e1>o1 e2>o2", M2 },
	["2:3:1"] = { "o1>x1 o2>o2 o2>x2 o2>x3 e1>o1 e2>o2 e3>o2", M2 },
	-- one-lane exits: exactly sl_rmid
	["2:1:1"] = { "o1>x1 o2>o2 e1>o1", M2 },
	["3:2:1"] = { "o1>x1 o2>o2 o2>x2 o3>o3 e1>o1 e2>o2", M3 },
	["3:3:1"] = { "o1>x1 o2>o2 o2>x2 o2>x3 o3>o3 e1>o1 e2>o2 e3>o3", M3 },
	["4:3:2"] = { "o1>x1 o2>x2 o3>o3 o3>x3 o4>o4 e1>o1 e2>o2 e3>o3", M4 },
}

test("sl_rmid2: exact junction and mid-node rules (2/3/4 lanes, 1-3-lane arms, 1-2 mid nodes, both sides); reachable without lane changes; no two ring lanes into one", function()
	local n = 0
	for key, want in pairs(WANT2) do
		local R, A, m = key:match("^(%d):(%d):(%d)$")
		R, A, m = tonumber(R), tonumber(A), tonumber(m)
		for _, o in ipairs(SIDES) do
			local msg = string.format("rmid2 R=%d arms=%d mids=%d %s%s", R, A, m, o.dir, o.mirror and " mirror" or "")
			local W = ringWorld(R, A, 4, o, m)
			local p, ring = planOf(W, "sl_rmid2")
			eq({ p.variant, p.layout, p.split, p.splitWanted, p.mids, #p.nodes }, { "sl_rmid2", "sl_rmid2", nil, nil, 4 * m, 4 + 4 * m }, msg)
			for _, r in ipairs(p.nodes) do
				eq(r.status, "apply", msg)
				eq(roles(r.view, r.conns), sorted(r.mid and want[2] or want[1]), msg .. " node " .. r.node)
				if not r.mid then
					assertNoMerge(r, msg)
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
	eq(n, 7 * 4)
	-- one-lane exits: sl_rmid2 is sl_rmid, connection for connection
	local W = ringWorld(2, 1, 4, { dir = "ccw" }, 1)
	local a, b = planOf(W, "sl_rmid2"), planOf(W, "sl_rmid")
	for i, r in ipairs(a.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(b.nodes[i].conns)) end
end)

test("sl_rmid2 on a 2-lane ring with 2-lane arms: each entry lane reaches every exit (the curb lane moves in at a mid node); sl_rmid there fans o1 into both exit lanes", function()
	for _, o in ipairs(SIDES) do
		local W = ringWorld(2, 2, 4, o, 1)
		local p, ring = planOf(W, "sl_rmid2")
		for node, lanes in pairs(exitsPerLane(W, ring, p)) do
			eq(lanes, { 4, 4 }, o.dir .. " node " .. node .. ": both entry lanes reach all 4 exits")
		end
		-- turbo on the same ring: the curb entry lane reaches the first exit only (the user's ring 282381)
		local t, rt = planOf(W, "sl_rturbo")
		for node, lanes in pairs(exitsPerLane(W, rt, t)) do eq(lanes, { 1, 4 }, "turbo node " .. node) end
	end
	-- the existing sl_rmid zone mode applies on these rings too (whatever the exit width): o1 -> x1 and x2, o2 straight only
	local p = planOf(ringWorld(2, 2, 4, { dir = "ccw" }, 1), "sl_rmid")
	eq(p.layout, "sl_rmid")
	for _, r in ipairs(p.nodes) do
		if not r.mid then eq(roles(r.view, r.conns), sorted("o1>x1 o1>x2 o2>o2 e1>o1 e2>o2")) end
	end
	-- and sl_rmatch: matched lanes there (both lanes exit and circulate), not the default's spiral
	local m = planOf(ringWorld(2, 2, 4, { dir = "ccw" }, 0), "sl_rmatch")
	eq({ m.layout, m.default }, { "sl_rmatch", nil })
	for _, r in ipairs(m.nodes) do eq(roles(r.view, r.conns), sorted("o1>o1 o1>x1 o2>o2 o2>x2 e1>o1 e2>o2")) end
end)

test("sl_rmid2 without mid nodes: sl_rturbo's junctions, splitWanted (Smart Lanes adds them); sl_rmid / sl_rsplit there fall back, no split", function()
	local W = ringWorld(2, 2, 4, { dir = "ccw" }, 0)
	local p = planOf(W, "sl_rmid2")
	local t = planOf(W, "sl_rturbo")
	eq({ p.variant, p.layout, p.split, p.splitWanted, #p.nodes }, { "sl_rmid2", "sl_rturbo", "no_mid_nodes", true, 4 })
	for i, r in ipairs(p.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(t.nodes[i].conns)) end
	for _, v in ipairs({ "sl_rmid", "sl_rsplit" }) do
		local q = planOf(W, v)
		eq({ q.layout, q.split, q.splitWanted }, { "sl_rspiral", "no_mid_nodes", nil }, v)
	end
	-- the default spiral (one-lane exits) still asks for the split; a 1-lane ring never
	eq(planOf(ringWorld(2, 1, 4, { dir = "ccw" }, 0), "two_lane").splitWanted, true)
	local one = planOf(ringWorld(1, 1, 4, { dir = "ccw" }, 0), "sl_rmid2")
	eq({ one.split, one.splitWanted }, { "one_lane_ring", nil })
end)

---------------------------------------------------------------------------
-- sl_rturbo_in

test("sl_rturbo_in: the documented tables (4-lane ring 3-lane arms, 3-lane ring 2-lane arms), 3-6 arms, both sides; reachable without lane changes; no merges; o4 used", function()
	local TABLE = {
		["4:3"] = "o1>x1 o2>o2 o2>x2 o3>x3 o4>o3 o4>o4 e1>o1 e2>o2 e3>o3 e3>o4",
		["3:2"] = "o1>x1 o2>x2 o3>o2 o3>o3 e1>o1 e2>o2 e2>o3",
	}
	for key, want in pairs(TABLE) do
		local R, A = key:match("^(%d):(%d)$")
		R, A = tonumber(R), tonumber(A)
		for nArms = 3, 6 do
			for _, o in ipairs(SIDES) do
				local msg = string.format("rturbo_in R=%d arms=%dx%d %s%s", R, nArms, A, o.dir, o.mirror and " mirror" or "")
				local W = ringWorld(R, A, nArms, o, 0)
				local p, ring = planOf(W, "sl_rturbo_in")
				eq({ p.variant, p.layout, p.turbo }, { "sl_rturbo_in", "sl_rturbo_in", true }, msg)
				for _, r in ipairs(p.nodes) do
					eq(roles(r.view, r.conns), sorted(want), msg)
					assertNoMerge(r, msg)
				end
				assertReach(W, ring, p, msg)
				-- per entry lane: the curb lane the next exit, the middle lanes every exit, the innermost one every exit
				-- (by its split into the next exit lane and the circling inner lane)
				for _, lanes in pairs(exitsPerLane(W, ring, p)) do
					eq(lanes[1], 1, msg .. " e1")
					for j = 2, #lanes do eq(lanes[j], nArms, msg .. " e" .. j) end
				end
			end
		end
	end
	-- turbo on the 4-lane ring: nothing enters or leaves o4 (the user's evidence); here e3 feeds it and it leaves via o3
	local W = ringWorld(4, 3, 4, { dir = "ccw" }, 0)
	local t = planOf(W, "sl_rturbo")
	for _, r in ipairs(t.nodes) do
		local rl = roles(r.view, r.conns)
		ok(not rl:find("e%d>o4") and not rl:find("o4>x"), "turbo leaves o4 unused: " .. rl)
	end
end)

test("sl_rturbo_in: a mixed ring (2- and 3-lane arms on 4 lanes), entry-only / exit-only ramps; a one-lane exit: matched (as sl_rturbo)", function()
	local mixed = F.ring({ ringTpl = "one_way_medium", arms = { { tpl = "large" }, { tpl = "medium" }, { tpl = "large" }, { tpl = "medium" } } })
	local p, ring = planOf(mixed, "sl_rturbo_in")
	for _, r in ipairs(p.nodes) do assertNoMerge(r, "mixed") end
	assertReach(mixed, ring, p, "mixed")
	local ramps = F.ring({ ringTpl = "one_way_medium", arms = { { tpl = "large" }, { tpl = "highway_ramp2" }, { tpl = "large" },
		{ tpl = "highway_ramp2", flip = true } } })
	local pr, rr = planOf(ramps, "sl_rturbo_in")
	for _, r in ipairs(pr.nodes) do if #r.view.x > 0 then assertNoMerge(r, "ramps") end end
	assertReach(ramps, rr, pr, "ramps")
	-- a one-lane exit on the ring: turbo does not qualify, matched lanes as sl_rturbo
	local narrow = F.ring({ ringTpl = "one_way_medium", arms = { { tpl = "large" }, { tpl = "small" }, { tpl = "large" }, { tpl = "large" } } })
	local pn = planOf(narrow, "sl_rturbo_in")
	local tn = planOf(narrow, "sl_rturbo")
	eq(pn.turbo, false)
	for i, r in ipairs(pn.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(tn.nodes[i].conns)) end
end)

---------------------------------------------------------------------------
-- The script: an sl_rmid2 zone on a 2-lane ring with 2-lane arms and no mid nodes (split, then written)

local BASE = 22767

local function runZone(ab, extra)
	local W = F.shift(ringWorld(2, 2, 4, { dir = "ccw" }, extra or 0), BASE, 0, 0)
	local G = makeGame(nil, { world = function() return W end, conns = {} })
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", Zones.EVENT_ID, Zones.EV_ZONES,
		{ op = "set", run = "lu", zones = { { x = 0, y = 0, r = 60, ab = ab, id = "r2m" } } })
	local ring = assert(Ring.findRing(G.world, BASE + 1))
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(ring.nodes) do sp.addedNodes[#sp.addedNodes + 1] = { entity = n } end
	for _, sid in ipairs(ring.segs) do
		local s = G.world.segs[sid]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = sid, comp = { node0 = s.node0, node1 = s.node1 } }
	end
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	G.frames(100)
	return G
end

test("script: an sl_rmid2 zone splits the ring's stretches (SPLIT), then writes 4 junctions + 4 mid nodes (layout=sl_rmid2, mid=yes, zid=)", function()
	local G = runZone("sl_rmid2")
	eq(#G.kinds("ERROR"), 0)
	local sp = G.kinds("SPLIT")
	eq(#sp, 1)
	ok(sp[1]:find(" nodes_added=4", 1, true), sp[1])
	ok(table.concat(G.kinds("WRITE"), "\n"):find("WRITE kind=split ring=%d+ success=true"))
	local rs = G.kinds("RSPLIT")
	ok(#rs >= 1 and rs[#rs]:find(" mids=4 per_stretch=1 ", 1, true) and rs[#rs]:find(" zid=r2m$"), tostring(rs[#rs]))
	local mids, junctions = 0, 0
	for _, l in ipairs(G.kinds("APPLY")) do
		ok(l:find(" layout=sl_rmid2", 1, true) and l:find(" zid=r2m$"), l)
		if l:find(" mid=yes", 1, true) then
			mids = mids + 1
			ok(l:find(" before=2 after=4 ", 1, true), l)
		else
			junctions = junctions + 1
		end
	end
	eq({ junctions, mids }, { 4, 4 })
	local ring = assert(Ring.findRing(G.world, BASE + 1))
	local want = Rules.planRing(G.world, ring, all(G.world), "sl_rmid2", function() return {} end)
	eq(want.layout, "sl_rmid2")
	for _, r in ipairs(want.nodes) do
		eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), "node " .. r.node)
	end
	ok(table.concat(G.kinds("VERIFY"), "\n"):find("VERIFY ring=%d+ same=8 nodes=8"))
end)

test("script: sl_rmid / sl_rturbo_in zones never split; sl_rturbo_in writes its layout (layout=sl_rturbo_in)", function()
	local G = runZone("sl_rmid")
	eq(#G.kinds("SPLIT"), 0)
	ok(G.kinds("RSPLIT")[1]:find("mids=0 fallback=sl_rspiral reason=no_mid_nodes", 1, true))
	local T = runZone("sl_rturbo_in")
	eq(#T.kinds("SPLIT"), 0)
	eq(#T.kinds("ERROR"), 0)
	local a = T.kinds("APPLY")
	eq(#a, 4)
	for _, l in ipairs(a) do ok(l:find(" layout=sl_rturbo_in", 1, true) and l:find(" zid=r2m$"), l) end
end)
