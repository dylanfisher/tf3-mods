recordDef = true

-- Line Rate Matcher shared types (pure model, engine adapter, commands, view model and GUI).
-- Part of Line Manager Plus (feature "line_rate_matcher", merged from square_line_rate_matcher 2026-10-11).
-- Loaded as module "line_manager_plus.rate_matcher_types" (every content/**/*.d.tl; tools/tealrt.py def_modules).
-- tealdef/line_manager_plus/rate_matcher_types.d.tl is a byte-for-byte editor copy (make check flags drift).
-- Every global name is prefixed SquareRateMatcher (globals are shared by all loaded mods).
-- Cargo ids are the game's 0-based cargo type ids everywhere here (the adapter converts IdVectors,
-- which are indexed cargo + 1).

-- ======================================================================
-- Supply -> target (model.targetsFromSupply)

--- One producer (StockList) in a stop's catchment, for one of its output cargos.
--- maxPerYear = api.engine.util.stock.getCargoMaxProductionPerYear (the industry window's number, 101 for
--- the probe's logging camp); producedPerYear = getCargoProducedPerYear (measured, noisy: hint only).
global record SquareRateMatcherProducer
	stockList : integer
	cargo : integer
	maxPerYear : number
	producedPerYear : number
end

--- One stop of a line: its station group, the set of cargos it loads there ({cargo -> true}) and, for the
--- line being matched, the producers in the group's reach. `producers` is optional on other lines' stops
--- (when present, a shared producer also makes that line a competitor).
global record SquareRateMatcherStop
	stationGroup : integer
	loads : {integer : boolean}
	producers : {SquareRateMatcherProducer}
end

--- Another line stopping at one of our station groups: its Rate (calcLineStationThroughput) and stops.
global record SquareRateMatcherOtherLine
	line : integer
	rate : number
	stops : {SquareRateMatcherStop}
end

global record SquareRateMatcherSupplyInput
	line : integer
	stops : {SquareRateMatcherStop}
	otherLines : {SquareRateMatcherOtherLine}
	passengerCargo : integer
end

--- Default target for one cargo the line loads next to at least one producer of it.
--- target = round(max(0, maxSupply - otherRate)).
global record SquareRateMatcherCargoTarget
	cargo : integer
	maxSupply : number
	produced : number
	otherRate : number
	otherLines : {integer}
	producers : {integer}
	target : integer
end

-- ======================================================================
-- Suggestion (model.suggest / model.suggestForCargos)

--- One vehicle on the line. capacities = {cargo -> capacity} from its TransportVehicleConfig;
--- purchaseTime from TRANSPORT_VEHICLE (bigger = newer); protected = in protectedEntities (missions);
--- selling = already going to the depot to be sold on arrival (sellOnArrival, sent by revisions up to 7 or another
--- mod). value = resale value
--- (api.engine.util.vehicle.getDepreciatedValue, the Replace window's refund, vehicle_store_window.tl:3525-3541);
--- running = running cost per year (getRunningCost, the vehicle window's figure, entity_window_util.tl:162).
--- capital = what replacing it costs per year: each part's store price (metadata cost.price) spread over that part's
--- lifespan in calendar years (model.capitalPerYear). Each nil when unknown.
global record SquareRateMatcherVehicle
	id : integer
	model : integer
	capacities : {integer : number}
	purchaseTime : number
	protected : boolean
	selling : boolean
	value : number
	running : number
	capital : number
end

--- One choice of the suggestion. delta > 0: clone `delta` vehicles of the template; delta < 0: sell the
--- vehicles in `remove` (length -delta); 0: keep. count = vehicles after, rate = estimated Rate after.
global record SquareRateMatcherOption
	delta : integer
	count : integer
	rate : number
	remove : {integer}
end

--- status: "ok" | "no_vehicles" | "no_rate" | "no_capacity" | "invalid_target".
--- Only "ok" fills the estimate fields. below / above = the counts whose estimated Rate is just below /
--- just above the target (the same option when one hits it exactly; below nil when even the fewest
--- vehicles are above the target, above nil with capped = true when MAX_ADD clones are still below it).
--- reason (suggestForCargos only): "single_cargo" | "most_vehicles".
global record SquareRateMatcherSuggestion
	status : string
	cargo : integer
	target : number
	rate : number
	count : integer
	perVehicle : number
	perModel : {integer : number}
	templateModel : integer
	templateVehicle : integer
	below : SquareRateMatcherOption
	above : SquareRateMatcherOption
	preselected : SquareRateMatcherOption
	delta : integer
	capped : boolean
	reason : string
	perCargo : {SquareRateMatcherSuggestion}
end

-- ======================================================================
-- Other models (model.rankModels)

--- A model that could serve the line: capacity for the cargo, top speed (any unit, same as current) and load speed
--- (metadata transportVehicle.loadSpeed, cargo units per second; nil = unknown).
global record SquareRateMatcherCandidate
	model : integer
	capacity : number
	speed : number
	loadSpeed : number
end

--- The line's current template model: its capacity / speed / load speed, its measured per-vehicle Rate and the share
--- of the line's round trip spent at stops (model.loadShare of the line's section times; nil = unknown, the estimate
--- then scales by capacity x speed only).
global record SquareRateMatcherCurrent
	model : integer
	capacity : number
	speed : number
	perVehicle : number
	loadSpeed : number
	loadShare : number
end

--- An alternative: estimated per-vehicle Rate, vehicles needed, the estimated Rate of that many and its
--- distance from the target.
global record SquareRateMatcherModelOption
	model : integer
	perVehicle : number
	count : integer
	rate : number
	diff : number
end

-- ======================================================================
-- Plans and their costs (model.plansFromSuggestion / model.switchPlans / model.planCost)

--- What one NEW vehicle of a model costs: price = the store price (metadata cost.price, the store's Buy total,
--- vehicle_store_window.tl:4038-4040), running = per year (metadata maintenance.runningCosts, the store's
--- "{cost}/year", vehicle_store_window.tl:118-125). nil = unknown.
--- capital = price spread over the model's lifespan, per year (model.capitalPerYear).
global record SquareRateMatcherModelCosts
	price : number
	running : number
	capital : number
end

--- One plan the window can apply: `count` vehicles of `model` on the line.
--- switch = false: the fleet's own model; buy = clones to add, remove = vehicles to sell (newest first).
--- switch = true: another model, the whole fleet changes: `replace` are replaced in place (makeVehicleReplaceCmd,
--- as the Replace window), `buy` new ones are bought onto the line, `remove` (surplus) are sold.
--- Costs (planCost): price = new vehicles (buy + replaced) x store price; refund = resale value of the vehicles
--- replaced or sold; net = price - refund (the Replace window's "for {cost}", vehicle_store_window.tl:4267-4278);
--- running = running cost per year of the fleet afterwards; capital = the fleet's purchase prices spread over their
--- lifespans, per year; costYear = running + capital (the yearly cost of owning the fleet); perRate = costYear / rate
--- (yearly cost per 1 of Rate per year). Each nil when unknown. suggested = the closest to the target (tie: fewer
--- vehicles).
--- fresh = true: an estimate for a line with no vehicles (model.estimatePlans): buy `count` new vehicles of `model`
--- onto the line (commands.buyOntoLine); perVehicle / roundTrip = the estimate per vehicle (Rate per year, seconds).
global record SquareRateMatcherPlan
	model : integer
	switch : boolean
	count : integer
	delta : integer
	rate : number
	diff : number
	buy : integer
	remove : {integer}
	replace : {integer}
	price : number
	refund : number
	net : number
	running : number
	capital : number
	costYear : number
	perRate : number
	suggested : boolean
	fresh : boolean
	perVehicle : number
	roundTrip : number
end

-- ======================================================================
-- Empty line estimate (model.calibrate / model.estimatePlans; findings lines-vehicles.md "Line Rate formula")

--- One other line of the same carrier with vehicles, for the calibration: distance = straight cyclic round trip
--- through its stops (m), stops = their count, speed = top speed of its first vehicle's model (m/s), drive / section =
--- sums of its LineCargoInfo driveSectionTimes / sectionTimes (s).
global record SquareRateMatcherTimingSample
	line : integer
	distance : number
	stops : integer
	speed : number
	drive : number
	section : number
end

--- How a carrier's vehicles run: detour = driving time / (straight distance / top speed), dwell = seconds at each
--- stop; n = the samples used (fallback = true: too few, the carrier's typical values). carrier = "water" | "road" |
--- "tram" | "air" | "other".
global record SquareRateMatcherTimes
	carrier : string
	detour : number
	dwell : number
	n : integer
	fallback : boolean
end

--- What the estimate of an empty line needs (engine.emptyLineInput): the route (distance m, stops), the carrier's
--- times, the buyable models (catalogue, for the cargo) and the default year in seconds (1460); depot = where they
--- would be bought.
global record SquareRateMatcherEmptyInput
	line : integer
	depot : integer
	cargo : integer
	distance : number
	stops : integer
	times : SquareRateMatcherTimes
	catalogue : {SquareRateMatcherModelInfo}
	yearSeconds : number
end

-- ======================================================================
-- from rate_matcher_model.tl (pure: no api.*, no base modules)
-- Module: ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_model.tl" as SquareRateMatcherModel
global record SquareRateMatcherModel
	--- At most this many clones in one suggestion.
	MAX_ADD : integer
	--- Vehicles a removal leaves on the line, at least.
	MIN_VEHICLES : integer
	--- Alternative models: at most this many vehicles of one model.
	MAX_MODEL_COUNT : integer
	--- Alternative models listed by default.
	TOP_MODELS : integer
	--- Rate comparisons tolerate this much (Rates are fractional per year).
	EPS : number
	--- loadShare never above this (a line that only waits gives no speed information).
	MAX_LOAD_SHARE : number
	--- "best": per rate at most this much (relative) above the lowest.
	BEST_TOLERANCE : number

	roundValue : function(v : any) : integer
	loadSetFromIdVector : function(v : {boolean}) : {integer : boolean}
	targetsFromSupply : function(input : SquareRateMatcherSupplyInput) : {SquareRateMatcherCargoTarget}, {integer}
	perVehicleRates : function(rate : number, vehicles : {SquareRateMatcherVehicle}, cargo : integer) : {integer : number}, {integer : number}
	pickSurplus : function(vehicles : {SquareRateMatcherVehicle}, k : integer, cargo? : integer) : {integer}
	suggest : function(rate : number, vehicles : {SquareRateMatcherVehicle}, cargo : integer, target : number) : SquareRateMatcherSuggestion
	suggestForCargos : function(rate : number, vehicles : {SquareRateMatcherVehicle}, targets : {integer : number}) : SquareRateMatcherSuggestion
	rankModels : function(candidates : {SquareRateMatcherCandidate}, current : SquareRateMatcherCurrent, target : number, topN? : integer) : {SquareRateMatcherModelOption}
	--- Estimated per-vehicle Rate of a candidate (rankModels' formula, see the module header); nil when it can't be
	--- estimated. The current model itself gives exactly current.perVehicle.
	modelPerVehicle : function(current : SquareRateMatcherCurrent, cand : SquareRateMatcherCandidate) : number
	--- Share of the round trip spent at stops: 1 - sum(drive times) / sum(section times) (LineCargoInfo
	--- driveSectionTimes / sectionTimes), clamped to 0 .. MAX_LOAD_SHARE; nil when the times don't make sense.
	loadShare : function(sectionTimes : {number}, driveTimes : {number}) : number
	--- price spread over the lifespan: price x yearMs / lifespanMs (both game ms); nil when unknown.
	capitalPerYear : function(price : number, lifespanMs : number, yearMs : number) : number
	--- Rows within BEST_TOLERANCE of the lowest perRate, as {index -> true}; empty when every row is (a tie).
	bestByPerRate : function(plans : {SquareRateMatcherPlan}) : {integer : boolean}
	--- Fills the cost fields of a plan (see SquareRateMatcherPlan) from the line's vehicles and the model's costs.
	planCost : function(p : SquareRateMatcherPlan, vehicles : {SquareRateMatcherVehicle}, costs : SquareRateMatcherModelCosts) : SquareRateMatcherPlan
	--- The fleet model's plans: the suggestion's below / above counts (one when they coincide), by count, costed.
	plansFromSuggestion : function(s : SquareRateMatcherSuggestion, vehicles : {SquareRateMatcherVehicle}, costs : SquareRateMatcherModelCosts) : {SquareRateMatcherPlan}
	--- Switch plans for another model (the whole fleet replaced): floor / ceil of target / perVehicle (at least 1),
	--- suggested as rankModels picks. Empty + reason "protected" (mission vehicles), "no_vehicles" or "invalid".
	switchPlans : function(modelId : integer, perVehicle : number, target : number, vehicles : {SquareRateMatcherVehicle}, costs : SquareRateMatcherModelCosts) : {SquareRateMatcherPlan}, string
	--- Running cost per year of the vehicles on the line (not selling); nil when none is known.
	fleetRunning : function(vehicles : {SquareRateMatcherVehicle}) : number

	--- Empty line estimate: fallback times per carrier ("water", "road", "tram", "air", "other").
	FALLBACK_TIMES : {string : SquareRateMatcherTimes}
	--- Fewer valid samples than this: the carrier's fallback times.
	MIN_SAMPLES : integer
	DETOUR_MIN : number
	DETOUR_MAX : number
	DWELL_MAX : number
	--- Median of the finite numbers in a list; nil when there are none.
	median : function(list : {number}) : number
	--- Straight cyclic round trip through the points ({x, y}, m); nil with fewer than 2 points or a bad one.
	routeDistance : function(points : {{number}}) : number
	--- The carrier's times from samples of other lines: medians of each sample's detour and dwell, clamped; the
	--- fallback for fewer than MIN_SAMPLES valid samples.
	calibrate : function(samples : {SquareRateMatcherTimingSample}, carrier : string) : SquareRateMatcherTimes
	--- Round trip (s) = distance x detour / speed + stops x dwell; nil when it can't be estimated.
	estimateRoundTrip : function(distance : number, stops : integer, speed : number, times : SquareRateMatcherTimes) : number
	--- Rate per year of one vehicle = capacity x yearSeconds / roundTrip; nil when unknown.
	estimatePerVehicle : function(capacity : number, roundTrip : number, yearSeconds : number) : number
	--- Plans for an empty line: per buyable model the count nearest the target (floor / ceil, 1 .. MAX_MODEL_COUNT),
	--- all bought new and costed; the TOP_MODELS closest to the target, then by cost per unit. suggested = the lowest
	--- cost per unit (tie: closer to the target). Empty for a target <= 0 or nothing estimable.
	estimatePlans : function(input : SquareRateMatcherEmptyInput, target : number, topN? : integer) : {SquareRateMatcherPlan}
end

-- ======================================================================
-- from rate_matcher_engine.tl (engine reads; no commands)
-- Module: ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_engine.tl" as SquareRateMatcherEngine

--- A vehicle model as the store sees it, for one cargo. capacity = the store's per-cargo capacity
--- (vehicle_store_util.tl:57-104: per compartment the largest load config that takes the cargo, summed);
--- speed = top speed from land/water/airVehicle (m/s, same unit for every model); price = cost.price;
--- running = maintenance.runningCosts (per year, the store's "{cost}/year", vehicle_store_window.tl:118-125).
--- available = buyable in `year` (vehicle_store_util.tl:731-736). loadSpeed = transportVehicle.loadSpeed; lifespanMs =
--- maintenance.lifespan x 1000 (vehicle_util.getLifespan, game ms); capital = price per calendar year of lifespan.
global record SquareRateMatcherModelInfo
	model : integer
	path : string
	name : string
	capacity : number
	speed : number
	price : integer
	running : number
	available : boolean
	loadSpeed : number
	lifespanMs : number
	capital : number
end

--- How the line's round trip splits (transportVehicleSystem.getLineCargoInfo for the cargo): section = sum of
--- sectionTimes, drive = sum of driveSectionTimes (seconds), loadShare = model.loadShare of them; maxFrequency =
--- api.engine.util.line.getMaxFrequency (logged for comparison). nil fields when unknown.
global record SquareRateMatcherLineTiming
	cargo : integer
	section : number
	drive : number
	sections : integer
	loadShare : number
	maxFrequency : number
end

--- Everything the pure model needs for one line, read in one go (engine.readLine).
global record SquareRateMatcherLineData
	line : integer
	rate : number
	vehicles : {SquareRateMatcherVehicle}
	supply : SquareRateMatcherSupplyInput
	passengerCargo : integer
	year : integer
	timing : SquareRateMatcherLineTiming
end

--- engine.modelCatalogue options. year: default the current calendar year; vehicleFilter: the mission
--- filter of gameCtx.filters:get().vehicleFilter (paths enabled / disabled, vehicle_store_util.tl:711-718).
global record SquareRateMatcherCatalogueOptions
	year : integer
	vehicleFilter : GameContext.Filters.VehicleFilter
end

global record SquareRateMatcherEngine
	--- Store availability rule (vehicle_store_util.tl:315-320, 731-736) for metadata yearFrom / yearTo.
	isAvailable : function(yearFrom : integer, yearTo : integer, year : integer) : boolean
	--- Replace-window filter tags rule (vehicle_store_util.depotMatchesVehicleFilterTags, :636-667):
	--- the model must carry every tag of the line's vehicles.
	matchesFilterTags : function(modelTags : {string}, lineTags : {string}) : boolean
	--- One of the model's transport modes is in the allowed set (depotMatchesVehicleTransportModes, :670-688).
	matchesTransportModes : function(modelModes : {TransportMode}, allowed : {TransportMode : boolean}) : boolean
	--- Per-cargo capacity of a ModelMetadata.TransportVehicle (0 when it can't carry it).
	cargoCapacity : function(tv : ModelMetadata.TransportVehicle, cargo : integer) : number

	currentYear : function() : integer, string
	lineRate : function(line : integer) : number, string
	lineVehicles : function(line : integer, protected? : {integer : any}) : {SquareRateMatcherVehicle}, string
	supplyInput : function(line : integer) : SquareRateMatcherSupplyInput, string
	readLine : function(line : integer, protected? : {integer : any}) : SquareRateMatcherLineData, string
	modelInfo : function(model : integer, cargo : integer, year? : integer) : SquareRateMatcherModelInfo, string
	modelCatalogue : function(vehicleIds : {integer}, cargo : integer, opts? : SquareRateMatcherCatalogueOptions) : {SquareRateMatcherModelInfo}, string
	--- Game ms per calendar year at the current calendar speed: api.util.getYearDuration(millisPerDay), the default
	--- year when paused (millisPerDay 0) or unknown (Problem Radar's radar_checks.calendarYearMs).
	calendarYearMs : function(millisPerDay : integer, yearDuration : function(integer) : integer, defaultYearMs : integer) : integer
	--- calendarYearMs for the running game (GAME_SPEED.millisPerDay).
	yearMs : function() : integer
	--- The line's round-trip split for `cargo` (see SquareRateMatcherLineTiming); nil + reason when unreadable.
	lineTiming : function(line : integer, cargo : integer) : SquareRateMatcherLineTiming, string
	currentFor : function(info : SquareRateMatcherModelInfo, perVehicle : number) : SquareRateMatcherCurrent
	candidatesOf : function(catalogue : {SquareRateMatcherModelInfo}) : {SquareRateMatcherCandidate}

	--- Empty line estimate. Lines scanned per calibration, samples that end the scan, stops read per line,
	--- calibration cache life (game ms).
	MAX_SCAN_LINES : integer
	MAX_SAMPLES : integer
	MAX_STOPS : integer
	CALIBRATION_TTL_MS : integer
	--- Model catalogue keys kept (carrier, modes, tags, cargo, year, year length, mission filter); all dropped when full.
	MAX_CATALOGUE_KEYS : integer
	--- Drops the catalogue and calibration caches (tests).
	clearCaches : function()
	clearCalibration : function()
	--- "water" | "road" | "tram" | "air" | "rail" | "other" for a Carrier.
	carrierKey : function(carrier : Carrier) : string
	--- The default year in seconds (api.util.getDefaultYearDuration / 1000; 1460 when unknown).
	yearSeconds : function() : number
	--- {x, y} of each stop (at most MAX_STOPS): the station's construction position, else the station's bounding
	--- box center; nil + "no_positions" when a stop has neither.
	stopPositions : function(line : integer) : {{number}}, string
	--- The carrier's times from up to MAX_SCAN_LINES other lines with single-part vehicles, at most MAX_SAMPLES
	--- samples (cached per carrier for CALIBRATION_TTL_MS of game time).
	calibration : function(carrier : Carrier, exceptLine? : integer) : SquareRateMatcherTimes
	--- Everything the estimate of an empty line needs (the depot the line's Buy Vehicles button would use, its
	--- carrier, modes and filter tags, the stops, the calibration, the catalogue); nil + "rail" | "no_depot" |
	--- "no_positions" | "few_stops" | "no_cargo" | "no_models" | "read: ...".
	emptyLineInput : function(line : integer, cargo : integer, opts? : SquareRateMatcherCatalogueOptions) : SquareRateMatcherEmptyInput, string
end

-- ======================================================================
-- from rate_matcher_commands.tl (sends the vanilla buy / set-line / replace / send-to-depot commands)
-- Module: ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_commands.tl" as SquareRateMatcherCommands

--- status: "ok" (all done) | "partial" | "failed" (none done) | "invalid" (nothing sent).
--- done = new vehicle ids (clone), vehicle ids sold (sell), or every completed step (switch: replaced,
--- bought and sold ids). replaced / bought / sold: the switch's ids per kind. reasons = {reason -> count}:
--- clone / switch: "not_enough_money" (balance check before sending, or a failed buy / replace: vanilla's reading,
--- vehicle_react_util.tl:362-366), "mission" (mission.buyVehicle refused; message = its text),
--- "set_line_failed" (bought but not on the line: ids in `unassigned`), "buy_failed" (sendCommand threw),
--- "replace_failed", "no_depot", "invalid_template", "invalid_model", "invalid_line", "invalid_count", "protected";
--- sell: "gone", "protected", "already_selling", "sell_failed". depot / depotFrom: the depot the clones were bought
--- at and which rule found it (commands.resolveDepot).
global record SquareRateMatcherCommandResult
	status : string
	requested : integer
	done : {integer}
	unassigned : {integer}
	replaced : {integer}
	bought : {integer}
	sold : {integer}
	reasons : {string : integer}
	message : string
	depot : integer
	depotFrom : string
end

global record SquareRateMatcherCommands
	MAX_CLONES : integer
	--- Depot for clones: findBestLineAndDepotForVehicle(template) when it picks this line, else
	--- line_util.getBestDepotForLine(line), then findBest's depot anyway, then a line vehicle's depot.
	resolveDepot : function(template : integer, line : integer) : integer, string
	cloneOntoLine : function(template : integer, line : integer, count : integer, onDone? : function(SquareRateMatcherCommandResult)) : SquareRateMatcherCommandResult
	sellVehicles : function(ids : {integer}, onDone? : function(SquareRateMatcherCommandResult), protected? : {integer : any}) : SquareRateMatcherCommandResult
	--- A model switch plan (plan.switch): replace plan.replace in place by plan.model, buy plan.buy new ones onto the
	--- line (depot of `template`), sell plan.remove. All or nothing on money: nothing is sent unless the balance
	--- covers the net cost (new price x (replaced + bought) - resale of the replaced).
	switchModel : function(plan : SquareRateMatcherPlan, line : integer, template : integer, onDone? : function(SquareRateMatcherCommandResult), protected? : {integer : any}) : SquareRateMatcherCommandResult
	--- Buys `count` new vehicles of `model` at `depot` (nil: line_util.getBestDepotForLine) and puts them on the line
	--- (an empty line's estimate). All or nothing on money; result.bought / done = the new vehicles.
	buyOntoLine : function(model : integer, count : integer, line : integer, depot : integer, onDone? : function(SquareRateMatcherCommandResult)) : SquareRateMatcherCommandResult
	--- Opens the game's Replace Vehicles window (radar_fleet.tl replaceVehicles). false + reason when it fell
	--- back to opening the vehicle manager with the vehicles selected (or nothing to do).
	replaceViaWindow : function(vehicleIds : {integer}, onClose? : function()) : boolean, string
	--- What one clone of `template` costs in the store: the parts' metadata cost.price (the store's price,
	--- vehicle_store_window.tl:3765-3771, 4038-4040), else api.engine.util.vehicle.getPartPrice; nil when unknown.
	clonePrice : function(template : integer) : integer
	--- The store price of one new vehicle of a model (metadata cost.price), nil when unknown.
	modelPrice : function(model : integer) : integer
	--- One log line with every price candidate of the template (store price, getPartPrice of its part and of a
	--- fresh clone part, resale value, running costs), for comparing with the store in game.
	priceReport : function(template : integer) : string
end

-- ======================================================================
-- from rate_matcher_view.tl (pure view model + texts of the popup; no api.*, only _() and the model)
-- Module: ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_view.tl" as SquareRateMatcherView

--- What the popup's Supply line says. kind: "cargo" (targets from producers) | "no_producer" (the line loads
--- cargo, none of it next to a producer) | "passenger" (passengers only) | "none" (loads nothing).
--- cargo = the cargo the options are computed for (the deciding cargo of suggestForCargos for "cargo"; otherwise
--- the lowest loaded cargo, passengers last; nil = equal shares). suggested = the target to prefill (nil: none).
global record SquareRateMatcherSupplyView
	kind : string
	targets : {SquareRateMatcherCargoTarget}
	unsupplied : {integer}
	cargo : integer
	suggested : integer
	reason : string
end

--- One row of the model comparison: the fleet's model (current = true, first) or another model. plans = its
--- below / above counts; plan = the suggested one (the table shows it).
--- best = its plan has the lowest yearly cost per Rate of the table (model.bestByPerRate; none on a tie).
global record SquareRateMatcherModelRow
	model : integer
	name : string
	current : boolean
	plans : {SquareRateMatcherPlan}
	plan : SquareRateMatcherPlan
	best : boolean
end

--- What view.build needs besides the line: the selection (nil = the fleet's model / the suggested count), the
--- model catalogue (engine.modelCatalogue, nil + why when none), the fleet model's info (infoOf(model): capacity,
--- speed, price, running; it may no longer be buyable) and the store price of one clone of the template.
global record SquareRateMatcherBuildInput
	selectedModel : integer
	selectedCount : integer
	catalogue : {SquareRateMatcherModelInfo}
	catalogueWhy : string
	infoOf : function(model : integer) : SquareRateMatcherModelInfo
	clonePrice : integer
	--- A line with no vehicles: the estimate's input (engine.emptyLineInput), or why there is none.
	empty : SquareRateMatcherEmptyInput
	emptyWhy : string
end

--- The popup for one target. status = the model's suggest status ("ok" fills the rest). models = the comparison
--- table (fleet model first); modelsWhy = why no other model is listed (engine.modelCatalogue's reason, "protected",
--- "none"; nil when some are); selectedModel = the active model row, plans = its plans, selected = the plan Apply
--- runs. fleetRunning = the line's running cost per year now.
--- A line with no vehicles: status "estimate" (models = the estimate's rows, one plan each, fresh), "estimate_target"
--- (target 0), "estimate_none" (no model within MAX_MODEL_COUNT), or "no_vehicles" with emptyWhy (no estimate);
--- empty = the estimate's input (route, times) for the note.
global record SquareRateMatcherViewState
	status : string
	rate : number
	count : integer
	perVehicle : number
	target : number
	cargo : integer
	capped : boolean
	templateModel : integer
	templateVehicle : integer
	suggestion : SquareRateMatcherSuggestion
	fleetRunning : number
	models : {SquareRateMatcherModelRow}
	modelsWhy : string
	selectedModel : SquareRateMatcherModelRow
	plans : {SquareRateMatcherPlan}
	selected : SquareRateMatcherPlan
	empty : SquareRateMatcherEmptyInput
	emptyWhy : string
end

--- One cell of the window's stats row (as the Line Manager's Capacity / Utilization / ... row).
global record SquareRateMatcherStatCell
	title : string
	value : string
	tip : string
end

global record SquareRateMatcherView
	--- The target box accepts 0 .. MAX_TARGET (per year).
	MAX_TARGET : integer
	--- Whole number as text (round half up); "?" for nil / NaN.
	fmt : function(v : any) : string
	--- Per-vehicle Rate: one decimal below 10, else whole.
	fmtPer : function(v : any) : string
	--- "{name}" placeholders (lang_util.format style, tostring of each value).
	fill : function(s : string, vars : {string : any}) : string
	supplyView : function(data : SquareRateMatcherLineData) : SquareRateMatcherSupplyView
	--- The prefilled target: the suggestion, else the current Rate (rounded), else 0.
	defaultTarget : function(data : SquareRateMatcherLineData, supply : SquareRateMatcherSupplyView) : integer
	--- A typed value as a target: rounded, 0 .. MAX_TARGET; nil when not a number.
	clampTarget : function(v : any) : integer
	--- The target box's text as a target: its digits only (nil when it has none), clamped.
	parseTarget : function(text : string) : integer
	build : function(data : SquareRateMatcherLineData, supply : SquareRateMatcherSupplyView, target : number, input : SquareRateMatcherBuildInput) : SquareRateMatcherViewState
	--- build's part for a line with no vehicles (v already has rate, count, fleetRunning).
	buildEmpty : function(v : SquareRateMatcherViewState, cargo : integer, target : number, input : SquareRateMatcherBuildInput) : SquareRateMatcherViewState
	--- A model's plans: the one with `count`, else the suggested one, else the first.
	pickPlan : function(plans : {SquareRateMatcherPlan}, count : integer) : SquareRateMatcherPlan
	--- One line: "Rate 66/yr · 2 vehicles · 33 each · running $12,000/yr".
	summaryText : function(v : SquareRateMatcherViewState, data : SquareRateMatcherLineData, money : function(integer) : string) : string
	--- The stats row: Rate, Vehicles, Per vehicle, Running costs (per year).
	statsCells : function(v : SquareRateMatcherViewState, data : SquareRateMatcherLineData, money : function(integer) : string) : {SquareRateMatcherStatCell}
	supplyLines : function(supply : SquareRateMatcherSupplyView, cargoName : function(integer) : string) : {string}
	statusText : function(v : SquareRateMatcherViewState) : string
	--- Number cells of a plan: count ("3"), change ("+1" / "-1" / "="), rate ("99"), buy now (net), cost/yr, per rate.
	--- money formats an integer.
	planCells : function(p : SquareRateMatcherPlan, money : function(integer) : string) : {string}
	--- Tooltip of a plan's Cost/yr cell: its running and purchase parts; nil when unknown.
	costTip : function(p : SquareRateMatcherPlan, money : function(integer) : string) : string
	--- The model table's name cell ("Small Ship (current)").
	modelName : function(row : SquareRateMatcherModelRow) : string
	--- What Apply does with the plan (one sentence; the Apply tooltip and the line above the buttons).
	planActionText : function(p : SquareRateMatcherPlan, modelName : string) : string
	--- No-models hint for engine.modelCatalogue's reason ("multi_part", ...), "protected", or an empty ranking.
	modelsHint : function(reason : string) : string
	--- The note under an empty line's estimate: route length, stops and where the times come from.
	estimateNote : function(e : SquareRateMatcherEmptyInput) : string
	--- Message after Apply (kind "clone" | "sell" | "switch" | "buy"), and whether it is an error.
	resultText : function(kind : string, r : SquareRateMatcherCommandResult, modelName? : string) : string, boolean
end

-- ======================================================================
-- from rate_matcher_window.tl (popup window; GUI thread)
-- Module: ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_window.tl" as SquareRateMatcherWindow

--- What the Line Manager tells the GUI each step (rate_matcher.lua reads its commonParams).
--- line = the line shown in the details panel when exactly one line is selected, else nil.
--- listAdd / listRemove: the Line Manager's vehicle list (commonParams.addOrRemoveVehicleToVehicleList,
--- manager_window.tl:7000-7017; vanilla Clone does the same in its onBuy, manager_window.tl:5108-5117); nil when the
--- manager doesn't offer it.
global record SquareRateMatcherContext
	line : integer
	protected : {integer : any}
	vehicleFilter : GameContext.Filters.VehicleFilter
	listAdd : function(ids : {integer})
	listRemove : function(ids : {integer})
end

global record SquareRateMatcherWindow
	--- Set once by rate_matcher.lua: returns the current Line Manager context (never errors; nil = none).
	setContextFn : function(fn : function() : SquareRateMatcherContext)
	--- The menu entry's icon (rate_matcher.lua registers "Match line rate" in the Line actions menu with it).
	ICON : string
	open : function(line : integer)
	close : function()
	isOpenFor : function(line : integer) : boolean
end
