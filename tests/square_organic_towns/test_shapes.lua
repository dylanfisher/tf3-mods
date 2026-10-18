-- Town shape archetypes (ot_shape, PLAN.md 6.3): selection from terrain / context / style, the steering field,
-- and per shape the grown network's metrics (ot_metrics: elong, spread, arms, side, waist).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")

local TOWNS = { 1, 7, 13, 21 }
local N = 14

--- Mean metrics of a forced shape in a style, grown N increments from a vanilla core (joins at dead ends, as
--- in game). anywhere = true: from an empty town joining any node (grids with 200 m blocks hardly grow from the
--- fake 90 m core; this tests the steering alone).
local function grow(styleId, shape, sampler, n, anywhere)
	sampler = sampler or F.flat
	local acc = { elong = 0, spread = 0, arms = 0, side = 0, waist = 0, edges = 0, drift = 0, drawn = 0 }
	for _, town in ipairs(TOWNS) do
		local style, stats = F.style({ forceStyle = styleId, townId = town, year = 1960, shape = shape }, sampler)
		-- NA vanilla grids share the survey axis with our grid (Probe C: angle 0 = a rectilinear grid); others turned
		local na = styleId == "NA_GRID" or styleId == "NA_SUBURB"
		local g = anywhere and OG.new() or F.vanillaTown(OG.new(), { angle = na and 0 or math.rad(7 * town) })
		for k = 1, n or N do
			local inc = core.planIncrement(g, style, { terrain = sampler, stats = stats, join = anywhere and "any" or "deadEnd" })
			if #inc.edges == 0 then break end
			OG.apply(g, inc, k)
		end
		local m = MT.graph(g, style.centre[1], style.centre[2])
		local w = 1 / #TOWNS
		for _, k in ipairs({ "elong", "spread", "arms", "side", "waist", "drift" }) do acc[k] = acc[k] + m[k] * w end
		acc.edges = acc.edges + #g.edges * w
		acc.drawn = acc.drawn + #(style.shape and style.shape.arms or {}) * w   -- (the arms the shape drew)
	end
	return acc
end

local function text(m)
	return string.format("elong=%.2f spread=%.2f arms=%.1f side=%.2f waist=%.2f drift=%.2f edges=%.0f drawn=%.1f", m.elong,
		m.spread, m.arms, m.side, m.waist, m.drift, m.edges, m.drawn)
end

---------------------------------------------------------------------------
-- selection

local function pickFor(raw, sampler)
	local style = F.style(raw, sampler)
	return style.shape, style
end

test("pick: a valley makes a linear town along it, a crest a ridge town", function()
	local dir = math.rad(30)
	local lin = 0
	for town = 1, 10 do
		local sh = pickFor({ forceStyle = "EU_ORGANIC", townId = town }, F.valley(dir))
		if sh.id == "linear" then
			lin = lin + 1
			ok(G.lineAngleDiff(sh.axis, dir) < math.rad(15), "axis along the valley: " .. math.deg(sh.axis))
			ok(sh.reason:find("valley", 1, true), sh.reason)
		end
	end
	ok(lin >= 6, "linear towns in a valley: " .. lin .. "/10")
	local n = 0
	for town = 1, 10 do
		local sh = pickFor({ forceStyle = "MED_HILL", townId = town }, F.valley(dir, true))
		if sh.id == "ridge" then
			n = n + 1
			ok(G.lineAngleDiff(sh.axis, dir) < math.rad(15), "crest axis: " .. math.deg(sh.axis))
		end
	end
	ok(n >= 7, "ridge towns on a crest: " .. n .. "/10")
end)

test("pick: a coast makes a fan opening inland or a strip along the shore; a river a town along its banks", function()
	local fan, strip = 0, 0
	for town = 1, 12 do
		local sh = pickFor({ forceStyle = "NORDIC", townId = town }, F.coast(300))
		if sh.id == "fan" then
			fan = fan + 1
			ok(G.angleDiff(sh.axis, math.pi) < math.rad(20), "fan opens west (inland): " .. math.deg(sh.axis))
		elseif sh.id == "linear" or sh.id == "shore" then
			-- (shore towns, 2026-10-12: with a traced shoreline the strip follows it, the shore shape)
			strip = strip + 1
			ok(G.lineAngleDiff(sh.axis, math.pi / 2) < math.rad(20), "strip along the north-south shore: " .. math.deg(sh.axis))
		end
	end
	ok(fan + strip >= 10, "coast shapes: fan " .. fan .. ", strip " .. strip)
	ok(strip >= 3, "Nordic coast strips: " .. strip)
	local along = 0
	for town = 1, 12 do
		local sh = pickFor({ forceStyle = "EU_EXTENSION", townId = town }, F.river(-120))
		if sh.id == "linear" and G.lineAngleDiff(sh.axis, 0) < math.rad(20) then along = along + 1 end
	end
	ok(along >= 5, "river towns along the banks: " .. along .. "/12")
end)

test("pick: roads between towns and neighbours steer the shape; town streets don't count as exits", function()
	local country = "::/infrastructure/street/standard/country_new_medium.street_template"
	local function road(a, r0, r1, tpl)
		return { p0 = { math.cos(a) * r0, math.sin(a) * r0 }, p1 = { math.cos(a) * r1, math.sin(a) * r1 }, template = tpl }
	end
	local ex = SH.exits({ road(0, 200, 400, country), road(math.pi, 200, 400, country), road(1, 200, 400, "town_new_small") }, 0, 0, 300)
	eq(#ex, 2, "two country roads, the town street left out")
	local lin = 0
	for town = 1, 20 do
		local sh = pickFor({ forceStyle = "EU_EXTENSION", townId = town, exits = ex })
		if sh.id == "linear" and G.lineAngleDiff(sh.axis, 0) < 0.05 then lin = lin + 1 end
	end
	ok(lin >= 8, "street villages along two opposite roads: " .. lin .. "/20")
	local ex4 = SH.exits({ road(0, 200, 400, country), road(1.6, 200, 400, country), road(3.1, 200, 400, country),
		road(4.7, 200, 400, country) }, 0, 0, 300)
	local cross = 0
	for town = 1, 20 do
		local sh = pickFor({ forceStyle = "EU_EXTENSION", townId = town, exits = ex4 })
		if sh.id == "cross" then
			cross = cross + 1
			eq(#sh.arms, 4, "arms along the four roads")
		end
	end
	ok(cross >= 8, "crossroads towns: " .. cross .. "/20")
	local twin = 0
	for town = 1, 20 do
		local sh = pickFor({ forceStyle = "EU_ORGANIC", townId = town, neighbours = { { dir = 2, dist = 1200 } } })
		if sh.id == "twin" then
			twin = twin + 1
			ok(G.angleDiff(sh.axis, 2) < 1e-6, "toward the neighbour")
			near(sh.D, 540, 1e-6, "second core at 0.45 x the distance")
		end
	end
	ok(twin >= 8, "twin towns growing toward a neighbour 1.2 km away: " .. twin .. "/20")
end)

test("pick on flat land: seeded per town from the style's weights; forced and saved shapes win", function()
	local count = {}
	for town = 1, 60 do
		local sh = pickFor({ forceStyle = "EU_ORGANIC", townId = town })
		count[sh.id] = (count[sh.id] or 0) + 1
		eq(sh.reason, "style")
	end
	local kinds = 0
	for _ in pairs(count) do kinds = kinds + 1 end
	ok(kinds >= 4, "EU organic towns differ: " .. kinds .. " shapes")
	ok((count.compact or 0) >= (count.cross or 0), "EU organic mostly compact")
	eq(count.fan, nil, "no fans without a coast")
	local na = {}
	for town = 1, 60 do
		local sh = pickFor({ townId = town })
		na[sh.id] = (na[sh.id] or 0) + 1
	end
	-- (v9: NA grid towns mostly compact / lens blocks, as the metropolis grid; cross / linear now and then)
	ok((na.compact or 0) + (na.lens or 0) > (na.cross or 0) + (na.linear or 0), "NA grid towns: compact / lens first")
	ok((na.cross or 0) + (na.linear or 0) > 0, "some cross / linear NA grid towns")
	local a = pickFor({ forceStyle = "EU_ORGANIC", townId = 3 })
	local b = pickFor({ forceStyle = "EU_ORGANIC", townId = 3 })
	eq(a.id, b.id, "deterministic")
	eq(pickFor({ forceStyle = "EU_ORGANIC", townId = 3, shape = "fingers" }).id, "fingers")
	local saved = pickFor({ forceStyle = "EU_ORGANIC", townId = 3, frame = { axis = 0.5, origin = { 0, 0 }, shape = "ridge",
		shapeAxis = 1.25 } })
	eq(saved.id, "ridge")
	eq(saved.axis, 1.25)
	ok(saved.reason:find("saved", 1, true), saved.reason)
end)

test("saved frame keeps the shape (index + axis) and older frames without it still load", function()
	local SV = ug_require(F.DIR .. "ot_saved.lua")
	local style = F.style({ forceStyle = "EU_ORGANIC", townId = 5, shape = "lens" })
	local fp = SV.frameParam(77, style, nil)
	eq(fp.s, SH.INDEX.lens)
	local st = SV.applyFrame(SV.normalize(nil), fp)
	local fr = SV.frame(st, 77)
	eq(fr.shape, "lens")
	near(fr.shapeAxis, style.shape.axis, 1e-5)
	local old = SV.normalize({ v = SV.VERSION, frames = { ["9"] = { a = 0.1, x = 1, y = 2 } } })
	local f9 = SV.frame(old, 9)
	eq(f9.shape, nil)
	near(f9.axis, 0.1, 1e-9)
end)

test("distance field: compact is plain distance; arms are cheap along, dear across; the fan's back is dear", function()
	local base = { centre = { 0, 0 }, block = 100, axis = 0 }
	local function shape(id, extra)
		local s = {}
		for k, v in pairs(base) do s[k] = v end
		s.id = id
		for k, v in pairs(extra or {}) do s[k] = v end
		return s
	end
	near(SH.distance(shape("compact"), 300, 400), 500, 1e-9)
	local lin = shape("linear", { arms = { 0, math.pi } })
	ok(SH.distance(lin, 400, 0) < SH.distance(lin, 0, 400) * 0.5, "linear: along much cheaper than across")
	local fan = shape("fan")
	ok(SH.distance(fan, -200, 0) > 2.5 * SH.distance(fan, 200, 0), "fan: behind the opening is dear")
	local lens = shape("lens", { green = { 90, 45 } })
	ok(SH.distance(lens, 20, 0) > SH.distance(lens, 200, 0), "lens: the green is avoided")
	local twin = shape("twin", { second = { 600, 0 }, D = 600 })
	ok(SH.distance(twin, 600, 0) < SH.distance(twin, -600, 0) * 0.5, "twin: the second core is cheap")
end)

---------------------------------------------------------------------------
-- grown shapes (flat land, from a vanilla core, dead-end joins)

local function metricsFor(styleId, n, anywhere)
	local out = {}
	for _, id in ipairs(SH.IDS) do
		out[id] = grow(styleId, id, nil, n, anywhere)
		print(string.format("%-12s %-8s %s", styleId, id, text(out[id])))
	end
	return out
end

for _, styleId in ipairs({ "EU_EXTENSION", "EU_ORGANIC" }) do
	test("shapes in " .. styleId .. ": each archetype's metrics", function()
		local m = metricsFor(styleId, N)
		local c = m.compact
		ok(c.elong <= 1.7, "compact stays round: " .. text(c))
		-- (2026-10-12, stronger steering: linear / ridge were +1.2 / +1.0 over compact before)
		ok(m.linear.elong >= c.elong + 1.8, "linear is long: " .. text(m.linear))
		ok(m.ridge.elong >= c.elong + 1.5, "ridge is long (flat land: no crest): " .. text(m.ridge))
		-- (6 spokes: a cross is a Y of 3 arms on every other spoke, fingers one arm per spoke)
		-- (deep arms 2026-10-12: the X's arms 60 deg apart are strips now, and in EU organic, whose spokes bend, two
		-- neighbouring strips often merge into one peak of the sector radii; 2.8 -> 2.2 there, EU extension 4.0)
		local crossMin = styleId == "EU_ORGANIC" and 2.0 or 2.5
		ok(m.cross.arms >= crossMin and m.cross.arms >= c.arms + 0.3, "cross has 3 arms: " .. text(m.cross))
		ok(m.fingers.arms >= 3 and m.fingers.arms >= c.arms + 0.8, "fingers: " .. text(m.fingers))
		ok(m.fan.side >= 0.78 and m.fan.side >= c.side + 0.15, "fan is one-sided: " .. text(m.fan))
		ok(m.twin.drift >= c.drift + 0.2 and m.twin.side >= 0.62, "twin leans toward its second core: " .. text(m.twin))
		ok(m.lens.elong >= 1.5 and m.lens.elong <= 2.1 and m.lens.arms <= 2, "lens is an oval: " .. text(m.lens))
		for id, x in pairs(m) do ok(x.edges >= 300, id .. " grows: " .. x.edges) end
	end)
end

test("shapes in NA_GRID (steering alone: empty town, joins anywhere): each archetype's metrics", function()
	local m = metricsFor("NA_GRID", 14, true)
	local c = m.compact
	ok(c.elong <= 1.5, "compact: " .. text(c))
	ok(m.linear.elong >= c.elong + 1.5, text(m.linear))
	ok(m.ridge.elong >= c.elong + 1, text(m.ridge))
	ok(m.cross.arms >= 3.5, text(m.cross))
	-- (§68: the finger count, 4-6 seeded per town, draws with rng.decide now: these towns draw 4.8 on average (4.2
	-- before), and on a 14-increment grid five or six fingers 60-72 deg apart merge into fewer peaks of the arm metric:
	-- 3.2 measured (3.8 before). The bar is the drawn shape's: at least 4 drawn, at least 3 grown, 1.5 over compact)
	ok(m.fingers.drawn >= 4 and m.fingers.arms >= 3 and m.fingers.arms >= c.arms + 1.5, text(m.fingers))
	ok(m.fan.side >= 0.68, text(m.fan))
	ok(m.twin.drift >= c.drift + 0.3 and m.twin.waist <= 0.8, text(m.twin))
	-- (2026-10-12, late hierarchy lattice with collector lines: 2.65)
	ok(m.lens.elong >= 1.6 and m.lens.elong <= 2.75, text(m.lens))
end)

---------------------------------------------------------------------------
-- saw-tooth outskirts (ot_select corner penalty) and the growth front

test("saw-tooth: the corner rule leaves fewer frontier teeth (corners + dead ends per km) at equal growth", function()
	local SEL = ug_require(F.DIR .. "ot_select.lua")
	for _, styleId in ipairs({ "EU_EXTENSION", "EU_ORGANIC" }) do
		local function teeth(on)
			SEL.SMOOTH = on
			local t, e = 0, 0
			local okRun, err = pcall(function()
				for _, town in ipairs(TOWNS) do
					local style, stats = F.style({ forceStyle = styleId, townId = town, year = 1960, shape = "compact" }, F.flat)
					local g = F.vanillaTown(OG.new(), { angle = math.rad(7 * town) })
					for k = 1, 10 do
						local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd" })
						if #inc.edges == 0 then break end
						OG.apply(g, inc, k)
					end
					t = t + MT.teeth(g, function(x) return not x.existing end) / #TOWNS
					e = e + #g.edges / #TOWNS
				end
			end)
			SEL.SMOOTH = true
			assert(okRun, err)
			return t, e
		end
		local off, eOff = teeth(false)
		local on, eOn = teeth(true)
		print(string.format("%s teeth/km off=%.2f on=%.2f edges off=%.0f on=%.0f", styleId, off, on, eOff, eOn))
		ok(on <= off * 0.85, styleId .. " fewer teeth: " .. on .. " vs " .. off)
		ok(eOn >= eOff * 0.9, styleId .. " growth kept")
	end
end)

test("growth front: no new piece beyond the town's front + reach (no endless spurs into the field)", function()
	local SEL = ug_require(F.DIR .. "ot_select.lua")
	for _, case in ipairs({ { "NA_GRID", "linear" }, { "EU_EXTENSION", "fingers" }, { "EU_ORGANIC", "compact" } }) do
		local style, stats = F.style({ forceStyle = case[1], townId = 7, year = 1960, shape = case[2] }, F.flat)
		local g = F.vanillaTown(OG.new(), { angle = 0 })
		local shaped = case[2] ~= "compact"
		for k = 1, 12 do
			local inc, rep = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd" })
			if #inc.edges == 0 then break end
			ok(rep.frontCap ~= nil, "front known")
			for _, e in ipairs(inc.edges) do
				local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
				local d = shaped and SH.distance(style.shape, mx, my, F.flat) or G.dist(style.centre[1], style.centre[2], mx, my)
				-- an edge is part of a piece whose midpoint passed; allow half a piece of slack
				ok(d <= rep.frontCap + 0.75 * math.max(style.block.len, style.block.depth),
					string.format("%s %s edge at %.0f beyond front %.0f", case[1], case[2], d, rep.frontCap))
			end
			OG.apply(g, inc, k)
		end
	end
end)
