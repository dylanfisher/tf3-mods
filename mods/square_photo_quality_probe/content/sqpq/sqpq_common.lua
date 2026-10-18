-- Photo Quality probe: constants and helpers shared by the mod script and the GUI plugin.
-- Plain Lua, pre-5.3. DEV only, never upload. Steps: plans/square_photo_quality_probe/TESTING.md.
--
-- Every log line starts with "[SQPQ] " and goes through log.message, so it lands in stdout.txt.

local M = {}

M.MOD_ID = "square_photo_quality_probe"
M.PREFIX = "[SQPQ] "

-- Graphics keys of AppConfig the settings page writes (base/content/gui/menu/settings_page.tl:866-990).
-- They are not in the AppConfig record of api/tealdef/api/type.d.tl, the page sets them by name.
-- shadowQuality left out (snapshot / restore never write it): see BOOST below. geometryQuality, terrainQuality and
-- grassQuality stay for the log lines; BOOST no longer changes them, so a restore writes back an unchanged value.
M.GRAPHICS_KEYS = {
	"textureQuality", "terrainTextureQuality", "numMSAASamples", "useSsao", "ssrQuality",
	"geometryQuality", "terrainQuality", "grassQuality", "resolutionScale", "vsync",
	"cameraTool",
}

-- "Very High" desktop preset values of the safe keys (base/content/gui/menu/graphics_presets_util.tl:90-100) plus
-- full resolution scale. numMSAASamples is replaced by the highest supported count when
-- app.getSupportedMSAASampleCounts works. Only keys that reload images / screen effects: changing render-buffer
-- settings at runtime crashed the game (shadowQuality 4 times, MoltenVK after "Could not invert matrix";
-- geometryQuality / terrainQuality / grassQuality once, StaticBuffer.cpp:743 assert; docs/findings/map-camera.md
-- "Changing render-buffer settings at runtime crashes"). Never change those from a mod.
M.BOOST = {
	terrainTextureQuality = 2,
	numMSAASamples = 4,
	useSsao = true,
	ssrQuality = 2,
	resolutionScale = 1.0,
}
M.BOOST_TEXTURES = 2 -- textureQuality, only with the param include_textures

-- Geometry tiers in baseConfig.settings.geometryQualityOptions (base/content/base/mod.script.tl:146-154)
M.TIER_NAMES = { "low", "medium", "high", "camtool", "cockpit", "camtool_preview" }
M.TIER_HIGH = 3
M.TIER_CAMTOOL = 4
M.TIER_CAMPREVIEW = 6

-- mod.json params: key -> option values (1-based option index arrives, docs/findings/scripting.md)
M.PARAMS = {
	include_textures = { true, false },
	restore_on_exit = { true, false },
	camtool_lod = { false, 10.0, 20.0 }, -- false = unchanged (5.0)
	camtool_far = { false, 40000.0 }, -- false = unchanged (22500)
	high_tier = { false, "camtool" }, -- "camtool": High tier gets lod 5.0, far 22500 like the base camera tool
	campreview_lod = { false, 5.0, 20.0 }, -- false = unchanged (1.0), "Camera tool preview" tier
}
M.DEFAULTS = {
	include_textures = 1,
	restore_on_exit = 1,
	camtool_lod = 1,
	camtool_far = 1,
	high_tier = 1,
	campreview_lod = 1,
}

function M.log(msg)
	if log ~= nil and log.message ~= nil then log.message(M.PREFIX .. msg) else print(M.PREFIX .. msg) end
end

local function optionIndex(key, raw)
	local count = #M.PARAMS[key]
	if raw == true then raw = 2 end
	local n = tonumber(raw)
	if n ~= nil and n == math.floor(n) and n >= 1 and n <= count then return n end
	return M.DEFAULTS[key]
end

function M.settingsFrom(params)
	local s = {}
	local p = type(params) == "table" and params or {}
	for key, values in pairs(M.PARAMS) do
		s[key] = values[optionIndex(key, p[key])]
	end
	return s
end

--- Settings from the GUI state: api.engine.config.getModParams() (engine.d.tl).
function M.runtimeSettings()
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	local mine = ok and type(all) == "table" and all[M.MOD_ID] or nil
	local s = M.settingsFrom(mine)
	s.source = mine ~= nil and "api" or ("defaults(" .. tostring(ok and "no entry" or all) .. ")")
	return s
end

function M.settingsText(s)
	return string.format("textures=%s restore=%s camtool_lod=%s camtool_far=%s high_tier=%s campreview_lod=%s",
		tostring(s.include_textures), tostring(s.restore_on_exit), tostring(s.camtool_lod), tostring(s.camtool_far),
		tostring(s.high_tier), tostring(s.campreview_lod))
end

--- One line with every graphics key of an AppConfig, each read in pcall.
function M.configText(cfg)
	if cfg == nil then return "cfg=nil" end
	local parts = {}
	for _, key in ipairs(M.GRAPHICS_KEYS) do
		local ok, v = pcall(function() return cfg[key] end)
		parts[#parts + 1] = key .. "=" .. (ok and tostring(v) or "ERR")
	end
	return table.concat(parts, " ")
end

--- One line with every geometry tier: name=far/near/lod.
function M.tiersText(settings)
	local ok, text = pcall(function()
		local list = settings.geometryQualityOptions
		local parts = {}
		for i = 1, #list do
			local o = list[i]
			parts[#parts + 1] = string.format("%s=near%.1f/far%.0f/lod%.2f", M.TIER_NAMES[i] or tostring(i),
				o.viewNearFar.x, o.viewNearFar.y, o.lodDistanceScaling)
		end
		return #list .. " tiers " .. table.concat(parts, " ")
	end)
	return ok and text or ("tiers ERR " .. tostring(text))
end

return M
