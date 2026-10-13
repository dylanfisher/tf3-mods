-- The traffic log (plans/square_stress_test/FLOW.md, FLOW_PLAN.md steps 4-5): stress/stress_flow.tl (zones,
-- lookup, aggregation, lines, bus laps) and gui/stress_flow_log.tl (the sampler) against tests/square_stress_test/
-- flow_fake.lua. tests/tools/test_flow_report.py runs flow_e2e.lua and feeds its lines to tools/flow_report.py.

local F

before_each(function()
	reset_modules()
	clear_logs()
	F = assert(loadfile("tests/square_stress_test/flow_fake.lua", "t", _ENV))()
end)

local function flow()
	return ug_require "square_stress_test::/stress/stress_flow.tl"
end

local function byKind(lines, kind)
	local out = {}
	for _, l in ipairs(lines) do if F.kind(l) == kind then out[#out + 1] = l end end
	return out
end

---------------------------------------------------------------------------
-- Pure part

test("num / word / list / counts: FLOW.md number and value format", function()
	local f = flow()
	eq(f.num(nil), "-")
	eq(f.num(0 / 0), "-")
	eq(f.num(7), "7")
	eq(f.num(81400000), "81400000")
	eq(f.num(13.94), "13.9")
	eq(f.num(0.7191), "0.719")
	eq(f.num(1234.5), "1.23e+03")
	eq(f.word("SQST Bus 3"), "SQST_Bus_3")
	eq(f.word(""), "-")
	eq(f.list({ 1, 2.5, 3 }, 2), "1,2.5,+1")
	eq(f.list({}, 3), "-")
	eq(f.counts({ b = 1, a = 3, c = 0 }), "a:3,b:1")
	eq(f.counts({}), "-")
	eq(f.median({ 3, 1, 2 }), 2)
	eq(f.median({ 4, 1, 2, 3 }), 2.5)
	eq(f.median({}), nil)
end)

test("zonesFromShowcase: built twins only, FLOW kinds, match, labels without spaces", function()
	local f = flow()
	local zs = f.zonesFromShowcase(F.showcase(), "s1-2-3")
	eq(#zs, 4, "g2b was not built")
	eq({ zs[1].zone, zs[1].twin, zs[1].pair, zs[1].ab, zs[1].kind, zs[1].src, zs[1].label, zs[1].match, zs[1].idFrom, zs[1].scRun },
		{ 1, "g1a", "g1", "sl", "rb", "placement", "Magic_Roundabout", "yes", "showcase", "s1-2-3" })
	eq({ zs[3].twin, zs[3].kind, zs[3].match, zs[3].reason }, { "g2a", "x", "no", "town" })
	eq({ zs[4].twin, zs[4].kind, zs[4].zone }, { "g3a", "ix", 4 })
	eq(#f.zonesFromShowcase(nil, nil), 0)
end)

test("zonesFromSaved: stored id / pair labels; else ids recomputed from the payload order; broken entries skipped", function()
	local f = flow()
	local zs = f.zonesFromSaved({ { x = 1, y = 2, r = 120, ab = "sl", id = "g7a", pair = "g7" }, { x = 5, y = 6, r = 80, ab = "game", id = "g7b", pair = "g7" } }, "s9")
	eq({ zs[1].twin, zs[1].pair, zs[1].ab, zs[1].src, zs[1].idFrom, zs[1].label, zs[1].kind, zs[1].scRun }, { "g7a", "g7", "sl", "sl_zones", "sl", "g7a", "other", "s9" })
	eq(zs[2].twin, "g7b")
	-- an older Smart Lanes: no labels; sets in order, each set's twins in SHOWCASE_AB order (sl, game, sl_phases)
	local old = f.zonesFromSaved({
		{ x = 0, y = 0, r = 10, ab = "sl" }, { x = 1, y = 0, r = 10, ab = "game" },
		{ x = 2, y = 0, r = 10, ab = "sl" }, { x = 3, y = 0, r = 10, ab = "game" }, { x = 4, y = 0, r = 10, ab = "sl_phases" },
		{ x = 5, y = 0, r = 10, ab = "sl" },
		{ x = 0 / 0, y = 0, r = 10, ab = "sl" }, { x = 6, y = 0, r = 0, ab = "game" }, "junk", { x = 7, y = 0, r = 10 },
		{ x = 8, y = 0, r = 10, ab = "game" } })
	local ids = {}
	for i, z in ipairs(old) do ids[i] = z.twin .. "/" .. z.pair .. "/" .. z.idFrom end
	eq(ids, { "g1a/g1/order", "g1b/g1/order", "g2a/g2/order", "g2b/g2/order", "g2c/g2/order", "g3a/g3/order", "g3b/g3/order" })
	eq(#f.zonesFromSaved(nil, nil), 0)
	-- the Lights showcase's sets after a reload: sl, game, sl_phases, sl_lock (twin d; 2026-10-13, replaces sl_fan,
	-- which older saves still have): one set each, the fourth twin's id ends in d
	local lights = f.zonesFromSaved({
		{ x = 0, y = 0, r = 10, ab = "sl" }, { x = 1, y = 0, r = 10, ab = "game" }, { x = 2, y = 0, r = 10, ab = "sl_phases" },
		{ x = 3, y = 0, r = 10, ab = "sl_lock" },
		{ x = 4, y = 0, r = 10, ab = "sl" }, { x = 5, y = 0, r = 10, ab = "game" }, { x = 6, y = 0, r = 10, ab = "sl_phases" },
		{ x = 7, y = 0, r = 10, ab = "sl_fan" } })
	local lids = {}
	for i, z in ipairs(lights) do lids[i] = z.twin .. "/" .. z.ab end
	eq(lids, { "g1a/sl", "g1b/game", "g1c/sl_phases", "g1d/sl_lock", "g2a/sl", "g2b/game", "g2c/sl_phases", "g2d/sl_fan" })
	-- the mixed Lights showcase's sets: sl, game, sl_exitfan (twin e)
	local mixed = f.zonesFromSaved({
		{ x = 0, y = 0, r = 10, ab = "sl" }, { x = 1, y = 0, r = 10, ab = "game" }, { x = 2, y = 0, r = 10, ab = "sl_exitfan" },
		{ x = 3, y = 0, r = 10, ab = "sl" }, { x = 4, y = 0, r = 10, ab = "game" }, { x = 5, y = 0, r = 10, ab = "sl_exitfan" } })
	local mids = {}
	for i, z in ipairs(mixed) do mids[i] = z.twin end
	eq(mids, { "g1a", "g1b", "g1e", "g2a", "g2b", "g2e" })
end)

test("zone lookup: the grid finds exactly the zones a brute-force check finds (400 zones, overlaps, rims, wide zones)", function()
	local f = flow()
	local zones = {}
	local seed = 12345
	local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return seed % n end
	for i = 1, 398 do zones[i] = { zone = i, x = rnd(20000) - 10000, y = rnd(20000) - 10000, r = 20 + rnd(400) } end
	zones[399] = { zone = 399, x = 0, y = 0, r = 30000 }   -- wider than 40 cells: checked in every lookup
	zones[400] = { zone = 400, x = 250, y = 250, r = 250 } -- on cell borders
	local idx = f.newIndex(zones)
	local buf = {}
	for _ = 1, 3000 do
		local x, y = rnd(24000) - 12000 + 0.5, rnd(24000) - 12000 + 0.25
		local n = f.zonesAt(idx, x, y, buf)
		local got = {}
		for k = 1, n do got[#got + 1] = buf[k] end
		table.sort(got)
		local want = {}
		for i, z in ipairs(zones) do if (x - z.x) ^ 2 + (y - z.y) ^ 2 <= z.r * z.r then want[#want + 1] = i end end
		eq(got, want)
	end
	-- on the rim counts
	eq(f.zonesAt(f.newIndex({ { x = 0, y = 0, r = 100 } }), 100, 0, buf), 1)
	eq(f.zonesAt(f.newIndex({ { x = 0, y = 0, r = 100 } }), 100.01, 0, buf), 0)
	eq(f.zonesAt(nil, 0, 0, buf), 0)
end)

test("aggregation: car-weighted speed, median, standing (< 0.5 m/s), queue (timeStanding >= 5 s), overlap counts in both", function()
	local f = flow()
	local s = f.newSample(2)
	f.addCar(s, { 1 }, 1, 10, 0)
	f.addCar(s, { 1 }, 1, 0.2, 7)
	f.addCar(s, { 1, 2 }, 2, 0, 3)
	f.addCar(s, {}, 0, 20, 0)
	f.addCar(s, { 1 }, 1, nil, 0)   -- unreadable speed: not counted
	f.addCar(s, { 2 }, 1, -4, 0)    -- reversing: |speed|
	eq({ s.zones[1].cars, s.zones[1].standing, s.zones[1].queue }, { 3, 2, 1 })
	eq({ s.zones[2].cars, s.zones[2].standing, s.zones[2].queue }, { 2, 1, 0 })
	eq({ s.all.cars, s.all.standing, s.inZones }, { 5, 2, 4 })
	local v, med, sm, smax = f.accStats(s.zones[1])
	near(v, 10.2 / 3, 1e-9)
	eq(med, 0.2)
	eq(sm, 5)
	eq(smax, 7)
	eq({ f.accStats(f.newAcc()) }, {})
	local z = { zone = 1, twin = "g3a", pair = "g3", ab = "sl" }
	local line = f.flowLine(2, 5, 81520000, z, s.zones[1])
	eq(line, "[SQST] FLOW run=2 s=5 zone=1 twin=g3a pair=g3 ab=sl gt=81520000 cars=3 standing=2 standing_pct=66.7 queue=1 v_mean=3.4 v_med=0.2 v_kmh=12.2 stand_mean=5 stand_max=7 cars_core=3 q_arm=- q_in=- q_out=- thru=- thru_s=- thru_scale=- thru_path=-")
	-- a zone without a car still gets its line
	eq(f.flowLine(2, 5, 81520000, { zone = 7 }, f.newAcc()),
		"[SQST] FLOW run=2 s=5 zone=7 twin=- gt=81520000 cars=0 standing=0 standing_pct=- queue=0 v_mean=- v_med=- v_kmh=- stand_mean=- stand_max=- cars_core=0 q_arm=- q_in=- q_out=- thru=- thru_s=- thru_scale=- thru_path=-")
end)

test("q_in / q_out: an arm's queue split by the side of the road (inbound right of the way in for right-hand traffic, left for left-hand)", function()
	local f = flow()
	local z = f.withMeasure({ zone = 1, x = 0, y = 0, r = 50 }, { { 1, 0 }, { 0, 1 } })   -- arms E and N
	local idx = f.newIndex({ z })
	local zs, parts, dirs = {}, {}, {}
	local s = f.newSample(1)
	local function car(x, y)
		local n = f.zonesAt(idx, x, y, zs, parts, dirs)
		f.addCar(s, zs, n, 0, 9, parts, dirs)
	end
	-- right-hand traffic: on the E arm (heading +x) the way in (-x) keeps right = +y... the side y < 0 is
	-- right of +x, so inbound is y > 0; on the N arm (heading +y) inbound is x < 0
	car(100, 5)    -- E, inbound
	car(100, 6)    -- E, inbound
	car(100, -5)   -- E, outbound
	car(-5, 100)   -- N, inbound
	car(5, 100)    -- N, outbound
	local a = s.zones[1]
	eq(z.armNames, { "N", "E" })
	eq(f.qArmText(z, a), "N:2,E:3")
	eq(f.qArmText(z, a, a.qIn), "N:1,E:2")
	eq(f.qArmText(z, a, a.qOut), "N:1,E:1")
	ok(f.flowLine(1, 1, 0, z, a):find(" q_arm=N:2,E:3 q_in=N:1,E:2 q_out=N:1,E:1 thru=- thru_s=- thru_scale=- thru_path=-", 1, true))
	-- left-hand traffic: mirrored
	f.DRIVE_SIDE = "left"
	local s2 = f.newSample(1)
	local n = f.zonesAt(idx, 100, 5, zs, parts, dirs)
	f.addCar(s2, zs, n, 0, 9, parts, dirs)
	eq(f.qArmText(z, s2.zones[1], s2.zones[1].qOut), "N:0,E:1")
	f.DRIVE_SIDE = "right"
end)

test("thru: pathState finds the junction ahead / passed within the window; thruCount = last sample's ahead that passed, only when both complete", function()
	local f = flow()
	local path = { 101, 102, 7, 8, 9, 103, 104 }   -- entities of a path's edges (0-based index i -> path[i + 1])
	local set = { [7] = true, [8] = true, [9] = true }
	local function get(i) return path[i + 1] end
	eq(f.pathState(get, #path, 0, set), "ahead")
	eq(f.pathState(get, #path, 3, set), "ahead", "on the junction: not passed yet")
	eq(f.pathState(get, #path, 5, set), "passed")
	eq(f.pathState(get, #path, 0, set, 2), nil, "beyond the window")
	eq(f.pathState(get, #path, 6, { [999] = true }), nil)
	eq(f.pathState(nil, 3, 0, set), nil)
	eq(f.pathState(get, #path, -1, set), nil)
	local prev, now = f.newAcc(), f.newAcc()
	prev.ahead = { [1] = true, [2] = true, [3] = true }
	now.passed = { [1] = true, [3] = true, [9] = true }
	eq(f.thruCount(prev, now, true), 2, "1 and 3; 9 was not ahead before")
	eq(f.thruCount(prev, now, false), nil)
	eq(f.thruCount(nil, now, true), nil)
	ok(f.flowLine(1, 2, 30000, { zone = 1 }, now, 2, 30, 1):find(" thru=2 thru_s=30 thru_scale=1 thru_path=-", 1, true) ~= nil)
end)

test("FLOW_START / FLOW_ZONE / FLOW_ALL / FLOW_SUMMARY lines carry the FLOW.md keys", function()
	local f = flow()
	eq(f.startLine({ run = 2, interval = 30, zones = 46, towns = 50, buses = 12, speed = 4, keepCleared = false, cap = 3000, gt = 81400000,
		src = "placement", scRun = "s1-2-3", budgetUs = 2000 }),
		"[SQST] FLOW_START run=2 v=3 interval=30 interval_unit=game_s zones=46 towns=50 buses=12 speed=4 keep_cleared=0 cap=3000 gt=81400000 gt_per_s=1000 src=placement sc_run=s1-2-3 budget_us=2000 target_min=3000 measure_pad=200 corridor_m=30 drive_side=right thru_r=40 thru_track=600 thru_window=32 thru_m=pos ix_corridor_m=50 path_thru=on")
	local z = f.zonesFromShowcase(F.showcase(), "s1-2-3")[3]
	eq(f.zoneLine(2, z), "[SQST] FLOW_ZONE run=2 zone=3 kind=x src=placement label=Crossroads x=0 y=1000 r=60 twin=g2a pair=g2 ab=sl sc_run=s1-2-3 id_from=showcase match=no reason=town r_measure=260 measure=circle arms=- approach=-")
	local s = f.newSample(0)
	s.drivers, s.sampled, s.target, s.stride = 3500, 3000, 3000, 2
	f.addCar(s, {}, 0, 10, 0)
	local all = f.allLine(2, 5, 81520000, s, { persons = 43000, frames = 40, busyUs = 61234, elapsedUs = 700000, frameMaxUs = 2049 })
	eq(all, "[SQST] FLOW_ALL run=2 s=5 gt=81520000 drivers=3500 sampled=3000 in_zones=0 standing=0 standing_pct=0 queue=0 v_mean=10 v_med=10 v_kmh=36 stand_mean=- stand_max=- persons=43000 pos_fail=0 frames=40 sweep_ms=61.2 elapsed_ms=700 capped=1 target=3000 stride=2 frame_ms_max=2 drivers_est=0 frame_phase=-")
	local t = f.newTotals()
	f.addSample(t, 100000, s, { persons = 1, frames = 10, busyUs = 3000, elapsedUs = 1, frameMaxUs = 1500 })
	f.addSample(t, 130000, s, { persons = 1, frames = 20, busyUs = 5000, elapsedUs = 1, frameMaxUs = 900 })
	t.warn.keep_cleared = 2
	eq(f.summaryLine(2, t, 4, 61.4, true),
		"[SQST] FLOW_SUMMARY run=2 samples=2 gt0=100000 gt1=130000 wall_s=61 zones=4 drivers_mean=3500 standing_frac=0 v_mean=10 v_kmh=36 capped=2 skipped=0 sweep_ms_mean=4 sweep_ms_max=5 frames_mean=15 warn=keep_cleared:2 final=1 frame_ms_max=1.5 target=3000")
	eq(f.targetLine(2, 6, 30000, nil, 40000, 52000, "skipped"),
		"[SQST] FLOW_TARGET run=2 s=6 target=30000 was=all read=40000 drivers_prev=52000 reason=skipped")
end)

test("FLOW_TOWNS: one scope=all line (levels summed, mean / min speed, cost), then towns slowest first", function()
	local f = flow()
	local lines = f.townsLines(2, 5, 1000, { [301] = { 0.8, { 5, 2, 1 } }, [302] = { 0.5, { 1, 1, 1, 4 } }, [303] = { "x", {} } }, 1, 4.25,
		function(t) return "Grid S" .. t end)
	eq(lines[1], "[SQST] FLOW_TOWNS run=2 s=5 gt=1000 scope=all towns=3 speed_mean=0.65 speed_min=0.5 levels=6,3,2,4 coef=1 ms=4.25")
	eq(lines[2], "[SQST] FLOW_TOWNS run=2 s=5 gt=1000 scope=town town=302 name=Grid_S302 speed=0.5 levels=1,1,1,4")
	eq(lines[3], "[SQST] FLOW_TOWNS run=2 s=5 gt=1000 scope=town town=301 name=Grid_S301 speed=0.8 levels=5,2,1")
	eq(lines[4], "[SQST] FLOW_TOWNS run=2 s=5 gt=1000 scope=town town=303 name=Grid_S303 speed=- levels=-")
end)

test("bus laps: a lap when the first stop's departure moved on (game s); a wiped history restarts; rt from sectionTimes", function()
	local f = flow()
	local laps = {}
	local function sample(deps, last, sections, gt)
		local acc = f.newBus()
		f.busVehicle(acc, laps, 800, { last = last, deps = deps, sections = sections }, 2, gt)
		return acc
	end
	local a = sample({ 100000, 160000 }, 160000, { 50, 60 }, 170000)
	eq({ #a.laps, a.rts, a.depAgeMax }, { 0, { 110 }, 10 })
	local b = sample({ 100000, 160000 }, 160000, { 50, 60 }, 200000)
	eq(#b.laps, 0, "same departure: no lap yet")
	local c = sample({ 230000, 160000 }, 230000, { 50, 0 }, 240000)
	eq(c.laps, { 130 }, "departure-to-departure at stop 1, dwell included")
	eq(c.rts, {}, "a section without a time: no round trip")
	local d = sample({ 0, 0 }, 0, {}, 250000)
	eq({ #d.laps, d.depAgeMax }, { 0, nil }, "history wiped (re-sent to its line)")
	eq(laps[800], nil)
	local e = sample({ 300000, 0 }, 300000, {}, 300000)
	eq(#e.laps, 0, "restarts after a wipe: no lap from the old departure")
	local line = f.busLine(2, 5, 300000, 900, "SQST Bus 1", { twin = "g1a", pair = "g1", ab = "sl" }, "session", c, 2, 0.01)
	eq(line, "[SQST] FLOW_BUS run=2 s=5 gt=300000 line=900 name=SQST_Bus_1 twin=g1a pair=g1 ab=sl twin_from=session vehicles=1 stops=2 rt_n=0 rt_mean=- rt_min=- rt_max=- lap_n=1 lap_mean=130 lap_min=130 lap_max=130 dep_age_max=10 freq=0.01 raw_last=230000 raw_deps=230000,160000 raw_sections=50,0")
	eq(f.busLine(2, 5, 1, 901, "SQST Bus 2", nil, nil, f.newBus(), nil, nil):find("twin=- vehicles=0 stops=- rt_n=0", 1, true) ~= nil, true)
end)

test("twinFromStops: the zone nearest the stops' midpoint, closer than half their distance", function()
	local f = flow()
	local zones = f.zonesFromShowcase(F.showcase(), "r")
	eq(f.twinFromStops(zones, -500, 0, 500, 0).twin, "g1a")
	eq(f.twinFromStops(zones, 900, 0, 1100, 0).twin, "g1b")
	eq(f.twinFromStops(zones, 5000, 5000, 5100, 5000), nil, "no zone near the midpoint")
	eq(f.twinFromStops(zones, nil, 0, 1, 1), nil)
end)

test("statusText", function()
	local f = flow()
	eq(f.statusText(false, 30, 0, 0, 0), "Off")
	eq(f.statusText(false, 30, 2, 14, 46), "Off (run 2: 14 samples)")
	eq(f.statusText(true, 30, 2, 14, 46, 12.3, 38, 2410), "On, every 30 game s: run 2, 14 samples, 46 zones, last sweep 12.3 ms in 38 frames, 2410 drivers")
	eq(f.statusText(true, 10, 1, 0, 0), "On, every 10 game s: run 1, 0 samples, 0 zones, first sweep running")
end)

---------------------------------------------------------------------------
-- The sampler

test("loading the sampler uses no api; it is idle until switched on", function()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	local fl = ug_require "square_stress_test::/stress/gui/stress_flow_log.tl"
	eq(fl.ui.on, false)
	eq(fl.ui.interval, 2)
	rt.notificationsSent = true
	-- idle: only the runtime's own clock, no engine read
	set_global("api", { type = { Clock = { new = function() return { getTime = function() return 1 end } end } },
		engine = setmetatable({}, { __index = function(_, k) error("api.engine." .. tostring(k) .. " used while idle") end }) })
	rt.tick()
	eq(fl.status(), "Off")
end)

test("a run: FLOW_START, one FLOW_ZONE per built twin, one FLOW per zone per sample (cars=0 too), FLOW_ALL, FLOW_BUS, FLOW_TOWNS", function()
	local rt, fl, slz, bl = F.load()
	slz.current = { run = "s1-2-3", seq = 1, zones = F.showcase() }
	bl.lineTwins[900] = { twin = "g1a", pair = "g1", ab = "sl" }
	fl.setInterval(1)   -- 10 game s
	fl.setOn(true)
	local lines = F.run(rt, 200, 500)   -- 100 game s: 10 or 11 samples
	local start = byKind(lines, "FLOW_START")
	eq(#start, 1)
	local s0 = F.kv(start[1])
	eq({ s0.run, s0.v, s0.interval, s0.interval_unit, s0.zones, s0.towns, s0.buses, s0.speed, s0.keep_cleared, s0.cap, s0.gt_per_s, s0.src, s0.sc_run },
		{ "1", "3", "10", "game_s", "4", "3", "1", "4", "0", "0", "1000", "placement", "s1-2-3" })
	eq(#byKind(lines, "FLOW_ZONE"), 4)
	local alls = byKind(lines, "FLOW_ALL")
	ok(#alls >= 9 and #alls <= 11, "samples: " .. #alls)
	local flows = byKind(lines, "FLOW")
	eq(#flows, 4 * #alls, "every zone every sample")
	-- the first sample: 320 drivers, 80 per zone g1a / g1b / g2a, none in g3a
	local per = {}
	for _, l in ipairs(flows) do
		local kv = F.kv(l)
		if kv.s == "1" then per[kv.twin] = kv end
	end
	eq({ per.g1a.cars, per.g1b.cars, per.g2a.cars, per.g3a.cars }, { "80", "80", "80", "0" })
	eq({ per.g3a.v_mean, per.g3a.standing, per.g3a.pair, per.g3a.ab }, { "-", "0", "g3", "sl" })
	-- g1a: i % 4 == 0, i % 5 ~= 0: standing i % 12 == 0 (27), queued i % 36 == 0 (9)
	eq({ per.g1a.standing, per.g1a.queue, per.g1a.stand_max }, { "27", "9", "6" })
	near(tonumber(per.g1a.v_mean), 530 / 80, 0.01)
	local a1 = F.kv(alls[1])
	eq({ a1.s, a1.drivers, a1.sampled, a1.in_zones, a1.persons, a1.capped, a1.pos_fail }, { "1", "320", "320", "240", "400", "0", "0" })
	ok(tonumber(a1.frames) >= 4, "sliced over frames: " .. a1.frames)
	-- buses: the session's twin; the towns at most every 60 s wall (the fake clock: 1 us per read)
	local bus = byKind(lines, "FLOW_BUS")
	eq(#bus, #alls, "one per SQST Bus line per sample, not for Other line")
	local b1 = F.kv(bus[1])
	eq({ b1.line, b1.name, b1.twin, b1.pair, b1.ab, b1.twin_from, b1.vehicles, b1.stops, b1.s }, { "900", "SQST_Bus_1", "g1a", "g1", "sl", "session", "2", "2", "1" })
	local towns = byKind(lines, "FLOW_TOWNS")
	eq(#towns, 3, "once (scope=all + 2 towns): the 60 s wall gate")
	eq(F.kv(towns[1]).s, "1")
	-- the gt of consecutive samples are one interval apart
	local g1, g2 = tonumber(F.kv(alls[1]).gt), tonumber(F.kv(alls[2]).gt)
	eq(g2 - g1, 10000)
	-- a summary every 10 samples
	local sums = byKind(lines, "FLOW_SUMMARY")
	eq(#sums, #alls >= 10 and 1 or 0)
	if #sums > 0 then eq(F.kv(sums[1]).final, "0") end
	-- Off: the final summary
	fl.setOn(false)
	local after = byKind(F.run(rt, 1, 500), "FLOW_SUMMARY")
	local fin = F.kv(after[#after])
	eq({ fin.final, fin.zones, fin.skipped, fin.warn }, { "1", "4", "0", "-" })
	eq(tonumber(fin.samples), #alls)
	ok(fl.status():find("^Off %(run 1: ") ~= nil, fl.status())
	eq(F.sent, 0, "reads only: no command")
end)

test("thru: cars through a junction between samples (ahead on their path, then passed), written on its FLOW lines with the sample's game seconds", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "s1-2-3", seq = 1, zones = F.showcase() }
	F.junctionEdges = { ["0,0"] = { 7700 }, ["1000,0"] = { 7701 } }
	-- the g1a drivers (car spot 1: i % 4 == 0) head through 7700: before it in the first samples, past it later
	local phase = 0
	F.pathOf = function(i)
		if i % 4 ~= 0 then return nil end
		return { 101, 7700, 102 }, phase
	end
	fl.setInterval(1)   -- 10 game s
	fl.setOn(true)
	local lines = F.run(rt, 25, 500)   -- the first two samples: ahead
	phase = 2
	lines = F.run(rt, 25, 500)        -- the next: passed
	local thru = {}
	for _, l in ipairs(byKind(lines, "FLOW")) do
		local kv = F.kv(l)
		if kv.twin == "g1a" then thru[tonumber(kv.s)] = { kv.thru_path, kv.thru_s } end
	end
	eq(thru[1], { "-", "-" }, "the first sample: nothing to compare")
	eq(thru[2], { "0", "10" }, "still ahead")
	local passed
	for s = 3, 5 do if thru[s] and thru[s][1] ~= "0" and thru[s][1] ~= "-" then passed = passed or thru[s] end end
	eq(passed, { "80", "10" }, "every g1a driver (80) passed once")
	-- g1b's drivers never had 7701 ahead
	for _, l in ipairs(byKind(lines, "FLOW")) do
		local kv = F.kv(l)
		if kv.twin == "g1b" and kv.thru_path ~= "-" then eq(kv.thru_path, "0") end
	end
	F.pathOf, F.junctionEdges = nil, nil
end)

test("thru with the path pair read as .first (another binding layout), the junction's streets re-read every sweep, and FLOW_PATHDBG lines (at most 4 per run)", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "s1-2-3", seq = 1, zones = F.showcase() }
	F.junctionEdges = { ["0,0"] = { 7700 } }
	F.pathLayout = "first"
	local phase = 0
	F.pathOf = function(i)
		if i % 4 ~= 0 then return nil end
		return { 101, 7800, 102 }, phase   -- the junction's street has id 7800 in the path (swapped since the run started)
	end
	fl.setInterval(1)
	fl.setOn(true)
	F.run(rt, 25, 500)
	F.junctionEdges = { ["0,0"] = { 7800 } }   -- a lock pass gave it a new id: the next sweeps read it fresh
	F.run(rt, 25, 500)
	phase = 2
	local lines = F.run(rt, 25, 500)
	local got
	for _, l in ipairs(byKind(lines, "FLOW")) do
		local kv = F.kv(l)
		if kv.twin == "g1a" and kv.thru_path ~= "-" and kv.thru_path ~= "0" then got = kv.thru_path end
	end
	eq(got, "80")
	local dbg = {}
	for _, e in ipairs(log_entries()) do if e.msg:find("[SQST] FLOW_PATHDBG", 1, true) then dbg[#dbg + 1] = e.msg end end
	eq(#dbg, 4, "four drivers per run")
	ok(dbg[1]:find(" elems=0:table/r2/101/", 1, true) ~= nil, dbg[1])
	ok(dbg[1]:find(" elem0=tostring=table:", 1, true) ~= nil and dbg[1]:find(",first:table(entity=101,index=0)", 1, true) ~= nil, dbg[1])
	F.pathOf, F.junctionEdges, F.pathLayout = nil, nil, nil
end)

test("budget: READS_PER_FRAME stops a slice (safety; 2000 by default), the sweep stops early when the clock passes 2 ms", function()
	local rt, fl, slz = F.load()
	eq(fl.READS_PER_FRAME, 2000)
	fl.READS_PER_FRAME = 100
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	F.P = 2000
	fl.setOn(true)
	local maxReads, prev = 0, 0
	F.run(rt, 60, 0, function()
		maxReads = math.max(maxReads, F.reads - prev)
		prev = F.reads
	end)
	eq(maxReads, 100)
	-- slow reads (100 us each): time, not the read limit, ends each slice (the clock is read every 8 persons)
	reset_modules()
	clear_logs()
	F = assert(loadfile("tests/square_stress_test/flow_fake.lua", "t", _ENV))()
	F.readUs = 100   -- every component read takes 100 us of the fake clock
	local rt2, fl2, slz2 = F.load()
	slz2.current = { run = "r", seq = 1, zones = F.showcase() }
	fl2.setOn(true)
	local maxP, prevP = 0, 0
	local lines = F.run(rt2, 400, 0, function()
		maxP = math.max(maxP, F.persons - prevP)
		prevP = F.persons
	end)
	ok(maxP <= 24, "persons per frame with a slow clock: " .. maxP)
	local a = F.kv(byKind(lines, "FLOW_ALL")[1])
	eq(a.drivers, "320")
	ok(tonumber(a.frames) > 40, "frames: " .. a.frames)
end)

test("every driver: 60k persons (48k drivers) all read within 2 ms per frame, done well inside an interval's ~450 frames (capped=0)", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	F.P = 60000
	-- the game's costs (FLOW_PLAN.md, seed 530609: 109k persons checked + 3000 read in ~95 ms): ~0.25 us per
	-- component read, ~1 us per getPosition, 1 us per clock read
	F.readUs, F.posUs = 0.25, 1
	fl.setOn(true)
	local frames, lines = 0, nil
	lines = F.run(rt, 600, 0, function() frames = frames + 1 end)
	local alls = byKind(lines, "FLOW_ALL")
	eq(#alls, 1, "paused: one sample")
	local a = F.kv(alls[1])
	-- 48000 ids not divisible by 5, minus 9999 (the fake world entity)
	eq({ a.persons, a.drivers, a.sampled, a.capped, a.target, a.stride }, { "60000", "47999", "47999", "0", "all", "1" })
	ok(tonumber(a.frames) <= 450, "frames: " .. a.frames)
	ok(tonumber(a.frame_ms_max) <= 2.1, "busiest frame ms: " .. a.frame_ms_max)
	print(string.format("    60k persons: frames=%s sweep_ms=%s frame_ms_max=%s", a.frames, a.sweep_ms, a.frame_ms_max))
	eq(#byKind(lines, "FLOW_TARGET"), 0)
end)

test("every driver with thru: 60k persons, every driver near a junction with a 40-edge path through it; still within 2 ms per frame and ~450 frames", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	F.P = 60000
	F.readUs, F.posUs, F.edgeUs = 0.25, 1, 0.25
	F.junctionEdges = { ["0,0"] = { 7700 }, ["1000,0"] = { 7701 }, ["0,1000"] = { 7702 } }
	local path = {}
	for k = 1, 40 do path[k] = 100000 + k end
	path[31] = 7700
	F.pathOf = function() return path, 0 end
	fl.setOn(true)
	local frames = 0
	local lines = F.run(rt, 600, 0, function() frames = frames + 1 end)
	local a = F.kv(byKind(lines, "FLOW_ALL")[1])
	eq({ a.drivers, a.sampled, a.capped, a.target }, { "47999", "47999", "0", "all" })
	ok(tonumber(a.frame_ms_max) <= 2.1, "busiest frame ms with the path reads: " .. a.frame_ms_max)
	ok(tonumber(a.frames) <= 450, "frames: " .. a.frames)
	print(string.format("    60k persons + thru: frames=%s sweep_ms=%s frame_ms_max=%s", a.frames, a.sweep_ms, a.frame_ms_max))
	F.pathOf, F.junctionEdges, F.edgeUs = nil, nil, nil
end)

test("a lowered target comes back once sweeps finish in the first half of their interval (FLOW_TARGET reason=recovered); thru counts again", function()
	local rt, fl, slz = F.load()
	local f = flow()
	f.TARGET_MIN = 100
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	F.P = 4000
	F.readUs, F.posUs = 1, 50   -- slow: the first sweep can't finish, the target drops
	fl.setInterval(1)
	fl.setOn(true)
	F.run(rt, 200, 200)
	F.posUs, F.readUs = 0, 0.1  -- then fast: the sweeps project to finish early, the target climbs back to all
	local lines = F.run(rt, 2000, 200)
	local rec = {}
	for _, l in ipairs(byKind(lines, "FLOW_TARGET")) do if F.kv(l).reason == "recovered" then rec[#rec + 1] = F.kv(l) end end
	ok(#rec >= 1, "recovered")
	eq(rec[#rec].target, "all")
	local alls = byKind(lines, "FLOW_ALL")
	eq(F.kv(alls[#alls]).target, "all")
	eq(F.kv(alls[#alls]).stride, "1")
	-- pure parts
	eq(f.raiseTarget(3000, 4000), nil, "3000 / 0.75 = 4000 covers every driver")
	eq(f.raiseTarget(1500, 4000), 2000)
	eq(f.raiseTarget(nil, 4000), nil)
	eq({ f.thruTrack(10), f.thruTrack(30), f.thruTrack(45), f.thruTrack(60) }, { 600, 600, 900, 1200 })
	local get = function(i) return ({ 5, 6, 7 })[i + 1] end
	eq(f.pathState(get, 3, 2, { [5] = true }), "passed")
	eq(f.pathState(get, 3, 2, { [5] = true }, nil, true), nil, "ahead only: no look behind")
end)

-- The cycle the review found (2026-10-13): thru's path reads were skipped under a target, so the stride sweeps ran
-- fast, the target went back to every driver, that sweep (with the reads) missed its interval and the target
-- dropped again: thru never counted. Now the path reads run on the stride's id subset too, and the raise is
-- projected from that sweep's own cost: path-read heavy runs settle on a stride with thru x stride.
for _, edgeUs in ipairs({ 3, 6 }) do
test("thru under a lowered target (path reads " .. edgeUs .. " us each): no flapping between every driver and a stride; thru counted on the same id subset x stride", function()
	local rt, fl, slz = F.load()
	local f = flow()
	f.TARGET_MIN = 100
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	F.P = 4000
	F.readUs, F.posUs, F.edgeUs = 0.25, 1, edgeUs   -- path reads dominate: every driver with its reads misses the interval
	F.junctionEdges = { ["0,0"] = { 7700 }, ["1000,0"] = { 7701 }, ["0,1000"] = { 7702 } }
	local passedAt = 0
	F.pathOf = function(i)
		local path = {}
		for k = 1, 40 do path[k] = 100000 + k end
		path[31] = 7700
		-- the g1a drivers pass 7700 every other sample (their position on the path moves on), the others stay before it
		return path, (i % 4 == 0 and passedAt or 0)
	end
	fl.setInterval(1)   -- 10 game s
	fl.setOn(true)
	local lines = {}
	for k = 1, 12 do
		passedAt = (k % 2 == 0) and 35 or 0
		lines = F.run(rt, 50, 200)
	end
	local tl = byKind(lines, "FLOW_TARGET")
	local toAll, lowered = 0, 0
	for _, l in ipairs(tl) do
		local kv = F.kv(l)
		if kv.reason == "recovered" and kv.target == "all" then toAll = toAll + 1 end
		if kv.reason == "skipped" then lowered = lowered + 1 end
	end
	ok(lowered >= 1, "lowered once")
	ok(toAll <= 1 and lowered <= 2, string.format("no flapping: %d raises to all, %d lowerings", toAll, lowered))
	-- thru is counted on the stride's id subset, scaled
	local scaled = 0
	for _, l in ipairs(byKind(lines, "FLOW")) do
		local kv = F.kv(l)
		if kv.twin == "g1a" and kv.thru ~= "-" and tonumber(kv.thru_scale or "") and tonumber(kv.thru_scale) > 1 then scaled = scaled + 1 end
	end
	ok(scaled >= 1, "thru with thru_scale > 1 under the target")
	F.pathOf, F.junctionEdges, F.edgeUs = nil, nil, nil
end)
end

test("a sweep that can't finish within its interval: skipped, FLOW_TARGET, the target lowered; later sweeps read every stride-th driver", function()
	local rt, fl, slz = F.load()
	local f = flow()
	f.TARGET_MIN = 100
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	F.P = 4000           -- 3200 drivers
	F.readUs, F.posUs = 1, 50   -- a read costs 50 us: ~35 drivers per 2 ms frame
	fl.setInterval(1)    -- 10 game s
	fl.setOn(true)
	local lines = F.run(rt, 400, 200)   -- due every 50 frames
	local tl = byKind(lines, "FLOW_TARGET")
	ok(#tl >= 1, "a FLOW_TARGET line")
	local t1 = F.kv(tl[1])
	eq({ t1.was, t1.reason }, { "all", "skipped" })
	local target = tonumber(t1.target)
	eq(target, math.max(100, math.floor(tonumber(t1.read) * 0.75)))
	ok(target < 3200)
	local alls = byKind(lines, "FLOW_ALL")
	ok(#alls >= 3, "samples: " .. #alls)
	local last = F.kv(alls[#alls])
	ok(tonumber(last.target) ~= nil and tonumber(last.target) <= target, "target=" .. last.target)
	ok(tonumber(last.stride) >= 2, "stride=" .. last.stride)
	ok(tonumber(last.sampled) <= tonumber(last.target), "sampled " .. last.sampled)
	-- with a stride only every stride-th person (by id) is read: drivers= is that subset's drivers x stride (an estimate)
	near(tonumber(last.drivers), 3200, 2 * tonumber(last.stride))
	eq({ last.capped, last.drivers_est }, { "1", "1" })
	-- spread over the list: each zone still gets its share (cars i % 4 pick the spot; stride 3 or 4 keeps them mixed)
	fl.setOn(false)
	local fin = F.kv(byKind(F.run(rt, 1, 0), "FLOW_SUMMARY")[1])
	ok(tonumber(fin.skipped) >= 1)
	eq(fin.target, last.target)
	-- lowerTarget / stride
	eq(f.lowerTarget(nil, 40000), 30000)
	eq(f.lowerTarget(20000, 40000), 20000, "never raised")
	eq(f.lowerTarget(nil, 10), 100, "TARGET_MIN")
	eq({ f.stride(nil, 55000), f.stride(30000, 55000), f.stride(30000, 20000) }, { 1, 2, 1 })
end)

test("measured area: the junction's circle plus a 30 m corridor along each arm out to r + 200 m; q_arm per arm; no arms = circle", function()
	local f = flow()
	-- a 4-arm crossing at (1000, 2000), r 70, arms measured slightly off the axes; listed W, N, E, S
	local z = f.withMeasure({ zone = 1, twin = "g1a", pair = "g1", ab = "sl", kind = "x", src = "placement", label = "2x2_X", x = 1000, y = 2000, r = 70 },
		{ { -1, 0 }, { 0.001, 1 }, { 2, 0 }, { 0, -1 } })
	eq({ z.rm, z.measure }, { 270, "corridor" })
	eq(z.armNames, { "N", "E", "S", "W" }, "compass order")
	eq(f.partOf(z, 0, 0), 0)
	eq(f.partOf(z, 49, 49), 0, "inside r")
	eq(f.partOf(z, 0, 150), 1, "N corridor")
	eq(f.partOf(z, 14, 269), 1, "N corridor edge")
	eq(f.partOf(z, 16, 150), nil, "beside the N corridor")
	eq(f.partOf(z, 0, 271), nil, "past r_measure")
	eq(f.partOf(z, 200, -10), 2, "E")
	eq(f.partOf(z, 0, -200), 3, "S")
	eq(f.partOf(z, -260, 5), 4, "W")
	eq(f.partOf(z, 120, 120), nil, "between two arms")
	-- a T: no S arm, so the S approach is outside
	local t = f.withMeasure({ zone = 2, x = 0, y = 0, r = 60 }, { { 1, 0 }, { 0, 1 }, { -1, 0 } })
	eq(t.armNames, { "N", "E", "W" })
	eq(f.partOf(t, 0, -100), nil)
	-- no arms (Smart Lanes' saved zones after a reload): the circle r + 200
	local c = f.withMeasure({ zone = 3, x = 0, y = 0, r = 60 }, nil)
	eq({ c.rm, c.measure, c.arms }, { 260, "circle", nil })
	eq(f.partOf(c, 180, 180), 0)
	eq(f.partOf(c, 200, 200), nil)
	-- lookup and q_arm
	local idx = f.newIndex({ z, c })
	local zs, parts = {}, {}
	eq(f.zonesAt(idx, 1000, 2150, zs, parts), 1)
	eq({ zs[1], parts[1] }, { 1, 1 })
	local s = f.newSample(2)
	local function car(x, y, speed, ts)
		local n = f.zonesAt(idx, x, y, zs, parts)
		f.addCar(s, zs, n, speed, ts, parts)
	end
	car(1000, 2000, 0, 9)      -- in the box, queued: no arm
	car(1000, 2150, 0, 9)      -- N, queued
	car(1000, 2160, 0, 9)      -- N, queued
	car(1100, 2000, 0, 2)      -- E, standing only
	car(1000, 1800, 0, 30)     -- S, queued
	car(1000, 1800, 12, 0)     -- S, driving
	car(1300, 2300, 0, 9)      -- nowhere
	local a = s.zones[1]
	eq({ a.cars, a.core, a.standing, a.queue }, { 6, 1, 5, 4 })
	eq(f.qArmText(z, a), "N:2,E:0,S:1,W:0")
	local line = f.flowLine(1, 1, 5000, z, a)
	ok(line:find(" cars=6 ", 1, true) and line:find(" cars_core=1 q_arm=N:2,E:0,S:1,W:0 q_in=") ~= nil, line)
	eq(f.zoneLine(1, z), "[SQST] FLOW_ZONE run=1 zone=1 kind=x src=placement label=2x2_X x=1000 y=2000 r=70 twin=g1a pair=g1 ab=sl sc_run=- id_from=- r_measure=270 measure=corridor arms=N,E,S,W approach=-")
	eq(f.qArmText(c, s.zones[2]), "-")
	-- from the Showcase zones (the read's arm headings)
	local list = F.showcase()
	list[1].arms = { { 1, 0 }, { -1, 0 } }
	local zones = f.zonesFromShowcase(list, "r")
	eq({ zones[1].measure, zones[1].armNames, zones[2].measure }, { "corridor", { "E", "W" }, "circle" })
end)

test("timing: a paused game takes no sample; a sample due during a running sweep is skipped", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	fl.setOn(true)
	local lines = F.run(rt, 100, 0)   -- paused: gt never moves
	eq(#byKind(lines, "FLOW_ALL"), 1, "only the first sample, at the start")
	clear_logs()
	-- 10 game s per frame with a 30 s interval: due every 3 frames, a sweep takes more
	lines = F.run(rt, 120, 10000)
	fl.setOn(false)
	lines = F.run(rt, 1, 0)
	local fin = F.kv(byKind(lines, "FLOW_SUMMARY")[#byKind(lines, "FLOW_SUMMARY")])
	ok(tonumber(fin.skipped) > 0, "skipped=" .. fin.skipped)
end)

test("Keep traffic cleared: a warning dialog at On, keep_cleared=1 and warn=keep_cleared", function()
	local rt, fl, slz, _, tr = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	tr.ui.keepCleared = true
	fl.setOn(true)
	eq(#rt.warnings, 1)
	eq(rt.warnings[1].title, "Traffic log")
	local lines = F.run(rt, 30, 500)
	eq(F.kv(byKind(lines, "FLOW_START")[1]).keep_cleared, "1")
	tr.ui.keepCleared = false
	fl.setOn(false)
	lines = F.run(rt, 1, 0)
	ok(F.kv(byKind(lines, "FLOW_SUMMARY")[1]).warn:find("^keep_cleared:%d+$") ~= nil)
end)

test("Clear queue stops the log (final summary); interval change restarts it as a new run", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	fl.setOn(true)
	F.run(rt, 30, 500)
	fl.setInterval(3)
	local lines = F.run(rt, 30, 500)
	local starts = byKind(lines, "FLOW_START")
	eq(#starts, 2)
	eq({ F.kv(starts[2]).run, F.kv(starts[2]).interval }, { "2", "60" })
	clear_logs()
	rt.clearQueue()
	lines = F.run(rt, 2, 500)
	eq(#byKind(lines, "FLOW_SUMMARY"), 1)
	eq(fl.ui.on, false)
end)

test("a new Showcase (or more of its twins read) restarts the run once no test build runs", function()
	local rt, fl, slz = F.load()
	local zones = F.showcase()
	slz.current = { run = "r", seq = 1, zones = zones }
	fl.setOn(true)
	F.run(rt, 10, 500)
	zones[4].built = true   -- g2b read now
	-- a test job in the queue: no restart yet
	rt.enqueue("showcase", 1, function() end, { delayMs = 1e9 })
	local lines = F.run(rt, 400, 0)   -- > ZONE_CHECK_US of fake clock
	eq(#byKind(lines, "FLOW_START"), 1)
	rt.clearQueue()   -- also stops the log
	eq(#byKind(F.run(rt, 2, 0), "FLOW_SUMMARY"), 1)
	clear_logs()
	fl.setOn(true)
	eq(F.kv(byKind(F.run(rt, 1, 0), "FLOW_START")[1]).zones, "5")
end)

test("after a reload: zones and twin ids from Smart Lanes' saved zones; the bus line's twin from its stops", function()
	local rt, fl = F.load()
	F.zrun = "s5-6-7"
	F.saved = { { x = 0, y = 0, r = 120, ab = "sl", id = "g1a", pair = "g1" }, { x = 1000, y = 0, r = 120, ab = "game", id = "g1b", pair = "g1" } }
	fl.setOn(true)
	local lines = F.run(rt, 40, 500)
	local s0 = F.kv(byKind(lines, "FLOW_START")[1])
	eq({ s0.zones, s0.src, s0.sc_run }, { "2", "sl_zones", "s5-6-7" })
	local z = F.kv(byKind(lines, "FLOW_ZONE")[2])
	eq({ z.twin, z.pair, z.ab, z.src, z.id_from, z.label, z.r }, { "g1b", "g1", "game", "sl_zones", "sl", "g1b", "120" })
	local b = F.kv(byKind(lines, "FLOW_BUS")[1])
	eq({ b.twin, b.pair, b.ab, b.twin_from }, { "g1a", "g1", "sl", "stops" })
end)

test("without Smart Lanes and without a Showcase: no zones, FLOW_ALL only", function()
	local rt, fl = F.load()
	F.smParams = false
	fl.setOn(true)
	local lines = F.run(rt, 40, 500)
	eq(F.kv(byKind(lines, "FLOW_START")[1]).src, "none")
	eq(#byKind(lines, "FLOW_ZONE"), 0)
	eq(#byKind(lines, "FLOW"), 0)
	ok(#byKind(lines, "FLOW_ALL") >= 1)
end)

test("every engine read throwing: the sampler keeps running and writes its lines", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	fl.setOn(true)
	local a = api
	a.engine.getComponent = function(e, ct)
		if e == F.WORLD and ct == "GAME_TIME" then return { gameTime = F.gt } end
		error("read failed")
	end
	a.engine.util.vehicle.getPosition = function() error("pos failed") end
	a.engine.util.town.computeTownsTrafficSpeedMap = function() error("towns failed") end
	local lines = F.run(rt, 60, 500)
	local all = F.kv(byKind(lines, "FLOW_ALL")[1])
	eq(all.drivers, "0")
	eq(#byKind(lines, "FLOW"), 4 * #byKind(lines, "FLOW_ALL"))
	local errs = 0
	for _, e in ipairs(log_entries()) do if e.msg:find("tick hook error", 1, true) then errs = errs + 1 end end
	eq(errs, 0)
end)

test("a phase that throws drops that sweep once (warn=sweep_error), the next sweeps run", function()
	local rt, fl, slz = F.load()
	local flow = ug_require "square_stress_test::/stress/stress_flow.tl"
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	fl.setOn(true)
	local allLine = flow.allLine
	local thrown = 0
	flow.allLine = function(...)
		if thrown == 0 then
			thrown = 1
			error("format failed")
		end
		return allLine(...)
	end
	local lines = F.run(rt, 200, 500)
	flow.allLine = allLine
	eq(thrown, 1)
	local errs, sweepErr = 0, 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("tick hook error", 1, true) then errs = errs + 1 end
		if e.msg:find("traffic log sweep error", 1, true) then sweepErr = sweepErr + 1 end
	end
	eq(errs, 0)
	eq(sweepErr, 1)
	eq(#byKind(lines, "FLOW_ALL") > 0, true)
	fl.setOn(false)
	local final = F.kv(byKind(F.run(rt, 0), "FLOW_SUMMARY")[#byKind(F.run(rt, 0), "FLOW_SUMMARY")])
	eq(final.warn:find("sweep_error:1", 1, true) ~= nil, true)
end)

test("a new Lights showcase restarts the run too, after its growth job; its sl_fan twin (d) is sampled", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "r", seq = 1, zones = F.showcase() }
	fl.setOn(true)
	F.run(rt, 10, 500)
	slz.current = { run = "r2", seq = 2, zones = {
		{ id = "g1a", pair = "g1", ab = "sl", kind = "plain", label = "Crossroads", x = 0, y = 0, r = 108, towns = 4, built = true },
		{ id = "g1b", pair = "g1", ab = "game", kind = "plain", label = "Crossroads", x = 1000, y = 0, r = 108, towns = 4, built = true },
		{ id = "g1c", pair = "g1", ab = "sl_phases", kind = "plain", label = "Crossroads", x = 2000, y = 0, r = 108, towns = 4, built = true },
		{ id = "g1d", pair = "g1", ab = "sl_fan", kind = "plain", label = "Crossroads", x = 3000, y = 0, r = 108, towns = 4, built = true },
	} }
	-- its towns still grow (a test job): no restart yet
	local job = rt.enqueue("lights_showcase_grow", 1, function() end, { delayMs = 1e9 })
	clear_logs()
	F.clockStep = 10000
	eq(#byKind(F.run(rt, 400, 0), "FLOW_START"), 0)
	F.clockStep = 1
	for i, j in ipairs(rt.queue.jobs) do if j == job then table.remove(rt.queue.jobs, i) break end end
	clear_logs()
	F.clockStep = 10000   -- 10 ms per clock read: past the zone check interval (2 s) within these frames
	local lines = F.run(rt, 400, 0)
	F.clockStep = 1
	local starts = byKind(lines, "FLOW_START")
	eq(#starts, 1)
	eq(F.kv(starts[1]).zones, "4")
	lines = F.run(rt, 200, 500)
	local seen = {}
	for _, l in ipairs(byKind(lines, "FLOW_ZONE")) do
		local kv = F.kv(l)
		seen[kv.twin] = kv.ab
	end
	eq(seen.g1d, "sl_fan")
	eq(seen.g1c, "sl_phases")
end)

---------------------------------------------------------------------------
-- thru by position (BENCH.md: the primary thru while the path element reads nothing)

test("thru by position: approachOf = junction 0 / inbound arm k / outbound -k / nil, out to the approach length; wider corridors at an interchange", function()
	local f = flow()
	local z = f.withMeasure({ zone = 1, x = 0, y = 0, r = 50, kind = "x" }, { { 1, 0 }, { 0, 1 } })
	z.approach = 500
	-- arms sorted by compass point: N first, then E
	eq(z.armNames, { "N", "E" })
	eq(f.approachOf(z, 10, 10), 0, "the junction")
	-- east arm (heading +x): right-hand traffic comes in on the north side of it (y > 0)
	eq(f.approachOf(z, 300, 5), 2)
	eq(f.approachOf(z, 300, -5), -2)
	eq(f.approachOf(z, 480, 5), 2, "past r_measure but on the approach")
	eq(f.approachOf(z, 520, 5), nil, "beyond the approach")
	eq(f.approachOf(z, 300, 20), nil, "off the corridor")
	-- north arm (heading +y): inbound on the west side (x < 0)
	eq(f.approachOf(z, -5, 200), 1)
	eq(f.approachOf(z, -300, -300), nil)
	z.kind = "ix"
	eq(f.approachOf(z, 300, 20), 2, "an interchange's corridor is 25 m to each side")
	f.DRIVE_SIDE = "left"
	eq(f.approachOf(z, 300, 5), -2, "left-hand traffic: the other side")
	f.DRIVE_SIDE = "right"
	-- no approach: r_measure; no arms: the circle
	z.approach = nil
	eq(f.approachOf(z, 300, 5), nil, "r_measure 250")
	local c = f.withMeasure({ zone = 2, x = 0, y = 0, r = 50 }, nil)
	eq(f.approachOf(c, 200, 0), 0)
	eq(f.approachOf(c, 300, 0), nil)
end)

test("thru by position: posCount = the drivers on their way in last sample that are not on their way in now; nil unless both complete", function()
	local f = flow()
	local prev, now = f.newAcc(), f.newAcc()
	prev.posIn = { [1] = 2, [2] = 0, [3] = 1, [4] = 2 }
	now.posIn = { [2] = 0, [4] = 2, [9] = 1 }
	eq(f.posCount(prev, now, true), 2, "1 and 3 passed; 2 still in the junction, 4 still queued; 9 new")
	eq(f.posCount(prev, now, false), nil)
	eq(f.posCount(nil, now, true), nil)
end)

test("thru by position in the sampler: cars on an inbound approach at one sample, out an exit (or gone far) at the next, counted once", function()
	local rt, fl, slz = F.load()
	local zones = F.showcase()
	zones[1].arms = { { 1, 0 }, { -1, 0 } }
	zones[1].approach = 500
	slz.current = { run = "s1-2-3", seq = 1, zones = zones }
	local phase = 0
	F.posOf = function(i)
		if i % 4 ~= 0 then return nil end
		if phase == 0 then return { 300, 5 } end   -- g1a's east approach, inbound side
		if phase == 1 then return { -300, -5 } end -- out on the west arm's outbound side
		return { 5000, 5000 }
	end
	fl.setInterval(1)
	fl.setOn(true)
	F.run(rt, 25, 500)
	phase = 1
	local lines = F.run(rt, 25, 500)
	phase = 2
	lines = F.run(rt, 25, 500)
	local got = {}
	for _, l in ipairs(byKind(lines, "FLOW")) do
		local kv = F.kv(l)
		if kv.twin == "g1a" and kv.thru ~= "-" then got[#got + 1] = kv.thru end
	end
	local sum = 0
	for _, v in ipairs(got) do sum = sum + tonumber(v) end
	eq(sum, 80, "every g1a driver (80) counted once: " .. table.concat(got, ","))
	F.posOf = nil
end)

test("thru_path gives up when no path element reads (FLOW_PATHOFF once), the positional thru goes on", function()
	local rt, fl, slz = F.load()
	slz.current = { run = "s1-2-3", seq = 1, zones = F.showcase() }
	F.junctionEdges = { ["0,0"] = { 7700 } }
	F.pathLayout = "first"
	-- elements no reader can read: plain numbers
	F.pathOf = function(i)
		if i % 4 ~= 0 then return nil end
		return { 101, 7700, 102 }, 0
	end
	local fp = F.pathLayout
	F.pathLayout = "none"
	fl.PATH_GIVE_UP = 200
	fl.setInterval(1)
	fl.setOn(true)
	local lines = F.run(rt, 75, 500)
	F.pathLayout = fp
	local off = 0
	for _, e in ipairs(log_entries()) do if e.msg:find("[SQST] FLOW_PATHOFF", 1, true) then off = off + 1 end end
	eq(off, 1)
	local last
	for _, l in ipairs(byKind(lines, "FLOW")) do
		local kv = F.kv(l)
		if kv.twin == "g1a" then last = kv end
	end
	eq(last.thru_path, "-")
	ok(last.thru ~= "-", "positional thru still counted")
	F.pathOf, F.junctionEdges, F.pathLayout = nil, nil, nil
end)
