-- square_smart_lanes: ring layout variants for the Stress Test bench (sl_rules M.variantConns / planRing with a
-- Rules.RING_VARIANTS variant; PLAN.md "Ring layout variants (bench)"). Per variant the exact connections of an arm
-- junction for 2-, 3- and 4-lane rings with 2- and 3-lane arms, both directions and both traffic sides,
-- reachability, and the counts table of the plan.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

F.TPL.one_way3 = "BS FV FV FV FS" -- a 3-lane one-way ring street (as highway_new_large's 3 lanes)
local RING_TPL = { [2] = "one_way_small", [3] = "one_way3", [4] = "one_way_medium" }
local ARM_TPL = { [2] = "medium", [3] = "large" }

local function all(world)
	local s = {}
	for id in pairs(world.nodes) do s[id] = true end
	return s
end

--- A ring of R lanes with `arms` arms of `armLanes` lanes each way; o = { dir, mirror }.
local function ringWorld(R, armLanes, nArms, o)
	local arms = {}
	for k = 1, nArms do arms[k] = { tpl = ARM_TPL[armLanes] } end
	return F.ring({ ringTpl = RING_TPL[R], arms = arms, dir = o.dir, mirror = o.mirror })
end

--- The plan of the ring through node 1 under `variant` (every node a seed unless `seeds`).
local function planOf(W, variant, seeds)
	local ring = assert(Ring.findRing(W, 1))
	return Rules.planRing(W, ring, seeds or all(W), variant, function() return {} end), ring
end

--- A junction's road connections in lane roles, sorted: "o2>o1" (ring in lane 2 -> ring out lane 1), "o1>x3",
-- "e2>o2" (positions kerb first: o1 outer, x1 / e1 kerb).
local function roles(v, conns)
	local pos = {}
	local function index(list, prefix, seg)
		for i, l in ipairs(list) do pos[seg .. ":" .. l .. ":" .. prefix] = prefix .. i end
	end
	index(v.o_in, "o", v.ringIn)
	index(v.e, "e", v.arm)
	local outPos = {}
	for i, l in ipairs(v.o_out) do outPos[v.ringOut .. ":" .. l] = "o" .. i end
	for i, l in ipairs(v.x) do outPos[v.arm .. ":" .. l] = "x" .. i end
	local out = {}
	for _, c in ipairs(conns) do
		if c.withRoad then
			local from = pos[c.segment0 .. ":" .. c.lane0 .. ":o"] or pos[c.segment0 .. ":" .. c.lane0 .. ":e"] or "?"
			out[#out + 1] = from .. ">" .. (outPos[c.segment1 .. ":" .. c.lane1] or "?")
		end
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

-- expected roles per variant, "R:armLanes" (4 arms)
local WANT = {
	sl_rturbo = {
		["2:2"] = "o1>x1 o2>o2 o2>x2 e1>o1 e2>o2",
		["2:3"] = "o1>x1 o2>o2 o2>x2 o2>x3 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>x1 o2>o2 o2>x2 o3>o3 e1>o1 e2>o2",
		["3:3"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>x1 o2>o2 o2>x2 o3>o3 o4>o4 e1>o1 e2>o2",
		["4:3"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 o4>o4 e1>o1 e2>o2 e3>o3",
	},
	sl_rmatch = {
		["2:2"] = "o1>o1 o1>x1 o2>o2 o2>x2 e1>o1 e2>o2",
		["2:3"] = "o1>o1 o1>x1 o2>o2 o2>x2 o2>x3 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>o1 o1>x1 o2>o2 o2>x2 o3>o3 e1>o1 e2>o2",
		["3:3"] = "o1>o1 o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>o1 o1>x1 o2>o2 o2>x2 o3>o3 o4>o4 e1>o1 e2>o2",
		["4:3"] = "o1>o1 o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 o4>o4 e1>o1 e2>o2 e3>o3",
	},
	sl_rout1 = {
		["2:2"] = "o1>o1 o1>x1 o1>x2 o2>o2 e1>o1 e2>o2",
		["2:3"] = "o1>o1 o1>x1 o1>x2 o1>x3 o2>o2 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>o1 o1>x1 o1>x2 o2>o2 o3>o3 e1>o1 e2>o2",
		["3:3"] = "o1>o1 o1>x1 o1>x2 o1>x3 o2>o2 o3>o3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>o1 o1>x1 o1>x2 o2>o2 o3>o3 o4>o4 e1>o1 e2>o2",
		["4:3"] = "o1>o1 o1>x1 o1>x2 o1>x3 o2>o2 o3>o3 o4>o4 e1>o1 e2>o2 e3>o3",
	},
	sl_r2exit = {
		["2:2"] = "o1>x1 o2>o2 o2>x2 e1>o1 e2>o2",
		["2:3"] = "o1>x1 o2>o2 o2>x2 o2>x3 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>x1 o2>o2 o2>x2 o3>o3 e1>o1 e2>o2",
		["3:3"] = "o1>x1 o2>o2 o2>x2 o2>x3 o3>o3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>x1 o2>o2 o2>x2 o3>o3 o4>o4 e1>o1 e2>o2",
		["4:3"] = "o1>x1 o2>o2 o2>x2 o2>x3 o3>o3 o4>o4 e1>o1 e2>o2 e3>o3",
	},
	sl_rspiral = {
		["2:2"] = "o1>x1 o1>x2 o2>o1 o2>o2 e1>o1 e2>o2",
		["2:3"] = "o1>x1 o1>x2 o1>x3 o2>o1 o2>o2 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>x1 o1>x2 o2>o1 o3>o2 o3>o3 e1>o1 e2>o2 e2>o3",
		["3:3"] = "o1>x1 o1>x2 o1>x3 o2>o1 o3>o2 o3>o3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>x1 o1>x2 o2>o1 o3>o2 o4>o3 e1>o1 e2>o2 e2>o3 e2>o4",
		["4:3"] = "o1>x1 o1>x2 o1>x3 o2>o1 o3>o2 o4>o3 e1>o1 e2>o2 e3>o3 e3>o4",
	},
	sl_rspread = {
		["2:2"] = "o1>x1 o2>o2 o2>x2 e1>o1 e2>o2",
		["2:3"] = "o1>x1 o2>o2 o2>x2 o2>x3 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x2 e1>o1 e2>o2 e2>o3",
		["3:3"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x2 o4>o4 o4>x2 e1>o1 e2>o2 e2>o3 e2>o4",
		["4:3"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 o4>o4 o4>x3 e1>o1 e2>o2 e3>o3 e3>o4",
	},
	-- turbo with the inner lanes fed (PLAN.md "Ring lane use (in progress)"): where the arm leaves ring lanes out, the
	-- innermost exiting lane exits only, the inner lanes shift one lane outwards (the innermost also circles), and the
	-- innermost entry lane splits into them; elsewhere sl_rturbo
	sl_rturbo_in = {
		["2:2"] = "o1>x1 o2>o2 o2>x2 e1>o1 e2>o2",
		["2:3"] = "o1>x1 o2>o2 o2>x2 o2>x3 e1>o1 e2>o2 e3>o2",
		["3:2"] = "o1>x1 o2>x2 o3>o2 o3>o3 e1>o1 e2>o2 e2>o3",
		["3:3"] = "o1>x1 o2>o2 o2>x2 o3>o3 o3>x3 e1>o1 e2>o2 e3>o3",
		["4:2"] = "o1>x1 o2>x2 o3>o2 o4>o3 o4>o4 e1>o1 e2>o2 e2>o3 e2>o4",
		["4:3"] = "o1>x1 o2>o2 o2>x2 o3>x3 o4>o3 o4>o4 e1>o1 e2>o2 e3>o3 e3>o4",
	},
}
-- sl_rmid2 on rings without mid nodes (and no split here: planRing only plans): sl_rturbo's junctions (test_rmid2.lua
-- has it with mid nodes)
WANT.sl_rmid2 = WANT.sl_rturbo
-- variants whose every entry reaches every exit without a lane change on a segment
local NO_LANE_CHANGE = { sl_rspiral = true, sl_rturbo_in = true }

local SIDES = { { dir = "ccw" }, { dir = "cw" }, { dir = "ccw", mirror = true }, { dir = "cw", mirror = true } }

local function assertReach(W, ring, p, laneChange, msg)
	local m = {}
	for _, r in ipairs(p.nodes) do m[r.node] = r.conns end
	local reach, dead = Rules.reachability(W, ring, m, laneChange)
	local ins, outs = {}, {}
	for _, r in ipairs(p.nodes) do
		local v = r.view
		if #v.e > 0 then ins[#ins + 1] = v.arm end
		if #v.x > 0 then outs[#outs + 1] = v.arm end
	end
	for _, a in ipairs(ins) do
		for _, b in ipairs(outs) do ok(reach[a] and reach[a][b], msg .. " entry " .. a .. " -> exit " .. b) end
	end
	eq(next(dead), nil, msg .. " dead ring lanes")
end

test("ring variants: exact connections per variant, 2/3/4-lane rings, 2/3-lane arms, both directions and sides", function()
	local n = 0
	for variant, cases in pairs(WANT) do
		for key, want in pairs(cases) do
			local R, A = key:match("^(%d):(%d)$")
			R, A = tonumber(R), tonumber(A)
			for _, o in ipairs(SIDES) do
				local msg = string.format("%s R=%d arms=%d %s%s", variant, R, A, o.dir, o.mirror and " mirror" or "")
				local W = ringWorld(R, A, 4, o)
				local p, ring = planOf(W, variant)
				eq(ring.lanes, R, msg)
				eq(p.variant, variant, msg)
				eq(#p.nodes, 4, msg)
				for _, r in ipairs(p.nodes) do
					eq(r.status, "apply", msg)
					eq(roles(r.view, r.conns), sorted(want), msg .. " node " .. r.node)
				end
				-- every entry reaches every exit: the spiral without lane changes, the others with them (as today)
				assertReach(W, ring, p, not NO_LANE_CHANGE[variant], msg)
				n = n + 1
			end
		end
	end
	eq(n, 8 * 6 * 4)
end)

test("ring variants: connections per arm junction match PLAN.md's table (3+3 arms unless noted)", function()
	-- rsplit / rmid: on these rings without mid nodes they fall back to rspiral (its own counts: the mid-node tests below)
	-- rmid2 without mid nodes: rturbo's
	local TABLE = { -- R:armLanes = { rturbo, rmatch, rout1, r2exit, rspiral, rspread, rsplit, rmid, rmid2, rturbo_in }
		["2:2"] = { 5, 6, 6, 5, 6, 5, 6, 6, 5, 5 }, ["2:3"] = { 7, 8, 8, 7, 8, 7, 8, 8, 7, 7 },
		["3:2"] = { 6, 7, 7, 6, 8, 8, 8, 8, 6, 7 },
		["3:3"] = { 8, 9, 9, 8, 9, 8, 9, 9, 8, 8 }, ["4:3"] = { 9, 10, 10, 9, 10, 11, 10, 10, 9, 10 },
	}
	for key, counts in pairs(TABLE) do
		local R, A = key:match("^(%d):(%d)$")
		for i, variant in ipairs(Rules.RING_VARIANTS) do
			local p = planOf(ringWorld(tonumber(R), tonumber(A), 4, { dir = "ccw" }), variant)
			for _, r in ipairs(p.nodes) do eq(r.after, counts[i], variant .. " " .. key) end
		end
	end
end)

test("ring variants: spiral depth follows the exits (3 arms: no circling lane; the U-turn stays reachable)", function()
	-- 3 arms on a 3-lane ring: D = 3 = A, entry lane j leaves at the j-th exit downstream (the 3rd: the U-turn)
	local W3 = ringWorld(3, 3, 3, { dir = "ccw" })
	local p, ring = planOf(W3, "sl_rspiral")
	for _, r in ipairs(p.nodes) do
		eq(roles(r.view, r.conns), sorted("o1>x1 o1>x2 o1>x3 o2>o1 o3>o2 e1>o1 e2>o2 e3>o3"))
	end
	assertReach(W3, ring, p, false, "spiral 3 arms")
	-- a 2-lane ring on 4 arms: the inner lane circles to the farther exits
	local W = ringWorld(2, 2, 4, { dir = "ccw" })
	local p4, ring4 = planOf(W, "sl_rspiral")
	assertReach(W, ring4, p4, false, "spiral 2-lane 4 arms")
end)

test("ring variants: a 1-lane ring keeps matched lanes in every variant; skipped junctions stay skipped", function()
	for _, variant in ipairs(Rules.RING_VARIANTS) do
		local W = F.ring({ ringTpl = "one_way_town1", arms = { { tpl = "small" }, { tpl = "small" }, { tpl = "small" } } })
		local p = planOf(W, variant)
		local m = planOf(F.ring({ ringTpl = "one_way_town1", arms = { { tpl = "small" }, { tpl = "small" }, { tpl = "small" } } }), "matched")
		for i, r in ipairs(p.nodes) do eq(Rules.connsText(r.conns), Rules.connsText(m.nodes[i].conns), variant) end
	end
	-- a road through the centre (a skipped junction) stays skipped
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "medium" } end
	arms[1].through = true
	local W = F.ring({ ringTpl = "one_way_small", arms = arms })
	local p = planOf(W, "sl_rturbo")
	local skipped = 0
	for _, r in ipairs(p.nodes) do if r.status == "skip" then skipped = skipped + 1 end end
	ok(skipped >= 1, "skipped junction")
end)

test("ring variants: the plan is the same whatever the seeds (the zone writes whole rings, the rule has no freshness)", function()
	for _, variant in ipairs(Rules.RING_VARIANTS) do
		local W = ringWorld(3, 3, 4, { dir = "ccw" })
		local whole = planOf(W, variant)
		local ring = assert(Ring.findRing(W, 1))
		for _, n in ipairs(ring.nodes) do
			local p = Rules.planRing(W, ring, { [n] = true }, variant, function() return {} end)
			for _, r in ipairs(p.nodes) do
				if r.node == n then
					local w
					for _, x in ipairs(whole.nodes) do if x.node == n then w = x end end
					eq(Rules.connsText(r.conns), Rules.connsText(w.conns), variant .. " seeded alone: node " .. n)
				end
			end
		end
	end
	-- planRing's default rule alone does depend on it (freshness); the automatic pass gives it whole rings
	-- (Rules.autoSeeds, test_wholering.lua), so there the layout does not depend on the seeds either
	local W = ringWorld(3, 3, 4, { dir = "ccw" })
	local ring = assert(Ring.findRing(W, 1))
	local fresh = Rules.planRing(W, ring, all(W), "two_lane", function() return {} end)
	local partial = Rules.planRing(W, ring, { [ring.nodes[1]] = true }, "two_lane", function() return {} end)
	eq(fresh.turbo, true)
	eq(partial.turbo, false)
	local auto = Rules.autoSeeds(W, ring, { [ring.nodes[1]] = true }, function() return {} end)
	eq(Rules.planRing(W, ring, auto.seeds, "two_lane", function() return {} end).turbo, true)
end)

test("ring variants: unknown variant names and the old variants plan as before", function()
	local W = ringWorld(2, 2, 4, { dir = "ccw" })
	local ring = assert(Ring.findRing(W, 1))
	local p = Rules.planRing(W, ring, all(W), "sl_rnope", function() return {} end)
	for _, r in ipairs(p.nodes) do eq(r.status, "skip") end
	eq(p.variant, nil)
	for _, v in ipairs({ "two_lane", "matched", "turbo", "engine" }) do eq(Rules.planRing(W, ring, all(W), v, function() return {} end).variant, nil) end
end)
