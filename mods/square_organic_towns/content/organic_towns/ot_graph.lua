-- Organic Towns: street graph snapshot model (pure). The engine layer fills it from the octree (BASE_EDGE +
-- BASE_EDGE_STREET in the town's box); the planner reads it and the SVG preview / tests build it by hand.
--
-- graph = { nodes = {node...}, edges = {edge...} (insertion order, never pairs() for decisions),
--           nodeById = {[id] = node}, edgeById = {[id] = edge}, adj = {[nodeId] = {edgeId...}},
--           cells = spatial hash of edges, nextId }
-- node  = { id, x, y, z, existing = bool }
-- edge  = { id, n0, n1, class = "main"|"medium"|"small", existing = bool, t0, t1 = {x, y, z} or nil,
--           increment = number or nil (preview: which simulated increment built it) }

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

local CELL = 100   -- spatial hash cell size (m)
local floor, sqrt = math.floor, math.sqrt

function M.new()
	return { nodes = {}, edges = {}, nodeById = {}, edgeById = {}, adj = {}, cells = {}, ncells = {}, nextId = 1 }
end

local function cellKey(cx, cy) return cx * 65536 + cy end   -- unique while |cy| < 32768 cells (3276 km)

local function bump(g, id)
	if type(id) == "number" and id >= g.nextId then g.nextId = floor(id) + 1 end
end

--- Adds a node; id nil -> next free positive id. Returns the node.
function M.addNode(g, id, x, y, z, existing)
	if id == nil then id = g.nextId end
	bump(g, id)
	local n = { id = id, x = x, y = y, z = z or 0, existing = existing ~= false }
	g.nodes[#g.nodes + 1] = n
	g.nodeById[id] = n
	g.adj[id] = g.adj[id] or {}
	local k = cellKey(floor(x / CELL), floor(y / CELL))
	local list = g.ncells[k]
	if list == nil then list = {}; g.ncells[k] = list end
	list[#list + 1] = n
	return n
end

local function indexEdge(g, e)
	local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
	-- (hang guard: an edge with a bad coordinate stays out of the hash; queries over huge boxes scan all edges)
	if not (G.finite(a.x) and G.finite(a.y) and G.finite(b.x) and G.finite(b.y)) then return end
	local x0, x1 = math.min(a.x, b.x), math.max(a.x, b.x)
	local y0, y1 = math.min(a.y, b.y), math.max(a.y, b.y)
	for cx = floor(x0 / CELL), floor(x1 / CELL) do
		for cy = floor(y0 / CELL), floor(y1 / CELL) do
			local k = cellKey(cx, cy)
			local list = g.cells[k]
			if list == nil then list = {}; g.cells[k] = list end
			list[#list + 1] = e.id
		end
	end
end

--- Adds an edge between two existing node ids. Returns the edge.
function M.addEdge(g, id, n0, n1, class, existing, t0, t1)
	assert(g.nodeById[n0] and g.nodeById[n1], "addEdge: unknown node")
	if id == nil then id = g.nextId end
	bump(g, id)
	local e = { id = id, n0 = n0, n1 = n1, class = class or "small", existing = existing ~= false, t0 = t0, t1 = t1 }
	g.edges[#g.edges + 1] = e
	g.edgeById[id] = e
	local a0, a1 = g.adj[n0], g.adj[n1]
	a0[#a0 + 1] = id
	if n1 ~= n0 then a1[#a1 + 1] = id end
	indexEdge(g, e)
	return e
end

--- Graph from a snapshot { nodes = {{id, x, y, z}...}, edges = {{id, node0|n0, node1|n1, class}...} }. Ids
--- are sorted so the result does not depend on the order the engine listed them in.
function M.fromSnapshot(snap)
	local g = M.new()
	local nodes, edges = {}, {}
	for _, n in ipairs(snap.nodes or {}) do nodes[#nodes + 1] = n end
	for _, e in ipairs(snap.edges or {}) do edges[#edges + 1] = e end
	table.sort(nodes, function(a, b) return a.id < b.id end)
	table.sort(edges, function(a, b) return a.id < b.id end)
	for _, n in ipairs(nodes) do M.addNode(g, n.id, n.x or n[1], n.y or n[2], n.z or n[3], true) end
	for _, e in ipairs(edges) do
		local n0, n1 = e.node0 or e.n0, e.node1 or e.n1
		if g.nodeById[n0] and g.nodeById[n1] then
			local ed = M.addEdge(g, e.id, n0, n1, e.class, true, e.t0, e.t1)
			ed.template = e.template
			-- roadDevelopmentLocked (the mod's own locked streets; ot_wedge frames look for them)
			if e.locked then ed.locked = true end
			-- (the mod's own street built this session, ot_driver snapshot; ot_knot.emptyOurs)
			if e.own then ed.own = true end
			-- buildings on its parcels (ot_driver snapshot; ot_select.armBuiltFronts), nil when unknown
			if e.built ~= nil then
				ed.built = e.built
				g.hasBuilt = true
			end
		end
	end
	return g
end

function M.degree(g, id)
	local a = g.adj[id]
	return a and #a or 0
end

--- Dead-end node ids (degree 1), ascending.
function M.deadEnds(g)
	local out = {}
	for _, n in ipairs(g.nodes) do
		if M.degree(g, n.id) == 1 then out[#out + 1] = n.id end
	end
	table.sort(out)
	return out
end

--- The other node of edge `e` seen from node `id`.
function M.other(e, id)
	if e.n0 == id then return e.n1 end
	return e.n0
end

--- Heading of edge `e` leaving node `id` (uses the edge's tangent if it has one, else the chord).
function M.headingFrom(g, e, id)
	local a = g.nodeById[id]
	if e.n0 == id and e.t0 then return G.atan2(e.t0[2], e.t0[1]) end
	if e.n1 == id and e.t1 then return G.atan2(-e.t1[2], -e.t1[1]) end
	local b = g.nodeById[M.other(e, id)]
	return G.heading(a.x, a.y, b.x, b.y)
end

function M.edgeLength(g, e)
	local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
	return G.dist(a.x, a.y, b.x, b.y)
end

--- Centre of the street network: length-weighted mean of edge midpoints (nil for an empty graph).
function M.centre(g)
	local sx, sy, sw = 0, 0, 0
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local w = G.dist(a.x, a.y, b.x, b.y)
		sx, sy, sw = sx + (a.x + b.x) / 2 * w, sy + (a.y + b.y) / 2 * w, sw + w
	end
	if sw <= 0 then
		if #g.nodes == 0 then return nil end
		for _, n in ipairs(g.nodes) do sx, sy = sx + n.x, sy + n.y end
		return { sx / #g.nodes, sy / #g.nodes }
	end
	return { sx / sw, sy / sw }
end

--- Radius around (cx, cy) covering fraction `q` (default 0.9) of the nodes.
function M.radius(g, cx, cy, q)
	local d = {}
	for _, n in ipairs(g.nodes) do d[#d + 1] = G.dist(cx, cy, n.x, n.y) end
	if #d == 0 then return 0 end
	table.sort(d)
	return d[math.max(1, math.min(#d, math.floor(#d * (q or 0.9) + 0.5)))]
end

--- Dominant street axis: length-weighted mean of edge headings modulo 90 deg (4x angle trick).
--- Returns angle in [-pi/4, pi/4) and strength 0..1 (1 = all edges on one orthogonal grid).
function M.dominantAxis(g)
	local sx, sy, sw = 0, 0, 0
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local w = G.dist(a.x, a.y, b.x, b.y)
		if w > 0 then
			local h = G.heading(a.x, a.y, b.x, b.y) * 4
			sx, sy, sw = sx + math.cos(h) * w, sy + math.sin(h) * w, sw + w
		end
	end
	if sw <= 0 then return 0.0, 0 end
	local ang = G.atan2(sy, sx) / 4
	return G.z0(ang), sqrt(sx * sx + sy * sy) / sw
end

--- Bounding box {minX, minY, maxX, maxY} of the nodes, or nil.
function M.bbox(g)
	if #g.nodes == 0 then return nil end
	local b = { math.huge, math.huge, -math.huge, -math.huge }
	for _, n in ipairs(g.nodes) do
		if n.x < b[1] then b[1] = n.x end
		if n.y < b[2] then b[2] = n.y end
		if n.x > b[3] then b[3] = n.x end
		if n.y > b[4] then b[4] = n.y end
	end
	return b
end

--- Nearest node within r of (x, y) passing `filter(node)` (optional). Returns node, distance.
function M.nearestNode(g, x, y, r, filter)
	local best, bd = nil, r
	local function try(n)
		local d = G.dist(x, y, n.x, n.y)
		if d <= bd and (filter == nil or filter(n)) then
			if best == nil or d < bd or (d == bd and n.id < best.id) then best, bd = n, d end
		end
	end
	if not (G.finite(x) and G.finite(y)) then return nil, r end   -- (hang guard: no endless cell loop)
	if r <= 4 * CELL then
		for cx = floor((x - r) / CELL), floor((x + r) / CELL) do
			for cy = floor((y - r) / CELL), floor((y + r) / CELL) do
				for _, n in ipairs(g.ncells[cellKey(cx, cy)] or {}) do try(n) end
			end
		end
	else
		for _, n in ipairs(g.nodes) do try(n) end
	end
	return best, bd
end

--- Nodes whose hash cells overlap the box around segment a-b grown by `pad` (each once, in cell order).
function M.nodesNear(g, ax, ay, bx, by, pad)
	pad = pad or 0
	local out = {}
	-- (hang guard: a box with a bad coordinate finds nothing, a huge one scans every node instead of its cells)
	local x0, x1, y0, y1 = G.cellRange(ax, ay, bx, by, pad, CELL)
	if x0 == nil then
		if G.finite(ax) and G.finite(ay) and G.finite(bx) and G.finite(by) then
			for _, n in ipairs(g.nodes) do out[#out + 1] = n end
		end
		return out
	end
	for cx = x0, x1 do
		for cy = y0, y1 do
			for _, n in ipairs(g.ncells[cellKey(cx, cy)] or {}) do out[#out + 1] = n end
		end
	end
	return out
end

--- Edge ids whose hash cells overlap the box around segment a-b grown by `pad` (deduplicated, ascending).
function M.edgesNear(g, ax, ay, bx, by, pad)
	pad = pad or 0
	local seen, out = {}, {}
	local x0, x1, y0, y1 = G.cellRange(ax, ay, bx, by, pad, CELL)
	if x0 == nil then
		if G.finite(ax) and G.finite(ay) and G.finite(bx) and G.finite(by) then
			for _, e in ipairs(g.edges) do out[#out + 1] = e.id end
			table.sort(out)
		end
		return out
	end
	for cx = x0, x1 do
		for cy = y0, y1 do
			local list = g.cells[cellKey(cx, cy)]
			if list then
				for _, id in ipairs(list) do
					if not seen[id] then seen[id] = true; out[#out + 1] = id end
				end
			end
		end
	end
	table.sort(out)
	return out
end

--- Calls fn(edge) for every edge in the hash cells overlapping the box around a-b grown by `pad` (an edge
--- spanning several cells may come more than once); stops early when fn returns true.
local function eachNear(g, ax, ay, bx, by, pad, fn)
	local x0, x1, y0, y1 = G.cellRange(ax, ay, bx, by, pad, CELL)
	if x0 == nil then
		if G.finite(ax) and G.finite(ay) and G.finite(bx) and G.finite(by) then
			for _, e in ipairs(g.edges) do if fn(e) then return true end end
		end
		return false
	end
	for cx = x0, x1 do
		for cy = y0, y1 do
			local list = g.cells[cellKey(cx, cy)]
			if list then
				for i = 1, #list do
					if fn(g.edgeById[list[i]]) then return true end
				end
			end
		end
	end
	return false
end

--- Distance from (x, y) to the nearest edge chord within `maxD` (nil if none); edges touching a node id in
--- `skip` (optional set) are ignored.
function M.distToEdges(g, x, y, maxD, skip)
	local best = nil
	eachNear(g, x, y, x, y, maxD, function(e)
		if not (skip and (skip[e.n0] or skip[e.n1])) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local d = G.pointSegDist(x, y, a.x, a.y, b.x, b.y)
			if d <= maxD and (best == nil or d < best) then best = d end
		end
	end)
	return best
end

--- Distance from (x, y) to the nearest edge within maxD that `keep(edge)` accepts, or nil.
function M.distToEdgesWhere(g, x, y, maxD, keep)
	local best = nil
	eachNear(g, x, y, x, y, maxD, function(e)
		if keep(e) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local d = (G.pointSegDist(x, y, a.x, a.y, b.x, b.y))
			if d <= maxD and (best == nil or d < best) then best = d end
		end
	end)
	return best
end

--- First edge (in hash order) whose chord properly crosses segment a-b (edges touching node ids in `skip` are
--- ignored). Returns the edge or nil.
function M.crossing(g, ax, ay, bx, by, skip)
	local found = nil
	eachNear(g, ax, ay, bx, by, 1, function(e)
		if not (skip and (skip[e.n0] or skip[e.n1])) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if G.segIntersect(ax, ay, bx, by, a.x, a.y, b.x, b.y, 1e-4) then found = e; return true end
		end
	end)
	return found
end

--- true when nodes a and b are joined by an edge.
function M.connected(g, a, b)
	for _, id in ipairs(g.adj[a] or {}) do
		local e = g.edgeById[id]
		if M.other(e, a) == b then return true end
	end
	return false
end

--- Frontier: dead ends first, then the outermost nodes (by distance from (cx, cy)), up to `limit` node ids.
function M.frontier(g, cx, cy, limit)
	local list = {}
	for _, n in ipairs(g.nodes) do
		local deg = M.degree(g, n.id)
		if deg >= 1 and deg <= 2 then
			list[#list + 1] = { id = n.id, dead = deg == 1, d = G.dist(cx, cy, n.x, n.y) }
		end
	end
	table.sort(list, function(a, b)
		if a.dead ~= b.dead then return a.dead end
		if a.d ~= b.d then return a.d > b.d end
		return a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(#list, limit or #list) do out[i] = list[i].id end
	return out
end

---------------------------------------------------------------------------
-- Network structure: bridges, 2-edge-connected parts, the core and each node's gateway to it. Used by the
-- selector's loop rule (a loop hanging off the town by one stem or node reads as a "lasso", showcase v2
-- screenshots) and by ot_metrics.

--- Bridge edges (removing one disconnects the graph): { [edge id] = true }. Iterative Tarjan over node ids in
--- insertion order (deterministic).
function M.bridges(g)
	local index, low, out = {}, {}, {}
	local counter = 0
	for _, root in ipairs(g.nodes) do
		if index[root.id] == nil and M.degree(g, root.id) > 0 then
			counter = counter + 1
			index[root.id], low[root.id] = counter, counter
			local stack = { { node = root.id, viaEdge = nil, i = 1 } }
			while #stack > 0 do
				local fr = stack[#stack]
				local adj = g.adj[fr.node]
				if fr.i <= #adj then
					local eid = adj[fr.i]
					fr.i = fr.i + 1
					if eid ~= fr.viaEdge then
						local o = M.other(g.edgeById[eid], fr.node)
						if index[o] == nil then
							counter = counter + 1
							index[o], low[o] = counter, counter
							stack[#stack + 1] = { node = o, viaEdge = eid, i = 1 }
						elseif index[o] < low[fr.node] then
							low[fr.node] = index[o]
						end
					end
				else
					stack[#stack] = nil
					local parent = stack[#stack]
					if parent then
						if low[fr.node] < low[parent.node] then low[parent.node] = low[fr.node] end
						if low[fr.node] > index[parent.node] then out[fr.viaEdge] = true end
					end
				end
			end
		end
	end
	return out
end

--- Structure of the network: { bridges, comp = { [node] = part id } (2-edge-connected parts: bridges removed),
--- parts = { [id] = { nodes, edges, cycle = bool } }, core = part id or nil (the part with a cycle and the most
--- edges), gateway = { [node] = node id } (core nodes themselves; every other node the core node its stem hangs
--- from; parts not connected to the core: their first node) }.
function M.structure(g)
	local br = M.bridges(g)
	local comp, parts, nextId = {}, {}, 0
	for _, n in ipairs(g.nodes) do
		if comp[n.id] == nil and M.degree(g, n.id) > 0 then
			nextId = nextId + 1
			local part = { id = nextId, nodes = 0, edges = 0 }
			parts[nextId] = part
			comp[n.id] = nextId
			local stack = { n.id }
			while #stack > 0 do
				local id = stack[#stack]
				stack[#stack] = nil
				part.nodes = part.nodes + 1
				for _, eid in ipairs(g.adj[id]) do
					if not br[eid] then
						local o = M.other(g.edgeById[eid], id)
						if comp[o] == nil then comp[o] = nextId; stack[#stack + 1] = o end
					end
				end
			end
		end
	end
	for _, e in ipairs(g.edges) do
		if not br[e.id] and comp[e.n0] then
			local part = parts[comp[e.n0]]
			part.edges = part.edges + 1
			part.edgeIds = part.edgeIds or {}
			part.edgeIds[#part.edgeIds + 1] = e.id
		end
	end
	local core, best = nil, 0
	for id = 1, nextId do
		local part = parts[id]
		part.cycle = part.edges >= part.nodes and part.edges > 0
		if part.cycle and part.edges > best then core, best = id, part.edges end
	end
	local gateway = {}
	local queue, head = {}, 1
	for _, n in ipairs(g.nodes) do
		if core and comp[n.id] == core then gateway[n.id] = n.id; queue[#queue + 1] = n.id end
	end
	local function flood()
		while head <= #queue do
			local id = queue[head]
			head = head + 1
			for _, eid in ipairs(g.adj[id]) do
				local o = M.other(g.edgeById[eid], id)
				if gateway[o] == nil then gateway[o] = gateway[id]; queue[#queue + 1] = o end
			end
		end
	end
	flood()
	for _, n in ipairs(g.nodes) do
		if gateway[n.id] == nil and M.degree(g, n.id) > 0 then
			gateway[n.id] = n.id
			queue[#queue + 1] = n.id
			flood()
		end
	end
	return { bridges = br, comp = comp, parts = parts, core = core, gateway = gateway }
end

--- The network as it would be with increment `inc` built: a topology-only graph (nodes, edges, adj; no spatial
--- hash) sharing g's node and edge tables; the increment's nodes and edges keep their (negative) entity ids and
--- its edges carry `new = true` and their plan piece `key`. For look checks (ot_core) and metrics.
function M.overlay(g, inc)
	local c = { nodes = {}, edges = {}, nodeById = {}, edgeById = {}, adj = {} }
	for _, n in ipairs(g.nodes) do
		c.nodes[#c.nodes + 1] = n
		c.nodeById[n.id] = n
		local a = {}
		for i, x in ipairs(g.adj[n.id] or {}) do a[i] = x end
		c.adj[n.id] = a
	end
	for _, e in ipairs(g.edges) do
		c.edges[#c.edges + 1] = e
		c.edgeById[e.id] = e
	end
	for _, nd in ipairs(inc.nodes) do
		local n = { id = nd.entity, x = nd.x, y = nd.y, z = nd.z }
		c.nodes[#c.nodes + 1] = n
		c.nodeById[n.id] = n
		c.adj[n.id] = {}
	end
	for _, e in ipairs(inc.edges) do
		local ce = { id = e.entity, n0 = e.node0, n1 = e.node1, class = e.class, t0 = e.t0, t1 = e.t1, new = true, key = e.key,
			template = e.template }
		if c.nodeById[ce.n0] and c.nodeById[ce.n1] then
			c.edges[#c.edges + 1] = ce
			c.edgeById[ce.id] = ce
			local a0, a1 = c.adj[ce.n0], c.adj[ce.n1]
			a0[#a0 + 1] = ce.id
			if ce.n1 ~= ce.n0 then a1[#a1 + 1] = ce.id end
		end
	end
	return c
end

--- Builds an increment (ot_plan output) into the graph as if the engine had built it: new nodes and edges
--- get fresh positive ids. Returns a map planned entity id -> graph id. Used by tests and the SVG preview.
function M.apply(g, inc, tag)
	local map = {}
	for _, n in ipairs(inc.nodes) do
		local node = M.addNode(g, nil, n.x, n.y, n.z, false)
		map[n.entity] = node.id
	end
	for _, e in ipairs(inc.edges) do
		local n0 = map[e.node0] or e.node0
		local n1 = map[e.node1] or e.node1
		local edge = M.addEdge(g, nil, n0, n1, e.class, false, e.t0, e.t1)
		edge.increment = tag
		edge.template = e.template
		map[e.entity] = edge.id
	end
	return map
end

return M
