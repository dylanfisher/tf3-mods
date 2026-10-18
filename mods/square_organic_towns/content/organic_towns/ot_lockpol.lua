-- Organic Towns: the steering lock policy (pure; §69, 2026-10-15; PLAN.md 6.2 "Steering lock policy").
--
-- User (2026-10-15, after run `2026-10-15_1936_sqot-glprobe`): "i think we should not lock all roads, just many of
-- them, especially early when trying to stear direction. but building a locked branch out into an open space, then
-- unlocking at the end seems good."
--
-- §65 locked every street the mod builds, §67 every houseless (then every) game street the town grew, with a few
-- valves: the game-built share of the non-core edges fell 0.58 -> 0.22 and the woods were spared (forestLot 46.9 ->
-- 34.7 ha), but most of a town became our more regular pattern (less organic texture), and long locked branches with
-- no houses stood out (spikes). This module decides, per street, whether it is locked ("steer" towns, ot_driver
-- LOCK_DEFAULT; frame `lm = 2`):
--   * the town's built outline (M.outline: per heading sector, a quantile of the housed streets' distances from the
--     centre, smoothed) separates "inside" (the established town) from "the rim" and "out" (beyond the houses);
--   * a new mod street is locked when it faces something the town must not grow into (M.facing: dense forest within
--     the skeleton's clearance, water, a neighbour's gap, and, at or beyond the outline, against the §62 land lean),
--     when it lies in a §63 skeleton arm while the town is young (the arms steer the town's direction), or when it
--     lies outside the inner zone, whose radius grows with the maturity (M.innerK: 0 young, so early everything is
--     locked, up to INNER_K[2] of the outline when grown). Inside the inner zone it stays unlocked: the game's own
--     fill does the blocks (texture);
--   * a game street (M.gameLock, §67 GLOCK in steer towns) is locked only at or beyond GK_RIM_K x the outline, and
--     only when it faces something unwanted (as above) or, while the town is young, lies beyond the outline at all;
--     inside, and on the rim toward open land in a grown town, the game keeps building;
--   * a branch into open land is built locked with its far tip unlocked (ot_glock.pickTips): the growth point the
--     game develops from (the tip valve); a tip never sits within CLEAR_M of dense forest.
-- The share locked falls with the maturity (M.innerK, the young rules) while the steering where it matters stays.
-- Every loop is over a capped list (SCAN_MAX). Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local SK = ug_require "square_organic_towns::/organic_towns/ot_skeleton.lua"
local LAND = ug_require "square_organic_towns::/organic_towns/ot_land.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"

local M = {}

local pi, cos, sin, atan2, abs, floor = math.pi, math.cos, math.sin, math.atan2 or math.atan, math.abs, math.floor

M.ON = true               -- false: steer towns lock every mod street and every game street (as "mod" + §67)
-- the policy's constants (calibration: TESTING.md "Combined test iteration" step 18)
M.MAT = { 0.15, 0.8 }     -- maturity (ot_assess.maturity) over which the inner zone opens ...
M.INNER_K = { 0, 0.85 }   -- ... its radius from 0 (young: every mod street locked) to this x the outline (grown)
M.ARM_FREE_MAT = 0.6      -- §63 skeleton arms stay locked until this maturity (then only outside the inner zone)
M.YOUNG_MAT = 0.35        -- below this maturity every game street beyond the outline is locked (the early steering)
M.GK_RIM_K = 0.85         -- game streets at least this x the outline out are lock candidates (inside: never)
M.LEAN_BAD = -0.15        -- §62 lean at the heading below this: "against the land" (at or beyond the outline only)
M.AHEAD_M = 120           -- m: the probe ahead of a street's outer end (forest, water, a neighbour's gap)
M.CORRIDOR = true         -- §70: a narrow clearing ahead (woods on both sides, ot_skeleton.corridorAt) faces forest
-- §71 (2026-10-16; run 2026-10-16_0405_sqot: Shaw, in a patchwork of small woods, game share 0.07 at lockMat 0.80; Dalemere
-- 0.12, Little Dalemere 0.15): the face rules count a wood only when it is big enough to matter (ot_forest.bigWoodAt: a
-- patch of dense cells of at least ot_forest.WOOD_MIN_HA); a copse no longer makes a street face forest. The §63
-- skeleton clearance and the hug costs are unchanged (they read the plain cover). Faces skipped: `smallWood=`.
M.SMALL_WOOD = true
M.SMALL_WOOD_R = 60       -- m: the hug's forest-facing (ot_forest.facesForest) needs a big wood this near the street / tip
M.SECTORS = 16            -- the outline's heading sectors
M.OUTLINE_Q = 0.85        -- per sector this quantile of the housed streets' distances ...
M.OUTLINE_MIN = 120       -- ... at least this (m)
M.OUTLINE_EMPTY_K = 0.6   -- a sector without houses: this x the town's own quantile (the town does not reach there)
M.SCAN_MAX = 6000         -- edges read per call at most (loop cap)
-- the lead beyond housed streets (ot_select limits.leadCap / housedMin / armCont, steer towns): no bare spikes
M.LEAD_BLOCKS = 2         -- the lead at most this many blocks (max(len, depth)) ...
M.LEAD_CAP = { 150, 250 } -- ... within this (m)
M.HOUSED_MIN_B = 2        -- a street counts as housed for the lead with this many buildings (one house is no front)
M.ARM_GAP_BLOCKS = 1      -- an arm's housed front runs on only across gaps of at most this many blocks ...
M.ARM_GAP_MIN = 100       -- ... at least this (m): one far house no longer moves the front (Merehythe's arm, 1936)

-- the lock maturity (§70, 2026-10-15; run 2026-10-15_2031_sqot: towns of 311-534 buildings read 0-0.16 after 40 years,
-- their persons (ot_assess.maturity, 1800..3600) low with the era's small houses, so every street they built stayed
-- locked and the game filled nothing (game share 0.00-0.34; the grown towns 0.57-0.68)): the larger of
--   base  the persons measure (ot_assess.maturity, as §69),
--   size  the buildings, SIZE_B[1]..SIZE_B[2] x the style / era scale (M.sizeScale),
--   age   the years since the town's first frame, AGE_Y[1]..AGE_Y[2], at most AGE_W (age alone never opens a town
--         fully), times the size gate (buildings over AGE_GATE_B x the scale: an old hamlet stays young).
M.SIZE_B = { 150, 600 }   -- buildings: size maturity 0 .. 1 (organic styles, eras up to ERA_Y[1])
M.SIZE_GRID_K = 1.2       -- grid styles (larger blocks, more buildings per street): this x the buildings
M.ERA_Y = { 1930, 1990 }  -- years: buildings grow larger over these ...
M.ERA_K = 0.75            -- ... the scale falls to this (fewer, larger buildings house the same town)
M.AGE_Y = { 5, 35 }       -- years since the first frame: age maturity 0 .. AGE_W ...
M.AGE_W = 0.8
M.AGE_GATE_B = 450        -- ... times min(1, buildings / this x the scale)

--- The building scale of a style and year (1: organic styles before ERA_Y[1]).
function M.sizeScale(style, year)
	local k = (style and style.grower ~= "organic") and M.SIZE_GRID_K or 1
	local y = tonumber(year)
	if y ~= nil and y == y then
		local t = math.max(0, math.min(1, (y - M.ERA_Y[1]) / math.max(1, M.ERA_Y[2] - M.ERA_Y[1])))
		k = k * (1 + (M.ERA_K - 1) * t)
	end
	return k
end

--- The lock maturity (0..1) from base (ot_assess.maturity or nil), buildings, age (years since the first frame, or nil:
--- unknown) and the scale (M.sizeScale). Returns the maturity and its parts { size, age, base } (age already gated).
function M.maturity(base, buildings, age, scale)
	scale = tonumber(scale) or 1
	if not (scale > 0) then scale = 1 end
	local b = tonumber(buildings) or 0
	if b ~= b then b = 0 end
	local lo, hi = M.SIZE_B[1] * scale, M.SIZE_B[2] * scale
	local size = hi > lo and math.max(0, math.min(1, (b - lo) / (hi - lo))) or (b >= lo and 1 or 0)
	local ag = 0
	local a = tonumber(age)
	if a ~= nil and a == a then
		ag = M.AGE_W * math.max(0, math.min(1, (a - M.AGE_Y[1]) / math.max(0.01, M.AGE_Y[2] - M.AGE_Y[1])))
		ag = ag * math.max(0, math.min(1, b / (M.AGE_GATE_B * scale)))
	end
	local bs = tonumber(base)
	if bs ~= nil and bs ~= bs then bs = nil end
	local v = math.max(bs or 0, size, ag)
	return math.max(0, math.min(1, v)), { size = size, age = ag, base = bs }
end

--- Log text of the maturity: "<v>:size<a>:age<b>:base<c>".
function M.matText(v, parts)
	if v == nil then return "-" end
	parts = parts or {}
	return string.format("%.2f:size%.2f:age%.2f:base%s", v, parts.size or 0, parts.age or 0,
		parts.base and string.format("%.2f", parts.base) or "-")
end

local function wrap(a)
	a = a % (2 * pi)
	if a > pi then a = a - 2 * pi end
	return a
end

local function sectorOf(a, n)
	local u = (a % (2 * pi)) / (2 * pi) * n
	return floor(u) % n + 1
end

--- The inner zone's share of the outline at maturity mat (0..1; nil: grown).
function M.innerK(mat)
	mat = tonumber(mat) or 1
	local lo, hi = M.MAT[1], M.MAT[2]
	local t = hi > lo and math.max(0, math.min(1, (mat - lo) / (hi - lo))) or (mat >= lo and 1 or 0)
	t = t * t * (3 - 2 * t)
	return M.INNER_K[1] + (M.INNER_K[2] - M.INNER_K[1]) * t
end

--- The town's built outline: items = { { x, y, built } } (street midpoints, houses on them), centre (cx, cy). Returns
--- { cx, cy, n, r = { [sector] = m }, rq = the whole town's quantile, housed = count } or nil (no housed street).
function M.outline(items, cx, cy)
	local n = M.SECTORS
	local per, all = {}, {}
	for i = 1, n do per[i] = {} end
	for i = 1, math.min(#(items or {}), M.SCAN_MAX) do
		local it = items[i]
		if (it[3] or 0) > 0 and it[1] == it[1] and it[2] == it[2] then
			local dx, dy = it[1] - cx, it[2] - cy
			local d = math.sqrt(dx * dx + dy * dy)
			local s = sectorOf(atan2(dy, dx), n)
			per[s][#per[s] + 1] = d
			all[#all + 1] = d
		end
	end
	if #all == 0 then return nil end
	local function q(list)
		table.sort(list)
		return list[math.max(1, math.floor(#list * M.OUTLINE_Q + 0.5))] or 0
	end
	local rq = math.max(M.OUTLINE_MIN, q(all))
	local raw = {}
	for i = 1, n do raw[i] = #per[i] > 0 and math.max(M.OUTLINE_MIN, q(per[i])) or math.max(M.OUTLINE_MIN, M.OUTLINE_EMPTY_K * rq) end
	local r = {}
	for i = 1, n do
		local p, nx = raw[(i - 2) % n + 1], raw[i % n + 1]
		r[i] = math.max(M.OUTLINE_MIN, 0.25 * p + 0.5 * raw[i] + 0.25 * nx)
	end
	return { cx = cx, cy = cy, n = n, r = r, rq = rq, housed = #all }
end

--- A round outline of radius r (a town without housed streets yet: its extent).
function M.roundOutline(cx, cy, r)
	local n = M.SECTORS
	local rr = {}
	for i = 1, n do rr[i] = math.max(M.OUTLINE_MIN, tonumber(r) or 0) end
	return { cx = cx, cy = cy, n = n, r = rr, rq = rr[1], housed = 0, round = true }
end

--- The outline radius at heading a (linear between the sector centres); without an outline: math.huge.
function M.rAt(ol, a)
	if ol == nil then return math.huge end
	local n = ol.n
	local u = (a % (2 * pi)) / (2 * pi) * n - 0.5
	local i = floor(u)
	local t = u - i
	local r0, r1 = ol.r[i % n + 1], ol.r[(i + 1) % n + 1]
	return r0 * (1 - t) + r1 * t
end

--- Where (x, y) lies: d (m from the centre), R (the outline there), a (heading). Without an outline: d, huge, a.
function M.where(ol, x, y, cx, cy)
	cx, cy = (ol and ol.cx) or cx or 0, (ol and ol.cy) or cy or 0
	local dx, dy = x - cx, y - cy
	local a = atan2(dy, dx)
	return math.sqrt(dx * dx + dy * dy), M.rAt(ol, a), a
end

--- Does the street at point (x, y), heading outward (ux, uy), face something the town must not grow into? ctx = { fg
--- (ot_forest grid), wet = function(x, y), gaps (ot_gap), field (ot_land), fo (the style's forest info: hug / deep
--- towns), p0, p1, tip0, tip1 (the street, for ot_forest.facesForest), rim = at or beyond the outline }. Returns
--- "forest" | "water" | "neighbour" | "lean" | nil; with nil a second value "smallWood" when only small woods (under
--- ot_forest.WOOD_MIN_HA, §71) would have made it face forest.
local function bigWood(fg, x, y) return FO.bigWoodAt(fg, x, y) end
M.bigWood = bigWood
local function forestAhead(fg, x, y, ux, uy, px, py, isWood)
	isWood = isWood or SK.denseAt
	if isWood(fg, px, py) then return true end
	if SK.clearAhead(fg, x + ux * 20, y + uy * 20, ux, uy, isWood) < SK.CLEAR_M then return true end
	-- (§70: ahead, a narrow clearing between woods on both sides: SK.corridorAt)
	if M.CORRIDOR and SK.corridorAt(fg, px, py, -uy, ux, isWood) ~= nil then return true end
	return false
end
function M.facing(x, y, ux, uy, ctx, a)
	ctx = ctx or {}
	local small = false
	local fo = ctx.fo
	if fo ~= nil and ctx.p0 ~= nil and FO.active(fo) and FO.facesForest(fo, ctx.p0, ctx.p1, ctx.tip0, ctx.tip1) then
		-- (§71: a hug town's forest face needs a big wood by the street; deep towns as before)
		if not M.SMALL_WOOD or FO.isDeep(fo) or fo.grid == nil
			or FO.bigWoodBy(fo.grid, ctx.p0, ctx.p1, M.SMALL_WOOD_R, ctx.tip0, ctx.tip1, FO.TIP_PROBE) then
			return "forest"
		end
		small = true
	end
	local px, py = x + ux * M.AHEAD_M, y + uy * M.AHEAD_M
	local fg = ctx.fg
	if fg ~= nil and fg.cover ~= nil then
		if forestAhead(fg, x, y, ux, uy, px, py, M.SMALL_WOOD and bigWood or nil) then return "forest" end
		if M.SMALL_WOOD and not small and forestAhead(fg, x, y, ux, uy, px, py, nil) then small = true end
	end
	if ctx.wet and (ctx.wet(px, py) or ctx.wet((x + px) / 2, (y + py) / 2)) then return "water" end
	if ctx.gaps ~= nil and GP.held(ctx.gaps, { { px, py } }, "small") ~= nil then return "neighbour" end
	if ctx.rim and ctx.field ~= nil and a ~= nil and LAND.at(ctx.field, a) < M.LEAN_BAD then return "lean" end
	return nil, small and "smallWood" or nil
end

-- the outer end of a street and its outward direction (away from the centre)
local function outward(p0, p1, cx, cy)
	local d0 = G.dist(cx, cy, p0[1], p0[2])
	local d1 = G.dist(cx, cy, p1[1], p1[2])
	local a, b = p0, p1
	if d0 > d1 then a, b = p1, p0 end
	local L = G.dist(a[1], a[2], b[1], b[2])
	local ux, uy
	if L > 1e-6 then ux, uy = (b[1] - a[1]) / L, (b[2] - a[2]) / L end
	-- (a street running round the town, not out of it: the radial direction at its outer end)
	local rx, ry = b[1] - cx, b[2] - cy
	local rl = math.sqrt(rx * rx + ry * ry)
	if rl > 1e-6 then
		rx, ry = rx / rl, ry / rl
		if ux == nil or ux * rx + uy * ry < 0.5 then ux, uy = rx, ry end
	end
	return b[1], b[2], ux or 1, uy or 0
end
M.outward = outward

--- A new mod street of a steer town: lock it? e = { p0, p1, key, tip0, tip1 }; c = { outline, cx, cy, mat, shape,
--- ctx (M.facing's) }. Returns locked (bool), why ("face:<what>" | "arm" | "out" | "rim" | "fill"), and true as a third
--- value when small woods alone would have made it face forest (§71: `smallWood=`).
function M.decide(e, c)
	if e == nil or e.p0 == nil or e.p1 == nil then return true, "bad" end
	local cx, cy = (c.outline and c.outline.cx) or c.cx or 0, (c.outline and c.outline.cy) or c.cy or 0
	local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
	local d, R, a = M.where(c.outline, mx, my, cx, cy)
	local ox, oy, ux, uy = outward(e.p0, e.p1, cx, cy)
	local ctx = {}
	for k, v in pairs(c.ctx or {}) do ctx[k] = v end
	ctx.p0, ctx.p1, ctx.tip0, ctx.tip1 = e.p0, e.p1, e.tip0, e.tip1
	ctx.rim = d >= M.GK_RIM_K * R
	local f, sm = M.facing(ox, oy, ux, uy, ctx, a)
	if f then return true, "face:" .. f end
	sm = sm == "smallWood"
	local mat = tonumber(c.mat) or 1
	if c.shape ~= nil and mat < M.ARM_FREE_MAT and SH.inArm(c.shape, mx, my) then return true, "arm", sm end
	if d > R then return true, "out", sm end
	if d > M.innerK(mat) * R then return true, "rim", sm end
	return false, "fill", sm
end

--- A game (or core) street of a steer town: lock it? ed = an edge record (p0, p1); c as M.decide's. Returns the reason
--- ("face:<what>" | "young") or nil (left open: "inside" / "open" as the second value). c.small (a number, when set) counts
--- the rim streets whose face small woods alone would have made (§71).
function M.gameLock(ed, c)
	if ed == nil or ed.p0 == nil or ed.p1 == nil then return nil, "bad" end
	local cx, cy = (c.outline and c.outline.cx) or c.cx or 0, (c.outline and c.outline.cy) or c.cy or 0
	local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
	local d, R, a = M.where(c.outline, mx, my, cx, cy)
	if R == math.huge or d < M.GK_RIM_K * R then return nil, "inside" end
	-- (c.faceCache: { [edge id] = what | false }, the probes are static per edge: forest, water, gaps, the lean)
	local f = nil
	local fc = c.faceCache
	if fc ~= nil and ed.id ~= nil then f = fc[ed.id] end
	if f == nil then
		local ox, oy, ux, uy = outward(ed.p0, ed.p1, cx, cy)
		local ctx = {}
		for k, v in pairs(c.ctx or {}) do ctx[k] = v end
		ctx.fo, ctx.rim = nil, true
		local f1, sm = M.facing(ox, oy, ux, uy, ctx, a)
		-- (cached: the face, "~small" (open, small woods only) or false)
		f = f1 or (sm == "smallWood" and "~small") or false
		if fc ~= nil and ed.id ~= nil then fc[ed.id] = f end
	end
	if f == "~small" then
		if type(c.small) == "number" then c.small = c.small + 1 end
		f = false
	end
	if f then return "face:" .. f end
	if (tonumber(c.mat) or 1) < M.YOUNG_MAT and d > R then return "young" end
	return nil, "open"
end

--- The steer lead (m) for a style: LEAD_BLOCKS blocks within LEAD_CAP.
function M.leadCap(style)
	local blk = style and style.block and math.max(style.block.len or 0, style.block.depth or 0) or 0
	return math.max(M.LEAD_CAP[1], math.min(M.LEAD_CAP[2], M.LEAD_BLOCKS * blk))
end

--- The gap an arm's housed front may run on across (m).
function M.armGap(style)
	local blk = style and style.block and math.max(style.block.len or 0, style.block.depth or 0) or 0
	return math.max(M.ARM_GAP_MIN, M.ARM_GAP_BLOCKS * blk)
end

--- The continuous housed front along an arm: along = the housed streets' distances along it (any order), from = the
--- town's housed radius there (rq), gap = the most a run of unhoused street may span. Returns the front (m along).
function M.contFront(along, from, gap)
	local list = {}
	for i = 1, math.min(#(along or {}), M.SCAN_MAX) do list[i] = along[i] end
	table.sort(list)
	local f = from or 0
	for _, x in ipairs(list) do
		if x > f then
			if x - f <= gap then f = x else break end
		end
	end
	return f
end

--- Policy tally text: "<why>:<n>/..." in a fixed order ("-" when empty).
M.WHY_ORDER = { "face:forest", "face:water", "face:neighbour", "face:lean", "arm", "out", "rim", "tip", "fill", "young" }
function M.tallyText(t)
	local parts = {}
	for _, k in ipairs(M.WHY_ORDER) do if (t[k] or 0) > 0 then parts[#parts + 1] = k:gsub("face:", "") .. ":" .. t[k] end end
	if #parts == 0 then return "-" end
	return table.concat(parts, "/")
end

return M
