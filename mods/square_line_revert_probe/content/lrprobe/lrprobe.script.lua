-- DEV ONLY - NOT FOR UPLOAD. Where can a "revert line" button live? Read-only: nothing here sends a command.
-- Every probe logs "[LRPROBE] <probe> ..." to stdout.txt. Steps: plans/square_line_revert/PROBE.md.
--
-- A  "toggle": wraps button_react_util.makeIconToggleButton (a module function, so the wrapper is seen by
--    manager_window.tl, which looks it up per call). When the icon is the Auto-Rename "A+"
--    (manager_window.tl:6317, used in LinePanelActionButtons at :3520), a test button is put to its left.
--    Precedent for wrapping module functions in doReplace: zhenya_auto_assign_terminals aat_eow.script.lua:685-698.
-- B  "params": wraps line_util.makeLineActionDescriptor to capture the manager's commonParams, which hold the
--    line being edited (lineState:old().entityAndRevision.entity, as aat_eow.script.lua:673-674 reads it)
--    and the selection (lineManagerStateRef:get().lineListEntitiesSelected, aat_eow.script.lua:634).
-- C  "eow": an official LineEowExtensionPoint plugin in the line window (line_eow.script.tl:24).
-- D  "event": does react.onEvent in a mod plugin hear "openVehicleManager" (fired with target nil)?

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local line_eow = ug_require "::/gui/entity_window/line/line_eow.script.tl"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"

local AUTO_RENAME_ICON = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"

local function say(...)
	local parts = { "[LRPROBE]" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	local line = table.concat(parts, " ")
	if log and log.message then log.message(line) else print(line) end
end

local function safe(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	say("ERROR", a)
	return nil
end

local function recipeName()
	local ok, name = pcall(react.getCurrentRecipeName)
	return ok and tostring(name) or "?"
end

--- One line per stop: everything a snapshot would have to copy (engine.d.tl:523-549).
local function dumpLine(tag, line)
	if not line then
		say(tag, "no line")
		return
	end
	if not api.engine.entityExists(line) then
		say(tag, "line", line, "does not exist")
		return
	end
	local comp = api.engine.getComponent(line, api.type.ComponentType.LINE)
	if not comp then
		say(tag, "line", line, "has no LINE component")
		return
	end
	local name = api.engine.getComponent(line, api.type.ComponentType.NAME)
	say(tag, "line", line, name and name.name or "?", "stops", #comp.stops,
		"reservationPriority", tostring(comp.reservationPriority))
	for i, s in ipairs(comp.stops) do
		local stopConfig = s.stopConfig
		say(tag, "  stop", i, "group", s.stationGroup, "station", s.station, "terminal", s.terminal,
			"alts", s.alternativeTerminals and #s.alternativeTerminals or "nil",
			"loadMode", tostring(s.loadMode),
			"wait", s.minWaitingTime, s.maxWaitingTime, s.maxAdditionalWaitingTime,
			"waypoints", s.waypoints and #s.waypoints or "nil",
			"stopConfig", stopConfig and "yes" or "nil")
	end
end

-- B: the manager's commonParams ---------------------------------------------------------------
local managerParams
local loggedParams = false

local function editedLine()
	local ls = managerParams and managerParams.lineState and managerParams.lineState:old()
	return ls and ls.entityAndRevision and ls.entityAndRevision.entity or nil, ls
end

local function selectedLines()
	local lines = {}
	local st = managerParams and managerParams.lineManagerStateRef and managerParams.lineManagerStateRef:get()
	for __, ear in ipairs(st and st.lineListEntitiesSelected or {}) do
		lines[#lines + 1] = ear.entity
	end
	return lines
end

local origDescriptor
local function lineActionDescriptor(commonParams, ...)
	if type(commonParams) == "table" and commonParams.lineManagerStateRef then
		managerParams = commonParams
		if not loggedParams then
			loggedParams = true
			say("params", "captured commonParams in", recipeName())
		end
	end
	return origDescriptor(commonParams, ...)
end

-- A: a button next to "A+" ---------------------------------------------------------------------
local function onToggleProbeClick(where)
	local line, ls = editedLine()
	say("toggle", "CLICK in", where, "managerParams", managerParams and "yes" or "nil",
		"editedLine", tostring(line), "editorPathVias", ls and ls.path and #ls.path or "nil")
	local sel = selectedLines()
	say("toggle", "selected lines", #sel)
	dumpLine("toggle edited", line)
	for i, l in ipairs(sel) do
		if i > 3 then break end
		dumpLine("toggle selected", l)
	end
end

local origToggle
local function iconToggleButton(className, path, ...)
	local node = origToggle(className, path, ...)
	if path ~= AUTO_RENAME_ICON then
		return node
	end
	local where = recipeName()
	local wrapped = safe(function()
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.Button{
					meta = {
						class = "vehicle-button, secondary",
						tooltip = "LRPROBE A: revert test (logs only)",
					},
					content = builtin.TextView{ text = "R" },
					onClick = function()
						safe(onToggleProbeClick, where)
					end,
				},
				node,
			},
		}
	end)
	return wrapped or node
end

local installed = false
local function doReplace(replacementApi)
	if installed then return end
	installed = true
	-- read the current functions now, so wrappers of other mods (Auto Assign Terminals) stay in the chain
	origToggle = button_react_util.makeIconToggleButton
	origDescriptor = line_util.makeLineActionDescriptor
	if type(origToggle) == "function" then
		button_react_util.makeIconToggleButton = iconToggleButton
		say("toggle", "installed wrapper")
	else
		say("toggle", "makeIconToggleButton missing:", type(origToggle))
	end
	if type(origDescriptor) == "function" then
		line_util.makeLineActionDescriptor = lineActionDescriptor
		say("params", "installed wrapper")
	else
		say("params", "makeLineActionDescriptor missing:", type(origDescriptor))
	end
end

-- C: line window plugin ------------------------------------------------------------------------
local function onEvent(probe)
	return function(name, param)
		safe(function()
			say(probe, "heard", name, "openWithLineEntity", param and tostring(param.openWithLineEntity) or "nil")
		end)
	end
end

local LineEowProbePlugin = react.RegisterPluginRecipe(line_eow.LineEowExtensionPoint, "LrProbeLineEowPlugin", function(p)
	local line = p.entityId
	react.onEvent("openVehicleManager", onEvent("eow-event"))
	local countState = engine_react_util.useStepState(function()
		local comp = api.engine.entityExists(line) and api.engine.getComponent(line, api.type.ComponentType.LINE) or nil
		return comp and #comp.stops or -1
	end)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { tooltip = "LRPROBE C: revert test (logs only)" },
				content = builtin.TextView{ text = "LRPROBE C: revert line (" .. tostring(countState:old()) .. " stops)" },
				onClick = function()
					say("eow", "CLICK line", line, "ownership", tostring(p.ownershipState))
					safe(dumpLine, "eow", line)
				end,
			},
		},
	}
end)

-- D: event listener ----------------------------------------------------------------------------
local EventProbePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "LrProbeEventPlugin", function()
	react.onEvent("openVehicleManager", onEvent("event"))
	return builtin.BoxLayout{ children = {} }
end)

say("loaded")

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return {
		doReplace = doReplace,
		LineEowProbePlugin = LineEowProbePlugin,
		EventProbePlugin = EventProbePlugin,
	}
end
