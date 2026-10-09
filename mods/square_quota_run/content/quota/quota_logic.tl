-- Quota Run core logic (PLAN.md §3, §4.3, v2: §9.3 rules, §9.4 bosses). PURE: no engine calls
-- and no module loading at all; config, cards, rules and bosses are injected, so the module is
-- testable offline and cannot reach the game.
-- No module-level run state. Every entry point is fn(state, input) : state, {intent}.
-- State is mutated in place (it is a fresh copy from state:get()) and returned.
-- Usage: see QuotaRunLogicModule in quota_types.d.tl (callers build one instance with
-- the config, cards, rules and bosses modules). rules/bosses nil = MVP behaviour: no rules, no
-- bosses, no extra RNG draws, rule cards never offered.
-- Runtime note: the game's Lua is older than 5.3: no //, bitwise ops, math.tointeger/math.type.

local SCHEMA_VERSION <const> = 2
local LCG_MOD <const> = 2147483647 -- Park-Miller minimal standard; products stay < 2^53
local LCG_MUL <const> = 48271
local MAX_CATCHUP_STEPS <const> = 10000
local VEHICLE_MOD_FLOOR <const> = 0.1 -- combined vehicle modifiers never go below this (boss curses)
local MOD_EPS <const> = 1e-9

local M : QuotaRunLogicModule = {}

function M.new(config : QuotaRunConfig, cards : QuotaRunCards, rules? : QuotaRunRules, bosses? : QuotaRunBosses) : QuotaRunLogic
	local logic : QuotaRunLogic = {}

	---------------------------------------------------------------------------
	-- helpers

	local function round(x : number) : integer
		return math.floor(x + 0.5)
	end

	local function logIntent(intents : {QuotaRunIntent}, message : string, level? : string)
		table.insert(intents, { kind = "log", message = message, level = level or "message" })
	end

	local function warn(intents : {QuotaRunIntent}, message : string)
		logIntent(intents, message, "warning")
	end

	local function notify(intents : {QuotaRunIntent}, key : string, params : {string : any})
		table.insert(intents, { kind = "notify", key = key, params = params })
	end

	local function setPhase(s : QuotaRunState, phase : string, intents : {QuotaRunIntent}, why : string)
		local old = s.phase
		s.phase = phase
		logIntent(intents, "phase " .. tostring(old) .. " -> " .. phase .. " (" .. why .. ")")
	end

	function logic.isActive(s : QuotaRunState) : boolean
		return s ~= nil and s.active == true
	end

	local function inPlay(s : QuotaRunState) : boolean
		return s.phase == "running" or s.phase == "choosing"
	end

	---------------------------------------------------------------------------
	-- v2 lookups (rules/bosses may be nil: then nothing resolves and the MVP paths run)

	local function emptyTally() : QuotaRunTally
		return { cargoTypes = {}, towns = {} }
	end

	local function ruleOf(s : QuotaRunState) : QuotaRunRule
		if rules == nil or s.rule == nil then return nil end
		return rules.get(s.rule)
	end

	local function bossOf(s : QuotaRunState) : QuotaRunBoss
		if bosses == nil or s.boss == nil then return nil end
		return bosses.get(s.boss)
	end

	local function isBossRound(r : integer) : boolean
		local every = config.BOSS_EVERY
		return bosses ~= nil and every ~= nil and every > 0 and r ~= nil and r % every == 0
	end

	--- The round in progress is a boss round whose rule is in force (cards can't override it).
	local function bossRuleActive(s : QuotaRunState) : boolean
		local boss = bossOf(s)
		return boss ~= nil and boss.rule ~= nil and s.rule ~= nil
	end

	function logic.computeQuota(s : QuotaRunState, r : integer) : integer
		local q = config.BASE_QUOTA * config.GROWTH ^ (r - 1) * (s.quotaMultAll or 1.0) * (s.quotaMultRound or 1.0)
		if r == s.round then
			-- v2: the rule and boss of the round in progress (PLAN §9.3 rule.quotaMult)
			local rule = ruleOf(s)
			if rule ~= nil and rule.quotaMult ~= nil then q = q * rule.quotaMult end
			local boss = bossOf(s)
			if boss ~= nil and boss.quotaMult ~= nil then q = q * boss.quotaMult end
		end
		return math.max(1, round(q))
	end

	function logic.computeReward(s : QuotaRunState, r : integer, progress : integer, quota : integer) : integer
		local reward = config.REWARD_BASE * r * (s.rewardMult or 1.0)
		if r == s.round then
			-- v2: this round's multipliers (round-modifier cards; boss bonus). finishRound calls this
			-- BEFORE startRound(r + 1) resets them.
			reward = reward * (s.rewardMultRound or 1.0)
			if s.boss ~= nil then reward = reward * (config.BOSS_REWARD_MULT or 1.0) end
		end
		if quota > 0 and progress >= quota * config.REWARD_BONUS_THRESHOLD then
			reward = reward * (1 + config.REWARD_BONUS)
		end
		return round(reward)
	end

	function logic.mixSeed(seed : integer) : integer
		local v = ((seed or 0) + config.SEED_MIX) % LCG_MOD
		if v <= 0 then v = v + LCG_MOD - 1 end
		if v <= 0 then v = 1 end
		return v
	end

	function logic.rngNext(s : QuotaRunState, n : integer) : integer
		local seed = s.rngSeed
		if seed == nil or seed <= 0 or seed >= LCG_MOD then seed = logic.mixSeed(seed) end
		seed = (seed * LCG_MUL) % LCG_MOD
		s.rngSeed = seed
		return seed % n + 1
	end

	---------------------------------------------------------------------------
	-- v2 rule targets (PLAN §9.3): drawn from last round's tallies, so the rule is achievable

	--- Sorted (ascending, math.floor-normalised) keys of the lastTally map the rule targets, with
	--- their units and the units total. Keys/values may come back as floats after save/load.
	local function targetPool(s : QuotaRunState, rule : QuotaRunRule) : {integer}, {integer : integer}, integer
		local keys : {integer} = {}
		local units : {integer : integer} = {}
		local map : {integer : integer} = nil
		local last = s.lastTally
		if last ~= nil then
			if rule.target == "town" then
				map = last.towns
			elseif rule.target == "cargoType" then
				map = last.cargoTypes
			end
		end
		if map ~= nil then
			for k, v in pairs(map) do
				local kn, vn = tonumber(k), tonumber(v)
				if kn ~= nil and vn ~= nil and vn >= 1 then
					local key = math.floor(kn)
					if units[key] == nil then
						table.insert(keys, key)
						units[key] = 0
					end
					units[key] = units[key] + math.floor(vn)
				end
			end
		end
		table.sort(keys)
		local total = 0
		for _, k in ipairs(keys) do total = total + units[k] end
		return keys, units, total
	end

	--- A rule can be set now: no target needed, or last round delivered something to target.
	local function canTarget(s : QuotaRunState, rule : QuotaRunRule) : boolean
		if rule.target == nil then return true end
		local _, _, total = targetPool(s, rule)
		return total > 0
	end

	--- Target drawn with the state LCG, weighted by last round's units (bigger destinations and
	--- cargo flows are likelier, which keeps the rule achievable). nil when nothing to draw.
	local function drawTarget(s : QuotaRunState, rule : QuotaRunRule) : integer
		local keys, units, total = targetPool(s, rule)
		if total <= 0 then return nil end
		local pick = logic.rngNext(s, math.min(total, LCG_MOD - 1))
		for _, k in ipairs(keys) do
			pick = pick - units[k]
			if pick <= 0 then return k end
		end
		return keys[#keys]
	end

	--- Set the round's rule and draw its target. Returns false (state unchanged, warning logged)
	--- when the rule is unknown or its target can't be drawn.
	local function applyRule(s : QuotaRunState, id : string, why : string, intents : {QuotaRunIntent}) : boolean
		local rule : QuotaRunRule = nil
		if rules ~= nil then rule = rules.get(id) end
		if rule == nil then
			warn(intents, why .. ": unknown rule " .. tostring(id) .. "; no rule set")
			return false
		end
		if not canTarget(s, rule) then
			warn(intents, why .. ": rule " .. id .. " has no " .. tostring(rule.target)
				.. " target (nothing delivered to one last round); no rule set")
			return false
		end
		s.rule = rule.id
		s.ruleTarget = nil
		if rule.target ~= nil then s.ruleTarget = drawTarget(s, rule) end
		logIntent(intents, "rule " .. rule.id .. (s.ruleTarget ~= nil and (" target=" .. s.ruleTarget) or "")
			.. " for round " .. tostring(s.round) .. " (" .. why .. ")")
		return true
	end

	--- A card may be offered now: every "rule" effect resolves, no boss rule is in force, and the
	--- rule's target can be drawn. Without rules data, rule cards are never offered (MVP pool).
	local function cardOfferable(s : QuotaRunState, card : QuotaRunCard) : boolean
		for _, eff in ipairs(card.effects) do
			if eff.kind == "rule" then
				local rule : QuotaRunRule = nil
				if rules ~= nil then rule = rules.get(eff.rule) end
				if rule == nil or bossRuleActive(s) or not canTarget(s, rule) then return false end
			end
		end
		return true
	end

	function logic.drawOffer(s : QuotaRunState) : {string}
		local pool : {string} = {}
		for _, card in ipairs(cards.list) do
			if cardOfferable(s, card) then table.insert(pool, card.id) end
		end
		local offer : {string} = {}
		local count = math.min(config.OFFER_SIZE, #pool)
		for i = 1, count do
			-- partial Fisher-Yates: pick from pool[i..#pool]
			local j = i - 1 + logic.rngNext(s, #pool - i + 1)
			pool[i], pool[j] = pool[j], pool[i]
			offer[i] = pool[i]
		end
		return offer
	end

	function logic.monthsLeft(s : QuotaRunState, gameTime : integer) : number
		return (s.roundEndTime - gameTime) / s.monthDuration
	end

	local function dumpValue(v : any, depth : integer) : string
		if type(v) == "string" then return string.format("%q", v) end
		if type(v) ~= "table" then return tostring(v) end
		if depth > 4 then return "{...}" end
		local t = v as {any : any}
		local keys : {any} = {}
		for k in pairs(t) do table.insert(keys, k) end
		table.sort(keys, function(a : any, b : any) : boolean return tostring(a) < tostring(b) end)
		local parts : {string} = {}
		for _, k in ipairs(keys) do
			local ks = type(k) == "string" and k as string or "[" .. tostring(k) .. "]"
			table.insert(parts, ks .. "=" .. dumpValue(t[k], depth + 1))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end

	function logic.dump(v : any) : string
		return dumpValue(v, 0)
	end

	---------------------------------------------------------------------------
	-- vehicle modifiers (v2): fx.vehicleMods = cap(cards) combined with the boss round's mods

	--- state.cardVehicleMods, created if missing (nil-tolerant v1 state: copy of fx.vehicleMods,
	--- which in v1 held exactly the cards' aggregate).
	local function cardMods(s : QuotaRunState) : {string : number}
		if s.cardVehicleMods == nil then
			local copy : {string : number} = {}
			if s.fx ~= nil and s.fx.vehicleMods ~= nil then
				for k, v in pairs(s.fx.vehicleMods) do copy[k] = v end
			end
			s.cardVehicleMods = copy
		end
		return s.cardVehicleMods
	end

	local function clampMod(v : number) : number
		return math.max(VEHICLE_MOD_FLOOR, math.min(config.VEHICLE_MOD_CAP, v))
	end

	local function sameMods(a : {string : number}, b : {string : number}) : boolean
		for k, v in pairs(a) do
			local w = b[k]
			if w == nil or math.abs(w - v) > MOD_EPS then return false end
		end
		for k in pairs(b) do
			if a[k] == nil then return false end
		end
		return true
	end

	--- Recompute fx.vehicleMods from the cards' aggregate and the boss of the round in progress,
	--- base rule 1 + sum(v - 1) (PLAN §3.2), clamped to [VEHICLE_MOD_FLOOR, VEHICLE_MOD_CAP];
	--- keys at 1.0 are dropped. On a change: new table, vehicleModsRev bumped, "vehicleMods" intent.
	local function recomputeVehicleMods(s : QuotaRunState, intents : {QuotaRunIntent})
		if s.fx == nil then
			s.fx = { vehicleMods = {}, vehicleModsRev = 0, vehicleApplied = {}, industryMods = {}, nextScanTime = 0 }
		end
		local fx = s.fx
		local out : {string : number} = {}
		for k, v in pairs(cardMods(s)) do out[k] = v end
		local boss = bossOf(s)
		if boss ~= nil and boss.vehicleMods ~= nil then
			for k, v in pairs(boss.vehicleMods) do out[k] = (out[k] or 1.0) + (v - 1) end
		end
		for k, v in pairs(out) do
			local c = clampMod(v)
			if math.abs(c - 1.0) <= MOD_EPS then
				out[k] = nil -- clearing a field during pairs() is allowed in Lua
			else
				out[k] = c
			end
		end
		if sameMods(out, fx.vehicleMods or {}) then return end
		fx.vehicleMods = out
		fx.vehicleModsRev = (fx.vehicleModsRev or 0) + 1
		table.insert(intents, { kind = "vehicleMods" })
	end

	---------------------------------------------------------------------------
	-- bosses (v2, PLAN §9.4)

	--- A boss can run now: no rule, or its rule resolves and its target can be drawn.
	local function bossEligible(s : QuotaRunState, boss : QuotaRunBoss) : boolean
		if boss.rule == nil then return true end
		local rule : QuotaRunRule = nil
		if rules ~= nil then rule = rules.get(boss.rule) end
		return rule ~= nil and canTarget(s, rule)
	end

	--- A boss id drawn with the state LCG from the eligible bosses (list order), excluding
	--- `exclude`. nil when none is eligible.
	local function drawBoss(s : QuotaRunState, exclude : string) : string
		local pool : {string} = {}
		for _, b in ipairs(bosses.list) do
			if b.id ~= exclude and bossEligible(s, b) then table.insert(pool, b.id) end
		end
		if #pool == 0 then return nil end
		return pool[logic.rngNext(s, #pool)]
	end

	--- The boss announced one round ahead. Eligibility is judged on the CURRENT lastTally (a proxy:
	--- the boss round's targets come from the round that is starting now); falls back to any boss.
	local function announceBoss(s : QuotaRunState) : string
		local id = drawBoss(s, nil)
		if id == nil and #bosses.list > 0 then id = bosses.list[logic.rngNext(s, #bosses.list)].id end
		return id
	end

	--- Make the round in progress a boss round (s.rule/ruleTarget must already be cleared).
	--- A boss whose rule can't be set runs without it (warning).
	local function startBoss(s : QuotaRunState, id : string, why : string, intents : {QuotaRunIntent})
		local boss = bosses.get(id)
		s.boss = boss.id
		logIntent(intents, "boss round " .. tostring(s.round) .. ": " .. boss.id .. " (" .. why .. ")")
		if boss.rule ~= nil and not applyRule(s, boss.rule, "boss " .. boss.id, intents) then
			warn(intents, "boss " .. boss.id .. " runs without its rule this round")
		end
	end

	--- End the boss of the round in progress (debug setBoss); its rule goes with it.
	local function endBoss(s : QuotaRunState)
		local boss = bossOf(s)
		if boss ~= nil and boss.rule ~= nil and s.rule == boss.rule then
			s.rule = nil
			s.ruleTarget = nil
		end
		s.boss = nil
	end

	--- Boss for boss round r (announced one, else drawn now; replaced when it became ineligible).
	local function setUpBossRound(s : QuotaRunState, intents : {QuotaRunIntent})
		local id = s.nextBoss
		local boss : QuotaRunBoss = nil
		if id ~= nil then boss = bosses.get(id) end
		if boss == nil then
			id = announceBoss(s)
			if id == nil then
				warn(intents, "round " .. s.round .. " is a boss round but there are no bosses")
				return
			end
			logIntent(intents, "boss for round " .. s.round .. " drawn now (none announced): " .. id)
		elseif not bossEligible(s, boss) then
			local other = drawBoss(s, id)
			if other ~= nil then
				warn(intents, "announced boss " .. id .. " has no target this round; replaced by " .. other)
				id = other
			end
		end
		startBoss(s, id, "every " .. config.BOSS_EVERY .. " rounds", intents)
	end

	--- PLAN §9.3 (c): a random eligible rule on non-boss rounds from RANDOM_RULE_FROM_ROUND on.
	local function setUpRandomRule(s : QuotaRunState, intents : {QuotaRunIntent})
		local pool : {string} = {}
		for _, rule in ipairs(rules.list) do
			if canTarget(s, rule) then table.insert(pool, rule.id) end
		end
		if #pool == 0 then
			warn(intents, "round " .. s.round .. ": no eligible random rule")
			return
		end
		applyRule(s, pool[logic.rngNext(s, #pool)], "random rule", intents)
	end

	---------------------------------------------------------------------------
	-- round / run transitions

	local function startRound(s : QuotaRunState, r : integer, startTime : integer, statsTotal : integer, intents : {QuotaRunIntent})
		local months = r == 1 and config.FIRST_ROUND_MONTHS or config.ROUND_MONTHS
		s.round = r
		s.roundStartTime = startTime
		s.roundEndTime = startTime + months * s.monthDuration
		s.quotaMultRound = 1.0
		s.progress = 0
		s.halfwayWarned = false
		if statsTotal ~= nil then s.statsBaseline = statsTotal end
		-- v2: tallies shift, per-round modifiers reset, then this round's boss / rule (PLAN §9.3-9.4)
		s.lastTally = s.tally or emptyTally()
		s.tally = emptyTally()
		s.rewardMultRound = 1.0
		s.rule = nil
		s.ruleTarget = nil
		s.boss = nil
		if isBossRound(r) then
			setUpBossRound(s, intents)
		elseif rules ~= nil and (config.RANDOM_RULE_FROM_ROUND or 0) > 0 and r >= config.RANDOM_RULE_FROM_ROUND then
			setUpRandomRule(s, intents)
		end
		s.nextBoss = nil
		if isBossRound(r + 1) then
			s.nextBoss = announceBoss(s)
			if s.nextBoss ~= nil then
				logIntent(intents, "next boss (round " .. (r + 1) .. "): " .. s.nextBoss)
			end
		end
		recomputeVehicleMods(s, intents) -- boss mods on / previous boss's mods off
		s.quota = logic.computeQuota(s, r)
	end

	local function roundStartNotify(s : QuotaRunState, intents : {QuotaRunIntent}, gameTime : integer)
		notify(intents, "roundStart", {
			round = s.round,
			quota = s.quota,
			months = round(logic.monthsLeft(s, gameTime)),
			rule = s.rule,
			ruleTarget = s.ruleTarget, -- v2.1 addendum: the notification script names it
			boss = s.boss,
			nextBoss = s.nextBoss,
		})
	end

	local function endRun(s : QuotaRunState, reason : string, intents : {QuotaRunIntent})
		s.endReason = reason
		s.offer = nil
		s.nextBoss = nil -- no next round; rule/boss stay as the record of the final round
		s.totalTransported = (s.totalTransported or 0) + (s.progress or 0)
		setPhase(s, "ended", intents, reason)
		logIntent(intents, "run over: reason=" .. reason .. " round=" .. s.round .. " roundsCleared=" .. s.roundsCleared
			.. " total=" .. s.totalTransported)
		table.insert(intents, { kind = "clearEffects" })
		table.insert(intents, { kind = "pause" })
		notify(intents, "runOver", { reason = reason, rounds = s.roundsCleared, total = s.totalTransported })
	end

	--- " rule=x target=n boss=y" for log lines (empty when none is set).
	local function v2Suffix(s : QuotaRunState) : string
		local out = ""
		if s.rule ~= nil then out = out .. " rule=" .. s.rule end
		if s.ruleTarget ~= nil then out = out .. " target=" .. s.ruleTarget end
		if s.boss ~= nil then out = out .. " boss=" .. s.boss end
		return out
	end

	local function finishRound(s : QuotaRunState, statsTotal : integer, intents : {QuotaRunIntent})
		local r = s.round
		if s.progress < s.quota then
			logIntent(intents, "round " .. r .. " failed: progress=" .. s.progress .. " quota=" .. s.quota .. v2Suffix(s))
			endRun(s, "quota", intents)
			return
		end

		-- Reward first: it reads this round's rewardMultRound/boss, which startRound resets.
		local reward = logic.computeReward(s, r, s.progress, s.quota)
		s.lastReward = reward
		s.roundsCleared = s.roundsCleared + 1
		s.totalTransported = (s.totalTransported or 0) + s.progress
		logIntent(intents, "round " .. r .. " cleared: progress=" .. s.progress .. " quota=" .. s.quota .. " reward=" .. reward
			.. v2Suffix(s))
		if reward ~= 0 then
			table.insert(intents, { kind = "cash", amount = reward })
		end
		notify(intents, "roundCleared", { round = r, reward = reward, progress = s.progress, quota = s.quota })

		-- The next round starts AT THE DEADLINE, not at pick time (PLAN §3).
		startRound(s, r + 1, s.roundEndTime, statsTotal, intents)
		if s.phase == "choosing" then
			warn(intents, "round ended while a pick was pending; previous offer forfeited")
		end
		s.offer = logic.drawOffer(s)
		setPhase(s, "choosing", intents, "round " .. r .. " cleared")
		logIntent(intents, "round " .. s.round .. " started: provisional quota=" .. s.quota .. " offer=" .. table.concat(s.offer, ",")
			.. v2Suffix(s))
		table.insert(intents, { kind = "pause" })
	end

	local function monthTick(s : QuotaRunState, input : QuotaRunTickInput, intents : {QuotaRunIntent})
		local tickTime = s.nextMonthTick
		s.nextMonthTick = tickTime + s.monthDuration
		local balance = input.balance
		if balance ~= nil then
			if balance < 0 then
				s.redMonths = s.redMonths + 1
			else
				s.redMonths = 0
			end
		end
		local month = math.floor((tickTime - s.runStartTime) / s.monthDuration)
		local statsDelta = input.statsTotal ~= nil and tostring(input.statsTotal - (s.statsBaseline or 0)) or "?"
		logIntent(intents, "month " .. month .. ": round=" .. s.round .. " progress=" .. s.progress .. "/" .. s.quota
			.. " statsDelta=" .. statsDelta .. " balance=" .. (balance ~= nil and tostring(balance) or "inf")
			.. " redMonths=" .. s.redMonths .. " phase=" .. s.phase .. v2Suffix(s))
		if balance ~= nil and balance < 0 and s.redMonths == config.BANKRUPT_WARN_MONTHS then
			notify(intents, "bankruptWarn", { redMonths = s.redMonths, monthsLeft = config.BANKRUPT_MONTHS - s.redMonths })
		end
		if s.redMonths >= config.BANKRUPT_MONTHS then
			endRun(s, "bankrupt", intents)
		end
	end

	local function applyCard(s : QuotaRunState, card : QuotaRunCard, gameTime : integer, intents : {QuotaRunIntent})
		for _, eff in ipairs(card.effects) do
			local kind = eff.kind
			if kind == "cash" then
				local amount = eff.amount * s.round
				if amount ~= 0 then table.insert(intents, { kind = "cash", amount = amount }) end
			elseif kind == "quotaMultRound" then
				s.quotaMultRound = (s.quotaMultRound or 1.0) * eff.mult
			elseif kind == "quotaMultAll" then
				s.quotaMultAll = (s.quotaMultAll or 1.0) * eff.mult
			elseif kind == "rewardMult" then
				s.rewardMult = (s.rewardMult or 1.0) * eff.mult
			elseif kind == "rewardMultRound" then
				s.rewardMultRound = (s.rewardMultRound or 1.0) * eff.mult
			elseif kind == "rule" then
				if bossRuleActive(s) then
					warn(intents, "card " .. card.id .. ": the boss rule " .. s.rule .. " wins; rule " .. tostring(eff.rule) .. " ignored")
				else
					applyRule(s, eff.rule, "card " .. card.id, intents)
				end
			elseif kind == "roundMonths" then
				local old = s.roundEndTime
				local new = old + eff.months * s.monthDuration
				if eff.months < 0 then
					-- never earlier than now + MIN_MONTHS_LEFT, and a cut never extends the round
					local floor = gameTime + config.MIN_MONTHS_LEFT * s.monthDuration
					new = math.max(new, math.min(old, floor))
				end
				s.roundEndTime = new
			elseif kind == "vehicleMod" then
				-- base aggregation rule 1 + sum(v - 1), capped (PLAN §3.2), into the permanent card
				-- aggregate; fx.vehicleMods is derived from it (plus a boss's temporary mods)
				local mods = cardMods(s)
				for key, v in pairs(eff.mods) do
					mods[key] = clampMod((mods[key] or 1.0) + (v - 1))
				end
				recomputeVehicleMods(s, intents)
			elseif kind == "industryProd" then
				table.insert(intents, { kind = "industryMods", industryCount = eff.count, mult = eff.mult })
			else
				warn(intents, "card " .. card.id .. ": unknown effect kind " .. tostring(kind))
			end
		end
		s.quota = logic.computeQuota(s, s.round)
	end

	---------------------------------------------------------------------------
	-- v2 pure helpers: migrate, weight, factsNeeded

	function logic.migrate(s : QuotaRunState) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if not logic.isActive(s) or (s.version or 1) >= SCHEMA_VERSION then
			return s, intents
		end
		local from = s.version or 1
		if s.rewardMultRound == nil then s.rewardMultRound = 1.0 end
		if s.tally == nil then s.tally = emptyTally() end
		if s.lastTally == nil then s.lastTally = emptyTally() end
		cardMods(s) -- copy of fx.vehicleMods (v1: the cards' aggregate)
		s.version = SCHEMA_VERSION
		logIntent(intents, "state migrated v" .. from .. " -> v" .. SCHEMA_VERSION .. ": phase=" .. tostring(s.phase)
			.. " round=" .. tostring(s.round) .. " cardVehicleMods=" .. logic.dump(s.cardVehicleMods))
		-- Announce the boss if the next round is a boss round (the current one never becomes one).
		if inPlay(s) and s.nextBoss == nil and s.round ~= nil and isBossRound(s.round + 1) then
			s.nextBoss = announceBoss(s)
			if s.nextBoss ~= nil then
				logIntent(intents, "next boss (round " .. (s.round + 1) .. "): " .. s.nextBoss .. " (after migration)")
			end
		end
		return s, intents
	end

	local function kindWeight(kind : string) : number
		if kind == "cargo" then return config.CARGO_WEIGHT end
		if kind == "passenger" then return config.PASSENGER_WEIGHT end
		return 1.0
	end

	local function sameId(a : integer, b : integer) : boolean
		return a ~= nil and b ~= nil and math.floor(a) == math.floor(b)
	end

	--- Product formula documented on QuotaRunRule, times the config kind weight (so CARGO_WEIGHT /
	--- PASSENGER_WEIGHT retunes apply under every rule). Missing fact fields count as "no match"
	--- (otherWeight), an unresolved carrier counts 1. A rule with both target and crossTown would
	--- share otherWeight (none does in v2.1).
	function logic.weight(s : QuotaRunState, fact : QuotaRunDeliveryFact) : number
		if fact == nil then return 0 end
		local w = kindWeight(fact.kind)
		local rule : QuotaRunRule = nil
		if s ~= nil then rule = ruleOf(s) end
		if rule == nil then return w end
		if fact.kind == "cargo" then
			w = w * (rule.cargoWeight or 1.0)
		elseif rule.cargoOnly then
			return 0
		elseif fact.kind == "passenger" then
			w = w * (rule.passengerWeight or 1.0)
		end
		if rule.target ~= nil then
			local v : integer = nil
			if rule.target == "town" then
				v = fact.toTown
			elseif rule.target == "cargoType" then
				v = fact.cargoType
			end
			if sameId(v, s.ruleTarget) then
				w = w * (rule.targetWeight or 1.0)
			else
				w = w * (rule.otherWeight or 1.0)
			end
		end
		if rule.carrierWeights ~= nil and fact.kind == "cargo" and fact.carrier ~= nil then
			w = w * (rule.carrierWeights[fact.carrier] or 1.0)
		end
		if rule.crossTownWeight ~= nil then
			if fact.fromTown ~= nil and fact.toTown ~= nil and not sameId(fact.fromTown, fact.toTown) then
				w = w * rule.crossTownWeight
			else
				w = w * (rule.otherWeight or 1.0)
			end
		end
		return w
	end

	-- factsNeeded cache: rule id ("" = none) -> field set, one map per TALLY_FACTS value. Built from
	-- constant rule data only (rebuildable, rule 2.3). NO_FACTS marks "nil" (fast path).
	local NO_FACTS : {string : boolean} = {}
	local factsCacheTally : {string : {string : boolean}} = {}
	local factsCachePlain : {string : {string : boolean}} = {}

	--- Shared, cached sets: callers must not mutate the returned table.
	function logic.factsNeeded(s : QuotaRunState) : {string : boolean}
		if rules == nil and bosses == nil then return nil end
		if not logic.isActive(s) or not inPlay(s) or config.METRIC ~= "events" then return nil end
		local tallyOn = config.TALLY_FACTS == true
		local cache = tallyOn and factsCacheTally or factsCachePlain
		local id = s.rule or ""
		local set = cache[id]
		if set == nil then
			set = {}
			local any = false
			if tallyOn then
				set.cargoType = true
				set.toTown = true
				any = true
			end
			local rule = ruleOf(s)
			if rule ~= nil and rule.needs ~= nil then
				for _, field in ipairs(rule.needs) do
					set[field] = true
					any = true
				end
			end
			if not any then set = NO_FACTS end
			cache[id] = set
		end
		if set == NO_FACTS then return nil end
		return set
	end

	---------------------------------------------------------------------------
	-- entry points

	function logic.activate(s : QuotaRunState, input : QuotaRunActivateInput) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if s ~= nil and s.active ~= nil then
			return s, intents -- idempotent: already decided for this save
		end
		if input == nil or input.gameTime == nil or input.monthDuration == nil or input.monthDuration <= 0 then
			warn(intents, "activate: invalid input, staying inert")
			return s, intents
		end
		local now = input.gameTime
		local n : QuotaRunState = {
			version = SCHEMA_VERSION,
			active = true,
			phase = "running",
			rngSeed = logic.mixSeed(input.seed or now),
			roundsCleared = 0,
			runStartTime = now,
			nextMonthTick = now + input.monthDuration,
			totalTransported = 0,
			statsBaseline = input.statsTotal or 0,
			redMonths = 0,
			quotaMultAll = 1.0,
			quotaMultRound = 1.0,
			rewardMult = 1.0,
			picked = {},
			lastReward = 0,
			savedSpeed = 0,
			monthDuration = input.monthDuration,
			fx = {
				vehicleMods = {},
				vehicleModsRev = 0,
				vehicleApplied = {},
				industryMods = {},
				nextScanTime = now,
			},
			-- v2 (rule/ruleTarget/boss/nextBoss/tallies are set by startRound)
			cardVehicleMods = {},
			rewardMultRound = 1.0,
		}
		logIntent(intents, "activated: gameTime=" .. now .. " monthDuration=" .. n.monthDuration .. " seed=" .. n.rngSeed)
		startRound(n, 1, now, input.statsTotal, intents)
		logIntent(intents, "round 1 started: quota=" .. n.quota .. " endTime=" .. n.roundEndTime .. v2Suffix(n))
		roundStartNotify(n, intents, now)
		return n, intents
	end

	function logic.tick(s : QuotaRunState, input : QuotaRunTickInput) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if not logic.isActive(s) or not inPlay(s) or input == nil or input.gameTime == nil then
			return s, intents
		end
		local now = input.gameTime
		if config.METRIC == "stats" and input.statsTotal ~= nil then
			s.progress = math.max(0, input.statsTotal - (s.statsBaseline or 0))
		end

		-- Catch up every month tick and round end that elapsed, in time order (month first on ties).
		local steps = 0
		while inPlay(s) and steps < MAX_CATCHUP_STEPS do
			local monthDue = s.nextMonthTick <= now
			local roundDue = s.roundEndTime <= now
			if monthDue and (not roundDue or s.nextMonthTick <= s.roundEndTime) then
				monthTick(s, input, intents)
			elseif roundDue then
				finishRound(s, input.statsTotal, intents)
			else
				break
			end
			steps = steps + 1
		end

		if inPlay(s) and not s.halfwayWarned then
			local mid = s.roundStartTime + math.floor((s.roundEndTime - s.roundStartTime) / 2)
			if now >= mid then
				s.halfwayWarned = true
				if s.progress * 2 < s.quota then
					notify(intents, "halfway", { round = s.round, progress = s.progress, quota = s.quota,
						months = round(logic.monthsLeft(s, now)) })
				end
			end
		end
		return s, intents
	end

	function logic.delivered(s : QuotaRunState, input : QuotaRunDeliveredInput) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if not logic.isActive(s) or not inPlay(s) or config.METRIC ~= "events" then
			return s, intents
		end
		if input == nil then return s, intents end
		local facts = input.facts
		if facts ~= nil then
			-- v2 (PLAN §9.3): one fact = one unit; progress += the rule weights. Rounding: the weight
			-- sum is rounded once per call (half up), like the MVP path rounds units * weight per
			-- call. All v2.1 rule weights are integers (quota_rules.tl), so with integer kind
			-- weights nothing is lost; fractional config weights round per call as in the MVP.
			local tally = s.tally
			if tally == nil then
				tally = emptyTally()
				s.tally = tally
			end
			if tally.cargoTypes == nil then tally.cargoTypes = {} end
			if tally.towns == nil then tally.towns = {} end
			local sum = 0.0
			for _, fact in ipairs(facts) do
				sum = sum + logic.weight(s, fact)
				-- raw (unweighted) tallies, for next round's rule targets
				if fact.kind == "cargo" and fact.cargoType ~= nil then
					local k = math.floor(fact.cargoType)
					tally.cargoTypes[k] = (tally.cargoTypes[k] or 0) + 1
				end
				if fact.toTown ~= nil then
					local k = math.floor(fact.toTown)
					tally.towns[k] = (tally.towns[k] or 0) + 1
				end
			end
			s.progress = s.progress + round(sum)
			return s, intents
		end
		if input.units == nil or input.units <= 0 then
			return s, intents
		end
		-- No facts: units * kind weight. Under a rule this is the rule's kind weight (the weight of a
		-- fact that only has `kind`), which is exact for rules with empty `needs`; with no rule it is
		-- the MVP CARGO_WEIGHT / PASSENGER_WEIGHT (1.0 for an unknown kind).
		local weight : number
		if ruleOf(s) == nil then
			weight = kindWeight(input.kind)
		else
			weight = logic.weight(s, { kind = input.kind })
		end
		s.progress = s.progress + round(input.units * weight)
		return s, intents
	end

	function logic.pickCard(s : QuotaRunState, input : QuotaRunPickInput) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if not logic.isActive(s) then return s, intents end
		if s.phase ~= "choosing" or s.offer == nil then
			warn(intents, "pickCard ignored in phase " .. tostring(s.phase))
			return s, intents
		end
		local index = input and input.index
		if index == nil or index < 1 or index > #s.offer then
			warn(intents, "pickCard ignored: bad index " .. tostring(index))
			return s, intents
		end
		local card = cards.get(s.offer[index])
		if card == nil then
			warn(intents, "pickCard ignored: unknown card " .. tostring(s.offer[index]))
			return s, intents
		end
		local now = input.gameTime or s.roundStartTime
		applyCard(s, card, now, intents)
		table.insert(s.picked, card.id)
		s.offer = nil
		logIntent(intents, "picked " .. card.id .. ": round=" .. s.round .. " quota=" .. s.quota .. " endTime=" .. s.roundEndTime
			.. " quotaMultAll=" .. s.quotaMultAll .. " rewardMult=" .. s.rewardMult)
		setPhase(s, "running", intents, "picked " .. card.id)
		table.insert(intents, { kind = "resume" })
		roundStartNotify(s, intents, now)
		return s, intents
	end

	function logic.continueSandbox(s : QuotaRunState, _input : QuotaRunContinueInput) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if not logic.isActive(s) then return s, intents end
		if s.phase ~= "ended" then
			warn(intents, "continueSandbox ignored in phase " .. tostring(s.phase))
			return s, intents
		end
		setPhase(s, "sandbox", intents, "player continues as sandbox")
		table.insert(intents, { kind = "resume" })
		return s, intents
	end

	-- Debug ops (PLAN §4.2 table, §4.6 dev panel). All need config.DEBUG and an active state;
	-- forceStart on an inert save is handled by the adapter (it needs engine gates).
	local DEBUG_MAX_MONTHS <const> = 240             -- skipMonths upper bound (20 years)
	local DEBUG_MAX_MONEY <const> = 1000000000000    -- addMoney |n| upper bound
	local DEBUG_MAX_PCT <const> = 1000               -- addQuotaPct |n| upper bound

	--- input.n if it is an integer in [lo, hi] (and not 0 when nonZero), else nil after a warning.
	local function debugN(intents : {QuotaRunIntent}, op : string, n : integer, lo : integer, hi : integer, nonZero : boolean) : integer
		if n == nil or n < lo or n > hi or (nonZero and n == 0) then
			warn(intents, "debug " .. op .. " ignored: missing or invalid n " .. tostring(n)
				.. " (allowed " .. lo .. ".." .. hi .. (nonZero and ", not 0" or "") .. ")")
			return nil
		end
		return n
	end

	local function debugNeedsPlay(s : QuotaRunState, intents : {QuotaRunIntent}, op : string) : boolean
		if inPlay(s) then return true end
		warn(intents, "debug " .. op .. " ignored in phase " .. tostring(s.phase))
		return false
	end

	local function append(intents : {QuotaRunIntent}, more : {QuotaRunIntent})
		for _, it in ipairs(more) do table.insert(intents, it) end
	end

	-- v2 probe ops (PLAN §9.9) are executed by the adapter; the logic just acknowledges them.
	local PROBE_OPS <const> : {string : boolean} = {
		incomeProbe = true, factsProbe = true, jumpYears = true, closeIndustry = true, townProbe = true,
	}

	local function clearsId(id : string) : boolean
		return id == "" or id == "none"
	end

	--- v2 debug ops setRule / setBoss / setNextBoss (input.id; "" or "none" clears). Invalid input:
	--- warning, no change. Returns the intents (state mutated in place).
	local function debugV2(s : QuotaRunState, input : QuotaRunDebugInput, intents : {QuotaRunIntent}) : {QuotaRunIntent}
		local op = input.op
		if not debugNeedsPlay(s, intents, op) then return intents end
		local id = input.id
		if id == nil then
			warn(intents, "debug " .. op .. " ignored: missing id")
			return intents
		end
		if op == "setRule" then
			if clearsId(id) then
				s.rule = nil
				s.ruleTarget = nil
			else
				local rule : QuotaRunRule = nil
				if rules ~= nil then rule = rules.get(id) end
				if rule == nil then
					warn(intents, "debug setRule ignored: unknown rule id " .. id)
					return intents
				end
				if not canTarget(s, rule) then
					warn(intents, "debug setRule ignored: rule " .. id .. " has no " .. tostring(rule.target) .. " target in lastTally")
					return intents
				end
				applyRule(s, id, "debug setRule", intents)
			end
			s.quota = logic.computeQuota(s, s.round)
		elseif op == "setBoss" then
			if clearsId(id) then
				endBoss(s)
			else
				local boss : QuotaRunBoss = nil
				if bosses ~= nil then boss = bosses.get(id) end
				if boss == nil then
					warn(intents, "debug setBoss ignored: unknown boss id " .. id)
					return intents
				end
				if not bossEligible(s, boss) then
					warn(intents, "debug setBoss ignored: boss " .. id .. " has no rule target in lastTally")
					return intents
				end
				endBoss(s)
				s.rule = nil -- the boss's rule replaces any rule of the round
				s.ruleTarget = nil
				startBoss(s, id, "debug setBoss", intents)
			end
			recomputeVehicleMods(s, intents)
			s.quota = logic.computeQuota(s, s.round)
		else -- setNextBoss
			if clearsId(id) then
				s.nextBoss = nil
			else
				if bosses == nil or bosses.get(id) == nil then
					warn(intents, "debug setNextBoss ignored: unknown boss id " .. id)
					return intents
				end
				if not isBossRound(s.round + 1) then
					-- startRound clears nextBoss on a non-boss round, so the announcement would never come true
					warn(intents, "debug setNextBoss ignored: round " .. (s.round + 1) .. " is not a boss round (use setBoss)")
					return intents
				end
				s.nextBoss = id
			end
		end
		logIntent(intents, "debug " .. op .. " " .. id .. ": round=" .. s.round .. " quota=" .. s.quota .. v2Suffix(s)
			.. " nextBoss=" .. tostring(s.nextBoss))
		return intents
	end

	function logic.debug(s : QuotaRunState, input : QuotaRunDebugInput) : QuotaRunState, {QuotaRunIntent}
		local intents : {QuotaRunIntent} = {}
		if not logic.isActive(s) then return s, intents end
		if not config.DEBUG then
			warn(intents, "debug ignored: DEBUG is off")
			return s, intents
		end
		local op = input and input.op
		local now = input and input.gameTime
		if op == "dump" then
			logIntent(intents, "dump: " .. logic.dump(s))
			local needs = logic.factsNeeded(s)
			local needList : {string} = {}
			if needs ~= nil then
				for k in pairs(needs) do table.insert(needList, k) end
				table.sort(needList)
			end
			logIntent(intents, "dump v2: version=" .. tostring(s.version) .. " rule=" .. tostring(s.rule)
				.. " ruleTarget=" .. tostring(s.ruleTarget) .. " boss=" .. tostring(s.boss) .. " nextBoss=" .. tostring(s.nextBoss)
				.. " rewardMultRound=" .. tostring(s.rewardMultRound) .. " cardVehicleMods=" .. logic.dump(s.cardVehicleMods)
				.. " tally=" .. logic.dump(s.tally) .. " lastTally=" .. logic.dump(s.lastTally)
				.. " factsNeeded=" .. (needs ~= nil and table.concat(needList, ",") or "nil"))
			return s, intents
		end
		if op == "forceStart" then
			warn(intents, "debug forceStart ignored: the run is already active (use op=reset for a fresh run)")
			return s, intents
		end
		if PROBE_OPS[op] then
			-- adapter-only (PLAN §9.9); never meant to reach the logic: no change, no warning
			logIntent(intents, "debug " .. op .. " is adapter-only; ignored by the logic")
			return s, intents
		end
		if op == "setRule" or op == "setBoss" or op == "setNextBoss" then
			return s, debugV2(s, input, intents)
		end
		if now == nil then
			warn(intents, "debug " .. tostring(op) .. " ignored: no gameTime")
			return s, intents
		end
		if op == "endRound" then
			s.roundEndTime = now
		elseif op == "addProgress" then
			if input.n == nil then
				warn(intents, "debug addProgress ignored: missing n")
				return s, intents
			end
			s.progress = math.max(0, s.progress + input.n)
		elseif op == "addQuotaPct" then
			-- progress += n% of the current quota (+100 => exactly one quota more)
			local n = debugN(intents, op, input.n, -DEBUG_MAX_PCT, DEBUG_MAX_PCT, true)
			if n == nil then return s, intents end
			s.progress = math.max(0, s.progress + round(s.quota * n / 100))
		elseif op == "setMonthsLeft" then
			if input.n == nil then
				warn(intents, "debug setMonthsLeft ignored: missing n")
				return s, intents
			end
			s.roundEndTime = now + input.n * s.monthDuration
		elseif op == "bankrupt" then
			s.redMonths = config.BANKRUPT_MONTHS - 1
		elseif op == "offer" then
			if not inPlay(s) then
				warn(intents, "debug offer ignored in phase " .. tostring(s.phase))
				return s, intents
			end
			s.offer = logic.drawOffer(s)
			setPhase(s, "choosing", intents, "debug offer")
			logIntent(intents, "offer=" .. table.concat(s.offer, ","))
			table.insert(intents, { kind = "pause" })
			return s, intents
		elseif op == "passRound" or op == "failRound" then
			-- Judge the round NOW (no unpaused frame needed): pass -> choosing (next round starts now),
			-- fail -> ended. Pass keeps any progress above the quota (bonus reward still possible).
			if not debugNeedsPlay(s, intents, op) then return s, intents end
			if op == "passRound" then
				s.progress = math.max(s.progress, s.quota)
			else
				s.progress = 0
			end
			s.roundEndTime = now
			logIntent(intents, "debug " .. op .. ": round=" .. s.round .. " progress=" .. s.progress .. " quota=" .. s.quota)
			finishRound(s, input.statsTotal, intents)
			return s, intents
		elseif op == "skipMonths" then
			-- Behave as if n default months had passed: every time anchor moves back by n months, then
			-- the normal catch-up runs now. That fires n month ticks (each one reads the CURRENT balance,
			-- so in the red redMonths += n and bankruptcy can end the run; in the black redMonths = 0), and
			-- ends the round if the deadline falls inside the skipped span (month ticks first on ties).
			-- No deliveries happen in skipped months, money and the game calendar do not move.
			if not debugNeedsPlay(s, intents, op) then return s, intents end
			local n = debugN(intents, op, input.n, 1, DEBUG_MAX_MONTHS, true)
			if n == nil then return s, intents end
			local d = n * s.monthDuration
			s.runStartTime = s.runStartTime - d
			s.roundStartTime = s.roundStartTime - d
			s.roundEndTime = s.roundEndTime - d
			s.nextMonthTick = s.nextMonthTick - d
			logIntent(intents, "debug skipMonths " .. n .. ": roundEndTime=" .. s.roundEndTime .. " nextMonthTick=" .. s.nextMonthTick)
			local _, more = logic.tick(s, { gameTime = now, balance = input.balance, statsTotal = input.statsTotal })
			append(intents, more)
			return s, intents
		elseif op == "applyCard" then
			-- Same resolution as pickCard, without an offer: phase, offer and speed are untouched.
			-- Recorded in `picked` like a real pick (the log line marks it as a debug apply).
			if not debugNeedsPlay(s, intents, op) then return s, intents end
			local card = input.id ~= nil and cards.get(input.id) or nil
			if card == nil then
				warn(intents, "debug applyCard ignored: unknown card id " .. tostring(input.id))
				return s, intents
			end
			applyCard(s, card, now, intents)
			table.insert(s.picked, card.id)
			logIntent(intents, "debug applyCard " .. card.id .. " (no offer used): round=" .. s.round .. " quota=" .. s.quota
				.. " endTime=" .. s.roundEndTime .. " quotaMultAll=" .. s.quotaMultAll .. " rewardMult=" .. s.rewardMult)
			return s, intents
		elseif op == "addMoney" then
			local n = debugN(intents, op, input.n, -DEBUG_MAX_MONEY, DEBUG_MAX_MONEY, true)
			if n == nil then return s, intents end
			logIntent(intents, "debug addMoney " .. n)
			table.insert(intents, { kind = "cash", amount = n })
			return s, intents
		elseif op == "clearEffects" then
			-- Engine effects only (vehicle + industry modifiers); quota/reward multipliers and the phase stay.
			-- cardVehicleMods is emptied too, otherwise the next recomputeVehicleMods (round start,
			-- setBoss, a vehicleMod card) would re-send the cleared card mods.
			s.cardVehicleMods = {}
			logIntent(intents, "debug clearEffects (phase stays " .. tostring(s.phase) .. ")")
			table.insert(intents, { kind = "clearEffects" })
			return s, intents
		elseif op == "reset" then
			-- Fresh run in place: undo the old run's engine effects (and our pause), then activate anew
			-- at `now` with a seed that differs from the old run. The old fx/savedSpeed ride along on the
			-- new state so the clearEffects/resume intents (executed on the returned state) see them.
			local old = s
			local wasPaused = old.phase == "choosing" or old.phase == "ended"
			local n, activateIntents = logic.activate(nil, {
				gameTime = now,
				seed = (old.rngSeed or 0) + now,
				monthDuration = old.monthDuration,
				statsTotal = input.statsTotal,
			})
			if n == nil then
				append(intents, activateIntents)
				return s, intents
			end
			n.fx = old.fx or n.fx
			n.savedSpeed = old.savedSpeed or 0
			logIntent(intents, "debug reset: old run phase=" .. tostring(old.phase) .. " round=" .. tostring(old.round) .. " -> fresh run")
			table.insert(intents, { kind = "clearEffects" })
			if wasPaused then table.insert(intents, { kind = "resume" }) end
			append(intents, activateIntents)
			return n, intents
		else
			warn(intents, "debug: unknown op " .. tostring(op))
			return s, intents
		end
		logIntent(intents, "debug " .. op .. ": progress=" .. s.progress .. " roundEndTime=" .. s.roundEndTime
			.. " redMonths=" .. s.redMonths)
		return s, intents
	end

	return logic
end

return M
