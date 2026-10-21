-- Stress Test Debug Tool HUD button + window: Game tab (here), Towns tab (actions in stress_towns.tl),
-- Traffic tab (stress_traffic.tl: add vehicles, Clear traffic; stress_flow_log.tl: Traffic log; stress_buslines.tl:
-- Auto bus lines) and,
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
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local dialog_react_util = ug_require "::/gui/menu/dialog_react_util.tl" as DialogReactUtil

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl" as SquareStressTowns
local traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl" as SquareStressTraffic
local buslines = ug_require "square_stress_test::/stress/gui/stress_buslines.tl" as SquareStressBusLines
local roads = ug_require "square_stress_test::/stress/gui/stress_roads.tl" as SquareStressRoads
local junctions = ug_require "square_stress_test::/stress/gui/stress_junctions.tl" as SquareStressJunctions
local flowlog = ug_require "square_stress_test::/stress/gui/stress_flow_log.tl" as SquareStressFlowLog
local flowlib = ug_require "square_stress_test::/stress/stress_flow.tl" as SquareStressFlow
local benchlib = ug_require "square_stress_test::/stress/stress_bench.tl" as SquareStressBench
local benchrun = ug_require "square_stress_test::/stress/gui/stress_bench_run.tl" as SquareStressBenchRun
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones

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

-- Tooltips are wrapped to this many characters per line (the game does not wrap them).
local TOOLTIP_WIDTH <const> = 60

local function button(label : string, tooltip : string, onClick : function(), class? : string) : TreeNodeId
	return builtin.Button{
		meta = { class = class or "sqst-button", tooltip = logic.wrapText(tooltip, TOOLTIP_WIDTH) },
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
		meta = { class = "sqst-primary", tooltip = logic.wrapText(tooltip, TOOLTIP_WIDTH) },
		content = text(label, "font-scale-body"),
		onClick = function()
			local ok, err : boolean, any = pcall(onClick)
			if not ok then rt.log("[SQST] button error (" .. label .. "): " .. tostring(err)) end
		end,
	}
end

---------------------------------------------------------------------------
-- Game tab actions

--- A build or removal button's action, refused with a dialog while a bench run is active (it clears and builds the
--- map itself: another build or a removal in between would break it).
local function notDuringBench(fn : function()) : function()
	return function()
		if benchrun.running() then
			rt.warn("Bench", "A bench run is in progress: wait for it to finish (Towns tab > Bench shows its phase), or Clear queue to stop it.")
			return
		end
		fn()
	end
end

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
--- A section header: a blank line (the gap above every section; a stylesheet margin alone did not show
--- in game 2026-10-11), then the title with its buttons on the right.
-- The buttons go in a builtin.FlowLayout so a long row (Bench: Sheet 1..6, Micro) wraps to the window width
-- instead of running off it (docs/findings.md "Wrapping rows in a GUI plugin"; user screenshot 2026-10-15). Each
-- button keeps its gap inside an hbox, so a wrapped line never starts with a bare spacer.
local function head(title : string, buttons : {TreeNodeId}) : TreeNodeId
	local children : {TreeNodeId} = { hbox({ text(title, "font-scale-body, sqst-section"), text("", "sqst-spacer") }, "sqst-head") }
	for _, b in ipairs(buttons) do children[#children + 1] = hbox({ b, text("", "sqst-spacer") }, "sqst-head") end
	return vbox({ text(" "), builtin.FlowLayout{ children = children } })
end

-- The dialog recipe: the base DialogWindow, or our own plain Window (SquareStressDialog, below
-- platformWindow) where this platform's dialog_react_util has none (PS5 report 2026-10-19, Smart Lanes;
-- docs/findings/gui.md "Base GUI modules differ by platform"). Logged once.
local SquareStressDialog : Recipe<DialogReactUtil.DialogWindowParam> -- set below
local dialogFallbackLogged = false
local function dialogRecipe() : Recipe<DialogReactUtil.DialogWindowParam>
	local base = (dialog_react_util as {string : any}).DialogWindow
	if base ~= nil then return base as Recipe<DialogReactUtil.DialogWindowParam> end
	if not dialogFallbackLogged then
		dialogFallbackLogged = true
		log.warning("[SQST] no base DialogWindow on this platform; using a plain window for dialogs")
	end
	return SquareStressDialog
end

--- The base confirm dialog (gui/menu/dialog_react_util.tl, used by the pause menu's Quit Game,
--- pause_menu.tl:15-45) in the default window container: the action button and Cancel (focused,
--- also on Esc and a click outside). onOk runs only after the confirm button.
local function confirm(title : string, body : string, okText : string, onOk : function())
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		rt.log("[SQST] " .. title .. ": no window container for the confirm dialog; nothing done")
		return
	end
	local recipe = dialogRecipe()
	wa.addSingletonWindow(recipe, {
		onClose = function() wa.removeAllWindows(recipe) end,
		x = 0.5,
		y = 0.5,
		windowTitle = title,
		displayText = body,
		choices = {
			{ text = okText, onClick = onOk, isSecondary = true },
			{ text = "Cancel", onClick = function() end, isSecondary = false },
		},
		onBackChoiceIndex = 2,
	} as DialogReactUtil.DialogWindowParam)
end

--- The same dialog with one OK button, for rt.warn. One at a time: warnings that come while it is
--- open wait, and those waiting are shown together.
local alertOpen = false
local function showWarnings()
	if alertOpen or #rt.warnings == 0 then return end
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		rt.warnings = {} -- logged already
		return
	end
	local list = rt.warnings
	rt.warnings = {}
	local title = list[1].title
	local parts : {string} = {}
	for _, w in ipairs(list) do
		if w.title ~= title then title = "Stress Test" end
	end
	for _, w in ipairs(list) do
		parts[#parts + 1] = title == w.title and w.body or (w.title .. ": " .. w.body)
	end
	alertOpen = true
	local recipe = dialogRecipe()
	local function close()
		alertOpen = false
		wa.removeAllWindows(recipe)
	end
	wa.addSingletonWindow(recipe, {
		onClose = close,
		x = 0.5,
		y = 0.5,
		windowTitle = title,
		displayText = table.concat(parts, "\n\n"),
		choices = {
			{ text = "OK", onClick = function() alertOpen = false end, isSecondary = false },
		},
		onBackChoiceIndex = 1,
	} as DialogReactUtil.DialogWindowParam)
end

--- "Grid A1, Grid A2, Grid B1 and 3 more".
local function nameList(names : {string}, max : integer) : string
	local shown : {string} = {}
	for i = 1, math.min(#names, max) do shown[i] = names[i] end
	local s = table.concat(shown, ", ")
	if #names > max then s = s .. string.format(" and %d more", #names - max) end
	return s
end

local function confirmRemoveTowns()
	local list, names = towns.removePlan()
	if #list == 0 then
		towns.removeTowns(list) -- logs "no towns to remove"
		return
	end
	confirm("Remove towns", string.format("Remove %d town%s with all their streets and buildings?\n%s\n\nThis cannot be undone.",
		#list, #list == 1 and "" or "s", nameList(names, 8)), "Remove", function() towns.removeTowns(list) end)
end

local function confirmRemoveRoads()
	local n, kept = roads.count()
	if n == 0 then
		rt.warn("Remove all roads", "There are no streets to remove.")
		return
	end
	confirm("Remove all roads", string.format("Remove all %d street pieces on the map (town streets and your own roads)?%s Tracks are not touched.\n\nThis cannot be undone.",
		n, kept > 0 and string.format(" %d that belong to stations, depots or other constructions stay.", kept) or ""),
		"Remove", function() roads.removeAll() end)
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

--- The Junction test form (Towns tab), only with square_roundabouts enabled; else one hint line.
local function crossingItems(sizeLabels : {string}) : {TreeNodeId}
	local ui = junctions.crossUi
	return {
		head("Crossing test", {
			primary(junctions.crossLabel(), "Create 4 towns around the map centre and a 3 x 3 grid of long roads between them: rows and columns of 3, 2 and 1 lanes each way cross in all 9 combinations, and collector roads on each side end them in T junctions. Every junction is a plain crossing, for testing lane rules (Smart Lanes) with real traffic",
				notDuringBench(function() junctions.buildCrossings() end)),
		}),
		hbox({ label("Size"), choice(sizeLabels, ui.size, function(i : integer) ui.size = i end) }, "sqst-row"),
		hbox({ label("Lights"), choice(logic.CROSSING_LIGHTS, ui.lights, function(i : integer) ui.lights = i end) }, "sqst-row"),
		hbox({ label("Traffic"), choice(logic.TEST_TRAFFIC, ui.traffic, function(i : integer) ui.traffic = i end) }, "sqst-row"),
		hint("About 9 km across; use an empty flat map (Blank Slate). Rows (west to east) and columns (south to north) have 3, 2 and 1 lanes each way; a collector road (2 lanes) on each side leads to that side's town. Lights Off: no traffic lights anywhere, so the lanes alone decide. Each crossing's [SQST] crossing_test line names it (x12 = row 1, column 2). Traffic = Bus lines: after the build, bus lines between the towns straight across the grid (west - east, south - north) and two turning ones (west - north, east - south), with the Traffic tab's Auto bus lines Buses count. Remove towns > Grid towns and Remove all roads clear it; Traffic tab > Remove added bus lines the lines."),
	}
end

local function junctionItems(sizeLabels : {string}) : {TreeNodeId}
	if not junctions.available() then
		return { hint("Junction test: enable Roundabouts & Interchanges to build one of each of its junctions between test towns.") }
	end
	local ui = junctions.ui
	local setLabels : {string} = {}
	for i, set in ipairs(logic.JUNCTION_SETS) do setLabels[i] = string.format("%s (%d)", set.label, #set.ids) end
	local spacingLabels : {string} = {}
	for i, m in ipairs(logic.JUNCTION_SPACINGS) do spacingLabels[i] = string.format("%g km", m / 1000) end
	return {
		head("Junction test", {
			primary(junctions.label(), "Create a grid of test towns (\"Grid A1\", ...) with one Roundabouts & Interchanges junction in the middle of every cell, its arms linked by road to the four corner towns. No other roads join the towns, so all traffic between them drives through the junctions",
				notDuringBench(function() junctions.build() end)),
		}),
		hbox({ label("Junctions"), choice(setLabels, ui.set, function(i : integer) ui.set = i end) }, "sqst-row"),
		hbox({ label("Spacing"), choice(spacingLabels, ui.spacing, function(i : integer) ui.spacing = i end) }, "sqst-row"),
		hbox({ label("Size"), choice(sizeLabels, ui.size, function(i : integer) ui.size = i end) }, "sqst-row"),
		hbox({
			label("Centre"),
			choice({ "Map centre", "Camera" }, ui.centre, function(i : integer) ui.centre = i end),
		}, "sqst-row"),
		hbox({ label("Streets"), choice(logic.GRID_STREETS, ui.streets, function(i : integer) ui.streets = i end) }, "sqst-row"),
		hbox({ label("In line"), choice(logic.JUNCTION_INLINE, ui.inline, function(i : integer) ui.inline = i end) }, "sqst-row"),
		hbox({ label("Lights"), choice(logic.JUNCTION_LIGHTS, ui.lights, function(i : integer) ui.lights = i end) }, "sqst-row"),
		hbox({ label("Traffic"), choice(logic.TEST_TRAFFIC, ui.traffic, function(i : integer) ui.traffic = i end) }, "sqst-row"),
		hint(junctions.caseNames() .. " Roads are large country roads, highway arms stay highways. In line: as many extra junctions as fit on every route to a town, each a different layout (roundabouts on roads, interchanges on highways); wider spacing fits more (4 km: about 3 per road route). Use an empty flat map (Blank Slate); each junction's [SQST] line lists its arms and the towns they reach. Traffic = Bus lines: after the build, two bus lines per junction between its opposite corner towns, so both drive straight through it and cross there (at most " .. tostring(logic.TEST_ROUTES_MAX) .. " lines), with the Traffic tab's Auto bus lines Buses count. Remove towns > Grid towns removes the towns; Remove all roads the junctions; Traffic tab > Remove added bus lines the lines."),
	}
end

--- The Showcase section (Towns tab), only with square_roundabouts enabled (the Junction test's hint
--- covers it otherwise). One button, no options (user 2026-10-12): a fresh seed per press, Keep balance
--- on, bus lines after the build; the queue line shows the progress.
--- The Bench section (Towns tab, plans/square_stress_test/BENCH.md): one button per sheet. A press checks what it
--- can at once (a dialog says what is missing), then a confirm dialog with the plan for this map; OK runs the whole
--- sheet (clear the map, build, record, screenshots) with no further input. The status line shows the phase.
local function confirmBench(key : string)
	local sheet = benchrun.sheetFor(key)
	if sheet == nil then return end
	local problems = benchrun.check(key)
	if #problems > 0 then
		rt.warn(sheet.title, table.concat(problems, "\n"))
		return
	end
	local what = "builds the bench, records %d game minutes of traffic at %dx and takes a screenshot of each test. About 15-25 minutes"
	if sheet.city ~= nil then
		what = "builds the cities and lights every inner crossing, records %d game minutes of traffic at %dx (Smart Lanes' automatic timing starts at the auto cities after "
			.. string.format("%d", math.floor((sheet.baselineS or 0) / 60)) .. " of them) and takes a screenshot of each city. About "
			-- the warm-up and the record at its speed, plus ~10 min of clearing, build (~5-8 min) and shots
			.. string.format("%d", math.floor((benchlib.recordS(sheet) + benchlib.WARMUP_S) / 60 / benchlib.speed(sheet) + 10.5)) .. " minutes"
	end
	local opts = ""
	if sheet.city ~= nil then
		opts = "\n\n" .. benchlib.cityOptionsText(sheet)
		if benchrun.cityUi.sameSeed and benchrun.lastCitySeed ~= nil then
			opts = opts .. string.format(" Seed: %d (the last city run's).", benchrun.lastCitySeed)
		end
	end
	local optsFmt = opts:gsub("%%", "%%%%")
	confirm(sheet.title, string.format("%s." .. optsFmt .. "\n\nThis removes every town and every road on the map first, sets the year to %d if earlier, " .. what .. "; leave the game running and unpaused. Use a fresh %g km Blank Slate map.",
		benchrun.planLine(key), benchlib.YEAR, math.floor(benchlib.recordS(sheet) / 60), benchlib.speed(sheet), sheet.minKm), "Run bench", function()
		benchrun.start(key)
	end)
end

local function benchItems() : {TreeNodeId}
	local buttons : {TreeNodeId} = {}
	for _, sh in ipairs(benchlib.SHEETS) do
		local key = sh.key
		buttons[#buttons + 1] = primary(sh.button or ("Sheet " .. key:sub(2)), sh.title .. ". One press: clears the map, builds, records the traffic and takes screenshots", function() confirmBench(key) end)
	end
	local lines : {string} = {}
	for _, sh in ipairs(benchlib.SHEETS) do
		local tests : {string} = {}
		for _, t in ipairs(sh.tests) do tests[#tests + 1] = string.format("%s (%d sets: %s)", t.title, t.sets, table.concat(t.twins, " / ")) end
		lines[#lines + 1] = string.format("%s: %s.", sh.button or ("Sheet " .. sh.key:sub(2)), table.concat(tests, "; "))
	end
	local status = benchrun.status()
	local items : {TreeNodeId} = {
		head("Bench", buttons),
		hint(table.concat(lines, " ") .. " Every junction is built as twins side by side (game default / Smart Lanes / a Smart Lanes test mode) with a town on every arm that needs traffic. Needs a fresh 16 km Blank Slate map, Smart Lanes (Apply automatically On; sheets 1, 2, 4, 5, 6 and Micro: No lights at roundabouts and ramps On) and, for sheets 1, 2, 4, 5, 6 and Micro, Roundabouts & Interchanges. Sheet 5 (ring lane use) runs each ring under three traffic mixes and logs every ring twin's turning mix and lane use; sheet 6 runs Smart Lanes' mid-node default under heavy traffic (30 game minutes). Micro is a small sheet for one-off tests (its tests are swapped in the mod's code). When the status says done, run make bench."),
	}
	if status ~= "" then items[#items + 1] = hint(status) end
	return items
end

local function showcaseItems() : {TreeNodeId}
	if not junctions.available() then return {} end
	return {
		head("Showcase", {
			primary(logic.showcaseLabel(), "Fill the map with groups: one junction (every interchange, roundabout and plain crossing type in turn, random settings) with a small or medium town on every arm. Each group is built side by side as twins with identical settings (Smart Lanes / game default), for an A/B comparison under the same traffic",
				notDuringBench(function() junctions.buildShowcase() end)),
		}),
		hint("Each press draws a new seed (in the log's first [SQST] showcase line). Use an empty flat map (Blank Slate) and Remove towns > All towns first. The build turns Keep balance on, builds a bus depot for every route while the towns are still small, grows the towns x10 locked into their grids, then adds bus lines across every group. A 16 km map takes a few minutes. With Smart Lanes enabled, the twins' zones go to it first: it leaves the game-default twins alone and gives the light-phase twins its phases. Remove towns > Grid towns and Remove all roads clean it up (and clear the zones)."),
	}
end

--- The City lights options (BENCH.md "Funnel layouts"): Layout and Baseline as choices, Busy / Swap roles / Same seed as
--- checkboxes; the confirm dialog repeats them.
local function cityOptionItems() : {TreeNodeId}
	local u = benchrun.cityUi
	local items : {TreeNodeId} = {
		hbox({ label("Layout"), choice(benchlib.CITY_LAYOUT_LABELS, u.layout or 1, function(i : integer) u.layout = i end) }, "sqst-row"),
		hbox({ label("Baseline"), choice(benchlib.CITY_BASELINE_LABELS, u.baseline or 1, function(i : integer) u.baseline = i end) }, "sqst-row"),
		builtin.CheckBox{
			value = u.busy and 1 or 0,
			onValueChange = function(v : integer) u.busy = v == 1 end,
			label = string.format("Busy: about %d people per city instead of %d", math.floor(benchlib.CITY_BUSY.pop), math.floor(benchlib.CITY.city.pop)),
		},
		builtin.CheckBox{
			value = u.swap and 1 or 0,
			onValueChange = function(v : integer) u.swap = v == 1 end,
			label = "Swap roles: the other city of each pair gets the automatic timing",
		},
	}
	if benchrun.lastCitySeed ~= nil then
		items[#items + 1] = builtin.CheckBox{
			value = u.sameSeed and 1 or 0,
			onValueChange = function(v : integer) u.sameSeed = v == 1 end,
			label = string.format("Same seed as the last city run (%d)", benchrun.lastCitySeed),
		}
	end
	return items
end

--- The Lights showcase section (Towns tab): one button, no options (user 2026-10-12, SHOWCASE.md "Lights
--- showcase"). Only lit plain crossings (our own construction), so it needs no other mod; Smart Lanes
--- gives its twins their modes. Every shape on one map (stress_logic.lightsMixedSpec), the same press every time.
local function lightsShowcaseItems() : {TreeNodeId}
	local autoStatus = slzones.autoStatus()
	local items : {TreeNodeId} = {
		head("Lights showcase", {
			primary(logic.lightsShowcaseLabel(), "Fill the map with every lit junction shape (2x2 X, 3x3 X, 3x2 X, T 2x2, lanes each way), " .. string.format("%d", logic.LIGHTS_PER_TYPE) .. " sets of each, with a medium town on every arm. Each set is built three times side by side: Smart Lanes, the game default and Smart Lanes with every turn fanned into the exit lanes",
				notDuringBench(function() junctions.buildLightsShowcase() end)),
			button(logic.lightsPlansLabel(), "A focused light-plan A/B: a 2-lane (2x2 X) and a 3-lane (3x3 X) lit crossroads, " .. string.format("%d", logic.LIGHTS_PLANS_PER_TYPE) .. " sets of each, every set built three times side by side: the game's light phases, Smart Lanes' axis plan and the axis plan with its timing kept adjusted. Busier towns (about " .. string.format("%d", logic.LIGHTS_PLANS_TARGET_POP) .. " people each); every second set unbalanced (a small north town, a tiny south town)",
				notDuringBench(function() junctions.buildLightPlans() end)),
		}),
		hint("Like the Showcase, for traffic lights: every 90 deg lit shape (2x2 X, 3x3 X, 3x2 X: main 3 lanes each way, side 2; T 2x2), " .. string.format("%d", logic.LIGHTS_PER_TYPE) .. " sets of each, every set as three twins a, b, e (Smart Lanes / game default / Smart Lanes exit-lane fan), so the twins compare under the same traffic; a new seed per press. All 12 sets, with every twin once in every position per shape (a position-balanced comparison), need a 20 km map; a 16 km map holds 6 sets, positions not balanced. Use an empty flat map (Blank Slate) from 1950 on (the game's lights) and Remove towns > All towns first. The build turns Keep balance on; every link is a large country road (3 lanes each way) and enters its town through a 3-lane roundabout (2 lanes where 3 is refused) at the middle of the grid's side (before 1940: the grid's crossroads), so the town entry is never the bottleneck; the towns stay locked inside their grids (country ring and country links: no houses outside) and grow once after the links, to about " .. string.format("%d", logic.LIGHTS_TARGET_POP) .. " people each (each town from its own capacity; denser, not wider). No bus lines: the towns' own traffic. About 2 minutes on a 16 km map. Remove towns > Grid towns and Remove all roads clean it up."),
		hint("Build light plans A/B: the same build for comparing light plans at busy junctions: 2x2 X and 3x3 X, " .. string.format("%d", logic.LIGHTS_PLANS_PER_TYPE) .. " sets each (fits a 16 km map), twins b, c, v (game default / Smart Lanes axis plan / the axis plan with its timing kept adjusted; towns \"Game default\", \"Smart phases\", \"Auto timing\"). Balanced and unbalanced sets in turn: in a balanced set every town has about " .. string.format("%d", logic.LIGHTS_PLANS_TARGET_POP) .. " people; in an unbalanced one the east and west towns about " .. string.format("%d", logic.LIGHTS_PLANS_POPS.busy) .. ", the north town about " .. string.format("%d", logic.LIGHTS_PLANS_POPS.small) .. " (\"small\") and the south town about " .. string.format("%d", logic.LIGHTS_PLANS_POPS.tiny) .. " (\"tiny\"). Needs Smart Lanes with the sl_auto zone mode (rev 8). Turn the Traffic log on and run at 4x for 90 game minutes after the build (the auto twins first re-time about 16 game minutes after the build and settle after about 45), then make flow. Press Auto re-time > Clear when done."),
		head("Auto re-time", {
			button("All lit junctions", "Smart Lanes keeps the timing of every lit junction on the map adjusted (its Keep timing adjusted, at most 1000 junctions): takes a queue snapshot every 2 game minutes and re-times each junction from about 16 game minutes on, every 10-60 minutes. Junctions lit later are not included: press again. For a before / after run on any lit map: Traffic log on, wait 15 game minutes, press, run 90 more, make flow",
				notDuringBench(function() slzones.sendAuto("all", "button") end)),
			button("Clear", "Stops Smart Lanes' automatic re-timing at every junction (the zones of a light plans A/B build do not stop it by themselves). Timing already written stays",
				notDuringBench(function() slzones.sendAuto("clear", "button") end)),
		}),
		head("City lights at scale", {
			button(benchlib.CITY.button, benchlib.CITY.title .. ". One press: clears the map, builds the cities, lights every inner crossing, records the traffic before and after Smart Lanes' automatic timing starts, takes screenshots",
				function() confirmBench(benchlib.CITY.key) end),
		}),
	}
	for _, it in ipairs(cityOptionItems()) do items[#items + 1] = it end
	local cs = benchrun.sheetFor(benchlib.CITY.key)
	items[#items + 1] = hint(string.format("%d big grid towns (Large, about %d people each wanted, the wide 800 m street grid, %d lit crossings each) in pairs: Smart Lanes keeps re-timing every light of one city of each pair (Auto re-time for its junctions), the other never (control). Traffic log on at %dx: %d game minutes as they are, then the automatic timing starts at the auto cities, then %d more. Layout: Hourglass leaves out a band through the middle except the 3 central streets (all traffic between the halves goes through that neck); Holes leaves out the inner streets of 4 blocks of 2 x 2 (placed by the seed, the same in every city). Busy wants about 2.5 times the people (the grid's lots may cap it; the log has the real number). Swap roles: run again with the same seed and Swap roles on; the report pairs the two runs. Needs Smart Lanes rev 8 with its Debug: performance log On (or DEV SQPERF: all mods): the report reads its frame times. When the status says done, run make flow (section Auto lights at scale).",
		cs.city.pairs * (cs.city.control and 2 or 1), math.floor(cs.city.pop), benchlib.cityLayout(cs).crossings, benchlib.speed(cs),
		math.floor((cs.baselineS or 0) / 60), math.floor((benchlib.recordS(cs) - (cs.baselineS or 0)) / 60)))
	if autoStatus ~= "" then items[#items + 1] = hint(autoStatus) end
	return items
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
	local gridLayoutLabels : {string} = {}
	for i, g in ipairs(logic.GRID_LAYOUTS) do gridLayoutLabels[i] = g.label end
	local gridSpacingLabels : {string} = {}
	for i, m in ipairs(logic.GRID_SPACINGS) do gridSpacingLabels[i] = string.format("%g km", m / 1000) end
	local items : {TreeNodeId} = {
		text(readout, "font-scale-body, sqst-readout"),
		head("Development", {
			button("Freeze all", "Stop the development of every town", function() towns.setDevelopment(false) end),
			button("Unfreeze all", "Let every town develop again", function() towns.setDevelopment(true) end),
		}),
		head("Grow", {
			primary(towns.growLabel(), "Multiply the size factors of the target town(s) and update all buildings; each extra pass re-sends the update to build more (Reset: back to 1, one pass; existing buildings may stay)",
				notDuringBench(function() towns.growSelected() end)),
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
				notDuringBench(function() towns.spawn() end)),
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
		head("Test grid", {
			primary(towns.gridLabel(), "Create identical towns (\"Grid A1\", ...) at exact, equally spaced grid positions, all with the same seed, size and street angle; nothing is placed if a point is on water or off the map",
				notDuringBench(function() towns.spawnGrid() end)),
		}),
		hbox({ label("Layout"), choice(gridLayoutLabels, ui.gridLayout, function(i : integer) ui.gridLayout = i end) }, "sqst-row"),
		hbox({ label("Spacing"), choice(gridSpacingLabels, ui.gridSpacing, function(i : integer) ui.gridSpacing = i end) }, "sqst-row"),
		hbox({ label("Size"), choice(sizeLabels, ui.gridSize, function(i : integer) ui.gridSize = i end) }, "sqst-row"),
		hbox({
			label("Centre"),
			choice({ "Map centre", "Camera" }, ui.gridCentre, function(i : integer) ui.gridCentre = i end),
		}, "sqst-row"),
		hbox({ label("Roads"), choice(logic.GRID_CONNECT, ui.gridConnect, function(i : integer) ui.gridConnect = i end) }, "sqst-row"),
		hbox({ label("Streets"), choice(logic.GRID_STREETS, ui.gridStreets, function(i : integer) ui.gridStreets = i end) }, "sqst-row"),
		hint("For traffic tests between towns: a flat map (Blank Slate generator), Remove towns > All towns (or an empty Map Editor map), create the grid, then Freeze all so the towns stay equal. Roads are the game's own town links; delete them to build your own. Streets = Wide grid first builds a square grid of large 4-lane town streets (400-800 m by size) where each town goes, so the town grows along wide roads; 'Wide grid, locked' also marks those streets so the town may not change or extend them (the flag of the game's Player owned road tool), and builds the grid's outer ring (perimeter and corner stubs) as a large country road, which gets no houses, so the town stays inside its grid."),
	}
	for _, item in ipairs(crossingItems(sizeLabels)) do items[#items + 1] = item end
	for _, item in ipairs(junctionItems(sizeLabels)) do items[#items + 1] = item end
	for _, item in ipairs(benchItems()) do items[#items + 1] = item end
	for _, item in ipairs(showcaseItems()) do items[#items + 1] = item end
	for _, item in ipairs(lightsShowcaseItems()) do items[#items + 1] = item end
	for _, item in ipairs({
		head("Remove towns", {
			primary(towns.removeLabel(), "Destroy the target town(s) with all their streets and buildings, one after another (the game's own town removal, as the map editor uses it). Cannot be undone",
				notDuringBench(confirmRemoveTowns)),
		}),
		hbox({ label("Target"), choice(logic.REMOVE_TARGETS, ui.removeTarget, function(i : integer) ui.removeTarget = i end) }, "sqst-row"),
		hint("Grid towns = the test towns: Test grid's and the Junction and Crossing tests' \"Grid A1\" ..., the Showcases' (\"Parclo 3 N (Smart lanes)\", \"Smart lanes 1 N\") and any town those tests made this session. Removes the town's streets and buildings too; save first."),
		head("Remove roads", {
			primary("Remove all roads", "Remove every street on the map in batches (town streets and your own roads). Streets that are part of a station, depot or other construction stay. Tracks are not touched. Cannot be undone",
				notDuringBench(confirmRemoveRoads)),
		}),
		hint("Towns rebuild their streets while they develop: remove or freeze the towns first. Save first."),
	}) do items[#items + 1] = item end
	return vbox(items, "sqst-tab")
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
	local flowIntervalLabels : {string} = {}
	for i, sec in ipairs(flowlib.INTERVALS) do flowIntervalLabels[i] = tostring(sec) .. " s" end
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
			primary("Clear traffic", "Send every person driving a car right now home (debug command \"jump home\"), only those in or outside towns with Where; your own vehicles are never touched",
				function() traffic.clearTraffic() end),
			button("Scan", "Count the persons driving now and every person's last trip mode (DRIVE / WALK / LINES) for the readout above, without clearing anything",
				function() traffic.scan() end),
		}),
		hbox({ label("Where"), choice(logic.CLEAR_WHERE, ui.clearWhere, function(i : integer) ui.clearWhere = i end) }, "sqst-row"),
		builtin.CheckBox{
			value = ui.keepCleared and 1 or 0,
			onValueChange = function(v : integer) traffic.setKeepCleared(v == 1) end,
			label = "Keep traffic cleared (repeats the clear, this session only)",
		},
		hbox({ label("Every"), choice(intervalLabels, ui.clearInterval, function(i : integer) traffic.setClearInterval(i) end) }, "sqst-row"),
		hint("Sends drivers home (debug command); they start new trips after a few seconds, so use Keep cleared for an empty road. Your own vehicles are never touched. Where = In towns clears town streets only, so traffic between towns (and through the Junction test's junctions) keeps driving; a town's area is the circle around its buildings + 60 m."),
		hint("Driving now = cars on the road at the last scan (Scan or a clear); Last trip mode = how every person made their last trip. Car traffic grows with town population (Towns tab) and with the load-time settings \"Sim person trip recalculation\", \"Car traffic\" and \"Town building capacity\"."),
		head("Traffic log", {}),
		builtin.CheckBox{
			meta = { tooltip = logic.wrapText("Write the traffic of every Showcase junction (cars, speed, standing cars) and of the whole map to stdout.txt at every interval, for an A/B comparison with make flow. This session only; reads only, changes nothing", TOOLTIP_WIDTH) },
			value = flowlog.ui.on and 1 or 0,
			onValueChange = function(v : integer)
				local ok, err : boolean, any = pcall(flowlog.setOn, v == 1)
				if not ok then rt.log("[SQST] traffic log error: " .. tostring(err)) end
			end,
			label = "Traffic log (stdout.txt, this session only)",
		},
		hbox({ label("Every"), choice(flowIntervalLabels, flowlog.ui.interval, function(i : integer)
			local ok, err : boolean, any = pcall(flowlog.setInterval, i)
			if not ok then rt.log("[SQST] traffic log error: " .. tostring(err)) end
		end) }, "sqst-row"),
		text(flowlog.status(), "font-scale-annotation, sqst-readout"),
		hint("Game seconds between samples (a paused game takes none). Zones: the Showcase's junctions (after a reload: the zones Smart Lanes saved). Each sample writes [SQST] FLOW lines; run 15-20 game minutes, then make flow. Keep traffic cleared distorts the flow: leave it off."),
		head("Auto bus lines", {
			primary(buslines.label(), "Per town: two bus stops 300-800 m apart on its streets, a line between them, a road depot (one that reaches the line, one of ours nearby, or a new one) and the buses",
				function() buslines.addBusLines() end),
		}),
		hbox({ label("Towns"), choice(logic.BUS_TOWN_CHOICES, bl.towns, function(i : integer) bl.towns = i end) }, "sqst-row"),
		hbox({ label("Lines"), choice(lineLabels, bl.lines, function(i : integer) bl.lines = i end) }, "sqst-row"),
		hbox({ label("Buses"), choice(busLabels, bl.buses, function(i : integer) bl.buses = i end) }, "sqst-row"),
		hint(string.format("Lines per town, buses per line (the newest bus on sale). One step at a time; a town stops at its first failure and the batch after %d failed towns in a row. Without Keep balance it stops when the money runs out.", buslines.MAX_TOWN_FAILS)),
		head("Added bus lines", {
			button(buslines.removeLabel(), "Sell the buses added by Auto bus lines (and the Junction / Crossing test's Traffic) in this session, then delete their lines (forgotten on reload)",
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
		hint("Developer experiments: probes 1-10 change the save (11 Flow only reads); each logs one [SQST-PROBE] <name> ok|fail line to stdout.txt. Use a test save."),
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
		hideNotifications = rt.hideNotifications, towns = townsLine, townsUi = towns.uiSignature() .. "|" .. junctions.uiSignature() .. "|" .. junctions.crossSignature() .. "|" .. junctions.showcaseSignature() .. "|" .. junctions.lightsSignature() .. "|" .. benchrun.status() .. "|" .. benchrun.cityUiSignature(), traffic = trafficLine, trafficUi = traffic.uiSignature() .. "|" .. buslines.uiSignature() .. "|" .. flowlog.uiSignature() }
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

-- Window fields differ by platform: the PS5 build rejects `closable` and react.lua makeUserdata then fails
-- the whole UI (docs/findings/gui.md "Window fields differ by platform"). Each field is tried once on a spare
-- Window param object; a field this platform rejects is left out and logged once. Nodes and meta aren't tried.
local windowFieldOk : {string : boolean} = {}
local function platformWindow<T>(p : T) : T
	local t = p as {string : any}
	for k, v in pairs(t) do
		if k ~= "content" and k ~= "header" and k ~= "meta" then
			local key = k .. "=" .. (v is boolean and tostring(v) or type(v))
			if windowFieldOk[key] == nil then
				local made, ud = pcall(function() : {string : any}
					local reactApi = ((api as table).gui as table).react as table
					local builtins = (reactApi.params as table).builtin as table
					return ((builtins.Window as table).new as function() : {string : any})()
				end)
				-- no spare object to try on: keep the field, as before this guard
				windowFieldOk[key] = not made or pcall(function() ud[k] = v end)
				if not windowFieldOk[key] then
					log.warning("[SQST] this platform's Window rejects '" .. key .. "'; left out")
				end
			end
			if not windowFieldOk[key] then t[k] = nil end
		end
	end
	return p
end

-- The dialog where the base DialogWindow is missing (dialogRecipe): the base one's shape (dialog_react_util.tl:
-- 60-140: the text, then one button per choice; a click closes, then runs the choice) from builtin widgets only.
SquareStressDialog = react.RegisterWrapperRecipe("SquareStressDialog", builtin.Window, function(params : DialogReactUtil.DialogWindowParam) : TreeNodeId
	local buttons : {TreeNodeId} = {}
	for _, choice in ipairs(params.choices or {}) do
		buttons[#buttons + 1] = builtin.Button{
			content = text(choice.text),
			onClick = function()
				params.onClose()
				if choice.onClick ~= nil then choice.onClick() end
			end,
		}
	end
	return builtin.Window(platformWindow{
		title = params.windowTitle,
		closable = true,
		movable = false,
		initialX = params.x,
		initialY = params.y,
		onClose = params.onClose,
		content = vbox({ text(params.displayText or ""), builtin.FlowLayout{ children = buttons } }),
	})
end)

local SquareStressWindow = react.RegisterWrapperRecipe("SquareStressWindow", builtin.Window, function(params : SquareStressWindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210
	return builtin.Window(platformWindow{
		id = WINDOW_ID,
		title = "Stress Test Debug Tool",
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = SquareStressContent(),
	})
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

-- "Icon" style (mod.json hudButtonStyle): gauge mask, gauge@2x.tga 48x48 (tools/render_icon_ridge.py),
-- shown at 24 UI px like the base layers icon and Better Minimap's map icon.
local HUD_ICON <const> = "square_stress_test::/stress/gui/gauge.tga"

--- mod.json hudButtonStyle: { "Text", "Icon" } (1-based index; default Icon). Missing or unreadable = Icon.
--- Read once per mount: mod params are fixed per game.
local function hudIconSetting() : boolean
	local ok, all = pcall(function() : {string : any} return api.engine.config.getModParams() as {string : any} end)
	local mine = ok and type(all) == "table" and all["square_stress_test"] as {string : any} or nil
	local v = type(mine) == "table" and mine["hudButtonStyle"] or nil
	return v ~= 1
end

--- The "Icon" ToggleButton's inline styles: only its size, 8 px padding around the 24 px icon (a 40 px
--- tile, like the layers and Timetables buttons in game). The tile, its pressed and
--- hover states and the white icon come from the base ToggleButton rules (builtin.css.lua:138-240).
--- No stylesheet rules (docs/findings.md "Load crash above ~200 mod stylesheet rules"). Built once.
local hudIconStyles : {StyleSheet} = nil
local function iconStyles() : {StyleSheet}
	if hudIconStyles == nil then
		local button = styleutil.makeStyle{}
		button.padding = api.type.Vec4f.new(8, 8, 8, 8)
		hudIconStyles = { button, styleutil.makeStyle{ size = { 24, 24 } } }
	end
	return hudIconStyles
end

local SquareStressHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "SquareStressHudPlugin", function() : TreeNodeId
	-- Hooks first, unconditionally (same order as square_problem_radar's plugin).
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	local iconRef : ReactRefT<boolean> = react.useRefLazy(hudIconSetting)
	-- The "Icon" ToggleButton is pressed while the window is open, however it was closed.
	local openState = react.useState(false) as ReactStateT<boolean>
	local function syncOpen()
		local open = windowState ~= nil and not windowState:hasExpired()
		if open ~= openState:old() then openState:set(open) end
	end
	react.onStep(function()
		if isMapEditorRef:get() then return end
		if iconRef:get() then syncOpen() end
		local ok, err : boolean, any = pcall(rt.tick)
		if not ok then log.warning("[SQST] tick error: " .. tostring(err)) end
		if #rt.warnings > 0 then
			local okW, errW : boolean, any = pcall(showWarnings)
			if not okW then
				alertOpen = false
				log.warning("[SQST] warning dialog error: " .. tostring(errW))
			end
		end
	end)
	if isMapEditorRef:get() then
		return nil
	end
	local tooltip = "Stress Test Debug Tool"
	local button : TreeNodeId
	if iconRef:get() then
		-- a base ToggleButton like the data layers button next to it (layers_button_ridge.tl:529-539)
		button = builtin.ToggleButton{
			meta = { class = "sqst-hud-icon-button", styleSheet = iconStyles()[1], tooltip = tooltip },
			content = builtin.ImageView{ meta = { class = "sqst-hud-icon", styleSheet = iconStyles()[2] }, path = HUD_ICON },
			value = openState:old() and 1 or 0,
			onValueChange = function(__ : integer)
				toggleWindow()
				syncOpen()
			end,
		}
	else
		button = builtin.Button{
			meta = { class = "sqst-hud-button", tooltip = tooltip },
			content = text("Debug"),
			onClick = toggleWindow,
		}
	end
	-- A plugin root must be a layout (MainModButtonArea mounts plugins as BoxLayout children).
	return builtin.BoxLayout{
		meta = { class = "sqst-box" },
		orientation = builtin.type.Orientation.Horizontal,
		children = { button },
	}
end)

return {
	SquareStressHudPlugin = SquareStressHudPlugin,
}
