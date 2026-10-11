-- Road-shape collisions: conservative against a brute-force distance, islands occupied, kinds, area.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local shape = ug_require "/showcase/sc_shape.lua"
local layout = ug_require "/showcase/sc_layout.lua"
local rngMod = ug_require "/showcase/sc_rng.lua"

--- A straight road from (0, 0) to (len, 0) with buffer g, probes every SPACING.
local function road(len, g)
	local s = shape.new()
	local pts = {}
	local m = math.max(1, math.ceil(len / shape.SPACING))
	for k = 0, m do pts[#pts + 1] = { len * k / m, 0, 0, g } end
	shape.addPolyline(s, pts, 1)
	return s
end

local function place(s, ox, oy, rot) return { fp = { shape = s }, ox = ox, oy = oy, rot = rot } end

--- Exact clearance of two buffered straight roads (segment-segment distance minus both g).
local function segSeg(a, b)
	local function pt(p, x) local c, s = layout.cosSin(p.rot) return p.ox + c * x, p.oy + s * x end
	local ax0, ay0 = pt(a, 0)
	local ax1, ay1 = pt(a, a.len)
	local bx0, by0 = pt(b, 0)
	local bx1, by1 = pt(b, b.len)
	local function pd(px, py, x0, y0, x1, y1)
		local dx, dy = x1 - x0, y1 - y0
		local L2 = dx * dx + dy * dy
		local t = math.max(0, math.min(1, ((px - x0) * dx + (py - y0) * dy) / L2))
		return math.sqrt((px - x0 - t * dx) ^ 2 + (py - y0 - t * dy) ^ 2)
	end
	-- crossing segments: 0
	local function cross(ox, oy, px, py, qx, qy) return (px - ox) * (qy - oy) - (py - oy) * (qx - ox) end
	local d1, d2 = cross(ax0, ay0, ax1, ay1, bx0, by0), cross(ax0, ay0, ax1, ay1, bx1, by1)
	local d3, d4 = cross(bx0, by0, bx1, by1, ax0, ay0), cross(bx0, by0, bx1, by1, ax1, ay1)
	local d = 0
	if not (d1 * d2 < 0 and d3 * d4 < 0) then
		d = math.min(pd(ax0, ay0, bx0, by0, bx1, by1), pd(ax1, ay1, bx0, by0, bx1, by1),
			pd(bx0, by0, ax0, ay0, ax1, ay1), pd(bx1, by1, ax0, ay0, ax1, ay1))
	end
	return d - a.g - b.g
end

test("collide never misses a real overlap, and frees clearly separated roads (random pairs)", function()
	local r = rngMod.new(7)
	local missed, falseHits, n = 0, 0, 0
	for _ = 1, 400 do
		local la, lb = 20 + r:next() * 200, 20 + r:next() * 200
		local ga, gb = 6 + r:next() * 20, 6 + r:next() * 20
		local gap = ({ 0, 5, 10 })[r:int(1, 3)]
		local a = place(road(la, ga), 0, 0, r:next() * 360)
		local b = place(road(lb, gb), (r:next() - 0.5) * 300, (r:next() - 0.5) * 300, r:next() * 360)
		a.len, a.g, b.len, b.g = la, ga, lb, gb
		local D = 30 + gap + shape.SLACK + 1
		local hit = shape.collide(a, b, gap, D, layout.cosSin)
		local c = segSeg(a, b)
		n = n + 1
		if c < gap and not hit then missed = missed + 1 end
		if c > gap + 2 * shape.SLACK and hit then falseHits = falseHits + 1 end
	end
	eq(missed, 0, "missed overlaps")
	eq(falseHits, 0, "hits beyond the slack")
	ok(n == 400)
end)

test("an island polygon is occupied: a small road inside it collides, from either side", function()
	local ring = road(10, 6)
	local outline = {}
	for k = 0, 31 do
		local a = k / 32 * 2 * math.pi
		outline[#outline + 1] = { 100 * math.cos(a), 100 * math.sin(a), 0 }
	end
	shape.addPolygon(ring, outline)
	local small = road(20, 6)
	local D = 40
	-- the small road wholly inside the island (far from the outline and the ring's own road)
	local A = place(ring, 0, 0, 0)
	local B = place(small, -40, 30, 0)
	ok(shape.collide(A, B, 0, D, layout.cosSin), "ring vs small")
	ok(shape.collide(B, A, 0, D, layout.cosSin), "small vs ring")
	-- outside it: free
	local C = place(small, 300, 0, 0)
	ok(not shape.collide(A, C, 0, D, layout.cosSin))
end)

test("kinds, area, field reuse", function()
	eq(shape.kindOf("::/infrastructure/street/highway/highway_new_small.street_template"), 3)
	eq(shape.kindOf("::/infrastructure/street/town/town_new_small.street_template", true), 4)
	eq(shape.KINDS[shape.kindOf("x/country/y")], "country")
	local s = road(100, 10)
	local a = shape.area(s)
	-- a 100 m road buffered by 10 m: about 100 x 20 + two half discs
	ok(a > 1800 and a < 2900, "area " .. a)
	local f = shape.field(s, 20)
	ok(shape.field(s, 10) == f, "a smaller range reuses the field")
end)

test("real footprints carry shapes with islands where the roundabout has one", function()
	local combos = ug_require "/showcase/sc_combos.lua"
	local footprint = ug_require "/showcase/sc_footprint.lua"
	local ring
	for _, e in ipairs(H.entries({ "ring" })) do ring = e end
	local v = combos.defaults(ring)
	local isl, scale
	for i, p in ipairs(ring.params) do
		if p.key == "sqrb_island" then isl = i end
		if p.key:find("radius_size", 1, true) then scale = i end
	end
	v[isl] = 2 -- grass
	v[scale] = 4 -- L: a real island
	local fp = footprint.measure(combos.make(ring, v), H.rbRequire, H.FP_OPTS, 400)
	ok(fp.shape and fp.shape.n > 20, "probes")
	ok(#fp.shape.polys >= 1, "island polygon")
	ok(fp.maxGrow >= footprint.MIN_GROW)
end)
