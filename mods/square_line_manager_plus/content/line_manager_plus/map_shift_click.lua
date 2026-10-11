-- Line Manager Plus, feature "Map: Shift-click a line opens the Line Manager" (moved here from Passenger
-- Destinations rev 5 before that was uploaded, 2026-10-11; in game behaviour verified there the same day). GUI only:
-- reads the game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace) through install() below.
--
-- Shift-click (Shift = input action IA_PRECISION_MODE, as zhenya mods, UI Overhaul and Passenger Destinations read it)
--   * on one of the player's lines (PLAYER_OWNED.player == api.engine.util.getPlayer()) opens the Line Manager on it;
--   * with a line window open, on anything that opens no window (water, ground: view_manager_util.wouldCreateView nil,
--     or the selector's onSelectNothing) opens it on the newest open line window's line. The line window draws its
--     line unselectable (base entity_window/line/line.tl LineViewer selectable = false), so a click on the drawn line
--     lands on what is under it.
-- The call is the line window's own "Manage Line" button (base entity_window/line/line.tl:140-149; the button exists
-- only for the player's own lines): react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = line }).
-- Only while the top tool is the plain map / an entity window (EntityDetailsTool, entity_window/view_manager.tl:340;
-- the map's default tool is the same tool with key "__pinned__") or Passenger Destinations' tool
-- ("SquarePassengerDestinations", pushed while its Shift hover arrows show: a Shift-click on empty map must still work
-- there). Never in the Line Manager, construction or any other tool. Everything else selects as usual.
--
-- Hook: base selector_react_util.makeDefaultSelector (selector_react_util.tl:88-104) builds the map's Selector with
-- builtin.Selector from the shared builtin.lua table (selector_react_util.tl:100), and every default selector action
-- calls it through a field lookup (selector_react_util.tl:231, 347). The field is wrapped; for the duration of each
-- call builtin.Selector is swapped for a function that wraps the Selector's onSelect / onSelectNothing (in a copy of
-- its params) and calls the real one. Afterwards builtin.Selector is set back to exactly the function we replaced,
-- also when the call fails.
--
-- Chain safety: Passenger Destinations wraps the same field (its Shift hover proxy ref) at its own load; either order
-- works because each wraps whatever the field holds when it installs. Guard flag on the module table:
-- `squareLmpShiftClick` (Passenger Destinations uses `squarePaxDestShift`). Clearing Passenger Destinations' Shift
-- hover arrows when the Line Manager opens is Passenger Destinations' job (its entry point pops its Shift entry once
-- another tool is on top), so this module never touches it.
--
-- Open line windows: lmp_line.script.lua (react-plugin ::LineEowExtensionPoint, lmp_line.res.lua) calls lineOpened /
-- lineClosed on mount / unmount. It is registered whatever the setting, and only keeps a list.
--
-- SQPERF section "map_click": the Shift-click check (only on clicks).

local PREFIX = "[LineManagerPlus] map shift click: "

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

local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local M = {}

M.SHIFT_ACTION = "IA_PRECISION_MODE"
M.GUARD = "squareLmpShiftClick"
-- top tools in which a Shift-click acts (see the header)
M.TOOLS = { EntityDetailsTool = true, SquarePassengerDestinations = true }
M.SRU = "::/gui/main/selector_react_util.tl"

-- line windows open, oldest first: a Shift-click on empty map manages the newest
local openLines = {}

function M.lineOpened(line)
	if type(line) == "number" then openLines[#openLines + 1] = line end
end

function M.lineClosed(line)
	for i = #openLines, 1, -1 do
		if openLines[i] == line then
			table.remove(openLines, i)
			return
		end
	end
end

function M.openLines()
	return openLines
end

local function shiftHeld()
	local ok, on = pcall(api.gui.inputAction.modifierOnlyActionIsActive, M.SHIFT_ACTION)
	return ok and on == true
end

local function toolAllowed()
	local globals = ug_require "::/gui/main/game_react_globals.tl"
	local tsApi = globals.getDefaultToolStackApi()
	if tsApi == nil or tsApi.getActiveTool == nil then return false end
	local ok, tool = pcall(tsApi.getActiveTool)
	return ok and type(tool) == "table" and M.TOOLS[tool.name] == true
end

local function playerLine(line)
	if type(line) ~= "number" or line < 0 then return false end
	if api.engine.getComponent(line, api.type.ComponentType.LINE) == nil then return false end
	local owned = api.engine.getComponent(line, api.type.ComponentType.PLAYER_OWNED)
	local okP, player = pcall(api.engine.util.getPlayer)
	return owned ~= nil and okP and owned.player == player
end

--- The line a Shift-click on `raw` (-1: nothing) manages, or nil: the clicked line if it is one of the player's;
--- else, when the click hit nothing that opens a window, the newest open line window's line (if the player's).
function M.targetLine(raw)
	local view = nil
	if type(raw) == "number" and raw >= 0 then
		local vmu = ug_require "::/gui/entity_window/view_manager_util.tl"
		local ok, e = pcall(vmu.wouldCreateView, raw)
		if ok and type(e) == "number" and e >= 0 then view = e end
	end
	if view ~= nil then
		return playerLine(view) and view or nil
	end
	local newest = openLines[#openLines]
	return playerLine(newest) and newest or nil
end

--- A click on `raw`: true when it was a Shift-click that opened the Line Manager (the click is then consumed).
local function click(raw)
	if not shiftHeld() or not toolAllowed() then return false end
	local line = M.targetLine(raw)
	if line == nil then return false end
	say("open the Line Manager for line " .. tostring(line) .. " (clicked " .. tostring(raw) .. ")")
	local react = ug_require "::/gui/main/react.lua"
	react.fireEvent(nil, "openVehicleManager", { openWithLineEntity = line })
	return true
end
M.click = perf:wrap("map_click", click)

local function tryClick(raw)
	local ok, handled = pcall(M.click, raw)
	if not ok then
		warnOnce("click", handled)
		return false
	end
	return handled == true
end

--- A copy of the Selector params with onSelect / onSelectNothing wrapped (the others unchanged).
function M.wrapSelectorParams(params)
	if type(params) ~= "table" then return params end
	local copy = {}
	for k, v in pairs(params) do copy[k] = v end
	local onSelect, onNothing = params.onSelect, params.onSelectNothing
	if type(onSelect) == "function" then
		copy.onSelect = function(entity, ...)
			if tryClick(entity) then return true end
			return onSelect(entity, ...)
		end
	end
	if type(onNothing) == "function" then
		copy.onSelectNothing = function(...)
			if tryClick(-1) then return true end
			return onNothing(...)
		end
	end
	return copy
end

local installed = false

--- Wraps selector_react_util.makeDefaultSelector (see the header); true when installed (now or before). Never errors.
function M.install(_replacementApi, _params)
	if installed then return true end
	local ok, err = pcall(function()
		local sru = ug_require(M.SRU)
		local builtin = ug_require "::/gui/main/builtin.lua"
		if type(sru) ~= "table" or type(builtin) ~= "table" then
			warnOnce("install", "selector_react_util or builtin missing; not installed")
			return
		end
		if sru[M.GUARD] then
			installed = true
			return
		end
		local prev = sru.makeDefaultSelector
		if type(prev) ~= "function" then
			warnOnce("install", "selector_react_util.makeDefaultSelector is " .. type(prev) .. "; not installed")
			return
		end
		-- restores builtin.Selector to what we replaced, then returns prev's results or raises its error
		local function finish(real, okPrev, ...)
			builtin.Selector = real
			if not okPrev then error((...), 0) end
			return ...
		end
		sru[M.GUARD] = true
		sru.makeDefaultSelector = function(...)
			local real = builtin.Selector
			if type(real) ~= "function" then return prev(...) end
			builtin.Selector = function(params)
				local okW, wrapped = pcall(M.wrapSelectorParams, params)
				if not okW then
					warnOnce("selector", wrapped)
					wrapped = params
				end
				return real(wrapped)
			end
			return finish(real, pcall(prev, ...))
		end
		installed = true
		say("installed")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return installed
end

return M
