-- Organic Towns: picks the next increment from a town's master plan (pure).
--
-- A grower (ot_grow_grid, ot_grow_organic) turns StyleParams into a deterministic master plan for the town:
--   mp = { junctions = { [key] = {x, y} }, pieces = { { key, a = junction key, b = junction key,
--          pts = {{x, y}...} (a ... b), class, curved = bool } } }
-- Pieces share junction points exactly. select() matches the plan against the snapshot graph (built, blocked,
-- reached) and grows the network greedily from what is reached, cheapest first, up to the edge budget.
-- The result is a list of streets for ot_plan.plan.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local P = ug_require "square_organic_towns::/organic_towns/ot_plan.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"
local WG = ug_require "square_organic_towns::/organic_towns/ot_wedge.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local LN = ug_require "square_organic_towns::/organic_towns/ot_lane.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"
local MD = ug_require "square_organic_towns::/organic_towns/ot_meadow.lua"
local LAND = ug_require "square_organic_towns::/organic_towns/ot_land.lua"
local SK = ug_require "square_organic_towns::/organic_towns/ot_skeleton.lua"
local LP = ug_require "square_organic_towns::/organic_towns/ot_lockpol.lua"
local KN = ug_require "square_organic_towns::/organic_towns/ot_knot.lua"
local CK = ug_require "square_organic_towns::/organic_towns/ot_check.lua"

local M = {}

local exp = math.exp

--- Distance from point to the segment centre -> station (for station pull).
local function stationDist(style, x, y)
	local best = nil
	for _, s in ipairs(style.stations or {}) do
		local sx, sy = s[1] or s.x, s[2] or s.y
		local d = G.pointSegDist(x, y, style.centre[1], style.centre[2], sx, sy)
		if best == nil or d < best then best = d end
	end
	return best
end

--- Distance from a point to a polyline.
local function polyDist(pts, x, y)
	local best = math.huge
	for i = 2, #pts do
		local d = G.pointSegDist(x, y, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
		if d < best then best = d end
	end
	return best
end

--- true when graph nodes `from` and `to` are joined by a chain of edges running along the polyline: every
--- node on the way and every edge midpoint within `tol` of it (at most 12 edges).
function M.alongGraph(g, pts, from, to, tol)
	if from == to then return false end
	local visited = { [from] = true }
	local frontier = { from }
	for _ = 1, 12 do
		local nextF = {}
		for _, id in ipairs(frontier) do
			local a = g.nodeById[id]
			for _, eid in ipairs(g.adj[id] or {}) do
				local e = g.edgeById[eid]
				local o = OG.other(e, id)
				if not visited[o] then
					local b = g.nodeById[o]
					if polyDist(pts, (a.x + b.x) / 2, (a.y + b.y) / 2) <= tol then
						if o == to then return true end
						if polyDist(pts, b.x, b.y) <= tol then
							visited[o] = true
							nextF[#nextF + 1] = o
						end
					end
				end
			end
		end
		if #nextF == 0 then return false end
		frontier = nextF
	end
	return false
end

local function occRadius(style, opts)
	return opts.occR or G.clamp(math.min(style.block.len, style.block.depth) * 0.35, 8, 30)
end

--- Classifies one piece: { built, blocked, excluded = "water"|"steep" }. `jnode` maps junction keys to graph
--- node ids (M.matchJunctions).
-- Green reserves (2026-10-12, user on the Density: control twin: "green gaps and interesting shapes": streets curving
-- around open meadows, not every block filled). A few seeded discs (style.greens, ot_style.greenReserves: organic
-- styles and metropolis parks) where no plan piece goes, so the town grows around them and they stay enclosed open
-- land. The game's own street growth may still enter them (no control over it).
M.GREEN = true

--- true when a point of the polyline (or its midpoint) lies inside one of style.greens ({x, y, r}).
function M.inGreen(style, pts)
	if not M.GREEN then return false end
	local greens = style.greens
	if greens == nil or #greens == 0 then return false end
	local mx, my = G.polyAt(pts, 0.5)
	for _, gr in ipairs(greens) do
		if G.dist(gr[1], gr[2], mx, my) < gr[3] then return true end
		for _, p in ipairs(pts) do
			if G.dist(gr[1], gr[2], p[1], p[2]) < gr[3] then return true end
		end
	end
	return false
end

M.ROAD_BLOCK = true
M.ROAD_CLEAR = 12          -- m: a piece's points this near a country road's centre line count as onto it
local ROAD_CELL = 100
--- true when polyline pts crosses a country road segment of roads (ot_roads.trace: segs) or comes within ROAD_CLEAR of
--- one (its ends excepted: a street may end beside a road). The segment index is cached on roads.
function M.nearRoads(roads, pts)
	local segs = roads.segs
	if segs == nil or #segs == 0 or #pts < 2 then return false end
	local idx = roads._selIdx
	if idx == nil then
		idx = {}
		for _, sg in ipairs(segs) do
			-- (G.cellRange: a bad / huge segment stays out of the index, hang guard)
			local x0, x1, y0, y1 = G.cellRange(sg[1], sg[2], sg[3], sg[4], 20, ROAD_CELL)
			for cx = x0 or 1, x1 or 0 do
				for cy = y0, y1 do
					local k = cx * 65536 + cy
					local l = idx[k]
					if l == nil then l = {}; idx[k] = l end
					l[#l + 1] = sg
				end
			end
		end
		roads._selIdx = idx
	end
	local function cellOf(x, y) return idx[math.floor(x / ROAD_CELL) * 65536 + math.floor(y / ROAD_CELL)] end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local seen = {}
		for _, p in ipairs({ a, b, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 } }) do
			for _, sg in ipairs(cellOf(p[1], p[2]) or {}) do
				if not seen[sg] then
					seen[sg] = true
					if G.segIntersect(a[1], a[2], b[1], b[2], sg[1], sg[2], sg[3], sg[4], 1e-6) then return true end
				end
			end
		end
	end
	for _, p in ipairs(G.resample(pts, 10)) do
		local d0 = G.dist(p[1], p[2], pts[1][1], pts[1][2])
		local d1 = G.dist(p[1], p[2], pts[#pts][1], pts[#pts][2])
		if d0 > 15 and d1 > 15 then
			for _, sg in ipairs(cellOf(p[1], p[2]) or {}) do
				if G.pointSegDist(p[1], p[2], sg[1], sg[2], sg[3], sg[4]) < M.ROAD_CLEAR then return true end
			end
		end
	end
	return false
end

local function classifyPiece(g, pc, style, opts, jnode, occR)
	local st = {}
	if #g.edges == 0 then
		-- nothing to be built on or blocked by
	elseif jnode[pc.a] and jnode[pc.b] then
		st.built = M.alongGraph(g, pc.pts, jnode[pc.a], jnode[pc.b], opts.builtTol or 6) or nil
	end
	if not st.built and #g.edges > 0 then
		local mx, my = G.polyAt(pc.pts, 0.5)
		local skip = {}
		if jnode[pc.a] then skip[jnode[pc.a]] = true end
		if jnode[pc.b] then skip[jnode[pc.b]] = true end
		if OG.distToEdges(g, mx, my, occR, skip) then
			st.blocked = true
		else
			for i = 2, #pc.pts do
				local a, b = pc.pts[i - 1], pc.pts[i]
				if OG.crossing(g, a[1], a[2], b[1], b[2], skip) then st.blocked = true; break end
			end
		end
	end
	-- country roads beyond the snapshot (M2, 2026-10-13: style.roads from ot_roads.trace; the graph holds only their
	-- first stretch): a piece across or onto one is blocked, as one across a street of the graph
	if not st.built and not st.blocked and M.ROAD_BLOCK and style.roads and M.nearRoads(style.roads, pc.pts) then
		st.blocked = true
	end
	if not st.built and not st.blocked and M.inGreen(style, pc.pts) then st.excluded = "green" end
	-- map edge (ot_map, 2026-10-13): nothing within MARGIN of the map boundary (style.bounds; nil: unknown, no limit)
	if not st.built and not st.blocked and not st.excluded and style.bounds and MAP.polyNearEdge(style.bounds, pc.pts) then
		st.excluded = "edge"
	end
	local terrain = opts.terrain
	if not st.built and not st.blocked and not st.excluded and terrain then
		if T.wetAlong(terrain, pc.pts, style.waterSetback) then
			st.excluded = "water"
		elseif T.pathMaxGrade(terrain, pc.pts) > (opts.maxGrade or style.maxSlope) then
			st.excluded = "steep"
		end
	end
	return st
end

--- Junction positions as a node hash (kept on the plan, derived data): idx graph whose node id i is the
--- junction keys[i] (keys sorted).
function M.junctionIndex(mp)
	if mp.jindex == nil then
		local idx = OG.new()
		local keys = {}
		for k in pairs(mp.junctions) do keys[#keys + 1] = k end
		table.sort(keys)
		for i, k in ipairs(keys) do
			local j = mp.junctions[k]
			OG.addNode(idx, i, j[1], j[2], 0, false)
		end
		mp.jindex, mp.jkeys = idx, keys
	end
	return mp.jindex, mp.jkeys
end

--- Junction keys (sorted) and their graph nodes: jnode[key] = nearest graph node id within snapR,
--- nodeUsed[node id] = true. Looks up each graph node in the plan's junction hash.
function M.matchJunctions(g, mp, snapR)
	snapR = snapR or 8
	local idx, keys = M.junctionIndex(mp)
	local jnode, nodeUsed, dist = {}, {}, {}
	for _, n in ipairs(g.nodes) do
		local j, d = OG.nearestNode(idx, n.x, n.y, snapR)
		if j then
			local k = keys[j.id]
			if dist[k] == nil or d < dist[k] then
				if jnode[k] then nodeUsed[jnode[k]] = nil end
				jnode[k], dist[k] = n.id, d
				nodeUsed[n.id] = true
			end
		end
	end
	return jnode, keys, nodeUsed
end

--- Classifies every plan piece against the graph (tests, debugging; select() classifies lazily).
--- Returns info[piece.key] = { built, blocked, excluded = reason }.
function M.classify(g, mp, style, opts, jnode)
	opts = opts or {}
	jnode = jnode or M.matchJunctions(g, mp, opts.snapR)
	local occR = occRadius(style, opts)
	local info = {}
	for _, pc in ipairs(mp.pieces) do info[pc.key] = classifyPiece(g, pc, style, opts, jnode, occR) end
	return info
end

--- Junction key -> pieces touching it (derived once per plan and kept on it).
local function adjacency(mp)
	if mp.adj == nil then
		local adj = {}
		for _, pc in ipairs(mp.pieces) do
			for _, k in ipairs({ pc.a, pc.b }) do
				local list = adj[k]
				if list == nil then list = {}; adj[k] = list end
				list[#list + 1] = pc
			end
		end
		mp.adj = adj
	end
	return mp.adj
end

--- Street hierarchy (NEXT_PHASE_BRIEF 9: wide streets only on through routes, never on dead-end stubs): true when
--- a main / medium plan piece continues at both of its junctions into another plan piece of at least its class
--- (an arterial line, a spoke, a ring), so its wider template is used; false for small pieces, connectors,
--- cul-de-sacs and the tips of lines that end in the field (those get the local template). Cached on the plan.
local RANK = { small = 1, medium = 2, main = 3 }
function M.through(mp, pc)
	local r = RANK[pc.class] or 1
	if pc.connector or pc.culDeSac or r < 2 then return false end
	mp._through = mp._through or {}
	local v = mp._through[pc.key]
	if v ~= nil then return v end
	local adj = adjacency(mp)
	v = true
	for _, k in ipairs({ pc.a, pc.b }) do
		local found = false
		for _, o in ipairs(adj[k] or {}) do
			if o ~= pc and (RANK[o.class] or 1) >= r and not o.culDeSac then found = true break end
		end
		if not found then v = false break end
	end
	mp._through[pc.key] = v
	return v
end

---------------------------------------------------------------------------
-- Irregular growth (PLAN.md 6.2 "Irregular growth"): the greedy order below decides which way a town grows.
-- Plain distance from the centre grows even rings. Real towns grow unevenly, so with `style.irregular` the
-- distance is scaled by a seeded angular preference (some sectors reach further), corridors along main
-- streets grow ahead (ribbons), seeded hotspots pull patches out along a main street (leapfrog), and coast
-- towns lean toward the water side. Everything is deterministic per town (style.seed).

-- Leads (showcase 2026-10-11: 300-800 m empty arterial stubs far beyond the houses): a new piece may reach at most
-- this many pieces beyond the network the town has (depth 0 = a junction on an existing street). A main / medium
-- street goes one piece (about one block) ahead, small streets two (the cross streets that close the blocks
-- beside it). Pieces that close a loop (both ends reached) always may. Off on an empty graph (a new town).
M.LEAD_DEPTH = { main = 1, medium = 1, small = 2 }

-- Look rules (showcase v2 screenshots, 2026-10-11): no zig-zag chains and no loops joined at one end.
--   zig-zag  a piece may not make the third corner of a chain whose corners (turn > ZIGZAG_DEG at nodes left with
--            2 streets) alternate left / right along one street (a staircase of grid pieces / S-chains of lanes); it
--            waits until a node of the chain has a third street (a T or a crossing). A single S is allowed: blocking
--            it left frontier nodes waiting for a third street that never came (stalled towns, tested).
--   lasso    a loop may close only inside a part of the new network that touches the town through two or more
--            gateways (ot_graph.structure: core nodes, or the core node a dead-end arm hangs from), or that hugs the
--            town (closing piece within HUG blocks of an existing street, stems left out: only dead ends can be
--            joined, so a block beside the town hangs off one stub too). A loop out on a stem reads as a balloon on
--            a string (a loop that starts right at the network everywhere would let cheap loop closures near the
--            dead ends outbid the shape's arms, tested);
--            increments that reach a second gateway (a through route) close their loops normally. Off on an empty
--            graph (a new town) and for a town network without any loop yet.
M.ZIGZAG_DEG = 35
M.CONN_MIN = 24          -- m: shortest connector from an engine dead end to the plan (nearer: none, or a near miss)
M.CONN_TURN = math.rad(60)   -- a connector turns at most this much off the dead end's street
M.CONN_RULES = true      -- the two rules above (tests compare with them off)
-- Young towns (2026-10-12: a 3 x 3 core with two dead ends planned nothing, its centre's streets not joinable and no
-- plan junction within joinR of either dead end at <= CONN_TURN): when a selection comes out empty, it is run again
-- with connectors up to CONN_RELAX_R x joinR (at least CONN_RELAX_MIN) long turning up to CONN_RELAX_TURN.
M.CONN_RELAX_R = 1.8
M.CONN_RELAX_TURN = math.rad(90)
M.CONN_RELAX_MIN = 90    -- m: ... and at least this long (small-block styles: MED hill's joinR is 30 m)
M.ARM_LEAD = 1           -- shaped towns: extra lead depth for main / medium pieces in an arm corridor
M.ARM_LEAD_SMALL = false -- (small pieces too: longer stems, lassos in MED hill towns; tested)
M.FRONT_Q = 0.9          -- the growth front: this quantile of the existing nodes' effective distance ...
M.FRONT_REACH = 2.5      -- ... plus this many blocks is as far as a new piece may reach (shaped towns)
M.FRONT_REACH_PLAIN = 4  -- ... (compact / unshaped towns: the irregular growth leapfrogs to hotspots)
-- (2026-10-18) The growth front counts junctions only, so it moves with the mod's own streets (a game that extends its
-- dead ends never moves it), and the 44 m minimum block left fewer plan pieces in reach (EU organic: one lane fewer
-- per ring cell, ~20 % fewer pieces within 450 m): in test_demand's models towns stopped for good (EU organic, no
-- brake: 8 of 12 grown towns built ~nothing, 4 with the 40 m plan) and a fast grower's larger increments came out half
-- full. Two driver limits widen it: opts.limits.frontRelax (a town whose last plan came out empty, ot_driver: up to
-- FRONT_RELAX blocks, one per step, when the front alone would leave this increment empty too, last of the
-- relaxations) and opts.limits.frontExtra (a fast grower's demand increment, ot_driver FAST_FRONT). The lead limit
-- (MAX_LEAD_M from the housed streets), the housed front and the depth caps hold.
M.FRONT_RELAX = 2
M.SMOOTH = true          -- saw-tooth rules (corner penalty, straight bonus, dangling L legs); tests compare off
M.CORNER_DEG = math.rad(60)
M.CORNER_PEN = 1.5
M.STRAIGHT_DEG = math.rad(20)
M.STRAIGHT_BONUS = 1     -- (0.85 tested: no fewer teeth, more lassos)
M.L_PRUNE = false        -- dangling L legs left out: fewer teeth but much less growth (tested); off
M.LOOP_BONUS = 0.5       -- a piece closing a loop (both ends reached) costs this share
-- no empty loops in organic styles (round R4, 2026-10-13; run 2026-10-13_1945_sqot-dev: unhoused rectangular loops in
-- Kirkham, Fleetwood, Syston, Ormskirk): an organic town's piece that closes a loop among this increment's new streets
-- needs a housed street within EMPTY_LOOP_M of its middle (the housed index; no index yet: allowed); arm and motif
-- pieces exempt
M.EMPTY_LOOP = true
M.EMPTY_LOOP_M = 90
M.ZIGZAG = true          -- defaults of opts.zigzag / opts.loopGuard (tests and the preview compare with them off)
M.LOOP_GUARD = true
M.JOINT_TURN = math.rad(60)   -- a piece leaving an existing dead end turns at most this much off its street ...
M.JOINT_RULE = false          -- ... unless a piece chosen with it continues straight there (a real T): default
-- for opts.jointRule. Showcase v4 (2026-10-12): 15 of 16 DIAGJOINT refusals were edges turning 82-95 deg at a dead
-- end, which leaves a 2-street node with a right-angle kink, while the same edge continued straight built. Such
-- joints also built many times (the organic towns grew through them), so the rule is not on by default: the
-- driver replans a refused increment with it (ot_driver.refused) before halving. ot_core.jointIssues re-checks
-- the planned result.
-- Late street hierarchy (2026-10-12): main / medium pieces may reach at most this many (fine) blocks beyond the
-- town's front of junctions (FRONT_Q), so wide arterials don't run 300-600 m into the fields ahead of the houses.
M.WIDE_REACH = 1.25
M.WIDE_REACH_MEDIUM = 1    -- collectors (medium) this many fine blocks further
M.HUG = 1.5              -- a single-gateway loop may close within this many block lengths of an existing street
-- Shape envelope (SHAPES_BRIEF 2026-10-12): Showcase v4's shape row read as round blobs. The front above is a
-- quantile of the junctions' EFFECTIVE distance, so a round core (whose sides lie far out in the shape's field)
-- widens it and lets pieces fill all round the core. The envelope is the region de <= a level + ENV_REACH x
-- block (M.envelopeCap: sized by the town's street length): it grows with the town but
-- keeps the shape's proportions (linear: ka x as long along the axis, kb x as wide), so new pieces go along the
-- arms / into the fan / toward the second core and never out on the "wrong" sides. Shaped towns only.
M.ENVELOPE = true
-- Arm fronts (same round): a piece in an arm corridor (ot_shape.armAt) may reach at most ARM_REACH blocks beyond
-- the arm's outermost junction (3+ streets), so an arm grows as a ribbon (cross streets close behind its tip)
-- instead of a bare main-street spine kilometres out with sparse combs (the cross / fingers previews: 1.2 km
-- spines). Shaped towns of the organic growers only (see select).
M.ARM_FRONT = true
M.ARM_REACH = 2
M.ENV_AREA = 1.3        -- the envelope holds this x the area of a round town with the same street length
M.ENV_REACH = 0.5       -- ... + this many blocks
M.ENV_MIN_FILL = 0.6    -- an increment the limits leave below this share of its edges is retried with them widened:
M.ENV_RELAX = 8         -- ... at most this many steps of
M.ENV_RETRY = 3         -- ot_core: a planned increment still under-filled is planned again with the envelope x 1.2^2k
M.ENV_RELAX_F = 1.2     -- ... x 1.2 on the envelope and one more block on the arm fronts

-- Deep arms (2026-10-12, Showcase v5: arms read as ladders / fishbones). Inside an arm corridor the cost and the
-- envelope use ot_shape.stripDistance (along the arm + a little across) for the arm's pieces (ot_grow_organic
-- `armPiece`: its spine, back streets and the lanes / ring arcs between them; plans without arm lines: every piece
-- in the corridor), so back streets beside the spine cost about as much as the spine there (STRIP); lanes leaving
-- the strip outward keep the shape's field (else stubs off the outer row: a ladder one row out). Line tips (ARM_TIPS): a plan piece meeting an arm line (ot_grow_organic
-- `armLine`: the spine or a back street) at a junction where the line already arrives makes it a corner, a street
-- passing through a junction of the line makes it a two-street node, and as the game joins only dead ends the line
-- could never grow through there (the U-shaped combs of the previews, ring arcs cutting the back streets); so at an
-- arm line's junction with two or more streets the line's pieces on both sides are chosen with the piece (the tip
-- stays one piece ahead, a dead end), or the piece waits.
-- Arms fill before they extend (2026-10-12, Showcase v6: empty straight arms with cross stubs beside dense cores,
-- an empty grid ladder beyond a metropolis's edge): no piece may reach farther along an arm than the farthest
-- street with houses on that arm (parcels with a building, ot_engine.townBuildings: snapshot edges carry `built`)
-- + ARM_FILL_LEAD blocks (ARM_FILL_LEAD_MILD for mild-reach shapes, ot_shape.reach). An arm without a housed street
-- yet counts from the town's housed radius (ARM_FILL_Q quantile of the housed streets' distances). Graphs without
-- the data (g.hasBuilt nil: tests, the preview) are not limited. Both growers; the lead caps stay.
M.ARM_FILL = true
M.ARM_FILL_LEAD = 2
M.ARM_FILL_LEAD_MILD = 1.25
M.ARM_FILL_Q = 0.8
M.ARM_FILL_MIN_M = 120   -- m: the lead at least this (small-block styles: MED hill's 40 m blocks)
-- One arm at a time (2026-10-13, run 2026-10-13_2240_sqot-dev: "long offshoot roads don't actually get houses on
-- them"): while one arm runs more than ARM_WAIT_M (and the fill rule's own lead + half a block: a long arm, from the
-- head start's longer lead, a motif or a relaxation) of unhoused street beyond its housed stretch (the farthest leads), an arm not yet housed beyond the town's housed radius starts out only ARM_WAIT_F x the lead past it instead of
-- the full lead: a new arm waits until the one before it has houses (houses fill by network distance from the core,
-- docs/findings/towns.md). Towns of 3+ arms only (cross, fingers; a linear town's two arms are its two ends). PLAN
-- `armWait=` counts the waiting arms.
M.ARM_WAIT = true
M.ARM_WAIT_M = 150
M.ARM_WAIT_F = 0.5        -- the waiting arms' lead: this x the normal lead ...
M.ARM_WAIT_LEAD_M = 60   -- ... at least this (m)
M.ARM_STRONG_HOLD = true -- strong-reach arm shapes: no envelope relaxation (see select); Showcase v8
M.ARM_FILL_RELAX = 1.5   -- x block: ... instead the fill limit may give this much (under-filled increments only)
M.ARM_FILL_BACK = 0.5    -- x block: deep arms' back streets and rungs reach at most this beyond the housed stretch
                         -- (Showcase v6: 2-row ladder strips ran 400-900 m past the last house; the spine leads, the
                         -- rows behind it come once the spine has houses)
-- Housed front (Showcase v9 round, 2026-10-12; user on Showcase v8: "Metropolis polycentric ends up with too many
-- empty streets built out before town growth": ~3-4 km of empty arterial grid toward the secondary centre). The arm
-- fill rule above, for every direction: with style.housedLead (blocks, max(len, depth)) no point of a new piece may
-- lie farther than that from the midpoint of a street with houses on it (snapshot edges carry `built`), so at most
-- ~1-2 blocks of unhoused street run ahead of the houses on any front, lattice frames and links to a secondary
-- centre included (they come when the houses reach toward them). An under-filled increment may give HOUSED_RELAX
-- blocks more. Graphs without the data (g.hasBuilt nil: tests, the preview, a fresh core) are not limited.
M.HOUSED = true
M.HOUSED_RELAX = 1        -- x block: the most the relaxation adds (0.5 per step)
M.HOUSED_MIN_M = 120      -- m: the lead at least this
M.STRIP = true
-- Motif pieces (ot_motif_land, M1 2026-10-13; pieces carrying `motif`): free of the envelope / front / wedge / arm limits
-- and the lasso guard (their motif bounds them), the housed front, lead limit and lead depth apply; a motif's main line
-- (`motifLead`) leads MOTIF_LEAD pieces further; `costK` scales their cost (ot_motif_land COST_MAIN / COST_LANE).
M.MOTIF_FREE = true
M.MOTIF_LEAD = 2
-- give-up for waiting motif branches (M4 fix, 2026-10-13): a `motifWait` branch (close, terrace row) whose main line's next
-- piece is refused / left out (excluded, blocked, the planner's or the game's refusal) in WAIT_GIVEUP plans is dropped
-- (ot_core: style._motifGaveUp, MOTIF event=waitGiveUp); the line's tip stays a dead end, so the line may still go on
-- later. A next piece only held by the lead limit / housed front is a plain wait (the houses come) and never counts.
M.WAIT_GIVEUP = 6
M.ARM_TIPS = true
M.ARM_LOOPS = true       -- arm pieces may close blocks beside a bare spine (lasso guard off for them)
M.SPINE_TIPS = true      -- the spine leaves its own tip only with a lane there (no bare spine creeping out a piece per increment)
M.ARM_LANE_TS = true     -- lanes from the spine meet their back street in a T too (else only lanes between rows)

M.RIBBON_MAX = 0.6       -- strongest corridor discount (cost x (1 - 0.6) on a main street)
M.CORRIDOR_W = 0.75      -- corridor half-width, x block length
M.HOTSPOT_W = 1.2        -- hotspot radius, x block length
M.HOT_CLEAR = true       -- §63: hotspots / lobes move off the woods (ot_skeleton.movePoint)
M.LOBE_R = { 300, 700 }  -- m: lobes on style.lobeDirs (roads out of town, the contour) sit this far out (2026-10-13)

local HARMONICS = {
	[1] = { { 1, 1 }, { 2, 0.3 } },     -- one favoured side
	[2] = { { 1, 0.35 }, { 2, 1 } },    -- two opposite lobes
	[3] = { { 2, 0.4 }, { 3, 1 } },     -- three lobes
}

--- The style's resolved irregularity (cached on the style table): { amp, harm = {{k, w, phase}}, wsum,
--- coast, waterDir, ribbon (corridor discount), hotspots = {{x, y}}, pull } or nil when off.
function M.irregularity(style)
	local irr = style.irregular
	if not irr then return nil end
	local c = style._irr
	-- (§63: the hotspots keep off the woods, so a new tree grid redoes them)
	local fo = style.forest
	local fgH = (M.HOT_CLEAR and SK.ON and fo and fo.grid and fo.grid.cover and fo.mode ~= "deep" and not style.deep) and fo.grid or false
	if c ~= nil and c._fg == fgH then return c end
	local seed = style.seed or 1
	c = { amp = G.clamp(irr.sector or 0, 0, 0.6), harm = {}, wsum = 0, coast = 0, pull = irr.pull or 0, hotspots = {},
		_fg = fgH, hotMoved = 0 }
	for i, h in ipairs(HARMONICS[G.clamp(irr.lobes or 1, 1, 3)]) do
		c.harm[i] = { h[1], h[2], rng.unit(seed, "sector", h[1]) * 2 * math.pi }
		c.wsum = c.wsum + h[2]
	end
	if style.waterDir and (irr.coast or 0) > 0 then c.coast, c.waterDir = G.clamp(irr.coast, 0, 1), style.waterDir end
	-- away from industries (ot_industry): the preference leans away from the works near the town (like the coast
	-- lean, opposite sign), so the hotspots and the favoured sectors sit on the other side
	local ind = style.industry
	if ind and ind.away and IND.IRR_K > 0 then
		c.indK, c.awayDir = G.clamp(IND.IRR_K * (ind.awayMag or 0) * (ind.strength or 1), 0, IND.IRR_K), ind.away
	end
	-- the landscape pull (ot_land, §62): the town's big-scale lean (open land pulls; forest, steep ground push; along
	-- the water) next to the seeded sectors; together at most LAND.TOTAL_MAX (both scaled down: the seeded variety
	-- stays). Without a field ampSeed = amp and the preference is exactly the seeded one.
	c.ampSeed, c.ampLand = c.amp, 0
	local land = style.land
	if land and land.lean and (land.k or 0) > 0 then
		local tot = c.amp + land.k
		local f = tot > LAND.TOTAL_MAX and LAND.TOTAL_MAX / tot or 1
		c.land, c.ampSeed, c.ampLand = land, c.amp * f, land.k * f
	end
	c.ribbon = G.clamp((style.ribbon or 0) * (irr.ribbon or 1), 0, M.RIBBON_MAX)
	local scale = math.max(style.block.len, 1)
	local cx, cy = style.centre[1], style.centre[2]
	-- hotspots: the first in the favoured direction, the next ones further out and turned
	local fav, fv = 0, -math.huge
	for k = 0, 35 do
		local a = k / 36 * 2 * math.pi
		local v = M.preference(c, a)
		if v > fv then fav, fv = a, v end
	end
	-- (2026-10-13, round 5, user: "more spread out around the landscape, not just radiating from the centre"): lobes
	-- along the landscape. With style.lobeDirs (the driver: roads leaving town, else the contour / valley axis) the
	-- hotspots sit on those headings first (ribbon development out along the country roads, along the hillside), at
	-- LOBE_R (300-700 m) rather than 3-8 blocks; the rest as before
	local dirs = style.lobeDirs
	for h = 1, irr.hotspots or 0 do
		local a = fav + (h - 1) * 2.4 + (rng.unit(seed, "hot", h, "a") - 0.5) * 0.8
		local r = scale * (3 + 2.5 * (h - 1) + rng.unit(seed, "hot", h, "r"))
		if dirs and #dirs > 0 and h <= #dirs * 2 then
			local k = (h - 1) % #dirs + 1
			local lap = math.floor((h - 1) / #dirs)
			a = dirs[k] + (rng.unit(seed, "lobe", h, "a") - 0.5) * 0.35
			r = M.LOBE_R[1] + (M.LOBE_R[2] - M.LOBE_R[1]) * (0.25 * lap + 0.75 * rng.unit(seed, "lobe", h, "r"))
			r = math.max(r, scale * 3)
		end
		-- (§63, ot_skeleton: a hotspot in or beside dense forest turns / moves in to the nearest clear spot, so the lobe's
		-- streets and their lots stay CLEAR_M off the wood edge; deep forest towns keep theirs; none clear: as it was)
		local hx, hy = cx + r * math.cos(a), cy + r * math.sin(a)
		if fgH then
			local moved
			hx, hy, moved = SK.movePoint(fgH, cx, cy, a, r)
			if moved then c.hotMoved = c.hotMoved + 1 end
		end
		c.hotspots[h] = { hx, hy }
	end
	style._irr = c
	return c
end

--- The seeded angular preference in [-1, 1] at heading a (radians, from the centre): the harmonics, the coast lean,
--- away from industry (without the landscape pull).
function M.seededPreference(c, a)
	local f = 0
	for _, h in ipairs(c.harm) do f = f + h[2] * math.cos(h[1] * a - h[3]) end
	f = c.wsum > 0 and f / c.wsum or 0
	if c.waterDir then f = (1 - c.coast) * f + c.coast * math.cos(a - c.waterDir) end
	if c.awayDir and c.indK > 0 then f = (1 - c.indK) * f + c.indK * math.cos(a - c.awayDir) end
	return f
end

--- Angular preference in [-1, 1] at heading a (radians, from the centre): the seeded one blended with the landscape
--- pull (ot_land) by their weights (ampSeed, ampLand); the seeded one alone without a field.
function M.preference(c, a)
	local f = M.seededPreference(c, a)
	local wl = c.ampLand or 0
	if c.land and wl > 0 then
		local ws = c.ampSeed or c.amp or 0
		f = (ws * f + wl * LAND.at(c.land, a)) / (ws + wl)
	end
	return f
end

--- The cost's reach factor at heading a: 1 + seeded amplitude x seeded preference + lean weight x lean (shaped
--- towns: SH.SECTOR_DAMP / LAND.SHAPE_F), at least 0.3.
function M.reach(c, a, shaped)
	local as = c.ampSeed or c.amp
	if shaped then as = as * SH.SECTOR_DAMP end
	local s = 1 + as * M.seededPreference(c, a)
	if c.land and (c.ampLand or 0) > 0 then
		s = s + c.ampLand * (shaped and LAND.SHAPE_F or 1) * LAND.at(c.land, a)
	end
	return math.max(0.3, s)
end

--- Spatial hash of the plan's main and medium pieces (sample points every ~25 m), cached on the plan. mainOnly
--- (shaped towns): main pieces only; the medium rings of the organic plans run across the arms and their
--- ribbons filled the wedges (shape-row towns read round in game, 2026-10-12).
local function corridorIndex(mp, cell, mainOnly)
	local slot = mainOnly and "_corrMain" or "_corr"
	local idx = mp[slot]
	if idx and idx.cell == cell then return idx end
	idx = { cell = cell, cells = {} }
	local function add(x, y, w)
		local k = math.floor(x / cell) * 65536 + math.floor(y / cell)
		local list = idx.cells[k]
		if list == nil then list = {}; idx.cells[k] = list end
		list[#list + 1] = { x, y, w }
	end
	for _, pc in ipairs(mp.pieces) do
		local w = (pc.class == "main" and 1) or (pc.class == "medium" and not mainOnly and 0.5) or nil
		if w then
			for i = 2, #pc.pts do
				local a, b = pc.pts[i - 1], pc.pts[i]
				local l = G.dist(a[1], a[2], b[1], b[2])
				local n = math.max(1, math.ceil(l / 25))
				for k = 0, n do add(a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n, w) end
			end
		end
	end
	mp[slot] = idx
	return idx
end

--- Corridor weight at (x, y): max over nearby main (1) / medium (0.5) samples of w x exp(-(d / cell)^2).
local function corridor(idx, x, y)
	local cell = idx.cell
	local i0, j0 = math.floor(x / cell), math.floor(y / cell)
	local best = 0
	for di = -1, 1 do
		for dj = -1, 1 do
			local list = idx.cells[(i0 + di) * 65536 + (j0 + dj)]
			if list then
				for _, s in ipairs(list) do
					local d2 = ((s[1] - x) ^ 2 + (s[2] - y) ^ 2) / (cell * cell)
					if d2 < 4 then
						local v = s[3] * exp(-d2)
						if v > best then best = v end
					end
				end
			end
		end
	end
	return best
end

--- Area (m2) of the region where the shape's effective distance is at most `level` (grid count, 56 x 56 over a
--- box the region fits in).
local function envelopeArea(shape, level, terrain)
	local reach = level * 3
	local n = 56
	local step = 2 * reach / n
	local cx, cy = shape.centre[1], shape.centre[2]
	local count = 0
	for i = 0, n - 1 do
		local x = cx - reach + (i + 0.5) * step
		for j = 0, n - 1 do
			if SH.distance(shape, x, cy - reach + (j + 0.5) * step, terrain) <= level then count = count + 1 end
		end
	end
	return count * step * step
end

--- The shape envelope's level (ot_shape effective distance) for graph g: the level whose region has ENV_AREA x the
--- area of a round town with the same street length (area = length x block / 2, the street density of a block
--- grid), + ENV_REACH blocks. So the shape spreads the town's area along its arms / into its fan instead of round,
--- and a long spur (little length) can't stretch it (a quantile of the node distances did: 2 km spines with
--- sparse combs in the cross / fingers previews). The level per metre of equivalent radius is measured once per
--- town (shape._envK; the shapes scale with the level, fingers' core and the twin's distance roughly). nil for
--- unshaped towns or an empty graph.
function M.envelopeCap(g, style, terrain)
	local shape = style.shape
	if shape == nil or shape.id == "compact" or #g.edges == 0 then return nil end
	local L = 0
	for _, e in ipairs(g.edges) do L = L + OG.edgeLength(g, e) end
	local blk = math.max(style.block.len, style.block.depth)
	local req = math.sqrt(L * blk / (2 * math.pi))
	if shape._envK == nil then
		local a = envelopeArea(shape, req, terrain)
		shape._envK = a > 0 and math.sqrt(math.pi * req * req / a) or 1
	end
	local g = SH.GEOM[shape.id]
	return shape._envK * math.sqrt(M.ENV_AREA * (g and g.env or 1)) * req + M.ENV_REACH * blk
end

--- Per arm of a shaped town: the farthest a new piece may reach along it (m): its outermost junction (3+
--- streets; any node when the arm has no junction yet; else the town's own radius) + ARM_REACH blocks (+ extra m).
--- nil for shapes without arms.
function M.armFronts(g, style, extra)
	local shape = style.shape
	if shape == nil or #g.edges == 0 or SH.armAt(shape, shape.centre[1], shape.centre[2]) == nil and
		not SH.ARMED[shape.id] then return nil end
	local arms = shape.arms or { shape.axis }
	local jf, nf = {}, {}
	local rTown = 0
	for i = 1, #arms do jf[i], nf[i] = 0, 0 end
	for _, n in ipairs(g.nodes) do
		local dg = OG.degree(g, n.id)
		if dg > 0 then
			local r = G.dist(shape.centre[1], shape.centre[2], n.x, n.y)
			if dg >= 3 and r > rTown then rTown = r end
			local i, along = SH.armAt(shape, n.x, n.y)
			if i then
				if dg >= 3 and along > jf[i] then jf[i] = along end
				if along > nf[i] then nf[i] = along end
			end
		end
	end
	-- (mild-reach shapes, ot_shape.reach: one block instead of ARM_REACH)
	local reach = ((shape.reach or 1) >= 1 and M.ARM_REACH or 1) * math.max(style.block.len, style.block.depth) + (extra or 0)
	local out = {}
	for i = 1, #arms do
		local f = jf[i] > 0 and jf[i] or (nf[i] > 0 and nf[i] or rTown)
		-- (§63 skeleton: an arm into open land leads further, shape.armK)
		out[i] = f + reach * (SH.armSkel(shape, i))
	end
	return out
end

--- Per arm of a shaped town: the farthest a new piece may reach along it under the fill rule (M.ARM_FILL): the
--- farthest housed street on the arm (edge midpoint, distance along the arm) + the lead; arms with none count from
--- the town's housed radius. Returns { [arm] = m }, { [arm] = housed along or false } or nil (no arms, no data).
function M.armBuiltFronts(g, style, leadM, lim)
	local shape = style.shape
	if not M.ARM_FILL or shape == nil or not g.hasBuilt or #g.edges == 0 then return nil end
	if not SH.ARMED[shape.id] then return nil end
	local arms = shape.arms or { shape.axis }
	local blk = math.max(style.block.len, style.block.depth)
	local bf, rs, sf = {}, {}, {}
	-- (§69 steer towns, lim.armCont: the housed along values per arm, for the continuous front below)
	local cont = lim ~= nil and lim.armCont ~= nil
	local hl = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			local i, along = SH.armAt(shape, mx, my)
			-- (town streets only: a country road out of town or a lane is no arm street; it never gets houses)
			local town = e.template == nil or tostring(e.template):find("/town/", 1, true) ~= nil
			if i and town and along > (sf[i] or 0) then sf[i] = along end
			if (e.built or 0) > 0 then
				rs[#rs + 1] = G.dist(shape.centre[1], shape.centre[2], mx, my)
				if i and along > (bf[i] or 0) then bf[i] = along end
				if cont and i and (e.built or 0) >= math.max(1, tonumber(lim.housedMin) or 1) then
					hl[i] = hl[i] or {}
					local l = hl[i]
					l[#l + 1] = along
				end
			end
		end
	end
	if #rs == 0 then return nil end   -- no housed street at all: no data to go by (a fresh core, a parcel-less read)
	table.sort(rs)
	local rq = rs[math.max(1, math.floor(#rs * M.ARM_FILL_Q + 0.5))] or 0
	local lead = math.max(((shape.reach or 1) >= 1 and M.ARM_FILL_LEAD or M.ARM_FILL_LEAD_MILD) * blk, M.ARM_FILL_MIN_M)
	-- (the head start: its own lead, ot_driver HEAD_LEAD_M, so the first arms reach out with houses-ready frontage)
	if leadM then lead = math.max(lead, leadM) end
	-- (§69 steer towns: an arm's housed front runs on only across gaps of at most lim.armCont m from the town's housed
	-- radius: a far house (a bridge end's dose, a lone farm) no longer lets the arm run out to it bare)
	local trimmed = 0
	if cont then
		for i = 1, #arms do
			if bf[i] ~= nil then
				local f = LP.contFront(hl[i] or {}, rq, lim.armCont)
				if f < bf[i] - 1e-6 then
					trimmed = trimmed + 1
					bf[i] = f > 0 and f or nil
				end
			end
		end
	end
	local out, housed, behind = {}, {}, {}
	-- (one arm at a time: the arm running farthest ahead without houses, when more than ARM_WAIT_M, leads; arms not yet
	-- out of the housed radius start only ARM_WAIT_F x the lead past it until it has houses)
	-- (a long arm: beyond what the fill rule's own lead lets an arm run, i.e. laid by the head start's longer lead, a
	-- motif or a relaxation)
	local leader, lrun = nil, math.max(M.ARM_WAIT_M, lead + 0.5 * blk)
	-- (only for towns of 3+ arms, cross / fingers: a linear / ridge / shore town's two arms are its two ends and grow
	-- together)
	if M.ARM_WAIT and #arms >= 3 then
		for i = 1, #arms do
			local run = (sf[i] or 0) - math.max(bf[i] or 0, rq)
			if run > lrun then leader, lrun = i, run end
		end
	end
	local waiting = 0
	for i = 1, #arms do
		housed[i] = bf[i] or false
		local ld = lead
		if leader ~= nil and i ~= leader and (bf[i] or 0) <= rq + M.ARM_WAIT_M then
			ld = math.max(M.ARM_WAIT_LEAD_M, M.ARM_WAIT_F * lead)
			waiting = waiting + 1
		end
		-- (§63 skeleton: an arm into open land leads further, shape.armK; a waiting arm still waits)
		if ld == lead then ld = ld * (SH.armSkel(shape, i)) end
		-- (§69 steer towns: never more than the steer lead beyond the housed front, whatever the skeleton's reach)
		if lim ~= nil and lim.leadCap ~= nil then ld = math.min(ld, lim.leadCap) end
		out[i] = math.max(bf[i] or 0, rq) + ld
		-- back streets and the lanes between the rows of a deep arm (not its spine): only beside the housed stretch
		behind[i] = math.max(bf[i] or 0, rq) + M.ARM_FILL_BACK * blk
	end
	out.waiting, out.leader, out.rq, out.lead, out.trimmed = waiting, leader, rq, lead, trimmed
	return out, housed, behind
end

--- Per arm: how far the streets run beyond the farthest housed street along it (m; the v6 diagnosis number):
--- { [arm] = { street = farthest street midpoint along, housed = farthest housed one (0: none) } } or nil.
function M.armGaps(g, style)
	local shape = style.shape
	if shape == nil or not g.hasBuilt then return nil end
	if not SH.ARMED[shape.id] then return nil end
	local out = {}
	for i = 1, #(shape.arms or { shape.axis }) do out[i] = { street = 0, housed = 0 } end
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local i, along = SH.armAt(shape, (a.x + b.x) / 2, (a.y + b.y) / 2)
			if i then
				if along > out[i].street then out[i].street = along end
				if (e.built or 0) > 0 and along > out[i].housed then out[i].housed = along end
			end
		end
	end
	return out
end

--- Housed-front index (M.HOUSED): { lead = m, cell, buckets } of the housed edges' midpoints, or nil (no
--- style.housedLead, no data, nothing housed yet).
function M.housedIndex(g, style)
	local hl = style.housedLead
	if not M.HOUSED or hl == nil or hl <= 0 or not g.hasBuilt or #g.edges == 0 then return nil end
	return M.housedIndexM(g, math.max(hl * math.max(style.block.len, style.block.depth), M.HOUSED_MIN_M))
end

-- Lead limit (2026-10-13, real map run 2026-10-13_0137_sqot-dev: Axbridge's head start laid an ~800 m empty medium
-- street to the map edge; the EU styles have no housed front and a lens has no arm fill rule): no point of a new
-- piece farther than MAX_LEAD_M from the midpoint of a street with houses, in every style (graphs with house data,
-- g.hasBuilt; a hard cap, never relaxed). The head start passes a tighter one (opts.limits.leadM, ot_driver HEAD_LEAD_M).
M.MAX_LEAD_M = 400        -- (550 until 2026-10-13: loops 400-500 m beyond the houses in the real map run)
-- Ring pieces wait for the houses (organic ring geometry, style.ringWobble, 2026-10-14 §56; the showcase run
-- 2026-10-14_2150's EU organic town laid long ring arcs and the ring road far ahead of its houses): an organic ring arc
-- beyond the old wall line (`ringArc`), the ring road motif's pieces and a crescent's arcs only within RING_LEAD_M of a
-- street with houses (all points as the lead limit; never relaxed).
M.RING_LEAD_M = 160
-- Head start steering (opts.limits.headForm): in an armed shape (linear / ridge / cross / fingers / shore) pieces off
-- the arm corridors cost HEAD_OFFARM x more, so the first streets draw the town's form (two long arms, the spokes, the
-- shore strip) instead of filling round the core.
M.HEAD_OFFARM = 2.2

-- §69 look rules for steer towns (opts.limits.steer, ot_driver "steer" lock; run 2026-10-15_1936_sqot-glprobe: Seven
-- Oaks' comb of parallel dead ends on its south side, its east arm zig-zagging into the woods). With most streets
-- locked, the game no longer closes our dead ends, so the planner must:
--   rake    a new spur off an existing node whose far end lies within RAKE_R of RAKE_N or more existing parallel dead-end
--           spurs (within RAKE_DEG, their bases within RAKE_R too) waits (a third tooth of a comb); a piece joining the
--           tips of two parallel spurs (RAKE_JOIN_R apart) closes the block: its cost x RAKE_JOIN_K, free of the lead,
--           lasso and empty-loop holds (it adds no reach). Relaxed when the increment would be empty.
--   wiggle  a main / medium piece (or an arm line's) extending an existing dead end may turn at most TURN_MAX off the
--           street it continues, and not back against the last corner of that street within WIGGLE_BACK_M when both
--           turns sum over WIGGLE_DEG (the zig-zag rule above only sees corners at two-street nodes one edge back; a
--           piece split into several edges (maxSeg) or a spine with lanes at every node hid the chain). Relaxed when
--           the increment would be empty.
M.RAKE = true
M.RAKE_R = 1.6            -- x block length
M.RAKE_JOIN_R = 2.4       -- x block length
M.RAKE_DEG = 25
M.RAKE_N = 2
M.RAKE_JOIN_K = 0.3
M.RAKE_SPUR_M = 260       -- m: a dead-end spur at most this long back to its junction
M.RAKE_WALK = 6           -- edges walked back at most
M.RAKE_SCAN = 600         -- dead ends read at most
M.WIGGLE = true
M.TURN_MAX = 40           -- deg
M.WIGGLE_DEG = 55         -- deg
M.WIGGLE_MIN = 10         -- deg: smaller turns are no corner
M.WIGGLE_BACK_M = 260     -- m walked back along the street
M.WIGGLE_WALK = 6         -- edges at most
-- knots (§70, 2026-10-15; run 2026-10-15_2031_sqot: Merehythe's south, curved locked streets crossing away from a junction,
-- looping back across a neighbour, running a few metres beside each other): steer towns' pieces must not cross a street
-- other than at a shared node, run alongside one for long, or close a loop smaller than half a block (ot_knot, on the
-- curves; the chord / middle-point tests of classifyPiece and ot_plan missed them). Cross / loop relaxed when the
-- increment would be empty; motif, ring and connector pieces exempt. §75 (2026-10-19): the parallel run is measured on
-- the whole street through the piece (ot_knot.chainBehind, only a junction end's approach left out), applies to
-- connectors too and never gives way.
M.KNOT = true
-- side streets (§75, 2026-10-19; user shots: a side street leaving a curving street at ~20-30 deg and running back beside
-- it): a steer town's piece meeting a junction (3+ streets with it) leaves at least ot_check LIMITS.sideAngle (60 deg)
-- off every street there, a fork's two arms excepted (ot_check.sideBad); the planner refuses the rest of a steer town's
-- plan the same way (ot_core passes sideAngle). Never relaxed. Organic growers only (SIDE_GRID); the climbing motifs
-- exempt (SIDE_FREE: their streets follow the slope and branch where the shelf is).
M.SIDE = true
M.SIDE_FREE = { switchbacks = true, hill_climb = true }
M.SIDE_GRID = false      -- grid growers exempt: their lattice meets at right angles by design; the acute joins are
                         -- where it meets the old core's stubs, and holding those cost NA grid / JP dense 14-26 % of
                         -- their growth offline (the shots were organic towns'), as M.HOOK_GRID
-- one empty row at a time (§75 follow-up, 2026-10-19; ot_knot ROW): a steer organic town's piece leaving a new dead end
-- waits while it runs beside one of the mod's own streets that has no house yet (or a piece chosen in this increment)
-- within ~1.2 block depths: knot reason `row`, never relaxed (as parallel). See the knot section in M.select.
M.ROW = true
-- hooks (§71, 2026-10-16; run 2026-10-16_0405_sqot: small curled "P" dead ends in Merehythe and Shaw): a steer town's
-- chosen piece that leaves a new dead end must not make that dead-end street curl round (ot_knot.hook: its chain back
-- to the junction turns over HOOK_DEG, or its end comes back within a block depth of its own street). Tested once the
-- increment is chosen (a U closing a block within it is fine), the select run again without the pruned pieces; kept
-- when pruning would empty the increment. Connector and ring pieces and the climbing motifs exempt. PLAN hookHeld=.
M.HOOK = true
M.HOOK_GRID = false      -- grid growers (NA grid, strict grids) exempt

-- Sparse streets (2026-10-14 §57; showcase run 2026-10-14_2237: the roundabout town's long empty snaking roads, Shape
-- cross's empty combs and EU organic's long thin dead-end fingers: each forced increment ran on from a street with one
-- or two houses, so the housed front and the lead limit (distances from any street with a house) moved out with them).
-- In a town with much unhoused street (SPARSE_EMPTY_M and SPARSE_SHARE of its length), no new piece may start, end or
-- run where the streets within SPARSE_R carry fewer than SPARSE_DENS houses per 100 m (at least SPARSE_MIN_LEN m of
-- street there): the houses come first. Motif pieces too; relaxed only when it would leave the increment
-- almost empty (SPARSE_RELAX_EDGES, §59: then a few held pieces come, the cheapest first). Only with
-- opts.sparse / opts.limits.sparse: the driver's forced increments (the showcase, dev tools: no demand waits for the houses there; a
-- demand-driven increment has the own empty budget, ot_core OWN_EMPTY_*).
M.SPARSE = true
M.SPARSE_R = 150
M.SPARSE_MIN_LEN = 300
M.SPARSE_DENS = 1.5
M.SPARSE_EMPTY_M = 1200
M.SPARSE_SHARE = 0.1
M.SPARSE_TOWN_DENS = 3      -- ... in a town whose streets carry this many houses per 100 m on the whole (a town still
                            -- without houses, or a test's bare graph, is not held)
M.SPARSE_RELAX_EDGES = 4   -- (§59) an increment the hold would leave with fewer edges than this takes held pieces up to it

--- The sparse-street index of g (M.SPARSE): { cell, buckets = { [k] = { { x, y, len, built } } } } or nil (no house data,
--- or too little unhoused street to matter).
function M.sparseIndex(g)
	if not M.SPARSE or not g.hasBuilt or #g.edges == 0 then return nil end
	local L, E = 0, 0
	local cell = M.SPARSE_R
	local idx = { cell = cell, buckets = {} }
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local l = G.dist(a.x, a.y, b.x, b.y)
			L = L + l
			if (e.built or 0) <= 0 then E = E + l end
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			local k = math.floor(mx / cell) .. ":" .. math.floor(my / cell)
			local bk = idx.buckets[k]
			if bk == nil then bk = {}; idx.buckets[k] = bk end
			bk[#bk + 1] = { mx, my, l, e.built or 0 }
		end
	end
	if E < M.SPARSE_EMPTY_M or E < M.SPARSE_SHARE * L then return nil end
	local B = 0
	for _, bk in pairs(idx.buckets) do for _, m in ipairs(bk) do B = B + m[4] end end
	if 100 * B / math.max(1, L) < M.SPARSE_TOWN_DENS then return nil end
	idx.empty, idx.length = E, L
	return idx
end

--- Is (x, y) among sparse streets (see M.SPARSE)? Returns bool, the houses per 100 m there.
function M.sparseAt(idx, x, y)
	local cell, R = idx.cell, M.SPARSE_R
	local cx, cy = math.floor(x / cell), math.floor(y / cell)
	local len, built = 0, 0
	for i = cx - 1, cx + 1 do
		for j = cy - 1, cy + 1 do
			local bk = idx.buckets[i .. ":" .. j]
			if bk then
				for _, m in ipairs(bk) do
					if G.dist(m[1], m[2], x, y) <= R then len, built = len + m[3], built + m[4] end
				end
			end
		end
	end
	if len < M.SPARSE_MIN_LEN then return false, nil end
	local dens = 100 * built / len
	return dens < M.SPARSE_DENS, dens
end

--- Where a piece comes from, for the PLAN `origins=` line (2026-10-14 §57: the empty roads of the 2347 run could not be
--- told apart from the log): "m:<motif>", "arm", "ring", "crescent", "link", "lattice" or "plain".
function M.origin(pc)
	if pc.motif then return "m:" .. tostring(pc.motif) end
	if pc.armPiece or pc.armLine or pc.armSpoke then return "arm" end
	if pc.ringArc then return "ring" end
	if pc.crescent then return "crescent" end
	if pc.connector then return "link" end
	if pc.lattice then return "lattice" end
	return "plain"
end

--- A housed-midpoint index with a lead of `lead` m (see M.housedIndex), or nil without house data.
function M.housedIndexM(g, lead, minB)
	if not g.hasBuilt or #g.edges == 0 or lead == nil then return nil end
	local cell = lead
	local idx = { lead = lead, cell = cell, buckets = {}, n = 0 }
	-- (§69 steer towns, minB: a street counts as housed with this many buildings; one house is no front)
	local mb = math.max(1, tonumber(minB) or 1)
	for _, e in ipairs(g.edges) do
		if (e.built or 0) >= mb then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
				local k = math.floor(mx / cell) .. ":" .. math.floor(my / cell)
				local bk = idx.buckets[k]
				if bk == nil then bk = {}; idx.buckets[k] = bk end
				bk[#bk + 1] = { mx, my }
				idx.n = idx.n + 1
			end
		end
	end
	if idx.n == 0 then return nil end
	return idx
end

--- Distance from (x, y) to the nearest housed midpoint of idx, capped at 2 x idx.cell (farther: math.huge).
function M.housedDist(idx, x, y)
	local cell = idx.cell
	local cx, cy = math.floor(x / cell), math.floor(y / cell)
	local best = math.huge
	for dx = -2, 2 do
		for dy = -2, 2 do
			local bk = idx.buckets[(cx + dx) .. ":" .. (cy + dy)]
			if bk then
				for _, p in ipairs(bk) do
					local d = G.dist(x, y, p[1], p[2])
					if d < best then best = d end
				end
			end
		end
	end
	return best
end

--- "gap/street" per arm, e.g. "420/880,0/300" (m), or "-".
function M.armGapText(gaps)
	if gaps == nil then return "-" end
	local parts = {}
	for i, x in ipairs(gaps) do parts[i] = string.format("%.0f/%.0f", math.max(0, x.street - x.housed), x.street) end
	return table.concat(parts, ",")
end

--- Cost of a frontier piece (lower first), without the loop-closing bonus. mp: the master plan (corridors).
local function cost(pc, style, opts, incSeed, mp, entry)
	local mx, my = G.polyAt(pc.pts, 0.5)
	local scale = math.max(style.block.len, 1)
	local cx, cy = style.centre[1], style.centre[2]
	-- town shape (ot_shape): its effective distance replaces the distance from the centre; the seeded sector
	-- preference is damped and the hotspots are left out (the shape decides the outline), ribbons stay
	local shape = style.shape
	-- (motif pieces, M1: the plain distance; the motif runs across the shape where its land leads, e.g. a climb up the
	-- slope of a town drawn along the contour)
	local shaped = shape ~= nil and shape.id ~= "compact" and not (pc.motif and M.MOTIF_FREE)
	local d = shaped and SH.distance(shape, mx, my, opts.terrain) or G.dist(cx, cy, mx, my)
	if shaped and M.STRIP and (pc.armPiece or entry or not (mp and mp.hasArmLines)) then
		local ds = SH.stripDistance(shape, mx, my, opts.terrain)
		if ds and ds < d then d = ds end
	end
	local irr = M.irregularity(style)
	local c
	if irr then
		local s = M.reach(irr, G.atan2(my - cy, mx - cx), shaped)
		c = d / (scale * s) + 0.5
		if irr.ribbon > 0 and mp then
			-- (deep arms: the whole strip shares its spine's ribbon, so back streets keep up with it)
			local w = (pc.armPiece and mp.hasArmLines and M.STRIP) and 1
				or corridor(corridorIndex(mp, scale * M.CORRIDOR_W, shaped), mx, my)
			c = c * (1 - irr.ribbon * w)
		end
		if not shaped then
			for _, h in ipairs(irr.hotspots) do
				local dh = G.dist(h[1], h[2], mx, my) / (scale * M.HOTSPOT_W)
				c = c * (1 - irr.pull * exp(-dh * dh))
			end
		end
	else
		c = d / scale + 0.5
		local ribbon = style.ribbon or 0
		if pc.armPiece and mp and mp.hasArmLines and M.STRIP then c = c * (1 - 0.5 * ribbon)
		elseif pc.class == "main" then c = c * (1 - 0.5 * ribbon)
		elseif pc.class == "medium" then c = c * (1 - 0.25 * ribbon) end
	end
	local sd = stationDist(style, mx, my)
	if sd then c = c * (1 - (style.stationPull or 0) * 0.5 * exp(-(sd / 150) ^ 2)) end
	local terrain = opts.terrain
	if terrain then
		local a, b = pc.pts[1], pc.pts[#pc.pts]
		local gr = T.grade(terrain, a[1], a[2], b[1], b[2])
		c = c + gr / math.max(style.maxSlope, 0.01) * 0.5
		if style.waterfront and style.waterFrontAxis then
			local h = G.heading(a[1], a[2], b[1], b[2])
			if G.lineAngleDiff(h, style.waterFrontAxis) < math.rad(15) then
				local cl = T.clearance(terrain, mx, my, style.waterSetback * 3, style.waterSetback / 2)
				if cl then c = c * 0.7 end
			end
		end
	end
	-- waterfront premium (shore towns and new coast / lake towns, style.waterPremium = { gain, band, shore }): streets
	-- near the water come first, like the real estate (cost x (1 - gain x exp(-(d / band)^2)), d = distance to the
	-- traced shoreline); the waterfront street itself (ot_shore) is a main street on top
	local wp = style.waterPremium
	if wp and wp.shore then
		local _, perp, wet = SH.shoreAt(wp.shore, mx, my)
		if not wet then c = c * (1 - wp.gain * exp(-(perp / wp.band) ^ 2)) end
	end
	-- away from industries (ot_industry, a preference, never a ban): pieces near a works cost more, heavier works more
	-- and farther (style.industry: set per plan by the driver; nil = no industries near the town, cost unchanged)
	local ind = style.industry
	-- (a motif's pieces built next to a works on purpose, M3 workers' terraces: `indFree`)
	if ind and not pc.indFree then c = c * (1 + IND.COST_K * IND.pen(ind, mx, my)) end
	-- forest-hugging towns (ot_forest, phase F): pieces in dense forest cost more, open pieces along the forest edge less
	-- (style.forest: set per plan by the driver; nil or mode clear / none = cost unchanged)
	local fo = style.forest
	-- (deep forest towns, 2026-10-14: the same with their stronger values, ot_forest.k)
	if FO.active(fo) then c = c * (FO.costFactor(fo, pc.pts, M.corridorOf(fo, pc)))
	-- (clear-mode towns, §63: a light extra cost on wooded pieces, scaled by the town's hug odds)
	elseif fo and fo.mode == "clear" and fo.grid then c = c * FO.clearFactor(fo, pc.pts, M.corridorOf(fo, pc)) end
	-- lattice styles: the arterial frame first (the cells read as superblocks early, the interior fills later)
	local lat = mp and mp.anchored and style.lattice
	if lat and (pc.class == "main" or pc.class == "medium") then c = c * (lat.discount or 0.5) end
	-- head start (opts.limits.headForm): the first streets go along the form's arms
	local lim = opts.limits
	if lim and lim.headForm and shaped and SH.ARMED[shape.id] and not SH.inArm(shape, mx, my) then c = c * M.HEAD_OFFARM end
	-- motif pieces (ot_motif_land, M1): the motif's streets come first (its main line cheapest)
	if pc.costK then c = c * pc.costK end
	c = c * (1 + 0.15 * (rng.unit(incSeed, pc.key) - 0.5))
	return c
end

--- A piece's forest corridor (ot_forest.corridor, R1), cached on the piece for its grid.
function M.corridorOf(fo, pc)
	if fo == nil or fo.grid == nil then return nil end
	local c = pc._foCo
	if c == nil or c.grid ~= fo.grid then
		c = FO.corridor(fo, pc.pts)
		c.grid = fo.grid
		pc._foCo = c
	end
	return c
end

--- Drops dangling small streets from a selection (in place): a chosen "small" piece (not a planned
--- cul-de-sac or a connector) with an end junction that no other chosen piece and no existing node uses.
--- Repeats until stable. Stubs of main/medium streets stay: the town grows on along them. Returns the count.
M.ITER_PER_EDGE = 4   -- the greedy loop's cap: maxEdges x this + ITER_BASE rounds (report.iterCap when it is hit)
M.ITER_BASE = 64

function M.prune(chosen, jnode)
	local count = {}
	for _, pc in ipairs(chosen) do
		count[pc.a] = (count[pc.a] or 0) + 1
		count[pc.b] = (count[pc.b] or 0) + 1
	end
	local removed = 0
	local changed = true
	local passes = #chosen + 1   -- (every pass but the last removes a piece)
	while changed and passes > 0 do
		passes = passes - 1
		changed = false
		for i = #chosen, 1, -1 do
			local pc = chosen[i]
			if pc.class == "small" and not pc.culDeSac and not pc.connector then
				local dangling = (count[pc.a] == 1 and not jnode[pc.a]) or (count[pc.b] == 1 and not jnode[pc.b])
				if dangling then
					table.remove(chosen, i)
					count[pc.a] = count[pc.a] - 1
					count[pc.b] = count[pc.b] - 1
					removed = removed + 1
					changed = true
				end
			end
		end
	end
	return removed
end

--- Selects the next streets. opts = { terrain, maxEdges = 24, maxSeg = 100, minLen = 10, snapR = 8, builtTol = 6,
--- joinR (engine-town connectors, default 0.75 x block.len), incSeed (per-increment seed),
--- exclude = { [piece key] = true } (pieces the planner refused in an earlier round),
--- cache = {} (junction matches and classifications shared by the rounds of one increment; the graph and
--- the plan must not change in between), join = ot_plan join mode (pieces ending at nodes the planner may not
--- join are excluded as "nojoin"; nil = no check), prune = drop dangling small streets (M.prune; default: grid
--- styles only, organic towns grow on through their lanes), armTips = false (deep arms' line tips off), why = {}
--- (debugging: filled with the last reason each open piece waited) }.
--- Only pieces next to the reached network are classified. Returns streets (for ot_plan.plan) and a report
--- { built, blocked, excluded (of the classified pieces), reached, selected, connectors, tips (pieces chosen by the
--- line tips rule), info }.
function M.select(g, mp, style, opts)
	opts = opts or {}
	local maxEdges = opts.maxEdges or 24
	local maxSeg = opts.maxSeg or 100
	local snapR = opts.snapR or 8
	local incSeed = opts.incSeed or rng.hash(style.seed or 1, #g.edges)
	local exclude = opts.exclude or {}
	local cache = opts.cache or {}
	cache.info = cache.info or {}
	local info = cache.info
	local occR = occRadius(style, opts)

	if cache.jnode == nil then
		cache.jnode, cache.jkeys, cache.nodeUsed = M.matchJunctions(g, mp, snapR)
	end
	local adj = adjacency(mp)
	local jkeys, nodeUsed = cache.jkeys, cache.nodeUsed
	local jnode = setmetatable({}, { __index = cache.jnode })   -- connector junctions are added per call
	local extraAdj = {}
	local report = { built = 0, blocked = 0, excluded = 0, reached = 0, selected = 0, connectors = 0, adopted = 0 }
	local adopted = {}

	local join = opts.join
	local reached = {}   -- junction keys reached (filled below)
	local function getInfo(pc)
		local st = info[pc.key]
		if st == nil then
			st = classifyPiece(g, pc, style, opts, jnode, occR)
			if join and not st.built and not st.blocked and not st.excluded then
				-- a new street may only end at existing nodes the planner can join (ot_plan.joinable)
				for _, k in ipairs({ pc.a, pc.b }) do
					local nid = jnode[k]
					if nid and not P.joinable(g, g.nodeById[nid], join) then st.excluded = "nojoin" end
				end
			end
			if st.excluded == "edge" then report.edgeHeld = (report.edgeHeld or 0) + 1 end
			if not st.built and not st.blocked and not st.excluded then
				st.need = P.edgeCount(pc, maxSeg, opts.minLen)
				-- (deep arms: other pieces in an arm's corridor cost as the strip does too, unless they leave a
				-- junction of the arm's lines the town reached (lanes off the outer row: stubs out of the strip):
				-- else an arm whose base the town reaches only through infill never started, the other arms'
				-- cheap strips outbidding its way in)
				local aj = mp.armJunction
				local entry = aj ~= nil and not pc.armPiece and not ((aj[pc.a] and reached[pc.a]) or (aj[pc.b] and reached[pc.b]))
				st.cost = cost(pc, style, opts, incSeed, mp, entry)
			end
			info[pc.key] = st
		end
		return st
	end

	-- engine streets that miss the plan: connect each dead end to the nearest free junction within joinR. A
	-- connector leaves the dead end at most CONN_TURN off its street's direction and is at least CONN_MIN long
	-- (the showcase v3 refusals: short connectors turning sharply at the dead end, ot_check.footprint); among the
	-- candidates the one with the least turn-weighted distance wins
	if #g.edges > 0 then
		local joinR = opts.joinR or style.block.len * 0.75
		if opts.connRelax then joinR = math.max(joinR * M.CONN_RELAX_R, M.CONN_RELAX_MIN) end
		local connTurn = opts.connRelax and M.CONN_RELAX_TURN or M.CONN_TURN
		for _, nid in ipairs(OG.deadEnds(g)) do
			if not nodeUsed[nid] and not (join and not P.joinable(g, g.nodeById[nid], join)) then
				local n = g.nodeById[nid]
				local out = nil   -- the dead end's direction (continuing its street outward)
				local de = g.edgeById[g.adj[nid][1]]
				if de then out = G.wrap(OG.headingFrom(g, de, nid) + math.pi) end
				local best, bd, bscore = nil, joinR, math.huge
				for _, k in ipairs(jkeys) do
					local j = mp.junctions[k]
					if not jnode[k] and math.abs(j[1] - n.x) < joinR and math.abs(j[2] - n.y) < joinR then
						local d = G.dist(n.x, n.y, j[1], j[2])
						if d < joinR and d > snapR then
							local turn = out and G.angleDiff(out, G.heading(n.x, n.y, j[1], j[2])) or 0
							-- (connRelax "force": no near misses, a straight connector to a junction further on instead)
							local nearMiss = d <= 2 * snapR and opts.connRelax ~= "force"
							if (nearMiss or not M.CONN_RULES or (d >= M.CONN_MIN and turn <= connTurn))
								and not OG.crossing(g, n.x, n.y, j[1], j[2], { [nid] = true }) then
								-- a near miss always wins (the dead end stands in for that junction)
								local score = nearMiss and (d - 1e6) or (M.CONN_RULES and d * (1 + turn / connTurn) or d)
								if score < bscore then best, bd, bscore = k, d, score end
							end
						end
					end
				end
				if best and bd <= 2 * snapR then
					-- a near miss (engine dead ends rarely sit exactly on the plan): the dead end stands in for
					-- that junction, so plan streets start at it instead of next to it
					jnode[best] = nid
					adopted[#adopted + 1] = best
					report.adopted = report.adopted + 1
				elseif best then
					local dk = "D" .. nid
					jnode[dk] = nid
					local j = mp.junctions[best]
					local pc = { key = "conn:" .. nid, a = dk, b = best, pts = { { n.x, n.y }, { j[1], j[2] } },
						class = "small", connector = true }
					extraAdj[dk] = { pc }
					extraAdj[best] = extraAdj[best] or {}
					local eb = extraAdj[best]
					eb[#eb + 1] = pc
					report.connectors = report.connectors + 1
				end
			end
		end
	end

	-- frontier: pieces touching a reached junction, grown as junctions get reached; `pending` pieces are
	-- classified before the next pick and the eligible ones (not built / blocked / excluded) move to `open`
	local seen, pending, open = {}, {}, {}
	local depth = {}
	local function reach(k, d)
		d = d or 0
		if depth[k] == nil or d < depth[k] then depth[k] = d end
		if reached[k] then return end
		reached[k] = true
		for _, list in ipairs({ adj[k] or {}, extraAdj[k] or {} }) do
			for _, pc in ipairs(list) do
				if not seen[pc.key] then seen[pc.key] = true; pending[#pending + 1] = pc end
			end
		end
	end
	for _, k in ipairs(jkeys) do
		if cache.jnode[k] and OG.degree(g, cache.jnode[k]) >= 1 then reach(k); report.reached = report.reached + 1 end
	end
	local dkeys = {}
	for k in pairs(extraAdj) do if k:sub(1, 1) == "D" then dkeys[#dkeys + 1] = k end end
	table.sort(dkeys)
	for _, k in ipairs(dkeys) do reach(k) end
	for _, k in ipairs(adopted) do reach(k) end
	if #g.edges == 0 then
		-- an empty town starts at the junction nearest the plan centre
		local best, bd = nil, math.huge
		for _, k in ipairs(jkeys) do
			local j = mp.junctions[k]
			local d = G.dist(style.centre[1], style.centre[2], j[1], j[2])
			if d < bd then best, bd = k, d end
		end
		if best then reach(best) end
	end

	-- look rules: zig-zag corners and lassos (see M.ZIGZAG_DEG)
	local zzOn = opts.zigzag
	if zzOn == nil then zzOn = M.ZIGZAG end
	local guardOn = opts.loopGuard
	if guardOn == nil then guardOn = M.LOOP_GUARD end
	guardOn = guardOn and #g.edges > 0
	local stru = nil
	if guardOn then
		stru = cache.structure or OG.structure(g)
		cache.structure = stru
		if stru.core == nil then guardOn = false end
	end
	local uf, anchors = {}, {}
	local function find(k)
		while uf[k] ~= k do k = uf[k] end
		return k
	end
	local function ensure(k, inherit)
		if uf[k] ~= nil then return find(k) end
		local nid = jnode[k]
		if nid and stru then
			local r = "gw" .. tostring(stru.gateway[nid] or nid)
			if uf[r] == nil then uf[r], anchors[r] = r, 1 end
			uf[k] = r
			return r
		end
		if inherit == nil then
			uf[k], anchors[k] = k, 1
			return k
		end
		uf[k] = inherit
		return find(inherit)
	end
	local function union(ra, rb)
		if ra == rb then return end
		uf[ra] = rb
		anchors[rb] = (anchors[rb] or 1) + (anchors[ra] or 1)
	end
	-- may pc close a loop here? Both ends rooted in one part with a single gateway: only when the loop hugs the
	-- town (the closing piece within HUG x block of an existing street: a block beside the town, which can only be
	-- joined at its dead ends), never out on a stem (a lasso)
	local hugR = M.HUG * math.max(style.block.len, style.block.depth)
	local function notBridge(e) return not (stru and stru.bridges[e.id]) end   -- a stem is not the town
	local function loopOk(pc)
		if not guardOn then return true end
		-- (deep arms: a block beside an arm's spine is a strip, not a balloon on a string, even where the spine
		-- reached out ahead of its blocks)
		if pc.armPiece and mp.hasArmLines and M.ARM_LOOPS then return true end
		-- (motif pieces: a terrace loop off the climbing street is the motif, not a balloon)
		if pc.motif and M.MOTIF_FREE then return true end
		if uf[pc.a] == nil or uf[pc.b] == nil then return true end
		local r = find(pc.a)
		if r ~= find(pc.b) or (anchors[r] or 1) >= 2 then return true end
		local mx, my = G.polyAt(pc.pts, 0.5)
		return OG.distToEdgesWhere(g, mx, my, hugR, notBridge) ~= nil
	end
	-- (R4: no empty loops in organic styles; the housed index is read below, before the greedy loop)
	local emptyLoopIdx = nil
	report.emptyLoopHeld = 0
	local emptyLoopKeys = {}
	local function emptyLoopOk(pc)
		if emptyLoopIdx == nil or pc.motif or pc.armPiece then return true end
		if uf[pc.a] == nil or uf[pc.b] == nil or find(pc.a) ~= find(pc.b) then return true end
		local mx, my = G.polyAt(pc.pts, 0.5)
		if M.housedDist(emptyLoopIdx, mx, my) <= M.EMPTY_LOOP_M then return true end
		if not emptyLoopKeys[pc.key] then
			emptyLoopKeys[pc.key] = true
			report.emptyLoopHeld = report.emptyLoopHeld + 1
		end
		return false
	end
	-- streets at each node: graph nodes by id (number), new junctions by "k" .. key: { {dx, dy, other} }
	local chosenAt = {}
	local function aid(k)
		local n = jnode[k]
		if n then return n end
		return "k" .. k
	end
	local function incident(a)
		local list = {}
		if type(a) == "number" and g.adj[a] then
			for _, eid in ipairs(g.adj[a]) do
				local e = g.edgeById[eid]
				local h = OG.headingFrom(g, e, a)
				list[#list + 1] = { math.cos(h), math.sin(h), OG.other(e, a) }
			end
		end
		for _, x in ipairs(chosenAt[a] or {}) do list[#list + 1] = x end
		return list
	end
	local function endDir(pc, atA)
		local pts = pc.pts
		if atA then
			if pc.dirA then return pc.dirA[1], pc.dirA[2] end
			local p = pts[1]
			if p[3] then return p[3], p[4] end
			local ux, uy = G.unit(pts[2][1] - p[1], pts[2][2] - p[2])
			return ux, uy
		end
		if pc.dirB then return -pc.dirB[1], -pc.dirB[2] end
		local p = pts[#pts]
		if p[3] then return -p[3], -p[4] end
		local ux, uy = G.unit(pts[#pts - 1][1] - p[1], pts[#pts - 1][2] - p[2])
		return ux, uy
	end
	local ZZ = math.rad(M.ZIGZAG_DEG)
	local function turn(ix, iy, ox, oy) return G.atan2(ix * oy - iy * ox, ix * ox + iy * oy) end
	-- would pc make the third corner of a zig-zag chain (corners alternating left / right at nodes with two streets
	-- along the street it continues)? A single S of two corners stays allowed.
	local function zigzag(pc)
		for side = 1, 2 do
			local atA = side == 1
			local a = aid(atA and pc.a or pc.b)
			local list = incident(a)
			if #list == 1 then
				local o = list[1]
				local dx, dy = endDir(pc, atA)
				local t1 = turn(-o[1], -o[2], dx, dy)
				if math.abs(t1) > ZZ then
					local lp = incident(o[3])
					if #lp == 2 then
						local toK, other
						if lp[1][3] == a then toK, other = lp[1], lp[2] elseif lp[2][3] == a then toK, other = lp[2], lp[1] end
						if toK then
							local t0 = turn(-other[1], -other[2], toK[1], toK[2])
							if math.abs(t0) > ZZ and t0 * t1 < 0 then
								-- an S so far; a chain when the corner before it turned the other way again
								local P, lq = o[3], incident(other[3])
								if #lq == 2 then
									local toP, otherQ
									if lq[1][3] == P then toP, otherQ = lq[1], lq[2] elseif lq[2][3] == P then toP, otherQ = lq[2], lq[1] end
									if toP then
										local tq = turn(-otherQ[1], -otherQ[2], toP[1], toP[2])
										if math.abs(tq) > ZZ and tq * t0 < 0 then return true end
									end
								end
							end
						end
					end
				end
			end
		end
		return false
	end
	-- §69 look rules of steer towns (M.RAKE / M.WIGGLE, opts.limits.steer): rakes of parallel dead ends, wiggling arms
	local steerLook = opts.limits ~= nil and opts.limits.steer == true and #g.edges > 0
	local rakeOn, wiggleOn = steerLook and M.RAKE, steerLook and M.WIGGLE
	report.rakeHeld, report.rakeJoin, report.wiggleHeld = 0, 0, 0
	local rakeRelaxed, wiggleRelaxed = false, false
	local rakeHeldKeys, wiggleHeldKeys = {}, {}
	local spurs, spurAt = nil, nil
	local function spurList()
		if spurs ~= nil then return spurs end
		spurs, spurAt = {}, {}
		local des = OG.deadEnds(g)
		for i = 1, math.min(#des, M.RAKE_SCAN) do
			local nid = des[i]
			local n = g.nodeById[nid]
			local cur, prev, len = nid, nil, 0
			for _ = 1, M.RAKE_WALK do
				local nxt = nil
				for _, eid in ipairs(g.adj[cur] or {}) do
					local o = OG.other(g.edgeById[eid], cur)
					if o ~= prev and o ~= cur then nxt = o break end
				end
				if nxt == nil then break end
				local a, b = g.nodeById[cur], g.nodeById[nxt]
				if a == nil or b == nil then break end
				len = len + G.dist(a.x, a.y, b.x, b.y)
				prev, cur = cur, nxt
				if OG.degree(g, cur) ~= 2 or len > M.RAKE_SPUR_M then break end
			end
			local b = g.nodeById[cur]
			if n and b and prev ~= nil and OG.degree(g, cur) >= 3 and len <= M.RAKE_SPUR_M and len > 1e-6 then
				local ux, uy = G.unit(n.x - b.x, n.y - b.y)
				local sp = { node = nid, x = n.x, y = n.y, bx = b.x, by = b.y, ux = ux, uy = uy, len = len }
				spurs[#spurs + 1] = sp
				spurAt[nid] = sp
			end
		end
		return spurs
	end
	local rakeCos = math.cos(math.rad(M.RAKE_DEG))
	local rakeR, rakeJoinR = M.RAKE_R * style.block.len, M.RAKE_JOIN_R * style.block.len
	-- (static per select: st.rakeJoin = pc joins the tips of two parallel spurs; st.rakeN = the parallel spurs beside the
	-- new spur pc would start from an existing node)
	local function rakeInfo(pc, st)
		if st.rakeN ~= nil then return end
		st.rakeN, st.rakeJoin = 0, false
		if pc.motif or pc.connector or pc.ringArc then return end
		spurList()
		local na, nb = jnode[pc.a], jnode[pc.b]
		if na and nb then
			local s1, s2 = spurAt[na], spurAt[nb]
			if s1 and s2 and s1 ~= s2 and s1.ux * s2.ux + s1.uy * s2.uy >= rakeCos
				and G.dist(s1.x, s1.y, s2.x, s2.y) <= rakeJoinR then st.rakeJoin = true end
			return
		end
		if (na == nil) == (nb == nil) then return end
		local near = na and pc.pts[1] or pc.pts[#pc.pts]
		local far = na and pc.pts[#pc.pts] or pc.pts[1]
		local ux, uy = G.unit(far[1] - near[1], far[2] - near[2])
		local n = 0
		for _, sp in ipairs(spurs) do
			if sp.node ~= (na or nb) and ux * sp.ux + uy * sp.uy >= rakeCos and G.dist(far[1], far[2], sp.x, sp.y) <= rakeR
				and G.dist(near[1], near[2], sp.bx, sp.by) <= rakeR + sp.len then n = n + 1 end
		end
		st.rakeN = n
	end
	local function rakeOk(pc)
		if not rakeOn or rakeRelaxed then return true end
		local st = info[pc.key]
		rakeInfo(pc, st)
		if st.rakeN >= M.RAKE_N then
			if not rakeHeldKeys[pc.key] then
				rakeHeldKeys[pc.key] = true
				report.rakeHeld = report.rakeHeld + 1
			end
			return false
		end
		return true
	end
	local function isRakeJoin(pc)
		if not rakeOn then return false end
		local st = info[pc.key]
		rakeInfo(pc, st)
		return st.rakeJoin
	end
	-- wiggle: the signed turns of the street arriving at graph node nid (from the dead end back), walked along the
	-- straightest continuation; returns the incoming direction (unit) and the last corner's signed turn (or 0)
	local wigMin, wigMax, wigSum = math.rad(M.WIGGLE_MIN), math.rad(M.TURN_MAX), math.rad(M.WIGGLE_DEG)
	local function arriving(nid)
		local adjN = g.adj[nid]
		if adjN == nil or #adjN ~= 1 then return nil end
		local e = g.edgeById[adjN[1]]
		local prev = OG.other(e, nid)
		local h = OG.headingFrom(g, e, nid) + math.pi   -- arriving at nid (its tangent there)
		local inx, iny = math.cos(h), math.sin(h)
		local h0 = OG.headingFrom(g, e, prev)           -- leaving prev toward nid
		local cur, cx, cy = prev, math.cos(h0), math.sin(h0)
		local walked = G.dist(g.nodeById[prev].x, g.nodeById[prev].y, g.nodeById[nid].x, g.nodeById[nid].y)
		local from = nid
		for _ = 1, M.WIGGLE_WALK do
			if walked > M.WIGGLE_BACK_M then break end
			local best, bt, bx, by = nil, math.huge, nil, nil
			for _, eid in ipairs(g.adj[cur] or {}) do
				local e2 = g.edgeById[eid]
				local o = OG.other(e2, cur)
				if o ~= from then
					local h2 = OG.headingFrom(g, e2, cur) + math.pi   -- arriving at cur from o
					local t = turn(math.cos(h2), math.sin(h2), cx, cy)
					if math.abs(t) < math.abs(bt) then
						local h3 = OG.headingFrom(g, e2, o)            -- leaving o toward cur
						best, bt, bx, by = o, t, math.cos(h3), math.sin(h3)
					end
				end
			end
			if best == nil or math.abs(bt) > math.rad(70) then break end
			if math.abs(bt) >= wigMin then return inx, iny, bt end
			local a, b = g.nodeById[cur], g.nodeById[best]
			walked = walked + G.dist(a.x, a.y, b.x, b.y)
			from, cur, cx, cy = cur, best, bx, by
		end
		return inx, iny, 0
	end
	local function wiggleOk(pc)
		if not wiggleOn or wiggleRelaxed then return true end
		if not (pc.class == "main" or pc.class == "medium" or pc.armLine) or pc.motif or pc.connector or pc.ringArc then return true end
		local st = info[pc.key]
		if st.wig == nil then
			st.wig = false
			for side = 1, 2 do
				local atA = side == 1
				local nid = jnode[atA and pc.a or pc.b]
				local other = jnode[atA and pc.b or pc.a]
				if nid and other == nil then
					local ix, iy, last = arriving(nid)
					if ix then
						local dx, dy = endDir(pc, atA)
						local t1 = turn(ix, iy, dx, dy)
						if math.abs(t1) > wigMax or (math.abs(t1) >= wigMin and last ~= 0 and t1 * last < 0
							and math.abs(t1) + math.abs(last) > wigSum) then st.wig = true end
					end
				end
			end
		end
		if st.wig then
			if not wiggleHeldKeys[pc.key] then
				wiggleHeldKeys[pc.key] = true
				report.wiggleHeld = report.wiggleHeld + 1
			end
			return false
		end
		return true
	end
	-- §70 knots (M.KNOT, ot_knot): crossings off a shared node, long near-parallel runs, small loops (steer towns); §75
	-- (2026-10-19): the parallel run over the whole street (the piece and the street behind its ends through two-street
	-- nodes, ot_knot.chainBehind), connectors too, and a side street leaving a junction under 60 deg (`side`, ot_check
	-- sideBad); `parallel` and `side` never give way (the planner refuses a side street anyway).
	local knotOn = steerLook and M.KNOT and KN.ON
	report.knotHeld, report.knotWhy = 0, {}
	local knotRelaxed = false
	local knotHeldKeys = {}
	local knotLim = KN.limits(style)
	-- (knotAdj[id] = { { other id, len, pts from id, tag } } of the chosen pieces: KN.way reads the first two)
	local knotChosen, knotAdj, knotPos = {}, {}, {}
	cache.knotEdgePts = cache.knotEdgePts or {}
	local function edgeCurve(e)
		local c = cache.knotEdgePts[e.id]
		if c == nil then
			c = KN.edgePts(g, e) or false
			cache.knotEdgePts[e.id] = c
		end
		return c or nil
	end
	local function knotPosOf(id)
		if type(id) == "number" then
			local n = g.nodeById[id]
			if n then return n.x, n.y end
			return nil
		end
		local p = knotPos[id]
		if p then return p[1], p[2] end
		return nil
	end
	-- (one table for the §75 helpers: the function is at the local variable limit)
	local kc = { side = math.rad(CK.LIMITS.sideAngle), sideOn = M.SIDE and (M.SIDE_GRID or style.grower == "organic") }
	-- the streets at node id ({ other id, pts from id outward, tag }): the graph's, and with `chosen` this increment's
	function kc.at(id, chosen)
		local out = type(id) == "number" and KN.graphAt(g, id, edgeCurve) or {}
		if chosen then for _, x in ipairs(knotAdj[id] or {}) do out[#out + 1] = { x[1], x[3], x[4] } end end
		return out
	end
	-- heading from (x, y) to the first point of polyline Q at least 20 m away (its last point if none): a piece's way out
	-- of its node as the planner sees it (a lattice junction mapped to a node a few metres off; ot_plan's first edge)
	function kc.head(x, y, Q)
		if Q == nil or #Q < 2 then return nil end
		local k = 2
		while k < #Q and G.dist(x, y, Q[k][1], Q[k][2]) < 20 do k = k + 1 end
		if G.dist(x, y, Q[k][1], Q[k][2]) < 1 then return nil end
		return G.heading(x, y, Q[k][1], Q[k][2])
	end
	-- the side rule at the piece's end node id leaving along Q (from that end; with `chosen`: only when a chosen piece is
	-- there). Graph streets by their tangents (ot_plan's headings), pieces from the node's position.
	function kc.sideAt(id, Q, chosen)
		if id == nil or Q == nil then return false end
		local x, y = knotPosOf(id)
		if x == nil then x, y = Q[1][1], Q[1][2] end
		local arms, any = {}, false
		if type(id) == "number" and g.adj[id] then
			for _, eid in ipairs(g.adj[id]) do arms[#arms + 1] = { h = OG.headingFrom(g, g.edgeById[eid], id) } end
		end
		if chosen then
			for _, c in ipairs(knotAdj[id] or {}) do
				local hc = kc.head(x, y, c[3])
				if hc then arms[#arms + 1] = { h = hc }; any = true end
			end
		end
		if #arms < 2 or (chosen and not any) then return false end
		local h = kc.head(x, y, Q)
		if h == nil then return false end
		arms[#arms + 1] = { h = h, new = true }
		return CK.sideBad(arms, kc.side) ~= nil
	end
	-- the piece's side rule at both ends (static: the graph; chosen: this increment's pieces too)
	function kc.side2(pc, P, chosen)
		if not kc.sideOn or (pc.motif and M.SIDE_FREE[pc.motif]) then return false end
		local R = {}
		for i = #P, 1, -1 do R[#R + 1] = P[i] end
		local a, b = pc.a, pc.b
		if chosen then a, b = aid(a), aid(b) else a, b = jnode[a], jnode[b] end
		return kc.sideAt(a, P, chosen) or kc.sideAt(b, R, chosen)
	end
	-- the parallel run of the whole street through the piece (§75): its chain behind both ends, the streets near it
	-- (the chain's own left out); `chosen` adds this increment's pieces. Returns true when it is a knot, and whether the
	-- chosen pieces took part (else the static answer stands).
	function kc.par(pc, P, chosen)
		local own = "p" .. tostring(pc.key)
		local ia, ib = aid(pc.a), aid(pc.b)
		local function at(id) return kc.at(id, chosen) end
		local pa, ta, ea = KN.chainBehind(ia, own, at)
		local R = {}
		for i = #P, 1, -1 do R[#R + 1] = P[i] end
		local pb, tb, eb = KN.chainBehind(ib, own, at)
		local tags = {}
		for k in pairs(ta) do tags[k] = true end
		for k in pairs(tb) do tags[k] = true end
		local used = false
		local function others(Q)
			local out = {}
			for _, id in ipairs(KN.near(g, Q, knotLim.parM)) do
				local e = g.edgeById[id]
				local E = e and not tags["e" .. tostring(id)] and edgeCurve(e)
				if E then out[#out + 1] = E end
			end
			if chosen then
				local x0, y0, x1, y1 = KN.bbox(Q)
				local pad = knotLim.parM
				for _, c in ipairs(knotChosen) do
					if not tags[c.tag] and not (c.x0 > x1 + pad or c.x1 < x0 - pad or c.y0 > y1 + pad or c.y1 < y0 - pad) then
						out[#out + 1] = c.pts
						used = true
					end
				end
			end
			return out
		end
		if chosen then
			for k in pairs(tags) do if k:sub(1, 1) == "p" then used = true end end
		end
		-- (the piece alone first, no skips: nothing beside it, no run through it; with `chosen`, nothing new: the static
		-- answer stands)
		local oP = others(P)
		if chosen and not used then return false, used end
		-- (the chain's own streets too: a street bent back beside itself)
		for _, Q in ipairs(pa) do oP[#oP + 1] = Q end
		for _, Q in ipairs(pb) do oP[#oP + 1] = Q end
		if KN.parallelRun(P, oP, knotLim, { skip0 = 0, skip1 = 0 }) <= 0 then return false, used end
		local C, s0, s1, k0, k1 = KN.streetLine(P, pa, ea, pb, eb)
		local run = KN.parallelRun(C, others(C), knotLim, { s0 = s0, s1 = s1, skip0 = k0, skip1 = k1, self = true })
		return run >= knotLim.parRun, used
	end
	-- one empty row at a time (§75 follow-up, 2026-10-19, KN.ROW; user shot 5: three long empty parallel dead-end lanes
	-- ~45 m apart, no houses): a piece leaving a new dead end (an end at no town street and no chosen piece) waits while
	-- it runs beside one of the mod's own streets without a house (KN.emptyOurs) or a piece chosen in this increment,
	-- within rowM for rowNeed m. Organic growers (grid towns lay their lattice by design, as SIDE_GRID), house data
	-- needed, opts.limits.rowHold ~= false (the driver: false on forced plans, which grow regardless of demand); never
	-- relaxed; motif / ring / crescent / connector pieces exempt; a piece closing a block passes.
	kc.rowOn = M.ROW and KN.ROW and style.grower == "organic" and g.hasBuilt == true
		and not (opts.limits ~= nil and opts.limits.rowHold == false)
	kc.rowLim = { parM = knotLim.rowM, parCos = knotLim.parCos }
	function kc.openEnd(k)
		local id = aid(k)
		if type(id) == "number" then return false end
		local a = knotAdj[id]
		return a == nil or #a == 0
	end
	function kc.row(pc, st, P)
		if not kc.rowOn or pc.motif or pc.ringArc or pc.crescent or pc.connector then return false end
		if not (kc.openEnd(pc.a) or kc.openEnd(pc.b)) then return false end
		local na, nb = jnode[pc.a], jnode[pc.b]
		if st.rowO == nil then
			-- (the graph's empty streets of ours near the piece, those at its own end nodes left out: static per select)
			st.rowO = {}
			for _, id in ipairs(KN.near(g, P, knotLim.rowM)) do
				local e = g.edgeById[id]
				if e and KN.emptyOurs(e) and e.n0 ~= na and e.n1 ~= na and e.n0 ~= nb and e.n1 ~= nb then
					local Q = edgeCurve(e)
					if Q then st.rowO[#st.rowO + 1] = Q end
				end
			end
			st.rowNeed = KN.rowNeed(G.polyLen(P))
		end
		local others = st.rowO
		if #knotChosen > 0 then
			local ia, ib = aid(pc.a), aid(pc.b)
			local x0, y0, x1, y1 = KN.bbox(P)
			local pad = knotLim.rowM
			local tag = "p" .. tostring(pc.key)
			others = {}
			for i, Q in ipairs(st.rowO) do others[i] = Q end
			for _, c in ipairs(knotChosen) do
				if c.tag ~= tag and c.a ~= ia and c.b ~= ia and c.a ~= ib and c.b ~= ib
					and not (c.x0 > x1 + pad or c.x1 < x0 - pad or c.y0 > y1 + pad or c.y1 < y0 - pad) then
					others[#others + 1] = c.pts
				end
			end
		end
		if #others == 0 then return false end
		return KN.parallelRun(P, others, kc.rowLim, { skip0 = 0, skip1 = 0 }) >= st.rowNeed
	end
	-- (static per select, the piece against the graph's streets: side / parallel (never relaxed), cross)
	-- (cross first, then side / parallel: a relaxed increment still holds the last two)
	local function knotGraph(pc, st, P)
		if not (knotRelaxed or pc.motif or pc.connector or pc.ringArc) then
			if st.knotGc == nil then
				st.knotGc = false
				local na, nb = jnode[pc.a], jnode[pc.b]
				for _, id in ipairs(KN.near(g, P, knotLim.parM)) do
					local e = g.edgeById[id]
					local Q = e and edgeCurve(e)
					if Q then
						local sp = { [1] = na ~= nil and (e.n0 == na or e.n1 == na), [2] = nb ~= nil and (e.n0 == nb or e.n1 == nb) }
						local sq = { [1] = (na ~= nil and e.n0 == na) or (nb ~= nil and e.n0 == nb),
							[2] = (na ~= nil and e.n1 == na) or (nb ~= nil and e.n1 == nb) }
						if KN.crosses(P, Q, sp, sq) then st.knotGc = "cross" break end
					end
				end
			end
			if st.knotGc then return st.knotGc end
		end
		if st.knotG == nil then
			st.knotG = false
			if kc.side2(pc, P, false) then st.knotG = "side"
			elseif not (pc.motif or pc.ringArc) and kc.par(pc, P, false) then st.knotG = "parallel" end
		end
		return st.knotG
	end
	local function knotNbrs(id)
		local out = {}
		if type(id) == "number" and g.adj[id] then
			for _, eid in ipairs(g.adj[id]) do
				local e = g.edgeById[eid]
				out[#out + 1] = { OG.other(e, id), OG.edgeLength(g, e) }
			end
		end
		for _, x in ipairs(knotAdj[id] or {}) do out[#out + 1] = x end
		return out
	end
	local function knotWhy(pc)
		if not knotOn then return nil end
		-- (cross / loop: not motif, ring or connector pieces; parallel: not motif or ring pieces; side: every piece but
		-- the climbing motifs')
		local exK = pc.motif or pc.connector or pc.ringArc
		local sideOn = kc.sideOn and not (pc.motif and M.SIDE_FREE[pc.motif])
		if (pc.motif or pc.ringArc) and not sideOn then return nil end
		local st = info[pc.key]
		if st.knotP == nil then st.knotP = KN.dense(pc.pts) or false end
		local P = st.knotP
		if not P or #P < 2 then return nil end
		local w = knotGraph(pc, st, P)
		if w then return w end
		-- (against this increment's chosen pieces and the loop it may close: again only when the chosen set changed)
		if st.knotStamp == #knotChosen and st.knotRelaxed == knotRelaxed then return st.knotDyn or nil end
		st.knotStamp, st.knotRelaxed, st.knotDyn = #knotChosen, knotRelaxed, false
		local ia, ib = aid(pc.a), aid(pc.b)
		if not (knotRelaxed or exK) then
			local x0, y0, x1, y1 = KN.bbox(P)
			local pad = knotLim.parM
			for _, c in ipairs(knotChosen) do
				if not (c.x0 > x1 + pad or c.x1 < x0 - pad or c.y0 > y1 + pad or c.y1 < y0 - pad) then
					local sp = { [1] = c.a == ia or c.b == ia, [2] = c.a == ib or c.b == ib }
					local sq = { [1] = c.a == ia or c.a == ib, [2] = c.b == ia or c.b == ib }
					if KN.crosses(P, c.pts, sp, sq) then st.knotDyn = "cross" return "cross" end
				end
			end
		end
		if #knotChosen > 0 then
			if kc.side2(pc, P, true) then st.knotDyn = "side" return "side" end
			if not (pc.motif or pc.ringArc) and kc.par(pc, P, true) then st.knotDyn = "parallel" return "parallel" end
		end
		-- (one empty row at a time: never relaxed; its dead-end test reads the chosen pieces, so it is dynamic)
		if kc.row(pc, st, P) then st.knotDyn = "row" return "row" end
		if knotRelaxed or exK then return nil end
		if reached[pc.a] and reached[pc.b] then
			local path = KN.way(ia, ib, knotNbrs, knotPosOf, knotLim.perim)
			if path and #path >= 2 and KN.loopArea(P, path) < knotLim.loopA then st.knotDyn = "loop" return "loop" end
		end
		return nil
	end
	local function knotOk(pc)
		local w = knotWhy(pc)
		if w == nil then return true end
		if not knotHeldKeys[pc.key] then
			knotHeldKeys[pc.key] = true
			report.knotHeld = report.knotHeld + 1
			report.knotWhy[w] = (report.knotWhy[w] or 0) + 1
		end
		return false
	end
	local function knotChoose(pc)
		if not knotOn then return end
		local st = info[pc.key]
		local P = st and st.knotP
		if P == nil or P == false then P = KN.dense(pc.pts) end
		if P == nil or #P < 2 then return end
		local ia, ib = aid(pc.a), aid(pc.b)
		local x0, y0, x1, y1 = KN.bbox(P)
		local tag = "p" .. tostring(pc.key)
		knotChosen[#knotChosen + 1] = { pts = P, a = ia, b = ib, x0 = x0, y0 = y0, x1 = x1, y1 = y1, tag = tag }
		local L = G.polyLen(P)
		local R = {}
		for i = #P, 1, -1 do R[#R + 1] = P[i] end
		knotAdj[ia] = knotAdj[ia] or {}
		knotAdj[ib] = knotAdj[ib] or {}
		knotAdj[ia][#knotAdj[ia] + 1] = { ib, L, P, tag }
		knotAdj[ib][#knotAdj[ib] + 1] = { ia, L, R, tag }
		if type(ia) ~= "number" then knotPos[ia] = { P[1][1], P[1][2] } end
		if type(ib) ~= "number" then knotPos[ib] = { P[#P][1], P[#P][2] } end
	end
	-- §71 hooks (M.HOOK, ot_knot.hook): no curled dead ends (steer towns), tested once the increment is chosen (a U on
	-- its way to closing a block is fine within one increment; one left open is pruned, see below). (One table: the
	-- function is at the local variable limit.) hk.adj = { [node id] = { { other id, pts from this node, tag } } } of
	-- the chosen pieces.
	-- Organic growers only (M.HOOK_GRID false): the hooks seen were organic towns' curls; a grid town's diagonal meeting a
	-- grid line makes acute V spurs that its later blocks close, and pruning them changed the NA grid towns' course
	-- (test_demand NA grid seed 1: 11 -> 3 builds).
	local hk = { on = steerLook and M.HOOK and KN.HOOK and (M.HOOK_GRID or style.grower == "organic"), adj = {} }
	report.hookHeld, report.hookWhy = 0, {}
	function hk.rev(P)
		local out = {}
		for i = #P, 1, -1 do out[#out + 1] = P[i] end
		return out
	end
	-- (the streets at node id, each as { other id, pts from id outward, tag })
	function hk.at(id)
		local out = {}
		if type(id) == "number" and g.adj[id] then
			for _, eid in ipairs(g.adj[id]) do
				local e = g.edgeById[eid]
				local Q = e and edgeCurve(e)
				if Q then out[#out + 1] = { OG.other(e, id), e.n0 == id and Q or hk.rev(Q), "e" .. tostring(eid) } end
			end
		end
		for _, x in ipairs(hk.adj[id] or {}) do out[#out + 1] = { x[1], x[2], x[3] } end
		return out
	end
	-- (the hook of chosen piece pc whose end `near` (a plan key) joins the network and whose other end is a dead end:
	-- "turn" | "back" | nil; its own adjacency entry left out)
	function hk.why(pc, near)
		if pc.connector or pc.ringArc then return nil end
		if pc.motif and KN.HOOK_FREE[pc.motif] then return nil end
		local st = info[pc.key]
		if st.knotP == nil then st.knotP = KN.dense(pc.pts) or false end
		local P = st.knotP
		if not P or #P < 2 then return nil end
		local atA = near == pc.a
		if not atA then P = hk.rev(P) end
		local own = "p" .. tostring(pc.key)
		-- (walk back from the joined end through nodes with two streets: the dead-end street the piece extends)
		local chain, roots = {}, {}
		local cur, cameTag, back = aid(near), own, 0
		local seen = { [cur] = true }
		local first = true
		for _ = 1, KN.HOOK_WALK + 1 do
			local list = {}
			for _, x in ipairs(hk.at(cur)) do if x[3] ~= own then list[#list + 1] = x end end
			-- (the streets at the node, the piece's own counted at its joined end: two there means it extends a dead end)
			local d = #list + (first and 1 or 0)
			first = false
			if d ~= 2 then
				-- (the junction the chain starts from: its other streets)
				if d >= 3 then for _, x in ipairs(list) do if x[3] ~= cameTag then roots[#roots + 1] = x[2] end end end
				break
			end
			local nx = nil
			for _, x in ipairs(list) do if x[3] ~= cameTag then nx = x break end end
			if nx == nil or seen[nx[1]] or back > KN.HOOK_BACK_M or #chain >= KN.HOOK_WALK then break end
			chain[#chain + 1] = nx[2]   -- (from cur back to the next node)
			back = back + G.polyLen(nx[2])
			seen[nx[1]] = true
			cur, cameTag = nx[1], nx[3]
		end
		-- (the chain outward: from its junction to the piece's joined end, then the piece)
		local C = {}
		local function add(p)
			local q = C[#C]
			if q == nil or q[1] ~= p[1] or q[2] ~= p[2] then C[#C + 1] = p end
		end
		for i = #chain, 1, -1 do
			local Q = chain[i]
			for j = #Q, 1, -1 do add(Q[j]) end
		end
		for _, p in ipairs(P) do add(p) end
		return KN.hook(C, roots, knotLim)
	end
	function hk.choose(pc)
		if not hk.on then return end
		local st = info[pc.key]
		local P = st and st.knotP
		if P == nil or P == false then P = KN.dense(pc.pts) end
		if P == nil or #P < 2 then return end
		local ia, ib = aid(pc.a), aid(pc.b)
		local tag = "p" .. tostring(pc.key)
		hk.adj[ia] = hk.adj[ia] or {}
		hk.adj[ib] = hk.adj[ib] or {}
		hk.adj[ia][#hk.adj[ia] + 1] = { ib, P, tag }
		hk.adj[ib][#hk.adj[ib] + 1] = { ia, hk.rev(P), tag }
	end
	function hk.drop(pc)
		local tag = "p" .. tostring(pc.key)
		for _, id in ipairs({ aid(pc.a), aid(pc.b) }) do
			local l = hk.adj[id]
			if l then for i = #l, 1, -1 do if l[i][3] == tag then table.remove(l, i) end end end
		end
	end
	for _, k in ipairs(jkeys) do if reached[k] then ensure(k) end end
	for _, k in ipairs(dkeys) do ensure(k) end
	for _, k in ipairs(adopted) do ensure(k) end
	report.zigzagWait, report.loopWait = 0, 0

	-- greedy growth, cheapest frontier piece first (closing a loop halves the cost)
	local chosen, depthOf = {}, {}
	local inSet = {}   -- keys of the chosen pieces
	local budget = maxEdges
	local capLeads = #g.edges > 0 and opts.leadDepth ~= false
	local leadCap = type(opts.leadDepth) == "table" and opts.leadDepth or M.LEAD_DEPTH
	-- depth of the far end if pc were chosen now (nil: closes a loop / both ends reached)
	local function newDepth(pc)
		if reached[pc.a] and reached[pc.b] then return nil end
		local from = reached[pc.a] and pc.a or pc.b
		return (depth[from] or 0) + (pc.connector and 0 or 1)
	end
	-- shaped towns: pieces in an arm corridor (ot_shape.inArm) may lead one piece further, so the arms run out
	-- beyond the round core the game's own growth makes
	local shape = style.shape
	local armLead = shape ~= nil and shape.id ~= "compact" and opts.armLead ~= false
	-- lattice-first (style.lattice, Showcase v8 round): only on a plan anchored to the town's streets (a game-made core
	-- or a saved frame); a fresh lattice in an empty town grows as a regular grid anyway (more stubs with it: tested)
	local lattice = mp.anchored and style.lattice or nil
	cache.lattice = lattice
	-- the growth front: no piece beyond the town's front (90th percentile of the existing nodes' effective
	-- distance, ot_shape) + FRONT_REACH blocks. Depth caps alone let a spur run on increment after increment
	-- (each build starts again from its own dead end: a 2 km arterial into the field in the NA grid preview)
	local frontCap = nil
	if capLeads and opts.front ~= false then
		frontCap = cache.frontCap
		if frontCap == nil then
			-- junctions only (3+ streets: where blocks are); split points and dead ends of a spur don't move it
			local ds = {}
			local shaped = shape ~= nil and shape.id ~= "compact"
			for pass = 1, 2 do
				for _, n in ipairs(g.nodes) do
					local dg = OG.degree(g, n.id)
					if (pass == 1 and dg >= 3) or (pass == 2 and dg > 0) then
						ds[#ds + 1] = shaped and SH.distance(shape, n.x, n.y, opts.terrain)
							or G.dist(style.centre[1], style.centre[2], n.x, n.y)
					end
				end
				if #ds >= 5 then break end
				ds = {}
			end
			table.sort(ds)
			local q = ds[math.max(1, math.floor(#ds * M.FRONT_Q + 0.5))] or 0
			-- unshaped towns grow by the seeded sector preference and hotspots (leapfrog): a looser front
			-- (town form, ot_form: clustered towns keep a tight front, sprawling ones leapfrog farther)
			frontCap = q + (shaped and M.FRONT_REACH or M.FRONT_REACH_PLAIN) * math.max(style.block.len, style.block.depth)
				* (style.form and style.form.front or 1)
			cache.frontCap, cache.frontQ = frontCap, q
			if shaped and opts.envelope ~= false and M.ENVELOPE then cache.envCap = M.envelopeCap(g, style, opts.terrain) end
			-- (organic growers only: a grid's cross pieces are pruned until they close a block, so its arm tips
			-- rarely become junctions and the front never moved: NA grid towns stalled after 3 increments)
			if shaped and opts.armFill ~= false then
				cache.armBuilt, cache.armHoused, cache.armBehind = M.armBuiltFronts(g, style,
					opts.limits and opts.limits.armFillM or nil, opts.limits)
			end
			if shaped and opts.armFront ~= false and M.ARM_FRONT and style.grower == "organic" then
				-- (deep arms: one piece more, for the line tips one piece ahead of the last lane; the tips rule and
				-- the lead caps keep the spine from running out bare)
				cache.armFront = M.armFronts(g, style, mp.hasArmLines and M.ARM_TIPS and maxSeg or 0)
			end
		end
	end
	-- (a fast grower's demand increment: the front opts.limits.frontExtra blocks farther, M.FRONT_RELAX note)
	if frontCap and opts.limits and opts.limits.frontExtra then
		frontCap = frontCap + opts.limits.frontExtra * math.max(style.block.len, style.block.depth)
	end
	report.frontCap = frontCap
	report.armTrim = cache.armBuilt and cache.armBuilt.trimmed or 0
	-- housed front (M.HOUSED, style.housedLead): every point of a piece within the lead of a housed street
	if cache.housedIdx == nil then cache.housedIdx = (opts.housed ~= false and M.housedIndex(g, style)) or false end
	local housedIdx = cache.housedIdx or nil
	if M.EMPTY_LOOP and style.grower == "organic" and not style.metro then
		if cache.emptyLoopIdx == nil then cache.emptyLoopIdx = M.housedIndexM(g, M.EMPTY_LOOP_M) or false end
		emptyLoopIdx = cache.emptyLoopIdx or nil
	end
	local housedExtra = 0
	report.housedHeld = 0
	-- lead limit (M.MAX_LEAD_M, the head start's opts.limits.leadM): a hard cap from the housed streets
	if cache.leadIdx == nil then
		local lm = M.MAX_LEAD_M
		if opts.limits and opts.limits.leadM then lm = math.min(lm or math.huge, opts.limits.leadM) end
		-- (§69 steer towns: the lead beyond housed streets capped, no bare spikes; housed = housedMin buildings)
		if opts.limits and opts.limits.leadCap then lm = math.min(lm or math.huge, opts.limits.leadCap) end
		-- (no street with housedMin buildings yet: the plain index, so a young core is never left without a limit)
		local hm = opts.limits and opts.limits.housedMin
		cache.leadIdx = (opts.leadLimit ~= false and lm and (M.housedIndexM(g, lm, hm) or (hm and M.housedIndexM(g, lm)))) or false
	end
	local leadIdx = cache.leadIdx or nil
	if cache.ringIdx == nil then
		cache.ringIdx = (style.ringWobble and opts.leadLimit ~= false and M.housedIndexM(g, M.RING_LEAD_M)) or false
	end
	local ringIdx = cache.ringIdx or nil
	report.ringHeld = 0
	-- sparse streets (M.SPARSE, §57): no new piece among streets that stayed nearly empty
	if cache.sparseIdx == nil then
		local on = opts.sparse == true or (opts.limits ~= nil and opts.limits.sparse == true)
		cache.sparseIdx = (on and opts.leadLimit ~= false and M.sparseIndex(g)) or false
	end
	local sparseIdx = cache.sparseIdx or nil
	report.sparseHeld = 0
	-- (2026-10-15 §59: the starve relaxation below lets the held pieces back in, a few edges at most)
	local sparseRelaxed = false
	local sparseHeldKeys = {}
	local ringHeldKeys = {}
	local headArms = opts.limits ~= nil and opts.limits.headForm == true and shape ~= nil and SH.ARMED[shape.id] == true
	report.leadHeld = 0
	report.leadM = leadIdx and leadIdx.lead or nil
	local leadHeldKeys = {}
	-- away from industries (ot_industry HOLD_PEN, penHold: industries only, never player facilities): pieces deep in a
	-- works' buffer wait while the increment can fill elsewhere (the cost alone can't steer when the fronts leave fewer
	-- pieces than the budget: grid towns); they come back when the increment would starve (last of the relaxations
	-- below), so a boxed-in town still grows
	local indInfo = style.industry
	local indLevel = (indInfo ~= nil and IND.HOLD_PEN ~= nil) and IND.HOLD_PEN or nil
	report.indHeld = 0
	local indHeldNow = 0
	local function indOk(pc)
		if indLevel == nil or pc.indFree then return true end
		local st = info[pc.key]
		if st.pen == nil then
			local mx, my = G.polyAt(pc.pts, 0.5)
			st.pen = IND.penHold(indInfo, mx, my)
		end
		if st.pen >= indLevel then
			indHeldNow = indHeldNow + 1
			return false
		end
		return true
	end
	-- the held pieces come back a step at a time (least exposed first): before the fronts widen (IND.HOLD_FIRST: the
	-- widened fronts reached farther toward the works in the offline runs) or as the last relaxation
	local function indRelax()
		indLevel = indLevel + (IND.HOLD_STEP or 0.25)
		if indLevel > IND.PEN_CAP then indLevel = nil end
		report.indRelax = (report.indRelax or 0) + 1
	end
	-- forest-hugging towns (ot_forest HOLD_PEN, phase F): pieces mostly in dense forest wait while the increment can fill
	-- elsewhere (on clear land, along the edge, farther out once the fronts widen); they come back a step at a time
	-- (least wooded first) when it would starve, so a town boxed in by forest still grows. Motif pieces are never held
	-- (their lines must stay whole), only costed.
	local foInfo = style.forest
	-- (deep forest towns, 2026-10-14: their own hold / step / fill values, ot_forest.k; groves inside the town's frame
	-- never come, below)
	local foHold = FO.k(foInfo, "HOLD_PEN")
	local foCutFill, foCutMin = FO.k(foInfo, "CUT_FILL"), FO.k(foInfo, "CUT_MIN_M")
	local foLevel = (FO.active(foInfo) and foHold ~= nil) and foHold or nil
	-- (§65 stall guard level 3, opts.limits.forestStep: a stalled town's forest hold starts that many steps looser; the
	-- CUT_FILL cap below still applies)
	local foStep = opts.limits and tonumber(opts.limits.forestStep) or nil
	if foLevel and foStep and foStep > 0 then
		foLevel = math.min(1.01, foLevel + foStep * (FO.k(foInfo, "HOLD_STEP") or 0.2))
		report.forestStep = foStep
	end
	local foDeep = FO.isDeep(foInfo)
	local foFrameR = nil
	if foDeep then
		local fr = foInfo.frameR or (style.radius or 0) * FO.DEEP.FRAME_F
		foFrameR = math.max(FO.DEEP.FRAME_MIN, fr)
	end
	report.groveHeld = 0
	local groveSet = {}
	report.forestHeld = 0
	local foHeldNow = 0
	-- (R1: the chosen street length, its wooded length and the forest under its lots; the clearing budget left, ha)
	local foChosenM, foWoodM = 0, 0
	report.forestLot = 0
	local laneFreed = {}
	-- forest lanes through a held strip (round after the names run, 2026-10-13): in a hug town the pieces a lane needs
	-- (wooded on both sides) were all held. A held piece next to the town whose line crosses the forest (its wooded
	-- stretch LN.MIN_M..MAX_M long, then open land) may come with that whole stretch and the first open piece beyond, in
	-- one go (a bundle, like withTips): the driver's ot_lane.mark makes the wooded edges a locked country lane, the open
	-- piece the town street that goes on. Seeded per line (ot_lane.free), the town's lane quota.
	local laneBundles = {}
	local laneBundle   -- (below gapOk)
	local foBudget = foInfo and foInfo.budget or nil
	local foBudgetLeft = foBudget and math.max(0, foBudget.total - foBudget.used) or nil
	local function forestOk(pc)
		if foLevel == nil or pc.motif then return true end
		local st = info[pc.key]
		local co = M.corridorOf(foInfo, pc)
		if st.fpen == nil then st.fpen = FO.corridorPen(co) end
		-- (relaxed: the wooded pieces only fill the increment up to FO.CUT_FILL; a hug town grows into the forest a little
		-- at a time, the next increment looks for open land again. R1: with clearing budget left up to CUT_FILL of
		-- maxEdges (as before), else up to CUT_FILL of the street length actually chosen (CUT_MIN_M at least))
		local level = foLevel
		-- (deep forest towns: a piece across a grove (a small wood, ot_forest.groveCells) inside the town's frame never comes, whatever
		-- the relaxation: the streets wrap around it, it stays a green island; a lane through it may still come)
		if foDeep then
			if st.grove == nil then
				local c0 = style.centre or { 0, 0 }
				st.grove = FO.inGrove(foInfo, pc.pts, c0[1], c0[2], foFrameR)
			end
			if st.grove then
				if foInfo.laneFree and laneBundle(pc) then return true end
				if not groveSet[pc.key] then
					groveSet[pc.key] = true
					report.groveHeld = report.groveHeld + 1
				end
				foHeldNow = foHeldNow + 1
				return false
			end
		end
		if level > foHold and st.fpen >= foHold then
			local capped
			if foBudgetLeft == nil or foBudgetLeft - report.forestLot >= FO.lotSpend(foInfo, co) then
				capped = maxEdges - budget >= maxEdges * foCutFill
			else
				local pl, pw = co and co.len or 0, co and co.woodM or 0
				capped = foWoodM + pw > math.max(foCutMin, foCutFill * (foChosenM + pl))
			end
			if capped then level = foHold end
		end
		if st.fpen >= level then
			-- (forest lanes, round after the names run: a held piece whose line crosses the forest may come with the whole
			-- crossing as a locked country lane, laneBundle below; the driver's ot_lane.mark makes it one)
			if foInfo.laneFree and laneBundle(pc) then return true end
			foHeldNow = foHeldNow + 1
			return false
		end
		return true
	end
	local function forestRelax()
		-- (at most just over 1: every piece may come, the CUT_FILL cap in forestOk still applies)
		foLevel = math.min(1.01, foLevel + (FO.k(foInfo, "HOLD_STEP") or 0.2))
		report.forestRelax = (report.forestRelax or 0) + 1
	end
	-- gaps between towns (ot_gap, R3): pieces in the gap before the halfway line to a neighbour (or past it, or on land
	-- the engine gives another town) never come; twins' main roads go on to the line
	local gapInfo = style.gaps
	report.gapHeld = 0
	local gapHeldNow = 0
	-- industry keep-clear zones (ot_industry.zoneHit, 2026-10-13): a piece whose street or lots enter one never comes
	-- (no relaxation; motif pieces too): the industry's fields need the room to grow. Counted as zoneHeld.
	local zoneInfo = (IND.ZONE and indInfo ~= nil and indInfo.zones ~= nil and #indInfo.zones > 0) and indInfo or nil
	report.zoneHeld = 0
	local zoneHeldSet = {}
	local function gapOk(pc)
		local st = info[pc.key]
		if zoneInfo ~= nil then
			if st.zone == nil then st.zone = IND.zoneHit(zoneInfo, pc.pts) ~= nil end
			if st.zone then
				if not zoneHeldSet[pc.key] then
					zoneHeldSet[pc.key] = true
					report.zoneHeld = report.zoneHeld + 1
				end
				return false
			end
		end
		if gapInfo == nil then return true end
		if st.gap == nil then st.gap = GP.held(gapInfo, pc.pts, pc.class) or false end
		if st.gap then
			gapHeldNow = gapHeldNow + 1
			return false
		end
		return true
	end
	laneBundle = function(pc)
		local cached = laneBundles[pc.key]
		if cached ~= nil then return cached or nil end
		laneBundles[pc.key] = false
		if pc.motif or not LN.lineOk(pc.key) then return nil end
		local from = (reached[pc.a] and pc.a) or (reached[pc.b] and pc.b) or nil
		if from == nil then return nil end
		local line = LN.lineOf(pc.key)
		local list, wooded, seenK = { pc }, { [pc.key] = true }, { [pc.key] = true }
		local co0 = M.corridorOf(foInfo, pc)
		local agg = { len = co0.len, c = co0.c * co0.len, l = co0.l * co0.len, r = co0.r * co0.len }
		local cur, k = pc, (pc.a == from) and pc.b or pc.a
		local exited = false
		for _ = 1, 24 do
			local nxt = nil
			for _, o in ipairs(adj[k] or {}) do
				if o ~= cur and not seenK[o.key] and LN.lineOf(o.key) == line then nxt = o break end
			end
			if nxt == nil then break end
			local st = getInfo(nxt)
			if not st.need or exclude[nxt.key] or inSet[nxt.key] or st.built or not gapOk(nxt) then break end
			seenK[nxt.key] = true
			list[#list + 1] = nxt
			local co = M.corridorOf(foInfo, nxt)
			if FO.corridorPen(co) < foHold then exited = true break end
			wooded[nxt.key] = true
			agg.len = agg.len + co.len
			agg.c, agg.l, agg.r = agg.c + co.c * co.len, agg.l + co.l * co.len, agg.r + co.r * co.len
			if agg.len > LN.MAX_M then break end
			cur, k = nxt, (nxt.a == k) and nxt.b or nxt.a
		end
		if not exited or agg.len < LN.MIN_M or agg.len > LN.MAX_M then return nil end
		local L = math.max(agg.len, 1e-6)
		local aggCo = { len = math.max(agg.len, LN.FREE_M), c = agg.c / L, l = agg.l / L, r = agg.r / L }
		-- (seeded per line: every piece of the crossing asks the same draw)
		if not foInfo.laneFree({ key = line, a = pc.a, b = pc.b }, aggCo) then return nil end
		local b = { list = list, wooded = wooded, len = agg.len }
		laneBundles[pc.key] = b
		return b
	end
	-- motif branches with `motifWait` (M3: cul-de-sac closes, terrace rows): a branch leaving a motif main line waits while
	-- the line's built tip is its junction and the line goes on from there unbuilt: built alone, it would take the tip's
	-- dead end and the line could never continue (the game joins only dead ends); withBranches brings it with the line's
	-- piece beyond. (M1 / M2 branches don't wait: their lines were measured without it.)
	local function branchOk(pc)
		if not (pc.motifWait and pc.motifBranch and not pc.motifLead and M.MOTIF_FREE) then return true end
		for _, k in ipairs({ pc.a, pc.b }) do
			local nid = jnode[k]
			if nid and OG.degree(g, nid) == 1 then
				for _, o in ipairs(adj[k] or {}) do
					if o ~= pc and o.motifLead and not (info[o.key] and info[o.key].built) then
						report.branchWait = (report.branchWait or 0) + 1
						-- (the line's next piece refused / left out: counted once per plan, ot_core; dropped at WAIT_GIVEUP)
						local so = getInfo(o)
						if opts.waitRefused and (exclude[o.key] or so.blocked or so.excluded) then
							opts.waitRefused[pc.key] = o.key
						end
						return false
					end
				end
			end
		end
		return true
	end
	local housedHeldKeys = {}
	report.armFill = 0   -- pieces held back by the fill rule (M.ARM_FILL)
	local fillHeld = {}
	if cache.armBuilt then
		local parts = {}
		for i, f in ipairs(cache.armBuilt) do
			local h = cache.armHoused[i]
			parts[i] = string.format("%s:%.0f", h and string.format("%.0f", h) or "-", f)
		end
		report.armBuilt = table.concat(parts, "/")
		report.armWait = cache.armBuilt.waiting or 0
	end
	-- the envelope and arm fronts of this call (relaxed below when they would starve the increment)
	local envScale = opts.envScale or 1
	-- strong-reach arm shapes (linear / ridge / fingers from the site or forced, ot_shape.reach): the envelope never
	-- widens; an under-filled increment instead lets the arms lead a little further than the fill rule (M.ARM_FILL_RELAX)
	-- or stays small (Showcase v7: the widened envelope took the held-back arm length sideways, inc=out100, and the
	-- houses filled the new side streets near the core first: the linear town grew round, elong 1.26)
	local strongArms = M.ARM_STRONG_HOLD and not opts.envWide and cache.armBuilt ~= nil and shape ~= nil and (shape.reach or 1) >= 1
	local blkMax = math.max(style.block.len, style.block.depth)
	local frontRelax, frontRelaxMax = 0, (opts.limits and tonumber(opts.limits.frontRelax)) or 0
	local envCap, armExtra, relax = cache.envCap and cache.envCap * (strongArms and 1 or envScale), 0, 0
	local fillExtra = 0
	if envScale > 1 then
		armExtra = (envScale - 1) * 5 * blkMax
		if strongArms then fillExtra = math.min(M.ARM_FILL_RELAX * blkMax, (envScale - 1) * 2 * blkMax) end
	end
	-- head start (opts.limits.envMul / armExtra, 2026-10-13): an armed shape's envelope and arm fronts reach further so
	-- the first streets draw its arms (the lead limit still holds every piece near the houses)
	local lim = opts.limits
	if lim and shape ~= nil and SH.ARMED[shape.id] then
		if envCap and lim.envMul then envCap = envCap * lim.envMul end
		if lim.armExtra then armExtra = armExtra + lim.armExtra * blkMax end
	end
	report.envCap = envCap
	-- green wedges (ot_wedge, 2026-10-13: style.wedges, set by the driver for armed shapes): beyond the core zone at the
	-- (unrelaxed) envelope level and outside every arm corridor nothing is planned; never relaxed
	local wedgeR = nil
	if style.wedges and opts.wedges ~= false and cache.envCap and WG.applies(style) then
		wedgeR = WG.coreR(shape, cache.envCap)
	end
	report.wedgeR = wedgeR
	report.wedgeHeld = 0
	local wedgeHeldKeys = {}
	-- (§59: the shape's limits counted too, for the empty PLAN line's `held=`: pieces beyond the envelope, an arm front,
	-- the late hierarchy's wide front or the housed front)
	report.envHeld, report.armFrontHeld, report.wideHeld, report.frontHeld = 0, 0, 0, 0
	local shapeHeldKeys = { envHeld = {}, armFrontHeld = {}, wideHeld = {}, frontHeld = {} }
	local function shapeHeld(field, key)
		local set = shapeHeldKeys[field]
		if not set[key] then
			set[key] = true
			report[field] = report[field] + 1
		end
		return false
	end
	-- protected meadows (ot_meadow, later-ideas phase: style.meadows, set by the driver for sprawling / unarmed character
	-- towns): beyond the core zone in a meadow sector between the lobes nothing is planned; never relaxed
	local meadow = nil
	if style.meadows and opts.meadows ~= false and MD.applies(style) then meadow = MD.zone(g, style, M.irregularity(style)) end
	report.meadowR = meadow and meadow.coreR or nil
	report.meadowHeld = 0
	report.meadowText = meadow and MD.text(meadow) or nil
	local meadowHeldKeys = {}
	-- late hierarchy: the tighter front for main / medium pieces (M.WIDE_REACH fine blocks beyond the front)
	local wideCap, wideFine = nil, 0
	if frontCap and style.hierarchy == "late" and opts.wideReach ~= false then
		local fine = math.max(style.block.len / ((style.sub and style.sub.u) or 1), style.block.depth / ((style.sub and style.sub.v) or 1))
		wideCap, wideFine = cache.frontQ + M.WIDE_REACH * fine, fine
		-- (lattice styles: the arterial frame may lead by whole cells, Showcase v8 round: superblock read as an organic
		-- core with a few loops, its arterials capped at 1.25 x the 87 m interior block)
		if lattice then wideCap = cache.frontQ + (lattice.lead or 1) * math.max(style.block.len, style.block.depth) end
		report.wideCap = wideCap
	end
	local function frontOk(pc)
		if frontCap == nil then return true end
		local st = info[pc.key]
		-- motif pieces (ot_motif_land, M1: the climbing street, ribs, the harbour crescent ...): no envelope, front, wedge,
		-- arm-fill or arm-front limit (the motif's own extent bounds them); the housed front and the lead limit below apply
		local mfree = pc.motif ~= nil and M.MOTIF_FREE
		if st.de == nil then
			local mx, my = G.polyAt(pc.pts, 0.5)
			local shaped = shape ~= nil and shape.id ~= "compact"
			st.de = shaped and SH.distance(shape, mx, my, opts.terrain) or G.dist(style.centre[1], style.centre[2], mx, my)
			if shaped and M.STRIP and (pc.armPiece or not mp.hasArmLines) then
				local ds = SH.stripDistance(shape, mx, my, opts.terrain)
				if ds and ds < st.de then st.de = ds end
			end
		end
		if not mfree and wideCap and (pc.class == "main" or pc.class == "medium")
			and st.de > wideCap + (pc.class == "medium" and M.WIDE_REACH_MEDIUM * wideFine or 0) then
			-- in an arm corridor of a shaped town the piece may still lead (the arms run out), at local width
			if not (armLead and SH.inArm(shape, G.polyAt(pc.pts, 0.5))) then return shapeHeld("wideHeld", pc.key) end
			st.ahead = true
		end
		if envCap and not mfree then
			-- (away from industries: the envelope leans away from the works, ot_industry ENV_K; the relaxation below
			-- still widens it when that would starve the increment)
			local de = st.de
			if style.industry then
				if st.dei == nil then
					local mx, my = G.polyAt(pc.pts, 0.5)
					st.dei = st.de * (1 + IND.ENV_K * IND.pen(style.industry, mx, my))
				end
				de = st.dei
			end
			if de > envCap then return shapeHeld("envHeld", pc.key) end
		end
		if wedgeR and not mfree then
			if st.wedge == nil then st.wedge = WG.polyInWedge(shape, pc.pts, wedgeR) end
			if st.wedge then
				if not wedgeHeldKeys[pc.key] then
					wedgeHeldKeys[pc.key] = true
					report.wedgeHeld = report.wedgeHeld + 1
				end
				return false
			end
		end
		if meadow and not mfree then
			if st.meadow == nil then st.meadow = MD.polyIn(meadow, pc.pts) end
			if st.meadow then
				if not meadowHeldKeys[pc.key] then
					meadowHeldKeys[pc.key] = true
					report.meadowHeld = report.meadowHeld + 1
				end
				return false
			end
		end
		if housedIdx then
			if st.housedD == nil then
				local far = 0
				local mx, my = G.polyAt(pc.pts, 0.5)
				for _, p in ipairs({ pc.pts[1], pc.pts[#pc.pts], { mx, my } }) do
					local d = M.housedDist(housedIdx, p[1], p[2])
					if d > far then far = d end
				end
				st.housedD = far
			end
			if st.housedD > housedIdx.lead + housedExtra then
				if not housedHeldKeys[pc.key] then
					housedHeldKeys[pc.key] = true
					report.housedHeld = report.housedHeld + 1
				end
				return false
			end
		end
		-- head start in an armed shape (opts.limits.headForm): only pieces in the arm corridors (and connectors), so the
		-- first streets draw the arms instead of rounding the core; the lead limit keeps them near the houses
		if headArms and not pc.connector and not mfree then
			if st.headArm == nil then st.headArm = SH.inArm(shape, G.polyAt(pc.pts, 0.5)) end
			if not st.headArm then
				report.headHeld = (report.headHeld or 0) + 1
				return false
			end
		end
		if leadIdx then
			if st.leadD == nil then
				local far = 0
				local mx, my = G.polyAt(pc.pts, 0.5)
				for _, p in ipairs({ pc.pts[1], pc.pts[#pc.pts], { mx, my } }) do
					local d = M.housedDist(leadIdx, p[1], p[2])
					if d > far then far = d end
				end
				st.leadD = far
			end
			if st.leadD > leadIdx.lead then
				if not leadHeldKeys[pc.key] then
					leadHeldKeys[pc.key] = true
					report.leadHeld = report.leadHeld + 1
				end
				return false
			end
		end
		if sparseIdx then
			if st.sparse == nil then
				st.sparse = false
				local mx, my = G.polyAt(pc.pts, 0.5)
				for _, p in ipairs({ pc.pts[1], pc.pts[#pc.pts], { mx, my } }) do
					if M.sparseAt(sparseIdx, p[1], p[2]) then st.sparse = true break end
				end
			end
			if st.sparse and not sparseRelaxed then
				if not sparseHeldKeys[pc.key] then
					sparseHeldKeys[pc.key] = true
					report.sparseHeld = report.sparseHeld + 1
				end
				return false
			end
		end
		if ringIdx and (pc.ringArc or pc.crescent or pc.motif == "ring_road") then
			if st.ringD == nil then
				local far = 0
				local mx, my = G.polyAt(pc.pts, 0.5)
				for _, p in ipairs({ pc.pts[1], pc.pts[#pc.pts], { mx, my } }) do
					local d = M.housedDist(ringIdx, p[1], p[2])
					if d > far then far = d end
				end
				st.ringD = far
			end
			if st.ringD > ringIdx.lead then
				if not ringHeldKeys[pc.key] then
					ringHeldKeys[pc.key] = true
					report.ringHeld = report.ringHeld + 1
				end
				return false
			end
		end
		if mfree then return true end
		if cache.armBuilt then
			if st.fillI == nil then
				-- (the arm the piece reaches farthest along, by its ends and midpoint: also pieces beside the corridor
				-- band, and a spine piece may be 2-3 edges long; a piece across the axis has along ~0 on every arm)
				local mx, my = G.polyAt(pc.pts, 0.5)
				local bi, ba = nil, 0
				if shape.id == "shore" then
					-- (shore towns: the arms follow the shoreline; along = arc length from the foot, ot_shape.armAt)
					for _, p in ipairs({ pc.pts[1], pc.pts[#pc.pts], { mx, my } }) do
						local k, al = SH.armAt(shape, p[1], p[2])
						if k and al > ba then bi, ba = k, al end
					end
				else
					for k, a in ipairs(shape.arms or { shape.axis }) do
						local ca, sa = math.cos(a), math.sin(a)
						for _, p in ipairs({ pc.pts[1], pc.pts[#pc.pts], { mx, my } }) do
							local al = (p[1] - shape.centre[1]) * ca + (p[2] - shape.centre[2]) * sa
							if al > ba then bi, ba = k, al end
						end
					end
				end
				st.fillI, st.fillAlong = bi or false, ba
			end
			local lim = st.fillI and cache.armBuilt[st.fillI]
			-- (a deep arm's back street / rung, not its spine: only beside the housed stretch)
			if st.fillI and pc.armPiece and mp.hasArmLines and not (pc.armLine and pc.armLine:sub(-2) == ":S") then
				lim = cache.armBehind[st.fillI]
			end
			if st.fillI and st.fillAlong > lim + fillExtra then
				if not fillHeld[pc.key] then
					fillHeld[pc.key] = true
					report.armFill = report.armFill + 1
				end
				return false
			end
		end
		if cache.armFront then
			if st.armI == nil then
				local mx, my = G.polyAt(pc.pts, 0.5)
				local i, along = SH.armAt(shape, mx, my, math.max(style.block.len, style.block.depth))
				st.armI, st.armAlong = i or false, along
			end
			if st.armI and st.armAlong > cache.armFront[st.armI] + armExtra then return shapeHeld("armFrontHeld", pc.key) end
		end
		if st.de > frontCap then return shapeHeld("frontHeld", pc.key) end
		return true
	end
	local function leadOk(pc)
		if not capLeads then return true end
		if not frontOk(pc) then return false end
		local nd = newDepth(pc)
		if nd == nil then return true end
		local cap = leadCap[pc.class or "small"] or 2
		-- (a motif's main line leads one piece further, M1)
		if pc.motifLead and M.MOTIF_FREE then cap = cap + M.MOTIF_LEAD end
		-- lattice styles (style.lattice: superblock): the arterial cell lines are laid out as whole frames ahead
		if lattice and (pc.class == "main" or pc.class == "medium") then cap = math.max(cap, lattice.depth or 8) end
		if armLead then
			local st = info[pc.key]
			if st.arm == nil then
				local mx, my = G.polyAt(pc.pts, 0.5)
				st.arm = SH.inArm(shape, mx, my)
			end
			-- (not the late collector lines: they run across the arms too and widened them, test_shapes)
			local lead = pc.class == "main" or (pc.class == "medium" and not style.collectorEvery and not style.sub)
			if st.arm and (lead or M.ARM_LEAD_SMALL) then cap = cap + M.ARM_LEAD end
			-- deep arms: the spine leads no further than its strip (the tips rule keeps it one piece ahead), and
			-- the strip's lanes and back streets may reach one piece further than small streets elsewhere (a lane
			-- and the back street behind it are built with the spine piece they belong to)
			-- (a back street only closes blocks: it runs on where lanes meet it, its tip one piece ahead by the
			-- tips rule, never as a bare line ahead of them, increment after increment)
			-- The spine likewise: from its own tip it goes on only with the lanes that meet it there (M.SPINE_TIPS)
			if pc.armPiece and mp.hasArmLines then
				local own = false
				if pc.armLine then
					-- (from its own tip: closing blocks only; starting from the town's streets: one piece)
					local from = reached[pc.a] and pc.a or pc.b
					for _, o in ipairs(adj[from] or {}) do
						if o ~= pc and o.armLine == pc.armLine and (inSet[o.key] or (info[o.key] and info[o.key].built)) then
							own = true
						end
					end
				end
				if pc.armLine and pc.armLine:sub(-2) == ":S" then
					cap = (own and M.SPINE_TIPS) and 0 or (leadCap[pc.class or "small"] or 2)
				elseif pc.armLine then
					cap = own and 0 or 1
				elseif pc.class == "small" then cap = cap + M.ARM_LEAD end
			end
		end
		return nd <= cap
	end
	-- saw-tooth outskirts (showcase v3): a piece that turns a corner at a node with one street (an L step at the
	-- frontier) costs more, one continuing it straight less (M.CORNER_PEN / M.STRAIGHT_BONUS)
	local smoothOn = opts.smooth
	if smoothOn == nil then smoothOn = M.SMOOTH end
	-- joint rule (M.JOINT_TURN): may pc leave the existing dead ends at its ends at its angle now?
	local jointOn = opts.jointRule
	if jointOn == nil then jointOn = M.JOINT_RULE end
	jointOn = jointOn and #g.edges > 0
	local function jointOk(pc)
		if not jointOn then return true end
		for side = 1, 2 do
			local atA = side == 1
			local nid = jnode[atA and pc.a or pc.b]
			if nid and OG.degree(g, nid) == 1 then
				local e = g.edgeById[g.adj[nid][1]]
				local h = OG.headingFrom(g, e, nid)
				local ox, oy = math.cos(h), math.sin(h)
				local dx, dy = endDir(pc, atA)
				local t = math.acos(G.clamp(-(dx * ox + dy * oy), -1, 1))
				if t > M.JOINT_TURN then
					-- only next to a piece chosen at this dead end that continues its street (the node becomes a T)
					local straight = false
					for _, x in ipairs(chosenAt[nid] or {}) do
						if math.acos(G.clamp(-(x[1] * ox + x[2] * oy), -1, 1)) <= M.JOINT_TURN then straight = true end
					end
					if not straight then return false end
				end
			end
		end
		return true
	end
	local function bend(pc)
		local f = 1
		for side = 1, 2 do
			local atA = side == 1
			local k = atA and pc.a or pc.b
			if reached[k] then
				local list = incident(aid(k))
				if #list == 1 then
					local o = list[1]
					local dx, dy = endDir(pc, atA)
					local t = math.abs(turn(-o[1], -o[2], dx, dy))
					if t > M.CORNER_DEG then f = f * M.CORNER_PEN elseif t < M.STRAIGHT_DEG then f = f * M.STRAIGHT_BONUS end
				end
			end
		end
		return f
	end
	-- arm line tips (M.ARM_TIPS): the pieces to choose together with pc so no arm line ends in a corner, or nil
	local tipsOn = M.ARM_TIPS and opts.armTips ~= false and #g.edges > 0 and mp.hasArmLines
	local function present(o, extra)
		if inSet[o.key] or extra[o.key] then return true end
		local st = getInfo(o)
		return st.built == true
	end
	-- motif branches (ot_motif_land, M1): the game joins only dead ends, so a rib / lane / terrace street leaving a motif's
	-- main line at a junction comes with the main-line piece that reaches that junction (later the junction is no dead end)
	local function withBranches(list, extra)
		if not M.MOTIF_FREE then return list end
		local function valid(o)
			if extra[o.key] or inSet[o.key] then return false end
			local st = getInfo(o)
			return st.need ~= nil and not exclude[o.key] and frontOk(o) and loopOk(o)
		end
		local function present(o) return extra[o.key] or inSet[o.key] or (info[o.key] and info[o.key].built) end
		local n0 = #list
		for i = 1, n0 do
			local p = list[i]
			if p.motifLead and p.motif then
				for _, k in ipairs({ p.a, p.b }) do
					local branches, passed, nextP, otherLead = {}, false, nil, false
					for _, o in ipairs(adj[k] or {}) do
						if o ~= p then
							if o.motifBranch then
								if not present(o) then branches[#branches + 1] = o end
							elseif o.motifLead and o.motifLine == p.motifLine then
								if present(o) then passed = true elseif nextP == nil then nextP = o end
							elseif o.motifLead then
								otherLead = true
							end
						end
					end
					if #branches > 0 then
						-- (the line passes the junction in this increment: its tip one piece beyond, a dead end)
						if not passed and nextP and valid(nextP) then
							list[#list + 1] = nextP
							extra[nextP.key] = true
							passed = true
						end
						-- (... or the line ends there at a new junction (not a town node), no other main line meets it, and the
						-- branches leave it: one junction of them all, M2 village green; M3 `motifJoin` pieces (the ring's
						-- joints, the station quarter's crossings) also at a town node that is still a dead end: they all
						-- join it in this increment)
						local free = jnode[k] == nil or (p.motifJoin and OG.degree(g, jnode[k]) <= 1)
						if passed or (nextP == nil and not otherLead and free) then
							for _, o in ipairs(branches) do
								if valid(o) then
									list[#list + 1] = o
									extra[o.key] = true
								end
							end
						end
					end
				end
			end
		end
		return list
	end
	local function withTips(pc)
		local list, extra = { pc }, { [pc.key] = true }
		withBranches(list, extra)
		if not tipsOn then return list end
		local i = 1
		while i <= #list do
			local p = list[i]
			-- (a lane or ring arc between two back streets, off the spine: the lines on both sides too, so it meets
			-- them in T's, never as a stub; else the outer row's lanes made a comb of stubs, a ladder one row out.
			-- Lanes from the spine may stay stubs for a while: the first rows keep up with the spine)
			local stubby = p.armLine == nil and (p.armOuter == true or (M.ARM_LANE_TS and p.armPiece ~= nil))
			for _, k in ipairs({ p.a, p.b }) do
				local deg = nil
				for _, o in ipairs(adj[k] or {}) do
					local line = o.armLine
					if line then
						if deg == nil then
							deg = #incident(aid(k))
							for _, x in ipairs(list) do if x.a == k or x.b == k then deg = deg + 1 end end
						end
						if deg < 2 and not stubby then break end
						-- a junction of an arm line with two or more streets: the line on both sides (a corner or a
						-- street passing through would stop the line there for good)
						if not present(o, extra) then
							local st = getInfo(o)
							if st.need and not exclude[o.key] then
								if not frontOk(o) or not loopOk(o) or not gapOk(o) then return nil end
								list[#list + 1] = o
								extra[o.key] = true
								if #list > 6 then return nil end
							end
							-- (built elsewhere / blocked / excluded: the line can't go on there anyway)
						end
					end
				end
			end
			i = i + 1
		end
		return list
	end
	local function choose(best)
		inSet[best.key] = true
		chosen[#chosen + 1] = best
		if foLevel ~= nil then
			local co = M.corridorOf(foInfo, best)
			if co then
				foChosenM, foWoodM = foChosenM + co.len, foWoodM + co.woodM
				report.forestLot = report.forestLot + FO.lotSpend(foInfo, co)
			end
		end
		-- roots (lasso rule) and the streets at both ends (zig-zag rule)
		local ra = uf[best.a] ~= nil and find(best.a) or nil
		local rb = uf[best.b] ~= nil and find(best.b) or nil
		if ra and rb then union(ra, rb)
		elseif ra then union(ensure(best.b, ra), ra)
		elseif rb then union(ensure(best.a, rb), rb)
		else union(ensure(best.b, ensure(best.a)), find(best.a)) end
		local ax, ay = endDir(best, true)
		local bx, by = endDir(best, false)
		local idA, idB = aid(best.a), aid(best.b)
		chosenAt[idA] = chosenAt[idA] or {}
		chosenAt[idB] = chosenAt[idB] or {}
		local la, lb = chosenAt[idA], chosenAt[idB]
		la[#la + 1] = { ax, ay, idB }
		lb[#lb + 1] = { bx, by, idA }
		knotChoose(best)
		hk.choose(best)
		budget = budget - info[best.key].need
		local nd = newDepth(best) or 0
		depthOf[best.key] = newDepth(best)
		report.maxDepth = math.max(report.maxDepth or 0, nd)
		local da, db = depth[best.a], depth[best.b]
		reach(best.a, da or nd)
		reach(best.b, db or nd)
		-- a loop closed through a deeper end makes both ends as shallow as the shallower one + 1
		if da and db then
			local m = math.min(da, db) + 1
			if da > m then depth[best.a] = m end
			if db > m then depth[best.b] = m end
		end
	end
	report.tips = 0
	-- (hang fix 2026-10-13: a hard cap on the rounds of the greedy loop, and the driver's plan slice may end between them)
	local iter, maxIter = 0, maxEdges * M.ITER_PER_EDGE + M.ITER_BASE
	local yieldFn = opts.yield
	while budget > 0 do
		iter = iter + 1
		if iter > maxIter then
			report.iterCap = iter - 1
			break
		end
		if yieldFn and iter % 4 == 0 then yieldFn() end
		for _, pc in ipairs(pending) do
			local st = getInfo(pc)
			if st.need and not exclude[pc.key] then open[#open + 1] = pc end
		end
		pending = {}
		local best, bc, bi, bestList = nil, math.huge, nil, nil
		local waitZ, waitL = 0, 0
		indHeldNow = 0
		foHeldNow = 0
		gapHeldNow = 0
		local why = opts.why   -- (debugging: the last reason each open piece waited)
		for i, pc in ipairs(open) do
			local st = info[pc.key]
			if why and not inSet[pc.key] then
				why[pc.key] = (st.need > budget and "budget") or (not frontOk(pc) and "front") or (not leadOk(pc) and "lead")
					or (not jointOk(pc) and "joint") or (not loopOk(pc) and "loop") or (zzOn and zigzag(pc) and "zigzag")
					or (withTips(pc) == nil and "tips") or "cost"
			end
			local rj = not inSet[pc.key] and st.need <= budget and isRakeJoin(pc)
			if not inSet[pc.key] and st.need <= budget and (rj or leadOk(pc)) and jointOk(pc) and indOk(pc) and forestOk(pc) and gapOk(pc)
				and branchOk(pc) and rakeOk(pc) and wiggleOk(pc) and knotOk(pc) then
				local c = st.cost
				if reached[pc.a] and reached[pc.b] then c = c * M.LOOP_BONUS
				elseif smoothOn then c = c * bend(pc) end
				if rj then c = c * M.RAKE_JOIN_K end
				if c < bc or (c == bc and best and pc.key < best.key) then
					if not rj and (not loopOk(pc) or not emptyLoopOk(pc)) then waitL = waitL + 1
					elseif zzOn and zigzag(pc) then waitZ = waitZ + 1
					else
						-- (a forest lane's crossing comes whole: laneBundle)
						local lb = laneBundles[pc.key]
						local list = lb and lb.list or withTips(pc)
						local need, cl = 0, c
						for _, x in ipairs(list or {}) do
							need = need + info[x.key].need
							-- (the pieces chosen with it: the dearest of them sets the order)
							if x ~= pc and not x.motifBranch and info[x.key].cost > cl then cl = info[x.key].cost end
						end
						if list and need <= budget and (cl < bc or (cl == bc and best and pc.key < best.key)) then
							best, bc, bi, bestList = pc, cl, i, list
						end
					end
				end
			end
		end
		if indHeldNow > report.indHeld then report.indHeld = indHeldNow end
		if foHeldNow > report.forestHeld then report.forestHeld = foHeldNow end
		if gapHeldNow > report.gapHeld then report.gapHeld = gapHeldNow end
		if best == nil and indLevel and IND.HOLD_FIRST and indHeldNow > 0 and maxEdges - budget < maxEdges * IND.HOLD_FILL then
			indRelax()
		elseif best == nil and housedIdx and maxEdges - budget < maxEdges * M.ENV_MIN_FILL
			and housedExtra < M.HOUSED_RELAX * blkMax - 1e-6 and report.housedHeld > 0 then
			-- the housed front would leave the increment under-filled: half a block more, at most HOUSED_RELAX blocks
			housedExtra = math.min(M.HOUSED_RELAX * blkMax, housedExtra + 0.5 * blkMax)
			report.housedRelax = housedExtra
		elseif best == nil and (envCap or cache.armFront) and maxEdges - budget < maxEdges * M.ENV_MIN_FILL
			and relax < M.ENV_RELAX then
			-- the shape's limits would leave the increment under-filled (a style whose plan has few pieces inside
			-- the envelope: EU organic's ring arcs cross the arms): widen them a step and look again; the shape
			-- still decides the order (cost) and the relaxation counts in the report
			relax = relax + 1
			if strongArms then
				fillExtra = math.min(M.ARM_FILL_RELAX * blkMax, fillExtra + 0.5 * blkMax)
				-- (nothing at all within the envelope yet, e.g. a young core whose dead ends lie at its rim: widen it until
				-- the first piece fits, then no further)
				if envCap and #chosen == 0 then envCap = envCap * M.ENV_RELAX_F end
			elseif envCap then envCap = envCap * M.ENV_RELAX_F end
			armExtra = armExtra + math.max(style.block.len, style.block.depth)
			report.envRelax = relax
		elseif best == nil and foLevel and foLevel < 1.01 and foHeldNow > 0 and maxEdges - budget < maxEdges * FO.k(foInfo, "HOLD_FILL") then
			-- (forest-hugging towns: nothing else fits, the least wooded of the held pieces may come now)
			forestRelax()
		elseif best == nil and indLevel and indHeldNow > 0 and maxEdges - budget < maxEdges * IND.HOLD_FILL then
			-- (away from industries: nothing else fits, the held pieces near the works may come now)
			indRelax()
		elseif best == nil and sparseIdx and not sparseRelaxed and report.sparseHeld > 0
			and maxEdges - budget < M.SPARSE_RELAX_EDGES then
			-- (2026-10-15 §59, showcase run 2026-10-15_0234 EU organic: from its 4th forced step every frontier piece sat
			-- among sparse streets, the plans came out empty and the town stopped while its houses kept coming: the
			-- dead ends of a growing town are on its newest, emptiest streets. Last of the relaxations: the held pieces
			-- may come, the cheapest first, up to SPARSE_RELAX_EDGES edges in all; the lead limit still holds.)
			sparseRelaxed = true
			budget = math.min(budget, M.SPARSE_RELAX_EDGES - (maxEdges - budget))
			report.sparseRelax = true
		elseif best == nil and #chosen == 0 and ((rakeOn and not rakeRelaxed and report.rakeHeld > 0)
			or (wiggleOn and not wiggleRelaxed and report.wiggleHeld > 0)) then
			-- (§69: the rake / wiggle holds would leave the increment empty: they give way, last)
			rakeRelaxed, wiggleRelaxed = true, true
			report.lookRelax = true
		elseif best == nil and #chosen == 0 and knotOn and not knotRelaxed and report.knotHeld > 0 then
			-- (§70: the knot holds would leave the increment empty: they give way, after the rake / wiggle ones)
			knotRelaxed = true
			report.knotRelax = true
		elseif best == nil and #chosen == 0 and frontCap and report.frontHeld > 0 and frontRelax < frontRelaxMax then
			-- (a stuck town, opts.limits.frontRelax: the front would leave the increment empty, one block wider per step)
			frontRelax = frontRelax + 1
			frontCap = frontCap + blkMax
			report.frontRelax, report.frontCap = frontRelax, frontCap
		elseif best == nil then
			report.zigzagWait, report.loopWait = report.zigzagWait + waitZ, report.loopWait + waitL
			break
		end
		if best ~= nil then
			if isRakeJoin(best) then report.rakeJoin = report.rakeJoin + 1 end
			table.remove(open, bi)
			local lb = laneBundles[best.key]
			if lb then for key in pairs(lb.wooded) do laneFreed[key] = true end end
			for _, x in ipairs(bestList) do
				if x ~= best then report.tips = report.tips + 1 end
				choose(x)
			end
		end
	end
	-- §71 hooks: a chosen piece whose far end is a dead end (no other chosen piece and no town street there) and whose
	-- dead-end street curls (hk.why) is left out, again until none is left (pruning one may leave the piece before it as
	-- a curled dead end; at most #chosen rounds); kept when that would empty the increment (hookRelax). Then the select
	-- runs once more without them (opts.hookPass), so the budget they took goes to other pieces.
	if hk.on and #chosen > 0 then
		local drop, why = {}, {}
		local cnt = {}
		for _, pc in ipairs(chosen) do
			cnt[pc.a] = (cnt[pc.a] or 0) + 1
			cnt[pc.b] = (cnt[pc.b] or 0) + 1
		end
		local function open(k)
			local n = jnode[k]
			return cnt[k] == 1 and (n == nil or OG.degree(g, n) == 0)
		end
		local nDrop = 0
		for _ = 1, #chosen do
			local any = false
			for _, pc in ipairs(chosen) do
				if not drop[pc.key] then
					local oa, ob = open(pc.a), open(pc.b)
					local w = nil
					if ob and not oa then w = hk.why(pc, pc.a) elseif oa and not ob then w = hk.why(pc, pc.b) end
					if w then
						drop[pc.key], why[pc.key] = true, w
						nDrop = nDrop + 1
						any = true
						cnt[pc.a], cnt[pc.b] = cnt[pc.a] - 1, cnt[pc.b] - 1
						hk.drop(pc)
					end
				end
			end
			if not any then break end
		end
		if nDrop > 0 and nDrop >= #chosen then
			report.hookRelax = true
		elseif nDrop > 0 then
			local kept = {}
			for _, pc in ipairs(chosen) do
				if drop[pc.key] then
					report.hookHeld = report.hookHeld + 1
					report.hookWhy[why[pc.key]] = (report.hookWhy[why[pc.key]] or 0) + 1
				else kept[#kept + 1] = pc end
			end
			chosen = kept
			if not opts.hookPass then
				local o = {}
				for k, v in pairs(opts) do o[k] = v end
				local ex = {}
				for k, v in pairs(exclude) do ex[k] = v end
				for k in pairs(drop) do ex[k] = true end
				o.exclude, o.hookPass = ex, true
				local st2, rep2 = M.select(g, mp, style, o)
				if #st2 >= #chosen then
					rep2.hookHeld = (rep2.hookHeld or 0) + report.hookHeld
					for k, v in pairs(report.hookWhy) do rep2.hookWhy[k] = (rep2.hookWhy[k] or 0) + v end
					rep2.hookPass = true
					return st2, rep2
				end
			end
		end
	end
	-- dangling L legs: a small piece chosen two pieces out (depth >= 2) whose far end nothing else uses is the
	-- second leg of an L at the frontier (the saw-tooth); left out unless that empties the increment
	if smoothOn and M.L_PRUNE and #chosen > 1 then
		local count = {}
		for _, pc in ipairs(chosen) do
			count[pc.a] = (count[pc.a] or 0) + 1
			count[pc.b] = (count[pc.b] or 0) + 1
		end
		local kept, legs = {}, 0
		for _, pc in ipairs(chosen) do
			local dangling = (count[pc.a] == 1 and not jnode[pc.a]) or (count[pc.b] == 1 and not jnode[pc.b])
			if pc.class == "small" and not pc.connector and not pc.culDeSac and (depthOf[pc.key] or 0) >= 2 and dangling then
				legs = legs + 1
			else
				kept[#kept + 1] = pc
			end
		end
		if legs > 0 and #kept > 0 then chosen = kept end
		report.legs = legs
	end
	local prune = opts.prune
	if prune == nil then prune = style.grower ~= "organic" end   -- organic towns grow through their lanes
	if prune then
		-- keep the stubs when they are all there is (steep or crowded sides grow through small streets only)
		local kept = {}
		for i, pc in ipairs(chosen) do kept[i] = pc end
		report.pruned = M.prune(kept, jnode)
		if #kept > 0 then chosen = kept else report.pruned = 0 end
	end
	report.selected = #chosen
	if #chosen == 0 and #g.edges > 0 and not opts.connRelax and M.CONN_RULES then
		local o = {}
		for k, v in pairs(opts) do o[k] = v end
		o.connRelax = true
		local st2, rep2 = M.select(g, mp, style, o)
		if #st2 > 0 then
			rep2.connRelax = true
			return st2, rep2
		end
	end
	for _, st in pairs(info) do
		if st.built then report.built = report.built + 1
		elseif st.blocked then report.blocked = report.blocked + 1
		elseif st.excluded then report.excluded = report.excluded + 1 end
	end

	local streets = {}
	for _, pc in ipairs(chosen) do
		local pts = {}
		for i, p in ipairs(pc.pts) do pts[i] = { p[1], p[2], p[3], p[4] } end
		streets[#streets + 1] = { pts = pts, class = pc.class, curved = pc.curved, smooth = pc.smooth,
			dirA = pc.dirA, dirB = pc.dirB, startNode = jnode[pc.a], endNode = jnode[pc.b], key = pc.key,
			through = M.through(mp, pc) and not info[pc.key].ahead, origin = M.origin(pc),
			sideFree = (pc.motif ~= nil and M.SIDE_FREE[pc.motif]) or nil }
	end
	report.info = info
	-- (the held pieces let through as forest lanes and chosen: ot_lane.mark's `freed`)
	local lf, nlf = {}, 0
	for _, pc in ipairs(chosen) do
		if laneFreed[pc.key] then lf[pc.key] = true; nlf = nlf + 1 end
	end
	report.laneFree, report.laneFreed = lf, nlf
	return streets, report
end

return M
