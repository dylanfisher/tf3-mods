-- Organic Towns: upward density in big towns (pure; later-ideas phase, 2026-10-13).
--
-- User (MOTIFS_BRIEF "Other ideas"): "upward density in big towns (core intensification instead of endless sprawl)".
-- Real map round 4 (session 2026-10-13_0232_sqot-dev): at 1000-3500 buildings the towns read as blobs; every new
-- resident needed a new lot, so the town spread outward (the game's own streets ~60 %, the mod's arms and fill). A big
-- town should instead grow taller in its core.
--
-- Lever: makeTownDevelopAtCmd(point, developStreets = false, upgradeBuildings = true) at a few points in the town's
-- core, along its main streets where houses already stand. Its side effect is known (findings towns.md: DevelopAt
-- resets the town's initial capacities to its current size, v5's fill twin grew 12x), so the driver puts the initial
-- capacities back right after the calls with NO allowance (EXTRA 0: the target stays what it was, unlike the dose's
-- +15 %). Whatever the upgrades add to the core's capacity then houses residents the target would otherwise send to new
-- lots at the edge. Whether upgradeBuildings really raises the buildings near the point is unverified (Showcase v6: one
-- dose with the flag showed no clear effect; it was never measured in a core): `UPWARD effect` logs the person capacity
-- per building (whole town) and the buildings near the points before -> after.
--
-- Who (M.decide): a town of at least MIN_BUILDINGS buildings, or of PRESSURE_BUILDINGS with PRESSURE_PLANS demand plans
-- in a row that came out held (the form can't absorb the demand: empty / own-empty / wedge / housed / lead holds); not a
-- metropolis (its fill is its own), not forced / head-start jobs; at most every GAP_S per town (jittered by id), never
-- while a fill's growth wave may still come (the dose's surge rule). Brakes: the restore (EXTRA 0) and CAP_K x the
-- town's base initial capacity (above it no upward dose at all).
-- What changes: the demand build of such a town is cut to (1 - cut) of its edges (CUT, by size), so the mod's own
-- streets stop leading the sprawl, and an upward dose follows the build (or an empty plan). Nothing saved; no street,
-- node or proposal code (the crash rule is untouched).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

M.ON = true
M.MIN_BUILDINGS = 1500       -- a big town
M.PRESSURE_BUILDINGS = 700   -- ... or a town this big whose demand the form can't absorb:
M.PRESSURE_PLANS = 3         -- ... this many demand plans in a row held (empty, or less than PRESSURE_SHARE of the ask)
M.PRESSURE_SHARE = 0.5
M.GAP_S = 240                -- real s between two upward doses of a town (x 0.75..1.25 by town id)
M.POINTS = 3                 -- DevelopAt points per dose
M.CORE_K = 0.45              -- the core: within this x the town's building radius (r90) of the centre ...
M.CORE_MIN, M.CORE_MAX = 200, 900   -- ... clamped (m)
M.SPACING = 150              -- m between a dose's points and from the last RECENT points
M.RECENT = 12
M.OFFSET = 18                -- m beside a street's midpoint (the lots, not the carriageway)
M.NEAR = 60                  -- m: buildings counted around a point (density score, effect line)
M.CLASS_W = { main = 1.6, medium = 1.3, small = 1 }   -- along main streets first
M.MIN_HOUSES = 3             -- a point needs this many buildings within NEAR (upgrade where houses stand)
M.EXTRA = 0                  -- the restore allows no rise of the initial capacities
M.CAP_K = 1.6                -- no upward dose above this x the town's base initial capacity sum
M.CUT = { 0.25, 0.5 }        -- demand increment cut at MIN_BUILDINGS .. CUT_FULL buildings (pressure towns: CUT[1])
M.CUT_FULL = 4000
-- (2026-10-14, the vanilla baseline BASELINE_VANILLA.md: the same population in 39 % more buildings, 3.0 persons per
-- building against vanilla's 4.6, `ups=` 0-1 per town) a SPARSE town fires too: SPARSE_BUILDINGS buildings or more at
-- fewer than SPARSE_PB persons (residents + jobs) per building; its demand build gives up CUT_SPARSE
-- (2026-10-14 late, the same-seed comparison against true vanilla, session 2026-10-14_0119_sqot: UPWARD ran 3 times in
-- 40 years; 22 of its 25 skips were `surge` (the dev simulation's Fast fill every 4th year grows every town > 25 % in
-- a few minutes, so the dose's surge rule always held it), and its 3 doses moved the persons per building by nothing
-- (4.00 -> 3.98, 2.74 -> 2.74, UPWARD effect): DevelopAt's upgradeBuildings does not raise a core. Now: no surge rule
-- for upward (its restore is exact, EXTRA 0, so it can't run away), sparse from 250 buildings under PB_AIM, and the
-- lever that does change building size, the town's level weights (M.levelDecide below, driver LEVELS).)
M.SPARSE_BUILDINGS = 250
M.SPARSE_PB = 4.5
M.CUT_SPARSE = 0.2
M.SURGE_BLOCKS = false       -- the dose's surge rule holds an upward dose (true until 2026-10-14 late)

-- Level weights (2026-10-14 late). makeTownCustomDistributionWeightsCmd(town, {{4} x 3 land uses}) (findings towns.md
-- "Per-town building levels") sets a town's level-to-capacity distribution weights: town-wide, saved with the town (it
-- stays after the mod is removed), the game's own target capacity per level (computeUnweightedTarget...) is weighted by
-- them (the debug panel lists actual, unweighted and weighted). The Stress Test's showcase towns with {0, 0.1, 0.5, 1}
-- rebuilt "taller and fewer" at the same capacity (33517 -> 21623 buildings, towns.md "A forced size command"). The
-- capacity and the target stay the game's: only the mix of building sizes changes. Who: a town the driver acts on, on
-- a new map, from LV_MIN_BUILDINGS buildings, whose weights are the game's default or ours (a player's custom weights
-- are never touched); strength k (0..1 in LV_Q steps) from how far its persons per building are below PB_AIM
-- (PB_LOW and below: 1); weights r^(level - 1) / r^3 with r = 1 + LV_STEP x k for all three land uses; at least LV_GAP_S
-- between two sends per town; ours cleared again (back to the game's default) at LV_CLEAR_PB. LEVELS lines.
M.LEVELS = true
M.PB_AIM = 4.5
M.PB_LOW = 2.5
M.LV_STEP = 0.6
M.LV_Q = 0.25
M.LV_MIN_BUILDINGS = 150
M.LV_GAP_S = 300
M.LV_CLEAR_PB = 5.5
-- (2026-10-14, run 2026-10-14_0302_sqot-sqrl: all 16 towns got weights at 150-210 buildings, in their first years,
-- and 4 were cleared at ~500 when their pb passed 5.5. Before 1950 the game has town buildings of levels 1-2 only
-- (era A, base/content/buildings/townbuildingutil.lua: level 3 from 1950, level 4 from 1990; findings towns.md), so
-- the weights could only tilt level 1 -> 2: actual level 3-4 capacity stayed 0 % in every town although the weighted
-- target asked 57 %. Now the weights are for grown towns only: none below LV_MAT maturity (ot_assess.maturity, from
-- the town's persons), the strength k scaled by the maturity, so a town builds up late and gradually. The API is
-- town-wide (no centre-first); the centre-first part stays the upward dose's.)
M.LV_MAT = 0.5              -- (until 2026-10-15; now LV_BLEND_MAT and the phases below)
-- (strong characters / densify, ot_character 2026-10-14; the values mirror ot_character DZ_* / LEVELS_EARLY_*: ot_upward
-- stays free of that module)
M.EARLY_MAT = 0.15         -- a dense kind (hilltop, harbour cove, company town, island town): weights from this maturity
M.EARLY_K = 0.5            -- ... at least this strength
M.DZ_PB_AIM = 8            -- a mature densify town aims at this many persons per building
M.DZ_K_MIN = 0.75          -- ... with at least this strength
M.DZ_CLEAR_PB = 11         -- ... cleared only from this

-- LEVELS by maturity (2026-10-15, NEXT_PHASE_BRIEF 58; run 2026-10-14_2347_sqot-dev load 3). The run's "mod-set" weights
-- that held Edton (699 buildings) at 100/0/0/0 were never sent by LEVELS (`ours=0` on every line): they appeared in
-- step with the mod's FILL restores (makeTownSetInitialLandUseCapacitiesCmd after a dose's DevelopAt), on exactly the
-- towns that got one (5 at year 1, the rest later; the 5 towns never restored stayed `c:-` and reached pb 4.0-5.0).
-- Their rows are no editor's (max < 1, many decimals), but LEVELS read them as the player's and never ran. Now:
-- * owner "fill" (M.levelOwner): custom weights that are none of ours, not the baseline and no town editor's
--   (M.editorLike: the editor writes rows normalised to 1 or slider steps of 0.01) are the engine's own write after
--   the mod's capacity restore: LEVELS may replace them. A player's (editor-like) weights stay untouched.
-- * the phase by the town's level maturity (M.levelMat: persons as ot_assess.maturity, or buildings from LV_B_LO to
--   LV_B_HI, the larger; a town held at level 1 houses few persons, so its persons alone read young for ever):
--     young   below LV_BLEND_MAT: nothing changes (no weights of ours; the fill weights stay);
--     blend   LV_BLEND_MAT .. LV_MATURE_MAT: a tilt toward level 1 that eases back to the engine's weights
--             (-1 at half grown, 0 at LV_MATURE_MAT, in LV_Q steps);
--     mature  from LV_MATURE_MAT: the engine's weights (tilt 0: the custom weights cleared, or the baseline) or above
--             them (the pb rule: levelK from PB_AIM, as before);
--     densify a drawn densify town from LV_BLEND_MAT: above the engine's weights, ramping in to DZ_RAMP_MAT.
-- * the tilt t (-1..1): t < 0 rows 1 / r^(l - 1), r = 1 + LV_HOLD_STEP x |t|; t > 0 rows r^(l - 1) / r^(top - 1),
--   r = 1 + LV_STEP x t (the old levelWeights for top = 4); t = 0 the engine's own (nil, or the baseline).
-- * the era (M.eraTop: levels 3 / 4 exist from 1950 / 1990, findings towns.md): a level above the era's top takes the
--   top's weight (the game builds its share at the top level anyway, run 2347: u 34/27/22/17 -> a 38/24/38/0), so no
--   tilt asks for buildings that can't exist, and none stays tilted toward them when the era opens.
M.LV_B_LO, M.LV_B_HI = 200, 800   -- buildings: level maturity 0 .. 1 (500 buildings: half grown, never held at level 1)
M.LV_BLEND_MAT = 0.5
M.LV_MATURE_MAT = 0.9
M.LV_HOLD_STEP = 1.5       -- tilt -1: 1 / 0.4 / 0.16 / 0.064 (w ~69/22/9 of the engine's 34/27/39 in 1950-1990)
M.DZ_RAMP_MAT = 0.75       -- a densify town's tilt is full from this level maturity
M.LV_MATURE_K = 0          -- a grown plain town's tilt above the engine's at most this from 1950 (top level 3+: the
                           -- engine's weights alone give pb ~4.9 in 1950-1990, 0.25 ~5.3, 0.75 ~6.2 by the run's fit,
                           -- the unmanaged towns of the run 4.0-5.0): the engine's own weights
M.LV_MATURE_K_TOP2 = 1     -- ... before 1950 (levels 1-2 only: pb at most ~4.2 however tilted)
M.ERA_L3, M.ERA_L4 = 1950, 1990
M.PHASES = { "young", "blend", "mature", "densify" }

--- The gap of town t in seconds (GAP_S spread by a hash of the id, so towns don't dose together).
function M.gapS(t)
	local u = (((tonumber(t) or 0) * 2246822519) % 1000) / 1000
	return M.GAP_S * (0.75 + 0.5 * u)
end

--- Share of a demand increment an upward town gives up: 0 below the threshold, CUT[1] .. CUT[2] by size.
function M.cut(buildings, why)
	if not M.ON then return 0 end
	if why == "pressure" then return M.CUT[1] end
	if why == "sparse" then return M.CUT_SPARSE end
	if why == "densify" then return M.CUT[2] end
	local b = buildings or 0
	if b < M.MIN_BUILDINGS then return 0 end
	local f = G.clamp((b - M.MIN_BUILDINGS) / math.max(1, M.CUT_FULL - M.MIN_BUILDINGS), 0, 1)
	return M.CUT[1] + (M.CUT[2] - M.CUT[1]) * f
end

--- Is the town an upward town now? o = { buildings, metro (bool), pressure (held plans in a row), forced, head,
--- last (the town's last upward record { us }), nowUs, town, initial (caps.initial), base (base initial sum),
--- persons (person capacity: residents + jobs, for the sparse rule),
--- surge (bool: a fill's growth wave may still come) }. Returns why ("big" | "pressure" | "sparse") or nil, skip reason.
function M.decide(o)
	if not M.ON then return nil, "off" end
	if o.forced or o.head then return nil, "forced" end
	if o.metro then return nil, "metro" end
	local b = o.buildings or 0
	local why = nil
	if b >= M.MIN_BUILDINGS then why = "big"
	elseif b >= M.PRESSURE_BUILDINGS and (o.pressure or 0) >= M.PRESSURE_PLANS then why = "pressure"
	elseif b >= M.SPARSE_BUILDINGS and o.persons and b > 0 and o.persons / b < M.SPARSE_PB then why = "sparse"
	-- (a mature densify town, ot_character 2026-10-14: its core doses from fewer buildings)
	elseif o.densify and b >= (o.dzMin or M.SPARSE_BUILDINGS) then why = "densify" end
	if why == nil then return nil, "small" end
	if o.base and o.base > 0 and o.initial and o.initial > M.CAP_K * o.base then return nil, "cap" end
	if o.last and o.last.us and o.nowUs and o.nowUs - o.last.us < M.gapS(o.town) * 1e6 then return nil, "gap", why end
	if o.surge and M.SURGE_BLOCKS then return nil, "surge", why end
	return why
end

--- Level-weight strength for a town at pb persons per building: 0 at PB_AIM or more, 1 at PB_LOW or less, x the
--- town's maturity mat (0..1, default 1), in LV_Q steps.
function M.levelK(pb, mat, aim)
	if pb == nil then return 0 end
	aim = aim or M.PB_AIM
	local k = G.clamp((aim - pb) / math.max(0.5, aim - M.PB_LOW), 0, 1) * G.clamp(mat or 1, 0, 1)
	return math.floor(k / M.LV_Q + 0.5) * M.LV_Q
end

--- The level weights for tilt k (-1..1; 0 / nil: none of ours, the engine's own) up to the era's top level (2..4,
--- default 4): k > 0 per land use { 1, r, r^2, r^3 } / r^3, r = 1 + LV_STEP x k (for top 4, as before 2026-10-15), a
--- level above top taking the top's weight; k < 0 { 1, 1/r, 1/r^2, 1/r^3 }, r = 1 + LV_HOLD_STEP x |k|. 3 decimals.
function M.levelWeights(k, top)
	k = tonumber(k) or 0
	top = math.max(2, math.min(4, math.floor(tonumber(top) or 4)))
	local row = {}
	if k >= 0 then
		local r = 1 + M.LV_STEP * k
		local hi = r ^ (top - 1)
		for l = 1, 4 do row[l] = math.floor(r ^ (math.min(l, top) - 1) / hi * 1000 + 0.5) / 1000 end
	else
		local r = 1 + M.LV_HOLD_STEP * math.min(1, -k)
		for l = 1, 4 do row[l] = math.floor(1 / r ^ (l - 1) * 1000 + 0.5) / 1000 end
	end
	return { { row[1], row[2], row[3], row[4] }, { row[1], row[2], row[3], row[4] }, { row[1], row[2], row[3], row[4] } }
end

--- The top building level the game can build in `year` (levels 3 / 4 from ERA_L3 / ERA_L4; nil: 4).
function M.eraTop(year)
	year = tonumber(year)
	if year == nil then return 4 end
	if year < M.ERA_L3 then return 2 end
	if year < M.ERA_L4 then return 3 end
	return 4
end

--- A town's level maturity (0..1): its maturity from persons (ot_assess.maturity; nil: 1) or from its buildings
--- (LV_B_LO .. LV_B_HI), the larger.
function M.levelMat(mat, buildings)
	local mb = G.clamp(((buildings or 0) - M.LV_B_LO) / math.max(1, M.LV_B_HI - M.LV_B_LO), 0, 1)
	return math.max(G.clamp(mat or 1, 0, 1), mb)
end

local function quant(x) return math.floor(x / M.LV_Q + 0.5) * M.LV_Q end

--- The phase and tilt of a town (no owner / gap rules): matL = M.levelMat, pb, densify (bool), early (a dense strong
--- kind), top (the era's top level, default 4). Returns phase ("young" | "blend" | "mature" | "densify" | "early"), tilt
--- (nil for young).
function M.levelPhase(matL, pb, densify, early, top)
	if early then
		if matL < M.EARLY_MAT then return "young", nil end
		return "early", math.max(M.levelK(pb, matL), M.EARLY_K)
	end
	if matL < M.LV_BLEND_MAT then return "young", nil end
	if densify then
		local e = G.clamp((matL - M.LV_BLEND_MAT) / math.max(0.01, M.DZ_RAMP_MAT - M.LV_BLEND_MAT), 0, 1)
		return "densify", quant(math.max(M.levelK(pb, 1, M.DZ_PB_AIM), M.DZ_K_MIN) * e)
	end
	if matL < M.LV_MATURE_MAT then
		local f = (matL - M.LV_BLEND_MAT) / math.max(0.01, M.LV_MATURE_MAT - M.LV_BLEND_MAT)
		local t = quant(-(1 - f))
		if t < 0 then return "blend", t end
	end
	return "mature", math.min(M.levelK(pb, 1), (top or 4) <= 2 and M.LV_MATURE_K_TOP2 or M.LV_MATURE_K)
end

--- The level-1 share (0..1) of the engine's weighted target for unweighted row u ({4}) and custom row c ({4}; nil
--- none).
function M.share1(u, c)
	if type(u) ~= "table" then return nil end
	local sum, one = 0, 0
	for l = 1, 4 do
		local v = (tonumber(u[l]) or 0) * (c and (tonumber(c[l]) or 0) or 1)
		sum = sum + v
		if l == 1 then one = v end
	end
	if sum <= 0 then return nil end
	return one / sum
end

--- Could these custom weights ({{4} x 3}) come from the town editor (base town_eow: a row it writes is normalised to
--- its largest weight, 1, or has a slider value, a multiple of 0.01)? Any such row: true. The engine's own writes after
--- a capacity restore (run 2026-10-14_2347: 0.453303/0.255125/0.100228/0) have neither.
function M.editorLike(rows)
	if type(rows) ~= "table" then return false end
	for i = 1, 3 do
		local r = rows[i]
		if type(r) == "table" then
			local mx = 0
			for l = 1, 4 do
				local v = tonumber(r[l]) or 0
				if v > mx then mx = v end
				if v > 0 and math.abs(v * 100 - math.floor(v * 100 + 0.5)) < 2e-3 then return true end
			end
			if math.abs(mx - 1) < 1e-3 then return true end
		end
	end
	return false
end

--- A comparable text of a town's custom level weights ({{4} x 3} or nil): "-" none, else the 12 numbers rounded to 3
--- decimals ("a/b/c/d;e/f/g/h;i/j/k/l"). The engine stores floats, so equal weights give equal texts.
function M.levelSig(rows)
	if type(rows) ~= "table" then return "-" end
	local out = {}
	for i = 1, 3 do
		local r = rows[i]
		if type(r) ~= "table" then return "-" end
		local p = {}
		for l = 1, 4 do
			local v = math.floor((tonumber(r[l]) or 0) * 1000 + 0.5) / 1000
			p[l] = string.format("%g", v)
		end
		out[i] = table.concat(p, "/")
	end
	return table.concat(out, ";")
end

--- The weights of a M.levelSig text ({{4} x 3}), nil for "-" or a malformed text.
function M.levelUnsig(sig)
	if type(sig) ~= "string" or sig == "-" then return nil end
	local rows = {}
	for part in sig:gmatch("[^;]+") do
		local r = {}
		for v in part:gmatch("[^/]+") do r[#r + 1] = tonumber(v) end
		if #r ~= 4 then return nil end
		rows[#rows + 1] = r
	end
	if #rows ~= 3 then return nil end
	return rows
end

--- Whose are a town's current custom weights? (2026-10-14, run 2026-10-14_0502_sqot: the generated towns carry custom
--- weights the mod never sent, the engine's own.) cur = M.levelSig of the current weights, base = the town's baseline
--- sig taken at the mod's first sight of the new map (nil: none taken, an old save), ours = the tilt the mod set with
--- the old formula (saved `lw`; 0 / nil none), rows = the current weights ({{4} x 3}; nil: unknown), sent = the sig of
--- the weights the mod last sent (saved `ls`, 2026-10-15; nil none). Returns "none" (no custom weights), "ours" (equal
--- to the weights the mod sent), "engine" (equal to the baseline), "player" (the town editor's kind, M.editorLike; or
--- anything when rows are unknown), or "fill" (2026-10-15: none of these, the engine's own write after the mod's FILL
--- restore, NEXT_PHASE_BRIEF 58).
function M.levelOwner(cur, base, ours, rows, sent)
	if cur == nil or cur == "-" then return "none" end
	if sent ~= nil and sent ~= "-" and cur == sent then return "ours" end
	if (ours or 0) > 0 and cur == M.levelSig(M.levelWeights(ours)) then return "ours" end
	if base ~= nil and cur == base then return "engine" end
	if rows ~= nil and not M.editorLike(rows) then return "fill" end
	return "player"
end

--- Should the driver send level weights now? o = { buildings, pb, mat (maturity from persons 0..1, default 1), custom
--- (the town has custom weights), owner (M.levelOwner of them, when read; nil: custom alone decides, as before
--- 2026-10-14: custom and not ours = the player's), ours (the tilt of the custom weights of ours: 0 / nil none), on (new
--- map, acted on), last (us of the last send), nowUs, town, deep, char ("off" | "early" | nil), densify (bool), top
--- (the era's top level, default 4), u / w (the residential unweighted / weighted target rows when read: a hold is
--- never lower than the town's current weights) }.
--- Returns "set" | "clear" | nil, k (the tilt, -1..1), why, phase (M.levelPhase; nil before it is known). A "clear"
--- returns the town to its engine baseline (or the game's default without one).
function M.levelDecide(o)
	if not M.LEVELS then return nil, 0, "off" end
	if not o.on then return nil, 0, "notNew" end
	local oursT = tonumber(o.ours) or 0
	local ours = oursT ~= 0
	if o.owner == "player" then return nil, 0, "player" end
	if o.owner == nil and o.custom and not ours then return nil, 0, "player" end
	if (o.buildings or 0) < M.LV_MIN_BUILDINGS then return nil, 0, "small" end
	-- (strong characters, ot_character 2026-10-14: a garden city stays low; the dense kinds build up early; a mature densify
	-- town aims higher (DZ_PB_AIM) with at least DZ_K_MIN and is cleared only far later)
	if o.char == "off" then
		if ours then return "clear", 0, "charOff" end
		return nil, 0, "charOff"
	end
	-- (a deep forest town stays low, 2026-10-14: no level weights of ours; any sent before it was deep are cleared)
	if o.deep then
		if ours then return "clear", 0, "deep" end
		return nil, 0, "deep"
	end
	if o.last and o.nowUs and o.nowUs - o.last < M.LV_GAP_S * 1e6 then return nil, 0, "gap" end
	local dzOn = o.densify == true
	local matL = M.levelMat(o.mat, o.buildings)
	local phase, t = M.levelPhase(matL, o.pb, dzOn, o.char == "early", o.top)
	if ours and o.pb and o.pb >= (dzOn and M.DZ_CLEAR_PB or M.LV_CLEAR_PB) then return "clear", 0, "dense", phase end
	-- (a young town: no weights of ours, none changed; weights already sent stay until the clear rule above; the
	-- engine's fill weights stay too: the young town is held low as before)
	if t == nil then return nil, 0, "young", phase end
	if t <= 0 and phase ~= "blend" then
		-- (the engine's weights: ours from the blend go, ours above them stay until the clear rule, fill weights go)
		if ours and oursT < 0 then return "clear", 0, "eased", phase end
		if ours then return nil, 0, "keep", phase end
		if o.owner == "fill" then return "clear", 0, "fill", phase end
		return nil, 0, "dense", phase
	end
	-- (a hold never lowers a town: with the current weighted target read, the blend's tilt rises (LV_Q steps) until its
	-- level-1 share is no more than the current one; a town at the engine's own weights so gets none)
	if t < 0 and o.u ~= nil and o.w ~= nil then
		local cur = M.share1(o.w, nil)
		local guard = 0
		while cur ~= nil and t < 0 and guard < 8 do
			guard = guard + 1
			local s1 = M.share1(o.u, M.levelWeights(t, o.top)[1])
			if s1 == nil or s1 <= cur + 1e-6 then break end
			t = quant(t + M.LV_Q)
		end
		if t >= 0 then
			if ours and oursT < 0 then return "clear", 0, "eased", phase end
			if ours then return nil, 0, "keep", phase end
			if o.owner == "fill" then return "clear", 0, "fill", phase end
			return nil, 0, "notLower", phase
		end
	end
	if ours and math.abs(t - oursT) < 1e-6 then return nil, t, "same", phase end
	local why = ours and "change" or (o.owner == "fill" and "fill") or (t < 0 and "hold") or "sparse"
	return "set", t, why, phase
end

--- "a1/a2/a3/a4" shares (%) of a {4} capacity row (LEVELS / ALLTOWN `lvl=`), "-" without.
function M.levelShares(row)
	if type(row) ~= "table" then return "-" end
	local sum = 0
	for l = 1, 4 do sum = sum + (tonumber(row[l]) or 0) end
	if sum <= 0 then return "0/0/0/0" end
	local p = {}
	for l = 1, 4 do p[l] = string.format("%.0f", 100 * (tonumber(row[l]) or 0) / sum) end
	return table.concat(p, "/")
end

--- ALLTOWN / LEVELS text of an engine levelInfo result (residential row): "a:<actual>,u:<unweighted>,w:<weighted>,c:<custom
--- weights or ->" or "-".
function M.levelText(info)
	if type(info) ~= "table" then return "-" end
	local c = "-"
	if type(info.custom) == "table" and type(info.custom[1]) == "table" then
		local r = info.custom[1]
		c = string.format("%g/%g/%g/%g", r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0)
	end
	return string.format("a:%s,u:%s,w:%s,c:%s", M.levelShares(info.actual and info.actual[1]),
		M.levelShares(info.unweighted and info.unweighted[1]), M.levelShares(info.weighted and info.weighted[1]), c)
end

--- Was a demand plan held (pressure)? asked = edges asked for, got = edges planned, report = ot_core report or nil.
function M.held(asked, got, report)
	if (got or 0) == 0 then return true end
	if (asked or 0) <= 0 then return false end
	if got >= M.PRESSURE_SHARE * asked then return false end
	local r = report or {}
	return (r.housedHeld or 0) + (r.wedgeHeld or 0) + (r.leadHeld or 0) + (r.meadowHeld or 0) > 0
		or (r.ownEmptyCap ~= nil and r.ownEmptyCap <= 0)
end

local function countNear(pts, x, y, r)
	local n, r2 = 0, r * r
	for _, p in ipairs(pts or {}) do
		local dx, dy = p[1] - x, p[2] - y
		if dx * dx + dy * dy <= r2 then n = n + 1 end
	end
	return n
end
M.countNear = countNear

--- The core radius (m) for a town whose buildings reach r90 (m).
function M.coreR(r90)
	return G.clamp(M.CORE_K * (r90 or 0), M.CORE_MIN, M.CORE_MAX)
end

--- Upward points: { {x, y, n = buildings near, class} } in the core (within coreR of centre c = {x, y}), beside the
--- midpoints of the graph's streets (main streets first: CLASS_W), where at least MIN_HOUSES buildings stand within
--- NEAR (most first), SPACING apart and from every point in `recent`; at most n (default POINTS). skip(x, y) -> true
--- leaves a point out (industry buffers). Returns the list (may be empty).
function M.points(g, pts, c, coreR, o)
	o = o or {}
	local n = o.n or M.POINTS
	local cand = {}
	if g == nil or c == nil then return {} end
	-- (a coarse cell index of the buildings: the score counts only buildings near a candidate)
	local cell = M.NEAR
	local idx = {}
	for _, p in ipairs(pts or {}) do
		if G.dist(c[1], c[2], p[1], p[2]) <= coreR + M.NEAR then
			local k = math.floor(p[1] / cell) * 65536 + math.floor(p[2] / cell)
			local l = idx[k]
			if l == nil then l = {}; idx[k] = l end
			l[#l + 1] = p
		end
	end
	local function near(x, y)
		local cnt = 0
		local i0, j0 = math.floor(x / cell), math.floor(y / cell)
		for i = i0 - 1, i0 + 1 do
			for j = j0 - 1, j0 + 1 do
				for _, p in ipairs(idx[i * 65536 + j] or {}) do
					local dx, dy = p[1] - x, p[2] - y
					if dx * dx + dy * dy <= M.NEAR * M.NEAR then cnt = cnt + 1 end
				end
			end
		end
		return cnt
	end
	for _, e in ipairs(g.edges or {}) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			if G.dist(c[1], c[2], mx, my) <= coreR then
				local l = G.dist(a.x, a.y, b.x, b.y)
				if l >= 20 then
					local nx, ny = -(b.y - a.y) / l, (b.x - a.x) / l
					-- the side away from the centre first: the town's denser inner side stays as it is
					local side = ((mx - c[1]) * nx + (my - c[2]) * ny) >= 0 and 1 or -1
					local px, py = mx + side * nx * M.OFFSET, my + side * ny * M.OFFSET
					local cnt = near(px, py)
					if cnt >= M.MIN_HOUSES and not (o.skip and o.skip(px, py)) then
						local w = M.CLASS_W[e.class or "small"] or 1
						cand[#cand + 1] = { G.round(px, 1), G.round(py, 1), n = cnt, class = e.class or "small", score = cnt * w,
							id = e.id }
					end
				end
			end
		end
	end
	table.sort(cand, function(p, q)
		if p.score ~= q.score then return p.score > q.score end
		return (p.id or 0) < (q.id or 0)
	end)
	local out = {}
	local function clear(x, y)
		for _, q in ipairs(out) do if G.dist(q[1], q[2], x, y) < M.SPACING then return false end end
		for _, q in ipairs(o.recent or {}) do if G.dist(q[1], q[2], x, y) < M.SPACING then return false end end
		return true
	end
	for _, p in ipairs(cand) do
		if #out >= n then break end
		if clear(p[1], p[2]) then out[#out + 1] = p end
	end
	return out
end

--- Remembers a dose's points in recent (newest last, at most RECENT). Returns recent.
function M.remember(recent, pts)
	recent = recent or {}
	for _, p in ipairs(pts or {}) do recent[#recent + 1] = { p[1], p[2] } end
	while #recent > M.RECENT do table.remove(recent, 1) end
	return recent
end

--- Person capacity per building, or nil.
function M.perBuilding(cap, buildings)
	if cap == nil or (buildings or 0) <= 0 then return nil end
	return cap / buildings
end

return M
