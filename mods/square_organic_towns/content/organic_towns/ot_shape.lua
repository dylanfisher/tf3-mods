-- Organic Towns: town shape archetypes (pure). PLAN.md 6.3 "Town shapes".
--
-- The street style (ot_style: grid, organic rings, ...) decides what the streets look like; the shape decides
-- where a town grows: which frontier pieces the selector (ot_select.cost) takes first. Real towns take their
-- outline from their site and their roads (urban morphology: Conzen's town-plan analysis, the German village
-- forms Strassendorf / Angerdorf / Haufendorf, ribbon development along roads, finger plans):
--
--   compact  Haufendorf / nucleated town: roughly round around the core (the old behaviour)
--   linear   street village / ribbon development / valley or coastal strip: long and narrow along one axis
--   cross    crossroads town: 3-4 corridors along the roads that meet in it (T, Y or +)
--   fingers  finger / spider plan: 4-6 narrow corridors with green wedges between (Copenhagen's Finger Plan,
--            suburbs along radial roads and rail)
--   fan      coast or one-sided site (a bay, a cliff, a river bank): a half-circle opening away from the barrier
--   twin     two cores growing together (old town + station quarter, twin villages, a satellite on the road to
--            a neighbour): a second core some 500-900 m out, joined by a corridor
--   lens     Angerdorf / village around a green: an oval with an open green in the middle
--   ridge    ridge town (hill towns of Italy and southern France): long along the crest, avoiding lower ground
--   shore    shore town (fishing villages, seaside resorts, lake towns, island towns): a long strip along the actual
--            shoreline (ot_terrain.shoreline, its curve around bays, lake shores and island coasts), limited depth
--            inland, a waterfront street at a setback (ot_shore); 2026-10-12, PLAN.md 6.3 "Shore towns"
--
-- Selection (SH.pick): on real maps the site decides (TERRAIN_GAIN): a valley axis -> linear, a ridge ->
-- ridge, a coast -> fan or a strip along the shore, a river -> along the banks, a hillside -> along the contour;
-- then the context (CONTEXT_GAIN): roads leaving the town (2 opposite -> linear, 3-4 -> cross, 5+ -> fingers),
-- a neighbouring town (close: twin growing toward it; farther: linear toward it), a station a few hundred
-- metres out (linear toward it). On flat land without context the style's own weights decide, seeded per
-- town (EU organic mostly compact / lobed / linear, NA grid cross / linear, Nordic linear, MED hill ridge /
-- compact ...). The pick is a weighted draw from the town seed, so towns of one map differ.
--
-- Steering (SH.distance): every shape is an "effective distance" de(x, y) that replaces the plain distance from
-- the centre in the selector's cost: the growth front is the set of points with de below a level that rises
-- as the town grows. Arms are ellipses along their direction (ka = reach, kb = half width per unit of
-- level); a compact core circle (scaled by cf) keeps the centre filled; wedges between arms cost more.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local SITE = ug_require "square_organic_towns::/organic_towns/ot_site.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local DV = ug_require "square_organic_towns::/organic_towns/ot_diverse.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"

local SH = {}

SH.IDS = { "compact", "linear", "cross", "fingers", "fan", "twin", "lens", "ridge", "shore" }   -- (append only: saved index)
SH.INDEX = {}
for i, id in ipairs(SH.IDS) do SH.INDEX[id] = i end

-- Flat land, no context: weights per style (seeded draw)
SH.STYLE_WEIGHTS = {
	-- (v9: compact / lens first, as the metropolis grid that read as the American grid; Showcase v8's NA grid drew a
	-- linear shape toward its neighbour and grew arms instead of blocks)
	NA_GRID = { compact = 3, lens = 1, cross = 0.75, linear = 0.75 },
	NA_SUBURB = { fingers = 2, compact = 1.5, fan = 1, linear = 0.5 },
	-- (2026-10-13 round 5: fewer round towns: compact / lens down, linear / fingers up)
	EU_ORGANIC = { compact = 1.75, twin = 1.5, linear = 1.4, lens = 0.6, cross = 0.75, fingers = 0.5 },
	EU_EXTENSION = { compact = 1.25, cross = 1.5, fingers = 1.25, linear = 1.25, twin = 1, lens = 0.3 },
	MED_HILL = { compact = 1.25, ridge = 2, lens = 0.3, linear = 0.75 },
	MED_ENSANCHE = { compact = 3, cross = 1 },
	JP_DENSE = { linear = 1, compact = 2.25, cross = 1 },
	-- (v9: Copenhagen's Finger Plan / Stockholm's green wedges: fingers with green between them; valleys and fjords
	-- still pick linear from the site)
	NORDIC = { fingers = 2, linear = 1.5, compact = 1, fan = 0.5 },
	SUPERBLOCK = { compact = 2, cross = 1.5, linear = 1 },
}
SH.DEFAULT_WEIGHTS = { compact = 2, linear = 1, cross = 1 }
SH.TERRAIN_GAIN = 12      -- site evidence decides (a style's weights sum to ~5-8)
SH.SHORE_GAIN = 0.7       -- x TERRAIN_GAIN for the shore strip of a coast town (0.75 until 2026-10-13: half the coast
SH.SHORE_GAIN_NORDIC = 0.85 -- towns became shore towns; 0.25 / 0.4 in rounds 2-4, back up in round 5: ot_form SHORE_P;
                          -- 0.45 / 0.6 in round 5, up in the final-test round: shore towns weren't visible)
-- x TERRAIN_GAIN for a hillside town along its contour (0.5 until 2026-10-13, 0.8 in rounds 3-4; round 5: 1.2, the user
-- on Middlewich, a hillside town along its contour with one long street up the hill: "very cool")
SH.HILLSIDE_GAIN = 1.4
-- (final-test round, 2026-10-13: the user loved Stratford-upon-Avon's "mountain roads", its linear arms along the
-- contour of the mountain's foothills (grade over 0.04, hill_road); real hilly towns read grade 0.01-0.05, so the
-- hillside candidate starts lower now, gain 1.2 -> 1.4)
SH.HILLSIDE_GRADE = 0.028
SH.COAST_DIST = 620       -- m: the water this near the centre gives the coast candidates (500 until the final-test round)
SH.SOFT_VALLEY = 6        -- m: soft valley / ridge for the site shape (both sides at least this higher / lower)
SH.SOFT_K = 1.5           -- ... and this x the most level axis' own change
SH.CONTEXT_GAIN = 7       -- roads between towns, neighbours, stations: a little over the style's taste
SH.ONE_EXIT_GAIN = 0.8    -- x CONTEXT_GAIN: one road leaves town -> linear along it (0.5 until round 5: ribbons)
SH.SECTOR_DAMP = 0.4      -- a shaped town keeps this share of the seeded sector preference (ot_select)

-- Geometry per shape: arm reach ka, half width kb, core factor cf (core circle radius = level / cf)
-- Strengthened 2026-10-12 (showcase v3: shape-row towns read round at 1000 m, the game's own growth around the
-- core dominates): longer, narrower arms, deeper wedges, a smaller core share (PLAN.md 6.3 "Stronger shapes").
SH.GEOM = {
	linear = { ka = 2.5, kb = 0.42, cf = 2.0 },
	ridge = { ka = 2.3, kb = 0.48, cf = 1.9, drop = 40 },   -- de x (1 + metres below the centre / drop)
	cross = { ka = 2.4, kb = 0.36, cf = 2.1 },
	fingers = { ka = 2.3, kb = 0.28, cf = 1.4, wedge = 2.4, core = 1.5 },   -- core radius = core x block
	fan = { across = 1.35, front = 0.95, back = 0.15 },
	-- twin: the old core grows slower (core), the link starts at linkAt x D, the second core at secondAt x D
	twin = { core = 2.4, link = 0.3, linkAt = 0.3, second = 1.0, secondAt = 0.3 },
	lens = { ka = 1.45, kb = 0.7, green = 3 },   -- the green: + green x block on de
	-- shore: along the shoreline (arc length from the town's foot point) ka x, inland kb x; beyond the depth cap
	-- (depth x block.depth, clamped, x island on islands) steep x more; the core circle (cf) and a link from the
	-- centre to its foot on the shore (link: corridor cost per metre off it) keep an inland core connected; env: x the
	-- selector's envelope area (the promenade is single-loaded: the water side has no lots, so more street per house)
	-- (round 5, 2026-10-13: longer and shallower, ka 3.0 -> 3.6, kb 0.45 -> 0.38, depth cap 350 -> 280 m: "spread further
	-- along the coast rather than deep")
	-- (final-test round, 2026-10-13: the shore towns' streets reached 660-900 m inland (SHAPE shore= / ownShore= depth),
	-- the core around an inland centre swallowing the strip: a smaller core (cf 2.0 -> 2.6), longer and shallower again
	-- (ka 3.6 -> 4.2, kb 0.38 -> 0.32, depth cap 280 -> 240 m); the inland side is a wedge now (ot_wedge: nothing planned
	-- beyond the depth cap off the link, a frame along the town's inland tips))
	shore = { ka = 4.2, kb = 0.32, cf = 2.6, link = 0.35, depth = 3.0, depthMin = 130, depthMax = 240, steep = 4,
		island = 0.75, wetM = 30, env = 1.3 },
}
-- shapes whose growth runs along arms (SH.armAt / inArm, the selector's arm rules)
SH.ARMED = { linear = true, ridge = true, cross = true, fingers = true, shore = true }
SH.ARM_BAND = 1.3          -- inArm: within this x the arm's half width (kb / ka of the distance along it)
SH.EXIT_MERGE = math.rad(30)   -- road exits closer than this in heading are one corridor
SH.EXIT_PAD = 150          -- m beyond the houses' extent: a road edge starting this near still leaves the town
SH.CROSS_X = true              -- cross on an even spoke count not divisible by 4: an X of 4 arms (else a Y of 3)
SH.TWIN_NEAR = 1800            -- m: a neighbour this close makes a twin (growing together)
-- Deep arms (2026-10-12, Showcase v5: arms read as ladders / fishbones): an arm grows as a strip, its spine plus back
-- streets parallel to it (ot_grow_organic), so the corridor is at least STRIP_BAND x block wide on each side, and
-- inside it the selector's distance counts the distance along the arm plus STRIP_PERP x the distance across
-- (SH.stripDistance) instead of the elliptical field, whose half width made a back street one block out cost as
-- much as five blocks further along (only the cross stubs were cheap: the ladder). Organic growers only (their
-- plans have the back rows; shape.strip); grids keep the old corridor.
SH.STRIP_BAND = 2.0            -- x block (len): arm corridor half width at least this (inArm / armAt / stripDistance)
SH.STRIP_PERP = 0.35           -- effective metres per metre across the arm inside the strip ...
SH.STRIP_PERP2 = 1.5           -- ... + this per metre beyond STRIP_ROW1 x block.depth (the second row comes later)
SH.STRIP_ROW1 = 1.25
SH.SPOKE_SNAP = true           -- organic plans: a seeded shape axis snaps to a master-plan spoke, arms sit on spokes
SH.NEIGHBOUR_FAR = 4000        -- m: ... this close pulls a linear town toward it
SH.NEIGHBOUR_GAIN = 0.12       -- x CONTEXT_GAIN for that pull (0.6 until 2026-10-12: with the showcase's towns 2.5 km
                               -- apart most style towns turned linear, Showcase v6)
-- Arm reach (2026-10-12, Showcase v6 user feedback: "many cities now have long linear offshoots ... across all
-- styles", JP dense with two empty straight arms): long arms only for shapes that want them. Strong reach (the
-- full GEOM ka, the arms' extra lead) for linear / ridge / fingers picked from the site (valley, coast, river,
-- hillside, ridge) and for forced shapes (dev showcase); every other shape (style weights, roads, neighbours,
-- stations; cross, twin, lens, fan) grows mostly around: its arm reach is shrunk to 1 + (ka - 1) x MILD_REACH and
-- the selector gives it no extra lead (ot_select, shape.reach).
SH.MILD_REACH = 0.4
SH.STRONG_IDS = { linear = true, ridge = true, fingers = true, shore = true }

local pi = math.pi
local cos, sin, sqrt, abs, max, min, floor = math.cos, math.sin, math.sqrt, math.abs, math.max, math.min, math.floor

local function deg(a) return floor(math.deg(G.wrap(a)) % 360 + 0.5) end

--- Road exits of a town: { {heading, w} } (merged within EXIT_MERGE, strongest first). edges = { {p0 = {x, y},
--- p1 = {x, y}, template} }: a road that is not a town street (country roads between towns, which the game
--- builds as main connections) crossing the circle of radius r around (cx, cy) counts at the heading of its
--- outer end. Town streets don't count: a town's own streets cross its building extent all around.
function SH.exits(edges, cx, cy, r)
	local raw = {}
	for _, e in ipairs(edges or {}) do
		if type(e.template) == "string" and e.template:find("town_", 1, true) == nil then
			local d0 = G.dist(cx, cy, e.p0[1], e.p0[2])
			local d1 = G.dist(cx, cy, e.p1[1], e.p1[2])
			-- (2026-10-13 fix: a road starting at the town's outer street node lies wholly beyond the houses' extent r:
			-- its inner end within r + EXIT_PAD counts too)
			local di, dd = math.min(d0, d1), math.max(d0, d1)
			if (di <= r and dd > r) or (di <= r + SH.EXIT_PAD and dd > di + 20) then
				local o = d0 > d1 and e.p0 or e.p1
				raw[#raw + 1] = { G.atan2(o[2] - cy, o[1] - cx), 1 }
			end
		end
	end
	table.sort(raw, function(a, b) return a[1] < b[1] end)
	local out = {}
	for _, x in ipairs(raw) do
		local merged = false
		for _, c in ipairs(out) do
			if G.angleDiff(c[1], x[1]) < SH.EXIT_MERGE then
				-- weighted mean heading
				local w = c[2] + x[2]
				local vx = cos(c[1]) * c[2] + cos(x[1]) * x[2]
				local vy = sin(c[1]) * c[2] + sin(x[1]) * x[2]
				c[1], c[2] = G.atan2(vy, vx), w
				merged = true
				break
			end
		end
		if not merged then out[#out + 1] = { x[1], x[2] } end
	end
	table.sort(out, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return a[1] < b[1]
	end)
	return out
end

---------------------------------------------------------------------------
-- Shore towns (2026-10-12): the shoreline as the shape's spine

SH.SHORE_MIN_LEN = 600     -- m of traced shoreline a shore shape needs
SH.SHORE_CELL = 200        -- m: segment index cell

--- true when the terrain stats carry a shoreline a shore town can follow (a sea / lake shore, no pond or river).
function SH.shoreUsable(t)
	local w = t and t.water
	local sh = t and t.shore
	return sh ~= nil and w ~= nil and w.kind == "coast" and w.body ~= "pond" and w.body ~= "river"
		and (sh.L or 0) >= SH.SHORE_MIN_LEN and #sh.pts >= 3
end

--- Shore data for a shape: { pts, cum, L, closed, foot = {x, y}, s0, axis (shore heading at the foot, the travel
--- direction), depthCap (m), island, cells (segment index) } from stats.shore, the plan centre and block depth.
function SH.shoreData(t, centre, depth, island)
	if not SH.shoreUsable(t) then return nil end
	local src = t.shore
	local g = SH.GEOM.shore
	local sd = { pts = src.pts, cum = src.cum, L = src.L, closed = src.closed == true, island = island == true,
		cells = {}, nseg = src.closed and #src.pts or #src.pts - 1 }
	local cell = SH.SHORE_CELL
	for i = 1, sd.nseg do
		local a, b = sd.pts[i], sd.pts[i % #sd.pts + 1]
		local x0, x1, y0, y1 = G.cellRange(a[1], a[2], b[1], b[2], 0, cell)   -- (hang guard)
		for cx = x0 or 1, x1 or 0 do
			for cy = y0, y1 do
				local k = cx * 65536 + cy
				local l = sd.cells[k]
				if l == nil then l = {}; sd.cells[k] = l end
				l[#l + 1] = i
			end
		end
	end
	local _, perp, _, sAbs, fx, fy, ti = SH.shoreAt(sd, centre[1], centre[2])
	sd.s0, sd.foot, sd.start = sAbs, { fx, fy }, perp
	local a, b = sd.pts[ti], sd.pts[ti % #sd.pts + 1]
	sd.axis = G.z0(G.heading(a[1], a[2], b[1], b[2]))
	sd.depthCap = G.clamp(g.depth * (depth or 80), g.depthMin, g.depthMax) * (island and g.island or 1)
	return sd
end

local function segNear(sd, i, x, y, best)
	local a, b = sd.pts[i], sd.pts[i % #sd.pts + 1]
	local d, t = G.pointSegDist(x, y, a[1], a[2], b[1], b[2])
	if d < best.d then best.d, best.i, best.t = d, i, t end
end

--- Nearest point of the shore to (x, y): along (m along the shore from the foot: the shorter way on a closed loop),
--- perp (m from the shore), wet (true: on the water side), s (arc length), fx, fy (the point), segment index, arm
--- (1: ahead of the foot in the travel direction, 2: behind).
function SH.shoreAt(sd, x, y)
	local cell = SH.SHORE_CELL
	local best = { d = math.huge }
	local i0, j0 = floor(x / cell), floor(y / cell)
	for ring = 0, 3 do
		for di = -ring, ring do
			for dj = -ring, ring do
				if max(abs(di), abs(dj)) == ring then
					local l = sd.cells[(i0 + di) * 65536 + (j0 + dj)]
					if l then for _, i in ipairs(l) do segNear(sd, i, x, y, best) end end
				end
			end
		end
		if best.d <= ring * cell then break end
	end
	if best.i == nil or best.d > 3 * cell then
		for i = 1, sd.nseg do segNear(sd, i, x, y, best) end
	end
	local i, t = best.i, best.t or 0
	local a, b = sd.pts[i], sd.pts[i % #sd.pts + 1]
	local fx, fy = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
	local segL = G.dist(a[1], a[2], b[1], b[2])
	local sAbs = sd.cum[i] + t * segL
	-- water on the right of the travel direction: (b - a) x (p - a) < 0
	local cross = (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1])
	local wet = cross < 0
	local along, arm = 0, 1
	if sd.s0 then
		local ds = sAbs - sd.s0
		if sd.closed then
			ds = ds % sd.L
			if ds <= sd.L / 2 then along, arm = ds, 1 else along, arm = sd.L - ds, 2 end
		else
			along, arm = abs(ds), ds >= 0 and 1 or 2
		end
	end
	return along, best.d, wet, sAbs, fx, fy, i, arm
end

--- Weighted candidates for a town: list of { id, w, axis (rad or nil = seeded), reason, arms = {rad} or nil,
--- toward = m (twin: distance to the neighbour) }. inputs: ot_inputs.build result; p: the resolved profile
--- (id, block, seed, centre).
function SH.candidates(inputs, p)
	local list = {}
	local siteMode = false
	local function add(id, w, axis, reason, extra)
		local c = { id = id, w = w, axis = axis, reason = reason, site = siteMode or nil }
		for k, v in pairs(extra or {}) do c[k] = v end
		list[#list + 1] = c
	end
	for _, id in ipairs(SH.IDS) do
		local ws = SH.STYLE_WEIGHTS[p.id] or SH.DEFAULT_WEIGHTS
		if (ws[id] or 0) > 0 then add(id, ws[id], nil, "style") end
	end
	local TG, CG = SH.TERRAIN_GAIN, SH.CONTEXT_GAIN
	local t = inputs.terrain
	siteMode = true
	if t then
		local w = t.water
		if w and w.kind == "coast" and (w.distance or math.huge) < SH.COAST_DIST and w.body ~= "pond" then
			add("fan", TG, G.wrap(w.dir + pi), "coast: a fan opening inland")
			-- (shore towns: along the traced shoreline, its curve, when there is one; else a straight strip)
			if SH.shoreUsable(t) then
				add("shore", TG * (p.id == "NORDIC" and SH.SHORE_GAIN_NORDIC or SH.SHORE_GAIN), w.axis,
					"coast: a strip along the shore")
			else
				add("linear", TG * (p.id == "NORDIC" and 1.25 or 0.75), w.axis, "coast: a strip along the shore")
			end
		elseif w and w.kind == "river" then
			add("linear", TG, w.axis, "river: along the banks")
			add("twin", TG * 0.3, w.axis, "river: two cores along the banks")
		end
		local dr = t.dirRelief
		if dr and (t.meanSlope or 0) > 0.03 then
			-- (final-test round: a soft valley / ridge too, both sides SOFT_VALLEY m higher / lower and SOFT_K x the axis'
			-- own change; ot_terrain's flags (8 m, 2 x) held for no real town)
			local loV = math.min(dr.sideA or 0, dr.sideB or 0)
			local loR = math.min(-(dr.sideA or 0), -(dr.sideB or 0))
			local softV = loV > SH.SOFT_VALLEY and loV > SH.SOFT_K * (dr.level or 0)
			local softR = loR > SH.SOFT_VALLEY and loR > SH.SOFT_K * (dr.level or 0)
			if dr.valley or softV then
				add("linear", TG, dr.axis, string.format("valley: axis %d deg", deg(dr.axis)))
			elseif dr.ridge or softR then
				add("ridge", TG, dr.axis, string.format("ridge: crest %d deg", deg(dr.axis)))
			elseif t.relief and (t.relief.grade or 0) > SH.HILLSIDE_GRADE then
				-- (2026-10-13, user: towns should "follow terrain": a slope town clearly along its contour; 0.5 until then,
				-- below a style's own weights, so most hillside towns drew a style shape)
				add("linear", TG * SH.HILLSIDE_GAIN, G.wrap(t.relief.dir + pi / 2), "hillside: along the contour")
				add("fan", TG * 0.3, t.relief.dir, "hillside: a fan downhill")
			end
		end
	end
	siteMode = false
	local exits = inputs.exits or {}
	if #exits == 1 then
		add("linear", CG * SH.ONE_EXIT_GAIN, exits[1][1], "one road leaves town")
	elseif #exits == 2 then
		if G.angleDiff(exits[1][1], exits[2][1]) > math.rad(140) then
			add("linear", CG, exits[1][1], "two roads leave on opposite sides")
		else
			add("cross", CG * 0.6, exits[1][1], "two roads leave town", { arms = { exits[1][1], exits[2][1] } })
		end
	elseif #exits >= 3 then
		local arms = {}
		for i = 1, min(#exits, 4) do arms[i] = exits[i][1] end
		add("cross", CG * (#exits == 3 and 1 or 0.8), exits[1][1], #exits .. " roads leave town", { arms = arms })
		if #exits >= 5 then
			local fa = {}
			for i = 1, min(#exits, 6) do fa[i] = exits[i][1] end
			add("fingers", CG * 0.6, exits[1][1], #exits .. " roads leave town (spider)", { arms = fa })
		end
	end
	local nb = inputs.neighbours or {}
	local near = nb[1]
	if near and near.dist <= SH.TWIN_NEAR then
		add("twin", CG, near.dir, string.format("neighbour town %.1f km: growing together", near.dist / 1000),
			{ toward = near.dist })
	elseif near and near.dist <= SH.NEIGHBOUR_FAR then
		add("linear", CG * SH.NEIGHBOUR_GAIN, near.dir, string.format("toward the neighbour town %.1f km", near.dist / 1000))
	end
	local st = inputs.stations and inputs.stations[1]
	if st then
		local sx, sy = st[1] or st.x, st[2] or st.y
		local d = G.dist(inputs.pos[1], inputs.pos[2], sx, sy)
		if d >= 250 and d <= 1200 then
			local gain = (p.id == "NA_GRID" or p.id == "JP_DENSE") and 0.75 or 0.5
			add("linear", CG * gain, G.heading(inputs.pos[1], inputs.pos[2], sx, sy), "toward the station")
		end
	end
	return list
end

--- Arms (headings) for a shape around `axis`, seeded: cross 3 (T / Y) or 4, fingers 4-6, linear / ridge the
--- two ends of the axis. spokes (organic growers: the master plan's spoke count, spokes at axis + i x 360/k):
--- the arms sit on spokes, so every arm gets the same main street (ribbon) along it; arms off the spokes grew
--- unevenly (tested).
--- Headings of the organic master plan's spokes (ot_grow_organic.masterPlan: the same seeded jitter), or nil.
function SH.spokeHeadings(p)
	if p.grower ~= "organic" or not p.radial then return nil end
	local k = math.max(3, p.radial.spokes)
	local jit = math.rad(p.jitter or 0)
	local out = {}
	for i = 1, k do
		out[i] = G.wrap((p.axis or 0) + (i - 1) * 2 * pi / k + jit * (rng.unit(p.seed or 1, "theta", i) * 2 - 1))
	end
	return out
end

local function seededArms(id, axis, seed, spokes, thetas, drawV)
	local function jit(k, amp) return (rng.unit(seed, "armj", k) * 2 - 1) * amp end
	if id == "linear" or id == "ridge" then
		if thetas then
			-- on the spoke nearest the axis and the spoke nearest its opposite (the strips follow the spokes)
			local function near(h)
				local best, bd = h, math.huge
				for _, t in ipairs(thetas) do
					local d = G.angleDiff(t, h)
					if d < bd then best, bd = t, d end
				end
				return best
			end
			return { near(axis), near(axis + pi) }
		end
		return { axis, G.wrap(axis + pi) }
	end
	if spokes and spokes >= 3 and (id == "cross" or id == "fingers") then
		local step = 2 * pi / spokes
		local idx
		if id == "fingers" then
			idx = {}
			for i = 0, spokes - 1 do idx[#idx + 1] = i end
		elseif spokes % 4 == 0 then
			idx = { 0, spokes / 4, spokes / 2, 3 * spokes / 4 }
		elseif spokes % 2 == 0 and SH.CROSS_X then
			-- (2026-10-12) an even spoke count not divisible by 4 (EU styles: 6): two straight lines crossing,
			-- an X of 4 arms (60 / 120 deg), not a Y of 3 (the goal: a cross reads as 4 arms)
			local k = floor(spokes / 3 + 0.5)
			idx = { 0, k, spokes / 2, spokes / 2 + k }
		else
			idx = { 0, floor(spokes / 3 + 0.5), floor(2 * spokes / 3 + 0.5) }
		end
		local out = {}
		local i0 = 0
		if thetas then
			-- the exact spoke headings (jitter included), counted from the spoke nearest the axis
			local bd = math.huge
			for i, t in ipairs(thetas) do
				local d = G.angleDiff(t, axis)
				if d < bd then i0, bd = i - 1, d end
			end
		end
		for _, i in ipairs(idx) do
			out[#out + 1] = thetas and thetas[(i0 + i) % spokes + 1] or G.wrap(axis + i * step)
		end
		return out
	end
	if id == "cross" then
		if rng.decide(drawV, seed, "arms3") < 0.35 then
			return { axis, G.wrap(axis + math.rad(120) + jit(1, math.rad(15))), G.wrap(axis + math.rad(240) + jit(2, math.rad(15))) }
		end
		local out = {}
		for k = 0, 3 do out[#out + 1] = G.wrap(axis + k * pi / 2 + (k > 0 and jit(k, math.rad(12)) or 0)) end
		return out
	end
	if id == "fingers" then
		local n = 4 + floor(rng.decide(drawV, seed, "fingers") * 3)
		local out = {}
		for k = 0, n - 1 do out[#out + 1] = G.wrap(axis + k * 2 * pi / n + (k > 0 and jit(k, math.rad(15)) or 0)) end
		return out
	end
	return nil
end

--- The shape of a town: { id, axis, reason, arms, centre, block, second = {x, y} (twin), green = {lu, lv}
--- (lens), forced = bool }. inputs.shape (dev tools) or inputs.frame.shape (saved at the town's first build)
--- force the id (and the saved axis). May set p.axis to the shape axis (see below).
function SH.pick(inputs, p, formShape)
	local seed = p.seed or 1
	-- formShape (ot_form, Showcase v8 round): the shape the town's form wants, as a forced id but neither dev nor saved
	local forced = inputs.shape or (inputs.frame and inputs.frame.shape) or formShape or nil
	if forced and SH.INDEX[forced] == nil then forced = nil end
	local cands = SH.candidates(inputs, p)
	local pick
	if forced then
		-- the strongest candidate of that id (its axis and reason), else seeded
		for _, c in ipairs(cands) do
			if c.id == forced and (pick == nil or c.w > pick.w) then pick = c end
		end
		pick = pick and { id = forced, axis = pick.axis, reason = pick.reason, arms = pick.arms, toward = pick.toward,
			site = pick.site } or { id = forced, reason = "forced" }
		local byForm = inputs.shape == nil and not (inputs.frame and inputs.frame.shape) and formShape ~= nil
		pick.reason = (inputs.shape and "forced (dev): " or (byForm and "form: " or "saved: ")) .. tostring(pick.reason)
		if inputs.frame and inputs.frame.shape == forced and inputs.frame.shapeAxis then pick.axis = inputs.frame.shapeAxis end
	else
		-- one entry per shape: the weights add up; axis / arms / reason from its strongest site or context
		-- evidence (a style-only shape gets a seeded axis)
		local byId, order = {}, {}
		for _, c in ipairs(cands) do
			local m = byId[c.id]
			if m == nil then
				m = { id = c.id, w = 0, bestW = -1, reason = "style" }
				byId[c.id] = m
				order[#order + 1] = m
			end
			m.w = m.w + c.w
			if c.site then m.siteW = (m.siteW or 0) + c.w end
			if c.axis ~= nil and c.w > m.bestW then
				m.bestW, m.axis, m.arms, m.toward, m.reason, m.site = c.w, c.axis, c.arms, c.toward, c.reason, c.site
			end
		end
		-- neighbour diversity (ot_diverse, 2026-10-13): a shape the towns nearby use weighs less, but only its style /
		-- road / neighbour part: the terrain's evidence (valley, ridge, river, coast, hillside) is never down-weighted
		local dv = DV.factors(inputs.nbrPicks, "shape")
		if next(dv) ~= nil then
			local used = {}
			for _, m in ipairs(order) do
				local f = dv[m.id]
				if f then
					local site = m.siteW or 0
					m.w = site + (m.w - site) * f
					used[m.id] = f
				end
			end
			DV.note(inputs, "shape", used)
		end
		local total = 0
		for _, m in ipairs(order) do total = total + m.w end
		-- (§68: the shape pick stays on rng.unit, the anchor of its 5-letter group: arms3 and metro draw with rng.decide,
		-- works with rng.draw, so none of them is a shifted copy of it any more)
		local r = rng.unit(seed, "shape") * total
		for _, m in ipairs(order) do
			r = r - m.w
			if pick == nil and r <= 0 then pick = m end
		end
		pick = pick or order[#order] or { id = "compact", reason = "default" }
	end
	local id = pick.id
	-- shore: needs a traced shoreline (else a straight strip along the water, or compact)
	local sd = nil
	if id == "shore" then
		local island = false
		local okI, feats = pcall(SITE.features, inputs.terrain, inputs.wide)
		if okI and feats then island = feats.island == true end
		sd = SH.shoreData(inputs.terrain, p.centre, p.block and p.block.depth, island)
		if sd == nil then
			local w = inputs.terrain and inputs.terrain.water
			id = w and "linear" or "compact"
			pick.axis = w and w.axis or pick.axis
			pick.reason = tostring(pick.reason) .. " (no shoreline)"
		elseif not (inputs.frame and inputs.frame.shape == "shore" and inputs.frame.shapeAxis) then
			pick.axis = sd.axis
		end
	end
	local strictGrid = p.grower ~= "organic" and (p.angleRange or 0) <= 10
	local axis = pick.axis
	local axisSeeded = axis == nil
	if axis == nil then
		if strictGrid then
			axis = G.wrap((p.axis or 0) + floor(rng.unit(seed, "shapeAxis") * 4) * pi / 2)
		else
			axis = G.wrap(rng.unit(seed, "shapeAxis") * 2 * pi)
		end
	end
	-- away from industries (ot_industry): a seeded axis turns (90 deg steps for strict grids, 30 deg otherwise) so the
	-- arms point away from the works near the town; an axis from the site, the context or a saved frame stays
	local indTurned, edgeTurned = false, false
	local function armsFn(a)
		if id == "twin" then return { a } end
		if id == "fan" then return { a, G.wrap(a + pi / 3), G.wrap(a - pi / 3) } end
		return seededArms(id, a, seed, nil, nil, p.drawV) or { a, G.wrap(a + pi) }
	end
	local turnN = strictGrid and 4 or 12
	-- map edge (ot_map, 2026-10-13: Axbridge's arm ran to the map boundary): a seeded axis turns so its arms point away
	-- from a near edge (least exposure within EXPOSE_REACH; kept when it has none); the industry turn below picks among
	-- the turns that are as good for the edge
	local edgeCands = nil
	if axisSeeded and id ~= "compact" and inputs.bounds ~= nil then
		local ex0 = MAP.armsExposure(inputs.bounds, p.centre[1], p.centre[2], armsFn(axis))
		if ex0 > 0 then
			local best, bestEx = axis, ex0
			edgeCands = {}
			local exs = {}
			for k = 0, turnN - 1 do
				local a = G.wrap(axis + k * 2 * pi / turnN)
				local ex = MAP.armsExposure(inputs.bounds, p.centre[1], p.centre[2], armsFn(a))
				exs[#exs + 1] = { a, ex }
				if ex < bestEx - 1e-9 then best, bestEx = a, ex end
			end
			-- (the edge's best turn first: ot_industry.bestAxis keeps cands[1] unless another gains enough)
			edgeCands[1] = best
			for _, x in ipairs(exs) do if x[2] <= bestEx + 0.02 and x[1] ~= best then edgeCands[#edgeCands + 1] = x[1] end end
			if best ~= axis then axis, edgeTurned = best, true end
		end
	end
	if axisSeeded and id ~= "compact" and inputs.industry ~= nil and IND.AXIS then
		local cands = edgeCands
		if cands == nil then
			cands = {}
			for k = 0, turnN - 1 do cands[#cands + 1] = G.wrap(axis + k * 2 * pi / turnN) end
		end
		axis, indTurned = IND.bestAxis(inputs.industry, p.centre[1], p.centre[2], cands, armsFn)
	end
	-- a fresh plan (no saved frame, no street grid, water or station axis) turns its plan axis to the shape's,
	-- so spokes / grid lines run along the corridors; strict grids keep their survey axis (NA, ensanche)
	if p.axisSource == "seed" and not strictGrid and id ~= "compact" then p.axis = G.z0(axis) end
	local shape = { id = id, axis = axis, reason = pick.reason or "style", centre = { p.centre[1], p.centre[2] },
		block = max(p.block and p.block.len or 100, 40), forced = forced ~= nil }
	if indTurned then shape.reason = tostring(shape.reason) .. " (turned away from industry)"; shape.indTurned = true end
	if edgeTurned then shape.reason = tostring(shape.reason) .. " (turned away from the map edge)"; shape.edgeTurned = true end
	-- arm reach: strong for site-picked linear / ridge / fingers and for dev-forced shapes, mild otherwise
	local strong = inputs.shape ~= nil or (SH.STRONG_IDS[id] == true and pick.site == true)
	shape.reach = strong and 1 or SH.MILD_REACH
	shape.strong = strong
	-- (§63 skeleton: arms from the site keep their headings; dev-forced shapes are left alone)
	shape.site = pick.site == true or nil
	shape.dev = inputs.shape ~= nil or nil
	local spokes = (p.grower == "organic" and p.radial and p.axisSource == "seed") and math.max(3, p.radial.spokes) or nil
	-- deep arms (2026-10-12): the arms sit exactly on spokes (their strips are built along the spokes); a seeded
	-- axis in a plan whose axis comes from the town's streets / station snaps to the nearest spoke first (before:
	-- arms at seeded angles between the spokes, which only infill crossed)
	local thetas = nil
	if (id == "linear" or id == "ridge" or id == "cross" or id == "fingers") and p.grower == "organic" and p.radial then
		if spokes and SH.SPOKE_SNAP then
			thetas = SH.spokeHeadings(p)
		elseif axisSeeded and SH.SPOKE_SNAP and not pick.arms then
			thetas = SH.spokeHeadings(p)
			local best, bd = axis, math.huge
			for _, t in ipairs(thetas) do
				local d = G.angleDiff(t, axis)
				if d < bd then best, bd = t, d end
			end
			axis = best
			shape.axis = best
			spokes = #thetas
		end
	end
	shape.arms = pick.arms or seededArms(id, axis, seed, spokes, thetas, p.drawV)
	if id == "shore" then
		shape.shore = sd
		shape.arms = { sd.axis, G.wrap(sd.axis + pi) }   -- (the shore's heading at the foot both ways: logs, metrics)
	end
	shape.depth = max(p.block and p.block.depth or 80, 30)
	shape.strip = p.grower == "organic" and (id == "linear" or id == "ridge" or id == "cross" or id == "fingers") or nil
	if id == "twin" then
		local D = G.clamp(6 * shape.block, 500, 900)
		if pick.toward then D = G.clamp(0.45 * pick.toward, 400, 900) end
		shape.second = { p.centre[1] + cos(axis) * D, p.centre[2] + sin(axis) * D }
		shape.D = D
	elseif id == "lens" then
		shape.green = { max(60, 0.9 * shape.block), max(35, 0.45 * shape.block) }
	end
	if p.centre and inputs.terrain and inputs.terrain.high and id == "ridge" then shape.highZ = inputs.terrain.high[3] end
	return shape
end

--- Elliptical arm distance from the centre along heading a: reach ka forward, half width kb (behind the
--- centre the half width applies too).
--- cap (m, or nil): the arm stops there (§63 skeleton, shape.armMax): beyond it the distance along runs at the core's
--- rate cf per metre (continuous at the cap), so the corridor past a wood edge costs like the core field.
local function armDist(dx, dy, a, ka, kb, cap, cf)
	local ca, sa = cos(a), sin(a)
	local along = dx * ca + dy * sa
	local perp = -dx * sa + dy * ca
	if along >= 0 then
		local u = along / ka
		if cap and along > cap then u = cap / ka + (along - cap) * (cf or 2) end
		return sqrt(u ^ 2 + (perp / kb) ^ 2)
	end
	return sqrt((along / kb) ^ 2 + (perp / kb) ^ 2)
end

--- The skeleton's per-arm reach factor and along-distance cap (ot_skeleton, §63): k (1 without), cap (m) or nil.
local function armSkel(shape, i)
	local k = shape.armK and shape.armK[i] or 1
	local m = shape.armMax and shape.armMax[i] or nil
	if m == false then m = nil end
	return k, m
end
SH.armSkel = armSkel

--- Effective distance (m) of point (x, y) for the shape (the selector's growth order; compact = plain
--- distance). terrain (optional ot_terrain sampler): the ridge's height term.
function SH.distance(shape, x, y, terrain)
	local cx, cy = shape.centre[1], shape.centre[2]
	local dx, dy = x - cx, y - cy
	local r = sqrt(dx * dx + dy * dy)
	local id = shape.id
	if id == "compact" or id == nil then return r end
	local g = SH.GEOM[id]
	if id == "linear" or id == "ridge" or id == "cross" or id == "fingers" then
		local best = r * g.cf
		if id == "fingers" then
			local rc = g.core * shape.block
			if r > rc then best = rc * g.cf + (r - rc) * g.cf * g.wedge end   -- green wedges between the fingers
		end
		-- (forms / character towns: kaMul / kbMul make the arms longer and narrower, ot_form)
		local ka = (1 + (g.ka - 1) * (shape.reach or 1)) * (shape.kaMul or 1)
		local kb = g.kb * (shape.kbMul or 1)
		for i, a in ipairs(shape.arms or { shape.axis }) do
			local k, cap = armSkel(shape, i)
			local d = armDist(dx, dy, a, ka * k, kb, cap, g.cf)
			if d < best then best = d end
		end
		if id == "ridge" and terrain and shape.highZ ~= nil then
			local okH, h = pcall(terrain.height, x, y)
			local h0 = shape.centreZ
			if h0 == nil then
				local okC, hc = pcall(terrain.height, cx, cy)
				h0 = okC and hc or 0
				shape.centreZ = h0
			end
			if okH and h then best = best * (1 + max(0, h0 - h) / g.drop) end
		end
		return best
	end
	if id == "shore" then
		local sd = shape.shore
		if sd == nil then return r end
		local core = r * g.cf
		local link = G.pointSegDist(x, y, cx, cy, sd.foot[1], sd.foot[2]) / g.link
		local along, perp, wet = SH.shoreAt(sd, x, y)
		if wet and perp > g.wetM then return min(core, link) end
		local pd = perp + max(0, perp - sd.depthCap) * g.steep
		return min(core, link, sqrt((along / (g.ka * (shape.kaMul or 1))) ^ 2 + (pd / g.kb) ^ 2))
	end
	if id == "fan" then
		local a = shape.axis
		local front = dx * cos(a) + dy * sin(a)
		local across = -dx * sin(a) + dy * cos(a)
		local k = front >= 0 and g.front or g.back
		return sqrt((across / g.across) ^ 2 + (front / k) ^ 2)
	end
	if id == "twin" then
		-- (polycentric metropolis, ot_metro: shape.seconds = { {x, y, D} } several secondary centres, each with its
		-- own link; a plain twin has the one shape.second)
		local best = r * g.core
		for _, s in ipairs(shape.seconds or { shape.second }) do
			local D = s[3] or shape.D or 400
			local r2 = G.dist(x, y, s[1], s[2])
			local link = G.pointSegDist(x, y, cx, cy, s[1], s[2]) / g.link + g.linkAt * D
			best = min(best, r2 * g.second + g.secondAt * D, link)
		end
		return best
	end
	if id == "lens" then
		local a = shape.axis
		local u = dx * cos(a) + dy * sin(a)
		local v = -dx * sin(a) + dy * cos(a)
		local d = sqrt((u / (g.ka * (shape.kaMul or 1))) ^ 2 + (v / (g.kb * (shape.kbMul or 1))) ^ 2)
		local gr = shape.green
		if gr and (u / gr[1]) ^ 2 + (v / gr[2]) ^ 2 < 1 then d = d + g.green * shape.block end
		return d
	end
	return r
end

--- Arm half width over reach (kb / ka with the form's kaMul / kbMul).
function SH.armRatio(shape, g)
	return (g.kb * (shape.kbMul or 1)) / (g.ka * (shape.kaMul or 1))
end

--- true when (x, y) lies in one of the shape's arm corridors beyond the core (linear / ridge / cross / fingers:
--- along an arm, within ARM_BAND x its half width, at least one block out; twin: along the link to the second
--- core or around it). The selector lets arms lead one piece further (ot_select).
function SH.inArm(shape, x, y)
	if shape == nil then return false end
	local id = shape.id
	local cx, cy = shape.centre[1], shape.centre[2]
	local dx, dy = x - cx, y - cy
	local block = shape.block or 100
	if id == "shore" then
		local sd = shape.shore
		if sd == nil then return false end
		local along, perp, wet = SH.shoreAt(sd, x, y)
		return along > block and perp <= sd.depthCap and not (wet and perp > SH.GEOM.shore.wetM)
	end
	if id == "linear" or id == "ridge" or id == "cross" or id == "fingers" then
		local g = SH.GEOM[id]
		for i, a in ipairs(shape.arms or { shape.axis }) do
			local ca, sa = cos(a), sin(a)
			local along = dx * ca + dy * sa
			local _, cap = armSkel(shape, i)
			if along > block and not (cap and along > cap) then
				local perp = abs(-dx * sa + dy * ca)
				if perp <= max((shape.strip and SH.STRIP_BAND or 0.6) * block, along * SH.armRatio(shape, g) * SH.ARM_BAND) then return true end
			end
		end
		return false
	end
	if id == "twin" and shape.second then
		for _, s in ipairs(shape.seconds or { shape.second }) do
			if G.pointSegDist(x, y, cx, cy, s[1], s[2]) <= 0.8 * block or G.dist(x, y, s[1], s[2]) <= 2 * block then return true end
		end
		return false
	end
	return false
end

--- The arm corridor (x, y) lies in: arm index, distance along it (m) -- linear / ridge / cross / fingers, within
--- the arm band (SH.inArm's width) and ahead of the centre (along > 0; minAlong: at least this far out). nil
--- elsewhere. ot_select keeps each arm's lead within ARM_REACH of its last junction (ribbons, no bare spines).
function SH.armAt(shape, x, y, minAlong)
	if shape == nil then return nil end
	local id = shape.id
	if id == "shore" then
		local sd = shape.shore
		if sd == nil then return nil end
		local along, perp, wet, _, _, _, _, arm = SH.shoreAt(sd, x, y)
		if along > (minAlong or 0) and perp <= sd.depthCap + 0.5 * (shape.block or 100) and not (wet and perp > SH.GEOM.shore.wetM) then
			return arm, along
		end
		return nil
	end
	if id ~= "linear" and id ~= "ridge" and id ~= "cross" and id ~= "fingers" then return nil end
	local g = SH.GEOM[id]
	local dx, dy = x - shape.centre[1], y - shape.centre[2]
	local block = shape.block or 100
	local best, bestAlong, bestPerp = nil, nil, math.huge
	for i, a in ipairs(shape.arms or { shape.axis }) do
		local ca, sa = cos(a), sin(a)
		local along = dx * ca + dy * sa
		local _, cap = armSkel(shape, i)
		if along > (minAlong or 0) and not (cap and along > cap) then
			local perp = abs(-dx * sa + dy * ca)
			if perp <= max((shape.strip and SH.STRIP_BAND or 0.6) * block, along * SH.armRatio(shape, g) * SH.ARM_BAND) and perp < bestPerp then
				best, bestAlong, bestPerp = i, along, perp
			end
		end
	end
	return best, bestAlong
end

--- Effective distance inside an arm strip (deep arms): the shape's distance at the point's foot on the arm axis
--- + STRIP_PERP x its distance from the axis, for points in an arm corridor (SH.armAt, beyond one block); nil
--- elsewhere (and for shapes without shape.strip). A back street one block out costs about half a block more than
--- the spine beside it, the second row (beyond STRIP_ROW1 x depth) some three blocks more, so arms grow as strips
--- 2-3 blocks deep instead of a spine with cross stubs.
function SH.stripDistance(shape, x, y, terrain)
	if shape == nil or not shape.strip then return nil end
	local i, along = SH.armAt(shape, x, y, shape.block or 100)
	if i == nil then return nil end
	local a = shape.arms[i]
	local cx, cy = shape.centre[1], shape.centre[2]
	local fx, fy = cx + cos(a) * along, cy + sin(a) * along
	local perp = abs(-(x - cx) * sin(a) + (y - cy) * cos(a))
	local row1 = SH.STRIP_ROW1 * (shape.depth or shape.block or 80)
	return SH.distance(shape, fx, fy, terrain) + SH.STRIP_PERP * perp + SH.STRIP_PERP2 * max(0, perp - row1)
end

--- "linear axis=35 arms=2 (valley: axis 35 deg)" for the log (spaces become _ there).
function SH.text(shape)
	if shape == nil then return "-" end
	local arms = {}
	for _, a in ipairs(shape.arms or {}) do arms[#arms + 1] = tostring(deg(a)) end
	local extra = ""
	if shape.shore then
		extra = string.format(" shoreLen=%.0f depth=%.0f%s%s", shape.shore.L, shape.shore.depthCap,
			shape.shore.closed and " closed" or "", shape.shore.island and " island" or "")
	end
	return string.format("%s axis=%d%s reach=%s%s", shape.id, deg(shape.axis or 0), #arms > 0 and (" arms=" .. table.concat(arms, "/")) or "",
		(shape.reach or 1) >= 1 and "strong" or "mild", extra)
end

return SH
