-- DEV ONLY probe for the planned square_town_street_names mod. Plan: plans/square_town_street_names/PROBE.md.
--
-- Logs greppable "[SQTSN_PROBE] ..." lines to stdout.txt:
--   init / dump      once per Lua state: towns, which entity kinds carry a NAME, a sample of station groups
--   event / gui      the first 3 of every game-script event kind (engine + GUI thread) with a payload summary
--   build            every onPre/PostBuildProposal: constructions, edge objects (stops), result entities
--   NEW group/station  every station group or station that appears (polling every 2 s, or right after a build)
--   name change      any watched town / station group / station whose name or NAME component changes
--   rename           the opt-in rename test (mod param "Rename test (DEV)", default Off)
--
-- Read-only unless the rename test is on. Plain Lua (pre-5.3: no //, no math.tointeger, no utf8).
-- Exports through data() (memory: script-lua-exports-via-data). Commands are only sent from update,
-- never inside a build event (memory: gs-no-sendcommand-in-build-events). Lazy init: works when added
-- to an existing save. Every entry point is wrapped in pcall; errors are logged once per message.

local TAG = "[SQTSN_PROBE] "
local MOD_ID = "square_town_street_names_probe"
local SCAN_SECONDS = 2
local STATE_V = 1

-- Set to "off" | "group" | "stem" | "force" to override the mod param without the mod settings dialog.
local RENAME_TEST_OVERRIDE = nil
-- Names used by the rename test, in order. Two equal names on purpose: does the engine accept a
-- duplicate stop name, or append "#2" / "East" etc. (NameSystem::FirstNonExistingWithNumber)?
local RENAME_NAMES = { "Pike Street", "Pike Street", "Pine Street", "Madison Street", "Union Street", "Spring Street" }
local RENAME_MAX = 6
-- Construction stations (bus/tram/train station, airport, harbour) get a name without "Station", so the
-- verify line shows whether the engine appends " Station" to the group name (plans/square_state_names).
local RENAME_CON_NAMES = { "King Street", "Union Station", "Sea-Tac Airport", "Colman Dock", "Westlake", "Everett Station" }

local WATCH_CAP = 400          -- watched entities for the name-change watcher
local WATCH_EXISTING_GROUPS = 150
local DUMP_GROUPS = 25
local DUMP_TOWNS = 60
local CENSUS_CAP = 30000
local EVENT_LOG_PER_KIND = 3

local moduleToken = tostring({}):match("0x(%x+)") or tostring({})
local dumpedThisState = false
local lastScan = 0
local eventCounts = {}
local guiEventCounts = {}
local lastEventSummary = 0
local warned = {}
local guiLoaded = false
local subscribedMode = nil
local pendingScan = false
local lastBuild = nil    -- module-local: tells whether build events and update share a Lua state

---------------------------------------------------------------------------
-- Logging helpers

local function log(msg)
	print(TAG .. msg)
end

local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	log("ERROR " .. msg)
end

local function q(s)
	if s == nil then return "nil" end
	return string.format("%q", tostring(s))
end

local function try(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	return nil
end

---------------------------------------------------------------------------
-- Engine reads (all pcall-guarded)

local CT = nil
local function ct()
	if CT == nil then CT = api.type.ComponentType end
	return CT
end

local function getComp(e, t)
	if e == nil or e < 0 then return nil end
	return try(function() return api.engine.getComponent(e, t) end)
end

local function exists(e)
	if e == nil or e < 0 then return false end
	return try(api.engine.entityExists, e) == true
end

local function nameComp(e)
	local c = getComp(e, ct().NAME)
	if c == nil then return nil end
	return c.name
end

local function entName(e)
	return try(api.engine.util.getEntityName, e)
end

local function stemOf(e)
	local r = try(api.engine.util.getEntityNameStem, e)
	if type(r) ~= "table" and type(r) ~= "userdata" then return nil, nil end
	local ok, n, se = pcall(function() return r[1], r[2] end)
	if not ok then return nil, nil end
	return n, se
end

--- "NAME=<comp or none> name=<getEntityName> stem=<stem>@<entity>"
local function names(e)
	local nc = nameComp(e)
	local sn, se = stemOf(e)
	return string.format("NAME=%s name=%s stem=%s@%s", nc ~= nil and q(nc) or "none", q(entName(e)), q(sn), tostring(se))
end

local function pos(e)
	local bv = getComp(e, ct().BOUNDING_VOLUME)
	if bv ~= nil then
		local p = try(function()
			local mn, mx = bv.bbox.min, bv.bbox.max
			return { (mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2 }
		end)
		if p ~= nil then return p, "bv" end
	end
	local eo = getComp(e, ct().EDGE_OBJECT)
	if eo ~= nil then
		local p = try(function()
			local m = eo.transf
			return { m[13], m[14], m[15] }
		end)
		if p ~= nil and p[1] ~= nil then return p, "eo" end
		p = try(function()
			local c = eo.transf:cols(3)
			return { c.x, c.y, c.z }
		end)
		if p ~= nil then return p, "eo-cols" end
	end
	return nil, "none"
end

local function fmtPos(p)
	if p == nil then return "nil" end
	return string.format("(%.0f,%.0f,%.0f)", p[1] or 0, p[2] or 0, p[3] or 0)
end

local function dist2d(a, b)
	local dx, dy = a[1] - b[1], a[2] - b[2]
	return math.sqrt(dx * dx + dy * dy)
end

local function entities(t)
	local r = try(api.engine.getEntitiesWithComponent, t)
	if r == nil then return {} end
	return r
end

---------------------------------------------------------------------------
-- Towns

local function townList()
	local out = {}
	for _, t in ipairs(entities(ct().TOWN)) do
		out[#out + 1] = { e = t, name = entName(t), p = pos(t) }
	end
	return out
end

local function townLabel(t)
	if t == nil or t < 0 then return tostring(t) end
	return tostring(t) .. "=" .. q(entName(t))
end

--- Every way we know to get a town for a station / position.
local function townInfo(station, p)
	local parts = {}
	local viaStation = station and try(api.engine.system.stationSystem.getTown, station) or nil
	parts[#parts + 1] = "stationSystem.getTown " .. townLabel(viaStation)
	if p ~= nil then
		local closest = try(function()
			return api.engine.util.town.getClosestTown(api.type.Vec3f.new(p[1], p[2], p[3]))
		end)
		parts[#parts + 1] = "util.town.getClosestTown " .. townLabel(closest)
		local best, bestD = nil, nil
		for _, t in ipairs(townList()) do
			if t.p ~= nil then
				local d = dist2d(p, t.p)
				if bestD == nil or d < bestD then best, bestD = t, d end
			end
		end
		if best ~= nil then
			parts[#parts + 1] = string.format("nearestCentre %s d=%.0f", townLabel(best.e), bestD)
		end
	end
	return table.concat(parts, " | ")
end

---------------------------------------------------------------------------
-- Stations

--- The street edge carrying an edge-object stop, found through BaseEdge.objects near its position.
local function edgeOfStop(station, p)
	if p == nil then return nil end
	local edges = try(function()
		return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(p[1], p[2]), 40, ct().BASE_EDGE)
	end) or {}
	for _, edge in ipairs(edges) do
		local be = getComp(edge, ct().BASE_EDGE)
		if be ~= nil then
			local hit = try(function()
				for _, o in ipairs(be.objects or {}) do
					if o[1] == station then return true end
				end
				return false
			end)
			if hit then return edge end
		end
	end
	return nil
end

local function stationKind(st)
	if getComp(st, ct().EDGE_OBJECT) ~= nil then return "edgeObject" end
	local con = try(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, st)
	if con ~= nil and con >= 0 then return "construction" end
	return "other"
end

local function describeStation(st, indent)
	local p, psrc = pos(st)
	local kind = stationKind(st)
	log(string.format("%sstation %d kind=%s %s pos=%s(%s)", indent, st, kind, names(st), fmtPos(p), psrc))
	if kind == "edgeObject" then
		local eo = getComp(st, ct().EDGE_OBJECT)
		local eoc = eo and try(function() return eo.edgeObjectConstruction end) or nil
		local param = eo and try(function() return eo.param end) or nil
		local edge = edgeOfStop(st, p)
		log(string.format("%s  edgeObjectConstruction=%s param=%s edge=%s %s", indent, q(eoc), tostring(param),
			tostring(edge), edge and names(edge) or ""))
	end
	local con = try(api.engine.system.streetConnectorSystem.getConstructionEntityForStation, st)
	if con ~= nil and con >= 0 then
		local c = getComp(con, ct().CONSTRUCTION)
		local fileName = c and try(function() return c.fileName end) or nil
		log(string.format("%s  construction %d fileName=%s %s", indent, con, q(fileName), names(con)))
	end
	log(indent .. "  town: " .. townInfo(st, p))
end

local function groupStations(g)
	local sg = getComp(g, ct().STATION_GROUP)
	if sg == nil then return {} end
	return try(function()
		local out = {}
		for _, s in ipairs(sg.stations or {}) do out[#out + 1] = s end
		return out
	end) or {}
end

local function describeGroup(g, header)
	local sts = groupStations(g)
	log(string.format("%s group %d %s stations=%d", header, g, names(g), #sts))
	for i, st in ipairs(sts) do
		if i > 4 then
			log("    ...(" .. #sts .. " stations)")
			break
		end
		describeStation(st, "    ")
	end
end

---------------------------------------------------------------------------
-- State (small; probe only). Keys are strings so the saved table stays a plain map.

local function getState(state)
	local s = state:get()
	if type(s) ~= "table" or s.v ~= STATE_V then
		s = { v = STATE_V }
	end
	return s
end

local function watchCount(s)
	local n = 0
	for _ in pairs(s.watch or {}) do n = n + 1 end
	return n
end

local function watchAdd(s, e, kind)
	s.watch = s.watch or {}
	local k = tostring(e)
	if s.watch[k] ~= nil then return end
	if watchCount(s) >= WATCH_CAP then return end
	local nc = nameComp(e)
	s.watch[k] = { kind = kind, name = entName(e), has = nc ~= nil }
end

---------------------------------------------------------------------------
-- Mod params

local function rawParam(key)
	local ok, all = pcall(api.engine.config.getModParams)
	if not ok or all == nil then return nil end
	local mine = all[MOD_ID]
	if mine == nil then return nil end
	return mine[key]
end

--- The game passes the 1-based option index (docs/findings.md), not mod.json's numbers;
--- accept both (index 2/3/4 or number 20/30/40). Anything else is Off and logged.
local function renameMode()
	if RENAME_TEST_OVERRIDE ~= nil then return RENAME_TEST_OVERRIDE end
	local n = tonumber(rawParam("renameTest"))
	if n == 2 or n == 20 then return "group" end
	if n == 3 or n == 30 then return "stem" end
	if n == 4 or n == 40 then return "force" end
	return "off"
end

local function allEvents()
	local n = tonumber(rawParam("eventDiscovery"))
	return n ~= 2 and n ~= 200
end

---------------------------------------------------------------------------
-- Load dump

local CENSUS_KINDS = {
	"TOWN", "STATION_GROUP", "STATION", "EDGE_OBJECT", "CONSTRUCTION", "BASE_EDGE", "BASE_NODE", "LINE",
	"TRANSPORT_VEHICLE", "VEHICLE_DEPOT", "INDUSTRY", "TOWN_BUILDING", "PLAYER", "GAME_SCRIPT", "SIM_PERSON",
}

local function nameCensus()
	local named = entities(ct().NAME)
	local counts, samples, order = {}, {}, {}
	for i, e in ipairs(named) do
		if i > CENSUS_CAP then break end
		local kind = "other"
		for _, k in ipairs(CENSUS_KINDS) do
			local t = ct()[k]
			if t ~= nil and getComp(e, t) ~= nil then
				kind = k
				break
			end
		end
		if counts[kind] == nil then
			counts[kind] = 0
			samples[kind] = {}
			order[#order + 1] = kind
		end
		counts[kind] = counts[kind] + 1
		if #samples[kind] < 4 then samples[kind][#samples[kind] + 1] = tostring(e) .. "=" .. q(nameComp(e)) end
	end
	log(string.format("dump NAME census: %d entities with a NAME component (cap %d)", #named, CENSUS_CAP))
	for _, k in ipairs(order) do
		log(string.format("dump   NAME on %s: %d e.g. %s", k, counts[k], table.concat(samples[k], ", ")))
	end
end

local function edgeCensus()
	local edges = entities(ct().BASE_EDGE_STREET)
	local withName, sample = 0, {}
	for i, e in ipairs(edges) do
		if i > CENSUS_CAP then break end
		local nc = nameComp(e)
		if nc ~= nil then
			withName = withName + 1
			if #sample < 5 then sample[#sample + 1] = tostring(e) .. "=" .. q(nc) end
		end
	end
	log(string.format("dump street edges: %d BASE_EDGE_STREET, %d with NAME %s", #edges, withName, table.concat(sample, ", ")))
	-- getEntityName may compute a name without a NAME component: check a few edges.
	local shown = 0
	for _, e in ipairs(edges) do
		if shown >= 3 then break end
		shown = shown + 1
		log(string.format("dump   street edge %d %s", e, names(e)))
	end
end

--- Initial size of a town (for "are names handed out largest town first?"): sum of the initial land-use
--- capacities and the size factors of its TOWN component.
local function townSize(e)
	local tc = getComp(e, ct().TOWN)
	if tc == nil then return "size=?" end
	local cap = try(function()
		local sum = 0
		for _, v in ipairs(tc.initialLandUseCapacities or {}) do sum = sum + v end
		return sum
	end)
	local sf = try(function()
		local out = {}
		for _, v in ipairs(tc.sizeFactors or {}) do out[#out + 1] = string.format("%.2f", v) end
		return table.concat(out, "/")
	end)
	return string.format("initialCap=%s sizeFactors=%s", tostring(cap), tostring(sf))
end

--- Config dict as a game script sees it (climate / nameList / economy).
local function configDictLine()
	local cfg = try(api.engine.config.getConfigDict)
	if cfg == nil then return "getConfigDict FAILED" end
	return string.format("climate=%s economy=%s nameList=%s", tostring(try(function() return cfg.climate end)),
		tostring(try(function() return cfg.economy end)), tostring(try(function() return cfg.nameList end)))
end

local function dump(s)
	log("dump configDict " .. configDictLine())
	local towns = townList()
	log(string.format("dump towns: %d", #towns))
	local s2t = try(api.engine.system.stationSystem.getTown2StationsMap) or {}
	for i, t in ipairs(towns) do
		if i > DUMP_TOWNS then
			log("dump   ...(" .. #towns .. " towns)")
			break
		end
		local nst = try(function() return #(s2t[t.e] or {}) end) or "?"
		log(string.format("dump   town %d %s pos=%s stations=%s %s", t.e, names(t.e), fmtPos(t.p), tostring(nst), townSize(t.e)))
	end
	nameCensus()
	edgeCensus()
	local groups = entities(ct().STATION_GROUP)
	local edgeStops, conStations, otherStations = 0, 0, 0
	for _, st in ipairs(entities(ct().STATION)) do
		local k = stationKind(st)
		if k == "edgeObject" then edgeStops = edgeStops + 1
		elseif k == "construction" then conStations = conStations + 1
		else otherStations = otherStations + 1 end
	end
	log(string.format("dump station groups: %d; stations: %d edge-object stops, %d construction stations, %d other",
		#groups, edgeStops, conStations, otherStations))
	for i, g in ipairs(groups) do
		if i > DUMP_GROUPS then
			log("dump   ...(" .. #groups .. " groups, rest not shown)")
			break
		end
		describeGroup(g, "dump  ")
	end
	-- Watch towns and a slice of existing groups (+ their first station) for name changes.
	for _, t in ipairs(towns) do watchAdd(s, t.e, "town") end
	for i, g in ipairs(groups) do
		if i > WATCH_EXISTING_GROUPS then break end
		watchAdd(s, g, "group")
		local sts = groupStations(g)
		if sts[1] ~= nil then watchAdd(s, sts[1], "station") end
	end
	log(string.format("dump watching %d entities for name changes", watchCount(s)))
end

---------------------------------------------------------------------------
-- Polling scan: new station groups / stations

local function queueRename(s, g, st)
	local mode = renameMode()
	if mode == "off" then return end
	s.renameCount = s.renameCount or 0
	if s.renameCount >= RENAME_MAX then return end
	s.renameCount = s.renameCount + 1
	local name = RENAME_NAMES[s.renameCount]
	if st ~= nil and stationKind(st) == "construction" then name = RENAME_CON_NAMES[s.renameCount] end
	s.renames = s.renames or {}
	s.renames[#s.renames + 1] = { g = g, st = st, mode = mode, name = name, phase = "queued" }
	log(string.format("rename queued #%d mode=%s group %d station %s -> %s", s.renameCount, mode, g, tostring(st), q(name)))
end

local function scan(s, via)
	local changed = false
	local groups = entities(ct().STATION_GROUP)
	local stations = entities(ct().STATION)
	if s.knownGroups == nil then
		s.knownGroups, s.knownStations = {}, {}
		for _, g in ipairs(groups) do s.knownGroups[tostring(g)] = true end
		for _, st in ipairs(stations) do
			s.knownStations[tostring(st)] = try(api.engine.system.stationGroupSystem.getStationGroup, st) or -1
		end
		log(string.format("baseline: %d station groups, %d stations (module %s)", #groups, #stations, moduleToken))
		return true
	end
	local lb = lastBuild
	local buildNote = lb and string.format("lastBuild=%s %ds ago", tostring(lb.name), os.time() - (lb.t or 0)) or "lastBuild=none"
	local present = {}
	for _, g in ipairs(groups) do
		local k = tostring(g)
		present[k] = true
		if not s.knownGroups[k] then
			s.knownGroups[k] = true
			changed = true
			describeGroup(g, string.format("NEW (via %s, %s)", via, buildNote))
			watchAdd(s, g, "group")
			local sts = groupStations(g)
			for _, st in ipairs(sts) do watchAdd(s, st, "station") end
			queueRename(s, g, sts[1])
		end
	end
	for _, st in ipairs(stations) do
		local k = tostring(st)
		local g = try(api.engine.system.stationGroupSystem.getStationGroup, st) or -1
		local old = s.knownStations[k]
		if old == nil then
			s.knownStations[k] = g
			changed = true
			log(string.format("NEW station %d in group %d (%s) via %s", st, g, names(g), via))
			describeStation(st, "    ")
			watchAdd(s, st, "station")
		elseif old ~= g then
			s.knownStations[k] = g
			changed = true
			log(string.format("station %d moved group %s -> %d %s", st, tostring(old), g, names(g)))
		end
	end
	local removed = 0
	for k in pairs(s.knownGroups) do
		if not present[k] then
			s.knownGroups[k] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		changed = true
		log(string.format("%d station group(s) removed", removed))
	end
	return changed
end

local function watchNames(s)
	local changed = false
	for k, w in pairs(s.watch or {}) do
		local e = tonumber(k)
		if not exists(e) then
			log(string.format("watch %s %s gone (was %s)", w.kind, k, q(w.name)))
			s.watch[k] = nil
			changed = true
		else
			local n = entName(e)
			local has = nameComp(e) ~= nil
			if n ~= w.name or has ~= w.has then
				log(string.format("name change %s %s %s (NAME %s) -> %s (NAME %s) now %s", w.kind, k, q(w.name),
					w.has and "yes" or "no", q(n), has and "yes" or "no", names(e)))
				w.name, w.has = n, has
				changed = true
			end
		end
	end
	return changed
end

local function runRenames(s)
	local changed = false
	for i, r in ipairs(s.renames or {}) do
		if r.phase == "queued" then
			local target = r.g
			local force = false
			if r.mode == "stem" or r.mode == "force" then target = r.st end
			if r.mode == "force" then force = true end
			local before = string.format("group %s | station %s", names(r.g), r.st and names(r.st) or "-")
			-- No callback: in the engine-state update the game rejects it ("Callbacks are currently
			-- disallowed"); the "verify" line 2 s later shows the result instead.
			local ok, err = pcall(function()
				api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(target, r.name, force))
			end)
			log(string.format("rename #%d sent=%s mode=%s target=%s force=%s name=%s err=%s; before: %s", i, tostring(ok),
				r.mode, tostring(target), tostring(force), q(r.name), tostring(err), before))
			r.phase = ok and "sent" or "failed"
			r.at = os.time()
			changed = true
		elseif r.phase == "sent" and os.time() - (r.at or 0) >= 2 then
			log(string.format("rename #%d verify (wanted %s): group %s | station %s", i, q(r.name), names(r.g),
				r.st and names(r.st) or "-"))
			r.phase = "verified"
			changed = true
		end
	end
	return changed
end

---------------------------------------------------------------------------
-- Events

local function payloadSummary(param)
	local t = type(param)
	if t ~= "table" then return t .. (param ~= nil and ("=" .. tostring(param):sub(1, 60)) or "") end
	local keys = {}
	for k, v in pairs(param) do
		if #keys >= 8 then
			keys[#keys + 1] = "..."
			break
		end
		keys[#keys + 1] = tostring(k) .. ":" .. type(v)
	end
	return "table{" .. table.concat(keys, ",") .. "}"
end

local function proposalSummary(p)
	local parts = {}
	local proposal = p[1]
	local cons = try(function()
		local out = {}
		for _, c in ipairs(proposal.toAdd or {}) do out[#out + 1] = tostring(c.fileName) end
		return out
	end) or {}
	parts[#parts + 1] = "toAdd=" .. #cons .. (#cons > 0 and ("{" .. table.concat(cons, ",") .. "}") or "")
	local nRemove = try(function() return #(proposal.toRemove or {}) end) or "?"
	parts[#parts + 1] = "toRemove=" .. tostring(nRemove)
	local eos = try(function()
		local out = {}
		for i, eo in ipairs(proposal.proposal.edgeObjectsToAdd or {}) do
			if i > 6 then
				out[#out + 1] = "..."
				break
			end
			local m = try(function() return eo.modelInstance.transf end)
			local pp = m and try(function() return { m[13], m[14], m[15] } end) or nil
			out[#out + 1] = string.format("[cat=%s result=%s left=%s pos=%s]", tostring(eo.category), tostring(eo.resultEntity),
				tostring(eo.left), fmtPos(pp))
		end
		return out
	end) or {}
	parts[#parts + 1] = "edgeObjectsToAdd=" .. #eos .. " " .. table.concat(eos, "")
	local n2o = try(function()
		local n = 0
		for _ in pairs(proposal.proposal.new2oldEdgeObjects or {}) do n = n + 1 end
		return n
	end)
	parts[#parts + 1] = "new2oldEdgeObjects=" .. tostring(n2o)
	local segs = try(function() return #(proposal.proposal.addedSegments or {}) end)
	parts[#parts + 1] = "addedSegs=" .. tostring(segs)
	local res = try(function()
		local out = {}
		for _, e in ipairs(p[3] or {}) do out[#out + 1] = tostring(e) end
		return out
	end) or {}
	parts[#parts + 1] = "p3={" .. table.concat(res, ",") .. "}"
	parts[#parts + 1] = "playerInitiated=" .. tostring(p[4])
	return table.concat(parts, " ")
end

local function onBuild(name, param)
	local p = param
	if type(p) ~= "table" or p[1] == nil then return end
	log(string.format("build %s %s", name, proposalSummary(p)))
	if name == "onPostBuildProposal" then
		-- Result entities as seen inside the post event (names may not be assigned yet).
		for i, e in ipairs(p[3] or {}) do
			if i > 4 then break end
			if exists(e) then
				local c = getComp(e, ct().CONSTRUCTION)
				local fileName = c and try(function() return c.fileName end) or nil
				log(string.format("build   result %d fileName=%s %s", e, q(fileName), names(e)))
			end
		end
		-- No state writes or commands inside a build event: flag the next update instead.
		pendingScan = true
		lastBuild = { name = name, t = os.time() }
	end
end

local function countEvent(counts, prefix, src, id, name, param)
	local key = tostring(src) .. "|" .. tostring(id) .. "|" .. tostring(name)
	local n = (counts[key] or 0) + 1
	counts[key] = n
	if n <= EVENT_LOG_PER_KIND then
		log(string.format("%s #%d src=%s id=%s name=%s param=%s", prefix, n, tostring(src), tostring(id), tostring(name),
			payloadSummary(param)))
	end
end

local function eventSummary()
	local now = os.time()
	if now - lastEventSummary < 120 then return end
	lastEventSummary = now
	local parts = {}
	for k, n in pairs(eventCounts) do parts[#parts + 1] = k .. "=" .. n end
	if #parts > 0 then
		table.sort(parts)
		log("event counts (engine, this Lua state): " .. table.concat(parts, "; "))
	end
end

---------------------------------------------------------------------------
-- Entry points

local function doUpdate(state)
	local now = os.time()
	local wantAll = allEvents()
	local subMode = wantAll and "all" or "build"
	local needSub = not state:hasEventSubscriptions() or subscribedMode ~= subMode
	-- Read the saved state only every SCAN_SECONDS (or right after a build): it holds the baseline.
	if not needSub and dumpedThisState and not pendingScan and now - lastScan < SCAN_SECONDS then
		eventSummary()
		return
	end
	local s = getState(state)
	if needSub then
		if wantAll then
			state:subscribeToAllEvents()
		else
			state:subscribeToNoEvents()
			state:subscribeToEvent("onPreBuildProposal")
			state:subscribeToEvent("onPostBuildProposal")
			state:subscribeToEvent("builder.proposalApply")
		end
		subscribedMode = subMode
		log(string.format("subscribed mode=%s renameTest=%s (raw %s) eventDiscovery raw %s", subMode, renameMode(),
			tostring(rawParam("renameTest")), tostring(rawParam("eventDiscovery"))))
	end
	local dirty = false
	if not dumpedThisState then
		dumpedThisState = true
		log(string.format("init Lua state %s, os.time %d, saved state %s", moduleToken, now,
			s.knownGroups and "has baseline" or "empty"))
		if now - (s.lastDump or 0) > 120 then
			s.lastDump = now
			dump(s)
			dirty = true
		else
			log("dump skipped (done less than 120 s ago in another Lua state)")
		end
	end
	if pendingScan or now - lastScan >= SCAN_SECONDS then
		local via = pendingScan and "postBuild" or "poll"
		pendingScan = false
		lastScan = now
		if scan(s, via) then dirty = true end
		if watchNames(s) then dirty = true end
		if runRenames(s) then dirty = true end
	end
	if dirty then state:set(s) end
	eventSummary()
end

local function doHandleEvent(src, id, name, param)
	countEvent(eventCounts, "event", src, id, name, param)
	if id == "apply_command" and (name == "onPreBuildProposal" or name == "onPostBuildProposal") then
		onBuild(name, param)
	end
end

local function doGuiHandleEvent(src, id, name, param)
	countEvent(guiEventCounts, "gui event", src, id, name, param)
	if name == "builder.proposalApply" and type(param) == "table" and param[1] ~= nil then
		log("gui builder.proposalApply " .. proposalSummary({ param[1], nil, nil, "gui" }))
	end
end

function data()
	return {
		update = function(_userParams, state, _dt)
			local ok, err = pcall(doUpdate, state)
			if not ok then warnOnce("update:" .. tostring(err), "update failed: " .. tostring(err)) end
		end,
		handleEvent = function(_userParams, _state, src, id, name, param)
			local ok, err = pcall(doHandleEvent, src, id, name, param)
			if not ok then warnOnce("event:" .. tostring(err), "handleEvent " .. tostring(name) .. " failed: " .. tostring(err)) end
		end,
		guiUpdate = function(_userParams, _state, _guiState)
			if not guiLoaded then
				guiLoaded = true
				log("gui script loaded (module " .. moduleToken .. ")")
			end
		end,
		guiHandleEvent = function(_userParams, _state, _guiState, src, id, name, param)
			local ok, err = pcall(doGuiHandleEvent, src, id, name, param)
			if not ok then warnOnce("gui:" .. tostring(err), "guiHandleEvent " .. tostring(name) .. " failed: " .. tostring(err)) end
		end,
	}
end
