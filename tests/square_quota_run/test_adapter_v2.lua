-- quota.script.tl v2 (PLAN §9.3 delivery facts, §9.8 migration, §9.9 probes P1-P4, P6, P7)
-- against a fake `api` with a component store. The logic instance is the real one, wrapped so
-- these tests control factsNeeded / migrate and record what the adapter passes to the logic
-- (adapter behaviour only; the rule math is covered by test_logic_*).

local MD = 1000
local GS_NAME = "square_quota_run::/quota/quota.gs"
local COMPANY_GS = "::/game_mechanics/company/company_progression.gs"
local MOD_ID = "square_quota_run"

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepcopy(x) end
	return out
end

local A -- fake engine world for the current test
local CT = {
	GAME_TIME = "GAME_TIME", GAME_SPEED = "GAME_SPEED", GAME_SCRIPT = "GAME_SCRIPT",
	TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE", INDUSTRY = "INDUSTRY", STOCK_LIST = "STOCK_LIST",
	SIM_CARGO = "SIM_CARGO", SIM_PERSON = "SIM_PERSON", CONSTRUCTION = "CONSTRUCTION",
	TOWN_BUILDING = "TOWN_BUILDING", TOWN = "TOWN", NAME = "NAME", PLAYER_OWNED = "PLAYER_OWNED",
}
local CARRIER = { ROAD = 11, RAIL = 12, TRAM = 13, OTHER = 14, AIR = 15, WATER = 16 }

local function daysIn(y, m)
	local d = ({ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
	if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then d = 29 end
	return d
end

local function newDate(y, m, d)
	return { year = y, month = m, day = d, getEndOfMonth = function(self)
		return { year = self.year, month = self.month, day = daysIn(self.year, self.month) }
	end }
end

local function installApi()
	A = {
		gameTime = 0, speed = 1, balance = 1000000, mission = false, added = false, editor = false,
		transported = { passengersTransported = 0, cargoTransported = 0 },
		gsEntity = 77, companyEntity = 88, companyMult = 1.25,
		sent = {}, comp = {}, io = {}, reads = 0,
		date = { year = 1900, month = 2, day = 29 },
		modParams = nil, modParamsTable = true,
	}
	set_global("api", {
		type = {
			ComponentType = CT,
			JournalEntry = { new = function() return { category = {} } end, Type = { OTHER = "OTHER" } },
			Vec3f = { new = function(x, y, z) return { x, y, z } end },
			Date = { new = newDate },
			enum = { Carrier = CARRIER },
		},
		engine = {
			getComponent = function(e, ct)
				if ct == CT.GAME_TIME then return { gameTime = A.gameTime } end
				if ct == CT.GAME_SPEED then return { speedup = A.speed } end
				if ct == CT.GAME_SCRIPT and e == A.gsEntity then return { addedToExistingSavegame = A.added } end
				if ct == CT.GAME_SCRIPT and e == A.companyEntity then
					return { state = { companyState = { [2] = { ticketPriceMultiplier = A.companyMult } } } }
				end
				A.reads = A.reads + 1
				local c = A.comp[e]
				return c and deepcopy(c[ct]) or nil
			end,
			entityExists = function(e) return A.comp[e] ~= nil end,
			config = { getModParams = function()
				if not A.modParamsTable then return nil end
				return { [""] = { isMapEditor = A.editor }, [MOD_ID] = A.modParams }
			end },
			getEntitiesWithComponent = function(ct, filters)
				local out = {}
				for e, c in pairs(A.comp) do if c[ct] ~= nil then out[#out + 1] = e end end
				table.sort(out, function(a, b) return a > b end) -- reverse: the adapter must sort itself
				return out
			end,
			util = {
				getWorld = function() return 1 end,
				getPlayer = function() return 2 end,
				hasStartedAsMission = function() return A.mission end,
				finance = { getPlayersBalance = function() return A.balance end },
				headquarters = { getTransportedData = function() return deepcopy(A.transported) end },
				getCalendarDate = function(gt) return newDate(A.date.year, A.date.month, A.date.day) end,
				stock = { getInputsOutputsFromRules = function(sl) return A.io[sl] or { {}, {} } end },
			},
			system = { gameScriptSystem = { getEntityForGameScript = function(name)
				if name == GS_NAME then return A.gsEntity end
				if name == COMPANY_GS then return A.companyEntity end
				return -1
			end } },
		},
		cmd = {
			sendCommand = function(cmd)
				A.sent[#A.sent + 1] = cmd
				if cmd.kind == "speed" then A.speed = cmd.speedup end
				if cmd.kind == "date" then A.date = { year = cmd.date.year, month = cmd.date.month, day = cmd.date.day } end
				if cmd.kind == "despawn" then A.comp[cmd.entity][CT.INDUSTRY].closureTimeStamp = cmd.time end
			end,
			makeGameSetSpeedCmd = function(s) return { kind = "speed", speedup = s } end,
			makeScriptingSendEventCmd = function(src, id, name, param)
				return { kind = "event", src = src, id = id, name = name, param = param }
			end,
			makeJournalBookAssetCmd = function(p, entry, pos) return { kind = "journal", player = p, entry = entry } end,
			makeGameSetDateCmd = function(d) return { kind = "date", date = d } end,
			makeIndustrySetDespawnTimeCmd = function(e, t) return { kind = "despawn", entity = e, time = t } end,
		},
		util = { getDefaultMonthDuration = function() return MD end },
	})
end

local function makeState(initial)
	local st = { value = deepcopy(initial), subs = {}, sets = 0, noEvents = 0, gets = 0 }
	function st:get() self.gets = self.gets + 1 return deepcopy(self.value) end
	function st:set(v) self.value = deepcopy(v); self.sets = self.sets + 1 end
	function st:subscribeToNoEvents() self.subs = {}; self.noEvents = self.noEvents + 1 end
	function st:subscribeToEvent(n) self.subs[n] = true end
	function st:subscribeToAllEvents() error("never subscribe to all events") end
	function st:hasEventSubscriptions() return next(self.subs) ~= nil end
	return st
end

stub_module("::/industries/industry_productivity_util.tl", {
	isIndustryWorkersBoosted = function() return false end,
	getPersonCapacityPotentialBoost = function() return 2.0 end,
})

-- Wrap the real logic (see the header). L is reset before each test.
local L
local realModule = ug_require "/quota/quota_logic.tl"
stub_module("/quota/quota_logic.tl", { new = function(...)
	local real = realModule.new(...)
	local w = {}
	for k, v in pairs(real) do w[k] = v end
	w.factsNeeded = function(s)
		L.factsNeededCalls = L.factsNeededCalls + 1
		if L.realFacts then return real.factsNeeded(s) end
		return deepcopy(L.needed)
	end
	w.migrate = function(s)
		L.migrateCalls = L.migrateCalls + 1
		if L.migrateImpl then return L.migrateImpl(s) end
		return s, {}
	end
	w.delivered = function(s, input)
		L.delivered[#L.delivered + 1] = deepcopy(input)
		return real.delivered(s, input)
	end
	w.debug = function(s, input)
		L.debugInputs[#L.debugInputs + 1] = deepcopy(input)
		return real.debug(s, input)
	end
	return w
end })

local script = ug_require "/quota/quota.script.tl"
local config = ug_require "/quota/quota_config.tl"

local function ev(st, id, name, param) return script.handleEvent({}, st, "", id, name, param) end
local function dbg(st, op, extra)
	local p = { op = op }
	for k, v in pairs(extra or {}) do p[k] = v end
	return ev(st, "QuotaRun", "QuotaRun.debug", p)
end

local function activeState()
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	assert(st.value and st.value.active)
	return st
end

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.level .. ": " .. e.msg end
	return table.concat(out, "\n")
end

local function warnings()
	local out = {}
	for _, e in ipairs(log_entries()) do if e.level == "warning" then out[#out + 1] = e.msg end end
	return table.concat(out, "\n")
end

local function has(text, needle) return text:find(needle, 1, true) ~= nil end

local ALL_SUBS = { ["QuotaRun.pickCard"] = true, ["QuotaRun.continueSandbox"] = true, ["QuotaRun.debug"] = true,
	OnToArriveAtDestination = true, OnCompletedLineUsage = true }
local function withTicket(subs)
	local out = deepcopy(subs)
	out.OnCalcTicketPrice = true
	return out
end

before_each(function()
	installApi()
	clear_logs()
	config.DEBUG = true
	config.METRIC = "events"
	L = { needed = nil, factsNeededCalls = 0, migrateCalls = 0, migrateImpl = nil, delivered = {}, debugInputs = {} }
end)

--- A small world: town 9 (construction 200 -> town building 201), town 8 (town building 300),
--- town 7 (town building 210), an industry stock list 400 (no town).
local function buildTowns()
	A.comp[9] = { [CT.TOWN] = { developmentActive = true, capacityScalingFactor = 1.5, noise = 3, pollution = 4 },
		[CT.NAME] = { name = "Nineton" } }
	A.comp[200] = { [CT.CONSTRUCTION] = { townBuildings = { 201 } } }
	A.comp[201] = { [CT.TOWN_BUILDING] = { town = 9 } }
	A.comp[300] = { [CT.TOWN_BUILDING] = { town = 8 } }
	A.comp[210] = { [CT.TOWN_BUILDING] = { town = 7 } }
	A.comp[220] = { [CT.TOWN_BUILDING] = { town = 9 } }
	A.comp[400] = { [CT.STOCK_LIST] = {} }
end

local function addCargo(e, cargoType, source, points)
	A.comp[e] = { [CT.SIM_CARGO] = { cargoType = cargoType, sourceEntity = source, pickupPoints = points } }
end

local ALL_NEEDS = { cargoType = true, toTown = true, fromTown = true, line = true, carrier = true }

-- delivery facts (PLAN §9.3) ------------------------------------------------------------------

test("factsNeeded nil: MVP fast path (units only, no facts, no engine reads)", function()
	local st = activeState()
	buildTowns()
	addCargo(100, 5, 300, { { line = 40, carrier = CARRIER.RAIL } })
	A.reads = 0
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 0 } }, { 100, { 200, 0 } } } })
	ev(st, "SimPersonSystem", "OnCompletedLineUsage", { entities = { 500 } })
	eq(L.delivered, { { units = 2, kind = "cargo" }, { units = 1, kind = "passenger" } })
	eq(A.reads, 0)
	eq(L.factsNeededCalls, 2)
	eq(st.value.progress, 3)
end)

test("cargo facts: every field resolved from SIM_CARGO, last pickup point and towns", function()
	local st = activeState()
	buildTowns()
	addCargo(100, 5, 300, { { line = 40, carrier = CARRIER.ROAD }, { line = 41, carrier = CARRIER.RAIL } })
	L.needed = ALL_NEEDS
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 3 } } } })
	eq(L.delivered[1].units, 1)
	eq(L.delivered[1].kind, "cargo")
	eq(L.delivered[1].facts, { { kind = "cargo", cargoType = 5, toTown = 9, fromTown = 8, line = 41, carrier = "RAIL" } })
end)

test("cargo facts: only the needed fields are read and set", function()
	local st = activeState()
	buildTowns()
	addCargo(100, 5, 300, { { line = 41, carrier = CARRIER.RAIL } })
	L.needed = { cargoType = true }
	A.reads = 0
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 3 } } } })
	eq(L.delivered[1].facts, { { kind = "cargo", cargoType = 5 } })
	eq(A.reads, 1) -- SIM_CARGO only, no town lookups
	L.needed = { toTown = true }
	A.reads = 0
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 3 } } } })
	eq(L.delivered[2].facts, { { kind = "cargo", toTown = 9 } })
	eq(A.reads, 2) -- CONSTRUCTION + TOWN_BUILDING, no SIM_CARGO
end)

test("carrier mapping: every api.type.enum.Carrier value, unknown -> OTHER, nil -> nil", function()
	local st = activeState()
	local cases = { ROAD = "ROAD", RAIL = "RAIL", TRAM = "TRAM", AIR = "AIR", WATER = "WATER", OTHER = "OTHER" }
	local entities, expected = {}, {}
	local e = 1000
	for key, want in pairs(cases) do
		addCargo(e, 1, -1, { { line = 1, carrier = CARRIER[key] } })
		entities[#entities + 1] = { e, { -1, 0 } }
		expected[#expected + 1] = want
		e = e + 1
	end
	addCargo(e, 1, -1, { { line = 1, carrier = 999 } })
	entities[#entities + 1] = { e, { -1, 0 } }
	expected[#expected + 1] = "OTHER"
	addCargo(e + 1, 1, -1, { { line = 1 } })
	entities[#entities + 1] = { e + 1, { -1, 0 } }
	L.needed = { carrier = true }
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = entities })
	local got = {}
	for i, f in ipairs(L.delivered[1].facts) do got[i] = f.carrier end
	eq(got, expected) -- the last fact has no carrier (nil is not stored)
	eq(#L.delivered[1].facts, #entities)
	eq(L.delivered[1].facts[#entities], { kind = "cargo" })
end)

test("facts are nil-safe: missing components, odd entries, deleted or negative entities", function()
	local st = activeState()
	buildTowns()
	addCargo(101, 2, 999, {})                          -- source entity does not exist, no pickup points
	addCargo(102, 3, 400, nil)                         -- source is an industry stock list (no town), no pickupPoints
	addCargo(103, 4, 300, { { line = -1, carrier = CARRIER.AIR } }) -- line -1 = none
	A.comp[104] = { [CT.CONSTRUCTION] = {} }           -- a construction without townBuildings
	A.comp[105] = { [CT.CONSTRUCTION] = { townBuildings = {} } }
	L.needed = ALL_NEEDS
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = {
		{ 100, { 200, 0 } },        -- no SIM_CARGO at all
		{ 101, { -1, 0 } },         -- negative target
		{ 102, { 104, 0 } },        -- construction without townBuildings
		{ 103, { 105, 0 } },        -- empty townBuildings
		{ 101, "x" },               -- malformed target
		7,                          -- not a table
		{ "a", nil },               -- garbage
	} })
	eq(L.delivered[1].units, 7)
	eq(L.delivered[1].facts, {
		{ kind = "cargo", toTown = 9 }, -- the target still resolves without SIM_CARGO
		{ kind = "cargo", cargoType = 2 },
		{ kind = "cargo", cargoType = 3 },
		{ kind = "cargo", cargoType = 4, fromTown = 8, carrier = "AIR" },
		{ kind = "cargo", cargoType = 2 },
		{ kind = "cargo" },
		{ kind = "cargo" },
	})
	-- persons: no SIM_PERSON, no destinations, missing lastNonResType when going home
	A.comp[501] = { [CT.SIM_PERSON] = { targetOrAtEntity = 201 } }
	A.comp[502] = { [CT.SIM_PERSON] = { targetOrAtEntity = 210, destinations = { 210, 201 } } }
	ev(st, "SimPersonSystem", "OnCompletedLineUsage", { entities = { 500, 501, 502, "z" } })
	eq(L.delivered[2].facts, {
		{ kind = "passenger" },
		{ kind = "passenger", toTown = 9 },
		{ kind = "passenger", toTown = 7 },
		{ kind = "passenger" },
	})
end)

test("passenger facts: toTown from targetOrAtEntity, fromTown like arrivaltracker person2source", function()
	local st = activeState()
	buildTowns()
	-- to work (target ~= home): source = home = destinations[1]
	A.comp[500] = { [CT.SIM_PERSON] = { targetOrAtEntity = 200, destinations = { 210, 200, 300 }, lastNonResType = 1 } }
	-- went home (target == destinations[1]): source = destinations[lastNonResType + 1]
	A.comp[501] = { [CT.SIM_PERSON] = { targetOrAtEntity = 210, destinations = { 210, 220, 300 }, lastNonResType = 2 } }
	L.needed = { toTown = true, fromTown = true }
	ev(st, "SimPersonSystem", "OnCompletedLineUsage", { entities = { 500, 501 } })
	eq(L.delivered[1].kind, "passenger")
	eq(L.delivered[1].facts, {
		{ kind = "passenger", toTown = 9, fromTown = 7 },
		{ kind = "passenger", toTown = 7, fromTown = 8 },
	})
	-- persons never carry cargoType/line/carrier even when asked
	L.needed = ALL_NEEDS
	ev(st, "SimPersonSystem", "OnCompletedLineUsage", { entities = { 500 } })
	eq(L.delivered[2].facts, { { kind = "passenger", toTown = 9, fromTown = 7 } })
end)

-- handleLegacy migration (PLAN §9.8) ------------------------------------------------------------

test("handleLegacy on an active state: migrate, run its intents, re-subscribe, set", function()
	local st = activeState()
	local s = st.value
	s.version = 1
	st.value = s
	st.subs = {}
	L.migrateImpl = function(state)
		state.version = 2
		state.rewardMultRound = 1.0
		return state, { { kind = "log", message = "migrated v1 -> v2" } }
	end
	local sets = st.sets
	ev(st, "", "handleLegacy", nil)
	eq(L.migrateCalls, 1)
	eq(st.value.version, 2)
	eq(st.value.rewardMultRound, 1.0)
	eq(st.sets, sets + 1)
	eq(st.subs, ALL_SUBS)
	ok(has(logText(), "[QuotaRun] migrated v1 -> v2"))
end)

test("handleLegacy never migrates an inert or deactivated state", function()
	for _, initial in ipairs({ false, true, "off" }) do
		local value = initial == "off" and { version = 1, active = false } or (initial and {} or nil)
		local st = makeState(value)
		ev(st, "", "handleLegacy", nil)
		eq(st.sets, 0)
		eq(st.value, value)
	end
	eq(L.migrateCalls, 0)
end)

test("real logic: handleLegacy upgrades a v1 state to version 2 (needs logic.migrate)", function()
	local st = activeState()
	local s = st.value
	s.version = 1
	s.rule, s.boss, s.nextBoss, s.cardVehicleMods, s.rewardMultRound, s.tally, s.lastTally = nil, nil, nil, nil, nil, nil, nil
	st.value = s
	L.migrateImpl = function(state) return realModule.new(config, ug_require "/quota/quota_cards.tl").migrate(state) end
	ev(st, "", "handleLegacy", nil)
	eq(st.value.version, 2)
	eq(st.subs, ALL_SUBS)
end)

-- probes: gating ------------------------------------------------------------------------------

local PROBES = {
	{ "incomeProbe", { n = 150 } }, { "factsProbe", { n = 5 } }, { "jumpYears", { n = 1 } },
	{ "closeIndustry", { n = 2 } }, { "townProbe", {} },
}

test("probes with DEBUG = false on an active run: rejected like every debug op, nothing changes", function()
	local st = activeState()
	buildTowns()
	config.DEBUG = false
	local before = deepcopy(st.value)
	A.sent = {}
	clear_logs()
	for _, p in ipairs(PROBES) do dbg(st, p[1], p[2]) end
	eq(st.value, before)
	eq(A.sent, {})
	eq(st.subs, ALL_SUBS)
	ok(has(warnings(), "DEBUG is off"))
	ok(not has(logText(), "P1"))
end)

test("probes on an inert save (DEBUG): refused, nothing written", function()
	local st = makeState(nil)
	A.added = true
	script.update({}, st, 0.5)
	for _, p in ipairs(PROBES) do dbg(st, p[1], p[2]) end
	eq(st.sets, 0)
	eq(st.value, nil)
	eq(A.sent, {})
	eq(st.subs, { ["QuotaRun.debug"] = true })
	ok(has(warnings(), "debug incomeProbe ignored: no run in this save"))
	ok(has(warnings(), "debug townProbe ignored: no run in this save"))
end)

test("probes with bad parameters: warning, no state change, no command", function()
	local st = activeState()
	buildTowns()
	local before = deepcopy(st.value)
	A.sent = {}
	local bad = {
		{ "incomeProbe", nil }, { "incomeProbe", -1 }, { "incomeProbe", 1001 }, { "incomeProbe", 1.5 },
		{ "factsProbe", 0 }, { "factsProbe", 201 }, { "factsProbe", nil },
		{ "jumpYears", 0 }, { "jumpYears", 101 }, { "jumpYears", 2.5 },
		{ "closeIndustry", 0 }, { "closeIndustry", 241 }, { "closeIndustry", nil },
		{ "townProbe", 0 }, { "townProbe", 2 }, -- one town in this world
	}
	for _, b in ipairs(bad) do dbg(st, b[1], { n = b[2] }) end
	eq(st.value, before)
	eq(A.sent, {})
	eq(st.subs, ALL_SUBS)
	local w = warnings()
	ok(has(w, "debug incomeProbe ignored: missing or invalid n 1001 (allowed 0..1000)"))
	ok(has(w, "debug factsProbe ignored: missing or invalid n 201 (allowed 1..200)"))
	ok(has(w, "debug jumpYears ignored: missing or invalid n nil (allowed 1..100)")) -- 2.5 is not an integer
	ok(has(w, "debug closeIndustry ignored: missing or invalid n 241 (allowed 1..240)"))
	ok(has(w, "debug townProbe ignored: missing or invalid n 2 (allowed 1..1)"))
	eq(#L.debugInputs, 0) -- probes never reach the logic
end)

-- P1 incomeProbe ----------------------------------------------------------------------------------

local function ticket(st, id, entries)
	return ev(st, id or "TransportVehicleSystem", "OnCalcTicketPrice", entries or {
		{ vehicleEntity = 1, lineEntity = 2, simEntity = 3, stockListEntity = 4, basePrice = 100, distance = 5000 },
	})
end

test("P1 incomeProbe: subscribe, return {[0] = mult} for both sources, log 10, then off", function()
	local st = activeState()
	ticket(st) -- not subscribed, no probe: ignored
	eq(ticket(st), nil)
	dbg(st, "incomeProbe", { n = 150 })
	eq(st.value.probe, { incomeMult = 1.5, incomeLogLeft = 10 })
	eq(st.subs, withTicket(ALL_SUBS))
	ok(has(warnings(), "P1 incomeProbe ON: returning {[0] = 1.5}"))
	ok(has(warnings(), "ticketPriceMultiplier=1.25"))
	eq(#L.debugInputs, 0)
	-- handler: one get() per event; set() only while logging
	local sets, gets = st.sets, st.gets
	for i = 1, 12 do
		local r = ticket(st, i % 2 == 0 and "SimEntityAtVehicleSystem" or "TransportVehicleSystem")
		eq(r, { [0] = 1.5 })
	end
	eq(st.gets - gets, 12)
	eq(st.sets - sets, 10)
	eq(st.value.probe, { incomeMult = 1.5 })
	local p1 = 0
	for _, e in ipairs(log_entries()) do if has(e.msg, "P1 OnCalcTicketPrice from ") then p1 = p1 + 1 end end
	eq(p1, 10)
	ok(has(logText(), "first={basePrice=100, distance=5000, lineEntity=2, simEntity=3, stockListEntity=4, vehicleEntity=1}"))
	-- other ids / names never get a multiplier
	eq(ev(st, "SimCargoSystem", "OnCalcTicketPrice", {}), nil)
	-- off
	dbg(st, "incomeProbe", { n = 0 })
	eq(st.value.probe, nil)
	eq(st.subs, ALL_SUBS)
	eq(ticket(st), nil)
end)

test("P1 subscription follows phase changes and survives handleLegacy; DEBUG off ignores a stale probe", function()
	local st = activeState()
	dbg(st, "incomeProbe", { n = 60 })
	dbg(st, "failRound") -- -> ended: metric subscriptions dropped, probe kept
	eq(st.value.phase, "ended")
	eq(st.subs, withTicket({ ["QuotaRun.pickCard"] = true, ["QuotaRun.continueSandbox"] = true, ["QuotaRun.debug"] = true }))
	dbg(st, "reset") -- fresh run: probe dropped with the old state, subscription re-synced
	eq(st.value.probe, nil)
	eq(st.subs, ALL_SUBS)
	dbg(st, "incomeProbe", { n = 60 })
	st.subs = {}
	ev(st, "", "handleLegacy", nil)
	eq(st.subs, withTicket(ALL_SUBS))
	eq(ticket(st), { [0] = 0.6 })
	-- a release build loading this save: no subscription, no multiplier
	config.DEBUG = false
	ev(st, "", "handleLegacy", nil)
	eq(st.subs, ALL_SUBS)
	eq(ticket(st), nil)
end)

-- P2 factsProbe ---------------------------------------------------------------------------------

test("P2 factsProbe: logs every field of the next n entities; the logic input is unchanged", function()
	local st = activeState()
	buildTowns()
	addCargo(100, 5, 300, { { line = 41, carrier = CARRIER.WATER } })
	dbg(st, "factsProbe", { n = 3 })
	eq(st.value.probe, { factsLeft = 3 })
	ok(has(logText(), "P2 factsProbe: logging the next 3 delivered entities"))
	-- factsNeeded nil: still the units-only input
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 0 } }, { 100, { 200, 0 } } } })
	eq(L.delivered[1], { units = 2, kind = "cargo" })
	ok(has(logText(), 'P2 fact {cargoType=5, carrier="WATER", fromTown=8, kind="cargo", line=41, toTown=9} (entry table, 2 left)'))
	eq(st.value.probe, { factsLeft = 1 })
	-- factsNeeded set: the logic gets only the needed fields; the probe runs out mid-event
	L.needed = { cargoType = true }
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 0 } }, { 100, { 200, 0 } } } })
	eq(L.delivered[2].facts, { { kind = "cargo", cargoType = 5 }, { kind = "cargo", cargoType = 5 } })
	ok(has(logText(), "(entry table, 0 left)"))
	eq(st.value.probe, nil)
	local count = 0
	for _, e in ipairs(log_entries()) do if has(e.msg, "P2 fact {") then count = count + 1 end end
	eq(count, 3)
end)

-- P3 jumpYears ----------------------------------------------------------------------------------

test("P3 jumpYears: sets the calendar n years ahead (day clamped), logs before/after, loud warning", function()
	local st = activeState()
	local before = deepcopy(st.value)
	A.sent = {}
	dbg(st, "jumpYears", { n = 3 })
	eq(#A.sent, 1)
	eq(A.sent[1].kind, "date")
	eq({ A.date.year, A.date.month, A.date.day }, { 1903, 2, 28 })
	ok(has(warnings(), "!!! P3 jumpYears 3 (debug) !!! NOT REVERSIBLE: setting the calendar from 1900-2-29 to 1903-2-28"))
	ok(has(logText(), "P3 jumpYears: date before=1900-2-29 after=1903-2-28"))
	eq(st.value, before) -- no run state involved
end)

-- P4 closeIndustry ------------------------------------------------------------------------------

local function addIndustry(e, opts)
	local construction = e + 50
	A.comp[e] = { [CT.INDUSTRY] = { stockList = e + 100, construction = construction, closureTimeStamp = 0,
		manualDevelopment = opts.manual or false } }
	if opts.playerOwned then A.comp[e][CT.PLAYER_OWNED] = {} end
	A.comp[construction] = { [CT.CONSTRUCTION] = { depots = opts.depots or {} }, [CT.NAME] = { name = "Mine " .. e } }
	A.io[e + 100] = { {}, opts.output and { 1 } or {} }
end

test("P4 closeIndustry: deterministic pick among closable industries, despawn = now + n months (game time)", function()
	local st = activeState()
	addIndustry(600, { output = true, manual = true })
	addIndustry(601, { output = true, playerOwned = true })
	addIndustry(602, { output = true })
	addIndustry(603, { output = false })
	addIndustry(604, { output = true, depots = { 9 } })
	addIndustry(605, { output = true })
	A.gameTime = 5000
	local seed = st.value.rngSeed
	A.sent = {}
	dbg(st, "closeIndustry", { n = 12 })
	eq(#A.sent, 1)
	local cmd = A.sent[1]
	eq(cmd.kind, "despawn")
	ok(cmd.entity == 602 or cmd.entity == 605, tostring(cmd.entity))
	eq(cmd.time, 5000 + 12 * MD)
	ok(st.value.rngSeed ~= seed, "rngSeed advanced")
	local w = warnings()
	ok(has(w, "!!! P4 closeIndustry (debug) !!! industry " .. cmd.entity .. ' "Mine ' .. cmd.entity .. '" (2 candidates)'))
	ok(has(w, "despawn time 0 -> 17000 (now 5000 + 12 months), reads back 17000"))
	-- same seed -> same pick
	local st2 = activeState()
	local s2 = st2.value
	s2.rngSeed = seed
	st2.value = s2
	A.sent = {}
	dbg(st2, "closeIndustry", { n = 12 })
	eq(A.sent[1].entity, cmd.entity)
end)

test("P4 closeIndustry with no closable industry: warning, nothing sent, no state change", function()
	local st = activeState()
	addIndustry(603, { output = false })
	local before = deepcopy(st.value)
	A.sent = {}
	dbg(st, "closeIndustry", { n = 6 })
	eq(A.sent, {})
	eq(st.value, before)
	ok(has(warnings(), "debug closeIndustry ignored: no industry the base could close"))
end)

-- P6 townProbe ----------------------------------------------------------------------------------

test("P6 townProbe: logs the TOWN component (developmentActive) of the n-th town by entity id", function()
	local st = activeState()
	A.comp[900] = { [CT.TOWN] = { developmentActive = false, capacityScalingFactor = 2, sizeFactors = { 1, 2 } } }
	A.comp[800] = { [CT.TOWN] = { developmentActive = true, noise = 1.5 }, [CT.NAME] = { name = "Eightville" } }
	local before = deepcopy(st.value)
	A.sent = {}
	dbg(st, "townProbe")
	ok(has(logText(), 'P6 townProbe 1/2: {developmentActive=true, entity=800, name="Eightville", noise=1.5}'))
	dbg(st, "townProbe", { n = 2 })
	ok(has(logText(), "P6 townProbe 2/2: {capacityScalingFactor=2, developmentActive=false, entity=900, sizeFactors={[1]=1, [2]=2}}"))
	eq(st.value, before)
	eq(A.sent, {})
end)

test("P6 townProbe without towns: warning", function()
	local st = activeState()
	dbg(st, "townProbe")
	ok(has(warnings(), "debug townProbe ignored: no towns"))
end)

-- P7 mod params -----------------------------------------------------------------------------------

test("P7: activation and dump log getModParams()[modId], nil-safe", function()
	A.modParams = { character = "classic" }
	local st = activeState()
	ok(has(logText(), 'P7 modParams["square_quota_run"] (activation): {character="classic"}'))
	clear_logs()
	dbg(st, "dump")
	ok(has(logText(), "[QuotaRun] dump: {"))
	ok(has(logText(), 'P7 modParams["square_quota_run"] (dump): {character="classic"}'))
	-- absent entry
	installApi()
	clear_logs()
	activeState()
	ok(has(logText(), 'P7 modParams["square_quota_run"] (activation): nil'))
	-- getModParams() returning nil must not break the inert dump (the activation gate reads it too)
	installApi()
	clear_logs()
	A.modParamsTable = false
	local inert = makeState(nil)
	dbg(inert, "dump")
	ok(has(logText(), "dump (inert): nil"))
	ok(has(logText(), 'P7 modParams["square_quota_run"] (dump): nil'))
end)

test("P7: no mod-params line with DEBUG = false", function()
	config.DEBUG = false
	A.modParams = { character = "classic" }
	activeState()
	ok(not has(logText(), "P7"))
end)

-- v2 logic ops pass through ---------------------------------------------------------------------

test("setRule / setBoss / setNextBoss reach logic.debug with id (like applyCard)", function()
	local st = activeState()
	A.gameTime = 321
	dbg(st, "setRule", { id = "freight_only" })
	dbg(st, "setBoss", { id = "" })
	dbg(st, "setNextBoss", { id = 5 }) -- non-string id dropped
	eq(#L.debugInputs, 3)
	eq(L.debugInputs[1].op, "setRule")
	eq(L.debugInputs[1].id, "freight_only")
	eq(L.debugInputs[1].gameTime, 321)
	eq(L.debugInputs[2].op, "setBoss")
	eq(L.debugInputs[2].id, "")
	eq(L.debugInputs[3].op, "setNextBoss")
	eq(L.debugInputs[3].id, nil)
end)

-- integration with the real logic ------------------------------------------------------------------

test("real logic: setRule rail_day -> facts carry carrier, rail counts and road does not", function()
	local st = activeState()
	buildTowns()
	L.realFacts = true
	dbg(st, "setRule", { id = "rail_day" })
	eq(st.value.rule, "rail_day")
	addCargo(100, 5, 300, { { line = 41, carrier = CARRIER.RAIL } })
	addCargo(101, 5, 300, { { line = 42, carrier = CARRIER.ROAD } })
	local before = st.value.progress
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 100, { 200, 0 } } } })
	local f = L.delivered[1].facts[1]
	eq(f.carrier, "RAIL")
	local afterRail = st.value.progress
	ok(afterRail > before, "rail delivery counts")
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 101, { 200, 0 } } } })
	eq(L.delivered[2].facts[1].carrier, "ROAD")
	eq(st.value.progress, afterRail)
end)
