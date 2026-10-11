-- DEV ONLY (never upload): Roundabouts Showcase, footprint of a combo. Pure Lua (no api.*): the
-- square_roundabouts geometry modules and the street widths come in through functions (ug_require
-- and api.res.streetTemplateRep in game, the test helpers offline).
--
-- The construction's edges (cubic Hermite curves) are sampled; every sample grows by its own
-- street's half width (sum of the template's laneConfigs widths / 2) + KERB, plus an embankment of
-- SLOPE * |z| where the street is not a bridge (z = height above the construction origin, so
-- "Hwy" level ramps get their earth slopes). The box around all grown samples is the footprint,
-- in the construction frame. Nothing is hard-coded per entry.
--
-- Sources of the edges, in order (sc_engine.measure):
--   1. the construction's own updateFn result: edgeLists[] = { params = {type = template},
--      edgeType = "BRIDGE"?, edges = {position, tangent} pairs } (basics.md "Edge Lists");
--   2. the geometry module named after the updateScript ("square_roundabouts_<x>.script@updateFn"
--      -> square_roundabouts_<x>.lua, "square_roundabouts.script" -> square_roundabouts_geometry.lua),
--      built like the updateFn: lists[] = { template, edgeType?, edges = {p0, p1, t0, t1} };
--   3. a fallback box.
--
-- footprint = { minX, maxX, minY, maxY, w, h, cx, cy, r, source, edges, maxGrow }

local shapeMod = ug_require "square_roundabouts_showcase::/showcase/sc_shape.lua"

local footprint = {}

footprint.RB_DIR = "square_roundabouts::/infrastructure/street_construction/"
footprint.SAMPLES = 8
-- metres added to a street's half width (kerb, verge, a little slack)
footprint.KERB = 4
-- horizontal metres of embankment per metre of height (a 1:1.5 earth slope)
footprint.SLOPE = 1.5
-- no sample grows less than this (m)
footprint.MIN_GROW = 6
-- width (m) of a street whose template width is unknown
footprint.DEFAULT_WIDTH = 16

local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
footprint.finite = finite

--- Module file of an updateScript fileName, or nil.
function footprint.moduleFile(scriptName)
	if type(scriptName) ~= "string" then return nil end
	local base = scriptName:match("([%w_]+)%.script")
	if not base then return nil end
	if base == "square_roundabouts" then return "square_roundabouts_geometry.lua" end
	if base:sub(1, 19) ~= "square_roundabouts_" then return nil end
	return base .. ".lua"
end

--- Builds the pure geometry of a combo like its updateFn does. Returns built or nil, error.
function footprint.build(entry, params, loader)
	local file = footprint.moduleFile(entry.script)
	if not file then return nil, "unknown updateScript " .. tostring(entry.script) end
	local okL, mod = pcall(loader, footprint.RB_DIR .. file)
	if not okL or type(mod) ~= "table" then return nil, "module " .. file .. " not loadable: " .. tostring(mod) end
	if type(mod.build) ~= "function" then return nil, "module " .. file .. " has no build()" end
	local okB, built = pcall(function()
		local spec
		if type(mod.specFor) == "function" then
			spec = mod.specFor(entry.captureParams, params)
		else
			spec = mod.readParams(params)
		end
		return mod.build(spec)
	end)
	if not okB then return nil, "build failed: " .. tostring(built) end
	if type(built) ~= "table" or type(built.lists) ~= "table" then return nil, "build returned no lists" end
	return built
end

local function hermite(e, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local function c(i) return h00 * (e.p0[i] or 0) + h10 * (e.t0[i] or 0) + h01 * (e.p1[i] or 0) + h11 * (e.t1[i] or 0) end
	return c(1), c(2), c(3)
end

-- Kerb per element kind (sc_shape.KINDS: town, country, highway, bridge, island, other), metres
-- added to the half street width. Tune these from the REFUSED lines' `model=` clearances and kinds.
footprint.KERB_BY_KIND = { 4, 4, 4, 4, 0, 4 }

--- Half width + kerb of a street template; widthOf(template) -> full width (m) or nil.
function footprint.halfWidth(template, widthOf, kind)
	local w
	if widthOf and template then
		local ok, v = pcall(widthOf, template)
		if ok and finite(v) and v > 0 then w = v end
	end
	return (w or footprint.DEFAULT_WIDTH) / 2 + (kind and footprint.KERB_BY_KIND[kind] or footprint.KERB)
end

--- Footprint of edge lists { {template, bridge, edges = {p0, p1, t0, t1}} } (and island outlines
-- polys = { {{x, y, z?}, ...} }) with per-sample growth, or nil + error. The footprint carries its
-- road shape (fp.shape, sc_shape). opts = { widthOf = function(template) : width?, margin = extra m }.
function footprint.fromLists(lists, opts, polys)
	opts = type(opts) == "table" and opts or { margin = tonumber(opts) or 0 }
	local extra = opts.margin or 0
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	local n, maxGrow, maxZ, bridges = 0, 0, 0, 0
	local shp = shapeMod.new()
	local function grow(x, y, g)
		if x - g < minX then minX = x - g end
		if x + g > maxX then maxX = x + g end
		if y - g < minY then minY = y - g end
		if y + g > maxY then maxY = y + g end
	end
	for _, l in ipairs(lists or {}) do
		local kind = shapeMod.kindOf(l.template, l.bridge)
		local half = footprint.halfWidth(l.template, opts.widthOf, kind)
		if l.bridge then bridges = bridges + 1 end
		for _, e in ipairs(l.edges or {}) do
			if not (e.p0 and e.p1 and e.t0 and e.t1) then return nil, "edge without p0/p1/t0/t1" end
			-- length from a coarse sampling, then probes every <= SPACING m
			local len, lx, ly = 0, nil, nil
			for k = 0, footprint.SAMPLES do
				local x, y, z = hermite(e, k / footprint.SAMPLES)
				if not (finite(x) and finite(y) and finite(z)) then return nil, "edge not finite" end
				if lx then len = len + math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2) end
				lx, ly = x, y
			end
			local m = math.max(footprint.SAMPLES, math.ceil(len / shapeMod.SPACING))
			local pts = {}
			for k = 0, m do
				local x, y, z = hermite(e, k / m)
				local g = half + (l.bridge and 0 or footprint.SLOPE * math.abs(z))
				if g < footprint.MIN_GROW then g = footprint.MIN_GROW end
				g = g + extra
				if g > maxGrow then maxGrow = g end
				if math.abs(z) > maxZ then maxZ = math.abs(z) end
				grow(x, y, g)
				pts[#pts + 1] = { x, y, z, g }
			end
			shapeMod.addPolyline(shp, pts, kind)
			n = n + 1
		end
	end
	if n == 0 then return nil, "no edges" end
	for _, poly in ipairs(polys or {}) do
		for _, q in ipairs(poly) do
			if finite(q[1]) and finite(q[2]) then grow(q[1], q[2], shapeMod.POLY_GROW + extra) end
		end
		shapeMod.addPolygon(shp, poly)
	end
	local fp = footprint.box(minX, maxX, minY, maxY, "geometry", n)
	fp.maxGrow, fp.maxZ, fp.bridges, fp.shape = maxGrow, maxZ, bridges, shp
	return fp
end

--- Lists of the pure geometry (built.lists) in fromLists form.
function footprint.listsOfBuilt(built)
	local out = {}
	for _, l in ipairs(built.lists or {}) do
		out[#out + 1] = { template = l.template, bridge = l.edgeType == "BRIDGE", edges = l.edges }
	end
	return out
end

--- Island outlines of the pure geometry (built.island.faces[].outline).
function footprint.polysOfBuilt(built)
	local out = {}
	for _, f in ipairs(built.island and built.island.faces or {}) do
		if type(f.outline) == "table" then out[#out + 1] = f.outline end
	end
	return out
end

--- Ground-face outlines of an updateFn result (the result's own and its subconstructions').
function footprint.polysOfResult(res)
	local out = {}
	local function faces(list)
		for _, gf in ipairs(list or {}) do
			if type(gf) == "table" and type(gf.face) == "table" then out[#out + 1] = gf.face end
		end
	end
	faces(res.groundFaces)
	for _, sc in ipairs(res.subconstructions or {}) do faces(sc.groundFaces) end
	return out
end

--- Footprint of an updateFn result (edgeLists[].edges = {position, tangent, tag?} entries, two per
-- edge: docs/wiki/modding/constructions/basics.md "Edge Lists"), or nil + error.
function footprint.fromResult(res, opts)
	local lists = {}
	for _, el in ipairs(res and res.edgeLists or {}) do
		local edges = {}
		local entries = el.edges or {}
		for i = 1, #entries - 1, 2 do
			local a, b = entries[i], entries[i + 1]
			if type(a) ~= "table" or type(b) ~= "table" then return nil, "bad edge entry" end
			edges[#edges + 1] = { p0 = a[1], t0 = a[2], p1 = b[1], t1 = b[2] }
		end
		lists[#lists + 1] = { template = el.params and el.params.type, bridge = el.edgeType == "BRIDGE", edges = edges }
	end
	local fp, err = footprint.fromLists(lists, opts, footprint.polysOfResult(res))
	if fp then fp.source = "updateFn" end
	return fp, err
end

function footprint.box(minX, maxX, minY, maxY, source, edges)
	local w, h = maxX - minX, maxY - minY
	return {
		minX = minX, maxX = maxX, minY = minY, maxY = maxY,
		w = w, h = h, cx = (minX + maxX) / 2, cy = (minY + maxY) / 2,
		r = math.sqrt(w * w + h * h) / 2,
		source = source, edges = edges or 0,
	}
end

--- The fallback footprint: a size x size box around the origin.
function footprint.fallback(size)
	local s = (size or 400) / 2
	return footprint.box(-s, s, -s, s, "fallback", 0)
end

--- Footprint of a combo from its geometry module, else the fallback box. Returns fp, error-or-nil.
function footprint.measure(combo, loader, opts, fallbackSize)
	local built, err = footprint.build(combo.entry, combo.params, loader)
	if built then
		local fp, e2 = footprint.fromLists(footprint.listsOfBuilt(built), opts, footprint.polysOfBuilt(built))
		if fp then return fp, nil end
		err = e2
	end
	return footprint.fallback(fallbackSize), err
end

return footprint
