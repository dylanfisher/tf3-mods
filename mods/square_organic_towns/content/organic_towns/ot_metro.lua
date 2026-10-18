-- Organic Towns: metropolis, an automatic city style (pure). NEXT_PHASE_BRIEF 14 (2026-10-12).
--
-- User (Showcase v6): "Metropolis is still really cool looking with how much it fills out and how dense it is. That
-- shouldn't be an option in settings, it's just a city style that happens when appropriate (big flat area, city
-- type, etc.). I could imagine styles within the metropolis ... different road and locking to guide it to be dense
-- but in slightly different ways." And: "styles of bigger cities that once enough time goes on or they get big
-- enough there are multiple dense metro areas divided by suburbs or less dense areas, e.g. like Los Angeles".
--
-- Who becomes one (M.decide): a town of at least MIN_CAP persons on big flat open land (ot_site features: open >=
-- OPEN_MIN, rough <= ROUGH_MAX; a coast / river / valley town with open >= OPEN_CORRIDOR may become a corridor
-- metropolis), not a MED hill town, and only a seeded share of those (CHANCE x openness), so not every big town turns
-- into one. Deterministic per town (seed + site + size): nothing is saved, a reload decides the same once the town is
-- that big again.
--
-- Variants (M.VARIANTS, picked per town from region and site, M.variantWeights). Every variant fills densely (the
-- driver's "metro" fill: DevelopAt beside new streets, ot_driver), gets large / medium arterials (from the template
-- era that has them; the straight-wide rule of ot_core keeps them straight) and differs in shape, road mix, which
-- streets are locked and where the fill goes:
--   grid         compact, arterial lines closer together (grid growers), no lock: the town packs side streets in;
--                fill beside every new street
--   radial       compact, more spokes / tighter rings (organic growers); the arterials (main / medium pieces) are
--                locked so they stay clean thoroughfares; fill nearest the centre first
--   corridor     linear with strong reach along one spine (the fill rule keeps it from running out empty, ot_select
--                ARM_FILL); streets off the corridor band are locked, fill only inside the band
--   oldcore      compact; the organic old centre keeps its style, beyond the current radius a grid zone (EU extension,
--                ensanche or NA grid: ot_style.zone outer); fill nearest the centre first
--   polycentric  several dense centres (LA): from POLY_MIN_CAP (or forced) one or two secondary centres POLY_D out on
--                flat dry land (the twin shape with several seconds, ot_shape); fill only within CENTRE_R of a centre,
--                streets between the centres locked (lower density there); the fill restores the initial capacities
--                with a looser brake (POLY_EXTRA, POLY_CAP) so the town doesn't explode
-- Green gaps (user, Density: control): no variant fills every block; the fill is per build (12 points), so
-- enclosed open land stays where no new street goes. ot_metrics.greenGaps measures it.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local ST = ug_require "square_organic_towns::/organic_towns/ot_style.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"

local M = {}

M.VARIANTS = { "grid", "radial", "corridor", "oldcore", "polycentric" }
M.INDEX = {}
for i, v in ipairs(M.VARIANTS) do M.INDEX[v] = i end

M.MIN_CAP = 4000          -- persons (~1000 buildings)
M.OPEN_MIN = 0.55         -- ot_site open feature
M.ROUGH_MAX = 0.35
M.OPEN_CORRIDOR = 0.3     -- coast / river / valley towns: a corridor metropolis from this openness
M.FLOOR_MIN = 0.7         -- ... or on a flat floor (ot_site floor, the town's own slope) in hilly country: a corridor
M.FLOOR_OPEN = 0.55       --     along the valley, its chance as from this openness (2026-10-13: Bexley, a flat river
                          --     town of 4164 persons in hills, was why=site: every town of that map read rough 1.00)
M.CHANCE = 0.35           -- share of the eligible towns (x min(1, open / 0.8)), seeded
M.NO_STYLE = { MED_HILL = true }
M.POLY_MIN_CAP = 9000     -- polycentric: secondary centres from this size (one; two from 2 x)
M.POLY_THIRD_CAP = 30000  -- ... a third from this size (later-ideas phase)
M.POLY_JUNCTION = true    -- ... a centre sits at a country-road junction in its range when one is there (later ideas)
M.POLY_J_RANGE = { 0.75, 1.2 }    -- ... junctions this x the centre's distance range
M.POLY_J_ANGLE = math.rad(75)     -- ... and within this of the centre's planned heading
M.POLY_SEP = 800          -- m: centres at least this far from each other
M.POLY_YEAR = 1950        -- ... car-age conurbations only
M.POLY_D = { 1200, 1700 } -- m from the main centre (min, max; seeded)
M.POLY_D_FORCED = { 800, 1000 }   -- forced centres (dev showcase: towns 2.5 km apart, 10 steps)
M.CENTRE_R = 400          -- m: a centre's dense disc (fill points, density log)
M.POLY_EXTRA = 0          -- polycentric fill: initial capacities may rise this share per fill (0.4 until 2026-10-14) ...
M.POLY_CAP = 3            -- ... and never above this x their base (ot_driver FILL restore)
-- Showcase v8 round (2026-10-12). Showcase v7: the metropolis variants looked distinct for 3-4 rounds and then all
-- became the same organic blob: ~90 % of a metropolis's streets were the game's own (radial: 1568 edges, 180 ours;
-- the game added 86-205 street edges per round vs our 18), because the unbraked fill reset the town's target to size
-- factor x its size every build (radial target 57658 vs 22136 persons after 9 builds), far beyond what 18 new edges
-- of ours could house, so the town built its own organic streets everywhere (and branched them off our unlocked
-- streets). So every variant now: restores the initial capacities after the fill with a brake (FILL_EXTRA per fill,
-- no cap but the driver's METRO_MAX_CAP), locks every new street (LOCK_ALL: the town can't branch off the skeleton;
-- locked streets still get houses, findings towns.md), and builds bigger increments (ot_driver METRO_MAX_EDGES), so
-- demand lands on our streets.
-- (2026-10-14: 0 like the dose, ot_driver FILL_EXTRA: no fill raises a town's target beyond the game's own; was 0.25)
M.FILL_EXTRA = 0          -- every variant: initial capacities may rise this share per fill (polycentric: POLY_EXTRA)
M.LOCK_ALL = true         -- every new street of a metropolis locked (else the variant's own rule, M.lockKeys)
M.CORRIDOR_BAND = 2.5     -- x block: corridor half width (lock outside, fill inside)
M.PARKS = 4               -- green reserves (parks) per metropolis (ot_style.greenReserves)
M.CRESCENT_PARKS = 1      -- ... of them crescents (ot_crescent; Showcase v9 round)
M.POLY_HOUSED = 1.5       -- polycentric: housed front (ot_select.HOUSED), blocks (Showcase v9 round)
M.POLY_EMPTY = 2000       -- ... and its empty budget (ot_core: unhoused street length + the increment), m

-- variant weights per region (the map's name set); site kind adds the corridor
M.REGION = {
	US = { grid = 3, polycentric = 2.5, radial = 0.5 },
	OCEANIA = { grid = 3, polycentric = 2, radial = 0.5 },
	EU = { oldcore = 2.5, radial = 2, grid = 1, polycentric = 0.8 },
	MED = { grid = 2, oldcore = 2, radial = 0.5 },
	NORDIC = { oldcore = 2, radial = 1, corridor = 1 },
	RU = { radial = 3, grid = 1, polycentric = 0.5 },
	JP = { grid = 2, corridor = 1.5, polycentric = 1.5 },
	EAST_ASIA = { grid = 2.5, polycentric = 1.5, corridor = 1 },
	ASIA = { grid = 1.5, oldcore = 1.5, polycentric = 1.2, radial = 1, corridor = 1 },
	MIXED = { grid = 1, oldcore = 1, polycentric = 1, radial = 1, corridor = 1 },   -- (Town style "Mixed")
}

--- Variant weights for a town: { {id, w} } (w > 0, M.VARIANTS order). region, features (ot_site), year.
function M.variantWeights(region, f, year)
	local base = M.REGION[region] or M.REGION.EU
	local w = {}
	for _, v in ipairs(M.VARIANTS) do w[v] = base[v] or 0.2 end
	local kind = f and f.kind
	if kind == "coast" or kind == "river" or kind == "valley" then w.corridor = w.corridor + 3 end
	if (year or 1960) < M.POLY_YEAR then w.polycentric = 0 end
	local out = {}
	for _, v in ipairs(M.VARIANTS) do if w[v] > 0 then out[#out + 1] = { id = v, w = w[v] } end end
	return out
end

--- Is the town a metropolis, and which kind? o = { styleId, cap (persons), features (ot_site.features), region,
--- year, seed, forced = variant id (dev showcase) }. Returns { variant, why, forced } or nil, why ("small" | "style"
--- | "site" | "rare").
function M.decide(o)
	if o.forced and M.INDEX[o.forced] then return { variant = o.forced, why = "forced", forced = true } end
	if (o.cap or 0) < M.MIN_CAP then return nil, "small" end
	if M.NO_STYLE[o.styleId or ""] then return nil, "style" end
	local f = o.features or {}
	local open, rough = f.open or 0, f.rough or 0
	local linearSite = f.kind == "coast" or f.kind == "river" or f.kind == "valley"
	local corridorSite = linearSite and open >= M.OPEN_CORRIDOR
	if (rough > M.ROUGH_MAX or open < M.OPEN_MIN) and not corridorSite and linearSite and (f.floor or 0) >= M.FLOOR_MIN then
		-- a flat valley / river / coast floor in hilly country: a corridor along it
		if rng.decide(o.dv, o.seed or 1, "metro") >= M.CHANCE * math.min(1, M.FLOOR_OPEN / 0.8) then return nil, "rare" end
		return { variant = "corridor", why = string.format("%s:floor=%.2f,rough=%.2f", f.kind or "?", f.floor, rough) }
	end
	if rough > M.ROUGH_MAX or (open < M.OPEN_MIN and not corridorSite) then return nil, "site" end
	if rng.decide(o.dv, o.seed or 1, "metro") >= M.CHANCE * math.min(1, math.max(open, 0.3) / 0.8) then return nil, "rare" end
	local ws = corridorSite and open < M.OPEN_MIN and { { id = "corridor", w = 1 } } or M.variantWeights(o.region, f, o.year)
	local total = 0
	for _, x in ipairs(ws) do total = total + x.w end
	local r = rng.decide(o.dv, o.seed or 1, "metroVariant") * total
	local id = ws[#ws].id
	for _, x in ipairs(ws) do
		r = r - x.w
		if r <= 0 then id = x.id break end
	end
	return { variant = id, why = string.format("%s:open=%.2f,rough=%.2f", f.kind or "?", open, rough) }
end

--- Number of secondary centres a polycentric metropolis has at this size (forcedCentres: at least one).
function M.centreCount(cap, forcedCentres)
	local n = 0
	if (cap or 0) >= M.POLY_MIN_CAP then n = 1 end
	if (cap or 0) >= 2 * M.POLY_MIN_CAP then n = 2 end
	-- (later-ideas phase: a third centre once the conurbation is big, NEXT_PHASE_BRIEF 14 "centres added over time")
	if (cap or 0) >= M.POLY_THIRD_CAP then n = 3 end
	if forcedCentres and n < 1 then n = 1 end
	return n
end

--- Secondary centres: n points POLY_D (or range = {min, max}) out from centre c, first along `axis`, the second on the opposite side; each
--- moved along its ring (+-30 / 60 deg) to the first flat dry spot (sampler: ot_terrain; no sampler: as planned).
--- Returns { {x, y, D} }.
local function okSpot(sampler, x, y)
	if not sampler then return true end
	local okW, wet = pcall(T.isWater, sampler, x, y)
	local okS, sl = pcall(T.slope, sampler, x, y)
	return not (okW and wet) and not (okS and sl and sl > 0.06)
end

--- (later-ideas phase, NEXT_PHASE_BRIEF 14 "centres at a junction of arterials") The country-road junction (ot_roads.trace
--- junctions: 3+ roads meet) nearest heading a0 within POLY_J_ANGLE, at POLY_J_RANGE x range from c, on flat dry land and
--- POLY_SEP from the centres so far: { x, y, D, src = "junction", heads } or nil.
function M.junctionCentre(c, a0, range, junctions, taken, sampler)
	local best, bt = nil, math.huge
	for _, j in ipairs(junctions or {}) do
		local x, y = j.x, j.y
		local D = G.dist(c[1], c[2], x, y)
		if D >= range[1] * M.POLY_J_RANGE[1] and D <= range[2] * M.POLY_J_RANGE[2] then
			local t = G.angleDiff(G.atan2(y - c[2], x - c[1]), a0)
			local clear = true
			for _, o in ipairs(taken) do if G.dist(o[1], o[2], x, y) < M.POLY_SEP then clear = false; break end end
			if clear and t <= M.POLY_J_ANGLE and t < bt and okSpot(sampler, x, y) then
				best, bt = { G.round(x, 1), G.round(y, 1), G.round(D, 1), src = "junction", heads = j.heads }, t
			end
		end
	end
	return best
end

function M.centres(c, axis, n, seed, sampler, range, junctions)
	local out = {}
	range = range or M.POLY_D
	for k = 1, n do
		local D = range[1] + (range[2] - range[1]) * rng.unit(seed or 1, "polyD", k)
		-- (the second opposite the first, the third across the axis)
		local a0 = axis + (k == 2 and math.pi or 0) + (k == 3 and math.pi / 2 or 0)
		local jc = M.POLY_JUNCTION and M.junctionCentre(c, a0, range, junctions, out, sampler) or nil
		local best = jc
		for _, da in ipairs({ 0, 30, -30, 60, -60 }) do
			if best then break end
			local a = a0 + math.rad(da)
			local x, y = c[1] + math.cos(a) * D, c[2] + math.sin(a) * D
			local clear = true
			for _, o in ipairs(out) do if G.dist(o[1], o[2], x, y) < M.POLY_SEP then clear = false; break end end
			if clear and okSpot(sampler, x, y) then best = { G.round(x, 1), G.round(y, 1), G.round(D, 1), src = "ring" } break end
		end
		if best then out[#out + 1] = best end
	end
	return out
end

local function copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = copy(x) end
	return t
end

--- A style table for the metropolis: a copy of `style` (the cached site / saved style) with the variant applied.
--- d = M.decide result; o = { cap, sampler, forcedCentres = bool }. Sets style.metro = { variant, centres, why,
--- forced, band } and returns the new table (the input is not changed).
function M.apply(style, d, o)
	o = o or {}
	local s = {}
	for k, v in pairs(style) do s[k] = v end
	-- (fields the variant changes are copied; the rest is shared with the cached style)
	s.templates = copy(style.templates)
	s.block = copy(style.block)
	s.radial = copy(style.radial)
	s.shape = copy(style.shape)
	s._outerCache = nil
	local v = d.variant
	-- road mix: arterials large (JP keeps a step narrower), collectors medium; the late hierarchy (wide streets only
	-- on through pieces that meet another street, ot_core.hierarchy) and the straight-wide rule apply
	if s.id == "JP_DENSE" then
		s.templates.main, s.templates.medium = "medium", "small"
	else
		s.templates.main, s.templates.medium = "large", "medium"
		if s.templates.small == "xsmall" then s.templates.small = "small" end
	end
	s.hierarchy = "late"
	s.templatePaths = {}
	for _, c in ipairs(ST.CLASSES) do s.templatePaths[c] = ST.templatePath(s.templates[c], s.newTemplates) end
	local sh = s.shape
	local form = style.form and style.form.id or nil
	local metro = { variant = v, why = d.why, forced = d.forced == true, centres = {}, form = form }
	local function compact()
		if sh then
			sh.id, sh.arms, sh.strip, sh.second, sh.seconds, sh.reach = "compact", nil, nil, nil, nil, 1
			sh.reason = "metropolis " .. v
		end
	end
	-- shore towns (2026-10-12): a shore metropolis keeps growing along its shore (grid, radial, corridor)
	local function keepShore()
		if sh and sh.id == "shore" and sh.shore then
			sh.reach, sh.strong, sh.second, sh.seconds, sh.strip = 1, true, nil, nil, nil
			sh.reason = "metropolis " .. v .. " shore"
			return true
		end
		return false
	end
	if v == "grid" then
		-- town form: a linear / wide grid metropolis keeps that outline, else compact
		if keepShore() then
			-- (along the shore)
		elseif sh and form and (form == "linear" or form == "wide") then
			sh.id = form == "linear" and "linear" or "lens"
			sh.reach, sh.strong, sh.second, sh.seconds = 1, true, nil, nil
			sh.arms = sh.id == "linear" and { sh.axis, G.wrap(sh.axis + math.pi) } or nil
			sh.reason = "metropolis grid " .. form
		else
			compact()
		end
		if s.grower ~= "organic" then
			s.arterialEvery = math.min(s.arterialEvery > 0 and s.arterialEvery or 4, 4)
			s.collectorEvery = 2
		end
	elseif v == "radial" then
		if s.radial then
			s.radial.spokes = math.max(s.radial.spokes, 8)
			s.radial.ringEvery = math.min(s.radial.ringEvery or 300, 250)
		end
		-- town form (ot_form): a radiating / fingers / linear radial metropolis grows fingers along its spokes
		if keepShore() then
			-- (along the shore)
		elseif sh and form and (form == "radiating" or form == "fingers" or form == "linear") and s.grower == "organic" then
			sh.id, sh.reach, sh.strong, sh.strip = "fingers", 1, true, true
			sh.second, sh.seconds = nil, nil
			local th = SH.spokeHeadings(s)
			sh.arms = th or sh.arms
			if th then sh.axis = th[1] end
			sh.reason = "metropolis radial " .. form
		else
			compact()
		end
	elseif v == "corridor" then
		-- (on a coast / lake with a traced shoreline: the corridor follows the shore's curve)
		if not keepShore() and sh and s.shoreFront and s.shoreFront.sd then
			sh.id, sh.shore, sh.reach, sh.strong, sh.strip = "shore", s.shoreFront.sd, 1, true, nil
			sh.axis = s.shoreFront.sd.axis
			sh.arms = { sh.axis, G.wrap(sh.axis + math.pi) }
			sh.second, sh.seconds = nil, nil
			sh.reason = "metropolis corridor shore"
		elseif sh and sh.id ~= "shore" then
			sh.id, sh.reach, sh.strong = "linear", 1, true
			sh.arms = { sh.axis, G.wrap(sh.axis + math.pi) }
			sh.strip = s.grower == "organic" or nil
			sh.second, sh.seconds = nil, nil
			sh.reason = "metropolis corridor"
		end
		metro.band = M.CORRIDOR_BAND * math.max(s.block.len, s.block.depth)
	elseif v == "oldcore" then
		compact()
		if s.outer == nil then
			local gridId = (s.region == "MED" and "MED_ENSANCHE") or ((s.region == "US" or s.region == "OCEANIA") and "NA_GRID")
				or "EU_EXTENSION"
			-- (a town that already is an extension grid gets the strict ensanche blocks outside)
			if gridId == s.id then gridId = s.id == "MED_ENSANCHE" and "NA_GRID" or "MED_ENSANCHE" end
			s.outer = { id = gridId, from = math.max(250, s.radius or 0) }
		end
	elseif v == "polycentric" then
		local n = M.centreCount(o.cap, o.forcedCentres)
		local axis = (sh and sh.axis) or s.axis or 0
		-- (forced centres while the town is still small: nearer, POLY_D_FORCED)
		local range = (o.forcedCentres and (o.cap or 0) < M.POLY_MIN_CAP) and M.POLY_D_FORCED or nil
		metro.centres = n > 0 and M.centres(s.centre, axis, n, s.seed, o.sampler, range,
			s.roads and s.roads.junctions or nil) or {}
		-- per-centre core style (later-ideas phase, ot_poly): a small grid core or the plan's own pattern, seeded
		for k, cc in ipairs(metro.centres) do cc.core = M.coreKind(s, k) end
		if sh and #metro.centres > 0 then
			sh.id, sh.reach, sh.arms, sh.strip = "twin", 1, nil, nil
			sh.second = { metro.centres[1][1], metro.centres[1][2] }
			sh.D = metro.centres[1][3]
			sh.seconds = metro.centres
			sh.reason = "metropolis polycentric"
		else
			compact()
		end
	end
	-- Showcase v9 round: the metropolis keeps its own mechanics (lock, increments, fill: ot_driver), not the style's
	-- smaller copy of them (style.mech); the housed front only for polycentric (user: "too many empty streets built out
	-- before town growth": the arterial grid toward the secondary centre ran ~3-4 km ahead of the houses); one park
	-- is a crescent (ot_crescent)
	s.mech = nil
	s.housedLead = v == "polycentric" and M.POLY_HOUSED or nil
	s.emptyBudget = v == "polycentric" and M.POLY_EMPTY or nil
	s.crescents = M.CRESCENT_PARKS
	-- parks: green reserves the plan grows around (ot_select.inGreen; enclosed open land, not every block filled)
	s.greens = ST.greenReserves(s, M.PARKS)
	s.metro = metro
	return s
end

-- per-centre core style (later-ideas phase): share of secondary centres with a small grid core of their own (else the
-- plan's own pattern), by the map's region
M.CORE_GRID = { US = 0.75, OCEANIA = 0.7, JP = 0.6, EAST_ASIA = 0.6, ASIA = 0.45, RU = 0.5, EU = 0.35, MED = 0.45, NORDIC = 0.3,
	MIXED = 0.45 }
M.CORE_GRID_DEFAULT = 0.45

--- Core kind of secondary centre k: "grid" | "plan" (seeded per town and centre).
function M.coreKind(style, k)
	local p = M.CORE_GRID[style.region or ""] or M.CORE_GRID_DEFAULT
	-- (a grid style's centres are grids anyway: their own core keeps the town's pattern)
	if style.grower ~= "organic" then p = p * 0.5 end
	return rng.decide(style.drawV, style.seed or 1, "polyCore", k) < p and "grid" or "plan"
end

--- Is (x, y) within CENTRE_R of the main centre or a secondary centre? Returns the centre index (0 = main) or nil.
function M.centreAt(style, x, y)
	local c = style.centre
	if G.dist(c[1], c[2], x, y) <= M.CENTRE_R then return 0 end
	for i, s in ipairs((style.metro and style.metro.centres) or {}) do
		if G.dist(s[1], s[2], x, y) <= M.CENTRE_R then return i end
	end
	return nil
end

--- Distance of (x, y) from the corridor spine (the shape axis through the centre), m.
local function corridorDist(style, x, y)
	local sh = style.shape
	-- (a corridor along the shore: the band is the distance from the traced shoreline)
	if sh and sh.id == "shore" and sh.shore then
		local _, perp = SH.shoreAt(sh.shore, x, y)
		return perp
	end
	local a = (sh and sh.axis) or style.axis or 0
	local dx, dy = x - style.centre[1], y - style.centre[2]
	return math.abs(-dx * math.sin(a) + dy * math.cos(a))
end

--- Plan edges of an increment to lock for the metropolis variant: { [key] = true }, n. inc edges carry key, class,
--- p0, p1. grid / oldcore: none; radial: main / medium pieces; corridor: edges outside the band; polycentric: edges
--- outside every centre's disc (between the centres).
function M.lockKeys(style, inc)
	local m = style.metro
	if m == nil or inc == nil then return nil, 0 end
	local keys, n = {}, 0
	for _, e in ipairs(inc.edges or {}) do
		local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
		local lock = false
		if M.LOCK_ALL then lock = true
		elseif m.variant == "radial" then lock = e.class == "main" or e.class == "medium"
		elseif m.variant == "corridor" then lock = corridorDist(style, mx, my) > (m.band or 250)
		elseif m.variant == "polycentric" then lock = #m.centres > 0 and M.centreAt(style, mx, my) == nil end
		if lock and e.key ~= nil and not keys[e.key] then
			keys[e.key] = true
			n = n + 1
		end
	end
	if n == 0 then return nil, 0 end
	return keys, n
end

--- Which of a build's edges the metropolis fill may use, in order: list of edges (p0, p1). grid: all; radial /
--- oldcore: nearest the centre first; corridor: inside the band; polycentric: within a centre's disc (none between).
function M.fillEdges(style, edges)
	local m = style.metro
	if m == nil then return edges end
	local out = {}
	for _, e in ipairs(edges or {}) do
		local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
		local take = true
		if m.variant == "corridor" then take = corridorDist(style, mx, my) <= (m.band or 250)
		elseif m.variant == "polycentric" then take = M.centreAt(style, mx, my) ~= nil end
		if take then out[#out + 1] = { e = e, d = G.dist(style.centre[1], style.centre[2], mx, my) } end
	end
	if m.variant == "radial" or m.variant == "oldcore" then
		table.sort(out, function(a, b) return a.d < b.d end)
	end
	local list = {}
	for i, x in ipairs(out) do list[i] = x.e end
	return list
end

--- Density per centre for the METRO line: buildings within CENTRE_R of each centre (main first) per hectare, and
--- of the rest within the town radius r. pts = { {x, y} }. Returns { centres = { n/ha ... }, between = n/ha,
--- counts = { ... }, rest = n }.
function M.density(style, pts, r)
	local cs = { style.centre }
	for _, c in ipairs((style.metro and style.metro.centres) or {}) do cs[#cs + 1] = c end
	local counts, rest = {}, 0
	for i = 1, #cs do counts[i] = 0 end
	for _, p in ipairs(pts or {}) do
		local hit = false
		for i, c in ipairs(cs) do
			if G.dist(c[1], c[2], p[1], p[2]) <= M.CENTRE_R then counts[i] = counts[i] + 1; hit = true break end
		end
		if not hit then rest = rest + 1 end
	end
	local ha = math.pi * M.CENTRE_R * M.CENTRE_R / 10000
	local dens = {}
	for i = 1, #cs do dens[i] = counts[i] / ha end
	-- (the town disc reaches at least past every centre's disc: Showcase v7 logged between=504 "per ha" when the
	-- building radius was smaller than the two discs together and the area fell to the 1 ha floor)
	local rr = r or 0
	for i = 2, #cs do rr = math.max(rr, G.dist(cs[1][1], cs[1][2], cs[i][1], cs[i][2]) + M.CENTRE_R) end
	rr = math.max(rr, M.CENTRE_R * 1.5)
	local area = math.max(1, math.pi * rr * rr / 10000 - #cs * ha)
	return { centres = dens, between = rest / area, counts = counts, rest = rest }
end

--- "core:12.3/c1:4.0 between=1.2" for the log.
function M.densityText(d)
	local parts = {}
	for i, v in ipairs(d.centres) do parts[i] = string.format("%s:%.1f", i == 1 and "core" or ("c" .. (i - 1)), v) end
	return table.concat(parts, "/"), string.format("%.2f", d.between)
end

return M
