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

--- A Smart Lanes module loaded outside its mod (sl_auto.lua requires sl_settings / sl_record): its ug_require calls
-- resolve inside square_smart_lanes' content.
local function slRequire(path)
	local cache = {}
	local function req(p)
		local rel = p:match("^square_smart_lanes::/(.+)$") or p
		if cache[rel] == nil then
			local env = setmetatable({ ug_require = req }, { __index = _G })
			local chunk = assert(loadfile("mods/square_smart_lanes/content/" .. rel, "t", env))
			cache[rel] = chunk()
		end
		return cache[rel]
	end
	return req(path)
end

test("sheets on a 16 km map: every test gets its sets (11 roundabouts, 9 channelized T / lit T, 6 diamonds, 3 lit X), groups / towns as BENCH.md", function()
	local want = {
		s1 = { tests = { rb4 = 11 }, groups = 33, towns = 132 },
		s2 = { tests = { cht = 9, dia = 6 }, groups = 39, towns = 117 },
		s3 = { tests = { lt22 = 9, lx = 3 }, groups = 36, towns = 117 },
		s4 = { tests = { rb2v = 1, rb3v = 1, rb4v = 1 }, groups = 13, towns = 52 },
		s5 = { tests = { lu2 = 3, lu4 = 3 }, groups = 24, towns = 96 },
		s6 = { tests = { hm2 = 3 }, groups = 12, towns = 48 },
		micro = { tests = { rb4l = 2, rb3 = 1, rb2 = 1 }, groups = 32, towns = 128 },
	}
	for _, sh in ipairs(bench.SHEETS) do
		local p = bench.plan(KM16, KM16, M, sh, 1)
		local got = {}
		for _, tp in ipairs(p.tests) do got[tp.test.id] = tp.sets end
		eq(got, want[sh.key].tests, sh.key)
		eq({ p.groups, p.towns }, { want[sh.key].groups, want[sh.key].towns }, sh.key)
		-- the micro bench asks for more sets than fit (round robin: as many as the map holds)
		if sh.key ~= "micro" then eq(#p.cut, 0, sh.key) end
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
	eq(bench.startLine(sh, info, 42), "[SQST] BENCH_START sheet=s1 spec=bench_s1@2 seed=42 map=16000x16000 tests=1 groups=33 towns=132 year=1950 sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=game,sl,sl_keeplights warmup_s=180 record_s=1200 interval_s=10 speed=2 pop=400 pool=no rank=no")
end)

test("preflight: Smart Lanes' settings read as it reads them; every reason a sheet can't run is said", function()
	eq(bench.slSettings({}), { auto = true, lights = true, freeTurn = "always", phases = "game", perf = false })
	eq(bench.slSettings({ sqrl_auto = 2, sqrl_lights = 2, sqrl_free_turn = 1, sqrl_light_phases = 2, sqperf_log = 2 }), { auto = false, lights = false, freeTurn = "off", phases = "sl", perf = true })
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
	ok(with("sl", bench.slSettings({ sqrl_auto = 2 }))[1]:find("Apply automatically to new roads", 1, true))
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

local rt, br, jnStub, flStub, clStub
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
	-- the city run's build (its own test below drives the real module)
	clStub = {
		build = function(sheet, seed, onDone, onAbort)
			calls[#calls + 1] = "city_build"
			clStub.onDone, clStub.onAbort = onDone, onAbort
			return true
		end,
		enroll = function(sheet, run, crossings, plan) calls[#calls + 1] = "city_enroll:" .. tostring(run) return 243 end,
		unenroll = function() calls[#calls + 1] = "city_unenroll" end,
		gapCheck = function(label) calls[#calls + 1] = "city_gaps:" .. tostring(label) return 0 end,
	}
	stub_module("square_stress_test::/stress/gui/stress_citylights.tl", clStub)
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
	eq(CAMS[1].z, 130)
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

test("micro bench v2: the bench.MICRO block (button Micro, key micro): 2-, 3- and 4-lane rings, each set 8 twins (game, sl, the six ring layouts), one set of every ring type before any second; 600 people a town; pooled and ranked; ids microg<k><twin>", function()
	local sh = bench.sheet("micro")
	eq({ sh.id, sh.key, sh.button, sh.pop, sh.pool, sh.rank, sh.roundRobin, sh.version }, { "bench_micro", "micro", "Micro", 600, true, true, true, bench.MICRO.version })
	eq(bench.MICRO.version, 2)
	ok(sh.tests == bench.MICRO.tests, "the sheet's tests are the MICRO block's")
	local sp = bench.spec(sh)
	eq(sp.growTarget, 600)
	eq(sp.growFactor, 1.5, "the fallback factor: 600 / 400")
	eq(sp.kinds, { "rb4l", "rb3", "rb2" })
	local want = { "game", "sl", "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread" }
	for _, t in ipairs(sh.tests) do
		eq(t.twins, want)
		eq(#t.compare, 13)
		eq(t.compare[1], { "sl", "game" })
		eq(t.compare[2], { "sl_rturbo", "sl" })
		eq(t.compare[8], { "sl_rturbo", "game" })
	end
	eq(bench.needs(sh), { "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread" }, "the preflight requires them in zmodes")
	ok(bench.problems(sh, { w = KM16, h = KM16, plan = bench.plan(KM16, KM16, M, sh, 1), slPresent = true, sl = bench.slSettings({}),
		slModes = { "game", "sl", "sl_keeplights" } })[1]:find("sl_rturbo, sl_rmatch", 1, true))
	local p = bench.plan(KM16, KM16, M, sh, 1)
	ok(bench.planText(p, KM16, KM16):match("^32 junctions, 128 towns %(~77k people%)") ~= nil, bench.planText(p, KM16, KM16))
	-- round robin: every ring type its first set, then the 4-lane ring its second
	local first = {}
	for _, g in ipairs(p.layout.groups) do first[g.set] = first[g.set] or g.test end
	eq({ first[1], first[2], first[3], first[4] }, { "rb4l", "rb3", "rb2", "rb4l" })
	local zones = logic.showcaseZones(p.layout, 0, 0)
	local letters = {}
	for _, z in ipairs(zones) do
		ok(z.id:match("^microg%d+[abhijklm]$") and #z.id <= 12, z.id)
		eq(logic.slZoneLabel(z.id), z.id)
		letters[z.ab] = z.id:sub(-1)
	end
	eq(letters, { game = "b", sl = "a", sl_rturbo = "h", sl_rmatch = "i", sl_rout1 = "j", sl_r2exit = "k", sl_rspiral = "l", sl_rspread = "m" })
	-- the by_ab text Smart Lanes logs on receipt, byte for byte (its six ring modes in its order)
	local payload = logic.slZonesPayload(zones, "s1-2-3")
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local op, list = Zl.validate(payload)
	eq(op, "set")
	eq(logic.slZonesByAb(payload.zones), Zl.byAbText(list))
	eq(logic.slZonesByAb(payload.zones), "game:4,sl:4,sl_phases:0,sl_rturbo:4,sl_rmatch:4,sl_rout1:4,sl_r2exit:4,sl_rspiral:4,sl_rspread:4")
	for _, m in ipairs(bench.RING_MODES) do ok(logic.SL_ZONE_AB[m], m) end
	for _, t in ipairs(p.layout.towns) do ok(logic.isTestTownName(t.name) and #t.name <= 31, t.name) end
	local info = { w = KM16, h = KM16, plan = p, year = 1950, slPresent = true, sl = bench.slSettings({}), slModes = Zl.AB }
	ok(bench.startLine(sh, info, 3):find(" pop=600 pool=yes rank=yes$") ~= nil, bench.startLine(sh, info, 3))
	eq(bench.problems(sh, info), {})
	-- the variants
	eq(bench.VARIANTS.rb3.file, logic.ENTRY_FILE)
	eq(bench.VARIANTS.rb3.fixed.sqst_entry_ring, 2)
	eq(bench.VARIANTS.rb4l.fixed.sqrb_lanes, 3)
	eq(bench.VARIANTS.rb4l.fixed.sqrb_arm_type, 6)
	eq(bench.VARIANTS.rb4.fixed.sqrb_lanes, 2)
	eq(logic.showcaseArms({ file = logic.ENTRY_FILE, params = bench.VARIANTS.rb3.fixed }), { 0, 90, 180, 270 })
end)

test("sheet 4 v5: per ring size twins on the plain ring and on the mid-node ring, one set each; modes <ab>@<geom>, own letters on the mid ring", function()
	local sh = bench.sheet("s4")
	eq({ sh.id, sh.key, sh.version, sh.pop, sh.rank, sh.roundRobin, sh.slLights }, { "bench_s4", "s4", 5, nil, true, nil, true })
	eq(#sh.tests, 3)
	local ids = {}
	for i, t in ipairs(sh.tests) do
		ids[i] = t.id
		eq(t.geoms, { plain = 1, mid = 2 }, t.id)
		eq(t.towns, { "N", "E", "S", "W" }, t.id)
		eq(t.sets, 1, t.id)
	end
	eq(ids, { "rb2v", "rb3v", "rb4v" })
	-- plain = what players have today (R&I Nodes between arms Off / the entry ring without nodes), mid = v4's rings
	eq({ sh.tests[1].variants[1], sh.tests[1].variants[2] }, { bench.VARIANTS.rb2t, bench.VARIANTS.rb2tm })
	eq({ sh.tests[2].variants[1], sh.tests[2].variants[2] }, { bench.VARIANTS.rb3, bench.VARIANTS.rb3m })
	eq({ sh.tests[3].variants[1], sh.tests[3].variants[2] }, { bench.VARIANTS.rb4l, bench.VARIANTS.rb4lm })
	eq(bench.VARIANTS.rb2t.fixed.sqrb_dev_ring_mid, nil)
	eq(bench.VARIANTS.rb3.fixed.sqst_entry_mid, nil)
	eq(sh.tests[1].twins, { "game@plain", "sl@plain", "game@mid", "sl_rsplit@mid", "sl_rmid@mid" })
	eq(sh.tests[2].twins, { "game@plain", "sl@plain", "game@mid", "sl_rsplit@mid" })
	eq(sh.tests[3].twins, sh.tests[2].twins)
	eq(sh.tests[2].compare, { { "sl_rsplit@mid", "game@plain" }, { "sl_rsplit@mid", "sl@plain" }, { "game@mid", "game@plain" }, { "sl@plain", "game@plain" } })
	eq(#sh.tests[1].compare, 6)
	eq({ sh.tests[1].linkLanes, sh.tests[2].linkLanes, sh.tests[3].linkLanes }, { 4, 0, 0 })
	-- twin modes: the Smart Lanes mode stays ab; mid twins get their own letter and " mid" names
	local m = bench.twinMode("game@mid")
	eq({ m.ab, m.twin, m.label, m.geom }, { "game", "p", "Game default mid", "mid" })
	local pl = bench.twinMode("sl@plain")
	eq({ pl.ab, pl.twin, pl.label, pl.geom }, { "sl", "a", "Smart lanes", "plain" })
	eq(bench.twinMode("sl_rsplit").twin, "n")
	eq(bench.twinMode("nope@mid"), nil)
	eq(bench.needs(sh), { "sl_rsplit", "sl_rmid" })
	local sp = bench.spec(sh)
	eq(sp.growTarget, 400)
	eq(sp.kinds, { "rb2v", "rb3v", "rb4v" })
	local p = bench.plan(KM16, KM16, M, sh, 1)
	eq(#p.cut, 0)
	eq(#p.problems, 0)
	ok(bench.planText(p, KM16, KM16):match("^13 junctions, 52 towns %(~21k people%), about [%d.]+ min to build; 16.0 x 16.0 km map: everything fits$") ~= nil,
		bench.planText(p, KM16, KM16))
	eq(bench.testLine(sh, p.tests[2]), "[SQST] BENCH_TEST sheet=s4 id=rb3v title=Roundabout,_3-lane_ring,_4_country_large_arms,_plain_and_with_mid_nodes kind=rb variants=RB_3-lane,RB_3-lane_mid twins=game@plain,sl@plain,game@mid,sl_rsplit@mid compare=sl_rsplit@mid:game@plain,sl_rsplit@mid:sl@plain,game@mid:game@plain,sl@plain:game@plain sets=1/1 groups=4 towns=16 towns_per_twin=4 pop=400 lights=game")
	-- each twin built on its geometry's variant, with its geom
	local byId = {}
	for _, g in ipairs(p.layout.groups) do
		ok(g.geom == "plain" or g.geom == "mid", g.name)
		local want = g.geom == "mid" and 2 or 1
		local t = (g.test == "rb2v" and sh.tests[1]) or (g.test == "rb3v" and sh.tests[2]) or sh.tests[3]
		eq(g.place.case_.id, t.variants[want].id, g.name)
		eq(g.variant, t.variants[want].label, g.name)
	end
	local zones = logic.showcaseZones(p.layout, 0, 0)
	eq(#zones, 13)
	local seen = {}
	for _, z in ipairs(zones) do
		ok(z.id:match("^s4g%d+[abpst]$") and #z.id <= 12, z.id)
		ok(not seen[z.id], "unique id " .. z.id)
		seen[z.id] = true
		ok(logic.showcaseZoneLine(z, true):find(" geom=" .. z.geom, 1, true), "zone line names its geometry")
		byId[z.id] = z
	end
	eq({ byId.s4g1b.ab, byId.s4g1b.geom, byId.s4g1p.ab, byId.s4g1p.geom, byId.s4g1s.ab, byId.s4g1t.ab },
		{ "game", "plain", "game", "mid", "sl_rsplit", "sl_rmid" })
	-- Smart Lanes takes the payload (zone ab = its modes), by_ab byte for byte
	local payload = logic.slZonesPayload(zones, "s4-1-2")
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local op, list = Zl.validate(payload)
	eq(op, "set")
	eq(#list, 13)
	eq(logic.slZonesByAb(payload.zones), Zl.byAbText(list))
	eq(logic.slZonesByAb(payload.zones), "game:6,sl:3,sl_phases:0,sl_rsplit:3,sl_rmid:1")
	for _, tw in ipairs(p.layout.towns) do ok(logic.isTestTownName(tw.name) and #tw.name <= 31, tw.name) end
	local info = { w = KM16, h = KM16, plan = p, year = 1950, slPresent = true, sl = bench.slSettings({}), slModes = Zl.AB }
	ok(bench.startLine(sh, info, 3):find("^%[SQST%] BENCH_START sheet=s4 spec=bench_s4@5 seed=3 ") ~= nil, bench.startLine(sh, info, 3))
	eq(bench.problems(sh, info), {})
end)

test("sheet 5: ring lane use, a 2-lane ring (game / sl_rturbo / sl_rmid2 / sl_rmatch) and a 4-lane ring (game / sl_rturbo / sl_rturbo_in / sl_rspread), 3 sets each, one traffic mix per set (town sizes per arm); letters w and y; by_ab as Smart Lanes", function()
	local sh = bench.sheet("s5")
	eq({ sh.id, sh.key, sh.version, sh.pop, sh.rank, sh.slLights, sh.button }, { "bench_s5", "s5", 1, 350, true, true, nil })
	eq(#sh.tests, 2)
	local lu2, lu4 = sh.tests[1], sh.tests[2]
	eq({ lu2.id, lu4.id }, { "lu2", "lu4" })
	eq({ lu2.variants[1], lu4.variants[1] }, { bench.VARIANTS.rb4, bench.VARIANTS.rb4l })
	eq(lu2.twins, { "game", "sl_rturbo", "sl_rmid2", "sl_rmatch" })
	eq(lu4.twins, { "game", "sl_rturbo", "sl_rturbo_in", "sl_rspread" })
	-- every layout vs game and vs sl_rturbo (what sl wrote there when Sheet 5 ran; matched on the 2-lane ring since 2026-10-15)
	eq(lu2.compare, { { "sl_rturbo", "game" }, { "sl_rmid2", "game" }, { "sl_rmatch", "game" }, { "sl_rmid2", "sl_rturbo" }, { "sl_rmatch", "sl_rturbo" } })
	eq(lu4.compare, { { "sl_rturbo", "game" }, { "sl_rturbo_in", "game" }, { "sl_rspread", "game" }, { "sl_rturbo_in", "sl_rturbo" }, { "sl_rspread", "sl_rturbo" } })
	for _, t in ipairs(sh.tests) do
		eq({ t.sets, t.mixes, t.ringMix, t.linkLanes }, { 3, { "even", "straight", "adjacent" }, true, 0 }, t.id)
	end
	eq(bench.needs(sh), { "sl_rturbo", "sl_rmid2", "sl_rmatch", "sl_rturbo_in", "sl_rspread" })
	-- the mixes: equal people per ring (4 x 350 = 2 x 600 + 2 x 100), opposite / neighbouring large towns
	eq({ bench.mixPop("even", "N") }, { 350 })
	eq({ bench.mixPop("straight", "N") }, { 600, "large" })
	eq({ bench.mixPop("straight", "S") }, { 600, "large" })
	eq({ bench.mixPop("straight", "E") }, { 100, "small" })
	eq({ bench.mixPop("adjacent", "E") }, { 600, "large" })
	eq({ bench.mixPop("adjacent", "W") }, { 100, "small" })
	for _, m in ipairs(bench.LU_MIXES) do
		local sum = 0
		for _, side in ipairs({ "N", "E", "S", "W" }) do sum = sum + bench.mixPop(m, side) end
		eq(sum, 1400, m)
	end
	local p = bench.plan(KM16, KM16, M, sh, 1)
	eq(#p.cut, 0)
	eq(#p.problems, 0)
	ok(bench.planText(p, KM16, KM16):match("^24 junctions, 96 towns %(~34k people%), about [%d.]+ min to build; 16.0 x 16.0 km map: everything fits$") ~= nil,
		bench.planText(p, KM16, KM16))
	-- each set one mix, every twin of the set the same; a test's sets go even, straight, adjacent
	local setMix, setTest = {}, {}
	for _, g in ipairs(p.layout.groups) do
		ok(g.mix ~= nil and g.ringMix == true, g.name)
		if setMix[g.set] ~= nil then eq(g.mix, setMix[g.set], g.name) end
		setMix[g.set], setTest[g.set] = g.mix, g.test
		for _, ti in ipairs(g.towns) do
			local t = p.layout.towns[ti]
			ok(t.pop ~= nil, t.name)
			-- a town below a Medium town's 400 is created with that capacity
			eq(t.townCaps, t.pop < 400 and math.floor(t.pop) or nil, t.name)
			ok(logic.isTestTownName(t.name) and #t.name <= 31, t.name)
			if g.mix == "even" then eq(t.pop, 350, t.name) ok(not t.name:match("large") and not t.name:match("small"), t.name) end
			if t.name:match(" large$") then eq(t.pop, 600, t.name) end
			if t.name:match(" small$") then eq({ t.pop, t.townCaps }, { 100, 100 }, t.name) end
			if g.mix == "straight" then eq(t.name:match(" ([NESW]) ") == "N" or t.name:match(" ([NESW]) ") == "S", t.pop == 600, t.name) end
			if g.mix == "adjacent" then eq(t.name:match(" ([NESW]) ") == "N" or t.name:match(" ([NESW]) ") == "E", t.pop == 600, t.name) end
		end
	end
	eq({ setMix[1], setMix[2], setMix[3], setMix[4], setMix[5], setMix[6] }, { "even", "straight", "adjacent", "even", "straight", "adjacent" })
	eq({ setTest[1], setTest[4] }, { "lu2", "lu4" })
	-- zones: mix on the zone line, letters w / y, ids s5g<k><letter>
	local zones = logic.showcaseZones(p.layout, 0, 0)
	eq(#zones, 24)
	local letters = {}
	for _, z in ipairs(zones) do
		ok(z.id:match("^s5g%d[bhiwym]$") and #z.id <= 12, z.id)
		eq(logic.slZoneLabel(z.id), z.id)
		letters[z.ab] = z.id:sub(-1)
		ok(logic.showcaseZoneLine(z, true):find(" test=" .. z.test .. " variant=.* mix=" .. z.mix .. "$") ~= nil, logic.showcaseZoneLine(z, true))
		eq(z.ringMix, true)
	end
	eq(letters, { game = "b", sl_rturbo = "h", sl_rmatch = "i", sl_rspread = "m", sl_rmid2 = "w", sl_rturbo_in = "y" })
	-- Smart Lanes takes the payload; by_ab byte for byte (sl_rmid2, sl_rturbo_in after sl_auto, only when > 0)
	local payload = logic.slZonesPayload(zones, "s5-1-2")
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local op, list = Zl.validate(payload)
	eq(op, "set")
	eq(#list, 24)
	eq(logic.slZonesByAb(payload.zones), Zl.byAbText(list))
	eq(logic.slZonesByAb(payload.zones), "game:6,sl:0,sl_phases:0,sl_rturbo:6,sl_rmatch:3,sl_rspread:3,sl_rmid2:3,sl_rturbo_in:3")
	local only = { { x = 0, y = 0, r = 50, ab = "sl_auto" }, { x = 0, y = 0, r = 50, ab = "sl_rturbo_in" } }
	eq(logic.slZonesByAb(only), "game:0,sl:0,sl_phases:0,sl_auto:1,sl_rturbo_in:1")
	local _, l2 = Zl.validate({ op = "set", run = "s5-1-3", zones = only })
	eq(logic.slZonesByAb(only), Zl.byAbText(l2))
	for _, m in ipairs({ "sl_rmid2", "sl_rturbo_in" }) do
		ok(logic.SL_ZONE_AB[m], m)
		eq(bench.twinMode(m).ab, m)
	end
	-- the log lines
	eq(bench.testLine(sh, p.tests[1]), "[SQST] BENCH_TEST sheet=s5 id=lu2 title=Roundabout,_2-lane_ring,_4_country_medium_arms,_three_traffic_mixes kind=rb variants=RB4_2L twins=game,sl_rturbo,sl_rmid2,sl_rmatch compare=sl_rturbo:game,sl_rmid2:game,sl_rmatch:game,sl_rmid2:sl_rturbo,sl_rmatch:sl_rturbo sets=3/3 groups=12 towns=48 towns_per_twin=4 pop=350 lights=game mixes=even,straight,adjacent pops=large:600,small:100,even:350 ring_mix=yes")
	local info = { w = KM16, h = KM16, plan = p, year = 1950, slPresent = true, sl = bench.slSettings({}), slModes = Zl.AB }
	ok(bench.startLine(sh, info, 3):find("^%[SQST%] BENCH_START sheet=s5 spec=bench_s5@1 seed=3 ") ~= nil, bench.startLine(sh, info, 3))
	eq(bench.problems(sh, info), {})
	-- a Smart Lanes without the two modes: the preflight names them
	local old = { "game", "sl", "sl_rturbo", "sl_rmatch", "sl_rspread" }
	ok(bench.problems(sh, { w = KM16, h = KM16, plan = p, slPresent = true, sl = bench.slSettings({}), slModes = old })[1]:find("sl_rmid2, sl_rturbo_in", 1, true))
end)

test("sheet 6: the mid-node default under heavy traffic: Sheet 4's plain town ring (rb2t), game / sl / sl_rmatch / sl_rturbo, 3 sets one mix each, 2400 people a ring, 30 game min recorded", function()
	local sh = bench.sheet("s6")
	eq({ sh.id, sh.key, sh.version, sh.pop, sh.rank, sh.slLights, sh.recordS }, { "bench_s6", "s6", 1, 600, true, true, 1800 })
	eq(bench.recordS(sh), 1800)
	eq(bench.speed(sh), 2)
	eq(bench.recordS(bench.sheet("s5")), 1200, "the others keep RECORD_S")
	local t = sh.tests[1]
	eq(#sh.tests, 1)
	eq({ t.id, t.sets, t.linkLanes, t.ringMix }, { "hm2", 3, 4, true })
	eq(t.variants[1], bench.VARIANTS.rb2t, "the plain ring: Smart Lanes splits it itself in the sl twin")
	eq(t.twins, { "game", "sl", "sl_rmatch", "sl_rturbo" })
	eq(t.compare, { { "sl", "game" }, { "sl_rmatch", "game" }, { "sl_rturbo", "game" }, { "sl", "sl_rmatch" }, { "sl_rmatch", "sl_rturbo" } })
	eq(bench.needs(sh), { "sl_rmatch", "sl_rturbo" })
	for _, m in ipairs(bench.LU_MIXES) do
		local sum = 0
		for _, side in ipairs({ "N", "E", "S", "W" }) do sum = sum + bench.mixPop(m, side, bench.HM_POPS) end
		eq(sum, 2400, m)
	end
	eq({ bench.mixPop("straight", "N", bench.HM_POPS) }, { 1000, "large" })
	eq({ bench.mixPop("straight", "E", bench.HM_POPS) }, { 200, "small" })
	eq({ bench.mixPop("even", "E", bench.HM_POPS) }, { 600 })
	local p = bench.plan(KM16, KM16, M, sh, 1)
	eq({ p.groups, p.towns, #p.cut }, { 12, 48, 0 })
	local seen = {}
	for _, g in ipairs(p.layout.groups) do
		for _, ti in ipairs(g.towns) do
			local tw = p.layout.towns[ti]
			seen[tw.pop] = true
			-- only the small towns (200) are created below a Medium town's 400
			eq(tw.townCaps, tw.pop < 400 and 200 or nil, tw.name)
			ok(logic.isTestTownName(tw.name) and #tw.name <= 31, tw.name)
		end
	end
	eq(seen, { [600] = true, [1000] = true, [200] = true })
	local zones = logic.showcaseZones(p.layout, 0, 0)
	local letters = {}
	for _, z in ipairs(zones) do
		ok(z.id:match("^s6g[123][abhi]$"), z.id)
		letters[z.ab] = z.id:sub(-1)
	end
	eq(letters, { game = "b", sl = "a", sl_rmatch = "i", sl_rturbo = "h" })
	eq(bench.testLine(sh, p.tests[1]), "[SQST] BENCH_TEST sheet=s6 id=hm2 title=Roundabout,_2-lane_ring,_4_one-lane_town_street_arms,_heavy_traffic,_three_traffic_mixes kind=rb variants=RB_2L_town twins=game,sl,sl_rmatch,sl_rturbo compare=sl:game,sl_rmatch:game,sl_rturbo:game,sl:sl_rmatch,sl_rmatch:sl_rturbo sets=3/3 groups=12 towns=48 towns_per_twin=4 pop=600 lights=game mixes=even,straight,adjacent pops=large:1000,small:200,even:600 ring_mix=yes")
	local info = { w = KM16, h = KM16, plan = p, year = 1950, slPresent = true, sl = bench.slSettings({}), slModes = { "game", "sl", "sl_rmatch", "sl_rturbo" } }
	ok(bench.startLine(sh, info, 3):find(" warmup_s=180 record_s=1800 interval_s=10 speed=2 pop=600 ", 1, true), bench.startLine(sh, info, 3))
	eq(bench.problems(sh, info), {})
end)

test("city lights: the cities (3 pairs of Large grid towns, auto / control side by side), their inner crossings, the enroll payloads, the log lines, the preflight", function()
	local c = bench.CITY
	eq(bench.sheet("city"), c)
	eq(bench.sheet("bench_city"), c)
	for _, s in ipairs(bench.SHEETS) do ok(s ~= c, "not a junction sheet") end
	eq({ bench.recordS(c), bench.speed(c), c.baselineS }, { 6300, 4, 900 })
	local lines, step = bench.cityLines(400)
	eq({ #lines, step, lines[1], lines[9] }, { 9, 80, -320, 320 })
	local p = bench.cityPlan(KM16, KM16, M, c)
	eq({ #p.cities, p.auto, p.control, p.crossings, p.enrolled, p.persons, p.half }, { 6, 3, 3, 486, 243, 18000, 400 })
	local ids, at = {}, {}
	for _, city in ipairs(p.cities) do
		ids[#ids + 1] = city.id
		at[city.id] = { city.x, city.y, city.role, city.ab, city.pair }
		eq(city.crossings, 81)
	end
	eq(ids, { "cityg1v", "cityg1b", "cityg2b", "cityg2v", "cityg3v", "cityg3b" })
	eq(at.cityg1v, { -4000, -2000, "auto", "city_auto", "cityg1" })
	eq(at.cityg2v, { 0, 2000, "auto", "city_auto", "cityg2" })
	eq(at.cityg3b, { 4000, 2000, "control", "city_control", "cityg3" })
	ok(1 / at.cityg2b[1] > 0, "+0, never -0")
	local none, why = bench.cityPlan(8000, 8000, M, c)
	eq(none, nil)
	ok(why:find("need 9.7 x 5.7 km", 1, true), why)
	eq(bench.cityPlanText(p, nil, KM16, KM16), "6 grid cities (3 auto, 3 control), 486 inner crossings lit (243 enrolled), ~18k people; 16.0 x 16.0 km map")
	ok(bench.cityPlanText(nil, why, 8000, 8000):find("^does not fit this 8.0 x 8.0 km map") ~= nil)
	-- no control: one row of auto cities
	local ps = bench.cityPlan(KM16, KM16, M, { city = { pairs = 3, size = 3, pop = 3000, spacing = 4000, control = false } })
	eq({ #ps.cities, ps.auto, ps.control, ps.enrolled }, { 3, 3, 0, 243 })
	-- inner crossings: 4+ streets within 4 m of an inner grid point; the ring's T-junctions, a 3-street inner node and the
	-- town's own nodes between the grid points are left out
	local cx, cy = 1000, -500
	local nodes, id = {}, 100
	for i = -5, 5 do
		for j = -5, 5 do
			id = id + 1
			local ring = math.abs(i) == 5 or math.abs(j) == 5
			local deg = ring and 3 or 4
			if i == 1 and j == 1 then deg = 3 end
			nodes[#nodes + 1] = { id, cx + i * 80 + (i == 2 and 2.5 or 0), cy + j * 80, deg }
		end
	end
	nodes[#nodes + 1] = { 999, cx + 40, cy + 40, 4 }       -- between grid points
	nodes[#nodes + 1] = { 998, cx + 80, cy + 85, 4 }       -- 5 m off a grid point
	local got = bench.cityInterior(nodes, cx, cy, 400)
	eq(#got, 80)
	for k = 2, #got do ok(got[k - 1][1] < got[k][1]) end
	for _, e in ipairs(got) do
		ok(e[1] ~= 999 and e[1] ~= 998, tostring(e[1]))
		eq(#e, 4)
		eq(e[4], 4, "its streets")
	end
	eq(bench.cityInterior({}, 0, 0, 400), {})
	-- payloads: 60 nodes each, op add, src stress; Smart Lanes' own validator takes every one
	local entries = {}
	for k = 1, 130 do entries[k] = { 5000 + k, k * 1.5, -k } end
	local pl = bench.cityPayloads(entries)
	eq(#pl, 3)
	eq({ #pl[1].nodes, #pl[2].nodes, #pl[3].nodes, pl[1].op, pl[1].src }, { 60, 60, 10, "add", "stress" })
	eq(pl[3].nodes[10], { 5130, 195, -130 })
	local Auto = slRequire("smart_lanes/sl_auto.lua")
	for _, one in ipairs(pl) do
		local op, list, src = Auto.validate(one)
		eq({ op, #list, src }, { "add", #one.nodes, "stress" })
	end
	-- lines
	local city = p.cities[1]
	eq(bench.cityLine(city, -4000, -2000, 77, 81, 12, 69, 0), "[SQST] CITY id=cityg1v pair=cityg1 role=auto town=77 name=City_auto_1 x=-4000 y=-2000 half=400 crossings=81 found=81 lit_before=12 forced=69 refused=0")
	eq(bench.cityEnrollLine("city-5", "add", 3, 243, 5, 900, true), "[SQST] CITY_ENROLL run=city-5 op=add cities=3 nodes=243 events=5 baseline_s=900 by=bench smart_lanes=yes")
	local z = bench.cityZone(city)
	z.built = true
	eq(logic.showcaseZoneLine(z, false), "[SQST] showcase zone id=cityg1v pair=cityg1 ab=city_auto kind=other type=City_auto_1 x=-4000 y=-2000 r=400 r_from=est towns=1 match=yes")
	local fz = ug_require("square_stress_test::/stress/stress_flow.tl").zonesFromShowcase({ z }, "city-5")
	eq({ #fz, fz[1].twin, fz[1].ab, fz[1].rm, fz[1].measure }, { 1, "cityg1v", "city_auto", 600, "circle" })
	-- preflight and BENCH_START
	local Zl = dofile("mods/square_smart_lanes/content/smart_lanes/sl_zones.lua")
	local good = { w = KM16, h = KM16, cityPlan = p, slPresent = true, sl = bench.slSettings({ sqperf_log = 2 }), slModes = Zl.AB, year = 1950 }
	eq(bench.problems(c, good), {})
	local function with(k, v)
		local t = {}
		for a, b in pairs(good) do t[a] = b end
		t[k] = v
		return bench.problems(c, t)
	end
	local noPerf = with("sl", bench.slSettings({}))
	eq(#noPerf, 1)
	ok(noPerf[1]:find("Debug: performance log", 1, true))
	good.perfAll = true
	eq(with("sl", bench.slSettings({})), {}, "the DEV master switch counts")
	good.perfAll = nil
	ok(with("slModes", { "game", "sl" })[1]:find("automatic re-timing", 1, true))
	ok(with("slPresent", false)[1]:find("Smart Lanes is not enabled", 1, true))
	ok(with("cityPlan", nil)[1]:find("do not fit", 1, true))
	eq(bench.startLine(c, good, 9), "[SQST] BENCH_START sheet=city spec=bench_city@2 seed=9 map=16000x16000 tests=0 groups=0 towns=6 year=1950 sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=" .. table.concat(Zl.AB, ",") .. " warmup_s=180 record_s=6300 interval_s=10 speed=4 pop=3000 pool=no rank=no city=yes cities=6 auto=3 control=3 crossings=486 enrolled=243 baseline_s=900 sl_perf=on layout=plain busy=0 role_swap=0")
end)

test("run: the city run goes preflight -> clear -> year -> the cities' build -> Smart Lanes idle -> warm-up at 4x -> baseline -> enroll -> after -> unenroll, speed 1 -> a shot over each city from 700 m -> BENCH_DONE", function()
	api.engine.config.getModParams = function() return { square_smart_lanes = { sqrl_auto = 1, sqperf_log = 2 } } end
	slz.modes = { "game", "sl", "sl_phases", "sl_auto" }
	clStub.last = { run = "city-21", crossings = {}, plan = {} }
	ok(br.start("city", 21))
	tick(3)
	ok(logText():find("[SQST] BENCH_START sheet=city spec=bench_city@2 seed=21 ", 1, true), logText())
	ok(logText():find(" city=yes cities=6 auto=3 control=3 crossings=486 enrolled=243 baseline_s=900 sl_perf=on", 1, true), logText())
	tick(6)
	eq(DATES, { 1950 })
	ok(table.concat(calls, " "):find("towns:2 roads city_build", 1, true), table.concat(calls, " "))
	eq(built, nil, "no junction build")
	clStub.onDone({ { id = "cityg1v", x = -4000, y = -2000, built = true }, { id = "cityg1b", x = -4000, y = 2000, built = true } })
	tick(3)
	eq(br.phase, "warmup")
	eq(SPEEDS, { 4 })
	tick(4, 50000)   -- 200 game s
	eq(br.phase, "record")
	ok(br.status():find("baseline", 1, true), br.status())
	tick(17, 50000)  -- 850 game s: still the baseline
	ok(not table.concat(calls, " "):find("city_enroll", 1, true))
	tick(2, 50000)   -- 950
	ok(table.concat(calls, " "):find("city_enroll:city-21", 1, true), table.concat(calls, " "))
	ok(logText():find("phase=record gt=%d+ ms=%d+ enroll=243") ~= nil, logText())
	ok(br.status():find("automatic timing on", 1, true), br.status())
	flState.samples = 450
	tick(108, 50000)  -- 6350 game s
	eq(br.phase, "shots")
	eq(SPEEDS, { 4, 1 })
	ok(table.concat(calls, " "):find("city_unenroll", 1, true))
	tick(80)
	eq(#SHOTS, 3, "the primer and two cities")
	eq({ CAMS[1].x, CAMS[1].y, CAMS[1].z }, { -4000, -2000, 700 })
	local all = logText()
	ok(all:find("[SQST] BENCH_SHOT sheet=city n=2 id=city:cityg1b x=-4000 y=2000 ok=true", 1, true), all)
	ok(all:find("[SQST] BENCH_DONE sheet=city spec=bench_city@2 seed=21 ok=yes samples=450 speed=4 ", 1, true), all)
end)

test("city lights options: Layout / Busy / Baseline / Swap roles make the sheet; the plan's crossings per layout, the roles swapped, the log keys; the defaults are v1's run", function()
	local def = bench.citySheet(nil)
	eq({ def.version, def.baselineS, def.recordS, def.city.pop, def.city.layout, def.city.busy, def.city.swap, def.city.weights },
		{ 2, 900, 6300, 3000, "plain", false, false, nil }, "the defaults: v1's run (recordS 6300, baseline 900)")
	ok(def ~= bench.CITY and def.city ~= bench.CITY.city, "a copy")
	local p0 = bench.cityPlan(KM16, KM16, M, def)
	local p1 = bench.cityPlan(KM16, KM16, M, bench.CITY)
	eq({ p0.crossings, p0.enrolled, p0.layout }, { p1.crossings, p1.enrolled, "plain" })
	-- hourglass + busy + 30 min + swapped
	local s = bench.citySheet({ layout = 2, busy = true, baseline = 2, swap = true })
	eq({ s.baselineS, s.recordS, s.city.pop, s.city.layout, s.city.busy, s.city.swap, s.city.weights },
		{ 1800, 7200, 7500, "hourglass", true, true, { 0.0, 0.0, 0.25, 1.0 } })
	local p = bench.cityPlan(KM16, KM16, M, s)
	eq({ p.crossings, p.enrolled, p.layout, p.neck, p.holes, p.x4, p.t3, p.swap, p.busy, p.persons }, { 450, 225, "hourglass", 3, 0, 61, 14, true, true, 45000 })
	local at = {}
	for _, c in ipairs(p.cities) do at[c.id] = { c.x, c.y, c.crossings, c.layout } end
	eq(at.cityg1v, { -4000, 2000, 75, "hourglass" }, "swapped: the auto city of pair 1 on the second row")
	eq(at.cityg1b, { -4000, -2000, 75, "hourglass" })
	eq(at.cityg2v, { 0, -2000, 75, "hourglass" })
	eq(bench.cityPlanText(p, nil, KM16, KM16), "6 grid cities (3 auto, 3 control, roles swapped, hourglass with a 3-street neck), 450 inner crossings lit (225 enrolled), ~45k people; 16.0 x 16.0 km map")
	eq(bench.cityOptionKeys(s), "layout=hourglass busy=1 baseline_s=1800 role_swap=1")
	eq(bench.cityOptionsText(s), "Layout: hourglass (a band through the middle where only the 3 central streets go on), 75 lit crossings per city. People: about 7500 wanted per city (Busy; the grid's lots may cap it). Baseline: 30 game min, then 90 after the automatic timing starts. Roles: swapped (the other city of each pair is auto).")
	-- holes: 4 per city from the seed, every pattern the same counts
	local h = bench.citySheet({ layout = 3 })
	local ph = bench.cityPlan(KM16, KM16, M, h)
	eq({ ph.crossings, ph.enrolled, ph.holes, ph.x4, ph.t3 }, { 462, 231, 4, 61, 16 })
	eq({ bench.cityHolesPattern(1), bench.cityHolesPattern(12), bench.cityHolesPattern(13), bench.cityHolesPattern(778824) }, { 1, 12, 1, (778824 - 1) % 12 + 1 })
	eq(bench.cityLayout(h, 25).holes, bench.cityLayout(h, 1).holes, "seed 25 = pattern 1")
	ok(bench.cityOptionsText(h):find("Layout: 4 holes of 2 x 2 blocks", 1, true))
	-- the v2 lines
	local c = p.cities[2]
	eq(c.id, "cityg1v")
	eq(bench.cityLine(c, 1, 2, 7, 75, 10, 65, 0, { layout = "hourglass", neck = 3, holes = 0, found4 = 61, found3 = 14, lit4 = 61, lit3 = 14, pop = 2500.4, gapStreets = 0, gapRemoved = 0 }),
		"[SQST] CITY id=cityg1v pair=cityg1 role=auto town=7 name=City_auto_1 x=1 y=2 half=400 crossings=75 found=75 lit_before=10 forced=65 refused=0 layout=hourglass neck_streets=3 holes=0 found4=61 found3=14 lit4=61 lit3=14 pop=2500 gap_streets=0 gap_removed=0")
	eq(bench.cityGapLine(c, "end", 2, 0), "[SQST] CITY_GAPS id=cityg1v pair=cityg1 role=auto at=end layout=hourglass gap_streets=2 removed=0")
	eq(bench.cityEnrollLine("city-5", "add", 3, 225, 4, 1800, true, s), "[SQST] CITY_ENROLL run=city-5 op=add cities=3 nodes=225 events=4 baseline_s=1800 by=bench smart_lanes=yes layout=hourglass busy=1 role_swap=1")
	-- a 3-street inner node counts with minDeg 3 (the funnel layouts' T)
	local nodes = { { 1, 80, 80, 3 }, { 2, 160, 80, 4 }, { 3, 400, 80, 3 } }
	eq(#bench.cityInterior(nodes, 0, 0, 400), 1)
	eq(bench.cityInterior(nodes, 0, 0, 400, 3), { { 1, 80, 80, 3 }, { 2, 160, 80, 4 } }, "the ring's T stays out")
end)

test("run: the city run with options: Hourglass + Busy + 30 min baseline + Swap roles in BENCH_START, the enroll after 30 game min, the gaps counted at the end; Same seed repeats the last city seed", function()
	api.engine.config.getModParams = function() return { square_smart_lanes = { sqrl_auto = 1, sqperf_log = 2 } } end
	slz.modes = { "game", "sl", "sl_phases", "sl_auto" }
	clStub.last = { run = "city-21", crossings = {}, plan = {} }
	br.cityUi.layout, br.cityUi.busy, br.cityUi.baseline, br.cityUi.swap = 2, true, 2, true
	ok(br.start("city"))
	local seed = br.lastCitySeed
	ok(seed ~= nil)
	tick(3)
	ok(logText():find(" record_s=7200 interval_s=10 speed=4 pop=7500 pool=no rank=no city=yes cities=6 auto=3 control=3 crossings=450 enrolled=225 baseline_s=1800 sl_perf=on layout=hourglass busy=1 role_swap=1", 1, true), logText())
	tick(6)
	clStub.onDone({ { id = "cityg1v", x = -4000, y = 2000, built = true } })
	tick(3)
	eq(br.phase, "warmup")
	tick(4, 50000)
	eq(br.phase, "record")
	tick(35, 50000)  -- 1750 game s: still the baseline
	ok(not table.concat(calls, " "):find("city_enroll", 1, true))
	tick(2, 50000)
	ok(table.concat(calls, " "):find("city_enroll:", 1, true), table.concat(calls, " "))
	tick(110, 50000)
	eq(br.phase, "shots")
	ok(table.concat(calls, " "):find("city_unenroll city_gaps:end", 1, true), table.concat(calls, " "))
	tick(80)
	ok(logText():find("BENCH_DONE sheet=city spec=bench_city@2 seed=" .. seed, 1, true), logText())
	-- Same seed: the next press repeats it
	br.cityUi.sameSeed = true
	clear_logs()
	ok(br.start("city"))
	eq(br.lastCitySeed, seed)
	tick(3)
	ok(logText():find("BENCH_START sheet=city spec=bench_city@2 seed=" .. seed .. " ", 1, true), logText())
	br.cityUi.layout, br.cityUi.busy, br.cityUi.baseline, br.cityUi.swap, br.cityUi.sameSeed = 1, false, 1, false, false
end)

test("run: the city run steps 4x down to 2x on a skipped sample; an abort after the enroll unenrolls; the preflight wants the performance log", function()
	api.engine.config.getModParams = function() return { square_smart_lanes = { sqrl_auto = 1 } } end
	slz.modes = { "game", "sl", "sl_auto" }
	ok(not br.start("city", 3))
	ok(not logText():find("BENCH_START", 1, true))
	api.engine.config.getModParams = function() return { square_smart_lanes = { sqrl_auto = 1 }, square_sqperf_all = {} } end
	clStub.last = { run = "city-3", crossings = {}, plan = {} }
	ok(br.start("city", 3))
	tick(9)
	clStub.onDone({})
	tick(3)
	eq(br.phase, "warmup")
	flState.skipped = 1
	tick(1, 1000)
	eq(SPEEDS, { 4, 2 })
	ok(logText():find("phase=warmup gt=%d+ ms=%d+ speed=2 %(a sample was skipped at 4x%)") ~= nil, logText())
	flState.skipped = 0
	tick(24, 50000)
	ok(table.concat(calls, " "):find("city_enroll", 1, true), table.concat(calls, " "))
	rt.clearQueue()
	tick(1)
	ok(logText():find("BENCH_ABORT sheet=city phase=record reason=Clear_queue", 1, true), logText())
	ok(table.concat(calls, " "):find("city_unenroll", 1, true))
end)
