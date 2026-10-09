-- radar_settings: the settings schema shared by the engine script ("ProblemRadar.setSetting"
-- validation) and the GUI model. Phase 3 adds integer settings (stuck thresholds per carrier,
-- idle-in-depot days).

local settings = ug_require "square_problem_radar::/radar/radar_settings.tl"

local NOTIFY = {
	veh_blocked = "passive", veh_nopath = "passive", veh_stuck = "notify", train_blocked_by = "passive",
	line_broken = "passive", line_no_vehicles = "notify", line_cargo_issue = "passive",
	line_cargo_not_unloaded = "passive", line_overloaded = "passive",
	line_underused = "passive", line_bunching = "passive", station_overcrowded = "passive", station_useless = "passive",
	fleet_worn = "passive", fleet_old = "passive", fleet_idle_depot = "passive",
	line_unprofitable = "passive", line_low_use = "passive",
}

local function notifyWith(over)
	local n = {}
	for k, v in pairs(NOTIFY) do n[k] = v end
	for k, v in pairs(over or {}) do n[k] = v end
	return n
end

local function with(over)
	local s = { hudMode = "badge", stuckMinRoad = 3, stuckMinTram = 3, stuckMinRail = 5, stuckMinWater = 10,
		stuckMinAir = 5, idleDepotDays = 30, lineOverloadFactor = 3, lineUnderusedPct = 10, lineClumpPct = 20,
		lineGapPct = 300, lineSustainMin = 10, wornPct = 20, notifyPaused = false, smoothSec = 30,
		econLossWarnPct = 75, econLossCritPct = 50, econLossSharePct = 2, econLowUsePct = 20, snoozeMonths = 6, notify = notifyWith() }
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

test("defaults and allowed hud modes", function()
	eq(settings.defaults(), with())
	eq(settings.HUD_MODES, { "badge", "compact" })
	ok(settings.defaults() ~= settings.defaults(), "fresh table each call")
end)

test("schema: KEYS lists every key once; NUMBERS defaults within range; a stuck key per carrier", function()
	eq(settings.KEYS, { "hudMode", "notifyPaused", "smoothSec", "stuckMinRoad", "stuckMinTram", "stuckMinRail", "stuckMinWater", "stuckMinAir",
		"idleDepotDays", "wornPct", "lineOverloadFactor", "lineUnderusedPct", "lineClumpPct", "lineGapPct", "lineSustainMin",
		"econLossWarnPct", "econLossCritPct", "econLossSharePct", "econLowUsePct", "snoozeMonths" })
	local d = settings.defaults()
	for _, key in ipairs(settings.KEYS) do ok(d[key] ~= nil, key .. " has a default") end
	for key, num in pairs(settings.NUMBERS) do
		ok(num.min <= num.default and num.default <= num.max, key .. " default in range")
		ok(num.unit == "min" or num.unit == "days" or num.unit == "%" or num.unit == "x" or num.unit == "s" or num.unit == "months", key .. " unit")
	end
	eq(settings.STUCK_KEYS, { ROAD = "stuckMinRoad", TRAM = "stuckMinTram", RAIL = "stuckMinRail", WATER = "stuckMinWater", AIR = "stuckMinAir" })
end)

test("normalize: garbage and partial input give valid settings, extra keys dropped", function()
	eq(settings.normalize(nil), with())
	eq(settings.normalize("x"), with())
	eq(settings.normalize({}), with())
	eq(settings.normalize({ hudMode = "compact", extra = 1 }), with({ hudMode = "compact" }))
	eq(settings.normalize({ hudMode = 3 }), with())
end)

test("normalize: integer settings validated (type, integer, range); floats from a save accepted", function()
	eq(settings.normalize({ stuckMinWater = 20, idleDepotDays = 7 }), with({ stuckMinWater = 20, idleDepotDays = 7 }))
	eq(settings.normalize({ stuckMinRail = 2.0 }).stuckMinRail, 2)
	eq(settings.normalize({ stuckMinRail = 2.5 }).stuckMinRail, 5, "non-integer")
	eq(settings.normalize({ stuckMinRail = 0 }).stuckMinRail, 5, "below min")
	eq(settings.normalize({ stuckMinRail = 241 }).stuckMinRail, 5, "above max")
	eq(settings.normalize({ stuckMinRail = "4" }).stuckMinRail, 5, "string")
	eq(settings.normalize({ stuckMinRail = 0 / 0 }).stuckMinRail, 5, "NaN")
	eq(settings.normalize({ idleDepotDays = 3650 }).idleDepotDays, 3650)
	eq(settings.normalize({ idleDepotDays = 3651 }).idleDepotDays, 30)
	eq(settings.normalize({ hudMode = 1 }).hudMode, "badge", "a number is no hud mode")
end)

test("apply: a valid change", function()
	local s, changed, rejected = settings.apply(with(), { hudMode = "compact" })
	eq(s, with({ hudMode = "compact" }))
	eq(changed, true)
	eq(rejected, {})
end)

test("apply: integer keys (console shrink of a threshold)", function()
	local s, changed, rejected = settings.apply(with(), { stuckMinWater = 1, idleDepotDays = 2 })
	eq(s, with({ stuckMinWater = 1, idleDepotDays = 2 }))
	eq(changed, true)
	eq(rejected, {})
	s, changed, rejected = settings.apply(s, { stuckMinWater = 1.0 })
	eq(changed, false, "same value as a float is no change")
	s, changed, rejected = settings.apply(s, { stuckMinRoad = -1, stuckMinAir = "5", stuckMinTram = 1.5 })
	eq(changed, false)
	eq(rejected, { "stuckMinAir", "stuckMinRoad", "stuckMinTram" })
	eq(s.stuckMinRoad, 3)
end)

test("apply: same value is not a change", function()
	local s, changed, rejected = settings.apply(with({ hudMode = "compact" }), { hudMode = "compact" })
	eq(s, with({ hudMode = "compact" }))
	eq(changed, false)
	eq(rejected, {})
end)

test("apply: unknown keys and values are ignored and reported; valid keys still apply", function()
	local s, changed, rejected = settings.apply(with(), { hudMode = "huge", zoom = 2 })
	eq(s, with())
	eq(changed, false)
	eq(rejected, { "hudMode", "zoom" })
	s, changed, rejected = settings.apply(with(), { hudMode = "compact", [1] = "x" })
	eq(s, with({ hudMode = "compact" }))
	eq(changed, true)
	eq(rejected, { "1" })
end)

test("apply: non-table param rejects; a broken current state is normalised", function()
	local s, changed, rejected = settings.apply(nil, "compact")
	eq(s, with())
	eq(changed, false)
	eq(rejected, { "<param>" })
	local cur = { hudMode = "bogus", stuckMinRail = -3 }
	s = settings.apply(cur, {})
	eq(s, with())
	eq(cur, { hudMode = "bogus", stuckMinRail = -3 }, "input not mutated")
end)

test("same: raw settings equal to their normalised form on every key", function()
	eq(settings.same(with(), settings.defaults()), true)
	eq(settings.same(with({ stuckMinRail = 5.0 }), settings.defaults()), true, "float from a save")
	eq(settings.same({ hudMode = "badge" }, settings.defaults()), false, "v2 settings lack the new keys")
	local v4 = with()
	v4.notify, v4.notifyPaused, v4.wornPct = nil, nil, nil
	eq(settings.same(v4, settings.defaults()), false, "v4 settings lack the Phase 5 keys")
	eq(settings.same(with({ notify = notifyWith({ bogus = "off" }) }), settings.defaults()), false, "extra notify kind")
	eq(settings.same(nil, settings.defaults()), false)
end)

test("stuckThresholdsMs: minutes per carrier to game ms", function()
	eq(settings.stuckThresholdsMs(nil), { ROAD = 180000, TRAM = 180000, RAIL = 300000, WATER = 600000, AIR = 300000 })
	eq(settings.stuckThresholdsMs(with({ stuckMinWater = 1 })).WATER, 60000)
	eq(settings.stuckThresholdsMs({ stuckMinRail = 0 }).RAIL, 300000, "invalid -> default")
end)

test("Phase 4 line settings: defaults, ranges, console shrink", function()
	local n = settings.NUMBERS
	eq({ n.lineOverloadFactor.default, n.lineOverloadFactor.min, n.lineOverloadFactor.max }, { 3, 1, 50 })
	eq({ n.lineUnderusedPct.default, n.lineUnderusedPct.min, n.lineUnderusedPct.max }, { 10, 1, 90 })
	eq({ n.lineClumpPct.default, n.lineClumpPct.min, n.lineClumpPct.max }, { 20, 1, 90 })
	eq({ n.lineGapPct.default, n.lineGapPct.min, n.lineGapPct.max }, { 300, 120, 2000 })
	eq({ n.lineSustainMin.default, n.lineSustainMin.min, n.lineSustainMin.max }, { 10, 1, 240 })
	local s, changed, rejected = settings.apply(with(), { lineSustainMin = 1, lineOverloadFactor = 1, lineUnderusedPct = 90,
		lineClumpPct = 90, lineGapPct = 120 })
	ok(changed)
	eq(rejected, {})
	eq(s, with({ lineSustainMin = 1, lineOverloadFactor = 1, lineUnderusedPct = 90, lineClumpPct = 90, lineGapPct = 120 }))
	local _, changed2, rejected2 = settings.apply(with(), { lineGapPct = 100, lineSustainMin = 0, lineUnderusedPct = 12.5, lineClumpPct = "20" })
	eq(changed2, false)
	eq(rejected2, { "lineClumpPct", "lineGapPct", "lineSustainMin", "lineUnderusedPct" })
	eq(settings.normalize({ lineGapPct = 2001, lineOverloadFactor = 51 }), with())
	eq(settings.normalize({ lineGapPct = 250.0 }).lineGapPct, 250, "float from a save")
end)

-- Phase 5 -------------------------------------------------------------------------

test("Phase 5: notify kinds cover the catalogue; defaults per PLAN", function()
	local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"
	local n = 0
	for _, kind in ipairs(settings.NOTIFY_KINDS) do
		n = n + 1
		ok(checks.KINDS[kind] ~= nil, kind .. " is a catalogue kind")
		ok(settings.NOTIFY_DEFAULTS[kind] ~= nil, kind .. " has a default")
	end
	local k = 0
	for _ in pairs(checks.KINDS) do k = k + 1 end
	eq(n, k, "every catalogue kind listed once")
	eq(settings.NOTIFY_DEFAULTS, NOTIFY)
	eq(settings.NOTIFY_LEVELS, { "off", "passive", "notify" })
	-- base-notified kinds stay passive; other Critical kinds notify
	for _, kind in ipairs({ "veh_blocked", "veh_nopath", "line_broken", "line_cargo_issue", "line_cargo_not_unloaded", "station_overcrowded",
		"station_useless", "fleet_worn" }) do
		eq(settings.NOTIFY_DEFAULTS[kind], "passive", kind)
	end
	for kind, info in pairs(checks.KINDS) do
		if info.tier ~= 1 then eq(settings.NOTIFY_DEFAULTS[kind], "passive", kind .. " (not critical)") end
	end
	eq({ settings.NUMBERS.wornPct.default, settings.NUMBERS.wornPct.min, settings.NUMBERS.wornPct.max }, { 20, 1, 90 })
end)

test("line_cargo_not_unloaded: listed right after line_cargo_issue; a saved notify table without it gets the default", function()
	local idx = {}
	for i, kind in ipairs(settings.NOTIFY_KINDS) do idx[kind] = i end
	eq(idx.line_cargo_not_unloaded, idx.line_cargo_issue + 1)
	-- a save from before this kind: every other kind stored, line_cargo_not_unloaded missing
	local saved = with({ hudMode = "compact", notify = notifyWith({ line_cargo_issue = "notify", veh_stuck = "off" }) })
	saved.notify.line_cargo_not_unloaded = nil
	local n = settings.normalize(saved)
	eq(n.notify.line_cargo_not_unloaded, "passive")
	eq(n.notify.line_cargo_issue, "notify")
	eq(n.notify.veh_stuck, "off")
	eq(n.hudMode, "compact")
	eq(settings.level(n, "line_cargo_not_unloaded"), "passive")
	ok(not settings.same(saved, n), "the old table is rewritten once with the new kind")
	local s2, changed = settings.apply(n, { notify = { line_cargo_not_unloaded = "notify" } })
	ok(changed)
	eq(s2.notify.line_cargo_not_unloaded, "notify")
end)

test("Phase 5: apply notify levels (subset merge, validation per kind)", function()
	local s, changed, rejected = settings.apply(with(), { notify = { veh_stuck = "off", fleet_old = "notify" } })
	ok(changed)
	eq(rejected, {})
	eq(s.notify, notifyWith({ veh_stuck = "off", fleet_old = "notify" }))
	s, changed, rejected = settings.apply(s, { notify = { veh_stuck = "off" } })
	eq(changed, false, "same level is no change")
	s, changed, rejected = settings.apply(s, { notify = { veh_stuck = "loud", bogus = "off", [1] = "off", fleet_worn = 2, veh_nopath = "notify" } })
	ok(changed, "the valid entry still applies")
	eq(s.notify.veh_nopath, "notify")
	eq(s.notify.veh_stuck, "off")
	eq(rejected, { "notify.1", "notify.bogus", "notify.fleet_worn", "notify.veh_stuck" })
	local _, c2, r2 = settings.apply(with(), { notify = "off" })
	eq(c2, false)
	eq(r2, { "notify" })
end)

test("Phase 5: notifyPaused boolean and wornPct integer", function()
	local s, changed, rejected = settings.apply(with(), { notifyPaused = true, wornPct = 35 })
	ok(changed)
	eq(rejected, {})
	eq(s, with({ notifyPaused = true, wornPct = 35 }))
	local _, c2, r2 = settings.apply(s, { notifyPaused = 1, wornPct = 0 })
	eq(c2, false)
	eq(r2, { "notifyPaused", "wornPct" })
	eq(settings.normalize({ notifyPaused = "yes", wornPct = 91 }), with())
	eq(settings.normalize({ wornPct = 25.0 }).wornPct, 25, "float from a save")
end)

test("Phase 5: normalize notify: bad levels default, unknown kinds dropped, partial filled", function()
	local s = settings.normalize({ notify = { veh_stuck = "off", fleet_old = "x", bogus = "notify" } })
	eq(s.notify, notifyWith({ veh_stuck = "off" }))
	eq(settings.normalize({ notify = "x" }).notify, NOTIFY)
	local raw = { notify = { veh_stuck = "off" } }
	settings.normalize(raw)
	eq(raw.notify, { veh_stuck = "off" }, "input not mutated")
	ok(settings.defaults().notify ~= settings.defaults().notify, "fresh notify table each call")
end)

test("Phase 5: level() falls back to the default", function()
	eq(settings.level(with({ notify = notifyWith({ veh_stuck = "off" }) }), "veh_stuck"), "off")
	eq(settings.level(nil, "veh_stuck"), "notify")
	eq(settings.level({ notify = { veh_stuck = "x" } }, "veh_stuck"), "notify")
	eq(settings.level({}, "unknown_kind"), "passive")
end)

test("Phase 5: reset to defaults (validated)", function()
	local cur = with({ hudMode = "compact", wornPct = 50, notifyPaused = true, notify = notifyWith({ veh_stuck = "off" }) })
	local s, changed, rejected = settings.reset(cur, {})
	eq(s, with())
	ok(changed)
	eq(rejected, {})
	eq(cur.wornPct, 50, "input not mutated")
	local s2, c2, r2 = settings.reset(cur, nil)
	eq(s2, with())
	ok(c2)
	eq(r2, {})
	local s3, c3, r3 = settings.reset(cur, "now")
	eq(c3, false, "not a reset request")
	eq(r3, { "<param>" })
	eq(s3, cur, "unchanged (normalised copy)")
	local _, c4 = settings.reset(with(), {})
	eq(c4, false, "already default: no change, no save")
end)

test("Phase 5: worn thresholds keep the base hysteresis (+10 points)", function()
	local on, off = settings.wornThresholds(nil)
	near(on, 0.2)
	near(off, 0.3)
	on, off = settings.wornThresholds(with({ wornPct = 95 }))
	near(on, 0.2, nil, "invalid -> default")
	on, off = settings.wornThresholds(with({ wornPct = 90 }))
	near(on, 0.9)
	near(off, 1.0)
end)

-- Smoothing ---------------------------------------------------------------------------

test("smoothSec: default 30 s, range 0-600, 0 allowed (off); saved settings without it normalise to 30", function()
	eq(settings.NUMBERS.smoothSec, { default = 30, min = 0, max = 600, unit = "s" })
	eq(settings.defaults().smoothSec, 30)
	eq(settings.normalize({ smoothSec = 0 }).smoothSec, 0, "0 = smoothing off")
	eq(settings.normalize({ smoothSec = 600.0 }).smoothSec, 600, "float from a save")
	eq(settings.normalize({ smoothSec = 601 }).smoothSec, 30, "over max")
	eq(settings.normalize({ smoothSec = -1 }).smoothSec, 30, "below min")
	eq(settings.normalize({ smoothSec = 2.5 }).smoothSec, 30, "non-integer")
	-- a Phase 6 save: every other key, no smoothSec -> default filled, and saved once (same == false)
	local old = with()
	old.smoothSec = nil
	eq(settings.normalize(old), with())
	eq(settings.same(old, settings.defaults()), false, "missing smoothSec is written once")
	local s, changed, rejected = settings.apply(with(), { smoothSec = 0 })
	eq(s.smoothSec, 0)
	ok(changed)
	eq(rejected, {})
	local _, _, bad = settings.apply(with(), { smoothSec = 9999 })
	eq(bad, { "smoothSec" })
end)
