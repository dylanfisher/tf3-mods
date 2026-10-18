-- "Town style" setting (NEXT_PHASE_BRIEF 55): the style region independent of the name list. Saved indices keep their
-- meaning (1 Automatic, 2 North American grid), the chosen region drives the style weights, metro variants, core
-- grids and the vanilla street angle; the names keep following the name list.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local PA = ug_require(F.DIR .. "ot_params.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local SITE = ug_require(F.DIR .. "ot_site.lua")
local MET = ug_require(F.DIR .. "ot_metro.lua")
local AN = ug_require(F.DIR .. "ot_angles.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")

local US = "::/names/usa/usa.names"
local SPAIN = "::/names/spain/spain.names"

-- value index -> { forceGrid, styleRegion }
local EXPECT = {
	{ false, nil }, { true, nil }, { false, "EU" }, { false, "MED" }, { false, "NORDIC" }, { false, "US" },
	{ false, "EAST_ASIA" }, { false, "JP" }, { false, "MIXED" },
}

test("every saved style index parses; 1 / 2 keep their meaning; bad values fall back to Automatic", function()
	eq(#PA.KEYS.style.values, #EXPECT)
	for i, e in ipairs(EXPECT) do
		local o = PA.parse({ style = i })
		eq(o.forceGrid, e[1], "index " .. i)
		eq(o.styleRegion, e[2], "index " .. i)
		ok(o.raw:find("style=" .. i, 1, true))
		if e[2] then ok(I.REGION[e[2]] ~= nil, e[2] .. " is a region") end
	end
	for _, bad in ipairs({ 0, 10, 2.5, "x" }) do
		local o = PA.parse({ style = bad })
		eq(o.forceGrid, false)
		eq(o.styleRegion, nil)
	end
	eq(PA.parse(nil).styleRegion, nil)
end)

test("old index 2 (North American grid): the region still follows the name list, exactly as before", function()
	local o = PA.parse({ style = 2 })
	for _, list in ipairs({ US, SPAIN, "::/names/germany/germany.names", "::/names/unknown/x.names" }) do
		local before = I.build({ nameList = list, climate = "temperate", year = 1960 })
		local now = I.build({ nameList = list, climate = "temperate", year = 1960, styleRegion = o.styleRegion })
		eq(now.region, before.region, list)
		eq(now.regionSource, before.regionSource, list)
		eq(now.country, before.country, list)
	end
	-- the forced grid: pickProfile / resolve return NA_GRID whatever the region
	local inp = I.build({ nameList = SPAIN, climate = "temperate", year = 1960, forceStyle = "NA_GRID" })
	eq(ST.pickProfile(inp), "NA_GRID")
end)

test("the setting sets the region (regionSource=setting), the name list keeps nameRegion; Spain keeps its country", function()
	local inp = I.build({ nameList = US, climate = "temperate", year = 1960, styleRegion = "EU" })
	eq(inp.region, "EU")
	eq(inp.regionSource, "setting")
	eq(inp.nameRegion, "US")
	eq(inp.country, nil, "a US list's country does not ride along into another region")
	inp = I.build({ nameList = SPAIN, climate = "temperate", year = 1960, styleRegion = "MED" })
	eq(inp.country, "spain")
	inp = I.build({ nameList = "::/names/unknown/x.names", climate = "subarctic", year = 1960, styleRegion = "JP" })
	eq(inp.region, "JP")
	eq(inp.nameRegion, nil)
	inp = I.build({ nameList = US, climate = "temperate", year = 1960, styleRegion = "NOPE" })
	eq(inp.region, "US")
	eq(inp.regionSource, "nameList")
	inp = I.build({ climate = "dry", year = 1960 })
	eq(inp.regionSource, "climate")
end)

test("each setting region's style weights match its ot_site table, the climate bias still applies", function()
	for i, e in ipairs(EXPECT) do
		local r = e[2]
		if r then
			for _, climate in ipairs({ "temperate", "tropical" }) do
				local inp = I.build({ nameList = US, climate = climate, year = 2000, styleRegion = r })
				inp.gridBias = nil   -- (ot_grid's era trend aside: the region table alone)
				local got = {}
				for _, w in ipairs(SITE.weights(inp, {})) do got[w.id] = w.w end
				local clim = SITE.CLIMATE[climate] or {}
				for id in pairs(SITE.AFFINITY) do
					local want = (SITE.REGION[r][id] or 0.1) * (clim[id] or 1)
					ok(math.abs((got[id] or 0) - want) < 1e-9,
						string.format("%s %s %s: %s vs %s (index %d)", r, climate, id, tostring(got[id]), want, i))
				end
			end
		end
	end
	-- Mixed: every style alike on a temperate map
	local inp = I.build({ nameList = US, climate = "temperate", year = 2000, styleRegion = "MIXED" })
	inp.gridBias = nil
	for _, w in ipairs(SITE.weights(inp, {})) do eq(w.w, 1, w.id) end
end)

test("the setting region drives metro variants, core grids and the vanilla street angle", function()
	for _, e in ipairs(EXPECT) do
		local r = e[2]
		if r then
			ok(MET.REGION[r] ~= nil, r .. " metro variants")
			ok(MET.CORE_GRID[r] ~= nil, r .. " core grid")
			ok(AN.BY_REGION[r] ~= nil, r .. " angle")
			local ws = MET.variantWeights(r, { kind = "plain" }, 2000)
			for _, w in ipairs(ws) do eq(w.w, MET.REGION[r][w.id] or 0.2, r .. " " .. w.id) end
			local reg, src = AN.region({ nameList = US, climate = "temperate" }, r)
			eq(reg, r)
			eq(src, "setting")
			eq(AN.angleFor("auto", reg), AN.BY_REGION[r])
		end
	end
	-- Automatic / North American grid: the name list's region, as before
	local reg, src = AN.region({ nameList = US }, PA.parse({ style = 2 }).styleRegion)
	eq(reg, "US")
	eq(src, "nameList")
	eq(AN.angleFor("auto", (AN.region({ nameList = US }, "EU"))), 35, "US names, European organic: the EU angle")
end)

test("names don't change with the setting: the driver's name classifier follows the name list", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local function cls(style, list)
		local E = { global = function() return { nameList = list, climate = "temperate" } end,
			modParams = function() return { style = style }, {} end, year = function() return 1960 end,
			nowUs = function() return 0 end, log = function() end }
		local d = D.new(E, "[T]")
		local inp = d:loadConfig()
		return d:nameCls(nil), inp
	end
	for _, list in ipairs({ "square_names_us_texas::/names/texas/texas.names", US, "::/names/germany/germany.names" }) do
		local want = cls(1, list)
		for i = 2, #EXPECT do
			local got, inp = cls(i, list)
			eq(got, want, list .. " style " .. i)
			if EXPECT[i][2] then eq(inp.regionSource, "setting") end
		end
	end
	eq((cls(3, "square_names_us_texas::/names/texas/texas.names")), "usa")
end)
