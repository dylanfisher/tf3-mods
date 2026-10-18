-- Organic Towns: the landscape pull (pure; §62, 2026-10-15; PLAN.md 6.2 "Landscape pull").
--
-- User, watching a run (US names, European build style, 1900): "i wonder if we should have more weight to build in a
-- general direction away from forests. but on a larger level ... imagine the forests pushing growth away, and towns
-- wanting to fill in where the green lines are going ... jsut try to weight overall high level growth using bigger
-- geographical cues", then "yes we need bigger scale influences. water, mountains, foreset, prairies, canyon, etc".
--
-- The town's overall growth direction (ot_select.preference: seeded sectors, the coast lean, away from industry) never
-- read the land beyond the town; the forest acted per piece only (ot_forest hug / deep). Here one smooth angular field
-- per town from the big-scale readings the driver already has, no new engine reads:
--   * forest  the town's tree grid (ot_forest, R 1500 m): the mean cover of N sectors of the ring r0..r1 (r0 beyond the
--             town's own extent, so the trees its streets cleared don't count): large woods push away
--   * steep   the wide survey's rays (ot_terrain.wide, 16 rays x 500 / 1000 / 1500 / 2000 m): the mean grade along each
--             ray (uphill full, downhill DOWN_F): mountains and steep rising ground push away; a valley's walls rise on
--             two sides, so its floor axis (both ways) stays favoured, a hillside's contour too
--   * water   the same rays' wet points: the dry directions beside water pull (along the shore, the banks), the wet
--             directions themselves never (no growth across the water)
--   * open    unwooded x even x dry ground: the strongest pull (prairie, open fields)
-- F(k) = W.open open - W.forest forest - W.steep steep + W.water shore per sector, smoothed once, centred; the lean is
-- F normalised to [-1, 1], its strength k = K_MAX x the asymmetry (range of F between A0 and A1): uniform land gives no
-- lean. ot_select blends it into the preference next to the seeded sectors (TOTAL_MAX caps both together, so the seeded
-- variety stays). Style factors (M.forStyle): clear-mode forest towns feel the forest at CLEAR_F, deep forest towns at
-- DEEP_F, character towns keep their intent (CHAR_F; a hilltop ignores the steep cue, the shore kinds the water cue),
-- a coast lean already pulls to the sea (water at COAST_F). Every loop runs over the grid's cells or the N sectors.
-- Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

local cos, sin, abs, floor = math.cos, math.sin, math.abs, math.floor

M.ON = true
M.N = 16                       -- sectors (the wide survey's rays sit on their centres)
M.R0 = 300                     -- m: the forest ring starts at least this far out ...
M.R0_EXT = 1.1                 -- ... and beyond the town's extent x this ...
M.R0_MAX = 1000                -- ... but at most here (a big town still reads the woods beyond it)
M.R1 = 1450                    -- m: the forest ring's outer edge (the grid's half size is 1500)
M.R0_STEP = 100                -- m: r0 rounded to this (the read is cached per town and step)
M.RAY_W = { 1, 0.7, 0.45, 0.25 }   -- weights of the wide survey's ray points (500 / 1000 / 1500 / 2000 m)
M.GRADE = { 0.025, 0.09 }      -- mean ray grade: no push below, full push above
M.DOWN_F = 0.6                 -- falling ground counts this much of rising ground
M.W = { open = 1.0, forest = 0.8, steep = 0.9, water = 0.6 }
M.SHORE_K = { 1, 0.75, 0.4 }   -- a wet sector's pull on its neighbours 1 / 2 / 3 sectors away (along the shore)
M.ALONG_K = 0.8                -- the near water's bank / shore axis pulls this much (both ways)
M.A0 = 0.2                     -- range of F under this: no lean (patchy but even land)
M.A1 = 1.0                     -- ... full strength from this
M.K_MAX = 0.35                 -- the lean's weight at most (ot_select adds it to the seeded amplitude)
M.TOTAL_MAX = 0.55             -- ot_select: seeded amplitude + lean weight at most this (both scaled down together)
M.SHAPE_F = 0.5                -- shaped towns (ot_shape): the lean x this in the cost (like SH.SECTOR_DAMP)
M.CLEAR_F = 0.5                -- forest cue x this for clear-mode towns (a metropolis too)
M.DEEP_F = 0.3                 -- ... and for deep forest towns (they live in the woods)
M.CHAR_F = 0.5                 -- character towns: the lean x this
M.COAST_F = 0.5                -- water cue x this when the coast lean already pulls (style.waterDir)
M.SHORE_KINDS = { waterfront = true, clifftop = true, harbour_cove = true, island_town = true }
M.LOBE_MIN_K = 0.08            -- lobe headings re-ordered by the lean from this strength
M.CUE_MIN = 0.3                -- LAND cues: a cue is named when its sectors differ by at least this
M.CELL_MAX = 20000             -- grid cells read at most (hang guard; the 1500 m grid at 50 m has 3600)

local TWO_PI = 2 * math.pi

local function clamp(v, lo, hi)
	if v ~= v then return lo end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

--- Sector index (1..n) of heading a (sector k centred on (k - 1) / n x 2 pi).
function M.sectorOf(a, n)
	n = n or M.N
	local u = (a % TWO_PI) / TWO_PI * n
	return floor(u + 0.5) % n + 1
end

--- The forest ring's inner radius for a town of extent r (m), rounded to R0_STEP.
function M.r0For(extR)
	local r = math.max(M.R0, (tonumber(extR) or 0) * M.R0_EXT)
	r = math.min(r, M.R0_MAX)
	return floor(r / M.R0_STEP + 0.5) * M.R0_STEP
end

--- Mean forest cover of n sectors of the ring r0..r1 around the grid's centre: { [1..n] }, or nil without a grid.
function M.forestSectors(fg, r0, r1, n)
	if fg == nil or fg.cover == nil or not fg.n then return nil end
	n = n or M.N
	r1 = math.min(r1 or M.R1, (fg.r or M.R1) - (fg.cell or 50) / 2)
	if r1 <= r0 then return nil end
	local sum, cnt = {}, {}
	for k = 1, n do sum[k], cnt[k] = 0, 0 end
	local a2, b2 = r0 * r0, r1 * r1
	local cells = 0
	for i = 0, fg.n - 1 do
		local x = fg.x0 + (i + 0.5) * fg.cell
		local dx = x - fg.cx
		if abs(dx) <= r1 then
			for j = 0, fg.n - 1 do
				cells = cells + 1
				if cells > M.CELL_MAX then break end
				local y = fg.y0 + (j + 0.5) * fg.cell
				local dy = y - fg.cy
				local d2 = dx * dx + dy * dy
				if d2 >= a2 and d2 <= b2 then
					local k = M.sectorOf(G.atan2(dy, dx), n)
					sum[k] = sum[k] + (fg.cover[i * fg.n + j + 1] or 0)
					cnt[k] = cnt[k] + 1
				end
			end
		end
		if cells > M.CELL_MAX then break end
	end
	local out = {}
	for k = 1, n do out[k] = cnt[k] > 0 and sum[k] / cnt[k] or 0 end
	return out
end

--- Per-ray steepness and wetness from the wide survey's rays (ot_terrain.wide `rays`, `hc`): steep[k], wet[k] in 0..1,
--- or nil without rays. Ray points marked `off` (off the map, the driver) count as wet (no land to grow onto).
function M.raySectors(wide, n)
	local rays = wide and wide.rays
	if rays == nil or #rays == 0 then return nil end
	n = n or M.N
	local steep, wet = {}, {}
	local nr = #rays
	for k = 1, n do
		-- (the survey's ray nearest to sector k's centre; WIDE_N = N in practice)
		local ri = floor((k - 1) / n * nr + 0.5) % nr + 1
		local ray = rays[ri]
		local ws, wsum, gs, gw = 0, 0, 0, 0
		local hPrev, rPrev, blocked = wide.hc, 0, false
		for i, p in ipairs(ray) do
			if i > 8 then break end
			local w = M.RAY_W[i] or 0.1
			wsum = wsum + w
			if p.wet or p.off then
				ws = ws + w
				blocked = true
			elseif not blocked and hPrev ~= nil and p.r and p.r > rPrev and p.h then
				local dh = p.h - hPrev
				local g = (dh > 0 and dh or -dh * M.DOWN_F) / (p.r - rPrev)
				gs, gw = gs + w * g, gw + w
				hPrev, rPrev = p.h, p.r
			end
		end
		wet[k] = wsum > 0 and ws / wsum or 0
		local g = gw > 0 and gs / gw or 0
		steep[k] = clamp((g - M.GRADE[1]) / (M.GRADE[2] - M.GRADE[1]), 0, 1)
	end
	return steep, wet
end

M.NEAR_WET = 0.6              -- the disc's water (stats.water: a river or shore the wide rays step over) at most this wet ...
M.NEAR_POW = 3                 -- ... toward its side, cos^NEAR_POW wide
M.NEAR_STRADDLE = 60           -- m: a river nearer than this runs through the town (no wet side, its banks still pull)

--- The disc's water as sector cues (ot_terrain.stats `water`: kind, dir, axis, distance, body): wet[k] toward the
--- water's side (none for a river through the town), along[k] = how well sector k runs along its bank / shore
--- (cos^2 to the axis). nil, nil for none or a pond.
function M.nearWater(stats, n)
	local w = stats and stats.water
	if w == nil or w.dir == nil or w.body == "pond" then return nil, nil end
	local through = w.kind == "river" and (w.distance or 0) < M.NEAR_STRADDLE
	n = n or M.N
	local wet, along = {}, {}
	local near = clamp(1 - (w.distance or 0) / 1200, 0.4, 1) * M.NEAR_WET
	local axis = w.axis or (w.dir + math.pi / 2)
	for k = 1, n do
		local a = (k - 1) / n * TWO_PI
		local c = cos(a - w.dir)
		wet[k] = (c > 0 and not through) and near * c ^ M.NEAR_POW or 0
		along[k] = cos(a - axis) ^ 2
	end
	return wet, along
end

--- The town's raw readings: { n, forest = {..} | nil, steep = {..} | nil, wet = {..} | nil, along = {..} | nil, r0 }.
--- fg: the tree grid (stats.forest), wide: the wide survey (with rays), extR: the town's extent (m), stats: the disc
--- statistics (its `water`: the river or shore near the town, which the 500 m ray steps can miss).
function M.read(fg, wide, extR, stats)
	if not M.ON then return nil end
	local n = M.N
	local r0 = M.r0For(extR)
	local forest = M.forestSectors(fg, r0, M.R1, n)
	local steep, wet = M.raySectors(wide, n)
	local nw, along = M.nearWater(stats, n)
	if nw then
		wet = wet or {}
		for k = 1, n do wet[k] = math.max(wet[k] or 0, nw[k]) end
	end
	if forest == nil and steep == nil and nw == nil then return nil end
	return { n = n, forest = forest, steep = steep, wet = wet, along = along, r0 = r0 }
end

--- Circular smoothing (1, 2, 1) / 4 of v[1..n].
local function smooth(v, n)
	local out = {}
	for k = 1, n do
		local a, b = v[(k - 2) % n + 1], v[k % n + 1]
		out[k] = (a + 2 * v[k] + b) / 4
	end
	return out
end

local function range(v, n)
	local lo, hi, kHi, kLo = math.huge, -math.huge, 1, 1
	for k = 1, n do
		if v[k] > hi then hi, kHi = v[k], k end
		if v[k] < lo then lo, kLo = v[k], k end
	end
	return hi - lo, kHi, kLo
end

--- Heading (rad) where v[1..n] is strongest: the resultant of its above-mean parts (a plateau of equal sectors reads
--- its middle), the top sector when they cancel out (two opposite lobes). sign = -1: where it is weakest.
local function heading(v, n, sign)
	sign = sign or 1
	local mean = 0
	for k = 1, n do mean = mean + v[k] end
	mean = mean / n
	local x, y, sum, best, bv = 0, 0, 0, 1, -math.huge
	for k = 1, n do
		local d = sign * (v[k] - mean)
		if d > bv then best, bv = k, d end
		if d > 0 then
			local a = (k - 1) / n * TWO_PI
			x, y, sum = x + d * cos(a), y + d * sin(a), sum + d
		end
	end
	if sum > 1e-9 and math.sqrt(x * x + y * y) >= 0.5 * sum then return G.atan2(y, x) % TWO_PI end
	return (best - 1) / n * TWO_PI
end
M.heading = heading

M.PEAK_TOL = 0.15              -- cue names: the sectors within this x the range of the top form its run

--- Heading (rad) of v[1..n]'s top: the middle of the circular run of sectors within PEAK_TOL x the range of the
--- smoothed maximum that holds it (a plateau reads its middle, two separate lobes the stronger one, never the gap
--- between them). mask[k] false: sector k is never the top (nil: every sector may be).
function M.peakHeading(v, n, mask)
	local sv = smooth(v, n)
	local hi, kHi, lo = -math.huge, nil, math.huge
	for k = 1, n do
		if (mask == nil or mask[k]) and sv[k] > hi then hi, kHi = sv[k], k end
		if sv[k] < lo then lo = sv[k] end
	end
	if kHi == nil then return heading(v, n) end
	local tol = M.PEAK_TOL * (hi - lo)
	local function inRun(k) return (mask == nil or mask[k]) and sv[k] >= hi - tol end
	local a, b = 0, 0
	for _ = 1, n - 1 do
		if not inRun((kHi - 2 - a) % n + 1) or a + b >= n - 1 then break end
		a = a + 1
	end
	for _ = 1, n - 1 do
		if not inRun((kHi + b) % n + 1) or a + b >= n - 1 then break end
		b = b + 1
	end
	local mid = (kHi - 1) + (b - a) / 2
	return (mid / n * TWO_PI) % TWO_PI
end

--- The field from raw readings and cue weights w ({ open, forest, steep, water }, default M.W): { n, lean = {[1..n]
--- in [-1, 1]}, k (0..K_MAX), A (asymmetry), peak / low (headings, rad), cues = { forest = k, steep = k, water = k,
--- open = heading } (where each cue is strongest, only when it varies by CUE_MIN) } or nil without readings.
function M.combine(rd, w)
	if rd == nil then return nil end
	w = w or M.W
	local n = rd.n or M.N
	local fo, st, we = rd.forest, rd.steep, rd.wet
	local F, open, shore = {}, {}, {}
	for k = 1, n do
		local f = fo and fo[k] or 0
		local s = st and st[k] or 0
		local d = we and we[k] or 0
		-- (a cue a style ignores doesn't close the open land either: a hilltop's slopes, a waterfront's water)
		open[k] = (1 - f) * ((w.steep or 0) > 0 and (1 - s) or 1) * ((w.water or 0) > 0 and (1 - d) or 1)
		local sh = 0
		if we then
			for o = 1, #M.SHORE_K do
				local a, b = we[(k - 1 - o) % n + 1], we[(k - 1 + o) % n + 1]
				sh = math.max(sh, M.SHORE_K[o] * math.max(a, b))
			end
			-- (along the near river's banks / the shore, both ways)
			if rd.along then sh = math.max(sh, M.ALONG_K * rd.along[k]) end
			sh = sh * (1 - d)
		end
		shore[k] = sh
		F[k] = (w.open or 0) * open[k] - (w.forest or 0) * f - (w.steep or 0) * s + (w.water or 0) * sh
	end
	F = smooth(F, n)
	local mean = 0
	for k = 1, n do mean = mean + F[k] end
	mean = mean / n
	local A = range(F, n)
	local mx = 0
	for k = 1, n do
		F[k] = F[k] - mean
		if abs(F[k]) > mx then mx = abs(F[k]) end
	end
	local lean = {}
	for k = 1, n do lean[k] = mx > 1e-9 and F[k] / mx or 0 end
	local kk = M.K_MAX * clamp((A - M.A0) / (M.A1 - M.A0), 0, 1)
	local cues = {}
	local function cue(name, v, weight, mask)
		if v == nil or (weight or 0) <= 0 then return end
		if range(v, n) >= M.CUE_MIN then cues[name] = M.peakHeading(v, n, mask) end
	end
	-- (§63 fix: run 2026-10-15_0539_sqot's Seachurch_Cove read `cues=open:N,forest:N`: the open cue was the resultant of
	-- the above-mean sectors, which landed on a forest lobe between two open sides. Each cue now names its own top
	-- (the middle of its near-top run of sectors), and open land only among the sectors with at most mean forest)
	local fMask = nil
	if fo and (w.forest or 0) > 0 and range(fo, n) >= M.CUE_MIN then
		local fm = 0
		for k = 1, n do fm = fm + fo[k] end
		fm = fm / n
		fMask = {}
		for k = 1, n do fMask[k] = fo[k] <= fm + 1e-9 end
	end
	cue("open", open, w.open, fMask)
	cue("forest", fo, w.forest)
	cue("steep", st, w.steep)
	cue("water", we, w.water)
	return { n = n, lean = lean, k = kk, A = A, peak = heading(F, n), low = heading(F, n, -1), cues = cues, r0 = rd.r0 }
end

--- The lean at heading a (radians), linear between the sector centres: [-1, 1], 0 without a field.
function M.at(field, a)
	if field == nil or field.lean == nil then return 0 end
	local n = field.n or #field.lean
	local u = (a % TWO_PI) / TWO_PI * n
	local i = floor(u)
	local t = u - i
	local v0, v1 = field.lean[i % n + 1], field.lean[(i + 1) % n + 1]
	return (v0 or 0) * (1 - t) + (v1 or 0) * t
end

--- Cue weights and an overall factor for a style: w, factor, why (text; "-" for none).
function M.weightsFor(style)
	local w = { open = M.W.open, forest = M.W.forest, steep = M.W.steep, water = M.W.water }
	local f, why = 1, {}
	local fo = style and style.forest
	if fo and (fo.mode == "clear") then w.forest = w.forest * M.CLEAR_F; why[#why + 1] = "clear" end
	if (fo and fo.mode == "deep") or (style and style.deep) then w.forest = w.forest * M.DEEP_F; why[#why + 1] = "deep" end
	local ck = style and style.charKind
	if ck then
		f = f * M.CHAR_F
		why[#why + 1] = "char"
		if ck == "hilltop" then w.steep = 0 end
		if M.SHORE_KINDS[ck] then w.water = 0 end
	end
	if style and style.waterDir and style.irregular and (style.irregular.coast or 0) > 0 then
		w.water = w.water * M.COAST_F
		why[#why + 1] = "coast"
	end
	return w, f, #why > 0 and table.concat(why, ",") or "-"
end

--- The field for a style from the town's raw readings (nil without): combine with the style's weights, k x factor.
function M.forStyle(rd, style)
	if rd == nil then return nil end
	local w, f, why = M.weightsFor(style)
	local field = M.combine(rd, w)
	if field == nil then return nil end
	field.kRaw = field.k
	field.k = field.k * f
	field.why = why
	return field
end

local COMPASS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }
--- 8-point compass name of heading a (0 = east, pi / 2 = north).
function M.compass(a)
	local i = floor((a % TWO_PI) / TWO_PI * 8 + 0.5) % 8 + 1
	return COMPASS[i]
end

--- LAND `cues=` text: "open:S,forest:NE,steep:W,water:E" (the cues that vary), "-" without.
function M.cuesText(field)
	if field == nil or field.cues == nil then return "-" end
	local parts = {}
	for _, name in ipairs({ "open", "forest", "steep", "water" }) do
		local k = field.cues[name]
		if k then parts[#parts + 1] = name .. ":" .. M.compass(k) end
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- PLAN `land=` text: "open:S,forest:NE/k0.35/to270" ("-" without a field).
function M.text(field)
	if field == nil then return "-" end
	return string.format("%s/k%.2f/to%.0f", M.cuesText(field), field.k or 0, math.deg(field.peak or 0) % 360)
end

--- Lobe headings ordered by the lean (favoured first; stable): a new list, or dirs itself when the lean is weak.
function M.orderDirs(dirs, field)
	if dirs == nil or #dirs < 2 or field == nil or (field.k or 0) < M.LOBE_MIN_K then return dirs end
	local list = {}
	for i, a in ipairs(dirs) do list[i] = { a = a, v = M.at(field, a), i = i } end
	table.sort(list, function(p, q)
		if abs(p.v - q.v) > 1e-9 then return p.v > q.v end
		return p.i < q.i
	end)
	local out = {}
	for i, p in ipairs(list) do out[i] = p.a end
	return out
end

return M
