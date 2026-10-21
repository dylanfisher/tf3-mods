-- Passenger Destinations: entity-window plugins that draw the base game's 3D cargo-flow arrows to where
-- passengers are going, in two jumps:
--   jump 1 (strong, CargoFlow.Consumers3D.Actual): to the stop where they leave the current line
--          (SIM_ENTITY_AT_*.lineStop1), one arrow per stop;
--   jump 2 (faded, Consumers3D.Potential + transparency, as base town.tl:1024-1035 draws potential flows):
--          from that stop to the building they travel to (SIM_PERSON.targetOrAtEntity), clustered on a
--          CLUSTER_M grid. Transfers after that stop are not in the API (SIM_PERSON has no route), so
--          jump 2 runs straight from the stop to the building.
-- A person walking or driving gets one strong arrow to the building.
--   * Station window (StationGroupEowExtensionPoint), vehicle window (VehicleEowExtensionPoint, order 20 =
--     under Basics) and person window (SimPersonEowExtensionPoint, order 41 = under "Current Route"): the
--     same compact card from one code path (useDestinations + destinationsRow): "Destinations: [] Show arrows",
--     the station adds "Terminals: [] 1 [] 2 ..." (all ticked by default), then the summary.
--   * Locate hover: hovering a person's Locate pin anywhere draws that person's arrows; hovering a Locations
--     pin (home / shop / work) in an open person window draws an arrow from the person to that building.
--   * Shift hover: hold Shift and point at a person, vehicle or station on the map to see its arrows (section
--     "Shift hover"). Shift-click a line (opens the line manager) moved to Line Manager Plus
--     (square_line_manager_plus, map_shift_click.lua) on 2026-10-11, before rev 5 was uploaded.
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
-- (window id "temp.view.entity_<keyEntity>", view_manager.tl:62-64; verified in game 2026-10-11). Popping
-- our tool un-shelves the window tool, which shows it and restores its own action (view_manager.tl:412-415).
--
-- Never an orphaned tool: popped on untoggle, on plugin unmount (window closed), when the window's entity
-- changes, and the plugin notices when something else popped or replaced it (module `active`).
-- Tool stack calls from unmount / timers go through react.enqueueJoin (main thread; memory
-- "onStep runs on worker threads"). Engine reads in timers are fine (base useStepStateTimer does them).
--
-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, slow calls (> 16 ms, at most one
-- line per section per minute) and, with the "Debug: performance log" mod setting, a 30 s summary.
-- Sections: the three plugin renders, locate_render and the arrow LayerConfig (GUI thread), the passenger
-- scans compute_station / compute_person / compute_vehicle, read_terminals and read_on_board
-- (useStepStateTimer polls, i.e. onStepTimer callbacks on worker threads "Main Pool N", and the click
-- handlers). api.type.Clock is safe on those threads (docs/findings.md "Timers and threads in GUI
-- contexts"). The per-refresh "[PaxDest] refresh" line is only written with that setting On.
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
local vehicle_eow = ug_require "::/gui/entity_window/vehicle/vehicle_eow.script.tl" as VehicleEow
local line_react_util = ug_require "::/gui/line_vehicle_mgmt/line_react_util.tl" as LineReactUtil
local view_manager_util = ug_require "::/gui/entity_window/view_manager_util.tl" as ViewManagerUtil
local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl" as ModEntryPoint

local LOG <const> = "[PaxDest] "
local REFRESH_S <const> = 1.0           -- arrows and counts refresh while on
local ACTION_POLL_S <const> = 0.25      -- the tool action picks up the card's latest snapshot (no engine reads)
local TERMINALS_S <const> = 2.0         -- terminal list of the station card
local MAX_STOP_ARROWS <const> = 10      -- jump-1 arrows (one per stop), most passengers first
local MAX_ARROWS <const> = 30           -- jump-2 arrows (stop -> area), most passengers first; the rest only counted
local MAX_ROWS <const> = 12             -- town rows listed in the card
local MAX_STOP_NAMES <const> = 5        -- stops named in the "Off at:" line
local TOOL_NAME <const> = "SquarePassengerDestinations"   -- react.RegisterTool names are global
local TOOL_KEY <const> = "square_passenger_destinations"
local HOVER_KEY <const> = "square_passenger_destinations_hover"  -- the Locate-hover arrow's own entry
local HOVER_OWNER <const> = -1          -- PaxToolParam.owner of the hover entry (cards count up from 1)
local ACTION_KEY <const> = "square_passenger_destinations"
local HEARTBEAT_S <const> = 10.0        -- an unchanged refresh is logged at most this often
local CLUSTER_M <const> = 150.0         -- destination grid cell (m): one jump-2 arrow per stop and occupied cell
local BUILDING_CACHE_MAX <const> = 20000  -- building info cache is dropped when it grows past this
local VEHICLE_REREAD_S <const> = 5        -- passengers on board re-read at least this often (s)
-- Shorter arrows are never drawn: a near-zero-length FlowData crashes the game (native assert
-- render_util.cpp:393 AddEveryNthPoint "(num)>=(2)", in game 2026-10-11 on a Locate hover). The
-- renderer's point spacing is unknown, so this is a generous margin. docs/findings.md "Cargo-flow arrows".
local MIN_ARROW_M <const> = 50.0

-- Shared texts of the three cards (one key each, so every card says the same thing).
local SHOW_ARROWS_TOOLTIP <const> = "Strong arrow: next stop, where they get off.\nFaded arrow: final destination (home, shop or work)."   -- i18n: keys

---------------------------------------------------------------------------
-- Plain data (numbers/strings/tables only, so useStepStateTimer's deepEquals can compare polls).

local record Arrow
	from : {number}       -- {x, y, z}
	to : {number}
	count : integer
	jump : integer        -- 1: to the stop where they get off; 2: from there to the building
end

local record Row
	name : string
	count : integer
end

local record Snapshot
	arrows : {Arrow}      -- drawn: jump 1 (at most MAX_STOP_ARROWS), jump 2 (at most MAX_ARROWS)
	rows : {Row}          -- towns, at most MAX_ROWS
	areas : integer       -- destination areas (grid cells)
	drawnAreas : integer  -- areas reached by a drawn arrow
	passengers : integer
	stops : string        -- "Market 3 · Harbour 1": where they get off, may be nil
	note : string         -- one line under the rows, may be nil
	kinds : string        -- "Home N · Shop N · Work N", may be nil
	catchment : integer   -- station group whose catchment area is drawn too (station window), may be nil
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

-- Station group positions across refreshes: stations rarely move, and each lookup costs a few native
-- calls per station. An entry is trusted for GROUP_POS_S wall seconds (a rebuilt station moves its
-- arrows within that); { pos (may be nil), os.time() }.
local GROUP_POS_S <const> = 10
local groupPosCache : {integer : {any}} = {}

--- Position of a station group: its own box if it has one, else the mean of its stations.
local function groupPos(group : integer, cache : {integer : {number}}) : {number}
	if cache[group] ~= nil then return cache[group] end
	local now = os.time()
	local hit = groupPosCache[group]
	if hit ~= nil and now - (hit[2] as integer) < GROUP_POS_S then
		cache[group] = hit[1] as {number}
		return hit[1] as {number}
	end
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
	groupPosCache[group] = { p, now }
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

-- Destinations --------------------------------------------------------------

--- A destination building: bbox top centre and town (TOWN_BUILDING.town, engine.d.tl:1305-1320).
--- Buildings don't move, so this is cached for the session (dropped when it grows too big).
local record BuildingInfo
	pos : {number}        -- nil without BOUNDING_VOLUME
	cell : string         -- CLUSTER_M grid cell of pos ("x:y"), nil without pos
	town : integer       -- nil: not a town building (industry, ...)
end
local buildingCache : {integer : BuildingInfo} = {}
local buildingCacheSize = 0

local function cellOf(p : {number}) : string
	return tostring(math.floor(p[1] / CLUSTER_M)) .. ":" .. tostring(math.floor(p[2] / CLUSTER_M))
end

local function buildingInfo(entity : integer) : BuildingInfo
	local info = buildingCache[entity]
	if info ~= nil then return info end
	if buildingCacheSize >= BUILDING_CACHE_MAX then
		buildingCache, buildingCacheSize = {}, 0
	end
	local tb = comp(entity, api.type.ComponentType.TOWN_BUILDING) as Engine.Component.TownBuilding
	local pos = bboxTop(entity)
	info = { pos = pos, cell = pos and cellOf(pos), town = tb and tb.town as integer or nil }
	buildingCache[entity] = info
	buildingCacheSize = buildingCacheSize + 1
	return info
end

-- Only names from the game are cached; "Other" is translated at use time (never stored or used as a key).
local townNames : {integer : string} = {}
local function townName(town : integer) : string
	if town == nil or town < 0 then return _("Other") end
	local n = townNames[town]
	if n == nil then
		n = entityName(town)
		if n == nil then return _("Other") end
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

-- English keys, translated at use time with _(). Whole phrases with placeholders, so a language can
-- reorder them (no sentence building).
local KIND_COUNTS : {string} = { "Home {n}", "Shop {n}", "Work {n}", "Other {n}" }   -- i18n: keys
local KIND_PLACES : {string} = { "Home, {town}", "Shop, {town}", "Work, {town}" }   -- i18n: keys

local record Cluster
	x : number
	y : number
	z : number
	n : integer
end

local function addTo(c : Cluster, p : {number})
	c.x, c.y, c.z, c.n = c.x + p[1], c.y + p[2], c.z + p[3], c.n + 1
end

local function newCluster() : Cluster
	return { x = 0.0, y = 0.0, z = 0.0, n = 0 }
end

local function centroid(c : Cluster) : {number}
	return { c.x / c.n, c.y / c.n, c.z / c.n }
end

local record Pair
	stop : integer        -- station group where they get off (nil: unknown, jump 2 starts at `from`)
	key : string          -- grid cell (BuildingInfo.cell)
	cell : Cluster
end

--- Many passengers (station, vehicle). each(visit) calls visit(person, line, lineStop1) per passenger
--- (line may be nil: no stop known). from: origin of jump 1 (nil: no arrows); exclude: a group never
--- used as a stop (the station itself).
local function aggregate(each : function(function(integer, integer, integer)), from : {number}, exclude : integer) : Snapshot
	local lines : {integer : Engine.Component.Line} = {}
	local posCache : {integer : {number}} = {}
	local stopCount : {integer : integer} = {}
	local byStop : {integer : {string : Pair}} = {}   -- stop (-1: unknown) -> cell -> pair (no per-passenger strings)
	local list : {Pair} = {}
	local cells : {string : boolean} = {}
	local towns : {integer : integer} = {}   -- town entity (-1: none) -> passengers
	local kinds : {integer} = { 0, 0, 0, 0 }   -- home, shop, work, other
	local total = 0
	each(function(person : integer, line : integer, stop1 : integer)
		local sp = comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
		if sp == nil then return end
		total = total + 1
		local idx = destinationIndex(sp)
		kinds[(idx or 3) + 1] = kinds[(idx or 3) + 1] + 1
		local info = buildingInfo(sp.targetOrAtEntity as integer)
		local tid = (info.town ~= nil and info.town >= 0) and info.town or -1
		towns[tid] = (towns[tid] or 0) + 1
		local stop = line ~= nil and stopGroup(lineOf(line, lines), stop1) or nil
		if stop == exclude then stop = nil end
		if stop ~= nil then stopCount[stop] = (stopCount[stop] or 0) + 1 end
		local p = info.pos
		if p ~= nil then
			local cell = info.cell
			cells[cell] = true
			local sk = stop or -1
			local inStop = byStop[sk]
			if inStop == nil then
				inStop = {}
				byStop[sk] = inStop
			end
			local pr = inStop[cell]
			if pr == nil then
				pr = { stop = stop, key = cell, cell = newCluster() }
				inStop[cell] = pr
				list[#list + 1] = pr
			end
			addTo(pr.cell, p)
		end
	end)

	local snap : Snapshot = { arrows = {}, rows = {}, areas = 0, drawnAreas = 0, passengers = total }
	for __ in pairs(cells) do snap.areas = snap.areas + 1 end

	-- jump 1: one arrow per stop, and the "Off at:" line
	local stops : {integer} = {}
	for s in pairs(stopCount) do stops[#stops + 1] = s end
	table.sort(stops, function(a : integer, b : integer) : boolean
		if stopCount[a] ~= stopCount[b] then return stopCount[a] > stopCount[b] end
		return a < b
	end)
	local names : {string} = {}
	for i, s in ipairs(stops) do
		if i <= MAX_STOP_ARROWS and from ~= nil then
			local to = groupPos(s, posCache)
			if to ~= nil then snap.arrows[#snap.arrows + 1] = { from = from, to = to, count = stopCount[s], jump = 1 } end
		end
		if i <= MAX_STOP_NAMES then
			names[#names + 1] = lang_util.format("{name} {n}", { name = entityName(s) or ("#" .. tostring(s)), n = tostring(stopCount[s]) })
		end
	end
	if #stops > MAX_STOP_NAMES then
		names[#names + 1] = lang_util.format(_("+{n} more stops"), { n = tostring(#stops - MAX_STOP_NAMES) })
	end
	if #names > 0 then
		snap.stops = lang_util.format(_("Off at: {stops}"), { stops = table.concat(names, " · ") })
	end

	-- jump 2: stop -> area, biggest first
	table.sort(list, function(a : Pair, b : Pair) : boolean
		if a.cell.n ~= b.cell.n then return a.cell.n > b.cell.n end
		if a.cell.x ~= b.cell.x then return a.cell.x < b.cell.x end
		if a.cell.y ~= b.cell.y then return a.cell.y < b.cell.y end
		return (a.stop or -1) < (b.stop or -1)
	end)
	local drawnCells : {string : boolean} = {}
	local drawn = 0
	for __, pr in ipairs(list) do
		if drawn >= MAX_ARROWS then break end
		local start = pr.stop ~= nil and groupPos(pr.stop, posCache) or from
		if start ~= nil then
			snap.arrows[#snap.arrows + 1] = { from = start, to = centroid(pr.cell), count = pr.cell.n, jump = 2 }
			drawn = drawn + 1
			drawnCells[pr.key] = true
		end
	end
	for __ in pairs(drawnCells) do snap.drawnAreas = snap.drawnAreas + 1 end

	-- towns and Home / Shop / Work
	local townList : {integer} = {}
	local townNamesOf : {integer : string} = {}
	for tid in pairs(towns) do
		townList[#townList + 1] = tid
		townNamesOf[tid] = townName(tid)
	end
	table.sort(townList, function(a : integer, b : integer) : boolean
		if towns[a] ~= towns[b] then return towns[a] > towns[b] end
		if townNamesOf[a] ~= townNamesOf[b] then return townNamesOf[a] < townNamesOf[b] end
		return a < b
	end)
	for i = 1, math.min(#townList, MAX_ROWS) do
		snap.rows[#snap.rows + 1] = { name = townNamesOf[townList[i]], count = towns[townList[i]] }
	end
	if #townList > MAX_ROWS then
		snap.note = lang_util.format(_("+{n} more towns"), { n = tostring(#townList - MAX_ROWS) })
	end
	if total > 0 then
		local parts : {string} = {}
		for i = 1, 3 do parts[i] = lang_util.format(_(KIND_COUNTS[i]), { n = tostring(kinds[i]) }) end   -- i18n: ignore
		if kinds[4] > 0 then parts[4] = lang_util.format(_(KIND_COUNTS[4]), { n = tostring(kinds[4]) }) end   -- i18n: ignore
		snap.kinds = table.concat(parts, " · ")
	end
	return snap
end

---------------------------------------------------------------------------
-- Station data

--- Calls visit(person, atTerminal) for every passenger waiting at the terminals of a group that are not
--- in `excluded`. Mirrors base station_group.tl:647-664 (makeStopTooltip): getLineStopSimEntities per
--- line stop of the terminal (getLineStopsForTerminal), then the person's SIM_ENTITY_AT_TERMINAL.
local function forEachWaiting(group : integer, excluded : {string : boolean}, visit : function(integer, Engine.Component.SimEntityAtTerminal))
	local pax = passengerCargo()
	local sg = comp(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
	for __, station in ipairs(sg and sg.stations or {}) do
		local st = comp(station, api.type.ComponentType.STATION) as Engine.Component.Station
		for i, __ in ipairs(st and st.terminals or {}) do
			if not excluded[tostring(station) .. ":" .. tostring(i - 1)] then
				local ok, stops = pcall(api.engine.system.lineSystem.getLineStopsForTerminal, station, i - 1)
				for __, ls in ipairs(ok and stops as {{integer}} or {}) do
					local okP, people = pcall(api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntities, ls[1], ls[2], pax)
					for __, person in ipairs(okP and people as {integer} or {}) do
						local at = comp(person, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL) as Engine.Component.SimEntityAtTerminal
						if at ~= nil then visit(person, at) end
					end
				end
			end
		end
	end
end

-- SQPERF section "compute_station" (poll: onStepTimer worker thread; clicks: GUI thread)
local computeStation = perf:wrap("compute_station", function(group : integer, excluded : {string : boolean}) : Snapshot
	local snap = aggregate(function(visit : function(integer, integer, integer))
		forEachWaiting(group, excluded, function(person : integer, at : Engine.Component.SimEntityAtTerminal)
			visit(person, at.line as integer, at.lineStop1)
		end)
	end, groupPos(group, {}), group)
	snap.catchment = group
	return snap
end)

---------------------------------------------------------------------------
-- Vehicle data

--- Passengers on board, cached per plugin. getVehicle2Cargo2SimEntitesMap covers every vehicle in the
--- game, so it is re-read only when the vehicle's passenger count changes or VEHICLE_REREAD_S passed
--- (passengers swapped at a stop with the count unchanged); the arrows' origin follows the vehicle
--- every refresh regardless.
local record OnBoard
	people : {integer}
	count : integer
	time : number
end

-- SQPERF section "read_on_board". As base entity_window_util.tl:1677-1680 (PassengersWidget, the
-- vehicle window's passenger list): the vehicle's entry, [1] = its passengers.
local readOnBoard = perf:wrap("read_on_board", function(vehicle : integer) : {integer}
	local ok, m = pcall(api.engine.system.simEntityAtVehicleSystem.getVehicle2Cargo2SimEntitesMap)
	local byCargo = ok and m ~= nil and (m as {integer : {integer : {integer}}})[vehicle] or nil
	return byCargo and byCargo[1] or {}
end)

local function onBoard(vehicle : integer, cache : OnBoard) : {integer}
	local ok, n = pcall(api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType, vehicle, passengerCargo())
	local count = ok and n as integer or -1
	local now = os.time()  -- wall seconds (os.clock is CPU time of all threads)
	if cache.people == nil or count ~= cache.count or now - cache.time >= VEHICLE_REREAD_S then
		cache.people, cache.count, cache.time = readOnBoard(vehicle), count, now
	end
	return cache.people
end

-- SQPERF section "compute_vehicle" (poll: onStepTimer worker thread; clicks: GUI thread)
local computeVehicle = perf:wrap("compute_vehicle", function(vehicle : integer, cache : OnBoard) : Snapshot
	local people = onBoard(vehicle, cache)
	return aggregate(function(visit : function(integer, integer, integer))
		for __, person in ipairs(people) do
			local at = comp(person, api.type.ComponentType.SIM_ENTITY_AT_VEHICLE) as Engine.Component.SimEntityAtVehicle
			if at ~= nil then visit(person, at.line as integer, at.lineStop1) else visit(person, nil, nil) end
		end
	end, vehiclePos(vehicle), nil)
end)

---------------------------------------------------------------------------
-- Person data

local record Trip
	from : {number}       -- the person, else their vehicle, else their stop
	line : integer        -- riding / waiting: the line, else nil
	atV : boolean
	nextStop : integer    -- where they get off the line, else nil
	atBuilding : boolean
end

local function tripOf(person : integer, posCache : {integer : {number}}) : Trip
	local trip : Trip = { from = bboxTop(person) }
	local atV = comp(person, api.type.ComponentType.SIM_ENTITY_AT_VEHICLE) as Engine.Component.SimEntityAtVehicle
	local atT = comp(person, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL) as Engine.Component.SimEntityAtTerminal
	if atV ~= nil or atT ~= nil then
		trip.atV = atV ~= nil
		trip.line = (atV ~= nil and atV.line or atT.line) as integer
		local line = comp(trip.line, api.type.ComponentType.LINE) as Engine.Component.Line
		trip.nextStop = stopGroup(line, atV ~= nil and atV.lineStop1 or atT.lineStop1)
		if trip.from == nil then
			if atV ~= nil then
				trip.from = vehiclePos(atV.vehicle as integer)
			else
				local here = stopGroup(line, atT.lineStop0)
				trip.from = here and groupPos(here, posCache)
			end
		end
	elseif comp(person, api.type.ComponentType.SIM_ENTITY_AT_BUILDING) ~= nil then
		trip.atBuilding = true
	elseif trip.from == nil then
		trip.from = vehiclePos(person)  -- a person driving is its own LAND_VEHICLE (sim_person.tl:39)
	end
	return trip
end

local function noPosition(snap : Snapshot)
	snap.note = snap.note ~= nil and lang_util.format(_("{note} (Own position unknown: no arrow.)"), { note = snap.note })
		or _("(Own position unknown: no arrow.)")
end

-- SQPERF section "compute_person" (poll: onStepTimer worker thread; clicks: GUI thread)
local computePerson = perf:wrap("compute_person", function(person : integer) : Snapshot
	local snap : Snapshot = { arrows = {}, rows = {}, areas = 0, drawnAreas = 0, passengers = 0 }
	local sp = comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
	if sp == nil then
		snap.note = _("No data for this person.")
		return snap
	end
	local posCache : {integer : {number}} = {}
	local target = sp.targetOrAtEntity as integer
	local info = buildingInfo(target)
	local kindIdx = destinationIndex(sp)
	local place = kindIdx ~= nil and lang_util.format(_(KIND_PLACES[kindIdx + 1]), { town = townName(info.town) })   -- i18n: ignore
		or (entityName(target) or townName(info.town))
	local trip = tripOf(person, posCache)
	if trip.atBuilding then
		snap.note = lang_util.format(_("At {place}: no trip right now."), { place = place })
		return snap
	end
	local to = info.pos
	if trip.line ~= nil then
		local stopName = trip.nextStop and (entityName(trip.nextStop) or ("#" .. tostring(trip.nextStop))) or "?"
		snap.note = lang_util.format(trip.atV and _("Riding {line}, off at {stop} -> {place}") or _("Waiting for {line}, off at {stop} -> {place}"),
			{ line = entityName(trip.line) or _("a line"), stop = stopName, place = place })
		local stopPos = trip.nextStop and groupPos(trip.nextStop, posCache)
		if stopPos ~= nil then
			if trip.from ~= nil then snap.arrows[#snap.arrows + 1] = { from = trip.from, to = stopPos, count = 1, jump = 1 } end
			if to ~= nil then snap.arrows[#snap.arrows + 1] = { from = stopPos, to = to, count = 1, jump = 2 } end
		elseif trip.from ~= nil and to ~= nil then
			snap.arrows[1] = { from = trip.from, to = to, count = 1, jump = 1 }
		end
	else
		snap.note = lang_util.format(_("-> {place}"), { place = place })
		if trip.from ~= nil and to ~= nil then snap.arrows[1] = { from = trip.from, to = to, count = 1, jump = 1 } end
	end
	if trip.from == nil and to ~= nil then noPosition(snap) end
	snap.passengers = 1
	return snap
end)

--- Locations hover: one arrow from the person (or their vehicle / stop) to one of their buildings.
local function computePersonTo(person : integer, building : integer) : Snapshot
	local snap : Snapshot = { arrows = {}, rows = {}, areas = 0, drawnAreas = 0, passengers = 1 }
	local trip = tripOf(person, {})
	local from = trip.from or (trip.atBuilding and bboxTop((comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson).targetOrAtEntity as integer)) or nil
	local to = buildingInfo(building).pos
	if from ~= nil and to ~= nil then snap.arrows[1] = { from = from, to = to, count = 1, jump = 1 } end
	return snap
end

--- pcall wrapper: a failing read draws nothing instead of breaking the window.
local function safe(fn : function() : Snapshot) : Snapshot
	local ok, snap = pcall(fn)
	if not ok then
		log.warning(LOG .. "read failed: " .. tostring(snap))
		return { arrows = {}, rows = {}, areas = 0, drawnAreas = 0, passengers = 0, note = _("Could not read the data.") }
	end
	return snap as Snapshot
end

---------------------------------------------------------------------------
-- LayerConfig (as square_industry_flows buildLayerConfig / base industry.tl:329-361, town.tl:1022-1035)

local jumpColorsCache : {integer : {Vec4f}} = nil
local function jumpColors(jump : integer) : {Vec4f}
	if jumpColorsCache == nil then
		local layerColors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/layers/layer_colors.gres")).data as LayerColors
		local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data as GResTransparency
		jumpColorsCache = {
			[1] = color_util.toArray4(layerColors.CargoFlow.Consumers3D.Actual),
			[2] = color_util.toArray4WithTransparency(layerColors.CargoFlow.Consumers3D.Potential, transparency.Low),
		}
	end
	return jumpColorsCache[jump] or jumpColorsCache[2]
end

--- Finite coordinates and at least MIN_ARROW_M long (see MIN_ARROW_M: shorter ones crash the game).
local function drawable(a : Arrow) : boolean
	if a.from == nil or a.to == nil then return false end
	local d2 = 0.0
	for i = 1, 3 do
		local u, v = a.from[i], a.to[i]
		if u == nil or v == nil or u ~= u or v ~= v or u == math.huge or u == -math.huge or v == math.huge or v == -math.huge then
			return false
		end
		d2 = d2 + (v - u) * (v - u)
	end
	return d2 >= MIN_ARROW_M * MIN_ARROW_M
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
	local pax = passengerCargo()
	local flowData : {LayerConfig.CargoFlowRenderableConfig.FlowData} = {}
	for __, a in ipairs(snap.arrows) do
		if drawable(a) then
			local d = api.type.LayerConfig.CargoFlowRenderableConfig.FlowData.new()
			d.from = vec3(a.from)
			d.to = vec3(a.to)
			d.speed = 40.0
			d.arrowColors = jumpColors(a.jump)
			d.cargoIconAlpha = a.jump == 1 and 1.0 or 0.5
			d.cargoTypes = { pax }
			flowData[#flowData + 1] = d
		end
	end
	if #flowData == 0 then return layerConfig end
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

-- Locate hover state (section "Locate hover" below); the tool's pop handler clears it.
local hover : {string : integer} = nil   -- { person, token }: the person whose arrow the hover entry draws
local function hoverPopped(person : integer)
	if hover ~= nil and hover.person == person then hover = nil end
end

-- Shift hover poll (section "Shift hover" below), run by every action of our tool while it is mounted.
local shiftPoll : function()

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
		if param.owner == HOVER_OWNER then
			hoverPopped(param.entity)
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

-- The game's one GameContext: from any card's plugin params, or from the map's default tool (it builds
-- its action through selector_react_util.makeDefaultSelectorCombinedFn{gameCtx = ...}, view_manager.tl:56-58,
-- wrapped in the Shift hover section). Nil only until the first of these after a load.
local lastGameCtx : GameContext = nil

local function makeActionFn(gameCtx : GameContext, owner : integer, current : function() : Snapshot) : function() : TreeNodeId
	local lastLog = ""
	local lastLogTime = -1.0
	return function() : TreeNodeId
		react.onStep(function() shiftPoll() end)   -- main thread (memory "onStepTimer runs on worker threads")
		local snapState = engine_react_util.useStepStateTimer(function() : Snapshot
			local snap = current()
			if snap == nil then return nil end
			if refreshLogOn() then
				local line = "areas=" .. tostring(snap.areas) .. " drawn=" .. tostring(#snap.arrows) .. " pax=" .. tostring(snap.passengers)
				local now = os.time()  -- wall seconds; os.clock is CPU time of all threads and runs fast
				if line ~= lastLog or now - lastLogTime >= HEARTBEAT_S then
					log.message(LOG .. "refresh owner=" .. tostring(owner) .. " " .. line)
					lastLog, lastLogTime = line, now
				end
			end
			return snap
		end, ACTION_POLL_S)
		local layerConfig = buildLayerConfig(snapState:old())
		local ctx = gameCtx or lastGameCtx
		-- each base selector helper only where this platform has it (PS5 report 2026-10-19, Smart Lanes;
		-- docs/findings/gui.md "Base GUI modules differ by platform"): the arrows alone otherwise
		local su = selector_react_util as {string : any}
		local sAction, sSelector, sTips = su.makeDefaultSelectorAction, su.makeDefaultSelector, su.makeDefaultSelectorTooltips
		if ctx == nil or not sAction is function then
			-- no game context seen yet: the arrows and the map selector, no HUD icons. The selector must stay:
			-- without it nothing reports the mouse while our tool is on top, so Shift hover took every push
			-- for "mouse left", popped, the map's selector reported the entity again, and the arrows flashed
			-- on and off ~3 times a second (in game 2026-10-11, until a window had been opened).
			local selectedRef : ReactRefT<Engine.Entity> = react.useRef(-1)
			local children : {TreeNodeId} = {}
			if sSelector is function and sTips is function then
				children[1] = selector_react_util.makeDefaultSelector(game_react_globals.getDefaultRendererComponent(), selectedRef, nil)
				children[2] = selector_react_util.makeDefaultSelectorTooltips(selectedRef)
			end
			children[#children + 1] = builtin.LayerConfig{ config = layerConfig }
			return builtin.ActionDescriptor{ children = children, terrainCirclePolicy = "Never" }
		end
		return selector_react_util.makeDefaultSelectorAction(ctx, layerConfig, true)()
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
-- Locate hover (plans/square_passenger_destinations/PLAN.md "D"). The Locate pin is base
-- line_react_util.LocateButton (line_react_util.tl:209), which every name row builds through
-- NameTextView (line_react_util.tl:331, a field lookup at render time), and it has no extension point.
-- So this module replaces that field in the shared module table with a recipe that wraps the original
-- in a Component with meta.onMouseOver (the base pattern of tile_list_react_util.tl:222-233):
--   * a person's pin (vehicle passengers, waiting lists, residents): that person's arrows;
--   * a building pin (TOWN_BUILDING / INDUSTRY) that, on hover, is a home / shop / work of a person whose
--     window is open (the person window's Locations card, sim_person_eow.script.tl DestinationTown): an
--     arrow from the person to it; with no such person the hover does nothing.
-- Any other pin (vehicles, stations, depots, ...) gets the original. The "Current Route" Home / Work buttons are a local recipe of
-- sim_person_eow.script.tl (DestinationAndTypeButton), so they can't be wrapped.
-- On hover a separate tool entry (HOVER_KEY) is pushed on top of whatever is there, so a card's arrows
-- come back when it pops. The push shelves the window tools below, which hides the hovered window
-- unless pinned (view_manager.tl:404-415): the windows that were visible just before the push are
-- shown again by the push handler. Which window holds the row is unknown here, so the candidates are
-- the windows our cards know are open plus the person's vehicle, stop and destination buildings.

local openWindows : {string : integer} = {}    -- window id -> open cards in it (our three plugins)
local openPersons : {integer : integer} = {}   -- person entity -> open person cards

local function noteWindow(entity : integer, delta : integer)
	local id = windowIdOf(entity)
	local n = (openWindows[id] or 0) + delta
	openWindows[id] = n > 0 and n or nil
end

local function notePerson(person : integer, delta : integer)
	local n = (openPersons[person] or 0) + delta
	openPersons[person] = n > 0 and n or nil
end

--- The person with an open window whose home / shop / work is `building`, else nil.
local function personOfBuilding(building : integer) : integer
	for person in pairs(openPersons) do
		local sp = comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
		if sp ~= nil then
			for i = 1, 3 do
				if sp.destinations[i] == building then return person end
			end
		end
	end
	return nil
end

--- Windows that may hold the hovered row: our cards' windows, the entity's own, and for a person their
--- vehicle, stop and buildings.
local function hoverCandidates(person : integer) : {string}
	local set : {string : boolean} = {}
	for id in pairs(openWindows) do set[id] = true end
	local function add(e : integer) if e ~= nil and e >= 0 then set[windowIdOf(e)] = true end end
	add(person)
	local atV = comp(person, api.type.ComponentType.SIM_ENTITY_AT_VEHICLE) as Engine.Component.SimEntityAtVehicle
	if atV ~= nil then add(atV.vehicle as integer) end
	local atT = comp(person, api.type.ComponentType.SIM_ENTITY_AT_TERMINAL) as Engine.Component.SimEntityAtTerminal
	if atT ~= nil then
		local line = comp(atT.line as integer, api.type.ComponentType.LINE) as Engine.Component.Line
		add(stopGroup(line, atT.lineStop0))
	end
	local sp = comp(person, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
	if sp ~= nil then
		add(sp.targetOrAtEntity as integer)
		for i = 1, 3 do add(sp.destinations[i] as integer) end
	end
	local visible : {string} = {}
	for id in pairs(set) do
		local ok, v = pcall(api.gui.byId.isVisible, id)
		if ok and v == true then visible[#visible + 1] = id end
	end
	return visible
end

local hoverCount = 0   -- pushes this session, logged
-- At most this many hover pushes per wall second; more are skipped until the next second. Sweeping the
-- mouse down a list makes ~10 a second (in game 2026-10-11); a real push/pop loop would hit the cap every
-- second and show as one "throttled" line per second.
local HOVER_PER_SECOND <const> = 20
local hoverSecond, hoverInSecond = -1, 0

local function hoverOff(token : integer, why : string)
	if hover == nil or hover.token ~= token then return end
	local h = hover
	hover = nil
	log.message(LOG .. "hover pop (" .. why .. "): entity=" .. tostring(h.person))
	local ok, err = pcall(function() : any toolStackApiOf(lastGameCtx).pop(PaxDestTool, HOVER_KEY) return nil end)
	if not ok then log.warning(LOG .. "hover pop failed: " .. tostring(err)) end
end

--- The hover entry's scan at the cards' cadence: the action polls every ACTION_POLL_S, a scan runs every
--- REFRESH_S (the first poll scans at once). Without this a hovered station was scanned 4 times a second.
local function throttled(current : function() : Snapshot) : function() : Snapshot
	local every = math.floor(REFRESH_S / ACTION_POLL_S + 0.5)
	local snap : Snapshot = nil
	local polls = 0
	return function() : Snapshot
		polls = polls + 1
		if snap == nil or polls >= every then snap, polls = safe(current), 0 end
		return snap
	end
end

local function hoverOn(person : integer, token : integer, current : function() : Snapshot)
	if hover ~= nil and hover.token == token then return end
	local tsApi = toolStackApiOf(lastGameCtx)
	if tsApi == nil then
		log.warning(LOG .. "hover: no tool stack")
		return
	end
	local now = os.time()
	if now ~= hoverSecond then hoverSecond, hoverInSecond = now, 0 end
	hoverInSecond = hoverInSecond + 1
	if hoverInSecond > HOVER_PER_SECOND then
		if hoverInSecond == HOVER_PER_SECOND + 1 then
			log.warning(LOG .. "hover throttled: more than " .. tostring(HOVER_PER_SECOND) .. " pushes this second")
		end
		return
	end
	local windowIds = hoverCandidates(person)
	hoverCount = hoverCount + 1
	hover = { person = person, token = token }
	log.message(LOG .. "hover push #" .. tostring(hoverCount) .. ": entity=" .. tostring(person) .. " token=" .. tostring(token) .. " gameCtx="
		.. tostring(lastGameCtx ~= nil) .. " visible windows=" .. table.concat(windowIds, ","))
	local param : PaxToolParam = { owner = HOVER_OWNER, entity = person, windowIds = windowIds,
		actionFn = makeActionFn(lastGameCtx, HOVER_OWNER, throttled(current)) }
	local ok, err = pcall(function() : any tsApi.push(PaxDestTool, HOVER_KEY, param, true) return nil end)
	if not ok then
		hover = nil
		log.warning(LOG .. "hover push failed: " .. tostring(err))
	end
end

local nextHoverToken = 0
local baseLocateButton = line_react_util.LocateButton

-- SQPERF section "locate_render" (GUI thread; one per Locate pin rendered anywhere)
-- The caller's meta (the row's "hidden-button" class while not hovered, line_react_util.tl / vehicle_list_react_util.tl)
-- must reach the base pin: the base CSS hides it by "#menu.management R::LocateButton!hidden-button Button *"
-- (line_vehicle_mgmt.css.lua:355-361). react applies a recipe call's meta to that recipe's node and strips it from the
-- params, so through our recipe the class landed on R::PaxDestHoverLocateButton and the pins showed on every row
-- (player report 2026-10-11, Line Manager line and vehicle lists). LocateButtonEntry (the field we install) moves
-- the meta into META_KEY before the recipe call; baseParam hands it back to the base recipe call as its meta.
local META_KEY = "squarePaxDestMeta"

local function baseParam(param : LineReactUtil.LocateButtonParam) : LineReactUtil.LocateButtonParam
	local p = param as {string : any}
	local meta = p[META_KEY]
	if meta == nil then return param end
	local q : {string : any} = {}
	for k, v in pairs(p) do
		if k ~= META_KEY then q[k] = v end
	end
	q.meta = meta
	return q as LineReactUtil.LocateButtonParam
end

local HoverLocateButton = react.RegisterRecipe("PaxDestHoverLocateButton", perf:wrap("locate_render", function(param : LineReactUtil.LocateButtonParam) : TreeNodeId
	local tokenRef : ReactRefT<integer> = react.useRefLazy(function() : integer
		nextHoverToken = nextHoverToken + 1
		return nextHoverToken
	end)
	local token = tokenRef:get()
	react.onUnmount(function()
		-- the row went away under the mouse (window closed, list refreshed): no mouse-out comes
		if hover ~= nil and hover.token == token then
			react.enqueueJoin(function() hoverOff(token, "unmount") end, "PaxDestHoverOff")
		end
	end)
	local entity = param.entity as integer
	-- persons, and buildings that can be someone's home / shop / work. Whose: looked up on hover, as
	-- the Locations card renders before our person card registers its person (openPersons).
	-- Classified once per entity: this renders for every pin of every list (line manager, passenger
	-- lists), and a list re-renders its rows often.
	local kindRef : ReactRefT<{integer}> = react.useRef(nil)   -- { entity, kind }: 0 other, 1 person, 2 building
	local memo = kindRef:get()
	if memo == nil or memo[1] ~= entity then
		local kind = 0
		if entity ~= nil and entity >= 0 then
			if comp(entity, api.type.ComponentType.SIM_PERSON) ~= nil then
				kind = 1
			elseif comp(entity, api.type.ComponentType.TOWN_BUILDING) ~= nil or comp(entity, api.type.ComponentType.INDUSTRY) ~= nil then
				kind = 2
			end
		end
		memo = { entity, kind }
		kindRef:set(memo)
	end
	local isPerson = memo[2] == 1
	local isBuilding = memo[2] == 2
	if not isPerson and not isBuilding then
		return builtin.BoxLayout{ children = { baseLocateButton(baseParam(param)) } }
	end
	local function onHover(hovered : boolean)
		if not hovered then
			hoverOff(token, "mouse out")
		elseif isPerson then
			hoverOn(entity, token, function() : Snapshot return computePerson(entity) end)
		else
			local person = personOfBuilding(entity)
			if person ~= nil then
				hoverOn(person, token, function() : Snapshot return computePersonTo(person, entity) end)
			end
		end
	end
	return builtin.BoxLayout{
		children = {
			builtin.Component{
				meta = {
					onMouseOver = onHover,
				},
				layout = builtin.BoxLayout{ children = { baseLocateButton(baseParam(param)) } },
			},
		},
	}
end))

do
	local m = line_react_util as {string : any}
	if baseLocateButton ~= nil and m.squarePaxDestHover == nil then
		m.squarePaxDestHover = true
		-- a plain function, not a recipe: it sees the caller's meta (react strips it only from a recipe's params)
		m.LocateButton = function(param : LineReactUtil.LocateButtonParam) : TreeNodeId
			local p = param as {string : any}
			if type(p) ~= "table" or p.meta == nil then return HoverLocateButton(param) end
			local q : {string : any} = {}
			for k, v in pairs(p) do
				if k ~= "meta" then q[k] = v end
			end
			q[META_KEY] = p.meta
			return HoverLocateButton(q as LineReactUtil.LocateButtonParam)
		end
		log.message(LOG .. "hover: LocateButton replaced")
	else
		log.message(LOG .. "hover: LocateButton not replaced (missing or already done)")
	end
end

---------------------------------------------------------------------------
-- Shift hover (PLAN.md "F"): hold Shift (input action IA_PRECISION_MODE, as zhenya mods and
-- UI Overhaul read it) and point at a person, vehicle or station on the map: its arrows show, without
-- opening a window. The map's hovered entity comes from base selector_react_util.makeDefaultSelector
-- (selector_react_util.tl:88-104, onHover -> selectedEntityRef:set), which every default selector action
-- builds through a field lookup (selector_react_util.tl:231, 347), so wrapping that field sees each hover.
-- Only while the top tool is the plain map / an entity window (EntityDetailsTool, view_manager.tl:340;
-- the map's default tool is the same tool with key "__pinned__", game.tl:396-467) or our own tool: never
-- in the line manager ("Manager"), construction, layers, statistics or any other tool.
-- The hovered entity is mapped to the window it would open (view_manager_util.wouldCreateView: carriage
-- -> vehicle, station -> station group). Show and hide go through react.enqueueJoin (the selector that
-- reports the hover is replaced by the push). While the arrows show, our action polls (onStep, main
-- thread): Shift released, or the mouse on something else for SHIFT_LEAVE_US -> hide / switch. The delay
-- absorbs the hover the new action's selector reports when it mounts.
-- Another tool pushed on top (a Shift-click that opens the line manager, Line Manager Plus's
-- "Map: Shift-click a line" feature, or a window) shelves the entry and unmounts our action, so its poll
-- stops: the entry point's onStep then pops it (shiftOnTop, below), or the arrows would wait under the
-- other tool and come back when it closes.

local SHIFT_ACTION <const> = "IA_PRECISION_MODE"
local SHIFT_TOKEN <const> = -2           -- hover token of the Shift entry
local SHIFT_LEAVE_US <const> = 250000    -- the mouse must stay elsewhere this long (us) before the arrows change
local SHIFT_TOOLS : {string : boolean} = { EntityDetailsTool = true, [TOOL_NAME] = true }

local mapHover : integer = -1     -- entity the map's default selector reported last (-1: nothing)
local mapHoverAt = 0.0            -- clock (us) of that report
local shiftRaw : integer = nil    -- hovered entity the Shift entry was opened for
local shiftOnTop = false          -- our action's poll ran since the Shift entry was pushed (it was on top)
local shiftClock : Clock = nil
local shiftCaches : {integer : OnBoard} = {}
local shiftCacheCount = 0

local function nowUs() : number
	if shiftClock == nil then shiftClock = api.type.Clock.new() end
	return shiftClock:getTime()
end

local function shiftHeld() : boolean
	local ok, on = pcall(api.gui.inputAction.modifierOnlyActionIsActive, SHIFT_ACTION)
	return ok and on == true
end

local function shiftAllowed() : boolean
	local tsApi = toolStackApiOf(lastGameCtx)
	if tsApi == nil or tsApi.getActiveTool == nil then return false end
	local ok, tool = pcall(tsApi.getActiveTool)
	local def = ok and tool as {string : any} or nil
	return def ~= nil and SHIFT_TOOLS[def.name as string] == true
end

local function vehicleCache(vehicle : integer) : OnBoard
	local c = shiftCaches[vehicle]
	if c == nil then
		if shiftCacheCount >= 50 then shiftCaches, shiftCacheCount = {}, 0 end
		c = { people = nil, count = -1, time = 0 }
		shiftCaches[vehicle] = c
		shiftCacheCount = shiftCacheCount + 1
	end
	return c
end

--- The entity whose arrows a hover on `raw` shows, and the scan for them; nil when not supported.
local function shiftTarget(raw : integer) : integer, function() : Snapshot
	if raw == nil or raw < 0 then return nil, nil end
	local ok, e = pcall(view_manager_util.wouldCreateView, raw)
	local entity = (ok and e ~= nil and (e as integer) >= 0) and e as integer or raw
	if comp(entity, api.type.ComponentType.SIM_PERSON) ~= nil then
		return entity, function() : Snapshot return computePerson(entity) end
	end
	if comp(entity, api.type.ComponentType.TRANSPORT_VEHICLE) ~= nil then
		local cache = vehicleCache(entity)
		return entity, function() : Snapshot return computeVehicle(entity, cache) end
	end
	local group : integer = nil
	if comp(entity, api.type.ComponentType.STATION_GROUP) ~= nil then
		group = entity
	else
		local station = entity
		if comp(entity, api.type.ComponentType.STATION) == nil then
			local con = comp(entity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
			station = con ~= nil and con.stations ~= nil and con.stations[1] as integer or nil
		end
		if station ~= nil then
			local okG, g = pcall(api.engine.system.stationGroupSystem.getStationGroup, station)
			if okG and g ~= nil and (g as integer) >= 0 then group = g as integer end
		end
	end
	if group ~= nil then
		return group, function() : Snapshot return computeStation(group, {}) end
	end
	return nil, nil
end

local function shiftHide(why : string)
	if shiftRaw == nil then return end
	shiftRaw, shiftOnTop = nil, false
	hoverOff(SHIFT_TOKEN, why)
end

local function shiftShow(raw : integer) : boolean
	local entity, current = shiftTarget(raw)
	if entity == nil then return false end
	shiftRaw, shiftOnTop = raw, false
	-- switching: the new push replaces the entry in place (same tool + key), no pop and re-shelve between
	if hover ~= nil and hover.token == SHIFT_TOKEN then hover = nil end
	hoverOn(entity, SHIFT_TOKEN, current)
	if hover == nil or hover.token ~= SHIFT_TOKEN then shiftRaw = nil end   -- throttled or failed
	return shiftRaw ~= nil
end

local function onMapHover(raw : integer)
	if raw ~= mapHover then mapHover, mapHoverAt = raw, nowUs() end
	-- the entry went away without our poll (a click opened a window, a Locate hover replaced it, ...)
	if shiftRaw ~= nil and (hover == nil or hover.token ~= SHIFT_TOKEN) then shiftRaw = nil end
	if shiftRaw ~= nil or raw == nil or raw < 0 then return end   -- showing: the poll handles changes
	if not shiftHeld() or not shiftAllowed() then return end
	react.enqueueJoin(function()
		if shiftRaw == nil and mapHover == raw and shiftHeld() then shiftShow(raw) end
	end, "PaxDestShiftShow")
end

shiftPoll = function()
	if shiftRaw == nil then return end
	if hover == nil or hover.token ~= SHIFT_TOKEN then   -- popped elsewhere (a click opened a window, ...)
		shiftRaw = nil
		return
	end
	shiftOnTop = true
	if not shiftHeld() then
		react.enqueueJoin(function() shiftHide("shift released") end, "PaxDestShiftHide")
		return
	end
	if mapHover ~= shiftRaw and nowUs() - mapHoverAt >= SHIFT_LEAVE_US then
		local raw = mapHover
		react.enqueueJoin(function()
			local target = raw >= 0 and shiftTarget(raw) or nil
			if target == nil then
				shiftHide("mouse left")
			elseif hover ~= nil and hover.token == SHIFT_TOKEN and hover.person == target then
				shiftRaw = raw   -- another part of the same thing (a station of the group, a carriage): no re-push
			else
				shiftShow(raw)
			end
		end, "PaxDestShiftSwitch")
	end
end

-- Line Manager Plus (map_shift_click.lua) wraps the same field for Shift-click, with its own guard flag
-- (squareLmpShiftClick); each mod wraps whatever the field holds when it installs, so either order chains.
do
	local m = selector_react_util as {string : any}
	local base = selector_react_util.makeDefaultSelector
	if base ~= nil and m.squarePaxDestShift == nil then
		m.squarePaxDestShift = true
		selector_react_util.makeDefaultSelector = function(refRC : ReactRefWrapApiT<Builtin.RendererComponentParam, Builtin.RenderComponentAPI>,
				selectedEntityRef : ReactRefT<Engine.Entity>, allowStacking : boolean, filters? : ReactRefT<GameContext.Filters>,
				invertedSelectionColors? : boolean) : TreeNodeId
			-- the base onHover only calls :set (selector_react_util.tl:101-104); forward it unchanged
			local proxy = {
				set = function(_self : any, entity : Engine.Entity)
					local ok, err : boolean, any = pcall(onMapHover, entity as integer)
					if not ok then log.warning(LOG .. "shift hover failed: " .. tostring(err)) end
					-- an unmounted action's selector may still report (base: "Ignoring Set() on expired")
					if selectedEntityRef and not selectedEntityRef:hasExpired() then selectedEntityRef:set(entity) end
				end,
				get = function(_self : any) : Engine.Entity
					return selectedEntityRef and selectedEntityRef:get() or -1
				end,
			}
			return base(refRC, proxy as ReactRefT<Engine.Entity>, allowStacking, filters, invertedSelectionColors)
		end
		log.message(LOG .. "shift hover: makeDefaultSelector wrapped")
	else
		log.message(LOG .. "shift hover: makeDefaultSelector not wrapped (missing or already done)")
	end
	-- The game context for Shift hover before any card was open: the map's default tool sets its action
	-- with makeDefaultSelectorCombinedFn{refRC, gameCtx} (view_manager.tl:56-58, a field lookup at call
	-- time) on push and on every unshelve.
	local combined = selector_react_util.makeDefaultSelectorCombinedFn
	if combined ~= nil and m.squarePaxDestCtx == nil then
		m.squarePaxDestCtx = true
		selector_react_util.makeDefaultSelectorCombinedFn = function(params : SelectorReactUtil.DefaultSelectorCompParams) : function() : TreeNodeId
			if lastGameCtx == nil and params ~= nil and params.gameCtx ~= nil then
				lastGameCtx = params.gameCtx
				log.message(LOG .. "game context from the map's default selector")
			end
			return combined(params)
		end
	end
end

---------------------------------------------------------------------------
-- The card, shared by the three plugins

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = str }
end

local function vbox(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end

local function hbox(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

local function checkBox(label : string, on : boolean, onChange : function(boolean), tooltip? : string) : TreeNodeId
	return builtin.CheckBox{
		meta = tooltip and { tooltip = tooltip } or nil,
		value = on and 1 or 0,
		label = label,
		onValueChange = function(value : integer) onChange(value == 1) end,
	}
end

--- Fixed-width gap between the checkboxes of a row (AAT's withGaps uses the same styled Component).
local function gap(width : integer) : TreeNodeId
	return builtin.Component{ meta = { styleSheet = styleutil.makeStyle{ size = { width, -1 } } } }
end

--- "Destinations: [] Show arrows" plus a card's extra items, in a FlowLayout, which wraps the items to the
--- window's width (base construction_desc_react_util.tl:970). Each item carries its trailing gap so a
--- wrapped row never starts with a spacer.
local function destinationsRow(on : boolean, toggle : function(boolean), extra? : {TreeNodeId}) : TreeNodeId
	local items : {TreeNodeId} = {
		hbox{ text(_("Destinations:"), "font-scale-body"), gap(8) },
		hbox{ checkBox(_("Show arrows"), on, toggle, _(SHOW_ARROWS_TOOLTIP)), gap(12) },   -- i18n: ignore
	}
	for __, item in ipairs(extra or {}) do items[#items + 1] = item end
	return builtin.FlowLayout{ children = items }
end

--- The summary under the row. header: "{n} ... going to:" (station / vehicle), nil for a person (note only).
local function summaryRows(snap : Snapshot, header : string, rows : {TreeNodeId})
	if snap == nil then
		rows[#rows + 1] = text(_("Reading..."), "font-scale-annotation")
		return
	end
	if header ~= nil then
		rows[#rows + 1] = text(lang_util.format(header, { n = tostring(snap.passengers) }), "font-scale-body")
		if snap.kinds ~= nil then rows[#rows + 1] = text(snap.kinds, "font-scale-annotation") end
		if snap.stops ~= nil then rows[#rows + 1] = text(snap.stops, "font-scale-annotation") end
		for __, r in ipairs(snap.rows) do
			rows[#rows + 1] = text(lang_util.format("-> {name}: {n}", { name = r.name, n = tostring(r.count) }), "font-scale-annotation")
		end
	end
	if snap.note ~= nil then rows[#rows + 1] = text(snap.note, "font-scale-annotation") end
	if snap.areas > snap.drawnAreas and snap.areas > 0 then
		rows[#rows + 1] = text(lang_util.format(_("{drawn} of {total} areas drawn"),
			{ drawn = tostring(snap.drawnAreas), total = tostring(snap.areas) }), "font-scale-annotation")
	end
end

local function card(gameCtx : GameContext, showOnRight : boolean, localKey : string, rows : {TreeNodeId}) : TreeNodeId
	-- a plugin's root must be a layout (memory "Recipe must return layout"); card shape as base
	-- sim_person_eow.script.tl:476-495 and AAT's line plugin; no title (content_card.tl:231 skips it)
	-- No card where this platform's content_card has no ContentCard, rather than a UI reload (PS5 report
	-- 2026-10-19, Smart Lanes; docs/findings/gui.md "Base GUI modules differ by platform").
	local ccCard = (content_card as {string : any}).ContentCard
	if not ccCard is function then
		return builtin.BoxLayout{ children = {} }
	end
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			meta = { localKey = localKey },
			extraChildrenPermanent = { vbox(rows) },
			gameCtx = gameCtx,
			showOnRightSide = showOnRight,
		},
	}
end

--- Per plugin instance: the state the timers and the tool action read.
local record Box
	on : boolean
	entity : integer
	snap : Snapshot       -- latest computed snapshot (nil while off); the tool action draws it
	compute : function() : Snapshot   -- the card's scan, replaced on every render
end

--- Same card text (everything summaryRows shows; arrows ignored). The card's state compares with this,
--- so a moving vehicle (new arrow origin every refresh) doesn't re-render the card; the tool action
--- reads the arrows from Box.snap.
local function sameSummary(a : Snapshot, b : Snapshot) : boolean
	if a == b then return true end
	if a == nil or b == nil then return false end
	if a.passengers ~= b.passengers or a.areas ~= b.areas or a.drawnAreas ~= b.drawnAreas or a.note ~= b.note
		or a.kinds ~= b.kinds or a.stops ~= b.stops or #a.rows ~= #b.rows then
		return false
	end
	for i, r in ipairs(a.rows) do
		if r.name ~= b.rows[i].name or r.count ~= b.rows[i].count then return false end
	end
	return true
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
local function useLifecycle(gameCtx : GameContext, owner : integer, entity : integer, box : Box, onLost : function())
	if gameCtx ~= nil then lastGameCtx = gameCtx end
	react.onMount(function() noteWindow(entity, 1) end)
	react.onUnmount(function()
		noteWindow(entity, -1)
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

local record Destinations
	on : boolean
	snap : Snapshot
	toggle : function(boolean)
	refresh : function()  -- recompute now (after a filter change)
end

--- The whole "Show arrows" behaviour of a card: push / pop of the tool, the REFRESH_S scan, lifecycle.
--- compute: the card's scan (worker thread in polls); windowIds: the windows to re-show after a push.
local function useDestinations(gameCtx : GameContext, entity : integer, windowIds : function() : {string}, compute : function() : Snapshot) : Destinations
	local owner = useOwner()
	local boxRef : ReactRefT<Box> = react.useRefLazy(function() : Box return { on = false, entity = entity } end)
	local box = boxRef:get()
	box.compute = compute
	local onState : ReactStateT<boolean> = react.useState(false)
	local snapState = engine_react_util.useStepStateTimer(function() : Snapshot
		box.snap = box.on and safe(box.compute) or nil
		return box.snap
	end, REFRESH_S, sameSummary)

	local function turnedOff()
		box.on, box.snap = false, nil
		if not onState:hasExpired() then onState:set(false) end
		if not snapState:hasExpired() then snapState:set(nil) end
	end
	useLifecycle(gameCtx, owner, entity, box, turnedOff)

	local function refresh()
		box.snap = box.on and safe(box.compute) or nil
		snapState:set(box.snap)
	end

	local function toggle(on : boolean)
		if on and not isActive(owner) then
			box.on, box.entity = true, entity
			if not pushTool(gameCtx, owner, entity, windowIds(), function() : Snapshot return box.snap end) then
				box.on, on = false, false
			end
		elseif not on and box.on then
			box.on = false
			popIfOwner(owner, "untoggled")
		end
		onState:set(on)
		refresh()
	end

	return { on = box.on, snap = snapState:old(), toggle = toggle, refresh = refresh }
end

---------------------------------------------------------------------------
-- Station window plugin

local function copySet(s : {string : boolean}) : {string : boolean}
	local out : {string : boolean} = {}
	for k, v in pairs(s) do if v then out[k] = true end end
	return out
end

-- SQPERF section "station_render" (GUI thread)
local PaxDestStationPlugin = react.RegisterPluginRecipe(station_group_eow.StationGroupEowExtensionPoint, "PaxDestStationPlugin", perf:wrap("station_render", function(p : StationGroupEow.StationGroupWidgetPluginParams) : TreeNodeId
	local group = p.entityId as integer
	-- terminals switched off in the filter (all on by default, so new terminals count right away)
	local excludedRef : ReactRefT<{string : boolean}> = react.useRefLazy(function() : {string : boolean} return {} end)
	local excludedState : ReactStateT<{string : boolean}> = react.useState({})
	local terminals = engine_react_util.useStepStateTimer(function() : {PaxTerminal}
		local ok, list = pcall(readTerminals, group)
		return ok and list as {PaxTerminal} or {}
	end, TERMINALS_S)
	local dest = useDestinations(p.gameCtx, group, function() : {string}
		local ids = { windowIdOf(group) }
		local sg = comp(group, api.type.ComponentType.STATION_GROUP) as Engine.Component.StationGroup
		for __, station in ipairs(sg and sg.stations or {}) do
			-- a station inside a construction may be shown in the construction's window
			local ok, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, station)
			if ok and con and (con as integer) >= 0 then ids[#ids + 1] = windowIdOf(con as integer) end
		end
		return ids
	end, function() : Snapshot return computeStation(group, excludedRef:get()) end)

	local list = terminals:old() or {}
	if #list == 0 then
		return builtin.BoxLayout{ children = {} }  -- no passenger lines here: no card
	end

	-- terminal filter, only where there is a choice (numbered like the base window)
	local extra : {TreeNodeId} = {}
	if #list > 1 then
		local excluded = excludedState:old()
		extra[1] = hbox{ text(_("Terminals:"), "font-scale-body"), gap(6) }
		for __, t in ipairs(list) do
			extra[#extra + 1] = hbox{ checkBox(tostring(t.display), not excluded[t.key], function(on : boolean)
				local s = copySet(excludedRef:get())
				s[t.key] = (not on) or nil
				excludedRef:set(s)
				excludedState:set(s)
				dest.refresh()
			end, lang_util.format(_("Terminal {n}"), { n = tostring(t.display) })), gap(6) }
		end
	end

	local rows : {TreeNodeId} = { destinationsRow(dest.on, dest.toggle, extra) }
	if dest.on then summaryRows(dest.snap, _("{n} waiting passengers, going to:"), rows) end
	return card(p.gameCtx, p.showCalloutOnRightSide, "paxDestStation", rows)
end))

---------------------------------------------------------------------------
-- Vehicle window plugin

-- SQPERF section "vehicle_render" (GUI thread)
local PaxDestVehiclePlugin = react.RegisterPluginRecipe(vehicle_eow.VehicleEowExtensionPoint, "PaxDestVehiclePlugin", perf:wrap("vehicle_render", function(p : VehicleEow.VehicleWidgetPluginParams) : TreeNodeId
	local vehicle = p.entityId as integer
	local cacheRef : ReactRefT<OnBoard> = react.useRefLazy(function() : OnBoard return { people = nil, count = -1, time = 0 } end)
	local cache = cacheRef:get()
	local dest = useDestinations(p.gameCtx, vehicle, function() : {string} return { windowIdOf(vehicle) } end,
		function() : Snapshot return computeVehicle(vehicle, cache) end)

	-- freight-only vehicles: no card (the window's static info, vehicle.tl:200-206; nil until it is read)
	local info = p.state ~= nil and p.state.staticVehicleInfo or nil
	if info ~= nil and not info.canTransportPassengers then
		return builtin.BoxLayout{ children = {} }
	end

	local rows : {TreeNodeId} = { destinationsRow(dest.on, dest.toggle) }
	if dest.on then summaryRows(dest.snap, _("{n} passengers on board, going to:"), rows) end
	return card(p.gameCtx, p.showCalloutOnRightSide, "paxDestVehicle", rows)
end))

---------------------------------------------------------------------------
-- Person window plugin

-- SQPERF section "person_render" (GUI thread)
local PaxDestPersonPlugin = react.RegisterPluginRecipe(sim_person_eow.SimPersonEowExtensionPoint, "PaxDestPersonPlugin", perf:wrap("person_render", function(p : SimPersonEow.SimPersonWidgetPluginParams) : TreeNodeId
	local person = p.entityId as integer
	-- the Locations pins of this window draw person -> building on hover (openPersons)
	react.onMount(function() notePerson(person, 1) end)
	react.onUnmount(function() notePerson(person, -1) end)
	local dest = useDestinations(p.gameCtx, person, function() : {string} return { windowIdOf(person) } end,
		function() : Snapshot return computePerson(person) end)

	local rows : {TreeNodeId} = { destinationsRow(dest.on, dest.toggle) }
	if dest.on then summaryRows(dest.snap, nil, rows) end
	return card(p.gameCtx, p.showCalloutOnRightSide, "paxDestPerson", rows)
end))

---------------------------------------------------------------------------
-- Entry point (::ModEntryPointExtension, base game.tl:73-93: an invisible root mounted with the game UI,
-- right after the ToolStack). It loads this module at game start, so the LocateButton and
-- makeDefaultSelector wrappers are in place before the first hover (they used to wait for the first
-- station / vehicle / person window). Its onStep (main thread) also:
--   * starts Shift hover when Shift is pressed while the mouse already rests on something;
--   * pops the Shift entry once another tool is on top of it (the line manager after a Shift-click, ...).
--     Only after our action's poll has run once (shiftOnTop): never in the steps between our push and
--     our tool becoming the top;
--   * diagnostics: logs once when arrows should be on but our tool is not on top (a game test lost every
--     arrow until a pause-menu round trip, 2026-10-11).

local function topToolName() : string
	local tsApi = toolStackApiOf(lastGameCtx)
	if tsApi == nil or tsApi.getActiveTool == nil then return nil end
	local ok, tool = pcall(tsApi.getActiveTool)
	local def = ok and tool as {string : any} or nil
	return def ~= nil and def.name as string or nil
end

local PaxDestEntry = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "PaxDestEntry", function() : TreeNodeId
	local heldRef : ReactRefT<boolean> = react.useRef(false)
	local diagRef : ReactRefT<string> = react.useRef("")
	react.onStep(function()
		local held = shiftHeld()
		if held and not heldRef:get() and shiftRaw == nil and mapHover ~= nil and mapHover >= 0 then
			onMapHover(mapHover)   -- Shift pressed while the mouse already rests on something
		end
		heldRef:set(held)
		if shiftRaw ~= nil and shiftOnTop then
			local top = topToolName()
			if top ~= TOOL_NAME then
				react.enqueueJoin(function()
					if shiftRaw ~= nil and shiftOnTop and topToolName() ~= TOOL_NAME then
						shiftHide("another tool on top: " .. tostring(top))
					end
				end, "PaxDestShiftCovered")
			end
		end
		local expect = (active ~= nil and active.owner) or (hover ~= nil and HOVER_OWNER) or nil
		local diag = ""
		if expect ~= nil then
			local top = topToolName()
			if top ~= TOOL_NAME then diag = "owner " .. tostring(expect) .. " expects our tool on top, top is " .. tostring(top) end
		end
		if diag ~= diagRef:get() then
			diagRef:set(diag)
			if diag ~= "" then log.message(LOG .. "diag: " .. diag) end
		end
	end)
	return builtin.BoxLayout{ children = {} }
end)

local result = {
	PaxDestStationPlugin = PaxDestStationPlugin,
	PaxDestPersonPlugin = PaxDestPersonPlugin,
	PaxDestVehiclePlugin = PaxDestVehiclePlugin,
	PaxDestEntry = PaxDestEntry,
}

perf:phase("init", perfInit)

return result
