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

-- "Car traffic" / "Town building capacity" (plans/square_stress_test/MORE_TRAFFIC.md, Phase 7a, NOT verified in
-- game): a loadScript modifier (category in base base/mod.lua:111; the base game registers one in
-- mission/modifier.lua:135) wraps the updateFn of town building scripts (buildings/**/<name>.script.lua ->
-- townbuildingutil.makeBuildingScript, townbuildingutil.lua:98-99) so each result's personCapacity is
-- patched by logic.patchTownBuildingResult. The original updateFn runs unprotected (its errors stay the
-- game's), the patch runs in pcall: a failure logs one warning and the result goes back as it is.
-- State per Lua state (runFn runs in ~50 of them, docs/findings.md), reset by every runFn (a new load).
-- Idempotent: a script whose updateFn is already one of our wrappers is left alone, so a second
-- registration in the same state never patches twice.
local MAX_FIRST <const> = 3
local tbState = {
	seen = 0,                       -- loadScript data with a top-level updateFn function
	wrapped = 0,                    -- of those, town building scripts wrapped
	first = {} as {string},         -- the first MAX_FIRST wrapped file names
	skipLogged = false,             -- "[SQST] town_building_skip" written (first non-matching updateFn)
	patchLogged = false,            -- "[SQST] town_building_patch" written (first patched result)
	warned = false,                 -- one log.warning per state at most
}
local wrappers : {any : boolean} = setmetatable({}, { __mode = "k" })

local function warnOnce(msg : string)
	if tbState.warned then return end
	tbState.warned = true
	log.warning(msg)
end

local function patchResult(fileName : string, result : any, cfg : SquareStressConfig)
	local r = result as {string : any}
	local pc = type(r) == "table" and r["personCapacity"] or nil
	local capBefore : any = type(pc) == "table" and (pc as {string : any})["capacity"] or nil
	if logic.patchTownBuildingResult(r, cfg) and not tbState.patchLogged then
		tbState.patchLogged = true
		log.message(logic.townBuildingPatchLine(fileName, r, capBefore, tbState.wrapped, tbState.seen))
	end
end

local function townBuildingModifier(cfg : SquareStressConfig) : function(string, table) : table
	return function(fileName : string, data : table) : table
		local ok, err : boolean, any = pcall(function()
			local d = data as {string : any}
			if type(d) ~= "table" or type(d["updateFn"]) ~= "function" then return end
			local orig = d["updateFn"] as function(any, any) : any
			if wrappers[orig] then return end
			tbState.seen = tbState.seen + 1
			if not logic.isTownBuildingScript(fileName) then
				if not tbState.skipLogged then
					tbState.skipLogged = true
					log.message("[SQST] town_building_skip first=" .. tostring(fileName) .. " (has updateFn, not a town building script)")
				end
				return
			end
			local wrapper = function(captureParams : any, params : any) : any
				local result = orig(captureParams, params)
				local okP, errP : boolean, any = pcall(patchResult, fileName, result, cfg)
				if not okP then warnOnce("[SQST] town_building_patch failed (" .. tostring(fileName) .. "): " .. tostring(errP)) end
				return result
			end
			wrappers[wrapper] = true
			d["updateFn"] = wrapper
			tbState.wrapped = tbState.wrapped + 1
			if #tbState.first < MAX_FIRST then tbState.first[#tbState.first + 1] = tostring(fileName) end
			if tbState.wrapped == MAX_FIRST then
				log.message(string.format("[SQST] town_building_wrap wrapped=%d seen=%d first=%s", tbState.wrapped,
					tbState.seen, table.concat(tbState.first, ",")))
			end
		end)
		if not ok then warnOnce("[SQST] loadScript modifier failed (" .. tostring(fileName) .. "): " .. tostring(err)) end
		return data
	end
end

mod.runFn = function(_captureParams : any, _settings : {{string, string}}, allModParams : {string : {string : integer}})
	local ok, cfg = pcall(logic.configFromParams, myParams(allModParams))
	if not ok or cfg == nil then return end
	if logic.wantsTownBuildingPatch(cfg) then
		-- wrapped/first: what this Lua state wrapped before this runFn (scripts load after runFn, so a
		-- new load normally shows 0 here; the town_building_wrap line follows once 3 are wrapped)
		log.message(string.format("[SQST] config %s wrapped=%d first=%s", logic.townBuildingConfigText(cfg),
			tbState.wrapped, #tbState.first > 0 and table.concat(tbState.first, ",") or "-"))
		tbState.seen, tbState.wrapped, tbState.first = 0, 0, {}
		tbState.skipLogged, tbState.patchLogged, tbState.warned = false, false, false
		addModifier("loadScript", townBuildingModifier(cfg))
	end
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
