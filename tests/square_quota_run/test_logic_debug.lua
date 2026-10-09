-- quota_logic dev-panel debug ops (PLAN §4.2 debug-op table, §4.6): passRound, failRound,
-- skipMonths, applyCard, addMoney, addQuotaPct, clearEffects, reset, forceStart (active run).
-- DEBUG = false gating for every op is in test_logic_events.lua.

local config = ug_require "/quota/quota_config.tl"
local cards = ug_require "/quota/quota_cards.tl"
local logic = ug_require("/quota/quota_logic.tl").new(config, cards)

local MD = 1000
local FAR = 1000000000
local PHASES = { "running", "choosing", "ended", "sandbox" }

local function activate(t)
	return (logic.activate(nil, { gameTime = t or 0, seed = 42, monthDuration = MD, statsTotal = 0 }))
end

--- An active state that just cleared round 1 and is choosing from `offer` (round 2 in progress).
local function choosing(offer)
	local s = activate(0)
	s.nextMonthTick = FAR
	s.progress = s.quota
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	assert(s.phase == "choosing" and s.round == 2)
	if offer then s.offer = offer end
	return s
end

local function find(intents, kind, key)
	for _, it in ipairs(intents) do
		if it.kind == kind and (key == nil or it.key == key) then return it end
	end
end

local function warned(intents, text)
	for _, it in ipairs(intents) do
		if it.kind == "log" and it.level == "warning" and (text == nil or it.message:find(text, 1, true)) then return true end
	end
	return false
end

local function kinds(intents)
	local out = {}
	for _, it in ipairs(intents) do out[#out + 1] = it.kind end
	return out
end

local function count(intents, kind)
	local n = 0
	for _, it in ipairs(intents) do if it.kind == kind then n = n + 1 end end
	return n
end

before_each(function()
	config.DEBUG = true
	config.METRIC = "events"
end)

test("debug ops on a nil / inert state: no change, no intents (forceStart is adapter-only)", function()
	for _, op in ipairs({ "passRound", "reset", "forceStart", "applyCard", "addMoney" }) do
		local s, intents = logic.debug(nil, { op = op, n = 5, gameTime = 0, id = "venture" })
		eq(s, nil)
		eq(intents, {})
		s, intents = logic.debug({ version = 1, active = false }, { op = op, n = 5, gameTime = 0, id = "venture" })
		eq(s, { version = 1, active = false })
		eq(intents, {})
	end
end)

-- passRound / failRound -----------------------------------------------------------

test("passRound: judged now, next round starts now, choosing + pause + reward", function()
	local s = activate(0)
	s.progress = 10
	local _, intents = logic.debug(s, { op = "passRound", gameTime = 4321, balance = 1 })
	eq(s.phase, "choosing")
	eq(s.round, 2)
	eq(s.roundsCleared, 1)
	eq(s.roundStartTime, 4321)
	eq(s.roundEndTime, 4321 + config.ROUND_MONTHS * MD)
	eq(#s.offer, 3)
	eq(s.progress, 0)
	eq(s.totalTransported, config.BASE_QUOTA)
	ok(find(intents, "pause"))
	eq(find(intents, "cash").amount, config.REWARD_BASE)
	ok(find(intents, "notify", "roundCleared"))
end)

test("passRound keeps progress above the quota (bonus reward)", function()
	local s = activate(0)
	s.progress = s.quota * 2
	local _, intents = logic.debug(s, { op = "passRound", gameTime = 5 })
	eq(find(intents, "cash").amount, math.floor(config.REWARD_BASE * (1 + config.REWARD_BONUS) + 0.5))
end)

test("passRound while choosing forfeits the pending offer and stays choosing", function()
	local s = choosing({ "venture", "express", "gamble" })
	local _, intents = logic.debug(s, { op = "passRound", gameTime = s.roundStartTime + 1 })
	eq(s.phase, "choosing")
	eq(s.round, 3)
	ok(warned(intents, "offer forfeited"))
end)

test("failRound: progress 0, ended (quota), clearEffects + pause", function()
	local s = activate(0)
	s.progress = 99999
	local _, intents = logic.debug(s, { op = "failRound", gameTime = 50 })
	eq(s.phase, "ended")
	eq(s.endReason, "quota")
	eq(s.totalTransported, 0)
	ok(find(intents, "clearEffects"))
	ok(find(intents, "pause"))
	ok(find(intents, "notify", "runOver"))
end)

test("passRound / failRound / skipMonths / applyCard need running or choosing", function()
	for _, op in ipairs({ "passRound", "failRound", "skipMonths", "applyCard" }) do
		for _, ph in ipairs({ "ended", "sandbox" }) do
			local s = activate(0)
			s.phase = ph
			local before = logic.dump(s)
			local _, intents = logic.debug(s, { op = op, n = 1, id = "venture", gameTime = 10, balance = -1 })
			eq(logic.dump(s), before, op .. " " .. ph)
			ok(warned(intents, "ignored in phase " .. ph), op .. " " .. ph)
		end
	end
end)

-- skipMonths ----------------------------------------------------------------------

test("skipMonths: time anchors move back n months; n month ticks fire now", function()
	local s = activate(0)
	local now = 100
	local before = { s.runStartTime, s.roundStartTime, s.roundEndTime, s.nextMonthTick }
	local _, intents = logic.debug(s, { op = "skipMonths", n = 2, gameTime = now, balance = -1 })
	eq(s.runStartTime, before[1] - 2 * MD)
	eq(s.roundStartTime, before[2] - 2 * MD)
	eq(s.roundEndTime, before[3] - 2 * MD)
	-- the two skipped ticks were caught up, so the next tick is where it was before
	eq(s.nextMonthTick, before[4])
	eq(s.redMonths, 2)
	eq(s.phase, "running")
	eq(math.ceil(logic.monthsLeft(s, now)), config.FIRST_ROUND_MONTHS - 2)
	local months = 0
	for _, it in ipairs(intents) do
		if it.kind == "log" and it.message:find("^month ") then months = months + 1 end
	end
	eq(months, 2)
end)

test("skipMonths in the black resets red months; nil balance (infinite money) leaves them", function()
	local s = activate(0)
	s.redMonths = 4
	logic.debug(s, { op = "skipMonths", n = 1, gameTime = 0, balance = 5 })
	eq(s.redMonths, 0)
	s.redMonths = 4
	logic.debug(s, { op = "skipMonths", n = 1, gameTime = 0 })
	eq(s.redMonths, 4)
end)

test("skipMonths past the deadline judges the round (month ticks first)", function()
	local s = activate(0)
	s.progress = s.quota
	logic.debug(s, { op = "setMonthsLeft", n = 3, gameTime = 0 })
	local _, intents = logic.debug(s, { op = "skipMonths", n = 6, gameTime = 0, balance = 1 })
	eq(s.phase, "choosing")
	eq(s.round, 2)
	-- the new round started at the (shifted) old deadline, 3 months ago
	eq(s.roundStartTime, -3 * MD)
	eq(math.ceil(logic.monthsLeft(s, 0)), config.ROUND_MONTHS - 3)
	ok(find(intents, "pause"))
	-- failing instead ends the run, which stops the catch-up
	s = activate(0)
	logic.debug(s, { op = "setMonthsLeft", n = 3, gameTime = 0 })
	logic.debug(s, { op = "skipMonths", n = 6, gameTime = 0, balance = 1 })
	eq(s.phase, "ended")
	eq(s.endReason, "quota")
end)

test("skipMonths in the red reaches bankruptcy (warning on the way)", function()
	local s = activate(0)
	local _, intents = logic.debug(s, { op = "skipMonths", n = config.BANKRUPT_MONTHS, gameTime = 0, balance = -1 })
	eq(s.phase, "ended")
	eq(s.endReason, "bankrupt")
	ok(find(intents, "notify", "bankruptWarn"))
end)

test("bankrupt + skipMonths 1 in the red ends the run (dev panel recipe)", function()
	local s = activate(0)
	logic.debug(s, { op = "bankrupt", gameTime = 0 })
	logic.debug(s, { op = "skipMonths", n = 1, gameTime = 0, balance = -1 })
	eq(s.phase, "ended")
	eq(s.endReason, "bankrupt")
end)

test("skipMonths validates n", function()
	for _, n in ipairs({ 0, -1, 241 }) do
		local s = activate(0)
		local before = logic.dump(s)
		local _, intents = logic.debug(s, { op = "skipMonths", n = n, gameTime = 0, balance = -1 })
		eq(logic.dump(s), before, tostring(n))
		ok(warned(intents, "invalid n"), tostring(n))
	end
	local _, intents = logic.debug(activate(0), { op = "skipMonths", gameTime = 0 })
	ok(warned(intents, "invalid n"))
end)

-- applyCard -----------------------------------------------------------------------

test("applyCard: same resolution as pickCard, no offer used, phase kept", function()
	local s = activate(0)
	local _, intents = logic.debug(s, { op = "applyCard", id = "venture", gameTime = 10 })
	eq(s.phase, "running")
	eq(s.picked, { "venture" })
	eq(find(intents, "cash").amount, 4000000)
	eq(count(intents, "resume"), 0)
	eq(count(intents, "notify"), 0)
	-- while choosing: the offer stays pending
	s = choosing({ "venture", "express", "gamble" })
	_, intents = logic.debug(s, { op = "applyCard", id = "express", gameTime = s.roundStartTime })
	eq(s.phase, "choosing")
	eq(s.offer, { "venture", "express", "gamble" })
	eq(s.fx.vehicleMods.TopSpeed, 1.15)
	ok(find(intents, "vehicleMods"))
	-- quota effects recompute the quota like a pick
	s = activate(0)
	logic.debug(s, { op = "applyCard", id = "lean_year", gameTime = 0 })
	eq(s.quota, math.floor(config.BASE_QUOTA * 0.8 + 0.5))
end)

test("applyCard matches pickCard for every card", function()
	for _, card in ipairs(cards.list) do
		local a = choosing({ card.id, "venture", "lean_year" })
		local b = choosing({ card.id, "venture", "lean_year" })
		local now = a.roundStartTime + 5
		local _, ia = logic.pickCard(a, { index = 1, gameTime = now })
		local _, ib = logic.debug(b, { op = "applyCard", id = card.id, gameTime = now })
		for _, k in ipairs({ "quota", "roundEndTime", "quotaMultAll", "quotaMultRound", "rewardMult", "picked" }) do
			eq(b[k], a[k], card.id .. " " .. k)
		end
		eq(b.fx.vehicleMods, a.fx.vehicleMods, card.id)
		for _, kind in ipairs({ "cash", "vehicleMods", "industryMods" }) do
			eq(count(ib, kind), count(ia, kind), card.id .. " " .. kind)
		end
	end
end)

test("applyCard rejects unknown or missing ids", function()
	local s = activate(0)
	local before = logic.dump(s)
	local _, intents = logic.debug(s, { op = "applyCard", id = "nope", gameTime = 0 })
	ok(warned(intents, "unknown card id nope"))
	_, intents = logic.debug(s, { op = "applyCard", gameTime = 0 })
	ok(warned(intents, "unknown card id nil"))
	eq(logic.dump(s), before)
end)

-- addMoney / addQuotaPct / clearEffects ------------------------------------------------

test("addMoney: cash intent in any active phase; n validated", function()
	for _, ph in ipairs(PHASES) do
		local s = activate(0)
		s.phase = ph
		local _, intents = logic.debug(s, { op = "addMoney", n = -10000000, gameTime = 0 })
		eq(find(intents, "cash").amount, -10000000, ph)
	end
	for _, n in ipairs({ 0, 2000000000000 }) do
		local _, intents = logic.debug(activate(0), { op = "addMoney", n = n, gameTime = 0 })
		ok(warned(intents, "invalid n"))
		eq(find(intents, "cash"), nil)
	end
	local _, intents = logic.debug(activate(0), { op = "addMoney", gameTime = 0 })
	ok(warned(intents, "invalid n"))
end)

test("addQuotaPct: n% of the quota; +100 adds exactly one quota; validated", function()
	local s = activate(0)
	logic.debug(s, { op = "addQuotaPct", n = 25, gameTime = 0 })
	eq(s.progress, 625)
	logic.debug(s, { op = "addQuotaPct", n = 100, gameTime = 0 })
	eq(s.progress, 625 + 2500)
	logic.debug(s, { op = "addQuotaPct", n = -1000, gameTime = 0 })
	eq(s.progress, 0)
	local _, intents = logic.debug(s, { op = "addQuotaPct", n = 0, gameTime = 0 })
	ok(warned(intents, "invalid n"))
end)

test("clearEffects: one clearEffects intent; phase and multipliers kept", function()
	local s = choosing({ "venture", "express", "gamble" })
	s.rewardMult = 2.0
	local _, intents = logic.debug(s, { op = "clearEffects", gameTime = 0 })
	eq(s.phase, "choosing")
	eq(s.rewardMult, 2.0)
	eq(count(intents, "clearEffects"), 1)
	eq(count(intents, "pause") + count(intents, "resume"), 0)
end)

-- reset / forceStart --------------------------------------------------------------

test("reset: fresh run at now, new seed, old fx cleared first, resume if paused", function()
	local s = choosing({ "venture", "express", "gamble" })
	logic.pickCard(s, { index = 2, gameTime = s.roundStartTime })
	s.phase = "ended"
	s.savedSpeed = 3
	local oldSeed = s.rngSeed
	local oldFx = s.fx
	local n, intents = logic.debug(s, { op = "reset", gameTime = 777, statsTotal = 40 })
	ok(n ~= s, "a new state table")
	eq(n.active, true)
	eq(n.phase, "running")
	eq(n.round, 1)
	eq(n.roundsCleared, 0)
	eq(n.picked, {})
	eq(n.runStartTime, 777)
	eq(n.statsBaseline, 40)
	eq(n.monthDuration, MD)
	ok(n.rngSeed ~= oldSeed)
	ok(n.fx == oldFx, "old fx rides along so clearEffects sees it")
	eq(n.savedSpeed, 3)
	local k = kinds(intents)
	eq(k[1], "log")
	eq(k[2], "clearEffects")
	eq(k[3], "resume")
	ok(find(intents, "notify", "roundStart"))
	-- from running: no resume
	_, intents = logic.debug(activate(0), { op = "reset", gameTime = 5 })
	eq(count(intents, "resume"), 0)
	eq(count(intents, "clearEffects"), 1)
end)

test("reset seeds differently from the old run", function()
	local a = activate(0)
	local b = logic.debug(activate(0), { op = "reset", gameTime = 0 })
	ok(a.rngSeed ~= b.rngSeed)
end)

test("forceStart on an active run is refused (use reset)", function()
	local s = activate(0)
	local before = logic.dump(s)
	local _, intents = logic.debug(s, { op = "forceStart", gameTime = 0 })
	eq(logic.dump(s), before)
	ok(warned(intents, "already active"))
end)
