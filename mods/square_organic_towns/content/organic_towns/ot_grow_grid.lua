-- Organic Towns: grid growth (NA grid, NA suburb outer zone, MED ensanche, JP dense, Nordic, superblock).
-- Pure. The master plan is a lattice on the town axis: line spacing block.len (along the axis) x block.depth,
-- each spacing varied by block.sd from a hash of (seed, line index), so the plan never changes between calls,
-- and never below ot_style.MIN_BLOCK; node positions jittered for low gridness (strict grids: none). Arterial
-- lines every `arterialEvery` blocks (the lines through the origin are the main streets), collectors half way.
-- Beyond the outer-zone radius (NA suburb; in a curvyLocal profile everywhere) some cross streets become
-- cul-de-sacs (never on two neighbouring lines) and, unless the core is a strict grid, pieces curve gently.
-- Superblocks (style.sub): the lattice is the arterial grid and each cell gets interior local streets.
-- Clusters (style.cluster with style.sub, Nordic since the Showcase v9 round): the cell lines are curving collector
-- loops (each cell side bowed by cluster.bow x its length, no junction jitter), and the cells hold no through
-- streets, only short cul-de-sacs from the loops (cluster.depth x the cell depth, staggered from both sides: small
-- clusters of houses around dead-end streets, Scandinavian post-war suburbs); a seeded share cluster.green of the
-- cells (never the four around the centre) stays without any, a meadow / forest patch inside its loop.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local S = ug_require "square_organic_towns::/organic_towns/ot_select.lua"
local style_ = ug_require "square_organic_towns::/organic_towns/ot_style.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

M.LINE_RADIUS = 80   -- m: curve target of lattice lines through jittered nodes (as ot_grow_organic)

local floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs

--- Line positions 0, +/-1 ... +/-n with spacing base * (1 + sd * noise), at least minGap.
function M.lines(seed, tag, base, sd, n, minGap)
	minGap = minGap or style_.MIN_BLOCK
	local pos = { [0] = 0 }
	for i = 1, n do
		local f = 1 + sd * (rng.unit(seed, tag, i) * 2 - 1) * 1.7
		pos[i] = pos[i - 1] + max(minGap, base * max(0.5, f))
		local fb = 1 + sd * (rng.unit(seed, tag, -i) * 2 - 1) * 1.7
		pos[-i] = pos[-i + 1] - max(minGap, base * max(0.5, fb))
	end
	return pos
end
local lines = M.lines

--- Shifts all line positions so the one nearest `target` lands on it.
local function alignLines(pos, n, target)
	local best, bd = 0, math.huge
	for i = -n, n do
		local d = abs(pos[i] - target)
		if d < bd then best, bd = i, d end
	end
	local delta = target - pos[best]
	for i = -n, n do pos[i] = pos[i] + delta end
end

--- Class of lattice line i: the line through the origin and every `every`-th line main (arterials); collector
--- (medium) lines every `coll` lines when given, else half way between the arterials when every >= 4.
local function lineClass(i, every, isOrigin, coll, originClass)
	if isOrigin then return originClass or "main" end
	if every and every > 0 and i % every == 0 then return "main" end
	if coll and coll > 0 then
		if i % coll == 0 then return "medium" end
	elseif every and every >= 4 and i % every == floor(every / 2) then
		return "medium"
	end
	return "small"
end
M.lineClass = lineClass

--- Fine line positions for a subdivided lattice (style.sub): `n` lines per interval of `pos` (indices -m..m),
--- evenly spaced; fine index i * n + k. Returns the fine table and its index bound.
local function subLines(pos, m, n)
	local out = {}
	for i = -m, m - 1 do
		for k = 0, n - 1 do out[i * n + k] = pos[i] + (pos[i + 1] - pos[i]) * k / n end
	end
	out[m * n] = pos[m]
	return out, m * n
end

M.MAX_EXTENT = 8000    -- m: a master plan never reaches farther (hang guard; ot_core caps at 6400)

--- Master plan around the style centre covering `extent` metres.
--- opts = { extent, origin = {x, y} (a lattice node lands here; default centre), terrain stats `water`
---          (aligns a lattice line with the shore setback) }
function M.masterPlan(style, opts)
	opts = opts or {}
	local L, D = style.block.len, style.block.depth
	local seed = style.seed or 1
	local extent = opts.extent or 600
	-- (hang fix 2026-10-13: a NaN / endless extent or block never makes an endless lattice)
	if not (extent > 0 and extent <= M.MAX_EXTENT) then extent = (extent and extent > M.MAX_EXTENT) and M.MAX_EXTENT or 600 end
	if not (L and L >= 10) then L = 10 end
	if not (D and D >= 10) then D = 10 end
	local nu, nv = ceil(extent / L) + 1, ceil(extent / D) + 1
	local u = lines(seed, "u", L, style.block.sd, nu)
	local v = lines(seed, "v", D, style.block.sd, nv)
	local origin = opts.origin or style.centre
	local ax = style.axis or 0
	local ca, sa = math.cos(ax), math.sin(ax)
	local water = opts.water
	if water and water.distance then
		-- a lattice line (along the axis) at the setback in front of the shore: the waterfront street
		local wx, wy = math.cos(water.dir), math.sin(water.dir)
		local proj = (wx * -sa + wy * ca)        -- water direction on the local v axis
		if abs(proj) > 0.5 then
			local target = (water.distance - style.waterSetback) * (proj > 0 and 1 or -1)
			alignLines(v, nv, target)
		end
	end
	-- superblocks (style.sub): the lattice above is the arterial grid; local streets subdivide each cell
	local sub = style.sub
	local su, sv = 1, 1
	local cu, cv = u, v          -- cell (arterial) lines
	if sub then
		su, sv = sub.u or 1, sub.v or 1
		u, nu = subLines(cu, nu, su)
		v, nv = subLines(cv, nv, sv)
	end
	local crossAt = {}           -- [strip + 1][fine u offset] = true
	if sub then
		for s_ = 1, sv do
			crossAt[s_] = {}
			for _, k in ipairs((sub.cross or {})[s_] or {}) do crossAt[s_][k] = true end
		end
	end
	local strict = (style.gridness or 1) >= style_.STRICT_GRID
	local jitterAmp = min(L, D) * (0.15 * (1 - (style.gridness or 1)) + 0.5 * math.tan(math.rad(style.jitter or 0)))
	if strict then jitterAmp = 0 end
	local cluster = sub and style.cluster or nil
	if cluster then jitterAmp = 0 end
	-- cluster loops: the bow of row j between cell columns c and c + 1 (signed, m), seeded per cell side
	local function bowOf(tag, c, j)
		return (cluster.bow or 0.12) * L * (rng.unit(seed, tag, c, j) < 0.5 and -1 or 1)
	end
	local function world(i, j)
		local uu, vv = u[i], v[j]
		if cluster and i % su ~= 0 then
			local c = floor(i / su)
			local t = (i - c * su) / su
			vv = vv + bowOf("bowH", c, j) * math.sin(math.pi * t)
		end
		if jitterAmp > 0 and i ~= 0 and j ~= 0 then
			uu = uu + jitterAmp * (rng.unit(seed, "ju", i, j) * 2 - 1)
			vv = vv + jitterAmp * (rng.unit(seed, "jv", i, j) * 2 - 1)
		end
		return origin[1] + uu * ca - vv * sa, origin[2] + uu * sa + vv * ca
	end
	local artU = style.arterialEvery or 0                                   -- vertical lines, spaced L
	local artV = artU > 0 and max(1, floor(artU * L / D + 0.5)) or 0        -- horizontal lines, spaced D
	local collU = style.collectorEvery
	local collV = collU and collU > 0 and max(1, floor(collU * L / D + 0.5)) or nil
	if sub then
		-- cell lines: every `art`-th main, the others collectors
		artU = sub.art or 1
		artV = max(1, floor(artU * L / D + 0.5))
		collU, collV = 1, 1
	end
	local mp = { junctions = {}, pieces = {}, u = u, v = v, su = su, sv = sv, origin = { origin[1], origin[2] } }
	-- cul-de-sacs on every other cross line (never two facing each other): the odd ones when collectors (medium,
	-- never cul-de-sacs) take the even lines
	mp.culParity = (collU and collU % 2 == 0) and 1 or 0
	local cx, cy = style.centre[1], style.centre[2]
	local function jkey(i, j)
		local k = "g" .. i .. ":" .. j
		if mp.junctions[k] == nil then
			local x, y = world(i, j)
			mp.junctions[k] = { x, y }
		end
		return k
	end
	-- jittered lattices: one tangent through each lattice node along its line (the bisector of the two chords
	-- meeting there), so two pieces of a line meet without a kink where no cross street joins (yet). Only where
	-- the half kink fits the shorter chord at the curve limit (L / (6 x 80 m), conservative for an S-shaped
	-- piece); elsewhere the node keeps the plain corner (nil: each piece uses its chord).
	local function nodeDir(prev, cur, nxt)
		local ax, ay, la = G.unit(cur[1] - prev[1], cur[2] - prev[2])
		local bx, by, lb = G.unit(nxt[1] - cur[1], nxt[2] - cur[2])
		local dx, dy = G.unit(ax + bx, ay + by)
		if la <= 0 or lb <= 0 or (dx == 0 and dy == 0) then return nil end
		local half = math.acos(G.clamp(ax * dx + ay * dy, -1, 1))
		if half > math.min(la, lb) / (6 * M.LINE_RADIUS) then return nil end
		return { dx, dy }
	end
	local function lineDir(i, j, di, dj)
		if u[i - di] == nil or v[j - dj] == nil or u[i + di] == nil or v[j + dj] == nil then return nil end
		return nodeDir({ world(i - di, j - dj) }, { world(i, j) }, { world(i + di, j + dj) })
	end
	local function addPiece(key, ka, kb, class, horizontal, lineIdx, ends)
		local a, b = mp.junctions[ka], mp.junctions[kb]
		local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		local d = G.dist(cx, cy, mx, my)
		if d > extent then return end
		local z = style_.zone(style, d)
		local pts = { { a[1], a[2] }, { b[1], b[2] } }
		local curved = false
		if (z ~= style or z.curvyLocal) and class == "small" then
			-- outer zone: cul-de-sacs instead of some cross streets, gentle curves on the others
			-- (only on even lines, so two cul-de-sacs never face each other across a block)
			if not horizontal and lineIdx % 2 == mp.culParity and rng.unit(seed, "cul", key) < (z.deadEnds or 0) then
				local ck = "c" .. key
				local f = 0.55
				mp.junctions[ck] = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f }
				mp.pieces[#mp.pieces + 1] = { key = key, a = ka, b = ck,
					pts = { { a[1], a[2] }, mp.junctions[ck] }, class = "small", zone = z.id, culDeSac = true }
				return
			end
			local l = G.dist(a[1], a[2], b[1], b[2])
			local amp = l * 0.25 * math.sin(math.rad(z.curve or 0) / 2) * (rng.unit(seed, "bend", key) * 2 - 1)
			if not strict and abs(amp) > 1 then
				local nx, ny = -(b[2] - a[2]) / l, (b[1] - a[1]) / l
				pts = { pts[1], { mx + nx * amp, my + ny * amp }, pts[2] }
				curved = true
			end
		end
		if cluster and not horizontal and lineIdx % su == 0 and not curved then
			-- a cluster loop's cross side: bowed through its midpoint (the rows bow through their fine points)
			local l = G.dist(a[1], a[2], b[1], b[2])
			if l > 1 then
				local amp = bowOf("bowV", lineIdx, ends and ends[2] or 0) * 0.6
				local nx, ny = -(b[2] - a[2]) / l, (b[1] - a[1]) / l
				pts = { pts[1], { mx + nx * amp, my + ny * amp }, pts[2] }
				curved = true
			end
		end
		local pc = { key = key, a = ka, b = kb, pts = pts, class = class, curved = curved, zone = z.id }
		if (jitterAmp > 0 or cluster) and not curved and ends then
			local di, dj = ends[3] - ends[1], ends[4] - ends[2]
			pc.dirA = lineDir(ends[1], ends[2], di, dj)
			pc.dirB = lineDir(ends[3], ends[4], di, dj)
		end
		mp.pieces[#mp.pieces + 1] = pc
	end
	-- class of fine line i (cell lines by the arterial pattern, interior lines local)
	local function classOf(i, n, every, coll, originClass)
		if i % n ~= 0 then return "small" end
		local c = floor(i / n + 0.5)
		return lineClass(c, every, c == 0, coll, originClass)
	end
	-- a cross street on fine column i (not a cell line) in the strip from row j to j + 1?
	local function crossing(i, j)
		local k = i % su
		return k == 0 or crossAt[j % sv + 1][k] == true
	end
	-- clusters: is cell (column c, row s) a green one (no cul-de-sacs)? the four cells around the centre never
	local function greenCell(c, s_)
		if (c == 0 or c == -1) and (s_ == 0 or s_ == -1) then return false end
		return rng.unit(seed, "gcell", c, s_) < (cluster.green or 0)
	end
	-- clusters: a cul-de-sac on fine column i in strip s (rows s .. s + 1) from the bottom row (odd offsets) or the
	-- top row (even offsets): "bottom" | "top" | nil
	local function culIn(i, s_)
		if not cluster then return nil end
		local k = i % su
		if k == 0 or s_ < -nv or s_ >= nv then return nil end
		if greenCell(floor(i / su), s_) then return nil end
		return (k % 2 == 1) and "bottom" or "top"
	end
	-- does a cul-de-sac meet row j at fine column i (from the strip above or below)?
	local function culAtRow(i, j)
		return culIn(i, j) == "bottom" or culIn(i, j - 1) == "top"
	end
	for j = -nv, nv do
		local class = classOf(j, sv, artV, collV)
		local i = -nu
		while i < nu do
			-- the next junction along the row: where a cross street meets it (superblocks: interior split points
			-- without a cross street would only make two-street nodes the dead-end joins can't use later)
			local i2 = i + 1
			if sub then
				while i2 < nu and not ((j > -nv and crossing(i2, j - 1)) or (j < nv and crossing(i2, j)) or culAtRow(i2, j)) do
					i2 = i2 + 1
				end
			end
			addPiece("h" .. i .. ":" .. j, jkey(i, j), jkey(i2, j), class, true, j, { i, j, i2, j })
			i = i2
		end
	end
	for i = -nu, nu do
		-- the cross axis (through the origin, across the town axis): a collector in the late hierarchy
		-- (style.crossAxis), the main street along the axis stays the arterial
		local class = classOf(i, su, artU, collU, style.crossAxis)
		for j = -nv, nv - 1 do
			-- superblock interior: a cross street only where the pattern puts one in this strip
			if crossing(i, j) then
				addPiece("v" .. i .. ":" .. j, jkey(i, j), jkey(i, j + 1), class, false, i, { i, j, i, j + 1 })
			else
				local side = culIn(i, j)
				if side then
					-- a cluster's cul-de-sac from its loop into the cell
					local from = jkey(i, side == "bottom" and j or j + 1)
					local a, b = mp.junctions[from], { world(i, side == "bottom" and j + 1 or j) }
					local f = cluster.depth or 0.42
					local ex, ey = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
					local mx, my = (a[1] + ex) / 2, (a[2] + ey) / 2
					if G.dist(cx, cy, mx, my) <= extent then
						local key = "q" .. i .. ":" .. j
						local ck = "c" .. key
						mp.junctions[ck] = { ex, ey }
						mp.pieces[#mp.pieces + 1] = { key = key, a = from, b = ck, pts = { { a[1], a[2] }, { ex, ey } },
							class = "small", zone = style.id, culDeSac = true }
					end
				end
			end
		end
	end
	return mp
end

--- Share of the graph's junction and dead-end nodes (degree ~= 2; split points along a street don't count)
--- lying on a junction of the plan (within snapR). 1 for a graph without such nodes.
function M.matchShare(g, mp, snapR)
	local idx = S.junctionIndex(mp)
	local hit, total = 0, 0
	for _, n in ipairs(g.nodes) do
		if OG.degree(g, n.id) ~= 2 then
			total = total + 1
			if OG.nearestNode(idx, n.x, n.y, snapR) then hit = hit + 1 end
		end
	end
	if total == 0 then return 1 end
	return hit / total
end

--- Extent the master plan must cover for the current graph.
function M.extentFor(g, style)
	local cx, cy = style.centre[1], style.centre[2]
	local r = (#g.nodes > 0) and OG.radius(g, cx, cy, 1.0) or 0
	return r + (2 + (style.lead or 1)) * max(style.block.len, style.block.depth)
end

--- Master plan for the town: the fresh plan (centre-anchored, shore-aligned) while the town's junction nodes
--- sit on it (a town we grew); else (engine streets) a lattice node on the node nearest the centre, so the plan
--- follows the town. opts = { stats (ot_terrain.stats), snapR, extent }.
function M.planFor(g, style, opts)
	opts = opts or {}
	local extent = opts.extent or M.extentFor(g, style)
	local water = opts.stats and opts.stats.water or nil
	if style.frame and style.frame.origin then
		-- saved frame (the town's first increment fixed it): same lattice every time
		local mp = M.masterPlan(style, { extent = extent, origin = style.frame.origin })
		mp.anchored = true
		return mp
	end
	local mp = M.masterPlan(style, { extent = extent, water = water })
	if #g.nodes > 0 and M.matchShare(g, mp, opts.snapR or 8) < 0.5 then
		local n = OG.nearestNode(g, style.centre[1], style.centre[2], math.huge)
		mp = M.masterPlan(style, { extent = extent, origin = { n.x, n.y } })
		mp.anchored = true
	end
	return mp
end

--- Plans the next grid increment for a town.
--- opts = { terrain (sampler), stats (ot_terrain.stats, for the waterfront line), maxEdges, maxSeg, snapR,
---          incSeed, extent, exclude, cache, mp (a plan from planFor to reuse) }
--- Returns streets (ot_plan input), master plan, select report.
function M.grow(g, style, opts)
	opts = opts or {}
	local mp = opts.mp or M.planFor(g, style, opts)
	local streets, report = S.select(g, mp, style, opts)
	return streets, mp, report
end

return M
