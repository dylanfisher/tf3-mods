-- Phase 4 search subsets: candidates, job expansion, dev params against the real geometry,
-- runner early exit / full grids / skips, T and S lines, the dev override check.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local grid = ug_require "/probe/probe_grid.lua"
local runner = ug_require "/probe/probe_runner.lua"
local geomInfo = ug_require "/probe/probe_geom.lua"
local engineMod = ug_require "/probe/probe_engine.lua"

local rb = H.loadRoundabouts()

local function job(block)
	local jobs = grid.expand({ block })
	return jobs[1], jobs
end

local function labels(cands)
	local out = {}
	for i, c in ipairs(cands) do out[i] = c.label end
	return out
end

test("dev params: probe names == square_roundabouts geom.DEV_KEYS, DEV_ORDER lists each once", function()
	eq(grid.DEV, rb.geom.DEV_KEYS)
	local seen = {}
	for _, name in ipairs(grid.DEV_ORDER) do
		ok(grid.DEV[name], name)
		ok(not seen[name], name .. " twice")
		seen[name] = true
	end
	for name in pairs(grid.DEV) do ok(seen[name], name .. " missing from DEV_ORDER") end
	eq(grid.SEARCH.MAGIC_OFFSET, rb.geom.RING_OFFSET[1])
	eq(#rb.geom.DEV_LEGS, #grid.SEARCH.SPLIT.legs)
end)

test("radius candidates: the slider value, then 5 m steps (and slider radii) up to 120 m; first accepted", function()
	local j = job({ entry = "main", radius = { "8" }, search = { kind = "radius" } })
	eq(j.search.first, true)
	local c = j.search.cands
	eq(c[1].dev, { radius = 8 })
	eq(c[2].dev, { radius = 10 })
	eq(c[3].dev, { radius = 12 }) -- slider radius between the steps
	eq(c[4].dev, { radius = 15 })
	eq(c[#c].dev, { radius = 120 })
	eq(#c, 25)
	eq(c[1].label, "radius=8")
	eq(#job({ entry = "main", radius = { "20" }, search = { kind = "radius" } }).search.cands, 21)
	eq(#job({ entry = "main", radius = { "12" }, search = { kind = "radius" } }).search.cands, 23) -- 12, 15, ..., 120
end)

test("splitter candidates: 108, unique, most compact first; fixed radius in every candidate", function()
	local j = job({ entry = "main", splitter = { "on" }, arm = { "town_l" }, search = { kind = "splitter", fixed = { { radius = 20 } } } })
	local c = j.search.cands
	eq(#c, 108)
	eq(j.search.first, false)
	eq(c[1].dev, { radius = 20, leg = 1, fork = 35, split = 20, spread = 6, neck = 0 })
	local seen = {}
	for i, x in ipairs(c) do
		ok(not seen[x.label], "duplicate " .. x.label)
		seen[x.label] = true
		eq(x.dev.radius, 20)
		if i > 1 then
			local p = c[i - 1].dev
			ok(p.split + p.neck <= x.dev.split + x.dev.neck, "compactness order at " .. i)
		end
	end
	eq(j.id, j.key .. "#splitter#radius=20")
end)

test("magic and tram candidates", function()
	local m = job({ entry = "magic", search = { kind = "magic_size" } })
	eq(labels(m.search.cands), { "magicSize=1", "magicSize=2", "magicSize=3", "magicSize=4", "magicSize=5" })
	local s = job({ entry = "magic", search = { kind = "magic_spacing", fixed = { { magicRadius = 12 } } } })
	eq(s.search.cands[1].dev, { magicRadius = 12, magicDistance = 35 }) -- 2 x 17 m -> 35
	eq(s.search.first, true)
	raises(function() job({ entry = "magic", search = { kind = "magic_spacing" } }) end, "needs fixed")
	local t = job({ entry = "main", centre = { "tram" }, search = { kind = "tram_stub", fixed = { { radius = 15 } } } })
	eq(#t.search.cands, #grid.SEARCH.TRAM_STUBS)
	eq(t.search.cands[1].dev, { radius = 15, tramStub = 6 })
	raises(function() job({ entry = "main", search = { kind = "nope" } }) end, "unknown search kind")
end)

local EXPECTED_JOBS = {
	search_quick = 178,
	search_magic = 12 + 36,
	search_tram = 30 + 288,
	search_splitter = 72 + 4,
	search_radius = 10368 - 3456 - 288,
	search_radius_split = 2 * 3 * 4 * 5 * 3 * 4 * 2,
}
EXPECTED_JOBS.search = EXPECTED_JOBS.search_magic + EXPECTED_JOBS.search_tram + EXPECTED_JOBS.search_splitter + EXPECTED_JOBS.search_radius

test("search subsets: job counts, exclusions, unique ids; quick stays under 2 minutes", function()
	for name, n in pairs(EXPECTED_JOBS) do
		local jobs = grid.expand(name)
		eq(#jobs, n, name)
		eq(grid.size(name), n, name .. " (size)")
		local ids = {}
		for _, j in ipairs(jobs) do
			ok(j.search and j.id, name .. ": search job")
			ok(not ids[j.id], name .. ": duplicate " .. j.id)
			ids[j.id] = true
		end
	end
	for _, j in ipairs(grid.expand("search_radius")) do
		local l = grid.labelsByKey(j.entry, j)
		if l.splitter == "on" then
			ok(l.arms ~= "none", j.key)
			ok(l.arm == "town_s" or l.arm == "country_s", j.key)
		end
	end
	for _, j in ipairs(grid.expand("search_radius_split")) do eq(j.search.requireRule, "splitter") end
	-- at about 40 engine calls/s, even if every candidate were tried
	ok(grid.maxCalls(grid.expand("search_quick")) <= 4800, "search_quick upper bound")
end)

test("dev params reach the real geometry exactly (readDev round trip) and stay sane", function()
	local function check(j)
		for _, c in ipairs(j.search.cands) do
			local p = grid.withDev(j.params, c.dev)
			eq(rb.geom.readDev(p), c.dev, j.id .. " " .. c.label)
			local g = geomInfo.forEntry(j.entry, rb, p)
			ok(g.error == nil, j.id .. " " .. c.label .. ": " .. tostring(g.error))
			ok(g.sane, j.id .. " " .. c.label .. ": " .. tostring(g.insane))
			if j.entry == "main" and c.dev.radius then eq(g.effR, c.dev.radius) end
			if j.entry == "magic" and c.dev.magicSize then eq(g.effSize, c.dev.magicSize) end
		end
	end
	for _, j in ipairs(grid.expand("search_quick")) do check(j) end
	-- the full splitter grid on the tightest ring of the splitter search, every wide arm road
	for _, j in ipairs(grid.expand({ { entry = "main", lanes = { "1" }, arms = { "6" }, splitter = { "on" },
		arm = { "town_m", "town_l", "country_m", "country_l" }, search = { kind = "splitter", fixed = { { radius = 20 } } } } })) do
		check(j)
	end
	for _, j in ipairs(grid.expand("search_magic")) do check(j) end
end)

-- runner with a fake engine ---------------------------------------------------------------------

local function fakeRun(jobs, evaluate, opts)
	opts = opts or {}
	local lines, t, calls = {}, 0, 0
	local r = runner.new({
		combos = jobs,
		subset = "test",
		progressEvery = opts.progressEvery or 1000,
		deps = {
			evaluate = function(trial)
				calls = calls + 1
				return evaluate(trial)
			end,
			log = function(l) lines[#lines + 1] = l end,
			now = function() t = t + 1 return t end,
			skip = opts.skip,
			ship = function() return { effR = 30 } end,
		},
	})
	local steps = 0
	while not r:step(opts.batch or 4) do steps = steps + 1 end
	return r, lines, calls, steps
end

local function parsed(lines, kind)
	local out = {}
	for _, l in ipairs(lines) do
		local k, f = H.parseLine(l)
		if k == kind then out[#out + 1] = f end
	end
	return out
end

test("runner: radius search stops at the first accepted radius (early exit)", function()
	local _, jobs = job({ entry = "main", radius = { "8", "20" }, search = { kind = "radius" } })
	local r, lines, calls = fakeRun(jobs, function(trial)
		return { ok = trial.params.sqrb_dev_radius >= 25, messages = {} }
	end)
	-- 8: 8, 10, 12, 15, 20, 25 -> 6 calls; 20: 20, 25 -> 2 calls
	eq(calls, 8)
	eq(r.calls, 8)
	eq(#parsed(lines, "T"), 8)
	local s = parsed(lines, "S")
	eq(#s, 2)
	eq(s[1].found, "true")
	eq(s[1].best, "radius=25")
	eq(s[1].devRadius, "25")
	eq(s[1].tried, "6")
	eq(s[1].rejected, "radius=8|radius=10|radius=12|radius=15|radius=20")
	eq(s[1].shipR, "30")
	eq(s[1].kind, "radius")
	eq(s[2].tried, "2")
	local _, e = H.parseLine(lines[#lines])
	eq(e.calls, "8")
	eq(e.found, "2")
	eq(e.none, "0")
	local _, st = H.parseLine(lines[1])
	eq(st.maxCalls, "46")
end)

test("runner: full grids try every candidate; none found; skips cost no call", function()
	local _, jobs = job({ entry = "main", splitter = { "on" }, arm = { "town_l", "town_s" },
		search = { kind = "splitter", fixed = { { radius = 20 } }, values = { legs = { 1, 3 }, forks = { 40 }, splits = { 26 }, spreads = { 6 }, necks = { 0 } } } })
	local r, lines, calls = fakeRun(jobs, function(trial)
		return { ok = trial.params.sqrb_dev_leg == 3 and trial.params.sqrb_arm_type == 1, messages = { "x" } }
	end, { batch = 1 })
	eq(calls, 4)
	local s = parsed(lines, "S")
	eq(s[1].found, "false") -- town_l: nothing accepted
	eq(s[1].accepted, "0")
	eq(s[2].found, "true")
	eq(s[2].best, "split=26 fork=40 spread=6 leg=3 neck=0")
	eq(s[2].acceptedList, s[2].best)
	eq(s[2].devLeg, "3")
	eq(r.jobs.none, 1)
	eq(r.jobs.found, 1)

	local r2, lines2, calls2 = fakeRun(jobs, function() return { ok = true } end, {
		skip = function(j) return grid.labelsByKey(j.entry, j).arm == "town_l" and "no rule" or nil end,
	})
	eq(calls2, 2) -- town_l skipped; town_s: first = false, so both candidates are tried
	local s2 = parsed(lines2, "S")
	eq(s2[1].skipped, "no rule")
	eq(s2[1].tried, "0")
	eq(r2.jobs.skipped, 1)
end)

test("runner: batch = engine calls per step; plain combos and search jobs mix", function()
	local jobs = grid.expand({ { entry = "magic" }, { entry = "magic", search = { kind = "magic_size" } } })
	local _, lines, calls, steps = fakeRun(jobs, function() return { ok = false, messages = { "no" } } end, { batch = 2 })
	eq(calls, 6)
	eq(steps, 2) -- 3 steps of 2 calls (the last returns true)
	eq(#parsed(lines, "R"), 1)
	eq(#parsed(lines, "T"), 5)
	eq(parsed(lines, "S")[1].found, "false")
end)

test("probe_geom: degenerate geometry is flagged (and never sent)", function()
	local nan = 0 / 0
	eq(geomInfo.insane({ { role = "ring", edges = { { p0 = { 0, 0, 0 }, p1 = { 10, 0, 0 }, t0 = { 10, 0, 0 }, t1 = { 10, 0, 0 } } } } }), nil)
	ok(geomInfo.insane({ { role = "ring", edges = { { p0 = { nan, 0, 0 }, p1 = { 10, 0, 0 }, t0 = { 10, 0, 0 }, t1 = { 10, 0, 0 } } } } }):find("not finite", 1, true))
	ok(geomInfo.insane({ { role = "arms", edges = { { p0 = { 0, 0, 0 }, p1 = { 0.2, 0, 0 }, t0 = { 1, 0, 0 }, t1 = { 1, 0, 0 } } } } }):find("shorter", 1, true))
	-- dev radius below what the offline model accepts: built anyway, offline = false
	local c = grid.combo("main", { 1, 1, 1, 5, 2, 1, 3, 1, 1, 1, 1 }) -- 6 arms, splitter, town large, 1 lane
	local g = geomInfo.forEntry("main", rb, grid.withDev(c.params, { radius = 20 }))
	eq(g.effR, 20)
	eq(g.offline, false)
	eq(g.forced, true)
	-- without the dev radius: the shipped plan (an engine floor the offline model accepts, or growth)
	local g2 = geomInfo.forEntry("main", rb, c.params)
	eq(g2.forced, false)
	ok(g2.offline ~= false)
end)

test("engine: degenerate geometry is not sent; devCheck stops when the overrides are ignored", function()
	local logs = {}
	local eng = engineMod.new({ context = "none" }, function(l) logs[#logs + 1] = l end)
	eng.files.main = "main.con"
	eng.modules = rb
	local sent = 0
	eng.proposalFor = function() sent = sent + 1 error("no api in tests") end
	-- sane == false: no proposal
	local saved = geomInfo.forEntry
	geomInfo.forEntry = function() return { sane = false, insane = "test" } end
	local r = eng:evaluate({ entry = "main", params = {}, key = "m:x" })
	geomInfo.forEntry = saved
	eq(sent, 0)
	eq(r.ok, false)
	ok(r.messages[1]:find("degenerate", 1, true))

	local function withCosts(c20, c60, ok20, ok60)
		local e = engineMod.new({}, function(l) logs[#logs + 1] = l end)
		e.files.main = "main.con"
		e.evaluate = function(_, c)
			local r0 = c.params.sqrb_dev_radius
			if r0 == 20 then return { ok = ok20, cost = c20 } end
			return { ok = ok60, cost = c60 }
		end
		return e:devCheck()
	end
	eq(withCosts(100, 200, true, true), true)
	ok(logs[#logs]:find("reach the updateFn", 1, true))
	eq(withCosts(100, 100, true, true), false)
	ok(logs[#logs]:find("ignores", 1, true))
	eq(withCosts(0, 0, false, true), true)
	ok(logs[#logs]:find("inconclusive", 1, true))
end)

-- Phase 5e searches -------------------------------------------------------------------------------

local P5_JOBS = {
	p5_channel_search = 2 * 6 * 6 * 2,
	p5_interchange_search = 6 + 6 + 6,
	p5_hamburger_radius = 2 * (3 * 2 * 6 * 5),
}
P5_JOBS.p5_search = P5_JOBS.p5_channel_search + P5_JOBS.p5_interchange_search + P5_JOBS.p5_hamburger_radius

test("Phase 5e searches: job counts, grid candidates (shipped values first), engine-call bounds", function()
	for name, n in pairs(P5_JOBS) do
		local jobs = grid.expand(name)
		eq(#jobs, n, name)
		eq(grid.size(name), n, name .. " (size)")
		local ids = {}
		for _, j in ipairs(jobs) do
			ok(j.search and not ids[j.id], name .. ": " .. tostring(j.id))
			ids[j.id] = true
		end
	end
	local chJobs = grid.expand("p5_channel_search")
	eq(#chJobs[1].search.cands, 12)
	eq(chJobs[1].search.first, false)
	eq(chJobs[1].search.cands[1].dev, { chSlipAngle = 40, chCornerGap = 7, chSlipFree = 4 })
	eq(chJobs[1].search.cands[1].label, "chSlipAngle=40 chCornerGap=7 chSlipFree=4")
	local perLayout = {}
	for _, j in ipairs(grid.expand("p5_interchange_search")) do
		local l = grid.labelsByKey(j.entry, j).layout
		perLayout[l] = #j.search.cands
		eq(j.search.cands[1].dev.ixClear, 8)
	end
	eq(perLayout, { two_bridge = 6, dumbbell = 18, peanut = 36 })
	eq(grid.maxCalls(grid.expand("p5_channel_search")), 1728)
	eq(grid.maxCalls(grid.expand("p5_interchange_search")), 360)
	eq(grid.maxCalls(grid.expand("p5_hamburger_radius")), 2 * 3 * 6 * 5 * (25 + 21))
	for _, j in ipairs(grid.expand("p5_hamburger_radius")) do
		local l = grid.labelsByKey(j.entry, j)
		eq(l.centre, "road")
		ok(l.through ~= "same" and l.through ~= l.arm, j.key)
	end
	raises(function() grid.expand({ { entry = "channel", search = { kind = "grid" } } }) end, "needs values")
	raises(function() grid.expand({ { entry = "channel", search = { kind = "grid", values = { order = { "nope" }, nope = { 1 } } } } }) end, "unknown dev override")
end)

test("Phase 5e: dev params reach the channel / interchange geometry and every candidate stays sane", function()
	for _, name in ipairs({ "p5_channel_search", "p5_interchange_search" }) do
		for _, j in ipairs(grid.expand(name)) do
			for _, c in ipairs(j.search.cands) do
				local p = grid.withDev(j.params, c.dev)
				eq(rb.geom.readDev(p), c.dev, j.id .. " " .. c.label)
				local g = geomInfo.forEntry(j.entry, rb, p)
				ok(g.error == nil, j.id .. " " .. c.label .. ": " .. tostring(g.error))
				ok(g.sane, j.id .. " " .. c.label .. ": " .. tostring(g.insane))
			end
		end
	end
	-- the hamburger radius search builds exactly the candidate radius
	for _, j in ipairs(grid.expand({ { entry = "main", lanes = { "1", "4" }, radius = { "8" }, arms = { "6" }, centre = { "road" },
		arm = { "town_s" }, through = { "town_l", "country_l" }, search = { kind = "radius" } } })) do
		for _, c in ipairs(j.search.cands) do
			local g = geomInfo.forEntry(j.entry, rb, grid.withDev(j.params, c.dev))
			ok(g.error == nil and g.sane, j.id .. " " .. c.label)
			eq(g.effR, c.dev.radius)
		end
	end
end)

-- Phase 5f searches
test("Phase 5f searches: the 81 channel combos nothing was accepted for, the 4-lane two-bridge ring", function()
	local jobs = grid.expand("p5f_search")
	eq(#jobs, 81 + 6)
	eq(grid.maxCalls(jobs), 81 * 9 + 6 * 4)
	local ch, ix = 0, 0
	for _, j in ipairs(jobs) do
		eq(j.search.kind, "grid")
		local l = grid.labelsByKey(j.entry, j)
		if j.entry == "channel" then
			ch = ch + 1
			eq(#j.search.cands, 9)
			-- the shipped fallback first, every candidate sets both dev values
			for _, c in ipairs(j.search.cands) do ok(c.dev.chSlipAngle and c.dev.chSlip, c.label) end
			eq(j.search.cands[1].dev, { chSlipAngle = 65, chSlip = 2 })
			local main, side = l.main, l.side
			local wideSide = side == "town_l" or side == "country_l" or (side == "town_m" and l.splitter == "off")
			local wideMain = main == "town_m" or main == "town_l" or main == "country_l"
			ok(wideSide or (l.layout == "X" and wideMain), j.key)
		else
			ix = ix + 1
			eq(l.layout, "two_bridge"); eq(l.lanes, "4")
			eq(j.search.cands[1].dev, { ixAlphaMax = 40 })
		end
	end
	eq(ch, 81); eq(ix, 6)
end)

-- Phase 7d: the Highway Interchange search -------------------------------------------------------
test("Phase 7d search p7_hx_search: jobs, grid candidates (shipped first), engine-call bound", function()
	local jobs = grid.expand("p7_hx_search")
	eq(#jobs, 6 + 30 + 30)
	eq(grid.size("p7_hx_search"), 66)
	eq(grid.maxCalls(jobs), 6 * 4 + 30 * 12 + 30 * 4)
	eq(grid.maxCalls(jobs), 504)
	local ids, kinds = {}, { diamond = 0, gap = 0, loop = 0 }
	for _, j in ipairs(jobs) do
		ok(not ids[j.id], j.id)
		ids[j.id] = true
		eq(j.entry, "highway"); eq(j.search.kind, "grid"); eq(j.search.first, false)
		local l = grid.labelsByKey(j.entry, j)
		eq(l.size, "small"); eq(l.cross, "town_m"); eq(l.ramp, "0"); eq(l.dir, "rht"); eq(l.year, "2020")
		local c1 = j.search.cands[1].dev
		if l.type == "diamond" then
			kinds.diamond = kinds.diamond + 1
			eq(c1, { hxClear = 8, hxGoreRun = 30 })
			eq(#j.search.cands, 4)
		elseif j.search.fixedLabel == "" then
			kinds.gap = kinds.gap + 1
			eq(c1, { hxTermGap = 30, hxClear = 8, hxGoreRun = 30 })
			eq(j.search.cands[1].label, "hxClear=8 hxGoreRun=30 hxTermGap=30")
			eq(#j.search.cands, 12)
		else
			kinds.loop = kinds.loop + 1
			eq(j.search.fixedLabel, "hxTermGap=30")
			eq(c1, { hxTermGap = 30, hxLoopRadius = 25 })
			eq(j.search.cands[3].label, "hxLoopRadius=22.50")
			eq(#j.search.cands, 4)
		end
	end
	eq(kinds, { diamond = 6, gap = 30, loop = 30 })
end)

test("Phase 7d: dev params reach the highway geometry, every candidate stays sane", function()
	local hx = rb.highway
	for _, j in ipairs(grid.expand("p7_hx_search")) do
		local ship = geomInfo.forEntry(j.entry, rb, j.params)
		for _, c in ipairs(j.search.cands) do
			local p = grid.withDev(j.params, c.dev)
			eq(rb.geom.readDev(p), c.dev, j.id .. " " .. c.label)
			local spec = hx.readParams(p)
			eq(spec.dev, c.dev)
			local b = hx.build(spec)
			local g = geomInfo.forEntry(j.entry, rb, p)
			ok(g.error == nil, j.id .. " " .. c.label .. ": " .. tostring(g.error))
			ok(g.sane, j.id .. " " .. c.label .. ": " .. tostring(g.insane))
			ok(not b.forced, j.id .. " " .. c.label .. ": forced")
			eq(b.frame.clear, c.dev.hxClear or 8)
			if c.dev.hxGoreRun then eq(b.frame.goreRun, c.dev.hxGoreRun) end
			if hx.hasLoops(spec) then
				eq(b.Ro - b.R, c.dev.hxTermGap or hx.TERM_GAP, j.id .. " " .. c.label)
				eq(b.R, c.dev.hxLoopRadius or 25, j.id .. " " .. c.label)
				eq(g.effR, b.R)
			end
		end
		-- the shipped candidate builds exactly the shipped layout
		local g1 = geomInfo.forEntry(j.entry, rb, grid.withDev(j.params, j.search.cands[1].dev))
		eq(g1.xm, ship.xm, j.id); eq(g1.term, ship.term, j.id); eq(g1.edges, ship.edges, j.id)
	end
end)

test("engine: highway template INFO line (R3), read only, never raises", function()
	local names = engineMod.templateNames(rb.ramps)
	ok(names[1]:find("highway_new_small.street_template", 1, true), names[1])
	eq(#names, 3)
	eq(engineMod.templateNames(nil)[1], "::/infrastructure/street/highway/highway_new_small.street_template")
	local tpl = {
		maxSlope = 0.1, maxSlopeShape = 0.12, maxSlopeBuild = 0.1, minCurveRadius = 30, minCurveRadiusBuild = 50,
		speedCoeffs = { 0.85, 0.6, 1 }, laneConfigs = { { speed = 5 }, { speed = 33.3333 }, { speed = 5 } }, country = true,
	}
	local text = engineMod.describeTemplate("x.street_template", 7, tpl)
	eq(text, "street template x.street_template id 7: maxSlope=0.1 maxSlopeShape=0.12 maxSlopeBuild=0.1 "
		.. "minCurveRadius=30 minCurveRadiusBuild=50 speedCoeffs=0.85/0.6/1 laneSpeeds=5/33.33/5 country=true")
	ok(engineMod.describeTemplate("y", -1, nil):find("not found", 1, true))
	ok(engineMod.describeTemplate("z", 3, {}):find("maxSlope=- ", 1, true))
	-- logTemplates with a stubbed repository: one INFO line per template, errors caught
	local logs = {}
	local e = engineMod.new({}, function(l) logs[#logs + 1] = l end)
	e.modules.ramps = rb.ramps
	local saved = api
	api = { res = { streetTemplateRep = {
		find = function(n) if n:find("large", 1, true) then error("boom") end return n:find("small", 1, true) and 4 or -1 end,
		get = function(id) return tpl end,
	} } }
	local okCall, err = pcall(function() e:logTemplates() end)
	api = saved
	ok(okCall, tostring(err))
	eq(#logs, 3)
	ok(logs[1]:find("INFO street template ::/infrastructure/street/highway/highway_new_small.street_template id 4: maxSlope=0.1 ", 1, true), logs[1])
	ok(logs[2]:find("not found", 1, true), logs[2])
	ok(logs[3]:find("error: ", 1, true) and logs[3]:find("not found", 1, true), logs[3])
end)

-- Phase 7e fix-up (p7_spot): evaluate with a place uses its own transf and context, and logs one D
-- line with classified collisions and the terrain under the nodes (stubbed api).
test("p7_spot: place transf, context per place, D line", function()
	local logs = {}
	local e = engineMod.new({ context = "none", pos = "camera", x = 0, y = 0 }, function(l) logs[#logs + 1] = l end)
	e.modules = rb
	-- the per-type entries (Phase 7c2) as resolved
	for _, f in ipairs(grid.ENTRIES.highway.files) do e.files[f] = "square_roundabouts::/" .. f end
	-- the default file is cached under the entry name (engine:resolveFile); since 7c3 the A4 / B4
	-- types share it (Parclo)
	e.files.highway = "square_roundabouts::/" .. grid.ENTRIES.highway.file
	e.player = 7
	local made = {}
	local function vec(...) return { ... } end
	local saved = api
	api = {
		type = {
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec4f = { new = vec },
			Mat4f = { new = vec },
			Context = { new = function() local c = {} made[#made + 1] = c return c end },
			SimpleProposal = { new = function() return {} end, ConstructionEntity = { new = function() return {} end } },
			ComponentType = { BASE_EDGE_STREET = "S", CONSTRUCTION = "C" },
		},
		gui = {
			camera = { getCameraData = function() return { x = 1000.25, y = -500.5, z = 800 } end },
			mouse = { hasTerrainPosition = function() return false end },
		},
		engine = {
			terrain = {
				getHeightAt = function(v) return 50 + v.x * 0.01 end, -- a 1 % slope along x
				isOnWater = function() return false end,
				isValidCoordinate = function() return true end,
			},
			entityExists = function(id) return id == 42 end,
			getComponent = function(id, t) if t == "S" then return {} end return nil end,
			util = { construction = { getConstructionResult = function() return {} end }, proposal = { makeProposalData = function(sp, ctx)
				made.lastCtx, made.lastTransf = ctx, sp.constructionsToAdd[1].transf
				return { errorState = { critical = false, messages = { "Construction Not Possible" } },
					collisionInfo = { collisionEntities = { { entity = 42 }, { entity = -3 } }, buildingEntities = {} },
					terrainPreviewHeightModCutFill = { { x = 1, y = 2 }, { x = 3, y = 4 } }, costs = 5 }
			end } },
		},
	}
	local okCall, err = pcall(function()
		e:placement()
		local combos = grid.expand("p7_spot")
		local c = combos[1]
		for _, k in ipairs(combos) do if k.place.rot == 90 and k.place.ctx == "terrain" then c = k break end end
		return e:evaluate(c)
	end)
	api = saved
	ok(okCall, tostring(err))
	local r = err
	eq(e.x, 1000.25); eq(e.y, -500.5)
	ok(logs[1]:find("position source camera", 1, true), logs[1])
	eq(r.ok, false)
	ok(made.lastCtx and made.lastCtx.checkTerrainAlignment == true and made.lastCtx.player == 7, "terrain context")
	eq(made.lastCtx.cleanupStreetGraph, nil)
	local t = made.lastTransf
	ok(math.abs(t[1][1]) < 1e-12 and t[1][2] == 1 and t[2][1] == -1, "90 degrees")
	eq(t[4][1], 1000.25)
	local d = logs[#logs]
	local kind, f = H.parseLine(d)
	eq(kind, "D")
	eq(f.collIds, "42:street|-3:new"); eq(f.coll, "2"); eq(f.cut, "4.00"); eq(f.fill, "6.00"); eq(f.hmods, "2")
	eq(f.rot, "90"); eq(f.ctx, "terrain"); eq(f.offMap, "0")
	ok(tonumber(f.nodes) > 20, f.nodes)
	-- rotated 90 degrees the highway runs along world y: no slope along it, the cross road's +-126.5 m
	-- arms run along x: terrain within +-1.27 m (1 % slope); the arm ends at 8 m are fill
	ok(tonumber(f.terrMax) <= 1.27 + 1e-6 and tonumber(f.terrMin) >= -1.27 - 1e-6, f.terrMin .. " " .. f.terrMax)
	ok(tonumber(f.fillMax) > 6, f.fillMax)
end)

test("spot subsets place at the camera unless Position says Mouse", function()
	eq(engineMod.positionSource({ pos = "setting", subset = "p7_spot2" }), "camera")
	eq(engineMod.positionSource({ pos = "setting", subset = "p7_spot" }), "camera")
	eq(engineMod.positionSource({ pos = "mouse", subset = "p7_spot2" }), "mouse")
	eq(engineMod.positionSource({ pos = "setting", subset = "p7_verify" }), "setting")
	-- Phase 7d2: the Scale and preset runs use the Position setting (flat map, 0 / 0)
	eq(engineMod.positionSource({ pos = "setting", subset = "p7_hx_scale" }), "setting")
	eq(engineMod.positionSource({ pos = "setting", subset = "p7_presets" }), "setting")
end)

-- 2026-10-09 (docs/findings.md "Negative zero in construction geometry"): the probe's 0-degree transf
-- is the UI builder's 1/-0/0/0/0/1, not a +0 identity, so a -0 tangent is refused offline-reproducibly.
test("engine.cosSin: Rotation 0 has sin = -0 like the builder; other angles as math.sin", function()
	local function neg0(v) return v == 0 and 1 / v < 0 end
	local c, s = engineMod.cosSin(0)
	eq(c, 1); ok(neg0(s), "sin(0) = -0")
	ok(not neg0(-s), "row 2 = +0")
	c, s = engineMod.cosSin(90)
	ok(math.abs(c) < 1e-12 and s == 1)
	engineMod.BUILDER_ZERO = false
	c, s = engineMod.cosSin(0)
	engineMod.BUILDER_ZERO = true
	ok(not neg0(s), "BUILDER_ZERO = false: the old +0 identity")
end)

-- Phase 7d2: p7_presets sends the preset key as the menu does; p7_hx_scale the entry's Layout index.
test("engine:paramsFor: p7_presets preset keys, p7_hx_scale Layout per type", function()
	local e = engineMod.new({ context = "none", pos = "setting", x = 0, y = 0 }, function() end)
	for _, c in ipairs(grid.expand("p7_presets")) do
		local p = e:paramsFor(c)
		if c.entry == "main" then ok(p.sqrb_radius_size and p.sqrb_radius, c.key) end
		if c.entry == "interchange" then ok(p.sqrb_ix_radius_size and p.sqrb_ix_radius, c.key) end
	end
	local hw = grid.ENTRIES.highway
	for _, c in ipairs(grid.expand("p7_hx_scale")) do
		local t = c.params[hw.fileAxis]
		eq(e:paramsFor(c)[hw.layoutKey], hw.layouts[t], c.key)
	end
end)
