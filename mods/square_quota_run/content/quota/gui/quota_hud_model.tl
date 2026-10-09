-- Quota Run HUD view model (PLAN.md §6 Phase 3). PURE: no api.*, no base modules, so it is
-- unit-tested offline (tests/square_quota_run/test_hud_model.lua).
-- build(state, gameTime) returns a small, flat, fresh table for useStepStateTimer's deepEquals,
-- or nil when the HUD must render nothing.

local config = ug_require "square_quota_run::/quota/quota_config.tl" as QuotaRunConfig
local cards = ug_require "square_quota_run::/quota/quota_cards.tl" as QuotaRunCards
-- v2.1 (PLAN §9.3, §9.4): data-only modules, safe on the GUI thread.
local rules = ug_require "square_quota_run::/quota/quota_rules.tl" as QuotaRunRules
local bosses = ug_require "square_quota_run::/quota/quota_bosses.tl" as QuotaRunBosses

local function int(v : number) : integer
	if v == nil then return 0 end
	return math.floor(v + 0.5)
end

local function cardName(id : string) : string
	local card = cards.get(id)
	return card and card.name or id
end

--- v2: rule / boss lookups by id. nil / unknown id (or a non-string after a bad save) -> nil, never an error.
local function ruleById(id : string) : QuotaRunRule
	if type(id) ~= "string" or rules == nil or rules.byId == nil then return nil end
	return rules.byId[id]
end

local function bossById(id : string) : QuotaRunBoss
	if type(id) ~= "string" or bosses == nil or bosses.byId == nil then return nil end
	return bosses.byId[id]
end

--- Dev panel status (DEBUG only): "veh TopSpeed=1.15 x12 | ind 3" or "no effects".
local function fxSummary(s : QuotaRunState) : string
	local fx = s.fx
	if fx == nil then return "no effects" end
	local keys : {string} = {}
	for k in pairs(fx.vehicleMods or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local mods : {string} = {}
	for _, k in ipairs(keys) do mods[#mods + 1] = k .. "=" .. string.format("%.2f", fx.vehicleMods[k]) end
	local vehicles, industries = 0, 0
	for _ in pairs(fx.vehicleApplied or {}) do vehicles = vehicles + 1 end
	for _ in pairs(fx.industryMods or {}) do industries = industries + 1 end
	if #mods == 0 and vehicles == 0 and industries == 0 then return "no effects" end
	return "veh " .. (#mods > 0 and table.concat(mods, ",") or "-") .. " x" .. vehicles .. " | ind " .. industries
end

--- DEBUG-only view for a state without a run in play: "inert" (nil / undecided) or "sandbox".
local function devOnlyView(phase : string, s : QuotaRunState) : QuotaRunHudView
	local picked : {string} = {}
	if s ~= nil then
		for i, id in ipairs(s.picked or {}) do picked[i] = cardName(id) end
	end
	return {
		phase = phase,
		round = s ~= nil and int(s.round) or 0,
		roundsCleared = s ~= nil and int(s.roundsCleared) or 0,
		progress = 0,
		quota = 0,
		fraction = 0.0,
		provisional = false,
		redMonths = 0,
		bankruptMonths = config.BANKRUPT_MONTHS,
		redWarning = false,
		picked = picked,
		offer = {},
		debug = true,
		fxSummary = s ~= nil and fxSummary(s) or "no effects",
	}
end

local model : QuotaRunHudModel = {}

function model.build(s : QuotaRunState, gameTime : integer) : QuotaRunHudView
	if s == nil or s.active ~= true then
		-- DEBUG: keep the dev panel reachable on an undecided inert save (forceStart).
		-- active == false (turned off by a mission/tutorial start) stays hidden.
		if config.DEBUG and (s == nil or s.active == nil) then return devOnlyView("inert", s) end
		return nil
	end
	local phase = s.phase
	if phase == "sandbox" and config.DEBUG then return devOnlyView("sandbox", s) end
	if phase ~= "running" and phase ~= "choosing" and phase ~= "ended" then return nil end

	local inPlay = phase ~= "ended"
	local progress = int(s.progress)
	local quota = int(s.quota)
	local fraction = 0.0
	if quota > 0 then fraction = math.min(1.0, math.max(0.0, progress / quota)) end

	local monthsLeft : integer = nil
	if gameTime ~= nil and s.roundEndTime ~= nil and s.monthDuration ~= nil and s.monthDuration > 0 then
		monthsLeft = math.max(0, math.ceil((s.roundEndTime - gameTime) / s.monthDuration))
	end

	local picked : {string} = {}
	for i, id in ipairs(s.picked or {}) do picked[i] = cardName(id) end

	local offer : {QuotaRunHudCard} = {}
	if phase == "choosing" then
		for i, id in ipairs(s.offer or {}) do
			local card = cards.get(id)
			offer[#offer + 1] = {
				index = i,
				id = id,
				name = card and card.name or id,
				description = card and card.description or "",
			}
		end
	end

	-- v2: what counts this round, and the announced boss (in play only; nil on v1 states).
	local rule = inPlay and ruleById(s.rule) or nil
	local boss = inPlay and bossById(s.boss) or nil
	local nextBoss = inPlay and bossById(s.nextBoss) or nil
	-- v2.1 addendum: the rule's target id + kind; the HUD script resolves the name (engine call).
	local ruleTarget : integer = nil
	local ruleTargetKind : string = nil
	if rule ~= nil and (rule.target == "town" or rule.target == "cargoType") and type(s.ruleTarget) == "number" then
		ruleTarget = math.floor(s.ruleTarget)
		ruleTargetKind = rule.target
	end

	local redMonths = int(s.redMonths)
	return {
		phase = phase,
		ruleName = rule and rule.name or nil,
		ruleDescription = rule and rule.description or nil,
		ruleTarget = ruleTarget,
		ruleTargetKind = ruleTargetKind,
		bossName = boss and boss.name or nil,
		bossDescription = boss and boss.description or nil,
		nextBossName = nextBoss and nextBoss.name or nil,
		nextBossDescription = nextBoss and nextBoss.description or nil,
		round = int(s.round),
		roundsCleared = int(s.roundsCleared),
		monthsLeft = monthsLeft,
		progress = progress,
		quota = quota,
		fraction = fraction,
		provisional = phase == "choosing",
		redMonths = redMonths,
		bankruptMonths = config.BANKRUPT_MONTHS,
		redWarning = inPlay and redMonths > 0,
		picked = picked,
		offer = offer,
		endReason = (not inPlay) and s.endReason or nil,
		totalTransported = (not inPlay) and int(s.totalTransported) or nil,
		debug = config.DEBUG or nil,
		fxSummary = config.DEBUG and fxSummary(s) or nil,
	}
end

return model
