recordDef = true

-- Quota Run shared contract (PLAN.md §4.1 state, §4.3 intents + logic inputs).
-- FROZEN at the end of Phase 1. Phases 2/3 may only read these records; Phase 2
-- may add fields under QuotaRunFxState. Any other change: stop and report.
-- v2 (PLAN §9.8, step v2.1 + probes, 2026-10-03): fields marked "v2" were added in one
-- reviewed contract change; QuotaRunState.version is 2. The same freeze rule applies again.
-- Every global name is prefixed QuotaRun (globals are shared by all loaded mods).

--- Effect bookkeeping, owned by quota_effects (Phase 2).
global record QuotaRunFxState
	vehicleMods : {string : number}       -- aggregated TopSpeed/Comfort/Pollution/Noise, absent = 1.0
	vehicleModsRev : integer              -- bumped whenever vehicleMods changes
	vehicleApplied : {integer : integer}  -- vehicle entity -> vehicleModsRev last sent
	industryMods : {integer : number}     -- stock-list entity -> our multiplier (>= 1.0)
	nextScanTime : integer                -- gameTime of next vehicle/industry scan
end

--- v2: per-round delivery tallies (pure logic, fed from delivery facts). Keys are engine ids
--- (town entity, cargo type id); values are raw units (unweighted). Iterate with sorted keys
--- for determinism. Integer keys may come back as floats after save/load: normalise with
--- math.floor before comparing.
global record QuotaRunTally
	cargoTypes : {integer : integer}      -- cargo type id -> units (cargo facts with cargoType)
	towns : {integer : integer}           -- destination town entity -> units (facts with toTown)
end

--- v2: debug probe bookkeeping (PLAN §9.9), owned by the adapter (quota.script.tl), DEBUG only.
--- Lives in state (rule 2.3); nil when no probe ever ran. Never read by the logic.
global record QuotaRunProbeState
	factsLeft : integer                   -- P2: log the resolved facts of this many more deliveries
	incomeMult : number                   -- P1: return {[0] = incomeMult} from OnCalcTicketPrice; nil = off
	incomeLogLeft : integer               -- P1: log this many more OnCalcTicketPrice params
end

--- The whole run, stored via GameScriptState:set. nil / no `active` = inert.
global record QuotaRunState
	version : integer            -- schema version, starts at 1
	active : boolean             -- nil = inert (existing saves); true for the whole run, incl. ended/sandbox
	phase : string               -- "running" | "choosing" | "ended" | "sandbox"
	rngSeed : integer            -- LCG state (Park-Miller, 1 .. 2^31-2)
	round : integer              -- 1-based, the round in progress
	roundsCleared : integer
	runStartTime : integer       -- gameTime at activation
	roundStartTime : integer     -- gameTime
	roundEndTime : integer       -- gameTime deadline
	nextMonthTick : integer      -- gameTime of next bankruptcy/month tick
	quota : integer              -- current round's quota (recomputed on pick)
	progress : integer           -- weighted units delivered this round (event counter)
	statsBaseline : integer      -- getTransportedData() sum at round start (diagnostic / METRIC="stats")
	totalTransported : integer   -- across finished rounds (incl. the final, failed round once the run ends)
	redMonths : integer
	quotaMultAll : number
	quotaMultRound : number      -- reset to 1.0 at each round start
	rewardMult : number
	offer : {string}             -- 3 card ids while phase == "choosing", else nil
	picked : {string}            -- history of card ids, in order
	endReason : string           -- "quota" | "bankrupt" (nil while running)
	lastReward : integer
	savedSpeed : integer         -- GAME_SPEED.speedup before our pause (0 => restore as 1)
	fx : QuotaRunFxState         -- owned by quota_effects (Phase 2)
	-- Added in Phase 1 (PLAN §4.1 note):
	monthDuration : integer      -- api.util.getDefaultMonthDuration() at activation (logic is engine-free)
	halfwayWarned : boolean      -- "halfway" notify already emitted this round
	-- v2 (PLAN §9.3, §9.4, §9.8). All nil-tolerant: logic.migrate fills defaults on a v1 state.
	rule : string                -- scoring rule id for the round in progress (quota_rules.tl); nil = MVP weights
	ruleTarget : integer         -- local_hero: town entity; specialist: cargo type id; nil otherwise
	boss : string                -- boss id of the round in progress (quota_bosses.tl); nil = not a boss round
	nextBoss : string            -- boss announced for the next round (drawn when the round before it starts)
	cardVehicleMods : {string : number} -- permanent aggregate from cards (capped); fx.vehicleMods = this + boss mods
	rewardMultRound : number     -- this round's reward multiplier (round-modifier cards, bosses); reset to 1.0 each round
	tally : QuotaRunTally        -- this round's raw delivery tallies
	lastTally : QuotaRunTally    -- the previous round's tallies (rule targets are drawn from it)
	probe : QuotaRunProbeState   -- adapter-owned debug probes; nil unless a probe op ran
end

--- Logic -> adapter side effect (PLAN §4.3). Executed in order by quota_effects.run.
global record QuotaRunIntent
	kind : string               -- "cash" | "pause" | "resume" | "notify" | "vehicleMods" | "industryMods" | "clearEffects" | "log"
	amount : integer            -- cash
	key : string                -- notify: "roundStart" | "roundCleared" | "halfway" | "bankruptWarn" | "runOver"
	                            -- v2: roundStart params also carry rule/boss/nextBoss ids when set
	params : {string : any}     -- notify params (numbers/strings only; text is built in the notification script)
	industryCount : integer     -- industryMods: N random (nil = all)
	mult : number               -- industryMods multiplier
	message : string            -- log
	level : string              -- log: "message" (default) | "warning"  (added in Phase 1)
end

--- Added in Phase 2: the `params` of a Quota Run notification (quota_effects.notify ->
--- notify/quota_notification.script.tl). `key` is the intent key; the other fields are the
--- intent's params for that key (roundStart: round, quota, months; roundCleared: round, reward,
--- progress, quota; halfway: round, progress, quota, months; bankruptWarn: redMonths, monthsLeft;
--- runOver: reason, rounds, total). Absent fields are nil.
global record QuotaRunNotificationParams
	key : string
	round : integer
	quota : integer
	months : integer
	reward : integer
	progress : integer
	redMonths : integer
	monthsLeft : integer
	reason : string             -- runOver: "quota" | "bankrupt"
	rounds : integer
	total : integer
	-- v2, roundStart only (ids; the notification script looks up names in quota_rules/quota_bosses):
	rule : string
	boss : string
	nextBoss : string
	-- v2.1 addendum (rule targets, 2026-10-03), roundStart only: state.ruleTarget when the rule
	-- has a target (town entity or cargo type id; the kind is the rule's `target` field). The
	-- notification script resolves the name (gui/quota_target_names.tl). pickCard emits roundStart
	-- after applying the card, so rule cards (local_hero_card) carry their target too; only debug
	-- ops (setRule / applyCard) change the rule without a notification (the HUD shows it).
	ruleTarget : integer
end

--- Logic inputs (PLAN §4.3). Fields marked "added" are Phase 1 additions.
global record QuotaRunActivateInput
	gameTime : integer
	seed : integer              -- raw seed (the adapter passes gameTime); logic mixes it
	monthDuration : integer     -- added: api.util.getDefaultMonthDuration()
	statsTotal : integer        -- added, optional: getTransportedData() sum for statsBaseline
end

global record QuotaRunTickInput
	gameTime : integer
	balance : integer           -- nil = infinite money
	statsTotal : integer        -- getTransportedData() sum; may be nil when no month tick/round end is due
end

--- v2: one delivered entity, resolved by the adapter (PLAN §9.3). Every field except kind is
--- optional (nil = unknown / not resolved). One fact = one unit.
global record QuotaRunDeliveryFact
	kind : string               -- "cargo" | "passenger"
	cargoType : integer         -- cargo: SIM_CARGO.cargoType
	toTown : integer            -- destination town entity
	fromTown : integer          -- source town entity
	line : integer              -- cargo: last pickup point's line
	carrier : string            -- cargo: last pickup point's carrier: "ROAD" | "RAIL" | "TRAM" | "AIR" | "WATER" | "OTHER"
end

global record QuotaRunDeliveredInput
	units : integer
	kind : string               -- added: "cargo" | "passenger" (selects CARGO_WEIGHT / PASSENGER_WEIGHT)
	facts : {QuotaRunDeliveryFact} -- v2, optional: when non-nil, progress = sum of rule weights over
	                            -- the facts and `units` is ignored; nil = MVP path (units * kind weight)
end

global record QuotaRunPickInput
	index : integer
	gameTime : integer
end

global record QuotaRunContinueInput
end

global record QuotaRunDebugInput
	op : string                 -- PLAN §4.2 debug-op table: "endRound" | "addProgress" | "setMonthsLeft" | "bankrupt" | "offer" | "dump"
	                            -- dev-panel ops (§4.6): "passRound" | "failRound" | "skipMonths" | "applyCard" | "addMoney"
	                            -- | "addQuotaPct" | "clearEffects" | "reset" | "forceStart" (forceStart is adapter-only)
	                            -- v2 logic ops: "setRule" (id; "" or "none" clears) | "setBoss" (id: make the round in
	                            -- progress a boss round now; "" clears) | "setNextBoss" (id; "" clears)
	                            -- v2 probe ops, adapter-only (PLAN §9.9; the logic never sees them): "incomeProbe"
	                            -- (n = mult x 100, 0 = off) | "factsProbe" (n deliveries) | "jumpYears" (n)
	                            -- | "closeIndustry" (n months) | "townProbe"
	n : integer
	gameTime : integer
	id : string                 -- added (dev panel): applyCard card id
	balance : integer           -- added (dev panel): skipMonths month ticks; nil = infinite money
	statsTotal : integer        -- added (dev panel): optional, passRound/skipMonths/reset stats baseline
end

--- Card data (quota_cards.tl). Plain data; the GUI wraps name/description in _().
global record QuotaRunCardEffect
	kind : string               -- "cash" | "quotaMultRound" | "quotaMultAll" | "roundMonths" | "vehicleMod" | "industryProd" | "rewardMult"
	                            -- v2: "rule" (sets state.rule for this round) | "rewardMultRound" (this round's reward only)
	amount : integer            -- cash: money per round number (negative = cost)
	mult : number               -- quotaMultRound / quotaMultAll / rewardMult / industryProd
	months : integer            -- roundMonths: +/- default months
	mods : {string : number}    -- vehicleMod: TopSpeed/Comfort/Pollution/Noise -> multiplier
	count : integer             -- industryProd: N random industries (nil = all)
	rule : string               -- v2 "rule": scoring rule id for this round (round-modifier cards)
end

global record QuotaRunCard
	id : string
	name : string
	description : string
	effects : {QuotaRunCardEffect}
end

---------------------------------------------------------------------------
-- Module interfaces (one file on purpose: the load order of separate .d.tl files is not
-- guaranteed, and every record here depends on the shared records above).

-- ======================================================================
-- from quota_config.tl
-- Tunables for Quota Run (PLAN.md §3.1). Module: ug_require "/quota/quota_config.tl" as QuotaRunConfig
global record QuotaRunConfig
	DEBUG : boolean                 -- enables QuotaRun.debug ops (flip to false before upload)
	METRIC : string                 -- "events" (event counter) | "stats" (getTransportedData delta)
	CARGO_WEIGHT : number
	PASSENGER_WEIGHT : number
	BASE_QUOTA : number
	GROWTH : number
	ROUND_MONTHS : integer
	FIRST_ROUND_MONTHS : integer
	MIN_MONTHS_LEFT : integer       -- roundMonths cards never move the deadline earlier than now + this
	REWARD_BASE : integer
	REWARD_BONUS_THRESHOLD : number -- progress >= quota * this earns the bonus
	REWARD_BONUS : number           -- +50%
	BANKRUPT_MONTHS : integer       -- red months that end the run
	BANKRUPT_WARN_MONTHS : integer  -- red months that trigger the warning notification
	VEHICLE_MOD_CAP : number
	OFFER_SIZE : integer
	SEED_MIX : integer              -- constant mixed into the initial RNG seed
	SCAN_INTERVAL_FRACTION : number -- fx scans every month * this (Phase 2)
	VEHICLE_SENDS_PER_FRAME : integer -- Phase 4: cap on ChangeModifier events per scan/clear call
	GUI_INLINE_PICKER : boolean     -- Phase 4: inline picker in the ridge instead of the dialog window
	-- v2 (PLAN §9.3-9.4)
	BOSS_EVERY : integer            -- every Nth round is a boss round (0 = no bosses)
	BOSS_REWARD_MULT : number       -- reward multiplier for clearing a boss round (v2.2 adds charter points)
	RANDOM_RULE_FROM_ROUND : integer -- non-boss rounds from this round on get a random rule (0 = off, PLAN §9.3 (c))
	TALLY_FACTS : boolean           -- resolve cargoType/toTown for every delivery so rule targets can be drawn
end

-- ======================================================================
-- v2: from quota_rules.tl (PLAN §9.3). Module: ug_require "/quota/quota_rules.tl" as QuotaRunRules
--- A scoring rule: data interpreted by logic.weight. Weight of a fact is the product of
---   kind:      cargoWeight | passengerWeight (0 for passengers when cargoOnly)
---   target:    targetWeight if the fact matches state.ruleTarget, else otherWeight
---   carrier:   carrierWeights[fact.carrier] (cargo facts with a carrier; missing key = 1)
---   crossTown: crossTownWeight if fromTown and toTown are both known and differ, else otherWeight
--- Unset multipliers are 1; a part whose rule field is nil is skipped.
global record QuotaRunRule
	id : string
	name : string               -- plain English; GUI wraps in _()
	description : string
	quotaMult : number          -- calibrates the quota for this rule's expected units (nil = 1)
	needs : {string}            -- fact fields the adapter must resolve: "cargoType" | "toTown" | "fromTown" | "carrier" | "line"
	cargoWeight : number
	passengerWeight : number
	target : string             -- nil | "town" (ruleTarget = toTown) | "cargoType" (ruleTarget = cargoType)
	targetWeight : number
	otherWeight : number
	carrierWeights : {string : number}
	crossTownWeight : number
	cargoOnly : boolean
end

global record QuotaRunRules
	list : {QuotaRunRule}       -- fixed order (draws index into it): append only
	byId : {string : QuotaRunRule}
	get : function(id : string) : QuotaRunRule
end

-- ======================================================================
-- v2: from quota_bosses.tl (PLAN §9.4). Module: ug_require "/quota/quota_bosses.tl" as QuotaRunBosses
--- v2.1 bosses need no new engine surface: a rule and/or a temporary vehicle modifier.
global record QuotaRunBoss
	id : string
	name : string               -- plain English; GUI wraps in _()
	description : string
	rule : string               -- scoring rule for the boss round (nil = none)
	vehicleMods : {string : number} -- temporary for the boss round, aggregated 1 + sum(v - 1) with the cards' mods
	quotaMult : number          -- extra quota multiplier for the boss round (nil = 1)
end

global record QuotaRunBosses
	list : {QuotaRunBoss}       -- fixed order: append only
	byId : {string : QuotaRunBoss}
	get : function(id : string) : QuotaRunBoss
end

-- ======================================================================
-- from quota_cards.tl
-- Card definitions (PLAN.md §3.2). Module: ug_require "/quota/quota_cards.tl" as QuotaRunCards
global record QuotaRunCards
	list : {QuotaRunCard}              -- all cards, fixed order (the offer draw depends on it)
	byId : {string : QuotaRunCard}
	get : function(id : string) : QuotaRunCard
end

-- ======================================================================
-- from quota_logic.tl
-- Pure Quota Run logic (PLAN.md §3, §4.3). Instance: (ug_require "/quota/quota_logic.tl" as QuotaRunLogicModule).new(config, cards)
-- Entry points take the state from state:get() (mutated in place and returned) plus an input
-- record, and return the new state and the side effects for the adapter to execute in order.
-- A nil / inactive state is returned unchanged with no intents (inert).
--- The module itself: a factory, so quota_logic.tl needs no ug_require (config/cards injected).
global record QuotaRunLogicModule
	--- v2: rules/bosses are optional; nil = no rules / no bosses (MVP behaviour, used by old tests).
	new : function(config : QuotaRunConfig, cards : QuotaRunCards, rules? : QuotaRunRules, bosses? : QuotaRunBosses) : QuotaRunLogic
end

global record QuotaRunLogic
	activate : function(state : QuotaRunState, input : QuotaRunActivateInput) : QuotaRunState, {QuotaRunIntent}
	tick : function(state : QuotaRunState, input : QuotaRunTickInput) : QuotaRunState, {QuotaRunIntent}
	delivered : function(state : QuotaRunState, input : QuotaRunDeliveredInput) : QuotaRunState, {QuotaRunIntent}
	pickCard : function(state : QuotaRunState, input : QuotaRunPickInput) : QuotaRunState, {QuotaRunIntent}
	continueSandbox : function(state : QuotaRunState, input : QuotaRunContinueInput) : QuotaRunState, {QuotaRunIntent}
	debug : function(state : QuotaRunState, input : QuotaRunDebugInput) : QuotaRunState, {QuotaRunIntent}

	-- Pure helpers (also used by tests, and by quota_effects for the industry draw).
	isActive : function(state : QuotaRunState) : boolean
	computeQuota : function(state : QuotaRunState, round : integer) : integer
	computeReward : function(state : QuotaRunState, round : integer, progress : integer, quota : integer) : integer
	mixSeed : function(seed : integer) : integer
	--- Advances state.rngSeed; returns an integer in 1..n.
	rngNext : function(state : QuotaRunState, n : integer) : integer
	--- OFFER_SIZE distinct card ids drawn with the state LCG.
	drawOffer : function(state : QuotaRunState) : {string}
	--- Default months until roundEndTime (may be negative), as a float.
	monthsLeft : function(state : QuotaRunState, gameTime : integer) : number
	--- Deterministic one-line dump of a plain-data value (sorted keys).
	dump : function(value : any) : string

	-- v2 pure helpers
	--- Upgrade a v1 state in place to version 2 (fills defaults; cardVehicleMods = copy of
	--- fx.vehicleMods). No-op on nil, inactive or already-v2 states. Returns the state and log intents.
	migrate : function(state : QuotaRunState) : QuotaRunState, {QuotaRunIntent}
	--- Weight of one fact under the state's current rule (MVP kind weights when rule is nil).
	weight : function(state : QuotaRunState, fact : QuotaRunDeliveryFact) : number
	--- Fact fields the adapter should resolve right now (current rule's needs, plus cargoType/toTown
	--- when TALLY_FACTS). nil = MVP fast path (send no facts). Called per delivery event: keep it cheap.
	factsNeeded : function(state : QuotaRunState) : {string : boolean}
end

-- ======================================================================
-- from quota_effects.tl
-- Engine side effects for Quota Run (PLAN.md §4.3, §6 Phase 2).
-- Module: ug_require "/quota/quota_effects.tl" as QuotaRunEffects
-- FROZEN interface: Phase 2 replaces the bodies in quota_effects.tl, never these signatures.
-- Runs on the sim thread only. Handlers may mutate `state` (savedSpeed, fx); the adapter
-- calls state:set afterwards.
global record QuotaRunEffects
	--- Execute intents in order (dispatches on intent.kind; unknown kinds are logged).
	run : function(state : QuotaRunState, intents : {QuotaRunIntent})
	--- Called from the adapter's update (unpaused) every frame in running/choosing, and in
	--- ended/sandbox while fx.vehicleApplied is non-empty (capped clearEffects continuation).
	--- Periodic work such as the fx vehicle/industry scans. Returns true if it changed state.
	onUpdate : function(state : QuotaRunState, gameTime : integer) : boolean

	-- One handler per intent kind.
	cash : function(state : QuotaRunState, intent : QuotaRunIntent)
	pause : function(state : QuotaRunState, intent : QuotaRunIntent)
	resume : function(state : QuotaRunState, intent : QuotaRunIntent)
	notify : function(state : QuotaRunState, intent : QuotaRunIntent)
	vehicleMods : function(state : QuotaRunState, intent : QuotaRunIntent)
	industryMods : function(state : QuotaRunState, intent : QuotaRunIntent)
	clearEffects : function(state : QuotaRunState, intent : QuotaRunIntent)
	log : function(state : QuotaRunState, intent : QuotaRunIntent)
end

recordDef = false

---------------------------------------------------------------------------
-- Phase 3 (GUI) additions: appended block, nothing above is changed.
recordDef = true

-- ======================================================================
-- from gui/quota_hud_model.tl
-- Pure HUD view model. Module: ug_require "square_quota_run::/quota/gui/quota_hud_model.tl" as QuotaRunHudModel
global record QuotaRunHudCard
	index : integer             -- position in state.offer (the pickCard index)
	id : string
	name : string               -- plain English; the GUI wraps it in _()
	description : string        -- plain English; the GUI wraps it in _()
end

global record QuotaRunHudView
	phase : string              -- "running" | "choosing" | "ended" (never "sandbox": no view)
	-- v2: names/descriptions are plain English (GUI wraps in _()); nil when unset.
	ruleName : string
	ruleDescription : string
	bossName : string           -- the round in progress is a boss round
	bossDescription : string
	nextBossName : string       -- announced boss for the next round
	nextBossDescription : string
	-- v2.1 addendum (rule targets, 2026-10-03). The model (pure) copies the target id and kind;
	-- quota_hud.script.tl getFromEngine resolves the display name (gui/quota_target_names.tl) and
	-- stores it on the same fresh view table, so useStepStateTimer's deepEquals compares a string.
	ruleTarget : integer        -- state.ruleTarget (floored) when the current rule has a target; nil otherwise
	ruleTargetKind : string     -- the rule's `target`: "town" | "cargoType"; nil when ruleTarget is nil
	ruleTargetName : string     -- set by the HUD script, not the model: town / cargo name; nil when no target or unknown
	round : integer
	roundsCleared : integer
	monthsLeft : integer        -- whole default months left (ceil, >= 0); nil if unknown
	progress : integer
	quota : integer
	fraction : number           -- progress / quota clamped to [0, 1]
	provisional : boolean       -- quota may still change (card pick pending)
	redMonths : integer
	bankruptMonths : integer    -- red months that end the run
	redWarning : boolean        -- in the red this month (running/choosing only)
	picked : {string}           -- names of picked cards, in order
	offer : {QuotaRunHudCard}   -- choosing only, else empty
	endReason : string          -- ended only: "quota" | "bankrupt"
	totalTransported : integer  -- ended only
	-- Dev panel (only set when QuotaRunConfig.DEBUG; nil otherwise, so release views are unchanged).
	-- With DEBUG, phase may also be "inert" (no run in this save yet) or "sandbox".
	debug : boolean
	fxSummary : string          -- one line: vehicle modifiers, vehicles touched, industries boosted
end

global record QuotaRunHudModel
	--- nil when the HUD must render nothing (no state, inactive, sandbox, unknown phase).
	--- With DEBUG: an "inert" view for a nil / undecided state (active == nil) and a "sandbox" view,
	--- so the dev panel (and forceStart) stays reachable; active == false still renders nothing.
	build : function(state : QuotaRunState, gameTime : integer) : QuotaRunHudView
end

-- ======================================================================
-- v2.1 addendum (rule targets, 2026-10-03): from gui/quota_target_names.tl
-- GUI-thread name lookup for rule targets. Module: ug_require "square_quota_run::/quota/gui/quota_target_names.tl" as QuotaRunTargetNames
global record QuotaRunTargetNames
	--- kind "town" (town entity) | "cargoType" (cargo type id) -> display name (already localised);
	--- nil for a nil / non-number id, an unknown kind, a missing entity or any engine error.
	resolve : function(kind : string, id : integer) : string
end

recordDef = false
