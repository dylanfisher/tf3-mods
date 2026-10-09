-- quota_logic event entry points: every §4.2 row (pickCard, continueSandbox, every debug op),
-- rejections in every wrong phase, card resolution for every effect kind (PLAN §3.2, §4.2, §5.2).

local config = ug_require "/quota/quota_config.tl"
local logic = ug_require("/quota/quota_logic.tl").new(config, ug_require "/quota/quota_cards.tl")
local cards = ug_require "/quota/quota_cards.tl"

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

local function pick(id, gameTime)
	local s = choosing({ id, "venture", "lean_year" })
	local now = gameTime or s.roundStartTime
	local _, intents = logic.pickCard(s, { index = 1, gameTime = now })
	return s, intents
end

before_each(function()
	config.DEBUG = true
	config.METRIC = "events"
end)

-- QuotaRun.pickCard ----------------------------------------------------------

test("pickCard: CHOOSING -> RUNNING, records pick, resume + roundStart notify", function()
	local s = choosing({ "venture", "express", "gamble" })
	local _, intents = logic.pickCard(s, { index = 2, gameTime = s.roundStartTime + 10 })
	eq(s.phase, "running")
	eq(s.offer, nil)
	eq(s.picked, { "express" })
	ok(find(intents, "resume"))
	local n = find(intents, "notify", "roundStart")
	eq(n.params.round, 2)
	eq(n.params.quota, s.quota)
	eq(n.params.months, 24)
end)

test("pickCard rejected in every non-choosing phase", function()
	for _, ph in ipairs({ "running", "ended", "sandbox" }) do
		local s = choosing({ "venture", "express", "gamble" })
		s.phase = ph
		local before = logic.dump(s)
		local _, intents = logic.pickCard(s, { index = 1, gameTime = 0 })
		eq(logic.dump(s), before, ph)
		ok(warned(intents, "pickCard ignored"), ph)
		eq(find(intents, "resume"), nil)
	end
end)

test("pickCard rejects bad index (nil, 0, 4, -1) and unknown card ids", function()
	for _, idx in ipairs({ 0, 4, -1 }) do
		local s = choosing()
		local before = logic.dump(s)
		local _, intents = logic.pickCard(s, { index = idx, gameTime = 0 })
		eq(logic.dump(s), before)
		ok(warned(intents, "bad index"))
	end
	local s = choosing()
	local _, intents = logic.pickCard(s, { gameTime = 0 })
	ok(warned(intents, "bad index"))
	eq(s.phase, "choosing")
	s.offer = { "nope", "venture", "express" }
	_, intents = logic.pickCard(s, { index = 1, gameTime = 0 })
	ok(warned(intents, "unknown card"))
	eq(s.phase, "choosing")
end)

-- card resolution, per effect kind -------------------------------------------

test("cash: amount x round (round = the round that just started)", function()
	local _, intents = pick("venture")
	eq(find(intents, "cash").amount, 4000000 * 2)
	local _, i2 = pick("austerity")
	eq(find(i2, "cash").amount, -5000000 * 2)
end)

test("quotaMultRound: recomputes this round's quota; reset next round", function()
	local s, intents = pick("hostile_loan")
	eq(find(intents, "cash").amount, 24000000)
	near(s.quotaMultRound, 1.3)
	eq(s.quota, math.floor(4000 * 1.3 + 0.5))
	s.progress = s.quota
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.quotaMultRound, 1.0)
	eq(s.quota, 6400)
end)

test("quotaMultAll: applies now and to future rounds", function()
	local s = pick("austerity")
	near(s.quotaMultAll, 0.85)
	eq(s.quota, math.floor(4000 * 0.85 + 0.5))
	s.progress = s.quota
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.quota, math.floor(6400 * 0.85 + 0.5))
end)

test("lean_year and gamble", function()
	local s = pick("lean_year")
	eq(s.quota, 3200)
	local g = pick("gamble")
	eq(g.quota, 6000)
	near(g.rewardMult, 2.0)
end)

test("rewardMult: multiplies future rewards", function()
	local s = pick("crunch")
	near(s.rewardMult, 1.5)
	s.progress = s.quota
	local _, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(find(intents, "cash").amount, 2000000 * 2 * 1.5 // 1)
end)

test("roundMonths +6 extends the deadline", function()
	local s = choosing({ "extension", "venture", "lean_year" })
	local old = s.roundEndTime
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	eq(s.roundEndTime, old + 6 * MD)
end)

test("roundMonths -6 shortens, floored at now + 3 months", function()
	local s = choosing({ "crunch", "venture", "lean_year" })
	local old = s.roundEndTime
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	eq(s.roundEndTime, old - 6 * MD)

	-- picked late: 20 of 24 months gone -> floor at now + 3
	s = choosing({ "crunch", "venture", "lean_year" })
	local now = s.roundStartTime + 20 * MD
	logic.pickCard(s, { index = 1, gameTime = now })
	eq(s.roundEndTime, now + 3 * MD)

	-- picked very late (2 months left): a cut never extends the round
	s = choosing({ "crunch", "venture", "lean_year" })
	old = s.roundEndTime
	logic.pickCard(s, { index = 1, gameTime = old - 2 * MD })
	eq(s.roundEndTime, old)
end)

test("vehicleMod: aggregated 1 + sum(v-1), rev bumped, vehicleMods intent", function()
	local s, intents = pick("express")
	near(s.fx.vehicleMods.TopSpeed, 1.15)
	eq(s.fx.vehicleModsRev, 1)
	ok(find(intents, "vehicleMods"))
	-- second card stacks additively
	s.offer = { "overdrive", "venture", "lean_year" }
	s.phase = "choosing"
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	near(s.fx.vehicleMods.TopSpeed, 1.45)
	near(s.fx.vehicleMods.Pollution, 2.0)
	near(s.fx.vehicleMods.Noise, 1.5)
	eq(s.fx.vehicleModsRev, 2)
	local l = pick("luxury")
	near(l.fx.vehicleMods.Comfort, 1.3)
end)

test("vehicleMod: capped at VEHICLE_MOD_CAP", function()
	local s = choosing({ "overdrive", "venture", "lean_year" })
	for _ = 1, 6 do
		s.phase = "choosing"
		s.offer = { "overdrive", "venture", "lean_year" }
		logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	end
	eq(s.fx.vehicleMods.TopSpeed, config.VEHICLE_MOD_CAP)
	eq(s.fx.vehicleMods.Pollution, config.VEHICLE_MOD_CAP)
	eq(s.fx.vehicleMods.Noise, config.VEHICLE_MOD_CAP)
end)

test("industryProd: intent with count / nil = all, and mult", function()
	local _, intents = pick("boomtown")
	local it = find(intents, "industryMods")
	eq(it.industryCount, 3)
	eq(it.mult, 1.5)
	local s2, i2 = pick("industrial_policy")
	it = find(i2, "industryMods")
	eq(it.industryCount, nil)
	eq(it.mult, 1.15)
	eq(find(i2, "cash").amount, -6000000)
	eq(s2.fx.industryMods, {}) -- logic never picks entities; quota_effects does
end)

test("every card resolves without warnings", function()
	-- This logic has no rules module (MVP): rule cards are never offered and warn when forced;
	-- test_logic_v2.lua covers them with rules injected.
	for _, c in ipairs(cards.list) do
		local hasRule = false
		for _, e in ipairs(c.effects) do if e.kind == "rule" then hasRule = true end end
		if hasRule then goto continue end
		local s, intents = pick(c.id)
		eq(s.phase, "running", c.id)
		eq(warned(intents), false, c.id)
		eq(s.picked[#s.picked], c.id)
		::continue::
	end
end)

-- QuotaRun.continueSandbox -------------------------------------------------------

test("continueSandbox: ENDED -> SANDBOX with resume", function()
	local s = activate(0)
	s.nextMonthTick = FAR
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.phase, "ended")
	local _, intents = logic.continueSandbox(s, {})
	eq(s.phase, "sandbox")
	ok(find(intents, "resume"))
end)

test("continueSandbox rejected in every non-ended phase", function()
	for _, ph in ipairs({ "running", "choosing", "sandbox" }) do
		local s = activate(0)
		s.phase = ph
		local before = logic.dump(s)
		local _, intents = logic.continueSandbox(s, {})
		eq(logic.dump(s), before, ph)
		ok(warned(intents, "continueSandbox ignored"), ph)
	end
end)

-- QuotaRun.debug ------------------------------------------------------------------

test("debug endRound: deadline = now; next tick ends the round", function()
	local s = activate(0)
	s.nextMonthTick = FAR
	logic.debug(s, { op = "endRound", gameTime = 777 })
	eq(s.roundEndTime, 777)
	logic.tick(s, { gameTime = 777, balance = 1 })
	eq(s.phase, "ended")
end)

test("debug addProgress {n}", function()
	local s = activate(0)
	logic.debug(s, { op = "addProgress", n = 300, gameTime = 0 })
	eq(s.progress, 300)
	logic.debug(s, { op = "addProgress", n = -1000, gameTime = 0 })
	eq(s.progress, 0)
	local _, intents = logic.debug(s, { op = "addProgress", gameTime = 0 })
	ok(warned(intents, "missing n"))
end)

test("debug setMonthsLeft {n}", function()
	local s = activate(0)
	logic.debug(s, { op = "setMonthsLeft", n = 2, gameTime = 5000 })
	eq(s.roundEndTime, 7000)
	local _, intents = logic.debug(s, { op = "setMonthsLeft", gameTime = 0 })
	ok(warned(intents, "missing n"))
	eq(s.roundEndTime, 7000)
end)

test("debug bankrupt: redMonths = 5; next red month tick ends the run", function()
	local s = activate(0)
	logic.debug(s, { op = "bankrupt", gameTime = 0 })
	eq(s.redMonths, 5)
	logic.tick(s, { gameTime = MD, balance = -1 })
	eq(s.phase, "ended")
	eq(s.endReason, "bankrupt")
end)

test("debug offer: force CHOOSING with an offer and pause", function()
	local s = activate(0)
	local _, intents = logic.debug(s, { op = "offer", gameTime = 0 })
	eq(s.phase, "choosing")
	eq(#s.offer, 3)
	eq(s.round, 1)
	ok(find(intents, "pause"))
	s.phase = "ended"
	s.offer = nil
	_, intents = logic.debug(s, { op = "offer", gameTime = 0 })
	eq(s.phase, "ended")
	ok(warned(intents, "offer ignored"))
end)

test("debug dump: logs the state", function()
	local s = activate(0)
	local _, intents = logic.debug(s, { op = "dump" })
	local l = find(intents, "log")
	ok(l.message:find("dump: {", 1, true))
	ok(l.message:find("phase=\"running\"", 1, true))
end)

test("debug works in every active phase; unknown op warns", function()
	for _, ph in ipairs(PHASES) do
		local s = activate(0)
		s.phase = ph
		logic.debug(s, { op = "addProgress", n = 1, gameTime = 0 })
		eq(s.progress, 1, ph)
	end
	local _, intents = logic.debug(activate(0), { op = "explode", gameTime = 0 })
	ok(warned(intents, "unknown op"))
end)

test("debug ops ignored when DEBUG == false", function()
	config.DEBUG = false
	for _, op in ipairs({ "endRound", "addProgress", "setMonthsLeft", "bankrupt", "offer", "dump",
		"passRound", "failRound", "skipMonths", "applyCard", "addMoney", "addQuotaPct", "clearEffects", "reset", "forceStart" }) do
		local s = activate(0)
		local before = logic.dump(s)
		local _, intents = logic.debug(s, { op = op, n = 3, id = "venture", gameTime = 50, balance = -1 })
		eq(logic.dump(s), before, op)
		ok(warned(intents, "DEBUG is off"), op)
		eq(#intents, 1)
	end
end)
