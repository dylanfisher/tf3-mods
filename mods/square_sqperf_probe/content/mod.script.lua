-- SQPERF probe: mod entry point (mod.json runScript "square_sqperf_probe::/mod.script@runFn").
-- Gives every industry construction without a hudIconScript the probe's HUD icon script, in memory
-- only (same loadConstruction modifier pattern as square_industry_production_label's
-- content/mod.script.lua; the HUD part decides per call whether to probe). If Industry Production
-- Label is enabled too, industries already have its script and are skipped: disable it for the probe.
-- runFn(captureParams, settings, allModParams): docs/findings.md "Script function signatures".
-- No register-once guard (memory: the modifier table is rebuilt per load). Plain Lua, pre-5.3.

local HUD_ICON_FN = "square_sqperf_probe::/sqperf_probe/probe_hud.script@hudIconFn"

local function isEmptyScriptRef(ref)
	if ref == nil then return true end
	if type(ref) ~= "table" then return false end
	return ref.fileName == nil or ref.fileName == ""
end

local function constructionModifier(_fileName, data)
	if type(data) == "table" and data.isIndustry and isEmptyScriptRef(data.hudIconScript) then
		data.hudIconScript = { fileName = HUD_ICON_FN, params = {} }
	end
	return data
end

function data()
	return {
		runFn = function(_captureParams, _settings, allModParams)
			addModifier("loadConstruction", constructionModifier)
			local mine = type(allModParams) == "table" and allModParams.square_sqperf_probe or nil
			local stage = type(mine) == "table" and mine.probe_stage or nil
			log.message("[SQPERF-PROBE] runFn modifier registered probe_stage=" .. tostring(stage))
		end,
	}
end
