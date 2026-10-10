-- Stress Test Debug Tool HUD button + window: Game tab (here), Towns tab (actions in stress_towns.tl),
-- Traffic tab (stress_traffic.tl: add vehicles, Clear traffic; stress_buslines.tl: Auto bus lines) and,
-- with the "Show probe tab (developers)" param, the Probe tab (stress_probes.tl, required only then).
-- Widget types: .cache/game/base/tealdef/scripts/builtin.d.tl
--
-- WIRING (same as square_problem_radar's radar_hud.script.tl, verified in game there):
--   * stress_hud.res.lua mounts SquareStressHudPlugin at "::MainModButtonAreaExtension"
--     (.cache/game/base/content/gui/main/main_mod_button_area.tl:7-13); one row high.
--   * the window is a RegisterWrapperRecipe around builtin.Window, opened with addSingletonWindow
--     (builtin.d.tl:1186-1232; base: .cache/game/base/content/gui/menu/main_page.tl:44-63).
--
-- QUEUE: buttons only enqueue jobs (stress_runtime.tl). The HUD button's react.onStep (Main Thread)
-- calls rt.tick every frame, which sends at most rt.PER_FRAME commands, so the queue keeps running
-- while the window is closed. Nothing happens until a button is pressed; nothing is saved.
--
-- Recipe rules (memory notes): every custom recipe returns a BoxLayout; a ScrollArea's content is a
-- Component; no recipe is ever used as a Component's layout.
--
-- LAYOUT (rev after the first in-game test, where the window grew off the top of the screen and the
-- probe buttons spilled out of the tab panel over the log): every variable-height part sits in a
-- ScrollArea of fixed size (stress_hud.css.lua), like square_problem_radar's tab lists and
-- square_industry_flows' type list. Each tab's content is one ScrollArea (sqst-tabscroll), so the
-- TabWidget has the same height for every tab; the log is a second fixed ScrollArea (sqst-logscroll)
-- below the tabs, one unwrapped line per entry (stress_logic.oneLine; stdout.txt keeps the full text).
--
-- FORMS (rev after the second in-game look, 2026-10-10: plain Buttons rendered as bare text, the
-- factor buttons fired at once, Freeze/Unfreeze sat below the fold): each section is a form. Its
-- heading row carries the section's action on the right (head()); the options (ToggleButtonGroups)
-- follow below. The action button is green ("sqst-primary") and names what it will do, e.g.
-- "Grow all towns x10"; secondary buttons (Freeze, Clear queue, Sell added) use the neutral
-- "sqst-button" look (stress_hud.css.lua).

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl" as SquareStressTowns
local traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl" as SquareStressTraffic
local buslines = ug_require "square_stress_test::/stress/gui/stress_buslines.tl" as SquareStressBusLines

local WINDOW_ID <const> = "squarestresstest.window"
local STATUS_US <const> = 1000000      -- status line (year, speed, balance) refresh
local RENDER_US <const> = 200000       -- at most 5 window refreshes per second
local TOWNS_US <const> = 4000000       -- Towns and Traffic tab readout refresh (cached in between)

-- PROBE TAB: only with the load-time param "Show probe tab (developers)" (mod.json show_probe_tab,
-- default Off). Read once, at the window's first render (a GUI context with api.engine; getModParams
-- works in GUI scripts, as SQPERF's gate shows: tools/sqperf). When Off, stress_probes.tl (1,100 lines,
-- the probe experiments) is never required and the tab is not created.
local probeState = 0                   -- 0 not read yet, 1 off, 2 on
local probes : SquareStressProbes = nil

local function probeModule() : SquareStressProbes
	if probeState == 0 then
		local ok, all = pcall(function() : {string : any} return api.engine.config.getModParams() as {string : any} end)
		probeState = (ok and logic.showProbeTab(all)) and 2 or 1
		if probeState == 2 then
			local okR, mod = pcall(ug_require, "square_stress_test::/stress/gui/stress_probes.tl")
			if okR then
				probes = mod as SquareStressProbes
			else
				probeState = 1
				log.warning("[SQST] probe tab unavailable: " .. tostring(mod))
			end
		end
	end
	return probes
end

---------------------------------------------------------------------------
-- Widgets

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = str,
	}
end

-- Every layout of ours carries "sqst-box", so the .css.lua spacing rule only targets our own layouts.
local function boxClass(class : string) : string
	return class and (class .. ", sqst-box") or "sqst-box"
end

local function hbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = boxClass(class) },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local function vbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = boxClass(class) },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

local function button(label : string, tooltip : string, onClick : function(), class? : string) : TreeNodeId
	return builtin.Button{
		meta = { class = class or "sqst-button", tooltip = tooltip },
		content = text(label, "font-scale-annotation"),
		onClick = function()
			local ok, err : boolean, any = pcall(onClick)
			if not ok then rt.log("[SQST] button error (" .. label .. "): " .. tostring(err)) end
		end,
	}
end

--- The one prominent action of a section (accent background, stress_hud.css.lua "sqst-primary").
local function primary(label : string, tooltip : string, onClick : function()) : TreeNodeId
	return builtin.Button{
		meta = { class = "sqst-primary", tooltip = tooltip },
		content = text(label, "font-scale-body"),
		onClick = function()
			local ok, err : boolean, any = pcall(onClick)
			if not ok then rt.log("[SQST] button error (" .. label .. "): " .. tostring(err)) end
		end,
	}
end

---------------------------------------------------------------------------
-- Game tab actions

local function addMoney(amount : integer)
	local chunks = logic.bookingChunks(amount)
	rt.enqueue("add_money_" .. logic.formatMoney(amount), #chunks, function(i : integer) rt.book(chunks[i]) end)
end

local function setSpeed(speed : integer)
	-- api/tealdef/api/cmd.d.tl:708. 8 sticks (docs/findings.md "Stress Test probes"); 16 has no read-back yet.
	rt.enqueue("set_speed_" .. tostring(speed), 1, function(_i : integer)
		rt.send("set_speed", api.cmd.makeGameSetSpeedCmd(speed))
	end)
end

local yearText = ""

local function jumpToYear()
	local y, why = logic.parseYear(yearText)
	if y == nil then
		rt.log(string.format("[SQST] set_year: \"%s\" is not a year (%s)", yearText, why))
		return
	end
	-- api/tealdef/api/cmd.d.tl:703; Date.new(y, m, d) api/tealdef/api/type.d.tl:959-970.
	rt.enqueue("set_year_" .. tostring(y), 1, function(_i : integer)
		rt.send("set_year", api.cmd.makeGameSetDateCmd(api.type.Date.new(y, 1, 1)), function(success : boolean, _d : any)
			rt.log(string.format("[SQST] set_year %d success=%s year now %s", y, tostring(success), tostring(api.engine.util.getYear())))
		end)
	end)
end

local function setKeepBalance(on : boolean)
	if on == rt.keepBalance then return end
	rt.keepBalance = on
	rt.log(string.format("[SQST] keep_balance %s (threshold %s)", on and "on" or "off", logic.formatMoney(rt.KEEP_BALANCE)))
end

---------------------------------------------------------------------------
-- Tabs

local function section(title : string) : TreeNodeId
	return text(title, "font-scale-body, sqst-section")
end

local function hint(str : string) : TreeNodeId
	return text(str, "font-scale-annotation, sqst-hint")
end

--- A section heading with the section's action button(s) on the same row, pushed to the right edge
--- (fixed-width row + an expanding spacer, stress_hud.css.lua "sqst-head"), so the action is visible
--- without scrolling: each section works like a form, options below, the button at the top.
local function head(title : string, buttons : {TreeNodeId}) : TreeNodeId
	local children : {TreeNodeId} = { text(title, "font-scale-body, sqst-section"), text("", "sqst-spacer") }
	for _, b in ipairs(buttons) do children[#children + 1] = b end
	return hbox(children, "sqst-head")
end

local function gameTab() : TreeNodeId
	local speedButtons : {TreeNodeId} = {}
	for _, sp in ipairs(logic.SPEEDS) do
		speedButtons[#speedButtons + 1] = button(tostring(sp) .. "x", "Set the simulation speed to " .. tostring(sp), function() setSpeed(sp) end)
	end
	return vbox({
		head("Money", {
			primary("Add 10M", "Book 10,000,000 as income", function() addMoney(10000000) end),
			primary("Add 100M", "Book 100,000,000 as income", function() addMoney(100000000) end),
		}),
		builtin.CheckBox{
			value = rt.keepBalance and 1 or 0,
			onValueChange = function(v : integer) setKeepBalance(v == 1) end,
			label = "Keep balance above " .. logic.formatMoney(rt.KEEP_BALANCE) .. " (checked every 2 s, this session only)",
		},
		builtin.CheckBox{
			value = rt.hideNotifications and 1 or 0,
			onValueChange = function(v : integer) rt.setHideNotifications(v == 1) end,
			label = "Hide all notifications (stored in the save: uncheck before removing the mod)",
		},
		head("Date", { primary("Jump to year", "Jump to 1 January of the year typed below", jumpToYear) }),
		builtin.TextInputField{
			meta = { class = "font-scale-body, sqst-year" },
			placeholderText = "Year, e.g. 2000",
			value = yearText,
			maxLength = 4,
			onTyping = function(str : string) yearText = str end,
			onValueChange = function(str : string) yearText = str end,
		},
		hint(string.format("Years %d-%d. Vehicles, buildings and eras follow the new date.", logic.MIN_YEAR, logic.MAX_YEAR)),
		head("Game speed", {}),
		hbox(speedButtons),
		hint("Above the game's own 4x. The simulation may not keep up with 16x on a busy map: the status line shows the speed it runs at."),
		head("Town ratings", {
			primary("Ignore noise and pollution", "Set every town's noise and pollution sensitivity to zero (as the town editor's rating sensitivity does), so they no longer lower town ratings",
				function() towns.setRatingSensitivity(true) end),
			button("Restore defaults", "Reset every town's rating sensitivities to the game's defaults (like the town editor's reset button: all six ratings)",
				function() towns.setRatingSensitivity(false) end),
		}),
		hint("For all towns that exist now (spawned towns later: press again). Stored in the save. The load-time setting \"No noise and pollution\" also zeroes vehicle emissions."),
	}, "sqst-tab")
end

--- A 1-based ToggleButtonGroup (verified in game in square_problem_radar's settings tab).
local function choice(labels : {string}, selected : integer, onPick : function(i : integer)) : TreeNodeId
	local buttons : {Builtin.ToggleButtonGroupChildParam} = {}
	for i, l in ipairs(labels) do
		buttons[i] = { content = text(l, "font-scale-annotation") }
	end
	return builtin.ToggleButtonGroup{
		buttons = buttons,
		selected = selected,
		onValueChange = function(index : integer)
			if index ~= nil and index >= 1 and index <= #labels then onPick(index) end
		end,
	}
end

local function label(str : string) : TreeNodeId
	return text(str, "font-scale-annotation, sqst-label")
end

local function townsTab(readout : string) : TreeNodeId
	local ui = towns.ui
	local factorLabels : {string} = {}
	for i, f in ipairs(logic.GROW_FACTORS) do factorLabels[i] = "x" .. tostring(f) end
	factorLabels[#factorLabels + 1] = "Reset to x1"
	local passLabels : {string} = {}
	for i, p in ipairs(logic.GROW_PASSES) do passLabels[i] = tostring(p) end
	local countLabels : {string} = {}
	for i, c in ipairs(logic.SPAWN_COUNTS) do countLabels[i] = tostring(c) end
	local sizeLabels : {string} = {}
	for i, sz in ipairs(logic.TOWN_SIZES) do sizeLabels[i] = string.format("%s (%d)", sz.label, sz.caps) end
	return vbox({
		text(readout, "font-scale-body, sqst-readout"),
		head("Development", {
			button("Freeze all", "Stop the development of every town", function() towns.setDevelopment(false) end),
			button("Unfreeze all", "Let every town develop again", function() towns.setDevelopment(true) end),
		}),
		head("Grow", {
			primary(towns.growLabel(), "Multiply the size factors of the target town(s) and update all buildings; each extra pass re-sends the update to build more (Reset: back to 1, one pass; existing buildings may stay)",
				function() towns.growSelected() end),
		}),
		hbox({
			label("Target"),
			choice({ "All towns", "Nearest to camera" }, ui.growTarget, function(i : integer) ui.growTarget = i end),
		}, "sqst-row"),
		hbox({ label("Factor"), choice(factorLabels, ui.factor, function(i : integer) ui.factor = i end) }, "sqst-row"),
		hbox({ label("Passes"), choice(passLabels, ui.passes, function(i : integer) ui.passes = i end) }, "sqst-row"),
		hint(string.format("One town at a time, one command in flight. Each pass builds ~300 buildings per town; use more passes for denser towns. A town stops early when a pass adds fewer than %d.", logic.MIN_PASS_GAIN)),
		head("Spawn towns", {
			primary(towns.spawnLabel(), "Create the towns one after another (\"SQST Town N\"), skipping water and spots near other towns",
				function() towns.spawn() end),
		}),
		hbox({ label("Count"), choice(countLabels, ui.count, function(i : integer) ui.count = i end) }, "sqst-row"),
		hbox({ label("Size"), choice(sizeLabels, ui.size, function(i : integer) ui.size = i end) }, "sqst-row"),
		hbox({
			label("Where"),
			choice({ "Near camera", "Spread over map" }, ui.placement, function(i : integer) ui.placement = i end),
		}, "sqst-row"),
		builtin.CheckBox{
			value = ui.connect and 1 or 0,
			onValueChange = function(v : integer) ui.connect = v == 1 end,
			label = "Connect new towns by road to their nearest town (may also link industries)",
		},
		hint("Size = initial capacity per district. Each town takes 1-6 s; the [SQST] spawn lines list what was built."),
	}, "sqst-tab")
end

local function trafficTab(readout : string) : TreeNodeId
	local ui = traffic.ui
	local perLineLabels : {string} = {}
	for i, c in ipairs(logic.VEHICLES_PER_LINE) do perLineLabels[i] = tostring(c) end
	local n = logic.VEHICLES_PER_LINE[ui.perLine] or 1
	local intervalLabels : {string} = {}
	for i, sec in ipairs(logic.CLEAR_INTERVALS) do intervalLabels[i] = tostring(sec) .. " s" end
	local bl = buslines.ui
	local lineLabels : {string} = {}
	for i, c in ipairs(logic.BUS_LINES_PER_TOWN) do lineLabels[i] = tostring(c) end
	local busLabels : {string} = {}
	for i, c in ipairs(logic.BUSES_PER_LINE) do busLabels[i] = tostring(c) end
	return vbox({
		text(readout, "font-scale-body, sqst-readout"),
		head("Add vehicles to lines", {
			primary(logic.addVehiclesLabel(n), "Buy copies of each line's first vehicle (same model and wagons) at its depot and put them on the line",
				function() traffic.addVehicles() end),
		}),
		hbox({ label("Per line"), choice(perLineLabels, ui.perLine, function(i : integer) ui.perLine = i end) }, "sqst-row"),
		hint("All your lines, one purchase at a time. Lines without a vehicle are skipped. Without Keep balance (Game tab) the batch stops when the money runs out; it also stops after 3 failures in a row."),
		head("Added vehicles", {
			button(string.format("Sell added vehicles (%d)", #traffic.added), "Sell the vehicles added here in this session (forgotten on reload)",
				function() traffic.removeAdded() end),
		}),
		head("Car traffic", {
			primary("Clear traffic", "Send every person driving a car right now home (debug command \"jump home\"); your own vehicles are never touched",
				function() traffic.clearTraffic() end),
		}),
		builtin.CheckBox{
			value = ui.keepCleared and 1 or 0,
			onValueChange = function(v : integer) traffic.setKeepCleared(v == 1) end,
			label = "Keep traffic cleared (repeats the clear, this session only)",
		},
		hbox({ label("Every"), choice(intervalLabels, ui.clearInterval, function(i : integer) traffic.setClearInterval(i) end) }, "sqst-row"),
		hint("Sends drivers home (debug command); they start new trips after a few seconds, so use Keep cleared for an empty road. Your own vehicles are never touched."),
		hint("Driving now = cars on the road at the last clear scan. Car traffic grows with town population (Towns tab) and with the load-time setting \"Sim person trip recalculation\"."),
		head("Auto bus lines", {
			primary(buslines.label(), "Per town: two bus stops 300-800 m apart on its streets, a line between them, a road depot (one that reaches the line, one of ours nearby, or a new one) and the buses",
				function() buslines.addBusLines() end),
		}),
		hbox({ label("Towns"), choice(logic.BUS_TOWN_CHOICES, bl.towns, function(i : integer) bl.towns = i end) }, "sqst-row"),
		hbox({ label("Lines"), choice(lineLabels, bl.lines, function(i : integer) bl.lines = i end) }, "sqst-row"),
		hbox({ label("Buses"), choice(busLabels, bl.buses, function(i : integer) bl.buses = i end) }, "sqst-row"),
		hint(string.format("Lines per town, buses per line (the newest bus on sale). One step at a time; a town stops at its first failure and the batch after %d failed towns in a row. Without Keep balance it stops when the money runs out.", buslines.MAX_TOWN_FAILS)),
		head("Added bus lines", {
			button(buslines.removeLabel(), "Sell the buses added by Auto bus lines in this session, then delete their lines (forgotten on reload)",
				function() buslines.removeAdded() end),
		}),
		hint("Stops and depots stay in place: bulldoze them by hand if needed."),
	}, "sqst-tab")
end

local function probeTab(probeMod : SquareStressProbes) : TreeNodeId
	local left : {TreeNodeId} = {}
	local right : {TreeNodeId} = {}
	local half = math.ceil(#probeMod.list / 2)
	for i, p in ipairs(probeMod.list) do
		local col = i <= half and left or right
		col[#col + 1] = button(p.label, p.tooltip, p.run, "sqst-button, sqst-probe")
	end
	return vbox({
		hint("Developer experiments: each probe changes the save and logs one [SQST-PROBE] <name> ok|fail line to stdout.txt. Use a test save."),
		hbox({ vbox(left, "sqst-col"), vbox(right, "sqst-col") }),
	}, "sqst-tab")
end

--- A fixed-size scroll area (size from stress_hud.css.lua by class). Its content must be a Component
--- around a layout, never a layout itself (memory "ScrollArea content is a Component"; base shape:
--- entity_window/entity_window_util.tl:715-721, repo: square_industry_flows flows_window.script.tl).
local function scroll(class : string, item : TreeNodeId, horizontal? : boolean) : TreeNodeId
	return builtin.ScrollArea{
		meta = { class = class },
		horizontalPolicy = horizontal and builtin.type.ScrollBarPolicy.AsNeeded or builtin.type.ScrollBarPolicy.AlwaysOff,
		verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
		content = builtin.Component{
			layout = vbox({ item }),
		},
	}
end

--- Every tab's item is the same fixed-height ScrollArea, so the TabWidget's height never depends
--- on the selected tab's content (square_problem_radar tabChild + its ScrollArea!radar-list).
local function tabChild(key : string, label : string, item : TreeNodeId) : TreeNodeId
	return builtin.TabWidgetChild{
		localKey = "sqst_tab_" .. key,
		value = key,
		indicator = text(label, "font-scale-tab-widget-indicator"),
		item = builtin.Component{
			layout = vbox({ scroll("sqst-tabscroll", item) }),
		},
	}
end

---------------------------------------------------------------------------
-- Window content

local record View
	status : string
	progress : string
	recent : {string}
	keepBalance : boolean
	hideNotifications : boolean
	towns : string                -- Towns tab readout (refreshed every TOWNS_US)
	townsUi : string              -- towns.uiSignature(): re-render when a selection changes
	traffic : string              -- Traffic tab readout (refreshed every TOWNS_US)
	trafficUi : string            -- traffic.uiSignature()
end

local function readStatus() : string
	local ok, s = pcall(function() : string
		local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
		return string.format("Year %s   Speed %sx   Balance %s", tostring(api.engine.util.getYear()),
			gs ~= nil and tostring(gs.speedup) or "?", logic.formatMoney(rt.balance()))
	end)
	return ok and s or "status unavailable"
end

local function makeView(status : string, townsLine : string, trafficLine : string) : View
	local recent : {string} = {}
	for i, line in ipairs(rt.recent) do recent[i] = line end
	return { status = status, progress = logic.progress(rt.queue), recent = recent, keepBalance = rt.keepBalance,
		hideNotifications = rt.hideNotifications, towns = townsLine, townsUi = towns.uiSignature(), traffic = trafficLine, trafficUi = traffic.uiSignature() .. "|" .. buslines.uiSignature() }
end

local function sameView(a : View, b : View) : boolean
	if a == nil or b == nil then return false end
	if a.status ~= b.status or a.progress ~= b.progress or a.keepBalance ~= b.keepBalance or a.hideNotifications ~= b.hideNotifications or #a.recent ~= #b.recent
		or a.towns ~= b.towns or a.townsUi ~= b.townsUi or a.traffic ~= b.traffic or a.trafficUi ~= b.trafficUi then return false end
	for i = 1, #a.recent do
		if a.recent[i] ~= b.recent[i] then return false end
	end
	return true
end

local windowState : ReactStateT<View> = nil

local SquareStressContent = react.RegisterRecipe("SquareStressContent", function() : TreeNodeId
	local viewState = react.useStateLazy(function() : View return makeView(readStatus(), towns.readout(), traffic.readout()) end)
	local tabState = react.useState("game") as ReactStateT<string>
	windowState = viewState
	local status = react.useRef(viewState:old().status) as ReactRefT<string>
	local nextStatus = react.useRef(0) as ReactRefT<integer>
	local nextRender = react.useRef(0) as ReactRefT<integer>
	local townsLine = react.useRef(viewState:old().towns) as ReactRefT<string>
	local nextTowns = react.useRef(0) as ReactRefT<integer>
	local trafficLine = react.useRef(viewState:old().traffic) as ReactRefT<string>
	react.onStep(function()
		local now = rt.nowUs()
		if now < nextRender:get() then return end
		nextRender:set(now + RENDER_US)
		if now >= nextStatus:get() then
			nextStatus:set(now + STATUS_US)
			status:set(readStatus())
		end
		if now >= nextTowns:get() then
			nextTowns:set(now + TOWNS_US)
			townsLine:set(towns.readout())
			trafficLine:set(traffic.readout())
		end
		local v = makeView(status:get(), townsLine:get(), trafficLine:get())
		if not sameView(v, viewState:old()) then viewState:set(v) end
	end)

	local view = viewState:old()
	local selected = tabState:old() or "game"
	local tabs : {TreeNodeId} = {
		tabChild("game", "Game", selected == "game" and gameTab() or vbox({})),
		tabChild("towns", "Towns", selected == "towns" and townsTab(view.towns) or vbox({})),
		tabChild("traffic", "Traffic", selected == "traffic" and trafficTab(view.traffic) or vbox({})),
	}
	local probeMod = probeModule()
	if probeMod ~= nil then
		tabs[#tabs + 1] = tabChild("probe", "Probe", selected == "probe" and probeTab(probeMod) or vbox({}))
	end
	local recent : {TreeNodeId} = {}
	for _, line in ipairs(view.recent) do
		recent[#recent + 1] = text(line, "font-scale-annotation, sqst-log")
	end
	if #recent == 0 then recent[1] = hint("No actions yet. Every action also writes an [SQST] line to stdout.txt.") end
	return vbox({
		text(view.status, "font-scale-body, sqst-status"),
		hbox({
			text("Queue: " .. view.progress, "font-scale-annotation, sqst-progress"),
			button("Clear queue", "Drop every queued job", function()
				local n = rt.clearQueue()
				rt.log(string.format("[SQST] queue cleared (%d jobs)", n))
			end),
		}, "sqst-row"),
		builtin.TabWidget{
			orientation = builtin.type.TabOrientation.North,
			deselectAllowed = false,
			value = selected,
			onValueChange = function(newTab : string)
				if newTab ~= nil then tabState:set(newTab) end
			end,
			tabs = tabs,
		},
		section("Log"),
		scroll("sqst-logscroll", vbox(recent, "sqst-logbox"), true),
	}, "sqst-content")
end)

local record SquareStressWindowParam
	onClose : function()
end

local SquareStressWindow = react.RegisterWrapperRecipe("SquareStressWindow", builtin.Window, function(params : SquareStressWindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210
	return builtin.Window{
		id = WINDOW_ID,
		title = "Stress Test Debug Tool",
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = SquareStressContent(),
	}
end)

local function closeWindow()
	windowState = nil
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then wa.removeAllWindows(SquareStressWindow) end
end

local function openWindow()
	-- getDefaultWindowApi may return nil (.cache/game/base/content/gui/main/game_react_globals.tl:14-20)
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning("[SQST] no window container; cannot open the window")
		return
	end
	wa.addSingletonWindow(SquareStressWindow, { onClose = closeWindow })
	wa.moveSingletonWindowToFront(SquareStressWindow)
end

local function toggleWindow()
	if windowState ~= nil and not windowState:hasExpired() then
		closeWindow()
	else
		openWindow()
	end
end

---------------------------------------------------------------------------
-- HUD button (always mounted: it also drives the queue)

local SquareStressHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "SquareStressHudPlugin", function() : TreeNodeId
	-- Hooks first, unconditionally (same order as square_problem_radar's plugin).
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	react.onStep(function()
		if isMapEditorRef:get() then return end
		local ok, err : boolean, any = pcall(rt.tick)
		if not ok then log.warning("[SQST] tick error: " .. tostring(err)) end
	end)
	if isMapEditorRef:get() then
		return nil
	end
	-- A plugin root must be a layout (MainModButtonArea mounts plugins as BoxLayout children).
	return builtin.BoxLayout{
		meta = { class = "sqst-box" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { class = "sqst-hud-button", tooltip = "Stress Test Debug Tool: open or close the window (changes your save; use a copy)" },
				content = text("Debug"),
				onClick = toggleWindow,
			},
		},
	}
end)

return {
	SquareStressHudPlugin = SquareStressHudPlugin,
}
