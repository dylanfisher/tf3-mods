-- Organic Towns load-time scripts (mod.json preRunScript "...mod.script@preRunFn" and runScript
-- "...mod.script@runFn", the official mods' pattern: urbangames_sandbox / campaign mod.json). Plain Lua, pre-5.3.
-- .script.lua resources export through data() (a `return` fails in game).
--
-- preRunFn(captureParams, configDict, allModParams, baseConfig): the "Vanilla town street angles" setting writes the
-- game's own town street angle ranges into baseConfig (ot_angles). configDict here is a LIST of {key, value} pairs
-- (base/content/base/mod.script.tl:184-191 reads it so); the Organic Towns probe read it as a dict and logged nil,
-- so preRunFn does know the map's nameList and climate. One "[SQOT] ANGLE" log line. The "Starting town size"
-- setting scales baseConfig.locations.town.populationDensity (ot_townsize; "Game size" leaves it untouched): one
-- "[SQOT] TOWNSIZE" line. The "Streets at industries" setting writes baseConfig.locations.makeInitialStreets
-- (ot_indstreets; Off by default: false; "Game default" leaves it untouched): one "[SQOT] INDSTREETS" line.
-- "Act on: Off" skips all three (one "[SQOT] PRERUN actOn=off" line): the base game's values stay.
--
-- runFn(captureParams, configDict, allModParams) gets the map's `nameList` and `climate` as a dict
-- (docs/findings.md "Organic Towns probe": getConfigDict() at runtime lacks them). A global set here is visible
-- in the game script's update and guiUpdate (same Lua states), where ot_driver reads it with
-- pcall(function() return _G[k] end). Set with rawset inside pcall: a plain global assignment trips base
-- init.lua's "Global variable in mod" guard in every state (findings "Street names and Road Stops"); this is
-- the probe's verified pattern. rawset is never called from the game-script or GUI states (nil there).

local KEY = "SQOT_CONFIG"
local MOD_ID = "square_organic_towns"

local function txt(v)
	return (tostring(v):gsub("%s+", "_"))
end

local function preRunFn(_captureParams, configDict, allModParams, baseConfig)
	-- "Act on: Off" means the mod does nothing (2026-10-14, the vanilla baseline run still wrote the EU angle range):
	-- no angle, town size or industry-street write; one PRERUN line
	local okO, off = pcall(function()
		local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"
		local mine = type(allModParams) == "table" and allModParams[MOD_ID] or nil
		return PA.parse(mine, allModParams).actOn == "off"
	end)
	if okO and off then
		pcall(log.message, "[SQOT] PRERUN actOn=off writes=none angle=" .. txt(baseConfig and baseConfig.townMajorStreetAngleRange))
		return
	end
	local ok, err = pcall(function()
		local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"
		local AN = ug_require "square_organic_towns::/organic_towns/ot_angles.lua"
		local mine = type(allModParams) == "table" and allModParams[MOD_ID] or nil
		local opts = PA.parse(mine, allModParams)
		local s = AN.settings(configDict, baseConfig)
		local region, source, climate = AN.region(s, opts.styleRegion)
		local angle = AN.angleFor(opts.startAngle, region, climate)
		local before = string.format("%s/%s", txt(baseConfig.townMajorStreetAngleRange),
			txt(baseConfig.townInitialMajorStreetAngleRange))
		if angle ~= nil then
			baseConfig.townMajorStreetAngleRange = angle + 0.0
			baseConfig.townInitialMajorStreetAngleRange = angle + 0.0
		end
		log.message(string.format("[SQOT] ANGLE choice=%s region=%s regionSource=%s nameList=%s climate=%s angle=%s->%s "
			.. "initialRange=%s note=newMapGeneratorUnverified", txt(opts.startAngle), txt(region), txt(source),
			txt(s.nameList), txt(s.climate), before, txt(baseConfig.townMajorStreetAngleRange),
			txt(baseConfig.townInitialMajorStreetAngleRange)))
	end)
	if not ok then pcall(log.warning, "[SQOT] ANGLE error=" .. txt(err)) end
	-- "Starting town size" (ot_townsize, a test round): scales the generator's town population factor, which the base
	-- game's preRunFn has set from its own "Population" setting before ours runs. Game size (the default): untouched.
	local okT, errT = pcall(function()
		local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"
		local TS = ug_require "square_organic_towns::/organic_towns/ot_townsize.lua"
		local mine = type(allModParams) == "table" and allModParams[MOD_ID] or nil
		local opts = PA.parse(mine, allModParams)
		local r = TS.apply(baseConfig, opts.townSize)
		local f = TS.fields(r, "preRunFn")
		-- (captureParams: its type, to look for a new map / load signal; preRunFn can't tell them apart yet)
		f[#f + 1] = { "capture", type(_captureParams) }
		log.message(TS.line("TOWNSIZE", f))
	end)
	if not okT then pcall(log.warning, "[SQOT] TOWNSIZE error=" .. txt(errT)) end
	-- "Streets at industries" (ot_indstreets): Off writes makeInitialStreets = false, so a new map's industries get
	-- no generator streets for towns to fill; Game default (the default) leaves baseConfig untouched
	local okI, errI = pcall(function()
		local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"
		local TS = ug_require "square_organic_towns::/organic_towns/ot_townsize.lua"
		local IS = ug_require "square_organic_towns::/organic_towns/ot_indstreets.lua"
		local mine = type(allModParams) == "table" and allModParams[MOD_ID] or nil
		local opts = PA.parse(mine, allModParams)
		log.message(TS.line("INDSTREETS", IS.fields(IS.apply(baseConfig, opts.industryStreets), "preRunFn")))
	end)
	if not okI then pcall(log.warning, "[SQOT] INDSTREETS error=" .. txt(errI)) end
end

local function runFn(_captureParams, configDict, _allModParams)
	pcall(function()
		local d = type(configDict) == "table" and configDict or {}
		local cfg = { nameList = d.nameList, climate = d.climate }
		if not pcall(function() rawset(_G, KEY, cfg) end) then
			pcall(function() _G[KEY] = cfg end)
		end
	end)
end

function data()
	return {
		preRunFn = preRunFn,
		runFn = runFn,
	}
end
