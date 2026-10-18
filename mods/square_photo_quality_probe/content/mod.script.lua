-- Photo Quality probe: load-time part (mod.json preRunScript / postRunScript). DEV only, never upload.
--
-- Q4: can a mod change the geometry tiers (draw distance, LOD scaling) of baseConfig.settings
-- (base/content/base/mod.script.tl:146-154), and does the change show in game? preRunFn rebuilds the whole
-- Settings the way the base game does (the list elements are userdata copies, so editing one in place may not
-- stick), postRunFn logs the read-back from api.res.getBaseConfig().

local common = require "square_photo_quality_probe::/sqpq/sqpq_common.lua"

local function mine(allModParams)
	if type(allModParams) ~= "table" then return nil end
	return allModParams[common.MOD_ID]
end

local function option(o)
	local n = api.type.BaseConfig.Settings.GeometryQualityOption.new()
	n.viewNearFar = api.type.Vec2f.new(o.viewNearFar.x, o.viewNearFar.y)
	n.fogStartEndFarPerc = api.type.Vec2f.new(o.fogStartEndFarPerc.x, o.fogStartEndFarPerc.y)
	n.lodDistanceScaling = o.lodDistanceScaling
	return n
end

local mod = {}

function mod.preRunFn(_captureParams, _configDict, allModParams, baseConfig)
	local ok, err = pcall(function()
		local s = common.settingsFrom(mine(allModParams))
		common.log("load preRunFn " .. common.settingsText(s))
		common.log("load preRunFn before " .. common.tiersText(baseConfig.settings))
		if not s.camtool_lod and not s.camtool_far and not s.high_tier and not s.campreview_lod then
			common.log("load preRunFn no tier writes")
			return
		end
		local old = baseConfig.settings.geometryQualityOptions
		local list = {}
		for i = 1, #old do list[i] = option(old[i]) end
		local cam = list[common.TIER_CAMTOOL]
		if s.high_tier == "camtool" then
			-- base camera tool values, taken before the camtool_* params change them
			local high = list[common.TIER_HIGH]
			high.viewNearFar = api.type.Vec2f.new(high.viewNearFar.x, cam.viewNearFar.y)
			high.lodDistanceScaling = cam.lodDistanceScaling
		end
		if s.camtool_lod then cam.lodDistanceScaling = s.camtool_lod end
		if s.camtool_far then cam.viewNearFar = api.type.Vec2f.new(cam.viewNearFar.x, s.camtool_far) end
		if s.campreview_lod then list[common.TIER_CAMPREVIEW].lodDistanceScaling = s.campreview_lod end
		local settings = api.type.BaseConfig.Settings.new()
		settings.geometryQualityOptions = list
		baseConfig.settings = settings
		common.log("load preRunFn after " .. common.tiersText(baseConfig.settings))
	end)
	if not ok then common.log("load preRunFn ERROR " .. tostring(err)) end
end

function mod.postRunFn(_captureParams, _configDict, _allModParams)
	local ok, err = pcall(function()
		common.log("load postRunFn readback " .. common.tiersText(api.res.getBaseConfig().settings))
	end)
	if not ok then common.log("load postRunFn ERROR " .. tostring(err)) end
end

function data()
	return mod
end
