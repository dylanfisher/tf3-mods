-- otd_layout (showcase placement, pure): items and priorities, island scan, grid spacing, drops on a small
-- island, wet spots, the coastal style moved to the shore.

local L = ug_require "/organic_towns_dev/otd_layout.lua"
local S = ug_require "/organic_towns_dev/otd_shared.lua"

local STYLES = {}
for _, st in ipairs(S.STYLES) do
	if st.id ~= "main" and st.id ~= "region" then STYLES[#STYLES + 1] = { id = st.id, label = st.label, angle = 0 } end
end

--- Square island |x|, |y| < half (sea beyond), on a box of +-4096.
local function island(half)
	return function(x, y) return math.abs(x) > half or math.abs(y) > half end
end
local BOX = { minX = -4096, maxX = 4096, minY = -4096, maxY = 4096 }

local function keys(list, f)
	local out = {}
	for _, p in ipairs(list) do out[#out + 1] = f(p) end
	return out
end

test("items: 9 styles, era row, a control (v8: no Control B), roundabout towns (probe + main mod), Probe C 0/15/45/90 (opt-in); priorities keep styles longest", function()
	local items = L.items(STYLES, { era = true, shapes = false, density = false, metros = false, forms = false, probeC = true })
	eq(#items, 9 + 2 + 1 + 4)
	eq(#L.items(STYLES, { era = true, roundabout = true, shapes = false, density = false, metros = false, forms = false, probeC = true }), 18)
	eq(#L.items(STYLES, { era = true, roundabout = true, shapes = false, density = false, metros = false, forms = false }), 14, "Probe C off by default (v5)")
	eq(L.PROBE_C, false)
	local by = {}
	for _, it in ipairs(L.items(STYLES, { era = true, roundabout = true, shapes = false, density = false, metros = false, forms = false, probeC = true })) do by[it.key] = it end
	eq(by.ERA_NA_1900.newTemplates, false, "a 1940+ game compares against 1900: old templates")
	eq(by.ERA_NA_1900.year, 1900)
	eq(by.ERA_EU_1900.style, "EU_EXTENSION")
	eq(by.RB_EU.roundabout, true)
	eq(by.RB_TOWN.charKind, "roundabout_town", "the main mod's roundabout town (2026-10-14)")
	ok(by.RB_TOWN.prio < by.RB_EU.prio and by.RB_TOWN.prio > by.ERA_NA_1900.prio)
	eq(by.PROBE_C_45.angle, 45)
	eq(by.PROBE_C_45.kind, "vanilla")
	eq(by.CONTROL_A.angle, nil, "controls keep createTowns' default angle")
	ok(by.NORDIC.coast, "NORDIC follows a shore")
	local minStyle = math.huge
	for _, it in ipairs(items) do if it.kind == "style" and not it.year and not it.roundabout then minStyle = math.min(minStyle, it.prio) end end
	ok(minStyle > by.RB_EU.prio and by.RB_EU.prio > by.ERA_NA_1900.prio and by.ERA_EU_1900.prio > by.CONTROL_A.prio
		and by.CONTROL_A.prio > by.PROBE_C_0.prio)
	eq(by.CONTROL_B, nil, "v8: one vanilla control")
	eq(#L.items(STYLES, { era = false, shapes = false, density = false, metros = false, forms = false, probeC = true }), 14, "before 1940 no era row (only old templates)")
end)

test("island: scans from the box centre to the first water along both axes", function()
	local land = L.island(BOX, island(3000))
	ok(land.maxX >= 2950 and land.maxX <= 3000, tostring(land.maxX))
	ok(land.minY <= -2950 and land.minY >= -3000, tostring(land.minY))
	eq(L.island(BOX, function() return true end), nil, "centre in the sea")
end)

test("layout: 18 towns on an 8 km island, >= MIN_SPACING apart, all dry; NORDIC at the coast", function()
	local water = island(4000)
	local land = L.island(BOX, water)
	local res = L.layout(L.items(STYLES, { era = true, roundabout = true, shapes = false, density = false, metros = false, forms = false, probeC = true }), land,
		water)
	eq(#res.placed, 18)
	eq(#res.dropped, 0)
	ok(res.spacing >= L.MIN_SPACING and res.spacing <= L.TARGET_SPACING, tostring(res.spacing))
	for i, a in ipairs(res.placed) do
		-- the coastal town sits COAST_D from the shore on purpose: dry within 250 m
		ok(L.dry(a.x, a.y, water, a.coast and { 0, 250 } or nil), a.item.key .. " dry")
		for j = i + 1, #res.placed do
			local b = res.placed[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
			ok(d >= L.MIN_SPACING - 1e-6, a.item.key .. "-" .. b.item.key .. " " .. d)
		end
	end
	local nordic
	for _, p in ipairs(res.placed) do if p.item.key == "NORDIC" then nordic = p end end
	eq(nordic.coast, L.COAST_D)
	local shore = math.min(4000 - math.abs(nordic.x), 4000 - math.abs(nordic.y))
	ok(shore >= L.COAST_D - L.STEP and shore <= L.COAST_D + L.STEP, "shore " .. shore)
	ok(nordic.row == 1 or nordic.col == 1 or nordic.row == res.rows or nordic.col == res.cols, "on the outer ring")
end)

test("layout: a small island drops Probe C first, then the controls; styles stay", function()
	local water = island(2400)
	local land = L.island(BOX, water)
	local res = L.layout(L.items(STYLES, { era = true, roundabout = true, shapes = false, density = false, metros = false, forms = false, probeC = true }),
		land, water)
	local dropped = keys(res.dropped, function(d) return d.item.key end)
	ok(#dropped > 0, "something dropped")
	for _, k in ipairs(dropped) do
		ok(k:find("PROBE_C", 1, true) or k:find("CONTROL", 1, true) or k:find("ERA_", 1, true) or k == "RB_EU" or k == "RB_TOWN", k)
	end
	local placed = {}
	for _, p in ipairs(res.placed) do placed[p.item.key] = true end
	for _, st in ipairs(STYLES) do ok(placed[st.id], st.id .. " kept") end
	ok(res.spacing >= L.MIN_SPACING, tostring(res.spacing))
	-- an island too small for even the grid box
	local tiny = L.layout(L.items(STYLES, { shapes = false, density = false, metros = false, forms = false }), L.island(BOX, island(600)), island(600))
	eq(#tiny.placed, 0)
	eq(tiny.dropped[1].why, "islandTooSmall")
end)

test("layout: an offset moves the whole grid (second run after a reset that left streets)", function()
	local water = island(4000)
	local land = L.island(BOX, water)
	local a = L.layout(L.items(STYLES, { era = false, shapes = false, density = false, metros = false, forms = false }), land, water)
	local b = L.layout(L.items(STYLES, { era = false, shapes = false, density = false, metros = false, forms = false }), land, water, { offset = { 300, -200 } })
	near(b.placed[2].x - a.placed[2].x, 300, 1e-6)
	near(b.placed[2].y - a.placed[2].y, -200, 1e-6)
end)

test("layout: a wet grid spot moves to a spare cell (or is dropped)", function()
	local base = island(3000)
	-- a lake at the first cell (top-left)
	local land = L.island(BOX, base)
	local probe = L.layout(L.items(STYLES, { era = false, shapes = false, density = false, metros = false, forms = false }), land, base)
	local first = probe.placed[1]
	local function water(x, y)
		return base(x, y) or ((x - first.x) ^ 2 + (y - first.y) ^ 2 < 300 ^ 2)
	end
	local res = L.layout(L.items(STYLES, { era = false, shapes = false, density = false, metros = false, forms = false }), land, water)
	local p1 = res.placed[1]
	ok(p1.x ~= first.x or p1.y ~= first.y, "moved")
	ok(p1.moved)
	ok(L.dry(p1.x, p1.y, water))
end)

test("items v3: shape row (8 archetypes, one style) and density row (v8: the control only); drop order Probe C, density, shapes", function()
	local items = L.items(STYLES, { era = true, roundabout = true, probes = false, probeC = true, metros = false, forms = false })
	eq(#items, 18 + 8 + 1)
	local by, shapes, levers = {}, {}, {}
	for _, it in ipairs(items) do
		by[it.key] = it
		if it.shape then shapes[#shapes + 1] = it.shape end
		if it.lever then levers[#levers + 1] = it.lever end
	end
	eq(shapes, L.SHAPES)
	eq(levers, { "control" })
	eq(by.SHAPE_LINEAR.style, L.SHAPE_STYLE)
	eq(by.SHAPE_LINEAR.label, "Shape: linear")
	eq(by.SHAPE_LINEAR.kind, "style")
	eq(by.DENS_CONTROL.style, L.DENSITY_STYLE)
	local minShape, maxShape, minDens, maxDens = math.huge, 0, math.huge, 0
	for _, it in ipairs(items) do
		if it.shape then minShape, maxShape = math.min(minShape, it.prio), math.max(maxShape, it.prio) end
		if it.lever then minDens, maxDens = math.min(minDens, it.prio), math.max(maxDens, it.prio) end
	end
	ok(by.CONTROL_A.prio > maxShape and minShape > maxDens and minDens > by.PROBE_C_0.prio)
end)

test("layout v3: 27 towns fit an 18 km island (more rows, 6 columns); a 7 km island drops Probe C, then density", function()
	local BIG = { minX = -9500, maxX = 9500, minY = -9500, maxY = 9500 }
	local water = island(9000)
	local res = L.layout(L.items(STYLES, { era = true, roundabout = true, probes = false, probeC = true, metros = false, forms = false }), L.island(BIG, water),
		water)
	eq(#res.placed, 27)
	eq(res.cols, L.MAX_COLS)
	eq(res.rows, 5)
	ok(res.spacing >= L.MIN_SPACING, tostring(res.spacing))
	local w2 = island(3500)
	local res2 = L.layout(L.items(STYLES, { era = true, roundabout = true, probes = false, probeC = true, metros = false, forms = false }), L.island(BIG, w2), w2)
	ok(#res2.dropped > 0)
	local droppedShape, droppedDensity, droppedProbe = false, false, 0
	for _, d in ipairs(res2.dropped) do
		if d.item.shape then droppedShape = true end
		if d.item.lever then droppedDensity = true end
		if d.item.key:find("PROBE_C", 1, true) then droppedProbe = droppedProbe + 1 end
	end
	eq(droppedProbe, math.min(4, #res2.dropped), "Probe C goes first")
	ok(not droppedShape or droppedDensity, "density before shapes")
	local placed = {}
	for _, p in ipairs(res2.placed) do placed[p.item.key] = true end
	for _, st in ipairs(STYLES) do ok(placed[st.id], st.id .. " kept") end
end)

test("items v8: lock control twin, form row (JP dense in 4 forms), metropolis row; 35 towns fit Blank Slate, metropolis band", function()
	local items = L.items(STYLES, { era = true, roundabout = true })
	-- (§65: + 2 old-lock twins in the probe row)
	eq(#items, 14 + 8 + 1 + 3 + 4 + 5)
	local by, probes, metros, forms = {}, {}, {}, {}
	for _, it in ipairs(items) do
		by[it.key] = it
		if it.probe then probes[#probes + 1] = it.key end
		if it.metro then metros[#metros + 1] = it.key end
		if it.form and not it.metro then forms[#forms + 1] = it.form end
	end
	eq(probes, { "SHAPE_LINEAR_PLAIN", "EU_ORGANIC_LOCKALL", "SHAPE_LINEAR_OLDLOCK" })
	-- (§65 lock A/B: the old default lock beside the main mod's "mod" lock, each twin of its row town)
	eq(by.EU_ORGANIC_LOCKALL.style, "EU_ORGANIC"); eq(by.EU_ORGANIC_LOCKALL.twinOf, "EU_ORGANIC")
	eq(by.EU_ORGANIC_LOCKALL.lock, "mod"); eq(by.EU_ORGANIC_LOCKALL.shape, nil)
	eq(by.SHAPE_LINEAR_OLDLOCK.style, L.SHAPE_STYLE); eq(by.SHAPE_LINEAR_OLDLOCK.shape, "linear")
	eq(by.SHAPE_LINEAR_OLDLOCK.lock, "shape")
	eq(metros, { "METRO_GRID", "METRO_RADIAL", "METRO_CORRIDOR", "METRO_OLDCORE", "METRO_POLYCENTRIC" })
	eq(forms, L.FORMS)
	eq(by.FORM_SPRAWLING.style, L.FORM_STYLE)
	eq(by.FORM_SPRAWLING.label, "Form: sprawling")
	eq(by.SHAPE_LINEAR_PLAIN.lock, "off")
	eq(by.SHAPE_LINEAR_PLAIN.fillKind, "off")
	eq(by.SHAPE_LINEAR_LOCKFILL, nil, "v8: the locked+fill twins are gone")
	eq(by.DENS_WEIGHTS, nil, "v8: only the density control")
	eq(by.METRO_POLYCENTRIC.metroCentres, true)
	eq(by.METRO_GRID.style, "NA_GRID")
	eq(by.METRO_OLDCORE.style, "EU_ORGANIC")
	eq(by.METRO_RADIAL.form, "radiating", "the radial metropolis grows fingers along its spokes")
	eq(by.PROBE_C_0, nil, "Probe C off")
	ok(S.isShapeTown(by.SHAPE_LINEAR_PLAIN), "probe twins are seen top-down like the shape row")
	ok(S.isShapeTown(by.METRO_RADIAL), "the metropolis row too")
	ok(S.isShapeTown(by.FORM_LINEAR), "and the form row")
	eq(#L.items(STYLES, { era = true, roundabout = true, shapes = false, forms = false }), 14 + 1, "no shape row: no probe twins, no metropolis row")
	-- Blank Slate (v4 log): land +-8150, box +-7250: the grid above a 5 km metropolis band
	local water = island(8150)
	local res = L.layout(items, L.island({ minX = -8192, maxX = 8192, minY = -8192, maxY = 8192 }, water), water)
	eq(#res.placed, 35)
	eq(#res.dropped, 0)
	eq(res.band, L.METRO_BAND)
	local ms, others = {}, {}
	for _, p in ipairs(res.placed) do
		if p.item.metro then ms[#ms + 1] = p else others[#others + 1] = p end
	end
	eq(#ms, 5)
	local bandTop = -7250 + L.METRO_BAND
	for _, p in ipairs(others) do ok(p.y >= bandTop - 1e-6, p.item.key .. " above the band: " .. p.y) end
	for _, p in ipairs(ms) do ok(p.y < bandTop, p.item.key .. " in the band") end
	-- metropolis towns at least ~3.5 km apart (v7: 2.5 km, they grew into one another) and >= 2 km from the grid towns
	for i, a in ipairs(ms) do
		for j = i + 1, #ms do
			local b = ms[j]
			ok(math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) >= 3500, a.item.key .. "-" .. b.item.key)
		end
		for _, b in ipairs(others) do ok(math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) >= 2000, a.item.key .. "-" .. b.item.key) end
	end
	ok(res.spacing >= 2300, "grid spacing " .. res.spacing)
	-- an island without room for the band: the metropolis towns join the grid
	local w2 = island(4000)
	local small = L.layout(items, L.island(BOX, w2), w2)
	eq(small.band, nil)
end)
