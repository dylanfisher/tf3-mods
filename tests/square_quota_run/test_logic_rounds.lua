-- quota_logic.tick: every §3 transition, month-tick catch-up, bankruptcy, halfway (PLAN §3, §3.1, §5.2).

local config = ug_require "/quota/quota_config.tl"
local logic = ug_require("/quota/quota_logic.tl").new(config, ug_require "/quota/quota_cards.tl")

local MD = 1000
local FAR = 1000000000

local function activate(t)
	return (logic.activate(nil, { gameTime = t or 0, seed = 42, monthDuration = MD, statsTotal = 0 }))
end

local function find(intents, kind, key)
	for _, it in ipairs(intents) do
		if it.kind == kind and (key == nil or it.key == key) then return it end
	end
end

local function count(intents, kind, key)
	local n = 0
	for _, it in ipairs(intents) do
		if it.kind == kind and (key == nil or it.key == key) then n = n + 1 end
	end
	return n
end

local function logs(intents)
	local out = {}
	for _, it in ipairs(intents) do if it.kind == "log" then out[#out + 1] = it.message end end
	return table.concat(out, "\n")
end

before_each(function()
	config.DEBUG = true
	config.METRIC = "events"
end)

test("RUNNING: nothing due -> no intents, state unchanged", function()
	local s = activate(0)
	local before = logic.dump(s)
	local s2, intents = logic.tick(s, { gameTime = 10, balance = 100 })
	ok(s2 == s)
	eq(intents, {})
	eq(logic.dump(s), before)
end)

test("RUNNING -> CHOOSING: quota met at deadline; next round starts AT the deadline", function()
	local s = activate(0)
	s.nextMonthTick = FAR -- isolate the round end from month ticks
	s.progress = s.quota
	local deadline = s.roundEndTime
	local now = deadline + 250 -- tick arrives a bit late
	local _, intents = logic.tick(s, { gameTime = now, balance = 1, statsTotal = 555 })
	eq(s.phase, "choosing")
	eq(s.round, 2)
	eq(s.roundsCleared, 1)
	eq(s.roundStartTime, deadline)
	eq(s.roundEndTime, deadline + config.ROUND_MONTHS * MD)
	eq(s.progress, 0)
	eq(s.totalTransported, 2500)
	eq(s.statsBaseline, 555)
	eq(s.quotaMultRound, 1.0)
	eq(s.quota, 4000)
	eq(s.halfwayWarned, false)
	eq(#s.offer, 3)
	eq(s.lastReward, 2000000)
	eq(find(intents, "cash").amount, 2000000)
	eq(find(intents, "notify", "roundCleared").params, { round = 1, reward = 2000000, progress = 2500, quota = 2500 })
	ok(find(intents, "pause"))
	eq(count(intents, "clearEffects"), 0)
	ok(logs(intents):find("phase running -> choosing", 1, true))
	-- order: cash before pause
	local iCash, iPause
	for i, it in ipairs(intents) do
		if it.kind == "cash" then iCash = i elseif it.kind == "pause" then iPause = i end
	end
	ok(iCash < iPause)
end)

test("reward bonus at 150% and rewardMult", function()
	local s = activate(0)
	s.nextMonthTick = FAR
	s.rewardMult = 2.0
	s.progress = 3750 -- 150% of 2500
	local _, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(find(intents, "cash").amount, 6000000)
end)

test("RUNNING -> ENDED: quota missed at deadline (clearEffects, pause, runOver)", function()
	local s = activate(0)
	s.nextMonthTick = FAR
	s.progress = s.quota - 1
	local _, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.phase, "ended")
	eq(s.endReason, "quota")
	eq(s.offer, nil)
	eq(s.round, 1)
	eq(s.totalTransported, 2499)
	ok(find(intents, "clearEffects"))
	ok(find(intents, "pause"))
	eq(find(intents, "notify", "runOver").params, { reason = "quota", rounds = 0, total = 2499 })
	eq(count(intents, "cash"), 0)
	ok(logs(intents):find("phase running -> ended", 1, true))
end)

test("ENDED and SANDBOX: tick does nothing", function()
	for _, ph in ipairs({ "ended", "sandbox" }) do
		local s = activate(0)
		s.phase = ph
		local before = logic.dump(s)
		local _, intents = logic.tick(s, { gameTime = FAR, balance = -1 })
		eq(intents, {})
		eq(logic.dump(s), before)
	end
end)

test("CHOOSING: round clock keeps running; deadline in choosing ends or re-offers", function()
	-- fail while choosing
	local s = activate(0)
	s.nextMonthTick = FAR
	s.phase = "choosing"
	s.offer = { "venture", "express", "gamble" }
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.phase, "ended")
	eq(s.offer, nil)
	-- pass while choosing: new offer replaces the old one
	s = activate(0)
	s.nextMonthTick = FAR
	s.phase = "choosing"
	s.offer = { "venture", "express", "gamble" }
	s.progress = s.quota
	local _, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.phase, "choosing")
	eq(s.round, 2)
	eq(#s.offer, 3)
	ok(find(intents, "pause"))
	ok(logs(intents):find("forfeited", 1, true))
end)

test("month tick: logs progress/stats/balance/redMonths and schedules the next tick", function()
	local s = activate(0)
	s.progress = 12
	local _, intents = logic.tick(s, { gameTime = MD, balance = 500, statsTotal = 30 })
	eq(s.nextMonthTick, 2 * MD)
	eq(s.redMonths, 0)
	local l = logs(intents)
	ok(l:find("month 1: round=1 progress=12/2500 statsDelta=30 balance=500 redMonths=0", 1, true), l)
end)

test("month ticks catch up when several elapsed since the last update", function()
	local s = activate(0)
	local _, intents = logic.tick(s, { gameTime = 5 * MD + 10, balance = -1 })
	eq(s.nextMonthTick, 6 * MD)
	eq(s.redMonths, 5)
	local l = logs(intents)
	for m = 1, 5 do ok(l:find("month " .. m .. ":", 1, true), "month " .. m) end
	eq(s.phase, "running")
end)

test("catch-up processes month ticks and multiple round ends in time order", function()
	local s = activate(0)
	s.progress = FAR -- clears round 1
	-- jump past round 1 (36 months) and round 2 (24 months) deadlines
	local _, intents = logic.tick(s, { gameTime = 61 * MD, balance = 1 })
	-- round 1 cleared at 36*MD -> round 2 [36, 60) with progress 0 -> fails at 60*MD
	eq(s.phase, "ended")
	eq(s.endReason, "quota")
	eq(s.round, 2)
	eq(s.roundsCleared, 1)
	eq(s.roundStartTime, 36 * MD)
	eq(s.nextMonthTick, 61 * MD) -- month ticks up to 60 processed before the round-2 end
	eq(count(intents, "notify", "roundCleared"), 1)
	eq(count(intents, "notify", "runOver"), 1)
end)

test("bankruptcy: increments when red, resets when not, skipped when balance nil", function()
	local s = activate(0)
	logic.tick(s, { gameTime = 1 * MD, balance = -1 })
	logic.tick(s, { gameTime = 2 * MD, balance = -1 })
	eq(s.redMonths, 2)
	logic.tick(s, { gameTime = 3 * MD, balance = nil })
	eq(s.redMonths, 2)
	logic.tick(s, { gameTime = 4 * MD, balance = 0 })
	eq(s.redMonths, 0)
end)

test("bankruptcy: warning at 3 red months, run ends at 6", function()
	local s = activate(0)
	local all = {}
	for m = 1, 6 do
		local _, intents = logic.tick(s, { gameTime = m * MD, balance = -100 })
		for _, it in ipairs(intents) do all[#all + 1] = it end
		if m < 6 then eq(s.phase, "running") end
	end
	eq(count(all, "notify", "bankruptWarn"), 1)
	eq(find(all, "notify", "bankruptWarn").params, { redMonths = 3, monthsLeft = 3 })
	eq(s.phase, "ended")
	eq(s.endReason, "bankrupt")
	eq(s.redMonths, 6)
	ok(find(all, "clearEffects"))
	eq(find(all, "notify", "runOver").params.reason, "bankrupt")
end)

test("bankruptcy also counts during CHOOSING", function()
	local s = activate(0)
	s.phase = "choosing"
	s.offer = { "venture", "express", "gamble" }
	s.redMonths = 5
	logic.tick(s, { gameTime = MD, balance = -1 })
	eq(s.phase, "ended")
	eq(s.endReason, "bankrupt")
	eq(s.offer, nil)
end)

test("halfway: notify once when below 50% at half time; none when on track", function()
	local s = activate(0)
	s.nextMonthTick = FAR
	local half = (s.roundEndTime - s.roundStartTime) // 2
	local _, i1 = logic.tick(s, { gameTime = half - 1, balance = 1 })
	eq(count(i1, "notify", "halfway"), 0)
	local _, i2 = logic.tick(s, { gameTime = half, balance = 1 })
	eq(find(i2, "notify", "halfway").params, { round = 1, progress = 0, quota = 2500, months = 18 })
	local _, i3 = logic.tick(s, { gameTime = half + 5, balance = 1 })
	eq(count(i3, "notify", "halfway"), 0)

	local t = activate(0)
	t.nextMonthTick = FAR
	t.progress = 1250
	local _, i4 = logic.tick(t, { gameTime = half, balance = 1 })
	eq(count(i4, "notify", "halfway"), 0)
	eq(t.halfwayWarned, true)
end)

test("round 3 quota after two clears grows by GROWTH^2", function()
	local s = activate(0)
	s.nextMonthTick = FAR
	s.progress = 1000000
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	logic.pickCard(s, { index = 1, gameTime = s.roundStartTime })
	s.quotaMultRound, s.quotaMultAll, s.rewardMult = 1.0, 1.0, 1.0
	s.quota = logic.computeQuota(s, s.round)
	s.progress = 1000000
	logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	eq(s.round, 3)
	eq(s.roundsCleared, 2)
	eq(s.quota, 6400)
end)
