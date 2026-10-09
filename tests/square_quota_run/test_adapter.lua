-- quota.script.tl (sim adapter) + quota_effects.tl Phase 1 handlers, against a fake `api`
-- and a fake GameScriptState (PLAN §2.1, §4.2, §4.4).

local MD = 1000
local GS_NAME = "square_quota_run::/quota/quota.gs"

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepcopy(x) end
	return out
end

local A -- fake engine world for the current test

local function installApi()
	A = {
		gameTime = 0, speed = 1, balance = 1000000, mission = false, added = false, editor = false,
		transported = { passengersTransported = 0, cargoTransported = 0 },
		gsEntity = 77, sent = {}, gsNameAsked = nil,
	}
	local CT = { GAME_TIME = "GAME_TIME", GAME_SPEED = "GAME_SPEED", GAME_SCRIPT = "GAME_SCRIPT",
		TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE", INDUSTRY = "INDUSTRY", STOCK_LIST = "STOCK_LIST" }
	-- Phase 2 effects: no vehicles or industries in this fake world (see test_effects*.lua).
	set_global("api", {
		type = {
			ComponentType = CT,
			JournalEntry = { new = function() return { category = {} } end, Type = { OTHER = "OTHER" } },
			Vec3f = { new = function(x, y, z) return { x, y, z } end },
		},
		engine = {
			getComponent = function(e, ct)
				if ct == CT.GAME_TIME then return { gameTime = A.gameTime } end
				if ct == CT.GAME_SPEED then return { speedup = A.speed } end
				if ct == CT.GAME_SCRIPT and e == A.gsEntity then return { addedToExistingSavegame = A.added } end
				return nil
			end,
			entityExists = function(e) return false end,
			-- src: company_growth.script.tl:74 shape: getModParams()[""]["isMapEditor"]
			config = { getModParams = function() return { [""] = { isMapEditor = A.editor } } end },
			getEntitiesWithComponent = function(ct, filters) return {} end,
			util = {
				getWorld = function() return 1 end,
				getPlayer = function() return 2 end,
				hasStartedAsMission = function() return A.mission end,
				finance = { getPlayersBalance = function(p) assert(p == 2) return A.balance end },
				headquarters = { getTransportedData = function() return deepcopy(A.transported) end },
			},
			system = { gameScriptSystem = { getEntityForGameScript = function(name)
				A.gsNameAsked = name
				return A.gsEntity
			end } },
		},
		cmd = {
			-- sim-thread commands run immediately (API/api/cmd.d.tl:1-9)
			sendCommand = function(cmd)
				A.sent[#A.sent + 1] = cmd
				if cmd.kind == "speed" then A.speed = cmd.speedup end
			end,
			makeGameSetSpeedCmd = function(s) return { kind = "speed", speedup = s } end,
			makeScriptingSendEventCmd = function(src, id, name, param)
				return { kind = "event", src = src, id = id, name = name, param = param }
			end,
			makeJournalBookAssetCmd = function(p, entry, pos) return { kind = "journal", player = p, entry = entry, pos = pos } end,
		},
		util = { getDefaultMonthDuration = function() return MD end },
	})
end

local function makeState(initial)
	local st = { value = deepcopy(initial), subs = {}, sets = 0, noEvents = 0 }
	function st:get() return deepcopy(self.value) end
	function st:set(v) self.value = deepcopy(v); self.sets = self.sets + 1 end
	function st:subscribeToNoEvents() self.subs = {}; self.noEvents = self.noEvents + 1 end
	function st:subscribeToEvent(n) self.subs[n] = true end
	function st:subscribeToAllEvents() error("never subscribe to all events") end
	function st:hasEventSubscriptions() return next(self.subs) ~= nil end
	return st
end

-- quota_effects requires the base worker-boost util (not loadable offline).
stub_module("::/industries/industry_productivity_util.tl", {
	isIndustryWorkersBoosted = function() return false end,
	getPersonCapacityPotentialBoost = function() return 2.0 end,
})

local script = ug_require "/quota/quota.script.tl"
local config = ug_require "/quota/quota_config.tl"

local function ev(st, id, name, param) return script.handleEvent({}, st, "", id, name, param) end

local function activeState()
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	assert(st.value and st.value.active)
	return st
end

local function speedCmds()
	local out = {}
	for _, c in ipairs(A.sent) do if c.kind == "speed" then out[#out + 1] = c.speedup end end
	return out
end

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.level .. ": " .. e.msg end
	return table.concat(out, "\n")
end

local ALL_SUBS = { ["QuotaRun.pickCard"] = true, ["QuotaRun.continueSandbox"] = true, ["QuotaRun.debug"] = true,
	OnToArriveAtDestination = true, OnCompletedLineUsage = true }
local GUI_SUBS = { ["QuotaRun.pickCard"] = true, ["QuotaRun.continueSandbox"] = true, ["QuotaRun.debug"] = true }

--- Drive an active state to `choosing` through update (round 1 cleared at its deadline).
local function toChoosing(st, speed)
	A.speed = speed or 1
	local s = st.value
	s.progress = s.quota
	st.value = s
	A.gameTime = s.roundEndTime
	script.update({}, st, 0.2)
	assert(st.value.phase == "choosing", st.value.phase)
end

before_each(function()
	installApi()
	clear_logs()
	config.DEBUG = true
	config.METRIC = "events"
end)

-- inert ---------------------------------------------------------------------------

test("inert: nil/empty state ignores every non-init event and update (release, DEBUG = false)", function()
	config.DEBUG = false
	for _, initial in ipairs({ false, true }) do
		local st = makeState(initial and {} or nil)
		ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { 1, 2 } })
		ev(st, "SimPersonSystem", "OnCompletedLineUsage", { entities = { 1 } })
		ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
		ev(st, "QuotaRun", "QuotaRun.continueSandbox", {})
		ev(st, "QuotaRun", "QuotaRun.debug", { op = "dump" })
		ev(st, "", "handleLegacy", nil)
		ev(st, "", "initMission", nil)
		ev(st, "", "initTutorial", nil)
		ev(st, "Other", "initNewGame", nil) -- wrong id
		script.update({}, st, 0.5)
		script.update({}, st, 0.0)
		eq(st.sets, 0)
		eq(st.noEvents, 0)
		eq(st.subs, {})
		eq(A.sent, {})
		eq(log_entries(), {})
	end
end)

-- activation ------------------------------------------------------------------------

test("activation on initNewGame: state, subscriptions, log", function()
	A.gameTime = 4321
	A.transported = { passengersTransported = 5, cargoTransported = 6 }
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	local s = st.value
	eq(s.active, true)
	eq(s.phase, "running")
	eq(s.runStartTime, 4321)
	eq(s.monthDuration, MD)
	eq(s.statsBaseline, 11)
	eq(st.subs, ALL_SUBS)
	ok(st.noEvents >= 1, "subscribeToNoEvents first")
	eq(A.gsNameAsked, GS_NAME)
	ok(logText():find("[QuotaRun] activated", 1, true))
	eq(speedCmds(), {})
end)

test("activation on initNewGameFromMap", function()
	local st = makeState(nil)
	ev(st, "", "initNewGameFromMap", nil)
	eq(st.value.active, true)
end)

test("second init event is ignored (idempotent)", function()
	local st = activeState()
	local s = st.value
	s.progress = 99
	st.value = s
	local sets = st.sets
	A.gameTime = 50000
	ev(st, "", "initNewGame", nil)
	eq(st.sets, sets)
	eq(st.value.progress, 99)
end)

test("rejected when started as a mission", function()
	A.mission = true
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	eq(st.value, nil)
	eq(st.sets, 0)
	eq(st.subs, {})
	ok(not logText():find("activated", 1, true))
end)

test("rejected when added to an existing savegame", function()
	A.added = true
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	eq(st.value, nil)
	eq(st.sets, 0)
	eq(st.subs, {})
	ok(logText():find("existing savegame", 1, true))
end)

test("missing own GAME_SCRIPT entity does not block activation", function()
	A.gsEntity = -1
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	eq(st.value.active, true)
end)

-- handleLegacy ----------------------------------------------------------------------

test("handleLegacy on an active save re-subscribes (no other change)", function()
	local st = activeState()
	st.subs = {}
	local before = deepcopy(st.value)
	ev(st, "", "handleLegacy", nil)
	eq(st.subs, ALL_SUBS)
	eq(st.value, before)
end)

test("handleLegacy in sandbox subscribes only to QuotaRun.* events", function()
	local st = activeState()
	local s = st.value
	s.phase = "sandbox"
	st.value = s
	ev(st, "", "handleLegacy", nil)
	eq(st.subs, GUI_SUBS)
end)

-- delivered routing -------------------------------------------------------------------

test("metric events route to delivered (cargo + passengers); mismatched ids ignored", function()
	local st = activeState()
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { { 1, { 2, 3 } }, { 4, { 5, 6 } }, { 7, { 8, 9 } } } })
	eq(st.value.progress, 3)
	ev(st, "SimPersonSystem", "OnCompletedLineUsage", { entities = { 10, 11 } })
	eq(st.value.progress, 5)
	ev(st, "SimCargoSystem", "OnCompletedLineUsage", { entities = { 1 } })
	ev(st, "SimPersonSystem", "OnToArriveAtDestination", { entities = { 1 } })
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", nil)
	ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = "x" })
	eq(st.value.progress, 5)
end)

-- update ----------------------------------------------------------------------------

test("update: dt == 0 does nothing even when a deadline is due", function()
	local st = activeState()
	A.gameTime = 10 * MD
	local sets = st.sets
	script.update({}, st, 0.0)
	eq(st.sets, sets)
	eq(st.value.redMonths, 0)
	eq(st.value.nextMonthTick, MD)
end)

test("update: no state write when nothing is due", function()
	local st = activeState()
	local sets = st.sets
	A.gameTime = 10
	script.update({}, st, 0.2)
	eq(st.sets, sets)
end)

test("update: month tick reads balance and catches up", function()
	local st = activeState()
	A.balance = -5
	A.gameTime = 3 * MD
	script.update({}, st, 0.2)
	eq(st.value.redMonths, 3)
	eq(st.value.nextMonthTick, 4 * MD)
	ok(logText():find("[QuotaRun] month 3:", 1, true))
end)

test("update: infinite money (nil balance) skips bankruptcy", function()
	local st = activeState()
	A.balance = nil
	A.gameTime = 7 * MD
	script.update({}, st, 0.2)
	eq(st.value.redMonths, 0)
	eq(st.value.phase, "running")
end)

-- pause / resume ------------------------------------------------------------------------

test("round end pauses and saves speed; pick restores it while still paused", function()
	local st = activeState()
	toChoosing(st, 4)
	eq(A.speed, 0)
	eq(st.value.savedSpeed, 4)
	eq(st.value.round, 2)
	local journal
	for _, c in ipairs(A.sent) do if c.kind == "journal" then journal = journal or c end end
	ok(journal and journal.entry.amount == 2000000)
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
	eq(st.value.phase, "running")
	eq(A.speed, 4)
	eq(st.value.savedSpeed, 0)
	eq(st.subs, ALL_SUBS)
end)

test("pick leaves speed alone if the player already unpaused", function()
	local st = activeState()
	toChoosing(st, 4)
	A.speed = 2 -- player unpaused from the game bar
	local n = #speedCmds()
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 3 })
	eq(st.value.phase, "running")
	eq(A.speed, 2)
	eq(#speedCmds(), n)
end)

test("savedSpeed 0 restores as 1", function()
	local st = activeState()
	toChoosing(st, 0) -- already paused when the round ended
	eq(st.value.savedSpeed, 0)
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 2 })
	eq(A.speed, 1)
end)

test("pickCard index from the GUI may be a float; non-integral is rejected", function()
	local st = activeState()
	toChoosing(st, 1)
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1.5 })
	eq(st.value.phase, "choosing")
	ok(logText():find("bad index", 1, true))
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 2.0 })
	eq(st.value.phase, "running")
end)

test("cash card books a journal entry of type OTHER for the player", function()
	local st = activeState()
	toChoosing(st, 1)
	local s = st.value
	s.offer = { "venture", "express", "gamble" }
	st.value = s
	A.sent = {}
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
	local j = A.sent[1]
	eq(j.kind, "journal")
	eq(j.player, 2)
	eq(j.entry.amount, 8000000)
	eq(j.entry.time, -1)
	eq(j.entry.category.type, "OTHER")
end)

test("vehicleMods / industryMods intents reach quota_effects (empty fake world)", function()
	local st = activeState()
	toChoosing(st, 1)
	local s = st.value
	s.offer = { "express", "boomtown", "gamble" }
	st.value = s
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
	ok(logText():find("vehicleMods rev=1", 1, true))
	s = st.value
	s.phase, s.offer = "choosing", { "express", "boomtown", "gamble" }
	st.value = s
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 2 })
	ok(logText():find("industryMods count=3 mult=1.5 chosen=0", 1, true))
end)

test("failure -> ended (metric subs dropped), continueSandbox -> sandbox, resumes", function()
	local st = activeState()
	A.speed = 3
	A.gameTime = st.value.roundEndTime
	script.update({}, st, 0.2)
	eq(st.value.phase, "ended")
	eq(A.speed, 0)
	eq(st.subs, GUI_SUBS)
	ok(logText():find("clearEffects: vehicles=0 industries=0", 1, true))
	ev(st, "QuotaRun", "QuotaRun.continueSandbox", {})
	eq(st.value.phase, "sandbox")
	eq(A.speed, 3)
	eq(st.subs, GUI_SUBS)
	-- sandbox is inert for update
	local sets = st.sets
	A.gameTime = A.gameTime + 100 * MD
	script.update({}, st, 0.2)
	eq(st.sets, sets)
end)

test("wrong-phase QuotaRun events are logged and ignored", function()
	local st = activeState()
	local before = deepcopy(st.value)
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
	ev(st, "QuotaRun", "QuotaRun.continueSandbox", {})
	ev(st, "QuotaRun", "QuotaRun.pickCard", nil)
	ev(st, "QuotaRun", "QuotaRun.nope", {})
	eq(st.value, before)
	ok(logText():find("warning: [QuotaRun] pickCard ignored", 1, true))
	ok(logText():find("warning: [QuotaRun] continueSandbox ignored", 1, true))
	ok(logText():find("unknown event", 1, true))
end)

test("debug event: ops routed with gameTime and integer n", function()
	local st = activeState()
	A.gameTime = 500
	ev(st, "QuotaRun", "QuotaRun.debug", { op = "addProgress", n = 7.0 })
	eq(st.value.progress, 7)
	ev(st, "QuotaRun", "QuotaRun.debug", { op = "setMonthsLeft", n = 2 })
	eq(st.value.roundEndTime, 2500)
	ev(st, "QuotaRun", "QuotaRun.debug", { op = "endRound" })
	eq(st.value.roundEndTime, 500)
	ev(st, "QuotaRun", "QuotaRun.debug", { op = "offer" })
	eq(st.value.phase, "choosing")
	eq(st.subs, ALL_SUBS)
	ev(st, "QuotaRun", "QuotaRun.debug", { op = "dump" })
	ok(logText():find("[QuotaRun] dump: {", 1, true))
	config.DEBUG = false
	ev(st, "QuotaRun", "QuotaRun.debug", { op = "addProgress", n = 5 })
	eq(st.value.progress, 7)
end)


-- Phase 4 safety: missions, tutorial, map editor, initNewGameFromMap ---------------------------

local function notifyKeys()
	local out = {}
	for _, c in ipairs(A.sent) do
		if c.kind == "event" and c.id == "Notifications" then out[#out + 1] = c.param.params.key end
	end
	return out
end

for _, name in ipairs({ "initMission", "initTutorial" }) do
	test(name .. " after an active initNewGame: run turned off, inert, no subscriptions", function()
		local st = activeState()
		ev(st, "", name, nil)
		eq(st.value, { version = 2, active = false })
		eq(st.subs, {})
		ok(logText():find("deactivated: " .. name, 1, true))
		-- stays inert: later init events and updates do nothing
		local sets = st.sets
		A.sent = {}
		ev(st, "", "initNewGame", nil)
		ev(st, "", "initNewGameFromMap", nil)
		ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { 1 } })
		A.gameTime = 100 * MD
		script.update({}, st, 0.5)
		eq(st.sets, sets)
		eq(A.sent, {})
	end)
end

test("initMission while choosing resumes the speed we paused", function()
	local st = activeState()
	toChoosing(st, 3)
	eq(A.speed, 0)
	ev(st, "", "initMission", nil)
	eq(A.speed, 3)
	eq(st.value.active, false)
end)

test("initMission on an inert state writes nothing", function()
	local st = makeState(nil)
	ev(st, "", "initMission", nil)
	ev(st, "", "initTutorial", nil)
	eq(st.sets, 0)
	eq(st.noEvents, 0)
	eq(st.value, nil)
end)

test("map editor: never activates (initNewGame or initNewGameFromMap)", function()
	A.editor = true
	for _, name in ipairs({ "initNewGame", "initNewGameFromMap" }) do
		local st = makeState(nil)
		ev(st, "", name, nil)
		eq(st.value, nil)
		eq(st.sets, 0)
		eq(st.subs, {})
	end
	ok(logText():find("map editor", 1, true))
end)

test("initNewGameFromMap after an active initNewGame re-initialises fresh and re-sends roundStart", function()
	local st = activeState()
	local s = st.value
	s.progress, s.round, s.redMonths = 77, 4, 2
	st.value = s
	A.gameTime = 900
	A.sent = {}
	ev(st, "", "initNewGameFromMap", nil)
	eq(st.value.active, true)
	eq(st.value.round, 1)
	eq(st.value.progress, 0)
	eq(st.value.redMonths, 0)
	eq(st.value.runStartTime, 900)
	eq(st.subs, ALL_SUBS)
	eq(notifyKeys(), { "roundStart" })
	ok(logText():find("re-initialising the run on initNewGameFromMap", 1, true))
	-- a second FromMap re-initialises again (still no duplicate state), plain initNewGame never does
	local sets = st.sets
	ev(st, "", "initNewGame", nil)
	eq(st.sets, sets)
end)

test("initNewGameFromMap re-init still respects the mission / existing-save / editor gates", function()
	for _, gate in ipairs({ "mission", "added", "editor" }) do
		installApi()
		local st = activeState()
		local before = deepcopy(st.value)
		A[gate] = true
		ev(st, "", "initNewGameFromMap", nil)
		eq(st.value, before, gate)
	end
end)

test("initNewGameFromMap does not revive a deactivated (active=false) state", function()
	local st = activeState()
	ev(st, "", "initMission", nil)
	ev(st, "", "initNewGameFromMap", nil)
	eq(st.value.active, false)
end)

-- Phase 4 perf: capped clearEffects continues in ended / sandbox ------------------------------

test("capped clearEffects continues on later frames in ended and sandbox", function()
	local st = activeState()
	local alive = {}
	for e = 1000, 1449 do alive[e] = true end
	api.engine.entityExists = function(e) return alive[e] == true end
	local s = st.value
	for e = 1000, 1449 do s.fx.vehicleApplied[e] = 1 end
	s.fx.vehicleMods = { TopSpeed = 1.15 }
	st.value = s
	local cap = config.VEHICLE_SENDS_PER_FRAME
	local function changeCount()
		local n = 0
		for _, c in ipairs(A.sent) do if c.kind == "event" and c.name == "ChangeModifier" then n = n + 1 end end
		return n
	end
	-- fail round 1 -> ended -> clearEffects (capped)
	A.gameTime = st.value.roundEndTime
	script.update({}, st, 0.2)
	eq(st.value.phase, "ended")
	eq(changeCount(), cap)
	eq(st.value.fx.vehicleMods, {})
	ok(logText():find("capped, continuing", 1, true))
	-- paused (dt == 0): no continuation
	script.update({}, st, 0.0)
	eq(changeCount(), cap)
	-- unpaused frame in ended: next batch
	script.update({}, st, 0.2)
	eq(changeCount(), 2 * cap)
	-- sandbox continues too, until done; every removal is an empty modifications table
	ev(st, "QuotaRun", "QuotaRun.continueSandbox", {})
	script.update({}, st, 0.2)
	eq(changeCount(), 450)
	eq(st.value.fx.vehicleApplied, {})
	for _, c in ipairs(A.sent) do
		if c.kind == "event" and c.name == "ChangeModifier" then eq(c.param.modifications, {}) end
	end
	-- done: sandbox update writes nothing any more
	local sets = st.sets
	script.update({}, st, 0.2)
	eq(st.sets, sets)
end)

-- Dev panel / DEBUG escape hatch (PLAN §4.6) ---------------------------------------------------

local function dbg(st, op, extra)
	local p = { op = op }
	for k, v in pairs(extra or {}) do p[k] = v end
	return ev(st, "QuotaRun", "QuotaRun.debug", p)
end

local function warnings()
	local out = {}
	for _, e in ipairs(log_entries()) do if e.level == "warning" then out[#out + 1] = e.msg end end
	return table.concat(out, "\n")
end

test("release (DEBUG = false): an existing save is never touched, forceStart included", function()
	config.DEBUG = false
	A.added = true
	for _, initial in ipairs({ false, true }) do
		local st = makeState(initial and {} or nil)
		ev(st, "", "handleLegacy", nil)
		script.update({}, st, 0.5)
		dbg(st, "forceStart")
		dbg(st, "passRound")
		script.update({}, st, 0.5)
		eq(st.sets, 0)
		eq(st.noEvents, 0)
		eq(st.subs, {})
		eq(A.sent, {})
		eq(st.value, initial and {} or nil)
	end
	eq(log_entries(), {})
end)

test("DEBUG inert save: update subscribes to QuotaRun.debug only; nothing is written", function()
	A.added = true
	for _, initial in ipairs({ false, true }) do
		local st = makeState(initial and {} or nil)
		ev(st, "", "handleLegacy", nil)
		ev(st, "", "initNewGame", nil) -- refused: added to an existing savegame
		script.update({}, st, 0.5)
		script.update({}, st, 0.0)
		eq(st.subs, { ["QuotaRun.debug"] = true })
		eq(st.noEvents, 0)
		-- every other event and debug op leaves it alone (only log lines)
		ev(st, "SimCargoSystem", "OnToArriveAtDestination", { entities = { 1, 2 } })
		ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
		for _, op in ipairs({ "passRound", "failRound", "skipMonths", "applyCard", "addMoney", "reset", "clearEffects", "offer", "nope" }) do
			dbg(st, op, { n = 1, id = "venture" })
		end
		dbg(st, "dump")
		A.gameTime = 100 * MD
		script.update({}, st, 0.5)
		eq(st.sets, 0)
		eq(st.value, initial and {} or nil)
		eq(A.sent, {})
		eq(st.subs, { ["QuotaRun.debug"] = true })
	end
	ok(logText():find("dump (inert): ", 1, true))
	ok(warnings():find("debug passRound ignored: no run in this save", 1, true))
end)

test("DEBUG: a deactivated save (active = false) never subscribes, forceStart refused", function()
	local st = makeState({ version = 1, active = false })
	script.update({}, st, 0.5)
	eq(st.subs, {})
	-- even if a debug event reached it
	dbg(st, "forceStart")
	eq(st.sets, 0)
	eq(st.value, { version = 1, active = false })
	ok(warnings():find("forceStart refused: this run was turned off", 1, true))
end)

test("DEBUG forceStart on an existing save (addedToExistingSavegame): activates, logs loudly", function()
	A.added = true
	A.gameTime = 5000
	local st = makeState(nil)
	ev(st, "", "initNewGame", nil)
	eq(st.sets, 0)
	script.update({}, st, 0.5)
	dbg(st, "forceStart")
	eq(st.value.active, true)
	eq(st.value.phase, "running")
	eq(st.value.runStartTime, 5000)
	eq(st.subs, ALL_SUBS)
	ok(warnings():find("FORCE START (debug)", 1, true))
	ok(warnings():find("ADDED TO (existing savegame)", 1, true))
	ok(logText():find("[QuotaRun] activated", 1, true))
	-- a second forceStart on the now active run is refused by the logic
	local before = deepcopy(st.value)
	dbg(st, "forceStart")
	eq(st.value, before)
	ok(warnings():find("already active", 1, true))
end)

test("DEBUG forceStart refused in a mission and in the map editor", function()
	for _, gate in ipairs({ "mission", "editor" }) do
		installApi()
		clear_logs()
		A[gate] = true
		local st = makeState(nil)
		script.update({}, st, 0.5)
		dbg(st, "forceStart")
		eq(st.value, nil, gate)
		eq(st.sets, 0, gate)
		eq(A.sent, {}, gate)
		ok(warnings():find("forceStart refused", 1, true), gate)
	end
end)

test("DEBUG forceStart refused after initMission turned an active run off", function()
	local st = activeState()
	ev(st, "", "initMission", nil)
	local sets = st.sets
	dbg(st, "forceStart")
	eq(st.sets, sets)
	eq(st.value.active, false)
end)

test("debug passRound / failRound route through the adapter: pause, subscriptions", function()
	local st = activeState()
	A.speed = 2
	dbg(st, "passRound")
	eq(st.value.phase, "choosing")
	eq(A.speed, 0)
	eq(st.value.savedSpeed, 2)
	eq(st.subs, ALL_SUBS)
	ev(st, "QuotaRun", "QuotaRun.pickCard", { index = 1 })
	eq(st.value.phase, "running")
	dbg(st, "failRound")
	eq(st.value.phase, "ended")
	eq(st.subs, GUI_SUBS)
end)

test("debug applyCard / addMoney / skipMonths read id, n and the balance", function()
	local st = activeState()
	A.sent = {}
	dbg(st, "applyCard", { id = "venture" })
	eq(st.value.picked, { "venture" })
	dbg(st, "addMoney", { n = 10000000.0 })
	local amounts = {}
	for _, c in ipairs(A.sent) do if c.kind == "journal" then amounts[#amounts + 1] = c.entry.amount end end
	eq(amounts, { 4000000, 10000000 })
	A.balance = -1
	dbg(st, "skipMonths", { n = 2 })
	eq(st.value.redMonths, 2)
	dbg(st, "skipMonths", { n = 1.5 }) -- non-integral n is rejected
	eq(st.value.redMonths, 2)
	dbg(st, "applyCard", { id = 7 }) -- non-string id is rejected
	eq(st.value.picked, { "venture" })
	ok(warnings():find("unknown card id nil", 1, true))
end)

test("debug reset: fresh run, old effects cleared, paused game resumed", function()
	local st = activeState()
	toChoosing(st, 3)
	A.gameTime = A.gameTime + 10
	dbg(st, "reset")
	local s = st.value
	eq(s.phase, "running")
	eq(s.round, 1)
	eq(s.runStartTime, A.gameTime)
	eq(A.speed, 3)
	eq(st.subs, ALL_SUBS)
	ok(logText():find("debug reset", 1, true))
	ok(logText():find("clearEffects: vehicles=0 industries=0", 1, true))
	-- from ended: subscriptions come back
	dbg(st, "failRound")
	eq(st.subs, GUI_SUBS)
	dbg(st, "reset")
	eq(st.value.phase, "running")
	eq(st.subs, ALL_SUBS)
end)

test("debug clearEffects keeps the phase", function()
	local st = activeState()
	toChoosing(st, 1)
	dbg(st, "clearEffects")
	eq(st.value.phase, "choosing")
	ok(logText():find("clearEffects: vehicles=0 industries=0", 1, true))
end)

test("debug ops on an active run with DEBUG = false change nothing", function()
	local st = activeState()
	config.DEBUG = false
	local before = deepcopy(st.value)
	A.sent = {}
	for _, op in ipairs({ "passRound", "failRound", "skipMonths", "applyCard", "addMoney", "reset", "clearEffects", "forceStart" }) do
		dbg(st, op, { n = 1, id = "venture" })
	end
	eq(st.value, before)
	eq(A.sent, {})
	ok(warnings():find("DEBUG is off", 1, true))
end)
