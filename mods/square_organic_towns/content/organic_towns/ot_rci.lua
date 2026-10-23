-- Organic Towns: supply-driven district weighting, "Town growth: By deliveries" (pure; §66, 2026-10-15).
--
-- The base game grows a town by its experience (deliveries) and splits each increase over residential, commercial and
-- industrial (R/C/I) by line use and cargo supply, then evens the split out (town_growth.script.tl rebalance2: a
-- minimum weight per district, a maximum that shrinks toward 0.5 once a district passes 40 % of the town). A played
-- base-game save (session 2026-10-15_0759_rci-sqrl, docs/findings/towns.md "District split") had 15 towns at 25-47 %
-- residential, 20-50 % commercial, 13-41 % industrial: varied, never clearly lopsided.
--
-- The lever (NTG's): a town's growth target per district is initialLandUseCapacities[i] x sizeFactors[i], the game's
-- next total target is Σ initialLandUseCapacities x its growth factor, and it never lowers the size factors. So this
-- module re-splits a town's initial capacities (the driver writes them with makeTownSetInitialLandUseCapacitiesCmd, the
-- one writer the FILL restore also uses):
--
--   usage u      = the base game's own usage weights (M.usage: line use x 2 averaged with residential cargo; commercial
--                  and industrial cargo supply / demand), read through the base town_util helpers, not recomputed
--   smoothed e   = e + (u - e) x (1 - exp(-dt / TAU_YEARS))                    (M.smooth; dt in game years)
--   aim w        = FLOORS + (1 - ΣFLOORS) x e / Σe   (M.aim; no deliveries at all: none, the town is left alone)
--   weighted     = n + f x (w - n)                   (M.weightedAim: "Delivery weighting" f, n = M.neutral 42/29/29)
--   shares s     = init x sf / Σ(init x sf)          (M.shares: the town's current target mix)
--   budget b     = min(STEP_MAX, MOVE_K x the target's growth since the last step / the target)
--   goal q       = s + (w - s) x min(1, b / Σ max(w - s, 0))                    (never past w: no overshoot)
--   new initial  = λ q / sf, λ = Σ init / Σ(q / sf)  (M.step: the initial sum is kept, so the game's next total target
--                  Σ init x growth factor is the base game's: the mix changes, not the speed)
--
-- Floors: no district's target goes below what is built (built capacity / sf, so nothing has to be torn down), and no
-- aim below its FLOORS share. A floor that blocks the losers lets the gainers take the move up to CEIL above the town's initial sum
-- when the weighting first wrote (`n0`, saved): the only way the total can grow, by CEIL at most. The current total
-- target may move by TOTAL_DEV at most per step (the move is halved until it fits). Steps under MIN_MOVE are not sent.
-- A town that does not grow is not moved (the budget is its growth), so an old save's towns turn slowly, with their
-- growth, never with a jump. Plain Lua, pre-5.3; every loop bounded (3 districts, HALVINGS).

local M = {}

M.ON = true
-- no district aims below its share (R, C, I). Residential keeps a quarter (§75, 2026-10-18: a town stays a place people
-- live in and makes its own passengers); the most residential can aim at is 0.76, commercial / industrial 0.63
M.FLOORS = { 0.25, 0.12, 0.12 }
-- (2026-10-21, user: "more gradual in speed" for every Delivery weighting: TAU 0.5 -> 1, MOVE_K 1 -> 0.67, STEP_MAX
-- 0.03 -> 0.02; a 20-point turn takes about 4 game years in a town growing 0.6 % a month, was about 3; PLAN.md 6.2
-- "Delivery weighting")
M.TAU_YEARS = 1.0       -- the usage is smoothed over about this many game years (a short delivery swing moves it less)
M.STEP_YEARS = 1 / 12   -- a town is stepped at most once per game month ...
M.STEP_S = 60           -- ... (real seconds when the game date can't be read)
M.MOVE_K = 0.67         -- the share of the target's growth since the last step that may be re-split
M.STEP_MAX = 0.02       -- share points moved per step at most
M.MIN_MOVE = 0.002      -- smaller moves are not sent
M.TOTAL_DEV = 0.04      -- the current total target may move by this share per step at most
M.CEIL = 0.05           -- the initial sum may rise this far above `n0` (only when a built floor blocks the losers)
M.HALVINGS = 6
M.MIN_TARGET = 60       -- towns with a smaller total target (persons) are left alone
-- the lean (the visual tie-in): a district whose target share is at least this marks the town's lean. Above the base
-- game's measured maxima (residential 47 %, commercial 50 %, industrial 41 %), so only a weighted town leans.
M.LEAN = { 0.55, 0.52, 0.45 }
M.LEAN_IDS = { "res", "com", "ind" }
-- the lean's offshoot / lane chance multipliers (ot_works / ot_district / ot_lead eligible draws) and whether a
-- commercial town's core doses as a densify town's (ot_upward.decide densify)
M.CHANCE_MUL = {
	ind = { works = 2.0, district = 0.6, lead = 0.8 },
	res = { works = 0.6, district = 1.5, lead = 1.5 },
	com = { works = 0.8, district = 1.0, lead = 1.0 },
}

local function finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clamp(x, a, b)
	if x < a then return a end
	if x > b then return b end
	return x
end

local function num(x)
	x = tonumber(x)
	if x == nil or not finite(x) then return 0 end
	return x
end

--- The base game's usage weights {res, com, ind} (0..1 each; town_growth.script.tl:377-412) from
--- sd = { line = getTownLineUsage, mult = town_util.LineUsageRatingMultiplier (2), res = { supply, demand },
--- com = {...}, ind = {...} } (sums over the land use's cargo types, town_util.getCargoSupplyDemands). nil -> nil.
function M.usage(sd)
	if type(sd) ~= "table" then return nil end
	local function ratio(p)
		if type(p) ~= "table" then return 0, false end
		local s, d = num(p[1] or p.supply), num(p[2] or p.demand)
		if d <= 0 then return 0, false end
		return clamp(s / d, 0, 1), true
	end
	local r = clamp(num(sd.line) * (tonumber(sd.mult) or 2), 0, 1)
	local rc, hasR = ratio(sd.res)
	if hasR then r = (r + rc) / 2 end
	local c = ratio(sd.com)
	local i = ratio(sd.ind)
	return { r, c, i }
end

--- The smoothed usage after dt game years (e nil: u itself, the first sight). Values stay in 0..1.
function M.smooth(e, u, dtYears)
	if type(u) ~= "table" then return e end
	if type(e) ~= "table" then return { clamp(num(u[1]), 0, 1), clamp(num(u[2]), 0, 1), clamp(num(u[3]), 0, 1) } end
	local dt = math.max(0, num(dtYears))
	local a = 1 - math.exp(-dt / math.max(1e-6, M.TAU_YEARS))
	local out = {}
	for k = 1, 3 do
		local v = num(e[k]) + (num(u[k]) - num(e[k])) * a
		out[k] = clamp(v, 0, 1)
	end
	return out
end

--- The aimed shares from a smoothed usage (FLOORS each, the rest by usage); nil when there are no deliveries at all.
--- (A negative or broken value counts as 0, so no share falls below its floor.)
function M.aim(e)
	if type(e) ~= "table" then return nil end
	local e1, e2, e3 = math.max(0, num(e[1])), math.max(0, num(e[2])), math.max(0, num(e[3]))
	local sum = e1 + e2 + e3
	if sum <= 1e-6 then return nil end
	local f = M.FLOORS
	local free = 1 - f[1] - f[2] - f[3]
	return { f[1] + free * e1 / sum, f[2] + free * e2 / sum, f[3] + free * e3 / sum }
end

--- The neutral mix: the aim of a town whose deliveries are even (all three districts used alike), FLOORS + a third of
--- the rest each (42/29/29). Stateless (nothing saved), inside the base game's measured spread (findings towns.md
--- "District split": residential 25-47 %, commercial 20-50 %, industrial 13-41 %) and below every LEAN threshold.
function M.neutral()
	local f = M.FLOORS
	local free = 1 - f[1] - f[2] - f[3]
	return { f[1] + free / 3, f[2] + free / 3, f[3] + free / 3 }
end

--- The aim under the "Delivery weighting" setting (ot_params deliveryWeight, f in 0..1): the neutral mix plus f x the
--- way to the full aim (M.aim), aim_f = n + f (aim - n). f = 1 (or nil / not a number): the full aim itself. A blend of
--- two share vectors that both keep FLOORS and sum to 1, so it does too. nil when there are no deliveries (as M.aim).
function M.weightedAim(e, f)
	local w = M.aim(e)
	if w == nil then return nil end
	f = tonumber(f)
	if f == nil or not finite(f) then return w end
	f = clamp(f, 0, 1)
	if f >= 1 then return w end
	local n = M.neutral()
	return { n[1] + f * (w[1] - n[1]), n[2] + f * (w[2] - n[2]), n[3] + f * (w[3] - n[3]) }
end

--- The target per district (init x sf), its total and the shares; nil when a value is missing, zero or not finite.
function M.shares(init, sf)
	if type(init) ~= "table" or type(sf) ~= "table" then return nil end
	local L, S = {}, 0
	for k = 1, 3 do
		local a, f = tonumber(init[k]), tonumber(sf[k])
		if a == nil or f == nil or not finite(a) or not finite(f) or a <= 0 or f <= 0 then return nil end
		L[k] = a * f
		S = S + L[k]
	end
	if S <= 0 then return nil end
	return { L[1] / S, L[2] / S, L[3] / S }, S, L
end

--- The town's lean ("res" | "com" | "ind") from its target shares, or nil (none clearly ahead).
function M.lean(s)
	if type(s) ~= "table" then return nil end
	local best, bi = -1, nil
	for k = 1, 3 do
		local v = num(s[k])
		if v >= M.LEAN[k] and v - M.LEAN[k] > best then best, bi = v - M.LEAN[k], k end
	end
	return bi and M.LEAN_IDS[bi] or nil
end

--- The chance multiplier a lean gives a draw of `kind` ("works" | "district" | "lead"); 1 without a lean.
function M.chanceMul(lean, kind)
	local t = lean and M.CHANCE_MUL[lean]
	return (t and tonumber(t[kind])) or 1
end

-- integers with sum n (largest remainder), each >= 1; nil when n < 3
local function roundSum(v, n)
	if n < 3 then return nil end
	local out, rem, sum = {}, {}, 0
	for k = 1, 3 do
		out[k] = math.max(1, math.floor(v[k]))
		rem[k] = v[k] - math.floor(v[k])
		sum = sum + out[k]
	end
	local order = { 1, 2, 3 }
	table.sort(order, function(a, b)
		if rem[a] ~= rem[b] then return rem[a] > rem[b] end
		return a < b
	end)
	-- (3 districts: at most a few units off; each pass moves one unit, bounded)
	local guard = 0
	while sum ~= n and guard < 64 do
		guard = guard + 1
		if sum < n then
			local k = order[((guard - 1) % 3) + 1]
			out[k] = out[k] + 1
			sum = sum + 1
		else
			local k = order[3 - ((guard - 1) % 3)]
			if out[k] > 1 then
				out[k] = out[k] - 1
				sum = sum - 1
			end
		end
	end
	if sum ~= n then return nil end
	return out
end

-- the new initial capacities for goal shares q (real numbers): λ q / sf with Σ = N
local function initsFor(q, sf, N)
	local den = 0
	for k = 1, 3 do den = den + q[k] / sf[k] end
	if den <= 0 then return nil, 0 end
	local lam = N / den
	local out = {}
	for k = 1, 3 do out[k] = lam * q[k] / sf[k] end
	return out, lam
end

--- One weighting step. o = { init = {3}, sf = {3}, uses = {3} built capacities, w = {3} aim (M.aim), grown = the
--- target's growth since the last step (persons), n0 = the town's initial sum when the weighting first wrote (nil: now) }.
--- Returns { list = {3} integers or nil, why = "ok" | "bad" | "small" | "noAim" | "noGrowth" | "atMix" | "built" |
--- "total" | "tiny", s = shares before, q = shares aimed this step, S = total target, S1 = the total after, N, N1 =
--- initial sums, move = share points moved, budget }.
function M.step(o)
	local out = { why = "bad" }
	if type(o) ~= "table" then return out end
	local s, S = M.shares(o.init, o.sf)
	if s == nil then return out end
	out.s, out.S = s, S
	local init, sf = {}, {}
	local N = 0
	for k = 1, 3 do
		init[k], sf[k] = tonumber(o.init[k]), tonumber(o.sf[k])
		N = N + init[k]
	end
	out.N = N
	if S < M.MIN_TARGET then out.why = "small" return out end
	local w = o.w
	if type(w) ~= "table" or not (finite(tonumber(w[1]) or 0/0) and finite(tonumber(w[2]) or 0/0) and finite(tonumber(w[3]) or 0/0)) then
		out.why = "noAim"
		return out
	end
	local budget = math.min(M.STEP_MAX, M.MOVE_K * math.max(0, num(o.grown)) / S)
	out.budget = budget
	if budget < M.MIN_MOVE then out.why = "noGrowth" return out end
	local d, pos = {}, 0
	for k = 1, 3 do
		d[k] = tonumber(w[k]) - s[k]
		if d[k] > 0 then pos = pos + d[k] end
	end
	if pos < M.MIN_MOVE then out.why = "atMix" return out end
	local scale = math.min(1, budget / pos)
	local uses = type(o.uses) == "table" and o.uses or {}
	local n0 = tonumber(o.n0)
	if n0 == nil or not finite(n0) or n0 <= 0 then n0 = N end
	local nMax = math.floor(n0 * (1 + M.CEIL))
	for _ = 1, M.HALVINGS + 1 do
		local q = {}
		for k = 1, 3 do q[k] = s[k] + d[k] * scale end
		local v, lam = initsFor(q, sf, N)
		if v == nil then out.why = "bad" return out end
		-- the built floor: a losing district keeps at least its built capacity as target (never below its old value)
		local short = 0
		for k = 1, 3 do
			if v[k] < init[k] then
				local floorK = math.min(init[k], num(uses[k]) / sf[k])
				if v[k] < floorK then
					short = short + (floorK - v[k])
					v[k] = floorK
				end
			end
		end
		-- the units the floor kept: taken back from the gainers, except what the ceiling above n0 allows
		local room = math.max(0, nMax - N)
		local back = math.max(0, short - room)
		if back > 0 then
			local gain = 0
			for k = 1, 3 do if v[k] > init[k] then gain = gain + (v[k] - init[k]) end end
			if gain <= back + 1e-9 then out.why = "built" return out end
			local f = 1 - back / gain
			for k = 1, 3 do if v[k] > init[k] then v[k] = init[k] + (v[k] - init[k]) * f end end
		end
		local N1 = 0
		for k = 1, 3 do N1 = N1 + v[k] end
		local list = roundSum(v, math.floor(N1 + 0.5))
		if list == nil then out.why = "bad" return out end
		-- (after rounding: the losers' floor once more, a unit off at most)
		for k = 1, 3 do
			if list[k] < init[k] and list[k] * sf[k] < num(uses[k]) - 1e-6 and list[k] + 1 <= init[k] then
				local j, best = nil, -1
				for m = 1, 3 do
					if m ~= k and list[m] > init[m] and list[m] - init[m] > best then j, best = m, list[m] - init[m] end
				end
				if j then
					list[k] = list[k] + 1
					list[j] = list[j] - 1
				end
			end
		end
		local S1, N1i = 0, 0
		for k = 1, 3 do
			S1 = S1 + list[k] * sf[k]
			N1i = N1i + list[k]
		end
		if math.abs(S1 / S - 1) <= M.TOTAL_DEV then
			local changed = false
			for k = 1, 3 do if list[k] ~= init[k] then changed = true end end
			local s1 = { list[1] * sf[1] / S1, list[2] * sf[2] / S1, list[3] * sf[3] / S1 }
			local move = 0
			for k = 1, 3 do move = move + math.max(0, s1[k] - s[k]) end
			out.q, out.S1, out.N1, out.move, out.s1, out.lambda = q, S1, N1i, move, s1, lam
			if not changed or move < M.MIN_MOVE / 2 then out.why = "tiny" return out end
			out.list = list
			out.why = "ok"
			return out
		end
		scale = scale / 2
	end
	out.why = "total"
	return out
end

--- "40/30/30" (whole percent) for shares, "-" for nil.
function M.pct(s)
	if type(s) ~= "table" then return "-" end
	return string.format("%.0f/%.0f/%.0f", num(s[1]) * 100, num(s[2]) * 100, num(s[3]) * 100)
end

--- "0.20/0.00/0.90" for usage values, "-" for nil.
function M.frac(u)
	if type(u) ~= "table" then return "-" end
	return string.format("%.2f/%.2f/%.2f", num(u[1]), num(u[2]), num(u[3]))
end

--- The saved smoothed usage as integers x 1000 (and back).
function M.pack(e)
	if type(e) ~= "table" then return nil end
	return { math.floor(clamp(num(e[1]), 0, 1) * 1000 + 0.5), math.floor(clamp(num(e[2]), 0, 1) * 1000 + 0.5),
		math.floor(clamp(num(e[3]), 0, 1) * 1000 + 0.5) }
end

function M.unpack(p)
	if type(p) ~= "table" then return nil end
	local out = {}
	for k = 1, 3 do
		local v = tonumber(p[k])
		if v == nil or not finite(v) then return nil end
		out[k] = clamp(v / 1000, 0, 1)
	end
	return out
end

return M
