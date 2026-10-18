-- Organic Towns SVG preview driver (run by tools/ot_preview.py, never shipped). Builds synthetic terrains,
-- resolves a style per case through the real input/style layer, simulates N increments with ot_core and
-- returns plain data for the Python SVG writer. Globals provided by the runner: ug_require.

local core = ug_require "square_organic_towns::/organic_towns/ot_core.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local I = ug_require "square_organic_towns::/organic_towns/ot_inputs.lua"
local ST = ug_require "square_organic_towns::/organic_towns/ot_style.lua"
local MT = ug_require "square_organic_towns::/organic_towns/ot_metrics.lua"
local SEL = ug_require "square_organic_towns::/organic_towns/ot_select.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"

local exp, sin, cos, abs, sqrt = math.exp, math.sin, math.cos, math.abs, math.sqrt

local TERRAINS = {}

TERRAINS.flat = T.sampler(function() return 20 end)

-- town on the flank of a big round hill (top 300 m east): ~11 % grade at the centre
TERRAINS.hillside = T.sampler(function(x, y)
	local dx, dy = x - 300, y
	return 15 + 80 * exp(-(dx * dx + dy * dy) / (2 * 400 * 400))
end)

-- a meandering river crossing just south of the centre, 50 m wide
local function riverOffset(x, y) return y - (-120 + 60 * sin(x / 300)) end
TERRAINS.river = T.sampler(function(x, y)
	local d = abs(riverOffset(x, y))
	if d < 25 then return -2 end
	return 5 + math.min(d - 25, 400) * 0.01
end)

-- sea to the east-north-east, shoreline 300 m from the centre, land rising inland
local SHORE_A = math.rad(20)
local function shoreDist(x, y) return 300 - (x * cos(SHORE_A) + y * sin(SHORE_A)) end
TERRAINS.coast = T.sampler(function(x, y)
	local d = shoreDist(x, y)
	if d < 0 then return -3 end
	return 2 + d * 0.02
end)

-- style cases: raw inputs as the engine layer would pass them
local CASES = {
	NA_GRID = { nameList = "square_names_us_texas::/names/usa/usa.names", climate = "temperate", year = 1960 },
	EU_ORGANIC = { nameList = "::/names/germany/germany.names", climate = "temperate", year = 1900 },
	MED_HILL = { nameList = "::/names/italy/italy.names", climate = "dry", year = 1850 },
	JP_DENSE = { nameList = "::/names/japan/japan.names", climate = "temperate", year = 1980,
		stations = { { 420, 260 } } },
	NORDIC = { nameList = "::/names/norway/norway.names", climate = "subarctic", year = 1900 },
	MED_ENSANCHE = { nameList = "::/names/spain/spain.names", climate = "dry", year = 1880 },
	-- forced profiles (no region picks them on their own in these cases)
	NA_SUBURB = { nameList = "::/names/usa/usa.names", climate = "temperate", year = 1970, forceStyle = "NA_SUBURB" },
	EU_EXTENSION = { nameList = "::/names/germany/germany.names", climate = "temperate", year = 1890,
		forceStyle = "EU_EXTENSION" },
	SUPERBLOCK = { nameList = "::/names/russia/russia.names", climate = "temperate", year = 1970, forceStyle = "SUPERBLOCK" },
}

local M = {}

M.TERRAIN_IDS = { "flat", "hillside", "river", "coast" }
M.STYLE_IDS = { "NA_GRID", "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "MED_ENSANCHE", "JP_DENSE", "NORDIC",
	"SUPERBLOCK" }

M.SHAPE_IDS = SH.IDS

--- A vanilla-like town core (the game's generator: a small grid with dead-end stubs; every in-game town starts
--- from one): n x n nodes `sp` m apart, turned by `angle`, stubs of 40 m outward from the non-corner perimeter.
local function vanillaCore(g, angle, n, sp)
	n, sp = n or 5, sp or 90
	local ca, sa = cos(angle), sin(angle)
	local function at(u, v) return u * ca - v * sa, u * sa + v * ca end
	local ids, half = {}, (n - 1) / 2
	for i = 0, n - 1 do
		ids[i] = {}
		for j = 0, n - 1 do
			local x, y = at((i - half) * sp, (j - half) * sp)
			ids[i][j] = OG.addNode(g, nil, x, y, 20).id
		end
	end
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			if i < n - 1 then OG.addEdge(g, nil, ids[i][j], ids[i + 1][j], "small").increment = 0 end
			if j < n - 1 then OG.addEdge(g, nil, ids[i][j], ids[i][j + 1], "small").increment = 0 end
			local edge = i == 0 or j == 0 or i == n - 1 or j == n - 1
			local corner = (i == 0 or i == n - 1) and (j == 0 or j == n - 1)
			if edge and not corner then
				local du = (i == 0 and -1) or (i == n - 1 and 1) or 0
				local dv = (j == 0 and -1) or (j == n - 1 and 1) or 0
				local x, y = at((i - half) * sp + du * 40, (j - half) * sp + dv * 40)
				OG.addEdge(g, nil, ids[i][j], OG.addNode(g, nil, x, y, 20).id, "small").increment = 0
			end
		end
	end
end

--- A round vanilla-like core (as the game makes it, Showcase v4: ~70 edges, 14 dead ends; tests fixtures
--- F.roundCore): rings at 90 / 180 / 270 m, radials, a 50 m stub outward from every outer node.
local function roundCore(g, angle)
	local rings, counts = { 90, 180, 270 }, { 6, 10, 14 }
	local c = OG.addNode(g, nil, 0, 0, 20)
	local ids = {}
	for ri, r in ipairs(rings) do
		ids[ri] = {}
		local n = counts[ri]
		for k = 0, n - 1 do
			local a = angle + k / n * 2 * math.pi + 0.15 * sin(k * 2.3 + ri)
			local rr = r * (1 + 0.08 * sin(k * 1.7 + ri * 3))
			ids[ri][k] = OG.addNode(g, nil, rr * cos(a), rr * sin(a), 20).id
		end
		for k = 0, n - 1 do OG.addEdge(g, nil, ids[ri][k], ids[ri][(k + 1) % n], "small").increment = 0 end
	end
	for k = 0, counts[1] - 1 do OG.addEdge(g, nil, c.id, ids[1][k], "small").increment = 0 end
	for ri = 1, #rings - 1 do
		for k = 0, counts[ri] - 1 do
			local a = g.nodeById[ids[ri][k]]
			local best, bd = nil, math.huge
			for j = 0, counts[ri + 1] - 1 do
				local b = g.nodeById[ids[ri + 1][j]]
				local d = sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
				if d < bd then best, bd = b, d end
			end
			OG.addEdge(g, nil, a.id, best.id, "small").increment = 0
		end
	end
	for k = 0, counts[#rings] - 1 do
		local a = g.nodeById[ids[#rings][k]]
		local r = sqrt(a.x * a.x + a.y * a.y)
		OG.addEdge(g, nil, a.id, OG.addNode(g, nil, a.x * (1 + 50 / r), a.y * (1 + 50 / r), 20).id, "small").increment = 0
	end
end

--- Runs one case; returns a plain table for the SVG writer. even = true turns irregular growth off (comparison).
--- shape = an ot_shape id (forced) or nil (the seeded pick); fromCore = start from a vanilla core and join at
--- dead ends only (as in game), else from an empty graph joining anywhere.
local SITE_NAMES = { EU = "::/names/germany/germany.names", US = "::/names/usa/usa.names",
	MED = "::/names/italy/italy.names", JP = "::/names/japan/japan.names", NORDIC = "::/names/norway/norway.names" }

M.roundCore = function(g, a) return roundCore(g, a) end

function M.run(styleCase, terrainId, increments, townId, even, shape, fromCore, siteRegion, year, round, maxEdges, runYear)
	local raw = {}
	local sampler = TERRAINS[terrainId]
	local stats = T.stats(sampler, 0, 0, 600, 24)
	if siteRegion then
		-- Automatic (ot_site): the style from the site, the region only biasing
		raw = { nameList = SITE_NAMES[siteRegion] or SITE_NAMES.EU, climate = "temperate", year = year or 1970,
			autoStyle = true, wide = T.wide(sampler, 0, 0, 2000) }
		fromCore = true
	else
		for k, v in pairs(CASES[styleCase]) do raw[k] = v end
	end
	if runYear then raw.year = runYear end
	raw.townId = townId or 1
	raw.pos = { 0, 0 }
	raw.capacity = 1500
	raw.terrain = stats
	raw.shape = shape
	-- from a vanilla core: the style sees the core's street axis, as in game (ot_graph.dominantAxis)
	local coreAngle = math.rad(7 * (townId or 1))
	if fromCore then raw.axis = { angle = coreAngle, strength = 1 } end
	local inputs = I.build(raw)
	local style = ST.resolve(inputs)
	if even then style.irregular = false end
	local g = OG.new()
	local incs
	if fromCore then
		if round then roundCore(g, coreAngle) else vanillaCore(g, coreAngle) end
		incs = {}
		for k = 1, increments or 12 do
			local inc = core.planIncrement(g, style, { terrain = sampler, stats = stats, join = "deadEnd", maxEdges = maxEdges })
			if #inc.edges == 0 then break end
			OG.apply(g, inc, k)
			incs[#incs + 1] = inc
		end
	else
		incs = core.simulate(g, style, { terrain = sampler, stats = stats }, increments or 12)
	end
	local out = { style = style.id, label = style.logName, outer = style.outer and style.outer.id or "",
		region = inputs.region, era = I.ERA_NAMES[inputs.era], axis = math.deg(style.axis), axisSource = style.axisSource,
		centre = style.centre, stations = inputs.stations, increments = #incs, nodes = {}, edges = {},
		water = stats.water and stats.water.kind or "", meanSlope = stats.meanSlope, waterFraction = stats.waterFraction,
		metrics = MT.text(MT.graph(g, style.centre[1], style.centre[2])), even = even == true, hotspots = {},
		shape = SH.text(style.shape), shapeWhy = style.shape and style.shape.reason or "-",
		styleWhy = style.styleWhy or "-", hierarchy = style.hierarchy or "-",
		look = string.format("zigzags=%d lassos=%d%s", MT.zigzags(g),
			(MT.lassos(g, SEL.HUG * math.max(style.block.len, style.block.depth))),
			style.shape and MT.ladder(g, style.shape, style.block, function(e) return (e.increment or 0) > 0 end)
				and (" arms " .. MT.ladderText(MT.ladder(g, style.shape, style.block, function(e) return (e.increment or 0) > 0 end))) or ""),
		second = style.shape and style.shape.second }
	-- green reserves (meadows; [4] = a crescent's) for the drawing
	out.greens = {}
	for _, gr in ipairs(style.greens or {}) do out.greens[#out.greens + 1] = { gr[1], gr[2], gr[3], gr[4] and 1 or 0 } end
	local irr = SEL.irregularity(style)
	for _, h in ipairs(irr and irr.hotspots or {}) do out.hotspots[#out.hotspots + 1] = { h[1], h[2] } end
	for _, n in ipairs(g.nodes) do out.nodes[#out.nodes + 1] = { n.id, n.x, n.y, OG.degree(g, n.id) } end
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local t0, t1 = e.t0 or { b.x - a.x, b.y - a.y }, e.t1 or { b.x - a.x, b.y - a.y }
		local size = e.template and e.template:match("town_%a+_(%a+)%.street_template$") or e.class
		out.edges[#out.edges + 1] = { a.x, a.y, b.x, b.y, t0[1], t0[2], t1[1], t1[2], size, e.increment or 0 }
	end
	-- street mix of the new streets (large / medium / small % of length, ot_core.mixText)
	local mix = { large = 0, medium = 0, small = 0, total = 0 }
	for _, e in ipairs(g.edges) do
		if (e.increment or 0) > 0 then
			local size = e.template and e.template:match("town_%a+_(%a+)%.street_template$") or "small"
			if size ~= "large" and size ~= "medium" then size = "small" end
			local l = OG.edgeLength(g, e)
			mix[size], mix.total = mix[size] + l, mix.total + l
		end
	end
	out.mix = core.mixText(mix)
	-- terrain raster for the background: 50 x 50 cells over the view
	local half = 1100
	for _, nd in ipairs(g.nodes) do half = math.max(half, math.abs(nd.x) + 120, math.abs(nd.y) + 120) end
	half = math.ceil(half / 100) * 100
	local n = 55
	local cell = 2 * half / n
	out.raster = { half = half, n = n, cells = {} }
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local x, y = -half + (i + 0.5) * cell, -half + (j + 0.5) * cell
			out.raster.cells[#out.raster.cells + 1] = { sampler.height(x, y), T.isWater(sampler, x, y) and 1 or 0 }
		end
	end
	return out
end

return M
