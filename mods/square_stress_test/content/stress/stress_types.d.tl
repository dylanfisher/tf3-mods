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

	-- Traffic tab (Phase 3)
	VEHICLES_PER_LINE : {integer}
	MAX_BUY_FAILURES : integer
	VEHICLE_TIMEOUT_MS : number
	stop : function(job : SquareStressJob)
	buyPlan : function(lines : {SquareStressLineVehicle}, n : integer) : {SquareStressLineVehicle}, {integer}
	configPrice : function(prices : {number}) : number
	canAfford : function(balance : number, price : number) : boolean
	trafficReadout : function(lines : integer, vehicles : integer, persons : integer, added : integer, driving? : integer) : string

	-- Clear traffic (Phase 3B)
	CLEAR_INTERVALS : {integer}
	CLEAR_SCAN_PER_FRAME : integer
	CLEAR_SEND_PER_FRAME : integer
	CLEAR_STATE_JUMP_HOME : integer
	CLEAR_SUMMARY_US : integer
	CLEAR_CALLBACK_TIMEOUT_US : integer
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

--- GUI-state runtime shared by the HUD script and the probes (gui/stress_runtime.tl). One instance per
--- GUI Lua state (the require cache); nothing is saved.
global record SquareStressRuntime
	queue : SquareStressQueue
	version : integer             -- bumped on every new log line or queue change (window refresh)
	recent : {string}             -- the last log lines, newest last
	keepBalance : boolean         -- Game tab toggle: keep the balance above KEEP_BALANCE
	hideNotifications : boolean   -- Game tab toggle, default true each session (sent on the first tick)
	notificationsSent : boolean   -- the current hideNotifications state was sent to the game script
	KEEP_BALANCE : integer
	PER_FRAME : integer

	nowUs : function() : integer
	log : function(msg : string)
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
end

global record SquareStressProbeDef
	id : string
	label : string
	tooltip : string
	run : function()
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
end

global record SquareStressTowns
	ui : SquareStressTownsUi
	grow : function(factor : number, passes? : integer)  -- factor nil = reset to x1 (one pass)
	growSelected : function()                 -- grow with ui.growTarget / ui.factor / ui.passes
	selectedPasses : function() : integer     -- ui.passes as a pass count
	selectedFactor : function() : number      -- ui.factor as a factor, nil = reset
	growLabel : function() : string
	spawnLabel : function() : string
	spawn : function()
	setDevelopment : function(active : boolean)
	--- ignore: sensitivity 0 for noise and pollution in every town; false: reset to the defaults.
	setRatingSensitivity : function(ignore : boolean)
	readout : function() : string
	uiSignature : function() : string
	--- Every town with its position (makeMapFromGame), empty when unavailable.
	townPositions : function() : {SquareStressTownPos}
end

--- Traffic tab selections (session only) and actions (gui/stress_traffic.tl).
global record SquareStressTrafficUi
	perLine : integer             -- index into VEHICLES_PER_LINE
	keepCleared : boolean         -- Keep traffic cleared (session only, default off)
	clearInterval : integer       -- index into CLEAR_INTERVALS
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
	--- Drivers found by the last finished scan (nil before the first).
	driving : integer
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
	LINE_TIMEOUT_MS : number

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
	stopModel : function() : string
	depotTransf : function(entrance : {number}, n : {number}) : Mat4f, {number}
	placeStop : function(name : string, g : SquareStressEdgeGeo, onDone : function(ok : boolean, details : string, group : integer))
	isRoadDepot : function(d : integer) : boolean, string
	depotPos : function(d : integer) : {number}, string
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
	removeAdded : function()
end
