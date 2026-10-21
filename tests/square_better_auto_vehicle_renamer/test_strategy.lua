-- Better Auto Vehicle Renamer: the sweep strategy (PLAN.md "Sweep strategy (2026-10-20)") against the fake game:
-- the list diff (a settled fleet reads only the backstop slice), new / sold vehicles within one cycle, the backstop's
-- bound for what the id list can't show (Replace keeping the id), the line watch (only with a setting that shows the
-- line), the expiry heap (old-vehicle mark), the idle back-off, the rename budget carry, several Lua states, caps.

local Sweep = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_sweep.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Text = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_text.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_better_auto_vehicle_renamer/"
local G = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local FULL = os.getenv("TEST_FULL") ~= nil
local IDLE_MS = Sweep.IDLE_MAX_W * Sweep.CYCLE_MS

local function answered(opts)
	local g = G.new(opts)
	g:update()
	g:answer("apply")
	g:cycles(1, 50)
	return g
end

local function fleet(g, n, f)
	local ids = {}
	for i = 1, n do
		local o = {}
		for k, v in pairs(f or {}) do o[k] = v end
		ids[i] = g:buy(o)
	end
	return ids
end

--- Run until the sweep is idle (the interval at its longest) and the cycle has just ended.
local function idle(g, maxUpdates)
	for _ = 1, maxUpdates or 5000 do
		local phase = g:update()
		if phase == "end" and g.rt.ivW == Sweep.IDLE_MAX_W then return true end
	end
	error("never idle")
end

--- Updates until cond() holds; returns the game ms it took (error past maxMs).
local function until_(g, cond, maxMs)
	local t0 = g.now
	while not cond() do
		g:update()
		if g.now - t0 > maxMs then error("not within " .. maxMs .. " ms") end
	end
	return g.now - t0
end

local function countRenders(fn)
	local render, n = Text.render, 0
	Text.render = function(...) n = n + 1; return render(...) end
	local ok_, e = pcall(fn)
	Text.render = render
	if not ok_ then error(e, 0) end
	return n
end

---------------------------------------------------------------------------

test("steady state: per cycle only the backstop slice is read; no renders, no line reads, no writes", function()
	local g = answered({ params = { ["bavr.speed"] = 3 } })
	fleet(g, 600, { line = 900 })
	idle(g)
	eq(#g.sent, 600)
	local sets, lines, ln = g.sets, g.calls.lines, g.calls.lineName
	local cycles, worst = 0, 0
	local renders = countRenders(function()
		local r0, t0 = g.calls.read, nil
		for _ = 1, 400 do -- 80 s
			local phase = g:update()
			if phase == "list" then
				if t0 ~= nil then
					local reads = g.calls.read - r0
					local allow = (g.now - t0) * Sweep.BACKSTOP / Sweep.CYCLE_MS + 1
					ok(reads <= allow, "reads " .. reads .. " in " .. (g.now - t0) .. " ms (allowed " .. allow .. ")")
					if reads > worst then worst = reads end
					cycles = cycles + 1
				end
				r0, t0 = g.calls.read, g.now
			end
		end
	end)
	ok(cycles >= 6, "cycles " .. cycles)
	ok(worst > 0, "the backstop reads something")
	eq({ renders, g.sets - sets, g.calls.lines - lines, g.calls.lineName - ln }, { 0, 0, 0, 0 })
end)

test("a new vehicle is named within one cycle of the idle interval; a sale is pruned and forgotten", function()
	local g = answered()
	local ids = fleet(g, 300, { line = 900 })
	idle(g)
	local r0 = g.calls.read
	local id = g:buy({ line = 900 })
	local took = until_(g, function() return g:name(id) == "Mercedes-Benz Citaro B-0301" end, IDLE_MS + 4000)
	ok(took <= IDLE_MS + 2000, "named in " .. took .. " ms")
	-- the new id read twice (the rename lease: claimed in one cycle, renamed in the next window's) plus the backstop,
	-- whose allowance runs from the last list (up to one window before the purchase)
	local reads = g.calls.read - r0
	ok(reads <= 2 + (took + Sweep.CYCLE_MS) * Sweep.BACKSTOP / Sweep.CYCLE_MS, "the new id plus the backstop: " .. reads)
	g:cycles(1, 100)
	eq(g.rt.ivW, 1, "a change: back to the shortest interval")
	idle(g)
	g:sell(ids[7])
	local pruned = false
	until_(g, function()
		pruned = pruned or g.rt.stats.pruned > 0
		return pruned
	end, IDLE_MS + 2000)
	eq(g:rec(ids[7]), nil, "the record is pruned")
	eq({ g.rt.mark[ids[7]], g.rt.inN[ids[7]], g.rt.n }, { nil, nil, 300 }, "this state's entries dropped")
end)

test("backstop: a Replace keeping the id is renamed within ceil(n / BACKSTOP) windows plus one idle interval", function()
	local n = 300
	local bound = math.ceil(n / Sweep.BACKSTOP) * Sweep.CYCLE_MS + IDLE_MS + 2000
	local picks = FULL and { 1, 37, 99, 150, 201, 263, 300 } or { 1, 150, 300 }
	for _, k in ipairs(picks) do
		local g = answered()
		local ids = fleet(g, n, { line = 900 })
		idle(g)
		local id = ids[k]
		g.vehicles[id].model, g.vehicles[id].pt = 8, g.now
		local took = until_(g, function() return g:name(id) == string.format("Solaris Urbino B-%04d", k) end, bound)
		ok(took <= bound, "vehicle " .. k .. ": " .. took .. " ms")
		eq(g:rec(id).t, k, "the number stays")
	end
end)

test("line rename: no line setting means no line reads and no renames; a line format re-renders that line only", function()
	local g = answered()
	fleet(g, 50, { line = 900 })
	fleet(g, 20, { line = 901 })
	idle(g)
	local sent, ln, lines = #g.sent, g.calls.lineName, g.calls.lines
	g.lines[900] = "Bus 14"
	for _ = 1, 150 do g:update() end -- 30 s
	eq({ #g.sent - sent, g.calls.lineName - ln, g.calls.lines - lines }, { 0, 0, 0 })

	local h = answered({ params = { ["bavr.format"] = 5, ["bavr.speed"] = 3 } })
	local a = fleet(h, 50, { line = 900 })
	local b = fleet(h, 20, { line = 901 })
	idle(h)
	eq(h:name(a[1]), "Bus 12 · B-0001")
	ok(h.calls.lines > 0, "the line watch runs with a line format")
	local sent2 = #h.sent
	h.lines[900] = "Bus 14"
	local took = until_(h, function() return h:name(a[1]) == "Bus 14 · B-0001" end, IDLE_MS + 4000)
	ok(took <= IDLE_MS + 2000, "renamed in " .. took .. " ms")
	until_(h, function() return h:name(a[50]) == "Bus 14 · B-0050" end, 2 * Sweep.CYCLE_MS + 2000) -- (25 per window)
	idle(h)
	eq(#h.sent - sent2, 50, "only line 900's vehicles")
	eq(h:name(b[1]), "Harbor Express · B-0051")
end)

test("line watch: a vehicle moved to another line is renamed within one cycle, long before the backstop", function()
	local g = answered({ params = { ["bavr.format"] = 5 } })
	local a = fleet(g, 600, { line = 900 }) -- the backstop needs 24 s for 600
	idle(g)
	local id = a[400]
	g.vehicles[id].line = 901
	local took = until_(g, function() return g:name(id) == "Harbor Express · B-0400" end, IDLE_MS + 6000)
	ok(took <= IDLE_MS + 2000, "moved in " .. took .. " ms")
	-- per line counting: the old line closes up, the mover goes to the end of its new line
	local h = answered({ params = { ["bavr.counter"] = 4, ["bavr.format"] = 3, ["bavr.speed"] = 3 } })
	local b = fleet(h, 300, { line = 900 })
	idle(h)
	h.vehicles[b[290]].line = 901
	until_(h, function() return h:name(b[300]) == "Bus 12 #299" and h:name(b[290]) == "Harbor Express #01" end,
		IDLE_MS + 8000)
end)

test("line watch off (the reader has no line list): names are re-read once per cycle, the backstop catches renames", function()
	local g = answered({ params = { ["bavr.format"] = 5, ["bavr.speed"] = 3 } })
	g.noLineWatch = true
	local a = fleet(g, 100, { line = 900 })
	local l0 = g.calls.lines
	idle(g)
	eq(g.calls.lines, l0)
	g.lines[900] = "Bus 14"
	local bound = math.ceil(100 / Sweep.BACKSTOP) * Sweep.CYCLE_MS + IDLE_MS + 2000
	until_(g, function() return g:name(a[100]) == "Bus 14 · B-0100" end, bound + 4 * Sweep.CYCLE_MS)
	-- a failing line list (nil) works the same way
	local h = answered({ params = { ["bavr.format"] = 5 } })
	local b = fleet(h, 20, { line = 900 })
	idle(h)
	h.linesFail = true
	h.lines[900] = "Bus 15"
	until_(h, function() return h:name(b[20]) == "Bus 15 · B-0020" end, bound)
	eq(h.rt.lwOk, false)
end)

test("old mark: the lifespan passing is marked within one window of it, even while idle (the expiry heap)", function()
	local g = answered({ params = { ["bavr.old"] = 3, ["bavr.format"] = 3 } })
	local exp = g.now + 200000
	local ids = fleet(g, 300, { line = 900 })
	local x = g:buy({ line = 900, exp = exp })
	local y = g:buy({ line = 900, exp = exp + 1e9 })
	idle(g)
	ok(g.now < exp, "idle before the expiry")
	eq(g:name(x), "B-0301")
	until_(g, function() return g:name(x) == "B-0301 *" end, 300000)
	ok(g.now - exp <= Sweep.CYCLE_MS + 1000, "marked " .. (g.now - exp) .. " ms after the expiry")
	eq(g:name(y), "B-0302")
	eq(g:name(ids[1]), "B-0001", "no lifespan: never")
end)

test("back-off: the interval doubles to IDLE_MAX_W windows while nothing changes, a change or wake resets it", function()
	local g = answered()
	fleet(g, 40, { line = 900 })
	g:cycles(4, 400)
	local starts = {}
	for _ = 1, 600 do
		if g:update() == "list" then starts[#starts + 1] = g.now end
	end
	local gaps = {}
	for i = 2, math.min(#starts, 7) do gaps[#gaps + 1] = math.floor((starts[i] - starts[i - 1]) / 1000 + 0.5) end
	-- after the last change: 2, 4, 8, then 10 s (window aligned: within one update of each)
	local seenMax = false
	for i = 1, #gaps do
		ok(gaps[i] <= IDLE_MS / 1000 + 1, "gap " .. gaps[i])
		if gaps[i] >= IDLE_MS / 1000 - 1 then seenMax = true end
	end
	ok(seenMax, "reached the idle interval: " .. table.concat(gaps, ","))
	eq(g.rt.ivW, Sweep.IDLE_MAX_W)
	g:buy({ line = 900 })
	g:cycles(1, 100)
	eq(g.rt.ivW, 1, "a new vehicle: back to one window")
	idle(g)
	Sweep.wake(g.rt)
	eq(g.rt.ivW, 1)
end)

test("budget carry: renaming a big Apply pass reads about the budget per window, not the whole queue", function()
	local g = G.new()
	local ids = {}
	for i = 1, 400 do ids[i] = g:buy({ line = 900, pt = 50000 - i }) end
	g:update()
	g:answer("apply")
	until_(g, function() return g.rt.stats.passCreated > 0 end, 20000) -- the collect cycle (a full one)
	-- the leader waits in the scan for the next window (the lease's hold) instead of reading on: per window it reads
	-- the budget plus the vehicle it waits at, and per cycle the backstop and the renamed ones once more
	local r0, perWinReads = g.calls.read, {}
	local perWin, last, lastR = {}, #g.sent, g.calls.read
	for _ = 1, 2000 do
		g:update(200)
		local w = math.floor(g.now / Sweep.CYCLE_MS)
		perWin[w] = (perWin[w] or 0) + (#g.sent - last)
		perWinReads[w] = (perWinReads[w] or 0) + (g.calls.read - lastR)
		last, lastR = #g.sent, g.calls.read
		if #g.sent >= 400 then break end
	end
	eq(#g.sent, 400, "all renamed")
	local windows, worst = 0, 0
	for w, n in pairs(perWin) do
		ok(n <= 10, "window " .. w .. ": " .. n)
		windows = windows + 1
		if perWinReads[w] > worst then worst = perWinReads[w] end
	end
	local mean = (g.calls.read - r0) / windows
	print(string.format("reads per window: mean %.1f, busiest %d; %d windows", mean, worst, windows))
	ok(mean <= 3 * 10, "reads per window: " .. mean)
	-- (the busiest: the cycle after a long hold, whose backstop slice covers the hold: BACKSTOP_MAX at most)
	ok(worst <= 3 * 10 + Sweep.BACKSTOP_MAX, "reads in the busiest window: " .. worst)
	ok(windows <= 400 / 10 + 3, "windows: " .. windows)
	for i = 1, 400, 57 do eq(g:name(ids[i]), string.format("Mercedes-Benz Citaro B-%04d", 401 - i)) end
end)

test("several Lua states: each keeps its own id set; settled costs the backstop in each; a new vehicle numbered once", function()
	local g = answered({ share = false })
	fleet(g, 200, { line = 900 })
	local rtA, rtB = g.rt, Sweep.newRuntime()
	local function run(n)
		for i = 1, n do
			g.rt = (i % 2 == 0) and rtB or rtA
			g:update(100)
		end
	end
	run(3000)
	eq(#g.sent >= 200, true)
	local sent, r0 = #g.sent, g.calls.read
	run(1200) -- 120 s game time, each state sees 60 s of updates
	ok(g.calls.read - r0 <= 2 * (120000 / Sweep.CYCLE_MS * Sweep.BACKSTOP + Sweep.BACKSTOP), "reads " .. (g.calls.read - r0))
	eq(#g.sent, sent, "settled: no renames")
	local id = g:buy({ line = 900 })
	run(400)
	eq(g:name(id), "Mercedes-Benz Citaro B-0201")
	local named = 0
	for _, e in ipairs(g.sent) do if e[1] == id then named = named + 1 end end
	eq(named, 1, "renamed once, by one of the states")
	ok(rtA.mark[id] ~= nil and rtB.mark[id] ~= nil, "both states listed it")
end)

test("caps: a failed list prunes nothing; expiries over MAX_EXP_POP and a full heap still mark everyone", function()
	local g = answered()
	local ids = fleet(g, 30, { line = 900 })
	idle(g)
	g.listFail = true
	local errs = 0
	for _ = 1, 200 do
		g:update()
		errs = errs + g.rt.stats.listErr
	end
	ok(errs >= 1, "the failure counted")
	eq(Reg.size(g:state()), 30, "nothing pruned")
	eq(g.rt.n, 30)
	eq(#g.sent, 30, "nothing renamed again")
	g.listFail = false
	idle(g)
	eq(Reg.size(g:state()), 30)

	local oldPop, oldHeap = Sweep.MAX_EXP_POP, Sweep.MAX_HEAP
	Sweep.MAX_EXP_POP, Sweep.MAX_HEAP = 3, 8
	local h = answered({ params = { ["bavr.old"] = 3, ["bavr.format"] = 3 } })
	local exp = h.now + 40000
	local v = {}
	for i = 1, 12 do v[i] = h:buy({ line = 900, exp = exp + (i % 2) }) end
	local okRun, e = pcall(function()
		idle(h)
		until_(h, function()
			for i = 1, 12 do if h:name(v[i]) ~= string.format("B-%04d *", i) then return false end end
			return true
		end, 120000)
	end)
	Sweep.MAX_EXP_POP, Sweep.MAX_HEAP = oldPop, oldHeap
	if not okRun then error(e, 0) end
	ok(h.rt.hn <= 8 + 1, "the heap stays at its cap")
end)

test("caps: the backstop and the line watch take at most their per-cycle maximum after a long gap", function()
	local g = answered({ params = { ["bavr.format"] = 5 } })
	fleet(g, 120, { line = 900 })
	for li = 1, 30 do g.lines[2000 + li] = "L" .. li end
	idle(g)
	local oldB, oldL = Sweep.BACKSTOP_MAX, Sweep.LINE_MAX
	Sweep.BACKSTOP_MAX, Sweep.LINE_MAX = 7, 5
	local r0, l0 = g.calls.read, g.calls.lineVehicles
	g.now = g.now + 50000 -- a long gap (e.g. a slow tick)
	local maxBack, maxLines = 0, 0
	local okRun, e = pcall(function()
		for _ = 1, 200 do
			g:update()
			if g.rt.stats.back > maxBack then maxBack = g.rt.stats.back end
			if g.rt.stats.lineChecks > maxLines then maxLines = g.rt.stats.lineChecks end
		end
	end)
	Sweep.BACKSTOP_MAX, Sweep.LINE_MAX = oldB, oldL
	if not okRun then error(e, 0) end
	ok(maxBack <= 7 and maxBack > 0, "backstop per cycle " .. maxBack)
	ok(maxLines <= 5 and maxLines > 0, "lines per cycle " .. maxLines)
	ok(g.calls.read > r0 and g.calls.lineVehicles > l0)
end)
