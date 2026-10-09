-- Quota Run sim-thread adapter (PLAN.md §2.1, §4.2-§4.4). Thin layer: engine reads,
-- event routing, intent execution. All rules live in quota_logic.tl; all side effects
-- in quota_effects.tl. All run state lives in GameScriptState (no module-level state).
--
-- Console (DEBUG only), e.g.:
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "endRound" }))
--   ops: endRound | addProgress {n} | setMonthsLeft {n} | bankrupt | offer | dump
--        passRound | failRound | skipMonths {n} | applyCard {id} | addMoney {n} | addQuotaPct {n}
--        clearEffects | reset | forceStart  (PLAN §4.2 / §4.6; the in-game dev panel sends the same events)
--        v2 logic ops: setRule {id} | setBoss {id} | setNextBoss {id}  ("" clears)
--        v2 probe ops (PLAN §9.9, handled HERE, never by the logic; active run only):
--          incomeProbe {n = mult x 100, 0 = off} | factsProbe {n} | jumpYears {n} | closeIndustry {n months} | townProbe {n?}
-- src (console pattern): .cache/game/base/content/game_mechanics/subventions/subventions.script.tl:9-12

local config = ug_require "/quota/quota_config.tl" as QuotaRunConfig
local cards = ug_require "/quota/quota_cards.tl" as QuotaRunCards
local rules = ug_require "/quota/quota_rules.tl" as QuotaRunRules
local bosses = ug_require "/quota/quota_bosses.tl" as QuotaRunBosses
local logic = (ug_require "/quota/quota_logic.tl" as QuotaRunLogicModule).new(config, cards, rules, bosses)
local effects = ug_require "/quota/quota_effects.tl" as QuotaRunEffects

-- Game-script name of this script.
-- src: .cache/game/mods/release/urbangames_campaign_mission_08/content/mission/mission_story.tl:891 (mod gs name pattern)
local GS_NAME <const> = "square_quota_run::/quota/quota.gs"
local EVENT_ID <const> = "QuotaRun"
local EV_PICK <const> = "QuotaRun.pickCard"
local EV_CONTINUE <const> = "QuotaRun.continueSandbox"
local EV_DEBUG <const> = "QuotaRun.debug"
local EV_CARGO <const> = "OnToArriveAtDestination"
local EV_PERSON <const> = "OnCompletedLineUsage"
-- P1 income probe (PLAN §9.5/§9.9). Same event name and source ids as the base handler:
-- src: .cache/game/base/content/game_mechanics/company/company_growth.script.tl:121 (subscribe), :159 (ids)
local EV_TICKET <const> = "OnCalcTicketPrice"
local ID_TICKET_CARGO <const> = "TransportVehicleSystem"
local ID_TICKET_PERSON <const> = "SimEntityAtVehicleSystem"
local MOD_ID <const> = "square_quota_run"
local PREFIX <const> = "[QuotaRun] "

local function getGameTime() : integer
	-- src: .cache/game/base/content/game_mechanics/subventions/subventions.script.tl:231
	-- src: .cache/game/api/tealdef/api/engine.d.tl:424-438 (GameTime.gameTime)
	local gt : Engine.Component.GameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gt.gameTime
end

local function getBalance() : integer
	-- nil = infinite money.
	-- src: .cache/game/base/content/game_mechanics/finance/loan.script.tl:47
	-- src: .cache/game/api/tealdef/api/engine/util.d.tl:858-861 (getPlayersBalance), :1023 (getPlayer)
	return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
end

local function getStatsTotal() : integer
	-- Diagnostic / METRIC = "stats" only.
	-- src: .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.script.tl:16-20
	-- src: .cache/game/api/tealdef/api/engine/util.d.tl:898, api/type.d.tl:150-153 (TransportationStats)
	local data = api.engine.util.headquarters.getTransportedData()
	if data == nil then return nil end
	return (data.passengersTransported or 0) + (data.cargoTransported or 0)
end

local function addedToExistingSavegame() : boolean
	-- Our own GAME_SCRIPT component (rule 2.1).
	-- src: .cache/game/base/content/game_mechanics/company/company_util.tl:284-285 (entity + GAME_SCRIPT component)
	-- src: .cache/game/api/tealdef/api/engine/system.d.tl:319-323 (getEntityForGameScript)
	-- src: .cache/game/api/tealdef/api/engine.d.tl:401-412 (GameScript.addedToExistingSavegame)
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(GS_NAME)
	if entity == nil or entity < 0 then return false end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<QuotaRunState>
	return gs ~= nil and gs.addedToExistingSavegame == true
end

local function isMapEditor() : boolean
	-- Never activate in the map editor (Phase 4). Same check as the base:
	-- src: .cache/game/base/content/game_mechanics/company/company_growth.script.tl:74,
	-- company.script.tl:232, towns/towns.script.tl:58; API: .cache/game/api/tealdef/api/engine.d.tl:1807 (getModParams)
	local params = api.engine.config.getModParams()
	local base = params ~= nil and params[""] or nil
	return base ~= nil and base["isMapEditor"] == true
end

--- P7 (PLAN §9.9, DEBUG only): does getModParams() carry our own mod's params at runtime?
--- Read-only log line, nil-safe at every step.
-- src: .cache/game/api/tealdef/api/engine.d.tl:1807 (getModParams : {string : table}); base reads
-- the "" entry the same way (company_growth.script.tl:74)
local function logModParams(where : string)
	local params = api.engine.config.getModParams()
	local mine : table = params ~= nil and params[MOD_ID] or nil
	log.message(PREFIX .. "P7 modParams[\"" .. MOD_ID .. "\"] (" .. where .. "): " .. logic.dump(mine))
end

local function inPlay(s : QuotaRunState) : boolean
	return s.phase == "running" or s.phase == "choosing"
end

--- P1: the income probe is on (DEBUG builds only; a release build ignores a stale probe in a save).
local function incomeProbeOn(s : QuotaRunState) : boolean
	return config.DEBUG and s.probe ~= nil and s.probe.incomeMult ~= nil
end

--- Subscriptions for an active run: GUI/console events always; metric events only while in play.
-- Pattern: subscribeToNoEvents() first, then re-subscribe.
-- src: .cache/game/base/content/game_mechanics/subventions/subventions.script.tl:375-383
local function syncSubscriptions(state : GameScriptState<QuotaRunState>, s : QuotaRunState)
	-- src: .cache/game/base/tealdef/scripts/gamescript.d.tl:40-49 (subscribeToNoEvents/subscribeToEvent :47-48) (GameScriptState)
	state:subscribeToNoEvents()
	state:subscribeToEvent(EV_PICK)
	state:subscribeToEvent(EV_CONTINUE)
	state:subscribeToEvent(EV_DEBUG)
	if inPlay(s) then
		-- src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:74-75
		state:subscribeToEvent(EV_CARGO)
		state:subscribeToEvent(EV_PERSON)
	end
	if incomeProbeOn(s) then
		-- P1 only (DEBUG): per-ticket handler, so subscribe only while the probe is on (PLAN §9.5).
		-- src: .cache/game/base/content/game_mechanics/company/company_growth.script.tl:121
		state:subscribeToEvent(EV_TICKET)
	end
end

--- Execute intents, keep subscriptions in step with the phase, persist.
local function commit(state : GameScriptState<QuotaRunState>, oldPhase : string, s : QuotaRunState, intents : {QuotaRunIntent})
	effects.run(s, intents)
	if s.phase ~= oldPhase then
		syncSubscriptions(state, s)
	end
	state:set(s)
end

--- Undo our side effects on an active state: remove vehicle/industry effects and, if we
--- paused the game (choosing/ended), restore the speed.
local function cleanUp(s : QuotaRunState)
	local intents : {QuotaRunIntent} = { { kind = "clearEffects" } }
	if s.phase == "choosing" or s.phase == "ended" then
		intents[#intents + 1] = { kind = "resume" }
	end
	effects.run(s, intents)
end

--- initMission / initTutorial on an ACTIVE state (Phase 4 safety fix): in the base a mission
--- start gets initNewGame and then initMission (.cache/game/base/content/mission/mission_sim.script.tl:830-845;
--- company.script.tl:379,392 resets on initMission too). If our run activated on the first event,
--- turn it off: clear effects, resume, drop every subscription, and store an inert state
--- (active = false: "already decided", so no later init event can activate it again).
local function deactivate(state : GameScriptState<QuotaRunState>, name : string)
	local s = state:get()
	if s == nil or s.active ~= true then
		return -- inert already: nothing to undo, nothing to write
	end
	cleanUp(s)
	state:subscribeToNoEvents()
	state:set({ version = s.version, active = false })
	log.message(PREFIX .. "deactivated: " .. name .. " (run turned off, state inert)")
end

--- Activate a fresh run at the current game time (gates already checked by the caller).
local function activateNow(state : GameScriptState<QuotaRunState>, s : QuotaRunState)
	local now = getGameTime()
	local n, intents = logic.activate(s, {
		gameTime = now,
		seed = now,
		-- src: .cache/game/api/tealdef/api/util.d.tl:114-116; base use: company_util.tl:14
		monthDuration = api.util.getDefaultMonthDuration(),
		statsTotal = getStatsTotal(),
	})
	if n == nil or n.active ~= true then
		effects.run(s, intents)
		return
	end
	effects.run(n, intents)
	syncSubscriptions(state, n)
	state:set(n)
	if config.DEBUG then logModParams("activation") end
end

local function tryActivate(state : GameScriptState<QuotaRunState>, name : string)
	local s = state:get()
	local reinit = false
	if s ~= nil and s.active ~= nil then
		-- initNewGameFromMap after an active start: re-initialise fresh, like the base resets its
		-- own progression on that event (src: .cache/game/base/content/game_mechanics/company/company.script.tl:392-402).
		-- This also re-sends the round-1 notification, which the notification script may have
		-- wiped when it reset on the same event (notifications.script.tl:695-699).
		if name == "initNewGameFromMap" and s.active == true then
			reinit = true
		else
			return -- idempotent: this save already decided
		end
	end
	if isMapEditor() then
		log.message(PREFIX .. "inert: " .. name .. " in the map editor")
		return
	end
	-- src: .cache/game/api/tealdef/api/engine/util.d.tl:1034-1036; same guard: company_growth.script.tl:77
	if api.engine.util.hasStartedAsMission() then
		log.message(PREFIX .. "inert: " .. name .. " in a mission")
		return
	end
	if addedToExistingSavegame() then
		log.message(PREFIX .. "inert: added to an existing savegame")
		return
	end
	if reinit then
		cleanUp(s)
		log.message(PREFIX .. "re-initialising the run on " .. name)
		s = nil
	end
	activateNow(state, s)
end

---------------------------------------------------------------------------
-- DEBUG-only escape hatch for inert saves (PLAN §4.6 "dev panel"). With config.DEBUG == false
-- none of this runs: an inert save gets no subscription, no write, no log line (rule 2.1).
-- With DEBUG == true an UNDECIDED inert save (state nil / no `active`, e.g. the mod was added to an
-- existing save) subscribes to QuotaRun.debug only, and still writes no state. The only op that
-- changes it is the explicit, user-triggered forceStart. A deactivated save (active == false,
-- mission/tutorial) never subscribes and is never revived.

--- update(), inert branch: listen for QuotaRun.debug once. Pattern (subscribe from update when
--- not yet subscribed): .cache/game/base/content/industries/industry_workers.script.tl:19-20,
--- vehicle/vehicle_modifier.script.tl:61-62; API: .cache/game/base/tealdef/scripts/gamescript.d.tl:45,48
local function listenForDebugWhileInert(state : GameScriptState<QuotaRunState>, s : QuotaRunState)
	if (s == nil or s.active == nil) and not state:hasEventSubscriptions() then
		state:subscribeToEvent(EV_DEBUG)
	end
end

local function forceStart(state : GameScriptState<QuotaRunState>, s : QuotaRunState)
	if s ~= nil and s.active == false then
		log.warning(PREFIX .. "forceStart refused: this run was turned off by a mission/tutorial start")
		return
	end
	if isMapEditor() then
		log.warning(PREFIX .. "forceStart refused: map editor")
		return
	end
	-- src: .cache/game/api/tealdef/api/engine/util.d.tl:1034-1036
	if api.engine.util.hasStartedAsMission() then
		log.warning(PREFIX .. "forceStart refused: this game started as a mission")
		return
	end
	local existing = addedToExistingSavegame()
	log.warning(PREFIX .. "!!! FORCE START (debug) !!! activating Quota Run on an inert save"
		.. (existing and " that the mod was ADDED TO (existing savegame)" or "")
		.. ". This save is now modified: save it under a NEW name.")
	activateNow(state, s)
end

--- QuotaRun.debug on an inert save (DEBUG only): forceStart, or a read-only dump.
local function handleInertDebug(state : GameScriptState<QuotaRunState>, s : QuotaRunState, param : any)
	local p : {string : any} = type(param) == "table" and param as {string : any} or {}
	local op = p.op
	if op == "forceStart" then
		forceStart(state, s)
	elseif op == "dump" then
		log.message(PREFIX .. "dump (inert): " .. logic.dump(s) .. " addedToExistingSavegame=" .. tostring(addedToExistingSavegame()))
		logModParams("dump")
	else
		log.warning(PREFIX .. "debug " .. tostring(op) .. " ignored: no run in this save (inert). Use op=forceStart on a COPY of the save.")
	end
end

local function toInteger(v : any) : integer
	-- No math.tointeger: the game's Lua runtime predates 5.3 (it is nil in game).
	if type(v) ~= "number" then return nil end
	local n = v as number
	if n ~= n or n == math.huge or n == -math.huge or n ~= math.floor(n) then return nil end
	return math.floor(n)
end

---------------------------------------------------------------------------
-- v2 delivery facts (PLAN §9.3). Resolve only the fields logic.factsNeeded asks for; with nil
-- the MVP fast path (units = #entities, no engine reads) is kept unchanged.
--
-- Cost per delivered entity (only the requested fields are read, every call nil-safe):
--   cargo:     SIM_CARGO (1 getComponent) covers cargoType + line/carrier; fromTown adds townOf(source),
--              toTown adds townOf(target); townOf = entityExists + CONSTRUCTION + TOWN_BUILDING (<= 3).
--   passenger: SIM_PERSON (1) + townOf per town field.
-- So at most ~7 engine reads per entity, the same order as the base arrival tracker per filter
-- (arrivaltracker.script.tl:36-65), and per event O(#entities). Nothing is cached in module state.

-- All fact fields: what factsProbe (P2) resolves regardless of factsNeeded.
local ALL_FACT_FIELDS : {string : boolean} = {
	cargoType = true, toTown = true, fromTown = true, line = true, carrier = true,
}
local FACTS_PROBE_MAX <const> = 200     -- P2 n upper bound

local function getComp(e : any, ct : Engine.ComponentType) : any
	if type(e) ~= "number" then return nil end
	local entity = e as integer
	if entity < 0 then return nil end
	-- src: .cache/game/api/tealdef/api/engine.d.tl:1690 (getComponent; nil when the entity lacks it)
	return api.engine.getComponent(entity, ct)
end

--- Town of a construction / town-building entity, else nil (industries, stations, deleted buildings).
--- Same walk as townbuilding2town, without its "construction or raw entity" fallback (a fact's town
--- field must be a town entity or nil).
-- src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:3-15
local function townOf(e : any) : integer
	if type(e) ~= "number" or (e as integer) < 0 then return nil end
	-- Deleted buildings: the base checks entityExists before reading a person's source building
	-- (src: .cache/game/base/content/game_mechanics/towns/town_growth.script.tl:662);
	-- API: .cache/game/api/tealdef/api/engine.d.tl:1723
	if not api.engine.entityExists(e as integer) then return nil end
	-- src: .cache/game/api/tealdef/api/engine.d.tl:295-326 (Construction.townBuildings), :1664 (CONSTRUCTION)
	local construction = getComp(e, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	local townBuildingEntity : any = e
	if construction ~= nil then
		local tbs = construction.townBuildings
		townBuildingEntity = tbs ~= nil and tbs[1] or nil
		if townBuildingEntity == nil then return nil end
	end
	-- src: .cache/game/api/tealdef/api/engine.d.tl:1305-1320 (TownBuilding.town), :1656 (TOWN_BUILDING)
	local townBuilding = getComp(townBuildingEntity, api.type.ComponentType.TOWN_BUILDING) as Engine.Component.TownBuilding
	if townBuilding == nil or townBuilding.town == nil or townBuilding.town < 0 then return nil end
	return townBuilding.town
end

--- api.type.enum.Carrier value -> contract string (QuotaRunDeliveryFact.carrier).
-- src: .cache/game/api/tealdef/api/type.d.tl:403-419 (Carrier), :2101 (Enum.Carrier), :3741 (Type.enum);
-- access path as in .cache/game/base/content/gui/line_vehicle_mgmt/vehicle_util.tl:130-152
local function carrierName(c : Carrier) : string
	if c == nil then return nil end
	local C = api.type["enum"].Carrier
	if c == C.ROAD then return "ROAD"
	elseif c == C.RAIL then return "RAIL"
	elseif c == C.TRAM then return "TRAM"
	elseif c == C.AIR then return "AIR"
	elseif c == C.WATER then return "WATER"
	end
	return "OTHER"
end

--- One cargo entry of OnToArriveAtDestination: {simCargoEntity, {targetEntity, n}}.
-- src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:128,131
local function cargoFact(item : any, need : {string : boolean}) : QuotaRunDeliveryFact
	local fact : QuotaRunDeliveryFact = { kind = "cargo" }
	if type(item) ~= "table" then return fact end
	local pair = item as {any}
	if need.cargoType or need.fromTown or need.line or need.carrier then
		-- src: .cache/game/api/tealdef/api/engine.d.tl:947-972 (SimCargo: cargoType, sourceEntity, pickupPoints), :1646
		local simCargo = getComp(pair[1], api.type.ComponentType.SIM_CARGO) as Engine.Component.SimCargo
		if simCargo ~= nil then
			if need.cargoType then fact.cargoType = simCargo.cargoType as integer end
			-- source: arrivaltracker.script.tl:56-58 compares SIM_CARGO.sourceEntity; we map it to a town
			if need.fromTown then fact.fromTown = townOf(simCargo.sourceEntity) end
			if need.line or need.carrier then
				-- Last pickup point = the leg that delivered it (PickupPoint.line / .carrier, engine.d.tl:949-960).
				local points = simCargo.pickupPoints
				local last = points ~= nil and points[#points] or nil
				if last ~= nil then
					if need.line and last.line ~= nil and last.line >= 0 then fact.line = last.line end
					if need.carrier then fact.carrier = carrierName(last.carrier) end
				end
			end
		end
	end
	if need.toTown then
		local target = type(pair[2]) == "table" and (pair[2] as {any})[1] or nil
		-- src: arrivaltracker.script.tl:51-52 (townbuilding2town(targetEntity))
		fact.toTown = townOf(target)
	end
	return fact
end

--- One OnCompletedLineUsage entity (a sim person).
-- src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:17-35 (person2goal,
-- person2source); same source rule: .cache/game/base/content/game_mechanics/towns/town_growth.script.tl:659-660
local function personFact(item : any, need : {string : boolean}) : QuotaRunDeliveryFact
	local fact : QuotaRunDeliveryFact = { kind = "passenger" }
	if not (need.toTown or need.fromTown) then return fact end
	-- src: .cache/game/api/tealdef/api/engine.d.tl:1086-1100 (SimPerson), :1643 (SIM_PERSON)
	local simPerson = getComp(item, api.type.ComponentType.SIM_PERSON) as Engine.Component.SimPerson
	if simPerson == nil then return fact end
	if need.toTown then fact.toTown = townOf(simPerson.targetOrAtEntity) end
	if need.fromTown then
		local dest = simPerson.destinations
		if dest ~= nil then
			local source : Engine.Entity = nil
			if simPerson.targetOrAtEntity == dest[1] then
				-- went home: came from the last non-residential destination (arrivaltracker.script.tl:25-28)
				if simPerson.lastNonResType ~= nil then
					source = dest[(simPerson.lastNonResType as integer) + 1]
				end
			else
				source = dest[1] -- went to shopping/work from home (:29-32)
			end
			fact.fromTown = townOf(source)
		end
	end
	return fact
end

local function resolveFact(kind : string, item : any, need : {string : boolean}) : QuotaRunDeliveryFact
	if kind == "cargo" then return cargoFact(item, need) end
	return personFact(item, need)
end

--- Copy of `fact` with only the fields in `need` (so a factsProbe never changes what the logic sees).
local function projectFact(fact : QuotaRunDeliveryFact, need : {string : boolean}) : QuotaRunDeliveryFact
	local out : QuotaRunDeliveryFact = { kind = fact.kind }
	if need.cargoType then out.cargoType = fact.cargoType end
	if need.toTown then out.toTown = fact.toTown end
	if need.fromTown then out.fromTown = fact.fromTown end
	if need.line then out.line = fact.line end
	if need.carrier then out.carrier = fact.carrier end
	return out
end

--- Drop spent probe fields; state.probe goes back to nil when no probe is running.
local function tidyProbe(s : QuotaRunState)
	local p = s.probe
	if p == nil then return end
	if p.factsLeft ~= nil and p.factsLeft <= 0 then p.factsLeft = nil end
	if p.incomeMult == nil or (p.incomeLogLeft ~= nil and p.incomeLogLeft <= 0) then p.incomeLogLeft = nil end
	if p.factsLeft == nil and p.incomeMult == nil and p.incomeLogLeft == nil then s.probe = nil end
end

local function deliveredEntities(param : any) : {any}
	if type(param) ~= "table" then return nil end
	local entities = (param as table).entities
	if type(entities) ~= "table" then return nil end
	return entities as {any}
end

local function handleDelivery(state : GameScriptState<QuotaRunState>, s : QuotaRunState, kind : string, param : any)
	local entities = deliveredEntities(param)
	local units = entities ~= nil and #entities or 0
	if units == 0 then return end
	local input : QuotaRunDeliveredInput = { units = units, kind = kind }
	local need = logic.factsNeeded(s)
	local probe = config.DEBUG and s.probe or nil
	local probing = probe ~= nil and probe.factsLeft ~= nil and probe.factsLeft > 0
	if need ~= nil or probing then
		local facts : {QuotaRunDeliveryFact} = {}
		for i = 1, units do
			local item = entities[i]
			if probing and probe.factsLeft > 0 then
				-- P2: every field, logged; the logic still gets only what it asked for.
				local full = resolveFact(kind, item, ALL_FACT_FIELDS)
				probe.factsLeft = probe.factsLeft - 1
				log.message(PREFIX .. "P2 fact " .. logic.dump(full) .. " (entry " .. type(item) .. ", "
					.. probe.factsLeft .. " left)")
				if need ~= nil then facts[i] = projectFact(full, need) end
			elseif need ~= nil then
				facts[i] = resolveFact(kind, item, need)
			end
		end
		if need ~= nil then input.facts = facts end
		if probing then tidyProbe(s) end
	end
	local oldPhase = s.phase
	local intents : {QuotaRunIntent}
	s, intents = logic.delivered(s, input)
	commit(state, oldPhase, s, intents)
end

---------------------------------------------------------------------------
-- v2 playtest probes (PLAN §9.9), DEBUG only, active run only. Handled here; the logic never sees
-- them. Probe bookkeeping lives in state.probe (rule 2.3).

local PROBE_OPS : {string : boolean} = {
	incomeProbe = true, factsProbe = true, jumpYears = true, closeIndustry = true, townProbe = true,
}
local INCOME_PROBE_MAX <const> = 1000    -- P1: n = mult x 100, so 0.01 .. 10.0
local INCOME_LOG_COUNT <const> = 10      -- P1: log this many OnCalcTicketPrice params
local JUMP_YEARS_MAX <const> = 100       -- P3
local CLOSE_MONTHS_MAX <const> = 240     -- P4

--- n if it is an integer in [lo, hi], else nil after a warning (same wording as the logic's debugN).
local function probeN(op : string, n : integer, lo : integer, hi : integer) : integer
	if n == nil or n < lo or n > hi then
		log.warning(PREFIX .. "debug " .. op .. " ignored: missing or invalid n " .. tostring(n)
			.. " (allowed " .. lo .. ".." .. hi .. ")")
		return nil
	end
	return n
end

local function probeState(s : QuotaRunState) : QuotaRunProbeState
	if s.probe == nil then s.probe = {} end
	return s.probe
end

local function entityName(e : integer) : string
	-- src: .cache/game/api/tealdef/api/engine.d.tl:795-800 (Name.name); base read: .cache/game/base/content/mission/name_util.tl:83
	local name = getComp(e, api.type.ComponentType.NAME) as Engine.Component.Name
	return name ~= nil and name.name or nil
end

local function formatDate(d : Date) : string
	if d == nil then return "nil" end
	return tostring(d.year) .. "-" .. tostring(d.month) .. "-" .. tostring(d.day)
end

--- P1 diagnostic: the base company multiplier, so the income per unit can be compared.
--- Reads the company_growth script state (registered by company_progression.gs.lua).
-- src: .cache/game/base/content/game_mechanics/company/company_progression.gs.lua:1-10,
-- company_growth.script.tl:159-169 (companyState[player].ticketPriceMultiplier);
-- gs name pattern: .cache/game/base/content/industries/industry_productivity_util.tl:6
local function companyTicketMultiplier() : any
	local e = api.engine.system.gameScriptSystem.getEntityForGameScript("::/game_mechanics/company/company_progression.gs")
	if e == nil or e < 0 then return nil end
	local gs = getComp(e, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<{string : any}>
	local st = gs ~= nil and gs.state or nil
	local companies = st ~= nil and st.companyState or nil
	if type(companies) ~= "table" then return nil end
	local mine = (companies as {integer : any})[api.engine.util.getPlayer()]
	if type(mine) ~= "table" then return nil end
	return (mine as {string : any}).ticketPriceMultiplier
end

--- P1 incomeProbe {n}: return {[0] = n / 100} from OnCalcTicketPrice while on; n = 0 turns it off.
local function probeIncome(state : GameScriptState<QuotaRunState>, s : QuotaRunState, n : integer)
	n = probeN("incomeProbe", n, 0, INCOME_PROBE_MAX)
	if n == nil then return end
	local p = probeState(s)
	if n == 0 then
		p.incomeMult = nil
		log.message(PREFIX .. "P1 incomeProbe OFF (unsubscribed from " .. EV_TICKET .. ")")
	else
		p.incomeMult = n / 100
		p.incomeLogLeft = INCOME_LOG_COUNT
		log.warning(PREFIX .. "P1 incomeProbe ON: returning {[0] = " .. tostring(p.incomeMult) .. "} from "
			.. EV_TICKET .. " (" .. ID_TICKET_CARGO .. ", " .. ID_TICKET_PERSON .. "); base company ticketPriceMultiplier="
			.. tostring(companyTicketMultiplier()) .. ". Logging the next " .. INCOME_LOG_COUNT .. " events.")
	end
	tidyProbe(s)
	syncSubscriptions(state, s)
	state:set(s)
end

--- P2 factsProbe {n}: log all fact fields of the next n delivered entities.
local function probeFacts(state : GameScriptState<QuotaRunState>, s : QuotaRunState, n : integer)
	n = probeN("factsProbe", n, 1, FACTS_PROBE_MAX)
	if n == nil then return end
	probeState(s).factsLeft = n
	log.message(PREFIX .. "P2 factsProbe: logging the next " .. n .. " delivered entities (all fields; factsNeeded now: "
		.. logic.dump(logic.factsNeeded(s)) .. ")")
	state:set(s)
end

--- P3 jumpYears {n}: move the CALENDAR n years ahead. Not reversible. Game time is untouched.
local function probeJumpYears(n : integer)
	n = probeN("jumpYears", n, 1, JUMP_YEARS_MAX)
	if n == nil then return end
	-- src: .cache/game/api/tealdef/api/engine/util.d.tl:1027-1030 (getCalendarDate(gameTime));
	-- base read: .cache/game/base/content/gui/game_bar/game_bar_widgets.tl:260
	local before = api.engine.util.getCalendarDate(getGameTime())
	if before == nil then
		log.warning(PREFIX .. "debug jumpYears ignored: no calendar date")
		return
	end
	local year = before.year + n
	-- Clamp the day to the target month (29 Feb): same construction as the base date editor,
	-- src: .cache/game/base/content/gui/game_bar/game_bar_widgets.tl:678-689; API: api/type.d.tl:959-1005 (Date)
	local endOfMonth = api.type.Date.new(year, before.month, 1):getEndOfMonth()
	local day = math.min(before.day, endOfMonth.day)
	log.warning(PREFIX .. "!!! P3 jumpYears " .. n .. " (debug) !!! NOT REVERSIBLE: setting the calendar from "
		.. formatDate(before) .. " to " .. year .. "-" .. before.month .. "-" .. day .. ". Use a throwaway save.")
	-- src: .cache/game/api/tealdef/api/cmd.d.tl:699-703 (makeGameSetDateCmd(date)); base use:
	-- .cache/game/base/content/mission/calendar.lua:20-23. Sim-thread commands run immediately (cmd.d.tl:1-9).
	api.cmd.sendCommand(api.cmd.makeGameSetDateCmd(api.type.Date.new(year, before.month, day)))
	local after = api.engine.util.getCalendarDate(getGameTime())
	log.message(PREFIX .. "P3 jumpYears: date before=" .. formatDate(before) .. " after=" .. formatDate(after)
		.. " gameTime=" .. tostring(getGameTime()))
end

--- P4 closeIndustry {n}: start an n-month closure countdown on one industry the base could close.
local function probeCloseIndustry(state : GameScriptState<QuotaRunState>, s : QuotaRunState, n : integer)
	n = probeN("closeIndustry", n, 1, CLOSE_MONTHS_MAX)
	if n == nil then return end
	-- Candidates mirror the base closure loop, which skips manualDevelopment and player-owned
	-- industries and only ever closes industries with output and no depots
	-- (src: .cache/game/base/content/game_mechanics/industries/industries.script.tl:62-69,105-110).
	-- src: .cache/game/api/tealdef/api/engine.d.tl:1713 (getEntitiesWithComponent), :441-458 (Industry), :1667 (PLAYER_OWNED);
	-- .cache/game/api/tealdef/api/engine/util.d.tl:84 (stock.getInputsOutputsFromRules)
	local candidates : {integer} = {}
	for _, e in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY) or {}) do
		local industry = getComp(e, api.type.ComponentType.INDUSTRY) as Engine.Component.Industry
		if industry ~= nil and not industry.manualDevelopment
			and getComp(e, api.type.ComponentType.PLAYER_OWNED) == nil then
			local construction = getComp(industry.construction, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
			local noDepots = construction == nil or construction.depots == nil or #construction.depots == 0
			local io = industry.stockList ~= nil and api.engine.util.stock.getInputsOutputsFromRules(industry.stockList) or nil
			local hasOutput = io ~= nil and io[2] ~= nil and #io[2] > 0
			if noDepots and hasOutput then candidates[#candidates + 1] = e end
		end
	end
	if #candidates == 0 then
		log.warning(PREFIX .. "debug closeIndustry ignored: no industry the base could close (needs output, no depots, not manual)")
		return
	end
	table.sort(candidates)
	local e = candidates[logic.rngNext(s, #candidates)]
	local industry = getComp(e, api.type.ComponentType.INDUSTRY) as Engine.Component.Industry
	local before = industry ~= nil and industry.closureTimeStamp or nil
	-- Time unit: GAME time (ms, GAME_TIME.gameTime), not calendar: the base sets
	-- gameTimeMs + closureCountdownTimeSpanYears * getDefaultYearDuration()
	-- (src: .cache/game/base/content/game_mechanics/industries/industries.script.tl:51-52,94-95) and compares
	-- it with gameTimeMs (:112). One month = state.monthDuration (getDefaultMonthDuration at activation).
	local month = s.monthDuration or api.util.getDefaultMonthDuration()
	local now = getGameTime()
	local at = now + n * month
	-- src: .cache/game/api/tealdef/api/cmd.d.tl:719-724 (makeIndustrySetDespawnTimeCmd(entity, timeStamp))
	api.cmd.sendCommand(api.cmd.makeIndustrySetDespawnTimeCmd(e, at))
	local afterIndustry = getComp(e, api.type.ComponentType.INDUSTRY) as Engine.Component.Industry
	local name = entityName(e) or (industry ~= nil and entityName(industry.construction)) or "?"
	log.warning(PREFIX .. "!!! P4 closeIndustry (debug) !!! industry " .. tostring(e) .. " \"" .. name .. "\""
		.. " (" .. #candidates .. " candidates): despawn time " .. tostring(before) .. " -> " .. at
		.. " (now " .. now .. " + " .. n .. " months), reads back "
		.. tostring(afterIndustry ~= nil and afterIndustry.closureTimeStamp or nil)
		.. ". The base resets it to 0 once the industry is no longer a closure candidate (industries.script.tl:96-99).")
	state:set(s) -- rngSeed advanced
end

local function plainValue(v : any) : any
	local t = type(v)
	if t == "table" or t == "number" or t == "boolean" or t == "string" or t == "nil" then return v end
	return tostring(v)
end

--- P6 townProbe {n?}: log the TOWN component of town #n (default 1, sorted by entity id).
local function probeTown(n : integer)
	-- src: .cache/game/api/tealdef/api/engine.d.tl:1285-1302 (Town, incl. developmentActive), :1653 (TOWN)
	local towns = api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN) or {}
	if #towns == 0 then
		log.warning(PREFIX .. "debug townProbe ignored: no towns")
		return
	end
	local index = probeN("townProbe", n or 1, 1, #towns)
	if index == nil then return end
	local sorted : {integer} = {}
	for i, e in ipairs(towns) do sorted[i] = e end
	table.sort(sorted)
	local e = sorted[index]
	local town = getComp(e, api.type.ComponentType.TOWN) as Engine.Component.Town
	if town == nil then
		log.warning(PREFIX .. "debug townProbe: town " .. tostring(e) .. " has no TOWN component")
		return
	end
	local view : {string : any} = {
		entity = e,
		name = entityName(e),
		developmentActive = plainValue(town.developmentActive),
		capacityScalingFactor = plainValue(town.capacityScalingFactor),
		initialLandUseCapacities = plainValue(town.initialLandUseCapacities),
		sizeFactors = plainValue(town.sizeFactors),
		noise = plainValue(town.noise),
		pollution = plainValue(town.pollution),
	}
	log.message(PREFIX .. "P6 townProbe " .. index .. "/" .. #towns .. ": " .. logic.dump(view)
		.. " (toggle: makeTownSetDevelopmentActiveCmd, cmd.d.tl:856)")
end

local function handleProbe(state : GameScriptState<QuotaRunState>, s : QuotaRunState, op : string, n : integer)
	if op == "incomeProbe" then probeIncome(state, s, n)
	elseif op == "factsProbe" then probeFacts(state, s, n)
	elseif op == "jumpYears" then probeJumpYears(n)
	elseif op == "closeIndustry" then probeCloseIndustry(state, s, n)
	elseif op == "townProbe" then probeTown(n)
	end
end

--- P1 handler. One state:get() (done by handleEvent); set() only while params are still being logged.
-- Return form {[0] = mult} ("multipliers[0] is used for all"):
-- src: .cache/game/base/content/game_mechanics/company/company_growth.script.tl:159-169. The return value
-- reaches the engine through handleEventScript exactly like company_growth's (its registration
-- .cache/game/base/content/game_mechanics/company/company_progression.gs.lua:1-10 has the same shape as quota.gs.lua).
local function onTicketPrice(state : GameScriptState<QuotaRunState>, s : QuotaRunState, id : string, param : any) : any
	if not incomeProbeOn(s) then return nil end
	local p = s.probe
	if p.incomeLogLeft ~= nil and p.incomeLogLeft > 0 then
		-- Params: {CalcTicketPriceEvent} / {CalcTicketPriceCargoEvent}
		-- (src: .cache/game/base/tealdef/scripts/gamescript.d.tl:3-18). Copy the first entry into plain data.
		local count = 0
		local first : {string : any} = nil
		if type(param) == "table" then
			local list = param as {CalcTicketPriceCargoEvent}
			count = #list
			local e = list[1]
			if e ~= nil then
				first = { vehicleEntity = e.vehicleEntity, lineEntity = e.lineEntity, simEntity = e.simEntity,
					stockListEntity = e.stockListEntity, basePrice = e.basePrice, distance = e.distance }
			end
		end
		p.incomeLogLeft = p.incomeLogLeft - 1
		log.message(PREFIX .. "P1 " .. EV_TICKET .. " from " .. id .. ": entries=" .. count .. " first=" .. logic.dump(first)
			.. " -> returning [0]=" .. tostring(p.incomeMult) .. " (" .. p.incomeLogLeft .. " more logged)")
		tidyProbe(s) -- never clears incomeMult
		state:set(s)
	end
	local multipliers : {integer : number} = {}
	multipliers[0] = p.incomeMult -- multipliers[0] is used for all (company_growth.script.tl:168)
	return multipliers
end

local function handleQuotaEvent(state : GameScriptState<QuotaRunState>, s : QuotaRunState, name : string, param : any)
	local p : {string : any} = type(param) == "table" and param as {string : any} or {}
	local oldPhase = s.phase
	local intents : {QuotaRunIntent}
	if name == EV_PICK then
		s, intents = logic.pickCard(s, { index = toInteger(p.index), gameTime = getGameTime() })
	elseif name == EV_CONTINUE then
		s, intents = logic.continueSandbox(s, {})
	elseif name == EV_DEBUG then
		local op = type(p.op) == "string" and p.op as string or nil
		if config.DEBUG and op ~= nil and PROBE_OPS[op] then
			-- Probes never reach the logic. With DEBUG off they fall through to logic.debug, which
			-- rejects them like every other op.
			handleProbe(state, s, op, toInteger(p.n))
			return
		end
		-- setRule / setBoss / setNextBoss (v2) carry `id` exactly like applyCard.
		s, intents = logic.debug(s, {
			op = op,
			n = toInteger(p.n),
			id = type(p.id) == "string" and p.id as string or nil,
			gameTime = getGameTime(),
			balance = getBalance(),
			statsTotal = getStatsTotal(),
		})
		if config.DEBUG then
			if op == "dump" then logModParams("dump") end
			-- reset builds a fresh state without `probe`: re-sync so a stale probe subscription goes too.
			effects.run(s, intents)
			syncSubscriptions(state, s)
			state:set(s)
			return
		end
	else
		log.warning(PREFIX .. "unknown event " .. tostring(name))
		return
	end
	commit(state, oldPhase, s, intents)
end

local script : GameScript<QuotaRunState> = {
	update = function(_userParams : table, state : GameScriptState<QuotaRunState>, dt : number) : any
		-- Inert fast path (rule 2.1).
		-- Perf note (Phase 4): state:get() copies the state each call. A cheaper read via
		-- state:get_native() is declared (.cache/game/base/tealdef/scripts/gamescript.d.tl:43) but has
		-- no usage anywhere in base or official mods, so we keep get() as the base does every frame
		-- (vehicle/vehicle_modifier.script.tl:27, arrival_tracker/arrivaltracker.script.tl:79) and
		-- only call set() when something changed. Delivery events likewise do one get()/set() per
		-- event, exactly like arrivaltracker.script.tl:112-131; progress must be persisted, and
		-- buffering it in module state would break rule 2.3.
		local s = state:get()
		if not s or not s.active then
			if config.DEBUG then listenForDebugWhileInert(state, s) end
			return
		end
		-- Paused: dt == 0 (src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:77)
		if dt == 0.0 then return end
		if not inPlay(s) then
			-- ended/sandbox: only finish a capped clearEffects (VEHICLE_SENDS_PER_FRAME).
			local fx = s.fx
			if fx ~= nil and fx.vehicleApplied ~= nil and next(fx.vehicleApplied) ~= nil then
				if effects.onUpdate(s, getGameTime()) then state:set(s) end
			end
			return
		end

		local now = getGameTime()
		local changed = false
		-- Only read stats/balance and run the logic when something is due (cheap per-frame path).
		if config.METRIC == "stats" or now >= s.nextMonthTick or now >= s.roundEndTime
			or (not s.halfwayWarned and now >= s.roundStartTime + math.floor((s.roundEndTime - s.roundStartTime) / 2)) then
			local oldPhase = s.phase
			local intents : {QuotaRunIntent}
			s, intents = logic.tick(s, { gameTime = now, balance = getBalance(), statsTotal = getStatsTotal() })
			effects.run(s, intents)
			if s.phase ~= oldPhase then syncSubscriptions(state, s) end
			changed = true
		end
		if inPlay(s) and effects.onUpdate(s, now) then
			changed = true
		end
		if changed then state:set(s) end
	end,

	handleEvent = function(_userParams : table, state : GameScriptState<QuotaRunState>, _src : string, id : string, name : string, param : any) : any
		if id == "" then
			-- Engine system events (src: .cache/game/base/content/game_mechanics/company/company.script.tl:378-392)
			if name == "initNewGame" or name == "initNewGameFromMap" then
				tryActivate(state, name)
			elseif name == "initMission" or name == "initTutorial" then
				-- Event names: .cache/game/base/content/mission/mission_sim.script.tl:824,830,841
				deactivate(state, name)
			elseif name == "handleLegacy" then
				local s = state:get()
				if s ~= nil and s.active then
					-- v2 (PLAN §9.8 "Migration"): upgrade a v1 state before re-subscribing (the
					-- subscriptions may depend on v2 fields, e.g. state.probe). migrate is a no-op on a
					-- v2 state; one set() per load is negligible.
					local intents : {QuotaRunIntent}
					s, intents = logic.migrate(s)
					effects.run(s, intents)
					syncSubscriptions(state, s)
					state:set(s)
				end
			end
			-- initMission/initTutorial never activate (they deactivate an active run); nothing else does.
			return
		end

		local s = state:get()
		if not s or not s.active then
			if config.DEBUG and id == EVENT_ID and name == EV_DEBUG then
				handleInertDebug(state, s, param)
			end
			return
		end

		if id == "SimCargoSystem" and name == EV_CARGO then
			-- src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:125-128
			handleDelivery(state, s, "cargo", param)
		elseif id == "SimPersonSystem" and name == EV_PERSON then
			-- src: .cache/game/base/content/game_mechanics/arrival_tracker/arrivaltracker.script.tl:115-118
			handleDelivery(state, s, "passenger", param)
		elseif name == EV_TICKET and (id == ID_TICKET_CARGO or id == ID_TICKET_PERSON) then
			-- P1 (DEBUG probe only; subscribed only while state.probe.incomeMult is set)
			return onTicketPrice(state, s, id, param)
		elseif id == EVENT_ID then
			handleQuotaEvent(state, s, name, param)
		end
	end,
}

return script
