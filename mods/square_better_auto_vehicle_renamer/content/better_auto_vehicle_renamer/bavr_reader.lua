-- Better Auto Vehicle Renamer: the sweep's reader (bavr_sweep.lua header) on the real game API. Lua 5.1 syntax; the
-- api table is passed in (tests hand it a fake one), and every game call runs in pcall, so a bad read is "gone" or
-- nil, never an error. PLAN.md "Phase 2".
--
-- Entry point:
--   Reader.new(api) -> reader with list / read / modelInfo / lineName / exists / lines / lineVehicles (the sweep's
--     contract; list, lines and lineVehicles return nil when the read failed, never a partial list), plus
--     reader.wantYear (bool, set by the game script: buf.year is read only when the year setting is on)
--     reader.wantParts (bool, set by the game script: buf.exp / buf.parts / buf.wagons are read only when the
--       old-vehicle marker or the train length is on)
--     reader.calls (counters for the log: list, read, model, year, parts, lines, lineVehicles, err)
--   Reader.expiry(n, ptOf, lifeOf) -> game ms the vehicle is past its lifespan, or nil (no lifespan): the base
--     vehicle window's rule (vehicle_util.tl:31-51 getLifespan / getMinPurchaseTimeAndLifespan): the part bought
--     first (ties: the shorter lifespan), its purchaseTime + its model's metadata.maintenance.lifespan * 1000; the
--     window shows no "time remaining" from then on (vehicle_util.tl:297-313). ptOf(i), lifeOf(i) -> numbers.
--   Reader.plainMetadata(md), Reader.power(md): a model's metadata (userdata or table) as the plain fields the core
--     wants (Classify.hasPassengers / isHeliModel), and its power (> 0: a powered part, Classify.lead).
--   Reader.yearOf(api, gameMs) -> year or nil: api.engine.util.getCalendarDate(gameMs).year, the base game's own
--     conversion of a past game time to a calendar date (notification_log.tl:151, finances_charts.tl:280; also in
--     a game script: deliver_workers.script.tl:78). It follows the calendar speed the game ran at (GameTime.dates).
--
-- Lists: getEntitiesWithComponent(TRANSPORT_VEHICLE, { requireOwnedByPlayer }) (list), lineSystem.getLinesForPlayer
-- (lines; getLines when that is missing), transportVehicleSystem.getLineVehicles (lineVehicles: the line watch; read
-- in a game script by Organic Towns, docs/findings/roads.md 2026-10-13), each copied into a Lua array in one pcall.
-- Game reads per vehicle (read): entityExists + getComponent(TRANSPORT_VEHICLE) + getEntityName; the line's
-- entityExists once per line per list; the model's metadata once per model per Lua state; the year once per purchase
-- time (cached); with wantParts the consist's parts once per vehicle while its first and last purchase times and its
-- part count stay (cached: the expiry and the wagon count), else one read of the last part's purchaseTime.

local Classify = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_classify.lua"

local M = {}

M.MAX_LIST = 100000     -- list cap (the sweep cuts at its own MAX_LIST too)
M.MAX_PARTS = 256       -- parts / compartments / load configs walked per model
M.MAX_YEARS = 20000     -- purchase times kept in the year cache (dropped whole beyond)
M.MAX_NAME_BYTES = 512  -- a longer name is cut (no real name is; keeps every later byte loop short)
M.MAX_CONSISTS = 50000  -- vehicles kept in the parts cache (dropped whole beyond)
M.MAX_LINES = 20000     -- line list cap (the sweep cuts at its own MAX_LINES too)
M.MAX_LINE_VEH = 10000  -- vehicles read per line
M.LIFESPAN_MS = 1000    -- metadata.maintenance.lifespan unit to game ms (vehicle_util.tl:31-34: lifespan * 1000)

-- # and [i] of a userdata vector or a table, in pcall
local function len(v)
	if v == nil then return 0 end
	local ok, n = pcall(function() return #v end)
	if ok and type(n) == "number" then return n end
	return 0
end
local function at(v, i)
	local ok, x = pcall(function() return v[i] end)
	if ok then return x end
	return nil
end
local function get(v, k)
	if v == nil then return nil end
	local ok, x = pcall(function() return v[k] end)
	if ok then return x end
	return nil
end
M.len, M.at, M.get = len, at, get

local function strList(v)
	local out = {}
	local n = len(v)
	if n > M.MAX_PARTS then n = M.MAX_PARTS end
	for i = 1, n do
		local s = at(v, i)
		if type(s) == "string" then out[#out + 1] = s end
	end
	return out
end

--- The fields of a model's metadata the core reads, as plain tables: transportVehicle.compartments[i].loadConfigs[j]
--- .cargoEntry.{capacity, cargoTypeSet.{cargoClassesIncluded, cargoTypesIncluded}} and airVehicle.isHelicopter.
function M.plainMetadata(md)
	local out = {}
	local tv = get(md, "transportVehicle")
	if tv ~= nil then
		local comps = get(tv, "compartments")
		local list = {}
		local nc = len(comps)
		if nc > M.MAX_PARTS then nc = M.MAX_PARTS end
		for i = 1, nc do
			local lcs = get(at(comps, i), "loadConfigs")
			local lout = {}
			local nl = len(lcs)
			if nl > M.MAX_PARTS then nl = M.MAX_PARTS end
			for j = 1, nl do
				local ce = get(at(lcs, j), "cargoEntry")
				if ce ~= nil then
					local set = get(ce, "cargoTypeSet")
					lout[#lout + 1] = { cargoEntry = { capacity = tonumber(get(ce, "capacity")) or 0, cargoTypeSet = {
						cargoClassesIncluded = strList(get(set, "cargoClassesIncluded")),
						cargoTypesIncluded = strList(get(set, "cargoTypesIncluded")) } } }
				end
			end
			list[#list + 1] = { loadConfigs = lout }
		end
		out.transportVehicle = { compartments = list }
	end
	local av = get(md, "airVehicle")
	if av ~= nil then
		local h = get(av, "isHelicopter")
		if type(h) == "boolean" then out.airVehicle = { isHelicopter = h } end
	end
	return out
end

--- A model's power: land engines' power (locos, power cars, road vehicles), else a ship's availPower, else an
--- aircraft's maxThrust. 0 for an unpowered part (a wagon) or when unreadable.
function M.power(md)
	local lv = get(md, "landVehicle")
	local engines = get(lv, "engines")
	local p = 0
	local n = len(engines)
	if n > M.MAX_PARTS then n = M.MAX_PARTS end
	for i = 1, n do p = p + (tonumber(get(at(engines, i), "power")) or 0) end
	if p > 0 then return p end
	local wv = get(md, "waterVehicle")
	p = tonumber(get(wv, "availPower")) or 0
	if p > 0 then return p end
	return tonumber(get(get(md, "airVehicle"), "maxThrust")) or 0
end

function M.expiry(n, ptOf, lifeOf)
	if type(n) ~= "number" or n < 1 then return nil end
	if n > M.MAX_PARTS then n = M.MAX_PARTS end
	local minPt, minLife = ptOf(1), lifeOf(1)
	for i = 2, n do
		local pt, life = ptOf(i), lifeOf(i)
		if type(pt) == "number" and (type(minPt) ~= "number" or pt < minPt or (pt == minPt and life < minLife)) then
			minPt, minLife = pt, life
		end
	end
	if type(minPt) ~= "number" or type(minLife) ~= "number" or minLife <= 0 then return nil end
	return minPt + minLife * M.LIFESPAN_MS
end

function M.yearOf(api, gameMs)
	local ok, y = pcall(function() return api.engine.util.getCalendarDate(gameMs).year end)
	if ok and type(y) == "number" then return y end
	return nil
end

function M.new(api)
	local r = { wantYear = false, wantParts = false,
		calls = { list = 0, read = 0, model = 0, year = 0, parts = 0, lines = 0, lineVehicles = 0, err = 0 } }
	local TV = api.type.ComponentType.TRANSPORT_VEHICLE
	local GOING = nil
	pcall(function() GOING = api.type.enum.TransportVehicleState.GOING_TO_DEPOT end)
	local engine, util, modelRep = api.engine, api.engine.util, api.res.modelRep
	local lineOk = {}      -- line id -> exists, per list
	local powerOf = {}     -- model id -> power
	local years, nyears = {}, 0
	local curParts = nil
	local lifeOfModel = {}  -- model id -> metadata.maintenance.lifespan (0 when unreadable)
	local consist, nconsist = {}, 0 -- vehicle id -> { pt1, n, ptLast, exp, wagons }

	local function modelPower(mid)
		local p = powerOf[mid]
		if p == nil then
			local ok, md = pcall(function() return modelRep.get(mid).metadata end)
			p = ok and M.power(md) or 0
			powerOf[mid] = p
		end
		return p
	end
	-- (runs inside read's pcall: plain indexing, no closure per part)
	local function partModel(i)
		local p = curParts[i]
		return p ~= nil and p.part.modelId or nil
	end
	local function isPowered(i)
		local mid = partModel(i)
		return type(mid) == "number" and modelPower(mid) > 0
	end
	local function modelLife(mid)
		local l = lifeOfModel[mid]
		if l == nil then
			local ok, v = pcall(function() return modelRep.get(mid).metadata.maintenance.lifespan end)
			l = (ok and tonumber(v)) or 0
			lifeOfModel[mid] = l
		end
		return l
	end
	local function partPt(i)
		local p = curParts[i]
		return p ~= nil and p.purchaseTime or nil
	end
	local function partLife(i)
		local mid = partModel(i)
		return type(mid) == "number" and modelLife(mid) or 0
	end
	-- the expiry and the wagon count of the consist, cached per vehicle while part 1's and the last part's purchase
	-- times and the part count stay (a Replace or a new wagon changes one of them)
	local function partsInfo(id, parts, n, buf)
		local last = n > 1 and parts[n].purchaseTime or buf.pt
		local c = consist[id]
		if c == nil or c[1] ~= buf.pt or c[2] ~= n or c[3] ~= last then
			r.calls.parts = r.calls.parts + 1
			curParts = parts
			local exp = M.expiry(n, partPt, partLife)
			local unpowered = 0
			local cap = n > M.MAX_PARTS and M.MAX_PARTS or n
			for i = 1, cap do
				if not isPowered(i) then unpowered = unpowered + 1 end
			end
			curParts = nil
			if c == nil then
				if nconsist >= M.MAX_CONSISTS then consist, nconsist = {}, 0 end
				nconsist = nconsist + 1
			end
			c = { buf.pt, n, last, exp or false, unpowered }
			consist[id] = c
		end
		buf.exp = c[4] or nil
		buf.parts = n
		buf.wagons = c[5]
	end

	-- a userdata vector or table of entity ids as a Lua array (run inside a pcall: one per list, not per element)
	local function copyIds(ids, cap)
		local out, k = {}, 0
		local n = #ids
		if n > cap then n = cap end
		for i = 1, n do
			local id = ids[i]
			if type(id) == "number" then
				k = k + 1
				out[k] = id
			end
		end
		return out
	end
	-- a failed read is nil (the sweep waits), never an empty list (that would read as "every vehicle sold")
	local function idList(key, fn, cap)
		r.calls[key] = r.calls[key] + 1
		local ok, out = pcall(function()
			local ids = fn()
			if ids == nil then return nil end
			return copyIds(ids, cap)
		end)
		if not ok or out == nil then
			r.calls.err = r.calls.err + 1
			return nil
		end
		return out
	end
	local lineSys, tvSys = nil, nil
	pcall(function() lineSys = engine.system.lineSystem end)
	pcall(function() tvSys = engine.system.transportVehicleSystem end)

	function r.list()
		lineOk = {}
		return idList("list", function()
			return engine.getEntitiesWithComponent(TV, { requireOwnedByPlayer = util.getPlayer() })
		end, M.MAX_LIST)
	end

	function r.lines()
		return idList("lines", function()
			if lineSys.getLinesForPlayer ~= nil then return lineSys.getLinesForPlayer(util.getPlayer()) end
			return lineSys.getLines()
		end, M.MAX_LINES)
	end

	function r.lineVehicles(li)
		return idList("lineVehicles", function() return tvSys.getLineVehicles(li) end, M.MAX_LINE_VEH)
	end

	local function readBody(id, buf)
		if not engine.entityExists(id) then return false end
		local tv = engine.getComponent(id, TV)
		if tv == nil then return false end
		buf.carrier = tv.carrier
		buf.depot = GOING ~= nil and tv.state == GOING
		local line = tv.line
		if type(line) == "number" and line > 0 then
			local e = lineOk[line]
			if e == nil then
				e = engine.entityExists(line) == true
				lineOk[line] = e
			end
			if e then buf.line = line end
		end
		local parts = tv.transportVehicleConfig.vehicles
		local n = #parts
		if n < 1 then return false end
		buf.pt = parts[1].purchaseTime
		if n == 1 then
			buf.model = parts[1].part.modelId
		else
			curParts = parts
			buf.model = partModel(Classify.lead(n, isPowered))
			curParts = nil
		end
		if r.wantParts then partsInfo(id, parts, n, buf) end
		local name = util.getEntityName(id)
		if type(name) == "string" and #name > M.MAX_NAME_BYTES then name = string.sub(name, 1, M.MAX_NAME_BYTES) end
		buf.name = name
		if r.wantYear and type(buf.pt) == "number" then
			local y = years[buf.pt]
			if y == nil then
				if nyears >= M.MAX_YEARS then years, nyears = {}, 0 end
				y = M.yearOf(api, buf.pt) or false
				years[buf.pt] = y
				nyears = nyears + 1
				r.calls.year = r.calls.year + 1
			end
			buf.year = y or nil
		end
		return true
	end

	function r.read(id, buf)
		r.calls.read = r.calls.read + 1
		local ok, res = pcall(readBody, id, buf)
		curParts = nil
		if not ok then
			r.calls.err = r.calls.err + 1
			return false
		end
		return res == true
	end

	function r.modelInfo(mid)
		r.calls.model = r.calls.model + 1
		local ok, info = pcall(function()
			local md = modelRep.get(mid).metadata
			local key = modelRep.getName(mid)
			local plain = M.plainMetadata(md)
			local name = get(get(md, "description"), "name")
			if powerOf[mid] == nil then powerOf[mid] = M.power(md) end
			return { name = type(name) == "string" and name or nil, key = type(key) == "string" and key or nil,
				heli = Classify.isHeliModel(plain, key), pax = Classify.hasPassengers(plain) }
		end)
		if not ok then
			r.calls.err = r.calls.err + 1
			return nil
		end
		return info
	end

	function r.lineName(li)
		local ok, name = pcall(function()
			if not engine.entityExists(li) then return nil end
			return util.getEntityName(li)
		end)
		if ok and type(name) == "string" then return name end
		return nil
	end

	function r.exists(id)
		local ok, e = pcall(function() return engine.entityExists(id) end)
		return ok and e == true
	end

	return r
end

return M
