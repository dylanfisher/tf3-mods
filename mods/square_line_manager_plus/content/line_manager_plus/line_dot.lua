-- Line Manager Plus, feature "Line stats on the colour dot" (PLAN.md feature 3): in the Line Manager's line list,
-- hovering a line's colour dot shows the line's vehicles by model and its Capacity, Utilization, Frequency and Rate
-- below the dot's vanilla tooltip ("Open Line Window"). The rest of the row is untouched. GUI only: reads the game
-- state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace) through install() below.
--
-- Where the dot comes from: LineAndDepotListEntry (base manager_window.tl:1957, the line list row, file-local) calls
-- line_react_util.ColorWidget{ tooltip = _("Open Line Window"), entity = entity, onClick = ... } (manager_window.tl:
-- 2154-2164, lines only: depot rows have no dot). ColorWidget (line_react_util.tl:271-306) puts param.tooltip on the
-- dot and on its Button as meta.tooltip, a plain string (base tealdef/scripts/builtin.d.tl:637; base writes
-- multi-line tooltips with "\n", e.g. gui/main/cargo_react_util.tl:147).
--
-- Hook: the MODULE FIELD line_react_util.ColorWidget is wrapped with a plain function (manager_window.tl looks it up
-- per call). Not ReplaceRecipe: that has one slot per recipe and would also hit the town window, the statistics, UI
-- Overhaul's cards and the vehicle row icon (line_react_util.tl:157). The wrapper only acts when
--   * it gets one table argument (the call form at manager_window.tl:2154; a call with a ref passes through),
--   * that has an onClick and a numeric entity, and
--   * the recipe rendering is LineAndDepotListEntry (react.getCurrentRecipeName, react.lua:648).
-- Then it returns SquareLmpLineDot{ prev, param } instead: a BoxLayout around prev(param) whose mouse listener
-- (react.onMouseEvent Entered / Exited, returning false so the dot's button still gets every event, as
-- LineAndDepotListEntry does at manager_window.tl:1978-1993) keeps a hovered flag. Only while hovered is the param
-- copied with the stats appended to its tooltip, so the stats are built for the one hovered dot, never for every row
-- (lmp_stats.lua, 1 s cache per line). A hovered entity that is not a line (or anything failing) leaves the param
-- untouched. Every other call goes straight to prev(...). The extra BoxLayout keeps R::ColorWidget in the tree, and
-- every base rule that styles the dot is a descendant selector (line_vehicle_mgmt.css.lua:304-520,
-- line_react_util.css.lua:12-15), so the dot looks the same.
--
-- Chain safety: install() reads the current field (another mod's wrapper stays in the chain). Our field holds a plain
-- function, which react can't map back to the ColorWidget recipe; a later mod's ReplaceRecipe(line_react_util.
-- ColorWidget, ...) would then index the recipe registry with nil and fail. So install() also wraps the shared
-- replacement api (the same table goes to every react-replacement-config, bootstrap_game.tl:39-48) to hand such a
-- call the function we wrapped, which react does know. Look: the vanilla tooltip (a string can't be styled by a
-- scoped rule, the tooltip window isn't under our recipe), 0 stylesheet rules.
--
-- SQPERF section "dot_tooltip": building the hovered dot's tooltip text.

local PREFIX = "[LineManagerPlus] dot tooltip: "

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

local M = {}

M.CALLER = "LineAndDepotListEntry"
M.LRU = "::/gui/line_vehicle_mgmt/line_react_util.tl"

--- The param for a hovered dot: a copy of `param` whose tooltip has the line's stats lines appended, or `param`
--- itself (same table) when there is nothing to add (not a line any more, no lines). Errors propagate.
local function hoveredParam(param)
	local lines = stats.lines(param.entity)
	if type(lines) ~= "table" or #lines == 0 then return param end
	local copy = {}
	for k, v in pairs(param) do copy[k] = v end
	local base = param.tooltip
	local head = (type(base) == "string" and base ~= "") and (base .. "\n") or ""
	copy.tooltip = head .. table.concat(lines, "\n")
	return copy
end
M.hoveredParam = perf:wrap("dot_tooltip", hoveredParam)

local function isEnteredOrExited(evt)
	local T = api.gui.mouse.Event.Type
	if evt.type == T.Entered then return true end
	if evt.type == T.Exited then return false end
	return nil
end

-- the root is a BoxLayout, as every custom recipe's must be; prev(...) is the ColorWidget node itself (an item, never a
-- Component layout). p = { prev = the wrapped ColorWidget, param = the caller's param }
M.LineDot = react.RegisterRecipe("SquareLmpLineDot", function(p)
	local hovered = react.useState(false)
	react.onMouseEvent(function(evt)
		local ok, res = pcall(isEnteredOrExited, evt)
		if not ok then
			warnOnce("mouse", res)
		elseif res ~= nil and res ~= hovered:old() then
			hovered:set(res)
		end
		return false
	end)
	local param = p.param
	if hovered:old() then
		local ok, res = pcall(M.hoveredParam, param)
		if ok then param = res else warnOnce("stats", res) end
	end
	local ok, node = pcall(p.prev, param)
	if not ok then
		warnOnce("dot", node)
		node = p.prev(p.param)
	end
	return builtin.BoxLayout{ children = { node } }
end)

local prev -- the ColorWidget we wrapped, set by install()
local wrapper -- our function in line_react_util.ColorWidget

local function intercept(param)
	if type(param) ~= "table" or param.onClick == nil or type(param.entity) ~= "number" then return nil end
	if react.getCurrentRecipeName() ~= M.CALLER then return nil end
	return M.LineDot{ prev = prev, param = param }
end

local function colorWidget(...)
	if select("#", ...) == 1 then
		local ok, node = pcall(intercept, ...)
		if not ok then
			warnOnce("wrap", node)
		elseif node ~= nil then
			return node
		end
	end
	return prev(...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the recipe we wrapped instead (see the header)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if wrapper ~= nil and original == wrapper then original = prev end
		return replace(original, ...)
	end
end

--- Wraps line_react_util.ColorWidget; true when installed (now or before). Never errors.
function M.install(replacementApi)
	if prev then return true end
	local ok, err = pcall(function()
		local lru = ug_require(M.LRU)
		local fn = type(lru) == "table" and lru.ColorWidget or nil
		if type(fn) ~= "function" then
			warnOnce("install", "line_react_util.ColorWidget is " .. type(fn) .. "; dot left as is")
			return
		end
		prev = fn
		wrapper = colorWidget
		lru.ColorWidget = wrapper
		shimReplacementApi(replacementApi)
		say("installed")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev ~= nil
end

return M
