-- Organic Towns: more terrain motifs (pure). Phase M4 of the motifs plan (plans/square_organic_towns/MOTIFS_BRIEF.md,
-- 2026-10-13). Registered into the ot_motif registry by ot_motif (RL.registerAll(MO)), MO.IDS 14-17.
--
--   switchbacks         (drawn, group land) on a slope too steep for the hill climb's gentle street: a street zigzagging
--                       up beside the town in legs along the slope (each about 6 %, traced with L.traceClimb), joined by
--                       hairpin bends (a circular arc of HAIRPIN_R >= ot_plan.MIN_RADIUS, two plan pieces split at the
--                       apex; a bend is placed only where its ground stays within maxSlope, else the leg is shortened
--                       or the climb stops), houses at the bends (the build's DevelopAt dose there), the slopes between
--                       the legs left green (no plan pieces in the zigzag's zone beyond the core).
--   ridge_street        (drawn, group land) a street along the crest (L-style trace keeping the highest ground within a
--                       turn limit of the crest axis, ot_terrain.dirRelief ridge), houses both sides, short dead-end spurs
--                       down the flanks only where the flank is gentle, no other streets on the flanks beyond the core.
--   headland_street     (drawn, group shore) a street along the top of a cliff above the sea, BRINK_OFF m inland of the
--                       cliff's brink (the brink traced along the coast: where the ground drops CLIFF_DROP per 20 m toward
--                       the water), short dead-end lanes inland, houses on the inland side facing the water (dose), nothing
--                       between the street and the cliff edge.
--   bridgehead_quarter  (derived, extra: no motif slot) a small straight grid on the far bank of the town's river bridge
--                       (ot_bridge), squared to the bridge, its first row the bridge's cross street continued straight on
--                       from its two dead ends; present only once the bridge is built (the frame's `br` flag or this
--                       session's build: style.bridge, the driver's bridgeRefresh), the bridge found in the snapshot
--                       (a street edge over water, ends on land) or from the session's bridge plan.
--
-- Each kind's pieces are plain plan pieces (L.overlay / L.layMain: motif, costK, motifLead) through the normal planner:
-- housed front, lead limit, own empty budget, map edge, water / grade checks, the crash rule unchanged. Dead-end branches
-- (spurs, lanes) carry motifWait (ot_select branchOk, the M3 rule; dropped by the M4 give-up when their line's next piece
-- keeps being refused). Classes small / medium only. Geometry from stable data (centre, terrain, seed, the bridge).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local L = ug_require "square_organic_towns::/organic_towns/ot_motif_land.lua"
local RM = ug_require "square_organic_towns::/organic_towns/ot_motif_road.lua"
local TW = ug_require "square_organic_towns::/organic_towns/ot_motif_town.lua"

local M = {}

local sqrt, cos, sin, abs, floor, max, min = math.sqrt, math.cos, math.sin, math.abs, math.floor, math.max, math.min

M.ON = true   -- (off in the other offline tests: their baselines were measured without M4; tests F.withReliefMotifs)

-- switchbacks
M.SB = {
	-- the town's relief grade: eligibility 0 .. 1 over these (0.065 .. 0.10 until the 2026-10-13 final test: real hilly
	-- EU towns read 0.01-0.05; the hill climb's is full at 0.035)
	GRADE = { 0.04, 0.07 },
	RANGE = { 25, 40 },        -- m of height range in the 600 m disc: x 0 .. 1 from RANGE[1] over RANGE[2] m
	STEEP_MAX = 1.35,          -- x maxSlope: steeper relief has no legal bend anywhere (0)
	LEG = { 2.8, 180, 280 },   -- leg length beyond the first: x block length, clamped (m)
	TARGET = 0.05,             -- leg grade (x 0.6 maxSlope at most): legs near the contour, the bends doing the climbing
	DEV = math.rad(60),        -- a leg's heading within this of its contour direction
	TURN = math.rad(15),       -- per trace step
	FIRST = math.rad(8),       -- the first step of a leg after a bend
	STEP = 30,
	R = 80,                    -- m: the bend's radius (ot_plan.MIN_RADIUS 70)
	BEND_GRADE = 0.97,         -- x maxSlope: the bend's steepest 10 m at most
	AHEAD = 1.5,               -- a leg traced this x its length: its bend at the end nearest its length whose ground fits
	BACK = { 10, 0.4 },        -- ... but not before this x its length (leg 0: never inside the town)
	BENDS = { 2, 4 },          -- bends wanted (seeded)
	ZONE = 1.15,               -- x R: the zigzag's zone (plan pieces dropped beyond the core)
	MAX_EXT = 1600,            -- m from the centre at most
}
-- ridge street
M.RS = {
	STEP = 40,
	HALF = 650,                -- m each way from the centre at most
	DEV = math.rad(40),
	TURN = math.rad(20),
	SIDE = 80,                 -- m: the crest test: both sides this far out ...
	DROP = 2,                  -- ... at least this much lower (else the crest ended)
	SP = { 1.4, 80, 140 },     -- spur spacing: x block length, clamped
	SPUR = { 1.6, 50, 110 },   -- spur length at most: x block depth, clamped
	SPUR_MIN = 40,
	SPUR_GRADE = 0.7,          -- x maxSlope: a spur stops where the flank is steeper
	ZONE = 40,                 -- m beyond the longest spur: the flank zone (plan pieces dropped beyond the core)
}
-- headland street
M.HL = {
	CLIFF_H = { 6, 20 },       -- m above the water at the brink: eligibility 0 .. 1 (10 .. 30 until the final test)
	REACH = 700,               -- m: the brink this near the centre at most (the brink: ot_terrain CLIFF_DROP / PROBE;
	                           -- 550 until the final test: coast towns sit 250-575 m from the water)
	NEAR = 300,                -- m: full eligibility up to this brink distance
	STEP = 40,
	HALF = 650,
	SEARCH = { 90, 140 },      -- m inland / seaward of a step's point searched for the brink
	TURN = math.rad(40),       -- per step at most
	DEV = math.rad(110),       -- from the first tangent at most
	MARGIN = 15,               -- m beyond waterSetback (>= 25): the street's distance inland of the brink
	LANE_SP = { 1.0, 55, 90 },
	LANE = { 1.2, 50, 100 },
	LANE_MIN = 35,
	SEA_ZONE = 70,             -- m beyond the street toward the sea: no plan pieces
}
-- bridgehead quarter
M.BH = {
	ROWS = { 3, 4 },           -- blocks away from the river (seeded)
	COLS = 4,                  -- blocks along the cross street (even: the bridge's far street meets the middle line)
	DEP = { 1.0, 45, 80 },     -- block depth: x block depth, clamped
	LEN = 55,                  -- m along the cross street (ot_bridge CROSS: the cross street's dead ends are junctions)
	FOLLOW = 220,              -- m: from the bridge's far end along its far street to the cross street at most
	GRADE = 0.8,
	ROAD = 18,
}

local function blk(style) return L.blk(style) end
local function unit(x, y)
	local l = sqrt(x * x + y * y)
	if l < 1e-9 then return 0, 0, 0 end
	return x / l, y / l, l
end

local function hairpinKeys(mp, prefix, i) return prefix .. ":H" .. i .. "a", prefix .. ":H" .. i .. "m", prefix .. ":H" .. i .. "b" end

---------------------------------------------------------------------------
-- switchbacks

--- A bend from (x, y) heading h toward uphill bearing b, radius R: its points (with tangents), the apex point, the exit
--- heading (h mirrored about b) and the turn's sign; nil when the leg runs (almost) straight up / down.
function M.bend(x, y, h, b, R)
	local h2 = G.wrap(2 * b - h)
	local turn = G.wrap(h2 - h)
	-- (the bend turns toward the uphill side: through b)
	local sg = sin(b - h) >= 0 and 1 or -1
	local delta = abs(turn)
	if (turn > 0 and sg < 0) or (turn < 0 and sg > 0) then delta = 2 * math.pi - delta end
	if delta < math.rad(60) or delta > math.rad(200) then return nil end
	local chord = 2 * R * sin(delta / 2)
	local ch = h + sg * delta / 2
	local bx, by = x + cos(ch) * chord, y + sin(ch) * chord
	local pts = L.arc(x, y, h, bx, by, sg * delta / 2)
	-- apex: half way round
	local cx, cy = x - sin(h) * R * sg, y + cos(h) * R * sg
	local a0 = G.atan2(y - cy, x - cx)
	local am = a0 + sg * delta / 2
	return { pts = pts, apex = { cx + R * cos(am), cy + R * sin(am) }, centre = { cx, cy }, h2 = h2, sg = sg,
		delta = delta, len = R * delta, x1 = bx, y1 = by }
end

local function legTrace(sampler, x, y, bearing, len, o, first)
	local sb = M.SB
	local raw, why = L.traceClimb(sampler, x, y, bearing, { maxLen = len, extent = o.extent, maxGrade = o.maxGrade,
		grade = o.grade, setback = o.setback, style = o.style, side = 1, dev = sb.DEV, turn = sb.TURN,
		firstTurn = first and sb.DEV or sb.FIRST, step = sb.STEP, noTop = true })
	return raw, why
end

--- The switchbacks' plan geometry (pure): { line, ix, legs = { { s0, s1 } }, bends = { { s0, sm, s1, apex, centre, R } },
--- bearing, climb, grade, stop, r0, zone } or nil, why.
function M.switchGeo(style, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local sb = M.SB
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local bearing = L.uphill(sampler, cx, cy, seed)
	if bearing == nil then return nil, "flat" end
	local maxSlope = style.maxSlope or 0.1
	local b = blk(style)
	local r = max(style.radius or 0, b)
	local legLen = L.clampSpec(sb.LEG, style.block and style.block.len or 80)
	local side = rng.unit(seed, "msbSide") < 0.5 and 1 or -1
	local nWant = sb.BENDS[1] + floor(rng.unit(seed, "msbN") * (sb.BENDS[2] - sb.BENDS[1] + 1))
	local o = { extent = min(extent or 1500, sb.MAX_EXT), maxGrade = maxSlope * 0.9, grade = min(sb.TARGET, 0.6 * maxSlope),
		setback = style.waterSetback or 25, style = style }
	local R = sb.R
	local line, legs, bends = {}, {}, {}
	local function append(pts, skipFirst)
		for i, p in ipairs(pts) do
			if not (skipFirst and i == 1) then line[#line + 1] = { p[1], p[2] } end
		end
	end
	local function cum()
		if #line < 2 then return 0 end
		return G.polyLen(line)
	end
	-- leg 0: from the centre along the contour (one side), out of the town and LEG beyond
	local h = G.wrap(bearing + side * math.pi / 2)
	local x, y = cx, cy
	local stop = "bends"
	local first = true
	for leg = 0, nWant do
		local len = leg == 0 and (r + legLen) or legLen
		-- (traced longer: the bend may come a little beyond the leg's length where the ground there fits it better)
		local raw, why = legTrace(sampler, x, y, h, len * sb.AHEAD, o, first)
		if #raw < 3 then stop = "leg:" .. tostring(why); break end
		local sm = L.smooth(raw, 120) or raw
		local pts = G.resample(sm, 10)
		local cumP = { 0 }
		for i = 2, #pts do cumP[i] = cumP[i - 1] + G.dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
		local function cutAt(k)
			local kept = {}
			for i = 1, k do kept[i] = { pts[i][1], pts[i][2] } end
			return kept
		end
		local kLen = #pts
		for i = 1, #pts do if cumP[i] <= len + 1e-6 then kLen = i end end
		-- the bend: the leg's end nearest its length whose bend's ground fits (within maxSlope), clear of water, the map
		-- edge and the legs below; leg 0 never bends inside the town
		local bend = nil
		if leg < nWant then
			local sMin = leg == 0 and (r + 40) or sb.BACK[2] * len
			local cands = {}
			for k = 3, #pts do if cumP[k] >= sMin then cands[#cands + 1] = k end end
			table.sort(cands, function(p, q)
				local dp, dq = abs(cumP[p] - len), abs(cumP[q] - len)
				if dp ~= dq then return dp < dq end
				return p < q
			end)
			local ix0 = #line >= 2 and L.index(line) or nil
			for _, k in ipairs(cands) do
				local p, q = pts[k - 1], pts[k]
				local hh = G.heading(p[1], p[2], q[1], q[2])
				local bd = M.bend(q[1], q[2], hh, bearing, R)
				if bd then
					local okB = T.pathMaxGrade(sampler, bd.pts, 10) <= sb.BEND_GRADE * maxSlope
						and not T.wetAlong(sampler, bd.pts, o.setback)
					if okB then
						for _, pp in ipairs(bd.pts) do
							if L.offEdge(style, pp[1], pp[2]) or G.dist(cx, cy, pp[1], pp[2]) > o.extent then okB = false; break end
						end
					end
					-- (clear of the earlier legs: the bend must not reach back onto the line below)
					if okB and ix0 then
						for i = 2, #bd.pts do
							local pp = bd.pts[i]
							if L.nearest(ix0, pp[1], pp[2], R * 0.9) then okB = false; break end
						end
					end
					if okB then
						bend = bd
						sm = cutAt(k)
						break
					end
				end
			end
			if bend == nil then stop = "bend:steep" end
		end
		if bend == nil then sm = cutAt(kLen) end
		-- (a leg shorter than a block after cutting back: stop before it)
		if leg > 0 and G.polyLen(sm) < 60 then stop = "leg:short"; break end
		local s0 = cum()
		append(sm, #line > 0)
		legs[#legs + 1] = { s0 = s0, s1 = cum() }
		if bend == nil then break end
		local sA = cum()
		append(bend.pts, true)
		local sB = cum()
		bends[#bends + 1] = { s0 = sA, sm = sA + (sB - sA) / 2, s1 = sB, apex = bend.apex, centre = bend.centre, R = R,
			delta = bend.delta }
		x, y, h = bend.x1, bend.y1, bend.h2
		first = false
	end
	if #bends == 0 then return nil, "noBend:" .. stop end
	-- (the last leg after the last bend is required: a bend never ends the street)
	if legs[#legs].s0 < bends[#bends].s1 - 1 then
		-- the climb ended right after a bend: drop that bend
		local bnd = table.remove(bends)
		local keep = {}
		local cumL = 0
		keep[1] = line[1]
		for i = 2, #line do
			cumL = cumL + G.dist(line[i - 1][1], line[i - 1][2], line[i][1], line[i][2])
			if cumL <= bnd.s0 + 1e-6 then keep[#keep + 1] = line[i] end
		end
		line = keep
		if #bends == 0 then return nil, "noBend:" .. stop end
	end
	local ix = L.index(line)
	local z0, zmax = T.height(sampler, cx, cy), -math.huge
	for _, p in ipairs(G.resample(line, 20)) do
		local z = T.height(sampler, p[1], p[2])
		if z > zmax then zmax = z end
	end
	return { line = line, ix = ix, legs = legs, bends = bends, bearing = bearing, side = side, climb = zmax - z0,
		grade = T.pathMaxGrade(sampler, line, 10), stop = stop, want = nWant, r0 = L.dropFrom(style), zone = sb.ZONE * R,
		legLen = legLen }
end

local function switchPlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.switchGeo(style, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local cx, cy = style.centre[1], style.centre[2]
	local stops = {}
	for i, bd in ipairs(geo.bends) do
		local ka, km, kb = hairpinKeys(mp, "msb", i)
		stops[#stops + 1] = { s = bd.s0, key = ka }
		stops[#stops + 1] = { s = bd.sm, key = km }
		stops[#stops + 1] = { s = bd.s1, key = kb }
	end
	local r0 = geo.r0
	local function drop(x, y)
		if G.dist(cx, cy, x, y) < r0 then return false end
		return L.nearest(geo.ix, x, y, geo.zone) ~= nil
	end
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "msb", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = m.id, class = "small", costK = L.COST_MAIN, lead = true,
		every = 80, stops = stops, part = "zigzag", mid = 0, drop = drop }, anchors)
	-- (the bends' pieces: tagged for the measure / dose)
	for _, pc in ipairs(mp.pieces) do
		if pc.motifLine == "msb" and pc.motifS0 then
			for _, bd in ipairs(geo.bends) do
				if pc.motifS0 >= bd.s0 - 0.5 and pc.motifS1 <= bd.s1 + 0.5 then pc.motifPart = "bend" end
			end
		end
	end
	geo.anchors, geo.links = res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function bendBuilt(g, ix, bd)
	local n = 0
	for _, f in ipairs({ 0.25, 0.75 }) do
		local s = bd.s0 + f * (bd.s1 - bd.s0)
		local x, y = L.at(ix, s)
		local d = g and OG.distToEdges(g, x, y, 12)
		if d then n = n + 1 end
	end
	return n == 2
end

local function switchMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 10)
	local bends = 0
	for _, bd in ipairs(geo.bends) do if bendBuilt(env.g, geo.ix, bd) then bends = bends + 1 end end
	local climb = 0
	if env.sampler then
		local z0 = T.height(env.sampler, geo.line[1][1], geo.line[1][2])
		for _, sp in ipairs(spans) do
			local x, y = L.at(geo.ix, sp[2])
			climb = max(climb, T.height(env.sampler, x, y) - z0)
		end
	end
	local atBends = 0
	for _, p in ipairs(env.pts or {}) do
		for _, bd in ipairs(geo.bends) do
			if G.dist(p[1], p[2], bd.centre[1], bd.centre[2]) <= bd.R + 45 then atBends = atBends + 1; break end
		end
	end
	return { edges = L.incEdges(env.inc, "msb"), total = n, houses = L.housesAlong(env.pts, geo.ix, spans, 45), len = len,
		bends = bends, climb = climb, atBends = atBends,
		text = string.format("len=%.0f/%.0f,bends=%d/%d(want %d),R=%.0f,climb=%.0f/%.0f,grade=%.3f,legs=%d,leg=%.0f,stop=%s,"
			.. "atBends=%d,anchors=%d/%d", len, geo.ix.len, bends, #geo.bends, geo.want, M.SB.R, climb, geo.climb, geo.grade,
			#geo.legs, geo.legLen, geo.stop, atBends, geo.anchors or 0, geo.links or 0) }
end

local function switchEligible(ctx)
	if not M.ON then return 0, "off" end
	local t = ctx.terrain
	if t == nil or t.relief == nil then return 0, "noTerrain" end
	local st = ctx.style
	if st.metro then return 0, "metro" end
	-- (a crest town: its ridge street; the centre is the top, no climb)
	if L.ridgeScore(t.dirRelief) > 0.3 then return 0, "ridge" end
	local g = t.relief.grade
	local maxSlope = st.maxSlope or 0.1
	if g > M.SB.STEEP_MAX * maxSlope then return 0, string.format("tooSteep:grade=%.3f", g) end
	local s = G.clamp((g - M.SB.GRADE[1]) / (M.SB.GRADE[2] - M.SB.GRADE[1]), 0, 1)
	local range = (t.highZ or 0) - (t.lowZ or 0)
	s = s * G.clamp((range - M.SB.RANGE[1]) / M.SB.RANGE[2], 0, 1)
	if (ctx.tier or 2) >= 4 then s = s * 0.5 end
	s = s * L.styleK(st)
	local why = string.format("steep:grade=%.3f,range=%.0f,max=%.2f", g, range, maxSlope)
	if s <= 0 then return 0, why end
	return s, why
end

--- DevelopAt points at the build's bends: beside each new bend edge, inside and outside the curve in turn.
local function switchDose(m, edges, off, n)
	local out = {}
	local geo = m.geo
	if geo == nil then return out end
	local k = 0
	for _, e in ipairs(edges or {}) do
		if e.p0 and e.p1 and #out < n then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			for _, bd in ipairs(geo.bends) do
				local d = G.dist(mx, my, bd.centre[1], bd.centre[2])
				if abs(d - bd.R) < 15 then
					k = k + 1
					local ux, uy = unit(mx - bd.centre[1], my - bd.centre[2])
					local sg = (k % 2 == 1) and 1 or -1
					out[#out + 1] = { G.round(mx + ux * off * sg, 1), G.round(my + uy * off * sg, 1) }
					break
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- ridge street

--- The crest through (cx, cy) along axis, both ways: each step the highest heading within TURN of the last (DEV of the
--- axis), stopping at water, the map edge, the extent, HALF m, a step steeper than maxGrade, or where the crest ends
--- (both sides SIDE m out no longer DROP m lower). Returns raw points (through the centre), the centre's index, stops.
function M.traceCrest(sampler, cx, cy, axis, o)
	local rs = M.RS
	local halves, whys = {}, {}
	for hs = 1, 2 do
		local dir = hs == 1 and axis or axis + math.pi
		local pts = {}
		local x, y, h = cx, cy, dir
		local z = T.height(sampler, x, y)
		local why = "len"
		for _ = 1, floor(o.half / rs.STEP) do
			local best, bz, bh = nil, -math.huge, nil
			for k = -4, 4 do
				local hh = h + k * rs.TURN / 4
				if G.angleDiff(hh, dir) <= rs.DEV then
					local nx, ny = x + cos(hh) * rs.STEP, y + sin(hh) * rs.STEP
					if not L.wetNear(sampler, nx, ny, o.setback) and not L.offEdge(o.style, nx, ny)
						and G.dist(cx, cy, nx, ny) <= o.extent then
						local nz = T.height(sampler, nx, ny) - abs(k) * 0.05
						if nz > bz then best, bz, bh = { nx, ny }, nz, hh end
					end
				end
			end
			if best == nil then why = "edge"; break end
			local zz = T.height(sampler, best[1], best[2])
			if abs(zz - z) / rs.STEP > o.maxGrade then why = "steep"; break end
			local px, py = -sin(bh), cos(bh)
			local za = T.height(sampler, best[1] + px * rs.SIDE, best[2] + py * rs.SIDE)
			local zb = T.height(sampler, best[1] - px * rs.SIDE, best[2] - py * rs.SIDE)
			if zz - za < rs.DROP or zz - zb < rs.DROP then why = "crestEnd"; break end
			pts[#pts + 1] = best
			x, y, z, h = best[1], best[2], zz, bh
		end
		halves[hs], whys[hs] = pts, why
	end
	local raw = {}
	for i = #halves[2], 1, -1 do raw[#raw + 1] = halves[2][i] end
	raw[#raw + 1] = { cx, cy }
	for _, p in ipairs(halves[1]) do raw[#raw + 1] = p end
	return raw, #halves[2], #halves[1], whys[1] .. "/" .. whys[2]
end

--- The ridge street's plan geometry (pure): { line, ix, sc (the centre's arc length), r0, spurs = { { s, side, x0, y0, x1,
--- y1, len } }, sp, spurMax, stop } or nil, why.
function M.ridgeGeo(style, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local cx, cy = style.centre[1], style.centre[2]
	local dr = T.dirRelief(sampler, cx, cy, 600)
	if dr == nil or L.ridgeScore(dr) <= 0 then return nil, "noRidge" end
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	local raw, nb, na, stop = M.traceCrest(sampler, cx, cy, dr.axis, { half = M.RS.HALF, extent = extent or 1500,
		setback = setback, style = style, maxGrade = maxSlope * 0.8 })
	if nb + na < 4 then return nil, "short:" .. stop end
	local line = L.smooth(raw, 150)
	if line == nil then return nil, "short:" .. stop end
	local ix = L.index(line)
	local _, sc = L.nearest(ix, cx, cy, 200)
	sc = sc or ix.len / 2
	local r0 = L.dropFrom(style)
	local sp = L.clampSpec(M.RS.SP, style.block and style.block.len or 80)
	local spurMax = L.clampSpec(M.RS.SPUR, style.block and style.block.depth or 60)
	local sg = M.RS.SPUR_GRADE * maxSlope
	local spurs = {}
	for _, dirS in ipairs({ 1, -1 }) do
		local s = sc + dirS * (r0 + sp * 0.5)
		local guard = G.LOOP_CAP
		while s > 30 and s < ix.len - 30 and guard > 0 do
			guard = guard - 1
			local x, y, ux, uy = L.at(ix, s)
			for _, sd in ipairs({ 1, -1 }) do
				local nx, ny = -uy * sd, ux * sd
				local len, z = 0, T.height(sampler, x, y)
				for d = 10, spurMax, 10 do
					local px, py = x + nx * d, y + ny * d
					if L.wetNear(sampler, px, py, setback) or L.offEdge(style, px, py) then break end
					local pz = T.height(sampler, px, py)
					if abs(pz - z) / 10 > sg then break end
					len, z = d, pz
				end
				if len >= M.RS.SPUR_MIN then
					spurs[#spurs + 1] = { s = s, side = sd, len = len, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len }
				end
			end
			s = s + dirS * sp
		end
	end
	table.sort(spurs, function(p, q) if p.s ~= q.s then return p.s < q.s end return p.side > q.side end)
	return { line = line, ix = ix, sc = sc, r0 = r0, spurs = spurs, sp = sp, spurMax = spurMax, stop = stop, axis = dr.axis,
		zone = spurMax + M.RS.ZONE }
end

local function ridgePlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.ridgeGeo(style, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local cx, cy = style.centre[1], style.centre[2]
	local stops, byS = {}, {}
	for _, sp in ipairs(geo.spurs) do
		local k = string.format("%.0f", sp.s)
		if byS[k] == nil then
			byS[k] = { s = sp.s, key = "mrs:S" .. k }
			stops[#stops + 1] = byS[k]
		end
		sp.key = byS[k].key
	end
	local function drop(x, y)
		if G.dist(cx, cy, x, y) < geo.r0 then return false end
		local d, s = L.nearest(geo.ix, x, y, geo.zone)
		return d ~= nil and abs(s - geo.sc) >= geo.r0
	end
	local anchors = L.anchors(env.g, style, geo.ix, geo.sc, { 1, -1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mrs", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = m.id, class = "medium", costK = L.COST_MAIN, lead = true,
		every = 90, stops = stops, part = "crest", mid = geo.sc, dirs = 2, drop = drop }, anchors)
	local made = 0
	for i, sp in ipairs(geo.spurs) do
		local j = mp.junctions[sp.key]
		if j then
			L.overlay(mp, { { j[1], j[2] }, { sp.x1, sp.y1 } }, { prefix = "mrsS" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = sp.key, deadEnd = true, part = "spur", branch = "start",
				drop = function(x, y, tee) return tee or drop(x, y) end })
			made = made + 1
		end
	end
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == m.id and pc.motifPart == "spur" then pc.motifWait = true end
	end
	geo.made, geo.anchors, geo.links = made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function ridgeMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	-- crest fidelity: the built spine's samples with both sides SIDE m out lower by DROP / 2 at least
	local on, tot = 0, 0
	if env.sampler then
		for _, sp in ipairs(spans) do
			local s = sp[1]
			local guard = G.LOOP_CAP
			while s <= sp[2] and guard > 0 do
				guard = guard - 1
				local x, y, ux, uy = L.at(geo.ix, s)
				local z = T.height(env.sampler, x, y)
				local za = T.height(env.sampler, x - uy * M.RS.SIDE, y + ux * M.RS.SIDE)
				local zb = T.height(env.sampler, x + uy * M.RS.SIDE, y - ux * M.RS.SIDE)
				tot = tot + 1
				if z - za >= M.RS.DROP / 2 and z - zb >= M.RS.DROP / 2 then on = on + 1 end
				s = s + 20
			end
		end
	end
	local spursB = 0
	for _, sp in ipairs(geo.spurs) do
		local mx, my = (sp.x0 + sp.x1) / 2, (sp.y0 + sp.y1) / 2
		if L.segBuilt(env.g, sp.x0, sp.y0, mx, my, 8) then spursB = spursB + 1 end
	end
	local left, right = 0, 0
	for _, p in ipairs(env.pts or {}) do
		local d, _, side = L.nearest(geo.ix, p[1], p[2], 45)
		if d then if side > 0 then left = left + 1 else right = right + 1 end end
	end
	local crest = tot > 0 and on / tot or 0
	return { edges = L.incEdges(env.inc, "mrs"), total = n, houses = left + right, len = len, crest = crest,
		spurs = spursB, left = left, right = right,
		text = string.format("spine=%.0f/%.0f,crest=%.2f,spurs=%d/%d,sides=%d+%d,stop=%s,anchors=%d/%d", len, geo.ix.len,
			crest, spursB, #geo.spurs, left, right, geo.stop, geo.anchors or 0, geo.links or 0) }
end

local function ridgeEligible(ctx)
	if not M.ON then return 0, "off" end
	local t = ctx.terrain
	local dr = t and t.dirRelief
	if dr == nil then return 0, "noRelief" end
	if (t.meanSlope or 0) <= 0.02 then return 0, string.format("flat:slope=%.3f", t.meanSlope or 0) end
	local st = ctx.style
	if st.metro then return 0, "metro" end
	local s = L.ridgeScore(dr) * L.styleK(st)
	local why = string.format("ridge:sides=%.0f/%.0f,level=%.1f", dr.sideA or 0, dr.sideB or 0, dr.level or 0)
	if s <= 0 then return 0, why end
	return s, why
end

---------------------------------------------------------------------------
-- headland street

--- The brink on a line (ot_terrain.brinkOn, M4).
M.brinkOn = T.brinkOn

--- The town's cliff: the stats' (ot_terrain.stats cliff), else toward the stats' water, else the nearest brink of 16 rays.
function M.cliffAt(sampler, t, cx, cy)
	if t and t.cliff then return t.cliff end
	if sampler == nil then return nil end
	if t and t.water then return T.cliff(sampler, cx, cy, t.water.dir) end
	local best = nil
	for k = 0, 15 do
		local c = T.cliff(sampler, cx, cy, k * math.pi / 8)
		if c and (best == nil or c.d < best.d) then best = c end
	end
	return best
end

--- The headland street's plan geometry (pure): { line, ix, brink (polyline), sea (+1: the sea left of travel, -1 right),
--- off, lanes, sMid, stop } or nil, why.
function M.headlandGeo(style, t, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local hl = M.HL
	local cx, cy = style.centre[1], style.centre[2]
	local c = M.cliffAt(sampler, t, cx, cy)
	if c == nil then return nil, "noCliff" end
	extent = extent or 1500
	local setback = max(style.waterSetback or 25, 25)
	local off = setback + hl.MARGIN
	-- the brink both ways along the coast
	local halves, whys = {}, {}
	for hs = 1, 2 do
		local t0 = c.dir + (hs == 1 and 1 or -1) * math.pi / 2
		local tx, ty = cos(t0), sin(t0)
		local px, py = c.x, c.y
		local pts, why = {}, "len"
		local acc = 0
		local guard = G.LOOP_CAP
		while acc < hl.HALF and guard > 0 do
			guard = guard - 1
			local qx, qy = px + tx * hl.STEP, py + ty * hl.STEP
			-- seaward normal: the sea side of the tangent (the cliff's direction)
			local nx, ny = -ty, tx
			if (nx * cos(c.dir) + ny * sin(c.dir)) < 0 then nx, ny = -nx, -ny end
			local bx, by = M.brinkOn(sampler, qx, qy, nx, ny, hl.SEARCH[1], hl.SEARCH[2])
			if bx == nil then why = "noCliff"; break end
			local ux, uy, l = unit(bx - px, by - py)
			if l < 10 then why = "stuck"; break end
			local hh = G.atan2(uy, ux)
			if G.angleDiff(hh, G.atan2(ty, tx)) > hl.TURN then why = "turn"; break end
			if G.angleDiff(hh, t0) > hl.DEV then why = "dev"; break end
			if L.offEdge(style, bx, by) then why = "edge"; break end
			if G.dist(cx, cy, bx, by) > extent then why = "extent"; break end
			pts[#pts + 1] = { bx, by }
			px, py, tx, ty = bx, by, ux, uy
			acc = acc + l
		end
		halves[hs], whys[hs] = pts, why
	end
	local brink = {}
	for i = #halves[2], 1, -1 do brink[#brink + 1] = halves[2][i] end
	brink[#brink + 1] = { c.x, c.y }
	for _, p in ipairs(halves[1]) do brink[#brink + 1] = p end
	if #brink < 4 then return nil, "short:" .. whys[1] .. "/" .. whys[2] end
	-- the street: the brink offset inland (away from the sea) by off, points on steep / wet ground ending a run
	local bdirs = G.polyDirs(brink)
	local function seaSign(i)
		local d = bdirs[i]
		local nx, ny = -d[2], d[1]   -- left of travel
		return (nx * cos(c.dir) + ny * sin(c.dir)) >= 0 and 1 or -1
	end
	local sea = seaSign(#halves[2] + 1)
	local runs, cur = {}, nil
	local maxSlope = style.maxSlope or 0.1
	for i, p in ipairs(brink) do
		local d = bdirs[i]
		local nx, ny = -d[2] * sea, d[1] * sea   -- toward the sea
		local x, y = p[1] - nx * off, p[2] - ny * off
		local good = not T.isWater(sampler, x, y) and T.slope(sampler, x, y, 6) <= maxSlope and not L.offEdge(style, x, y)
		if good then
			cur = cur or {}
			cur[#cur + 1] = { x, y, i }
		elseif cur then
			runs[#runs + 1] = cur
			cur = nil
		end
	end
	if cur then runs[#runs + 1] = cur end
	-- the run through the town's point (the brink's start), else the longest
	local best, bl = nil, -1
	for _, r in ipairs(runs) do
		local hasMid = false
		for _, p in ipairs(r) do if p[3] == #halves[2] + 1 then hasMid = true end end
		local l = #r >= 2 and G.polyLen(r) or 0
		if hasMid then l = l + 1e6 end
		if l > bl then best, bl = r, l end
	end
	if best == nil or #best < 3 then return nil, "noRoom" end
	local raw = {}
	for _, p in ipairs(best) do raw[#raw + 1] = { p[1], p[2] } end
	local line = L.smooth(raw, 120)
	if line == nil or G.polyLen(line) < 150 then return nil, "noRoom" end
	local ix = L.index(line)
	-- the sea side relative to the street's travel
	local _, sMid = L.nearest(ix, cx, cy, 3000)
	sMid = sMid or ix.len / 2
	local mx, my, mux, muy = L.at(ix, sMid)
	local seaL = (-muy * cos(c.dir) + mux * sin(c.dir)) >= 0 and 1 or -1
	-- lanes inland
	local sp = L.clampSpec(hl.LANE_SP, style.block and style.block.len or 80)
	local laneMax = L.clampSpec(hl.LANE, style.block and style.block.depth or 60)
	local lanes = {}
	local s = 30
	local guard = G.LOOP_CAP
	while s <= ix.len - 30 and guard > 0 do
		guard = guard - 1
		local x, y, ux, uy = L.at(ix, s)
		local nx, ny = uy * seaL, -ux * seaL   -- inland: away from the sea
		local len, z = 0, T.height(sampler, x, y)
		for d = 10, laneMax, 10 do
			local px, py = x + nx * d, y + ny * d
			if L.wetNear(sampler, px, py, setback) or L.offEdge(style, px, py) then break end
			local pz = T.height(sampler, px, py)
			if abs(pz - z) / 10 > 0.8 * maxSlope then break end
			len, z = d, pz
		end
		if len >= hl.LANE_MIN then lanes[#lanes + 1] = { s = s, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len, len = len } end
		s = s + sp
	end
	return { line = line, ix = ix, brink = brink, brinkIx = L.index(brink), sea = seaL, off = off, lanes = lanes, sMid = sMid,
		stop = whys[1] .. "/" .. whys[2], cliff = c, laneMax = laneMax, sp = sp }
end

local function headlandPlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.headlandGeo(style, m.terrainStats, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local stops = {}
	for i, ln in ipairs(geo.lanes) do
		ln.key = "mhl:L" .. i
		stops[#stops + 1] = { s = ln.s, key = ln.key }
	end
	local zone = geo.laneMax + 20
	local function hdrop(x, y, tee)
		-- (between the street and the cliff always; inland the lanes' block, but the T's onto the street: the links)
		local d, s, side = L.nearest(geo.ix, x, y, M.HL.SEA_ZONE + geo.off)
		if d and side * geo.sea > 0 then return true end
		d, s, side = L.nearest(geo.ix, x, y, zone)
		if d == nil then return false end
		return not tee and s > 5 and s < geo.ix.len - 5
	end
	local anchors = L.anchors(env.g, style, geo.ix, geo.sMid, { 1, -1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mhl", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = m.id, class = "medium", costK = L.COST_MAIN, lead = true,
		every = 90, stops = stops, part = "clifftop", mid = geo.sMid, dirs = 2, drop = hdrop }, anchors)
	local made = 0
	for i, ln in ipairs(geo.lanes) do
		local j = mp.junctions[ln.key]
		if j then
			L.overlay(mp, { { j[1], j[2] }, { ln.x1, ln.y1 } }, { prefix = "mhlL" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = ln.key, deadEnd = true, part = "lane", branch = "start",
				drop = function(x, y, tee) return tee or hdrop(x, y) end })
			made = made + 1
		end
	end
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == m.id and pc.motifPart == "lane" then pc.motifWait = true end
	end
	geo.made, geo.anchors, geo.links = made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function headlandMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	-- the built street's setback from the brink (min / mean over its 20 m samples)
	local sMin, sSum, k = math.huge, 0, 0
	for _, sp in ipairs(spans) do
		local s = sp[1]
		local guard = G.LOOP_CAP
		while s <= sp[2] and guard > 0 do
			guard = guard - 1
			local x, y = L.at(geo.ix, s)
			local d = L.nearest(geo.brinkIx, x, y, 400) or 400
			sMin, sSum, k = min(sMin, d), sSum + d, k + 1
			s = s + 20
		end
	end
	-- streets between the street and the cliff edge (not along the street)
	local seaward = 0
	local g = env.g
	for _, e in ipairs(g and g.edges or {}) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			local d, _, side = L.nearest(geo.ix, mx, my, geo.off + 30)
			if d and d > 10 and side * geo.sea > 0 then seaward = seaward + 1 end
		end
	end
	local lanes = 0
	for _, ln in ipairs(geo.lanes) do
		local mx, my = (ln.x0 + ln.x1) / 2, (ln.y0 + ln.y1) / 2
		if L.segBuilt(env.g, ln.x0, ln.y0, mx, my, 8) then lanes = lanes + 1 end
	end
	local inland, sea = 0, 0
	for _, p in ipairs(env.pts or {}) do
		local d, _, side = L.nearest(geo.ix, p[1], p[2], 45)
		if d then if side * geo.sea > 0 then sea = sea + 1 else inland = inland + 1 end end
	end
	local mean = k > 0 and sSum / k or 0
	return { edges = L.incEdges(env.inc, "mhl"), total = n, houses = inland + sea, len = len, setbackMin = k > 0 and sMin or 0,
		setbackMean = mean, seaward = seaward, lanes = lanes, inland = inland, seaHouses = sea,
		text = string.format("front=%.0f/%.0f,setback=%.0f..%.0f(plan %.0f),seaward=%d,lanes=%d/%d,houses=%d inland/%d sea,"
			.. "cliff=%.0fm@%.0f,stop=%s,anchors=%d/%d", len, geo.ix.len, k > 0 and sMin or 0, mean, geo.off, seaward, lanes,
			#geo.lanes, inland, sea, geo.cliff.h, geo.cliff.d, geo.stop, geo.anchors or 0, geo.links or 0) }
end

local function headlandEligible(ctx)
	if not M.ON then return 0, "off" end
	local t = ctx.terrain
	if t == nil or t.water == nil or t.water.kind ~= "coast" then return 0, "noCoast" end
	local st = ctx.style
	if st.metro then return 0, "metro" end
	if st.shape and st.shape.id == "shore" then return 0, "shoreTown" end   -- (shore towns: their strip and row)
	local c = t.cliff
	if c == nil then return 0, "noCliff" end
	local hl = M.HL
	local s = G.clamp((c.h - hl.CLIFF_H[1]) / (hl.CLIFF_H[2] - hl.CLIFF_H[1]), 0, 1)
		* G.clamp(1 - (c.d - hl.NEAR) / (hl.REACH - hl.NEAR), 0, 1)
	s = s * L.styleK(st)
	local why = string.format("cliff:h=%.0f,d=%.0f", c.h, c.d)
	if s <= 0 then return 0, why end
	return s, why
end

-- headland style hook: the terrain stats on the record (the plan's cliff search); the promenade (ot_shore) left out (the
-- shore lies at the cliff's foot)
local function headlandStyle(p, m, env)
	m.terrainStats = env.terrain
	if p.shoreFront then
		p.shoreFront = nil
		m.replaced = "shoreFront"
	end
end

--- DevelopAt points on the inland side of the build's clifftop street (the row facing the water).
local function headlandDose(m, edges, off, n)
	local geo = m.geo
	if geo == nil then return {} end
	return RM.doseSide(geo.ix, edges, off, n, -geo.sea)
end

---------------------------------------------------------------------------
-- bridgehead quarter

--- The town's bridge in graph g: { A (near end), B (far end), C (the far street's end: the cross street's junction),
--- heading (A -> B), len } or nil, why. Found from style.bridge.C / heading (this session's plan) when it lies on a node,
--- else the street edge over water with both ends on land (the far end the one farther from the centre).
function M.findBridge(style, g, sampler)
	if g == nil or sampler == nil then return nil, "noGraph" end
	local br = style.bridge or {}
	local cx, cy = style.centre[1], style.centre[2]
	local C, heading = nil, nil
	if br.C and br.heading then
		local nd = OG.nearestNode(g, br.C[1], br.C[2], 10)
		if nd then C, heading = nd, br.heading end
	end
	local A, B = nil, nil
	if C == nil then
		local bestE, bl = nil, -1
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				local l = G.dist(a.x, a.y, b.x, b.y)
				if l >= 12 and T.isWater(sampler, (a.x + b.x) / 2, (a.y + b.y) / 2) and not T.isWater(sampler, a.x, a.y)
					and not T.isWater(sampler, b.x, b.y) and l > bl then
					bestE, bl = e, l
				end
			end
		end
		if bestE == nil then return nil, "noBridgeEdge" end
		A, B = g.nodeById[bestE.n0], g.nodeById[bestE.n1]
		if G.dist(cx, cy, A.x, A.y) > G.dist(cx, cy, B.x, B.y) then A, B = B, A end
		heading = G.heading(A.x, A.y, B.x, B.y)
		-- follow the far street from B (through 2-street nodes) to the cross street's junction
		local prev, cur, acc = A.id, B.id, 0
		local hx, hy = cos(heading), sin(heading)
		local guard = G.LOOP_CAP   -- (a ring of zero-length edges never ends the walk by length)
		while acc < M.BH.FOLLOW and guard > 0 do
			guard = guard - 1
			local nextId = nil
			for _, eid in ipairs(g.adj[cur] or {}) do
				local e = g.edgeById[eid]
				local o = OG.other(e, cur)
				if o ~= prev then
					local on = g.nodeById[o]
					local cn = g.nodeById[cur]
					-- (straight on: away from the river)
					if on and ((on.x - cn.x) * hx + (on.y - cn.y) * hy) > 0.7 * G.dist(on.x, on.y, cn.x, cn.y) then
						nextId = o
					end
				end
			end
			if nextId == nil then break end
			local cn, on = g.nodeById[cur], g.nodeById[nextId]
			acc = acc + G.dist(cn.x, cn.y, on.x, on.y)
			prev, cur = cur, nextId
			if OG.degree(g, cur) ~= 2 then break end
		end
		C = g.nodeById[cur]
		if C == nil or C.id == B.id then return nil, "noFarStreet" end
	end
	return { C = C, heading = heading, A = A, B = B }
end

--- The quarter's plan geometry (pure): { C, f, u, rows, cols, len, dep, J, segs, nOk } or nil, why.
function M.bridgeGeo(style, g, sampler, extent)
	if style.bridge == nil then return nil, "noBridge" end
	if sampler == nil then return nil, "noTerrain" end
	local br, why = M.findBridge(style, g, sampler)
	if br == nil then return nil, why end
	local bh = M.BH
	local cx, cy = style.centre[1], style.centre[2]
	local fx, fy = cos(br.heading), sin(br.heading)
	local ux, uy = -fy, fx
	local ox, oy = br.C.x, br.C.y
	local seed = style.seed or 1
	local rows = bh.ROWS[1] + floor(rng.unit(seed, "mbhRows") * (bh.ROWS[2] - bh.ROWS[1] + 1))
	local cols = bh.COLS
	local dep = L.clampSpec(bh.DEP, style.block and style.block.depth or 60)
	-- (the cross street's half length: its dead ends are the first row's junctions)
	local len = bh.LEN
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	extent = extent or 1500
	local ridx = RM.segIndex(style.roads and style.roads.segs or {})
	local function J(k, j)
		local a = (j - cols / 2) * len
		return ox + fx * k * dep + ux * a, oy + fy * k * dep + uy * a
	end
	local function okSeg(k1, j1, k2, j2)
		-- (the far street's own junction carries 3 streets already: no new street from it)
		if (k1 == 0 and j1 == cols / 2 and k2 ~= 0) or (k2 == 0 and j2 == cols / 2 and k1 ~= 0) then return false end
		local ax, ay = J(k1, j1)
		local bx, by = J(k2, j2)
		local mx, my = (ax + bx) / 2, (ay + by) / 2
		for _, p in ipairs({ { ax, ay }, { mx, my }, { bx, by } }) do
			if L.offEdge(style, p[1], p[2]) or G.dist(cx, cy, p[1], p[2]) > extent then return false end
		end
		if T.wetAlong(sampler, { { ax, ay }, { bx, by } }, setback) then return false end
		if T.grade(sampler, ax, ay, bx, by) > bh.GRADE * maxSlope then return false end
		if RM.segNear(ridx, mx, my, bh.ROAD) or RM.segCross(ridx, ax, ay, bx, by) then return false end
		if TW.crossesGraph(g, ax, ay, bx, by) then return false end
		return true
	end
	local segs, nOk = {}, 0
	for k = 0, rows do
		for j = 0, cols - 1 do
			local s = { k, j, k, j + 1, ok = okSeg(k, j, k, j + 1) }
			segs[#segs + 1] = s
			if s.ok then nOk = nOk + 1 end
		end
	end
	for j = 0, cols do
		for k = 0, rows - 1 do
			local s = { k, j, k + 1, j, ok = okSeg(k, j, k + 1, j) }
			segs[#segs + 1] = s
			if s.ok then nOk = nOk + 1 end
		end
	end
	if nOk < 4 then return nil, "noRoom" end
	return { C = { br.C.x, br.C.y }, node = br.C.id, f = { fx, fy }, u = { ux, uy }, rows = rows, cols = cols, len = len,
		dep = dep, J = J, segs = segs, nOk = nOk, heading = br.heading, src = (style.bridge and style.bridge.C) and "plan" or "graph" }
end

local function bhKey(k, j) return "mbh:" .. k .. ":" .. j end

local function bridgePlan(mp, style, m, env)
	m.geo = nil
	mp.bridgeKey = style.bridgeKey
	if not M.ON then return end
	mp.bridgeGeo, mp.bridgeWhy = nil, nil
	local geo, why = M.bridgeGeo(style, env.g, env.terrain, env.extent)
	if geo == nil then
		m.planWhy = why
		mp.bridgeWhy = style.bridge and why or nil
		return
	end
	local id = m.id
	local fx, fy, ux, uy = geo.f[1], geo.f[2], geo.u[1], geo.u[2]
	local ox, oy = geo.C[1], geo.C[2]
	local half = geo.cols / 2 * geo.len + 15
	local depth = geo.rows * geo.dep + 15
	local function inRect(x, y)
		local a = (x - ox) * fx + (y - oy) * fy
		local b = (x - ox) * ux + (y - oy) * uy
		return a >= -10 and a <= depth and abs(b) <= half
	end
	local okAt = {}
	for _, s in ipairs(geo.segs) do okAt[s[1] .. ":" .. s[2] .. ":" .. s[3] .. ":" .. s[4]] = s.ok end
	local function segOk(k1, j1, k2, j2) return okAt[k1 .. ":" .. j1 .. ":" .. k2 .. ":" .. j2] end
	local planned, nRuns = TW.layGrid(mp, { nk = geo.rows, nj = geo.cols, J = geo.J, segOk = segOk, key = bhKey,
		prefix = "mbh", id = id, rowCls = function() return "small" end, drop = inRect })
	local count = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.motif == id then TW.pair(pc); count = count + 1 end
	end
	geo.planned, geo.pieces, geo.runs = planned, count, nRuns
	m.geo = geo
	mp.bridgeGeo = geo
	m.planWhy = nil
end

local function bridgeMeasure(env, m)
	local mp = env.mp
	local geo = m.geo or (mp and mp.bridgeGeo)
	if geo == nil then
		local why = m.planWhy or (mp and mp.bridgeWhy)
		if why == nil then return nil end
		return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(why) }
	end
	local built, planned, linked = 0, 0, 0
	for _, s in ipairs(geo.segs) do
		if s.ok then
			planned = planned + 1
			local ax, ay = geo.J(s[1], s[2])
			local bx, by = geo.J(s[3], s[4])
			if L.segBuilt(env.g, ax, ay, bx, by, 8) then
				built = built + 1
				-- (linked: a built side leaving the cross street's dead ends)
				local h = geo.cols / 2
				for _, e in ipairs({ { s[1], s[2] }, { s[3], s[4] } }) do
					if e[1] == 0 and (e[2] == h - 1 or e[2] == h + 1) then linked = linked + 1; break end
				end
			end
		end
	end
	local houses = 0
	local qx, qy = geo.J(geo.rows / 2, geo.cols / 2)
	local rq = max(geo.rows * geo.dep, geo.cols * geo.len) * 0.75
	for _, p in ipairs(env.pts or {}) do if G.dist(qx, qy, p[1], p[2]) <= rq then houses = houses + 1 end end
	return { edges = L.incEdges(env.inc, "mbh"), total = built, houses = houses, built = built, planned = planned,
		linked = linked,
		text = string.format("bridge=%s,grid=%dx%d,sides=%d/%d,linked=%d,heading=%.0f", geo.src, geo.cols, geo.rows, built,
			planned, linked, math.deg(G.wrap(geo.heading)) % 360) }
end

local function bridgeEligible(ctx)
	if not M.ON then return 0 end
	local st = ctx.style
	if st.metro or st.bridge == nil then return 0 end
	return 1, "bridge:" .. tostring(st.bridge.src or "built")
end

--- The style's bridge record key (ot_core rebuilds the master plan when it changes).
function M.bridgeKey(rec)
	if rec == nil then return "" end
	if rec.C then return string.format("plan:%.0f:%.0f", rec.C[1], rec.C[2]) end
	return "built"
end

---------------------------------------------------------------------------

--- Registers the M4 kinds (append order = their save indices after the M3 kinds: 14-17).
function M.registerAll(MO)
	MO.register({ id = "switchbacks", group = "land", eligible = switchEligible, plan = switchPlan, measure = switchMeasure,
		dose = switchDose })
	MO.register({ id = "ridge_street", group = "land", eligible = ridgeEligible, plan = ridgePlan, measure = ridgeMeasure })
	MO.register({ id = "headland_street", group = "shore", eligible = headlandEligible, style = headlandStyle,
		plan = headlandPlan, measure = headlandMeasure, dose = headlandDose })
	-- (derived + extra: present once the town's bridge stands, takes no motif slot, never saved; locked like the station
	-- quarter)
	MO.register({ id = "bridgehead_quarter", derived = true, extra = true, lock = true, eligible = bridgeEligible,
		plan = bridgePlan, measure = bridgeMeasure })
end

return M
