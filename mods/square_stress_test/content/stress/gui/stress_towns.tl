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

local towns : SquareStressTowns = {
	ui = { growTarget = 1, factor = 1, passes = 1, count = 1, size = 2, placement = 1, connect = false },
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

function towns.grow(factor : number, passes? : integer)
	local name = factor ~= nil and ("grow_x" .. tostring(factor)) or "grow_reset"
	local np = (factor ~= nil and passes ~= nil and passes > 1) and math.floor(passes) or 1
	local list : {integer}
	if towns.ui.growTarget == 2 then
		local x, y = rt.camera()
		local t = closestTown(x, y)
		if t == nil then
			rt.log("[SQST] " .. name .. ": no town near the camera")
			return
		end
		list = { t }
	else
		list = townList()
	end
	if #list == 0 then
		rt.log("[SQST] " .. name .. ": no towns")
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

--- Road links between each new town and its nearest town: one makeTownConnectWithIndustriesCmd per
--- pair, keep = true (false would remove existing streets, cmd.d.tl:813-819). The connection indices
--- come from api.engine.mapgen.getDefaultTownConnections over the two Map.Towns (as the map editor's
--- "Propose Default Connections", map_editor.tl:2544), so the engine's own index convention is used.
local function connectTowns(created : {integer})
	local name = "connect_towns"
	local pairs_ : {{integer}} = nil
	local byId : {integer : GameMap.Town} = nil
	local total = #created
	rt.enqueue(name, total, function(i : integer, job : SquareStressJob)
		if i == 1 then
			local all : {SquareStressTownPos}
			all, byId = townPositions()
			local newPos : {SquareStressTownPos} = {}
			for _, t in ipairs(all) do
				for _, c in ipairs(created) do
					if c == t.id then newPos[#newPos + 1] = t end
				end
			end
			pairs_ = logic.nearestPairs(newPos, all)
		end
		local pair = pairs_[i]
		if pair == nil then
			logic.resume(job)
			return
		end
		local a, b = byId[pair[1]], byId[pair[2]]
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
		if connect and #created > 0 then connectTowns(created) end
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
-- Freeze / unfreeze (makeTownSetDevelopmentActiveCmd, cmd.d.tl:856; the growth script only touches
-- towns with developmentActive, RESEARCH.md section 1)

function towns.setDevelopment(active : boolean)
	local list = townList()
	local name = active and "unfreeze_towns" or "freeze_towns"
	if #list == 0 then
		rt.log("[SQST] " .. name .. ": no towns")
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
		rt.log("[SQST] " .. name .. ": no towns")
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
	return string.format("%d/%d/%d/%d/%d/%d/%s", u.growTarget, u.factor, u.passes, u.count, u.size, u.placement, tostring(u.connect))
end

towns.townPositions = function() : {SquareStressTownPos}
	local list = townPositions()
	return list
end

return towns
