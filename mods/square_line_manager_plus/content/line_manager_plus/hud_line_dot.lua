-- Line Manager Plus, feature "Line editor: active border on line dot". GUI only: reads the game state, writes
-- nothing, saves nothing. Installed by lmp.script.lua (doReplace) through install() below.
--
-- In the line editor, a stop's map HUD shows a row of colored dots, one per player line that stops there (base
-- manager_hud_util.tl:119-161, StopLinesDisplay, inside the recipe HudStationWithLineStops). Lines of similar colors
-- look alike, so the dot of the line being edited gets a border: NeutralDarkest on a light dot, NeutralLightest on a
-- dark one (the base hover picks its border the same way, gui_react_util.stylingHoverClassForColor). Inline style on
-- the dot Button, as the base gives the stop-number button an inline borderColor (manager_hud_util.tl:93-98): the base
-- `Button!line-dot` rule already has the contour borderImage with an Invisible borderColor, so 0 stylesheet rules.
--
-- Hook: StopLinesDisplay is file-local. Per dot it builds
--   builtin.Button{ meta = { class = "line-dot,...", styleSheet = ..., tooltip = makeSelectLineTooltip(lineEntity) }, ... }
-- with field lookups of builtin.Button and manager_tooltips_util.makeSelectLineTooltip. Lua resolves the callee
-- builtin.Button before it evaluates the argument table, so swapping builtin.Button from inside the tooltip call would
-- reach the next dot, not this one. Both fields are wrapped instead, once:
--   * makeSelectLineTooltip: when called for the edited line (lmp_capture.editedLine) while HudStationWithLineStops
--     renders, it arms the Button wrapper with the line and the tooltip text it returns;
--   * builtin.Button: unarmed, it calls the previous function straight away (one nil check). Armed, it disarms first,
--     then, when the params are a line dot's (class "line-dot," and that exact tooltip), calls it with a copy whose
--     styleSheet adds the border. The table constructor makes no other Button call between the two.
-- Every other call (other recipe, other line, no line edited) passes through unchanged. The other base caller of the
-- tooltip (manager_tooltips_util.SelectLine) renders in its own recipe, so it never arms.
--
-- Chain safety: install() wraps whatever the fields hold then; the replacement api is not involved (plain function
-- fields, not recipes). Guard flag on the tooltip module table: `squareLmpLineDot`.
--
-- Cost: one nil check per builtin.Button call anywhere; one recipe-name check per dot while the line editor shows a
-- stop HUD; the border dot also reads its line's COLOR component.

local PREFIX = "[LineManagerPlus] line dot: "

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

local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"

local M = {}

M.TOOLTIPS = "::/gui/line_vehicle_mgmt/manager_tooltips_util.tl"
M.RECIPE = "HudStationWithLineStops"
M.CLASS = "line-dot,"
M.GUARD = "squareLmpLineDot"

local react, builtin, styleutil, color_util
local colors -- default_colors.gres data, read once

--- The line's color as a Vec4f, or nil. Errors propagate.
local function lineColor4(line)
	local c = api.engine.getComponent(line, api.type.ComponentType.COLOR)
	if c == nil or c.color == nil then return nil end
	return api.type.Vec4f.new(c.color, 1.0)
end

--- The border color for a dot of color c (Vec4f): dark on a light dot, light on a dark one. Errors propagate.
function M.borderColor(c)
	if colors == nil then
		colors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	end
	return color_util.toVec4((c.x + c.y + c.z) / 3 > 0.5 and colors.NeutralDarkest or colors.NeutralLightest)
end

--- A copy of a line dot's Button params with the border added, or nil when params aren't a line dot's.
--- Errors propagate.
function M.borderParams(params, line)
	if type(params) ~= "table" or type(params.meta) ~= "table" then return nil end
	local class = params.meta.class
	if type(class) ~= "string" or class:sub(1, #M.CLASS) ~= M.CLASS then return nil end
	local c = lineColor4(line)
	if c == nil then return nil end
	local meta = {}
	for k, v in pairs(params.meta) do meta[k] = v end
	meta.styleSheet = styleutil.makeStyle{ backgroundColor1 = c, borderColor = M.borderColor(c) }
	local copy = {}
	for k, v in pairs(params) do copy[k] = v end
	copy.meta = meta
	return copy
end

local armed -- { line, text } between the edited line's tooltip call and its Button call

local function button(prev)
	return function(params, ...)
		if armed == nil then return prev(params, ...) end
		local a = armed
		armed = nil
		if type(params) == "table" and type(params.meta) == "table" and params.meta.tooltip == a.text then
			local ok, copy = pcall(M.borderParams, params, a.line)
			if not ok then
				warnOnce("dot", copy)
			elseif copy ~= nil then
				return prev(copy, ...)
			end
		end
		return prev(params, ...)
	end
end

--- true when the dot of `entity` should get the border: the edited line while a stop HUD renders. Errors propagate.
function M.wants(entity)
	if entity == nil then return false end
	if react.getCurrentRecipeName() ~= M.RECIPE then return false end
	return capture.editedLine() == entity
end

local installed = false

--- Wraps manager_tooltips_util.makeSelectLineTooltip; true when installed (now or before). Never errors.
function M.install(_replacementApi, _params)
	if installed then return true end
	local ok, err = pcall(function()
		local mtu = ug_require(M.TOOLTIPS)
		react = ug_require "::/gui/main/react.lua"
		builtin = ug_require "::/gui/main/builtin.lua"
		styleutil = ug_require "::/gui/main/styleutil.tl"
		color_util = ug_require "::/gui/main/color_util.tl"
		if type(mtu) ~= "table" or type(builtin) ~= "table" or type(styleutil) ~= "table"
				or type(color_util) ~= "table" then
			warnOnce("install", "manager_tooltips_util, builtin, styleutil or color_util missing; not installed")
			return
		end
		if mtu[M.GUARD] then
			installed = true
			return
		end
		local prev = mtu.makeSelectLineTooltip
		local prevButton = builtin.Button
		if type(prev) ~= "function" or type(prevButton) ~= "function"
				or type(react.getCurrentRecipeName) ~= "function" then
			warnOnce("install", "makeSelectLineTooltip / builtin.Button / react.getCurrentRecipeName missing; not installed")
			return
		end
		if not capture.install() then
			warnOnce("install", "line capture not installed; not installed")
			return
		end
		mtu[M.GUARD] = true
		builtin.Button = button(prevButton)
		mtu.makeSelectLineTooltip = function(entity, ...)
			local text = prev(entity, ...)
			armed = nil
			local okW, want = pcall(M.wants, entity)
			if not okW then
				warnOnce("check", want)
			elseif want and type(text) == "string" then
				armed = { line = entity, text = text }
			end
			return text
		end
		installed = true
		say("installed")
	end)
	if not ok then warnOnce("install", err) end
	return installed
end

return M
