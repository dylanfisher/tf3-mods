-- SQPERF wiring of Supply Gaps (plans/sqperf/README.md): the game script times update / event, the
-- overlay times the whole tick and each stage of it (ctx tick), with SQPERF's default timer
-- (api.type.Clock, faked here) and the "Debug: performance log" param as the level 3 gate. The
-- module itself is tested in tests/square_problem_radar/test_sqperf.lua.
-- run_tests: no-split (each test reloads the modules)

local MOD = "square_supply_gaps"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_supply_gaps/"
local MOD_ROOT = here .. "../../mods/square_supply_gaps/"

local clockUs, debugOn, mapEditor

-- Fake api: a Clock (microseconds, clockUs) and getModParams with the debug param (2 = On).
local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return clockUs end } end },
			ComponentType = { GAME_SPEED = "GAME_SPEED" },
		},
		engine = {
			config = { getModParams = function()
				return { [""] = { isMapEditor = mapEditor }, [MOD] = { sqperf_log = debugOn and 2 or 1 } }
			end },
			util = { getWorld = function() return 1 end },
			getComponent = function() return { speedup = 1 } end,
		},
		gui = { mission = { setMarkerAtEntity = function() end, removeMarker = function() end } },
		res = { cargoTypeRep = { get = function(c) return { name = "C" .. c, icon = "" } end } },
	}
end

local function sqperfLines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern)) then out[#out + 1] = e.msg end
	end
	return out
end

before_each(function()
	clockUs, debugOn, mapEditor = 0, false, false
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
end)

-- An empty world; `lineUs` is how long the lines stage takes (advances the fake Clock).
local function loadOverlay(lineUs)
	local overlay = ug_require(MOD .. "::/supply_gaps/sg_overlay.tl")
	local gather = ug_require(MOD .. "::/supply_gaps/sg_gather.tl")
	local cache = ug_require(MOD .. "::/supply_gaps/sg_cache.tl")
	local scope = ug_require(MOD .. "::/supply_gaps/sg_scope.tl")
	gather.passengerCargo = function() return 0 end
	gather.lines = function()
		clockUs = clockUs + lineUs
		return {}, false
	end
	gather.unloadGroups = function() return {} end
	gather.groupStations = function() return {} end
	gather.buildingMap = function() return 0, {} end
	cache.engineFetch = function() return {} end
	overlay.readCamera = function()
		return { cx = 0, cy = 0, distance = 50, poly = scope.square(0, 0, 50), hits = 4, fallback = false }
	end
	overlay.setOn(true)
	return overlay
end

test("overlay: a slow stage and the tick are logged as slow calls with the debug param Off", function()
	local overlay = loadOverlay(20000) -- lines: 20 ms
	overlay.tick("timer")
	eq(overlay.ticks, 1)
	eq(#sqperfLines("ctx=tick .*slow=lines max=20%.0"), 1, "slow stage")
	eq(#sqperfLines("ctx=tick .*slow=tick max=20%.0"), 1, "slow tick")
	eq(#sqperfLines("phase=first"), 1, "first tick (>= 5 ms)")
	eq(#sqperfLines("win_ms="), 0, "no summary while Off")
end)

test("overlay: with the debug param On the 30 s summary lists the tick and every stage", function()
	debugOn = true
	local overlay = loadOverlay(100)
	for _ = 1, 3 do overlay.tick("timer") end
	clockUs = clockUs + 31e6
	overlay.tick("timer")
	local win = sqperfLines("ctx=tick .*win_ms=")
	eq(#win, 1, "one window summary")
	ok(win[1]:find("timer=clock", 1, true), win[1])
	ok(win[1]:find("| tick n=", 1, true), win[1])
	for _, stage in ipairs({ "lines", "catch", "map", "boxes", "scope", "read", "model", "markers", "labels" }) do
		ok(win[1]:find("| " .. stage .. " n=", 1, true), stage .. ": " .. win[1])
	end
	eq(#sqperfLines("slow="), 0, "fast ticks: no slow line")
end)

test("overlay: off ticks are not timed (nothing to report)", function()
	debugOn = true
	local overlay = loadOverlay(100)
	overlay.setOn(false)
	overlay.tick("timer")
	clockUs = clockUs + 31e6
	overlay.tick("timer")
	eq(#sqperfLines(), 0)
end)

local function fakeState()
	local st = { subs = nil }
	function st:get() return nil end
	function st:set(v) self.value = v end
	function st:hasEventSubscriptions() return self.subs ~= nil and next(self.subs) ~= nil end
	function st:subscribeToNoEvents() self.subs = {} end
	function st:subscribeToEvent(n) self.subs[n] = true end
	return st
end

test("game script: update and event are timed (ctx gs); summary with the debug param On", function()
	debugOn = true
	local script = ug_require(MOD .. "::/supply_gaps/sg_state.script.tl")
	local st = fakeState()
	script.update({}, st, 0.2)
	script.handleEvent({}, st, "", "SupplyGaps", "SupplyGaps.setOn", { on = true })
	clockUs = clockUs + 31e6
	script.update({}, st, 0.2)
	local win = sqperfLines("ctx=gs .*win_ms=")
	eq(#win, 1)
	ok(win[1]:find("| update n=", 1, true), win[1])
	ok(win[1]:find("| event n=1 ", 1, true), win[1])
	eq(st.value, { v = 1, on = true }, "behaviour unchanged")
end)

test("mod.json has the Debug: performance log param (Off default)", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	ok(s:find('"key": "sqperf_log"', 1, true))
	ok(s:find('"name": "Debug: performance log"', 1, true))
	ok(s:find('"defaultIndex": 0', 1, true))
end)
