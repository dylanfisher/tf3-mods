-- SQPERF wiring of the minimap (minimap_hud.script.tl): both instruments, the onStep one (perfStep,
-- ctx step) and the GUI one (perf, ctx gui), use SQPERF's default timer, api.type.Clock, one per Lua
-- state (safe in onStep, docs/findings.md "Timers and threads in GUI contexts"). Plus the mod.json
-- param.
-- The module itself is tested in tests/square_problem_radar/test_sqperf.lua.

local PATH = "square_better_minimap::/sqperf/square_better_minimap.lua"
local MOD = "square_better_minimap"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_better_minimap/"
local MOD_ROOT = here .. "../../mods/square_better_minimap/"

local clockMade, clockRead, clockUs

-- Fake api: a Clock (microseconds, clockUs) that counts its use, and getModParams with the debug
-- param at `value`.
local function fakeApi(value)
	clockMade, clockRead, clockUs = 0, 0, 0
	set_global("api", {
		type = { Clock = { new = function()
			clockMade = clockMade + 1
			return { getTime = function() clockRead = clockRead + 1; return clockUs end }
		end } },
		engine = { config = { getModParams = function()
			return { [MOD] = { sqperf_log = value } }
		end } },
	})
end

local function sqperfLines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern)) then out[#out + 1] = e.msg end
	end
	return out
end

before_each(function()
	clear_logs()
	reset_modules()
end)

test("step instrument (onStep work) times with the shared api.type.Clock", function()
	fakeApi(2) -- On
	local sq = ug_require(PATH)
	local gui = sq.new({ mod = MOD, ctx = "gui", paramKey = "sqperf_log", first = { "hud_render" } })
	local step = sq.new({ mod = MOD, ctx = "step", paramKey = "sqperf_log",
		first = { "map_gen", "industries_read" } })
	eq(gui.timer, "clock")
	eq(step.timed, true)
	eq(step.timer, "clock")
	eq(step.slowMs, 16)
	eq(clockMade, 1, "one Clock per Lua state, shared by both instruments")
	local t = step:start()
	clockUs = clockUs + 120000 -- makeMapFromGame: 120 ms
	near(step:stop("map_gen", t), 120, 1e-9)
	t = step:start()
	clockUs = clockUs + 4000
	step:stop("industries_read", t)
	for _ = 1, 50 do
		t = step:start()
		clockUs = clockUs + 200
		step:stop("cam_read", t)
		step:count("cam_moves")
	end
	clockUs = clockUs + 31e6 -- past the 30 s window
	t = step:start()
	step:stop("cam_read", t)
	ok(clockRead > 0, "Clock read")
	eq(#sqperfLines("ctx=step .*slow=map_gen max=120%.0"), 1, "slow map build logged")
	eq(#sqperfLines("phase=first ms=124%.0 map_gen=120%.0 industries_read=4%.0"), 1, "first build")
	local win = sqperfLines("ctx=step .*win_ms=")
	eq(#win, 1, "window summary with the debug param On")
	ok(win[1]:find("timer=clock", 1, true), win[1])
	ok(win[1]:find("cam_read n=51 ", 1, true), win[1])
	ok(win[1]:find("cam_moves c=50", 1, true), win[1])
end)

test("the script's instruments use the default timer (no now override)", function()
	local f = assert(io.open(MOD_ROOT .. "content/minimap/gui/minimap_hud.script.tl", "r"))
	local s = f:read("a")
	f:close()
	local n = 0
	for call in s:gmatch("sqperf%.new%((%b{})%)") do
		n = n + 1
		ok(not call:find("now%s*="), "no now override: " .. call)
		ok(not call:find("timed%s*="), "timed by default: " .. call)
	end
	eq(n, 2, "perf and perfStep")
end)

test("GUI instrument uses Clock; off by default: renders under 16 ms log nothing", function()
	fakeApi(1) -- Off
	local sq = ug_require(PATH)
	local gui = sq.new({ mod = MOD, ctx = "gui", paramKey = "sqperf_log", first = { "hud_render" } })
	eq(clockMade, 1)
	local render = gui:wrap("hud_render", function(a, b) return a, b, nil, "x" end)
	local r1, r2, r3, r4 = render(1, 2)
	eq(r1, 1); eq(r2, 2); eq(r3, nil); eq(r4, "x")
	ok(clockRead > 0, "Clock read")
	eq(#sqperfLines(), 0)
end)

test("mod.json has the Debug: performance log param, Off by default", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	local i = s:find('"key": "sqperf_log"', 1, true)
	ok(i, "key")
	local rest = s:sub(i)
	ok(rest:find('"name": "Debug: performance log"', 1, true), "name")
	ok(rest:find('"values": %[%s*"Off",%s*"On"%s*%]'), "values Off/On")
	ok(rest:find('"defaultIndex": 0', 1, true), "default Off")
	ok(s:find('"key": "showArrow"', 1, true), "existing param kept")
end)
