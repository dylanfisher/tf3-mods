-- Rev 6 fleet recheck after an Upgrade from the fleet window: radar_checks.fleetCleared (which fleet rows
-- of a re-read vehicle no longer hold), radar_checks.dropAlerts (rows, counts, pending, snoozes) and the
-- view model's hideRows (the GUI's early filter).

local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"
local model = ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl"

local function alert(kind, key, extra)
	local k = checks.KINDS[kind]
	local a = { id = kind .. ":" .. key, kind = kind, tab = k.tab, tier = k.tier, entity = tonumber(key) or 1, etype = "Bus",
		label = "V" .. key, context = "c", code = "X", firstSeen = 0 }
	for f, v in pairs(extra or {}) do a[f] = v end
	return a
end

local function sorted(t)
	table.sort(t)
	return t
end

-- Smoothing off: vehicle 3 old + worn, vehicle 4 old, one line alert.
local function listed()
	local s = checks.freshState()
	s.settings.smoothSec = 0
	s = checks.merge(s, "lines", { alert("line_broken", "2") }, 1000)
	s = checks.merge(s, "fleet", { alert("fleet_old", "3"), alert("fleet_worn", "3"), alert("fleet_old", "4") }, 1000)
	return s
end

-- fleetCleared ---------------------------------------------------------------------

test("fleetCleared: a replaced vehicle (young, full condition) clears both rows", function()
	eq(sorted(checks.fleetCleared(3, { exists = true, ageMs = 10, lifespanMs = 1000, condition = 1.0 }, 0.3)),
		{ "fleet_old:3", "fleet_worn:3" })
end)

test("fleetCleared: still old / still worn (hysteresis end) / unknown values clear nothing", function()
	eq(checks.fleetCleared(3, { exists = true, ageMs = 2000, lifespanMs = 1000, condition = 0.3 }, 0.3), {})
	eq(checks.fleetCleared(3, { exists = true }, 0.3), {})
	-- lifespan 0: never old, so an Old row of it no longer holds
	eq(checks.fleetCleared(3, { exists = true, ageMs = 5000, lifespanMs = 0 }, 0.3), { "fleet_old:3" })
	eq(checks.fleetCleared(3, { exists = true, condition = 0.31 }, 0.3), { "fleet_worn:3" })
end)

test("fleetCleared: a vehicle that is gone clears both; nil input clears nothing", function()
	eq(sorted(checks.fleetCleared(7, { exists = false }, 0.3)), { "fleet_old:7", "fleet_worn:7" })
	eq(checks.fleetCleared(nil, { exists = false }, 0.3), {})
	eq(checks.fleetCleared(7, nil, 0.3), {})
end)

-- dropAlerts ---------------------------------------------------------------------

test("dropAlerts: rows, kindCounts, total and tierCounts", function()
	local s = listed()
	eq(s.total, 4)
	eq(s.tierCounts, { 1, 0, 3 })
	local d, changed = checks.dropAlerts(s, { ["fleet_old:3"] = true, ["fleet_worn:3"] = true })
	ok(changed)
	eq(#d.alerts, 2)
	eq(d.total, 2)
	eq(d.kindCounts.fleet_old, 1)
	eq(d.kindCounts.fleet_worn, nil)
	eq(d.tierCounts, { 1, 0, 1 })
	eq(s.kindCounts.fleet_worn, 1, "input counts untouched")
end)

test("dropAlerts: unknown ids or an empty set are no change", function()
	local s = listed()
	local _, changed = checks.dropAlerts(s, { ["fleet_old:99"] = true })
	ok(not changed)
	_, changed = checks.dropAlerts(s, {})
	ok(not changed)
	_, changed = checks.dropAlerts(s, nil)
	ok(not changed)
end)

test("dropAlerts: a snoozed row goes with its snooze and no count change", function()
	local s = checks.snooze(listed(), "fleet_old:4", 50000)
	eq(s.total, 3)
	local d, changed = checks.dropAlerts(s, { ["fleet_old:4"] = true })
	ok(changed)
	eq(d.total, 3)
	eq(d.snoozed, nil)
	eq(d.kindCounts.fleet_old, 1)
	eq(#d.alerts, 3)
end)

test("dropAlerts: pending (smoothing) rows go too; a later scan without them lists nothing", function()
	local s = checks.freshState()
	s.settings.smoothSec = 30
	s = checks.merge(s, "fleet", { alert("fleet_worn", "5") }, 1000)
	eq(#s.pending, 1)
	local d, changed = checks.dropAlerts(s, { ["fleet_worn:5"] = true })
	ok(changed)
	eq(d.pending, nil)
	local after = checks.merge(d, "fleet", {}, 40000)
	eq(#after.alerts, 0)
	eq(after.total, 0)
end)

test("dropAlerts: a dropped listed row does not linger through the smoothing window", function()
	local s = checks.freshState()
	s.settings.smoothSec = 30
	s = checks.merge(s, "fleet", { alert("fleet_old", "6") }, 1000, nil, nil, true)
	eq(#s.alerts, 1)
	local d = checks.dropAlerts(s, { ["fleet_old:6"] = true })
	local after = checks.merge(d, "fleet", {}, 2000)
	eq(#after.alerts, 0)
end)

-- hideRows (view model) -------------------------------------------------------------

test("view hideRows: rows and their counts go; the view itself when nothing applies", function()
	local v = model.buildRaw(listed())
	eq(v.total, 4)
	ok(model.hideRows(v, {}) == v)
	ok(model.hideRows(v, { ["fleet_old:99"] = true }) == v)
	local h = model.hideRows(v, { ["fleet_old:3"] = true, ["fleet_worn:3"] = true })
	eq(#h.rows, 2)
	eq(h.total, 2)
	eq(h.tabCounts.fleet, 1)
	eq(h.tabCounts.all, 2)
	eq(h.tierCounts, { 1, 0, 1 })
	eq(h.worstTier, 1)
	eq(v.total, 4, "input view untouched")
	eq(#v.rows, 4)
end)

test("view hideRows: snoozed rows leave the Snoozed tab", function()
	local v = model.buildRaw(checks.snooze(listed(), "fleet_old:4", 50000))
	eq(v.tabCounts.snoozed, 1)
	local h = model.hideRows(v, { ["fleet_old:4"] = true })
	eq(h.tabCounts.snoozed, 0)
	eq(#h.snoozedRows, 0)
	eq(h.total, v.total)
end)

-- calendarYearMs (round 3: ages in the base vehicle window's unit) -------------------

test("calendarYearMs: the current speed's year; frozen / bad values give the default", function()
	local function yearOf(mpd) return mpd * 365 end
	eq(checks.calendarYearMs(4000, yearOf, 1460000), 1460000)
	eq(checks.calendarYearMs(16000, yearOf, 1460000), 5840000)
	eq(checks.calendarYearMs(0, yearOf, 1460000), 1460000)
	eq(checks.calendarYearMs(nil, yearOf, 1460000), 1460000)
	eq(checks.calendarYearMs(4000, function() error("boom") end, 1460000), 1460000)
	eq(checks.calendarYearMs(4000, function() return 0 end, 1460000), 1460000)
	eq(checks.calendarYearMs(0, yearOf, nil), 365 * 4 * 1000)
end)
