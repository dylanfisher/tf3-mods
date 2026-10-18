-- square_smart_lanes rev 7 "Reset sticks" (PLAN.md): sl_kept.lua pure helpers, the SmartLanes.kept event in
-- sl_lanes.script.lua's handleEvent, and the automatic pass leaving kept nodes alone (the tool side is in
-- test_tool.lua "kept (tool)").

local Kept = ug_require "square_smart_lanes::/smart_lanes/sl_kept.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

---------------------------------------------------------------------------
-- sl_kept.lua

test("validate: add / remove with {n, x, y} entries; src tool by default; fresh copies", function()
	local op, nodes, src = Kept.validate({ op = "add", nodes = { { 5, 1.5, -2 }, { n = 7, x = 3, y = 4 } }, junk = 1 })
	eq(op, "add")
	eq(nodes, { { 5, 1.5, -2 }, { 7, 3, 4 } })
	eq(src, "tool")
	eq({ Kept.validate({ op = "remove", nodes = { { 0, 0, 0 } }, src = "prune" }) }, { "remove", { { 0, 0, 0 } }, "prune" })
	eq(select(3, Kept.validate({ op = "add", nodes = { { 1, 0, 0 } }, src = "auto" })), "auto")
end)

test("validate: anything malformed refuses the whole event (types, op, src, count, ids, coordinates)", function()
	local many = {}
	for i = 1, Kept.EVENT_MAX + 1 do many[i] = { i, i, 0 } end
	local cap = {}
	for i = 1, Kept.EVENT_MAX do cap[i] = { i, i, 0 } end
	local bad = {
		{ "x", "not_table" },
		{ { op = "set", nodes = { { 1, 0, 0 } } }, "op" },
		{ { nodes = { { 1, 0, 0 } } }, "op" },
		{ { op = "add", src = "gui", nodes = { { 1, 0, 0 } } }, "src" },
		{ { op = "add", src = 3, nodes = { { 1, 0, 0 } } }, "src" },
		{ { op = "add" }, "nodes" },
		{ { op = "add", nodes = "1" }, "nodes" },
		{ { op = "add", nodes = {} }, "empty" },
		{ { op = "add", nodes = many }, "too_many" },
		{ { op = "add", nodes = { { 1, 0, 0 }, "x" } }, "node2" },
		{ { op = "add", nodes = { { -1, 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1.5, 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { "1", 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 0 / 0, 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1, 0 / 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1, 0, math.huge } } }, "node1" },
		{ { op = "add", nodes = { { 1, 2e6, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1, 0 } } }, "node1" },
	}
	for i, b in ipairs(bad) do
		eq({ Kept.validate(b[1]) }, { nil, b[2] }, "case " .. i)
	end
	eq(Kept.validate({ op = "add", nodes = cap }), "add", "exactly EVENT_MAX nodes pass")
end)

test("apply: add (no duplicates: id or spot, moved to the end), remove by id or position, input unchanged", function()
	local list = { { 1, 0, 0 }, { 2, 10, 0 } }
	local out, st = Kept.apply(list, "add", { { 3, 20, 0 } })
	eq(out, { { 1, 0, 0 }, { 2, 10, 0 }, { 3, 20, 0 } })
	eq(st, { added = 1, removed = 0, dropped = 0 })
	eq(#list, 2, "the input list is not changed")
	-- the same spot under another id (a rebuilt node): one entry, the new id, at the end
	out = Kept.apply(out, "add", { { 9, 0.6, 0.6 } })
	eq(out, { { 2, 10, 0 }, { 3, 20, 0 }, { 9, 0.6, 0.6 } })
	-- the same id at another spot: one entry
	out = Kept.apply(out, "add", { { 2, 50, 50 } })
	eq(out, { { 3, 20, 0 }, { 9, 0.6, 0.6 }, { 2, 50, 50 } })
	-- remove: by id (anywhere) and by position (any id)
	local r, rs = Kept.apply(out, "remove", { { 2, 999, 999 }, { 777, 20.5, 0.5 } })
	eq(r, { { 9, 0.6, 0.6 } })
	eq(rs.removed, 2)
	-- just outside 1 m: no match
	local r2, rs2 = Kept.apply(r, "remove", { { 777, 1.4, 1.4 } })
	eq(r2, r)
	eq(rs2.removed, 0)
	-- malformed saved entries are dropped, nil-safe
	eq(Kept.apply({ "x", { 1 }, { 4, 1, 1 } }, "remove", {}), { { 4, 1, 1 } })
	eq(Kept.apply(nil, "add", { { 1, 2, 3 } }), { { 1, 2, 3 } })
end)

test("apply: the cap keeps the newest Kept.MAX entries (the oldest dropped)", function()
	local list = {}
	for i = 1, Kept.MAX do list[i] = { i, i * 10, 0 } end
	local add = {}
	for i = 1, 5 do add[i] = { Kept.MAX + i, -i * 10, 0 } end
	local out, st = Kept.apply(list, "add", add)
	eq(#out, Kept.MAX)
	eq(st.dropped, 5)
	eq(out[1], { 6, 60, 0 }, "entries 1-5 dropped")
	eq(out[#out], { Kept.MAX + 5, -50, 0 })
end)

test("index / match: by id first, else the nearest entry within 1 m (across grid cells); nil-safe", function()
	local idx = Kept.index({ { 1, 0, 0 }, { 2, 1.9, 0 }, { 3, -0.9, -0.9 }, "junk" })
	eq(idx.n, 3)
	eq(Kept.match(idx, 2, 500, 500), { 2, 1.9, 0 }, "id wins, wherever the node is")
	eq(Kept.match(idx, 99, 0.2, 0), { 1, 0, 0 })
	eq(Kept.match(idx, 99, 1.2, 0), { 2, 1.9, 0 }, "the nearest of two within 1 m")
	eq(Kept.match(idx, 99, -0.5, -1.2), { 3, -0.9, -0.9 }, "a neighbouring cell")
	eq(Kept.match(idx, 99, 0, 1.01), nil)
	eq(Kept.match(idx, 99, nil, nil), nil)
	eq(Kept.match(Kept.index(nil), 1, 0, 0), nil)
	eq(Kept.match(nil, 1, 0, 0), nil)
	eq(Kept.match(idx, nil, 0 / 0, 0), nil)
end)

test("payloads: one event per EVENT_MAX nodes", function()
	local nodes = {}
	for i = 1, Kept.EVENT_MAX * 2 + 1 do nodes[i] = { i, 0, 0 } end
	local p = Kept.payloads("add", nodes, "tool")
	eq(#p, 3)
	eq(#p[1].nodes, Kept.EVENT_MAX)
	eq(#p[3].nodes, 1)
	eq(p[2].op, "add")
	eq(p[2].src, "tool")
	eq(Kept.payloads("remove", {}, "tool"), {})
end)

test("readSaved: kseq and the list (state_native, else the state copy); the list only when kseq changed; never throws", function()
	eq({ Kept.readSaved({}) }, { nil, nil })
	local saved = { kseq = 3, kept = { { 1, 2, 3 } } }
	local finds = {}
	local native = true
	local api = { type = { ComponentType = { GAME_SCRIPT = "GS" } }, engine = {
		system = { gameScriptSystem = { getEntityForGameScript = function() return 5 end } },
		getComponent = function()
			if not native then return { state = saved } end
			return { state_native = { find = function(_, k)
				finds[#finds + 1] = k
				local v = saved[k]
				if type(v) == "table" then return { asTable = function() return v end } end
				return v
			end } }
		end } }
	eq({ Kept.readSaved(api, nil) }, { 3, { { 1, 2, 3 } } })
	finds = {}
	eq({ Kept.readSaved(api, 3) }, { 3, nil }, "unchanged: the list is not read")
	eq(finds, { "kseq" })
	saved = {}
	eq({ Kept.readSaved(api, 3) }, { nil, {} }, "nothing saved yet")
	native = false
	saved = { kseq = 4, kept = { { 7, 0, 0 } } }
	eq({ Kept.readSaved(api, 3) }, { 4, { { 7, 0, 0 } } }, "the state copy")
	eq({ Kept.readSaved(api, 4) }, { 4, nil })
	api.engine.system.gameScriptSystem.getEntityForGameScript = function() return -1 end
	eq({ Kept.readSaved(api, 4) }, { nil, nil })
end)

---------------------------------------------------------------------------
-- sl_lanes.script.lua: the event and the automatic pass

--- The probe ring, a Channelized Junction T (nodes 1-7) and a two-way crossroads (node 901, segments 911-914).
local FX = {
	world = function()
		local w = F.merge(F.PROBE_4LANE_MEDIUM.world(), F.channelT())
		local nodes = { [901] = { 0, -800 }, [902] = { -60, -800 }, [903] = { 60, -800 }, [904] = { 0, -740 }, [905] = { 0, -860 } }
		local segs = { [911] = { 901, 902, F.TPL.medium }, [912] = { 901, 903, F.TPL.medium }, [913] = { 901, 904, F.TPL.medium },
			[914] = { 901, 905, F.TPL.medium } }
		return F.merge(w, F.build(nodes, segs))
	end,
	conns = F.PROBE_4LANE_MEDIUM.conns,
}

--- onPostBuildProposal param: the given nodes added with every segment at them.
local function build(G, nodes)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	local seen = {}
	for _, n in ipairs(nodes) do
		sp.addedNodes[#sp.addedNodes + 1] = { entity = n }
		for _, sid in ipairs(G.world.nodes[n].segs) do
			if not seen[sid] then
				seen[sid] = true
				local s = G.world.segs[sid]
				sp.addedSegments[#sp.addedSegments + 1] = { entity = sid, comp = { node0 = s.node0, node1 = s.node1 } }
			end
		end
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end
local RING = { 22768, 23292, 23293, 23294 }
local CHANNEL = { 1, 2, 3, 4, 5, 6, 7 }

--- A game whose GUI-side events (makeScriptingSendEventCmd) reach handleEvent at once, as the engine would a
-- tick later; G.events keeps them.
local function game(params)
	local G = makeGame(params, FX)
	G.events = {}
	G.api.cmd.makeScriptingSendEventCmd = function(_, id, name, param) return { event = { id = id, name = name, param = param } } end
	local send = G.api.cmd.sendCommand
	G.api.cmd.sendCommand = function(cmd, cb)
		if cmd.event ~= nil then
			G.events[#G.events + 1] = cmd.event
			G.gs.handleEvent({}, G.state, "", cmd.event.id, cmd.event.name, cmd.event.param)
			return
		end
		return send(cmd, cb)
	end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G
end

local function keptEvent(G, payload)
	return G.gs.handleEvent({}, G.state, "", Kept.EVENT_ID, Kept.EV_KEPT, payload)
end
local function at(G, n) return { n, G.world.nodes[n].x, G.world.nodes[n].y } end
local function written(G)
	local set = {}
	for _, cmd in ipairs(G.sent) do
		for _, e in ipairs(cmd.proposal.streetProposal.nodeConfigsToAdd or {}) do set[e.entity] = true end
	end
	return set
end

test("event: add / remove stored in the saved state (kept, kseq), KEPT lines; a remove of nothing writes nothing", function()
	local G = game()
	keptEvent(G, { op = "add", nodes = { at(G, 901) } })
	local s = G.state:get()
	eq(s.kept, { at(G, 901) })
	eq(s.kseq, 1)
	eq(G.kinds("KEPT"), { "[SQRL] KEPT op=add n=1 total=1 src=tool" })
	keptEvent(G, { op = "remove", nodes = { { 5555, 1000, 1000 } }, src = "tool" })
	eq(G.state:get().kseq, 1, "nothing matched: no change")
	eq(#G.kinds("KEPT"), 1)
	keptEvent(G, { op = "remove", nodes = { { 777, G.world.nodes[901].x + 0.5, G.world.nodes[901].y } } })
	s = G.state:get()
	eq(s.kept, nil, "the last entry gone: no list")
	eq(s.kseq, 2)
	eq(G.kinds("KEPT")[2], "[SQRL] KEPT op=remove n=1 total=0 src=tool")
	eq(#G.kinds("ERROR"), 0)
end)

test("event: malformed payloads are ignored as a whole (state unchanged, one line each, capped at 20)", function()
	local G = game()
	keptEvent(G, { op = "add", nodes = { { 1, 0, 0 }, { -3, 0, 0 } } })
	keptEvent(G, { op = "clear" })
	keptEvent(G, "x")
	eq(G.state:get(), nil)
	eq(G.kinds("KEPT"), { "[SQRL] KEPT op=ignored reason=node2", "[SQRL] KEPT op=ignored reason=op",
		"[SQRL] KEPT op=ignored reason=not_table" })
	for _ = 1, 30 do keptEvent(G, 7) end
	eq(#G.kinds("KEPT"), 20)
end)

test("event: the cap drops the oldest entries (KEPT op=dropped)", function()
	local G = game()
	local list = {}
	for i = 1, Kept.MAX do list[i] = { 100000 + i, i * 3, 5000 } end
	G.state:set({ kept = list, kseq = 7 })
	keptEvent(G, { op = "add", nodes = { { 1, 0, 0 }, { 2, 0, 50 } } })
	local s = G.state:get()
	eq(#s.kept, Kept.MAX)
	eq(s.kept[1][1], 100003)
	eq(s.kseq, 8)
	eq(G.kinds("KEPT")[2], "[SQRL] KEPT op=dropped n=2 total=" .. Kept.MAX)
end)

test("event: Apply automatically Off still stores it; the map editor ignores it", function()
	local G = game({ sqrl_auto = 2 })
	eq(G.state.subs, { "SmartLanes.zones", "SmartLanes.kept", "SmartLanes.auto", "onPostBuildProposal" })
	keptEvent(G, { op = "add", nodes = { { 1, 0, 0 } } })
	eq(G.state:get().kseq, 1)
	local M = makeGame(nil, FX)
	M.api.engine.config.getModParams = function() return { square_smart_lanes = {}, [""] = { isMapEditor = true } } end
	M.gs.update({}, M.state, 0.1)
	keptEvent(M, { op = "add", nodes = { { 1, 0, 0 } } })
	eq(M.state:get(), nil)
	eq(#M.kinds("KEPT"), 0)
end)

test("automatic pass: a kept crossroads is left alone (SKIP kind=kept reason=reset_kept); after a remove it gets smart lanes", function()
	local base = game()
	base.gs.handleEvent({}, base.state, "", "apply_command", "onPostBuildProposal", build(base, { 901 }))
	base.frames(40)
	ok(written(base)[901], "control: written without a mark")
	local G = game()
	keptEvent(G, { op = "add", nodes = { at(G, 901) } })
	G.frames(6)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, { 901 }))
	G.frames(40)
	eq(#G.sent, 0, "nothing written")
	eq(G.lightCmds, nil)
	eq(#G.kinds("APPLY"), 0)
	ok(G.kinds("SKIP")[1] == "[SQRL] SKIP kind=kept job=1 nodes=1 reason=reset_kept", tostring(G.kinds("SKIP")[1]))
	local sum = G.kinds("SUMMARY")[1]
	ok(sum ~= nil and sum:find("skips=reset_kept:1", 1, true), tostring(sum))
	-- Apply clears the mark (the tool's remove event): the next build writes smart lanes again
	keptEvent(G, { op = "remove", nodes = { at(G, 901) } })
	G.frames(6)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, { 901 }))
	G.frames(40)
	ok(written(G)[901], "written after the remove")
	eq(#G.kinds("ERROR"), 0)
end)

test("automatic pass: a kept slip node is left alone, the other nodes of the build get their rule", function()
	local base = game()
	base.gs.handleEvent({}, base.state, "", "apply_command", "onPostBuildProposal", build(base, CHANNEL))
	base.frames(40)
	ok(written(base)[2] and written(base)[3], "control: slip nodes 2 and 3 written")
	local G = game()
	keptEvent(G, { op = "add", nodes = { at(G, 2) } })
	G.frames(6)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, CHANNEL))
	G.frames(40)
	local w = written(G)
	eq(w[2], nil, "the kept slip node")
	ok(w[3], "the other slip node")
	eq(G.kinds("SKIP")[1], "[SQRL] SKIP kind=kept job=1 nodes=1 reason=reset_kept")
	for _, l in ipairs(G.kinds("APPLY")) do ok(not l:find("node=2 ", 1, true), l) end
	eq(#G.kinds("ERROR"), 0)
end)

test("automatic pass: a ring with one kept junction is left alone as a whole (SKIP ring= reason=reset_kept)", function()
	local base = game()
	base.gs.handleEvent({}, base.state, "", "apply_command", "onPostBuildProposal", build(base, { 22768 }))
	base.frames(40)
	eq(#base.sent, 1, "control: the whole ring written from one arm")
	-- the kept junction is not in the build: the ring through the built arm is skipped
	local G = game()
	keptEvent(G, { op = "add", nodes = { at(G, 23293) } })
	G.frames(6)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, { 22768 }))
	G.frames(40)
	eq(#G.sent, 0)
	eq(G.lightCmds, nil)
	local skip = G.kinds("SKIP")
	eq(#skip, 1)
	ok(skip[1]:find("node=22768 reason=reset_kept", 1, true) and skip[1]:find("ring=", 1, true), skip[1])
	-- the kept junction itself in the build: filtered, and the ring of the others skipped too
	local G2 = game()
	keptEvent(G2, { op = "add", nodes = { at(G2, 23292) } })
	G2.frames(6)
	G2.gs.handleEvent({}, G2.state, "", "apply_command", "onPostBuildProposal", build(G2, RING))
	G2.frames(40)
	eq(#G2.sent, 0)
	ok(G2.kinds("SKIP")[1] == "[SQRL] SKIP kind=kept job=1 nodes=1 reason=reset_kept", G2.kinds("SKIP")[1])
	ok(G2.kinds("SKIP")[2]:find("reason=reset_kept", 1, true), G2.kinds("SKIP")[2])
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR"), 0)
end)

test("automatic pass: a kept spot under a new node id is matched by position and the entry moves to the new id", function()
	local G = game()
	local p = G.world.nodes[901]
	keptEvent(G, { op = "add", nodes = { { 424242, p.x + 0.3, p.y - 0.3 } } })
	G.frames(6)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, { 901 }))
	G.frames(40)
	eq(#G.sent, 0, "the replaced junction stays the game's")
	eq(#G.events, 1)
	eq(G.events[1].param, { op = "add", nodes = { at(G, 901) }, src = "auto" })
	eq(G.state:get().kept, { at(G, 901) })
	ok(G.kinds("KEPT")[2]:find("op=add n=1 total=1 src=auto", 1, true), G.kinds("KEPT")[2])
end)

test("load: the mirror is read once, entries whose node is gone are pruned (src=prune); Apply automatically Off: none", function()
	local G = game()
	keptEvent(G, { op = "add", nodes = { at(G, 901), { 123456, 5000, 5000 }, at(G, 2) } })
	local G2 = makeGame(nil, FX)
	G2.state = G.state
	G2.events = {}
	G2.api.cmd.makeScriptingSendEventCmd = G.api.cmd.makeScriptingSendEventCmd
	local send = G2.api.cmd.sendCommand
	G2.api.cmd.sendCommand = function(cmd, cb)
		if cmd.event ~= nil then
			G2.events[#G2.events + 1] = cmd.event
			G2.gs.handleEvent({}, G2.state, "", cmd.event.id, cmd.event.name, cmd.event.param)
			return
		end
		return send(cmd, cb)
	end
	G2.gs.update({}, G2.state, 0.1)
	G2.frames(1)
	eq(#G2.events, 1)
	eq(G2.events[1].param, { op = "remove", nodes = { { 123456, 5000, 5000 } }, src = "prune" })
	eq(G2.state:get().kept, { at(G2, 901), at(G2, 2) })
	-- the reloaded game still leaves the kept crossroads alone
	G2.frames(6)
	G2.gs.handleEvent({}, G2.state, "", "apply_command", "onPostBuildProposal", build(G2, { 901 }))
	G2.frames(40)
	eq(#G2.sent, 0)
	-- Apply automatically Off: nothing pruned
	local G3 = makeGame({ sqrl_auto = 2 }, FX)
	G3.state = G2.state
	G3.api.cmd.makeScriptingSendEventCmd = function() error("must not send") end
	G3.gs.update({}, G3.state, 0.1)
	G3.frames(3)
	eq(#G3.kinds("ERROR"), 0)
	eq(#G2.kinds("ERROR"), 0)
end)

test("save safety: builds, an Apply's remove of an unkept node: the state never gets kept / kseq", function()
	local G = game()
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, { 901 }))
	G.frames(40)
	keptEvent(G, { op = "remove", nodes = { at(G, 901) } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", build(G, RING))
	G.frames(40)
	local s = G.state:get()
	eq(s.kept, nil)
	eq(s.kseq, nil)
	eq(#G.kinds("KEPT"), 0)
	eq(#G.events, 0)
end)
