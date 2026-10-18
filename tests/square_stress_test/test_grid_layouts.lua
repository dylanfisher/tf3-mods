-- Stress Test street grid layouts (stress/stress_grid_streets.lua; plans/square_stress_test/BENCH.md "Funnel layouts"):
-- the City lights bench's Plain grid / Hourglass / Holes. Each layout keeps the grid connected (one network from the town's
-- center), leaves out exactly the streets of its gaps (the gap check finds every one left out and none kept), counts its
-- inner crossings per kind, and is the same for the same params (every city of a run gets the same grid).

local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"

local function key(x, y) return string.format("%.1f,%.1f", x, y) end

--- Nodes (by position) and their neighbours from an edge list; the BFS from (0, 0) (visited set, capped by the node count).
local function graph(edges)
	local adj, nodes = {}, 0
	local function add(a, b)
		local ka, kb = key(a[1], a[2]), key(b[1], b[2])
		if adj[ka] == nil then adj[ka] = {} nodes = nodes + 1 end
		if adj[kb] == nil then adj[kb] = {} nodes = nodes + 1 end
		adj[ka][#adj[ka] + 1] = kb
		adj[kb][#adj[kb] + 1] = ka
	end
	for _, e in ipairs(edges) do add(e[1], e[3]) end
	return adj, nodes
end

local function reached(adj, nodes, from)
	local seen, queue, head, n = { [from] = true }, { from }, 1, 1
	while head <= #queue and head <= nodes do
		local cur = queue[head]
		head = head + 1
		for _, nb in ipairs(adj[cur] or {}) do
			if not seen[nb] then
				seen[nb] = true
				n = n + 1
				queue[#queue + 1] = nb
			end
		end
	end
	return n
end

local function mid(e) return (e[1][1] + e[3][1]) / 2, (e[1][2] + e[3][2]) / 2 end

--- Every check one layout must pass: connected from the center, kept streets out of the gaps, every left-out street in a
--- gap, the inner crossings per kind as counted, no -0.
local function checkLayout(half, L, what)
	local all = grid.edges(half)
	local kept = grid.layoutEdges(half, L)
	local adj, nodes = graph(kept)
	ok(adj[key(0, 0)] ~= nil and #adj[key(0, 0)] >= 2, what .. ": the town's center stands on a street")
	eq(reached(adj, nodes, key(0, 0)), nodes, what .. ": every street reached from the center (one network)")
	local removed = 0
	for _, e in ipairs(all) do
		local k = grid.edgeKey(e, L)
		local x, y = mid(e)
		if k ~= nil and L.removed[k] then
			removed = removed + 1
			ok(grid.inGap(L, x, y), what .. ": a left-out street lies in a gap " .. k)
		else
			ok(not grid.inGap(L, x, y), what .. ": a kept street is in no gap " .. tostring(k))
		end
	end
	eq(#kept + removed, #all, what)
	-- the inner crossings per kind, from the kept streets
	local x4, t3 = 0, 0
	local lines = grid.lines(half)
	for a = 2, #lines - 1 do
		for b = 2, #lines - 1 do
			local d = adj[key(lines[a], lines[b])] and #adj[key(lines[a], lines[b])] or 0
			if d == 4 then x4 = x4 + 1 elseif d == 3 then t3 = t3 + 1 end
		end
	end
	eq({ x4, t3, x4 + t3 }, { L.x4, L.t3, L.crossings }, what .. ": crossings per kind")
	for _, e in ipairs(kept) do
		for _, p in ipairs({ e[1], e[2], e[3], e[4] }) do
			for c = 1, 3 do ok(p[c] ~= 0 or 1 / p[c] > 0, what .. ": +0, never -0") end
		end
	end
	return kept, removed
end

test("plain: every street, 81 four-way crossings on the 800 m grid; the construction's default and old params build the same grid", function()
	local L = grid.layout(400, "plain")
	eq({ L.name, L.n, L.step, L.x4, L.t3, L.crossings, L.neck, #L.holes, #L.gaps }, { "plain", 10, 80, 81, 0, 81, 0, 0, 0 })
	local kept, removed = checkLayout(400, L, "plain")
	eq({ #kept, removed }, { 224, 0 })
	-- old params (no layout key) and an unknown layout give the plain grid
	for _, params in ipairs({ { sqst_grid_half = 3, sqst_grid_ring = 2 }, { sqst_grid_half = 3, sqst_grid_ring = 2, sqst_grid_layout = 9 } }) do
		local r = grid.result(params)
		eq(#r.edgeLists[1].edges / 2 + #r.edgeLists[2].edges / 2, 224)
	end
	eq(grid.layout(400, 7).name, "plain")
end)

test("hourglass: a band 2 blocks tall through the middle where only the 3 central north-south streets go on: the halves meet only at the neck; 75 lit crossings (61 X, 14 T)", function()
	local L = grid.layout(400, "hourglass")
	eq({ L.name, L.neck, L.x4, L.t3, L.gone, L.crossings }, { "hourglass", 3, 61, 14, 6, 75 })
	eq(grid.layout(400, 2).name, "hourglass", "by index (the construction param)")
	local kept, removed = checkLayout(400, L, "hourglass")
	eq({ #kept, removed }, { 224 - 24, 24 }, "8 east-west pieces on the center line, 2 pieces of 8 north-south lines")
	-- every kept street crossing the band (|y| < 80) is a neck street (|x| <= 80): all traffic between the halves goes
	-- through the neck; the ring's sides are cut there too
	local crossingBand = 0
	for _, e in ipairs(kept) do
		local x, y = mid(e)
		if math.abs(y) < 80 and math.abs(e[1][2] - e[3][2]) > 1 then
			crossingBand = crossingBand + 1
			ok(math.abs(x) <= 80, "a north-south street in the band is a neck street: x=" .. x)
		end
		if math.abs(y) < 1e-6 then ok(math.abs(x) < 80, "an east-west street on the center line only inside the neck: x=" .. x) end
	end
	eq(crossingBand, 6, "3 neck streets x 2 blocks")
	-- the gaps: 2 rectangles left and right of the neck, out past the ring line
	eq(#L.gaps, 2)
	ok(grid.inGap(L, -400, 40) and grid.inGap(L, 240, 0) and not grid.inGap(L, 0, 40) and not grid.inGap(L, -240, 160))
	-- the construction builds it from its params, the country ring in its own list
	local r = grid.result({ sqst_grid_half = 3, sqst_grid_ring = 2, sqst_grid_layout = 2 })
	eq(#r.edgeLists[1].edges / 2 + #r.edgeLists[2].edges / 2, 224 - 24)
	eq(#r.edgeLists[2].edges / 2, 40 - 4 + 4, "ring: 40 sides less the 4 band pieces, plus the 4 corner stubs")
end)

test("holes: every pattern 4 holes of 2 x 2 blocks, never at the center, no two sharing a street; 77 lit crossings (61 X, 16 T); the same pattern the same holes", function()
	local seen = {}
	local differ = 0
	for p = 1, grid.HOLE_PATTERNS do
		local L = grid.layout(400, "holes", p)
		eq({ L.name, L.pattern, #L.holes, L.x4, L.t3, L.gone, L.crossings, #L.gaps }, { "holes", p, 4, 61, 16, 4, 77, 4 }, "pattern " .. p)
		for a, h in ipairs(L.holes) do
			ok(h[1] >= 2 and h[1] <= 8 and h[2] >= 2 and h[2] <= 8, "inner")
			ok(not (h[1] == 5 and h[2] == 5), "not at the center")
			for b = a + 1, #L.holes do
				local g = L.holes[b]
				ok(math.max(math.abs(h[1] - g[1]), math.abs(h[2] - g[2])) >= grid.HOLE_MIN_GAP, "apart")
			end
		end
		local kept, removed = checkLayout(400, L, "holes " .. p)
		eq({ #kept, removed }, { 224 - 16, 16 })
		eq(grid.layout(400, 3, p).holes, L.holes, "deterministic")
		local s = ""
		for _, h in ipairs(L.holes) do s = s .. h[1] .. "," .. h[2] .. ";" end
		if not seen[s] then differ = differ + 1 end
		seen[s] = true
	end
	ok(differ >= 6, "the patterns differ: " .. differ)
	-- the pattern wraps (a seed's pattern: (seed - 1) % HOLE_PATTERNS + 1), bad values fall back to pattern 1
	eq(grid.layout(400, "holes", grid.HOLE_PATTERNS + 2).holes, grid.layout(400, "holes", 2).holes)
	eq(grid.layout(400, "holes", nil).pattern, 1)
	local r = grid.result({ sqst_grid_half = 3, sqst_grid_ring = 2, sqst_grid_layout = 3, sqst_grid_holes = 5 })
	eq(#r.edgeLists[1].edges / 2 + #r.edgeLists[2].edges / 2, 224 - 16)
end)

test("every layout on the smaller grids stays connected; the hole search ends on a grid too small for 4 holes (capped)", function()
	for _, half in ipairs(grid.HALF) do
		for _, name in ipairs(grid.LAYOUTS) do
			for p = 1, name == "holes" and grid.HOLE_PATTERNS or 1 do
				local L = grid.layout(half, name, p)
				checkLayout(half, L, string.format("%s %d p%d", name, half, p))
				ok(#L.holes <= grid.HOLE_COUNT)
			end
		end
	end
	-- 4 blocks: the only candidate is the center: no hole
	eq(grid.holeCenters(4, 1), {})
	eq(#grid.holeCenters(6, 3) <= grid.HOLE_COUNT, true)
end)
