-- Organic Towns: protected meadows for sprawling and character towns (pure; later-ideas phase, 2026-10-13).
--
-- Real map round 4/5: green wedges (ot_wedge) keep the armed shapes (linear, ridge, cross, fingers) from filling into a
-- disc, but the sprawling towns (form sprawling, unshaped: their lobes come from the seeded hotspots on the roads out of
-- town, ot_select.irregularity) and the unarmed character towns had nothing: Barrow-in-Furness (character sprawling,
-- session 2026-10-13_0342_sqot) filled into a blob while its far patches stayed empty. User: "Acton has some nice gaps
-- in it"; "gaps for sprawling and character towns (wedge frames currently cover armed shapes only)".
--
-- The same two levers as the wedges, on the town's lobes instead of a shape's arms:
-- * Meadow reserve (M.inMeadow, ot_select `meadowHeld`): the lobe headings are the hotspots' headings (the roads out of
--   town first, ot_select.irregularity; a shore town: its shore axis both ways), deduplicated within MIN_SEP. Between two
--   neighbouring lobes at least MIN_GAP apart the middle SHARE of the gap is a meadow sector; beyond the core zone
--   (M.coreR: CORE_K x the radius of a disc holding the town's street length, at least CORE_MIN) the mod plans nothing
--   in a meadow sector, never relaxed (as the wedges: the lobes between carry the growth).
-- * Meadow frame (ot_core.frameIncrement through ot_wedge.frameStreets with `accept` = in a meadow sector and no tails):
--   at a demand build, at most every FRAME_GAP_S, the game's unlocked dead ends in a meadow sector beyond 0.6 x the
--   core zone are linked in angular order by locked small streets, so the game's own growth can't run out into the
--   meadow from them (it attaches 0-1 side streets to locked streets, findings towns.md).
-- Plain base town streets, locked (removing the mod leaves ordinary locked streets). Nothing saved: the lobes come from
-- the seed, the roads and the shore each session, the frame from the snapshot's locked streets.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"

local M = {}

M.ON = true
M.MIN_SEP = math.rad(35)   -- lobe headings closer than this are one lobe
M.MIN_GAP = math.rad(70)   -- a meadow only between lobes at least this far apart
M.SHARE = 0.45             -- the meadow sector: this share of the gap, in its middle
M.CORE_K = 0.9             -- core zone: this x the radius of a disc holding the town's street length (x block) ...
M.CORE_MIN = 220           -- ... at least this (m)
M.MAX_SECTORS = 4

--- Does the meadow rule apply? Sprawling towns (any) and character towns without arms (shore, compact); not armed
--- shapes (ot_wedge covers them), not a metropolis or a mech grid style.
function M.applies(style)
	if not M.ON or style == nil or style.metro or style.mech then return false end
	local form = style.form
	if form == nil then return false end
	local sh = style.shape
	local armed = sh ~= nil and (sh.id == "linear" or sh.id == "ridge" or sh.id == "cross" or sh.id == "fingers")
	if armed then return false end
	return form.id == "sprawling" or form.character == true
end

local function wrap2(a) return a % (2 * math.pi) end

--- Lobe headings (radians, sorted 0..2pi) of a style: a shore shape's axis both ways; else the hotspots' headings
--- (irr = ot_select.irregularity(style)), else style.lobeDirs. Deduplicated within MIN_SEP.
function M.lobes(style, irr)
	local c = style.centre
	local raw = {}
	local sh = style.shape
	if sh and sh.id == "shore" and sh.axis then
		raw = { sh.axis, sh.axis + math.pi }
	else
		for _, h in ipairs((irr and irr.hotspots) or {}) do raw[#raw + 1] = G.atan2(h[2] - c[2], h[1] - c[1]) end
		if #raw < 2 then
			raw = {}
			for _, a in ipairs(style.lobeDirs or {}) do raw[#raw + 1] = a end
		end
	end
	local out = {}
	for _, a in ipairs(raw) do
		local w = wrap2(a)
		local dup = false
		for _, b in ipairs(out) do if math.abs(G.wrap(w - b)) < M.MIN_SEP then dup = true; break end end
		if not dup then out[#out + 1] = w end
	end
	table.sort(out)
	return out
end

--- Meadow sectors between neighbouring lobes: { {mid, half} } (radians), at most MAX_SECTORS (widest first).
function M.sectors(lobes)
	local out = {}
	local n = #lobes
	if n < 2 then return out end
	for i = 1, n do
		local a0, a1 = lobes[i], lobes[i % n + 1]
		local gap = (a1 - a0) % (2 * math.pi)
		if gap >= M.MIN_GAP then
			out[#out + 1] = { mid = wrap2(a0 + gap / 2), half = M.SHARE * gap / 2, gap = gap }
		end
	end
	table.sort(out, function(p, q) return p.gap > q.gap end)
	while #out > M.MAX_SECTORS do table.remove(out) end
	return out
end

--- Core zone radius (m) for graph g: CORE_K x sqrt(L x block / 2pi), at least CORE_MIN.
function M.coreR(g, style)
	local L = 0
	for _, e in ipairs(g.edges or {}) do L = L + OG.edgeLength(g, e) end
	local blk = math.max(style.block and style.block.len or 80, style.block and style.block.depth or 60)
	return math.max(M.CORE_MIN, M.CORE_K * math.sqrt(L * blk / (2 * math.pi)))
end

--- The town's meadow zone: { centre, lobes, sectors, coreR, arms (= lobes, for ot_wedge.frameStreets) } or nil when
--- the rule doesn't apply or there is no sector. irr = ot_select.irregularity(style).
function M.zone(g, style, irr)
	if not M.applies(style) then return nil end
	local lobes = M.lobes(style, irr)
	local sectors = M.sectors(lobes)
	if #sectors == 0 then return nil end
	return { centre = { style.centre[1], style.centre[2] }, lobes = lobes, sectors = sectors, coreR = M.coreR(g, style),
		arms = lobes }
end

--- Is the heading of (x, y) from the zone's centre inside a meadow sector (any distance)?
function M.inSector(z, x, y)
	if z == nil then return false end
	local a = wrap2(G.atan2(y - z.centre[2], x - z.centre[1]))
	for _, s in ipairs(z.sectors) do
		if math.abs(G.wrap(a - s.mid)) <= s.half then return true end
	end
	return false
end

--- true when (x, y) lies in a meadow: beyond the core zone (x k, default 1) and inside a meadow sector.
function M.inMeadow(z, x, y, k)
	if z == nil then return false end
	if G.dist(z.centre[1], z.centre[2], x, y) <= z.coreR * (k or 1) then return false end
	return M.inSector(z, x, y)
end

--- true when the polyline's midpoint or any point lies in a meadow.
function M.polyIn(z, pts)
	if z == nil then return false end
	local mx, my = G.polyAt(pts, 0.5)
	if M.inMeadow(z, mx, my) then return true end
	for _, p in ipairs(pts) do
		if M.inMeadow(z, p[1], p[2]) then return true end
	end
	return false
end

--- "n:deg/deg@coreR" for the logs (sector count, their widths in degrees, core zone radius), "-" without.
function M.text(z)
	if z == nil then return "-" end
	local w = {}
	for _, s in ipairs(z.sectors) do w[#w + 1] = string.format("%.0f", math.deg(2 * s.half)) end
	return string.format("%d:%s@%.0f", #z.sectors, table.concat(w, "/"), z.coreR)
end

return M
