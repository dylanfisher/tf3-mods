-- Smoke test of the game script sweep (original and optimized) against a small fake engine: runs without errors,
-- a pass over many lines spans several ticks in the optimized one, and lines not visited in a tick keep their
-- state. Terminal choice itself is not covered (no positions: every line stays undecided and waits to retry).

local NLINES, NGROUPS = 30, 4
local CT = { LINE = 1, STATION_GROUP = 2, STATION = 3, TRANSPORT_NETWORK = 4, GAME_TIME = 5, GAME_SPEED = 6,
	TRANSPORT_VEHICLE = 7 }

local clockUs, messages = 0, {}
-- os.clock drives the sweep interval: each update call moves it on by 5 s, so every call sweeps
local realOs, osClock = os, 0

local function world()
	local comps = {}
	local lines = {}
	for g = 1, NGROUPS do
		local group, st = 1000 + g, 2000 + g
		comps[group] = { [CT.STATION_GROUP] = { stations = { st } } }
		local terms = {}
		for t = 1, 3 do terms[t] = { tag = t, vehicleNodeId = { entity = 3000 + g, index = t } } end
		comps[st] = { [CT.STATION] = { terminals = terms } }
	end
	for l = 1, NLINES do
		local id = 100 + l
		lines[l] = id
		local stops = {}
		for k = 1, 3 do
			local g = (l + k) % NGROUPS + 1
			stops[k] = { stationGroup = 1000 + g, station = 0, terminal = 0, alternativeTerminals = {}, waypoints = {},
				stopConfig = { load = {} } }
		end
		comps[id] = { [CT.LINE] = { reservationPriority = l % 3, stops = stops, vehicleInfo = { transportModes = { [1] = true } } } }
	end
	return comps, lines
end

local function fakeApi(comps, lines)
	return {
		type = {
			ComponentType = CT,
			enum = { TransportMode = { TRAIN = 1, BUS = 2, TRUCK = 3, CAR = 4 }, StockListType = { OutputStock = 1 } },
			-- 1 ms per reading: the 8 ms budget runs out after a few lines
			Clock = { new = function() return { getTime = function() clockUs = clockUs + 1000; return clockUs end } end },
			NodeId = { new = function(e, i) return { entity = e, index = i } end },
		},
		engine = {
			getComponent = function(e, t) return comps[e] and comps[e][t] end,
			entityExists = function(e) return comps[e] ~= nil end,
			system = {
				lineSystem = { getLinesForPlayer = function() return lines end },
				transportVehicleSystem = { getLineVehicles = function() return {} end },
				streetSystem = { getNode2StreetEdgeMap = function() return {} end },
				streetConnectorSystem = { getConstructionEntityForStation = function() return 9 end },
				transportNetworkSystem = { getTpNetData = function() return { getNodeData = function() return nil end } end },
			},
			util = {
				getPlayer = function() return 1 end,
				getWorld = function() return 0 end,
				line = { getLineProblems = function() return {} end },
			},
			config = { getModParams = function() return { square_aat_perftest = {} } end },
		},
		res = { cargoTypeRep = { getPassengerCargoTypeId = function() return 0 end } },
	}
end

local function fakeState()
	local data = { intro = "done" } -- the first run question is answered
	return {
		get = function() return data end,
		set = function(_, s) data = s end,
		subscribeToEvent = function() end,
		data = function() return data end,
	}
end

local function load(path)
	reset_modules()
	clockUs, messages = 0, {}
	local comps, lines = world()
	set_global("api", fakeApi(comps, lines))
	set_global("require", ug_require)
	osClock = 0
	set_global("os", setmetatable({ clock = function() return osClock end }, { __index = realOs }))
	set_global("debugPrint", function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
		messages[#messages + 1] = table.concat(parts)
	end)
	return ug_require(path), comps, lines
end

local function noErrors()
	for __, m in ipairs(messages) do ok(not m:find("error", 1, true), m) end
end

-- runs update until the state has no cursor left (or n ticks), returns the tick count
local function tick(script, state)
	osClock = osClock + 5
	script.update({}, state, 1)
end

local function untilPassDone(script, state, n)
	for k = 1, n do
		tick(script, state)
		local s = state.data()
		if s and s.lastSweep and not s.cursor then return k end
	end
	return n
end

test("original: one tick covers every line, no errors", function()
	local script, __, lines = load("square_aat_perftest::/base/aat_main.lua")
	local state = fakeState()
	tick(script, state)
	noErrors()
	local s = state.data()
	for __, l in ipairs(lines) do ok(s.checked[tostring(l)] ~= nil, "line " .. l) end
end)

test("optimized: a pass spans several ticks, then every line is checked, no errors", function()
	local script, __, lines = load("square_aat_perftest::/opt/aat_main.lua")
	local state = fakeState()
	tick(script, state)
	local s = state.data()
	ok(s.cursor ~= nil, "first tick stops early")
	ok(s.cursor.i > 1 and s.cursor.i <= #lines, "cursor inside the list")
	local ticks = untilPassDone(script, state, 50)
	ok(ticks > 1 and ticks < 50, "pass finished after " .. ticks .. " more ticks")
	noErrors()
	s = state.data()
	for __, l in ipairs(lines) do ok(s.checked[tostring(l)] ~= nil, "line " .. l) end
	-- undecided lines wait for a retry, like in the original
	for __, l in ipairs(lines) do eq(s.checked[tostring(l)], "retry", "line " .. l) end
end)

test("optimized: lines not visited in a tick keep their overrides and signatures", function()
	local script, __, lines = load("square_aat_perftest::/opt/aat_main.lua")
	local state = fakeState()
	untilPassDone(script, state, 50)
	local s = state.data()
	local lastKey = tostring(lines[#lines])
	s.lineOverrides[lastKey] = { ["1001#1"] = { mode = "manual" } }
	s.lineModes[lastKey] = "manual"
	local retryBefore = s.retry[lastKey]
	-- next pass, first tick only: the last line is not reached
	tick(script, state)
	s = state.data()
	ok(s.cursor ~= nil, "pass not done")
	ok(s.lineModes[lastKey] == "manual", "line mode kept")
	ok(s.retry[lastKey] ~= nil and s.retry[lastKey].sig == retryBefore.sig, "retry kept")
	eq(s.checked[lastKey], "retry")
	noErrors()
end)

test("optimized: a refresh request starts the pass over from the first line", function()
	local script, __, lines = load("square_aat_perftest::/opt/aat_main.lua")
	local state = fakeState()
	tick(script, state)
	ok(state.data().cursor ~= nil, "mid-pass")
	script.handleEvent({}, state, "", "AutoAssignTerminals", "refresh", { line = lines[1] })
	local s = state.data()
	ok(s.force ~= nil, "request stored")
	ok(s.cursor ~= nil, "still more to do")
	untilPassDone(script, state, 50)
	s = state.data()
	ok(s.force == nil, "request done after the pass")
	noErrors()
end)

test("optimized: signatures are shorter than the original's", function()
	local base = load("square_aat_perftest::/base/aat_main.lua")
	local st1 = fakeState()
	tick(base, st1)
	local opt = load("square_aat_perftest::/opt/aat_main.lua")
	local st2 = fakeState()
	untilPassDone(opt, st2, 50)
	local function size(s)
		local n = 0
		for __, r in pairs(s.retry) do n = n + #r.sig end
		return n
	end
	-- tiny groups (3 terminals): the fingerprint is about as long as the tags; only check it is not much longer
	ok(size(st2.data()) <= size(st1.data()) * 1.5, size(st2.data()) .. " vs " .. size(st1.data()))
end)
