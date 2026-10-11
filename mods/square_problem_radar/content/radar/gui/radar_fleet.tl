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

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body", styleSheet = radar_inline.text(class) }, -- INLINE STYLES
		text = str,
	}
end

-- "radar-box": the .css.lua spacing rule targets only our own BoxLayouts (radar_hud.script.tl boxClass).
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

local function button(label : string, tip : string, onClick : function(), primary? : boolean) : TreeNodeId
	return builtin.Button{
		-- "secondary": the base outlined button (gui/main/default.css.lua:104-107); a plain Button has an
		-- invisible surface and reads as text. "primary": the base filled accent button (:77-79).
		meta = { class = "radar-fleet-button, " .. (primary and "primary" or "secondary"), tooltip = tip },
		content = text(label, "font-scale-annotation"),
		onClick = onClick,
	}
end

local function n(v : integer) : string
	return lang_util.formatInt(v or 0)
end

--- A 1 px line across its parent (radar_hud.css.lua !radar-fleet-divider): a styled Component, the base
--- way to draw separators (game_bar.tl:1023 builtin.Component{ meta = { class = "separator" } }).
local function divider(class? : string, style? : StyleSheet) : TreeNodeId -- INLINE STYLES: style
	return builtin.Component{ meta = { class = "radar-fleet-divider" .. (class ~= nil and (", " .. class) or ""), styleSheet = style } }
end

--- Section title (brighter, a step larger) with a divider under it.
local function header(title : string) : {TreeNodeId}
	return { text(title, "font-scale-headline, radar-fleet-head"), divider() }
end

--- A panel with a subtle background (radar_hud.css.lua !radar-fleet-card). A Component holding a
--- builtin layout (never a recipe: memory recipe-not-component-layout).
local function card(children : {TreeNodeId}) : TreeNodeId
	return builtin.Component{
		meta = { class = "radar-fleet-card" },
		layout = vbox(children, "radar-fleet-card-box"),
	}
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

--- Green above zero, red below, default text at zero (radar_hud.css.lua; the base !positive class is
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

local REPLACE_TIP_KEY <const> = "Opens the game's Replace Vehicles window for these vehicles" -- i18n: keys

local function lineCard(view : ProblemRadarFleetView) : TreeNodeId
	local c : {TreeNodeId} = header(_("Line"))
	c[#c + 1] = stat(_("Vehicles"), n(view.count))
	c[#c + 1] = stat(_("Past lifespan"), n(view.old), warnIf(view.old > 0))
	c[#c + 1] = stat(_("Worn"), n(view.worn), warnIf(view.worn > 0))
	c[#c + 1] = stat(_("Capacity"), n(view.capacity))
	local usage = view.usagePct ~= nil and api.util.toStringPercent(view.usagePct / 100) or "–"
	c[#c + 1] = stat(_("Utilization"), lang_util.format(_("{used} of {capacity} on board now ({usage})"),
		{ used = n(view.used), capacity = n(view.capacity), usage = usage }))
	-- The base progress bar (builtin.d.tl:1012-1020; game_bar.tl:450-456 with-border + label).
	c[#c + 1] = builtin.ProgressBar{
		meta = { class = "radar-fleet-usage, with-border, font-scale-annotation" },
		value = math.max(0, math.min(1, (view.usagePct or 0) / 100)),
		label = usage,
		applyGradient = false,
	}
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
	return card(c)
end

local function moneyCard(view : ProblemRadarFleetView) : TreeNodeId
	local c : {TreeNodeId} = header(_("Last 12 months"))
	c[#c + 1] = stat(_("Income"), money(view.income), moneyClass(view.income))
	c[#c + 1] = stat(_("Running Costs"), money(view.running), moneyClass(view.running))
	c[#c + 1] = stat(_("Maintenance"), money(view.maintenance), moneyClass(view.maintenance))
	-- The sum line: a divider above, a larger font.
	c[#c + 1] = divider("radar-fleet-sum-line")
	c[#c + 1] = stat(_("Balance"), money(view.balance), moneyClass(view.balance), nil, true)
	return card(c)
end

local function groupRow(g : ProblemRadarFleetGroup, i : integer, replaceTip : string) : TreeNodeId
	local vehicles, oldVehicles = g.vehicles, g.oldVehicles
	local age = g.lifeYears > 0
		and lang_util.format(_("{age} of {life} y"), { age = tostring(g.oldestYears), life = tostring(g.lifeYears) })
		or years(g.oldestYears)
	local buttons : {TreeNodeId} = {
		button(lang_util.format(_("Upgrade {n}…"), { n = n(g.count) }), replaceTip, function() replaceVehicles(vehicles) end),
	}
	if g.offerOld then
		buttons[#buttons + 1] = button(lang_util.format(_("Upgrade old ({n})…"), { n = n(g.old) }), replaceTip,
			function() replaceVehicles(oldVehicles) end)
	end
	-- Alternating row backgrounds (radar-fleet-row-odd); the vehicle's own group gets a "›" marker in the
	-- accent colour instead of a coloured name.
	return builtin.Component{
		meta = { class = "radar-fleet-row, " .. (i % 2 == 1 and "radar-fleet-row-odd" or "radar-fleet-row-even"), localKey = g.key,
			styleSheet = i % 2 == 1 and radar_inline.fleetRowOdd() or nil }, -- INLINE STYLES
		layout = hbox({
			text(g.hasTarget and "›" or "", "font-scale-body, radar-fleet-mark"),
			text(g.name, "font-scale-body, radar-fleet-model"),
			text(n(g.count), "font-scale-body, radar-fleet-num"),
			text(age, "font-scale-body, radar-fleet-age" .. (g.old > 0 and ", radar-tier-2" or "")),
			text(n(g.old), "font-scale-body, radar-fleet-num" .. (g.old > 0 and ", radar-tier-2" or "")),
			vbox(buttons, "radar-fleet-row-buttons"),
		}),
	}
end

-- More model groups than this scroll (in a fixed-height area); fewer size the window to them.
local MAX_UNSCROLLED_GROUPS <const> = 6

local function groupList(view : ProblemRadarFleetView, replaceTip : string) : {TreeNodeId}
	local rows : {TreeNodeId} = {}
	for i, g in ipairs(view.groups) do rows[i] = groupRow(g, i, replaceTip) end
	local out : {TreeNodeId} = header(_("Fleet by model"))
	out[#out + 1] = hbox({
		text("", "font-scale-annotation, radar-fleet-mark"),
		text(_("Model"), "font-scale-annotation, radar-fleet-model, radar-dim"),
		text(_("Count"), "font-scale-annotation, radar-fleet-num, radar-dim"),
		text(_("Oldest: age / lifespan"), "font-scale-annotation, radar-fleet-age, radar-dim"),
		text(_("Past lifespan"), "font-scale-annotation, radar-fleet-num, radar-dim"),
	}, "radar-fleet-table-head")
	out[#out + 1] = divider("radar-fleet-dim-line", radar_inline.fleetDimLine()) -- INLINE STYLES
	if #rows <= MAX_UNSCROLLED_GROUPS then
		out[#out + 1] = vbox(rows, "radar-fleet-rows")
	else
		-- ScrollArea content must be a Component (memory: scrollarea-content-component;
		-- base: entity_window/entity_window_util.tl:715-721).
		out[#out + 1] = builtin.ScrollArea{
			meta = { class = "radar-fleet-groups" },
			horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
			verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
			content = builtin.Component{ layout = vbox(rows, "radar-fleet-rows") },
		}
	end
	return out
end

--- The most relevant action is "primary" (the base filled accent button, gui/main/default.css.lua:77-79):
--- the old vehicles when there are some of one model, else this vehicle. "Show line" comes last.
local function actions(view : ProblemRadarFleetView, replaceTip : string) : {TreeNodeId}
	local vehicle, line = view.vehicle, view.line
	local oldVehicles, fleetVehicles = view.oldVehicles, view.fleetVehicles
	local buttons : {TreeNodeId} = {}
	if oldVehicles ~= nil then
		buttons[#buttons + 1] = button(lang_util.format(_("Upgrade old vehicles ({n})…"), { n = n(#oldVehicles) }), replaceTip,
			function() replaceVehicles(oldVehicles) end, true)
	end
	buttons[#buttons + 1] = button(_("Upgrade this vehicle…"), replaceTip, function() replaceVehicles({ vehicle }) end,
		oldVehicles == nil)
	if fleetVehicles ~= nil then
		buttons[#buttons + 1] = button(lang_util.format(_("Upgrade whole fleet ({n})…"), { n = n(#fleetVehicles) }), replaceTip,
			function() replaceVehicles(fleetVehicles) end)
	end
	if line ~= nil then
		buttons[#buttons + 1] = button(_("Show line"), _("Open the line's window"), function() showLine(line) end)
	end
	local out : {TreeNodeId} = header(_("Upgrade"))
	-- FlowLayout: the buttons wrap to the window width (docs/findings.md "Wrapping rows").
	out[#out + 1] = builtin.FlowLayout{ children = buttons }
	out[#out + 1] = text(_("The Upgrade buttons open the game's Replace Vehicles window, where you choose the new vehicle and confirm the price. Trains of different compositions are upgraded one model group at a time."),
		"font-scale-annotation, radar-hint")
	return out
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
		local replaceTip = _(REPLACE_TIP_KEY) -- i18n: ignore (REPLACE_TIP_KEY)
		-- Top: two cards side by side (line stats | 12-month money); then the model table, then the
		-- actions under their own divider. The window sizes to this content (radar_hud.css.lua).
		children = view.line ~= nil and { hbox({ lineCard(view), moneyCard(view) }, "radar-fleet-cards") }
			or { text(_("This vehicle is not on a line."), "font-scale-annotation, radar-hint") }
		for __, c in ipairs(groupList(view, replaceTip)) do children[#children + 1] = c end
		for __, c in ipairs(actions(view, replaceTip)) do children[#children + 1] = c end
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

local ProblemRadarFleetWindow = react.RegisterWrapperRecipe("ProblemRadarFleetWindow", builtin.Window, function(params : FleetWindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210
	return builtin.Window{
		id = WINDOW_ID,
		title = params.title,
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = ProblemRadarFleetContent{ vehicle = params.vehicle, wornAt = params.wornAt,
			meta = { styleSheet = radar_inline.fleetContent() } }, -- INLINE STYLES
	}
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
