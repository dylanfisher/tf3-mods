-- Stress Test probes (PLAN.md Phase 1): one bounded experiment per open question in
-- plans/square_stress_test/RESEARCH.md "Open probes" 1-8, plus probe 9 (clearing private car traffic,
-- plans/square_stress_test/PROBES_TRAFFIC.md) and probe 10 (automatic bus lines: stops, depot, line,
-- bus; plans/square_stress_test/PROBES_BUSLINES.md). Every probe runs from the queue (GUI main
-- thread, stress_runtime.tl), wraps its work in pcall (the queue's step pcall plus the callbacks'),
-- and ends with one "[SQST-PROBE] <name> ok|fail <details>" line in stdout.txt. Follow-up reads are
-- delayed queue steps (rt.later). In-game steps: plans/square_stress_test/TESTING.md.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local bl = ug_require "square_stress_test::/stress/gui/stress_buslines.tl" as SquareStressBusLines
local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl" as SquareStressNodeCfg

local probes : SquareStressProbes = { list = {} }

---------------------------------------------------------------------------
-- Read helpers (engine reads from the GUI state, as base GUI code does)

local function str(v : any) : string
	if type(v) == "table" then
		local parts : {string} = {}
		for i, x in ipairs(v as {any}) do
			if i > 8 then parts[#parts + 1] = "..." break end
			parts[#parts + 1] = str(x)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	if type(v) == "number" then
		local n = v as number
		if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
		return string.format("%.3g", n)
	end
	return tostring(v)
end

local function entitySet(ct : Engine.ComponentType) : {integer : boolean}, integer
	local set : {integer : boolean} = {}
	local list = api.engine.getEntitiesWithComponent(ct)
	for _, e in ipairs(list) do set[e] = true end
	return set, #list
end

-- getEntitiesWithComponent only iterates some component types: BASE_EDGE_STREET throws "Cannot loop
-- over this component type" (in game 2026-10-10, docs/findings.md "Stress Test probes"). TOWN works
-- (probe 1); base GUI code only lists TOWN, INDUSTRY, VEHICLE_DEPOT, TRANSPORT_VEHICLE, WAREHOUSE and
-- STATION_GROUP this way (statistics/*.tl, line_vehicle_mgmt/manager_window.tl). Street edges are
-- found with the octree instead: findEntitiesInCircle(BASE_EDGE) (api/tealdef/api/engine/util.d.tl:329,
-- base tutorial_story_util.tl:76; square_bulk_bulldozer's bb_gather.tl uses it in game), keeping the
-- edges that have a BASE_EDGE_STREET component (a track edge has none).

--- Street edges whose octree entry lies within r metres of (x, y); -1 when the query fails.
function probes.streetEdgesNear(x : number, y : number, r : number) : integer, integer
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, api.type.ComponentType.BASE_EDGE)
	if not ok or list == nil then return -1, nil end
	local n : integer = 0
	local first : integer = nil
	for _, e in ipairs(list as {integer}) do
		local okS, se : boolean, any = pcall(api.engine.getComponent, e, api.type.ComponentType.BASE_EDGE_STREET)
		if okS and se ~= nil then
			n = n + 1
			if first == nil then first = e end
		end
	end
	return n, first
end

local STREET_COUNT_RADIUS <const> = 600.0   -- probe 3b's 3x3 grid spans 300 m; develop adds streets around it
local REFERENCE_RADIUS <const> = 5000.0     -- probe 4: any existing street edge to copy typeIndex from

local function townComp(town : integer) : Engine.Component.Town
	return api.engine.getComponent(town, api.type.ComponentType.TOWN) as Engine.Component.Town
end

local function townBuildings(town : integer) : integer
	local m = api.engine.system.townBuildingSystem.getTown2BuildingMap()
	local list = m[town]
	return list ~= nil and #list or 0
end

local function townCaps(town : integer) : string
	local ok, m = pcall(api.engine.system.townBuildingSystem.getTown2personCapacitiesMap)
	if not ok or m == nil then return "?" end
	return str(m[town])
end

local function townName(e : integer) : string
	local ok, n = pcall(api.engine.util.getEntityName, e)
	return ok and tostring(n) or "?"
end

local function closestTown(x : number, y : number) : integer
	local t = api.engine.util.town.getClosestTown(api.type.Vec3f.new(x, y, 0))
	if t == nil or t < 0 then return nil end
	return t
end

local function townSummary(town : integer) : string
	local tc = townComp(town)
	return string.format("town=%d name=%s initCaps=%s sizeFactors=%s scaling=%s buildings=%d personCaps=%s",
		town, townName(town), str(tc.initialLandUseCapacities), str(tc.sizeFactors), str(tc.capacityScalingFactor),
		townBuildings(town), townCaps(town))
end

local function gameSpeed() : integer
	local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
	return gs ~= nil and gs.speedup or nil
end

local function cameraOrFail(name : string) : number, number
	local ok, x, y = pcall(rt.camera)
	if not ok or x == nil then
		rt.probe(name, false, "camera read failed: " .. tostring(x))
		return nil, nil
	end
	if not api.engine.terrain.isValidCoordinate(api.type.Vec2f.new(x, y)) then
		rt.probe(name, false, string.format("camera centre %.0f,%.0f is off the map", x, y))
		return nil, nil
	end
	return x, y
end

--- A queue step that turns an error into a "[SQST-PROBE] <name> fail error: ..." line.
local function guarded(name : string, fn : function(i : integer)) : function(i : integer)
	return function(i : integer)
		local ok, err : boolean, any = pcall(fn, i)
		if not ok then rt.probe(name, false, "error: " .. tostring(err)) end
	end
end

local function add(id : string, label : string, tooltip : string, run : function())
	probes.list[#probes.list + 1] = { id = id, label = label, tooltip = tooltip, run = run }
end

---------------------------------------------------------------------------
-- Probe 1: makeTownCreateCmd in a running game (RESEARCH.md section 1). Builds the TownInfo through
-- api.engine.mapgen.createTowns, as the map editor does (base gui/map_editor/map_editor.tl:1621-1636,
-- Map.Town fields :1743-1750). The editor also destroys createTowns' toRemove list; this probe never
-- does: it only logs the count, so existing towns are safe. big = true also overwrites the TownInfo's
-- initialLandUseCapacities with 1600 per district (the stock tool's maximum, RESEARCH.md) to see
-- whether larger values are accepted.

local townSeq = 0

local function createTown(name : string, big : boolean)
	local x, y = cameraOrFail(name)
	if x == nil then return end
	rt.enqueue(name, 1, guarded(name, function(_i : integer)
		local before, nBefore = entitySet(api.type.ComponentType.TOWN)
		townSeq = townSeq + 1
		local t = api.type.Map.Town.new()
		t.pos = api.type.Vec2f.new(x, y)
		t.name = string.format("SQST Town %d", townSeq)
		t.sizeFactors = { 1, 1, 1 }
		local res = api.engine.mapgen.createTowns("sqst", { t })
		local toAdd = res.toAdd
		local info = string.format("pos=%.0f,%.0f towns=%d toAdd=%d toRemove=%d(ignored)", x, y, nBefore, #toAdd, #res.toRemove)
		if #toAdd == 0 then
			rt.probe(name, false, info .. " createTowns returned nothing to add")
			return
		end
		local ti = toAdd[1]
		info = info .. string.format(" info.caps=%s info.scaling=%s info.angle=%s", str(ti.initialLandUseCapacities),
			str(ti.capacityScalingFactor), str(ti.majorStreetAngle))
		if big then
			local okSet, errSet : boolean, any = pcall(function() ti.initialLandUseCapacities = { 1600, 1600, 1600 } end)
			info = info .. (okSet and (" set caps -> " .. str(ti.initialLandUseCapacities)) or (" setting caps failed: " .. tostring(errSet)))
		end
		local t0 = rt.nowUs()
		rt.send(name, api.cmd.makeTownCreateCmd(toAdd), function(success : boolean, _data : any)
			local cbMs = (rt.nowUs() - t0) / 1000
			rt.log(string.format("[SQST] %s callback success=%s after %.0f ms", name, tostring(success), cbMs))
			rt.later(name .. ":check", 3000, function()
				local after, nAfter = entitySet(api.type.ComponentType.TOWN)
				local new : {integer} = {}
				for e in pairs(after) do
					if not before[e] then new[#new + 1] = e end
				end
				local details = string.format("%s success=%s callbackMs=%.0f towns %d->%d", info, tostring(success), cbMs, nBefore, nAfter)
				if #new > 0 then details = details .. " new: " .. townSummary(new[1]) end
				rt.probe(name, success and #new > 0, details)
			end)
		end)
	end), { quiet = true })
end

add("p1_town", "1a Create town here",
	"Probe 1: api.engine.mapgen.createTowns + makeTownCreateCmd at the camera centre (default size).",
	function() createTown("town_create", false) end)
add("p1_town_big", "1b Create big town here",
	"Probe 1: the same, with initialLandUseCapacities overwritten to 1600 per district.",
	function() createTown("town_create_big", true) end)

---------------------------------------------------------------------------
-- Probe 2: makeTownUpdateSizeCmd(updateAllBuildings = true) with a large factor on the town closest
-- to the camera (api/tealdef/api/cmd.d.tl:876; base growth sends false: town_growth.script.tl:550).
-- Reads back the size factors, building count and person capacities 5 s and 30 s later.

add("p2_grow", "2 Grow nearest town x10",
	"Probe 2: makeTownUpdateSizeCmd(town, sizeFactors x10, updateAllBuildings=true) on the town closest to the camera.",
	function()
		local name = "town_grow_x10"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local town = closestTown(x, y)
			if town == nil then
				rt.probe(name, false, "no town found")
				return
			end
			local before = townSummary(town)
			local factors = logic.scaledFactors(townComp(town).sizeFactors, 10)
			local t0 = rt.nowUs()
			rt.send(name, api.cmd.makeTownUpdateSizeCmd(town, factors, true), function(success : boolean, _data : any)
				local cbMs = (rt.nowUs() - t0) / 1000
				rt.log(string.format("[SQST] %s callback success=%s after %.0f ms; before: %s; sent sizeFactors=%s",
					name, tostring(success), cbMs, before, str(factors)))
				rt.later(name .. ":5s", 5000, function()
					rt.log("[SQST] " .. name .. " +5s: " .. townSummary(town))
				end)
				rt.later(name .. ":30s", 30000, function()
					rt.probe(name, success, string.format("callbackMs=%.0f before: %s | +30s: %s", cbMs, before, townSummary(town)))
				end)
			end)
		end), { quiet = true })
	end)

---------------------------------------------------------------------------
-- Probe 3: makeTownDevelopAtCmd(pos, developStreets = true, upgradeBuildings = true)
-- (api/tealdef/api/cmd.d.tl:844; no base caller). Counts street edges and the nearest town's
-- buildings before and after.

local function developAt(name : string, n : integer, spacing : number)
	local x, y = cameraOrFail(name)
	if x == nil then return end
	local points = logic.gridPoints(x, y, n, spacing)
	local beforeStreets, beforeBuildings, town : integer, integer, integer = 0, 0, nil
	local okCount, sent = 0, 0
	rt.enqueue(name, #points, guarded(name, function(i : integer)
		if i == 1 then
			town = closestTown(x, y)
			beforeStreets = probes.streetEdgesNear(x, y, STREET_COUNT_RADIUS)
			beforeBuildings = town ~= nil and townBuildings(town) or 0
		end
		local p = points[i]
		sent = sent + 1
		rt.send(name, api.cmd.makeTownDevelopAtCmd(api.type.Vec2f.new(p[1], p[2]), true, true), function(success : boolean, _data : any)
			if success then okCount = okCount + 1 end
		end)
		if i == #points then
			rt.later(name .. ":check", 5000, function()
				local streets = probes.streetEdgesNear(x, y, STREET_COUNT_RADIUS)
				local buildings = town ~= nil and townBuildings(town) or 0
				rt.probe(name, okCount > 0, string.format(
					"calls=%d succeeded=%d spacing=%.0fm town=%s streetEdges(r=%.0fm) %d->%d (+%d) townBuildings %d->%d (+%d)",
					sent, okCount, spacing, town ~= nil and townName(town) or "none", STREET_COUNT_RADIUS, beforeStreets, streets, streets - beforeStreets,
					beforeBuildings, buildings, buildings - beforeBuildings))
			end)
		end
	end), { quiet = true })
end

add("p3_develop", "3a Develop at camera (1 call)",
	"Probe 3: one makeTownDevelopAtCmd(camera centre, developStreets=true, upgradeBuildings=true).",
	function() developAt("town_develop_1", 1, 0) end)
add("p3_develop_grid", "3b Develop 3x3 grid (9 calls)",
	"Probe 3: nine makeTownDevelopAtCmd calls on a 150 m grid around the camera, sent through the queue.",
	function() developAt("town_develop_9", 9, 150) end)

---------------------------------------------------------------------------
-- Probe 4: a street edge built from scratch (no edge to copy). Pattern: the base rail builder
-- (base mission/tasks/auto_builder/track_builder.tl:7-77) with the street parts from
-- api/tealdef/api/type.d.tl:2519-2527 (type = 0, streetEdge) and RoadType.STREET. Variant A copies the
-- typeIndex of an existing street edge (or -1) and sends no context; if it fails, variant B uses
-- typeIndex 1 (as track_builder) and a Context with the player. Stops and depots are not tried yet.

local STREET_TEMPLATE <const> = "::/infrastructure/street/town/town_new_medium.street_template"

--- typeIndex and BASE_EDGE_STREET component of an existing street edge within REFERENCE_RADIUS of the
--- camera (octree, see streetEdgesNear) (move_it copies the latter the same way: .cache/subscribed/move_it/content/tools/move_it/move_it.script.tl:3716-3720), or -1 / nil.
local function referenceEdge(x : number, y : number) : integer, string, Engine.Component.BaseEdgeStreet
	local _n, e = probes.streetEdgesNear(x, y, REFERENCE_RADIUS)
	if e == nil then return -1, "none", nil end
	local be = api.engine.getComponent(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
	if be == nil then return -1, "none", nil end
	local se = api.engine.getComponent(e, api.type.ComponentType.BASE_EDGE_STREET) as Engine.Component.BaseEdgeStreet
	return be.typeIndex, string.format("edge=%d type=%s typeIndex=%s template=%s", e, str(be.type), str(be.typeIndex), tostring(be.roadTemplate)), se
end

local function streetProposal(x : number, y : number, typeIndex : integer, streetEdge : Engine.Component.BaseEdgeStreet) : SimpleProposal
	local tpl = api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(STREET_TEMPLATE))
	local p0 = { x - 40, y, 0.0 }
	local p1 = { x + 40, y, 0.0 }
	p0[3] = api.engine.terrain.getHeightAt(api.type.Vec2f.new(p0[1], p0[2]))
	p1[3] = api.engine.terrain.getHeightAt(api.type.Vec2f.new(p1[1], p1[2]))
	local proposal = api.type.SimpleProposal.new()
	local n0 = api.type.NodeAndEntity.new()
	n0.entity = -3
	n0.comp.position = api.type.Vec3f.new(p0[1], p0[2], p0[3])
	local n1 = api.type.NodeAndEntity.new()
	n1.entity = -4
	n1.comp.position = api.type.Vec3f.new(p1[1], p1[2], p1[3])
	local seg = api.type.SegmentAndEntity.new()
	seg.entity = -1
	seg.type = 0
	-- No api.type.BaseEdgeStreet constructor in the tealdef: copy an existing edge's component, else
	-- keep the SegmentAndEntity's default.
	if streetEdge ~= nil then seg.streetEdge = streetEdge end
	seg.comp.node0 = -3
	seg.comp.node1 = -4
	-- Straight edge: both tangents point from node0 to node1, length = chord (+0 zeros only).
	seg.comp.tangent0 = api.type.Vec3f.new(80, 0, p1[3] - p0[3])
	seg.comp.tangent1 = api.type.Vec3f.new(80, 0, p1[3] - p0[3])
	seg.comp.position0 = api.type.Vec3f.new(p0[1], p0[2], p0[3])
	seg.comp.position1 = api.type.Vec3f.new(p1[1], p1[2], p1[3])
	seg.comp.type = api.type["enum"].BaseEdgeType.NORMAL
	seg.comp.typeIndex = typeIndex
	seg.comp.laneConfigs = tpl.laneConfigs
	seg.comp.roadTemplate = STREET_TEMPLATE
	seg.comp.roadStyle = tpl.streetStyle
	seg.comp.roadType = api.type["enum"].RoadType.STREET
	proposal.streetProposal.nodesToAdd = { n0, n1 }
	proposal.streetProposal.edgesToAdd = { seg }
	-- both new nodes are 1-edge dead ends: an empty config each (script-made nodes get none otherwise,
	-- docs/findings/towns.md "Street proposal crash")
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local cfgRm : {integer} = {}
	nc.complete({ seg }, {}, cfgAdd, cfgRm)
	proposal.streetProposal.nodeConfigsToAdd = cfgAdd
	return proposal
end

local function errText(data : any) : string
	local ok, s = pcall(function() : string
		local d = data as WorldBuildProposalCommandData
		local es = d.resultProposalData.errorState
		return string.format("critical=%s messages=%s warnings=%s costs=%s", tostring(es.critical), str(es.messages),
			str(es.warnings), str(d.resultProposalData.costs))
	end)
	return ok and s or "(no error state)"
end

add("p4_street", "4 Build street here",
	"Probe 4: an 80 m town street (town_new_medium) built from scratch along x at the camera centre.",
	function()
		local name = "street_from_scratch"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local refIdx, refInfo, refStreet = referenceEdge(x, y)
			local before = probes.streetEdgesNear(x, y, STREET_COUNT_RADIUS)
			local function tryB(infoA : string)
				local ctx = api.type.Context.new()
				ctx.player = rt.player()
				rt.send(name .. ":B", api.cmd.makeWorldBuildProposalCmd(streetProposal(x, y, 1, refStreet), ctx, false, true), function(success : boolean, data : any)
					rt.later(name .. ":checkB", 1000, function()
						local after = probes.streetEdgesNear(x, y, STREET_COUNT_RADIUS)
						rt.probe(name, success, string.format("variant=B(typeIndex=1, ctx.player) ref: %s | A: %s | B: success=%s %s streetEdges %d->%d",
							refInfo, infoA, tostring(success), errText(data), before, after))
					end)
				end)
			end
			rt.send(name .. ":A", api.cmd.makeWorldBuildProposalCmd(streetProposal(x, y, refIdx, refStreet), nil, false, false), function(success : boolean, data : any)
				local infoA = string.format("success=%s typeIndex=%d %s", tostring(success), refIdx, errText(data))
				if success then
					rt.later(name .. ":checkA", 1000, function()
						local after = probes.streetEdgesNear(x, y, STREET_COUNT_RADIUS)
						rt.probe(name, true, string.format("variant=A ref: %s | A: %s streetEdges %d->%d", refInfo, infoA, before, after))
					end)
				else
					tryB(infoA)
				end
			end)
		end), { quiet = true })
	end)

---------------------------------------------------------------------------
-- Probe 5: buy vehicles on an existing line from the GUI queue, with callbacks (RESEARCH.md section 6
-- conflict). Clones the first vehicle of the player's first line that has one, as the base "duplicate
-- vehicles" handler does (base gui/line_vehicle_mgmt/manager_window.tl:8494-8526 config copy,
-- vehicle_react_util.tl:331-382 purchaseTime/autoLoadConfig, buy, then SetLine in the callback), with
-- the depot from api.engine.util.vehicle.findBestLineAndDepotForVehicle.

local function findLineVehicle() : integer, integer
	for _, line in ipairs(api.engine.system.lineSystem.getLinesForPlayer(rt.player())) do
		local vs = api.engine.system.transportVehicleSystem.getLineVehicles(line)
		if vs ~= nil and #vs > 0 then return line, vs[1] end
	end
	return nil, nil
end

local function cloneConfig(vehicle : integer) : TransportVehicleConfig
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
	local cfg = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	local parts : {TransportVehiclePart} = {}
	for _, part in ipairs(cfg.vehicles) do
		part.purchaseTime = math.floor(gt.gameTime)
		part.maintenanceState = 1
		local auto : {boolean} = {}
		for k = 1, #part.part.compartment2loadConfig do auto[k] = true end
		part.autoLoadConfig = auto
		parts[#parts + 1] = part
	end
	cfg.vehicles = parts
	return cfg
end

local function buyVehicles(name : string, n : integer)
	rt.enqueue(name, 1, guarded(name, function(_i : integer)
		local line, vehicle = findLineVehicle()
		if line == nil then
			rt.probe(name, false, "no line with a vehicle (build one bus line with one bus first)")
			return
		end
		local ld = api.engine.util.vehicle.findBestLineAndDepotForVehicle(vehicle)
		local depot = ld ~= nil and ld[2] or -1
		if depot == nil or depot < 0 then
			rt.probe(name, false, string.format("line=%d vehicle=%d: findBestLineAndDepotForVehicle found no depot (%s)", line, vehicle, str(ld)))
			return
		end
		local before = #api.engine.system.transportVehicleSystem.getLineVehicles(line)
		local balance0 = rt.balance()
		local bought, setLine, answered = 0, 0, 0
		for _ = 1, n do
			rt.send(name .. ":buy", api.cmd.makeVehicleBuyCmd(rt.player(), depot, cloneConfig(vehicle)), function(success : boolean, data : any)
				answered = answered + 1
				if not success then return end
				bought = bought + 1
				local newV = (data as VehicleBuyCommandData).resultVehicleEntity
				rt.send(name .. ":setLine", api.cmd.makeVehicleSetLineCmd(newV, line, 0), function(ok2 : boolean, _d : any)
					if ok2 then setLine = setLine + 1 end
				end)
			end)
		end
		rt.later(name .. ":check", 5000, function()
			local after = #api.engine.system.transportVehicleSystem.getLineVehicles(line)
			rt.probe(name, bought == n and setLine == n, string.format(
				"line=%d (%s) depot=%d requested=%d answered=%d bought=%d setLine=%d lineVehicles %d->%d balance %s->%s",
				line, townName(line), depot, n, answered, bought, setLine, before, after,
				logic.formatMoney(balance0), logic.formatMoney(rt.balance())))
		end)
	end), { quiet = true })
end

add("p5_buy1", "5a Buy 1 vehicle on first line",
	"Probe 5: clone the first vehicle of your first line: makeVehicleBuyCmd at its best depot, then makeVehicleSetLineCmd in the callback.",
	function() buyVehicles("vehicle_buy_1", 1) end)
add("p5_buy5", "5b Buy 5 in one frame",
	"Probe 5: the same with five buy commands sent in the same frame (batch).",
	function() buyVehicles("vehicle_buy_5", 5) end)

---------------------------------------------------------------------------
-- Probe 6: makeGameSetSpeedCmd above the UI's 4 (cmd.d.tl:708; the UI clamps with
-- getEstimatedMaximumGameSpeed, gui/main/game.tl:632-690), and journal bookings of large amounts.

local function speedProbe(speed : integer)
	local name = "speed_" .. tostring(speed)
	rt.enqueue(name, 1, guarded(name, function(_i : integer)
		local before = gameSpeed()
		local est = "?"
		local okEst, e = pcall(api.gui.game.getEstimatedMaximumGameSpeed)
		if okEst then est = str(e) end
		rt.send(name, api.cmd.makeGameSetSpeedCmd(speed), function(success : boolean, _d : any)
			rt.later(name .. ":1s", 1000, function()
				rt.log(string.format("[SQST] %s +1s speedup=%s", name, str(gameSpeed())))
			end)
			rt.later(name .. ":15s", 15000, function()
				local now = gameSpeed()
				rt.probe(name, success and now == speed, string.format("success=%s estimatedMax=%s speedup before=%s +15s=%s",
					tostring(success), est, str(before), str(now)))
			end)
		end)
	end), { quiet = true })
end

add("p6_speed8", "6a Speed 8", "Probe 6: makeGameSetSpeedCmd(8), read GAME_SPEED.speedup after 1 s and 15 s.", function() speedProbe(8) end)
add("p6_speed16", "6b Speed 16", "Probe 6: makeGameSetSpeedCmd(16), read back after 1 s and 15 s.", function() speedProbe(16) end)

local function bookProbe(name : string, amount : number)
	rt.enqueue(name, 1, guarded(name, function(_i : integer)
		local b0 = rt.balance()
		local entry = api.type.JournalEntry.new()
		entry.amount = amount as integer
		entry.time = -1
		entry.category.type = api.type.JournalEntry.Type.OTHER
		local readBack = str(entry.amount)
		rt.send(name, api.cmd.makeJournalBookAssetCmd(rt.player(), entry, api.type.Vec3f.new(0, 0, 0)), function(success : boolean, _d : any)
			rt.later(name .. ":check", 2000, function()
				local b1 = rt.balance()
				local delta = (b0 ~= nil and b1 ~= nil) and (b1 - b0) or nil
				rt.probe(name, success and delta ~= nil and delta >= amount * 0.99, string.format(
					"success=%s amount=%s entry.amount=%s balance %s -> %s delta=%s",
					tostring(success), str(amount), readBack, str(b0), str(b1), str(delta)))
			end)
		end)
	end), { quiet = true })
end

add("p6_book1b", "6c Book +1 billion", "Probe 6: one makeJournalBookAssetCmd of 1,000,000,000; balance before and 2 s after.",
	function() bookProbe("book_1e9", 1e9) end)
add("p6_book3b", "6d Book +3 billion (overflow test)",
	"Probe 6: one booking of 3,000,000,000 (above a 32-bit integer). May wrap to a negative amount: use a test save.",
	function() bookProbe("book_3e9", 3e9) end)

---------------------------------------------------------------------------
-- Probe 7: runtime write to api.res.getBaseConfig().noCosts (RESEARCH.md section 7: load-time only?).
-- Each click flips the value; build something afterwards and check whether it cost money.

add("p7_nocosts", "7 Toggle baseConfig.noCosts",
	"Probe 7: write api.res.getBaseConfig().noCosts = not current at runtime and read it back. Build a road afterwards to see if it costs money.",
	function()
		local name = "basecfg_nocosts"
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local bc = api.res.getBaseConfig()
			local before = bc.noCosts
			local okW, errW : boolean, any = pcall(function() bc.noCosts = not before end)
			local fresh = api.res.getBaseConfig()
			local after = fresh.noCosts
			rt.probe(name, okW and after == not before, string.format(
				"before=%s wrote=%s writeOk=%s err=%s reread=%s sameObject=%s sandboxMode=%s",
				tostring(before), tostring(not before), tostring(okW), tostring(errW), tostring(after),
				tostring(rawequal(bc, fresh)), tostring(fresh.sandboxMode)))
		end), { quiet = true })
	end)

---------------------------------------------------------------------------
-- Probe 8: per-entity makeEntitySetEmissionsCmd (cmd.d.tl:671) vs the base emissions script, which
-- re-sends changed values periodically unless advancedOptions.missionEmissionsScriptFactor == 0
-- (base game_mechanics/emission/emissions.script.tl:27-29, 115-131). Zeroes 10 emitters, reads them
-- 2 s and 30 s later, then restores the originals.

local function emitter(e : integer) : Engine.Component.EmissionEmitter
	if not api.engine.entityExists(e) then return nil end
	return api.engine.getComponent(e, api.type.ComponentType.EMISSION_EMITTER) as Engine.Component.EmissionEmitter
end

local function zeroCount(list : {{number}}) : integer, integer
	local zero, read = 0, 0
	for _, o in ipairs(list) do
		local em = emitter(math.floor(o[1]))
		if em ~= nil then
			read = read + 1
			if em.noisePower == 0 and em.pollutionPower == 0 then zero = zero + 1 end
		end
	end
	return zero, read
end

--- Entities that may carry an EMISSION_EMITTER, and where they came from.
local function emitterCandidates() : {integer}, string
	local ok, list = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.EMISSION_EMITTER)
	if ok and list ~= nil then return list as {integer}, "EMISSION_EMITTER" end
	local out : {integer} = {}
	local parts : {string} = { "EMISSION_EMITTER not iterable" }
	local function addAll(label : string, fn : function() : {integer})
		local okL, l = pcall(fn)
		if okL and l ~= nil then
			for _, e in ipairs(l as {integer}) do out[#out + 1] = e end
			parts[#parts + 1] = string.format("%s=%d", label, #(l as {integer}))
		else
			parts[#parts + 1] = label .. "=error"
		end
	end
	addAll("vehicles", function() : {integer} return api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE) end)
	addAll("industries", function() : {integer} return api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY) end)
	local okC, cx, cy = pcall(rt.camera)
	if okC and cx ~= nil then
		addAll("constructions1km", function() : {integer}
			return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(cx, cy), 1000, api.type.ComponentType.CONSTRUCTION)
		end)
	end
	return out, table.concat(parts, " ")
end

add("p8_emissions", "8 Zero emissions of 10 entities",
	"Probe 8: makeEntitySetEmissionsCmd(e, 0, 0, ...) on 10 emitters; re-read after 2 s and 30 s, then restore them.",
	function()
		local name = "emissions_zero"
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local factor = api.res.getBaseConfig().advancedOptions.missionEmissionsScriptFactor
			-- EMISSION_EMITTER is not known to be iterable (getEntitiesWithComponent throws for some
			-- types, see streetEdgesNear): try it, else scan the types the base GUI lists (vehicles,
			-- industries) plus the constructions (town buildings) around the camera.
			local all, source = emitterCandidates()
			local picked : {{number}} = {}   -- {entity, noise, pollution, radius}
			for _, e in ipairs(all) do
				local em = emitter(e)
				if em ~= nil and (em.noisePower > 0 or em.pollutionPower > 0) then
					picked[#picked + 1] = { e, em.noisePower, em.pollutionPower, em.radius }
					if #picked >= 10 then break end
				end
			end
			if #picked == 0 then
				rt.probe(name, false, string.format("candidates=%d (%s), none with noise or pollution > 0", #all, source))
				return
			end
			for _, o in ipairs(picked) do
				rt.send(name, api.cmd.makeEntitySetEmissionsCmd(math.floor(o[1]), 0, 0, o[4], o[4]))
			end
			local first = string.format("candidates=%d (%s) picked=%d factor=%s first: e=%d noise=%.3g pollution=%.3g radius=%.3g",
				#all, source, #picked, str(factor), math.floor(picked[1][1]), picked[1][2], picked[1][3], picked[1][4])
			local zero2, read2 = 0, 0
			rt.later(name .. ":2s", 2000, function()
				zero2, read2 = zeroCount(picked)
				rt.log(string.format("[SQST] %s +2s zero=%d/%d", name, zero2, read2))
			end)
			rt.later(name .. ":30s", 30000, function()
				local zero30, read30 = zeroCount(picked)
				rt.probe(name, zero2 > 0, string.format("%s | +2s zero=%d/%d | +30s zero=%d/%d (still zero = not overwritten); restoring",
					first, zero2, read2, zero30, read30))
				for _, o in ipairs(picked) do
					local e = math.floor(o[1])
					if api.engine.entityExists(e) then
						rt.send(name .. ":restore", api.cmd.makeEntitySetEmissionsCmd(e, o[2], o[3], o[4], o[4]))
					end
				end
			end)
		end), { quiet = true })
	end)

---------------------------------------------------------------------------
-- Probe 9: clearing private car traffic (plans/square_stress_test/PROBES_TRAFFIC.md). A private car
-- is not an entity of its own: it is a SIM_PERSON whose lastMoveMode is DRIVE (engine.d.tl:1086-1112,
-- modelIdCar / colorConfigCar). There is no destroy command for persons, and removing entities by
-- other means kills the sim thread (docs/findings.md, nodeConfigsToRemove). The one candidate is
-- api.cmd.debug.makeSimPersonSetStateCmd (cmd.d.tl:994-1003). Its state values come from the base
-- entity debug panel (gui/debug_panel/make_entity_debug_panel.tl:669-690): 0 pick new destinations,
-- 1 new path, 2 jump home, 3 jump shopping, 4 jump working, 5 go home, 6 go shopping, 7 go working.
-- Campaign mission 1 sends 2 ("jump home") to every SIM_PERSON through forEachEntityWithComponent
-- (mods/release/urbangames_campaign_mission_01/content/mission/mission_story.tl:2835-2840), so a
-- jumped driver should leave the road at once. All reads here, no writes except 9b/9c/9e's commands.

local CENSUS_CAP <const> = 200000      -- persons inspected per scan (the rest are only counted)
local DRIVER_PICK <const> = 5          -- persons per set-state probe
local DRIVER_RADIUS <const> = 400.0    -- street edges around the camera searched for moving drivers

local SET_STATE_LABELS <const> : {integer : string} = {
	[0] = "pick new destinations", [1] = "new path", [2] = "jump home", [3] = "jump shopping",
	[4] = "jump working", [5] = "go home", [6] = "go shopping", [7] = "go working",
}

local SIM_PERSON_FIELDS <const> : {string} = {
	"cargoType", "destinations", "moveModes", "travelTimes", "targetOrAtEntity", "lastNonResType",
	"lastMoveMode", "walkSpeed", "modelIdPerson", "colorConfigPerson", "modelIdCar", "colorConfigCar",
	"lastDestinationUpdate", "landUse2ReachableWalkDrive", "landUse2ReachableLines", "pickupTime", "happiness",
}

local function comp(e : integer, ct : Engine.ComponentType) : any
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

--- WALK / DRIVE / LINES for a MoveMode value, else its raw text.
local function moveModeName(v : any) : string
	local ok, mm = pcall(function() : any return api.type["enum"].MoveMode end)
	if ok and mm ~= nil then
		for _, n in ipairs({ "WALK", "DRIVE", "LINES" }) do
			local okN, val = pcall(function() : any return (mm as {string : any})[n] end)
			if okN and val ~= nil and val == v then return n end
		end
	end
	return tostring(v)
end

local function moveModeList(v : any) : string
	if type(v) ~= "table" then return tostring(v) end
	local parts : {string} = {}
	for _, m in ipairs(v as {any}) do parts[#parts + 1] = moveModeName(m) end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- Every field of a component: pairs when it is a table, else the known field names (userdata).
local function fieldDump(obj : any, known : {string}) : string
	if obj == nil then return "nil" end
	local parts : {string} = {}
	local okP = pcall(function()
		local keys : {any} = {}
		for k, _ in pairs(obj as {any : any}) do
			keys[#keys + 1] = k
			if #keys >= 60 then break end
		end
		table.sort(keys, function(a : any, b : any) : boolean return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			local v = (obj as {any : any})[k]
			local s = str(v)
			if type(v) == "table" and s == "{}" then
				-- a record (no array part): one level of its own fields
				local sub : {string} = {}
				for k2, v2 in pairs(v as {any : any}) do
					sub[#sub + 1] = tostring(k2) .. "=" .. str(v2)
					if #sub >= 12 then break end
				end
				if #sub > 0 then s = "{" .. table.concat(sub, ",") .. "}" end
			end
			parts[#parts + 1] = tostring(k) .. "=" .. s
		end
	end)
	if okP and #parts > 0 then return "(" .. type(obj) .. ") " .. table.concat(parts, " ") end
	parts = {}
	for _, k in ipairs(known) do
		local okF, v = pcall(function() : any return (obj as {string : any})[k] end)
		parts[#parts + 1] = k .. "=" .. (okF and str(v) or "?")
	end
	return "(" .. type(obj) .. ", known fields) " .. table.concat(parts, " ")
end

--- Calls fn for every SIM_PERSON; returns how it iterated (nil when it could not) and the count, or
--- nil and the errors. fn must not throw (it runs inside the engine's loop for forEachEntityWithComponent).
local function forEachSimPerson(fn : function(e : integer)) : string, integer, string
	local ct = api.type.ComponentType.SIM_PERSON
	local ok, list = pcall(api.engine.getEntitiesWithComponent, ct)
	if ok and list ~= nil then
		for _, e in ipairs(list as {integer}) do fn(e) end
		return "getEntitiesWithComponent", #(list as {integer}), nil
	end
	local errList = tostring(list)
	local n = 0
	local okF, errF : boolean, any = pcall(api.engine.forEachEntityWithComponent, function(e : integer)
		n = n + 1
		fn(e)
	end, ct)
	if okF then return "forEachEntityWithComponent (list threw: " .. errList .. ")", n, nil end
	return nil, n, "list: " .. errList .. " | forEach: " .. tostring(errF)
end

local function simPersonCount() : string
	local ok, n = pcall(api.engine.system.simPersonSystem.getCount)
	return ok and str(n) or ("error: " .. tostring(n))
end

local function listCount(ct : Engine.ComponentType) : string
	local ok, l = pcall(api.engine.getEntitiesWithComponent, ct)
	if ok and l ~= nil then return tostring(#(l as {integer})) end
	return "not iterable"
end

local function isDriveMode(sp : Engine.Component.SimPerson) : boolean
	return sp ~= nil and moveModeName(sp.lastMoveMode) == "DRIVE"
end

--- Driving a car right now: DRIVE, a MOVE_PATH, not seated in a vehicle.
local function isDriving(e : integer) : boolean
	local sp = comp(e, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
	return isDriveMode(sp) and comp(e, api.type.ComponentType.MOVE_PATH) ~= nil
		and comp(e, api.type.ComponentType.SIM_PERSON_AT_VEHICLE) == nil
end

local function movePathSummary(e : integer) : string
	local mp = comp(e, api.type.ComponentType.MOVE_PATH) as Engine.Component.MovePath
	if mp == nil then return "movePath=nil" end
	local ok, s = pcall(function() : string
		return string.format("movePath{state=%s edges=%s speed=%s blocked=%s}", str(mp.state),
			mp.path ~= nil and str(#mp.path.edges) or "?", mp.dyn ~= nil and str(mp.dyn.speed) or "?", str(mp.blocked))
	end)
	return ok and s or "movePath=(unreadable)"
end

add("p9_census", "9a SimPerson census",
	"Probe 9: list every SIM_PERSON (capped), count them by lastMoveMode and vehicle/path components, time the scan, dump one driver.",
	function()
		local name = "simperson_census"
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local CT = api.type.ComponentType
			local t0 = rt.nowUs()
			local scanned, atVehP, atVehE, withPath, driving, driveLand, errors = 0, 0, 0, 0, 0, 0, 0
			local byMode : {string : integer} = {}
			local firstDriver : integer = nil
			local how, total, err = forEachSimPerson(function(e : integer)
				if scanned >= CENSUS_CAP then return end
				scanned = scanned + 1
				local okE = pcall(function()
					local sp = api.engine.getComponent(e, CT.SIM_PERSON) as Engine.Component.SimPerson
					local mode = sp ~= nil and moveModeName(sp.lastMoveMode) or "nil"
					byMode[mode] = (byMode[mode] or 0) + 1
					local hasP = api.engine.getComponent(e, CT.SIM_PERSON_AT_VEHICLE) ~= nil
					if hasP then atVehP = atVehP + 1 end
					if api.engine.getComponent(e, CT.SIM_ENTITY_AT_VEHICLE) ~= nil then atVehE = atVehE + 1 end
					local hasPath = api.engine.getComponent(e, CT.MOVE_PATH) ~= nil
					if hasPath then withPath = withPath + 1 end
					if mode == "DRIVE" then
						if hasPath and not hasP then
							driving = driving + 1
							if firstDriver == nil then firstDriver = e end
						end
						if api.engine.getComponent(e, CT.LAND_VEHICLE) ~= nil then driveLand = driveLand + 1 end
					end
				end)
				if not okE then errors = errors + 1 end
			end)
			local ms = (rt.nowUs() - t0) / 1000
			local modes : {string} = {}
			for m, n in pairs(byMode) do modes[#modes + 1] = m .. "=" .. tostring(n) end
			table.sort(modes)
			if firstDriver ~= nil then
				rt.detail(string.format("[SQST] %s first driver e=%d SIM_PERSON: %s", name, firstDriver,
					fieldDump(comp(firstDriver, CT.SIM_PERSON), SIM_PERSON_FIELDS)))
				rt.detail(string.format("[SQST] %s first driver e=%d %s LAND_VEHICLE=%s MODEL_PERSON=%s SIM_ENTITY_MOVING=%s", name,
					firstDriver, movePathSummary(firstDriver), tostring(comp(firstDriver, CT.LAND_VEHICLE) ~= nil),
					tostring(comp(firstDriver, CT.MODEL_PERSON) ~= nil), fieldDump(comp(firstDriver, CT.SIM_ENTITY_MOVING), {})))
			end
			rt.probe(name, how ~= nil, string.format(
				"iter=%s total=%d scanned=%d (cap %d) scanMs=%.0f errors=%d getCount=%s byLastMoveMode={%s} SIM_PERSON_AT_VEHICLE=%d SIM_ENTITY_AT_VEHICLE=%d MOVE_PATH=%d drivingNow(DRIVE+MOVE_PATH-AT_VEHICLE)=%d DRIVE+LAND_VEHICLE=%d LAND_VEHICLE=%s TRANSPORT_VEHICLE=%s firstDriver=%s%s",
				how or "none", total, scanned, CENSUS_CAP, ms, errors, simPersonCount(), table.concat(modes, ","), atVehP, atVehE,
				withPath, driving, driveLand, listCount(CT.LAND_VEHICLE), listCount(CT.TRANSPORT_VEHICLE), str(firstDriver),
				err ~= nil and (" err: " .. err) or ""))
		end), { quiet = true })
	end)

--- Up to n persons driving now: first those on street edges near (x, y)
--- (simPersonSystem.getSimPersonsMovingForTransportNetwork per edge, system.d.tl:155), else any.
local function pickDrivers(x : number, y : number, n : integer) : {integer}, string
	local found : {integer} = {}
	local seen : {integer : boolean} = {}
	local edges, moving = 0, 0
	local okO, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), DRIVER_RADIUS, api.type.ComponentType.BASE_EDGE)
	if okO and list ~= nil then
		for _, edge in ipairs(list as {integer}) do
			if #found >= n then break end
			if comp(edge, api.type.ComponentType.BASE_EDGE_STREET) ~= nil then
				edges = edges + 1
				local okM, ps = pcall(api.engine.system.simPersonSystem.getSimPersonsMovingForTransportNetwork, edge)
				if okM and ps ~= nil then
					for _, p in ipairs(ps as {integer}) do
						moving = moving + 1
						if not seen[p] and #found < n and isDriving(p) then found[#found + 1] = p end
						seen[p] = true
					end
				end
			end
		end
	end
	local near = string.format("streetEdges(r=%.0fm)=%d movingOnThem=%d", DRIVER_RADIUS, edges, moving)
	if #found > 0 then return found, "near camera: " .. near end
	local scanned = 0
	local how = forEachSimPerson(function(e : integer)
		if #found >= n or scanned >= CENSUS_CAP then return end
		scanned = scanned + 1
		local ok, d = pcall(isDriving, e)
		if ok and d then found[#found + 1] = e end
	end)
	return found, string.format("anywhere (%s; scanned %d, %s)", near, scanned, how or "SIM_PERSON not iterable")
end

local function personState(e : integer) : string
	if not api.engine.entityExists(e) then return string.format("e=%d gone", e) end
	local CT = api.type.ComponentType
	local sp = comp(e, CT.SIM_PERSON) as Engine.Component.SimPerson
	local mode, target, modes = "nil", "?", "?"
	if sp ~= nil then
		mode, target, modes = moveModeName(sp.lastMoveMode), str(sp.targetOrAtEntity), moveModeList(sp.moveModes)
	end
	return string.format("e=%d mode=%s moveModes=%s target=%s %s moving=%s atBuilding=%s atVehicle=%s", e, mode, modes, target,
		movePathSummary(e), tostring(comp(e, CT.SIM_ENTITY_MOVING) ~= nil), tostring(comp(e, CT.SIM_ENTITY_AT_BUILDING) ~= nil),
		tostring(comp(e, CT.SIM_PERSON_AT_VEHICLE) ~= nil))
end

--- After-tally: still driving / with a MOVE_PATH / at a building / gone.
local function tally(list : {integer}) : string
	local drive, path, atB, gone = 0, 0, 0, 0
	for _, e in ipairs(list) do
		if not api.engine.entityExists(e) then
			gone = gone + 1
		else
			if isDriving(e) then drive = drive + 1 end
			if comp(e, api.type.ComponentType.MOVE_PATH) ~= nil then path = path + 1 end
			if comp(e, api.type.ComponentType.SIM_ENTITY_AT_BUILDING) ~= nil then atB = atB + 1 end
		end
	end
	return string.format("drivingNow=%d/%d movePath=%d atBuilding=%d gone=%d", drive, #list, path, atB, gone)
end

local function setStateProbe(state : integer)
	local name = "simperson_setstate_" .. tostring(state)
	local x, y = cameraOrFail(name)
	if x == nil then return end
	rt.enqueue(name, 1, guarded(name, function(_i : integer)
		local dbg = api.cmd.debug
		if dbg == nil or dbg.makeSimPersonSetStateCmd == nil then
			rt.probe(name, false, string.format("api.cmd.debug=%s makeSimPersonSetStateCmd=%s: not available in this state",
				tostring(dbg ~= nil), dbg ~= nil and tostring(dbg.makeSimPersonSetStateCmd ~= nil) or "n/a"))
			return
		end
		local picked, source = pickDrivers(x, y, DRIVER_PICK)
		if #picked == 0 then
			rt.probe(name, false, "no person driving a car found (" .. source .. "); needs a town with car traffic")
			return
		end
		for _, e in ipairs(picked) do rt.detail(string.format("[SQST] %s before: %s", name, personState(e))) end
		local answered, succeeded = 0, 0
		for _, e in ipairs(picked) do
			rt.send(name, dbg.makeSimPersonSetStateCmd(e, state), function(success : boolean, _d : any)
				answered = answered + 1
				if success then succeeded = succeeded + 1 end
			end)
		end
		local head = string.format("state=%d (%s) picked=%d from %s", state, SET_STATE_LABELS[state] or "?", #picked, source)
		local t2 = "?"
		rt.later(name .. ":2s", 2000, function()
			for _, e in ipairs(picked) do rt.detail(string.format("[SQST] %s +2s: %s", name, personState(e))) end
			t2 = tally(picked)
			rt.log(string.format("[SQST] %s +2s %s", name, t2))
		end)
		rt.later(name .. ":15s", 15000, function()
			for _, e in ipairs(picked) do rt.detail(string.format("[SQST] %s +15s: %s", name, personState(e))) end
			rt.probe(name, succeeded == #picked, string.format("%s callbacks=%d succeeded=%d | +2s %s | +15s %s",
				head, answered, succeeded, t2, tally(picked)))
		end)
	end), { quiet = true })
end

add("p9_jump_home", "9b Cars near camera: jump home",
	"Probe 9: makeSimPersonSetStateCmd(person, 2 = jump home) on 5 persons driving near the camera. Watch whether those cars vanish.",
	function() setStateProbe(2) end)
add("p9_new_path", "9c Cars near camera: new path",
	"Probe 9: makeSimPersonSetStateCmd(person, 1 = new path) on 5 persons driving near the camera.",
	function() setStateProbe(1) end)

local function buildingsNear(x : number, y : number) : {integer}, string
	for _, r in ipairs({ 100.0, 300.0, 1000.0 }) do
		local ok, l = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, api.type.ComponentType.TOWN_BUILDING)
		if ok and l ~= nil and #(l as {integer}) > 0 then return l as {integer}, string.format("octree TOWN_BUILDING r=%.0fm", r) end
	end
	local town = closestTown(x, y)
	if town == nil then return {}, "no town" end
	local list = api.engine.system.townBuildingSystem.getTown2BuildingMap()[town] or {}
	return list as {integer}, string.format("town map of %s (octree found none)", townName(town))
end

add("p9_capacity", "9d Person capacity dump",
	"Probe 9: read PERSON_CAPACITY (pathfindingPreference) of up to 3 town buildings nearest the camera. Read only.",
	function()
		local name = "person_capacity_dump"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local CT = api.type.ComponentType
			local list, source = buildingsNear(x, y)
			local parts : {string} = {}
			local read = 0
			for k = 1, math.min(3, #list) do
				local b = list[k]
				local tb = comp(b, CT.TOWN_BUILDING) as Engine.Component.TownBuilding
				local pcEntity = tb ~= nil and tb.personCapacity or b
				local pc = comp(pcEntity, CT.PERSON_CAPACITY) as Engine.Component.PersonCapacity
				if pc == nil and pcEntity ~= b then pcEntity, pc = b, comp(b, CT.PERSON_CAPACITY) as Engine.Component.PersonCapacity end
				if pc == nil then
					parts[#parts + 1] = string.format("[b=%d tb=%s no PERSON_CAPACITY]", b, tostring(tb ~= nil))
				else
					read = read + 1
					local pref = pc.pathfindingPreference
					local okD, persons = pcall(api.engine.system.simPersonSystem.getSimPersonsForDestination, pcEntity)
					parts[#parts + 1] = string.format("[b=%d pc=%d type=%s capacity=%s personNodes=%s vehicleNodes=%s persons=%s pref: %s disallowed=%s weight=%s]",
						b, pcEntity, str(pc.type), str(pc.capacity), pc.personNodes ~= nil and str(#pc.personNodes) or "?",
						pc.vehicleNodes ~= nil and str(#pc.vehicleNodes) or "?", okD and persons ~= nil and str(#(persons as {integer})) or "?",
						fieldDump(pref, { "destinationWeight", "disallowedMoveModes" }),
						pref ~= nil and moveModeList(pref.disallowedMoveModes) or "nil", pref ~= nil and str(pref.destinationWeight) or "nil")
					if read == 1 then rt.detail(string.format("[SQST] %s full PERSON_CAPACITY of pc=%d: %s", name, pcEntity,
						fieldDump(pc, { "type", "capacity", "personNodes", "vehicleNodes", "pathfindingPreference" }))) end
				end
			end
			rt.probe(name, read > 0, string.format("source=%s buildings=%d %s", source, #list, table.concat(parts, " ")))
		end), { quiet = true })
	end)

add("p9_new_dest", "9e Cars near camera: new destinations",
	"Probe 9: makeSimPersonSetStateCmd(person, 0 = pick new destinations) on 5 persons driving near the camera.",
	function() setStateProbe(0) end)


---------------------------------------------------------------------------
-- Probe 10: automatic bus lines (plans/square_stress_test/PROBES_BUSLINES.md): stops on existing
-- streets (10a, 10b), a road depot connected to a street (10c), and a line with one bus (10d). The
-- helpers (proposals, depot spots, depot lookup, bus model) live in stress_buslines.tl, shared with
-- the Traffic tab's Auto bus lines; its header has the citations.

local BUS_STOP_RADIUS <const> = 300.0     -- 10a/10c: street edges searched around the camera
local BUS_PAIR_RADIUS <const> = 900.0     -- 10b: wide enough for two edges 300-600 m apart
local BUS_PAIR_MIN <const> = 300.0
local BUS_PAIR_MAX <const> = 600.0
local BUS_PAIR_TRIES <const> = 20         -- first edges (nearest first) tried as the pair's first stop
local BUS_DEPOT_EDGES <const> = 3         -- 10c: nearest edges whose depot spots are tried
local BUS_FIND_RADIUS <const> = 1500.0    -- 10d fallback: stops and depots near the camera

add("p10_stop", "10a Bus stop on nearest street",
	"Probe 10: replace the street edge nearest the camera by a copy with a bus stop (base small stop) at its middle, right side. Logs the new STATION_GROUP.",
	function()
		local name = "bus_stop_on_street"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local cands, info = bl.streetEdgeCandidates(x, y, BUS_STOP_RADIUS)
			if #cands == 0 then
				rt.probe(name, false, "no eligible street edge near the camera: " .. info)
				return
			end
			bl.placeStop(name, cands[1], function(ok : boolean, details : string, _group : integer)
				rt.probe(name, ok, info .. " | " .. details)
			end)
		end), { quiet = true })
	end)

add("p10_stop_pair", "10b Two bus stops 300-600 m apart",
	"Probe 10: two stops (as 10a) on two street edges 300-600 m apart near the camera; keeps their station groups for 10d.",
	function()
		local name = "bus_stop_pair"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local cands, info = bl.streetEdgeCandidates(x, y, BUS_PAIR_RADIUS)
			local a, b = bl.pickEdgePair(cands, BUS_PAIR_MIN, BUS_PAIR_MAX, {}, 0, BUS_PAIR_TRIES)
			if a == nil then
				rt.probe(name, false, string.format("no two eligible street edges %.0f-%.0f m apart: %s", BUS_PAIR_MIN, BUS_PAIR_MAX, info))
				return
			end
			local span = string.format("%s pair distance=%.0fm", info, bl.dist2(a.mid, b.mid))
			bl.placeStop(name .. ":1", a, function(ok1 : boolean, d1 : string, g1 : integer)
				if not api.engine.entityExists(b.id) then
					rt.probe(name, false, string.format("%s | stop1 %s: %s | stop2 edge %d is gone", span, ok1 and "ok" or "fail", d1, b.id))
					return
				end
				bl.placeStop(name .. ":2", b, function(ok2 : boolean, d2 : string, g2 : integer)
					local both = ok1 and ok2 and g1 ~= nil and g2 ~= nil and g1 ~= g2
					if both then bl.lastGroups = { g1, g2 } end
					rt.probe(name, both, string.format("%s stationGroups=%s,%s | stop1: %s | stop2: %s", span, str(g1), str(g2), d1, d2))
				end)
			end)
		end), { quiet = true })
	end)

add("p10_depot", "10c Road depot by nearest street",
	"Probe 10: build the base road depot beside one of the 3 street edges nearest the camera (spots along the edge, both sides, 30/45/60 m off; each pre-checked), then split the edge and connect the entrance with a short street.",
	function()
		local name = "road_depot_here"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local cands, info = bl.streetEdgeCandidates(x, y, BUS_STOP_RADIUS)
			if #cands == 0 then
				rt.probe(name, false, "no eligible street edge near the camera: " .. info)
				return
			end
			local edges : {SquareStressEdgeGeo} = {}
			for i = 1, math.min(BUS_DEPOT_EDGES, #cands) do edges[i] = cands[i] end
			local _, nDepots = bl.listSet(api.type.ComponentType.VEHICLE_DEPOT)
			bl.buildDepot(name, edges, x, y, function(ok : boolean, details : string, depot : integer)
				if depot ~= nil then bl.lastDepot = depot end
				local _, nAfter = bl.listSet(api.type.ComponentType.VEHICLE_DEPOT)
				rt.probe(name, ok, string.format("%s | %s | depot=%s VEHICLE_DEPOT %d->%d", info, details, str(depot), nDepots, nAfter))
			end)
		end), { quiet = true })
	end)

add("p10_line", "10d Bus line + 1 bus (10b stops, 10c depot)",
	"Probe 10: makeLineCreateCmd over 10b's two stops (else the two newest stops near the camera), buy the newest bus on sale at 10c's depot (else the nearest road depot), then makeVehicleSetLineCmd.",
	function()
		local name = "bus_line_from_pair"
		local x, y = cameraOrFail(name)
		if x == nil then return end
		rt.enqueue(name, 1, guarded(name, function(_i : integer)
			local groups, gSrc = bl.lastGroups, "10b"
			local valid = #groups == 2
			for _, g in ipairs(groups) do
				if not api.engine.entityExists(g) then valid = false end
			end
			if not valid then
				local near = bl.stationGroupsNear(x, y, BUS_FIND_RADIUS)
				groups, gSrc = { near[1], near[2] }, string.format("newest near camera (%d groups within %.0fm)", #near, BUS_FIND_RADIUS)
			end
			local depot, dSrc = bl.lastDepot, "10c"
			if depot == nil or not api.engine.entityExists(depot) then
				local d, dist, dInfo = bl.nearestRoadDepot(x, y, BUS_FIND_RADIUS)
				depot, dSrc = d, (dist ~= nil and string.format("nearest road depot (%.0fm)", dist) or "none") .. " " .. dInfo
			end
			local head = string.format("groups=%s (%s) depot=%s (%s)", str(groups), gSrc, str(depot), dSrc)
			if groups[1] == nil or groups[2] == nil or depot == nil then
				rt.probe(name, false, head .. ": needs two stops and a road depot (run 10b and 10c first)")
				return
			end
			local modelId, modelInfo = bl.pickBusModel()
			head = head .. " " .. modelInfo
			if modelId == nil then
				rt.probe(name, false, head .. ": no bus model on sale this year")
				return
			end
			bl.createLine(name, groups, function(lineE : integer, lineInfo : string)
				if lineE == nil then
					rt.probe(name, false, string.format("%s | %s", head, lineInfo))
					return
				end
				local b0 = rt.balance()
				rt.send(name .. ":buy", api.cmd.makeVehicleBuyCmd(rt.player(), depot, bl.busConfig(modelId)), function(okB : boolean, dataB : any)
					local v = okB and (dataB as VehicleBuyCommandData).resultVehicleEntity or nil
					if v == nil then
						rt.probe(name, false, string.format("%s | %s | buy success=%s balance=%s", head, lineInfo, tostring(okB), logic.formatMoney(b0)))
						return
					end
					rt.send(name .. ":setLine", api.cmd.makeVehicleSetLineCmd(v, lineE, 0), function(okS : boolean, _d2 : any)
						rt.later(name .. ":check", 5000, function()
							local okV, lv = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, lineE)
							local bd, bdInfo = bl.bestDepotForLine(lineE, x, y)
							local tv = comp(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
							rt.probe(name, okS, string.format(
								"%s | %s vehicle=%d setLine=%s +5s: lineVehicles=%s vehicleState=%s %s (sameDepot=%s) balance %s->%s",
								head, lineInfo, v, tostring(okS), okV and str(#(lv as {integer})) or "?", tv ~= nil and str(tv.state) or "?",
								bdInfo, tostring(bd == depot), logic.formatMoney(b0), logic.formatMoney(rt.balance())))
						end)
					end)
				end)
			end)
		end), { quiet = true })
	end)

---------------------------------------------------------------------------
-- Probe 11 "Flow" (read only, plans/square_stress_test/FLOW.md): its own module (this file's main chunk
-- is close to the 200-locals limit, docs/findings.md); its buttons go after probe 10's.
local flowProbes = ug_require "square_stress_test::/stress/gui/stress_probes_flow.tl" as SquareStressFlowProbes
flowProbes.addTo(probes.list)

return probes
