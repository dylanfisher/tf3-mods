-- Supply-driven district weighting, "Town growth: By deliveries" (§66, 2026-10-15; ot_rci + the driver wiring).
-- The formula (usage as the base game reads it, smoothing, aim with floors, the step's caps and floors, no NaN), a
-- lopsided town converging without overshoot while the total grows as in the base game, Act on Off / Game default /
-- New towns only, the FILL restore keeping the weighted values, the per-tick cap, the saved state.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local RCI = ug_require(F.DIR .. "ot_rci.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local PA = ug_require(F.DIR .. "ot_params.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local DT = ug_require(F.DIR .. "ot_district.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local function isNum(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end

test("usage: the base game's weights (line use x 2 averaged with residential cargo, cargo supply / demand)", function()
	local u = RCI.usage({ line = 0.3, mult = 2, res = { 0, 0 }, com = { 30, 60 }, ind = { 90, 100 } })
	near(u[1], 0.6)
	near(u[2], 0.5)
	near(u[3], 0.9)
	-- residential cargo demand: averaged with the line use
	u = RCI.usage({ line = 0.1, mult = 2, res = { 50, 100 }, com = { 0, 0 }, ind = { 0, 0 } })
	near(u[1], (0.2 + 0.5) / 2)
	eq(u[2], 0)
	eq(u[3], 0)
	-- clamped: line use x 2 above 1, supply above demand
	u = RCI.usage({ line = 0.9, res = { 0, 0 }, com = { 200, 100 }, ind = { 5, 0 } })
	eq(u, { 1, 1, 0 })
	eq(RCI.usage(nil), nil)
	-- NaN / garbage reads become 0
	u = RCI.usage({ line = 0 / 0, res = "x", com = { 0 / 0, 10 }, ind = { 1, 1 / 0 } })
	for k = 1, 3 do ok(isNum(u[k]) and u[k] >= 0 and u[k] <= 1, "usage " .. k) end
end)

test("smooth: first sight is the usage, then an exponential approach in game years; aim: floors, none without deliveries", function()
	local e = RCI.smooth(nil, { 0.2, 0, 1 })
	eq(e, { 0.2, 0, 1 })
	local e0 = RCI.smooth(e, { 1, 1, 0 }, 0)
	eq(e0, e, "no time passed: unchanged")
	local e1 = RCI.smooth(e, { 1, 1, 0 }, RCI.TAU_YEARS)
	near(e1[1], 0.2 + 0.8 * (1 - math.exp(-1)), 1e-9)
	local eL = RCI.smooth(e, { 1, 1, 0 }, 100)
	near(eL[1], 1, 1e-6)
	near(eL[3], 0, 1e-6)
	local eN = RCI.smooth(e, { 0 / 0, 2, -1 }, 0 / 0)
	for k = 1, 3 do ok(isNum(eN[k]) and eN[k] >= 0 and eN[k] <= 1) end
	eq(RCI.aim({ 0, 0, 0 }), nil, "no deliveries: no aim")
	local w = RCI.aim({ 0, 0, 1 })
	near(w[1], RCI.FLOOR)
	near(w[2], RCI.FLOOR)
	near(w[3], 1 - 2 * RCI.FLOOR)
	w = RCI.aim({ 0.5, 0.5, 0.5 })
	near(w[1] + w[2] + w[3], 1, 1e-12)
	near(w[1], 1 / 3, 1e-12)
end)

test("step: guards (bad values, small town, no aim, no growth, at the mix)", function()
	eq(RCI.step(nil).why, "bad")
	eq(RCI.step({ init = { 100, 0, 100 }, sf = { 1, 1, 1 }, w = { 0.3, 0.3, 0.4 }, grown = 50 }).why, "bad")
	eq(RCI.step({ init = { 100, 100, 100 }, sf = { 1, 0 / 0, 1 }, w = { 0.3, 0.3, 0.4 }, grown = 50 }).why, "bad")
	eq(RCI.step({ init = { 10, 10, 10 }, sf = { 1, 1, 1 }, w = { 0.3, 0.3, 0.4 }, grown = 5 }).why, "small")
	eq(RCI.step({ init = { 100, 100, 100 }, sf = { 1, 1, 1 }, w = nil, grown = 50 }).why, "noAim")
	eq(RCI.step({ init = { 100, 100, 100 }, sf = { 1, 1, 1 }, w = { 0.2, 0.2, 0.6 }, grown = 0 }).why, "noGrowth")
	eq(RCI.step({ init = { 100, 100, 100 }, sf = { 1, 1, 1 }, w = { 0.2, 0.2, 0.6 }, grown = -40 }).why, "noGrowth")
	eq(RCI.step({ init = { 100, 100, 100 }, sf = { 2, 2, 2 }, w = { 1 / 3, 1 / 3, 1 / 3 }, grown = 100 }).why, "atMix")
end)

test("step: moves toward the aim by at most the budget, keeps the initial sum, never past the aim", function()
	local o = { init = { 400, 300, 300 }, sf = { 1.5, 1.5, 1.5 }, uses = { 0, 0, 0 }, w = { 0.2, 0.2, 0.6 }, grown = 1500 }
	local r = RCI.step(o)
	eq(r.why, "ok")
	eq(r.list[1] + r.list[2] + r.list[3], 1000, "the initial sum kept: the game's next total target is the base game's")
	ok(r.move <= RCI.STEP_MAX + 0.002, "at most STEP_MAX per step")
	ok(r.list[3] > 300 and r.list[1] < 400, "industrial up, residential down")
	ok(math.abs(r.S1 / r.S - 1) <= RCI.TOTAL_DEV)
	-- a small growth: the budget is the growth (MOVE_K x grown / S)
	o.grown = 15   -- 1 % of S 1500
	r = RCI.step(o)
	eq(r.why, "ok")
	ok(r.move <= 0.01 + 0.002, "the growth's share at most: " .. r.move)
	-- near the aim: lands on it, never past it
	o = { init = { 205, 200, 595 }, sf = { 1, 1, 1 }, uses = { 0, 0, 0 }, w = { 0.2, 0.2, 0.6 }, grown = 500 }
	r = RCI.step(o)
	eq(r.why, "ok")
	eq(r.list, { 200, 200, 600 })
end)

test("step: the built floor keeps a losing district at its built capacity; the ceiling lets the gainers rise a little", function()
	-- residential built at its whole target: it can't lose, the sum would have to rise
	local o = { init = { 400, 300, 300 }, sf = { 1, 1, 1 }, uses = { 400, 300, 300 }, w = { 0.2, 0.2, 0.6 }, grown = 300 }
	local r = RCI.step(o)
	eq(r.why, "ok", "the ceiling's room: " .. tostring(r.why))
	ok(r.list[1] >= 400 and r.list[2] >= 300, "no district below what is built")
	ok(r.N1 <= math.floor(1000 * (1 + RCI.CEIL)), "the sum at most CEIL above n0")
	-- the ceiling used up (n0 lower): blocked
	o.n0 = 1000 / (1 + RCI.CEIL) - 1
	o.init = { 400, 300, 300 }
	r = RCI.step(o)
	eq(r.why, "built")
	-- partly built: the losers go down to their built capacity, not below
	o = { init = { 400, 300, 300 }, sf = { 2, 2, 2 }, uses = { 790, 400, 400 }, w = { 0.2, 0.2, 0.6 }, grown = 2000 }
	r = RCI.step(o)
	eq(r.why, "ok")
	ok(r.list[1] * 2 >= 790 - 1e-9, "residential target >= built")
	ok(r.list[2] * 2 >= 400 - 1e-9)
end)

-- the base game's split of an increase (town_growth.script.tl): weights by usage, pinned to [minW, maxW], the maximum
-- dampened from 1 toward 0.5 as a district passes 40 % of the town (a simplified rebalance, no map-wide damping)
local function gameSplit(usage, cur, extra, minW)
	local tot = usage[1] + usage[2] + usage[3]
	if tot <= 0 then return { 0, 0, 0 } end
	local w = { usage[1] / tot, usage[2] / tot, usage[3] / tot }
	local S = cur[1] + cur[2] + cur[3] + extra
	local maxW = {}
	for k = 1, 3 do
		local share = (cur[k] + w[k] * extra) / S
		maxW[k] = 1
		if share >= 0.4 then maxW[k] = 1 - (math.min(share, 0.5) - 0.4) / 0.1 * 0.5 end
	end
	for _ = 1, 8 do
		local sum = 0
		for k = 1, 3 do
			w[k] = math.max(minW, math.min(maxW[k], w[k]))
			sum = sum + w[k]
		end
		for k = 1, 3 do w[k] = w[k] / sum end
	end
	return { w[1] * extra, w[2] * extra, w[3] * extra }
end

--- A town over `years` game years: the game grows its total target toward Σ init x F (F +rate per month), splits each
--- increase (gameSplit), builds `buildK` of the gap per month; the weighting steps monthly when `on`.
local function simulate(o)
	local init = { o.init[1], o.init[2], o.init[3] }
	local sf = { 1, 1, 1 }
	local uses = { init[1], init[2], init[3] }
	local F = 1
	local e, Sprev, n0 = nil, nil, nil
	local hist = {}
	for m = 1, o.years * 12 do
		F = F * (1 + o.rate)
		local cur = { init[1] * sf[1], init[2] * sf[2], init[3] * sf[3] }
		local S = cur[1] + cur[2] + cur[3]
		local N = init[1] + init[2] + init[3]
		local extra = N * F - S
		if extra > 0 then
			local add = gameSplit(o.usage, cur, extra, 0.1)
			for k = 1, 3 do sf[k] = (cur[k] + add[k]) / init[k] end
		end
		for k = 1, 3 do
			local L = init[k] * sf[k]
			if uses[k] < L then uses[k] = uses[k] + (L - uses[k]) * o.buildK end
		end
		if o.on then
			e = RCI.smooth(e, o.usage, 1 / 12)
			local w = RCI.aim(e)
			local s, St = RCI.shares(init, sf)
			if Sprev == nil or St < Sprev then Sprev = St end
			local r = RCI.step({ init = init, sf = sf, uses = uses, w = w, grown = St - Sprev, n0 = n0 })
			if r.why == "ok" then
				n0 = n0 or r.N
				init = r.list
				Sprev = r.S1
			elseif r.why ~= "noGrowth" and r.why ~= "tiny" then
				Sprev = St
			end
			hist[#hist + 1] = { s = s, w = w }
		end
	end
	local s, S = RCI.shares(init, sf)
	return { s = s, S = S, N = init[1] + init[2] + init[3], hist = hist, init = init }
end

test("a lopsided town converges toward its aim without overshoot; the total stays the base game's", function()
	-- fed only industrial cargo, no passengers: aim 12 / 12 / 76
	local usage = { 0, 0, 1 }
	local base = simulate({ init = { 400, 300, 300 }, usage = usage, years = 20, rate = 0.006, buildK = 0.5, on = false })
	local mod = simulate({ init = { 400, 300, 300 }, usage = usage, years = 20, rate = 0.006, buildK = 0.5, on = true })
	ok(base.s[3] <= 0.52, string.format("the base game evens it out: industrial %.2f", base.s[3]))
	ok(mod.s[3] >= 0.6, string.format("weighted: industrial %.2f (a mill town)", mod.s[3]))
	local w = RCI.aim(usage)
	local prev = nil
	for i, h in ipairs(mod.hist) do
		ok(h.s[3] <= w[3] + 0.005, "never past the aim at month " .. i)
		if prev then ok(h.s[3] >= prev - 0.006, "no step back at month " .. i) end
		prev = h.s[3]
	end
	ok(math.abs(mod.S / base.S - 1) <= RCI.CEIL + 0.02, string.format("total %.0f vs base %.0f", mod.S, base.S))
	ok(mod.N <= math.floor(1000 * (1 + RCI.CEIL)), "the initial sum at most CEIL above its start")
	-- a passenger town: mostly residential
	local res = simulate({ init = { 400, 300, 300 }, usage = { 1, 0, 0 }, years = 20, rate = 0.006, buildK = 0.5, on = true })
	ok(res.s[1] >= 0.6, string.format("passengers only: residential %.2f", res.s[1]))
	-- a town that never grows: never moved (an old save's stagnant town)
	local still = simulate({ init = { 400, 300, 300 }, usage = { 0, 0, 1 }, years = 5, rate = 0, buildK = 0.5, on = true })
	eq(still.init, { 400, 300, 300 })
end)

test("an old save's town adjusts with its growth only, by STEP_MAX per month at most (no jump)", function()
	local init = { 2000, 1500, 1500 }
	local sf = { 3, 3, 3 }
	local r = RCI.step({ init = init, sf = sf, uses = { 0, 0, 0 }, w = { 0.12, 0.12, 0.76 }, grown = 1e6 })
	eq(r.why, "ok")
	ok(r.move <= RCI.STEP_MAX + 1e-3, "one month: at most STEP_MAX however much it grew: " .. r.move)
	ok(math.abs(r.S1 / r.S - 1) <= RCI.TOTAL_DEV)
end)

test("sweep: every step keeps its invariants (no NaN, sums, floors, caps, no overshoot)", function()
	local STRIDE = FULL and 1 or 5
	local inits = { { 100, 100, 100 }, { 400, 300, 300 }, { 10, 10, 200 }, { 2000, 200, 50 }, { 1, 1, 1000 } }
	local sfs = { { 1, 1, 1 }, { 3, 1.2, 0.8 }, { 0.5, 4, 2 } }
	local usesK = { 0, 0.5, 0.9, 1.0, 1.2 }
	local aims = { { 0.12, 0.12, 0.76 }, { 0.76, 0.12, 0.12 }, { 0.12, 0.76, 0.12 }, { 1 / 3, 1 / 3, 1 / 3 }, { 0.5, 0.3, 0.2 } }
	local growns = { 0, 1, 10, 100, 1e4 }
	local n, i = 0, 0
	for _, init in ipairs(inits) do
		for _, sf in ipairs(sfs) do
			for _, uk in ipairs(usesK) do
				for _, w in ipairs(aims) do
					for _, g in ipairs(growns) do
						i = i + 1
						if i % STRIDE == 0 or (uk == 1.0 and g == 100) then
							n = n + 1
							local uses = { init[1] * sf[1] * uk, init[2] * sf[2] * uk, init[3] * sf[3] * uk }
							local N = init[1] + init[2] + init[3]
							local r = RCI.step({ init = init, sf = sf, uses = uses, w = w, grown = g * (init[1] + init[2] + init[3]) / 100 })
							local tag = string.format("#%d %s", i, r.why)
							if r.why == "ok" then
								local sum = 0
								for k = 1, 3 do
									ok(isNum(r.list[k]) and r.list[k] >= 1 and r.list[k] == math.floor(r.list[k]), tag)
									sum = sum + r.list[k]
									if r.list[k] < init[k] then
										ok(r.list[k] * sf[k] >= uses[k] - sf[k] - 1e-6, tag .. " built floor " .. k)
									end
									-- no overshoot: each share moves toward its aim (a unit's rounding aside)
									local tol = 1.5 * sf[k] / r.S1 + 1e-6
									if w[k] >= r.s[k] then ok(r.s1[k] <= w[k] + tol, tag .. " past aim " .. k)
									else ok(r.s1[k] >= w[k] - tol, tag .. " past aim " .. k) end
								end
								ok(sum >= N - 1 and sum <= math.floor(N * (1 + RCI.CEIL)), tag .. " sum " .. sum)
								ok(math.abs(r.S1 / r.S - 1) <= RCI.TOTAL_DEV + 1e-9, tag .. " total")
								ok(r.move <= RCI.STEP_MAX + 3 * math.max(sf[1], sf[2], sf[3]) / r.S1 + 1e-6, tag .. " move")
							else
								eq(r.list, nil, tag)
							end
						end
					end
				end
			end
		end
	end
	ok(n >= (FULL and 1875 or 300), "cases " .. n)
end)

test("lean and the chance multipliers (the visual tie-in)", function()
	eq(RCI.lean({ 0.4, 0.3, 0.3 }), nil, "a base-game town leans nowhere")
	eq(RCI.lean({ 0.47, 0.5, 0.03 }), nil, "the base game's maxima: no lean")
	eq(RCI.lean({ 0.2, 0.15, 0.65 }), "ind")
	eq(RCI.lean({ 0.6, 0.2, 0.2 }), "res")
	eq(RCI.lean({ 0.25, 0.55, 0.2 }), "com")
	eq(RCI.chanceMul(nil, "works"), 1)
	ok(RCI.chanceMul("ind", "works") > 1 and RCI.chanceMul("ind", "district") < 1)
	ok(RCI.chanceMul("res", "district") > 1 and RCI.chanceMul("res", "lead") > 1)
	-- the Works draw: a seed that is "rare" at CHANCE founds with an industrial lean's multiplier
	local base = { fresh = true, buildings = 500, seed = nil }
	local found = nil
	for seed = 1, 400 do
		base.seed = seed
		local a = WK.eligible(base)
		base.chanceMul = 2
		local b = WK.eligible(base)
		base.chanceMul = nil
		if not a and b then found = seed break end
	end
	ok(found ~= nil, "some seed founds only with the lean")
	local dOk = DT.eligible({ fresh = true, buildings = 500, seed = 1, chanceMul = 0 })
	eq(dOk, false, "chanceMul 0: never")
end)

---------------------------------------------------------------------------
-- driver wiring

local function fakeEngine(o)
	o = o or {}
	local E = { t = 0, logs = {}, events = {}, writes = {}, year = 1950, caps = {}, supply = {}, levels = {} }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.towns()
		local out = {}
		for id in pairs(E.caps) do out[#out + 1] = id end
		table.sort(out)
		return out
	end
	function E.name(t) return "Town" .. t end
	function E.yearF() return E.year end
	function E.townCaps(t)
		local c = E.caps[t]
		if c == nil then return nil end
		local out = { initials = { c.init[1], c.init[2], c.init[3] }, sizeFactors = { c.sf[1], c.sf[2], c.sf[3] },
			uses = { c.uses[1], c.uses[2], c.uses[3] }, initial = 0, target = 0, actual = 0 }
		for k = 1, 3 do
			out.initial = out.initial + c.init[k]
			out.target = out.target + c.init[k] * c.sf[k]
			out.actual = out.actual + c.uses[k]
		end
		return out
	end
	function E.townSupply(t) return E.supply[t] end
	function E.setInitialCaps(t, list, cb)
		E.writes[#E.writes + 1] = { t = t, list = { list[1], list[2], list[3] } }
		E.caps[t].init = { list[1], list[2], list[3] }
		if o.engineLevels then E.levels[t] = { { 0.5, 0, 0, 0 }, { 0.5, 0, 0, 0 }, { 0.5, 0, 0, 0 } } end
		cb(true)
	end
	function E.levelInfo(t) return { custom = E.levels[t] } end
	function E.setLevelWeights(t, w, cb)
		E.levels[t] = w
		E.levelSets = (E.levelSets or 0) + 1
		cb(true)
	end
	function E.sendEvent(_id, name, param) E.events[#E.events + 1] = { name = name, param = param } end
	function E.modParams() return o.params or {}, {} end
	return E
end

local function newDriver(E, params)
	local d = D.new(E)
	d.opts = PA.parse(params or {}, {})
	d.phase = "run"
	return d
end

local function grow(E, t, k)
	local c = E.caps[t]
	for i = 1, 3 do c.sf[i] = c.sf[i] * k end
end

--- Runs the driver's weighting for `months` game months, `ticks` ticks per month (1 s apart), growing each town by
--- `k` per month. Returns the RCI write lines.
local function run(d, E, saved, months, k, ticks)
	for _ = 1, months do
		E.year = E.year + 1 / 12
		for t in pairs(E.caps) do grow(E, t, k) end
		for _ = 1, ticks or 8 do
			E.t = E.t + 1e6
			d:rciTick(E.t, saved)
		end
	end
end

local function lines(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do
		if l:find("[SQOT] " .. what .. " ", 1, true) then out[#out + 1] = l end
	end
	return out
end

local function indTown(E, t)
	E.caps[t] = { init = { 400, 300, 300 }, sf = { 1, 1, 1 }, uses = { 200, 150, 150 } }
	E.supply[t] = { line = 0, mult = 2, res = { 0, 0 }, com = { 0, 50 }, ind = { 90, 100 } }
end

test("driver: By deliveries re-splits an industrial town through setInitialCaps; RCI line; saved event", function()
	local E = fakeEngine()
	indTown(E, 7)
	local d = newDriver(E, { act_on = 3 })
	eq(d.opts.townGrowth, "deliveries", "the default")
	run(d, E, {}, 6, 1.05)
	ok(#E.writes >= 3, "writes: " .. #E.writes)
	local c = E.caps[7].init
	eq(c[1] + c[2] + c[3], 1000, "the initial sum kept")
	ok(c[3] > 300 and c[1] < 400)
	local l = lines(E, "RCI")
	ok(#l >= 3)
	ok(l[1]:find("r/c/i=40/30/30->", 1, true) and l[1]:find("caps=400,300,300->", 1, true) and l[1]:find("supply=", 1, true), l[1])
	local ev = E.events[#E.events]
	eq(ev.name, SV.EV_RCI)
	eq(ev.param.town, 7)
	eq(ev.param.n0, 1000)
	-- the saved event applies and reads back
	local s = SV.applyRci(nil, ev.param)
	local back = SV.rci(s, 7)
	ok(back ~= nil and back.k == ev.param.k and back.n0 == 1000)
	eq(d:rciLean(7), "ind", "45 % industrial after five steps")
	ok(d:rciManaged(7))
	ok(l[1]:find("aim=12/12/76", 1, true) and l[1]:find("sum=1000->1000", 1, true), l[1])
	ok(d:rciText(7):find("aim=12/12/76:use=0.00/0.00/0.90", 1, true), d:rciText(7))
	-- the dev readout (ALLTOWN rci=, the inspector): the engine's reads, then the main driver's state
	local ro = D.rciReadout(E, 7, d)
	ok(ro:find("31/24/45:use=0.00/0.00/0.90:aim=12/12/76:lean=ind|main:", 1, true), ro)
	eq(D.rciReadout(E, 99, nil), "-:use=-:aim=-:lean=-", "an unknown town")
end)

test("driver: Act on Off and Game default do nothing; New towns only skips the known towns and the mod's offshoots", function()
	local E = fakeEngine()
	indTown(E, 7)
	local d = newDriver(E, { act_on = 1 })
	run(d, E, {}, 6, 1.05)
	eq(#E.writes, 0, "Act on Off")
	E = fakeEngine()
	indTown(E, 7)
	d = newDriver(E, { act_on = 3, town_growth = 2 })
	eq(d.opts.townGrowth, "game")
	run(d, E, {}, 6, 1.05)
	eq(#E.writes, 0, "Game default")
	eq(d:rciLean(7), nil)
	E = fakeEngine()
	indTown(E, 7)
	indTown(E, 8)
	indTown(E, 9)
	d = newDriver(E, { act_on = 2 })
	local saved = { v = SV.VERSION, known = { 7 }, frames = {}, wk = { 9 } }
	run(d, E, saved, 6, 1.05)
	for _, w in ipairs(E.writes) do
		ok(w.t == 8, "only the new, non-offshoot town: " .. w.t)
	end
	ok(#E.writes > 0)
end)

test("driver: one command per tick, RCI_PER_TICK towns per tick, never beside a job or a command in flight", function()
	local E = fakeEngine()
	for t = 1, 20 do indTown(E, t) end
	local d = newDriver(E, { act_on = 3 })
	-- the first sight of every town (no growth yet: nothing sent), PER_TICK towns per tick
	E.t = 1e6
	d:rciTick(E.t, {})
	local seen = 0
	for _, s in pairs(d.towns) do if s.rci then seen = seen + 1 end end
	eq(seen, D.RCI_PER_TICK)
	-- the tick pace
	d:rciTick(E.t + 1000, {})
	seen = 0
	for _, s in pairs(d.towns) do if s.rci then seen = seen + 1 end end
	eq(seen, D.RCI_PER_TICK, "not again within RCI_TICK_S")
	for _ = 1, 10 do E.t = E.t + 1e6; d:rciTick(E.t, {}) end
	E.year = E.year + 1 / 12
	for t = 1, 20 do grow(E, t, 1.1) end
	local before = #E.writes
	E.t = E.t + 1e6
	d:rciTick(E.t, {})
	eq(#E.writes - before, 1, "one command per tick")
	-- a job running or a command in flight: nothing
	before = #E.writes
	d.job = { town = 3, stage = "fill" }
	for _ = 1, 5 do E.t = E.t + 1e6; d:rciTick(E.t, {}) end
	eq(#E.writes, before)
	d.job = nil
	d.inflight = true
	for _ = 1, 5 do E.t = E.t + 1e6; d:rciTick(E.t, {}) end
	eq(#E.writes, before)
	d.inflight = false
	-- the time budget: a slow engine stops the walk after the first town
	E.t = E.t + 1e6
	local slow = E.nowUs
	local calls = 0
	E.nowUs = function() calls = calls + 1; return E.t + calls * (D.RCI_BUDGET_US + 1) end
	d.rciNextUs = 0
	local cur0 = d.rciCursor
	d:rciTick(E.t, {})
	E.nowUs = slow
	ok(d.rciCursor == (cur0 % 20) + 1, "one town within the budget")
end)

test("driver: the FILL restore puts a weighted town's values back exactly (D.restoreExact), others as before", function()
	eq(D.restoreExact({ 380, 300, 320 }, { 200, 150, 160 }), { 380, 300, 320 }, "DevelopAt lowered all three: back")
	eq(D.restoreExact({ 380, 300, 320 }, { 380, 300, 320 }), nil, "unchanged: no command")
	-- the old rule would leave the lowered districts lowered
	eq(D.restoreCaps({ 380, 300, 320 }, { 200, 150, 160 }, nil, 0), nil)
	local E = fakeEngine()
	indTown(E, 7)
	local d = newDriver(E, { act_on = 3 })
	run(d, E, {}, 4, 1.05)
	ok(d:rciManaged(7))
	local w = E.caps[7].init
	local weighted = { w[1], w[2], w[3] }
	-- a dose: DevelopAt resets the capacities to the built ones, then the restore
	E.caps[7].init = { 200, 150, 150 }
	local job = { town = 7, fillRun = { rec = { kind = "dose", initials0 = weighted } } }
	local sent = d:fillRestore(job, E.t)
	ok(sent)
	eq(E.caps[7].init, weighted, "the weighting kept")
	local l = lines(E, "FILL restore")
	ok(l[#l]:find("rci=keep", 1, true), l[#l])
end)

test("driver: a write that changed a town's level weights puts them back (the mod's own: the §58 refill path)", function()
	local E = fakeEngine({ engineLevels = true })
	indTown(E, 7)
	local d = newDriver(E, { act_on = 3 })
	run(d, E, {}, 3, 1.05)
	ok(#E.writes > 0)
	eq(E.levels[7], nil, "the engine's write undone: back to the game's default")
	ok((E.levelSets or 0) >= 1)
	ok(#lines(E, "RCI") > #E.writes, "RCI levels=putBack lines")
end)

test("saved: rc normalizes, caps entries, keeps n0 from the first event; saves from before have none", function()
	local s = SV.normalize({ v = SV.VERSION, known = {}, frames = {} })
	eq(s.rc, nil, "a save from before: no weighting")
	local s1 = SV.applyRci(s, { town = 5, e = { 100, 0, 900 }, s = 1234.4, y = 195050, n0 = 1000, k = 1 })
	local s2, ch = SV.applyRci(s1, { town = 5, e = { 110, 0, 890 }, s = 1300, y = 195058, n0 = 1040, k = 2 })
	ok(ch)
	local r = SV.rci(s2, 5)
	eq(r.n0, 1000, "the ceiling's base stays the first")
	eq(r.k, 2)
	near(r.y, 1950.58, 1e-9)
	near(r.e[3], 0.89, 1e-9)
	local _, same = SV.applyRci(s2, { town = 5, e = { 110, 0, 890 }, s = 1300, y = 195058, n0 = 1000, k = 2 })
	eq(same, false, "idempotent")
	local bad = SV.normalize({ v = SV.VERSION, rc = { ["x"] = {}, ["6"] = { e = { 0 / 0, 1, 2 }, s = 1, y = 1 },
		["7"] = { e = { 5000, -3, 2 }, s = 10, y = 1 } } })
	eq(bad.rc["6"], nil)
	eq(bad.rc["7"].e, { 1000, 0, 2 })
	-- the cap
	local big = { v = SV.VERSION, rc = {} }
	for t = 1, SV.RCI_CAP + 10 do big.rc[tostring(t)] = { e = { 1, 1, 1 }, s = 1, y = 1 } end
	local n = 0
	for _ in pairs(SV.normalize(big).rc) do n = n + 1 end
	eq(n, SV.RCI_CAP)
end)
