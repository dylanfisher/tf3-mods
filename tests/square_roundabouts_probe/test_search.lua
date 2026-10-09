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
