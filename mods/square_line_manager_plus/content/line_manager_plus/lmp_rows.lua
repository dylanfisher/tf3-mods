-- Line Manager Plus, shared groundwork: one slot in the line editor's button row for every feature
-- (plans/square_line_manager_plus/PLAN.md "Shared groundwork").
--
-- One wrapper of button_react_util.makeIconToggleButton (base button_react_util.tl:57-80, a module table field looked
-- up per call). When it builds the Auto-Rename icon ("A+", manager_window.tl:3520 with iconPaths.abAutoRename, :6317)
-- inside LinePanelActionButtons, the registered injectors' nodes are put around it:
--   BoxLayout{ <order < 0>..., A+, <order >= 0>... }
-- Anything else (other icons, other recipes, no manager params captured yet, no injector adding a node) returns the
-- base node unchanged. Precedent: undo.lua's former iconToggleButton; aat_eow.script.lua:640-661, :704-716.
--
-- Injectors: rows.register{ id = "undo", order = -100, build = function(ctx) return { node, ... } or nil end }.
-- ctx = { params = the captured commonParams (lmp_capture) }. Each build runs in its own pcall: a failing injector
-- drops only its own nodes and is logged once. Sorted by order, then by registration; registering an id again
-- replaces it. Orders in use: -100 undo (Undo, Redo). Planned: the Line Rate Matcher before undo, the "Line actions"
-- popover button after A+.
--
-- install() reads the current function at install time, so other mods' wrappers (Auto Assign Terminals) stay in the
-- chain, and wraps only once. SQPERF section "toggle_button" (the wrapper, the base function included).
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"

local M = {}

M.AUTO_RENAME_ICON = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"
M.RECIPE_ACTION_BUTTONS = "LinePanelActionButtons"

local PREFIX = "[LineManagerPlus] rows: "

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local injectors = {} -- sorted by order, then registration
local seq = 0

--- Adds (or replaces, same id) an injector { id, order, build }. Errors on a malformed injector.
function M.register(inj)
	assert(type(inj) == "table" and type(inj.id) == "string" and type(inj.build) == "function",
		"injector needs id and build")
	local order = type(inj.order) == "number" and inj.order or 0
	for i = #injectors, 1, -1 do
		if injectors[i].id == inj.id then table.remove(injectors, i) end
	end
	seq = seq + 1
	injectors[#injectors + 1] = { id = inj.id, order = order, build = inj.build, seq = seq }
	table.sort(injectors, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.seq < b.seq
	end)
end

--- The registered injector ids in row order (tests, logging).
function M.ids()
	local out = {}
	for i, inj in ipairs(injectors) do out[i] = inj.id end
	return out
end

local orig -- the previous makeIconToggleButton, set by install()

local function wrap(node)
	if react.getCurrentRecipeName() ~= M.RECIPE_ACTION_BUTTONS then return nil end
	local params = capture.params()
	if not params then return nil end
	local ctx = { params = params }
	local children, anchored, added = {}, false, false
	for _i, inj in ipairs(injectors) do
		if not anchored and inj.order >= 0 then
			children[#children + 1] = node
			anchored = true
		end
		local ok, nodes = pcall(inj.build, ctx)
		if not ok then
			warnOnce(inj.id, nodes)
		elseif type(nodes) == "table" then
			for _j, n in ipairs(nodes) do
				children[#children + 1] = n
				added = true
			end
		end
	end
	if not added then return nil end
	if not anchored then children[#children + 1] = node end
	-- the injectors' recipes are items themselves, never a Component layout (memory: recipe-not-component-layout)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

local function iconToggleButton(className, path, ...)
	local node = orig(className, path, ...)
	if path ~= M.AUTO_RENAME_ICON or #injectors == 0 then return node end
	local ok, wrapped = pcall(wrap, node)
	if not ok then
		warnOnce("button", wrapped)
		return node
	end
	return wrapped or node
end

--- Wraps makeIconToggleButton (and installs lmp_capture); true when installed (now or before), false when a base
--- function is missing.
function M.install()
	if not capture.install() then return false end
	if orig then return true end
	local fn = button_react_util.makeIconToggleButton
	if type(fn) ~= "function" then
		warnOnce("install", "makeIconToggleButton " .. type(fn))
		return false
	end
	orig = fn
	button_react_util.makeIconToggleButton = perf:wrap("toggle_button", iconToggleButton)
	return true
end

return M
