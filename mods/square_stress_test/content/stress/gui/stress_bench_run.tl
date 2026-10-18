-- Stress Test bench run (plans/square_stress_test/BENCH.md "Automation"): one press runs a bench sheet end to end.
-- preflight (map, Smart Lanes settings and zone modes, Roundabouts & Interchanges, busy) -> clear the map (every town,
-- every road) -> the year to 1950 if earlier -> build (gui/stress_junctions.tl buildBench: towns, entries, junctions,
-- Smart Lanes idle, links, growth) -> traffic log on (10 game s), speed 2 -> warm-up -> record -> log off, speed 1 ->
-- a screenshot of every test's first set -> "[SQST] BENCH_DONE". Every phase logs "[SQST] BENCH_PHASE"; game time
-- counts the warm-up and the record (a paused game waits). Runs from the rt tick hook (Main Thread); every step is
-- pcall'd, an error or Clear queue ends the run with "[SQST] BENCH_ABORT".

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local bench = ug_require "square_stress_test::/stress/stress_bench.tl" as SquareStressBench
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones
local jn = ug_require "square_stress_test::/stress/gui/stress_junctions.tl" as SquareStressJunctions
local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl" as SquareStressTowns
local roads = ug_require "square_stress_test::/stress/gui/stress_roads.tl" as SquareStressRoads
local fl = ug_require "square_stress_test::/stress/gui/stress_flow_log.tl" as SquareStressFlowLog
local traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl" as SquareStressTraffic
-- the city run (bench.CITY, BENCH.md "City lights at scale"): its build instead of buildBench, the enroll after its baseline
local citylights = ug_require "square_stress_test::/stress/gui/stress_citylights.tl" as SquareStressCityLights

local MAP_MARGIN <const> = 400.0      -- stress_junctions MAP_MARGIN
local POLL_US <const> = 250000        -- the state machine looks every this often
local ACK_MS <const> = 5000           -- Smart Lanes' answer to the preflight's clear
local REMOVE_MAX_MS <const> = 600000  -- the map clearing may take this long
local SHOT_GAP_US <const> = 4000000   -- between two screenshots
local SHOT_SETTLE_US <const> = 2500000  -- after a camera move, before its shot
local SHOT_DIST <const> = 130.0       -- m: the camera's distance over a junction (450 m showed only queues, no lanes: 2026-10-14)
local BUILD_MAX_MS <const> = 5400000  -- the build (towns to growth) may take this long in all
local STALL_MS <const> = 600000       -- ... and this long without a single log line (no progress)

local br : SquareStressBenchRun = { phase = "idle", cityUi = { layout = 1, busy = false, baseline = 1, swap = false, sameSeed = false } }

--- A sheet by key; the City lights sheet with the window's options (bench.citySheet; the defaults: the v1 run).
function br.sheetFor(key : string) : SquareStressBenchSheet
	local sheet = bench.sheet(key)
	if sheet ~= nil and sheet.city ~= nil then return bench.citySheet(br.cityUi) end
	return sheet
end

--- The City lights options' signature (the window re-renders when one changes).
function br.cityUiSignature() : string
	local u = br.cityUi
	return string.format("%d%s%d%s%s%s", u.layout or 1, tostring(u.busy), u.baseline or 1, tostring(u.swap), tostring(u.sameSeed),
		tostring(br.lastCitySeed))
end

-- the run's state in one table (Lua 5.1 upvalue limit)
local record Run
	sheet : SquareStressBenchSheet
	info : SquareStressBenchInfo
	seed : integer
	phase : string
	nextUs : integer
	t0Us : integer
	phaseUs : integer
	clearsSeen : integer
	ackRun : string
	gt0 : number              -- game time the current timed phase started
	speed : integer
	steppedDown : boolean
	finished : boolean        -- buildRun's onRunFinished came
	zones : {SquareStressShowcaseZone}
	layout : SquareStressShowcaseLayout
	shots : {{number}}        -- {x, y} of each screenshot (the zone of every test's first set)
	shotIds : {string}
	shotI : integer
	shotDueUs : integer
	samples : integer
	problems : {string}
	roadsQueued : boolean     -- Remove all roads queued (after the towns)
	idle : boolean            -- Smart Lanes' queue went empty after the build
	moved : boolean           -- the camera was moved for the next screenshot
	linesSeen : integer       -- rt.lines at the last look (build watchdog)
	progressUs : integer      -- when the build last logged something
	recordSpeed : integer     -- the game speed of the record
	enrolled : boolean        -- the city run: its enroll was sent (after baselineS of the record)
end

local run : Run = nil

local function nowUs() : integer
	return rt.nowUs()
end

local function gameTime() : number
	local ok, gt = pcall(function() : number
		local c = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
		return c.gameTime
	end)
	if ok and type(gt) == "number" then return gt end
	return nil
end

local function gameSpeed() : integer
	local ok, sp = pcall(function() : integer
		local c = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
		return c.speedup
	end)
	if ok and type(sp) == "number" then return math.floor(sp as number) end
	return nil
end

local function year() : integer
	local ok, y = pcall(api.engine.util.getYear)
	if ok and type(y) == "number" then return math.floor(y as number) end
	return nil
end

local function setSpeed(speed : integer)
	run.speed = speed
	rt.send("bench_speed", api.cmd.makeGameSetSpeedCmd(speed))
end

local function phase(name : string, extra? : string)
	run.phase = name
	run.phaseUs = nowUs()
	br.phase = name
	local gt = gameTime()
	rt.log(string.format("[SQST] BENCH_PHASE sheet=%s phase=%s gt=%s ms=%.0f%s", run.sheet.key, name, gt ~= nil and string.format("%.0f", gt) or "-",
		(nowUs() - run.t0Us) / 1000, extra ~= nil and (" " .. extra) or ""))
	rt.version = rt.version + 1
end

local function abort(why : string)
	if run == nil then return end
	rt.log(string.format("[SQST] BENCH_ABORT sheet=%s phase=%s reason=%s", run.sheet.key, run.phase, (tostring(why):gsub("%s+", "_"))))
	rt.warn(run.sheet.title, "The bench stopped: " .. tostring(why))
	-- back to normal: the traffic log off (its final summary) and 1x, if the run had changed them
	if run.phase == "warmup" or run.phase == "record" then
		pcall(fl.setOn, false)
	end
	-- the city run: its junctions unenrolled again
	if run.sheet.city ~= nil and run.enrolled then pcall(citylights.unenroll) end
	fl.pathThru = true
	if (run.speed or 1) ~= 1 then pcall(setSpeed, 1) end
	jn.onRunFinished, jn.onRunAborted, jn.benchActive = nil, nil, false
	run = nil
	br.phase = "idle"
	rt.version = rt.version + 1
end

--- The window's status line.
function br.status() : string
	if run == nil then return br.last or "" end
	local p = run.phase
	if p == "warmup" or p == "record" then
		local gt = gameTime()
		local need = (p == "warmup" and bench.WARMUP_S or bench.recordS(run.sheet))
		local done = (gt ~= nil and run.gt0 ~= nil) and (gt - run.gt0) / 1000 or 0
		local city = ""
		if run.sheet.city ~= nil and p == "record" then city = run.enrolled and ", automatic timing on" or ", baseline" end
		return string.format("Bench %s: %s %d of %d game s (speed %d%s)", run.sheet.key, p == "warmup" and "warm-up" or "recording",
			math.floor(math.min(done, need)), need, run.speed or 1, city)
	end
	return string.format("Bench %s: %s", run.sheet.key, p)
end

function br.running() : boolean
	return run ~= nil
end

--- The preflight's reads (synchronous part; the zone modes come after Smart Lanes answered the clear).
local function readInfo(sheet : SquareStressBenchSheet) : SquareStressBenchInfo
	local info : SquareStressBenchInfo = { year = year() }
	pcall(function()
		local box = api.engine.terrain.getBoundingBox()
		info.w, info.h = box.max.x - box.min.x, box.max.y - box.min.y
	end)
	if info.w ~= nil and info.w > 0 and info.h ~= nil and info.h > 0 then
		if sheet.city ~= nil then
			info.cityPlan, info.cityWhy = bench.cityPlan(info.w, info.h, MAP_MARGIN, sheet)
		else
			info.plan = bench.plan(info.w, info.h, MAP_MARGIN, sheet)
		end
	end
	info.busy = rt.busyJob(rt.TEST_JOBS)
	for _, t in ipairs(sheet.tests) do
		for _, v in ipairs(t.variants) do
			if v.file ~= logic.SHOWCASE_PLAIN_FILE then info.needsRb = true end
		end
	end
	info.rbOk = jn.available()
	info.paused = gameSpeed() == 0
	info.slPresent = slzones.present()
	if info.slPresent then
		local ok, all = pcall(function() : {string : any} return api.engine.config.getModParams() as {string : any} end)
		local raw = (ok and type(all) == "table") and (all as {string : any})["square_smart_lanes"] or nil
		info.sl = bench.slSettings(type(raw) == "table" and raw as {string : any} or {})
		-- the DEV master switch (plans/sqperf/README.md): every SQPERF mod's window lines on
		info.perfAll = ok and type(all) == "table" and (all as {string : any})["square_sqperf_all"] ~= nil
	end
	return info
end

--- The window's plan line for a sheet on this map.
function br.planLine(key : string) : string
	local sheet = br.sheetFor(key)
	if sheet == nil then return "" end
	local ok, text = pcall(function() : string
		local w, h : number, number = nil, nil
		local box = api.engine.terrain.getBoundingBox()
		w, h = box.max.x - box.min.x, box.max.y - box.min.y
		if sheet.city ~= nil then
			local cp, why = bench.cityPlan(w, h, MAP_MARGIN, sheet)
			return bench.cityPlanText(cp, why, w, h)
		end
		return bench.planText(bench.plan(w, h, MAP_MARGIN, sheet), w, h)
	end)
	return ok and text or "(the map size could not be read)"
end

--- What would stop the sheet now (the confirm dialog shows it instead of starting): empty when it can start.
function br.check(key : string) : {string}
	local sheet = br.sheetFor(key)
	if sheet == nil then return { "Unknown bench sheet " .. tostring(key) } end
	if run ~= nil then return { "A bench is running (" .. run.sheet.key .. "): wait for it to finish." } end
	local info = readInfo(sheet)
	-- the zone modes are known only after the preflight's clear: not checked here
	info.slModes = bench.needs(sheet)
	return bench.problems(sheet, info)
end

---------------------------------------------------------------------------
-- The phases

local function startBuild()
	jn.onRunFinished = function(name : string, _seed : integer, layout : SquareStressShowcaseLayout, zones : {SquareStressShowcaseZone})
		if run ~= nil and name == run.sheet.id then
			run.finished = true
			run.layout, run.zones = layout, zones
		end
	end
	-- the build ends the bench when Smart Lanes refused or did not acknowledge the twins' zones (stress_junctions waitZones)
	jn.onRunAborted = function(name : string, why : string)
		if run ~= nil and name == run.sheet.id then abort(why) end
	end
	phase("build")
	if run.sheet.city ~= nil then
		-- the city run: its cities, their lights and zones (gui/stress_citylights.tl); no junction twins, no Smart Lanes zones
		local sheet = run.sheet
		local okB = citylights.build(sheet, run.seed, function(zones : {SquareStressShowcaseZone})
			if run ~= nil and run.sheet == sheet then
				run.finished = true
				run.zones = zones
			end
		end, function(why : string)
			if run ~= nil and run.sheet == sheet then abort(why) end
		end)
		if not okB then abort("the city build did not start (the cities do not fit, or a build is running)") end
		return
	end
	if not jn.buildBench(run.sheet, run.seed) then abort("the build did not start (see its dialog)") end
end

local function startShots()
	run.shots, run.shotIds = {}, {}
	if run.sheet.city ~= nil then
		-- one shot over each city
		for _, z in ipairs(run.zones or {}) do
			run.shots[#run.shots + 1] = { z.x, z.y }
			run.shotIds[#run.shotIds + 1] = string.format("city:%s", z.id)
		end
		run.shotI = 0
		run.shotDueUs = nowUs()
		phase("shots", string.format("n=%d", #run.shots))
		return
	end
	local seen : {string : boolean} = {}
	for gi, g in ipairs(run.layout ~= nil and run.layout.groups or {}) do
		local z = run.zones ~= nil and run.zones[gi] or nil
		-- every twin of each test's first set
		if g.test ~= nil and z ~= nil and z.built and (not seen[g.test] or seen[g.test .. "#" .. tostring(g.set)]) then
			seen[g.test] = true
			seen[g.test .. "#" .. tostring(g.set)] = true
			run.shots[#run.shots + 1] = { z.x, z.y }
			run.shotIds[#run.shotIds + 1] = string.format("%s:%s", g.test, z.id)
		end
	end
	run.shotI = 0
	run.shotDueUs = nowUs()
	phase("shots", string.format("n=%d", #run.shots))
end

local function done()
	local samples = run.samples or 0
	-- speed: the record's (a step-down included); speed_end: after the stop
	rt.log(string.format("[SQST] BENCH_DONE sheet=%s spec=%s@%d seed=%d ok=yes samples=%d speed=%d minutes=%s problems=%d speed_end=%d", run.sheet.key, run.sheet.id,
		run.sheet.version, run.seed, samples, run.recordSpeed or run.speed or 1, logic.minutesText((nowUs() - run.t0Us) / 1000), #run.problems,
		run.speed or 1))
	br.last = string.format("Bench %s done (seed %d): tell Claude \"done\" (make bench).", run.sheet.key, run.seed)
	jn.onRunFinished, jn.onRunAborted, jn.benchActive = nil, nil, false
	run = nil
	br.phase = "idle"
	rt.version = rt.version + 1
end

--- One look of the state machine.
local function step(now : integer)
	local p = run.phase
	if p == "ack" then
		local answered = slzones.ackRun() == run.ackRun
		if not answered and (now - run.phaseUs) / 1000 >= ACK_MS then
			-- no answer to the clear: the zone modes are unknown (a paused game answers nothing)
			abort(string.format("Smart Lanes did not answer within %d s (game paused? an older Smart Lanes without the bench's zone modes?). Unpause the game, or update Smart Lanes, and press again.", ACK_MS // 1000))
			return
		end
		if answered then
			run.info.slModes = slzones.modes()
			local problems = bench.problems(run.sheet, run.info)
			if #problems > 0 then
				abort(table.concat(problems, " "))
				return
			end
			rt.log(bench.startLine(run.sheet, run.info, run.seed))
			-- one BENCH_TEST line per test (the report's tests and comparisons; BENCH.md "Log contract additions")
			for _, tp in ipairs(run.info.plan ~= nil and run.info.plan.tests or {}) do rt.log(bench.testLine(run.sheet, tp)) end
			-- the map cleared: every town (with its streets), then every road left
			local was = towns.ui.removeTarget
			towns.ui.removeTarget = 3
			local okT, list = pcall(function() : {integer}
				local l = towns.removePlan()
				if #l > 0 then towns.removeTowns(l) end
				return l
			end)
			towns.ui.removeTarget = was
			if not okT then
				abort("removing the towns failed: " .. tostring(list))
				return
			end
			phase("clear", string.format("towns=%d", #list))
		end
	elseif p == "clear" then
		if rt.busyJob({ "remove_" }) ~= nil then
			if (now - run.phaseUs) / 1000 > REMOVE_MAX_MS then abort("clearing the map took too long") end
			return
		end
		if not run.roadsQueued then
			run.roadsQueued = true
			local n = roads.count()
			if n > 0 then roads.removeAll() return end
		end
		local y = year()
		if y ~= nil and y < bench.YEAR then
			phase("year", string.format("from=%d to=%d", y, bench.YEAR))
			rt.send("bench_year", api.cmd.makeGameSetDateCmd(api.type.Date.new(bench.YEAR, 1, 1)), function(success : boolean, _d : any)
				local now2 = year()
				rt.log(string.format("[SQST] bench year %d success=%s year now %s", bench.YEAR, tostring(success), tostring(now2)))
				if run == nil or run.phase ~= "year" then return end
				-- the game's own lights start in 1950: a year still earlier would leave the lit tests dark
				if now2 == nil or now2 < bench.YEAR then
					abort(string.format("the year could not be set to %d (it is %s)", bench.YEAR, tostring(now2)))
					return
				end
				startBuild()
			end)
			return
		end
		startBuild()
	elseif p == "year" then
		if (now - run.phaseUs) / 1000 > 30000 then abort(string.format("the year change to %d did not answer within 30 s (game paused?)", bench.YEAR)) end
	elseif p == "build" then
		if not run.finished then
			-- a watchdog on progress: any [SQST] line of the build (rt.lines counts them) resets it
			if rt.lines ~= run.linesSeen then
				run.linesSeen, run.progressUs = rt.lines, now
			elseif (now - (run.progressUs or run.phaseUs)) / 1000 > STALL_MS then
				abort(string.format("the build made no progress for %d minutes (game paused?)", STALL_MS // 60000))
				return
			end
			if (now - run.phaseUs) / 1000 > BUILD_MAX_MS then abort("the build did not finish within 90 minutes") return end
		end
		if run.finished then
			-- Smart Lanes' queue empty before the traffic counts (its late light looks, SL-6, included)
			phase("sl_idle")
			slzones.waitIdle("bench:idle", 60000, function(res : string, ms : number)
				if run == nil or run.phase ~= "sl_idle" then return end
				rt.log(string.format("[SQST] bench smart_lanes idle=%s ms=%.0f", res, ms))
				run.idle = true
			end)
		end
	elseif p == "sl_idle" then
		if run.idle then
			if traffic.ui.keepCleared then
				traffic.setKeepCleared(false)
				rt.log("[SQST] bench: Keep traffic cleared turned off")
			end
			if fl.ui.on then fl.setOn(false) end
			fl.setInterval(bench.INTERVAL)
			-- thru by position is the count (it matched the path count within 1 %, docs/findings/lines-vehicles.md): no
			-- path reads, the sampler's heaviest part (BENCH.md "Thru by position")
			fl.pathThru = false
			fl.setOn(true)
			local sp = bench.speed(run.sheet)
			setSpeed(sp)
			run.gt0 = gameTime()
			phase("warmup", string.format("speed=%d", sp))
		end
	elseif p == "warmup" or p == "record" then
		local gt = gameTime()
		if gt == nil then return end
		if run.gt0 == nil then run.gt0 = gt end
		local samples, skipped = fl.counts()
		if skipped > 0 and run.speed > 1 and not run.steppedDown and p == "warmup" then
			-- a sweep missed its interval: one speed step down (half: 2x -> 1x, the city run's 4x -> 2x), a fresh sampler
			-- run, the warm-up again
			local was = run.speed
			local down = math.max(1, was // 2)
			run.steppedDown = true
			setSpeed(down)
			fl.setOn(false)
			fl.setOn(true)
			run.gt0 = gt
			phase("warmup", string.format("speed=%d (a sample was skipped at %dx)", down, was))
			return
		end
		-- the city run: its enroll once the baseline is recorded (a CITY_ENROLL line splits the report there)
		if p == "record" and run.sheet.city ~= nil and not run.enrolled and gt - run.gt0 >= (run.sheet.baselineS or 0) * 1000 then
			run.enrolled = true
			local last = citylights.last
			local n = last ~= nil and citylights.enroll(run.sheet, last.run, last.crossings, last.plan) or 0
			phase("record", string.format("enroll=%d", n))
		end
		local need = (p == "warmup" and bench.WARMUP_S or bench.recordS(run.sheet)) * 1000
		if gt - run.gt0 >= need then
			if p == "warmup" then
				run.gt0 = gt
				run.recordSpeed = run.speed or 1
				phase("record", string.format("speed=%d samples_so_far=%d", run.speed or 1, samples))
			else
				run.samples = samples
				fl.setOn(false)
				fl.pathThru = true
				setSpeed(1)
				-- the city run: every junction unenrolled again (the written timing stays); its gaps counted once more (a
				-- funnel layout: a street the town grew into a gap during the record shows as CITY_GAPS at=end)
				if run.sheet.city ~= nil then
					citylights.unenroll()
					pcall(citylights.gapCheck, "end")
				end
				phase("stop", string.format("samples=%d skipped=%d", samples, skipped))
				startShots()
			end
		end
	elseif p == "shots" then
		if now < run.shotDueUs then return end
		local i = run.shotI
		if i == 0 then
			-- the first request of a session writes no file (docs/findings "Screenshots"): a primer
			pcall(function() api.gui.camera.takeScreenshot(1) end)
			run.shotI = 1
			run.shotDueUs = now + SHOT_GAP_US
			run.moved = false
			return
		end
		if i > #run.shots then
			done()
			return
		end
		local pt = run.shots[i]
		if not run.moved then
			local okC = pcall(function()
				local cur = api.gui.camera.getCameraData()
				api.gui.camera.setCameraData(api.type.Vec5f.new(pt[1], pt[2], run.sheet.shotDist or SHOT_DIST, cur.w, cur.q))
			end)
			run.moved = okC
			if not okC then run.shotI = i + 1 end
			run.shotDueUs = now + SHOT_SETTLE_US
			return
		end
		local okS = pcall(function() api.gui.camera.takeScreenshot(1) end)
		rt.log(string.format("[SQST] BENCH_SHOT sheet=%s n=%d id=%s x=%.0f y=%.0f ok=%s", run.sheet.key, i, run.shotIds[i], pt[1], pt[2], tostring(okS)))
		run.shotI = i + 1
		run.moved = false
		run.shotDueUs = now + SHOT_GAP_US
	end
end

rt.addTickHook(function(now : integer)
	if run == nil or now < run.nextUs then return end
	run.nextUs = now + POLL_US
	if rt.queueClears ~= run.clearsSeen then
		abort("Clear queue")
		return
	end
	local ok, err : boolean, any = pcall(step, now)
	if not ok then abort("error: " .. tostring(err)) end
end)

--- Starts sheet `key` (after the window's confirm). false and why when it can't.
function br.start(key : string, seedArg? : integer) : boolean, string
	local sheet = br.sheetFor(key)
	if sheet == nil then return false, "unknown sheet" end
	if run ~= nil then return false, "a bench is running" end
	local info = readInfo(sheet)
	-- everything but the zone modes now (those after Smart Lanes answers the clear)
	info.slModes = bench.needs(sheet)
	local problems = bench.problems(sheet, info)
	if #problems > 0 then
		rt.warn(sheet.title, table.concat(problems, "\n"))
		return false, problems[1]
	end
	info.slModes = nil
	local okT, t = pcall(os.time)
	local seed = seedArg or logic.showcaseSeed(((okT and t ~= nil) and t or 0) * 1000 + math.floor(nowUs() / 1000))
	-- City lights, Same seed: the last city run's seed again (its holes; the Swap roles rerun)
	if seedArg == nil and sheet.city ~= nil and br.cityUi.sameSeed and br.lastCitySeed ~= nil then seed = br.lastCitySeed end
	if sheet.city ~= nil then br.lastCitySeed = seed end
	run = { sheet = sheet, info = info, seed = seed, nextUs = 0, t0Us = nowUs(), clearsSeen = rt.queueClears, problems = {}, speed = 1 }
	-- the other test builds and removals refuse while it runs (stress_hud, buildRun)
	jn.benchActive = true
	rt.keepBalance = true
	-- Smart Lanes' zone modes: a clear with our run id; once it stored that id, its zmodes are current (BENCH.md SL-4)
	run.ackRun = slzones.sendClear("bench_preflight")
	phase("ack", string.format("seed=%d", seed))
	return true, nil
end

return br
