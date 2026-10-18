-- pm_hud.lua (Photo Mode: Hide labels, Hide UI, the tour's window hiding) on a fake api / react. The base HUD
-- filter is GUI save data key "" field hudFilter (base gui/layers/layer_hud_filter.tl).

local hud, fake

local CT = { GAME_SPEED = "GAME_SPEED", STATION_GROUP = 4, INDUSTRY = 5, WAREHOUSE = 12, TOWN = 13, SUBCONSTRUCTION = 14, TRANSPORT_VEHICLE = 1 }
local CARRIER = { ROAD = 0, RAIL = 1, TRAM = 2, AIR = 3, WATER = 4 }

local PLAYER_FILTER = { preFilters = { [CT.TOWN] = "Hidden" }, preFilterTvCarriers = {}, showCosts = true,
	showIncome = false, showEventIcons = true, showCargoFlow = true }

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

before_each(function()
	reset_modules()
	fake = { save = { [""] = { hudFilter = copy(PLAYER_FILTER), other = 5 } }, visible = {}, events = {}, now = 0,
		view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }, mouse = { x = 10, y = 10 }, speed = 1 }
	set_global("api", {
		engine = {
			util = { getWorld = function() return 1 end },
			getComponent = function(e, t) if t == "GAME_SPEED" then return { speedup = fake.speed } end return nil end,
		},
		type = {
			ComponentType = CT,
			enum = { Carrier = CARRIER },
			Clock = { new = function() return { getTime = function() return fake.now * 1e6 end } end },
		},
		gui = {
			game = {
				getGuiSaveData = function(k) return copy(fake.save[k]) end,
				setGuiSaveData = function(k, d) fake.save[k] = copy(d) end,
			},
			byId = { setVisible = function(id, on) fake.visible[id] = on end },
			-- round 14 / 15: base react events (game.tl:160-169, :401) as the game handles them
			fireReactEvent = function(name, param)
				fake.reactEvents = fake.reactEvents or {}
				fake.reactEvents[#fake.reactEvents + 1] = name
				if name == "disableToolActions" then fake.actionsDisabled = param end
				if name == "setSelectorEntityFilter" then fake.selectorFilter = param end
				if name == "setDisableFeatures" then fake.features = param end
			end,
			mission = { getMission = function() return fake.mission end },
			camera = { getCameraData = function() local v = fake.view return { x = v.x, y = v.y, z = v.z, w = v.w, q = v.q } end },
			mouse = {
				hasTerrainPosition = function() return fake.mouse ~= nil end,
				getTerrainPosition = function() return { x = fake.mouse.x, y = fake.mouse.y, z = 0 } end,
			},
		},
	})
	stub_module("::/gui/main/react.lua", { fireEvent = function(__, name) fake.events[#fake.events + 1] = name end })
	-- round 15: the game's disabled features (game.tl's ref, replaced by "setDisableFeatures")
	fake.features = {}
	stub_module("::/gui/main/game_react_globals.tl", { getDisableFeatures = function() return fake.features end,
		getDefaultToolStackApi = function() return nil end })
	hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
	hud.persist = function()
		local m = hud.saveMarker()
		fake.save["square_photo_mode"] = { v = 1, views = {}, hud = m }
	end
end)

local function steps(n, dt)
	for __ = 1, n do
		fake.now = fake.now + (dt or 0.016)
		if hud.busy() then hud.step() end
	end
end

test("Hide labels and hover: every filter off, the selector kept prevented (no hover); untick: all back", function()
	hud.setLabels(true)
	local f = fake.save[""].hudFilter
	eq(f.showCosts, false); eq(f.showCargoFlow, false)
	eq(f.preFilters[CT.STATION_GROUP], "Hidden"); eq(f.preFilterTvCarriers[CARRIER.RAIL], "Hidden")
	eq(fake.save[""].other, 5, "the rest of the base save data kept")
	eq(fake.events, { "preventReactSelector" })
	steps(30)
	eq(fake.events, { "preventReactSelector" }, "stays prevented while hidden: no hover, no entity tooltips")
	eq(hud.busy(), false, "nothing runs per frame while hidden")
	ok(fake.save["square_photo_mode"].hud.hidden, "our safety net in our own save data")
	hud.reassertHidden()
	eq(fake.events, { "preventReactSelector", "preventReactSelector" }, "fired again (a remounted selector)")
	hud.setLabels(false)
	eq(fake.save[""].hudFilter, PLAYER_FILTER, "exactly the player's filter")
	eq(fake.save["square_photo_mode"].hud, nil)
	eq(fake.events[#fake.events], "allowReactSelector", "hover back with the labels")
	hud.reassertHidden()
	eq(fake.events[#fake.events], "allowReactSelector", "nothing fired while shown")
end)

test("a player without a filter gets none back; a filter changed meanwhile is kept", function()
	fake.save[""].hudFilter = nil
	hud.setLabels(true)
	hud.setLabels(false)
	eq(fake.save[""].hudFilter, nil, "absent again")
	fake.save[""].hudFilter = copy(PLAYER_FILTER)
	hud.setLabels(true)
	fake.save[""].hudFilter.showIncome = true -- the player switched income back on in the HUD filter window
	local mine = copy(fake.save[""].hudFilter)
	hud.setLabels(false)
	eq(fake.save[""].hudFilter, mine, "theirs stays")
end)

test("the pause menu brings labels, UI and window back", function()
	hud.setLabels(true)
	hud.hideUi()
	hud.tourHide(true, true)
	eq(fake.visible["react.game-ui-root"], false)
	eq(fake.visible[hud.WINDOW_ID], false)
	hud.pauseMenu()
	eq(fake.save[""].hudFilter, PLAYER_FILTER)
	eq(fake.visible["react.game-ui-root"], true)
	eq(fake.visible[hud.WINDOW_ID], true)
	eq(fake.events[#fake.events], "allowReactSelector", "the selector is never left prevented")
	eq(hud.busy(), false)
end)

test("a save made while hidden gets its labels back on the next load", function()
	hud.setLabels(true)
	local saved = copy(fake.save)
	reset_modules()
	stub_module("::/gui/main/react.lua", { fireEvent = function(__, name) fake.events[#fake.events + 1] = name end })
	fake.save = saved
	hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
	hud.persist = function() fake.save["square_photo_mode"] = { v = 1, views = {}, hud = hud.saveMarker() } end
	hud.start()
	eq(fake.save[""].hudFilter, PLAYER_FILTER)
	eq(fake.save["square_photo_mode"].hud, nil, "marker cleared")
	eq(fake.visible["react.game-ui-root"], true, "UI shown at every start")
end)

test("Hide UI: stays hidden (no timer, no mouse or camera trigger) until the pause menu", function()
	local changed = 0
	hud.changed = function() changed = changed + 1 end
	hud.hideUi()
	eq(fake.visible["react.game-ui-root"], false)
	eq(hud.uiHidden(), true, "the checkbox shows ticked")
	eq(changed, 1, "the window re-renders the checkbox")
	eq(hud.busy(), true, "while hidden: one GAME_SPEED read a frame (the pause-key escape)")
	steps(600, 0.1) -- a minute
	fake.view.z = 900 -- the player zooms
	fake.mouse = { x = 500, y = 10 } -- and moves the mouse
	steps(10)
	eq(hud.uiHidden(), true, "still hidden")
	eq(fake.visible["react.game-ui-root"], false)
	hud.pauseMenu()
	eq(hud.uiHidden(), false, "Esc brings it back")
	eq(fake.visible["react.game-ui-root"], true)
	hud.hideUi()
	hud.showUi("checkbox")
	eq(fake.visible["react.game-ui-root"], true, "unticking shows it")
	hud.hideUi()
	hud.start()
	eq(fake.visible["react.game-ui-root"], true, "a new game shows it")
	eq(hud.uiHidden(), false)
end)

test("a tour with the UI hidden keeps it hidden (no timer) until the tour ends", function()
	hud.tourHide(true, true)
	eq(fake.visible["react.game-ui-root"], false)
	steps(1200, 0.1) -- two minutes
	eq(fake.visible["react.game-ui-root"], false, "still hidden")
	eq(fake.visible[hud.WINDOW_ID], false)
	hud.tourHide(false)
	eq(fake.visible["react.game-ui-root"], true)
	eq(fake.visible[hud.WINDOW_ID], true)
	-- Hide UI and a tour together: the root comes back only when both are done
	hud.tourHide(true, true)
	hud.hideUi()
	hud.showUi("test")
	eq(fake.visible["react.game-ui-root"], false, "the tour still hides it")
	hud.tourHide(false)
	eq(fake.visible["react.game-ui-root"], true)
	-- the pause menu ends both
	hud.tourHide(true, true)
	hud.pauseMenu()
	eq(fake.visible["react.game-ui-root"], true)
end)

test("escape hatch: the pause key while the UI is hidden brings it back and stops the tour", function()
	local escaped = {}
	hud.onEscape = function(why) escaped[#escaped + 1] = why hud.tourHide(false) end
	hud.tourHide(true, true)
	ok(hud.busy(), "watching the game speed while hidden")
	steps(hud.ESCAPE_SETTLE_FRAMES + 5)
	fake.speed = 2 -- the speed throttle (4 -> 2) never pauses: no escape
	steps(5)
	eq(fake.visible["react.game-ui-root"], false, "a speed change between running speeds is not the pause key")
	fake.speed = 0 -- the player pressed Space
	clear_logs()
	steps(1)
	eq(escaped, { "pause key" })
	eq(fake.visible["react.game-ui-root"], true)
	eq(fake.visible[hud.WINDOW_ID], true)
	eq(hud.busy(), false, "no more reads once shown")
	local logged = false
	for __, e in ipairs(log_entries()) do if e.msg:find("pause key while hidden", 1, true) then logged = true end end
	ok(logged, "the path that restored is logged")
	-- Hide UI: unpausing brings it back too, the checkbox unticks
	hud.hideUi()
	steps(hud.ESCAPE_SETTLE_FRAMES + 1)
	fake.speed = 1
	steps(1)
	eq(hud.uiHidden(), false)
	eq(fake.visible["react.game-ui-root"], true)
end)

test("escape hatch: a speed change while settling (our own freeze command landing) is not the pause key", function()
	hud.hideUi()
	steps(3)
	fake.speed = 0 -- the freeze we just sent lands
	steps(hud.ESCAPE_SETTLE_FRAMES + 3)
	eq(hud.uiHidden(), true, "still hidden")
	fake.speed = 1
	steps(1)
	eq(hud.uiHidden(), false, "the player's unpause brings it back")
	-- an unreadable speed never triggers
	fake.speed = nil
	hud.hideUi()
	steps(hud.ESCAPE_SETTLE_FRAMES + 10)
	eq(hud.uiHidden(), true)
end)

---------------------------------------------------------------------------
-- Round 6: camera mode (the base free camera tool) and labels during tours

local TOOL = { name = "FreeCam" }

--- A fake default tool stack with the base free camera tool; the camera "drives" when drives = true (then the
--- free camera reports what we set), else it stays where it is.
local function withToolStack()
	local st = { stack = {}, pushes = 0, pops = 0 }
	st.api = {
		push = function(tool) st.stack[#st.stack + 1] = tool st.pushes = st.pushes + 1 end,
		pop = function(tool)
			st.pops = st.pops + 1
			for i = #st.stack, 1, -1 do if st.stack[i] == tool then table.remove(st.stack, i) end end
		end,
		getActiveTool = function() return st.stack[#st.stack], nil end,
	}
	stub_module("::/gui/main/free_cam_options.tl", { FreeCamTool = TOOL })
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultToolStackApi = function() return st.api end })
	local camApi = api.gui.camera
	camApi.isFreeCameraMouseAttached = function() return st.mouse == true end
	camApi.toggleFreeCameraMouseAttachment = function() st.mouse = not st.mouse end
	camApi.getEye = function() return st.eye end
	camApi.getCenter = function() return st.centre end
	hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
	return st
end

local SET = { x = 100, y = 200, d = 300, a = 0.5, p = 0.4 }

test("round 9: a tour never pushes the free camera; it hides the window and the UI root, restored at its end", function()
	local st = withToolStack()
	eq(hud.cameraCheck, nil, "no camera mode probe any more")
	hud.tourHide(true, { cameraMode = true, hideLabels = false })
	eq(st.pushes, 0, "no free camera for a tour")
	eq(fake.visible[hud.WINDOW_ID], false)
	eq(fake.visible["react.game-ui-root"], false)
	hud.tourHide(false)
	eq(fake.visible[hud.WINDOW_ID], true)
	eq(fake.visible["react.game-ui-root"], true)
	hud.tourHide(true, {})
	hud.pauseMenu()
	eq(fake.visible["react.game-ui-root"], true, "the pause menu shows everything")
	hud.tourHide(true, {})
	hud.start()
	eq(fake.visible["react.game-ui-root"], true, "a new game shows everything")
end)

test("round 9: hover off while an automated move runs; back when it ends, unless Hide labels and hover keeps it", function()
	hud.setAutoHover(true)
	eq(fake.events, { "preventReactSelector" }, "off at once")
	eq(hud.autoHover(), true)
	ok(hud.busy(), "re-asserted a few frames later")
	steps(40)
	eq(fake.events, { "preventReactSelector", "preventReactSelector", "preventReactSelector" },
		"again at frames 2 and 30 (a selector remounted meanwhile starts allowed), then nothing")
	hud.setAutoHover(true)
	eq(#fake.events, 3, "a second start does nothing")
	hud.setAutoHover(false)
	eq(fake.events[#fake.events], "allowReactSelector", "back when the move ends")
	eq(hud.busy(), false)
	-- with the labels hidden by the player, the selector stays prevented after the move
	hud.setLabels(true)
	hud.setAutoHover(true)
	local n = #fake.events
	hud.setAutoHover(false)
	eq(#fake.events, n, "nothing allowed: the labels checkbox keeps the hover off")
	eq(fake.events[n], "preventReactSelector")
	-- the labels shown during a move: the filter is re-read (allow), the hover off again next frames
	hud.setAutoHover(true)
	hud.setLabels(false)
	eq(fake.events[#fake.events], "allowReactSelector", "re-renders with the player's filter")
	steps(3)
	eq(fake.events[#fake.events], "preventReactSelector", "and the hover goes again while the move runs")
	hud.pauseMenu()
	eq(hud.autoHover(), false, "the pause menu ends it in any case")
	eq(fake.events[#fake.events], "allowReactSelector")
	hud.setAutoHover(true)
	hud.start()
	eq(hud.autoHover(), false, "a new game: nothing kept (a fresh selector starts allowed)")
end)

test("the footer's Camera mode: pushes the tool, notices Esc; without the tool it hides the UI (Esc / pause key)", function()
	local st = withToolStack()
	st.mouse = true
	local toggles = 0
	api.gui.camera.toggleFreeCameraMouseAttachment = function() toggles = toggles + 1 st.mouse = not st.mouse end
	eq(hud.cameraMode(), true)
	eq(toggles, 0, "round 13: the free camera's mouse attachment is the game's own (never toggled)")
	eq(st.mouse, true)
	eq(#st.stack, 1)
	ok(hud.busy(), "watching for the player's Esc")
	steps(3)
	eq(hud.cameraModeOn(), true, "the push may take a frame to show as the active tool")
	table.remove(st.stack) -- Esc
	steps(10)
	eq(hud.cameraModeOn(), false)
	eq(hud.busy(), false)
	-- no tool: Hide UI instead
	st.api.push = function() error("no") end
	eq(hud.cameraMode(), false)
	eq(hud.uiHidden(), true)
	hud.pauseMenu()
	eq(hud.uiHidden(), false)
end)

test("labels during tours: hidden for the tour, back after it; labels the player hid stay hidden", function()
	hud.tourHide(true, { hideLabels = true })
	eq(hud.labelsHidden(), true)
	hud.tourHide(false)
	eq(hud.labelsHidden(), false, "back after the tour")
	eq(fake.save[""].hudFilter, PLAYER_FILTER)
	hud.setLabels(true)
	local n = #fake.events
	hud.tourHide(true, { hideLabels = true })
	eq(fake.events[n + 1], "preventReactSelector", "the selector prevented again at the tour start")
	hud.tourHide(false)
	eq(hud.labelsHidden(), true, "the player's own choice stays")
end)

-- Round 10: our own tool on the default tool stack while hover must be off (pm_hud "tool")

--- A fake react with RegisterTool and a fake default tool stack that calls the tools' push / pop handlers as the
--- base ToolStack does (builtin.lua); `clear` pops every tool (another tool taking over).
local function withViewTool()
	reset_modules()
	local st = { stack = {}, registered = {} }
	stub_module("::/gui/main/react.lua", {
		fireEvent = function(__, name) fake.events[#fake.events + 1] = name end,
		RegisterTool = function(desc)
			if st.registered[desc.name] then error("Already registered a tool with name " .. desc.name) end
			st.registered[desc.name] = desc
			return desc
		end,
	})
	st.api = {
		push = function(tool, key, params, stacking)
			st.stack[#st.stack + 1] = tool
			if tool.push then tool.push({}, params) end
		end,
		pop = function(tool)
			for i = #st.stack, 1, -1 do
				if st.stack[i] == tool then
					table.remove(st.stack, i)
					if tool.pop then tool.pop({}, nil) end
				end
			end
		end,
		clear = function()
			for i = #st.stack, 1, -1 do
				local t = table.remove(st.stack, i)
				if t.pop then t.pop({}, nil) end
			end
		end,
		getActiveTool = function() return st.stack[#st.stack], nil end,
	}
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultToolStackApi = function() return st.api end,
		getDisableFeatures = function() return fake.features end })
	hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
	hud.persist = function() end
	return st
end

test("round 10: an automated move pushes our tool (no hover, tooltips, floaters); popped when it ends", function()
	local st = withViewTool()
	hud.setAutoHover(true)
	eq(#st.stack, 1, "pushed at the move's start")
	eq(st.stack[1].name, hud.TOOL_NAME)
	eq(hud.toolOn(), true)
	ok(fake.events[1] == "preventReactSelector", "the events still fired as a second path")
	steps(40)
	eq(#st.stack, 1, "pushed once")
	hud.setAutoHover(false)
	eq(#st.stack, 0, "popped at the end")
	eq(hud.toolOn(), false)
	eq(hud.busy(), false)
	-- the labels hidden keep it after a move, the untick pops it
	hud.setLabels(true)
	eq(#st.stack, 1, "hidden labels push it (no hover)")
	hud.setAutoHover(true)
	hud.setAutoHover(false)
	eq(#st.stack, 1, "still pushed: the labels keep the hover off")
	hud.setLabels(false)
	eq(#st.stack, 0)
	-- registered once per game state, reused
	hud.setAutoHover(true)
	hud.setAutoHover(false)
	eq(#st.stack, 0)
end)

test("round 10 / 12 / 15: another tool clearing the stack: during a move ours goes back; labels alone: not pushed back until a new request", function()
	local st = withViewTool()
	hud.setAutoHover(true)
	st.api.clear()
	steps(2)
	eq(hud.toolOn(), true, "round 15: pushed again during the move")
	eq(#st.stack, 1)
	hud.setAutoHover(false)
	eq(#st.stack, 0)
	-- the labels alone (the normal game): another tool keeps the map
	hud.setLabels(true)
	eq(#st.stack, 1, "hiding the labels pushes it")
	st.api.clear()
	steps(2)
	eq(hud.toolOn(), false, "noticed")
	steps(40)
	eq(#st.stack, 0, "not pushed back against the player's tool")
	-- round 12 (session 2026-10-14_0229: labels hidden all session kept every later tour without our tool): a new
	-- request from one of our controls pushes it again, though the old need never ended
	hud.setAutoHover(true)
	eq(#st.stack, 1, "a new move pushes it again (the labels never shown in between)")
	hud.setAutoHover(false)
	eq(#st.stack, 1, "kept for the labels")
	hud.setLabels(false)
	eq(#st.stack, 0)
	hud.setAutoHover(true)
	eq(#st.stack, 1, "a new move pushes it again")
	hud.pauseMenu()
	eq(#st.stack, 0, "the pause menu pops it")
	hud.setAutoHover(true)
	hud.start()
	eq(hud.toolOn(), false, "a new game: a new tool stack, nothing kept")
end)

test("round 10: no tool stack or RegisterTool failing: the events alone, nothing raises", function()
	local st = withViewTool()
	st.api.push = function() error("no") end
	hud.setAutoHover(true)
	eq(hud.toolOn(), false)
	eq(fake.events[1], "preventReactSelector")
	hud.setAutoHover(false)
	eq(fake.events[#fake.events], "allowReactSelector")
end)

-- Round 11: our tool's own empty action (the round 10 tool had none and the default selector stayed: session
-- 2026-10-14_0055_session "Selected entity" with it pushed)

--- withViewTool plus a tool stack context with setActionFn (as builtin.lua ToolStack makeContext) and fake base
--- modules for the action: builtin (ActionDescriptor, HudIconManagerConfig), the selector's default filter lists,
--- the HUD toolbox and helpers, and the genericRep configs.
local function withActionTool()
	local st = withViewTool()
	st.actions = {}
	st.api.push = function(tool, key, params, stacking)
		st.stack[#st.stack + 1] = tool
		local ctx = { setActionFn = function(fn, key2) st.actions[#st.actions + 1] = { fn = fn, key = key2 } end }
		if tool.push then tool.push(ctx, params) end
	end
	stub_module("::/gui/main/builtin.lua", {
		ActionDescriptor = function(p) return { kind = "ActionDescriptor", p = p } end,
		HudIconManagerConfig = function(p) return { kind = "HudIconManagerConfig", p = p } end,
	})
	stub_module("::/gui/main/selector_react_util.tl", {
		defaultHudIconFilter = { CT.TRANSPORT_VEHICLE, CT.INDUSTRY, CT.STATION_GROUP, CT.TOWN },
		defaultHudIconFilterTvCarrier = { CARRIER.ROAD, CARRIER.RAIL },
	})
	stub_module("::/gui/main/hud_icon_toolbox.tl", { HudIconMasterGame = "master" })
	stub_module("::/gui/hud/hud_react_util.tl", {
		makeDefaultVisibilityThresholds = function() return {} end,
		makeVehicleIconOffsets = function() return {} end,
	})
	api.gui.genericRep = {
		find = function(path) return path end,
		get = function(path)
			if path:find("hud_gui_config", 1, true) then
				return { data = { renderDistances = { Costs = 500 }, vehicleIconOffsets = {} } }
			end
			return { data = { Income = { "sfx" } } }
		end,
	}
	return st
end

test("round 11: our tool sets an empty action of its own: no Selector, the HUD icons from the filter, a back", function()
	local st = withActionTool()
	local backs = {}
	hud.onBack = function(why) backs[#backs + 1] = why end
	hud.setAutoHover(true)
	eq(#st.stack, 1)
	eq(#st.actions, 1, "the push sets the action")
	local node = st.actions[1].fn()
	eq(node.kind, "ActionDescriptor")
	eq(node.p.tool, hud.ACTION_TOOL)
	ok(not hud.ACTION_TOOL:find("_", 1, true), "a class-safe name")
	for __, c in ipairs(node.p.children) do ok(c.kind ~= "Selector", "no selector: no hover or click-to-select") end
	eq(#node.p.children, 1)
	local cfg = node.p.children[1]
	eq(cfg.kind, "HudIconManagerConfig")
	-- the player's filter hides towns and shows costs, not income
	local shown = {}
	for __, t in ipairs(cfg.p.preFilter) do shown[t] = true end
	ok(shown[CT.INDUSTRY] and shown[CT.STATION_GROUP] and not shown[CT.TOWN], "the player's filter")
	eq(cfg.p.showCosts, true); eq(cfg.p.showIncome, false)
	-- the back (a right click) goes to the hook
	node.p.onBack()
	eq(backs, { "right click" })
	-- hiding the labels re-sets the action with a new key: the icons follow the hidden filter
	hud.setLabels(true)
	eq(#st.actions, 2)
	ok(st.actions[2].key ~= st.actions[1].key, "a new key rebuilds it")
	local cfg2 = st.actions[2].fn().p.children[1]
	eq(#cfg2.p.preFilter, 0, "no labels")
	eq(cfg2.p.showCosts, false)
	hud.setLabels(false)
	eq(#st.actions, 3, "and back")
	hud.setAutoHover(false)
	eq(#st.stack, 0)
end)

test("round 11: a missing base piece drops only the icon config; the action stays (no hover)", function()
	local st = withActionTool()
	api.gui.genericRep = nil
	clear_logs()
	hud.setAutoHover(true)
	local node = st.actions[1].fn()
	eq(node.kind, "ActionDescriptor")
	eq(#node.p.children, 0)
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("no HUD icon config", 1, true) then n = n + 1 end end
	eq(n, 1, "logged once")
	st.actions[1].fn()
	n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("no HUD icon config", 1, true) then n = n + 1 end end
	eq(n, 1, "not every render")
end)

-- Round 12: the hidden cursor during tours (round 13: the smooth camera's click selector removed)

test("round 13: the right-click back only while a move runs; with only the labels hidden the action has none", function()
	local st = withActionTool()
	local backs = {}
	hud.onBack = function(why) backs[#backs + 1] = why end
	hud.setLabels(true)
	local node = st.actions[#st.actions].fn()
	eq(node.p.onBack, nil, "labels hidden alone: the game's right click stays the game's")
	for __, c in ipairs(node.p.children) do ok(c.kind ~= "Selector", "no selector") end
	eq(node.p.mouseCursor, nil, "the cursor stays outside a tour")
	-- a move on top: the action is set again with the back
	local n = #st.actions
	hud.setAutoHover(true)
	eq(#st.actions, n + 1, "re-set for the move")
	node = st.actions[#st.actions].fn()
	ok(type(node.p.onBack) == "function")
	node.p.onBack()
	eq(backs, { "right click" })
	hud.setAutoHover(false)
	eq(#st.stack, 1, "the labels keep the tool")
	eq(st.actions[#st.actions].fn().p.onBack, nil, "the back goes with the move")
	hud.setLabels(false)
	eq(#st.stack, 0)
	eq(hud.setSmoothCam, nil, "the smooth camera is gone"); eq(hud.onWorldClick, nil)
end)

test("round 12: during a tour the action hides the cursor; back after it", function()
	local st = withActionTool()
	hud.setAutoHover(true)
	hud.tourHide(true, {})
	eq(st.actions[#st.actions].fn().p.mouseCursor, hud.CURSOR_NONE)
	eq(hud.CURSOR_NONE, 1009, "the base's None cursor")
	hud.tourHide(false)
	eq(st.actions[#st.actions].fn().p.mouseCursor, nil)
	hud.setAutoHover(false)
end)

test("round 13: after free camera, hidden labels and a tour, the pause menu leaves nothing of ours: no tool, UI shown, selector allowed, the mouse attachment untouched", function()
	local st = withViewTool()
	stub_module("::/gui/main/free_cam_options.tl", { FreeCamTool = { name = "FreeCam" } })
	local toggles = 0
	api.gui.camera.isFreeCameraMouseAttached = function() return true end
	api.gui.camera.toggleFreeCameraMouseAttachment = function() toggles = toggles + 1 end
	api.gui.camera.getEye = function() return nil end
	api.gui.camera.getCenter = function() return nil end
	eq(hud.cameraMode(), true)
	steps(3)
	for i = #st.stack, 1, -1 do if st.stack[i].name == "FreeCam" then table.remove(st.stack, i) end end -- Esc
	steps(10)
	eq(hud.cameraModeOn(), false)
	hud.setLabels(true)
	hud.setAutoHover(true)
	hud.tourHide(true, {})
	eq(fake.visible["react.game-ui-root"], false)
	hud.pauseMenu()
	hud.setAutoHover(false)
	steps(40)
	eq(#st.stack, 0, "no tool of ours left on the stack")
	eq(fake.visible["react.game-ui-root"], true)
	eq(fake.visible[hud.WINDOW_ID], true)
	eq(fake.events[#fake.events], "allowReactSelector", "the game's selector allowed")
	eq(hud.labelsHidden(), false)
	eq(toggles, 0, "the free camera's mouse attachment never toggled")
	eq(hud.busy(), false, "nothing left running")
end)

---------------------------------------------------------------------------
-- Round 15: the world lock during automated moves (round 14's disableToolActions let the default selector's
-- clicks through: session 2026-10-14_0658_session "Selected entity 26133" 5 s after "tool actions off")

local function countLogs(pat)
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find(pat, 1, true) then n = n + 1 end end
	return n
end

test("round 15: an automated move locks the world (entity filter, no entity windows); never disableToolActions", function()
	fake.features = { CreateNewLine = true } -- whatever the game had
	clear_logs()
	hud.setAutoHover(true)
	eq(hud.locked(), true)
	ok(fake.selectorFilter ~= nil and next(fake.selectorFilter) ~= nil, "a non-empty filter: the default selector refuses everything")
	for e in pairs(fake.selectorFilter) do ok(e < 0, "only an id no entity has: " .. tostring(e)) end
	eq(fake.features, { CreateNewLine = true, OpenEntityWindow = true }, "the game's features kept, windows off")
	eq(fake.actionsDisabled, nil, "round 14's switch is never fired")
	steps(1)
	eq(countLogs("world lock check: entity windows off (the event reached the game)"), 1)
	steps(40)
	eq(countLogs("world lock check"), 1, "checked once")
	hud.setAutoHover(false)
	eq(hud.locked(), false)
	eq(fake.selectorFilter, {}, "the free game's empty filter back")
	eq(fake.features, { CreateNewLine = true }, "exactly the game's features back")
	eq(fake.reactEvents, { "setSelectorEntityFilter", "setDisableFeatures", "setSelectorEntityFilter",
		"setDisableFeatures" }, "once each way")
	eq(hud.busy(), false)
end)

test("round 15: Hide labels alone never locks the world (the normal game keeps its windows)", function()
	hud.setLabels(true)
	steps(10)
	eq(hud.locked(), false)
	eq(fake.reactEvents, nil)
	hud.setLabels(false)
end)

test("round 15: in a campaign mission the selector filter is left alone (it can't be read back)", function()
	fake.mission = "mission_01"
	hud.setAutoHover(true)
	eq(fake.selectorFilter, nil)
	eq(fake.features.OpenEntityWindow, true, "entity windows still off")
	hud.setAutoHover(false)
	eq(fake.selectorFilter, nil)
	eq(fake.features, {})
end)

test("round 15: every exit unlocks: the pause menu, a new game, the safety check", function()
	hud.setAutoHover(true)
	hud.pauseMenu()
	eq(hud.locked(), false, "pause menu")
	eq(fake.features, {})
	hud.setAutoHover(true)
	eq(hud.locked(), true)
	hud.start()
	eq(hud.locked(), false, "game start")
	eq(fake.selectorFilter, {})
	eq(hud.busy(), false)
	-- the safety check: a lock with no move running (a path that forgot to end the move)
	hud.setAutoHover(true)
	hud.S.auto = nil
	steps(1)
	eq(hud.locked(), false, "safety check")
	eq(fake.features, {})
end)

test("round 15: the features event not arriving is logged; unreadable features give an empty table back", function()
	api.gui.fireReactEvent = function() end -- nothing reaches the game
	clear_logs()
	hud.setAutoHover(true)
	steps(1)
	eq(countLogs("STILL ON (the event did not arrive)"), 1)
	hud.setAutoHover(false)
	reset_modules()
	stub_module("::/gui/main/react.lua", { fireEvent = function() end })
	stub_module("::/gui/main/game_react_globals.tl", { getDisableFeatures = function() error("gone") end })
	hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
	local sent = {}
	api.gui.fireReactEvent = function(name, p) sent[#sent + 1] = { name, p } end
	hud.setAutoHover(true)
	eq(sent[2][2], { OpenEntityWindow = true })
	hud.setAutoHover(false)
	eq(sent[4][2], {}, "nothing read: the free game's empty table")
end)

test("round 15: a failing fireReactEvent raises nothing; the lock still ends", function()
	api.gui.fireReactEvent = function() error("boom") end
	hud.setAutoHover(true)
	eq(hud.locked(), true)
	hud.setAutoHover(false)
	eq(hud.locked(), false)
	eq(hud.busy(), false)
end)

test("round 15: our tool taken off during a move goes back on top at once (stacked), at most LOCK_REPUSH times", function()
	local st = withViewTool()
	hud.setAutoHover(true)
	eq(#st.stack, 1)
	st.api.clear()
	steps(1)
	eq(#st.stack, 1, "pushed again")
	eq(hud.toolOn(), true)
	-- another tool pushed on top of ours, then ours cleared under it: ours goes on top of it (it comes back after)
	local other = { name = "BuildMenu" }
	st.stack[#st.stack + 1] = other
	st.api.pop(st.stack[1])
	steps(1)
	eq(st.stack[#st.stack].name, hud.TOOL_NAME, "ours on top")
	eq(st.stack[1], other, "the other tool kept below")
	for __ = 1, hud.LOCK_REPUSH + 3 do
		st.api.pop(st.stack[#st.stack])
		steps(1)
	end
	eq(hud.toolOn(), false, "no endless fight: after LOCK_REPUSH it stays off")
	hud.setAutoHover(false)
	eq(hud.locked(), false)
	-- labels alone: another tool keeps the map
	hud.setLabels(true)
	ok(hud.toolOn())
	st.api.clear()
	steps(2)
	eq(hud.toolOn(), false, "not pushed back in the normal game")
end)
