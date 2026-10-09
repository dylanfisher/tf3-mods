-- Line Editor Undo: undo and redo icon buttons left of Auto-Rename ("A+") in the line manager. Each Undo click undoes one
-- edit of the edited line's stops; Shift+click reverts every edit since the line was opened. Redo re-applies undone
-- states one at a time until the next edit of your own. GUI only: no game script, nothing in the savegame. Plan: plans/square_line_revert/PLAN.md. Technique proven in game by square_line_revert_probe
-- (PROBE.md run 1).
--
-- Two module-function wrappers, installed by doReplace (line_revert_replace.res.lua):
-- * line_util.makeLineActionDescriptor: captures the manager's commonParams (a useRefLazy table, one per manager
--   window: manager_window.tl:6255). The edited line is commonParams.lineState:old().entityAndRevision.entity
--   (lineState = the editor's reactLineState, manager_window.tl:6636). Precedent:
--   zhenya_auto_assign_terminals gui/aat_eow.script.lua:625-629.
-- * button_react_util.makeIconToggleButton: when it builds the Auto-Rename icon (manager_window.tl:3520 with
--   iconPaths.abAutoRename, :6317) inside LinePanelActionButtons, our two button recipes are put to its left.
--   Precedent for wrapping a button builder: aat_eow.script.lua:640-661.
-- Both are module table fields looked up per call by manager_window.tl, and ug_require caches modules by resolved
-- path, so the "::/" paths below give the same tables manager_window uses.
--
-- The editor commits every edit at once with makeLineUpdateCmd: each editor action calls reactLineCommit once
-- (manager_window.tl:6714-6992), which sends one command (engine_react_util.tl:24-53, makeCommand :6526-6561).
-- So polling the LINE component every step sees each edit as its own change: the undo history (core.observe)
-- records one entry per change. The history starts the first step the button is mounted with a new edited line,
-- before a click can reach the editor. A session = (commonParams table, line entity): a different line or a new
-- manager window starts a new one with a new history.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local core = ug_require "square_line_revert::/line_revert/line_revert_core.lua"

local AUTO_RENAME_ICON = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"
-- base undo glyph (gui.zip: gui/node_editor/icons/undo@2x.tga, 48x48 greyscale mask like symbol_autorename@2x.tga);
-- the engine picks the @2x file for the plain path, as for AUTO_RENAME_ICON (manager_window.tl:6317)
local UNDO_ICON = "::/gui/node_editor/icons/undo.tga"
-- its neighbour in the same folder (gui.zip: gui/node_editor/icons/redo@2x.tga)
local REDO_ICON = "::/gui/node_editor/icons/redo.tga"
local RECIPE_ACTION_BUTTONS = "LinePanelActionButtons"
local PREFIX = "[LineRevert] "

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

-- State --------------------------------------------------------------------------------------------------------
local managerParams -- latest commonParams seen by makeLineActionDescriptor
local session -- { params, line = entity, history = core history (states[1] = line when opened), busy = text | nil }
local loggedLoadMode = false

local function editedLine(params)
	local ls = params and params.lineState and params.lineState:old()
	return ls and ls.entityAndRevision and ls.entityAndRevision.entity or nil
end

local function selectedCount(params)
	local st = params and params.lineManagerStateRef and params.lineManagerStateRef:get()
	return st and st.lineListEntitiesSelected and #st.lineListEntitiesSelected or 0
end

local function isProtected(params, line)
	-- as manager_window.tl:744 asks before an edit
	local filters = params.gameCtx and params.gameCtx.filters and params.gameCtx.filters:get()
	local protected = filters and filters.protectedEntities
	return protected ~= nil and line_util.isStopProtected(line, nil, protected)
end

local function readLine(line)
	if not (line and api.engine.entityExists(line)) then return nil end
	return api.engine.getComponent(line, api.type.ComponentType.LINE)
end

local function logLoadModeOnce(comp)
	-- in-game check (TESTING.md): what a LoadMode value is, for core's equality
	if loggedLoadMode then return end
	local s = comp.stops and #comp.stops > 0 and comp.stops[1]
	if s then
		loggedLoadMode = true
		say("loadMode type " .. type(s.loadMode) .. " value " .. tostring(s.loadMode))
	end
end

--- Starts a session when the edited line changed; returns the current one (or nil when no line is edited).
local function ensureSession(params)
	local line = editedLine(params)
	if not line then return nil end
	if session and session.params == params and session.line == line then return session end
	local comp = readLine(line)
	if not comp then return nil end
	logLoadModeOnce(comp)
	local snap = core.snapshot(comp)
	session = { params = params, line = line, history = core.newHistory(snap) }
	say("session line " .. tostring(line) .. " stops " .. #snap.stops)
	return session
end

--- Records the live line in the session's history (a no-op when it equals the last entry or our own command).
local function observe(s, comp)
	if core.observe(s.history, core.snapshot(comp)) then
		say("edit " .. core.changeCount(s.history) .. " on line " .. tostring(s.line))
	end
end

-- View model for the button, refreshed every step ------------------------------------------------------------
local HIDDEN = { hidden = true }
local SHIFT_HINT = " Shift+click: revert all."

local function plural(n, one, many)
	return tostring(n) .. " " .. (n == 1 and one or many)
end

local function undoView(h)
	if #h.states <= 1 then
		return { enabled = false, tooltip = "Undo: no changes since you opened this line" }
	end
	local top = h.states[#h.states]
	local diff = core.diffSummary(h.states[#h.states - 1], top)
	local n = core.changeCount(h)
	return {
		enabled = true,
		tooltip = "Undo: " .. diff .. " (" .. plural(n, "change", "changes") .. " since you opened this line)."
			.. SHIFT_HINT,
	}
end

local function redoView(h)
	local target = core.redoTarget(h)
	if target == nil then
		return { enabled = false, tooltip = "Redo: nothing to redo" }
	end
	-- what the redo applies: the current top state -> the redo target; "N more" = redo steps left after this one
	local diff = core.diffSummary(h.states[#h.states], target)
	return { enabled = true, tooltip = "Redo: " .. diff .. " (" .. tostring(#h.redo - 1) .. " more)" }
end

--- { hidden } or { line, undo = { enabled, tooltip }, redo = { enabled, tooltip } }. Both buttons call it every
--- step; the second call in a step is a no-op for the history (observe ignores a repeat).
local function computeView()
	local params = managerParams
	if not params or selectedCount(params) ~= 1 then return HIDDEN end
	local s = ensureSession(params)
	if not s then return HIDDEN end
	if isProtected(params, s.line) then return HIDDEN end
	local comp = readLine(s.line)
	if not comp then
		local gone = { enabled = false, tooltip = "Line no longer exists" }
		return { line = s.line, undo = gone, redo = gone }
	end
	observe(s, comp)
	local h = s.history
	if h.expected ~= nil then
		local busy = { enabled = false, tooltip = s.busy or "Undoing..." }
		return { line = s.line, undo = busy, redo = busy }
	end
	return { line = s.line, undo = undoView(h), redo = redoView(h) }
end

local function sameButton(a, b)
	if a == nil or b == nil then return a == b end
	return a.enabled == b.enabled and a.tooltip == b.tooltip
end

local function sameView(a, b)
	return a.hidden == b.hidden and a.line == b.line and sameButton(a.undo, b.undo) and sameButton(a.redo, b.redo)
end

-- Undo / redo ------------------------------------------------------------------------------------------------------
local function feedback(params, message, isError)
	-- commonParams.addFeedback(message, mode, dialogData, id): manager_window.d.tl:133-138; modes "Error" or nil
	-- as manager_window.tl:2283 and :5305 use it (also from a command callback, :5301-5305).
	say(message)
	local ok, err = pcall(function()
		if params and params.addFeedback then
			params.addFeedback(message, isError and "Error" or nil, nil, nil)
		end
	end)
	if not ok then warnOnce("addFeedback", err) end
end

local function stationCount(group)
	if not api.engine.entityExists(group) then return nil end
	local sg = api.engine.getComponent(group, api.type.ComponentType.STATION_GROUP)
	if not sg or not sg.stations then return nil end
	return #sg.stations
end

--- Shift (the "precision mode" modifier) held: the same query zhenya_auto_assign_terminals makes from a GUI click
--- handler (aat_eow.script.lua:670) and the base makes from GUI input handlers (construction_react_util.tl:1916,
--- :3637; manager_window.tl:537). api.gui is the GUI-thread API (api/tealdef/api/gui.d.tl:358). Any failure
--- counts as "not held", so a plain undo is the fallback.
local function shiftHeld()
	local ok, held = pcall(function()
		return api.gui and api.gui.inputAction and api.gui.inputAction.modifierOnlyActionIsActive("IA_PRECISION_MODE")
	end)
	if not ok then
		warnOnce("shift", held)
		return false
	end
	return held == true
end

--- The editor's mode can hold a path index: {"SEGMENT", n} (insert after via n), MOVE_STOP / MOVE_WAYPOINT.
--- After an undo that index can lie past the end of the shorter path, and the next click crashes the base
--- (addWaypoint: table.insert(path, n + 1, ...) "position out of bounds", manager_window.tl:6954-6961).
--- {"SEGMENT", nil} means "at the end" and is valid for any path; the base uses it after a move (:6866).
--- Set twice: switchLVMMode stores the old mode as "previous" (:6068-6080), which switchToPrevLVMMode
--- (:6082-6091) would restore, so the second call makes the stale index unreachable.
local function resetEditorMode(params)
	local ok, err = pcall(function()
		local mode = params.getModeState and params.getModeState()
		if not mode or mode[1] == "MAIN" or not params.switchMode then return end
		params.switchMode({ "SEGMENT", nil })
		params.switchMode({ "SEGMENT", nil })
	end)
	if not ok then warnOnce("mode", err) end
end

local LABELS = {
	undo = { busy = "Undoing...", done = "undid one edit on", refused = "undo" },
	all = { busy = "Undoing...", done = "reverted", refused = "undo" },
	redo = { busy = "Redoing...", done = "redid one edit on", refused = "redo" },
}

--- kind = "undo" (one step), "all" (back to the state when the line was opened) or "redo" (one step forward).
--- Undo and redo share this path: missing-station check, editor-mode reset, `expected` in flight, and on a
--- refused command core.finishCommand restores both stacks.
local function send(kind)
	local params = managerParams
	local s = session
	if not (s and params and s.params == params and editedLine(params) == s.line) then
		say(kind .. ": no session for the edited line")
		return
	end
	local comp = readLine(s.line)
	if not comp then
		feedback(params, "Line Editor Undo: the line no longer exists.", true)
		return
	end
	local h = s.history
	-- record an edit that landed after the last step, so the click acts on the edit the user just made (and an
	-- edit clears the redo stack before a redo is taken from it)
	observe(s, comp)
	if h.expected ~= nil then
		say(kind .. ": previous command still in flight")
		return
	end
	local target
	if kind == "redo" then
		target = core.redoTarget(h)
	else
		target = core.undoTarget(h, kind == "all")
	end
	if not target then return end
	local missing = core.missingStops(target, stationCount)
	if #missing > 0 then
		feedback(params, "Line Editor Undo: " .. #missing .. (#missing == 1 and " station" or " stations")
			.. " of that line state no longer exist. Nothing was changed.", true)
		return
	end
	local built = core.build(target, api.type)
	local live = core.snapshot(comp)
	local _target, token
	if kind == "redo" then
		_target, token = core.beginRedo(h, live)
	else
		_target, token = core.beginUndo(h, live, kind == "all")
	end
	local label = LABELS[kind]
	s.busy = label.busy
	local line = s.line
	resetEditorMode(params)
	local count = #target.stops
	-- same command and callback shape as the editor's commit (manager_window.tl:6555-6561, "update cannot change entity id")
	api.cmd.sendCommand(api.cmd.makeLineUpdateCmd(line, built), function(_result, success)
		local ok, err = pcall(function()
			core.finishCommand(h, token, success)
			if success then
				say(label.done .. " line " .. tostring(line) .. " (" .. count .. " stops)")
			else
				feedback(params, "Line Editor Undo: the game refused the " .. label.refused .. ".", true)
			end
		end)
		if not ok then warnOnce("callback", err) end
	end)
end

-- Button -------------------------------------------------------------------------------------------------------
--- One recipe per button, both built here so they share the look: line_revert.css.lua scopes the same rules under
--- both recipe names. `which` = "undo" or "redo" picks the half of the view and the click action.
local function makeButtonRecipe(recipeName, which, icon)
	return react.RegisterRecipe(recipeName, function(_p)
		local state = engine_react_util.useStepState(function()
			local ok, v = pcall(computeView)
			if not ok then
				warnOnce("view", v)
				return HIDDEN
			end
			return v
		end, nil, sameView)
		local v = state:old() or HIDDEN
		local b = v[which]
		if v.hidden or b == nil then
			-- a recipe must return a layout (memory: react-recipe-must-return-layout)
			return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = {} }
		end
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				-- same shape as button_react_util.makeIconButton (button_react_util.tl:31-55): a Button whose content is
				-- an AutoFit ImageView, with the class of the A+ button (manager_window.tl:3520-3521). A Button, not a
				-- ToggleButton, since undo / redo are one-shot actions; line_revert.css.lua gives it the unchecked-toggle
				-- look of its neighbours. meta.enabled as manager_hud_util.tl:281. No mouseTransparent on ImageView (crashes).
				builtin.Button{
					meta = { class = "vehicle-button, secondary", tooltip = b.tooltip, enabled = b.enabled },
					content = builtin.ImageView{
						path = icon,
						scaling = builtin.type.ImageViewScaling.AutoFit,
					},
					onClick = function()
						local ok, err = pcall(function()
							if which == "redo" then
								send("redo")
							else
								send(shiftHeld() and "all" or "undo")
							end
						end)
						if not ok then
							warnOnce(which, err)
							feedback(managerParams, "Line Editor Undo: " .. which .. " failed (see log).", true)
						end
					end,
				},
			},
		}
	end)
end

-- recipe names also used as CSS scopes in line_revert.css.lua
local LineRevertButton = makeButtonRecipe("SquareLineRevertButton", "undo", UNDO_ICON)
local LineRedoButton = makeButtonRecipe("SquareLineRedoButton", "redo", REDO_ICON)

-- Wrappers -----------------------------------------------------------------------------------------------------
local origDescriptor -- set in doReplace
local function lineActionDescriptor(commonParams, ...)
	local ok, err = pcall(function()
		if type(commonParams) == "table" and commonParams.lineManagerStateRef then managerParams = commonParams end
	end)
	if not ok then warnOnce("descriptor", err) end
	return origDescriptor(commonParams, ...)
end

local origToggle -- set in doReplace
local function iconToggleButton(className, path, ...)
	local node = origToggle(className, path, ...)
	if path ~= AUTO_RENAME_ICON then return node end
	local ok, wrapped = pcall(function()
		if react.getCurrentRecipeName() ~= RECIPE_ACTION_BUTTONS or not managerParams then return nil end
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				-- the recipes are the items themselves, never a Component layout (memory: recipe-not-component-layout)
				LineRevertButton{},
				LineRedoButton{},
				node,
			},
		}
	end)
	if not ok then
		warnOnce("button", wrapped)
		return node
	end
	return wrapped or node
end

local function doReplace(_replacementApi)
	if origToggle or origDescriptor then return end -- already installed
	-- read the current functions now, not at load, so wrappers of other mods (Auto Assign Terminals) stay in the chain
	local toggle, descriptor = button_react_util.makeIconToggleButton, line_util.makeLineActionDescriptor
	if type(toggle) ~= "function" or type(descriptor) ~= "function" then
		warnOnce("install", "makeIconToggleButton " .. type(toggle) .. ", makeLineActionDescriptor " .. type(descriptor))
		return
	end
	origToggle, origDescriptor = toggle, descriptor
	button_react_util.makeIconToggleButton = iconToggleButton
	line_util.makeLineActionDescriptor = lineActionDescriptor
	say("installed")
end

-- .script.lua resources expose their exports through data(), not a return value (memory: script-lua-exports-via-data)
function data()
	return {
		doReplace = doReplace,
		LineRevertButton = LineRevertButton,
		LineRedoButton = LineRedoButton,
	}
end
