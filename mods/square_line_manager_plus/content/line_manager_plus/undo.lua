-- Line Manager Plus, feature "Line editor undo" (from Line Editor Undo, square_line_revert rev 4): undo and redo icon
-- buttons left of Auto-Rename ("A+") in the line manager. Each Undo click undoes one edit of the edited line's stops;
-- Shift+click reverts every edit since the line was opened. Redo re-applies undone states one at a time until the next
-- edit of your own. GUI only: no game script, nothing in the savegame. Installed by lmp.script.lua (doReplace) through
-- install() below, when the mod setting is On and Line Editor Undo isn't installing its own buttons. Original plan:
-- plans/square_line_revert/PLAN.md; technique proven in game by square_line_revert_probe (PROBE.md run 1).
--
-- Uses the shared groundwork (installed by install()):
-- * lmp_capture.lua: the manager's commonParams (wraps line_util.makeLineActionDescriptor once for every feature).
--   The edited line is commonParams.lineState:old().entityAndRevision.entity (capture.editedLine).
-- * lmp_rows.lua: an injector (order -100) puts our two button recipes left of the Auto-Rename icon (A+) inside
--   LinePanelActionButtons (wraps button_react_util.makeIconToggleButton once for every feature).
--
-- The editor commits every edit at once with makeLineUpdateCmd: each editor action calls reactLineCommit once
-- (manager_window.tl:6714-6992), which sends one command (engine_react_util.tl:24-53, makeCommand :6526-6561).
-- So polling the LINE component every step sees each edit as its own change: the undo history (core.observe)
-- records one entry per change. The history starts the first step the button is mounted with a new edited line,
-- before a click can reach the editor. A session = (commonParams table, line entity): a different line or a new
-- manager window starts a new one with a new history.

-- SQPERF (plans/sqperf/README.md, the shared instrument in lmp_perf.lua): all on the GUI thread, the view
-- computed for the buttons every step ("view": line read, history observe, tooltips; react onStep via
-- useStepState), the button renders ("button_render"), clicks ("click", including the undo/redo
-- command); the two wrapped base functions ("descriptor", "toggle_button") are now timed by
-- lmp_capture.lua / lmp_rows.lua. Calls over 16 ms are logged (at most one line per section per minute); with the
-- "Debug: performance log" mod setting On, a 30 s summary, and the trace lines (session start, each
-- recorded edit, the LoadMode check). Local counters only.
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local core = ug_require "square_line_manager_plus::/line_manager_plus/undo_core.lua"
local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
local rows = ug_require "square_line_manager_plus::/line_manager_plus/lmp_rows.lua"

-- base undo glyph (gui.zip: gui/node_editor/icons/undo@2x.tga, 48x48 greyscale mask like symbol_autorename@2x.tga);
-- the engine picks the @2x file for the plain path, as for AUTO_RENAME_ICON (manager_window.tl:6317)
local UNDO_ICON = "::/gui/node_editor/icons/undo.tga"
-- its neighbour in the same folder (gui.zip: gui/node_editor/icons/redo@2x.tga)
local REDO_ICON = "::/gui/node_editor/icons/redo.tga"
local PREFIX = "[LineManagerPlus] undo: "

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

-- Trace lines: only with the "Debug: performance log" setting On (the instrument's gate, re-read every 30 s).
local function trace(msg)
	if perf.on then say(msg) end
end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

-- State --------------------------------------------------------------------------------------------------------
local session -- { params, line = entity, history = core history (states[1] = line when opened), busy = text | nil }
local loggedLoadMode = false

local editedLine = capture.editedLine
local selectedCount = capture.selectedLineCount

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
		trace("loadMode type " .. type(s.loadMode) .. " value " .. tostring(s.loadMode))
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
	trace("session line " .. tostring(line) .. " stops " .. #snap.stops)
	return session
end

--- Records the live line in the session's history (a no-op when it equals the last entry or our own command).
--- Runs every step: core.observeLive compares the component with the newest state in place and only copies it
--- when it changed.
local function observe(s, comp)
	if core.observeLive(s.history, comp) then
		trace("edit " .. core.changeCount(s.history) .. " on line " .. tostring(s.line))
	end
end

-- View model for the button, refreshed every step ------------------------------------------------------------
local HIDDEN = { hidden = true }

--- core.diffSummary(a, b), remembered per slot ("undo" / "redo") for the last pair of states. History states are
--- never changed once stored, so the same pair gives the same text; the tooltips ask for it every step.
local diffMemo = {}
local function cachedDiff(slot, a, b)
	local m = diffMemo[slot]
	if m and m.a == a and m.b == b then return m.text end
	local text = core.diffSummary(a, b)
	diffMemo[slot] = { a = a, b = b, text = text }
	return text
end

local function undoView(h)
	if #h.states <= 1 then
		return { enabled = false, tooltip = _("Undo: no changes since you opened this line") }
	end
	local top = h.states[#h.states]
	local diff = cachedDiff("undo", h.states[#h.states - 1], top)
	local n = core.changeCount(h)
	return {
		enabled = true,
		tooltip = core.fill(n == 1 and _("Undo: {diff} (1 change since you opened this line). Shift+click: revert all.")
			or _("Undo: {diff} ({n} changes since you opened this line). Shift+click: revert all."), { diff = diff, n = n }),
	}
end

local function redoView(h)
	local target = core.redoTarget(h)
	if target == nil then
		return { enabled = false, tooltip = _("Redo: nothing to redo") }
	end
	-- what the redo applies: the current top state -> the redo target; "N more" = redo steps left after this one
	local diff = cachedDiff("redo", h.states[#h.states], target)
	return { enabled = true, tooltip = core.fill(_("Redo: {diff} ({n} more)"), { diff = diff, n = #h.redo - 1 }) }
end

--- { hidden } or { line, undo = { enabled, tooltip }, redo = { enabled, tooltip } }. Called once per step for
--- both buttons (stepView below); a repeat call is still a no-op for the history (observe ignores a repeat).
local function computeView()
	local params = capture.params()
	if not params or selectedCount(params) ~= 1 then return HIDDEN end
	local s = ensureSession(params)
	if not s then return HIDDEN end
	if isProtected(params, s.line) then return HIDDEN end
	local comp = readLine(s.line)
	if not comp then
		local gone = { enabled = false, tooltip = _("Line no longer exists") }
		return { line = s.line, undo = gone, redo = gone }
	end
	observe(s, comp)
	local h = s.history
	if h.expected ~= nil then
		-- s.busy holds the English key (LABELS), translated here
		local busy = { enabled = false, tooltip = _(s.busy or "Undoing...") } -- i18n: ignore
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

--- One view per step for both buttons: the Undo button's step computes it (and counts a generation), the Redo
--- button's step takes it when Undo computed a new one since Redo last looked, else computes its own. So the line
--- is read once per step, whatever order the two steps run in (at worst Redo shows the view one step late).
--- Cleared when the action row is built (iconToggleButton), so a new row never starts from an old window's view.
local shared = { view = nil, gen = 0, seen = 0 }

local function safeView()
	local tPerf = perf:start() -- SQPERF section "view" (failed calls count too)
	local ok, v = pcall(computeView)
	perf:stop("view", tPerf)
	if not ok then
		warnOnce("view", v)
		return HIDDEN
	end
	return v
end

local function stepView(which)
	if which == "undo" then
		local v = safeView()
		shared.view, shared.gen = v, shared.gen + 1
		return v
	end
	if shared.view ~= nil and shared.seen ~= shared.gen then
		shared.seen = shared.gen
		return shared.view
	end
	return safeView()
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

--- The editor's mode can hold a stale path index after our command: lmp_capture.resetEditorMode (shared with the
--- Reverse line action) moves it to {"SEGMENT", nil}.
local resetEditorMode = capture.resetEditorMode

local LABELS = {
	-- busy: tooltip text key (translated at use); done: log text only
	undo = { busy = "Undoing...", done = "undid one edit on" }, -- i18n: keys busy
	all = { busy = "Undoing...", done = "reverted" }, -- i18n: keys busy
	redo = { busy = "Redoing...", done = "redid one edit on" }, -- i18n: keys busy
}

--- kind = "undo" (one step), "all" (back to the state when the line was opened) or "redo" (one step forward).
--- Undo and redo share this path: missing-station check, editor-mode reset, `expected` in flight, and on a
--- refused command core.finishCommand restores both stacks.
local function send(kind)
	local params = capture.params()
	local s = session
	if not (s and params and s.params == params and editedLine(params) == s.line) then
		say(kind .. ": no session for the edited line")
		return
	end
	local comp = readLine(s.line)
	if not comp then
		feedback(params, _("Line Manager Plus: the line no longer exists."), true)
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
		feedback(params, #missing == 1
			and _("Line Manager Plus: 1 station of that line state no longer exists. Nothing was changed.")
			or core.fill(_("Line Manager Plus: {n} stations of that line state no longer exist. Nothing was changed."),
				{ n = #missing }), true)
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
				feedback(params, kind == "redo" and _("Line Manager Plus: the game refused the redo.")
					or _("Line Manager Plus: the game refused the undo."), true)
			end
		end)
		if not ok then warnOnce("callback", err) end
	end)
end

-- Button -------------------------------------------------------------------------------------------------------
--- One recipe for both buttons, so lmp.css.lua scopes its rules under a single recipe name (every
--- stylesheet rule counts toward the game's load-crash limit, docs/findings.md). Param `which` = "undo" or "redo"
--- picks the icon, the half of the view and the click action.
local function makeButtonRecipe(recipeName)
	-- SQPERF section "button_render" (both buttons; the recipe's own function, its first call includes the first view)
	return react.RegisterRecipe(recipeName, perf:wrap("button_render", function(p)
		local which = (p and p.which == "redo") and "redo" or "undo"
		local icon = which == "redo" and REDO_ICON or UNDO_ICON
		local state = engine_react_util.useStepState(function()
			return stepView(which)
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
				-- ToggleButton, since undo / redo are one-shot actions; lmp.css.lua gives it the unchecked-toggle
				-- look of its neighbours. meta.enabled as manager_hud_util.tl:281. No mouseTransparent on ImageView (crashes).
				builtin.Button{
					meta = { class = "vehicle-button, secondary", tooltip = b.tooltip, enabled = b.enabled },
					content = builtin.ImageView{
						path = icon,
						scaling = builtin.type.ImageViewScaling.AutoFit,
					},
					onClick = function()
						local tPerf = perf:start() -- SQPERF section "click" (failed clicks count too)
						local ok, err = pcall(function()
							if which == "redo" then
								send("redo")
							else
								send(shiftHeld() and "all" or "undo")
							end
						end)
						if not ok then
							warnOnce(which, err)
							feedback(capture.params(), which == "redo" and _("Line Manager Plus: redo failed (see log).")
								or _("Line Manager Plus: undo failed (see log)."), true)
						end
						perf:stop("click", tPerf)
					end,
				},
			},
		}
	end))
end

-- recipe name also used as the CSS scope in lmp.css.lua; UndoButton{ which = "undo" | "redo" }
local UndoButton = makeButtonRecipe("SquareLmpUndoButton")

-- Row injector -------------------------------------------------------------------------------------------------
--- lmp_rows injector: [Undo][Redo] left of A+. A new row starts from a fresh view (never an old window's).
local function buildButtons(_ctx)
	shared.view = nil
	return { UndoButton{ which = "undo" }, UndoButton{ which = "redo" } }
end

local installed = false

--- Installs the shared capture and button row and registers our buttons; true when installed (now or before),
--- false when a base function is missing. Errors pass to the caller (lmp.script.lua runs it in pcall).
local function install(_replacementApi)
	if installed then return true end
	if not rows.install() then return false end -- rows installs lmp_capture too
	rows.register({ id = "undo", order = -100, build = buildButtons })
	installed = true
	say("installed")
	return true
end

return {
	install = install,
	UndoButton = UndoButton,
}
