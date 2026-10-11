-- Line Manager Plus, shared groundwork: the Line Manager's commonParams, captured once for every feature
-- (plans/square_line_manager_plus/PLAN.md "Shared groundwork").
--
-- One wrapper of line_util.makeLineActionDescriptor (base line_util.tl:1023), which every manager mode calls with
-- the manager window's commonParams (a useRefLazy table, one per manager window: manager_window.tl:6255). The latest
-- table that has a lineManagerStateRef is kept; anything else passes through unchanged. Precedent:
-- zhenya_auto_assign_terminals gui/aat_eow.script.lua:625-629.
--
-- The base function is a module table field looked up per call by manager_window.tl, and ug_require caches modules by
-- resolved path, so "::/gui/line_vehicle_mgmt/line_util.tl" here is the table manager_window uses. install() reads the
-- current function at install time, not at load, so other mods' wrappers (Auto Assign Terminals) stay in the chain.
-- Installing twice (several features call install()) wraps once.
--
-- SQPERF section "descriptor" (the wrapper, the base function included), as before in undo.lua.
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"

local PREFIX = "[LineManagerPlus] capture: "

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local M = {}

local current -- latest commonParams of a line manager window
local orig -- the previous makeLineActionDescriptor, set by install()

local function descriptor(commonParams, ...)
	local ok, err = pcall(function()
		if type(commonParams) == "table" and commonParams.lineManagerStateRef then current = commonParams end
	end)
	if not ok then warnOnce("descriptor", err) end
	return orig(commonParams, ...)
end

--- Wraps makeLineActionDescriptor; true when installed (now or before), false when the base function is missing.
function M.install()
	if orig then return true end
	local fn = line_util.makeLineActionDescriptor
	if type(fn) ~= "function" then
		warnOnce("install", "makeLineActionDescriptor " .. type(fn))
		return false
	end
	orig = fn
	line_util.makeLineActionDescriptor = perf:wrap("descriptor", descriptor)
	return true
end

--- The latest commonParams, or nil before a line manager window was opened.
function M.params()
	return current
end

--- true when the react state or ref `s` belongs to a recipe that has unmounted (s:hasExpired(), as the base checks
--- before reading, engine_react_util.tl:146). The captured commonParams outlive their manager window: when the
--- window closes and another opens, our buttons render and step before the new window's descriptor call replaces
--- them. :old() on such a state returns nil but the engine prints "Calling Old() on expired ReactStateWrap returns
--- nil" plus a stack traceback to stdout.txt every time (docs/findings.md "Expired react states"), so check first.
--- A value without hasExpired (a plain table) counts as live.
function M.expired(s)
	if s == nil then return false end
	local f = s.hasExpired
	return f ~= nil and f(s) == true
end

--- The edited line of p (default: the captured params): commonParams.lineState:old().entityAndRevision.entity
--- (lineState = the editor's reactLineState, manager_window.tl:6636), or nil (also when that window has closed).
function M.editedLine(p)
	p = p or current
	local state = p and p.lineState
	if state == nil or M.expired(state) then return nil end
	local ls = state:old()
	return ls and ls.entityAndRevision and ls.entityAndRevision.entity or nil
end

--- Number of lines selected in the line list (0 without params).
function M.selectedLineCount(p)
	p = p or current
	local st = p and p.lineManagerStateRef and p.lineManagerStateRef:get()
	return st and st.lineListEntitiesSelected and #st.lineListEntitiesSelected or 0
end

--- Entities of the vehicles selected in the vehicle list ({} without params), as manager_window.tl:62-69
--- getSelectedVehicleEntities.
function M.selectedVehicles(p)
	p = p or current
	local out = {}
	local st = p and p.vehicleManagerStateRef and p.vehicleManagerStateRef:get()
	local sel = st and st.vehicleListEntitiesSelected
	if type(sel) ~= "table" then return out end
	for _i, ear in ipairs(sel) do
		if ear and ear.entity ~= nil then out[#out + 1] = ear.entity end
	end
	return out
end

--- After a command changed the edited line's stops (undo, redo, reverse), the editor's mode can still hold a path
--- index: {"SEGMENT", n} (insert after via n), MOVE_STOP / MOVE_WAYPOINT. That index can point past the end of a
--- shorter path or at another stop, and the next click crashes the base (addWaypoint: table.insert(path, n + 1, ...)
--- "position out of bounds", manager_window.tl:6954-6961). {"SEGMENT", nil} means "at the end" and is valid for any
--- path; the base uses it after a move (:6866). Set twice: switchLVMMode stores the old mode as "previous"
--- (:6068-6080), which switchToPrevLVMMode (:6082-6091) would restore, so the second call makes the stale index
--- unreachable. Nothing happens in the MAIN mode. Never throws (logged once).
function M.resetEditorMode(p)
	local ok, err = pcall(function()
		local mode = p.getModeState and p.getModeState()
		if not mode or mode[1] == "MAIN" or not p.switchMode then return end
		p.switchMode({ "SEGMENT", nil })
		p.switchMode({ "SEGMENT", nil })
	end)
	if not ok then warnOnce("mode", err) end
end

return M
