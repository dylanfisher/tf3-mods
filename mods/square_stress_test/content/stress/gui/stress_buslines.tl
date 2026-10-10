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
-- stub is verified by the street edge count at that node. Construction transforms never hold -0
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
-- buses come from findBestDepotForLine if it finds one, else the town's depot. A line left with no bus is
-- destroyed again (makeLineDestroyCmd) and its stops are logged as wasted. Every vehicle or line id is
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

local bl : SquareStressBusLines = {
	ui = { towns = 2, lines = 1, buses = 2 },
	lines = {},
	vehicles = {},
	depots = {},
	avoidPoints = {},
	lastGroups = {},
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
bl.LINE_TIMEOUT_MS = 300000            -- one line (depot rings, 2 stops, line, N buses) at most
bl.REMOVE_WAIT_MS = 20000              -- Remove added bus lines: wait at most this for sold buses to be gone
bl.REMOVE_POLL_MS = 500

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

--- Node configs at the given nodes with oldEdge re-pointed (node -> new edge id), as move_it does.
local function nodeConfigs(oldEdge : integer, nodeToNew : {{integer}}) : {Proposal.BaseNodeLaneConnectionAndEntity}, {integer}
	local add : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local rm : {integer} = {}
	for _, pair in ipairs(nodeToNew) do
		local node, newId = pair[1], pair[2]
		local cfg = comp(node, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
		if cfg ~= nil then
			rm[#rm + 1] = node
			local ae = api.type.BaseNodeLaneConnectionAndEntity.new()
			ae.entity = node
			ae.comp = cfg
			local conns : {LaneConnection} = {}
			for i = 1, #cfg.laneConnections do
				local lc = cfg.laneConnections[i]
				if lc.segment0 == oldEdge then lc.segment0 = newId end
				if lc.segment1 == oldEdge then lc.segment1 = newId end
				conns[#conns + 1] = lc
			end
			ae.comp.laneConnections = conns
			local cws : {integer} = {}
			for i = 1, #cfg.crosswalks do
				local c = cfg.crosswalks[i]
				cws[#cws + 1] = c == oldEdge and newId or c
			end
			ae.comp.crosswalks = cws
			add[#add + 1] = ae
		end
	end
	return add, rm
end

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

--- Splits g at param t (new node -4, halves -1 and -2) and adds a stub -3 from there to node (an
--- existing node, or a new node -5 at nodePos when node is nil: the pre-check's stand-in).
local function connectProposal(g : SquareStressEdgeGeo, t : number, node : integer, nodePos : {number}) : SimpleProposal
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
	local cfgAdd, cfgRm = nodeConfigs(g.id, { { g.node0, -1 }, { g.node1, -2 } })
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
local function freeNode(con : Engine.Component.Construction, pos : {number}) : integer, {number}
	local CT = api.type.ComponentType
	local frozen : {integer : boolean} = {}
	for _, n in ipairs(con.frozenNodes or {}) do frozen[n] = true end
	local best : integer = nil
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
					if d < bestD then best, bestPos, bestD = n, p, d end
				end
			end
		end
	end
	return best, bestPos
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

--- Builds a road depot beside one of the edges and connects its entrance to the street.
--- onDone(ok, details, depot): ok = the depot exists and its entrance node got a street edge.
function bl.buildDepot(name : string, edges : {SquareStressEdgeGeo}, cx : number, cy : number,
		onDone : function(ok : boolean, details : string, depot : integer))
	local tries = bl.depotTries(edges, bl.DEPOT_GAPS, bl.DEPOT_PARAMS)
	local before = bl.listSet(api.type.ComponentType.VEHICLE_DEPOT)
	local idx, sends = 0, 0
	local pre : {string : integer} = {}
	local sentText : {string} = {}
	local function head() : string
		return string.format("edges=%d spots=%d tried=%d pre={%s} sent=%d [%s]", #edges, #tries, idx, countsText(pre), sends,
			table.concat(sentText, "; "))
	end
	if #tries == 0 then
		onDone(false, head() .. " no depot spot (edges too short or no direction)", nil)
		return
	end
	local nextBatch : function()

	local function connect(c : SquareStressDepotTry, depot : integer, conE : integer, located : string)
		local info = located
		local con = conE ~= nil and comp(conE, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction or nil
		if con == nil then
			onDone(false, string.format("%s | %s | construction=%s has no CONSTRUCTION component", head(), info, str(conE)), depot)
			return
		end
		local node, nodePos = freeNode(con, c.entrance)
		info = string.format("%s depot=%s construction=%d frozenNodes=%d frozenEdges=%d freeNode=%s", info, str(depot), conE,
			#(con.frozenNodes or {}), #(con.frozenEdges or {}), str(node))
		if node == nil then
			onDone(false, head() .. " | " .. info .. " (no free entrance node found)", depot)
			return
		end
		info = info .. string.format(" at %.1f,%.1f (%.1fm from target)", nodePos[1], nodePos[2], dist2(nodePos, c.entrance))
		local edgesBefore = bl.streetEdgesAt(node)
		if edgesBefore >= 2 then
			onDone(depot ~= nil, head() .. " | " .. info .. string.format(" already connected (streetEdges at node=%d)", edgesBefore), depot)
			return
		end
		local g2 : SquareStressEdgeGeo = nil
		if api.engine.entityExists(c.edge.id) then g2 = bl.edgeGeo(c.edge.id, cx, cy) end
		if g2 == nil then
			onDone(false, head() .. " | " .. info .. string.format(" street edge %d changed; not connected", c.edge.id), depot)
			return
		end
		rt.send(name .. ":connect", api.cmd.makeWorldBuildProposalCmd(connectProposal(g2, c.t, node, nodePos), nil, false, false),
			function(okC : boolean, dataC : any)
				rt.later(name .. ":connected", SETTLE_MS, function()
					local edgesAfter = bl.streetEdgesAt(node)
					local connected = okC and (edgesAfter >= 2 or edgesAfter > edgesBefore)
					onDone(connected and depot ~= nil, string.format("%s | %s connect: success=%s %s streetEdges at node %d->%d connected=%s",
						head(), info, tostring(okC), bl.errText(dataC), edgesBefore, edgesAfter, tostring(connected)), depot)
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

--- Our nearest connected depot (built this session) within r of (x, y).
local function ourDepotNear(x : number, y : number, r : number) : integer, number
	local best : integer = nil
	local bestD = r
	for _, d in ipairs(bl.depots) do
		if api.engine.entityExists(d) then
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
			if not rt.isLine(line) then
				onDone(bought, string.format("line=%d is gone; setLine skipped (bus %d stays in the depot)", line, v))
				return
			end
			rt.send(name .. ":setLine", api.cmd.makeVehicleSetLineCmd(v, line, 0), function(okS : boolean, _d : any)
				if not okS then
					onDone(bought, string.format("setLine failed vehicle=%d line=%d (bought, stays in the depot)", v, line))
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

--- The town's eligible street edges within TOWN_EDGE_RADIUS of its centre (the TOWN_EDGE_MAX nearest),
--- nearest the centre first, that belong to this town (closest town), and the built-up ones among them
--- (a town building within BUILT_RADIUS; octree TOWN_BUILDING). Third result: summary.
local function townEdges(town : SquareStressTownPos) : {SquareStressEdgeGeo}, {SquareStressEdgeGeo}, string
	local cands, info = bl.streetEdgeCandidates(town.x, town.y, bl.TOWN_EDGE_RADIUS)
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

local function forget(list : {integer}, e : integer)
	for k = #list, 1, -1 do
		if list[k] == e then table.remove(list, k) end
	end
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
local function findDepot(name : string, run : TownRun, onDone : function(depot : integer, how : string, far : boolean))
	local town = run.town
	local clears = rt.queueClears
	local ours, dOurs = ourDepotNear(town.x, town.y, bl.BUS_DEPOT_REUSE)
	if ours ~= nil then onDone(ours, string.format("ours, %.0fm", dOurs), false) return end
	local near, dNear = bl.nearestRoadDepot(town.x, town.y, bl.BUS_DEPOT_REUSE)
	if near ~= nil then onDone(near, string.format("existing, %.0fm", dNear), false) return end
	local notes : {string} = {}
	local ri = 0
	local function rings() : string return table.concat(notes, "; ") end
	local tryRing : function()
	tryRing = function()
		ri = ri + 1
		local ring = bl.DEPOT_RINGS[ri]
		if ring == nil then
			rt.detail(string.format("[SQST] %s %s depot rings: %s", name, run.name, rings()))
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
		local edges, inRing = bl.ringPick(cands, ring[1], ring[2], bl.RING_SAMPLE, bl.RING_EDGES,
			function(g : SquareStressEdgeGeo) : number return depotScore(g, town.id) end)
		if #edges == 0 then
			notes[#notes + 1] = label .. " edges=0"
			tryRing()
			return
		end
		bl.buildDepot(name .. ":depot", edges, town.x, town.y, function(okD : boolean, dd : string, depot : integer)
			notes[#notes + 1] = string.format("%s inRing=%d %s", label, inRing, bl.depotShort(dd))
			rt.detail(string.format("[SQST] %s %s depot %s: %s", name, run.name, label, dd))
			if okD then
				rt.detail(string.format("[SQST] %s %s depot rings: %s", name, run.name, rings()))
				onDone(depot, "built in ring " .. label, false)
				return
			end
			if rt.queueClears ~= clears then onDone(nil, "queue cleared", false) return end
			tryRing()
		end)
	end
	tryRing()
end

--- Two free stop edges for a line: built-up edges without traffic first, then built-up, then any town
--- edge without traffic, then any; never within STOP_AVOID of our stops or depot entrances.
local function pickStops(town : SquareStressTownPos) : SquareStressEdgeGeo, SquareStressEdgeGeo, string, string
	local mine, built, info = townEdges(town)
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
	local a, b, pool, info = pickStops(town)
	if a == nil then
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
					rt.detail(string.format("[SQST] %s %s created %s stationGroups=%d,%d", name, run.name, dl, g1, g2))
					head = head .. " " .. dl
					if stopped(0) then return end
					local depot = run.depot
					local best, bestInfo = bl.bestDepotForLine(line, a.mid[1], a.mid[2])
					if best ~= nil then
						depot = best
					elseif run.depotFar then
						abandon(line, string.format("last-resort depot %d not confirmed (%s)", run.depot, bestInfo))
						return
					end
					head = head .. string.format(" buses from depot=%d (%s)", depot, bestInfo)
					bl.buyBuses(name, depot, makeCfg, buses, line, function(bought : integer, failure : string)
						if failure == nil then
							onDone(true, string.format("%s buses=%d/%d", head, bought, buses))
						elseif bought == 0 and failure ~= "queue cleared" then
							abandon(line, string.format("buses=0/%d | %s", buses, failure))
						else
							onDone(false, string.format("%s buses=%d/%d | %s", head, bought, buses, failure))
						end
					end)
				end)
			end)
		end)
	end

	local function afterDepot()
		if stopped(0) then return end
		if not api.engine.entityExists(a.id) or not api.engine.entityExists(b.id) then
			a, b, pool, info = pickStops(town)   -- the depot's street connection replaced one of them
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
	rt.log(string.format("[SQST] %s: refused, %s is still queued or running", name, busy))
	return true
end

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
		rt.log("[SQST] bus_lines: no town found")
		return
	end
	local runs : {TownRun} = {}
	local plan : {{integer}} = {}   -- {run index, line k}
	for i, t in ipairs(picked) do
		runs[i] = { town = t, name = entityName(t.id), failed = false, done = 0, wasted = 0 }
		for k = 1, nLines do plan[#plan + 1] = { i, k } end
	end
	rt.log(string.format("[SQST] %s: %d towns x %d lines x %d buses (%d lines)", name, #runs, nLines, nBuses, #plan))
	local stats = { lines = 0, townsOk = 0, townsFailed = 0 }
	local failsInRow = 0
	local stopReason : string = nil
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
	end, { serial = true, label = "Bus lines", timeoutMs = bl.LINE_TIMEOUT_MS })

	rt.enqueue(name .. ":summary", 1, function(_i : integer, job : SquareStressJob)
		logic.resume(job)
		token = token + 1   -- answers of a timed-out line no longer count
		local wasted = 0
		for _, run in ipairs(runs) do wasted = wasted + run.wasted end
		rt.log(string.format("[SQST] %s summary towns=%d ok=%d failed=%d lines=%d (complete %d) buses=%d wastedStops=%d (session: %d lines, %d buses) balance %s->%s%s",
			name, #runs, stats.townsOk, stats.townsFailed, #bl.lines - linesBefore, stats.lines, #bl.vehicles - vehiclesBefore, wasted, #bl.lines,
			#bl.vehicles, logic.formatMoney(balance0), logic.formatMoney(rt.balance()), stopReason ~= nil and (" stopped: " .. stopReason) or ""))
	end, { serial = true, quiet = true })
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
