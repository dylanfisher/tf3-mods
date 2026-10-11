-- Industry Production Label: the HUD icon script set on industry constructions by
-- content/mod.script.lua (data.hudIconScript.fileName = "...production_label.script@hudIconFn").
--
-- HudIconMasterGame calls hudIconFn(captureParams, params, userParam) for the construction's first
-- subconstruction (the industry's STOCK_LIST entity) and appends the result to the same HUD icon
-- as the stock pill (.cache/game/base/content/gui/main/hud_icon_toolbox.tl:242-251, 353-356).
-- Shape modelled on .cache/game/base/content/landmarks/landmark_hud.script.tl (hudIconFn returns a
-- registered recipe) and on StockHudIcon / HudIconMasterGame (hud_icon_toolbox.tl:56-108, 161-372).
--
-- READ-ONLY: per refresh, one getStockListInputOutputData + one getIndustryProductionData per output
-- (base industry_util, the same calls as the industry window) + one STOCK_LIST read + one lookup in
-- the shared pickup-rate cache (production_label_pickup.tl, rebuilt there at most every 15 s). No
-- commands, no game script, no saved state. Refreshed every REFRESH_INTERVAL s, not every frame
-- (PLAN "Recipe", "Pickup rate pill"). The engine part is shared per entity through
-- production_label_readcache.tl: one read per industry / warehouse per readcache.TTL_MS (1.5 s) for
-- all labels of it (PERF_REVIEW.md 2026-10-10).
--
-- Options (mod settings, PLAN "Options", "Settings read live (2026-10-07)"): read live by readSettings()
-- from api.engine.config.getModParams() each time hudIconFn is called (once per HUD icon mount, not per
-- frame), never cached across calls: params only change on a game load, which rebuilds the HUD, and a
-- cache would keep the previous save's choice. (Revision 3 baked them into the hudIconScript params in
-- content/mod.script.lua; the game kept the old construction resources, so a changed setting did not
-- apply.) captureParams now only carry the kind ({kind = "industry"} / {kind = "warehouse"}).
-- Pickup off: pickup.ratesFor is never called, so the shared cache is never rebuilt. Production and
-- pickup off (industries), or warehouse off (warehouses): an empty layout without a recipe or any
-- engine read.
--
-- Warehouses (PLAN "Warehouse rates (2026-10-07)"): content/mod.script.lua sets this same hudIconFn on
-- warehouse constructions with captureParams {kind = "warehouse"}. HudIconMasterGame calls it for the
-- warehouse's subconstructions[1], the warehouse entity with the StorageStock the base stock pill shows
-- (warehouses/warehouse.script.lua:349; StockHudIcon, hud_icon_toolbox.tl:56-108). hudIconFn then mounts
-- ProductionLabelWarehouseHudIcon instead: per refresh, two getCargoLogValueDiffPerYear reads per cargo
-- type (incoming "itemsUnloaded", outgoing "itemsLoaded"), the same calls the base stock pill makes per
-- stored cargo (cargo_util.tl:238-239). Industries are unchanged.

-- SQPERF (plans/sqperf/README.md): load time of this HUD Lua state, the first industry read (it
-- includes the first pickup-cache rebuild), slow calls (> 16 ms, at most one line per section per
-- minute) and, with the "Debug: performance log" mod setting, a 30 s summary. hudIconFn, the recipe
-- renders and the useStepStateTimer reads (first in render, then react.onStepTimer) all run on worker
-- threads ("Main Pool N"); api.type.Clock is safe there (docs/findings.md "Timers and threads in GUI
-- contexts"). Local counters only; nothing is saved. read_industry / read_warehouse time only the
-- engine reads behind the shared read cache; cache hits are counted (read_cache_hit, read_cache_hit_wh,
-- read_cache_new = industries cached for the first time or again after expiring), pickup_rebuild is
-- one slice of a pickup rebuild and pickup_built counts completed rebuilds.
local sqperf = ug_require "square_industry_production_label::/sqperf/square_industry_production_label.lua" as SquareIndustryProductionLabelSqPerf
local perf = sqperf.new({ mod = "square_industry_production_label", ctx = "hud", paramKey = "sqperf_log", first = { "read_industry" } })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl" as GuiReactUtil
local cargo_util = ug_require "::/gui/main/cargo_util.tl" as CargoUtil
local industry_util = ug_require "::/gui/main/industry_util.tl" as IndustryUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil

local model = ug_require "square_industry_production_label::/production_label/production_label_model.tl" as SquareProductionLabelModel
local pickup = ug_require "square_industry_production_label::/production_label/production_label_pickup.tl" as SquareProductionLabelPickup
local readcache = ug_require "square_industry_production_label::/production_label/production_label_readcache.tl" as SquareProductionLabelReadCache
pickup.perf = perf -- SQPERF section "pickup_rebuild", counter "pickup_built"

-- Millisecond wall clock for the read cache and the sliced pickup rebuild: api.type.Clock (safe on the
-- HUD worker threads, docs/findings.md "Timers and threads in GUI contexts"; never getApplicationTime,
-- GUI-thread only). Fallback os.time (1 s steps: a cached read is then at most ~2 s old).
local nowMs : function() : number
do
	local ok, clock = pcall(function() : Clock return api.type.Clock.new() end)
	if ok and clock ~= nil and pcall(function() : integer return clock:getTime() end) then
		nowMs = function() : number return clock:getTime() / 1000 end
	else
		nowMs = function() : number return os.time() * 1000 end
	end
end
pickup.nowMs = nowMs

local STOCK_LIST = api.type.ComponentType.STOCK_LIST

-- Seconds between engine reads. useStepStateTimer(getFromEngine, interval?, stateEqualsFn?)
-- defaults to 0.5 (.cache/game/base/tealdef/gui/main/engine_react_util.d.tl:20-24,
-- engine_react_util.tl:126-157, via react.onStepTimer(fn, intervalSeconds?)). Capacity only changes
-- with boosts / expansion and the idle state with deliveries, so 2 s is plenty.
local REFRESH_INTERVAL <const> = 2.0

-- isIndustry as the industry window passes it (industry_eow.script.tl:734 -> ProductionRulesWidget
-- -> industry_react_util.tl:306); hudIconScript is only set on data.isIndustry constructions.
local IS_INDUSTRY <const> = true

local record ProductionLabelParam
	entity : Engine.Entity
	showProduction : boolean
	showPickup : boolean
end

--- Engine read for one industry entity (the STOCK_LIST subconstruction), without pickup rates (the
--- shared read cache keeps this part; readIndustry adds each label's pickup). Output i of
--- getStockListInputOutputData(entity, false, false, 0) (0 = no limit, industry_util.tl:170, 265-294)
--- is the `index` getIndustryProductionData looks up (it calls the same function with maxNum = index,
--- industry_util.tl:313-317), so each output cargo gets the window's `total` and `actual`.
local function readView(entity : Engine.Entity) : SquareProductionLabelView
	if entity == nil or entity < 0 or not api.engine.entityExists(entity) then
		return nil
	end
	local stockList : Engine.Component.StockList = api.engine.getComponent(entity, STOCK_LIST)
	if stockList == nil then
		return nil
	end
	local outputs = industry_util.getStockListInputOutputData(entity, false, false, 0)
	local productionDatas : {IndustryUtil.ProductionData} = {}
	for i = 1, #outputs do
		local pd = industry_util.getIndustryProductionData(entity, false, false, i, IS_INDUSTRY)
		if pd ~= nil then
			productionDatas[#productionDatas + 1] = pd
		end
	end
	return model.view(productionDatas, stockList.cargoData, nil)
end

--- What a label's timer reads (PERF_REVIEW.md 2026-10-10): the industry part from the shared per-entity
--- read cache (one engine read per entity per readcache.TTL_MS, whichever label asks first; SQPERF
--- section "read_industry" = those engine reads, counters "read_cache_hit" / "read_cache_new"), then
--- this label's pickup rates. Pickup rates ride along in the same state (entry.pickup), so no second
--- timer is needed; the pickup cache is only touched when showPickup is set (option off: no lookup,
--- no rebuild) and the industry has a view. An engine-read error is raised to the caller (not cached).
local function readIndustry(entity : Engine.Entity, showPickup : boolean) : SquareProductionLabelView
	local cache = readcache.industry
	local now = nowMs()
	local found, cached = readcache.get(cache, entity, now)
	local view : SquareProductionLabelView
	if found then
		perf:count("read_cache_hit")
		view = cached as SquareProductionLabelView
	else
		local tPerf = perf:start() -- SQPERF section "read_industry" (failed reads count too)
		local ok, res = pcall(readView, entity)
		perf:stop("read_industry", tPerf)
		if not ok then error(res, 0) end
		view = res as SquareProductionLabelView
		if readcache.put(cache, entity, now, view) then perf:count("read_cache_new") end
	end
	if showPickup and view ~= nil then
		return model.withPickup(view, pickup.ratesFor(entity))
	end
	return view
end

--- One pill, built like the stock pill: makeContentLabelIndictator with labelMode "HudIconMain"
--- (hud_icon_toolbox.tl:78-84), wrapped in a BoxLayout that only carries our class for the scoped CSS.
--- A single icon path is passed as a string so the pill has the same ImageView structure as the stock
--- pill; a list becomes a horizontal BoxLayout of icons (gui_react_util.tl:283-308).
local function makePill(style : SquareProductionLabelStyle, paths : {string}, value : integer) : TreeNodeId
	local iconPath : string | {string} = paths
	if #paths == 1 then
		iconPath = paths[1]
	end
	return builtin.BoxLayout{
		meta = { class = style.entryClass },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			gui_react_util.makeContentLabelIndictator({
				iconPath = iconPath,
				label = model.formatLabel(value, lang_util.formatInt),
				labelFontColor = style.labelFontColor as GuiReactUtil.LabelFontColor,
				labelMode = "HudIconMain",
				shippingState = style.shippingState as GuiReactUtil.ShippingState,
			}),
		},
	}
end

--- Engine read for one warehouse entity. Every cargo type of api.res.cargoTypeRep.getAll() (as base
--- cargo_util.calculateStockCargoCount walks them, cargo_util.tl:214), passengers skipped, so a cargo that
--- only passed through (nothing stored right now) or that the warehouse no longer accepts still shows.
--- Per cargo: the per-year counts of the warehouse window's Incoming ("itemsUnloaded") and Outgoing
--- ("itemsLoaded") chart (warehouse_eow.script.tl:159; util.d.tl:89-94). Filtering, rounding and
--- ordering are in model.warehouseView.
local function readWarehouseView(entity : Engine.Entity) : SquareProductionLabelWarehouseView
	if entity == nil or entity < 0 or not api.engine.entityExists(entity) then
		return nil
	end
	if api.engine.getComponent(entity, STOCK_LIST) == nil then
		return nil
	end
	local passenger = api.res.cargoTypeRep.getPassengerCargoTypeId()
	local rates : {any} = {}
	for cargoTypeId, __ in pairs(api.res.cargoTypeRep.getAll()) do
		if cargoTypeId ~= passenger then
			local incoming = api.engine.util.stock.getCargoLogValueDiffPerYear(entity, "itemsUnloaded", cargoTypeId)
			local outgoing = api.engine.util.stock.getCargoLogValueDiffPerYear(entity, "itemsLoaded", cargoTypeId)
			rates[#rates + 1] = { cargoType = cargoTypeId, incoming = incoming, outgoing = outgoing }
		end
	end
	return model.warehouseView(rates)
end

--- A warehouse label's timer read through the shared read cache (as readIndustry; SQPERF section
--- "read_warehouse" = engine reads, counter "read_cache_hit_wh"). Errors are raised, not cached.
local function readWarehouse(entity : Engine.Entity) : SquareProductionLabelWarehouseView
	local cache = readcache.warehouse
	local now = nowMs()
	local found, cached = readcache.get(cache, entity, now)
	if found then
		perf:count("read_cache_hit_wh")
		return cached as SquareProductionLabelWarehouseView
	end
	local tPerf = perf:start() -- SQPERF section "read_warehouse" (failed reads count too)
	local ok, res = pcall(readWarehouseView, entity)
	perf:stop("read_warehouse", tPerf)
	if not ok then error(res, 0) end
	readcache.put(cache, entity, now, res)
	return res as SquareProductionLabelWarehouseView
end

-- SQPERF section "industry_render" (the recipe's own function; its first call includes the first read).
local ProductionLabelHudIcon = react.RegisterRecipe("ProductionLabelHudIcon", perf:wrap("industry_render", function(param : ProductionLabelParam) : TreeNodeId
	-- Set by the first failed read. That industry then shows no label and is not read again, so a
	-- deterministic error is logged once instead of silently repeating every REFRESH_INTERVAL.
	local failed = react.useRef(false)
	local state = engine_react_util.useStepStateTimer(function() : SquareProductionLabelView
		if failed:get() then
			return nil
		end
		-- A malformed (modded) industry must never break the HUD: no label instead of an error.
		local ok, view = pcall(readIndustry, param.entity, param.showPickup)
		if not ok then
			failed:set(true)
			log.warning("square_industry_production_label: no label for entity " .. tostring(param.entity) .. ": " .. tostring(view))
			return nil
		end
		return view as SquareProductionLabelView
	end, REFRESH_INTERVAL)

	react.setMouseTransparent(true)

	local view = state:old()
	local rows : {TreeNodeId} = {}
	if view ~= nil then
		local count = #view.entries
		-- Row 1: production pills (capacity icon, plus the cargo icon from model.ICON_MIN_OUTPUTS entries on).
		-- Option "Show production" off: no row.
		if param.showProduction then
			local production : {TreeNodeId} = {}
			for __, entry in ipairs(view.entries) do
				local cargoIcon = cargo_util.getCargoIconById(entry.cargoType)
				production[#production + 1] = makePill(model.styleFor(entry.producing), model.iconPaths(cargoIcon, count), entry.value)
			end
			rows[#rows + 1] = builtin.BoxLayout{
				meta = { class = "production-label-row, production-label-spaced" },
				orientation = builtin.type.Orientation.Horizontal,
				children = production,
			}
		end
		-- Row 2, below: pickup-rate pills, only for outputs whose lines' summed rate is > 0. Same icon
		-- rule, counted over all outputs, so a multi-output industry always says which cargo it is.
		-- Option "Show line pickup rate" off: readView left every entry's pickup nil, so no row.
		local pickupPills : {TreeNodeId} = {}
		for __, entry in ipairs(model.pickupEntries(view)) do
			local cargoIcon = cargo_util.getCargoIconById(entry.cargoType)
			pickupPills[#pickupPills + 1] = makePill(model.STYLE_PICKUP, model.iconPaths(cargoIcon, count, model.PICKUP_ICON), entry.pickup)
		end
		if #pickupPills > 0 then
			rows[#rows + 1] = builtin.BoxLayout{
				meta = { class = "production-label-row, production-label-spaced" },
				orientation = builtin.type.Orientation.Horizontal,
				children = pickupPills,
			}
		end
	end

	-- Empty BoxLayout when nothing applies: the hudIconScript contract expects a layout
	-- (docs/wiki/modding/constructions/basics.md "HUD Icon Script").
	return builtin.BoxLayout{
		meta = { class = "production-label-layout, production-label-spaced" },
		orientation = builtin.type.Orientation.Vertical,
		children = rows,
	}
end))

local record WarehouseLabelParam
	entity : Engine.Entity
end

-- SQPERF section "warehouse_render".
local ProductionLabelWarehouseHudIcon = react.RegisterRecipe("ProductionLabelWarehouseHudIcon", perf:wrap("warehouse_render", function(param : WarehouseLabelParam) : TreeNodeId
	-- Same failure handling as ProductionLabelHudIcon: first error logged once, then no label.
	local failed = react.useRef(false)
	local state = engine_react_util.useStepStateTimer(function() : SquareProductionLabelWarehouseView
		if failed:get() then
			return nil
		end
		local ok, view = pcall(readWarehouse, param.entity)
		if not ok then
			failed:set(true)
			log.warning("square_industry_production_label: no warehouse label for entity " .. tostring(param.entity) .. ": " .. tostring(view))
			return nil
		end
		return view as SquareProductionLabelWarehouseView
	end, REFRESH_INTERVAL)

	react.setMouseTransparent(true)

	local view = state:old()
	local rows : {TreeNodeId} = {}
	if view ~= nil then
		-- Row 1: incoming, row 2: outgoing; the same cargos in the same order in both rows (a 0 is
		-- shown, so each cargo has its in/out pair). Every pill carries its cargo icon: a warehouse
		-- holds several cargos and the stock pills above may be in another order.
		local incoming : {TreeNodeId} = {}
		local outgoing : {TreeNodeId} = {}
		for __, entry in ipairs(view.entries) do
			local cargoIcon = cargo_util.getCargoIconById(entry.cargoType)
			incoming[#incoming + 1] = makePill(model.STYLE_INCOMING, model.warehouseIconPaths(model.INCOMING_ICON, cargoIcon), entry.incoming)
			outgoing[#outgoing + 1] = makePill(model.STYLE_OUTGOING, model.warehouseIconPaths(model.OUTGOING_ICON, cargoIcon), entry.outgoing)
		end
		rows[1] = builtin.BoxLayout{
			meta = { class = "production-label-row, production-label-spaced" },
			orientation = builtin.type.Orientation.Horizontal,
			children = incoming,
		}
		rows[2] = builtin.BoxLayout{
			meta = { class = "production-label-row, production-label-spaced" },
			orientation = builtin.type.Orientation.Horizontal,
			children = outgoing,
		}
	end

	-- Empty layout when nothing moved: the warehouse label looks vanilla.
	return builtin.BoxLayout{
		meta = { class = "production-label-layout, production-label-spaced" },
		orientation = builtin.type.Orientation.Vertical,
		children = rows,
	}
end))

local MOD_ID <const> = "square_industry_production_label"

-- Set after the first failed getModParams call, so a deterministic error is logged once, not per mount.
local settingsWarned = false

--- The mod settings, read live (no cache: see the header). getModParams is not marked GUI-thread only
--- (.cache/game/api/tealdef/api/engine.d.tl:1806-1807) and better_minimap reads it in its HUD script,
--- but hudIconFn / HUD recipes do not run on the GUI thread (getApplicationTime hard-crashed there), so
--- this call is an in-game risk to check (TESTING §8). Any error: one warning, then all pills on.
local function readSettings() : SquareProductionLabelOptions
	local ok, allOrErr = pcall(api.engine.config.getModParams)
	if not ok then
		if not settingsWarned then
			settingsWarned = true
			log.warning("square_industry_production_label: could not read the mod settings, showing all pills: " .. tostring(allOrErr))
		end
		return model.options(nil)
	end
	local all = allOrErr as {string : any}
	local mine : any = nil
	if type(all) == "table" then
		mine = all[MOD_ID]
	end
	return model.options(mine)
end

--- Still a layout, as the hudIconScript contract expects (constructions/basics.md "HUD Icon Script").
local function emptyLayout() : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = "production-label-layout, production-label-spaced" },
		orientation = builtin.type.Orientation.Vertical,
		children = {},
	}
end

perf:phase("init", perfInit)

return {
	-- SQPERF section "hud_icon_fn" (once per HUD icon mount; includes the settings read).
	hudIconFn = perf:wrap("hud_icon_fn", function(captureParams : any, params : Builtin.HudIconParam, _userParam : HudIconToolbox.HudIconMasterUserParam) : TreeNodeId
		local options = readSettings()
		if model.kind(captureParams) == model.WAREHOUSE_KIND then
			if not options.showWarehouse then
				return emptyLayout()
			end
			return ProductionLabelWarehouseHudIcon{ entity = params.entity }
		end
		if not options.showProduction and not options.showPickup then
			return emptyLayout()
		end
		return ProductionLabelHudIcon{ entity = params.entity, showProduction = options.showProduction, showPickup = options.showPickup }
	end),
}
