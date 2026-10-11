-- Line Manager Plus, feature "Send to Line: before/after estimate" (PLAN.md feature 2, setting send_to_line_estimate):
-- the Send to Line hover text (stli.lua) shows what sending the selected vehicles would do to the target line, e.g.
-- "Capacity: 40 → ~80", "Frequency: 7 min 19 s → ~4 min 53 s", "Rate: 66 → ~132". Formulas and edge cases:
-- stli_core.lua header (core.estimate). GUI only: reads the game state, writes nothing, saves nothing.
--
-- It extends the Send to Line info feature, so it needs that one installed (setting send_to_line_info On; lmp.script
-- installs the features in order, info first). The selection comes from the shared lmp_capture.lua (one wrapper of
-- line_util.makeLineActionDescriptor). Any failure here leaves the info without arrows; logged once as
-- "[LineManagerPlus] estimate: ...".

local PREFIX = "[LineManagerPlus] estimate: "

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local M = {}

--- Turns the estimate on in stli.lua; true when it did. Never errors.
function M.install(_replacementApi)
	local done = false
	local ok, err = pcall(function()
		local stli = ug_require "square_line_manager_plus::/line_manager_plus/stli.lua"
		if not stli.isInstalled() then
			say("not installed: it needs \"Send to Line: target line info\" On")
			return
		end
		local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
		if not capture.install() then
			warnOnce("install", "the Line Manager's selection can't be read; no estimate")
			return
		end
		stli.enableEstimate(function() return capture.selectedVehicles() end)
		done = true
		say("installed")
	end)
	if not ok then warnOnce("install", err) end
	return done
end

return M
