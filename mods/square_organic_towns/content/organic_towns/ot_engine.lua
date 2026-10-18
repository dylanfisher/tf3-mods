-- Organic Towns: the engine layer (api.* reads, proposal objects, commands). Runs in the game script's
-- guiUpdate (Main Thread, docs/findings.md "Organic Towns probe": commands sent there get callbacks).
-- No decisions here: ot_driver decides, ot_proposal maps. Every read is pcall-guarded and returns plain
-- Lua tables. Copied and trimmed from the probe (otp_world.lua reads, otp_build.lua Builder:proposal and
-- precheck), never required from it.
--
-- Crash traps kept out (HANDOFF): never parcelSystem.getParcelData(edge) (native crash; the whole map from
-- getSegment2ParcelData() is read instead), nodeConfigsToRemove only for nodes with a BASE_NODE_CONFIG
-- (decided in ot_proposal), no rawget/rawset (nil in this state), no state:get_native.

local M = {}

M.MOD_ID = "square_organic_towns"

local function CT() return api.type.ComponentType end

function M.comp(e, ct)
	if e == nil or ct == nil then return nil end
	local ok, c = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

local clock = nil
function M.nowUs()
	if clock == nil then
		local ok, c = pcall(function() return api.type.Clock.new() end)
		if not ok or c == nil then return math.floor(os.clock() * 1e6) end
		clock = c
	end
	return clock:getTime()
end

--- An optional global (runFn's config) without rawget (nil in game-script states, findings.md).
function M.global(k)
	local ok, v = pcall(function() return _G[k] end)
	if ok then return v end
	return nil
end

function M.modParams()
	local ok, all = pcall(api.engine.config.getModParams)
	if not ok or type(all) ~= "table" then return nil, nil end
	return all[M.MOD_ID], all
end

--- baseConfig.locations.town.populationDensity as the game reads it at runtime (the "Starting town size" test:
--- base's "Population" setting x ours, ot_townsize), or nil.
function M.townPopulationDensity()
	local ok, v = pcall(function() return api.res.getBaseConfig().locations.town.populationDensity end)
	if ok and tonumber(v) then return math.floor(tonumber(v) * 1000 + 0.5) / 1000 end
	return nil
end

--- The simulation speed: the world's GAME_SPEED component, field speedup (api/tealdef engine.d.tl GameSpeed: "multiplier
--- for game simulation speed (non-negative, 0 = paused)"; read in game by Photo Mode and the Stress Test, findings
--- lines-vehicles "Speed 8 sticks"). nil when unreadable (the driver then counts the game as running).
function M.gameSpeed()
	local ok, v = pcall(function()
		return api.engine.getComponent(api.engine.util.getWorld(), CT().GAME_SPEED).speedup
	end)
	if ok and type(v) == "number" then return v end
	return nil
end

function M.gameTime()
	local gt = M.comp(api.engine.util.getWorld(), CT().GAME_TIME)
	return gt and gt.gameTime or 0
end

function M.year()
	local ok, d = pcall(api.engine.util.getCalendarDate, M.gameTime())
	if ok and d ~= nil and d.year then return d.year end
	local okY, y = pcall(api.engine.util.getYear)
	if okY and y then return y end
	return 1960
end

--- The game year with its fraction (year + (month - 1) / 12 + (day - 1) / 365; ot_satpace's game time), or nil.
function M.yearF()
	local ok, y = pcall(function()
		local d = api.engine.util.getCalendarDate(M.gameTime())
		if d == nil or not tonumber(d.year) then return nil end
		return d.year + ((tonumber(d.month) or 1) - 1) / 12 + ((tonumber(d.day) or 1) - 1) / 365
	end)
	if ok and tonumber(y) then return y end
	return nil
end

--- The map's bounding box { minX, minY, maxX, maxY } (m) from api.engine.terrain.getBoundingBox (the call
--- square_better_minimap uses in GUI scripts; ot_map map edge), or nil when it fails.
function M.mapBounds()
	local ok, bb = pcall(api.engine.terrain.getBoundingBox)
	if not ok or bb == nil then return nil end
	local ok2, b = pcall(function() return { bb.min.x, bb.min.y, bb.max.x, bb.max.y } end)
	if not ok2 or type(b) ~= "table" or not (tonumber(b[1]) and tonumber(b[2]) and tonumber(b[3]) and tonumber(b[4])) then return nil end
	return b
end

--- The bridge type index for a town street bridge in `year` (ot_bridge, 2026-10-13): the first of BRIDGE_PREFS that
--- exists and is available that year (availability yearFrom / yearTo, 0 = open; -1 = never), or nil. skip = { [path] =
--- true } (2026-10-14: a type a crossing was refused with, "Construction not possible" without a collision).
M.BRIDGE_PREFS = { "::/infrastructure/bridge/stone.bridge", "::/infrastructure/bridge/steel.bridge",
	"::/infrastructure/bridge/concrete.bridge" }
function M.bridgeType(year, skip)
	for _, path in ipairs(M.BRIDGE_PREFS) do
		local idx = (skip == nil or not skip[path]) and M.bridgeUsable(path, year) or nil
		if idx then return idx, path end
	end
	return nil, nil
end

--- The bridge type index of `path` when it exists and is available in `year`, else nil.
function M.bridgeUsable(path, year)
	local ok, idx, bt = pcall(function()
		local rep = api.res.bridgeTypeRep
		local i = rep.find(path)
		if i == nil or i < 0 then return nil, nil end
		return i, rep.get(i)
	end)
	if not (ok and idx and bt) then return nil end
	local okA, usable = pcall(function()
		local a = bt.availability
		local from, to = a and a.yearFrom or 0, a and a.yearTo or 0
		if from == -1 then return false end
		if from ~= 0 and year < from then return false end
		if to ~= 0 and year >= to then return false end
		-- (stone / steel / concrete carry RAIL and ROAD in the base game: base/content/infrastructure/bridge/
		-- *.bridge.lua; the carrier enum's runtime form is unverified, so it is not compared here)
		return true
	end)
	if okA and usable then return idx end
	return nil
end

function M.balance()
	local ok, b = pcall(function() return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer()) end)
	if ok then return b end
	return nil
end

---------------------------------------------------------------------------
-- Towns

--- Town entity ids, ascending.
function M.towns()
	local ok, list = pcall(api.engine.getEntitiesWithComponent, CT().TOWN)
	local out = {}
	if ok and list then
		for _, t in ipairs(list) do out[#out + 1] = t end
	end
	table.sort(out)
	return out
end

function M.name(e)
	local ok, n = pcall(api.engine.util.getEntityName, e)
	return ok and tostring(n) or "?"
end

--- Centre of an entity's BOUNDING_VOLUME (x, y) or nil. For a town this box is fixed (not its extent), so its
--- centre is the town's stable position (seed and plan centre).
function M.boxCentre(e)
	local bv = M.comp(e, CT().BOUNDING_VOLUME)
	if bv == nil then return nil end
	local ok, x, y = pcall(function()
		local b = bv.bbox
		return (b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2
	end)
	if not ok then return nil end
	return x, y
end

--- { target = Σ initial capacity x sizeFactor, actual = Σ land use person capacities, sizeFactors = {3},
--- initial = Σ initial land use capacities, initials = {3} (makeTownDevelopAtCmd resets them to the town's current
--- capacities: Showcase v5, findings "makeTownDevelopAtCmd raises the town's initial capacities"), active
--- (developmentActive) }.
function M.townCaps(t)
	local tc = M.comp(t, CT().TOWN)
	if tc == nil then return nil end
	local out = { target = 0, actual = 0, sizeFactors = {}, initial = 0, initials = {} }
	pcall(function() out.active = tc.developmentActive ~= false end)
	pcall(function()
		for i = 1, 3 do
			out.sizeFactors[i] = tc.sizeFactors[i]
			out.initials[i] = tc.initialLandUseCapacities[i]
			out.initial = out.initial + tc.initialLandUseCapacities[i]
			out.target = out.target + tc.initialLandUseCapacities[i] * tc.sizeFactors[i]
		end
	end)
	pcall(function()
		local c = api.engine.system.townBuildingSystem.getLandUsePersonCapacities(t)
		-- (2026-10-14: per land use too, CHECK `uses=`: are a Works town's 200 industrial persons built as industry?)
		out.uses = {}
		for i = 1, 3 do
			out.actual = out.actual + (c[i] or 0)
			out.uses[i] = c[i] or 0
		end
	end)
	return out
end

---------------------------------------------------------------------------
-- Industries (away from industries, ot_industry)

--- Every industry on the map: { {x, y, file} } (file = its construction's CONSTRUCTION.fileName, "" if unknown).
--- Read as the base statistics window lists them (getEntitiesWithComponent(INDUSTRY), statistic_industries.tl:392)
--- and square_industry_flows resolves them (getConstructionEntityForSubconstruction -> CONSTRUCTION.fileName, the
--- industry entity's BOUNDING_VOLUME centre); getConstructionEntityForIndustry as a fallback. Read-only, pcall-guarded
--- per industry; nil when the listing itself fails.
function M.industries()
	local ok, list = pcall(api.engine.getEntitiesWithComponent, CT().INDUSTRY)
	if not ok or list == nil then return nil end
	local out = {}
	for _, e in ipairs(list) do
		local x, y = M.boxCentre(e)
		local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction, e)
		if not okC or con == nil or con < 0 then
			okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForIndustry, e)
		end
		local file = ""
		if okC and con ~= nil and con >= 0 then
			local c = M.comp(con, CT().CONSTRUCTION)
			local okF, f = pcall(function() return c and c.fileName end)
			if okF and f ~= nil then file = tostring(f) end
			if x == nil then x, y = M.boxCentre(con) end
		end
		if x ~= nil then out[#out + 1] = { x, y, file = file, e = e } end
	end
	return out
end

---------------------------------------------------------------------------
-- Rail passenger stations (M3 station quarter, ot_motif_town). Read from the tealdefs and base files 2026-10-13, not
-- verified in a game-script state (docs/findings/towns.md "Listing rail stations"): stationSystem.getTown2StationsMap()
-- (every station, keyed by town; getEntitiesWithComponent(STATION) as a fallback), the station's construction
-- (streetConnectorSystem.getConstructionEntityForStation; kerbside stops have none), a rail station's
-- CONSTRUCTION.fileName under `stations/rail/` (or the group's carriers holding RAIL), a passenger station
-- (util.station.isStationOfType(station, false)), the position from the construction's transform (BOUNDING_VOLUME
-- centre as the fallback) and the forecourt direction = the transform's local -Y (the modular station's main building
-- faces -Y: main_building_1_era_a.module.lua, its linkable person lanes at y = -17).

local function stationList()
	local out, seen = {}, {}
	local okM, map = pcall(api.engine.system.stationSystem.getTown2StationsMap)
	if okM and map ~= nil then
		pcall(function()
			for _, list in pairs(map) do
				for i = 1, #list do
					local st = list[i]
					if not seen[st] then seen[st] = true; out[#out + 1] = st end
				end
			end
		end)
	end
	if #out == 0 then
		local okE, list = pcall(api.engine.getEntitiesWithComponent, CT().STATION)
		if okE and list then
			for _, st in ipairs(list) do
				if not seen[st] then seen[st] = true; out[#out + 1] = st end
			end
		end
	end
	return out
end

local function isRail(file, st)
	local f = string.lower(file or "")
	if f:find("stations/rail/", 1, true) or f:find("station/rail/", 1, true) then return true end
	if f:find("stations/", 1, true) or f:find("station/", 1, true) then return false end
	local ok, r = pcall(function()
		local grp = api.engine.system.stationGroupSystem.getStationGroup(st)
		local c = api.engine.system.stationGroupSystem.getCarriers(grp, -1, -1)
		local rail = api.type["enum"].Carrier.RAIL
		for _, k in pairs(c[1] or {}) do if k == rail then return true end end
		return false
	end)
	return ok and r == true
end

---------------------------------------------------------------------------
-- Ship lines and the water level (round R6, 2026-10-13; read from the tealdefs, NOT verified in a game script:
-- docs/findings/roads.md "A low road bridge cuts a ship lane", research in PLAN.md 6.3 "Forest / gaps / bridges round").
-- lineSystem.getLines(); a water line: util.line.getLineTransportModesUnion(line)[SHIP | SMALL_SHIP] (the base line
-- manager's test, line_util.tl), else the LINE component's vehicleInfo.transportModes; its stops (LINE.stops:
-- stationGroup, station index) -> the station's construction (or the group) box centre; its vehicles
-- (transportVehicleSystem.getLineVehicles). Read-only, every call pcall-guarded, at most MAX_LINES lines.
M.MAX_LINES = 2000

--- Every ship line: { { line, stops = { {x, y} }, vehicles } }, and the count of lines read; nil, why when the listing fails.
function M.shipLines()
	local okL, lines = pcall(api.engine.system.lineSystem.getLines)
	if not okL or lines == nil then return nil, "noLines" end
	local okT, tm = pcall(function() return api.type["enum"].TransportMode end)
	if not okT or tm == nil then return nil, "noEnum" end
	local out, n = {}, 0
	for i = 1, math.min(#lines, M.MAX_LINES) do
		local ln = lines[i]
		n = n + 1
		pcall(function()
			local water = false
			local okU, modes = pcall(api.engine.util.line.getLineTransportModesUnion, ln)
			if okU and modes then water = modes[tm.SHIP] == true or modes[tm.SMALL_SHIP] == true end
			local lc = M.comp(ln, CT().LINE)
			if not water and lc and lc.vehicleInfo and lc.vehicleInfo.transportModes then
				local v = lc.vehicleInfo.transportModes
				water = v[tm.SHIP] == true or v[tm.SMALL_SHIP] == true
			end
			if not water or lc == nil then return end
			local rec = { line = ln, stops = {}, vehicles = 0 }
			for k = 1, #lc.stops do
				local st = lc.stops[k]
				local x, y
				pcall(function()
					local list = M.groupStations(st.stationGroup)
					local sid = list[(tonumber(st.station) or 0) + 1] or list[1]
					if sid then
						local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, sid)
						if okC and con and con >= 0 then x, y = M.boxCentre(con) end
						if x == nil then x, y = M.boxCentre(sid) end
					end
					if x == nil then x, y = M.boxCentre(st.stationGroup) end
				end)
				if x then rec.stops[#rec.stops + 1] = { x, y } end
			end
			pcall(function()
				local vs = api.engine.system.transportVehicleSystem.getLineVehicles(ln)
				rec.vehicles = vs and #vs or 0
			end)
			out[#out + 1] = rec
		end)
	end
	return out, n
end

--- The water level (m): the TERRAIN component of the heightmap tile at (0, 0) (`waterLevel`), else 0 (sea level 0 m,
--- docs/findings/map-camera.md, assumed). Returns level, source ("terrain" | "default").
function M.waterLevel()
	local ok, v = pcall(function()
		local e = api.engine.terrain.getHeightmapEntity(api.type.Vec2i.new(0, 0))
		local t = M.comp(e, CT().TERRAIN)
		return t and tonumber(t.waterLevel) or nil
	end)
	if ok and v and v == v and math.abs(v) < 1e4 then return v, "terrain" end
	return 0, "default"
end

--- Every rail passenger station on the map: { { x, y, fx, fy (forecourt unit vector or nil), front = {x, y} or nil,
--- box = {x0, y0, x1, y1} or nil, file, id = construction } }, one per construction; nil when the listing fails.
function M.railStations()
	local ok, sts = pcall(stationList)
	if not ok or sts == nil then return nil end
	local out, seenCon = {}, {}
	for _, st in ipairs(sts) do
		pcall(function()
			local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, st)
			if not okC or con == nil or con < 0 or seenCon[con] then return end
			local c = M.comp(con, CT().CONSTRUCTION)
			if c == nil then return end
			local okF, file = pcall(function() return tostring(c.fileName) end)
			file = okF and file or ""
			if not isRail(file, st) then return end
			local okP, pass = pcall(api.engine.util.station.isStationOfType, st, false)
			if okP and pass == false then return end
			seenCon[con] = true
			local x, y, fx, fy
			pcall(function()
				local p = c.transf:getTransl()
				x, y = p.x, p.y
			end)
			pcall(function()
				local d = c.transf:transformDirection(api.type.Vec3f.new(0, -1, 0))
				fx, fy = d.x, d.y
			end)
			if x == nil or fx == nil then
				-- (a transform read as 16 numbers, column-major: local Y = entries 5, 6; the origin = 13, 14)
				pcall(function()
					local t = c.transf
					if x == nil and tonumber(t[13]) then x, y = t[13], t[14] end
					if fx == nil and tonumber(t[5]) then fx, fy = -t[5], -t[6] end
				end)
			end
			if x == nil then x, y = M.boxCentre(con) end
			if x == nil then return end
			local rec = { x = x, y = y, file = file, id = con }
			local l = fx and math.sqrt(fx * fx + fy * fy) or 0
			if l > 1e-6 then
				rec.fx, rec.fy = fx / l, fy / l
				rec.front = { x + rec.fx * 17, y + rec.fy * 17 }
			end
			local bv = M.comp(con, CT().BOUNDING_VOLUME)
			if bv then
				pcall(function()
					local b = bv.bbox
					rec.box = { b.min.x, b.min.y, b.max.x, b.max.y }
				end)
			end
			out[#out + 1] = rec
		end)
	end
	return out
end

--- Every harbour on the map (industrial satellites, ot_works 2026-10-13; read like railStations: the station's
--- construction file under `stations/water/`, base harbor_modular.con): { { x, y, id = construction } }, nil on error.
function M.harbours()
	local okS, sts = pcall(stationList)
	if not okS or sts == nil then return nil end
	local out, seenCon = {}, {}
	for i, st in ipairs(sts) do
		if i > 20000 then break end
		pcall(function()
			local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, st)
			if not okC or con == nil or con < 0 or seenCon[con] then return end
			local c = M.comp(con, CT().CONSTRUCTION)
			if c == nil then return end
			local okF, file = pcall(function() return string.lower(tostring(c.fileName)) end)
			if not (okF and (file:find("stations/water/", 1, true) or file:find("station/water/", 1, true))) then return end
			seenCon[con] = true
			local x, y = M.boxCentre(con)
			if x then out[#out + 1] = { x = x, y = y, id = con } end
		end)
	end
	return out
end

--- Creates a town (industrial satellites, ot_works 2026-10-13; the dev probe's path, verified in game 2026-10-13:
--- mapgen.createTowns lays out a Map.Town at the position, its TownInfo gets the initial land use capacities and the
--- name, makeTownCreateCmd builds it). o = { x, y, name, caps = {r, c, i}, seed }. cb(success). Returns sent, info.
function M.createTown(o, cb)
	local info = {}
	local ok, err = pcall(function()
		local t = api.type.Map.Town.new()
		t.pos = api.type.Vec2f.new(o.x, o.y)
		t.name = o.name
		t.sizeFactors = { 1, 1, 1 }
		local res = api.engine.mapgen.createTowns(o.seed or "sqot", { t })
		if res == nil or res.toAdd == nil or #res.toAdd == 0 then error("createTowns returned nothing to add") end
		local ti = res.toAdd[1]
		ti.initialLandUseCapacities = { o.caps[1], o.caps[2], o.caps[3] }
		ti.position = api.type.Vec2f.new(o.x, o.y)
		pcall(function() ti.name = o.name end)
		api.cmd.sendCommand(api.cmd.makeTownCreateCmd({ ti }), function(_data, success) cb(success == true) end)
	end)
	if not ok then
		info.err = tostring(err)
		return false, info
	end
	return true, info
end

local function parcelCT()
	local ok, ct = pcall(function() return CT().PARCEL end)
	if ok then return ct end
	return nil
end

--- The town's building positions { {x, y} } and built parcels per street edge { [edge] = count }.
--- town2buildings: the getTown2BuildingMap result (read once per check).
function M.townBuildings(t, town2buildings)
	local pts, builtBy = {}, {}
	local list = town2buildings and town2buildings[t] or {}
	local pct = parcelCT()
	for _, b in ipairs(list) do
		local x, y = M.boxCentre(b)
		local tb = M.comp(b, CT().TOWN_BUILDING)
		if x == nil and tb ~= nil then x, y = M.boxCentre(tb.construction) end
		if x ~= nil then pts[#pts + 1] = { x, y } end
		if tb ~= nil and pct ~= nil then
			pcall(function()
				for i = 1, #tb.parcels do
					local pc = M.comp(tb.parcels[i], pct)
					if pc ~= nil then builtBy[pc.streetSegment] = (builtBy[pc.streetSegment] or 0) + 1 end
				end
			end)
		end
	end
	return pts, builtBy
end

function M.town2buildings()
	local ok, m = pcall(api.engine.system.townBuildingSystem.getTown2BuildingMap)
	if ok then return m end
	return nil
end

--- The whole segment -> ParcelData map. NEVER parcelSystem.getParcelData(edge): native crash (probe J).
function M.parcelMap()
	local ok, m = pcall(api.engine.system.parcelSystem.getSegment2ParcelData)
	if ok then return m end
	return nil
end

--- Parcel count of one ParcelData (probe J: #leftEntities + #rightParcels; other spellings tried too).
function M.parcelCount(pd)
	local n = 0
	for _, k in ipairs({ "leftEntities", "rightParcels", "leftParcels", "rightEntities" }) do
		local ok, v = pcall(function() return pd[k] end)
		if ok and v ~= nil then
			local okN, c = pcall(function() return #v end)
			if okN and type(c) == "number" then n = n + c end
		end
	end
	return n
end

function M.closestTown(x, y)
	local ok, t = pcall(api.engine.util.town.getClosestTown, api.type.Vec3f.new(x, y, 0))
	if not ok or t == nil or t < 0 then return nil end
	return t
end

---------------------------------------------------------------------------
-- Streets

--- Street edges whose BASE_EDGE lies within r of (x, y), as plain tables: { id, n0, n1, p0, p1, t0, t1,
--- template, lanes, owned, objects, inConstruction, locked }.
local function edgeTable(e)
	if M.comp(e, CT().BASE_EDGE_STREET) == nil then return nil end
	local be = M.comp(e, CT().BASE_EDGE)
	if be == nil then return nil end
	local okE, ed = pcall(function()
		return {
			id = e, n0 = be.node0, n1 = be.node1,
			p0 = { be.position0.x, be.position0.y, be.position0.z },
			p1 = { be.position1.x, be.position1.y, be.position1.z },
			t0 = { be.tangent0.x, be.tangent0.y, be.tangent0.z },
			t1 = { be.tangent1.x, be.tangent1.y, be.tangent1.z },
			template = tostring(be.roadTemplate), lanes = be.laneConfigs ~= nil and #be.laneConfigs or 0,
			objects = be.objects ~= nil and #be.objects or 0, locked = be.roadDevelopmentLocked == true,
		}
	end)
	if not okE or ed == nil then return nil end
	-- (§67: bridges and tunnels are never rebuilt locked; "normal" | "bridge" | "tunnel" | nil unknown)
	pcall(function()
		local BT = api.type.enum.BaseEdgeType
		ed.etype = (be.type == BT.BRIDGE and "bridge") or (be.type == BT.TUNNEL and "tunnel") or "normal"
	end)
	ed.owned = M.comp(e, CT().PLAYER_OWNED) ~= nil
	local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForEdge, e)
	ed.inConstruction = okC and con ~= nil and con >= 0
	return ed
end

--- Street edges within r of (x, y) (edgeTable records), at most MAX_STREETS (audit 2026-10-13: uncapped before; a
--- capped read sets M.streetsCapped = the octree's count for the caller's log).
M.MAX_STREETS = 6000
function M.streets(x, y, r)
	local out = {}
	M.streetsCapped = nil
	if x ~= x or y ~= y or not (r and r > 0 and r < 1e5) then return out end
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, CT().BASE_EDGE)
	if not ok or list == nil then return out end
	if #list > M.MAX_STREETS then M.streetsCapped = #list end
	for i = 1, math.min(#list, M.MAX_STREETS) do
		local ed = edgeTable(list[i])
		if ed ~= nil then out[#out + 1] = ed end
	end
	return out
end

--- Obstacles around (x, y) within r for a satellite site and its link (2026-10-13, real map run 2026-10-13_0342_sqot:
--- three of four satellite seeds were refused by the pre-check, "Collision" with entities outside the town's snapshot):
--- { segs = { {x0, y0, x1, y1, id = edge, kind = "street"|"track", town = bool} }, boxes = { {x0, y0, x1, y1, id, kind =
--- "con"|"field"} } }: every BASE_EDGE (streets of any template and tracks; a curved edge as two chords through its
--- Hermite midpoint) and the bounding boxes of constructions (industries, stations, depots) and farm FIELDs. Capped at
--- MAX_OBSTACLES each; pcall-guarded, read-only.
M.MAX_OBSTACLES = 6000
function M.obstacles(x, y, r)
	local out = { segs = {}, boxes = {} }
	local centre = api.type.Vec2f.new(x, y)
	local okE, list = pcall(api.engine.util.octree.findEntitiesInCircle, centre, r, CT().BASE_EDGE)
	if okE and list then
		for i = 1, math.min(#list, M.MAX_OBSTACLES) do
			local e = list[i]
			local be = M.comp(e, CT().BASE_EDGE)
			if be then
				pcall(function()
					local street = M.comp(e, CT().BASE_EDGE_STREET) ~= nil
					local tpl = street and tostring(be.roadTemplate) or ""
					local p0, p1, t0, t1 = be.position0, be.position1, be.tangent0, be.tangent1
					local mx = (p0.x + p1.x) / 2 + (t0.x - t1.x) / 8
					local my = (p0.y + p1.y) / 2 + (t0.y - t1.y) / 8
					local kind = street and "street" or "track"
					local town = tpl:find("town_", 1, true) ~= nil
					out.segs[#out.segs + 1] = { p0.x, p0.y, mx, my, id = e, kind = kind, town = town }
					out.segs[#out.segs + 1] = { mx, my, p1.x, p1.y, id = e, kind = kind, town = town }
				end)
			end
		end
	end
	for _, spec in ipairs({ { "con", CT().CONSTRUCTION }, { "field", CT().FIELD } }) do
		local okC, cl = pcall(api.engine.util.octree.findEntitiesInCircle, centre, r, spec[2])
		if okC and cl then
			for i = 1, math.min(#cl, M.MAX_OBSTACLES) do
				local e = cl[i]
				local bv = M.comp(e, CT().BOUNDING_VOLUME)
				if bv then
					pcall(function()
						local b = bv.bbox
						out.boxes[#out.boxes + 1] = { b.min.x, b.min.y, b.max.x, b.max.y, id = e, kind = spec[1] }
					end)
				end
			end
		end
	end
	return out
end

--- What an entity is, for refusal logs (`partners=`): "street", "track", "node", "con", "field", "building", "town" or
--- "?" (2026-10-13: the satellites' collision partners were unknown entities).
function M.entityKind(e)
	if type(e) ~= "number" or e < 0 then return "?" end
	if M.comp(e, CT().BASE_EDGE_STREET) ~= nil then return "street" end
	if M.comp(e, CT().BASE_EDGE) ~= nil then return "track" end
	if M.comp(e, CT().BASE_NODE) ~= nil then return "node" end
	if M.comp(e, CT().FIELD) ~= nil then return "field" end
	if M.comp(e, CT().TOWN_BUILDING) ~= nil then return "building" end
	if M.comp(e, CT().CONSTRUCTION) ~= nil then return "con" end
	if M.comp(e, CT().SUBCONSTRUCTION) ~= nil then return "subcon" end
	return "?"
end

--- One street edge as M.streets gives it (nil: gone or not a street). The driver follows a town's network
--- beyond the snapshot circle with it (ot_driver.townNetwork).
function M.edge(e)
	if type(e) ~= "number" or e < 0 then return nil end
	return edgeTable(e)
end

--- Street edges at a node (the true degree; a snapshot circle can cut a node's other edges off).
function M.nodeStreetEdges(n)
	local ok, l = pcall(api.engine.system.streetSystem.getNodeStreetSegments, n)
	local out = {}
	if ok and l then
		for i = 1, #l do out[#out + 1] = l[i] end
	end
	return out
end

function M.hasConfig(n)
	return M.comp(n, CT().BASE_NODE_CONFIG) ~= nil
end

function M.nodeInConstruction(n)
	local ok, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForNode, n)
	return not ok or (con ~= nil and con >= 0)
end

---------------------------------------------------------------------------
-- Trees around a town (phase F forest-aware towns, ot_forest; read from the game files 2026-10-13, NOT verified in a
-- game script: docs/findings/towns.md "Reading trees near a town"). Trees are ASSET_GROUP entities (map-generated forest,
-- the player's tree brush, reforestation) whose MODEL_INSTANCE_LIST holds the trees as fat (Mat4f transf) or thin (pos)
-- instances; a model is a tree when `api.res.modelRep.get(id).metadata.tree` is set (as the base construction menu and
-- the subscribed schbrongx_minimap test it). The reader lists the groups in one octree call, then reads them a slice
-- at a time: per group at most a share of FO.READ_MAX instance reads (stride; each read tree counts `stride` trees).
-- Read-only, every call pcall-guarded.

--- A sliced tree reader around (cx, cy) within r. o = { readMax, add = function(x, y, w) }.
--- reader:step(maxUs) reads until maxUs have passed and returns true when done; reader.stats = { groups, reads,
--- trees (weighted), models, nonTree, stride (max), capped, err }.
M.READ_CHECK = 256
function M.forestReader(cx, cy, r, o)
	local rd = { stats = { groups = 0, reads = 0, trees = 0, nonTree = 0, stride = 1, capped = false, err = nil,
		listUs = 0 }, gi = 0, done = false }
	local isTree = {}
	-- (stop names 2026-10-13: the species of each tree model from its file name, ot_stopname.species, for o.species)
	local speciesOf = {}
	local function treeModel(id)
		local v = isTree[id]
		if v == nil then
			local ok, t = pcall(function()
				local m = api.res.modelRep.get(id)
				return m ~= nil and m.metadata ~= nil and m.metadata.tree ~= nil
			end)
			v = ok and t == true
			isTree[id] = v
			if v and o.speciesOf then
				local okN, name = pcall(api.res.modelRep.getName, id)
				speciesOf[id] = (okN and o.speciesOf(name)) or false
			end
		end
		return v
	end
	function rd:list()
		local t0 = M.nowUs()
		local ct = CT().ASSET_GROUP
		if ct == nil then
			self.stats.err = "noAssetGroupType"
			self.groups = {}
			return
		end
		local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(cx, cy), r, ct)
		if not ok then self.stats.err = "octree:" .. tostring(list) end
		self.groups = (ok and list) or {}
		self.stats.groups = #self.groups
		self.stats.listUs = M.nowUs() - t0
		-- per group read budget: the total spread evenly over the groups (at least 4 each); a hard stop at 2 x readMax
		-- (capped)
		self.perGroup = math.max(4, math.floor((o.readMax or 24000) / math.max(1, #self.groups)))
		self.readStop = 2 * (o.readMax or 24000)
	end
	-- (audit 2026-10-13: a single big group read up to readMax instances in one slice; now the clock is checked every
	-- READ_CHECK reads and the group resumes next slice from `from`: returns the next index, or nil when the group is done)
	local function readGroup(self, e, from, t0, maxUs)
		local mil = M.comp(e, CT().MODEL_INSTANCE_LIST)
		if mil == nil then return end
		local okD, dyn = pcall(function() return mil.dynamic end)
		if okD and dyn == true then return end
		local fat, thin = mil.fatInstances_native, mil.thinInstances_native
		local nf = (fat and fat:size()) or 0
		local nt = (thin and thin:size()) or 0
		local n = nf + nt
		if n == 0 then return end
		local stride = math.max(1, math.ceil(n / self.perGroup))
		if from == nil then
			if stride > self.stats.stride then self.stats.stride = stride end
			if stride > 1 then self.stats.capped = true end
		end
		-- (a seeded start within the stride: the instances' order within a group is unknown)
		local i = from or (1 + (e % stride))
		local k = 0
		while i <= n do
			local x, y, id
			if i <= nf then
				local inst = fat:at(i)
				id = inst.modelId
				local p = inst.transf:getTransl()
				x, y = p.x, p.y
			else
				local inst = thin:at(i - nf)
				id = inst.modelId
				x, y = inst.pos.x, inst.pos.y
			end
			self.stats.reads = self.stats.reads + 1
			if treeModel(id) then
				self.stats.trees = self.stats.trees + stride
				if o.add then o.add(x, y, stride) end
				local sp = speciesOf[id]
				if sp and o.species then o.species(sp, stride) end
			else
				self.stats.nonTree = self.stats.nonTree + 1
			end
			i = i + stride
			k = k + 1
			if k % M.READ_CHECK == 0 and i <= n and M.nowUs() - t0 >= maxUs then return i end
		end
		return nil
	end
	function rd:step(maxUs)
		if self.done then return true end
		local t0 = M.nowUs()
		if self.groups == nil then
			self:list()
			return false   -- (the octree call is this tick's slice)
		end
		local budget = maxUs or 3000
		if self.cur then
			local e = self.cur.e
			local ok, nxt = pcall(readGroup, self, e, self.cur.i, t0, budget)
			if not ok and self.stats.err == nil then self.stats.err = "read:" .. tostring(nxt) end
			self.cur = (ok and nxt) and { e = e, i = nxt } or nil
			if self.cur or M.nowUs() - t0 >= budget then return false end
		end
		while self.gi < #self.groups do
			if self.stats.reads >= self.readStop then
				self.stats.capped = true
				break
			end
			self.gi = self.gi + 1
			local e = self.groups[self.gi]
			local ok, nxt = pcall(readGroup, self, e, nil, t0, budget)
			if not ok and self.stats.err == nil then self.stats.err = "read:" .. tostring(nxt) end
			if ok and nxt then
				self.cur = { e = e, i = nxt }
				return false
			end
			if M.nowUs() - t0 >= budget then return false end
		end
		self.done = true
		return true
	end
	return rd
end

---------------------------------------------------------------------------
-- Terrain sampler (ot_terrain interface), memoised on a 2 m grid for one check

-- (hang fix 2026-10-13: a NaN / infinite / absurd coordinate never reaches the engine's terrain queries; it reads as
-- dry ground at height 0, and NaN can't become a cache key)
M.SAMPLE_MAX = 1e6
local function badXY(x, y)
	return x ~= x or y ~= y or x == nil or y == nil or math.abs(x) > M.SAMPLE_MAX or math.abs(y) > M.SAMPLE_MAX
end
M.badXY = badXY

function M.sampler()
	local hCache, wCache = {}, {}
	local function key(x, y)
		return (math.floor(x / 2 + 0.5) + 50000) * 100000 + (math.floor(y / 2 + 0.5) + 50000)
	end
	return {
		height = function(x, y)
			if badXY(x, y) then return 0 end
			local k = key(x, y)
			local v = hCache[k]
			if v == nil then
				local ok, h = pcall(api.engine.terrain.getHeightAt, api.type.Vec2f.new(x, y))
				v = ok and h or 0
				hCache[k] = v
			end
			return v
		end,
		water = function(x, y)
			if badXY(x, y) then return false end
			local k = key(x, y)
			local v = wCache[k]
			if v == nil then
				local ok, w = pcall(api.engine.terrain.isOnWater, api.type.Vec2f.new(x, y))
				v = ok and w == true
				wCache[k] = v
			end
			return v
		end,
		waterLevel = 0,
	}
end

---------------------------------------------------------------------------
-- Proposal objects (from an ot_proposal spec)

local function vec3(v)
	local function z(a) if a == 0 then return 0.0 end return a end
	return api.type.Vec3f.new(z(v[1]), z(v[2]), z(v[3] or 0))
end

local function newLC()
	local LC = api.type.LaneConnection
	if LC ~= nil and LC.new ~= nil then return LC.new() end
	return {}
end

local templateCache = {}
local function template(path)
	local t = templateCache[path]
	if t == nil then
		local ok, tpl = pcall(function()
			return api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(path))
		end)
		t = ok and tpl or false
		templateCache[path] = t
	end
	return t or nil
end

--- Every road edge (not a track) within r of (x, y), read wide for the country roads (2026-10-13, after the final test:
--- the town snapshot's `E.streets` gave no non-town edge in any town, though earlier tour shots show dirt country roads
--- leaving towns): { list = { { id, n0, n1, p0, p1, t0, t1, template, country (the template's `country` flag, nil when
--- the template didn't resolve), street (has BASE_EDGE_STREET) } }, stats = { edges, streets, noStreetComp, tracks,
--- country, town, other, templates = { short = n } } }. Capped at MAX_ROAD_EDGES; pcall-guarded, read-only.
M.MAX_ROAD_EDGES = 3000
function M.roadEdges(x, y, r)
	local out = { list = {}, stats = { edges = 0, streets = 0, noStreetComp = 0, tracks = 0, country = 0, town = 0, other = 0,
		templates = {} } }
	local st = out.stats
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, CT().BASE_EDGE)
	if not ok or list == nil then st.err = tostring(list); return out end
	local trackType = nil
	pcall(function() trackType = api.type.RoadType.TRACK end)
	for i = 1, math.min(#list, M.MAX_ROAD_EDGES) do
		local e = list[i]
		local be = M.comp(e, CT().BASE_EDGE)
		if be then
			st.edges = st.edges + 1
			pcall(function()
				local street = M.comp(e, CT().BASE_EDGE_STREET) ~= nil
				local isTrack = trackType ~= nil and be.roadType == trackType
				if isTrack and not street then st.tracks = st.tracks + 1; return end
				if street then st.streets = st.streets + 1 else st.noStreetComp = st.noStreetComp + 1 end
				local path = tostring(be.roadTemplate)
				local tpl = template(path)
				local country = nil
				if tpl then country = tpl.country == true end
				local short = path:match("([%w_]+)%.street_template") or path
				st.templates[short] = (st.templates[short] or 0) + 1
				if country then st.country = st.country + 1
				elseif path:find("town_", 1, true) then st.town = st.town + 1
				else st.other = st.other + 1 end
				out.list[#out.list + 1] = {
					id = e, n0 = be.node0, n1 = be.node1,
					p0 = { be.position0.x, be.position0.y, be.position0.z },
					p1 = { be.position1.x, be.position1.y, be.position1.z },
					t0 = { be.tangent0.x, be.tangent0.y, be.tangent0.z },
					t1 = { be.tangent1.x, be.tangent1.y, be.tangent1.z },
					template = path, country = country, street = street,
				}
			end)
		end
	end
	return out
end

--- true when the base town template resource exists (the era's templates must resolve).
--- Lane count (incl. sidewalks) of a street template, or nil.
function M.templateLanes(path)
	local tpl = template(path)
	if not tpl then return nil end
	local ok, n = pcall(function() return #tpl.laneConfigs end)
	return ok and n or nil
end

function M.templateExists(path)
	return template(path) ~= nil
end

--- SimpleProposal for a spec. Not player owned, no edge objects, locked only where the spec says so.
function M.proposal(spec)
	local nodes = {}
	for _, nd in ipairs(spec.nodes) do
		local ne = api.type.NodeAndEntity.new()
		ne.entity = nd.entity
		ne.comp.position = vec3(nd.pos)
		nodes[#nodes + 1] = ne
	end
	local edges = {}
	for _, sp in ipairs(spec.edges) do
		local seg = api.type.SegmentAndEntity.new()
		seg.entity = sp.entity
		seg.type = 0
		seg.comp = api.engine.getComponent(sp.src, CT().BASE_EDGE)
		seg.streetEdge = api.engine.getComponent(sp.src, CT().BASE_EDGE_STREET)
		seg.comp.node0 = sp.node0
		seg.comp.node1 = sp.node1
		seg.comp.position0 = vec3(sp.p0)
		seg.comp.position1 = vec3(sp.p1)
		seg.comp.tangent0 = vec3(sp.t0)
		seg.comp.tangent1 = vec3(sp.t1)
		seg.comp.objects = {}
		-- shaped towns' arm / rim streets (ot_driver.lockKeys) and the dev lock probe; else unlocked
		seg.comp.roadDevelopmentLocked = sp.locked == true
		if sp.bridge then
			-- a river bridge (ot_bridge, 2026-10-13): BaseEdgeType BRIDGE with the bridge type index (Move It's
			-- ground -> bridge conversion sets the same two fields); a failure aborts the whole proposal
			local okB, errB = pcall(function()
				seg.comp.type = api.type.enum.BaseEdgeType.BRIDGE
				seg.comp.typeIndex = sp.bridge
			end)
			if not okB then error("bridge edge fields: " .. tostring(errB)) end
		else
			pcall(function()
				seg.comp.type = 0
				seg.comp.typeIndex = -1
			end)
		end
		if sp.override then
			local tpl = template(sp.override)
			if tpl == nil then error("street template not found: " .. tostring(sp.override)) end
			seg.comp.roadTemplate = sp.override
			seg.comp.laneConfigs = tpl.laneConfigs
			seg.comp.roadStyle = tpl.streetStyle
		end
		-- tree-lined entries (ot_entry, later-ideas phase; ot_proposal `decor`): "template" = the `_trees` template's own
		-- default decorations (the base track builder's way: edgeDecorationRep.find of each default), "none" = no
		-- decorations (a street continuing from a tree-lined dead end). A decoration that can't be resolved leaves the
		-- edge as the plain template (same lanes), counted in M.treesFallback.
		if sp.decor == "none" then
			pcall(function() seg.comp.edgeDecorations = {} end)
		elseif sp.decor == "template" then
			local okD = pcall(function()
				local tpl = template(sp.override)
				local list = {}
				for _, v in ipairs(tpl.defaultEdgeDecorations or {}) do
					local id = api.res.edgeDecorationRep.find(v[1])
					if id == nil or id < 0 then error("decoration not found: " .. tostring(v[1])) end
					list[#list + 1] = { id, v[2] == true }
				end
				if #list == 0 then error("no default decorations") end
				seg.comp.edgeDecorations = list
			end)
			if not okD then
				M.treesFallback = (M.treesFallback or 0) + 1
				local plain = sp.override:gsub("_trees%.street_template$", ".street_template")
				local tpl = template(plain)
				if tpl == nil then error("street template not found: " .. tostring(plain)) end
				seg.comp.roadTemplate = plain
				seg.comp.laneConfigs = tpl.laneConfigs
				seg.comp.roadStyle = tpl.streetStyle
				pcall(function() seg.comp.edgeDecorations = {} end)
			end
		end
		edges[#edges + 1] = seg
	end
	local cfgAdd = {}
	for _, c in ipairs(spec.cfgAdd) do
		local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
		entry.entity = c.node
		local cfg = c.node >= 0 and M.comp(c.node, CT().BASE_NODE_CONFIG) or nil
		if cfg ~= nil then entry.comp = cfg end    -- keeps its crosswalks, as the probe's verified D3 joint
		local conns = {}
		for _, cn in ipairs(c.conns) do
			local lc = newLC()
			lc.segment0 = cn[1]
			lc.lane0 = cn[2]
			lc.segment1 = cn[3]
			lc.lane1 = cn[4]
			lc.withRoad = cn[5] ~= false
			lc.withTram = false
			conns[#conns + 1] = lc
		end
		entry.comp.laneConnections = conns
		cfgAdd[#cfgAdd + 1] = entry
	end
	local p = api.type.SimpleProposal.new()
	p.streetProposal.nodesToAdd = nodes
	p.streetProposal.edgesToAdd = edges
	p.streetProposal.edgesToRemove = {}
	p.streetProposal.nodesToRemove = {}
	-- ot_proposal lists only nodes whose BASE_NODE_CONFIG exists; re-checked here right before sending
	local remove = {}
	for _, n in ipairs(spec.cfgRemove) do
		if M.hasConfig(n) then remove[#remove + 1] = n end
	end
	p.streetProposal.nodeConfigsToRemove = remove
	p.streetProposal.nodeConfigsToAdd = cfgAdd
	return p
end

--- §67 (2026-10-15): a proposal that rebuilds existing town street edges between their SAME two nodes, locked
--- (roadDevelopmentLocked = true; nothing can set it in place, findings towns.md). The pattern of move_it's
--- buildEdgeAbsTangentProposal: each edge's own BASE_EDGE / BASE_EDGE_STREET copied (template, lanes, style,
--- decorations, geometry; -0 normalized), edgesToRemove = the old edge, no node added or removed; every end node with a
--- BASE_NODE_CONFIG gets it back (remove + add, only when it exists) with its lane connections and crosswalks re-pointed
--- from the old edge to the new one, in their order (traffic light phases index them). Each edge is checked again here:
--- it must exist, be a street, unlocked, not the player's, without edge objects, NORMAL (no bridge / tunnel), not a
--- loop, and neither it nor its nodes owned by a construction. ids = edge ids. Returns proposal, list ({ old, entity,
--- n0, n1, len }) for the edges kept, skipped ({ [id] = why }); proposal nil when none is left.
function M.lockProposal(ids)
	local skipped, list = {}, {}
	local segs, old2new, nodes = {}, {}, {}
	local nodeSeen = {}
	local BT = api.type.enum.BaseEdgeType
	for _, id in ipairs(ids or {}) do
		local why = nil
		local okX, ex = pcall(api.engine.entityExists, id)
		if not okX or not ex then why = "gone" end
		local be = why == nil and M.comp(id, CT().BASE_EDGE) or nil
		local bs = why == nil and M.comp(id, CT().BASE_EDGE_STREET) or nil
		if why == nil and (be == nil or bs == nil) then why = "notStreet" end
		if why == nil then
			local okF, w = pcall(function()
				if be.roadDevelopmentLocked then return "locked" end
				if be.type ~= BT.NORMAL then return "bridge" end
				if be.objects ~= nil and #be.objects > 0 then return "objects" end
				if be.node0 == be.node1 then return "loop" end
				return nil
			end)
			-- (not `okF and w or "read"`: w is nil for a lockable edge, which read as "read" and refused every edge;
			-- console probe 2026-10-15, edge 103287)
			if okF then why = w else why = "read" end
		end
		if why == nil and M.comp(id, CT().PLAYER_OWNED) ~= nil then why = "player" end
		if why == nil then
			local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForEdge, id)
			if not okC or (con ~= nil and con >= 0) then why = "construction" end
		end
		if why == nil and (M.nodeInConstruction(be.node0) or M.nodeInConstruction(be.node1)) then why = "nodeConstruction" end
		if why == nil and old2new[id] then why = "twice" end
		if why ~= nil then
			skipped[id] = why
		else
			local entity = -(#segs + 1)
			local okS, seg = pcall(function()
				local sg = api.type.SegmentAndEntity.new()
				sg.entity = entity
				sg.type = 0
				sg.comp = be
				sg.streetEdge = bs
				sg.comp.position0 = vec3({ be.position0.x, be.position0.y, be.position0.z })
				sg.comp.position1 = vec3({ be.position1.x, be.position1.y, be.position1.z })
				sg.comp.tangent0 = vec3({ be.tangent0.x, be.tangent0.y, be.tangent0.z })
				sg.comp.tangent1 = vec3({ be.tangent1.x, be.tangent1.y, be.tangent1.z })
				sg.comp.objects = {}
				sg.comp.roadDevelopmentLocked = true
				return sg
			end)
			if not okS then
				skipped[id] = "segment"
			else
				segs[#segs + 1] = seg
				old2new[id] = entity
				local p0, p1 = be.position0, be.position1
				list[#list + 1] = { old = id, entity = entity, n0 = be.node0, n1 = be.node1,
					len = math.sqrt((p1.x - p0.x) ^ 2 + (p1.y - p0.y) ^ 2) }
				for _, n in ipairs({ be.node0, be.node1 }) do
					if not nodeSeen[n] then nodeSeen[n] = true; nodes[#nodes + 1] = n end
				end
			end
		end
	end
	if #segs == 0 then return nil, list, skipped end
	local cfgAdd, cfgRemove = {}, {}
	for _, n in ipairs(nodes) do
		local cfg = M.comp(n, CT().BASE_NODE_CONFIG)
		if cfg ~= nil then
			local okC, entry = pcall(function()
				local ae = api.type.BaseNodeLaneConnectionAndEntity.new()
				ae.entity = n
				ae.comp = cfg
				local conns = {}
				for i = 1, #cfg.laneConnections do
					local lc = cfg.laneConnections[i]
					lc.segment0 = old2new[lc.segment0] or lc.segment0
					lc.segment1 = old2new[lc.segment1] or lc.segment1
					conns[#conns + 1] = lc
				end
				ae.comp.laneConnections = conns
				local cw = {}
				for i = 1, #cfg.crosswalks do cw[#cw + 1] = old2new[cfg.crosswalks[i]] or cfg.crosswalks[i] end
				ae.comp.crosswalks = cw
				return ae
			end)
			if not okC then error("node config " .. tostring(n) .. ": " .. tostring(entry)) end
			cfgRemove[#cfgRemove + 1] = n
			cfgAdd[#cfgAdd + 1] = entry
		end
	end
	local removeIds = {}
	for _, e in ipairs(list) do removeIds[#removeIds + 1] = e.old end
	local p = api.type.SimpleProposal.new()
	p.streetProposal.nodesToAdd = {}
	p.streetProposal.edgesToAdd = segs
	p.streetProposal.edgesToRemove = removeIds
	p.streetProposal.nodesToRemove = {}
	p.streetProposal.nodeConfigsToRemove = cfgRemove
	p.streetProposal.nodeConfigsToAdd = cfgAdd
	return p, list, skipped
end

--- The street edge between nodes n0 and n1 other than `old` (the rebuilt one after a lock build), its locked flag; nil.
function M.edgeBetween(n0, n1, old)
	for _, e in ipairs(M.nodeStreetEdges(n0)) do
		if e ~= old then
			local be = M.comp(e, CT().BASE_EDGE)
			if be ~= nil and ((be.node0 == n0 and be.node1 == n1) or (be.node0 == n1 and be.node1 == n0)) then
				return e, be.roadDevelopmentLocked == true
			end
		end
	end
	return nil
end

--- Context: terrain alignment checked, no street graph cleanup, no player unless asPlayer == true.
--- Without a player the build is free and the streets are the town's (2026-10-17, session 2026-10-17_1841_sqot:
--- BUILT balance unchanged at cost 63098; findings towns.md). With one the player pays (the driver books it back,
--- Driver:refundBuild) and the streets may count as the player's.
function M.context(asPlayer)
	local ctx = api.type.Context.new()
	-- (the 2026-10-11 crash first blamed on the missing player was the new nodes' missing configs: findings towns.md;
	-- the dev tools' "Build as player" toggle, ot_hooks.player = true, sends with one)
	if asPlayer == true then pcall(function() ctx.player = api.engine.util.getPlayer() end) end
	ctx.checkTerrainAlignment = true
	ctx.cleanupStreetGraph = false
	ctx.gatherBuildings = true
	ctx.gatherFields = true
	return ctx
end

--- makeProposalData pre-check: { ok, critical, msgs = {}, buildings, collisions, cost, us, err }.
function M.precheck(proposal, ctx)
	local t0 = M.nowUs()
	local ok, pd = pcall(api.engine.util.proposal.makeProposalData, proposal, ctx)
	local r = { us = M.nowUs() - t0, ok = false, msgs = {}, buildings = 0, collisions = 0 }
	if not ok or pd == nil then
		r.err = tostring(pd)
		return r
	end
	pcall(function()
		local es = pd.errorState
		r.critical = es.critical == true
		for i = 1, #(es.messages or {}) do r.msgs[#r.msgs + 1] = tostring(es.messages[i]) end
	end)
	pcall(function() r.cost = pd.costs end)
	pcall(function() r.buildings = #(pd.collisionInfo.buildingEntities or {}) end)
	pcall(function()
		local ce = pd.collisionInfo.collisionEntities or {}
		r.collisions = #ce
		if r.collisions > 0 then
			r.partners = {}
			for i = 1, math.min(#ce, 8) do
				local v = ce[i]
				-- CollisionInfo.EntityData { entity } (type.d.tl ProposalData)
				if type(v) ~= "number" then pcall(function() v = v.entity end) end
				r.partners[#r.partners + 1] = tonumber(v) or -1
			end
		end
	end)
	r.ok = not r.critical and #r.msgs == 0 and r.buildings == 0
	return r
end

--- Sends the build (playerInitiated = false: no reputation effect, PLAN.md 2.3 step 8). cb(success, info)
--- with info = { msgs, cost } from the command data, on the Main Thread a frame after the command ran.
function M.sendBuild(proposal, ctx, cb)
	local cmd = api.cmd.makeWorldBuildProposalCmd(proposal, ctx, false, false)
	api.cmd.sendCommand(cmd, function(data, success)
		local info = { msgs = {} }
		pcall(function()
			local es = data.resultProposalData.errorState
			info.critical = es.critical
			for i = 1, #(es.messages or {}) do info.msgs[#info.msgs + 1] = tostring(es.messages[i]) end
		end)
		pcall(function() info.cost = data.resultProposalData.costs end)
		cb(success == true, info)
	end)
end

--- Books amount (> 0) back to the player as street construction income (every mod build's refund, Driver:refundBuild;
--- makeJournalBookAssetCmd as square_full_refund / square_stress_test book, findings debugging.md). cb(success) or nil.
function M.bookStreetRefund(amount, cb)
	local ok, err = pcall(function()
		local e = api.type.JournalEntry.new()
		e.amount = math.floor(amount)
		e.time = -1
		e.category.type = api.type.JournalEntry.Type.CONSTRUCTION
		e.category.construction = api.type.JournalEntry.Construction.STREET
		api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), e, api.type.Vec3f.new(0, 0, 0)),
			function(_d, success) if cb then cb(success == true) end end)
	end)
	if not ok and cb then cb(false, err) end
	return ok
end

--- Saved-state event to the game script's handleEvent (square_problem_radar's sendEvent pattern).
function M.sendEvent(id, name, param)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", id, name, param))
end

--- An entity's creation revision (api.engine.getRevision num[1], as base entity_util.makeEntityAndRevision0), or nil:
--- the new-town notification's click checks it so a reused id never jumps to another town (2026-10-17).
function M.revision(e)
	local ok, r = pcall(function()
		if not api.engine.entityExists(e) then return nil end
		return api.engine.getRevision(e).num[1]
	end)
	if ok and type(r) == "number" then return r end
	return nil
end

function M.log(line)
	log.message(line)
end

--- Testing param: scale a town's size factors (makeTownUpdateSizeCmd, as the probe's Grow here). cb(success).
function M.growTown(t, factors, cb)
	api.cmd.sendCommand(api.cmd.makeTownUpdateSizeCmd(t, factors, true), function(_data, success)
		cb(success == true)
	end)
end

--- Town development at a position: makeTownDevelopAtCmd(position, developStreets, upgradeBuildings) ("new
--- buildings or street segments are added at the given position"; the undo_tf3 mod rebuilds a house with
--- (pos, false, false)). The driver's fill beside new arm streets (ot_driver FILL). cb(success).
function M.developAt(x, y, streets, upgrade, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownDevelopAtCmd(api.type.Vec2f.new(x, y), streets == true, upgrade == true),
			function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- Town development on (makeTownSetDevelopmentActiveCmd(t, true)): only to undo a switch-off that followed our own
--- dose fill (ot_driver FILL reactivate, 2026-10-13). cb(success).
function M.setDevelopmentActive(t, on, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownSetDevelopmentActiveCmd(t, on == true), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- A town's transport supply as the base game's growth reads it (§66, ot_rci.usage): { line = getTownLineUsage, mult =
--- town_util.LineUsageRatingMultiplier, res / com / ind = { supply, demand } summed over the land use's cargo types }
--- through the base helpers (town_util.getCargoSupplyDemands, town_growth.script.tl:377-412), or nil when they can't be
--- read. Every call pcall-guarded.
local townUtil = nil
function M.townSupply(t)
	if townUtil == nil then
		local ok, tu = pcall(ug_require, "::/game_mechanics/towns/town_util.tl")
		townUtil = (ok and type(tu) == "table" and type(tu.getCargoSupplyDemands) == "function") and tu or false
	end
	if not townUtil then return nil end
	local okS, sd = pcall(townUtil.getCargoSupplyDemands, t)
	if not okS or type(sd) ~= "table" then return nil end
	local okL, line = pcall(function() return api.engine.util.town.getTownLineUsage(t) end)
	local function sum(list)
		local s, d = 0, 0
		for i, c in ipairs(list or {}) do
			if i > 64 then break end
			s = s + (tonumber(c.supply) or 0)
			d = d + (tonumber(c.demand) or 0)
		end
		return { s, d }
	end
	return { line = okL and tonumber(line) or 0, mult = tonumber(townUtil.LineUsageRatingMultiplier) or 2,
		res = sum(sd.residential), com = sum(sd.commercial), ind = sum(sd.industrial) }
end

--- Sets a town's initial land use capacities (makeTownSetInitialLandUseCapacitiesCmd; the town editor's command):
--- the driver's fill puts them back after DevelopAt reset them (FILL restore), and the supply-driven weighting (§66,
--- Driver:rciTown) re-splits them: the one writer of a town's initial capacities. list = {3} integers. cb(success).
function M.setInitialCaps(t, list, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeTownSetInitialLandUseCapacitiesCmd(t, { list[1], list[2], list[3] }),
			function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

---------------------------------------------------------------------------
-- Level weights (2026-10-14 late, ot_upward.levelDecide; findings towns.md "Per-town building levels")

local function rows4(v)
	if v == nil then return nil end
	local out = {}
	for i = 1, 3 do
		local r = v[i]
		if r == nil then return nil end
		local row = {}
		for l = 1, 4 do
			local x = tonumber(r[l])
			if x == nil then return nil end
			row[l] = x
		end
		out[i] = row
	end
	return out
end

--- A town's building levels: { custom = the TOWN component's levelToCapacityDistributionWeights as {{4} x 3} or nil
--- (the game's default), actual / unweighted / weighted = the capacity per level and land use
--- (api.engine.util.town.compute{Actual,UnweightedTarget,WeightedTarget}TownBuildingCapacityPerType, as the base debug
--- panel lists them) or nil }. Every read pcall-guarded; nil when the town has no TOWN component.
function M.levelInfo(t)
	local tc = M.comp(t, CT().TOWN)
	if tc == nil then return nil end
	local out = {}
	pcall(function() out.custom = rows4(tc.levelToCapacityDistributionWeights) end)
	-- (unset might read as an empty or all-zero list rather than nil: all zero counts as the game's default)
	if out.custom then
		local sum = 0
		for i = 1, 3 do for l = 1, 4 do sum = sum + math.abs(out.custom[i][l]) end end
		if sum == 0 then out.custom = nil end
	end
	local u = api.engine.util and api.engine.util.town
	if u then
		pcall(function() out.actual = rows4(u.computeActualTownBuildingCapacityPerType(t)) end)
		pcall(function() out.unweighted = rows4(u.computeUnweightedTargetTownBuildingCapacityPerType(t)) end)
		pcall(function() out.weighted = rows4(u.computeWeightedTargetTownBuildingCapacityPerType(t)) end)
	end
	return out
end

--- Sets (weights = {{4} x 3} numbers) or clears (nil: the game's default) a town's level weights
--- (makeTownCustomDistributionWeightsCmd, the town editor's command). cb(success).
function M.setLevelWeights(t, weights, cb)
	local ok = pcall(function()
		local w = nil
		if weights ~= nil then
			w = {}
			for i = 1, 3 do w[i] = { weights[i][1] + 0.0, weights[i][2] + 0.0, weights[i][3] + 0.0, weights[i][4] + 0.0 } end
		end
		api.cmd.sendCommand(api.cmd.makeTownCustomDistributionWeightsCmd(t, w), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

---------------------------------------------------------------------------
-- Landscape names (ot_names, 2026-10-13; not verified in game yet: PLAN.md "Landscape names" open questions)

--- The game language code (api.util.getLanguage(), "language settings" per api/tealdef/api/util.d.tl:270; its fields
--- are undocumented, so .code / .lang / .language / [1] are tried) or nil, and a short text of what came back (log).
function M.language()
	local ok, r = pcall(function() return api.util.getLanguage() end)
	if not ok then return nil, "err:" .. tostring(r) end
	if r == nil then return nil, "nil" end
	if type(r) == "string" then return r, "string" end
	local code = nil
	for _, k in ipairs({ "code", "lang", "language", 1 }) do
		local okK, v = pcall(function() return r[k] end)
		if okK and type(v) == "string" and v ~= "" then code = v break end
		if okK and v ~= nil and code == nil then
			local okC, c = pcall(function() return v.code end)
			if okC and type(c) == "string" and c ~= "" then code = c break end
		end
	end
	local parts = {}
	pcall(function()
		for k, v in pairs(r) do
			if #parts >= 8 then break end
			parts[#parts + 1] = tostring(k) .. ":" .. tostring(v)
		end
	end)
	return code, (#parts > 0 and table.concat(parts, ",") or type(r))
end

--- A base name list's towns (the file names.script.lua requires: "::/names/<path>/<dir>/towns.lua", a plain
--- `return { ... }`), or nil and the error.
function M.townList(path, dir)
	local ok, list = pcall(ug_require, "::/names/" .. tostring(path) .. "/" .. tostring(dir) .. "/towns.lua")
	if not ok then return nil, tostring(list) end
	if type(list) ~= "table" then return nil, "type:" .. type(list) end
	return list, nil
end

--- Renames an entity (makeEntitySetNameCmd, the base windows' rename command). cb(success); a send error -> cb(false).
function M.setName(e, name, cb)
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(e, name), function(_data, success) cb(success == true) end)
	end)
	if not ok then cb(false) end
end

--- Every industry's entity and name ({ {id, name} }, at most `max`; the name the statistics window shows:
--- getEntityName(industry entity), base gui/statistics/statistic_industries.tl:356).
function M.industryNames(max)
	local ok, list = pcall(api.engine.getEntitiesWithComponent, CT().INDUSTRY)
	local out = {}
	if not ok or list == nil then return out end
	for _, e in ipairs(list) do
		if #out >= (max or 4000) then break end
		local okN, n = pcall(api.engine.util.getEntityName, e)
		if okN and type(n) == "string" then out[#out + 1] = { id = e, name = n } end
	end
	return out
end

---------------------------------------------------------------------------
-- Landscape stop names (ot_names stop part; the state names mods' pattern, templates/state_names/content/
-- rename.script.lua: collect in onPostBuildProposal, rename later; here from the driver in guiUpdate with a callback)

local PLACEHOLDER_BASE = -400000000   -- edge objects of a proposal get placeholder ids from here (base town_util.tl)

local function nonEmpty(v)
	if v == nil then return false end
	local okN, n = pcall(function() return #v end)
	return not okN or n == nil or n > 0
end

--- The new player Road Stops of an onPostBuildProposal event param ({ proposal, ..., result entities, player build }):
--- { {st, g, n, x, y} } (edge objects of category 0 with a real station id, not carried over from an old object: a road
--- upgrade re-creates stops). Never sends a command. Empty for anything else.
function M.collectStops(param)
	local found = {}
	if type(param) ~= "table" or param[1] == nil or param[4] ~= true then return found end
	pcall(function()
		local sp = param[1].proposal
		local n2o, renewed = nil, nil
		local eos = sp.edgeObjectsToAdd or {}
		for i, eo in ipairs(eos) do
			if #found >= 32 then break end
			local id = eo.resultEntity
			if eo.category == 0 and type(id) == "number" and id >= 0 then
				if n2o == nil then
					n2o = sp.new2oldEdgeObjects
					renewed = {}
					pcall(function()
						for _, news in pairs(sp.old2newEdgeObjects or {}) do
							for _, nw in ipairs(news) do renewed[nw] = true end
						end
					end)
				end
				local carried = renewed[id] == true
				if not carried and n2o ~= nil then
					pcall(function()
						if nonEmpty(n2o[PLACEHOLDER_BASE + i - 1]) or nonEmpty(n2o[id]) then carried = true end
					end)
				end
				if not carried then
					local x, y
					pcall(function()
						local t = eo.modelInstance.transf
						local okT, p = pcall(function() return t:getTransl() end)
						if okT and p then x, y = p.x, p.y else x, y = t[13], t[14] end
					end)
					local okG, g = pcall(api.engine.system.stationGroupSystem.getStationGroup, id)
					g = okG and tonumber(g) or -1
					local n = nil
					if g >= 0 then
						local okN, nm = pcall(api.engine.util.getEntityName, g)
						if okN and type(nm) == "string" then n = nm end
					end
					found[#found + 1] = { st = id, g = g, n = n, x = tonumber(x), y = tonumber(y) }
				end
			end
		end
	end)
	-- new player stations (rail / harbour / bus and truck station constructions; the state names mods' collect): only
	-- brand-new ones (no removal in the proposal: an upgrade or rebuild removes the old construction). They are named
	-- only beside an industry (ot_stopname.stationName). k = "rail" | "harbor" | "street".
	pcall(function()
		local p = param[1]
		local removes = 0
		pcall(function() removes = #(p.toRemove or {}) end)
		if removes ~= 0 then return end
		for _, e in ipairs(param[3] or {}) do
			if #found >= 32 then break end
			if type(e) == "number" and e >= 0 then
				local con = M.comp(e, CT().CONSTRUCTION)
				local f = con and string.lower(tostring(con.fileName or "")) or ""
				local k = (f:find("stations/rail/", 1, true) and "rail") or (f:find("stations/water/", 1, true) and "harbor")
					or (f:find("stations/street/", 1, true) and "street") or nil
				if k then
					local x, y = M.boxCentre(e)
					for _, st in ipairs(con.stations or {}) do
						local okG, g = pcall(api.engine.system.stationGroupSystem.getStationGroup, st)
						g = okG and tonumber(g) or -1
						local n = nil
						if g >= 0 then
							local okN, nm = pcall(api.engine.util.getEntityName, g)
							if okN and type(nm) == "string" then n = nm end
						end
						found[#found + 1] = { st = st, g = g, n = n, x = tonumber(x), y = tonumber(y), k = k }
					end
				end
			end
		end
	end)
	return found
end

--- Whether the street stop st at (x, y) sits on a bridge (ot_stopname bridge stops, 2026-10-14; not yet verified in
--- game): the BASE_EDGEs within r (STOP_BRIDGE_R), the stop's own edge (the one whose `objects` list holds st), and the
--- bridge edges among them (BaseEdge `type` == api.type.enum.BaseEdgeType.BRIDGE) as two chords through the Hermite
--- midpoint. Returns { read = the stop's edge was found, on = that edge is a bridge, edge = its id, bridges = { { x0, y0,
--- x1, y1, ends = { {x, y}, {x, y} }, id } }, n = edges read }. Read-only, every read pcall-guarded, capped.
M.STOP_BRIDGE_R = 80
M.STOP_BRIDGE_MAX = 200
function M.stopBridge(st, x, y, r)
	local out = { read = false, on = false, bridges = {}, n = 0 }
	if not tonumber(x) or not tonumber(y) or x ~= x or y ~= y then return out end
	local okT, BT = pcall(function() return api.type.enum.BaseEdgeType.BRIDGE end)
	if not okT then BT = nil end
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r or M.STOP_BRIDGE_R,
		CT().BASE_EDGE)
	if not ok or list == nil then out.err = "octree"; return out end
	for i = 1, math.min(#list, M.STOP_BRIDGE_MAX) do
		local e = list[i]
		local be = M.comp(e, CT().BASE_EDGE)
		if be then
			out.n = out.n + 1
			pcall(function()
				local ty = be.type
				local isB = (BT ~= nil and ty == BT) or ty == 1
				if type(st) == "number" and be.objects ~= nil then
					for k = 1, math.min(#be.objects, 64) do
						local o = be.objects[k]
						local id = nil
						pcall(function() id = o[1] end)
						if id == st then out.read, out.on, out.edge = true, isB, e break end
					end
				end
				if isB then
					local p0, p1, t0, t1 = be.position0, be.position1, be.tangent0, be.tangent1
					local mx = (p0.x + p1.x) / 2 + (t0.x - t1.x) / 8
					local my = (p0.y + p1.y) / 2 + (t0.y - t1.y) / 8
					local ends = { { p0.x, p0.y }, { p1.x, p1.y } }
					out.bridges[#out.bridges + 1] = { p0.x, p0.y, mx, my, ends = ends, id = e }
					out.bridges[#out.bridges + 1] = { mx, my, p1.x, p1.y, ends = ends, id = e }
				end
			end)
		end
	end
	return out
end

--- A station's group (or nil).
function M.stationGroup(st)
	local ok, g = pcall(api.engine.system.stationGroupSystem.getStationGroup, st)
	if ok and tonumber(g) and g >= 0 then return g end
	return nil
end

--- A station group's stations ({ ids }).
function M.groupStations(g)
	local sg = M.comp(g, CT().STATION_GROUP)
	local out = {}
	if sg == nil then return out end
	pcall(function()
		for _, s in ipairs(sg.stations or {}) do out[#out + 1] = s end
	end)
	return out
end

--- A station's town (or nil).
function M.stationTown(st)
	local ok, t = pcall(api.engine.system.stationSystem.getTown, st)
	if ok and tonumber(t) and t >= 0 then return t end
	return nil
end

--- The names of a town's station groups (every station of the town; skip: a group left out). { [name] = true }.
function M.townStopNames(town, skip)
	local out = {}
	local ok, sts = pcall(api.engine.system.stationSystem.getStations, town)
	if not ok or sts == nil then return out end
	local seen = {}
	pcall(function()
		for i, st in ipairs(sts) do
			if i > 2000 then break end
			local g = M.stationGroup(st)
			if g and g ~= skip and not seen[g] then
				seen[g] = true
				out[M.name(g)] = true
			end
		end
	end)
	return out
end

--- Every station group entity on the map (a list; stop names unique map-wide, read live per stop: ot_driver stopUsed).
function M.stationGroups()
	local ok, list = pcall(api.engine.getEntitiesWithComponent, CT().STATION_GROUP)
	if not ok or list == nil then return {} end
	return list
end

--- Every station group's name on the map ({ [name] = true }; skip: a group left out), at most max groups (stop names
--- unique map-wide, ot_stopname).
function M.mapStopNames(skip, max)
	local out = {}
	local ok, list = pcall(api.engine.getEntitiesWithComponent, CT().STATION_GROUP)
	if not ok or list == nil then return out end
	for i, g in ipairs(list) do
		if i > (max or 20000) then break end
		if g ~= skip then
			local okN, n = pcall(api.engine.util.getEntityName, g)
			if okN and type(n) == "string" then out[n] = true end
		end
	end
	return out
end

--- A base name list's street names ("::/names/<path>/<dir>/streets.lua"), or nil and the error.
function M.streetList(path, dir)
	local ok, list = pcall(ug_require, "::/names/" .. tostring(path) .. "/" .. tostring(dir) .. "/streets.lua")
	if not ok then return nil, tostring(list) end
	if type(list) ~= "table" then return nil, "type:" .. type(list) end
	return list, nil
end

--- os.time() (stop queue ages).
function M.osTime()
	local ok, t = pcall(os.time)
	return ok and t or 0
end

return M
