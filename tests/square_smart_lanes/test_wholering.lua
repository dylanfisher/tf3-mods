-- square_smart_lanes: whole rings in the automatic pass (sl_rules M.autoSeeds / M.ringForm, sl_lanes.script.lua
-- ringStep; PLAN.md "Whole rings in the automatic pass"). A ring a build touches is planned whole, so its final
-- lanes do not depend on the order its arms were built in; a junction the build did not touch that was edited by
-- hand (neither Smart Lanes' lanes nor the engine's) keeps the ring at the build's seeds, as before.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

F.TPL.one_way3 = "BS FV FV FV FS" -- a 3-lane one-way ring street
local RING_TPL = { [2] = "one_way_small", [3] = "one_way3", [4] = "one_way_medium" }

--- A ring of R lanes with nArms arms of template armTpl; o = { dir, mirror }.
local function ringWorld(R, armTpl, nArms, o)
	local arms = {}
	for k = 1, nArms do arms[k] = { tpl = armTpl } end
	return F.ring({ ringTpl = RING_TPL[R], arms = arms, dir = o and o.dir, mirror = o and o.mirror })
end

--- The arm junction views of the ring, in ring order.
local function armViews(W, ring)
	local out = {}
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(W, ring, n)
		if v.kind == "arm" then out[#out + 1] = v end
	end
	return out
end

--- A tiny "game" over world W: configs[node] = current connections (the engine default model at first, as after
-- the ring was built with the mod off), build(seedList) = a build that rebuilds those junctions (the engine
-- regenerates their defaults) followed by the automatic pass for the ring (autoSeeds + planRing, the apply
-- nodes written). Returns the game; game.last = the last { auto, plan }.
local function sim(W)
	local ring = assert(Ring.findRing(W, W.slots and W.slots[1].id or 1))
	local g = { W = W, ring = ring, configs = {} }
	for _, v in ipairs(armViews(W, ring)) do g.configs[v.node] = Rules.engineDefault(v) end
	local function cur(n) return g.configs[n] or {} end
	function g.build(list)
		local seeds = {}
		for _, n in ipairs(list) do
			seeds[n] = true
			local v = Ring.nodeView(W, ring, n)
			if v.kind == "arm" then g.configs[n] = Rules.engineDefault(v) end
		end
		local auto = Rules.autoSeeds(W, ring, seeds, cur)
		local plan = Rules.planRing(W, ring, auto.seeds, "two_lane", cur)
		for _, r in ipairs(plan.nodes) do
			if r.status == "apply" then g.configs[r.node] = r.conns end
		end
		g.last = { auto = auto, plan = plan }
		return auto, plan
	end
	function g.text()
		local t = {}
		for _, v in ipairs(armViews(W, ring)) do t[#t + 1] = v.node .. "=" .. Rules.roadText(g.configs[v.node]) end
		return table.concat(t, "|")
	end
	return g
end

--- Every permutation of list (small lists only).
local function perms(list)
	if #list <= 1 then return { list } end
	local out = {}
	for i = 1, #list do
		local rest = {}
		for j = 1, #list do if j ~= i then rest[#rest + 1] = list[j] end end
		for _, p in ipairs(perms(rest)) do
			local q = { list[i] }
			for _, x in ipairs(p) do q[#q + 1] = x end
			out[#out + 1] = q
		end
	end
	return out
end

--- The expected text: every arm junction with the matched-lanes rule, turbo or not.
local function wantText(W, ring, turbo)
	local t = {}
	for _, v in ipairs(armViews(W, ring)) do
		t[#t + 1] = v.node .. "=" .. Rules.roadText(Rules.twoLaneConns(v, { turbo = turbo }))
	end
	return table.concat(t, "|")
end

---------------------------------------------------------------------------
-- Rules level

test("whole ring: 3- and 4-lane qualifying rings end turbo, 2-lane ones matched (since 2026-10-15), on every junction in every build order", function()
	for _, R in ipairs({ 2, 3, 4 }) do
		for _, dir in ipairs({ "ccw", "cw" }) do
			local W = ringWorld(R, "medium", 4, { dir = dir })
			local g0 = sim(W)
			local nodes = {}
			for _, v in ipairs(armViews(W, g0.ring)) do nodes[#nodes + 1] = v.node end
			-- a 2-lane ring with 2-lane exits: matched lanes (Rules.matchedDefault; until 2026-10-15 turbo)
			local turbo = R > 2
			local want = wantText(W, g0.ring, turbo)
			local ringPlan = Rules.ringPlan(R, armViews(W, g0.ring), true)
			eq(ringPlan.turbo, true, R .. "-lane ring qualifies")
			eq(Rules.matchedDefault(R, armViews(W, g0.ring)), not turbo, R .. "-lane ring: matched default")
			-- one arm at a time, every order
			for _, order in ipairs(perms(nodes)) do
				local g = sim(W)
				for _, n in ipairs(order) do
					local auto, plan = g.build({ n })
					eq(auto.whole, true)
					eq(plan.turbo, turbo, "turbo after building " .. n)
					eq(plan.defaultWhy, (not turbo) and "two_lane_exits" or nil)
					eq(plan.fresh, true)
					-- after any single arm, already the final layout
					eq(g.text(), want, R .. " " .. dir .. " after " .. n .. " of " .. table.concat(order, ","))
				end
			end
			-- whole ring first, then single arms; and pairs
			local g = sim(W)
			g.build(nodes)
			eq(g.text(), want)
			for _, n in ipairs(nodes) do
				g.build({ n })
				eq(g.text(), want)
			end
			g.build({ nodes[1], nodes[3] })
			eq(g.text(), want)
		end
	end
end)

test("whole ring: a ring with a narrow exit ends matched (3, 4 lanes) or spiral (2 lanes) on every junction in every build order", function()
	for _, R in ipairs({ 2, 3, 4 }) do
		-- 1-lane arms: every exit has one lane
		local W = ringWorld(R, "small", 4, { dir = "ccw" })
		local g0 = sim(W)
		local nodes = {}
		for _, v in ipairs(armViews(W, g0.ring)) do nodes[#nodes + 1] = v.node end
		local want = wantText(W, g0.ring, false)
		if R == 2 then
			-- the default spiral (PLAN.md "Default: the mid-node spiral"; no mid nodes here: sl_rspiral)
			local t = {}
			for _, v in ipairs(armViews(W, g0.ring)) do t[#t + 1] = v.node .. "=" .. Rules.roadText(Rules.variantConns(v, "sl_rspiral", { A = 4 })) end
			want = table.concat(t, "|")
		end
		for _, order in ipairs(perms(nodes)) do
			local g = sim(W)
			for _, n in ipairs(order) do
				local auto, plan = g.build({ n })
				eq(auto.whole, true)
				eq(plan.turbo, false)
				eq(plan.turboReason, "narrow_exit")
			end
			eq(g.text(), want, R .. "-lane ring, order " .. table.concat(order, ","))
		end
	end
end)

test("whole ring: a mixed ring left by the old rule (some junctions turbo, some matched) gets turbo everywhere from one arm", function()
	local W = ringWorld(4, "medium", 4, { dir = "ccw" })
	local g = sim(W)
	local views = armViews(W, g.ring)
	for i, v in ipairs(views) do g.configs[v.node] = Rules.twoLaneConns(v, { turbo = i % 2 == 0 }) end
	-- tram connections and connection order do not matter
	local v4 = views[4]
	local rev = {}
	for i = #g.configs[v4.node], 1, -1 do rev[#rev + 1] = g.configs[v4.node][i] end
	rev[#rev + 1] = Rules.conn(v4.ringIn, v4.o_in[2], v4.ringOut, v4.o_out[2], false, true)
	g.configs[v4.node] = rev
	local auto = g.build({ views[1].node })
	eq(auto.whole, true)
	eq(#auto.extra, 3)
	eq(g.text(), wantText(W, g.ring, true))
end)

test("whole ring: a 2-lane ring written turbo by an earlier version gets matched lanes everywhere from one arm (no hand_edit)", function()
	-- rings in players' saves keep turbo until a build touches them or the player presses Apply: then the whole ring
	-- is re-planned (ringForm "turbo" is one of ours), never flagged as a hand edit
	for _, dir in ipairs({ "ccw", "cw" }) do
		for _, A in ipairs({ 3, 4, 5, 6 }) do
			local W = ringWorld(2, "medium", A, { dir = dir })
			local g = sim(W)
			local views = armViews(W, g.ring)
			for _, v in ipairs(views) do g.configs[v.node] = Rules.twoLaneConns(v, { turbo = true }) end
			for _, v in ipairs(views) do eq(Rules.ringForm(v, g.configs[v.node], { A = A }), "turbo", dir .. " " .. A) end
			local auto, plan = g.build({ views[2].node })
			eq({ auto.whole, #auto.extra, #auto.handEdit }, { true, A - 1, 0 }, dir .. " " .. A)
			eq({ plan.turbo, plan.defaultWhy }, { false, "two_lane_exits" })
			eq(g.text(), wantText(W, g.ring, false), dir .. " " .. A)
			-- and the matched ring it wrote is ours too: a later one-arm build changes nothing
			for _, v in ipairs(views) do eq(Rules.ringForm(v, g.configs[v.node], { A = A }), "matched") end
			g.build({ views[1].node })
			eq(g.text(), wantText(W, g.ring, false))
		end
	end
end)

test("whole ring: Roundabout Interchange with a 2-lane off-ramp: the same layout (ramp's own lane included) in every order", function()
	for _, dir in ipairs({ "ccw", "cw" }) do
		local W = F.interchange({ dir = dir, outTpl = "highway_ramp2" })
		local g0 = sim(W)
		local nodes = {}
		for _, v in ipairs(armViews(W, g0.ring)) do nodes[#nodes + 1] = v.node end
		g0.build(nodes)
		local want = g0.text()
		-- a 2-lane ring whose exits all have 2 lanes: matched lanes since 2026-10-15 (was turbo), the ramp's own lane kept
		eq({ g0.last.plan.turbo, g0.last.plan.defaultWhy }, { false, "two_lane_exits" }, dir)
		local own = 0
		for _, r in ipairs(g0.last.plan.nodes) do if r.entry == "own_lane" then own = own + 1 end end
		eq(own, 1, "the on-ramp takes its own lane")
		for _, order in ipairs(perms(nodes)) do
			local g = sim(W)
			for _, n in ipairs(order) do g.build({ n }) end
			eq(g.text(), want, dir .. " order " .. table.concat(order, ","))
		end
	end
end)

test("ringForm: turbo, matched, own_lane, engine default and none; anything else is a hand edit", function()
	local W = ringWorld(4, "medium", 4, { dir = "ccw" })
	local ring = assert(Ring.findRing(W, 1))
	local v = armViews(W, ring)[1]
	eq(Rules.ringForm(v, Rules.twoLaneConns(v, { turbo = true })), "turbo")
	eq(Rules.ringForm(v, Rules.twoLaneConns(v, { turbo = false })), "matched")
	eq(Rules.ringForm(v, Rules.engineDefault(v)), "engine")
	eq(Rules.ringForm(v, {}), "none")
	local edited = Rules.engineDefault(v)
	table.remove(edited, 1)
	eq(Rules.ringForm(v, edited), nil)
	local extra = Rules.twoLaneConns(v, { turbo = true })
	extra[#extra + 1] = Rules.conn(v.ringIn, v.o_in[4], v.arm, v.x[1], true, false)
	eq(Rules.ringForm(v, extra), nil)
	-- the on-ramp's own-lane form
	local I = F.interchange({ outTpl = "highway_ramp2" })
	local ir = assert(Ring.findRing(I, 1))
	for _, iv in ipairs(armViews(I, ir)) do
		if #iv.x == 0 and #iv.e > 0 then eq(Rules.ringForm(iv, Rules.rampEntryConns(iv)), "own_lane") end
	end
end)

test("whole ring: a hand-edited junction the build did not touch is left alone, and the ring keeps the seeds (not_fresh)", function()
	local W = ringWorld(4, "medium", 4, { dir = "ccw" })
	local g = sim(W)
	local views = armViews(W, g.ring)
	local nodes = {}
	for _, v in ipairs(views) do nodes[#nodes + 1] = v.node end
	g.build(nodes)
	eq(g.text(), wantText(W, g.ring, true))
	-- the player removes one connection at junction 3 with the Crossing Tool
	local edited = {}
	for i, c in ipairs(g.configs[nodes[3]]) do if i > 1 then edited[#edited + 1] = c end end
	g.configs[nodes[3]] = edited
	local editedText = Rules.roadText(edited)
	local auto, plan = g.build({ nodes[1] })
	eq(auto.whole, false)
	eq(auto.handEdit, { nodes[3] })
	eq(plan.fresh, false)
	eq(plan.turbo, false)
	eq(plan.turboReason, "not_fresh")
	for _, r in ipairs(plan.nodes) do
		if r.node == nodes[1] then eq(r.status, "apply") else eq(r.status, "untouched") end
	end
	eq(Rules.roadText(g.configs[nodes[3]]), editedText, "the hand edit stays")
	eq(Rules.roadText(g.configs[nodes[1]]), Rules.roadText(Rules.twoLaneConns(views[1], { turbo = false })), "seed: matched")
	-- an original seed that is hand-edited is written as before (the build rebuilt it)
	local auto2, plan2 = g.build({ nodes[3] })
	eq(auto2.whole, true)
	eq(plan2.turbo, true)
	eq(g.text(), wantText(W, g.ring, true))
end)

test("autoSeeds: skipped and plain ring nodes are not added; a held junction makes it wait before any read", function()
	local arms = {}
	for k = 1, 4 do arms[k] = { tpl = "medium" } end
	arms[2].through = true
	local W = F.ring({ ringTpl = "one_way_small", arms = arms, extraNodes = 1 })
	local ring = assert(Ring.findRing(W, 1))
	local reads = 0
	local function cur(n)
		reads = reads + 1
		return {}
	end
	local a = Rules.autoSeeds(W, ring, { [1] = true }, cur)
	eq(a.whole, true)
	for _, n in ipairs(a.extra) do eq(Ring.nodeView(W, ring, n).kind, "arm") end
	local skipN = 0
	for _, n in ipairs(ring.nodes) do
		local k = Ring.nodeView(W, ring, n).kind
		if k ~= "arm" then ok(not a.seeds[n], "not added: " .. k) end
		if k == "skip" then skipN = skipN + 1 end
	end
	ok(skipN >= 1)
	local p = Rules.planRing(W, ring, a.seeds, "two_lane", cur)
	eq(p.turboReason, "skip_node")
	reads = 0
	local w = Rules.autoSeeds(W, ring, { [1] = true }, cur, function(n) return n == a.extra[1] end)
	eq(w.wait, a.extra[1])
	eq(reads, 0, "no read while held")
end)

---------------------------------------------------------------------------
-- The automatic pass (sl_lanes.script.lua with the fake game: the probe 4-lane ring)

local RING_NODES = { 22768, 23292, 23293, 23294 }
local RING_SEGS = { [23299] = true, [23300] = true, [23301] = true, [23302] = true }

--- A build that touches only ring junction `node` (its arm segment), as a link road or town growth at one arm.
local function oneArmBuild(G, node)
	local seg = nil
	for _, sid in ipairs(G.world.nodes[node].segs) do
		if not RING_SEGS[sid] then seg = G.world.segs[sid] end
	end
	assert(seg ~= nil)
	local sp = { addedNodes = { { entity = node } }, addedSegments = { { entity = seg.id, comp = { node0 = seg.node0, node1 = seg.node1 } } },
		nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

local function ringBuild(G)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, id in ipairs(RING_NODES) do sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
	for id in pairs(RING_SEGS) do
		local s = G.world.segs[id]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = id, comp = { node0 = s.node0, node1 = s.node1 } }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

local function ringConfigs(G)
	local t = {}
	for _, n in ipairs(RING_NODES) do t[#t + 1] = n .. "=" .. Rules.roadText(G.configs[n].laneConnections) end
	return table.concat(t, "|")
end

--- The whole-ring turbo layout of the probe ring.
local function turboText(G)
	local ring = assert(Ring.findRing(G.world, 22768))
	local t = {}
	for _, n in ipairs(RING_NODES) do
		t[#t + 1] = n .. "=" .. Rules.roadText(Rules.twoLaneConns(Ring.nodeView(G.world, ring, n), { turbo = true }))
	end
	return table.concat(t, "|")
end

local function newGame()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G
end

local function engineDefaultAt(G, n)
	local ring = assert(Ring.findRing(G.world, 22768))
	G.configs[n].laneConnections = Rules.engineDefault(Ring.nodeView(G.world, ring, n))
end

test("automatic pass: a build at one arm of an untouched ring writes the whole ring, turbo, in one proposal", function()
	local G = newGame()
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G, 23293))
	G.frames(20)
	eq(#G.sent, 1)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4)
	local rm = G.sent[1].proposal.streetProposal.nodeConfigsToRemove
	table.sort(rm)
	eq(rm, RING_NODES, "every remove with its add")
	local a = G.kinds("APPLY")
	eq(#a, 4)
	for _, l in ipairs(a) do ok(l:find(" turbo=true fresh=true ", 1, true), l) end
	eq(ringConfigs(G), turboText(G))
	-- lights only at the junction the build touched
	G.frames(40)
	local lit = {}
	for _, c in ipairs(G.lightCmds or {}) do lit[#lit + 1] = c.node end
	ok(#lit <= 1, "lights: " .. table.concat(lit, ","))
	for _, n in ipairs(lit) do eq(n, 23293) end
	eq(#G.kinds("ERROR"), 0)
end)

test("automatic pass: every order of one-arm builds ends with the same turbo ring", function()
	local want = nil
	for _, order in ipairs(perms(RING_NODES)) do
		local G = newGame()
		for _, n in ipairs(order) do
			engineDefaultAt(G, n) -- the build rebuilt that junction: the engine's defaults
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G, n))
			G.frames(20)
			want = want or turboText(G)
			eq(ringConfigs(G), want, "after " .. n .. " of " .. table.concat(order, ","))
		end
		eq(#G.kinds("ERROR"), 0)
		for _, l in ipairs(G.kinds("APPLY")) do ok(l:find(" turbo=true fresh=true ", 1, true), l) end
	end
end)

test("automatic pass: a hand-edited junction the build did not touch: SKIP reason=hand_edit, the seed matched, the edit kept", function()
	local G = newGame()
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	eq(ringConfigs(G), turboText(G))
	-- the player edits 23293 with the Crossing Tool (one connection less)
	local list = {}
	for i, c in ipairs(G.configs[23293].laneConnections) do if i > 1 then list[#list + 1] = c end end
	G.configs[23293].laneConnections = list
	local edited = Rules.roadText(list)
	local before = { [23292] = Rules.roadText(G.configs[23292].laneConnections), [23294] = Rules.roadText(G.configs[23294].laneConnections) }
	engineDefaultAt(G, 22768)
	local sent0 = #G.sent
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G, 22768))
	G.frames(20)
	eq(#G.sent, sent0 + 1)
	local sp = G.sent[#G.sent].proposal.streetProposal
	eq(sp.nodeConfigsToRemove, { 22768 })
	eq(#sp.nodeConfigsToAdd, 1)
	local skips = G.kinds("SKIP")
	eq(#skips, 1)
	ok(skips[1]:find("ring=22768 node=23293 reason=hand_edit$"), skips[1])
	local a = G.kinds("APPLY")
	ok(a[#a]:find("node=22768 .* turbo=false fresh=false "), a[#a])
	local sums = G.kinds("SUMMARY")
	ok(sums[#sums]:find(" skips=hand_edit:1 ", 1, true), sums[#sums])
	eq(Rules.roadText(G.configs[23293].laneConnections), edited, "hand edit kept")
	eq(Rules.roadText(G.configs[23292].laneConnections), before[23292])
	eq(Rules.roadText(G.configs[23294].laneConnections), before[23294])
	eq(#G.kinds("ERROR"), 0)
end)

test("automatic pass: a ring junction the job would add that our earlier proposal still names makes the job wait (WAIT), then it goes on", function()
	local G = newGame()
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	-- a hand edit at 23293, so the next build writes only its seed 22768; that proposal stays unanswered
	local list = {}
	for i, c in ipairs(G.configs[23293].laneConnections) do if i > 1 then list[#list + 1] = c end end
	G.configs[23293].laneConnections = list
	engineDefaultAt(G, 22768)
	G.defer = true
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G, 22768))
	G.frames(20)
	eq(#G.deferred, 1)
	local sent1 = #G.sent
	-- the player resets 23293 to the game's lanes; then a build at 23292: 22768 is still held
	engineDefaultAt(G, 23293)
	engineDefaultAt(G, 23292)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G, 23292))
	G.frames(30)
	eq(#G.sent, sent1, "nothing sent while 22768 is held")
	local w = G.kinds("WAIT")
	eq(#w, 1, "one WAIT line")
	ok(w[1]:find("kind=ring job=", 1, true) and w[1]:find(" ring=22768 node=22768$"), w[1])
	-- the earlier proposal lands: the job reads 22768 after it and plans the whole ring
	G.defer = false
	G.flush()
	G.frames(20)
	eq(#G.sent, sent1 + 1)
	-- 22768 (matched by the job before), 23293 and 23292 (engine defaults); 23294 is turbo already
	local add = {}
	for _, e in ipairs(G.sent[#G.sent].proposal.streetProposal.nodeConfigsToAdd) do add[#add + 1] = e.entity end
	table.sort(add)
	eq(add, { 22768, 23292, 23293 })
	eq(ringConfigs(G), turboText(G))
	eq(#G.kinds("WAIT"), 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("automatic pass: a whole ring build followed by a one-arm build changes nothing", function()
	local G = newGame()
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	local after = ringConfigs(G)
	eq(after, turboText(G))
	local sent = #G.sent
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G, 23294))
	G.frames(20)
	eq(#G.sent, sent, "already right: nothing sent")
	eq(ringConfigs(G), after)
end)
