-- Organic Towns: polylines -> node/edge specs for one street increment (pure).
--
-- In:  plan(graph, streets, opts)
--   streets = { { pts = {{x, y[, ux, uy]}, ...}, class = "main"|"medium"|"small", curved = bool,
--                 smooth = bool (pts already a smooth dense curve carrying unit tangents), dirA/dirB = {ux, uy}
--                 (end tangents of a jittered lattice piece), startNode = existing node id or nil,
--                 endNode = existing node id or nil }, ... }  (priority order)
--   opts    = { terrain = ot_terrain sampler or nil, maxSeg = 100, snapR = 8, minLen = 10, minAngle = 25 (deg),
--               sideAngle = 0 (deg: §75, a new street at a junction of 3+ streets meets every other street there at
--               least this far off, a fork's two arms excepted, ot_check.sideBad; 0 = off, the default: steer towns'
--               plans and the near-miss joins pass ot_check.LIMITS.sideAngle 60; streets with `sideFree` are exempt),
--               maxGrade = 0.10, waterSetback = 25, maxEdges = 24, join = "deadEnd"|"any"|"none",
--               clear = 6 (m: new nodes keep this far from existing streets, new edges from existing nodes),
--               clearEdge = 16 (m: every point of a new edge keeps this far from existing street centre lines it
--               doesn't meet: two small town streets are 16 m wide together; the showcase's pre-checks refused
--               plans whose edges ran alongside existing streets with "Collision", 2026-10-11),
--               templatePaths = { main = ..., medium = ..., small = ... }, requireConnected = bool
--               (default: true when the graph has nodes), joinExtra = { [existing node id] = true } (§74: may be a
--               street's explicit start / end node whatever its degree) }
--   graph nodes with `noJoin = true` are never joined (M.joinable)
-- Out: increment = {
--   nodes = { { entity = -k, x, y, z } },                                new nodes only
--   edges = { { entity = -k, node0, node1, p0 = {x,y,z}, p1, t0 = {x,y,z}, t1, class, template, length,
--               street = index into streets, key = the street's plan piece key } },
--   joins = { { node = existing node id, edge = entity } },              where the increment touches the network
--   dropped = { { street = index, reason = "steep"|"water"|"crossesExisting"|"nearExisting"|"crossesNew"|"nearNew"|"angle"|
--                 "short"|"exists"|"blockedNode"|"budget"|"disconnected"|"curve" } },
--   ("crossesNew" / "nearNew": the edge crosses or overlaps an edge already accepted for this increment, except at
--   a shared node: ot_check.pairConflict)
--   stats = { edges, nodes, length } }
-- Entity ids follow SimpleProposal's convention (edges first: -1..-E, then nodes -(E+1)..); node0/node1 are
-- either such a new node id or a positive existing node id. Tangents (Hermite, z included): straight edges the
-- chord; curved edges the curve's direction at each node (one tangent per node along a street) with the arc
-- length as magnitude, and every curved edge's Hermite at least MIN_RADIUS (ot_check; refused: "curve").
-- Angles at nodes are measured between actual tangents. `length` is the arc length.
-- Every coordinate is rounded to mm and -0 normalised to +0 (docs/findings.md "Negative zero").

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local C = ug_require "square_organic_towns::/organic_towns/ot_check.lua"

local M = {}

M.DEFAULTS = { maxSeg = 100, snapR = 8, minLen = 10, minAngle = 25, sideAngle = 0, maxGrade = 0.10, waterSetback = 25,
	maxEdges = 24, join = "deadEnd", clear = 6, clearEdge = 16 }

local function opt(opts, k)
	local v = opts[k]
	if v == nil then return M.DEFAULTS[k] end
	return v
end

M.SIMPLIFY_TOL = 1.5   -- m: curve vertices closer than this to the chord are dropped before splitting

--- The node positions a street polyline becomes: simplified (no vertex closer than minLen to the next one),
--- then every run split evenly into pieces of at most maxSeg.
function M.shape(pts, maxSeg, minLen)
	return G.resample(G.simplify(pts, M.SIMPLIFY_TOL, minLen or M.DEFAULTS.minLen), maxSeg or M.DEFAULTS.maxSeg)
end

M.FOOTPRINT = true        -- junction footprint check (ot_check.footprint); tests compare with it off
M.MIN_RADIUS = 70         -- m: every emitted edge's Hermite curve (town templates: 44 m final, 60 m player tool)
M.LINE_RADIUS = 80        -- m: curved streets that arrive unsmoothed are smoothed to this (ot_geom.smoothLine)
M.MAX_EDGE_TURN = math.rad(40)   -- a curved street gets a node at least every 40 deg of turn
M.SPLIT_TRIES = 3         -- edge counts tried for a curved street (from the fewest allowed up)

local function turnBetween(a, b)
	return math.acos(G.clamp(a[1] * b[1] + a[2] * b[2], -1, 1))
end

local function hermiteRadius(ax, ay, bx, by, d0, d1, L)
	return (C.minRadius({ ax, ay }, { d0[1] * L, d0[2] * L }, { bx, by }, { d1[1] * L, d1[2] * L }, 12))
end

--- Node positions of a street with the unit tangent direction at each and the arc length of the edge ending
--- there: { {x, y, ux, uy, arc} }. Straight streets: M.shape with chord directions. Curved streets
--- (`curved`; `smooth` = the points already are a smooth dense curve, else they are smoothed here) and grid
--- pieces with end directions (`dirA`/`dirB`, junctions jittered: one tangent through each lattice node) are
--- cut evenly by arc length (at most maxSeg, a node every MAX_EDGE_TURN of turn, no edge below minLen; up to
--- SPLIT_TRIES counts until every edge's Hermite curve reaches MIN_RADIUS).
function M.streetPoints(st, maxSeg, minLen)
	maxSeg = maxSeg or M.DEFAULTS.maxSeg
	minLen = minLen or M.DEFAULTS.minLen
	local pts = st.pts
	if st.dirA or st.dirB then
		-- end directions blended toward the chord (halves) until the piece's curve is wide enough; a strongly
		-- jittered lattice then keeps a corner at the node instead
		local a, b = pts[1], pts[#pts]
		local cx, cy, L = G.unit(b[1] - a[1], b[2] - a[2])
		local da, db = st.dirA or { cx, cy }, st.dirB or { cx, cy }
		for k = 0, 4 do
			local w = (k == 4) and 0 or 0.5 ^ k
			local ax_, ay_ = G.unit(cx + (da[1] - cx) * w, cy + (da[2] - cy) * w)
			local bx_, by_ = G.unit(cx + (db[1] - cx) * w, cy + (db[2] - cy) * w)
			if w == 0 or hermiteRadius(a[1], a[2], b[1], b[2], { ax_, ay_ }, { bx_, by_ }, L) >= M.LINE_RADIUS then
				da, db = { ax_, ay_ }, { bx_, by_ }
				break
			end
		end
		pts = G.hermitePts(a[1], a[2], b[1], b[2], da, db, 16)
	elseif st.curved and not st.smooth then
		pts = (G.smoothLine(pts, M.LINE_RADIUS))
	elseif not st.curved then
		local out = {}
		local sh = M.shape(pts, maxSeg, minLen)
		for i, p in ipairs(sh) do
			local q = sh[i + 1] or p
			local o = sh[i - 1] or p
			local ux, uy
			if sh[i + 1] then ux, uy = G.unit(q[1] - p[1], q[2] - p[2]) else ux, uy = G.unit(p[1] - o[1], p[2] - o[2]) end
			out[i] = { p[1], p[2], ux, uy, i > 1 and G.dist(o[1], o[2], p[1], p[2]) or 0, chord = true }
		end
		return out
	end
	local dirs, cum = G.polyDirs(pts)
	local L = cum[#cum]
	local turn = 0
	for i = 2, #dirs do turn = turn + turnBetween(dirs[i - 1], dirs[i]) end
	local nMin = math.max(math.ceil(L / maxSeg - 1e-9), math.ceil(turn / M.MAX_EDGE_TURN - 1e-9), 1)
	local nMax = math.max(1, math.floor(L / minLen))
	nMin = math.min(nMin, nMax)
	-- even cuts; the fewest edges whose Hermite curves all reach MIN_RADIUS, else the best of SPLIT_TRIES
	-- counts (short edges magnify small direction errors, so more nodes is not always better)
	local function cuts(n)
		local at = {}
		for k = 0, n do at[#at + 1] = L * k / n end
		return at
	end
	local function worst(at)
		local w = math.huge
		for k = 2, #at do
			local ax, ay, a0x, a0y = G.frameAt(pts, dirs, cum, at[k - 1])
			local bx, by, b0x, b0y = G.frameAt(pts, dirs, cum, at[k])
			local r = hermiteRadius(ax, ay, bx, by, { a0x, a0y }, { b0x, b0y }, at[k] - at[k - 1])
			if r < w then w = r end
		end
		return w
	end
	local at, bestW = nil, -1
	for n = nMin, math.min(nMax, nMin + M.SPLIT_TRIES - 1) do
		local c = cuts(n)
		local w = worst(c)
		if w > bestW then at, bestW = c, w end
		if w >= M.MIN_RADIUS then break end
	end
	at = at or cuts(nMin)
	local out = {}
	for k, s in ipairs(at) do
		local x, y, ux, uy = G.frameAt(pts, dirs, cum, s)
		out[k] = { x, y, ux, uy, k > 1 and (s - at[k - 1]) or 0 }
	end
	-- exact end points (the junctions)
	out[1][1], out[1][2] = pts[1][1], pts[1][2]
	out[#out][1], out[#out][2] = pts[#pts][1], pts[#pts][2]
	return out
end

--- Number of edges a street becomes (the selector's budget estimate matches the planner). `pts` may be a
--- street table (with curved/smooth/dirA/dirB) or a bare polyline (straight).
function M.edgeCount(pts, maxSeg, minLen)
	if pts.pts then return #M.streetPoints(pts, maxSeg, minLen) - 1 end
	return #M.shape(pts, maxSeg, minLen) - 1
end

--- May a new street end at existing graph node `node` under join mode `join`? Never at a node marked
--- `noJoin` (the engine layer marks nodes it must not touch: player roads, constructions, own nodes without a
--- lane config); "deadEnd" only at nodes with at most one edge.
function M.joinable(g, node, join)
	if node == nil or node.noJoin or join == "none" then return false end
	if join == "any" then return true end
	return OG.degree(g, node.id) <= 1
end

--- Plans one increment. See the header for the shapes.
function M.plan(g, streets, opts)
	opts = opts or {}
	local maxSeg, snapR, minLen = opt(opts, "maxSeg"), opt(opts, "snapR"), opt(opts, "minLen")
	local minAngle = math.rad(opt(opts, "minAngle"))
	local sideAngle = math.rad(opt(opts, "sideAngle"))
	local maxGrade, setback, maxEdges = opt(opts, "maxGrade"), opt(opts, "waterSetback"), opt(opts, "maxEdges")
	local join = opt(opts, "join")
	local clear = opt(opts, "clear")
	local clearEdge = opt(opts, "clearEdge")
	local terrain = opts.terrain
	local requireConnected = opts.requireConnected
	if requireConnected == nil then requireConnected = #g.nodes > 0 end

	-- working state: new nodes have negative local ids, existing nodes their graph id
	local newNodes = {}         -- [-k] = {x, y}
	local newNodeList = {}      -- local ids in creation order
	local accepted = {}         -- accepted edges {a, b, class, street, prev = {x,y}|nil, next = {x,y}|nil, curved}
	local nodeHeadings = {}     -- [nodeRef] = { { h = heading, new = true, free } } of accepted new edges
	local pairUsed = {}         -- "a|b" -> true
	local dropped = {}

	local function pos(ref)
		if ref < 0 then local n = newNodes[ref]; return n[1], n[2] end
		local n = g.nodeById[ref]
		return n.x, n.y
	end

	local function joinable(node) return M.joinable(g, node, join) end
	-- (§74 near-miss joins, ot_nearmiss: these existing nodes may be a street's explicit end whatever their degree, a
	-- node in the middle of a street becoming a T; never one marked noJoin, except a value "retired" for a node marked
	-- nmRetired: the driver's retired dead end, whose only noJoin reason is that it stayed empty)
	local joinExtra = opts.joinExtra

	-- node for a point: snaps to a new node, or at street ends to an existing one; false = blocked
	local function nodeFor(x, y, isEnd, explicit)
		if explicit ~= nil then
			local ex = g.nodeById[explicit]
			local xj = joinExtra and joinExtra[explicit]
			if ex and (joinable(ex) or (xj and join ~= "none" and (not ex.noJoin or (xj == "retired" and ex.nmRetired)))) then
				return explicit
			end
			return false
		end
		local best, bd = nil, snapR
		for _, k in ipairs(newNodeList) do
			local n = newNodes[k]
			local d = G.dist(x, y, n[1], n[2])
			if d <= bd then best, bd = k, d end
		end
		if best then return best end
		local ex = OG.nearestNode(g, x, y, snapR)
		if ex then
			if isEnd and joinable(ex) then return ex.id end
			return false
		end
		-- a new node on (or right next to) an existing street would overlap it: blocked
		if #g.edges > 0 and OG.distToEdges(g, x, y, clear) then return false end
		local k = -(#newNodeList + 1)
		newNodes[k] = { x, y }
		newNodeList[#newNodeList + 1] = k
		return k
	end

	-- the streets at a node: { h = heading leaving it, new = accepted in this increment, free = its street is sideFree }
	local function armsAt(ref)
		local arms = {}
		if ref > 0 then
			for _, id in ipairs(g.adj[ref] or {}) do arms[#arms + 1] = { h = OG.headingFrom(g, g.edgeById[id], ref) } end
		end
		for _, a in ipairs(nodeHeadings[ref] or {}) do arms[#arms + 1] = a end
		return arms
	end

	-- a new street leaving node ref at heading h: minAngle off every street there (a bend), and at a junction the
	-- side-street rule (§75, ot_check.sideBad) over the pairs with a new street
	local function angleOk(ref, h, free)
		local arms = armsAt(ref)
		for _, o in ipairs(arms) do
			if G.angleDiff(o.h, h) < minAngle then return false end
		end
		if sideAngle > 0 and #arms >= 2 then
			arms[#arms + 1] = { h = h, new = true, free = free }
			if C.sideBad(arms, sideAngle) then return false end
		end
		return true
	end

	-- junction footprints (ot_check.footprint): every edge keeps room for the street bodies overlapping at both
	-- of its nodes. Existing edges at a joined node count too (a short vanilla dead-end stub can't take a sharp
	-- turn), with their own footprint at their far node; accepted new edges are re-checked when a later edge
	-- meets them at a sharper angle.
	local templates = opts.templatePaths or {}
	local footprintOn = opts.footprint ~= false and M.FOOTPRINT
	local function widthOf(class) return C.halfWidth(class, templates[class]) end
	local exFp = {}   -- existing edge id -> footprint at its far node (existing streets only), cached
	local function existingArms(ref)
		local out = {}
		for _, id in ipairs(g.adj[ref] or {}) do
			local e = g.edgeById[id]
			out[#out + 1] = { h = OG.headingFrom(g, e, ref), w = C.halfWidth(e.class, e.template), ex = e }
		end
		return out
	end
	local function farFootprint(e, ref)
		local key = e.id .. ":" .. ref
		if exFp[key] == nil then
			local far = OG.other(e, ref)
			local h = OG.headingFrom(g, e, far)
			local w = C.halfWidth(e.class, e.template)
			local fp = 0
			for _, id in ipairs(g.adj[far] or {}) do
				if id ~= e.id then
					local o = g.edgeById[id]
					fp = math.max(fp, C.footprint(h, w, OG.headingFrom(g, o, far), C.halfWidth(o.class, o.template)))
				end
			end
			exFp[key] = fp
		end
		return exFp[key]
	end
	local accAt = {}   -- node ref -> accepted edges there
	--- nil when the edge (heading hA at a, hB at b, half width w, length L) fits with every street at its nodes,
	--- else "footprint".
	local function footprintFail(a, b, hA, hB, w, L)
		if not footprintOn then return nil end
		local need = {}
		for side = 1, 2 do
			local ref, h = side == 1 and a or b, side == 1 and hA or hB
			local fp = 0
			if ref > 0 then
				for _, arm in ipairs(existingArms(ref)) do
					local f = C.footprint(h, w, arm.h, arm.w)
					fp = math.max(fp, f)
					-- the existing street must hold this junction's footprint and its far one
					local el = OG.edgeLength(g, arm.ex)
					if el < f + farFootprint(arm.ex, ref) + C.FOOTPRINT_MARGIN then return "footprint" end
				end
			end
			for _, e in ipairs(accAt[ref] or {}) do
				local eh, other = e.a == ref and e.hA or e.hB, e.a == ref and e.b or e.a
				local f = C.footprint(h, w, eh, e.w)
				fp = math.max(fp, f)
				if f > (e.fp[ref] or 0) and e.arc < f + (e.fp[other] or 0) + C.FOOTPRINT_MARGIN then return "footprint" end
			end
			need[side] = fp
		end
		if L < need[1] + need[2] + C.FOOTPRINT_MARGIN then return "footprint" end
		return nil, need[1], need[2]
	end

	-- the edge's curve as a polyline (ot_check.curvePts: chord for straight edges, Hermite samples for curves)
	local function samples(ax, ay, bx, by, d0, d1, arc)
		if d0 == nil then return { { ax, ay }, { bx, by } } end
		return C.curvePts({ ax, ay }, { d0[1] * arc, d0[2] * arc }, { bx, by }, { d1[1] * arc, d1[2] * arc })
	end

	-- self-clearance against the edges already accepted for this increment (ot_check.pairConflict): no
	-- crossing and no overlap except at shared nodes (the showcase's "Collision partners=ent-20" refusals)
	local function conflictNew(P, a, b, class)
		local w = widthOf(class)
		for _, e in ipairs(accepted) do
			local kind = C.pairConflict(P, a, b, w, e.pts, e.a, e.b, widthOf(e.class))
			if kind then return kind end
		end
		return nil
	end

	local function check(a, b, hA, hB, d0, d1, arc, class, free)
		local ax, ay = pos(a)
		local bx, by = pos(b)
		if a == b then return "short" end
		local l = G.dist(ax, ay, bx, by)
		if l < minLen then return "short" end
		local key = a < b and (a .. "|" .. b) or (b .. "|" .. a)
		if pairUsed[key] then return "exists" end
		if a > 0 and b > 0 and OG.connected(g, a, b) then return "exists" end
		local skip = {}
		if a > 0 then skip[a] = true end
		if b > 0 then skip[b] = true end
		if OG.crossing(g, ax, ay, bx, by, skip) then return "crossesExisting" end
		-- passing an existing node it doesn't connect to (touching, or running along a street's end)
		for _, n in ipairs(OG.nodesNear(g, ax, ay, bx, by, clear)) do
			if not skip[n.id] and OG.degree(g, n.id) > 0 and G.pointSegDist(n.x, n.y, ax, ay, bx, by) < clear then
				return "nearExisting"
			end
		end
		-- a medium (main) street is 24 m wide: 4 m more clearance than two small ones
		local ce = clearEdge + math.max(0, widthOf(class) - 8)
		if clearEdge > 0 and #g.edges > 0 then
			-- running alongside an existing street (edges at its own existing end nodes don't count): sample the
			-- chord every 8 m, leaving out the first / last 12 m at an existing end node (the joint itself)
			local n = math.max(2, math.ceil(l / 8))
			for k = 0, n do
				local f = k / n
				local dA, dB = f * l, (1 - f) * l
				if not ((a > 0 and dA < 12) or (b > 0 and dB < 12)) then
					if OG.distToEdges(g, ax + (bx - ax) * f, ay + (by - ay) * f, ce, skip) then return "nearExisting" end
				end
			end
		end
		local P = samples(ax, ay, bx, by, d0, d1, arc)
		local cn = conflictNew(P, a, b, class)
		if cn then return cn end
		if terrain then
			if T.pathMaxGrade(terrain, { { ax, ay }, { bx, by } }) > maxGrade then return "steep" end
			if T.wetAlong(terrain, { { ax, ay }, { bx, by } }, setback) then return "water" end
		end
		if not angleOk(a, hA, free) or not angleOk(b, hB, free) then return "angle" end
		if d0 and hermiteRadius(ax, ay, bx, by, d0, d1, arc) < M.MIN_RADIUS then return "curve" end
		local fpBad, fpA, fpB = footprintFail(a, b, hA, hB, widthOf(class), arc or l)
		if fpBad then return fpBad end
		return nil, key, P, fpA, fpB
	end

	local budgetHit = false
	local yieldFn = opts.yield   -- (the driver's plan slice may end between the streets, ot_driver.PLAN_SLICE_US)
	for si, st in ipairs(streets) do
		if yieldFn and si % 4 == 0 then yieldFn() end
		if budgetHit then
			dropped[#dropped + 1] = { street = si, reason = "budget" }
		else
			local pts = M.streetPoints(st, maxSeg, minLen)
			local refs = {}
			for i, p in ipairs(pts) do
				local explicit = nil
				if i == 1 then explicit = st.startNode elseif i == #pts then explicit = st.endNode end
				refs[i] = nodeFor(p[1], p[2], i == 1 or i == #pts, explicit)
			end
			for i = 2, #pts do
				local a, b = refs[i - 1], refs[i]
				if a == false or b == false then
					dropped[#dropped + 1] = { street = si, reason = "blockedNode" }
				elseif #accepted >= maxEdges then
					dropped[#dropped + 1] = { street = si, reason = "budget" }
					budgetHit = true
					break
				else
					local ax, ay = pos(a)
					local bx, by = pos(b)
					local p, q = pts[i - 1], pts[i]
					local d0, d1, arc
					if p.chord then
						-- straight: chord directions from the (possibly snapped) node positions
						local ux, uy = G.unit(bx - ax, by - ay)
						d0, d1, arc = { ux, uy }, { ux, uy }, G.dist(ax, ay, bx, by)
					else
						d0, d1, arc = { p[3], p[4] }, { q[3], q[4] }, q[5]
					end
					local hA = G.atan2(d0[2], d0[1])
					local hB = G.wrap(G.atan2(d1[2], d1[1]) + math.pi)
					local reason, key, P, fpA, fpB = check(a, b, hA, hB, (not p.chord) and d0 or nil, d1, arc, st.class,
						st.sideFree == true)
					if reason then
						dropped[#dropped + 1] = { street = si, reason = reason }
					else
						pairUsed[key] = true
						local w = widthOf(st.class or "small")
						local acc = { a = a, b = b, class = st.class or "small", street = si,
							d0 = d0, d1 = d1, arc = arc, pts = P, hA = hA, hB = hB, w = w, fp = { [a] = fpA or 0, [b] = fpB or 0 } }
						-- the footprints of the edges already at its nodes grow with the new street's angle
						for side = 1, 2 do
							local ref, h = side == 1 and a or b, side == 1 and hA or hB
							for _, e in ipairs(accAt[ref] or {}) do
								local eh = e.a == ref and e.hA or e.hB
								e.fp[ref] = math.max(e.fp[ref] or 0, C.footprint(h, w, eh, e.w))
							end
							accAt[ref] = accAt[ref] or {}
							local l = accAt[ref]
							l[#l + 1] = acc
						end
						accepted[#accepted + 1] = acc
						nodeHeadings[a] = nodeHeadings[a] or {}
						nodeHeadings[b] = nodeHeadings[b] or {}
						local ha, hb = nodeHeadings[a], nodeHeadings[b]
						local free = st.sideFree == true or nil
						ha[#ha + 1] = { h = hA, new = true, free = free }
						hb[#hb + 1] = { h = hB, new = true, free = free }
					end
				end
			end
		end
	end

	-- connectivity: keep components touching an existing node (or, on an empty graph, the first component)
	if #accepted > 0 then
		local parent = {}
		local function find(x)
			while parent[x] ~= nil and parent[x] ~= x do x = parent[x] end
			return x
		end
		local function union(x, y)
			parent[x] = parent[x] or x
			parent[y] = parent[y] or y
			local rx, ry = find(x), find(y)
			if rx ~= ry then parent[rx] = ry end
		end
		for _, e in ipairs(accepted) do union(e.a, e.b) end
		local good = {}
		local any = false
		for _, e in ipairs(accepted) do
			if e.a > 0 then good[find(e.a)] = true; any = true end
			if e.b > 0 then good[find(e.b)] = true; any = true end
		end
		-- nothing touches the network: keep nothing (growth must connect) or the first component (new town)
		if not any and not requireConnected then good[find(accepted[1].a)] = true end
		local kept = {}
		for _, e in ipairs(accepted) do
			if good[find(e.a)] then kept[#kept + 1] = e
			else dropped[#dropped + 1] = { street = e.street, reason = "disconnected" } end
		end
		accepted = kept
	end

	-- heights
	local function zAt(ref)
		if ref > 0 then return g.nodeById[ref].z or 0 end
		local n = newNodes[ref]
		if terrain then return terrain.height(n[1], n[2]) end
		return 0
	end

	-- entity ids: edges -1..-E, then the used new nodes
	local inc = { nodes = {}, edges = {}, joins = {}, dropped = dropped }
	local E = #accepted
	local entityOf = {}
	local used = {}
	for _, e in ipairs(accepted) do used[e.a] = true; used[e.b] = true end
	local nextNode = -(E + 1)
	for _, k in ipairs(newNodeList) do
		if used[k] then
			entityOf[k] = nextNode
			local n = newNodes[k]
			inc.nodes[#inc.nodes + 1] = { entity = nextNode, x = G.round(n[1]), y = G.round(n[2]), z = G.round(zAt(k)) }
			nextNode = nextNode - 1
		end
	end
	local function ent(ref)
		if ref > 0 then return ref end
		return entityOf[ref]
	end
	local total = 0
	for i, e in ipairs(accepted) do
		local ax, ay = pos(e.a)
		local bx, by = pos(e.b)
		local az, bz = zAt(e.a), zAt(e.b)
		local L = e.arc or G.dist(ax, ay, bx, by)
		local d0x, d0y, d1x, d1y = e.d0[1], e.d0[2], e.d1[1], e.d1[2]
		local dz = bz - az
		local r = G.round
		local edge = {
			entity = -i, node0 = ent(e.a), node1 = ent(e.b), class = e.class, template = templates[e.class],
			through = streets[e.street] and streets[e.street].through or nil,
			p0 = { r(ax), r(ay), r(az) }, p1 = { r(bx), r(by), r(bz) },
			t0 = { r(d0x * L), r(d0y * L), r(dz) }, t1 = { r(d1x * L), r(d1y * L), r(dz) },
			length = L, street = e.street, key = streets[e.street] and streets[e.street].key or nil,
			origin = streets[e.street] and streets[e.street].origin or nil,
			sideFree = streets[e.street] and streets[e.street].sideFree or nil,
		}
		total = total + L
		inc.edges[#inc.edges + 1] = edge
		if e.a > 0 then inc.joins[#inc.joins + 1] = { node = e.a, edge = -i } end
		if e.b > 0 then inc.joins[#inc.joins + 1] = { node = e.b, edge = -i } end
	end
	inc.stats = { edges = #inc.edges, nodes = #inc.nodes, length = total }
	return inc
end

--- Drops edges from a planned increment (drop = { [edge index] = true }) and every edge left without a path to the
--- existing network (an increment without joins keeps its biggest piece); renumbers the entities (edges -1..-E, then the
--- used new nodes) and the joins. In place; returns inc and the number of edges removed. (2026-10-14 late: the straight
--- run guard, ot_check.straightRuns.)
function M.dropEdges(inc, drop)
	local keep = {}
	for i, e in ipairs(inc.edges) do if not drop[i] then keep[#keep + 1] = e end end
	-- connectivity over node entity ids (existing > 0)
	local parent = {}
	local function find(x)
		local r = x
		for _ = 1, 100000 do
			if parent[r] == nil or parent[r] == r then break end
			r = parent[r]
		end
		return r
	end
	local function union(a, b)
		parent[a] = parent[a] or a
		parent[b] = parent[b] or b
		local ra, rb = find(a), find(b)
		if ra ~= rb then parent[ra] = rb end
	end
	for _, e in ipairs(keep) do union(e.node0, e.node1) end
	local good, any = {}, false
	for _, e in ipairs(keep) do
		if e.node0 > 0 then good[find(e.node0)] = true; any = true end
		if e.node1 > 0 then good[find(e.node1)] = true; any = true end
	end
	if not any and #keep > 0 then
		local size = {}
		for _, e in ipairs(keep) do local r = find(e.node0); size[r] = (size[r] or 0) + 1 end
		local best, bn = nil, -1
		for r, n in pairs(size) do if n > bn or (n == bn and r > best) then best, bn = r, n end end
		good[best] = true
	end
	local kept = {}
	for _, e in ipairs(keep) do if good[find(e.node0)] then kept[#kept + 1] = e end end
	local removed = #inc.edges - #kept
	if removed == 0 then return inc, 0 end
	local E = #kept
	local nodeMap, nextNode = {}, -(E + 1)
	local nodes = {}
	local byEnt = {}
	for _, n in ipairs(inc.nodes) do byEnt[n.entity] = n end
	local function mapNode(id)
		if id > 0 then return id end
		if nodeMap[id] == nil then
			local n = byEnt[id]
			nodeMap[id] = nextNode
			nodes[#nodes + 1] = { entity = nextNode, x = n.x, y = n.y, z = n.z }
			nextNode = nextNode - 1
		end
		return nodeMap[id]
	end
	local joins, total = {}, 0
	-- (nodes first in the old order, so the renumbering is stable)
	local usedOld = {}
	for _, e in ipairs(kept) do usedOld[e.node0] = true; usedOld[e.node1] = true end
	for _, n in ipairs(inc.nodes) do if usedOld[n.entity] then mapNode(n.entity) end end
	for i, e in ipairs(kept) do
		e.entity = -i
		e.node0, e.node1 = mapNode(e.node0), mapNode(e.node1)
		if e.node0 > 0 then joins[#joins + 1] = { node = e.node0, edge = -i } end
		if e.node1 > 0 then joins[#joins + 1] = { node = e.node1, edge = -i } end
		total = total + (e.length or 0)
	end
	inc.edges, inc.nodes, inc.joins = kept, nodes, joins
	inc.stats = { edges = #kept, nodes = #nodes, length = total }
	return inc, removed
end

--- Walks every number in an increment; true when none is -0 (tests, and a guard before sending).
function M.noNegativeZero(inc)
	local function bad(v) return v == 0 and 1 / v < 0 end
	for _, n in ipairs(inc.nodes) do
		if bad(n.x) or bad(n.y) or bad(n.z) then return false end
	end
	for _, e in ipairs(inc.edges) do
		for _, v in ipairs({ e.p0, e.p1, e.t0, e.t1 }) do
			for k = 1, 3 do if bad(v[k]) then return false end end
		end
	end
	return true
end

return M
