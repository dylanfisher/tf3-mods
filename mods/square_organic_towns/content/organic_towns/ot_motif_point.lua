-- Organic Towns: the peninsula tip motif (pure; final-test round, 2026-10-13). Registered into the ot_motif registry by
-- ot_motif (P.registerAll(MO)), MO.IDS 18.
--
-- User (final all-phases test, session 2026-10-13_0856_sqot-dev): Southborough's "small group of houses at the tip of a
-- coastal peninsula" was "like expensive real estate". There it came by chance: the town's linear arm along the water
-- (shape linear "river: along the banks", axis 30 deg) ran out along the spit until the water stopped it. The motif
-- makes it deliberate:
--
--   peninsula_tip  (drawn, group point) on a town near a spit of land (a peninsula / headland narrower than NARROW m
--                  with water on both sides for at least NECK_MIN m, its tip TIP_BEYOND..MAX_BEYOND m beyond the houses):
--                  one street from the town out along the spit's middle (re-centred between the two shores each step),
--                  stopping short of the tip, and a small cluster at its end: CLUSTER lanes off both sides near the tip
--                  (dead ends, as long as the land allows). The plan's other streets are kept off the spit beyond the core
--                  (the neck stays green: one street of houses), the spine and lanes are locked (the game hangs no side
--                  streets on them), the build's DevelopAt dose goes beside them (houses along the approach and at the
--                  tip first).
--
-- The spit is found once per town and session from the terrain (P.findSpit, the driver's terrain stage: stats.spit):
-- DIRS rays from the centre, each walked out until it reaches water ahead; along the last stretch the land's width
-- across the ray (water on both sides within PROBE m); the ray with the longest narrow neck wins. Geometry from stable
-- data (centre, terrain, seed); not saved beyond the frame's motif id. Plain plan pieces through the normal planner
-- (housed front, lead limit, own empty budget, map edge, water / grade checks, the crash rule unchanged).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local L = ug_require "square_organic_towns::/organic_towns/ot_motif_land.lua"

local P = {}

local cos, sin, abs, floor, max, min = math.cos, math.sin, math.abs, math.floor, math.max, math.min

P.ON = true
P.PT = {
	DIRS = 16,             -- rays from the centre
	S0 = 150,              -- m: rays start this far out
	STEP = 50,             -- m per ray step
	MAX_D = 1800,          -- m: the tip this far from the centre at most
	PROBE = 300,           -- m: width probe each side of the ray
	PROBE_STEP = 50,
	NARROW = 450,          -- m: the land at most this wide across the ray (water both sides) is the neck
	NECK_MIN = 200,        -- m of neck before the tip at least
	TIP_BEYOND = 120,      -- m: the tip at least this far beyond the houses' extent (else the town has it already)
	MAX_BEYOND = 1300,     -- ... at most this far
	-- geometry
	TRACE_STEP = 30,
	RECENTRE = 15,         -- m per step at most toward the spit's middle
	SIDE_MAX = 260,        -- m: shore search across the spine
	END_GAP = 25,          -- m beyond waterSetback: the spine stops this short of the water ahead
	CLUSTER_LEN = 240,     -- m of spine at its end: the tip cluster's lanes
	LANE_GAP = 60,         -- m between lanes along the spine
	LANE_LEN = { 35, 90 }, -- m: lane length range (as the land allows)
	CORRIDOR = 140,        -- m: the plan's own pieces this near the spine beyond the core are dropped
	SCORE = 0.9,           -- eligibility at best
	-- (round R5, 2026-10-13: Alsager, visibly a peninsula (water in 14 of 16 directions), read spit=-: its land is wider
	-- than NARROW. A second, wide pass when the narrow one finds nothing; the spit then carries wide = true)
	WIDE = { PROBE = 500, NARROW = 850, NECK_MIN = 250 },
}

local function wet(s, x, y, r)
	return L.wetNear(s, x, y, r)
end

--- The distance (m) from (x, y) along (ux, uy) to the first water within maxD (step), or nil.
local function waterAlong(s, x, y, ux, uy, maxD, step)
	for d = step, maxD, step do
		if T.isWater(s, x + ux * d, y + uy * d) then return d end
	end
	return nil
end

--- The town's spit (see the header): { dir (rad), tip (m from the centre to the last dry step), neck (m of narrow
--- land before it), width (mean m across the neck), base (m: where the neck starts), x, y (the tip point) } or nil.
function P.findSpit(s, cx, cy, o)
	if s == nil then return nil end
	o = o or {}
	local pt = P.PT
	local sp = P.findSpitPass(s, cx, cy, o, pt.PROBE, pt.NARROW, pt.NECK_MIN)
	if sp == nil and pt.WIDE then
		sp = P.findSpitPass(s, cx, cy, o, pt.WIDE.PROBE, pt.WIDE.NARROW, pt.WIDE.NECK_MIN)
		if sp then sp.wide = true end
	end
	return sp
end

--- One pass of the spit search with a probe reach, the widest neck and its least length.
function P.findSpitPass(s, cx, cy, o, probe, narrow, neckMin)
	local pt = P.PT
	local best = nil
	for k = 0, pt.DIRS - 1 do
		local a = k / pt.DIRS * 2 * math.pi
		local ux, uy = cos(a), sin(a)
		local nx, ny = -uy, ux
		local run, wsum, nw = 0, 0, 0
		local tip = nil
		local probeNext = true
		for d = pt.S0, pt.MAX_D, pt.STEP do
			local x, y = cx + ux * d, cy + uy * d
			if T.isWater(s, x, y) then tip = d - pt.STEP; break end
			if o.offEdge and o.offEdge(x, y) then break end
			-- (the width every other step: the neck is long, the probes cost)
			if probeNext then
				local wl = waterAlong(s, x, y, nx, ny, probe, pt.PROBE_STEP)
				local wr = wl and waterAlong(s, x, y, -nx, -ny, probe, pt.PROBE_STEP) or nil
				if wl and wr and wl + wr <= narrow then
					run, wsum, nw = run + 2 * pt.STEP, wsum + wl + wr, nw + 1
				else
					run, wsum, nw = 0, 0, 0
				end
			end
			probeNext = not probeNext
		end
		if tip and run >= neckMin and nw > 0 then
			local width = wsum / nw
			local sc = run / max(width, 50) + 0.0003 * tip
			if best == nil or sc > best.score then
				best = { dir = G.wrap(a), tip = tip, neck = min(run, tip), width = width, base = max(0, tip - run),
					x = cx + ux * tip, y = cy + uy * tip, score = sc }
			end
		end
	end
	return best
end

--- "tip/neck/width@deg" (TERRAIN line) or "-".
function P.text(sp)
	if sp == nil then return "-" end
	return string.format("%.0f/%.0f/%.0f@%d%s", sp.tip, sp.neck, sp.width, floor(math.deg(G.wrap(sp.dir)) % 360 + 0.5),
		sp.wide and "w" or "")
end

--- The spine from the centre out along the spit (re-centred between its shores), stopping END_GAP + setback short of
--- the water ahead. Returns raw points, stop why.
function P.traceSpine(s, cx, cy, spit, o)
	local pt = P.PT
	local setback = o.setback or 25
	local pts = { { cx, cy } }
	local x, y, h = cx, cy, spit.dir
	local why = "len"
	local maxD = spit.tip + 200
	for _ = 1, floor(maxD / pt.TRACE_STEP) do
		local ux, uy = cos(h), sin(h)
		local nx, ny = x + ux * pt.TRACE_STEP, y + uy * pt.TRACE_STEP
		-- (water ahead within the setback + gap: the tip)
		if waterAlong(s, nx, ny, ux, uy, setback + pt.END_GAP, 10) or T.isWater(s, nx, ny) then why = "tip"; break end
		if o.offEdge and o.offEdge(nx, ny) then why = "edge"; break end
		-- re-centre on the neck (both shores within SIDE_MAX across)
		local d = G.dist(cx, cy, nx, ny)
		if d >= spit.base - 100 then
			local lx, ly = -uy, ux
			local side = max(pt.SIDE_MAX, (spit.width or 0) / 2 + 100)   -- (R5: a wide spit's shores lie farther out)
			local wl = waterAlong(s, nx, ny, lx, ly, side, 15)
			local wr = waterAlong(s, nx, ny, -lx, -ly, side, 15)
			if wl and wr then
				local shift = G.clamp((wl - wr) / 2, -pt.RECENTRE, pt.RECENTRE)
				nx, ny = nx + lx * shift, ny + ly * shift
			end
		end
		if wet(s, nx, ny, setback) then why = "water"; break end
		local nh = G.heading(x, y, nx, ny)
		-- (no turning back)
		if G.angleDiff(nh, spit.dir) > math.rad(80) then why = "turn"; break end
		pts[#pts + 1] = { nx, ny }
		x, y, h = nx, ny, nh
	end
	return pts, why
end

--- The peninsula tip's plan geometry (pure): { line, ix, lanes = { { s, x0, y0, x1, y1, len, key } }, spit, stop,
--- r0, sCluster } or nil, why.
function P.tipGeo(style, spit, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	if spit == nil then return nil, "noSpit" end
	local pt = P.PT
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local setback = style.waterSetback or 25
	local maxSlope = style.maxSlope or 0.1
	local function offEdge(x, y) return L.offEdge(style, x, y) end
	local raw, why = P.traceSpine(sampler, cx, cy, spit, { setback = setback, offEdge = offEdge })
	if #raw < 4 then return nil, "short:" .. why end
	-- (as the hill climb: a tighter smoothing when the smooth line comes out too steep)
	local line = nil
	for _, R in ipairs({ 100, 60, 0 }) do
		local cand = R > 0 and L.smooth(raw, R) or G.simplify(raw, 5, 25)
		if cand and #cand >= 2 then
			line = cand
			if T.pathMaxGrade(sampler, cand) <= 0.9 * maxSlope then break end
		end
	end
	if line == nil then return nil, "short:" .. why end
	local ix = L.index(line)
	local r0 = L.dropFrom(style)
	local e = line[#line]
	if G.dist(cx, cy, e[1], e[2]) < (style.radius or 0) + pt.TIP_BEYOND * 0.5 then return nil, "reached" end
	if extent and G.dist(cx, cy, e[1], e[2]) > extent then
		-- (beyond the plan's extent: cut there)
		local cut = {}
		for _, p in ipairs(line) do
			if G.dist(cx, cy, p[1], p[2]) > extent then break end
			cut[#cut + 1] = p
		end
		if #cut < 2 then return nil, "extent" end
		line = cut
		ix = L.index(line)
	end
	-- the tip cluster: lanes off both sides along the spine's last CLUSTER_LEN m (alternating, seeded first side)
	local lanes = {}
	local sCluster = max(r0, ix.len - pt.CLUSTER_LEN)
	local side = rng.unit(seed, "mptSide") < 0.5 and 1 or -1
	local s = ix.len - 20
	local guard = G.LOOP_CAP
	while s >= sCluster and guard > 0 do
		guard = guard - 1
		local x, y, ux, uy = L.at(ix, s)
		for _, sd in ipairs({ side, -side }) do
			local nx, ny = -uy * sd, ux * sd
			local len, z = 0, T.height(sampler, x, y)
			for d = 10, pt.LANE_LEN[2], 10 do
				local px, py = x + nx * d, y + ny * d
				if wet(sampler, px, py, setback + 10) or offEdge(px, py) then break end
				local pz = T.height(sampler, px, py)
				if abs(pz - z) / 10 > 0.75 * maxSlope then break end
				len, z = d, pz
			end
			if len >= pt.LANE_LEN[1] then
				lanes[#lanes + 1] = { s = s, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len, len = len, side = sd }
				break
			end
		end
		side = -side
		s = s - pt.LANE_GAP
	end
	table.sort(lanes, function(a, b) return a.s < b.s end)
	return { line = line, ix = ix, lanes = lanes, spit = spit, stop = why, r0 = r0, sCluster = sCluster }
end

local function tipStyle(p, m, env)
	-- (the terrain stats on the record: the plan's spit; a forced motif without one finds it in the plan)
	m.terrainStats = env.terrain
end

local function tipPlan(mp, style, m, env)
	m.geo = nil
	if not P.ON then return end
	local spit = m.terrainStats and m.terrainStats.spit or nil
	if spit == nil and m.forced and env.terrain then
		spit = P.findSpit(env.terrain, style.centre[1], style.centre[2])
	end
	local geo, why = P.tipGeo(style, spit, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local stops = {}
	for i, ln in ipairs(geo.lanes) do
		ln.key = "mpt:L" .. i
		stops[#stops + 1] = { s = ln.s, key = ln.key }
	end
	local cx, cy = style.centre[1], style.centre[2]
	local r0 = geo.r0
	-- (the plan's own pieces off the spit beyond the core: the neck keeps one street, the tip its cluster)
	local function drop(x, y, tee)
		if G.dist(cx, cy, x, y) < r0 then return false end
		return L.nearest(geo.ix, x, y, P.PT.CORRIDOR) ~= nil
	end
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mpt", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = m.id, class = "small", costK = L.COST_MAIN, lead = true,
		every = 90, stops = stops, part = "spine", mid = 0, drop = drop }, anchors)
	local made = 0
	for i, ln in ipairs(geo.lanes) do
		local j = mp.junctions[ln.key]
		if j then
			L.overlay(mp, { { j[1], j[2] }, { ln.x1, ln.y1 } }, { prefix = "mptL" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = ln.key, deadEnd = true, part = "lane", branch = "start",
				drop = function(x, y, tee) return tee or drop(x, y) end })
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

local function tipMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	local lanes = 0
	for _, ln in ipairs(geo.lanes) do
		local mx, my = (ln.x0 + ln.x1) / 2, (ln.y0 + ln.y1) / 2
		if L.segBuilt(env.g, ln.x0, ln.y0, mx, my, 8) then lanes = lanes + 1 end
	end
	local e = geo.line[#geo.line]
	local atTip = 0
	for _, p in ipairs(env.pts or {}) do
		if G.dist(e[1], e[2], p[1], p[2]) <= 160 then atTip = atTip + 1 end
	end
	local houses = L.housesAlong(env.pts, geo.ix, spans, 45)
	local sMax = 0
	for _, sp in ipairs(spans) do if sp[2] > sMax then sMax = sp[2] end end
	return { edges = L.incEdges(env.inc, "mpt"), total = n, houses = houses, len = len, lanes = lanes, atTip = atTip,
		reach = sMax,
		text = string.format("spine=%.0f/%.0f,reach=%.0f,lanes=%d/%d,atTip=%d,tip=%s,stop=%s,anchors=%d/%d", len, geo.ix.len,
			sMax, lanes, #geo.lanes, atTip, P.text(geo.spit), tostring(geo.stop), geo.anchors or 0, geo.links or 0) }
end

local function tipEligible(ctx)
	if not P.ON then return 0, "off" end
	local t = ctx.terrain
	local st = ctx.style
	if st.metro then return 0, "metro" end
	local sp = t and t.spit
	if sp == nil then return 0, "noSpit" end
	local pt = P.PT
	local beyond = sp.tip - (st.radius or 0)
	local why = string.format("spit:%s,beyond=%.0f", P.text(sp), beyond)
	if beyond < pt.TIP_BEYOND then return 0, why .. ",reached" end
	if beyond > pt.MAX_BEYOND then return 0, why .. ",far" end
	if L.offEdge(st, sp.x, sp.y) then return 0, why .. ",edge" end
	local s = pt.SCORE * G.clamp(sp.neck / 350, 0.45, 1) * L.styleK(st)
	if (ctx.tier or 2) >= 4 then s = s * 0.5 end
	if s <= 0 then return 0, why end
	return s, why
end

--- DevelopAt points beside the build's spine / lane edges (houses along the approach and at the tip), alternating
--- sides, at most n.
local function tipDose(m, edges, off, n)
	local geo = m.geo
	if geo == nil then return {} end
	local out = {}
	for i, e in ipairs(edges or {}) do
		if e.p0 and e.p1 and #out < n then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			local d, s = L.nearest(geo.ix, mx, my, 100)
			if d then
				local x, y, ux, uy = L.at(geo.ix, s)
				local sg = (i % 2 == 0) and 1 or -1
				out[#out + 1] = { G.round(x - uy * off * sg, 1), G.round(y + ux * off * sg, 1) }
			end
		end
	end
	return out
end

function P.registerAll(MO)
	MO.register({ id = "peninsula_tip", group = "point", lock = true, eligible = tipEligible, style = tipStyle,
		plan = tipPlan, measure = tipMeasure, dose = tipDose })
	MO.LOCK_PREFIX.peninsula_tip = "mpt"
end

return P
