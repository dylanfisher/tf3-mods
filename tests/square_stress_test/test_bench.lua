-- Stress Test bench (plans/square_stress_test/BENCH.md): the sheets, the point-clearance packer and the plan
-- (stress/stress_bench.tl), checked offline: every clearance rule between every two placed groups, the capacity per
-- sheet on a 16 km map, twins identical and their order rotated, the log lines and the preflight checks; and the run
-- (gui/stress_bench_run.tl) against stubs: every phase in order, game time counting, the speed step-down, aborts.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
local bench = ug_require "square_stress_test::/stress/stress_bench.tl"

local M = 400.0   -- stress_junctions MAP_MARGIN
local KM16 = 16000

---------------------------------------------------------------------------
-- The plan

local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

local function segDist(p, a, b)
	local dx, dy = b[1] - a[1], b[2] - a[2]
	local l2 = dx * dx + dy * dy
	local t = l2 > 0 and math.max(0, math.min(1, ((p[1] - a[1]) * dx + (p[2] - a[2]) * dy) / l2)) or 0
	return dist(p, { a[1] + t * dx, a[2] + t * dy })
end

test("sheets on a 16 km map: every test gets its sets (11 roundabouts, 9 channelized T / lit T, 6 diamonds, 3 lit X), groups / towns as BENCH.md", function()
	local want = {
		s1 = { tests = { rb4 = 11 }, groups = 33, towns = 132 },
		s2 = { tests = { cht = 9, dia = 6 }, groups = 39, towns = 117 },
		s3 = { tests = { lt22 = 9, lx = 3 }, groups = 36, towns = 117 },
	}
	for _, sh in ipairs(bench.SHEETS) do
		local p = bench.plan(KM16, KM16, M, sh, 1)
		local got = {}
		for _, tp in ipairs(p.tests) do got[tp.test.id] = tp.sets end
		eq(got, want[sh.key].tests, sh.key)
		eq({ p.groups, p.towns }, { want[sh.key].groups, want[sh.key].towns }, sh.key)
		eq(#p.cut, 0, sh.key)
		eq(#p.problems, 0, sh.key)
		eq(#p.layout.groups, p.groups)
		ok(p.layout.square)
	end
end)

test("plan: every two groups clear each other (town 1250 m, junction to town reach + 625, link to town 625, link to junction reach + 400, links 100 m apart); inside the map margin", function()
	for _, sh in ipairs(bench.SHEETS) do
		local L = bench.plan(KM16, KM16, M, sh, 2).layout
		local G = {}
		for _, g in ipairs(L.groups) do
			local towns = {}
			for _, ti in ipairs(g.towns) do towns[#towns + 1] = { L.towns[ti].x, L.towns[ti].y } end
			G[#G + 1] = { j = { g.place.x, g.place.y }, r = g.place.reach, towns = towns }
			for _, t in ipairs(towns) do
				ok(math.abs(t[1]) <= KM16 / 2 - M and math.abs(t[2]) <= KM16 / 2 - M, "inside the margin")
			end
		end
		for i = 1, #G do
			for k = i + 1, #G do
				for _, pair in ipairs({ { G[i], G[k] }, { G[k], G[i] } }) do
					local a, b = pair[1], pair[2]
					for _, t in ipairs(a.towns) do
						for _, u in ipairs(b.towns) do ok(dist(t, u) >= 1250 - 1e-6, sh.key .. " towns") end
						ok(dist(t, b.j) >= b.r + 625 - 1e-6, sh.key .. " town to junction")
						for _, u in ipairs(b.towns) do ok(segDist(u, a.j, t) >= 625 - 1e-6, sh.key .. " link to town") end
						ok(segDist(b.j, a.j, t) >= b.r + 400 - 1e-6, sh.key .. " link to junction")
						for _, u in ipairs(b.towns) do ok(segDist(u, a.j, t) >= 100 and segDist(a.j, b.j, u) >= 100, sh.key .. " links") end
					end
				end
			end
		end
	end
end)

test("plan: towns on the arms' axes at one distance (884 m at 90 deg, 713 m for the straight lane drop), rotation 0, no -0; twins identical, each set's twins in an order rotated by the set", function()
	local p = bench.plan(KM16, KM16, M, bench.sheet("s1"), 1)
	local L = p.layout
	local bySet = {}
	for _, g in ipairs(L.groups) do
		eq(g.place.angle, 0)
		ok(not (g.place.x == 0 and 1 / g.place.x < 0) and not (g.place.y == 0 and 1 / g.place.y < 0), "no -0")
		local want = g.test == "drop" and 713 or 884
		for _, ti in ipairs(g.towns) do
			local t = L.towns[ti]
			local dx, dy = t.x - g.place.x, t.y - g.place.y
			ok(dx == 0 or dy == 0, "on an axis")
			eq(math.abs(dx) + math.abs(dy), want, g.test)
			eq(t.size, 2)
		end
		bySet[g.set] = bySet[g.set] or {}
		table.insert(bySet[g.set], g)
	end
	local firsts = {}
	for set, list in pairs(bySet) do
		local params = logic.showcaseParamText(list[1].place.case_)
		for _, g in ipairs(list) do
			eq(logic.showcaseParamText(g.place.case_), params, "twins identical")
			eq(#g.towns, #list[1].towns)
			eq(g.name, string.format("Group %d%s", set, g.twin))
		end
		-- the mode placed first (the layout lists the twins in placement order)
		if list[1].test == "rb4" then firsts[list[1].ab] = (firsts[list[1].ab] or 0) + 1 end
	end
	eq(firsts, { game = 4, sl = 4, sl_keeplights = 3 }, "every mode placed first in 3 or 4 of the 11 roundabout sets")
	for _, g in ipairs(L.groups) do eq(#g.towns, 4) end
	-- a lane drop (no sheet uses it since sheet 1 version 2; its shape stays): two towns E / W at 713 m
	local dropSheet = { id = "bench_t", key = "t", title = "t", version = 1, minKm = 16, tests = { { id = "drop", title = "drop",
		variants = { bench.VARIANTS.drop }, towns = { "E", "W" }, twins = { "game", "sl" }, compare = { { "sl", "game" } }, sets = 2, linkLanes = 0 } } }
	local D = bench.plan(KM16, KM16, M, dropSheet, 1).layout
	eq(#D.groups, 4)
	for _, g in ipairs(D.groups) do
		eq(#g.towns, 2)
		for _, ti in ipairs(g.towns) do eq(math.abs(D.towns[ti].x - g.place.x) + math.abs(D.towns[ti].y - g.place.y), 713) end
	end
	ok(L.towns[1].name:match("^%u%l+ %l+ 1 %u$"), L.towns[1].name)
	for _, t in ipairs(L.towns) do ok(logic.isTestTownName(t.name), t.name) end
end)

test("plan: deterministic; a smaller map cuts whole sets (logged as cut); a map too small gets nothing", function()
	local sh = bench.sheet("s1")
	local a, b = bench.plan(KM16, KM16, M, sh, 5), bench.plan(KM16, KM16, M, sh, 6)
	eq(#a.layout.groups, #b.layout.groups)
	for i, g in ipairs(a.layout.groups) do eq({ g.place.x, g.place.y, g.ab }, { b.layout.groups[i].place.x, b.layout.groups[i].place.y, b.layout.groups[i].ab }) end
	local s2 = bench.sheet("s2")
	local small = bench.plan(12000, 12000, M, s2, 1)
	ok(#small.cut >= 1, "cut")
	ok(small.cut[1]:find("^cht: %d of 9 sets$") ~= nil, small.cut[1])
	-- the later test gets what is left (a 12 km map: maybe nothing)
	ok(small.tests[2].sets >= 0)
	for _, g in ipairs(small.layout.groups) do
		local n = 0
		for _, h in ipairs(small.layout.groups) do if h.set == g.set then n = n + 1 end end
		eq(n, g.test == "cht" and 3 or 2, "sets whole")
	end
	local tiny = bench.plan(2000, 2000, M, sh, 1)
	eq(tiny.groups, 0)
end)

test("plan: the packer takes well under a few seconds on a 16 km map", function()
	local t0 = os.clock()
	bench.plan(KM16, KM16, M, bench.sheet("s3"), 77)
	ok(os.clock() - t0 < 5, string.format("%.2f s", os.clock() - t0))
end)

test("spec: one kind slot per test, the sheet's modes, Lights showcase towns / entries / locks / growth to 400, links at the arm's lanes, its layout from the plan", function()
	local sh = bench.sheet("s1")
	local sp = bench.spec(sh)
	eq(sp.id, "bench_s1")
	eq(sp.kinds, { "rb4" })
	local ab = {}
	for _, m in ipairs(sp.modes) do ab[#ab + 1] = m.ab .. m.twin end
	eq(ab, { "gameb", "sla", "sl_keeplightsf" })
	ok(sp.square and sp.entries and sp.lockStreets and sp.noBusLines and sp.modeNames and sp.bench)
	eq(sp.linkLanes, nil)
	eq(sp.growTarget, 400)
	local L = sp.layoutFn(KM16, KM16, M, 3)
	eq(#L.groups, 33)
	eq(bench.needs(sh), { "sl_keeplights" })
	eq(bench.needs(bench.sheet("s3")), { "sl_lock" })
	for _, g in ipairs(L.groups) do
		eq(g.linkLanes, 0)
		ok(g.slot == g.test)
	end
	local L2 = bench.spec(bench.sheet("s2")).layoutFn(KM16, KM16, M, 3)
	for _, g in ipairs(L2.groups) do
		if g.test == "dia" then eq(g.pairLanes, 4) else eq(g.pairLanes, nil) end
	end
	local L3 = bench.spec(bench.sheet("s3")).layoutFn(KM16, KM16, M, 3)
	for _, g in ipairs(L3.groups) do eq(g.litYes, true) end
end)

test("zones: test, variant and approach on the payload's source; sl_keeplights in by_ab after sl_exitfan only when there are such zones", function()
	local L = bench.plan(KM16, KM16, M, bench.sheet("s1"), 1).layout
	local zones = logic.showcaseZones(L, 0, 0)
	eq(#zones, 33)
	local payload = logic.slZonesPayload(zones, "s1-2-3")
	eq(logic.slZonesByAb(payload.zones), "game:11,sl:11,sl_phases:0,sl_keeplights:11")
	eq(logic.slZonesByAb({ { ab = "sl_exitfan" }, { ab = "sl_keeplights" } }), "game:0,sl:0,sl_phases:0,sl_exitfan:1,sl_keeplights:1")
	eq(logic.slZonesByAb({ { ab = "sl" } }), "game:0,sl:1,sl_phases:0")
	for _, z in ipairs(zones) do
		eq(z.test, "rb4")
		eq(z.approach, 518)
		ok(z.id:match("^s1g%d+[abf]$") and z.pair:match("^s1g%d+$"), z.id .. " " .. z.pair)
	end
	local line = logic.showcaseZoneLine(zones[1], false)
	ok(line:find(" test=rb4 variant=RB4_2L approach=518$") ~= nil, line)
	-- a Showcase layout (not square): no approach
	local sc = logic.showcaseLayout(16000, 16000, 400, 1)
	eq(logic.showcaseZones(sc, 0, 0)[1].approach, nil)
end)

test("log lines: BENCH_TEST per test, the plan text, BENCH_START with Smart Lanes' settings", function()
	local sh = bench.sheet("s1")
	local p = bench.plan(KM16, KM16, M, sh, 1)
	eq(bench.testLine(sh, p.tests[1]), "[SQST] BENCH_TEST sheet=s1 id=rb4 title=Roundabout,_2-lane_ring,_4_country_medium_arms kind=rb variants=RB4_2L twins=game,sl,sl_keeplights compare=sl:game,sl:sl_keeplights sets=11/11 groups=33 towns=132 towns_per_twin=4 pop=400 lights=game")
	ok(bench.planText(p, KM16, KM16):find("^33 junctions, 132 towns %(~53k people%), about [%d.]+ min to build; 16.0 x 16.0 km map: everything fits$") ~= nil,
		bench.planText(p, KM16, KM16))
	local info = { w = KM16, h = KM16, plan = p, year = 1950, sl = bench.slSettings({ sqrl_auto = 1, sqrl_lights = 1, sqrl_free_turn = 3, sqrl_light_phases = 1 }),
		slModes = { "game", "sl", "sl_keeplights" } }
	eq(bench.startLine(sh, info, 42), "[SQST] BENCH_START sheet=s1 spec=bench_s1@2 seed=42 map=16000x16000 tests=1 groups=33 towns=132 year=1950 sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=game,sl,sl_keeplights warmup_s=180 record_s=1200 interval_s=10 speed=2")
end)

test("preflight: Smart Lanes' settings read as it reads them; every reason a sheet can't run is said", function()
	eq(bench.slSettings({}), { auto = true, lights = true, freeTurn = "always", phases = "game" })
	eq(bench.slSettings({ sqrl_auto = 2, sqrl_lights = 2, sqrl_free_turn = 1, sqrl_light_phases = 2 }), { auto = false, lights = false, freeTurn = "off", phases = "sl" })
	eq(bench.slSettings({ sqrl_auto = 0, sqrl_lights = 7 }).lights, true, "out of range: the default")
	local sh = bench.sheet("s1")
	local p = bench.plan(KM16, KM16, M, sh, 1)
	local good = { w = KM16, h = KM16, plan = p, needsRb = true, rbOk = true, slPresent = true, sl = bench.slSettings({}), slModes = { "game", "sl", "sl_keeplights" } }
	eq(bench.problems(sh, good), {})
	local function with(k, v)
		local t = {}
		for a, b in pairs(good) do t[a] = b end
		t[k] = v
		return bench.problems(sh, t)
	end
	ok(with("busy", "lights_showcase")[1]:find("still queued", 1, true))
	ok(with("plan", bench.plan(2000, 2000, M, sh, 1))[1]:find("Nothing fits", 1, true))
	ok(with("rbOk", false)[1]:find("Roundabouts & Interchanges", 1, true))
	ok(with("slPresent", false)[1]:find("Smart Lanes is not enabled", 1, true))
	ok(with("sl", bench.slSettings({ sqrl_lights = 2 }))[1]:find("No lights at roundabouts and ramps", 1, true))
	ok(with("sl", bench.slSettings({ sqrl_auto = 2 }))[1]:find("Apply automatically", 1, true))
	ok(with("slModes", { "game", "sl" })[1]:find("sl_keeplights", 1, true))
	ok(with("slModes", nil)[1]:find("reported no modes", 1, true))
	-- sheet 3 needs no lights setting
	local s3 = bench.sheet("s3")
	eq(bench.problems(s3, { w = KM16, h = KM16, plan = bench.plan(KM16, KM16, M, s3, 1), slPresent = true,
		sl = bench.slSettings({ sqrl_lights = 2 }), slModes = { "game", "sl", "sl_lock" } }), {})
end)

---------------------------------------------------------------------------
-- The run (gui/stress_bench_run.tl) against stubs

local T, GT, YEAR, SPEEDS, DATES, SHOTS, CAMS, SPEEDUP, NOYEAR
local calls, built, flState, slz, removeJobs

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			Date = { new = function(y) return { year = y } end },
			Vec5f = { new = function(x, y, z, w, q) return { x = x, y = y, z = z, w = w, q = q } end },
		},
		cmd = {
			sendCommand = function(cmd, cb)
				if cmd.speed then SPEEDS[#SPEEDS + 1] = cmd.speed end
				if cmd.date then DATES[#DATES + 1] = cmd.date.year if not NOYEAR then YEAR = cmd.date.year end end
				if cb then cb(cmd, true) end
			end,
			makeGameSetSpeedCmd = function(s) return { speed = s } end,
			makeGameSetDateCmd = function(d) return { date = d } end,
		},
		gui = { camera = {
			getCameraData = function() return { x = 0, y = 0, z = 1000, w = 0.5, q = 0.7 } end,
			setCameraData = function(v) CAMS[#CAMS + 1] = v end,
			takeScreenshot = function(s) SHOTS[#SHOTS + 1] = s end,
		} },
		engine = {
			getComponent = function(e, ct)
				if e == 9 and ct == "GAME_TIME" then return { gameTime = GT } end
				if e == 9 and ct == "GAME_SPEED" and SPEEDUP ~= nil then return { speedup = SPEEDUP } end
				return nil
			end,
			terrain = { getBoundingBox = function() return { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } } end },
			config = { getModParams = function() return { square_smart_lanes = { sqrl_auto = 1, sqrl_lights = 1 } } end },
			util = { getWorld = function() return 9 end, getYear = function() return YEAR end, getPlayer = function() return 7 end,
				finance = { getPlayersBalance = function() return 1e12 end } },
		},
	}
end

local rt, br, jnStub, flStub
before_each(function()
	T, GT, YEAR, SPEEDUP, NOYEAR = 0, 1000000, 1920, nil, nil
	SPEEDS, DATES, SHOTS, CAMS, calls, removeJobs = {}, {}, {}, {}, {}, {}
	built = nil
	flState = { on = false, interval = 2, samples = 0, skipped = 0, starts = 0 }
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	slz = { zrun = nil, modes = { "game", "sl", "sl_phases", "sl_fan", "sl_lock", "sl_exitfan", "sl_keeplights" }, qlen = 0 }
	stub_module("square_stress_test::/stress/gui/stress_slzones.tl", {
		present = function() return true end,
		sendClear = function(by) calls[#calls + 1] = "clear:" .. by slz.zrun = "run-" .. by return "run-" .. by end,
		ackRun = function() return slz.zrun end,
		modes = function() return slz.modes end,
		waitIdle = function(name, maxMs, cb) calls[#calls + 1] = "idle" cb("yes", 2000) end,
	})
	jnStub = {
		available = function() return true end,
		buildBench = function(sheet, seed) built = { sheet = sheet, seed = seed } calls[#calls + 1] = "build" return true end,
	}
	stub_module("square_stress_test::/stress/gui/stress_junctions.tl", jnStub)
	stub_module("square_stress_test::/stress/gui/stress_towns.tl", {
		ui = { removeTarget = 1 },
		removePlan = function() return { 11, 12 }, { "A", "B" } end,
		removeTowns = function(list) calls[#calls + 1] = "towns:" .. #list removeJobs[#removeJobs + 1] = "remove_all" end,
	})
	stub_module("square_stress_test::/stress/gui/stress_roads.tl", {
		count = function() return 5, 0 end,
		removeAll = function() calls[#calls + 1] = "roads" removeJobs[#removeJobs + 1] = "remove_roads" end,
	})
	flStub = {
		ui = flState,
		setOn = function(on)
			flState.on = on
			if on then flState.starts = flState.starts + 1 flState.samples, flState.skipped = 0, 0 end
			calls[#calls + 1] = "log:" .. tostring(on)
		end,
		setInterval = function(i) flState.interval = i end,
		counts = function() return flState.samples, flState.skipped end,
	}
	stub_module("square_stress_test::/stress/gui/stress_flow_log.tl", flStub)
	stub_module("square_stress_test::/stress/gui/stress_traffic.tl", { ui = { keepCleared = true },
		setKeepCleared = function(on) calls[#calls + 1] = "keep:" .. tostring(on) end })
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	-- the removal jobs: busy while listed, gone one tick later
	local busyJob = rt.busyJob
	rt.busyJob = function(prefixes)
		for _, p in ipairs(prefixes) do
			if p == "remove_" and #removeJobs > 0 then return table.remove(removeJobs, 1) end
		end
		return busyJob(prefixes)
	end
	br = ug_require "square_stress_test::/stress/gui/stress_bench_run.tl"
end)

local function tick(n, gtStep)
	for _ = 1, n do
		T = T + 300000
		GT = GT + (gtStep or 0)
		rt.tick()
	end
end

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.msg end
	return table.concat(out, "\n")
end

local function phases()
	local out = {}
	for _, e in ipairs(log_entries()) do
		local p = e.msg:match("%[SQST%] BENCH_PHASE sheet=s1 phase=([%w_]+)")
		if p then out[#out + 1] = p end
	end
	return out
end

test("run: one press goes preflight -> clear the map -> year 1950 -> build -> Smart Lanes idle -> warm-up -> record (game time) -> log off, speed 1 -> screenshots -> BENCH_DONE", function()
	local okS = br.start("s1", 77)
	ok(okS)
	eq(calls[1], "clear:bench_preflight")
	tick(3)
	ok(logText():find("[SQST] BENCH_START sheet=s1 spec=bench_s1@2 seed=77 ", 1, true), logText())
	ok(logText():find("sl_modes=game,sl,sl_phases,sl_fan,sl_lock,sl_exitfan,sl_keeplights", 1, true))
	tick(6)
	eq(DATES, { 1950 })
	ok(built ~= nil and built.sheet.key == "s1" and built.seed == 77, "built")
	local seq = table.concat(calls, " ")
	ok(seq:find("towns:2 roads build", 1, true), seq)
	-- the build finishes (its growth included): the hook
	tick(2)
	eq(br.phase, "build")
	jnStub.onRunFinished("bench_s1", 77, { groups = { { test = "rb4", set = 1, twin = "b" } } }, { { built = true, x = 100, y = 200, id = "g1b" } })
	tick(3)
	eq(br.phase, "warmup")
	eq(flState.on, true)
	eq(flState.interval, 1, "10 game s")
	eq(flStub.pathThru, false, "no path reads in a bench record")
	eq(SPEEDS, { 2 })
	ok(seq ~= nil)
	ok(table.concat(calls, " "):find("keep:false", 1, true), "Keep traffic cleared turned off")
	-- a paused game: nothing moves on
	tick(20, 0)
	eq(br.phase, "warmup")
	tick(4, 50000)   -- 200 game s
	eq(br.phase, "record")
	ok(br.status():find("^Bench s1: recording ") ~= nil, br.status())
	flState.samples = 120
	tick(24, 50000)  -- 1200 game s
	eq(flState.on, false)
	eq(SPEEDS, { 2, 1 })
	eq(br.phase, "shots")
	tick(60)
	eq(#SHOTS, 2, "the primer and one junction")
	eq(CAMS[1].x, 100)
	eq(CAMS[1].z, 450)
	local all = logText()
	ok(all:find("[SQST] BENCH_SHOT sheet=s1 n=1 id=rb4:g1b x=100 y=200 ok=true", 1, true), all)
	ok(all:find("[SQST] BENCH_DONE sheet=s1 spec=bench_s1@2 seed=77 ok=yes samples=120 speed=2 ", 1, true), all)
	ok(all:find(" speed_end=1", 1, true), all)
	-- one BENCH_TEST line per test after BENCH_START
	ok(all:find("[SQST] BENCH_TEST sheet=s1 id=rb4 ", 1, true), all)
	eq(flStub.pathThru, true, "the path thru back on after the record")
	eq(br.phase, "idle")
	ok(br.status():find('tell Claude "done"', 1, true), br.status())
	eq(phases(), { "ack", "clear", "year", "build", "sl_idle", "warmup", "record", "stop", "shots" })
	eq(jnStub.onRunFinished, nil, "hook removed")
end)

test("run: a sample skipped in the warm-up at 2x -> speed 1, a fresh sampler run, the warm-up again (once)", function()
	br.start("s1", 5)
	tick(12)
	jnStub.onRunFinished("bench_s1", 5, { groups = {} }, {})
	tick(3)
	eq(br.phase, "warmup")
	flState.skipped = 1
	tick(1, 1000)
	eq(SPEEDS, { 2, 1 })
	eq(flState.starts, 2)
	ok(logText():find("phase=warmup gt=%d+ ms=%d+ speed=1 %(a sample was skipped at 2x%)") ~= nil, logText())
	flState.skipped = 3
	tick(1, 1000)
	eq(SPEEDS, { 2, 1 }, "only once")
end)

test("run: Smart Lanes without the sheet's zone mode, or another refusal, ends the run before anything is removed (BENCH_ABORT, dialog)", function()
	slz.modes = { "game", "sl", "sl_lock" }
	br.start("s1", 5)
	tick(3)
	ok(logText():find("[SQST] BENCH_ABORT sheet=s1 phase=ack reason=This_Smart_Lanes_does_not_know_the_zone_mode_sl_keeplights", 1, true), logText())
	eq(built, nil)
	ok(not table.concat(calls, " "):find("towns:", 1, true))
	ok(#rt.warnings >= 1)
	eq(br.running(), false)
	-- an older Smart Lanes (no zmodes)
	slz.modes = nil
	br.start("s1", 6)
	tick(30)
	ok(logText():find("reported_no_modes", 1, true), logText())
end)

test("run: Clear queue ends it (BENCH_ABORT reason=Clear_queue); a second press while it runs is refused", function()
	ok(br.start("s1", 5))
	local okB, why = br.start("s1", 6)
	eq(okB, false)
	eq(why, "a bench is running")
	tick(3)
	rt.clearQueue()
	tick(2)
	ok(logText():find("BENCH_ABORT sheet=s1 phase=", 1, true) and logText():find("reason=Clear_queue", 1, true), logText())
	eq(br.running(), false)
end)

test("run: a build that does not start ends the run; check() names what is missing before the dialog", function()
	jnStub.buildBench = function() return false end
	br.start("s1", 5)
	tick(12)
	ok(logText():find("reason=the_build_did_not_start", 1, true), logText())
	jnStub.available = function() return false end
	local p = br.check("s1")
	ok(#p == 1 and p[1]:find("Roundabouts & Interchanges", 1, true), table.concat(p, " | "))
	eq(br.check("s3"), {}, "sheet 3 needs only this mod and Smart Lanes")
	ok(br.planLine("s1"):find("^33 junctions, 132 towns") ~= nil, br.planLine("s1"))
end)

test("run: a paused game is refused up front; Smart Lanes not answering the clear ends the run naming a paused game", function()
	SPEEDUP = 0
	local okS, why = br.start("s1", 5)
	eq(okS, false)
	ok(why:find("paused", 1, true), why)
	SPEEDUP = 1
	slz.zrun = "nobody"
	-- the clear never answered
	ok(br.start("s1", 5))
	slz.zrun = "other"
	tick(25)
	ok(logText():find("reason=Smart_Lanes_did_not_answer_within_5_s_(game_paused?", 1, true), logText())
	eq(built, nil)
end)

test("run: an abort in the record turns the traffic log off and the speed back to 1x; the hooks and the bench flag go", function()
	br.start("s1", 5)
	tick(12)
	ok(jnStub.benchActive)
	jnStub.onRunFinished("bench_s1", 5, { groups = {} }, {})
	tick(3)
	eq(br.phase, "warmup")
	eq(flState.on, true)
	jnStub.onRunAborted = jnStub.onRunAborted   -- set by startBuild
	rt.clearQueue()
	tick(1)
	eq(flState.on, false)
	eq(SPEEDS, { 2, 1 })
	eq(jnStub.onRunFinished, nil)
	eq(jnStub.onRunAborted, nil)
	eq(jnStub.benchActive, false)
end)

test("run: the build's own stop (zones refused) ends the run; the year that did not change ends it; a throwing town removal ends it", function()
	br.start("s1", 5)
	tick(12)
	eq(br.phase, "build")
	ok(jnStub.onRunAborted ~= nil)
	jnStub.onRunAborted("bench_s1", "Smart Lanes did not take the twins' zones (ack=refused:ab3)")
	ok(logText():find("BENCH_ABORT sheet=s1 phase=build reason=Smart_Lanes_did_not_take_the_twins'_zones_(ack=refused:ab3)", 1, true), logText())
	clear_logs()
	NOYEAR, YEAR = true, 1920
	br.start("s1", 6)
	tick(12)
	ok(logText():find("reason=the_year_could_not_be_set_to_1950_(it_is_1920)", 1, true), logText())
	clear_logs()
	NOYEAR = nil
	local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl"
	towns.removePlan = function() error("boom") end
	towns.ui.removeTarget = 2
	br.start("s1", 7)
	tick(4)
	ok(logText():find("reason=removing_the_towns_failed:", 1, true), logText())
	eq(towns.ui.removeTarget, 2, "the Remove towns target restored")
end)

test("run: a build that logs nothing for 10 minutes is stopped by the watchdog; logging keeps it alive", function()
	br.start("s1", 5)
	tick(12)
	eq(br.phase, "build")
	for _ = 1, 30 do
		T = T + 60000000   -- a minute
		rt.log("[SQST] bench_s1 still building")
		rt.tick()
	end
	eq(br.phase, "build", "progress: alive after 30 minutes")
	for _ = 1, 12 do
		T = T + 60000000
		rt.tick()
	end
	ok(logText():find("reason=the_build_made_no_progress_for_10_minutes", 1, true), logText())
end)
