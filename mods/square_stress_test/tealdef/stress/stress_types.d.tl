recordDef = true

-- Stress Test shared types. Every global name is prefixed SquareStress (globals are shared by all
-- loaded mods). Editor copy: tealdef/stress/stress_types.d.tl (keep both identical).

--- Load-time settings decoded from the mod.json params (stress_logic.configFromParams).
--- nil / false / 1.0 = leave the game's value alone.
global record SquareStressConfig
	noCosts : boolean
	sandboxMode : boolean
	vehiclesNoExpire : boolean
	noEmissions : boolean         -- "No noise and pollution": emissions script off, vehicle emissions 0, town noise/pollution ratings off
	recomputeFactor : number      -- multiplies simPersonDestinationRecomputationProbability
	townDevelopInterval : number  -- replaces townDevelopInterval (nil = unchanged)
	carTrafficMode : SquareStressCarTrafficMode -- "Car traffic" (nil = Default: town buildings untouched)
	townCapacityFactor : number   -- "Town building capacity": multiplies personCapacity.capacity (1.0 = unchanged)
end

--- One "Car traffic" option (stress_logic.CAR_TRAFFIC_MODES): town buildings whose personCapacity.type is
--- in landUses get the move modes in disallow added to personCapacity.disallowedMoveModes.
global record SquareStressCarTrafficMode
	id : string                   -- for the [SQST] lines: "default", "drive_destinations", "drive_all"
	landUses : {string}           -- "RESIDENTIAL", "COMMERCIAL", "INDUSTRIAL"
	disallow : {string}           -- MoveMode names ("WALK", "LINES"); never "DRIVE"
end

--- Persons of a scan by SIM_PERSON.lastMoveMode (Traffic tab readout, MORE_TRAFFIC.md U3/U5).
global record SquareStressMoveSplit
	drive : integer
	walk : integer
	lines : integer
end

--- One queued job: `total` calls of step(i, job), i = 1..total, at most queue.perFrame calls per frame
--- over all jobs. A job with notBefore (microseconds, same clock as tick's now) waits until then.
--- A serial job waits after every step until stress_logic.resume(job) is called (from the command's
--- callback), and only the first serial job in the queue runs: one serial command in flight at a time.
global record SquareStressJob
	name : string
	label : string                -- progress text (default: name), e.g. "Growing"
	total : integer
	step : function(i : integer, job : SquareStressJob)
	notBefore : integer
	quiet : boolean               -- true: no [SQST] line when done (probes log their own)
	serial : boolean
	waiting : boolean             -- serial: a step ran, its callback hasn't resumed the job yet
	waitSinceUs : integer
	waitTimeoutUs : integer       -- serial: give up waiting after this long (counts as an error)
	done : integer
	errors : integer
	firstErr : string
	startedUs : integer
	busyUs : integer
	maxPerTick : integer          -- at most this many steps per tick (one chunk per frame); nil = no limit
end

--- One "Towns" game-script event of the town ratings action (stress_logic.ratingSteps).
global record SquareStressRatingStep
	town : integer
	event : string                -- "setTownRatingSensitivity" or "resetTownRatingSensitivity"
	param : {string : any}
end

--- A finished job, as returned by stress_logic.tick (the caller logs it).
global record SquareStressDone
	name : string
	count : integer
	errors : integer
	firstErr : string
	wallMs : number               -- first step to last step
	busyMs : number               -- time spent inside step calls
	quiet : boolean
end

global record SquareStressQueue
	jobs : {SquareStressJob}
	perFrame : integer
end

global record SquareStressLogic
	PARAM_KEYS : {string}
	RECOMPUTE_FACTORS : {number}
	DEVELOP_INTERVALS : {number}
	SPEEDS : {integer}
	MIN_YEAR : integer
	MAX_YEAR : integer
	MAX_BOOKING : integer
	LOG_LINE_MAX : integer

	optionIndex : function(raw : any, count : integer) : integer
	configFromParams : function(params : {string : any}) : SquareStressConfig
	applyToBaseConfig : function(cfg : SquareStressConfig, bc : BaseConfig) : {string}
	--- loadModel modifier body: zeroes a vehicle model's emissions metadata (cars and transport vehicles only).
	zeroVehicleEmissions : function(data : table) : boolean
	--- postRunFn: the town_ratings_sensitivity.res config fields to set (option index 1 = scale 0).
	SENSITIVITY_OFF : {string : integer}
	--- "Show probe tab (developers)" from a full mod params table (getModParams()).
	showProbeTab : function(allModParams : {string : any}) : boolean
	--- Town rating events (base Towns game script) for Ignore noise and pollution / Restore defaults.
	RATING_KEYS : {string}
	ratingSteps : function(towns : {integer}, ignore : boolean) : {SquareStressRatingStep}

	newQueue : function(perFrame : integer) : SquareStressQueue
	push : function(q : SquareStressQueue, job : SquareStressJob) : SquareStressJob
	tick : function(q : SquareStressQueue, now : function() : integer) : {SquareStressDone}
	pending : function(q : SquareStressQueue) : integer
	progress : function(q : SquareStressQueue) : string
	clear : function(q : SquareStressQueue) : integer
	doneLine : function(d : SquareStressDone) : string
	oneLine : function(msg : string, max? : integer) : string

	parseYear : function(s : string) : integer, string
	bookingChunks : function(amount : number, maxChunk? : integer) : {integer}
	topUpAmount : function(balance : number, threshold : number, margin : number) : integer
	formatMoney : function(n : number) : string
	scaledFactors : function(current : {number}, factor : number) : {number}
	gridPoints : function(cx : number, cy : number, n : integer, spacing : number) : {{number}}

	-- Towns tab (Phase 2)
	GROW_FACTORS : {integer}
	MAX_SIZE_FACTOR : number
	SPAWN_COUNTS : {integer}
	TOWN_SIZES : {SquareStressTownSize}
	SERIAL_TIMEOUT_MS : number
	resume : function(job : SquareStressJob)
	listText : function(v : any) : string
	grownFactors : function(current : {number}, factor : number) : {number}, boolean
	spiralPoints : function(cx : number, cy : number, count : integer, spacing : number) : {{number}}
	mapGrid : function(minX : number, minY : number, maxX : number, maxY : number, spacing : number, margin : number) : {{number}}
	spreadSpacing : function(minX : number, minY : number, maxX : number, maxY : number, n : integer, margin : number, minSpacing : number) : number
	spreadPick : function(points : {{number}}, n : integer) : {{number}}
	placeTowns : function(candidates : {{number}}, existing : {{number}}, n : integer, minDist : number,
		isOk : function(x : number, y : number) : boolean, string) : {{number}}, {string : integer}
	MIN_TOWN_DIST : number
	PLACE_STEPS : {SquareStressPlaceStep}
	stepDistance : function(step : SquareStressPlaceStep, spacing : number) : number
	skippedText : function(skipped : {string : integer}) : string
	placeRelaxed : function(n : integer, existing : {{number}}, spacing : number,
		candidates : function(step : SquareStressPlaceStep, minDist : number) : {{number}},
		isOk : function(x : number, y : number) : boolean, string, spread : boolean) : {{number}}, {SquareStressPlaceTry}
	placementText : function(tried : {SquareStressPlaceTry}) : string
	GROW_PASSES : {integer}
	MIN_PASS_GAIN : integer
	passStep : function(i : integer, passes : integer) : integer, integer
	growPlan : function(current : {number}, factor : number, pass : integer) : {number}, string
	passContinues : function(before : integer, after : integer) : boolean
	nextTownNumber : function(names : {string}) : integer
	nearestPairs : function(newTowns : {SquareStressTownPos}, allTowns : {SquareStressTownPos}) : {{integer}}
	townReadout : function(towns : {integer}, caps : {integer : {integer}}, buildings : {integer : {integer}}, frozen : integer) : string
	GRID_LAYOUTS : {SquareStressGridLayout}
	GRID_SPACINGS : {number}
	GRID_CONNECT : {string}
	GRID_SEED : string
	gridPositions : function(cx : number, cy : number, cols : integer, rows : integer, spacing : number) : {SquareStressGridPoint}
	gridPairs : function(cols : integer, rows : integer, mode : integer) : {{integer}}
	gridLabel : function(layoutLabel : string, spacing : number) : string
	GRID_STREETS : {string}
	GRID_STREET_HALF : {number}
	WIDE_GRID_NEW_FROM : integer
	gridStreetHalf : function(caps : integer) : integer
	REMOVE_TARGETS : {string}
	isGridTownName : function(name : string) : boolean
	TEST_TOWN_MODES : {string}
	TEST_TOWN_WORDS : {string : boolean}
	isTestTownName : function(name : string) : boolean
	removeLabel : function(target : integer) : string
	-- More car traffic (MORE_TRAFFIC.md Phase 7a: loadScript modifier around the town building updateFn)
	CAR_TRAFFIC_MODES : {SquareStressCarTrafficMode}
	CAPACITY_FACTORS : {number}
	carTrafficMode : function(raw : any) : SquareStressCarTrafficMode
	wantsTownBuildingPatch : function(cfg : SquareStressConfig) : boolean
	townBuildingConfigText : function(cfg : SquareStressConfig) : string
	isTownBuildingScript : function(fileName : string) : boolean
	patchTownBuildingResult : function(result : {string : any}, cfg : SquareStressConfig) : boolean
	townBuildingPatchLine : function(fileName : string, result : {string : any}, capBefore : any, wrapped : integer,
		seen : integer) : string
	-- Junction test (Towns tab, needs square_roundabouts)
	JUNCTION_DIR : string
	JUNCTION_CASES : {SquareStressJunctionCase}
	JUNCTION_SETS : {SquareStressJunctionSet}
	JUNCTION_SPACINGS : {number}
	JUNCTION_INLINE : {string}
	CROSSING_D : number
	CROSSING_L : number
	CROSSING_G : number
	CROSSING_LANES : {integer}
	CROSSING_COLLECTOR : integer
	CROSSING_DIRS : {string : {number}}
	crossingLayout : function(cx : number, cy : number, scale : number) : SquareStressCrossingLayout
	crossingReach : function(townR : number) : number
	JUNCTION_LIGHTS : {string}
	CROSSING_LIGHTS : {string}
	INLINE_ROAD : {SquareStressJunctionCase}
	INLINE_HIGHWAY : {SquareStressJunctionCase}
	INLINE_ROAD_R : number
	INLINE_HIGHWAY_R : number
	INLINE_GAP : number
	INLINE_TOWN_R : number
	inlineStops : function(a : {number}, b : {number}, clearA : number, clearB : number, pitch : number, maxN : integer) : {{number}}
	junctionCases : function(set : SquareStressJunctionSet) : {SquareStressJunctionCase}
	junctionGrid : function(n : integer) : integer, integer
	wrapText : function(text : string, width : integer) : string
	fitJunctionGrid : function(n : integer, spacing : number, w : number, h : number, margin : number) : integer, integer, number
	junctionCells : function(points : {SquareStressGridPoint}, cols : integer, rows : integer) : {SquareStressJunctionCell}
	junctionLabel : function(n : integer, spacing : number) : string
	clusterEnds : function(ends : {{number}}, gap : number) : {SquareStressArmCluster}
	assignArms : function(cx : number, cy : number, clusters : {SquareStressArmCluster}, corners : {{number}}, maxDeg : number) : {integer : integer}
	assignLeftovers : function(cx : number, cy : number, clusters : {SquareStressArmCluster}, corners : {{number}},
		assigned : {integer : integer}, skip? : {integer : boolean}) : {{number}}
	linePoints : function(p0 : {number}, p1 : {number}, maxSeg : number) : {{number}}
	distToSegment : function(p : {number}, a : {number}, b : {number}) : number
	isLargeStreet : function(template : string) : boolean
	BUS_ZONE_MARGIN : number
	BUS_TOWN_MARGIN : number
	busEdgeReject : function(template : string, p0 : {number}, p1 : {number}, town : SquareStressTownPos, zones : {{number}},
		townOnly : boolean) : string
	gridHalfOfSize : function(size : integer) : number
	LARGE_PREFER : number
	rankTownNodes : function(cands : {SquareStressNodeCand}, arm : {number}, town : {number}, maxR : number, avoid : {{{number}}},
		noLarge? : boolean) : {SquareStressNodeCand}
	ROAD_BATCH : integer
	uniqueEdges : function(node2edges : {integer : {integer}}) : {integer}
	chunk : function(list : {integer}, n : integer) : {{integer}}
	orphanNodes : function(edgeEnds : {{integer}}, degree : {integer : integer}, frozen : {integer : boolean}) : {integer}

	-- Traffic tab (Phase 3)
	VEHICLES_PER_LINE : {integer}
	MAX_BUY_FAILURES : integer
	VEHICLE_TIMEOUT_MS : number
	stop : function(job : SquareStressJob)
	buyPlan : function(lines : {SquareStressLineVehicle}, n : integer) : {SquareStressLineVehicle}, {integer}
	configPrice : function(prices : {number}) : number
	canAfford : function(balance : number, price : number) : boolean
	trafficReadout : function(lines : integer, vehicles : integer, persons : integer, added : integer, driving? : integer,
		modes? : SquareStressMoveSplit) : string
	moveSplitText : function(split : SquareStressMoveSplit) : string
	moveSplitLog : function(split : SquareStressMoveSplit) : string

	-- Clear traffic (Phase 3B)
	CLEAR_INTERVALS : {integer}
	CLEAR_SCAN_PER_FRAME : integer
	CLEAR_SEND_PER_FRAME : integer
	CLEAR_STATE_JUMP_HOME : integer
	CLEAR_SUMMARY_US : integer
	CLEAR_CALLBACK_TIMEOUT_US : integer
	CLEAR_WHERE : {string}
	TOWN_AREA_MARGIN : number
	townArea : function(points : {{number}}, margin : number) : SquareStressTownArea
	inTownArea : function(areas : {SquareStressTownArea}, x : number, y : number) : boolean
	clearWanted : function(where : integer, inTown : boolean) : boolean
	isDriver : function(driveMode : boolean, hasPath : boolean, atVehicle : boolean, isTransportVehicle : boolean) : boolean
	chunkLast : function(first : integer, n : integer, size : integer) : integer
	clearStepsLeft : function(scanLeft : integer, sendLeft : integer, scanPer : integer, sendPer : integer) : integer
	clearLine : function(name : string, scanned : integer, drivers : integer, sent : integer, ok : integer,
		answered : integer, ms : number, note? : string) : string

	-- Action button labels
	growLabel : function(nearest : boolean, factor : number, passes? : integer) : string
	spawnLabel : function(n : integer, sizeLabel : string) : string
	addVehiclesLabel : function(n : integer) : string

	-- Auto bus lines (Phase 3C)
	BUS_TOWN_CHOICES : {string}
	BUS_TOWN_COUNTS : {integer}
	BUS_LINES_PER_TOWN : {integer}
	BUSES_PER_LINE : {integer}
	busTownPick : function(positions : {SquareStressTownPos}, cx : number, cy : number, choice : integer) : {SquareStressTownPos}
	busLinesLabel : function(choice : integer, lines : integer) : string

	-- Traffic through the Junction / Crossing test (bus lines between test towns)
	TEST_TRAFFIC : {string}
	TEST_ROUTES_MAX : integer
	cellRoutes : function(cells : {SquareStressJunctionCell}, linked : {string : {integer : boolean}}, maxN : integer) : {{integer}}
	crossingRoutes : function(linked : {integer : boolean}) : {{integer}}
	testSummary : function(title : string, built : integer, total : integer, what : string, linked : integer, links : integer,
		lines : integer) : string

	-- Showcase (Towns tab; gui/stress_junctions.tl jn.buildShowcase)
	newRng : function(seed : number) : SquareStressRng
	rngNext : function(rng : SquareStressRng) : integer
	rngInt : function(rng : SquareStressRng, n : integer) : integer
	showcaseSeed : function(clock : number) : integer
	SHOWCASE_GAP : number
	SHOWCASE_IX_R : number
	SHOWCASE_RB_MAX : number
	SHOWCASE_TOWN_R : number
	SHOWCASE_SIZE : integer
	SHOWCASE_STEP : number
	SHOWCASE_MAX_GROUPS : integer
	SHOWCASE_MISSES : integer
	SHOWCASE_KINDS : {string}
	SHOWCASE_KIND_NAMES : {string : string}
	SHOWCASE_AB : {SquareStressShowcaseAb}
	showcaseModes : function(kind : string, lightsOff : boolean, spec? : SquareStressShowcaseSpec) : {SquareStressShowcaseAb}
	showcaseZones : function(layout : SquareStressShowcaseLayout, cx? : number, cy? : number) : {SquareStressShowcaseZone}
	groupApproach : function(layout : SquareStressShowcaseLayout, g : SquareStressShowcaseGroup) : number
	-- Stress Test -> Smart Lanes zones channel (gui/stress_slzones.tl; Smart Lanes sl_zones.lua)
	SL_ZONES_MAX : integer
	SL_ZONE_R_MAX : number
	SL_ZONE_PAD : number
	SL_ZONE_AB : {string : boolean}
	--- { op = "set", run, zones = {{x, y, r, ab}} } (r = reach + SL_ZONE_PAD, capped) and the zones dropped.
	slZonesPayload : function(zones : {SquareStressShowcaseZone}, run : string) : {string : any}, integer
	SL_ZONE_LABEL_MAX : integer
	slZoneLabel : function(v : string) : string
	slZoneRun : function(seed : integer, wallS : integer, n : integer) : string
	slZonesByAb : function(list : {{string : any}}) : string
	SHOWCASE_IX_CROSS : integer
	SHOWCASE_IX_TYPES : {SquareStressShowcaseType}
	SHOWCASE_RB_TYPES : {SquareStressShowcaseType}
	SHOWCASE_PLAIN_FILE : string
	SHOWCASE_PLAIN_ANGLES : {number}
	SHOWCASE_PLAIN_TYPES : {SquareStressShowcaseType}
	showcaseTypes : function(kind : string) : {SquareStressShowcaseType}
	showcaseDraw : function(rng : SquareStressRng, t : SquareStressShowcaseType, armRoad : integer) : SquareStressJunctionCase
	showcaseParamText : function(case_ : SquareStressJunctionCase) : string
	showcaseArms : function(case_ : SquareStressJunctionCase) : {number}
	showcaseOneWay : function(case_ : SquareStressJunctionCase) : {integer : boolean}
	showcaseReach : function(case_ : SquareStressJunctionCase) : number
	showcaseTownDists : function(reach : number, arms : {number}, spacings : {number}, townR? : number) : {number}
	showcaseLayout : function(w : number, h : number, margin : number, seed : integer, spec? : SquareStressShowcaseSpec) : SquareStressShowcaseLayout
	showcaseCounts : function(layout : SquareStressShowcaseLayout, spec? : SquareStressShowcaseSpec) : integer, integer, {string : integer}, {string : integer}
	showcaseLabel : function() : string
	lightsShowcaseLabel : function(shape? : string) : string
	-- Lights showcase (SHOWCASE.md "Lights showcase"): lit plain crossings only, four twins each
	--- One junction shape per press (cycled): 2x2 X, 3x3 X, 3x2 X, T 2x2 (lanes each way per road)
	LIGHTS_SHAPES : {SquareStressShowcaseType}
	--- The Lights showcase spec of shape k (1-based, wrapped): one slot with that one type, no bus lines.
	lightsSpec : function(k : integer) : SquareStressShowcaseSpec
	-- Batched building (createGrid batch, Showcase link groups)
	GRID_BATCH : integer
	LINK_GROUP_MAX : integer
	LINK_GROUP_GAP : number
	TOWN_MATCH_MAX : number
	BATCH_TIMEOUT_MS : number
	segDist : function(a0 : {number}, a1 : {number}, b0 : {number}, b1 : {number}) : number
	--- Groups of non-touching link footprints {x0, y0, x1, y1, r} (indices), greedy in order, at most maxN each.
	groupLinks : function(items : {{number}}, gap : number, maxN : integer) : {{integer}}
	--- Point index -> found index, nearest pairs first, one to one, within maxD.
	matchNearest : function(points : {{number}}, found : {{number}}, maxD : number) : {integer : integer}
	TIMING_PHASES : {string}
	timingLine : function(id : string, t : {string : number}, totalMs : number) : string
	minutesText : function(ms : number) : string
	LIGHTS_AB : {SquareStressShowcaseAb}
	LIGHTS_SIZE : integer
	LIGHTS_GROW_FACTOR : number
	LIGHTS_TARGET_POP : number
	GROW_FILL : number
	growFactorFor : function(target : number, initRes : number, fill? : number) : number
	growFactorForCap : function(target : number, capacity : number) : number
	LIGHTS_GROW_PASSES : integer
	LIGHTS_LIT_FROM : integer
	-- Town growth locked into the grid (Showcase and Lights showcase)
	LOCK_BATCH : integer
	LOCK_MAX_PASS : integer
	LOCK_RETRY_MS : number
	LOCK_MARGIN : number
	HOUSE_MARGIN : number
	LOCK_REACH : number
	STUB_TOL : number
	ZONE_LOCK_MARGIN : number
	OWN_TOWN_MARGIN : number
	DENSE_GROW_FACTOR : number
	DENSE_GROW_PASSES : integer
	DENSE_WEIGHTS : {number}
	outsideGrid : function(a : SquareStressLockArea, px : number, py : number, margin : number) : boolean
	edgeOutside : function(a : SquareStressLockArea, p0 : {number}, p1 : {number}, margin : number) : boolean
	--- 0 / 1: which end of the edge is a grid corner stub's outer end; nil: no stub.
	stubOuterEnd : function(a : SquareStressLockArea, p0 : {number}, p1 : {number}, tol? : number) : integer
	--- makeTownCustomDistributionWeightsCmd's table: w (default DENSE_WEIGHTS) for each of the 3 land uses.
	denseWeights : function(w? : {number}) : {{number}}
	levelCounts : function(levels : {integer}) : {integer}
	levelText : function(c : {integer}) : string
	denseSteps : function(n : integer, passes : integer) : {SquareStressDenseStep}
	popText : function(pops : {integer : integer}, n : integer) : string
	popByTargetText : function(pops : {integer : integer}, targets : {integer : number}, n : integer) : string
	leakLine : function(name : string, label : string, outside : integer, houses : integer, extra? : string) : string
	--- The variants of the shared Showcase code: the Showcase (v2) and the Lights showcase.
	SHOWCASE_SPEC : SquareStressShowcaseSpec
	LIGHTS_SPEC : SquareStressShowcaseSpec
	LIGHTS_MIXED_AB : {SquareStressShowcaseAb}
	LIGHTS_EXITFAN_AB : SquareStressShowcaseAb
	LIGHTS_PER_TYPE : integer
	lightsMixedSpec : function() : SquareStressShowcaseSpec
	-- Light plans A/B (SHOWCASE.md "Light plans A/B"): 2x2 X and 3x3 X, twins game / sl_phases / sl_auto, balanced and
	-- unbalanced sets in turn
	LIGHTS_AUTO_AB : SquareStressShowcaseAb
	LIGHTS_PLANS_AB : {SquareStressShowcaseAb}
	LIGHTS_PLANS_TARGET_POP : number
	LIGHTS_PLANS_PER_TYPE : integer
	LIGHTS_PLANS_POPS : {string : number}
	LIGHTS_PLANS_UNBALANCED : {string : string}
	lightsPlansDemand : function(typeIndex : integer, k : integer) : string
	lightsPlansTownPop : function(demand : string, side : string) : number, string
	lightsPlansSpec : function() : SquareStressShowcaseSpec
	LIGHTS_PLANS_SPEC : SquareStressShowcaseSpec
	lightsPlansLabel : function() : string
	specKinds : function(spec : SquareStressShowcaseSpec) : {string}
	specTypes : function(spec : SquareStressShowcaseSpec, slot : string) : {SquareStressShowcaseType}
	specModes : function(spec : SquareStressShowcaseSpec) : {SquareStressShowcaseAb}
	specSize : function(spec : SquareStressShowcaseSpec) : integer
	specTownR : function(spec : SquareStressShowcaseSpec) : number
	specSizeText : function(spec : SquareStressShowcaseSpec) : string
	showcaseRoutes : function(layout : SquareStressShowcaseLayout, groupLinked : {integer : {integer : boolean}}, maxN : integer) : {{integer}}
	showcaseRedraw : function(case_ : SquareStressJunctionCase, maxReach : number, seed : integer, spec? : SquareStressShowcaseSpec) : SquareStressJunctionCase
	--- nil when a set's twins match as built, else the reason(s): "town", "redrawn", "town,redrawn".
	showcaseMatch : function(twins : {SquareStressShowcaseTwin}, lostTown : boolean, lostLink? : boolean, lostEntry? : boolean) : string
	showcaseZoneLine : function(z : SquareStressShowcaseZone, measured : boolean) : string
	showcaseZoneMatchLine : function(z : SquareStressShowcaseZone) : string
	countryTemplate : function(carLanes : integer, year? : integer) : string
	axisUnit : function(deg : number) : {number}
	COMPASS : {string}
	compassIndex : function(side : string) : integer
	compassOf : function(deg : number) : string
	showcaseTownName : function(t : SquareStressShowcaseType, m : SquareStressShowcaseAb, set : integer, side : string, modeNames : boolean, word? : string) : string
	sideCentre : function(tx : number, ty : number, half : number, jx : number, jy : number) : {number}
	HOUSE_ODD_M : number
	housePos : function(box : {number}, con : {number}) : {number}, string, boolean
	ENTRY_FILE : string
	ENTRY_CASE : SquareStressJunctionCase
	ENTRY_REACH : number
	ENTRY_FAR_CLEAR : number
	ENTRY_IN_REACHES : {number}
	ENTRY_RINGS : {integer}
	ENTRY_RING_LANES : {integer}
	ENTRY_RING_RADIUS : {number}
	ENTRY_FROM_YEAR : integer
	ENTRY_MIN_JOIN : number
	ENTRY_SCAN : number
	ENTRY_ROLE_COS : number
	ENTRY_LINK_LANES : integer
	entryOutward : function(tx : number, ty : number, sx : number, sy : number) : {number}
	drivingSide : function(forwards : {boolean}) : string
	axisIndex : function(v : {number}) : integer
	entryRoles : function(cx : number, cy : number, out : {number}, pts : {{number}}) : {string : integer}, string
	entryLine : function(id : string, town : string, kind : string, detail : string) : string
	nodeAt : function(cands : {SquareStressNodeCand}, pt : {number}, tol : number) : SquareStressNodeCand
	ownTownNodes : function(cands : {SquareStressNodeCand}, area : SquareStressLockArea) : {SquareStressNodeCand}
	showcaseSummary : function(built : {string : integer}, planned : {string : integer}, builtAb : {string : integer},
		plannedAb : {string : integer}, linked : integer, links : integer, lines : integer, seed : integer, skipped? : integer,
		spec? : SquareStressShowcaseSpec) : string

	-- Hide all notifications
	NOTIFICATION_GUI_TYPES : {string}
	notificationPayload : function(on : boolean, typeNames : {string}) : {string : any}
end

--- A line and the vehicle to copy for it (its first vehicle; nil when the line has none).
global record SquareStressLineVehicle
	line : integer
	vehicle : integer
end

--- A town spawn size: initial land use capacity per district and the spacing between new towns.
global record SquareStressTownSize
	label : string
	caps : integer
	spacing : number              -- metres between new towns and to existing ones
end

--- A test grid layout (stress_logic.GRID_LAYOUTS).
global record SquareStressGridLayout
	label : string
	cols : integer
	rows : integer
end

--- One town centre of a test grid (stress_logic.gridPositions).
global record SquareStressGridPoint
	x : number
	y : number
	name : string                 -- "Grid A1": row letter, column number
	row : integer
	col : integer
	size : integer                -- Showcase: its own TOWN_SIZES index (nil: the batch's size)
	pop : number                  -- light plans A/B: the people it grows to (nil: the spec's growTarget)
	townCaps : integer            -- its initial land use capacities when below its size's (the grid stays the size's; nil: the size's)
end

--- Crossing test: one crossing (stress_crossing construction) of the layout.
global record SquareStressCrossingJunction
	id : string                   -- "x12" (row 1, column 2), "w1" (west collector, row 1), ...
	x : number
	y : number
	angle : number                -- radians: the construction's local x (main road)
	shape : integer               -- stress_crossing.SHAPES: 1 X, 2 T
	main : integer                -- stress_crossing.ROADS index
	side : integer
	label : string
end

global record SquareStressCrossingLink
	a : string                    -- junction id and arm direction ("E", "N", "W", "S")
	aDir : string
	b : string
	bDir : string
end

global record SquareStressCrossingTown
	name : string
	x : number
	y : number
	from : string                 -- the junction whose arm `dir` links to this town
	dir : string
end

global record SquareStressCrossingLayout
	junctions : {SquareStressCrossingJunction}
	links : {SquareStressCrossingLink}
	towns : {SquareStressCrossingTown}
end

--- One junction of the junction test (stress_logic.JUNCTION_CASES): a square_roundabouts construction
--- (file under JUNCTION_DIR) and the params that differ from its defaults (1-based indices).
global record SquareStressJunctionCase
	id : string
	label : string
	file : string
	params : {string : number}
end

--- A Junctions choice of the junction test: the ids of the cases it builds.
global record SquareStressJunctionSet
	label : string
	ids : {string}
end

--- Showcase (stress_logic.showcaseLayout): a seeded PRNG (Park-Miller, exact in Lua 5.1 doubles).
global record SquareStressRng
	state : integer
end

--- One param a Showcase type draws per placement: its key and the 1-based indices it may take.
global record SquareStressShowcaseRange
	key : string
	values : {integer}
end

--- A Showcase construction type: a square_roundabouts file (or our plain crossing), fixed params and drawn ranges.
global record SquareStressShowcaseType
	id : string
	label : string
	file : string
	kind : string                 -- "ix" interchange (highway arms), "rb" roundabout, "plain" game crossing
	slot : string                 -- Lights showcase shapes: their kind slot ("x" crossroads, "t" T-junctions)
	fixed : {string : number}
	ranges : {SquareStressShowcaseRange}
	armKey : string               -- the arm road param (roundabouts; interchanges: the cross road), nil for plain
	short : string                -- its word in Showcase town names ("Ring IX"; nil: label)
end

--- One Showcase construction: its case (params drawn), centre, angle (radians, local x) and reach (m).
global record SquareStressShowcasePlacement
	case_ : SquareStressJunctionCase
	x : number
	y : number
	angle : number
	reach : number
	lightsOff : boolean           -- plain crossings: lights off (the game's NO), else the game decides
end

--- A Showcase group: one junction and one town per arm (indices into the layout's towns, arm order).
global record SquareStressShowcaseGroup
	name : string
	kind : string                 -- "ix", "rb", "plain"
	slot : string                 -- the spec's kind slot it was drawn for (Showcase: = kind; Lights showcase "x", "t")
	place : SquareStressShowcasePlacement
	towns : {integer}
	oneWay : {integer : boolean}  -- arm positions on a one-way road (no bus line)
	R : number                    -- the room it keeps from other groups (m)
	set : integer                 -- its twin set (the drawn group: "Group 3a" / "3b" are set 3)
	twin : string                 -- "a", "b", "c", "d"
	ab : string                   -- A/B mode (SHOWCASE_AB / LIGHTS_AB): "sl", "game", "sl_phases", "sl_lock" (Lights
	                              -- showcase's fourth twin since 2026-10-13), "sl_fan" (its fourth twin before; still read), "sl_exitfan" (the mixed Lights showcase's third twin, e)
	test : string                 -- bench (BENCH.md): its test id
	variant : string              -- bench: its variant label
	litYes : boolean              -- bench: a lit plain crossing (a light set to Yes at the read when none stands)
	linkLanes : integer           -- bench: its links' road lanes (0: the arm's own lanes; nil: the spec's linkLanes)
	pairLanes : integer           -- bench: a highway arm's merge piece, country road of this many road lanes (nil: 6)
	geom : string                 -- bench: its ring geometry when the test has twins on two ("plain" / "mid", Sheet 4 v5)
	demand : string               -- light plans A/B (demandMix): "balanced" / "unbalanced" (its set's; nil: none)
	mix : string                  -- bench Sheet 5: its set's traffic mix ("even" / "straight" / "adjacent"; nil: none)
	ringMix : boolean             -- bench Sheet 5: the traffic log logs its ring's turning mix and lane use (RINGMIX / RINGLANE)
end

--- A variant of the shared Showcase code (stress_logic SHOWCASE_SPEC, LIGHTS_SPEC). nil fields: the
--- Showcase's own tables, read at call time.
global record SquareStressShowcaseSpec
	id : string                   -- job and log name: "showcase", "lights_showcase"
	title : string                -- dialogs and the summary: "Showcase", "Lights showcase"
	kinds : {string}              -- kind slots in turn (nil: SHOWCASE_KINDS)
	types : {string : {SquareStressShowcaseType}}  -- slot -> its types in turn (nil: showcaseTypes(slot))
	kindLog : {string : string}   -- slot -> its key on the summary log line ("interchanges")
	kindWords : {string : string} -- slot -> its words in the summary sentence ("plain junctions")
	modes : {SquareStressShowcaseAb}  -- the twins (nil: SHOWCASE_AB)
	size : integer                -- TOWN_SIZES index of every town, never drawn (nil: SHOWCASE_SIZE)
	townR : number                -- town clearance factor (nil: SHOWCASE_TOWN_R)
	misses : integer              -- a slot stops after this many misses in a row (nil: SHOWCASE_MISSES)
	litOnly : boolean             -- every crossing lit (never drawn off; Yes asked in the construction)
	growFactor : number           -- after the links every town grows x this (nil: no growth)
	growPasses : integer          -- in this many build-out passes
	lockStreets : boolean         -- every street of the towns roadDevelopmentLocked (grid, seed streets, links), stubs removed
	denseWeights : {number}       -- building level weights 1..4 sent before the growth (nil: the town's own)
	modeNames : boolean           -- town names "<mode> <set> <side>" (Lights showcase); else "<type> <set> <side> (<mode>)"
	square : boolean              -- exact square layout (Lights showcase): crossings at 90 deg, never turned, towns on the arms' axes at one distance, links straight to the middle of the grid's facing side
	noBusLines : boolean          -- no bus lines after the build (Lights showcase)
	entries : boolean             -- a roundabout at each town's entry (Lights showcase; SHOWCASE.md "Town entries")
	linkLanes : integer           -- link pieces: the country road of this many road lanes (nil: the arm's own)
	shape : integer               -- Lights showcase: its shape (index into LIGHTS_SHAPES; nil: every shape, lightsMixedSpec)
	shapeLabel : string           -- Lights showcase: "2x2 X", ... (nil: mixed)
	perType : integer             -- at most this many sets of each type (nil: as many as fit; the Lights showcase: 3)
	alternateTwins : boolean      -- every second set's twins placed in reverse order (the Lights showcase)
	demandMix : boolean           -- light plans A/B: balanced and unbalanced sets in turn (lightsPlansDemand, lightsPlansTownPop)
	growTarget : number           -- grow every town to about this many people (its own factor from its population; nil: growFactor for all)
	variant : string              -- " variant=<it>" on the run's first log line ("light_plans"; nil: none)
	bench : boolean               -- a bench sheet (stress_bench.spec): per-group lights / link lanes, lit counts on the built lines
	layoutFn : function(w : number, h : number, margin : number, seed : integer) : SquareStressShowcaseLayout  -- the layout instead of showcaseLayout
end

--- One bench test (stress_bench.tl; BENCH.md "The spec format").
global record SquareStressBenchTest
	id : string                   -- short [%w_] id: the zone lines' test=
	title : string
	variants : {SquareStressShowcaseType}  -- one per set in turn (fixed params, no ranges)
	towns : {string}              -- compass points of the arms that get a town (rotation 0)
	twins : {string}              -- zone ab names, in letter order
	compare : {{string}}          -- the report's comparisons {a, b}: a minus b
	geoms : {string : integer}    -- twins "<ab>@<geom>": geom -> its variant's index (Sheet 4 v5); nil: every twin the set's variant
	sets : integer                -- sets wanted
	litYes : boolean              -- a lit plain crossing (a light set to Yes at the read when none stands)
	linkLanes : integer           -- link pieces' road lanes (0: the arm's own)
	pairLanes : integer           -- a highway arm's merge piece: the country road of this many road lanes (nil: 6)
	mixes : {string}              -- traffic mixes, one per set in turn (bench.LU_MIXES; nil: every town the sheet's pop)
	ringMix : boolean             -- its twins' traffic log zones log RINGMIX / RINGLANE (ring turning mix, lane use)
	pops : {string : number}      -- the mixes' town sizes (large / small / even; nil: bench.LU_POPS; Sheet 6: bench.HM_POPS)
end

--- The city run's cities (stress_bench.CITY.city).
global record SquareStressBenchCityOpts
	pairs : integer               -- auto + control pairs (without control: auto cities)
	size : integer                -- TOWN_SIZES index
	pop : number                  -- people a city grows to
	spacing : number              -- m between neighbouring city centres
	control : boolean             -- a never-enrolled control city beside each auto city
	layout : string               -- "plain" | "hourglass" | "holes" (stress_grid_streets.lua LAYOUTS; nil: plain)
	busy : boolean                -- the Busy option (bench.CITY_BUSY: more people, denser weights)
	swap : boolean                -- Swap roles: the other city of each pair is the auto one
	weights : {number}            -- level 1..4 weights of the size command (nil: logic.DENSE_WEIGHTS)
end

--- The City lights options as picked in the window (stress_bench_run br.cityUi; bench.citySheet makes the sheet).
global record SquareStressBenchCityUi
	layout : integer              -- bench.CITY_LAYOUTS index
	busy : boolean
	baseline : integer            -- bench.CITY_BASELINES index
	swap : boolean
	sameSeed : boolean            -- the last city run's seed again (its holes; the Swap roles rerun)
end

--- A street grid's layout (stress_grid_streets.lua grid.layout).
global record SquareStressStreetLayout
	name : string                 -- "plain" | "hourglass" | "holes"
	n : integer                   -- blocks per side
	step : number
	half : number
	removed : {string : boolean}  -- left-out segments "h:i:j" / "v:i:j"
	gaps : {{number}}             -- {x0, y0, x1, y1} relative to the center
	holes : {{integer}}           -- hole centers {i, j} (grid line indices)
	neck : integer                -- neck streets (hourglass), else 0
	pattern : integer             -- the holes pattern (holes), else 0
	x4 : integer                  -- inner crossings with 4 streets
	t3 : integer                  -- ... with 3 (T at the neck / a hole's edge)
	gone : integer                -- inner grid points with no street
	crossings : integer           -- x4 + t3
end

--- The street grid geometry (stress/stress_grid_streets.lua, plain Lua: the construction's updateFn uses it too).
global record SquareStressGridStreets
	LAYOUTS : {string}
	HOLE_PATTERNS : integer
	HOLE_COUNT : integer
	layout : function(half : number, layout : any, pattern? : integer, block? : number) : SquareStressStreetLayout
	inGap : function(L : SquareStressStreetLayout, px : number, py : number) : boolean
end

--- The extra keys of a CITY line (stress_bench.cityLine): the layout and the crossings per kind.
global record SquareStressCityLineExtra
	layout : string
	neck : integer
	holes : integer
	found4 : integer
	found3 : integer
	lit4 : integer
	lit3 : integer
	pop : integer                 -- the town's people (residential capacity) at the lights (nil: unread)
	gapStreets : integer          -- streets found in the layout's gaps after the lock (removed: gapRemoved)
	gapRemoved : integer
end

--- One city of the city run (stress_bench.cityPlan): offsets from the map centre.
global record SquareStressBenchCity
	id : string                   -- zone id "cityg1v" (auto) / "cityg1b" (control)
	pair : string                 -- "cityg1"
	role : string                 -- "auto" | "control"
	ab : string                   -- the zone's ab: city_auto | city_control (never sent to Smart Lanes)
	x : number
	y : number
	name : string                 -- "City auto 1"
	half : number                 -- the wide grid's half side
	pop : number
	crossings : integer           -- the grid's inner crossings (4-way and, in a funnel layout, 3-way)
	layout : string               -- the grid's layout (plain / hourglass / holes)
end

--- The city run's last build (gui/stress_citylights.tl cl.last): its cities and their inner crossings {node, x, y}.
global record SquareStressCityLightsLast
	plan : SquareStressBenchCityPlan
	crossings : {integer : {{number}}}
	run : string
	layout : SquareStressStreetLayout   -- the cities' street grid layout (gapCheck)
	cx : number                       -- the map center the cities are placed around
	cy : number
	created : {integer : integer}     -- city index -> town
end

--- The city run's build (gui/stress_citylights.tl).
global record SquareStressCityLights
	build : function(sheet : SquareStressBenchSheet, seed : integer, onDone : function(zones : {SquareStressShowcaseZone}), onAbort : function(why : string)) : boolean
	enroll : function(sheet : SquareStressBenchSheet, run : string, crossings : {integer : {{number}}}, plan : SquareStressBenchCityPlan) : integer
	unenroll : function()
	gapCheck : function(label : string) : integer
	last : SquareStressCityLightsLast
end

--- The city run's cities on a map.
global record SquareStressBenchCityPlan
	cities : {SquareStressBenchCity}
	auto : integer
	control : integer
	crossings : integer           -- inner crossings in all
	enrolled : integer            -- of them in the auto cities
	persons : number
	half : number
	layout : string               -- plain / hourglass / holes
	neck : integer                -- neck streets (hourglass)
	holes : integer               -- holes per city (holes)
	x4 : integer                  -- per city: 4-way inner crossings
	t3 : integer                  -- per city: 3-way inner crossings
	swap : boolean
	busy : boolean
end

--- One bench sheet: one map, one press.
global record SquareStressBenchSheet
	id : string                   -- job / log name: "bench_s1"
	key : string                  -- "s1"
	title : string
	version : integer             -- BENCH_START spec=<id>@<version>
	minKm : number                -- the map side it is planned for
	slLights : boolean            -- needs Smart Lanes' "No lights at roundabouts and ramps" On
	tests : {SquareStressBenchTest}
	button : string               -- its button's label (nil: "Sheet <n>" from its key)
	pop : number                  -- people per town (nil: bench.POP)
	pool : boolean                -- the report pools every test's pairs of one comparison (the micro bench)
	roundRobin : boolean          -- the packer places one set of every test in turn (else every set of a test, then the next)
	rank : boolean                -- the report ranks every twin mode per test (the micro bench's ring layouts)
	recordS : number              -- game s recorded (nil: bench.RECORD_S)
	speed : integer               -- the record's game speed (nil: bench.SPEED)
	city : SquareStressBenchCityOpts  -- the city run (bench.CITY): cities instead of tests
	baselineS : number            -- the city run: game s of the record before the enroll
	shotDist : number             -- the screenshots' camera height (nil: 130 m over a junction)
end

--- The micro bench's swappable block (stress_bench.MICRO).
global record SquareStressBenchMicro
	version : integer
	title : string
	pop : number
	pool : boolean
	roundRobin : boolean
	rank : boolean
	tests : {SquareStressBenchTest}
end

global record SquareStressBenchTestPlan
	test : SquareStressBenchTest
	wanted : integer
	sets : integer
	groups : integer
	towns : integer
end

--- A sheet packed onto a map (stress_bench plan).
global record SquareStressBenchPlan
	sheet : SquareStressBenchSheet
	layout : SquareStressShowcaseLayout
	tests : {SquareStressBenchTestPlan}
	groups : integer
	towns : integer
	persons : integer
	drivers : integer
	buildMin : number
	cut : {string}                -- "rb4: 7 of 9 sets"
	problems : {string}           -- variants without a usable shape
end

--- One placed (or candidate) bench group's points (stress_bench packer): its junction, reach, town centres
--- (its links run from the junction to each) and their box.
global record SquareStressBenchFoot
	jx : number
	jy : number
	reach : number
	towns : {{number}}
	x0 : number
	x1 : number
	y0 : number
	y1 : number
end

--- A bench variant's group shape (centre 0, 0): the case, its reach, the arms with towns (degrees), their town
--- offsets and compass points, the town distance and a signature (the packer's cursor key).
global record SquareStressBenchShape
	case_ : SquareStressJunctionCase
	reach : number
	degs : {number}
	offsets : {{number}}
	sides : {string}
	dist : number
	sig : string
end

--- Smart Lanes' settings as the bench reads them (stress_bench.slSettings).
global record SquareStressBenchSl
	auto : boolean
	lights : boolean
	freeTurn : string
	phases : string
	perf : boolean                -- its "Debug: performance log" On (SQPERF window lines)
end

--- The bench preflight's reads (stress_bench.problems / startLine).
global record SquareStressBenchInfo
	w : number
	h : number
	plan : SquareStressBenchPlan
	busy : string
	needsRb : boolean
	rbOk : boolean
	slPresent : boolean
	sl : SquareStressBenchSl
	slModes : {string}            -- nil: Smart Lanes reported none (older, or no answer)
	paused : boolean              -- the game speed is 0
	year : integer
	cityPlan : SquareStressBenchCityPlan  -- the city run's cities on this map (nil: they do not fit, cityWhy)
	cityWhy : string
	perfAll : boolean             -- the DEV master switch square_sqperf_all is active
end

--- The bench run (gui/stress_bench_run.tl): one sheet from the press to BENCH_DONE.
global record SquareStressBenchRun
	phase : string                -- "idle", "ack", "clear", "year", "build", "sl_idle", "warmup", "record", "stop", "shots"
	last : string                 -- the last run's closing words (the window's status after it)
	status : function() : string
	running : function() : boolean
	planLine : function(key : string) : string
	check : function(key : string) : {string}
	start : function(key : string, seed? : integer) : boolean, string
	cityUi : SquareStressBenchCityUi          -- the City lights options (the window's rows)
	lastCitySeed : integer                    -- the last city run's seed (Same seed)
	sheetFor : function(key : string) : SquareStressBenchSheet
	cityUiSignature : function() : string
end

--- The bench's pure part (stress/stress_bench.tl).
global record SquareStressBench
	VERSION : integer
	STEP : number
	LINK_TOWN : number
	LINK_JUNCTION : number
	LINK_LINK : number
	BUCKET : number
	SIZE : integer
	POP : integer
	PERSONS_PER_TOWN : integer
	DRIVER_SHARE : number
	BUILD_S_PER_TOWN : number
	AB : {string : SquareStressShowcaseAb}
	VARIANTS : {string : SquareStressShowcaseType}
	MICRO : SquareStressBenchMicro
	RING_MODES : {string}
	MID_TWINS : {string}
	MID_LETTER : {string : string}
	PLAIN_MID_TWINS : {string}
	PLAIN_MID_COMPARE : {{string}}
	PLAIN_MID_COMPARE2 : {{string}}
	twinMode : function(string) : SquareStressShowcaseAb
	LU_MIXES : {string}
	LU_POPS : {string : number}
	LU_SIDES : {string : {string : string}}
	mixPop : function(mix : string, side : string, pops? : {string : number}) : number, string
	HM_POPS : {string : number}
	CITY : SquareStressBenchSheet
	CITY_BLOCK : number
	CITY_SNAP : number
	CITY_ZONE_LETTER : {string : string}
	CITY_AB : {string : string}
	CITY_EVENT_MAX : integer
	cityLines : function(half : number) : {number}, number
	cityPlan : function(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet) : SquareStressBenchCityPlan, string
	cityInterior : function(nodes : {{number}}, cx : number, cy : number, half : number, minDeg? : integer) : {{number}}
	cityPayloads : function(entries : {{number}}) : {{string : any}}
	cityZone : function(c : SquareStressBenchCity) : SquareStressShowcaseZone
	cityLine : function(c : SquareStressBenchCity, x : number, y : number, town : integer, found : integer, litBefore : integer, forced : integer, refused : integer, extra? : SquareStressCityLineExtra) : string
	cityEnrollLine : function(run : string, op : string, cities : integer, nodes : integer, events : integer, baselineS : number, sl : boolean, sheet? : SquareStressBenchSheet) : string
	CITY_LAYOUTS : {string}
	CITY_LAYOUT_LABELS : {string}
	CITY_BASELINES : {number}
	CITY_BASELINE_LABELS : {string}
	CITY_AFTER_S : number
	CITY_BUSY : SquareStressBenchCityOpts
	citySheet : function(ui : SquareStressBenchCityUi) : SquareStressBenchSheet
	cityLayout : function(sheet : SquareStressBenchSheet, seed? : integer) : SquareStressStreetLayout
	cityHolesPattern : function(seed : integer) : integer
	cityOptionKeys : function(sheet : SquareStressBenchSheet) : string
	cityOptionsText : function(sheet : SquareStressBenchSheet) : string
	cityGapLine : function(c : SquareStressBenchCity, label : string, found : integer, removed : integer) : string
	cityPlanText : function(p : SquareStressBenchCityPlan, why : string, w : number, h : number) : string
	recordS : function(sheet : SquareStressBenchSheet) : integer
	speed : function(sheet : SquareStressBenchSheet) : integer
	setMix : function(t : SquareStressBenchTest, k : integer) : string
	MID_COMPARE : {{string}}
	SHEETS : {SquareStressBenchSheet}
	sheet : function(key : string) : SquareStressBenchSheet
	shape : function(v : SquareStressShowcaseType, sides : {string}) : SquareStressBenchShape, string
	clear : function(f : SquareStressBenchFoot, g : SquareStressBenchFoot) : boolean
	plan : function(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet, seed? : integer) : SquareStressBenchPlan
	modes : function(sheet : SquareStressBenchSheet) : {SquareStressShowcaseAb}
	needs : function(sheet : SquareStressBenchSheet) : {string}
	spec : function(sheet : SquareStressBenchSheet) : SquareStressShowcaseSpec
	testLine : function(sheet : SquareStressBenchSheet, tp : SquareStressBenchTestPlan) : string
	planText : function(p : SquareStressBenchPlan, w : number, h : number) : string
	YEAR : integer
	WARMUP_S : integer
	RECORD_S : integer
	INTERVAL : integer
	SPEED : integer
	SL_KEYS : {string : string}
	slSettings : function(raw : {string : any}) : SquareStressBenchSl
	problems : function(sheet : SquareStressBenchSheet, info : SquareStressBenchInfo) : {string}
	startLine : function(sheet : SquareStressBenchSheet, info : SquareStressBenchInfo, seed : integer) : string
end

--- A Showcase town's grid for the street lock and the leak check (stress_towns lockTowns / densify).
global record SquareStressLockArea
	town : integer                -- town entity
	label : string                -- its name for the log
	x : number                    -- grid (and town) centre
	y : number
	half : number                 -- half the grid's side (logic.gridHalfOfSize)
	reach : number                -- its streets are looked for this far from its centre at least (its junction's distance; nil: half x 1.41 + LOCK_REACH)
	zones : {{number}}            -- its junctions' zones {x, y, r}: every street there is locked, whatever its closest town (lock passes, leak checks)
	target : number               -- light plans A/B: its own growth target (people; nil: the density job's target)
end

--- One step of a density job (logic.denseSteps).
global record SquareStressDenseStep
	kind : string                 -- "weights", "grow", "final"
	town : integer                -- index into the areas
	pass : integer
end

--- Options of SquareStressTowns.lockTowns.
global record SquareStressLockOpts
	pass : string                 -- log label: "towns" (after the towns), "links" (after the links)
	stubs : boolean               -- also remove the grid corner stubs no link uses
	onDone : function(ms : number)  -- after the summary line (the run's timing)
end

--- Options of SquareStressTowns.densify.
global record SquareStressDenseOpts
	factor : number               -- size factor multiplier (pass 1; later passes re-send; with target: the fallback)
	target : number               -- each town's factor for about this many people from its capacity target (growFactorForCap; nil: factor for all)
	passes : integer
	weights : {number}            -- level weights 1..4 (nil: none sent)
	onDone : function(ms : number)  -- after the dense summary line (the run's timing)
end

--- One A/B mode of the Showcase twins (stress_logic.SHOWCASE_AB).
global record SquareStressShowcaseAb
	ab : string
	twin : string
	label : string                -- its words in Showcase town names: "Smart lanes", "Game default", ...
	note : string
	litPlainOnly : boolean        -- only for a plain crossing with lights
	geom : string                 -- bench twins "<ab>@<geom>" (bench.twinMode): the ring geometry, nil otherwise
end

--- A Showcase group's zone with its A/B mode (stress_logic.showcaseZones; FLOW.md "Showcase zones").
global record SquareStressShowcaseZone
	id : string                   -- "g3a"
	pair : string                 -- "g3"
	ab : string
	kind : string
	label : string
	x : number
	y : number
	r : number
	towns : integer
	reason : string               -- nil: the set's twins match as built; else why not ("town", "redrawn", "town,redrawn")
	built : boolean               -- its zone line was written (built and read); the traffic log samples only these
	arms : {{number}}             -- its arms' measured headings {hx, hy} (the read's clusters; the traffic log's corridors)
	test : string                 -- the bench test it belongs to (BENCH.md; nil outside a bench)
	variant : string              -- the bench variant label
	geom : string                 -- the bench twin's ring geometry ("plain" / "mid"; nil: the test has one)
	approach : number             -- square layouts: its straight approach length along every arm (m; logic.groupApproach; thru)
	demand : string               -- light plans A/B: its set's demand ("balanced" / "unbalanced"; nil: none)
	mix : string                  -- bench Sheet 5: its set's traffic mix (nil: none)
	ringMix : boolean             -- bench Sheet 5: RINGMIX / RINGLANE for its ring
end

--- One twin of a Showcase set as built (stress_logic.showcaseMatch).
global record SquareStressShowcaseTwin
	built : boolean
	redrawn : boolean             -- the check refused its planned draw and it was redrawn
	params : string               -- its params as built (showcaseParamText)
end

global record SquareStressShowcaseLayout
	seed : integer
	square : boolean              -- the spec's square layout (towns on the arms' axes, straight links: approach lengths)
	idPrefix : string             -- a bench sheet's key ("s1"): its zone ids "s1g3a", pairs "s1g3" (nil: "g3a")
	towns : {SquareStressGridPoint}   -- offsets from the map centre, "Grid S1", ..., each with its size
	groups : {SquareStressShowcaseGroup}
end

--- One grid cell of the junction test: its centre and its corner towns (indices into the grid's
--- points: south-west, south-east, north-east, north-west).
global record SquareStressJunctionCell
	x : number
	y : number
	name : string                 -- "Cell A1"
	corners : {integer}
end

--- Arm ends of a built junction that belong together (a highway's two carriageways), with their
--- centroid (stress_logic.clusterEnds).
global record SquareStressArmCluster
	members : {integer}           -- indices into the ends list
	x : number
	y : number
	hx : number                   -- measured heading (unit vector, the way its road leaves the junction); nil: unknown
	hy : number
end

--- A town street node a junction arm may be linked to.
global record SquareStressNodeCand
	id : integer
	x : number
	y : number
	z : number
	deg : integer                 -- street edges at the node
	large : boolean               -- on a large two-way street (logic.isLargeStreet)
	score : number                -- set by rankTownNodes
end

--- Options of SquareStressTowns.createGrid.
global record SquareStressGridOpts
	name : string                 -- log name ("grid_3x3")
	label : string                -- progress label
	cols : integer
	rows : integer
	spacing : number
	size : SquareStressTownSize
	useCamera : boolean           -- centre on (cx, cy), else the map centre
	cx : number
	cy : number
	connect : integer             -- index into GRID_CONNECT
	streets : integer             -- index into GRID_STREETS (1 the town's own, 2 our wide grid first, 3 locked)
	points : {SquareStressGridPoint}  -- instead of cols x rows: these points (x, y offsets from the centre, name)
	skipNoLand : boolean          -- a point that fails the land check is skipped (logged), not the whole grid cancelled (Showcase)
	batch : boolean               -- batched: grids GRID_BATCH per proposal, their locks across towns, every town in one command (each falls back to one by one)
	gridLayout : integer          -- our street grid's layout param (stress_grid_streets.lua LAYOUTS index; nil: plain)
	gridHoles : integer           -- its holes pattern (layout 3)
end

--- A placement relaxation step (stress_logic.PLACE_STEPS).
global record SquareStressPlaceStep
	label : string
	dist : number                 -- fraction of the size's spacing (at least MIN_TOWN_DIST)
	widen : number                -- near camera: candidate count multiplier (more rings)
	fine : boolean                -- spread over map: grid step = the step's distance, not the coarse grid
end

--- One placement step as tried (stress_logic.placeRelaxed), for the log.
global record SquareStressPlaceTry
	label : string
	minDist : number
	candidates : integer
	placed : integer
	skipped : {string : integer}
end

--- A town entity and its position (Map.Town pos from makeMapFromGame).
global record SquareStressTownPos
	id : integer
	x : number
	y : number
	half : number                 -- route lines: half-size of the town's square street grid (m); nil: no grid
end

--- Options for SquareStressRuntime.enqueue.
global record SquareStressJobOpts
	delayMs : number
	quiet : boolean
	serial : boolean
	label : string
	timeoutMs : number
	maxPerTick : integer
end

--- A warning for the window's dialog (rt.warn).
global record SquareStressWarning
	title : string
	body : string
end

--- GUI-state runtime shared by the HUD script and the probes (gui/stress_runtime.tl). One instance per
--- GUI Lua state (the require cache); nothing is saved.
global record SquareStressRuntime
	queue : SquareStressQueue
	version : integer             -- bumped on every new log line or queue change (window refresh)
	recent : {string}             -- the last log lines, newest last
	warnings : {SquareStressWarning}  -- not yet shown in a dialog (the HUD pops them)
	keepBalance : boolean         -- Game tab toggle: keep the balance above KEEP_BALANCE
	hideNotifications : boolean   -- Game tab toggle, default true each session (sent on the first tick)
	notificationsSent : boolean   -- the current hideNotifications state was sent to the game script
	drivingSide : string          -- "right" / "left" as the Lights showcase read it from a grid street (nil: not read; the traffic log assumes right)
	KEEP_BALANCE : integer
	PER_FRAME : integer

	nowUs : function() : integer
	log : function(msg : string)
	--- A node's config with edges re-pointed (newIds) and dropped (gone), and the change count.
	nodeConfigEntry : function(node : integer, newIds : {integer : integer}, gone : {integer : boolean}) : Proposal.BaseNodeLaneConnectionAndEntity, integer
	--- Logs and queues a warning for a dialog.
	warn : function(title : string, body : string)
	probe : function(name : string, ok : boolean, details : string)
	enqueue : function(name : string, total : integer, step : function(i : integer, job : SquareStressJob), opts? : SquareStressJobOpts) : SquareStressJob
	later : function(name : string, delayMs : number, fn : function())
	--- onDone gets the command's resultEntities as a third argument (api/tealdef/api/cmd.d.tl:598-600).
	send : function(name : string, cmd : any, onDone? : function(success : boolean, data : any, resultEntities : {{integer}}))
	--- stdout.txt only (per-item detail lines), not the window log.
	detail : function(msg : string)
	tick : function()
	camera : function() : number, number
	--- A queued or running job whose name starts with one of the prefixes (button debounce), else nil.
	busyJob : function(prefixes : {string}) : string
	TEST_JOBS : {string}          -- job-name prefixes of the Junction / Crossing test and Showcase builds
	--- The entity exists and still has a TRANSPORT_VEHICLE / LINE component (guards before commands).
	isVehicle : function(e : integer) : boolean
	isLine : function(e : integer) : boolean
	--- PLAYER_OWNED.player is the player (true when unreadable).
	ownedByPlayer : function(e : integer) : boolean
	player : function() : integer
	balance : function() : integer
	book : function(amount : number)
	--- Sets "Hide all notifications" and sends it to the base Notifications game script.
	setHideNotifications : function(on : boolean)
	--- Called every frame from tick (Main Thread) before the queue runs, each pcall'd.
	addTickHook : function(fn : function(nowUs : integer))
	tickHooks : {function(nowUs : integer)}
	--- Drops every queued job (the Clear queue button); returns how many. Bumps queueClears.
	clearQueue : function() : integer
	queueClears : integer
	lines : integer               -- log lines written (rt.log / rt.detail): the bench build watchdog
end

--- One street segment as seen from a node (gui/stress_nodecfg.tl): its road lanes in LaneConnection indices
--- (zero-based incl. the sidewalks, left to right looking from the node into the segment), outer lane first.
global record SquareStressNodeSide
	ins : {integer}               -- lanes arriving at the node
	outs : {integer}              -- lanes leaving it
	tram : {integer : boolean}    -- lane index -> carries a tram track
	lanes : integer               -- lane count incl. sidewalks (index bound)
	dir : {number}                -- 2D unit vector from the node into the segment; nil: unknown
end

--- A replaced node's config carried over to its new node (stress_junctions linkProposal): the old node,
--- its old edges -> the copies' temp ids.
global record SquareStressNodeSeed
	node : integer
	newIds : {integer : integer}
	ghost : SquareStressLightGhost   -- the leg a removal took from this lit node, which the link now replaces
end

--- A lit node's leg that one proposal removes and a later one replaces in the same direction (Lights showcase
--- town entries: the side-middle street at a far grid node, then the roundabout arm's join). Read before the
--- removal (nc.ghost); the replacement's config (nc.configs via a seed's ghost) gives the new leg's
--- connections the old leg's per-phase states and re-adds its crosswalk.
global record SquareStressLightGhost
	leg : integer                  -- the removed edge
	conns : {{integer}}            -- the node's connections before the removal {s0, l0, s1, l1}, in order
	cws : {integer}                -- its crosswalks before the removal (edge ids), in order
	locked : {{integer}}           -- per phase: its lockedLanes (0-based into conns, then cws)
	result : string                -- set by nc.configs: "carried", or "unmapped (why)"
end

--- A ghost applied to a replacement node's new list (nc.configs -> nc.relight / nc.remapLocked): the old
--- connections re-pointed (removed leg -> leg), per phase their locks, the re-added crosswalk.
global record SquareStressLightCarry
	old : {integer : {integer}}    -- old index (1-based) -> {s0, l0, s1, l1} re-pointed
	nOld : integer
	locked : {{integer}}           -- per phase: lockedLanes of the old list
	leg : integer                  -- the new leg (temp edge id)
	cwIndex : integer              -- 0-based phase index of its re-added crosswalk (nil: none re-added)
	cwLocked : {boolean}           -- per phase: whether the removed leg's crosswalk was locked
end

--- Node configs for script street proposals (gui/stress_nodecfg.tl). Script-made nodes get no
--- BASE_NODE_CONFIG, and such a node can crash the simulation at random (docs/findings/towns.md).
global record SquareStressNodeCfg
	--- A segment's side at its end atEnd (0 = node0, 1 = node1) from its laneConfigs; nil laneConfigs or
	--- unreadable: a two-way street of `lanes` (default 4) lanes.
	side : function(laneConfigs : any, atEnd : integer, lanes? : integer) : SquareStressNodeSide
	--- Lane connections of a node with these segments: every ordered pair a ~= b, in_a[k] -> out_b[k]
	--- (outer with outer; the engine's town-junction pattern for two-way streets), none between two
	--- segments leaving the node within 30 deg of each other (a reversal), and pairs whose both segments
	--- are in `covered` left out (kept from an old config). Plain {segment0, lane0, segment1, lane1, withTram}.
	pattern : function(segs : {integer}, sides : {integer : SquareStressNodeSide}, covered? : {integer : boolean}) : {{integer}}
	--- The engine's two-way pattern with lane counts per segment (incl. sidewalks), as LaneConnections.
	junctionConns : function(segs : {integer}, lanes : {integer : integer}) : {LaneConnection}
	--- A config for a node the proposal adds: junctionConns (empty on a 1-edge node).
	newNodeConfig : function(node : integer, segs : {integer}, lanes : {integer : integer}) : Proposal.BaseNodeLaneConnectionAndEntity
	--- Light phase remap for a changed connection list (lockedLanes: 0-based indices into the connections,
	--- then the crosswalks). old: old index (1-based) -> {s0, l0, s1, l1} re-pointed, nil when dropped;
	--- new: the written list; cwMap: old crosswalk k -> new position. Kept connections keep their state, new
	--- ones take their movement's, else their approach's, else unlocked; dropped ones vanish.
	--- carry/phase (a replaced leg, SquareStressLightCarry): a connection of the new leg takes the removed
	--- leg's state for its movement (else its approach) in that phase before the rules above.
	remapLocked : function(old : {integer : {integer}}, nOld : integer, new : {{integer}}, cwMap : {integer : integer},
		nCwOld : integer, locked : {integer}, carry? : SquareStressLightCarry, phase? : integer) : {integer}
	--- Writes cfg's phases re-pointed (remapLocked) on a clone onto entry.comp: phases written, 0 without a
	--- light, -1 when re-pointing failed and states = {} (the game's default) was written instead.
	--- carry: a replaced leg's states (remapLocked) and its re-added crosswalk's locks per phase.
	relight : function(entry : Proposal.BaseNodeLaneConnectionAndEntity, cfg : Engine.Component.BaseNodeConfig,
		old : {integer : {integer}}, nOld : integer, new : {{integer}}, cwMap : {integer : integer}, nCwOld : integer,
		carry? : SquareStressLightCarry) : integer
	--- A lit node's config before `leg` is removed from it (SquareStressLightGhost); nil without a config,
	--- without phases, or when no connection or crosswalk uses leg.
	ghost : function(node : integer, leg : integer) : SquareStressLightGhost
	--- As junctionConns, but each segment's lanes and direction read from its BaseEdge (bes[seg]: laneConfigs,
	--- node0/node1, tangents), so the pattern follows the driving side (left-hand traffic too); a segment
	--- without a readable edge falls back to the right-hand count model of lanes[seg] (default 4).
	connsAt : function(node : integer, segs : {integer}, bes : {integer : Engine.Component.BaseEdge}, lanes : {integer : integer}) : {LaneConnection}
	--- Lane count of a street edge incl. its sidewalks (4 when unreadable).
	edgeLanes : function(e : integer) : integer
	--- The configs a street proposal still lacks: every node of `edges` (the edgesToAdd list) not in
	--- `have` gets one. A new node (temp id < 0): its seed's old config re-pointed plus the pattern for
	--- the rest, else the pattern (empty with one edge). An existing node: with a config, that config
	--- (edges in `removed` dropped) plus the pattern for its new segments, listed for removal too; without
	--- one, the pattern over all its segments (add only). Returns cfgAdd and cfgRemove entries to append.
	configs : function(edges : {Proposal.SegmentAndEntity}, removed : {integer}, have : {integer : boolean},
		seeds? : {integer : SquareStressNodeSeed}) : {Proposal.BaseNodeLaneConnectionAndEntity}, {integer}
	--- Appends configs() to a proposal's lists in place (cfgAdd / cfgRm as built by the caller).
	complete : function(edges : {Proposal.SegmentAndEntity}, removed : {integer}, cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity},
		cfgRm : {integer}, seeds? : {integer : SquareStressNodeSeed})
	--- Shape check of a street proposal's configs (tests, and a log line before a send): new nodes without a
	--- config, removes without an add, existing nodes of added edges without one, lane indices out of range.
	problems : function(sp : any, lanesOf? : function(seg : integer) : integer) : {string}
end

global record SquareStressProbeDef
	id : string
	label : string
	tooltip : string
	run : function()
end

--- Probes 11a-11h "Flow" (gui/stress_probes_flow.tl, plans/square_stress_test/FLOW.md): read only.
global record SquareStressFlowProbes
	drivers : {integer}           -- the last driver sample (reused by the next probe for 20 s)
	driversUs : integer           -- rt.nowUs() when it was taken
	--- "n=.. min=.. med=.. p90=.. max=.. mean=.." of a list ("n=0" when empty).
	stats : function(values : {number}) : string
	--- "k:v,..." most frequent first, "-" when empty.
	counts : function(m : {string : integer}) : string
	--- lastMoveMode DRIVE + MOVE_PATH, not seated in a vehicle.
	isDriver : function(e : integer) : boolean
	--- street_edge | edge_other | node | construction | tn_only | other | gone | nil
	entityKind : function(e : integer) : string
	--- Appends the 11a-11h buttons to the Probe tab's list.
	addTo : function(out : {SquareStressProbeDef})
end

global record SquareStressProbes
	list : {SquareStressProbeDef}
	--- Street edges within r metres (octree BASE_EDGE + BASE_EDGE_STREET), -1 if the query failed;
	--- also the first such edge (nil if none).
	streetEdgesNear : function(x : number, y : number, r : number) : integer, integer
end

--- Towns tab selections (session only) and actions (gui/stress_towns.tl).
global record SquareStressTownsUi
	growTarget : integer          -- 1 all towns, 2 nearest to the camera
	factor : integer              -- index into GROW_FACTORS; #GROW_FACTORS + 1 = reset to x1
	passes : integer              -- index into GROW_PASSES (build-out passes per town)
	count : integer               -- index into SPAWN_COUNTS
	size : integer                -- index into TOWN_SIZES
	placement : integer           -- 1 near camera, 2 spread over the map
	connect : boolean             -- connect each new town to its nearest town by road
	gridLayout : integer          -- index into GRID_LAYOUTS
	gridSpacing : integer         -- index into GRID_SPACINGS
	gridSize : integer            -- index into TOWN_SIZES
	gridCentre : integer          -- 1 map centre, 2 camera
	gridConnect : integer         -- index into GRID_CONNECT
	gridStreets : integer         -- index into GRID_STREETS
	removeTarget : integer        -- index into REMOVE_TARGETS
end

global record SquareStressTowns
	ui : SquareStressTownsUi
	testTowns : {integer : string}  -- town entity createGrid made this session -> its name then (Remove towns > Grid towns takes it while the name is unchanged)
	--- factor nil = reset to x1 (one pass). list: these towns instead of ui.growTarget's;
	--- name: the job name (default grow_x<factor>).
	grow : function(factor : number, passes? : integer, list? : {integer}, name? : string)
	growSelected : function()                 -- grow with ui.growTarget / ui.factor / ui.passes
	selectedPasses : function() : integer     -- ui.passes as a pass count
	selectedFactor : function() : number      -- ui.factor as a factor, nil = reset
	growLabel : function() : string
	spawnLabel : function() : string
	spawn : function()
	gridLabel : function() : string
	--- Test grid: identical towns at exact grid positions, then optional roads between them.
	spawnGrid : function()
	--- The grid behind spawnGrid. onDone gets grid index -> town entity and the grid points after the
	--- last town (and after the road links are queued), and the grid indices skipped for want of land
	--- (opts.skipNoLand); not called when the grid is cancelled.
	--- Builds the wide street grid construction at (x, y) for a town of caps (lock: then marks its
	--- streets roadDevelopmentLocked), then onDone (always).
	buildStreetGrid : function(name : string, label : string, x : number, y : number, caps : integer, onDone : function(), lock? : boolean)
	--- timing: ms of its towns, grids and locks (batch; one by one: everything under towns).
	createGrid : function(opts : SquareStressGridOpts,
		onDone? : function(created : {integer : integer}, points : {SquareStressGridPoint}, skipped : {integer : boolean}, timing : {string : number}))
	removeLabel : function() : string
	--- The towns ui.removeTarget would remove now, and their names. GUI main thread (camera).
	removePlan : function() : {integer}, {string}
	--- Destroys the towns of list (default removePlan()) with their streets and buildings, one at a time.
	removeTowns : function(list? : {integer})
	setDevelopment : function(active : boolean)
	--- ignore: sensitivity 0 for noise and pollution in every town; false: reset to the defaults.
	setRatingSensitivity : function(ignore : boolean)
	readout : function() : string
	uiSignature : function() : string
	--- Every town with its position (makeMapFromGame), empty when unavailable.
	townPositions : function() : {SquareStressTownPos}
	--- One serial job: every unlocked street of each area's town (its grid and what it grew) swapped for a
	--- locked copy in bounded batches (opts.stubs: then its unused corner stubs removed); one line per town.
	lockTowns : function(name : string, areas : {SquareStressLockArea}, opts? : SquareStressLockOpts)
	--- Swaps the street edges of `list` for locked copies (bounded batches, one proposal in flight, node configs
	--- re-pointed; gone, locked or construction edges left out), then done(locked, failed, already): locked counts
	--- the edges that were roadDevelopmentLocked already (already of them). Not a job of its own.
	lockEdgeList : function(name : string, label : string, list : {integer}, done : function(locked : integer, failed : integer, already : integer))
	--- One serial job: level weights, growth passes (each followed by the leak check, which locks any new
	--- street), then every town's final check with its building levels.
	densify : function(name : string, areas : {SquareStressLockArea}, opts : SquareStressDenseOpts)
end

--- Junction test selections (session only).
global record SquareStressJunctionsUi
	set : integer                 -- index into JUNCTION_SETS
	spacing : integer             -- index into JUNCTION_SPACINGS
	size : integer                -- index into TOWN_SIZES
	centre : integer              -- 1 map centre, 2 camera
	streets : integer             -- index into GRID_STREETS
	inline : integer              -- index into JUNCTION_INLINE
	lights : integer              -- index into JUNCTION_LIGHTS
	traffic : integer             -- index into TEST_TRAFFIC (2: bus lines through the junctions after the build)
end

--- Junction test (gui/stress_junctions.tl): a town grid with a square_roundabouts junction in every
--- cell, each arm linked by road to a corner town.
global record SquareStressJunctions
	ui : SquareStressJunctionsUi
	--- Whether square_roundabouts' constructions are loaded (cached after the first answer).
	available : function() : boolean
	label : function() : string
	--- "Roundabout, Magic Roundabout, ..." of the selected set.
	caseNames : function() : string
	uiSignature : function() : string
	--- Towns, then junctions, then arm links; one command in flight. GUI main thread (camera read).
	build : function()
	--- Crossing test (stress_logic.crossingLayout): size = TOWN_SIZES index, lights 1 off / 2 game.
	crossUi : SquareStressCrossUi
	crossLabel : function() : string
	crossSignature : function() : string
	buildCrossings : function()
	--- Showcase (stress_logic.showcaseLayout): towns, then the groups. One button: a fresh seed per
	--- press (seed: a given one, tests and reproduction), Keep balance on, bus lines after the build.
	lastSeed : integer            -- the seed of the last Showcase run (nil before the first)
	showcaseSignature : function() : string
	buildShowcase : function(seed? : integer)
	--- Lights showcase (stress_logic.lightsMixedSpec): every lit shape (2x2 X, 3x3 X, 3x2 X, T 2x2) three sets
	--- each, the game and Smart Lanes twins, Medium towns grown to about LIGHTS_TARGET_POP people after the
	--- links, no bus lines. Needs only this mod. shape: that one shape with four twins (lightsSpec).
	lastLightsSeed : integer      -- the seed of the last Lights showcase run (nil before the first)
	lightsSignature : function() : string
	buildLightsShowcase : function(seed? : integer, shape? : integer)
	--- Light plans A/B (stress_logic.lightsPlansSpec): 2x2 X and 3x3 X, twins game / sl_phases / sl_auto, balanced and
	--- unbalanced sets.
	buildLightPlans : function(seed? : integer)
	--- Bench (stress_bench.tl): one sheet packed onto the map, built like the Lights showcase. false: not started.
	buildBench : function(sheet : SquareStressBenchSheet, seed? : integer) : boolean
	--- Called once a Showcase / Lights showcase / bench run is finished (its growth included): name, seed, layout, zones.
	onRunFinished : function(name : string, seed : integer, layout : SquareStressShowcaseLayout, zones : {SquareStressShowcaseZone})
	--- Called when a bench build stops early (Smart Lanes refused or did not acknowledge its zones): name, why.
	onRunAborted : function(name : string, why : string)
	--- A bench run is active (gui/stress_bench_run.tl): the other test builds refuse.
	benchActive : boolean
end

global record SquareStressCrossUi
	size : integer
	lights : integer
	traffic : integer             -- index into TEST_TRAFFIC
end

--- Remove roads (gui/stress_roads.tl).
global record SquareStressRoads
	--- Street edges removeAll would remove now, and how many belong to constructions (kept).
	count : function() : integer, integer
	--- Removes every street edge that belongs to no construction, in batches, one in flight.
	removeAll : function()
end

--- Traffic tab selections (session only) and actions (gui/stress_traffic.tl).
global record SquareStressTrafficUi
	perLine : integer             -- index into VEHICLES_PER_LINE
	keepCleared : boolean         -- Keep traffic cleared (session only, default off)
	clearInterval : integer       -- index into CLEAR_INTERVALS
	clearWhere : integer          -- index into CLEAR_WHERE (1 everywhere, 2 in towns, 3 outside towns)
end

--- A town's built-up area for Clear traffic's Where (stress_logic.townArea): centre and radius.
global record SquareStressTownArea
	x : number
	y : number
	r : number
end

--- One Clear traffic cycle (gui/stress_traffic.tl): a snapshot of the SIM_PERSON list scanned with a
--- cursor, the drivers found, then set-state commands sent in chunks; callbacks are counted as they come.
global record SquareStressClearCycle
	name : string                 -- "clear_traffic" or "keep_traffic_cleared"
	keep : boolean                -- started by Keep traffic cleared
	job : SquareStressJob
	list : {integer}              -- SIM_PERSON snapshot (nil until the first step)
	cursor : integer              -- next index of list to scan
	drivers : {integer}
	sendCursor : integer          -- next index of drivers to send to
	scanned : integer
	sent : integer
	answered : integer
	ok : integer
	startedUs : integer
	workDoneUs : integer          -- scan and sends finished (or stopped); nil while running
	note : string                 -- why it ended early, for the log
	finished : boolean            -- logged; the next cycle may start
	where : integer               -- index into CLEAR_WHERE
	areas : {SquareStressTownArea} -- town areas (Where other than everywhere)
	kept : integer                -- drivers left driving by Where
	unknown : integer             -- drivers whose position could not be read (left driving)
	scanOnly : boolean            -- Scan: count drivers and move modes, send nothing
	modes : SquareStressMoveSplit -- every scanned person by lastMoveMode
end

global record SquareStressTraffic
	ui : SquareStressTrafficUi
	--- Vehicles bought by "Add vehicles" in this session, not sold yet (memory only, never saved).
	added : {integer}
	addVehicles : function()
	removeAdded : function()
	readout : function() : string
	uiSignature : function() : string
	--- Clear traffic: send every driver home once (no-op while a cycle runs).
	clearTraffic : function()
	setKeepCleared : function(on : boolean)
	setClearInterval : function(index : integer)
	--- Scan: count drivers and move modes now, send nothing (no-op while a cycle runs).
	scan : function()
	--- Drivers found by the last finished scan (nil before the first).
	driving : integer
	--- Move-mode split of the last finished scan (nil before the first).
	modes : SquareStressMoveSplit
	cycle : SquareStressClearCycle
	--- Every frame (rt tick hook): ends cycles, starts Keep cleared cycles.
	tickClear : function(nowUs : integer)
end

--- A street edge a stop or a depot connection may go on (gui/stress_buslines.tl edgeGeo).
global record SquareStressEdgeGeo
	id : integer
	node0 : integer
	node1 : integer
	p0 : {number}
	t0 : {number}
	p1 : {number}
	t1 : {number}
	mid : {number}                -- point at param 0.5 (cubic Hermite)
	dmid : {number}               -- derivative at param 0.5
	length : number               -- chord
	dist : number                 -- reference point (camera, town centre) -> mid (2D)
	template : string             -- BaseEdge.roadTemplate ("" when unreadable)
end

--- One candidate depot spot beside a street edge (stress_buslines.depotTries).
global record SquareStressDepotTry
	edge : SquareStressEdgeGeo
	t : number                    -- param along the edge where the stub leaves the street
	side : integer                -- 1 right of the edge direction, -1 left
	gap : number                  -- street centre -> the depot's free entrance node
	point : {number}              -- street point at t
	n : {number}                  -- unit normal from the street towards the depot (2D, -0 free)
	entrance : {number}           -- where the depot's free entrance node should land
end

--- Auto bus lines selections (session only).
global record SquareStressBusLinesUi
	towns : integer               -- index into BUS_TOWN_CHOICES
	lines : integer               -- index into BUS_LINES_PER_TOWN
	buses : integer               -- index into BUSES_PER_LINE
end

--- Bus stop / depot / line helpers shared by probe 10 and Auto bus lines (gui/stress_buslines.tl).
global record SquareStressBusLines
	ui : SquareStressBusLinesUi
	--- Lines and buses made by Auto bus lines in this session, depots built by buildDepot (memory only).
	lines : {integer}
	vehicles : {integer}
	depots : {integer}
	--- Middles of our stops and our depots' entrances (session): no new stop within STOP_AVOID of them.
	avoidPoints : {{number}}
	--- Probe 10b's station groups (for 10d).
	lastGroups : {integer}
	--- Probe 10c's depot (for 10d).
	lastDepot : integer
	--- Showcase route lines: depot -> the road network it was built or confirmed for (session).
	depotNet : {integer : string}
	--- Showcase route lines: line -> the twin it serves (session; the traffic log's FLOW_BUS twin=).
	lineTwins : {integer : SquareStressLineTwin}

	MIN_STOP_EDGE : number
	DEPOT_GAPS : {number}
	DEPOT_PARAMS : {number}
	MIN_SPLIT_PIECE : number
	DEPOT_MAX_SENDS : integer
	PAIR_MIN : number
	PAIR_MAX : number
	PAIR_TRIES : integer
	STOP_AVOID : number
	TOWN_EDGE_RADIUS : number
	TOWN_EDGE_MAX : integer
	BUS_DEPOT_REUSE : number
	DEPOT_RINGS : {{number}}
	RING_SAMPLE : integer
	RING_EDGES : integer
	DEPOT_CLEAR_RADIUS : number
	REMOVE_WAIT_MS : number
	REMOVE_POLL_MS : number
	BUILT_RADIUS : number
	MIN_LINE_BALANCE : integer
	MAX_TOWN_FAILS : integer
	MAX_ROUTE_FAILS : integer
	LINE_TIMEOUT_MS : number
	MAP_MARGIN : number
	STOP_DEPOT_RINGS : {{number}}

	-- pure
	z0 : function(v : number) : number
	dist2 : function(a : {number}, b : {number}) : number
	hermiteAt : function(p0 : {number}, t0 : {number}, p1 : {number}, t1 : {number}, t : number) : {number}, {number}
	pickEdgePair : function(cands : {SquareStressEdgeGeo}, minD : number, maxD : number, avoid : {{number}}, avoidR : number,
		tries : integer) : SquareStressEdgeGeo, SquareStressEdgeGeo
	depotTries : function(edges : {SquareStressEdgeGeo}, gaps : {number}, params : {number}) : {SquareStressDepotTry}
	tryText : function(c : SquareStressDepotTry) : string
	ringPick : function(cands : {SquareStressEdgeGeo}, rMin : number, rMax : number, sample : integer, max : integer,
		scoreOf : function(g : SquareStressEdgeGeo) : number) : {SquareStressEdgeGeo}, integer
	nextLineNumber : function(names : {string}, last : integer) : integer
	depotShort : function(details : string) : string

	-- engine
	listSet : function(ct : Engine.ComponentType) : {integer : boolean}, integer
	newIn : function(before : {integer : boolean}, after : {integer : boolean}) : {integer}
	errText : function(data : any) : string
	edgeGeo : function(e : integer, cx : number, cy : number) : SquareStressEdgeGeo, string
	streetEdgeCandidates : function(x : number, y : number, r : number) : {SquareStressEdgeGeo}, string
	stationGroupsNear : function(x : number, y : number, r : number) : {integer}
	streetEdgesAt : function(node : integer) : integer
	gateText : function(depot : integer) : string
	stopModel : function() : string
	depotTransf : function(entrance : {number}, n : {number}) : Mat4f, {number}
	placeStop : function(name : string, g : SquareStressEdgeGeo, onDone : function(ok : boolean, details : string, group : integer))
	isRoadDepot : function(d : integer) : boolean, string
	depotPos : function(d : integer) : {number}, string
	insideMap : function(p : {number}, margin : number, box? : Box2f) : boolean
	nearestRoadDepot : function(x : number, y : number, r : number) : integer, number, string
	buildDepot : function(name : string, edges : {SquareStressEdgeGeo}, cx : number, cy : number,
		onDone : function(ok : boolean, details : string, depot : integer))
	pickBusModel : function() : integer, string
	busConfig : function(modelId : integer) : TransportVehicleConfig
	cloneBusConfig : function() : TransportVehicleConfig, string
	createLine : function(name : string, groups : {integer}, onDone : function(line : integer, details : string))
	bestDepotForLine : function(line : integer, x : number, y : number) : integer, string
	buyBuses : function(name : string, depot : integer, makeCfg : function() : TransportVehicleConfig, n : integer, line : integer,
		onDone : function(bought : integer, failure : string))

	-- Auto bus lines
	selectedLines : function() : integer
	selectedBuses : function() : integer
	label : function() : string
	removeLabel : function() : string
	uiSignature : function() : string
	addBusLines : function()
	--- One line per route between two towns (a stop in each, the first town's depot), buses per line as
	--- selectedBuses(); queued after any running job, refused while a bus-lines job is queued or running.
	--- name starts with "bus_lines" (busy checks). Returns the number of lines queued (0: refused / none).
	addRouteLines : function(name : string, title : string, routes : {SquareStressBusRoute}) : integer
	--- Showcase: one serial job (name; "showcase_depots") that finds or builds every route's first-town depot
	--- (as its line would, on its own town's streets and road network) BEFORE the towns grow; the lines
	--- later reuse them. onDone(ms) after its summary line.
	prebuildDepots : function(name : string, routes : {SquareStressBusRoute}, onDone? : function(ms : number))
	--- The up-front warning of a test whose Traffic is Bus lines (nil when money does not matter: Keep
	--- balance on, or no costs): its bus lines are skipped if the balance is below MIN_LINE_BALANCE by then.
	moneyWarning : function() : string
	removeAdded : function()
end

--- A bus line between two towns (Junction / Crossing test traffic): a stop in a, one in b.
global record SquareStressBusRoute
	a : SquareStressTownPos
	b : SquareStressTownPos
	label : string                -- "Grid A1 -> Grid B2" (log lines)
	net : string                  -- the road network both towns are on (Showcase: "group 3"); nil: one network
	zones : {{number}}            -- Showcase: every junction zone {x, y, r}; stops and depots stay out of them
	twin : string                 -- Showcase: the twin the line serves ("g3a"; FLOW_BUS twin=), nil: none
	pair : string                 -- "g3"
	ab : string                   -- "sl" / "game" / "sl_phases"
end

--- The Showcase twin a bus line serves (stress_buslines lineTwins; the traffic log's FLOW_BUS keys).
global record SquareStressLineTwin
	twin : string
	pair : string
	ab : string
end

--- Stress Test -> Smart Lanes zones channel (gui/stress_slzones.tl): makeScriptingSendEventCmd into Smart
--- Lanes' saved game-script state; the acknowledgement is the run id read back from that state.
global record SquareStressSlZones
	EVENT_ID : string
	EV_ZONES : string
	GS_NAME : string
	ACK_TIMEOUT_MS : number
	ACK_POLL_MS : number
	--- Smart Lanes is active in this game (its mod params are listed).
	present : function() : boolean
	--- Sends a set of the zones; returns the run id (nil when nothing could be sent). Logs
	--- "[SQST] showcase zones sent n= run= by_ab= smart_lanes=yes|no".
	sendSet : function(zones : {SquareStressShowcaseZone}, seed : integer) : string
	--- Sends a clear (Remove all roads, Remove towns > Grid / All towns). Logs "[SQST] showcase zones cleared by=".
	sendClear : function(by : string) : string
	IDLE_GAP_MS : number
	--- Smart Lanes' saved zmodes / zerr / qlen (BENCH.md SL-4, SL-5); nil when absent.
	modes : function() : {string}
	refused : function() : string, string
	qlen : function() : integer
	--- onDone("yes" | "timeout" | "absent" | "unread", ms): Smart Lanes' queue empty twice IDLE_GAP_MS apart, at most maxMs.
	waitIdle : function(name : string, maxMs : number, onDone : function(result : string, ms : number))
	--- The run id Smart Lanes stored last (nil: unreadable or absent).
	ackRun : function() : string
	--- Calls onDone("yes" | "refused:<reason>" | "timeout" | "absent" | "unsent", ms) once Smart Lanes holds run, at most
	--- ACK_TIMEOUT_MS after the call (polled every ACK_POLL_MS through rt.later).
	waitAck : function(run : string, onDone : function(result : string, ms : number))
	--- The zones of the session's last Showcase (the list sendSet got; the Showcase marks them built as it
	--- reads them) and its run id (nil: none sent, or cleared since). Session only.
	current : SquareStressSlZonesCurrent
	--- Smart Lanes' saved zones (fresh {x, y, r, ab, id?, pair?} tables) and their run id; nil when Smart
	--- Lanes is absent or its state unreadable (GUI thread). For the traffic log after a reload.
	savedZones : function() : {{string : any}}, string
	EV_AUTO : string
	--- "SmartLanes.auto" { op = "all" | "clear", run } (Smart Lanes PLAN.md "Stress Test interface: Keep timing adjusted"):
	--- the run id (nil when not sent). Logs "[SQST] AUTO_ALL op=all|clear run= by= smart_lanes=yes|no".
	sendAuto : function(op : string, by : string) : string
	--- SmartLanes.auto add payloads (stress_bench.cityPayloads), one event each; the events sent.
	sendAutoNodes : function(payloads : {{string : any}}) : integer
	--- Traffic-log zones not sent to Smart Lanes (the city run): z.current, logged "[SQST] showcase zones local n= run=".
	setLocal : function(zones : {SquareStressShowcaseZone}, run : string)
	--- The session's last sendAuto: {op, run, by} (nil: none yet).
	autoLast : {string : string}
	--- Smart Lanes' saved arun (the run of its last all / clear; nil: unreadable or absent).
	autoAckRun : function() : string
	--- "Auto re-time: last all, run ..., Smart Lanes acknowledged" (empty before the first send).
	autoStatus : function() : string
end

global record SquareStressSlZonesCurrent
	run : string
	zones : {SquareStressShowcaseZone}
	seq : integer                 -- +1 per sendSet in the session (a new Showcase)
end

--- One zone of the traffic log (stress_flow.tl; FLOW.md FLOW_ZONE).
global record SquareStressFlowZone
	zone : integer                -- 1..n within the run
	twin : string                 -- Showcase twin id "g3a" (nil: not a twin)
	pair : string                 -- "g3"
	ab : string                   -- "sl" / "game" / "sl_phases"
	kind : string                 -- FLOW kind: ix / rb / x / other
	src : string                  -- "placement" (session Showcase) / "sl_zones" (Smart Lanes' saved zones, after a reload)
	label : string
	x : number
	y : number
	r : number
	match : string                -- "yes" / "no" (session Showcase only)
	reason : string
	idFrom : string               -- "showcase" / "sl" (stored labels) / "order" (recomputed from the list order)
	scRun : string                -- the Showcase zones run id (Smart Lanes zrun)
	rm : number                   -- r_measure: the measured area reaches this far from the centre (r + MEASURE_PAD)
	measure : string              -- "corridor" (circle r + one corridor per arm) / "circle" (no arms known: the circle rm)
	arms : {{number}}             -- unit headings of its arms, in compass order (nil: none known)
	armNames : {string}           -- their compass points ("N", "E", ...)
	test : string                 -- the bench test (nil outside a bench)
	approach : number             -- m: its straight approach along every arm (square layouts; positional thru), nil: r_measure
	demand : string               -- light plans A/B: its set's demand (FLOW_ZONE demand=; nil: none)
	mix : string                  -- bench Sheet 5: its set's traffic mix (FLOW_ZONE mix=; nil: none)
	ringMix : boolean             -- RINGMIX / RINGLANE lines for its ring (stress_flow ring*)
end

--- One ring zone's turning mix and lane use, cumulative over a traffic log run (stress_flow.newRing; RINGMIX / RINGLANE).
global record SquareStressFlowRing
	arms : integer                -- A: the zone's arms
	pos : {integer}               -- arm index (the zone's compass order) -> its place in counterclockwise angle order 1..A
	done : {integer : boolean}    -- drivers counted (once each)
	tries : {integer : integer}   -- drivers read without both an entry and an exit arm on their path window
	n : integer                   -- drivers counted (exits + uturn + none)
	exits : {integer}             -- [k]: drivers that left k arms after their entry arm (k < A)
	uturn : integer               -- left by their entry arm (k = A)
	none : integer                -- no entry and exit in the read part of the path after RING_TRIES samples
	reads : integer               -- path elements read for it
	capped : integer              -- samples where the sweep's RING_MIX_READS cap left drivers unread
	lanes : {integer : integer}   -- radius bin (RING_BIN m) -> car samples on its ring edges (RINGLANE)
	laneCars : integer            -- car samples counted in lanes
end

--- Zone lookup grid (stress_flow.newIndex).
global record SquareStressFlowIndex
	cell : number
	buckets : {integer : {integer}}
	zones : {SquareStressFlowZone}
	wide : {integer}
end

--- One zone's (or the map's) counts in a sample.
global record SquareStressFlowAcc
	cars : integer
	standing : integer
	queue : integer
	vSum : number
	speeds : {number}
	standSum : number
	standMax : number
	core : integer                -- cars in the junction's circle r (zones only)
	qArm : {integer}              -- queued cars per arm corridor (zones only; index = the zone's arm)
	qIn : {integer}               -- of them on the inbound side (towards the junction)
	qOut : {integer}              -- on the outbound side
	ahead : {integer : boolean}   -- thru: drivers with the junction ahead on their path (zones only)
	passed : {integer : boolean}  -- thru: drivers (of the previous sample's ahead) that have passed it
	posIn : {integer : integer}   -- positional thru: drivers on their way in (driver -> inbound arm k, 0 in the junction)
end

global record SquareStressFlowSample
	zones : {SquareStressFlowAcc}
	all : SquareStressFlowAcc
	inZones : integer
	drivers : integer             -- drivers found (also past the cap)
	sampled : integer             -- drivers read (MOVE_PATH + position), at most the cap
	posFail : integer             -- sampled drivers without a position (counted map-wide only)
	target : integer              -- the sweep's target (nil: every driver)
	stride : integer              -- every stride-th driver read (1: each)
	driversEst : boolean          -- drivers is an estimate (with a stride: the subset's drivers x stride)
end

--- A sweep's wall cost (FLOW_ALL).
global record SquareStressFlowSweepCost
	persons : integer
	frames : integer
	busyUs : integer
	elapsedUs : integer
	frameMaxUs : integer          -- the sweep's busiest frame
	framePhase : string           -- the sweep phase of that frame (list, sets, scan, ...)
end

global record SquareStressFlowStart
	run : integer
	interval : integer
	zones : integer
	towns : integer
	buses : integer
	speed : integer
	keepCleared : boolean
	cap : integer
	gt : number
	src : string
	scRun : string
	budgetUs : integer
	pathThru : boolean            -- the path thru read (false: off for the run)
end

--- The TRANSPORT_VEHICLE fields a bus line's FLOW_BUS uses.
global record SquareStressFlowTv
	last : number                 -- lastLineStopDeparture (game ms)
	deps : {number}               -- lineStopDepartures (game ms)
	sections : {number}           -- sectionTimes (s)
end

global record SquareStressFlowBus
	vehicles : integer
	laps : {number}
	rts : {number}
	depAgeMax : number
	rawLast : number
	rawDeps : {number}
	rawSecs : {number}
end

global record SquareStressFlowTotals
	samples : integer
	gt0 : number
	gt1 : number
	drivers : integer
	sampled : integer
	standing : integer
	vSum : number
	capped : integer
	skipped : integer
	busyUs : integer
	busyMaxUs : integer
	frames : integer
	warn : {string : integer}
	wall0 : integer
	frameMaxUs : integer
	target : integer              -- the last sample's target (nil: every driver)
end

--- The traffic log's pure part (stress/stress_flow.tl).
global record SquareStressFlow
	VERSION : integer
	STAND_SPEED : number
	QUEUE_S : number
	GRID_CELL : number
	GT_PER_S : integer
	INTERVALS : {integer}
	SUMMARY_EVERY : integer
	CAP : integer
	TARGET_MIN : integer
	TARGET_DROP : number
	MEASURE_PAD : number
	CORRIDOR_HALF : number
	IX_CORRIDOR_HALF : number
	corridorHalf : function(z : SquareStressFlowZone) : number
	approachOf : function(z : SquareStressFlowZone, dx : number, dy : number) : integer
	posCount : function(prev : SquareStressFlowAcc, now : SquareStressFlowAcc, complete : boolean) : integer
	TOWN_LINES_MAX : integer
	VALUE_MAX : integer
	DRIVE_SIDE : string
	THRU_R : number
	THRU_TRACK : number
	THRU_SPEED : number
	THRU_TRACK_MAX : number
	THRU_WINDOW : integer
	RING_MIX_READS : integer
	RING_LANE_READS : integer
	RING_WINDOW : integer
	RING_TRIES : integer
	RING_ARM_COS : number
	RING_BIN : number
	RING_EDGE_DR : number
	RING_EVERY : integer
	newRing : function(z : SquareStressFlowZone) : SquareStressFlowRing
	ringClass : function(z : SquareStressFlowZone, dx : number, dy : number) : integer
	ringMove : function(get : function(i : integer) : integer, n : integer, cur : integer, w? : integer) : integer, integer
	ringSteps : function(ring : SquareStressFlowRing, entry : integer, exit : integer, side : string) : integer
	ringCount : function(ring : SquareStressFlowRing, driver : integer, entry : integer, exit : integer, side : string) : integer
	ringMiss : function(ring : SquareStressFlowRing, driver : integer)
	ringEdge : function(z : SquareStressFlowZone, ax : number, ay : number, bx : number, by : number) : boolean
	ringLane : function(ring : SquareStressFlowRing, d : number)
	ringMixLine : function(run : integer, s : integer, gt : number, z : SquareStressFlowZone, ring : SquareStressFlowRing, side : string, final : boolean) : string
	ringLaneLine : function(run : integer, s : integer, gt : number, z : SquareStressFlowZone, ring : SquareStressFlowRing, final : boolean) : string
	num : function(v : number) : string
	word : function(s : string) : string
	list : function(v : {number}, max : integer) : string
	counts : function(m : {string : integer}) : string
	median : function(v : {number}) : number
	kindOf : function(k : string) : string
	zonesFromShowcase : function(list : {SquareStressShowcaseZone}, run : string) : {SquareStressFlowZone}
	zonesFromSaved : function(list : {{string : any}}, run : string) : {SquareStressFlowZone}
	newIndex : function(zones : {SquareStressFlowZone}, cell? : number) : SquareStressFlowIndex
	compass : function(hx : number, hy : number) : string
	withMeasure : function(z : SquareStressFlowZone, arms : {{number}}) : SquareStressFlowZone
	partOf : function(z : SquareStressFlowZone, dx : number, dy : number) : integer, integer
	zonesAt : function(idx : SquareStressFlowIndex, x : number, y : number, out : {integer}, parts? : {integer}, dirs? : {integer}) : integer
	newAcc : function() : SquareStressFlowAcc
	newSample : function(nZones : integer) : SquareStressFlowSample
	addCar : function(s : SquareStressFlowSample, zs : {integer}, n : integer, speed : number, timeStanding : number, parts? : {integer},
		dirs? : {integer})
	accStats : function(a : SquareStressFlowAcc) : number, number, number, number
	startLine : function(o : SquareStressFlowStart) : string
	zoneLine : function(run : integer, z : SquareStressFlowZone) : string
	flowLine : function(run : integer, s : integer, gt : number, z : SquareStressFlowZone, a : SquareStressFlowAcc, thru? : integer,
		thruS? : number, thruScale? : integer, thruPath? : integer) : string
	raiseOk : function(elapsedGt : number, sampled : integer, count : integer, intervalGt : number) : boolean
	qArmText : function(z : SquareStressFlowZone, a : SquareStressFlowAcc, which? : {integer}) : string
	pathState : function(get : function(i : integer) : integer, n : integer, cur : integer, set : {integer : boolean}, w? : integer,
		aheadOnly? : boolean) : string
	raiseTarget : function(target : integer, drivers : integer) : integer
	thruTrack : function(intervalS : number) : number
	thruCount : function(prev : SquareStressFlowAcc, now : SquareStressFlowAcc, complete : boolean) : integer
	allLine : function(run : integer, s : integer, gt : number, smp : SquareStressFlowSample, sw : SquareStressFlowSweepCost) : string
	lowerTarget : function(target : integer, read : integer) : integer
	stride : function(target : integer, drivers : integer) : integer
	targetLine : function(run : integer, s : integer, target : integer, was : integer, read : integer, driversPrev : integer, reason : string) : string
	townsLines : function(run : integer, s : integer, gt : number, m : {integer : {any}}, coef : number, ms : number,
		names : (function(town : integer) : string), pops? : {integer : integer}) : {string}
	newBus : function() : SquareStressFlowBus
	busVehicle : function(acc : SquareStressFlowBus, laps : {integer : number}, v : integer, tv : SquareStressFlowTv, stops : integer, gt : number)
	busLine : function(run : integer, s : integer, gt : number, line : integer, name : string, twin : SquareStressLineTwin,
		twinFrom : string, acc : SquareStressFlowBus, stops : integer, freq : number) : string
	twinFromStops : function(zones : {SquareStressFlowZone}, ax : number, ay : number, bx : number, by : number) : SquareStressFlowZone
	newTotals : function() : SquareStressFlowTotals
	addSample : function(t : SquareStressFlowTotals, gt : number, smp : SquareStressFlowSample, sw : SquareStressFlowSweepCost)
	summaryLine : function(run : integer, t : SquareStressFlowTotals, zones : integer, wallS : number, final : boolean) : string
	statusText : function(on : boolean, interval : integer, run : integer, samples : integer, zones : integer, lastMs : number,
		lastFrames : integer, drivers : integer) : string
end

global record SquareStressFlowLogUi
	on : boolean
	interval : integer            -- index into SquareStressFlow.INTERVALS
end

--- The Traffic tab's "Traffic log" sampler (gui/stress_flow_log.tl), session only.
global record SquareStressFlowLog
	ui : SquareStressFlowLogUi
	BUDGET_US : integer
	READS_PER_FRAME : integer
	WRITES_PER_FRAME : integer
	PATH_GIVE_UP : integer
	pathThru : boolean            -- read the drivers' paths for thru_path (default true; the bench sets false)
	TOWNS_EVERY_US : integer
	TOWNS_SLOW_EVERY_US : integer
	TOWNS_SLOW_MS : number
	--- Turns the log on (a new run: FLOW_START, FLOW_ZONE lines) or off (FLOW_SUMMARY final=1).
	setOn : function(on : boolean)
	--- Picks the interval (index into INTERVALS); a running log restarts as a new run.
	setInterval : function(index : integer)
	status : function() : string
	uiSignature : function() : string
	--- Every frame (rt tick hook, Main Thread).
	tick : function(nowUs : integer)
	--- The current run's samples and skipped samples (0, 0 when off).
	counts : function() : integer, integer
end
