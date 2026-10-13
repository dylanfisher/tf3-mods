-- Stress Test bus lines (PLAN.md Phase 3C): the stop / depot / line / bus helpers shared by the Probe
-- tab's probe 10 (stress_probes.tl) and the Traffic tab's "Auto bus lines" feature (this file, bottom).
-- Research and in-game results: plans/square_stress_test/PROBES_BUSLINES.md, docs/findings.md
-- "Stress Test probes" (fifth run).
--
-- STOPS (probe 10a/10b, fifth run: variant A worked on all 6 stops, ~40k each, one new STATION_GROUP
-- each). A street stop is an edge object, and an edge object can only be added to a NEW edge of the
-- same proposal ("Edge entity (must be a new edge in edgesToAdd, starting from -1 and decreasing)",
-- api/tealdef/api/type.d.tl:2764-2784). So the edge is replaced: 1 removed, 1 added segment whose
-- comp.objects holds {-400000000 + index, STOP_RIGHT} (base mission/tasks/build_construction/
-- mission_task_build_construction_util.tl:222-240; temp id base game_mechanics/towns/town_util.tl:
-- 1433-1442). The copy keeps BASE_EDGE / BASE_EDGE_STREET and the junction node configs are re-pointed
-- at it (subscribed move_it.script.tl:3700-3768). Variant B (no comp.objects) only if A fails. Stop
-- constructions: base stations/street/small_stops/small_{old,mid,new}.con by year (small_new.con.lua:55-62).
--
-- DEPOT (probe 10c). ConstructionEntity{fileName, params = {seed}, transf, playerEntity} in
-- constructionsToAdd (type.d.tl:2832-2851), resource "::/depots/road/road_depot/road_depot.con". Its
-- entrance street "lane1" runs from local (0,-35), a free node, to (0,-20.26); the building's collider
-- spans local x -17.7..38.5, y -20.1..19.9 (base depots/road/road_depot/road_depot.script.lua). The
-- fifth run showed (a) resultEntities[1][1] is NOT the construction (it had no CONSTRUCTION component),
-- so the depot is found by diffing the VEHICLE_DEPOT list and mapped to its construction with
-- streetConnectorSystem.getConstructionEntityForDepot (api/tealdef/api/engine/system.d.tl:237-240), and
-- (b) one spot often collides (messages={Collision}), so buildDepot walks a list of candidate spots
-- (depotTries: along the edge at 0.5/0.25/0.75, both sides, entrance 30/45/60 m off the street centre)
-- over several edges. Each spot is pre-checked without building anything: makeProposalData on the
-- depot proposal and on a stand-in stub street (api/tealdef/api/engine/util.d.tl:925; the native
-- function takes a SimpleProposal: subscribed move_it_probe_overpass overpass_probe.script.tl:325-330,
-- mods/square_roundabouts_probe probe_engine.lua runs it on the GUI thread). Only spots whose
-- pre-check shows no error are sent (if the pre-check itself is unavailable, the spot is sent and the
-- engine's answer decides), at most DEPOT_MAX_SENDS sends. A script proposal does not snap, so a second
-- proposal splits the street edge at the spot and adds a stub street to the depot's free node; the
-- stub is verified by the street edge count and the lane connections at that node. The stub is the
-- small town street (the entrance street's lanes), and the free node gets a full two-way config in the
-- same proposal (2026-10-12 Showcase v2: stubs copied from the 8-lane grid street were all refused
-- "Construction Not Possible"; the one gate that did join kept 0 lane connections, the red no-entry
-- sign, and findBestDepotForLine found no depot; docs/findings/lines-vehicles.md "Script-built road
-- depots"). Route lines build stops and depots only on their own town's streets (EdgeRule). Construction transforms never hold -0
-- (docs/findings.md "Negative zero"): every matrix entry goes through z0.
--
-- LINE AND BUS (probe 10d). makeLineCreateCmd(name, color, player, Line{stops = {Stop{stationGroup,
-- station = 0, terminal = 0}}}), the line in resultEntities[1][1] (base mission/tasks/vehicle_util/
-- mission_vehicle_util.tl:5-30). Bus: the newest model on sale this year that the vehicle shop lists
-- for a road depot (carrier ROAD, mode BUS, filter tag "default", year window: base gui/
-- line_vehicle_mgmt/vehicle_store_window.tl:4789-4816, vehicle_store_util.tl:315-320, 636-665, 731-737),
-- else a copy of one of the player's existing buses. Config as base replace_vehicles.tl:40-50 /
-- vehicle_util.makePart, purchase fields as vehicle_react_util.tl:331-340, then
-- makeVehicleSetLineCmd(vehicle, line, 0).
--
-- AUTO BUS LINES ORDER (sixth run, docs/findings.md): per town the depot comes FIRST (ours or any road
-- depot of the player within BUS_DEPOT_REUSE, else buildDepot over DEPOT_RINGS outward from the centre,
-- else the nearest road depot anywhere, which only counts if findBestDepotForLine confirms a depot once
-- the line exists); a town without one is skipped with nothing built. Then the stops and the line; the
-- buses come only from a depot findBestDepotForLine confirms (2026-10-12: buses bought at a depot of
-- another road network could not be put on the line); none: a new depot near stop 1 (STOP_DEPOT_RINGS),
-- asked again, else the line is given up before any bus is bought. A bus whose SetLine fails is sold
-- again. A line left with no bus is destroyed again (makeLineDestroyCmd) and its stops are logged as
-- wasted. Depot spots stay MAP_MARGIN inside the map, and a depot whose street connection is refused is
-- removed again before the next spot is tried. Route lines with a network (Showcase: bl.depotNet) reuse
-- only depots of that network and build only on their own town's streets. Every vehicle or line id is
-- re-checked (rt.isVehicle / rt.isLine) right before its command, and removal waits until the sold buses
-- are gone before it deletes a line (the sixth run's crash: a TransportVehicle read on a non-vehicle).
--
-- Road depots in the VEHICLE_DEPOT list: base code derives the carrier from transportModes
-- (gui/line_vehicle_mgmt/vehicle_util.tl:54-75) and only lists depots with in/out nodes
-- (manager_window.tl:1358-1364); the fifth run's 10d found none with VehicleDepot.carrier, so isRoadDepot
-- accepts either. The position comes from the depot's construction transform (Mat4f subscript 13/14,
-- type.d.tl:745-783), else its BOUNDING_VOLUME (base mission/mission_task_util.tl:123-135).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl" as SquareStressTowns
local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl" as SquareStressNodeCfg

local bl : SquareStressBusLines = {
	ui = { towns = 2, lines = 1, buses = 2 },
	lines = {},
	vehicles = {},
	depots = {},
	avoidPoints = {},
	lastGroups = {},
	lineTwins = {},
}

bl.MIN_STOP_EDGE = 30.0                -- chord; the stop sits at the middle, >= minDistToCrossing 10 m
bl.DEPOT_GAPS = { 30.0, 45.0, 60.0, 80.0 }   -- street centre -> the depot's free entrance node (stub length)
bl.DEPOT_PARAMS = { 0.5, 0.25, 0.75 }  -- where along the edge the stub leaves the street
bl.MIN_SPLIT_PIECE = 12.0              -- both halves of a split edge at least this long (chord)
bl.DEPOT_MAX_SENDS = 6                 -- real build commands per buildDepot (pre-checked spots)
bl.PAIR_MIN = 300.0                    -- auto bus lines: stop distance (middle to middle)
bl.PAIR_MAX = 800.0
bl.PAIR_TRIES = 30                     -- first edges tried as a pair's first stop
bl.STOP_AVOID = 100.0                  -- no new stop within this of a stop placed in the same batch
bl.TOWN_EDGE_RADIUS = 900.0            -- street edges searched around a town centre
bl.TOWN_EDGE_MAX = 300                 -- at most this many (nearest the centre) get the town checks
bl.BUS_DEPOT_REUSE = 2000.0            -- reuse any road depot of the player this close to the town
bl.DEPOT_RINGS = { { 300.0, 700.0 }, { 700.0, 1200.0 }, { 1200.0, 2000.0 }, { 0.0, 300.0 } }   -- depot search, in order
bl.RING_SAMPLE = 60                    -- edges of a ring scored (spread over the ring's distance range)
bl.RING_EDGES = 15                     -- of those, the fewest-buildings ones buildDepot tries
bl.DEPOT_CLEAR_RADIUS = 80.0           -- buildings counted around an edge's middle for the depot ranking
bl.BUILT_RADIUS = 60.0                 -- an edge with a town building this close counts as built-up
bl.MIN_LINE_BALANCE = 1000000          -- without Keep balance: no new line below this balance
bl.MAX_TOWN_FAILS = 3                  -- stop the batch after this many failed towns in a row
bl.MAX_ROUTE_FAILS = 10                -- route lines (Showcase, tests): stop after this many failed routes in all
bl.LINE_TIMEOUT_MS = 300000            -- one line (depot rings, 2 stops, line, N buses) at most
bl.REMOVE_WAIT_MS = 20000              -- Remove added bus lines: wait at most this for sold buses to be gone
bl.REMOVE_POLL_MS = 500
-- Depot spots (entrance and building origin) stay this far inside the map (the Junction test's and
-- Showcase's MAP_MARGIN; 2026-10-12 a depot 294 m from the map edge connected "Construction Not Possible").
bl.MAP_MARGIN = 400.0
-- A line whose depot does not reach it (findBestDepotForLine finds none): a new depot is searched in
-- these rings around its first stop (the stop's own town's streets) before the line is given up.
bl.STOP_DEPOT_RINGS = { { 0.0, 400.0 }, { 400.0, 900.0 } }
--- Showcase route lines: depot -> the road network ("group 3") it was built or confirmed
--- for; a depot is reused only within its own network (2026-10-12: a depot of the roundabout line was
--- reused for a group's line 1.2 km away on another network, findBestDepotForLine=-1, setLine failed).
bl.depotNet = {}

local EDGE_OBJECT_TEMP_ID <const> = -400000000
local DEPOT_CON <const> = "::/depots/road/road_depot/road_depot.con"
local DEPOT_ENTRANCE_Y <const> = -35.0    -- local y of the depot's free entrance node
local PRECHECKS_PER_STEP <const> = 6      -- pre-checks per queue step (spread over frames)
local SETTLE_MS <const> = 500             -- wait after a build callback before reading the result

local stopSeq = 0
local lineSeq = 0   -- the last "SQST Bus N" number given out (2026-10-10: a shared counter made it skip by 3)

---------------------------------------------------------------------------
-- Pure helpers (no engine calls; unit-tested)

function bl.z0(v : number) : number
	if v == 0 then return 0.0 end   -- -0 == 0: return +0
	return v
end
local z0 = bl.z0

function bl.dist2(a : {number}, b : {number}) : number
	local dx, dy = a[1] - b[1], a[2] - b[2]
	return math.sqrt(dx * dx + dy * dy)
end
local dist2 = bl.dist2

--- Point and derivative of a cubic Hermite edge (p0, t0, p1, t1) at param t.
function bl.hermiteAt(p0 : {number}, t0 : {number}, p1 : {number}, t1 : {number}, t : number) : {number}, {number}
	local t2, t3 = t * t, t * t * t
	local h00, h10, h01, h11 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
	local d00, d10, d01, d11 = 6 * t2 - 6 * t, 3 * t2 - 4 * t + 1, -6 * t2 + 6 * t, 3 * t2 - 2 * t
	local p, d = {}, {}
	for k = 1, 3 do
		p[k] = h00 * p0[k] + h10 * t0[k] + h01 * p1[k] + h11 * t1[k]
		d[k] = d00 * p0[k] + d10 * t0[k] + d01 * p1[k] + d11 * t1[k]
	end
	return p, d
end

local function scaled(v : {number}, f : number) : {number}
	return { v[1] * f, v[2] * f, v[3] * f }
end

--- Two edges whose middles are minD..maxD apart, the first among the first `tries` candidates (in the
--- given order); no edge with its middle within avoidR of a point in avoid. nil, nil when none.
function bl.pickEdgePair(cands : {SquareStressEdgeGeo}, minD : number, maxD : number, avoid : {{number}},
		avoidR : number, tries : integer) : SquareStressEdgeGeo, SquareStressEdgeGeo
	local function free(g : SquareStressEdgeGeo) : boolean
		for _, p in ipairs(avoid or {}) do
			if dist2(g.mid, p) < (avoidR or 0) then return false end
		end
		return true
	end
	local usable : {SquareStressEdgeGeo} = {}
	for _, g in ipairs(cands) do
		if free(g) then usable[#usable + 1] = g end
	end
	for i, a in ipairs(usable) do
		if i > (tries or 20) then break end
		for _, b in ipairs(usable) do
			local d = dist2(a.mid, b.mid)
			if b.id ~= a.id and d >= minD and d <= maxD then return a, b end
		end
	end
	return nil, nil
end

--- Candidate depot spots beside the given edges, in try order: per edge, per gap (nearest first),
--- per param along the edge, right side then left. Params whose split would leave a piece shorter than
--- MIN_SPLIT_PIECE, and spots where the edge has no direction, are left out.
function bl.depotTries(edges : {SquareStressEdgeGeo}, gaps : {number}, params : {number}) : {SquareStressDepotTry}
	local out : {SquareStressDepotTry} = {}
	for _, g in ipairs(edges) do
		for _, gap in ipairs(gaps) do
			for _, t in ipairs(params) do
				if t * g.length >= bl.MIN_SPLIT_PIECE and (1 - t) * g.length >= bl.MIN_SPLIT_PIECE then
					local p, d = bl.hermiteAt(g.p0, g.t0, g.p1, g.t1, t)
					local dl = math.sqrt(d[1] * d[1] + d[2] * d[2])
					if dl > 1e-6 then
						for _, side in ipairs({ 1, -1 }) do
							local n = { z0(d[2] / dl * side), z0(-d[1] / dl * side) }
							out[#out + 1] = { edge = g, t = t, side = side, gap = gap, point = p, n = n,
								entrance = { p[1] + n[1] * gap, p[2] + n[2] * gap, p[3] } }
						end
					end
				end
			end
		end
	end
	return out
end

--- Edges for the depot search in one ring (rMin <= dist < rMax from the town centre): at most `sample`
--- of them spread evenly over the ring's distance order, ranked by score (fewest buildings around; the
--- caller adds a penalty for another town's edges), then distance, then id; the first `max`. Second
--- result: the edges in the ring before sampling.
function bl.ringPick(cands : {SquareStressEdgeGeo}, rMin : number, rMax : number, sample : integer, max : integer,
		scoreOf : function(g : SquareStressEdgeGeo) : number) : {SquareStressEdgeGeo}, integer
	local inRing : {SquareStressEdgeGeo} = {}
	for _, g in ipairs(cands) do
		if g.dist >= rMin and g.dist < rMax then inRing[#inRing + 1] = g end
	end
	table.sort(inRing, function(a : SquareStressEdgeGeo, b : SquareStressEdgeGeo) : boolean
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.id < b.id
	end)
	local picked : {SquareStressEdgeGeo} = {}
	if #inRing <= sample then
		for i, g in ipairs(inRing) do picked[i] = g end
	else
		for k = 1, sample do picked[k] = inRing[math.floor((k - 1) * #inRing / sample) + 1] end
	end
	local score : {integer : number} = {}
	for _, g in ipairs(picked) do score[g.id] = scoreOf(g) end
	table.sort(picked, function(a : SquareStressEdgeGeo, b : SquareStressEdgeGeo) : boolean
		if score[a.id] ~= score[b.id] then return score[a.id] < score[b.id] end
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.id < b.id
	end)
	local out : {SquareStressEdgeGeo} = {}
	for i = 1, math.min(max, #picked) do out[i] = picked[i] end
	return out, #inRing
end

--- The next "SQST Bus N" number: one above both the last given out and the highest among the names.
function bl.nextLineNumber(names : {string}, last : integer) : integer
	local top = last or 0
	for _, n in ipairs(names) do
		local num = tonumber(string.match(n, "^SQST Bus (%d+)$"))
		if num ~= nil and num > top then top = math.floor(num) end
	end
	return top + 1
end

--- "edges=4 spots=72 tried=72 pre={Collision=72} sent=0 | no spot left" -> the counts and the last reason.
function bl.depotShort(details : string) : string
	local counts = string.match(details, "^(edges=%d+ spots=%d+ tried=%d+ pre={[^}]*} sent=%d+)")
	local tail = string.match(details, ".*| ([^|]*)$")
	if counts == nil then return details end
	return tail ~= nil and (counts .. " " .. tail) or counts
end

--- "e50 t=0.50 R30" for the log.
function bl.tryText(c : SquareStressDepotTry) : string
	return string.format("e%d t=%.2f %s%.0f", c.edge.id, c.t, c.side > 0 and "R" or "L", c.gap)
end

--- {reason = count} as "a=2,b=1" (sorted).
local function countsText(counts : {string : integer}) : string
	local parts : {string} = {}
	for k, n in pairs(counts) do parts[#parts + 1] = k .. "=" .. tostring(n) end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function str(v : any) : string
	return logic.listText(v)
end

---------------------------------------------------------------------------
-- Engine reads

local function comp(e : integer, ct : Engine.ComponentType) : any
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

local function fromVec3(v : Vec3f) : {number}
	return { v.x, v.y, v.z }
end

local function vec3(v : {number}) : Vec3f
	return api.type.Vec3f.new(z0(v[1]), z0(v[2]), z0(v[3]))
end

local function entityName(e : integer) : string
	local ok, n = pcall(api.engine.util.getEntityName, e)
	return ok and tostring(n) or "?"
end

function bl.listSet(ct : Engine.ComponentType) : {integer : boolean}, integer
	local ok, list = pcall(api.engine.getEntitiesWithComponent, ct)
	if not ok or list == nil then return {}, -1 end
	local set : {integer : boolean} = {}
	for _, e in ipairs(list as {integer}) do set[e] = true end
	return set, #(list as {integer})
end

function bl.newIn(before : {integer : boolean}, after : {integer : boolean}) : {integer}
	local out : {integer} = {}
	for e in pairs(after) do
		if not before[e] then out[#out + 1] = e end
	end
	table.sort(out)
	return out
end

--- Text of a build command's error state ("critical=... messages=..."), "(no error state)" if none.
function bl.errText(data : any) : string
	local ok, s = pcall(function() : string
		local d = data as WorldBuildProposalCommandData
		local es = d.resultProposalData.errorState
		return string.format("critical=%s messages=%s warnings=%s costs=%s", tostring(es.critical), str(es.messages),
			str(es.warnings), str(d.resultProposalData.costs))
	end)
	return ok and s or "(no error state)"
end

--- A street edge a stop or depot connection may go on, else nil and why not.
function bl.edgeGeo(e : integer, cx : number, cy : number) : SquareStressEdgeGeo, string
	local CT = api.type.ComponentType
	local be = comp(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
	if be == nil then return nil, "noEdge" end
	if comp(e, CT.BASE_EDGE_STREET) == nil then return nil, "track" end
	if be.objects ~= nil and #be.objects > 0 then return nil, "hasObjects" end
	local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForEdge, e)
	if okC and con ~= nil and con >= 0 then return nil, "construction" end
	local n0 = comp(be.node0, CT.BASE_NODE) as Engine.Component.BaseNode
	local n1 = comp(be.node1, CT.BASE_NODE) as Engine.Component.BaseNode
	if n0 == nil or n1 == nil then return nil, "noNodes" end
	local g : SquareStressEdgeGeo = { id = e, node0 = be.node0, node1 = be.node1, p0 = fromVec3(n0.position),
		p1 = fromVec3(n1.position), t0 = fromVec3(be.tangent0), t1 = fromVec3(be.tangent1) }
	local okT, tpl = pcall(function() : string return tostring(be.roadTemplate) end)
	g.template = okT and tpl ~= "nil" and tpl or ""
	g.length = dist2(g.p0, g.p1)
	if g.length < bl.MIN_STOP_EDGE then return nil, "short" end
	g.mid, g.dmid = bl.hermiteAt(g.p0, g.t0, g.p1, g.t1, 0.5)
	g.dist = dist2(g.mid, { cx, cy })
	return g, nil
end

--- Eligible street edges within r of (x, y), nearest middle first, and a summary.
function bl.streetEdgeCandidates(x : number, y : number, r : number) : {SquareStressEdgeGeo}, string
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, api.type.ComponentType.BASE_EDGE)
	if not ok or list == nil then return {}, "octree BASE_EDGE query failed: " .. tostring(list) end
	local out : {SquareStressEdgeGeo} = {}
	local why : {string : integer} = {}
	for _, e in ipairs(list as {integer}) do
		local okG, g, reason = pcall(bl.edgeGeo, e, x, y)
		if okG and g ~= nil then
			out[#out + 1] = g
		else
			local k = okG and (reason or "?") or "error"
			why[k] = (why[k] or 0) + 1
		end
	end
	table.sort(out, function(a : SquareStressEdgeGeo, b : SquareStressEdgeGeo) : boolean return a.dist < b.dist end)
	return out, string.format("edges(r=%.0fm)=%d eligible=%d skipped={%s}", r, #(list as {integer}), #out, countsText(why))
end

--- Station groups of the stations within r of (x, y) (octree STATION, as base tutorial_story.tl:770),
--- highest id first.
function bl.stationGroupsNear(x : number, y : number, r : number) : {integer}
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, api.type.ComponentType.STATION)
	if not ok or list == nil then return {} end
	local seen : {integer : boolean} = {}
	local out : {integer} = {}
	for _, st in ipairs(list as {integer}) do
		local okG, sg = pcall(api.engine.system.stationGroupSystem.getStationGroup, st)
		if okG and sg ~= nil and sg >= 0 and not seen[sg] then
			seen[sg] = true
			out[#out + 1] = sg
		end
	end
	table.sort(out, function(a : integer, b : integer) : boolean return a > b end)
	return out
end

--- Street edges at a node (streetSystem map), -1 when unreadable.
function bl.streetEdgesAt(node : integer) : integer
	local ok, m = pcall(api.engine.system.streetSystem.getNode2StreetEdgeMap)
	if not ok or m == nil then return -1 end
	local list = (m as {integer : {integer}})[node]
	return list ~= nil and #list or 0
end

---------------------------------------------------------------------------
-- Proposals

--- Node configs at the given nodes with oldEdge re-pointed (node -> new edge id). Read lane connections
--- are read-only (docs/findings/roads.md "Junction lane connections"), so rt.nodeConfigEntry rebuilds
--- them with api.type.LaneConnection.new(); a node without BASE_NODE_CONFIG is left out of both lists.
local function nodeConfigs(oldEdge : integer, nodeToNew : {{integer}}) : {Proposal.BaseNodeLaneConnectionAndEntity}, {integer}
	local add : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local rm : {integer} = {}
	for _, pair in ipairs(nodeToNew) do
		local node, newId = pair[1], pair[2]
		local okE, entry = pcall(rt.nodeConfigEntry, node, { [oldEdge] = newId }, nil)
		if okE and entry ~= nil then
			rm[#rm + 1] = node
			add[#add + 1] = entry
		end
	end
	return add, rm
end

-- Lane counts, the engine's two-way pattern and new-node configs: gui/stress_nodecfg.tl (shared with the
-- Junction test's link roads and the other street proposals).
local edgeLanes = nc.edgeLanes
local newNodeConfig = nc.newNodeConfig

--- A street segment copied from srcEdge (BASE_EDGE + BASE_EDGE_STREET) with new ends.
local function copiedSegment(id : integer, srcEdge : integer, n0 : integer, n1 : integer,
		p0 : {number}, t0 : {number}, p1 : {number}, t1 : {number}) : Proposal.SegmentAndEntity
	local seg = api.type.SegmentAndEntity.new()
	seg.entity = id
	seg.type = 0
	seg.comp = api.engine.getComponent(srcEdge, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
	seg.streetEdge = api.engine.getComponent(srcEdge, api.type.ComponentType.BASE_EDGE_STREET) as Engine.Component.BaseEdgeStreet
	seg.comp.node0 = n0
	seg.comp.node1 = n1
	seg.comp.position0 = vec3(p0)
	seg.comp.position1 = vec3(p1)
	seg.comp.tangent0 = vec3(t0)
	seg.comp.tangent1 = vec3(t1)
	seg.comp.objects = {}
	return seg
end

function bl.stopModel() : string
	local ok, year = pcall(api.engine.util.getYear)
	local y = ok and year or 2000
	if y >= 1980 then return "::/stations/street/small_stops/small_new.con" end
	if y >= 1920 then return "::/stations/street/small_stops/small_mid.con" end
	return "::/stations/street/small_stops/small_old.con"
end

--- The edge replaced by a copy (-1) that carries one stop at param 0.5 on the right side.
local function stopProposal(g : SquareStressEdgeGeo, model : string, stopName : string, withObjects : boolean) : SimpleProposal
	local proposal = api.type.SimpleProposal.new()
	local seg = copiedSegment(-1, g.id, g.node0, g.node1, g.p0, g.t0, g.p1, g.t1)
	if withObjects then
		seg.comp.objects = { { EDGE_OBJECT_TEMP_ID, api.type["enum"].EdgeObjectType.STOP_RIGHT } } as {{integer, EdgeObjectType}}
	end
	local eo = api.type.SimpleStreetProposal.EdgeObject.new()
	eo.edgeEntity = -1
	eo.param = 0.5
	eo.oneWay = false
	eo.left = false
	eo.model = model
	eo.playerEntity = rt.player()
	eo.name = stopName
	local cfgAdd, cfgRm = nodeConfigs(g.id, { { g.node0, -1 }, { g.node1, -1 } })
	-- an end node without a config (a script-made node) gets a fresh one (nc.complete)
	nc.complete({ seg }, { g.id }, cfgAdd, cfgRm)
	proposal.streetProposal.edgesToRemove = { g.id }
	proposal.streetProposal.edgesToAdd = { seg }
	proposal.streetProposal.edgeObjectsToAdd = { eo }
	proposal.streetProposal.nodeConfigsToRemove = cfgRm
	proposal.streetProposal.nodeConfigsToAdd = cfgAdd
	return proposal
end

--- Depot transform: local +y along n (away from the street), so the entrance (local -y) faces the
--- street; the free node at local (0, DEPOT_ENTRANCE_Y) lands on entrance. Column-major, -0 free.
function bl.depotTransf(entrance : {number}, n : {number}) : Mat4f, {number}
	local ox = entrance[1] - DEPOT_ENTRANCE_Y * n[1]
	local oy = entrance[2] - DEPOT_ENTRANCE_Y * n[2]
	local oz = api.engine.terrain.getHeightAt(api.type.Vec2f.new(ox, oy))
	local V = api.type.Vec4f.new
	return api.type.Mat4f.new(
		V(z0(n[2]), z0(-n[1]), 0.0, 0.0),
		V(z0(n[1]), z0(n[2]), 0.0, 0.0),
		V(0.0, 0.0, 1.0, 0.0),
		V(z0(ox), z0(oy), z0(oz), 1.0)), { ox, oy, oz }
end

local function depotProposal(transf : Mat4f) : SimpleProposal
	local proposal = api.type.SimpleProposal.new()
	local ce = api.type.SimpleProposal.ConstructionEntity.new()
	ce.fileName = DEPOT_CON
	ce.params = { seed = 1 }
	ce.transf = transf
	ce.playerEntity = rt.player()
	ce.name = "SQST Road Depot"
	proposal.constructionsToAdd = { ce }
	return proposal
end

--- The depot stub's street: the small town street of the year, whose lanes are exactly those of the
--- depot's own entrance street (entrance_new / entrance_old: 4 lanes 3/5/5/3 m, the same street style:
--- base infrastructure/street/{town,constructions}/*.street_template.lua). nil, nil when unreadable.
local function stubTemplate() : string, StreetTemplate
	local okY, year = pcall(api.engine.util.getYear)
	local path = (okY and year ~= nil and year < logic.WIDE_GRID_NEW_FROM) and "::/infrastructure/street/town/town_old_small.street_template"
		or "::/infrastructure/street/town/town_new_small.street_template"
	local ok, tpl = pcall(function() : StreetTemplate return api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(path)) end)
	if not ok or tpl == nil then return nil, nil end
	return path, tpl
end

--- The free entrance node's full node config (docs/findings/towns.md "Joining a script street to a town
--- dead end", D3): a plain join keeps the node's old config (0 lane connections: the red no-entry sign
--- at the depot gate), so the stub -3 and the depot's entrance edge get the engine's two-way pattern,
--- incoming road lane 1 -> outgoing lane 2 both ways (4 lanes each; ot_proposal.junctionConns). The
--- node is removed first only if it has a config (removing a missing one asserts Engine.cpp:693).
--- Each segment's own lanes and direction pick the indices (nc.connsAt: the stub -3's from its proposal
--- edge `stub`, the entrance edge's read), so a stub that fell back to a copy of a wider street still gets
--- valid ones and the pattern follows the driving side; lane counts are the fallback. Any light phases
--- of the old config are re-pointed (nc.relight; a depot gate has none in practice).
local function gateConfig(node : integer, entranceEdge : integer, stub : Proposal.SegmentAndEntity, stubLanes : integer) : Proposal.BaseNodeLaneConnectionAndEntity, boolean
	local cfg = comp(node, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
	local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
	entry.entity = node
	if cfg ~= nil then entry.comp = cfg end   -- keeps its crosswalks
	if entry.comp == nil then entry.comp = {} as Engine.Component.BaseNodeConfig end
	local bes : {integer : Engine.Component.BaseEdge} = {
		[entranceEdge] = comp(entranceEdge, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge,
		[-3] = stub ~= nil and stub.comp or nil,
	}
	local conns = nc.connsAt(node, { entranceEdge, -3 }, bes, { [entranceEdge] = edgeLanes(entranceEdge), [-3] = stubLanes })
	if cfg ~= nil then
		-- every old connection is replaced; crosswalks stay where they were
		local nOld, nCw = 0, 0
		pcall(function()
			nOld = #(cfg.laneConnections or {})
			nCw = #(cfg.crosswalks or {})
		end)
		local plain : {{integer}} = {}
		for _, c in ipairs(conns) do plain[#plain + 1] = { c.segment0, c.lane0, c.segment1, c.lane1 } end
		local cwMap : {integer : integer} = {}
		for k = 1, nCw do cwMap[k] = k end
		nc.relight(entry, cfg, {}, nOld, plain, cwMap, nCw)
	end
	entry.comp.laneConnections = conns
	return entry, cfg ~= nil
end

--- Splits g at param t (new node -4, halves -1 and -2) and adds a stub -3 from there to node (an
--- existing node, or a new node -5 at nodePos when node is nil: the pre-check's stand-in). The stub is
--- the small town street (stubTemplate), not a copy of g: 2026-10-12 every stub copied from the 8-lane
--- town_new_large grid street into the depot's 4-lane entrance node was refused "Construction Not
--- Possible" while the same stub to a new node pre-checked ok. With entranceEdge (the depot's own
--- entrance edge at node) the node gets its full config (gateConfig).
local function connectProposal(g : SquareStressEdgeGeo, t : number, node : integer, nodePos : {number}, entranceEdge? : integer) : SimpleProposal
	local proposal = api.type.SimpleProposal.new()
	local p, d = bl.hermiteAt(g.p0, g.t0, g.p1, g.t1, t)
	local split = api.type.NodeAndEntity.new()
	split.entity = -4
	split.comp.position = vec3(p)
	local nodes = { split }
	local target = node
	if target == nil then
		local stand = api.type.NodeAndEntity.new()
		stand.entity = -5
		stand.comp.position = vec3(nodePos)
		nodes[#nodes + 1] = stand
		target = -5
	end
	local stubT = { nodePos[1] - p[1], nodePos[2] - p[2], nodePos[3] - p[3] }
	local e1 = copiedSegment(-1, g.id, g.node0, -4, g.p0, scaled(g.t0, t), p, scaled(d, t))
	local e2 = copiedSegment(-2, g.id, -4, g.node1, p, scaled(d, 1 - t), g.p1, scaled(g.t1, 1 - t))
	local e3 = copiedSegment(-3, g.id, -4, target, p, stubT, nodePos, stubT)
	local gLanes = edgeLanes(g.id)
	local stubLanes = gLanes
	local path, tpl = stubTemplate()
	if path ~= nil then
		e3.comp.roadTemplate = path
		e3.comp.laneConfigs = tpl.laneConfigs
		e3.comp.roadStyle = tpl.streetStyle
		local okN, n = pcall(function() : integer return #tpl.laneConfigs end)
		stubLanes = (okN and n ~= nil and n >= 3) and n or 4
	end
	e3.comp.roadDevelopmentLocked = false
	local cfgAdd, cfgRm = nodeConfigs(g.id, { { g.node0, -1 }, { g.node1, -2 } })
	-- the new split node -4 (and the pre-check's stand-in -5) get configs too; -4's from each segment's
	-- own lanes and direction (nc.connsAt: the driving side is read, not assumed), -5 an empty one
	cfgAdd[#cfgAdd + 1] = newNodeConfig(-4, {}, {})
	cfgAdd[#cfgAdd].comp.laneConnections = nc.connsAt(-4, { -1, -2, -3 }, { [-1] = e1.comp, [-2] = e2.comp, [-3] = e3.comp },
		{ [-1] = gLanes, [-2] = gLanes, [-3] = stubLanes })
	if target == -5 then cfgAdd[#cfgAdd + 1] = newNodeConfig(-5, { -3 }, {}) end
	if node ~= nil and entranceEdge ~= nil then
		local entry, had = gateConfig(node, entranceEdge, e3, stubLanes)
		cfgAdd[#cfgAdd + 1] = entry
		if had then cfgRm[#cfgRm + 1] = node end
	end
	-- anything still without a config (an end node of g that has none, a target node without the gate
	-- config) gets one (nc.complete)
	nc.complete({ e1, e2, e3 }, { g.id }, cfgAdd, cfgRm)
	proposal.streetProposal.nodesToAdd = nodes
	proposal.streetProposal.edgesToRemove = { g.id }
	proposal.streetProposal.edgesToAdd = { e1, e2, e3 }
	proposal.streetProposal.nodeConfigsToRemove = cfgRm
	proposal.streetProposal.nodeConfigsToAdd = cfgAdd
	return proposal
end

--- Asks the engine whether a proposal could be built, without building it. "ok", a reason
--- ("Collision", "critical", ...) or nil when makeProposalData is unavailable.
local function precheck(proposal : SimpleProposal) : string
	local okU, util = pcall(function() : UtilProposal return api.engine.util.proposal end)
	if not okU or util == nil or util.makeProposalData == nil then return nil end
	local validate = util.makeProposalData as function(SimpleProposal) : ProposalData
	local ok, pd = pcall(validate, proposal)
	if not ok or pd == nil then return nil end
	local okE, reason = pcall(function() : string
		local es = pd.errorState
		if es == nil then return nil end
		if es.messages ~= nil and #es.messages > 0 then return tostring(es.messages[1]) end
		if es.critical then return "critical" end
		return "ok"
	end)
	if not okE then return nil end
	return reason
end

--- Short tags of the first entities of a command's resultEntities, for the log ("10438:edge").
local function resultText(res : {{integer}}) : string
	if res == nil then return "nil" end
	local CT = api.type.ComponentType
	local parts : {string} = {}
	for i, er in ipairs(res) do
		if i > 6 then parts[#parts + 1] = "..." break end
		local e = er[1]
		local tag = "?"
		if comp(e, CT.CONSTRUCTION) ~= nil then tag = "con"
		elseif comp(e, CT.VEHICLE_DEPOT) ~= nil then tag = "depot"
		elseif comp(e, CT.BASE_EDGE) ~= nil then tag = "edge"
		elseif comp(e, CT.BASE_NODE) ~= nil then tag = "node" end
		parts[#parts + 1] = string.format("%s:%s", tostring(e), tag)
	end
	return string.format("%d{%s}", #res, table.concat(parts, ","))
end

---------------------------------------------------------------------------
-- Stops

--- Places one stop on g (variant A, then B if A fails); onDone gets the station group (or nil).
function bl.placeStop(name : string, g : SquareStressEdgeGeo, onDone : function(ok : boolean, details : string, group : integer))
	local model = bl.stopModel()
	stopSeq = stopSeq + 1
	local stopName = string.format("SQST Stop %d", stopSeq)
	local before, nBefore = bl.listSet(api.type.ComponentType.STATION_GROUP)
	local head = string.format("edge=%d len=%.0fm mid=%.0f,%.0f model=%s", g.id, g.length, g.mid[1], g.mid[2], model)
	local function check(variant : string, success : boolean, data : any, res : {{integer}})
		local result = string.format("variant=%s success=%s %s", variant, tostring(success), bl.errText(data))
		rt.later(name .. ":check", SETTLE_MS, function()
			local after, nAfter = bl.listSet(api.type.ComponentType.STATION_GROUP)
			local new = bl.newIn(before, after)
			local near = bl.stationGroupsNear(g.mid[1], g.mid[2], 40)
			local group = new[1] or (success and near[1] or nil)
			if success then   -- every created entity id in the log, to match a later crash entity against
				bl.avoidPoints[#bl.avoidPoints + 1] = g.mid
				rt.detail(string.format("[SQST] %s stop built: %s edge=%d stationGroup=%s newGroups=%s result=%s", name, stopName, g.id,
					str(group), str(new), resultText(res)))
			end
			onDone(success and group ~= nil, string.format("%s %s STATION_GROUP %d->%d new=%s nearStop(40m)=%s group=%s",
				head, result, nBefore, nAfter, str(new), str(near), str(group)), group)
		end)
	end
	rt.send(name .. ":A", api.cmd.makeWorldBuildProposalCmd(stopProposal(g, model, stopName, true), nil, false, false), function(success : boolean, data : any, res : {{integer}})
		if success then
			check("A(objects)", true, data, res)
			return
		end
		local infoA = bl.errText(data)
		if not api.engine.entityExists(g.id) then
			check("A(objects)", false, data, res)
			return
		end
		rt.send(name .. ":B", api.cmd.makeWorldBuildProposalCmd(stopProposal(g, model, stopName, false), nil, false, false), function(okB : boolean, dataB : any, resB : {{integer}})
			check("B(no objects) A: " .. infoA .. " | B:", okB, dataB, resB)
		end)
	end)
end

---------------------------------------------------------------------------
-- Depots

--- The construction's free entrance node: the end of a frozen edge that is not frozen, nearest to pos.
local function freeNode(con : Engine.Component.Construction, pos : {number}) : integer, {number}, integer
	local CT = api.type.ComponentType
	local frozen : {integer : boolean} = {}
	for _, n in ipairs(con.frozenNodes or {}) do frozen[n] = true end
	local best, bestEdge : integer, integer = nil, nil
	local bestPos : {number} = nil
	local bestD = math.huge
	for _, e in ipairs(con.frozenEdges or {}) do
		local be = comp(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
		if be ~= nil then
			for _, n in ipairs({ be.node0, be.node1 }) do
				local bn = comp(n, CT.BASE_NODE) as Engine.Component.BaseNode
				if bn ~= nil and not frozen[n] then
					local p = fromVec3(bn.position)
					local d = dist2(p, pos)
					if d < bestD then best, bestPos, bestD, bestEdge = n, p, d, e end
				end
			end
		end
	end
	return best, bestPos, bestEdge
end

--- A node's lane connections ("-1": no BASE_NODE_CONFIG).
local function laneConnsAt(node : integer) : integer
	local cfg = comp(node, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
	if cfg == nil then return -1 end
	return #(cfg.laneConnections or {})
end

--- The depot's gate for the log: "gate node=N streetEdges=E laneConns=L" (L = 0 at a gate with street
--- edges: the red no-entry sign, buses can't leave the depot), or why it could not be read.
function bl.gateText(depot : integer) : string
	local ok, text = pcall(function() : string
		local conE = api.engine.system.streetConnectorSystem.getConstructionEntityForDepot(depot)
		local con = conE ~= nil and conE >= 0 and comp(conE, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction or nil
		if con == nil then return "gate ?(no construction)" end
		local pos = bl.depotPos(depot) or { 0, 0, 0 }
		local node = freeNode(con, pos)
		if node == nil then return "gate ?(no free node)" end
		return string.format("gate node=%d streetEdges=%d laneConns=%d", node, bl.streetEdgesAt(node), laneConnsAt(node))
	end)
	return ok and text or ("gate ?(" .. tostring(text) .. ")")
end

local function isValue(v : any, enumValue : any, text : string) : boolean
	return v == enumValue or v == text
end

--- Whether a VEHICLE_DEPOT is a road depot: VehicleDepot.carrier ROAD, or a road transport mode (BUS,
--- TRUCK, CAR) among its transportModes (base vehicle_util.getDepotCarriers derives it that way).
function bl.isRoadDepot(d : integer) : boolean, string
	local vd = comp(d, api.type.ComponentType.VEHICLE_DEPOT) as Engine.Component.VehicleDepot
	if vd == nil then return false, "noComp" end
	local E = api.type["enum"]
	if vd.carrier ~= nil then
		if isValue(vd.carrier, E.Carrier.ROAD, "ROAD") then return true, "carrier" end
	end
	local okM, road = pcall(function() : boolean
		for mode, on in pairs(vd.transportModes as {any : boolean} or {}) do
			if on and (isValue(mode, E.TransportMode.BUS, "BUS") or isValue(mode, E.TransportMode.TRUCK, "TRUCK")
				or isValue(mode, E.TransportMode.CAR, "CAR")) then return true end
		end
		return false
	end)
	if okM and road then return true, "modes" end
	return false, string.format("carrier=%s", tostring(vd.carrier))
end

--- Whether the depot has in/out nodes (base lists only those in the vehicle manager).
local function depotHasNodes(d : integer) : boolean
	local vd = comp(d, api.type.ComponentType.VEHICLE_DEPOT) as Engine.Component.VehicleDepot
	if vd == nil then return false end
	return #(vd.inNodes or {}) + #(vd.outNodes or {}) > 0
end

--- A depot's position and where it came from: its construction's transform, else its bounding volume.
function bl.depotPos(d : integer) : {number}, string
	local okC, conE = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot, d)
	if okC and conE ~= nil and conE >= 0 then
		local con = comp(conE, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
		if con ~= nil and con.transf ~= nil then
			local okT, p = pcall(function() : {number}
				local m = con.transf
				return { m[13], m[14], m[15] }
			end)
			if okT and p ~= nil and p[1] ~= nil then return p, "con" end
			local okG, v = pcall(function() : Vec3f return con.transf:getTransl() end)
			if okG and v ~= nil then return fromVec3(v), "conTransl" end
		end
	end
	for _, e in ipairs({ d, okC and conE or -1 }) do
		if e ~= nil and e >= 0 then
			local bv = comp(e, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
			if bv ~= nil and bv.bbox ~= nil then
				local okB, p = pcall(function() : {number}
					local a, b = bv.bbox.min, bv.bbox.max
					return { (a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2 }
				end)
				if okB and p ~= nil then return p, e == d and "bbox" or "conBbox" end
			end
		end
	end
	return nil, okC and "noPos" or ("conLookup error: " .. tostring(conE))
end

--- Nearest road depot within r of (x, y) (one with in/out nodes if any is in range), its distance,
--- and a diagnostic summary (the first 4 depots: road?, how, distance or position source, nodes).
function bl.nearestRoadDepot(x : number, y : number, r : number) : integer, number, string
	local ok, list = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.VEHICLE_DEPOT)
	if not ok or list == nil then return nil, nil, "VEHICLE_DEPOT list failed: " .. tostring(list) end
	local best, bare : integer, integer = nil, nil
	local bestD, bareD = r, r
	local road, withPos = 0, 0
	local notes : {string} = {}
	for _, d in ipairs(list as {integer}) do
		local isRoad, how = bl.isRoadDepot(d)
		if isRoad and not rt.ownedByPlayer(d) then isRoad, how = false, "otherPlayer" end
		local p, src = bl.depotPos(d)
		local dist = p ~= nil and dist2(p, { x, y }) or nil
		if isRoad then road = road + 1 end
		if p ~= nil then withPos = withPos + 1 end
		local nodes = depotHasNodes(d)
		if #notes < 4 then
			notes[#notes + 1] = string.format("%d:%s/%s/%s/nodes=%s", d, isRoad and "road" or "notRoad", how, dist ~= nil and string.format("%.0fm", dist) or src, tostring(nodes))
		end
		if isRoad and dist ~= nil then
			if nodes and dist <= bestD then best, bestD = d, dist end
			if not nodes and dist <= bareD then bare, bareD = d, dist end
		end
	end
	if best == nil and bare ~= nil then best, bestD = bare, bareD end
	return best, best ~= nil and bestD or nil, string.format("depots=%d road=%d withPos=%d [%s]", #(list as {integer}), road, withPos,
		table.concat(notes, " "))
end

--- After a depot build succeeded: the new road depot (VEHICLE_DEPOT diff, nearest the expected
--- origin, with nodes first) and its construction (getConstructionEntityForDepot, else a CONSTRUCTION
--- among resultEntities).
local function locateDepot(before : {integer : boolean}, res : {{integer}}, origin : {number}) : integer, integer, string
	local after, nAfter = bl.listSet(api.type.ComponentType.VEHICLE_DEPOT)
	local new = bl.newIn(before, after)
	local best : integer = nil
	local bestCon : integer = nil
	local bestScore = math.huge
	local notes : {string} = {}
	for _, d in ipairs(new) do
		local okC, conE = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForDepot, d)
		local con = okC and conE ~= nil and conE >= 0 and conE or nil
		local p = bl.depotPos(d)
		local dist = p ~= nil and dist2(p, origin) or 1e9
		local nodes = depotHasNodes(d)
		local score = dist + (nodes and 0 or 1e6)
		notes[#notes + 1] = string.format("%d(con=%s %s nodes=%s)", d, str(con), dist < 1e9 and string.format("%.0fm", dist) or "noPos", tostring(nodes))
		if score < bestScore then best, bestCon, bestScore = d, con, score end
	end
	if bestCon == nil then
		for _, er in ipairs(res or {}) do
			if comp(er[1], api.type.ComponentType.CONSTRUCTION) ~= nil then bestCon = er[1] break end
		end
	end
	return best, bestCon, string.format("VEHICLE_DEPOT +%d new=[%s] (total %d) result=%s", #new, table.concat(notes, " "), nAfter, resultText(res))
end

local function forget(list : {integer}, e : integer)
	for k = #list, 1, -1 do
		if list[k] == e then table.remove(list, k) end
	end
end

--- Whether p (x, y) lies at least `margin` inside the map's terrain box (read once per call site and
--- passed as box; nil: read now); true when the box can't be read.
function bl.insideMap(p : {number}, margin : number, box? : Box2f) : boolean
	if box == nil then
		local ok, b = pcall(function() : Box2f return api.engine.terrain.getBoundingBox() end)
		if not ok or b == nil then return true end
		box = b
	end
	local ok, inside = pcall(function() : boolean
		return p[1] >= box.min.x + margin and p[1] <= box.max.x - margin and p[2] >= box.min.y + margin and p[2] <= box.max.y - margin
	end)
	return not ok or inside
end

--- Builds a road depot beside one of the edges and connects its entrance to the street.
--- onDone(ok, details, depot): ok = the depot exists and its entrance node got a street edge.
function bl.buildDepot(name : string, edges : {SquareStressEdgeGeo}, cx : number, cy : number,
		onDone : function(ok : boolean, details : string, depot : integer))
	-- never a stub onto a highway or one-way street (the split node's config is the two-way pattern)
	local twoWay : {SquareStressEdgeGeo} = {}
	for _, g in ipairs(edges) do
		local r = logic.busEdgeReject(g.template, g.p0, g.p1, nil, nil, false)
		if r ~= "highway" and r ~= "oneway" then twoWay[#twoWay + 1] = g end
	end
	edges = twoWay
	local all = bl.depotTries(edges, bl.DEPOT_GAPS, bl.DEPOT_PARAMS)
	-- spots whose entrance or building lies within MAP_MARGIN of the map edge are left out
	local tries : {SquareStressDepotTry} = {}
	local okBox, box = pcall(function() : Box2f return api.engine.terrain.getBoundingBox() end)
	for _, c in ipairs(all) do
		local _, origin = bl.depotTransf(c.entrance, c.n)
		if not okBox or box == nil or (bl.insideMap(c.entrance, bl.MAP_MARGIN, box) and bl.insideMap(origin, bl.MAP_MARGIN, box)) then
			tries[#tries + 1] = c
		end
	end
	local outside = #all - #tries
	local before = bl.listSet(api.type.ComponentType.VEHICLE_DEPOT)
	local idx, sends = 0, 0
	local pre : {string : integer} = {}
	local sentText : {string} = {}
	local function head() : string
		return string.format("edges=%d spots=%d tried=%d pre={%s} sent=%d%s [%s]", #edges, #tries, idx, countsText(pre), sends,
			outside > 0 and string.format(" outside=%d", outside) or "", table.concat(sentText, "; "))
	end
	if #tries == 0 then
		onDone(false, head() .. " no depot spot (edges too short or no direction)", nil)
		return
	end
	local nextBatch : function()

	--- A depot that could not be connected is removed again (never left standing unconnected:
	--- 2026-10-12) and the next spot tried; `why` goes into the log.
	local function dropAndGoOn(c : SquareStressDepotTry, depot : integer, conE : integer, why : string)
		sentText[#sentText + 1] = string.format("%s not connected (%s)", bl.tryText(c), why)
		local function goOn(removed : boolean)
			sentText[#sentText + 1] = string.format("depot %s removed=%s", str(depot), tostring(removed))
			if removed then
				forget(bl.depots, depot)
				bl.depotNet[depot] = nil
				for k = #bl.avoidPoints, 1, -1 do
					if bl.avoidPoints[k] == c.entrance then table.remove(bl.avoidPoints, k) end
				end
			end
			nextBatch()
		end
		if conE == nil or not api.engine.entityExists(conE) then goOn(false) return end
		local okP, p = pcall(function() : SimpleProposal
			local proposal = api.type.SimpleProposal.new()
			proposal.constructionsToRemove = { conE }
			return proposal
		end)
		if not okP or p == nil then goOn(false) return end
		rt.send(name .. ":remove", api.cmd.makeWorldBuildProposalCmd(p, nil, false, false), function(okR : boolean, _d : any)
			goOn(okR)
		end)
	end

	local function connect(c : SquareStressDepotTry, depot : integer, conE : integer, located : string)
		local info = located
		local con = conE ~= nil and comp(conE, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction or nil
		if con == nil then
			onDone(false, string.format("%s | %s | construction=%s has no CONSTRUCTION component", head(), info, str(conE)), depot)
			return
		end
		local node, nodePos, entranceEdge = freeNode(con, c.entrance)
		info = string.format("%s depot=%s construction=%d frozenNodes=%d frozenEdges=%d freeNode=%s", info, str(depot), conE,
			#(con.frozenNodes or {}), #(con.frozenEdges or {}), str(node))
		if node == nil then
			dropAndGoOn(c, depot, conE, info .. " no free entrance node found")
			return
		end
		info = info .. string.format(" at %.1f,%.1f (%.1fm from target)", nodePos[1], nodePos[2], dist2(nodePos, c.entrance))
		local edgesBefore = bl.streetEdgesAt(node)
		if edgesBefore >= 2 then
			local conns = laneConnsAt(node)
			if conns == 0 then
				dropAndGoOn(c, depot, conE, info .. string.format(" joined, but a dead end (streetEdges at node=%d, laneConns=0)", edgesBefore))
				return
			end
			onDone(depot ~= nil, head() .. " | " .. info .. string.format(" already connected (streetEdges at node=%d, laneConns=%d)", edgesBefore, conns), depot)
			return
		end
		local g2 : SquareStressEdgeGeo = nil
		if api.engine.entityExists(c.edge.id) then g2 = bl.edgeGeo(c.edge.id, cx, cy) end
		if g2 == nil then
			dropAndGoOn(c, depot, conE, info .. string.format(" street edge %d changed", c.edge.id))
			return
		end
		local connsBefore = laneConnsAt(node)
		rt.send(name .. ":connect", api.cmd.makeWorldBuildProposalCmd(connectProposal(g2, c.t, node, nodePos, entranceEdge), nil, false, false),
			function(okC : boolean, dataC : any)
				rt.later(name .. ":connected", SETTLE_MS, function()
					local edgesAfter = bl.streetEdgesAt(node)
					-- a gate joined with no lane connections is a dead end (the red no-entry sign): not connected
					local connsAfter = laneConnsAt(node)
					local connected = okC and (edgesAfter >= 2 or edgesAfter > edgesBefore) and connsAfter ~= 0
					local text = string.format("%s connect: success=%s %s streetEdges at node %d->%d laneConns %d->%d (entrance edge %s, stub %s) connected=%s",
						info, tostring(okC), bl.errText(dataC), edgesBefore, edgesAfter, connsBefore, connsAfter, str(entranceEdge),
						(stubTemplate()) or "copy", tostring(connected))
					if connected and depot ~= nil then
						onDone(true, head() .. " | " .. text, depot)
					else
						dropAndGoOn(c, depot, conE, text)
					end
				end)
			end)
	end

	local function send(c : SquareStressDepotTry)
		sends = sends + 1
		local transf, origin = bl.depotTransf(c.entrance, c.n)
		rt.send(name .. ":build", api.cmd.makeWorldBuildProposalCmd(depotProposal(transf), nil, false, false),
			function(success : boolean, data : any, res : {{integer}})
				sentText[#sentText + 1] = string.format("%s origin=%.1f,%.1f,%.1f success=%s%s", bl.tryText(c), origin[1], origin[2], origin[3],
					tostring(success), success and "" or (" " .. bl.errText(data)))
				if not success then
					nextBatch()
					return
				end
				rt.later(name .. ":locate", SETTLE_MS, function()
					local depot, conE, located = locateDepot(before, res, origin)
					if depot ~= nil then
						table.insert(bl.depots, depot)
						bl.avoidPoints[#bl.avoidPoints + 1] = c.entrance   -- no stop next to our depot's gate
					end
					if depot == nil then
						onDone(false, head() .. " | built, but no new road depot found: " .. located, nil)
						return
					end
					connect(c, depot, conE, located)
				end)
			end)
	end

	nextBatch = function()
		if sends >= bl.DEPOT_MAX_SENDS then
			onDone(false, head() .. string.format(" | gave up after %d build commands", sends), nil)
			return
		end
		rt.later(name .. ":spots", 0, function()
			local checked = 0
			while idx < #tries and checked < PRECHECKS_PER_STEP do
				idx = idx + 1
				checked = checked + 1
				local c = tries[idx]
				local transf = bl.depotTransf(c.entrance, c.n)
				local verdict = precheck(depotProposal(transf))
				if verdict == "ok" or verdict == nil then
					local stub : string = "edgeGone"
					if api.engine.entityExists(c.edge.id) then stub = precheck(connectProposal(c.edge, c.t, nil, c.entrance)) end
					if stub ~= nil and stub ~= "ok" then verdict = "stub:" .. stub end
				end
				local key = verdict == nil and "unavailable" or verdict
				pre[key] = (pre[key] or 0) + 1
				if verdict == "ok" or verdict == nil then
					send(c)
					return
				end
			end
			if idx >= #tries then
				onDone(false, head() .. " | no spot left", nil)
				return
			end
			nextBatch()
		end)
	end
	nextBatch()
end

---------------------------------------------------------------------------
-- Line and buses

--- Newest bus model on sale this year, as the vehicle shop filters (see the header).
function bl.pickBusModel() : integer, string
	local okY, year = pcall(api.engine.util.getYear)
	local y = okY and year or 2000
	local E = api.type["enum"]
	local best : integer = nil
	local bestFrom = -math.huge
	local bestName = "none"
	local scanned, buses, errors = 0, 0, 0
	local okF, errF : boolean, any = pcall(api.res.modelRep.forEachModelWithMetadata, "transportVehicle", function(path : string)
		local okM = pcall(function()
			scanned = scanned + 1
			local id = api.res.modelRep.find(path) as integer
			local md = api.res.modelRep.get(id).metadata as {string : any}
			local tv = md.transportVehicle as {string : any}
			if not isValue(tv.carrier, E.Carrier.ROAD, "ROAD") then return end
			local bus = false
			for _, m in ipairs(tv.transportModes as {any} or {}) do
				if isValue(m, E.TransportMode.BUS, "BUS") then bus = true end
			end
			local tagged = false
			for _, t in ipairs(tv.filterTags as {string} or {}) do
				if t == "default" then tagged = true end
			end
			if not bus or not tagged then return end
			buses = buses + 1
			local av = md.availability as {string : number} or {}
			local from, to = av.yearFrom or -1, av.yearTo or -1
			if from > 0 and y < from then return end
			if to > 0 and y >= to then return end
			if from > bestFrom then best, bestFrom, bestName = id, from, path end
		end)
		if not okM then errors = errors + 1 end
	end)
	return best, string.format("year=%d models=%d roadBuses=%d errors=%d pick=%s(id=%s yearFrom=%s)%s", y, scanned, buses, errors,
		bestName, str(best), str(bestFrom), okF and "" or (" scan failed: " .. tostring(errF)))
end

local function gameTime() : integer
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return math.floor(gt.gameTime)
end

--- One-part config for a model (vehicle_util.makePart + vehicle_react_util purchase fields).
function bl.busConfig(modelId : integer) : TransportVehicleConfig
	local tv = (api.res.modelRep.get(modelId).metadata as {string : any}).transportVehicle as {string : any}
	local part = api.type.TransportVehiclePart.new()
	part.part.modelId = modelId
	part.part.reversed = false
	local lcs : {LoadConfig} = {}
	local auto : {boolean} = {}
	for _ in ipairs(tv.compartments as {any} or {}) do
		local lc = api.type.LoadConfig.new()
		lc.loadConfigIndex = 0
		lcs[#lcs + 1] = lc
		auto[#auto + 1] = true
	end
	part.part.compartment2loadConfig = lcs
	part.purchaseTime = gameTime()
	part.maintenanceState = 1
	part.autoLoadConfig = auto
	local cfg = api.type.TransportVehicleConfig.new()
	cfg.vehicles = { part }
	cfg.vehicleGroups = { 1 }
	cfg.muFileNames = {}
	return cfg
end

--- A config copied from one of the player's buses (first vehicle of a line whose first model is a road
--- bus), for when no model is on sale; nil when there is none.
function bl.cloneBusConfig() : TransportVehicleConfig, string
	local E = api.type["enum"]
	local okL, lines = pcall(api.engine.system.lineSystem.getLinesForPlayer, rt.player())
	if not okL or lines == nil then return nil, "no lines" end
	for _, line in ipairs(lines as {integer}) do
		local okV, vs = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, line)
		local v = okV and vs ~= nil and (vs as {integer})[1] or nil
		if v ~= nil then
			local okC, cfg, info = pcall(function() : TransportVehicleConfig, string
				local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
				local modelId = tv.transportVehicleConfig.vehicles[1].part.modelId
				local md = api.res.modelRep.get(modelId).metadata as {string : any}
				local mtv = md.transportVehicle as {string : any}
				if not isValue(mtv.carrier, E.Carrier.ROAD, "ROAD") then return nil, nil end
				local bus = false
				for _, m in ipairs(mtv.transportModes as {any} or {}) do
					if isValue(m, E.TransportMode.BUS, "BUS") then bus = true end
				end
				if not bus then return nil, nil end
				local c = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
				local parts : {TransportVehiclePart} = {}
				for _, part in ipairs(c.vehicles) do
					part.purchaseTime = gameTime()
					part.maintenanceState = 1
					local auto : {boolean} = {}
					for k = 1, #part.part.compartment2loadConfig do auto[k] = true end
					part.autoLoadConfig = auto
					parts[#parts + 1] = part
				end
				c.vehicles = parts
				return c, string.format("copy of vehicle %d (line %d)", v, line)
			end)
			if okC and cfg ~= nil then return cfg, info end
		end
	end
	return nil, "no bus of yours to copy"
end

--- Price of a config (sum of part prices), nil when unknown.
local function configPrice(cfg : TransportVehicleConfig) : number
	local prices : {number} = {}
	for i, part in ipairs(cfg.vehicles) do
		local ok, p = pcall(api.engine.util.vehicle.getPartPrice, part)
		if not ok or p == nil then return nil end
		prices[i] = p as number
	end
	return logic.configPrice(prices)
end

local function noCosts() : boolean
	local ok, v = pcall(function() : boolean return api.res.getBaseConfig().noCosts end)
	return ok and v == true
end

--- Whether money checks apply (no Keep balance, costs on).
local function moneyMatters() : boolean
	return not rt.keepBalance and not noCosts()
end

function bl.moneyWarning() : string
	if not moneyMatters() then return nil end
	return string.format("Keep balance (Game tab) is off: the build costs money, and its bus lines are not added if the balance is below %s by then.\nTick Keep balance now to be sure; the build goes on either way.",
		logic.formatMoney(bl.MIN_LINE_BALANCE))
end

local COLORS : {{number}} = { { 0.9, 0.45, 0.1 }, { 0.2, 0.6, 0.9 }, { 0.3, 0.75, 0.3 }, { 0.85, 0.25, 0.5 }, { 0.6, 0.4, 0.85 }, { 0.9, 0.8, 0.2 } }

--- makeLineCreateCmd over the station groups; onDone(line or nil, details).
function bl.createLine(name : string, groups : {integer}, onDone : function(line : integer, details : string))
	local line = api.type.Line.new()
	local stops : {Engine.Component.Line.Stop} = {}
	for _, sg in ipairs(groups) do
		local s = api.type.Line.Stop.new()
		s.stationGroup = sg
		s.station = 0
		s.terminal = 0
		stops[#stops + 1] = s
	end
	line.stops = stops
	local names : {string} = {}
	pcall(function()
		for _, l in ipairs(api.engine.system.lineSystem.getLinesForPlayer(rt.player()) as {integer}) do names[#names + 1] = entityName(l) end
	end)
	lineSeq = bl.nextLineNumber(names, lineSeq)
	local lineName = string.format("SQST Bus %d", lineSeq)
	local c = COLORS[(lineSeq % #COLORS) + 1]
	rt.send(name .. ":line", api.cmd.makeLineCreateCmd(lineName, api.type.Vec3f.new(c[1], c[2], c[3]), rt.player(), line),
		function(okL : boolean, _d : any, res : {{integer}})
			local lineE = okL and res ~= nil and res[1] ~= nil and res[1][1] or nil
			onDone(lineE, string.format("line=%s (%s) success=%s", str(lineE), lineName, tostring(okL)))
		end)
end

--- findBestDepotForLine for a bus line (a depot that reaches the line by road), nil if none.
function bl.bestDepotForLine(line : integer, x : number, y : number) : integer, string
	local E = api.type["enum"]
	local ok, d = pcall(api.engine.util.vehicle.findBestDepotForLine, E.Carrier.ROAD, { E.TransportMode.BUS }, line, api.type.Vec3f.new(x, y, 0))
	if not ok then return nil, "findBestDepotForLine error: " .. tostring(d) end
	if d == nil or d < 0 or not api.engine.entityExists(d) then return nil, "findBestDepotForLine=" .. str(d) end
	return d, "findBestDepotForLine=" .. str(d)
end

--- Our nearest connected depot (built this session) within r of (x, y); with net, only one of that
--- road network (bl.depotNet).
local function ourDepotNear(x : number, y : number, r : number, net? : string) : integer, number
	local best : integer = nil
	local bestD = r
	for _, d in ipairs(bl.depots) do
		if api.engine.entityExists(d) and (net == nil or bl.depotNet[d] == net) then
			local p = bl.depotPos(d)
			local dist = p ~= nil and dist2(p, { x, y }) or nil
			if dist ~= nil and dist <= bestD then best, bestD = d, dist end
		end
	end
	return best, best ~= nil and bestD or nil
end

--- Buys n buses at depot one after another, each put on line; onDone(bought, failure or nil).
function bl.buyBuses(name : string, depot : integer, makeCfg : function() : TransportVehicleConfig, n : integer, line : integer,
		onDone : function(bought : integer, failure : string))
	local bought = 0
	local clears = rt.queueClears
	local function nextBus()
		if bought >= n then
			onDone(bought, nil)
			return
		end
		if rt.queueClears ~= clears then
			onDone(bought, "queue cleared")
			return
		end
		local cfg = makeCfg()
		if moneyMatters() then
			local price, balance = configPrice(cfg), rt.balance()
			if not logic.canAfford(balance, price) then
				onDone(bought, string.format("balance %s can't pay the next bus (%s)", logic.formatMoney(balance), logic.formatMoney(price)))
				return
			end
		end
		rt.send(name .. ":buy", api.cmd.makeVehicleBuyCmd(rt.player(), depot, cfg), function(okB : boolean, dataB : any)
			local v = okB and (dataB as VehicleBuyCommandData).resultVehicleEntity or nil
			if v == nil or v < 0 then
				onDone(bought, string.format("buy %d/%d failed at depot %d", bought + 1, n, depot))
				return
			end
			bl.vehicles[#bl.vehicles + 1] = v
			rt.detail(string.format("[SQST] %s bought bus=%d depot=%d for line=%d (%d/%d)", name, v, depot, line, bought + 1, n))
			-- SetLine only on the bus this very callback returned, while it still is a vehicle of ours
			if not rt.isVehicle(v) or not rt.ownedByPlayer(v) then
				onDone(bought, string.format("bought bus=%d is not a vehicle of yours now; setLine skipped", v))
				return
			end
			-- a bus that can't go on the line is sold again at once (2026-10-12: two buses stayed in a depot
			-- of another road network)
			local function sellBack(why : string)
				if not rt.isVehicle(v) then onDone(bought, why .. "; it is no vehicle now, not sold") return end
				rt.send(name .. ":sell", api.cmd.makeVehicleSellCmd({ v }), function(okX : boolean, _dx : any)
					if okX then forget(bl.vehicles, v) end
					onDone(bought, string.format("%s; sold again=%s", why, tostring(okX)))
				end)
			end
			if not rt.isLine(line) then
				sellBack(string.format("line=%d is gone; setLine skipped (bus %d)", line, v))
				return
			end
			rt.send(name .. ":setLine", api.cmd.makeVehicleSetLineCmd(v, line, 0), function(okS : boolean, _d : any)
				if not okS then
					sellBack(string.format("setLine failed vehicle=%d line=%d", v, line))
					return
				end
				bought = bought + 1
				nextBus()
			end)
		end)
	end
	nextBus()
end

---------------------------------------------------------------------------
-- Auto bus lines (Traffic tab)

--- Sim persons moving on a street edge right now (simPersonSystem.getSimPersonsMovingForTransportNetwork,
--- api/tealdef/api/engine/system.d.tl:155-157; whether a street edge counts as a transport network
--- entity is untested in game), 0 when unavailable. Stop edges with traffic on them come last: a stop
--- replaces its edge, and the vehicles on it get re-routed.
local function movingOn(e : integer) : integer
	local ok, n = pcall(function() : integer
		return #(api.engine.system.simPersonSystem.getSimPersonsMovingForTransportNetwork(e) as {integer})
	end)
	if not ok or n == nil then return 0 end
	return n
end

local function quietOnes(edges : {SquareStressEdgeGeo}) : {SquareStressEdgeGeo}
	local out : {SquareStressEdgeGeo} = {}
	for _, g in ipairs(edges) do
		if movingOn(g.id) == 0 then out[#out + 1] = g end
	end
	return out
end

--- Where a route line may build (logic.busEdgeReject): route = true for route lines (Showcase,
--- Junction / Crossing test: own town streets only, its grid when town.half is set, out of the zones);
--- Auto bus lines only keep off highways and one-way streets.
local record EdgeRule
	route : boolean
	zones : {{number}}
end

--- The edges of cands that pass rule for town (all of them with no rule), and the rejected counts per
--- reason added to why.
local function ruleEdges(cands : {SquareStressEdgeGeo}, town : SquareStressTownPos, rule : EdgeRule,
		why : {string : integer}) : {SquareStressEdgeGeo}
	local out : {SquareStressEdgeGeo} = {}
	local isRoute = rule ~= nil and rule.route
	for _, g in ipairs(cands) do
		local r = logic.busEdgeReject(g.template, g.p0, g.p1, isRoute and town or nil, rule ~= nil and rule.zones or nil, isRoute)
		if r == nil then out[#out + 1] = g else why[r] = (why[r] or 0) + 1 end
	end
	return out
end

local function rejectedText(why : {string : integer}) : string
	if next(why) == nil then return "" end
	return string.format(" rejected={%s}", countsText(why))
end

--- The town's eligible street edges within TOWN_EDGE_RADIUS of its centre (the TOWN_EDGE_MAX nearest),
--- nearest the centre first, that belong to this town (closest town) and pass rule, and the built-up ones
--- among them (a town building within BUILT_RADIUS; octree TOWN_BUILDING). Third result: summary.
local function townEdges(town : SquareStressTownPos, rule : EdgeRule) : {SquareStressEdgeGeo}, {SquareStressEdgeGeo}, string
	local all, info = bl.streetEdgeCandidates(town.x, town.y, bl.TOWN_EDGE_RADIUS)
	local why : {string : integer} = {}
	local cands = ruleEdges(all, town, rule, why)
	info = info .. rejectedText(why)
	local mine : {SquareStressEdgeGeo} = {}
	local built : {SquareStressEdgeGeo} = {}
	local other, octreeOk = 0, true
	for i, g in ipairs(cands) do
		if i > bl.TOWN_EDGE_MAX then break end
		local okT, t = pcall(api.engine.util.town.getClosestTown, api.type.Vec3f.new(g.mid[1], g.mid[2], 0))
		if not okT or t == nil or t < 0 or t == town.id then
			mine[#mine + 1] = g
			local okB, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(g.mid[1], g.mid[2]), bl.BUILT_RADIUS,
				api.type.ComponentType.TOWN_BUILDING)
			if not okB then octreeOk = false end
			if okB and list ~= nil and #(list as {integer}) > 0 then built[#built + 1] = g end
		else
			other = other + 1
		end
	end
	return mine, built, string.format("%s town=%d otherTown=%d builtUp=%d%s", info, #mine, other, #built, octreeOk and "" or " (building query failed)")
end

--- Depot ranking of an edge (lower first): town buildings within DEPOT_CLEAR_RADIUS of its middle, +1000
--- when it belongs to another town, +500 near one of our stops or depot entrances.
local function depotScore(g : SquareStressEdgeGeo, townId : integer) : number
	local score = 0.0
	local okB, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(g.mid[1], g.mid[2]), bl.DEPOT_CLEAR_RADIUS,
		api.type.ComponentType.TOWN_BUILDING)
	if okB and list ~= nil then score = score + #(list as {integer}) end
	local okT, t = pcall(api.engine.util.town.getClosestTown, api.type.Vec3f.new(g.mid[1], g.mid[2], 0))
	if okT and t ~= nil and t >= 0 and t ~= townId then score = score + 1000 end
	for _, p in ipairs(bl.avoidPoints) do
		if dist2(g.mid, p) < bl.STOP_AVOID then
			score = score + 500
			break
		end
	end
	return score
end

local function lineVehicles(line : integer) : {integer}
	local ok, vs = pcall(function() : {integer}
		return api.engine.system.transportVehicleSystem.getLineVehicles(line) as {integer}
	end)
	if not ok or vs == nil then return {} end
	return vs
end

local record TownRun
	town : SquareStressTownPos
	name : string
	failed : boolean
	done : integer                -- lines finished
	depot : integer               -- the town's depot, found or built before its first stop
	depotHow : string
	depotFar : boolean            -- last resort (nearest anywhere): used only if findBestDepotForLine confirms a depot
	wasted : integer              -- stops built for lines that were given up
	other : SquareStressTownPos   -- addRouteLines: the line's second town (stop 2 there); nil: both stops in town
	net : string                  -- addRouteLines: the towns' road network (depots reused only within it); nil: any
	twin : SquareStressLineTwin   -- addRouteLines: the Showcase twin the route serves (bl.lineTwins); nil: none
	rule : EdgeRule               -- where its stops and depots may go (ruleEdges)
end

--- Whether a street edge belongs to the town (its closest town; true when that can't be read).
local function inTown(g : SquareStressEdgeGeo, townId : integer) : boolean
	local okT, t = pcall(api.engine.util.town.getClosestTown, api.type.Vec3f.new(g.mid[1], g.mid[2], 0))
	return not okT or t == nil or t < 0 or t == townId
end

--- The edges of a list that belong to the town.
local function townOnly(cands : {SquareStressEdgeGeo}, townId : integer) : {SquareStressEdgeGeo}
	local out : {SquareStressEdgeGeo} = {}
	for _, g in ipairs(cands) do
		if inTown(g, townId) then out[#out + 1] = g end
	end
	return out
end

function bl.selectedLines() : integer
	return logic.BUS_LINES_PER_TOWN[bl.ui.lines] or 1
end

function bl.selectedBuses() : integer
	return logic.BUSES_PER_LINE[bl.ui.buses] or 2
end

function bl.label() : string
	return logic.busLinesLabel(bl.ui.towns, bl.selectedLines())
end

function bl.uiSignature() : string
	return string.format("%d/%d/%d/%d/%d", bl.ui.towns, bl.ui.lines, bl.ui.buses, #bl.lines, #bl.vehicles)
end

function bl.removeLabel() : string
	return string.format("Remove added bus lines (%d)", #bl.lines)
end

--- The town's depot, found or built BEFORE anything else (2026-10-10: stops and a line built first were
--- left behind empty when the depot then failed). In order: a depot built by us within BUS_DEPOT_REUSE,
--- any road depot of the player within BUS_DEPOT_REUSE, a new one (DEPOT_RINGS outward from the centre,
--- RING_EDGES fewest-buildings edges per ring), else the nearest road depot anywhere (far = true).
--- onDone(depot or nil, how, far).
--- A route line (run.net set: Showcase) reuses only our depots of its own road network, builds on its
--- own town's streets only, and has no last resort far away (each would be on another network).
local function findDepot(name : string, run : TownRun, onDone : function(depot : integer, how : string, far : boolean))
	local town = run.town
	local clears = rt.queueClears
	local ours, dOurs = ourDepotNear(town.x, town.y, bl.BUS_DEPOT_REUSE, run.net)
	if ours ~= nil then onDone(ours, string.format("ours, %.0fm%s", dOurs, run.net ~= nil and (", " .. run.net) or ""), false) return end
	if run.net == nil then
		local near, dNear = bl.nearestRoadDepot(town.x, town.y, bl.BUS_DEPOT_REUSE)
		if near ~= nil then onDone(near, string.format("existing, %.0fm", dNear), false) return end
	end
	local notes : {string} = {}
	local ri = 0
	local function rings() : string return table.concat(notes, "; ") end
	local tryRing : function()
	tryRing = function()
		ri = ri + 1
		local ring = bl.DEPOT_RINGS[ri]
		if ring == nil then
			rt.detail(string.format("[SQST] %s %s depot rings: %s", name, run.name, rings()))
			if run.net ~= nil then
				onDone(nil, string.format("no depot on the %s network; rings: %s", run.net, rings()), false)
				return
			end
			local far, dFar = bl.nearestRoadDepot(town.x, town.y, math.huge)
			if far ~= nil then
				onDone(far, string.format("nearest anywhere, %.0fm; rings: %s", dFar, rings()), true)
			else
				onDone(nil, "no road depot anywhere; rings: " .. rings(), false)
			end
			return
		end
		local label = string.format("%.0f-%.0fm", ring[1], ring[2])
		local cands = bl.streetEdgeCandidates(town.x, town.y, ring[2])
		if run.net ~= nil then cands = townOnly(cands, town.id) end
		local why : {string : integer} = {}
		cands = ruleEdges(cands, town, run.rule, why)
		local rej = rejectedText(why)
		local edges, inRing = bl.ringPick(cands, ring[1], ring[2], bl.RING_SAMPLE, bl.RING_EDGES,
			function(g : SquareStressEdgeGeo) : number return depotScore(g, town.id) end)
		if #edges == 0 then
			notes[#notes + 1] = label .. " edges=0" .. rej
			tryRing()
			return
		end
		bl.buildDepot(name .. ":depot", edges, town.x, town.y, function(okD : boolean, dd : string, depot : integer)
			notes[#notes + 1] = string.format("%s inRing=%d%s %s", label, inRing, rej, bl.depotShort(dd))
			rt.detail(string.format("[SQST] %s %s depot %s: %s", name, run.name, label, dd))
			if okD then
				rt.detail(string.format("[SQST] %s %s depot rings: %s", name, run.name, rings()))
				if run.net ~= nil then bl.depotNet[depot] = run.net end
				onDone(depot, "built in ring " .. label, false)
				return
			end
			if rt.queueClears ~= clears then onDone(nil, "queue cleared", false) return end
			tryRing()
		end)
	end
	tryRing()
end

--- A new depot near a line's first stop g, on the streets of the run's town (STOP_DEPOT_RINGS around
--- the stop): for a line no depot reaches yet. onDone(depot or nil, how).
local function stopDepot(name : string, run : TownRun, g : SquareStressEdgeGeo, onDone : function(depot : integer, how : string))
	local notes : {string} = {}
	local ri = 0
	local clears = rt.queueClears
	local tryRing : function()
	tryRing = function()
		if rt.queueClears ~= clears then onDone(nil, "queue cleared") return end
		ri = ri + 1
		local ring = bl.STOP_DEPOT_RINGS[ri]
		if ring == nil then
			onDone(nil, table.concat(notes, "; "))
			return
		end
		local label = string.format("%.0f-%.0fm of stop 1", ring[1], ring[2])
		local why : {string : integer} = {}
		local cands = ruleEdges(townOnly(bl.streetEdgeCandidates(g.mid[1], g.mid[2], ring[2]), run.town.id), run.town, run.rule, why)
		local rej = rejectedText(why)
		local edges, inRing = bl.ringPick(cands, ring[1], ring[2], bl.RING_SAMPLE, bl.RING_EDGES,
			function(e : SquareStressEdgeGeo) : number return depotScore(e, run.town.id) end)
		if #edges == 0 then
			notes[#notes + 1] = label .. " edges=0" .. rej
			tryRing()
			return
		end
		bl.buildDepot(name .. ":depot", edges, g.mid[1], g.mid[2], function(okD : boolean, dd : string, depot : integer)
			notes[#notes + 1] = string.format("%s inRing=%d%s %s", label, inRing, rej, bl.depotShort(dd))
			rt.detail(string.format("[SQST] %s %s depot %s: %s", name, run.name, label, dd))
			if okD then
				if run.net ~= nil then bl.depotNet[depot] = run.net end
				onDone(depot, "built " .. label)
				return
			end
			tryRing()
		end)
	end
	tryRing()
end

--- Two free stop edges for a line: built-up edges without traffic first, then built-up, then any town
--- edge without traffic, then any; never within STOP_AVOID of our stops or depot entrances.
--- One free stop edge in a town (same pool order as pickStops), for a line between two towns.
local function pickOne(town : SquareStressTownPos, rule : EdgeRule) : SquareStressEdgeGeo, string, string
	local mine, built, info = townEdges(town, rule)
	local names : {string} = { "builtUp,quiet", "builtUp", "all,quiet", "all" }
	for i, poolName in ipairs(names) do
		local pool : {SquareStressEdgeGeo}
		if i == 1 then pool = quietOnes(built) elseif i == 2 then pool = built elseif i == 3 then pool = quietOnes(mine) else pool = mine end
		for _, g in ipairs(pool) do
			local free = true
			for _, p in ipairs(bl.avoidPoints) do
				if dist2(g.mid, p) < bl.STOP_AVOID then free = false break end
			end
			if free then return g, poolName, info end
		end
	end
	return nil, nil, info
end

local function pickStops(town : SquareStressTownPos, other : SquareStressTownPos, rule : EdgeRule) : SquareStressEdgeGeo, SquareStressEdgeGeo, string, string
	if other ~= nil then
		local a, poolA, infoA = pickOne(town, rule)
		local b, poolB, infoB = pickOne(other, rule)
		local info = infoA .. " | " .. infoB
		if a == nil or b == nil then return nil, nil, nil, info end
		return a, b, poolA .. "/" .. poolB, info
	end
	local mine, built, info = townEdges(town, rule)
	local names : {string} = { "builtUp,quiet", "builtUp", "all,quiet", "all" }
	for i, poolName in ipairs(names) do
		local pool : {SquareStressEdgeGeo}
		if i == 1 then pool = quietOnes(built) elseif i == 2 then pool = built elseif i == 3 then pool = quietOnes(mine) else pool = mine end
		local a, b = bl.pickEdgePair(pool, bl.PAIR_MIN, bl.PAIR_MAX, bl.avoidPoints, bl.STOP_AVOID, bl.PAIR_TRIES)
		if a ~= nil then return a, b, poolName, info end
	end
	return nil, nil, nil, info
end

--- One line in a town: the town's depot first (nothing is built if there is none), then 2 stops 300-800 m
--- apart, the line, N buses. A line that ends up with no bus is destroyed again (its stops are counted as
--- wasted). onDone(ok, details).
local function runLine(name : string, run : TownRun, k : integer, buses : integer,
		makeCfg : function() : TransportVehicleConfig, onDone : function(ok : boolean, details : string))
	local town = run.town
	local clears = rt.queueClears
	local head = string.format("line %d:", k)
	local function stopped(wasted : integer) : boolean   -- Clear queue pressed: no further commands for this line
		if rt.queueClears == clears then return false end
		run.wasted = run.wasted + wasted
		onDone(false, "queue cleared")
		return true
	end
	local a, b, pool, info = pickStops(town, run.other, run.rule)
	if a == nil then
		if run.other ~= nil then
			onDone(false, string.format("%s no free street edge in one of the towns (%s); nothing built", head, info))
			return
		end
		onDone(false, string.format("%s no two free street edges %.0f-%.0f m apart (%s); nothing built", head, bl.PAIR_MIN, bl.PAIR_MAX, info))
		return
	end

	local function abandon(line : integer, why : string)
		run.wasted = run.wasted + 2
		local vs = lineVehicles(line)
		if not rt.isLine(line) or #vs > 0 then
			onDone(false, string.format("%s | %s | line %d kept (%s), 2 stops wasted", head, why, line,
				rt.isLine(line) and (tostring(#vs) .. " vehicles on it") or "no longer a line"))
			return
		end
		rt.send(name .. ":destroyLine", api.cmd.makeLineDestroyCmd(line), function(okX : boolean, _d : any)
			if okX then forget(bl.lines, line) end
			onDone(false, string.format("%s | %s | line %d destroyed=%s, 2 stops wasted", head, why, line, tostring(okX)))
		end)
	end

	local function withStops()
		head = string.format("line %d: edges %d,%d (%s) %.0fm apart depot=%d (%s)", k, a.id, b.id, pool, dist2(a.mid, b.mid), run.depot, run.depotHow)
		bl.placeStop(name .. ":stop1", a, function(ok1 : boolean, d1 : string, g1 : integer)
			if not ok1 then onDone(false, head .. " | stop1 failed: " .. d1) return end
			if stopped(1) then return end
			if not api.engine.entityExists(b.id) then
				run.wasted = run.wasted + 1
				onDone(false, string.format("%s | stop2 edge %d is gone | 1 stop wasted", head, b.id))
				return
			end
			bl.placeStop(name .. ":stop2", b, function(ok2 : boolean, d2 : string, g2 : integer)
				if not ok2 or g2 == g1 then
					run.wasted = run.wasted + 1
					onDone(false, head .. " | stop2 failed: " .. d2 .. " | 1 stop wasted")
					return
				end
				if stopped(2) then return end
				head = head .. string.format(" groups=%d,%d", g1, g2)
				bl.createLine(name, { g1, g2 }, function(line : integer, dl : string)
					if line == nil then
						run.wasted = run.wasted + 2
						onDone(false, head .. " | " .. dl .. " | 2 stops wasted")
						return
					end
					bl.lines[#bl.lines + 1] = line
					if run.twin ~= nil then bl.lineTwins[line] = run.twin end
					rt.detail(string.format("[SQST] %s %s created %s stationGroups=%d,%d", name, run.name, dl, g1, g2))
					head = head .. " " .. dl
					if stopped(0) then return end
					local function buy(depot : integer, info : string)
						if run.net ~= nil and bl.depotNet[depot] == nil then bl.depotNet[depot] = run.net end
						head = head .. string.format(" buses from depot=%d (%s)", depot, info)
						bl.buyBuses(name, depot, makeCfg, buses, line, function(bought : integer, failure : string)
							if failure == nil then
								onDone(true, string.format("%s buses=%d/%d", head, bought, buses))
							elseif bought == 0 and failure ~= "queue cleared" then
								abandon(line, string.format("buses=0/%d | %s", buses, failure))
							else
								onDone(false, string.format("%s buses=%d/%d | %s", head, bought, buses, failure))
							end
						end)
					end
					-- Buses only from a depot findBestDepotForLine confirms reaches the line (2026-10-12: bought at
					-- a depot of another road network, setLine failed and the bus stayed there). None: the town's
					-- depot is on another network or not connected; a new depot near stop 1, asked again; still
					-- none: the line is given up before any bus is bought.
					local best, bestInfo = bl.bestDepotForLine(line, a.mid[1], a.mid[2])
					if best ~= nil then buy(best, bestInfo) return end
					-- a line that vanished meanwhile gets no depot built for it
					if not rt.isLine(line) then
						abandon(line, string.format("line %d is gone (%s)", line, bestInfo))
						return
					end
					stopDepot(name, run, a, function(depot : integer, how : string)
						if stopped(0) then return end
						if depot == nil then
							abandon(line, string.format("no depot reaches the line (%s; depot %d: %s, %s) and none could be built near stop 1 (%s)",
								bestInfo, run.depot, run.depotHow, bl.gateText(run.depot), how))
							return
						end
						local best2, info2 = bl.bestDepotForLine(line, a.mid[1], a.mid[2])
						if best2 == nil then
							abandon(line, string.format("no depot reaches the line (%s; depot %d: %s, %s), not even depot %d %s (%s, %s)", bestInfo,
								run.depot, run.depotHow, bl.gateText(run.depot), depot, how, bl.gateText(depot), info2))
							return
						end
						run.depot, run.depotHow, run.depotFar = depot, how, false
						buy(best2, string.format("%s after depot %d %s", info2, depot, how))
					end)
				end)
			end)
		end)
	end

	local function afterDepot()
		if stopped(0) then return end
		if not api.engine.entityExists(a.id) or not api.engine.entityExists(b.id) then
			a, b, pool, info = pickStops(town, run.other, run.rule)   -- the depot's street connection replaced one of them
			if a == nil then
				onDone(false, string.format("%s depot=%d (%s), then no two free street edges (%s); no stop built", head, run.depot, run.depotHow, info))
				return
			end
		end
		withStops()
	end

	if run.depot ~= nil and api.engine.entityExists(run.depot) then afterDepot() return end
	findDepot(name, run, function(depot : integer, how : string, far : boolean)
		if depot == nil then
			onDone(false, string.format("%s depot failed, nothing built (%s)", head, how))
			return
		end
		run.depot, run.depotHow, run.depotFar = depot, how, far
		afterDepot()
	end)
end

local BUS_JOBS : {string} = { "bus_lines", "remove_bus_lines" }

--- Logs and returns true when a bus-lines batch or removal is still queued or running (no stacking).
local function refuseBusy(name : string) : boolean
	local busy = rt.busyJob(BUS_JOBS)
	if busy == nil then return false end
	rt.warn("Busy", string.format("%s: %s is still queued or running; wait for it to finish.", name, busy))
	return true
end

local runBatch : function(name : string, label : string, runs : {TownRun}, nLines : integer, nBuses : integer, rerun : string,
	routes? : boolean)

function bl.addBusLines()
	local name = "bus_lines"
	if refuseBusy(name) then return end
	local nLines, nBuses = bl.selectedLines(), bl.selectedBuses()
	local okC, cx, cy = pcall(rt.camera)
	if not okC or cx == nil then
		rt.log("[SQST] bus_lines: camera read failed: " .. tostring(cx))
		return
	end
	local picked = logic.busTownPick(towns.townPositions(), cx, cy, bl.ui.towns)
	if #picked == 0 then
		rt.warn("Bus lines", "No town found on the map.")
		return
	end
	local runs : {TownRun} = {}
	for i, t in ipairs(picked) do
		runs[i] = { town = t, name = entityName(t.id), failed = false, done = 0, wasted = 0, rule = { route = false } }
	end
	rt.log(string.format("[SQST] %s: %d towns x %d lines x %d buses (%d lines)", name, #runs, nLines, nBuses, #runs * nLines))
	runBatch(name, "Bus lines", runs, nLines, nBuses, "then press the button again.")
end

--- The serial batch behind addBusLines and addRouteLines: nLines lines per run, one step at a time.
--- A batch that stops early (no money, no bus, failed towns) says so in a dialog (label: its title;
--- rerun: how to try again, after the fix). Auto bus lines stop after MAX_TOWN_FAILS failed towns in a
--- row (the town ring around the camera: no money or no room repeats); route lines (routes, each its own
--- pair of towns: 2026-10-12 the Showcase stopped after its first 3 of 40 routes) go on past a failed
--- route and stop only after MAX_ROUTE_FAILS failed routes in all.
runBatch = function(name : string, label : string, runs : {TownRun}, nLines : integer, nBuses : integer, rerun : string,
		routes? : boolean)
	local plan : {{integer}} = {}   -- {run index, line k}
	for i = 1, #runs do
		for k = 1, nLines do plan[#plan + 1] = { i, k } end
	end
	local stats = { lines = 0, townsOk = 0, townsFailed = 0 }
	local failsInRow = 0
	local stopReason : string = nil
	local stopWhy : string = nil   -- the dialog's text for stopReason (nil: stopReason)
	local stopFix = "Check the log ([SQST] " .. name .. "), "   -- and its advice
	local token = 0
	local modelId : integer = nil
	local modelInfo : string = nil
	local cloneCfg : TransportVehicleConfig = nil
	local balance0 = rt.balance()
	local linesBefore, vehiclesBefore = #bl.lines, #bl.vehicles

	local function makeCfg() : TransportVehicleConfig
		if modelId ~= nil then return bl.busConfig(modelId) end
		return api.type.TransportVehicleConfig.new(cloneCfg)
	end

	local function townDone(run : TownRun, job : SquareStressJob, ok : boolean, why : string)
		if ok then
			stats.townsOk = stats.townsOk + 1
			failsInRow = 0
			rt.log(string.format("[SQST] %s town %s (%d): %d lines ok", name, run.name, run.town.id, run.done))
		elseif routes then
			stats.townsFailed = stats.townsFailed + 1
			rt.log(string.format("[SQST] %s town %s (%d) failed after %d lines: %s (%d/%d failed routes, going on)", name, run.name,
				run.town.id, run.done, why, stats.townsFailed, bl.MAX_ROUTE_FAILS))
			if stats.townsFailed >= bl.MAX_ROUTE_FAILS then
				stopReason = string.format("%d failed routes", stats.townsFailed)
				rt.log(string.format("[SQST] %s stopped after %d failed routes", name, stats.townsFailed))
				logic.stop(job)
			end
		else
			stats.townsFailed = stats.townsFailed + 1
			failsInRow = failsInRow + 1
			rt.log(string.format("[SQST] %s town %s (%d) failed after %d lines: %s (%d/%d failed towns in a row)", name, run.name,
				run.town.id, run.done, why, failsInRow, bl.MAX_TOWN_FAILS))
			if failsInRow >= bl.MAX_TOWN_FAILS then
				stopReason = string.format("%d failed towns in a row", failsInRow)
				rt.log(string.format("[SQST] %s stopped after %d failed towns in a row", name, failsInRow))
				logic.stop(job)
			end
		end
	end

	local function step(i : integer, job : SquareStressJob)
		local p = plan[i]
		local run, k = runs[p[1]], p[2]
		if run.failed then logic.resume(job) return end
		if modelId == nil and cloneCfg == nil then
			modelId, modelInfo = bl.pickBusModel()
			if modelId == nil then
				local info : string
				cloneCfg, info = bl.cloneBusConfig()
				modelInfo = modelInfo .. "; " .. info
			end
			rt.detail(string.format("[SQST] %s bus: %s", name, modelInfo))
			if modelId == nil and cloneCfg == nil then
				stopReason = "no bus model on sale and no bus to copy (" .. modelInfo .. ")"
				rt.log(string.format("[SQST] %s stopped: %s", name, stopReason))
				logic.stop(job)
				return
			end
		end
		if moneyMatters() then
			local balance = rt.balance()
			if balance ~= nil and balance < bl.MIN_LINE_BALANCE then
				stopReason = string.format("balance %s below %s; tick Keep balance or add money", logic.formatMoney(balance),
					logic.formatMoney(bl.MIN_LINE_BALANCE))
				stopWhy = string.format("the balance %s is below %s", logic.formatMoney(balance), logic.formatMoney(bl.MIN_LINE_BALANCE))
				stopFix = "Tick Keep balance (Game tab) or add money, "
				rt.log(string.format("[SQST] %s stopped: %s", name, stopReason))
				logic.stop(job)
				return
			end
		end
		token = token + 1
		local mine = token
		local t0 = rt.nowUs()
		runLine(name, run, k, nBuses, makeCfg, function(ok : boolean, details : string)
			if mine ~= token then
				rt.detail(string.format("[SQST] %s %s late answer ignored: %s", name, run.name, details))
				return
			end
			rt.detail(string.format("[SQST] %s %d/%d %s %s ms=%.0f %s", name, i, #plan, run.name, ok and "ok" or "fail",
				(rt.nowUs() - t0) / 1000, details))
			if ok then
				run.done = run.done + 1
				stats.lines = stats.lines + 1
				if run.done >= nLines then townDone(run, job, true, nil) end
			else
				run.failed = true
				townDone(run, job, false, details)
			end
			logic.resume(job)
		end)
	end

	rt.enqueue(name, #plan, function(i : integer, job : SquareStressJob)
		local ok, err : boolean, any = pcall(step, i, job)
		if not ok then
			local p = plan[i]
			local run = runs[p[1]]
			if not run.failed then
				run.failed = true
				townDone(run, job, false, "error: " .. tostring(err))
			end
			logic.resume(job)
		end
	end, { serial = true, label = label, timeoutMs = bl.LINE_TIMEOUT_MS })

	rt.enqueue(name .. ":summary", 1, function(_i : integer, job : SquareStressJob)
		logic.resume(job)
		token = token + 1   -- answers of a timed-out line no longer count
		local wasted = 0
		for _, run in ipairs(runs) do wasted = wasted + run.wasted end
		rt.log(string.format("[SQST] %s summary towns=%d ok=%d failed=%d lines=%d (complete %d) buses=%d wastedStops=%d (session: %d lines, %d buses) balance %s->%s%s",
			name, #runs, stats.townsOk, stats.townsFailed, #bl.lines - linesBefore, stats.lines, #bl.vehicles - vehiclesBefore, wasted, #bl.lines,
			#bl.vehicles, logic.formatMoney(balance0), logic.formatMoney(rt.balance()), stopReason ~= nil and (" stopped: " .. stopReason) or ""))
		if stopReason ~= nil then
			local added = #bl.lines - linesBefore
			rt.warn(label, string.format("%s %s.\n%s%s", added == 0 and "Bus lines not added:" or string.format("Bus lines stopped after %d of %d lines:",
				added, #plan), stopWhy or stopReason, stopFix, rerun))
		end
	end, { serial = true, quiet = true })
end

function bl.addRouteLines(name : string, title : string, routes : {SquareStressBusRoute}) : integer
	if refuseBusy(name) then return 0 end
	local runs : {TownRun} = {}
	for _, r in ipairs(routes or {}) do
		if r.a ~= nil and r.b ~= nil and r.a.id ~= nil and r.b.id ~= nil and r.a.id ~= r.b.id then
			runs[#runs + 1] = { town = r.a, other = r.b, name = r.label or string.format("%d -> %d", r.a.id, r.b.id),
				failed = false, done = 0, wasted = 0, net = r.net, rule = { route = true, zones = r.zones },
				twin = r.twin ~= nil and { twin = r.twin, pair = r.pair, ab = r.ab } or nil }
		end
	end
	if #runs == 0 then return 0 end
	local nBuses = bl.selectedBuses()
	rt.log(string.format("[SQST] %s: %d bus lines between %s towns x %d buses", name, #runs, title, nBuses))
	runBatch(name, title .. " bus lines", runs, 1, nBuses, string.format("then build the %s again: its bus lines cannot be added on their own later (Auto bus lines on the Traffic tab adds lines in the towns around the camera).",
		title), true)
	return #runs
end

--- Showcase (SHOWCASE.md "Depots before growth"): every route's depot found or built BEFORE the towns grow
--- (seed 718344: all 10 routes failed after the x10 growth, every depot spot collided with buildings in the
--- built-up grids). One serial job, one step per route town (its first town, as its line's own findDepot:
--- our depots of its road network, else DEPOT_RINGS on its own town's streets, out of the junction zones);
--- each depot is marked with the route's network (bl.depotNet), so the line built after the growth finds it
--- (findDepot -> ourDepotNear) instead of building one in the grown town. Logs one line per town, then
--- "[SQST] <name> summary towns=N depots=D failed=F ms=M" and calls onDone(ms).
function bl.prebuildDepots(name : string, routes : {SquareStressBusRoute}, onDone? : function(ms : number))
	local runs : {TownRun} = {}
	local seen : {string : boolean} = {}
	for _, r in ipairs(routes or {}) do
		if r.a ~= nil and r.a.id ~= nil then
			local key = string.format("%d|%s", r.a.id, tostring(r.net))
			if not seen[key] then
				seen[key] = true
				runs[#runs + 1] = { town = r.a, other = r.b, name = r.label or tostring(r.a.id), failed = false, done = 0, wasted = 0,
					net = r.net, rule = { route = true, zones = r.zones } }
			end
		end
	end
	if #runs == 0 then
		if onDone ~= nil then pcall(onDone, 0) end
		return
	end
	local t0 = rt.nowUs()
	local built, failed = 0, 0
	rt.log(string.format("[SQST] %s: %d route towns, each its depot before the growth", name, #runs))
	rt.enqueue(name, #runs, function(i : integer, job : SquareStressJob)
		local run = runs[i]
		local function done(depot : integer, how : string)
			if depot ~= nil then
				built = built + 1
				if run.net ~= nil and bl.depotNet[depot] == nil then bl.depotNet[depot] = run.net end
				rt.log(string.format("[SQST] %s %s depot=%d (%s)", name, run.name, depot, how))
			else
				failed = failed + 1
				rt.log(string.format("[SQST] %s %s: no depot (%s); its line tries again after the growth", name, run.name, how))
			end
			logic.resume(job)
			if i == #runs then
				local ms = (rt.nowUs() - t0) / 1000
				rt.log(string.format("[SQST] %s summary towns=%d depots=%d failed=%d ms=%.0f", name, #runs, built, failed, ms))
				if onDone ~= nil then pcall(onDone, ms) end
			end
		end
		local ok, err : boolean, any = pcall(findDepot, name, run, function(depot : integer, how : string, _far : boolean) done(depot, how) end)
		if not ok then done(nil, "error: " .. tostring(err)) end
	end, { serial = true, label = "Building the bus depots", timeoutMs = logic.BATCH_TIMEOUT_MS })
end

--- Sells the buses bought by Auto bus lines, waits until they are really gone, then deletes their lines
--- (stops and depots stay). Every id is re-checked before its command: a sold bus or deleted line is
--- never acted on again, and a line that still lists vehicles is kept (2026-10-10 crash, docs/findings.md
--- "Sixth run").
function bl.removeAdded()
	local name = "remove_bus_lines"
	local vs : {integer} = {}
	for i, v in ipairs(bl.vehicles) do vs[i] = v end
	local ls : {integer} = {}
	for i, l in ipairs(bl.lines) do ls[i] = l end
	if #vs == 0 and #ls == 0 then
		rt.log("[SQST] " .. name .. ": no bus lines added in this session")
		return
	end
	if refuseBusy(name) then return end
	local sold, deleted, gone, failed, kept = 0, 0, 0, 0, 0
	local soldList : {integer} = {}
	local waitNote = "none"

	rt.enqueue(name, #vs, function(i : integer, job : SquareStressJob)
		local v = vs[i]
		if not rt.isVehicle(v) then   -- gone, or the id now names something else
			gone = gone + 1
			forget(bl.vehicles, v)
			logic.resume(job)
			return
		end
		local ok, err : boolean, any = pcall(rt.send, name, api.cmd.makeVehicleSellCmd({ v }), function(success : boolean, _d : any)
			if success then
				forget(bl.vehicles, v)   -- never acted on again
				sold = sold + 1
				soldList[#soldList + 1] = v
			else
				failed = failed + 1
				rt.log(string.format("[SQST] %s sell vehicle %d failed", name, v))
			end
			logic.resume(job)
		end)
		if not ok then
			failed = failed + 1
			rt.log(string.format("[SQST] %s error vehicle %d: %s", name, v, tostring(err)))
			logic.resume(job)
		end
	end, { serial = true, label = "Selling buses", timeoutMs = logic.VEHICLE_TIMEOUT_MS })

	-- Wait until every sold bus is gone (no TRANSPORT_VEHICLE, or on none of our lines) before any line goes.
	rt.enqueue(name .. ":wait", 1, function(_i : integer, job : SquareStressJob)
		local t0 = rt.nowUs()
		local function poll()
			local onLines : {integer : boolean} = {}
			for _, l in ipairs(ls) do
				for _, v in ipairs(lineVehicles(l)) do onLines[v] = true end
			end
			local left = 0
			for _, v in ipairs(soldList) do
				if rt.isVehicle(v) and onLines[v] then left = left + 1 end
			end
			local waited = (rt.nowUs() - t0) / 1000
			if left == 0 or waited >= bl.REMOVE_WAIT_MS then
				waitNote = string.format("%d still listed after %.0f ms", left, waited)
				logic.resume(job)
				return
			end
			rt.later(name .. ":poll", bl.REMOVE_POLL_MS, poll)
		end
		poll()
	end, { serial = true, quiet = true, label = "Waiting for sold buses", timeoutMs = bl.REMOVE_WAIT_MS + 10000 })

	rt.enqueue(name .. ":lines", #ls, function(i : integer, job : SquareStressJob)
		local l = ls[i]
		if not rt.isLine(l) then
			gone = gone + 1
			forget(bl.lines, l)
			bl.lineTwins[l] = nil   -- a reused id must not inherit the twin (FLOW_BUS)
			logic.resume(job)
			return
		end
		local listed = lineVehicles(l)
		if #listed > 0 then
			kept = kept + 1
			rt.log(string.format("[SQST] %s line %d still lists %d vehicles; not deleted", name, l, #listed))
			logic.resume(job)
			return
		end
		local ok, err : boolean, any = pcall(rt.send, name, api.cmd.makeLineDestroyCmd(l), function(success : boolean, _d : any)
			if success then
				deleted = deleted + 1
				forget(bl.lines, l)
				bl.lineTwins[l] = nil
			else
				failed = failed + 1
				rt.log(string.format("[SQST] %s delete line %d failed", name, l))
			end
			logic.resume(job)
		end)
		if not ok then
			failed = failed + 1
			rt.log(string.format("[SQST] %s error line %d: %s", name, l, tostring(err)))
			logic.resume(job)
		end
	end, { serial = true, label = "Removing bus lines", timeoutMs = logic.VEHICLE_TIMEOUT_MS })

	rt.enqueue(name .. ":summary", 1, function(_i : integer, job : SquareStressJob)
		logic.resume(job)
		rt.log(string.format("[SQST] %s summary vehicles=%d sold=%d lines=%d deleted=%d kept=%d gone=%d failed=%d wait: %s left: %d lines, %d buses (stops and depots stay)",
			name, #vs, sold, #ls, deleted, kept, gone, failed, waitNote, #bl.lines, #bl.vehicles))
	end, { serial = true, quiet = true })
end

return bl
