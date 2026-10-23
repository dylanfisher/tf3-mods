-- Organic Towns: pure entry point for one town increment: StyleParams + snapshot graph (+ terrain sampler)
-- -> grower (grid / organic) -> selection -> ot_plan node/edge specs. The engine layer (Phase 3) turns the
-- result into a SimpleProposal; tests and the SVG preview apply it to the graph instead.

local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local P = ug_require "square_organic_towns::/organic_towns/ot_plan.lua"
local GRID = ug_require "square_organic_towns::/organic_towns/ot_grow_grid.lua"
local ORG = ug_require "square_organic_towns::/organic_towns/ot_grow_organic.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local MT = ug_require "square_organic_towns::/organic_towns/ot_metrics.lua"
local SEL = ug_require "square_organic_towns::/organic_towns/ot_select.lua"
local MO = ug_require "square_organic_towns::/organic_towns/ot_motif.lua"
local SHF = ug_require "square_organic_towns::/organic_towns/ot_shore.lua"
local WG = ug_require "square_organic_towns::/organic_towns/ot_wedge.lua"
local MD = ug_require "square_organic_towns::/organic_towns/ot_meadow.lua"
local PO = ug_require "square_organic_towns::/organic_towns/ot_poly.lua"
local NM = ug_require "square_organic_towns::/organic_towns/ot_nearmiss.lua"
local CK = ug_require "square_organic_towns::/organic_towns/ot_check.lua"

local M = {}

M.MAX_EDGES = 24        -- PLAN.md 2.3 step 4
M.MAX_SEG_FLAT = 100    -- longest edge piece on flat ground (m)
M.MAX_SEG_SLOPE = 40    -- on slopes (PLAN.md 2.3 step 6)
M.SLOPE_SPLIT = 0.04    -- mean slope above which pieces are short
M.ROUNDS = 4            -- select/plan rounds per increment
M.ENV_WIDE_MIN = 3   -- strong-arm shapes: an increment below this many edges is planned once more with the envelope free
M.EMPTY_MIN_EDGES = 6   -- empty budget (style.emptyBudget): the smallest increment it leaves
M.EMPTY_EDGE_M = 70     -- ... counting this many metres per edge
M.ROUNDS_EMPTY = 10     -- ... while the result is still empty (young towns: the planner refuses the first pieces at
                        -- a small core one after another, 2026-10-12)
M.OWN_EMPTY_BASE = 1500 -- own empty budget (opts.ownEmpty): m of the mod's own unhoused streets allowed ...
M.OWN_EMPTY_SHARE = 0.08 -- ... + this x the town's street length
M.OWN_EMPTY_MIN = 4     -- ... and no increment below this many edges of room
M.OWN_EMPTY_TIGHT = 900 -- ... base for a town with retired empty dead ends (R4 2026-10-13: unhoused stubs and loops in
                        -- Kirkham, Fleetwood, Syston, Ormskirk; the driver passes opts.ownEmptyBase)

--- The grower module for a style.
function M.grower(style)
	if style.grower == "organic" then return ORG end
	return GRID
end

-- Master plans per style table (weak keys): reused while they cover the extent the town needs (plans are
-- prefix-stable, so a larger one contains the smaller one's pieces) and, for grids, the anchoring holds.
local planCache = setmetatable({}, { __mode = "k" })
M.PLAN_MARGIN = 400   -- a cached plan is built this much (or half the needed extent) larger than needed
M.MAX_EXTENT = 6000   -- m: the master plan's extent at most (hang guard; a real town needs ~1-3 km)
M.REANCHOR_EDGES = 12 -- a plan whose motif line has no anchor yet is rebuilt after this many more streets

--- The town's master plan, from the cache when it still fits.
function M.masterPlan(g, style, opts, snapR)
	local grower = M.grower(style)
	local need = grower.extentFor(g, style)
	if opts.yield then opts.yield() end
	-- (hang guard 2026-10-13: a far stray node (a country road, the town network) or a NaN never makes an endless plan)
	if not (need > 0) then need = 600 end
	need = math.min(need, M.MAX_EXTENT)
	local c = planCache[style]
	if c and c.extent >= need and c.terrain == opts.terrain then
		local stillFits = true
		-- (a motif line that found no dead end of the town to start from, ot_motif_land anchors: planned again once the
		-- town has REANCHOR_EDGES more streets)
		if c.mp.motifReanchor and #g.edges >= (c.edges or 0) + M.REANCHOR_EDGES then stillFits = false end
		-- (... and when the dead end a motif line starts from was built on: the line continues from the new tip)
		for _, id in ipairs(c.mp.motifAnchorIds or {}) do
			if g.nodeById[id] == nil or OG.degree(g, id) ~= 1 then stillFits = false; break end
		end
		-- (... and when the town's rail stations changed, M3 station quarter: ot_driver refreshes style.stationKey)
		if (c.mp.stationKey or "") ~= (style.stationKey or "") then stillFits = false end
		-- (... and when the town's bridge record changed, M4 bridgehead quarter: ot_driver.bridgeRefresh)
		if (c.mp.bridgeKey or "") ~= (style.bridgeKey or "") then stillFits = false end
		-- (... and when the skeleton's arms changed, §63 ot_skeleton: the deep arms' spokes follow them)
		if (c.mp.skelKey or "") ~= (style.skelKey or "") then stillFits = false end
		if grower == GRID and #g.nodes > 0 and not c.mp.anchored then stillFits = GRID.matchShare(g, c.mp, snapR, opts.yield) >= 0.5 end
		if stillFits then return c.mp end
	end
	local extent = math.min(need + math.max(M.PLAN_MARGIN, need * 0.5), M.MAX_EXTENT + M.PLAN_MARGIN)
	-- (2026-10-13 final test: a plan rebuilt with its motifs took up to ~150 ms in one tick, PLAN us=431633 slices=3:
	-- the driver's slice may now end between the plan's parts too)
	local yield = opts.yield or function() end
	local mp = grower.planFor(g, style, { terrain = opts.terrain, stats = opts.stats, snapR = snapR, extent = extent,
		yield = opts.yield })
	yield()
	-- motifs (ot_motif, M0): their candidate pieces. The crescents around a green (Showcase v9 round, migrated to the
	-- motif registry unchanged): the plan cut at the crescent meadows, arcs around them (with the green reserves:
	-- ot_select.GREEN, off in most offline tests)
	MO.applyPlan(mp, style, { green = SEL.GREEN, extent = extent, terrain = opts.terrain, g = g, yield = yield })
	-- waterfront streets (shore towns, 2026-10-12): a promenade along the traced shore, a row of small blocks behind it
	if style.shoreFront then yield(); SHF.apply(mp, style, extent, opts.terrain) end
	-- polycentric metropolis (ot_poly, later-ideas phase): the grid cores of its secondary centres
	if style.metro and style.metro.variant == "polycentric" then PO.applyPlan(mp, style, { g = g, terrain = opts.terrain, extent = extent }) end
	mp.stationKey = style.stationKey
	mp.bridgeKey = style.bridgeKey
	mp.skelKey = style.skelKey
	planCache[style] = { extent = extent, mp = mp, terrain = opts.terrain, edges = #g.edges }
	return mp
end

local C = ug_require "square_organic_towns::/organic_towns/ot_check.lua"

--- Street hierarchy (NEXT_PHASE_BRIEF 9): wide streets only on through routes, never on dead-end stubs. Every new
--- edge planned with a template wider than the style's local (small) one keeps it only when
---   * its plan piece is a through piece (ot_select.through: the line continues at both ends), and
---   * its piece meets another street somewhere along it in the built result (a node with 3+ streets): a bare
---     arterial spur out in the field stays local width, also when it continues a wide street;
--- else it gets the local template. A wide edge joining an existing dead end whose street is narrower is marked
--- `wideJoin` (ot_proposal: the joint edge takes the wide template instead of copying the dead end's). Sets
--- inc.hier = { wide, stub, bare } (edge counts) and returns it.
function M.hierarchy(g, inc, style)
	local small = style.templatePaths and style.templatePaths.small
	local h = { wide = 0, stub = 0, bare = 0, bent = 0, bentEdges = 0, maxDefl = { large = 0, medium = 0 } }
	inc.hier = h
	if small == nil then return h end
	local w0 = C.halfWidth("small", small)
	local function wide(t) return t ~= nil and C.halfWidth(nil, t) > w0 end
	local deg = {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if deg[n] == nil then deg[n] = (n > 0 and OG.degree(g, n) or 0) end
			deg[n] = deg[n] + 1
		end
	end
	local function existingWide(n)
		if n <= 0 then return false end
		for _, id in ipairs(g.adj[n] or {}) do
			if wide(g.edgeById[id].template) then return true end
		end
		return false
	end
	local groups, order = {}, {}
	for _, e in ipairs(inc.edges) do
		if wide(e.template) then
			if not e.through then
				e.template = small
				h.stub = h.stub + 1
			else
				local k = e.key or ("edge" .. e.entity)
				if groups[k] == nil then groups[k] = {}; order[#order + 1] = k end
				local l = groups[k]
				l[#l + 1] = e
			end
		end
	end
	local kept = {}
	for _, k in ipairs(order) do
		local ok = false
		for _, e in ipairs(groups[k]) do
			for _, n in ipairs({ e.node0, e.node1 }) do
				if (deg[n] or 0) >= 3 then ok = true end
			end
		end
		for _, e in ipairs(groups[k]) do
			if ok then
				kept[#kept + 1] = e
			else
				e.template = small
				h.bare = h.bare + 1
			end
		end
	end
	-- straight wide streets: a wide piece that bends too much gets a narrower template (M.straightWide)
	M.straightWide(inc, kept, small, h)
	-- (§73) medium / large only as long, continuous, anchored runs (M.continuity)
	M.continuity(g, inc, style, h)
	for _, e in ipairs(kept) do
		if wide(e.template) then
			h.wide = h.wide + 1
			for _, n in ipairs({ e.node0, e.node1 }) do
				if n > 0 and not existingWide(n) then e.wideJoin = true end
			end
		end
	end
	return h
end

-- Straight wide streets (2026-10-12, user: "a rule to avoid curvature in wide roads. Medium or large (especially
-- large) will mostly be in longer straight lines for thoroughfares"). Limits on a wide piece (its plan piece's
-- edges): the deflection of each edge (angle between its end tangents, edges are <= 100 m) and at each joint where
-- two of its edges, or two wide pieces of the same plan line (ot_check.lineOf), continue through a node. Large
-- streets: gentle bends only; medium: modest curves; small / local streets keep their organic curves. A piece over
-- the large limits that fits the medium ones is built medium, else small (never a sharp-bending wide street).
M.STRAIGHT_RULE = true
M.STRAIGHT_LIMITS = { large = { edge = 10, joint = 12 }, medium = { edge = 25, joint = 30 } }

local function tdeg(ax, ay, bx, by)
	local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
	if la < 1e-9 or lb < 1e-9 then return 0 end
	local c = (ax * bx + ay * by) / (la * lb)
	return math.deg(math.acos(math.max(-1, math.min(1, c))))
end

--- Deflection (deg) of an edge: the angle between its tangents at both ends (0 for a straight edge).
function M.edgeDeflection(e)
	if e.t0 == nil and (e.p0 == nil or e.p1 == nil) then return 0 end
	local t0 = e.t0 or { e.p1[1] - e.p0[1], e.p1[2] - e.p0[2] }
	local t1 = e.t1 or t0
	return tdeg(t0[1], t0[2], t1[1], t1[2])
end

--- Deflection (deg) where edge a and edge b meet at node n, travelling through it (a into n, b out of n).
function M.jointDeflection(a, b, n)
	local function dirAt(e, node, leaving)
		if e.t0 == nil and (e.p0 == nil or e.p1 == nil) then return 0, 0 end
		local t
		if e.node0 == node then t = e.t0 or { e.p1[1] - e.p0[1], e.p1[2] - e.p0[2] }
			return leaving and t[1] or -t[1], leaving and t[2] or -t[2]
		end
		t = e.t1 or { e.p1[1] - e.p0[1], e.p1[2] - e.p0[2] }
		return leaving and -t[1] or t[1], leaving and -t[2] or t[2]
	end
	local ax, ay = dirAt(a, n, false)   -- direction arriving at n
	local bx, by = dirAt(b, n, true)    -- direction leaving n
	return tdeg(ax, ay, bx, by)
end

local function sizeOf(template)
	return type(template) == "string" and template:match("town_%a+_(%a+)%.street_template$") or nil
end

--- Applies the straight-wide rule to the wide edges `list` of inc (in place: templates narrowed). small = the
--- style's local template. Adds h.bent (pieces narrowed), h.bentEdges and h.maxDefl = { large, medium } (largest
--- deflection, edge or joint, of the wide pieces kept; deg). Returns h.
function M.straightWide(inc, list, small, h)
	h = h or {}
	h.bent, h.bentEdges, h.maxDefl = h.bent or 0, h.bentEdges or 0, h.maxDefl or { large = 0, medium = 0 }
	if not M.STRAIGHT_RULE or #list == 0 then return h end
	local groups, order = {}, {}
	for _, e in ipairs(list) do
		local k = e.key or ("edge" .. tostring(e.entity))
		if groups[k] == nil then groups[k] = { edges = {}, defl = 0 }; order[#order + 1] = k end
		local gr = groups[k]
		gr.edges[#gr.edges + 1] = e
		gr.defl = math.max(gr.defl, M.edgeDeflection(e))
	end
	-- joints: two wide edges of one piece, or of one plan line, meeting at a node with exactly those two going on
	local at = {}
	for _, e in ipairs(list) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			at[n] = at[n] or {}
			local l = at[n]
			l[#l + 1] = e
		end
	end
	for n, l in pairs(at) do
		for i = 1, #l do
			for j = i + 1, #l do
				local a, b = l[i], l[j]
				local la, lb = C.lineOf(a.key), C.lineOf(b.key)
				if a.key == b.key or (la ~= nil and la == lb) then
					local d = M.jointDeflection(a, b, n)
					-- (a joint of more than 90 deg is two streets meeting, not one going on)
					if d <= 90 then
						for _, e in ipairs({ a, b }) do
							local gr = groups[e.key or ("edge" .. tostring(e.entity))]
							gr.joint = math.max(gr.joint or 0, d)
						end
					end
				end
			end
		end
	end
	local L, Mm = M.STRAIGHT_LIMITS.large, M.STRAIGHT_LIMITS.medium
	for _, k in ipairs(order) do
		local gr = groups[k]
		local size = sizeOf(gr.edges[1].template)
		local de, dj = gr.defl, gr.joint or 0
		local to = nil
		if size == "large" and (de > L.edge or dj > L.joint) then
			if de <= Mm.edge and dj <= Mm.joint then to = "medium" else to = "small" end
		elseif size == "medium" and (de > Mm.edge or dj > Mm.joint) then
			to = "small"
		end
		if to then
			h.bent = h.bent + 1
			for _, e in ipairs(gr.edges) do
				h.bentEdges = h.bentEdges + 1
				if to == "small" then e.template = small
				else e.template = e.template:gsub("_large%.street_template$", "_medium.street_template") end
			end
			size = sizeOf(gr.edges[1].template)
		end
		if size == "large" or size == "medium" then
			if math.max(de, dj) > h.maxDefl[size] then h.maxDefl[size] = math.max(de, dj) end
		end
	end
	return h
end

--- "wide/stub/bare/bent/short" and the kept wide pieces' largest deflection "L/M" (deg) for the PLAN line.
function M.hierText(h)
	if h == nil then return "-" end
	local md = h.maxDefl or { large = 0, medium = 0 }
	return string.format("wide%d/stub%d/bare%d/bent%d/short%d", h.wide or 0, h.stub or 0, h.bare or 0, h.bent or 0,
		h.short or 0), string.format("%.0f/%.0f", md.large or 0, md.medium or 0)
end

---------------------------------------------------------------------------
-- Continuous thoroughfares (§73, 2026-10-17; user: "early on (~1909) medium streets get built in weird configurations
-- (like just a single track in-between small streets) and causes the car path finding to go in weird roundabouts. The
-- whole point of the larger streets is intentional thoroughfares"). The hierarchy above keeps a wide piece when its
-- plan line goes on at both ends and it meets a street: one block of a planned main line, built while the rest of
-- the line was not (and maybe never is), was a lone medium edge between small streets. Now medium / large edges
-- are kept only as runs: the connected set of medium / large edges (the town's existing ones and the increment's
-- new ones) an increment's wide edges belong to must
--   * be at least RUN_MIN_M long (300 m: three of our <= 100 m edges, five EU-organic blocks, 1.5 NA blocks; a cut,
--     orphaned or one-block run is shorter), and
--   * reach a meaningful place: an existing medium / large street (it continues or crosses one), a country road
--     (the town's exit), the town centre or a rail station (a node within RUN_ANCHOR_M). The late street hierarchy
--     (style.hierarchy "late": the sprawling styles from 1950 and the metropolis, whose arterial lattice is planned
--     as such) also counts the town itself: a run that sets off from an existing street node.
-- Early era (old templates, before 1940): a town of 1900 had one high street, the road through it, and narrow lanes
-- (PLAN.md 6.2 "Continuous thoroughfares"): a new run that doesn't continue an existing one starts only while the
-- town has fewer than RUN_OLD_MAX runs of RUN_MIN_M. Every other new medium / large edge is built at the
-- style's narrower template. The run is judged on what the increment builds at once (a build is one proposal,
-- all or nothing), so a refused or cut run leaves no stub; a run grows on only from an existing run.
M.RUN_RULE = true
M.RUN_MIN_M = 300
M.RUN_ANCHOR_M = 150
M.RUN_OLD_MAX = 1
M.RUN_MAX_EDGES = 20000   -- edges walked per call at most (a capped walk logs nothing: the rest stays as planned)

local SIZE_RANK = { xsmall = 0, small = 1, medium = 2, large = 3 }

--- Size of a town street template ("small", "medium" ...; the `_trees` variant too), else nil.
function M.townSize(t)
	if type(t) ~= "string" then return nil end
	return t:match("town_%a+_(%a+)%.street_template$") or t:match("town_%a+_(%a+)_trees%.street_template$")
end

--- Is an edge (graph or increment) a medium / large street? By template, else by class (main / medium) when it has none.
function M.isWideEdge(e)
	if e == nil or e.forestLane then return false end
	local s = M.townSize(e.template)
	if s then return (SIZE_RANK[s] or 0) >= 2 end
	if e.template ~= nil then return false end
	return e.class == "main" or e.class == "medium"
end

local function isRoadTemplate(t)
	return type(t) == "string" and t ~= "" and t ~= "nil" and t:find("town_", 1, true) == nil
end

--- The narrower template a cut run gets: the style's collector template when it isn't medium / large, else its local one.
function M.narrowTemplate(style)
	local tp = style and style.templatePaths or {}
	local m = tp.medium
	if m and SIZE_RANK[M.townSize(m) or "small"] < 2 then return m end
	return tp.small
end

--- Medium / large runs of graph g plus (optionally) increment inc's wide edges: the connected sets of wide edges (two
--- edges sharing a node are one run). Returns the runs { edges = { {e, new, len} ... }, len, nodes = {id = true},
--- existing = m of existing edges, newN = new edges } and walked (edges looked at; capped at RUN_MAX_EDGES).
function M.wideRuns(g, inc)
	local items, at, walked = {}, {}, 0
	local nodePos = {}
	local function add(e, isNew, len, a, b)
		items[#items + 1] = { e = e, new = isNew, len = len, a = a, b = b }
		for _, n in ipairs({ a, b }) do
			local l = at[n]
			if l == nil then l = {}; at[n] = l end
			l[#l + 1] = #items
		end
	end
	for _, e in ipairs(g and g.edges or {}) do
		walked = walked + 1
		if walked > M.RUN_MAX_EDGES then break end
		if M.isWideEdge(e) then add(e, false, OG.edgeLength(g, e), e.n0, e.n1) end
	end
	if inc then
		for _, nd in ipairs(inc.nodes or {}) do nodePos[nd.entity] = { nd.x, nd.y } end
		for _, e in ipairs(inc.edges or {}) do
			walked = walked + 1
			if walked > M.RUN_MAX_EDGES then break end
			if M.isWideEdge(e) then
				local len = 0
				if e.p0 and e.p1 then len = math.sqrt((e.p1[1] - e.p0[1]) ^ 2 + (e.p1[2] - e.p0[2]) ^ 2) end
				if e.p0 and nodePos[e.node0] == nil then nodePos[e.node0] = { e.p0[1], e.p0[2] } end
				if e.p1 and nodePos[e.node1] == nil then nodePos[e.node1] = { e.p1[1], e.p1[2] } end
				add(e, true, len, e.node0, e.node1)
			end
		end
	end
	local runs, seen = {}, {}
	for i = 1, #items do
		if not seen[i] then
			local run = { edges = {}, len = 0, nodes = {}, existing = 0, newN = 0 }
			local stack, steps = { i }, 0
			seen[i] = true
			-- (each item is pushed once: seen; steps capped at the item count as a guard)
			while #stack > 0 and steps <= #items do
				steps = steps + 1
				local k = table.remove(stack)
				local it = items[k]
				run.edges[#run.edges + 1] = it
				run.len = run.len + it.len
				if it.new then run.newN = run.newN + 1 else run.existing = run.existing + it.len end
				for _, n in ipairs({ it.a, it.b }) do
					run.nodes[n] = true
					for _, j in ipairs(at[n]) do
						if not seen[j] then seen[j] = true; stack[#stack + 1] = j end
					end
				end
			end
			runs[#runs + 1] = run
		end
	end
	return runs, walked, nodePos
end

--- Does run reach a meaningful place (an existing wide street, a country road, the centre, a station; late hierarchy:
--- the town's network)? Returns the anchor kind ("run", "exit", "centre", "station", "town") or nil.
function M.runAnchor(g, run, style, nodePos)
	if run.existing > 0 then return "run" end
	local centre = style and style.centre
	local stations = style and style.stations or {}
	local late = style ~= nil and style.hierarchy == "late"
	local R = M.RUN_ANCHOR_M
	local best = nil
	for n in pairs(run.nodes) do
		local x, y
		local node = g and g.nodeById[n]
		if node then
			x, y = node.x, node.y
			for _, id in ipairs(g.adj[n] or {}) do
				local ed = g.edgeById[id]
				if ed and isRoadTemplate(ed.template) then return "exit" end
			end
			if late and best == nil and #(g.adj[n] or {}) > 0 then best = "town" end
		elseif nodePos and nodePos[n] then
			x, y = nodePos[n][1], nodePos[n][2]
		end
		if x then
			if centre and best == nil and math.sqrt((x - centre[1]) ^ 2 + (y - centre[2]) ^ 2) <= R then best = "centre" end
			if best == nil then
				for _, s in ipairs(stations) do
					local sx, sy = s[1] or s.x, s[2] or s.y
					if sx and sy and math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) <= R then best = "station" break end
				end
			end
		end
	end
	return best
end

--- The continuity rule (above) on increment inc over graph g: new wide edges of a run that is too short, reaches no
--- anchor, or (old era) would be one run too many get the narrower template (M.narrowTemplate); their `wideJoin` is
--- cleared. Idempotent; the driver runs it again after cutting edges (straight guard) and marking forest lanes. Adds
--- h.short (edges narrowed) and h.runs = { kept, cut, maxLen } to h (default inc.hier). Returns h.
function M.continuity(g, inc, style, h)
	h = h or inc.hier or {}
	inc.hier = inc.hier or h
	h.short = h.short or 0
	-- (kept / maxLen describe the last pass, the increment as it goes out; cut adds up over the passes)
	h.runs = { kept = 0, cut = h.runs and h.runs.cut or 0, maxLen = 0 }
	if not M.RUN_RULE or inc == nil then return h end
	local narrow = M.narrowTemplate(style)
	if narrow == nil then return h end
	local runs, _, nodePos = M.wideRuns(g, inc)
	-- existing runs of RUN_MIN_M (old era: the town's high streets)
	local have = 0
	for _, r in ipairs(runs) do
		if r.existing >= M.RUN_MIN_M then have = have + 1 end
	end
	local fresh = {}
	for _, r in ipairs(runs) do
		if r.newN > 0 then fresh[#fresh + 1] = r end
	end
	-- (the longest first: it gets the old era's slot)
	table.sort(fresh, function(a, b)
		if a.len ~= b.len then return a.len > b.len end
		return a.newN > b.newN
	end)
	local old = style and style.newTemplates == false
	for _, r in ipairs(fresh) do
		local anchor = M.runAnchor(g, r, style, nodePos)
		local keep = r.len >= M.RUN_MIN_M and anchor ~= nil
		if keep and old and r.existing < M.RUN_MIN_M then
			if have >= M.RUN_OLD_MAX then keep = false else have = have + 1 end
		end
		if keep then
			h.runs.kept = h.runs.kept + 1
			if r.len > h.runs.maxLen then h.runs.maxLen = r.len end
		else
			h.runs.cut = h.runs.cut + 1
			for _, it in ipairs(r.edges) do
				if it.new then
					it.e.template = narrow
					it.e.wideJoin = nil
					h.short = h.short + 1
				end
			end
		end
	end
	return h
end

--- Audit of the medium / large streets graph g holds (the SNAPSHOT `wideRuns` token): runs, their edges and length,
--- runs shorter than RUN_MIN_M (short), one-edge runs (lone: a single wide edge between narrower streets), the longest,
--- and the wide edges by builder (by(edge) -> "mod" / "game" / other key; optional). Returns the table.
function M.wideAudit(g, by)
	local a = { runs = 0, edges = 0, len = 0, short = 0, lone = 0, max = 0, by = {} }
	local runs = M.wideRuns(g, nil)
	for _, r in ipairs(runs) do
		a.runs = a.runs + 1
		a.edges = a.edges + #r.edges
		a.len = a.len + r.len
		if r.len < M.RUN_MIN_M then a.short = a.short + 1 end
		if #r.edges == 1 then a.lone = a.lone + 1 end
		if r.len > a.max then a.max = r.len end
		for _, it in ipairs(r.edges) do
			local k = by and by(it.e) or "other"
			a.by[k] = (a.by[k] or 0) + 1
		end
	end
	return a
end

--- "runs/edges/len:short<n>,lone<n>,max<m>;mod<n>,game<n>,other<n>" for the audit (or "0" without a wide street).
function M.wideAuditText(a)
	if a == nil then return "-" end
	if a.runs == 0 then return "0" end
	local by = {}
	for _, k in ipairs({ "mod", "game", "other" }) do
		if a.by[k] then by[#by + 1] = k .. a.by[k] end
	end
	for k, n in pairs(a.by) do
		if k ~= "mod" and k ~= "game" and k ~= "other" then by[#by + 1] = k .. n end
	end
	return string.format("%d/%d/%.0f:short%d,lone%d,max%.0f;%s", a.runs, a.edges, a.len, a.short, a.lone, a.max,
		table.concat(by, ","))
end

--- Street mix of an increment (the hierarchy target, PLAN.md 6.2 "Street mix"): new street length (m, chords) by
--- template size: { large, medium, small (xsmall counted here), total }. Edges without a template count by class
--- (main large, medium medium, else small).
local BY_CLASS = { main = "large", medium = "medium" }
function M.mix(inc)
	local m = { large = 0, medium = 0, small = 0, total = 0 }
	for _, e in ipairs(inc.edges or {}) do
		local size = e.template and e.template:match("town_%a+_(%a+)%.street_template$") or BY_CLASS[e.class] or "small"
		if m[size] == nil or size == "total" then size = "small" end
		local l = 0
		if e.p0 and e.p1 then l = math.sqrt((e.p1[1] - e.p0[1]) ^ 2 + (e.p1[2] - e.p0[2]) ^ 2) end
		m[size] = m[size] + l
		m.total = m.total + l
	end
	return m
end

--- Adds mix b into accumulator a (in place; a may be nil). Returns a.
function M.addMix(a, b)
	a = a or { large = 0, medium = 0, small = 0, total = 0 }
	for _, k in ipairs({ "large", "medium", "small", "total" }) do a[k] = a[k] + (b and b[k] or 0) end
	return a
end

--- "L/M/S" percentages of a mix ("-" when empty), e.g. "18/27/55".
function M.mixText(m)
	if m == nil or m.total <= 0 then return "-" end
	local function pc(v) return math.floor(100 * v / m.total + 0.5) end
	return string.format("%d/%d/%d", pc(m.large), pc(m.medium), pc(m.small))
end

--- Joint kinks the increment would make (ot_select.JOINT_TURN; Showcase v4 DIAGJOINT): an existing dead end
--- left with exactly one new street that turns more than JOINT_TURN off the dead end's street (a right-angle kink
--- at a 2-street node: Construction Not Possible in game). Returns the piece keys of those new edges (sorted).
function M.jointIssues(g, inc)
	local at = {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n > 0 then
				at[n] = at[n] or {}
				local l = at[n]
				l[#l + 1] = e
			end
		end
	end
	local keys, seen = {}, {}
	for n, list in pairs(at) do
		if #list == 1 and g.nodeById[n] and OG.degree(g, n) == 1 then
			local e = list[1]
			local old = g.edgeById[g.adj[n][1]]
			local ho = OG.headingFrom(g, old, n)
			local dx, dy
			if e.node0 == n then
				if e.t0 then dx, dy = e.t0[1], e.t0[2] else dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2] end
			else
				if e.t1 then dx, dy = -e.t1[1], -e.t1[2] else dx, dy = e.p0[1] - e.p1[1], e.p0[2] - e.p1[2] end
			end
			local l = math.sqrt(dx * dx + dy * dy)
			if l > 0 then
				local c = -(dx * math.cos(ho) + dy * math.sin(ho)) / l
				local t = math.acos(math.max(-1, math.min(1, c)))
				if t > SEL.JOINT_TURN and e.key and not seen[e.key] then
					seen[e.key] = true
					keys[#keys + 1] = e.key
				end
			end
		end
	end
	table.sort(keys)
	return keys
end

M.LOOK_CHECK = true   -- post-plan look check (zig-zags / lassos the increment would make); tests turn it off

--- Look problems the increment `inc` would add to graph g (ot_select look rules, measured on the built result:
--- the planner may drop a piece the selector counted on): { zigzags = n, lassos = n, keys = { piece keys to
--- leave out: the newest new edge of each problem } }. Lassos only once the town has a loop (core); a loop with a
--- node within hugR m of an existing street hugs the town (ot_select.HUG) and is not one. yield: nil or the plan
--- slice's yield, called between the parts (2026-10-21); before: nil or OG.structure(g) already made (ot_select's
--- cache.structure: the same graph, the same structure).
function M.lookIssues(g, inc, hugR, yield, before)
	local out = { zigzags = 0, lassos = 0, keys = {} }
	if #inc.edges == 0 then return out end
	yield = yield or function() end
	local c = OG.overlay(g, inc)
	yield()
	local seen = {}
	local function blame(ids)
		local best = nil
		for _, id in ipairs(ids) do
			local e = c.edgeById[id]
			if e and e.new and (best == nil or e.id < best.id) then best = e end   -- entities -1, -2 ...: lowest = newest
		end
		if best and best.key and not seen[best.key] then
			seen[best.key] = true
			out.keys[#out.keys + 1] = best.key
		end
		return best ~= nil
	end
	for _, z in ipairs(MT.zigzagList(c)) do
		if blame(z) then out.zigzags = out.zigzags + 1 end
	end
	yield()
	if #g.edges > 0 then
		before = before or OG.structure(g)
		yield()
		local function notBridge(e) return not before.bridges[e.id] end
		if before.core then
			local st = OG.structure(c)
			yield()
			local ids = {}
			for id in pairs(st.parts) do ids[#ids + 1] = id end
			table.sort(ids)
			for ip, id in ipairs(ids) do
				if ip % 8 == 0 then yield() end
				local part = st.parts[id]
				if part.cycle and id ~= st.core then
					local hugs = false
					-- a loop through a node of the old network starts right there (a block patch at a dead end)
					for _, eid in ipairs(part.edgeIds or {}) do
						local e = c.edgeById[eid]
						if e.n0 > 0 or e.n1 > 0 then hugs = true break end
					end
					if not hugs and hugR and hugR > 0 then
						for _, eid in ipairs(part.edgeIds or {}) do
							local e = c.edgeById[eid]
							for _, nid in ipairs({ e.n0, e.n1 }) do
								local n = c.nodeById[nid]
								if nid < 0 and n and OG.distToEdgesWhere(g, n.x, n.y, hugR, notBridge) then hugs = true end
							end
							if hugs then break end
						end
					end
					if not hugs and blame(part.edgeIds or {}) then out.lassos = out.lassos + 1 end
				end
			end
		end
	end
	table.sort(out.keys)
	return out
end

--- Plans one increment. opts = { terrain = sampler, stats = ot_terrain.stats, maxEdges, join, bucket, yield,
--- jointRule (no sharp turns at existing dead ends, ot_select.JOINT_RULE; default off), wideReach = false,
--- exclude = { [piece key] = true } (pieces to leave out, e.g. refused by the engine's pre-check) }.
--- Returns increment (ot_plan), select report, master plan.
function M.planIncrement(g, style, opts)
	opts = opts or {}
	-- (green reserves of a plan that ended inside its greenRelax rounds, e.g. the driver's hang guard: back in place)
	if style._greensSaved then style.greens, style._greensSaved = style._greensSaved, nil end
	local stats = opts.stats
	local maxSeg = M.MAX_SEG_FLAT
	if stats and stats.meanSlope > M.SLOPE_SPLIT then maxSeg = M.MAX_SEG_SLOPE end
	local maxEdges = opts.maxEdges or M.MAX_EDGES
	-- empty budget (Showcase v9 round; style.emptyBudget m, polycentric): the town's unhoused street length (snapshot
	-- edges without a building, ot_metrics.emptyLen) plus this increment stays within the budget: fewer edges while
	-- the houses catch up (at least EMPTY_MIN_EDGES, so a forced build still grows)
	local emptyCap = nil
	if style.emptyBudget and SEL.HOUSED and opts.emptyBudget ~= false then
		local el = MT.emptyLen(g)
		if el then
			emptyCap = math.max(M.EMPTY_MIN_EDGES, math.min(maxEdges, math.floor((style.emptyBudget - el) / M.EMPTY_EDGE_M)))
			maxEdges = emptyCap
		end
	end
	-- own empty budget (2026-10-13, real map run 2026-10-13_0232_sqot-dev: 4-17 km of the mod's own streets stood empty in
	-- every town, Grays' south a row of empty loops): the mod's own unhoused street length (opts.ownEmpty(edge): locked
	-- or built this session) stays within OWN_EMPTY_BASE + OWN_EMPTY_SHARE x the town's street length; below
	-- OWN_EMPTY_MIN edges of room the increment is empty (the houses catch up first). Forced builds (opts.force) exempt;
	-- the driver's forced increments pass opts.ownEmptyFloor instead (2026-10-14 §57: at most that many edges then).
	local ownEmptyCap, ownEmpty = nil, nil
	if opts.ownEmpty and SEL.HOUSED and not opts.force and g.hasBuilt then
		local el = MT.emptyLen(g, opts.ownEmpty)
		if el then
			local L = 0
			for _, e in ipairs(g.edges) do L = L + OG.edgeLength(g, e) end
			-- (R4: a town whose own dead ends stayed empty (the driver retired them) gets the tighter base)
			local budget = (opts.ownEmptyBase or M.OWN_EMPTY_BASE) + M.OWN_EMPTY_SHARE * L
			local cap = math.floor((budget - el) / M.EMPTY_EDGE_M)
			ownEmpty = el
			if cap < maxEdges then
				ownEmptyCap = cap >= M.OWN_EMPTY_MIN and cap or 0
				-- (a forced increment, the showcase: a few edges still, near the houses: ot_select SPARSE, lead limits)
				if opts.ownEmptyFloor and ownEmptyCap < opts.ownEmptyFloor then ownEmptyCap = opts.ownEmptyFloor end
				maxEdges = ownEmptyCap
			end
		end
	end
	if maxEdges <= 0 then
		local empty = { nodes = {}, edges = {}, joins = {}, dropped = {}, stats = { edges = 0, nodes = 0, length = 0 },
			style = style.id }
		local rep = { ownEmptyCap = 0, ownEmpty = ownEmpty, emptyCap = emptyCap }
		-- (§74: a town held by its own empty budget still closes its near misses: joins add no frontage ahead of the houses)
		if opts.yield and opts.nearMiss then opts.yield(tonumber(opts.nearMiss.budgetUs) or 0) end
		M.nearMissPass(g, style, empty, rep, opts, M.MAX_SEG_FLAT)
		return empty, rep, nil
	end
	local bucket = opts.bucket or math.floor(#g.edges / 16)
	local snapR = 8
	local minLen = 10
	local exclude, cache = {}, {}
	for k, v in pairs(opts.exclude or {}) do exclude[k] = v end   -- pieces refused in game before (precheck)
	-- motif branches given up (ot_select WAIT_GIVEUP, M4): left out like a refusal
	for k in pairs(style._motifGaveUp or {}) do exclude[k] = true end
	local waitRefused = {}
	local best, bestReport, bestIssues
	-- (2026-10-22: TICKCOST atStep=plan.resume>ot_core:743, 84 ms: the empty budgets and the master plan's extent and
	-- cache check ran before the first yield; a yield here and after the extent splits them, and names the long one)
	if opts.yield then opts.yield() end
	local mp = M.masterPlan(g, style, opts, snapR)
	-- opts.yield (the driver's coroutine slice, ot_driver.PLAN_SLICE_US): may suspend between the steps
	local yield = opts.yield or function() end
	yield()
	-- the planner may refuse pieces the selector picked (angles, crossings among new pieces, snapping);
	-- refused pieces are excluded and the selection rerun, up to M.ROUNDS times; the fullest result wins
	-- (opts.envScale0, §65: a stalled town's plan starts with the envelope this much wider, ot_driver STALL_ENV_SCALE)
	local envScale0 = math.max(1, tonumber(opts.envScale0) or 1)
	local envScale = envScale0
	local connRelax = nil
	local envWide = nil
	-- (§75: a steer town's side streets leave a junction at 60-120 deg, ot_select SIDE / ot_check.LIMITS.sideAngle;
	-- organic growers only, SEL.SIDE_GRID)
	local sideAngle = (opts.limits and opts.limits.steer == true and SEL.SIDE
		and (SEL.SIDE_GRID or style.grower == "organic")) and CK.LIMITS.sideAngle or 0
	local function rounds()
	for round = 1, M.ROUNDS_EMPTY do
		if round > M.ROUNDS and #best.edges > 0 then break end
		local streets, _, report = M.grower(style).grow(g, style, {
			terrain = opts.terrain, stats = stats, maxEdges = maxEdges, maxSeg = maxSeg, minLen = minLen,
			snapR = snapR, incSeed = rng.hash(style.seed or 1, "inc", bucket), exclude = exclude, cache = cache,
			mp = mp, join = opts.join or "deadEnd", envScale = envScale, connRelax = connRelax, envWide = envWide,
			limits = opts.limits, waitRefused = waitRefused, yield = opts.yield,
		})
		local inc = P.plan(g, streets, {
			terrain = opts.terrain, maxSeg = maxSeg, snapR = snapR, minLen = minLen, minAngle = 25, sideAngle = sideAngle,
			maxGrade = style.maxSlope, waterSetback = style.waterSetback, maxEdges = maxEdges,
			join = opts.join or "deadEnd", templatePaths = style.templatePaths, yield = opts.yield,
		})
		yield()
		M.hierarchy(g, inc, style)
		inc.mix = M.mix(inc)
		yield()   -- (2026-10-21, TICKCOST round: the checks below in slices of their own)
		local hugR = SEL.HUG * math.max(style.block.len, style.block.depth)
		local look = (opts.lookCheck ~= false and M.LOOK_CHECK) and M.lookIssues(g, inc, hugR, opts.yield, cache.structure)
			or { zigzags = 0, lassos = 0, keys = {} }
		inc.look = look
		yield()
		-- joint kinks at existing dead ends: the piece is left out like a look problem
		local jr = opts.jointRule
		if jr == nil then jr = SEL.JOINT_RULE end
		local joints = jr and M.jointIssues(g, inc) or {}
		inc.jointKinks = #joints
		for _, k in ipairs(joints) do look.keys[#look.keys + 1] = k end
		local issues = look.zigzags + look.lassos + #joints
		-- the cleanest round wins, then the fullest
		if best == nil or issues < bestIssues or (issues == bestIssues and #inc.edges > #best.edges) then
			best, bestReport, bestIssues = inc, report, issues
		end
		local refused = 0
		for _, k in ipairs(look.keys) do
			if not exclude[k] then
				exclude[k] = true
				refused = refused + 1
			end
		end
		for _, d in ipairs(inc.dropped) do
			local st = streets[d.street]
			if st and st.key and d.reason ~= "budget" and d.reason ~= "disconnected" and not exclude[st.key] then
				exclude[st.key] = true
				refused = refused + 1
			end
		end
		if refused == 0 or (#inc.edges >= maxEdges and issues == 0) then break end
		yield()
	end
	end
	rounds()
	-- a young town whose first pieces the planner all refused (curves / angles where the plan meets its few dead
	-- ends, 2026-10-12): once more with straight connectors from the dead ends (ot_select connRelax "force")
	if #best.edges == 0 and #g.edges > 0 then
		connRelax = "force"
		exclude = {}
		for k, v in pairs(opts.exclude or {}) do exclude[k] = v end
		for k in pairs(style._motifGaveUp or {}) do exclude[k] = true end
		cache = {}
		yield()
		rounds()
		connRelax = nil
		if bestReport and #best.edges > 0 then bestReport.connRelax = "force" end
	end
	-- a shaped town whose envelope (ot_select.envelopeCap) leaves the planned increment under-filled (the planner
	-- and the pruning drop pieces the selector found inside it: small towns, narrow arms) plans again with the
	-- envelope and arm fronts widened, a step at a time; the fullest clean result wins
	local shape = style.shape
	if shape and shape.id ~= "compact" and SEL.ENVELOPE and opts.envelope ~= false then
		local first = #best.edges
		for k = 1, SEL.ENV_RETRY do
			if #best.edges >= maxEdges * SEL.ENV_MIN_FILL then break end
			envScale = math.max(envScale0, SEL.ENV_RELAX_F ^ (2 * k))
			yield()
			rounds()
		end
		-- a strong-arm shape holds its envelope (ot_select ARM_STRONG_HOLD); when that leaves almost nothing (a young core
		-- whose dead ends sit at the rim), once more with the envelope widened like any shape
		if #best.edges < M.ENV_WIDE_MIN and (shape.reach or 1) >= 1 and SEL.ARM_STRONG_HOLD then
			envWide = true
			yield()
			rounds()
			envWide = nil
			if bestReport then bestReport.envWide = true end
		end
		if envScale > 1 and bestReport then
			bestReport.envScale, bestReport.envFirst = envScale, first
		end
	end
	-- green reserves over the growth points (2026-10-13): ot_style places them beyond the houses' radius, so a reserve
	-- can cover a dead end that sticks out beyond the houses; when every dead end is covered the town never grows by the
	-- mod (showcase EU organic: form wide, 3 greens on both dead ends). An empty increment plans once more without the
	-- reserves within a block of a dead end; the others stay (PLAN greenRelax=n).
	if #best.edges == 0 and #g.edges > 0 and M.GREEN_RELAX and style.greens and #style.greens > 0 then
		local kept, nDropped = M.greensClearOfDeadEnds(g, style)
		if nDropped > 0 then
			-- (no pcall around rounds(): the driver's slice yields inside it, and a Lua without yield across pcall would
			-- fail the plan; a plan that errors here leaves style._greensSaved, restored by the next planIncrement)
			style._greensSaved = style.greens
			style.greens = kept
			exclude = {}
			for k, v in pairs(opts.exclude or {}) do exclude[k] = v end
			for k in pairs(style._motifGaveUp or {}) do exclude[k] = true end
			cache = {}
			yield()
			rounds()
			style.greens, style._greensSaved = style._greensSaved, nil
			if bestReport and #best.edges > 0 then bestReport.greenRelax = nDropped end
		end
	end
	best.style = style.id
	-- waiting motif branches whose line's next piece was refused in this plan: counted per style (kept across the
	-- session's plans); at SEL.WAIT_GIVEUP the branch is dropped (bestReport.waitGaveUp: the driver's MOTIF line)
	local waitKeys = {}
	for k in pairs(waitRefused) do waitKeys[#waitKeys + 1] = k end
	if #waitKeys > 0 then
		table.sort(waitKeys)
		style._motifWaitN = style._motifWaitN or {}
		for _, k in ipairs(waitKeys) do
			local n = (style._motifWaitN[k] or 0) + 1
			style._motifWaitN[k] = n
			if n >= SEL.WAIT_GIVEUP and not (style._motifGaveUp and style._motifGaveUp[k]) then
				style._motifGaveUp = style._motifGaveUp or {}
				style._motifGaveUp[k] = true
				if bestReport then
					bestReport.waitGaveUp = bestReport.waitGaveUp or {}
					bestReport.waitGaveUp[#bestReport.waitGaveUp + 1] = { key = k, line = waitRefused[k], plans = n }
				end
			end
		end
	end
	if bestReport then bestReport.emptyCap, bestReport.ownEmptyCap, bestReport.ownEmpty = emptyCap, ownEmptyCap, ownEmpty end
	-- (§74 close the gap: near-miss dead ends joined to the street ahead, appended to the increment; opts.nearMiss)
	if bestReport == nil then bestReport = {} end
	-- (2026-10-21: the pass runs in one go, its budget at most: in a fresh slice of its own, yield's reserveUs)
	if opts.nearMiss then yield(tonumber(opts.nearMiss.budgetUs) or 0) end
	M.nearMissPass(g, style, best, bestReport, opts, maxSeg)
	return best, bestReport, mp
end

--- §74 (ot_nearmiss): the near-miss joins appended to inc (in place) when opts.nearMiss is set (the driver: { midOk,
--- retiredOk (passed on since §75: it was dropped here, so no retired dead end was ever joined in game), buildings,
--- clock, budgetUs }; tests: {}), report.nearMiss = the pass's report (report.nearMissErr when it raised: the
--- increment stays as planned). No yield inside (pcall).
function M.nearMissPass(g, style, inc, report, opts, maxSeg)
	local nmo = opts and opts.nearMiss
	if not (nmo and NM.ON) or g == nil or #g.edges == 0 then return end
	local okN, add, rep = pcall(NM.joins, g, style, inc, { terrain = opts.terrain, maxSeg = maxSeg,
		maxGrade = style.maxSlope, waterSetback = style.waterSetback, join = opts.join or "deadEnd", midOk = nmo.midOk,
		retiredOk = nmo.retiredOk, buildings = nmo.buildings, seed = nmo.seed, exclude = opts.exclude, cap = nmo.cap,
		clock = nmo.clock, budgetUs = nmo.budgetUs })
	if not okN then
		-- (the driver's hang guard fires inside the pass: passed on, as anywhere else in the plan)
		if tostring(add):find("planHang", 1, true) then error(add, 0) end
		report.nearMissErr = tostring(add)
		return
	end
	report.nearMiss = rep
	if add and #add.edges > 0 then
		NM.merge(inc, add)
		inc.mix = M.mix(inc)
	end
end

M.GREEN_RELAX = true

--- style.greens without the reserves that hold a dead end of g within their radius + one block: (kept, dropped count).
function M.greensClearOfDeadEnds(g, style)
	local blk = math.max(style.block and style.block.len or 0, style.block and style.block.depth or 0)
	local ends = OG.deadEnds(g)
	local kept, n = {}, 0
	for _, gr in ipairs(style.greens or {}) do
		local near = false
		for _, id in ipairs(ends) do
			local nd = g.nodeById[id]
			if nd and math.sqrt((nd.x - gr[1]) ^ 2 + (nd.y - gr[2]) ^ 2) < gr[3] + blk then near = true; break end
		end
		if near then n = n + 1 else kept[#kept + 1] = gr end
	end
	return kept, n
end

--- Runs `n` increments on graph g (building each into it, tagged 1..n). Stops early when an increment is
--- empty. Joins any node unless opts.join says otherwise (in game only dead ends, plus the street nodes of the §74
--- near-miss joins that the driver allows). Returns the list of increments. For tests and the SVG preview.
function M.simulate(g, style, opts, n)
	opts = opts or {}
	if opts.join == nil then
		local o = {}
		for k, v in pairs(opts) do o[k] = v end
		o.join = "any"
		opts = o
	end
	local out = {}
	for k = 1, n do
		local inc = M.planIncrement(g, style, opts)
		if #inc.edges == 0 then break end
		OG.apply(g, inc, k)
		out[#out + 1] = inc
	end
	return out
end

--- A wedge frame increment (ot_wedge, 2026-10-13) for an armed town: links the unlocked dead ends in its green wedges
--- (beyond the core zone at the envelope level) with locked small streets. opts = { terrain }. Returns inc (ot_plan
--- increment, its edges' keys "frame:a:b") or nil, why, info = { cands, links, coreR, env, kind, and the §75 tip cap
--- (ot_wedge.tipCap): tipCap (m; nil without house data), tipCut / cutMaxR (tips beyond it dropped, the farthest),
--- maxTipR (the farthest tip kept), bodyOut (houses outside the main body) }.
function M.frameIncrement(g, style, opts)
	opts = opts or {}
	-- (opts.yield: nil, or the driver's step note, called between the steps, 2026-10-21: FRAME took up to 41 ms)
	local yield = opts.yield or function() end
	local hidx = g.hasBuilt and SEL.housedIndexM(g, WG.LEAD_M) or nil
	yield()
	local streets, why, nCand, coreR, env, kind, tipCap, body
	if WG.applies(style) then
		kind = "wedge"
		env = SEL.envelopeCap(g, style, opts.terrain, opts.yield)
		yield()
		coreR = WG.coreR(style.shape, env)
		if coreR == nil then return nil, "noEnv", {} end
		tipCap, body = WG.tipCap(g, style.shape.centre[1], style.shape.centre[2])
		yield()
		streets, why, nCand = WG.frameStreets(g, style.shape, { coreR = coreR, housedIdx = hidx, housedDist = SEL.housedDist,
			ringLead = SEL.RING_LEAD_M, maxTipR = tipCap })
	elseif style.meadows and MD.applies(style) then
		-- protected meadows (ot_meadow, later-ideas phase): the game's tips in a meadow sector linked, no tails (the lobes
		-- between the meadows stay free)
		kind = "meadow"
		local z = MD.zone(g, style, SEL.irregularity(style))
		if z == nil then return nil, "noMeadow", { kind = kind } end
		yield()
		coreR, env = z.coreR, nil
		tipCap, body = WG.tipCap(g, z.centre[1], z.centre[2])
		yield()
		streets, why, nCand = WG.frameStreets(g, { centre = z.centre, arms = z.lobes, axis = z.lobes[1] }, { coreR = coreR,
			housedIdx = hidx, housedDist = SEL.housedDist, noTails = true, ringLead = SEL.RING_LEAD_M, maxTipR = tipCap,
			accept = function(x, y) return MD.inSector(z, x, y) end })
	else
		return nil, "style", {}
	end
	-- links refused in game before (opts.exclude: the driver's piece keys) stay out (2026-10-13)
	if why == nil and opts.exclude then
		local kept = {}
		for _, st in ipairs(streets) do
			if not (st.key and opts.exclude[st.key]) then kept[#kept + 1] = st end
		end
		streets = kept
		if #streets == 0 then why = "excluded" end
	end
	-- (§75 tip cap: tipCut tips beyond tipCap dropped, maxTipR the farthest kept; bodyOut the houses outside the body)
	local info = { cands = nCand or 0, links = #streets, coreR = coreR, env = env, kind = kind, tipCap = tipCap,
		bodyOut = body and body.out or nil,
		tipCut = WG.lastTipCut or 0, maxTipR = WG.lastMaxTipR or 0, cutMaxR = WG.lastCutMaxR or 0 }
	if why then return nil, why, info end
	yield()
	local inc = P.plan(g, streets, { terrain = opts.terrain, maxSeg = M.MAX_SEG_FLAT, snapR = 8, minLen = 10, minAngle = 25,
		maxGrade = style.maxSlope, waterSetback = style.waterSetback, maxEdges = WG.MAX_EDGES, join = "deadEnd",
		templatePaths = style.templatePaths, yield = opts.yield })
	inc.mix = M.mix and M.mix(inc) or nil
	if #inc.edges == 0 then return nil, "planEmpty", info end
	return inc, nil, info
end

return M
