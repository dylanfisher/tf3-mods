-- Smart Lanes road tool (Phase 2 step 1): Roads -> Tools, right after the Crossing Tool.
-- Hover a junction (or a roundabout between its junctions), click to select it, see its lane
-- connections and press Smart lanes / Reset. plans/square_smart_lanes/PLAN.md "Phase 2".
--
-- Wiring (as mods/square_bulk_bulldozer bulk_bulldozer.script.tl, a working mod tool):
-- sl_tool.res.lua -> getDefinition below -> ACTION_CUSTOM with the SmartLanesAction recipe; the
-- construction menu mounts it while the entry is selected (construction.tl:401-436) and the recipe
-- hands the world layer to param.setActionFn. The world layer is an ActionDescriptor with a
-- builtin.Selector (onHover / onSelect / onProcessMouseEvent, builtin.d.tl:1392-1415), a
-- builtin.NodeViewer for the selected junctions' connections (double_slip_switch.tl:87-143, 185-199;
-- one NodeViewer, its nodeConfig map holding every selected junction: ring, street, Shift+click
-- multi selection, sl_toolcore C.nodeViewerSpec),
-- one EdgeRenderable with circle markers and an ActionTooltip.
-- Toolbar values reach the recipe through onChangeFn -> api.gui.fireReactEvent -> react.onEvent
-- (getDefinition may run in another Lua state than the recipe; bulk bulldozer research §6, §12).
-- All logic (picking, apply, reset, re-reads) is in sl_toolcore.lua, tested offline.
-- Toolbar: row 1 Smart lanes | Reset (each only where it would change something), row 2 Smart lights | Re-time, row 3
-- "Keep timing adjusted [Yes|No]" (rows 2 and 3 only at a lit junction; a last row "Record traffic" at any selected
-- real junction or roundabout; twin toggle params, the one whose default is the junction's enrolled state shown:
-- autoTwin); with nothing selected instead the settings panel (sl_settingsui.lua: this save's light settings, also
-- in the base Crossing Tool through a forEachDefinition wrapper, installed below and by doReplace), then the info
-- block.
--
-- Exports through data() like every .script.lua of this mod (memory: `return M` alone fails in game).
--
-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state; sections get_definition,
-- action_render (tool recipe), world_render (actionFn), step (react.onStep, Main Thread), hover /
-- select (Selector), apply / reset / retime_button / record_button (toolbar buttons), status_render,
-- badge_render; nested inside them the controller's (sl_toolcore Core.new): resolve, badge,
-- refresh, multi_add, batch, nv_spec, highlight, retime (Re-time measuring and probe, per frame), record (the traffic
-- recording, per frame). The PROBE diagnostics (hover, nodeviewer, oneway) are logged only with
-- "Debug: performance log" On (probeOn below); TOOL / PICK / APPLY / WRITE / VERIFY / RESET / ERROR
-- lines stay (one per player action).

local sqperf = ug_require "square_smart_lanes::/sqperf/square_smart_lanes.lua"
local perf = sqperf.new({ mod = "square_smart_lanes", ctx = "gui", paramKey = "sqperf_log", first = { "action_render" } })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local constructionUi = ug_require "::/gui/construction/construction_react_util.tl"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local Core = ug_require "square_smart_lanes::/smart_lanes/sl_toolcore.lua"
local SettingsUI = ug_require "square_smart_lanes::/smart_lanes/sl_settingsui.lua"

local EV_SHOWN = "SmartLanes.shown"
local EV_APPLY = "SmartLanes.apply"
local EV_RESET = "SmartLanes.reset"
local EV_LIGHTS = "SmartLanes.lights" -- the "Smart lights" button ("Lights only" before 2026-10-16)
local EV_RETIME = "SmartLanes.retime"
local EV_AUTO = "SmartLanes.autoBox" -- the "Keep timing adjusted" toggle (payload { value = 1 Yes | 2 No })
local EV_RECORD = "SmartLanes.record" -- the "Record traffic" button
local EV_STATUS = "SmartLanes.status"
local EV_BADGE = "SmartLanes.badge"
local KEY_APPLY = "sqrl_tool_apply"
local KEY_RESET = "sqrl_tool_reset"
local KEY_LIGHTS = "sqrl_tool_lights"
local KEY_RETIME = "sqrl_tool_retime"
local KEY_AUTO_ON = "sqrl_tool_auto_on"   -- shown at an enrolled junction (default Yes)
local KEY_AUTO_OFF = "sqrl_tool_auto_off" -- shown at a junction not enrolled (default No)
local KEY_RECORD = "sqrl_tool_record"
local KEY_INFO = "sqrl_tool_status"
local GROUP_ACTIONS = "sqrl_tool_actions" -- Smart lanes and Reset share the first row (the lanes), each shown only
-- where a click would change something (user 2026-10-16: hidden, not grayed; both hidden: no row);
-- "Smart lights" and Re-time the second (the light phases), shown only at a junction with a standing traffic light
-- (Smart lights only where its axis plan can be made, PLAN.md "No classic fallback"):
-- all four in one row do not fit the 314 px bottom bar in German / Russian (construction.css.lua:726; a group is one
-- horizontal BoxLayout, it does not wrap). A param whose checkEnabledFn says "Hidden" is left out before the menu
-- groups the params (construction.tl:2050-2072, the bottom bar; 1361-1376 the side panel), so a hidden row leaves no
-- row, gap or separator (flushGroup, construction.tl:2023-2046). A shown button that can't act right now (a change
-- landing; in the light row also nothing to change) is "Disabled" (grayed) with its reason in the tooltip.
local GROUP_LIGHTS = "sqrl_tool_lights"
-- "Keep timing adjusted" (RETIME_PLAN.md "Step B"): the base Yes / No toggle (a two-value Button param:
-- script_param_util.tl:396-450 draws a ToggleButtonGroup, as the street builder's "Underground") in a third row of its
-- own, shown with the light row. With its label it does not fit beside Smart lights | Re-time in the 314 px bar
-- ("Takt laufend anpassen", "Держать фазы настроенными" are each ~150-200 px; a group is one horizontal BoxLayout,
-- construction.tl:2050-2072, it does not wrap); a group of its own is a new row (flushGroup draws the base separator
-- above it, as between the other rows).
local GROUP_AUTO = "sqrl_tool_auto"
-- "Record traffic" (PLAN.md "Traffic rate at a junction"): one base Button in a last row of its own, shown at any
-- selected real junction (3 roads or more) or roundabout (not only lit ones; never at a bend or lane drop), right
-- above the info block that shows its rates. Beside Smart lanes | Reset it would make a row of three (German
-- "Smarte Spuren | Zurücksetzen | Verkehr aufzeichnen" does not fit the 314 px bar); its own row keeps every row at
-- two buttons at most.
local GROUP_RECORD = "sqrl_tool_record"
-- The settings panel with nothing selected (sl_settingsui.lua, PLAN.md "In-game settings panel"): its own group
-- (SettingsUI.GROUP), labels above their controls. It replaces the rev 8 rows "Adjust all lights" / "Stop for all
-- lights": its "Automatic light timing" is the same per-save switch (All lights / Junctions I choose).
-- the info block (selection, result, lane status) under them: its group id is the class the tool's
-- stylesheet (sl_tool.css.lua) scopes its rules under, so it reads as text, not as a button
local GROUP_INFO = "sq-tool-info" -- dashes: the stylesheet parser reads class names as [%a%d-]+ only

-- Menu position: the Crossing Tool is roads_tools order 1200, nothing sits between 1200 and 1250
-- (base tools: tram 100, bus lane 200, crosswalk 300, player owned 1000, traffic light 1100).
-- Bus lane and traffic light are year-gated; while they are hidden the menu's isActionActive
-- index check (construction.tl:758-760, 427) mismatches. In mouse mode that only makes abort()
-- a no-op (construction.tl:315-328); gamepad mode may misbehave (bulk bulldozer research §1).
local MENU_ORDER = 1250
local RMB_CLICK_MAX_PX = 16 -- a right click that moved further is a camera drag

local function emit(kind, fields)
	local text = Rules.line(kind, fields)
	pcall(function() log.message(text) end)
end

-- PROBE lines (Phase 2 spike diagnostics, ~100 per short session) only with the debug setting On:
-- perf.on is the instrument's level 3 gate, read at its first stop and then every 30 s.
local function probeOn()
	return perf.on == true
end

-- ERROR lines are capped (sl_pick.errorGate: 3 per where=, 20 per session), so a failure that
-- repeats on every refresh / render cannot flood stdout.txt (in game 2026-10-11: 68 highlight errors)
local errorState = {}

local function out(kind, fields)
	if string.find(kind, "PROBE", 1, true) == 1 and not probeOn() then return end
	if kind == "ERROR" then
		local where
		for _, f in ipairs(fields or {}) do
			if f[1] == "where" then where = f[2] end
		end
		local gate = Pick.errorGate(errorState, where)
		if gate == "drop" then return end
		if gate == "last" then
			local copy = {}
			for i, f in ipairs(fields) do copy[i] = f end
			copy[#copy + 1] = { "more", "suppressed" }
			fields = copy
		end
	end
	emit(kind, fields)
end

-- File-scope state of this Lua state (the recipe's). Reset when the tool is closed.
-- In the shared state module (sl_toolstate.lua), so the background plugin (sl_bg.script.lua) reaches g.core: it steps
-- a Re-time run while the tool is closed.
local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
if g.layout == nil then
	g.core = nil
	g.layout = "turbo" -- the one layout the tool applies ("Smart lanes", sl_rules.LAYOUTS)
	g.status = { head = Pick.status(nil).head, detail = Pick.status(nil).detail, extra = nil, version = 0 }
	g.badge = { key = "none", label = Pick.badgeNone().label, class = nil, version = 0 } -- lane status badge
	g.nvKey = nil -- selection the NodeViewer probe line was logged for
	g.activations = 0
end

local function core()
	if g.core == nil then
		g.core = Core.new(api, out, os.clock, perf)
		-- the automatic re-timing runtime of this Lua state (sl_bg.script.lua makes it), nil when the plugin runs elsewhere
		g.core.autoRt = function() return g.auto end
	end
	return g.core
end

--- The status's extra lines (Re-time, Record traffic) and which of them are muted as one comparable text ("" for none).
local function extraKey(extra, muted)
	if type(extra) ~= "table" then return "" end
	local k = table.concat(extra, "\n")
	if type(muted) == "table" and #muted > 0 then k = k .. "\n#" .. table.concat(muted, ",") end
	return k
end

local function publishStatus(st)
	if st.head == g.status.head and st.detail == g.status.detail
		and extraKey(st.extra, st.muted) == extraKey(g.status.extra, g.status.muted) then return end
	g.status = { head = st.head, detail = st.detail, extra = st.extra, muted = st.muted, version = g.status.version + 1 }
	pcall(api.gui.fireReactEvent, EV_STATUS, g.status)
end

local function publishBadge(b)
	if b == nil then return end
	if b.key == g.badge.key and b.label == g.badge.label and b.class == g.badge.class then return end
	g.badge = { key = b.key, label = b.label, class = b.class, version = g.badge.version + 1 }
	pcall(api.gui.fireReactEvent, EV_BADGE, g.badge)
end

local function vec4(c, a)
	return api.type.Vec4f.new(c[1], c[2], c[3], a or c[4])
end

local function cursor()
	local ok, pos = pcall(function()
		if not api.gui.mouse.hasTerrainPosition() then return nil end
		local p = api.gui.mouse.getTerrainPosition()
		return { x = p.x, y = p.y }
	end)
	if ok then return pos end
	return nil
end

local function isStreetThing(entity)
	if type(entity) ~= "number" or entity < 0 then return false end
	local CT = api.type.ComponentType
	local okN, n = pcall(api.engine.getComponent, entity, CT.BASE_NODE)
	if okN and n ~= nil then return true end
	local okE, e = pcall(api.engine.getComponent, entity, CT.BASE_EDGE_STREET)
	return okE and e ~= nil
end

-- A full circle at (x, y, z) (bulk bulldozer markerEdge / overpass_probe full-circle Arc).
local function circleEdge(m, color)
	local width = m.kind == "ring" and 0.5 or 0.8
	local arc = api.type.EdgeGeometry.Arc.new()
	arc.center = api.type.Vec2f.new(m.x, m.y)
	arc.radius = m.r
	arc.startAngle = 0
	arc.angle = 2 * math.pi
	local geo = api.type.EdgeGeometry.new()
	geo.arc = arc
	geo.height = api.type.Vec2f.new(m.z, m.z)
	geo.width = width
	geo.length = 2 * math.pi * m.r
	local viz = builtin.type.EdgeRenderable.Edge.new(geo)
	viz.colors = { color, color, color }
	viz.stepSize = 1
	viz.width = width
	viz.offsetZ = 1.0
	return viz
end

-- One-way arrows (LayerConfig.showOneWay, api/type.d.tl:4924). The base game sets it only for the
-- street builder (construction_react_util.tl:521-523, in the local getLayerConfig). A map layer the
-- player picked wins, as in base (mergeLayerConfig, construction_react_util.tl:3985-3990).
local function oneWayLayerConfig(preferred)
	if preferred ~= nil then return preferred end
	local cfg = api.type.LayerConfig.new()
	cfg.showOneWay = true
	return cfg
end

-- Better Roundabouts (square_roundabouts) placements: its constructions' menu entries exist only
-- while that mod is active, so matching the definition's resName is the installed check too.
local function isRoundaboutPlacement(definition)
	return definition.action == "ACTION_CONSTRUCTION_BUILDER" and type(definition.resName) == "string"
		and definition.resName:find("square_roundabouts", 1, true) ~= nil
end

-- The native Crossing Tool: construction.tl:4438 calls construction_react_util.getActionParams
-- through the module table at render time, so wrapping it in this (GUI) Lua state adds the arrows
-- to ACTION_LANE_MODIFIER_TOOL and to Better Roundabouts placements. Guarded: once per module
-- table, any error returns the base result.
local function patchCrossingToolArrows()
	if type(constructionUi) ~= "table" or type(constructionUi.getActionParams) ~= "function" then return end
	if constructionUi.__sqrlOneWayPatched then return end
	constructionUi.__sqrlOneWayPatched = true
	local base = constructionUi.getActionParams
	local logged = {}
	constructionUi.getActionParams = function(definition, ...)
		local res = base(definition, ...)
		pcall(function()
			if res == nil or definition == nil then return end
			local which
			if definition.action == "ACTION_LANE_MODIFIER_TOOL" then
				which = "crossing_tool"
			elseif isRoundaboutPlacement(definition) then
				which = "roundabout"
			end
			if which == nil then return end
			if res.layerConfig == nil then res.layerConfig = api.type.LayerConfig.new() end
			res.layerConfig.showOneWay = true
			local key = which .. ":" .. tostring(definition.resName)
			if not logged[key] then
				logged[key] = true
				out("PROBE", { { "oneway", which }, { "res", tostring(definition.resName) } })
			end
		end)
		return res
	end
	if sqperf.readParam(Rules.MOD_ID, "sqperf_log") then emit("PROBE", { { "oneway", "patched" } }) end
end
pcall(patchCrossingToolArrows)

local MARKER_COLORS = {
	sel = { 0.20, 0.80, 0.75, 0.95 },
	ring = { 0.20, 0.80, 0.75, 0.6 },
	hover = { 1, 1, 1, 0.8 },
	-- the mid nodes' connections (sl_midview): lane changes bright, straight on faint
	mid = { 1.00, 0.75, 0.25, 0.95 },
	midStraight = { 1.00, 0.75, 0.25, 0.35 },
}

-- One mid-node connection (sl_toolcore C.highlight lines, sl_midview V.curves) as a cubic spline edge. Not run in
-- game yet (TESTING.md "RS"): built in the caller's pcall, so an api mismatch only loses the curves (logged once).
local function splineEdge(l, color)
	local V2 = api.type.Vec2f.new
	local cs = api.type.EdgeGeometry.CubicSpline.new()
	cs.pos = { V2(l.a.x, l.a.y), V2(l.b.x, l.b.y) }
	cs.tangent = { V2(l.ta.x, l.ta.y), V2(l.tb.x, l.tb.y) }
	local geo = api.type.EdgeGeometry.new()
	geo.type = api.type.EdgeGeometry.Type.CUBIC_SPLINE
	geo.cubicSpline = cs
	local z = l.z or 0
	geo.height = V2(z, z)
	geo.width = 0.6
	geo.length = math.sqrt((l.b.x - l.a.x) ^ 2 + (l.b.y - l.a.y) ^ 2)
	local viz = builtin.type.EdgeRenderable.Edge.new(geo)
	viz.colors = { color, color, color }
	viz.stepSize = 1
	viz.width = 0.6
	viz.offsetZ = 1.0
	return viz
end
local midErrLogged = false

-- NodeViewer for the selected junction(s): one colour per outgoing segment. Defensive: the
-- NodeViewer data is built in a pcall and the outcome logged once per selection (PROBE nodeviewer).
local function nodeViewer(c)
	local spec = c.nodeViewerSpec()
	if next(spec) == nil then return nil end
	local nodes, edges = 0, 0
	local ok, res = pcall(function()
		local cfg = {}
		for node, list in pairs(spec) do
			nodes = nodes + 1
			local arr = {}
			for _, it in ipairs(list) do
				local d = api.type.NodeViewerData.new()
				d.edgeIdx = it.edgeIdx
				local col = Pick.PALETTE[it.color] or Pick.PALETTE[1]
				d.colors = { vec4(col, 1), vec4(col, 0.35) }
				d.order = 0
				d.width = 0.4
				arr[#arr + 1] = d
				edges = edges + 1
			end
			cfg[node] = arr
		end
		return builtin.NodeViewer{ nodeConfig = cfg }
	end)
	local key = Pick.targetKey(c.sel)
	if g.nvKey ~= key then
		g.nvKey = key
		if ok then
			out("PROBE nodeviewer", { { "ok", true }, { "target", key }, { "nodes", nodes }, { "edges", edges } })
		else
			out("PROBE nodeviewer", { { "ok", false }, { "target", key }, { "error", res } })
		end
	end
	if ok then return res end
	return nil
end

local SmartLanesAction = react.RegisterRecipe("SmartLanesAction", perf:wrap("action_render", function(param)
	-- hooks first, in a fixed order
	local versionState = react.useState(0)
	local refSeen = react.useRef(-1)
	local refWasActive = react.useRef(false)
	local refRmb = react.useRef(nil)
	local refParam = react.useRef(param)
	refParam:set(param)

	-- runs every frame (onStep): the status texts are rebuilt only when the core's version moved
	-- (every change of hover, selection or result bumps it) or when forced
	local function sync(force)
		local c = core()
		if c.version == refSeen:get() and not force then return end
		refSeen:set(c.version)
		versionState:set(c.version)
		publishStatus(c.status(g.layout))
		publishBadge(c.badge())
	end

	local function closeAll(why)
		if g.core ~= nil then
			local ok, e = pcall(g.core.flush)
			if not ok then out("ERROR", { { "where", "flush" }, { "err", e } }) end
		end
		g.nvKey = nil
		out("TOOL", { { "closed", why } })
		pcall(publishStatus, core().status(g.layout))
		pcall(publishBadge, core().badge())
	end

	react.onMount(function()
		pcall(publishStatus, core().status(g.layout))
		pcall(publishBadge, core().badge())
	end)
	react.onUnmount(function()
		pcall(closeAll, "unmount")
	end)

	-- the chips' checkEnabledFn fires this every menu step: sync only when something changed
	react.onEvent(EV_SHOWN, function(_name, _payload)
		sync()
	end)
	local function act(what, fn)
		if not refParam:get().isActive then return end
		local tAct = perf:start()
		local ok, e = pcall(fn)
		perf:stop(what, tAct)
		if not ok then out("ERROR", { { "where", what }, { "err", e } }) end
		sync()
	end
	-- one Smart lanes click: the whole roundabout when the roundabout itself is selected (clicked between its
	-- junctions), else the selected junction, street or junctions (sl_toolcore C.applySelection)
	react.onEvent(EV_APPLY, function()
		act("apply", function() core().applyAction(g.layout) end)
	end)
	react.onEvent(EV_RESET, function()
		act("reset", function()
			local s = core().sel
			core().reset((s ~= nil and s.kind == "node") and "node" or "ring")
		end)
	end)
	-- Smart lights: Smart Lanes phases for the selected lit crossroads' lanes as they are (sl_toolcore C.lightsOnly)
	react.onEvent(EV_LIGHTS, function()
		act("lights_only", function() core().lightsOnly() end)
	end)
	-- Re-time: measure the selected lit junction's traffic, then new phase lengths (sl_toolcore C.retime);
	-- pressed while it measures: cancel
	react.onEvent(EV_RETIME, function()
		act("retime_button", function() core().retime() end)
	end)
	-- Keep timing adjusted: the toggle's new value (1 Yes, 2 No) is the player's intent for the selected junction
	-- (sl_toolcore C.setAuto; the side already in force changes nothing)
	react.onEvent(EV_AUTO, function(_name, payload)
		act("auto_box", function() core().setAuto(type(payload) == "table" and payload.value == 1) end)
	end)
	-- Record traffic: start recording the selected junction / roundabout, or stop the recording there (sl_toolcore
	-- C.record)
	react.onEvent(EV_RECORD, function()
		act("record_button", function() core().record() end)
	end)

	react.onStep(function()
		local tStep = perf:start()
		local prm = refParam:get()
		local active = prm.isActive == true
		if active ~= refWasActive:get() then
			refWasActive:set(active)
			if active then
				g.activations = g.activations + 1
				out("TOOL", { { "activated", g.activations }, { "order", MENU_ORDER } })
			else
				closeAll("deactivated")
			end
		end
		local ok, e = pcall(core().step)
		if not ok then out("ERROR", { { "where", "step" }, { "err", e } }) end
		sync()
		perf:stop("step", tStep)
	end)

	-- Right click: clears the selection (in game only PressedOutside and Clicked of button 2 reach
	-- the Selector, bulk_bulldozer.script.tl:907-934). A click that moved like a camera drag keeps it.
	local onMouse = function(e)
		local Ty = api.gui.mouse.Event.Type
		if e.button ~= 2 then return false end
		if e.type == Ty.Pressed or e.type == Ty.PressedOutside then
			refRmb:set({ x = e.x, y = e.y })
			return false
		end
		if e.type == Ty.Clicked or e.type == Ty.Released then
			local p = refRmb:get()
			refRmb:set(nil)
			local moved = 0
			if p ~= nil and e.x ~= nil and e.y ~= nil then moved = math.max(math.abs(e.x - p.x), math.abs(e.y - p.y)) end
			if moved <= RMB_CLICK_MAX_PX and core().clear() then
				out("TOOL", { { "cleared", "right_click" } })
				sync()
				return true
			end
		end
		return false
	end

	local actionFn = function()
		local tWorld = perf:start()
		local _v = versionState:old() -- re-render on changes
		local c = core()
		local children = {
			builtin.Selector{
				filter = function(entity)
					return isStreetThing(entity)
				end,
				onHover = function(entity, _i, _d)
					local tHover = perf:start()
					c.onHover(entity, cursor())
					perf:stop("hover", tHover)
				end,
				onSelect = function(entity, _i, _d)
					local tSelect = perf:start()
					-- Shift read at the click (Main Thread), as Bulk Bulldozer reads it at the LMB
					-- press; unreadable -> a plain click. Hover never reads it (plain-click preview).
					c.select(entity, cursor(), { shift = c.shiftHeld() })
					sync()
					perf:stop("select", tSelect)
					return true -- swallow the click: no entity window
				end,
				onProcessMouseEvent = onMouse,
				selectionColor = vec4(MARKER_COLORS.sel, 0.35),
				selectionOutlineColor = vec4(MARKER_COLORS.sel, 0.7),
				selectionOutlineColor1 = vec4(MARKER_COLORS.sel, 0.9),
			},
		}
		local ents, markers, lines = {}, {}, {}
		local okH, e1, m1, l1 = pcall(c.highlight)
		if okH then ents, markers, lines = e1, m1, l1 or {} else out("ERROR", { { "where", "highlight" }, { "err", e1 } }) end

		local nv = nodeViewer(c)
		if nv ~= nil then children[#children + 1] = nv end

		if #markers > 0 or #lines > 0 then
			local okM, edges = pcall(function()
				local list = {}
				for _, m in ipairs(markers) do list[#list + 1] = circleEdge(m, vec4(MARKER_COLORS[m.kind] or MARKER_COLORS.hover)) end
				-- the mid nodes' connections: in the same EdgeRenderable (one per recipe)
				local okL, errL = pcall(function()
					for _, l in ipairs(lines) do
						list[#list + 1] = splineEdge(l, vec4(l.change and MARKER_COLORS.mid or MARKER_COLORS.midStraight))
					end
				end)
				if not okL and not midErrLogged then
					midErrLogged = true
					out("ERROR", { { "where", "mid_lines" }, { "err", errL } })
				end
				return list
			end)
			-- only ONE EdgeRenderable per recipe (the engine asserts on more; overpass_probe:4517-4519)
			if okM and #edges > 0 then
				children[#children + 1] = builtin.EdgeRenderable{ edges = edges, ignoreDepth = true }
			end
		end

		local okL, layer = pcall(function()
			local ctx = refParam:get().gameCtx
			return oneWayLayerConfig(ctx and ctx.preferredLayerConfig and ctx.preferredLayerConfig:get() or nil)
		end)
		if okL and layer ~= nil then
			children[#children + 1] = builtin.LayerConfig{ config = layer }
		elseif not okL then
			out("ERROR", { { "where", "layer" }, { "err", layer } })
		end

		if c.hover ~= nil then
			local text = Pick.describe(c.hover) .. "\n" .. Pick.detail(c.hover)
			if c.hover.badge ~= nil then text = text .. "\n" .. string.format(_("Lanes: %s"), c.hover.badge.label) end
			if c.sel == nil or Pick.targetKey(c.sel) ~= Pick.targetKey(c.hover) then
				text = text .. "\n" .. _("Click to select")
			end
			-- with a selection, Shift+click adds to it (sl_toolcore C.select); a selected junction leaves it
			if c.sel ~= nil then
				local member = false
				if c.hover.kind == "node" then
					if c.sel.kind == "node" then
						member = c.sel.node == c.hover.node
					else
						for _, n in ipairs(c.sel.junctionNodes or {}) do
							if n == c.hover.node then
								member = true
								break
							end
						end
					end
				end
				text = text .. "\n" .. (member and _("Shift+click: remove from the selection") or Pick.shiftHint())
			end
			children[#children + 1] = builtin.ActionTooltip{
				recipe = constructionUi.SimpleTooltipRecipe,
				param = { message = { message = text } },
			}
		end

		local desc = builtin.ActionDescriptor{
			tool = "smart-lanes-tool",
			crosshair = false,
			terrainCirclePolicy = "Never",
			highlightedEntities = ents,
			-- Back (Esc): clears the selection first, else leaves the tool
			onBack = function()
				if core().clear() then
					out("TOOL", { { "cleared", "back" } })
				else
					refParam:get().abort()
				end
			end,
			children = children,
		}
		perf:stop("world_render", tWorld)
		return desc
	end

	react.setForceFocusable(true)
	react.setRestrictMouseFocus(true)

	if not param.isActive then return nil end
	param.setActionFn(actionFn, "SmartLanesAction")
	-- Esc with a selection clears it; without one it falls through and closes the menu
	-- (construction_react_util.tl:1437-1441; bulk_bulldozer.script.tl:1096-1102).
	if core().sel ~= nil then
		react.useInputAction("IA_MENU_BACK", react.iaHandler(function()
			if core().clear() then out("TOOL", { { "cleared", "esc" } }) end
			sync()
		end))
	end
	return nil
end))

-- Hover texts of the two grey read-only boxes (also the params' own tooltips).
local STATUS_TIP = _("Selection: the junction or roundabout you clicked, and the result\nof the last button you pressed. Right-click or Esc clears the selection.")
local BADGE_TIP = _("Smart lanes: what the Smart lanes button sets.\nGame default: the game's own lane connections.\nGame default (locked): you pressed Reset here. Smart Lanes leaves\nthis junction alone when you build next to it. The Smart lanes\nbutton gives it smart lanes again.\nCustom lanes: set some other way: by hand (Crossing Tool), before\nthe mod was added, or the junction's traffic lights were switched\non or off since. The Smart lanes button sets smart lanes.\nGame or custom lanes: not smart lanes yet. The Smart lanes button\nsets them.\nNot handled: Smart Lanes has no rule for this junction. Why:\nin the selection box. The game's lanes stay as they are.")

-- Muted text (the previous traffic recording under the current one): the base NeutralMedium grey (default_colors.gres,
-- gray50) inline, as the badge colours below (meta.styleSheet, styleutil.makeStyle; no stylesheet rule, rule cap). The
-- base has no muted TextView class (default.css.lua: positive / negative / warning / error / info / success only); the
-- tool info block's text is NeutralVeryLight (gray80). Unverified in game, as the badge colour: that the inline colour
-- wins over the disabled button's text rule (TESTING.md "TR" step 8).
local mutedStyleCache = nil
local function mutedStyle()
	if mutedStyleCache == nil then
		local ok, st = pcall(function()
			local colors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
			local styleutil = ug_require "::/gui/main/styleutil.tl"
			return styleutil.makeStyle{ color = colors.NeutralMedium }
		end)
		mutedStyleCache = ok and st or false
	end
	return mutedStyleCache or nil
end

-- Toolbar status chip: content of a disabled one-value Button (bulk_bulldozer.script.tl:1105-1140).
-- Returns a BoxLayout (a recipe child must be a layout) and re-renders itself from g.status /
-- EV_STATUS (the menu re-renders a param only when its value or definition changes).
local SmartLanesStatus = react.RegisterRecipe("SmartLanesStatus", perf:wrap("status_render", function(_param)
	local textState = react.useState({ head = g.status.head, detail = g.status.detail, extra = g.status.extra,
		muted = g.status.muted })
	local refSeen = react.useRef(g.status.version)
	local function take(head, detail, extra, muted)
		local old = textState:old()
		if head == nil or detail == nil then return end
		if old == nil or old.head ~= head or old.detail ~= detail or extraKey(old.extra, old.muted) ~= extraKey(extra, muted) then
			textState:set({ head = head, detail = detail, extra = extra, muted = muted })
		end
	end
	react.onEvent(EV_STATUS, function(_name, payload)
		if payload ~= nil then take(payload.head, payload.detail, payload.extra, payload.muted) end
	end)
	react.onStep(function()
		if g.status.version ~= refSeen:get() then
			refSeen:set(g.status.version)
			take(g.status.head, g.status.detail, g.status.extra, g.status.muted)
		end
	end)
	local t = textState:old()
	-- meta.tooltip on the TextViews (as base statistics_react_util.tl:67; not on the BoxLayout: no
	-- base example, and unknown recipe fields have crashed the game); the tooltip repeats the lines in full
	-- (they can be clipped) under a short explanation of the box
	local lines = { tostring(t.head), tostring(t.detail) }
	for _, l in ipairs(type(t.extra) == "table" and t.extra or {}) do lines[#lines + 1] = tostring(l) end
	local tip = STATUS_TIP .. "\n\n" .. table.concat(lines, "\n")
	local children = {
		builtin.TextView{ meta = { class = "font-scale-body", tooltip = tip }, text = t.head },
		builtin.TextView{ meta = { class = "font-scale-annotation", tooltip = tip }, text = t.detail },
	}
	-- the selected lit junction's Re-time lines (sl_toolcore C.retimeLines: measuring, or the last result there) and
	-- Record traffic's (C.recordLines); the extra lines listed in t.muted (the previous recording, to compare) in a
	-- dimmer grey (mutedStyle: inline, no stylesheet rule)
	local muted = {}
	for _, i in ipairs(type(t.muted) == "table" and t.muted or {}) do muted[i + 2] = true end
	for i = 3, #lines do
		children[#children + 1] = builtin.TextView{ meta = { class = "font-scale-annotation", tooltip = tip,
			styleSheet = muted[i] and mutedStyle() or nil }, text = lines[i] }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end))

-- Lane status badge: content of a second disabled one-value Button, the SmartLanesStatus pattern
-- (returns a BoxLayout, re-renders itself from g.badge / EV_BADGE). Colour from the game's global
-- TextView classes "positive" / "warning" (base gui/main/default.css.lua:12-22, used as
-- meta.class = "font-scale-body, positive" in line_react_util.tl:630 / vehicle_react_util.tl:424).
-- The disabled button's grey text rule (builtin.css.lua:268-275, overridden by the shared tool info
-- block in sl_tool.css.lua) hid those class colours, so the colour also goes inline (meta.styleSheet,
-- styleutil.makeStyle as Better Minimap): no stylesheet rules for it (docs/findings.md "Load crash
-- above ~200 mod stylesheet rules"). Unverified in game: that the inline colour wins over the class rule.
local BADGE_COLOR = { positive = "Positive", warning = "Warning" }
local badgeStyles = {}
local function badgeStyle(class)
	local name = class ~= nil and BADGE_COLOR[class] or nil
	if name == nil then return nil end
	if badgeStyles[name] == nil then
		local ok, st = pcall(function()
			local colors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
			local styleutil = ug_require "::/gui/main/styleutil.tl"
			return styleutil.makeStyle{ color = colors[name] }
		end)
		badgeStyles[name] = ok and st or false
	end
	return badgeStyles[name] or nil
end

local SmartLanesBadge = react.RegisterRecipe("SmartLanesBadge", perf:wrap("badge_render", function(_param)
	local badgeState = react.useState({ key = g.badge.key, label = g.badge.label, class = g.badge.class })
	local refSeen = react.useRef(g.badge.version)
	local function take(key, label, class)
		if label == nil then return end
		local old = badgeState:old()
		if old == nil or old.key ~= key or old.label ~= label or old.class ~= class then
			badgeState:set({ key = key, label = label, class = class })
		end
	end
	react.onEvent(EV_BADGE, function(_name, payload)
		if payload ~= nil then take(payload.key, payload.label, payload.class) end
	end)
	react.onStep(function()
		if g.badge.version ~= refSeen:get() then
			refSeen:set(g.badge.version)
			take(g.badge.key, g.badge.label, g.badge.class)
		end
	end)
	local b = badgeState:old()
	local class = "font-scale-body"
	if b.class ~= nil then class = class .. ", " .. b.class end
	-- just the state (the user dropped the 2026-10-08 "Current lanes: " prefix, 2026-10-11); nothing
	-- with nothing selected (the status line above already gives the pick hint)
	if b.label == nil or b.key == "none" then
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = {} }
	end
	local tip = BADGE_TIP .. "\n\n" .. b.label
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.TextView{ meta = { class = class, tooltip = tip, styleSheet = badgeStyle(b.class) }, text = b.label },
		},
	}
end))

-- A toolbar button's content (makeCompactButtonFn): its label in a BoxLayout so the bar's 50 px TextView rule
-- (construction.css.lua:820-823) does not clip it (bulk_bulldozer.script.tl:1141-1150), with a tooltip that says
-- why the button is grayed (or what it does here) above the button's own text. The param's own tooltip can't
-- change at runtime (construction.tl:1064-1079: a ref set from param.tooltip, re-read only when the param's
-- ParamForUi changes), but this content is our recipe, so its TextView's meta.tooltip can (polled every step from
-- sl_toolcore C.buttonTip). Unverified in game: that a TextView inside a disabled button shows its tooltip (the base
-- shows tooltips on disabled widgets themselves, mod_manager_react_util.tl:5943-5947; TESTING.md "Toolbar rows").
local SmartLanesButton = react.RegisterRecipe("SmartLanesButton", function(param)
	-- "" = no dynamic part (a state never holds nil here)
	local function current()
		if g.core == nil then return "" end
		local ok, t = pcall(g.core.buttonTip, param.which)
		if ok and type(t) == "string" then return t end
		return ""
	end
	local tipState = react.useState(current())
	react.onStep(function()
		local t = current()
		if t ~= tipState:old() then tipState:set(t) end
	end)
	local dyn = tipState:old()
	local tip = param.tip
	if dyn ~= nil and dyn ~= "" then tip = dyn .. "\n\n" .. tostring(param.tip) end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { builtin.TextView{ meta = { class = "font-scale-body", tooltip = tip }, text = param.label } },
	}
end)

-- checkEnabledFn of a toolbar button (which = "apply" | "reset" | "lights" | "retime"). The menu calls it every
-- step (construction.tl:1584-1597, onStep 1901-1925) in this Lua state, as the Overpass mod's Build button reads
-- its recipe's flag (bulk bulldozer research.md §131). "Hidden" where it has nothing to do (row 1 where it would
-- change nothing, row 2 away from a lit junction), "Disabled" (grayed, the reason in its tooltip: SmartLanesButton)
-- when it can't act right now,
-- else "Enabled" (sl_toolcore C.buttons / C.paramState). The menu re-lays the bar only when a result changes
-- (updateDisabledParams deepEquals); the results follow the selection, Re-time and pending writes, never the
-- hover. No core yet (tool never opened) = nothing selected.
local function stateOf(which)
	return function(_params)
		if g.core == nil then return "Hidden" end
		local ok, st = pcall(g.core.paramState, which)
		if ok and (st == "Enabled" or st == "Disabled") then return st end
		return "Hidden"
	end
end

--- The "Keep timing adjusted" toggle shows the selected junction's enrolled state from the first frame. The base
-- toggle (like a CheckBox) shows getStoredValues(category)[key], re-read every step (construction.tl:1044-1051,
-- 1081-1084), and only onChangeFn hands us the menu's params api (onChangeFn's second argument, construction.tl:1885;
-- checkEnabledFn gets none), so before the first click nothing can set it (docs/findings/gui.md "A CheckBox param's
-- shown value can be set by the mod"). Twin params with the same label, values and row: KEY_AUTO_ON (default Yes) is
-- shown at an enrolled junction, KEY_AUTO_OFF (default No) at one that is not, the other "Hidden" (a hidden param
-- leaves no row or gap, and its value is dropped from the current values: the tool's action never reads these keys).
-- Before any click each shows its default, which is the truth by construction. From the first click on (g.paramsApi)
-- both stored values follow the enrolled state every step, so a twin clicked earlier never shows a stale side.
local function syncAutoToggles(want)
	local pa = g.paramsApi
	if pa == nil then return end
	pcall(function()
		local stored = pa.getStoredValues(pa.getCategory())
		if type(stored) ~= "table" then return end
		if stored[KEY_AUTO_ON] ~= want then stored[KEY_AUTO_ON] = want end
		if stored[KEY_AUTO_OFF] ~= want then stored[KEY_AUTO_OFF] = want end
	end)
end

--- checkEnabledFn of a twin (on = true: KEY_AUTO_ON, shown at an enrolled junction).
local function autoTwin(on)
	return function(_params)
		if g.core == nil then return "Hidden" end
		local ok, st = pcall(g.core.paramState, "auto")
		if not ok or (st ~= "Enabled" and st ~= "Disabled") then return "Hidden" end
		local okC, enrolled = pcall(g.core.autoChecked)
		enrolled = okC and enrolled == true
		syncAutoToggles(enrolled and 1 or 2)
		if enrolled ~= on then return "Hidden" end
		return st
	end
end

local function fire(name, payload)
	pcall(api.gui.fireReactEvent, name, payload or {})
end

-- An action button (Smart lanes, Reset, Smart lights, Re-time, Record traffic). Small look (user 2026-10-16: "all
-- buttons the size of Keep timing adjusted"), base widgets only, no stylesheet rule: `numbers = { 1 }` makes the menu
-- draw the one value as a base ToggleButtonGroup with one button (script_param_util.tl:440: a group when
-- numChoices > 1 or numbers ~= nil), the widget of the Yes / No toggle, instead of a lone ToggleButton. The bar's
-- 32 x 32 px minimum (construction.css.lua:817-819) is a rule on `ToggleButton!right-parameters`; in a group that
-- class sits on the group, not on its button, so the button is as tall as its text plus the bar's 4 px padding
-- (814-816; the Yes / No toggle's 0 px comes from 804-807, which needs the param's label wrap). The value stays 1
-- (getParamDefaultValue: numbers[defaultIndex]); a click on the one (selected) button still reaches onChangeFn
-- (builtin.lua ToggleButtonGroup: every ToggleButton click calls onValueChange with its index). The content stays
-- SmartLanesButton (its label unclipped, the grayed reason in its tooltip). Unverified in game (TESTING.md "Toolbar
-- rows").
local function actionButton(key, label, tooltip, event, group, which)
	return {
		key = key,
		name = label,
		tooltip = tooltip,
		values = { label },
		numbers = { 1 },
		defaultIndex = 1,
		hideLabel = true,
		group = group,
		uiType = api.type.enum.ScriptParamType.Button,
		yearFrom = 0,
		yearTo = 0,
		location = api.type.enum.ScriptParamLocation.Toolbar,
		makeCompactButtonFn = function(_value) return SmartLanesButton{ which = which, label = label, tip = tooltip } end,
		-- every click runs onChangeFn, also with an unchanged value (construction.tl:1866-1898)
		onChangeFn = function(_newValue, _api, _oldValue) fire(event) end,
		checkEnabledFn = stateOf(which),
	}
end

--- One twin of the "Keep timing adjusted" toggle (autoTwin): values Yes / No, default `def`, shown when the
-- selected lit junction's enrolled state is `on`.
local function autoToggle(key, def, on)
	return {
		key = key,
		name = _("Keep timing adjusted"),
		tooltip = _("Adjusts this junction's light phase lengths now and then, also\nwith the tool closed. Every 2 game minutes Smart Lanes counts the\ncars waiting on each road; after about 16 minutes of counts it\ngives more green to the roads where cars keep waiting, at most\nevery 10 minutes, less often while the timing fits. Only the\nlengths change, never which lanes are green; the cycle moves by\nat most 20 s per change. Never while you build nearby. Phases you\nedit by hand become the new base. Choose No to stop; Reset brings\nback the game's phases. Shown at a junction with traffic lights."),
		values = { _("Yes"), _("No") },
		-- the 1-based value itself (script_param_util.tl getScriptParamDefaultValue: no numbers -> defaultIndex)
		defaultIndex = def,
		group = GROUP_AUTO,
		uiType = api.type.enum.ScriptParamType.Button,
		yearFrom = 0,
		yearTo = 0,
		location = api.type.enum.ScriptParamLocation.Toolbar,
		onChangeFn = function(newValue, paramsApi, _oldValue)
			if paramsApi ~= nil then g.paramsApi = paramsApi end
			fire(EV_AUTO, { value = newValue })
		end,
		checkEnabledFn = autoTwin(on),
	}
end

-- The settings panel (sl_settingsui.lua, PLAN.md "In-game settings panel"). A toggle value's button content: its label
-- in a BoxLayout (the bar's 50 px TextView rule would clip "Désactivé"), with the param's tooltip.
local function settingContent(label, tip)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { builtin.TextView{ meta = { class = "font-scale-body", tooltip = tip }, text = label } },
	}
end

--- The panel's params for the Smart Lanes tool (src "tool": shown with nothing selected; Automatic light timing through
-- the controller, so its mirror and result line follow at once) or the Crossing Tool (src "crossing": always shown).
local function settingsParams(src)
	local opts = { src = src, content = settingContent, emit = out }
	if src == "tool" then
		opts.shown = function() return g.core == nil or g.core.sel == nil end
		opts.setLightMode = function(mode)
			if g.core ~= nil then
				g.core.setLightMode(mode)
			elseif not SettingsUI.send(api, { op = "mode", mode = mode, src = "tool" }) then
				error("send")
			end
		end
	end
	return SettingsUI.params(api, opts)
end

-- The base Crossing Tool gets the same panel: construction.tl:4279-4287 collects the menu's definitions through
-- construction_react_util.forEachDefinition (the module table, once per menu mount), so a wrapper there inserts our
-- params into the ACTION_LANE_MODIFIER_TOOL definition (before Underground; SettingsUI.insertInto: idempotent, the
-- function in place at install kept in the chain, as Better Bus Overlay's). Installed at this script's load (as the
-- one-way arrows above, verified in game) and by doReplace (sl_settings_replace.res.lua, a react-replacement-config:
-- before any recipe runs), once per module table. Log: SETTINGS op=menu where=crossing_tool result=inserted|present
-- (once per result and Lua state), SETTINGS op=patch result=installed|already|missing (debug log only).
local menuLogged = {}
local function patchCrossingToolSettings()
	local res = SettingsUI.wrapForEach(constructionUi, function() return settingsParams("crossing") end, function(r)
		if menuLogged[r] then return end
		menuLogged[r] = true
		emit("SETTINGS", { { "op", "menu" }, { "where", "crossing_tool" }, { "result", r } })
	end)
	if res ~= "already" and sqperf.readParam(Rules.MOD_ID, "sqperf_log") then
		emit("SETTINGS", { { "op", "patch" }, { "result", res } })
	end
	return res
end
pcall(patchCrossingToolSettings)

local M = {
	-- react-replacement-config (sl_settings_replace.res.lua): the Crossing Tool wrapper before any recipe runs
	doReplace = function(_replacementApi)
		pcall(patchCrossingToolSettings)
	end,
	getDefinition = perf:wrap("get_definition", function(constructionDefinition, _repository, _params)
		local params = {
			actionButton(KEY_APPLY, _("Smart lanes"),
				_("Set smart lanes on the selection: a junction (roundabout junction,\ncrossroads, T-junction, slip-lane junction or lane drop), the whole\nroundabout (clicked between its junctions), a street (clicked between\njunctions: its end junctions) or junctions added with Shift+click.\nShown when there is something to change; grayed out while a change\nis landing."), EV_APPLY, GROUP_ACTIONS, "apply"),
			actionButton(KEY_RESET, _("Reset"),
				_("Back to the game's own lane connections for the selected junction\n(or the whole roundabout when a roundabout is selected).\nOn a slip-lane junction or lane drop: back to the lanes it had\nbefore you first set smart lanes there.\nAt roundabouts and ramps the game decides on traffic lights again.\nOn a street or several junctions (Shift+click): each as above.\nSmart Lanes leaves a reset junction alone when you build next to it.\nThe Smart lanes button gives it smart lanes again.\nWith traffic lights it also brings back the game's light phases.\nShown when there is something to reset; grayed out while a change\nis landing."), EV_RESET, GROUP_ACTIONS, "reset"),
			-- the light buttons in a second row, shown only at a junction with a standing traffic light: base Buttons
			-- like Smart lanes and Reset (no new style)
			actionButton(KEY_LIGHTS, _("Smart lights"),
				_("New Smart Lanes light phases for the lanes as they are now\n(also lanes you changed with the Crossing Tool). The lanes stay.\nWorks whatever the \"Light phases\" setting says. Reset brings\nback the game's phases. Shown at a crossroads or T-junction with\ntraffic lights (other junctions keep the game's phases); hidden\nonce its phases are on (the lane status says so)."), EV_LIGHTS, GROUP_LIGHTS, "lights"),
			actionButton(KEY_RETIME, _("Re-time"),
				_("Measures the traffic at the selected junction for about\n3 game minutes, then sets its cycle and the lengths of its light\nphases: a longer cycle where cars queue, more green where more\ncars pass. Which lanes are green in each phase stays as it is.\nThe measurement goes on when you select something else or\nclose the tool; click again at that junction to cancel.\nReset brings back the game's phases.\nShown at a junction with traffic lights."), EV_RETIME, GROUP_LIGHTS, "retime"),
			autoToggle(KEY_AUTO_ON, 1, true),
			autoToggle(KEY_AUTO_OFF, 2, false),
		}
		local infoParam = {
			-- info block: a disabled one-value Button (the menu draws every toolbar param as a
			-- button; sl_tool.css.lua makes this one plain text) holding the selection and result
			-- (SmartLanesStatus) and the lane status under it (SmartLanesBadge). Its checkEnabledFn
			-- runs on every activation and change and nudges the recipes to sync
			-- (bulk_bulldozer.script.tl:1166-1174, 1300-1303).
			key = KEY_INFO,
			name = _("Selection"),
			tooltip = STATUS_TIP,
			values = { _("Selection") },
			defaultIndex = 1,
			hideLabel = true,
			group = GROUP_INFO,
			uiType = api.type.enum.ScriptParamType.Button,
			yearFrom = 0,
			yearTo = 0,
			location = api.type.enum.ScriptParamLocation.Toolbar,
			makeCompactButtonFn = function(_value)
				return builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = { SmartLanesStatus{}, SmartLanesBadge{} },
				}
			end,
			onChangeFn = function(_newValue, _api, _oldValue) end,
			checkEnabledFn = function(_p)
				fire(EV_SHOWN)
				return "Disabled"
			end,
		}
		-- the settings panel (sl_settingsui.lua), shown with nothing selected, above the info block
		for _i, p in ipairs(settingsParams("tool")) do params[#params + 1] = p end
		-- the last row above the info block: Record traffic at any selected real junction or roundabout (never shown with
		-- the settings panel, which is shown only with nothing selected)
		params[#params + 1] = actionButton(KEY_RECORD, _("Record traffic"),
			_("Counts the vehicles passing the selected junction for up to\n20 game minutes (a roundabout selected between its junctions:\nthe vehicles entering it). The info below shows vehicles per\nminute over the last 3 minutes and over the whole recording.\nIt goes on when you select something else or close the tool;\nclick again at that junction to stop. Up to 20 junctions can\nrecord at once. The last result of each junction is kept with\nthe save and shown when you select it again. Changes nothing\nat the junction."), EV_RECORD, GROUP_RECORD, "record")
		params[#params + 1] = infoParam
		return {
			resName = constructionDefinition,
			name = _("Smart Lanes"),
			-- shown in the menu's info callout, which wraps it (construction.css.lua:534-539
			-- textAutoWrap, 540 px): no "\n" breaks, it is not a tooltip
			description = _("Set the lane connections of roundabouts, slip-lane junctions, crossroads and lane drops: click a junction, a roundabout or a road and press Smart lanes. Shift+click adds more junctions or roads. Reset brings back the game's own connections. Right-click or Esc clears the selection."),
			-- own icons next to this file; the game loads the @2x files (sl_tool@2x.tga 240x150,
			-- sl_tool_preview@2x.tga 720x405, the sizes of the Crossing Tool's lane_control icons),
			-- rendered by tools/render_icon_square_smart_lanes.py
			icon = { icon = resolve("sl_tool.tga") },
			previewIcon = { icon = resolve("sl_tool_preview.tga") },
			availability = { yearFrom = 0, yearTo = 0 },
			action = "ACTION_CUSTOM",
			-- UG erases the generic at this boundary (bulk_bulldozer.script.tl:1152-1154)
			customAction = { recipe = SmartLanesAction, customParam = nil },
			constructions = {},
			categories = {},
			params = params,
			menuCategory = {
				categories = {
					{ category = "roads_tools", order = MENU_ORDER },
				},
			},
		}
	end),
}

function data()
	return M
end

perf:phase("init", perfInit)
