-- square_smart_lanes "Automatic light timing" (all lights) and the first-load welcome (PLAN.md "Automatic timing for
-- all lights + first-load welcome"): sl_allmode.lua (setting / override resolution, opt-outs, the welcome's decision,
-- the existing-junctions pass's slices and caps), the SmartLanes.auto ops mode / welcome / pass and the opt-out
-- bookkeeping in sl_lanes.script.lua's handleEvent, and the existing-junctions pass through the GUI script (the
-- runtime's all-lights listing and the tool's buttons are in test_tool.lua "all lights").

local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local function has(line, text) return line ~= nil and line:find(text, 1, true) ~= nil end

---------------------------------------------------------------------------
-- Resolution

test("setting / override: Junctions I choose by default, All lights / Off from the setting, the save's amode wins", function()
	eq(AllMode.settingOf(nil), "pick")
	eq(AllMode.settingOf({}), "pick")
	eq(AllMode.settingOf({ sqrl_auto_lights = 1 }), "pick")
	eq(AllMode.settingOf({ sqrl_auto_lights = 2 }), "all")
	eq(AllMode.settingOf({ sqrl_auto_lights = 2.0 }), "all", "a double index")
	eq(AllMode.settingOf({ sqrl_auto_lights = 3 }), "off", "Off: the last value (saved indices 1 and 2 hold)")
	eq(AllMode.settingOf({ sqrl_auto_lights = 4 }), "pick", "out of range: the default")
	eq(AllMode.settingOf({ sqrl_auto_lights = 1.5 }), "pick")
	eq(AllMode.effective("pick", nil), "pick")
	eq(AllMode.effective("all", nil), "all")
	eq(AllMode.effective("pick", "all"), "all", "the welcome's Apply / Adjust all lights")
	eq(AllMode.effective("all", "pick"), "pick", "Stop for all lights")
	eq(AllMode.effective("off", nil), "off")
	eq(AllMode.effective("off", "pick"), "pick", "the save's own choice wins over Off")
	eq(AllMode.effective("all", "off"), "off")
	eq(AllMode.effective(nil, "x"), "pick", "garbage: the default")
	eq(AllMode.isMapEditor({ [""] = { isMapEditor = true } }), true)
	eq(AllMode.isMapEditor({ [""] = {} }), false)
	eq(AllMode.isMapEditor(nil), false)
end)

test("timed by hand: the flag, no record of ours, whole-second greens, Light phases not Smart Lanes", function()
	eq(AllMode.handTimed(true, { 30, 25 }, false, false), true)
	eq(AllMode.handTimed(nil, { 30, 25 }, false, false), false, "never flagged")
	eq(AllMode.handTimed(true, { 27.0945, 21.5547 }, false, false), false, "the game's greens (a freed curb turn kept them)")
	eq(AllMode.handTimed(true, { 30, 25 }, true, false), false, "Smart Lanes measured it (Re-time / Keep timing adjusted)")
	eq(AllMode.handTimed(true, { 30, 25 }, false, true), false, "Light phases Smart Lanes: its plans are whole seconds")
	eq(AllMode.handTimed(true, {}, false, false), false, "no vehicle phase")
	eq(AllMode.wholeSecond(24.004), true)
	eq(AllMode.wholeSecond(0 / 0), false)
end)

test("opt-outs: no duplicates (by id or 2 m), the oldest dropped beyond OUT_MAX; opt-in removes", function()
	local list, added, dropped = AllMode.optOut(nil, { { 5, 10, 10 }, { 6, 50, 50 } }, Auto.matches)
	eq(list, { { 5, 10, 10 }, { 6, 50, 50 } })
	eq({ added, dropped }, { 2, 0 })
	list, added = AllMode.optOut(list, { { 9, 10.5, 10 } }, Auto.matches)
	eq(added, 0, "the same spot under a new id")
	eq(list[1], { 9, 10.5, 10 })
	local removed
	list, removed = AllMode.optIn(list, { { 77, 50, 50.5 } }, Auto.matches)
	eq({ list, removed }, { { { 9, 10.5, 10 } }, 1 })
	local full = {}
	for i = 1, AllMode.OUT_MAX do full[i] = { i, i * 10, 0 } end
	list, added, dropped = AllMode.optOut(full, { { 99999, -500, -500 } }, Auto.matches)
	eq({ #list, added, dropped }, { AllMode.OUT_MAX, 1, 1 })
	eq(list[1][1], 2, "the oldest went")
	eq(list[#list][1], 99999)
end)

test("save safety: the additions stay bounded (OUT_MAX opt-outs, NEW_SAVED_MAX new lights, a mode, an answer, the pass seqs), under 45 kB", function()
	local s = { amode = "all", wel = 2, mpass = { seq = 3, done = 3 }, aout = {} }
	for i = 1, AllMode.OUT_MAX + 50 do
		s.aout = AllMode.optOut(s.aout, { { 1000000 + i, 123456.7 + i * 3, -98765.4 } }, Auto.matches)
	end
	eq(#s.aout, AllMode.OUT_MAX)
	-- the new lights' list: the latest NEW_SAVED_MAX node ids only
	for i = 1, 40 do
		local ids = {}
		for j = 1, AllMode.NEW_SEEDS_MAX + 5 do ids[j] = 1000000000 + i * 100 + j end
		s.alit = AllMode.litAdd(s.alit, ids)
	end
	eq(#s.alit.nodes, AllMode.NEW_SAVED_MAX)
	eq(s.alit.seq, 40)
	local parts = {}
	local function ser(v)
		if type(v) == "table" then
			parts[#parts + 1] = "{"
			for k, x in pairs(v) do
				parts[#parts + 1] = tostring(k) .. "="
				ser(x)
				parts[#parts + 1] = ","
			end
			parts[#parts + 1] = "}"
		else
			parts[#parts + 1] = tostring(v)
		end
	end
	ser(s)
	local size = #table.concat(parts)
	ok(size < 45000, "serialized " .. size)
end)

---------------------------------------------------------------------------
-- The welcome: asked once per save

test("welcome decision: waits, reads at the delay, shows once without an answer; answered / editor: done; unreadable: skip", function()
	local function run(readFn, frames)
		local w = AllMode.newWelcome()
		local phases, reads = {}, 0
		for _ = 1, frames do
			local p = AllMode.welcomeStep(w, function()
				reads = reads + 1
				return readFn()
			end)
			phases[#phases + 1] = p
		end
		return w, phases, reads
	end
	local D, R = AllMode.WELCOME_DELAY_FRAMES, AllMode.WELCOME_RETRY_FRAMES
	-- a save without an answer (a new game: the state holds nothing)
	local w, phases, reads = run(function() return true, nil, false end, D + 5)
	eq(phases[D - 1], "wait")
	eq(phases[D], "show")
	eq(phases[D + 1], "shown")
	eq(reads, 1, "read once")
	local shows = 0
	for _, p in ipairs(phases) do if p == "show" then shows = shows + 1 end end
	eq(shows, 1, "shown once")
	-- answered before (Apply or Not now): nothing shown
	w = run(function() return true, 1, false end, D + 5)
	eq({ w.phase, w.reason }, { "done", "answered" })
	-- the map editor: nothing shown
	w = run(function() return true, nil, true end, D + 5)
	eq({ w.phase, w.reason }, { "done", "editor" })
	-- the state readable only at the third look
	local n = 0
	w, phases, reads = run(function()
		n = n + 1
		return n >= 3, nil, false
	end, D + 3 * R)
	eq(reads, 3)
	eq(phases[D + 2 * R], "show")
	-- never readable: skip after WELCOME_TRIES reads, then no more reads
	w, phases, reads = run(function() return false end, D + (AllMode.WELCOME_TRIES + 3) * R)
	eq({ w.phase, w.reason, reads }, { "skip", "unreadable", AllMode.WELCOME_TRIES })
	-- a read that throws counts as unreadable
	w = run(function() error("boom") end, D + 1)
	eq(w.phase, "wait")
end)

local FX = { world = function()
	return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build({ [901] = { 0, 0 }, [902] = { 100, 0 }, [903] = { 0, 100 } },
		{ [1] = { 901, 902, F.TPL.medium }, [2] = { 901, 903, F.TPL.medium } }, false))
end, conns = F.PROBE_4LANE_MEDIUM.conns }

local function autoEvent(G, payload)
	return G.gs.handleEvent({}, G.state, "", Auto.EVENT_ID, Auto.EV_AUTO, payload)
end

test("welcome event: the answer stored once (wel); Apply + lights -> amode all; Apply + lanes -> the pass requested; Not now", function()
	local G = makeGame(nil, FX)
	G.gs.update({}, G.state, 0.1)
	autoEvent(G, AllMode.welcomePayload("apply", true, true))
	local s = G.state:get()
	eq({ s.wel, s.amode, s.mpass, s.aseq }, { 2, "all", { seq = 1, done = 0 }, 1 })
	eq(G.kinds("WELCOME"), { "[SQRL] WELCOME op=answer answer=apply lanes=1 lights=1 mode=all pass=1" })
	-- asked once: a second answer changes nothing
	autoEvent(G, AllMode.welcomePayload("later"))
	eq(G.state:get().wel, 2)
	eq(G.kinds("WELCOME")[2], "[SQRL] WELCOME op=ignored reason=answered answer=later")
	-- Not now: only the answer
	local L = makeGame(nil, FX)
	L.gs.update({}, L.state, 0.1)
	autoEvent(L, AllMode.welcomePayload("later", true, true))
	eq(L.state:get(), { wel = 1, aseq = 1 })
	-- Apply with only the lanes box: no mode
	local A = makeGame(nil, FX)
	A.gs.update({}, A.state, 0.1)
	autoEvent(A, AllMode.welcomePayload("apply", true, false))
	eq({ A.state:get().amode, A.state:get().mpass.seq }, { nil, 1 })
	-- malformed: ignored; the map editor: nothing stored
	autoEvent(A, { op = "welcome", answer = "maybe" })
	autoEvent(A, { op = "welcome", answer = "apply", lanes = "yes" })
	eq(A.kinds("AUTORETIME"), { "[SQRL] AUTORETIME op=ignored reason=answer", "[SQRL] AUTORETIME op=ignored reason=lanes" })
	local M = makeGame(nil, FX)
	M.api.engine.config.getModParams = function() return { square_smart_lanes = {}, [""] = { isMapEditor = true } } end
	M.gs.update({}, M.state, 0.1)
	autoEvent(M, AllMode.welcomePayload("apply", true, true))
	eq(M.state:get(), nil)
	eq(#G.kinds("ERROR") + #L.kinds("ERROR") + #A.kinds("ERROR"), 0)
end)

test("opt-outs in the handler: in all mode a tool remove opts out, a tool add opts in, src=all never enrolls an opt-out; pick: none kept", function()
	-- the setting All lights
	local G = makeGame({ sqrl_auto_lights = 2 }, FX)
	G.gs.update({}, G.state, 0.1)
	autoEvent(G, { op = "add", src = "all", nodes = { { 901, 0, 0 }, { 902, 100, 0 } } })
	autoEvent(G, { op = "remove", src = "tool", nodes = { { 902, 100, 0 } } })
	local s = G.state:get()
	eq(s.auto, { { 901, 0, 0 } })
	eq(s.aout, { { 902, 100, 0 } })
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=optout node=902 pos=100.0,0.0 src=tool optouts=1"))
	-- the listing's add of an opted-out junction (read before the opt-out landed): dropped
	local seq = s.aseq
	autoEvent(G, { op = "add", src = "all", nodes = { { 902, 100.4, 0 } } })
	eq(G.state:get().auto, { { 901, 0, 0 } })
	eq(G.state:get().aseq, seq, "nothing written")
	-- a prune (no light any more) is not an opt-out
	autoEvent(G, { op = "remove", src = "prune", nodes = { { 901, 0, 0 } } })
	eq(G.state:get().aout, { { 902, 100, 0 } })
	-- ticked by hand: enrolled, no opt-out any more
	autoEvent(G, { op = "add", src = "tool", nodes = { { 902, 100, 0 } } })
	s = G.state:get()
	eq({ s.auto, s.aout }, { { { 902, 100, 0 } }, nil })
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=optin node=902"))
	-- Junctions I choose (the default, no override): a tool remove is just a remove
	local P = makeGame(nil, FX)
	P.gs.update({}, P.state, 0.1)
	autoEvent(P, { op = "add", nodes = { { 901, 0, 0 } } })
	autoEvent(P, { op = "remove", nodes = { { 901, 0, 0 } } })
	eq(P.state:get().aout, nil)
	-- ...but the save's override (amode all) counts as All lights
	autoEvent(P, { op = "mode", mode = "all", src = "tool" })
	autoEvent(P, { op = "add", nodes = { { 901, 0, 0 } } })
	autoEvent(P, { op = "remove", nodes = { { 901, 0, 0 } } })
	eq(P.state:get().aout, { { 901, 0, 0 } })
	eq(#G.kinds("ERROR") + #P.kinds("ERROR"), 0)
end)

test("mode event: all clears the opt-outs; pick (Stop for all lights) also unenrolls every junction", function()
	local G = makeGame(nil, FX)
	G.gs.update({}, G.state, 0.1)
	autoEvent(G, { op = "mode", mode = "all", src = "tool" })
	autoEvent(G, { op = "add", nodes = { { 901, 0, 0 }, { 902, 100, 0 } } })
	autoEvent(G, { op = "remove", nodes = { { 902, 100, 0 } } })
	eq(G.state:get().aout, { { 902, 100, 0 } })
	autoEvent(G, { op = "mode", mode = "all", src = "tool" })
	local s = G.state:get()
	eq({ s.amode, s.aout, #s.auto }, { "all", nil, 1 })
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=mode mode=all src=tool unenrolled=0 optouts_cleared=1"))
	autoEvent(G, { op = "mode", mode = "pick", src = "tool" })
	s = G.state:get()
	eq({ s.amode, s.auto, s.aout }, { "pick", nil, nil })
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=mode mode=pick src=tool unenrolled=1"))
	autoEvent(G, { op = "mode", mode = "some" })
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=ignored reason=mode"))
	-- readSaved hands the extras to the GUI mirrors
	local _, _, extra = Auto.readSaved({ type = { ComponentType = { GAME_SCRIPT = "GS" } }, engine = {
		system = { gameScriptSystem = { getEntityForGameScript = function() return 5 end } },
		getComponent = function() return { state = { amode = "all", wel = 2, aout = { { 1, 2, 3 } }, mpass = { seq = 1, done = 0 } } } end } }, nil)
	eq({ extra.mode, extra.wel, extra.out, extra.pass }, { "all", 2, { { 1, 2, 3 } }, { seq = 1, done = 0 } })
end)

---------------------------------------------------------------------------
-- New lights at once (PLAN.md "New lights at once"): the rules, the saved list, the runtime's queue, the game script

test("new lights: the decision (off / optout / hand / cap / enroll)", function()
	eq(AllMode.decide("pick", false, false, false, 0, 10), "off")
	eq(AllMode.decide("all", true, false, false, 0, 10), "off", "map editor")
	eq(AllMode.decide("all", false, true, true, 10, 10), "optout")
	eq(AllMode.decide("all", false, false, true, 10, 10), "hand")
	eq(AllMode.decide("all", false, false, false, 10, 10), "cap")
	eq(AllMode.decide("all", false, false, false, 9, 10), "enroll")
	-- timed by hand from the phases: only the vehicle phases' greens count
	local kinds = function() return { "veh", "walk", "veh" } end
	local st = { { duration = 20 }, { duration = 6.3 }, { duration = 25 } }
	eq(AllMode.handTimedOf(true, st, 4, 2, kinds, false, false), true)
	eq(AllMode.handTimedOf(nil, st, 4, 2, kinds, false, false), false)
	eq(AllMode.handTimedOf(true, st, 4, 2, kinds, true, false), false, "measured by Smart Lanes")
	eq(AllMode.handTimedOf(true, { { duration = 20.4 } }, 4, 2, function() return { "veh" } end, false, false), false)
	eq(AllMode.handTimedOf(true, st, 4, 2, function() error("x") end, false, false), false)
	eq(AllMode.statesOf({ { lockedLanes = { 1, 2 }, duration = 7 } }), { { locked = { 1, 2 }, duration = 7 } })
end)

test("new lights: the saved list (seq per build, the latest kept) and what the runtime takes from it", function()
	local a, n = AllMode.litAdd(nil, { 5, 6, -1, 7.5, "x" })
	eq({ a, n }, { { seq = 1, nodes = { { 5, 1 }, { 6, 1 } } }, 2 })
	local b = AllMode.litAdd(a, { 8 })
	eq(b, { seq = 2, nodes = { { 5, 1 }, { 6, 1 }, { 8, 2 } } })
	eq(a.seq, 1, "the input is not changed")
	eq({ AllMode.litAdd(b, {}) }, { b, 0 })
	eq({ AllMode.litSince(b, 1) }, { { 8 }, 2, {} })
	eq({ AllMode.litSince(b, nil) }, { { 5, 6, 8 }, 2, {} })
	eq({ AllMode.litSince(b, 2) }, { {}, 2, {} })
	eq({ AllMode.litSince(b, math.huge) }, { {}, 2, {} }, "the first read only takes the seq")
	eq({ AllMode.litSince(nil, 3) }, { {}, nil, {} })
	-- one build: at most NEW_SEEDS_MAX
	local ids = {}
	for i = 1, AllMode.NEW_SEEDS_MAX + 9 do ids[i] = i end
	local _, m = AllMode.litAdd(nil, ids)
	eq(m, AllMode.NEW_SEEDS_MAX)
end)

test("new lights: the queue looks again NEW_RETRY_S after the first look, then gives up; a new build starts again; capped", function()
	local q = AllMode.newQueue()
	eq({ AllMode.queueAdd(q, { 1, 2, 2 }, 100) }, { 2, 0 })
	local due = AllMode.queueTake(q, 100, 1)
	eq({ #due, due[1].n, #q.items }, { 1, 1, 1 }, "at most max per take")
	eq(#AllMode.queueTake(q, 99, 10), 0, "not due yet")
	-- node 1 had no light: looked at again at +3, +10, +30, then given up
	local looks = { 100 }
	local it = due[1]
	for _ = 1, 10 do
		if not AllMode.queueRetry(q, it, looks[#looks]) then break end
		local t = it.at
		local d = AllMode.queueTake(q, t, 10)
		ok(#d >= 1)
		for _, x in ipairs(d) do if x.n == 1 then it = x end end
		looks[#looks + 1] = t
	end
	local want = { 100 }
	for _, d in ipairs(AllMode.NEW_RETRY_S) do want[#want + 1] = 100 + d end
	eq(looks, want)
	eq(#q.items, 0)
	-- a node built again while it waits starts again (due at once, the looks counted anew)
	AllMode.queueAdd(q, { 9 }, 0)
	local x = AllMode.queueTake(q, 0, 1)[1]
	AllMode.queueRetry(q, x, 0)
	eq(q.byId[9].at, AllMode.NEW_RETRY_S[1])
	AllMode.queueAdd(q, { 9 }, 1)
	eq({ q.byId[9].at, q.byId[9].tries }, { 1, 0 })
	-- the cap
	local many = {}
	for i = 1, AllMode.NEW_QUEUE_MAX + 20 do many[i] = 1000 + i end
	local added, dropped = AllMode.queueAdd(q, many, 0)
	eq(#q.items, AllMode.NEW_QUEUE_MAX)
	eq(added + dropped, AllMode.NEW_QUEUE_MAX + 20)
	AllMode.queueClear(q)
	eq(#q.items, 0)
end)

--- onPostBuildProposal param: nodes whose configs were (re)written, segments (ids) added with their end nodes.
local function buildParam(cfgNodes, segs, player)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(cfgNodes or {}) do
		sp.nodeConfigsToAdd[#sp.nodeConfigsToAdd + 1] = { entity = n }
		sp.nodeConfigsToRemove[#sp.nodeConfigsToRemove + 1] = n
	end
	for _, sg in ipairs(segs or {}) do
		sp.addedSegments[#sp.addedSegments + 1] = { entity = sg[1], comp = { node0 = sg[2], node1 = sg[3] } }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, player ~= false }
end
local function build(G, cfgNodes, segs, player)
	return G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", buildParam(cfgNodes, segs, player))
end

test("new lights (game script): in all mode a player build saves its nodes (enrolled / opted out left out), also with Apply automatically Off; pick, editor, other builds: nothing", function()
	-- All lights, Apply automatically Off: no job, the nodes saved for the runtime
	local G = makeGame({ sqrl_auto_lights = 2, sqrl_auto = 2 }, FX)
	G.gs.update({}, G.state, 0.1)
	autoEvent(G, { op = "add", src = "all", nodes = { { 901, 0, 0 } } })
	autoEvent(G, { op = "add", src = "all", nodes = { { 902, 100, 0 } } })
	autoEvent(G, { op = "remove", src = "tool", nodes = { { 902, 100, 0 } } })
	local seq = G.state:get().aseq
	-- a Crossing Tool click (config only) at 903, and a street placed by hand from 901 to 904
	build(G, { 903 })
	build(G, nil, { { 77, 901, 904 } })
	local s = G.state:get()
	eq(s.alit, { seq = 2, nodes = { { 903, 1 }, { 904, 2 } } }, "901 enrolled, 902 opted out: left out")
	eq(s.aseq, seq + 2)
	eq(s.jobs, nil, "Apply automatically Off: no lanes job")
	local q = G.kinds("AUTORETIME")
	ok(has(q[#q - 1], "op=new_lights phase=queued src=build nodes=1 segs=0 cfgs=1"), tostring(q[#q - 1]))
	ok(has(q[#q], "op=new_lights phase=queued src=build nodes=1 segs=1 cfgs=0"), tostring(q[#q]))
	-- nothing new (only enrolled / opted-out nodes) and builds of the game (not the player's): nothing written
	build(G, { 901, 902 })
	build(G, { 903 }, nil, false)
	eq(G.state:get().aseq, seq + 2)
	-- Apply automatically On: the lanes job and the new lights both
	local A = makeGame({ sqrl_auto_lights = 2 }, FX)
	A.gs.update({}, A.state, 0.1)
	build(A, nil, { { 1, 901, 902 } })
	eq({ #A.state:get().jobs, A.state:get().alit.nodes }, { 1, { { 901, 1 }, { 902, 1 } } })
	-- Junctions I choose: nothing saved for it; the save's amode all counts as All lights
	local P = makeGame(nil, FX)
	P.gs.update({}, P.state, 0.1)
	build(P, { 903 })
	eq(P.state:get() and P.state:get().alit, nil)
	autoEvent(P, { op = "mode", mode = "all", src = "tool" })
	build(P, { 903 })
	eq(P.state:get().alit.nodes, { { 903, 1 } })
	-- the map editor: nothing
	local M = makeGame(nil, FX)
	M.api.engine.config.getModParams = function()
		return { square_smart_lanes = { sqrl_auto_lights = 2 }, [""] = { isMapEditor = true } }
	end
	M.gs.update({}, M.state, 0.1)
	build(M, { 903 })
	eq(M.state:get(), nil)
	eq(#G.kinds("ERROR") + #A.kinds("ERROR") + #P.kinds("ERROR") + #M.kinds("ERROR"), 0)
end)

test("new lights (game script): onPostBuildProposal is subscribed also with Apply automatically Off (the new-lights path needs it)", function()
	local G = makeGame({ sqrl_auto_lights = 2, sqrl_auto = 2 }, FX)
	G.gs.update({}, G.state, 0.1)
	local subs = {}
	for _, n in ipairs(G.state.subs or {}) do subs[n] = true end
	ok(subs.onPostBuildProposal, "subscribed: " .. table.concat(G.state.subs or {}, ","))
	local A = makeGame({ sqrl_auto_lights = 2 }, FX)
	A.gs.update({}, A.state, 0.1)
	subs = {}
	for _, n in ipairs(A.state.subs or {}) do subs[n] = true end
	ok(subs.onPostBuildProposal, table.concat(A.state.subs or {}, ","))
end)

test("new lights get Smart lights (game script): a config-only build with Light phases = Smart Lanes and Apply automatically On saves its nodes with the phases look, enrolled ones too, without all lights; street builds, Game default, Apply Off: not", function()
	-- Light phases = Smart Lanes (mod setting), Junctions I choose, Apply automatically On
	local G = makeGame({ sqrl_light_phases = 2 }, FX)
	G.gs.update({}, G.state, 0.1)
	build(G, { 903 })
	eq(G.state:get().alit, { seq = 1, nodes = { { 903, 1, 1 } } })
	ok(has(G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")], "op=new_lights phase=queued src=build nodes=1 segs=0 cfgs=1 plan=1"),
		G.kinds("AUTORETIME")[#G.kinds("AUTORETIME")])
	-- a street build: the automatic pass's (its lane write carries the plan), no phases look; Junctions I choose: nothing
	build(G, nil, { { 77, 901, 904 } })
	eq(G.state:get().alit.seq, 1)
	-- with all lights: enrolled nodes are kept for the phases look (the runtime skips their enrollment)
	local A = makeGame({ sqrl_light_phases = 2, sqrl_auto_lights = 2 }, FX)
	A.gs.update({}, A.state, 0.1)
	autoEvent(A, { op = "add", src = "all", nodes = { { 901, 0, 0 } } })
	build(A, { 901, 903 })
	eq(A.state:get().alit.nodes, { { 901, 1, 1 }, { 903, 1, 1 } })
	-- a street build in all mode: saved without the look (as before)
	build(A, nil, { { 77, 902, 904 } })
	eq(A.state:get().alit.nodes[3], { 902, 2 })
	-- Game default: nothing (Junctions I choose); the save's in-game setting Smart Lanes (sset.phases = 2) counts
	local D = makeGame(nil, FX)
	D.gs.update({}, D.state, 0.1)
	build(D, { 903 })
	eq(D.state:get() and D.state:get().alit, nil)
	autoEvent(D, { op = "setting", key = "phases", value = 2, src = "tool" })
	build(D, { 903 })
	eq(D.state:get().alit.nodes, { { 903, 1, 1 } }, "the in-game setting")
	-- and back to Game default in game: nothing more
	autoEvent(D, { op = "setting", key = "phases", value = 1, src = "tool" })
	build(D, { 902 })
	eq(D.state:get().alit.seq, 1)
	-- Apply automatically Off: no phases look (Light phases is for junctions Smart Lanes handles)
	local O = makeGame({ sqrl_light_phases = 2, sqrl_auto = 2 }, FX)
	O.gs.update({}, O.state, 0.1)
	build(O, { 903 })
	eq(O.state:get() and O.state:get().alit, nil)
	-- an sl_phases zone with Game default: the look (the runtime decides per node)
	local Z = makeGame(nil, FX)
	Z.gs.update({}, Z.state, 0.1)
	Z.gs.handleEvent({}, Z.state, "", "square_smart_lanes", "SmartLanes.zones",
		{ op = "set", run = "r1", zones = { { x = 0, y = 100, r = 30, ab = "sl_phases" } } })
	build(Z, { 903 })
	eq(Z.state:get().alit and Z.state:get().alit.nodes, { { 903, 1, 1 } })
	eq(#G.kinds("ERROR") + #A.kinds("ERROR") + #D.kinds("ERROR") + #O.kinds("ERROR") + #Z.kinds("ERROR"), 0)
end)

test("new lights (alit): the phases look flag kept through litAdd / litSince / the queue; all lights off keeps only the flagged entries", function()
	local alit = AllMode.litAdd(nil, { 5, 6 }, true)
	alit = AllMode.litAdd(alit, { 7 })
	eq(alit.nodes, { { 5, 1, 1 }, { 6, 1, 1 }, { 7, 2 } })
	local ids, seq, plan = AllMode.litSince(alit, nil)
	eq({ ids, seq, plan }, { { 5, 6, 7 }, 2, { [5] = true, [6] = true } })
	local q = AllMode.newQueue()
	AllMode.queueAdd(q, ids, 10, plan)
	eq({ q.byId[5].plan, q.byId[7].plan }, { true, nil })
	AllMode.queueAdd(q, { 5 }, 11)
	eq(q.byId[5].plan, true, "added again without the flag: kept")
	eq(AllMode.queueKeepPlans(q), 2)
	eq(q.byId[7], nil)
	-- the saved list stays capped (3 numbers per entry at most)
	local big = nil
	for i = 1, 100 do big = AllMode.litAdd(big, { i }, i % 2 == 0) end
	eq(#big.nodes, AllMode.NEW_SAVED_MAX)
end)

test("new lights (game script): adds src=build / select only while all lights are in force, never for an opted-out junction", function()
	local G = makeGame({ sqrl_auto_lights = 2 }, FX)
	G.gs.update({}, G.state, 0.1)
	autoEvent(G, { op = "add", src = "build", nodes = { { 901, 0, 0 } } })
	autoEvent(G, { op = "add", src = "select", nodes = { { 902, 100, 0 } } })
	eq(G.state:get().auto, { { 901, 0, 0 }, { 902, 100, 0 } })
	local en = G.kinds("AUTORETIME")
	ok(has(en[#en - 1], "op=enroll node=901 pos=0.0,0.0 src=build total=1"), tostring(en[#en - 1]))
	ok(has(en[#en], "op=enroll node=902 pos=100.0,0.0 src=select total=2"), tostring(en[#en]))
	-- opted out (moved a little: matched by position)
	autoEvent(G, { op = "remove", src = "tool", nodes = { { 902, 100, 0 } } })
	autoEvent(G, { op = "add", src = "select", nodes = { { 9902, 100.5, 0 } } })
	autoEvent(G, { op = "add", src = "build", nodes = { { 902, 100, 0 } } })
	eq(G.state:get().auto, { { 901, 0, 0 } })
	-- Junctions I choose: dropped (an event sent before the switch)
	local P = makeGame(nil, FX)
	P.gs.update({}, P.state, 0.1)
	autoEvent(P, { op = "add", src = "build", nodes = { { 901, 0, 0 } } })
	autoEvent(P, { op = "add", src = "select", nodes = { { 901, 0, 0 } } })
	eq(P.state:get(), nil)
	eq(#G.kinds("ERROR") + #P.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- The existing-junctions pass: slices and caps

local function withPass(keys, fn)
	local saved = {}
	for k, v in pairs(keys) do
		saved[k] = AllMode[k]
		AllMode[k] = v
	end
	local okP, e = pcall(fn)
	for k, v in pairs(saved) do AllMode[k] = v end
	if not okP then error(e, 0) end
end

test("pass slices: at most PASS_SLICE junctions each, a visited set (duplicates scanned once), per-frame cap, the end", function()
	withPass({ PASS_SLICE = 4, PASS_SCAN_PER_FRAME = 7 }, function()
		local list = {}
		for i = 1, 30 do list[#list + 1] = i end
		list[#list + 1] = 2 -- a duplicate
		list[#list + 1] = -1 -- garbage
		local p = AllMode.newPass(1, list, "config")
		local isJ = function(n) return n % 3 == 0 end -- 10 junctions
		local slices, frames = {}, 0
		while p.phase == "scan" and frames < 100 do
			frames = frames + 1
			local s = AllMode.passStep(p, isJ, nil)
			if s ~= nil then slices[#slices + 1] = s end
		end
		eq(slices, { { 3, 6, 9, 12 }, { 15, 18, 21, 24 }, { 27, 30 } })
		eq({ p.reason, p.junctions, p.scanned, p.slices, p.capped }, { "done", 10, 32, 3, nil })
		ok(frames >= 5, "at most 7 entries a frame: " .. frames)
		eq(AllMode.passStep(p, isJ, nil), nil, "done: nothing more")
	end)
end)

test("pass caps: junctions (PASS_JUNCTIONS_MAX), list entries (PASS_LIST_MAX), the frame's clock budget; no list", function()
	withPass({ PASS_SLICE = 5, PASS_JUNCTIONS_MAX = 7, PASS_SCAN_PER_FRAME = 1000 }, function()
		local list = {}
		for i = 1, 100 do list[i] = i end
		local p = AllMode.newPass(1, list, "node")
		local got = {}
		for _ = 1, 10 do
			local s = AllMode.passStep(p, function() return true end, nil)
			if s ~= nil then got[#got + 1] = #s end
		end
		eq(got, { 5, 2 })
		eq({ p.phase, p.reason, p.capped, p.junctions }, { "done", "cap_junctions", "cap_junctions", 7 })
	end)
	withPass({ PASS_LIST_MAX = 10, PASS_SCAN_PER_FRAME = 1000 }, function()
		local list = {}
		for i = 1, 50 do list[i] = i end
		local p = AllMode.newPass(1, list, "node")
		local s = AllMode.passStep(p, function(n) return n <= 20 end, nil)
		eq(s, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
		eq({ p.reason, p.scanned }, { "cap_list", 10 })
	end)
	withPass({ PASS_SCAN_PER_FRAME = 1000, PASS_CHECK_EVERY = 4, PASS_SCAN_BUDGET_MS = 2 }, function()
		local list = {}
		for i = 1, 100 do list[i] = i end
		local p = AllMode.newPass(1, list, "node")
		local t = 0
		-- every junction test costs 0.3 ms: the budget stops the frame after the first check past 2 ms
		local s = AllMode.passStep(p, function() t = t + 0.3 return false end, function() return t end)
		eq(s, nil)
		eq(p.scanned, 8, "two checks of 4 entries: 1.2 ms, then 2.4 ms")
		eq(p.phase, "scan")
	end)
	local p = AllMode.newPass(1, nil, "none")
	eq({ p.phase, p.reason }, { "done", "no_list" })
	-- a junction test that throws counts as no junction
	local q = AllMode.newPass(1, { 1, 2 }, "node")
	eq(AllMode.passStep(q, function() error("x") end, nil), nil)
	eq({ q.phase, q.junctions }, { "done", 0 })
end)

---------------------------------------------------------------------------
-- The existing-junctions pass through the GUI script

--- G plus: scripting events routed to the game script's handleEvent, the node-config list.
local function passGame(params)
	local G = makeGame(params)
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
	G.api.engine.getEntitiesWithComponent = function(ct)
		G.listCalls = (G.listCalls or 0) + 1
		local out = {}
		if ct == "BNC" then for id in pairs(G.world.nodes) do out[#out + 1] = id end end
		table.sort(out)
		return out
	end
	G.gs.update({}, G.state, 0.1)
	return G
end

local RING = { 22768, 23292, 23293, 23294 }

test("existing-junctions pass: the welcome's Apply plans the ring whole (the build path), changes no lights, logs start / end, done once", function()
	local G = passGame()
	G.frames(3)
	autoEvent(G, AllMode.welcomePayload("apply", true, false))
	G.frames(40)
	local mp = G.kinds("MAPPASS")
	ok(has(mp[1], "op=start seq=1 src=config") and has(mp[1], "resume=0"), tostring(mp[1]))
	ok(has(mp[#mp], "op=end seq=1 reason=done slices=1 junctions=4"), tostring(mp[#mp]))
	eq(#G.kinds("APPLY"), 4, "every ring junction")
	eq(#G.sent, 1, "one proposal for the ring")
	ok(has(G.kinds("APPLY")[1], "turbo=true") or has(G.kinds("APPLY")[1], "layout="), G.kinds("APPLY")[1])
	eq(#G.kinds("LIGHTS"), 0, "no lights changed")
	-- the end went back to the state: never again
	eq(G.state:get().mpass, { seq = 1, done = 1 })
	G.frames(200)
	eq(#G.kinds("MAPPASS"), #mp)
	eq(G.listCalls, 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("existing-junctions pass: a ring with a junction edited by hand is left alone; kept junctions skipped", function()
	local G = passGame()
	-- one arm junction with lanes neither Smart Lanes' nor the game's (a Crossing Tool edit): its first connection only
	local c = G.configs[23293].laneConnections
	G.configs[23293].laneConnections = { c[1] }
	G.frames(3)
	autoEvent(G, AllMode.welcomePayload("apply", true, false))
	G.frames(40)
	eq(#G.kinds("APPLY"), 0)
	eq(#G.sent, 0)
	ok(has(G.kinds("SKIP")[1], "node=23293 reason=hand_edit"), tostring(G.kinds("SKIP")[1]))
	ok(has(G.kinds("MAPPASS")[#G.kinds("MAPPASS")], "op=end seq=1 reason=done"))
	-- a kept junction (the tool's Reset): the ring stays the game's
	local K = passGame()
	K.gs.handleEvent({}, K.state, "", "square_smart_lanes", "SmartLanes.kept", { op = "add", nodes = { { 22768, K.world.nodes[22768].x, K.world.nodes[22768].y } } })
	K.frames(10)
	autoEvent(K, AllMode.welcomePayload("apply", true, false))
	K.frames(40)
	eq(#K.kinds("APPLY"), 0)
	ok(has(table.concat(K.kinds("SKIP"), "\n"), "reason=reset_kept"))
	eq(#G.kinds("ERROR") + #K.kinds("ERROR"), 0)
end)

test("existing-junctions pass: a pass cut short runs again at the next load (resume=1); Apply automatically Off still runs it; editor never", function()
	local G = passGame()
	G.state:set({ mpass = { seq = 2, done = 1 }, wel = 2 })
	G.frames(30)
	local mp = G.kinds("MAPPASS")
	ok(has(mp[1], "op=start seq=2") and has(mp[1], "resume=1"), tostring(mp[1]))
	ok(has(mp[#mp], "op=end seq=2"), tostring(mp[#mp]))
	eq(G.state:get().mpass, { seq = 2, done = 2 })
	-- Apply automatically Off: the pass the player asked for still runs (polled every MP_POLL_OFF frames)
	local O = passGame({ sqrl_auto = 2 })
	O.frames(3)
	autoEvent(O, AllMode.welcomePayload("apply", true, false))
	O.frames(300)
	eq(#O.kinds("APPLY"), 4)
	ok(has(O.kinds("MAPPASS")[#O.kinds("MAPPASS")], "op=end"))
	-- the map editor: nothing
	local E = passGame()
	E.api.engine.config.getModParams = function() return { square_smart_lanes = {}, [""] = { isMapEditor = true } } end
	E.state:set({ mpass = { seq = 1, done = 0 } })
	E.frames(300)
	eq(#E.kinds("MAPPASS"), 0)
	eq(#G.kinds("ERROR") + #O.kinds("ERROR") + #E.kinds("ERROR"), 0)
end)

test("existing-junctions pass: the caps end it with a MAPPASS op=cap line; no list: op=end reason=no_list", function()
	withPass({ PASS_JUNCTIONS_MAX = 2, PASS_SLICE = 2 }, function()
		local G = passGame()
		G.frames(3)
		autoEvent(G, AllMode.welcomePayload("apply", true, false))
		G.frames(60)
		local mp = table.concat(G.kinds("MAPPASS"), "\n")
		ok(has(mp, "op=cap seq=1 what=junctions max=2"), mp)
		ok(has(mp, "op=end seq=1 reason=cap_junctions slices=1 junctions=2"), mp)
		eq(#G.kinds("ERROR"), 0)
	end)
	local N = passGame()
	N.api.engine.getEntitiesWithComponent = function() error("Cannot loop over this component type") end
	N.frames(3)
	autoEvent(N, AllMode.welcomePayload("apply", true, false))
	N.frames(20)
	ok(has(N.kinds("MAPPASS")[1], "src=none list=0"), tostring(N.kinds("MAPPASS")[1]))
	ok(has(N.kinds("MAPPASS")[2], "op=end seq=1 reason=no_list slices=0"), tostring(N.kinds("MAPPASS")[2]))
	eq(N.state:get().mpass.done, 1)
end)

test("wrapLine: the welcome's lines break at spaces within the columns, CJK counted double, never before closing punctuation", function()
	local function width(l)
		local w = 0
		for ch in l:gmatch("[%z\1-\127\194-\244][\128-\191]*") do w = w + ((#ch == 3 and ch:byte(1) >= 0xE3) and 2 or 1) end
		return w
	end
	local function lines(t) local r = {} for l in (t .. "\n"):gmatch("(.-)\n") do r[#r + 1] = l end return r end
	local en = "Automatic light timing gives more green to roads with more waiting cars."
	local w = AllMode.wrapLine(en, 50)
	eq(w, "Automatic light timing gives more green to roads\nwith more waiting cars.")
	eq(AllMode.wrapLine("Short line.", 50), "Short line.", "short: unchanged")
	eq(AllMode.wrapLine("a\nb", 50), "a\nb", "newlines kept")
	-- every language of the welcome: no line over 50 columns, no words lost
	local f = io.open("mods/square_smart_lanes/strings.json", "r")
	local raw = f:read("*a")
	f:close()
	for _, key in ipairs({ "To change one junction, use the Smart Lanes tool (Roads, Tools).", en }) do
		for v in raw:gmatch('"' .. key:gsub("%p", "%%%0") .. '": "([^"]*)"') do
			local out = AllMode.wrapLine(v, 50)
			for _, l in ipairs(lines(out)) do ok(width(l) <= 50, l) end
			eq((out:gsub("[\n ]", "")), (v:gsub(" ", "")), "nothing lost")
		end
	end
	local zh = "要修改单个路口，请使用 Smart Lanes 工具（道路，工具）。"
	local zw = AllMode.wrapLine(zh, 20)
	for _, l in ipairs(lines(zw)) do
		ok(width(l) <= 20, l)
		ok(not (l:sub(1, 3) == "，" or l:sub(1, 3) == "。" or l:sub(1, 3) == "）"), "no line starts with closing punctuation: " .. l)
	end
	eq((zw:gsub("[\n ]", "")), (zh:gsub(" ", "")))
	eq(AllMode.wrapLine(nil, 50), nil)
	eq(AllMode.wrapLine("x", 0), "x")
end)
