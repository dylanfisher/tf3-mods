-- radar_notify (Phase 5): per-kind notify level filtering, first-appearance-only toasts, the
-- re-notify cooldown, the per-cycle cap + summary, pause, the notified-set caps and the
-- "nothing changed -> no state:set" contract (result.changed).

local notify = ug_require "square_problem_radar::/radar/radar_notify.tl"
local settingsMod = ug_require "square_problem_radar::/radar/radar_settings.tl"
local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"

local MIN = 60000

local function settings(levels, over)
	local s = settingsMod.defaults()
	for k, v in pairs(levels or {}) do s.notify[k] = v end
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function alert(kind, key, firstSeen, extra)
	local k = checks.KINDS[kind]
	local a = { id = kind .. ":" .. key, kind = kind, tab = k.tab, tier = k.tier, entity = tonumber(key) or 1, etype = "Bus",
		label = "L" .. key, context = "", code = "ROAD", firstSeen = firstSeen or 0 }
	for f, v in pairs(extra or {}) do a[f] = v end
	return a
end

local function ids(list)
	local out = {}
	for i, a in ipairs(list) do out[i] = a.id end
	return out
end

local function step(now, alerts, prev, s)
	return notify.step({ now = now, settings = s or settings(), alerts = alerts,
		notified = prev and prev.notified or {}, cleared = prev and prev.cleared or {} })
end

test("constants", function()
	eq(notify.MAX_TOASTS, 3)
	eq(notify.COOLDOWN_MS, 10 * MIN)
	eq(notify.MAX_NOTIFIED, checks.MAX_STORED_ALERTS)
	eq(notify.MAX_CLEARED, 100)
end)

test("filterOff: off kinds are dropped, passive and notify kept", function()
	local s = settings({ veh_stuck = "off", fleet_old = "passive", line_no_vehicles = "notify" })
	local out = notify.filterOff({ alert("veh_stuck", "1"), alert("fleet_old", "2"), alert("line_no_vehicles", "3"), "junk" }, s)
	eq(ids(out), { "fleet_old:2", "line_no_vehicles:3" })
	ok(notify.isOn(s, "fleet_old"))
	eq(notify.isOn(s, "veh_stuck"), false)
	eq(#notify.filterOff(nil, s), 0)
end)

test("levels: only notify kinds toast; passive are listed only", function()
	local s = settings({ fleet_old = "notify" })
	local r = step(1000, { alert("veh_stuck", "1"), alert("fleet_worn", "2"), alert("fleet_old", "3") }, nil, s)
	eq(ids(r.toasts), { "veh_stuck:1", "fleet_old:3" }, "tier order: critical first")
	eq(r.more, 0)
	eq(r.notified, { ["veh_stuck:1"] = 1000, ["fleet_old:3"] = 1000 })
	ok(r.changed)
end)

test("first appearance only: no second toast while the alert persists; no change -> no state:set", function()
	local a = alert("veh_stuck", "1")
	local r1 = step(1000, { a })
	eq(#r1.toasts, 1)
	local r2 = step(5000, { a }, r1)
	eq(#r2.toasts, 0)
	eq(r2.more, 0)
	eq(r2.changed, false, "nothing transitioned")
	eq(r2.notified, { ["veh_stuck:1"] = 1000 })
	-- floats from a save are the same values
	local r3 = step(9000, { a }, { notified = { ["veh_stuck:1"] = 1000.0 }, cleared = {} })
	eq(r3.changed, false)
	-- no alerts, nothing stored: unchanged too
	eq(step(1, {}).changed, false)
end)

test("cooldown: cleared and back within it -> no toast; after it -> toast again", function()
	local a = alert("veh_stuck", "1")
	local r1 = step(0, { a })
	local r2 = step(1 * MIN, {}, r1)
	eq(r2.cleared, { ["veh_stuck:1"] = MIN }, "the cooldown starts when it clears")
	eq(r2.notified, {})
	ok(r2.changed)
	local r3 = step(2 * MIN, {}, r2)
	eq(r3.changed, false, "a running cooldown is no change")
	-- back within 10 minutes: flapping, marked notified silently
	local r4 = step(5 * MIN, { a }, r3)
	eq(#r4.toasts, 0)
	eq(r4.notified, { ["veh_stuck:1"] = 5 * MIN })
	eq(r4.cleared, {})
	-- clears again, back after the cooldown
	local r5 = step(6 * MIN, {}, r4)
	local r6 = step(16 * MIN + 1, {}, r5)
	eq(r6.cleared, {}, "expired cooldown dropped")
	ok(r6.changed)
	local r7 = step(17 * MIN, { a }, r6)
	eq(ids(r7.toasts), { "veh_stuck:1" })
end)

test("cooldown: a cleared time in the future (bad save) counts as now", function()
	local r = step(1000, {}, { notified = {}, cleared = { ["veh_stuck:1"] = 99999999 } })
	eq(r.cleared, { ["veh_stuck:1"] = 1000 })
end)

test("per-cycle cap: at most 3 toasts, the rest counted for one summary and marked notified", function()
	local alerts = {}
	for i = 1, 7 do alerts[#alerts + 1] = alert("veh_stuck", tostring(i), 100 - i) end
	local r = step(1000, alerts)
	eq(#r.toasts, 3)
	eq(ids(r.toasts), { "veh_stuck:7", "veh_stuck:6", "veh_stuck:5" }, "oldest first")
	eq(r.more, 4)
	local n = 0
	for _ in pairs(r.notified) do n = n + 1 end
	eq(n, 7, "the summarised ones never toast later")
	local r2 = step(2000, alerts, r)
	eq(#r2.toasts, 0)
	eq(r2.more, 0)
	local r3 = notify.step({ now = 1, settings = settings(), alerts = alerts, notified = {}, cleared = {}, maxToasts = 1 })
	eq(#r3.toasts, 1)
	eq(r3.more, 6)
end)

test("pause: new alerts are marked silently (no backlog after resuming)", function()
	local s = settings(nil, { notifyPaused = true })
	local r = step(1000, { alert("veh_stuck", "1"), alert("veh_stuck", "2") }, nil, s)
	eq(#r.toasts, 0)
	eq(r.more, 0)
	eq(r.notified, { ["veh_stuck:1"] = 1000, ["veh_stuck:2"] = 1000 })
	local r2 = step(2000, { alert("veh_stuck", "1"), alert("veh_stuck", "2"), alert("veh_stuck", "3") }, r, settings())
	eq(ids(r2.toasts), { "veh_stuck:3" }, "only the alert that appeared after resuming")
end)

test("min age: line_no_vehicles waits 2 game-minutes after it appeared", function()
	local a = alert("line_no_vehicles", "5", 1000)
	local r1 = step(1000 + MIN, { a })
	eq(#r1.toasts, 0)
	eq(r1.notified, {}, "not marked: it is evaluated again next cycle")
	eq(r1.changed, false)
	local r2 = step(1000 + 2 * MIN, { a }, r1)
	eq(ids(r2.toasts), { "line_no_vehicles:5" })
end)

test("a kind switched to passive or off: no toast; its notified entry clears normally", function()
	local a = alert("veh_stuck", "1")
	local r1 = step(0, { a })
	local r2 = step(MIN, { a }, r1, settings({ veh_stuck = "passive" }))
	eq(r2.changed, false, "still listed: kept")
	local r3 = step(2 * MIN, {}, r2, settings({ veh_stuck = "off" }))
	eq(r3.cleared, { ["veh_stuck:1"] = 2 * MIN })
end)

test("caps: notified at MAX_NOTIFIED, cleared at MAX_CLEARED (newest kept); garbage dropped", function()
	local alerts = {}
	for i = 1, 310 do alerts[#alerts + 1] = alert("veh_stuck", tostring(i)) end
	local r = step(1000, alerts)
	local n = 0
	for _ in pairs(r.notified) do n = n + 1 end
	eq(n, notify.MAX_NOTIFIED)
	local cleared = {}
	for i = 1, 120 do cleared["veh_stuck:" .. i] = i end
	local r2 = step(200, {}, { notified = {}, cleared = cleared })
	local c = 0
	for _ in pairs(r2.cleared) do c = c + 1 end
	eq(c, notify.MAX_CLEARED)
	eq(r2.cleared["veh_stuck:120"], 120)
	eq(r2.cleared["veh_stuck:1"], nil, "oldest dropped")
	local r3 = step(5, {}, { notified = { [1] = 2, x = "y" }, cleared = "bad" })
	eq(r3.cleared, {})
	ok(r3.changed, "garbage replaced once")
end)

test("params: plain copy of the alert for the notification", function()
	local a = alert("line_broken", "12", 5, { code = "NO_PATH", arg = "Catenary", pos = { 1, 2, 3 }, metric = "x", context = "c" })
	local p = notify.params(a)
	eq(p, { kind = "line_broken", tier = 1, etype = "Bus", label = "L12", context = "c", code = "NO_PATH", arg = "Catenary",
		metric = "x", entity = 12, pos = { 1, 2, 3 } })
	ok(p.pos ~= a.pos, "a copy")
	eq(notify.params(alert("veh_stuck", "1", 0, { pos = { 1, 2 } })).pos, nil)
end)

-- Phase 6 -------------------------------------------------------------------------

test("Phase 6: silentAll marks every new alert notified without a toast (mod just added)", function()
	local alerts = { alert("veh_stuck", "1"), alert("veh_stuck", "2"), alert("line_no_vehicles", "3", 0) }
	local r = notify.step({ now = 10 * MIN, settings = settings(), alerts = alerts, notified = {}, cleared = {}, silentAll = true })
	eq(#r.toasts, 0)
	eq(r.more, 0)
	eq(r.notified, { ["veh_stuck:1"] = 10 * MIN, ["veh_stuck:2"] = 10 * MIN, ["line_no_vehicles:3"] = 10 * MIN })
	ok(r.changed)
	-- the next cycle toasts only what is really new
	local r2 = step(11 * MIN, { alerts[1], alerts[2], alerts[3], alert("veh_stuck", "4") }, r)
	eq(ids(r2.toasts), { "veh_stuck:4" })
end)

test("Phase 6: silentKinds primes only the kinds just switched to notify", function()
	local s = settings({ fleet_old = "notify" })
	local alerts = { alert("fleet_old", "1"), alert("veh_stuck", "2") }
	local r = notify.step({ now = 1000, settings = s, alerts = alerts, notified = {}, cleared = {}, silentKinds = { fleet_old = true } })
	eq(ids(r.toasts), { "veh_stuck:2" })
	eq(r.notified["fleet_old:1"], 1000)
end)

test("Phase 6: newlyNotify lists kinds whose level became notify", function()
	local old = settings()
	eq(notify.newlyNotify(old, settings()), nil)
	eq(notify.newlyNotify(old, settings({ fleet_old = "notify", fleet_worn = "off" })), { fleet_old = true })
	eq(notify.newlyNotify(settings({ veh_stuck = "off" }), settings()), { veh_stuck = true }, "default notify after off")
	eq(notify.newlyNotify(nil, settings({ veh_stuck = "passive" })), nil)
end)

test("Phase 6: toastBefore never errors on bad field types", function()
	local a = { id = "x", tier = "bad", firstSeen = {} }
	local b = { id = 5, tier = 1, firstSeen = 1 }
	ok(notify.toastBefore(b, a))
	eq(notify.toastBefore(a, b), false)
end)

test("Phase 6: budget - at most 3 toasts + 1 summary per 2 game-minutes, overflow carried", function()
	eq(notify.BUDGET_WINDOW_MS, 2 * MIN)
	eq(notify.BUDGET_TOASTS, 3)
	eq(notify.BUDGET_SUMMARIES, 1)
	local function list(n, from)
		local out = {}
		for i = 1, n do out[i] = alert("veh_stuck", tostring((from or 0) + i)) end
		return out
	end
	-- cycle 1: 2 toasts (no summary)
	local t, more, b = notify.applyBudget(nil, 0, list(2), 0)
	eq(#t, 2)
	eq(more, 0)
	eq(b, { windowStart = 0, toasts = 2, summaries = 0, pending = 0 })
	-- cycle 2 (same window): 3 toasts + 4 more -> 1 toast fits, 2 over + 4 more = one summary of 6
	t, more, b = notify.applyBudget(b, 30000, list(3, 10), 4)
	eq(ids(t), { "veh_stuck:11" })
	eq(more, 6)
	eq(b.summaries, 1)
	eq(b.pending, 0)
	-- cycle 3 (same window): budget used up -> everything pending
	t, more, b = notify.applyBudget(b, 60000, list(2, 20), 1)
	eq(#t, 0)
	eq(more, 0)
	eq(b.pending, 3)
	-- cycle 4: nothing new, still the same window -> nothing sent
	t, more, b = notify.applyBudget(b, 90000, {}, 0)
	eq(#t, 0)
	eq(more, 0)
	eq(b.pending, 3)
	-- cycle 5: a new window -> the carried 3 arrive as the summary (with a new toast)
	t, more, b = notify.applyBudget(b, 2 * MIN, list(1, 30), 0)
	eq(ids(t), { "veh_stuck:31" })
	eq(more, 3)
	eq(b, { windowStart = 2 * MIN, toasts = 1, summaries = 1, pending = 0 })
end)

test("Phase 6: budget - paused drops the backlog; a bad / future budget starts a new window", function()
	local t, more, b = notify.applyBudget({ windowStart = 0, toasts = 3, summaries = 1, pending = 9 }, 1000, { alert("veh_stuck", "1") }, 2, true)
	eq(#t, 0)
	eq(more, 0)
	eq(b.pending, 0)
	t, more, b = notify.applyBudget({ windowStart = 99999999, toasts = 3, summaries = 1, pending = "x" }, 1000, { alert("veh_stuck", "1") }, 0)
	eq(#t, 1)
	eq(more, 0)
	eq(b, { windowStart = 1000, toasts = 1, summaries = 0, pending = 0 })
end)

test("smoothing: pending alerts never toast; a toast follows the row, MIN_AGE_MS counts from when it was listed", function()
	local s = settings({ station_overcrowded = "notify" })
	local st = checks.freshState()
	st.settings = s
	st = checks.merge(st, "stations", { alert("station_overcrowded", "1") }, 0)
	st = checks.merge(st, "lines", { alert("line_no_vehicles", "2") }, 0)
	local r = step(1000, st.alerts, nil, s)
	eq(r.toasts, {}, "pending: not listed, not toasted")
	eq(r.notified, {})
	st = checks.merge(st, "stations", { alert("station_overcrowded", "1") }, 30000)
	st = checks.merge(st, "lines", { alert("line_no_vehicles", "2") }, 30000)
	eq(st.total, 2)
	r = step(30000, st.alerts, nil, s)
	eq(ids(r.toasts), { "station_overcrowded:1" }, "listed now: toasts")
	-- line_no_vehicles waits MIN_AGE_MS from its listed time (30 s), not from first detection (0)
	local r2 = step(2 * MIN + 29999, st.alerts, r, s)
	eq(r2.toasts, {})
	local r3 = step(2 * MIN + 30000, st.alerts, r, s)
	eq(ids(r3.toasts), { "line_no_vehicles:2" })
	-- lingering (missed, still inside the window): still listed, no clear, no re-toast
	st = checks.merge(st, "stations", {}, 3 * MIN)
	local r4 = step(3 * MIN, st.alerts, r3, s)
	eq(r4.toasts, {})
	eq(r4.cleared, {})
end)
