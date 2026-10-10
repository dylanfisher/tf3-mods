-- Passenger Destinations: two entity-window plugins that draw the base game's 3D cargo-flow arrows to
-- where passengers are going. Default: the FINAL destination (the home / shop / work building,
-- SIM_PERSON.targetOrAtEntity). A "Next stop instead of final destination" switch keeps the old mode
-- (the stop where they leave the current line, SIM_ENTITY_AT_*.lineStop1).
--   * Station window (StationGroupEowExtensionPoint): per-terminal toggles (+ "All terminals"). Final:
--     the waiting passengers' target buildings, clustered on a CLUSTER_M grid, one arrow per cluster
--     (biggest first, at most MAX_ARROWS); the card counts them per town plus Home/Shop/Work. Next stop:
--     one arrow per destination station group, counted per stop.
--   * Person window (SimPersonEowExtensionPoint, order 41 = right under "Current Route", base
--     sim_person_eow_route.res.lua order 40): "Show destination" toggle. Arrow from the person (or their
--     stop / vehicle) to the target building (or the next stop in next-stop mode).
-- GUI only, read-only: no game script, no commands, nothing saved. Plan: plans/square_passenger_destinations/PLAN.md
--
-- HOW THE ARROWS GET DRAWN (same mechanism as square_industry_flows, flows_window.script.tl header):
-- a builtin.LayerConfig only takes effect inside the ActionDescriptor of the TOP tool of the tool stack
-- (.cache/game/base/content/gui/main/builtin.lua:1162-1194 ToolStackEntryWrap). The plugins get the
-- window's gameCtx.toolStack, so turning a toggle on pushes our own window-less tool with
-- allowStacking = true (builtin.lua:1381-1390); the tool's push handler hands the ToolStack our action
-- (ctx.setActionFn), which is the base default selector action with our LayerConfig
-- (selector_react_util.tl:324-372 makeDefaultSelectorAction).
--
-- KNOWN SIDE EFFECT, handled here: pushing a tool shelves every tool below it (builtin.lua shelveNonTop),
-- and the entity window's tool hides its window when shelved unless it is pinned
-- (entity_window/view_manager.tl:404-415, setVisible(windowId, false)). Our push handler runs after that
-- (builtin.lua push: shelveNonTop, then pushHandler) and makes the window visible again
-- (window id "temp.view.entity_<keyEntity>", view_manager.tl:62-64). Popping our tool un-shelves the
-- window tool, which shows it and restores its own action (view_manager.tl:412-415).
--
-- Never an orphaned tool: popped on untoggle, on plugin unmount (window closed), when the window's entity
-- changes, and the plugin notices when something else popped or replaced it (module `active`).
-- Tool stack calls from unmount / timers go through react.enqueueJoin (main thread; memory
-- "onStep runs on worker threads"). Engine reads in timers are fine (base useStepStateTimer does them).
--
-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, slow calls (> 16 ms, at most one
-- line per section per minute) and, with the "Debug: performance log" mod setting, a 30 s summary.
-- Sections: the two plugin renders and the arrow LayerConfig (GUI thread), the passenger scans
-- compute_station / compute_person and read_terminals (useStepStateTimer polls, i.e. onStepTimer
-- callbacks on worker threads "Main Pool N", and the click handlers). api.type.Clock is safe on those
-- threads (docs/findings.md "Timers and threads in GUI contexts"). The per-refresh "[PaxDest] refresh"
-- line is only written with that setting On. Local counters only; nothing is saved.
local sqperf = ug_require "square_passenger_destinations::/sqperf/square_passenger_destinations.lua" as SquarePassengerDestinationsSqPerf
local perf = sqperf.new({ mod = "square_passenger_destinations", ctx = "gui", paramKey = "sqperf_log" })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local selector_react_util = ug_require "::/gui/main/selector_react_util.tl" as SelectorReactUtil
local station_group_eow = ug_require "::/gui/entity_window/station_group/station_group_eow.script.tl" as StationGroupEow
local sim_person_eow = ug_require "::/gui/entity_window/sim_person/sim_person_eow.script.tl" as SimPersonEow

local LOG <const> = "[PaxDest] "
local REFRESH_S <const> = 1.0           -- arrows and counts refresh while on
local ACTION_POLL_S <const> = 0.25      -- the tool action picks up the card's latest snapshot (no engine reads)
local TERMINALS_S <const> = 2.0         -- terminal list of the station card
local MAX_ARROWS <const> = 30           -- most-used destinations drawn; the rest only counted
local MAX_ROWS <const> = 12             -- destination rows listed in the card
local FIRST_ROW_TERMINALS <const> = 6   -- terminal boxes on the station card's first row; more wrap
local WRAP_ROW_TERMINALS <const> = 10   -- terminal boxes per wrapped row
local TOOL_NAME <const> = "SquarePassengerDestinations"   -- react.RegisterTool names are global
local TOOL_KEY <const> = "square_passenger_destinations"
local ACTION_KEY <const> = "square_passenger_destinations"
local HEARTBEAT_S <const> = 10.0        -- an unchanged refresh is logged at most this often
local CLUSTER_M <const> = 150.0         -- final-destination grid cell (m): one arrow per occupied cell
local BUILDING_CACHE_MAX <const> = 20000  -- building info cache is dropped when it grows past this

---------------------------------------------------------------------------
-- Plain data (numbers/strings/tables only, so useStepStateTimer's deepEquals can compare polls).

local record Arrow
	from : {number}       -- {x, y, z}
	to : {number}
	count : integer
end

local record Row
	name : string
	count : integer
end

local record Snapshot
	arrows : {Arrow}      -- drawn, most passengers first, at most MAX_ARROWS
	rows : {Row}          -- listed, at most MAX_ROWS
	destinations : integer
	passengers : integer
	note : string         -- one line under the rows, may be nil
	kinds : string        -- "Home N · Shop N · Work N" (final mode, station window), may be nil
	catchment : integer   -- station group whose catchment area is drawn too (station window), may be nil
end

--- "final": the building the passenger travels to (SIM_PERSON.targetOrAtEntity), the default.
--- "next": the stop where they leave the current line (SIM_ENTITY_AT_*.lineStop1).
local enum Mode
	"final"
	"next"
end

local record PaxTerminal
	key : string          -- "<station>:<terminalIndex0>"
	station : integer
	terminal : integer    -- zero-based, as getLineStopsForTerminal takes it
	display : integer     -- 1-based flat number as the base window shows it (station_group.tl:772-806)
end

---------------------------------------------------------------------------
-- Engine reads

local paxCargo : integer = nil
local function passengerCargo() : integer
	if paxCargo == nil then
		-- base: cargo_util.getPassengerCargoTypeId (gui/main/cargo_util.tl:24-26); SIM_PERSON.cargoType "always 0"
		local ok, id = pcall(api.res.cargoTypeRep.getPassengerCargoTypeId)
		paxCargo = ok and id as integer or 0
		log.message(LOG .. "passenger cargo type id = " .. tostring(paxCargo))
	end
	return paxCargo
end

local function comp(entity : integer, ct : Engine.ComponentType) : any
	if entity == nil or entity < 0 then return nil end
	local ok, c : boolean, any = pcall(api.engine.getComponent, entity, ct)  -- no closure per call: runs per passenger
	if ok then return c end
	return nil
end

--- Top centre of the BOUNDING_VOLUME box (base industry.tl:195-202), nil without one.
local function bboxTop(entity : integer) : {number}
	local bv = comp(entity, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil or bv.bbox == nil then return nil end
	local mn : Vec3f = bv.bbox.min
	local mx : Vec3f = bv.bbox.max
	return { (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mx.z }
end

local function vec3ToList(v : Vec3f, lift : number) : {number}
	if v == nil then return nil end
	return { v.x, v.y, v.z + lift }
end

--- Middle of the first waiting-area (person) edge of a station: street stops have no construction.
local function stationEdgePos(station : integer) : {number}
	local st = comp(station, api.type.ComponentType.STATION) as Engine.Component.Station
	if st == nil then return nil end
	for __, t in ipairs(st.terminals) do
		for __, edgeId in ipairs(t.personEdges) do
			local tn = comp(edgeId.entity, api.type.ComponentType.TRANSPORT_NETWORK) as Engine.Component.TransportNetwork
			local edge = tn and tn.edges[edgeId.index + 1]
			if edge then
				local ok, p = pcall(api.engine.util.transport.calcPosition, edge.geometry, 0.5)
				if ok and p then return vec3ToList(p as Vec3f, 5.0) end
			end
		end
	end
	return nil
end

local loggedPosSource : {integer : boolean} = {}

--- Position of one station: its construction's box, its own box, or a waiting-area edge.
local function stationPos(station : integer) : {number}, string
	local ok, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, station)
	if ok and con and (con as integer) >= 0 then
		local p = bboxTop(con as integer)
		if p then return p, "construction" end
	end
	local p = bboxTop(station)
	if p then return p, "station" end
	return stationEdgePos(station), "edge"
end

--- Position of a station group: its own box if it has one, else the mean of its stations.
local function groupPos(group : integer, cache : {integer : {number}}) : {number}
	if cache[group] ~= nil then return cache[group] end
	local p = bboxTop(group)
	local source = "group"
	if p == nil then
		local sg = comp(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
		local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
		for __, station in ipairs(sg and sg.stations or {}) do
			local q, src = stationPos(station)
			if q then
				sx, sy, sz, n = sx + q[1], sy + q[2], sz + q[3], n + 1
				source = src
			end
		end
		if n > 0 then p = { sx / n, sy / n, sz / n } end
	end
	if not loggedPosSource[group] then
		loggedPosSource[group] = true
		log.message(LOG .. "position of group " .. tostring(group) .. " from " .. (p and source or "NOTHING"))
	end
	cache[group] = p
	return p
end

local function entityName(entity : integer) : string
	local ok, name = pcall(api.engine.util.getEntityName, entity)
	if ok and name ~= nil and name ~= "" then return name as string end
	return nil
end

local function lineOf(line : integer, cache : {integer : Engine.Component.Line}) : Engine.Component.Line
	local l = cache[line]
	if l == nil then
		l = comp(line, api.type.ComponentType.LINE) as Engine.Component.Line
		cache[line] = l
	end
	return l
end

--- Station group of a line's stop (stopIndex zero-based, as in SIM_ENTITY_AT_* lineStop0/1).
local function stopGroup(line : Engine.Component.Line, stopIndex : integer) : integer
	if line == nil or stopIndex == nil or stopIndex < 0 then return nil end
	local stop = line.stops[stopIndex + 1]
	return stop and stop.stationGroup as integer or nil
end

local function vehiclePos(vehicle : integer) : {number}
	if vehicle == nil or vehicle < 0 then return nil end
	local ok, p = pcall(api.engine.util.vehicle.getPosition, vehicle)
	if ok and p then return vec3ToList(p as Vec3f, 3.0) end
	return nil
end

---------------------------------------------------------------------------
-- Station data

--- Passenger terminals of a station group that have at least one line stop. SQPERF section "read_terminals".
local readTerminals = perf:wrap("read_terminals", function(group : integer) : {PaxTerminal}
	local out : {PaxTerminal} = {}
	local sg = comp(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
	if sg == nil then return out end
	local display = 1
	for __, station in ipairs(sg.stations) do
		local st = comp(station, api.type.ComponentType.STATION) as Engine.Component.Station
		for i, t in ipairs(st and st.terminals or {}) do
			if t.passengersLoad or t.passengersUnload then
				local ok, stops = pcall(api.engine.system.lineSystem.getLineStopsForTerminal, station, i - 1)
				if ok and stops and #(stops as {any}) > 0 then
					out[#out + 1] = { key = tostring(station) .. ":" .. tostring(i - 1), station = station, terminal = i - 1, display = display }
				end
			end
			display = display + 1
		end
	end
	return out
end)

local function sortedRows(counts : {integer : integer}, from : {number}, posCache : {integer : {number}}) : Snapshot
	local order : {integer} = {}
	local total = 0
	for dest, n in pairs(counts) do
		order[#order + 1] = dest
		total = total + n
	end
	table.sort(order, function(a : integer, b : integer) : boolean
		if counts[a] ~= counts[b] then return counts[a] > counts[b] end
		return a < b
	end)
	local snap : Snapshot = { arrows = {}, rows = {}, destinations = #order, passengers = total }
	for i, dest in ipairs(order) do
		if i <= MAX_ARROWS and from ~= nil then
			local to = groupPos(dest, posCache)
			if to ~= nil then
				snap.arrows[#snap.arrows + 1] = { from = from, to = to, count = counts[dest] }
			end
		end
		if i <= MAX_ROWS then
			snap.rows[#snap.rows + 1] = { name = entityName(dest) or ("#" .. tostring(dest)), count = counts[dest] }
		end
	end
	return snap
end

--- Calls visit(person, atTerminal) for every passenger waiting at the selected terminals of a group.
--- Mirrors base station_group.tl:647-664 (makeStopTooltip): getLineStopSimEntities per line stop of the
--- terminal (getLineStopsForTerminal), then the person's SIM_ENTITY_AT_TERMINAL. Without needAt that
--- read is skipped (one engine read less per passenger) and atTerminal is nil.
local function forEachWaiting(group : integer, selected : {string : boolean}, needAt : boolean, visit : function(integer, Engine.Component.SimEntityAtTerminal))
	local pax = passengerCargo()
	local sg = comp(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
	for __, station in ipairs(sg and sg.stations or {}) do
		local st = comp(station, api.type.ComponentType.STATION) as Engine.Component.Station
		for i, __ in ipairs(st and st.terminals or {}) do
			if selected[tostring(station) .. ":" .. tostring(i - 1)] then
				local ok, stops = pcall(api.engine.system.lineSystem.getLineStopsForTerminal, station, i - 1)
				for __, ls in ipairs(ok and stops as {{integer}} or {}) do
					local okP, people = pcall(api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntities, ls[1], ls[2], pax)
					for __, person in ipairs(okP and people as {integer} or {}) do
						if needAt then
							local at = comp(person, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL) as Engine.Component.SimEntityAtTerminal
							if at ~= nil then visit(person, at) end
						else
							visit(person, nil)
						end
					end
				end
			end
		end
	end
end

--- Next-stop mode: SIM_ENTITY_AT_TERMINAL.lineStop1 -> LINE.stops[lineStop1 + 1].stationGroup.
local function computeStationNext(group : integer, selected : {string : boolean}) : Snapshot
	local counts : {integer : integer} = {}
	local lines : {integer : Engine.Component.Line} = {}
	local posCache : {integer : {number}} = {}
	forEachWaiting(group, selected, true, function(_person : integer, at : Engine.Component.SimEntityAtTerminal)
		local dest = stopGroup(lineOf(at.line as integer, lines), at.lineStop1)
		if dest ~= nil and dest ~= group then
			counts[dest] = (counts[dest] or 0) + 1
		end
	end)
	local snap = sortedRows(counts, groupPos(group, posCache), posCache)
	snap.catchment = group
	return snap
end

-- Final destination ---------------------------------------------------------

--- A destination building: bbox top centre and town (TOWN_BUILDING.town, engine.d.tl:1305-1320).
--- Buildings don't move, so this is cached for the session (dropped when it grows too big).
local record BuildingInfo
	pos : {number}        -- nil without BOUNDING_VOLUME
	town : integer        -- nil: not a town building (industry, ...)
end
local buildingCache : {integer : BuildingInfo} = {}
local buildingCacheSize = 0

local function buildingInfo(entity : integer) : BuildingInfo
	local info = buildingCache[entity]
	if info ~= nil then return info end
	if buildingCacheSize >= BUILDING_CACHE_MAX then
		buildingCache, buildingCacheSize = {}, 0
	end
	local tb = comp(entity, api.type.ComponentType.TOWN_BUILDING) as Engine.Component.TownBuilding
	info = { pos = bboxTop(entity), town = tb and tb.town as integer or nil }
	buildingCache[entity] = info
	buildingCacheSize = buildingCacheSize + 1
	return info
end

local townNames : {integer : string} = {}
local function townName(town : integer) : string
	if town == nil or town < 0 then return _("Other") end
	local n = townNames[town]
	if n == nil then
		n = entityName(town) or _("Other")
		townNames[town] = n
	end
	return n
end

--- 0 Home, 1 Shop, 2 Work, nil unknown: base sim_person.tl:77-86 (target vs destinations[1..3]) and the
--- labels of sim_person_eow.script.tl:61-71 getDestinationTitle.
local function destinationIndex(sp : Engine.Component.SimPerson) : integer
	for i = 1, 3 do
		if sp.destinations[i] ~= nil and sp.targetOrAtEntity == sp.destinations[i] then return i - 1 end
	end
	return nil
end

local KIND_NAMES : {string} = { _("Home"), _("Shop"), _("Work") }

local function kindName(index : integer) : string
	return index ~= nil and KIND_NAMES[index + 1] or nil
end

local record Cluster
	x : number
	y : number
	z : number
	n : integer
end

--- Final-destination mode: each waiting passenger's SIM_PERSON.targetOrAtEntity, clustered on a
--- CLUSTER_M grid; one arrow per cluster (to its centroid), biggest first. Rows: counts per town.
local function computeStationFinal(group : integer, selected : {string : boolean}) : Snapshot
	local clusters : {string : Cluster} = {}
	local towns : {string : integer} = {}
	local kinds : {integer} = { 0, 0, 0, 0 }   -- home, shop, work, other
	local total = 0
	forEachWaiting(group, selected, false, function(person : integer, _at : Engine.Component.SimEntityAtTerminal)
		local sp = comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
		if sp == nil then return end
		total = total + 1
		local idx = destinationIndex(sp)
		kinds[(idx or 3) + 1] = kinds[(idx or 3) + 1] + 1
		local info = buildingInfo(sp.targetOrAtEntity as integer)
		local tn = townName(info.town)
		towns[tn] = (towns[tn] or 0) + 1
		local p = info.pos
		if p ~= nil then
			local key = tostring(math.floor(p[1] / CLUSTER_M)) .. ":" .. tostring(math.floor(p[2] / CLUSTER_M))
			local c = clusters[key]
			if c == nil then
				c = { x = 0.0, y = 0.0, z = 0.0, n = 0 }
				clusters[key] = c
			end
			c.x, c.y, c.z, c.n = c.x + p[1], c.y + p[2], c.z + p[3], c.n + 1
		end
	end)

	local posCache : {integer : {number}} = {}
	local from = groupPos(group, posCache)
	local list : {Cluster} = {}
	for __, c in pairs(clusters) do list[#list + 1] = c end
	table.sort(list, function(a : Cluster, b : Cluster) : boolean
		if a.n ~= b.n then return a.n > b.n end
		if a.x ~= b.x then return a.x < b.x end
		return a.y < b.y
	end)
	local snap : Snapshot = { arrows = {}, rows = {}, destinations = #list, passengers = total, catchment = group }
	if from ~= nil then
		for i = 1, math.min(#list, MAX_ARROWS) do
			local c = list[i]
			snap.arrows[#snap.arrows + 1] = { from = from, to = { c.x / c.n, c.y / c.n, c.z / c.n }, count = c.n }
		end
	end

	local townList : {string} = {}
	for name, __ in pairs(towns) do townList[#townList + 1] = name end
	table.sort(townList, function(a : string, b : string) : boolean
		if towns[a] ~= towns[b] then return towns[a] > towns[b] end
		return a < b
	end)
	for i = 1, math.min(#townList, MAX_ROWS) do
		snap.rows[#snap.rows + 1] = { name = townList[i], count = towns[townList[i]] }
	end
	if #townList > MAX_ROWS then
		snap.note = lang_util.format(_("+{n} more towns"), { n = tostring(#townList - MAX_ROWS) })
	end
	if total > 0 then
		local parts : {string} = {}
		for i = 1, 3 do parts[i] = KIND_NAMES[i] .. " " .. tostring(kinds[i]) end
		if kinds[4] > 0 then parts[4] = _("Other") .. " " .. tostring(kinds[4]) end
		snap.kinds = table.concat(parts, " · ")
	end
	return snap
end

-- SQPERF section "compute_station" (poll: onStepTimer worker thread; clicks: GUI thread)
local computeStation = perf:wrap("compute_station", function(group : integer, selected : {string : boolean}, mode : Mode) : Snapshot
	if mode == "next" then return computeStationNext(group, selected) end
	return computeStationFinal(group, selected)
end)

---------------------------------------------------------------------------
-- Person data

-- SQPERF section "compute_person" (poll: onStepTimer worker thread; clicks: GUI thread)
local computePerson = perf:wrap("compute_person", function(person : integer, mode : Mode) : Snapshot
	local snap : Snapshot = { arrows = {}, rows = {}, destinations = 0, passengers = 0 }
	local sp = comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
	if sp == nil then
		snap.note = _("No data for this person.")
		return snap
	end
	local lines : {integer : Engine.Component.Line} = {}
	local posCache : {integer : {number}} = {}
	local from = bboxTop(person)
	local to : {number} = nil

	-- the final destination: target building, "Home/Shop/Work, Town"
	local target = sp.targetOrAtEntity as integer
	local info = buildingInfo(target)
	local kind = kindName(destinationIndex(sp))
	local place = kind and (kind .. ", " .. townName(info.town)) or (entityName(target) or townName(info.town))

	local atV = comp(person, api.type.ComponentType.SIM_ENTITY_AT_VEHICLE) as Engine.Component.SimEntityAtVehicle
	local atT = comp(person, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL) as Engine.Component.SimEntityAtTerminal
	if atV ~= nil or atT ~= nil then
		local lineEntity = (atV ~= nil and atV.line or atT.line) as integer
		local line = lineOf(lineEntity, lines)
		local nextStop = stopGroup(line, atV ~= nil and atV.lineStop1 or atT.lineStop1)
		if from == nil then
			if atV ~= nil then
				from = vehiclePos(atV.vehicle as integer)
			else
				local here = stopGroup(line, atT.lineStop0)
				from = here and groupPos(here, posCache)
			end
		end
		local stopName = nextStop and (entityName(nextStop) or ("#" .. tostring(nextStop))) or "?"
		local lineName = entityName(lineEntity) or _("a line")
		if mode == "next" then
			to = nextStop and groupPos(nextStop, posCache)
		else
			to = info.pos
		end
		snap.note = lang_util.format(atV ~= nil and _("Riding {line}, off at {stop} -> {place}") or _("Waiting for {line}, off at {stop} -> {place}"),
			{ line = lineName, stop = stopName, place = place })
	else
		local atB = comp(person, api.type.ComponentType.SIM_ENTITY_AT_BUILDING)
		if atB ~= nil then
			snap.note = lang_util.format(_("At {place}: no trip right now."), { place = place })
		else
			if from == nil then
				from = vehiclePos(person)  -- a person driving is its own LAND_VEHICLE (sim_person.tl:39)
			end
			to = info.pos
			snap.note = lang_util.format(_("-> {place}"), { place = place })
		end
	end
	if from ~= nil and to ~= nil then
		snap.arrows[1] = { from = from, to = to, count = 1 }
		snap.destinations, snap.passengers = 1, 1
	elseif to ~= nil then
		snap.note = (snap.note or "") .. " " .. _("(Own position unknown: no arrow.)")
	end
	return snap
end)

--- pcall wrapper: a failing read draws nothing instead of breaking the window.
local function safe(fn : function() : Snapshot) : Snapshot
	local ok, snap = pcall(fn)
	if not ok then
		log.warning(LOG .. "read failed: " .. tostring(snap))
		return { arrows = {}, rows = {}, destinations = 0, passengers = 0, note = _("Could not read the data.") }
	end
	return snap as Snapshot
end

---------------------------------------------------------------------------
-- LayerConfig (as square_industry_flows buildLayerConfig / base industry.tl:329-361)

local layerColorsCache : {Vec4f} = nil
local function arrowColors() : {Vec4f}
	if layerColorsCache == nil then
		local layerColors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/layers/layer_colors.gres")).data as LayerColors
		layerColorsCache = color_util.toArray4(layerColors.CargoFlow.Consumers3D.Actual)
	end
	return layerColorsCache
end

local function vec3(p : {number}) : Vec3f
	return api.type.Vec3f.new(p[1], p[2], p[3])
end

-- SQPERF section "layer_config" (the tool action's render, GUI thread)
local buildLayerConfig = perf:wrap("layer_config", function(snap : Snapshot) : LayerConfig
	local layerConfig = api.type.LayerConfig.new()
	if snap == nil then return layerConfig end
	if snap.catchment ~= nil then
		-- the station window's own catchment display (station_group.tl:903-909), so it still looks like it
		local catchment = api.type.LayerConfig.CatchmentAreaRenderableConfig.new()
		catchment.isVisible = true
		catchment.entity = snap.catchment
		catchment.cargo = true
		catchment.person = true
		layerConfig.catchmentAreaRenderableConfig = catchment
	end
	if #snap.arrows == 0 then return layerConfig end
	local colors = arrowColors()
	local pax = passengerCargo()
	local flowData : {LayerConfig.CargoFlowRenderableConfig.FlowData} = {}
	for __, a in ipairs(snap.arrows) do
		local d = api.type.LayerConfig.CargoFlowRenderableConfig.FlowData.new()
		d.from = vec3(a.from)
		d.to = vec3(a.to)
		d.speed = 40.0
		d.arrowColors = colors
		d.cargoIconAlpha = 1.0
		d.cargoTypes = { pax }
		flowData[#flowData + 1] = d
	end
	local cfg = api.type.LayerConfig.CargoFlowRenderableConfig.new()
	cfg.flowData = flowData
	layerConfig.cargoFlowRenderableConfig = cfg
	return layerConfig
end)

---------------------------------------------------------------------------
-- Tool

local record PaxToolParam
	owner : integer
	entity : integer
	windowIds : {string}
	actionFn : function() : TreeNodeId
end

local record Active
	owner : integer
	entity : integer
	toolStackApi : Builtin.ToolStackAPI
end

--- The plugin instance whose tool is on the stack (nil: none). One at a time: a second push with the
--- same tool + key replaces the entry (builtin.lua copyToolStackExcept), and the first plugin sees it lost.
local active : Active = nil
local nextOwner = 0

local function windowIdOf(entity : integer) : string
	return "temp.view.entity_" .. tostring(entity)  -- view_manager.tl:62-64
end

local function reshowWindows(ids : {string})
	for __, id in ipairs(ids) do
		local ok, visible = pcall(api.gui.byId.isVisible, id)
		if ok and visible == false then
			local okSet = pcall(api.gui.byId.setVisible, id, true)
			log.message(LOG .. "push: window " .. id .. " was hidden by the shelve -> reshown=" .. tostring(okSet))
		elseif ok then
			log.message(LOG .. "push: window " .. id .. " visible=" .. tostring(visible))
		end
	end
end

local PaxDestTool : ReactToolDefinition<PaxToolParam> = react.RegisterTool({
	name = TOOL_NAME,
	push = function(ctx : Builtin.ToolStackContext<PaxToolParam>, param : PaxToolParam)
		log.message(LOG .. "push handler: owner=" .. tostring(param.owner) .. " entity=" .. tostring(param.entity))
		ctx.setActionFn(param.actionFn, ACTION_KEY)
		reshowWindows(param.windowIds)
	end,
	pop = function(_ctx : Builtin.ToolStackContext<PaxToolParam>, param : PaxToolParam)
		log.message(LOG .. "pop handler: owner=" .. tostring(param.owner) .. " entity=" .. tostring(param.entity))
		if active ~= nil and active.owner == param.owner then
			active = nil
		end
	end,
	shelve = function(_ctx : Builtin.ToolStackContext<PaxToolParam>, param : PaxToolParam, shelve : boolean)
		log.message(LOG .. "shelve handler: owner=" .. tostring(param.owner) .. " shelved=" .. tostring(shelve))
	end,
	getDebugString = function(_ctx : Builtin.ToolStackContext<PaxToolParam>, param : PaxToolParam) : string
		return "entity " .. tostring(param.entity)
	end,
} as ReactToolDefinition<PaxToolParam>)

local function toolStackApiOf(gameCtx : GameContext) : Builtin.ToolStackAPI
	if gameCtx ~= nil and gameCtx.toolStack ~= nil and not gameCtx.toolStack:hasExpired() then
		local ok, apiTs = pcall(function() : Builtin.ToolStackAPI return gameCtx.toolStack:get():getApi() end)
		if ok and apiTs ~= nil then return apiTs as Builtin.ToolStackAPI end
	end
	return game_react_globals.getDefaultToolStackApi()
end

local function isActive(owner : integer) : boolean
	return active ~= nil and active.owner == owner
end

local function popIfOwner(owner : integer, why : string)
	if not isActive(owner) then return end
	local a = active
	active = nil
	log.message(LOG .. "pop (" .. why .. "): owner=" .. tostring(owner) .. " entity=" .. tostring(a.entity))
	local ok, err = pcall(function() : any a.toolStackApi.pop(PaxDestTool, TOOL_KEY) return nil end)
	if not ok then
		log.warning(LOG .. "pop failed: " .. tostring(err))
	end
end

--- Same as popIfOwner, but on the main thread after the current react pass (unmount, timers).
local function popLater(owner : integer, why : string)
	react.enqueueJoin(function() popIfOwner(owner, why) end, "PaxDestPop")
end

--- Our action: the base default selector action (HUD icons, entity selection, tooltips) plus our
--- LayerConfig, while the tool is on top (only then is the action mounted). It does no engine reads:
--- current() returns the snapshot the plugin's own REFRESH_S timer computed for the card (Box.snap), so
--- each refresh scans the passengers once, not once for the card and once for the arrows.
-- The "refresh" diagnostics line (up to one per refresh while the arrows are on) is written only with
-- the "Debug: performance log" mod setting On (read once per Lua state; SQPERF's readParam).
local refreshLog : boolean = nil
local function refreshLogOn() : boolean
	if refreshLog == nil then refreshLog = sqperf.readParam("square_passenger_destinations", "sqperf_log") end
	return refreshLog
end

local function makeActionFn(gameCtx : GameContext, owner : integer, current : function() : Snapshot) : function() : TreeNodeId
	local lastLog = ""
	local lastLogTime = -1.0
	return function() : TreeNodeId
		local snapState = engine_react_util.useStepStateTimer(function() : Snapshot
			local snap = current()
			if snap == nil then return nil end
			if refreshLogOn() then
				local line = "dests=" .. tostring(snap.destinations) .. " drawn=" .. tostring(#snap.arrows) .. " pax=" .. tostring(snap.passengers)
				local now = os.time()  -- wall seconds; os.clock is CPU time of all threads and runs fast
				if line ~= lastLog or now - lastLogTime >= HEARTBEAT_S then
					log.message(LOG .. "refresh owner=" .. tostring(owner) .. " " .. line)
					lastLog, lastLogTime = line, now
				end
			end
			return snap
		end, ACTION_POLL_S)
		local layerConfig = buildLayerConfig(snapState:old())
		return selector_react_util.makeDefaultSelectorAction(gameCtx, layerConfig, true)()
	end
end

local function pushTool(gameCtx : GameContext, owner : integer, entity : integer, windowIds : {string}, current : function() : Snapshot) : boolean
	local tsApi = toolStackApiOf(gameCtx)
	if tsApi == nil then
		log.warning(LOG .. "no tool stack; cannot draw arrows")
		return false
	end
	local param : PaxToolParam = { owner = owner, entity = entity, windowIds = windowIds, actionFn = makeActionFn(gameCtx, owner, current) }
	active = { owner = owner, entity = entity, toolStackApi = tsApi }
	log.message(LOG .. "push: owner=" .. tostring(owner) .. " entity=" .. tostring(entity))
	local ok, err = pcall(function() : any tsApi.push(PaxDestTool, TOOL_KEY, param, true) return nil end)
	if not ok then
		active = nil
		log.warning(LOG .. "push failed: " .. tostring(err))
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Card widgets

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = str }
end

local function vbox(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end

local function checkBox(label : string, on : boolean, onChange : function(boolean), tooltip? : string) : TreeNodeId
	return builtin.CheckBox{
		meta = tooltip and { tooltip = tooltip } or nil,
		value = on and 1 or 0,
		label = label,
		onValueChange = function(value : integer) onChange(value == 1) end,
	}
end

local function snapshotRows(snap : Snapshot, mode : Mode, rows : {TreeNodeId})
	if snap == nil then
		rows[#rows + 1] = text(_("Reading..."), "font-scale-annotation")
		return
	end
	rows[#rows + 1] = text(lang_util.format(mode == "next" and _("{n} waiting passengers, next stop:") or _("{n} waiting passengers, going to:"),
		{ n = tostring(snap.passengers) }), "font-scale-body")
	if snap.kinds ~= nil then
		rows[#rows + 1] = text(snap.kinds, "font-scale-annotation")
	end
	for __, r in ipairs(snap.rows) do
		rows[#rows + 1] = text(lang_util.format("-> {name}: {n}", { name = r.name, n = tostring(r.count) }), "font-scale-annotation")
	end
	if mode == "next" and snap.destinations > #snap.rows then
		rows[#rows + 1] = text(lang_util.format(_("+{n} more stops"), { n = tostring(snap.destinations - #snap.rows) }), "font-scale-annotation")
	elseif snap.note ~= nil then
		rows[#rows + 1] = text(snap.note, "font-scale-annotation")
	end
	if snap.destinations > #snap.arrows and snap.destinations > 0 then
		rows[#rows + 1] = text(lang_util.format(mode == "next" and _("{drawn} of {total} stops drawn") or _("{drawn} of {total} areas drawn"),
			{ drawn = tostring(#snap.arrows), total = tostring(snap.destinations) }), "font-scale-annotation")
	end
end

local function hbox(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

--- Fixed-width gap between the checkboxes of a row (AAT's withGaps uses the same styled Component).
local function gap(width : integer) : TreeNodeId
	return builtin.Component{ meta = { styleSheet = styleutil.makeStyle{ size = { width, -1 } } } }
end

local function card(gameCtx : GameContext, showOnRight : boolean, localKey : string, rows : {TreeNodeId}, title? : string) : TreeNodeId
	-- a plugin's root must be a layout (memory "Recipe must return layout"); card shape as base
	-- sim_person_eow.script.tl:476-495 and AAT's line plugin
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			meta = { localKey = localKey },
			title = title,   -- optional: content_card.tl:231 skips the title row when nil
			extraChildrenPermanent = rows,
			gameCtx = gameCtx,
			showOnRightSide = showOnRight,
		},
	}
end

--- Per plugin instance: a token and a box the action's compute closure reads (so changing the
--- selection needs no re-push; the next refresh picks it up).
local record Box
	on : boolean
	entity : integer
	selected : {string : boolean}
	mode : Mode
	snap : Snapshot       -- latest computed snapshot (nil while off); the tool action draws it
end

--- "Next stop instead of final destination" switch, shared by both cards (default off = final).
local function modeBox(mode : Mode, onChange : function(Mode)) : TreeNodeId
	return builtin.CheckBox{
		meta = { tooltip = _("Off: the building each passenger travels to (home, shop or work). On: the stop where they leave the current line.") },
		value = mode == "next" and 1 or 0,
		label = _("Next stop instead of final destination"),
		onValueChange = function(value : integer) onChange(value == 1 and "next" or "final") end,
	}
end

local function useOwner() : integer
	local ref : ReactRefT<integer> = react.useRefLazy(function() : integer
		nextOwner = nextOwner + 1
		return nextOwner
	end)
	return ref:get()
end

--- Common lifecycle: pop on unmount, on entity change, and turn the UI off when the tool was popped or
--- replaced from elsewhere (clicking another entity clears the stack, another window took over, ...).
local function useLifecycle(owner : integer, entity : integer, box : Box, onLost : function())
	react.onUnmount(function()
		if box.on then popLater(owner, "unmount") end
	end)
	if box.on and box.entity ~= entity then
		box.on = false
		popLater(owner, "entity changed")
		react.enqueueJoin(onLost, "PaxDestLost")
	end
	react.onStepTimer(function()
		if box.on and not isActive(owner) then
			box.on = false
			log.message(LOG .. "lost: owner=" .. tostring(owner) .. " (tool popped or replaced elsewhere)")
			react.enqueueJoin(onLost, "PaxDestLost")
		end
	end, 0.5)
end

---------------------------------------------------------------------------
-- Station window plugin

local function copySet(s : {string : boolean}) : {string : boolean}
	local out : {string : boolean} = {}
	for k, v in pairs(s) do if v then out[k] = true end end
	return out
end

local function anySelected(s : {string : boolean}) : boolean
	for __, v in pairs(s) do if v then return true end end
	return false
end

-- SQPERF section "station_render" (GUI thread)
local PaxDestStationPlugin = react.RegisterPluginRecipe(station_group_eow.StationGroupEowExtensionPoint, "PaxDestStationPlugin", perf:wrap("station_render", function(p : StationGroupEow.StationGroupWidgetPluginParams) : TreeNodeId
	local group = p.entityId as integer
	local owner = useOwner()
	local boxRef : ReactRefT<Box> = react.useRefLazy(function() : Box return { on = false, entity = group, selected = {}, mode = "final" } end)
	local box = boxRef:get()
	local selState : ReactStateT<{string : boolean}> = react.useState({})
	local modeState : ReactStateT<Mode> = react.useState("final")
	local terminals = engine_react_util.useStepStateTimer(function() : {PaxTerminal}
		local ok, list = pcall(readTerminals, group)
		return ok and list as {PaxTerminal} or {}
	end, TERMINALS_S)
	local snapState = engine_react_util.useStepStateTimer(function() : Snapshot
		box.snap = box.on and safe(function() : Snapshot return computeStation(group, box.selected, box.mode) end) or nil
		return box.snap
	end, REFRESH_S)

	local function turnedOff()
		box.on, box.selected, box.snap = false, {}, nil
		if not selState:hasExpired() then selState:set({}) end
		if not snapState:hasExpired() then snapState:set(nil) end
	end
	useLifecycle(owner, group, box, turnedOff)

	--- New selection from a click (GUI thread): push on the first terminal, pop after the last.
	local function apply(sel : {string : boolean})
		box.selected = sel
		local want = anySelected(sel)
		if want and not isActive(owner) then
			local windowIds = { windowIdOf(group) }
			local sg = comp(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
			for __, station in ipairs(sg and sg.stations or {}) do
				-- a station inside a construction may be shown in the construction's window
				local ok, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, station)
				if ok and con and (con as integer) >= 0 then windowIds[#windowIds + 1] = windowIdOf(con as integer) end
			end
			box.on, box.entity = true, group
			if not pushTool(p.gameCtx, owner, group, windowIds, function() : Snapshot return box.snap end) then
				box.on, sel = false, {}
				box.selected = sel
			end
		elseif not want and box.on then
			box.on = false
			popIfOwner(owner, "untoggled")
		end
		selState:set(sel)
		box.snap = box.on and safe(function() : Snapshot return computeStation(group, sel, box.mode) end) or nil
		snapState:set(box.snap)
	end

	local list = terminals:old() or {}
	if #list == 0 then
		return builtin.BoxLayout{ children = {} }  -- no passenger lines here: no card
	end
	local sel = selState:old()
	local allOn = true
	for __, t in ipairs(list) do
		if not sel[t.key] then allOn = false end
	end

	-- Compact card (the extension point mounts plugins above Terminals, station_group.tl:863-866): one row
	-- "Destinations: [] All [] 1 [] 2 ... | [] Next stop"; beyond FIRST_ROW_TERMINALS the terminal boxes wrap.
	local lines : {{TreeNodeId}} = {}
	local cur : {TreeNodeId} = {
		text(_("Destinations:"), "font-scale-body"),
		gap(8),
		checkBox(_("All"), allOn, function(on : boolean)
			local s : {string : boolean} = {}
			if on then
				for __, t in ipairs(list) do s[t.key] = true end
			end
			apply(s)
		end, _("All terminals")),
	}
	local inRow = 0
	local limit = FIRST_ROW_TERMINALS
	for __, t in ipairs(list) do
		if inRow >= limit then
			lines[#lines + 1] = cur
			cur, inRow, limit = {}, 0, WRAP_ROW_TERMINALS
		else
			cur[#cur + 1] = gap(6)
		end
		cur[#cur + 1] = checkBox(tostring(t.display), sel[t.key] == true, function(on : boolean)
			local s = copySet(selState:old())
			s[t.key] = on or nil
			apply(s)
		end, lang_util.format(_("Terminal {n}"), { n = tostring(t.display) }))
		inRow = inRow + 1
	end
	cur[#cur + 1] = gap(12)
	cur[#cur + 1] = checkBox(_("Next stop"), modeState:old() == "next", function(on : boolean)
		local mode : Mode = on and "next" or "final"
		box.mode = mode
		modeState:set(mode)
		box.snap = box.on and safe(function() : Snapshot return computeStation(group, box.selected, mode) end) or nil
		snapState:set(box.snap)
	end, _("Off: the building each passenger travels to (home, shop or work). On: the stop where they leave the current line."))
	lines[#lines + 1] = cur

	local rows : {TreeNodeId} = {}
	for __, l in ipairs(lines) do rows[#rows + 1] = hbox(l) end
	if box.on then
		snapshotRows(snapState:old(), modeState:old(), rows)
	end
	return card(p.gameCtx, p.showCalloutOnRightSide, "paxDestStation", { vbox(rows) })
end))

---------------------------------------------------------------------------
-- Person window plugin

-- SQPERF section "person_render" (GUI thread)
local PaxDestPersonPlugin = react.RegisterPluginRecipe(sim_person_eow.SimPersonEowExtensionPoint, "PaxDestPersonPlugin", perf:wrap("person_render", function(p : SimPersonEow.SimPersonWidgetPluginParams) : TreeNodeId
	local person = p.entityId as integer
	local owner = useOwner()
	local boxRef : ReactRefT<Box> = react.useRefLazy(function() : Box return { on = false, entity = person, selected = {}, mode = "final" } end)
	local box = boxRef:get()
	local onState : ReactStateT<boolean> = react.useState(false)
	local modeState : ReactStateT<Mode> = react.useState("final")
	local snapState = engine_react_util.useStepStateTimer(function() : Snapshot
		box.snap = box.on and safe(function() : Snapshot return computePerson(person, box.mode) end) or nil
		return box.snap
	end, REFRESH_S)

	local function turnedOff()
		box.on, box.snap = false, nil
		if not onState:hasExpired() then onState:set(false) end
		if not snapState:hasExpired() then snapState:set(nil) end
	end
	useLifecycle(owner, person, box, turnedOff)

	local function toggle(on : boolean)
		if on and not isActive(owner) then
			box.on, box.entity = true, person
			if not pushTool(p.gameCtx, owner, person, { windowIdOf(person) }, function() : Snapshot return box.snap end) then
				box.on, on = false, false
			end
		elseif not on and box.on then
			box.on = false
			popIfOwner(owner, "untoggled")
		end
		onState:set(on)
		box.snap = box.on and safe(function() : Snapshot return computePerson(person, box.mode) end) or nil
		snapState:set(box.snap)
	end

	local rows : {TreeNodeId} = {
		checkBox(_("Show destination"), onState:old(), toggle),
		modeBox(modeState:old(), function(mode : Mode)
			box.mode = mode
			modeState:set(mode)
			box.snap = box.on and safe(function() : Snapshot return computePerson(person, mode) end) or nil
			snapState:set(box.snap)
		end),
	}
	if box.on then
		local snap = snapState:old()
		if snap ~= nil and snap.note ~= nil then
			rows[#rows + 1] = text(snap.note, "font-scale-annotation")
		elseif snap == nil then
			rows[#rows + 1] = text(_("Reading..."), "font-scale-annotation")
		end
	end
	return card(p.gameCtx, p.showCalloutOnRightSide, "paxDestPerson", { vbox(rows) }, _("Passenger destinations"))
end))

local result = {
	PaxDestStationPlugin = PaxDestStationPlugin,
	PaxDestPersonPlugin = PaxDestPersonPlugin,
}

perf:phase("init", perfInit)

return result
