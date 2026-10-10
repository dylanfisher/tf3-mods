-- Better Roundabouts: shared pure geometry of the highway entries (no api.*): the highway's
-- cross-section frame, the slip roads' gore + climb edges, the carriageways with arbitrary tagged
-- gore nodes, the highway bridge's extent, the bridge type by year and the list helper.
-- Extracted unchanged from square_roundabouts_interchange.lua in Phase 7a (INTERCHANGES.md
-- section 3, "Shared helpers"): the Roundabout Interchange builds byte-identical results through
-- it (tests/square_roundabouts/golden_entries.lua). Helpers take plain numbers, never a spec:
-- each entry resolves its own DEV-ONLY overrides (ixClear, ixGoreRun, ...) before calling.
--
-- Frame: highway along x, z up; right-hand traffic: eastbound (+x) carriageway "s" south (y < 0),
-- westbound (-x) carriageway "n" north. Left-hand traffic is the caller's geom.mirrorX.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local S = geom.shapes

local ramps = {}

-- Base highway templates (one-way carriageways, yearFrom 1940); half width = lanes + shoulders
-- (laneConfigs: 2+5+2, 4+5+5+4, 4+5+5+5+4 m).
local STREET = "::/infrastructure/street/"
ramps.HIGHWAYS = {
	{ template = STREET .. "highway/highway_new_small.street_template", halfWidth = 4.5 },
	{ template = STREET .. "highway/highway_new_medium.street_template", halfWidth = 9 },
	{ template = STREET .. "highway/highway_new_large.street_template", halfWidth = 11.5 },
}
ramps.DEFAULT_HIGHWAY = 2
-- Slip roads: the base interchanges' slip template (one-way, one lane).
ramps.RAMP = { template = STREET .. "highway/highway_new_small.street_template", halfWidth = 4.5 }
-- Kerb-to-kerb gap between the carriageways: the base diamond's (centres +-13.5 m, large highway
-- half width 11.5 m; base sc.lua:293-298). Carriageway centres at +-(half width + MEDIAN / 2).
ramps.MEDIAN = 4
-- A slip road joins its carriageway at a node this far outside the carriageway node, with the same
-- tag and a tangent parallel to the highway: the base diamond's entranceExitOffset (sc.lua:333).
ramps.MERGE_OFFSET = 4
-- The slip road's gore edge (ramps.gore): it leaves the carriageway's band (GORE_GAP clear) over
-- GORE_RUN along the highway, or GORE_SLOPE x the lateral distance for wide highways (a turn of
-- about 30 degrees at most, as the base diamond's slip roads).
ramps.GORE_GAP = 1
ramps.GORE_RUN = 30
ramps.GORE_SLOPE = 2.5
-- Height of the upper level (base diamond bridgeHeight, sc.lua:331): ramps rise 0 -> 8 m.
ramps.HEIGHT = 8
-- Bridge type by year (PHASE5.md 5a: steel from 1940, concrete, the base interchanges' bridge,
-- from 1970; concrete when the year is missing).
ramps.BRIDGE_STEEL = "::/infrastructure/bridge/steel.bridge"
ramps.BRIDGE_CONCRETE = "::/infrastructure/bridge/concrete.bridge"
ramps.CONCRETE_FROM = 1970
-- Plan gap between the highway's outer kerb and the kerb of an upper-level road that is not a
-- bridge (it stands on an embankment), and between a lower-level road and the highway bridge's
-- end. 8 m: about the toe of an 8 m embankment.
ramps.CLEAR = 8

--- Bridge type for the year (nil: concrete, as the base interchanges).
function ramps.bridgeType(year)
	if year and year < ramps.CONCRETE_FROM then return ramps.BRIDGE_STEEL end
	return ramps.BRIDGE_CONCRETE
end

--- Highway cross-section numbers: highway (a HIGHWAYS entry), hwH (its half width), c (carriageway
-- centre |y|), hwRamp (slip road half width), corr (the highway's outer kerb |y|), clear (the plan
-- gap, CLEAR or a dev override), yClear (corr + clear). Callers add their own fields.
function ramps.frame(highwayIndex, clear)
	local hwy = ramps.HIGHWAYS[highwayIndex]
	local f = {
		highway = hwy,
		hwH = hwy.halfWidth,
		c = hwy.halfWidth + ramps.MEDIAN / 2,            -- carriageway centre
		hwRamp = ramps.RAMP.halfWidth,
	}
	f.corr = f.c + f.hwH        -- the highway's outer kerb
	f.clear = clear
	f.yClear = f.corr + f.clear
	return f
end

--- The gore of a slip road on carriageway cw ("s" / "n") of frame f, io "in" (off-ramp:
-- carriageway -> slip road) or "out" (on-ramp), whose carriageway node is at x = -+xm (before /
-- after the junction in driving order) and height z. Returns {m, g, head, tag, before, io}:
--   m: the slip road's node on the carriageway, MERGE_OFFSET outside the carriageway node, same tag;
--   g: the plain node where the slip road's band is GORE_GAP clear of the carriageway's, at least
--      goreRun (or GORE_SLOPE x the lateral distance) along the highway from m, towards the junction;
--   head: the carriageway's driving direction (the gore edge is parallel to it at both ends);
--   tag: tagPrefix .. cw .. "_w" / "_e" (the carriageway node's tag).
function ramps.gore(f, cw, io, xm, goreRun, tagPrefix, z)
	local sgn = cw == "s" and -1 or 1           -- carriageway side (y)
	local head = cw == "s" and { 1, 0, 0 } or { -1, 0, 0 }
	-- off-ramps leave the carriageway before the junction, on-ramps join it after
	local before = (io == "in") == (cw == "s") and -1 or 1
	local tag = tagPrefix .. cw .. (before < 0 and "_w" or "_e")
	local m = { before * xm, sgn * (f.c + ramps.MERGE_OFFSET), z }
	local lateral = f.hwH + f.hwRamp + ramps.GORE_GAP - ramps.MERGE_OFFSET
	local run = math.max(goreRun, ramps.GORE_SLOPE * lateral)
	-- G: towards the junction along the highway
	local g = { m[1] - before * run, sgn * (f.c + f.hwH + f.hwRamp + ramps.GORE_GAP), z }
	return { m = m, g = g, head = head, tag = tag, before = before, io = io }
end

--- The two edges of a slip road with gore `gore` (ramps.gore) whose other end is endPos, joined
-- along unit endDir (the direction of travel there) with tag endTag, in driving order:
--   gore: level, between m and g, parallel to the highway at both ends;
--   climb: from g (parallel to the highway) to endPos; it carries the whole height change.
-- Each edge has .part "gore" / "climb".
function ramps.slipEdges(gore, endPos, endDir, endTag)
	local m, g, head, tag = gore.m, gore.g, gore.head, gore.tag
	local ge, climb
	if gore.io == "in" then
		ge, climb = S.curveEdge(m, head, g, head, tag, nil), S.curveEdge(g, head, endPos, endDir, nil, endTag)
	else
		ge, climb = S.curveEdge(g, head, m, head, nil, tag), S.curveEdge(endPos, endDir, g, head, endTag, nil)
	end
	ge.part, climb.part = "gore", "climb"
	if gore.io == "in" then return { ge, climb } end
	return { climb, ge }
end

-- Phase 7b (Highway Interchange) -------------------------------------------------------------
-- Pure additions: the Roundabout Interchange does not call them (its goldens stay unchanged).

--- The level gore edge of `gore` alone, in driving order: the same edge as ramps.slipEdges' gore
-- edge (.part "gore"), for ramps whose climb is not a single edge (loops, wrapped diagonals).
function ramps.goreEdge(gore)
	local e
	if gore.io == "in" then
		e = S.curveEdge(gore.m, gore.head, gore.g, gore.head, gore.tag, nil)
	else
		e = S.curveEdge(gore.g, gore.head, gore.m, gore.head, nil, gore.tag)
	end
	e.part = "gore"
	return e
end

--- A circular arc in plan (z 0): centre, centreline radius r, from angle a0 sweeping `sweep`
-- radians (positive anticlockwise, negative clockwise), split into the fewest edges of at most
-- geom.MAX_EDGE_ANGLE (the ring rule) with circle handles r * geom.hermiteScale(step). from / to
-- (optional) replace the computed end points exactly (so the arc meets its neighbours bit for bit).
function ramps.arcEdges(centre, r, a0, sweep, from, to)
	local n = math.max(1, math.ceil(math.abs(sweep) / geom.MAX_EDGE_ANGLE - 1e-7))
	local step = sweep / n
	local k = geom.hermiteScale(math.abs(step)) * r
	local sgn = step < 0 and -1 or 1
	local function at(a) return { centre[1] + r * math.cos(a), centre[2] + r * math.sin(a), 0 } end
	local function tan(a) return { -math.sin(a) * sgn * k, math.cos(a) * sgn * k, 0 } end
	local edges = {}
	for i = 1, n do
		local a, b = a0 + step * (i - 1), a0 + step * i
		edges[i] = { p0 = at(a), t0 = tan(a), p1 = at(b), t1 = tan(b) }
	end
	if from then edges[1].p0 = { from[1], from[2], 0 } end
	if to then edges[n].p1 = { to[1], to[2], 0 } end
	for i = 2, n do edges[i].p0 = edges[i - 1].p1 end
	return edges
end

local function planLength(e)
	local total, prev = 0, e.p0
	for k = 1, 32 do
		local p = S.hermite(e, k / 32)
		local dx, dy = p[1] - prev[1], p[2] - prev[2]
		total = total + math.sqrt(dx * dx + dy * dy)
		prev = p
	end
	return total
end

--- Heights along a chain of edges in driving order (each edge's p1 is the next one's p0 in
-- plan): z goes from z0 to z1 by a smoothstep of the plan length s, z0 + (z1 - z0) (3u^2 - 2u^3),
-- u = s / S: flat at both ends, peak grade 1.5 x the average. Every end gets its height and a
-- tangent z = the profile's slope x the tangent's plan length (the base addCurvedRamp also uses
-- non-flat tangents mid-ramp, sc.lua:24-27). Replaces the edges' p / t tables (no sharing).
function ramps.profile(edges, z0, z1)
	local lens, total = {}, 0
	for i, e in ipairs(edges) do
		lens[i] = planLength(e)
		total = total + lens[i]
	end
	local dz = z1 - z0
	local function set(p, t, s)
		local u = s / total
		local z = z0 + dz * u * u * (3 - 2 * u)
		local slope = dz / total * 6 * u * (1 - u)
		return { p[1], p[2], z }, { t[1], t[2], slope * math.sqrt(t[1] * t[1] + t[2] * t[2]) }
	end
	local s = 0
	for i, e in ipairs(edges) do
		e.p0, e.t0 = set(e.p0, e.t0, s)
		s = s + lens[i]
		if i == #edges then s = total end
		e.p1, e.t1 = set(e.p1, e.t1, s)
	end
	return total
end

--- Plan length, average and peak gradient of a chain of edges (|z| change over plan length;
-- peak over 64 samples per edge).
function ramps.gradient(edges)
	local plan, peak = 0, 0
	for _, e in ipairs(edges) do
		local prev = e.p0
		for k = 1, 64 do
			local p = S.hermite(e, k / 64)
			local dx, dy = p[1] - prev[1], p[2] - prev[2]
			local d = math.sqrt(dx * dx + dy * dy)
			plan = plan + d
			if d > 1e-9 then peak = math.max(peak, math.abs(p[3] - prev[3]) / d) end
			prev = p
		end
	end
	local first, last = edges[1], edges[#edges]
	return plan, math.abs(last.p1[3] - first.p0[3]) / plan, peak
end

--- Loop ramp, canonical case (right-hand frame): an on-ramp (gore io "out") onto carriageway "s"
-- west of the cross road (x = 0). From the terminal T = (0, g.y - 2r) on the cross road: a straight
-- stub west to (g.x, T.y) (perpendicular to the cross road), a clockwise half circle of centreline
-- radius r (west -> north -> east: right turns) up to the gore's G, heading +x, then the level gore
-- edge. Heights: zTerm at T, the gore's height at G (ramps.profile over stub + arc); the gore edge is
-- level. Other loops are mirror / rotation images (square_roundabouts_highway.lua). Returns the
-- edges in driving order, .part "stub" / "loop" / "gore"; T carries termTag.
function ramps.loop(gore, r, termTag, zTerm)
	local g = gore.g
	local y0 = g[2] - 2 * r
	local stub = S.straightEdge({ 0, y0, 0 }, { g[1], y0, 0 }, termTag, nil)
	stub.part = "stub"
	local climb = { stub }
	for _, e in ipairs(ramps.arcEdges({ g[1], g[2] - r, 0 }, r, -math.pi / 2, -math.pi, stub.p1, g)) do
		e.part = "loop"
		climb[#climb + 1] = e
	end
	ramps.profile(climb, zTerm, g[3])
	climb[#climb + 1] = ramps.goreEdge(gore)
	return climb
end

--- Half of the highway bridge (highway over the lower roads): the largest |x| at which a lower road
-- (edges = {{e, hw}}, hw its half width) comes within f.clear of the highway in plan, plus f.clear,
-- rounded up to 1 m.
function ramps.highwayBridgeHalf(f, edges)
	local xb = 0
	for _, x in ipairs(edges) do
		local e, hw = x.e, x.hw
		local n = math.max(8, math.ceil(S.edgeLength(e) / 1.0))
		for k = 0, n do
			local p = S.hermite(e, k / n)
			if math.abs(p[2]) < f.corr + hw + f.clear then
				xb = math.max(xb, math.abs(p[1]) + hw + f.clear)
			end
		end
	end
	return math.ceil(xb)
end

--- Straight carriageway edges at height z: cwNodes.s / cwNodes.n = {xs, tags, bridged} with the
-- node x positions ascending (west to east), tags[i] the node's tag or false, bridged[seg] true
-- when segment seg (between xs[seg] and xs[seg + 1]) is a bridge. South ("s") runs east, north
-- ("n") west (its nodes reversed). Returns the plain and the bridged edges, south first, each
-- edge with .cw.
function ramps.carriageways(f, cwNodes, z)
	local hwN, hwB = {}, {}
	for _, cw in ipairs({ "s", "n" }) do
		local y = cw == "s" and -f.c or f.c
		local xs, tags, bridged = cwNodes[cw].xs, cwNodes[cw].tags, cwNodes[cw].bridged or {}
		local pts = {}
		for i, x in ipairs(xs) do pts[i] = { pos = { x, y, z }, tag = tags[i] or nil } end
		if cw == "n" then
			local rev = {}
			for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
			pts = rev
		end
		for i = 1, #pts - 1 do
			local e = S.straightEdge(pts[i].pos, pts[i + 1].pos, pts[i].tag, pts[i + 1].tag)
			e.cw = cw
			local seg = cw == "s" and i or (#pts - i)
			if bridged[seg] then hwB[#hwB + 1] = e else hwN[#hwN + 1] = e end
		end
	end
	return hwN, hwB
end

--- One list of the geometry output (square_roundabouts_result.lua maps it): bridge = a bridge
-- type name (edgeType "BRIDGE") or nil.
function ramps.list(role, entry, halfWidth, edges, bridge)
	return {
		role = role, template = entry.template, halfWidth = halfWidth, edges = edges,
		edgeType = bridge and "BRIDGE" or nil, edgeTypeName = bridge,
	}
end

return ramps
