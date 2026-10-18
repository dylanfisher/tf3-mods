-- Organic Towns: terrain / water motifs (pure). Phase M1 of the motifs plan (plans/square_organic_towns/MOTIFS_BRIEF.md,
-- 2026-10-13). Registered into the ot_motif registry by ot_motif (L.registerAll(MO)); every kind is a drawn one
-- (0-2 per town, seeded, saved on the frame, neighbour diversity).
--
--   hill_climb       (user's favourite: Middlewich, session 2026-10-13_0342_sqot) one main street from the town up the
--                    easiest climb of its slope (gentle grade, bends along the contour allowed, no hairpins: those are
--                    M4's switchbacks), 1-3 small terrace loops on the flatter shelves beside it, the steep ground
--                    between left green (no plan pieces in the climb's corridor). The climbing street leads by its
--                    housed stretch: no envelope / front / arm-fill limit, the housed front and the lead limit apply.
--   valley_fishbone  a main street along the valley floor, short lanes (ribs) up both slopes at intervals, each rib
--                    stopping where the ground gets steep.
--   harbour_crescent a curved waterfront street around a bay (concave shoreline, the traced shore), short streets
--                    inland off it, a dense row facing the water (the build's DevelopAt dose there, MO.dose).
--   fishing_village  a few narrow parallel streets straight down the slope to the shore, joined by a waterfront street
--                    at the bottom, beside the town's core on a sloped shore; small towns.
--
-- Each motif's plan hook adds plain plan pieces (L.overlay: the line cut into the master plan, crossing plan pieces
-- ending in a T on it, the plan's pieces in the motif's corridor dropped) that carry `motif` (ot_select: no envelope,
-- front, wedge or arm limits, loops allowed; the housed front, the lead limit, the lead depth, the own empty budget, the
-- map edge, water / grade checks and the crash rule unchanged), `costK` (cheaper: built first) and `motifLead` (the main
-- line: one piece more lead depth). Classes small / medium only (ot_core.hierarchy / straightWide narrow them further).
-- Plan data (the line, lanes, stats) goes on the motif record (m.geo) for the measure (MOTIF build lines) and the dose.
-- Not saved beyond the frame's motif ids: the geometry is derived from the terrain, the centre and the seed each session.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"

local L = {}

local sqrt, cos, sin, abs, floor, max, min = math.sqrt, math.cos, math.sin, math.abs, math.floor, math.max, math.min

L.ON = true
L.CELL = 40              -- m: line segment index cell
L.SNAP = 14              -- m: a crossing this near another stop on the line joins it
L.SMOOTH_R = 120         -- m: main lines smoothed to at least this radius where they have room
L.COST_MAIN = 0.4        -- costK of a motif's main line (ot_select cost)
L.COST_LANE = 0.7        -- ... of its lanes / ribs / terraces
L.COST_TEE = 0.7         -- ... of the plan's streets meeting its main line (they lead the town to it)
L.GRID_STYLES = { NA_GRID = true, NA_SUBURB = true, MED_ENSANCHE = true, SUPERBLOCK = true }
L.GRID_K = 0.35          -- eligibility x this for the gridded styles (their plans are whole blocks)

-- hill climb
L.HC = {
	STEP = 40,           -- m per trace step
	MAX_LEN = 900,       -- m of climb at most (from the centre)
	GRADE = 0.055,       -- target grade (x maxSlope 0.6 at most)
	TURN = math.rad(25), -- max turn per step
	DEV = math.rad(80),  -- max deviation from the uphill bearing (no hairpins)
	FLAT = 0.012,        -- three steps rising less than this: the top (a plateau)
	RING = 250,          -- m: the uphill bearing from heights on a ring this far out
	CORRIDOR = 1.1,      -- x block depth + 25 m: the climb's corridor (plan pieces there dropped beyond the core)
	SHELF = 0.65,        -- a terrace shelf's ground at most this x maxSlope
	TERRACE_GAP = 130,   -- m between terraces along the climb
	TERRACES = { 1, 3 }, -- terraces per town (seeded within)
	-- eligibility over the town's relief (2026-10-13 final test, session 2026-10-13_0856_sqot-dev: real hilly EU towns
	-- read grade 0.01-0.05 (Wirksworth, local slope 0.12: grade 0.048, range 103 m); the synthetic fixtures' 0.025-0.075
	-- left two of sixteen towns eligible)
	SMOOTH_TRY = { 120, 70, 0 },     -- m: smoothing radii tried for the climb's line (0: simplified only), the first
	                                 -- one within the climb's max grade wins (the last one that fits the length else)
	ELIG_GRADE = { 0.012, 0.035 },   -- grade: eligibility 0 .. 1 over these
	ELIG_RANGE = { 15, 45 },         -- m of height range in the 600 m disc: x 0 .. 1 over these
}
-- soft valley / ridge (2026-10-13 final test): both sides of the most level axis higher (valley) / lower (ridge) by at
-- least SOFT[1] m, full at SOFT[1] + SOFT[2] m, the sides at least SOFT_K x the axis' own change (ot_terrain.dirRelief's
-- flags ask 8 m and 2 x: no real town had them)
L.SOFT = { 4, 16 }
L.SOFT_K = 1.3
-- valley fishbone
L.VF = {
	STEP = 40,
	HALF = 650,          -- m of main street each way from the centre at most
	DEV = math.rad(45),  -- max deviation from the valley axis
	TURN = math.rad(20),
	RIB_SP = { 1.3, 70, 140 },   -- rib spacing: x block length, clamped (m)
	RIB_LEN = { 2.2, 70, 170 },  -- rib length at most: x block depth, clamped
	RIB_MIN = 35,        -- m: shorter ribs left out
	RIB_GRADE = 0.75,    -- a rib stops where the ground along it is steeper than this x maxSlope
}
-- harbour crescent
L.HB = {
	MARGIN = 12,         -- m beyond waterSetback: the crescent's distance from the shore
	LANE_SP = { 1.0, 55, 90 },
	LANE_LEN = { 1.2, 50, 100 },
	MIN_RATIO = 0.08,    -- bay depth / chord at least this (0.12 until the 2026-10-13 final test)
	ELIG_DIST = 650,     -- m: the water this near the centre at most (400 until the final test: towns sit 250-575 m
	                     -- from the shore and grow to it)
	FULL_RATIO = 0.25,   -- eligibility full at this bay ratio
	MIN_CHORD = 250,     -- m
}
-- fishing village
L.FV = {
	MARGIN = 12,
	SP = { 0.9, 45, 80 },        -- spacing of the parallel streets
	LEN = { 3.0, 120, 260 },     -- their length at most
	MIN_LEN = 50,
	N = { 3, 4 },                -- streets (seeded)
	GRADE = 0.9,                 -- a street stops where the ground is steeper than this x maxSlope
	TOWARD = math.rad(75),       -- the slope must fall toward the water within this (60 until the final test)
	ELIG_DIST = 550,             -- m: the water this near the centre at most (350 until the final test)
	ELIG_GRADE = { 0.022, 0.05 }, -- grade: eligibility 0 .. 1 over these (0.025 .. 0.065 until the final test)
}

-- The driver's plan slice inside the motifs' plan hooks (2026-10-13 slice budget: an overlay over a big plan took
-- ~30-110 ms): ot_motif.applyPlan sets L.yieldFn while its hooks run; L.overlay calls it every OVERLAY_YIELD pieces, only
-- inside a coroutine (a stale function outside one does nothing).
L.yieldFn = nil
L.OVERLAY_YIELD = 64
local function sliceYield()
	local fn = L.yieldFn
	if fn == nil or type(coroutine) ~= "table" then return end
	local co, main = coroutine.running()
	if co ~= nil and not main then fn() end
end

local function unit(x, y)
	local l = sqrt(x * x + y * y)
	if l < 1e-9 then return 0, 0, 0 end
	return x / l, y / l, l
end

local function clampSpec(spec, base)
	return G.clamp(spec[1] * base, spec[2], spec[3])
end

local function blk(style)
	return max(style.block and style.block.len or 80, style.block and style.block.depth or 60)
end

---------------------------------------------------------------------------
-- line tools

--- Segment index of a polyline: { pts, cum, dirs, cells } (segment k: pts[k - 1] -> pts[k]).
function L.index(pts)
	local dirs, cum = G.polyDirs(pts)
	local ix = { pts = pts, cum = cum, dirs = dirs, cells = {}, len = cum[#cum] }
	-- (the line's bounding box: L.nearest / crossings reject far points and pieces without the cell scan; 2026-10-13
	-- slice budget: the fishing village's overlays took ~110 ms offline, 8650 nearest calls over a 1669-piece plan)
	local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(pts) do
		if G.finite(p[1]) and G.finite(p[2]) then
			bx0, by0, bx1, by1 = min(bx0, p[1]), min(by0, p[2]), max(bx1, p[1]), max(by1, p[2])
		end
	end
	ix.box = { bx0, by0, bx1, by1 }
	local cell = L.CELL
	for k = 2, #pts do
		local a, b = pts[k - 1], pts[k]
		-- (G.cellRange: a segment with a bad coordinate or a huge box is left out of the index, never an endless loop)
		local x0, x1, y0, y1 = G.cellRange(a[1], a[2], b[1], b[2], 0, cell)
		for cx = x0 or 1, x1 or 0 do
			for cy = y0, y1 do
				local key = cx * 65536 + cy
				local l = ix.cells[key]
				if l == nil then l = {}; ix.cells[key] = l end
				l[#l + 1] = k
			end
		end
	end
	return ix
end

--- Nearest point of the indexed line within r of (x, y): d, s (arc length), side (> 0: left of travel), or nil.
function L.nearest(ix, x, y, r)
	local cell = L.CELL
	if not (G.finite(x) and G.finite(y) and r and r >= 0) then return nil end
	local box = ix.box
	if box and (x < box[1] - r or x > box[3] + r or y < box[2] - r or y > box[4] + r) then return nil end
	local n = math.min(math.ceil(r / cell), 64)
	local i0, j0 = floor(x / cell), floor(y / cell)
	local bd, bs, side = math.huge, nil, 0
	local seen = {}
	for di = -n, n do
		for dj = -n, n do
			for _, k in ipairs(ix.cells[(i0 + di) * 65536 + (j0 + dj)] or {}) do
				if not seen[k] then
					seen[k] = true
					local a, b = ix.pts[k - 1], ix.pts[k]
					local d, t = G.pointSegDist(x, y, a[1], a[2], b[1], b[2])
					if d < bd then
						bd = d
						bs = ix.cum[k - 1] + t * (ix.cum[k] - ix.cum[k - 1])
						side = (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1])
					end
				end
			end
		end
	end
	if bs == nil or bd > r then return nil end
	return bd, bs, side
end

--- Point and unit tangent at arc length s.
function L.at(ix, s)
	return G.frameAt(ix.pts, ix.dirs, ix.cum, s)
end

--- Points of the indexed line from arc length s0 to s1 (with tangents).
function L.sub(ix, s0, s1)
	local out = {}
	local x, y, ux, uy = L.at(ix, s0)
	out[1] = { x, y, ux, uy }
	for k = 1, #ix.pts do
		local c = ix.cum[k]
		if c > s0 + 1e-6 and c < s1 - 1e-6 then
			local p, d = ix.pts[k], ix.dirs[k]
			out[#out + 1] = { p[1], p[2], d[1], d[2] }
		end
	end
	x, y, ux, uy = L.at(ix, s1)
	out[#out + 1] = { x, y, ux, uy }
	return out
end

--- Proper crossings of polyline pts with the indexed line: list of { f (fraction on pts), x, y, s (on the line) }.
local function crossings(pts, ix)
	local out = {}
	-- (a crossing lies in both boxes: a piece whose box misses the line's has none)
	local box = ix.box
	if box then
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, p in ipairs(pts) do x0, y0, x1, y1 = min(x0, p[1]), min(y0, p[2]), max(x1, p[1]), max(y1, p[2]) end
		if x1 < box[1] or x0 > box[3] or y1 < box[2] or y0 > box[4] then return out end
	end
	local total = G.polyLen(pts)
	if total <= 0 then return out end
	local cell = L.CELL
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local seen = {}
		local x0, x1, y0, y1 = G.cellRange(a[1], a[2], b[1], b[2], 0, cell)
		for cx = x0 or 1, x1 or 0 do
			for cy = y0, y1 do
				for _, k in ipairs(ix.cells[cx * 65536 + cy] or {}) do
					if not seen[k] then
						seen[k] = true
						local c, d = ix.pts[k - 1], ix.pts[k]
						local t, u = G.segIntersect(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2], 1e-6)
						if t then
							out[#out + 1] = { (acc + t * l) / total, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
								ix.cum[k - 1] + u * (ix.cum[k] - ix.cum[k - 1]) }
						end
					end
				end
			end
		end
		acc = acc + l
	end
	table.sort(out, function(p, q) return p[1] < q[1] end)
	return out
end

--- Lays polyline `line` into master plan mp (in place). o = { prefix (unique key prefix), motif (id), class, curved
--- (default true), costK, lead (motifLead), band (m: the plan's pieces / parts whose midpoint lies this near the line
--- are dropped; not the parts ending on it), drop = fn(x, y, tee) -> true (more pieces / parts dropped by midpoint;
--- tee: the part ends on the line), stops = { { s, key? } } (junctions
--- wanted on the line: lanes), startKey / endKey (existing junction keys at the line's ends), deadEnd (the last piece a
--- planned cul-de-sac), every (m: the line split into pieces at most about this long), dense = { cx, cy, r0, r1, step }
--- (junctions every step m where the line is r0..r1 from (cx, cy): links for the town's dead ends), branch = "start" |
--- "end" (the line's first / last piece meets a main line: it is chosen with the main line's piece there), part (tag) }. Plan pieces
--- crossing the line end there in a T (shared junction), as ot_crescent / ot_shore do. Returns { stops = sorted
--- { s, key, x, y }, ix, pieces, cut }.
function L.overlay(mp, line, o)
	local ix = L.index(line)
	local len = ix.len
	local stops = {}
	local function stopNear(s, tol)
		for _, st in ipairs(stops) do if abs(st.s - s) <= tol then return st end end
		return nil
	end
	local function newStop(s, key, x, y)
		local st = { s = s, key = key, x = x, y = y }
		stops[#stops + 1] = st
		mp.junctions[key] = { x, y }
		return st
	end
	-- ends
	do
		local x, y = line[1][1], line[1][2]
		if o.startKey and mp.junctions[o.startKey] then
			stops[#stops + 1] = { s = 0, key = o.startKey, x = x, y = y }
		else
			newStop(0, o.prefix .. ":A", x, y)
		end
		x, y = line[#line][1], line[#line][2]
		if o.endKey and mp.junctions[o.endKey] then
			stops[#stops + 1] = { s = len, key = o.endKey, x = x, y = y }
		else
			newStop(len, o.prefix .. ":Z", x, y)
		end
	end
	-- wanted stops (lanes meet the line here)
	for i, w in ipairs(o.stops or {}) do
		if w.s > 1 and w.s < len - 1 then
			local st = stopNear(w.s, 1)
			if st == nil then
				local x, y = L.at(ix, w.s)
				st = newStop(w.s, w.key or (o.prefix .. ":S" .. i), x, y)
			end
			w.key, w.x, w.y = st.key, st.x, st.y
		end
	end
	local function dropAt(x, y, tee, pc)
		-- (motif streets stay, this motif's and another's: they are cut where the line crosses them)
		if pc and pc.motif ~= nil then return false end
		if o.band and o.band > 0 and not tee and L.nearest(ix, x, y, o.band) then return true end
		if o.drop and o.drop(x, y, tee) then return true end
		return false
	end
	local onLine = {}
	local kept, cut = {}, 0
	for pi, pc in ipairs(mp.pieces) do
		if pi % L.OVERLAY_YIELD == 0 then sliceYield() end
		local hits = crossings(pc.pts, ix)
		if #hits == 0 then
			local mx, my = G.polyAt(pc.pts, 0.5)
			if not dropAt(mx, my, false, pc) then kept[#kept + 1] = pc end
		else
			local cuts, keys = {}, { pc.a }
			for hi, c in ipairs(hits) do
				local st = stopNear(c[4], L.SNAP)
				if st == nil then
					st = newStop(c[4], o.prefix .. ":X" .. pc.key .. ":" .. hi, c[2], c[3])
					st.pending = true   -- (kept only when a part of a plan piece kept below ends here)
				end
				onLine[st.key] = st
				cuts[#cuts + 1] = { c[1], st.x, st.y }
				keys[#keys + 1] = st.key
			end
			keys[#keys + 1] = pc.b
			local parts = G.polySplit(pc.pts, cuts)
			for i, pts in ipairs(parts) do
				local mx, my = G.polyAt(pts, 0.5)
				local tee = onLine[keys[i]] or onLine[keys[i + 1]] or false
				local pl = G.polyLen(pts)
				-- (a part meeting the line at a shallow angle runs along it: dropped, else it blocks the line)
				local shallow = tee and o.band and o.band > 0 and pc.motif == nil
					and (L.nearest(ix, mx, my, o.band) or math.huge) < 0.3 * pl
				if keys[i + 1] and keys[i] ~= keys[i + 1] and pl > 5 and not shallow and not dropAt(mx, my, tee, pc) then
					local np = {}
					for k, v in pairs(pc) do np[k] = v end
					np.key, np.a, np.b, np.pts = pc.key .. "~" .. o.prefix .. i, keys[i], keys[i + 1], pts
					if i ~= 1 then np.dirA = nil end
					if i ~= #parts then np.dirB = nil end
					-- (the plan's streets meeting the line come a little earlier: they lead the town to it)
					if tee and o.teeK then np.costK = math.min(np.costK or 1, o.teeK) end
					kept[#kept + 1] = np
					if onLine[keys[i]] then onLine[keys[i]].pending = nil end
					if onLine[keys[i + 1]] then onLine[keys[i + 1]].pending = nil end
				end
			end
			cut = cut + 1
		end
	end
	-- crossings whose plan parts were all dropped (the motif's corridor): no junction on the line there
	for i = #stops, 1, -1 do
		if stops[i].pending then
			mp.junctions[stops[i].key] = nil
			table.remove(stops, i)
		end
	end
	-- dense stops where the line leaves the town (o.dense = { cx, cy, r0, r1, step }): junctions every step m there, so
	-- the town's dead ends nearby link to the line by the selector's connectors (ot_select, within joinR) even where the
	-- line's first pieces pass too near the town's streets for the planner
	local dn = o.dense
	if dn and (dn.step or 0) > 0 and len < G.MAX_COORD then
		local k = 0
		for sd = dn.step, len - dn.step, dn.step do
			local x, y = L.at(ix, sd)
			local d = G.dist(dn.cx, dn.cy, x, y)
			if d >= dn.r0 and d <= dn.r1 and stopNear(sd, 12) == nil then
				k = k + 1
				newStop(sd, o.prefix .. ":D" .. k, x, y)
			end
		end
	end
	-- periodic stops (pieces about `every` long, so the lead depth counts in blocks)
	if o.every and o.every > 0 then
		table.sort(stops, function(p, q) return p.s < q.s end)
		local add = {}
		for i = 2, #stops do
			local a, b = stops[i - 1], stops[i]
			local n = floor((b.s - a.s) / o.every + 0.5)
			if not (n < G.LOOP_CAP) then n = 1 end   -- (a NaN / endless line: no periodic stops)
			for k = 1, n - 1 do add[#add + 1] = a.s + (b.s - a.s) * k / n end
		end
		for i, s in ipairs(add) do
			local x, y = L.at(ix, s)
			newStop(s, o.prefix .. ":P" .. i, x, y)
		end
	end
	table.sort(stops, function(p, q) return p.s < q.s end)
	local n = 0
	local curved = o.curved ~= false
	for i = 2, #stops do
		local a, b = stops[i - 1], stops[i]
		if b.s - a.s > 0.5 and a.key ~= b.key then
			n = n + 1
			local pts
			if curved then pts = L.sub(ix, a.s, b.s) else pts = { { a.x, a.y }, { b.x, b.y } } end
			-- (the ends sit exactly on the junctions)
			pts[1][1], pts[1][2] = a.x, a.y
			pts[#pts][1], pts[#pts][2] = b.x, b.y
			kept[#kept + 1] = { key = o.prefix .. "#" .. a.key .. "|" .. b.key, a = a.key, b = b.key, pts = pts, class = o.class or "small",
				curved = curved or nil, smooth = curved or nil, motif = o.motif, costK = o.costK, motifLead = o.lead or nil,
				motifPart = o.part, culDeSac = (o.deadEnd and i == #stops) or nil, motifS0 = a.s, motifS1 = b.s,
				motifLine = o.prefix,
				-- (the piece at the main line: chosen with the main line's piece there, ot_select withBranches)
				motifBranch = ((o.branch == "start" and i == 2) or (o.branch == "end" and i == #stops)) or nil }
		end
	end
	mp.pieces = kept
	mp._through, mp._corr, mp._corrMain = nil, nil, nil
	return { stops = stops, ix = ix, pieces = n, cut = cut }
end

-- Anchors (where the line meets the town): the planner refuses new streets passing too near the town's streets and
-- nodes, and the game joins only dead ends, so a line traced from the centre may never connect where it leaves the
-- houses. Per direction along the line (from sMid): the exit (the last point within NEAR m of a town street, no farther
-- than the town radius + 3 blocks), then the town's dead end that best reaches the line just beyond it: one lying on the
-- line (within SNAP_ON m: the line simply continues from it, e.g. the built tip of the climb on a later plan), else a
-- short link street from it: a circular arc leaving the dead end straight along its street (radius >= LINK_R, MIN_LINK
-- .. REACH blocks long, meeting the line at >= MEET), so the joint has no kink. The line's pieces inward of an anchor
-- are left out (they lie in the town).
L.ANCHOR = { NEAR = 25, REACH = 3.5, AHEAD = 3, MIN_LINK = 24, SNAP_ON = 7, LINK_R = 95, MEET = math.rad(35) }

--- A circular arc from (ax, ay) leaving at heading h0 to (bx, by), dl = the signed angle from h0 to the chord (the
--- arc turns 2 dl in all); points every <= 10 deg with unit tangents (a straight line when dl ~ 0).
function L.arc(ax, ay, h0, bx, by, dl)
	local ll = G.dist(ax, ay, bx, by)
	if abs(dl) < 1e-4 then
		local ux, uy = unit(bx - ax, by - ay)
		return { { ax, ay, ux, uy }, { bx, by, ux, uy } }
	end
	local R = ll / (2 * abs(sin(dl)))
	local sg = dl > 0 and 1 or -1
	-- centre: to the left of travel (turning left, dl > 0) or right
	local cx, cy = ax - sin(h0) * R * sg, ay + cos(h0) * R * sg
	local a0 = G.atan2(ay - cy, ax - cx)
	local n = max(2, math.ceil(math.deg(abs(2 * dl)) / 10))
	local pts = {}
	for k = 0, n do
		local a = a0 + sg * 2 * abs(dl) * k / n
		local h = h0 + sg * 2 * abs(dl) * k / n
		pts[#pts + 1] = { cx + R * cos(a), cy + R * sin(a), cos(h), sin(h) }
	end
	pts[#pts][1], pts[#pts][2] = bx, by
	return pts
end

--- true when a link street (pts from dead end `id`) keeps clear of the town's other streets: no crossing, nothing
--- within CLEAR m beyond its first 12 m (the planner's nearExisting / crossesExisting checks).
L.LINK_CLEAR = 16
function L.linkClear(g, pts, id)
	local skip = { [id] = true }
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if OG.crossing(g, a[1], a[2], b[1], b[2], skip) then return false end
		acc = acc + G.dist(a[1], a[2], b[1], b[2])
		if acc > 12 and OG.distToEdges(g, b[1], b[2], L.LINK_CLEAR, skip) then return false end
	end
	return true
end

--- Anchors of the indexed line on graph g: list of { s, dir, x, y (the node), link (true: a link street), pts (the
--- link's points with tangents) }.
function L.anchors(g, style, ix, sMid, dirs, sampler)
	local out = {}
	if g == nil or #g.edges == 0 then return out end
	local A = L.ANCHOR
	local b = blk(style)
	local cx, cy = style.centre[1], style.centre[2]
	local rMax = max(style.radius or 0, b) + 3 * b
	local ends = OG.deadEnds(g)
	for _, dir in ipairs(dirs) do
		local exitS = sMid
		local sx = sMid
		local guard = G.LOOP_CAP
		while sx >= 0 and sx <= ix.len and guard > 0 and dir ~= 0 do
			guard = guard - 1
			local x, y = L.at(ix, sx)
			if G.dist(cx, cy, x, y) > rMax then break end
			if OG.distToEdges(g, x, y, A.NEAR) then exitS = sx end
			sx = sx + dir * 10
		end
		local best, bsc = nil, math.huge
		for _, id in ipairs(ends) do
			local n = g.nodeById[id]
			if n and not n.noJoin then
				local d0, sn = L.nearest(ix, n.x, n.y, A.REACH * b)
				if d0 and (sn - sMid) * dir > 0 then
					if d0 <= A.SNAP_ON then
						if (sn - exitS) * dir >= -b and d0 < bsc then
							best, bsc = { s = sn, dir = dir, x = n.x, y = n.y, link = false, id = id }, d0
						end
					else
						local e = g.edgeById[g.adj[id][1]]
						local od = G.wrap(OG.headingFrom(g, e, id) + math.pi)
						for t = -b, A.AHEAD * b, 10 do
							local st = sn + dir * t
							if st > 1 and st < ix.len - 1 and (st - exitS) * dir >= 0 then
								local x, y, ux, uy = L.at(ix, st)
								local ll = G.dist(n.x, n.y, x, y)
								if ll >= A.MIN_LINK and ll <= A.REACH * b then
									local ch = G.heading(n.x, n.y, x, y)
									local dl = G.wrap(ch - od)
									local sd = abs(sin(dl))
									local okR = sd < 1e-6 or ll / (2 * sd) >= A.LINK_R
									local d1 = od + 2 * dl
									if okR and abs(dl) < math.pi / 2 and G.lineAngleDiff(d1, G.atan2(uy, ux)) >= A.MEET then
										local sc = ll * (1 + abs(dl)) + 50
										if sc < bsc then
											local pts = L.arc(n.x, n.y, od, x, y, dl)
											-- (the planner's checks: not too steep, not onto / beside water)
											if L.linkClear(g, pts, id) and (sampler == nil or (T.pathMaxGrade(sampler, pts) <= (style.maxSlope or 0.1)
												and not T.wetAlong(sampler, pts, style.waterSetback or 25))) then
												best, bsc = { s = st, dir = dir, x = n.x, y = n.y, link = true, pts = pts, id = id }, sc
											end
										end
									end
								end
							end
						end
					end
				end
			end
		end
		if best then out[#out + 1] = best end
	end
	return out
end

--- Lays a motif's main line with its anchors: overlay o (+ the anchors' stops), the link streets, the pieces inward of
--- each anchor left out. anchors: L.anchors result. Returns the overlay result (+ .anchors = n, .links = n).
function L.layMain(mp, line, o, anchors)
	o.stops = o.stops or {}
	for i, a in ipairs(anchors) do
		local w = { s = a.s, key = o.prefix .. ":N" .. i }
		o.stops[#o.stops + 1] = w
		a.stop = w
	end
	local res = L.overlay(mp, line, o)
	local links = 0
	-- (ot_core plans again when an anchor's dead end is a dead end no more: the town built on from it)
	mp.motifAnchorIds = mp.motifAnchorIds or {}
	for _, a in ipairs(anchors) do mp.motifAnchorIds[#mp.motifAnchorIds + 1] = a.id end
	for i, a in ipairs(anchors) do
		local w = a.stop
		if w.key and mp.junctions[w.key] then
			if a.link then
				local kn = o.prefix .. ":K" .. i
				mp.junctions[kn] = { a.x, a.y }
				L.overlay(mp, a.pts, { prefix = o.prefix .. "K" .. i, motif = o.motif, class = "small",
					costK = o.costK, lead = true, startKey = kn, endKey = w.key, part = "link" })
				links = links + 1
			end
			-- (the line's pieces inward of the anchor lie in the town)
			local kept = {}
			for _, pc in ipairs(mp.pieces) do
				local inner = pc.motifLine == o.prefix and pc.motifS0 ~= nil
					and ((a.dir > 0 and pc.motifS1 <= a.s + 0.5) or (a.dir < 0 and pc.motifS0 >= a.s - 0.5))
				-- (only up to the town's middle on that side)
				if inner and o.mid then
					inner = (a.dir > 0 and pc.motifS0 >= o.mid - 0.5) or (a.dir < 0 and pc.motifS1 <= o.mid + 0.5)
				end
				if not inner then kept[#kept + 1] = pc end
			end
			mp.pieces = kept
		end
	end
	-- approach (o.approach = { d, r, k }): the plan's streets within d of the line and r of the centre cost k x (the town
	-- grows toward where the line leaves it, so its dead ends come to the line)
	local ap = o.approach
	if ap then
		local cx0, cy0 = ap.cx, ap.cy
		for _, pc in ipairs(mp.pieces) do
			if pc.motif == nil then
				local mx, my = G.polyAt(pc.pts, 0.5)
				if G.dist(cx0, cy0, mx, my) <= ap.r and L.nearest(res.ix, mx, my, ap.d) then
					pc.costK = math.min(pc.costK or 1, ap.k)
				end
			end
		end
	end
	res.anchors, res.links = #anchors, links
	-- (a direction without an anchor: ot_core plans again once the town has grown a little)
	if #anchors < (o.dirs or 1) then mp.motifReanchor = true end
	return res
end

--- The approach zone of a motif's main line (L.layMain o.approach): within 2 blocks of it, up to the corridor + 1 block.
L.COST_APPROACH = 0.75
function L.approach(style)
	local b = blk(style)
	return { cx = style.centre[1], cy = style.centre[2], d = 2 * b, r = L.dropFrom(style) + b, k = L.COST_APPROACH }
end

--- Dense junctions where a motif's main line leaves the town (its radius - 1 block .. + 2.5 blocks).
function L.dense(style)
	local b = blk(style)
	local r = max(style.radius or 0, b)
	return { cx = style.centre[1], cy = style.centre[2], r0 = max(0, r - b), r1 = r + 2.5 * b, step = 30 }
end

--- The band (m) along a motif's main line where the plan's pieces are dropped (no street running beside it).
function L.band(style)
	return G.clamp(0.5 * (style.block and style.block.depth or 60), 20, 40)
end

--- A smooth main line from raw trace points (simplified, then smoothed to R).
function L.smooth(raw, R)
	if #raw < 2 then return nil end
	local simp = G.simplify(raw, 5, 25)
	if #simp < 2 then return nil end
	local sm = G.smoothLine(simp, R or L.SMOOTH_R)
	return sm
end

local function wetNear(sampler, x, y, r)
	if T.isWater(sampler, x, y) then return true end
	if r and r > 0 then
		for k = 0, 7 do
			local a = k * math.pi / 4
			if T.isWater(sampler, x + cos(a) * r, y + sin(a) * r) then return true end
		end
	end
	return false
end

local function offEdge(style, x, y)
	return style.bounds ~= nil and MAP.nearEdge(style.bounds, x, y)
end

--- Graph edges lying along the indexed line (both ends and the midpoint within tol): length (m), list of { s0, s1 }
--- (arc spans on the line), count.
function L.builtAlong(g, ix, tol)
	local total, spans, n = 0, {}, 0
	if g == nil then return 0, spans, 0 end
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local da, sa = L.nearest(ix, a.x, a.y, tol)
			if da then
				local db, sb = L.nearest(ix, b.x, b.y, tol)
				if db and L.nearest(ix, (a.x + b.x) / 2, (a.y + b.y) / 2, tol) then
					total = total + G.dist(a.x, a.y, b.x, b.y)
					spans[#spans + 1] = { min(sa, sb), max(sa, sb) }
					n = n + 1
				end
			end
		end
	end
	return total, spans, n
end

--- Buildings (pts {x, y}) within r of the line where it is built (spans).
local function housesAlong(pts, ix, spans, r)
	local n = 0
	for _, p in ipairs(pts or {}) do
		local d, s = L.nearest(ix, p[1], p[2], r)
		if d then
			for _, sp in ipairs(spans) do
				if s >= sp[1] - 10 and s <= sp[2] + 10 then n = n + 1; break end
			end
		end
	end
	return n
end

--- Edges of this build (inc.edges) whose key starts with prefix.
local function incEdges(inc, prefix)
	local n = 0
	for _, e in ipairs(inc and inc.edges or {}) do
		if type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then n = n + 1 end
	end
	return n
end

--- true when a piece-like segment a-b has a graph edge along it (its midpoint within tol of a graph edge chord).
local function segBuilt(g, ax, ay, bx, by, tol)
	if g == nil then return false end
	local mx, my = (ax + bx) / 2, (ay + by) / 2
	for _, e in ipairs(g.edges) do
		local p, q = g.nodeById[e.n0], g.nodeById[e.n1]
		if p and q and G.pointSegDist(mx, my, p.x, p.y, q.x, q.y) <= tol then
			-- (and roughly parallel)
			local h1, h2 = G.heading(ax, ay, bx, by), G.heading(p.x, p.y, q.x, q.y)
			if G.lineAngleDiff(h1, h2) < math.rad(35) then return true end
		end
	end
	return false
end

--- m from the centre where a motif's corridor starts (the plan's pieces dropped beyond): the town's radius plus
--- DROP_BLOCKS blocks, so the plan's streets just outside the houses stay and link the motif's line to the town.
L.DROP_BLOCKS = 1.5
function L.dropFrom(style)
	local b = blk(style)
	return max(style.radius or 0, b) + L.DROP_BLOCKS * b
end

local function styleK(style)
	return L.GRID_STYLES[style.id] and L.GRID_K or 1
end

--- Soft valley score 0..1 of a dirRelief result (L.SOFT), and the lower side's rise (m).
function L.valleyScore(dr)
	if dr == nil then return 0, 0 end
	local lo = min(dr.sideA or 0, dr.sideB or 0)
	if lo <= L.SOFT[1] or lo < L.SOFT_K * (dr.level or 0) then return 0, lo end
	return G.clamp((lo - L.SOFT[1]) / L.SOFT[2], 0, 1) * G.clamp(1.5 - (dr.level or 0) / max(lo, 1), 0, 1), lo
end

--- Soft ridge score 0..1 (both sides lower), and the higher side's drop (m).
function L.ridgeScore(dr)
	if dr == nil then return 0, 0 end
	local lo = min(-(dr.sideA or 0), -(dr.sideB or 0))
	if lo <= L.SOFT[1] or lo < L.SOFT_K * (dr.level or 0) then return 0, lo end
	return G.clamp((lo - L.SOFT[1]) / L.SOFT[2], 0, 1) * G.clamp(1.5 - (dr.level or 0) / max(lo, 1), 0, 1), lo
end

---------------------------------------------------------------------------
-- hill climb

--- The uphill bearing from (cx, cy): the dry direction on a ring of RING m with the most rise (ties: seeded), and
--- that rise (m), or nil (flat / all water).
function L.uphill(sampler, cx, cy, seed)
	local h0 = T.height(sampler, cx, cy)
	local best, bv = nil, -math.huge
	for k = 0, 23 do
		local a = k / 24 * 2 * math.pi
		local x, y = cx + cos(a) * L.HC.RING, cy + sin(a) * L.HC.RING
		if not T.isWater(sampler, x, y) then
			local v = T.height(sampler, x, y) - h0 + 0.01 * rng.unit(seed or 1, "mhcBear", k)
			if v > bv then best, bv = a, v end
		end
	end
	if best == nil or bv < 4 then return nil, bv end
	return best, bv
end

--- Traces the easiest climb from (cx, cy) toward bearing: steps of STEP m, each the heading (within TURN of the last,
--- DEV of the bearing) whose rise is nearest the target grade, never over maxGrade, never onto or beside water.
--- Returns raw points and why it stopped ("top" | "steep" | "water" | "len" | "edge").
--- (M4 switchbacks: o.dev / o.turn / o.firstTurn / o.step override DEV / TURN / the first step's turn (DEV) / STEP; o.noTop
--- keeps going over level ground (a leg along the slope))
function L.traceClimb(sampler, cx, cy, bearing, o)
	local hc = L.HC
	local step = o.step or hc.STEP
	local devMax, turnMax = o.dev or hc.DEV, o.turn or hc.TURN
	local pts = { { cx, cy } }
	local x, y, h = cx, cy, bearing
	local z = T.height(sampler, x, y)
	local flat, why = 0, "len"
	local side = o.side or 1
	for _ = 1, floor(o.maxLen / step) do
		local best, bs, bz, bh = nil, math.huge, nil, nil
		-- (the first step may leave in any direction within DEV of the bearing: on a slope steeper than the target the
		-- climb starts across it)
		local turn = #pts == 1 and (o.firstTurn or devMax) or turnMax
		for k = -5, 5 do
			local dh = k * turn / 5
			local hh = h + dh * side
			if G.angleDiff(hh, bearing) <= devMax then
				local nx, ny = x + cos(hh) * step, y + sin(hh) * step
				if not wetNear(sampler, nx, ny, o.setback) and not (o.style and offEdge(o.style, nx, ny))
					and G.dist(cx, cy, nx, ny) <= o.extent then
					local nz = T.height(sampler, nx, ny)
					local gr = (nz - z) / step
					if abs(gr) <= o.maxGrade then
						local sc = abs(gr - o.grade) * 10 + abs(dh) * 0.15 + (gr < 0 and 1 or 0)
						if sc < bs then best, bs, bz, bh = { nx, ny }, sc, nz, hh end
					end
				end
			end
		end
		if best == nil then why = "steep"; break end
		if not o.noTop and (bz - z) / step < hc.FLAT then
			flat = flat + 1
			if flat >= 3 then
				-- (drop the level steps at the top)
				for _ = 1, 2 do if #pts > 2 then pts[#pts] = nil end end
				why = "top"
				break
			end
		else
			flat = 0
		end
		pts[#pts + 1] = best
		x, y, z, h = best[1], best[2], bz, bh
	end
	return pts, why
end

--- The hill climb's plan geometry for a style (pure): { line (smooth), why, bearing, terraces = { { s0, s1, side,
--- off } }, r0 } or nil, why.
function L.climbGeo(style, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local bearing = L.uphill(sampler, cx, cy, seed)
	if bearing == nil then return nil, "flat" end
	local maxSlope = style.maxSlope or 0.1
	local o = { maxLen = L.HC.MAX_LEN, extent = (extent or 1500), maxGrade = maxSlope * 0.9,
		grade = min(L.HC.GRADE, 0.6 * maxSlope), setback = style.waterSetback or 25, style = style,
		side = rng.unit(seed, "mhcSide") < 0.5 and 1 or -1 }
	local raw, why = L.traceClimb(sampler, cx, cy, bearing, o)
	if #raw < 4 then return nil, "short:" .. why end
	-- (2026-10-13 final test: Wirksworth's climb, traced at the target grade, smoothed to 120 m cut across the contours:
	-- grade 0.135 > maxSlope, the planner refused its pieces beyond 124 m of 833. A tighter smoothing (or none) when
	-- the smooth line comes out steeper than the climb may be)
	local line = nil
	for _, R in ipairs(L.HC.SMOOTH_TRY) do
		local cand = R > 0 and L.smooth(raw, R) or G.simplify(raw, 5, 25)
		if cand and #cand >= 2 and G.polyLen(cand) >= 120 then
			line = cand
			if T.pathMaxGrade(sampler, cand) <= o.maxGrade then break end
		end
	end
	if line == nil or G.polyLen(line) < 120 then return nil, "short:" .. why end
	local ix = L.index(line)
	local r0 = L.dropFrom(style)
	-- terraces: shelves beside the climb (beyond the core) whose ground is flat enough
	local off = G.clamp((style.block.depth or 60) * 0.9, 45, 80)
	local W = G.clamp((style.block.len or 80) * 1.1, 60, 110)
	local shelfMax = L.HC.SHELF * maxSlope
	local cands = {}
	local s = r0 + 20
	local guard = G.LOOP_CAP
	while s + W <= ix.len - 20 and guard > 0 do
		guard = guard - 1
		for _, sd in ipairs({ 1, -1 }) do
			local worst, wet = 0, false
			for _, f in ipairs({ 0, 0.5, 1 }) do
				local x, y, ux, uy = L.at(ix, s + f * W)
				local nx, ny = -uy * sd, ux * sd
				for _, d in ipairs({ off * 0.5, off }) do
					local px, py = x + nx * d, y + ny * d
					if wetNear(sampler, px, py, style.waterSetback or 25) or offEdge(style, px, py) then wet = true end
					local sl = T.slope(sampler, px, py, 6)
					if sl > worst then worst = sl end
				end
			end
			if not wet and worst <= shelfMax then cands[#cands + 1] = { s0 = s, s1 = s + W, side = sd, off = off, slope = worst } end
		end
		s = s + 20
	end
	table.sort(cands, function(p, q)
		if abs(p.slope - q.slope) > 1e-9 then return p.slope < q.slope end
		if p.s0 ~= q.s0 then return p.s0 < q.s0 end
		return p.side > q.side
	end)
	local want = L.HC.TERRACES[1] + floor(rng.unit(seed, "mhcTer") * (L.HC.TERRACES[2] - L.HC.TERRACES[1] + 1))
	local terraces = {}
	for _, c in ipairs(cands) do
		if #terraces >= want then break end
		local okGap = true
		for _, t in ipairs(terraces) do
			if c.s0 < t.s1 + L.HC.TERRACE_GAP and c.s1 > t.s0 - L.HC.TERRACE_GAP then okGap = false; break end
		end
		if okGap then terraces[#terraces + 1] = c end
	end
	table.sort(terraces, function(p, q) return p.s0 < q.s0 end)
	-- stats: height climbed, steepest grade along the smooth line
	local z0, zmax = T.height(sampler, cx, cy), -math.huge
	for _, p in ipairs(G.resample(line, 20)) do
		local z = T.height(sampler, p[1], p[2])
		if z > zmax then zmax = z end
	end
	return { line = line, ix = ix, why = why, bearing = bearing, terraces = terraces, r0 = r0, off = off,
		climb = zmax - z0, grade = T.pathMaxGrade(sampler, line), corridor = off + 25,
		wantTerraces = want }
end

local function climbPlan(mp, style, m, env)
	m.geo = nil
	if not L.ON then return end
	local geo, why = L.climbGeo(style, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local cx, cy = style.centre[1], style.centre[2]
	local corridor = geo.corridor
	local stops = {}
	for i, t in ipairs(geo.terraces) do
		stops[#stops + 1] = { s = t.s0, key = "mhc:T" .. i .. "a" }
		stops[#stops + 1] = { s = t.s1, key = "mhc:T" .. i .. "b" }
	end
	-- the climbing street: the plan's pieces in its corridor beyond the core dropped (the steep ground between the
	-- terraces stays green), crossing pieces end in a T on it (inside the core they keep the town's links to it)
	local r0 = geo.r0
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local function drop(x, y)
		if G.dist(cx, cy, x, y) < r0 then return false end
		return L.nearest(geo.ix, x, y, corridor) ~= nil
	end
	local res = L.layMain(mp, geo.line, { prefix = "mhc", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = m.id, class = "medium", costK = L.COST_MAIN, lead = true,
		every = 90, stops = stops, part = "climb", mid = 0, drop = drop }, anchors)
	-- terrace loops: two lanes off the climb and a back street on the shelf
	local made = 0
	for i, t in ipairs(geo.terraces) do
		local ka, kb = "mhc:T" .. i .. "a", "mhc:T" .. i .. "b"
		local ja, jb = mp.junctions[ka], mp.junctions[kb]
		if ja and jb then
			local back = {}
			local sub = L.sub(geo.ix, t.s0, t.s1)
			for _, p in ipairs(sub) do back[#back + 1] = { p[1] - p[4] * t.side * t.off, p[2] + p[3] * t.side * t.off } end
			local ta, tb = back[1], back[#back]
			local kta, ktb = "mhc:T" .. i .. "c", "mhc:T" .. i .. "d"
			mp.junctions[kta] = { ta[1], ta[2] }
			mp.junctions[ktb] = { tb[1], tb[2] }
			L.overlay(mp, { { ja[1], ja[2] }, { ta[1], ta[2] } }, { prefix = "mhcT" .. i .. "a", motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = ka, endKey = kta, part = "terrace", branch = "start", drop = drop })
			local bl = L.smooth(back, 80) or back
			L.overlay(mp, bl, { prefix = "mhcT" .. i .. "b", motif = m.id, class = "small", costK = L.COST_LANE,
				startKey = kta, endKey = ktb, part = "terrace", drop = drop })
			L.overlay(mp, { { tb[1], tb[2] }, { jb[1], jb[2] } }, { prefix = "mhcT" .. i .. "c", motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = ktb, endKey = kb, part = "terrace", branch = "end", drop = drop })
			t.back = bl
			made = made + 1
		end
	end
	geo.pieces, geo.cut, geo.terracesMade, geo.anchors, geo.links = res.pieces, res.cut, made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
	mp.motifGeo = mp.motifGeo or {}
	mp.motifGeo[m.id] = geo
end

local function climbMeasure(env, m)
	local geo = m.geo
	if geo == nil then
		return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") }
	end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	local sMax = 0
	for _, sp in ipairs(spans) do if sp[2] > sMax then sMax = sp[2] end end
	local climb = 0
	if env.sampler and sMax > 0 then
		local x0, y0 = L.at(geo.ix, 0)
		local z0 = T.height(env.sampler, x0, y0)
		for _, sp in ipairs(spans) do
			for _, s in ipairs({ sp[1], sp[2] }) do
				local x, y = L.at(geo.ix, s)
				local dz = T.height(env.sampler, x, y) - z0
				if dz > climb then climb = dz end
			end
		end
	end
	local ter = 0
	for _, t in ipairs(geo.terraces) do
		if t.back and #t.back >= 2 then
			local a, b = t.back[1], t.back[#t.back]
			local mx, my = G.polyAt(t.back, 0.5)
			if segBuilt(env.g, a[1], a[2], mx, my, 10) or segBuilt(env.g, mx, my, b[1], b[2], 10) then ter = ter + 1 end
		end
	end
	local houses = housesAlong(env.pts, geo.ix, spans, 45)
	local edges = incEdges(env.inc, "mhc")
	return { edges = edges, total = n, houses = houses, len = len, climb = climb, terraces = ter, reach = sMax,
		text = string.format("len=%.0f/%.0f,climb=%.0f/%.0f,grade=%.3f,terraces=%d/%d,stop=%s,anchors=%d/%d", len, geo.ix.len,
			climb, geo.climb, geo.grade, ter, #geo.terraces, geo.why, geo.anchors or 0, geo.links or 0) }
end

local function climbEligible(ctx)
	local t = ctx.terrain
	if t == nil or t.relief == nil then return 0, "noTerrain" end
	local hc = L.HC
	local range = (t.highZ or 0) - (t.lowZ or 0)
	local g = t.relief.grade
	local s = G.clamp((g - hc.ELIG_GRADE[1]) / (hc.ELIG_GRADE[2] - hc.ELIG_GRADE[1]), 0, 1)
	local vs = (t.meanSlope or 0) > 0.02 and L.valleyScore(t.dirRelief) or 0
	local valley = vs > s
	if valley then s = vs end
	s = s * G.clamp((range - hc.ELIG_RANGE[1]) / (hc.ELIG_RANGE[2] - hc.ELIG_RANGE[1]), 0, 1)
	if (t.meanSlope or 0) > 0.18 then s = s * 0.3 end   -- (steep everywhere: switchbacks, M4)
	if (ctx.tier or 2) >= 4 then s = s * 0.6 end
	s = s * styleK(ctx.style)
	if ctx.style.metro then s = 0 end
	local why = string.format("%s:grade=%.3f,range=%.0f", valley and "valley" or "slope", g, range)
	if s <= 0 then return 0, why end
	return s, why
end

---------------------------------------------------------------------------
-- valley fishbone

--- The valley floor through (cx, cy) along axis: both ways, each step the lowest of the headings within TURN of the
--- last (DEV of the axis), stopping at water, the extent, steep rises or HALF m. Returns raw points (one line through
--- the centre) and the arc length of the centre on it.
function L.traceFloor(sampler, cx, cy, axis, o)
	local vf = L.VF
	local halves = {}
	for side = 1, 2 do
		local dir = side == 1 and axis or axis + math.pi
		local pts = {}
		local x, y, h = cx, cy, dir
		local z = T.height(sampler, x, y)
		for _ = 1, floor(o.half / vf.STEP) do
			local best, bz, bh = nil, math.huge, nil
			for k = -4, 4 do
				local hh = h + k * vf.TURN / 4
				if G.angleDiff(hh, dir) <= vf.DEV then
					local nx, ny = x + cos(hh) * vf.STEP, y + sin(hh) * vf.STEP
					if not wetNear(sampler, nx, ny, o.setback) and not offEdge(o.style, nx, ny)
						and G.dist(cx, cy, nx, ny) <= o.extent then
						local nz = T.height(sampler, nx, ny) + abs(k) * 0.05
						if nz < bz then best, bz, bh = { nx, ny }, nz, hh end
					end
				end
			end
			if best == nil then break end
			local zz = T.height(sampler, best[1], best[2])
			if abs(zz - z) / vf.STEP > o.maxGrade then break end
			pts[#pts + 1] = best
			x, y, z, h = best[1], best[2], zz, bh
		end
		halves[side] = pts
	end
	local raw = {}
	for i = #halves[2], 1, -1 do raw[#raw + 1] = halves[2][i] end
	raw[#raw + 1] = { cx, cy }
	for _, p in ipairs(halves[1]) do raw[#raw + 1] = p end
	return raw, #halves[2], #halves[1]
end

function L.fishboneGeo(style, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local cx, cy = style.centre[1], style.centre[2]
	local dr = T.dirRelief(sampler, cx, cy, 600)
	if dr == nil or L.valleyScore(dr) <= 0 then return nil, "noValley" end
	local maxSlope = style.maxSlope or 0.1
	local raw, nb, na = L.traceFloor(sampler, cx, cy, dr.axis, { half = L.VF.HALF, extent = extent or 1500,
		setback = style.waterSetback or 25, style = style, maxGrade = maxSlope * 0.8 })
	if nb + na < 4 then return nil, "short" end
	local line = L.smooth(raw, 150)
	if line == nil then return nil, "short" end
	local ix = L.index(line)
	local _, sc = L.nearest(ix, cx, cy, 200)
	sc = sc or ix.len / 2
	local r0 = L.dropFrom(style)
	local sp = clampSpec(L.VF.RIB_SP, style.block.len or 80)
	local ribMax = clampSpec(L.VF.RIB_LEN, style.block.depth or 60)
	local ribGrade = L.VF.RIB_GRADE * maxSlope
	local ribs = {}
	for _, dirS in ipairs({ 1, -1 }) do
		local s = sc + dirS * (r0 + sp * 0.5)
		local guard = G.LOOP_CAP
		while s > 30 and s < ix.len - 30 and guard > 0 do
			guard = guard - 1
			local x, y, ux, uy = L.at(ix, s)
			for _, sd in ipairs({ 1, -1 }) do
				local nx, ny = -uy * sd, ux * sd
				local len, z = 0, T.height(sampler, x, y)
				for d = 10, ribMax, 10 do
					local px, py = x + nx * d, y + ny * d
					if wetNear(sampler, px, py, style.waterSetback or 25) or offEdge(style, px, py) then break end
					local pz = T.height(sampler, px, py)
					if abs(pz - z) / 10 > ribGrade then break end
					len, z = d, pz
				end
				if len >= L.VF.RIB_MIN then
					ribs[#ribs + 1] = { s = s, side = sd, len = len, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len }
				end
			end
			s = s + dirS * sp
		end
	end
	table.sort(ribs, function(p, q) if p.s ~= q.s then return p.s < q.s end return p.side > q.side end)
	return { line = line, ix = ix, axis = dr.axis, sc = sc, r0 = r0, ribs = ribs, sp = sp, ribMax = ribMax }
end

local function fishbonePlan(mp, style, m, env)
	m.geo = nil
	if not L.ON then return end
	local geo, why = L.fishboneGeo(style, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local cx, cy = style.centre[1], style.centre[2]
	local stops, byS = {}, {}
	for _, r in ipairs(geo.ribs) do
		local k = string.format("%.0f", r.s)
		if byS[k] == nil then
			byS[k] = { s = r.s, key = "mvf:R" .. k }
			stops[#stops + 1] = byS[k]
		end
		r.key = byS[k].key
	end
	local zone = geo.ribMax + 20
	local anchors = L.anchors(env.g, style, geo.ix, geo.sc, { 1, -1 }, env.terrain)
	local function fdrop(x, y)
		if G.dist(cx, cy, x, y) < geo.r0 then return false end
		local d, s = L.nearest(geo.ix, x, y, zone)
		return d ~= nil and abs(s - geo.sc) >= geo.r0
	end
	local res = L.layMain(mp, geo.line, { prefix = "mvf", approach = L.approach(style), teeK = L.COST_TEE, dense = L.dense(style), band = L.band(style), motif = m.id,
		class = "medium", costK = L.COST_MAIN, lead = true, every = 100, stops = stops, part = "spine", mid = geo.sc, dirs = 2,
		drop = function(x, y) return fdrop(x, y) end }, anchors)
	local made = 0
	for i, r in ipairs(geo.ribs) do
		if mp.junctions[r.key] then
			local j = mp.junctions[r.key]
			L.overlay(mp, { { j[1], j[2] }, { r.x1, r.y1 } }, { prefix = "mvfR" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = r.key, deadEnd = true, part = "rib", branch = "start", drop = fdrop })
			made = made + 1
		end
	end
	geo.pieces, geo.cut, geo.ribsMade, geo.anchors, geo.links = res.pieces, res.cut, made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function fishboneMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	local built, sides, ss = 0, { [1] = 0, [-1] = 0 }, {}
	for _, r in ipairs(geo.ribs) do
		local mx, my = (r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2
		if segBuilt(env.g, r.x0, r.y0, mx, my, 8) then
			built = built + 1
			sides[r.side] = sides[r.side] + 1
			ss[#ss + 1] = r.s
		end
	end
	-- (spacing: the median gap between built rib junctions along the spine; the core's gap is one of them)
	table.sort(ss)
	local gaps = {}
	for i = 2, #ss do if ss[i] - ss[i - 1] > 1 then gaps[#gaps + 1] = ss[i] - ss[i - 1] end end
	table.sort(gaps)
	local spacing = #gaps > 0 and gaps[math.floor((#gaps + 1) / 2)] or 0
	local houses = housesAlong(env.pts, geo.ix, spans, 45)
	return { edges = incEdges(env.inc, "mvf"), total = n, houses = houses, len = len, ribs = built,
		left = sides[1], right = sides[-1], spacing = spacing,
		text = string.format("spine=%.0f/%.0f,ribs=%d/%d,sides=%d+%d,spacing=%.0f,anchors=%d/%d", len, geo.ix.len, built,
			#geo.ribs, sides[1], sides[-1], spacing, geo.anchors or 0, geo.links or 0) }
end

local function fishboneEligible(ctx)
	local t = ctx.terrain
	local dr = t and t.dirRelief
	if dr == nil then return 0, "noRelief" end
	if (t.meanSlope or 0) <= 0.02 then return 0, string.format("flat:slope=%.3f", t.meanSlope or 0) end
	if t.water and t.water.kind == "river" then return 0, "river" end   -- (river towns: their banks)
	local s, lo = L.valleyScore(dr)
	s = s * styleK(ctx.style)
	if ctx.style.metro then s = 0 end
	local why = string.format("valley:sides=%.0f/%.0f,level=%.1f", dr.sideA or 0, dr.sideB or 0, dr.level or 0)
	if s <= 0 then return 0, why end
	return s, why
end

---------------------------------------------------------------------------
-- harbour crescent

--- The bay at a traced shore (stats.shore: water on the right of travel) nearest the town: { sA, sB (arc lengths of
--- the mouth), depth (m, the shore's deepest point inland of the mouth's chord), chord (m), ratio } or nil.
function L.bay(shore)
	if shore == nil or shore.pts == nil or #shore.pts < 4 then return nil end
	local pts, cum = shore.pts, shore.cum
	local n = #pts
	local s0 = shore.s0 or cum[shore.i0 or 1] or 0
	local Ltot = cum[n]
	local function idxAt(s)
		local lo, hi = 1, n
		while hi - lo > 1 do
			local mid = floor((lo + hi) / 2)
			if cum[mid] <= s then lo = mid else hi = mid end
		end
		return lo
	end
	local best = nil
	for dm = -300, 300, 100 do
		for w = 200, 700, 100 do
			local sa, sb = s0 + dm - w, s0 + dm + w
			if sa >= 0 and sb <= Ltot then
				local ia, ib = idxAt(sa), idxAt(sb)
				if ib - ia >= 3 then
					local a, b = pts[ia], pts[ib]
					local ux, uy, cl = unit(b[1] - a[1], b[2] - a[2])
					if cl >= L.HB.MIN_CHORD then
						local depth, neg = 0, 0
						for i = ia + 1, ib - 1 do
							-- left of the chord = the land side (water on the right of travel)
							local d = ux * (pts[i][2] - a[2]) - uy * (pts[i][1] - a[1])
							if d > depth then depth = d end
							if d < neg then neg = d end
						end
						local ratio = (depth + 0.5 * neg) / cl
						if best == nil or ratio > best.ratio + 1e-9 then
							best = { sA = cum[ia], sB = cum[ib], ia = ia, ib = ib, depth = depth, chord = cl, ratio = ratio }
						end
					end
				end
			end
		end
	end
	return best
end

local function shoreSub(shore, ia, ib)
	local out = {}
	for i = ia, ib do out[#out + 1] = { shore.pts[i][1], shore.pts[i][2] } end
	return out
end

--- Offsets a shore run (water on the right) inland by off: points left of travel, those on water or nearer the shore
--- than minClear dropped (the longest valid run kept).
local function offsetShore(run, off, sampler, sd, minClear)
	local runs, cur = {}, nil
	local n = #run
	for i = 1, n do
		local a, b = run[max(1, i - 1)], run[min(n, i + 1)]
		local tx, ty = unit(b[1] - a[1], b[2] - a[2])
		local x, y = run[i][1] - ty * off, run[i][2] + tx * off
		local okP = not (sampler and T.isWater(sampler, x, y))
		if okP and sd then
			local _, perp, wet = SH.shoreAt(sd, x, y)
			okP = not wet and perp >= minClear
		end
		if okP then
			cur = cur or {}
			cur[#cur + 1] = { x, y }
		elseif cur then
			runs[#runs + 1] = cur
			cur = nil
		end
	end
	if cur then runs[#runs + 1] = cur end
	local best, bl = nil, 0
	for _, r in ipairs(runs) do
		local l = #r >= 2 and G.polyLen(r) or 0
		if l > bl then best, bl = r, l end
	end
	return best
end

function L.harbourGeo(style, m, sampler)
	local t = m.terrainStats
	local shore = t and t.shore
	local bay = L.bay(shore)
	if bay == nil or bay.ratio < L.HB.MIN_RATIO then return nil, "noBay" end
	local sd = m.sd
	local setback = style.waterSetback or 25
	local off = setback + L.HB.MARGIN
	local run = shoreSub(shore, bay.ia, bay.ib)
	local o = offsetShore(run, off, sampler, sd, setback + 5)
	if o == nil or G.polyLen(o) < 120 then return nil, "noRoom" end
	local line = L.smooth(o, 90)
	if line == nil then return nil, "noRoom" end
	local ix = L.index(line)
	local sp = clampSpec(L.HB.LANE_SP, style.block.len or 80)
	local lane = clampSpec(L.HB.LANE_LEN, style.block.depth or 60)
	local lanes = {}
	local s = 25
	local guard = G.LOOP_CAP
	while s <= ix.len - 25 and guard > 0 do
		guard = guard - 1
		local x, y, ux, uy = L.at(ix, s)
		local nx, ny = -uy, ux   -- left of travel = inland
		local len = 0
		for d = 10, lane, 10 do
			local px, py = x + nx * d, y + ny * d
			if (sampler and (T.isWater(sampler, px, py) or T.slope(sampler, px, py, 6) > (style.maxSlope or 0.1)))
				or offEdge(style, px, py) then break end
			len = d
		end
		if len >= 35 then lanes[#lanes + 1] = { s = s, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len, len = len } end
		s = s + sp
	end
	return { line = line, ix = ix, bay = bay, lanes = lanes, off = off, lane = lane, run = run, sp = sp }
end

local function harbourPlan(mp, style, m, env)
	m.geo = nil
	if not L.ON then return end
	local geo, why = L.harbourGeo(style, m, env.terrain)
	if geo == nil then m.planWhy = why; return end
	local stops = {}
	for i, ln in ipairs(geo.lanes) do
		stops[#stops + 1] = { s = ln.s, key = "mhb:L" .. i }
		ln.key = "mhb:L" .. i
	end
	local _, sMid = L.nearest(geo.ix, style.centre[1], style.centre[2], 2000)
	sMid = sMid or geo.ix.len / 2
	local anchors = L.anchors(env.g, style, geo.ix, sMid, { 1, -1 }, env.terrain)
	local zone = geo.lane + 15
	local function hdrop(x, y, tee)
		local d, s, side = L.nearest(geo.ix, x, y, zone)
		if d == nil then return false end
		-- (between the crescent and the water always; the row behind it along the bay, except the streets meeting
		-- the crescent in a T: the links inland)
		if side < 0 then return true end
		return not tee and s > 5 and s < geo.ix.len - 5
	end
	local res = L.layMain(mp, geo.line, { prefix = "mhb", approach = L.approach(style), teeK = L.COST_TEE, dense = L.dense(style), band = L.band(style), motif = m.id,
		class = "medium", costK = L.COST_MAIN, lead = true, every = 90, stops = stops, part = "front", mid = sMid, dirs = 2,
		drop = hdrop }, anchors)
	local made = 0
	for i, ln in ipairs(geo.lanes) do
		local j = mp.junctions[ln.key]
		if j then
			L.overlay(mp, { { j[1], j[2] }, { ln.x1, ln.y1 } }, { prefix = "mhbL" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = ln.key, deadEnd = true, part = "lane", branch = "start", drop = hdrop })
			made = made + 1
		end
	end
	-- coverage of the bay's curve by the planned crescent
	local cov, tot = 0, 0
	for _, p in ipairs(G.resample(geo.run, 20)) do
		tot = tot + 1
		if L.nearest(geo.ix, p[1], p[2], geo.off + 20) then cov = cov + 1 end
	end
	geo.planCover = tot > 0 and cov / tot or 0
	geo.pieces, geo.cut, geo.lanesMade, geo.anchors, geo.links = res.pieces, res.cut, made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function harbourMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	-- share of the bay's curve covered by the built waterfront street
	local cov, tot = 0, 0
	for _, p in ipairs(G.resample(geo.run, 20)) do
		tot = tot + 1
		local d, s = L.nearest(geo.ix, p[1], p[2], geo.off + 20)
		if d then
			for _, sp in ipairs(spans) do
				if s >= sp[1] - 10 and s <= sp[2] + 10 then cov = cov + 1; break end
			end
		end
	end
	local lanes = 0
	for _, ln in ipairs(geo.lanes) do
		local mx, my = (ln.x0 + ln.x1) / 2, (ln.y0 + ln.y1) / 2
		if segBuilt(env.g, ln.x0, ln.y0, mx, my, 8) then lanes = lanes + 1 end
	end
	local cover = tot > 0 and cov / tot or 0
	local houses = housesAlong(env.pts, geo.ix, spans, 40)
	return { edges = incEdges(env.inc, "mhb"), total = n, houses = houses, len = len, cover = cover, lanes = lanes,
		text = string.format("front=%.0f/%.0f,cover=%.2f/%.2f,lanes=%d/%d,bay=%.2f,anchors=%d/%d", len, geo.ix.len, cover,
			geo.planCover, lanes, #geo.lanes, geo.bay.ratio, geo.anchors or 0, geo.links or 0) }
end

local function harbourEligible(ctx)
	local t = ctx.terrain
	if t == nil or not SH.shoreUsable(t) then return 0, "noShore" end
	if (t.water.distance or math.huge) > L.HB.ELIG_DIST then return 0, string.format("far:%.0f", t.water.distance or -1) end
	if ctx.style.shape and ctx.style.shape.id == "shore" then return 0, "shoreTown" end   -- (shore towns: their strip and row)
	local bay = L.bay(t.shore)
	if bay == nil then return 0, "noBay" end
	local s = G.clamp((bay.ratio - L.HB.MIN_RATIO) / (L.HB.FULL_RATIO - L.HB.MIN_RATIO), 0, 1)
	s = s * styleK(ctx.style)
	if ctx.style.metro then s = 0 end
	local why = string.format("bay:ratio=%.2f,chord=%.0f", bay.ratio, bay.chord)
	if s <= 0 then return 0, why end
	return s, why
end

---------------------------------------------------------------------------
-- fishing village

function L.villageGeo(style, m, sampler)
	local sd = m.sd
	if sd == nil or sampler == nil then return nil, "noShore" end
	local seed = style.seed or 1
	local setback = style.waterSetback or 25
	local off = setback + L.FV.MARGIN
	local sp = clampSpec(L.FV.SP, style.block.len or 80)
	local maxLen = clampSpec(L.FV.LEN, style.block.depth or 60)
	local nWant = L.FV.N[1] + floor(rng.unit(seed, "mfvN") * (L.FV.N[2] - L.FV.N[1] + 1))
	local r0 = max((style.radius or 0) * 0.8, 60)
	local width = (nWant - 1) * sp
	local shore = sd
	local Ltot = shore.L
	local pts, cum = shore.pts, shore.cum
	local n = #pts
	local function idxAt(s)
		local lo, hi = 1, n
		while hi - lo > 1 do
			local mid = floor((lo + hi) / 2)
			if cum[mid] <= s then lo = mid else hi = mid end
		end
		return lo
	end
	local maxGrade = L.FV.GRADE * (style.maxSlope or 0.1)
	local function tryDir(dirS)
		local sA = sd.s0
		local sB = sd.s0 + dirS * (r0 + width + 40)
		if sB < 0 or sB > Ltot then return nil end
		local ia, ib = idxAt(min(sA, sB)), min(n, idxAt(max(sA, sB)) + 1)
		if ib - ia < 2 then return nil end
		local run = shoreSub(shore, ia, ib)
		local o = offsetShore(run, off, sampler, sd, setback + 5)
		if o == nil or G.polyLen(o) < r0 + width then return nil end
		if dirS < 0 then
			local rev = {}
			for i = #o, 1, -1 do rev[#rev + 1] = o[i] end
			o = rev
		end
		local line = L.smooth(o, 100)
		if line == nil then return nil end
		local ix = L.index(line)
		-- one heading for every street: uphill, within TOWARD of the inland normal at the village's middle
		local mx, my, ux, uy = L.at(ix, min(ix.len, r0 + width / 2))
		local nx, ny = -uy * dirS, ux * dirS
		if sampler and T.isWater(sampler, mx + nx * 30, my + ny * 30) then nx, ny = -nx, -ny end
		local up = G.atan2(ny, nx)
		local gh = T.downhill(sampler, mx + nx * 40, my + ny * 40)
		if gh then
			local u = G.wrap(gh + math.pi)
			if G.angleDiff(u, up) <= math.rad(35) then up = u end
		end
		local hx, hy = cos(up), sin(up)
		local streets = {}
		local score = 0
		for k = 0, nWant - 1 do
			local s = r0 + 20 + k * sp
			if s <= ix.len - 10 then
				local x, y = L.at(ix, s)
				local len, z = 0, T.height(sampler, x, y)
				for d = 10, maxLen, 10 do
					local px, py = x + hx * d, y + hy * d
					if wetNear(sampler, px, py, setback) or offEdge(style, px, py) then break end
					local pz = T.height(sampler, px, py)
					if abs(pz - z) / 10 > maxGrade then break end
					len, z = d, pz
				end
				if len >= L.FV.MIN_LEN then
					streets[#streets + 1] = { s = s, x0 = x, y0 = y, x1 = x + hx * len, y1 = y + hy * len, len = len }
					score = score + len
				end
			end
		end
		if #streets < 2 then return nil end
		return { line = line, ix = ix, streets = streets, heading = up, dir = dirS, score = score, off = off, sp = sp,
			maxLen = maxLen, want = nWant, r0 = r0 }
	end
	local a, b = tryDir(1), tryDir(-1)
	local pickA = rng.unit(seed, "mfvDir") < 0.5
	local geo
	if a and b then
		if abs(a.score - b.score) < 0.15 * max(a.score, b.score) then geo = pickA and a or b
		else geo = a.score > b.score and a or b end
	else
		geo = a or b
	end
	if geo == nil then return nil, "noRoom" end
	return geo
end

local function villagePlan(mp, style, m, env)
	m.geo = nil
	if not L.ON then return end
	local geo, why = L.villageGeo(style, m, env.terrain)
	if geo == nil then m.planWhy = why; return end
	local stops = {}
	for i, st in ipairs(geo.streets) do
		stops[#stops + 1] = { s = st.s, key = "mfv:S" .. i }
		st.key = "mfv:S" .. i
	end
	local first, last = geo.streets[1].s, geo.streets[#geo.streets].s
	local hx, hy = cos(geo.heading), sin(geo.heading)
	local x0, y0 = L.at(geo.ix, first)
	local function vdrop(x, y)
		-- the village block: between the first and last street (+ half a spacing), from the water up the streets
		local d, s = L.nearest(geo.ix, x, y, geo.maxLen + 30)
		if d == nil then return false end
		if s < first - geo.sp * 0.5 or s > last + geo.sp * 0.5 then return false end
		local up = (x - x0) * hx + (y - y0) * hy
		return up < geo.maxLen + 20
	end
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mfv", approach = L.approach(style), teeK = L.COST_TEE, dense = L.dense(style), band = L.band(style), motif = m.id,
		class = "small", costK = L.COST_MAIN, lead = true, every = 80, stops = stops, part = "front", mid = 0,
		drop = vdrop }, anchors)
	local made = 0
	for i, st in ipairs(geo.streets) do
		local j = mp.junctions[st.key]
		if j then
			L.overlay(mp, { { j[1], j[2] }, { st.x1, st.y1 } }, { prefix = "mfvS" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, lead = true, startKey = st.key, deadEnd = true, every = 70,
				part = "street", branch = "start", drop = vdrop })
			made = made + 1
		end
	end
	geo.pieces, geo.cut, geo.made, geo.anchors, geo.links = res.pieces, res.cut, made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function villageMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	local down, dlen = 0, 0
	for _, st in ipairs(geo.streets) do
		local ix = L.index({ { st.x0, st.y0 }, { st.x1, st.y1 } })
		local l = L.builtAlong(env.g, ix, 6)
		-- (reaching the waterfront: a built piece at its bottom)
		if l > 0 and segBuilt(env.g, st.x0, st.y0, st.x0 + (st.x1 - st.x0) * 0.3, st.y0 + (st.y1 - st.y0) * 0.3, 8) then
			down = down + 1
			dlen = dlen + l
		end
	end
	local houses = housesAlong(env.pts, geo.ix, spans, 40)
	return { edges = incEdges(env.inc, "mfv"), total = n, houses = houses, len = len, streets = down, streetLen = dlen,
		text = string.format("front=%.0f/%.0f,streets=%d/%d,len=%.0f,heading=%.0f,anchors=%d/%d", len, geo.ix.len, down,
			#geo.streets, dlen, math.deg(geo.heading), geo.anchors or 0, geo.links or 0) }
end

local function villageEligible(ctx)
	local t = ctx.terrain
	if t == nil or not SH.shoreUsable(t) or t.relief == nil then return 0, "noShore" end
	local dist = t.water.distance or math.huge
	if dist > L.FV.ELIG_DIST then return 0, string.format("far:%.0f", dist) end
	if ctx.style.shape and ctx.style.shape.id == "shore" then return 0, "shoreTown" end
	-- the slope falls toward the water
	local off = G.angleDiff(t.relief.dir, t.water.dir)
	if off > L.FV.TOWARD then return 0, string.format("notToward:%.0f", math.deg(off)) end
	local fg = L.FV.ELIG_GRADE
	local s = G.clamp((t.relief.grade - fg[1]) / (fg[2] - fg[1]), 0, 1)
	local tier = ctx.tier or 2
	if tier >= 4 then return 0, "big" end
	if tier == 3 then s = s * 0.4 end
	if (ctx.year or 1900) >= 1950 then s = s * 0.6 end
	s = s * styleK(ctx.style)
	if ctx.style.metro then s = 0 end
	local why = string.format("slopingShore:grade=%.3f,water=%.0f", t.relief.grade, dist)
	if s <= 0 then return 0, why end
	return s, why
end

-- harbour / village style hook: the shore data (the traced shore) on the record, the promenade (ot_shore) replaced by the
-- motif's own waterfront street, streets near the water first
local function shoreStyle(p, m, env)
	local t = env.terrain
	m.terrainStats = t
	if t == nil or not SH.shoreUsable(t) then return end
	local sd = (p.waterPremium and p.waterPremium.shore) or SH.shoreData(t, p.centre, p.block.depth, env.feats and env.feats.island)
	m.sd = sd
	if sd == nil then return end
	if p.shoreFront then
		p.shoreFront = nil
		m.replaced = "shoreFront"
	end
	if p.waterPremium == nil then p.waterPremium = { gain = 0.2, band = 250, shore = sd } end
end

--- DevelopAt points (the driver's motif dose, ot_driver fillPoints): beside the build's edges on the harbour crescent,
--- on the land side, off m apart from the street; at most n.
local function harbourDose(m, edges, off, n)
	local geo = m.geo
	local out = {}
	if geo == nil then return out end
	for _, e in ipairs(edges or {}) do
		if e.p0 and e.p1 then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			local d, s = L.nearest(geo.ix, mx, my, 10)
			if d then
				local x, y, ux, uy = L.at(geo.ix, s)
				out[#out + 1] = { s = s, x = x - uy * off, y = y + ux * off }
			end
		end
	end
	table.sort(out, function(a, b) return a.s < b.s end)
	local pts = {}
	local k = min(n, #out)
	for i = 1, k do
		local c = out[max(1, min(#out, floor((i - 0.5) * #out / k) + 1))]
		pts[#pts + 1] = { G.round(c.x, 1), G.round(c.y, 1) }
	end
	return pts
end

---------------------------------------------------------------------------

-- (shared with the road motifs, ot_motif_road M2)
L.wetNear, L.offEdge, L.housesAlong, L.incEdges, L.segBuilt, L.styleK, L.blk, L.clampSpec =
	wetNear, offEdge, housesAlong, incEdges, segBuilt, styleK, blk, clampSpec

--- Registers the M1 kinds (append order = their save indices after crescent / hill_road).
function L.registerAll(MO)
	-- (group: one motif per group and town: the climb and the fishbone both lay the town's main street on its slope /
	-- floor, the harbour and the village both its waterfront)
	MO.register({ id = "hill_climb", group = "land", eligible = climbEligible, plan = climbPlan, measure = climbMeasure })
	MO.register({ id = "valley_fishbone", group = "land", eligible = fishboneEligible, plan = fishbonePlan,
		measure = fishboneMeasure })
	MO.register({ id = "harbour_crescent", group = "shore", eligible = harbourEligible, style = shoreStyle,
		plan = harbourPlan, measure = harbourMeasure, dose = harbourDose })
	MO.register({ id = "fishing_village", group = "shore", eligible = villageEligible, style = shoreStyle,
		plan = villagePlan, measure = villageMeasure })
end

return L
