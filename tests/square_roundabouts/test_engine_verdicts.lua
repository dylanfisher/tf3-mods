-- Engine verdicts replayed against the shipped geometry (Phase 4b). Every combo the engine
-- rejected in the probe runs (plans/square_roundabouts/probe_search*.csv: the searches;
-- probe_results.csv: the `all` sweep of the Phase 3b geometry) must now ship a layout the engine
-- accepted, exactly as the probe built it, or fall in a documented known-gap category
-- (verdicts.lua V.GAPS, PLAN.md "Phase 4b notes"). Rejections of the Phase 4b verification sweep
-- (probe_results_4b.csv, once run) are listed too. The synthetic tests keep the replay honest.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local hx = ug_require(DIR .. "square_roundabouts_highway.lua")

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local V = loadfile(here .. "verdicts.lua", "t", _ENV)()
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local PLANS = here .. "../../plans/square_roundabouts/"

local function with(t, fn)
	geom.setTuning(t)
	local okRun, err = pcall(fn)
	geom.setTuning(nil)
	if not okRun then error(err, 0) end
end
local EMPTY = { radius = {}, magic = {}, splitter = {} }

local DEFAULT_KEY = "m:1,2,1,3,1,1,1,1,1,1,1" -- defaults at 8 m

test("synthetic: radius replay catches a shipped radius the engine rejected, passes with the engine radius", function()
	local jobs = { {
		kind = "radius", fixed = "", skipped = "", key = DEFAULT_KEY, radius = "8",
		found = "true", devRadius = "15", rejected = "radius=8|radius=10|radius=12",
	} }
	with(EMPTY, function()
		local problems = V.radius(geom, magic, jobs)
		eq(#problems, 1) -- ships 8: rejected
		eq(V.neutral(geom.tuning), true)
	end)
	local spec = geom.readParams((V.params(DEFAULT_KEY, geom.PARAM_KEYS, magic.PARAM_KEYS)))
	with({ radius = { [geom.patternKey(spec)] = { [8] = 15 } }, magic = {}, splitter = {} }, function()
		eq(V.radius(geom, magic, jobs), {})
		eq(V.neutral(geom.tuning), false)
	end)
	-- none found: the shipped radius is a gap, not a problem
	jobs[1].found, jobs[1].devRadius = "false", "-"
	with(EMPTY, function()
		local problems, gaps = V.radius(geom, magic, jobs)
		eq(problems, {})
		eq(#gaps, 1)
		eq(gaps[1][1], "none")
	end)
end)

test("synthetic: magic and splitter replay", function()
	local mj = { { kind = "magic_size", fixed = "", key = "g:1,3,1,1", acceptedList = "magicSize=5" } }
	with(EMPTY, function()
		ok(#V.magicSize(magic, mj) > 0, "town large ships size 4, engine only took 5")
	end)
	with({ magic = { ["3,1"] = { [1] = 5, [2] = 5, [3] = 5, [4] = 5 } } }, function()
		eq(V.magicSize(magic, mj), {})
	end)
	-- 2-lane satellites (search_magic2, key "g:size,arm,dir,island,2"): the "arm,dir,2" row, else
	-- the 1-lane row (a probed empty 2-lane row replaces the fallback)
	eq(V.magicRowKey("g:1,3,1,1"), "3,1"); eq(V.magicRowKey("g:1,3,2,1,1"), "3,2"); eq(V.magicRowKey("g:1,3,2,1,2"), "3,2,2")
	eq(V.magicLanes("g:1,3,1,1"), 1); eq(V.magicLanes("g:1,3,1,1,2"), 2)
	eq(V.params("g:1,3,1,1", nil, magic.PARAM_KEYS)[magic.PARAM_KEYS.lanes], nil)
	eq(V.params("g:1,3,1,1,2", nil, magic.PARAM_KEYS)[magic.PARAM_KEYS.lanes], 2)
	local mj2 = { { kind = "magic_size", fixed = "", key = "g:3,1,1,1,2", acceptedList = "magicSize=5" } }
	local all5 = { [1] = 5, [2] = 5, [3] = 5, [4] = 5 }
	with({ magic = { ["1,1,2"] = all5 } }, function() eq(V.magicSize(magic, mj2), {}) end)
	with({ magic = { ["1,1"] = all5 } }, function() eq(V.magicSize(magic, mj2), {}, "1-lane row as the fallback") end)
	with({ magic = { ["1,1"] = all5, ["1,1,2"] = {} } }, function()
		ok(#V.magicSize(magic, mj2) > 0, "the probed 2-lane row (no floor) wins over the 1-lane fallback")
	end)
	local function trial(lanes, radius, okv, split)
		return { kind = "splitter", key = "m:1," .. lanes .. ",5,3,2,1,3,1,1,1,1", ok = okv, devRadius = tostring(radius),
			devSplit = tostring(split or 20), devFork = "50", devSpread = "6", devLeg = "2", devNeck = "0" }
	end
	local trials = { trial(2, 20, "false"), trial(2, 40, "true"), trial(1, 20, "false"), trial(1, 40, "false"), trial(1, 40, "true", 32) }
	local rule = { split = 20, fork = 50, spread = 6, leg = 2, neck = 0 }
	with({ splitter = { ["3,2"] = { split = 20, fork = 50, spread = 6, leg = 2, neck = 0, floor = { [3] = 40 } } } }, function()
		local problems, gaps = V.splitter(geom, trials)
		eq(problems, {})
		eq(gaps, {})
	end)
	with({ splitter = { ["3,2"] = { split = 20, fork = 50, spread = 6, leg = 2, neck = 0, floor = { [3] = 20 } } } }, function()
		eq(#V.splitter(geom, trials), 1, "rejected at its floor")
	end)
	with({ splitter = { ["3,1"] = { split = 20, fork = 50, spread = 6, leg = 2, neck = 0, floor = { [3] = 60 } } } }, function()
		local problems, gaps = V.splitter(geom, trials)
		eq(problems, {})
		eq(#gaps, 1, "accepted at no probed radius: provisional")
		eq(gaps[1][1], "provisional")
		eq(V.provisionalFloors(geom, trials)["3,1,3"], true)
	end)
	with({ splitter = { ["3,1"] = { split = 32, fork = 50, spread = 6, leg = 2, neck = 0, floor = { [3] = 40 } } } }, function()
		eq(V.splitter(geom, trials), {})
	end)
	ok(rule)
end)

test("synthetic: interchange replay (Phase 5g: a radius an accepted sweep row or alpha trial placed)", function()
	local shipped = 30
	local fakeIx = {
		PARAM_KEYS = setmetatable({}, { __index = function(_, k) return k end }),
		readParams = function(p) return p end,
		build = function() return { radius = shipped } end,
	}
	local key = "x:1,1,1,3,1,2,2,1,1,1,2"
	local rejected = { entry = "interchange", key = key, ok = "false", effR = "25" }
	local accepted40 = { entry = "interchange", key = key, ok = "true", effR = "35" }
	local function run(sweep, trials)
		local problems, gaps = V.interchange(geom, fakeIx, sweep, trials)
		return #problems, #gaps
	end
	eq({ run({ rejected, accepted40 }) }, { 0, 2 }, "30 m placed nowhere: both rows are gaps")
	local trial = { entry = "interchange", key = key, ok = "true", effR = "30", devIxAlphaMax = "45", devIxClear = "-" }
	eq({ run({ rejected, accepted40 }, { trial }) }, { 0, 0 }, "the alpha trial placed 30 m")
	eq({ run({ rejected, accepted40 }, { { entry = "interchange", key = key, ok = "true", effR = "30", devIxClear = "4" } }) }, { 0, 2 },
		"a trial with another dev value builds another layout")
	eq({ run({ rejected, accepted40, { entry = "interchange", key = key, ok = "true", effR = "30" } }) }, { 0, 0 }, "a later sweep placed it")
	shipped = 25
	eq({ run({ rejected }) }, { 1, 0 }, "ships the rejected radius")
	shipped = 35
	eq({ run({ accepted40 }) }, { 0, 0 }, "unchanged accepted row")
end)

test("synthetic: highway replay (Phase 7e: a refused layout still shipped, a new layout, a later placement)", function()
	local layout = { size = 25, xm = 175.5, yTi = 80.5, yTo = 110.5 }
	local fakeHx = {
		PARAM_KEYS = setmetatable({}, { __index = function(_, k) return k end }),
		readParams = function(p) return p end,
		build = function() return layout end,
	}
	local key = "h:1,3,2,2,1,1,1,1,2"
	local refused = { entry = "highway", key = key, ok = "false", effSize = "25", xm = "175.50", term = "80.5/110.5" }
	local function run(rows)
		local problems, gaps = V.hx(fakeHx, rows)
		return #problems, #gaps
	end
	eq({ run({ refused }) }, { 1, 0 }, "ships the refused layout")
	layout = { size = 25, xm = 182.5, yTi = 80.5, yTo = 110.5 }
	eq({ run({ refused }) }, { 0, 1 }, "a new layout no row placed: gap")
	eq({ run({ refused, { entry = "highway", key = key, ok = "true", effSize = "25", xm = "182.50", term = "80.5/110.5" } }) }, { 0, 0 },
		"p7_verify placed it")
	eq({ run({ { entry = "highway", key = key, ok = "true", effSize = "25", xm = "182.50", term = "80.5/110.5" } }) }, { 0, 0 }, "unchanged accepted row")
	local p = V.hxParams(hx, "h:6,3,2,4,1,2,3,2,1")
	eq(p, { [hx.PARAM_KEYS.type] = 6, [hx.PARAM_KEYS.highway] = 3, [hx.PARAM_KEYS.level] = 2, [hx.PARAM_KEYS.cross] = 4,
		[hx.PARAM_KEYS.size] = 1, [hx.PARAM_KEYS.rampLength] = 2, [hx.PARAM_KEYS.armLength] = 3,
		[hx.PARAM_KEYS.direction] = 2, year = 1969 })
	-- pre-7c2 keys (7c's sliders): same metres -> today's index, retired values -> nil
	local lp = V.hxParams(hx, "h:1,3,2,4,3,4,4,2,1", true) -- 45 m loops, +60 m ramps, 60 m arms
	eq({ lp[hx.PARAM_KEYS.size], lp[hx.PARAM_KEYS.rampLength], lp[hx.PARAM_KEYS.armLength] }, { 2, 3, 3 })
	-- Phase 7c3: diamond terminals 0 / 40 / 100 m, so 7c's 30 m is retired; 0 m still maps
	eq(V.hxParams(hx, "h:6,3,2,4,3,1,1,2,1", true), nil, "diamond 30 m terminals retired")
	eq(V.hxParams(hx, "h:6,3,2,4,1,1,1,2,1", true)[hx.PARAM_KEYS.size], 1, "diamond 0 m terminals")
	eq(V.hxParams(hx, "h:1,3,2,4,2,1,1,2,1", true), nil, "35 m loops retired")
	eq(V.hxParams(hx, "h:1,3,2,4,1,2,1,2,1", true), nil, "+20 m ramps retired")
	eq(V.hxParams(hx, "h:1,3,2,4,1,1,2,2,1", true), nil, "40 m arms retired")
end)

test("synthetic: CSV reader (quotes, empty fields)", function()
	local path = os.tmpname()
	local f = assert(io.open(path, "w"))
	f:write('a,b,c\r\n1,"x, ""y""",\r\n2,,"z"\r\n')
	f:close()
	local rows = V.readCsv(path)
	os.remove(path)
	eq(#rows, 2)
	eq(rows[1], { a = "1", b = 'x, "y"', c = "" })
	eq(rows[2], { a = "2", b = "", c = "z" })
	eq(V.readCsv(path), nil)
end)

-- One test per group of replay stages (each loads the CSVs, about 0.7 s), so the runner can shard
-- them: radius ~17 s, sweep ~12 s, channel ~14 s, the rest ~1 s. Gap counts print per test.
local CH = DIR .. "square_roundabouts_channel.lua"
local IX = DIR .. "square_roundabouts_interchange.lua"
local function verdictTest(what, run)
	test("engine verdicts: every rejected combo now ships an accepted layout, or a documented gap (" .. what .. ")", function()
		ok(V.readCsv(PLANS .. "probe_search.csv") ~= nil, "plans/square_roundabouts/probe_search.csv is missing")
		ok(V.readCsv(PLANS .. "probe_p5_all.csv") ~= nil, "plans/square_roundabouts/probe_p5_all.csv is missing")
		-- the Phase 4 searches and sweep, the Phase 5e runs (p5_search: p5_hamburger_radius; p5_all:
		-- the hamburger sweep), the Phase 5f runs once they exist
		local all = V.loadAll(PLANS)
		local problems, gaps = {}, {}
		local function add(p, g)
			for _, x in ipairs(p or {}) do problems[#problems + 1] = x end
			for _, x in ipairs(g or {}) do gaps[#gaps + 1] = x end
		end
		run(add, all.jobs, all.trials, all.sweep)
		local shown = {}
		for i = 1, math.min(8, #problems) do shown[i] = problems[i] end
		ok(#problems == 0, #problems .. " verdicts disagree: " .. table.concat(shown, "; "))
		local byCat, example = {}, {}
		for _, g in ipairs(gaps) do
			ok(V.GAPS[g[1]] ~= nil, "undocumented gap category " .. tostring(g[1]))
			byCat[g[1]] = (byCat[g[1]] or 0) + 1
			example[g[1]] = example[g[1]] or g[2]
		end
		local cats = {}
		for c in pairs(byCat) do cats[#cats + 1] = c end
		table.sort(cats)
		for _, c in ipairs(cats) do
			print(string.format("    known gap %-11s %4d  (e.g. %s)", c, byCat[c], example[c]))
		end
	end)
end

verdictTest("radius", function(add, jobs) add(V.radius(geom, magic, jobs)) end)
verdictTest("sweep", function(add, jobs, trials, sweep) add(V.sweep(geom, magic, sweep, jobs, trials)) end)
-- Phase 5f: the Channelized Junction and the Roundabout Interchange (p5_all, p5_search, p5f_*)
verdictTest("channel", function(add, _, trials, sweep) add(V.channel(geom, ug_require(CH), sweep, trials)) end)
verdictTest("magic, splitter, tram, through, interchange, 4b", function(add, jobs, trials, sweep)
	add(V.magicSize(magic, jobs))
	add(V.splitter(geom, trials))
	add(V.tram(geom, magic, trials))
	add(V.through(geom, jobs))
	add(V.interchange(geom, ug_require(IX), sweep, trials))
	-- the verification sweep of the tuned geometry, once it has run (PROBE.md "Phase 4b runs")
	local final = V.readCsv(PLANS .. "probe_results_4b.csv")
	if final then add(V.final(geom, magic, final)) end
end)

-- Phase 7e: the Highway Interchange (p7_hx_all, p7_verify once it exists)
verdictTest("highway", function(add)
	local rows = {}
	for _, name in ipairs(V.HX_FILES) do
		for _, r in ipairs(V.readCsv(PLANS .. name) or {}) do rows[#rows + 1] = r end
	end
	ok(#rows >= 912, "probe_p7_hx_all.csv rows: " .. #rows)
	-- recorded before Phase 7c2: replayed where the values still ship (V.hxParams legacy)
	add(V.hx(hx, rows, true))
	local now = {}
	for _, name in ipairs(V.HX_FILES_7C2) do
		for _, r in ipairs(V.readCsv(PLANS .. name) or {}) do now[#now + 1] = r end
	end
	add(V.hx(hx, now))
end)

test("offline model vs engine: the engine-fitted checks agree with a sample of the probe verdicts", function()
	-- every 25th engine call of the searches (exact dev layouts), rebuilt as the probe built them;
	-- test_replay_report.lua runs all 32,704 (PLAN.md "Phase 4b notes": 92% agreement)
	local trials = V.readCsv(PLANS .. "probe_search_trials.csv") or {}
	local m = { tp = 0, fp = 0, fn = 0, tn = 0 }
	geom.setTuning(EMPTY)
	local okRun, err = pcall(V.legacy, geom, function()
		for i = 1, #trials, 25 do
			local r = trials[i]
			if r.kind ~= "" and V.sent(r) then
				local built = V.probeLayout(geom, magic, r)
				local model = #checks.engineModel(built.lists, built.halfWidth) == 0
				local engine = r.ok == "true"
				local k = model and (engine and "tp" or "fp") or (engine and "fn" or "tn")
				m[k] = m[k] + 1
			end
		end
	end)
	geom.setTuning(nil)
	if not okRun then error(err, 0) end
	local n = m.tp + m.fp + m.fn + m.tn
	ok(n > 500, "sample size " .. n)
	local agree = (m.tp + m.tn) / n
	print(string.format("    sample %d: agree %.1f%%; model ok & engine ok %d, model ok & engine rejects %d, model rejects & engine ok %d, both reject %d",
		n, 100 * agree, m.tp, m.fp, m.fn, m.tn))
	ok(agree >= 0.88, "agreement " .. agree)
	ok(m.fn / n <= 0.01, "false alarms " .. m.fn)
end)
