recordDef = true

-- Industry Production Label shared types (pure model + HUD recipe).
-- Loaded as module "production_label.production_label_types" (every content/**/*.d.tl;
-- tools/tealrt.py def_modules). tealdef/production_label/production_label_types.d.tl is a
-- byte-for-byte editor copy (make check flags drift).
-- Every global name is prefixed SquareProductionLabel (globals are shared by all loaded mods).

--- One output cargo of an industry: its capacity (the window's rounded `total`, > 0) and whether
--- it is producing right now (rounded live rate > 0). `pickup` is the summed line rate of the lines
--- loading this cargo in reach (rounded, > 0), nil when there is none (no pickup pill).
global record SquareProductionLabelEntry
	cargoType : integer
	value : integer
	producing : boolean
	pickup : integer
end

--- What the HUD recipe keeps in its useStepStateTimer state: small and plain, so the base
--- deepEquals (.cache/game/base/content/gui/main/engine_react_util.tl:126-157) is cheap.
global record SquareProductionLabelView
	entries : {SquareProductionLabelEntry}
end

--- Which pills to draw (mod settings, PLAN "Options"); all default to true. Read live by hudIconFn
--- from api.engine.config.getModParams() (PLAN "Settings read live (2026-10-07)").
global record SquareProductionLabelOptions
	showProduction : boolean
	showPickup : boolean
	showWarehouse : boolean
	--- "Show only while holding Shift": our pills only while Shift is held on the map.
	holdShift : boolean
end

--- One cargo of a warehouse label (PLAN "Warehouse rates (2026-10-07)"): per-year incoming
--- ("itemsUnloaded") and outgoing ("itemsLoaded") counts, rounded, >= 0, at least one of them > 0.
global record SquareProductionLabelWarehouseEntry
	cargoType : integer
	incoming : integer
	outgoing : integer
end

--- The warehouse recipe's useStepStateTimer state: busiest cargo first, at most MAX_WAREHOUSE_CARGOS.
global record SquareProductionLabelWarehouseView
	entries : {SquareProductionLabelWarehouseEntry}
end

--- How one entry is drawn. labelFontColor / shippingState are GuiReactUtil.LabelFontColor /
--- GuiReactUtil.ShippingState values (gui_react_util.tl:68-111); entryClass goes on our wrapper
--- BoxLayout (scoped CSS in production_label.css.lua).
global record SquareProductionLabelStyle
	labelFontColor : string
	shippingState : string
	entryClass : string
end

-- ======================================================================
-- from production_label_model.tl (pure: no api.*, no base modules)
-- Module: ug_require "square_industry_production_label::/production_label/production_label_model.tl" as SquareProductionLabelModel
global record SquareProductionLabelModel
	--- Text before the number; "" (the HUD font has no "▲", it rendered as "?").
	PREFIX : string
	--- Image that marks every pill as capacity (base building_industry icon).
	CAPACITY_ICON : string
	--- From this many entries on, each pill also shows its cargo icon.
	ICON_MIN_OUTPUTS : integer
	--- Style of an output that is producing (white text, green background from our CSS).
	STYLE_PRODUCING : SquareProductionLabelStyle
	--- Style of an idle output (white text, neutral dark background from our CSS).
	STYLE_IDLE : SquareProductionLabelStyle
	--- Image that marks every pickup-rate pill (base Line Manager icon).
	PICKUP_ICON : string
	--- Style of a pickup-rate pill (white text, neutral dark background like idle).
	STYLE_PICKUP : SquareProductionLabelStyle
	--- Round like the industry window (mathutil.round: floor(x + 0.5)); nil for a non-number,
	--- NaN, +-inf or a negative value.
	roundValue : function(v : any) : integer
	--- cargoData[cargoType].produceFrequency of a STOCK_LIST-like cargoData table, or nil.
	produceFrequency : function(cargoData : any, cargoType : integer) : any
	--- True when the live rate rounds to > 0. The rate is `actual` when it is a number, else
	--- `produceFrequency` (getIndustryProductionData has no `actual` for output-only rules).
	isProducing : function(actual : any, produceFrequency : any) : boolean
	--- Rounded pickup rate of one cargo from a {cargoTypeId : rate} table; nil unless it is > 0.
	pickupValue : function(pickupRates : any, cargoType : integer) : integer
	--- One entry from a getIndustryProductionData result ({cargoTypeId, actual, total}), the
	--- STOCK_LIST cargoData and the optional pickup rates; nil when malformed or the rounded
	--- capacity is not > 0.
	makeEntry : function(productionData : any, cargoData : any, pickupRates? : any) : SquareProductionLabelEntry
	--- Entries for a list of production datas, in order, one per cargo type (first wins);
	--- nil when there is nothing to show. Malformed input never errors.
	view : function(productionDatas : any, cargoData : any, pickupRates? : any) : SquareProductionLabelView
	--- The entries of a view that have a pickup rate, in order (fresh table; empty for nil).
	pickupEntries : function(view : SquareProductionLabelView) : {SquareProductionLabelEntry}
	--- True when no entry has a value > 0 or a pickup rate (nil view: true); the label is then empty.
	isUnused : function(view : SquareProductionLabelView) : boolean
	--- The view with each entry's pickup set from pickupRates (as model.view would); `view` itself
	--- (shared, never changed) when pickupRates is nil. model.view(pds, cd, rates) equals
	--- model.withPickup(model.view(pds, cd, nil), rates).
	withPickup : function(view : SquareProductionLabelView, pickupRates : any) : SquareProductionLabelView
	--- Options from the mod's own getModParams() entry ({showProduction, showPickup, showWarehouse, holdShift},
	--- 1-based value index): 2 = off, anything else (incl. a missing or malformed table) = on.
	--- Always a fresh table.
	options : function(modParams : any) : SquareProductionLabelOptions
	--- STYLE_PRODUCING or STYLE_IDLE.
	styleFor : function(producing : boolean) : SquareProductionLabelStyle
	--- Icons for one pill: {mainIcon or CAPACITY_ICON}, plus the cargo icon when
	--- entryCount >= ICON_MIN_OUTPUTS and the cargo icon is a non-empty string. Always a fresh table.
	iconPaths : function(cargoIconPath : string, entryCount : integer, mainIcon? : string) : {string}
	--- captureParams.kind of a warehouse label ("warehouse"), set by content/mod.script.lua.
	WAREHOUSE_KIND : string
	--- Direction icon of an incoming pill (base "Received": cargo box + down arrow).
	INCOMING_ICON : string
	--- Direction icon of an outgoing pill (base "Supplied": cargo box + up arrow).
	OUTGOING_ICON : string
	--- At most this many cargos per warehouse label (the busiest).
	MAX_WAREHOUSE_CARGOS : integer
	--- Style of an incoming pill (white text, chart "Positive" background from our CSS).
	STYLE_INCOMING : SquareProductionLabelStyle
	--- Style of an outgoing pill (white text, chart "Negative" background from our CSS).
	STYLE_OUTGOING : SquareProductionLabelStyle
	--- WAREHOUSE_KIND when captureParams.kind says so, else "industry" (also for nil / malformed).
	kind : function(captureParams : any) : string
	--- One warehouse entry from {cargoType, incoming, outgoing}: counts rounded, nil / malformed /
	--- negative counts are 0; nil when the cargo type is malformed or both counts are 0.
	warehouseEntry : function(raw : any) : SquareProductionLabelWarehouseEntry
	--- Entries from a list of raw {cargoType, incoming, outgoing}: one per cargo type (first wins),
	--- busiest (incoming + outgoing) first, ties by cargo type id, capped at MAX_WAREHOUSE_CARGOS;
	--- nil when nothing moved. Malformed input never errors.
	warehouseView : function(rates : any) : SquareProductionLabelWarehouseView
	--- {directionIcon, cargo icon}; the cargo icon only when it is a non-empty string. Fresh table.
	warehouseIconPaths : function(directionIcon : string, cargoIconPath : string) : {string}
	--- PREFIX .. formatted value; `formatInt` defaults to tostring (the game passes lang_util.formatInt).
	formatLabel : function(value : integer, formatInt? : function(integer) : string) : string
end

-- ======================================================================
-- from production_label_pickup.tl (shared pickup-rate cache; engine calls only in engineAdapter)
-- Module: ug_require "square_industry_production_label::/production_label/production_label_pickup.tl" as SquareProductionLabelPickup

--- One line stop as the aggregation needs it (from the LINE component, engine.d.tl Line.Stop).
--- station / terminal are 0-based like the component; load is a plain copy of stopConfig.load
--- (index = cargoTypeId + 1).
global record SquareProductionLabelPickupStop
	stationGroup : integer
	station : integer
	terminal : integer
	loadMode : integer
	load : {boolean}
end

--- Engine reads behind one rebuild (real one: SquareProductionLabelPickup.engineAdapter; stubbed in tests).
--- The aggregation memoises every call per rebuild.
global record SquareProductionLabelPickupAdapter
	--- getStationGroup2LineStopsMap(): station group -> {{line, stopIndex0}}.
	lineStopsMap : function() : {integer : {{integer, integer}}}
	--- The line's stops, nil when it has no LINE component.
	lineStops : function(line : integer) : {SquareProductionLabelPickupStop}
	--- calcLineStationThroughput(line).
	lineRate : function(line : integer) : number
	--- StockList entities in cargo reach of the station group (catchables + built-in fallback).
	reachableStockLists : function(stationGroup : integer) : {integer}
	--- Output cargo type ids of a StockList entity.
	outputCargoTypes : function(stockList : integer) : {integer}
	--- Terminal.cargoLoad of that stop's terminal; nil when unknown (not skipped).
	terminalCargoLoad : function(stationGroup : integer, station : integer, terminal : integer) : boolean
	--- Passenger cargo type id (ignored when deciding whether a stop loads cargo), may be nil.
	passengerCargoType : function() : integer
	--- Debug counter kept by the engine adapter: stations resolved by the construction fallback.
	fallbackStations : integer
end

--- Counts from one rebuild (debug log and tests).
global record SquareProductionLabelPickupStats
	stationGroups : integer
	lines : integer
	cargoStops : integer
	stockLists : integer
	stopIndexMismatches : integer
end

--- One station group of a rebuild: its entry of getStationGroup2LineStopsMap().
global record SquareProductionLabelPickupGroup
	stationGroup : integer
	lineStops : {{integer, integer}}
end

--- A rebuild in progress (pickup.newBuild / pickup.step): the scan position, the per-rebuild memos
--- and the partial result. Opaque outside the pickup module.
global record SquareProductionLabelPickupBuild
	adapter : SquareProductionLabelPickupAdapter
	stats : SquareProductionLabelPickupStats
	passenger : integer
	groups : {SquareProductionLabelPickupGroup}
	gi : integer
	stopsOf : {integer : {SquareProductionLabelPickupStop}}
	outputsOf : {integer : {integer}}
	producersOf : {integer : {{integer, integer}}}
	--- stockList -> cargo -> line -> set of the line's 1-based stop indices that load it in reach.
	served : {integer : {integer : {integer : {integer : boolean}}}}
	servedKeys : {integer}
	si : integer
	rateOf : {integer : number}
	result : {integer : {integer : integer}}
	done : boolean
end

--- The shared cache: stockList entity -> {cargoTypeId -> rounded rate > 0}.
global record SquareProductionLabelPickupCache
	rates : {integer : {integer : integer}}
	builtAt : number
	builtUpdateCount : integer
	building : boolean
	builds : integer
	errorLogged : boolean
	--- Sliced rebuild in progress (nil when none), its start and its last slice (pickup.nowMs ms).
	pending : SquareProductionLabelPickupBuild
	pendingStartMs : number
	sliceAtMs : number
end

global record SquareProductionLabelPickup
	--- Wall-clock seconds between rebuilds (os.time; getApplicationTime is GUI-thread only and crashes in HUD recipes).
	REFRESH_INTERVAL : number
	--- Engine.Component.Line.LoadMode.LEGACY_UNLOAD_ONLY as a number (declaration order, unverified).
	LEGACY_UNLOAD_ONLY : integer
	--- Sliced rebuilds: work per slice (ms), minimum time between slices (ms), and the age (ms) after
	--- which a pending rebuild finishes in its next slice.
	SLICE_BUDGET_MS : number
	SLICE_GAP_MS : number
	BUILD_MAX_MS : number
	--- Millisecond timer for the slices (set to the api.type.Clock timer by production_label.script.tl).
	nowMs : function() : number
	--- One-shot debug log of the first rebuild and the first label lookups.
	DEBUG : boolean
	--- Number of label lookups logged when DEBUG is on.
	DEBUG_LOOKUPS : integer
	--- The module-wide cache shared by every label.
	cache : SquareProductionLabelPickupCache
	--- SQPERF instrument (a SquareIndustryProductionLabelSqPerfInst; typed any because this file
	--- loads before the sqperf types) set by production_label.script.tl for section "pickup_rebuild".
	--- nil when unset (tests): no timing.
	perf : any
	--- A fresh, never-built cache.
	newCache : function() : SquareProductionLabelPickupCache
	--- Pure: stockList -> {cargo -> rate} from the adapter's reads, each line's rate times its
	--- pickup visits per (stockList, cargo), plus counts.
	aggregate : function(adapter : SquareProductionLabelPickupAdapter) : {integer : {integer : integer}}, SquareProductionLabelPickupStats
	--- Pickup visits per round trip: stops in the set whose previous stop (cyclic) is not in it; at least 1.
	visits : function(stopSet : {integer : boolean}, stopCount : integer) : integer
	--- A resumable rebuild: reads the line-stops map now; the rest happens in step.
	newBuild : function(adapter : SquareProductionLabelPickupAdapter) : SquareProductionLabelPickupBuild
	--- Continue a rebuild until done (true) or until overBudget() returns true after a unit of work
	--- (false). Without overBudget it runs to the end. The result equals aggregate's.
	step : function(build : SquareProductionLabelPickupBuild, overBudget? : function() : boolean) : boolean
	--- In-game driver: the first build at once (refresh), later ones sliced (one slice per
	--- SLICE_GAP_MS). Returns built (a rebuild completed: rates swapped), its stats, and whether
	--- any rebuild work ran in this call.
	tick : function(cache : SquareProductionLabelPickupCache, makeAdapter : function() : SquareProductionLabelPickupAdapter, now : number, getUpdateCount : function() : integer, nowMs : function() : number) : boolean, SquareProductionLabelPickupStats, boolean
	--- Whether a rebuild is due at `now`; getUpdateCount is only called once the interval passed.
	--- Paused (updateCount unchanged): not due, and the interval restarts at `now`.
	isStale : function(cache : SquareProductionLabelPickupCache, now : number, getUpdateCount : function() : integer) : boolean
	--- Rebuild when stale (pcall; the last good rates survive an error). True plus stats when it rebuilt.
	refresh : function(cache : SquareProductionLabelPickupCache, adapter : SquareProductionLabelPickupAdapter, now : number, getUpdateCount : function() : integer) : boolean, SquareProductionLabelPickupStats
	--- The engine-backed adapter (in game only).
	engineAdapter : function() : SquareProductionLabelPickupAdapter
	--- In game: {cargo -> rate} for a label's STOCK_LIST entity, refreshing the shared cache when
	--- stale. Never errors; nil when there is no pickup.
	ratesFor : function(entity : integer) : {integer : integer}
end

-- ======================================================================
-- from production_label_readcache.tl (per-entity read cache shared by every HUD label; pure)
-- Module: ug_require "square_industry_production_label::/production_label/production_label_readcache.tl" as SquareProductionLabelReadCache

global record SquareProductionLabelReadCacheEntry
	at : number
	value : any
end

--- One cache: entity -> its last read and when (ms).
global record SquareProductionLabelReadCacheInst
	entries : {integer : SquareProductionLabelReadCacheEntry}
	ttlMs : number
	sweptAt : number
end

global record SquareProductionLabelReadCache
	--- Max age (ms) of a cached read (below the labels' 2 s poll).
	TTL_MS : number
	--- Expired entries are dropped at most once per SWEEP_MS (ms).
	SWEEP_MS : number
	new : function(ttlMs? : number) : SquareProductionLabelReadCacheInst
	--- found, value (a cached nil counts as found) when the entry is younger than ttlMs at `now`.
	get : function(c : SquareProductionLabelReadCacheInst, key : integer, now : number) : boolean, any
	--- Store a read at `now`; true when the key was not cached before.
	put : function(c : SquareProductionLabelReadCacheInst, key : integer, now : number, value : any) : boolean
	--- The industry and warehouse caches of the HUD state.
	industry : SquareProductionLabelReadCacheInst
	warehouse : SquareProductionLabelReadCacheInst
	--- Fresh empty industry and warehouse caches (tests).
	reset : function()
end

--- ======================================================================
--- from production_label_shift.tl (pills shown while Shift is held, and on the selected industry / warehouse)
-- Module: ug_require "square_industry_production_label::/production_label/production_label_shift.tl" as SquareProductionLabelShift

global record SquareProductionLabelShift
	--- Top tool names in which holding Shift shows the pills.
	TOOLS : {string : boolean}
	--- True once the entry point runs in this Lua state.
	installed : boolean
	--- True while Shift shows the pills on every label.
	active : boolean
	--- Construction -> number of its windows open.
	selected : {integer : integer}
	--- One frame's input (Shift held, top tool name or nil); returns the new `active`.
	update : function(held : boolean, toolName : string) : boolean
	--- A window of `construction` opened / closed (counted).
	opened : function(construction : integer)
	closed : function(construction : integer)
	--- True when the label of `construction` shows its pills (Shift, its window open, or not installed).
	isShown : function(construction : integer) : boolean
	--- Fresh state (tests).
	reset : function()
	--- The construction entity of `entity` (itself when it is one), else `entity`; -1 for nil / negative.
	toConstruction : function(entity : integer) : integer
end

recordDef = false
