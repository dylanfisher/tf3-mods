-- Organic <-> gridded balance (ot_grid, 2026-10-13, real map round 3). User: "Is our code set up so that in later years
-- cities are more likely to become more gridded? Perhaps a mod setting ... Default should tend toward organic,
-- especially early game ... none have any grid." The era trend and the Town layout setting scale the gridded styles'
-- weights (ot_site) and the organic growers' grid look (ot_style); the outer zone turns more regular with the years.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local GR = ug_require(F.DIR .. "ot_grid.lua")
-- every test here with the grid bias on (fixtures turn it off for the other files)
local function test_(name, fn) test(name, function() F.withGrid(fn) end) end
local SITE = ug_require(F.DIR .. "ot_site.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local P = ug_require(F.DIR .. "ot_params.lua")

-- the 16 towns of the real map run 2026-10-13_0137_sqot-dev (STYLE styleWhy features: open, rough, coast, river)
local SITES = {
	{ 0, 0.65, 0, 1 }, { 0.04, 0, 0.91, 0 }, { 0.52, 0.04, 0, 0 }, { 0.05, 0.27, 0.62, 0 }, { 0.46, 0.12, 0, 0 },
	{ 0.40, 0.07, 0.41, 0 }, { 0.07, 0.33, 0, 0 }, { 0, 0.36, 0.41, 0 }, { 0.21, 0.18, 0, 0 }, { 0, 0.48, 0, 0 },
	{ 0.03, 0.37, 0, 0 }, { 0.24, 0.15, 0.66, 0 }, { 0, 0.5, 0.28, 0 }, { 0, 0.48, 0.53, 0 }, { 0, 0.5, 0.87, 0 },
	{ 0.23, 0.17, 0.41, 0 },
}
local GRIDISH = { EU_EXTENSION = true, MED_ENSANCHE = true, NA_GRID = true, NA_SUBURB = true, SUPERBLOCK = true }
local TRUE_GRID = { MED_ENSANCHE = true, NA_GRID = true, NA_SUBURB = true, SUPERBLOCK = true }

--- expected shares over the 16 sites (mean of each site's normalised weights): grid-ish, true grids, by style
local function shares(region, year, layout)
	local inputs = I.build({ nameList = region == "US" and "::/names/usa/usa.names" or "::/names/europe/europe.names",
		year = year, layout = layout })
	local g, tg, by = 0, 0, {}
	for _, s in ipairs(SITES) do
		local ws = SITE.weights(inputs, { open = s[1], rough = s[2], coast = s[3], river = s[4], valley = 0 })
		local total = 0
		for _, x in ipairs(ws) do total = total + x.w end
		for _, x in ipairs(ws) do
			local w = x.w / total / #SITES
			by[x.id] = (by[x.id] or 0) + w
			if GRIDISH[x.id] then g = g + w end
			if TRUE_GRID[x.id] then tg = tg + w end
		end
	end
	return g, tg, by
end

test_("era trend (era range 1900+): 0 to 1910, 1 at 1970, rising on to 2000; setting factors monotone", function()
	eq(GR.era(1900), 0, "TF3's earliest start: no grid trend")
	eq(GR.era(1910), 0)
	ok(GR.era(1930) > 0.2 and GR.era(1930) < 0.5, "1930 " .. GR.era(1930))
	near(GR.era(1970), 1, 1e-9)
	ok(GR.era(2000) > 1 and GR.era(2050) <= GR.ERA_MAX + 1e-9, "late years above 1")
	local last = -1
	for k = 1, 5 do
		local b = GR.bias(1930, k)
		ok(b.gridded > last, "gridded factor rises with the setting: " .. GR.text(b))
		last = b.gridded
	end
	ok(GR.bias(1910, 2).look < GR.bias(1930, 2).look and GR.bias(1930, 2).look < GR.bias(1980, 2).look, "look rises with the years")
	eq(P.parse({}).townLayout, 2, "default Organic")
	eq(P.parse({ town_layout = 5 }).townLayout, 5)
end)

test_("EU map: grid-ish share by era (default setting, era range 1900+): organic early, a visible minority 1930-1960, more later", function()
	local rows = {}
	for _, y in ipairs({ 1900, 1920, 1940, 1960, 1990 }) do
		local g, tg, by = shares("EU", y, nil)
		rows[y] = { g = g, tg = tg }
		print(string.format("EU %d: grid-ish %.2f (true grids %.2f) EU_ORGANIC %.2f EU_EXTENSION %.2f ensanche %.2f NA_GRID %.2f suburb %.2f superblock %.2f MED_HILL %.2f",
			y, g, tg, by.EU_ORGANIC or 0, by.EU_EXTENSION or 0, by.MED_ENSANCHE or 0, by.NA_GRID or 0, by.NA_SUBURB or 0,
			by.SUPERBLOCK or 0, by.MED_HILL or 0))
	end
	ok(rows[1900].g <= 0.2, "1900 clearly organic: " .. rows[1900].g)
	ok(rows[1920].g <= 0.25, "1920 still organic: " .. rows[1920].g)
	ok(rows[1940].g >= 0.15 and rows[1960].g <= 0.5, "1940-1960 a visible minority")
	ok(rows[1940].g <= 0.4, "1940: under 40 %: " .. rows[1940].g)
	ok(rows[1990].g > rows[1940].g + 0.1, "more later: " .. rows[1990].g)
	ok(rows[1940].tg >= 0.04, "some true grid towns by 1940: " .. rows[1940].tg)
end)

test_("Town layout setting: the 5 steps shift the mix monotonically (EU 1930 and 1980, US 1930)", function()
	for _, c in ipairs({ { "EU", 1930 }, { "EU", 1980 }, { "US", 1930 } }) do
		local last, line = -1, {}
		for k = 1, 5 do
			local g = shares(c[1], c[2], k)
			ok(g > last, string.format("%s %d step %d: %.2f > %.2f", c[1], c[2], k, g, last))
			last = g
			line[#line + 1] = string.format("%.2f", g)
		end
		print(string.format("%s %d grid-ish by setting (very organic .. very gridded): %s", c[1], c[2], table.concat(line, " / ")))
	end
	local vo = shares("EU", 1930, 1)
	local vg = shares("EU", 1930, 5)
	ok(vo <= 0.2 and vg >= 0.5, string.format("extremes differ clearly: %.2f vs %.2f", vo, vg))
end)

test_("grid look: organic growers straighter with the years; outer zone more regular and closer; saved style kept", function()
	local function style(year, layout, frame)
		return ST.resolve(I.build({ townId = 7, pos = { 0, 0 }, capacity = 1500, year = year, layout = layout,
			nameList = "::/names/europe/europe.names", forceStyle = (not frame) and "EU_ORGANIC" or nil, keepOuter = true,
			frame = frame }))
	end
	local a, b, c = style(1920, 2), style(1945, 2), style(2000, 2)
	eq(style(1900, 2).outer, nil, "1900: no extension ring yet (ot_style EXT_OUTER_YEAR)")
	ok(a.jitter > b.jitter and b.jitter > c.jitter, string.format("jitter %.1f > %.1f > %.1f", a.jitter, b.jitter, c.jitter))
	ok(c.gridness > a.gridness, "gridness rises")
	local oa, oc = ST.zone(a, 1e6), ST.zone(c, 1e6)
	ok(oc.gridness > oa.gridness and oc.jitter < oa.jitter, string.format("outer zone straighter later: gridness %.2f -> %.2f, jitter %.1f -> %.1f",
		oa.gridness, oc.gridness, oa.jitter, oc.jitter))
	ok(c.outer.from < a.outer.from, string.format("outer zone closer later: %.0f -> %.0f m", a.outer.from, c.outer.from))
	ok(style(1930, 5).jitter < style(1930, 1).jitter, "very gridded straighter than very organic")
	-- a saved style keeps its id whatever the setting
	local saved = style(1990, 5, { axis = 0.3, origin = { 0, 0 }, style = "MED_HILL" })
	eq(saved.id, "MED_HILL")
	eq(saved.styleSource, "saved")
end)

test_("the grid look is saved with the frame: a framed town keeps the look its plan was made with (real map run 2026-10-13_0232_sqot-dev: it dropped after the head start)", function()
	local SV = ug_require(F.DIR .. "ot_saved.lua")
	local raw = { townId = 7, pos = { 0, 0 }, capacity = 1500, year = 1930, nameList = "::/names/europe/europe.names",
		forceStyle = "EU_ORGANIC" }
	local fresh = ST.resolve(I.build(raw))
	ok(fresh.gridLook and fresh.gridLook > 0, "fresh town: look " .. tostring(fresh.gridLook))
	local fp = SV.frameParam(7, fresh, nil, 1000)
	near(fp.gl, fresh.gridLook, 1e-3, "saved")
	local st = SV.applyFrame(nil, fp)
	local frame = SV.frame(st, 7)
	near(frame.gridLook, fresh.gridLook, 1e-3)
	local r2 = {}
	for k, v in pairs(raw) do r2[k] = v end
	r2.frame = frame
	local framed = ST.resolve(I.build(r2))
	near(framed.gridLook or 0, fresh.gridLook, 1e-3, "framed: the same look")
	near(framed.jitter or 0, fresh.jitter or 0, 1e-9, "same jitter")
	-- an old frame without gl: no look (as before)
	frame.gridLook = nil
	local old = ST.resolve(I.build(r2))
	ok(old.gridLook == nil, "old frame: none")
end)
