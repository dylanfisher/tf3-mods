-- ot_angles (the game's own town street angle ranges by region) and mod.script.lua's preRunFn / runFn.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local AN = ug_require "square_organic_towns::/organic_towns/ot_angles.lua"
local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"

local US = "::/names/usa/usa.names"
local EU = "::/names/europe/europe.names"

test("settings: preRunFn's pairs list, a dict, and baseConfig as the fallback", function()
	local s = AN.settings({ { "climate", "::/climates/dry/dry.clima" }, { "economy", "x" }, { "nameList", US } })
	eq(s, { nameList = US, climate = "::/climates/dry/dry.clima" })
	eq(AN.settings({ nameList = EU, climate = "temperate" }), { nameList = EU, climate = "temperate" })
	eq(AN.settings({}, { nameId = EU, climate = "subarctic" }), { nameList = EU, climate = "subarctic" })
	eq(AN.settings({ { "nameList", US } }, { nameId = EU }).nameList, US, "the dict pairs win over baseConfig")
	eq(AN.settings(nil, nil), {})
	eq(AN.settings({ "junk", { 5, 6 } }), {})
end)

test("region: from the name list, else from the climate", function()
	local r, src = AN.region({ nameList = US })
	eq(r, "US")
	eq(src, "nameList")
	r, src = AN.region({ nameList = "::/names/unknown/x.names", climate = "::/climates/subarctic/x.clima" })
	eq(r, "NORDIC")
	eq(src, "climate")
	eq((AN.region({})), "EU")
	eq((AN.region({ climate = "dry" })), "MED")
end)

test("angleFor: automatic by region, fixed choices, nil for the game default", function()
	eq(AN.angleFor("auto", "US"), 0)
	eq(AN.angleFor("auto", "OCEANIA"), 0)
	eq(AN.angleFor("auto", "EU"), 35)
	eq(AN.angleFor("auto", "MED"), 45)
	eq(AN.angleFor("auto", "NORDIC"), 25)
	eq(AN.angleFor("auto", "RU"), 30)
	eq(AN.angleFor("auto", "JP"), 15)
	eq(AN.angleFor("auto", "EAST_ASIA"), 15)
	eq(AN.angleFor("auto", nil, "dry"), 45, "no region: climate fallback")
	eq(AN.angleFor("grid", "EU"), 0)
	eq(AN.angleFor("mixed", "US"), 15)
	eq(AN.angleFor("organic", "US"), 40)
	eq(AN.angleFor("default", "EU"), nil)
	for i, c in ipairs(AN.CHOICES) do ok(PA.KEYS.start_angle.values[i] == c, "param value " .. c) end
end)

test("params: start_angle index -> choice, default automatic", function()
	eq(PA.parse(nil).startAngle, "auto")
	eq(PA.parse({ start_angle = 2 }).startAngle, "grid")
	eq(PA.parse({ start_angle = 5 }).startAngle, "default")
	eq(PA.parse({ start_angle = 9 }).startAngle, "auto")
	ok(PA.parse({ start_angle = 3 }).raw:find("start_angle=3", 1, true))
end)

--- mod.script.lua's data() with a fake ug_require and log.
local function loadScript()
	local lines = {}
	local env = setmetatable({
		ug_require = ug_require,
		log = { message = function(l) lines[#lines + 1] = l end, warning = function(l) lines[#lines + 1] = "WARN " .. l end },
	}, { __index = _ENV })
	local chunk = assert(loadfile(here .. "../../mods/square_organic_towns/content/mod.script.lua", "t", env))
	chunk()
	return env.data(), lines
end

test("mod.script: data() has preRunFn and runFn; preRunFn sets both angle ranges from a pairs configDict", function()
	local d, lines = loadScript()
	eq(type(d.preRunFn), "function")
	eq(type(d.runFn), "function")
	local bc = { townMajorStreetAngleRange = 0, townInitialMajorStreetAngleRange = 0 }
	d.preRunFn({}, { { "climate", "::/climates/temperate/temperate.clima" }, { "nameList", EU } }, {}, bc)
	eq(bc.townMajorStreetAngleRange, 35)
	eq(bc.townInitialMajorStreetAngleRange, 35)
	ok(lines[1]:find("[SQOT] ANGLE choice=auto region=EU regionSource=nameList", 1, true), lines[1])
	ok(lines[1]:find("angle=0/0->35", 1, true), lines[1])
	-- grid on a European map; game default leaves the values
	local bc2 = { townMajorStreetAngleRange = 7, townInitialMajorStreetAngleRange = 7 }
	d.preRunFn({}, { { "nameList", EU } }, { square_organic_towns = { start_angle = 2 } }, bc2)
	eq(bc2.townMajorStreetAngleRange, 0)
	local bc3 = { townMajorStreetAngleRange = 7, townInitialMajorStreetAngleRange = 9 }
	d.preRunFn({}, { { "nameList", US } }, { square_organic_towns = { start_angle = 5 } }, bc3)
	eq(bc3.townMajorStreetAngleRange, 7)
	eq(bc3.townInitialMajorStreetAngleRange, 9)
	-- never throws on junk
	d.preRunFn(nil, nil, nil, {})
end)
