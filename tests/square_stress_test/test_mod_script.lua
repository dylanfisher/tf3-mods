-- mod.script.tl: preRunFn writes only non-default settings; runFn registers the no-end-year and the
-- vehicle emissions modifiers only when their param is on; postRunFn sets the town rating sensitivity
-- config only with "No noise and pollution".

local mods
local modifiers

before_each(function()
	reset_modules()
	clear_logs()
	modifiers = {}
	set_global("addModifier", function(kind, fn) modifiers[#modifiers + 1] = { kind = kind, fn = fn } end)
	mods = ug_require "square_stress_test::/mod.script.tl"
end)

local function bc()
	return { noCosts = false, sandboxMode = false, townDevelopInterval = 60, simPersonDestinationRecomputationProbability = 1.0,
		emission = { townNoiseResidentialAffected = true, townNoiseCommercialAffected = true, townNoiseIndustrialAffected = true },
		advancedOptions = { missionEmissionsScriptFactor = 1 } }
end

test("preRunFn with default params leaves the base config untouched", function()
	local b = bc()
	mods.preRunFn({}, {}, { square_stress_test = { no_costs = 1, sandbox = 1, sim_recompute = 1, town_develop = 1 } }, b)
	eq(b, bc())
	mods.preRunFn({}, {}, {}, b)
	mods.preRunFn({}, {}, nil, b)
	eq(b, bc())
end)

test("preRunFn applies the chosen options", function()
	local b = bc()
	mods.preRunFn({}, {}, { square_stress_test = { no_costs = 2, sandbox = 2, town_develop = 2, sim_recompute = 3 } }, b)
	eq(b.noCosts, true)
	eq(b.sandboxMode, true)
	eq(b.townDevelopInterval, 15)
	eq(b.simPersonDestinationRecomputationProbability, 5.0)
end)

test("preRunFn never throws", function()
	mods.preRunFn({}, {}, { square_stress_test = { no_costs = 2 } }, setmetatable({}, { __newindex = function() error("ro") end }))
end)

test("runFn: modifier only when vehicles_no_expire is on; it clears yearTo of vehicles only", function()
	mods.runFn({}, {}, { square_stress_test = { vehicles_no_expire = 1 } })
	eq(#modifiers, 0)
	mods.runFn({}, {}, { square_stress_test = { vehicles_no_expire = 2 } })
	eq(#modifiers, 1)
	eq(modifiers[1].kind, "loadModel")
	local vehicle = { metadata = { transportVehicle = {}, availability = { yearFrom = 1900, yearTo = 1950 } } }
	eq(modifiers[1].fn("bus.mdl", vehicle).metadata.availability.yearTo, 0)
	local tree = { metadata = { availability = { yearTo = 1950 } } }
	eq(modifiers[1].fn("tree.mdl", tree).metadata.availability.yearTo, 1950)
	eq(modifiers[1].fn("x.mdl", { metadata = {} }).metadata, {})
	-- registered again on every runFn call (no register-once guard)
	mods.runFn({}, {}, { square_stress_test = { vehicles_no_expire = 2 } })
	eq(#modifiers, 2)
end)

test("preRunFn with no_emissions: emissions script factor 0 and town noise off", function()
	local b = bc()
	mods.preRunFn({}, {}, { square_stress_test = { no_emissions = 2 } }, b)
	eq(b.advancedOptions.missionEmissionsScriptFactor, 0)
	eq(b.emission.townNoiseResidentialAffected, false)
	eq(b.emission.townNoiseIndustrialAffected, false)
	eq(b.noCosts, false)
end)

test("runFn: emissions modifier only with no_emissions; it zeroes vehicles", function()
	mods.runFn({}, {}, { square_stress_test = { no_emissions = 1 } })
	eq(#modifiers, 0)
	mods.runFn({}, {}, { square_stress_test = { no_emissions = 2, vehicles_no_expire = 2 } })
	eq(#modifiers, 2)
	eq(modifiers[2].kind, "loadModel")
	local bus = { metadata = { transportVehicle = {}, emissions = { noise = { score = 30 }, pollution = { score = 20 } } } }
	local out = modifiers[2].fn("bus.mdl", bus)
	eq(out.metadata.emissions.noise.score, 0)
	eq(out.metadata.emissions.pollution.idle, 0)
end)

local function sensitivityRes()
	local res = { data = { SensitivityUrbanCare = 2, SensitivityNoise = 4, SensitivityPollution = 4 }, set = nil }
	function res:setData(d) self.set = d end
	return res
end

test("postRunFn: town noise and pollution sensitivity option 1 only with no_emissions; never throws", function()
	local res = sensitivityRes()
	local found
	set_global("api", { res = { genericRep = {
		find = function(name) found = name return 3 end,
		get = function(id) eq(id, 3) return res end,
	} } })
	mods.postRunFn({}, {}, { square_stress_test = { no_emissions = 1 } })
	eq(res.set, nil)
	mods.postRunFn({}, {}, { square_stress_test = { no_emissions = 2 } })
	eq(found, "::/game_mechanics/towns/town_ratings_sensitivity.res")
	eq(res.set, { SensitivityUrbanCare = 2, SensitivityNoise = 1, SensitivityPollution = 1 })
	set_global("api", {})
	mods.postRunFn({}, {}, { square_stress_test = { no_emissions = 2 } })
	mods.postRunFn({}, {}, nil)
end)

test("runFn: the removed town_streets setting registers nothing, even with an old saved Wide value (crash 2026-10-11)", function()
	mods.runFn({}, {}, { square_stress_test = { town_streets = 2 } })
	eq(#modifiers, 0)
end)
