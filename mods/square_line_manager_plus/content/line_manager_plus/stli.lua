-- Line Manager Plus, feature "Send to Line info": in the Line Manager's vehicle mode ("Send to Line"), the tooltip
-- shown while hovering a line on the map ("Send 3 vehicles to Bus Line 1.") gets the target line's vehicles by model
-- and its Capacity, Utilization, Frequency and Rate below it. GUI only: reads the game state, writes nothing, saves
-- nothing. Installed by lmp.script.lua (doReplace) through install() below, when the mod setting is On.
--
-- How: install replaces the recipe manager_tooltips_util.VMSendToLine (base
-- gui/line_vehicle_mgmt/manager_tooltips_util.tl:245, set as the tooltip by manager_window.tl:1241-1247) with
-- SendToLineInfo. That recipe WRAPS the vanilla one instead of rewriting it: react.CallOriginalRecipe
-- (base gui/main/react.lua:457) renders the game's own tooltip with the untouched params, and our lines go in a
-- second tooltip-styled text below it. We only read params.lineOrDepotEntity.
--
-- Failure handling (a recipe error drops the whole game UI, so nothing may escape):
-- * install: every step in pcall; if VMSendToLine is missing or no longer a recipe, nothing is replaced.
-- * render: the vanilla node and our lines are each built in pcall; any error or a hovered entity that is not a
--   line leaves the vanilla tooltip alone. Each failure kind is logged once ("[LineManagerPlus] send to line: ...").
-- Stats of a line come from lmp_stats.lua (the stli_core model shared with the colour dot tooltip, line_dot.lua),
-- cached for 1 s, so hovering costs one lookup per line per second.
--
-- Before -> after estimate (setting send_to_line_estimate, installed by stli_estimate.lua through enableEstimate):
-- the vehicles being sent are the Line Manager's selected vehicles (lmp_capture.selectedVehicles, the list the mode
-- itself sends, manager_window.tl:1180); VMSendToLine's params only carry their count (numVehicles,
-- manager_window.tl:1241-1247). Only when the captured list has exactly numVehicles entries are they passed to the
-- stats (stli_core.estimate adds "→ ~after" to Capacity, Frequency and Rate); otherwise current values only.

local PREFIX = "[LineManagerPlus] send to line: "
-- the vanilla tooltip's text classes (base gui/line_vehicle_mgmt/line_react_util.tl:20-32 makeTooltip), so our
-- block gets the same background, padding and font; "sq-lmp-stli" makes it a darker blue with a small gap above
-- (lmp.css.lua)
local TOOLTIP_CLASS = "lvm-selector-tooltip, font-scale-tooltip, default-tooltip-configuration, sq-lmp-stli"

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

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local stats = ug_require "square_line_manager_plus::/line_manager_plus/lmp_stats.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local origRecipe -- manager_tooltips_util.VMSendToLine, set in install
local selectedFn -- fn() -> {vehicle entity}, set by enableEstimate (lmp_capture.selectedVehicles)

-- the vehicles being sent, or nil (estimate off, a list that doesn't match the tooltip's count, or an error)
local function sentVehicles(params)
	if not selectedFn then return nil end
	local ok, res = pcall(function()
		local v = selectedFn()
		if type(v) == "table" and #v > 0 and #v == params.numVehicles then return v end
		return nil
	end)
	if ok then return res end
	warnOnce("selection", res)
	return nil
end

local function vanillaNode(params)
	local ok, node = pcall(react.CallOriginalRecipe, origRecipe, params)
	if ok then return node end
	warnOnce("vanilla tooltip", node)
	return nil
end

local function infoLines(params)
	local ok, lines = pcall(function()
		if type(params) ~= "table" then return nil end
		return stats.lines(params.lineOrDepotEntity, sentVehicles(params))
	end)
	if ok then return lines end
	warnOnce("line info", lines)
	return nil
end

-- the root is a BoxLayout, as every custom recipe's must be (a Component/TextView root crashes the game).
-- SQPERF section "tooltip": one render, the vanilla node included (perf:wrap passes errors through; none escape here).
local SendToLineInfo = react.RegisterRecipe("SquareLmpSendToLineInfo", perf:wrap("tooltip", function(params)
	local children = {}
	local base = vanillaNode(params)
	if base ~= nil then children[#children + 1] = base end
	local lines = infoLines(params)
	if lines and #lines > 0 then
		children[#children + 1] = builtin.TextView{
			meta = { class = TOOLTIP_CLASS },
			text = table.concat(lines, "\n"),
		}
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end))

local installed = false
--- Replaces VMSendToLine; true when it did (or already had). Never errors.
local function install(replacementApi)
	if installed then return true end
	local ok, err = pcall(function()
		local tooltips = ug_require "::/gui/line_vehicle_mgmt/manager_tooltips_util.tl"
		local orig = type(tooltips) == "table" and tooltips.VMSendToLine or nil
		-- read now, not at load; another mod may have put a plain function there, which CallOriginalRecipe can't run
		if type(orig) ~= "function" or not react.GetRecipeId(orig) then
			warnOnce("install", "manager_tooltips_util.VMSendToLine is not a recipe (" .. type(orig) .. "); tooltip left as is")
			return
		end
		origRecipe = orig
		replacementApi.ReplaceRecipe(orig, SendToLineInfo)
		installed = true
		say("installed")
	end)
	if not ok then
		origRecipe = nil
		warnOnce("install", err)
	end
	return installed
end

return {
	install = install,
	SendToLineInfo = SendToLineInfo,
	--- true once the tooltip is replaced (the estimate needs it)
	isInstalled = function() return installed end,
	--- turns the before -> after estimate on; fn() returns the selected vehicles' entities
	enableEstimate = function(fn) selectedFn = fn end,
}
