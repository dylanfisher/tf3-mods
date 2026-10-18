-- Organic Towns: the game's own town street angle ranges per region (pure). mod.script.lua's preRunFn writes them
-- into baseConfig: townInitialMajorStreetAngleRange (a town's first layout: a new map's starting towns and towns
-- founded later) and townMajorStreetAngleRange (the game's own later street growth). Both are "angle within town
-- major street directions are randomized (in degrees)" (base/content/base/mod.script.tl:110-111, default 0).
-- Probe C (docs/findings.md, Organic Towns showcase v2): TownInfo angle 0 = a strict rectilinear grid, 15 = mild,
-- 45 = visibly irregular. Whether the new-map generator reads the baseConfig range is unverified (the town
-- builder tool does: town_builder_tool.script.tl:99, construction_react_util.tl:3531).
--
-- preRunFn's configDict is a LIST of {key, value} pairs (base mod.script.tl:184-191 turns it into a table the
-- same way); a dict-style table is accepted too.

local I = ug_require "square_organic_towns::/organic_towns/ot_inputs.lua"

local M = {}

M.CHOICES = { "auto", "grid", "mixed", "organic", "default" }

-- fixed choices (degrees); "auto" uses BY_REGION, "default" leaves the game's value (nil)
M.FIXED = { grid = 0, mixed = 15, organic = 40 }

M.BY_REGION = { US = 0, OCEANIA = 0, EU = 35, MED = 45, NORDIC = 25, RU = 30, JP = 15, EAST_ASIA = 15, ASIA = 25,
	MIXED = 25 }

--- { nameList, climate } from a preRunFn configDict (pairs list or dict) and, as a fallback, baseConfig.nameId /
--- baseConfig.climate (set by base's preRunFn, if it ran before ours).
function M.settings(configDict, baseConfig)
	local out = {}
	if type(configDict) == "table" then
		for _, v in ipairs(configDict) do
			if type(v) == "table" and type(v[1]) == "string" then out[v[1]] = v[2] end
		end
		if out.nameList == nil and type(configDict.nameList) == "string" then out.nameList = configDict.nameList end
		if out.climate == nil and type(configDict.climate) == "string" then out.climate = configDict.climate end
	end
	if type(baseConfig) == "table" or type(baseConfig) == "userdata" then
		if out.nameList == nil then
			local ok, v = pcall(function() return baseConfig.nameId end)
			if ok and type(v) == "string" and v ~= "" then out.nameList = v end
		end
		if out.climate == nil then
			local ok, v = pcall(function() return baseConfig.climate end)
			if ok and type(v) == "string" and v ~= "" then out.climate = v end
		end
	end
	return { nameList = out.nameList, climate = out.climate }
end

--- Region, regionSource ("setting" | "nameList" | "climate"), climate id for the settings. styleRegion: the
--- "Town style" setting's region (ot_params) or nil.
function M.region(s, styleRegion)
	local climate = I.climate(s and s.climate)
	if styleRegion ~= nil and I.REGION[styleRegion] then return styleRegion, "setting", climate end
	local region = I.region(s and s.nameList)
	if region then return region, "nameList", climate end
	return I.regionFromClimate(climate), "climate", climate
end

--- Angle range in degrees for a choice, or nil (leave the game's value).
function M.angleFor(choice, region, climate)
	if choice == "default" then return nil end
	if M.FIXED[choice] ~= nil then return M.FIXED[choice] end
	-- auto (and anything unknown)
	local r = region or I.regionFromClimate(I.climate(climate))
	local a = M.BY_REGION[r]
	if a == nil then a = M.BY_REGION.EU end
	return a
end

return M
