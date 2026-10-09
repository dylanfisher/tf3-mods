-- Smart Lanes road tool (Phase 2 step 1): Roads -> Tools, right after the Crossing Tool.
-- Hover a junction (or a roundabout between its junctions), click to select it, see its lane
-- connections and press Apply / Reset. plans/square_smart_lanes/PLAN.md "Phase 2".
--
-- Wiring (as mods/square_bulk_bulldozer bulk_bulldozer.script.tl, a working mod tool):
-- sl_tool.res.lua -> getDefinition below -> ACTION_CUSTOM with the SmartLanesAction recipe; the
-- construction menu mounts it while the entry is selected (construction.tl:401-436) and the recipe
-- hands the world layer to param.setActionFn. The world layer is an ActionDescriptor with a
-- builtin.Selector (onHover / onSelect / onProcessMouseEvent, builtin.d.tl:1392-1415), a
-- builtin.NodeViewer for the selected junction's connections (double_slip_switch.tl:87-143, 185-199),
-- one EdgeRenderable with circle markers and an ActionTooltip.
-- Toolbar values reach the recipe through onChangeFn -> api.gui.fireReactEvent -> react.onEvent
-- (getDefinition may run in another Lua state than the recipe; bulk bulldozer research §6, §12).
-- All logic (picking, apply, reset, re-reads) is in sl_toolcore.lua, tested offline.
--
-- Exports through data() like every .script.lua of this mod (memory: `return M` alone fails in game).

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local constructionUi = ug_require "::/gui/construction/construction_react_util.tl"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local Core = ug_require "square_smart_lanes::/smart_lanes/sl_toolcore.lua"

local EV_SHOWN = "SmartLanes.shown"
local EV_APPLY_NODE = "SmartLanes.applyNode"
local EV_APPLY_RING = "SmartLanes.applyRing"
local EV_RESET = "SmartLanes.reset"
local EV_STATUS = "SmartLanes.status"
local EV_BADGE = "SmartLanes.badge"
local KEY_APPLY_NODE = "sqrl_tool_apply_node"
local KEY_APPLY_RING = "sqrl_tool_apply_ring"
local KEY_RESET = "sqrl_tool_reset"
local KEY_STATUS = "sqrl_tool_status"
local KEY_BADGE = "sqrl_tool_badge"
local GROUP_APPLY = "sqrl_tool_apply" -- the two Apply buttons share a row
local GROUP_RESET = "sqrl_tool_reset" -- Reset on its own row (three in one row clipped the labels)
local GROUP_BADGE = "sqrl_tool_badge" -- lane status badge in its own row under the status chip

-- Menu position: the Crossing Tool is roads_tools order 1200, nothing sits between 1200 and 1250
-- (base tools: tram 100, bus lane 200, crosswalk 300, player owned 1000, traffic light 1100).
-- Bus lane and traffic light are year-gated; while they are hidden the menu's isActionActive
-- index check (construction.tl:758-760, 427) mismatches. In mouse mode that only makes abort()
-- a no-op (construction.tl:315-328); gamepad mode may misbehave (bulk bulldozer research §1).
local MENU_ORDER = 1250
local RMB_CLICK_MAX_PX = 16 -- a right click that moved further is a camera drag

local function T(s)
	if _ ~= nil then return _(s) end
	return s
end

local function out(kind, fields)
	local text = Rules.line(kind, fields)
	pcall(function() log.message(text) end)
end

-- File-scope state of this Lua state (the recipe's). Reset when the tool is closed.
local g = {
	core = nil,
	layout = "turbo", -- the one layout the tool applies ("Smart lanes", sl_rules.LAYOUTS)
	status = { head = "Nothing selected", detail = "Layout: Matched lanes", version = 0 },
	badge = { label = Pick.BADGE_NONE.label, class = nil, version = 0 }, -- lane status badge
	nvKey = nil,       -- selection the NodeViewer probe line was logged for
	activations = 0,
}

local function core()
	if g.core == nil then g.core = Core.new(api, out, os.clock) end
	return g.core
end

local function publishStatus(st)
	if st.head == g.status.head and st.detail == g.status.detail then return end
	g.status = { head = st.head, detail = st.detail, version = g.status.version + 1 }
	pcall(api.gui.fireReactEvent, EV_STATUS, g.status)
end

local function publishBadge(b)
	if b == nil then return end
	if b.label == g.badge.label and b.class == g.badge.class then return end
	g.badge = { label = b.label, class = b.class, version = g.badge.version + 1 }
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
	out("PROBE", { { "oneway", "patched" } })
end
pcall(patchCrossingToolArrows)

local MARKER_COLORS = {
	sel = { 0.20, 0.80, 0.75, 0.95 },
	ring = { 0.20, 0.80, 0.75, 0.6 },
	hover = { 1, 1, 1, 0.8 },
}

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

local SmartLanesAction = react.RegisterRecipe("SmartLanesAction", function(param)
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
		local ok, e = pcall(fn)
		if not ok then out("ERROR", { { "where", what }, { "err", e } }) end
		sync()
	end
	react.onEvent(EV_APPLY_NODE, function()
		act("apply_node", function() core().apply("node", g.layout) end)
	end)
	react.onEvent(EV_APPLY_RING, function()
		act("apply_ring", function() core().apply("ring", g.layout) end)
	end)
	react.onEvent(EV_RESET, function()
		act("reset", function()
			local s = core().sel
			core().reset((s ~= nil and s.kind == "node") and "node" or "ring")
		end)
	end)

	react.onStep(function()
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
		local _v = versionState:old() -- re-render on changes
		local c = core()
		local children = {
			builtin.Selector{
				filter = function(entity)
					return isStreetThing(entity)
				end,
				onHover = function(entity, _i, _d)
					c.onHover(entity, cursor())
				end,
				onSelect = function(entity, _i, _d)
					c.select(entity, cursor())
					sync()
					return true -- swallow the click: no entity window
				end,
				onProcessMouseEvent = onMouse,
				selectionColor = vec4(MARKER_COLORS.sel, 0.35),
				selectionOutlineColor = vec4(MARKER_COLORS.sel, 0.7),
				selectionOutlineColor1 = vec4(MARKER_COLORS.sel, 0.9),
			},
		}
		local ents, markers = {}, {}
		local okH, e1, m1 = pcall(c.highlight)
		if okH then ents, markers = e1, m1 else out("ERROR", { { "where", "highlight" }, { "err", e1 } }) end

		local nv = nodeViewer(c)
		if nv ~= nil then children[#children + 1] = nv end

		if #markers > 0 then
			local okM, edges = pcall(function()
				local list = {}
				for _, m in ipairs(markers) do list[#list + 1] = circleEdge(m, vec4(MARKER_COLORS[m.kind] or MARKER_COLORS.hover)) end
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
			if c.hover.badge ~= nil then text = text .. "\nLanes: " .. c.hover.badge.label end
			if c.sel == nil or Pick.targetKey(c.sel) ~= Pick.targetKey(c.hover) then
				text = text .. "\nClick to select"
			end
			children[#children + 1] = builtin.ActionTooltip{
				recipe = constructionUi.SimpleTooltipRecipe,
				param = { message = { message = text } },
			}
		end

		return builtin.ActionDescriptor{
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
end)

-- Hover texts of the two grey read-only boxes (also the params' own tooltips).
local STATUS_TIP = T("Selection: the junction or roundabout you clicked, and the result\nof the last Apply or Reset. Right-click or Esc clears the selection.")
local BADGE_TIP = T("Current lanes: what the selected junction or roundabout has now.\nSmart lanes: what Apply sets.\nGame default: the game's own lane connections.\nCustom lanes: anything else (Crossing Tool, older settings).\nCustom: a slip-lane junction without the rule.\nNot handled: the tool has no rule for this junction.")

-- Toolbar status chip: content of a disabled one-value Button (bulk_bulldozer.script.tl:1105-1140).
-- Returns a BoxLayout (a recipe child must be a layout) and re-renders itself from g.status /
-- EV_STATUS (the menu re-renders a param only when its value or definition changes).
local SmartLanesStatus = react.RegisterRecipe("SmartLanesStatus", function(_param)
	local textState = react.useState({ head = g.status.head, detail = g.status.detail })
	local refSeen = react.useRef(g.status.version)
	local function take(head, detail)
		local old = textState:old()
		if head == nil or detail == nil then return end
		if old == nil or old.head ~= head or old.detail ~= detail then
			textState:set({ head = head, detail = detail })
		end
	end
	react.onEvent(EV_STATUS, function(_name, payload)
		if payload ~= nil then take(payload.head, payload.detail) end
	end)
	react.onStep(function()
		if g.status.version ~= refSeen:get() then
			refSeen:set(g.status.version)
			take(g.status.head, g.status.detail)
		end
	end)
	local t = textState:old()
	-- meta.tooltip on the TextViews (as base statistics_react_util.tl:67; not on the BoxLayout: no
	-- base example, and unknown recipe fields have crashed the game); the tooltip repeats both lines in full
	-- (they can be clipped) under a short explanation of the box
	local tip = STATUS_TIP .. "\n\n" .. tostring(t.head) .. "\n" .. tostring(t.detail)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.TextView{ meta = { class = "font-scale-body", tooltip = tip }, text = t.head },
			builtin.TextView{ meta = { class = "font-scale-annotation", tooltip = tip }, text = t.detail },
		},
	}
end)

-- Lane status badge: content of a second disabled one-value Button, the SmartLanesStatus pattern
-- (returns a BoxLayout, re-renders itself from g.badge / EV_BADGE). Colour from the game's global
-- TextView classes "positive" / "warning" (base gui/main/default.css.lua:12-22, used as
-- meta.class = "font-scale-body, positive" in line_react_util.tl:630 / vehicle_react_util.tl:424).
-- Unverified in game: builtin.css.lua:268-275 greys TextViews of disabled buttons; which rule
-- wins there is unknown (worst case the badge is grey like the status chip).
local SmartLanesBadge = react.RegisterRecipe("SmartLanesBadge", function(_param)
	local badgeState = react.useState({ label = g.badge.label, class = g.badge.class })
	local refSeen = react.useRef(g.badge.version)
	local function take(label, class)
		if label == nil then return end
		local old = badgeState:old()
		if old == nil or old.label ~= label or old.class ~= class then
			badgeState:set({ label = label, class = class })
		end
	end
	react.onEvent(EV_BADGE, function(_name, payload)
		if payload ~= nil then take(payload.label, payload.class) end
	end)
	react.onStep(function()
		if g.badge.version ~= refSeen:get() then
			refSeen:set(g.badge.version)
			take(g.badge.label, g.badge.class)
		end
	end)
	local b = badgeState:old()
	local class = "font-scale-body"
	if b.class ~= nil then class = class .. ", " .. b.class end
	-- "Current lanes: <state>" so it reads as a readout, not a button (user, 2026-10-08)
	local text = (b.label == nil or b.label == "Lane status") and "Current lanes: select a junction"
		or ("Current lanes: " .. b.label)
	local tip = BADGE_TIP .. "\n\n" .. text
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.TextView{ meta = { class = class, tooltip = tip }, text = text },
		},
	}
end)

-- Label in a BoxLayout so the bar's 50 px TextView rule (construction.css.lua:820-823) does not
-- clip it (bulk_bulldozer.script.tl:1141-1150).
local function buttonLabel(label)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { builtin.TextView{ meta = { class = "font-scale-body" }, text = label } },
	}
end

-- checkEnabledFn of an action button (which = "applyNode" | "applyRing" | "reset"). The menu calls
-- it every step (construction.tl:1584-1597, onStep 1901-1925) in this Lua state, as the Overpass
-- mod's Build button reads its recipe's flag (bulk bulldozer research.md §131); "Disabled" greys
-- the button and ignores clicks. Enabled only when the click would change the selection
-- (sl_toolcore C.actions); no core yet (tool never opened) = nothing selected.
local function enabledWhen(which)
	return function(_params)
		if g.core == nil then return "Disabled" end
		local ok, a = pcall(g.core.actions)
		if ok and a[which] then return "Enabled" end
		return "Disabled"
	end
end

local function fire(name, payload)
	pcall(api.gui.fireReactEvent, name, payload or {})
end

local function actionButton(key, label, tooltip, event, group, which)
	return {
		key = key,
		name = label,
		tooltip = tooltip,
		values = { label },
		defaultIndex = 1,
		hideLabel = true,
		group = group,
		uiType = api.type.enum.ScriptParamType.Button,
		yearFrom = 0,
		yearTo = 0,
		location = api.type.enum.ScriptParamLocation.Toolbar,
		makeCompactButtonFn = function(_value) return buttonLabel(label) end,
		-- every click runs onChangeFn, also with an unchanged value (construction.tl:1866-1898)
		onChangeFn = function(_newValue, _api, _oldValue) fire(event) end,
		checkEnabledFn = enabledWhen(which),
	}
end

local M = {
	getDefinition = function(constructionDefinition, _repository, _params)
		local params = {
			actionButton(KEY_APPLY_NODE, T("Apply to junction"),
				T("Set smart lanes on the selected junction only:\nlanes matched one to one, and an exit-only outer lane\nwhere every exit of the roundabout has two or more lanes.\nOn a slip-lane junction: lanes matched one to one, no crossings.\nGreyed out when the junction already has smart lanes."), EV_APPLY_NODE, GROUP_APPLY, "applyNode"),
			actionButton(KEY_APPLY_RING, T("Apply to roundabout"),
				T("Set smart lanes on every junction of the selected roundabout.\nGreyed out when all of them already have smart lanes."), EV_APPLY_RING, GROUP_APPLY, "applyRing"),
			actionButton(KEY_RESET, T("Reset"),
				T("Back to the game's own lane connections for the selected junction (or the whole roundabout when a roundabout is selected).\nOn a slip-lane junction: back to the lanes it had before your first Apply there.\nGreyed out when there is nothing to reset."), EV_RESET, GROUP_RESET, "reset"),
			{
				-- status chip: a disabled one-value Button whose content is SmartLanesStatus. Its
				-- checkEnabledFn runs on every activation and change and nudges the recipe to sync
				-- (bulk_bulldozer.script.tl:1166-1174, 1300-1303).
				key = KEY_STATUS,
				name = T("Selection"),
				tooltip = STATUS_TIP,
				values = { T("Selection") },
				defaultIndex = 1,
				hideLabel = true,
				uiType = api.type.enum.ScriptParamType.Button,
				yearFrom = 0,
				yearTo = 0,
				location = api.type.enum.ScriptParamLocation.Toolbar,
				makeCompactButtonFn = function(_value) return SmartLanesStatus{} end,
				onChangeFn = function(_newValue, _api, _oldValue) end,
				checkEnabledFn = function(_p)
					fire(EV_SHOWN)
					return "Disabled"
				end,
			},
			{
				-- lane status badge: what lanes the selection has now (sl_pick.badge)
				key = KEY_BADGE,
				name = T("Lane status"),
				tooltip = BADGE_TIP,
				values = { T("Lane status") },
				defaultIndex = 1,
				hideLabel = true,
				group = GROUP_BADGE,
				uiType = api.type.enum.ScriptParamType.Button,
				yearFrom = 0,
				yearTo = 0,
				location = api.type.enum.ScriptParamLocation.Toolbar,
				makeCompactButtonFn = function(_value) return SmartLanesBadge{} end,
				onChangeFn = function(_newValue, _api, _oldValue) end,
				checkEnabledFn = function(_p)
					fire(EV_SHOWN)
					return "Disabled"
				end,
			},
		}
		return {
			resName = constructionDefinition,
			name = T("Smart Lanes"),
			description = T("Set the lane connections of a roundabout or a slip-lane junction: click a junction or a roundabout and press Apply. Reset brings back the game's own connections. Right-click or Esc clears the selection."),
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
	end,
}

function data()
	return M
end
