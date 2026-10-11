-- Layout patterns: no overlaps, inside the max radius, caps, determinism, kaleidoscope symmetry,
-- no NaN / -0.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local layout = ug_require "/showcase/sc_layout.lua"
local combos = ug_require "/showcase/sc_combos.lua"
local footprint = ug_require "/showcase/sc_footprint.lua"

local SYMS = { "R", "I", "M", "C", "P", "Q", "D" }
local ENTRY = { "ring", "interchange", "magic", "channel", "parclo", "parclo2", "diamond" }

--- n synthetic items: footprints from 60 x 60 to 900 x 560, off-centre bboxes, both sides, with
-- mirror footprints (bbox centre mirrored in x, as square_roundabouts mirrors x -> -x).
local function mix(n)
	local sizes = { { 60, 60 }, { 90, 70 }, { 140, 140 }, { 220, 180 }, { 300, 120 }, { 420, 260 }, { 900, 560 }, { 600, 600 } }
	local items = {}
	for i = 1, n do
		local s = sizes[(i - 1) % #sizes + 1]
		local cx, cy = ((i * 37) % 11 - 5) * 3, ((i * 53) % 7 - 3) * 4
		local k = (i - 1) % #ENTRY + 1
		items[i] = {
			combo = { key = "k" .. i }, fp = H.fakeFp(s[1], s[2], cx, cy), entry = ENTRY[k], entryIndex = k,
			symbol = SYMS[k], colour = ENTRY[k] .. ":" .. (i % 3), side = (i % 2) + 1,
			mirror = { combo = { key = "m" .. i }, fp = H.fakeFp(s[1], s[2], -cx, cy) },
		}
	end
	return items
end

local function isNegZero(v) return v == 0 and 1 / v < 0 end

-- Ground truth for road shapes, independent of the clearance fields: the smallest distance between
-- a probe of one shape and a (merged, buffered) segment of the other, minus both buffers, over both
-- directions. The packer's test is conservative, so placed shapes must keep at least the gap.
local function worldOf(p, x, y)
	local c, s = layout.cosSin(p.rot)
	local ox, oy = layout.originOf(p)
	return ox + c * x - s * y, oy + s * x + c * y
end

local function segDist(px, py, x0, y0, x1, y1)
	local dx, dy = x1 - x0, y1 - y0
	local L2 = dx * dx + dy * dy
	local t = L2 > 0 and math.max(0, math.min(1, ((px - x0) * dx + (py - y0) * dy) / L2)) or 0
	return math.sqrt((px - x0 - t * dx) ^ 2 + (py - y0 - t * dy) ^ 2)
end

local function shapeClearance(p, q)
	local best = math.huge
	for _, pair in ipairs({ { p, q }, { q, p } }) do
		local a, b = pair[1], pair[2]
		local A, B = a.fp.shape, b.fp.shape
		local segs = {}
		for i, sg in ipairs(B.segs) do
			local x0, y0 = worldOf(b, sg[1], sg[2])
			local x1, y1 = worldOf(b, sg[3], sg[4])
			segs[i] = { x0, y0, x1, y1, sg[5] }
		end
		for i = 1, A.n do
			local ax, ay = worldOf(a, A.px[i], A.py[i])
			for _, sg in ipairs(segs) do
				local v = segDist(ax, ay, sg[1], sg[2], sg[3], sg[4]) - sg[5] - A.pg[i]
				if v < best then best = v end
			end
		end
	end
	return best
end

-- shapeD: the placements carry road shapes; overlapping boxes are fine where the roads keep the gap
local function checkPlacements(ps, gap, maxR, label, shapeD)
	local packer = shapeD and true
	for i, p in ipairs(ps) do
		for _, k in ipairs({ "x", "y", "rot", "ox", "oy" }) do
			ok(layout.finite(p[k]), label .. ": " .. k .. " finite")
			ok(not isNegZero(p[k]), label .. ": " .. k .. " is -0")
		end
		ok(p.rot >= 0 and p.rot < 360, label .. ": rot range")
		local c, s = layout.cosSin(p.rot)
		ok(not isNegZero(c) and not isNegZero(s), label .. ": cos/sin -0")
		local d = math.sqrt((p.x - (p.cx0 or 0)) ^ 2 + (p.y - (p.cy0 or 0)) ^ 2)
		ok(d + p.fp.r <= maxR + 1e-6, label .. ": inside max radius")
		-- the origin puts the bbox centre at (x, y)
		local bx = p.ox + c * p.fp.cx - s * p.fp.cy
		local by = p.oy + s * p.fp.cx + c * p.fp.cy
		near(bx, p.x, 1e-6, label .. ": origin x")
		near(by, p.y, 1e-6, label .. ": origin y")
		for j = i + 1, #ps do
			if packer then
				if p.fp.shape and ps[j].fp.shape and layout.overlaps(p, ps[j], gap) then
					local c = shapeClearance(p, ps[j])
					ok(c >= gap - 1e-6, string.format("%s: roads %d/%d only %.2f m apart", label, i, j, c))
				end
			else
				ok(not layout.overlaps(p, ps[j], gap), label .. ": overlap " .. i .. "/" .. j)
			end
		end
	end
end

local ROTATIONS = { "pattern", "fixed", "face", "random90", "random" }

test("every pattern and rotation: no overlaps, nothing dropped for overlap, inside the radius", function()
	local n = 0
	for _, pattern in ipairs(layout.PATTERNS) do
		for _, rot in ipairs(ROTATIONS) do
			for _, seed in ipairs({ 1, 7 }) do
				local items = mix(60)
				local opts = { pattern = pattern, gap = 40, rotation = rot, seed = seed, cx = 0, cy = 0, maxRadius = 20000, cap = 2000 }
				local ps, dropped = layout.run(items, opts)
				local label = pattern .. "/" .. rot .. "/" .. seed
				checkPlacements(ps, 40, 20000, label)
				for _, d in ipairs(dropped) do
					ok(d.reason ~= "overlap" and d.reason ~= "not finite", label .. ": dropped for " .. d.reason)
				end
				-- every item is placed (the kaleidoscope: every item's whole orbit)
				local copies = pattern == "kaleido4" and 8 or pattern == "kaleido8" and 16 or 1
				eq(#ps, copies == 1 and 60 or 1 + copies * 59, label .. ": all placed")
				n = n + 1
			end
		end
	end
	ok(n == #layout.PATTERNS * 10)
end)

test("the max radius trims and the cap holds", function()
	for _, pattern in ipairs(layout.PATTERNS) do
		local ps, dropped = layout.run(mix(80), { pattern = pattern, gap = 20, seed = 2, maxRadius = 1500, cap = 30, cx = 500, cy = -700 })
		-- the kaleidoscope's cap is on combos (sc_combos), it places every orbit that fits
		if pattern ~= "kaleido4" and pattern ~= "kaleido8" then ok(#ps <= 30, pattern .. ": cap") end
		for _, p in ipairs(ps) do p.cx0, p.cy0 = 500, -700 end
		checkPlacements(ps, 20, 1500, pattern)
		ok(#dropped > 0, pattern .. ": something dropped")
	end
end)

test("deterministic: the same seed gives the same layout, scatter changes with the seed", function()
	for _, pattern in ipairs(layout.PATTERNS) do
		local a = layout.run(mix(40), { pattern = pattern, gap = 30, rotation = "random", seed = 5, maxRadius = 20000 })
		local b = layout.run(mix(40), { pattern = pattern, gap = 30, rotation = "random", seed = 5, maxRadius = 20000 })
		eq(#a, #b, pattern)
		for i = 1, #a do
			eq(a[i].item.combo.key, b[i].item.combo.key, pattern)
			eq(a[i].x, b[i].x, pattern)
			eq(a[i].rot, b[i].rot, pattern)
		end
	end
	local a = layout.run(mix(40), { pattern = "scatter", gap = 30, seed = 1, maxRadius = 8000 })
	local b = layout.run(mix(40), { pattern = "scatter", gap = 30, seed = 2, maxRadius = 8000 })
	local same = true
	for i = 1, math.min(#a, #b) do if a[i].x ~= b[i].x then same = false end end
	ok(not same)
end)

local function findAt(ps, x, y)
	for _, p in ipairs(ps) do
		if math.abs(p.x - x) < 1e-6 and math.abs(p.y - y) < 1e-6 then return p end
	end
	return nil
end

test("kaleidoscope: D4 / D8 symmetry, true mirrors with the traffic side's footprint", function()
	for _, n in ipairs({ 4, 8 }) do
		for _, rot in ipairs({ "pattern", "fixed", "random90", "random" }) do
			local ps = layout.run(mix(30), { pattern = "kaleido" .. n, gap = 40, rotation = rot, seed = 3, maxRadius = 1e6, cap = 1000 })
			ok(#ps > 2 * n, "placed")
			eq((#ps - 1) % (2 * n), 0, "orbits of 2n")
			for _, p in ipairs(ps) do
				if p.x ~= 0 or p.y ~= 0 then
					-- rotation by 360 / n: same combo, same side, rotation + 360 / n
					local a = math.rad(360 / n)
					local q = findAt(ps, p.x * math.cos(a) - p.y * math.sin(a), p.x * math.sin(a) + p.y * math.cos(a))
					ok(q, "rotated copy")
					eq(q.item, p.item)
					eq(q.mirrored, p.mirrored)
					local step = (q.rot - p.rot - 360 / n) % 360
					ok(step < 1e-4 or step > 360 - 1e-4, "rotation step")
					-- mirror about the x axis: the other side, rotation 180 - theta
					local m = findAt(ps, p.x, -p.y)
					ok(m, "mirror copy")
					eq(m.item, p.item)
					eq(m.mirrored, not p.mirrored)
					local want = layout.normRot(180 - p.rot)
					local diff = math.abs(m.rot - want)
					ok(diff < 1e-4 or math.abs(diff - 360) < 1e-4, "mirror rotation")
					-- the mirror's footprint is the mirrored combo's
					eq(m.fp, m.mirrored and m.item.mirror.fp or m.item.fp)
				end
			end
		end
	end
end)

test("kaleidoscope: the max radius drops whole orbits only", function()
	for _, n in ipairs({ 4, 8 }) do
		for _, maxR in ipairs({ 800, 1500, 3000 }) do
			local ps, dropped = layout.run(mix(120), { pattern = "kaleido" .. n, gap = 40, seed = 1, maxRadius = maxR, cap = 1000 })
			eq((#ps - 1) % (2 * n), 0, n .. "/" .. maxR .. ": orbits of 2n")
			local outside = 0
			for _, d in ipairs(dropped) do if d.reason == "outside max radius" then outside = outside + 1 end end
			ok(outside > 0, "something outside")
			checkPlacements(ps, 40, maxR, "kaleido" .. n .. "/" .. maxR)
		end
	end
end)

test("kaleidoscope: every item's orbit is placed, nothing sampled away", function()
	local ps, dropped = layout.run(mix(40), { pattern = "kaleido4", gap = 10, seed = 1, maxRadius = 1e6, cap = 10 })
	eq(#ps, 1 + 8 * 39)
	eq(#dropped, 0)
end)

test("relocate: the nearest free spot, the refused spot stays blocked", function()
	local ps = layout.run(mix(30), { pattern = "grid", gap = 10, seed = 1, maxRadius = 1e6, cx = 100, cy = 200 })
	local packer = layout.packerOf(ps, 10)
	local p = ps[5]
	local q = layout.relocate(packer, p, { cx = 100, cy = 200, maxRadius = 1e6 })
	ok(q, "moved")
	ok(not layout.overlaps(p, q, 10), "off the refused spot")
	for i, o in ipairs(ps) do if o ~= p then ok(not layout.overlaps(o, q, 10), "free of " .. i) end end
	eq(q.item, p.item)
	eq(q.rot, p.rot)
	local c, s2 = layout.cosSin(q.rot)
	near(q.ox + c * q.fp.cx - s2 * q.fp.cy, q.x, 1e-6)
	ok(not isNegZero(q.x) and not isNegZero(q.ox))
	-- nothing within a tiny max radius
	eq(layout.relocate(packer, p, { cx = 100, cy = 200, maxRadius = 10 }), nil)
end)

test("cosSin is exact at multiples of 90 and never -0; normRot never -0", function()
	eq({ layout.cosSin(0) }, { 1, 0 })
	eq({ layout.cosSin(90) }, { 0, 1 })
	eq({ layout.cosSin(-90) }, { 0, -1 })
	eq({ layout.cosSin(180) }, { -1, 0 })
	eq({ layout.cosSin(720) }, { 1, 0 })
	local z = 0.0
	ok(not isNegZero(layout.normRot(-z)))
	ok(not isNegZero(layout.plusZero(-z)))
	ok(not isNegZero(select(2, layout.cosSin(-z))))
	eq(layout.normRot(-90), 270)
	eq(layout.normRot(359.9999999), 0)
end)

local function realItems(cap)
	local list = combos.enumerate(H.entries(), "showcase", cap, 1)
	local items = {}
	for i, c in ipairs(list) do
		local m = combos.mirrorOf(c)
		items[i] = { combo = c, fp = footprint.measure(c, H.rbRequire, H.FP_OPTS, 400), entry = c.entry.id, entryIndex = 1,
			symbol = c.entry.symbol, colour = c.entry.id, side = c.values[combos.mirrorParam(c.entry)],
			mirror = { combo = m, fp = footprint.measure(m, H.rbRequire, H.FP_OPTS, 400) } }
	end
	return items
end

-- Fill (footprint area / bounding box) of every entry's 126 showcase combos at gap 10 with the
-- measured street margins, no radius limit. OLD = the previous algorithm (circle rings, column-max
-- grids, kaleidoscope sampled to the cap) on the same footprints, measured 2026-10-10.
local OLD_FILL = { grid = 0.740, mosaic = 0.548, kaleido4 = 0.200, kaleido8 = 0.194, mandala = 0.235,
	spiral = 0.238, gradient = 0.274, checker = 0.348, scatter = 0.0 }
local MIN_FILL = { grid = 0.80, mosaic = 0.60, kaleido4 = 0.45, kaleido8 = 0.40, mandala = 0.33,
	spiral = 0.33, gradient = 0.70, checker = 0.80, scatter = 0.30 }

test("density (boxes only): every pattern packs much tighter than the first version", function()
	local items = realItems(250)
	eq(#items, 126)
	for _, pattern in ipairs(layout.PATTERNS) do
		local ps, dropped = layout.run(items, { pattern = pattern, gap = 10, seed = 1, maxRadius = 1e6, cap = 1e6, shapes = false })
		local fill = layout.fill(ps)
		eq(#dropped, 0, pattern .. ": nothing dropped")
		ok(fill >= MIN_FILL[pattern], string.format("%s: fill %.1f%% >= %.0f%%", pattern, fill * 100, MIN_FILL[pattern] * 100))
		if OLD_FILL[pattern] > 0.5 then
			ok(fill >= OLD_FILL[pattern] + 0.1, pattern .. ": better than the old layout")
		else
			ok(fill >= OLD_FILL[pattern] * 1.4, string.format("%s: %.1f%% vs old %.1f%%", pattern, fill * 100, OLD_FILL[pattern] * 100))
		end
	end
end)

test("real footprints: every entry's showcase combos in every pattern without overlaps", function()
	local entries = H.entries()
	local list = combos.enumerate(entries, "showcase", 140, 1)
	local items = {}
	for i, c in ipairs(list) do
		local fp = footprint.measure(c, H.rbRequire, H.FP_OPTS, 400)
		local m = combos.mirrorOf(c)
		items[i] = { combo = c, fp = fp, entry = c.entry.id, entryIndex = 1, symbol = c.entry.symbol, colour = c.entry.id,
			side = c.values[combos.mirrorParam(c.entry)], mirror = { combo = m, fp = footprint.measure(m, H.rbRequire, H.FP_OPTS, 400) } }
	end
	-- a kaleidoscope places 8 / 16 copies of each: every 5th combo keeps the brute-force check short
	local few = {}
	for i = 1, #items, 5 do few[#few + 1] = items[i] end
	for _, pattern in ipairs(layout.PATTERNS) do
		local use = (pattern == "kaleido4" or pattern == "kaleido8") and few or items
		local ps, dropped = layout.run(use, { pattern = pattern, gap = 10, seed = 1, maxRadius = 50000, cap = 1000 })
		checkPlacements(ps, 10, 50000, "real " .. pattern, layout.shapeRange(use, 10))
		for _, d in ipairs(dropped) do ok(d.reason ~= "overlap", pattern .. ": overlap drop") end
	end
end)

test("fill: repeats until the cap or the max radius, no overlaps, kaleidoscope orbits stay whole", function()
	for _, pattern in ipairs(layout.PATTERNS) do
		-- the cap binds
		local ps = layout.run(mix(5), { pattern = pattern, gap = 10, seed = 1, maxRadius = 1e5, cap = 150, fill = true })
		ok(#ps <= 150, pattern .. ": cap " .. #ps)
		ok(#ps > 100, pattern .. ": filled to near the cap " .. #ps)
		checkPlacements(ps, 10, 1e5, pattern .. " fill/cap")
		local repeats = 0
		for _, p in ipairs(ps) do if p.item.cycle then repeats = repeats + 1 end end
		ok(repeats > 0, pattern .. ": repeats")
		if pattern == "kaleido4" or pattern == "kaleido8" then
			local n = pattern == "kaleido4" and 4 or 8
			eq((#ps - 1) % (2 * n), 0, pattern .. ": whole orbits")
		end
		-- the radius binds: nothing outside, and the disc is well used
		local qs, dropped = layout.run(mix(12), { pattern = pattern, gap = 10, seed = 1, maxRadius = 1500, cap = 1e5, fill = true })
		checkPlacements(qs, 10, 1500, pattern .. " fill/radius")
		local area = 0
		for _, p in ipairs(qs) do area = area + p.fp.w * p.fp.h end
		ok(area / (math.pi * 1500 * 1500) > 0.25, string.format("%s: disc %.0f%% used", pattern, area / (math.pi * 1500 * 1500) * 100))
		for _, d in ipairs(dropped) do ok(d.reason ~= "overlap", pattern .. ": overlap") end
	end
end)

test("fill Off: each item once (the old behaviour)", function()
	local ps = layout.run(mix(12), { pattern = "spiral", gap = 10, seed = 1, maxRadius = 1e5, cap = 150, fill = false })
	eq(#ps, 12)
end)

-- Road shapes vs boxes at gap 0, radius 3000, Repeat, all 126 showcase combos (constructions placed,
-- measured 2026-10-10: boxes -> shapes). The shapes let arms interlock and small pieces sit in the
-- empty corners of big ones.
local SHAPE_GAIN = { grid = 1.05, mosaic = 1.0, kaleido4 = 1.25, kaleido8 = 1.25, mandala = 1.3, spiral = 1.3,
	gradient = 1.05, checker = 1.05, scatter = 1.3 }

test("road shapes: many more constructions than boxes in the same disc, roads never collide", function()
	for _, pattern in ipairs(layout.PATTERNS) do
		local items = realItems(250)
		local boxes = layout.run(items, { pattern = pattern, gap = 0, seed = 1, maxRadius = 3000, cap = 10000, fill = true, shapes = false })
		local ps = layout.run(items, { pattern = pattern, gap = 0, seed = 1, maxRadius = 3000, cap = 10000, fill = true })
		print(string.format("%-9s boxes %4d  shapes %4d  roadFill %.1f%% -> %.1f%%", pattern, #boxes, #ps,
			layout.roadFill(boxes) * 100, layout.roadFill(ps) * 100))
		ok(#ps >= #boxes * SHAPE_GAIN[pattern], string.format("%s: %d vs %d boxes", pattern, #ps, #boxes))
		if pattern == "spiral" or pattern == "grid" then
			checkPlacements(ps, 0, 3000, "shapes " .. pattern, layout.shapeRange(items, 0))
		end
	end
end)
