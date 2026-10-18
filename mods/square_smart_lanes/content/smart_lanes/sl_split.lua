-- Smart Lanes: splitting a roundabout's ring edges so the default spiral gets its mid nodes (PLAN.md "Default: the
-- mid-node spiral", "Smart Lanes adds the mid nodes"). Placed from the construction menu, the game joins the plain
-- ring nodes of a dissolved construction away where the pieces are short (docs/findings/roads.md "Menu placements
-- join short ring pieces"), so Smart Lanes splits each entry-to-exit stretch that has no plain node itself: the
-- stretch's one edge is removed and its two exact halves are added, with a new node at the middle. Pure: the
-- geometry and the choice of edges; sl_write W.splitProposal reads the components and builds the proposal.
-- Lua 5.1 syntax.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local S = {}

S.MIN_PIECE = 8      -- m: both halves of a split edge at least this long (else refused: "short")
S.MAX_EDGES = 8      -- edges one ring split may touch (a ring has at most 32 segments; 4 arms: 4)

--- Point of the cubic Hermite curve p0, t0, p1, t1 (tables {x, y, z}) at s in [0, 1].
function S.hermite(p0, t0, p1, t1, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local out = {}
	for _, k in ipairs({ "x", "y", "z" }) do
		out[k] = h00 * (p0[k] or 0) + h10 * (t0[k] or 0) + h01 * (p1[k] or 0) + h11 * (t1[k] or 0)
	end
	return out
end

--- Derivative of that curve at s (d/ds).
function S.deriv(p0, t0, p1, t1, s)
	local s2 = s * s
	local d00, d10, d01, d11 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
	local out = {}
	for _, k in ipairs({ "x", "y", "z" }) do
		out[k] = d00 * (p0[k] or 0) + d10 * (t0[k] or 0) + d01 * (p1[k] or 0) + d11 * (t1[k] or 0)
	end
	return out
end

local function scale(v, f) return { x = v.x * f, y = v.y * f, z = (v.z or 0) * f } end

--- The two exact halves of an edge's curve: { first = {p0, t0, p1, t1}, second = {...}, mid = point }. A sub-curve of
-- a cubic Hermite on [a, b] is the Hermite with the end points and the derivatives scaled by (b - a): the same shape.
function S.halves(p0, t0, p1, t1)
	local m = S.hermite(p0, t0, p1, t1, 0.5)
	local dm = S.deriv(p0, t0, p1, t1, 0.5)
	return {
		mid = m,
		first = { p0 = p0, t0 = scale(t0, 0.5), p1 = m, t1 = scale(dm, 0.5) },
		second = { p0 = m, t0 = scale(dm, 0.5), p1 = p1, t1 = scale(t1, 0.5) },
	}
end

--- Length of a curve (polyline of 16 pieces).
function S.length(c)
	local total, prev = 0, c.p0
	for i = 1, 16 do
		local q = S.hermite(c.p0, c.t0, c.p1, c.t1, i / 16)
		total = total + math.sqrt((q.x - prev.x) ^ 2 + (q.y - prev.y) ^ 2 + ((q.z or 0) - (prev.z or 0)) ^ 2)
		prev = q
	end
	return total
end

--- The ring edges to split so every stretch from a junction with entries to the next one with exits (the stretches
-- Rules.splitMids needs a plain node on) has one: the stretch's edge when it is a single edge without a plain node.
-- ring: sl_ring findRing result; views: { [node] = nodeView }. Returns { {seg, from, to} } in ring order, or nil and
-- why: "no_stretch" (nothing to split), "too_many" (more than MAX_EDGES), "short" (a half under MIN_PIECE m, by the
-- world's segment length). Bounded by the ring's nodes.
function S.edges(world, ring, views)
	local nodes, segs = ring.nodes, ring.segs
	local n = #nodes
	local out = {}
	for i = 1, n do
		local v = views[nodes[i]]
		local nxt = views[nodes[i % n + 1]]
		-- a stretch of one edge: two junctions next to each other on the ring
		if v and nxt and v.kind ~= "plain" and nxt.kind ~= "plain" and #(v.e or {}) > 0 and #(nxt.x or {}) > 0 then
			local s = world.seg(segs[i])
			if s == nil then return nil, "no_segment" end
			if Ring.segLength(s) / 2 < S.MIN_PIECE then return nil, "short" end
			out[#out + 1] = { seg = segs[i], from = nodes[i], to = nodes[i % n + 1] }
		end
	end
	if #out == 0 then return nil, "no_stretch" end
	if #out > S.MAX_EDGES then return nil, "too_many" end
	return out
end

--- Per-session cap: a ring (by key) is split at most MAX_PER_RING times (a later build that joins the nodes again
-- gets one more split, never a loop). counts: the caller's table { [ringKey] = n }.
S.MAX_PER_RING = 2
function S.allowed(counts, key)
	return (counts[key] or 0) < S.MAX_PER_RING
end

return S
