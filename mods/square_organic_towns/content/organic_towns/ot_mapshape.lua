-- Organic Towns: the map survey for names (pure; 2026-10-14, NEXT_PHASE_BRIEF 45 "Names from the map's shape").
--
-- User (run 2026-10-14_0710_sqot): "it would be cool if we could really take into account the shape of the map. e.g.
-- middle fork, directionality, big geographical cues would be super neat." Once per new map, in the names phase, the
-- mod reads the whole map on a coarse grid (at most MAX_N x MAX_N cells of about CELL_M: one height and one water read
-- each) and keeps the big shapes for every naming step:
--   * water cells split by their width (the shortest run through the cell over four axes): narrow ones are rivers
--     (RIVER_MAX_M), the rest water bodies; bodies touching the map edge are the sea, the others lakes;
--   * rivers as a network: components of river cells (gaps of one cell bridged), long ones (RIVER_MIN_M) only; forks and
--     confluences (three or more river arms on a ring of RING cells), mouths (a river cell beside a body: sea or lake),
--     sharp bends (two arms at under BEND_DEG), steep drops (falls: the water's edge FALL_DH lower within two cells),
--     upper / lower course (the distance from the mouth along the river, else the height along it);
--   * relief: the highest peak (PEAK_MIN above the dry median, a local maximum), the main range (the largest patch of
--     high ground), the main valley (the longest river);
--   * coast: bays (water with land on most of a ring), capes (land with water on most of a ring), narrows (a narrow
--     water between two wide ones), isthmus (a narrow neck of land between two waters).
-- M.townCues turns that into a town's cue tags (ot_placename tags: confluence, mouth, bend, falls, upper, lower, twin,
-- north / south / east / west / central, biglake, peak, summit, range, divide, mainvalley, bay, bigbay, headland,
-- narrows, isthmus) with weights, plus the river component the town sits on (towns along one river share its name).
--
-- Sliced and capped: M.step works in units (one cell, one ring, one BFS pop) and asks `more()` every CHECK_EVERY units;
-- each phase stops after PHASE_K units per cell (logged as capped=<phase>, the phase's features skipped); the driver
-- also stops the whole survey after NAMES_SHAPE_MAX_S (capped=timeout). Read-only; nothing saved. Plain Lua, pre-5.3.

local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

M.ON = true
M.CELL_M = 120            -- target cell size (m)
M.MAX_N = 128             -- cells per side at most (MAX_N^2 cells, two reads each)
M.MIN_N = 12
M.RIVER_MAX_M = 400       -- a water cell this narrow is river
M.WCAP = 12               -- run length looked at per side (cells)
M.RIVER_MIN_M = 1500      -- a river this long counts
M.RING = 3                -- ring radius (cells) for river arms
M.BEND_DEG = 100          -- two arms closer than this: a bend
M.FALL_DH = 12            -- m: the water's edge this much lower within two cells: falls
M.CLUSTER = 4             -- cells: candidates this close form one feature
M.MAX_FEAT = 48           -- features per kind at most
M.UPLOW_MIN_M = 3000      -- rivers this long have an upper and a lower course
M.UPLOW_DH = 12           -- m: without a mouth, the river must fall this much
M.PEAK_MIN = 120          -- m above the dry median
M.PEAK_R = 4              -- cells: a peak is the highest point this far round
M.MAX_PEAKS = 8
M.RANGE_MIN = 150         -- m above the dry median at least ...
M.RANGE_K = 0.5           -- ... or this share of the way to the top: high ground
M.RANGE_CELLS = 12        -- the largest patch of high ground this big is the range
M.VALLEY_MIN_M = 4000     -- the longest river this long is the main valley
M.BAY_R = 6               -- cells: bay / cape ring (a convex lake shore reads about 0.5 land)
M.BAY_DRY = 0.6           -- water with this much land on its ring: a bay
M.BAY_BODY = 200          -- cells: bays only in water bodies this big
M.CAPE_WET = 0.6          -- land beside a body with this much water on its ring: a cape
M.NARROW_M = 450          -- water this narrow ...
M.WIDE_M = 1000           -- ... reaching water this wide on both sides: narrows
M.NARROW_WALK = 8
M.ISTH_WALK = 4           -- cells: water on both sides this near ...
M.ISTH_DRY = 5            -- ... and land this far along the neck: an isthmus
M.BIGLAKE_CELLS = 20      -- the largest lake this big is the map's big lake
M.SMALL_BODY = 12         -- cells: a wide water smaller than this (not at the edge) is part of a river
M.CHECK_EVERY = 32        -- units between budget checks
M.PHASE_K = 40            -- units per cell per phase at most
-- town cue radii (m)
M.RIV_NEAR_M = 900
M.FORK_NEAR_M = 1500
M.MOUTH_NEAR_M = 1500
M.BEND_NEAR_M = 800
M.FALL_NEAR_M = 1500
M.TWIN_NEAR_M = 1200
M.CENTRAL = 0.25          -- within this share of the half extent of the map's centre: central
M.DIR_FROM = 0.3          -- beyond this share toward an edge: that compass side
M.BIGLAKE_NEAR_M = 1500
M.PEAK_NEAR_M = 3000
M.RANGE_NEAR_M = 2500
M.DIVIDE_M = 4000
M.VALLEY_NEAR_M = 1500
M.BAY_NEAR_M = 1500
M.CAPE_NEAR_M = 1000
M.NARROW_NEAR_M = 1200

local PHASES = { "sample", "width", "label", "rivers", "flow", "relief", "coast" }
local AX = { { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1.41421356 }, { 1, -1, 1.41421356 } }
local PERP = { 2, 1, 4, 3 }

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

-- a round ring of radius r (cells): 8 r directions rounded to cells, in angle order, no cell twice
local RINGS = {}
local function ring(r)
	if RINGS[r] then return RINGS[r] end
	local out, seen = {}, {}
	local n = 8 * r
	for i = 0, n - 1 do
		local a = i / n * 2 * math.pi - math.pi
		local dc, dr = math.floor(r * math.cos(a) + 0.5), math.floor(r * math.sin(a) + 0.5)
		local key = dc .. ":" .. dr
		if not seen[key] then
			seen[key] = true
			out[#out + 1] = { dc, dr, G.atan2(dr, dc) }
		end
	end
	RINGS[r] = out
	return out
end

--- A new survey over bounds = { x0, y0, x1, y1 } (ot_engine.mapBounds), or nil and why ("noBounds" | "small").
--- o = { cell = m, maxN }.
function M.new(bounds, o)
	o = o or {}
	if type(bounds) ~= "table" or not (tonumber(bounds[1]) and tonumber(bounds[2]) and tonumber(bounds[3]) and tonumber(bounds[4])) then
		return nil, "noBounds"
	end
	local x0, y0, x1, y1 = bounds[1], bounds[2], bounds[3], bounds[4]
	local ext = math.max(x1 - x0, y1 - y0)
	if ext <= 0 then return nil, "noBounds" end
	local maxN = o.maxN or M.MAX_N
	local cs = math.max(o.cell or M.CELL_M, ext / maxN)
	local nx = math.max(1, math.floor((x1 - x0) / cs))
	local ny = math.max(1, math.floor((y1 - y0) / cs))
	if nx < M.MIN_N or ny < M.MIN_N then return nil, "small" end
	local st = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, cs = cs, nx = nx, ny = ny, cells = nx * ny, phase = 1, k = 0,
		pass = 1, work = 0, phaseWork = 0, done = false, capped = {}, wet = {}, h = {}, wd = {}, ax = {}, kind = {},
		rl = {}, bl = {}, rc = {}, bc = {}, sp = {}, dist = {}, cand = { fork = {}, mouth = {}, bend = {}, falls = {},
		bay = {}, cape = {}, narrows = {}, isthmus = {}, peak = {} }, nWet = 0 }
	return st
end

local function idx(st, c, r) return r * st.nx + c + 1 end
local function cr(st, k) local i = k - 1 return i % st.nx, math.floor(i / st.nx) end
local function inside(st, c, r) return c >= 0 and r >= 0 and c < st.nx and r < st.ny end
local function centre(st, c, r) return st.x0 + (c + 0.5) * st.cs, st.y0 + (r + 0.5) * st.cs end

---------------------------------------------------------------------------
-- phases (each returns true when finished)

local P = {}

function P.sample(st, s)
	st.k = st.k + 1
	if st.k > st.cells then return true end
	local c, r = cr(st, st.k)
	local x, y = centre(st, c, r)
	local w = T.isWater(s, x, y) == true
	st.wet[st.k] = w
	st.h[st.k] = tonumber(s.height(x, y)) or 0
	if w then st.nWet = st.nWet + 1 end
	return false
end

local function run(st, c, r, dc, dr)
	local n = 0
	for i = 1, M.WCAP do
		local cc, rr = c + dc * i, r + dr * i
		if not inside(st, cc, rr) or not st.wet[idx(st, cc, rr)] then break end
		n = i
	end
	return n
end

function P.width(st)
	st.k = st.k + 1
	if st.k > st.cells then return true end
	local k = st.k
	if not st.wet[k] then return false end
	local c, r = cr(st, k)
	local best, ba = math.huge, 1
	for a, d in ipairs(AX) do
		local m = (1 + run(st, c, r, d[1], d[2]) + run(st, c, r, -d[1], -d[2])) * st.cs * d[3]
		if m < best then best, ba = m, a end
	end
	st.wd[k], st.ax[k] = best, ba
	st.kind[k] = best <= M.RIVER_MAX_M and 1 or 2
	return false
end

-- labels in two passes: water bodies first (8-neighbours; a body under SMALL_BODY cells, such as the wide water where two
-- rivers meet, becomes river), then rivers (8-neighbours and one-cell gaps)
function P.label(st)
	local q = st.q
	local river = st.pass == 2
	if q and st.qh <= #q then
		local k = q[st.qh]
		st.qh = st.qh + 1
		local c, r = cr(st, k)
		local rad = river and 2 or 1
		local id = river and st.rl[k] or st.bl[k]
		local comp = river and st.rc[id] or st.bc[id]
		for dr = -rad, rad do
			for dc = -rad, rad do
				local cc, rr = c + dc, r + dr
				if (dc ~= 0 or dr ~= 0) and inside(st, cc, rr) then
					local j = idx(st, cc, rr)
					if river and st.kind[j] == 1 and st.rl[j] == nil then
						st.rl[j] = id
						q[#q + 1] = j
						comp.n, comp.sx, comp.sy, comp.wsum = comp.n + 1, comp.sx + cc, comp.sy + rr, comp.wsum + math.min(st.wd[j] or 0, M.RIVER_MAX_M)
						comp.cells[#comp.cells + 1] = j
					elseif not river and st.kind[j] == 2 and st.bl[j] == nil then
						st.bl[j] = id
						q[#q + 1] = j
						comp.n, comp.sx, comp.sy = comp.n + 1, comp.sx + cc, comp.sy + rr
						comp.cells[#comp.cells + 1] = j
						if cc == 0 or rr == 0 or cc == st.nx - 1 or rr == st.ny - 1 then comp.border = true end
					end
				end
			end
		end
		return false
	end
	st.q, st.qh = nil, 1
	-- the next unlabelled cell of this pass
	while true do
		st.k = st.k + 1
		local k = st.k
		if k > st.cells then
			if not river then
				-- small bodies become river; the body pass ends
				for _, comp in ipairs(st.bc) do
					if comp.n < M.SMALL_BODY and not comp.border then
						comp.dead = true
						for _, j in ipairs(comp.cells) do
							st.kind[j], st.bl[j] = 1, nil
						end
					end
					comp.x, comp.y = centre(st, comp.sx / comp.n, comp.sy / comp.n)
					comp.sea = comp.border == true
					comp.cells = nil
				end
				st.pass, st.k = 2, 0
				return false
			end
			for _, comp in ipairs(st.rc) do
				local mw = comp.n > 0 and comp.wsum / comp.n or st.cs
				comp.len = comp.n * st.cs * st.cs / math.max(st.cs, mw)
				comp.long = comp.len >= M.RIVER_MIN_M
				comp.x, comp.y = centre(st, comp.sx / comp.n, comp.sy / comp.n)
			end
			return true
		end
		if river and st.kind[k] == 1 and st.rl[k] == nil then
			local c, r = cr(st, k)
			st.rc[#st.rc + 1] = { id = #st.rc + 1, n = 1, sx = c, sy = r, wsum = math.min(st.wd[k] or 0, M.RIVER_MAX_M), cells = { k } }
			st.rl[k] = #st.rc
			st.q, st.qh = { k }, 1
			return false
		elseif not river and st.kind[k] == 2 and st.bl[k] == nil then
			local c, r = cr(st, k)
			st.bc[#st.bc + 1] = { id = #st.bc + 1, n = 1, sx = c, sy = r, cells = { k },
				border = (c == 0 or r == 0 or c == st.nx - 1 or r == st.ny - 1) }
			st.bl[k] = #st.bc
			st.q, st.qh = { k }, 1
			return false
		end
	end
end

-- greedy clusters of candidates { {k, ...} } within CLUSTER cells; at most MAX_FEAT (the rest skipped and noted)
local function cluster(st, list, name, rad)
	rad = rad or M.CLUSTER
	local out = {}
	for _, cd in ipairs(list) do
		local c, r = cr(st, cd.k)
		local hit = nil
		for _, f in ipairs(out) do
			if math.abs(f.c - c) <= rad and math.abs(f.r - r) <= rad then hit = f break end
		end
		if hit then
			hit.n = hit.n + 1
			hit.sc, hit.sr = hit.sc + c, hit.sr + r
			if (cd.arms or 0) > (hit.arms or 0) then hit.arms = cd.arms end
		elseif #out < M.MAX_FEAT then
			out[#out + 1] = { c = c, r = r, sc = c, sr = r, n = 1, k = cd.k, comp = cd.comp, body = cd.body, arms = cd.arms }
		else
			st.capped[#st.capped + 1] = name
			break
		end
	end
	for _, f in ipairs(out) do f.x, f.y = centre(st, f.sc / f.n, f.sr / f.n) end
	table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.k < b.k end)
	return out
end

-- the water's edge near a river cell: the highest wet height in its 3 x 3 (the shallow cells by the banks)
local function surface(st, k)
	local c, r = cr(st, k)
	local best = -math.huge
	for dr = -1, 1 do
		for dc = -1, 1 do
			local cc, rr = c + dc, r + dr
			if inside(st, cc, rr) then
				local j = idx(st, cc, rr)
				if st.wet[j] and st.h[j] > best then best = st.h[j] end
			end
		end
	end
	return best
end

function P.rivers(st)
	st.k = st.k + 1
	local k = st.k
	if k > st.cells then
		if st.pass == 1 then
			st.pass, st.k = 2, 0
			return false
		end
		st.forks = cluster(st, st.cand.fork, "forks")
		st.mouths = cluster(st, st.cand.mouth, "mouths")
		st.bends = cluster(st, st.cand.bend, "bends")
		st.falls = cluster(st, st.cand.falls, "falls")
		st.pass = 1
		return true
	end
	local id = st.rl[k]
	if id == nil or not st.rc[id].long then return false end
	if st.pass == 1 then
		st.sp[k] = surface(st, k)
		return false
	end
	local c, r = cr(st, k)
	-- a mouth: a body cell beside it
	local nearBody, mouthBody = false, nil
	for dr = -2, 2 do
		for dc = -2, 2 do
			local cc, rr = c + dc, r + dr
			if inside(st, cc, rr) then
				local j = idx(st, cc, rr)
				if st.kind[j] == 2 then
					nearBody = true
					if math.abs(dc) <= 1 and math.abs(dr) <= 1 then mouthBody = st.bl[j] end
				end
			end
		end
	end
	if mouthBody then
		local list = st.cand.mouth
		list[#list + 1] = { k = k, comp = id, body = mouthBody }
		st.rc[id].mouth = true
		st.rc[id].mouthCells = st.rc[id].mouthCells or {}
		local mc = st.rc[id].mouthCells
		mc[#mc + 1] = k
	end
	if not nearBody then
		-- arms on the ring
		local rg = ring(M.RING)
		local runs, cur = {}, nil
		local n = #rg
		local wetAt = {}
		for i, o in ipairs(rg) do
			local cc, rr = c + o[1], r + o[2]
			wetAt[i] = inside(st, cc, rr) and st.kind[idx(st, cc, rr)] == 1
		end
		-- start at a dry ring cell
		local s0 = nil
		for i = 1, n do if not wetAt[i] then s0 = i break end end
		if s0 then
			for step = 1, n do
				local i = (s0 + step - 1) % n + 1
				if wetAt[i] then
					if cur == nil then cur = { a = i, m = 0 } end
					cur.m = cur.m + 1
				elseif cur then
					runs[#runs + 1] = cur
					cur = nil
				end
			end
			if cur then runs[#runs + 1] = cur end
			if #runs >= 3 then
				local list = st.cand.fork
				list[#list + 1] = { k = k, comp = id, arms = #runs }
			elseif #runs == 2 then
				local a1 = rg[(runs[1].a + math.floor((runs[1].m - 1) / 2) - 1) % n + 1]
				local a2 = rg[(runs[2].a + math.floor((runs[2].m - 1) / 2) - 1) % n + 1]
				local d = math.abs(a1[3] - a2[3])
				if d > math.pi then d = 2 * math.pi - d end
				if math.deg(d) < M.BEND_DEG then
					local list = st.cand.bend
					list[#list + 1] = { k = k, comp = id }
				end
			end
		end
	end
	-- falls: the water's edge FALL_DH higher within two cells along the same river
	local spk = st.sp[k]
	if spk then
		for dr = -2, 2 do
			for dc = -2, 2 do
				local cc, rr = c + dc, r + dr
				if inside(st, cc, rr) then
					local j = idx(st, cc, rr)
					if st.rl[j] == id and st.sp[j] and st.sp[j] - spk >= M.FALL_DH then
						local list = st.cand.falls
						list[#list + 1] = { k = k, comp = id }
						return false
					end
				end
			end
		end
	end
	return false
end

-- upper / lower course: distance from the mouth along each long river (BFS, one pop per unit), else its heights
function P.flow(st)
	local q = st.fq
	if q and st.fqh <= #q then
		local k = q[st.fqh]
		st.fqh = st.fqh + 1
		local comp = st.rc[st.fc]
		local c, r = cr(st, k)
		local d = st.dist[k]
		for dr = -2, 2 do
			for dc = -2, 2 do
				local cc, rr = c + dc, r + dr
				if inside(st, cc, rr) then
					local j = idx(st, cc, rr)
					if st.rl[j] == st.fc and st.dist[j] == nil then
						st.dist[j] = d + 1
						if d + 1 > (comp.maxd or 0) then comp.maxd = d + 1 end
						q[#q + 1] = j
					end
				end
			end
		end
		return false
	end
	st.fq = nil
	-- the next long river
	st.fc = (st.fc or 0) + 1
	local comp = st.rc[st.fc]
	if comp == nil then return true end
	if not comp.long or comp.len < M.UPLOW_MIN_M then return false end
	if comp.mouthCells and #comp.mouthCells > 0 then
		comp.flow, comp.maxd = "mouth", 0
		st.fq, st.fqh = {}, 1
		for _, k in ipairs(comp.mouthCells) do
			if st.dist[k] == nil then
				st.dist[k] = 0
				st.fq[#st.fq + 1] = k
			end
		end
		return false
	end
	-- no mouth: by the water's edge heights along it (a sample of up to 2000 cells)
	local hs = {}
	local step = math.max(1, math.floor(#comp.cells / 2000))
	for i = 1, #comp.cells, step do
		local v = st.sp[comp.cells[i]]
		if v and v > -math.huge then hs[#hs + 1] = v end
	end
	if #hs >= 4 then
		table.sort(hs)
		local lo, hi = hs[math.max(1, math.floor(#hs * 0.1))], hs[math.max(1, math.ceil(#hs * 0.9))]
		if hi - lo >= M.UPLOW_DH then comp.flow, comp.lo, comp.hi = "height", lo, hi end
	end
	return false
end

function P.relief(st)
	if st.pass == 1 then
		st.k = st.k + 1
		if st.k > st.cells then
			local hs = st.dryH or {}
			if #hs == 0 then return true end
			table.sort(hs)
			st.median = hs[math.max(1, math.floor((#hs + 1) / 2))]
			st.top = hs[#hs]
			st.dryH = nil
			st.rangeT = st.median + math.max(M.RANGE_MIN, M.RANGE_K * (st.top - st.median))
			st.pass, st.k = 2, 0
			return false
		end
		local stride = math.max(1, math.floor(st.cells / 4096))
		if not st.wet[st.k] and st.k % stride == 0 then
			st.dryH = st.dryH or {}
			st.dryH[#st.dryH + 1] = st.h[st.k]
		end
		return false
	elseif st.pass == 2 then
		-- peaks: local maxima PEAK_MIN above the median
		st.k = st.k + 1
		if st.k > st.cells then st.pass, st.k = 3, 0 return false end
		local k = st.k
		local h = st.h[k]
		if st.wet[k] or h < st.median + M.PEAK_MIN then return false end
		local c, r = cr(st, k)
		for dr = -M.PEAK_R, M.PEAK_R do
			for dc = -M.PEAK_R, M.PEAK_R do
				local cc, rr = c + dc, r + dr
				if (dc ~= 0 or dr ~= 0) and inside(st, cc, rr) then
					local j = idx(st, cc, rr)
					if st.h[j] > h or (st.h[j] == h and j < k) then return false end
				end
			end
		end
		local list = st.cand.peak
		list[#list + 1] = { k = k, h = h }
		return false
	else
		-- the range: patches of high ground (BFS, one pop per unit)
		local q = st.gq
		if q and st.gqh <= #q then
			local k = q[st.gqh]
			st.gqh = st.gqh + 1
			local c, r = cr(st, k)
			local comp = st.ranges[#st.ranges]
			for dr = -1, 1 do
				for dc = -1, 1 do
					local cc, rr = c + dc, r + dr
					if (dc ~= 0 or dr ~= 0) and inside(st, cc, rr) then
						local j = idx(st, cc, rr)
						if not st.wet[j] and st.h[j] >= st.rangeT and st.gl[j] == nil then
							st.gl[j] = #st.ranges
							q[#q + 1] = j
							comp.n, comp.sx, comp.sy = comp.n + 1, comp.sx + cc, comp.sy + rr
						end
					end
				end
			end
			return false
		end
		st.gq = nil
		st.ranges, st.gl = st.ranges or {}, st.gl or {}
		while true do
			st.k = st.k + 1
			local k = st.k
			if k > st.cells then
				-- peaks: highest first, apart
				table.sort(st.cand.peak, function(a, b) if a.h ~= b.h then return a.h > b.h end return a.k < b.k end)
				st.peaks = {}
				for _, p in ipairs(st.cand.peak) do
					if #st.peaks >= M.MAX_PEAKS then break end
					local c, r = cr(st, p.k)
					local apart = true
					for _, q2 in ipairs(st.peaks) do
						if math.abs(q2.c - c) <= 3 * M.PEAK_R and math.abs(q2.r - r) <= 3 * M.PEAK_R then apart = false break end
					end
					if apart then
						local x, y = centre(st, c, r)
						st.peaks[#st.peaks + 1] = { c = c, r = r, x = x, y = y, h = p.h }
					end
				end
				local best = nil
				for i, g in ipairs(st.ranges) do
					if g.n >= M.RANGE_CELLS and (best == nil or g.n > st.ranges[best].n) then best = i end
				end
				st.range = best
				if best then
					local g = st.ranges[best]
					g.x, g.y = centre(st, g.sx / g.n, g.sy / g.n)
				end
				-- the main valley: the longest river
				local vb = nil
				for _, comp in ipairs(st.rc) do
					if comp.long and comp.len >= M.VALLEY_MIN_M and (vb == nil or comp.len > vb.len) then vb = comp end
				end
				st.valley = vb and vb.id or nil
				st.pass = 1
				return true
			end
			if not st.wet[k] and st.h[k] >= st.rangeT and st.gl[k] == nil then
				local c, r = cr(st, k)
				st.ranges[#st.ranges + 1] = { n = 1, sx = c, sy = r }
				st.gl[k] = #st.ranges
				st.gq, st.gqh = { k }, 1
				return false
			end
		end
	end
end

local function ringShare(st, c, r, rad, test)
	local n, hit = 0, 0
	for _, o in ipairs(ring(rad)) do
		local cc, rr = c + o[1], r + o[2]
		if inside(st, cc, rr) then
			n = n + 1
			if test(idx(st, cc, rr)) then hit = hit + 1 end
		end
	end
	return n > 0 and hit / n or 0
end

local function walkWet(st, c, r, dc, dr, maxN, wantWide)
	for i = 1, maxN do
		local cc, rr = c + dc * i, r + dr * i
		if not inside(st, cc, rr) then return false end
		local j = idx(st, cc, rr)
		if not st.wet[j] then return false end
		if (st.wd[j] or 0) >= wantWide then return true end
	end
	return false
end

function P.coast(st)
	st.k = st.k + 1
	local k = st.k
	if k > st.cells then
		st.bays = cluster(st, st.cand.bay, "bays", 2 * M.CLUSTER)
		st.capes = cluster(st, st.cand.cape, "capes", 2 * M.CLUSTER)
		st.narrows = cluster(st, st.cand.narrows, "narrows")
		st.isthmus = cluster(st, st.cand.isthmus, "isthmus")
		return true
	end
	local c, r = cr(st, k)
	if st.wet[k] then
		local b = st.bl[k]
		if b and st.bc[b].n >= M.BAY_BODY then
			local dry = ringShare(st, c, r, M.BAY_R, function(j) return not st.wet[j] end)
			if dry >= M.BAY_DRY then
				local list = st.cand.bay
				list[#list + 1] = { k = k, body = b }
			end
		end
		if (st.wd[k] or 0) <= M.NARROW_M then
			local p = AX[PERP[st.ax[k] or 1]]
			if walkWet(st, c, r, p[1], p[2], M.NARROW_WALK, M.WIDE_M) and walkWet(st, c, r, -p[1], -p[2], M.NARROW_WALK, M.WIDE_M) then
				local list = st.cand.narrows
				list[#list + 1] = { k = k }
			end
		end
		return false
	end
	-- land beside a body
	local nearBody = false
	for dr = -1, 1 do
		for dc = -1, 1 do
			local cc, rr = c + dc, r + dr
			if inside(st, cc, rr) and st.kind[idx(st, cc, rr)] == 2 then nearBody = true end
		end
	end
	if nearBody then
		local wet = ringShare(st, c, r, M.BAY_R, function(j) return st.kind[j] == 2 end)
		if wet >= M.CAPE_WET then
			local list = st.cand.cape
			list[#list + 1] = { k = k }
		end
	end
	-- an isthmus: body water on both sides along one axis, land along the other
	for a, d in ipairs(AX) do
		local function bodyWithin(sx, sy)
			for i = 1, M.ISTH_WALK do
				local cc, rr = c + sx * i, r + sy * i
				if not inside(st, cc, rr) then return false end
				local j = idx(st, cc, rr)
				if st.kind[j] == 2 then return true end
				if st.wet[j] then return false end
			end
			return false
		end
		if bodyWithin(d[1], d[2]) and bodyWithin(-d[1], -d[2]) then
			local p = AX[PERP[a]]
			local okNeck = true
			for _, sgn in ipairs({ 1, -1 }) do
				for i = 1, M.ISTH_DRY do
					local cc, rr = c + p[1] * i * sgn, r + p[2] * i * sgn
					if not inside(st, cc, rr) or st.wet[idx(st, cc, rr)] then okNeck = false break end
				end
			end
			if okNeck then
				local list = st.cand.isthmus
				list[#list + 1] = { k = k }
				break
			end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- stepping

local function nextPhase(st)
	st.phase = st.phase + 1
	st.k, st.pass, st.phaseWork = 0, 1, 0
	st.q, st.fq, st.gq = nil, nil, nil
	if st.phase > #PHASES then st.done = true end
end

--- Works on the survey: more = a function returning false when the time slice is used up (checked every CHECK_EVERY
--- units), a number of units, or nil (to the end). s = an ot_terrain sampler. Returns true when the survey is done.
function M.step(st, s, more)
	if st == nil or st.done then return true end
	local n = 0
	while not st.done do
		local name = PHASES[st.phase]
		local okP, fin = pcall(P[name], st, s)
		if not okP then
			st.capped[#st.capped + 1] = name .. ":error"
			st.err = tostring(fin)
			nextPhase(st)
		else
			st.work = st.work + 1
			st.phaseWork = st.phaseWork + 1
			if fin then nextPhase(st)
			elseif st.phaseWork > st.cells * M.PHASE_K then
				-- (the phase's cap: logged as capped=<phase>, its features skipped)
				st.capped[#st.capped + 1] = name
				nextPhase(st)
			end
		end
		n = n + 1
		if type(more) == "number" then
			if n >= more then break end
		elseif more and n % M.CHECK_EVERY == 0 and not more() then
			break
		end
	end
	return st.done
end

--- Ends a survey early (the driver's time cap): the phases not reached are skipped and noted.
function M.stop(st, why)
	if st == nil or st.done then return end
	for i = st.phase, #PHASES do st.capped[#st.capped + 1] = (i == st.phase and why) and (PHASES[i] .. ":" .. why) or PHASES[i] end
	st.done = true
	st.phase = #PHASES + 1
end

--- The survey's phase reached: "sample" ... "coast", or "done".
function M.phaseName(st) return st and (PHASES[st.phase] or "done") or "-" end

---------------------------------------------------------------------------
-- summary

--- Counts for the log: { rivers, forks, mouths, bends, falls, lakes, sea, peaks, ranges, valley, bays, capes, narrows,
--- isthmus }.
function M.counts(st)
	local o = { rivers = 0, forks = #(st.forks or {}), mouths = #(st.mouths or {}), bends = #(st.bends or {}),
		falls = #(st.falls or {}), lakes = 0, sea = false, peaks = #(st.peaks or {}), ranges = st.range and 1 or 0,
		valley = st.valley ~= nil, bays = #(st.bays or {}), capes = #(st.capes or {}), narrows = #(st.narrows or {}),
		isthmus = #(st.isthmus or {}) }
	for _, comp in ipairs(st.rc or {}) do if comp.long then o.rivers = o.rivers + 1 end end
	for _, b in ipairs(st.bc or {}) do
		if b.dead then -- (part of a river)
		elseif b.sea then o.sea = true elseif b.n >= 4 then o.lakes = o.lakes + 1 end
	end
	return o
end

--- The map's largest lake (body not touching the edge, BIGLAKE_CELLS or more): comp or nil.
function M.bigLake(st)
	local best = nil
	for _, b in ipairs(st.bc or {}) do
		if not b.sea and not b.dead and b.n >= M.BIGLAKE_CELLS and (best == nil or b.n > best.n) then best = b end
	end
	return best
end

---------------------------------------------------------------------------
-- a town's cues

local DIRS = { "north", "south", "east", "west" }

local function dirOf(dx, dy)
	if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "east" or "west" end
	return dy >= 0 and "north" or "south"
end

local function nearest(list, x, y, maxD)
	local best, bd = nil, maxD * maxD
	for _, f in ipairs(list or {}) do
		local d = (f.x - x) ^ 2 + (f.y - y) ^ 2
		if d <= bd then best, bd = f, d end
	end
	return best, best and math.sqrt(bd) or nil
end

--- The cues of a town at (x, y): { w = { [tag] = weight }, river = long river component id or nil, dir = the map
--- compass side or nil, ldir = the side of the big lake it is on (or nil), lake = true by the big lake }. nil without a
--- survey.
function M.townCues(st, x, y)
	if st == nil or not tonumber(x) or not tonumber(y) or st.cells == nil or st.h == nil then return nil end
	local w = {}
	local function put(t, v) if v and v > (w[t] or 0) then w[t] = math.min(1, v) end end
	local cs = st.cs
	local c = clamp(math.floor((x - st.x0) / cs), 0, st.nx - 1)
	local r = clamp(math.floor((y - st.y0) / cs), 0, st.ny - 1)
	local out = { w = w }
	-- rivers near the town (long ones)
	local rad = math.ceil(M.RIV_NEAR_M / cs)
	local bestK, bestD, comps = nil, math.huge, {}
	for dr = -rad, rad do
		for dc = -rad, rad do
			local cc, rr = c + dc, r + dr
			if inside(st, cc, rr) then
				local j = idx(st, cc, rr)
				local id = st.rl[j]
				if id and st.rc[id].long then
					local d = math.sqrt(dc * dc + dr * dr) * cs
					if d < bestD then bestK, bestD = j, d end
					if d <= M.TWIN_NEAR_M and (comps[id] == nil or d < comps[id]) then comps[id] = d end
				end
			end
		end
	end
	if bestK then
		local id = st.rl[bestK]
		out.river = id
		local n = 0
		for _ in pairs(comps) do n = n + 1 end
		if n >= 2 then put("twin", 0.9) end
		local comp = st.rc[id]
		local frac = nil
		if comp.flow == "mouth" and (comp.maxd or 0) > 0 and st.dist[bestK] then frac = st.dist[bestK] / comp.maxd
		elseif comp.flow == "height" and st.sp[bestK] then frac = clamp((st.sp[bestK] - comp.lo) / (comp.hi - comp.lo), 0, 1) end
		if frac then
			out.flow = frac
			if frac <= 0.33 then put("lower", 0.6 + 0.4 * (1 - frac / 0.33))
			elseif frac >= 0.67 then put("upper", 0.6 + 0.4 * ((frac - 0.67) / 0.33)) end
		end
	end
	local f = nearest(st.forks, x, y, M.FORK_NEAR_M)
	if f then put("confluence", 1); out.arms = f.arms end
	local m = nearest(st.mouths, x, y, M.MOUTH_NEAR_M)
	if m then put("mouth", 1); out.mouthSea = m.body and st.bc[m.body] and st.bc[m.body].sea or false end
	if nearest(st.bends, x, y, M.BEND_NEAR_M) then put("bend", 0.9) end
	if nearest(st.falls, x, y, M.FALL_NEAR_M) then put("falls", 1) end
	-- the compass on the map
	local hx, hy = (st.x1 - st.x0) / 2, (st.y1 - st.y0) / 2
	local nx, ny = (x - (st.x0 + hx)) / math.max(1, hx), (y - (st.y0 + hy)) / math.max(1, hy)
	if math.max(math.abs(nx), math.abs(ny)) <= M.CENTRAL then put("central", 0.8) end
	local function side(v) return v > M.DIR_FROM and clamp(0.4 + 0.6 * (v - M.DIR_FROM) / (1 - M.DIR_FROM), 0.4, 1) or nil end
	put("north", side(ny)); put("south", side(-ny)); put("east", side(nx)); put("west", side(-nx))
	local bd, bv = nil, 0
	for _, d in ipairs(DIRS) do if (w[d] or 0) > bv then bd, bv = d, w[d] end end
	if bd then out.dir = bd; put("dir", bv) end
	-- the big lake
	local bl = M.bigLake(st)
	if bl then
		local lr = math.ceil(M.BIGLAKE_NEAR_M / cs)
		local found = false
		for dr = -lr, lr do
			for dc = -lr, lr do
				local cc, rr = c + dc, r + dr
				if not found and inside(st, cc, rr) and st.bl[idx(st, cc, rr)] == bl.id and (dc * dc + dr * dr) * cs * cs <= M.BIGLAKE_NEAR_M ^ 2 then
					found = true
				end
			end
		end
		if found then
			put("biglake", 1)
			out.lake = true
			out.ldir = dirOf(x - bl.x, y - bl.y)
		end
	end
	-- relief
	local pk = st.peaks and st.peaks[1]
	if pk and pk.h >= (st.median or 0) + M.PEAK_MIN and (pk.x - x) ^ 2 + (pk.y - y) ^ 2 <= M.PEAK_NEAR_M ^ 2 then put("peak", 1) end
	if st.range then
		local g = st.gl or {}
		if g[idx(st, c, r)] == st.range then
			put("summit", 0.9)
		else
			local rr0 = math.ceil(M.RANGE_NEAR_M / cs)
			local near = false
			for dr = -rr0, rr0 do
				for dc = -rr0, rr0 do
					local cc, rr = c + dc, r + dr
					if not near and inside(st, cc, rr) and g[idx(st, cc, rr)] == st.range then
						if math.abs(dc) <= 1 and math.abs(dr) <= 1 then put("summit", 0.7) end
						near = true
					end
				end
			end
			if near then put("range", 0.8) end
		end
		-- a divide: on the high ground, two long rivers on opposite sides
		if (w.summit or 0) >= 0.7 then
			local dr0 = math.ceil(M.DIVIDE_M / cs)
			local nearC = {}
			for dr = -dr0, dr0 do
				for dc = -dr0, dr0 do
					local cc, rr = c + dc, r + dr
					if inside(st, cc, rr) then
						local id = st.rl[idx(st, cc, rr)]
						if id and st.rc[id].long then
							local d = dc * dc + dr * dr
							if nearC[id] == nil or d < nearC[id].d then nearC[id] = { d = d, a = G.atan2(dr, dc) } end
						end
					end
				end
			end
			local list = {}
			for id, e in pairs(nearC) do list[#list + 1] = { id = id, a = e.a } end
			table.sort(list, function(a, b) return a.id < b.id end)
			for i = 1, #list do
				for j = i + 1, #list do
					local d = math.abs(list[i].a - list[j].a)
					if d > math.pi then d = 2 * math.pi - d end
					if math.deg(d) >= 120 then put("divide", 1) end
				end
			end
		end
	end
	if st.valley then
		local vr = math.ceil(M.VALLEY_NEAR_M / cs)
		local found = false
		for dr = -vr, vr do
			for dc = -vr, vr do
				local cc, rr = c + dc, r + dr
				if not found and inside(st, cc, rr) and st.rl[idx(st, cc, rr)] == st.valley then found = true end
			end
		end
		if found then put("mainvalley", 0.9); out.valley = true end
	end
	-- coast
	local b = nearest(st.bays, x, y, M.BAY_NEAR_M)
	if b then
		put("bay", 1)
		if st.bays[1] == b then put("bigbay", 1); out.bigbay = true end
	end
	if nearest(st.capes, x, y, M.CAPE_NEAR_M) then put("headland", 1) end
	if nearest(st.narrows, x, y, M.NARROW_NEAR_M) then put("narrows", 1) end
	if nearest(st.isthmus, x, y, M.NARROW_NEAR_M) then put("isthmus", 1) end
	return out
end

M.WATER_NEAR_M = 1500     -- M.waterNear: water bodies read this far round a town

--- The wide water near (x, y) by the survey (2026-10-14, NEXT_PHASE_BRIEF 49: "Lake in the Hills" on an island map with
--- `lakes=0 sea=true`): { sea = bool, lake = bool, river = bool, lakes = n } (a lake: a body that isn't the sea and
--- wasn't merged into a river; lakes: how many), or nil without a survey. r (m, default WATER_NEAR_M) bounds the cells read.
function M.waterNear(st, x, y, r)
	if st == nil or not tonumber(x) or not tonumber(y) or st.cells == nil or st.bl == nil then return nil end
	local cs = st.cs
	local c = clamp(math.floor((x - st.x0) / cs), 0, st.nx - 1)
	local rr0 = clamp(math.floor((y - st.y0) / cs), 0, st.ny - 1)
	local rad = math.min(math.ceil((r or M.WATER_NEAR_M) / cs), 40)
	-- (lakes: the distinct lake bodies within reach, NEXT_PHASE_BRIEF 61's "Twin Lakes")
	local out = { sea = false, lake = false, river = false, lakes = 0 }
	local seenB = {}
	for dr = -rad, rad do
		for dc = -rad, rad do
			local cc, rr = c + dc, rr0 + dr
			if inside(st, cc, rr) and dc * dc + dr * dr <= rad * rad then
				local j = idx(st, cc, rr)
				local b = st.bl[j]
				if b and st.bc[b] and not st.bc[b].dead then
					if st.bc[b].sea then out.sea = true
					else
						out.lake = true
						if not seenB[b] then seenB[b] = true; out.lakes = out.lakes + 1 end
					end
				elseif st.rl[j] then
					out.river = true
				end
			end
		end
	end
	return out
end

-- tags in the log's order
M.CUE_ORDER = { "confluence", "twin", "mouth", "bend", "falls", "upper", "lower", "north", "south", "east", "west",
	"central", "biglake", "peak", "summit", "range", "divide", "mainvalley", "bay", "bigbay", "headland", "narrows",
	"isthmus" }

--- "confluence:1.00,north:0.70" (the cue tags, the strongest first), "-" for none.
function M.cueText(cue)
	if cue == nil or cue.w == nil then return "-" end
	local list = {}
	for i, t in ipairs(M.CUE_ORDER) do if cue.w[t] then list[#list + 1] = { t, cue.w[t], i } end end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[3] < b[3] end)
	local parts = {}
	for _, e in ipairs(list) do parts[#parts + 1] = string.format("%s:%.2f", e[1], e[2]) end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- NAMES survey fields: { {k, v} } for the driver's log.
function M.surveyFields(st)
	local o = M.counts(st)
	local capped = (#(st.capped or {}) > 0) and table.concat(st.capped, "+") or "-"
	return { { "rivers", o.rivers }, { "forks", o.forks }, { "mouths", o.mouths }, { "bends", o.bends },
		{ "falls", o.falls }, { "lakes", o.lakes }, { "sea", o.sea }, { "peaks", o.peaks }, { "ranges", o.ranges },
		{ "valley", o.valley }, { "bays", o.bays }, { "capes", o.capes }, { "narrows", o.narrows },
		{ "isthmus", o.isthmus }, { "grid", st.nx .. "x" .. st.ny }, { "cell", math.floor(st.cs + 0.5) },
		{ "wet", st.nWet or 0 }, { "units", st.work or 0 }, { "capped", capped } }
end

return M
