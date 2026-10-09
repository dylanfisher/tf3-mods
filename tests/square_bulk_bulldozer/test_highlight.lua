-- bb_highlight: mode switches, colours per phase, overlay segments along edge curves (user report
-- 2026-10-07: the selection was invisible in the world; research §11).

local hl = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_highlight.tl"

local function straight(x0, y0, x1, y1, z0, z1)
	local dx, dy = x1 - x0, y1 - y0
	return { p0x = x0, p0y = y0, t0x = dx, t0y = dy, p1x = x1, p1y = y1, t1x = dx, t1y = dy,
		p0z = z0, p1z = z1, t0z = z0 and (z1 - z0) or nil, t1z = z0 and (z1 - z0) or nil }
end

test("default mode draws both the engine tint and the overlay lines", function()
	eq(hl.MODE, "both")
	ok(hl.usesEngine(hl.MODE))
	ok(hl.usesLines(hl.MODE))
	ok(hl.usesEngine("engine") and not hl.usesLines("engine"))
	ok(hl.usesLines("lines") and not hl.usesEngine("lines"))
	ok(not hl.usesEngine("off") and not hl.usesLines("off"))
	ok(hl.HOVER_ONLY_HIGHLIGHTED)
end)

test("describeMode names the active path", function()
	ok(hl.describeMode("both"):find("engine tint", 1, true))
	ok(hl.describeMode("lines"):find("red lines", 1, true))
	ok(hl.describeMode("engine"):find("highlightedEntities", 1, true))
	ok(hl.describeMode("x"):find("unknown", 1, true))
end)

test("colours: selection is opaque bulldoze red, hover preview lighter and fainter", function()
	for _, ph in ipairs({ "painting", "selected", "committing" }) do
		local c = hl.colors(ph)
		near(c.line[1], 206 / 255, 1e-9, ph)
		near(c.line[2], 32 / 255, 1e-9, ph)
		near(c.outline1[4], 1.0, 1e-9, ph)
		ok(c.fill[4] > 0, "visible fill " .. ph)
		ok(c.outline[4] > 0, "visible outline " .. ph)
	end
	local sel, prev = hl.colors("selected"), hl.colors("idle")
	ok(prev.line[2] > sel.line[2], "preview is lighter (coral)")
	ok(prev.fill[4] < sel.fill[4], "preview fill fainter")
	ok(prev.line[4] < sel.line[4], "preview line fainter")
	ok(prev.lineWidth < sel.lineWidth, "preview line thinner")
	for _, k in ipairs({ "fill", "outline", "outline1", "line" }) do
		eq(#sel[k], 4, k)
		for i = 1, 4 do ok(sel[k][i] >= 0 and sel[k][i] <= 1, k .. i) end
	end
end)

test("piecesFor: ~SEGMENT_LENGTH pieces, at least 1, at most MAX_PER_EDGE", function()
	eq(hl.piecesFor(0), 1)
	eq(hl.piecesFor(nil), 1)
	eq(hl.piecesFor(1), 1)
	eq(hl.piecesFor(hl.SEGMENT_LENGTH), 1)
	eq(hl.piecesFor(hl.SEGMENT_LENGTH + 0.1), 2)
	eq(hl.piecesFor(10000), hl.MAX_PER_EDGE)
end)

test("curveLength of a straight edge is its length", function()
	near(hl.curveLength(straight(0, 0, 30, 40)), 50, 1e-9)
end)

test("curveZ: Hermite heights, nil without z", function()
	local c = straight(0, 0, 100, 0, 10, 20)
	near(hl.curveZ(c, 0), 10, 1e-9)
	near(hl.curveZ(c, 1), 20, 1e-9)
	near(hl.curveZ(c, 0.5), 15, 1e-9)
	eq(hl.curveZ(straight(0, 0, 1, 1), 0.5), nil)
end)

test("edgeSegments: a straight edge becomes a connected polyline from end to end", function()
	local segs, trunc = hl.edgeSegments({ straight(0, 0, 60, 0, 5, 5) }, 100)
	eq(trunc, false)
	eq(#segs, 4)   -- 60 m / 15 m
	near(segs[1].x0, 0, 1e-9)
	near(segs[#segs].x1, 60, 1e-9)
	for i = 2, #segs do
		near(segs[i].x0, segs[i - 1].x1, 1e-9, "joint x " .. i)
		near(segs[i].y0, segs[i - 1].y1, 1e-9, "joint y " .. i)
		near(segs[i].z0, segs[i - 1].z1, 1e-9, "joint z " .. i)
	end
	for _, s in ipairs(segs) do
		near(s.z0, 5, 1e-9)
		near(s.y0, 0, 1e-9)
	end
end)

test("edgeSegments: curved edge stays on its Hermite curve", function()
	-- quarter-ish bend from (0,0) heading +x to (50,50) heading +y
	local c = { p0x = 0, p0y = 0, t0x = 70, t0y = 0, p1x = 50, p1y = 50, t1x = 0, t1y = 70 }
	local segs = hl.edgeSegments({ c }, 100)
	ok(#segs >= 4)
	near(segs[#segs].x1, 50, 1e-9)
	near(segs[#segs].y1, 50, 1e-9)
	-- the middle point bulges below the chord y = x
	local mid = segs[math.floor(#segs / 2)]
	ok(mid.x1 > mid.y1, "bends like the curve")
end)

test("edgeSegments: heights from heightAt when the curve has none, else 0", function()
	local segs = hl.edgeSegments({ straight(0, 0, 10, 0) }, 10, function(x, y) return 100 + x end)
	eq(#segs, 1)
	near(segs[1].z0, 100, 1e-9)
	near(segs[1].z1, 110, 1e-9)
	local segs0 = hl.edgeSegments({ straight(0, 0, 10, 0) }, 10)
	near(segs0[1].z0, 0, 1e-9)
end)

test("edgeSegments: over budget, edges get fewer pieces first, never zero", function()
	local curves = {}
	for i = 1, 10 do curves[i] = straight(0, i * 10, 120, i * 10, 0, 0) end   -- 8 pieces each = 80
	local segs, trunc = hl.edgeSegments(curves, 20)
	eq(trunc, false, "every edge still drawn")
	ok(#segs <= 20)
	ok(#segs >= 10)
	-- every edge reaches its far end
	local ends = 0
	for _, s in ipairs(segs) do if math.abs(s.x1 - 120) < 1e-9 then ends = ends + 1 end end
	eq(ends, 10)
end)

test("edgeSegments: more edges than budget → capped and truncated", function()
	local curves = {}
	for i = 1, 30 do curves[i] = straight(0, i, 5, i) end
	local segs, trunc = hl.edgeSegments(curves, 12)
	eq(#segs, 12)
	eq(trunc, true)
end)

test("edgeSegments: empty / bad input", function()
	local segs, trunc = hl.edgeSegments({}, 10)
	eq(#segs, 0)
	eq(trunc, false)
	segs, trunc = hl.edgeSegments({ straight(0, 0, 1, 0) }, 0)
	eq(#segs, 0)
	eq(trunc, true)
end)
