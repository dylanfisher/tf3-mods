-- SQPERF instrumentation module (content/sqperf/square_problem_radar.lua, canonical copy in
-- tools/sqperf/sqperf.lua): thresholds, rate limiting, the opt-in window summary, phases, the
-- wrapper's transparency, untimed instruments and the hot path's allocations.
-- run_tests: no-split (the module caches its Clock per load; tests reset modules where it matters)

local PATH = "square_problem_radar::/sqperf/square_problem_radar.lua"
local MOD = "square_problem_radar"

local function load()
	reset_modules()
	return ug_require(PATH)
end

-- Fake ms clock the tests move by hand.
local function fakeClock(start)
	local c = { t = start or 1000 }
	c.now = function() return c.t end
	return c
end

local function lines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern)) then out[#out + 1] = e.msg end
	end
	return out
end

local function params(value)
	set_global("api", { engine = { config = { getModParams = function()
		return { [MOD] = { sqperf_log = value } }
	end } } })
end

before_each(function()
	clear_logs()
	set_global("api", nil)
end)

test("thresholds by context", function()
	local sq = load()
	eq(sq.GUI_SLOW_MS, 16)
	eq(sq.SIM_SLOW_MS, 50)
	eq(sq.new({ mod = MOD, ctx = "gui" }).slowMs, 16)
	eq(sq.new({ mod = MOD, ctx = "hud", timed = false }).slowMs, 16)
	eq(sq.new({ mod = MOD, ctx = "gs" }).slowMs, 50)
	eq(sq.new({ mod = MOD, ctx = "gs", slowMs = 5 }).slowMs, 5)
end)

test("no lines below the threshold, also over many windows with level 3 off", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
	params(1) -- Off
	for _ = 1, 5000 do
		local t0 = p:start()
		c.t = c.t + 49.9
		p:stop("scan", t0)
		p:count("x")
	end
	eq(#lines(), 0)
	eq(p.on, false)
	local g = sq.new({ mod = MOD, ctx = "gui", now = c.now })
	for _ = 1, 100 do
		local t0 = g:start()
		c.t = c.t + 16
		g:stop("render", t0)
	end
	eq(#lines(), 0, "16.0 ms is not over 16")
end)

test("slow call: first line at once, then at most one per section per 60 s", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gui", now = c.now })
	local function call(ms)
		local t0 = p:start()
		c.t = c.t + ms
		p:stop("window_render", t0)
	end
	for _ = 1, 9 do call(2) end
	call(41.25)
	local l = lines()
	eq(#l, 1)
	ok(l[1]:find("^%[SQPERF%] mod=square_problem_radar ctx=gui vm=%x+ slow=window_render max=41.2 over=1/10$"), l[1])
	-- more slow calls inside the minute: silent
	call(30); call(80); call(3)
	eq(#lines(), 1)
	c.t = c.t + 60000
	call(1) -- not slow itself, but flushes the waiting summary
	l = lines()
	eq(#l, 2)
	ok(l[2]:find("slow=window_render max=80.0 over=2/4$"), l[2])
	-- nothing pending now: quiet
	c.t = c.t + 120000
	call(1)
	eq(#lines(), 2)
end)

test("rate limit is per section", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now })
	for _, name in ipairs({ "a", "b", "a", "b" }) do
		local t0 = p:start()
		c.t = c.t + 60
		p:stop(name, t0)
	end
	local l = lines()
	eq(#l, 2)
	ok(l[1]:find("slow=a "), l[1])
	ok(l[2]:find("slow=b "), l[2])
end)

test("a waiting slow summary is flushed at a window boundary by another section", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now })
	local function call(name, ms)
		local t0 = p:start()
		c.t = c.t + ms
		p:stop(name, t0)
	end
	call("scan", 70)
	call("scan", 90) -- waits (rate limit)
	eq(#lines(), 1)
	c.t = c.t + 61000
	call("update", 1) -- "scan" never runs again; the window boundary flushes it
	local l = lines()
	eq(#l, 2)
	ok(l[2]:find("slow=scan max=90.0 over=1/1$"), l[2])
end)

test("level 3 off: no window line and counters are not kept", function()
	local sq = load()
	local c = fakeClock()
	params(1)
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
	for _ = 1, 10 do
		local t0 = p:start()
		c.t = c.t + 31000
		p:stop("update", t0)
		p:count("toasts", 3)
	end
	eq(#lines("win_ms"), 0)
	eq(next(p.cnt), nil)
end)

test("level 3 on: one summary per window with sections, counters and memory", function()
	local sq = load()
	local c = fakeClock()
	params(2) -- On (1-based index of {"Off", "On"})
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
	local function call(name, ms)
		local t0 = p:start()
		c.t = c.t + ms
		p:stop(name, t0)
	end
	call("update", 1) -- opens the first window, reads the gate
	eq(p.on, true)
	call("update", 2); call("update", 4); call("scan_lines", 3)
	p:count("toasts", 2); p:count("toasts"); p:count("stateSet")
	p:hit("poll")
	eq(#lines("win_ms"), 0)
	c.t = c.t + 30000
	call("update", 1)
	local l = lines("win_ms")
	eq(#l, 1)
	ok(l[1]:find("^%[SQPERF%] mod=square_problem_radar ctx=gs vm=%x+ win_ms=300%d%d%.%d timer=custom mem_kb=%d+ | "), l[1])
	ok(l[1]:find(" | poll n=1 | scan_lines n=1 ms=3.000 max=3.000 | update n=3 ms=7.000 max=4.000 | stateSet c=1 | toasts c=3", 1, true), l[1])
	-- the next window starts empty
	c.t = c.t + 30000
	call("update", 1)
	l = lines("win_ms")
	eq(#l, 2)
	ok(l[2]:find(" | update n=1 ms=1.000 max=1.000", 1, true), l[2])
	ok(not l[2]:find("toasts", 1, true), "counters reset")
end)

test("level 3 gate is re-read at window boundaries", function()
	local sq = load()
	local c = fakeClock()
	params(1)
	local p = sq.new({ mod = MOD, ctx = "gui", now = c.now, paramKey = "sqperf_log" })
	local function call() local t0 = p:start(); c.t = c.t + 1; p:stop("r", t0) end
	call()
	eq(p.on, false)
	params(2)
	c.t = c.t + 30000
	call()
	eq(p.on, true)
	eq(#lines("win_ms"), 0, "the window that was off is not logged")
	c.t = c.t + 30000
	call()
	eq(#lines("win_ms"), 1)
end)

test("gate errors and missing params count as off", function()
	local sq = load()
	eq(sq.readParam(MOD, "sqperf_log"), false) -- api is nil
	set_global("api", { engine = { config = { getModParams = function() error("boom") end } } })
	eq(sq.readParam(MOD, "sqperf_log"), false)
	params(nil)
	eq(sq.readParam(MOD, "sqperf_log"), false)
	params(2)
	eq(sq.readParam(MOD, "sqperf_log"), true)
end)

test("master switch: square_sqperf_all in the params table turns the gate on", function()
	local sq = load()
	eq(sq.MASTER_MOD, "square_sqperf_all")
	-- debugOn on a params table (runFn's allModParams or getModParams())
	eq(sq.debugOn({ [MOD] = { sqperf_log = 1 } }, MOD), false, "own Off, no master")
	eq(sq.debugOn({ [MOD] = { sqperf_log = 2 } }, MOD), true, "own On")
	eq(sq.debugOn({ [MOD] = { sqperf_log = 1 }, square_sqperf_all = {} }, MOD), true, "own Off + master (no params: { })")
	eq(sq.debugOn({ square_sqperf_all = {} }, MOD), true, "master, own entry missing")
	eq(sq.debugOn({ [MOD] = {}, other_mod = {} }, MOD), false)
	eq(sq.debugOn({ [MOD] = { custom = 2 } }, MOD, "custom"), true, "explicit key")
	eq(sq.debugOn(nil, MOD), false)
	eq(sq.debugOn("x", MOD), false)
	-- readParam / the instrument gate read getModParams through it
	set_global("api", { engine = { config = { getModParams = function()
		return { [MOD] = { sqperf_log = 1 }, square_sqperf_all = {} }
	end } } })
	eq(sq.readParam(MOD, "sqperf_log"), true)
	eq(sq.readParam(MOD), true, "key defaults to sqperf_log")
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
	local t0 = p:start(); c.t = c.t + 1; p:stop("scan", t0)
	eq(p.on, true, "level 3 on via the master switch")
	t0 = p:start(); c.t = c.t + 30000; p:stop("scan", t0)
	eq(#lines("win_ms="), 1)
	-- master absent: off
	set_global("api", { engine = { config = { getModParams = function()
		return { [MOD] = { sqperf_log = 1 }, square_roundabouts = {} }
	end } } })
	eq(sq.readParam(MOD, "sqperf_log"), false)
	-- getModParams error: off (master can't be seen either)
	set_global("api", { engine = { config = { getModParams = function() error("boom") end } } })
	eq(sq.readParam(MOD, "sqperf_log"), false)
	local q = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
	t0 = q:start(); c.t = c.t + 1; q:stop("scan", t0)
	eq(q.on, false)
end)

test("phase detail: appended string or format pattern + args", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, initMs = 0 })
	local t0 = p:start(); c.t = c.t + 1.5
	near(p:phase("towns", t0, "towns=%d num=%s", 12, "nil"), 1.5, 1e-9)
	p:phase("rename", t0, "due=3 renamed_stops=1")
	p:phase("plain", t0)
	p:phase("bad", t0, "x=%d", "not a number") -- bad pattern: raw pattern, no error
	local l = lines("phase=")
	eq(#l, 4)
	ok(l[1]:find(" phase=towns ms=1.5 timer=custom towns=12 num=nil$"), l[1])
	ok(l[2]:find(" phase=rename ms=1.5 timer=custom due=3 renamed_stops=1$"), l[2])
	ok(l[3]:find(" phase=plain ms=1.5 timer=custom$"), l[3])
	ok(l[4]:find(" phase=bad ms=1.5 timer=custom x=%%d$"), l[4])
end)

test("phase detail below the threshold: no line, nothing allocated", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, enabled = false })
	local t0 = p:start()
	p:phase("warm", t0, "n=%d", 1)
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for i = 1, 20000 do
		c.t = c.t + 0.0001
		p:phase("towns", t0, "%s=%d num=%d", "towns", i, i)
	end
	local grown = collectgarbage("count") - before
	collectgarbage("restart")
	eq(#lines(), 0)
	ok(grown < 4, "grew " .. grown .. " KB")
end)

test("phase lines: init, and first once every listed section ran once", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, first = { "scan_a", "scan_b" } })
	local t0 = p:start()
	c.t = c.t + 212.4
	near(p:phase("init", t0), 212.4, 1e-9)
	local function call(name, ms) local s = p:start(); c.t = c.t + ms; p:stop(name, s) end
	call("scan_a", 40.1)
	call("update", 5)
	call("scan_a", 3) -- second call of scan_a does not count
	eq(#lines("phase=first"), 0)
	call("scan_b", 7.9)
	call("scan_b", 7.9)
	local l = lines("phase=")
	eq(#l, 2)
	ok(l[1]:find("^%[SQPERF%] mod=square_problem_radar ctx=gs vm=%x+ phase=init ms=212.4 timer=custom$"), l[1])
	ok(l[2]:find(" phase=first ms=48.0 scan_a=40.1 scan_b=7.9$"), l[2])
end)

test("phase lines below the init threshold are dropped while level 3 is off", function()
	local sq = load()
	eq(sq.INIT_LOG_MS, 5)
	local c = fakeClock()
	params(1) -- Off
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log", first = { "scan_a", "scan_b" } })
	eq(p.initMs, 5)
	local t0 = p:start()
	c.t = c.t + 4.9
	near(p:phase("init", t0), 4.9, 1e-9, "ms is returned even when not logged")
	local function call(name, ms) local s = p:start(); c.t = c.t + ms; p:stop(name, s) end
	call("scan_a", 2); call("scan_b", 2.9) -- first = 4.9
	eq(#lines(), 0)
	-- at the threshold: logged (init and first alike)
	local q = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log", first = { "scan_a", "scan_b" } })
	t0 = q:start(); c.t = c.t + 5; q:phase("init", t0)
	local function callQ(name, ms) local s = q:start(); c.t = c.t + ms; q:stop(name, s) end
	callQ("scan_a", 2); callQ("scan_b", 3)
	local l = lines("phase=")
	eq(#l, 2)
	ok(l[1]:find(" phase=init ms=5.0 timer=custom$"), l[1])
	ok(l[2]:find(" phase=first ms=5.0 scan_a=2.0 scan_b=3.0$"), l[2])
	-- opts.initMs overrides; 0 logs everything
	clear_logs()
	local r = sq.new({ mod = MOD, ctx = "gs", now = c.now, initMs = 0 })
	t0 = r:start(); r:phase("init", t0)
	eq(#lines("phase=init ms=0.0"), 1)
	local big = sq.new({ mod = MOD, ctx = "gs", now = c.now, initMs = 100 })
	t0 = big:start(); c.t = c.t + 99; big:phase("init", t0)
	eq(#lines("ms=99.0"), 0)
end)

test("level 3 on: phase lines are logged below the threshold (gate read at init)", function()
	local sq = load()
	local c = fakeClock()
	local reads = 0
	set_global("api", { engine = { config = { getModParams = function()
		reads = reads + 1
		return { [MOD] = { sqperf_log = 2 } }
	end } } })
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log", first = { "scan_a" } })
	eq(reads, 0, "new does not read the param of a timed instrument")
	eq(p.on, false, "not known yet at init: the first window opens on the first stop")
	local t0 = p:start()
	c.t = c.t + 0.4
	p:phase("init", t0)
	eq(reads, 1, "read once for the init line")
	ok(lines(" phase=init ms=0.4 ")[1] ~= nil)
	-- the first stop logs phase=first before its window opens: read again, logged
	local s = p:start(); c.t = c.t + 0.1; p:stop("scan_a", s)
	ok(lines(" phase=first ms=0.1 scan_a=0.1$")[1] ~= nil)
	eq(#lines("phase="), 2)
	-- gate errors count as off (states without api.engine)
	clear_logs()
	set_global("api", nil)
	local q = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
	t0 = q:start(); q:phase("init", t0)
	eq(#lines(), 0)
	-- an instrument with no gate at all: dropped, no error
	local u = sq.new({ mod = MOD, ctx = "hud", timed = false })
	u:phase("init", 0)
	eq(#lines(), 0)
	-- untimed with level 3 fixed on: logged (ms=0.0)
	local v = sq.new({ mod = MOD, ctx = "hud", timed = false, enabled = true })
	v:phase("init", 0)
	eq(#lines("phase=init ms=0.0 timer=none"), 1)
end)

test("wrap keeps arguments, every return value and errors", function()
	local sq = load()
	local c = fakeClock()
	local p = sq.new({ mod = MOD, ctx = "gs", now = c.now })
	local f = p:wrap("f", function(a, b, ...)
		return a, nil, b, select("#", ...), nil
	end)
	local r = table.pack(f(1, 2, nil, nil))
	eq(r.n, 5)
	eq(r[1], 1); eq(r[2], nil); eq(r[3], 2); eq(r[4], 2); eq(r[5], nil)
	eq(select("#", p:wrap("g", function() end)()), 0)
	eq(p.sec.f.n, 1)
	-- errors pass through unchanged, same object; pcall at the call site behaves as before
	local errObj = { code = 7 }
	local g = p:wrap("g", function() error(errObj) end)
	local okCall, e = pcall(g)
	eq(okCall, false)
	ok(e == errObj, "same error object")
	local h = p:wrap("h", function() error("bad thing", 0) end)
	local okH, eh = pcall(h)
	eq(okH, false); eq(eh, "bad thing")
	raises(function() h() end, "bad thing")
	-- pcall(wrapped, args) as Problem Radar uses it
	local okP, x, y = pcall(p:wrap("p", function(a) return a + 1, "y" end), 41)
	eq(okP, true); eq(x, 42); eq(y, "y")
end)

test("untimed instrument never touches a clock", function()
	local clockCalls = 0
	set_global("api", { type = { Clock = { new = function() clockCalls = clockCalls + 1; error("no clock here") end } } })
	local sq = load()
	local p = sq.new({ mod = MOD, ctx = "step", timed = false, paramKey = "sqperf_log" })
	eq(p.timer, "none")
	eq(p:start(), 0)
	eq(p:stop("poll", 0), 0)
	p:hit("poll")
	p:wrap("w", function() return 1 end)()
	eq(clockCalls, 0)
	eq(p.sec.poll.n, 2)
	eq(p.on, false, "paramKey is not read without a clock")
	eq(#lines(), 0)
	local saved = sq.WINDOW_MS
	sq.WINDOW_MS = 0 -- every hit closes a window
	local q = sq.new({ mod = MOD, ctx = "hud", timed = false, enabled = true })
	q:hit("icon"); q:hit("icon"); q:count("x", 2)
	sq.WINDOW_MS = saved
	local l = lines("win_ms")
	ok(#l >= 1)
	ok(l[#l]:find("timer=none") and l[#l]:find("| icon n=1"), l[#l])
	eq(clockCalls, 0)
end)

test("api.type.Clock is used when present (microseconds -> ms), os.clock otherwise", function()
	local us = 5000000
	set_global("api", { type = { Clock = { new = function()
		return { getTime = function() return us end }
	end } } })
	local sq = load()
	local p = sq.new({ mod = MOD, ctx = "gs" })
	eq(p.timer, "clock")
	local t0 = p:start()
	eq(t0, 5000)
	us = us + 75500
	eq(p:stop("x", t0), 75.5)
	ok(lines("slow=x max=75.5")[1] ~= nil)
	set_global("api", nil)
	local sq2 = load()
	eq(sq2.new({ mod = MOD, ctx = "gs" }).timer, "os.clock")
end)

test("hot path allocates nothing once a section exists (level 3 off and on)", function()
	local sq = load()
	local c = fakeClock()
	for _, value in ipairs({ 1, 2 }) do
		params(value)
		local p = sq.new({ mod = MOD, ctx = "gs", now = c.now, paramKey = "sqperf_log" })
		local f = p:wrap("w", function(a) return a end)
		local t = p:start(); p:stop("s", t); f(1); p:hit("h"); p:count("k")
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for i = 1, 20000 do
			local t0 = p:start()
			c.t = c.t + 0.001
			p:stop("s", t0)
			f(i)
			p:hit("h")
			p:count("k")
		end
		local grown = collectgarbage("count") - before
		collectgarbage("restart")
		ok(grown < 4, "grew " .. grown .. " KB with level 3 " .. (value == 2 and "on" or "off"))
	end
end)

test("overhead micro-benchmark (Lua 5.4 + os.clock; printed, loose bound)", function()
	set_global("api", nil)
	local sq = load()
	local p = sq.new({ mod = MOD, ctx = "gs" }) -- os.clock timer here (no api.type.Clock offline)
	local function work(x) return x + 1 end
	local wrapped = p:wrap("bench", work)
	local N = 200000
	local t = os.clock()
	for i = 1, N do work(i) end
	local plain = os.clock() - t
	t = os.clock()
	for i = 1, N do wrapped(i) end
	local timed = os.clock() - t
	t = os.clock()
	for i = 1, N do local t0 = p:start(); work(i); p:stop("bench2", t0) end
	local manual = os.clock() - t
	t = os.clock()
	for i = 1, N do p:hit("bench3"); work(i) end
	local hit = os.clock() - t
	-- bookkeeping alone: a timer that costs ~nothing (the game's Clock:getTime replaces os.clock)
	local zero = 0
	local q = sq.new({ mod = MOD, ctx = "gs", now = function() return zero end })
	local wrappedQ = q:wrap("bench", work)
	t = os.clock()
	for i = 1, N do wrappedQ(i) end
	local book = os.clock() - t
	t = os.clock()
	for _ = 1, N do os.clock() end
	local oneClock = os.clock() - t
	local function us(x) return string.format("%.3f", (x - plain) / N * 1e6) end
	print("overhead per call (us): wrap=" .. us(timed) .. " start/stop=" .. us(manual) .. " hit=" .. us(hit)
		.. " wrap-bookkeeping-only=" .. us(book) .. " one os.clock()=" .. string.format("%.3f", oneClock / N * 1e6)
		.. " (plain call " .. string.format("%.3f", plain / N * 1e6) .. " us)")
	ok((timed - plain) / N < 20e-6, "wrap overhead under 20 us per call")
end)
