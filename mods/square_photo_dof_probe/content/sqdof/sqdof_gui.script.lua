-- DoF probe GUI plugin (top-left mod button ridge). DEV only, never upload.
--
-- The button cycles the rendering environment: off -> tilt -> dof -> dof_shallow -> debug -> off. Each mode is
-- one of this mod's env files (content/environments/sqdof_<climate>_<mode>.env.lua, plans/square_photo_dof_probe/
-- gen_envs.py): the current base climate's env with light.latitude + 2 pi * mode, which the manually installed
-- probe shader (shader_files/.../ssr_apply.fs) reads as its mode. Without that shader the switch changes nothing
-- visible. Switching is rendering only (api.gui.rendering.setEnvironment, docs/findings/environment.md): nothing
-- reaches the save. A switch resets the six live atmosphere fields to the file's, so they are carried over.
-- Off (button, pause menu, unmount) switches back to the game's environment ResName.
-- Every line starts with [SQDOF] in stdout.txt.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"

local MOD_ID = "square_photo_dof_probe"
local MODES = { "tilt", "dof", "dof_shallow", "debug" } -- index = shader mode (latitude + 2 pi * index)
local CLIMATES = { dry = true, temperate = true, tropical = true, subarctic = true }
local ATMO_KEYS = { "cloudCoverage", "cloudBase", "cloudTop", "cloudScattering", "dayOfYear", "sunRotation" }

local S = {
	mode = 0, -- 0 = off
	saved = nil, -- { resName, atmo } while a probe env is on
	shown = nil,
}

local function say(msg)
	if log ~= nil and log.message ~= nil then log.message("[SQDOF] " .. msg) else print("[SQDOF] " .. msg) end
end

local function fmt(v)
	if type(v) == "number" then return string.format("%.6g", v) end
	return tostring(v)
end

local function buttonText()
	if S.mode == 0 then return "SQDOF off" end
	return "SQDOF " .. MODES[S.mode]
end

local function refreshButton()
	if S.shown == nil then return end
	local ok = pcall(function()
		if not S.shown:hasExpired() then S.shown:set(buttonText()) end
	end)
	if not ok then S.shown = nil end
end

local function readAtmo()
	local e = api.gui.rendering.getEnvironment()
	local out = {}
	for _, k in ipairs(ATMO_KEYS) do out[k] = e.atmosphere[k] end
	return out, e.name
end

local function atmoText(t)
	local parts = {}
	for _, k in ipairs(ATMO_KEYS) do parts[#parts + 1] = k .. "=" .. fmt(t[k]) end
	return table.concat(parts, " ")
end

--- Sets the env resource `resName`, then puts the live atmosphere values `atmo` back on it.
local function switchTo(resName, atmo)
	local id = api.res.environmentRep.find(resName)
	if id == nil or id < 0 then
		say("switch: env not found: " .. tostring(resName))
		return false
	end
	api.gui.rendering.setEnvironment(api.res.environmentRep.get(id))
	local e = api.gui.rendering.getEnvironment()
	for _, k in ipairs(ATMO_KEYS) do
		if type(atmo[k]) == "number" then e.atmosphere[k] = atmo[k] end
	end
	api.gui.rendering.setEnvironment(e)
	return true
end

local function off(why)
	if S.saved == nil then
		S.mode = 0
		refreshButton()
		return
	end
	local saved = S.saved
	S.saved = nil
	S.mode = 0
	local ok, res = pcall(switchTo, saved.resName, saved.atmo)
	local okR, atmo, name = pcall(readAtmo)
	say(string.format("off (%s) back to %s ok=%s now name=%s %s", why, tostring(saved.resName),
		tostring(ok and res), okR and tostring(name) or "?", okR and atmoText(atmo) or tostring(atmo)))
	refreshButton()
end

local function cycle()
	local nxt = S.mode + 1
	if nxt > #MODES then
		off("button")
		return
	end
	if S.saved == nil then
		local resName = tostring(api.gui.game.getEnvironment())
		local climate = string.match(resName, "^::/climates/([%a]+)/")
		if climate == nil or not CLIMATES[climate] then
			say("refused: the game environment is not a base climate env: " .. resName)
			return
		end
		local atmo = readAtmo()
		S.saved = { resName = resName, climate = climate, atmo = atmo }
		say("saved " .. resName .. " " .. atmoText(atmo))
	end
	local target = string.format("%s::/environments/sqdof_%s_%s.env", MOD_ID, S.saved.climate, MODES[nxt])
	local ok, res = pcall(switchTo, target, S.saved.atmo)
	if not (ok and res) then
		say("switch to " .. target .. " FAILED " .. tostring(res))
		off("switch failed")
		return
	end
	S.mode = nxt
	local okR, atmo, name = pcall(readAtmo)
	say(string.format("mode %d %s on: %s now name=%s %s", nxt, MODES[nxt], target,
		okR and tostring(name) or "?", okR and atmoText(atmo) or tostring(atmo)))
	refreshButton()
end

local PhotoDofProbePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension,
	"PhotoDofProbePlugin", function()
	local shown = react.useState(buttonText())
	S.shown = shown
	react.onEvent("openPauseMenu", function()
		local ok, err = pcall(off, "pause menu")
		if not ok then say("pause ERROR " .. tostring(err)) end
	end)
	react.onUnmount(function()
		local ok, err = pcall(off, "unmount")
		if not ok then say("unmount ERROR " .. tostring(err)) end
	end)
	-- recipe roots must be layouts (docs/findings/gui.md)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { tooltip = "DEV DoF probe. Click: off -> tilt -> dof -> dof_shallow\n-> debug -> off. Needs the probe shader in the game\n(TESTING.md). Logs [SQDOF] lines to stdout.txt." },
				content = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = shown:old() },
				onClick = function()
					local ok, err = pcall(cycle)
					if not ok then say("click ERROR " .. tostring(err)) end
				end,
			},
		},
	}
end)

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return {
		PhotoDofProbePlugin = PhotoDofProbePlugin,
	}
end
