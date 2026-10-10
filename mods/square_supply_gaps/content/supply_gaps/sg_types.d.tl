require "supply_gaps.sg_types"
recordDef = true

-- Supply Gaps shared contract: the plain records the engine reads (sg_gather.tl) produce, the
-- catchment scheduler (sg_cache.tl) keeps, and the pure model (sg_model.tl) turns into gaps.
-- Loaded as module "supply_gaps.sg_types" (every content/**/*.d.tl; tools/tealrt.py def_modules).
-- tealdef/supply_gaps/sg_types.d.tl is a byte-for-byte editor copy (make check flags drift). Never
-- `require` this module from a .tl/.lua file: the types come in via
-- tealdef/square_supply_gaps_def.d.tl. Every global name is prefixed SupplyGaps (globals are shared
-- by all loaded mods). Plain numbers, strings and tables only (no engine userdata).
-- Land use index: LandUseType + 1 (1 residential, 2 commercial, 3 industrial; 0 unknown), as
-- .cache/game/base/content/game_mechanics/towns/town_util.tl:13-15.

--- One town building, read by sg_gather.readBuilding (TOWN_BUILDING + STOCK_LIST + PERSON_CAPACITY).
global record SupplyGapsBuilding
	entity : integer          -- the TOWN_BUILDING entity
	town : integer            -- TownBuilding.town
	landUse : integer         -- PERSON_CAPACITY.type + 1 (0 unknown)
	needs : {integer}         -- cargos with an InputStock, passengers skipped, ascending, unique
	stockList : integer       -- TownBuilding.stockList (-1 / nil if none)
	pos : {number}            -- {x, y, z}: bounding-box centre; nil without BOUNDING_VOLUME
	stock : {integer : integer}      -- need -> units in its input stock(s) at the last read
	                                 -- (simEntityAtStockSystem.getStockCount); no key = read failed
	zeroReads : {integer : integer}  -- need -> consecutive reads with stock 0 (model.zeroStreak)
end

--- One stop of a line, as needed for "delivers".
global record SupplyGapsStop
	stationGroup : integer
	unload : boolean          -- the stop's terminal unloads cargo (Terminal.cargoUnload ~= false;
	                          -- unknown terminal = true)
end

--- One LINE, read by sg_gather.lines.
global record SupplyGapsLine
	entity : integer
	carries : {integer}       -- cargos with stopConfig.load true at any stop (passengers kept here;
	                          -- the model drops them), ascending, unique
	stops : {SupplyGapsStop}
end

--- Everything the model needs for one tick. All maps are keyed by entity id.
global record SupplyGapsWorld
	buildings : {integer : SupplyGapsBuilding}
	groupCargo : {integer : {integer : boolean}}   -- delivering group -> cargo set; the key
	                                               -- SupplyGapsModel.ANY means "every cargo"
	groupStations : {integer : {integer}}          -- group -> its station entities
	catchables : {integer : {integer}}             -- station -> getStationCatchables(station, true)
	includeStarved : boolean                       -- starved buildings count as gaps (marker + gapList)
	starvedReads : integer                         -- zero reads before "starved" (nil = STARVED_READS)
	order : {integer}                              -- optional: sorted building ids (else sortedKeys)
end

--- Per-cargo counts of one area (Phase 2c): buildings needing the cargo / covered (reached and,
--- while includeStarved is on, not starved).
global record SupplyGapsAreaCargo
	needed : integer
	covered : integer
end

--- One area = one town district: town x land use (the engine's district, Gui.SelectionDetails.Town
--- {townEntity, districtType}; TOWN.cargoNeeds per district). Built by model.compute.
global record SupplyGapsArea
	key : integer             -- model.areaKey(town, landUse)
	town : integer
	landUse : integer         -- 1 residential, 2 commercial, 3 industrial
	cargos : {integer : SupplyGapsAreaCargo}
	x : number                -- centroid of the area's positioned buildings (nil if none)
	y : number
	positioned : integer      -- buildings that contributed to the centroid
end

--- One "[icon] 73%" chip of an area label.
global record SupplyGapsChip
	cargo : integer
	pct : integer             -- floor(covered * 100 / needed)
	needed : integer
	covered : integer
	tone : string             -- LabelFontColor: "Normal" (>= 90), "Inferior" (>= 50), "Poor"
end

--- One area label (sg_areas.labels): the areas nearest the camera, cap MAX_LABELS.
global record SupplyGapsAreaLabel
	key : integer
	town : integer
	landUse : integer
	chips : {SupplyGapsChip}
	dist : number             -- squared distance of the centroid to the camera (math.huge: no position)
	x : number                -- areas.candidates only: the area centroid (nil if none)
	y : number
end

--- Pure area-label planner (sg_areas.tl), unit-tested.
global record SupplyGapsAreas
	MAX_LABELS : integer
	WORST : integer
	--- floor(covered * 100 / needed), 0 for needed <= 0.
	pct : function(covered : integer, needed : integer) : integer
	--- "Normal" | "Inferior" | "Poor" for a percentage.
	tone : function(pct : integer) : string
	--- Chips of one area: the selected cargo, or ("All needed", selection nil) the worst `worst`
	--- cargos below 100 % (lowest % first, then more buildings, then cargo id); an area with every
	--- cargo at 100 % gets one chip (its most-needed cargo). Empty when the area doesn't need it.
	chips : function(area : SupplyGapsArea, selection : integer, worst : integer) : {SupplyGapsChip}
	--- Every area with chips (no distance; x / y = centroid): camera-independent part of labels.
	candidates : function(areas : {integer : SupplyGapsArea}, selection : integer, worst : integer) : {SupplyGapsAreaLabel}
	--- The `cap` candidates nearest the camera (distance, then key).
	nearest : function(candidates : {SupplyGapsAreaLabel}, camera : SupplyGapsCamera, cap : integer) : {SupplyGapsAreaLabel}
	--- Labels for the `cap` areas nearest the camera that have chips (distance, then key).
	labels : function(areas : {integer : SupplyGapsArea}, selection : integer, camera : SupplyGapsCamera, cap : integer, worst : integer) : {SupplyGapsAreaLabel}
end

--- One chip as the HUD draws it (plain data; the HUD thread does no engine or res reads).
global record SupplyGapsLabelChip
	icon : string
	text : string             -- "73%"
	tone : string
	cargo : integer
end

--- One area row as the HUD draws it.
global record SupplyGapsLabelRow
	landUse : integer
	chips : {SupplyGapsLabelChip}
end

--- What the HUD wrappers read (overlay.labelStore). Replaced as a whole every tick, never mutated.
global record SupplyGapsLabelStore
	byTown : {integer : {SupplyGapsLabelRow}}   -- town -> rows, landUse ascending
	shown : integer                             -- labels (areas) in the store
	areas : integer                             -- areas with a need (before the cap)
end

--- Per-cargo counts (buildings needing / reached / reached but starved; starved <= reached).
global record SupplyGapsCount
	needed : integer
	reached : integer
	starved : integer
end

global record SupplyGapsCargoCount
	needed : integer
	reached : integer
	starved : integer
	towns : {integer : SupplyGapsCount}
end

--- One compute() result.
global record SupplyGapsView
	cargos : {integer : SupplyGapsCargoCount}
	gaps : {integer : {integer}}   -- gap building -> its unreached needs (ascending, may be empty
	                               -- for a starved-only gap)
	starved : {integer : {integer}} -- gap building -> its reached-but-starved needs (ascending)
	kind : {integer : string}      -- gap building -> model.UNREACHED | model.STARVED (unreached wins)
	gapList : {integer}            -- gap buildings, ascending
	total : integer                -- #gapList
	unreachedTotal : integer       -- gaps of kind UNREACHED
	starvedTotal : integer         -- gaps of kind STARVED (0 when includeStarved is off)
	buildings : integer            -- buildings with at least one need
	areas : {integer : SupplyGapsArea}  -- area key -> counts (Phase 2c; landUse 0 skipped)
end

--- {x, y} of the camera centre (api.gui.camera.getCameraData() [1], [2]).
global type SupplyGapsCamera = {number}

--- 2D box {minX, minY, maxX, maxY} on the ground (Phase 2d: building / town extent).
global type SupplyGapsBox = {number}

--- One camera read for "Only towns in view" (sg_overlay.readCamera, GUI thread).
global record SupplyGapsCameraView
	cx : number
	cy : number
	distance : number         -- getCameraData distance (z)
	poly : {number}           -- ground footprint x1, y1, ..., x4, y4 (screen corners, clockwise from top left)
	hits : integer            -- corners whose ray hit the ground plane (the rest are capped)
	fallback : boolean        -- true: the projection failed, poly is a square of +- distance
end

--- Hysteresis state of the in-view selection.
global record SupplyGapsScopeState
	inView : {integer : boolean}   -- towns in view after the last select
	lastIn : {integer : integer}   -- town -> last tick its box overlapped the footprint
end

--- "Only towns in view" (sg_scope.tl, pure, Phase 2d).
global record SupplyGapsScope
	CAP_FACTOR : number       -- footprint corners at most this x camera distance from the centre
	MIN_DIST : number         -- floor for the camera distance
	EXIT_FACTOR : number      -- exit margin = max(EXIT_FACTOR x distance, EXIT_MIN)
	EXIT_MIN : number
	HOLD_TICKS : integer      -- a town stays in view this many ticks after its last overlap
	NAMES_SHOWN : integer
	newState : function() : SupplyGapsScopeState
	--- Ray n -> f meets the plane z = planeZ, capped at maxDist from (cx, cy): x, y, hit.
	groundPoint : function(nx : number, ny : number, nz : number, fx : number, fy : number, fz : number, planeZ : number, cx : number, cy : number, maxDist : number) : number, number, boolean
	--- Footprint polygon from corner rays {{p0}, {p1}} (screen2World at depth 0 / 1, {x, y, z} each,
	--- either may be nil); ordered by distance to `eye`. Returns the polygon and the number of hits.
	footprint : function(rays : {{{number}}}, eye : {number}, planeZ : number, cx : number, cy : number, maxDist : number) : {number}, integer
	--- Square polygon of +- half around (cx, cy).
	square : function(cx : number, cy : number, half : number) : {number}
	--- Convex polygon vs box grown by `margin` (separating axes).
	intersects : function(poly : {number}, box : SupplyGapsBox, margin : number) : boolean
	--- Town -> union of its buildings' boxes (ids / townOf as gather.flatten; boxes may lack ids).
	townBoxes : function(ids : {integer}, townOf : {integer}, boxes : {integer : SupplyGapsBox}) : {integer : SupplyGapsBox}
	--- Towns in view with hysteresis (updates `state`); second result: the set changed.
	select : function(townBoxes : {integer : SupplyGapsBox}, cam : SupplyGapsCameraView, state : SupplyGapsScopeState, tick : integer) : {integer : boolean}, boolean
	--- Town ids sorted by box-centre distance to (cx, cy), then id.
	byDistance : function(towns : {integer : boolean}, townBoxes : {integer : SupplyGapsBox}, cx : number, cy : number) : {integer}
	--- "A, B, C +2": the first `shown` names, then "+N".
	namesText : function(names : {string}, shown : integer) : string
end

--- Marker change set.
global record SupplyGapsDiff
	add : {integer}           -- ascending
	remove : {integer}        -- ascending
end

--- Pure model (sg_model.tl): no api.*, unit-tested in tests/square_supply_gaps/.
global record SupplyGapsModel
	ANY : integer
	MAX_MARKERS : integer
	UNREACHED : string
	STARVED : string
	--- Consecutive zero-stock reads before a reached need counts as starved (anti-flicker).
	STARVED_READS : integer
	--- Next zero-read streak: count 0 -> prev + 1 (capped), count > 0 -> 0, count nil -> prev.
	zeroStreak : function(prev : integer, count : integer) : integer
	--- Group -> cargo set of the groups that deliver it: a line carrying c (stopConfig.load, minus
	--- passengers) delivers c at each of its stops with unload ~= false.
	deliveringGroups : function(lines : {SupplyGapsLine}, passenger : integer) : {integer : {integer : boolean}}
	--- "Count stops without a line": every listed group also delivers ANY (returns groupCargo).
	addUnlinedGroups : function(groupCargo : {integer : {integer : boolean}}, unloadGroups : {integer}) : {integer : {integer : boolean}}
	--- Gaps for one selection: nil = "All needed" (any need unreached / starved), else that cargo.
	compute : function(world : SupplyGapsWorld, selection : integer) : SupplyGapsView
	--- The `cap` gap buildings nearest the camera (ascending distance, then entity); no position = last.
	markerPlan : function(gapList : {integer}, buildings : {integer : SupplyGapsBuilding}, camera : SupplyGapsCamera, cap : integer) : {integer}
	--- What to add / remove to go from the `prev` set to the `next` list.
	diff : function(prev : {integer : boolean}, next : {integer}) : SupplyGapsDiff
	--- Same compute() inputs from two reads of one building (town, land use, needs, position, starved
	--- flag per need); stock counts and short zero streaks are ignored.
	sameBuilding : function(a : SupplyGapsBuilding, b : SupplyGapsBuilding, starvedReads? : integer) : boolean
	--- Sorted keys of an integer-keyed table.
	sortedKeys : function(t : {integer : any}) : {integer}
	--- Area key of a town district: town * 4 + landUse.
	areaKey : function(town : integer, landUse : integer) : integer
	--- Sorted ids of the buildings whose town is in `towns` (nil = every building). Phase 2d: the
	--- order passed to compute, so counts, gaps, markers and areas cover only these towns.
	scopeOrder : function(buildings : {integer : SupplyGapsBuilding}, towns : {integer : boolean}) : {integer}
end

--- One catchment cache entry.
global record SupplyGapsCatchEntry
	list : {integer}
	tick : integer            -- tick of the last fetch
end

--- Stats of one cache.step.
global record SupplyGapsStepStats
	new : integer             -- stations fetched because they were not cached
	refreshed : integer       -- round-robin refreshes
	dropped : integer         -- entries removed (station no longer wanted)
	errors : integer          -- fetches that raised (old list kept, [] when new)
	catchables : integer      -- total cached catchables after the step
	changed : integer         -- entries added, dropped or with a different list (0 = same catchables)
end

--- Catchment scheduler state (GUI memory only).
global record SupplyGapsCatchCache
	entries : {integer : SupplyGapsCatchEntry}
	tick : integer
	cursor : integer          -- last station refreshed round robin (next starts after it)
	perTick : integer         -- current STATIONS_PER_TICK (halved over budget)
	bCursor : integer         -- index into the building id list of the last round-robin read
	perfTicks : integer       -- ticks since the last PERF line
	perfMax : number
	perfSum : number
end

global type SupplyGapsFetchFn = function(station : integer) : {integer}

--- Catchment scheduler (sg_cache.tl): pure apart from engineFetch.
global record SupplyGapsCache
	STATIONS_PER_TICK : integer
	MIN_STATIONS_PER_TICK : integer
	BUILDING_EVERY : integer
	BUDGET_MS : number
	PERF_EVERY : integer
	new : function() : SupplyGapsCatchCache
	STATION_CYCLE : integer
	--- One tick: drop unwanted stations, fetch uncached ones, refresh perTick others round robin
	--- (at most `cap` when given). `stations` = the stations of the delivering groups (any order,
	--- duplicates ok).
	step : function(c : SupplyGapsCatchCache, stations : {integer}, fetch : SupplyGapsFetchFn, cap? : integer) : SupplyGapsStepStats
	--- Round-robin cap for n stations: ceil(n / STATION_CYCLE), at least MIN_STATIONS_PER_TICK.
	refreshCap : function(n : integer) : integer
	--- station -> catchables, for SupplyGapsWorld.catchables.
	catchables : function(c : SupplyGapsCatchCache) : {integer : {integer}}
	--- Indices into `ids` to read this tick: every id not in `known` or in `due` (urgent; at most
	--- `maxUrgent` of them in index order when given, the rest wait for later ticks), plus
	--- ceil(#ids / BUILDING_EVERY) others round robin (each building re-read every BUILDING_EVERY
	--- ticks), ascending.
	buildingStep : function(c : SupplyGapsCatchCache, ids : {integer}, known : {integer : boolean}, due? : {integer : boolean}, maxUrgent? : integer) : {integer}
	--- Record a tick's time; over BUDGET_MS halves perTick (min MIN_STATIONS_PER_TICK). True if halved.
	noteTime : function(c : SupplyGapsCatchCache, ms : number) : boolean
	--- Every PERF_EVERY noted ticks: {max, avg} ms since the last report (and resets), else nil.
	perf : function(c : SupplyGapsCatchCache) : {number}
	--- getStationCatchables(station, true) as a plain list.
	engineFetch : SupplyGapsFetchFn
end

--- Line cache for gather.lines (perf review 2026-10-09): GUI memory only.
global record SupplyGapsLineCache
	lines : {integer : SupplyGapsLine}  -- line -> last read (nil: not cached / failed)
	sig : {integer : string}            -- line -> its (group:stopIndex) set in the stop map at that read
	cursor : integer                    -- last line re-read round robin
	list : {SupplyGapsLine}             -- the last returned list (returned again when nothing changed)
end

--- Engine reads (sg_gather.tl), GUI thread, read-only. Each entity read is in pcall; a failing
--- entity is skipped and counted (gather.errors, first 20 logged as ERR).
global record SupplyGapsGather
	errors : integer
	MAX_ERR_LOGS : integer
	--- api.res.cargoTypeRep.getPassengerCargoTypeId().
	passengerCargo : function() : integer
	LINE_EVERY : integer
	--- Every line with a stop (lineSystem.getStationGroup2LineStopsMap). Without a cache one LINE read
	--- each; with one, only new lines, lines whose stop set changed and ceil(n / LINE_EVERY) others
	--- round robin. Second result: the list changed since the last call (true without a cache).
	lines : function(lc? : SupplyGapsLineCache) : {SupplyGapsLine}, boolean
	newLineCache : function() : SupplyGapsLineCache
	--- Station groups with a cargo-unloading terminal (for "Count stops without a line").
	unloadGroups : function() : {integer}
	--- group -> its stations (STATION_GROUP.stations, -1 entries skipped).
	groupStations : function(groups : {integer}) : {integer : {integer}}
	--- Total town buildings in getTown2BuildingMap, and the map.
	buildingMap : function() : integer, {integer : {integer}}
	--- Flat building id list (towns ascending, engine order inside a town) and the town of each; third
	--- result false when it equals prevIds / prevTownOf (then those tables are returned).
	flatten : function(map : {integer : {integer}}, prevIds? : {integer}, prevTownOf? : {integer}) : {integer}, {integer}, boolean
	--- One town building (nil without TOWN_BUILDING) and whether the read succeeded. `prev` (may be
	--- nil) supplies the position and the zero-read streaks.
	readBuilding : function(b : integer, town : integer, prev : SupplyGapsBuilding, passenger : integer) : SupplyGapsBuilding, boolean
	--- 2D BOUNDING_VOLUME box of an entity (nil without one); errors raise (caller pcalls).
	buildingBox : function(b : integer) : SupplyGapsBox
	--- NAME of a town ("" if none; errors raise).
	townName : function(t : integer) : string
end

--- Result of one markers.apply / clearAll.
global record SupplyGapsMarkerStats
	added : integer
	removed : integer
	errors : integer
	shown : integer           -- markers up after the call
	retyped : integer         -- markers re-set because their kind changed
end

--- Mission-marker lifecycle (sg_markers.tl, PLAN "Rendering, track A"). GUI thread only. Every engine
--- call is in pcall; keys are KEY_PREFIX .. entity, so only our own markers are ever removed.
global record SupplyGapsMarkers
	KEY_PREFIX : string
	TYPE : string             -- marker type of unreached gaps ("arrow")
	TYPE_STARVED : string     -- marker type of starved gaps ("exclamation")
	SCALE : number
	shown : {integer : boolean}        -- entities with a marker up
	typeOf : {integer : string}        -- entity -> marker type it was set with
	--- Show markers for exactly `next` (diff against what is up). `kinds` (may be nil) picks the
	--- type per entity (model.STARVED -> TYPE_STARVED, else TYPE); a changed type re-sets the marker.
	apply : function(next : {integer}, kinds? : {integer : string}) : SupplyGapsMarkerStats
	--- Remove every marker of ours.
	clearAll : function() : SupplyGapsMarkerStats
	--- Forget every marker WITHOUT engine calls (plugin unmount: the world may be going away; mission
	--- markers are GUI-only and die with it).
	forget : function() : integer
end

--- One cargo row of the window snapshot.
global record SupplyGapsCargoRow
	cargo : integer
	name : string
	needed : integer
	reached : integer
	starved : integer
end

--- What the window shows (plain data; compared with deepEquals by useStepStateTimer).
global record SupplyGapsSnapshot
	on : boolean
	unlined : boolean
	selection : integer       -- nil = "All needed"
	ticks : integer
	gaps : integer
	unreached : integer       -- gap buildings of kind unreached
	starved : integer         -- gap buildings of kind starved (0 when hidden)
	includeStarved : boolean
	buildings : integer       -- buildings with needs
	markers : integer
	capped : boolean
	rows : {SupplyGapsCargoRow}
	labels : boolean          -- "Area labels" (Phase 2c)
	labelsShown : integer     -- areas in the label store
	scoped : boolean          -- "Only towns in view" (Phase 2d)
	viewTowns : integer       -- towns in scope (in view, or every town with buildings when not scoped)
	viewText : string         -- "Rockledge, Columbus, Avon +2" (scoped) or "" ; nearest first
	pending : integer         -- buildings of towns in scope not read yet
end

--- Session state (GUI memory; nothing saved).
global record SupplyGapsSession
	on : boolean
	unlined : boolean         -- "Count stops without a line"
	starved : boolean         -- "Include in-range but empty" (default on)
	selection : integer
	labels : boolean          -- "Area labels" (default on): per-district coverage chips in the HUD
	scoped : boolean          -- "Only towns in view" (default on, Phase 2d)
end

--- The overlay: session, tick pipeline (gather -> cache -> model -> markers -> area labels)
--- (sg_overlay.tl). GUI thread only.
global record SupplyGapsOverlay
	TICK : number
	--- `session.on` at game load (false; the saved per-save flag switches it on, sg_saved.tl);
	--- shutdown (plugin unmount = game unload) restores every default.
	DEFAULT_ON : boolean
	session : SupplyGapsSession
	cache : SupplyGapsCatchCache
	buildings : {integer : SupplyGapsBuilding}
	seen : {integer : boolean}  -- every building id read at least once (with or without needs)
	view : SupplyGapsView
	gapList : {integer}        -- view.gapList (nil while off)
	ticks : integer
	cargoNames : {integer : string}
	cargoIcons : {integer : string}
	--- Phase 2d: urgent building reads per tick (new ids, towns that just came into view).
	PRIORITY_PER_TICK : integer
	--- Perf review: building box reads per tick (the map-wide pass after load), and its time budget.
	BOX_PER_TICK : integer
	BOX_BUDGET_MS : number
	--- Perf review: building reads stop for this tick once the tick has run this long (at least
	--- READ_MIN reads first); unread urgent ids wait for the next tick.
	READ_BUDGET_MS : number
	READ_MIN : integer
	--- Perf review counters (tests, DEBUG PERF line): ticks that ran / skipped model.compute,
	--- marker plans, label rebuilds, box reads, building reads.
	counters : {string : integer}
	--- Camera + ground footprint (GUI thread; replaceable in tests).
	readCamera : function() : SupplyGapsCameraView
	boxes : {integer : SupplyGapsBox}   -- building -> 2D box ({} = none), read once per id
	townBoxes : {integer : SupplyGapsBox}
	scopeState : SupplyGapsScopeState
	scopeTowns : {integer : boolean}    -- towns counted this tick (nil before the first tick)
	ready : {integer : boolean}          -- towns whose buildings were all read once (sticky)
	due : {integer : boolean}            -- known buildings to re-read urgently (town came into view)
	townNames : {integer : string}
	viewText : string
	viewCount : integer
	pending : integer
	setScoped : function(on : boolean)
	--- Area label data the HUD wrappers read (sg_labels.lua); nil while off / labels off.
	labelStore : SupplyGapsLabelStore
	--- Switch the overlay on / off (off removes every marker at once).
	setOn : function(on : boolean)
	setUnlined : function(on : boolean)
	setStarved : function(on : boolean)
	setSelection : function(cargo : integer)
	setLabels : function(on : boolean)
	--- Pure-ish: label list -> HUD store (icon paths via `iconOf`).
	makeLabelStore : function(list : {SupplyGapsAreaLabel}, areas : integer, iconOf : function(integer) : string) : SupplyGapsLabelStore
	--- One tick (timer or the paused fallback). Does nothing while off. Never raises.
	tick : function(source : string)
	--- From onStepTimer.
	timerTick : function()
	--- From onStep (every frame): ticks from here while the game is paused and the timer is silent
	--- (unverified whether onStepTimer fires while paused). Cheap when nothing is due.
	stepCheck : function()
	--- Plugin unmount / map unload: markers forgotten (no engine calls), caches dropped, session
	--- back to its defaults (off; the saved flag is read again at the next load).
	shutdown : function()
	snapshot : function() : SupplyGapsSnapshot
	--- Clock in seconds: api.type.Clock (wall, microseconds) when available, else os.clock (process
	--- CPU time of all threads on macOS, so it overstates); replaceable in tests.
	clock : function() : number
	--- Wall seconds (os.time; replaceable in tests).
	now : function() : number
end

--- Per-save state of the game script (sg_state.script.tl, PLAN "Per-save state"). Absent state = off.
--- Written only by the "SupplyGaps.setOn" event, and only when `on` changes.
global record SupplyGapsSavedState
	v : integer   -- format version (sg_saved.VERSION)
	on : boolean  -- "Show supply gaps" was ticked
end

--- Load decision on the GUI side: read the saved flag once it is readable, then stop.
global record SupplyGapsSavedLoad
	done : boolean
	tries : integer
end

--- sg_saved.tl: pure state rules (engine script + GUI) and the GUI adapter (read / send).
global record SupplyGapsSaved
	VERSION : integer
	GS_NAME : string      -- game-script name for getEntityForGameScript
	EVENT_ID : string
	EV_SET_ON : string
	--- Reads before the load decision gives up (one per overlay tick, ~1 s each).
	LOAD_TRIES : integer
	--- Saved state (any shape) -> the flag; nil, non-tables and anything but `on == true` are off.
	isOn : function(raw : any) : boolean
	--- Validate an event param ({ on = boolean }) against the saved state: the new state, whether it
	--- changed (write only then), and a rejection text for an invalid param (state untouched).
	apply : function(raw : any, param : any) : SupplyGapsSavedState, boolean, string
	newLoad : function() : SupplyGapsSavedLoad
	--- One load attempt: `read` is the saved flag, or nil while the state is not readable yet.
	--- Returns "on" (switch the overlay on), "off" (stay off), "wait" (retry next tick) or "done"
	--- (already decided, or the player toggled first).
	loadStep : function(load : SupplyGapsSavedLoad, read : boolean) : string
	--- GUI thread: the saved flag, or nil when the game-script state is not readable (yet).
	readOn : function() : boolean
	--- GUI thread: send the flag to the game script (it saves only a change).
	sendOn : function(on : boolean)
end

--- HUD area labels (sg_labels.lua, plain Lua): wraps of base HUD recipes, installed once at load.
global record SupplyGapsLabels
	--- Wrap town_hud_react_util.TownHudIcon and layer_cargo_flow.HudIconMaster once (each in pcall).
	--- Returns a short status ("town=ok cargoflow=ok") for the INIT log line.
	install : function() : string
end

recordDef = false
