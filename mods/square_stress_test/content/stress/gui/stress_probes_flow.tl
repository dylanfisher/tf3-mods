-- Stress Test probes 11a-11h "Flow" (plans/square_stress_test/FLOW_PLAN.md step 0): read-only
-- experiments that answer the traffic-flow log's open questions before the sampler is written
-- (log contract: plans/square_stress_test/FLOW.md; in-game steps: TESTING.md 6M). Appended to the
-- Probe tab by stress_probes.tl (shown only with the show_probe_tab setting).
--
-- Rules every probe follows:
-- - Read only: no command is sent, nothing is built or changed.
-- - Main Thread: every read runs from the runtime queue (rt.tick <- react.onStep, docs/findings.md
--   "Timers and threads in GUI contexts"), never from onStepTimer.
-- - Every engine read is pcall'd; api.engine.entityExists (api/engine.d.tl:1723) before any network
--   query on an entity (dead entities crash native code, FLOW_PLAN.md "Risks").
-- - Bounded per frame: work is sliced (sliced(): at most perFrame items per job and BUDGET_US per frame
--   over all flow jobs, maxPerTick = 1), the driver sample is capped at MAX_DRIVERS.
-- - 11c queries only entities with a TRANSPORT_NETWORK component; 11h calls calcPathPosData only on
--   persons still driving (a missed native lookup asserts; pcall doesn't catch that).
-- - Output: "[SQST] probe 11x <topic> k=v ..." detail lines (stdout.txt only), then one
--   "[SQST-PROBE] flow_11x_<name> ok|fail ..." line (also in the window log).
--
-- API (verified against .cache/game/api/tealdef, cited where used):
--   MOVE_PATH: MovePath{path, state, blocked, dyn{pathPos, speed, timeStanding, ...}}  api/engine.d.tl:673-709
--   Path.edges {{EdgeId, boolean}}, EdgeId{entity (TN entity), index (0-based)}        api/type.d.tl:2269-2280, :1164-1175
--   PathPos{edgeIndex (0-based), pos, pos01}                                           api/type.d.tl:2284-2294
--   TRANSPORT_NETWORK.edges {Edge{speedLimit, curveSpeedLimit, curSpeed}}              api/engine.d.tl:1363-1372, api/type.d.tl:1114-1126
--   VehicleState RUNNING/STOPPING/STOPPED/ARRIVED                                      api/type.d.tl:432-441
--   VehicleOrder (no ComponentType for it in the list)                                 api/engine.d.tl:1565-1574, :1621-1684
--   LandVehicle.dyn{brakingTimer, turnLeft, turnRight}                                 api/engine.d.tl:471-489
--   simPersonSystem.getSimPersonsMovingForTransportNetwork(tn)                         api/engine/system.d.tl:155-157
--   util.town.computeTownsTrafficSpeedMap(coef) -> {town: {speed, {streets per level}}}  api/engine/util.d.tl:667-670
--   TRANSPORT_VEHICLE lineStopDepartures, lastLineStopDeparture, sectionTimes           api/engine.d.tl:1482-1487
--   GAME_TIME{gameTime, gameTime0, timeOfDaySec} on getWorld()                         api/engine.d.tl:425-433, base company_util.tl:89
--   util.line.getMaxFrequency(line)                                                    api/engine/util.d.tl:206
--   lineSystem.getLinesForPlayer / transportVehicleSystem.getLineVehicles              api/engine/system.d.tl:18, :372
--   util.vehicle.getSpeed / getPosition / calcPathPosData                              api/engine/util.d.tl:438-449
--   Construction{fileName, transf, timeBuilt, frozenNodes, frozenEdges}                api/engine.d.tl:295-330
--   PlayerOwned{player}                                                                api/engine.d.tl:855-859
--   streetConnectorSystem.getConstructionEntityForEdge / ForNode (< 0: none)          api/engine/system.d.tl:240, :246
--   octree.findEntitiesInCircle(center, r, ct)                                         api/engine/util.d.tl:329

local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime

local flow : SquareStressFlowProbes = { drivers = {}, driversUs = 0 }

local MAX_DRIVERS <const> = 200        -- drivers sampled per probe run
local SCAN_PER_FRAME <const> = 2000    -- SIM_PERSON tests per frame while gathering drivers
local READ_PER_FRAME <const> = 25      -- MOVE_PATH (or similar) reads per frame
local QUERY_PER_FRAME <const> = 10     -- network queries per frame (11c)
local BUDGET_US <const> = 4000         -- a slice stops early after this much time in one frame
local DRIVERS_TTL_US <const> = 20000000  -- a driver sample is reused by the next probe for 20 s
local NEAR_R <const> = 300.0           -- camera radius of 11c / 11g / 11h queries
local CAMERA_EDGES <const> = 30
local CAMERA_NODES <const> = 20
local DRIVER_TARGETS <const> = 20      -- 11c: driver-occupied entities queried per kind
local RETURN_CHECK <const> = 50        -- 11c: returned persons checked with isDriver per query
local SAMPLE_LINES <const> = 12        -- per-driver sample lines (stdout.txt)
local PATH_DRIVERS <const> = 20        -- 11b: drivers whose whole path is classified
local PATH_STEPS <const> = 300         -- 11b: path steps classified per driver at most
local STAND_SPEED <const> = 0.5        -- "standing" below this speed (FLOW.md, provisional unit m/s)
local BUS_LINES <const> = 6
local BUS_VEHICLES <const> = 4
local BUS_RECHECK_MS <const> = 10000
local CON_MAX <const> = 12
local EDGE_MAX <const> = 400

---------------------------------------------------------------------------
-- Helpers

local function comp(e : integer, ct : Engine.ComponentType) : any
	if e == nil or ct == nil then return nil end
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

local function exists(e : integer) : boolean
	if e == nil or e < 0 then return false end
	local ok, x = pcall(api.engine.entityExists, e)
	return ok and x == true
end

local function num(v : any) : string
	if type(v) ~= "number" then return tostring(v) end
	local n = v as number
	if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
	return string.format("%.3g", n)
end

--- "{a,b,c}" of up to max numbers (", ..." beyond).
local function list(v : any, max : integer) : string
	if type(v) ~= "table" then return tostring(v) end
	local parts : {string} = {}
	for i, x in ipairs(v as {any}) do
		if i > max then parts[#parts + 1] = "..+" .. tostring(#(v as {any}) - max) break end
		parts[#parts + 1] = num(x)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- "n=.. min=.. med=.. p90=.. max=.. mean=.." of a list of numbers ("n=0" when empty).
function flow.stats(values : {number}) : string
	local n = #values
	if n == 0 then return "n=0" end
	local s : {number} = {}
	local sum = 0.0
	for i, v in ipairs(values) do s[i] = v sum = sum + v end
	table.sort(s)
	local function at(q : number) : number return s[math.max(1, math.min(n, math.ceil(q * n)))] end
	return string.format("n=%d min=%s med=%s p90=%s max=%s mean=%s", n, num(s[1]), num(at(0.5)), num(at(0.9)),
		num(s[n]), num(sum / n))
end

--- "k:v,..." of a count map, most frequent first, "-" when empty.
function flow.counts(m : {string : integer}) : string
	local keys : {string} = {}
	for k in pairs(m) do keys[#keys + 1] = k end
	if #keys == 0 then return "-" end
	table.sort(keys, function(a : string, b : string) : boolean
		if m[a] ~= m[b] then return m[a] > m[b] end
		return a < b
	end)
	local parts : {string} = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. tostring(m[k]) end
	return table.concat(parts, ",")
end

--- flow.counts cut to the max most frequent keys, "+N" = N more keys (long lists such as town
--- building file names stay one readable line).
local function topCounts(m : {string : integer}, max : integer) : string
	local all = flow.counts(m)
	local parts : {string} = {}
	local n = 0
	for part in string.gmatch(all, "[^,]+") do
		n = n + 1
		if n <= max then parts[#parts + 1] = part end
	end
	if n > max then parts[#parts + 1] = "+" .. tostring(n - max) end
	return table.concat(parts, ",")
end

local function bump(m : {string : integer}, k : string)
	m[k] = (m[k] or 0) + 1
end

--- The name of an engine enum value (api.type.enum.<enumName>), else its raw text.
local function enumName(enumKey : string, v : any, names : {string}) : string
	local ok, e = pcall(function() : any return ((api.type as {string : any})["enum"] as {string : any})[enumKey] end)
	if ok and e ~= nil then
		for _, n in ipairs(names) do
			local okN, val = pcall(function() : any return (e as {string : any})[n] end)
			if okN and val ~= nil and val == v then return n end
		end
	end
	return tostring(v)
end

local VEHICLE_STATES <const> : {string} = { "RUNNING", "STOPPING", "STOPPED", "ARRIVED" }

local driveValue : any = nil
--- Driving a car right now: lastMoveMode DRIVE, a MOVE_PATH, not seated in a vehicle
--- (docs/findings.md "Stress Test probes" fourth run; stress_traffic.tl isDriver).
function flow.isDriver(e : integer) : boolean
	local CT = api.type.ComponentType
	local sp = comp(e, CT.SIM_PERSON) as Engine.Component.SimPerson
	if sp == nil then return false end
	if driveValue == nil then
		local ok, v = pcall(function() : any return api.type["enum"].MoveMode.DRIVE end)
		driveValue = (ok and v ~= nil) and v or 1
	end
	if sp.lastMoveMode ~= driveValue then return false end
	return comp(e, CT.MOVE_PATH) ~= nil and comp(e, CT.SIM_PERSON_AT_VEHICLE) == nil
		and comp(e, CT.SIM_ENTITY_AT_VEHICLE) == nil
end

--- The path step a mover is on now: path.edges[pathPos.edgeIndex + 1] (0-based index) and its
--- EdgeId's TN entity and lane index; nil when unreadable.
local function currentStep(mp : Engine.Component.MovePath) : integer, integer, integer
	local ok, ent, idx, edgeIndex = pcall(function() : integer, integer, integer
		local i = mp.dyn.pathPos.edgeIndex
		local step = mp.path.edges[i + 1]
		return step[1].entity, step[1].index, i
	end)
	if not ok then return nil, nil, nil end
	return ent, idx, edgeIndex
end

--- What kind of entity a path step's TN entity is.
function flow.entityKind(e : integer) : string
	if e == nil then return "nil" end
	if not exists(e) then return "gone" end
	local CT = api.type.ComponentType
	if comp(e, CT.BASE_EDGE_STREET) ~= nil then return "street_edge" end
	if comp(e, CT.BASE_EDGE) ~= nil then return "edge_other" end
	if comp(e, CT.BASE_NODE) ~= nil then return "node" end
	if comp(e, CT.CONSTRUCTION) ~= nil then return "construction" end
	if comp(e, CT.TRANSPORT_NETWORK) ~= nil then return "tn_only" end
	return "other"
end

local function cameraPos(name : string) : number, number
	local ok, x, y = pcall(rt.camera)
	if not ok or x == nil then
		rt.probe(name, false, "camera read failed: " .. tostring(x))
		return nil, nil
	end
	return x, y
end

-- BUDGET_US is shared by every flow slice in one frame (two probes, or a scan finishing and the
-- probe it feeds starting in the same rt.tick): a tick hook (runs first in every rt.tick) resets it.
local frameUsedUs = 0
local frameHooked = false

--- A queue job that runs fn(k) for k = 1..n, at most perFrame items per frame and BUDGET_US per frame
--- over all flow slices (one step per frame), then done(frames, errors, firstError). fn returns true
--- to stop early.
local function sliced(name : string, n : integer, perFrame : integer, fn : function(k : integer) : boolean,
		done : function(frames : integer, errors : integer, firstErr : string))
	local k, errors, stop = 0, 0, false
	local firstErr : string = nil
	local function finish(frames : integer)
		local ok, err : boolean, any = pcall(done, frames, errors, firstErr)
		if not ok then rt.probe(name, false, "error: " .. tostring(err)) end
	end
	if n <= 0 then finish(0) return end
	if not frameHooked then
		frameHooked = true
		rt.addTickHook(function(_now : integer) frameUsedUs = 0 end)
	end
	rt.enqueue(name, 1, function(_i : integer, job : SquareStressJob)
		local t0 = rt.nowUs()
		local c = 0
		while k < n and c < perFrame and not stop and frameUsedUs + (rt.nowUs() - t0) < BUDGET_US do
			k, c = k + 1, c + 1
			local ok, res : boolean, any = pcall(fn, k)
			if not ok then
				errors = errors + 1
				if firstErr == nil then firstErr = tostring(res) end
			elseif res == true then
				stop = true
			end
		end
		frameUsedUs = frameUsedUs + (rt.nowUs() - t0)
		if k < n and not stop then
			job.total = job.done + 1
		else
			finish(job.done)
		end
	end, { quiet = true, maxPerTick = 1, label = "Flow probe" })
end

--- Up to MAX_DRIVERS persons driving now, then cont(drivers, source). Reuses the last sample for
--- DRIVERS_TTL_US (still existing ones only); else scans the SIM_PERSON list (iterable, docs/findings.md
--- "Stress Test probes" fourth run) in slices.
local function withDrivers(name : string, contRaw : function(drivers : {integer}, source : string))
	-- an error in the probe's own synchronous part still ends with its one [SQST-PROBE] line
	local function cont(drivers : {integer}, source : string)
		local ok, err : boolean, any = pcall(contRaw, drivers, source)
		if not ok then rt.probe(name, false, "error: " .. tostring(err)) end
	end
	local now = rt.nowUs()
	if #flow.drivers > 0 and now - flow.driversUs < DRIVERS_TTL_US then
		local alive : {integer} = {}
		for _, e in ipairs(flow.drivers) do
			if exists(e) then alive[#alive + 1] = e end
		end
		if #alive > 0 then
			cont(alive, string.format("reused sample (%.0f s old, %d of %d still exist)", (now - flow.driversUs) / 1e6, #alive, #flow.drivers))
			return
		end
	end
	rt.enqueue(name .. ":list", 1, function(_i : integer)
		local t0 = rt.nowUs()
		local ok, l = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.SIM_PERSON)
		local listUs = rt.nowUs() - t0
		if not ok or l == nil then
			cont({}, "SIM_PERSON list failed: " .. tostring(l))
			return
		end
		local persons = l as {integer}
		local found : {integer} = {}
		sliced(name .. ":scan", #persons, SCAN_PER_FRAME, function(k : integer) : boolean
			if flow.isDriver(persons[k]) then found[#found + 1] = persons[k] end
			return #found >= MAX_DRIVERS
		end, function(frames : integer, errors : integer, _firstErr : string)
			flow.drivers, flow.driversUs = found, rt.nowUs()
			cont(found, string.format("scan of %d persons (list %d us, %d frames, %d errors)", #persons, listUs, frames, errors))
		end)
	end, { quiet = true, label = "Flow probe" })
end

local function failNoDrivers(name : string, drivers : {integer}, source : string) : boolean
	if #drivers > 0 then return false end
	rt.probe(name, false, "no person driving a car found (" .. source .. "); needs towns with car traffic running")
	return true
end

--- A queue step (or later callback) whose error still ends the probe with its one [SQST-PROBE] line.
local function guard(name : string, fn : function()) : function(_i : integer)
	return function(_i : integer)
		local ok, err : boolean, any = pcall(fn)
		if not ok then rt.probe(name, false, "error: " .. tostring(err)) end
	end
end

local function add(out : {SquareStressProbeDef}, id : string, label : string, tooltip : string, run : function())
	out[#out + 1] = { id = id, label = label, tooltip = tooltip, run = run }
end

local function D(fmt : string, ...: any)
	rt.detail("[SQST] probe " .. string.format(fmt, ...))
end

---------------------------------------------------------------------------
-- 11a MOVE_PATH read cost and units (FLOW_PLAN.md open question 2). Per driver: one MOVE_PATH read
-- timed, #path.edges, dyn.speed / timeStanding, util.vehicle.getSpeed (timed) and the lane's
-- TRANSPORT_NETWORK edge speedLimit / curveSpeedLimit / curSpeed (timed): speed vs limit tells the
-- unit of dyn.speed.

local function probeMovePath()
	local name = "flow_11a_movepath"
	withDrivers(name, function(drivers : {integer}, source : string)
		if failNoDrivers(name, drivers, source) then return end
		local CT = api.type.ComponentType
		local readUs, edgeCounts, speeds, standing, gsUs, gsRatio, tnUs, limits, rel, curSpeeds : {number}, {number}, {number}, {number}, {number}, {number}, {number}, {number}, {number}, {number} = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
		local nilPaths, gone, nStanding, samples = 0, 0, 0, 0
		sliced(name, #drivers, READ_PER_FRAME, function(k : integer) : boolean
			local e = drivers[k]
			if not exists(e) then gone = gone + 1 return false end
			local t0 = rt.nowUs()
			local mp = comp(e, CT.MOVE_PATH) as Engine.Component.MovePath
			readUs[#readUs + 1] = rt.nowUs() - t0
			if mp == nil then nilPaths = nilPaths + 1 return false end
			local nEdges = mp.path ~= nil and mp.path.edges ~= nil and #mp.path.edges or -1
			edgeCounts[#edgeCounts + 1] = nEdges
			local sp = mp.dyn ~= nil and mp.dyn.speed or nil
			local ts = mp.dyn ~= nil and mp.dyn.timeStanding or nil
			if sp ~= nil then speeds[#speeds + 1] = sp end
			if sp ~= nil and sp < STAND_SPEED then
				nStanding = nStanding + 1
				if ts ~= nil then standing[#standing + 1] = ts end
			end
			local t1 = rt.nowUs()
			local okG, gs = pcall(api.engine.util.vehicle.getSpeed, e)
			gsUs[#gsUs + 1] = rt.nowUs() - t1
			if okG and gs ~= nil and sp ~= nil and sp > 0.1 then gsRatio[#gsRatio + 1] = (gs as number) / sp end
			local ent, idx = currentStep(mp)
			local limit, curve, cur : number, number, number = nil, nil, nil
			if ent ~= nil and exists(ent) then
				local t2 = rt.nowUs()
				local tn = comp(ent, CT.TRANSPORT_NETWORK) as Engine.Component.TransportNetwork
				tnUs[#tnUs + 1] = rt.nowUs() - t2
				local okE, edge = pcall(function() : Edge return tn.edges[idx + 1] end)
				if okE and edge ~= nil then
					limit, curve, cur = edge.speedLimit, edge.curveSpeedLimit, edge.curSpeed
					if limit ~= nil then limits[#limits + 1] = limit end
					if cur ~= nil then curSpeeds[#curSpeeds + 1] = cur end
					if limit ~= nil and limit > 0 and sp ~= nil then rel[#rel + 1] = sp / limit end
				end
			end
			if samples < SAMPLE_LINES then
				samples = samples + 1
				D("11a sample e=%d edges=%d edgeIndex=%s pos01=%s speed=%s getSpeed=%s timeStanding=%s lane=%s/%s speedLimit=%s curveSpeedLimit=%s curSpeed=%s state=%s blocked=%s",
					e, nEdges, num(mp.dyn ~= nil and mp.dyn.pathPos.edgeIndex or nil), num(mp.dyn ~= nil and mp.dyn.pathPos.pos01 or nil),
					num(sp), okG and num(gs) or "err", num(ts), num(ent), num(idx), num(limit), num(curve), num(cur),
					enumName("VehicleState", mp.state, VEHICLE_STATES), num(mp.blocked))
			end
			return false
		end, function(frames : integer, errors : integer, firstErr : string)
			D("11a movepath_read_us %s", flow.stats(readUs))
			D("11a path_edges %s", flow.stats(edgeCounts))
			D("11a dyn_speed %s standing(<%s)=%d", flow.stats(speeds), num(STAND_SPEED), nStanding)
			D("11a time_standing_of_standing %s", flow.stats(standing))
			D("11a get_speed_us %s getSpeed/dyn.speed %s", flow.stats(gsUs), flow.stats(gsRatio))
			D("11a lane tn_read_us %s", flow.stats(tnUs))
			D("11a lane speedLimit %s curSpeed %s", flow.stats(limits), flow.stats(curSpeeds))
			D("11a speed/speedLimit %s", flow.stats(rel))
			rt.probe(name, #readUs > 0 and nilPaths < #readUs, string.format(
				"drivers=%d (%s) read=%d nilPath=%d gone=%d frames=%d errors=%d%s",
				#drivers, source, #readUs, nilPaths, gone, frames, errors, firstErr ~= nil and (" firstError: " .. firstErr) or ""))
		end)
	end)
end

---------------------------------------------------------------------------
-- 11b What a car's current path entity is (FLOW_PLAN.md open question 1): is
-- path.edges[edgeIndex + 1][1].entity a BASE_EDGE street segment, or a node while the car crosses a
-- junction? Counted by kind; for the first PATH_DRIVERS drivers also every step of the whole path and
-- the transitions between kinds (edge>node>edge shows whether nodes are path steps at all).

local function probePathEntity()
	local name = "flow_11b_path_entity"
	withDrivers(name, function(drivers : {integer}, source : string)
		if failNoDrivers(name, drivers, source) then return end
		local CT = api.type.ComponentType
		local current, whole, trans, lanes : {string : integer}, {string : integer}, {string : integer}, {string : integer} = {}, {}, {}, {}
		local samples, pathsDone = 0, 0
		local kindCache : {integer : string} = {}
		local function kind(e : integer) : string
			local k = kindCache[e]
			if k == nil then k = flow.entityKind(e) kindCache[e] = k end
			return k
		end
		sliced(name, #drivers, READ_PER_FRAME, function(k : integer) : boolean
			local e = drivers[k]
			if not exists(e) then bump(current, "driver_gone") return false end
			local mp = comp(e, CT.MOVE_PATH) as Engine.Component.MovePath
			if mp == nil then bump(current, "no_move_path") return false end
			local ent, idx, edgeIndex = currentStep(mp)
			local kd = kind(ent)
			bump(current, kd)
			bump(lanes, kd .. "#" .. tostring(idx))
			if kd ~= "street_edge" and samples < SAMPLE_LINES then
				samples = samples + 1
				local prev, nxt = "-", "-"
				pcall(function()
					local p = mp.path.edges[edgeIndex]
					if p ~= nil then prev = kind(p[1].entity) .. ":" .. tostring(p[1].entity) end
					local q = mp.path.edges[edgeIndex + 2]
					if q ~= nil then nxt = kind(q[1].entity) .. ":" .. tostring(q[1].entity) end
				end)
				D("11b sample e=%d entity=%s kind=%s lane=%s pos01=%s speed=%s prev=%s next=%s trafficLight=%s",
					e, num(ent), kd, num(idx), num(mp.dyn.pathPos.pos01), num(mp.dyn.speed), prev, nxt,
					tostring(ent ~= nil and comp(ent, CT.BASE_NODE_TRAFFIC_LIGHT) ~= nil))
			end
			if pathsDone < PATH_DRIVERS and mp.path ~= nil and mp.path.edges ~= nil then
				pathsDone = pathsDone + 1
				local last = ""
				for i = 1, math.min(#mp.path.edges, PATH_STEPS) do
					local kk = kind(mp.path.edges[i][1].entity)
					bump(whole, kk)
					if last ~= "" then bump(trans, last .. ">" .. kk) end
					last = kk
				end
			end
			return false
		end, function(frames : integer, errors : integer, firstErr : string)
			D("11b current_kind %s", flow.counts(current))
			D("11b current_kind#lane %s", flow.counts(lanes))
			D("11b whole_path_kinds (first %d drivers, <= %d steps each) %s", pathsDone, PATH_STEPS, flow.counts(whole))
			D("11b transitions %s", flow.counts(trans))
			rt.probe(name, (current.street_edge or 0) > 0, string.format("drivers=%d (%s) current={%s} nodeSteps=%d frames=%d errors=%d%s",
				#drivers, source, flow.counts(current), whole.node or 0, frames, errors, firstErr ~= nil and (" firstError: " .. firstErr) or ""))
		end)
	end)
end

---------------------------------------------------------------------------
-- 11c getSimPersonsMovingForTransportNetwork on street segments and nodes (FLOW_PLAN.md open question
-- 1): around the camera (octree), and on the entities sampled drivers are on right now, where the
-- expected answer is known (does the list contain that driver?). Cost per call, return shape, counts.

local record Target
	group : string
	e : integer
	expect : integer   -- a driver on it right now (nil: none known)
end

local record GroupStat
	n : integer
	ok : integer
	err : integer
	gone : integer
	noTn : integer     -- skipped: no TRANSPORT_NETWORK component
	matched : integer
	expected : integer
	us : {number}
	counts : {number}
	drivers : integer
	checked : integer
	shape : string
	firstErr : string
end

local function probeMoving()
	local name = "flow_11c_moving"
	local x, y = cameraPos(name)
	if x == nil then return end
	withDrivers(name, function(drivers : {integer}, source : string)
		local CT = api.type.ComponentType
		local targets : {Target} = {}
		local okO, edges = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), NEAR_R, CT.BASE_EDGE)
		local nodeSeen : {integer : boolean} = {}
		local camNodes = 0
		local camEdges = 0
		if okO and edges ~= nil then
			for _, e in ipairs(edges as {integer}) do
				if camEdges >= CAMERA_EDGES then break end
				if comp(e, CT.BASE_EDGE_STREET) ~= nil then
					camEdges = camEdges + 1
					targets[#targets + 1] = { group = "camera_edge", e = e }
					local be = comp(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
					if be ~= nil then
						for _, n in ipairs({ be.node0, be.node1 }) do
							if camNodes < CAMERA_NODES and n ~= nil and not nodeSeen[n] then
								nodeSeen[n] = true
								camNodes = camNodes + 1
								targets[#targets + 1] = { group = "camera_node", e = n }
							end
						end
					end
				end
			end
		end
		local dEdges, dNodes = 0, 0
		local stats : {string : GroupStat} = {}
		local order : {string} = { "camera_edge", "camera_node", "driver_edge", "driver_node" }
		for _, g in ipairs(order) do
			stats[g] = { n = 0, ok = 0, err = 0, gone = 0, noTn = 0, matched = 0, expected = 0, us = {}, counts = {}, drivers = 0, checked = 0 }
		end
		-- the drivers' current entities: MOVE_PATH reads, so sliced like the queries
		sliced(name .. ":targets", #drivers, READ_PER_FRAME, function(k : integer) : boolean
			local d = drivers[k]
			if not exists(d) then return false end
			local mp = comp(d, CT.MOVE_PATH) as Engine.Component.MovePath
			local ent = mp ~= nil and currentStep(mp) or nil
			local kd = ent ~= nil and flow.entityKind(ent) or "nil"
			if kd == "street_edge" and dEdges < DRIVER_TARGETS then
				dEdges = dEdges + 1
				targets[#targets + 1] = { group = "driver_edge", e = ent, expect = d }
			elseif kd == "node" and dNodes < DRIVER_TARGETS then
				dNodes = dNodes + 1
				targets[#targets + 1] = { group = "driver_node", e = ent, expect = d }
			end
			return dEdges >= DRIVER_TARGETS and dNodes >= DRIVER_TARGETS
		end, function(_tFrames : integer, _tErrors : integer, _tFirstErr : string)
			if #targets == 0 then
				rt.probe(name, false, string.format("nothing to query: octree=%s camera edges=0, drivers=%d (%s)", tostring(okO), #drivers, source))
				return
			end
			local samples = 0
			sliced(name, #targets, QUERY_PER_FRAME, function(k : integer) : boolean
				local t = targets[k]
				local g = stats[t.group]
				g.n = g.n + 1
				if not exists(t.e) then g.gone = g.gone + 1 return false end
				-- only entities with a TRANSPORT_NETWORK component: a native component lookup that misses can
				-- assert (Engine.h GetComponentDataIndex, docs/findings.md sixth run), which pcall can't catch
				if comp(t.e, CT.TRANSPORT_NETWORK) == nil then g.noTn = g.noTn + 1 return false end
				local t0 = rt.nowUs()
				local ok, ps = pcall(api.engine.system.simPersonSystem.getSimPersonsMovingForTransportNetwork, t.e)
				g.us[#g.us + 1] = rt.nowUs() - t0
				if not ok then
					g.err = g.err + 1
					if g.firstErr == nil then g.firstErr = tostring(ps) end
					return false
				end
				g.ok = g.ok + 1
				if g.shape == nil then g.shape = type(ps) end
				local l = (type(ps) == "table" or type(ps) == "userdata") and (ps as {integer}) or {}
				local okN, n = pcall(function() : integer return #l end)
				g.counts[#g.counts + 1] = okN and n or -1
				local found = false
				local okI = pcall(function()
					for i, p in ipairs(l) do
						if p == t.expect then found = true end
						if i <= RETURN_CHECK then
							g.checked = g.checked + 1
							if flow.isDriver(p) then g.drivers = g.drivers + 1 end
						end
					end
				end)
				if t.expect ~= nil then
					g.expected = g.expected + 1
					if found then g.matched = g.matched + 1 end
				end
				if samples < SAMPLE_LINES and okN and n > 0 then
					samples = samples + 1
					D("11c sample group=%s entity=%d returned=%d first=%s expect=%s found=%s iterable=%s", t.group, t.e, n,
						list(l, 6), num(t.expect), tostring(found), tostring(okI))
				end
				return false
			end, function(frames : integer, errors : integer, firstErr : string)
				local parts : {string} = {}
				for _, gName in ipairs(order) do
					local g = stats[gName]
					D("11c group=%s queried=%d ok=%d err=%d gone=%d no_tn=%d shape=%s returned{%s} driversAmongReturned=%d/%d expectedFound=%d/%d cost_us{%s}%s",
						gName, g.n, g.ok, g.err, g.gone, g.noTn, g.shape or "-", flow.stats(g.counts), g.drivers, g.checked, g.matched, g.expected,
						flow.stats(g.us), g.firstErr ~= nil and (" firstError: " .. g.firstErr) or "")
					parts[#parts + 1] = string.format("%s:%d/%d", gName, g.matched, g.expected)
				end
				local okAny = false
				for _, g in pairs(stats) do if g.ok > 0 then okAny = true end end
				rt.probe(name, okAny, string.format("targets=%d drivers=%d (%s) expectedFound{%s} frames=%d errors=%d%s", #targets, #drivers,
					source, table.concat(parts, ","), frames, errors, firstErr ~= nil and (" firstError: " .. firstErr) or ""))
			end)
		end)
	end)
end

---------------------------------------------------------------------------
-- 11d VehicleOrder reachable? (FLOW_PLAN.md open question 3) and the MOVE_PATH blocked / state values of
-- drivers. engine.d.tl's ComponentType list (:1621-1684) has no VEHICLE_ORDER; the probe also lists
-- every ComponentType key the runtime has that the list lacks, and LAND_VEHICLE.dyn (braking / turning).

local function componentTypeKeys() : {string}, string
	local keys : {string} = {}
	local ok, err : boolean, any = pcall(function()
		for k, _ in pairs(api.type.ComponentType as {string : any}) do keys[#keys + 1] = tostring(k) end
	end)
	table.sort(keys)
	if ok then return keys, nil end
	return keys, tostring(err)
end

local function probeOrder()
	local name = "flow_11d_order"
	local CT = api.type.ComponentType
	local keys, keysErr = componentTypeKeys()
	local orderish : {string} = {}
	for _, k in ipairs(keys) do
		if string.find(string.upper(k), "ORDER", 1, true) ~= nil then orderish[#orderish + 1] = k end
	end
	local okD, direct = pcall(function() : any return (CT as {string : any})["VEHICLE_ORDER"] end)
	if not okD then direct = nil end
	local okT, vo = pcall(function() : any return (api.type as {string : any})["VehicleOrder"] end)
	D("11d component_types n=%d%s orderLike={%s} VEHICLE_ORDER=%s api.type.VehicleOrder=%s",
		#keys, keysErr ~= nil and (" (pairs failed: " .. keysErr .. ")") or "", table.concat(orderish, ","), tostring(direct),
		okT and tostring(vo ~= nil) or "err")
	withDrivers(name, function(drivers : {integer}, source : string)
		if failNoDrivers(name, drivers, source) then return end
		local states, blocked, cross, braking : {string : integer}, {string : integer}, {string : integer}, {string : integer} = {}, {}, {}, {}
		local orderRead = 0
		local samples = 0
		sliced(name, #drivers, READ_PER_FRAME, function(k : integer) : boolean
			local e = drivers[k]
			if not exists(e) then bump(states, "gone") return false end
			local mp = comp(e, CT.MOVE_PATH) as Engine.Component.MovePath
			if mp == nil then bump(states, "no_move_path") return false end
			bump(states, enumName("VehicleState", mp.state, VEHICLE_STATES))
			bump(blocked, num(mp.blocked))
			local standingNow = mp.dyn ~= nil and mp.dyn.speed ~= nil and mp.dyn.speed < STAND_SPEED
			bump(cross, (standingNow and "standing" or "moving") .. "+blocked=" .. num(mp.blocked))
			if direct ~= nil and comp(e, direct as Engine.ComponentType) ~= nil then orderRead = orderRead + 1 end
			local lv = comp(e, CT.LAND_VEHICLE) as Engine.Component.LandVehicle
			if lv ~= nil and lv.dyn ~= nil then
				local okB, b = pcall(function() : string
					return (lv.dyn.brakingTimer > 0 and "braking" or "no_brake") .. (lv.dyn.turnLeft and "+left" or "") .. (lv.dyn.turnRight and "+right" or "")
				end)
				bump(braking, okB and b or "unreadable")
			else
				bump(braking, "no_land_vehicle")
			end
			if samples < 4 then
				samples = samples + 1
				D("11d sample e=%d state=%s blocked=%s reverse=%s servedFrom=%s servedTo=%s occupiedBack=%s occupiedFront=%s endPos=%s endParam=%s speed=%s accel=%s brakeDecel=%s timeUntilAccel=%s timeToIgnore=%s timeStanding=%s approachingStation=%s",
					e, num(mp.state), num(mp.blocked), tostring(mp.reverse), num(mp.servedFrom), num(mp.servedTo), num(mp.occupiedBackIndex),
					num(mp.occupiedFrontIndex), num(mp.endPos), num(mp.endParam), num(mp.dyn.speed), num(mp.dyn.accel), num(mp.dyn.brakeDecel),
					num(mp.dyn.timeUntilAccel), num(mp.dyn.timeToIgnore), num(mp.dyn.timeStanding), tostring(mp.dyn.approachingStation))
			end
			return false
		end, function(frames : integer, errors : integer, firstErr : string)
			D("11d state %s", flow.counts(states))
			D("11d blocked %s", flow.counts(blocked))
			D("11d speed_x_blocked %s", flow.counts(cross))
			D("11d land_vehicle %s", flow.counts(braking))
			rt.probe(name, true, string.format("drivers=%d (%s) VEHICLE_ORDER=%s readOnDrivers=%d orderLike={%s} state{%s} blocked{%s} frames=%d errors=%d%s",
				#drivers, source, tostring(direct ~= nil), orderRead, table.concat(orderish, ","), flow.counts(states), flow.counts(blocked),
				frames, errors, firstErr ~= nil and (" firstError: " .. firstErr) or ""))
		end)
	end)
end

---------------------------------------------------------------------------
-- 11e computeTownsTrafficSpeedMap from the GUI state's onStep (FLOW_PLAN.md open question 4): works?,
-- cost with coefficient 1 and 0.1 (one call per frame), per town the speed and the street counts per
-- congestion level (base town_util.tl:345, :459 call it from the town game script).

local function probeTownSpeed()
	local name = "flow_11e_towns"
	local results : {string} = {}
	local coefs : {number} = { 1.0, 0.1 }
	local okAll = false
	sliced(name, #coefs, 1, function(k : integer) : boolean
		local coef = coefs[k]
		local t0 = rt.nowUs()
		local ok, m = pcall(api.engine.util.town.computeTownsTrafficSpeedMap, coef)
		local us = rt.nowUs() - t0
		if not ok or m == nil then
			results[#results + 1] = string.format("coef=%s us=%d error=%s", num(coef), us, tostring(m))
			return false
		end
		okAll = true
		local n, speeds, levelLen = 0, {} as {number}, {} as {string : integer}
		local okP, errP : boolean, any = pcall(function()
			for town, v in pairs(m as {integer : {any}}) do
				n = n + 1
				local sp = v[1]
				if type(sp) == "number" then speeds[#speeds + 1] = sp as number end
				local lv = v[2]
				local okL, len = pcall(function() : integer return #(lv as {integer}) end)
				bump(levelLen, okL and tostring(len) or "?")
				if k == 1 and n <= 15 then
					local okN, tn = pcall(api.engine.util.getEntityName, town)
					local tname = okN and (string.gsub(tostring(tn), "%s+", "_")) or "?"
					D("11e town=%d name=%s speed=%s levels=%s", town, tname, num(sp), list(lv, 12))
				end
			end
		end)
		results[#results + 1] = string.format("coef=%s us=%d towns=%d speed{%s} levelsLen{%s}%s", num(coef), us, n, flow.stats(speeds),
			flow.counts(levelLen), okP and "" or (" iterate error: " .. tostring(errP)))
		D("11e %s", results[#results])
		return false
	end, function(frames : integer, errors : integer, firstErr : string)
		rt.probe(name, okAll, string.format("%s frames=%d errors=%d%s", table.concat(results, " | "), frames, errors,
			firstErr ~= nil and (" firstError: " .. firstErr) or ""))
	end)
end

---------------------------------------------------------------------------
-- 11f Bus round-trip data (FLOW_PLAN.md open question 5): for vehicles of "SQST Bus N" lines (else any
-- player line) TRANSPORT_VEHICLE sectionTimes, lineStopDepartures, lastLineStopDeparture vs GAME_TIME,
-- read cost, util.line.getMaxFrequency; 10 s later the same reads again, with the game-time and
-- wall-time deltas (and GAME_SPEED) to pin the units.

local record BusRead
	v : integer
	line : integer
	last : integer
	deps : string
	depSpan : number
	secSum : number
end

local function gameTime() : integer, integer, integer
	local gt = comp(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	if gt == nil then return nil, nil, nil end
	return gt.gameTime, gt.gameTime0, gt.timeOfDaySec
end

local function gameSpeed() : integer
	local gs = comp(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	return gs ~= nil and gs.speedup or nil
end

--- One TRANSPORT_VEHICLE read; nil when gone or unreadable. us: the read's cost.
local function busRead(v : integer, gt : integer, tag : string) : BusRead, number
	if not exists(v) then return nil, 0 end
	local t0 = rt.nowUs()
	local tv = comp(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
	local us = rt.nowUs() - t0
	if tv == nil then return nil, us end
	local r : BusRead = { v = v, line = tv.line, last = tv.lastLineStopDeparture }
	local lo, hi : number, number = nil, nil
	for _, d in ipairs(tv.lineStopDepartures or {}) do
		if d ~= nil and d > 0 then
			if lo == nil or d < lo then lo = d end
			if hi == nil or d > hi then hi = d end
		end
	end
	r.depSpan = lo ~= nil and (hi - lo) or nil
	local sum = 0.0
	for _, s in ipairs(tv.sectionTimes or {}) do sum = sum + s end
	r.secSum = sum
	r.deps = list(tv.lineStopDepartures, 8)
	D("11f %s vehicle=%d line=%s stopIndex=%s state=%s read_us=%d gameTime=%s lastLineStopDeparture=%s age=%s lineStopDepartures=%s depSpan=%s sectionTimes=%s sectionSum=%s timeUntilDeparture=%s",
		tag, v, num(tv.line), num(tv.stopIndex), enumName("TransportVehicleState", tv.state, { "IN_DEPOT", "EN_ROUTE", "GOING_TO_DEPOT", "AT_TERMINAL" }),
		us, num(gt), num(tv.lastLineStopDeparture), (gt ~= nil and tv.lastLineStopDeparture ~= nil) and num(gt - tv.lastLineStopDeparture) or "?",
		r.deps, num(r.depSpan), list(tv.sectionTimes, 8), num(sum), num(tv.timeUntilDeparture))
	return r, us
end

local function probeBus()
	local name = "flow_11f_bus"
	rt.enqueue(name .. ":lines", 1, guard(name, function()
		local ok, ls = pcall(api.engine.system.lineSystem.getLinesForPlayer, rt.player())
		if not ok or ls == nil then
			rt.probe(name, false, "getLinesForPlayer failed: " .. tostring(ls))
			return
		end
		local ours, others : {integer}, {integer} = {}, {}
		for _, l in ipairs(ls as {integer}) do
			local okN, n = pcall(api.engine.util.getEntityName, l)
			if okN and n ~= nil and string.match(tostring(n), "^SQST Bus %d+$") ~= nil then ours[#ours + 1] = l else others[#others + 1] = l end
		end
		local pick = #ours > 0 and ours or others
		local src = #ours > 0 and string.format("%d SQST Bus lines", #ours) or string.format("no SQST Bus line, %d other lines", #others)
		local vehicles : {integer} = {}
		local freqs : {string} = {}
		for i = 1, math.min(BUS_LINES, #pick) do
			local l = pick[i]
			if exists(l) then
				local okV, lv = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, l)
				local okF, f = pcall(api.engine.util.line.getMaxFrequency, l)
				freqs[#freqs + 1] = string.format("%d:%s", l, okF and num(f) or "err")
				if okV and lv ~= nil then
					for j, v in ipairs(lv as {integer}) do
						if j > BUS_VEHICLES then break end
						vehicles[#vehicles + 1] = v
					end
				end
			end
		end
		if #vehicles == 0 then
			rt.probe(name, false, src .. ": no vehicle on the lines read; run Auto bus lines (Traffic tab) or a test with Traffic Bus lines first")
			return
		end
		local gt0, gtPrev, tod = gameTime()
		local wall0 = rt.nowUs()
		local speed0 = gameSpeed()
		D("11f game_time gameTime=%s gameTime0=%s timeOfDaySec=%s speed=%s maxFrequency{%s}", num(gt0), num(gtPrev), num(tod), num(speed0), table.concat(freqs, ","))
		local first : {integer : BusRead} = {}
		local costs : {number} = {}
		sliced(name, #vehicles, READ_PER_FRAME, function(k : integer) : boolean
			local r, us = busRead(vehicles[k], gt0, "t0")
			costs[#costs + 1] = us
			if r ~= nil then first[vehicles[k]] = r end
			return false
		end, function(_frames : integer, errors : integer, firstErr : string)
			rt.later(name .. ":recheck", BUS_RECHECK_MS, guard(name, function()
				local gt1 = gameTime()
				local wallS = (rt.nowUs() - wall0) / 1e6
				local changed, read = 0, 0
				for _, v in ipairs(vehicles) do
					local r = busRead(v, gt1, "t1")
					if r ~= nil then
						read = read + 1
						local a = first[v]
						if a ~= nil and (a.last ~= r.last or a.deps ~= r.deps) then changed = changed + 1 end
					end
				end
				local dGt = (gt0 ~= nil and gt1 ~= nil) and (gt1 - gt0) or nil
				rt.probe(name, read > 0, string.format(
					"%s vehicles=%d read_us{%s} recheck: wall=%.1fs gameTime %s->%s (delta %s, %s per wall s) speed=%s->%s departuresChanged=%d/%d errors=%d%s",
					src, #vehicles, flow.stats(costs), wallS, num(gt0), num(gt1), num(dGt), dGt ~= nil and wallS > 0 and num(dGt / wallS) or "?",
					num(speed0), num(gameSpeed()), changed, read, errors, firstErr ~= nil and (" firstError: " .. firstErr) or ""))
			end) as function())
		end)
	end), { quiet = true, label = "Flow probe" })
end

---------------------------------------------------------------------------
-- 11g Do placements stay CONSTRUCTION entities, and do script-built / construction street edges carry
-- PLAYER_OWNED? (FLOW_PLAN.md open question 6). Around the camera: CONSTRUCTION entities (octree;
-- base tutorial_story.tl:92 does the same), their file, owner and frozen nodes / edges; street edges by
-- owner x in-a-construction; their nodes by in-a-construction.

local function probePlacements()
	local name = "flow_11g_placements"
	local x, y = cameraPos(name)
	if x == nil then return end
	rt.enqueue(name .. ":query", 1, guard(name, function()
		local CT = api.type.ComponentType
		local me = rt.player()
		local okC, cons = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), NEAR_R, CT.CONSTRUCTION)
		local clist : {integer} = (okC and cons ~= nil) and (cons as {integer}) or {}
		local files : {string : integer} = {}
		local nCons = 0
		-- a town has hundreds of building constructions within 300 m: their reads are sliced too
		sliced(name .. ":cons", #clist, READ_PER_FRAME * 2, function(i : integer) : boolean
			local c = clist[i]
			nCons = nCons + 1
			if not exists(c) then bump(files, "gone") return false end
			local cc = comp(c, CT.CONSTRUCTION) as Engine.Component.Construction
			local file = cc ~= nil and tostring(cc.fileName) or "?"
			bump(files, file)
			if i <= CON_MAX and cc ~= nil then
				local po = comp(c, CT.PLAYER_OWNED) as Engine.Component.PlayerOwned
				local okT, p = pcall(function() : Vec3f return cc.transf:getTransl() end)
				D("11g construction=%d file=%s owner=%s ours=%s frozenNodes=%d frozenEdges=%d timeBuilt=%s at=%s",
					c, file, po ~= nil and num(po.player) or "none", tostring(po ~= nil and po.player == me),
					#(cc.frozenNodes or {}), #(cc.frozenEdges or {}), num(cc.timeBuilt),
					(okT and p ~= nil) and string.format("%.0f,%.0f(d=%.0fm)", p.x, p.y, math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)) or "?")
			end
			return false
		end, function(_cFrames : integer, _cErrors : integer, _cFirstErr : string)
			D("11g constructions r=%.0fm query=%s n=%d files{%s}", NEAR_R, okC and "ok" or ("error: " .. tostring(cons)), nCons, topCounts(files, 25))
			local okE, edges = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), NEAR_R, CT.BASE_EDGE)
			local elist : {integer} = {}
			if okE and edges ~= nil then
				for _, e in ipairs(edges as {integer}) do
					if #elist >= EDGE_MAX then break end
					elist[#elist + 1] = e
				end
			end
			local edgeTab, nodeTab : {string : integer}, {string : integer} = {}, {}
			local nodeSeen : {integer : boolean} = {}
			local streets = 0
			local function owner(e : integer) : string
				local po = comp(e, CT.PLAYER_OWNED) as Engine.Component.PlayerOwned
				if po == nil then return "unowned" end
				return po.player == me and "ours" or "other_owner"
			end
			local function inCon(fn : function(integer) : integer, e : integer) : string
				local ok, c = pcall(fn, e)
				if not ok then return "con?" end
				return (c ~= nil and c >= 0) and "in_con" or "free"
			end
			sliced(name, #elist, READ_PER_FRAME * 2, function(k : integer) : boolean
				local e = elist[k]
				if not exists(e) or comp(e, CT.BASE_EDGE_STREET) == nil then return false end
				streets = streets + 1
				bump(edgeTab, owner(e) .. "+" .. inCon(api.engine.system.streetConnectorSystem.getConstructionEntityForEdge, e))
				local be = comp(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
				if be ~= nil then
					for _, n in ipairs({ be.node0, be.node1 }) do
						if n ~= nil and not nodeSeen[n] and exists(n) then
							nodeSeen[n] = true
							bump(nodeTab, owner(n) .. "+" .. inCon(api.engine.system.streetConnectorSystem.getConstructionEntityForNode, n))
						end
					end
				end
				return false
			end, function(frames : integer, errors : integer, firstErr : string)
				D("11g street_edges r=%.0fm n=%d owner+construction{%s}", NEAR_R, streets, flow.counts(edgeTab))
				D("11g street_nodes owner+construction{%s}", flow.counts(nodeTab))
				rt.probe(name, okC and okE, string.format("camera=%.0f,%.0f r=%.0fm constructions=%d files{%s} streetEdges=%d edges{%s} nodes{%s} frames=%d errors=%d%s",
					x, y, NEAR_R, nCons, topCounts(files, 6), streets, flow.counts(edgeTab), flow.counts(nodeTab), frames, errors,
					firstErr ~= nil and (" firstError: " .. firstErr) or ""))
			end)
		end)
	end), { quiet = true, label = "Flow probe" })
end

---------------------------------------------------------------------------
-- 11h Position cost (zone membership by position): util.vehicle.getPosition and calcPathPosData per
-- driver (timed), the path fallback (current edge -> BASE_EDGE.node0 -> BASE_NODE.position, as
-- stress_traffic.tl driverPos) and the distance between the two, getPosition of line vehicles, and one
-- octree street-edge query around the camera (a zone lookup).

local function probePosition()
	local name = "flow_11h_position"
	local x, y = cameraPos(name)
	if x == nil then return end
	withDrivers(name, function(drivers : {integer}, source : string)
		local CT = api.type.ComponentType
		local t0 = rt.nowUs()
		local okO, edges = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), NEAR_R, CT.BASE_EDGE)
		local octUs = rt.nowUs() - t0
		D("11h octree BASE_EDGE r=%.0fm us=%d n=%s", NEAR_R, octUs, okO and tostring(#(edges as {integer})) or ("error: " .. tostring(edges)))
		local posUs, pdUs, pathUs, dist : {number}, {number}, {number}, {number} = {}, {}, {}, {}
		local zero, failed, notDriving = 0, 0, 0
		sliced(name, #drivers, READ_PER_FRAME, function(k : integer) : boolean
			local e = drivers[k]
			if not exists(e) then return false end
			-- a reused sample can be up to 20 s old: calcPathPosData only on a person still on a path
			if not flow.isDriver(e) then notDriving = notDriving + 1 return false end
			local a = rt.nowUs()
			local ok, p = pcall(api.engine.util.vehicle.getPosition, e)
			posUs[#posUs + 1] = rt.nowUs() - a
			if not ok or p == nil then failed = failed + 1
			elseif p.x == 0 and p.y == 0 then zero = zero + 1 end
			local b = rt.nowUs()
			pcall(api.engine.util.vehicle.calcPathPosData, e)
			pdUs[#pdUs + 1] = rt.nowUs() - b
			local c = rt.nowUs()
			local okP, nx, ny = pcall(function() : number, number
				local mp = api.engine.getComponent(e, CT.MOVE_PATH) as Engine.Component.MovePath
				local ent = currentStep(mp)
				local be = api.engine.getComponent(ent, CT.BASE_EDGE) as Engine.Component.BaseEdge
				local n = api.engine.getComponent(be.node0, CT.BASE_NODE) as Engine.Component.BaseNode
				return n.position.x, n.position.y
			end)
			pathUs[#pathUs + 1] = rt.nowUs() - c
			if ok and p ~= nil and okP and nx ~= nil then dist[#dist + 1] = math.sqrt((p.x - nx) ^ 2 + (p.y - ny) ^ 2) end
			return false
		end, function(frames : integer, errors : integer, firstErr : string)
			D("11h getPosition_us %s zero=%d failed=%d notDriving=%d", flow.stats(posUs), zero, failed, notDriving)
			D("11h calcPathPosData_us %s", flow.stats(pdUs))
			D("11h path_node_fallback_us %s", flow.stats(pathUs))
			D("11h distance_getPosition_to_edge_node0_m %s", flow.stats(dist))
			-- line vehicles: one more slice
			local vs : {integer} = {}
			local okL, ls = pcall(api.engine.system.lineSystem.getLinesForPlayer, rt.player())
			if okL and ls ~= nil then
				for _, l in ipairs(ls as {integer}) do
					if #vs >= 20 then break end
					local okV, lv = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, l)
					if okV and lv ~= nil then
						for _, v in ipairs(lv as {integer}) do if #vs < 20 then vs[#vs + 1] = v end end
					end
				end
			end
			local busUs : {number} = {}
			local busZero = 0
			for _, v in ipairs(vs) do
				if exists(v) then
					local a = rt.nowUs()
					local ok, p = pcall(api.engine.util.vehicle.getPosition, v)
					busUs[#busUs + 1] = rt.nowUs() - a
					if ok and p ~= nil and p.x == 0 and p.y == 0 then busZero = busZero + 1 end
				end
			end
			D("11h line_vehicles getPosition_us %s zero=%d", flow.stats(busUs), busZero)
			rt.probe(name, #posUs > 0 and failed < #posUs, string.format("drivers=%d (%s) read=%d zero=%d failed=%d notDriving=%d octreeUs=%d lineVehicles=%d frames=%d errors=%d%s",
				#drivers, source, #posUs, zero, failed, notDriving, octUs, #vs, frames, errors, firstErr ~= nil and (" firstError: " .. firstErr) or ""))
		end)
	end)
end

---------------------------------------------------------------------------

--- Appends the 11a-11h buttons to the Probe tab's list.
function flow.addTo(out : {SquareStressProbeDef})
	local RO <const> = "\nRead only."
	add(out, "p11_movepath", "11a Flow: MOVE_PATH cost + units",
		"Probe 11: up to 200 drivers: MOVE_PATH read cost, path length,\ndyn.speed / timeStanding vs the lane's speedLimit and getSpeed." .. RO, probeMovePath)
	add(out, "p11_path_entity", "11b Flow: path entity in junctions",
		"Probe 11: what a car's current path step is (street edge, node, ...),\ncounted over up to 200 drivers, plus the kinds along whole paths." .. RO, probePathEntity)
	add(out, "p11_moving", "11c Flow: cars per edge / node query",
		"Probe 11: getSimPersonsMovingForTransportNetwork on street edges and\nnodes near the camera and under sampled drivers: shape, counts, cost." .. RO, probeMoving)
	add(out, "p11_order", "11d Flow: VehicleOrder, blocked, state",
		"Probe 11: is VehicleOrder readable; MOVE_PATH blocked / state values\nand LAND_VEHICLE braking among up to 200 drivers." .. RO, probeOrder)
	add(out, "p11_towns", "11e Flow: town traffic speed map",
		"Probe 11: computeTownsTrafficSpeedMap(1) and (0.1) from onStep: cost,\nspeed and street counts per congestion level per town." .. RO, probeTownSpeed)
	add(out, "p11_bus", "11f Flow: bus section times",
		"Probe 11: SQST Bus line vehicles: sectionTimes, lineStopDepartures,\nlastLineStopDeparture vs game time, again after 10 s." .. RO, probeBus)
	add(out, "p11_placements", "11g Flow: constructions + ownership",
		"Probe 11: CONSTRUCTION entities within 300 m of the camera, and\nstreet edges / nodes there by PLAYER_OWNED and construction." .. RO, probePlacements)
	add(out, "p11_position", "11h Flow: position cost",
		"Probe 11: getPosition / calcPathPosData / path-node position cost\nfor up to 200 drivers and 20 line vehicles; one octree query." .. RO, probePosition)
end

return flow
