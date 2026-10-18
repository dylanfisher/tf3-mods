-- Photo Mode: finding subjects on the map (GUI thread only: called from button clicks and the plugin's
-- react.onStep). Read-only: only api.engine getters, never a command.
--
-- Lists are cached (LIST_TTL_MS) so repeated clicks and the tour don't re-list the map; every pick reads a
-- handful of components. The "interesting" scans read a few components per vehicle within a time budget
-- (SCAN_BUDGET_MS, counted from the start of the pick, list build included, with api.type.Clock) and log how
-- much they covered. Each scan continues where its previous click stopped (cam.budgetedWalk), so repeated
-- clicks cover the whole fleet on a big save; "longest" also keeps its best train between clicks.
-- Nothing here runs per frame: only on a click, or once per tour hop (pm_driver).
--
-- Sources (api/tealdef/api/engine.d.tl, engine/system.d.tl):
--   vehicles    getEntitiesWithComponent(TRANSPORT_VEHICLE); TRANSPORT_VEHICLE.carrier / .state (IN_DEPOT skipped)
--   persons     getEntitiesWithComponent(SIM_PERSON). MODEL_PERSON can't be listed: it raises "Cannot loop
--               over this component type" (game log 2026-10-13_0325, every list build), so it is tried once per
--               session only; positions still read MODEL_PERSON.position first
--   stations    getEntitiesWithComponent(STATION_GROUP)
--   towns       api.engine.terrain.makeMapFromGame(false, true, false, false).towns (pos, existing), as
--               square_stress_test stress_towns.tl townPositions; population =
--               townBuildingSystem.getTown2personCapacitiesMap()[town][1] (docs/findings/towns.md)
--   industries  getEntitiesWithComponent(INDUSTRY)
--   position    BOUNDING_VOLUME bbox centre (base scripts/entity_util.tl getPosition); a vehicle without one:
--               its middle carriage's (base mission/mission_task_util.tl:123-145); a person: MODEL_PERSON.position;
--               a station group without one: its first station's construction, then the station
--   place       a random point inside getBoundingBox (8 % in from each edge), framed above the terrain
--   shots       the photographer's shots (SHOT below, scoring and framing in ../pm_shots.lua); a vehicle's track:
--               MOVE_PATH path.edges[dyn.pathPos.edgeIndex + 1 (+-1)] = { EdgeId, forward }, its BASE_EDGE
--               (type NORMAL / BRIDGE / TUNNEL, node0 / node1) and the BASE_NODE positions; speed
--               MOVE_PATH dyn.speed (m/s); aircraft MOVE_PATH_AIRCRAFT aircraftState.flightState / dyn.velocity;
--               standing trains TRANSPORT_VEHICLE.loadState (api.type.TransportVehicle.LoadState); model year
--               api.res.modelRep.get(part.modelId).metadata.availability.yearFrom; water
--               api.engine.terrain.isOnWater; heights getHeightAt. Not done (cost): level crossings (needs the
--               node -> edges map per node), ships under bridges (an octree query per ship).
--   longest     the rail vehicle with the most parts (#TRANSPORT_VEHICLE.transportVehicleConfig.vehicles)
--   variety     (round 17) a bag per kind (../pm_variety.lua): the scans prefer a subject not shown yet in the
--               kind's cycle, the saved views come in shuffled order, and every pick carries its place in the
--               cycle (poolN of poolM) and its view variant (how often that subject was shown before), which the
--               driver turns into a new perspective.

local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local shots = ug_require "square_photo_mode::/photo_mode/pm_shots.lua"
local variety = ug_require "square_photo_mode::/photo_mode/pm_variety.lua"
local perf = (ug_require "square_photo_mode::/photo_mode/gui/pm_perf.lua").perf

local W = {}

local LIST_TTL_MS = 5000
local SLOW_TTL_MS = 30000 -- stations, towns, industries change slowly
-- A click's search, from the start of the pick (list build included): one hitch, below ~50 ms with the last
-- component read and the jump. Measured with api.type.Clock (docs/findings/gui.md "Timers and threads").
local SCAN_BUDGET_MS = 35
local PICK_TRIES = 60
W.SCAN_BUDGET_MS = SCAN_BUDGET_MS

local clock = nil
local function clockMs()
	if clock == nil then clock = api.type.Clock.new() end
	return clock:getTime() / 1000
end
function W.nowMs()
	local ok, t = pcall(clockMs)
	return ok and t or 0
end

local rng = nil
function W.rnd()
	if rng == nil then rng = cam.newRng(math.floor(W.nowMs() * 1000) + 12345) end
	return rng()
end

local CT = nil
local function ct()
	if CT == nil then CT = api.type.ComponentType end
	return CT
end

local function exists(e)
	if type(e) ~= "number" or e < 0 then return false end
	local ok, r = pcall(api.engine.entityExists, e)
	return ok and r == true
end

--- A component of `e`, or nil. getComponent wants "a valid, existing entity" (api/tealdef/api/engine.d.tl:1686-
--- 1690), and the cached lists (up to 30 s old) hold entities that may be gone since (vehicle sold, person
--- arrived, station removed): a missing component on a dead entity is the Engine.h:323 GetComponentDataIndex
--- assert class, which pcall can't stop. So every read checks entityExists right before.
local function comp(e, t)
	if not exists(e) then return nil end
	local ok, c = pcall(api.engine.getComponent, e, t)
	if ok then return c end
	return nil
end

-- SQPERF section names, built once (never `..` per call).
local LIST_SECTION = {}
for __, key in ipairs({ "vehicles", "persons", "stations", "industries", "towns" }) do
	LIST_SECTION[key] = "list_" .. key
end

local cache = {}
--- The cached list `key`, rebuilt by build() when older than ttl ms. One log line per rebuild.
local function cached(key, ttl, build)
	local now = W.nowMs()
	local c = cache[key]
	if c ~= nil and now - c.t < ttl then return c.list end
	local t0 = perf:start()
	local ok, list = pcall(build)
	if not ok then
		core.log("list " .. key .. " ERROR " .. tostring(list))
		list = {}
	end
	list = list or {}
	cache[key] = { t = now, list = list }
	perf:stop(LIST_SECTION[key] or "list", t0)
	core.log(string.format("list %s n=%d ms=%.1f", key, #list, W.nowMs() - now))
	return list
end

-- Budgeted scans: where each one stops, so the next click goes on from there (cleared with the cache).
local scans = {}

local bounds, boundsRead = nil, false

-- Round 17: the variety bag of each pick kind (pm_variety.lua); kept across clearCache (a cycle outlives the lists).
local bags = {}
local function bagOf(kind)
	local b = bags[kind]
	if b == nil then
		b = variety.newBag(kind == "saved" and math.huge or nil)
		bags[kind] = b
	end
	return b
end
local function fresh(kind, id) return variety.isFresh(bags[kind], id) end

function W.clearCache()
	cache = {}
	scans = {}
	bounds, boundsRead = nil, false
end

--- The map's extent { minX, minY, maxX, maxY } (api.engine.terrain.getBoundingBox, read once per photo mode
--- session), or nil when unreadable: the driver keeps every camera centre inside it (cam.safeView).
function W.mapBounds()
	if not boundsRead then
		boundsRead = true
		local ok, bb = pcall(function() return api.engine.terrain.getBoundingBox() end)
		bounds = ok and cam.boundsOf(bb) or nil
	end
	return bounds
end

--- The engine's entity list as is: getEntitiesWithComponent already returns a fresh Lua list
--- (api/tealdef/api/engine.d.tl: {Entity}), which is only read, never changed, so it is cached without a copy
--- (a copy doubled the time and memory of the persons list on a 100k-person save).
local function entities(t)
	return api.engine.getEntitiesWithComponent(t) or {}
end

---------------------------------------------------------------------------
-- Positions

local function bboxCentre(e)
	local bv = comp(e, ct().BOUNDING_VOLUME)
	if bv == nil then return nil end
	local mn, mx = bv.bbox.min, bv.bbox.max
	return (mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2
end

--- World position of an entity (x, y, z) or nil.
function W.position(e)
	local x, y, z = bboxCentre(e)
	if x ~= nil then return x, y, z end
	local cl = comp(e, ct().CARRIAGE_LIST)
	if cl ~= nil and cl.carriages ~= nil and #cl.carriages > 0 then
		local mid = cl.carriages[math.floor((#cl.carriages + 1) / 2)]
		x, y, z = bboxCentre(mid)
		if x ~= nil then return x, y, z end
		x, y, z = bboxCentre(cl.carriages[1])
		if x ~= nil then return x, y, z end
	end
	local mp = comp(e, ct().MODEL_PERSON)
	if mp ~= nil and mp.position ~= nil then return mp.position.x, mp.position.y, mp.position.z end
	return nil
end

local function stationGroupPosition(g)
	local x, y, z = bboxCentre(g)
	if x ~= nil then return x, y, z end
	local sg = comp(g, ct().STATION_GROUP)
	if sg == nil or sg.stations == nil or #sg.stations == 0 then return nil end
	local st = sg.stations[1]
	local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, st)
	if okC and con ~= nil and con >= 0 then
		x, y, z = bboxCentre(con)
		if x ~= nil then return x, y, z end
	end
	return bboxCentre(st)
end

local function heightAt(x, y)
	return api.engine.terrain.getHeightAt(api.type.Vec2f.new(x, y))
end
--- Terrain height at (x, y), or nil. Called every frame of a camera move (round 7: the eye-space solver,
--- pm_flight.solveEye, 4-6 per frame), so no closure per call: pcall on a module-level function.
local function groundAt(x, y)
	local ok, h = pcall(heightAt, x, y)
	if ok and type(h) == "number" then return h end
	return nil
end
W.groundAt = groundAt

-- Round 14: the terrain's BASE height (api.engine.terrain.getBaseHeightAt: no terrain alignments, the
-- non-permanent modifications of roads, tracks, industries and buildings; 4 m resolution) and whether a point is
-- on water. The diagnosis of the game's camera centre leaving getHeightAt + 4 at cuts, terraces and river banks
-- (pm_driver "centre fit"; findings map-camera.md "Tour eye jolts from the game's centre"). nil when unreadable.
local function baseHeightAt(x, y)
	return api.engine.terrain.getBaseHeightAt(api.type.Vec2f.new(x, y))
end
function W.baseGroundAt(x, y)
	local ok, h = pcall(baseHeightAt, x, y)
	if ok and type(h) == "number" then return h end
	return nil
end
local function onWater(x, y)
	return api.engine.terrain.isOnWater(api.type.Vec2f.new(x, y))
end
function W.waterAt(x, y)
	local ok, r = pcall(onWater, x, y)
	if ok then return r == true end
	return nil
end

---------------------------------------------------------------------------
-- Lists

local function vehicles() return cached("vehicles", LIST_TTL_MS, function() return entities(ct().TRANSPORT_VEHICLE) end) end

-- MODEL_PERSON raised "Cannot loop over this component type" in game (2026-10-13): tried once per Lua state.
local modelPersonListable = true
local function persons()
	return cached("persons", LIST_TTL_MS * 2, function()
		if modelPersonListable then
			local ok, list = pcall(entities, ct().MODEL_PERSON)
			if ok and #list > 0 then return list end
			if not ok then
				modelPersonListable = false
				core.log("list persons: MODEL_PERSON not listable (" .. tostring(list) .. "), using SIM_PERSON from now on")
			end
		end
		return entities(ct().SIM_PERSON)
	end)
end

local function stationGroups() return cached("stations", SLOW_TTL_MS, function() return entities(ct().STATION_GROUP) end) end
local function industries() return cached("industries", SLOW_TTL_MS, function() return entities(ct().INDUSTRY) end) end

local function towns()
	return cached("towns", SLOW_TTL_MS, function()
		local out = {}
		local map = api.engine.terrain.makeMapFromGame(false, true, false, false)
		for __, t in ipairs(map.towns) do
			if t.existing ~= nil and t.existing >= 0 then
				out[#out + 1] = { id = t.existing, x = t.pos.x, y = t.pos.y }
			end
		end
		return out
	end)
end

---------------------------------------------------------------------------
-- Vehicles

local function carrierKind(c)
	local C = api.type.enum.Carrier
	if c == C.RAIL then return "train" end
	if c == C.ROAD then return "road" end
	if c == C.TRAM then return "tram" end
	if c == C.AIR then return "plane" end
	if c == C.WATER then return "ship" end
	return "vehicle"
end

-- filter: which vehicle kinds a subject button takes
local FILTERS = {
	vehicle = function(k) return true end,
	train = function(k) return k == "train" end,
	road = function(k) return k == "road" or k == "tram" end,
	plane = function(k) return k == "plane" end,
	ship = function(k) return k == "ship" end,
}

--- The kind of a running vehicle ("train", "road", ...), nil for one in a depot or unreadable.
local function runningKind(v)
	local tv = comp(v, ct().TRANSPORT_VEHICLE)
	if tv == nil then return nil, nil end
	if tv.state == api.type.enum.TransportVehicleState.IN_DEPOT then return nil, tv end
	return carrierKind(tv.carrier), tv
end

local function vehicleSubject(v, kind, why)
	local x, y, z = W.position(v)
	if x == nil then return nil end
	return { entity = v, x = x, y = y, z = z, kind = kind, follow = true,
		airborne = kind == "plane" and cam.isAirborne(z, groundAt(x, y)), why = why }
end

local function pickVehicle(filterKey)
	local filter = FILTERS[filterKey]
	local list = vehicles()
	local hitKind = nil
	local v = cam.pickRandom(list, W.rnd, function(e)
		local k = runningKind(e)
		if k ~= nil and filter(k) then hitKind = k return true end
		return false
	end, PICK_TRIES)
	if v == nil then return nil end
	return vehicleSubject(v, hitKind, "random")
end

local pickT0 = 0 -- W.nowMs() at the start of the current pick: the scans' budget includes the list build

--- Walks the vehicle list within SCAN_BUDGET_MS (from the start of the pick), going on where the previous scan
--- `key` stopped (the first one starts at random); score(v, kind, tv) returns a number (or nil to skip) and
--- done = true to stop at once. keepBest: the best vehicle of earlier clicks is scored again first (while it
--- still runs), so the scans find the best of the whole fleet (round 17: it comes back once the cycle has shown
--- the others). Returns the best vehicle, its kind,
--- score, how many were read, the list size and the ms since the pick started. Round 17: a vehicle shown already
--- in the kind's variety cycle (pm_variety.isFresh) only wins when no fresh one is found, and never stops the scan.
local function scanVehicles(key, score, keepBest)
	local list = vehicles()
	local n = #list
	if n == 0 then return nil end
	local st = scans[key]
	if st == nil then
		st = { cursor = math.floor(W.rnd() * n), best = nil }
		scans[key] = st
	end
	local best, bestKind, bestScore = nil, nil, nil
	local shown, shownKind, shownScore = nil, nil, nil -- the best already shown in this cycle
	local overall, overallScore = nil, nil -- the best of all (kept between clicks for keepBest)
	local function consider(v)
		local kind, tv = runningKind(v)
		if kind == nil then return false end
		local okS, s, done = pcall(score, v, kind, tv)
		if not okS or s == nil then return false end
		if overallScore == nil or s > overallScore then overall, overallScore = v, s end
		if not fresh(key, v) then
			if shownScore == nil or s > shownScore then shown, shownKind, shownScore = v, kind, s end
			return false
		end
		if bestScore == nil or s > bestScore then best, bestKind, bestScore = v, kind, s end
		return done == true
	end
	if keepBest and st.best ~= nil and exists(st.best) then consider(st.best) end
	local cursor, read = cam.budgetedWalk(n, st.cursor, function(i) return consider(list[i]) end,
		function() return W.nowMs() - pickT0 > SCAN_BUDGET_MS end)
	st.cursor = cursor
	if keepBest then st.best = overall end
	if best == nil then best, bestKind, bestScore = shown, shownKind, shownScore end
	return best, bestKind, bestScore, read, n, W.nowMs() - pickT0
end

---------------------------------------------------------------------------
-- The photographer's shots (scoring and framing: pm_shots.lua). Each is a budgeted scan (scanVehicles: one
-- click's 35 ms, going on where its last click stopped) or a handful of terrain reads, and returns a subject
-- with `framing` ({ x, y, d, p, look }), which the driver turns into a view facing the right way.

local function side() return W.rnd() < 0.5 and -1 or 1 end

--- MOVE_PATH of a land vehicle and the path edge `off` places from the current one: edge entity, forward.
local function pathEdge(mp, off)
	local ok, e, fwd = pcall(function()
		local ed = mp.path.edges[mp.dyn.pathPos.edgeIndex + 1 + (off or 0)]
		if ed == nil then return nil end
		return ed[1].entity, ed[2]
	end)
	if ok then return e, fwd end
	return nil
end

local function nodeXY(n)
	local bn = comp(n, ct().BASE_NODE)
	if bn == nil or bn.position == nil then return nil end
	return bn.position.x, bn.position.y
end

--- An edge's BASE_EDGE and the positions of its two nodes (node0 x, y, node1 x, y), or nil.
local function edgeData(edge)
	local be = comp(edge, ct().BASE_EDGE)
	if be == nil then return nil end
	local ax, ay = nodeXY(be.node0)
	local bx, by = nodeXY(be.node1)
	if ax == nil or bx == nil then return be end
	return be, ax, ay, bx, by
end

--- The heading a vehicle moves along on `edge` (forward: the path's direction flag), or nil.
local function edgeHeading(edge, forward)
	local be, ax, ay, bx, by = edgeData(edge)
	if ax == nil then return nil, be end
	if forward == false then ax, ay, bx, by = bx, by, ax, ay end
	return shots.heading(bx - ax, by - ay), be
end

--- A vehicle's movement: MOVE_PATH, speed (m/s), heading on its current edge and that edge's BASE_EDGE.
local function movement(v)
	local mp = comp(v, ct().MOVE_PATH)
	if mp == nil then return nil end
	local okS, speed = pcall(function() return mp.dyn.speed end)
	local edge, fwd = pathEdge(mp, 0)
	local heading, be = nil, nil
	if edge ~= nil then heading, be = edgeHeading(edge, fwd) end
	return mp, okS and tonumber(speed) or 0, heading, be, edge
end

local function isWater(x, y)
	local ok, r = pcall(function() return api.engine.terrain.isOnWater(api.type.Vec2f.new(x, y)) end)
	return ok and r == true
end

local function budgetLeft() return W.nowMs() - pickT0 <= SCAN_BUDGET_MS end

local function framed(v, kind, why, f, extra)
	if f == nil then return nil end
	local x, y, z = W.position(v)
	local s = { entity = v, x = f.x, y = f.y, z = z, kind = kind, follow = true, why = why, framing = f }
	if extra ~= nil then for k, val in pairs(extra) do s[k] = val end end
	return s
end

local SHOT = {}

--- Train on a bridge: the deck height above the terrain counts most (pm_shots.bridgeScore); side-on from below.
function SHOT.bridge()
	local BRIDGE = api.type.enum.BaseEdgeType.BRIDGE
	local info = {}
	local v, kind, s, read, n, ms = scanVehicles("bridge", function(e, k)
		if k ~= "train" then return nil end
		local mp, speed, heading, be = movement(e)
		if be == nil or be.type ~= BRIDGE then return nil end
		local x, y, z = W.position(e)
		local g = x and groundAt(x, y)
		if g == nil then return nil end
		local score, great = shots.bridgeScore(z - g)
		info[e] = { x = x, y = y, h = z - g, heading = heading or W.rnd() * cam.TWO_PI }
		return score, great
	end)
	core.log(string.format("scan bridge: read %d of %d ms=%.1f height=%s", read or 0, n or 0, ms or 0,
		v and string.format("%.0f", info[v].h) or "-"))
	if v == nil then return nil end
	local i = info[v]
	return framed(v, kind, "bridge", shots.frameBridge(i.x, i.y, i.heading, i.h, side()))
end

--- Crossing water: a train or road vehicle on a bridge over water (isOnWater under it); side-on, low.
function SHOT.water()
	local BRIDGE = api.type.enum.BaseEdgeType.BRIDGE
	local info = {}
	local v, kind, s, read, n, ms = scanVehicles("water", function(e, k)
		if k ~= "train" and k ~= "road" and k ~= "tram" then return nil end
		local mp, speed, heading, be = movement(e)
		if be == nil or be.type ~= BRIDGE then return nil end
		local x, y, z = W.position(e)
		if x == nil or not isWater(x, y) then return nil end
		local g = groundAt(x, y) or z
		info[e] = { x = x, y = y, h = z - g, heading = heading or 0 }
		return shots.waterScore(true, true, z - g), true
	end)
	core.log(string.format("scan water: read %d of %d ms=%.1f found=%s", read or 0, n or 0, ms or 0, tostring(v ~= nil)))
	if v == nil then return nil end
	local i = info[v]
	return framed(v, kind, "water", shots.frameWater(i.x, i.y, i.heading, i.h, side()))
end

--- Two trains passing: moving trains' positions from this click's scan, the closest pair within maxSep.
function SHOT.passing()
	local t = shots.T.passing
	local points = {}
	local __, __, __, read, n, ms = scanVehicles("passing", function(e, k)
		if k ~= "train" then return nil end
		local mp = comp(e, ct().MOVE_PATH)
		local okS, speed = pcall(function() return mp.dyn.speed end)
		if not okS or (tonumber(speed) or 0) < t.minSpeed then return nil end
		local x, y = W.position(e)
		if x ~= nil then points[#points + 1] = { x = x, y = y, e = e } end
		return nil
	end)
	local function pairId(p, q) return math.min(p.e, q.e) .. "+" .. math.max(p.e, q.e) end
	-- round 17: a pair not shown yet in this cycle first
	local a, b, d = shots.closestPair(points, t.maxSep, function(p, q) return p.e ~= q.e and fresh("passing", pairId(p, q)) end)
	if a == nil then a, b, d = shots.closestPair(points, t.maxSep, function(p, q) return p.e ~= q.e end) end
	core.log(string.format("scan passing: read %d of %d ms=%.1f moving=%d pair=%s", read or 0, n or 0, ms or 0,
		#points, d and string.format("%.0fm", d) or "-"))
	if a == nil then return nil end
	local __, __, heading = movement(a.e)
	return framed(a.e, "train", "passing", shots.framePassing(a, b, heading or shots.heading(b.x - a.x, b.y - a.y) + math.pi / 2, side()),
		{ poolId = pairId(a, b) })
end

--- Tunnel portal: a train on an open edge next to a tunnel edge on its path (or the other way round), near the
--- node between them; framed from outside, looking into the portal.
function SHOT.tunnel()
	local ET = api.type.enum.BaseEdgeType
	local info = {}
	local v, kind, s, read, n, ms = scanVehicles("tunnel", function(e, k)
		if k ~= "train" then return nil end
		local mp = comp(e, ct().MOVE_PATH)
		if mp == nil then return nil end
		local cur = pathEdge(mp, 0)
		local beC = cur and comp(cur, ct().BASE_EDGE)
		if beC == nil then return nil end
		local x, y = W.position(e)
		if x == nil then return nil end
		local best, bestInfo = nil, nil
		for __, off in ipairs({ 1, -1 }) do
			local nb = pathEdge(mp, off)
			local beN = nb and comp(nb, ct().BASE_EDGE)
			if beN ~= nil and (beC.type == ET.TUNNEL) ~= (beN.type == ET.TUNNEL) then
				-- the portal: the node the two edges share
				local portal = nil
				for __, a in ipairs({ beC.node0, beC.node1 }) do
					if a == beN.node0 or a == beN.node1 then portal = a end
				end
				local px, py = nil, nil
				if portal ~= nil then px, py = nodeXY(portal) end
				if px ~= nil then
					local openBe = beC.type == ET.TUNNEL and beN or beC
					local far = openBe.node0 == portal and openBe.node1 or openBe.node0
					local ox, oy = nodeXY(far)
					local dist = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
					local sc = ox and shots.tunnelScore(beC.type == ET.TUNNEL, beN.type == ET.TUNNEL, dist, beC.type ~= ET.TUNNEL)
					if sc ~= nil and (best == nil or sc > best) then
						best, bestInfo = sc, { px = px, py = py, ox = ox, oy = oy }
					end
				end
			end
		end
		if best ~= nil then info[e] = bestInfo end
		return best
	end)
	core.log(string.format("scan tunnel: read %d of %d ms=%.1f found=%s", read or 0, n or 0, ms or 0, tostring(v ~= nil)))
	if v == nil then return nil end
	local i = info[v]
	return framed(v, kind, "tunnel", shots.frameTunnel(i.px, i.py, i.ox, i.oy, side()))
end

--- Landing / take-off: aircraft in TakeOff / Landing (best) or Approach, low over the ground; the camera on the
--- ground ahead of it, looking back along its path.
function SHOT.approach()
	local FS = api.type.enum.FlightState
	local info = {}
	local v, kind, s, read, n, ms = scanVehicles("approach", function(e, k)
		if k ~= "plane" then return nil end
		local mpa = comp(e, ct().MOVE_PATH_AIRCRAFT)
		local st = mpa and mpa.aircraftState
		if st == nil then return nil end
		local fs = st.flightState
		local rank = (fs == FS.TakeOff or fs == FS.Landing) and 3 or (fs == FS.Approach and 2 or nil)
		if rank == nil then return nil end
		local x, y, z = W.position(e)
		local g = x and groundAt(x, y)
		if g == nil then return nil end
		local sc = shots.approachScore(rank, z - g)
		if sc == nil then return nil end
		local okV, vx, vy = pcall(function() return st.dyn.velocity.x, st.dyn.velocity.y end)
		if not okV then return nil end
		info[e] = { x = x, y = y, vx = vx, vy = vy }
		return sc, rank == 3 and z - g < 120
	end)
	core.log(string.format("scan approach: read %d of %d ms=%.1f score=%s", read or 0, n or 0, ms or 0, tostring(s)))
	if v == nil then return nil end
	local i = info[v]
	return framed(v, "plane", "approach", shots.frameApproach(i.x, i.y, i.vx, i.vy), { follow = false })
end

--- Busy street: the grid cell with the most running road vehicles (this click's scan); low, down the street.
function SHOT.rush()
	local t = shots.T.rush
	local points = {}
	local __, __, __, read, n, ms = scanVehicles("rush", function(e, k)
		if k ~= "road" and k ~= "tram" then return nil end
		local x, y = W.position(e)
		if x ~= nil then points[#points + 1] = { x = x, y = y } end
		return nil
	end)
	local cell, mx, my, count = shots.densestCell(points, t.cell, t.minCount)
	core.log(string.format("scan rush: read %d of %d ms=%.1f road=%d best=%s", read or 0, n or 0, ms or 0, #points,
		tostring(count)))
	if cell == nil then return nil end
	local f = shots.frameRush(mx, my, shots.mainAxis(cell), W.rnd() < 0.5)
	return f and { x = f.x, y = f.y, kind = "road", why = "rush", framing = f,
		poolId = math.floor(mx / t.cell) .. ":" .. math.floor(my / t.cell) } or nil
end

--- The biggest town (residents: getTown2personCapacitiesMap()[town][1], docs/findings/towns.md).
local function biggestTown()
	local caps = api.engine.system.townBuildingSystem.getTown2personCapacitiesMap()
	local t, pop = cam.maxBy(towns(), function(town)
		local c = caps[town.id]
		return c ~= nil and c[1] or nil
	end)
	return t, pop
end

--- Skyline: the biggest town from a ring of points around it (water first, then not much higher than the town).
function SHOT.skyline()
	local town, pop = biggestTown()
	if town == nil then return nil end
	local t = shots.T.skyline
	local gt = groundAt(town.x, town.y) or 0
	local samples = {}
	for i = 1, t.dirs do
		local dir = (i - 1) / t.dirs * cam.TWO_PI
		local x, y = town.x + math.cos(dir) * t.r, town.y + math.sin(dir) * t.r
		local g = groundAt(x, y)
		if g ~= nil then samples[#samples + 1] = { dir = dir, water = isWater(x, y), rise = g - gt, id = town.id .. ":" .. i } end
	end
	-- round 17: a direction not shown yet in this cycle first
	local unseen = {}
	for __, sm in ipairs(samples) do if fresh("skyline", sm.id) then unseen[#unseen + 1] = sm end end
	local best = shots.pickSkyline(unseen) or shots.pickSkyline(samples)
	core.log(string.format("skyline town %s population=%s water=%s", tostring(town.id), tostring(pop),
		tostring(best and best.water)))
	if best == nil then return nil end
	local f = shots.frameSkyline(town.x, town.y, best.dir, best.rise)
	return f and { entity = town.id, x = town.x, y = town.y, kind = "town", why = "skyline", framing = f,
		poolId = best.id } or nil
end

--- Viewpoint: around up to T.viewpoint.towns random towns, the highest ring point above its town (water between
--- them a bonus); framed from the hill, looking down at the town.
function SHOT.viewpoint()
	local t = shots.T.viewpoint
	local list = towns()
	if #list == 0 then return nil end
	local samples = {}
	local start = math.floor(W.rnd() * #list)
	for k = 1, math.min(t.towns, #list) do
		local town = list[(start + k - 1) % #list + 1]
		local gt = groundAt(town.x, town.y)
		if gt ~= nil then
			for __, r in ipairs(t.radii) do
				for i = 1, t.dirs do
					local dir = (i - 1) / t.dirs * cam.TWO_PI
					local x, y = town.x + math.cos(dir) * r, town.y + math.sin(dir) * r
					local g = groundAt(x, y)
					if g ~= nil and g - gt >= t.minRise then
						samples[#samples + 1] = { x = x, y = y, rise = g - gt, town = town,
							water = isWater((x + town.x) / 2, (y + town.y) / 2),
							id = math.floor(x + 0.5) .. ":" .. math.floor(y + 0.5) }
					end
				end
			end
		end
		if not budgetLeft() then break end
	end
	-- round 17: a hill not shown yet in this cycle first
	local unseen = {}
	for __, sm in ipairs(samples) do if fresh("viewpoint", sm.id) then unseen[#unseen + 1] = sm end end
	local best = shots.pickViewpoint(unseen) or shots.pickViewpoint(samples)
	core.log(string.format("viewpoint: %d high points, best rise=%s", #samples,
		best and string.format("%.0f", best.rise) or "-"))
	if best == nil then return nil end
	local f = shots.frameViewpoint(best.town.x, best.town.y, best.x, best.y, best.rise)
	return f and { entity = best.town.id, x = best.town.x, y = best.town.y, kind = "town", why = "viewpoint",
		framing = f, poolId = best.id } or nil
end

--- Train at a platform: a standing train that is loading, unloading or departing; longer and departing first.
function SHOT.departure()
	local LS = api.type.TransportVehicle.LoadState
	local info = {}
	local v, kind, s, read, n, ms = scanVehicles("departure", function(e, k, tv)
		if k ~= "train" then return nil end
		local ls = tv.loadState
		local loading = ls == LS.Loading or ls == LS.Unloading or ls == LS.Departing or ls == LS.WaitForScheduledDeparture
		if not loading then return nil end
		local mp, speed, heading = movement(e)
		local cfg = tv.transportVehicleConfig
		local parts = cfg ~= nil and cfg.vehicles ~= nil and #cfg.vehicles or 1
		local sc = shots.departureScore(speed, true, ls == LS.Departing, parts)
		if sc == nil then return nil end
		local x, y = W.position(e)
		if x == nil then return nil end
		info[e] = { x = x, y = y, heading = heading or W.rnd() * cam.TWO_PI, parts = parts }
		return sc
	end)
	core.log(string.format("scan departure: read %d of %d ms=%.1f score=%s", read or 0, n or 0, ms or 0, tostring(s)))
	if v == nil then return nil end
	local i = info[v]
	return framed(v, kind, "departure", shots.frameDeparture(i.x, i.y, i.heading, i.parts, side()))
end

-- Model years, per model id (api.res.modelRep metadata availability.yearFrom; 0 = unknown), cached per state.
local modelYear = {}
local function yearOf(tv)
	local ok, y = pcall(function()
		local id = tv.transportVehicleConfig.vehicles[1].part.modelId
		if modelYear[id] == nil then
			local m = api.res.modelRep.get(id)
			local av = m.metadata.availability or m.metadata["availability"]
			modelYear[id] = tonumber(av and av.yearFrom) or 0
		end
		return modelYear[id]
	end)
	return ok and y or 0
end

--- Oldest vehicle: the running vehicle of the oldest model (kept best across clicks, as the longest train).
function SHOT.oldest()
	local v, kind, s, read, n, ms = scanVehicles("oldest", function(e, k, tv)
		return shots.oldestScore(yearOf(tv))
	end, true)
	core.log(string.format("scan oldest: read %d of %d ms=%.1f year=%s", read or 0, n or 0, ms or 0,
		s and tostring(-s) or "-"))
	if v == nil then return nil end
	local x, y = W.position(v)
	if x == nil then return nil end
	local __, __, heading = movement(v)
	local t = shots.T.oldest
	local d = (cam.FRAMING[kind] or cam.FRAMING.vehicle).d * t.dScale
	return framed(v, kind, "oldest", shots.frameVehicle(x, y, heading or W.rnd() * cam.TWO_PI, d, t.p, t.yaw, side()))
end

--- Fastest vehicle: the train or road vehicle moving fastest right now (MOVE_PATH dyn.speed); followed.
function SHOT.fastest()
	local info = {}
	local v, kind, s, read, n, ms = scanVehicles("fastest", function(e, k)
		if k ~= "train" and k ~= "road" and k ~= "tram" then return nil end
		local mp, speed, heading = movement(e)
		if mp == nil or speed < 1 then return nil end
		info[e] = heading
		return speed
	end)
	core.log(string.format("scan fastest: read %d of %d ms=%.1f speed=%s", read or 0, n or 0, ms or 0,
		s and string.format("%.0fkm/h", s * 3.6) or "-"))
	if v == nil then return nil end
	local x, y = W.position(v)
	if x == nil then return nil end
	local d = (cam.FRAMING[kind] or cam.FRAMING.vehicle).d
	return framed(v, kind, "fastest", shots.frameFastest(x, y, info[v] or 0, d, side()), { followShot = true })
end

--- Longest train: the rail vehicle with the most parts (kept best across clicks); side-on.
function SHOT.longest()
	local v, kind, s, read, n, ms = scanVehicles("longest", function(e, k, tv)
		if k ~= "train" then return nil end
		local cfg = tv.transportVehicleConfig
		return cfg ~= nil and cfg.vehicles ~= nil and #cfg.vehicles or nil
	end, true)
	core.log(string.format("scan longest: read %d of %d ms=%.1f parts=%s", read or 0, n or 0, ms or 0, tostring(s)))
	if v == nil then return nil end
	local x, y = W.position(v)
	if x == nil then return nil end
	local __, __, heading = movement(v)
	return framed(v, kind, "longest", shots.frameLongest(x, y, heading or W.rnd() * cam.TWO_PI, s, side()))
end

--- A random place anywhere on the map (inside the terrain's bounds, 8 % in from each edge).
local function pickPlace()
	local b = W.mapBounds()
	if b == nil then return nil end
	local x, y = cam.randomPoint(b, W.rnd, 0.08)
	return { x = x, y = y, z = groundAt(x, y), kind = "place", why = "random place" }
end

--- Points a drone flight may head for (pm_flight.nextWaypoint), from the ticked flight subjects (`subjects`, a
--- set of cam.FLIGHT_SUBJECTS keys; nil = all): towns; landscape (land points, hills weighted up); water (sea,
--- lakes, coasts: isOnWater); rivers (narrow water: cam.waterKind, land on both sides 150 m out); rail lines
--- (where running trains are); points of interest (stations incl. airports and harbours, industries). The terrain
--- samples are random points (FLIGHT_SAMPLES isOnWater calls, up to 4 more per water hit for the river test);
--- a subject the map has none of (no river found) simply adds nothing, logged. Once per waypoint (about a
--- minute of flight) and per new Aerials area, never per frame.
local FLIGHT_SAMPLES = 24
local FLIGHT_SAMPLES_RIVERS = 48 -- rivers are narrow: more samples to hit one
function W.flightCandidates(subjects)
	local on = subjects or cam.DEFAULT_FLIGHT_SUBJECTS
	local out, count = {}, {}
	local function add(x, y, w, why)
		out[#out + 1] = { x = x, y = y, w = w, why = why }
		count[why] = (count[why] or 0) + 1
	end
	if on.towns then
		for __, t in ipairs(towns()) do add(t.x, t.y, 2, "town") end
	end
	if on.poi then
		local sg = stationGroups()
		for __ = 1, math.min(12, #sg) do
			local x, y = stationGroupPosition(sg[math.floor(W.rnd() * #sg) + 1])
			if x ~= nil then add(x, y, 1, "station") end
		end
		local ind = industries()
		for __ = 1, math.min(6, #ind) do
			local x, y = bboxCentre(ind[math.floor(W.rnd() * #ind) + 1])
			if x ~= nil then add(x, y, 0.8, "industry") end
		end
	end
	if on.rail then
		local vs = vehicles()
		local found, tries = 0, 0
		while found < 8 and tries < math.min(40, #vs) do
			tries = tries + 1
			local v = vs[math.floor(W.rnd() * #vs) + 1]
			if exists(v) and runningKind(v) == "train" then
				local x, y = W.position(v)
				if x ~= nil then
					add(x, y, 1.2, "rail")
					found = found + 1
				end
			end
		end
	end
	local b = W.mapBounds()
	if b ~= nil and (on.landscape or on.water or on.rivers) then
		local n = on.rivers and FLIGHT_SAMPLES_RIVERS or FLIGHT_SAMPLES
		local land, lowest = {}, nil
		for __ = 1, n do
			local x, y = cam.randomPoint(b, W.rnd, 0.12)
			local kind = cam.waterKind(isWater, x, y, 150)
			if kind == "river" and on.rivers then
				add(x, y, 2, "river")
			elseif kind ~= nil and on.water then
				add(x, y, 1.5, "water")
			elseif kind == nil and on.landscape and #land < FLIGHT_SAMPLES then
				local z = groundAt(x, y)
				if z ~= nil then
					land[#land + 1] = { x = x, y = y, z = z }
					if lowest == nil or z < lowest then lowest = z end
				end
			end
		end
		-- hills first: weight 0.6 .. 1.6 by the height above the lowest land sample
		local top = 0
		for __, p in ipairs(land) do top = math.max(top, p.z - lowest) end
		for __, p in ipairs(land) do
			add(p.x, p.y, 0.6 + (top > 0 and (p.z - lowest) / top or 0), "landscape")
		end
	end
	local parts = {}
	for __, k in ipairs(cam.FLIGHT_SUBJECTS) do
		if on[k] then
			local key = ({ towns = "town", poi = "station", rail = "rail", landscape = "landscape", water = "water",
				rivers = "river" })[k]
			local c = (count[key] or 0) + (k == "poi" and (count.industry or 0) or 0)
			parts[#parts + 1] = k .. "=" .. c .. (c == 0 and " (none found)" or "")
		end
	end
	core.log("flight candidates " .. table.concat(parts, " "))
	return out
end

---------------------------------------------------------------------------
-- Other subjects

-- The position the last accepted random pick was read at, so a pick reads its components once.
local hitX, hitY, hitZ = nil, nil, nil
local function hitAt(x, y, z)
	hitX, hitY, hitZ = x, y, z
	return x ~= nil
end

--- A person's position: MODEL_PERSON first (one read for a walker), else the generic chain.
local function personPosition(e)
	local mp = comp(e, ct().MODEL_PERSON)
	if mp ~= nil and mp.position ~= nil then return mp.position.x, mp.position.y, mp.position.z end
	return W.position(e)
end

local function pickPerson()
	local p = cam.pickRandom(persons(), W.rnd, function(e) return hitAt(personPosition(e)) end, 20)
	if p == nil then return nil end
	return { entity = p, x = hitX, y = hitY, z = hitZ, kind = "person", follow = true, why = "random" }
end

local function pickStation()
	local g = cam.pickRandom(stationGroups(), W.rnd, function(e) return hitAt(stationGroupPosition(e)) end, 20)
	if g == nil then return nil end
	return { entity = g, x = hitX, y = hitY, z = hitZ, kind = "station", why = "random" }
end

local function townSubject(t, why)
	return { entity = t.id, x = t.x, y = t.y, z = nil, kind = "town", why = why }
end

local function pickTown()
	local t = cam.pickRandom(towns(), W.rnd, nil, 1)
	return t and townSubject(t, "random") or nil
end

local function pickIndustry()
	local e = cam.pickRandom(industries(), W.rnd, function(i) return hitAt(bboxCentre(i)) end, 20)
	if e == nil then return nil end
	return { entity = e, x = hitX, y = hitY, z = hitZ, kind = "industry", why = "random" }
end

local PICKERS = {
	vehicle = function() return pickVehicle("vehicle") end,
	train = function() return pickVehicle("train") end,
	road = function() return pickVehicle("road") end,
	plane = function() return pickVehicle("plane") end,
	ship = function() return pickVehicle("ship") end,
	person = pickPerson,
	station = pickStation,
	town = pickTown,
	industry = pickIndustry,
	place = pickPlace,
	bridge = SHOT.bridge,
	water = SHOT.water,
	passing = SHOT.passing,
	tunnel = SHOT.tunnel,
	approach = SHOT.approach,
	rush = SHOT.rush,
	skyline = SHOT.skyline,
	viewpoint = SHOT.viewpoint,
	departure = SHOT.departure,
	oldest = SHOT.oldest,
	fastest = SHOT.fastest,
	longest = SHOT.longest,
}

--- The player's saved views (set by pm_driver.lua from the window's list; GUI save data): { { id, name, x, y, d,
--- a, p } } in list order.
W.savedViews = function() return {} end

--- "saved" (round 8): one of the player's saved views at random, as a subject with its own view (the tour's shots
--- and Anything draw from it; the window's Go and the saved-views tour play them in order). nil when none.
--- Round 17: a shuffle bag (pm_variety.choose): every saved view once before any comes back.
PICKERS.saved = function()
	local okL, list = pcall(W.savedViews)
	if not okL or type(list) ~= "table" or #list == 0 then return nil end
	local byId, ids = {}, {}
	for i, b in ipairs(list) do
		if type(b) == "table" and cam.finite(b.x) and cam.finite(b.y) and cam.finite(b.d) and cam.finite(b.a)
			and cam.finite(b.p) then
			local id = b.id ~= nil and b.id or ("#" .. i)
			if byId[id] == nil then
				byId[id] = b
				ids[#ids + 1] = id
			end
		end
	end
	local id = variety.choose(bagOf("saved"), ids, W.rnd)
	local b = id ~= nil and byId[id] or nil
	if b == nil then return nil end
	return { kind = "saved", x = b.x, y = b.y, view = { x = b.x, y = b.y, d = b.d, a = b.a, p = b.p },
		why = "saved view " .. tostring(b.id), id = b.id, poolId = id, poolSize = #ids }
end

--- Round 17: records a pick in its kind's variety bag (pm_variety.take): s.poolKind, s.poolN of s.poolM (its
--- place in the cycle) and s.variant (how often this subject was shown before: the driver varies the view).
--- The subject's id: s.poolId (a pair, a direction, a hill, a saved view), else its entity, else its place.
local function record(kind, s)
	if s == nil then return nil end
	local id = s.poolId
	if id == nil then id = s.entity end
	if id == nil and cam.finite(s.x) and cam.finite(s.y) then id = string.format("%.0f:%.0f", s.x, s.y) end
	s.poolKind = kind
	s.poolN, s.poolM, s.variant = variety.take(bagOf(kind), id, s.poolSize)
	return s
end

--- "Anything": the kinds of cam.ANY_KINDS in a weighted random order, the first that has something wins.
--- Kinds with nothing on the map cost one empty pick each (cached lists), so the weights share out among the
--- kinds that exist. A plain picker call each (not W.pick), so the 35 ms scan budget is not involved.
PICKERS.any = function()
	for __, kind in ipairs(cam.weightedOrder(cam.ANY_KINDS, W.rnd)) do
		local fn = PICKERS[kind]
		local okP, s = pcall(fn)
		if okP and s ~= nil then
			s.why = "any " .. kind
			return record(kind, s)
		end
	end
	return nil
end

local PICK_SECTION = {}
for kind in pairs(PICKERS) do PICK_SECTION[kind] = "pick_" .. kind end

---------------------------------------------------------------------------
-- "This place" tour (round 6, pm_place.lua): what is near the place.

local NEARBY_BUDGET_MS = 15 -- the vehicle walk of one lookup
local NEARBY_MAX = 16 -- of each kind
local NEARBY_PERSON_TRIES = 150 -- random persons' positions read per lookup

--- Subjects within r of (x, y): { entity, x, y, z, kind = "building" | <vehicle kind> | "person", moving }.
--- Buildings, stations, industries and depots: the constructions of the octree circle query
--- (api.engine.util.octree.findEntitiesInCircle(centre, r, CONSTRUCTION), as base mission code
--- build_construction_variant.tl:60), a random subset with their bounding-box centres. Running vehicles
--- (aircraft left out: a flying one is above any ground framing): the cached vehicle list walked within
--- NEARBY_BUDGET_MS, going on where the last lookup stopped (cam.budgetedWalk). People: NEARBY_PERSON_TRIES random
--- persons' positions. At most NEARBY_MAX of each. Called at the tour start and every pm_place.REFRESH_HOPS hops,
--- never per frame; logged with the counts and the time.
function W.nearby(x, y, r)
	local out, seen = {}, {}
	if not (cam.finite(x) and cam.finite(y) and cam.finite(r)) or r <= 0 then return out end
	local t0 = W.nowMs()
	local r2 = r * r
	local function add(e, px, py, pz, kind, moving)
		if px == nil or seen[e] then return false end
		local dx, dy = px - x, py - y
		if dx * dx + dy * dy > r2 then return false end
		seen[e] = true
		out[#out + 1] = { entity = e, x = px, y = py, z = pz, kind = kind, moving = moving }
		return true
	end
	local nb, nv, np = 0, 0, 0
	local okC, cons = pcall(function()
		return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), r, ct().CONSTRUCTION)
	end)
	if okC and type(cons) == "table" and #cons > 0 then
		local n = #cons
		local all = n <= NEARBY_MAX * 2 -- a few: every one; many: a random subset
		for i = 1, math.min(n, NEARBY_MAX * 2) do
			if nb >= NEARBY_MAX then break end
			local e = all and cons[i] or cons[math.floor(W.rnd() * n) + 1]
			if not seen[e] then
				local px, py, pz = bboxCentre(e)
				if add(e, px, py, pz, "building", false) then nb = nb + 1 end
			end
		end
	elseif not okC then
		core.log("place subjects: octree ERROR " .. tostring(cons))
	end
	local list = vehicles()
	local n = #list
	local read = 0
	if n > 0 then
		local st = scans.nearby
		if st == nil then
			st = { cursor = math.floor(W.rnd() * n) }
			scans.nearby = st
		end
		local tv0 = W.nowMs()
		st.cursor, read = cam.budgetedWalk(n, st.cursor, function(i)
			local v = list[i]
			local kind = runningKind(v)
			if kind ~= nil and kind ~= "plane" then
				local px, py, pz = W.position(v)
				if add(v, px, py, pz, kind, true) then nv = nv + 1 end
			end
			return nv >= NEARBY_MAX
		end, function() return W.nowMs() - tv0 > NEARBY_BUDGET_MS end)
	end
	local ps = persons()
	if #ps > 0 then
		for __ = 1, NEARBY_PERSON_TRIES do
			if np >= NEARBY_MAX then break end
			local e = ps[math.floor(W.rnd() * #ps) + 1]
			if not seen[e] then
				local px, py, pz = personPosition(e)
				if add(e, px, py, pz, "person", true) then np = np + 1 end
			end
		end
	end
	core.log(string.format("place subjects r=%.0f buildings=%d vehicles=%d (read %d of %d) persons=%d ms=%.1f", r, nb,
		nv, read, n, np, W.nowMs() - t0))
	return out
end

--- Where a nearby subject is now (a vehicle or person moves): x, y, z, or nil when it is gone.
function W.subjectPosition(s)
	if s == nil or not exists(s.entity) then return nil end
	if s.kind == "person" then return personPosition(s.entity) end
	if s.moving then return W.position(s.entity) end
	return s.x, s.y, s.z
end

--- A subject of `kind` (a key of PICKERS): { entity, x, y, z, kind (framing kind), follow (vehicle or person),
--- airborne, why } or nil when the map has none (or on an error, logged). Called on a click or a tour hop,
--- never every frame.
function W.pick(kind)
	local fn = PICKERS[kind]
	if fn == nil then return nil end
	pickT0 = W.nowMs()
	local t0 = perf:start()
	local ok, s = pcall(fn)
	perf:stop(PICK_SECTION[kind], t0)
	if not ok then
		core.log("pick " .. tostring(kind) .. " ERROR " .. tostring(s))
		return nil
	end
	if kind == "any" then return s end -- recorded under the kind it found
	return record(kind, s)
end

--- True when the entity still exists (a followed vehicle may have been sold).
W.exists = exists

--- True when a picked subject can still be followed / ridden: it exists and is still what it was picked as
--- (entity ids are reused after a removal): a vehicle with TRANSPORT_VEHICLE, not in a depot; a person with
--- MODEL_PERSON or SIM_PERSON. Checked right before followEntity / enterFollowCameraCockpit.
function W.alive(s)
	if s == nil or not exists(s.entity) then return false end
	local ok, r = pcall(function()
		if s.kind == "person" then
			return comp(s.entity, ct().MODEL_PERSON) ~= nil or comp(s.entity, ct().SIM_PERSON) ~= nil
		end
		local tv = comp(s.entity, ct().TRANSPORT_VEHICLE)
		return tv ~= nil and tv.state ~= api.type.enum.TransportVehicleState.IN_DEPOT
	end)
	return ok and r == true
end

---------------------------------------------------------------------------
-- Round 15 DEV: anchors for the cutscene aerial (pm_cutscene C.planFly; TESTING.md CD4)

-- What the octree is asked for, in order: any model entity, tree / rock groups, constructions (buildings,
-- industries, stations: the type W.nearby already queries). Which of them carry a FAT model instance (the
-- transform an attachment needs, as the campaign's carriages and spawned models: pm_cutscene C.anchorFor) is what
-- the prototype finds out: W.flyStats counts them per type for the log.
W.FLY_TYPES = { "MODEL_INSTANCE_LIST", "ASSET_GROUP", "CONSTRUCTION" }
W.FLY_MAX = 40 -- entities read per type and waypoint
W.flyStats = {}

--- The position of entity e's first fat model instance (x, y, z), or nil (none / unreadable).
local function fatPosition(e)
	local mil = comp(e, ct().MODEL_INSTANCE_LIST)
	if mil == nil then return nil end
	local ok, x, y, z = pcall(function()
		local fat = mil.fatInstances
		if fat == nil or #fat < 1 then return nil end
		local t = fat[1].transf:getTransl()
		return t.x, t.y, t.z
	end)
	if not ok or not cam.finite(x) or not cam.finite(y) then return nil end
	return x, y, cam.finite(z) and z or 0
end
W.fatPosition = fatPosition

--- Anchor candidates { entity, x, y, z, kind } within r of (x, y): entities with a fat model instance, positioned
--- by it. Counts per type in W.flyStats[type] = { found, fat } (an octree type that raises: { error }).
function W.flyCandidates(x, y, r)
	local out, seen = {}, {}
	if not (cam.finite(x) and cam.finite(y) and cam.finite(r)) or r <= 0 then return out end
	for __, tn in ipairs(W.FLY_TYPES) do
		local st = W.flyStats[tn] or { found = 0, fat = 0 }
		W.flyStats[tn] = st
		local t = ct()[tn]
		local okQ, list = pcall(function()
			return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), r, t)
		end)
		if not okQ then
			st.error = tostring(list)
		elseif type(list) == "table" then
			for i = 1, math.min(#list, W.FLY_MAX) do
				local e = list[i]
				if not seen[e] then
					seen[e] = true
					st.found = st.found + 1
					-- static anchors only: a carriage, a person or an animal would carry the camera away
					local moving = comp(e, ct().CARRIAGE) ~= nil or comp(e, ct().MODEL_PERSON) ~= nil
						or comp(e, ct().ANIMAL) ~= nil or comp(e, ct().MOVE_PATH) ~= nil
					local px, py, pz
					if moving then st.moving = (st.moving or 0) + 1 else px, py, pz = fatPosition(e) end
					if px ~= nil then
						st.fat = st.fat + 1
						out[#out + 1] = { entity = e, x = px, y = py, z = pz, kind = tn }
					end
				end
			end
		end
	end
	return out
end

--- "MODEL_INSTANCE_LIST 12/40 ASSET_GROUP 0/31 CONSTRUCTION 3/9" (fat / found), then cleared.
function W.flyStatsText()
	local parts = {}
	for __, tn in ipairs(W.FLY_TYPES) do
		local st = W.flyStats[tn]
		if st ~= nil then
			parts[#parts + 1] = st.error ~= nil and (tn .. " ERROR " .. st.error)
				or string.format("%s %d/%d%s", tn, st.fat, st.found,
					st.moving ~= nil and string.format(" (%d moving skipped)", st.moving) or "")
		end
	end
	W.flyStats = {}
	return table.concat(parts, " ") .. " (with a fat instance / found)"
end

return W
