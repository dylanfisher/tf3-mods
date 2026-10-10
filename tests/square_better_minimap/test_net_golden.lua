-- minimap_net golden output (PERF_REVIEW.md "Network layer (2026-10-09)"): a fixed synthetic network
-- is sampled, rasterised (adds, then removals) and encoded in both palettes and both row orders.
-- The checksums were computed with the code BEFORE the 2026-10-09 performance changes, so any
-- optimisation of hermitePolyline / drawPolyline / fillRect / encodeRows must keep every byte.

local net = ug_require "square_better_minimap::/minimap/minimap_net.tl"
local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl"

-- Deterministic generator (own LCG: independent of math.random).
local function lcg(seed)
	local x = seed
	return function()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

--- A synthetic network over `box`: nEdges edges (streets / tracks, every 13th a tunnel, a few long
--- ones, curved tangents) and nBuildings town buildings. Items in image pixels, like the scheduler's.
local function synth(box, w, h, nEdges, nBuildings, seed)
	local rnd = lcg(seed)
	local xf = net.makeXform(box, geom.DEFAULT_ORIENT, w, h)
	local W, H = box.maxX - box.minX, box.maxY - box.minY
	local items = {}
	for i = 1, nEdges do
		local x0 = box.minX + rnd() * W
		local y0 = box.minY + rnd() * H
		local len = (i % 50 == 0) and (500 + rnd() * 4000) or (20 + rnd() * 180)
		local a = rnd() * 2 * math.pi
		local x1, y1 = x0 + math.cos(a) * len, y0 + math.sin(a) * len
		local bend = (rnd() - 0.5) * 1.2
		local t0x, t0y = math.cos(a + bend) * len, math.sin(a + bend) * len
		local t1x, t1y = math.cos(a - bend) * len, math.sin(a - bend) * len
		items[#items + 1] = {
			kind = (i % 3 == 0) and net.KIND_TRACK or net.KIND_STREET,
			dashed = (i % 13 == 0),
			pts = net.hermitePolyline(xf, x0, y0, t0x, t0y, x1, y1, t1x, t1y),
		}
	end
	for _ = 1, nBuildings do
		local cx = box.minX + rnd() * W
		local cy = box.minY + rnd() * H
		local sx, sy = 8 + rnd() * 30, 8 + rnd() * 30
		local x0, y0, x1, y1 = net.rectFromBounds(xf, cx - sx, cy - sy, cx + sx, cy + sy)
		items[#items + 1] = { kind = net.KIND_TOWN, x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
	end
	return items
end

local function sum(acc, v)
	return (acc * 31 + v) % 4294967291
end

local function ptsChecksum(items)
	local c = 0
	for _, it in ipairs(items) do
		if it.pts then
			for _, v in ipairs(it.pts) do c = sum(c, v + 100000) end
		else
			c = sum(sum(sum(sum(c, it.x0 + 100000), it.y0 + 100000), it.x1 + 100000), it.y1 + 100000)
		end
	end
	return c
end

local function gridChecksum(g)
	local c = 0
	for i = 1, #g.cells do c = sum(c, net.layerOf(g.cells[i]) + 4 * (g.cells[i] % 4096)) end
	return c
end

local function bufChecksum(out)
	local c = 0
	for i = 1, #out do c = sum(c, out[i]) end
	return c
end

--- Adds every item, removes every 7th, re-adds every 21st; encodes in 4 variants.
local function run(box, w, h, nEdges, nBuildings, seed)
	local items = synth(box, w, h, nEdges, nBuildings, seed)
	local g = net.newGrid(w, h)
	for _, it in ipairs(items) do net.drawItem(g, it, 1) end
	for i = 7, #items, 7 do net.drawItem(g, items[i], -1) end
	for i = 21, #items, 21 do net.drawItem(g, items[i], 1) end
	local res = { pts = ptsChecksum(items), grid = gridChecksum(g) }
	local out = {}
	for _, v in ipairs({ { false, false }, { false, true }, { true, false }, { true, true } }) do
		local pal = net.paletteFor(v[1], "RGBA")
		net.encodeRows(g, out, 0, h, pal, v[2])
		eq(#out, net.expectedLength(w, h))
		res[#res + 1] = bufChecksum(out)
	end
	return res
end

local WIDE = geom.boxFromBounds(-8000, -4000, 8000, 4000)   -- 512 x 256
local SQUARE = geom.boxFromBounds(-4000, -4000, 4000, 4000) -- 512 x 512

-- Values computed with the pre-change minimap_net.tl (2026-10-09). Do not update them to make a
-- test pass: a different value means the picture changed.
local GOLDEN = {
	wide = { pts = 2832688202, grid = 2349064048, 1947100600, 2554812317, 505795453, 2647568538 },
	square = { pts = 257152135, grid = 3692458589, 146048218, 2751314373, 2005494191, 1943767335 },
}

local function check(name, res)
	local g = GOLDEN[name]
	eq(res.pts, g.pts, name .. " polylines")
	eq(res.grid, g.grid, name .. " grid")
	eq(res[1], g[1], name .. " normal, top-down")
	eq(res[2], g[2], name .. " normal, rows flipped")
	eq(res[3], g[3], name .. " hi-vis, top-down")
	eq(res[4], g[4], name .. " hi-vis, rows flipped")
end

test("golden: 512x256 image, 6000 edges + 5000 buildings, both palettes and row orders", function()
	local w, h = net.imageSize(WIDE, geom.DEFAULT_ORIENT, 512)
	eq(w, 512); eq(h, 256)
	check("wide", run(WIDE, w, h, 6000, 5000, 12345))
end)

test("golden: 512x512 image, 8000 edges + 6000 buildings, both palettes and row orders", function()
	local w, h = net.imageSize(SQUARE, geom.DEFAULT_ORIENT, 512)
	eq(w, 512); eq(h, 512)
	check("square", run(SQUARE, w, h, 8000, 6000, 777))
end)
