-- Snooze: radar_checks.snooze / unsnooze / cleanSnoozed, merge keeping snoozed alerts stored but
-- uncounted and ending snoozes per group, radar_notify forgetting snoozed ids (a snooze that ends
-- toasts again), and the view model's Snoozed tab.

local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"
local notify = ug_require "square_problem_radar::/radar/radar_notify.tl"
local model = ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl"

local function alert(kind, key, extra)
	local k = checks.KINDS[kind]
	local a = { id = kind .. ":" .. key, kind = kind, tab = k.tab, tier = k.tier, entity = tonumber(key) or 1, etype = "Line",
		label = "L" .. key, context = "c", code = "X", firstSeen = 0 }
	for f, v in pairs(extra or {}) do a[f] = v end
	return a
end

-- Smoothing off, two lines alerts and one fleet alert listed.
local function listed()
	local s = checks.freshState()
	s.settings.smoothSec = 0
	s = checks.merge(s, "lines", { alert("line_unprofitable", "1", { tier = 1 }), alert("line_broken", "2") }, 1000)
	s = checks.merge(s, "fleet", { alert("fleet_old", "3") }, 1000)
	return s
end

test("snooze: the alert stays stored but leaves total, kindCounts and tierCounts", function()
	local s = listed()
	eq(s.total, 3)
	eq(s.tierCounts, { 2, 0, 1 })
	local z, changed = checks.snooze(s, "line_unprofitable:1", 50000)
	ok(changed)
	eq(#z.alerts, 3)
	eq(z.total, 2)
	eq(z.kindCounts.line_unprofitable, nil)
	eq(z.tierCounts, { 1, 0, 1 })
	eq(z.snoozed["line_unprofitable:1"], { untilMs = 50000, kind = "line_unprofitable", label = "L1", etype = "Line", context = "c", entity = 1 })
	eq(s.kindCounts.line_unprofitable, 1, "input counts untouched")
end)

test("snooze: unknown id is no change; re-snoozing (a repeated click) is no change", function()
	local s = listed()
	local _, changed = checks.snooze(s, "line_broken:99", 50000)
	ok(not changed)
	local z = checks.snooze(s, "line_broken:2", 50000)
	local z2, changed2 = checks.snooze(z, "line_broken:2", 90000)
	ok(not changed2)
	eq(z2.total, 2)
	eq(z2.snoozed["line_broken:2"].untilMs, 50000)
end)

test("cleanSnoozed returns a clean map itself (no copy per scan); seq carried by upgradeState and merge", function()
	local z = checks.snooze(listed(), "line_broken:2", 50000)
	ok(checks.cleanSnoozed(z.snoozed) == z.snoozed)
	z.seq = 41
	eq(checks.upgradeState(z).seq, 41)
	eq(checks.merge(z, "fleet", { alert("fleet_old", "3") }, 2000).seq, 41)
	eq(checks.snooze(z, "fleet_old:3", 60000).seq, 41)
end)

test("view applyPending: a pending snooze / wake moves the row and its counts at once", function()
	local s = checks.snooze(listed(), "fleet_old:3", 50000)
	local v = model.buildRaw(s)
	eq(model.applyPending(v, {}, {}) == v, true, "nothing pending: same view")
	local p = model.applyPending(v, { ["line_broken:2"] = 70000 }, { ["fleet_old:3"] = true })
	eq(#p.rows, 2)
	eq(p.rows[1].id, "line_unprofitable:1")
	eq(p.rows[2].id, "fleet_old:3")
	eq(p.rows[2].snoozedUntil, nil)
	eq(#p.snoozedRows, 1)
	eq(p.snoozedRows[1].snoozedUntil, 70000)
	eq(p.tabCounts.all, 2)
	eq(p.tabCounts.lines, 0)
	eq(p.tabCounts.fleet, 1)
	eq(p.tabCounts.snoozed, 1)
	eq(p.tierCounts, { 1, 0, 1 })
	eq(p.total, 2)
	eq(p.worstTier, 1)
	eq(#v.rows, 2, "input view untouched")
	eq(v.rows[2].snoozedUntil, nil)
	-- Applying again to the result is a no-op (idempotent for the commit + poll paths).
	local again = model.applyPending(p, { ["line_broken:2"] = 70000 }, { ["fleet_old:3"] = true })
	eq(again, p)
end)

test("merge: snoozed rows stay uncounted while detected; the snooze ends in its own group's merge", function()
	local s = checks.snooze(listed(), "line_unprofitable:1", 50000)
	local fresh = { alert("line_unprofitable", "1", { tier = 1 }), alert("line_broken", "2") }
	local m, changed = checks.merge(s, "lines", fresh, 2000)
	ok(not changed, "nothing new")
	eq(m.total, 2)
	ok(m.snoozed["line_unprofitable:1"] ~= nil)
	-- Expired, but another group's merge leaves it alone.
	local f = checks.merge(m, "fleet", { alert("fleet_old", "3") }, 60000)
	ok(f.snoozed ~= nil and f.snoozed["line_unprofitable:1"] ~= nil)
	eq(f.total, 2)
	local l, changed2 = checks.merge(f, "lines", fresh, 60000)
	ok(changed2)
	eq(l.snoozed, nil)
	eq(l.total, 3)
	eq(l.tierCounts, { 2, 0, 1 })
end)

test("snooze outlives its problem: kept (not listed) until it ends", function()
	local s = checks.snooze(listed(), "line_broken:2", 50000)
	local m = checks.merge(s, "lines", { alert("line_unprofitable", "1", { tier = 1 }) }, 2000)
	eq(#m.alerts, 2)
	ok(m.snoozed["line_broken:2"] ~= nil)
	-- It comes back while snoozed: stored, not counted.
	local back = checks.merge(m, "lines", { alert("line_unprofitable", "1", { tier = 1 }), alert("line_broken", "2") }, 3000)
	eq(back.kindCounts.line_broken, nil)
	eq(back.total, 2)
end)

test("unsnooze one / all: counts again at once", function()
	local s = checks.snooze(checks.snooze(listed(), "line_broken:2", 50000), "fleet_old:3", 50000)
	eq(s.total, 1)
	local one, c1 = checks.unsnooze(s, "fleet_old:3")
	ok(c1)
	eq(one.total, 2)
	eq(one.kindCounts.fleet_old, 1)
	eq(one.tierCounts, { 1, 0, 1 }, "line_broken still snoozed")
	local _, c0 = checks.unsnooze(one, "nope")
	ok(not c0)
	local all = checks.unsnooze(one, nil)
	eq(all.snoozed, nil)
	eq(all.total, 3)
	eq(all.tierCounts, { 2, 0, 1 })
end)

test("upgradeState keeps snoozes; cleanSnoozed drops garbage and caps", function()
	local s = checks.snooze(listed(), "line_broken:2", 50000)
	local u, changed = checks.upgradeState(s)
	ok(not changed)
	eq(u.snoozed, s.snoozed)
	eq(checks.cleanSnoozed({ a = { untilMs = "x", kind = "k" }, [3] = { untilMs = 1, kind = "k" } }), nil)
	local many = {}
	for i = 1, checks.MAX_SNOOZED + 5 do many["k:" .. i] = { untilMs = i, kind = "line_broken" } end
	local c = checks.cleanSnoozed(many)
	local n = 0
	for _ in pairs(c) do n = n + 1 end
	eq(n, checks.MAX_SNOOZED)
	ok(c["k:1"] == nil and c["k:" .. (checks.MAX_SNOOZED + 5)] ~= nil, "the latest-ending kept")
end)

test("notify: a snoozed alert never toasts, is forgotten, and toasts again when the snooze ends", function()
	local s = listed()
	s.settings.notify.line_broken = "notify"
	local a = alert("line_broken", "2")
	local snoozed = { ["line_broken:2"] = { untilMs = 50000, kind = "line_broken" } }
	local r1 = notify.step({ now = 1000, settings = s.settings, alerts = { a }, notified = {}, cleared = {}, snoozed = snoozed })
	eq(#r1.toasts, 0)
	eq(r1.notified, {})
	-- Already notified before it was snoozed: dropped from both maps, no cooldown.
	local r2 = notify.step({ now = 2000, settings = s.settings, alerts = { a }, notified = { ["line_broken:2"] = 500 },
		cleared = { ["line_broken:2"] = 400 }, snoozed = snoozed })
	eq(r2.notified, {})
	eq(r2.cleared, {})
	ok(r2.changed)
	local r3 = notify.step({ now = 60000, settings = s.settings, alerts = { a }, notified = r2.notified, cleared = r2.cleared })
	eq(#r3.toasts, 1)
end)

test("view: snoozed rows only in the Snoozed tab; gone ones from the snapshot", function()
	local s = checks.snooze(checks.snooze(listed(), "line_broken:2", 90000), "fleet_old:3", 50000)
	s.snoozed["veh_stuck:7"] = { untilMs = 70000, kind = "veh_stuck", label = "", etype = "Bus", context = "", entity = 7 }
	local v = model.buildRaw(s)
	eq(#v.rows, 1)
	eq(v.tabCounts.all, 1)
	eq(v.tabCounts.lines, 0)
	eq(v.tabCounts.economy, 1)
	eq(v.tabCounts.snoozed, 3)
	eq(v.tierCounts, { 1, 0, 0 })
	eq(v.total, 1)
	local rows, more = model.visibleRows(v, model.SNOOZED_TAB)
	eq(more, 0)
	eq({ rows[1].id, rows[2].id, rows[3].id }, { "fleet_old:3", "veh_stuck:7", "line_broken:2" })
	eq(rows[2].label, "#7")
	ok(rows[2].gone)
	eq(rows[2].detail, "Not detected right now")
	eq(rows[3].snoozedUntil, 90000)
	ok(not rows[3].gone)
	eq(#model.visibleRows(v, "all"), 1)
end)
