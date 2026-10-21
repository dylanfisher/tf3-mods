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
-- Set cargo for all stops (order 400; PLAN.md "Open work" and D9, 2026-10-20): the entry opens a second page of the
-- menu (lmp_actions choices / choose) with "Clear all" and each cargo type at least one stop of the line can take
-- (Passengers first, then by the cargo type's order; freight only while currently produced, as the base cargo chooser
-- lists it, cargofilter_window.tl:576-588). A choice is one makeLineUpdateCmd as Reverse (snapshot,
-- line_ops_core.setAllStopsCargo, customFilters = true as the base chooser, cargofilter_window.tl:438, editor mode
-- reset, one toolbar undo step): every stop that can take the cargo (line_ops_core.supportsCargo) loads only it, the
-- others are left unchanged (user decision); Clear all sets every stop's load to all false. maxLoad, the unload flags
-- and the load mode stay. Stop facts (M.stopInfos): the terminal (STATION_GROUP.stations[station + 1] ->
-- STATION.terminals[terminal + 1]) flags and the catchment's stocks (cargo_util.getInputOutputStocksForStation, as the
-- chooser, one query per station); the page's rows are cached for CHOICES_TTL_US while it is open.
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
-- the manager's cargo settings icon (manager_window.tl:6321 hudConfigure) and the cargo chooser's remove icon
-- (cargofilter_window.tl:734)
local ICON_CARGO = "::/gui/line_vehicle_mgmt/icons/symbol_cargo.tga"
local ICON_CLEAR = "::/gui/line_vehicle_mgmt/icons/symbol_trash_bin.tga"

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

-- Set cargo for all stops -----------------------------------------------------------------------------------------

M.CLEAR_ID = "clear"
M.CHOICES_TTL_US = 1000000 -- the page's rows are re-read at most once a second
M.MAX_STOPS = 1000 -- loop cap for a line's stops

local cargoUtil -- base cargo_util (GUI state), required on first use; false when missing
local function cargo_util()
	if cargoUtil == nil then
		local ok, cu = pcall(ug_require, "::/gui/main/cargo_util.tl")
		cargoUtil = ok and type(cu) == "table" and cu or false
		if not cargoUtil then warnOnce("cargo_util", cu) end
	end
	return cargoUtil or nil
end

--- Cargo types as { count = max id + 1, passenger = id, list = { { id, order, name, icon } } } with every type that
--- can be offered: passengers and the freight currently produced.
function M.cargoTypes()
	local all = api.res.cargoTypeRep.getAll(true)
	local passenger = api.res.cargoTypeRep.getPassengerCargoTypeId()
	local count, list = 0, {}
	for id in pairs(all) do
		if id + 1 > count then count = id + 1 end
		if id == passenger or api.engine.util.stock.isCargoTypeCurrentlyProduced(id) then
			local ct = api.res.cargoTypeRep.get(id)
			if ct ~= nil then
				list[#list + 1] = { id = id, order = ct.order or 0, name = ct.name, icon = ct.icon }
			end
		end
	end
	return { count = count, passenger = passenger, list = list }
end

--- Per-stop facts of the live LINE component `comp` for line_ops_core.supportsCargo: { pLoad, pUnload, cLoad,
--- cUnload, input, output, load } per stop (see line_ops_core). A terminal that can't be read leaves the flags nil.
function M.stopInfos(comp)
	local infos, stocks = {}, {}
	local cu = cargo_util()
	local n = math.min(#comp.stops, M.MAX_STOPS)
	for k = 1, n do
		local s = comp.stops[k]
		local info = { load = {}, input = {}, output = {} }
		local load = s.stopConfig and s.stopConfig.load
		for i = 1, math.min(load and #load or 0, 1024) do
			if load[i] then info.load[i - 1] = true end
		end
		local ok, err = pcall(function()
			local sg = api.engine.getComponent(s.stationGroup, api.type.ComponentType.STATION_GROUP)
			local station = sg and sg.stations[s.station + 1]
			local st = station and api.engine.getComponent(station, api.type.ComponentType.STATION)
			local t = st and st.terminals[s.terminal + 1]
			if not t then return end
			info.pLoad, info.pUnload = t.passengersLoad == true, t.passengersUnload == true
			info.cLoad, info.cUnload = t.cargoLoad == true, t.cargoUnload == true
			if (info.cLoad or info.cUnload) and cu then
				local io = stocks[station]
				if io == nil then
					local input, _ni, output = cu.getInputOutputStocksForStation(station)
					io = { input = input or {}, output = output or {} }
					stocks[station] = io
				end
				info.input, info.output = io.input, io.output
			end
		end)
		if not ok then warnOnce("stop info", err) end
		infos[k] = info
	end
	return infos
end

local choicesCache = nil -- { line, at, rows }

--- The page's rows: Clear all, then one per cargo type some stop can take (or one disabled hint row).
function M.cargoRows(ctx)
	if choicesCache and choicesCache.line == ctx.line and now() - choicesCache.at < M.CHOICES_TTL_US then
		return choicesCache.rows
	end
	local rows = {}
	local comp = readLine(ctx.line)
	local reason = (isBusy() and "A change to this line is still in progress.") -- i18n: keys
		or blockReason(comp)
	if reason then
		rows[1] = { id = "blocked", label = _(reason), icon = ICON_CARGO, enabled = false } -- i18n: ignore
	else
		local infos = M.stopInfos(comp)
		local types = M.cargoTypes()
		local byId = {}
		for _i, t in ipairs(types.list) do byId[t.id] = t end
		local loading = core.loadingStops(infos)
		rows[1] = { id = M.CLEAR_ID, label = _("Clear all"), icon = ICON_CLEAR, enabled = loading > 0,
			tooltip = loading > 0 and _("Remove the cargo selection of every stop of this line.")
				or _("No stop of this line has a cargo selected.") }
		local choices = core.cargoChoices(infos, types.list, types.passenger)
		for _i, c in ipairs(choices) do
			local t = byId[c.id]
			local values = { cargo = t.name, n = c.supported, total = #infos }
			local tooltip
			if c.done >= c.supported then
				tooltip = core.fill(_("Every stop that can take {cargo} already loads only it."), values)
			elseif c.supported >= #infos then
				tooltip = core.fill(_("Load only {cargo} at all {total} stops."), values)
			else
				tooltip = core.fill(_("Load only {cargo} at the {n} of {total} stops that can take it.\nThe other stops stay as they are."), values)
			end
			rows[#rows + 1] = { id = c.id, label = t.name, icon = t.icon, iconClass = "text-icon-size-hack",
				enabled = c.done < c.supported, tooltip = tooltip }
		end
		if #choices == 0 then
			rows[#rows + 1] = { id = "none", label = _("No cargo type fits these stops"), icon = ICON_CARGO,
				enabled = false,
				tooltip = _("No stop has a terminal and catchment for a produced cargo.") }
		end
	end
	choicesCache = { line = ctx.line, at = now(), rows = rows }
	return rows
end

--- A click on a row of the page: `choice` is M.CLEAR_ID or a cargo type id.
function M.setCargo(ctx, choice)
	choicesCache = nil
	local cargoId = nil
	if choice ~= M.CLEAR_ID then
		if type(choice) ~= "number" then return end -- a hint row
		cargoId = choice
	end
	local comp = checkedLine(ctx)
	if not comp then return end
	local params, line = ctx.params, ctx.line
	local types = M.cargoTypes()
	local infos = M.stopInfos(comp)
	local snap = undo_core.snapshot(comp)
	local new, changed = core.setAllStopsCargo(snap, cargoId, function(k)
		return core.supportsCargo(infos, k, cargoId, types.passenger)
	end, types.count)
	if changed == 0 then
		actions.feedback(params, _("Line Manager Plus: the stops already have this cargo selection."), false)
		return
	end
	local built = undo_core.build(new, api.type)
	capture.resetEditorMode(params)
	busy = { since = now(), kind = "set cargo" }
	api.cmd.sendCommand(api.cmd.makeLineUpdateCmd(line, built), function(_result, success)
		local ok, err = pcall(function()
			busy = nil
			choicesCache = nil
			if success then
				say("set cargo " .. (cargoId and tostring(cargoId) or "none") .. " on line " .. tostring(line) .. " ("
					.. changed .. " of " .. #new.stops .. " stops changed)")
			else
				actions.feedback(params, _("Line Manager Plus: the game refused the cargo change."), true)
			end
		end)
		if not ok then warnOnce("set cargo callback", err) end
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
	actions.register({
		id = "set_cargo", order = 400, label = "Set cargo for all stops", icon = ICON_CARGO, -- i18n: keys label
		view = function(ctx)
			return entryView(ctx,
				_("Choose one cargo type for every stop that can take it,\nor clear the cargo selection of all stops."))
		end,
		choices = M.cargoRows,
		choose = M.setCargo,
	})
	installed = true
	say("installed")
	return true
end

return M
