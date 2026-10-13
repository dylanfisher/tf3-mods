-- square_smart_lanes: the automatic pass spread over GUI frames (PERF_REVIEW.md 2026-10-12). With a fake
-- api.type.Clock (fakegame opts.clock: time moves only by the modelled cost of api calls) a job runs in
-- steps within the frame budget; without a Clock it runs in one frame. Both give the same lines and the
-- same written configs; every write is built in the frame it is sent in.

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local BUDGET_US = 8000 -- sl_lanes.script.lua BUDGET_MS
local SLACK_US = 2000  -- one step may start just inside the budget, plus the frame's send

--- The game's six default phases (findings.md) for a crossroads whose arms are segs (axis 1: segs 1 and 3).
local function gameSix(conns, nCross, segs)
	local function phase(green, cwGreen, d)
		local l = {}
		for i, c in ipairs(conns) do if not green[c.segment0] then l[#l + 1] = i - 1 end end
		for k = 1, nCross do if not cwGreen then l[#l + 1] = #conns + k - 1 end end
		return { lockedLanes = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	local a, b = { [segs[1]] = true, [segs[3] or -1] = true }, { [segs[2]] = true, [segs[4] or -1] = true }
	return { phase(a, false, 24), phase({}, false, 6), phase(b, false, 24), phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) }
end

--- A 13 x 13 grid of two-way medium streets (crossroads, T-junctions at the edge) with the probe ring:
-- 160 seeds; the junctions get the game's lanes and, all but every 7th (light unknown), a light with the
-- game's six phases.
local function gridGame(params, opts)
	local gw = F.oneWayGrid(13, 80, 900000, false, F.TPL.medium)
	local seeds = {}
	for id in pairs(gw.nodes) do seeds[#seeds + 1] = id end
	table.sort(seeds)
	while #seeds > 160 do table.remove(seeds) end
	local G = makeGame(params, { world = function() return F.merge(F.PROBE_4LANE_MEDIUM.world(), gw) end,
		conns = F.PROBE_4LANE_MEDIUM.conns }, opts)
	for k, n in ipairs(seeds) do
		local v = Slip.classify(G.world, n)
		if v and v.case == "X" then
			local conns = Slip.defaultConns(v)
			local cfg = G.configs[n]
			cfg.laneConnections = conns
			local cws = {}
			for _, s in ipairs(G.world.nodes[n].segs) do cws[#cws + 1] = s end
			cfg.crosswalks = cws
			cfg.trafficLightPreference = G.TLP.AUTO
			if k % 7 ~= 0 then
				G.lights[n] = true
				cfg.trafficLightConfig = G.tlc(gameSix(conns, #cws, G.world.nodes[n].segs))
			end
		end
	end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G, seeds
end

local function build(G, seeds)
	local sp = { addedNodes = {}, addedSegments = { { entity = 0, comp = {} } }, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(seeds) do sp.addedNodes[#sp.addedNodes + 1] = { entity = n } end
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
end

--- n frames; proposals answer between frames (as in game: never inside the frame that sent them).
local function frames(G, n)
	G.defer = true
	for _ = 1, n do
		G.frames(1)
		G.flush()
	end
end

local function sqrl(G)
	local out = {}
	for _, l in ipairs(G.logs) do
		if l:find("[SQRL] ", 1, true) then out[#out + 1] = l end
	end
	return out
end

local function sorted(list)
	local c = {}
	for i, x in ipairs(list) do c[i] = x end
	table.sort(c)
	return c
end

--- Every node's written lanes and phases, as text.
local function configs(G)
	local out = {}
	for id, c in pairs(G.configs) do
		local st = {}
		for i, s in ipairs(c.trafficLightConfig and c.trafficLightConfig.states or {}) do
			st[i] = table.concat(sorted(s.lockedLanes or {}), ",") .. "/" .. tostring(s.duration)
		end
		out[#out + 1] = id .. " " .. Rules.connsText(c.laneConnections) .. " | " .. table.concat(st, ";")
	end
	return sorted(out)
end

--- node -> number of lane proposals naming it.
local function proposalsPerNode(G)
	local per = {}
	for _, cmd in ipairs(G.sent) do
		for _, n in ipairs(cmd.proposal.streetProposal.nodeConfigsToRemove) do per[n] = (per[n] or 0) + 1 end
	end
	return per
end

local function maxFrame(G)
	local m = 0
	for _, u in ipairs(G.frameUs) do if u > m then m = u end end
	return m
end

test("frames: a 160-node lit grid job spans frames within the budget; the same lines and configs as in one frame", function()
	for _, params in ipairs({ { sqrl_free_turn = 2 }, { sqrl_light_phases = 2 } }) do
		local G1, seeds = gridGame(params)
		build(G1, seeds)
		frames(G1, 1200)
		local Gn = gridGame(params, { clock = true })
		build(Gn, seeds)
		frames(Gn, 1200)
		eq(#G1.sent, 1, "no Clock: the job in one frame, one proposal")
		ok(#Gn.sent > 5, "with the budget: one proposal per frame that built entries (" .. #Gn.sent .. ")")
		-- every node in exactly one lane proposal
		for n, k in pairs(proposalsPerNode(Gn)) do eq(k, 1, "node " .. n) end
		-- the same lines (the frames change only their order) and the same written configs
		eq(sorted(sqrl(Gn)), sorted(sqrl(G1)), "the same SQRL lines")
		eq(configs(Gn), configs(G1), "the same configs")
		for _, kind in ipairs({ "SUMMARY", "AUDIT", "AUDIT_SUMMARY", "WRITE", "VERIFY", "RECHECK" }) do
			eq(Gn.kinds(kind), G1.kinds(kind), kind .. " lines in the same order")
		end
		eq(#Gn.kinds("WRITE"), 1, "one WRITE line for the job, as before")
		ok(Gn.kinds("WRITE")[1]:find("kind=slip job=1 nodes=900001,900002,", 1, true), Gn.kinds("WRITE")[1])
		eq(#Gn.kinds("ERROR"), 0)
		-- no frame over the budget (plus at most one step and the frame's send)
		local m = maxFrame(Gn)
		ok(m <= BUDGET_US + SLACK_US, "max frame " .. m .. " us")
		local busy = 0
		for _, u in ipairs(Gn.frameUs) do if u > 0 then busy = busy + 1 end end
		ok(busy > 10, "the work spread over " .. busy .. " frames")
	end
end)

test("frames: the world changes between frames: a removed node and a replaced segment are never written stale", function()
	local G, seeds = gridGame({ sqrl_free_turn = 2 }, { clock = true })
	build(G, seeds)
	-- run until the job has sent a part of its slip writes
	local guard = 0
	repeat
		frames(G, 1)
		guard = guard + 1
	until #G.sent > 0 or guard > 400
	ok(#G.sent > 0 and #G.kinds("SUMMARY") == 0, "the job is under way")
	local done = proposalsPerNode(G)
	-- two crossroads the job has not reached yet (near the last seeds): one removed, one whose first
	-- segment is replaced
	local gone, moved = 900000 + 11 * 13 + 7, 900000 + 11 * 13 + 4
	ok(not done[gone] and not done[moved])
	for _, s in ipairs(G.world.nodes[gone].segs) do
		local sg = G.world.segs[s]
		local other = sg.node0 == gone and sg.node1 or sg.node0
		local keep = {}
		for _, x in ipairs(G.world.nodes[other].segs) do if x ~= s then keep[#keep + 1] = x end end
		G.world.nodes[other].segs = keep
		G.world.segs[s] = nil
	end
	G.world.nodes[gone] = nil
	G.configs[gone] = nil
	G.lights[gone] = nil
	local old = G.world.nodes[moved].segs[1]
	local sg = G.world.segs[old]
	local new = 990001
	G.world.segs[new] = { node0 = sg.node0, node1 = sg.node1, lanes = sg.lanes, p0 = sg.p0, p1 = sg.p1, t0 = sg.t0, t1 = sg.t1 }
	G.world.segs[old] = nil
	for _, n in ipairs({ sg.node0, sg.node1 }) do
		for i, x in ipairs(G.world.nodes[n].segs) do if x == old then G.world.nodes[n].segs[i] = new end end
		-- the game gives a node whose edge was replaced a new config (no connections yet: here, none)
		if not done[n] then
			G.configs[n].laneConnections = {}
			G.configs[n].trafficLightConfig = nil
			G.lights[n] = nil
		end
	end
	frames(G, 1200)
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
	eq(#G.kinds("SUMMARY"), 1)
	local per = proposalsPerNode(G)
	eq(per[gone], nil, "the removed node is never written")
	eq(per[moved], 1, "the node with the new segment is written once")
	-- its connections name the new segment, never the old one
	local uses = { [old] = 0, [new] = 0 }
	for _, c in ipairs(G.configs[moved].laneConnections) do
		for _, s in ipairs({ c.segment0, c.segment1 }) do
			if uses[s] ~= nil then uses[s] = uses[s] + 1 end
		end
	end
	eq(uses[old], 0, "no stale segment id")
	ok(uses[new] > 0, "the new segment's lanes are connected")
	for n, k in pairs(per) do eq(k, 1, "node " .. n) end
end)

test("frames: build events during a job wait for it; a waiting job that shares nodes takes in the later one (merged=)", function()
	local G, seeds = gridGame({ sqrl_free_turn = 2 }, { clock = true })
	build(G, seeds)
	local guard = 0
	repeat
		frames(G, 1)
		guard = guard + 1
	until #G.sent > 0 or guard > 400
	ok(#G.kinds("SUMMARY") == 0, "job 1 under way")
	-- two builds at the probe ring while job 1 runs; the second shares node 22768 with the first
	build(G, { 22768, 23292 })
	build(G, { 23293, 23294, 22768 })
	frames(G, 6)
	eq(#G.kinds("SUMMARY"), 0, "job 1 still under way: the new jobs wait")
	frames(G, 1500)
	eq(#G.kinds("ERROR"), 0)
	local s = G.kinds("SUMMARY")
	eq(#s, 2, table.concat(s, "\n"))
	ok(s[1]:find("SUMMARY job=1 nodes=160 ", 1, true), s[1])
	ok(s[2]:find("SUMMARY job=2 nodes=4 rings=1 ring=4/0/0 ", 1, true) and s[2]:find(" merged=3", 1, true), s[2])
	-- no line of job 2 before job 1's summary (one job at a time)
	local iSum1, iRing = nil, nil
	for i, l in ipairs(G.logs) do
		if l:find("SUMMARY job=1 ", 1, true) then iSum1 = i end
		if iRing == nil and l:find("APPLY ring=", 1, true) then iRing = i end
	end
	ok(iSum1 ~= nil and iRing ~= nil and iSum1 < iRing, "job 2's ring after job 1's summary")
	-- the ring whole in one proposal
	local ring = {}
	for _, l in ipairs(G.kinds("APPLY")) do
		local n = l:match("^%[SQRL%] APPLY ring=%S+ node=(%d+)")
		if n then ring[#ring + 1] = tonumber(n) end
	end
	eq(#ring, 4)
	local whole = false
	for _, cmd in ipairs(G.sent) do
		local set = {}
		for _, n in ipairs(cmd.proposal.streetProposal.nodeConfigsToRemove) do set[n] = true end
		local all = true
		for _, n in ipairs(ring) do if not set[n] then all = false end end
		if all then whole = true end
	end
	ok(whole, "the ring's four junctions in one proposal")
end)

test("frames: rings stay whole in one proposal and every node is written once, whatever the frame budget cuts", function()
	-- roundabouts (two-lane rings with 3 to 5 arms, both directions), an alternating one-way grid and
	-- Channelized Junctions; a tight cost model
	local subs = { F.oneWayGrid(7, 60, 0, true) }
	for k = 1, 6 do
		local arms = {}
		for _ = 1, 2 + k % 4 do arms[#arms + 1] = { tpl = "medium" } end
		subs[#subs + 1] = F.ring({ ringTpl = "one_way_medium", radius = 40, arms = arms, dir = k % 2 == 0 and "cw" or "ccw" })
	end
	for k = 1, 4 do subs[#subs + 1] = F.channelX({ main = F.TPL.large, mirror = k % 2 == 0 }) end
	local seeds, worlds = {}, {}
	for k, w in ipairs(subs) do
		local sw = F.shift(w, 100000 * k, 3000 * k, 4000)
		worlds[#worlds + 1] = sw
		local ids = {}
		for id in pairs(sw.nodes) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do seeds[#seeds + 1] = id end
	end
	local fx = { world = function()
		local w = F.PROBE_4LANE_MEDIUM.world()
		for _, sw in ipairs(worlds) do F.merge(w, sw) end
		return w
	end, conns = F.PROBE_4LANE_MEDIUM.conns }
	local function run(opts)
		local G = makeGame(nil, fx, opts)
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		build(G, seeds)
		frames(G, 1500)
		return G
	end
	local G1 = run(nil)
	-- reads cost 10x: the budget cuts after a few steps
	local Gn = run({ clock = true, costs = { BN = 250, BE = 500, BNC = 600, BNC_ITEM = 20, segs = 100, cmd = 1000, cmd_item = 100 } })
	eq(#Gn.kinds("ERROR"), 0)
	eq(sorted(sqrl(Gn)), sorted(sqrl(G1)), "the same SQRL lines")
	eq(configs(Gn), configs(G1), "the same configs")
	for n, k in pairs(proposalsPerNode(Gn)) do eq(k, 1, "node " .. n) end
	-- each ring's applied junctions in one proposal (WRITE ring=<key> nodes=...)
	local rings = 0
	for _, l in ipairs(Gn.kinds("WRITE")) do
		local key, list = l:match("WRITE ring=(%S+) nodes=(%S+)")
		if key then
			rings = rings + 1
			local nodes = {}
			for x in list:gmatch("%d+") do nodes[#nodes + 1] = tonumber(x) end
			local found = false
			for _, cmd in ipairs(Gn.sent) do
				local set = {}
				for _, n in ipairs(cmd.proposal.streetProposal.nodeConfigsToRemove) do set[n] = true end
				local all = #cmd.proposal.streetProposal.nodeConfigsToRemove == #nodes
				for _, n in ipairs(nodes) do if not set[n] then all = false end end
				if all then found = true end
			end
			ok(found, "ring " .. key .. ": its own proposal")
		end
	end
	ok(rings >= 6, "rings written: " .. rings)
	local busy = 0
	for _, u in ipairs(Gn.frameUs) do if u > 0 then busy = busy + 1 end end
	ok(busy > 20, "spread over " .. busy .. " frames")
end)

test("frames: a slip step that fails is logged (ERROR where=slip_step) and the job goes on; nothing stays held", function()
	local G, seeds = gridGame({ sqrl_free_turn = 2 }, { clock = true })
	local real = Slip.plan
	local bad = seeds[120]
	Slip.plan = function(world, n, ...)
		if n == bad then error("plan boom") end
		return real(world, n, ...)
	end
	local okR, e = pcall(function()
		build(G, seeds)
		frames(G, 600)
	end)
	assert(okR, e)
	local errs = G.kinds("ERROR")
	eq(#errs, 1)
	ok(errs[1]:find("where=slip_step ", 1, true) and errs[1]:find("plan_boom", 1, true), errs[1])
	eq(#G.kinds("SUMMARY"), 1, "the job finished")
	ok(G.kinds("SUMMARY")[1]:find("SUMMARY job=1 nodes=160 ", 1, true), G.kinds("SUMMARY")[1])
	ok(#G.kinds("WRITE") >= 1, "the other nodes written")
	for _, w in ipairs(G.kinds("WRITE")) do ok(w:find(" success=true", 1, true), w) end
	-- nothing stays held: the next job runs as well
	Slip.plan = real
	build(G, seeds)
	frames(G, 1200)
	eq(#G.kinds("SUMMARY"), 2)
	ok(G.kinds("SUMMARY")[2]:find("SUMMARY job=2 nodes=160 ", 1, true), G.kinds("SUMMARY")[2])
	eq(#G.kinds("ERROR"), 1)
end)

test("frames: verifies and re-checks share the budget, and re-checks wait while a job runs", function()
	local G, seeds = gridGame({ sqrl_free_turn = 3 }, { clock = true })
	build(G, seeds)
	frames(G, 1200)
	eq(#G.kinds("ERROR"), 0)
	-- the light-unknown junctions get their light and the game's phases: the re-check frees their kerb turns
	eq(#G.kinds("RECHECK"), 2, table.concat(G.kinds("RECHECK"), "\n"))
	ok(G.kinds("VERIFY")[1]:find("kind=slip job=1 same=", 1, true), G.kinds("VERIFY")[1])
	local same, total = G.kinds("VERIFY")[1]:match("same=(%d+) nodes=(%d+)")
	eq(same, total, "every written node read back as sent")
	ok(maxFrame(G) <= BUDGET_US + SLACK_US, "max frame " .. maxFrame(G))
end)

test("frames: a job waits while a proposal of ours naming one of its nodes is unanswered (ring, lights-off)", function()
	local G = makeGame(nil)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.defer = true -- nothing answers until G.flush()
	build(G, { 22768 })
	G.frames(20)
	eq(#G.sent, 1, "the ring's proposal went out")
	build(G, { 22768 })
	G.frames(30)
	eq(#G.kinds("SUMMARY"), 1, "job 2 waits for the ring's answer")
	-- the ring lands (its lights-off then goes out first, held until it answered)
	G.defer = false
	G.flush()
	G.frames(60)
	eq(#G.kinds("SUMMARY"), 2)
	ok(G.kinds("SUMMARY")[2]:find("SUMMARY job=2 ", 1, true), G.kinds("SUMMARY")[2])
	eq(#G.sent, 1, "job 2 read the landed ring: nothing to write")
	eq(#G.kinds("ERROR"), 0)
end)

test("frames: a refused part (one stale entry among 10) is sent again entry by entry from fresh reads: 9 written, retry= on WRITE", function()
	-- 10 crossroads inside the grid (not on the probe ring), one job; bad = an entry the engine refuses
	-- (as a stale segment or another mod's pending light change would)
	local seeds = {}
	for j = 1, 10 do seeds[#seeds + 1] = 900000 + 2 * 13 + j end
	local bad = seeds[4]
	local function hasBad(cmd)
		for _, n in ipairs(cmd.proposal.streetProposal.nodeConfigsToRemove) do
			if n == bad then return true end
		end
		return false
	end
	for _, clock in ipairs({ false, true }) do
		local tag = clock and "budget" or "one frame"
		local base = gridGame({ sqrl_free_turn = 2 }, { clock = clock })
		build(base, seeds)
		frames(base, 200)
		eq(#base.sent, clock and #base.sent or 1, tag)
		local want = configs(base)
		local G = gridGame({ sqrl_free_turn = 2 }, { clock = clock })
		local before = Rules.connsText(G.configs[bad].laneConnections)
		G.refuse = hasBad
		build(G, seeds)
		frames(G, 200)
		-- the part with bad refused; every entry of it again alone: bad refused again, the others landed
		local per = proposalsPerNode(G)
		local partSize = #G.sent[1].proposal.streetProposal.nodeConfigsToRemove
		if not clock then eq(partSize, 10, tag .. ": one part of 10 entries") end
		local retried = 0
		for _, l in ipairs(G.kinds("RETRY")) do
			retried = retried + 1
			local n = tonumber(l:match(" node=(%d+)"))
			if n == bad then
				ok(l:find("kind=slip job=1 node=" .. bad .. " result=refused", 1, true), l)
			else
				ok(l:find(" result=landed", 1, true), l)
				eq(per[n], 2, tag .. ": node " .. n .. " in its part and its retry")
			end
		end
		ok(retried >= 2 and retried <= 10, tag .. ": the refused part's entries retried (" .. retried .. ")")
		if not clock then eq(retried, 10, tag) end
		eq(per[bad], 2, tag .. ": bad retried once only")
		-- every other node written as without the refusal; bad as read
		eq(Rules.connsText(G.configs[bad].laneConnections), before, tag .. ": bad not written")
		local got, wantNoBad = {}, {}
		for _, l in ipairs(configs(G)) do if not l:find("^" .. bad .. " ") then got[#got + 1] = l end end
		for _, l in ipairs(want) do if not l:find("^" .. bad .. " ") then wantNoBad[#wantNoBad + 1] = l end end
		eq(got, wantNoBad, tag .. ": the other nodes as without the refusal")
		local w = G.kinds("WRITE")
		eq(#w, 1, tag .. ": one WRITE line, after the retries")
		ok(w[1]:find("kind=slip job=1 nodes=", 1, true) and w[1]:find(" success=false", 1, true), w[1])
		ok(w[1]:find(" retry=" .. retried .. " retry_ok=" .. (retried - 1), 1, true), w[1])
		-- the verify covers the retried nodes that landed (not bad)
		local v = G.kinds("VERIFY")
		ok(#v >= 1 and not v[1]:find(tostring(bad), 1, true), v[1])
		eq(#G.kinds("ERROR"), 0, tag)
		-- bad is released: the next build of it is handled (and lands once the engine takes it)
		G.refuse = nil
		local n0 = #G.sent
		build(G, { bad })
		frames(G, 200)
		ok(#G.sent > n0, tag .. ": bad written by the next job")
		eq(Rules.connsText(G.configs[bad].laneConnections) ~= before, true, tag .. ": bad written now")
	end
end)

test("frames: a refused single-entry part is not retried (it is the bad entry itself)", function()
	local seeds = { 900000 + 2 * 13 + 4 }
	local G = gridGame({ sqrl_free_turn = 2 })
	G.refuse = function() return true end
	build(G, seeds)
	frames(G, 100)
	eq(#G.sent, 1)
	eq(#G.kinds("RETRY"), 0)
	local w = G.kinds("WRITE")[1]
	ok(w:find(" success=false", 1, true) and not w:find("retry=", 1, true), w)
	eq(#G.kinds("ERROR"), 0)
end)

--- 10 crossroads inside the grid (not on the probe ring) and the predicate "the proposal names bad".
local function tenCross()
	local seeds = {}
	for j = 1, 10 do seeds[#seeds + 1] = 900000 + 2 * 13 + j end
	local bad = seeds[4]
	local function hasBad(cmd)
		for _, n in ipairs(cmd.proposal.streetProposal.nodeConfigsToRemove) do
			if n == bad then return true end
		end
		return false
	end
	return seeds, bad, hasBad
end

test("frames: a slip part whose callback never comes times out: TIMEOUT line, WRITE timeout=, verify of what landed, a late callback ignored", function()
	local seeds, bad, hasBad = tenCross()
	local G = gridGame({ sqrl_free_turn = 2 }, { clock = true })
	local lostNodes = nil
	G.lose = function(cmd)
		if not hasBad(cmd) then return false end
		lostNodes = {}
		for _, n in ipairs(cmd.proposal.streetProposal.nodeConfigsToRemove) do lostNodes[n] = true end
		return true
	end
	build(G, seeds)
	frames(G, 200)
	ok(lostNodes ~= nil, "the part with bad went out")
	local nLost = 0
	for _ in pairs(lostNodes) do nLost = nLost + 1 end
	ok(#G.sent > 1, "more than one part (" .. #G.sent .. ")")
	eq(#G.kinds("SUMMARY"), 1, "the job's steps are done")
	eq(#G.kinds("WRITE"), 0, "WRITE waits for the lost part")
	eq(#G.kinds("TIMEOUT"), 0)
	-- the lost part's nodes are held meanwhile: a build of bad waits
	G.lose = nil
	build(G, { bad })
	frames(G, 100)
	eq(#G.kinds("SUMMARY"), 1, "job 2 waits for the held node")
	frames(G, 400)
	local t = G.kinds("TIMEOUT")
	eq(#t, 1, table.concat(t, "\n"))
	ok(t[1]:find("TIMEOUT kind=slip job=1 parts=1 retries=0 entries=" .. nLost, 1, true), t[1])
	local w = G.kinds("WRITE")
	ok(#w >= 1 and w[1]:find("kind=slip job=1 nodes=", 1, true), w[1])
	ok(w[1]:find(" success=false", 1, true) and w[1]:find(" timeout=" .. nLost, 1, true), w[1])
	-- the verify covers only the parts that landed
	local v = G.kinds("VERIFY")[1]
	ok(v ~= nil and v:find("kind=slip job=1 ", 1, true), tostring(v))
	local same, total = v:match("same=(%d+) nodes=(%d+)")
	eq(tonumber(total), 10 - nLost, v)
	eq(same, total, v)
	-- the nodes are released: job 2 ran and wrote bad
	frames(G, 100)
	eq(#G.kinds("SUMMARY"), 2, "job 2 ran once the part timed out")
	ok(G.kinds("SUMMARY")[2]:find("SUMMARY job=2 ", 1, true), G.kinds("SUMMARY")[2])
	local nW = #G.kinds("WRITE")
	-- the lost callback arrives late: logged, nothing counted or released twice
	for _, f in ipairs(G.lost) do f() end
	frames(G, 50)
	local late = G.kinds("LATE")
	eq(#late, 1, table.concat(late, "\n"))
	ok(late[1]:find("LATE kind=slip job=1 nodes=" .. nLost .. " success=true", 1, true), late[1])
	eq(#G.kinds("WRITE"), nW, "no second WRITE")
	eq(#G.kinds("TIMEOUT"), 1)
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
	-- holds stay consistent: a later build of the lost nodes is handled at once (nothing held)
	local some = {}
	for n in pairs(lostNodes) do if n ~= bad then some[#some + 1] = n end end
	if #some > 0 then
		build(G, some)
		frames(G, 40)
		eq(#G.kinds("SUMMARY"), 3, "job 3 not held")
	end
end)

test("frames: a retry whose callback never comes times out (RETRY result=timeout); the WRITE line counts it; a late callback ignored", function()
	local seeds, bad, hasBad = tenCross()
	local G = gridGame({ sqrl_free_turn = 2 })
	G.refuse = hasBad
	-- the retry of bad alone (a single-entry proposal) never answers
	G.lose = function(cmd)
		return hasBad(cmd) and #cmd.proposal.streetProposal.nodeConfigsToRemove == 1
	end
	build(G, seeds)
	frames(G, 200)
	eq(#G.kinds("RETRY"), 9, "the other entries' retries answered")
	eq(#G.kinds("WRITE"), 0, "WRITE waits for the lost retry")
	eq(#G.lost, 1)
	frames(G, 500)
	local t = G.kinds("TIMEOUT")
	eq(#t, 1, table.concat(t, "\n"))
	ok(t[1]:find("TIMEOUT kind=slip job=1 parts=0 retries=1 entries=1", 1, true), t[1])
	local r = G.kinds("RETRY")
	eq(#r, 10)
	ok(r[10]:find("node=" .. bad .. " result=timeout", 1, true), r[10])
	local w = G.kinds("WRITE")
	eq(#w, 1)
	ok(w[1]:find(" retry=10 retry_ok=9 timeout=1", 1, true), w[1])
	local v = G.kinds("VERIFY")[1]
	ok(v ~= nil and not v:find(tostring(bad), 1, true), tostring(v))
	-- late answer: one LATE line, no RETRY / WRITE again
	G.lost[1]()
	frames(G, 20)
	eq(#G.kinds("LATE"), 1)
	ok(G.kinds("LATE")[1]:find("LATE kind=slip job=1 nodes=1 success=false", 1, true), G.kinds("LATE")[1])
	eq(#G.kinds("RETRY"), 10)
	eq(#G.kinds("WRITE"), 1)
	eq(#G.kinds("ERROR"), 0, table.concat(G.kinds("ERROR"), "\n"))
	-- bad is released: the next job writes it
	G.refuse, G.lose = nil, nil
	local n0 = #G.sent
	build(G, { bad })
	frames(G, 100)
	ok(#G.sent > n0, "bad written by the next job")
end)
