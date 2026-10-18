-- Problem Radar fleet window (rev 6, plans/square_problem_radar/FLEET_UPGRADE.md): opened from the ↑
-- button of a fleet_old / fleet_worn row. Shows the vehicle's line (stats, 12-month money split), its
-- fleet grouped by composition, and "Upgrade" buttons that open the GAME's own Replace window
-- (the vehicle window's Replace button, .cache/game/base/content/gui/entity_window/vehicle/vehicle.tl:445-462).
-- That window is the picker and the confirmation (year/carrier/cargo filters, multiple units, the
-- price, money checks). This file never sends a command: nothing here changes the save.
--
-- POLL: useStepStateTimer every POLL_SECONDS (onStepTimer: worker thread, docs/findings.md "Timers and
-- threads in GUI contexts"): engine reads only, then the pure model (radar_fleet_model.tl). Texts,
-- _() and api.util formatting happen in render (GUI thread).
-- Window: same pattern as the radar window (radar_hud.script.tl ProblemRadarWindow; base
-- .cache/game/base/content/gui/menu/main_page.tl:44-63), centred by id in radar_hud.css.lua.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl" as LineUtil
local vehicle_store_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl" as VehicleStoreUtil
local vehicle_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl" as VehicleUtil

local fleet_model = ug_require "square_problem_radar::/radar/gui/radar_fleet_model.tl" as ProblemRadarFleetModel
local radar_checks = ug_require "square_problem_radar::/radar/radar_checks.tl" as ProblemRadarChecks
-- INLINE STYLES (rev 6): StyleSheets that replace radar_hud.css.lua rules (radar_inline.tl).
local radar_inline = ug_require "square_problem_radar::/radar/gui/radar_inline.tl" as ProblemRadarInline

local M : ProblemRadarFleet = {}

local POLL_SECONDS <const> = 2.0
local WINDOW_ID <const> = "squareproblemradar.fleet" -- radar_hud.css.lua centres "#squareproblemradar.fleet"

-- SQPERF instance of radar_hud.script.tl (setPerf); a no-op stand-in until it is set.
local perf : SquareProblemRadarSqPerfInst = nil

local function perfStart() : number
	return perf ~= nil and perf:start() or 0
end

local function perfStop(name : string, t : number)
	if perf ~= nil then perf:stop(name, t) end
end

---------------------------------------------------------------------------
-- Engine reads (poll; worker thread: no api.gui, no _()).

-- Model id -> display name / lifespan, cached for the GUI state's lifetime (models don't change
-- in game). Name: the model's description.name, as the base store shows it
-- (vehicle_store_util.tl:445-480 getVehicleNameAndIcons -> makeSingleVehicle desc.name).
local modelNames : {integer : string} = {}
local modelLifespans : {integer : integer} = {}

local function modelName(id : integer) : string
	local n = modelNames[id]
	if n == nil then
		local ok, v = pcall(function() : string
			local m = api.res.modelRep.get(id)
			local desc = m ~= nil and m.metadata ~= nil and m.metadata.description as ModelMetadata.Description or nil
			return desc ~= nil and desc.name or nil
		end)
		n = ok and type(v) == "string" and v or ""
		modelNames[id] = n
	end
	return n
end

--- vehicle_util.getLifespan (vehicle_util.tl:31-34); 0 = none. Same as radar.script.tl lifespanOf.
local function lifespanOf(id : integer) : integer
	local life = modelLifespans[id]
	if life == nil then
		local ok, l = pcall(vehicle_util.getLifespan, id)
		life = ok and type(l) == "number" and l as integer or 0
		modelLifespans[id] = life
	end
	return life
end

local function getTv(v : integer) : Engine.Component.TransportVehicle
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
end

--- One vehicle: composition key + name, the oldest part's age and lifespan (radar.script.tl
--- purchaseAndLifespan = vehicle_util.getMinPurchaseTimeAndLifespan, vehicle_util.tl:36-52), condition.
local function readVehicle(v : integer, now : integer, names : {string : string}) : ProblemRadarFleetVehicle
	local tv = getTv(v)
	local parts = tv ~= nil and tv.transportVehicleConfig ~= nil and tv.transportVehicleConfig.vehicles or nil
	local out : ProblemRadarFleetVehicle = { entity = v, key = "" }
	if parts == nil or #parts == 0 then return out end
	local ids : {integer} = {}
	local minPurchase, minLife : integer, integer = nil, nil
	for i, p in ipairs(parts) do
		ids[i] = p.part.modelId
		local life = lifespanOf(p.part.modelId)
		if minPurchase == nil or p.purchaseTime < minPurchase or (p.purchaseTime == minPurchase and life < minLife) then
			minPurchase, minLife = p.purchaseTime, life
		end
	end
	out.key = fleet_model.compositionKey(ids)
	if names[out.key] == nil then names[out.key] = fleet_model.compositionName(ids, modelName) end
	out.ageMs = now - minPurchase
	out.lifespanMs = minLife
	-- notifications.script.tl:307-320 / radar.script.tl scanFleet: the base vehicle condition
	out.condition = api.engine.util.vehicle.getVehicleMaintenanceState(v)
	return out
end

--- 12-month cost split types: radar.script.tl costTypes (api.type.JournalEntry.Maintenance VEHICLE =
--- "Running Costs Vehicles", VEHICLE_MAINTENANCE = "Maintenance Vehicles", finances_util.tl:68-73).
local function costTypes() : any, any
	local JE = api.type.JournalEntry
	local CT = JE ~= nil and JE.Maintenance or nil
	if CT ~= nil and CT.VEHICLE ~= nil and CT.VEHICLE_MAINTENANCE ~= nil then
		return CT.VEHICLE, CT.VEHICLE_MAINTENANCE
	end
	return nil, nil
end

--- The line's numbers, as the base line window reads them:
--- * capacity / used: getLineCapacityUsages(line, false), summed over cargo types (cargo_util.tl:709-711)
--- * interval: line_util.calculateFrequencySeconds (line_util.tl:1350-1354; statistic_lines.tl:207-214)
--- * transported: logbook itemsTransported per year (line_react_util.tl:642-658)
--- * balance: calculateBalance({line}, now - year, now, true) (line_react_util.tl:620-640), split
---   like radar.script.tl measureMoney.
local function readLine(raw : ProblemRadarFleetRaw, line : integer, now : integer)
	local used, cap : number, number = 0, 0
	for __, u in pairs(api.engine.util.line.getLineCapacityUsages(line, false) or {}) do
		if u ~= nil and (u.capacity or 0) > 0 then
			used = used + (u.used or 0)
			cap = cap + u.capacity
		end
	end
	raw.used, raw.capacity = math.floor(used), math.floor(cap)
	raw.intervalS = line_util.calculateFrequencySeconds(line)
	raw.transported = api.engine.util.logbook.getLogValuePerYear(line, "itemsTransported")
	local calc = api.engine.util.finance.calculateBalance
	-- 12 months as the base line window counts them: the default year (line_react_util.tl:620-640).
	local from = math.max(now - api.util.getDefaultYearDuration(), 0)
	raw.balance = calc({ line }, from, now, true)
	local vehicleType, maintType = costTypes()
	if vehicleType ~= nil then
		raw.running = calc({ line }, from, now, true, vehicleType as JournalEntry.Maintenance)
		raw.maintenance = calc({ line }, from, now, true, maintType as JournalEntry.Maintenance)
	end
end

--- Years in the window are calendar years at the current calendar speed, like the base vehicle
--- window's Age (radar_checks.calendarYearMs); the radar's Old rows use the same (radar.script.tl scanFleet).
local function calendarYearMs() : integer
	local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	return radar_checks.calendarYearMs(gs ~= nil and gs.millisPerDay or 0, api.util.getYearDuration, api.util.getDefaultYearDuration())
end

local function readFleet(vehicle : integer, wornAt : number) : ProblemRadarFleetRaw
	if vehicle == nil or not api.engine.entityExists(vehicle) then return { vehicle = vehicle, gone = true } end
	local tv = getTv(vehicle)
	if tv == nil then return { vehicle = vehicle, gone = true } end
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	local now = gt.gameTime
	local raw : ProblemRadarFleetRaw = {
		vehicle = vehicle,
		vehicles = {},
		names = {},
		yearMs = calendarYearMs(),
		wornAt = wornAt,
		multiUnit = vehicle_store_util.acceptsMultiVehicle(tv.carrier),
	}
	local line = tv.line
	if line ~= nil and line > 0 and api.engine.entityExists(line) then
		raw.line = line
		for __, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line) or {}) do
			raw.vehicles[#raw.vehicles + 1] = readVehicle(v, now, raw.names)
		end
		readLine(raw, line, now)
	else
		raw.vehicles[1] = readVehicle(vehicle, now, raw.names)
	end
	return raw
end

--- Window poll (onStepTimer): never errors (a failed read shows the "gone" text until the next poll).
local function pollView(vehicle : integer, wornAt : number) : ProblemRadarFleetView
	local t = perfStart()
	local ok, raw = pcall(readFleet, vehicle, wornAt)
	if not ok then
		log.warning("[ProblemRadar] fleet window read failed: " .. tostring(raw))
		raw = { vehicle = vehicle, gone = true }
	end
	local view = fleet_model.build(raw as ProblemRadarFleetRaw)
	perfStop("poll_fleet", t)
	return view
end

---------------------------------------------------------------------------
-- Rev 6: after a replace. The engine's fleet scan reads ages for a slice of the fleet per pass, so the
-- replaced vehicles' Old / Worn rows would linger. When the game's Replace window closes (its onClose
-- runs after vehicle_react_util.HandleVehicleChanges has sent the replace commands on accept, and on
-- cancel; vehicle_store_window.tl:4654-4674, 4895-4930), the vehicles go to the engine as
-- "ProblemRadar.recheckVehicles" (radar.script.tl handleRecheck), and once more RESEND_S later in case
-- the replace had not applied yet. Meanwhile the radar window hides their rows that no longer hold
-- (hiddenFleetIds, read live) for HIDE_S. Wall-clock seconds (os.time): plain Lua, safe on any thread.

local EVENT_ID <const> = "ProblemRadar"
local EV_RECHECK <const> = "ProblemRadar.recheckVehicles"
local RESEND_S <const> = 3
local HIDE_S <const> = 30

-- vehicle -> os.time() its Replace window closed; and the batches still to be re-sent once.
local replacedAt : {integer : integer} = {}
local record Resend
	at : integer
	vehicles : {integer}
end
local resends : {Resend} = {}

local function sendRecheck(vehicles : {integer}) : boolean
	-- src: .cache/game/api/tealdef/api/cmd.d.tl:788 (makeScriptingSendEventCmd), as radar_hud.script.tl sendEvent
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", EVENT_ID, EV_RECHECK, { vehicles = vehicles }))
	return true
end

--- Replace window closed (GUI thread): recheck now, remember the vehicles for the resend and the filter.
local function onReplaceClosed(vehicles : {integer})
	local now = os.time()
	for __, v in ipairs(vehicles) do replacedAt[v] = now end
	resends[#resends + 1] = { at = now + RESEND_S, vehicles = vehicles }
	local ok, err = pcall(sendRecheck, vehicles)
	if not ok then log.warning("[ProblemRadar] fleet recheck not sent: " .. tostring(err)) end
end

function M.recheckTick()
	if #resends == 0 then return end
	local now = os.time()
	local due : {{integer}} = {}
	local keep : {Resend} = {}
	for __, r in ipairs(resends) do
		if now >= r.at then due[#due + 1] = r.vehicles else keep[#keep + 1] = r end
	end
	if #due == 0 then return end
	resends = keep
	-- onStepTimer runs on a worker thread: the command goes out on the main thread
	-- (react.d.tl:401 enqueueJoin; base use mission_framework_react.tl:954).
	react.enqueueJoin(function()
		for __, vehicles in ipairs(due) do
			local ok, err = pcall(sendRecheck, vehicles)
			if not ok then log.warning("[ProblemRadar] fleet recheck not sent: " .. tostring(err)) end
		end
	end, "ProblemRadarFleetRecheck")
end

--- What radar.script.tl handleRecheck reads, for the GUI's own early verdict.
local function recheckInfo(v : integer, now : integer) : ProblemRadarFleetRecheck
	if not api.engine.entityExists(v) then return { exists = false } end
	local info : ProblemRadarFleetRecheck = { exists = true }
	local names : {string : string} = {}
	local r = readVehicle(v, now, names)
	info.ageMs, info.lifespanMs, info.condition = r.ageMs, r.lifespanMs, r.condition
	return info
end

function M.hiddenFleetIds(wornClear : number) : {string : boolean}
	local hide : {string : boolean} = {}
	if next(replacedAt) == nil then return hide end
	local wall = os.time()
	local ok, err = pcall(function() : boolean
		local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
		local now = gt.gameTime
		for v, at in pairs(replacedAt) do
			if wall - at > HIDE_S then
				replacedAt[v] = nil
			else
				for __, id in ipairs(radar_checks.fleetCleared(v, recheckInfo(v, now), wornClear)) do hide[id] = true end
			end
		end
		return true
	end)
	if not ok then log.warning("[ProblemRadar] fleet recheck read failed: " .. tostring(err)) end
	return hide
end

---------------------------------------------------------------------------
-- Actions (GUI thread: button clicks).

local function existing(vehicles : {integer}) : {integer}
	local out : {integer} = {}
	for __, v in ipairs(vehicles or {}) do
		if api.engine.entityExists(v) then out[#out + 1] = v end
	end
	return out
end

--- The vehicle window's Replace button, for a list of vehicles (vehicle.tl:445-462: carrier + transport
--- modes from line_util, filter tags from vehicle_store_util, event "replaceVehicles", handled by
--- vehicle_store_window.tl:4895-4934, which opens the store in "Replace" mode). If the parameters can't
--- be built (mixed carriers: the helper returns carrier nil, line_util.tl:1629-1650), the game's
--- vehicle manager opens with the vehicles selected instead (vehiclecondition.script.tl:63).
local function replaceVehicles(vehicles : {integer})
	local t = perfStart()
	local list = existing(vehicles)
	if #list == 0 then
		perfStop("click_fleet_replace", t)
		return
	end
	local ok, err = pcall(function() : nil
		local tmc = line_util.getLineAndVehicleCompatibleTransportModesAndCarrier(list)
		if tmc == nil or tmc.carrier == nil then error("no common carrier") end
		local param : VehicleStoreWindow.VehicleStoreEventParam = {
			vehicleEntities = list,
			carrier = tmc.carrier,
			transportModes = tmc.transportModes,
			filterTags = vehicle_store_util.getVehicleFilterTags(list),
			onClose = function() onReplaceClosed(list) end,
		}
		react.fireEvent(nil, "replaceVehicles", param)
		return nil
	end)
	if not ok then
		log.warning("[ProblemRadar] replace window not available (" .. tostring(err) .. "); opening the vehicle manager")
		local p : ManagerWindow.ManagerWindowEventParam = { openWithVehicleEntities = list }
		react.fireEvent(nil, "openVehicleManager", p)
	end
	perfStop("click_fleet_replace", t)
end

--- "Show line": the game's line window (selectEntity, as radar_hud.script.tl focusRow).
local function showLine(line : integer)
	if line == nil or not api.engine.entityExists(line) then return end
	api.gui.fireReactEvent("selectEntity", { entity = line, stack = true })
end

---------------------------------------------------------------------------
-- Render (GUI thread).

local function text(str : string, class? : string, tip? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body", tooltip = tip, styleSheet = radar_inline.text(class) }, -- INLINE STYLES
		text = str,
	}
end

-- "radar-box": the .css.lua spacing rule ("R::ProblemRadarFleetContent !radar-box", innerSpacing) targets
-- only our own layouts (radar_hud.script.tl boxClass); no element name, so it covers the FlowLayout too.
local function hbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = class and (class .. ", radar-box") or "radar-box" },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local function vbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = class and (class .. ", radar-box") or "radar-box" },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

--- Native fleet window (2026-10-14): base "primary" (filled accent) / "secondary" (outlined) buttons
--- (gui/main/default.css.lua:77-107) with compact padding inline (radar_inline fleetButton / rowButton;
--- ui-guide "Controls" without its xx-small class rule). Body text, as the guide's buttons.
local function button(label : string, tip : string, onClick : function(), primary? : boolean, style? : StyleSheet) : TreeNodeId
	return builtin.Button{
		meta = { class = primary and "primary" or "secondary", tooltip = tip,
			styleSheet = style or radar_inline.fleetButton() }, -- INLINE STYLES
		content = text(label, "font-scale-body"),
		onClick = onClick,
	}
end

local function n(v : integer) : string
	return lang_util.formatInt(v or 0)
end

--- A 1 px line: a Component with an inline size and colour (base separators are Components too,
--- game_bar.tl:1023).
local function hline(style : StyleSheet) : TreeNodeId -- INLINE STYLES
	return builtin.Component{ meta = { class = "radar-fleet-line", styleSheet = style } }
end

--- Native card (radar_inline fleetCard / fleetTableCard: the base entity-window card nine-patch, as
--- Timetables frames its panels). A Component holding a builtin layout (never a recipe:
--- docs/findings/gui.md). `fill`: the card stretches to the row's height (base class "vertical-spacer",
--- gravity { 0, -1 }, default.css.lua:128) and a base vertical spacer after the content takes the spare
--- height (gui_react_util.makeVerticalSpacer, as the base loan cards, finances_loan_gui.tl:354), so both
--- top cards are as tall as the taller one with their content at the top. To verify in game.
local function card(children : {TreeNodeId}, style : StyleSheet, fill? : boolean) : TreeNodeId
	if fill then children[#children + 1] = builtin.Component{ meta = { class = "vertical-spacer" } } end
	return builtin.Component{
		meta = { class = "radar-fleet-card" .. (fill and ", vertical-spacer" or ""), styleSheet = style }, -- INLINE STYLES
		layout = vbox(children, "radar-fleet-card-box"),
	}
end

--- Section heading (brighter, a step larger) above a card.
local function heading(title : string, class? : string) : TreeNodeId
	return text(title, "font-scale-headline, " .. (class or "radar-fleet-head"))
end

--- One "label  value" line of a card: label column fixed width (wraps), values right-aligned in a
--- fixed column (textAlignment, as keybinding_hint.css.lua:262-268). The tooltip sits on the label
--- TextView (base pattern: manager_window.tl:3890-3898 makeTitleText).
local function stat(label : string, value : string, valueClass? : string, tip? : string, big? : boolean) : TreeNodeId
	local font = big and "font-scale-headline" or "font-scale-body"
	local labelClass = font .. ", radar-col130" .. (big and ", radar-fleet-sum" or "")
	return hbox({
		builtin.TextView{
			meta = { class = labelClass, tooltip = tip, styleSheet = radar_inline.text(labelClass) }, -- INLINE STYLES
			text = label,
		},
		text(value, font .. ", radar-fleet-value" .. (valueClass ~= nil and (", " .. valueClass) or "")),
	}, "radar-fleet-stat")
end

local function money(v : integer) : string
	if v == nil then return "–" end
	return api.util.formatMoney(v)
end

--- Green above zero, red below, default text at zero (radar_inline; the base !positive class is
--- the blue "jordyBlue", default_colors.gres.lua:58, which reads like a link).
local function moneyClass(v : integer) : string
	if v == nil or v == 0 then return nil end
	return v > 0 and "radar-money-pos" or "radar-money-neg"
end

--- Warning colour (the radar's tier 2) for counts above zero.
local function warnIf(on : boolean) : string
	return on and "radar-tier-2" or nil
end

local function years(y : integer) : string
	return lang_util.format(_("{n} y"), { n = tostring(y or 0) })
end

-- Upgrade button tooltips (the former hint line under the buttons, wrapped per CLAUDE.md "Tooltips").
local TIP_THIS_KEY <const> = "Opens the game's Replace Vehicles window for this vehicle.\nThere you choose the new vehicle and confirm the price." -- i18n: keys
local TIP_MANY_KEY <const> = "Opens the game's Replace Vehicles window for these vehicles.\nThere you choose the new vehicle and confirm the price." -- i18n: keys
local TIP_GROUP_KEY <const> = "Opens the game's Replace Vehicles window for these vehicles.\nThere you choose the new vehicle and confirm the price.\nTrains of different compositions are upgraded\none model group at a time." -- i18n: keys

local record Tips
	this : string
	many : string
	group : string
end

local function lineCard(view : ProblemRadarFleetView) : TreeNodeId
	local c : {TreeNodeId} = {}
	c[#c + 1] = stat(_("Vehicles"), n(view.count))
	c[#c + 1] = stat(_("Past lifespan"), n(view.old), warnIf(view.old > 0))
	c[#c + 1] = stat(_("Worn"), n(view.worn), warnIf(view.worn > 0))
	c[#c + 1] = stat(_("Capacity"), n(view.capacity))
	local usage = view.usagePct ~= nil and api.util.toStringPercent(view.usagePct / 100) or "–"
	c[#c + 1] = stat(_("Utilization"), lang_util.format(_("{used} of {capacity} on board now ({usage})"),
		{ used = n(view.used), capacity = n(view.capacity), usage = usage }))
	-- The base progress bar (builtin.d.tl:1012-1020; game_bar.tl:450-456 with-border + label), in a row of
	-- its own: the base ProgressBar rule's gravity { -1, -1 } would otherwise grow it into the card's
	-- spare height (card fill); in a horizontal row it only fills the row's own height.
	c[#c + 1] = hbox({ builtin.ProgressBar{
		meta = { class = "radar-fleet-usage, with-border, font-scale-annotation", styleSheet = radar_inline.fleetUsage() }, -- INLINE STYLES
		value = math.max(0, math.min(1, (view.usagePct or 0) / 100)),
		label = usage,
		applyGradient = false,
	} })
	c[#c + 1] = stat(_("Frequency"), view.intervalS > 0 and api.util.formatMinutesSeconds(view.intervalS) or "–", nil,
		_("Time interval between the vehicles."))
	c[#c + 1] = stat(_("Transported"), lang_util.format(_("{n} per year"), { n = n(view.transported) }))
	local age = "–"
	if view.avgYears ~= nil then
		age = view.avgLifeYears ~= nil
			and lang_util.format(_("{age} y · lifespan {life} y"), { age = tostring(view.avgYears), life = tostring(view.avgLifeYears) })
			or years(view.avgYears)
	end
	c[#c + 1] = stat(_("Average age"), age, warnIf(view.avgPastLife == true))
	return card(c, radar_inline.fleetCard(), true)
end

local function moneyCard(view : ProblemRadarFleetView) : TreeNodeId
	local c : {TreeNodeId} = {}
	c[#c + 1] = stat(_("Income"), money(view.income), moneyClass(view.income))
	c[#c + 1] = stat(_("Running Costs"), money(view.running), moneyClass(view.running))
	c[#c + 1] = stat(_("Maintenance"), money(view.maintenance), moneyClass(view.maintenance))
	-- The sum line: a line above, a larger font.
	c[#c + 1] = hline(radar_inline.fleetSumLine())
	c[#c + 1] = stat(_("Balance"), money(view.balance), moneyClass(view.balance), nil, true)
	return card(c, radar_inline.fleetCard(), true)
end

--- One model group. Its per-row Upgrade buttons only when the line has more than one group (with one,
--- "Upgrade whole fleet" / "Upgrade old vehicles" below the table do the same). The vehicle's own group
--- (was a "›" marker column) shows its name in the accent colour with a tooltip, also only then.
local function groupRow(g : ProblemRadarFleetGroup, i : integer, tips : Tips, several : boolean) : TreeNodeId
	local vehicles, oldVehicles = g.vehicles, g.oldVehicles
	local age = g.lifeYears > 0
		and lang_util.format(_("{age} of {life} y"), { age = tostring(g.oldestYears), life = tostring(g.lifeYears) })
		or years(g.oldestYears)
	local target = several and g.hasTarget
	local cells : {TreeNodeId} = {
		text(g.name, "font-scale-body, radar-fleet-model" .. (target and ", radar-fleet-target" or ""),
			target and _("The vehicle you opened this window for has this model.") or nil),
		text(n(g.count), "font-scale-body, radar-fleet-num"),
		text(age, "font-scale-body, radar-fleet-age" .. (g.old > 0 and ", radar-tier-2" or "")),
		text(n(g.old), "font-scale-body, radar-fleet-past" .. (g.old > 0 and ", radar-tier-2" or "")),
	}
	if several then
		local buttons : {TreeNodeId} = {
			button(lang_util.format(_("Upgrade {n}…"), { n = n(g.count) }), tips.group, function() replaceVehicles(vehicles) end,
				false, radar_inline.rowButton()),
		}
		if g.offerOld then
			buttons[#buttons + 1] = button(lang_util.format(_("Upgrade old ({n})…"), { n = n(g.old) }), tips.group,
				function() replaceVehicles(oldVehicles) end, false, radar_inline.rowButton())
		end
		cells[#cells + 1] = vbox(buttons, "radar-fleet-row-buttons")
	end
	-- Alternating row backgrounds (radar_inline fleetRow: the Timetables zebra on odd rows).
	return builtin.Component{
		meta = { class = "radar-fleet-row, " .. (i % 2 == 1 and "radar-fleet-row-odd" or "radar-fleet-row-even"), localKey = g.key,
			styleSheet = radar_inline.fleetRow(i % 2 == 1) }, -- INLINE STYLES
		layout = hbox(cells),
	}
end

-- More model groups than this scroll (in a fixed-height area); fewer size the window to them.
local MAX_UNSCROLLED_GROUPS <const> = 6

--- The model table in a card: one-line short headers, their full meaning in the tooltips.
local function groupList(view : ProblemRadarFleetView, tips : Tips) : {TreeNodeId}
	local several = #view.groups > 1
	local rows : {TreeNodeId} = {}
	for i, g in ipairs(view.groups) do rows[i] = groupRow(g, i, tips, several) end
	local c : {TreeNodeId} = {}
	c[#c + 1] = builtin.Component{
		meta = { class = "radar-fleet-table-head", styleSheet = radar_inline.fleetHeadRow() }, -- INLINE STYLES
		layout = hbox({
			text(_("Model"), "font-scale-annotation, radar-fleet-model, radar-dim",
				_("The vehicle model. Trains show their composition.")),
			text(_("Count"), "font-scale-annotation, radar-fleet-num, radar-dim", _("Vehicles of this model on the line.")),
			text(_("Oldest"), "font-scale-annotation, radar-fleet-age, radar-dim",
				_("Age of the oldest vehicle of this model\nand the model's lifespan, in years.")),
			text(_("Past lifespan"), "font-scale-annotation, radar-fleet-past, radar-dim",
				_("Vehicles of this model older than their lifespan.")),
		}),
	}
	c[#c + 1] = hline(radar_inline.fleetDimLine()) -- INLINE STYLES
	if #rows <= MAX_UNSCROLLED_GROUPS then
		c[#c + 1] = vbox(rows, "radar-fleet-rows")
	else
		-- ScrollArea content must be a Component (memory: scrollarea-content-component;
		-- base: entity_window/entity_window_util.tl:715-721).
		c[#c + 1] = builtin.ScrollArea{
			meta = { class = "radar-fleet-groups", styleSheet = radar_inline.fleetGroups() }, -- INLINE STYLES
			horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
			verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
			content = builtin.Component{ layout = vbox(rows, "radar-fleet-rows") },
		}
	end
	return { heading(_("Fleet by model")), card(c, radar_inline.fleetTableCard()) }
end

--- One action row. "primary" (the base filled accent button) goes to the most relevant fleet-wide
--- action: the old vehicles when there are some of one model, else the whole fleet, else this vehicle.
--- The others are "secondary" (outlined); "Show line" comes last. The former hint under the buttons
--- is in their tooltips.
local function actions(view : ProblemRadarFleetView, tips : Tips) : {TreeNodeId}
	local vehicle, line = view.vehicle, view.line
	local oldVehicles, fleetVehicles = view.oldVehicles, view.fleetVehicles
	local primary = oldVehicles ~= nil and "old" or fleetVehicles ~= nil and "fleet" or "this"
	local buttons : {TreeNodeId} = {}
	if oldVehicles ~= nil then
		buttons[#buttons + 1] = button(lang_util.format(_("Upgrade old vehicles ({n})…"), { n = n(#oldVehicles) }), tips.many,
			function() replaceVehicles(oldVehicles) end, primary == "old")
	end
	if fleetVehicles ~= nil then
		buttons[#buttons + 1] = button(lang_util.format(_("Upgrade whole fleet ({n})…"), { n = n(#fleetVehicles) }), tips.many,
			function() replaceVehicles(fleetVehicles) end, primary == "fleet")
	end
	buttons[#buttons + 1] = button(_("Upgrade this vehicle…"), tips.this, function() replaceVehicles({ vehicle }) end,
		primary == "this")
	if line ~= nil then
		buttons[#buttons + 1] = button(_("Show line"), _("Open the line's window"), function() showLine(line) end)
	end
	-- FlowLayout: the buttons wrap to the window width (docs/findings.md "Wrapping rows"); its gaps come
	-- from the "!radar-box" innerSpacing rule.
	return {
		builtin.Component{ meta = { styleSheet = radar_inline.fleetGap() } }, -- INLINE STYLES
		builtin.FlowLayout{ meta = { class = "radar-box" }, children = buttons },
	}
end

local record FleetContentParam is IRecipeParamWithMeta -- INLINE STYLES: meta (radar_inline.fleetContent)
	vehicle : integer
	wornAt : number
end

-- The open window's state (set on every render; expired once the window is gone) and its vehicle.
local fleetState : ReactStateT<ProblemRadarFleetView> = nil
local openVehicle : integer = nil

local ProblemRadarFleetContent = react.RegisterRecipe("ProblemRadarFleetContent", function(params : FleetContentParam) : TreeNodeId
	local t = perfStart()
	local vehicle, wornAt = params.vehicle, params.wornAt
	local state = engine_react_util.useStepStateTimer(function() : ProblemRadarFleetView
		return pollView(vehicle, wornAt)
	end, POLL_SECONDS)
	fleetState = state
	local view = state:old() or fleet_model.build(nil)
	local children : {TreeNodeId}
	if view.gone then
		children = { text(_("This vehicle no longer exists."), "font-scale-body, radar-empty, radar-dim") }
	else
		local tips : Tips = {
			this = _(TIP_THIS_KEY), -- i18n: ignore (TIP_THIS_KEY)
			many = _(TIP_MANY_KEY), -- i18n: ignore (TIP_MANY_KEY)
			group = _(TIP_GROUP_KEY), -- i18n: ignore (TIP_GROUP_KEY)
		}
		-- Top: two cards side by side (line stats | 12-month money), their headings above them; then the
		-- model table's card, then one action row. The window sizes to this content.
		if view.line ~= nil then
			children = {
				hbox({ heading(_("Line"), "radar-fleet-head-col"), heading(_("Last 12 months")) }, "radar-fleet-heads"),
				hbox({ lineCard(view), moneyCard(view) }, "radar-fleet-cards"),
			}
		else
			children = { text(_("This vehicle is not on a line."), "font-scale-body, radar-dim") }
		end
		for __, c in ipairs(groupList(view, tips)) do children[#children + 1] = c end
		for __, c in ipairs(actions(view, tips)) do children[#children + 1] = c end
	end
	-- A recipe returns a layout (memory: react-recipe-must-return-layout).
	local root = vbox(children, "radar-fleet")
	perfStop("fleet_render", t)
	return root
end)

local record FleetWindowParam
	title : string
	vehicle : integer
	wornAt : number
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
					log.warning("[ProblemRadar] this platform's Window rejects '" .. key .. "'; left out")
				end
			end
			if not windowFieldOk[key] then t[k] = nil end
		end
	end
	return p
end

local ProblemRadarFleetWindow = react.RegisterWrapperRecipe("ProblemRadarFleetWindow", builtin.Window, function(params : FleetWindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210
	return builtin.Window(platformWindow{
		id = WINDOW_ID,
		title = params.title,
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = ProblemRadarFleetContent{ vehicle = params.vehicle, wornAt = params.wornAt,
			meta = { styleSheet = radar_inline.fleetContent() } }, -- INLINE STYLES
	})
end)

function M.close()
	fleetState, openVehicle = nil, nil
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then wa.removeAllWindows(ProblemRadarFleetWindow) end
end

--- Title: "Fleet: <line>", or the vehicle's name when it has no line.
local function titleFor(vehicle : integer) : string
	local ok, name = pcall(function() : string
		local tv = getTv(vehicle)
		local line = tv ~= nil and tv.line or nil
		if line ~= nil and line > 0 and api.engine.entityExists(line) then return api.engine.util.getEntityName(line) end
		return api.engine.util.getEntityName(vehicle)
	end)
	return lang_util.format(_("Fleet: {name}"), { name = ok and name or "" })
end

function M.open(vehicle : integer, wornAt : number)
	local t = perfStart()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning("[ProblemRadar] no window container; cannot open the fleet window")
		return
	end
	local isOpen = fleetState ~= nil and not fleetState:hasExpired()
	if isOpen and openVehicle == vehicle then
		wa.moveSingletonWindowToFront(ProblemRadarFleetWindow)
		perfStop("click_fleet_open", t)
		return
	end
	-- Another vehicle: a fresh window (its poll and title belong to the vehicle it was opened for).
	if isOpen then wa.removeAllWindows(ProblemRadarFleetWindow) end
	openVehicle = vehicle
	wa.addSingletonWindow(ProblemRadarFleetWindow, {
		title = titleFor(vehicle),
		vehicle = vehicle,
		wornAt = wornAt,
		onClose = M.close,
	})
	wa.moveSingletonWindowToFront(ProblemRadarFleetWindow)
	perfStop("click_fleet_open", t)
end

function M.setPerf(p : any)
	perf = p as SquareProblemRadarSqPerfInst
end

return M
