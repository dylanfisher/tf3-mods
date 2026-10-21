-- Line Manager Plus, feature "Line actions: Duplicate and Reverse line" (PLAN.md feature 4, setting line_actions):
-- three entries in the "Line actions" menu (lmp_actions.lua, the toolbar button right of A+). Installed by
-- lmp.script.lua (doReplace) through install() below. GUI code only; the result is ordinary vanilla line data.
--
-- Duplicate line: one makeLineCreateCmd (api/tealdef/api/cmd.d.tl:760-767), as the editor creates a line
-- (manager_window.tl:6526-6553): the copy has the same stops with every per-stop setting (terminal and alternatives,
-- load mode, waiting times, cargo config, waypoints), the line's customFilters and reservationPriority, all through
-- undo_core.snapshot / build. Name "<name> (copy)" ("<name> (copy N)" while that is taken; translated format strings
-- with a {name} placeholder; stored like the editor's "Line N", line_util.tl:66-80). New colour as for a new line
-- (line_util.makeLineColor, user decision D3). Vehicles stay where they are; the copy starts empty. On success the
-- copy is selected in the Line Manager through commonParams.selectLine (the map's "select line" click,
-- manager_window.tl:6716-6745: deselects all, then selects and scrolls to it) when that manager is still the open one.
--
-- Reverse line: one makeLineUpdateCmd on the edited line (manager_window.tl:6555-6561): line_ops_core.reverse keeps
-- stop 1 first and reverses the rest (D4), moving each segment's waypoints with it; then the engine picks terminals
-- for the new direction (lineSystem.getBestLineAssignment(line, comp, true), api/engine/system.d.tl:48-52, as
-- line_util.autoAssignTerminals does; D5), keeping the player's terminal where it has no answer. A reverse that would
-- change nothing sends no command. Undo: the undo feature polls the LINE component and records every change as one
-- edit, so the reverse is one Undo step ("stops reordered") with no extra code here; with the undo feature Off the
-- reverse still works. The editor's mode is reset first (lmp_capture.resetEditorMode), as undo does.
--
-- Duplicate + reverse line (orders: Match line rate 50, Duplicate 100, Reverse 200, this 300): one makeLineCreateCmd
-- with the reversed stops (M.reversed on the snapshot: stop 1 first, waypoints moved, engine terminals for the new
-- direction asked of the original line), named and coloured as Duplicate, selected on success. Guards of both
-- (blockReason + the 3-stop reason; a mirror-image route sends nothing). The original line is untouched.
--
-- Guards (each entry's view, shown as a disabled entry with the reason as tooltip): fewer than 2 stops, a stop whose
-- station is gone, a command of ours still in flight (max BUSY_US). lmp_actions shows the menu only for exactly one
-- selected, edited, unprotected line. Every command is atomic: the game applies the whole line or refuses it
-- (callback success false → a translated feedback line), so a line is never half edited.
--
-- Save safety: nothing of ours is stored. A duplicated or reversed line is plain vanilla data that stays valid without
-- the mod. Commands are sent from the menu click (GUI thread, as undo's), never from a build-proposal event.

local core = ug_require "square_line_manager_plus::/line_manager_plus/line_ops_core.lua"
local undo_core = ug_require "square_line_manager_plus::/line_manager_plus/undo_core.lua"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
local actions = ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua"

local PREFIX = "[LineManagerPlus] line ops: "

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

-- Duplicate / reverse icons of the manager's vehicle toolbar (manager_window.tl:6309, :6312, iconPaths.abReverse /
-- abDuplicate; gui.zip gui/line_vehicle_mgmt/icons/*@2x.tga, 48x48 masks)
local ICON_DUPLICATE = "::/gui/line_vehicle_mgmt/icons/symbol_square_copy.tga"
local ICON_REVERSE = "::/gui/line_vehicle_mgmt/icons/symbol_arrow_reverse.tga"

local M = {}

M.BUSY_US = 10 * 1000000 -- a command without callback after 10 s no longer blocks the entries

-- State: the command in flight ({ since = Clock us, kind }) or nil
local busy = nil
local clock

local function now()
	-- api.type.Clock: wall clock in microseconds, safe on every thread (docs/findings.md "Timers and threads")
	if not clock then clock = api.type.Clock.new() end
	return clock:getTime()
end

local function isBusy()
	if busy == nil then return false end
	if now() - busy.since > M.BUSY_US then
		warnOnce("timeout", busy.kind .. ": no callback after " .. (M.BUSY_US / 1000000) .. " s")
		busy = nil
		return false
	end
	return true
end
M.isBusy = isBusy

local function readLine(line)
	if not (line and api.engine.entityExists(line)) then return nil end
	return api.engine.getComponent(line, api.type.ComponentType.LINE)
end

local function stationCount(group)
	if not api.engine.entityExists(group) then return nil end
	local sg = api.engine.getComponent(group, api.type.ComponentType.STATION_GROUP)
	if not sg or not sg.stations then return nil end
	return #sg.stations
end

--- English key of the reason why `line` can't be copied or reversed now, or nil.
local function blockReason(comp)
	if not comp then return "Line no longer exists" end -- i18n: keys
	local stops = comp.stops
	return core.blockReason(stops and #stops or 0, core.missingCount(stops, stationCount))
end

--- English key of the reason why `comp` can't be reversed, beyond blockReason: with stop 1 kept first, 2 stops reverse
--- to themselves (the line already runs both ways).
local function reverseReason(comp)
	if comp and comp.stops and #comp.stops < 3 then
		return "Reversing needs at least 3 stops: with 2, the line already runs both ways." -- i18n: keys
	end
	return nil
end

--- The entry's { enabled, tooltip }; `extraReason(comp)` (optional) adds an entry-specific English reason.
local function entryView(ctx, tooltip, extraReason)
	if isBusy() then return { enabled = false, tooltip = tooltip } end
	local comp = readLine(ctx.line)
	local reason = blockReason(comp) or (extraReason and extraReason(comp))
	if reason then return { enabled = false, tooltip = _(reason) } end -- i18n: ignore
	return { enabled = true, tooltip = tooltip }
end

--- Re-checks the line at click time; returns its component, or nil after a feedback line.
local function checkedLine(ctx)
	if isBusy() then
		say("previous command still in flight")
		return nil
	end
	local comp = readLine(ctx.line)
	local reason = blockReason(comp)
	if reason then
		actions.feedback(ctx.params, _(reason), true) -- i18n: ignore
		return nil
	end
	return comp
end

-- Duplicate --------------------------------------------------------------------------------------------------------

--- The copy's name: "<name> (copy)", or "<name> (copy N)" when the player already has a line of that name.
function M.copyName(line, player)
	local taken = {}
	local lines = api.engine.system.lineSystem.getLinesForPlayer(player)
	for i = 1, #(lines or {}) do
		taken[api.engine.util.getEntityName(lines[i])] = true
	end
	return core.copyName(api.engine.util.getEntityName(line), taken, _("{name} (copy)"), _("{name} (copy {n})"))
end

local function selectNewLine(params, newLine)
	-- only in the manager that asked (a manager closed or reopened since then keeps its own selection)
	if newLine == nil or params ~= capture.params() or type(params.selectLine) ~= "function" then return end
	local ok, err = pcall(params.selectLine, { entity = newLine }, true, nil)
	if not ok then warnOnce("select", err) end
end

function M.duplicate(ctx)
	local comp = checkedLine(ctx)
	if not comp then return end
	local params, line = ctx.params, ctx.line
	local snap = undo_core.snapshot(comp)
	local player = api.engine.util.getPlayer()
	local name = M.copyName(line, player)
	local color = line_util.makeLineColor(player)
	local built = undo_core.build(snap, api.type)
	busy = { since = now(), kind = "duplicate" }
	api.cmd.sendCommand(api.cmd.makeLineCreateCmd(name, color, player, built), function(_result, success, resultEntities)
		local ok, err = pcall(function()
			busy = nil
			if success then
				-- the created line, as the editor reads it (manager_window.tl:6545-6550)
				local newLine = resultEntities and resultEntities[1] and resultEntities[1][1]
				say("duplicated line " .. tostring(line) .. " as " .. tostring(newLine) .. " (" .. #snap.stops .. " stops)")
				selectNewLine(params, newLine)
			else
				actions.feedback(params, _("Line Manager Plus: the game refused the new line."), true)
			end
		end)
		if not ok then warnOnce("duplicate callback", err) end
	end)
end

-- Reverse ----------------------------------------------------------------------------------------------------------

--- The reversed snapshot of `comp` (live LINE component of `line`) with the engine's terminals for the new direction.
function M.reversed(line, comp)
	local snap = undo_core.snapshot(comp)
	local rev = core.reverse(snap)
	local ok, err = pcall(function()
		local assignment = api.engine.system.lineSystem.getBestLineAssignment(line, undo_core.build(rev, api.type), true)
		core.applyAssignment(rev, assignment)
	end)
	if not ok then warnOnce("terminals", err) end -- keeps the player's terminals
	return rev, snap
end

function M.reverse(ctx)
	local comp = checkedLine(ctx)
	if not comp then return end
	local params, line = ctx.params, ctx.line
	local reason = reverseReason(comp)
	if reason then
		actions.feedback(params, _(reason), false) -- i18n: ignore
		return
	end
	local rev, snap = M.reversed(line, comp)
	if undo_core.equal(rev, snap) then
		-- a mirror-image route such as A, B, C, B
		actions.feedback(params, _("Line Manager Plus: this line visits the same stops in both directions, so reversing doesn't change it."), false)
		return
	end
	local built = undo_core.build(rev, api.type)
	capture.resetEditorMode(params)
	busy = { since = now(), kind = "reverse" }
	api.cmd.sendCommand(api.cmd.makeLineUpdateCmd(line, built), function(_result, success)
		local ok, err = pcall(function()
			busy = nil
			if success then
				say("reversed line " .. tostring(line) .. " (" .. #rev.stops .. " stops)")
			else
				actions.feedback(params, _("Line Manager Plus: the game refused the reversed line."), true)
			end
		end)
		if not ok then warnOnce("reverse callback", err) end
	end)
end

-- Duplicate + reverse ---------------------------------------------------------------------------------------------

--- A reversed copy in one makeLineCreateCmd: the reverse's stops and terminals (M.reversed, asked of the original
--- line) with the duplicate's name, new colour and selection. Nothing changes on the original line, so the editor's
--- mode stays. The same guards as both: blockReason, the 3-stop reason, and a mirror-image route gives the reverse's
--- feedback and no command (the "reversed" copy would be a plain copy).
function M.duplicateReversed(ctx)
	local comp = checkedLine(ctx)
	if not comp then return end
	local params, line = ctx.params, ctx.line
	local reason = reverseReason(comp)
	if reason then
		actions.feedback(params, _(reason), false) -- i18n: ignore
		return
	end
	local rev, snap = M.reversed(line, comp)
	if undo_core.equal(rev, snap) then
		actions.feedback(params, _("Line Manager Plus: this line visits the same stops in both directions, so reversing doesn't change it."), false)
		return
	end
	local player = api.engine.util.getPlayer()
	local name = M.copyName(line, player)
	local color = line_util.makeLineColor(player)
	local built = undo_core.build(rev, api.type)
	busy = { since = now(), kind = "duplicate reversed" }
	api.cmd.sendCommand(api.cmd.makeLineCreateCmd(name, color, player, built), function(_result, success, resultEntities)
		local ok, err = pcall(function()
			busy = nil
			if success then
				local newLine = resultEntities and resultEntities[1] and resultEntities[1][1]
				say("duplicated line " .. tostring(line) .. " reversed as " .. tostring(newLine) .. " (" .. #rev.stops
					.. " stops)")
				selectNewLine(params, newLine)
			else
				actions.feedback(params, _("Line Manager Plus: the game refused the new line."), true)
			end
		end)
		if not ok then warnOnce("duplicate reversed callback", err) end
	end)
end

-- Install ----------------------------------------------------------------------------------------------------------
local installed = false

--- Installs the Line actions button (lmp_actions, lmp_rows, lmp_capture) and registers both entries; true when
--- installed (now or before), false when a base function is missing. Errors pass to the caller (lmp.script.lua pcall).
function M.install(_replacementApi, _params)
	if installed then return true end
	if not actions.install() then return false end
	actions.register({
		id = "duplicate", order = 100, label = "Duplicate line", icon = ICON_DUPLICATE, -- i18n: keys label
		view = function(ctx)
			return entryView(ctx, _("A new line with the same stops and settings, a new color and no vehicles."))
		end,
		run = M.duplicate,
	})
	actions.register({
		id = "reverse", order = 200, label = "Reverse line", icon = ICON_REVERSE, -- i18n: keys label
		view = function(ctx)
			return entryView(ctx,
				_("Serve the stops in the opposite order. Stop 1 stays first; terminals are chosen for the new direction."),
				reverseReason)
		end,
		run = M.reverse,
	})
	actions.register({
		id = "duplicate_reversed", order = 300, label = "Duplicate + reverse line", icon = ICON_DUPLICATE, -- i18n: keys label
		view = function(ctx)
			return entryView(ctx,
				_("A new line with the stops in the opposite order (stop 1 first),\na new color and no vehicles."),
				reverseReason)
		end,
		run = M.duplicateReversed,
	})
	installed = true
	say("installed")
	return true
end

return M
