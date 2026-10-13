-- Stress Test Towns tab actions (PLAN.md Phase 2): grow towns, spawn towns, freeze development, and
-- the readout. Built on the probe results in docs/findings.md "Stress Test probes":
--   * grow: makeTownUpdateSizeCmd(town, sizeFactors x f, updateAllBuildings = true) works almost at once
--     (x10: 58 -> 343 buildings in 5 s). One call builds only ~250-350 buildings, but re-sending the
--     same factor keeps building (third run: 889 -> 2314 over 5 calls), hence the build-out passes.
--   * spawn: api.engine.mapgen.createTowns(seed, {one Map.Town}) -> makeTownCreateCmd(toAdd), with the
--     TownInfo's initialLandUseCapacities overwritten (1600 was kept as given). createTowns' toRemove
--     lists all existing towns (it treats its input as the whole town list): ignored, never destroyed.
--     Several creates in flight slowed to 10-12 s and raced, so every town command here runs in the
--     queue's serial lane: one command in flight, the next step after its callback (stress_logic.tick).
--   * makeTownDevelopAtCmd added no streets (probe 3): no "Develop now" button.
-- All commands are sent from queue steps (rt.tick, react.onStep, Main Thread); camera reads happen in
-- onClick (GUI main thread). Every action ends with one "[SQST] action=... count=... ms=..." line
-- (stress_logic.doneLine); per-town details go to stdout.txt only (rt.detail).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones
local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl" as SquareStressNodeCfg

local towns : SquareStressTowns = {
	ui = { growTarget = 1, factor = 1, passes = 1, count = 1, size = 2, placement = 1, connect = false,
		gridLayout = 1, gridSpacing = 2, gridSize = 2, gridCentre = 1, gridConnect = 2, gridStreets = 1,
		removeTarget = 1 },
	testTowns = {},
}

local MAP_MARGIN <const> = 1000.0     -- spread over map: keep new town centres this far from the edge
local SHORE_PROBE <const> = 300.0     -- terrain check: these offsets around a centre must be land too

---------------------------------------------------------------------------
-- Reads

local function townList() : {integer}
	return api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN) as {integer}
end

local function townComp(town : integer) : Engine.Component.Town
	return api.engine.getComponent(town, api.type.ComponentType.TOWN) as Engine.Component.Town
end

local function townName(e : integer) : string
	local ok, n = pcall(api.engine.util.getEntityName, e)
	return ok and tostring(n) or "?"
end

local function townBuildings(town : integer) : integer
	local list = api.engine.system.townBuildingSystem.getTown2BuildingMap()[town]
	return list ~= nil and #list or 0
end

local function townCaps(town : integer) : {integer}
	local ok, m = pcall(api.engine.system.townBuildingSystem.getTown2personCapacitiesMap)
	if not ok or m == nil then return nil end
	return m[town]
end

--- A town's population: its residential person capacity (as the game counts it: company_util.computeWorldPopulation,
--- the town window), nil when unreadable.
local function townPop(town : integer) : integer
	local c = townCaps(town)
	local ok, p = pcall(function() : integer return c ~= nil and c[1] or nil end)
	return ok and p ~= nil and math.floor(p) or nil
end

local function townSummary(town : integer) : string
	local tc = townComp(town)
	return string.format("town=%d name=%s initCaps=%s sizeFactors=%s buildings=%d personCaps=%s",
		town, townName(town), logic.listText(tc.initialLandUseCapacities), logic.listText(tc.sizeFactors),
		townBuildings(town), logic.listText(townCaps(town)))
end

--- Every town with its position (Map.Town pos), the map editor's way of listing towns
--- (base gui/map_editor/map_editor.tl:2492; api engine.d.tl:1762). Second result: the Map.Towns by id.
local function townPositions() : {SquareStressTownPos}, {integer : GameMap.Town}
	local out : {SquareStressTownPos} = {}
	local byId : {integer : GameMap.Town} = {}
	local ok, map = pcall(api.engine.terrain.makeMapFromGame, false, true, false, false)
	if not ok or map == nil then
		rt.log("[SQST] makeMapFromGame failed: " .. tostring(map) .. " (town positions unknown)")
		return out, byId
	end
	for _, t in ipairs((map as GameMap).towns) do
		if t.existing ~= nil and t.existing >= 0 then
			out[#out + 1] = { id = t.existing, x = t.pos.x, y = t.pos.y }
			byId[t.existing] = t
		end
	end
	return out, byId
end

local function closestTown(x : number, y : number) : integer
	local t = api.engine.util.town.getClosestTown(api.type.Vec3f.new(x, y, 0))
	if t == nil or t < 0 then return nil end
	return t
end

--- Terrain check for a town centre: on the map and on land, also SHORE_PROBE metres around it
--- (api.engine.terrain.isValidCoordinate / isOnWater, api/tealdef/api/engine.d.tl:1729-1746).
local function landOk(x : number, y : number) : boolean, string
	local offsets : {{number}} = { { 0, 0 }, { SHORE_PROBE, 0 }, { -SHORE_PROBE, 0 }, { 0, SHORE_PROBE }, { 0, -SHORE_PROBE } }
	for _, o in ipairs(offsets) do
		local p = api.type.Vec2f.new(x + o[1], y + o[2])
		if not api.engine.terrain.isValidCoordinate(p) then return false, "edge" end
		if api.engine.terrain.isOnWater(p) then return false, "water" end
	end
	return true, nil
end

---------------------------------------------------------------------------
-- Grow

--- Grows the towns of ui.growTarget (or `given`, its job `jobName`; the Showcases use towns.densify) by
--- factor, then re-sends the same factors for the build-out passes.
function towns.grow(factor : number, passes? : integer, given? : {integer}, jobName? : string)
	local name = jobName or (factor ~= nil and ("grow_x" .. tostring(factor)) or "grow_reset")
	local np = (factor ~= nil and passes ~= nil and passes > 1) and math.floor(passes) or 1
	local list : {integer}
	if given ~= nil then
		list = given
	elseif towns.ui.growTarget == 2 then
		local x, y = rt.camera()
		local t = closestTown(x, y)
		if t == nil then
			rt.warn("No town", "There is no town near the camera.")
			return
		end
		list = { t }
	else
		list = townList()
	end
	if #list == 0 then
		rt.warn("No towns", "There are no towns on the map.")
		return
	end
	local total = #list * np
	local stopped : {integer : boolean} = {}      -- town index -> build-out ended early
	local firstB : {integer : integer} = {}       -- town index -> buildings before pass 1
	local lastB : {integer : integer} = {}        -- town index -> buildings after its last pass
	local sentN, early = 0, 0
	local function finishIfLast(i : integer)
		if i ~= total then return end
		local b0, b1 = 0, 0
		for k, b in pairs(firstB) do
			b0 = b0 + b
			b1 = b1 + (lastB[k] or b)
		end
		rt.log(string.format("[SQST] %s summary towns=%d passes=%d sent=%d stoppedEarly=%d buildings %d->%d", name,
			#list, np, sentN, early, b0, b1))
	end
	rt.enqueue(name, total, function(i : integer, job : SquareStressJob)
		local k, pass = logic.passStep(i, np)
		local town = list[k]
		if stopped[k] or not api.engine.entityExists(town) then
			logic.resume(job)
			finishIfLast(i)
			return
		end
		local tc = townComp(town)
		local before = logic.listText(tc.sizeFactors)
		local buildings0 = townBuildings(town)
		if firstB[k] == nil then firstB[k] = buildings0 end
		local factors, note = logic.growPlan(tc.sizeFactors, factor, pass)
		local t0 = rt.nowUs()
		sentN = sentN + 1
		rt.send(name, api.cmd.makeTownUpdateSizeCmd(town, factors, true), function(success : boolean, _d : any)
			local buildings1 = townBuildings(town)
			lastB[k] = buildings1
			local stopText = ""
			if pass < np and (not success or not logic.passContinues(buildings0, buildings1)) then
				stopped[k] = true
				early = early + 1
				stopText = string.format(" build-out done after pass %d (+%d < %d)", pass, buildings1 - buildings0,
					logic.MIN_PASS_GAIN)
			end
			rt.detail(string.format("[SQST] %s %d/%d pass %d/%d town=%d name=%s success=%s ms=%.0f sizeFactors %s->%s%s buildings %d->%d (+%d)%s",
				name, i, total, pass, np, town, townName(town), tostring(success), (rt.nowUs() - t0) / 1000, before,
				logic.listText(factors), note, buildings0, buildings1, buildings1 - buildings0, stopText))
			logic.resume(job)
			finishIfLast(i)
		end)
	end, { serial = true, label = factor ~= nil and string.format(np > 1 and "Growing x%g, %d passes" or "Growing x%g", factor, np)
		or "Resetting size" })
end

--- The Factor choice as a factor (nil = reset to x1, the choice after the last factor).
function towns.selectedFactor() : number
	return logic.GROW_FACTORS[towns.ui.factor] as number
end

--- The Passes choice as a pass count (1 when unset).
function towns.selectedPasses() : integer
	return logic.GROW_PASSES[towns.ui.passes] or 1
end

function towns.growSelected()
	towns.grow(towns.selectedFactor(), towns.selectedPasses())
end

function towns.growLabel() : string
	return logic.growLabel(towns.ui.growTarget == 2, towns.selectedFactor(), towns.selectedPasses())
end

---------------------------------------------------------------------------
-- Spawn

function towns.spawnLabel() : string
	local size = logic.TOWN_SIZES[towns.ui.size] or logic.TOWN_SIZES[1]
	return logic.spawnLabel(logic.SPAWN_COUNTS[towns.ui.count] or 1, size.label)
end

--- Up to n town centres: placeRelaxed over PLACE_STEPS (strict first, then less distance to other
--- towns and more candidates), the terrain check (map edge, water) always strict. Second result: log text.
local function spawnPositions(n : integer, size : SquareStressTownSize, near : boolean, cx : number, cy : number,
		existing : {SquareStressTownPos}) : {{number}}, string
	local exist : {{number}} = {}
	for i, t in ipairs(existing) do exist[i] = { t.x, t.y } end
	local function ok(x : number, y : number) : boolean, string
		local okL, good, why = pcall(landOk, x, y)
		if not okL then return false, "error" end
		return good, why
	end
	if near then
		local placed, tried = logic.placeRelaxed(n, exist, size.spacing, function(step : SquareStressPlaceStep, minDist : number) : {{number}}
			return logic.spiralPoints(cx, cy, math.floor((n * 6 + 10) * step.widen), minDist)
		end, ok, false)
		return placed, string.format("near camera %.0f,%.0f %s", cx, cy, logic.placementText(tried))
	end
	local box = api.engine.terrain.getBoundingBox()
	local coarse = logic.spreadSpacing(box.min.x, box.min.y, box.max.x, box.max.y, n, MAP_MARGIN, size.spacing)
	local placed, tried = logic.placeRelaxed(n, exist, size.spacing, function(step : SquareStressPlaceStep, minDist : number) : {{number}}
		return logic.mapGrid(box.min.x, box.min.y, box.max.x, box.max.y, step.fine and minDist or coarse, MAP_MARGIN)
	end, ok, true)
	return placed, string.format("spread map=%.0f..%.0f,%.0f..%.0f coarse grid=%.0fm %s",
		box.min.x, box.max.x, box.min.y, box.max.y, coarse, logic.placementText(tried))
end

--- Road links between pairs of towns: one makeTownConnectWithIndustriesCmd per pair, keep = true
--- (false would remove existing streets, cmd.d.tl:813-819). The connection indices come from
--- api.engine.mapgen.getDefaultTownConnections over the two Map.Towns (as the map editor's "Propose
--- Default Connections", map_editor.tl:2544), so the engine's own index convention is used.
--- makePairs runs when the job starts (the new towns are listed by then) and returns entity pairs;
--- total is the job's step count (at least the number of pairs; extra steps do nothing).
local function connectTowns(name : string, total : integer, makePairs : function(all : {SquareStressTownPos}) : {{integer}})
	local pairs_ : {{integer}} = nil
	local byId : {integer : GameMap.Town} = nil
	rt.enqueue(name, total, function(i : integer, job : SquareStressJob)
		if i == 1 then
			local all : {SquareStressTownPos}
			all, byId = townPositions()
			pairs_ = makePairs(all)
		end
		local pair = pairs_[i]
		if pair == nil then
			logic.resume(job)
			return
		end
		local a, b = byId[pair[1]], byId[pair[2]]
		if a == nil or b == nil then
			rt.log(string.format("[SQST] %s %s - %s: town position unknown; skipped", name, townName(pair[1]), townName(pair[2])))
			logic.resume(job)
			return
		end
		local conns = api.engine.mapgen.getDefaultTownConnections({ a, b })
		if conns == nil or #conns == 0 then
			rt.log(string.format("[SQST] %s %s - %s: getDefaultTownConnections returned no connection; skipped",
				name, townName(pair[1]), townName(pair[2])))
			logic.resume(job)
			return
		end
		local t0 = rt.nowUs()
		rt.send(name, api.cmd.makeTownConnectWithIndustriesCmd({ pair[1], pair[2] }, conns, true), function(success : boolean, _d : any)
			logic.resume(job)
			rt.detail(string.format("[SQST] %s %d/%d %s - %s connections=%s success=%s ms=%.0f", name, i, total,
				townName(pair[1]), townName(pair[2]), logic.listText(conns), tostring(success), (rt.nowUs() - t0) / 1000))
		end)
	end, { serial = true, label = "Connecting towns" })
end

function towns.spawn()
	local n = logic.SPAWN_COUNTS[towns.ui.count] or 1
	local size = logic.TOWN_SIZES[towns.ui.size] or logic.TOWN_SIZES[1]
	local near = towns.ui.placement ~= 2
	local connect = towns.ui.connect
	local cx, cy = 0.0, 0.0
	if near then cx, cy = rt.camera() end
	local name = string.format("spawn_%s", size.label:lower())
	local positions : {{number}} = {}
	local firstNumber = 1
	local created : {integer} = {}
	local failed = 0

	local function finishBatch()
		rt.log(string.format("[SQST] %s summary requested=%d placed=%d created=%d failed=%d caps=%d", name, n, #positions,
			#created, failed, size.caps))
		if connect and #created > 0 then
			connectTowns("connect_towns", #created, function(all : {SquareStressTownPos}) : {{integer}}
				local newPos : {SquareStressTownPos} = {}
				for _, t in ipairs(all) do
					for _, c in ipairs(created) do
						if c == t.id then newPos[#newPos + 1] = t end
					end
				end
				return logic.nearestPairs(newPos, all)
			end)
		end
	end

	rt.enqueue(name, n, function(i : integer, job : SquareStressJob)
		if i == 1 then
			-- Positions are chosen when the batch starts (after any earlier serial job), so towns made by
			-- an earlier batch count as existing.
			local existing = townPositions()
			local names : {string} = {}
			for _, t in ipairs(townList()) do names[#names + 1] = townName(t) end
			firstNumber = logic.nextTownNumber(names)
			local info : string
			positions, info = spawnPositions(n, size, near, cx, cy, existing)
			-- Count first: the window shows only the first LOG_LINE_MAX characters (stdout.txt the rest).
			rt.log(string.format("[SQST] %s placement: %d of %d positions, %s", name, #positions, n, info))
		end
		local p = positions[i]
		if p == nil then
			logic.resume(job)
			if i == n then finishBatch() end
			return
		end
		local before : {integer : boolean} = {}
		for _, e in ipairs(townList()) do before[e] = true end
		local t = api.type.Map.Town.new()
		t.pos = api.type.Vec2f.new(p[1], p[2])
		t.name = string.format("SQST Town %d", firstNumber + i - 1)
		t.sizeFactors = { 1, 1, 1 }
		local res = api.engine.mapgen.createTowns("sqst" .. tostring(firstNumber + i - 1), { t })
		if #res.toAdd == 0 then
			failed = failed + 1
			rt.log(string.format("[SQST] %s %s: createTowns returned nothing to add", name, t.name))
			logic.resume(job)
			if i == n then finishBatch() end
			return
		end
		local ti = res.toAdd[1]
		local infoCaps = logic.listText(ti.initialLandUseCapacities)
		ti.initialLandUseCapacities = { size.caps, size.caps, size.caps }
		local t0 = rt.nowUs()
		rt.send(name, api.cmd.makeTownCreateCmd({ ti }), function(success : boolean, _d : any, resultEntities : {{integer}})
			local ms = (rt.nowUs() - t0) / 1000
			local function report()
				local new : integer = nil
				for _, re in ipairs(resultEntities or {}) do
					local e = re[1]
					if e ~= nil and not before[e] and api.engine.entityExists(e)
							and api.engine.getComponent(e, api.type.ComponentType.TOWN) ~= nil then
						new = e
						break
					end
				end
				if new == nil then
					for _, e in ipairs(townList()) do
						if not before[e] then new = e break end
					end
				end
				if success and new ~= nil then created[#created + 1] = new else failed = failed + 1 end
				rt.detail(string.format("[SQST] %s %d/%d %s pos=%.0f,%.0f success=%s ms=%.0f createTowns caps=%s sent caps=%d results=%d %s",
					name, i, n, t.name, p[1], p[2], tostring(success), ms, infoCaps, size.caps, #(resultEntities or {}),
					new ~= nil and townSummary(new) or "new town not found"))
				logic.resume(job)
				if i == n then finishBatch() end
			end
			local found = false
			for _, e in ipairs(townList()) do
				if not before[e] then found = true break end
			end
			if found or not success then
				report()
			else
				-- Not listed yet: look once more a second later before the next town starts.
				rt.later(name .. ":recheck", 1000, report)
			end
		end)
	end, { serial = true, label = string.format("Spawning %s towns", size.label:lower()) })
end

---------------------------------------------------------------------------
-- Test grid: identical towns at exact, equally spaced positions (for traffic tests on a flat map).
-- Same flow as spawn (createTowns -> makeTownCreateCmd, serial), but the positions are fixed: the
-- grid is all or nothing (one point on water or off the map cancels it, nothing relaxes), every town
-- gets the same seed, capacities and street angle 0 (axis-aligned with the grid), and the created
-- towns' real centres are logged against the requested ones afterwards.

local GRID_NEAR_WARN <const> = 0.5  -- warn about existing towns closer than spacing x this to a grid point

-- "Wide grid" streets (Streets choice): before a grid town is created, our street grid construction
-- (infrastructure/street_construction/square_stress_test_town_grid.con.lua, geometry
-- stress/stress_grid_streets.lua) is built at its centre: large 4-lane town streets, every node
-- free, so the new town lines them with houses. Sent like the Stress Test's road depot
-- (stress_buslines depotProposal: constructionsToAdd, no context), rotation 0 with +0 entries.
local GRID_STREETS_CON <const> = "infrastructure/street_construction/square_stress_test_town_grid.con"
local gridStreetsName : string = nil   -- "" = not found

local function gridStreetsCon() : string
	if gridStreetsName == nil then
		gridStreetsName = ""
		for _, n in ipairs({ "square_stress_test::/" .. GRID_STREETS_CON, "square_stress_test::" .. GRID_STREETS_CON, GRID_STREETS_CON }) do
			local ok, id = pcall(function() : integer return api.res.constructionRep.find(n) end)
			if ok and type(id) == "number" and id >= 0 then
				gridStreetsName = n
				break
			end
		end
	end
	return gridStreetsName ~= "" and gridStreetsName or nil
end

--- Builds the street grid at (x, y), then calls onDone whatever the outcome (the town is created
--- either way; a refused grid is logged).
--- Street edges (BASE_EDGE with BASE_EDGE_STREET) the octree places within r of (x, y): by one point of
--- the edge, most likely its middle, not by its extent (docs/findings/roads.md "Octree edge search matches
--- the edge's position"). The grid lock's lockR (gridEntity) holds every grid edge's middle with room to
--- spare (half x 1.5 + 100 m; the stubs' middles lie at half x 1.41 + 21 m).
local function streetEdgesNear(x : number, y : number, r : number) : {integer : boolean}
	local out : {integer : boolean} = {}
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, api.type.ComponentType.BASE_EDGE)
	if not ok or list == nil then return out end
	for _, e in ipairs(list as {integer}) do
		local okS, st : boolean, any = pcall(api.engine.getComponent, e, api.type.ComponentType.BASE_EDGE_STREET)
		if okS and st ~= nil then out[e] = true end
	end
	return out
end

--- Whether edge (node = false) or node e belongs to a construction (a junction's frozen streets).
local function inConstruction(e : integer, node : boolean) : boolean
	local sys = api.engine.system.streetConnectorSystem
	local ok, con = pcall(function() : integer
		if node then return sys.getConstructionEntityForNode(e) end
		return sys.getConstructionEntityForEdge(e)
	end)
	return ok and con ~= nil and con >= 0
end

--- One proposal that swaps each edge for a copy with roadDevelopmentLocked = true. The nodes stay;
--- every node at those edges gets its lane connections and crosswalks re-pointed at the copies
--- (rt.nodeConfigEntry, remove + add; light phases keep their indices: nothing is dropped). Edges read
--- fresh: gone, already locked, or carrying edge objects (a stop: its object would not follow the copy)
--- are left out, as are a construction's edges and edges at its nodes. nil when none is left; second
--- result: how many edges are in it, third: which.
local function lockProposal(list : {integer}) : SimpleProposal, integer, {integer}
	local CT = api.type.ComponentType
	local newIds : {integer : integer} = {}
	local adds : {Proposal.SegmentAndEntity} = {}
	local removes : {integer} = {}
	local nodes : {integer : boolean} = {}
	for _, e in ipairs(list) do
		-- a protected read: an edge removed since the scan (town growth) is left out
		local okB, beAny : boolean, any = pcall(api.engine.getComponent, e, CT.BASE_EDGE)
		local be = okB and beAny as Engine.Component.BaseEdge or nil
		local st = be ~= nil and api.engine.getComponent(e, CT.BASE_EDGE_STREET) as Engine.Component.BaseEdgeStreet or nil
		local okO, nObj = pcall(function() : integer return be ~= nil and be.objects ~= nil and #be.objects or 0 end)
		-- never a construction's edge, or one ending at a construction's node (a junction's frozen
		-- streets: lockGrid takes every new edge near the grid, unfiltered)
		local free = be ~= nil and not inConstruction(e, false) and not inConstruction(be.node0, true) and not inConstruction(be.node1, true)
		if be ~= nil and st ~= nil and free and be.roadDevelopmentLocked ~= true and (not okO or nObj == 0) then
			local seg = api.type.SegmentAndEntity.new()
			seg.entity = -(#adds + 1)
			seg.type = 0
			seg.comp = be
			seg.comp.roadDevelopmentLocked = true
			seg.streetEdge = st
			adds[#adds + 1] = seg
			removes[#removes + 1] = e
			newIds[e] = seg.entity
			nodes[be.node0] = true
			nodes[be.node1] = true
		end
	end
	if #adds == 0 then return nil, 0, {} end
	local cfgRemove : {integer} = {}
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local sorted : {integer} = {}
	for n in pairs(nodes) do sorted[#sorted + 1] = n end
	table.sort(sorted)
	for _, n in ipairs(sorted) do
		local entry = rt.nodeConfigEntry(n, newIds, nil)
		if entry ~= nil then
			cfgRemove[#cfgRemove + 1] = n
			cfgAdd[#cfgAdd + 1] = entry
		end
	end
	-- a node without a config (script-made, e.g. a Junction test link's) gets a fresh one (nc.complete)
	nc.complete(adds, removes, cfgAdd, cfgRemove)
	local p = api.type.SimpleProposal.new()
	p.streetProposal.edgesToAdd = adds
	p.streetProposal.edgesToRemove = removes
	p.streetProposal.nodeConfigsToRemove = cfgRemove
	p.streetProposal.nodeConfigsToAdd = cfgAdd
	return p, #adds, removes
end

--- Lock counts of one lockEdges run.
local record LockResult
	asked : integer               -- edges asked for
	locked : integer              -- edges swapped for locked copies
	failed : integer              -- edges of batches refused twice (or unbuildable)
	batches : integer             -- proposals sent
	refused : integer             -- refusals (each retried once)
	by : {integer : {integer}}    -- owner key -> { locked, failed, refused, batches } (lockEdges' owner map)
end

--- Locks the edges of `list` in batches of LOCK_BATCH, one proposal in flight (callback chained; call
--- it inside a serial step). Each batch is built from fresh reads when it is sent (an earlier batch
--- swapped its neighbours' edges, so its node configs must be read after that). A refused batch is rebuilt
--- and sent once more LOCK_RETRY_MS later (a node whose light write is still pending refuses a street
--- proposal, docs/findings/roads.md); refused again, its edges count as failed. done(result) at the end.
local function lockEdges(name : string, label : string, list : {integer}, done : function(r : LockResult), owner? : {integer : integer})
	local res : LockResult = { asked = #list, locked = 0, failed = 0, batches = 0, refused = 0, by = {} }
	local batches = logic.chunk(list, logic.LOCK_BATCH)
	local k = 0
	local nextBatch : function()
	-- per owner (owner: edge -> key, e.g. a town of a lock pass across towns): what happened to its edges
	local function tally(edgesIn : {integer}, slot : integer, perEdge : boolean)
		if owner == nil then return end
		local seen : {integer : boolean} = {}
		for _, e in ipairs(edgesIn) do
			local key = owner[e]
			if key ~= nil and (perEdge or not seen[key]) then
				seen[key] = true
				local c = res.by[key]
				if c == nil then
					c = { 0, 0, 0, 0 }
					res.by[key] = c
				end
				c[slot] = c[slot] + 1
			end
		end
	end
	local function send(batch : {integer}, try : integer)
		local okP, p, n, inIt = pcall(lockProposal, batch)
		if not okP then
			rt.log(string.format("[SQST] %s %s: lock batch error: %s", name, label, tostring(p)))
			res.failed = res.failed + #batch
			tally(batch, 2, true)
			nextBatch()
			return
		end
		if p == nil then nextBatch() return end
		res.batches = res.batches + 1
		tally(inIt, 4, false)
		local t0 = rt.nowUs()
		local okS, err : boolean, any = pcall(function()
			rt.send(name .. ":lock", api.cmd.makeWorldBuildProposalCmd(p as SimpleProposal, nil, false, true), function(success : boolean, _data : any)
				rt.detail(string.format("[SQST] %s %s lock batch %d/%d edges=%d try=%d success=%s ms=%.0f", name, label, k, #batches, n, try,
					tostring(success), (rt.nowUs() - t0) / 1000))
				if success then
					res.locked = res.locked + n
					tally(inIt, 1, true)
					nextBatch()
				elseif try < 2 then
					res.refused = res.refused + 1
					tally(inIt, 3, false)
					rt.log(string.format("[SQST] %s %s: lock batch %d (%d edges) refused; sent again in %.0f s", name, label, k, n,
						logic.LOCK_RETRY_MS / 1000))
					rt.later(name .. ":relock", logic.LOCK_RETRY_MS, function() send(batch, try + 1) end)
				else
					res.refused = res.refused + 1
					res.failed = res.failed + n
					tally(inIt, 3, false)
					tally(inIt, 2, true)
					rt.log(string.format("[SQST] %s %s: lock batch %d (%d edges) refused twice; left unlocked", name, label, k, n))
					nextBatch()
				end
			end)
		end)
		if not okS then
			rt.log(string.format("[SQST] %s %s: lock batch failed: %s", name, label, tostring(err)))
			res.failed = res.failed + n
			tally(inIt, 2, true)
			nextBatch()
		end
	end
	nextBatch = function()
		k = k + 1
		if k > #batches then
			done(res)
			return
		end
		send(batches[k], 1)
	end
	nextBatch()
end

--- Locks the street grid just built around (x, y): its edges are the street edges found there now
--- and not `before` (in LOCK_BATCH batches, each retried once: lockEdges). Logs the result; onDone in
--- every case.
local function lockGrid(name : string, label : string, x : number, y : number, r : number, before : {integer : boolean}, onDone : function())
	local list : {integer} = {}
	for e in pairs(streetEdgesNear(x, y, r)) do
		if not before[e] then list[#list + 1] = e end
	end
	table.sort(list)
	if #list == 0 then
		rt.log(string.format("[SQST] %s %s: street grid not locked (no streets found)", name, label))
		onDone()
		return
	end
	local t0 = rt.nowUs()
	lockEdges(name, label, list, function(r : LockResult)
		rt.detail(string.format("[SQST] %s %s street grid locked edges=%d locked=%d batches=%d refused=%d failed=%d success=%s ms=%.0f", name,
			label, #list, r.locked, r.batches, r.refused, r.failed, tostring(r.failed == 0 and r.locked > 0), (rt.nowUs() - t0) / 1000))
		if r.locked == 0 or r.failed > 0 then
			rt.log(string.format("[SQST] %s %s: locking the street grid was refused (%d of %d edges locked)", name, label, r.locked, #list))
		end
		onDone()
	end)
end

--- The street grid construction for a town of caps at (x, y) (lock: the country ring, SHOWCASE.md "Country
--- ring"; stress_grid_streets.lua RING_TEMPLATES), the radius its streets with the corner stubs reach
--- (half x sqrt 2 + STUB, rounded up: lockR), its side and era. nil when our construction is not found.
local function gridEntity(x : number, y : number, caps : integer, lock : boolean) : SimpleProposal.ConstructionEntity, number, number, integer
	local file = gridStreetsCon()
	if file == nil then return nil, 0, 0, 0 end
	local okY, year = pcall(api.engine.util.getYear)
	local era = (okY and year ~= nil and year < logic.WIDE_GRID_NEW_FROM) and 2 or 1
	local half = logic.gridStreetHalf(caps)
	local okH, z = pcall(api.engine.terrain.getHeightAt, api.type.Vec2f.new(x, y))
	if not okH or z == nil then z = 0.0 end
	local V = api.type.Vec4f.new
	local ce = api.type.SimpleProposal.ConstructionEntity.new()
	ce.fileName = file
	ce.params = { sqst_grid_half = half, sqst_grid_era = era, sqst_grid_ring = lock and 2 or 1, seed = 1 }
	ce.transf = api.type.Mat4f.new(V(1.0, 0.0, 0.0, 0.0), V(0.0, 1.0, 0.0, 0.0), V(0.0, 0.0, 1.0, 0.0),
		V(x == 0 and 0.0 or x, y == 0 and 0.0 or y, z == 0 and 0.0 or z, 1.0))
	ce.playerEntity = rt.player()
	ce.name = "SQST street grid"
	return ce, logic.GRID_STREET_HALF[half] * 1.5 + 100, 2 * logic.GRID_STREET_HALF[half], era
end

--- " critical=.. messages=.." of a refused build's proposal data ("" when unreadable).
local function refusedText(data : any) : string
	local okE, es = pcall(function() : string
		local d = data as WorldBuildProposalCommandData
		return string.format(" critical=%s messages=%s", tostring(d.resultProposalData.errorState.critical),
			logic.listText(d.resultProposalData.errorState.messages))
	end)
	return okE and es or ""
end

function towns.buildStreetGrid(name : string, label : string, x : number, y : number, caps : integer, onDone : function(), lock? : boolean)
	local ce, lockR, side, era = gridEntity(x, y, caps, lock == true)
	if ce == nil then
		rt.log(string.format("[SQST] %s %s: street grid construction not found; the town builds its own streets", name, label))
		onDone()
		return
	end
	local proposal = api.type.SimpleProposal.new()
	proposal.constructionsToAdd = { ce }
	local before : {integer : boolean} = lock and streetEdgesNear(x, y, lockR) or {}
	local t0 = rt.nowUs()
	rt.send(name .. ":streets", api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true), function(success : boolean, data : any)
		local errText = success and "" or refusedText(data)
		rt.detail(string.format("[SQST] %s %s street grid %dm era=%d success=%s ms=%.0f%s", name, label,
			math.floor(side), era, tostring(success), (rt.nowUs() - t0) / 1000, errText))
		if not success then
			rt.log(string.format("[SQST] %s %s: street grid refused%s; the town builds its own streets", name, label, errText))
		end
		if success and lock then
			-- read the new streets a moment later, as the junction test does
			rt.later(name .. ":lock", 1000, function() lockGrid(name, label, x, y, lockR, before, onDone) end)
		else
			onDone()
		end
	end)
end

function towns.gridLabel() : string
	local layout = logic.GRID_LAYOUTS[towns.ui.gridLayout] or logic.GRID_LAYOUTS[1]
	return logic.gridLabel(layout.label, logic.GRID_SPACINGS[towns.ui.gridSpacing] or logic.GRID_SPACINGS[1])
end

--- Sets a TownInfo field, false when the userdata refuses it (field names from type.d.tl:3175).
local function trySet(ti : TownInfo, key : string, value : any) : boolean
	return (pcall(function() (ti as {string : any})[key] = value end))
end

function towns.spawnGrid()
	local ui = towns.ui
	local layout = logic.GRID_LAYOUTS[ui.gridLayout] or logic.GRID_LAYOUTS[1]
	local useCamera = ui.gridCentre == 2
	local cx, cy = 0.0, 0.0
	if useCamera then cx, cy = rt.camera() end
	towns.createGrid({
		name = string.format("grid_%dx%d", layout.cols, layout.rows),
		label = string.format("Creating %s grid", layout.label),
		cols = layout.cols,
		rows = layout.rows,
		spacing = logic.GRID_SPACINGS[ui.gridSpacing] or logic.GRID_SPACINGS[1],
		size = logic.TOWN_SIZES[ui.gridSize] or logic.TOWN_SIZES[1],
		useCamera = useCamera,
		cx = cx,
		cy = cy,
		connect = ui.gridConnect,
		streets = ui.gridStreets,
	})
end

--- One town at grid point p: createTowns, then makeTownCreateCmd; the new town is found by diffing the
--- town list (a second look 1 s later when not seen at the callback). Logs "[SQST] <name> k/n <point> ..."
--- and calls done(town, or nil when it failed).
local function createOne(name : string, p : SquareStressGridPoint, caps : integer, k : integer, n : integer, done : function(town : integer))
	local before : {integer : boolean} = {}
	for _, e in ipairs(townList()) do before[e] = true end
	local t = api.type.Map.Town.new()
	t.pos = api.type.Vec2f.new(p.x, p.y)
	t.name = p.name
	t.sizeFactors = { 1, 1, 1 }
	local res = api.engine.mapgen.createTowns(logic.GRID_SEED, { t })
	if #res.toAdd == 0 then
		rt.log(string.format("[SQST] %s %s: createTowns returned nothing to add", name, p.name))
		done(nil)
		return
	end
	local ti = res.toAdd[1]
	local given = ti.position
	local givenText = given ~= nil and string.format("%.1f,%.1f", given.x, given.y) or "?"
	ti.initialLandUseCapacities = { caps, caps, caps }
	ti.position = api.type.Vec2f.new(p.x, p.y)
	local angleOk = trySet(ti, "majorStreetAngle", 0.0) and trySet(ti, "initialMajorStreetAngle", 0.0)
	local t0 = rt.nowUs()
	rt.send(name, api.cmd.makeTownCreateCmd({ ti }), function(success : boolean, _d : any)
		local ms = (rt.nowUs() - t0) / 1000
		local function report()
			local new : integer = nil
			for _, e in ipairs(townList()) do
				if not before[e] then new = e break end
			end
			rt.detail(string.format("[SQST] %s %d/%d %s pos=%.0f,%.0f createTowns pos=%s angle0=%s success=%s ms=%.0f %s",
				name, k, n, p.name, p.x, p.y, givenText, tostring(angleOk), tostring(success), ms,
				new ~= nil and townSummary(new) or "new town not found"))
			done((success and new ~= nil) and new or nil)
		end
		local found = false
		for _, e in ipairs(townList()) do
			if not before[e] then found = true break end
		end
		if found or not success then
			report()
		else
			rt.later(name .. ":recheck", 1000, report)
		end
	end)
end

--- The state of a batched createGrid (one table: the job's closures stay far below Lua 5.1's upvalue limit).
local record GridBatch
	name : string
	points : {SquareStressGridPoint}
	live : {integer}                       -- grid indices built (not skipped)
	capsOf : function(k : integer) : integer
	lock : boolean
	grids : boolean                        -- our street grid first (streets 2 / 3)
	lockR : {integer : number}             -- grid index -> radius its streets reach
	before : {integer : {integer : boolean}}   -- grid index -> street edges there before its grid's batch
	gridOk : {integer : boolean}
	timing : {string : number}             -- towns / grids / locks (ms)
end

--- One step of a batched createGrid after its setup.
local record GridTask
	kind : string                          -- "grids", "lock", "towns"
	list : {integer}                       -- grids: its grid indices
	label : string                         -- grids: "batch c/n"
end

--- Sends the street grids of `list` (grid indices) in one proposal; a refused proposal is sent again one
--- grid per proposal (each logged; a refused one leaves its town on its own streets). done() at the end.
local function gridBatch(b : GridBatch, list : {integer}, label : string, done : function())
	local ces : {SimpleProposal.ConstructionEntity} = {}
	local idx : {integer} = {}
	local sides : {integer : number} = {}
	local era = 0
	for _, k in ipairs(list) do
		local p = b.points[k]
		local ce, lockR, side, e = gridEntity(p.x, p.y, b.capsOf(k), b.lock)
		if ce ~= nil then
			ces[#ces + 1] = ce
			idx[#idx + 1] = k
			sides[k], era = side, e
			b.lockR[k] = lockR
			if b.lock and b.before[k] == nil then b.before[k] = streetEdgesNear(p.x, p.y, lockR) end
		else
			rt.log(string.format("[SQST] %s %s: street grid construction not found; the town builds its own streets", b.name, p.name))
		end
	end
	if #ces == 0 then done() return end
	local proposal = api.type.SimpleProposal.new()
	proposal.constructionsToAdd = ces
	local t0 = rt.nowUs()
	rt.send(b.name .. ":streets", api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, true), function(success : boolean, data : any)
		local ms = (rt.nowUs() - t0) / 1000
		local errText = success and "" or refusedText(data)
		for _, k in ipairs(idx) do
			if success then b.gridOk[k] = true end
			rt.detail(string.format("[SQST] %s %s street grid %dm era=%d success=%s ms=%.0f %s grids=%d%s", b.name, b.points[k].name,
				math.floor(sides[k]), era, tostring(success), ms, label, #idx, errText))
		end
		if success or #idx == 1 then
			if not success then
				rt.log(string.format("[SQST] %s %s: street grid refused%s; the town builds its own streets", b.name, b.points[idx[1]].name, errText))
			end
			done()
			return
		end
		-- the batch was refused: each grid on its own, to find (and log) the one(s) the game refuses
		rt.log(string.format("[SQST] %s street grids %s (%d grids) refused%s; sent again one by one", b.name, label, #idx, errText))
		local j = 0
		local nextOne : function()
		nextOne = function()
			j = j + 1
			if j > #idx then done() return end
			gridBatch(b, { idx[j] }, "alone", nextOne)
		end
		nextOne()
	end)
end

--- Every live point's town in ONE makeTownCreateCmd (api cmd.d.tl:831 takes a list of TownInfos): one
--- createTowns call for all of them, each TownInfo's capacities, position and angle set as createOne does
--- (matched to its point by its position, logic.matchNearest; in order when they can't be matched). The
--- new towns are found by diffing the town list and matched back to the points by their real positions
--- (townPositions, nearest within TOWN_MATCH_MAX). done(found: grid index -> town, missing grid indices).
local function createBatch(b : GridBatch, list : {integer}, done : function(found : {integer : integer}, missing : {integer}))
	local before : {integer : boolean} = {}
	for _, e in ipairs(townList()) do before[e] = true end
	local maps : {GameMap.Town} = {}
	local asked : {{number}} = {}
	for i, k in ipairs(list) do
		local p = b.points[k]
		local t = api.type.Map.Town.new()
		t.pos = api.type.Vec2f.new(p.x, p.y)
		t.name = p.name
		t.sizeFactors = { 1, 1, 1 }
		maps[i] = t
		asked[i] = { p.x, p.y }
	end
	local okC, res = pcall(api.engine.mapgen.createTowns, logic.GRID_SEED, maps)
	local nAdd = (okC and res ~= nil and res.toAdd ~= nil) and #res.toAdd or 0
	if nAdd ~= #list then
		rt.log(string.format("[SQST] %s towns batch: createTowns gave %d of %d towns%s; one by one", b.name, nAdd, #list,
			okC and "" or (" (" .. tostring(res) .. ")")))
		done({}, list)
		return
	end
	-- each TownInfo to its point (createTowns may hand them back in another order)
	local given : {{number}} = {}
	for j = 1, nAdd do
		local okP, gx, gy = pcall(function() : number, number return res.toAdd[j].position.x, res.toAdd[j].position.y end)
		given[j] = okP and { gx, gy } or { math.huge, math.huge }
	end
	local m = logic.matchNearest(asked, given, logic.TOWN_MATCH_MAX)
	local nM = 0
	for _ in pairs(m) do nM = nM + 1 end
	local order = "position"
	if nM < #list then
		order = "list order"
		m = {}
		for i = 1, #list do m[i] = i end
	end
	local infos : {TownInfo} = {}
	local angleOk = true
	for i, k in ipairs(list) do
		local p = b.points[k]
		local ti = res.toAdd[m[i]]
		local caps = b.capsOf(k)
		ti.initialLandUseCapacities = { caps, caps, caps }
		ti.position = api.type.Vec2f.new(p.x, p.y)
		angleOk = trySet(ti, "majorStreetAngle", 0.0) and trySet(ti, "initialMajorStreetAngle", 0.0) and angleOk
		infos[#infos + 1] = ti
	end
	local t0 = rt.nowUs()
	rt.send(b.name, api.cmd.makeTownCreateCmd(infos), function(success : boolean, _d : any)
		local ms = (rt.nowUs() - t0) / 1000
		local function newTowns() : {integer}
			local out : {integer} = {}
			for _, e in ipairs(townList()) do
				if not before[e] then out[#out + 1] = e end
			end
			return out
		end
		local function report()
			local new = newTowns()
			local all = townPositions()
			local pos : {integer : {number}} = {}
			for _, t in ipairs(all) do pos[t.id] = { t.x, t.y } end
			local found : {{number}} = {}
			for j, e in ipairs(new) do found[j] = pos[e] or { math.huge, math.huge } end
			local mm = logic.matchNearest(asked, found, logic.TOWN_MATCH_MAX)
			-- new towns left over (centred further off than TOWN_MATCH_MAX) go to the points left over, nearest
			-- first, so no point is created twice; only when the town's nearest asked point IS that point (it
			-- sits in that grid, not in another one): else the town is logged as a stray and its point is
			-- created one by one
			local leftP, leftF : {integer}, {integer} = {}, {}
			local usedF : {integer : boolean} = {}
			for _, j in pairs(mm) do usedF[j] = true end
			for i = 1, #list do if mm[i] == nil then leftP[#leftP + 1] = i end end
			for j = 1, #new do if not usedF[j] then leftF[#leftF + 1] = j end end
			local far, stray = 0, 0
			if #leftP > 0 and #leftF > 0 then
				local pp : {{number}} = {}
				local ff : {{number}} = {}
				for k, i in ipairs(leftP) do pp[k] = asked[i] end
				for k, j in ipairs(leftF) do ff[k] = found[j] end
				for k, k2 in pairs(logic.matchNearest(pp, ff, math.huge)) do
					local f = ff[k2]
					local nearest, bestD = 0, math.huge
					for i2, q in ipairs(asked) do
						local d = (q[1] - f[1]) ^ 2 + (q[2] - f[2]) ^ 2
						if d < bestD then nearest, bestD = i2, d end
					end
					if nearest == leftP[k] and bestD < math.huge then
						mm[leftP[k]] = leftF[k2]
						far = far + 1
					else
						stray = stray + 1
						rt.log(string.format("[SQST] %s towns batch: new town %d at %.0f,%.0f is not in %s's grid; left as it is", b.name,
							new[leftF[k2]], f[1], f[2], b.points[list[leftP[k]]].name))
					end
				end
			end
			local out : {integer : integer} = {}
			local missing : {integer} = {}
			for i, k in ipairs(list) do
				local p = b.points[k]
				-- a town found is used even when the command reported failure (never created twice)
				local e = mm[i] ~= nil and new[mm[i]] or nil
				if e ~= nil then out[k] = e else missing[#missing + 1] = k end
				rt.detail(string.format("[SQST] %s %d/%d %s pos=%.0f,%.0f createTowns pos=%.1f,%.1f angle0=%s success=%s ms=%.0f batch=%d (%s) %s",
					b.name, i, #list, p.name, p.x, p.y, given[m[i]][1], given[m[i]][2], tostring(angleOk), tostring(success), ms, #list, order,
					e ~= nil and townSummary(e) or "new town not found"))
			end
			rt.log(string.format("[SQST] %s towns batch: one command for %d towns success=%s ms=%.0f new=%d matched=%d missing=%d far=%d stray=%d", b.name, #list,
				tostring(success), ms, #new, #list - #missing, #missing, far, stray))
			done(out, missing)
		end
		if success and #newTowns() < #list then
			rt.later(b.name .. ":recheck", 1000, report)
		else
			report()
		end
	end)
end

function towns.createGrid(opts : SquareStressGridOpts,
		onDone? : function(created : {integer : integer}, points : {SquareStressGridPoint}, skipped : {integer : boolean}, timing : {string : number}))
	local layout = { cols = opts.cols, rows = opts.rows }
	local spacing = opts.spacing
	local size = opts.size
	local connectMode = opts.connect
	local useCamera = opts.useCamera
	local cx, cy = opts.cx or 0.0, opts.cy or 0.0
	local name = opts.name
	local n = opts.points ~= nil and #opts.points or layout.cols * layout.rows
	local points : {SquareStressGridPoint} = {}
	local created : {integer : integer} = {}   -- grid index -> town entity
	local failed = 0
	local cancelled = false
	local skipped : {integer : boolean} = {}   -- opts.skipNoLand: grid index -> skipped (no land)
	local nSkipped = 0
	local timing : {string : number} = { towns = 0, grids = 0, locks = 0 }
	local t0All = rt.nowUs()

	local function finishBatch()
		if cancelled then return end
		if not opts.batch then timing.towns = (rt.nowUs() - t0All) / 1000 end
		-- Requested vs real centres (makeMapFromGame), so a shifted town shows in the log.
		local all = townPositions()
		local byId : {integer : SquareStressTownPos} = {}
		for _, t in ipairs(all) do byId[t.id] = t end
		local worst = 0.0
		for k, p in ipairs(points) do
			local e = created[k]
			local real = e ~= nil and byId[e] or nil
			if real ~= nil then
				local d = math.sqrt((real.x - p.x) ^ 2 + (real.y - p.y) ^ 2)
				if d > worst then worst = d end
				rt.detail(string.format("[SQST] %s %s town=%d asked=%.0f,%.0f real=%.1f,%.1f off=%.1fm buildings=%d",
					name, p.name, e, p.x, p.y, real.x, real.y, d, townBuildings(e)))
			end
		end
		local nCreated = 0
		for _, e in pairs(created) do
			nCreated = nCreated + 1
			-- with its name: Remove towns takes it only while it still has that name (a destroyed town's
			-- entity id may be reused by a later, real town)
			towns.testTowns[e] = townName(e)
		end
		rt.log(string.format("[SQST] %s summary towns=%d created=%d failed=%d%s spacing=%.0fm centre=%.0f,%.0f caps=%d maxOffset=%.1fm%s",
			name, n, nCreated, failed, opts.skipNoLand and string.format(" skipped=%d", nSkipped) or "", spacing, cx, cy, size.caps, worst,
			opts.batch and string.format(" batched towns_ms=%.0f grids_ms=%.0f locks_ms=%.0f", timing.towns, timing.grids, timing.locks) or ""))
		local gp = logic.gridPairs(layout.cols, layout.rows, connectMode)
		if #gp > 0 and nCreated >= 2 then
			connectTowns("connect_grid", #gp, function(_all : {SquareStressTownPos}) : {{integer}}
				local out : {{integer}} = {}
				for _, pr in ipairs(gp) do
					local a, b = created[pr[1]], created[pr[2]]
					if a ~= nil and b ~= nil then out[#out + 1] = { a, b } end
				end
				return out
			end)
		end
		if onDone ~= nil then onDone(created, points, skipped, timing) end
	end

	-- the points, the land check (cancel, or skip with opts.skipNoLand) and the placement line
	local function setup()
		if not useCamera then
			local box = api.engine.terrain.getBoundingBox()
			cx, cy = (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2
		end
		if opts.points ~= nil then
			-- explicit points (Crossing test), offsets from the centre
			points = {}
			for k, q in ipairs(opts.points) do
				points[k] = { x = cx + q.x, y = cy + q.y, name = q.name, row = 1, col = k, size = q.size }
			end
		else
			points = logic.gridPositions(cx, cy, layout.cols, layout.rows, spacing)
		end
		for k, p in ipairs(points) do
			local okL, good, why = pcall(landOk, p.x, p.y)
			if (not okL or not good) and opts.skipNoLand then
				-- Showcase: this town alone is left out (nothing of it is built), the rest goes on
				skipped[k] = true
				nSkipped = nSkipped + 1
				rt.log(string.format("[SQST] %s %s at %.0f, %.0f: town skipped: no land (%s)", name, p.name, p.x, p.y,
					okL and tostring(why) or "unchecked"))
			elseif not okL or not good then
				cancelled = true
				rt.warn("Not enough space", string.format("%s cancelled: %s at %.0f, %.0f is %s.\nUse a smaller spacing, fewer towns, another centre or a larger flat map such as Blank Slate.",
					name, p.name, p.x, p.y, okL and tostring(why) or "unchecked"))
				break
			end
		end
		if not cancelled then
			local near = 0
			for _, t in ipairs((townPositions())) do
				for _, p in ipairs(points) do
					if (t.x - p.x) ^ 2 + (t.y - p.y) ^ 2 < (spacing * GRID_NEAR_WARN) ^ 2 then
						near = near + 1
						break
					end
				end
			end
			rt.log(string.format("[SQST] %s placement: %d towns %.0fm apart around %.0f,%.0f%s", name, n, spacing, cx, cy,
				near > 0 and string.format(" (warning: %d existing town(s) close to grid points)", near) or ""))
		end
	end

	-- a point's own size (Showcase: the spec's one size), else the batch's
	local function capsOf(k : integer) : integer
		local p = points[k]
		return p ~= nil and p.size ~= nil and logic.TOWN_SIZES[p.size] ~= nil and logic.TOWN_SIZES[p.size].caps or size.caps
	end

	if opts.batch then
		-- Batched (SHOWCASE.md "Faster, simpler Lights showcase + batched building"): every street grid in
		-- proposals of GRID_BATCH, their streets locked in LOCK_BATCH batches across towns, then every town in
		-- one command; each batch falls back to one by one on refusal. Steps: setup, grids (one per batch),
		-- lock, towns, the towns the batch missed (one by one).
		local b : GridBatch = { name = name, points = points, live = {}, capsOf = capsOf, lock = opts.streets == 3,
			grids = opts.streets == 2 or opts.streets == 3, lockR = {}, before = {}, gridOk = {}, timing = timing }
		local tasks : {GridTask} = {}
		rt.enqueue(name, 1, function(i : integer, job : SquareStressJob)
			if i == 1 then
				setup()
				b.points = points
				if cancelled then logic.resume(job) return end
				for k = 1, #points do
					if not skipped[k] then b.live[#b.live + 1] = k end
				end
				if b.grids then
					local chunks = logic.chunk(b.live, logic.GRID_BATCH)
					for c, list in ipairs(chunks) do tasks[#tasks + 1] = { kind = "grids", list = list, label = string.format("batch %d/%d", c, #chunks) } end
					if b.lock then tasks[#tasks + 1] = { kind = "lock" } end
				end
				tasks[#tasks + 1] = { kind = "towns" }
				job.total = 1 + #tasks
				logic.resume(job)
				return
			end
			local task = tasks[i - 1]
			local kind = task.kind
			local function last()
				logic.resume(job)
				if i == job.total then finishBatch() end
			end
			local t0 = rt.nowUs()
			if kind == "grids" then
				gridBatch(b, task.list, task.label, function()
					timing.grids = timing.grids + (rt.nowUs() - t0) / 1000
					last()
				end)
			elseif kind == "lock" then
				-- read the new streets a moment later, as one grid's lock does; every grid's in one list
				rt.later(name .. ":lock", 1000, function()
					local seen : {integer : boolean} = {}
					local list : {integer} = {}
					local nGrids = 0
					for _, k in ipairs(b.live) do
						if b.gridOk[k] then
							nGrids = nGrids + 1
							local p = points[k]
							for e in pairs(streetEdgesNear(p.x, p.y, b.lockR[k])) do
								if not (b.before[k] or {})[e] and not seen[e] then
									seen[e] = true
									list[#list + 1] = e
								end
							end
						end
					end
					table.sort(list)
					if #list == 0 then
						if nGrids > 0 then rt.log(string.format("[SQST] %s: street grids not locked (no streets found)", name)) end
						timing.locks = timing.locks + (rt.nowUs() - t0) / 1000
						last()
						return
					end
					local t1 = rt.nowUs()
					lockEdges(name, "grids", list, function(r : LockResult)
						rt.log(string.format("[SQST] %s street grids locked grids=%d edges=%d locked=%d batches=%d refused=%d failed=%d ms=%.0f", name,
							nGrids, #list, r.locked, r.batches, r.refused, r.failed, (rt.nowUs() - t1) / 1000))
						if r.locked == 0 or r.failed > 0 then
							rt.log(string.format("[SQST] %s: locking the street grids was refused (%d of %d edges locked)", name, r.locked, #list))
						end
						timing.locks = timing.locks + (rt.nowUs() - t0) / 1000
						last()
					end)
				end)
			elseif kind == "towns" then
				if #b.live == 0 then last() return end
				createBatch(b, b.live, function(found : {integer : integer}, missing : {integer})
					for k, e in pairs(found) do created[k] = e end
					if #missing == 0 then
						timing.towns = timing.towns + (rt.nowUs() - t0) / 1000
						last()
						return
					end
					-- the towns the batch did not create: one by one (createOne), each logged
					rt.log(string.format("[SQST] %s towns batch missed %d town(s); creating them one by one", name, #missing))
					local j = 0
					local nextOne : function()
					nextOne = function()
						j = j + 1
						if j > #missing then
							timing.towns = timing.towns + (rt.nowUs() - t0) / 1000
							last()
							return
						end
						local k = missing[j]
						createOne(name, points[k], capsOf(k), j, #missing, function(town : integer)
							if town ~= nil then created[k] = town else failed = failed + 1 end
							nextOne()
						end)
					end
					nextOne()
				end)
			else
				last()
			end
		end, { serial = true, label = opts.label, timeoutMs = logic.BATCH_TIMEOUT_MS })
		return
	end

	rt.enqueue(name, n, function(i : integer, job : SquareStressJob)
		if i == 1 then setup() end
		local p = points[i]
		local caps = capsOf(i)
		if cancelled or p == nil or skipped[i] then
			logic.resume(job)
			if i == n then finishBatch() end
			return
		end
		local function createTown()
			createOne(name, p, caps, i, n, function(town : integer)
				if town ~= nil then created[i] = town else failed = failed + 1 end
				logic.resume(job)
				if i == n then finishBatch() end
			end)
		end
		if opts.streets == 2 or opts.streets == 3 then
			towns.buildStreetGrid(name, p.name, p.x, p.y, caps, function() createTown() end, opts.streets == 3)
		else
			createTown()
		end
	end, { serial = true, label = opts.label })
end

---------------------------------------------------------------------------
-- Town growth locked into the grid (Showcase and Lights showcase; SHOWCASE.md "Town growth locked into
-- the grid"). A town on a locked grid still got houses there but its own streets kept branching out of
-- it (screenshot 2026-10-12). Locked streets get houses and the town stops branching off them
-- (docs/findings/towns.md, Showcase v5: 0 vanilla streets attached after 10 steps vs 33 unlocked), so
-- every street of the town is locked: the grid (built locked), the town's own seed streets, the link
-- roads (built locked, stress_junctions) and anything the town grows later (the leak check after each
-- growth pass). Which streets are the town's: street edges within the grid's corners + LOCK_REACH whose
-- closest town is it, not in a construction (the junctions). Their positions are their nodes'.

--- One town's streets around its grid (scanTown).
local record LockScan
	unlocked : {integer}          -- unlocked street edges of the town without edge objects (to lock), sorted
	inside : integer              -- of them inside the grid square (+ LOCK_MARGIN)
	outside : integer             -- of them outside: streets the town grew out of the grid (the leak)
	lockedOutside : integer       -- locked streets outside (ours: link roads, stubs not removed)
	objects : integer             -- unlocked edges with edge objects (never swapped)
	stubs : {{integer}}           -- unused grid corner stubs: { edge, outer (dead-end) node, corner node }
	edges : integer               -- street edges of the town looked at
	zone : integer                -- of the unlocked ones: in its junctions' zones (+ ZONE_LOCK_MARGIN), any town's
end

local function nodeXY(n : integer) : {number}
	local ok, c : boolean, any = pcall(api.engine.getComponent, n, api.type.ComponentType.BASE_NODE)
	if not ok or c == nil then return nil end
	local okP, x, y = pcall(function() : number, number
		local pos = (c as Engine.Component.BaseNode).position
		return pos.x, pos.y
	end)
	if not okP or x == nil then return nil end
	return { x, y }
end

local function nodeDegree(n : integer) : integer
	local ok, segs = pcall(api.engine.system.streetSystem.getNodeSegments, n)
	if not ok or segs == nil then return nil end
	return #(segs as {integer})
end

--- The town's streets around area a (see the section comment), classified.
local function scanTown(a : SquareStressLockArea) : LockScan
	local CT = api.type.ComponentType
	local out : LockScan = { unlocked = {}, inside = 0, outside = 0, lockedOutside = 0, objects = 0, stubs = {}, edges = 0, zone = 0 }
	local r = math.max(a.half * 1.4143 + logic.LOCK_REACH, a.reach or 0)
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(a.x, a.y), r, CT.BASE_EDGE)
	if not ok or list == nil then return out end
	local ids : {integer} = {}
	local seen : {integer : boolean} = {}
	for _, e in ipairs(list as {integer}) do
		if not seen[e] then ids[#ids + 1] = e seen[e] = true end
	end
	-- its junctions' zones: every street there, whatever town is closest (a junction lies between its
	-- towns; user 2026-10-12: a town grew a block off an unlinked crossing arm)
	local inZone : {integer : boolean} = {}
	for _, z in ipairs(a.zones or {}) do
		local okZ, zl = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(z[1], z[2]), z[3] + logic.ZONE_LOCK_MARGIN, CT.BASE_EDGE)
		if okZ and zl ~= nil then
			for _, e in ipairs(zl as {integer}) do
				inZone[e] = true
				if not seen[e] then ids[#ids + 1] = e seen[e] = true end
			end
		end
	end
	table.sort(ids)
	for _, e in ipairs(ids) do
		local okS, st : boolean, any = pcall(api.engine.getComponent, e, CT.BASE_EDGE_STREET)
		local okB, beAny : boolean, any = pcall(api.engine.getComponent, e, CT.BASE_EDGE)
		local be = (okS and st ~= nil and okB) and beAny as Engine.Component.BaseEdge or nil
		local p0 = be ~= nil and nodeXY(be.node0) or nil
		local p1 = be ~= nil and nodeXY(be.node1) or nil
		if p0 ~= nil and p1 ~= nil and not inConstruction(e, false) then
			local mine = true
			local okT, t = pcall(api.engine.util.town.getClosestTown, api.type.Vec3f.new((p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2, 0))
			if okT and t ~= nil and t >= 0 and t ~= a.town and not inZone[e] then mine = false end
			if mine then
				out.edges = out.edges + 1
				local outside = logic.edgeOutside(a, p0, p1, logic.LOCK_MARGIN)
				local okO, nObj = pcall(function() : integer return be.objects ~= nil and #be.objects or 0 end)
				if be.roadDevelopmentLocked == true then
					if outside then out.lockedOutside = out.lockedOutside + 1 end
				else
					if inZone[e] then out.zone = out.zone + 1
					elseif outside then out.outside = out.outside + 1 else out.inside = out.inside + 1 end
					if okO and nObj > 0 then out.objects = out.objects + 1 else out.unlocked[#out.unlocked + 1] = e end
				end
				local endK = logic.stubOuterEnd(a, p0, p1)
				if endK ~= nil then
					local outer = endK == 0 and be.node0 or be.node1
					local corner = endK == 0 and be.node1 or be.node0
					-- a link joined there: the outer end is no dead end any more
					if nodeDegree(outer) == 1 and not inConstruction(outer, true) and (not okO or nObj == 0) then
						out.stubs[#out.stubs + 1] = { e, outer, corner }
					end
				end
			end
		end
	end
	return out
end

--- The town's buildings: how many stand outside its grid (+ HOUSE_MARGIN), the count, the level
--- counts of all and of those in the grid's central half (the "dense centre"), and how many stand along
--- the outside of its perimeter street (beyond the grid's outer streets, within HOUSE_MARGIN: the parcels
--- of the ring's outer side; a country ring has none).
local function townHouses(a : SquareStressLockArea) : integer, integer, {integer}, {integer}, integer, {string : integer}
	local CT = api.type.ComponentType
	local src : {string : integer} = {}
	local okM, m = pcall(api.engine.system.townBuildingSystem.getTown2BuildingMap)
	local list = (okM and m ~= nil) and (m as {integer : {integer}})[a.town] or nil
	local levels : {integer} = {}
	local centre : {integer} = {}
	local outside, perimeter = 0, 0
	local inner : SquareStressLockArea = { town = a.town, label = a.label, x = a.x, y = a.y, half = a.half / 2 }
	for i = 1, #(list or {}) do
		local b = list[i]
		local okL, lvl = pcall(function() : integer
			return (api.engine.getComponent(b, CT.TOWN_BUILDING) as Engine.Component.TownBuilding).level
		end)
		local level = (okL and lvl ~= nil) and lvl or 1
		levels[#levels + 1] = level
		-- its spot (logic.housePos): the box centre when the box is real, else its construction's origin; a
		-- building with neither (still under construction) is not counted (houses_unread)
		local okB, box = pcall(function() : {number}
			local bv = api.engine.getComponent(b, CT.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
			return { bv.bbox.min.x, bv.bbox.min.y, bv.bbox.max.x, bv.bbox.max.y }
		end)
		local okC, con = pcall(function() : {number}
			local tb = api.engine.getComponent(b, CT.TOWN_BUILDING) as Engine.Component.TownBuilding
			local cc = api.engine.getComponent(tb.construction, CT.CONSTRUCTION) as Engine.Component.Construction
			local v = cc.transf:getTransl()
			return { v.x, v.y }
		end)
		local pos, from, odd = logic.housePos(okB and box or nil, okC and con or nil)
		if from ~= nil then src[from] = (src[from] or 0) + 1 end
		if odd then src.odd = (src.odd or 0) + 1 end
		if pos == nil then
			src.unread = (src.unread or 0) + 1
		else
			local x, y = pos[1], pos[2]
			if logic.outsideGrid(a, x, y, logic.HOUSE_MARGIN) then outside = outside + 1
			elseif logic.outsideGrid(a, x, y, 0) then perimeter = perimeter + 1 end
			if not logic.outsideGrid(inner, x, y, 0) then centre[#centre + 1] = level end
		end
	end
	return outside, #levels, logic.levelCounts(levels), logic.levelCounts(centre), perimeter, src
end

--- The removal of a town's unused corner stubs (scanTown's stubs): the stub edges, their dead-end nodes,
--- and the corner nodes' configs without them (remove + add, only where a corner has a config: never a
--- remove on a node without one; the same shape as Remove all roads, stress_roads.tl). nil when none is left.
local function stubProposal(stubs : {{integer}}) : SimpleProposal, integer
	local edges : {integer} = {}
	local deadNodes : {integer} = {}
	local gone : {integer : boolean} = {}
	local corners : {integer : boolean} = {}
	for _, st in ipairs(stubs) do
		local okB, be : boolean, any = pcall(api.engine.getComponent, st[1], api.type.ComponentType.BASE_EDGE)
		if okB and be ~= nil and not gone[st[1]] then
			edges[#edges + 1] = st[1]
			deadNodes[#deadNodes + 1] = st[2]
			gone[st[1]] = true
			corners[st[3]] = true
		end
	end
	if #edges == 0 then return nil, 0 end
	local sorted : {integer} = {}
	for n in pairs(corners) do sorted[#sorted + 1] = n end
	table.sort(sorted)
	local cfgRemove : {integer} = {}
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	for _, n in ipairs(sorted) do
		local entry = rt.nodeConfigEntry(n, nil, gone)
		if entry ~= nil then
			cfgRemove[#cfgRemove + 1] = n
			cfgAdd[#cfgAdd + 1] = entry
		end
	end
	local p = api.type.SimpleProposal.new()
	p.streetProposal.edgesToRemove = edges
	p.streetProposal.nodesToRemove = deadNodes
	if #cfgAdd > 0 then
		p.streetProposal.nodeConfigsToRemove = cfgRemove
		p.streetProposal.nodeConfigsToAdd = cfgAdd
	end
	return p, #edges
end

--- At most LOCK_MAX_PASS of the scan's unlocked edges (the rest the next pass).
local function lockList(sc : LockScan) : {integer}
	local list : {integer} = {}
	for i = 1, math.min(#sc.unlocked, logic.LOCK_MAX_PASS) do list[i] = sc.unlocked[i] end
	return list
end

--- Locks the street edges of `list` (lockEdges: LOCK_BATCH batches, one proposal in flight, a refused batch rebuilt
--- and sent once more; gone, locked or construction edges left out), then done(locked, failed). Runs inside the
--- caller's serial step (the Lights showcase's town entries: their own streets right after their build).
--- done(locked, failed, already): an edge already roadDevelopmentLocked counts as locked (lockProposal leaves it out;
--- 2026-10-13, log session of seed 148916: the entry ring's highway_new_medium quarters, a template with
--- initiallyLocked = true, were already locked: every entry logged "locked=4 of 8").
function towns.lockEdgeList(name : string, label : string, list : {integer}, done : function(locked : integer, failed : integer, already : integer))
	local already = 0
	local todo : {integer} = {}
	for _, e in ipairs(list) do
		local ok, be = pcall(function() : Engine.Component.BaseEdge return api.engine.getComponent(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge end)
		if ok and be ~= nil and be.roadDevelopmentLocked == true then already = already + 1 else todo[#todo + 1] = e end
	end
	lockEdges(name, label, todo, function(r : LockResult) done(r.locked + already, r.failed, already) end)
end

--- One serial step for every town (SHOWCASE.md "batched building"): each town scanned, every town's
--- unlocked streets (LOCK_MAX_PASS per town) locked together in LOCK_BATCH batches across towns (lockEdges,
--- per-town tallies), then (opts.stubs) every town's unused corner stubs removed in one proposal (refused:
--- one proposal per town). One line per town as before, the summary, then opts.onDone(ms).
function towns.lockTowns(name : string, areas : {SquareStressLockArea}, opts? : SquareStressLockOpts)
	local o : SquareStressLockOpts = opts or {}
	local passText = o.pass or "towns"
	if #areas == 0 then return end
	rt.enqueue(name, 1, function(_i : integer, job : SquareStressJob)
		local t0 = rt.nowUs()
		local tot = { locked = 0, failed = 0, removed = 0, outside = 0, stubsLeft = 0 }
		local scans : {integer : LockScan} = {}
		local lists : {integer : {integer}} = {}
		local owner : {integer : integer} = {}
		local all : {integer} = {}
		for k, a in ipairs(areas) do
			local okE, exists = pcall(api.engine.entityExists, a.town)
			if okE and not exists then
				rt.log(string.format("[SQST] %s town %s: gone; not locked", name, a.label))
			else
				local sc = scanTown(a)
				scans[k] = sc
				tot.outside = tot.outside + sc.outside
				lists[k] = lockList(sc)
				for _, e in ipairs(lists[k]) do
					if owner[e] == nil then
						owner[e] = k
						all[#all + 1] = e
					end
				end
			end
		end
		local function finish(stubsOf : {integer : integer}, removedOf : {integer : integer}, r : LockResult)
			for k, a in ipairs(areas) do
				local sc = scans[k]
				if sc ~= nil then
					local c = r.by[k] or { 0, 0, 0, 0 }
					local stubs, removed = stubsOf[k] or 0, removedOf[k] or 0
					tot.locked = tot.locked + c[1]
					tot.failed = tot.failed + c[2]
					tot.removed = tot.removed + removed
					tot.stubsLeft = tot.stubsLeft + stubs - removed
					rt.log(string.format("[SQST] %s town %s lock pass=%s edges=%d unlocked=%d inside=%d outside_streets=%d zone_streets=%d locked=%d refused=%d failed=%d batches=%d objects=%d left=%d stubs=%d removed=%d",
						name, a.label, passText, sc.edges, #sc.unlocked, sc.inside, sc.outside, sc.zone, c[1], c[3], c[2], c[4], sc.objects,
						#sc.unlocked - #lists[k], stubs, removed))
				end
			end
			local ms = (rt.nowUs() - t0) / 1000
			rt.log(string.format("[SQST] %s summary pass=%s towns=%d locked=%d failed=%d stubs_removed=%d stubs_kept=%d outside_streets=%d edges=%d batches=%d ms=%.0f",
				name, passText, #areas, tot.locked, tot.failed, tot.removed, tot.stubsLeft, tot.outside, #all, r.batches, ms))
			logic.resume(job)
			if o.onDone ~= nil then pcall(o.onDone, ms) end
		end
		lockEdges(name, "towns", all, function(r : LockResult)
			local stubsOf : {integer : integer} = {}
			local removedOf : {integer : integer} = {}
			if not o.stubs then
				finish(stubsOf, removedOf, r)
				return
			end
			-- the stubs from a fresh read (the lock swapped every edge for a new one), every town's together
			local perTown : {integer : {{integer}}} = {}
			local allStubs : {{integer}} = {}
			local keys : {integer} = {}
			for k, a in ipairs(areas) do
				if scans[k] ~= nil then
					local st = scanTown(a).stubs
					perTown[k] = st
					stubsOf[k] = #st
					if #st > 0 then keys[#keys + 1] = k end
					for _, x in ipairs(st) do allStubs[#allStubs + 1] = x end
				end
			end
			local function sendStubs(list : {{integer}}, ks : {integer}, after : function(ok : boolean))
				local okP, p, n = pcall(stubProposal, list)
				if not okP or p == nil then
					if not okP then rt.log(string.format("[SQST] %s: stub removal error: %s (they stay, locked)", name, tostring(p))) end
					after(false)
					return
				end
				local okS, err : boolean, any = pcall(function()
					rt.send(name .. ":stubs", api.cmd.makeWorldBuildProposalCmd(p as SimpleProposal, nil, false, true), function(success : boolean, _d : any)
						if not success then
							local who : {string} = {}
							for _, k in ipairs(ks) do who[#who + 1] = areas[k].label end
							rt.log(string.format("[SQST] %s town %s: removing %d corner stubs was refused (they stay, locked)", name,
								table.concat(who, ", "), n))
						end
						after(success)
					end)
				end)
				if not okS then
					rt.log(string.format("[SQST] %s: stub removal failed: %s (they stay, locked)", name, tostring(err)))
					after(false)
				end
			end
			if #allStubs == 0 then
				finish(stubsOf, removedOf, r)
				return
			end
			sendStubs(allStubs, keys, function(okAll : boolean)
				if okAll then
					for _, k in ipairs(keys) do removedOf[k] = #perTown[k] end
					finish(stubsOf, removedOf, r)
					return
				end
				if #keys == 1 then
					finish(stubsOf, removedOf, r)
					return
				end
				-- refused together: one proposal per town, so one bad town keeps only its own stubs
				local j = 0
				local nextTown : function()
				nextTown = function()
					j = j + 1
					if j > #keys then
						finish(stubsOf, removedOf, r)
						return
					end
					local k = keys[j]
					sendStubs(perTown[k], { k }, function(okOne : boolean)
						if okOne then removedOf[k] = #perTown[k] end
						nextTown()
					end)
				end
				nextTown()
			end)
		end, owner)
	end, { serial = true, label = "Locking town streets", timeoutMs = logic.BATCH_TIMEOUT_MS })
end

--- The leak check of one town after a growth pass: counts the streets it grew out of its grid and its
--- houses outside, locks every unlocked street of it (bounded), logs the leak line; then done(outside
--- streets, houses outside, locked).
local function leakCheck(name : string, a : SquareStressLockArea, extra : string, done : function(outside : integer, houses : integer, locked : integer))
	local sc = scanTown(a)
	local housesOut, _n, _l, _c, perimeter, src = townHouses(a)
	local list = lockList(sc)
	lockEdges(name, a.label, list, function(r : LockResult)
		-- houses_unread / houses_pos: buildings without a usable spot, and where the spots came from
		-- (bbox / con = construction origin / odd = both read, far apart): logic.housePos
		rt.log(logic.leakLine(name, a.label, sc.outside, housesOut, string.format("%s houses_perimeter=%d zone_streets=%d inside_new=%d locked=%d failed=%d locked_outside=%d houses_unread=%d houses_pos=bbox:%d,con:%d,odd:%d",
			extra, perimeter, sc.zone, sc.inside, r.locked, r.failed, sc.lockedOutside, src.unread or 0, src.bbox or 0, src.con or 0, src.odd or 0)))
		done(sc.outside, housesOut, r.locked)
	end)
end

function towns.densify(name : string, areas : {SquareStressLockArea}, opts : SquareStressDenseOpts)
	if #areas == 0 then return end
	local factor = opts.factor or logic.DENSE_GROW_FACTOR
	local np = math.max(1, math.floor(opts.passes or 1))
	local steps = logic.denseSteps(#areas, np)
	local weights = opts.weights ~= nil and logic.denseWeights(opts.weights) or nil
	local weightsText = weights ~= nil and logic.listText(weights[1]) or "town's own"
	local stopped : {integer : boolean} = {}
	local b0 : {integer : integer} = {}
	local acc = { b1 = 0, outside = 0, houses = 0, locked = 0, sent = 0, early = 0 }
	local all : {integer} = { 0, 0, 0, 0 }
	local pops : {integer : integer} = {}   -- town index -> population at its final check
	local t0 : integer = nil
	local targetText = opts.target ~= nil and string.format(" target=%d (each town: target / its capacity target)", math.floor(opts.target)) or ""
	rt.log(string.format("[SQST] %s queued towns=%d factor=x%g passes=%d weights=%s (level 1..4, every land use)%s", name, #areas, factor, np,
		weightsText, targetText))
	rt.enqueue(name, #steps, function(i : integer, job : SquareStressJob)
		local st = steps[i]
		local a = areas[st.town]
		if t0 == nil then t0 = rt.nowUs() end
		local function last()
			logic.resume(job)
			if i == #steps then
				local before = 0
				for _, b in pairs(b0) do before = before + b end
				local ms = (rt.nowUs() - t0) / 1000
				rt.log(string.format("[SQST] %s dense summary towns=%d factor=x%g passes=%d weights=%s sent=%d stoppedEarly=%d buildings %d->%d outside_streets=%d houses_outside=%d locked=%d levels %s ms=%.0f%s",
					name, #areas, factor, np, weightsText, acc.sent, acc.early, before, acc.b1, acc.outside, acc.houses, acc.locked, logic.levelText(all), ms,
					logic.popText(pops, #areas)))
				if opts.onDone ~= nil then pcall(opts.onDone, ms) end
			end
		end
		local okE, exists = pcall(api.engine.entityExists, a.town)
		if okE and not exists then
			last()
			return
		end
		if st.kind == "weights" then
			b0[st.town] = townBuildings(a.town)
			if weights == nil then last() return end
			local okC, cmd : boolean, any = pcall(api.cmd.makeTownCustomDistributionWeightsCmd, a.town, weights)
			if not okC then
				rt.log(string.format("[SQST] %s town %s: weights not sent: %s", name, a.label, tostring(cmd)))
				last()
				return
			end
			rt.send(name .. ":weights", cmd, function(success : boolean, _d : any)
				local now = "?"
				pcall(function()
					local w = townComp(a.town).levelToCapacityDistributionWeights
					now = w ~= nil and logic.listText(w[1]) or "nil"
				end)
				rt.detail(string.format("[SQST] %s town %s weights=%s success=%s read_back=%s", name, a.label, weightsText, tostring(success), now))
				last()
			end)
			return
		end
		if st.kind == "grow" then
			if stopped[st.town] then last() return end
			local tc = townComp(a.town)
			local before = logic.listText(tc.sizeFactors)
			local buildings0 = townBuildings(a.town)
			-- with a target: this town's own factor from its residential capacity target now (initial capacity x its
			-- size factor; a forced command fills that x factor; pass 1; unreadable: the fallback factor)
			local f = factor
			local pop0 = townPop(a.town)
			local cap0 : number = nil
			pcall(function() cap0 = (tc.initialLandUseCapacities[1] as number) * ((tc.sizeFactors or {})[1] or 1) end)
			if opts.target ~= nil and st.pass == 1 then
				local own = logic.growFactorForCap(opts.target, cap0)
				if own ~= nil then f = own end
			end
			local factors, note = logic.growPlan(tc.sizeFactors, f, st.pass)
			if opts.target ~= nil and st.pass == 1 then
				note = note .. string.format(" (x%g for %d from capacity=%s pop=%s)", f, math.floor(opts.target), cap0 ~= nil and string.format("%.0f", cap0) or "?",
					pop0 ~= nil and tostring(pop0) or "?")
			end
			local t0 = rt.nowUs()
			acc.sent = acc.sent + 1
			rt.send(name, api.cmd.makeTownUpdateSizeCmd(a.town, factors, true), function(success : boolean, _d : any)
				local buildings1 = townBuildings(a.town)
				local stopText = ""
				if st.pass < np and (not success or not logic.passContinues(buildings0, buildings1)) then
					stopped[st.town] = true
					acc.early = acc.early + 1
					stopText = string.format(" build-out done after pass %d (+%d < %d)", st.pass, buildings1 - buildings0, logic.MIN_PASS_GAIN)
				end
				local pop = townPop(a.town)
				rt.detail(string.format("[SQST] %s town %s pass %d/%d success=%s ms=%.0f sizeFactors %s->%s%s buildings %d->%d (+%d) pop=%s%s", name,
					a.label, st.pass, np, tostring(success), (rt.nowUs() - t0) / 1000, before, logic.listText(factors), note, buildings0, buildings1,
					buildings1 - buildings0, pop ~= nil and tostring(pop) or "?", stopText))
				-- one pass only (Lights showcase): its leak check is the final one
				if np == 1 then last() return end
				leakCheck(name, a, string.format(" pass=%d/%d buildings=%d", st.pass, np, buildings1), function(_o : integer, _h : integer, locked : integer)
					acc.locked = acc.locked + locked
					last()
				end)
			end)
			return
		end
		-- final: the leak check once more (the town kept building after its passes) and its building levels
		local _, n, levels, centre = townHouses(a)
		leakCheck(name, a, string.format(" final buildings=%d", n), function(outside : integer, houses : integer, locked : integer)
			acc.outside = acc.outside + outside
			acc.houses = acc.houses + houses
			acc.locked = acc.locked + locked
			acc.b1 = acc.b1 + n
			for k = 1, 4 do all[k] = all[k] + levels[k] end
			-- the population read late (every town's size command answered by now: the town has had time to fill)
			local pop = townPop(a.town)
			pops[st.town] = pop
			rt.log(string.format("[SQST] %s town %s levels %s centre %s buildings=%d pop=%s", name, a.label, logic.levelText(levels),
				logic.levelText(centre), n, pop ~= nil and tostring(pop) or "?"))
			last()
		end)
	end, { serial = true, label = string.format("Growing x%g, locked to the grid", factor) })
end

---------------------------------------------------------------------------
-- Remove towns: makeTownDestroyCmd per town (cmd.d.tl:832-836: the town's streets and buildings go
-- with it), serial like the map editor's own "remove all towns" (map_editor.tl:758-778, which sends
-- them back to back; here one in flight, the next after its callback).

function towns.removeLabel() : string
	return logic.removeLabel(towns.ui.removeTarget)
end

--- The towns ui.removeTarget would remove now and their names (the confirm dialog lists them).
--- GUI main thread (camera read): call from onClick.
function towns.removePlan() : {integer}, {string}
	local target = towns.ui.removeTarget
	local list : {integer} = {}
	if target == 1 then
		local x, y = rt.camera()
		local t = closestTown(x, y)
		if t ~= nil then list = { t } end
	else
		-- ids of towns gone by any path (another tool, the map editor) are dropped first: ids may be reused
		for e in pairs(towns.testTowns) do
			if not api.engine.entityExists(e) then towns.testTowns[e] = nil end
		end
		for _, t in ipairs(townList()) do
			-- test towns: made by createGrid this session (entity id, still under the name it was made with),
			-- or named like one (earlier sessions, old "Grid S35" names included)
			local n = townName(t)
			if target == 3 or (towns.testTowns[t] ~= nil and towns.testTowns[t] == n) or logic.isTestTownName(n) then
				list[#list + 1] = t
			end
		end
	end
	local names : {string} = {}
	for i, t in ipairs(list) do names[i] = townName(t) end
	return list, names
end

--- Removes the towns of list (default: removePlan()).
function towns.removeTowns(list? : {integer})
	local target = towns.ui.removeTarget
	local name = ({ "remove_nearest", "remove_grid", "remove_all" })[target] or "remove_nearest"
	local busy = rt.busyJob(rt.TEST_JOBS)
	if busy ~= nil then
		rt.warn("Remove towns", string.format("Remove towns: %s is still queued or running; wait for it to finish.", busy))
		return
	end
	list = list or towns.removePlan()
	if #list == 0 then
		rt.warn("Remove towns", "There are no towns to remove.")
		return
	end
	-- Grid towns / All towns take the Showcase's towns: its twin zones go from Smart Lanes too (a later
	-- Showcase sends its own; a nearest-town removal keeps them). Harmless without Smart Lanes.
	if target == 2 or target == 3 then slzones.sendClear(name) end
	local removed, failed, buildings = 0, 0, 0
	rt.enqueue(name, #list, function(i : integer, job : SquareStressJob)
		local town = list[i]
		local function last()
			if i == #list then
				rt.log(string.format("[SQST] %s summary towns=%d removed=%d failed=%d buildings=%d towns left=%d", name,
					#list, removed, failed, buildings, #townList()))
			end
		end
		if not api.engine.entityExists(town) then
			logic.resume(job)
			last()
			return
		end
		local tName, b = townName(town), townBuildings(town)
		local t0 = rt.nowUs()
		rt.send(name, api.cmd.makeTownDestroyCmd(town), function(success : boolean, _d : any)
			local gone = not api.engine.entityExists(town)
			if gone then towns.testTowns[town] = nil end   -- an entity id may be reused later
			if success and gone then
				removed = removed + 1
				buildings = buildings + b
			else
				failed = failed + 1
			end
			rt.detail(string.format("[SQST] %s %d/%d town=%d name=%s buildings=%d success=%s gone=%s ms=%.0f", name, i,
				#list, town, tName, b, tostring(success), tostring(gone), (rt.nowUs() - t0) / 1000))
			logic.resume(job)
			last()
		end)
	end, { serial = true, label = "Removing towns" })
end

---------------------------------------------------------------------------
-- Freeze / unfreeze (makeTownSetDevelopmentActiveCmd, cmd.d.tl:856; the growth script only touches
-- towns with developmentActive, RESEARCH.md section 1)

function towns.setDevelopment(active : boolean)
	local list = townList()
	local name = active and "unfreeze_towns" or "freeze_towns"
	if #list == 0 then
		rt.warn("No towns", "There are no towns on the map.")
		return
	end
	rt.enqueue(name, #list, function(i : integer, _job : SquareStressJob)
		if api.engine.entityExists(list[i]) then
			rt.send(name, api.cmd.makeTownSetDevelopmentActiveCmd(list[i], active))
		end
	end, { label = active and "Unfreezing" or "Freezing" })
end

--- Town ratings (Game tab): sensitivity 0 for noise and pollution in every town, or back to the
--- defaults, through the base Towns game script's events, exactly as the town editor sends them
--- (stress_logic.ratingSteps has the citations). One event in flight at a time; the next step runs
--- from the callback. Stored in the save (the towns script state), like the editor's own setting.
function towns.setRatingSensitivity(ignore : boolean)
	local name = ignore and "ignore_town_emissions" or "restore_town_ratings"
	local list = townList()
	if #list == 0 then
		rt.warn("No towns", "There are no towns on the map.")
		return
	end
	local steps = logic.ratingSteps(list, ignore)
	local okN = 0
	rt.enqueue(name, #steps, function(i : integer, job : SquareStressJob)
		local s = steps[i]
		local function last()
			if i == #steps then
				rt.log(string.format("[SQST] %s summary towns=%d events=%d ok=%d", name, #list, #steps, okN))
			end
		end
		if not api.engine.entityExists(s.town) then
			logic.resume(job)
			last()
			return
		end
		rt.send(name, api.cmd.makeScriptingSendEventCmd("", "Towns", s.event, s.param), function(success : boolean, _d : any)
			if success then okN = okN + 1 end
			logic.resume(job)
			last()
		end)
	end, { serial = true, label = ignore and "Ignoring noise and pollution" or "Restoring town ratings" })
end

---------------------------------------------------------------------------
-- Readout (called every few seconds while the window is open, never per frame)

function towns.readout() : string
	local ok, s = pcall(function() : string
		local list = townList()
		local frozen = 0
		for _, t in ipairs(list) do
			local tc = townComp(t)
			if tc ~= nil and not tc.developmentActive then frozen = frozen + 1 end
		end
		local caps = api.engine.system.townBuildingSystem.getTown2personCapacitiesMap()
		local buildings = api.engine.system.townBuildingSystem.getTown2BuildingMap()
		return logic.townReadout(list, caps as {integer : {integer}}, buildings as {integer : {integer}}, frozen)
	end)
	return ok and s or "Towns: readout unavailable"
end

function towns.uiSignature() : string
	local u = towns.ui
	return string.format("%d/%d/%d/%d/%d/%d/%s/%d/%d/%d/%d/%d/%d/%d", u.growTarget, u.factor, u.passes, u.count, u.size, u.placement,
		tostring(u.connect), u.gridLayout, u.gridSpacing, u.gridSize, u.gridCentre, u.gridConnect, u.gridStreets, u.removeTarget)
end

towns.townPositions = function() : {SquareStressTownPos}
	local list = townPositions()
	return list
end

return towns
