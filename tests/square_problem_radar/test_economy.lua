-- Phase 7 economy: line_unprofitable (12-month balance, quarters, cost coverage tiers), line_low_use
-- (time-weighted yearly utilisation average, tracking-age gate, persistence rules), the v5 -> v6
-- migration, the tier counts behind the ridge HUD, the economy settings and the model texts.
-- Inputs are the plain tables radar.script.tl's gather layer builds (radar_types.d.tl).

local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"
local settings = ug_require "square_problem_radar::/radar/radar_settings.tl"
local model = ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl"

local YEAR = 365 * 4 * 1000 -- game ms per year (default calendar, as api.util.getDefaultYearDuration)

local function money(year, q, vehicleCost, maintCost)
	return { year = year, quarters = q, vehicleCost = vehicleCost, maintCost = maintCost }
end

local function line(name, owned, stops, vehicles)
	return { name = name, owned = owned ~= false, stops = stops or 3, vehicles = vehicles or 2 }
end

local function byId(alerts)
	local m = {}
	for _, a in ipairs(alerts) do m[a.id] = a end
	return m
end

-- line_unprofitable: consistency ------------------------------------------------

test("judgeLoss: 12-month balance negative and >= 3 of 4 quarters negative", function()
	local s = settings.defaults()
	local l = checks.judgeLoss(money(-400, { -100, -100, -100, -100 }), s)
	ok(l ~= nil)
	eq(l.negQuarters, 4)
	eq(l.balance, -400)
	eq(checks.judgeLoss(money(-200, { -100, -100, 50, -50 }), s).negQuarters, 3, "3 of 4 is enough")
	eq(checks.judgeLoss(money(-100, { -100, -100, 50, 50 }), s), nil, "2 of 4 is not consistent")
	eq(checks.judgeLoss(money(100, { -100, -100, -100, 400 }), s), nil, "positive year: not losing money")
	eq(checks.judgeLoss(money(0, { -1, -1, -1, 3 }), s), nil, "break-even year")
	eq(checks.ECON_MIN_NEG_QUARTERS, 3)
end)

test("judgeLoss: a line without history in the oldest quarter (too young) is not judged", function()
	local s = settings.defaults()
	eq(checks.judgeLoss(money(-300, { 0, -100, -100, -100 }), s), nil)
	eq(checks.judgeLoss(money(-300, { 0.0, -100, -100, -100 }), s), nil, "float zero from the engine")
	eq(checks.judgeLoss(money(-300, { -1, -100, -100, -99 }), s).negQuarters, 4)
	eq(checks.judgeLoss(nil, s), nil)
	eq(checks.judgeLoss({ year = -5 }, s), nil, "no quarters")
	eq(checks.judgeLoss(money("x", { -1, -1, -1, -1 }), s), nil)
end)

-- line_unprofitable: severity ------------------------------------------------------

test("judgeLoss: tier by cost coverage (income / vehicle costs): Info, Warning < 75 %, Critical < 50 %", function()
	local s = settings.defaults()
	-- costs = 600 + 400 = 1000; income = balance + costs
	local function tierFor(balance)
		return checks.judgeLoss(money(balance, { -1, -1, -1, -1 }, -600, -400), s)
	end
	local info = tierFor(-100)           -- income 900 -> 90 %
	eq(info.tier, 3)
	near(info.coveragePct, 90, 1e-9)
	eq(tierFor(-250).tier, 3, "exactly 75 % is not below 75")
	eq(tierFor(-260).tier, 2)            -- 74 %
	eq(tierFor(-500).tier, 2, "exactly 50 % is a Warning")
	eq(tierFor(-510).tier, 1)            -- 49 %
	eq(tierFor(-1000).tier, 1)           -- no income at all: 0 %
	-- thresholds from the settings
	local s2 = settings.normalize({ econLossWarnPct = 95, econLossCritPct = 85 })
	eq(checks.judgeLoss(money(-100, { -1, -1, -1, -1 }, -600, -400), s2).tier, 2)
	eq(checks.judgeLoss(money(-200, { -1, -1, -1, -1 }, -600, -400), s2).tier, 1)
	-- Critical >= Warning: Critical simply wins
	local s3 = settings.normalize({ econLossWarnPct = 40, econLossCritPct = 60 })
	eq(checks.judgeLoss(money(-450, { -1, -1, -1, -1 }, -600, -400), s3).tier, 1)
end)

test("judgeLoss: coverage + size points: 0 Info, 1-2 Warning, 3+ Critical", function()
	local s = settings.defaults() -- coverage poor < 75 %, very poor < 50 %; size big >= 2 %, very big >= 6 %
	-- costs 1000 (600 + 400); network vehicle costs 10000 -> the loss / 100 is its share in %
	local function judge(balance, net)
		return checks.judgeLoss(money(balance, { -1, -1, -1, -1 }, -600, -400), s, net or 10000)
	end
	eq(judge(-100, 1000000).tier, 3, "90 % coverage, tiny loss: Info")
	eq(judge(-300, 1000000).tier, 2, "70 % (poor), tiny: Warning")
	eq(judge(-600, 1000000).tier, 2, "40 % (very poor), tiny: Warning (was Critical by coverage alone)")
	eq(judge(-200, 10000).tier, 2, "80 %, big (2 %): Warning")
	eq(judge(-200, 2000).tier, 2, "80 %, very big (10 %): Warning")
	eq(judge(-300, 10000).tier, 2, "poor + big: 2 points, Warning")
	eq(judge(-300, 4000).tier, 1, "poor + very big (7.5 %): Critical")
	eq(judge(-600, 20000).tier, 1, "very poor + big (3 %): Critical")
	local l = judge(-600, 20000)
	near(l.sharePct, 3, 1e-9)
	near(l.coveragePct, 40, 1e-9)
	-- unknown cost split counts as poor (1 point)
	eq(checks.judgeLoss(money(-300, { -1, -1, -1, -1 }), s, 4000).tier, 1, "unknown split + very big: Critical")
	eq(checks.judgeLoss(money(-300, { -1, -1, -1, -1 }), s, 1000000).tier, 2, "unknown split + tiny: Warning")
	-- unknown network costs: coverage alone decides, as before the size rule
	eq(judge(-600, 0).tier, 1)
	eq(judge(-600, 0).sharePct, nil)
	eq(checks.judgeLoss(money(-600, { -1, -1, -1, -1 }, -600, -400), s).tier, 1)
	-- the share threshold from the settings
	local s2 = settings.normalize({ econLossSharePct = 10 })
	eq(checks.judgeLoss(money(-300, { -1, -1, -1, -1 }, -600, -400), s2, 4000).tier, 2, "7.5 % is no longer very big")
end)

test("unprofitable: the share of all lines' costs is stored as a floored whole %", function()
	local out = checks.unprofitable({ settings = settings.defaults(), lines = { [10] = line("Coal") },
		money = { [10] = money(-1234567, { -1, -1, -1, -1 }, -3000000, -1000000) }, eligible = { [10] = true },
		networkCost = 20000000 })
	eq(out[1].arg, "-1200000|4|65|6", "6.17 % floored")
	eq(out[1].tier, 1, "poor (69 %) + very big (>= 6 %)")
	out = checks.unprofitable({ settings = settings.defaults(), lines = { [10] = line("Coal") },
		money = { [10] = money(-1234567, { -1, -1, -1, -1 }, -3000000, -1000000) }, eligible = { [10] = true },
		networkCost = 500000000 })
	eq(out[1].arg, "-1200000|4|65|0", "under 1 %")
	eq(out[1].tier, 2)
end)

test("model: within a tier, bigger losses are listed first", function()
	local function a(id, tier, metric, firstSeen)
		return { id = id, kind = "line_unprofitable", tab = "economy", tier = tier, entity = 1, label = id,
			arg = metric .. "|4|40|1", metric = metric, firstSeen = firstSeen }
	end
	local view = model.buildRaw({ alerts = { a("small", 2, "-18000", 1), a("big", 2, "-360000", 9), a("crit", 1, "-5000", 5),
		{ id = "line_low_use:1", kind = "line_low_use", tab = "economy", tier = 2, entity = 1, arg = "5|12", metric = "5%", firstSeen = 0 } } })
	local ids = {}
	for _, r in ipairs(view.rows) do ids[#ids + 1] = r.id end
	eq(ids[1], "crit", "tier first")
	-- the two Warning losses: bigger first, regardless of firstSeen
	local big, small
	for i, id in ipairs(ids) do if id == "big" then big = i elseif id == "small" then small = i end end
	ok(big < small)
end)

test("judgeLoss: unknown or implausible cost split falls back to Warning", function()
	local s = settings.defaults()
	local l = checks.judgeLoss(money(-100, { -1, -1, -1, -1 }), s)
	eq(l.tier, 2)
	eq(l.coveragePct, nil)
	eq(checks.judgeLoss(money(-100, { -1, -1, -1, -1 }, 0, 0), s).tier, 2, "no cost entries")
	eq(checks.judgeLoss(money(-500, { -1, -1, -1, -1 }, -100, -100), s).coveragePct, nil, "income would be negative")
	eq(checks.judgeLoss(money(-100, { -1, -1, -1, -1 }, -600, nil), s).tier, 2, "one cost type missing")
end)

test("roundSig2: two significant digits, sign kept", function()
	eq(checks.roundSig2(-1234567), -1200000)
	eq(checks.roundSig2(-1250000), -1300000)
	eq(checks.roundSig2(987), 990)
	eq(checks.roundSig2(-99), -99)
	eq(checks.roundSig2(5), 5)
	eq(checks.roundSig2(0), 0)
	eq(checks.roundSig2(-995.0), -1000)
end)

test("unprofitable: row per checked losing line; arg/metric raw integers; ownership and eligibility", function()
	local lines = { [10] = line("Coal"), [11] = line("Foreign", false), [12] = line("Fine"), [13] = line("Idle", true, 3, 0) }
	local out = checks.unprofitable({
		settings = settings.defaults(),
		lines = lines,
		money = {
			[10] = money(-1234567, { -300000, -300000, -300000, -334567 }, -3000000, -1000000), -- coverage 69.1 %
			[11] = money(-500, { -1, -1, -1, -1 }),
			[12] = money(5000, { 1, 1, 1, 1 }),
			[13] = money(-500, { -1, -1, -1, -1 }),
		},
		eligible = { [10] = true, [12] = true },
	})
	eq(#out, 1)
	local a = out[1]
	eq(a.id, "line_unprofitable:10")
	eq(a.kind, "line_unprofitable")
	eq(a.tab, "economy")
	eq(a.tier, 2)
	eq(a.entity, 10)
	eq(a.etype, "Line")
	eq(a.label, "Coal")
	eq(a.code, "Loss")
	eq(a.arg, "-1200000|4|65|", "balance to 2 digits, coverage floored to 5-point steps, no network costs")
	eq(a.metric, "-1200000")
	local nosplit = checks.unprofitable({ settings = settings.defaults(), lines = lines,
		money = { [10] = money(-500, { -1, -1, -1, -1 }) }, eligible = { [10] = true } })
	eq(nosplit[1].code, "LossNoSplit")
	eq(nosplit[1].arg, "-500|4||")
	eq(nosplit[1].tier, 2)
end)

test("unprofitable: rows of eligible lines not checked this pass are carried; others dropped", function()
	local keep = {
		{ id = "line_unprofitable:20", kind = "line_unprofitable", tab = "economy", tier = 1, entity = 20, arg = "-9|4|0", firstSeen = 5 },
		{ id = "line_unprofitable:21", kind = "line_unprofitable", tab = "economy", tier = 2, entity = 21, firstSeen = 5 }, -- gone
		{ id = "line_unprofitable:10", kind = "line_unprofitable", tab = "economy", tier = 3, entity = 10, firstSeen = 5 }, -- re-checked
		{ id = "line_low_use:20", kind = "line_low_use", tab = "economy", tier = 3, entity = 20, firstSeen = 5 },        -- other kind
	}
	local out = checks.unprofitable({
		settings = settings.defaults(),
		lines = { [10] = line("A"), [20] = line("B") },
		money = { [10] = money(100, { 1, 1, 1, 1 }) }, -- now profitable
		eligible = { [10] = true, [20] = true },
		keep = keep,
	})
	eq(#out, 1)
	eq(out[1].id, "line_unprofitable:20")
	eq(out[1].tier, 1, "carried with its tier")
	eq(out[1].carried, true)
	eq(keep[1].carried, nil, "input not mutated")
end)

-- line_low_use: the average --------------------------------------------------------

test("updateUseAvg: tracking starts at the first sample, which the second fully replaces", function()
	local u = checks.updateUseAvg(nil, 0.4, 1000, YEAR)
	eq(u, { avg = 0.4, start = 1000, last = 1000 })
	local u2 = checks.updateUseAvg(u, 0.1, 2000, YEAR)
	near(u2.avg, 0.1, 1e-12, "the first sample stands for no time")
	eq(u2.start, 1000)
	eq(u2.last, 2000)
	eq(checks.updateUseAvg(u2, 0.9, 2000, YEAR), u2, "dt = 0: unchanged")
	eq(checks.updateUseAvg(u2, 0.9, 500, YEAR).start, 500, "time went back (another save): restart")
	eq(checks.updateUseAvg(nil, 1.7, 0, YEAR).avg, 1.0, "clamped")
	eq(checks.updateUseAvg(nil, -1, 0, YEAR).avg, 0.0)
end)

test("updateUseAvg: time-weighted EMA with a one-year time constant, bias-corrected", function()
	-- Samples 1.0 for half a year, then 0.0 for half a year, in steps: the average is the
	-- exponentially weighted mean of the two halves.
	local u = checks.updateUseAvg(nil, 1.0, 0, YEAR)
	local step = YEAR // 100
	local t = 0
	for _ = 1, 50 do
		t = t + step
		u = checks.updateUseAvg(u, 1.0, t, YEAR)
	end
	near(u.avg, 1.0, 1e-9, "constant input stays constant")
	for _ = 1, 50 do
		t = t + step
		u = checks.updateUseAvg(u, 0.0, t, YEAR)
	end
	-- weight of the older half: (1 - e^-0.5) e^-0.5; of the newer half: 1 - e^-0.5; total 1 - e^-1
	local e = math.exp(-0.5)
	near(u.avg, (1 - e) * e / (1 - math.exp(-1)), 1e-9)
	-- one big step equals many small ones (dt weighting)
	local a = checks.updateUseAvg(checks.updateUseAvg(nil, 0.0, 0, YEAR), 0.5, YEAR // 2, YEAR)
	local b = checks.updateUseAvg(nil, 0.0, 0, YEAR)
	for i = 1, 10 do b = checks.updateUseAvg(b, 0.5, i * (YEAR // 20), YEAR) end
	near(a.avg, b.avg, 1e-9)
end)

test("sampleUseAvg: lines gone drop their average; new lines over the cap are not tracked", function()
	local live = { [1] = { avg = 0.5, start = 0, last = 100 }, [2] = { avg = 0.2, start = 0, last = 100 } }
	local out = checks.sampleUseAvg(live, { [1] = 0.5, [3] = 0.3, [4] = 0.1 }, { [1] = true, [3] = true, [4] = true }, 200, YEAR, 2)
	eq(out[2], nil, "line 2 is gone")
	eq(out[1].last, 200)
	eq(out[3], { avg = 0.3, start = 200, last = 200 })
	eq(out[4], nil, "over the cap of 2")
	eq(live[1].last, 100, "input entries not mutated")
	local kept = checks.sampleUseAvg(live, {}, { [1] = true, [2] = true }, 300, YEAR)
	eq(kept[2], live[2], "not measured this pass: kept as is")
	eq(checks.MAX_USE_TRACKED, 1000)
end)

test("lowUse: judged only after half a year of tracking; tiers at the threshold, half and quarter", function()
	local lines = { [1] = line("A"), [2] = line("B"), [3] = line("C"), [4] = line("D"), [5] = line("E", false), [6] = line("F") }
	local now = 10 * YEAR
	local half = YEAR // 2
	local avgs = {
		[1] = { avg = 0.15, start = now - half, last = now },      -- 15 % < 20: Info
		[2] = { avg = 0.09, start = now - YEAR * 2, last = now },  -- 9 % < 10: Warning
		[3] = { avg = 0.04, start = now - YEAR, last = now },      -- 4 % < 5: Critical
		[4] = { avg = 0.01, start = now - half + 1, last = now },  -- not tracked long enough yet
		[5] = { avg = 0.01, start = 0, last = now },               -- not the player's
		[6] = { avg = 0.20, start = 0, last = now },               -- exactly the threshold: fine
	}
	local out = checks.lowUse({ now = now, yearMs = YEAR, settings = settings.defaults(), lines = lines,
		eligible = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true }, useAvg = avgs })
	local m = byId(out)
	eq(#out, 3)
	eq(m["line_low_use:1"].tier, 3)
	eq(m["line_low_use:1"].arg, "15|6")
	eq(m["line_low_use:1"].metric, "15%")
	eq(m["line_low_use:1"].tab, "economy")
	eq(m["line_low_use:1"].code, "LowUse")
	eq(m["line_low_use:2"].tier, 2)
	eq(m["line_low_use:2"].arg, "9|12", "months capped at 12")
	eq(m["line_low_use:3"].tier, 1)
	eq(checks.USE_MIN_TRACK_FRACTION, 0.5)
	-- not eligible (broken, no vehicles): no row
	local none = checks.lowUse({ now = now, yearMs = YEAR, settings = settings.defaults(), lines = lines, eligible = {}, useAvg = avgs })
	eq(#none, 0)
	-- threshold from the settings
	local lower = checks.lowUse({ now = now, yearMs = YEAR, settings = settings.normalize({ econLowUsePct = 10 }), lines = lines,
		eligible = { [1] = true, [2] = true }, useAvg = avgs })
	eq(#lower, 1)
	eq(lower[1].id, "line_low_use:2")
	eq(lower[1].tier, 3)
end)

-- line_low_use: persistence ------------------------------------------------------------

test("persistUseAvg: saved only on add / remove / restart or the monthly cadence (not on moves)", function()
	local month = YEAR // 12
	local live = { [1] = { avg = 0.25, start = 0, last = 1000 } }
	local saved, changed = checks.persistUseAvg(live, {}, month)
	ok(changed, "new line")
	eq(saved, { [1] = { 2500, 0, 1000 } })
	-- moves alone, however large, wait for the cadence (perf review 2026-10-07: noisy instant samples
	-- moved some average >= 1 point on most passes, and each move rewrote the whole state)
	local s2, c2 = checks.persistUseAvg({ [1] = { avg = 0.60, start = 0, last = 2000 } }, saved, month)
	eq(c2, false)
	ok(s2 == saved, "unchanged: the same table back")
	-- a month after the last write: every entry rewritten
	local s4, c4 = checks.persistUseAvg({ [1] = { avg = 0.25, start = 0, last = 1000 + month } }, saved, month)
	ok(c4)
	eq(s4[1][3], 1000 + month)
	-- tracking restarted (another start): written at once, so reconcileUseAvg still matches
	local _, c7 = checks.persistUseAvg({ [1] = { avg = 0.25, start = 500, last = 1500 } }, saved, month)
	ok(c7)
	-- a line gone
	local s5, c5 = checks.persistUseAvg({}, saved, month)
	ok(c5)
	eq(s5, {})
	-- garbage saved data
	local _, c6 = checks.persistUseAvg(live, "x", month)
	ok(c6)
end)

test("persistUseAvg: the cadence is per write, not per entry (many lines re-sampled less than monthly)", function()
	-- 500 lines, 8 sampled per lines pass (2.4 s): each line is re-sampled every ~150 s, more than a
	-- game month (~122 s). Per-entry cadence wrote on every pass; now about once per month.
	local month = YEAR // 12
	local L, PER, PASS = 500, 8, 2400
	local live, saved = {}, {}
	local keep = {}
	for l = 1, L do keep[l] = true end
	local writes, cursor = 0, 0
	local t0 = 2 * YEAR
	local passes = math.floor(3 * month / PASS)
	local firstRotation = math.ceil(L / PER)
	local steady = 0
	for p = 0, passes - 1 do
		local now = t0 + p * PASS
		local samples = {}
		for k = 0, PER - 1 do samples[(cursor + k) % L + 1] = ((p * 7 + k) % 10) / 10 end
		cursor = (cursor + PER) % L
		live = checks.sampleUseAvg(checks.reconcileUseAvg(saved, live, now - PASS, now), samples, keep, now, YEAR)
		local changed
		saved, changed = checks.persistUseAvg(live, saved, month)
		if changed then
			writes = writes + 1
			if p >= firstRotation then steady = steady + 1 end
		end
	end
	ok(steady <= 3, "about one write per game month after the first rotation, got " .. steady)
	ok(writes <= firstRotation + 3, "first rotation adds lines, then monthly: " .. writes)
	-- the live copy kept matching the save throughout (never rebuilt from it)
	eq(checks.reconcileUseAvg(saved, live, t0 + passes * PASS, t0 + passes * PASS), live)
end)

test("reconcileUseAvg: live averages kept while they match the save, else rebuilt from it", function()
	local saved = { [1] = { 2500, 0, 1000 }, [2] = { 100.0, 50.0, 900.0 } }
	local fromSave = checks.reconcileUseAvg(saved, nil, nil, 2000)
	eq(fromSave, { [1] = { avg = 0.25, start = 0, last = 1000 }, [2] = { avg = 0.01, start = 50, last = 900 } })
	local live = { [1] = { avg = 0.2549, start = 0, last = 1500 }, [2] = { avg = 0.0105, start = 50, last = 900 } }
	ok(checks.reconcileUseAvg(saved, live, 1500, 2000) == live, "consistent: kept")
	-- a load to an earlier time / another save
	eq(checks.reconcileUseAvg(saved, live, 2500, 2000), fromSave, "live made later than now")
	local other = { [1] = { avg = 0.25, start = 7, last = 1500 }, [2] = live[2] }
	eq(checks.reconcileUseAvg(saved, other, 1500, 2000), fromSave, "different start")
	local older = { [1] = { avg = 0.25, start = 0, last = 999 }, [2] = live[2] }
	eq(checks.reconcileUseAvg(saved, older, 1500, 2000), fromSave, "a sample older than the saved one")
	local moved = { [1] = { avg = 0.30, start = 0, last = 1500 }, [2] = live[2] }
	ok(checks.reconcileUseAvg(saved, moved, 1500, 2000) == moved, "drift between writes is expected: kept")
	eq(checks.reconcileUseAvg(saved, { [1] = live[1] }, 1500, 2000), fromSave, "different lines")
	-- malformed / future entries are dropped
	local junk = checks.reconcileUseAvg({ [1] = { 1, 2 }, [2] = "x", [3] = { 5000, 0, 9999 } }, nil, nil, 2000)
	eq(junk, {})
	eq(checks.reconcileUseAvg("x", nil, nil, 1), {})
end)

test("save / load round trip: the averages survive as last written (at most a game month old)", function()
	local month = YEAR // 12
	local live = {}
	local saved = {}
	local t = 0
	for i = 1, 200 do
		t = t + 7000
		live = checks.sampleUseAvg(live, { [5] = (i % 2 == 0) and 0.1 or 0.3 }, { [5] = true }, t, YEAR)
		saved = checks.persistUseAvg(live, saved, month)
	end
	-- "load": no live copy
	local restored = checks.reconcileUseAvg(saved, nil, nil, t)
	ok(t - restored[5].last < month, "written within the last month")
	ok(math.abs(restored[5].avg - live[5].avg) < 0.01, "a month of samples moves a yearly average little")
	eq(restored[5].start, live[5].start)
end)

-- line_unprofitable: cost (perf review 2026-10-07) ---------------------------------------------

test("lineMoney: stops once the verdict is settled; a losing line gets all 7 numbers", function()
	local calls
	local function fake(year, quarters, veh, maint)
		calls = {}
		return function(from, to, mt)
			calls[#calls + 1] = { from, to, mt }
			if mt == "VEH" then return veh end
			if mt == "VM" then return maint end
			if to - from == YEAR then return year end
			return quarters[math.floor((from - YEAR) / (YEAR // 4)) + 1]
		end
	end
	local now = 2 * YEAR
	-- profitable: 1 call, no verdict
	local m = checks.lineMoney(fake(500, { 1, 1, 1, 1 }), now, YEAR, "VEH", "VM")
	eq(#calls, 1)
	eq(calls[1], { YEAR, now })
	eq(checks.judgeLoss(m, settings.defaults()), nil)
	-- too young (empty oldest quarter): 2 calls
	m = checks.lineMoney(fake(-500, { 0, -1, -1, -1 }), now, YEAR, "VEH", "VM")
	eq(#calls, 2)
	eq(checks.judgeLoss(m, settings.defaults()), nil)
	-- two quarters >= 0 settle "not consistent": stops at the second one
	m = checks.lineMoney(fake(-50, { -100, 30, 20, -1 }), now, YEAR, "VEH", "VM")
	eq(#calls, 4)
	eq(checks.judgeLoss(m, settings.defaults()), nil)
	-- losing: year, 4 quarters (in order, the last one ends now), 2 cost types
	m = checks.lineMoney(fake(-700, { -100, -200, 50, -450 }, -600, -400), now, YEAR, "VEH", "VM")
	eq(#calls, 7)
	eq(calls[2], { YEAR, YEAR + YEAR // 4 })
	eq(calls[5][2], now)
	eq(calls[6][3], "VEH")
	eq(calls[7][3], "VM")
	local loss = checks.judgeLoss(m, settings.defaults())
	eq(loss.negQuarters, 3)
	eq(loss.tier, 1) -- income 300 of costs 1000
	-- no cost enum: 5 calls, split unknown
	m = checks.lineMoney(fake(-700, { -100, -200, -50, -350 }), now, YEAR, nil, nil)
	eq(#calls, 5)
	eq(checks.judgeLoss(m, settings.defaults()).tier, 2)
end)

test("dueRotation: rotation order, at most max, a month between checks, pending rows sooner", function()
	local month = YEAR // 12
	local ids = { 5, 1, 3, 9 }
	eq(checks.dueRotation(ids, -1, {}, 1000, month, 2), { 1, 3 }, "never checked: in id order, capped")
	eq(checks.dueRotation(ids, 3, {}, 1000, month, 9), { 5, 9, 1, 3 }, "after the cursor, then wrap")
	local at = { [1] = 1000, [3] = 1000, [5] = 1000 - month, [9] = 5000 }
	eq(checks.dueRotation(ids, -1, at, 1000, month, 9), { 5, 9 }, "5 a month old; 9 checked later than now (a load)")
	eq(checks.dueRotation(ids, -1, at, 1000 + 30000, month, 9, { [3] = true }, 30000), { 3, 5 }, "3 has a pending row: after the smoothing window")
	eq(checks.dueRotation(ids, -1, at, 1000 + 29999, month, 9, { [3] = true }, 30000), { 5 })
	eq(checks.dueRotation(ids, -1, at, 5000 + month, month, 9), { 1, 3, 5, 9 }, "all a month old")
	eq(checks.dueRotation({}, -1, {}, 0, month, 4), {})
	eq(checks.ECON_RECHECKS_PER_YEAR, 12)
end)

-- state v6, tier counts --------------------------------------------------------------

local SETTINGS_DEFAULT = settings.defaults()

test("upgradeState: v5 -> v6 keeps alerts, timers, notify maps and pending; adds useAvg and tier counts", function()
	local a = { id = "line_broken:1", kind = "line_broken", tab = "lines", tier = 1, entity = 1, firstSeen = 5 }
	local p = { id = "fleet_worn:2", kind = "fleet_worn", tab = "fleet", tier = 3, entity = 2, firstSeen = 6 }
	local mem = { stoppedSince = { [7] = 100 }, blockedSince = { [8] = 50 }, blockedBy = { [8] = 9 }, overloadSince = { [3] = 40 },
		underusedSince = {}, bunchingSince = { [4] = 1 } }
	local v5settings = {}
	for k, v in pairs(SETTINGS_DEFAULT) do v5settings[k] = v end
	v5settings.econLossWarnPct, v5settings.econLossCritPct, v5settings.econLowUsePct = nil, nil, nil
	v5settings.lineSustainMin = 7
	local v5 = { version = 5, settings = v5settings, alerts = { a }, total = 4, kindCounts = { line_broken = 1, fleet_worn = 3 },
		memory = mem, notified = { ["line_broken:1"] = 5 }, notifyCleared = { ["x:1"] = 2 }, pending = { p } }
	local s, changed = checks.upgradeState(v5)
	ok(changed, "saved once as v6")
	eq(s.version, 6)
	eq(s.alerts, { a })
	eq(s.total, 4)
	eq(s.kindCounts, { line_broken = 1, fleet_worn = 3 })
	eq(s.notified, { ["line_broken:1"] = 5 })
	eq(s.notifyCleared, { ["x:1"] = 2 })
	eq(s.pending, { p })
	eq(s.memory, { stoppedSince = { [7] = 100 }, blockedSince = { [8] = 50 }, blockedBy = { [8] = 9 }, overloadSince = { [3] = 40 },
		underusedSince = {}, bunchingSince = { [4] = 1 }, useAvg = {} })
	eq(s.tierCounts, { 1, 0, 3 }, "stored row by its tier, the rest by the kind's tier")
	eq(s.settings.lineSustainMin, 7)
	eq(s.settings.econLossWarnPct, 75, "new settings get defaults")
	eq(s.settings.notify.line_unprofitable, "passive")
	eq(mem.useAvg, nil, "v5 memory not mutated")
	local _, again = checks.upgradeState(s)
	eq(again, false, "stable after migration")
end)

test("upgradeState: a v6 state keeps its averages; broken useAvg or tier counts are repaired", function()
	local s0 = checks.freshState()
	s0.memory.useAvg[3] = { 2500, 0, 100 }
	local s, changed = checks.upgradeState(s0)
	eq(changed, false)
	ok(s.memory == s0.memory, "memory kept by reference")
	local bad = checks.freshState()
	bad.memory.useAvg = "x"
	bad.memory.stoppedSince[1] = 5
	local s2, c2 = checks.upgradeState(bad)
	ok(c2)
	eq(s2.memory.useAvg, {})
	eq(s2.memory.stoppedSince, { [1] = 5 })
	local bad2 = checks.freshState()
	bad2.tierCounts = { 1, "x" }
	local s3, c3 = checks.upgradeState(bad2)
	ok(c3)
	eq(s3.tierCounts, { 0, 0, 0 })
end)

test("tierCounts + merge: economy rows count at their own tier; a tier change alone is a change", function()
	local s = checks.freshState()
	s.settings.smoothSec = 0
	local function row(id, tier)
		return { id = "line_unprofitable:" .. id, kind = "line_unprofitable", tab = "economy", tier = tier, entity = id,
			etype = "Line", label = "", context = "", code = "Loss" }
	end
	local m1, c1 = checks.merge(s, "lines", { row(1, 1), row(2, 3) }, 10)
	ok(c1)
	eq(m1.tierCounts, { 1, 0, 1 })
	eq(m1.kindCounts, { line_unprofitable = 2 })
	local m2, c2 = checks.merge(m1, "lines", { row(1, 2), row(2, 3) }, 20)
	ok(c2, "tier changed")
	eq(m2.tierCounts, { 0, 1, 1 })
	local _, c3 = checks.merge(m2, "lines", { row(1, 2), row(2, 3) }, 30)
	eq(c3, false)
	-- over the stored cap: unknown rows count at the kind's (mildest) tier
	eq(checks.tierCounts({ row(1, 1) }, { line_unprofitable = 3, veh_stuck = 2 }), { 3, 0, 2 })
	eq(checks.tierCounts(nil, nil), { 0, 0, 0 })
end)

test("model.counts: tiers from the state's tierCounts when they add up, else per kind", function()
	local c = model.counts({ line_unprofitable = 2, fleet_worn = 1 }, "badge", { 1, 1, 1 })
	eq(c.tierCounts, { 1, 1, 1 })
	eq(c.worstTier, 1)
	eq(c.total, 3)
	local c2 = model.counts({ line_unprofitable = 2, fleet_worn = 1 }, "badge", { 5, 0, 0 })
	eq(c2.tierCounts, { 0, 0, 3 }, "inconsistent: by catalogue tier")
	eq(c2.worstTier, 3)
	eq(model.counts({ line_low_use = 1 }, "badge", nil).tierCounts, { 0, 0, 1 })
	eq(model.counts({}, "badge", { 0, 0, 0 }).worstTier, 0)
end)

-- settings -------------------------------------------------------------------------

test("settings: economy thresholds validated (integers in range), reset covers them", function()
	eq(settings.NUMBERS.econLossWarnPct, { default = 75, min = 1, max = 99, unit = "%" })
	eq(settings.NUMBERS.econLossCritPct, { default = 50, min = 1, max = 99, unit = "%" })
	eq(settings.NUMBERS.econLossSharePct, { default = 2, min = 1, max = 50, unit = "%" })
	eq(settings.NUMBERS.econLowUsePct, { default = 20, min = 1, max = 90, unit = "%" })
	local s, changed, rejected = settings.apply(settings.defaults(), { econLossWarnPct = 80, econLowUsePct = 15.0 })
	ok(changed)
	eq(rejected, {})
	eq(s.econLossWarnPct, 80)
	eq(s.econLowUsePct, 15)
	local _, c2, r2 = settings.apply(settings.defaults(), { econLossCritPct = 0, econLowUsePct = 91, econLossWarnPct = 50.5 })
	eq(c2, false)
	eq(r2, { "econLossCritPct", "econLossWarnPct", "econLowUsePct" })
	eq(settings.normalize({ econLossCritPct = 100 }).econLossCritPct, 50, "out of range from a save: default")
	local reset, rc = settings.reset(s, {})
	ok(rc)
	eq(reset.econLossWarnPct, 75)
	eq(reset.econLowUsePct, 20)
	eq(settings.NOTIFY_DEFAULTS.line_unprofitable, "passive")
	eq(settings.NOTIFY_DEFAULTS.line_low_use, "passive")
	local _, c3, r3 = settings.apply(settings.defaults(), { notify = { line_low_use = "off" } })
	ok(c3)
	eq(r3, {})
end)

-- model texts ------------------------------------------------------------------------

test("model: line_unprofitable detail, money metric, tier label and icon", function()
	eq(model.formatMoney(-1200000), "-1,200,000")
	eq(model.formatMoney(999), "999")
	eq(model.formatMoney(1000), "1,000")
	-- short cell texts (about 45 characters), every combination; 3-part args from older saves
	eq(model.detailText("line_unprofitable", "Loss", "-1200000|4|65|7"), "Earns 65% of costs · 7% of all line costs")
	eq(model.detailText("line_unprofitable", "Loss", "-1200000|4|65|0"), "Earns 65% of costs · <1% of all line costs")
	eq(model.detailText("line_unprofitable", "Loss", "-1200000|4|65"), "Earns 65% of its costs · 4/4 quarters lost")
	eq(model.detailText("line_unprofitable", "Loss", "-1200000|3|65|"), "Earns 65% of its costs · 3/4 quarters lost")
	eq(model.detailText("line_unprofitable", "LossNoSplit", "-500|3||12"), "Loss 12% of all line costs · 3/4 quarters")
	eq(model.detailText("line_unprofitable", "LossNoSplit", "-500|3|"), "Lost money in 3/4 quarters")
	for _, arg in ipairs({ "-1200000|4|65|7", "-1200000|4|65|0", "-500|3||12" }) do
		ok(#model.detailText("line_unprofitable", "Loss", arg) <= 46, arg .. " fits the detail column")
	end
	-- the full sentence for the tooltip / notification
	eq(model.tipText("line_unprofitable", "-1200000|4|65|7"), "Lost 1,200,000 in 12 months (4/4 quarters negative). "
		.. "Income covers about 65% of its vehicle costs. The loss is 7% of all lines' vehicle costs.")
	eq(model.tipText("line_unprofitable", "-500|3|"), "Lost 500 in 12 months (3/4 quarters negative).")
	eq(model.tipText("line_unprofitable", "junk"), nil)
	eq(model.tipText("line_low_use", "7|12"), nil)
	eq(model.detailText("line_unprofitable", "Loss", "junk"), "Lost money over the last 12 months")
	eq(model.detailText("line_unprofitable", "Loss", nil), "Lost money over the last 12 months")
	local row = model.decorate({ id = "line_unprofitable:1", kind = "line_unprofitable", tab = "economy", tier = 2, label = "Coal",
		context = "", etype = "Line", code = "Loss", arg = "-1200000|4|65", metric = "-1200000", firstSeen = 0 })
	eq(row.metric, "-1,200,000")
	eq(row.tip, "Lost 1,200,000 in 12 months (4/4 quarters negative). Income covers about 65% of its vehicle costs.")
	eq(row.kindLabel, "Losing money")
	eq(row.typeLabel, "Line")
	-- the GUI scripts plug in api.util.formatMoney
	local saved = model.formatMoney
	model.formatMoney = function(m) return "$" .. tostring(m) end
	eq(model.tipText("line_unprofitable", "-500|3|"), "Lost $500 in 12 months (3/4 quarters negative).")
	model.formatMoney = saved
	eq(model.kindTierLabel("line_unprofitable"), "Info to Critical")
	eq(model.kindTierLabel("line_underused"), "Info")
	eq(model.kindTierLabel("veh_stuck"), "Critical")
	local title, desc, icon = model.notificationText({ kind = "line_unprofitable", tier = 1, etype = "Line", label = "Coal",
		code = "Loss", arg = "-1000|4|0", metric = "-1000" })
	eq(title, "Losing money: Coal")
	eq(desc, "Lost 1,000 in 12 months (4/4 quarters negative). Income covers about 0% of its vehicle costs.")
	eq(icon, "::/game_mechanics/finance/icons/symbol_coin_stack.tga")
end)

test("model: line_low_use detail and the Economy tab", function()
	eq(model.detailText("line_low_use", "LowUse", "7|12"), "7% used on average over the last year")
	eq(model.detailText("line_low_use", "LowUse", "7|8"), "7% used on average over 8 months")
	eq(model.detailText("line_low_use", "LowUse", nil), "Vehicles mostly empty over a long time")
	local _, _, icon = model.notificationText({ kind = "line_low_use", tier = 3, label = "X", arg = "7|12" })
	eq(icon, "::/game_mechanics/notifications/gui/icons/line_minus.tga")
	local v = model.buildRaw({ alerts = {
		{ id = "line_low_use:1", kind = "line_low_use", tab = "economy", tier = 1, entity = 1, firstSeen = 1 },
		{ id = "line_unprofitable:2", kind = "line_unprofitable", tab = "economy", tier = 3, entity = 2, firstSeen = 1 },
	}, kindCounts = { line_low_use = 1, line_unprofitable = 2 } })
	eq(v.tabCounts.economy, 3)
	eq(v.hiddenByTab.economy, 1)
	eq(v.tierCounts, { 1, 0, 2 })
	eq(#model.rowsForTab(v, "economy"), 2)
	eq(model.kindLabel("line_low_use"), "Low use")
end)
