-- Organic Towns: waterfront streets along a traced shoreline (pure). Shore towns, 2026-10-12 (PLAN.md 6.3 "Shore
-- towns").
--
-- User: "I want to emphasise being able to have some coastal towns prefer spreading across the coastline, similar to
-- how high real estate can be on the coast ... lakes also act like this in real life." A shore town (ot_form "shore",
-- ot_shape "shore") grows as a strip along the water; this module gives its master plan the street that makes it read
-- so: a waterfront street (promenade) at a setback from the shore that follows the shoreline's curve, and behind it a
-- row of small blocks (a back street parallel to it, short cross streets between the two every RUNG x block length),
-- denser than the style's blocks inland. The style's own plan is cut at the back street (pieces cross it in a T, the
-- parts between it and the water are dropped). New coast / lake towns with another form get the promenade alone (the
-- plan cut at it, no row): style.shoreFront = { sd = ot_shape shore data, row = bool, class }.
--
-- The promenade: the traced shore offset inland by waterSetback + MARGIN (the planner's water check, ot_terrain.wetAlong,
-- looks waterSetback to each side), only within the plan's extent, smoothed to a radius of at least SMOOTH_R (a medium
-- street within the straight-wide limits on gentle shores; ot_core.straightWide narrows it to small where it bends
-- more), split where it would come nearer than waterSetback + 5 m to the shore (tight bays, headlands) or onto water.
-- Plain plan pieces like any other: the selector, the housed front / arm fill, the planner's checks and the proposal's
-- node handling apply unchanged. Not saved: derived from the terrain each session like the plan.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"

local S = {}

S.ON = true
S.MARGIN = 12            -- m beyond waterSetback: the promenade's distance from the traced shore
S.SMOOTH_R = 180         -- m: smallest radius the promenade is smoothed to (where it has room)
S.SAMPLE = 10            -- m between the dense promenade points
S.MIN_LINE = 150         -- m: shorter promenade runs are left out
S.ROW = { 0.9, 40, 75 }  -- back street: x block depth, clamped (m)
S.RUNG = { 0.8, 50, 120 } -- cross streets between promenade and back street: every x block length, clamped (m)
S.SNAP = 15              -- m: a plan street crossing the back street this near a cross street's junction joins it
S.END_GAP = 20           -- m: no cross street this near a line's end

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local function unit(x, y)
	local l = sqrt(x * x + y * y)
	if l < 1e-9 then return 0, 0 end
	return x / l, y / l
end

--- Dense points (every S.SAMPLE m, with unit tangents) of a smooth polyline.
local function dense(pts)
	local dirs, cum = G.polyDirs(pts)
	local L = cum[#cum]
	local n = max(1, math.ceil(L / S.SAMPLE))
	local out = {}
	for k = 0, n do
		local x, y, ux, uy = G.frameAt(pts, dirs, cum, L * k / n)
		out[#out + 1] = { x, y, ux, uy }
	end
	return out
end

--- Runs of the shoreline within `extent` of the centre: lists of shore points (the run through the foot first).
local function shoreRuns(sd, cx, cy, extent)
	local pts = sd.pts
	local n = #pts
	local inside = {}
	local all = true
	for i = 1, n do
		inside[i] = G.dist(cx, cy, pts[i][1], pts[i][2]) <= extent
		if not inside[i] then all = false end
	end
	local runs = {}
	if all and sd.closed then
		-- a whole loop (a small island or lake): one open run starting opposite the foot
		local i0 = 1
		local bd = -1
		for i = 1, n do
			local d = G.dist(sd.foot[1], sd.foot[2], pts[i][1], pts[i][2])
			if d > bd then bd, i0 = d, i end
		end
		local run = {}
		for k = 0, n - 1 do run[#run + 1] = pts[(i0 + k - 1) % n + 1] end
		runs[1] = run
		return runs
	end
	local cur = nil
	for i = 1, n do
		if inside[i] then
			cur = cur or {}
			cur[#cur + 1] = pts[i]
		elseif cur then
			runs[#runs + 1] = cur
			cur = nil
		end
	end
	if cur then runs[#runs + 1] = cur end
	-- (a closed loop starts at the town's foot: the runs through the end and the start of the list are one)
	if sd.closed and inside[1] and inside[n] and #runs >= 2 then
		local last = table.remove(runs)
		for _, p in ipairs(runs[1]) do last[#last + 1] = p end
		runs[1] = last
	end
	return runs
end

--- The land-side offset of a shore run at distance off, split where invalid; lists of {x, y}.
local function offsetRuns(run, off, sd, terrain, minClear)
	local out, cur = {}, nil
	local n = #run
	for i = 1, n do
		local a, b = run[max(1, i - 1)], run[min(n, i + 1)]
		local tx, ty = unit(b[1] - a[1], b[2] - a[2])
		-- water on the right of travel: land on the left
		local x, y = run[i][1] - ty * off, run[i][2] + tx * off
		local _, perp, wet = SH.shoreAt(sd, x, y)
		local okP = not wet and perp >= minClear and not (terrain and T.isWater(terrain, x, y))
		if okP then
			cur = cur or {}
			cur[#cur + 1] = { x, y }
		elseif cur then
			out[#out + 1] = cur
			cur = nil
		end
	end
	if cur then out[#out + 1] = cur end
	return out
end

--- Splits dense points where they come nearer than minClear to the shore or onto water; runs of >= MIN_LINE.
local function validRuns(pts, sd, terrain, minClear)
	local out, cur = {}, nil
	local function flush()
		if cur and #cur >= 2 and (#cur - 1) * S.SAMPLE >= S.MIN_LINE then out[#out + 1] = cur end
		cur = nil
	end
	for _, p in ipairs(pts) do
		local _, perp, wet = SH.shoreAt(sd, p[1], p[2])
		if not wet and perp >= minClear and not (terrain and T.isWater(terrain, p[1], p[2])) then
			cur = cur or {}
			cur[#cur + 1] = p
		else
			flush()
		end
	end
	flush()
	return out
end

S.CELL = 40              -- m: segment index cell of the dense lines

--- Segment index of a dense line: { D, cells = { [key] = { k... } } } (segment k: D[k - 1] -> D[k]).
local function indexLine(D)
	local cell = S.CELL
	local idx = { D = D, cells = {} }
	for k = 2, #D do
		local c, d = D[k - 1], D[k]
		local x0, x1, y0, y1 = G.cellRange(c[1], c[2], d[1], d[2], 0, cell)   -- (hang guard)
		for cx = x0 or 1, x1 or 0 do
			for cy = y0, y1 do
				local key = cx * 65536 + cy
				local l = idx.cells[key]
				if l == nil then l = {}; idx.cells[key] = l end
				l[#l + 1] = k
			end
		end
	end
	return idx
end

--- Crossings of polyline pts with the indexed dense line: list of { idx = position on D (sample index + fraction),
--- f = arc fraction on pts, x, y } sorted by f.
local function crossLine(pts, ix)
	local out = {}
	local D, cell = ix.D, S.CELL
	local total = G.polyLen(pts)
	if total <= 0 then return out end
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		local seen = {}
		local x0, x1, y0, y1 = G.cellRange(a[1], a[2], b[1], b[2], 0, cell)   -- (hang guard)
		for cx = x0 or 1, x1 or 0 do
			for cy = y0, y1 do
				for _, k in ipairs(ix.cells[cx * 65536 + cy] or {}) do
					if not seen[k] then
						seen[k] = true
						local c, d = D[k - 1], D[k]
						local t, u = G.segIntersect(a[1], a[2], b[1], b[2], c[1], c[2], d[1], d[2], 1e-6)
						if t then
							out[#out + 1] = { idx = k - 1 + u, f = (acc + t * l) / total, x = a[1] + (b[1] - a[1]) * t,
								y = a[2] + (b[2] - a[2]) * t }
						end
					end
				end
			end
		end
		acc = acc + l
	end
	table.sort(out, function(p, q) return p.f < q.f end)
	return out
end

--- true when (x, y) lies within r (<= a few cells) of the indexed dense line.
local function nearLine(ix, x, y, r)
	local D, cell = ix.D, S.CELL
	local n = math.ceil(r / cell)
	local i0, j0 = floor(x / cell), floor(y / cell)
	for di = -n, n do
		for dj = -n, n do
			for _, k in ipairs(ix.cells[(i0 + di) * 65536 + (j0 + dj)] or {}) do
				if G.pointSegDist(x, y, D[k - 1][1], D[k - 1][2], D[k][1], D[k][2]) <= r then return true end
			end
		end
	end
	return false
end

--- Points of D from index position i0 to i1 (sample indices with fractions), with tangents.
local function subLine(D, i0, i1)
	local function at(pos)
		local k = floor(pos)
		if k >= #D then return { D[#D][1], D[#D][2], D[#D][3], D[#D][4] } end
		if k < 1 then return { D[1][1], D[1][2], D[1][3], D[1][4] } end
		local f = pos - k
		local a, b = D[k], D[k + 1]
		local ux, uy = unit(a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f)
		return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, ux, uy }
	end
	local out = { at(i0) }
	for k = floor(i0) + 1, math.ceil(i1) - 1 do
		if k > i0 + 1e-6 and k < i1 - 1e-6 then out[#out + 1] = { D[k][1], D[k][2], D[k][3], D[k][4] } end
	end
	out[#out + 1] = at(i1)
	return out
end

--- Applies the waterfront streets of style.shoreFront to master plan mp in place (extent: the plan's, m from the
--- centre; terrain: sampler or nil). Returns the number of promenade lines; mp.shoreFront = { lines, rungs, cut, len }.
function S.apply(mp, style, extent, terrain)
	local sf = style and style.shoreFront
	mp.shoreFront = nil
	if not S.ON or sf == nil or sf.sd == nil or mp == nil then return 0 end
	local sd = sf.sd
	local cx, cy = style.centre[1], style.centre[2]
	local setback = style.waterSetback or 25
	local off = setback + S.MARGIN
	local minClear = setback + 5
	local row = sf.row and G.clamp(S.ROW[1] * style.block.depth, S.ROW[2], S.ROW[3]) or nil
	local rungSp = G.clamp(S.RUNG[1] * style.block.len, S.RUNG[2], S.RUNG[3])
	local class = sf.class or "medium"
	local lines = {}
	for _, run in ipairs(shoreRuns(sd, cx, cy, (extent or 1000) + 50)) do
		for _, o in ipairs(offsetRuns(run, off, sd, terrain, minClear)) do
			if #o >= 2 and G.polyLen(o) >= S.MIN_LINE then
				local simp = G.simplify(o, 6, 25)
				local sm = (G.smoothLine(simp, S.SMOOTH_R))
				for _, D in ipairs(validRuns(dense(sm), sd, terrain, minClear)) do
					local B = nil
					if row then
						-- the back street: the promenade offset inland by the row depth (same samples: cross street k
						-- runs from D[k] to B[k]); points onto water or near the shore end it (rare: headland tips)
						B = {}
						for k, p in ipairs(D) do
							B[k] = { p[1] - p[4] * row, p[2] + p[3] * row, p[3], p[4] }
						end
					end
					lines[#lines + 1] = { D = D, B = B, ixD = indexLine(D), ixB = B and indexLine(B) or nil }
				end
			end
		end
	end
	if #lines == 0 then return 0 end
	-- cut the plan at the back street (row) or the promenade: crossing pieces end there in a T, parts on the water
	-- side and pieces in the band between the line and the water are dropped
	local kept = {}
	local junc = {}   -- per line: list of { idx, key } on the cut line
	for li = 1, #lines do junc[li] = {} end
	local function cutOf(L) return L.ixB or L.ixD end
	local band = row and (row + 10) or 15
	local function inBand(x, y)
		local _, perp, wet = SH.shoreAt(sd, x, y)
		if wet then return true end
		if perp >= off + (row or 0) - 3 then return false end
		for _, L in ipairs(lines) do
			if nearLine(L.ixD, x, y, band) then return true end
		end
		return false
	end
	-- rung junctions first (crossings snap to them)
	local rungs = {}
	for li, L in ipairs(lines) do
		if row then
			local n = #L.D
			local stepK = rungSp / S.SAMPLE
			local k = 1 + S.END_GAP / S.SAMPLE
			if not (stepK >= 1) then stepK = n + 1 end   -- (hang guard: a zero / NaN rung spacing makes one rung)
			while k <= n - S.END_GAP / S.SAMPLE do
				local kk = floor(k + 0.5)
				local key = "sfJ" .. li .. ":" .. kk
				mp.junctions[key] = { L.B[kk][1], L.B[kk][2] }
				mp.junctions["sfT" .. li .. ":" .. kk] = { L.D[kk][1], L.D[kk][2] }
				junc[li][#junc[li] + 1] = { idx = kk, key = key, rung = true, x = L.B[kk][1], y = L.B[kk][2] }
				rungs[#rungs + 1] = { li = li, k = kk }
				k = k + stepK
			end
		end
	end
	local cuts = 0
	for _, pc in ipairs(mp.pieces) do
		local hits = {}
		for li, L in ipairs(lines) do
			for _, c in ipairs(crossLine(pc.pts, cutOf(L))) do
				c.li = li
				hits[#hits + 1] = c
			end
		end
		if #hits == 0 then
			local mx, my = G.polyAt(pc.pts, 0.5)
			if not inBand(mx, my) then kept[#kept + 1] = pc end
		else
			table.sort(hits, function(p, q) return p.f < q.f end)
			local cutPts, keys = {}, { pc.a }
			for hi, c in ipairs(hits) do
				-- snap to a cross street's junction nearby, else a new junction on the line
				local key, jx, jy = nil, c.x, c.y
				for _, j in ipairs(junc[c.li]) do
					if G.dist(j.x, j.y, c.x, c.y) <= S.SNAP then key, jx, jy = j.key, j.x, j.y break end
				end
				if key == nil then
					key = "sfX" .. c.li .. ":" .. pc.key .. ":" .. hi
					mp.junctions[key] = { jx, jy }
					junc[c.li][#junc[c.li] + 1] = { idx = c.idx, key = key, x = jx, y = jy }
				end
				cutPts[hi] = { c.f, jx, jy }
				keys[#keys + 1] = key
			end
			keys[#keys + 1] = pc.b
			local parts = G.polySplit(pc.pts, cutPts)
			for i, pts in ipairs(parts) do
				local mx, my = G.polyAt(pts, 0.5)
				if keys[i + 1] and keys[i] ~= keys[i + 1] and G.polyLen(pts) > 5 and not inBand(mx, my) then
					local np = {}
					for k, v in pairs(pc) do np[k] = v end
					np.key, np.a, np.b, np.pts = pc.key .. "~sf" .. i, keys[i], keys[i + 1], pts
					if i ~= 1 then np.dirA = nil end
					if i ~= #parts then np.dirB = nil end
					kept[#kept + 1] = np
				end
			end
			cuts = cuts + 1
		end
	end
	-- the lines' pieces
	local total = 0
	for li, L in ipairs(lines) do
		local D, n = L.D, #L.D
		total = total + (n - 1) * S.SAMPLE
		local function addLine(C, list, prefix, cls, endKeys)
			table.sort(list, function(p, q) return p.idx < q.idx end)
			local stops = { { idx = 1, key = endKeys[1] } }
			for _, j in ipairs(list) do
				if j.idx > stops[#stops].idx + 0.5 and j.idx < n - 0.5 then stops[#stops + 1] = j end
			end
			stops[#stops + 1] = { idx = n, key = endKeys[2] }
			mp.junctions[endKeys[1]] = { C[1][1], C[1][2] }
			mp.junctions[endKeys[2]] = { C[n][1], C[n][2] }
			for s = 2, #stops do
				local a, b = stops[s - 1], stops[s]
				-- (armLine: the selector's line-tips rule, ot_select ARM_TIPS, keeps the line's tip a dead end one piece
				-- ahead: a cross street meeting it at its tip would leave a corner the game can't extend from)
				kept[#kept + 1] = { key = prefix .. li .. "#" .. (s - 1), a = a.key, b = b.key, pts = subLine(C, a.idx, b.idx),
					class = cls, curved = true, smooth = true, shoreFront = true, armLine = prefix .. li .. ":L" }
			end
		end
		if row then
			local top = {}
			for _, j in ipairs(junc[li]) do
				if j.rung then top[#top + 1] = { idx = j.idx, key = "sfT" .. li .. ":" .. j.idx } end
			end
			addLine(D, top, "sfP", class, { "sfP" .. li .. ":A", "sfP" .. li .. ":Z" })
			addLine(L.B, junc[li], "sfB", "small", { "sfB" .. li .. ":A", "sfB" .. li .. ":Z" })
		else
			addLine(D, junc[li], "sfP", class, { "sfP" .. li .. ":A", "sfP" .. li .. ":Z" })
		end
	end
	for _, r in ipairs(rungs) do
		local L = lines[r.li]
		local a, b = L.D[r.k], L.B[r.k]
		kept[#kept + 1] = { key = "sfR" .. r.li .. ":" .. r.k, a = "sfT" .. r.li .. ":" .. r.k, b = "sfJ" .. r.li .. ":" .. r.k,
			pts = { { a[1], a[2] }, { b[1], b[2] } }, class = "small", shoreFront = true }
	end
	mp.pieces = kept
	mp.hasArmLines = true
	mp.shoreFront = { lines = #lines, rungs = #rungs, cut = cuts, len = total }
	return #lines
end

return S
