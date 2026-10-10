-- Shared geometry checks for the square_roundabouts tests (not a test file itself).
-- Load with: local checks = loadfile(<dir> .. "checks.lua", "t", _ENV)()
-- Each check returns a list of problem strings (empty = fine), so a test can report them all.
--
-- Works on the pure geometry output: lists = {{role, halfWidth, edges = {{p0, t0, p1, t1, tag0, tag1}}}}.

local checks = {}

--- 3D dot product (geom.shapes.dot is plan-only: it ignores z; shapes.len / norm / dist are 3D).
function checks.dot3(p, q) return p[1] * q[1] + p[2] * q[2] + (p[3] or 0) * (q[3] or 0) end

--- A test-only view of geom.shapes whose `dot` fails loudly where plan-only and 3D disagree
-- (both vectors have a z component, e.g. two climbing tangents: S.dot(S.norm(t0), S.norm(t1))
-- is then < 1 for parallel tangents). Say what is meant instead: S.pdot (plan, the mod's
-- S.dot) or S.dot3. Mod code keeps the plain module; only the test's local S changes:
--   local S = checks.strictShapes(geom.shapes)
function checks.strictShapes(shapes)
	local strict = setmetatable({}, { __index = shapes })
	strict.pdot = shapes.dot
	strict.dot3 = checks.dot3
	function strict.dot(p, q)
		if (p[3] or 0) * (q[3] or 0) ~= 0 then
			error("S.dot ignores z but both vectors have one (" .. tostring(p[3]) .. ", " .. tostring(q[3])
				.. "): use S.dot3 (3D) or S.pdot (plan)", 2)
		end
		return shapes.dot(p, q)
	end
	return strict
end

local function sub(p, q) return { p[1] - q[1], p[2] - q[2], (p[3] or 0) - (q[3] or 0) } end
local function len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + (v[3] or 0) * (v[3] or 0)) end
local function dist(p, q) return len(sub(p, q)) end
local function dot(p, q) return p[1] * q[1] + p[2] * q[2] end
-- plan distance (footprints are 2D: an elevated road's band is checked in plan, heights apart)
local function dist2(p, q) local dx, dy = p[1] - q[1], p[2] - q[2]; return math.sqrt(dx * dx + dy * dy) end
local function norm(v) local l = len(v); return { v[1] / l, v[2] / l, 0 } end

local function hermite(e, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local d00, d10, d01, d11 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
	local p, d = {}, {}
	for i = 1, 3 do
		p[i] = h00 * e.p0[i] + h10 * e.t0[i] + h01 * e.p1[i] + h11 * e.t1[i]
		d[i] = d00 * e.p0[i] + d10 * e.t0[i] + d01 * e.p1[i] + d11 * e.t1[i]
	end
	return p, d
end
checks.hermite = hermite

function checks.edgeLength(e)
	-- hermite() positions and dist() inline (same arithmetic, no tables): 64 chords
	local p0, t0, p1, t1 = e.p0, e.t0, e.p1, e.t1
	local ax, ay, az = p0[1], p0[2], p0[3]
	local total = 0
	for k = 1, 64 do
		local s = k / 64
		local s2, s3 = s * s, s * s * s
		local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
		local x = h00 * p0[1] + h10 * t0[1] + h01 * p1[1] + h11 * t1[1]
		local y = h00 * p0[2] + h10 * t0[2] + h01 * p1[2] + h11 * t1[2]
		local z = h00 * p0[3] + h10 * t0[3] + h01 * p1[3] + h11 * t1[3]
		local dx, dy, dz = ax - x, ay - y, (az or 0) - z
		total = total + math.sqrt(dx * dx + dy * dy + dz * dz)
		ax, ay, az = x, y, z
	end
	return total
end

--- Flattened edges with their list's role and half width.
function checks.edges(lists)
	local out = {}
	for li, l in ipairs(lists) do
		for ei, e in ipairs(l.edges) do
			out[#out + 1] = { e = e, hw = l.halfWidth, role = l.role, name = l.role .. "#" .. ei, list = li,
				bridge = l.edgeType == "BRIDGE" }
		end
	end
	return out
end

--- Every tag sits at one position; entries at one position share one tag; every tag is used by
-- at least two node entries (otherwise it merges nothing).
function checks.tags(lists)
	local problems, pos, count, nodes = {}, {}, {}, {}
	for _, l in ipairs(lists) do
		for _, e in ipairs(l.edges) do
			for _, n in ipairs({ { e.p0, e.tag0 }, { e.p1, e.tag1 } }) do
				nodes[#nodes + 1] = n
				if n[2] then
					count[n[2]] = (count[n[2]] or 0) + 1
					if pos[n[2]] and dist(pos[n[2]], n[1]) > 1e-9 then
						problems[#problems + 1] = "tag " .. n[2] .. " at two positions"
					end
					pos[n[2]] = pos[n[2]] or n[1]
				end
			end
		end
	end
	for tag, c in pairs(count) do
		if c < 2 then problems[#problems + 1] = "tag " .. tag .. " used once" end
	end
	for i = 1, #nodes do
		for j = i + 1, #nodes do
			if dist(nodes[i][1], nodes[j][1]) < 1e-6 and nodes[i][2] ~= nodes[j][2] then
				problems[#problems + 1] = "nodes at one position with tags " .. tostring(nodes[i][2]) .. " / " .. tostring(nodes[j][2])
			end
		end
	end
	return problems
end

function checks.lengths(lists, min)
	local problems = {}
	for _, x in ipairs(checks.edges(lists)) do
		local l = checks.edgeLength(x.e)
		if l < min - 1e-6 then problems[#problems + 1] = x.name .. " is " .. string.format("%.2f", l) .. " m" end
	end
	return problems
end

local function samples(x, spacing, length)
	local n = math.max(4, math.ceil((length or checks.edgeLength(x.e)) / spacing))
	local pts = {}
	for k = 0, n do
		local p, d = hermite(x.e, k / n)
		pts[#pts + 1] = { p = p, t = norm(d) }
	end
	return pts
end

local function bbox(pts, pad)
	local b = { math.huge, math.huge, -math.huge, -math.huge }
	for _, s in ipairs(pts) do
		b[1], b[2] = math.min(b[1], s.p[1] - pad), math.min(b[2], s.p[2] - pad)
		b[3], b[4] = math.max(b[3], s.p[1] + pad), math.max(b[4], s.p[2] + pad)
	end
	return b
end

local function segDist(q, a, b)
	local ab = sub(b, a)
	local l2 = dot(ab, ab)
	local s = l2 > 0 and math.max(0, math.min(1, dot(sub(q, a), ab) / l2)) or 0
	return dist2(q, { a[1] + ab[1] * s, a[2] + ab[2] * s, 0 })
end

--- Distance from point q to the road footprint of edge A (a band of half width hwA that ends
-- square at the edge's end nodes), from A's samples.
-- Boxes of runs of 16 samples (cached on the edge record): {minx, miny, maxx, maxy, first, last}.
-- A run starts at a sample index = 1 (mod 4), so it holds whole steps of the coarse pass below.
local function sampleRuns(A)
	if A.runs then return A.runs end
	local pts, runs = A.pts, {}
	for c = 1, #pts, 16 do
		local last = math.min(c + 15, #pts)
		local b = { math.huge, math.huge, -math.huge, -math.huge, c, last }
		for k = c, last do
			local p = pts[k].p
			if p[1] < b[1] then b[1] = p[1] end
			if p[2] < b[2] then b[2] = p[2] end
			if p[1] > b[3] then b[3] = p[1] end
			if p[2] > b[4] then b[4] = p[2] end
		end
		runs[#runs + 1] = b
	end
	A.runs = runs
	return runs
end

-- squared plan distance from (x, y) to a run's box (a lower bound for any sample in it)
local function boxDist2(b, x, y)
	local dx = b[1] - x
	if dx < 0 then dx = x - b[3]; if dx < 0 then dx = 0 end end
	local dy = b[2] - y
	if dy < 0 then dy = y - b[4]; if dy < 0 then dy = 0 end end
	return dx * dx + dy * dy
end

local function footprintDist(A, q, hint)
	-- coarse pass over every 4th sample, then refine around the best one (edges are smooth and
	-- shorter than their curvature radius, so the distance along them is unimodal enough).
	-- A run whose box is no closer than the best so far cannot improve it (same result as
	-- scanning every coarse sample: only strictly smaller distances replace the best).
	-- (squared distances inline: the same order as dist2, so the same samples win)
	local pts = A.pts
	local qx, qy = q[1], q[2]
	local best, bk = math.huge, 1
	local runs = sampleRuns(A)
	-- hint: a coarse sample index (from a nearby query). Its distance bounds the coarse minimum, so
	-- runs farther than it are skipped too; the scan order and the strict "<" are unchanged, so the
	-- first coarse sample at the minimum still wins.
	local bound = math.huge
	if hint then
		local p = pts[hint].p
		local dx, dy = p[1] - qx, p[2] - qy
		bound = dx * dx + dy * dy
	end
	for ri = 1, #runs do
		local r = runs[ri]
		local rb = boxDist2(r, qx, qy)
		if rb < best and rb <= bound then
			for k = r[5], r[6], 4 do
				local p = pts[k].p
				local dx, dy = p[1] - qx, p[2] - qy
				local d = dx * dx + dy * dy
				if d < best then best, bk = d, k end
			end
		end
	end
	local coarse = bk
	local lo, hi = math.max(1, bk - 4), math.min(#pts, bk + 4)
	for k = lo, hi do
		local p = pts[k].p
		local dx, dy = p[1] - qx, p[2] - qy
		local d = dx * dx + dy * dy
		if d < best then best, bk = d, k end
	end
	best = math.sqrt(best)
	local s = A.pts[bk]
	local along = (qx - s.p[1]) * s.t[1] + (qy - s.p[2]) * s.t[2]
	if (bk == 1 and along < 0) or (bk == #A.pts and along > 0) then
		local n = { -s.t[2], s.t[1], 0 }
		return segDist(q, { s.p[1] - n[1] * A.hw, s.p[2] - n[2] * A.hw, 0 }, { s.p[1] + n[1] * A.hw, s.p[2] + n[2] * A.hw, 0 }), coarse
	end
	return best - A.hw, coarse
end
checks.footprintDist = footprintDist

--- True if the cross-section of Q's band at sample s comes within margin of P's band. The disc
-- of radius hwQ around s decides first (cheap); a hit is confirmed on the cross-section segment,
-- so a band does not poke out behind its own end node.
local function bandHits(P, Q, s, margin)
	-- fast reject (same verdict): P.box is P's samples padded by P.hw + margin, and P's band lies
	-- within P.hw of its samples, so a point more than Q.hw outside that box is clear of it
	local b, pad, x, y = P.box, Q.hw + 1e-3, s.p[1], s.p[2]
	if x < b[1] - pad or x > b[3] + pad or y < b[2] - pad or y > b[4] + pad then return false end
	-- the same bound per run of P's samples (P's box is loose around curved or diagonal edges)
	local reach, near = P.hw + Q.hw + margin + 1e-3, false
	reach = reach * reach
	for _, r in ipairs(sampleRuns(P)) do
		if boxDist2(r, x, y) < reach then near = true; break end
	end
	if not near then return false end
	local d0, hint = footprintDist(P, s.p)
	if d0 >= Q.hw + margin - 1e-6 then return false end
	-- the centre is one of the cross-section points below (k = 0): the verdict is "any point hits"
	if d0 < margin - 1e-6 then return true end
	local n = { -s.t[2], s.t[1], 0 }
	local steps = math.max(2, math.ceil(Q.hw))
	for k = -steps, steps do
		local o = Q.hw * k / steps
		if footprintDist(P, { s.p[1] + n[1] * o, s.p[2] + n[2] * o, 0 }, hint) < margin - 1e-6 then return true end
	end
	return false
end

--- No two road footprints overlap, except in a junction: edges that share a node may overlap in
-- one stretch that starts at that node (where they fork or meet), at most `maxJunction` (default:
-- max(30 m, 1.2 x the sum of the half widths)) long
-- along each edge. Once they are clear they must stay clear. Edges without a shared node must
-- never overlap. skip(A, B) may exempt a pair (documented exceptions). maxJunction may be a
-- number (every pair) or a function(A, B, default) returning the limit for a pair (A, B: edge
-- records with e, hw, role, name).
function checks.overlaps(lists, margin, skip, maxJunction)
	margin = margin or 0.5
	-- a junction stretch grows with the roads' widths: 30 m, or 1.2 x the sum of the half widths
	-- for wide pairs (a 6-lane road crossing a 4-lane ring)
	local function limit(A, B)
		local default = math.max(30, 1.2 * (A.hw + B.hw))
		if type(maxJunction) == "function" then return maxJunction(A, B, default) end
		if maxJunction then return maxJunction end
		return default
	end
	local problems = {}
	local xs = checks.edges(lists)
	for _, x in ipairs(xs) do
		x.length = checks.edgeLength(x.e)
		x.pts = samples(x, 1.0, x.length)
		x.box = bbox(x.pts, x.hw + margin)
	end
	for i = 1, #xs do
		for j = i + 1, #xs do
			local A, B = xs[i], xs[j]
			local overlapBox = A.box[1] <= B.box[3] and B.box[1] <= A.box[3] and A.box[2] <= B.box[4] and B.box[2] <= A.box[4]
			if overlapBox and not (skip and skip(A, B)) then
				local bad
				for _, pair in ipairs({ { A, B }, { B, A } }) do
					local P, Q = pair[1], pair[2]
					-- walk Q's samples from each end; a shared end may start a junction stretch
					local n = #Q.pts
					local flags = {}
					for k = 1, n do flags[k] = bandHits(P, Q, Q.pts[k], margin) end
					-- a shared end: the same position, or the same tag (a tag merge of nodes that are
					-- not at one position: the interchange's slip roads, base diamond pattern)
					local function same(q, qt, p, pt) return dist(q, p) < 1e-6 or (qt ~= nil and qt == pt) end
					local shared0 = same(Q.e.p0, Q.e.tag0, P.e.p0, P.e.tag0) or same(Q.e.p0, Q.e.tag0, P.e.p1, P.e.tag1)
					local shared1 = same(Q.e.p1, Q.e.tag1, P.e.p0, P.e.tag0) or same(Q.e.p1, Q.e.tag1, P.e.p1, P.e.tag1)
					local lo, hi = 1, n
					if shared0 then while lo <= n and flags[lo] do lo = lo + 1 end end
					if shared1 then while hi >= 1 and flags[hi] do hi = hi - 1 end end
					local step = Q.length / (n - 1)
					local lim = limit(P, Q)
					if (lo - 1) * step > lim or (n - hi) * step > lim then
						bad = string.format("%s / %s junction stretch longer than %.1f m", P.name, Q.name, lim)
					end
					for k = lo, hi do
						if not bad and flags[k] then
							local p = Q.pts[k].p
							bad = string.format("%s / %s overlap at (%.1f, %.1f): centreline %.2f m from the other band (half width %.1f)",
								P.name, Q.name, p[1], p[2], footprintDist(P, p), Q.hw)
						end
					end
					if bad then break end
				end
				if bad then problems[#problems + 1] = bad end
			end
		end
	end
	return problems
end

--- Skip function for checks.overlaps on layouts with two levels (Roundabout Interchange): a pair
-- whose bands come within `margin` of each other in plan is skipped when, at every such place,
-- their heights differ by at least `minSep` and the higher one is a bridge edge (its list has
-- edgeType "BRIDGE"). Any other pair is checked in 2D as before, so an elevated road on an
-- embankment over another road, or a crossing with too little clearance, still fails. `stats`
-- (optional): stats.crossings counts the skipped pairs, stats.minSep the smallest separation seen.
function checks.levelSkip(minSep, margin, stats)
	margin = margin or 0.5
	stats = stats or {}
	return function(A, B)
		local near, okAll, sep = false, true, math.huge
		local reach = A.hw + B.hw + margin
		local bb = B.box -- B's samples' bounding box, padded by B.hw + the overlap margin
		for _, a in ipairs(A.pts) do
			local ax, ay = a.p[1], a.p[2]
			local inBox = ax >= bb[1] - A.hw and ax <= bb[3] + A.hw and ay >= bb[2] - A.hw and ay <= bb[4] + A.hw
			for _, b in ipairs(inBox and B.pts or {}) do
				local dx, dy = ax - b.p[1], ay - b.p[2]
				if dx * dx + dy * dy < reach * reach then
					near = true
					local dz = a.p[3] - b.p[3]
					local upperBridge = (dz > 0 and A.bridge) or (dz < 0 and B.bridge)
					if math.abs(dz) < minSep or not upperBridge then okAll = false end
					sep = math.min(sep, math.abs(dz))
				end
			end
			if not okAll then break end
		end
		if near and okAll then
			stats.crossings = (stats.crossings or 0) + 1
			stats.minSep = math.min(stats.minSep or math.huge, sep)
		end
		return near and okAll
	end
end

--- Every island outline vertex keeps at least `gap` from every road footprint.
function checks.islandClear(lists, island, gap)
	local problems = {}
	if not island then return problems end
	local xs = checks.edges(lists)
	for _, x in ipairs(xs) do
		x.pts = samples(x, 1.0)
		x.box = bbox(x.pts, x.hw + gap)
	end
	for fi, f in ipairs(island.faces) do
		for _, p in ipairs(f.outline) do
			for _, x in ipairs(xs) do
				local inBox = p[1] >= x.box[1] and p[1] <= x.box[3] and p[2] >= x.box[2] and p[2] <= x.box[4]
				local d = inBox and footprintDist(x, p) or math.huge
				if d < gap then
					problems[#problems + 1] = string.format("face %d vertex (%.1f, %.1f) %.2f m from %s", fi, p[1], p[2], d, x.name)
					break
				end
			end
		end
	end
	return problems
end

-- Construction results (any entry's updateFn output) -----------------------------------------
-- These work on the result table the game receives (edgeLists of {position, tangent, tag?}
-- entries, two per edge), so every menu entry that goes through square_roundabouts_result.lua
-- (main, Magic and the Phase 5 entries) is checked the same way (PHASE5.md Phase 5a).

--- Short edges and near-coincident nodes: no edge has a chord or Hermite length under `minLen`
-- (default 1 m), and no two distinct nodes lie within `minGap` (default 0.5 m) of each other in
-- 3D. A node is one position + tag: untagged entries at the same position are one node (the engine
-- merges them), entries sharing a tag merge on purpose (checks.tags keeps a tag at one position).
-- Two nodes closer than minGap with different tags (or one untagged) would not merge but sit on
-- top of each other. `stats` (optional) keeps the shortest edge (stats.len) and the closest pair
-- of distinct nodes (stats.gap) seen.
function checks.shortEdges(res, minLen, minGap, stats)
	minLen, minGap = minLen or 1.0, minGap or 0.5
	stats = stats or {}
	local problems, nodes, byTag = {}, {}, {}
	local function node(entry)
		local p, tag = entry[1], entry[3]
		-- the duplicates of a node carry its tag: search that tag's nodes only
		local same = byTag[tag or false]
		if not same then same = {}; byTag[tag or false] = same end
		for _, n in ipairs(same) do
			if dist(n.p, p) < 1e-6 then return end
		end
		local n = { p = p, tag = tag, i = #nodes + 1 }
		nodes[#nodes + 1] = n
		same[#same + 1] = n
	end
	for li, el in ipairs(res.edgeLists or {}) do
		local type = el.params and el.params.type or "?"
		for i = 1, #el.edges, 2 do
			local a, b = el.edges[i], el.edges[i + 1]
			local e = { p0 = a[1], t0 = a[2], p1 = b[1], t1 = b[2] }
			local chord, l = dist(e.p0, e.p1), checks.edgeLength(e)
			stats.len = math.min(stats.len or math.huge, chord, l)
			if chord < minLen - 1e-9 or l < minLen - 1e-9 then
				problems[#problems + 1] = string.format("edgeList %d (%s) edge %d: chord %.2f m, length %.2f m (< %.1f)",
					li, type, (i + 1) / 2, chord, l, minLen)
			end
			node(a); node(b)
		end
	end
	-- every pair closer than max(closest so far, minGap), by a sweep over x: the same closest
	-- distance and the same problem pairs as checking every pair (listed in x order)
	table.sort(nodes, function(a, b) return a.p[1] < b.p[1] end)
	local best = math.huge
	for i = 1, #nodes do
		local A = nodes[i]
		local j = i + 1
		while j <= #nodes and nodes[j].p[1] - A.p[1] < math.max(best, minGap) do
			local B = nodes[j]
			if not (A.tag and A.tag == B.tag) then
				local d = dist(A.p, B.p)
				if d < best then best = d end
				if d < minGap then
					local P, Q = A, B
					if Q.i < P.i then P, Q = Q, P end -- named in insertion order, as before
					problems[#problems + 1] = string.format("nodes %.2f m apart at (%.1f, %.1f, %.1f), tags %s / %s",
						d, P.p[1], P.p[2], P.p[3] or 0, tostring(P.tag), tostring(Q.tag))
				end
			end
			j = j + 1
		end
	end
	if best < math.huge then stats.gap = math.min(stats.gap or math.huge, best) end
	return problems
end

-- yearFrom of every base street template, bridge and tunnel an entry may emit (each file's
-- `availability.yearFrom`, base content/infrastructure/street/*/, bridge/, tunnel/; PHASE5.md
-- "Phase 5a notes", spike 3). A template missing here fails checks.latestYear, so a new entry
-- that adds one has to look its year up.
local STREET = "::/infrastructure/street/"
checks.YEAR_FROM = {
	[STREET .. "highway/highway_new_small.street_template"] = 1940,
	[STREET .. "highway/highway_new_medium.street_template"] = 1940,
	[STREET .. "highway/highway_new_large.street_template"] = 1940,
	[STREET .. "town/town_new_one_way_xsmall.street_template"] = 1940,
	[STREET .. "town/town_new_one_way_small.street_template"] = 1940,
	[STREET .. "town/town_new_one_way_medium.street_template"] = 1940,
	[STREET .. "town/town_new_one_way_small_tram_electrified.street_template"] = 1940,
	[STREET .. "town/town_new_one_way_medium_tram_electrified.street_template"] = 1940,
	[STREET .. "town/town_new_small.street_template"] = 1940,
	[STREET .. "town/town_new_medium.street_template"] = 1940,
	[STREET .. "town/town_new_large.street_template"] = 1940,
	[STREET .. "town/town_new_small_tram_electrified.street_template"] = 1940,
	[STREET .. "town/town_new_medium_tram_electrified.street_template"] = 1940,
	[STREET .. "town/town_new_large_tram_electrified.street_template"] = 1940,
	[STREET .. "country/country_new_small.street_template"] = 1940,
	[STREET .. "country/country_new_medium.street_template"] = 1940,
	[STREET .. "country/country_new_large.street_template"] = 1940,
	[STREET .. "tram/tram_new.street_template"] = 1925,
	-- old era (yearTo 1940) and the station entrance one-way (yearFrom 0): not used yet
	[STREET .. "town/town_old_small.street_template"] = 0,
	[STREET .. "town/town_old_medium.street_template"] = 0,
	[STREET .. "town/town_old_large.street_template"] = 0,
	[STREET .. "country/country_old_small.street_template"] = 0,
	[STREET .. "country/country_old_medium.street_template"] = 0,
	[STREET .. "country/country_old_large.street_template"] = 0,
	[STREET .. "constructions/entrance_old_one_way.street_template"] = 0,
	-- bridges and tunnels (edgeTypeName)
	["::/infrastructure/bridge/stone.bridge"] = 0,
	["::/infrastructure/bridge/steel.bridge"] = 1940,
	["::/infrastructure/bridge/concrete.bridge"] = 1970,
	["::/infrastructure/tunnel/tunnel_a_car.tunnel"] = 1900,
	["::/infrastructure/tunnel/tunnel_b_car.tunnel"] = 1970,
}

--- The latest yearFrom over every template and bridge/tunnel type in a result, plus problems for
-- unknown ones. `seen` (optional) collects the names.
function checks.latestYear(res, seen)
	local latest, problems = 0, {}
	for _, el in ipairs(res.edgeLists or {}) do
		for _, name in ipairs({ el.params and el.params.type, el.edgeTypeName }) do
			if name then
				local y = checks.YEAR_FROM[name]
				if not y then
					problems[#problems + 1] = "no yearFrom known for " .. name
				else
					latest = math.max(latest, y)
				end
				if seen then seen[name] = true end
			end
		end
	end
	return latest, problems
end

--- Negative zeros in a construction result (docs/findings.md "Negative zero in construction geometry",
-- 2026-10-09). The UI builder's 0-degree transf is (cos, sin) = (1, -0): a tangent (+x, -0) or (-0, -y)
-- stays -0 in world space, and the engine refused a layout for exactly that at Rotation 0 only. A +0
-- identity transf (every script probe) and the goldens (G.serialize prints -0 as 0) hide it.
-- res = the updateFn result ({edgeLists = {{edges = {{p, t}, ...}}}}). Returns problems (world -0
-- tangent components, the refusal pattern), the world count and the raw count (any -0 in a position
-- or tangent; common and harmless in released entries, e.g. tangent z = -0).
function checks.isNeg0(v) return v == 0 and 1 / v < 0 end
function checks.negativeZeros(res)
	local problems, raw = {}, 0
	local z = 0.0
	local c, s = 1.0, -z -- the builder's transf at 0 degrees (sin = -0, computed at run time)
	for li, el in ipairs(res.edgeLists or {}) do
		local type = el.params and el.params.type or "?"
		for i, pt in ipairs(el.edges or {}) do
			for _, v in ipairs({ pt[1], pt[2] }) do
				for k = 1, 3 do if checks.isNeg0(v[k]) then raw = raw + 1 end end
			end
			local t = pt[2]
			local wx, wy = c * t[1] - s * t[2], s * t[1] + c * t[2]
			if checks.isNeg0(wx) or checks.isNeg0(wy) then
				problems[#problems + 1] = string.format("edgeList %d (%s) entry %d tangent (%.17g, %.17g) -> world (%s, %s) at 0 deg",
					li, type, i, t[1], t[2], checks.isNeg0(wx) and "-0" or "ok", checks.isNeg0(wy) and "-0" or "ok")
			end
		end
	end
	return problems, #problems, raw
end

function checks.report(problems, what)
	if #problems > 0 then
		local shown = {}
		for i = 1, math.min(5, #problems) do shown[i] = problems[i] end
		error((what and (what .. ": ") or "") .. #problems .. " problem(s): " .. table.concat(shown, "; "), 2)
	end
end

-- Junction model ------------------------------------------------------------------------------
-- How the engine shapes a junction is not visible to scripts. This approximates it the usual way:
-- at a node, neighbouring roads (in angular order) meet at a kerb corner, the intersection of
-- the facing kerbs (each road's kerb curve, extended straight behind the node). Each road is cut
-- back to its corner(s); what is left between the junctions at both ends is the edge's free
-- length. In game (2026-10-07) a junction that eats (almost) a whole edge fails with
-- "Construction not possible": see PLAN.md "Phase 3b notes" for the calibration.

local function kerb(x, atStart, side, back, step)
	-- polyline of {p, d}: kerb points on `side` (+1 left, -1 right of the direction away from the
	-- node) with the signed centreline distance d from the node (negative behind it)
	local e, hw = x.e, x.hw
	local n = math.max(8, math.ceil(checks.edgeLength(e) / (step or 0.5)))
	local pts, total, prev = {}, 0, nil
	local first
	for k = 0, n do
		local s = atStart and (k / n) or (1 - k / n)
		local p, d = hermite(e, s)
		if not atStart then d = { -d[1], -d[2], -d[3] } end
		d = norm(d)
		if prev then total = total + dist(prev, p) end
		prev = p
		local l = { -d[2], d[1], 0 }
		if k == 0 then first = { p = p, d = d, l = l } end
		pts[#pts + 1] = { p = { p[1] + l[1] * hw * side, p[2] + l[2] * hw * side, 0 }, d = total }
	end
	local out = {}
	local m = math.ceil(back / 1.0)
	for k = m, 1, -1 do
		local b = back * k / m
		local q = first.p
		out[#out + 1] = { p = { q[1] - first.d[1] * b + first.l[1] * hw * side, q[2] - first.d[2] * b + first.l[2] * hw * side, 0 }, d = -b }
	end
	for _, pt in ipairs(pts) do out[#out + 1] = pt end
	return out, first.d
end

local function cross2(a, b) return a[1] * b[2] - a[2] * b[1] end

-- Bounding boxes of runs of CHUNK segments of a kerb polyline (cached on it): kerbCrossing skips
-- a pair of runs whose boxes are apart, which skips only segment pairs the per-pair test skips too.
local CHUNK = 16
local function chunks(k)
	if k.chunks then return k.chunks end
	local out = {}
	for c = 1, #k - 1, CHUNK do
		local last = math.min(c + CHUNK, #k)
		local b = { math.huge, math.huge, -math.huge, -math.huge, c, last - 1 }
		for i = c, last do
			local p = k[i].p
			if p[1] < b[1] then b[1] = p[1] end
			if p[2] < b[2] then b[2] = p[2] end
			if p[1] > b[3] then b[3] = p[1] end
			if p[2] > b[4] then b[4] = p[2] end
		end
		out[#out + 1] = b
	end
	k.chunks = out
	return out
end

--- First crossing of two kerb polylines (smallest positive cut sum). Returns dA, dB or nil.
local function kerbCrossing(ka, kb)
	local best, bestA, bestB
	local cb = chunks(kb)
	for _, ca in ipairs(chunks(ka)) do
	-- the runs of kb whose boxes meet this run of ka
	local near = {}
	for _, c in ipairs(cb) do
		if not (c[3] < ca[1] or c[1] > ca[3] or c[4] < ca[2] or c[2] > ca[4]) then near[#near + 1] = c end
	end
	for i = ca[5], #near > 0 and ca[6] or 0 do
		local p, r = ka[i].p, sub(ka[i + 1].p, ka[i].p)
		local minx, maxx = math.min(ka[i].p[1], ka[i + 1].p[1]), math.max(ka[i].p[1], ka[i + 1].p[1])
		local miny, maxy = math.min(ka[i].p[2], ka[i + 1].p[2]), math.max(ka[i].p[2], ka[i + 1].p[2])
		for _, c in ipairs(near) do
		for j = c[5], c[6] do
			local q = kb[j].p
			local q2 = kb[j + 1].p
			if not (math.max(q[1], q2[1]) < minx or math.min(q[1], q2[1]) > maxx or math.max(q[2], q2[2]) < miny or math.min(q[2], q2[2]) > maxy) then
				local s = sub(q2, q)
				local den = cross2(r, s)
				if math.abs(den) > 1e-12 then
					local qp = sub(q, p)
					local u = cross2(qp, s) / den
					local v = cross2(qp, r) / den
					if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
						local dA = ka[i].d + (ka[i + 1].d - ka[i].d) * u
						local dB = kb[j].d + (kb[j + 1].d - kb[j].d) * v
						local cost = math.max(dA, 0) + math.max(dB, 0)
						if not best or cost < best then best, bestA, bestB = cost, dA, dB end
					end
				end
			end
		end
		end
	end
	end
	return bestA, bestB
end

--- Junction cut-backs. Returns a list of {x = edge record, cut0, cut1, length, free} and a list
-- of node records {pos, ends = {{x, atStart, angle, cut}}}.
function checks.junctions(lists)
	local xs = checks.edges(lists)
	local nodes = {}
	-- each road end's two kerbs, built once (a road end meets a neighbour on each side)
	local kerbs = {}
	local function kerbOf(x, atStart, side, back)
		local byX = kerbs[x] or {}
		kerbs[x] = byX
		local key = (atStart and "s" or "e") .. side .. ":" .. back
		local k = byX[key]
		if not k then k = kerb(x, atStart, side, back); byX[key] = k end
		return k
	end
	local function nodeAt(p)
		for _, n in ipairs(nodes) do if dist(n.pos, p) < 1e-6 then return n end end
		local n = { pos = p, ends = {} }
		nodes[#nodes + 1] = n
		return n
	end
	for _, x in ipairs(xs) do
		x.cut0, x.cut1 = 0, 0
		x.length = checks.edgeLength(x.e)
		for _, atStart in ipairs({ true, false }) do
			local n = nodeAt(atStart and x.e.p0 or x.e.p1)
			n.ends[#n.ends + 1] = { x = x, atStart = atStart }
		end
	end
	for _, n in ipairs(nodes) do
		local maxHw = 0
		for _, en in ipairs(n.ends) do
			local t = en.atStart and en.x.e.t0 or { -en.x.e.t1[1], -en.x.e.t1[2], 0 }
			en.dir = norm(t)
			en.angle = math.atan(en.dir[2], en.dir[1])
			maxHw = math.max(maxHw, en.x.hw)
		end
		table.sort(n.ends, function(a, b) return a.angle < b.angle end)
		local plain = #n.ends == 2 and dot(n.ends[1].dir, n.ends[2].dir) < -0.9995
		if #n.ends >= 2 and not plain then
			for i, A in ipairs(n.ends) do
				local B = n.ends[i % #n.ends + 1]
				local gap = B.angle - A.angle
				if i == #n.ends then gap = gap + 2 * math.pi end
				if gap < math.pi - 1e-3 then
					local back = 3 * maxHw
					local ka = kerbOf(A.x, A.atStart, 1, back)
					local kb = kerbOf(B.x, B.atStart, -1, back)
					local dA, dB = kerbCrossing(ka, kb)
					if dA then
						for _, pr in ipairs({ { A, dA }, { B, dB } }) do
							local en, d = pr[1], pr[2]
							en.cut = math.max(en.cut or 0, d)
							en.behind = math.min(en.behind or 0, d)
						end
					end
				end
			end
			for _, en in ipairs(n.ends) do
				if en.atStart then en.x.cut0 = math.max(en.x.cut0, en.cut or 0) else en.x.cut1 = math.max(en.x.cut1, en.cut or 0) end
				-- "behind" only for a road that ends here: a ring running on through the node
				-- (another end straight opposite) does not end at it
				local continued = false
				for _, o in ipairs(n.ends) do
					if o ~= en and dot(o.dir, en.dir) < -0.9995 then continued = true end
				end
				if not continued then en.x.behind = math.max(en.x.behind or 0, -(en.behind or 0)) end
			end
		end
	end
	for _, x in ipairs(xs) do x.free = x.length - x.cut0 - x.cut1 end
	return xs, nodes
end

-- Calibration (in game, 2026-10-07; PLAN.md "Phase 3b notes"):
--   * free length: 4.7 m and more worked (Magic, medium arms: 4.7 / 5.6 m; splitter ring 6.8 m),
--     1.6 m and 0.5 m failed (Magic, country / town large arms). geom.JUNCTION_FREE = 4.5.
--   * kerb corner behind a road's node: up to 5.7 m worked (splitter, town medium arm at the
--     split node), 12.7 m and 15.6 m failed (splitter, country / town large). BEHIND_MAX = 6.
checks.BEHIND_MAX = 6.0

--- Every edge keeps at least `minFree` metres outside the junctions at its two ends, and no
-- junction corner lies more than `maxBehind` behind a road's node (a narrow road running along
-- the extended kerb of a much wider one). "Behind" counts only for roads that end at the node,
-- not for a ring that runs on through it.
function checks.junctionRoom(lists, minFree, maxBehind)
	maxBehind = maxBehind or checks.BEHIND_MAX
	local problems = {}
	local xs = checks.junctions(lists)
	for _, x in ipairs(xs) do
		if x.free < minFree - 1e-6 then
			problems[#problems + 1] = string.format("%s (half width %.1f): %.1f m long, junctions take %.1f + %.1f m, %.1f m free (< %.1f)",
				x.name, x.hw, x.length, x.cut0, x.cut1, x.free, minFree)
		end
		if (x.behind or 0) > maxBehind + 1e-6 then
			problems[#problems + 1] = string.format("%s (half width %.1f): a junction corner %.1f m behind its node (> %.1f)",
				x.name, x.hw, x.behind, maxBehind)
		end
	end
	return problems
end

-- Engine-fitted model (Phase 4b, PLAN.md "Phase 4b notes") ------------------------------------
-- Fitted to the probe's 32,704 engine verdicts (search trials: exact dev layouts; the `all` sweep
-- of the Phase 3b geometry), replayed offline by test_replay_report.lua. The Phase 3b thresholds
-- (free 4.5 m, corner behind 6 m for every road) agreed with the engine on 72% of them; these
-- agree on 92%, with 26 false alarms (layouts the engine took that this model rejects).
--   * free length >= 2.5 m: the engine took layouts down to 2.0 m (2.7 m Magic, 2.8 m splitter);
--   * a plain arm's kerb corner at most 1 m behind its node (the engine took 12 arms with more,
--     up to 5.4 m, and rejected 5,697); splitter legs keep the 6 m limit (151 legs accepted
--     between 1 and 5.7 m);
--   * tram line: tram stubs >= 16 m beyond the ring half width and a tram-only middle >= 21 m,
--     or the tram road all the way (search_tram: all 240 calls classified);
--   * neck (a narrower two-way road before the split node): at most 4.5 m narrower (half width)
--     than the arm, and the legs at most 2.5 m wider than the neck (large arms on a small neck
--     and one-way medium legs on a small neck never placed).
checks.ENGINE = {
	free = 2.5, behindArms = 1.0, behindLegs = 6.0,
	tramStub = 16, tramMiddle = 21,
	neckArmDiff = 4.5, neckLegDiff = 2.5,
}

local TRAM_ONLY = "tram/tram_new.street_template"

--- Problems of a layout under the engine-fitted model (empty = the model expects it to place),
-- and checks.junctions' edge records (free lengths), so a test need not run the model twice.
-- ringHalfWidth: the ring road's half width (tram stub length beyond it).
function checks.engineModel(lists, ringHalfWidth)
	local E = checks.ENGINE
	local problems = {}
	local xs = checks.junctions(lists)
	for _, x in ipairs(xs) do
		if x.free < E.free - 1e-6 then
			problems[#problems + 1] = string.format("%s: %.1f m free (< %.1f)", x.name, x.free, E.free)
		end
		local limit = x.role == "legs" and E.behindLegs or E.behindArms
		if (x.behind or 0) > limit + 1e-6 then
			problems[#problems + 1] = string.format("%s: a junction corner %.1f m behind its node (> %.1f)", x.name, x.behind, limit)
		end
	end
	local middle, stubs = nil, {}
	local armHw, legHw, neckHw
	for _, l in ipairs(lists) do
		if l.role == "through" then
			for _, e in ipairs(l.edges) do
				if l.template and l.template:find(TRAM_ONLY, 1, true) then
					middle = checks.edgeLength(e)
				elseif (e.tag0 and e.tag0:find("tram", 1, true)) or (e.tag1 and e.tag1:find("tram", 1, true)) then
					stubs[#stubs + 1] = checks.edgeLength(e) - (ringHalfWidth or 0)
				end
			end
		elseif l.role == "arms" then armHw = l.halfWidth
		elseif l.role == "legs" then legHw = l.halfWidth
		elseif l.role == "neck" then neckHw = l.halfWidth end
	end
	if middle then
		if middle < E.tramMiddle - 1e-6 then
			problems[#problems + 1] = string.format("tram line: tram-only middle %.1f m (< %.1f)", middle, E.tramMiddle)
		end
		for _, st in ipairs(stubs) do
			if st < E.tramStub - 1e-6 then
				problems[#problems + 1] = string.format("tram line: stub %.1f m (< %.1f)", st, E.tramStub)
			end
		end
	end
	if neckHw then
		if armHw and armHw - neckHw > E.neckArmDiff + 1e-6 then
			problems[#problems + 1] = string.format("neck: half width %.1f on an arm of %.1f", neckHw, armHw)
		end
		if legHw and legHw - neckHw > E.neckLegDiff + 1e-6 then
			problems[#problems + 1] = string.format("neck: legs of half width %.1f fork from a neck of %.1f", legHw, neckHw)
		end
	end
	return problems, xs
end

return checks
