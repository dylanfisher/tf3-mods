-- square_smart_lanes rev 8 step B "Keep timing adjusted" (RETIME_PLAN.md "Step B"): sl_auto.lua (the saved list, its
-- event, intervals) and the SmartLanes.auto event in sl_lanes.script.lua's handleEvent (the runtime and the tool are in
-- test_tool.lua "keep timing adjusted").

local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

---------------------------------------------------------------------------
-- sl_auto.lua

test("validate: the ops, their default src, nodes rounded to 0.1 m, run ids; entries are {n, x, y}; last records", function()
	eq({ Auto.validate({ op = "add", nodes = { { 5, 1.04, -2.06 } } }) }, { "add", { { 5, 1, -2.1 } }, "tool", "-" })
	eq({ Auto.validate({ op = "remove", nodes = { { n = 7, x = 3, y = 4 } }, src = "prune" }) }, { "remove", { { 7, 3, 4 } }, "prune", "-" })
	eq({ Auto.validate({ op = "update", nodes = { { 7, 3, 4, 120.5, 600, 2 } } }) }, { "update", { { 7, 3, 4 } }, "auto", "-" })
	eq({ Auto.validate({ op = "now", nodes = { { 7, 3, 4 } } }) }, { "now", { { 7, 3, 4 } }, "tool", "-" })
	eq({ Auto.validate({ op = "all", run = "st-12" }) }, { "all", {}, "stress", "st-12" })
	eq({ Auto.validate({ op = "clear", run = 42 }) }, { "clear", {}, "stress", "42" })
	eq(select(3, Auto.validate({ op = "add", src = "zone", nodes = { { 1, 0, 0 } } })), "zone")
	eq(select(3, Auto.validate({ op = "add", src = "all", nodes = { { 1, 0, 0 } } })), "all")
	-- older builds' bookkeeping fields (t, e, c) are dropped
	eq(select(2, Auto.validate({ op = "add", nodes = { { 1, 0, 0, 5, 6, 1 } } })), { { 1, 0, 0 } })
	-- last-measured records: {n, x, y, t, k, c0, c1}, t and the cycles whole, k = src x 10 + outcome
	eq({ Auto.validate({ op = "last", src = "auto", nodes = { { 7, 3.04, 4, 120.4, 22, 52, 52.4 } } }) },
		{ "last", { { 7, 3, 4, 120, 22, 52, 52 } }, "auto", "-" })
	eq(select(3, Auto.validate({ op = "last", nodes = { { 7, 3, 4, 1, 11, 50, 75 } } })), "tool")
	eq(Auto.record(7, 3, 4, 99.6, "manual", "written", 50, 75), { 7, 3, 4, 100, 11, 50, 75 })
	eq(Auto.record(7, 3, 4, 99.6, "auto", "fits", 52), { 7, 3, 4, 100, 22, 52, 52 })
	eq(Auto.record(7, 3, 4, 1, "auto", "maybe", 52), nil)
	eq(Auto.recordParts({ 7, 3, 4, 100, 24, 60, 60 }), { src = "auto", out = "notwritten", t = 100, c0 = 60, c1 = 60 })
	eq(Auto.recordParts({ 7, 3, 4, 100, 15, 60, 60 }), nil, "no outcome 5")
end)

test("validate: anything malformed refuses the whole event", function()
	local many = {}
	for i = 1, Auto.EVENT_MAX + 1 do many[i] = { i, i, 0 } end
	local bad = {
		{ "x", "not_table" },
		{ { op = "set", nodes = { { 1, 0, 0 } } }, "op" },
		{ { nodes = { { 1, 0, 0 } } }, "op" },
		{ { op = "add", src = "prune", nodes = { { 1, 0, 0 } } }, "src" },
		{ { op = "remove", src = "zone", nodes = { { 1, 0, 0 } } }, "src" },
		{ { op = "update", src = "tool", nodes = { { 1, 0, 0 } } }, "src" },
		{ { op = "all", src = "zone" }, "src" },
		{ { op = "all", run = "a b" }, "run" },
		{ { op = "clear", run = string.rep("x", 41) }, "run" },
		{ { op = "add" }, "nodes" },
		{ { op = "add", nodes = {} }, "empty" },
		{ { op = "add", nodes = many }, "too_many" },
		{ { op = "add", nodes = { { 1, 0, 0 }, "x" } }, "node2" },
		{ { op = "add", nodes = { { -1, 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1.5, 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1, 0 / 0, 0 } } }, "node1" },
		{ { op = "add", nodes = { { 1, 2e6, 0 } } }, "node1" },
		{ { op = "last", src = "zone", nodes = { { 1, 0, 0, 1, 11, 50, 50 } } }, "src" },
		{ { op = "last", nodes = { { 1, 0, 0 } } }, "node1" },
		{ { op = "last", nodes = { { 1, 0, 0, -1, 11, 50, 50 } } }, "node1" },
		{ { op = "last", nodes = { { 1, 0, 0, 1, 31, 50, 50 } } }, "node1" },
		{ { op = "last", nodes = { { 1, 0, 0, 1, 11, 50, 5000 } } }, "node1" },
	}
	for i, b in ipairs(bad) do eq({ Auto.validate(b[1]) }, { nil, b[2] }, "case " .. i) end
end)

test("apply: add (no duplicates by id or position; a new id at the spot re-keys it), remove, update, the cap refuses", function()
	local list, st = Auto.apply(nil, "add", { { 1, 0, 0 }, { 2, 50, 0 } })
	eq(list, { { 1, 0, 0 }, { 2, 50, 0 } })
	eq({ st.added, st.changed }, { 2, true })
	-- the same spot under another id (the node re-created by a write): one entry, the new id
	list, st = Auto.apply(list, "add", { { 9, 1.2, 0.9 } })
	eq(list, { { 9, 1.2, 0.9 }, { 2, 50, 0 } })
	eq({ st.added, st.already, st.updated }, { 0, 1, 1 })
	list, st = Auto.apply(list, "add", { { 9, 1.2, 0.9 } })
	eq(st.changed, false, "already there: nothing to write")
	-- update: the runtime re-attached the junction (by position: the id changed again)
	list, st = Auto.apply(list, "update", { { 11, 1.2, 0.9 }, { 77, 900, 900 } })
	eq(list[1], { 11, 1.2, 0.9 })
	eq({ #list, st.updated }, { 2, 1 }, "an update never adds")
	list, st = Auto.apply(list, "update", { { 11, 1.2, 0.9 } })
	eq(st.changed, false, "the same id and position: nothing to write")
	list, st = Auto.apply(list, "remove", { { 555, 50.5, 0.5 } })
	eq(list, { { 11, 1.2, 0.9 } })
	eq(st.removed, 1)
	-- the cap: adds beyond MAX are refused, nothing old is dropped
	local full = {}
	for i = 1, Auto.MAX do full[i] = { 1000 + i, i * 10, 0 } end
	local out, s2 = Auto.apply(full, "add", { { 5, 0, 500 }, { 1001, 10, 0 } })
	eq(#out, Auto.MAX)
	eq(out[1], { 1001, 10, 0 })
	eq(#s2.refused, 1)
	eq(s2.refused[1], { 5, 0, 500 })
end)

test("index / match: by id, else the nearest entry within 2 m; posKey; nil-safe", function()
	local idx = Auto.index({ { 1, 0, 0 }, { 2, 3, 0 }, { 3, 100, 100, 5, 600, 2 } })
	eq(idx.list[3], { 3, 100, 100 }, "an older build's bookkeeping dropped")
	eq(idx.n, 3)
	eq(Auto.match(idx, 3, nil, nil)[1], 3)
	eq(Auto.match(idx, 99, 1.5, 0.5)[1], 1, "the nearer of two within 2 m")
	eq(Auto.match(idx, 99, 2.6, 0)[1], 2)
	eq(Auto.match(idx, 99, 50, 50), nil)
	eq(Auto.match(idx, 99, 101.9, 100)[1], 3)
	eq(Auto.match(nil, 1, 0, 0), nil)
	eq(Auto.match(Auto.index(nil), 1, 0, 0), nil)
	eq(Auto.posKey(1000.04, -2.06), "1000.0,-2.1")
	eq(Auto.posKey(nil, 1), "-")
end)

test("nextEvery: a write -> 10 min; fits / too little traffic -> 10, 20, 40, 60, 60 min; refused -> 10 min", function()
	eq(Auto.nextEvery(0, "write"), 600)
	eq(Auto.nextEvery(3600, "write"), 600)
	local e, seq = 0, {}
	for _ = 1, 5 do
		e = Auto.nextEvery(e, "fits")
		seq[#seq + 1] = e / 60
	end
	eq(seq, { 10, 20, 40, 60, 60 })
	eq(Auto.nextEvery(300, "small"), 600)
	eq(Auto.nextEvery(2400, "refused"), 600)
	eq(Auto.nextEvery(nil, "fits"), 600)
end)

test("check interval setting (sqrl_auto_every): x0.5 / x1 / x2 / x4 scale write, back-off, cap and soon; first and retry unscaled; clamp; default x1", function()
	-- the param: 1-based indices, default x1 on anything else
	eq(Auto.everyFactorOf(nil), 1)
	eq(Auto.everyFactorOf({}), 1)
	eq(Auto.everyFactorOf({ sqrl_auto_every = 1 }), 0.5)
	eq(Auto.everyFactorOf({ sqrl_auto_every = 2.0 }), 1)
	eq(Auto.everyFactorOf({ sqrl_auto_every = 3 }), 2)
	eq(Auto.everyFactorOf({ sqrl_auto_every = 4 }), 4)
	eq(Auto.everyFactorOf({ sqrl_auto_every = 0 }), 1, "out of range")
	eq(Auto.everyFactorOf({ sqrl_auto_every = 5 }), 1, "out of range")
	eq(Auto.everyFactorOf({ sqrl_auto_every = 1.5 }), 1, "not an index")
	eq(Auto.everyFactorOf({ sqrl_auto_every = "x" }), 1)
	local ok2, e = pcall(function()
		local function backoff()
			local ev, seq = 0, {}
			for _ = 1, 6 do
				ev = Auto.nextEvery(ev, "fits")
				seq[#seq + 1] = ev / 60
			end
			return seq
		end
		eq(Auto.setEveryFactor(0.5), 0.5)
		eq(Auto.nextEvery(3600, "write"), 300, "write gap 5 min")
		eq(backoff(), { 5, 10, 20, 30, 30, 30 })
		eq(Auto.nextEvery(2400, "refused"), 300)
		eq(Auto.every(Auto.EVERY_SOON), 150)
		eq(Auto.setEveryFactor(4), 4)
		eq(Auto.nextEvery(0, "write"), 2400)
		eq(backoff(), { 40, 80, 160, 240, 240, 240 })
		eq(Auto.every(Auto.EVERY_WRITE), 2400)
		-- a running interval of another factor: doubled from where it is, within the new cap
		eq(Auto.nextEvery(300, "small"), 2400)
		eq(Auto.setEveryFactor(2), 2)
		eq(backoff(), { 20, 40, 80, 120, 120, 120 })
		-- never scaled
		eq({ Auto.EVERY_FIRST, Auto.RETRY_S }, { 0, 120 })
		-- clamp, junk
		eq(Auto.setEveryFactor(0.1), 0.5)
		eq(Auto.setEveryFactor(100), 4)
		eq(Auto.setEveryFactor(0 / 0), 1)
		eq(Auto.setEveryFactor(nil), 1)
		eq(Auto.setEveryFactor("2"), 1)
		eq(Auto.nextEvery(0, "write"), 600)
	end)
	Auto.setEveryFactor(1)
	if not ok2 then error(e, 0) end
end)

test("save safety: both lists stay bounded (1000 entries x 3 numbers, 1000 records x 8), under 120 kB serialized", function()
	local list, last = nil, nil
	for i = 1, 1200 do
		local x, y = (i % 50) * 100.37 + 0.05, math.floor(i / 50) * 99.91 - 12345.6
		list = Auto.apply(list, "add", { { 100000 + i, x, y } })
		-- the durations signature at its cap (Auto.DSIG_MAX; 8 phases of 60 s give 4320)
		last = Auto.applyLast(last, { Auto.record(100000 + i, x, y, 1234567 + i, "auto", "written", 112, 120, math.floor(Auto.DSIG_MAX) - 1) })
	end
	eq(#list, Auto.MAX)
	eq(#last, Auto.LAST_MAX)
	eq(last[1][4], 1234567 + 201, "the oldest records dropped")
	local function ser(v)
		if type(v) == "table" then
			local parts = {}
			for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. ser(x) end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return tostring(v)
	end
	local state = { auto = list, aseq = 1200, aall = { seq = 3, run = string.rep("r", 40) }, arun = string.rep("r", 40),
		areq = { seq = 9, nodes = {} }, rlast = last, lseq = 1200 }
	for i = 1, Auto.EVENT_MAX do state.areq.nodes[i] = { 200000 + i, 12345.6, -12345.6 } end
	local size = #ser(state)
	print("saved state with both caps reached: " .. size .. " bytes")
	ok(size < 120000, "bounded: " .. size)
	-- a malformed saved list is cleaned on read, at most MAX entries
	local dirty = { "x", { -1, 0, 0 } }
	for i = 1, 1100 do dirty[#dirty + 1] = { i, i, 0 } end
	eq(#Auto.clean(dirty), Auto.MAX - 2)
end)

test("applyLast: one record per junction (by id or within 2 m), replaced by a newer one; the oldest dropped beyond the cap", function()
	local last, st = Auto.applyLast(nil, { Auto.record(5, 10, 10, 100, "manual", "written", 50, 75) })
	eq(last, { { 5, 10, 10, 100, 11, 50, 75 } })
	eq({ st.added, st.changed }, { 1, true })
	-- the automatic mode at the same junction (re-created under another id, 1 m away): replaced
	last, st = Auto.applyLast(last, { Auto.record(9, 11, 10, 400, "auto", "fits", 75) })
	eq(last, { { 9, 11, 10, 400, 22, 75, 75 } })
	eq({ st.replaced, st.added }, { 1, 0 })
	last, st = Auto.applyLast(last, { Auto.record(9, 11, 10, 400, "auto", "fits", 75) })
	eq(st.changed, false, "the same record: nothing to write")
	-- malformed records are skipped, the rest applied
	last = Auto.applyLast(last, { { 1, 2 }, Auto.record(3, 500, 500, 10, "auto", "small", 60) })
	eq(#last, 2)
	eq(Auto.match(Auto.lastIndex(last), 3, nil, nil)[5], 23)
end)

test("readSaved: nil when unreadable; aseq unchanged reads nothing else; the list and the requests otherwise", function()
	eq({ Auto.readSaved({}, nil) }, { nil, nil, nil })
	local state = { aseq = 4, auto = { { 1, 2, 3 } }, aall = { seq = 1, run = "r" }, areq = { seq = 2, nodes = { { 1, 2, 3 } } }, arun = "r" }
	local api = { type = { ComponentType = { GAME_SCRIPT = "GS" } }, engine = {
		system = { gameScriptSystem = { getEntityForGameScript = function() return 5 end } },
		getComponent = function(_, ct) return ct == "GS" and { state = state } or nil end } }
	local seq, list, extra = Auto.readSaved(api, nil)
	eq(seq, 4)
	eq(list, { { 1, 2, 3 } })
	eq(extra.all, { seq = 1, run = "r" })
	eq(extra.req.seq, 2)
	eq(extra.run, "r")
	local s2, l2 = Auto.readSaved(api, 4)
	eq({ s2, l2 }, { 4, nil })
	-- the records: lseq and rlast, read only when lseq changed; nothing saved: an empty list
	eq({ Auto.readLast(api, nil) }, { nil, {} })
	state.lseq, state.rlast = 2, { { 1, 2, 3, 100, 11, 50, 75 } }
	eq({ Auto.readLast(api, nil) }, { 2, { { 1, 2, 3, 100, 11, 50, 75 } } })
	eq({ Auto.readLast(api, 2) }, { 2, nil })
	eq({ Auto.readLast({}, nil) }, { nil, nil })
end)

---------------------------------------------------------------------------
-- the SmartLanes.auto event in the game script

local FX = { world = function()
	return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build({ [901] = { 0, 0 }, [902] = { 100, 0 }, [903] = { 0, 100 } },
		{ [1] = { 901, 902, F.TPL.medium }, [2] = { 901, 903, F.TPL.medium } }, false))
end, conns = F.PROBE_4LANE_MEDIUM.conns }

local function autoEvent(G, payload)
	return G.gs.handleEvent({}, G.state, "", Auto.EVENT_ID, Auto.EV_AUTO, payload)
end

test("event: add / remove stored (auto, aseq), AUTORETIME enroll / unenroll lines; nothing changed writes nothing", function()
	local G = makeGame(nil, FX)
	G.gs.update({}, G.state, 0.1)
	autoEvent(G, { op = "add", nodes = { { 901, 0, 0 }, { 902, 100, 0 } } })
	local s = G.state:get()
	eq(s.auto, { { 901, 0, 0 }, { 902, 100, 0 } })
	eq(s.aseq, 1)
	eq(G.kinds("AUTORETIME"), { "[SQRL] AUTORETIME op=enroll node=901 pos=0.0,0.0 src=tool total=2",
		"[SQRL] AUTORETIME op=enroll node=902 pos=100.0,0.0 src=tool total=2" })
	autoEvent(G, { op = "add", nodes = { { 901, 0.5, 0 } } })
	eq(G.state:get().aseq, 1, "already enrolled: nothing written")
	autoEvent(G, { op = "remove", nodes = { { 777, 0.4, 0.3 } } })
	s = G.state:get()
	eq(s.auto, { { 902, 100, 0 } })
	eq(s.aseq, 2)
	eq(G.kinds("AUTORETIME")[3], "[SQRL] AUTORETIME op=unenroll node=777 pos=0.4,0.3 src=tool total=1")
	-- the runtime re-attached it under a new id: no line
	autoEvent(G, { op = "update", src = "auto", nodes = { { 905, 100.5, 0 } } })
	eq(G.state:get().auto, { { 905, 100.5, 0 } })
	eq(G.state:get().aseq, 3)
	eq(#G.kinds("AUTORETIME"), 3)
	autoEvent(G, { op = "remove", nodes = { { 905, 100, 0 } } })
	eq(G.state:get().auto, nil, "the last entry gone: no list")
	eq(#G.kinds("ERROR"), 0)
end)

test("event: last records stored in rlast (lseq +1, aseq unchanged, no line); nothing new writes nothing", function()
	local G = makeGame(nil, FX)
	G.gs.update({}, G.state, 0.1)
	eq(G.state:get(), nil, "nothing saved before the first use")
	autoEvent(G, { op = "last", src = "tool", nodes = { Auto.record(901, 0, 0, 100, "manual", "fits", 52) } })
	local s = G.state:get()
	eq(s.rlast, { { 901, 0, 0, 100, 12, 52, 52 } })
	eq({ s.lseq, s.aseq, s.auto }, { 1, nil, nil })
	autoEvent(G, { op = "last", src = "auto", nodes = { Auto.record(901, 0, 0, 900, "auto", "written", 52, 72),
		Auto.record(902, 100, 0, 900, "auto", "small", 60) } })
	s = G.state:get()
	eq(s.rlast, { { 901, 0, 0, 900, 21, 52, 72 }, { 902, 100, 0, 900, 23, 60, 60 } })
	eq(s.lseq, 2)
	autoEvent(G, { op = "last", src = "auto", nodes = { Auto.record(902, 100, 0, 900, "auto", "small", 60) } })
	eq(G.state:get().lseq, 2, "the same record: nothing written")
	eq(#G.kinds("AUTORETIME"), 0)
	eq(#G.kinds("ERROR"), 0)
end)

test("event: now / all / clear requests, run ids read back (arun), zid= of the zone the junction lies in", function()
	local G = makeGame(nil, FX)
	G.gs.update({}, G.state, 0.1)
	G.gs.handleEvent({}, G.state, "", "square_smart_lanes", "SmartLanes.zones", { op = "set", run = "z1",
		zones = { { x = 0, y = 0, r = 30, ab = "sl_auto", id = "g1t", pair = "g1" } } })
	autoEvent(G, { op = "add", src = "zone", nodes = { { 901, 0, 0 } } })
	eq(G.kinds("AUTORETIME")[1], "[SQRL] AUTORETIME op=enroll node=901 pos=0.0,0.0 src=zone total=1 zid=g1t")
	autoEvent(G, { op = "now", nodes = { { 901, 0, 0 } } })
	local s = G.state:get()
	eq(s.areq, { seq = 1, nodes = { { 901, 0, 0 } } })
	eq(G.kinds("AUTORETIME")[2], "[SQRL] AUTORETIME op=now node=901 pos=0.0,0.0 src=tool zid=g1t")
	autoEvent(G, { op = "all", run = "st-7" })
	s = G.state:get()
	eq(s.aall, { seq = 1, run = "st-7" })
	eq(s.arun, "st-7")
	eq(G.kinds("AUTORETIME")[3], "[SQRL] AUTORETIME op=enroll_all phase=request run=st-7 src=stress")
	autoEvent(G, { op = "all", run = "st-8" })
	eq(G.state:get().aall.seq, 2)
	autoEvent(G, { op = "clear", run = "st-8" })
	s = G.state:get()
	eq(s.auto, nil)
	eq(s.arun, "st-8")
	eq(G.kinds("AUTORETIME")[5], "[SQRL] AUTORETIME op=unenroll all=1 n=1 run=st-8 src=stress")
	local seqs = s.aseq
	eq(seqs, 5, "every request bumps aseq (the runtime re-reads)")
	eq(#G.kinds("ERROR"), 0)
end)

test("event: the cap refuses adds (AUTORETIME op=refuse reason=cap); malformed payloads ignored (20 lines); map editor ignores", function()
	local G = makeGame(nil, FX)
	G.gs.update({}, G.state, 0.1)
	local full = {}
	for i = 1, Auto.MAX do full[i] = { 1000 + i, i * 10, 5000 } end
	G.state:set({ auto = full, aseq = 3 })
	autoEvent(G, { op = "add", nodes = { { 5, 0, 0 } } })
	eq(G.kinds("AUTORETIME"), { "[SQRL] AUTORETIME op=refuse reason=cap node=5 pos=0.0,0.0 src=tool total=" .. Auto.MAX })
	eq(G.state:get().aseq, 3, "nothing stored")
	autoEvent(G, { op = "add", nodes = { { -5, 0, 0 } } })
	autoEvent(G, "x")
	eq(G.kinds("AUTORETIME")[2], "[SQRL] AUTORETIME op=ignored reason=node1")
	eq(G.kinds("AUTORETIME")[3], "[SQRL] AUTORETIME op=ignored reason=not_table")
	for _ = 1, 30 do autoEvent(G, 7) end
	eq(#G.kinds("AUTORETIME"), 21)
	local M = makeGame(nil, FX)
	M.api.engine.config.getModParams = function() return { square_smart_lanes = {}, [""] = { isMapEditor = true } } end
	M.gs.update({}, M.state, 0.1)
	autoEvent(M, { op = "add", nodes = { { 1, 0, 0 } } })
	eq(M.state:get(), nil)
end)

test("zones: sl_auto plans the axis phases as sl_phases (the automatic pass), whatever Light phases says", function()
	local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
	local op, list = Zones.validate({ op = "set", zones = { { x = 0, y = 0, r = 50, ab = "sl_auto" } } })
	eq(op, "set")
	eq(list[1].ab, "sl_auto")
	-- the game script's choice of phases for a node in the zone (the same branch as sl_phases)
	local src = io.open(here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_lanes.script.lua"):read("a")
	ok(src:find('zoneAb[n] == "sl_phases" or zoneAb[n] == "sl_auto"', 1, true) ~= nil, "zonePh includes sl_auto")
end)
