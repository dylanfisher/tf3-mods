-- otd_simgrow ("Simulate natural growth"): the game's growth curve, its district split, the connectedness spread,
-- the simulation's pace / pause / stop / resume with a fake engine, the UpdateSize command (no forced building
-- update) and the runner's simStart / simStop commands (SIMGROW lines, tour when stopped).

local SG = ug_require "/organic_towns_dev/otd_simgrow.lua"

---------------------------------------------------------------------------
-- curve

test("growth curve: F(1) = 1, F(18) = 40, monotonic; factor 1 at the start level, rising with experience", function()
	near(SG.growthFunction(1), 1, 1e-3)
	near(SG.growthFunction(18), 40, 0.05)
	for l = 1, 30, 0.25 do ok(SG.growthFunction(l + 0.25) > SG.growthFunction(l), "F rises at " .. l) end
	for _, l0 in ipairs({ 1, 2, 3, 4 }) do
		near(SG.growthFactor(SG.expAt(l0), l0), 1, 1e-3, "start of level " .. l0)
		local prev = 0
		for e = SG.expAt(l0), SG.expAt(l0) + 2e6, 5000 do
			local f = SG.growthFactor(e, l0)
			ok(f >= prev, "monotonic in experience")
			prev = f
		end
	end
end)

test("level and fraction follow the game's cost (1000 x 1.5^(n-1) per level); start levels by residential capacity", function()
	eq(SG.expAt(1), 0)
	eq(SG.expAt(2), 1000)
	near(SG.expAt(4), 4750, 1e-6)
	local l, f = SG.levelAndFraction(500)
	eq(l, 1); near(f, 0.5)
	l, f = SG.levelAndFraction(1000 + 750)
	eq(l, 2); near(f, 0.5, 1e-3)
	l = SG.levelAndFraction(4750)
	eq(l, 4)
	eq(SG.initialLevel(90), 1)
	eq(SG.initialLevel(120), 2)
	eq(SG.initialLevel(160), 3)
	eq(SG.initialLevel(250), 4)
end)

test("expForFactor inverts growthFactor", function()
	for _, l0 in ipairs({ 1, 2, 4 }) do
		for _, f in ipairs({ 1.2, 2, 3.5, 8, 20 }) do
			near(SG.growthFactor(SG.expForFactor(f, l0), l0), f, 1e-3, "factor " .. f)
		end
		eq(SG.expForFactor(0.8, l0), SG.expAt(l0), "a town below its start size starts at its start level")
	end
end)

---------------------------------------------------------------------------
-- distribution

test("distribute: the new land use adds up to the target, weights >= min, no district shrinks", function()
	local o = { initials = { 128, 92, 83 }, sizeFactors = { 1, 1, 1 }, mapSum = { 5000, 3500, 3200 }, newSum = 450,
		minWeight = 0.1 }
	local f, d = SG.distribute(o)
	ok(f ~= nil)
	local sum = 0
	for i = 1, 3 do
		sum = sum + o.initials[i] * f[i]
		ok(f[i] >= 1, "no shrink")
		ok(d.weights[i] >= 0.1 - 1e-9, "min weight")
	end
	near(sum, 450, 1e-6)
	near(d.weights[1] + d.weights[2] + d.weights[3], 1, 1e-9)
end)

test("distribute: nothing when the target is not above the current size (the game's floor test)", function()
	local f = SG.distribute({ initials = { 100, 100, 100 }, sizeFactors = { 1.5, 1.5, 1.5 }, newSum = 450.7, minWeight = 0.1 })
	eq(f, nil)
	f = SG.distribute({ initials = { 100, 100, 100 }, sizeFactors = { 1.5, 1.5, 1.5 }, newSum = 451.2, minWeight = 0.1 })
	ok(f ~= nil)
end)

test("distribute: a district over 40 % of the map is dampened toward 0.4; a district with no initial stays 0", function()
	local f, d = SG.distribute({ initials = { 300, 50, 50 }, sizeFactors = { 1, 1, 1 }, mapSum = { 9000, 1000, 1000 },
		newSum = 600, minWeight = 0.1 })
	ok(d.weights[1] <= 0.4 + 1e-9, "residential weight capped by the map share: " .. d.weights[1])
	near(d.weights[1] + d.weights[2] + d.weights[3], 1, 1e-9)
	local g = SG.distribute({ initials = { 100, 100, 0 }, sizeFactors = { 1, 1, 1 }, newSum = 300, minWeight = 0.1 })
	eq(g[3], 0)
end)

test("rebalance: pinned to [min, max] and summing to 1", function()
	local w = SG.rebalance({ 0.9, 0.08, 0.02 }, { 0.1, 0.1, 0.1 }, { 0.5, 1, 1 })
	near(w[1] + w[2] + w[3], 1, 1e-9)
	ok(w[1] <= 0.5 + 1e-9)
	ok(w[2] >= 0.1 and w[3] >= 0.1)
end)

---------------------------------------------------------------------------
-- connectedness

test("rate: deterministic per town + seed; ~25 % none, most slow, a few fast; seed changes it", function()
	local n, counts, rs = 2000, { none = 0, slow = 0, medium = 0, fast = 0 }, {}
	local differ = 0
	for t = 1, n do
		local r, c = SG.rate(1000 + t * 7, 3, 300, false)
		local r2 = SG.rate(1000 + t * 7, 3, 300, false)
		eq(r, r2)
		if SG.rate(1000 + t * 7, 4, 300, false) ~= r then differ = differ + 1 end
		counts[c] = counts[c] + 1
		rs[#rs + 1] = r
	end
	local none = counts.none / n
	ok(none > 0.2 and none < 0.3, "none share " .. none)
	ok(counts.slow > counts.medium and counts.slow > counts.fast, "most connected towns grow slowly")
	ok(counts.slow / n > 0.38 and counts.slow / n < 0.52, "slow share " .. counts.slow / n)
	ok(counts.fast / n > 0.08 and counts.fast / n < 0.16, "a few fast: " .. counts.fast / n)
	local top = 0
	for _, r in ipairs(rs) do if r >= 3 then top = top + 1 end end
	ok(top / n > 0.02 and top / n < 0.07, "metropolis candidates (r >= 3): " .. top / n)
	ok(differ > n / 2, "another seed gives other rates")
end)

test("rate: the size bias connects big towns more often and better", function()
	local small, big, smallNone, bigNone = 0, 0, 0, 0
	for t = 1, 1000 do
		local a = SG.rate(t, 1, 250, true)
		local b = SG.rate(t, 1, 1000, true)
		small, big = small + a, big + b
		if a == 0 then smallNone = smallNone + 1 end
		if b == 0 then bigNone = bigNone + 1 end
		eq(SG.rate(t, 1, 250, true), SG.rate(t, 1, 250, false), "no bias below 250 persons")
	end
	ok(big > small * 1.3, "big towns connected better")
	ok(bigNone < smallNone * 0.7, "big towns less often unconnected")
end)

---------------------------------------------------------------------------
-- simulation with a fake engine

local function persons(w)
	return w.initials[1] * w.sizeFactors[1] + w.initials[2] * w.sizeFactors[2] + w.initials[3] * w.sizeFactors[3]
end

local function fakeEnv(o)
	o = o or {}
	local env = { sent = {}, logs = {}, speedV = 1, paused = false, now = 0 }
	env.T = o.towns or {
		[11] = { initials = { 128, 92, 83 }, sizeFactors = { 1, 1, 1 }, x = 0, y = 0, b = 100 },
		[12] = { initials = { 220, 150, 140 }, sizeFactors = { 1, 1, 1 }, x = 3000, y = 0, b = 200 },
		[13] = { initials = { 60, 40, 40 }, sizeFactors = { 1, 1, 1 }, x = 9000, y = 0, b = 40 },
	}
	function env.towns()
		local ids = {}
		for t in pairs(env.T) do ids[#ids + 1] = t end
		table.sort(ids)
		return ids
	end
	function env.name(t) return "Town " .. t end
	function env.centre(t) return env.T[t].x, env.T[t].y end
	function env.town(t)
		local w = env.T[t]
		if w == nil then return nil end
		return { initials = w.initials, sizeFactors = { w.sizeFactors[1], w.sizeFactors[2], w.sizeFactors[3] }, active = w.active ~= false }
	end
	function env.updateSize(t, f, cb, forced)
		env.sent[#env.sent + 1] = { t = t, f = f, forced = forced == true, year = env.sim and env.sim.years }
		local w = env.T[t]
		-- unforced: the houses stay where they were (the developer's pace); forced: they reach the target at once
		if not forced and w.actual == nil then w.actual = persons(w) end
		w.sizeFactors = { f[1], f[2], f[3] }
		w.b = w.b + 1
		if forced then w.actual = nil end
		if o.holdCallbacks then env.held = env.held or {}; env.held[#env.held + 1] = cb else cb(true) end
	end
	function env.buildings()
		local out = {}
		for t, w in pairs(env.T) do out[t] = w.b end
		return out
	end
	--- built capacity: w.actual (nil = at the target)
	function env.caps(t)
		local w = env.T[t]
		local target = 0
		for i = 1, 3 do target = target + w.initials[i] * w.sizeFactors[i] end
		return { actual = w.actual or target, target = target }
	end
	if o.main then
		env.main = { seen = 0, busy = false, marks = 0 }
		function env.mainMark(towns, _now)
			env.main.marks = env.main.marks + 1
			env.main.seen = 0
			return { towns = towns }
		end
		function env.mainSeen(mark, _now)
			return { seen = env.main.seen, total = #mark.towns, busy = env.main.busy, checks = env.main.seen, builds = 0 }
		end
	end
	function env.speed() return env.speedV end
	function env.minWeight() return 0.1 end
	function env.log(what, fields)
		local parts = { what }
		for _, f in ipairs(fields or {}) do parts[#parts + 1] = f[1] .. "=" .. tostring(f[2]) end
		env.logs[#env.logs + 1] = table.concat(parts, " ")
	end
	return env
end

--- Ticks the sim for `seconds` of real time at 50 ms per tick.
local function run(sim, env, seconds)
	local r
	for _ = 1, math.floor(seconds * 20) do
		env.now = env.now + 50000
		r = sim:tick(env.now) or r
	end
	return r
end


--- A sim whose towns get fixed rates (11: fast, 12: medium, 13: none).
local function fixedSim(env, opts)
	local sim = SG.new(env, opts or { pace = 10, seed = 1 })
	sim:start(env.now, false)
	sim.towns[11].rate, sim.towns[12].rate, sim.towns[13].rate = 3, 1, 0
	return sim
end

test("sim: pace 10 s -> one simulated year per 10 s of running game; towns grow in small steps, rate 0 never", function()
	local env = fakeEnv()
	local sim = fixedSim(env)
	run(sim, env, 10.2)
	eq(sim.years, 1)
	eq(sim.step, 4, "four steps per year")
	local maxJump = 0
	local last = {}
	for _, s in ipairs(env.sent) do
		ok(s.t ~= 13, "a town with rate 0 gets no command")
		if last[s.t] then maxJump = math.max(maxJump, s.f[1] / last[s.t]) end
		last[s.t] = s.f[1]
	end
	ok(#env.sent >= 4, "steps sent: " .. #env.sent)
	ok(maxJump < 1.15, "small steps: " .. maxJump)
	run(sim, env, 20)
	eq(sim.years, 3)
	ok(persons(env.T[11]) > persons(env.T[12]) * 0.6, "the fast town catches up")
	eq(env.T[13].sizeFactors[1], 1, "rate 0: unchanged")
	local yearLines = 0
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW year") then yearLines = yearLines + 1 end end
	eq(yearLines, 3)
end)

test("sim: target follows the game's curve; the sum of the land use equals the target after each step", function()
	local env = fakeEnv()
	local sim = fixedSim(env)
	run(sim, env, 40)
	local st, w = sim.towns[11], env.T[11]
	local initSum = w.initials[1] + w.initials[2] + w.initials[3]
	near(persons(w), initSum * SG.growthFactor(st.exp, st.l0), initSum * 0.05, "persons near the curve's target")
	ok(st.factor > 1.5, "the fast town grew: " .. st.factor)
end)

test("sim: paused game (speed 0) -> no simulated time", function()
	local env = fakeEnv()
	local sim = fixedSim(env)
	env.speedV = 0
	run(sim, env, 30)
	eq(sim.step, 0)
	eq(#env.sent, 0)
	env.speedV = 4
	run(sim, env, 10.2)
	eq(sim.years, 1, "real seconds count while the game runs, at any speed")
end)

test("sim: stop holds everything; resume keeps years and experience; a fresh start derives exp from the size", function()
	local env = fakeEnv()
	local sim = fixedSim(env)
	run(sim, env, 20.2)
	eq(sim.years, 2)
	local exp = sim.towns[11].exp
	ok(sim:stop("button"))
	local n = #env.sent
	run(sim, env, 30)
	eq(#env.sent, n, "stopped: no commands")
	eq(sim.years, 2)
	sim:start(env.now, true)
	eq(sim.towns[11].exp, exp, "resume keeps the experience")
	run(sim, env, 10.2)
	eq(sim.years, 3)
	-- a new session: experience from the town's size
	local fresh = SG.new(env, { pace = 10, seed = 1 })
	fresh:start(env.now, false)
	local w = env.T[11]
	local f0 = persons(w) / (w.initials[1] + w.initials[2] + w.initials[3])
	near(SG.growthFactor(fresh.towns[11].exp, fresh.towns[11].l0), f0, 1e-3)
end)

test("sim: year limit returns 'limit'; scope near camera picks only close towns; inactive towns are skipped", function()
	local env = fakeEnv()
	env.T[12].active = false
	local sim = SG.new(env, { pace = 10, seed = 1, limit = 2 })
	sim:start(env.now, false)
	sim.towns[12].rate = 2
	local r = run(sim, env, 25)
	eq(r, "limit")
	for _, s in ipairs(env.sent) do ok(s.t ~= 12, "development inactive: never sent") end
	local near = SG.new(fakeEnv(), { pace = 10, seed = 1, near = { 0, 0 } })
	local picked = near:start(0, false)
	eq(picked, { 11, 12 }, "within 4 km of the camera")
end)

test("sim: one command per town in flight; commands spread over ticks", function()
	local env = fakeEnv({ holdCallbacks = true })
	local sim = fixedSim(env)
	run(sim, env, 10.2)
	local per = {}
	for _, s in ipairs(env.sent) do per[s.t] = (per[s.t] or 0) + 1 end
	eq(per[11], 1, "the next step waits for the callback")
	for _, cb in ipairs(env.held) do cb(true) end
	env.held = {}
	run(sim, env, 2.6)
	ok(#env.sent > 2)
end)

---------------------------------------------------------------------------
-- fast paces, Fast fill, waiting for the main mod

local function yearLines(env)
	local out = {}
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW year") then out[#out + 1] = l end end
	return out
end

test("fast paces: 1 / 2 / 5 s per year send one size command per town per year; the curve matches the 4-step pace", function()
	eq(SG.PACES, { 0, 1, 2, 5, 10, 30, 60 })
	eq(SG.cmdSteps(0), 1); eq(SG.cmdSteps(1), 1); eq(SG.cmdSteps(5), 1); eq(SG.cmdSteps(10), 4); eq(SG.cmdSteps(60), 4)
	local slowEnv = fakeEnv()
	local slow = fixedSim(slowEnv, { pace = 10, seed = 1 })
	run(slow, slowEnv, 100.2)
	eq(slow.years, 10)
	local env = fakeEnv()
	local sim = fixedSim(env, { pace = 1, seed = 1 })
	run(sim, env, 10.2)
	eq(sim.years, 10, "one simulated year per real second")
	local per = {}
	for _, s in ipairs(env.sent) do per[s.t] = (per[s.t] or 0) + 1 end
	ok(per[11] <= 10 and per[11] >= 9, "one command per year: " .. tostring(per[11]))
	-- experience still integrates in quarter years, so the sizes match the slow pace closely
	near(persons(env.T[11]), persons(slowEnv.T[11]), persons(slowEnv.T[11]) * 0.03, "fast town")
	near(persons(env.T[12]), persons(slowEnv.T[12]), persons(slowEnv.T[12]) * 0.03, "medium town")
	eq(#yearLines(env), 10)
	ok(yearLines(env)[1]:find(" s=", 1, true) and yearLines(env)[1]:find(" cap=", 1, true), yearLines(env)[1])
end)

test("Fast fill: every N years, only towns whose built capacity lags, also when their size doesn't change", function()
	local env = fakeEnv()
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = true, fillEvery = 2 })
	env.sim = sim
	env.T[12].actual = 1e9            -- 12's houses are ahead: never filled
	run(sim, env, 4.2)
	eq(sim.years, 4)
	local forcedYears = {}
	for _, s in ipairs(env.sent) do
		if s.forced then
			ok(s.t == 11, "only the lagging town is forced: " .. s.t)
			forcedYears[#forcedYears + 1] = s.year
		end
	end
	eq(forcedYears, { 2, 4 }, "forced in the 2nd and 4th simulated year (after that year's size step)")
	-- a lagging town whose size doesn't change still gets the forced command at its current size
	env.T[13].actual = 10
	sim.towns[13].rate = 0
	local e2 = fakeEnv()
	local s2 = fixedSim(e2, { pace = 1, seed = 1, fastFill = true, fillEvery = 1 })
	s2.towns[12].rate = 1e-9          -- grows too slowly to change its size
	e2.T[12].actual = 100
	run(s2, e2, 1.2)
	local f12
	for _, s in ipairs(e2.sent) do if s.t == 12 then f12 = s end end
	ok(f12 and f12.forced, "filled at its size")
	eq(f12.f, { 1, 1, 1 })
	for _, s in ipairs(e2.sent) do ok(s.t ~= 13, "rate 0: never filled") end
	ok(yearLines(e2)[1]:find("filled=2", 1, true), yearLines(e2)[1])
end)

test("Fast fill year: sizes and their callbacks first, then the fill and its callbacks; the clock stands still", function()
	local env = fakeEnv({ holdCallbacks = true })
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = true, fillEvery = 1 })
	run(sim, env, 3)
	eq(sim.years, 0, "size callbacks held: the fill year waits")
	ok(sim:status().head:find("sizes before the fill", 1, true), sim:status().head)
	for _, s in ipairs(env.sent) do ok(not s.forced, "no forced command before the sizes are in") end
	for _, cb in ipairs(env.held) do cb(true) end
	env.held = {}
	run(sim, env, 0.2)
	eq(sim.phase, "fill")
	ok(sim:status().head:find("filling 2 towns", 1, true), sim:status().head)
	local forced = 0
	for _, s in ipairs(env.sent) do if s.forced then forced = forced + 1 end end
	eq(forced, 2, "the lagging towns filled at their new size")
	run(sim, env, 5)
	eq(sim.phase, "fill", "fill callbacks held")
	local step = sim.step
	for _, cb in ipairs(env.held) do cb(true) end
	env.held = {}
	run(sim, env, 0.1)
	eq(sim.phase, "run")
	eq(sim.step, step, "no simulated time passed while filling: no step at once")
	local y = yearLines(env)[1]
	ok(y and y:find("filled=2", 1, true) and y:find("res=sent:2,none:1", 1, true), y)
	-- without fast fill a year ends when its commands are sent
	local e2 = fakeEnv({ holdCallbacks = true })
	local s2 = fixedSim(e2, { pace = 1, seed = 1 })
	run(s2, e2, 1.2)
	eq(s2.years, 1)
end)

test("wait for the main mod: after the sizes (the towns that grew most) before the fill, then briefly after it", function()
	local env = fakeEnv({ main = true })
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, waitMain = true })
	run(sim, env, 1.2)
	eq(sim.phase, "wait")
	eq(sim.waitKind, "sizes")
	eq(sim.years, 1, "the year is counted ...")
	eq(#yearLines(env), 0, "... but summed up after the waits")
	for _, s in ipairs(env.sent) do ok(not s.forced, "no fill before the main mod's turn") end
	ok(sim:status().head:find("waiting for the main mod (0/2 towns checked", 1, true), sim:status().head)
	local n = #env.sent
	run(sim, env, 3)
	eq(#env.sent, n, "nothing sent while waiting")
	env.main.seen, env.main.busy = 2, true
	run(sim, env, 0.2)
	eq(sim.phase, "wait", "a main job still running")
	env.main.busy = false
	run(sim, env, 0.1)
	-- the fill went out, then the short wait for the filled towns
	eq(sim.phase, "wait")
	eq(sim.waitKind, "fill")
	local forced = 0
	for _, s in ipairs(env.sent) do if s.forced then forced = forced + 1 end end
	eq(forced, 2)
	ok(sim:status().head:find("after the fill", 1, true), sim:status().head)
	run(sim, env, SG.WAIT_FILL_S + 0.2)
	eq(sim.phase, "run")
	local y = yearLines(env)[1]
	ok(y and y:find("main=2/2", 1, true) and y:find("timeout=false", 1, true) and y:find("waitS=3.", 1, true)
		and y:find("waitFillS=4.", 1, true), y)
	-- the cap
	run(sim, env, 1.2)
	eq(sim.phase, "wait")
	run(sim, env, SG.WAIT_MAX_S + SG.WAIT_FILL_S + 0.5)
	ok(yearLines(env)[2]:find("timeout=true", 1, true), yearLines(env)[2])
	-- the wait list: at most WAIT_TOWNS, the biggest growth first
	local towns = {}
	for t = 1, 9 do towns[100 + t] = { initials = { 100, 100, 100 }, sizeFactors = { 1, 1, 1 }, x = 0, y = 0, b = 10 } end
	local e5 = fakeEnv({ main = true, towns = towns })
	local s5 = SG.new(e5, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, waitMain = true })
	s5:start(0, false)
	for t, st in pairs(s5.towns) do st.rate = (t - 100) * 0.3 end
	local marked
	e5.mainMark = function(list) marked = list return { towns = list } end
	run(s5, e5, 1.2)
	eq(#marked, SG.WAIT_TOWNS)
	eq(marked[1], 109, "fastest first")
	-- no main driver (mainMark nil) or waitMain off: no wait
	local e2 = fakeEnv()
	local s2 = fixedSim(e2, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, waitMain = true })
	run(s2, e2, 2.2)
	eq(s2.years, 2)
	local e3 = fakeEnv({ main = true })
	local s3 = fixedSim(e3, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, waitMain = false })
	run(s3, e3, 2.2)
	eq(s3.years, 2)
	eq(e3.main.marks, 0)
	-- not in a year without a fill
	local e4 = fakeEnv({ main = true })
	local s4 = fixedSim(e4, { pace = 1, seed = 1, fastFill = true, fillEvery = 2, waitMain = true })
	run(s4, e4, 1.2)
	eq(s4.phase, "run")
	eq(e4.main.marks, 0)
end)

test("a growing town that gets no step is logged once as a stall (why, active)", function()
	local env = fakeEnv()
	local sim = fixedSim(env, { pace = 1, seed = 1 })
	run(sim, env, 1.2)
	env.T[11].active = false
	run(sim, env, 3.2)
	local stalls = {}
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW stall") then stalls[#stalls + 1] = l end end
	eq(#stalls, 1)
	ok(stalls[1]:find("town=11", 1, true) and stalls[1]:find("why=off", 1, true) and stalls[1]:find("active=false", 1, true), stalls[1])
	ok(yearLines(env)[3]:find("off:1", 1, true), yearLines(env)[3])
end)

test("stop while waiting resets the wait; a resume starts a fresh year", function()
	local env = fakeEnv({ main = true })
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, waitMain = true })
	run(sim, env, 1.2)
	eq(sim.phase, "wait")
	sim:stop("button")
	eq(sim.phase, "run")
	sim:start(env.now, true)
	env.main.seen = 99
	run(sim, env, 1.2)
	eq(sim.years, 2)
end)

---------------------------------------------------------------------------
-- the engine command and the runner

test("X.updateSize sends makeTownUpdateSizeCmd(town, factors, false): no forced building update", function()
	local got
	set_global("api", {
		cmd = {
			makeTownUpdateSizeCmd = function(t, f, all) got = { t = t, f = f, all = all } return "cmd" end,
			sendCommand = function(c, cb) cb({}, true) end,
		},
	})
	reset_modules()
	local X = ug_require "/organic_towns_dev/otd_engine.lua"
	local okCb
	X.updateSize(42, { 1.5, 1.25, 1.1 }, function(s) okCb = s end)
	eq(got.t, 42)
	eq(got.all, false)
	eq(got.f, { 1.5, 1.25, 1.1 })
	eq(okCb, true)
	X.updateSize(42, { 2, 2, 2 }, function() end, true)
	eq(got.all, true, "Fast fill: updateAllBuildings")
end)

test("runner: simStart / simStop commands log SIMGROW lines, keep the main driver free, and ask for the tour", function()
	local R = ug_require "/organic_towns_dev/otd_runner.lua"
	local S = ug_require "/organic_towns_dev/otd_shared.lua"
	local env = fakeEnv()
	local lines = {}
	local D = {
		new = function() return { phase = "manual", towns = {}, counts = {}, loadConfig = function() end } end,
		line = function(what, fields, prefix)
			local parts = { prefix, what }
			for _, f in ipairs(fields or {}) do parts[#parts + 1] = f[1] .. "=" .. tostring(f[2]) end
			return table.concat(parts, " ")
		end,
	}
	local E = { towns = env.towns, name = env.name, boxCentre = env.centre, log = function() end }
	local X = { townGrowth = env.town, updateSize = env.updateSize, buildingCounts = env.buildings,
		gameSpeed = env.speed, minDistrictWeight = env.minWeight, log = function(l) lines[#lines + 1] = l end,
		setGameSpeed = function(v, cb) cb(true) end }
	local H = {}
	local r = R.new({ D = D, E = E, X = X, H = H, SG = SG, S = S })
	r.allTowns = function(self) self.allTownList = {} end   -- (measured by the main driver in game)
	local st = r:command({ action = "simStart", pace = 5, seed = 2, limit = 1, scope = "all", bias = true, tourWhenDone = true,
		fastFill = false }, 0, S)
	ok(st.sim and st.sim.running)
	local start
	for _, l in ipairs(lines) do if l:find("SIMGROW start", 1, true) then start = l end end
	ok(start and start:find("seed=2", 1, true) and start:find("pace=10", 1, true) and start:find("towns=3", 1, true), start)
	local now = 0
	for _ = 1, 400 do
		now = now + 50000
		r:tick(now)
		eq(H.devBusy, false, "the simulation never holds the main driver")
	end
	eq(r.sim.years, 2)
	st = r:command({ action = "simStop" }, now, S)
	eq(st.sim.running, false)
	eq(st.sim.autoTour, 1, "tour asked for")
	local final, stop = 0, nil
	for _, l in ipairs(lines) do
		if l:find("SIMGROW final", 1, true) then final = final + 1 end
		if l:find("SIMGROW stop", 1, true) then stop = l end
	end
	eq(final, 3)
	ok(stop and stop:find("reason=button", 1, true), stop)
	-- Start again with the same seed resumes
	st = r:command({ action = "simStart", pace = 5, seed = 2, scope = "all" }, now, S)
	eq(st.sim.years, 2)
	r:command({ action = "simStop" }, now, S)
	-- (2026-10-14 late) a town creation of the main driver in flight: the measure and tour wait for it
	local main = { phase = "run", towns = {}, counts = { checks = 0, builds = 0, fails = 0, refused = 0 },
		createInFlight = { town = 7 } }
	H.main = main
	st = r:command({ action = "simStart", pace = 5, seed = 2, scope = "all", tourWhenDone = true }, now, S)
	local tours = r.sim.autoTour
	st = r:command({ action = "simStop" }, now, S)
	eq(r.sim.autoTour, tours, "waits while a creation is in flight")
	ok(r.sim.tourPending ~= nil)
	r:tick(now + 5e6)
	eq(r.sim.autoTour, tours, "still in flight")
	main.createInFlight = nil
	r:tick(now + 6e6)
	eq(r.sim.autoTour, tours, "a short wait after it came back")
	r:tick(now + 6e6 + (R.TOUR_AFTER_CREATE_S + 1) * 1e6)
	eq(r.sim.autoTour, tours + 1, "then measured and toured")
	local waitDone = false
	for _, l in ipairs(lines) do if l:find("SIMGROW tour wait=done why=created", 1, true) then waitDone = true end end
	ok(waitDone, "SIMGROW tour wait=done line")
	H.main = nil
end)

--- A runner with a fake main driver (H.main) and game speed.
local function simRunner(o)
	o = o or {}
	local R = ug_require "/organic_towns_dev/otd_runner.lua"
	local S = ug_require "/organic_towns_dev/otd_shared.lua"
	local env = fakeEnv()
	local lines = {}
	local D = {
		CHECK_S = 3,
		new = function() return { phase = "manual", towns = {}, counts = {}, loadConfig = function() end } end,
		line = function(what, fields, prefix)
			local parts = { prefix, what }
			for _, f in ipairs(fields or {}) do parts[#parts + 1] = f[1] .. "=" .. tostring(f[2]) end
			return table.concat(parts, " ")
		end,
	}
	local A = { COOLDOWN_S = { built = 90, room = 30, empty = 240 } }
	local game = { speed = o.speed or 4, sets = {} }
	local E = { towns = env.towns, name = env.name, boxCentre = env.centre, log = function() end,
		townCaps = function(t) local c = env.caps(t) return { actual = c.actual, target = c.target, sizeFactors = {} } end }
	local X = { townGrowth = env.town, updateSize = env.updateSize, buildingCounts = env.buildings,
		gameSpeed = function() return game.speed end, minDistrictWeight = env.minWeight,
		log = function(l) lines[#lines + 1] = l end,
		setGameSpeed = function(v, cb) game.sets[#game.sets + 1] = v; game.speed = v; cb(true) end }
	local main = { phase = "run", counts = { checks = 0, builds = 0, fails = 0, refused = 0 }, sched = { towns = {} }, job = nil, inflight = false }
	local H = { main = main }
	local r = R.new({ D = D, E = E, X = X, H = H, SG = SG, S = S, A = A })
	r.allTowns = function(self) self.allTownList = {} end
	return r, { env = env, lines = lines, D = D, A = A, game = game, main = main, H = H, S = S }
end

local function findLine(lines, pat)
	for _, l in ipairs(lines) do if l:find(pat, 1, true) then return l end end
	return nil
end

test("runner: a run raises the main driver's check pace and the game speed; Stop restores both", function()
	local r, c = simRunner()
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all" }, 0, c.S)
	eq(c.D.CHECK_S, SG.MAIN_CHECK_S)
	near(c.A.COOLDOWN_S.room, 30 * SG.MAIN_COOLDOWN_MULT, 1e-9)
	near(c.A.COOLDOWN_S.built, 90 * SG.MAIN_COOLDOWN_MULT, 1e-9)
	eq(c.game.speed, SG.SIM_SPEED)
	local start = findLine(c.lines, "SIMGROW start")
	ok(start:find("fastFill=true", 1, true) and start:find("fillEvery=2", 1, true) and start:find("waitMain=true", 1, true)
		and start:find("speed=4->8", 1, true) and start:find("cmdSteps=1", 1, true), start)
	r:command({ action = "simStop" }, 1e6, c.S)
	eq(c.D.CHECK_S, 3)
	eq(c.A.COOLDOWN_S.room, 30)
	eq(c.A.COOLDOWN_S.built, 90)
	eq(c.game.speed, 4, "previous speed back")
	ok(findLine(c.lines, "SIMGROW stop"):find("speed=8->4", 1, true))
	-- a speed the player picked meanwhile stays; a paused game is not unpaused at Start
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all" }, 2e6, c.S)
	c.game.speed = 2
	r:command({ action = "simStop" }, 3e6, c.S)
	eq(c.game.speed, 2)
	c.game.speed = 0
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all", waitMain = false, buildRound = false }, 4e6, c.S)
	eq(c.game.speed, 0)
	eq(c.D.CHECK_S, 3, "waitMain off: the main driver keeps its pace")
	r:command({ action = "simStop" }, 5e6, c.S)
	-- speedUp off
	c.game.speed = 4
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all", speedUp = false }, 6e6, c.S)
	eq(c.game.speed, 4)
	r:command({ action = "simStop" }, 7e6, c.S)
	eq(c.D.CHECK_S, 3)
end)

test("runner: an error in the simulation restores the main pace and the game speed", function()
	local r, c = simRunner()
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all" }, 0, c.S)
	r.sim.tick = function() error("boom") end
	r:tick(50000)
	eq(r.sim.running, false)
	eq(c.D.CHECK_S, 3)
	eq(c.game.speed, 4)
end)

test("runner: the wait follows the main driver's scheduler (checked, long cooldown, job running, paused)", function()
	local r, c = simRunner()
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all" }, 0, c.S)
	local sched = c.main.sched.towns
	sched[11] = { nextUs = 5e6 }
	sched[12] = { nextUs = 900e6 }   -- on a cooldown past the wait cap: doesn't hold the wait
	local mark = r:simMainMark({ 11, 12, 13 }, 10e6)
	local w = r:simMainSeen(mark, 10e6)
	eq(w.seen, 1); eq(w.total, 3); eq(w.busy, false)
	sched[11].nextUs = 12e6          -- 11 checked (cooldown set again)
	sched[13] = { nextUs = 11e6 }    -- 13 checked for the first time
	c.main.counts.checks = 2
	c.main.job = { town = 13 }
	w = r:simMainSeen(mark, 11e6)
	eq(w.seen, 3); eq(w.busy, true); eq(w.checks, 2)
	c.H.paused = true
	eq(r:simMainSeen(mark, 11e6), nil, "paused main driver: stop waiting")
	eq(r:simMainMark({ 11 }, 11e6), nil)
	c.H.paused = false
	c.H.main = nil
	eq(r:simMainMark({ 11 }, 11e6), nil, "no main driver visible")
	r:command({ action = "simStop" }, 12e6, c.S)
end)

test("runner: a fast run with fill and wait reaches its year limit; options change while running", function()
	local r, c = simRunner()
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all", fillEvery = 1, buildRound = false }, 0, c.S)
	r.sim.limit = 2
	for t, st in pairs(r.sim.towns) do st.rate = t == 13 and 0 or 2 end
	c.env.T[11].actual, c.env.T[12].actual = 10, 10
	local now = 0
	local function ticks(n, fn)
		for _ = 1, n do
			now = now + 50000
			if fn then fn() end
			r:tick(now)
		end
	end
	ticks(25)
	eq(r.sim.phase, "wait", "waiting for the main driver after the first fill")
	-- the main driver checks the towns
	ticks(1, function()
		for _, t in ipairs({ 11, 12 }) do c.main.sched.towns[t] = { nextUs = now + 1e6 } end
	end)
	ok(r.sim.phase == "fill" or (r.sim.phase == "wait" and r.sim.waitKind == "fill"), r.sim.phase)
	ticks(3, function()
		for _, t in ipairs({ 11, 12 }) do c.main.sched.towns[t] = { nextUs = now + 2e6 } end
	end)
	eq(r.sim.phase, "run", "the filled towns checked again: the year ends")
	eq(r.sim.years, 1)
	r:command({ action = "simOpt", fillEvery = 3, fastFill = true, waitMain = false }, now, c.S)
	eq(r.sim.fillEvery, 4)
	eq(r.sim.waitMain, false)
	eq(c.D.CHECK_S, 3, "wait off: main pace restored")
	ticks(25)
	eq(r.sim.running, false, "year limit")
	ok(findLine(c.lines, "SIMGROW stop"):find("reason=limit", 1, true))
	local forced = 0
	for _, s in ipairs(c.env.sent) do if s.forced then forced = forced + 1 end end
	eq(forced, 2, "year 1: both lagging towns filled; year 2: fill every 4 -> none")
end)

test("every town grows: no town without growth, rates within the even range, same seed same rate", function()
	for t = 1, 400 do
		local r, c = SG.rate(2000 + t * 13, 2, 300, true, true)
		assert(r >= SG.EVEN_MIN and r <= SG.EVEN_MAX, "rate in range: " .. tostring(r))
		assert(c == "medium" or c == "fast", "class " .. tostring(c))
		assert(SG.rate(2000 + t * 13, 2, 300, true, true) == r, "deterministic")
	end
end)

---------------------------------------------------------------------------
-- build round (2026-10-13: the main mod's turn on every grown town at each chunk's end)

--- A fake round engine for the sim: records the towns, finishes after `ticks` ticks with `builds` builds.
local function fakeRound(env, o)
	o = o or {}
	env.rounds = {}
	function env.roundStart(towns, now)
		if o.refuse then return nil, o.refuse end
		local h = { towns = towns, ticks = 0, startUs = now }
		env.rounds[#env.rounds + 1] = h
		env.roundSentBefore = #env.sent
		return h
	end
	function env.roundTick(h, now)
		h.ticks = h.ticks + 1
		if o.never or h.ticks < (o.ticks or 3) then return nil end
		return { towns = #h.towns, checks = #h.towns * 2, builds = #h.towns, edges = 10 * #h.towns, served = #h.towns,
			capped = 0, demandLeft = 4, s = (now - h.startUs) / 1e6, peak = 2, per = "x" }
	end
end

test("build round: sizes and callbacks first, then every grown town's round (most growth first), then the fill", function()
	local env = fakeEnv({ holdCallbacks = true })
	fakeRound(env)
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = true, fillEvery = 2, buildRound = true, waitMain = true })
	run(sim, env, 1.2)
	eq(sim.phase, "run", "year 1: no round (every 2 years)")
	for _, cb in ipairs(env.held or {}) do cb(true) end
	env.held = {}
	run(sim, env, 1.0)
	eq(#env.rounds, 0, "the round waits for the year's size callbacks")
	for _, cb in ipairs(env.held) do cb(true) end
	env.held = {}
	run(sim, env, 0.1)
	eq(#env.rounds, 1)
	eq(sim.phase, "round", table.concat(env.logs, "\n"))
	eq(env.rounds[1].towns, { 11, 12 }, "the grown towns (11 fastest first); 13 has rate 0")
	for _, s in ipairs(env.sent) do ok(not s.forced, "no fill before the round") end
	ok(sim:status().head:find("build round", 1, true), sim:status().head)
	local years = sim.years
	run(sim, env, 1.0)
	eq(sim.years, years, "the clock stands still during the round and the fill")
	eq(sim.phase, "fill")
	local forced = 0
	for _, s in ipairs(env.sent) do if s.forced then forced = forced + 1 end end
	eq(forced, 2, "the fill after the round")
	for _, cb in ipairs(env.held) do cb(true) end
	env.held = {}
	run(sim, env, 0.1)
	eq(sim.phase, "run", "no wait after the fill in round mode")
	local round
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW round") then round = l end end
	ok(round and round:find("year=2", 1, true) and round:find("towns=2", 1, true) and round:find("builds=2", 1, true)
		and round:find("demandLeft=4", 1, true), round)
	local y = yearLines(env)[2]
	ok(y and y:find("round=2/2", 1, true) and y:find("filled=2", 1, true), y)
	eq(sim.rounds, 1); eq(sim.roundBuilds, 2)
	-- the next round: only the towns that grew since this one
	sim.towns[12].rate = 0
	for _ = 1, 50 do
		run(sim, env, 0.05)
		for _, cb in ipairs(env.held) do cb(true) end
		env.held = {}
	end
	ok(#env.rounds == 2 and #env.rounds[2].towns == 1 and env.rounds[2].towns[1] == 11, "only town 11 grew")
end)

test("build round without Fast fill: round every N years, no fill; no round possible -> logged, the year goes on", function()
	local env = fakeEnv()
	fakeRound(env)
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = false, fillEvery = 1, buildRound = true })
	run(sim, env, 1.2)
	eq(#env.rounds, 1)
	run(sim, env, 0.3)
	eq(sim.phase, "run")
	for _, s in ipairs(env.sent) do ok(not s.forced, "no fill") end
	local e2 = fakeEnv()
	fakeRound(e2, { refuse = "noMain" })
	local s2 = fixedSim(e2, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, buildRound = true })
	run(s2, e2, 1.3)
	ok(s2.phase == "run" or s2.phase == "fill", s2.phase)
	local l
	for _, x in ipairs(e2.logs) do if x:find("^SIMGROW round") then l = x end end
	ok(l and l:find("why=noMain", 1, true), l)
	-- a round that never reports: the guard
	local e3 = fakeEnv()
	fakeRound(e3, { never = true })
	local s3 = fixedSim(e3, { pace = 1, seed = 1, fillEvery = 1, buildRound = true })
	run(s3, e3, 1.2)
	eq(s3.phase, "round")
	run(s3, e3, SG.ROUND_GUARD_S + 0.5)
	eq(s3.rounds, 1, "the round given up after the guard")
	run(s3, e3, 1.0)
	eq(s3.years, 2, "went on after the guard")
	local g
	for _, x in ipairs(e3.logs) do if x:find("why=guard", 1, true) then g = x end end
	ok(g, "guard logged")
	-- stop during the round resets it
	local e4 = fakeEnv()
	fakeRound(e4, { never = true })
	local s4 = fixedSim(e4, { pace = 1, seed = 1, fillEvery = 1, buildRound = true })
	run(s4, e4, 1.2)
	s4:stop("button")
	eq(s4.phase, "run"); eq(s4.roundH, nil)
end)

test("stall: a town switched off after Start is switched back on (at most REACTIVATE_MAX) and resumes", function()
	local env = fakeEnv()
	local calls = {}
	env.reactivate = function(t, cb)
		calls[#calls + 1] = t
		if env.reactWorks then env.T[t].active = true end
		cb(true)
	end
	env.T[13].active = false   -- off at Start: never switched on by the sim
	local sim = fixedSim(env, { pace = 1, seed = 1 })
	sim.towns[13].rate = 1
	run(sim, env, 1.2)
	env.T[11].active = false   -- the main mod's dose fill switched it off
	run(sim, env, 6.2)
	local n11 = 0
	for _, t in ipairs(calls) do
		ok(t ~= 13, "a town off at Start stays off")
		if t == 11 then n11 = n11 + 1 end
	end
	eq(n11, SG.REACTIVATE_MAX, "at most REACTIVATE_MAX tries while the game keeps it off")
	-- the game reports it active again (the main mod's FILL reactivate): the next step resumes it
	env.T[11].active = true
	local before = #env.sent
	run(sim, env, 1.1)
	local resumed, sent11 = nil, false
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW resume") then resumed = l end end
	for i = before + 1, #env.sent do if env.sent[i].t == 11 then sent11 = true end end
	ok(resumed and resumed:find("town=11", 1, true) and resumed:find("reactivations=" .. SG.REACTIVATE_MAX, 1, true), resumed)
	ok(sent11, "steps again")
	-- our reactivation works: resumed after STALL_STEPS off steps
	local e2 = fakeEnv()
	calls = {}
	e2.reactivate = function(t, cb)
		calls[#calls + 1] = t
		e2.T[t].active = true
		cb(true)
	end
	local s2 = fixedSim(e2, { pace = 1, seed = 1 })
	run(s2, e2, 1.2)
	e2.T[12].active = false
	run(s2, e2, 4.2)
	eq(#calls, 1)
	local r2
	for _, l in ipairs(e2.logs) do if l:find("^SIMGROW resume") then r2 = l end end
	ok(r2 and r2:find("town=12", 1, true) and r2:find("offSteps=" .. SG.STALL_STEPS, 1, true), r2)
	local react
	for _, l in ipairs(e2.logs) do if l:find("^SIMGROW reactivate") then react = l end end
	ok(react and react:find("ok=true", 1, true), react)
end)

--- A fake main mod for the runner's round: driver instances whose jobs check a town's demand (world.demand, edges)
--- and build up to world.inc edges per job when it is >= 6 (why=demand), else why=ahead (outcome room). Each job takes
--- world.steps advances. Shared state (towns, sched, counts) comes from the pool driver's fields, as in the main mod.
local function fakeMain(world)
	local FD = {}
	FD.__index = FD
	function FD:startJob(t, now, o)
		if self.job ~= nil then return nil end
		self.job = { town = t, stage = "assess", n = 0, onDone = o.onDone, force = o.force == true }
		world.active = world.active + 1
		world.peak = math.max(world.peak, world.active)
		world.jobs[#world.jobs + 1] = { t = t, force = o.force == true, prefix = self.prefix, E = self.E }
		return self.job
	end
	function FD:measure(t)
		local d = world.demand[t] or 0
		return { why = d >= 6 and "demand" or "ahead", dem = { edges = d } }
	end
	function FD:advance(now, _saved)
		local job = self.job
		if job == nil then return false end
		job.n = job.n + 1
		if job.n < world.steps then return true end
		local m = self:measure(job.town)
		local outcome = "room"
		local s = self.towns[job.town] or { builds = 0, ledger = { served = 0 } }
		self.towns[job.town] = s
		if m.why == "demand" then
			local n = math.min(world.inc, world.demand[job.town])
			world.demand[job.town] = world.demand[job.town] - n
			job.spec = { edges = {} }
			for i = 1, n do job.spec.edges[i] = i end
			s.builds = s.builds + 1
			s.ledger.served = s.ledger.served + n
			self.counts.builds = self.counts.builds + 1
			outcome = "built"
		end
		self.counts.checks = self.counts.checks + 1
		self.sched.towns[job.town] = { nextUs = now + 1e6 }
		self.job = nil
		world.active = world.active - 1
		job.onDone(job, outcome)
		return false
	end
	return FD
end

local function roundRunner(world)
	local r, c = simRunner()
	local FD = fakeMain(world)
	c.D.new = function(E, prefix)
		return setmetatable({ E = E, prefix = prefix, phase = "manual", towns = {}, counts = {}, sched = { towns = {} },
			loadConfig = function() end }, FD)
	end
	c.main.towns, c.main.opts, c.main.prefix, c.main.E = {}, { actOn = "all" }, "[SQOT]", { tag = "mainE" }
	c.main.verbose = false
	c.main.saved = { v = 1, known = {}, frames = {} }
	return r, c
end

test("runner round: every grown town is checked until served (or capped), the main driver held, per-town results", function()
	-- (2026-10-14: ROUND_BUILDS 6 -> 3; this test's town 11 needs 3 builds and a 4th check: run at the old cap)
	local rb0 = SG.ROUND_BUILDS
	SG.ROUND_BUILDS = 6
	local okT, errT = pcall(function()
	local world = { demand = { [11] = 26, [12] = 3, [13] = 500 }, inc = 10, steps = 3, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	c.main.job = { town = 99 }   -- the main driver is busy: the round waits for its job
	local rd = r:simRoundStart({ 11, 12, 13 }, 0)
	ok(rd ~= nil)
	eq(c.H.devBusy, true, "held from the start (no new main check)")
	local now = 0
	eq(r:simRoundTick(rd, now), nil)
	eq(#world.jobs, 0, "no job while the main driver's job runs")
	c.main.job = nil
	local res
	for _ = 1, 400 do
		now = now + 50000
		res = r:simRoundTick(rd, now)
		if res == nil then eq(c.H.devBusy, true, "held during the round") end
		if res then break end
	end
	ok(res, "the round ended")
	eq(c.H.devBusy, false, "released after the round")
	-- 11: 10 + 10 + 6 built, then a check that says ahead (served); 12: one check, served; 13: capped
	eq(world.demand[11], 0)
	eq(c.main.towns[11].builds, 3, "the main driver's own per-town state")
	eq(c.main.towns[11].ledger.served, 26, "the demand ledger served through the shared state")
	eq(c.main.towns[12].builds, 0, "12 had too little demand: checked, no build")
	eq(c.main.towns[13].builds, SG.ROUND_BUILDS)
	eq(c.main.counts.builds, 3 + SG.ROUND_BUILDS)
	eq(c.main.counts.checks, 4 + 1 + SG.ROUND_BUILDS)
	ok(c.main.sched.towns[11] and c.main.sched.towns[13], "cooldowns in the main scheduler")
	eq(res.towns, 3); eq(res.builds, 3 + SG.ROUND_BUILDS); eq(res.edges, 26 + 10 * SG.ROUND_BUILDS)
	eq(res.served, 2); eq(res.capped, 1)
	eq(res.checks, 4 + 1 + SG.ROUND_BUILDS)
	ok(res.per:find("Town_11:3/4:ahead:0", 1, true) and res.per:find("Town_12:0/1:ahead:3", 1, true)
		and res.per:find("Town_13:" .. SG.ROUND_BUILDS .. "/" .. SG.ROUND_BUILDS .. ":demand", 1, true), res.per)
	near(res.demandLeft, 3 + 500 - 10 * SG.ROUND_BUILDS, 1e-9)
	for _, j in ipairs(world.jobs) do
		eq(j.force, false, "the main mod's normal check (its trigger decides)")
		eq(j.prefix, "[SQOT]"); eq(j.E.tag, "mainE")
	end
	eq(c.H.simNoFills, false, "the round's fill skip is off again")
	end)
	SG.ROUND_BUILDS = rb0
	assert(okT, errT)
end)

test("round cap (2026-10-14): at most ROUND_BUILDS = 3 builds per town and round; the fill skip on during the round", function()
	eq(SG.ROUND_BUILDS, 3)
	local world = { demand = { [13] = 500 }, inc = 10, steps = 3, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	local rd = r:simRoundStart({ 13 }, 0)
	eq(c.H.simNoFills, true, "no dose / upward fill in the round")
	local now, res = 0, nil
	for _ = 1, 400 do
		now = now + 50000
		res = r:simRoundTick(rd, now)
		if res then break end
	end
	ok(res)
	eq(c.main.towns[13].builds, 3)
	eq(res.capped, 1)
	eq(c.H.simNoFills, false)
end)

test("runner round: at most ROUND_INFLIGHT jobs at once, one per town; the time cap lets running jobs finish", function()
	local saved = SG.ROUND_INFLIGHT
	SG.ROUND_INFLIGHT = 2
	local world = { demand = {}, inc = 10, steps = 4, active = 0, peak = 0, jobs = {} }
	local towns = {}
	for t = 1, 6 do towns[t] = 100 + t; world.demand[100 + t] = 20 end
	local r, c = roundRunner(world)
	r.E.boxCentre = function(t) return t * 5000, 0 end   -- far apart
	local perTown = {}
	local FD = getmetatable(c.D.new())
	local start = FD.startJob
	FD.startJob = function(self, t, now, o)
		perTown[t] = (perTown[t] or 0) + 1
		ok(perTown[t] == 1, "one job per town at a time")
		local j = start(self, t, now, o)
		local done = o.onDone
		j.onDone = function(job, outcome) perTown[t] = perTown[t] - 1; done(job, outcome) end
		return j
	end
	local rd = r:simRoundStart(towns, 0)
	local now, res = 0, nil
	for _ = 1, 400 do
		now = now + 50000
		res = r:simRoundTick(rd, now)
		if res then break end
	end
	SG.ROUND_INFLIGHT = saved
	eq(world.peak, 2, "the concurrency cap")
	eq(res.builds, 12, "2 builds per town (20 edges)")
	eq(res.served, 6)
	eq(res.peak, 2)
	-- neighbour towns whose plan extents may meet (rA + rB + 2 x ROUND_REACH_M; unknown r: ROUND_R_DEFAULT) never
	-- build at the same time
	SG.ROUND_INFLIGHT = 3
	local w3 = { demand = { [1] = 20, [2] = 20, [3] = 20 }, inc = 10, steps = 3, active = 0, peak = 0, jobs = {} }
	local r3, c3 = roundRunner(w3)
	local reach = 2 * SG.ROUND_R_DEFAULT + 2 * SG.ROUND_REACH_M
	local pos = { [1] = 0, [2] = reach * 0.9, [3] = reach * 3 }
	r3.E.boxCentre = function(t) return pos[t], 0 end
	local running = {}
	local FD3 = getmetatable(c3.D.new())
	local st3 = FD3.startJob
	FD3.startJob = function(self, t, now, o)
		running[t] = true
		ok(not (running[1] and running[2]), "1 and 2 are neighbours")
		local j = st3(self, t, now, o)
		local done = o.onDone
		j.onDone = function(job, outcome) running[t] = nil; done(job, outcome) end
		return j
	end
	local rd3 = r3:simRoundStart({ 1, 2, 3 }, 0)
	local res3
	for k = 1, 400 do
		res3 = r3:simRoundTick(rd3, k * 50000)
		if res3 then break end
	end
	SG.ROUND_INFLIGHT = saved
	eq(res3.builds, 6)
	eq(w3.peak, 2, "3 beside 1 or 2, never 1 beside 2")
	-- the time cap
	SG.ROUND_INFLIGHT = saved
	local w2 = { demand = { [11] = 1000 }, inc = 5, steps = 2, active = 0, peak = 0, jobs = {} }
	local r2, c2 = roundRunner(w2)
	local rd2 = r2:simRoundStart({ 11 }, 0)
	local n, res2 = 0, nil
	local t2 = 0
	for _ = 1, 4000 do
		t2 = t2 + 50000
		-- each job takes long: the cap comes after the first build
		if w2.active > 0 then t2 = t2 + SG.ROUND_MAX_S * 1e6 end
		res2 = r2:simRoundTick(rd2, t2)
		n = n + 1
		if res2 then break end
	end
	eq(res2.why, "time")
	eq(res2.builds, 1, "the running job finished, no new one")
	eq(w2.active, 0)
	eq(c2.H.devBusy, false)
end)

test("runner round: a full run with Quick-like options builds before each fill; Stop drains a running round", function()
	local world = { demand = { [11] = 12, [12] = 12, [13] = 12 }, inc = 6, steps = 2, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all", fillEvery = 1 }, 0, c.S)
	ok(findLine(c.lines, "SIMGROW start"):find("buildRound=true", 1, true))
	for t, st in pairs(r.sim.towns) do st.rate = t == 13 and 0 or 2 end
	c.env.T[11].actual, c.env.T[12].actual = 10, 10
	local now = 0
	local sawRound = false
	for _ = 1, 200 do
		now = now + 50000
		r:tick(now)
		if r.sim.phase == "round" then sawRound = true end
		if sawRound and r.sim.phase == "run" then break end
	end
	ok(sawRound, "a round ran")
	local round = findLine(c.lines, "SIMGROW round")
	ok(round and round:find("towns=2", 1, true) and round:find("builds=4", 1, true), round)
	local forced = 0
	for _, s in ipairs(c.env.sent) do if s.forced then forced = forced + 1 end end
	eq(forced, 2, "the fill after the round")
	eq(world.jobs[1].t, 12, "most growth first (12 is the bigger town)")
	-- Stop in the middle of a round: running jobs finish, then the main driver is free again
	world.demand[11], world.demand[12] = 100, 100
	world.steps = 20
	for _ = 1, 40 do
		now = now + 50000
		r:tick(now)
		if r.simRound and world.active > 0 then break end
	end
	ok(r.simRound and world.active > 0, "a round with jobs running")
	r:command({ action = "simStop" }, now, c.S)
	ok(findLine(c.lines, "SIMGROW stop"):find("rounds=", 1, true))
	for _ = 1, 60 do
		now = now + 50000
		r:tick(now)
	end
	eq(r.simRound, nil)
	eq(world.active, 0)
	eq(c.H.devBusy, false)
end)

test("R7 realistic split: the era's mostly residential weights, not the town's starting share", function()
	local m1 = SG.mixFor(1905)
	ok(m1[1] > 0.5 and m1[3] > m1[2], "1900s: residential first, industry second")
	local m2 = SG.mixFor(1990)
	ok(m2[1] > m1[1] and m2[3] < m1[3], "later: less industry")
	-- Alsager-like: 34 % industrial at the start
	local initials = { 100, 30, 66 }
	-- (a map's sums: the town is a small part of it, so the map clamp doesn't bind)
	local map = { 20000, 8000, 9000 }
	local f, d = SG.distribute({ initials = initials, sizeFactors = { 1, 1, 1 }, newSum = 400, minWeight = 0.05,
		weights = SG.mixFor(1930), mapSum = map })
	ok(f ~= nil)
	local _, old = SG.distribute({ initials = initials, sizeFactors = { 1, 1, 1 }, newSum = 400, minWeight = 0.05, mapSum = map })
	print(string.format("      Alsager-like growth 196 -> 400: era mix %.0f / %.0f / %.0f, town mix (old) %.0f / %.0f / %.0f",
		d.added[1], d.added[2], d.added[3], old.added[1], old.added[2], old.added[3]))
	-- (the game's own rebalance caps a district over 40-50 % of the town (town_growth.script.tl MAX_TOWN_*), so the
	-- residential share can't run away; the era mix still grows less industry than the starting share)
	ok(d.added[1] > d.added[3] and d.added[1] > d.added[2], "residential first")
	ok(old.added[3] > d.added[3] + 5, "the old rule (town mix) grew more industry")
	local saved = SG.MIX
	SG.MIX = false
	eq(SG.mixFor(1930), nil)
	SG.MIX = saved
end)

test("runner pool drivers inherit the main driver's new-map gate and log prefix (run 2026-10-13_2240: WORKS notNewMap)", function()
	local world = { demand = {}, inc = 10, steps = 3, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	c.main.newMap, c.main.listDir, c.main.prefix = true, "en", nil
	-- the build round's drivers: the main driver's gate, its (nil = "[SQOT]") prefix
	local d = r:poolDriver(1, c.main, "simPool")
	eq(d.newMap, true, "build round driver: newMap")
	eq(d.listDir, "en")
	eq(d.prefix, nil, "the main driver's prefix, not [SQOT_DEV]")
	-- the dev tasks' drivers: the dev driver has none of its own, the main driver's gate is used
	c.H.main = c.main
	local d2 = r:poolDriver(1)
	eq(d2.newMap, true, "dev pool driver: newMap from the main driver")
	eq(d2.prefix, "[SQOT_DEV]")
	c.H.main = nil
end)

---------------------------------------------------------------------------
-- speed-up (2026-10-14, after the run 2026-10-14_0302: Quick 175 s): pace 0, the main driver held through the fill,
-- early fills during the round, the extent neighbour rule, Fill every 8, Build out, the game date

test("pace 0: a year passes as soon as its size commands came back; same sizes as a paced run; not while paused", function()
	local env = fakeEnv({ holdCallbacks = true })
	local sim = fixedSim(env, { pace = 0, seed = 1 })
	run(sim, env, 0.2)
	eq(sim.years, 0, "the year waits for its callbacks")
	local sent = #env.sent
	run(sim, env, 1.0)
	eq(#env.sent, sent, "no next step while the callbacks are out")
	for _, cb in ipairs(env.held) do cb(true) end
	env.held = {}
	run(sim, env, 0.05)
	eq(sim.years, 1)
	-- callbacks at once: many years per real second, no town ever busy
	local e2 = fakeEnv()
	local s2 = fixedSim(e2, { pace = 0, seed = 1, limit = 20 })
	local r = run(s2, e2, 1.0)
	eq(r, "limit")
	eq(s2.years, 20)
	for _, l in ipairs(yearLines(e2)) do ok(not l:find("busy:", 1, true), l) end
	local e3 = fakeEnv()
	local s3 = fixedSim(e3, { pace = 1, seed = 1 })
	run(s3, e3, 20.2)
	eq(s3.years, 20)
	near(persons(e2.T[11]), persons(e3.T[11]), 1e-6, "the same sizes as at 1 s per year")
	near(persons(e2.T[12]), persons(e3.T[12]), 1e-6)
	-- paused game: no step
	local e4 = fakeEnv()
	local s4 = fixedSim(e4, { pace = 0, seed = 1 })
	e4.speedV = 0
	run(s4, e4, 2)
	eq(s4.step, 0)
	ok(s4:status().head:find("as fast as possible", 1, true), s4:status().head)
end)

test("early fill: towns whose round part ended are filled while the round still runs elsewhere", function()
	local env = fakeEnv()
	local ready, filling, doneRound = {}, {}, false
	env.rounds = {}
	function env.roundStart(towns, now, o)
		local h = { towns = towns, o = o }
		env.rounds[#env.rounds + 1] = h
		return h
	end
	function env.roundReady(h) local out = ready; ready = {} return out end
	function env.roundFilling(h, t, on) filling[#filling + 1] = { t = t, on = on } end
	function env.roundTick(h, now)
		if not doneRound then return nil end
		return { towns = #h.towns, checks = 2, builds = 1, edges = 5, served = 2, capped = 0, s = 1, peak = 2, per = "x" }
	end
	local sim = fixedSim(env, { pace = 1, seed = 1, fastFill = true, fillEvery = 1, buildRound = true,
		roundBuilds = 9, roundMaxS = 7 })
	env.T[11].actual, env.T[12].actual = 10, 10
	run(sim, env, 1.1)
	eq(sim.phase, "round")
	eq(env.rounds[1].o.builds, 9, "the round's limits passed on")
	eq(env.rounds[1].o.maxS, 7)
	local forced = function()
		local n, ts = 0, {}
		for _, s in ipairs(env.sent) do if s.forced then n = n + 1; ts[#ts + 1] = s.t end end
		return n, ts
	end
	eq(forced(), 0, "nothing ready: no fill yet")
	ready = { 12 }
	run(sim, env, 0.1)
	local n, ts = forced()
	eq(n, 1); eq(ts[1], 12, "town 12's fill while 11 still builds")
	eq(sim.phase, "round")
	eq(filling[1].t, 12); eq(filling[1].on, true); eq(filling[2].on, false, "its fill came back")
	doneRound = true
	run(sim, env, 0.1)
	n, ts = forced()
	eq(n, 2, "the rest filled after the round, 12 not again")
	eq(ts[2], 11)
	eq(sim.phase, "run")
	local y = yearLines(env)[1]
	ok(y:find("fillEarly=1", 1, true) and y:find("filled=2", 1, true), y)
end)

test("runner: the main driver stays held through the fill after a round, free again after it", function()
	local world = { demand = { [11] = 0, [12] = 0, [13] = 0 }, inc = 6, steps = 2, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	c.env.updateSize = function(t, f, cb, forced)
		c.env.sent[#c.env.sent + 1] = { t = t, f = f, forced = forced == true }
		local w = c.env.T[t]
		w.sizeFactors = { f[1], f[2], f[3] }
		if forced then c.held = c.held or {}; c.held[#c.held + 1] = cb else cb(true) end
	end
	r.X.updateSize = c.env.updateSize
	r:command({ action = "simStart", pace = 2, seed = 1, scope = "all", fillEvery = 1 }, 0, c.S)
	for t, st in pairs(r.sim.towns) do st.rate = t == 13 and 0 or 2 end
	c.env.T[11].actual, c.env.T[12].actual = 10, 10
	local now, sawFill = 0, false
	for _ = 1, 200 do
		now = now + 50000
		r:tick(now)
		if r.sim.phase == "fill" then
			sawFill = true
			eq(c.H.devBusy, true, "held during the fill")
			break
		end
	end
	ok(sawFill, "a fill ran")
	for _ = 1, 5 do
		now = now + 50000
		r:tick(now)
		eq(c.H.devBusy, true, "held while the fill's commands are out")
	end
	eq(#(c.held or {}), 2, "both lagging towns filled")
	for _, cb in ipairs(c.held or {}) do cb(true) end
	c.held = {}
	for _ = 1, 3 do now = now + 50000; r:tick(now) end
	eq(r.sim.phase, "run")
	eq(c.H.devBusy, false, "free after the fill")
	r:command({ action = "simStop" }, now, c.S)
end)

test("runner round: the extent rule pairs small neighbours, keeps big ones apart; no job beside a filling town", function()
	local world = { demand = {}, inc = 10, steps = 3, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	local pos = { [1] = 0, [2] = 1800, [3] = 1800 }
	r.E.boxCentre = function(t) return pos[t], 0 end
	c.main.towns[1], c.main.towns[2] = { extR = 150 }, { extR = 150 }
	r.simRound = { owner = c.main, filling = {} }
	eq(r:simNear(1, 2), false, "two 150 m towns 1.8 km apart: plans can't meet (was: within 2 km)")
	c.main.towns[2].extR = 600
	eq(r:simNear(1, 2), true, "a 600 m town 1.8 km away: they may")
	c.main.towns[3] = nil
	eq(r:simTownR(3), SG.ROUND_R_DEFAULT, "unknown extent: the default")
	c.main.towns[2].extR = 150
	r.simRound.filling[2] = true
	eq(r:simRoundClear(1, {}), true, "a far filling town doesn't hold the job")
	pos[2] = 500
	eq(r:simRoundClear(1, {}), false, "a near town's fill in flight holds it")
	r.simRound = nil
end)

test("runner round: simRoundReady hands out each finished town once, not beside a running neighbour", function()
	local world = { demand = { [11] = 30, [12] = 0, [13] = 0 }, inc = 10, steps = 3, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	local pos = { [11] = 0, [12] = 500, [13] = 20000 }
	r.E.boxCentre = function(t) return pos[t], 0 end
	local rd = r:simRoundStart({ 11, 12, 13 }, 0, { builds = 2, maxS = 30 })
	eq(rd.maxBuilds, 2)
	local handed, now = {}, 0
	local res
	for _ = 1, 400 do
		now = now + 50000
		for _, t in ipairs(r:simRoundReady(rd)) do
			handed[#handed + 1] = t
			ok(t ~= 11 or world.active == 0, "11 only when its jobs ended")
		end
		res = r:simRoundTick(rd, now)
		if res then break end
	end
	ok(res, "the round ended")
	eq(c.main.towns[11].builds, 2, "capped at the round's own limit (2, not ROUND_BUILDS)")
	local pos13, pos12 = nil, nil
	for i, t in ipairs(handed) do if t == 13 then pos13 = i end if t == 12 then pos12 = i end end
	ok(pos13 ~= nil, "13 (far away) handed out")
	ok(pos12 == nil or pos12 > 1, "12 waits while its neighbour 11 builds")
	local seen = {}
	for _, t in ipairs(handed) do ok(not seen[t], "once each"); seen[t] = true end
end)

test("Fill every 8: options 1/2/4/8, rounds and fills every 8 years", function()
	eq(SG.FILL_EVERY, { 1, 2, 4, 8 })
	eq(SG.QUICK.fillEvery, 4); eq(SG.QUICK.pace, 0)
	local env = fakeEnv()
	fakeRound(env, { ticks = 1 })
	local sim = fixedSim(env, { pace = 0, seed = 1, fastFill = true, fillEvery = 8, buildRound = true, limit = 16 })
	env.T[11].actual = 10
	for _ = 1, 400 do
		env.now = env.now + 50000
		if sim:tick(env.now) == "limit" then break end
	end
	eq(sim.years, 16)
	eq(#env.rounds, 2, "rounds in years 8 and 16")
end)

test("Build out: chunks of years, one size step each, round + fill per chunk, sizes as a yearly run; SIMGROW chunk", function()
	local env = fakeEnv()
	fakeRound(env, { ticks = 1 })
	local B = SG.BUILDOUT
	local chunk = B.years / B.chunks
	local sim = fixedSim(env, { pace = 0, seed = 1, fastFill = true, buildRound = true, limit = B.years, chunk = chunk })
	env.T[11].actual = 10
	local r
	for _ = 1, 2000 do
		env.now = env.now + 50000
		r = sim:tick(env.now)
		if r == "limit" then break end
	end
	eq(r, "limit")
	eq(sim.years, B.years)
	eq(#env.rounds, B.chunks, "a round per chunk")
	local chunks = {}
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW chunk") then chunks[#chunks + 1] = l end end
	eq(#chunks, B.chunks)
	ok(chunks[1]:find("chunk=1 of=" .. B.chunks .. " years=" .. chunk, 1, true) and chunks[1]:find("year=" .. chunk, 1, true), chunks[1])
	eq(#yearLines(env), 0, "no year lines in Build out")
	local steps11 = 0
	for _, s in ipairs(env.sent) do if s.t == 11 and not s.forced then steps11 = steps11 + 1 end end
	eq(steps11, B.chunks, "one size step per chunk")
	-- the same sizes as a yearly run of the same years (experience still in quarter years)
	local e2 = fakeEnv()
	local s2 = fixedSim(e2, { pace = 0, seed = 1, limit = B.years })
	for _ = 1, 4000 do
		e2.now = e2.now + 50000
		if s2:tick(e2.now) == "limit" then break end
	end
	eq(s2.years, B.years)
	near(persons(env.T[11]), persons(e2.T[11]), persons(e2.T[11]) * 0.01, "fast town")
	near(persons(env.T[12]), persons(e2.T[12]), persons(e2.T[12]) * 0.01, "medium town")
	ok(sim:status().head:find("build out, 10-year chunks: " .. B.chunks .. " of " .. B.chunks, 1, true), sim:status().head)
end)

test("move the game date: forward to the start year + simulated years at each round, never back; off by default", function()
	local env = fakeEnv()
	fakeRound(env, { ticks = 1 })
	local gameYear = 1900
	env.year = function() return gameYear end
	local sets = {}
	env.setYear = function(y, cb) sets[#sets + 1] = y; gameYear = y; cb(true) end
	local sim = SG.new(env, { pace = 0, seed = 1, fastFill = true, fillEvery = 4, buildRound = true, limit = 12, moveDate = true })
	sim:start(env.now, false)
	for _ = 1, 600 do
		env.now = env.now + 50000
		if sim:tick(env.now) == "limit" then break end
	end
	eq(sets, { 1904, 1908, 1912 })
	local dl
	for _, l in ipairs(env.logs) do if l:find("^SIMGROW date") then dl = l end end
	ok(dl and dl:find("year=1912", 1, true) and dl:find("ok=true", 1, true), dl)
	-- a later map: never back
	local e2 = fakeEnv()
	fakeRound(e2, { ticks = 1 })
	local y2 = 1900
	e2.year = function() return y2 end
	local sets2 = {}
	e2.setYear = function(y, cb) sets2[#sets2 + 1] = y; cb(true) end
	local s2 = SG.new(e2, { pace = 0, seed = 1, fastFill = true, fillEvery = 4, buildRound = true, limit = 8, moveDate = true })
	s2:start(e2.now, false)
	y2 = 1950   -- the player moved the date meanwhile
	for _ = 1, 600 do
		e2.now = e2.now + 50000
		if s2:tick(e2.now) == "limit" then break end
	end
	eq(#sets2, 0, "1904 / 1908 are before the game's 1950: never set back")
	-- off: no date command
	local e3 = fakeEnv()
	local n3 = 0
	e3.year = function() return 1900 end
	e3.setYear = function(_y, cb) n3 = n3 + 1; cb(true) end
	local s3 = SG.new(e3, { pace = 0, seed = 1, limit = 8 })
	s3:start(e3.now, false)
	for _ = 1, 200 do
		e3.now = e3.now + 50000
		if s3:tick(e3.now) == "limit" then break end
	end
	eq(n3, 0)
end)

test("runner: Build out starts fresh with chunks, every town, the tour; lowers the upward gaps, restores them", function()
	local world = { demand = { [11] = 0, [12] = 0, [13] = 0 }, inc = 6, steps = 1, active = 0, peak = 0, jobs = {} }
	local r, c = roundRunner(world)
	local UP = { GAP_S = 240, LV_GAP_S = 300 }
	r.UP = UP
	local p = { action = "simStart", pace = 5, seed = 1, scope = "all", mode = "buildout", tourWhenDone = false, even = false }
	r:command(p, 0, c.S)
	local start = findLine(c.lines, "SIMGROW start")
	local B = SG.BUILDOUT
	ok(start:find("mode=buildout chunks=" .. B.chunks .. " years=" .. B.years, 1, true) and start:find("pace=0", 1, true)
		and start:find("even=true", 1, true) and start:find("tourWhenDone=true", 1, true)
		and start:find("roundBuilds=" .. B.roundBuilds, 1, true), start)
	eq(r.sim.chunk, B.years / B.chunks)
	eq(UP.GAP_S, B.upGapS); eq(UP.LV_GAP_S, B.upGapS)
	local now = 0
	for _ = 1, 6000 do
		now = now + 50000
		r:tick(now)
		if not r.sim.running then break end
	end
	eq(r.sim.running, false, "stopped at the year limit")
	eq(r.sim.years, B.years)
	local stop = findLine(c.lines, "SIMGROW stop")
	ok(stop:find("reason=limit", 1, true) and stop:find("upGap=restored", 1, true) and stop:find("mode=buildout", 1, true), stop)
	eq(UP.GAP_S, 240); eq(UP.LV_GAP_S, 300)
	eq(r.sim.autoTour, 1, "the tour asked for")
	local chunks = 0
	for _, l in ipairs(c.lines) do if l:find("SIMGROW chunk", 1, true) then chunks = chunks + 1 end end
	eq(chunks, B.chunks)
	-- a second Build out starts fresh (no resume)
	r:command(p, now, c.S)
	eq(r.sim.years, 0)
	r:command({ action = "simStop" }, now, c.S)
	-- Quick (mode quick) logs its mode
	r:command({ action = "simStart", pace = 1, seed = 1, scope = "all", mode = "quick" }, now, c.S)
	local starts = {}
	for _, l in ipairs(c.lines) do if l:find("SIMGROW start", 1, true) then starts[#starts + 1] = l end end
	ok(starts[#starts]:find("mode=quick", 1, true) and starts[#starts]:find("pace=0", 1, true), starts[#starts])
	r:command({ action = "simStop" }, now, c.S)
end)

test("sim: a cut head start (firstRound) adds a build round in the first year; otherwise every fillEvery years", function()
	local env = fakeEnv()
	local sim = SG.new(env, { pace = 0, seed = 1, fillEvery = 4, buildRound = true, firstRound = true })
	sim.years = 0
	ok(sim:roundYear(), "year 1: round")
	sim.years = 1
	ok(not sim:roundYear(), "year 2: none")
	sim.years = 3
	ok(sim:roundYear(), "year 4: round")
	local plain = SG.new(env, { pace = 0, seed = 1, fillEvery = 4, buildRound = true })
	plain.years = 0
	ok(not plain:roundYear(), "no cut: no first-year round")
end)
