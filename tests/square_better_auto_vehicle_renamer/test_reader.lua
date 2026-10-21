-- Better Auto Vehicle Renamer: the reader on a fake game API (bavr_reader.lua): the player's vehicle list, one
-- vehicle's read (carrier, depot, line guard, lead part, purchase time, name, year), model info converted from
-- userdata-like metadata (passengers, helicopter, power), the year from getCalendarDate, and errors counted, never
-- raised. PLAN.md "Phase 2".

local Reader = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_reader.lua"

--- A userdata-like view of a table: unknown fields raise (as the engine's userdata do), # works.
local function ud(t)
	if type(t) ~= "table" then return t end
	return setmetatable({}, {
		__index = function(_, k)
			local v = t[k]
			if v == nil then error("no member named '" .. tostring(k) .. "'") end
			return ud(v)
		end,
		__len = function() return #t end,
	})
end

local YEAR_MS = 2000000

local function fakeApi()
	local A = { player = 7, calls = { date = 0, getComponent = 0 }, exists = {}, comps = {}, names = {}, models = {},
		modelNames = {}, owned = {} }
	A.api = {
		type = {
			ComponentType = { TRANSPORT_VEHICLE = 11 },
			enum = { TransportVehicleState = { IN_DEPOT = 0, EN_ROUTE = 1, AT_TERMINAL = 2, GOING_TO_DEPOT = 3 } },
		},
		engine = {
			entityExists = function(id) return A.exists[id] == true end,
			getComponent = function(id, ct)
				A.calls.getComponent = A.calls.getComponent + 1
				assert(ct == 11)
				if A.throw then error("boom") end
				local c = A.comps[id]
				return c and ud(c) or nil
			end,
			getEntitiesWithComponent = function(ct, filter)
				assert(ct == 11)
				A.filter = filter
				if A.listThrows then error("list boom") end
				return A.owned
			end,
			util = {
				getPlayer = function() return A.player end,
				getEntityName = function(id) return A.names[id] end,
				getCalendarDate = function(ms)
					A.calls.date = A.calls.date + 1
					return ud({ year = 1850 + math.floor(ms / YEAR_MS), month = 1, day = 1 })
				end,
			},
		},
		res = { modelRep = {
			get = function(mid)
				local m = A.models[mid]
				if m == nil then error("no model " .. tostring(mid)) end
				return ud({ metadata = m })
			end,
			getName = function(mid) return A.modelNames[mid] end,
		} },
	}
	return A
end

local function paxComp(cap, class)
	return { { loadConfigs = { { cargoEntry = { capacity = cap, cargoTypeSet = { cargoClassesIncluded = { class },
		cargoTypesIncluded = {} } } } } } }
end

local function setup()
	local A = fakeApi()
	-- models: 1 bus, 2 truck, 3 loco, 4 wagon, 5 helicopter (metadata), 6 helicopter (path only), 7 ship, 8 plane
	A.models[1] = { description = { name = "Citaro" }, transportVehicle = { compartments = paxComp(48, "PASSENGERS") },
		landVehicle = { engines = { { power = 210 } } } }
	A.models[2] = { description = { name = "Scania R" }, transportVehicle = { compartments = paxComp(20, "PIECE_GOODS") },
		landVehicle = { engines = { { power = 300 } } } }
	A.models[3] = { description = { name = "Class 101" }, transportVehicle = { compartments = {} },
		landVehicle = { engines = { { power = 1000 }, { power = 500 } } } }
	A.models[4] = { description = { name = "Coach" }, transportVehicle = { compartments = paxComp(60, "PASSENGERS") },
		landVehicle = { engines = {} } }
	A.models[5] = { description = { name = "AW101" }, airVehicle = { isHelicopter = true, maxThrust = 50 } }
	A.models[6] = { description = { name = "Old Heli" } }
	A.models[7] = { description = { name = "Sternwheeler" }, waterVehicle = { availPower = 400 } }
	A.models[8] = { description = { name = "DC-3" }, airVehicle = { isHelicopter = false, maxThrust = 80 } }
	A.modelNames = { "vehicle/bus/citaro.mdl", "vehicle/truck/scania.mdl", "vehicle/train/class101.mdl",
		"vehicle/train/coach.mdl", "vehicle/helicopter/aw101.mdl", "vehicle/helicopter/old.mdl", "vehicle/ship/sw.mdl",
		"vehicle/plane/dc3.mdl" }
	local function veh(id, carrier, parts, line, state, name)
		local vs = {}
		for i, p in ipairs(parts) do vs[i] = { part = { modelId = p[1] }, purchaseTime = p[2] } end
		A.comps[id] = { carrier = carrier, state = state or 1, line = line or -1,
			transportVehicleConfig = { vehicles = vs } }
		A.exists[id] = true
		A.names[id] = name or ("Vehicle " .. id)
		A.owned[#A.owned + 1] = id
	end
	A.exists[900] = true -- a line
	veh(100, 0, { { 1, 5 * YEAR_MS + 5 } }, 900)
	veh(101, 1, { { 4, 3 * YEAR_MS }, { 3, 3 * YEAR_MS + 9 }, { 4, 1 } }, 901) -- line 901 does not exist
	veh(102, 0, { { 2, 1 } }, nil, 3)
	return A, Reader.new(A.api)
end

test("list: the player's vehicles (requireOwnedByPlayer), a plain array; an error gives nil (never an empty list)", function()
	local A, r = setup()
	eq(r.list(), { 100, 101, 102 })
	eq(A.filter.requireOwnedByPlayer, 7)
	A.listThrows = true
	eq(r.list(), nil, "a failed read is no list (the sweep would take an empty one for every vehicle sold)")
	eq(r.calls.err, 1)
end)

test("read: carrier, depot, line guard, purchase time of part 1, lead powered part, name", function()
	local A, r = setup()
	r.list()
	local buf = {}
	ok(r.read(100, buf))
	eq({ buf.carrier, buf.depot, buf.line, buf.model, buf.pt, buf.name, buf.year },
		{ 0, false, 900, 1, 5 * YEAR_MS + 5, "Vehicle 100", nil })
	buf = {}
	ok(r.read(101, buf))
	eq(buf.model, 3, "the first part with power (the loco), not the wagon in front")
	eq(buf.pt, 3 * YEAR_MS, "purchase time of part 1")
	eq(buf.line, nil, "a line that does not exist is no line")
	buf = {}
	ok(r.read(102, buf))
	eq(buf.depot, true, "GOING_TO_DEPOT")
	eq(buf.line, nil, "line -1")
	-- a wagon-only consist: part 1
	A.comps[101].transportVehicleConfig.vehicles = { { part = { modelId = 4 }, purchaseTime = 1 },
		{ part = { modelId = 4 }, purchaseTime = 1 } }
	buf = {}
	ok(r.read(101, buf))
	eq(buf.model, 4)
end)

test("read: gone and failing entities are false, counted, never raised", function()
	local A, r = setup()
	local buf = {}
	A.exists[100] = false
	eq(r.read(100, buf), false, "gone: not even getComponent")
	eq(A.calls.getComponent, 0)
	A.throw = true
	eq(r.read(102, buf), false)
	eq(r.calls.err, 1)
	A.throw = false
	A.comps[102].transportVehicleConfig.vehicles = {}
	eq(r.read(102, buf), false, "no parts")
end)

test("read: the year only when the year setting is on, once per purchase time", function()
	local A, r = setup()
	local buf = {}
	r.read(100, buf)
	eq(buf.year, nil)
	eq(A.calls.date, 0)
	r.wantYear = true
	for _ = 1, 5 do
		buf = {}
		r.read(100, buf)
	end
	eq(buf.year, 1855)
	eq(A.calls.date, 1, "cached per purchase time")
	eq(Reader.yearOf(A.api, 0), 1850)
	eq(Reader.yearOf({}, 0), nil, "no API: nil")
end)

test("modelInfo: name, file name, passengers, helicopter by metadata or path; never raises", function()
	local A, r = setup()
	eq(r.modelInfo(1), { name = "Citaro", key = "vehicle/bus/citaro.mdl", heli = false, pax = true })
	eq(r.modelInfo(2).pax, false, "truck: no passengers")
	eq(r.modelInfo(5).heli, true)
	eq(r.modelInfo(6).heli, true, "path fallback (no airVehicle field: the strict metadata raises, caught)")
	eq(r.modelInfo(8).heli, false)
	eq(r.modelInfo(4).pax, true)
	eq(r.modelInfo(99), nil, "unknown model")
	ok(r.calls.err >= 1)
end)

test("metadata conversion and power", function()
	local m = Reader.plainMetadata(ud({ transportVehicle = { compartments = paxComp(10, "PASSENGERS") },
		airVehicle = { isHelicopter = false } }))
	eq(m.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity, 10)
	eq(m.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.cargoTypeSet.cargoClassesIncluded, { "PASSENGERS" })
	eq(m.airVehicle, { isHelicopter = false })
	eq(Reader.plainMetadata(nil), {})
	eq(Reader.power(ud({ landVehicle = { engines = { { power = 100 }, { power = 50 } } } })), 150)
	eq(Reader.power(ud({ landVehicle = { engines = {} } })), 0)
	eq(Reader.power(ud({ waterVehicle = { availPower = 7 } })), 7)
	eq(Reader.power(ud({ airVehicle = { maxThrust = 3 } })), 3)
	eq(Reader.power(nil), 0)
end)

test("lineName and exists", function()
	local A, r = setup()
	A.names[900] = "Bus 12"
	eq(r.lineName(900), "Bus 12")
	eq(r.lineName(901), nil, "a line that does not exist")
	eq(r.exists(100), true)
	eq(r.exists(5), false)
end)

test("caps: a huge name is cut, a long list is cut", function()
	local A, r = setup()
	A.names[100] = string.rep("x", 10000)
	local buf = {}
	r.read(100, buf)
	eq(#buf.name, Reader.MAX_NAME_BYTES)
	local old = Reader.MAX_LIST
	Reader.MAX_LIST = 2
	eq(#r.list(), 2)
	Reader.MAX_LIST = old
end)

---------------------------------------------------------------------------
-- The old-vehicle marker's expiry and the train length (PLAN.md "Old-vehicle marker", "Train length")

test("expiry: the base rule, the first-bought part (ties: the shorter lifespan) + its lifespan * 1000", function()
	local function ex(parts)
		return Reader.expiry(#parts, function(i) return parts[i][1] end, function(i) return parts[i][2] end)
	end
	eq(ex({ { 100, 5 } }), 100 + 5000)
	eq(ex({ { 300, 5 }, { 100, 50 }, { 200, 1 } }), 100 + 50000, "the oldest part's own lifespan")
	eq(ex({ { 100, 50 }, { 100, 7 } }), 100 + 7000, "same purchase time: the shorter lifespan")
	eq(ex({ { 100, 0 } }), nil, "no lifespan in the model: never old")
	eq(Reader.expiry(0, nil, nil), nil)
	local calls = 0
	Reader.expiry(1e9, function() calls = calls + 1; return 1 end, function() return 1 end)
	eq(calls, Reader.MAX_PARTS, "the part walk is capped")
end)

test("read with wantParts: expiry, part count and unpowered parts, read once per consist until it changes", function()
	local A, r = setup()
	A.models[3].maintenance = { lifespan = 40 * 365 * 4 }
	A.models[4].maintenance = { lifespan = 30 * 365 * 4 }
	A.models[1].maintenance = { lifespan = 12 * 365 * 4 }
	r.wantParts = true
	r.list()
	local buf = {}
	ok(r.read(101, buf))
	-- parts: coach (pt 3Y), loco (pt 3Y + 9), coach (pt 1): the oldest is the last coach
	eq({ buf.parts, buf.wagons, buf.exp }, { 3, 2, 1 + 30 * 365 * 4 * 1000 })
	eq(r.calls.parts, 1)
	for _ = 1, 5 do r.read(101, {}) end
	eq(r.calls.parts, 1, "cached while the consist stays")
	-- a wagon added: the part count changes, read again
	local vs = A.comps[101].transportVehicleConfig.vehicles
	vs[#vs + 1] = { part = { modelId = 4 }, purchaseTime = 7 * YEAR_MS }
	buf = {}
	r.read(101, buf)
	eq({ buf.parts, buf.wagons, r.calls.parts }, { 4, 3, 2 })
	-- a bus: one part, its own lifespan
	buf = {}
	r.read(100, buf)
	eq({ buf.parts, buf.wagons, buf.exp }, { 1, 0, 5 * YEAR_MS + 5 + 12 * 365 * 4 * 1000 })
	-- off: nothing read
	r.wantParts = false
	buf = {}
	r.read(100, buf)
	eq({ buf.parts, buf.exp }, { nil, nil })
	-- a model without maintenance metadata: no expiry, no error
	r.wantParts = true
	buf = {}
	ok(r.read(102, buf))
	eq(buf.exp, nil)
end)

test("parts cache is capped at MAX_CONSISTS vehicles (dropped whole)", function()
	local A, r = setup()
	r.wantParts = true
	local old = Reader.MAX_CONSISTS
	Reader.MAX_CONSISTS = 2
	for _ = 1, 3 do
		for _, id in ipairs({ 100, 101, 102 }) do r.read(id, {}) end
	end
	Reader.MAX_CONSISTS = old
	ok(r.calls.parts > 3, "re-read after the drop: " .. r.calls.parts)
end)

test("line watch reads: the player's lines (getLines when getLinesForPlayer is missing) and a line's vehicles; errors nil", function()
	local A = fakeApi()
	local calls = {}
	A.api.engine.system = {
		lineSystem = { getLinesForPlayer = function(p) calls.player = p; return { 900, 901, "x" } end },
		transportVehicleSystem = { getLineVehicles = function(li)
			if li == 666 then error("no line") end
			return li == 900 and { 100, 101 } or {}
		end },
	}
	local r = Reader.new(A.api)
	eq(r.lines(), { 900, 901 }, "numbers only")
	eq(calls.player, 7)
	eq(r.lineVehicles(900), { 100, 101 })
	eq(r.lineVehicles(901), {})
	eq(r.lineVehicles(666), nil, "an error is nil")
	A.api.engine.system.lineSystem = { getLines = function() return { 5 } end }
	eq(Reader.new(A.api).lines(), { 5 }, "getLines as the fallback")
	local B = fakeApi() -- no api.engine.system at all
	local rb = Reader.new(B.api)
	eq({ rb.lines(), rb.lineVehicles(900) }, {})
	ok(rb.calls.err >= 2)
end)
