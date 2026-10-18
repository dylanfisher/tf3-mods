-- Organic Towns: shape metrics of a street network around its centre (pure). Used by the offline tests and SVG
-- previews to measure how unevenly a town grows (PLAN.md 6.2 "Irregular growth"), and by the dev showcase to log
-- the same numbers for real towns. Every edge counts with its chord length at its midpoint.
--   drift   distance of the length-weighted centroid from the centre, / mean radius (0 = centred)
--   spread  max / min over SECTORS sectors of the sector's 90th-percentile radius (1 = round; empty sectors
--           count as MIN_R)
--   cv      coefficient of variation of the street length per sector (0 = even)
--   elong   sqrt of the ratio of the principal second moments (1 = round, 2 = twice as long as wide)
--   meanR   length-weighted mean radius (m); length = total street length (m)
--   arms    corridors / fingers: prominent peaks of the 24-sector 90th-percentile radius (smoothed): each rises
--           ARM_PEAK x above the lowest sector toward its neighbouring peak (0-1 for a round town, 2 for a strip,
--           3-4 for a cross, 4-6 for fingers)
--   side    one-sidedness: the largest share of street length on one side of a line through the centre (0.5 =
--           even, 1 = all on one side: a fan / half town)
--   waist   two lobes: along the principal axis, the thinnest length density between the two ends' densest
--           tenths, over the weaker of the two (1 = no waist, toward 0 = two cores joined by a thin link)

local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

M.SECTORS = 8
M.MIN_R = 25
M.ARM_SECTORS = 24
M.ARM_PEAK = 1.25
M.WAIST_BINS = 10

local sqrt, pi, floor = math.sqrt, math.pi, math.floor

local function angle(y, x)
	if math.atan2 then return math.atan2(y, x) end
	return math.atan(y, x)
end

--- segs = { {x0, y0, x1, y1}, ... }, centre {cx, cy}. Returns the metrics table (all zero for no segments).
function M.segments(segs, cx, cy)
	local n = M.SECTORS
	local out = { drift = 0, spread = 1, cv = 0, elong = 1, meanR = 0, length = 0, sectors = {}, arms = 0, side = 0.5,
		waist = 1 }
	local W, sx, sy, sr = 0, 0, 0, 0
	local radii, len = {}, {}
	for k = 1, n do radii[k], len[k] = {}, 0 end
	local mxx, myy, mxy = 0, 0, 0
	for _, s in ipairs(segs) do
		local l = sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
		if l > 0 then
			local mx, my = (s[1] + s[3]) / 2 - cx, (s[2] + s[4]) / 2 - cy
			local r = sqrt(mx * mx + my * my)
			W, sx, sy, sr = W + l, sx + l * mx, sy + l * my, sr + l * r
			mxx, myy, mxy = mxx + l * mx * mx, myy + l * my * my, mxy + l * mx * my
			local a = angle(my, mx)
			local k = floor((a + pi) / (2 * pi) * n) % n + 1
			local list = radii[k]
			list[#list + 1] = r
			len[k] = len[k] + l
		end
	end
	if W <= 0 then return out end
	out.length = W
	out.meanR = sr / W
	local gx, gy = sx / W, sy / W
	out.drift = out.meanR > 0 and sqrt(gx * gx + gy * gy) / out.meanR or 0
	local hi, lo = 0, math.huge
	local meanL = W / n
	local var = 0
	for k = 1, n do
		local list = radii[k]
		table.sort(list)
		local p90 = #list > 0 and list[math.max(1, math.min(#list, floor(#list * 0.9 + 0.5)))] or 0
		p90 = math.max(p90, M.MIN_R)
		out.sectors[k] = p90
		if p90 > hi then hi = p90 end
		if p90 < lo then lo = p90 end
		var = var + (len[k] - meanL) ^ 2
	end
	out.spread = hi / lo
	out.cv = sqrt(var / n) / meanL
	-- principal moments about the centroid
	local cxx, cyy, cxy = mxx / W - gx * gx, myy / W - gy * gy, mxy / W - gx * gy
	local tr, det = cxx + cyy, cxx * cyy - cxy * cxy
	local disc = sqrt(math.max(0, tr * tr / 4 - det))
	local l1, l2 = tr / 2 + disc, tr / 2 - disc
	out.elong = l2 > 1e-9 and sqrt(l1 / l2) or 1
	-- arms: peaks of the fine sector radii
	local na = M.ARM_SECTORS
	local fine = {}
	for k = 1, na do fine[k] = {} end
	local mids = {}
	for _, s in ipairs(segs) do
		local l = sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
		if l > 0 then
			local mx, my = (s[1] + s[3]) / 2 - cx, (s[2] + s[4]) / 2 - cy
			local k = floor((angle(my, mx) + pi) / (2 * pi) * na) % na + 1
			local list = fine[k]
			list[#list + 1] = sqrt(mx * mx + my * my)
			mids[#mids + 1] = { mx, my, l }
		end
	end
	local rad = {}
	for k = 1, na do
		local list = fine[k]
		table.sort(list)
		rad[k] = math.max(#list > 0 and list[math.max(1, math.min(#list, floor(#list * 0.9 + 0.5)))] or 0, M.MIN_R)
	end
	local sm = {}
	for k = 1, na do
		local a, b = rad[(k - 2) % na + 1], rad[k % na + 1]
		sm[k] = (a + 2 * rad[k] + b) / 4
	end
	-- local maxima, then merge neighbours whose valley between them is shallow (prominence: each arm rises ARM_PEAK
	-- x above the lowest sector toward its neighbouring arm)
	local peaks = {}
	for k = 1, na do
		local a, b = sm[(k - 2) % na + 1], sm[k % na + 1]
		if sm[k] >= a and sm[k] > b then peaks[#peaks + 1] = k end
	end
	local function valley(p, q)
		local v = math.huge
		local k = p
		while k ~= q do
			k = k % na + 1
			if sm[k] < v then v = sm[k] end
		end
		return v
	end
	local changed = #peaks > 1
	while changed and #peaks > 1 do
		changed = false
		for i = 1, #peaks do
			local p, q = peaks[i], peaks[i % #peaks + 1]
			if math.min(sm[p], sm[q]) < M.ARM_PEAK * valley(p, q) then
				table.remove(peaks, sm[p] < sm[q] and i or (i % #peaks + 1))
				changed = true
				break
			end
		end
	end
	local lo = math.huge
	for k = 1, na do if sm[k] < lo then lo = sm[k] end end
	local arms = 0
	for _, k in ipairs(peaks) do if sm[k] >= M.ARM_PEAK * lo then arms = arms + 1 end end
	out.arms = arms
	out.fine = sm
	-- side: the heaviest half-plane through the centre
	local best = 0
	for k = 0, 35 do
		local a = k / 36 * 2 * pi
		local ux, uy = math.cos(a), math.sin(a)
		local w = 0
		for _, m in ipairs(mids) do if m[1] * ux + m[2] * uy > 0 then w = w + m[3] end end
		if w > best then best = w end
	end
	out.side = best / W
	-- waist: length density along the principal axis (about the centroid)
	local ang = 0.5 * angle(2 * cxy, cxx - cyy)
	local ux, uy = math.cos(ang), math.sin(ang)
	local lo, hi2 = math.huge, -math.huge
	for _, m in ipairs(mids) do
		local t = (m[1] - gx) * ux + (m[2] - gy) * uy
		m[4] = t
		if t < lo then lo = t end
		if t > hi2 then hi2 = t end
	end
	local nb = M.WAIST_BINS
	if hi2 - lo > 1e-6 then
		local bins = {}
		for k = 1, nb do bins[k] = 0 end
		for _, m in ipairs(mids) do
			local k = math.min(nb, floor((m[4] - lo) / (hi2 - lo) * nb) + 1)
			bins[k] = bins[k] + m[3]
		end
		local li, ri = 1, nb
		for k = 1, nb / 2 do if bins[k] > bins[li] then li = k end end
		for k = nb / 2 + 1, nb do if bins[k] > bins[ri] then ri = k end end
		local valley = math.huge
		for k = li, ri do if bins[k] < valley then valley = bins[k] end end
		local weak = math.min(bins[li], bins[ri])
		out.waist = weak > 0 and math.min(1, valley / weak) or 1
	end
	return out
end

--- Metrics of an ot_graph network (nodes by id, edges n0/n1) around (cx, cy). Optional filter(edge) -> bool.
function M.graph(g, cx, cy, filter)
	local segs = {}
	for _, e in ipairs(g.edges) do
		if filter == nil or filter(e) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then segs[#segs + 1] = { a.x, a.y, b.x, b.y } end
		end
	end
	return M.segments(segs, cx, cy)
end

--- Metrics of points (building positions, each weighing the same): pts = { {x, y}, ... }. The same table as
--- M.segments (the houses' outline: the shape a player sees from above, SHAPES_BRIEF 2026-10-12).
function M.points(pts, cx, cy)
	local segs = {}
	for _, p in ipairs(pts or {}) do
		local x, y = p[1] or p.x, p[2] or p.y
		if x and y then segs[#segs + 1] = { x - 0.5, y, x + 0.5, y } end
	end
	return M.segments(segs, cx, cy)
end

--- "elong/arms/side/waist" (log field).
function M.short(m)
	if m == nil then return "-" end
	return string.format("%.2f/%.1f/%.2f/%.2f", m.elong, m.arms, m.side, m.waist)
end

---------------------------------------------------------------------------
-- Look issues (showcase v2 screenshots): zig-zag chains and loops hanging off one stem (ot_select look rules).

M.ZIGZAG_DEG = 35

--- Signed turn (radians) at a node with exactly two streets, travelling in along `inEdge` and out along the
--- other: nil when the node has another degree.
local function cornerAt(g, id, inEdge)
	local adj = g.adj[id]
	if adj == nil or #adj ~= 2 then return nil end
	local outEdge = adj[1] == inEdge and adj[2] or adj[1]
	local hin = OG.headingFrom(g, g.edgeById[inEdge], id) + math.pi
	local hout = OG.headingFrom(g, g.edgeById[outEdge], id)
	local ix, iy, ox, oy = math.cos(hin), math.sin(hin), math.cos(hout), math.sin(hout)
	return angle(ix * oy - iy * ox, ix * ox + iy * oy), outEdge
end

--- Zig-zag chains: three corners in a row (> ZIGZAG_DEG, at nodes with two streets each) alternating left /
--- right along one street (a staircase or an S-chain of separate pieces; a single S doesn't count). Optional
--- filter(edge) -> bool limits which middle edges count. Returns the count.
function M.zigzags(g, filter)
	return #M.zigzagList(g, filter)
end

--- The zig-zag chains as { {e1, e2, e3, e4} } edge ids (the four streets around the three corners).
function M.zigzagList(g, filter)
	local lim = math.rad(M.ZIGZAG_DEG)
	local out = {}
	for _, e in ipairs(g.edges) do
		if filter == nil or filter(e) then
			-- travel n0 -> n1 along e: corners at n0 (coming from its other edge), at n1 and one further
			local adj0 = g.adj[e.n0]
			if adj0 and #adj0 == 2 then
				local before = adj0[1] == e.id and adj0[2] or adj0[1]
				local t0 = cornerAt(g, e.n0, before)
				local t1, after = cornerAt(g, e.n1, e.id)
				if t0 and t1 and math.abs(t0) > lim and math.abs(t1) > lim and t0 * t1 < 0 then
					local far = OG.other(g.edgeById[after], e.n1)
					local t2, next = cornerAt(g, far, after)
					if t2 and math.abs(t2) > lim and t2 * t1 < 0 then out[#out + 1] = { before, e.id, after, next } end
				end
			end
		end
	end
	return out
end

--- Saw-tooth outskirts (showcase v3 screenshots: stepped / saw-tooth block chains at the edge): corners (nodes
--- with two streets turning more than TOOTH_DEG) and dead ends, per km of street. Optional filter(edge) -> bool
--- limits the edges (e.g. the mod's own); a node counts when one of its edges passes. Returns teeth per km,
--- corners, dead ends, km.
M.TOOTH_DEG = 60
function M.teeth(g, filter)
	local lim = math.rad(M.TOOTH_DEG)
	local km, corners, ends = 0, 0, 0
	local seen = {}
	for _, e in ipairs(g.edges) do
		if filter == nil or filter(e) then
			km = km + OG.edgeLength(g, e) / 1000
			for _, id in ipairs({ e.n0, e.n1 }) do
				if not seen[id] then
					seen[id] = true
					local adj = g.adj[id]
					if adj and #adj == 1 then
						ends = ends + 1
					elseif adj and #adj == 2 then
						local t = cornerAt(g, id, adj[1])
						if t and math.abs(t) > lim then corners = corners + 1 end
					end
				end
			end
		end
	end
	if km <= 0 then return 0, 0, 0, 0 end
	return (corners + ends) / km, corners, ends, km
end

M.HUG_R = 100   -- m (ot_select.HUG x block): a loop part this close to the rest of the network hugs the town

--- Lassos: loops hanging off the town by a stem (2-edge-connected parts with a cycle other than the core,
--- ot_graph.structure) of 2+ bridge edges that don't hug the town: none of their nodes within hugR (default
--- HUG_R) of an edge outside the part (stems, i.e. bridges, left out). Returns the count and the largest one's
--- edge count.
function M.lassos(g, hugR)
	hugR = hugR or M.HUG_R
	local st = OG.structure(g)
	-- stem length: bridge edges from each node to the core (BFS over bridges from the core)
	local stem = {}
	local queue, head = {}, 1
	for _, n in ipairs(g.nodes) do
		if st.core and st.comp[n.id] == st.core then stem[n.id] = 0; queue[#queue + 1] = n.id end
	end
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		for _, eid in ipairs(g.adj[id] or {}) do
			local o = OG.other(g.edgeById[eid], id)
			if stem[o] == nil then
				stem[o] = stem[id] + (st.bridges[eid] and 1 or 0)
				queue[#queue + 1] = o
			end
		end
	end
	local n, big = 0, 0
	local ids = {}
	for id in pairs(st.parts) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local part = st.parts[id]
		local partStem = math.huge
		for _, eid in ipairs(part.edgeIds or {}) do
			local pe = g.edgeById[eid]
			partStem = math.min(partStem, stem[pe.n0] or math.huge, stem[pe.n1] or math.huge)
		end
		if part.cycle and id ~= st.core and partStem >= 2 then
			local inPart = {}
			for _, eid in ipairs(part.edgeIds or {}) do inPart[eid] = true end
			local hugs = false
			for _, eid in ipairs(part.edgeIds or {}) do
				local pe = g.edgeById[eid]
				for _, nid in ipairs({ pe.n0, pe.n1 }) do
					local nd = g.nodeById[nid]
					for _, e in ipairs(g.edges) do
						if not inPart[e.id] and not st.bridges[e.id] and st.comp[e.n0] ~= id then
							local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
							if (G.pointSegDist(nd.x, nd.y, a.x, a.y, b.x, b.y)) <= hugR then hugs = true break end
						end
					end
					if hugs then break end
				end
				if hugs then break end
			end
			if not hugs then
				n = n + 1
				if part.edges > big then big = part.edges end
			end
		end
	end
	return n, big
end

---------------------------------------------------------------------------
-- Arms as strips, not ladders (Showcase v5, 2026-10-12: shaped towns' arms read as fishbones, one spine with short
-- dead-end stubs every block on both sides; real ribbon villages have back lanes parallel to the main street).

M.LADDER_BAND = 3      -- arm corridor half width for the metric, x block.depth (fixed: independent of ot_shape)
M.LADDER_CORE = 1.5    -- ... beyond this many block lengths from the centre
M.LADDER_PAR = math.rad(30)   -- a street within this angle of the arm axis runs along it (spine / back street)
M.LADDER_ROW = 0.4     -- parallel streets more than this many block depths apart are separate rows

--- Ladder / depth of a shaped town's arms. g: ot_graph; shape: ot_shape table (arms, centre; nil or a shape
--- without arms -> nil); block: style.block ({len, depth}) or a number for both; optional filter(edge) -> bool (e.g.
--- the mod's own edges). Arm streets: within LADDER_BAND x depth of an arm's axis (the nearest), beyond
--- LADDER_CORE x len from the centre. Streets are chains between nodes that don't have exactly two streets.
--- Returns { segs (arm chains), stubs (rungs: dead-end chains shorter than block.len running across the arm, more
--- than 45 deg off its axis; the tips of the spine and back streets run along it), share = stubs / segs, depth (the
--- strip's depth in blocks: per block.len bin along an arm, the rows of streets parallel to the axis (within
--- LADDER_PAR; rows more than LADDER_ROW x depth apart) minus one (the spine), averaged over the bins with a
--- parallel street: a fishbone 0, a spine with one back street each side 2; relative to the streets, so a spine
--- a little off the arm's axis doesn't count as a row), bins, blocks (closed blocks: the arm streets' cycle count
--- E - V + components), length (m) }.
function M.ladder(g, shape, block, filter)
	if shape == nil or shape.arms == nil or #shape.arms == 0 then return nil end
	local id = shape.id
	if id ~= "linear" and id ~= "ridge" and id ~= "cross" and id ~= "fingers" then return nil end
	local bl = type(block) == "table" and block.len or block or 100
	local bd = type(block) == "table" and block.depth or block or 100
	local cx, cy = shape.centre[1], shape.centre[2]
	local band, minAlong = M.LADDER_BAND * bd, M.LADDER_CORE * bl
	local function armAt(x, y)
		local best, bp, ba = nil, math.huge, nil
		for i, h in ipairs(shape.arms) do
			local ca, sa = math.cos(h), math.sin(h)
			local along = (x - cx) * ca + (y - cy) * sa
			local perp = -(x - cx) * sa + (y - cy) * ca
			if along > minAlong and math.abs(perp) <= band and math.abs(perp) < bp then best, bp, ba = i, math.abs(perp), along end
		end
		return best, ba
	end
	-- per edge: the arm it lies in (nearest axis, at its midpoint)
	local armOf = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then armOf[e.id] = armAt((a.x + b.x) / 2, (a.y + b.y) / 2) end
	end
	local out = { segs = 0, stubs = 0, share = 0, depth = 0, bins = 0, blocks = 0, length = 0 }
	local function deg(nid) return #(g.adj[nid] or {}) end
	local done = {}
	local inArm = {}   -- edge ids of the chains counted
	for _, n in ipairs(g.nodes) do
		if deg(n.id) ~= 2 and deg(n.id) > 0 then
			for _, eid in ipairs(g.adj[n.id]) do
				if not done[eid] then
					-- walk the chain from n through two-street nodes
					local chain, at, cur = {}, n.id, eid
					local deadEnd = deg(n.id) == 1
					while cur and not done[cur] do
						done[cur] = true
						chain[#chain + 1] = cur
						at = OG.other(g.edgeById[cur], at)
						if deg(at) == 2 then
							local adj = g.adj[at]
							cur = adj[1] == cur and adj[2] or adj[1]
						else
							if deg(at) == 1 then deadEnd = true end
							cur = nil
						end
					end
					-- (the chain's direction: its two end nodes)
					local n0, n1 = g.nodeById[n.id], g.nodeById[at]
					local L, Larm, pass = 0, 0, filter == nil
					for _, ce in ipairs(chain) do
						local e = g.edgeById[ce]
						local l = OG.edgeLength(g, e)
						L = L + l
						if armOf[ce] then Larm = Larm + l end
						if filter and filter(e) then pass = true end
					end
					if pass and L > 0 and Larm > 0.5 * L then
						out.segs = out.segs + 1
						out.length = out.length + L
						if deadEnd and L < bl then
							-- a rung: across the arm (more than 45 deg off the axis of the arm it lies in); the tips
							-- of the spine and back streets run along it and don't count
							local i = armOf[chain[1]] or armOf[chain[#chain]]
							local h = i and shape.arms[i]
							local dx, dy = n1.x - n0.x, n1.y - n0.y
							local l = math.sqrt(dx * dx + dy * dy)
							if h == nil or l <= 0 or math.abs(dx * math.cos(h) + dy * math.sin(h)) / l < math.cos(math.pi / 4) then
								out.stubs = out.stubs + 1
							end
						end
						for _, ce in ipairs(chain) do inArm[#inArm + 1] = ce end
					end
				end
			end
		end
	end
	if out.segs == 0 then return out end
	out.share = out.stubs / out.segs
	-- depth: sample the parallel arm streets every 20 m into bins (arm, along / len); per bin the spine (|perp| <
	-- LADDER_ROW x depth) and the signed offsets of the others
	local bins = {}
	for _, eid in ipairs(inArm) do
		local e = g.edgeById[eid]
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local i = armOf[eid]
		if i then
			local h = shape.arms[i]
			local ca, sa = math.cos(h), math.sin(h)
			local dx, dy = b.x - a.x, b.y - a.y
			local l = math.sqrt(dx * dx + dy * dy)
			local cosT = l > 0 and math.abs(dx * ca + dy * sa) / l or 0
			if cosT >= math.cos(M.LADDER_PAR) then
				local k = math.max(1, math.ceil(l / 20))
				for s = 0, k do
					local x, y = a.x + dx * s / k, a.y + dy * s / k
					local along = (x - cx) * ca + (y - cy) * sa
					local perp = -(x - cx) * sa + (y - cy) * ca
					if along > minAlong and math.abs(perp) <= band then
						local key = i * 100000 + math.floor(along / bl)
						local bin = bins[key]
						if bin == nil then bin = { offs = {} }; bins[key] = bin end
						bin.offs[#bin.offs + 1] = perp
					end
				end
			end
		end
	end
	local nb, rows = 0, 0
	local keys = {}
	for key in pairs(bins) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local list = bins[key].offs
		table.sort(list)
		local last, r = nil, 0
		for _, p in ipairs(list) do
			if last == nil or p - last > M.LADDER_ROW * bd then r = r + 1 end
			last = p
		end
		nb, rows = nb + 1, rows + r - 1
	end
	out.bins = nb
	out.depth = nb > 0 and rows / nb or 0
	-- cycle count of the arm streets: E - V + components (union-find over their nodes)
	local uf, nv, comps = {}, 0, 0
	local function find(x)
		while uf[x] ~= x do uf[x] = uf[uf[x]]; x = uf[x] end
		return x
	end
	for _, eid in ipairs(inArm) do
		local e = g.edgeById[eid]
		for _, v in ipairs({ e.n0, e.n1 }) do
			if uf[v] == nil then uf[v] = v; nv = nv + 1; comps = comps + 1 end
		end
		local ra, rb = find(e.n0), find(e.n1)
		if ra ~= rb then uf[ra] = rb; comps = comps - 1 end
	end
	out.blocks = #inArm - nv + comps
	return out
end

--- "ladder=0.42 depth=1.6 blocks=5" (log / report text; "-" for nil).
function M.ladderText(l)
	if l == nil then return "-" end
	return string.format("ladder=%.2f depth=%.1f blocks=%d", l.share, l.depth, l.blocks)
end

--- "drift=0.12 spread=1.80 cv=0.35 elong=1.40 meanR=320 length=5400" (log / report text).
function M.text(m)
	return string.format("drift=%.2f spread=%.2f cv=%.2f elong=%.2f arms=%d side=%.2f waist=%.2f meanR=%.0f length=%.0f",
		m.drift, m.spread, m.cv, m.elong, m.arms or 0, m.side or 0.5, m.waist or 1, m.meanR, m.length)
end

-- Green gaps (2026-10-12, user on the Density: control twin: "green gaps and interesting shapes": curving streets
-- around open meadows, not every block filled; keep it). On a raster of GREEN_CELL m over the street network: street
-- cells (edge chords), the open land reachable from the border without crossing a street is outside; everything
-- else is enclosed. Enclosed cells farther than about one cell from any building are "green"; a 4-connected green
-- patch of at least GREEN_MIN_HA is a green gap. Chords stand in for curves (a slight undercount at tight curves).
M.GREEN_CELL = 20
M.GREEN_MAX_CELLS = 180   -- per side; larger towns use coarser cells
M.GREEN_MIN_HA = 1

--- Green gaps of a town: g = street graph (ot_graph), pts = building points { {x, y} }. Returns { gaps = count of
--- patches >= GREEN_MIN_HA, gapHa = their area, maxHa = the largest, enclosedHa = enclosed area, share = gapHa /
--- enclosedHa, cell } or nil (no streets).
function M.greenGaps(g, pts)
	if g == nil or #g.edges == 0 then return nil end
	local segs = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then segs[#segs + 1] = { a.x, a.y, b.x, b.y } end
	end
	return M.greenGapsSegs(segs, pts)
end

--- M.greenGaps on street segments { {x0, y0, x1, y1} } (the dev showcase's town measurements).
function M.greenGapsSegs(segs, pts)
	if segs == nil or #segs == 0 then return nil end
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, sg in ipairs(segs) do
		minX, maxX = math.min(minX, sg[1], sg[3]), math.max(maxX, sg[1], sg[3])
		minY, maxY = math.min(minY, sg[2], sg[4]), math.max(maxY, sg[2], sg[4])
	end
	local c = M.GREEN_CELL
	local span = math.max(maxX - minX, maxY - minY)
	if span / c > M.GREEN_MAX_CELLS - 4 then c = span / (M.GREEN_MAX_CELLS - 4) end
	minX, minY = minX - 2 * c, minY - 2 * c
	local nx = floor((maxX - minX) / c) + 3
	local ny = floor((maxY - minY) / c) + 3
	local function idx(i, j) return j * nx + i end
	local street, built, seen = {}, {}, {}
	local function cellOf(x, y) return floor((x - minX) / c), floor((y - minY) / c) end
	for _, sg in ipairs(segs) do
		local ax, ay, bx, by = sg[1], sg[2], sg[3], sg[4]
		local L = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		local k = math.max(1, math.ceil(L / (c * 0.5)))
		for s = 0, k do
			local i, j = cellOf(ax + (bx - ax) * s / k, ay + (by - ay) * s / k)
			street[idx(i, j)] = true
		end
	end
	for _, p in ipairs(pts or {}) do
		local i, j = cellOf(p[1], p[2])
		for di = -1, 1 do
			for dj = -1, 1 do
				if i + di >= 0 and i + di < nx and j + dj >= 0 and j + dj < ny then built[idx(i + di, j + dj)] = true end
			end
		end
	end
	-- outside: flood from the border through non-street cells
	local stack = {}
	for i = 0, nx - 1 do stack[#stack + 1] = idx(i, 0); stack[#stack + 1] = idx(i, ny - 1) end
	for j = 0, ny - 1 do stack[#stack + 1] = idx(0, j); stack[#stack + 1] = idx(nx - 1, j) end
	while #stack > 0 do
		local k = stack[#stack]
		stack[#stack] = nil
		if not seen[k] and not street[k] then
			seen[k] = true
			local i, j = k % nx, floor(k / nx)
			if i > 0 then stack[#stack + 1] = k - 1 end
			if i < nx - 1 then stack[#stack + 1] = k + 1 end
			if j > 0 then stack[#stack + 1] = k - nx end
			if j < ny - 1 then stack[#stack + 1] = k + nx end
		end
	end
	local cellHa = c * c / 10000
	local enclosed, gapHa, gaps, maxHa = 0, 0, 0, 0
	local done = {}
	for j = 0, ny - 1 do
		for i = 0, nx - 1 do
			local k = idx(i, j)
			if not seen[k] and not street[k] then
				enclosed = enclosed + 1
				if not built[k] and not done[k] then
					-- one green patch (4-connected enclosed cells without buildings)
					local n, st = 0, { k }
					done[k] = true
					while #st > 0 do
						local q = st[#st]
						st[#st] = nil
						n = n + 1
						local qi, qj = q % nx, floor(q / nx)
						for _, nb in ipairs({ qi > 0 and q - 1 or nil, qi < nx - 1 and q + 1 or nil, qj > 0 and q - nx or nil,
							qj < ny - 1 and q + nx or nil }) do
							if nb and not done[nb] and not seen[nb] and not street[nb] and not built[nb] then
								done[nb] = true
								st[#st + 1] = nb
							end
						end
					end
					local ha = n * cellHa
					if ha >= M.GREEN_MIN_HA then
						gaps = gaps + 1
						gapHa = gapHa + ha
						if ha > maxHa then maxHa = ha end
					end
				end
			end
		end
	end
	local encHa = enclosed * cellHa
	return { gaps = gaps, gapHa = gapHa, maxHa = maxHa, enclosedHa = encHa, share = encHa > 0 and gapHa / encHa or 0, cell = c }
end

--- "gaps/gapHa/maxHa/enclosedHa/share%" e.g. "6/14.2/4.0/120.5/12" ("-" for nil).
function M.greenText(gg)
	if gg == nil then return "-" end
	return string.format("%d/%.1f/%.1f/%.1f/%.0f", gg.gaps, gg.gapHa, gg.maxHa, gg.enclosedHa, 100 * gg.share)
end

--- Street orientation (Showcase v8 round: do the metropolis variants keep their character?), length-weighted over
--- the graph's edges (filter(e) optional), around (cx, cy):
---   orth    share of length within ORTH_DEG of the dominant grid axes (mod 90; a grid ~0.9, organic ~0.4, random 0.22)
---   radial  share within RADIAL_DEG of the direction to the centre (spokes; random 0.33)
---   ring    share within RADIAL_DEG of the tangent (rings; random 0.33)
---   spokes  radial + ring (a radial-ring city above ~0.75; a grid or a random net ~0.67)
--- Edges within MIN_R of the centre are left out (every direction is radial there). Returns the table (zeros: none).
M.ORTH_DEG = 10
M.RADIAL_DEG = 15
function M.orientation(g, cx, cy, filter)
	local raw = {}
	for _, e in ipairs(g.edges) do
		if filter == nil or filter(e) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then raw[#raw + 1] = { a.x, a.y, b.x, b.y } end
		end
	end
	return M.orientationSegs(raw, cx, cy)
end

--- M.orientation for segments { {x0, y0, x1, y1} } (the dev showcase's town streets).
function M.orientationSegs(raw, cx, cy)
	local W = 0
	local segs = {}
	for _, q in ipairs(raw) do
		local l = G.dist(q[1], q[2], q[3], q[4])
		local mx, my = (q[1] + q[3]) / 2, (q[2] + q[4]) / 2
		if l > 0 and G.dist(cx, cy, mx, my) > M.MIN_R * 2 then
			segs[#segs + 1] = { h = G.heading(q[1], q[2], q[3], q[4]), l = l, r = G.heading(cx, cy, mx, my) }
			W = W + l
		end
	end
	local out = { orth = 0, radial = 0, ring = 0, spokes = 0 }
	if W <= 0 then return out end
	-- dominant axis mod 90 (4 x heading)
	local sx, sy = 0, 0
	for _, x in ipairs(segs) do sx, sy = sx + math.cos(4 * x.h) * x.l, sy + math.sin(4 * x.h) * x.l end
	local ax = angle(sy, sx) / 4
	local od, rd = math.rad(M.ORTH_DEG), math.rad(M.RADIAL_DEG)
	local o, ra, ri = 0, 0, 0
	for _, x in ipairs(segs) do
		local d90 = math.abs(((x.h - ax) + pi / 4) % (pi / 2) - pi / 4)
		if d90 <= od then o = o + x.l end
		local dr = math.abs(((x.h - x.r) + pi / 2) % pi - pi / 2)   -- 0 = radial, pi/2 = tangential
		if dr <= rd then ra = ra + x.l elseif dr >= pi / 2 - rd then ri = ri + x.l end
	end
	out.orth, out.radial, out.ring = o / W, ra / W, ri / W
	out.spokes = out.radial + out.ring
	return out
end

--- "orth/radial/ring" e.g. "0.82/0.31/0.30".
function M.orientText(o)
	if o == nil then return "-" end
	return string.format("%.2f/%.2f/%.2f", o.orth, o.radial, o.ring)
end

--- Showcase v9 round: share of the length of segments { {x0, y0, x1, y1} } within ORTH_DEG of the grid axes of
--- `axis` (rad, mod 90 deg): the town's own axis, not the dominant one (M.orientationSegs), so "the first increments
--- are grid streets on the town axis" is measurable from step 1 (PLAN `gridShare=`). Returns share, length.
function M.axisShare(segs, axis)
	local W, o = 0, 0
	local od = math.rad(M.ORTH_DEG)
	for _, q in ipairs(segs or {}) do
		local l = G.dist(q[1], q[2], q[3], q[4])
		if l > 0 then
			W = W + l
			local h = G.heading(q[1], q[2], q[3], q[4])
			if math.abs(((h - (axis or 0)) + pi / 4) % (pi / 2) - pi / 4) <= od then o = o + l end
		end
	end
	return W > 0 and o / W or 0, W
end

--- Unhoused street length (Showcase v9 round, user: "too many empty streets built out before town growth"): the
--- chord length of the graph's edges without a building on their parcels (snapshot edges carry `built`, g.hasBuilt),
--- optionally only edges passing filter(e). Returns total m, the longest single unhoused edge chain's length is not
--- traced (cheap: one pass), count of unhoused edges; nil without the data.
function M.emptyLen(g, filter)
	if g == nil or not g.hasBuilt then return nil end
	local len, n = 0, 0
	for _, e in ipairs(g.edges) do
		if (e.built or 0) <= 0 and (filter == nil or filter(e)) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				len = len + G.dist(a.x, a.y, b.x, b.y)
				n = n + 1
			end
		end
	end
	return len, n
end

---------------------------------------------------------------------------
-- Shore towns (2026-10-12): how much of a town sits on its shore. sd: ot_shape shore data (shape.shore or
-- style.waterPremium.shore); g: ot_graph (filter(e) optional); pts: building positions {x, y} or nil. Within NEAR m of
-- the traced shore (land side) counts as the waterfront. Returns { streets = share of street length near the water,
-- houses = share of buildings near it (nil without pts), covered = m of shoreline with a street within COVER m (50 m
-- bins along the shore), depth = 90th percentile of the streets' distance from the shore (m), length = street m } or nil.
M.SHORE_NEAR = 300
M.SHORE_COVER = 150
M.SHORE_BIN = 50

function M.shore(g, sd, pts, filter)
	if sd == nil or g == nil then return nil end
	local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
	local L, near, bins, nb, perps = 0, 0, {}, 0, {}
	for _, e in ipairs(g.edges) do
		if filter == nil or filter(e) then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
				local l = OG.edgeLength(g, e)
				local _, perp, wet, sAbs = SH.shoreAt(sd, mx, my)
				if wet then perp = 0 end
				L = L + l
				perps[#perps + 1] = perp
				if perp <= M.SHORE_NEAR then near = near + l end
				if perp <= M.SHORE_COVER then
					local k = floor(sAbs / M.SHORE_BIN)
					if not bins[k] then bins[k] = true; nb = nb + 1 end
				end
			end
		end
	end
	if L <= 0 then return nil end
	table.sort(perps)
	local out = { streets = near / L, covered = nb * M.SHORE_BIN, length = L,
		depth = perps[math.max(1, math.floor(#perps * 0.9 + 0.5))] or 0 }
	if pts and #pts > 0 then
		local h = 0
		for _, p in ipairs(pts) do
			local _, perp, wet = SH.shoreAt(sd, p[1], p[2])
			if wet or perp <= M.SHORE_NEAR then h = h + 1 end
		end
		out.houses = h / #pts
	end
	return out
end

--- "streets/houses cov=m depth=m" e.g. "0.82/0.75 cov=1800 depth=210" ("-" for nil).
function M.shoreText(m)
	if m == nil then return "-" end
	return string.format("%.2f/%s cov=%.0f depth=%.0f", m.streets, m.houses and string.format("%.2f", m.houses) or "-",
		m.covered, m.depth)
end

---------------------------------------------------------------------------
-- Land spread (2026-10-13, round 5; user: "I still wish cities were more spread out around the landscape, not just
-- radiating from the centre"): how far a town's buildings reach beyond a disc of the same built area around its centre,
-- and in how many separate lobes. pts = { {x, y} } (buildings), cx, cy = the town centre. Built area = occupied
-- SPREAD_CELL cells; Req = the radius of a disc with that area.
--   ratio   radius of gyration about the centre / that of a uniform disc of radius Req (Req / sqrt 2): 1 = a full disc,
--           1.5+ = spread out (strips, fingers, lobes)
--   beyond  share of the buildings farther than 1.5 x Req from the centre
--   lobes   groups of buildings (8-connected LOBE_CELL cells, gaps of a cell or more between them) holding at least
--           LOBE_MIN buildings and LOBE_SHARE of the town: 1 = one body
M.SPREAD_CELL = 40
M.LOBE_CELL = 60
M.LOBE_MIN = 6
M.LOBE_SHARE = 0.03

function M.landSpread(pts, cx, cy)
	local n = #(pts or {})
	if n < 10 then return nil end
	local occ, nOcc, sum2 = {}, 0, 0
	for _, p in ipairs(pts) do
		local k = floor(p[1] / M.SPREAD_CELL) * 65536 + floor(p[2] / M.SPREAD_CELL)
		if not occ[k] then occ[k] = true; nOcc = nOcc + 1 end
		local dx, dy = p[1] - cx, p[2] - cy
		sum2 = sum2 + dx * dx + dy * dy
	end
	local req = sqrt(nOcc * M.SPREAD_CELL * M.SPREAD_CELL / pi)
	local rg = sqrt(sum2 / n)
	local far = 0
	for _, p in ipairs(pts) do
		if G.dist(p[1], p[2], cx, cy) > 1.5 * req then far = far + 1 end
	end
	-- lobes: connected components of occupied LOBE_CELL cells
	local cells, list = {}, {}
	for _, p in ipairs(pts) do
		local i, j = floor(p[1] / M.LOBE_CELL), floor(p[2] / M.LOBE_CELL)
		local k = i * 65536 + j
		local c = cells[k]
		if c == nil then c = { i = i, j = j, n = 0 }; cells[k] = c; list[#list + 1] = c end
		c.n = c.n + 1
	end
	local lobes, need = 0, math.max(M.LOBE_MIN, M.LOBE_SHARE * n)
	for _, c in ipairs(list) do
		if not c.seen then
			c.seen = true
			local stack, total = { c }, 0
			while #stack > 0 do
				local x = table.remove(stack)
				total = total + x.n
				for di = -1, 1 do
					for dj = -1, 1 do
						local y = cells[(x.i + di) * 65536 + (x.j + dj)]
						if y and not y.seen then y.seen = true; stack[#stack + 1] = y end
					end
				end
			end
			if total >= need then lobes = lobes + 1 end
		end
	end
	return { ratio = req > 0 and rg / (req / sqrt(2)) or 0, beyond = far / n, lobes = lobes, req = req, rg = rg, n = n }
end

--- `spread=` text: "ratio/beyond %/lobes" or "-".
function M.spreadText(sp)
	if sp == nil then return "-" end
	return string.format("%.2f/%.0f/%d", sp.ratio, 100 * sp.beyond, sp.lobes)
end

--- Hill road (2026-10-13, round 5; the user on Middlewich, session 2026-10-13_0342_sqot: "the one street up into the
--- hills is very cool"): for an armed shape, the arm whose far street end climbs (or drops) most from the centre:
--- { len (m along the arm to its farthest street), climb (m, far end - centre height), houses (buildings in that arm
--- beyond CORE_M along it), edges (streets in the arm), arm (its index) } or nil. g = street graph, shape = ot_shape shape, pts = buildings, s = terrain sampler.
M.HILL_CORE_M = 150
function M.hillRoad(g, shape, pts, s)
	local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
	local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
	if g == nil or shape == nil or s == nil or not SH.ARMED[shape.id] then return nil end
	local arms = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			local i, along = SH.armAt(shape, mx, my)
			if i then
				local r = arms[i]
				if r == nil then r = { len = 0, houses = 0, edges = 0, arm = i }; arms[i] = r end
				r.edges = r.edges + 1
				if along > r.len then r.len, r.x, r.y = along, mx, my end
			end
		end
	end
	for _, p in ipairs(pts or {}) do
		local i, along = SH.armAt(shape, p[1], p[2])
		if i and arms[i] and along > M.HILL_CORE_M then arms[i].houses = arms[i].houses + 1 end
	end
	local h0 = T.height(s, shape.centre[1], shape.centre[2])
	local best
	for _, r in pairs(arms) do
		if r.x then
			r.climb = T.height(s, r.x, r.y) - h0
			if best == nil or math.abs(r.climb) > math.abs(best.climb) then best = r end
		end
	end
	return best
end

--- `hillRoad=` text: "len/climb/houses" or "-".
function M.hillText(h)
	if h == nil then return "-" end
	return string.format("%.0f/%+.0f/%d", h.len, h.climb, h.houses)
end

return M
