-- Stress Test load-time settings. Script functions referenced from mod.json as
-- "square_stress_test::mod.script@<function>"; captureParams comes first (base base/base_mod.lua:8,
-- base/mod.script.tl:16; docs/findings.md "Script function signatures"). Param values are 1-based
-- option indices.
--
-- BaseConfig values (noCosts, sandboxMode, the emissions script factor, town noise, sim person
-- recomputation, town develop interval) can only be written in preRunFn, which is the one script function
-- that receives the BaseConfig (official mods: .cache/game/mods/release/urbangames_no_costs/content/mod.script.tl:4-6,
-- urbangames_sandbox/content/mod.script.tl:4-6). The loadModel modifiers ("vehicles never expire", vehicle
-- emissions) need runFn (urbangames_vehicles_no_end_year/content/mod.script.lua:4-9). The default town
-- rating sensitivity is a script config resource the base game itself sets in its postRunFn (base
-- base/mod.script.tl:676-692), so ours goes there too. Defaults write nothing.
--
-- "No noise and pollution" (no_emissions) does all three: preRunFn emissions script factor 0 + town noise
-- off, runFn vehicle emissions 0, postRunFn town noise/pollution sensitivity 0 (stress_logic.tl explains
-- each). It replaced the earlier "Town noise ignored" param: that was only one of the three parts.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic

local MOD_ID <const> = "square_stress_test"

local function myParams(allModParams : {string : {string : integer}}) : {string : any}
	if allModParams == nil then return {} end
	return (allModParams[MOD_ID] or {}) as {string : any}
end

local mod = {}

mod.preRunFn = function(_captureParams : any, _configDict : {{string, string}}, allModParams : {string : {string : integer}}, baseConfig : BaseConfig)
	local ok, err : boolean, any = pcall(function()
		local cfg = logic.configFromParams(myParams(allModParams))
		local changes = logic.applyToBaseConfig(cfg, baseConfig)
		if #changes > 0 then
			log.message("[SQST] config " .. table.concat(changes, " "))
		end
	end)
	if not ok then log.warning("[SQST] preRunFn failed: " .. tostring(err)) end
end

-- Idempotent modifier: registered on every runFn call, never behind a "registered once" flag
-- (memory: tf3-runfn-no-register-once-guard).
local function noEndYear(_fileName : string, data : table) : table
	local md = data ~= nil and data["metadata"] as {string : {string : any}} or nil
	if md ~= nil and md["transportVehicle"] ~= nil and md["availability"] ~= nil then
		md["availability"]["yearTo"] = 0
	end
	return data
end

local function noEmissions(_fileName : string, data : table) : table
	logic.zeroVehicleEmissions(data)
	return data
end

mod.runFn = function(_captureParams : any, _settings : {{string, string}}, allModParams : {string : {string : integer}})
	local ok, cfg = pcall(logic.configFromParams, myParams(allModParams))
	if not ok or cfg == nil then return end
	if cfg.vehiclesNoExpire then
		addModifier("loadModel", noEndYear)
	end
	if cfg.noEmissions then
		addModifier("loadModel", noEmissions)
	end
end

-- Default town rating sensitivity for noise and pollution = 0 (stress_logic.SENSITIVITY_OFF), written the
-- way the base postRunFn writes it (base base/mod.script.tl:680-684 -> scripts/util/config_util.tl:3-8).
-- Mod postRunFns run after the base one (as preRunFns do: the base preRunFn sets noCosts = false at
-- base/mod.script.tl:82 and the official No Costs mod's true wins), so ours is the value that stays.
mod.postRunFn = function(_captureParams : any, _configDict : {{string, string}}, allModParams : {string : {string : integer}})
	local ok, err : boolean, any = pcall(function()
		local cfg = logic.configFromParams(myParams(allModParams))
		if not cfg.noEmissions then return end
		local res = api.res.genericRep.get(api.res.genericRep.find("::/game_mechanics/towns/town_ratings_sensitivity.res"))
		local data = res.data as {string : integer}
		local parts : {string} = {}
		for field, index in pairs(logic.SENSITIVITY_OFF) do
			data[field] = index
			parts[#parts + 1] = field .. "=" .. tostring(index)
		end
		table.sort(parts)
		res:setData(data as table)
		log.message("[SQST] config town_ratings_sensitivity " .. table.concat(parts, " "))
	end)
	if not ok then log.warning("[SQST] postRunFn failed: " .. tostring(err)) end
end

return mod
