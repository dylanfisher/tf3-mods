-- Organic Towns: forest-aware towns (pure; phase F, 2026-10-13). User: "If the game doesn't already do this, working
-- around dense forest for some cities could be cool, e.g. smaller fingering cities around forests, vs big suburbs that
-- just bulldoze them."
--
-- The game has no such rule: its town developer (C++) and every street proposal auto-remove the trees in the way
-- (AssetGroupAutoRemove; docs/findings/towns.md "Reading trees near a town"). The mod reads the trees around a town
-- (ot_engine.forestReader: octree ASSET_GROUP -> MODEL_INSTANCE_LIST instances whose model has `metadata.tree`, sampled
-- with a stride under a read budget, sliced over driver ticks) into a coarse grid (CELL m) per town, read again after
-- RENEW_S or RENEW_BUILDS builds / RENEW_EDGES edges (R1), kept on the town's terrain stats (`stats.forest`). Pieces are
-- measured over a corridor to lot depth on both sides (R1, M.corridor). Per town and plan a mode:
--   hug    forest-hugging towns (seeded; more likely early, small / medium, organic styles, character towns): dense forest
--          is a soft barrier: plan pieces in it cost more (COST_K) and wait while the increment can fill elsewhere (HOLD_PEN,
--          relaxed a step at a time when it would starve: a boxed-in town still grows), pieces along the forest edge cost
--          a little less (EDGE_GAIN: streets follow the edge, the clearings take the fingers), dose points on the open side
--   clear  later / bigger / grid / metropolis towns build through as before (only logged)
--   none   too little forest around the town (share under MIN_SHARE): nothing to hug
--   deep   (deep forest round, 2026-10-14) 1-3 towns per map in dense forest (growth ring share >= DEEP_SHARE, seeded,
--          small / early / organic / character towns): a stronger hug (M.DEEP), winding streets (M.deepStyle), every
--          street near the trees locked, groves inside the town kept, 2 of 3 lanes, a quarter of the clearing budget
-- Hug / clear / none are not saved: the mode follows from the town's seed, year, size and style each plan (a town may
-- turn from hug to clear as it grows or the years pass, never back: the seeded draw is fixed, the chance only falls).
-- Deep is saved on the town's frame (`fd`, ot_saved): picked before the first build, it never flips.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

M.ON = true
M.R = 1500            -- m: the grid's half size around the town centre
M.CELL = 50           -- m: cell size
M.RENEW_S = 1200      -- real s: a town's grid is read again after this (reforestation, towns and players clearing)
-- tree density per cell -> cover 0..1 (trees per hectare). LIGHT and below: open land with a few trees; DENSE and
-- above: forest. Calibrated 2026-10-13 from the final test (session 2026-10-13_0856_sqot-dev, a heavily wooded hilly EU
-- map): the cells with trees read p50 24-28, p90 60 trees/ha (stride 2-3), so 25 / 90 left every town at forest share
-- 0.01-0.08 (all mode none). TF3's forests hold ~30-60 trees/ha in this read (offline, a wood of 40 trees/ha read at
-- stride 3 gives share 0.41 of a half-wooded map with 12 / 36; 0.04 with 25 / 90: test_forest). The reader samples
-- every `stride`-th tree and counts it `stride` times: one sampled tree in a 50 m cell reads stride x 4 trees/ha, so
-- LIGHT is at least LIGHT_STRIDE x that (a lone sampled tree is open land).
M.LIGHT_HA = 12
M.DENSE_HA = 36
M.LIGHT_STRIDE = 1.5
M.FOREST_COVER = 0.5  -- a cell with at least this cover counts as forest (shares, forestCut)
M.SHARE_R = 1000      -- m: `forest=` share within this radius of the centre
M.MIN_SHARE = 0.08    -- under this forest share around the town: mode none

-- the reader's budget (ot_engine.forestReader): instance reads per town about READ_MAX, spread evenly over the groups
-- (a stride per group: each read tree counts `stride` trees), a hard stop at 2 x READ_MAX (the FOREST line's `capped`)
M.READ_MAX = 24000
M.MAX_SAMPLES = 2000  -- samples per segment at most (hang guard)
M.SLICE_US = 3000     -- driver: Main Thread time per tick for the reader (PLAN 7: sliced)

-- hug: the planner (ot_select)
M.COST_K = 2.2        -- cost x (1 + COST_K x pen): a piece deep in forest costs ~3.2x (as if 3x farther out)
M.EDGE_GAIN = 0.2     -- cost x (1 - EDGE_GAIN x edge): open pieces with forest beside them come first (streets along the edge)
M.HOLD_PEN = 0.45     -- pieces with at least this pen (mean cover along the piece) wait while the increment fills elsewhere
M.HOLD_STEP = 0.2     -- ... coming back a step at a time (least wooded first) when the increment would starve
M.HOLD_FILL = 0.34    -- ... only while the increment has less than this share of its edges
M.CUT_FILL = 0.5      -- ... and once relaxed, the wooded pieces fill an increment up to this share at most (R1: of maxEdges
                      -- with clearing budget left, else of the chosen street length, CUT_MIN_M below)
M.SAMPLE_M = 20       -- m between pen samples along a piece
M.HOLD_LEN = 120      -- m: a piece with this much wooded length (cover-weighted) has pen 1 whatever its length
-- plot depth (round R1, 2026-10-13; run 2026-10-13_1945_sqot-dev, Billingham's suburbs around the forest): the houses'
-- lots reach about 36-40 m from the centreline (ot_style: 4 x 8 m), so a piece is measured over a corridor, the
-- centreline plus LOT_OFFSETS on each side (the lots), and BEYOND_OFFSETS for the forest just past the lots (the edge
-- premium: a street one lot depth off the trees, its lots open on both sides)
M.LOT_OFFSETS = { 20, 36 }
M.BEYOND_OFFSETS = { 52, 72 }
M.LOT_DEPTH = 36      -- m: a lot's depth (forestLot= hectares: side cover x length x this)
M.EDGE_OPEN = 0.3     -- the lots on both sides below this cover (and the centreline below 0.15): an edge street
-- the wooded length per increment (R1: the old cap counted maxEdges, so increments of 1-5 edges read forestCut=1.00): a
-- relaxed wooded piece may come while the wooded length stays within CUT_FILL of the increment's actual street length
-- (CUT_MIN_M at least: a boxed-in town still creeps on); with clearing budget left (below) up to CUT_FILL of maxEdges
M.CUT_MIN_M = 60
-- the clearing budget per town and decade of game time (forest under lots, hectares by size tier 1..4): towns cover
-- some trees on purpose; once spent, only the CUT_FILL share of what actually gets built may be wooded
M.BUDGET_HA = { 2, 3, 5, 8 }
M.BUDGET_YEARS = 10
-- re-read the grid after this many builds or new edges in the town (the town and the player clear trees), sliced like
-- the first read (the driver's stage "forest"); RENEW_S still applies
M.RENEW_BUILDS = 6
M.RENEW_EDGES = 80

-- mode odds: style base x era x size x character, against a seeded draw
M.STYLE_P = { EU_ORGANIC = 0.8, MED_HILL = 0.75, NORDIC = 0.75, JP_DENSE = 0.55, EU_EXTENSION = 0.62,
	NA_SUBURB = 0.12, NA_GRID = 0.1, MED_ENSANCHE = 0.08, SUPERBLOCK = 0.05 }
M.STYLE_P_DEFAULT = 0.5
-- (2026-10-15: EU_EXTENSION 0.45 -> 0.62, the user: "upgrade weaving chance"; seed `a` replay 1950: 6 hug + 1 deep, 1900: 12 + 1)
-- (2026-10-15 §59, seed `a` replays: start 1900 gave 9 hug / 6 clear / 1 deep, start 1950 3 hug / 13 clear; user:
-- "can we change early towns that weave through to be slightly higher weighted. and yes lets soften era curve")
-- full chance up to ERA[1], falling to ERA_LATE at ERA[2] and after (was 1920 / 1980 / 0.25)
M.ERA = { 1950, 1990 }
M.ERA_LATE = 0.5
-- early towns weave through a little more: x EARLY_F up to EARLY[1], back to 1 by EARLY[2] (P_MAX still caps)
M.EARLY = { 1910, 1930 }
M.EARLY_F = 1.12
M.TIER_F = { 1.0, 1.0, 0.6, 0.3 }   -- size tiers 1..4 (ot_inputs): small / medium towns hug, big suburbs clear
M.CHARACTER_F = 1.4
M.P_MAX = 0.95

-- deep forest towns (2026-10-14; user: "push some towns that are in particularly dense forested areas to lock more often
-- around trees, to really try to make them winding, wooded, secluded towns"; Verwood / Dewsbury liked: fingers between
-- forest patches, woods kept). Who: the forest share of the growth ring (DEEP_RING m from the centre: the town's own
-- cleared core left out) at least DEEP_SHARE, a seeded draw against DEEP_P x style x tier x era x character, at most
-- DEEP_MAX per map (saved frames + this session), never a metropolis or an offshoot (Works / district).
M.DEEP_ON = true
M.DEEP_SHARE = 0.40
-- (2026-10-14, run 2026-10-14_0613_sqot on seed `a`: no ring reached 0.45, the most wooded 0.37 / 0.32 / 0.28, because a
-- 50 m cell counts as forest only from cover 0.5 (~24 trees / ha) while the wooded cells there read 16-36 trees / ha. The
-- deep pick now counts its ring with its own lower cell threshold DEEP_COVER (~18 trees / ha) and DEEP_SHARE 0.40 (was
-- 0.45 at FOREST_COVER). A rank-based pick was not taken: each town is picked before its first build, when the other
-- towns' tree grids are mostly not read yet. FOREST_COVER itself (shares, holds, cuts, groves) is unchanged.)
M.DEEP_COVER = 0.25
-- (and the woods around it, not on one side: DEEP_SECTORS of the ring's 8 sectors at least DEEP_SECTOR_WOOD wooded; a
-- town at a forest edge is a hug town)
M.DEEP_SECTORS = 5
M.DEEP_SECTOR_WOOD = 0.25
M.DEEP_RING = { 150, 900 }
M.DEEP_P = 0.75
M.DEEP_STYLE = { EU_ORGANIC = 1, MED_HILL = 0.9, NORDIC = 0.9, EU_EXTENSION = 0.5 }   -- organic growers + Nordic only
M.DEEP_TIER = { 1, 0.85, 0.35, 0 }
M.DEEP_ERA = { 1960, 2010 }   -- full chance up to 1960, DEEP_ERA_LATE from 2010 (§59; was 1930 / 1990 / 0.35)
M.DEEP_ERA_LATE = 0.45
M.DEEP_CHARACTER = 1.3
M.DEEP_MAX = 3
-- deep towns' planner / lock / budget values (M.k reads them for mode deep, else the hug value of the same name)
M.DEEP = {
	COST_K = 3.2,        -- wooded pieces dearer than in a hug town (2.2)
	EDGE_GAIN = 0.35,    -- streets one lot off the forest edge come first (0.2)
	HOLD_PEN = 0.38,     -- one side wooded to lot depth (~0.4) already waits (hug 0.45: both sides)
	HOLD_STEP = 0.12,    -- relaxed in smaller steps (0.2)
	CUT_FILL = 0.25,     -- relaxed wooded pieces fill at most this share of an increment (0.5)
	CUT_MIN_M = 120,     -- ... at least (hug 60: about one wooded piece per increment, so a town deep in the woods creeps on)
	BUDGET_F = 0.25,     -- a quarter of the hug clearing budget per window
	SPEND_F = 1.5,       -- a held (wooded) piece's lots spend 1.5 x their hectares
	LOCK = 0.2,          -- lock: forest on the centreline or within lot depth on either side at least this cover
	NEAR = 0.1,          -- ... or in the band beyond the lots (52 / 72 m; the grid smoothing: trees within ~90 m)
	TIP_PROBE = 120,     -- m: a dead end probed this far on (hug 80)
	TIP_PEN = 0.3,
	-- groves: wooded patches of at most GROVE_CELLS forest cells (cover >= FOREST_COVER, 4-connected; 16 cells = 4 ha),
	-- not touching the grid's border, inside the town's frame: a piece whose centreline crosses one never comes (green
	-- islands the streets wrap around). The forest around the town is no grove: it is held / relaxed / budgeted as above,
	-- so a town in a clearing still grows out (a frame-wide ban boxed the offline driver town in: no plan at all).
	GROVE_CELLS = 16,
	FRAME_MIN = 150,     -- m: the frame is max(FRAME_MIN, FRAME_F x the houses' extent) around the centre (the driver
	FRAME_F = 1.25,      -- sets fo.frameR; a grove farther out may still be cleared within the budget as the town grows)
}

--- A planner / lock value for the forest info's mode: M.DEEP[key] for a deep town, else M[key].
function M.k(fo, key)
	if fo ~= nil and fo.mode == "deep" then
		local v = M.DEEP[key]
		if v ~= nil then return v end
	end
	return M[key]
end

---------------------------------------------------------------------------
-- the grid

--- New empty grid around (cx, cy): half size r (M.R), cell (M.CELL).
function M.newGrid(cx, cy, r, cell)
	r, cell = r or M.R, cell or M.CELL
	local n = math.max(1, math.ceil(2 * r / cell))
	return { cx = cx, cy = cy, r = r, cell = cell, n = n, x0 = cx - n * cell / 2, y0 = cy - n * cell / 2,
		trees = {}, samples = {}, total = 0 }
end

local function index(fg, x, y)
	local i = math.floor((x - fg.x0) / fg.cell)
	local j = math.floor((y - fg.y0) / fg.cell)
	if i < 0 or j < 0 or i >= fg.n or j >= fg.n then return nil end
	return i * fg.n + j + 1
end

--- One tree (weight w: the reader's stride) at (x, y); outside the grid ignored. n = the sampled trees it stands for
--- (default 1; fixtures pass more for a whole cell). Returns true when counted.
function M.addTree(fg, x, y, w, n)
	local k = index(fg, x, y)
	if k == nil then return false end
	w = w or 1
	fg.trees[k] = (fg.trees[k] or 0) + w
	if fg.samples then fg.samples[k] = (fg.samples[k] or 0) + (n or 1) end
	fg.total = fg.total + w
	return true
end

-- (R1 stride bias, 2026-10-13: the light threshold used to rise with the grid's largest stride, max(12, 1.5 x stride /
-- 0.25 ha): one big group read at stride 5 made light 30 / dense 60 for every cell, and visibly wooded towns (Redruth,
-- Southminster) read `none`. Now the thresholds stay LIGHT_HA / DENSE_HA on the stride-corrected density, and only a
-- cell with a single sampled tree reads open (a lone tree, whatever its weight).)
local function coverOf(fg, trees, samples)
	local ha = fg.cell * fg.cell / 10000
	local d = (trees or 0) / ha
	if samples ~= nil and samples <= 1 and (fg.stride or 1) > 1 then return 0 end
	local light = M.LIGHT_HA
	local dense = math.max(M.DENSE_HA, light * 2)
	if d <= light then return 0 end
	if d >= dense then return 1 end
	return (d - light) / (dense - light)
end

--- Finishes the grid: cover per cell (density -> 0..1), smoothed once (centre 4, the 4 neighbours 1 each: a lone dense
--- cell in open land reads ~0.5, a clearing of one cell in forest ~0.5), the forest share within SHARE_R and the
--- density percentiles of the cells with trees (calibration). Returns fg.
function M.finish(fg)
	local n = fg.n
	local raw = {}
	local smp = fg.samples or {}
	for k, v in pairs(fg.trees) do raw[k] = coverOf(fg, v, smp[k]) end
	local cover = {}
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local k = i * n + j + 1
			local sum, wsum = 4 * (raw[k] or 0), 4
			for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
				local a, b = i + d[1], j + d[2]
				if a >= 0 and b >= 0 and a < n and b < n then
					sum, wsum = sum + (raw[a * n + b + 1] or 0), wsum + 1
				end
			end
			local c = sum / wsum
			if c > 0.001 then cover[k] = c end
		end
	end
	fg.cover = cover
	-- share of forest cells within SHARE_R
	local tot, wood = 0, 0
	local r2 = M.SHARE_R * M.SHARE_R
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x, y = fg.x0 + (i + 0.5) * fg.cell, fg.y0 + (j + 0.5) * fg.cell
			local dx, dy = x - fg.cx, y - fg.cy
			if dx * dx + dy * dy <= r2 then
				tot = tot + 1
				if (cover[i * n + j + 1] or 0) >= M.FOREST_COVER then wood = wood + 1 end
			end
		end
	end
	fg.share = tot > 0 and wood / tot or 0
	local dens = {}
	local ha = fg.cell * fg.cell / 10000
	for _, v in pairs(fg.trees) do dens[#dens + 1] = v / ha end
	table.sort(dens)
	local function pct(p)
		if #dens == 0 then return 0 end
		return dens[math.max(1, math.min(#dens, math.floor(#dens * p + 0.5)))]
	end
	fg.p50, fg.p90, fg.treeCells = pct(0.5), pct(0.9), #dens
	local dense = 0
	for _, c in pairs(cover) do if c >= M.FOREST_COVER then dense = dense + 1 end end
	fg.denseCells = dense
	fg.done = true
	return fg
end

--- Cover 0..1 at (x, y) (0 outside the grid or before finish).
function M.cover(fg, x, y)
	if fg == nil or fg.cover == nil then return 0 end
	local k = index(fg, x, y)
	if k == nil then return 0 end
	return fg.cover[k] or 0
end

--- Cover at (x, y), or nil outside the grid (unknown: the site checks of Works / district towns, which reach beyond
--- the parent's grid, count only what was read).
function M.coverAt(fg, x, y)
	if fg == nil or fg.cover == nil then return nil end
	local k = index(fg, x, y)
	if k == nil then return nil end
	return fg.cover[k] or 0
end

--- A grid from a function forest(x, y) -> trees per hectare (offline fixtures): one tree weight per cell centre.
function M.fromFunction(cx, cy, fn, r, cell)
	local fg = M.newGrid(cx, cy, r, cell)
	local ha = fg.cell * fg.cell / 10000
	for i = 0, fg.n - 1 do
		for j = 0, fg.n - 1 do
			local x, y = fg.x0 + (i + 0.5) * fg.cell, fg.y0 + (j + 0.5) * fg.cell
			local d = fn(x, y) or 0
			if d > 0 then M.addTree(fg, x, y, d * ha, 1000) end
		end
	end
	return M.finish(fg)
end

---------------------------------------------------------------------------
-- per town: the mode

--- Era factor of the hug chance: EARLY_F up to EARLY[1], down to 1 at EARLY[2], 1 up to ERA[1], ERA_LATE from ERA[2]
--- (never rising with the year).
function M.eraF(year)
	local y = year or 1960
	local e = M.EARLY
	if e and y < e[2] then
		if y <= e[1] then return M.EARLY_F end
		return M.EARLY_F + (1 - M.EARLY_F) * (y - e[1]) / (e[2] - e[1])
	end
	if y <= M.ERA[1] then return 1 end
	if y >= M.ERA[2] then return M.ERA_LATE end
	return 1 + (M.ERA_LATE - 1) * (y - M.ERA[1]) / (M.ERA[2] - M.ERA[1])
end

--- The chance a town hugs the forest, and the factors: p, why.
function M.chance(style)
	local base = M.STYLE_P[style.id] or M.STYLE_P_DEFAULT
	local era = M.eraF(style.year)
	local tier = M.TIER_F[style.tier or 2] or 1
	local ch = (style.form and style.form.character) and M.CHARACTER_F or 1
	local p = math.min(M.P_MAX, base * era * tier * ch)
	return p, string.format("p=%.2f(s%.2f,e%.2f,t%.2f,c%.1f)", p, base, era, tier, ch)
end

--- Forest info for a style (the driver sets style.forest each plan): nil without a grid; else { grid, mode = "hug" |
--- "clear" | "none", share, why }. A metropolis always clears.
function M.forStyle(fg, style)
	if not M.ON or fg == nil or not fg.done or style == nil then return nil end
	local share = fg.share or 0
	if style.metro then return { grid = fg, mode = "clear", share = share, why = "metro" } end
	-- (a deep town, picked once and saved on its frame: deep whatever the share reads after its streets cleared trees)
	if style.deep then return { grid = fg, mode = "deep", share = share, why = style.deep.why or "deep", p = 1 } end
	if share < M.MIN_SHARE then return { grid = fg, mode = "none", share = share, why = "share" } end
	-- (2026-10-14, run 2026-10-14_0119_sqot: Winchcombe Heath, a district founded in a forest clearing, grew over the
	-- forest: a Works / district town hugs the forest from its first build, whatever the seed, era and size say)
	if style.offshoot then return { grid = fg, mode = "hug", share = share, why = "offshoot", p = 1 } end
	local p, why = M.chance(style)
	local u = rng.decide(style.drawV, style.seed or 1, "forestMode")
	local mode = u < p and "hug" or "clear"
	return { grid = fg, mode = mode, share = share, why = string.format("%s,u=%.2f", why, u), p = p }
end

--- True when the forest steers the planner (hug or deep).
function M.active(fo)
	return fo ~= nil and (fo.mode == "hug" or fo.mode == "deep") and fo.grid ~= nil
end

--- True for a deep forest town's forest info.
function M.isDeep(fo)
	return fo ~= nil and fo.mode == "deep" and fo.grid ~= nil
end

---------------------------------------------------------------------------
-- deep forest towns: who, and their plan geometry

--- Forest share (cells with cover >= cover, default FOREST_COVER) of the ring r0..r1 m around the grid's centre (0 without
--- a grid).
function M.ringShare(fg, r0, r1, cover)
	cover = cover or M.FOREST_COVER
	if fg == nil or fg.cover == nil then return 0 end
	local tot, wood = 0, 0
	local a2, b2 = r0 * r0, r1 * r1
	for i = 0, fg.n - 1 do
		for j = 0, fg.n - 1 do
			local x, y = fg.x0 + (i + 0.5) * fg.cell, fg.y0 + (j + 0.5) * fg.cell
			local d2 = (x - fg.cx) ^ 2 + (y - fg.cy) ^ 2
			if d2 >= a2 and d2 <= b2 then
				tot = tot + 1
				if (fg.cover[i * fg.n + j + 1] or 0) >= cover then wood = wood + 1 end
			end
		end
	end
	return tot > 0 and wood / tot or 0
end

--- Forest shares (cover >= FOREST_COVER) of n sectors of the ring r0..r1 m (generated names' `edge` tag, 2026-10-14):
--- { [1..n] = share } or nil without a grid.
function M.sectorShares(fg, r0, r1, n, cover)
	if fg == nil or fg.cover == nil then return nil end
	cover = cover or M.FOREST_COVER
	n = n or 8
	local tot, wood = {}, {}
	for k = 1, n do tot[k], wood[k] = 0, 0 end
	local a2, b2 = r0 * r0, r1 * r1
	for i = 0, fg.n - 1 do
		for j = 0, fg.n - 1 do
			local x, y = fg.x0 + (i + 0.5) * fg.cell, fg.y0 + (j + 0.5) * fg.cell
			local dx, dy = x - fg.cx, y - fg.cy
			local d2 = dx * dx + dy * dy
			if d2 >= a2 and d2 <= b2 then
				local a = G.atan2(dy, dx)
				if a < 0 then a = a + 2 * math.pi end
				local k = math.min(n, math.floor(a / (2 * math.pi) * n) + 1)
				tot[k] = tot[k] + 1
				if (fg.cover[i * fg.n + j + 1] or 0) >= cover then wood[k] = wood[k] + 1 end
			end
		end
	end
	local out = {}
	for k = 1, n do out[k] = tot[k] > 0 and wood[k] / tot[k] or 0 end
	return out
end

-- A town at a forest edge (generated names' `edge` tag, 2026-10-14; run 2026-10-14_0613_sqot: `edge` fired on all 16
-- towns from any forest share 0.08-0.35): the town itself mostly open (EDGE_IN share within EDGE_R[1]), woods on one side
-- (a sector of the ring EDGE_R[1]..EDGE_R[2] at least EDGE_WOOD) and open land on another (a sector at most EDGE_OPEN_S).
M.EDGE_R = { 250, 900 }
M.EDGE_IN = 0.25
M.EDGE_WOOD = 0.45
M.EDGE_OPEN_S = 0.12

--- Is the town at a forest edge (see EDGE_*)? Returns bool, the text "in/max/min" (or "-").
function M.isEdge(fg)
	local sec = M.sectorShares(fg, M.EDGE_R[1], M.EDGE_R[2], 8)
	if sec == nil then return false, "-" end
	local inner = M.ringShare(fg, 0, M.EDGE_R[1])
	local hi, lo = 0, 1
	for _, v in ipairs(sec) do hi, lo = math.max(hi, v), math.min(lo, v) end
	return inner <= M.EDGE_IN and hi >= M.EDGE_WOOD and lo <= M.EDGE_OPEN_S, string.format("%.2f/%.2f/%.2f", inner, hi, lo)
end

--- Era factor of the deep chance: 1 up to DEEP_ERA[1], DEEP_ERA_LATE from DEEP_ERA[2].
function M.deepEraF(year)
	local y = year or 1960
	local e = M.DEEP_ERA
	if y <= e[1] then return 1 end
	if y >= e[2] then return M.DEEP_ERA_LATE end
	return 1 + (M.DEEP_ERA_LATE - 1) * (y - e[1]) / (e[2] - e[1])
end

--- The deep draw's chance for a style (0 for a style or size tier that never goes deep): DEEP_P x style x tier x era x
--- character, at most P_MAX.
function M.deepChance(style)
	local sw = M.DEEP_STYLE[style.id] or 0
	local tf = M.DEEP_TIER[style.tier or 2] or 0
	local ch = (style.form and style.form.character) and M.DEEP_CHARACTER or 1
	return math.min(M.P_MAX, M.DEEP_P * sw * tf * M.deepEraF(style.year) * ch)
end

--- The deep forest reading of a tree grid without the style (2026-10-15, NEXT_PHASE_BRIEF 61, the naming phase: it runs
--- before the town's style is resolved): the ring share and the wooded sectors deepPick asks for. Returns ok, ring
--- share, wooded sectors.
function M.deepSite(fg)
	if not (M.ON and M.DEEP_ON) or fg == nil or not fg.done then return false, 0, 0 end
	local ring = M.ringShare(fg, M.DEEP_RING[1], M.DEEP_RING[2], M.DEEP_COVER)
	if ring < M.DEEP_SHARE then return false, ring, 0 end
	local wooded = 0
	for _, v in ipairs(M.sectorShares(fg, M.DEEP_RING[1], M.DEEP_RING[2], 8, M.DEEP_COVER) or {}) do
		if v >= M.DEEP_SECTOR_WOOD then wooded = wooded + 1 end
	end
	return wooded >= M.DEEP_SECTORS, ring, wooded
end

--- Is this a deep forest town? fg = the town's tree grid, style = its resolved style (id, tier, year, seed, form, metro,
--- offshoot), o = { count = deep towns on the map so far, force = dev }. Returns deep (bool), why ("ring=0.52,p=..,u=.."
--- or the reason it is not: noGrid / metro / offshoot / style / tier / share / draw / quota).
function M.deepPick(fg, style, o)
	o = o or {}
	if not (M.ON and M.DEEP_ON) then return false, "off" end
	if fg == nil or not fg.done then return false, "noGrid" end
	if o.force then return true, "force" end
	if style == nil then return false, "noStyle" end
	if style.metro then return false, "metro" end
	if style.offshoot then return false, "offshoot" end
	local sw = M.DEEP_STYLE[style.id] or 0
	if sw <= 0 then return false, "style:" .. tostring(style.id) end
	local tf = M.DEEP_TIER[style.tier or 2] or 0
	if tf <= 0 then return false, "tier" end
	local ring = M.ringShare(fg, M.DEEP_RING[1], M.DEEP_RING[2], M.DEEP_COVER)
	if ring < M.DEEP_SHARE then return false, string.format("share:ring=%.2f", ring) end
	local wooded = 0
	for _, v in ipairs(M.sectorShares(fg, M.DEEP_RING[1], M.DEEP_RING[2], 8, M.DEEP_COVER) or {}) do
		if v >= M.DEEP_SECTOR_WOOD then wooded = wooded + 1 end
	end
	if wooded < M.DEEP_SECTORS then return false, string.format("share:ring=%.2f,sectors=%d", ring, wooded) end
	local p = M.deepChance(style)
	local u = rng.decide(style.drawV, style.seed or 1, "forestDeep")
	local why = string.format("ring=%.2f,p=%.2f,u=%.2f", ring, p, u)
	-- (NEXT_PHASE_BRIEF 61: a town the naming phase named for its deep forest, o.named, skips the draw: its name carries
	-- the kind; o.named == false: the naming phase ran and named it otherwise, never deep)
	if o.named == false then return false, "names:" .. why end
	if o.named == true then why = why .. ",named" elseif u >= p then return false, "draw:" .. why end
	if (o.count or 0) >= M.DEEP_MAX then return false, "quota:" .. why end
	return true, why
end

--- The grid's grove cells (DEEP.GROVE_CELLS, cached on the grid): { [cell index] = true }.
function M.groveCells(fg)
	if fg == nil or fg.cover == nil then return {} end
	if fg._groves then return fg._groves end
	local n, cover, lim = fg.n, fg.cover, M.FOREST_COVER
	local seen, out = {}, {}
	for k, c in pairs(cover) do
		if c >= lim and not seen[k] then
			-- (flood fill, bounded by the cell count: every cell is visited once)
			local comp, stack, border = {}, { k }, false
			seen[k] = true
			while #stack > 0 do
				local q = table.remove(stack)
				comp[#comp + 1] = q
				local i, j = math.floor((q - 1) / n), (q - 1) % n
				if i == 0 or j == 0 or i == n - 1 or j == n - 1 then border = true end
				for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
					local a, b = i + d[1], j + d[2]
					if a >= 0 and b >= 0 and a < n and b < n then
						local r = a * n + b + 1
						if not seen[r] and (cover[r] or 0) >= lim then
							seen[r] = true
							stack[#stack + 1] = r
						end
					end
				end
			end
			if not border and #comp <= M.DEEP.GROVE_CELLS then
				for _, q in ipairs(comp) do out[q] = true end
			end
		end
	end
	fg._groves = out
	return out
end

-- wood sizes (§71, 2026-10-16; run 2026-10-16_0405_sqot: Shaw sits in a patchwork of small woods, and the steer lock's
-- face rules (ot_lockpol.facing, ot_glock valves / tips) locked nearly every rim street of it against copses of a few
-- trees: game share 0.07). A wood is a 4-connected patch of dense cells (cover >= FOREST_COVER); one smaller than
-- WOOD_MIN_HA does not make a street "face forest". A patch touching the grid's border counts as big (its size beyond
-- is unknown). The §63 skeleton clearance and the hug costs read the plain cover, as before.
M.WOOD_MIN_HA = 1.75      -- ha: a wood at least this big counts for the lock policy's face rules (50 m cells: 7 cells)

--- The cells a wood needs to count (M.WOOD_MIN_HA over the grid's cell area).
function M.woodMinCells(fg)
	local cell = (fg and fg.cell) or M.CELL
	return math.max(1, math.ceil(M.WOOD_MIN_HA * 10000 / (cell * cell) - 1e-9))
end

--- Per dense cell the size (cells) of its wood, border patches math.huge (cached on the grid per cover table):
--- { [cell index] = n }. Every cell is visited once (the flood fill's stack holds each cell at most once).
function M.woodSizes(fg)
	if fg == nil or fg.cover == nil then return {} end
	if fg._woodSz and fg._woodCov == fg.cover then return fg._woodSz end
	local n, cover, lim = fg.n, fg.cover, M.FOREST_COVER
	local seen, out = {}, {}
	local cap = n * n + 1
	for k, c in pairs(cover) do
		if c >= lim and not seen[k] then
			local comp, stack, border = {}, { k }, false
			seen[k] = true
			local guard = 0
			while #stack > 0 and guard <= cap do
				guard = guard + 1
				local q = table.remove(stack)
				comp[#comp + 1] = q
				local i, j = math.floor((q - 1) / n), (q - 1) % n
				if i == 0 or j == 0 or i == n - 1 or j == n - 1 then border = true end
				for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
					local a, b = i + d[1], j + d[2]
					if a >= 0 and b >= 0 and a < n and b < n then
						local r = a * n + b + 1
						if not seen[r] and (cover[r] or 0) >= lim then
							seen[r] = true
							stack[#stack + 1] = r
						end
					end
				end
			end
			local size = border and math.huge or #comp
			for _, q in ipairs(comp) do out[q] = size end
		end
	end
	fg._woodSz, fg._woodCov = out, fg.cover
	return out
end

--- Is (x, y) in a wood big enough to count (dense, its patch at least M.woodMinCells)?
function M.bigWoodAt(fg, x, y)
	if fg == nil or fg.cover == nil then return false end
	local k = index(fg, x, y)
	if k == nil or (fg.cover[k] or 0) < M.FOREST_COVER then return false end
	return (M.woodSizes(fg)[k] or 0) >= M.woodMinCells(fg)
end

--- Does a big wood (M.bigWoodAt) lie within r m of (x, y)? (The cells whose centres lie within r + half a cell.)
function M.bigWoodNear(fg, x, y, r)
	if fg == nil or fg.cover == nil or x ~= x or y ~= y then return false end
	local cell = fg.cell
	local m = math.min(20, math.ceil((r or 0) / cell))   -- (cap: at most 41 x 41 cells)
	local i0, j0 = math.floor((x - fg.x0) / cell), math.floor((y - fg.y0) / cell)
	local sz, need, lim = M.woodSizes(fg), M.woodMinCells(fg), (r or 0) + cell * 0.71
	for di = -m, m do
		for dj = -m, m do
			local i, j = i0 + di, j0 + dj
			if i >= 0 and j >= 0 and i < fg.n and j < fg.n then
				local cx, cy = fg.x0 + (i + 0.5) * cell, fg.y0 + (j + 0.5) * cell
				if (cx - x) * (cx - x) + (cy - y) * (cy - y) <= lim * lim then
					local q = i * fg.n + j + 1
					if (sz[q] or 0) >= need then return true end
				end
			end
		end
	end
	return false
end

--- Does a big wood lie within r m of the street p0 -> p1, or of its tip probes (tip0 / tip1: probe len m on from that
--- end)? Sampled every SAMPLE_M (MAX_SAMPLES at most).
function M.bigWoodBy(fg, p0, p1, r, tip0, tip1, len)
	if fg == nil or p0 == nil or p1 == nil then return false end
	local L = G.dist(p0[1], p0[2], p1[1], p1[2])
	local ux, uy = 0, 0
	if L > 1e-6 then ux, uy = (p1[1] - p0[1]) / L, (p1[2] - p0[2]) / L end
	local a, b = (tip0 and len or 0), L + (tip1 and len or 0)
	local tot = a + b
	if not (tot == tot) or tot == math.huge then return false end
	local n = math.max(1, math.min(M.MAX_SAMPLES, math.ceil(tot / M.SAMPLE_M)))
	for k = 0, n do
		local s = -a + tot * k / n
		if M.bigWoodNear(fg, p0[1] + ux * s, p0[2] + uy * s, r) then return true end
	end
	return false
end

--- Does polyline pts cross a grove (M.groveCells) within R m of (cx, cy)? Sampled every SAMPLE_M.
function M.inGrove(fo, pts, cx, cy, R)
	local fg = fo and fo.grid
	if fg == nil or pts == nil or #pts < 2 then return false end
	local gv = M.groveCells(fg)
	if next(gv) == nil then return false end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local n = math.max(1, math.ceil(l / M.SAMPLE_M))
		if not (n <= M.MAX_SAMPLES) then n = 1 end   -- (hang guard)
		for k = 0, n do
			local f = k / n
			local x, y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			local q = index(fg, x, y)
			if q and gv[q] and G.dist(x, y, cx, cy) <= R then return true end
		end
	end
	return false
end

M.WIGGLE = { amp = 7, wave = 90 }   -- deep towns' long plan lanes / secondary radials: a gentle sine (ot_grow_organic)

--- A deep town's plan geometry (ot_style.resolve, before the shape / form / greens / motifs): curvier, shorter straight
--- runs, smaller blocks, organic all the way out (no gridded outer zone). Only the existing knobs, each within the
--- grower's own radius checks (spokes steer at most STEP / spokeRadius, lines smoothed to LINE_RADIUS 80 m, the planner's
--- 70 m edge check; ot_plan.MIN_RADIUS). Returns p.
function M.deepStyle(p)
	if p == nil then return p end
	local MB = 40   -- (ot_style.MIN_BLOCK: 2 x 2 lots of 8 m + a street)
	p.curve = math.max(p.curve or 0, 35)
	p.jitter = math.max(p.jitter or 0, 20)
	p.contour = math.max(p.contour or 0, 0.8)
	if p.block then
		local b = p.block
		p.block = { len = math.max(MB, b.len * 0.8), depth = math.max(math.min(b.depth, MB), b.depth * 0.85),
			sd = math.max(b.sd or 0, 0.35) }
	end
	if p.grower == "organic" then
		p.gridness = math.min(p.gridness or 0.5, 0.15)
		p.curveWave = 110       -- m: the spokes' wobble wavelength (200)
		p.spokeRadius = 80      -- m: spokes may turn a little tighter (90; LINE_RADIUS 80, the planner's check 70)
		p.wiggle = { amp = M.WIGGLE.amp, wave = M.WIGGLE.wave }
		if p.radial then
			p.radial = { spokes = p.radial.spokes, ringEvery = math.max(150, (p.radial.ringEvery or 250) * 0.8) }
		end
	elseif p.cluster then
		-- (Nordic: more cells left green, loops bowed more)
		p.cluster = { depth = p.cluster.depth, green = math.max(p.cluster.green or 0, 0.45),
			bow = math.max(p.cluster.bow or 0, 0.18) }
	end
	p.outer, p._outerCache = nil, nil
	p.deepGeo = true
	return p
end

--- `deep=` text: "<maxStraight m>/<bends>/<edges>" from the increment's edges (ot_plan edges with p0 / p1 / t0 / t1):
--- the longest straight stretch of one edge (its Hermite curve, heading within 4 deg) or of a chain of straight edges
--- (straight, from ot_check.straightRuns), and the edges that bend >= BEND_DEG. Returns maxStraight, bends, n.
M.BEND_DEG = 8
function M.windStats(inc, chainMax)
	local best, bends, n = chainMax or 0, 0, 0
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.p0 and e.p1 and e.t0 and e.t1 and not e.forestLane then
			n = n + 1
			local l0 = G.len(e.t0[1], e.t0[2])
			local l1 = G.len(e.t1[1], e.t1[2])
			if l0 > 1e-6 and l1 > 1e-6 then
				local d0, d1 = { e.t0[1] / l0, e.t0[2] / l0 }, { e.t1[1] / l1, e.t1[2] / l1 }
				local turn = math.abs(G.angleDiff(G.atan2(d0[2], d0[1]), G.atan2(d1[2], d1[1])))
				if turn >= math.rad(M.BEND_DEG) then bends = bends + 1 end
				local pts = G.hermitePts(e.p0[1], e.p0[2], e.p1[1], e.p1[2], d0, d1, 16)
				local run = G.maxStraightRun(pts, 4)
				if run > best then best = run end
			end
		end
	end
	return best, bends, n
end

---------------------------------------------------------------------------
-- the planner's measures

--- Wooded share of a polyline (samples every SAMPLE_M): the mean cover, or the cover-weighted wooded length / HOLD_LEN
--- when that is more (long pieces); 0 open .. 1 deep forest.
function M.pen(fo, pts)
	local fg = fo and fo.grid
	if fg == nil or pts == nil or #pts < 2 then return 0 end
	local tot, sum = 0, 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local n = math.max(1, math.ceil(l / M.SAMPLE_M))
		if not (n <= M.MAX_SAMPLES) or l ~= l then n, l = 1, 0 end   -- (hang guard: an endless / NaN segment counts as open)
		for k = 1, n do
			local f = (k - 0.5) / n
			sum = sum + M.cover(fg, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f) * l / n
		end
		tot = tot + l
	end
	if tot <= 0 then return M.cover(fg, pts[1][1], pts[1][2]) end
	-- (a long piece, e.g. a Nordic cluster loop, with a long wooded stretch counts as wooded even when its mean is low:
	-- the wooded length over HOLD_LEN counts as full cover)
	return math.min(1, math.max(sum / tot, sum / M.HOLD_LEN))
end

--- Forest beside an open point: the most cover of the 8 cells around it (one cell out) when the point itself is
--- open (cover < 0.3), else 0. (Phase F; the planner now uses the corridor's `beyond` instead, R1.)
function M.edge(fo, x, y)
	local fg = fo and fo.grid
	if fg == nil then return 0 end
	if M.cover(fg, x, y) >= 0.3 then return 0 end
	local best, c = 0, fg.cell
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }) do
		local v = M.cover(fg, x + d[1] * c, y + d[2] * c)
		if v > best then best = v end
	end
	return best
end

--- The corridor of a polyline (R1, plot depth): samples every SAMPLE_M along the centreline and at LOT_OFFSETS /
--- BEYOND_OFFSETS on each side (left = the polyline's left normal). Returns { c = centreline pen (M.pen), l, r = mean
--- lot cover per side, bl, br = mean cover just beyond the lots per side, len = length (m), lotHa = forest under the
--- lots (side cover x length x LOT_DEPTH, hectares), woodM = the wooded length (m; the lots' mean cover x length) }.
function M.corridor(fo, pts)
	local fg = fo and fo.grid
	local out = { c = 0, l = 0, r = 0, bl = 0, br = 0, len = 0, lotHa = 0, woodM = 0 }
	if fg == nil or pts == nil or #pts < 2 then return out end
	out.c = M.pen(fo, pts)
	local nl, nb = #M.LOT_OFFSETS, #M.BEYOND_OFFSETS
	local sl, sr, sbl, sbr, tot = 0, 0, 0, 0, 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local n = math.max(1, math.ceil(l / M.SAMPLE_M))
		if not (n <= M.MAX_SAMPLES) or not (l > 1e-6) or l == math.huge then n, l = 0, 0 end   -- (hang guard: an endless / NaN segment counts as open)
		local ux, uy = 0, 0
		if l > 0 then ux, uy = (b[1] - a[1]) / l, (b[2] - a[2]) / l end
		local nx, ny = -uy, ux
		for k = 1, n do
			local f = (k - 0.5) / n
			local x, y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			local w = l / n
			local cl, cr, bl, br = 0, 0, 0, 0
			for _, o in ipairs(M.LOT_OFFSETS) do
				cl = cl + M.cover(fg, x + nx * o, y + ny * o)
				cr = cr + M.cover(fg, x - nx * o, y - ny * o)
			end
			for _, o in ipairs(M.BEYOND_OFFSETS) do
				bl = bl + M.cover(fg, x + nx * o, y + ny * o)
				br = br + M.cover(fg, x - nx * o, y - ny * o)
			end
			sl, sr = sl + w * cl / nl, sr + w * cr / nl
			sbl, sbr = sbl + w * bl / nb, sbr + w * br / nb
		end
		tot = tot + l
	end
	if tot <= 0 then return out end
	out.len = tot
	out.l, out.r, out.bl, out.br = sl / tot, sr / tot, sbl / tot, sbr / tot
	out.lotHa = (sl + sr) * M.LOT_DEPTH / 10000
	out.woodM = (sl + sr) / 2
	return out
end

--- The hold / cost pen of a corridor: the centreline pen or the mean over the five lines (centre, both sides' lots),
--- whichever is more. One side wooded to lot depth reads ~0.4 (dearer, not held), both sides ~0.8 (held).
function M.corridorPen(co)
	if co == nil then return 0 end
	local n = #M.LOT_OFFSETS
	local mean = (co.c + n * co.l + n * co.r) / (1 + 2 * n)
	return math.max(co.c, mean)
end

--- An edge street (R1): its centreline and lots open on both sides (below EDGE_OPEN: the grid's smoothing reads ~0.2 one
--- cell off the trees), with forest just beyond the lots on one side: the edge premium's weight 0..1 (the beyond
--- cover), else 0.
function M.edgeOf(co)
	if co == nil or co.c >= M.EDGE_OPEN or co.l >= M.EDGE_OPEN or co.r >= M.EDGE_OPEN then return 0 end
	return math.max(co.bl, co.br)
end

--- Cost factor of a piece for a hug town (1 otherwise), its pen and its corridor (co: pass a cached one).
function M.costFactor(fo, pts, co)
	if not M.active(fo) then return 1, 0 end
	co = co or M.corridor(fo, pts)
	local pen = M.corridorPen(co)
	local f = 1 + M.k(fo, "COST_K") * pen
	f = f * (1 - M.k(fo, "EDGE_GAIN") * M.edgeOf(co))
	return f, pen, co
end

-- clear-mode towns (§63, 2026-10-15; run 2026-10-15_0539_sqot: "the towns take over forest too quickly"): they still build
-- through the woods, but a wooded piece costs a little more, scaled by the town's own hug odds (fo.p: style x era x
-- size x character, M.chance), so an early small organic town that drew "clear" leans to its open land while a late
-- big suburb hardly notices. No hold, no edge premium, no budget: a light touch. A metropolis (fo.p nil) none.
M.CLEAR_COST_K = 0.6

--- Cost factor of a piece for a clear-mode town (1 otherwise): 1 + CLEAR_COST_K x p x the corridor pen.
function M.clearFactor(fo, pts, co)
	if fo == nil or fo.mode ~= "clear" or fo.grid == nil or not ((fo.p or 0) > 0) or M.CLEAR_COST_K <= 0 then return 1 end
	co = co or M.corridor(fo, pts)
	return 1 + M.CLEAR_COST_K * math.min(1, fo.p) * M.corridorPen(co)
end

--- Clearing budget hectares a piece / edge with corridor co spends (R1 lotHa; a deep town's wooded (held) pieces
--- DEEP.SPEND_F x).
function M.lotSpend(fo, co)
	if co == nil then return 0 end
	local ha = co.lotHa or 0
	if M.isDeep(fo) and M.corridorPen(co) >= M.DEEP.HOLD_PEN then ha = ha * M.DEEP.SPEND_F end
	return ha
end

--- Share of the segments' length ({x0, y0, x1, y1}) in forest (cover >= FOREST_COVER): PLAN `forestCut=`. nil without
--- a grid.
function M.cutShare(fo, segs)
	local fg = fo and fo.grid
	if fg == nil then return nil end
	local tot, inside = 0, 0
	for _, s in ipairs(segs or {}) do
		local l = G.dist(s[1], s[2], s[3], s[4])
		if l > 0 then
			local n = math.max(1, math.ceil(l / M.SAMPLE_M))
			if not (n <= M.MAX_SAMPLES) then n = 0 end   -- (hang guard)
			for k = 1, n do
				local f = (k - 0.5) / n
				tot = tot + l / n
				if M.cover(fg, s[1] + (s[3] - s[1]) * f, s[2] + (s[4] - s[2]) * f) >= M.FOREST_COVER then
					inside = inside + l / n
				end
			end
		end
	end
	if tot <= 0 then return nil end
	return inside / tot
end

--- A dose point for a hug town: (px, py) when its side is open, else the other side of the street (ox, oy) when that
--- is more open (the houses go on the open side, facing the trees across the street). R1: each side is read to lot
--- depth (the point at FILL_OFFSET and the same ray out to the deepest LOT_OFFSET from the street's middle, the
--- midpoint of p and o).
function M.sideCover(fg, px, py, ox, oy)
	local mx, my = (px + ox) / 2, (py + oy) / 2
	local d = G.dist(mx, my, px, py)
	local c = M.cover(fg, px, py)
	if d > 1e-6 then
		local deep = M.LOT_OFFSETS[#M.LOT_OFFSETS] / d
		c = math.max(c, M.cover(fg, mx + (px - mx) * deep, my + (py - my) * deep))
	end
	return c
end

function M.openSide(fo, px, py, ox, oy)
	if not M.active(fo) then return px, py end
	local a, b = M.sideCover(fo.grid, px, py, ox, oy), M.sideCover(fo.grid, ox, oy, px, py)
	if a >= M.EDGE_OPEN and b < a then return ox, oy end
	return px, py
end

---------------------------------------------------------------------------
-- forest-facing streets (round after the names run, 2026-10-13: Brentwood, run 2026-10-13_2113_sqot-dev, grew deep
-- into the forested mountain foot. The mod built 105 of its 446 edges; the game's own development built the rest and
-- has no forest rule (docs/findings/towns.md "Reading trees"): it hung its streets off the mod's and its own dead ends
-- into the trees. A hug town now locks its new streets that face the forest (roadDevelopmentLocked: the town still
-- builds houses on them but hangs no side streets off them, docs/findings/towns.md Showcase v5), so the game grows on
-- the open side; the mod's own pieces still cover some trees within the clearing budget)

M.FACE_LOCK = 0.5     -- a side's lots or the band beyond at least this cover: the street faces the forest
M.TIP_PROBE = 80      -- m: a dead end's street probed this far on: into the forest (pen >= FACE_LOCK) locks it

--- Does the street p0 -> p1 face the forest? tip0 / tip1: that end is a dead end of the increment (probe on from it).
--- Returns true, "side" | "tip" or false.
--- Deep towns (2026-10-14) lock much more: any forest on the centreline or within lot depth on either side
--- (DEEP.LOCK) -> "side", forest in the band just beyond the lots (DEEP.NEAR, 52-72 m) -> "near", a dead end probed
--- DEEP.TIP_PROBE m on into forest (DEEP.TIP_PEN) -> "tip".
function M.facesForest(fo, p0, p1, tip0, tip1)
	if not M.active(fo) or p0 == nil or p1 == nil then return false end
	local co = M.corridor(fo, { p0, p1 })
	local deep = M.isDeep(fo)
	if math.max(co.l, co.r, co.bl, co.br) >= M.FACE_LOCK then return true, "side" end
	if deep and math.max(co.c, co.l, co.r) >= M.DEEP.LOCK then return true, "side" end
	if deep and math.max(co.bl, co.br) >= M.DEEP.NEAR then return true, "near" end
	local L = G.dist(p0[1], p0[2], p1[1], p1[2])
	if L > 1e-6 then
		local probe = deep and M.DEEP.TIP_PROBE or M.TIP_PROBE
		local lim = deep and M.DEEP.TIP_PEN or M.FACE_LOCK
		local ux, uy = (p1[1] - p0[1]) / L, (p1[2] - p0[2]) / L
		if tip1 and M.pen(fo, { p1, { p1[1] + ux * probe, p1[2] + uy * probe } }) >= lim then return true, "tip" end
		if tip0 and M.pen(fo, { p0, { p0[1] - ux * probe, p0[2] - uy * probe } }) >= lim then return true, "tip" end
	end
	return false
end

---------------------------------------------------------------------------
-- the clearing budget (R1): forest under lots per town and decade, in hectares (session memory on the driver's town
-- state; nothing saved)

--- The budget table for a town state at game year `year`, size tier and buildings: { decade, total, used, b0, win }.
--- A new window (used back to 0) opens with a new decade of game time or once the town has grown BUDGET_GROW x since
--- the window opened (round after the names run: Brentwood grew 116 -> 1917 buildings in the dev sim's 40 years
--- while the game calendar hardly moved, so its 2 ha went in the head start and never came back; a fast grower in
--- normal play is the same within a decade); the total follows the town's current tier.
M.BUDGET_GROW = 1.5
function M.budgetFor(ts, year, tier, buildings, factor)
	if ts == nil then return nil end
	local dec = math.floor((year or 1900) / M.BUDGET_YEARS)
	-- (factor: a deep town's DEEP.BUDGET_F)
	local total = (M.BUDGET_HA[tier or 2] or M.BUDGET_HA[2]) * (factor or 1)
	local b = ts.forestBudget
	local nb = tonumber(buildings)
	local why = nil
	if b == nil then why = "first"
	elseif b.decade ~= dec then why = "decade"
	elseif nb and b.b0 and b.b0 > 0 and nb >= b.b0 * M.BUDGET_GROW then why = "growth" end
	if why then
		b = { decade = dec, total = total, used = 0, b0 = nb, win = why, wins = ((b and b.wins) or 0) + 1 }
		ts.forestBudget = b
	elseif total > b.total then
		b.total = total
	end
	return b
end

--- `forestBudget=` text: "<left>/<total>" hectares, "-" without one.
function M.budgetText(b, pending)
	if b == nil then return "-" end
	return string.format("%.1f/%.1f", math.max(0, b.total - b.used - (pending or 0)), b.total)
end

--- `forest=` text for STYLE / SHAPE / ALLTOWN: "<share>:<mode>" (e.g. "0.34:hug"), "-" without a grid.
function M.text(fo)
	if fo == nil then return "-" end
	return string.format("%.2f:%s", fo.share or 0, fo.mode or "?")
end

return M
