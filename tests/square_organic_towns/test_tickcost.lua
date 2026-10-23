-- TICKCOST round (2026-10-21: session 2026-10-22_0518 had 194 ticks over 16 ms, up to 110 ms at job:plan /
-- job:snapshot / job:assess). The faster main body (ot_assess.body: numeric cell keys, unit-weight quantiles) and the
-- dead-end connectors' junction cells (ot_select.CONN_GRID) give the results of the code they replace; the tick's step
-- tracker names TICKCOST atStep.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

--- ot_assess.body as it was before 2026-10-21 (string cell keys, pair sorts): the reference.
local function quantile(list, q)
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	local total = 0
	for _, x in ipairs(list) do total = total + x[2] end
	local want, acc = q * total, 0
	for _, x in ipairs(list) do
		acc = acc + x[2]
		if acc >= want then return x[1] end
	end
	return list[#list][1]
end
local function oldBody(points, o)
	o = o or {}
	local cell = o.cell or A.BODY_CELL_M
	local reach = math.max(1, math.ceil((o.gap or A.BODY_GAP_M) / cell))
	local nAll = #points
	if nAll == 0 then return nil end
	local stride = math.max(1, math.ceil(nAll / (o.maxPts or A.BODY_PTS_MAX)))
	local pts = {}
	for i = 1, nAll, stride do pts[#pts + 1] = points[i] end
	local n, sx, sy = 0, 0, 0
	for _, p in ipairs(pts) do
		local w = p[3] or 1
		n, sx, sy = n + w, sx + p[1] * w, sy + p[2] * w
	end
	if n <= 0 then return nil end
	local mx, my = sx / n, sy / n
	-- cells: key -> { i, j, pts = { index... } }
	local cells, keys = {}, {}
	for k, p in ipairs(pts) do
		local i, j = math.floor(p[1] / cell), math.floor(p[2] / cell)
		local key = i .. ":" .. j
		local c = cells[key]
		if c == nil then
			c = { i = i, j = j, idx = {} }
			cells[key] = c
			keys[#keys + 1] = key
		end
		c.idx[#c.idx + 1] = k
	end
	-- flood fill (each cell queued once: the visited mark is set on queueing; the loops end with the cell list)
	local groups = {}
	for _, key in ipairs(keys) do
		local c0 = cells[key]
		if c0.grp == nil then
			local grp = { cells = {}, n = 0, sx = 0, sy = 0 }
			groups[#groups + 1] = grp
			c0.grp = grp
			local queue, head = { c0 }, 1
			while head <= #queue do
				local c = queue[head]
				head = head + 1
				grp.cells[#grp.cells + 1] = c
				for _, k in ipairs(c.idx) do
					local w = pts[k][3] or 1
					grp.n = grp.n + w
					grp.sx, grp.sy = grp.sx + pts[k][1] * w, grp.sy + pts[k][2] * w
				end
				for di = -reach, reach do
					for dj = -reach, reach do
						local nb = cells[(c.i + di) .. ":" .. (c.j + dj)]
						if nb and nb.grp == nil then
							nb.grp = grp
							queue[#queue + 1] = nb
						end
					end
				end
			end
		end
	end
	for _, grp in ipairs(groups) do
		grp.mx, grp.my = grp.sx / grp.n, grp.sy / grp.n
		grp.dm = G.dist(mx, my, grp.mx, grp.my)
	end
	table.sort(groups, function(a, b)
		if a.n ~= b.n then return a.n > b.n end
		return a.dm < b.dm
	end)
	local body = groups[1]
	local dBody, dAll = {}, {}
	local reachC = 0
	for _, c in ipairs(body.cells) do
		for _, k in ipairs(c.idx) do
			local p = pts[k]
			dBody[#dBody + 1] = { G.dist(body.mx, body.my, p[1], p[2]), p[3] or 1 }
			if o.cx then reachC = math.max(reachC, G.dist(o.cx, o.cy, p[1], p[2])) end
		end
	end
	for k, p in ipairs(pts) do dAll[k] = { G.dist(mx, my, p[1], p[2]), p[3] or 1 } end
	local out = { n = n, bodyN = body.n, rBody = quantile(dBody, A.EXTENT_QUANTILE), bx = body.mx, by = body.my,
		r50 = quantile(dAll, 0.5), out = n - body.n, groups = #groups - 1, reachC = o.cx and reachC or nil }
	local far = groups[2]
	if far then
		out.farN, out.farD = far.n, G.dist(body.mx, body.my, far.mx, far.my)
		out.farDeg = math.deg(G.atan2(far.my - body.my, far.mx - body.mx)) % 360
	end
	return out
end


local function rng(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

--- A cloud: a main group and `k` outlying groups, n points, weights (nil: unit) from wfn.
local function cloud(seed, n, k, wfn)
	local r = rng(seed)
	local pts = {}
	local centres = { { 0, 0, 400 } }
	for i = 1, k do centres[#centres + 1] = { (r() - 0.5) * 3000, (r() - 0.5) * 3000, 60 + r() * 150 } end
	for i = 1, n do
		local c = centres[1 + (i % (#centres + 2) >= #centres and 0 or i % (#centres + 2))]
		local a, d = r() * 2 * math.pi, r() * c[3]
		pts[i] = { c[1] + math.cos(a) * d, c[2] + math.sin(a) * d, wfn and wfn(r) or nil }
	end
	return pts
end

test("main body: the same result as the string-keyed reference (unit and real weights, outliers, odd points)", function()
	local cases = {}
	local stride = FULL and 1 or 3
	for seed = 1, 24, stride do
		cases[#cases + 1] = { cloud(seed, 50 + seed * 37, seed % 4), {} }
		cases[#cases + 1] = { cloud(seed + 100, 300, 2, function(r) return 1 + math.floor(r() * 4) end), { cx = 10, cy = -20 } }
	end
	-- (a point exactly on a cell corner, at -0, NaN and a far one off any map: the string fallback)
	local odd = cloud(7, 200, 1)
	odd[#odd + 1] = { -0.0, -0.0 }
	odd[#odd + 1] = { 0 / 0, 5 }
	odd[#odd + 1] = { 3e8, -3e8 }
	odd[#odd + 1] = { -100, 100 }
	cases[#cases + 1] = { odd, {} }
	cases[#cases + 1] = { cloud(9, 6000, 3), {} }   -- (stride > 1: BODY_PTS_MAX)
	for ci, c in ipairs(cases) do
		local a, b = A.body(c[1], c[2]), oldBody(c[1], c[2])
		for _, k in ipairs({ "n", "bodyN", "rBody", "bx", "by", "r50", "out", "groups", "farN", "farD", "farDeg", "reachC" }) do
			local x, y = a[k], b[k]
			if not (x ~= x and y ~= y) then eq(x, y, "case " .. ci .. " field " .. k) end
		end
	end
	eq(A.body({}), nil)
end)

test("dead-end connectors: the junction cells pick what the full scan picks (plans identical)", function()
	local function plans(grid)
		SEL.CONN_GRID = grid
		local out = {}
		local styles = FULL and { "EU_ORGANIC", "NA_GRID", "EU_EXTENSION", "MED_HILL", "NORDIC" } or { "EU_ORGANIC", "NA_GRID", "MED_HILL" }
		for _, sid in ipairs(styles) do
			for _, ang in ipairs({ 0, 0.37 }) do
				local style, stats = F.style({ forceStyle = sid, townId = 31, year = 1990, capacity = 3000 }, F.flat)
				-- (a turned core off the plan's lattice: its dead ends need connectors)
				local g = F.vanillaTown(nil, { n = 7, spacing = 90, angle = ang, cx = 13, cy = -7 })
				F.markBuilt(g, 200)
				local inc, rep = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
				out[#out + 1] = F.dump({ inc })
				out.conns = (out.conns or 0) + (rep and rep.connectors or 0) + (rep and rep.adopted or 0)
			end
		end
		SEL.CONN_GRID = true
		return out
	end
	local a, b = plans(true), plans(false)
	ok((a.conns or 0) > 0, "connectors or adopted dead ends planned: " .. tostring(a.conns))
	eq(#a, #b)
	for i = 1, #a do eq(a[i], b[i], "plan " .. i) end
end)

--- A driver over a fake clock: each read costs `cost` us.
local function clockDriver(cost)
	local E = { t = 0, logs = {} }
	function E.nowUs()
		E.t = E.t + cost
		return E.t
	end
	function E.log(l) E.logs[#E.logs + 1] = l end
	return D.new(E), E
end

test("step tracker: the tick's longest stretch between two notes names TICKCOST atStep", function()
	local d, E = clockDriver(10)
	d:stepStart(d:nowUs())
	d:stepNote("a")
	E.t = E.t + 5000
	d:stepNote("b")
	E.t = E.t + 200
	d:stepNote("c")
	local at, us = d:stepMax()
	eq(at, "a>b")
	ok(us >= 5000 and us < 5100, tostring(us))
	local d2 = clockDriver(10)
	eq(d2:stepMax(), "-")
end)
