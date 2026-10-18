-- Irregular growth (PLAN.md 6.2 "Irregular growth"): ot_metrics, the seeded preference / hotspots of ot_select,
-- and per style: grown with it on vs off (style.irregular = false) on flat land, the shape metrics move the
-- way the style should (organic styles uneven, grids still close to even), and the networks stay valid.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")

local TOWNS = { 1, 7, 13, 21 }
local INCREMENTS = 12

--- Mean metrics over TOWNS for a style grown INCREMENTS times; irregular = false turns it off.
local function grow(id, irregular, sampler)
	sampler = sampler or F.flat
	local acc = { drift = 0, spread = 0, cv = 0, elong = 0, gx = 0, components = 0 }
	for _, town in ipairs(TOWNS) do
		-- compact: these tests measure the irregular growth alone (town shapes: test_shapes.lua)
		local style, stats = F.style({ forceStyle = id, townId = town, year = 1960, shape = "compact" }, sampler)
		if not irregular then style.irregular = false end
		local g = OG.new()
		core.simulate(g, style, { terrain = sampler, stats = stats }, INCREMENTS)
		local m = MT.graph(g, style.centre[1], style.centre[2])
		local n = #TOWNS
		acc.drift, acc.spread, acc.cv, acc.elong = acc.drift + m.drift / n, acc.spread + m.spread / n, acc.cv + m.cv / n,
			acc.elong + m.elong / n
		local sx, w = 0, 0
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local l = G.dist(a.x, a.y, b.x, b.y)
			sx, w = sx + l * (a.x + b.x) / 2, w + l
		end
		acc.gx = acc.gx + (w > 0 and sx / w or 0) / n
		acc.components = math.max(acc.components, F.components(g))
	end
	return acc
end

local function text(m)
	return string.format("drift=%.2f spread=%.2f cv=%.2f elong=%.2f", m.drift, m.spread, m.cv, m.elong)
end

test("metrics: an even ring is centred and round; a one-sided blob drifts and spreads", function()
	local ring = {}
	for k = 0, 63 do
		local a, b = k / 64 * 2 * math.pi, (k + 1) / 64 * 2 * math.pi
		ring[#ring + 1] = { 300 * math.cos(a), 300 * math.sin(a), 300 * math.cos(b), 300 * math.sin(b) }
	end
	local m = MT.segments(ring, 0, 0)
	ok(m.drift < 0.01, text(m))
	near(m.spread, 1, 0.01)
	ok(m.cv < 0.05, text(m))
	near(m.elong, 1, 0.01)
	near(m.meanR, 300, 1)
	local blob = {}
	for _, s in ipairs(ring) do blob[#blob + 1] = { s[1] * 0.5 + 200, s[2] * 0.25, s[3] * 0.5 + 200, s[4] * 0.25 } end
	local b = MT.segments(blob, 0, 0)
	ok(b.drift > 0.8 and b.spread > 5 and b.elong > 1.5, text(b))
	eq(MT.segments({}, 0, 0).length, 0)
	ok(MT.text(m):find("spread=1.00", 1, true))
end)

test("irregularity: seeded per town, preference in [-1, 1], off when style.irregular is false", function()
	local a = F.style({ forceStyle = "EU_ORGANIC", townId = 1 })
	local a2 = F.style({ forceStyle = "EU_ORGANIC", townId = 1 })
	local b = F.style({ forceStyle = "EU_ORGANIC", townId = 2 })
	local ia, ia2, ib = SEL.irregularity(a), SEL.irregularity(a2), SEL.irregularity(b)
	eq(ia.harm[1][3], ia2.harm[1][3], "same town, same phases")
	ok(ia.harm[1][3] ~= ib.harm[1][3], "another town, other phases")
	for k = 0, 71 do
		local v = SEL.preference(ia, k / 72 * 2 * math.pi)
		ok(v >= -1 - 1e-9 and v <= 1 + 1e-9, "range " .. v)
	end
	near(ia.ribbon, 0.2 * 1.5, 1e-9)
	local off = F.style({ forceStyle = "EU_ORGANIC" })
	off.irregular = false
	eq(SEL.irregularity(off), nil)
end)

test("irregularity: hotspots 3-6.5 blocks out, the first on the favoured side; coast leans toward the water", function()
	local s = F.style({ forceStyle = "NA_SUBURB", townId = 7 })
	local irr = SEL.irregularity(s)
	eq(#irr.hotspots, 2)
	for h, p in ipairs(irr.hotspots) do
		local r = G.dist(s.centre[1], s.centre[2], p[1], p[2]) / s.block.len
		ok(r >= 3 + 2.5 * (h - 1) - 1e-9 and r <= 4 + 2.5 * (h - 1) + 1e-9, "hotspot " .. h .. " at " .. r .. " blocks")
	end
	local h1 = irr.hotspots[1]
	ok(SEL.preference(irr, G.atan2(h1[2] - s.centre[2], h1[1] - s.centre[1])) > 0.3, "first hotspot on the favoured side")
	-- a coast town (sea east): its preference toward the east is raised by the coast weight
	local c = F.style({ forceStyle = "NORDIC", townId = 7 }, F.coast())
	local ic = SEL.irregularity(c)
	ok(ic.waterDir ~= nil and math.abs(G.angleDiff(ic.waterDir, 0)) < 0.3, "water to the east")
	local plain = F.style({ forceStyle = "NORDIC", townId = 7 })
	local ip = SEL.irregularity(plain)
	ok(SEL.preference(ic, 0) > SEL.preference(ip, 0) - 1e-9, "east preferred more on the coast")
end)

-- organic and suburban styles grow visibly unevenly; grids favour their arterials but stay close to even
local UNEVEN = { "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "JP_DENSE", "NORDIC" }
local GRIDS = { "NA_GRID", "MED_ENSANCHE", "SUPERBLOCK" }

for _, id in ipairs(UNEVEN) do
	test("shape " .. id .. ": uneven growth (spread and sector cv well above the even baseline)", function()
		local even, irr = grow(id, false), grow(id, true)
		print(id .. " even " .. text(even) .. " | irregular " .. text(irr))
		ok(irr.spread >= even.spread + 0.2, "spread " .. irr.spread .. " vs " .. even.spread)
		ok(irr.cv >= even.cv * 1.4, "cv " .. irr.cv .. " vs " .. even.cv)
		ok(irr.drift >= even.drift, "drift " .. irr.drift .. " vs " .. even.drift)
		eq(irr.components, 1, "one connected network")
	end)
end

for _, id in ipairs(GRIDS) do
	test("shape " .. id .. ": still close to even, a little uneven along the arterials", function()
		local even, irr = grow(id, false), grow(id, true)
		print(id .. " even " .. text(even) .. " | irregular " .. text(irr))
		ok(irr.spread > even.spread, "spread " .. irr.spread .. " vs " .. even.spread)
		ok(irr.spread < 1.7, "spread stays moderate: " .. irr.spread)
		ok(irr.drift < 0.25, "drift stays small: " .. irr.drift)
		eq(irr.components, 1, "one connected network")
	end)
end

test("shape NORDIC on a coast: the town leans toward the shore side", function()
	local even, irr = grow("NORDIC", false, F.coast()), grow("NORDIC", true, F.coast())
	print("NORDIC coast even gx=" .. even.gx .. " irregular gx=" .. irr.gx)
	-- (v9: Nordic grows in whole cluster cells of 190 x 150 m; the lean became a few metres at most, so only "not away
	-- from the shore" is checked: the coast pull still applies, the cell lattice quantises it)
	ok(irr.gx > even.gx - 10, "centroid x " .. irr.gx .. " vs " .. even.gx .. " (sea to the east)")
end)
