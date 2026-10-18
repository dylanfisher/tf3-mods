-- DEV ONLY (never upload). Organic Towns dev tools: "Simulate natural growth". Reproduces the base game's town
-- growth over compressed time on any map, with no transport: every town gets a simulated connectedness (exp per
-- person per year, deterministic per town id + seed), its simulated experience advances each step, and the game's
-- own formulas turn it into a target size, split over residential / commercial / industrial and applied with the
-- same command the game uses. Plain Lua, pre-5.3, no requires; the engine reads and the command are injected
-- (env), so tests/square_organic_towns_dev/test_simgrow.lua drives it with fakes.
--
-- The game's natural growth (read from the base scripts, docs/findings/towns.md "Natural town growth"):
--   * experience only comes from transport (town_growth_config.res.lua: 10 per cargo item, 5 per passenger, x 2^tier,
--     x the authority rating); town_cargo_util.tl growthPerTick = 0, so without transport towns never grow;
--   * level and fraction from the experience: level n costs 1000 x 1.5^(n-1) (town_cargo_util.getLevelAndFraction);
--     a town starts at level 1-4 from its residential initial capacity (> 100 / 150 / 200, ensureState);
--   * growth factor = town_growth_function.getGrowthFactor(level + 1 - initialLevel + fraction) (F(1) = 1, F(18) = 40);
--   * town_growth.script.tl update (every 120 updates per town): target = Σ initial capacities x factor; only when
--     floor(target) > floor(Σ initial x sizeFactors) the extra capacity is split by usage weights (transport supply /
--     demand per district), rebalanced (min townGrowthMinDistrictFraction each, max dampened toward 0.5 of the town and
--     0.4 of the map), and sent as makeTownUpdateSizeCmd(town, sizeFactors, false): no forced building update, the
--     town developer builds at its own pace. The script never shrinks a town, so it keeps the sizes set here.
--   * With no transport every usage weight is 0 and the game skips the town even with experience (totalUsage > 0
--     test), so this tool uses the town's current district mix as the usage weights (the "plausible fixed weights").
--
-- What it changes: only the towns' size factors (the same command as the game; with Fast fill some years' commands
-- also update all buildings, the dev tools' forced growth). The changes stay in the save for
-- good (a bigger town keeps growing toward its size). Its own state (rates, experience, simulated years) lives in
-- this session only; a new Start derives each town's experience from its current size, so a reloaded save continues
-- where the towns are (same seed -> same rates).

local SG = {}

-- realistic split (round R7, 2026-10-13; run 2026-10-13_1945_sqot-dev: SIMGROW kept each town's starting share, so
-- Alsager (34 % industrial at the start) grew all three districts alike and read as industrial everywhere): the usage
-- weights of the growth step are a per-era split, mostly residential (residential, commercial, industrial), instead of
-- the town's current mix; the game's rebalance (min / max weights) applies as before. MIX = false: the old behaviour.
SG.MIX = true
SG.MIX_ERAS = { { 1920, { 0.62, 0.14, 0.24 } }, { 1950, { 0.64, 0.17, 0.19 } }, { 1980, { 0.66, 0.21, 0.13 } },
	{ math.huge, { 0.68, 0.24, 0.08 } } }

--- The era's usage weights {res, com, ind} for a game year (nil when MIX is off).
function SG.mixFor(year)
	if not SG.MIX then return nil end
	local y = tonumber(year) or 1950
	for _, e in ipairs(SG.MIX_ERAS) do
		if y < e[1] then return { e[2][1], e[2][2], e[2][3] } end
	end
	return nil
end

-- the game's constants (cited above)
SG.EXP_BASE = 1000          -- town_growth_config.res.lua expBaseTownLevel
SG.EXP_SCALING = 1.5        -- town_cargo_util.tl townExpScaling
SG.MAX_TOWN_FRACTION, SG.MAX_TOWN_DAMPEN = 0.5, 0.4    -- town_growth.script.tl:14-15
SG.MAX_MAP_FRACTION, SG.MAX_MAP_DAMPEN = 0.4, 0.32     -- town_growth.script.tl:16-17
SG.MIN_WEIGHT_FALLBACK = 0.1   -- when baseConfig.economy.townDevelopment.townGrowthMinDistrictFraction can't be read

-- the tool
-- Speed (first real map run 2026-10-12_2306_sqot-dev, 16 towns, pace 30 s, game speed 4x): 13 growing towns x 4
-- steps = 52 size steps per year, all applied; buildings +65-90 per year (2313 -> 4544 in 32 years, 16 min). The
-- town developer kept up with slow towns (built capacity 92-100 % of the target) but not with fast ones (Aldershot
-- 55 %: ~3.6 capacity per real second at 4x), 84 % over the map. So at 30 s per year our pace was the limit; at a
-- few seconds per year the developer is (its pace is in game time, no API knob), hence Fast fill: the year's size
-- command with updateAllBuildings = true (the dev tools' forced growth) for towns whose built capacity is under
-- FILL_RATIO of their target, every FILL_EVERY years, with its check pace raised for the run (MAIN_CHECK_S, cooldowns x
-- MAIN_COOLDOWN_MULT, restored at Stop), and game speed SIM_SPEED during the run (restored at Stop).
-- Order of a fill year (2026-10-13, after the run 2026-10-13_0018_top-up-598153: the fill came first, so the game
-- placed its own streets for the forced houses before the main mod's turn, and the fast towns ended with ~7 % of their
-- new streets from the mod): the year's size commands -> wait for the main mod's checks / builds of the WAIT_TOWNS that
-- grew most (WAIT_MAX_S) -> the fill (the lagging towns' current size with updateAllBuildings) -> a short wait
-- (WAIT_FILL_S). The simulated clock stands still while a fill year waits or fills (that run's next year came at once
-- after every wait).
-- Build round (2026-10-13, after the run 2026-10-13_0137_sqot-dev: Quick 40 years, 16 towns, 358 s; the main driver
-- checked each town ~3 times in the whole run (75 CHECK lines, 31 demand builds), 10 of 16 towns got no demand build,
-- the mod's share of new street edges 16 %; in normal play 40 years take hours and the driver checks each town hundreds
-- of times). The simulation runs in chunks of FILL_EVERY years: the chunk's last year applies the sizes (callbacks
-- awaited), then a build round (env.roundStart / roundTick, the runner): the main driver's scheduler held, every town
-- that grew in the chunk gets the main mod's normal check -> plan -> build on its own state (demand ledger, cooldowns),
-- concurrently (the runner's job pool), again after each build until a check doesn't build or ROUND_BUILDS, at most
-- ROUND_MAX_S; then the fill; then the next chunk. "Wait for the main mod" (waitMain) stays as the fallback when the
-- build round is off.
-- Speed-up (2026-10-14, after the run 2026-10-14_0302_sqot-sqrl: Quick 40 years took 175 s: 30 quiet years x 1 s of
-- pace, 10 fill years with fillS 3.9-20.7 s (94 s in all) and roundS 0-9.4 s (29 s)). The long fills were the ones the
-- main driver's own build overlapped: its scheduler was free again after the round, its proposal queued with the 16
-- forced updates (BUILT ms=8717 / 16859 instead of ~300-800) and the fill waited for it; alone a fill took 4-10 s
-- (~100 buildings per s). So: pace 0 (no minimum time per year: a quiet year passes as soon as its size commands came
-- back), the main driver stays held through the fill too (the runner's simHolds), a town's fill starts as soon as its
-- own round jobs ended (Sim:earlyFill: still after the main mod's turn on that town, so its streets come before the
-- forced houses, and it plans from the houses of the last fill), more round jobs at once (ROUND_INFLIGHT) and the
-- neighbour rule from the towns' plan extents instead of a fixed 2 km (runner simRoundClear).
SG.PACES = { 0, 1, 2, 5, 10, 30, 60 }   -- real seconds (while the game runs) per simulated year (at least; 0 = none)
SG.PACE_DEFAULT = 1                      -- (0 s; 2 s until 2026-10-14: a plain Start ran 2 s per year)
SG.FAST_PACE = 5            -- paces up to this: one size command per town per year (experience still in quarters)
SG.SEEDS = { 1, 2, 3, 4, 5 }
SG.LIMITS = { 0, 20, 40, 60 }   -- simulated years, 0 = until stopped
SG.LIMIT_DEFAULT = 3       -- (40 years; "never" until 2026-10-14: a plain Start ran until stopped)
SG.STEPS_PER_YEAR = 4       -- experience integration: quarter years (and size commands per year at slow paces)
SG.FILL_EVERY = { 1, 2, 4, 8 } -- Fast fill (and the build round): every this many simulated years
SG.FILL_EVERY_DEFAULT = 2
SG.FILL_RATIO = 0.95        -- ... towns whose built capacity is under this share of their (new) target
-- (WAIT_*: the fallback with the build round off; the 0302 run never used them, so they stay as they were)
SG.WAIT_MAX_S = 15          -- wait for the main mod's checks after a fill year's size step at most this long
SG.WAIT_TOWNS = 6           -- ... for the towns that grew most since the last wait (2026-10-13: 4 of 13 checked in 15 s)
SG.WAIT_FILL_S = 4          -- after the fill (forced buildings): a short wait for the main mod at most this long
SG.STALL_STEPS = 2          -- a growing town that gets no step this many steps in a row: SIMGROW stall (once)
SG.ROUND_BUILDS = 3         -- build round: builds per town per round at most (the main mod's plans were 3-15 edges;
                            -- 6 until 2026-10-14: run 0502's rounds were per-town serial chains of ~2-3 s a step)
SG.ROUND_INFLIGHT = 24      -- ... jobs at once (the runner's pool, at most R.POOL_MAX; 0302: 12, the peak every round)
SG.ROUND_MAX_S = 20         -- ... no new job after this many real seconds (running jobs finish; ~1.5-3 s per job)
-- ... no two jobs at once (and no job beside a fill) in towns whose plan extents may meet: centres closer than
-- rA + rB + 2 x ROUND_REACH_M (r: the town's building extent from the main driver's last check, else ROUND_R_DEFAULT).
-- A plan stays within its town's extent + ~700 m: the street snapshot reaches 300 m past the extent (ot_driver
-- SNAP_MARGIN), an increment of 6-36 edges grows up to ~400 m beyond its joints, a satellite seed sits ~1 km from the
-- centre. (Was a fixed 2 km between centres; two 300 m towns now pair from 1.9 km, two 150 m towns from 1.6 km.)
SG.ROUND_REACH_M = 700
SG.ROUND_R_DEFAULT = 400
SG.ROUND_START_S = 10       -- ... waits at most this long for the main driver's running job before the round (a cap:
                            -- the 0302 rounds never waited, round s = the jobs)
SG.ROUND_GUARD_S = 90       -- ... the simulation gives up on a round that never reports after this long
SG.REACTIVATE_MAX = 3       -- an "off" town that was active at Start: development switched back on at most this often
SG.SIM_SPEED = 8            -- game speed during the run (makeGameSetSpeedCmd 8 sticks, findings lines-vehicles)
SG.MAIN_CHECK_S = 0.25      -- the main driver's check pace during the run (its D.CHECK_S is 3)
SG.MAIN_COOLDOWN_MULT = 0.1 -- ... and its per-town cooldowns (ot_assess COOLDOWN_S) times this
-- "Quick" preset: 40 years as fast as possible, Fast fill every 4 years, a build round before each fill, speed 8
SG.QUICK = { pace = 0, limit = 40, fillEvery = 4 }
-- "Build out" (2026-10-14): every town to a mature size, YEARS simulated years in CHUNKS big steps: each chunk is one
-- size command per town with the chunk's years of experience (integrated in quarter years as the yearly steps do, so
-- the sizes match a yearly run), then the build round (up to ROUND_BUILDS builds per town, ROUND_MAX_S) and the fill.
-- The main mod's upward doses and level weights come from its own checks in the rounds; their real-time gaps
-- (ot_upward GAP_S 240 s, LV_GAP_S 300 s) are lowered to UP_GAP_S during the run (restored at Stop), so a town can get
-- each about once per chunk as in normal play (where 10 years take hours). Every town grows, the tour at the end.
SG.BUILDOUT = { years = 100, chunks = 10, roundBuilds = 8, roundMaxS = 25, upGapS = 8 }
SG.NEAR_M = 4000            -- "near camera": towns whose centre is within this of the camera at Start
SG.SIZE_CAP = 50            -- size factors never above this (the dev runner's GROW_CAP; the game itself has no cap)
SG.SEND_PER_TICK = 4        -- towns processed per tick (the step's commands spread over the ticks)
SG.INFLIGHT_MAX = 16
SG.CMD_TIMEOUT_US = 30000000
SG.TOP_N = 5                -- towns named in each year's summary
-- connectedness spread (exp per person per simulated year; calibrated offline for a 300-person town from level 2:
-- r 0.2 -> factor 1.8 after 40 years, r 1 -> 4.1, r 3 -> 11, r 5 -> 19)
-- Spread (no bias): 25 % none; connected r = R_MIN x (R_MAX / R_MIN)^(v^R_EXP), v uniform: ~45 % of all towns slow
-- (r < 0.3: under 2x in 40 years), ~18 % medium, ~12 % fast (r >= 1.3: over 5x), ~4 % over r 3 (11x+: metropolis
-- candidates).
SG.P_NONE = 0.25            -- share of towns not connected at all (no growth)
SG.R_MIN, SG.R_MAX, SG.R_EXP = 0.1, 5, 2.5
SG.CLASS_SLOW, SG.CLASS_FAST = 0.3, 1.3
-- "every town grows" (judging looks, not realism): every town connected, r seeded in [EVEN_MIN, EVEN_MAX]
-- (about 4-7x in 40 years)
SG.EVEN_MIN, SG.EVEN_MAX = 1.0, 2.0

---------------------------------------------------------------------------
-- the game's curve

--- town_growth_function.getGrowthFactor (3rd degree polynomial, F(1) = 1, F(18) = 40; monotonic).
function SG.growthFunction(l)
	return 0.00930472 * l * l * l - 0.08061382 * l * l + 0.63330472 * l + 0.438
end

--- Experience at the start of level n (town_cargo_util: base x (1 - 1.5^(n-1)) / (1 - 1.5)).
function SG.expAt(level)
	return SG.EXP_BASE * (1 - SG.EXP_SCALING ^ (level - 1)) / (1 - SG.EXP_SCALING)
end

--- town_cargo_util.getLevelAndFraction: level, fraction of the way to the next level.
function SG.levelAndFraction(exp)
	local base, k = SG.EXP_BASE, SG.EXP_SCALING
	if exp < base then return 1, exp / base end
	local level = math.floor(math.log(1 - ((exp + 1) * (1 - k) / base)) / math.log(k)) + 1
	local cur, nxt = SG.expAt(level), SG.expAt(level + 1)
	return level, (exp - cur) / (nxt - cur)
end

--- town_cargo_util.ensureState: the start level from the residential initial capacity.
function SG.initialLevel(initialRes)
	initialRes = initialRes or 0
	if initialRes > 200 then return 4 end
	if initialRes > 150 then return 3 end
	if initialRes > 100 then return 2 end
	return 1
end

--- town_cargo_util.getGrowthFactor: F(level + 1 - initialLevel + fraction).
function SG.growthFactor(exp, l0)
	local level, fraction = SG.levelAndFraction(exp)
	return SG.growthFunction(level + 1 - (l0 or 1) + fraction)
end

--- Experience whose growth factor is `factor` (inverse of growthFactor; factor <= 1 -> the start level's exp).
function SG.expForFactor(factor, l0)
	l0 = l0 or 1
	if factor == nil or factor <= 1 then return SG.expAt(l0) end
	local lo, hi = 1, 2
	while SG.growthFunction(hi) < factor and hi < 200 do hi = hi * 2 end
	for _ = 1, 60 do
		local mid = (lo + hi) / 2
		if SG.growthFunction(mid) < factor then lo = mid else hi = mid end
	end
	local p = (lo + hi) / 2 + l0 - 1      -- level + fraction
	local level = math.floor(p)
	local a, b = SG.expAt(level), SG.expAt(level + 1)
	return a + (p - level) * (b - a)
end

---------------------------------------------------------------------------
-- connectedness

--- Deterministic uniform [0, 1) from town id, seed and a salt (Lehmer rounds with a fold; no bit ops, pre-5.3).
function SG.hash01(town, seed, salt)
	local m = 2147483647
	local x = (math.floor(town or 0) * 7919 + math.floor(seed or 0) * 104729 + math.floor(salt or 0) * 1299709 + 12345) % m
	for _ = 1, 4 do
		-- multiply, then fold the high part back in (a non-linear step: plain Park-Miller rounds keep salts of one
		-- town a fixed offset apart, so its "connected" and "how much" draws were correlated)
		x = (x * 48271) % m
		x = (x + math.floor(x / 65536) * 69621 + 1) % m
	end
	return x / m
end

--- Connectedness of a town: rate (exp per person per simulated year), class ("none" | "slow" | "medium" | "fast").
--- bias: larger towns (Σ initial capacities, which growth never changes) are more often connected and connected
--- better (a town of 1000 initial persons: none 12 %, v^(1/1.5)).
--- even: every town grows (r in [EVEN_MIN, EVEN_MAX]), no "none".
function SG.rate(town, seed, initialSum, bias, even)
	if even then
		local r = SG.EVEN_MIN + (SG.EVEN_MAX - SG.EVEN_MIN) * SG.hash01(town, seed, 2)
		return r, r < SG.CLASS_FAST and "medium" or "fast"
	end
	local b = 0
	if bias and (initialSum or 0) > 250 then
		b = math.min(2, math.log(initialSum / 250) / math.log(2)) * 0.5
	end
	local pNone = SG.P_NONE / (1 + b)
	local u = SG.hash01(town, seed, 1)
	if u < pNone then return 0, "none" end
	local v = SG.hash01(town, seed, 2)
	if b > 0 then v = v ^ (1 / (1 + b)) end
	local r = SG.R_MIN * (SG.R_MAX / SG.R_MIN) ^ (v ^ SG.R_EXP)
	local class = r < SG.CLASS_SLOW and "slow" or (r < SG.CLASS_FAST and "medium" or "fast")
	return r, class
end

---------------------------------------------------------------------------
-- the game's distribution (town_growth.script.tl:404-548)

local function mapClamp(x, a, b, c, d)
	local t = (x - a) / (b - a)
	local v = c + (d - c) * t
	local lo, hi = math.min(c, d), math.max(c, d)
	return math.max(lo, math.min(hi, v))
end

--- rebalance2 (town_growth.script.tl:423-491), verbatim: pins weights into [min, max], then spreads 1 - sum over the
--- weights that still have room (equal shares, repeated while some hit their bound). Changes `weights` in place.
function SG.rebalance(weights, minWeights, maxWeights)
	local pinnedDown, pinnedUp = {}, {}
	local sum = 0
	for i = 1, #weights do
		pinnedDown[i] = weights[i] < minWeights[i]
		if pinnedDown[i] then weights[i] = minWeights[i] end
		pinnedUp[i] = weights[i] > maxWeights[i]
		if pinnedUp[i] then weights[i] = maxWeights[i] end
		sum = sum + weights[i]
	end
	local diff = 1.0 - sum
	local negative = diff < 0
	local mult = negative and -1 or 1
	local remaining = math.abs(diff)
	for _ = 1, 50 do   -- (the game loops until done; 3 weights settle in <= 3 rounds)
		local capacityOf, count = {}, 0
		for i = 1, #weights do
			if diff > 0 then
				if not pinnedUp[i] then capacityOf[i] = maxWeights[i] - weights[i]; count = count + 1 end
			else
				if not pinnedDown[i] then capacityOf[i] = weights[i] - minWeights[i]; count = count + 1 end
			end
		end
		if count == 0 then return weights end
		local all = true
		local per = remaining / count
		for i = 1, #weights do
			local cap = capacityOf[i]
			if cap ~= nil then
				if per < cap then
					weights[i] = weights[i] + per * mult
					remaining = remaining - per
				else
					weights[i] = weights[i] + cap * mult
					remaining = remaining - cap
					if negative then pinnedDown[i] = true else pinnedUp[i] = true end
					all = false
				end
			end
		end
		if all then return weights end
	end
	return weights
end

--- One growth step of a town as the game's update does it. o = { initials {3}, sizeFactors {3}, mapSum {3} (Σ initial
--- x sizeFactor of every town per district), newSum (target persons), minWeight, weights {3} or nil (usage; nil =
--- the town's current mix) }. Returns the new size factors (nil when the target is not above the current size:
--- floor test as the game) and info { current, added {3}, weights {3} }.
function SG.distribute(o)
	local cur, curSum, initSum = {}, 0, 0
	for i = 1, 3 do
		cur[i] = (o.initials[i] or 0) * (o.sizeFactors[i] or 0)
		curSum = curSum + cur[i]
		initSum = initSum + (o.initials[i] or 0)
	end
	local info = { current = curSum, initial = initSum }
	if math.floor(o.newSum) <= math.floor(curSum) then return nil, info end
	local usage = o.weights
	if usage == nil then
		usage = {}
		for i = 1, 3 do usage[i] = curSum > 0 and cur[i] / curSum or ((o.initials[i] or 0) > 0 and 1 or 0) end
	end
	local total = usage[1] + usage[2] + usage[3]
	if total <= 0 then return nil, info end
	local extra = o.newSum - curSum
	local w = { usage[1] / total, usage[2] / total, usage[3] / total }
	local added, newWorld, newTown = {}, {}, {}
	local sumWorld, sumTown = 0, 0
	for i = 1, 3 do
		added[i] = w[i] * extra
		newWorld[i] = (o.mapSum and o.mapSum[i] or cur[i]) + added[i]
		newTown[i] = cur[i] + added[i]
		sumWorld, sumTown = sumWorld + newWorld[i], sumTown + newTown[i]
	end
	local maxW = { 1, 1, 1 }
	for i = 1, 3 do
		if sumWorld > 0 and newWorld[i] / sumWorld >= SG.MAX_MAP_DAMPEN then
			maxW[i] = mapClamp(newWorld[i] / sumWorld, SG.MAX_MAP_DAMPEN, SG.MAX_MAP_FRACTION, 1.0, SG.MAX_MAP_FRACTION)
		end
		if sumTown > 0 and newTown[i] / sumTown >= SG.MAX_TOWN_DAMPEN then
			maxW[i] = math.min(maxW[i], mapClamp(newTown[i] / sumTown, SG.MAX_TOWN_DAMPEN, SG.MAX_TOWN_FRACTION, 1.0,
				SG.MAX_TOWN_FRACTION))
		end
	end
	local m = o.minWeight or SG.MIN_WEIGHT_FALLBACK
	SG.rebalance(w, { m, m, m }, maxW)
	local f = {}
	for i = 1, 3 do
		added[i] = w[i] * extra
		if (o.initials[i] or 0) > 0 then
			f[i] = math.min(SG.SIZE_CAP, (cur[i] + added[i]) / o.initials[i])
			f[i] = math.max(f[i], o.sizeFactors[i] or 0)   -- never shrink a district (the game's weights are >= 0)
		else
			f[i] = 0
		end
	end
	info.added, info.weights = added, w
	return f, info
end

---------------------------------------------------------------------------
-- the simulation

--- 1-based index of v in list (nil when absent).
function SG.indexOf(list, v)
	for i, x in ipairs(list) do if x == v then return i end end
	return nil
end

--- Size commands per town per simulated year at a pace: 1 at fast paces (bigger steps, fewer commands), else 4.
function SG.cmdSteps(pace)
	if (pace or 0) <= SG.FAST_PACE then return 1 end
	return SG.STEPS_PER_YEAR
end

local Sim = {}
Sim.__index = Sim

local function fmt2(v) return string.format("%.2f", v or 0) end
local function list3(t, f)
	local o = {}
	for i = 1, 3 do o[i] = string.format(f or "%.2f", t and t[i] or 0) end
	return table.concat(o, "/")
end

--- env = { towns() -> ids, name(t), centre(t) -> x, y, town(t) -> { initials {3}, sizeFactors {3}, active } or nil,
--- updateSize(t, factors, cb(success), forced) (forced: updateAllBuildings), caps(t) -> { actual, target } or nil
--- (built and target person capacity), buildings() -> { [town] = count } or nil, speed() -> number or nil (0 =
--- paused), minWeight() -> number or nil, mainMark(towns, now) -> mark or nil (nil: no main driver to wait for),
--- mainSeen(mark, now) -> { seen, total, busy, checks, builds } or nil, roundStart(towns, now) -> handle or nil, why
--- (nil: no round possible), roundTick(handle, now) -> nil while running, else { towns, checks, builds, edges, served,
--- capped, demandLeft, s, peak, why, per }, reactivate(t, cb(ok)) (development on) or nil, log(what, fields),
--- roundReady(handle) -> towns whose round part ended (early fill) or nil, roundFilling(handle, t, on) (a town's fill in
--- flight: no neighbour job beside it) or nil, year() -> game year or nil, setYear(y, cb(ok)) (game date) or nil }.
--- roundStart(towns, now, o): o = { builds, maxS } (nil: SG.ROUND_BUILDS / ROUND_MAX_S).
--- opts = { pace (s per year, 0 = none), seed, near = { x, y } or nil (all towns), limit (years, 0 = none), bias,
--- tourWhenDone, fastFill, fillEvery (years), waitMain, buildRound, chunk (Build out: years per step), mode (log text),
--- roundBuilds, roundMaxS (the round's limits, nil = SG's), moveDate (the game date follows the simulated years) }.
function SG.new(env, opts)
	local s = setmetatable({ env = env, towns = {}, order = {}, years = 0, step = 0, simUs = 0, lastUs = nil,
		queue = {}, inflight = 0, running = false, applied = 0, yearApplied = 0, sends = 0, fails = 0,
		autoTour = 0, yearFrac = 0, phase = "run", yearTowns = {}, yearFilled = 0, fills = 0, yearRes = {},
		fillQueue = {}, filledTowns = {}, rounds = 0, roundBuilds = 0, earlyDone = {}, earlyQueue = {}, yearEarly = 0,
		earlyFills = 0, chunks = 0 }, Sim)
	s:configure(opts)
	return s
end

function Sim:configure(opts)
	opts = opts or {}
	self.pace = opts.pace or SG.PACES[SG.PACE_DEFAULT]
	self.seed = opts.seed or 1
	self.near = opts.near
	self.limit = opts.limit or 0
	self.bias = opts.bias ~= false
	self.even = opts.even == true
	self.tourWhenDone = opts.tourWhenDone == true
	self.fastFill = opts.fastFill == true
	self.fillEvery = opts.fillEvery or SG.FILL_EVERY[SG.FILL_EVERY_DEFAULT]
	self.waitMain = opts.waitMain == true
	self.buildRound = opts.buildRound == true
	-- (Build out: years per step, nil = yearly steps; the round's limits; the game date moved with the years)
	self.chunk = (tonumber(opts.chunk) or 0) > 0 and tonumber(opts.chunk) or nil
	-- (the main mod's head start was cut at the start: a build round in the first simulated year stands in for it)
	self.firstRound = opts.firstRound == true
	self.mode = opts.mode or (self.chunk and "buildout" or "custom")
	self.roundMaxBuilds = opts.roundBuilds
	self.roundMaxS = opts.roundMaxS
	self.moveDate = opts.moveDate == true
end

function Sim:log(what, fields)
	if self.env.log then self.env.log("SIMGROW " .. what, fields) end
end

--- Picks the towns (scope), gives each its rate and its experience from its current size. Keeps known towns'
--- experience when resuming.
function Sim:start(now, resume)
	local env = self.env
	self.minW = (env.minWeight and env.minWeight()) or SG.MIN_WEIGHT_FALLBACK
	if not resume or self.startYear == nil then
		local okY, y = pcall(function() return env.year and env.year() end)
		self.startYear = okY and tonumber(y) or nil
	end
	local ids = env.towns() or {}
	local picked, counts = {}, { none = 0, slow = 0, medium = 0, fast = 0 }
	local builds = env.buildings and env.buildings() or {}
	for _, t in ipairs(ids) do
		local keep = true
		if self.near then
			local x, y = env.centre(t)
			keep = x ~= nil and math.sqrt((x - self.near[1]) ^ 2 + (y - self.near[2]) ^ 2) <= SG.NEAR_M
		end
		local info = keep and env.town(t) or nil
		if info then
			local st = resume and self.towns[t] or nil
			local initSum, curSum = 0, 0
			for i = 1, 3 do
				initSum = initSum + (info.initials[i] or 0)
				curSum = curSum + (info.initials[i] or 0) * (info.sizeFactors[i] or 0)
			end
			if st == nil and initSum > 0 then
				local r, class = SG.rate(t, self.seed, initSum, self.bias, self.even)
				local l0 = SG.initialLevel(info.initials[1])
				local exp = SG.expForFactor(curSum / initSum, l0)
				st = { town = t, rate = r, class = class, l0 = l0, exp = exp, startPersons = curSum,
					startBuildings = builds[t] or 0, startFactor = curSum / initSum, wasActive = info.active ~= false }
				self.towns[t] = st
				local level, fr = SG.levelAndFraction(exp)
				self:log("town", { { "town", t }, { "name", env.name(t) }, { "rate", fmt2(r) }, { "class", class },
					{ "l0", l0 }, { "level", string.format("%d+%.2f", level, fr) }, { "factor", fmt2(curSum / initSum) },
					{ "initial", list3(info.initials, "%.0f") }, { "sizeFactors", list3(info.sizeFactors) },
					{ "persons", string.format("%.0f", curSum) }, { "buildings", builds[t] or 0 },
					{ "active", info.active ~= false } })
			end
			if st then
				picked[#picked + 1] = t
				counts[st.class] = counts[st.class] + 1
			end
		end
	end
	self.order = picked
	if self.buildingsStart == nil then
		local sum = 0
		for _, t in ipairs(picked) do sum = sum + (self.towns[t].startBuildings or 0) end
		self.buildingsStart, self.buildingsTotal = sum, sum
	end
	self.running = true
	self.lastUs = now
	self.lastYearUs = now
	self.startUs = self.startUs or now
	self.counts = counts
	return picked, counts
end

function Sim:stop(reason)
	if not self.running then return false end
	self.running = false
	self.queue = {}
	self.queueYear = false
	self.yearFrac = 0
	self.phase = "run"
	self.mark = nil
	self.fillQueue, self.filledTowns, self.waitKind = {}, {}, nil
	self.yearTowns, self.yearFilled = {}, 0
	self.roundH, self.roundInfo = nil, nil
	self.earlyDone, self.earlyQueue, self.yearEarly, self.fillUs0 = {}, {}, 0, nil
	self.stopReason = reason
	return true
end

--- Fast fill this year? (the year being simulated is years + 1; Build out: every chunk)
function Sim:fillYear()
	if self.chunk then return self.fastFill end
	return self.fastFill and (self.years + 1) % math.max(1, self.fillEvery or 1) == 0
end

--- A build round this year? (every fillEvery years, with or without Fast fill: the chunk's end; Build out: every chunk)
function Sim:roundYear()
	if self.chunk then return self.buildRound end
	if self.buildRound and self.firstRound and self.years == 0 then return true end
	return self.buildRound and (self.years + 1) % math.max(1, self.fillEvery or 1) == 0
end

--- Moves the game date to the simulated year (opts.moveDate; forward only, Jan 1st; env.setYear =
--- makeGameSetDateCmd, as the Stress Test's year jump). The calendar otherwise stands still in a run: a 1900 map stays
--- in era A (town buildings of levels 1-2 only until 1950, docs/findings/towns.md). SIMGROW date line.
function Sim:moveDateNow()
	if not self.moveDate or self.env.setYear == nil or self.startYear == nil then return end
	local y = math.floor(self.startYear + self.years)
	local okC, cur = pcall(function() return self.env.year and self.env.year() end)
	cur = okC and tonumber(cur) or nil
	if (cur ~= nil and y <= cur) or (self.dateAsked ~= nil and y <= self.dateAsked) then return end
	self.dateAsked = y
	self.env.setYear(y, function(ok)
		self:log("date", { { "year", y }, { "was", cur or "-" }, { "ok", ok == true }, { "simYears", self.years } })
	end)
end

--- Σ initial x sizeFactor per district over every town of the map (the game's mapSumLandUse).
function Sim:mapSum()
	local sum = { 0, 0, 0 }
	for _, t in ipairs(self.env.towns() or {}) do
		local info = self.env.town(t)
		if info then
			for i = 1, 3 do sum[i] = sum[i] + (info.initials[i] or 0) * (info.sizeFactors[i] or 0) end
		end
	end
	return sum
end

--- One town's step: experience for dtYears (in quarter years, the size following the curve in between), target
--- size, distribution, command (when the target is above the size). forced (Fast fill): a town whose built capacity
--- is under FILL_RATIO of its (new) target gets the command with updateAllBuildings, at its current size when the
--- size doesn't change. Returns "sent" | "filled" | "same" | "none" (rate 0) | "off" (development inactive) |
--- "gone" | "busy".
function Sim:townStep(t, dtYears, mapSum, forced)
	local st = self.towns[t]
	if st == nil then return "gone" end
	if st.pending then
		if self.nowUs and st.sentUs and self.nowUs - st.sentUs > SG.CMD_TIMEOUT_US then
			st.pending = false
			self.inflight = math.max(0, self.inflight - 1)
			self.fails = self.fails + 1
			self:log("town", { { "town", t }, { "timeout", true } })
		else
			return "busy"
		end
	end
	local info = self.env.town(t)
	if info == nil then return "gone" end
	if info.active == false then return "off" end   -- the game's addExperience / update skip inactive towns too
	if st.rate <= 0 then return "none" end
	local initSum, curSum = 0, 0
	for i = 1, 3 do
		initSum = initSum + (info.initials[i] or 0)
		curSum = curSum + (info.initials[i] or 0) * (info.sizeFactors[i] or 0)
	end
	if initSum <= 0 then return "gone" end
	local n = math.max(1, math.floor(dtYears * SG.STEPS_PER_YEAR + 0.5))
	local p = curSum
	for _ = 1, n do
		st.exp = st.exp + st.rate * p * (dtYears / n)
		p = math.max(p, initSum * SG.growthFactor(st.exp, st.l0))
	end
	local factor = SG.growthFactor(st.exp, st.l0)
	local newSum = initSum * factor
	-- (R7: the era's realistic split, the simulated year from the map's year at the start)
	local year = self.startYear and (self.startYear + (self.years or 0) + (self.yearFrac or 0)) or nil
	local mix = SG.mixFor(year)
	local f, d = SG.distribute({ initials = info.initials, sizeFactors = info.sizeFactors, mapSum = mapSum,
		newSum = newSum, minWeight = self.minW, weights = mix })
	st.factor, st.target = factor, newSum
	if newSum > curSum then st.markAdded = (st.markAdded or 0) + (newSum - curSum) end
	local fill = false
	if forced then
		local to = f or info.sizeFactors
		local target = 0
		for i = 1, 3 do target = target + (info.initials[i] or 0) * (to[i] or 0) end
		local caps = self.env.caps and self.env.caps(t) or nil
		fill = caps == nil or caps.actual == nil or caps.actual < SG.FILL_RATIO * target
		if fill and f == nil then f = { info.sizeFactors[1], info.sizeFactors[2], info.sizeFactors[3] } end
	end
	if f == nil then return "same" end
	st.pending, st.sentUs = true, self.nowUs
	self.inflight = self.inflight + 1
	self.sends = self.sends + 1
	self.yearTowns[#self.yearTowns + 1] = t
	if fill then
		self.yearFilled = self.yearFilled + 1
		self.fills = self.fills + 1
	end
	if d.added ~= nil then
		local level, fr = SG.levelAndFraction(st.exp)
		st.lastLine = { { "year", string.format("%.2f", self.years + (self.yearFrac or 0)) },
			{ "town", t }, { "name", self.env.name(t) }, { "rate", fmt2(st.rate) }, { "level", string.format("%d+%.2f", level, fr) },
			{ "factor", fmt2(factor) }, { "target", string.format("%.0f", newSum) }, { "persons", string.format("%.0f", curSum) },
			{ "added", list3(d.added, "%.0f") }, { "weights", list3(d.weights) }, { "mix", mix and "era" or "town" },
			{ "sizeFactors", list3(info.sizeFactors) },
			{ "to", list3(f) }, { "fill", fill } }
	end
	self.env.updateSize(t, f, function(success)
		if st.pending then
			st.pending = false
			self.inflight = math.max(0, self.inflight - 1)
		end
		if success then
			self.applied = self.applied + 1
			self.yearApplied = self.yearApplied + 1
			st.applied = (st.applied or 0) + 1
		else
			self.fails = self.fails + 1
			self:log("town", { { "town", t }, { "ok", false } })
		end
	end, fill)
	return fill and "filled" or "sent"
end

--- Σ built and target person capacity of the simulated towns (env.caps), or nil.
function Sim:capacity()
	if self.env.caps == nil then return nil end
	local actual, target = 0, 0
	for _, t in ipairs(self.order) do
		local c = self.env.caps(t)
		if c and c.actual and c.target then actual, target = actual + c.actual, target + c.target end
	end
	return actual, target
end

--- Year summary: SIMGROW year with totals, timing (s = real seconds since the last year), the built capacity vs the
--- target (cap: how far the houses lag the sizes), Fast fill and the main mod wait, and the top towns; logs each
--- town that grew this year (its last step).
function Sim:yearSummary(now)
	local env = self.env
	local builds = env.buildings and env.buildings() or {}
	local total, totalStart, growing = 0, 0, 0
	local rows = {}
	for _, t in ipairs(self.order) do
		local st = self.towns[t]
		local b = builds[t] or 0
		total, totalStart = total + b, totalStart + (st.startBuildings or 0)
		if st.rate > 0 then growing = growing + 1 end
		rows[#rows + 1] = { t = t, b = b, st = st }
		if st.lastLine then
			local l = st.lastLine
			l[#l + 1] = { "buildings", b }
			self:log("town", l)
			st.lastLine = nil
		end
	end
	table.sort(rows, function(a, b) if a.b ~= b.b then return a.b > b.b end return a.t < b.t end)
	local top = {}
	for i = 1, math.min(SG.TOP_N, #rows) do
		local r = rows[i]
		top[#top + 1] = string.format("%s:%d:x%.2f:r%.2f", (tostring(env.name(r.t)):gsub("[%s=,]", "_")), r.b, r.st.factor or r.st.startFactor or 1,
			r.st.rate)
	end
	self.buildingsTotal, self.buildingsStart, self.growing = total, totalStart, growing
	local actual, target = self:capacity()
	self.capText = actual and target > 0 and string.format("%.0f/%.0f(%d%%)", actual, target, math.floor(100 * actual / target + 0.5)) or "-"
	local secs = now and self.lastYearUs and (now - self.lastYearUs) / 1e6 or nil
	self.lastYearUs = now or self.lastYearUs
	-- (2026-10-14: buildings added this year and the rate, buildings per real s: the Quick estimate is ~0.7 s x quiet
	-- years + buildings added / 90)
	local addedY = total - (self.lastTotal or totalStart)
	self.lastTotal = total
	local rateY = (secs and secs > 0) and addedY / secs or nil
	self.lastYearS = secs
	local w = self.waitInfo
	local wf = self.waitFill
	local res = {}
	for _, k in ipairs({ "sent", "same", "none", "busy", "off", "gone" }) do
		if (self.yearRes[k] or 0) > 0 then res[#res + 1] = k .. ":" .. self.yearRes[k] end
	end
	local mc = env.mainCounts and env.mainCounts() or nil
	local lc = self.lastCounts or {}
	local frames = mc and (mc.frames or 0) - (lc.frames or 0) or nil
	local gapHeld = mc and (mc.gapHeld or 0) - (lc.gapHeld or 0) or nil
	if mc then self.lastCounts = { frames = mc.frames or 0, gapHeld = mc.gapHeld or 0 } end
	-- (Build out: one SIMGROW chunk line per chunk, the year line's fields after chunk= of=)
	local fields = {}
	if self.chunk then
		self.chunks = (self.chunks or 0) + 1
		fields[1] = { "chunk", self.chunks }
		fields[2] = { "of", self.limit > 0 and math.ceil(self.limit / self.chunk) or "-" }
		fields[3] = { "years", self.chunk }
	end
	for _, f in ipairs({ { "year", self.years }, { "s", secs and string.format("%.1f", secs) or "-" }, { "pace", self.pace },
		{ "frames", frames or "-" }, { "gapHeld", gapHeld or "-" },
		{ "towns", #self.order }, { "growing", growing }, { "applied", self.yearApplied },
		{ "buildings", string.format("%d(+%d)", total, total - totalStart) }, { "added", addedY },
		{ "perS", rateY and string.format("%.0f", rateY) or "-" }, { "cap", self.capText },
		{ "res", #res > 0 and table.concat(res, ",") or "-" },
		{ "sizesS", self.sizesS and string.format("%.1f", self.sizesS) or "-" },
		{ "waitS", w and string.format("%.1f", w.s) or "-" }, { "main", w and string.format("%s/%d", tostring(w.seen or "-"), w.total or 0) or "-" },
		{ "mainChecks", w and w.checks or "-" }, { "mainBuilds", w and w.builds or "-" }, { "timeout", w and w.timeout or false },
		{ "filled", self.yearFilled }, { "fillS", self.fillS and string.format("%.1f", self.fillS) or "-" },
		{ "fillEarly", self.yearEarly or 0 },
		{ "waitFillS", wf and string.format("%.1f", wf.s) or "-" },
		{ "mainFill", wf and string.format("%s/%d", tostring(wf.seen or "-"), wf.total or 0) or "-" },
		{ "mainFillBuilds", wf and wf.builds or "-" },
		{ "round", self.roundInfo and string.format("%d/%d", self.roundInfo.builds or 0, self.roundInfo.towns or 0) or "-" },
		{ "roundS", self.roundInfo and string.format("%.1f", self.roundInfo.s or 0) or "-" },
		{ "speed", env.speed and env.speed() or "-" }, { "fails", self.fails }, { "top", table.concat(top, ",") } }) do
		fields[#fields + 1] = f
	end
	self:log(self.chunk and "chunk" or "year", fields)
	self.yearApplied, self.yearFilled, self.yearTowns, self.fillS, self.waitInfo = 0, 0, {}, nil, nil
	self.waitFill, self.sizesS, self.yearRes, self.waitKind, self.roundInfo = nil, nil, {}, nil, nil
	self.yearEarly, self.fillUs0 = 0, nil
end

--- The year is over (after its fill and the wait): summary, year limit. Returns "limit" when reached.
function Sim:endYear(now)
	self:yearSummary(now)
	if self.limit > 0 and self.years >= self.limit then return "limit" end
	return nil
end

--- Towns to wait for after a fill year's size step: the WAIT_TOWNS that gained the most persons since the last wait
--- (2026-10-13: the main driver checked ~4 of 13 grown towns in the 15 s cap; the fast towns matter most). Resets the
--- tally.
function Sim:waitTowns(n)
	local rows = {}
	for _, t in ipairs(self.order) do
		local st = self.towns[t]
		if (st.markAdded or 0) > 0 then rows[#rows + 1] = { t = t, a = st.markAdded } end
		st.markAdded = 0
	end
	table.sort(rows, function(a, b) if a.a ~= b.a then return a.a > b.a end return a.t < b.t end)
	local out = {}
	for i = 1, math.min(n or SG.WAIT_TOWNS, #rows) do out[i] = rows[i].t end
	return out
end

--- Waiting for the main mod: after a fill year's size step (kind "sizes": until its driver has checked the towns that
--- grew most, or they are on a long cooldown, and has no job running, or WAIT_MAX_S; then the fill) or after the fill
--- (kind "fill": the same for the filled towns, at most WAIT_FILL_S; then the year ends).
function Sim:waitTick(now)
	local waited = now - (self.waitStartUs or now)
	local info = self.env.mainSeen and self.env.mainSeen(self.mark, now) or nil
	self.waitNow = info
	local cap = self.waitKind == "fill" and SG.WAIT_FILL_S or SG.WAIT_MAX_S
	local timeout = waited >= cap * 1e6
	if info == nil or ((info.seen or 0) >= (info.total or 0) and not info.busy) or timeout then
		local w = { s = waited / 1e6, seen = info and info.seen or nil, total = info and info.total or 0,
			checks = info and info.checks or nil, builds = info and info.builds or nil, timeout = timeout and info ~= nil }
		self.mark, self.waitNow = nil, nil
		if self.waitKind == "fill" then
			self.waitFill = w
			self.phase = "run"
			self.lastUs = now
			return self:endYear(now)
		end
		self.waitInfo = w
		return self:startFill(now)
	end
	return nil
end

--- Fast fill (after the main mod's turn, 2026-10-13: its streets before the forced houses): the lagging towns get
--- their current size again with updateAllBuildings (Sim:townFill), a few per tick.
--- Towns already filled during the round (Sim:earlyFill) are skipped; fillS then counts from the first early fill.
function Sim:startFill(now, afterRound)
	if not afterRound then self.earlyDone, self.filledTowns = {}, {} end
	self.phase = "fill"
	self.fillQueue = {}
	for _, t in ipairs(self.order) do
		if not self.earlyDone[t] then self.fillQueue[#self.fillQueue + 1] = t end
	end
	self.fillUs0 = self.fillUs0 or now
	return nil
end

--- A town's fill while the round still runs elsewhere (2026-10-14): its own round jobs have ended (the runner's
--- roundReady: served, capped or cut, and no running job of a town whose plan extent may meet its own), so the
--- forced houses still come after the main mod's streets there. The runner keeps neighbour jobs off a filling town
--- (roundFilling). Once per town and round.
function Sim:earlyFill(t, now)
	if self.earlyDone[t] then return end
	self.earlyDone[t] = true
	local env, h = self.env, self.roundH
	local hooks = env.roundFilling and {
		before = function() env.roundFilling(h, t, true) end,
		after = function() env.roundFilling(h, t, false) end,
	} or nil
	if self:townFill(t, hooks) == "filled" then
		if self.fillUs0 == nil then self.fillUs0 = now end
		self.yearEarly = self.yearEarly + 1
		self.earlyFills = self.earlyFills + 1
	end
end

--- One fill tick: sends, then waits for the callbacks (or CMD_TIMEOUT_US), then the short wait for the main mod.
function Sim:fillTick(now)
	local n = 0
	while #self.fillQueue > 0 and n < SG.SEND_PER_TICK and self.inflight < SG.INFLIGHT_MAX do
		self:townFill(table.remove(self.fillQueue, 1))
		n = n + 1
	end
	if #self.fillQueue > 0 then return nil end
	if self.inflight > 0 and now - (self.fillUs0 or now) < SG.CMD_TIMEOUT_US then return nil end
	self.fillS = (now - (self.fillUs0 or now)) / 1e6
	local mark = (self.waitMain and not self.buildRound and #self.filledTowns > 0 and self.env.mainMark)
		and self.env.mainMark(self.filledTowns, now) or nil
	if mark ~= nil then
		self.phase, self.waitKind, self.mark, self.waitStartUs = "wait", "fill", mark, now
		return nil
	end
	self.phase = "run"
	self.lastUs = now
	return self:endYear(now)
end

--- A town's fill: its current size again with updateAllBuildings when its built capacity is under FILL_RATIO of its
--- target. hooks = { before(), after(success) } or nil (around the command: Sim:earlyFill). Returns "filled" | "full"
--- | "none" | "busy" | "off" | "gone".
function Sim:townFill(t, hooks)
	local st = self.towns[t]
	if st == nil then return "gone" end
	if st.rate <= 0 then return "none" end
	if st.pending then return "busy" end
	local info = self.env.town(t)
	if info == nil then return "gone" end
	if info.active == false then return "off" end
	local target = 0
	for i = 1, 3 do target = target + (info.initials[i] or 0) * (info.sizeFactors[i] or 0) end
	local caps = self.env.caps and self.env.caps(t) or nil
	if not (caps == nil or caps.actual == nil or caps.actual < SG.FILL_RATIO * target) then return "full" end
	local f = { info.sizeFactors[1], info.sizeFactors[2], info.sizeFactors[3] }
	st.pending, st.sentUs = true, self.nowUs
	self.inflight = self.inflight + 1
	self.sends = self.sends + 1
	self.yearFilled = self.yearFilled + 1
	self.fills = self.fills + 1
	self.filledTowns[#self.filledTowns + 1] = t
	if hooks and hooks.before then hooks.before() end
	self.env.updateSize(t, f, function(success)
		if st.pending then
			st.pending = false
			self.inflight = math.max(0, self.inflight - 1)
		end
		if not success then
			self.fails = self.fails + 1
			self:log("town", { { "town", t }, { "ok", false }, { "fill", true } })
		end
		if hooks and hooks.after then hooks.after(success) end
	end, true)
	return "filled"
end

--- Step results per year (res=) and stalls: a growing town that returns off / gone / busy STALL_STEPS steps in a row is
--- logged once (SIMGROW stall: why, development active, initials, size factors, pending seconds). 2026-10-13: every
--- town whose initial capacities the main mod's dose fill had restored stopped getting steps for the rest of the run
--- (Bilston from year 4, Braintree from year 12; no timeout, no failed command); the line names the branch.
function Sim:noteResult(t, res)
	self.yearRes[res] = (self.yearRes[res] or 0) + 1
	local st = self.towns[t]
	if st == nil then return end
	if res == "off" or res == "gone" or res == "busy" then
		st.stuck = (st.stuck or 0) + 1
		if st.stuck >= SG.STALL_STEPS and not st.stallLogged then
			st.stallLogged = true
			local info = self.env.town(t)
			self:log("stall", { { "town", t }, { "name", self.env.name(t) }, { "why", res }, { "steps", st.stuck },
				{ "active", info and tostring(info.active ~= false) or "nil" },
				{ "initials", info and list3(info.initials, "%.0f") or "-" }, { "sizeFactors", info and list3(info.sizeFactors) or "-" },
				{ "pendingS", st.pending and st.sentUs and self.nowUs and string.format("%.1f", (self.nowUs - st.sentUs) / 1e6) or "-" },
				{ "factor", fmt2(st.factor) }, { "applied", st.applied or 0 } })
		end
		if res == "off" then self:reactivate(t, st) end
	else
		if st.offSteps then
			-- the town gets steps again after an "off" spell (the main mod's FILL reactivate or ours)
			self:log("resume", { { "town", t }, { "name", self.env.name(t) }, { "offSteps", st.offSteps },
				{ "reactivations", st.reactSent or 0 } })
		end
		st.stuck, st.offSteps = 0, nil
	end
end

--- A town found with development off that was active at Start (2026-10-13 run: Thornaby-on-Tees, Market_Drayton and
--- Cheadle stayed off to the end, res=off, though the main mod logged FILL reactivate once each; their later dose fills
--- read active=false->false, so it never tried again): development switched back on (the game itself never switches it
--- off; the main mod's dose fill did), after STALL_STEPS off steps, at most REACTIVATE_MAX times per town. The town is
--- re-read at every step, so it resumes as soon as the game reports it active (SIMGROW resume).
function Sim:reactivate(t, st)
	st.offSteps = (st.offSteps or 0) + 1
	if not st.wasActive or self.env.reactivate == nil or st.reactPending then return end
	if (st.stuck or 0) < SG.STALL_STEPS or (st.reactSent or 0) >= SG.REACTIVATE_MAX then return end
	st.reactSent = (st.reactSent or 0) + 1
	st.reactPending = true
	local n = st.reactSent
	self.env.reactivate(t, function(ok)
		st.reactPending = false
		self:log("reactivate", { { "town", t }, { "name", self.env.name(t) }, { "try", n }, { "ok", ok == true } })
	end)
end

--- Build round (the chunk's end, before the fill): towns = every town that grew since the last round (most growth
--- first). The runner holds the main driver's scheduler and runs the main mod's own check -> plan -> build on each
--- (env.roundStart / roundTick). No round possible (no main driver visible): logged, the year goes on.
function Sim:startRound(now, towns, fill)
	self.roundFill = fill == true
	self.roundUs0 = now
	self.earlyDone, self.earlyQueue, self.filledTowns = {}, {}, {}
	local h, why = nil, "noTowns"
	if #towns > 0 then
		why = "noRound"
		if self.env.roundStart then
			h, why = self.env.roundStart(towns, now, { builds = self.roundMaxBuilds, maxS = self.roundMaxS })
		end
	end
	if h == nil then
		self.roundInfo = { towns = #towns, checks = 0, builds = 0, s = 0, why = why or "noMain" }
		self:logRound(self.roundInfo)
		return self:afterRound(now)
	end
	self.phase, self.roundH = "round", h
	return nil
end

function Sim:roundTick(now)
	-- (a fill year: the towns whose round part ended are filled while the others still build, a few per tick)
	if self.roundFill and self.env.roundReady then
		for _, t in ipairs(self.env.roundReady(self.roundH) or {}) do self.earlyQueue[#self.earlyQueue + 1] = t end
		local n = 0
		while #self.earlyQueue > 0 and n < SG.SEND_PER_TICK and self.inflight < SG.INFLIGHT_MAX do
			self:earlyFill(table.remove(self.earlyQueue, 1), now)
			n = n + 1
		end
	end
	local res = { why = "noRoundTick" }
	if self.env.roundTick then res = self.env.roundTick(self.roundH, now) end
	if res == nil then
		if now - (self.roundUs0 or now) < SG.ROUND_GUARD_S * 1e6 then return nil end
		res = { why = "guard", s = (now - (self.roundUs0 or now)) / 1e6 }
	end
	self.roundH = nil
	self.roundInfo = res
	self.rounds = self.rounds + 1
	self.roundBuilds = self.roundBuilds + (res.builds or 0)
	self:logRound(res)
	return self:afterRound(now)
end

function Sim:logRound(res)
	self:log("round", { { "year", self.years }, { "towns", res.towns or 0 }, { "checks", res.checks or 0 },
		{ "builds", res.builds or 0 }, { "edges", res.edges or 0 }, { "served", res.served or 0 }, { "capped", res.capped or 0 },
		{ "demandLeft", res.demandLeft and string.format("%.0f", res.demandLeft) or "-" },
		{ "s", string.format("%.1f", res.s or 0) }, { "peak", res.peak or 0 }, { "why", res.why or "done" },
		{ "per", res.per or "-" } })
end

--- After the round: the fill (a fill year) or the year's end.
function Sim:afterRound(now)
	if self.roundFill then return self:startFill(now, true) end
	self.phase = "run"
	self.lastUs = now
	return self:endYear(now)
end

--- One tick: advances the simulated clock while the game runs (not while a fill year waits or fills), starts a step
--- every pace / cmdSteps (1 per year at fast paces, 4 at slow ones), works the step's queue a few towns per tick. A
--- Fast fill year (2026-10-13 order): the year's size commands and their callbacks, then the wait for the main mod
--- (its checks and builds on the grown towns: its streets first), then the fill (forced buildings), then a short wait.
--- Returns "limit" when the year limit was reached (the caller stops).
function Sim:tick(now)
	if not self.running then return nil end
	self.nowUs = now
	local speed = self.env.speed and self.env.speed() or 1
	local dt = now - (self.lastUs or now)
	self.lastUs = now
	if self.phase == "wait" then return self:waitTick(now) end
	if self.phase == "fill" then return self:fillTick(now) end
	if self.phase == "round" then return self:roundTick(now) end
	-- (pace 0: no minimum real time per year; a step still starts only while the game runs, and the year ends once
	-- its size commands came back, so no step finds a town busy)
	local runs = speed ~= nil and speed > 0
	if not self.queueYear and runs and dt > 0 and dt < 5e6 then self.simUs = self.simUs + dt end
	local cmdSteps = self.chunk and 1 or SG.cmdSteps(self.pace)
	local stepUs = (self.pace or 0) * 1e6 / cmdSteps
	if #self.queue == 0 and not self.queueYear and runs and self.simUs >= stepUs then
		self.simUs = self.simUs - stepUs
		if self.simUs > stepUs then self.simUs = stepUs end   -- no burst after a stall
		self.step = self.step + 1
		self.stepMap = self:mapSum()
		if self.chunk then
			-- (Build out: one step of `chunk` years, the experience still integrated in quarter years by townStep)
			self.stepDt = self.chunk
			self.yearFrac = self.chunk
			self.queueYear = true
		else
			self.stepDt = math.min(1 / cmdSteps, 1 - (self.yearFrac or 0))
			if self.stepDt <= 1e-9 then self.stepDt = 1 / cmdSteps end
			self.yearFrac = (self.yearFrac or 0) + self.stepDt
			self.queueYear = self.yearFrac >= 1 - 1e-6
		end
		self.stepForced = self.queueYear and self:fillYear()
		self.stepRound = self.queueYear and self:roundYear()
		self.stepUs0 = now
		for _, t in ipairs(self.order) do self.queue[#self.queue + 1] = t end
	end
	local n = 0
	while #self.queue > 0 and n < SG.SEND_PER_TICK and self.inflight < SG.INFLIGHT_MAX do
		local t = table.remove(self.queue, 1)
		self:noteResult(t, self:townStep(t, self.stepDt or 1 / cmdSteps, self.stepMap, false))
		n = n + 1
	end
	if #self.queue == 0 and self.queueYear then
		local awaited = self.stepForced or self.stepRound or (self.pace or 0) <= 0
		if awaited and self.inflight > 0 and now - (self.stepUs0 or now) < SG.CMD_TIMEOUT_US then
			return nil   -- a fill / round year (or pace 0): the size commands' callbacks first
		end
		self.queueYear = false
		self.yearFrac = 0
		self.years = self.years + (self.chunk or 1)
		if self.stepRound or self.stepForced or (self.limit > 0 and self.years >= self.limit) then self:moveDateNow() end
		if self.stepRound then
			self.sizesS = (now - (self.stepUs0 or now)) / 1e6
			return self:startRound(now, self:waitTowns(#self.order), self.stepForced)
		end
		if self.stepForced then
			self.sizesS = (now - (self.stepUs0 or now)) / 1e6
			local towns = self:waitTowns()
			local mark = (self.waitMain and #towns > 0 and self.env.mainMark) and self.env.mainMark(towns, now) or nil
			if mark ~= nil then
				self.phase, self.waitKind, self.mark, self.waitStartUs = "wait", "sizes", mark, now
				return nil
			end
			return self:startFill(now)
		end
		return self:endYear(now)
	end
	return nil
end

--- Plain status for the HUD.
function Sim:status()
	local c = self.counts or {}
	local doing = ""
	if self.running and self.phase == "wait" then
		local w = self.waitNow
		doing = string.format("; waiting for the main mod (%s/%d towns checked, %.0f s%s)", tostring(w and w.seen or 0),
			w and w.total or #self.yearTowns, ((self.nowUs or 0) - (self.waitStartUs or self.nowUs or 0)) / 1e6,
			self.waitKind == "fill" and ", after the fill" or "")
	elseif self.running and self.phase == "round" then
		doing = string.format("; build round (the main mod's turn, %.0f s)", ((self.nowUs or 0) - (self.roundUs0 or self.nowUs or 0)) / 1e6)
	elseif self.running and self.phase == "fill" then
		doing = string.format("; filling %d towns", self.yearFilled)
	elseif self.running and self.stepForced and self.queueYear then
		doing = "; sizes before the fill"
	end
	-- (pace 0: "as fast as possible"; Build out: chunks of years)
	local paceText = (self.pace or 0) <= 0 and "as fast as possible" or (tostring(self.pace) .. " s per year")
	if self.chunk then
		paceText = string.format("build out, %d-year chunks: %d of %s", self.chunk, self.chunks or 0,
			self.limit > 0 and tostring(math.ceil(self.limit / self.chunk)) or "-")
	end
	local last = self.lastYearS and string.format(", last %.0f s", self.lastYearS) or ""
	local head = string.format("%s: %d simulated years (%s%s, seed %d, %s%s), %d towns: %d growing (%d slow, %d medium, "
		.. "%d fast), %d not connected; buildings %d (+%d), capacity %s; size steps %d%s%s",
		self.running and "Running" or ("Stopped" .. (self.stopReason and (" (" .. self.stopReason .. ")") or "")),
		self.years, paceText, last, self.seed,
		self.near and "near camera" or "all towns",
		self.fastFill and string.format(", fast fill every %d", self.fillEvery) or "", #self.order,
		(c.slow or 0) + (c.medium or 0) + (c.fast or 0), c.slow or 0, c.medium or 0, c.fast or 0, c.none or 0,
		self.buildingsTotal or 0, (self.buildingsTotal or 0) - (self.buildingsStart or 0), self.capText or "-", self.applied,
		self.fails > 0 and string.format(", %d failed", self.fails) or "", doing)
	return { running = self.running, years = self.years, head = head, autoTour = self.autoTour, pace = self.pace,
		seed = self.seed, near = self.near ~= nil, limit = self.limit, bias = self.bias, tourWhenDone = self.tourWhenDone,
		fastFill = self.fastFill, fillEvery = self.fillEvery, waitMain = self.waitMain, buildRound = self.buildRound,
		phase = self.phase, rounds = self.rounds, roundBuilds = self.roundBuilds, mode = self.mode, chunk = self.chunk,
		moveDate = self.moveDate }
end

SG.Sim = Sim
return SG
