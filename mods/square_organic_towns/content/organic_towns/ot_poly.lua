-- Organic Towns: polycentric next steps (pure; later-ideas phase, 2026-10-13; NEXT_PHASE_BRIEF 14 open items).
--
-- The polycentric metropolis (ot_metro) had its secondary centres on a ring along the town axis, grown by the twin
-- shape, with the master plan's one pattern everywhere. The open items: centres at a junction of arterials, a core style
-- per centre, centres added over time, the empty-street budget kept. ot_metro now places a centre at a country-road
-- junction in its range (MET.junctionCentre: where the roads between towns cross is where a second downtown grows), adds
-- a third centre from POLY_THIRD_CAP, and gives every secondary centre a seeded core kind (MET.coreKind: "grid" or the
-- plan's own pattern). This module lays the grid cores into the master plan (M.applyPlan, from ot_core.masterPlan): a
-- small straight grid (N x N blocks, the station quarter's grid layer ot_motif_town.layGrid) centred on the centre,
-- squared to the junction's roads (else the town axis), the plan's own pieces inside it dropped. Its pieces are motif
-- pieces (free of the envelope; the housed front, the lead limit and the polycentric empty budget, ot_metro POLY_HOUSED /
-- POLY_EMPTY, apply as to every piece), so a centre's grid is built only when the houses reach it. Nothing saved; plain
-- base town streets; no new node or proposal rule (the crash rule is untouched).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local L = ug_require "square_organic_towns::/organic_towns/ot_motif_land.lua"
local RM = ug_require "square_organic_towns::/organic_towns/ot_motif_road.lua"
local TW = ug_require "square_organic_towns::/organic_towns/ot_motif_town.lua"

local M = {}

M.ON = true
M.N = { 3, 4 }                -- blocks each way (seeded per centre)
M.LEN = { 1.0, 70, 110 }      -- block length: x block length, clamped (m)
M.DEP = { 1.0, 55, 90 }       -- block depth: x block depth, clamped (m)
M.GRADE = 0.8                 -- x maxSlope per block side at most
M.ROAD = 18                   -- m: grid streets keep this far from country roads (their crossing junction included)
M.GAP = 30                    -- m: a junction centre's grid starts this far off the roads
M.PREFIX = "mpc"

local function key(c) return function(k, j) return M.PREFIX .. c .. ":" .. k .. ":" .. j end end

--- The grid's orientation at a centre: the junction's first road heading, else the town axis (radians).
local function orient(style, cc)
	if cc.heads and #cc.heads > 0 then return cc.heads[1] end
	return (style.shape and style.shape.axis) or style.axis or 0
end

--- Grid geometry of secondary centre index c (record cc = { x, y, ... }): { n, len, dep, J, segs, nOk, h } or nil, why.
function M.geo(style, cc, c, sampler, g)
	if sampler == nil then return nil, "noTerrain" end
	local seed = style.seed or 1
	local n = M.N[1] + math.floor(rng.unit(seed, "polyN", c) * (M.N[2] - M.N[1] + 1))
	local len = L.clampSpec(M.LEN, style.block and style.block.len or 80)
	local dep = L.clampSpec(M.DEP, style.block and style.block.depth or 60)
	local h = orient(style, cc)
	local fx, fy = math.cos(h), math.sin(h)
	local ux, uy = -fy, fx
	local cx, cy = cc[1] or cc.x, cc[2] or cc.y
	-- (a junction centre: the grid in the crossing's quadrant facing the main centre, GAP off the roads (the mod never
	-- crosses a country road); else centred on the centre)
	local junction = cc.src == "junction"
	local sa, sb = 1, 1
	if junction then
		local tx, ty = style.centre[1] - cx, style.centre[2] - cy
		sa = (tx * fx + ty * fy) >= 0 and 1 or -1
		sb = (tx * ux + ty * uy) >= 0 and 1 or -1
	end
	local function J(k, j)
		local a, b
		if junction then a, b = sa * (M.GAP + k * dep), sb * (M.GAP + j * len)
		else a, b = (k - n / 2) * dep, (j - n / 2) * len end
		return cx + fx * a + ux * b, cy + fy * a + uy * b
	end
	local maxSlope = style.maxSlope or 0.1
	local setback = style.waterSetback or 25
	local ridx = RM.segIndex((style.roads and style.roads.segs) or {})
	local function okSeg(ax, ay, bx, by)
		local mx, my = (ax + bx) / 2, (ay + by) / 2
		for _, p in ipairs({ { ax, ay }, { mx, my }, { bx, by } }) do
			if L.offEdge(style, p[1], p[2]) then return false end
		end
		if T.wetAlong(sampler, { { ax, ay }, { bx, by } }, setback) then return false end
		if T.grade(sampler, ax, ay, bx, by) > M.GRADE * maxSlope then return false end
		if RM.segNear(ridx, mx, my, M.ROAD) or RM.segNear(ridx, ax, ay, 12) or RM.segNear(ridx, bx, by, 12)
			or RM.segCross(ridx, ax, ay, bx, by) then return false end
		if TW.crossesGraph(g, ax, ay, bx, by) then return false end
		return true
	end
	local segs, nOk = {}, 0
	for k = 0, n do
		for j = 0, n - 1 do
			local ax, ay = J(k, j)
			local bx, by = J(k, j + 1)
			local ok = okSeg(ax, ay, bx, by)
			segs[#segs + 1] = { k, j, k, j + 1, ok = ok }
			if ok then nOk = nOk + 1 end
		end
	end
	for j = 0, n do
		for k = 0, n - 1 do
			local ax, ay = J(k, j)
			local bx, by = J(k + 1, j)
			local ok = okSeg(ax, ay, bx, by)
			segs[#segs + 1] = { k, j, k + 1, j, ok = ok }
			if ok then nOk = nOk + 1 end
		end
	end
	if nOk < 4 then return nil, "noRoom" end
	return { n = n, len = len, dep = dep, J = J, segs = segs, nOk = nOk, h = h, c = { cx, cy }, junction = junction }
end

--- Lays the grid cores of a polycentric metropolis's secondary centres (core "grid") into master plan mp. env = { g,
--- terrain, extent }. Sets mp.polyCores = { { c, kind, planned, runs, why, geo } } (one per secondary centre).
function M.applyPlan(mp, style, env)
	mp.polyCores = nil
	local m = style.metro
	if not M.ON or m == nil or m.variant ~= "polycentric" or #(m.centres or {}) == 0 then return end
	local cores = {}
	for c, cc in ipairs(m.centres) do
		local rec = { c = c, kind = cc.core or "plan", src = cc.src or "ring" }
		if rec.kind == "grid" then
			local geo, why = M.geo(style, cc, c, env.terrain, env.g)
			if geo == nil then
				rec.why = why
			else
				local okAt = {}
				for _, sg in ipairs(geo.segs) do okAt[sg[1] .. ":" .. sg[2] .. ":" .. sg[3] .. ":" .. sg[4]] = sg.ok end
				-- (the grid's rectangle in its own k / j frame: corners J(0, 0) and J(n, n))
				local ox, oy = geo.J(0, 0)
				local kx, ky = geo.J(1, 0)
				local jx, jy = geo.J(0, 1)
				local ax_, ay_ = (kx - ox) / geo.dep, (ky - oy) / geo.dep
				local bx_, by_ = (jx - ox) / geo.len, (jy - oy) / geo.len
				local dk, dj = geo.n * geo.dep, geo.n * geo.len
				local function inRect(x, y)
					local a = (x - ox) * ax_ + (y - oy) * ay_
					local b = (x - ox) * bx_ + (y - oy) * by_
					return a >= -15 and a <= dk + 15 and b >= -15 and b <= dj + 15
				end
				local id = M.PREFIX .. c
				local planned, runs = TW.layGrid(mp, { nk = geo.n, nj = geo.n, J = geo.J, key = key(c),
					prefix = M.PREFIX .. c .. "_", id = id,
					segOk = function(k1, j1, k2, j2) return okAt[k1 .. ":" .. j1 .. ":" .. k2 .. ":" .. j2] end,
					rowCls = function(k) return (k == 0 or k == geo.n) and "medium" or "small" end, drop = inRect })
				-- (the grid's crossings come together: the game joins only dead ends)
				for _, pc in ipairs(mp.pieces) do if pc.motif == id then TW.pair(pc) end end
				rec.planned, rec.runs, rec.geo = planned, runs, geo
			end
		end
		cores[c] = rec
	end
	mp.polyCores = cores
end

--- "c1:grid@junction:built/planned,c2:plan@ring" for the METRO lines ("-" without centres). g = the town's graph.
function M.text(mp, g)
	local cores = mp and mp.polyCores
	if cores == nil or #cores == 0 then return "-" end
	local parts = {}
	for _, r in ipairs(cores) do
		local t = string.format("c%d:%s@%s", r.c, r.kind, r.src)
		if r.kind == "grid" then
			if r.geo then
				local built, planned = 0, 0
				for _, sg in ipairs(r.geo.segs) do
					if sg.ok then
						planned = planned + 1
						local ax, ay = r.geo.J(sg[1], sg[2])
						local bx, by = r.geo.J(sg[3], sg[4])
						if L.segBuilt(g, ax, ay, bx, by, 8) then built = built + 1 end
					end
				end
				t = t .. string.format(":%d/%d", built, planned)
			else
				t = t .. ":" .. tostring(r.why)
			end
		end
		parts[#parts + 1] = t
	end
	return table.concat(parts, ",")
end

return M
