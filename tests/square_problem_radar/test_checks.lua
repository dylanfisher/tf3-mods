-- radar_checks: the pure Phase 2 checks (game-flag alerts), the Phase 3 checks (stuck / blocked-by /
-- old / idle) and their timers, the state merge and the v1/v2/v3 -> v4 migration (Phase 4 checks: test_line_quality.lua). Inputs are the plain tables radar.script.tl's gather layer builds
-- (radar_types.d.tl ProblemRadar*Input).

local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"

local function ids(alerts)
	local out = {}
	for i, a in ipairs(alerts) do out[i] = a.id end
	table.sort(out)
	return out
end

local function byId(alerts)
	local m = {}
	for _, a in ipairs(alerts) do m[a.id] = a end
	return m
end

local function line(name, owned, stops, vehicles)
	return { name = name, owned = owned ~= false, stops = stops or 3, vehicles = vehicles or 1 }
end

local function veh(name, owned, extra)
	local v = { name = name, owned = owned ~= false, etype = "Train", line = 50, lineName = "R2" }
	for k, x in pairs(extra or {}) do v[k] = x end
	return v
end

-- catalogue ------------------------------------------------------------------

test("catalogue: tab and tier per kind (PLAN alert catalogue)", function()
	local want = {
		veh_blocked = { "vehicles", 1 }, veh_nopath = { "vehicles", 1 },
		line_broken = { "lines", 1 }, line_no_vehicles = { "lines", 1 },
		line_cargo_issue = { "lines", 2 }, line_cargo_not_unloaded = { "lines", 2 }, station_overcrowded = { "stations", 2 },
		station_useless = { "stations", 3 }, fleet_worn = { "fleet", 3 },
		veh_stuck = { "vehicles", 1 }, train_blocked_by = { "vehicles", 2 },
		fleet_old = { "fleet", 3 }, fleet_idle_depot = { "fleet", 3 },
		line_overloaded = { "lines", 2 }, line_underused = { "lines", 3 }, line_bunching = { "lines", 2 },
		line_unprofitable = { "economy", 3 }, line_low_use = { "economy", 3 },
	}
	local n = 0
	for kind, k in pairs(checks.KINDS) do
		n = n + 1
		eq({ k.tab, k.tier }, want[kind], kind)
		local inGroup = false
		for _, g in ipairs(checks.GROUP_KINDS[k.group]) do inGroup = inGroup or g == kind end
		ok(inGroup, kind .. " listed in its group")
	end
	eq(n, 18)
	-- Phase 7: the economy kinds scale up to Critical; every other kind has a fixed tier.
	eq(checks.KINDS.line_unprofitable.maxTier, 1)
	eq(checks.KINDS.line_low_use.maxTier, 1)
	eq(checks.KINDS.line_underused.maxTier, nil)
	eq(checks.GROUPS, { "lines", "stations", "vehicles", "fleet" })
	eq(checks.WORN_THRESHOLD, 0.2)
	eq(checks.MAX_STORED_ALERTS, 300)
end)

-- lines ----------------------------------------------------------------------

test("lines: line_broken with relaxation reason and break position; ownership filtered", function()
	local out = checks.lines({
		lines = { [10] = line("R2"), [11] = line("Foreign", false), [12] = line("Few", true, 1, 0) },
		problems = {
			{ line = 10, code = "NO_PATH", pos = { 1, 2, 3 },
				okModes = { ELECTRIC_TRAIN = true }, relaxedModes = { TRAIN = true }, allowedModes = { ELECTRIC_TRAIN = true, TRAIN = true } },
			{ line = 10, code = "DOUBLE_STATIONS" }, -- second problem of the same line: ignored
			{ line = 11, code = "NO_PATH" },          -- not the player's line
			{ line = 12, code = "ZERO_OR_ONE_STATION" },
			{ line = 99, code = "NO_PATH" },          -- unknown line: ignored
			{ line = 12, code = "NOTHING" },
		},
	})
	eq(ids(out), { "line_broken:10", "line_broken:12" })
	local a = byId(out)["line_broken:10"]
	eq(a.kind, "line_broken")
	eq(a.tab, "lines")
	eq(a.tier, 1)
	eq(a.entity, 10)
	eq(a.etype, "Line")
	eq(a.label, "R2")
	eq(a.code, "NO_PATH")
	eq(a.arg, "Catenary")
	eq(a.pos, { 1, 2, 3 })
	local b = byId(out)["line_broken:12"]
	eq(b.arg, nil)
	eq(b.pos, nil)
end)

test("lines: line_no_vehicles needs >= 2 stops, 0 vehicles, owned, not broken", function()
	local out = checks.lines({
		lines = {
			[1] = line("Empty", true, 4, 0),
			[2] = line("One stop", true, 1, 0),
			[3] = line("Has vehicles", true, 4, 2),
			[4] = line("Foreign", false, 4, 0),
			[5] = line("Broken", true, 3, 0),
		},
		problems = { { line = 5, code = "NO_PATH" } },
	})
	eq(ids(out), { "line_broken:5", "line_no_vehicles:1" })
	local a = byId(out)["line_no_vehicles:1"]
	eq(a.tier, 1)
	eq(a.code, "NoVehicles")
	eq(a.arg, "4")
end)

test("lines: line_cargo_issue uses the first issue and counts the rest", function()
	local out = checks.lines({
		lines = { [7] = line("Coal"), [8] = line("Foreign", false) },
		issues = {
			[7] = { { code = "NowhereToUnload", stop = 1, cargo = "Coal" }, { code = "VehicleUseless", stop = -1 } },
			[8] = { { code = "NowhereToLoad", stop = 0 } },
		},
	})
	eq(ids(out), { "line_cargo_issue:7" })
	local a = out[1]
	eq(a.tier, 2)
	eq(a.tab, "lines")
	eq(a.code, "NowhereToUnload")
	eq(a.arg, "Coal")
	eq(a.metric, "+1")
end)

test("lines: line_cargo_not_unloaded groups round-trip vehicles into one row per line", function()
	local out = checks.lines({
		lines = { [7] = line("Coal"), [8] = line("Grain"), [9] = line("Foreign", false) },
		roundTrips = { [100] = 30, [101] = 12, [102] = 5.0, [103] = 9, [104] = 4, [105] = 0 },
		vehicleLines = { [100] = 7, [101] = 7, [102] = 8, [104] = 9, [105] = 8 },
	})
	eq(ids(out), { "line_cargo_not_unloaded:7", "line_cargo_not_unloaded:8" })
	local a = byId(out)["line_cargo_not_unloaded:7"]
	eq(a.kind, "line_cargo_not_unloaded")
	eq(a.tab, "lines")
	eq(a.tier, 2)
	eq(a.entity, 7)
	eq(a.etype, "Line")
	eq(a.label, "Coal")
	eq(a.code, "RoundTrip")
	eq(a.arg, "2|42")
	eq(a.metric, "2 veh · 42")
	local b = byId(out)["line_cargo_not_unloaded:8"]
	eq(b.arg, "1|5", "zero-count vehicle 105 ignored")
	eq(b.metric, "1 veh · 5")
end)

test("lines: line_cargo_not_unloaded skips vehicles without an owned line; nil inputs (kind off) are fine", function()
	local out = checks.lines({
		lines = { [7] = line("Coal"), [9] = line("Foreign", false) },
		roundTrips = { [100] = 30, [101] = 12, [102] = 3 },
		vehicleLines = { [101] = 9, [102] = 55 }, -- 100: no line / not owned; 101: foreign line; 102: unknown line
	})
	eq(ids(out), {})
	eq(ids(checks.lines({ lines = { [7] = line("Coal") }, roundTrips = { [100] = 3 } })), {})
	eq(ids(checks.lines({ lines = { [7] = line("Coal") }, vehicleLines = { [100] = 7 } })), {})
end)

test("lines: line_cargo_not_unloaded coexists with line_cargo_issue on the same line", function()
	local out = checks.lines({
		lines = { [7] = line("Coal") },
		issues = { [7] = { { code = "NowhereToUnload", stop = 1, cargo = "Coal" } } },
		roundTrips = { [100] = 8 },
		vehicleLines = { [100] = 7 },
	})
	eq(ids(out), { "line_cargo_issue:7", "line_cargo_not_unloaded:7" })
end)

test("relaxationType mirrors base line_util.getRelaxationType", function()
	local r = checks.relaxationType
	eq(r(nil, {}, {}), nil)
	eq(r({ ELECTRIC_TRAIN = true }, { TRAIN = true }, { TRAIN = true, ELECTRIC_TRAIN = true }), "Catenary")
	eq(r({ TRAM = true }, { BUS = true }, { TRAM = true }), "TramLanes")
	eq(r({ TRAIN = true }, {}, { TRAIN = true }), "Train")
	eq(r({ BUS = true }, {}, { BUS = true }), "Road")
	eq(r({ TRAM_TRACK = true }, {}, { TRAM_TRACK = true }), "TramTrack")
	eq(r({ TRAM_TRACK = true }, {}, { TRAM = true }), "TramLanes")
	eq(r({ BUS = true }, { BUS = true }, { BUS = true }), nil)
end)

-- stations -------------------------------------------------------------------

test("stations: overcrowded only when overflowing and served by a player line", function()
	local out = checks.stations({
		groups = {
			[20] = { name = "Central", owned = true, overflow = true, used = 412, capacity = 300 },
			[21] = { name = "Foreign", owned = false, overflow = true, used = 9, capacity = 1 },
			[22] = { name = "Calm", owned = true, overflow = false },
		},
	})
	eq(ids(out), { "station_overcrowded:20" })
	local a = out[1]
	eq(a.tier, 2)
	eq(a.tab, "stations")
	eq(a.etype, "Station")
	eq(a.label, "Central")
	eq(a.metric, "412/300")
end)

test("stations: station_useless per (station group, line, problem); player lines only", function()
	local out = checks.stations({
		lines = { [30] = line("Bus 4"), [31] = line("Foreign", false) },
		groups = { [40] = { name = "Market", owned = false, overflow = false } },
		lineStationProblems = {
			{ line = 30, stationGroup = 40, code = "CargoTypeLoadUseless" },
			{ line = 30, stationGroup = 40, code = "CargoTypeUnloadUseless" },
			{ line = 30, stationGroup = 40, code = "CargoTypeLoadUseless" }, -- duplicate
			{ line = 31, stationGroup = 40, code = "StopUseless" },
		},
	})
	eq(ids(out), { "station_useless:40:30:CargoTypeLoadUseless", "station_useless:40:30:CargoTypeUnloadUseless" })
	local a = out[1]
	eq(a.tier, 3)
	eq(a.entity, 40)
	eq(a.entity2, 30)
	eq(a.label, "Market")
	eq(a.context, "Bus 4")
end)

-- vehicles -------------------------------------------------------------------

test("vehicles: Blocked gives one alert per pair with the other train", function()
	local out = checks.vehicles({
		vehicles = { [5] = veh("IC 1"), [3] = veh("RE 7"), [8] = veh("Foreign A", false), [9] = veh("Foreign B", false) },
		problems = {
			{ vehicles = { 5, 3 }, code = "Blocked" },
			{ vehicles = { 3, 5 }, code = "Blocked" }, -- same pair again
			{ vehicles = { 8, 9 }, code = "Blocked" }, -- not ours
		},
	})
	eq(ids(out), { "veh_blocked:3:5" })
	local a = out[1]
	eq(a.tier, 1)
	eq(a.tab, "vehicles")
	eq(a.entity, 3)
	eq(a.entity2, 5)
	eq(a.label, "RE 7")
	eq(a.arg, "IC 1")
	eq(a.context, "R2")
	eq(a.etype, "Train")
end)

test("vehicles: NoPath* problems + getNoPathVehicles, deduplicated, with failure reason", function()
	local out = checks.vehicles({
		vehicles = { [1] = veh("Ferry", true, { etype = "Ship" }), [2] = veh("Loco"), [4] = veh("Theirs", false) },
		problems = {
			{ vehicles = { 1 }, code = "NoPathShip" },
			{ vehicles = { 4 }, code = "NoPathGeneric" },
		},
		noPath = { 2, 1, 4 },
		failures = { [2] = { reason = "NoElectric", pos = { 5, 6, 7 } }, [1] = { reason = nil, pos = { 0, 0, 0 } } },
	})
	eq(ids(out), { "veh_nopath:1", "veh_nopath:2" })
	local m = byId(out)
	eq(m["veh_nopath:1"].code, "NoPathShip")
	eq(m["veh_nopath:1"].etype, "Ship")
	eq(m["veh_nopath:1"].arg, nil)
	eq(m["veh_nopath:1"].pos, nil, "zero vector is no location")
	eq(m["veh_nopath:2"].code, "NoPath")
	eq(m["veh_nopath:2"].arg, "NoElectric")
	eq(m["veh_nopath:2"].pos, { 5, 6, 7 })
end)

-- fleet ----------------------------------------------------------------------

test("fleet: worn at <= 0.2, kept up to 0.3 once alerted (base hysteresis), owned only", function()
	local out = checks.fleet({
		vehicles = {
			[1] = veh("Old bus", true, { condition = 0.18, etype = "Bus" }),
			[2] = veh("Edge", true, { condition = 0.2 }),
			[3] = veh("Recovering", true, { condition = 0.25 }),
			[4] = veh("New alert?", true, { condition = 0.25 }),
			[5] = veh("Theirs", false, { condition = 0.1 }),
			[6] = veh("Repaired", true, { condition = 0.31 }),
		},
		prevIds = { ["fleet_worn:3"] = true, ["fleet_worn:6"] = true },
	})
	eq(ids(out), { "fleet_worn:1", "fleet_worn:2", "fleet_worn:3" })
	local a = byId(out)["fleet_worn:1"]
	eq(a.tier, 3)
	eq(a.tab, "fleet")
	eq(a.metric, "18%")
	eq(a.etype, "Bus")
	eq(a.context, "R2")
end)

test("fleet: worn threshold from the settings (Phase 5 wornPct) with its hysteresis", function()
	local function run(c, prev)
		return checks.fleet({ vehicles = { [1] = veh("T", true, { condition = c }) }, prevIds = prev or {},
			wornThreshold = 0.4, wornClear = 0.5 })
	end
	eq(#run(0.4), 1, "at the threshold")
	eq(#run(0.45), 0, "above it: no new alert")
	eq(#run(0.45, { ["fleet_worn:1"] = true }), 1, "kept up to threshold + 0.1")
	eq(#run(0.51, { ["fleet_worn:1"] = true }), 0)
	eq(#checks.fleet({ vehicles = { [1] = veh("T", true, { condition = 0.25 }) }, prevIds = {} }), 0, "default 0.2")
end)

-- merge ----------------------------------------------------------------------

local settingsMod = ug_require "square_problem_radar::/radar/radar_settings.tl"
local SETTINGS_DEFAULT = settingsMod.defaults()

local function settingsWith(over)
	local s = {}
	for k, v in pairs(SETTINGS_DEFAULT) do s[k] = v end
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function freshMemory()
	return { stoppedSince = {}, blockedSince = {}, blockedBy = {}, overloadSince = {}, underusedSince = {}, bunchingSince = {}, useAvg = {} }
end

local function alert(kind, key, firstSeen)
	local k = checks.KINDS[kind]
	return { id = kind .. ":" .. key, kind = kind, tab = k.tab, tier = k.tier, entity = 1, etype = "", label = "",
		context = "", code = "X", firstSeen = firstSeen or 0 }
end

-- A fresh state with smoothing off (smoothSec = 0): the pre-smoothing merge behaviour, which the
-- merge tests below pin down (smoothing has its own tests at the end of this file).
local function instantState()
	local s = checks.freshState()
	s.settings.smoothSec = 0
	return s
end

test("merge: firstSeen is set on first appearance and kept on later scans", function()
	local s = instantState()
	local s1, changed1 = checks.merge(s, "lines", { alert("line_broken", "1") }, 1000)
	ok(changed1)
	eq(s1.alerts[1].firstSeen, 1000)
	eq(s1.total, 1)
	eq(s1.kindCounts, { line_broken = 1 })

	local s2, changed2 = checks.merge(s1, "lines", { alert("line_broken", "1"), alert("line_no_vehicles", "2") }, 5000)
	ok(changed2)
	local m = byId(s2.alerts)
	eq(m["line_broken:1"].firstSeen, 1000)
	eq(m["line_no_vehicles:2"].firstSeen, 5000)

	local s3, changed3 = checks.merge(s2, "lines", { alert("line_broken", "1"), alert("line_no_vehicles", "2") }, 9000)
	eq(changed3, false, "same alert set: no state:set needed")
	eq(s3.alerts, s2.alerts)

	-- gone and back: a new firstSeen
	local s4 = checks.merge(s3, "lines", { alert("line_no_vehicles", "2") }, 10000)
	local s5 = checks.merge(s4, "lines", { alert("line_broken", "1"), alert("line_no_vehicles", "2") }, 11000)
	eq(byId(s5.alerts)["line_broken:1"].firstSeen, 11000)
end)

test("merge: only the scanned group is replaced; other groups' alerts stay", function()
	local s = checks.merge(instantState(), "fleet", { alert("fleet_worn", "9") }, 10)
	s = checks.merge(s, "lines", { alert("line_broken", "1") }, 20)
	eq(ids(s.alerts), { "fleet_worn:9", "line_broken:1" })
	s = checks.merge(s, "lines", {}, 30)
	eq(ids(s.alerts), { "fleet_worn:9" })
	eq(s.kindCounts, { fleet_worn = 1 })
	eq(s.total, 1)
	-- an alert of another group's kind in `fresh` is ignored
	s = checks.merge(s, "lines", { alert("fleet_worn", "77") }, 40)
	eq(ids(s.alerts), { "fleet_worn:9" })
end)

test("merge: sorted by tier then firstSeen; capped with an overflow count", function()
	local fresh = {}
	for i = 1, 5 do fresh[#fresh + 1] = alert("fleet_worn", tostring(i)) end
	local s = checks.merge(instantState(), "fleet", fresh, 100, 3)
	s = checks.merge(s, "lines", { alert("line_cargo_issue", "a"), alert("line_broken", "b") }, 200, 3)
	eq(#s.alerts, 3)
	eq(s.alerts[1].id, "line_broken:b")
	eq(s.alerts[2].id, "line_cargo_issue:a")
	eq(s.alerts[3].kind, "fleet_worn")
	eq(s.total, 7)
	eq(s.kindCounts, { fleet_worn = 5, line_broken = 1, line_cargo_issue = 1 })
end)

test("merge: carries settings; plain values only (no functions/userdata)", function()
	local s = checks.freshState()
	s.settings = settingsWith({ hudMode = "compact" })
	s.memory.stoppedSince[7] = 100
	local m = checks.merge(s, "vehicles", { alert("veh_nopath", "3") }, 1)
	eq(m.settings, settingsWith({ hudMode = "compact" }))
	eq(m.version, 6)
	eq(m.memory.stoppedSince, { [7] = 100 }, "memory carried over")
	local mem = { stoppedSince = { [8] = 5 }, blockedSince = {}, blockedBy = {} }
	local m2 = checks.merge(s, "vehicles", {}, 2, nil, mem)
	eq(m2.memory, mem, "memory replaced when given")
	local function plain(v, depth)
		local t = type(v)
		if t == "table" then
			for k, x in pairs(v) do
				ok(type(k) == "string" or type(k) == "number", "plain key")
				plain(x, depth + 1)
			end
		else
			ok(t == "string" or t == "number" or t == "boolean", "plain value: " .. t)
		end
	end
	plain(m, 0)
end)

test("merge: count changes alone (over the cap) count as a change", function()
	local s = checks.merge(instantState(), "lines", { alert("line_broken", "1") }, 1, 1)
	local s2, changed = checks.merge(s, "fleet", { alert("fleet_worn", "2") }, 2, 1)
	ok(changed)
	eq(#s2.alerts, 1)
	eq(s2.total, 2)
	local _, again = checks.merge(s2, "fleet", { alert("fleet_worn", "2") }, 3, 1)
	eq(again, false)
end)

-- state migration ---------------------------------------------------------------

local function v6(over)
	local st = { version = 6, settings = SETTINGS_DEFAULT, alerts = {}, total = 0, kindCounts = {}, memory = freshMemory(),
		notified = {}, notifyCleared = {}, tierCounts = { 0, 0, 0 } }
	for k, v in pairs(over or {}) do st[k] = v end
	return st
end

test("upgradeState: nil / garbage give a fresh v6 state", function()
	for _, v in ipairs({ false, "x", 3 }) do
		local s, changed = checks.upgradeState(v ~= false and v or nil)
		eq(s, v6())
		ok(changed)
	end
	eq(checks.STATE_VERSION, 6)
end)

test("upgradeState: v1 -> v6 keeps settings, drops old alerts, adds total/kindCounts/memory/notify maps", function()
	local v1 = { version = 1, settings = { hudMode = "compact" }, alerts = { { id = "old", tier = 1 } } }
	local s, changed = checks.upgradeState(v1)
	ok(changed)
	eq(s, v6({ settings = settingsWith({ hudMode = "compact" }) }))
	eq(v1.version, 1, "input not mutated")
end)

test("upgradeState: v2 -> v6 keeps alerts and counts (same alert schema), adds default settings + memory", function()
	local a = alert("line_broken", "1", 5)
	local v2 = { version = 2, settings = { hudMode = "compact" }, alerts = { a }, total = 1, kindCounts = { line_broken = 1 } }
	local s, changed = checks.upgradeState(v2)
	ok(changed, "version bump is saved once")
	eq(s, v6({ settings = settingsWith({ hudMode = "compact" }), alerts = { a }, total = 1, kindCounts = { line_broken = 1 },
		tierCounts = { 1, 0, 0 } }))
	eq(v2.version, 2, "input not mutated")
	eq(v2.memory, nil)
	local _, again = checks.upgradeState(s)
	eq(again, false, "stable after migration")
end)

test("upgradeState: v3 -> v6 keeps alerts, settings and vehicle timers; adds line timers", function()
	local a = alert("veh_stuck", "7", 5)
	local v3mem = { stoppedSince = { [7] = 100.0 }, blockedSince = { [8] = 50 }, blockedBy = { [8] = 9 } }
	local v3settings = { hudMode = "badge", stuckMinRail = 4 }
	local v3 = { version = 3, settings = v3settings, alerts = { a }, total = 1, kindCounts = { veh_stuck = 1 }, memory = v3mem }
	local s, changed = checks.upgradeState(v3)
	ok(changed, "saved once as v6")
	eq(s.version, 6)
	eq(s.alerts, { a })
	eq(s.kindCounts, { veh_stuck = 1 })
	eq(s.settings, settingsWith({ stuckMinRail = 4 }), "new settings get defaults")
	eq(s.memory, { stoppedSince = { [7] = 100.0 }, blockedSince = { [8] = 50 }, blockedBy = { [8] = 9 },
		overloadSince = {}, underusedSince = {}, bunchingSince = {}, useAvg = {} })
	eq(s.notified, {})
	eq(s.notifyCleared, {})
	eq(v3mem.overloadSince, nil, "v3 memory not mutated")
	local _, again = checks.upgradeState(s)
	eq(again, false, "stable after migration")
	local s2 = checks.upgradeState({ version = 3, settings = SETTINGS_DEFAULT, alerts = {}, total = 0, kindCounts = {}, memory = "x" })
	eq(s2.memory, freshMemory(), "broken v3 memory -> fresh")
end)

test("upgradeState: v4 -> v6 keeps every timer, drops lineCursor, adds notify maps and Phase 5 settings", function()
	local a = alert("line_overloaded", "3", 5)
	local v4mem = { stoppedSince = { [7] = 100 }, blockedSince = {}, blockedBy = {}, overloadSince = { [3] = 40.0 },
		underusedSince = { [4] = 1 }, bunchingSince = {}, lineCursor = 3.0 }
	local v4settings = { hudMode = "compact", stuckMinRoad = 3, stuckMinTram = 3, stuckMinRail = 5, stuckMinWater = 10,
		stuckMinAir = 5, idleDepotDays = 30, lineOverloadFactor = 4, lineUnderusedPct = 10, lineClumpPct = 20,
		lineGapPct = 300, lineSustainMin = 10 }
	local v4 = { version = 4, settings = v4settings, alerts = { a }, total = 1, kindCounts = { line_overloaded = 1 }, memory = v4mem }
	local s, changed = checks.upgradeState(v4)
	ok(changed, "saved once as v6")
	eq(s, v6({ settings = settingsWith({ hudMode = "compact", lineOverloadFactor = 4 }), alerts = { a }, total = 1,
		kindCounts = { line_overloaded = 1 }, tierCounts = { 0, 1, 0 },
		memory = { stoppedSince = { [7] = 100 }, blockedSince = {}, blockedBy = {}, overloadSince = { [3] = 40.0 },
			underusedSince = { [4] = 1 }, bunchingSince = {}, useAvg = {} } }))
	eq(s.settings.notify.veh_stuck, "notify", "notify defaults")
	eq(s.settings.wornPct, 20)
	eq(s.settings.notifyPaused, false)
	eq(v4mem.lineCursor, 3.0, "v4 memory not mutated")
	local _, again = checks.upgradeState(s)
	eq(again, false, "stable after migration")
	-- v4 with v3-shaped memory keeps the vehicle timers
	local s2 = checks.upgradeState({ version = 4, settings = v4settings, alerts = {}, total = 0, kindCounts = {},
		memory = { stoppedSince = { [1] = 2 }, blockedSince = {}, blockedBy = {} } })
	eq(s2.memory.stoppedSince, { [1] = 2 })
	eq(s2.memory.overloadSince, {})
end)

test("upgradeState: a current v6 state is kept as is (floats from a save included)", function()
	local a = alert("line_broken", "1", 5)
	local mem = freshMemory()
	mem.stoppedSince[12] = 100.0
	mem.overloadSince[3] = 40.0
	local notified = { ["line_broken:1"] = 5.0 }
	local st = v6({ version = 6.0, settings = settingsWith({ stuckMinRail = 4.0, lineSustainMin = 2.0 }), alerts = { a },
		total = 1.0, kindCounts = { line_broken = 1 }, memory = mem, notified = notified })
	local s, changed = checks.upgradeState(st)
	eq(changed, false)
	eq(s.alerts[1], a)
	eq(s.total, 1)
	eq(s.settings.stuckMinRail, 4)
	ok(s.memory == mem, "memory kept by reference (no per-scan copy)")
	ok(s.notified == notified, "notified kept by reference")
	-- partial v5: missing total is recomputed and saved
	local s2, changed2 = checks.upgradeState(v6({ alerts = { a }, total = "x" }))
	ok(changed2)
	eq(s2.total, 1)
	-- broken memory or a leftover lineCursor is replaced and saved
	local s3, changed3 = checks.upgradeState(v6({ memory = { stoppedSince = {}, blockedSince = {}, blockedBy = {} } }))
	ok(changed3)
	eq(s3.memory, freshMemory())
	local withCursor = freshMemory()
	withCursor.lineCursor = 4
	withCursor.stoppedSince[1] = 9
	local s3b, changed3b = checks.upgradeState(v6({ memory = withCursor }))
	ok(changed3b)
	eq(s3b.memory.stoppedSince, { [1] = 9 })
	eq(s3b.memory.lineCursor, nil)
	-- missing notify maps are added and saved
	local s4, changed4 = checks.upgradeState(v6({ notified = "x", notifyCleared = nil }))
	ok(changed4)
	eq(s4.notified, {})
	eq(s4.notifyCleared, {})
	-- settings missing a key are saved normalised
	local _, changed5 = checks.upgradeState(v6({ settings = { hudMode = "badge" } }))
	ok(changed5)
end)

test("merge on a v1 state migrates it", function()
	local s, changed = checks.merge({ version = 1, settings = { hudMode = "compact" }, alerts = {} }, "fleet", {}, 1)
	eq(changed, false, "no alert change; radar.script.tl scanGroup saves the migration itself (upgraded)")
	eq(s.version, 6)
	eq(s.settings, settingsWith({ hudMode = "compact" }))
	eq(s.total, 0)
	eq(s.memory, freshMemory())
	eq(s.notified, {})
end)

test("merge carries the notify maps", function()
	local st = v6({ notified = { ["line_broken:1"] = 5 }, notifyCleared = { ["veh_stuck:2"] = 9 } })
	local s = checks.merge(st, "lines", { alert("line_broken", "1") }, 10)
	eq(s.notified, { ["line_broken:1"] = 5 })
	eq(s.notifyCleared, { ["veh_stuck:2"] = 9 })
end)

test("patchMemory: copy with fields replaced; other timers untouched; input not mutated", function()
	local m = freshMemory()
	m.overloadSince[5] = 10
	local p = checks.patchMemory(m, { stoppedSince = { [1] = 2 } })
	eq(p.stoppedSince, { [1] = 2 })
	eq(p.overloadSince, { [5] = 10 })
	eq(m.stoppedSince, {}, "input not mutated")
	eq(p.useAvg, {}, "Phase 7 useAvg is part of every memory")
	eq(checks.patchMemory(nil, nil), freshMemory())
end)

-- Phase 3: timers ------------------------------------------------------------------

local MIN = 60000

test("updateStopped: timer starts, continues, resets when the vehicle moves", function()
	local m, changed = checks.updateStopped({}, { [1] = "ROAD", [2] = "RAIL" }, 1000)
	eq(m, { [1] = 1000, [2] = 1000 })
	ok(changed)
	local m2, changed2 = checks.updateStopped(m, { [1] = "ROAD", [2] = "RAIL" }, 5000)
	eq(m2, { [1] = 1000, [2] = 1000 }, "continues: start time kept")
	eq(changed2, false)
	local m3, changed3 = checks.updateStopped(m2, { [2] = "RAIL" }, 9000)
	eq(m3, { [2] = 1000 }, "vehicle 1 moved (or no longer exists): pruned")
	ok(changed3)
	local m4 = checks.updateStopped(m3, { [1] = "ROAD", [2] = "RAIL" }, 12000)
	eq(m4[1], 12000, "standing again: a new timer")
end)

test("updateStopped: floats / garbage from a save; future times clamp to now", function()
	local m, changed = checks.updateStopped({ [3] = 500.0, [4] = "x", [5] = 99999 }, { [3] = "AIR", [4] = "AIR", [5] = "AIR" }, 1000)
	eq(m, { [3] = 500, [4] = 1000, [5] = 1000 })
	ok(changed)
	local _, changed2 = checks.updateStopped({ [3] = 500.0 }, { [3] = "AIR" }, 1000)
	eq(changed2, false, "500.0 == 500")
	local _, changed3 = checks.updateStopped(nil, {}, 1)
	eq(changed3, true, "nil memory: an empty map is still saved")
end)

test("updateStopped: capped, keeping the oldest timers", function()
	local prev = { [10] = 300, [11] = 100, [12] = 200, [13] = 100 }
	local m = checks.updateStopped(prev, { [10] = "ROAD", [11] = "ROAD", [12] = "ROAD", [13] = "ROAD", [14] = "ROAD" }, 1000, 3)
	eq(m, { [11] = 100, [12] = 200, [13] = 100 })
	eq(checks.MAX_STOPPED_TIMERS, 500)
end)

test("updateBlocked: pair timer kept while the same blocker blocks; restarts on a new blocker; pruned", function()
	local since, by, changed = checks.updateBlocked({}, {}, { { 1, 2 }, { 3, 4 } }, 1000)
	eq(since, { [1] = 1000, [3] = 1000 })
	eq(by, { [1] = 2, [3] = 4 })
	ok(changed)
	local since2, by2, changed2 = checks.updateBlocked(since, by, { { 1, 2 }, { 3, 4 } }, 5000)
	eq(since2, { [1] = 1000, [3] = 1000 })
	eq(changed2, false)
	local since3, by3 = checks.updateBlocked(since2, by2, { { 1, 9 } }, 7000)
	eq(since3, { [1] = 7000 }, "new blocker restarts; train 3 no longer blocked is pruned")
	eq(by3, { [1] = 9 })
	-- several blockers for one train: the lowest id; self-pairs ignored
	local s4, b4 = checks.updateBlocked({}, {}, { { 5, 8 }, { 5, 6 }, { 7, 7 } }, 1)
	eq(b4, { [5] = 6 })
	eq(s4, { [5] = 1 })
end)

test("updateBlocked: capped (oldest kept), blockedBy follows", function()
	local since, by = checks.updateBlocked({ [1] = 10, [2] = 5, [3] = 20 }, { [1] = 11, [2] = 12, [3] = 13 },
		{ { 1, 11 }, { 2, 12 }, { 3, 13 } }, 100, 2)
	eq(since, { [1] = 10, [2] = 5 })
	eq(by, { [1] = 11, [2] = 12 })
end)

test("save churn: only timers at least PERSIST_TIMER_AFTER_MS old are saved; blockedBy follows", function()
	eq(checks.PERSIST_TIMER_AFTER_MS, 30000)
	local since = { [1] = 1000, [2] = 20000, [3] = 31000 }
	eq((checks.agedTimers(since, 31000, 30000)), { [1] = 1000 }, "only 30 s and older")
	local s2, b2 = checks.agedTimers(since, 51000, 30000, { [1] = 7, [2] = 8, [3] = 9 })
	eq(s2, { [1] = 1000, [2] = 20000 })
	eq(b2, { [1] = 7, [2] = 8 })
	eq((checks.agedTimers(nil, 1, 1)), {})
	ok(checks.sameTimerMap({ [1] = 1000 }, { [1] = 1000.0 }))
	ok(not checks.sameTimerMap({ [1] = 1000 }, { [1] = 1000, [2] = 5 }))
end)

test("save churn: withYoungTimers = saved timers + live ones that were too young to be saved", function()
	local saved, savedBy = { [1] = 1000 }, { [1] = 7 }
	local live, liveBy = { [1] = 1000, [2] = 40000, [3] = 5000, [4] = 99999 }, { [1] = 7, [2] = 8, [3] = 9, [4] = 10 }
	local s, b = checks.withYoungTimers(saved, savedBy, live, liveBy, 50000, 52400, 30000)
	eq(s, { [1] = 1000, [2] = 40000 }, "3 was old (so saved, then dropped there): not restored; 4 is after liveAt")
	eq(b, { [1] = 7, [2] = 8 })
	local s2, b2 = checks.withYoungTimers(nil, nil, { [5] = 10 }, nil, 20, 20, 30000)
	eq(s2, { [5] = 10 })
	eq(b2, {})
	-- after a load: no live timers (liveAt nil), or live ones from a later game time (an older save)
	eq((checks.withYoungTimers({ [6] = 3.0 }, nil, {}, nil, nil, 9, 30000)), { [6] = 3.0 })
	eq((checks.withYoungTimers({ [6] = 3 }, nil, { [7] = 50 }, nil, 60, 9, 30000)), { [6] = 3 })
end)

test("save churn: a vehicle standing a few seconds does not change the saved timers", function()
	local P = 30000
	-- pass at 40 s: vehicle 1 has stood 40 s (saved); vehicle 2 starts standing
	local saved = { [1] = 0 }
	local prev = checks.withYoungTimers(saved, nil, { [1] = 0 }, nil, 37600, 40000, P)
	local full = checks.updateStopped(prev, { [1] = true, [2] = true }, 40000)
	eq(full, { [1] = 0, [2] = 40000 })
	ok(checks.sameTimerMap(checks.agedTimers(full, 40000, P), saved), "unchanged: no state:set")
	-- next pass (2.4 s later): the young timer survives; vehicle 2 moves again
	prev = checks.withYoungTimers(saved, nil, full, nil, 40000, 42400, P)
	eq(prev, { [1] = 0, [2] = 40000 })
	full = checks.updateStopped(prev, { [1] = true }, 42400)
	ok(checks.sameTimerMap(checks.agedTimers(full, 42400, P), saved), "still unchanged")
	-- vehicle 3, young at the last pass, crosses the threshold before this one: kept and now saved
	prev = checks.withYoungTimers(saved, nil, { [1] = 0, [3] = 40000 }, nil, 67600, 70000, P)
	eq(prev, { [1] = 0, [3] = 40000 })
	full = checks.updateStopped(prev, { [1] = true, [3] = true }, 70000)
	local aged = checks.agedTimers(full, 70000, P)
	eq(aged, { [1] = 0, [3] = 40000 })
	ok(not checks.sameTimerMap(aged, saved), "a change: saved once")
end)

test("chainRoot: follows blockers; cycles give their lowest id", function()
	local by = { [1] = 2, [2] = 3, [5] = 6, [6] = 5, [7] = 5, [9] = 10, [10] = 11, [11] = 10 }
	eq(checks.chainRoot(by, 1), 3)
	eq(checks.chainRoot(by, 3), 3)
	eq(checks.chainRoot(by, 7), 5)
	eq(checks.chainRoot(by, 6), 5)
	eq(checks.chainRoot(by, 9), 10)
end)

test("formatMinutes", function()
	eq(checks.formatMinutes(0), "0m")
	eq(checks.formatMinutes(12 * MIN + 59999), "12m")
	eq(checks.formatMinutes(125 * MIN), "2h05m")
end)

-- Phase 3: veh_stuck -------------------------------------------------------------

local THRESH = { ROAD = 3 * MIN, TRAM = 3 * MIN, RAIL = 5 * MIN, WATER = 10 * MIN, AIR = 5 * MIN }

local function stuckInput(over)
	local input = {
		now = 100 * MIN,
		thresholds = THRESH,
		standing = {},
		stoppedSince = {},
		blockedSince = {},
		blockedBy = {},
		vehicles = {},
		excluded = {},
	}
	for k, v in pairs(over or {}) do input[k] = v end
	return input
end

test("veh_stuck: threshold per carrier", function()
	local now = 100 * MIN
	local standing, since, vehicles = {}, {}, {}
	local cases = {
		{ 1, "ROAD", 3 }, { 2, "ROAD", 2 }, { 3, "TRAM", 3 }, { 4, "RAIL", 5 }, { 5, "RAIL", 4 },
		{ 6, "WATER", 10 }, { 7, "WATER", 9 }, { 8, "AIR", 5 }, { 9, "AIR", 4 }, { 10, "OTHER", 99 },
	}
	for _, c in ipairs(cases) do
		standing[c[1]] = { carrier = c[2] }
		since[c[1]] = now - c[3] * MIN
		vehicles[c[1]] = veh("V" .. c[1], true, { etype = c[2] })
	end
	local out = checks.stuck(stuckInput({ standing = standing, stoppedSince = since, vehicles = vehicles }))
	eq(ids(out), { "veh_stuck:1", "veh_stuck:3", "veh_stuck:4", "veh_stuck:6", "veh_stuck:8" })
	local a = byId(out)["veh_stuck:6"]
	eq(a.tier, 1)
	eq(a.tab, "vehicles")
	eq(a.code, "WATER")
	eq(a.metric, "10m")
	eq(a.context, "R2")
end)

test("veh_stuck: next stop as arg; ownership, exclusions, queueing, blocked trains", function()
	local now = 100 * MIN
	local old = now - 30 * MIN
	local out = checks.stuck(stuckInput({
		standing = {
			[1] = { carrier = "ROAD", nextStop = "Market" },
			[2] = { carrier = "ROAD" },                         -- not ours
			[3] = { carrier = "RAIL" },                         -- already veh_blocked / veh_nopath
			[4] = { carrier = "WATER", queueing = true },        -- harbour queue
			[5] = { carrier = "RAIL" },                         -- in a blocked pair -> train_blocked_by
			[6] = { carrier = "ROAD", nextStop = "" },
			[7] = { carrier = "ROAD" },                         -- no timer
		},
		stoppedSince = { [1] = old, [2] = old, [3] = old, [4] = old, [5] = old, [6] = old },
		blockedBy = { [5] = 99 },
		vehicles = { [1] = veh("Bus 1"), [2] = veh("Theirs", false), [3] = veh("T3"), [4] = veh("Ferry"),
			[5] = veh("T5"), [6] = veh("Bus 6"), [7] = veh("Bus 7") },
		excluded = { [3] = true },
	}))
	eq(ids(out), { "veh_stuck:1", "veh_stuck:6" })
	eq(byId(out)["veh_stuck:1"].arg, "Market")
	eq(byId(out)["veh_stuck:6"].arg, nil, "empty next stop is no arg")
	eq(byId(out)["veh_stuck:1"].metric, "30m")
end)

test("veh_stuck: a train waiting for a free path goes to train_blocked_by (no blocker)", function()
	local now = 100 * MIN
	local out = checks.stuck(stuckInput({
		standing = { [4] = { carrier = "RAIL", waitingForPath = true, nextStop = "Central" } },
		stoppedSince = { [4] = now - 6 * MIN },
		vehicles = { [4] = veh("IC 4") },
	}))
	eq(ids(out), { "train_blocked_by:w4" })
	local a = out[1]
	eq(a.tier, 2)
	eq(a.code, "WaitingForPath")
	eq(a.entity, 4)
	eq(a.entity2, nil)
	eq(a.arg, "Central")
	eq(a.metric, "6m")
end)

-- Phase 3: train_blocked_by ----------------------------------------------------

test("train_blocked_by: only after the rail threshold; entity = blocked, entity2 = blocker", function()
	local now = 100 * MIN
	local vehicles = { [1] = veh("RE 1"), [2] = veh("IC 2"), [3] = veh("RE 3"), [4] = veh("IC 4") }
	local out = checks.stuck(stuckInput({
		blockedBy = { [1] = 2, [3] = 4 },
		blockedSince = { [1] = now - 5 * MIN, [3] = now - 4 * MIN },
		vehicles = vehicles,
	}))
	eq(ids(out), { "train_blocked_by:2" })
	local a = out[1]
	eq(a.entity, 1)
	eq(a.entity2, 2)
	eq(a.arg, "IC 2")
	eq(a.code, "BlockedBy")
	eq(a.metric, "5m")
	eq(a.label, "RE 1")
end)

test("train_blocked_by: chains collapse to one row per root, with the queue count", function()
	local now = 100 * MIN
	local old = now - 20 * MIN
	-- 1 behind 2 behind 3 (root); 4 also behind 3; 5 behind 6 (separate chain); 7 foreign
	local out = checks.stuck(stuckInput({
		blockedBy = { [1] = 2, [2] = 3, [4] = 3, [5] = 6, [7] = 6 },
		blockedSince = { [1] = old, [2] = old + MIN, [4] = old, [5] = old, [7] = old },
		vehicles = { [1] = veh("A"), [2] = veh("B"), [3] = veh("C"), [4] = veh("D"), [5] = veh("E"), [6] = veh("F"),
			[7] = veh("Theirs", false) },
	}))
	eq(ids(out), { "train_blocked_by:3", "train_blocked_by:6" })
	local m = byId(out)
	-- direct followers of 3 are 2 and 4; 4 has waited longer
	eq(m["train_blocked_by:3"].entity, 4)
	eq(m["train_blocked_by:3"].entity2, 3)
	eq(m["train_blocked_by:3"].metric, "20m +2")
	eq(m["train_blocked_by:6"].entity, 5)
	eq(m["train_blocked_by:6"].metric, "20m", "foreign train not counted")
end)

test("train_blocked_by: deadlock cycles the game flags are excluded; unflagged cycles give one row", function()
	local now = 100 * MIN
	local old = now - 20 * MIN
	local vehicles = { [1] = veh("A"), [2] = veh("B"), [3] = veh("C"), [4] = veh("D") }
	local flagged = checks.stuck(stuckInput({
		blockedBy = { [1] = 2, [2] = 1 },
		blockedSince = { [1] = old, [2] = old },
		vehicles = vehicles,
		excluded = { [1] = true, [2] = true },
	}))
	eq(ids(flagged), {})
	local cycle = checks.stuck(stuckInput({
		blockedBy = { [3] = 4, [4] = 3 },
		blockedSince = { [3] = old, [4] = old },
		vehicles = vehicles,
	}))
	eq(ids(cycle), { "train_blocked_by:3" })
	eq(cycle[1].entity, 4)
	eq(cycle[1].entity2, 3)
	eq(cycle[1].metric, "20m +1")
	-- only the root qualifies: the root itself, blocked by its own blocker
	local rootOnly = checks.stuck(stuckInput({
		blockedBy = { [3] = 4, [4] = 3 },
		blockedSince = { [3] = old, [4] = now },
		vehicles = vehicles,
	}))
	eq(rootOnly[1].entity, 3)
	eq(rootOnly[1].entity2, 4)
end)

-- Phase 3: fleet_old / fleet_idle_depot ------------------------------------------

local YEAR = 1460000

test("fleet_old: age > lifespan; lifespan 0 never old; metric percent, arg years", function()
	local out = checks.fleet({
		vehicles = {
			[1] = veh("Old", true, { ageMs = 23 * YEAR + 100, lifespanMs = 20 * YEAR }),
			[2] = veh("Exactly", true, { ageMs = 20 * YEAR, lifespanMs = 20 * YEAR }),
			[3] = veh("Young", true, { ageMs = YEAR, lifespanMs = 20 * YEAR }),
			[4] = veh("No lifespan", true, { ageMs = 50 * YEAR, lifespanMs = 0 }),
			[5] = veh("Theirs", false, { ageMs = 50 * YEAR, lifespanMs = YEAR }),
		},
		yearMs = YEAR,
	})
	eq(ids(out), { "fleet_old:1" })
	local a = out[1]
	eq(a.tier, 3)
	eq(a.tab, "fleet")
	eq(a.code, "Old")
	eq(a.arg, "23/20")
	eq(a.metric, "115%")
	eq(a.context, "R2")
end)

test("fleet_old: alerts of vehicles not read this pass are kept; read ones are re-decided", function()
	local function oldAlert(v) return { id = "fleet_old:" .. v, kind = "fleet_old", tab = "fleet", tier = 3, entity = v,
		etype = "Bus", label = "B" .. v, context = "", code = "Old", arg = "21/20", metric = "105%", firstSeen = 7 } end
	local keep = { oldAlert(1), oldAlert(2), { id = "fleet_worn:3", kind = "fleet_worn", entity = 3 } }
	local out = checks.fleet({
		vehicles = { [2] = veh("Renewed", true, { ageMs = 1, lifespanMs = 20 * YEAR }) },
		keepOld = keep,
		yearMs = YEAR,
	})
	eq(ids(out), { "fleet_old:1" })
	ok(out[1] ~= keep[1], "a copy, not the old state's table")
	eq(out[1].arg, "21/20")
end)

test("fleet_idle_depot: daysInDepot >= setting; depot name as context", function()
	local out = checks.fleet({
		vehicles = {
			[1] = veh("Parked", true, { daysInDepot = 30, depotName = "Depot North" }),
			[2] = veh("Fresh", true, { daysInDepot = 29 }),
			[3] = veh("Theirs", false, { daysInDepot = 400 }),
			[4] = veh("Long", true, { daysInDepot = 400.0 }),
		},
		idleDays = 30,
	})
	eq(ids(out), { "fleet_idle_depot:1", "fleet_idle_depot:4" })
	local a = byId(out)["fleet_idle_depot:1"]
	eq(a.tier, 3)
	eq(a.code, "InDepot")
	eq(a.context, "Depot North")
	eq(a.arg, "30")
	eq(a.metric, "30d")
	eq(byId(out)["fleet_idle_depot:4"].context, "", "no depot name")
	local fewer = checks.fleet({ vehicles = { [2] = veh("Fresh", true, { daysInDepot = 5 }) }, idleDays = 5 })
	eq(ids(fewer), { "fleet_idle_depot:2" })
	local default = checks.fleet({ vehicles = { [2] = veh("Fresh", true, { daysInDepot = 29 }) } })
	eq(ids(default), {}, "default 30 days")
end)

test("vehicles group merge: Phase 2 + Phase 3 kinds together", function()
	local s = checks.merge(instantState(), "vehicles",
		{ alert("veh_nopath", "1"), alert("veh_stuck", "2"), alert("train_blocked_by", "3") }, 10)
	eq(s.kindCounts, { veh_nopath = 1, veh_stuck = 1, train_blocked_by = 1 })
	s = checks.merge(s, "fleet", { alert("fleet_old", "4"), alert("fleet_idle_depot", "5") }, 20)
	eq(s.total, 5)
	eq(s.alerts[1].kind ~= nil, true)
end)

-- Phase 6 review fixes ---------------------------------------------------------

test("Phase 6: NoVehicleToLoadCargo on a line without vehicles is the line_no_vehicles row only", function()
	local out = checks.lines({
		lines = { [7] = line("Empty", true, 3, 0), [8] = line("Mixed", true, 3, 0), [9] = line("Running", true, 3, 2) },
		issues = {
			[7] = { { code = "NoVehicleToLoadCargo", stop = -1, cargo = "Coal" } },
			[8] = { { code = "NoVehicleToLoadCargo", stop = -1 }, { code = "NowhereToUnload", stop = 1, cargo = "Coal" } },
			[9] = { { code = "NoVehicleToLoadCargo", stop = -1 } },
		},
	})
	eq(ids(out), { "line_cargo_issue:8", "line_cargo_issue:9", "line_no_vehicles:7", "line_no_vehicles:8" })
	local a = byId(out)["line_cargo_issue:8"]
	eq(a.code, "NowhereToUnload", "the duplicate issue is removed, the other one stays")
	eq(a.metric, nil)
	eq(byId(out)["line_cargo_issue:9"].code, "NoVehicleToLoadCargo", "kept when the line has vehicles")
end)

test("Phase 6: NoVehicleToLoadCargo stays on a broken line (no line_no_vehicles row there)", function()
	local out = checks.lines({
		lines = { [7] = line("Broken", true, 3, 0) },
		problems = { { line = 7, code = "NO_PATH" } },
		issues = { [7] = { { code = "NoVehicleToLoadCargo", stop = -1 } } },
	})
	eq(ids(out), { "line_broken:7", "line_cargo_issue:7" })
end)

test("Phase 6: alertBefore / merge never error on bad tier, firstSeen or id types", function()
	local good = { id = "veh_stuck:1", kind = "veh_stuck", tab = "vehicles", tier = 1, firstSeen = 5 }
	local bad1 = { id = 42, kind = "veh_blocked", tab = "vehicles", tier = "x", firstSeen = "y" }
	local bad2 = { kind = "fleet_worn", tab = "fleet", tier = {}, firstSeen = true }
	ok(checks.alertBefore(good, bad1))
	eq(checks.alertBefore(bad1, good), false)
	ok(checks.alertBefore(bad2, bad1) or checks.alertBefore(bad1, bad2) or true, "no error")
	local list = { bad1, good, bad2, { id = "a", tier = 2.0, firstSeen = 1.5 } }
	table.sort(list, checks.alertBefore)
	eq(list[1], good)
	-- merge keeps other groups' garbage rows sortable
	local s = instantState()
	s.alerts = { bad1, bad2, { id = "station_useless:1", kind = "station_useless", tab = "stations", tier = "3", firstSeen = 0 } }
	local merged = checks.merge(s, "lines", { alert("line_broken", "1") }, 100)
	eq(merged.alerts[1].id, "line_broken:1")
end)

test("Phase 6: carryOver keeps the previous rows of the failed part until FAIL_DROP_AFTER failures", function()
	eq(checks.FAIL_DROP_AFTER, 10)
	local prev = { alert("veh_stuck", "1"), alert("veh_blocked", "2"), alert("train_blocked_by", "3"), "junk" }
	local kinds = { veh_stuck = true, train_blocked_by = true }
	local function k(list)
		local out = {}
		for i, a in ipairs(list) do out[i] = a.id end
		return out
	end
	eq(k(checks.carryOver(prev, kinds, 1)), { "veh_stuck:1", "train_blocked_by:3" })
	eq(k(checks.carryOver(prev, kinds, 9)), { "veh_stuck:1", "train_blocked_by:3" })
	eq(checks.carryOver(prev, kinds, 10), {}, "dropped on the 10th failure in a row")
	eq(checks.carryOver(prev, kinds, 3, 3), {})
	eq(checks.carryOver(nil, kinds, 1), {})
end)

test("Phase 6: a group that keeps failing is merged with no alerts (its rows go, others stay)", function()
	local s = checks.merge(instantState(), "vehicles", { alert("veh_stuck", "1") }, 100)
	s = checks.merge(s, "lines", { alert("line_broken", "2") }, 100)
	local dropped, changed = checks.merge(s, "vehicles", {}, 200)
	ok(changed)
	eq(#dropped.alerts, 1)
	eq(dropped.alerts[1].id, "line_broken:2")
	eq(dropped.kindCounts, { line_broken = 1 })
	eq(dropped.memory, s.memory, "timers kept")
end)

test("Phase 6: standingDue - no reads under the smallest threshold; classify unknown carriers once", function()
	local th = { ROAD = 3 * 60000, RAIL = 5 * 60000, WATER = 10 * 60000 }
	local now = 20 * 60000
	local stopped = {
		[1] = now - 60000,          -- under every threshold: nothing to read
		[2] = now - 4 * 60000,      -- over the smallest, carrier unknown: classify
		[3] = now - 4 * 60000,      -- known ship, under its 10 min: nothing
		[4] = now - 12 * 60000,     -- known ship, over: due
		[5] = now - 4 * 60000,      -- known road, over: due
		[6] = now - 30 * 60000,     -- OTHER carrier (no threshold): never due
		[7] = now - 3 * 60000.0,    -- exactly the smallest threshold, float from a save: classify
	}
	local carriers = { [3] = "WATER", [4] = "WATER", [5] = "ROAD", [6] = "OTHER" }
	local classify, due = checks.standingDue(stopped, now, carriers, th)
	eq(classify, { 2, 7 })
	eq(due, { 4, 5 })
	local c2, d2 = checks.standingDue(stopped, now, carriers, {})
	eq(c2, {})
	eq(d2, {})
end)

test("Phase 6: expireMarks keeps marks of vehicles still present and younger than the ttl", function()
	local marks = { [1] = 100, [2] = 100, [3] = 0, [4] = 900, [5] = "x" }
	local out = checks.expireMarks(marks, 1000, 950, { [1] = true, [3] = true, [4] = true, [5] = true })
	eq(out, { [1] = 100, [4] = 900 }, "2 gone, 3 expired, 5 garbage")
	eq(checks.expireMarks(nil, 1, 1, {}), {})
	eq(checks.expireMarks({ [1] = 5000 }, 1000, 950, { [1] = true }), {}, "a future mark is dropped")
end)

test("Phase 6: keepSameEntity drops kept rows whose id now belongs to another entity", function()
	local a1 = alert("fleet_old", "1"); a1.entity = 1
	local a2 = alert("fleet_old", "2"); a2.entity = 2
	local a3 = alert("fleet_old", "3"); a3.entity = 3
	local a4 = alert("fleet_old", "4"); a4.entity = 4.0
	local kept, revs = checks.keepSameEntity({ a1, a2, a3, a4 }, { [1] = 10, [2] = 20, [4] = 40 }, { [1] = 10, [2] = 25, [4] = 40 })
	eq(#kept, 2)
	eq(kept[1].id, "fleet_old:1")
	eq(kept[2].id, "fleet_old:4")
	eq(revs, { [1] = 10, [4] = 40 }, "2 reused (revision changed), 3 gone (no revision)")
	local k2, r2 = checks.keepSameEntity({ a3 }, nil, { [3] = 7 })
	eq(#k2, 1, "no saved revision yet (after a load): kept and remembered")
	eq(r2, { [3] = 7 })
end)

-- Smoothing (settings.smoothSec, radar_checks.merge) ---------------------------------------
-- Default window 30 game seconds = 30000 ms. Scans every ~2.4 s are modelled by calling merge.

local W = 30000

local function smoothState(sec)
	local s = checks.freshState()
	s.settings.smoothSec = sec or 30
	return s
end

local function pendingIds(s)
	local out = {}
	for i, a in ipairs(s.pending or {}) do out[i] = a.id end
	table.sort(out)
	return out
end

test("smoothing: a flickering detection stays pending (invisible) until detected over the window", function()
	local s, changed = checks.merge(smoothState(), "stations", { alert("station_overcrowded", "1") }, 0)
	ok(changed, "pending entry is saved")
	eq(s.alerts, {})
	eq(s.total, 0)
	eq(s.kindCounts, {})
	eq(pendingIds(s), { "station_overcrowded:1" })
	-- missed one scan: still pending, miss recorded
	s = checks.merge(s, "stations", {}, 2400)
	eq(pendingIds(s), { "station_overcrowded:1" })
	eq(s.pending[1].missedAt, 2400)
	eq(s.total, 0)
	-- detected again: the miss is forgotten, the window is NOT restarted
	s = checks.merge(s, "stations", { alert("station_overcrowded", "1") }, 4800)
	eq(s.pending[1].missedAt, nil)
	eq(s.pending[1].firstSeen, 0)
	local s2, again = checks.merge(s, "stations", { alert("station_overcrowded", "1") }, 7200)
	eq(again, false, "an unchanged pending entry does not rewrite the state")
	s = checks.merge(s2, "stations", { alert("station_overcrowded", "1") }, W - 1)
	eq(s.total, 0, "not yet: under the window")
	s, changed = checks.merge(s, "stations", { alert("station_overcrowded", "1") }, W)
	ok(changed)
	eq(ids(s.alerts), { "station_overcrowded:1" })
	eq(s.alerts[1].firstSeen, W, "firstSeen = the time it became listed")
	eq(s.kindCounts, { station_overcrowded = 1 })
	eq(s.total, 1)
	eq(s.pending, nil, "no pending left")
end)

test("smoothing: a single short blip is never listed; it is dropped once missed for longer than the window", function()
	local s = checks.merge(smoothState(), "stations", { alert("station_overcrowded", "1") }, 0)
	s = checks.merge(s, "stations", {}, 2400)
	s = checks.merge(s, "stations", {}, 2400 + W)
	eq(pendingIds(s), { "station_overcrowded:1" }, "missed exactly the window: kept")
	eq(s.total, 0)
	s = checks.merge(s, "stations", {}, 2401 + W)
	eq(s.pending, nil, "missed longer than the window: dropped")
	eq(s.alerts, {})
	-- seen again later: a new window from that time
	s = checks.merge(s, "stations", { alert("station_overcrowded", "1") }, 50000)
	eq(s.pending[1].firstSeen, 50000)
	eq(s.total, 0)
end)

test("smoothing: a listed alert missed briefly stays listed with its data and firstSeen", function()
	local a = alert("station_overcrowded", "1")
	a.metric = "412/300"
	local s = checks.merge(smoothState(), "stations", { a }, 100, nil, nil, true)
	eq(s.alerts[1].firstSeen, 100)
	local s1, changed = checks.merge(s, "stations", {}, 1000)
	ok(changed, "missedAt is saved")
	eq(ids(s1.alerts), { "station_overcrowded:1" })
	eq(s1.alerts[1].missedAt, 1000)
	eq(s1.alerts[1].metric, "412/300", "last data kept")
	eq(s1.total, 1)
	eq(s1.kindCounts, { station_overcrowded = 1 })
	local s1b, again = checks.merge(s1, "stations", {}, 3400)
	eq(again, false, "still missing: no state change")
	eq(s1b.alerts[1].missedAt, 1000, "miss time is the first miss")
	local b = alert("station_overcrowded", "1")
	b.metric = "500/300"
	local s2 = checks.merge(s1b, "stations", { b }, 5000)
	eq(s2.alerts[1].firstSeen, 100, "firstSeen unchanged")
	eq(s2.alerts[1].missedAt, nil)
	eq(s2.alerts[1].metric, "500/300", "fresh data again")
	eq(s2.pending, nil)
end)

test("smoothing: a listed alert gone for longer than the window clears", function()
	local s = checks.merge(smoothState(), "stations", { alert("station_overcrowded", "1") }, 100, nil, nil, true)
	s = checks.merge(s, "stations", {}, 1000)
	s = checks.merge(s, "stations", {}, 1000 + W)
	eq(s.total, 1, "missed exactly the window: still listed")
	local s2, changed = checks.merge(s, "stations", {}, 1001 + W)
	ok(changed)
	eq(s2.alerts, {})
	eq(s2.total, 0)
	eq(s2.kindCounts, {})
	-- it comes back: pending again (a new problem), not listed at once
	local s3 = checks.merge(s2, "stations", { alert("station_overcrowded", "1") }, 40000)
	eq(s3.total, 0)
	eq(pendingIds(s3), { "station_overcrowded:1" })
end)

test("smoothing: smoothSec = 0 reproduces the old behaviour (listed and cleared on the next scan)", function()
	local s = checks.merge(smoothState(0), "stations", { alert("station_overcrowded", "1") }, 10)
	eq(ids(s.alerts), { "station_overcrowded:1" })
	eq(s.alerts[1].firstSeen, 10)
	eq(s.pending, nil)
	s = checks.merge(s, "stations", {}, 20)
	eq(s.alerts, {})
	eq(s.total, 0)
	eq(s.pending, nil)
	-- switching to 0 while something is pending / lingering: pending detected now is listed, the rest goes
	local p = checks.merge(smoothState(), "stations", { alert("station_overcrowded", "1"), alert("station_useless", "2") }, 0)
	p = checks.merge(p, "fleet", { alert("fleet_worn", "3") }, 0, nil, nil, true)
	p = checks.merge(p, "fleet", {}, 100)
	eq(p.alerts[1].missedAt, 100)
	p.settings.smoothSec = 0
	p = checks.merge(p, "stations", { alert("station_overcrowded", "1") }, 200)
	eq(ids(p.alerts), { "fleet_worn:3", "station_overcrowded:1" })
	eq(p.pending, nil)
	p = checks.merge(p, "fleet", {}, 300)
	eq(ids(p.alerts), { "station_overcrowded:1" })
end)

test("smoothing: an older save without the new fields keeps its listed alerts listed", function()
	local a = alert("station_overcrowded", "1", 5)
	local oldSettings = settingsWith({})
	oldSettings.smoothSec = nil -- saved before the setting existed
	local st = v6({ settings = oldSettings, alerts = { a }, total = 1, kindCounts = { station_overcrowded = 1 } })
	eq(st.pending, nil)
	local u, changed = checks.upgradeState(st)
	ok(changed, "settings saved once with the default")
	eq(u.settings.smoothSec, 30)
	eq(u.pending, nil)
	eq(u.alerts[1], a)
	-- detected: still listed, firstSeen kept (not made pending again)
	local s = checks.merge(st, "stations", { alert("station_overcrowded", "1") }, 1000)
	eq(ids(s.alerts), { "station_overcrowded:1" })
	eq(s.alerts[1].firstSeen, 5)
	eq(s.total, 1)
	eq(s.pending, nil)
	-- not detected: lingers like any listed alert
	local s2 = checks.merge(st, "stations", {}, 1000)
	eq(s2.total, 1)
	eq(s2.alerts[1].missedAt, 1000)
	-- a v4 save's alerts too
	local v4 = { version = 4, settings = { hudMode = "badge" }, alerts = { a }, total = 1, kindCounts = { station_overcrowded = 1 } }
	local s3 = checks.merge(v4, "stations", { alert("station_overcrowded", "1") }, 1000)
	eq(s3.alerts[1].firstSeen, 5)
	eq(s3.total, 1)
	-- a garbage pending field is tolerated
	local s4 = checks.merge(v6({ alerts = { a }, total = 1, kindCounts = { station_overcrowded = 1 },
		pending = { "junk", { id = 7 }, alert("station_useless", "2", 0) } }), "stations", { alert("station_useless", "2") }, W)
	eq(ids(s4.alerts), { "station_overcrowded:1", "station_useless:2" }, "valid pending entry matured, junk dropped")
	eq(s4.pending, nil)
end)

test("smoothing: pending entries are capped (oldest first detection kept)", function()
	eq(checks.MAX_PENDING_ALERTS, 200)
	local first = {}
	for i = 1, 150 do first[#first + 1] = alert("fleet_worn", string.format("a%03d", i)) end
	local s = checks.merge(smoothState(), "fleet", first, 0)
	eq(#s.pending, 150)
	local second = {}
	for i = 1, 150 do second[#second + 1] = alert("fleet_worn", string.format("a%03d", i)) end
	for i = 1, 150 do second[#second + 1] = alert("fleet_worn", string.format("b%03d", i)) end
	s = checks.merge(s, "fleet", second, 1000)
	eq(#s.pending, 200)
	local m = byId(s.pending)
	ok(m["fleet_worn:a001"] ~= nil and m["fleet_worn:a150"] ~= nil, "the older ones kept")
	ok(m["fleet_worn:b050"] ~= nil and m["fleet_worn:b051"] == nil, "newer ones by id up to the cap")
	eq(s.total, 0)
	s = checks.merge(s, "fleet", second, W)
	eq(s.total, 150, "the first 150 listed after the window")
	eq(#s.pending, 150, "the 150 newer ones now fit")
end)

test("smoothing: carried rows (kept without a re-check) neither start nor stop timers", function()
	-- listed + lingering, then the scan fails and carryOver keeps it: still clears after the window
	local s = checks.merge(smoothState(), "vehicles", { alert("veh_stuck", "1") }, 0, nil, nil, true)
	s = checks.merge(s, "vehicles", {}, 1000)
	eq(s.alerts[1].missedAt, 1000)
	local kinds = { veh_stuck = true }
	local carried = checks.carryOver(s.alerts, kinds, 1)
	eq(carried[1].carried, true)
	ok(carried[1] ~= s.alerts[1], "a copy: the state's row is not marked")
	s = checks.merge(s, "vehicles", carried, 5000)
	eq(s.alerts[1].missedAt, 1000, "carried: the miss is not forgotten")
	eq(s.alerts[1].carried, nil, "the flag is never stored")
	s = checks.merge(s, "vehicles", checks.carryOver(s.alerts, kinds, 2), 1001 + W)
	eq(s.alerts, {}, "cleared after the window even while carried")
	-- listed, not missing, carried: stays listed with no miss
	local l = checks.merge(smoothState(), "vehicles", { alert("veh_stuck", "2") }, 0, nil, nil, true)
	l = checks.merge(l, "vehicles", checks.carryOver(l.alerts, kinds, 1), 100000)
	eq(ids(l.alerts), { "veh_stuck:2" })
	eq(l.alerts[1].missedAt, nil)
	-- pending, carried for longer than the window (line not measured): kept, not listed, not dropped
	local q = alert("line_overloaded", "3")
	local p = checks.merge(smoothState(), "lines", { q }, 0)
	local c = {}
	for k, v in pairs(p.pending[1]) do c[k] = v end
	c.carried = true
	p = checks.merge(p, "lines", { c }, 60000)
	eq(p.total, 0, "carried is no detection: not listed")
	eq(pendingIds(p), { "line_overloaded:3" }, "and not dropped")
	p = checks.merge(p, "lines", { alert("line_overloaded", "3") }, 61000)
	eq(ids(p.alerts), { "line_overloaded:3" }, "measured again past the window: listed")
end)

test("smoothing: priming (instant) lists at once; 'off' kinds go at once; over-cap kinds are not delayed", function()
	local s = checks.merge(smoothState(), "lines", { alert("line_broken", "1") }, 50, nil, nil, true)
	eq(ids(s.alerts), { "line_broken:1" })
	eq(s.alerts[1].firstSeen, 50)
	-- a kind switched off: no lingering, pending dropped
	s = checks.merge(s, "lines", { alert("line_broken", "1"), alert("line_no_vehicles", "2") }, 60)
	eq(pendingIds(s), { "line_no_vehicles:2" })
	s.settings.notify.line_broken = "off"
	s.settings.notify.line_no_vehicles = "off"
	s = checks.merge(s, "lines", {}, 70)
	eq(s.alerts, {})
	eq(s.pending, nil)
	-- over the stored cap (counted but not stored): a re-detected unstored id is listed at once
	local c = smoothState()
	local many = { alert("fleet_worn", "1"), alert("fleet_worn", "2"), alert("fleet_worn", "3") }
	c = checks.merge(c, "fleet", many, 0, 2, nil, true)
	eq(#c.alerts, 2)
	eq(c.total, 3)
	c = checks.merge(c, "fleet", { alert("fleet_worn", "1"), alert("fleet_worn", "2"), alert("fleet_worn", "3") }, 2400, 2)
	eq(c.total, 3, "no count flicker for the unstored row")
	eq(c.pending, nil)
end)

test("smoothing: other groups' pending entries are untouched by a scan; state stays plain data", function()
	local s = checks.merge(smoothState(), "stations", { alert("station_overcrowded", "1") }, 0)
	s = checks.merge(s, "lines", {}, 100000)
	eq(pendingIds(s), { "station_overcrowded:1" }, "only the scanned group's pending ids can be missed")
	eq(s.pending[1].missedAt, nil)
	local function plain(v)
		if type(v) == "table" then
			for k, x in pairs(v) do
				ok(type(k) == "string" or type(k) == "number", "plain key")
				plain(x)
			end
		else
			ok(type(v) == "string" or type(v) == "number" or type(v) == "boolean", "plain value")
		end
	end
	plain(s)
end)
