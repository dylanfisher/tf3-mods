-- DEV ONLY (never upload). Organic Towns dev tools: engine calls the main mod's ot_engine doesn't have (edge
-- reads for undo, the removal proposal, plan markers, the status event to the HUD). Runs in the dev game
-- script's guiUpdate / guiHandleEvent (Main Thread, the same Lua state as the main mod's driver). Every call
-- is pcall-guarded. Crash traps (plans/square_organic_towns/HANDOFF.md): no parcelSystem.getParcelData, a node
-- goes into nodeConfigsToRemove only when its BASE_NODE_CONFIG exists (re-checked right here), no rawget/rawset,
-- no state:get_native, nothing is sent from a build event.

local S = ug_require "square_organic_towns_dev::/organic_towns_dev/otd_shared.lua"
local UN = ug_require "square_organic_towns_dev::/organic_towns_dev/otd_undo.lua"

local X = {}

local function CT() return api.type.ComponentType end

local function comp(e, ct)
	local ok, c = pcall(api.engine.getComponent, e, ct)
	if ok then return c end
	return nil
end

--- { n0, n1, owned, objects, locked (roadDevelopmentLocked) } of a street edge, or nil when it no longer exists.
function X.edge(id)
	local okX, exists = pcall(api.engine.entityExists, id)
	if okX and not exists then return nil end
	local be = comp(id, CT().BASE_EDGE)
	if be == nil then return nil end
	local out = nil
	pcall(function()
		out = { n0 = be.node0, n1 = be.node1, objects = be.objects ~= nil and #be.objects or 0,
			locked = be.roadDevelopmentLocked == true }
	end)
	if out == nil then return nil end
	out.owned = comp(id, CT().PLAYER_OWNED) ~= nil
	return out
end

--- { p0 = {x, y, z}, p1 } of a street edge, or nil (showcase fill points).
function X.edgeGeom(id)
	local be = comp(id, CT().BASE_EDGE)
	if be == nil then return nil end
	local out = nil
	pcall(function()
		out = { p0 = { be.position0.x, be.position0.y, be.position0.z }, p1 = { be.position1.x, be.position1.y, be.position1.z } }
	end)
	return out
end

--- true when the node's config has traffic light phases.
function X.hasLights(n)
	local cfg = comp(n, CT().BASE_NODE_CONFIG)
	if cfg == nil then return false end
	local ok, n2 = pcall(function()
		local tl = cfg.trafficLightConfig
		return tl ~= nil and tl.states ~= nil and #tl.states or 0
	end)
	return ok and (n2 or 0) > 0
end

--- The pruned config entry of a node (connections / crosswalks through `gone` edges dropped), or nil.
local function prunedEntry(n, gone)
	local cfg = comp(n, CT().BASE_NODE_CONFIG)
	if cfg == nil then return nil end
	local conns, cws = {}, {}
	for i = 1, #(cfg.laneConnections or {}) do
		local c = cfg.laneConnections[i]
		conns[#conns + 1] = { segment0 = c.segment0, lane0 = c.lane0, segment1 = c.segment1, lane1 = c.lane1,
			withRoad = c.withRoad, withTram = c.withTram }
	end
	for i = 1, #(cfg.crosswalks or {}) do cws[#cws + 1] = cfg.crosswalks[i] end
	local keep, keepCw = UN.prune(conns, cws, gone)
	local list = {}
	for _, c in ipairs(keep) do
		local LC = api.type.LaneConnection
		local lc = (LC ~= nil and LC.new ~= nil) and LC.new() or {}
		lc.segment0, lc.lane0, lc.segment1, lc.lane1 = c.segment0, c.lane0, c.segment1, c.lane1
		lc.withRoad, lc.withTram = c.withRoad, c.withTram
		list[#list + 1] = lc
	end
	local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
	entry.entity = n
	entry.comp = cfg
	entry.comp.laneConnections = list
	entry.comp.crosswalks = keepCw
	return entry
end

--- SimpleProposal removing an otd_undo plan (edges, orphan nodes, pruned configs).
function X.removalProposal(plan)
	local p = api.type.SimpleProposal.new()
	p.streetProposal.edgesToRemove = plan.edges
	p.streetProposal.nodesToRemove = plan.nodesRemove
	local remove, add = {}, {}
	for _, n in ipairs(plan.cfgPrune) do
		if comp(n, CT().BASE_NODE_CONFIG) ~= nil then   -- never remove a config that doesn't exist (crash)
			local entry = prunedEntry(n, plan.gone)
			if entry ~= nil then
				remove[#remove + 1] = n
				add[#add + 1] = entry
			end
		end
	end
	if #add > 0 then
		p.streetProposal.nodeConfigsToRemove = remove
		p.streetProposal.nodeConfigsToAdd = add
	end
	return p, #add
end

--- Sends a proposal (no player: town streets; playerInitiated false). cb(success, info = { msgs, cost }).
function X.send(proposal, ctx, cb)
	api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, ctx, false, false), function(data, success)
		local info = { msgs = {} }
		pcall(function()
			local es = data.resultProposalData.errorState
			for i = 1, #(es.messages or {}) do info.msgs[#info.msgs + 1] = tostring(es.messages[i]) end
		end)
		pcall(function() info.cost = data.resultProposalData.costs end)
		cb(success == true, info)
	end)
end

X.MARKER_ICON = "::/gui/main/icons/symbol_emote_leaf_colored.tga"   -- base greenification_display uses it
X.MARKER_SPACING = 20

--- Short-lived HUD icons along planned edges (dry run): one per node and every MARKER_SPACING m. Returns the
--- number spawned (0 when api.gui is missing in this state).
function X.markers(edges, seconds)
	local n = 0
	local function spawn(x, y, z)
		local ok = pcall(api.gui.spawnEphemeralHudImage, X.MARKER_ICON, nil, nil, api.type.Vec3f.new(x, y, z + 2), seconds,
			false, true)
		if ok then n = n + 1 end
	end
	for _, e in ipairs(edges or {}) do
		local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
		local len = math.sqrt(dx * dx + dy * dy)
		local k = math.max(1, math.floor(len / X.MARKER_SPACING))
		for i = 0, k do
			local f = i / k
			spawn(e.p0[1] + dx * f, e.p0[2] + dy * f, (e.p0[3] or 0) + ((e.p1[3] or 0) - (e.p0[3] or 0)) * f)
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Showcase (otd_showcase): terrain box, water, town creation and renaming

--- The terrain's bounding box { minX, maxX, minY, maxY } (api.engine.terrain.getBoundingBox), or nil.
function X.terrainBox()
	local ok, b = pcall(api.engine.terrain.getBoundingBox)
	if not ok or b == nil then return nil end
	local okR, out = pcall(function() return { minX = b.min.x, maxX = b.max.x, minY = b.min.y, maxY = b.max.y } end)
	if okR then return out end
	return nil
end

--- true on water or off the map (isValidCoordinate false).
function X.isWater(x, y)
	local p = api.type.Vec2f.new(x, y)
	local okV, valid = pcall(api.engine.terrain.isValidCoordinate, p)
	if okV and valid == false then return true end
	local ok, w = pcall(api.engine.terrain.isOnWater, p)
	return ok and w == true
end

local function listText(v)
	local ok, s = pcall(function()
		local o = {}
		for i = 1, #v do o[i] = string.format("%g", v[i]) end
		return table.concat(o, "/")
	end)
	return ok and s or "?"
end

--- Creates one town as the Stress Test does (findings "Stress Test probes"): createTowns(seed, { Map.Town })
--- -> its TownInfo (toRemove ignored: it lists every existing town) with initialLandUseCapacities {caps x 3},
--- the exact position, the name and, when o.angle is set, majorStreetAngle / initialMajorStreetAngle (degrees,
--- like baseConfig's townMajorStreetAngleRange; the values createTowns gave are returned for the log) ->
--- makeTownCreateCmd. cb(success) after the command. Returns false, { err } when nothing was sent.
--- o = { x, y, name, caps, capsList ({res, com, ind}: R7 industrial satellite probe; overrides caps), angle, seed }.
function X.createTown(o, cb)
	local info = {}
	local ok, err = pcall(function()
		local t = api.type.Map.Town.new()
		t.pos = api.type.Vec2f.new(o.x, o.y)
		t.name = o.name
		t.sizeFactors = { 1, 1, 1 }
		local res = api.engine.mapgen.createTowns(o.seed or "sqotdev", { t })
		if res == nil or res.toAdd == nil or #res.toAdd == 0 then error("createTowns returned nothing to add") end
		local ti = res.toAdd[1]
		pcall(function() info.angle0 = ti.majorStreetAngle end)
		pcall(function() info.initAngle0 = ti.initialMajorStreetAngle end)
		info.caps0 = listText(ti.initialLandUseCapacities)
		ti.initialLandUseCapacities = o.capsList and { o.capsList[1], o.capsList[2], o.capsList[3] } or { o.caps, o.caps, o.caps }
		ti.position = api.type.Vec2f.new(o.x, o.y)
		pcall(function() ti.name = o.name end)
		if o.angle ~= nil then
			local a = o.angle + 0.0
			info.angleSet = (pcall(function() ti.majorStreetAngle = a end))
				and (pcall(function() ti.initialMajorStreetAngle = a end))
		end
		api.cmd.sendCommand(api.cmd.makeTownCreateCmd({ ti }), function(_data, success) cb(success == true) end)
	end)
	if not ok then
		info.err = tostring(err)
		return false, info
	end
	return true, info
end

--- Renames an entity (makeEntitySetNameCmd). cb(success).
function X.rename(e, name, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(e, name), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- Destroys a town (makeTownDestroyCmd: "all streets and buildings belonging to the town will be removed as
--- well", cmd.d.tl; the map editor uses it). cb(success).
function X.destroyTown(t, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownDestroyCmd(t), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- Town development at a position (makeTownDevelopAtCmd(position, developStreets, upgradeBuildings): "new
--- buildings or street segments are added at the given position"; the undo_tf3 mod rebuilds a house with
--- (pos, false, false)). The showcase's "Fill mod streets" probe. cb(success).
function X.developAt(x, y, streets, upgrade, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownDevelopAtCmd(api.type.Vec2f.new(x, y), streets == true, upgrade == true),
			function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- Town development on / off (makeTownSetDevelopmentActiveCmd; base town_growth.script.tl only grows active
--- towns). The showcase's "Freeze vanilla growth" probe: does forced UpdateSize still build vanilla streets?
function X.setDevelopmentActive(t, on, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownSetDevelopmentActiveCmd(t, on == true), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

---------------------------------------------------------------------------
-- Node dump (otd_nodedump): read-only

--- One street edge for the node dump: { id, n0, n1, template, lanes, forward = {bool per lane} } or nil.
function X.edgeFull(id)
	local be = comp(id, CT().BASE_EDGE)
	if be == nil then return nil end
	local out = nil
	pcall(function()
		out = { id = id, n0 = be.node0, n1 = be.node1, template = tostring(be.roadTemplate), forward = {} }
		local lc = be.laneConfigs or {}
		out.lanes = #lc
		for i = 1, #lc do
			local okF, f = pcall(function() return lc[i].forward end)
			if okF then out.forward[i] = f == true end
		end
	end)
	return out
end

--- Street nodes within r of (x, y), nearest first, at most max: { {id, x, y, z, dist} }.
function X.nodesNear(x, y, r, max)
	local out = {}
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, CT().BASE_NODE)
	if not ok or list == nil then return out end
	for _, n in ipairs(list) do
		local bn = comp(n, CT().BASE_NODE)
		if bn ~= nil then
			pcall(function()
				local p = bn.position
				out[#out + 1] = { id = n, x = p.x, y = p.y, z = p.z, dist = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2) }
			end)
		end
	end
	table.sort(out, function(a, b) return a.dist < b.dist end)
	while #out > (max or 3) do table.remove(out) end
	return out
end

--- A node's street segments and BASE_NODE_CONFIG as plain data for otd_nodedump (fills node.edges, segs,
--- config, conns, crosswalks, userModified, lights). Never writes anything.
function X.nodeRead(node)
	node.edges, node.segs, node.conns = {}, {}, {}
	local okS, segs = pcall(api.engine.system.streetSystem.getNodeStreetSegments, node.id)
	if okS and segs then
		for i = 1, #segs do
			local e = segs[i]
			node.segs[#node.segs + 1] = e
			node.edges[e] = X.edgeFull(e)
		end
	end
	local cfg = comp(node.id, CT().BASE_NODE_CONFIG)
	node.config = cfg ~= nil
	if cfg ~= nil then
		pcall(function()
			for k = 1, #(cfg.laneConnections or {}) do
				local c = cfg.laneConnections[k]
				node.conns[#node.conns + 1] = { c.segment0, c.lane0, c.segment1, c.lane1, c.withRoad == true, c.withTram == true }
				-- a connection may name a segment the street system didn't list (tracks, constructions): read it too
				for _, s in ipairs({ c.segment0, c.segment1 }) do
					if node.edges[s] == nil then
						node.edges[s] = X.edgeFull(s)
						node.segs[#node.segs + 1] = s
					end
				end
			end
		end)
		pcall(function() node.crosswalks = #(cfg.crosswalks or {}) end)
		pcall(function() node.userModified = cfg.userModifiedLaneConnections end)
		pcall(function()
			local tl = cfg.trafficLightConfig
			node.lights = tl ~= nil and tl.states ~= nil and #tl.states or 0
		end)
	end
	return node
end

---------------------------------------------------------------------------
-- Showcase v3: density lever, game speed, calendar

--- Per-town level weights (makeTownCustomDistributionWeightsCmd(town, {{4} x 3 land uses}), cmd.d.tl).
--- cb(success). false when the command could not be made.
function X.townWeights(t, weights, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownCustomDistributionWeightsCmd(t, weights), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
	return ok
end

--- Current simulation speedup (GAME_SPEED component: 0 = paused) or nil.
function X.gameSpeed()
	local gs = comp(api.engine.util.getWorld(), CT().GAME_SPEED)
	if gs == nil then return nil end
	local ok, v = pcall(function() return gs.speedup end)
	return ok and v or nil
end

--- Sets the simulation speed (makeGameSetSpeedCmd(speedup), as the base game bar; its buttons offer 0/1/2/4).
function X.setGameSpeed(v, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(math.floor(v)), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
	return ok
end

--- Sets the game date to Jan 1st of year y (makeGameSetDateCmd, as the base calendar editor and the Stress Test's year
--- jump; findings lines-vehicles "Year jump": accepted, getYear() follows at once). cb(success).
function X.setYear(y, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeGameSetDateCmd(api.type.Date.new(math.floor(y), 1, 1)),
			function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
	return ok
end

--- Calendar position in months (year x 12 + month - 1 + (day - 1) / 30) from the game time, or nil.
function X.calendarMonths()
	local ok, m = pcall(function()
		local gt = comp(api.engine.util.getWorld(), CT().GAME_TIME)
		local d = api.engine.util.getCalendarDate(gt.gameTime)
		return d.year * 12 + (d.month - 1) + ((d.day or 1) - 1) / 30
	end)
	if ok and type(m) == "number" then return m end
	return nil
end

---------------------------------------------------------------------------
-- Simulate natural growth (otd_simgrow)

--- A town's growth inputs: { initials {3}, sizeFactors {3}, active (developmentActive) } or nil.
function X.townGrowth(t)
	local tc = comp(t, CT().TOWN)
	if tc == nil then return nil end
	local ok, out = pcall(function()
		local o = { initials = {}, sizeFactors = {}, active = tc.developmentActive ~= false }
		for i = 1, 3 do
			o.initials[i] = tc.initialLandUseCapacities[i] or 0
			o.sizeFactors[i] = tc.sizeFactors[i] or 0
		end
		return o
	end)
	if ok then return out end
	return nil
end

--- The game's natural growth command: makeTownUpdateSizeCmd(town, sizeFactors, false) (town_growth.script.tl:550;
--- false = no immediate update of all buildings, the town developer builds at its own pace). all = true (Simulate's
--- Fast fill): updateAllBuildings, the houses come at once (up to ~300 per command, findings lines-vehicles).
--- cb(success).
function X.updateSize(t, factors, cb, all)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownUpdateSizeCmd(t, { factors[1], factors[2], factors[3] }, all == true),
			function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- baseConfig.economy.townDevelopment.townGrowthMinDistrictFraction (the game's minimum district weight) or nil.
function X.minDistrictWeight()
	local ok, v = pcall(function() return api.res.getBaseConfig().economy.townDevelopment.townGrowthMinDistrictFraction end)
	if ok and type(v) == "number" then return v end
	return nil
end

--- Buildings per town { [town] = count } from the town building map, or nil.
function X.buildingCounts()
	local ok, m = pcall(api.engine.system.townBuildingSystem.getTown2BuildingMap)
	if not ok or m == nil then return nil end
	local out = {}
	pcall(function()
		for t, list in pairs(m) do
			local okN, n = pcall(function() return #list end)
			out[t] = okN and n or 0
		end
	end)
	return out
end

--- A town's actual person capacity per district {res, com, ind} (townBuildingSystem.getLandUsePersonCapacities), or nil.
function X.landUse(t)
	local ok, c = pcall(api.engine.system.townBuildingSystem.getLandUsePersonCapacities, t)
	if not ok or c == nil then return nil end
	local out = {}
	local okR = pcall(function() for i = 1, 3 do out[i] = tonumber(c[i]) or 0 end end)
	if not okR then return nil end
	return out
end

--- Pushes the status table to the HUD (react.onEvent there). false when api.gui is missing in this state.
function X.pushStatus(status)
	local ok = pcall(api.gui.fireReactEvent, S.EV_STATUS, status)
	return ok
end

function X.log(line)
	log.message(line)
end

---------------------------------------------------------------------------
-- Test stops (2026-10-13, "Place test stops (named)"): one kerbside Road Stop on an existing town street edge, the
-- recipe square_stress_test verified in game (stress_buslines.tl stopProposal; docs/findings/lines-vehicles.md: 6 of 6
-- built): the edge is replaced by a copy (-1) carrying the stop (edge objects only go on new edges of the same proposal),
-- `objects` = { { -400000000 + index, STOP_RIGHT } }, the edge object at param 0.5 on the right; no new node, the two end
-- nodes' configs re-sent with the old edge re-pointed to -1 (read lane connections are read-only: rebuilt). An end node
-- without a config, or with traffic lights, is refused (never invent or break a config).

X.STOP_TEMP_ID = -400000000

--- The stop construction of the year (as square_stress_test bl.stopModel).
function X.stopModel()
	local ok, y = pcall(api.engine.util.getYear)
	y = ok and tonumber(y) or 2000
	if y >= 1980 then return "::/stations/street/small_stops/small_new.con" end
	if y >= 1920 then return "::/stations/street/small_stops/small_mid.con" end
	return "::/stations/street/small_stops/small_old.con"
end

local function remappedEntry(n, oldEdge, newId)
	local cfg = comp(n, CT().BASE_NODE_CONFIG)
	if cfg == nil then return nil end
	local list, cws = {}, {}
	local LC = api.type.LaneConnection
	for i = 1, #(cfg.laneConnections or {}) do
		local c = cfg.laneConnections[i]
		local lc = (LC ~= nil and LC.new ~= nil) and LC.new() or {}
		lc.segment0 = c.segment0 == oldEdge and newId or c.segment0
		lc.lane0 = c.lane0
		lc.segment1 = c.segment1 == oldEdge and newId or c.segment1
		lc.lane1 = c.lane1
		lc.withRoad, lc.withTram = c.withRoad, c.withTram
		list[#list + 1] = lc
	end
	for i = 1, #(cfg.crosswalks or {}) do
		local cw = cfg.crosswalks[i]
		cws[#cws + 1] = cw == oldEdge and newId or cw
	end
	local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
	entry.entity = n
	entry.comp = cfg
	entry.comp.laneConnections = list
	entry.comp.crosswalks = cws
	return entry
end

--- SimpleProposal: street edge `id` replaced by a copy with one Road Stop at its middle (right side), or nil and why.
function X.stopProposal(id, model, name)
	local be = comp(id, CT().BASE_EDGE)
	local bs = comp(id, CT().BASE_EDGE_STREET)
	if be == nil or bs == nil then return nil, "noEdge" end
	local n0, n1
	local okN = pcall(function() n0, n1 = be.node0, be.node1 end)
	if not okN or n0 == nil then return nil, "nodes" end
	for _, n in ipairs({ n0, n1 }) do
		if comp(n, CT().BASE_NODE_CONFIG) == nil then return nil, "noConfig" end
		if X.hasLights(n) then return nil, "lights" end
	end
	local p = api.type.SimpleProposal.new()
	local seg = api.type.SegmentAndEntity.new()
	seg.entity = -1
	seg.type = 0
	seg.comp = be
	seg.streetEdge = bs
	seg.comp.objects = { { X.STOP_TEMP_ID, api.type["enum"].EdgeObjectType.STOP_RIGHT } }
	local eo = api.type.SimpleStreetProposal.EdgeObject.new()
	eo.edgeEntity = -1
	eo.param = 0.5
	eo.oneWay = false
	eo.left = false
	eo.model = model
	pcall(function() eo.playerEntity = api.engine.util.getPlayer() end)
	eo.name = name
	local add, rm = {}, {}
	for _, n in ipairs({ n0, n1 }) do
		local entry = remappedEntry(n, id, -1)
		if entry == nil then return nil, "noConfig" end
		rm[#rm + 1] = n
		add[#add + 1] = entry
	end
	p.streetProposal.edgesToRemove = { id }
	p.streetProposal.edgesToAdd = { seg }
	p.streetProposal.edgeObjectsToAdd = { eo }
	p.streetProposal.nodeConfigsToRemove = rm
	p.streetProposal.nodeConfigsToAdd = add
	return p, nil
end

--- Every STATION_GROUP entity as a set (to find the new stop's group by diffing).
function X.stationGroups()
	local ok, list = pcall(api.engine.getEntitiesWithComponent, CT().STATION_GROUP)
	local set = {}
	if ok and list then for _, g in ipairs(list) do set[g] = true end end
	return set
end

return X
