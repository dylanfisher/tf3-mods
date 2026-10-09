-- Name set scripts (content/{{MOD_ID}}/names.script.lua + mod.script.lua runFn): climate routes, regional
-- sets, exact counts, streets. Fake data via stub_module; plain `require` in the scripts maps to ug_require.

local MOD = "{{MOD_ID}}"
local P = MOD .. "::/" .. MOD .. "/"

local TOWNS = {
	{ n = "Westbig", t = { "west", "big" }, p = 500000 },
	{ n = "Eastbig", t = { "east", "big" }, p = 200000 },
}
for i = 1, 30 do TOWNS[#TOWNS + 1] = { n = "W" .. i, t = { "west" }, p = 1000 } end
for i = 1, 30 do TOWNS[#TOWNS + 1] = { n = "E" .. i, t = { "east" }, p = 1000 } end
local TAGS = {}
for _, t in ipairs(TOWNS) do TAGS[t.n] = t.t[1] end

local STATE = { climates = { temperate = { west = 100 }, dry = { east = 100 } } }
local STREETS = { "Main Street", "Front Street", "Cedar Street" }

local function load(opts)
	opts = opts or {}
	reset_modules()
	set_global("data", nil)
	set_global("api", opts.api)
	set_global("SNGLOBAL_MODID", nil)
	set_global("require", function(p) return ug_require(p) end)
	stub_module(P .. "data/towns.lua", opts.towns or TOWNS)
	stub_module(P .. "data/state.lua", STATE)
	stub_module(P .. "data/streets.lua", opts.streets or STREETS)
	if opts.runFnClimate then
		ug_require(P .. "mod.script.lua")
		data().runFn({}, { climate = opts.runFnClimate, nameList = "x" }, {})
		set_global("data", nil)
	end
	ug_require(P .. "names.script.lua")
	return data()
end

local function apiWithClimate(c)
	return { engine = { config = { getConfigDict = function() return { climate = c } end } } }
end

local function allSide(list, side)
	for _, n in ipairs(list) do
		if TAGS[n] ~= side then return false, n end
	end
	return true
end

test("climate via getConfigDict picks the climate's towns", function()
	local fns = load({ api = apiWithClimate("::/climates/dry/dry.clima") })
	local res = fns.townsFn({}, { lang = "en", num = 10 })
	eq(#res, 10)
	eq(res[1], "Eastbig")
	ok(allSide(res, "east"))
end)

test("climate via the runFn global when api.engine is missing", function()
	local fns = load({ runFnClimate = "::/climates/temperate/temperate.clima" })
	local res = fns.townsFn({}, { lang = "en", num = 10 })
	eq(#res, 10)
	eq(res[1], "Westbig")
	ok(allSide(res, "west"))
end)

test("the runFn global wins over getConfigDict (Probe 3: name scripts have no api.engine)", function()
	local fns = load({ api = apiWithClimate("::/climates/dry/dry.clima"), runFnClimate = "::/climates/temperate/temperate.clima" })
	ok(allSide(fns.townsFn({}, { lang = "en", num = 5 }), "west"))
end)

--- the base game's _G guard (base/content/base/init.lua): logs ERROR "Global variable in mod" on assignment
--- (keeps the harness sandbox's own metatable, e.g. its __index; unguard() restores it)
local sandboxMeta
local function guardGlobals()
	local hits = {}
	local tos, rs = tostring, rawset
	sandboxMeta = getmetatable(_G)
	local mt = {}
	for k, v in pairs(sandboxMeta or {}) do mt[k] = v end
	mt.__newindex = function(t, k, v)
		hits[#hits + 1] = tos(k)
		rs(t, k, v)
	end
	setmetatable(_G, mt)
	return hits
end
local function unguard()
	setmetatable(_G, sandboxMeta)
end

test("runFn never assigns a global through the base guard; the names script still sees the climate", function()
	reset_modules()
	set_global("data", nil)
	set_global("SNGLOBAL_MODID", nil)
	set_global("require", function(p) return ug_require(p) end)
	stub_module(P .. "data/towns.lua", TOWNS)
	stub_module(P .. "data/state.lua", STATE)
	stub_module(P .. "data/streets.lua", STREETS)
	ug_require(P .. "mod.script.lua")
	local runFn = data().runFn
	ug_require(P .. "names.script.lua")
	local fns = data()
	local hits = guardGlobals()
	pcall(runFn, {}, { climate = "::/climates/dry/dry.clima", nameList = "x" }, {})
	local okR, res = pcall(fns.townsFn, {}, { lang = "en", num = 6 })
	unguard()
	ok(okR, tostring(res))
	eq(hits, {}, "no __newindex")
	ok(allSide(res, "east"))
end)

test("without rawset the climate still arrives through sn_shared.lua, with no global assigned", function()
	reset_modules()
	set_global("data", nil)
	set_global("SNGLOBAL_MODID", nil)
	set_global("require", function(p) return ug_require(p) end)
	stub_module(P .. "data/towns.lua", TOWNS)
	stub_module(P .. "data/state.lua", STATE)
	stub_module(P .. "data/streets.lua", STREETS)
	ug_require(P .. "mod.script.lua")
	local runFn = data().runFn
	ug_require(P .. "names.script.lua")
	local fns = data()
	-- shadow rawset in the sandbox globals (nil would fall through to the host's)
	local G, realRawset = _G, rawset
	realRawset(G, "SNGLOBAL_MODID", nil)
	realRawset(G, "rawset", false)
	local hits = guardGlobals()
	pcall(runFn, {}, { climate = "::/climates/dry/dry.clima", nameList = "x" }, {})
	local okR, res = pcall(fns.townsFn, {}, { lang = "en", num = 6 })
	unguard()
	realRawset(G, "rawset", nil)
	ok(okR, tostring(res))
	eq(hits, {}, "no __newindex")
	eq(rawget(G, "SNGLOBAL_MODID"), nil)
	ok(allSide(res, "east"))
end)

test("no climate visible: whole state, both big towns first", function()
	local fns = load({})
	local res = fns.townsFn({}, { lang = "en", num = 8 })
	eq(#res, 8)
	eq(res[1], "Westbig")
	eq(res[2], "Eastbig")
end)

test("unknown (mod) climate: whole state", function()
	local fns = load({ api = apiWithClimate("othermod::/climates/alpine/alpine.clima") })
	local res = fns.townsFn({}, { lang = "en", num = 4 })
	eq(res[1], "Westbig")
	eq(res[2], "Eastbig")
end)

test("regional set (option C) uses its tags, not the climate", function()
	local fns = load({ api = apiWithClimate("::/climates/dry/dry.clima") })
	local res = fns.townsFn({ tags = { "west" }, setId = "westside" }, { lang = "en", num = 12 })
	eq(#res, 12)
	ok(allSide(res, "west"))
end)

test("num = -1 returns every town; exact counts beyond the data", function()
	local fns = load({})
	eq(#fns.townsFn({}, { lang = "en", num = -1 }), #TOWNS)
	eq(#fns.townsFn({}, { lang = "en", num = #TOWNS + 7 }), #TOWNS + 7)
end)

test("broken data still returns the exact count", function()
	local fns = load({ towns = {} })
	eq(#fns.townsFn({}, { lang = "en", num = 3 }), 3)
end)

test("streets: num = -1 is a shuffle of the whole pool; positive num picks", function()
	local fns = load({})
	local all = fns.streetsFn({}, { lang = "en", num = -1 })
	eq(#all, #STREETS)
	local set = {}
	for _, s in ipairs(all) do set[s] = true end
	for _, s in ipairs(STREETS) do ok(set[s], s) end
	eq(#fns.streetsFn({}, { lang = "en", num = 5 }), 5)
end)
