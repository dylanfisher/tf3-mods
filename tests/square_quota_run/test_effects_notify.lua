-- notify/quota_notification.script.tl: every key the logic emits renders a title and a
-- description with all placeholders filled (PLAN §6 Phase 2, notifications).

stub_module("::/scripts/lang_util.tl", {
	-- like string_util.format: "{name}" -> values.name (BT/scripts/lang_util.d.tl:4)
	format = function(s, values)
		return (s:gsub("{(%w+)}", function(k)
			local v = values[k]
			if v == nil then error("missing placeholder value " .. k) end
			return v
		end))
	end,
	formatInt = function(i)
		assert(math.type(i) == "integer", "formatInt needs an integer")
		return tostring(i)
	end,
})
-- v2.1 addendum: fake engine lookups for rule-target names (gui/quota_target_names.tl):
-- town entities 7 / 8 exist, cargo type 3 is Coal, ids >= 50 make the cargo repository raise.
local TOWNS = { [7] = "Springfield", [8] = "" }
local CARGO = { [3] = { name = "Coal" } }
set_global("api", {
	util = { formatMoney = function(m)
		assert(math.type(m) == "integer", "formatMoney needs an integer")
		return "$" .. m
	end },
	engine = {
		entityExists = function(e) return TOWNS[e] ~= nil end,
		util = { getEntityName = function(e)
			assert(math.type(e) == "integer", "entity must be an integer")
			return TOWNS[e]
		end },
	},
	res = { cargoTypeRep = { get = function(id)
		if id >= 50 then error("invalid cargo type id " .. id) end
		return CARGO[id]
	end } },
})

-- v2: fixed rule/boss data (the notification script reads byId[id].name / .description only).
local function dataModule(list)
	local byId = {}
	for _, e in ipairs(list) do byId[e.id] = e end
	return { list = list, byId = byId, get = function(id) return byId[id] end }
end
stub_module("/quota/quota_rules.tl", dataModule({
	{ id = "freight_only", name = "Freight Only", description = "Cargo counts triple, passengers not at all." },
	{ id = "local_hero", name = "Local Hero", description = "Deliveries into one town count x4.", target = "town" },
	{ id = "specialist", name = "Specialist", description = "One cargo type counts x10.", target = "cargoType" },
}))
stub_module("/quota/quota_bosses.tl", dataModule({
	{ id = "inspector", name = "The Inspector", description = "All vehicles run at 75% top speed." },
	{ id = "recession", name = "Recession", description = "Ticket income x0.6" },
}))

local notification = ug_require "/quota/notify/quota_notification.script.tl"
local config = ug_require "/quota/quota_config.tl"
local cards = ug_require "/quota/quota_cards.tl"
local logic = ug_require "/quota/quota_logic.tl".new(config, cards)

local function render(params)
	local d = notification.useDataState(params)
	ok(type(d.title) == "string" and #d.title > 0, "title")
	ok(type(d.description) == "string", "description")
	ok(type(d.icon) == "string" and d.icon:find("^::/game_mechanics/notifications/gui/icons/"), "icon")
	ok(not d.title:find("[{}?]"), "unfilled title: " .. d.title)
	ok(not d.description:find("[{}?]"), "unfilled description: " .. d.description)
	return d
end

test("every notify key renders with the params the logic emits", function()
	eq(render({ key = "roundStart", round = 1, quota = 2500, months = 36 }).title, "Round 1 started")
	local d = render({ key = "roundCleared", round = 2, reward = 4000000, progress = 4100, quota = 4000 })
	ok(d.description:find("$4000000", 1, true))
	ok(d.description:find("4100 of 4000", 1, true))
	render({ key = "halfway", round = 3, progress = 100, quota = 6400, months = 12 })
	ok(render({ key = "bankruptWarn", redMonths = 3, monthsLeft = 3 }).description:find("3 months", 1, true))
	ok(render({ key = "runOver", reason = "bankrupt", rounds = 4, total = 12345 }).description:find("bankrupt", 1, true))
	ok(render({ key = "runOver", reason = "quota", rounds = 0, total = 7 }).description:find("quota was missed", 1, true))
end)

test("float params (after a save/load round trip) still format as integers", function()
	local d = render({ key = "roundCleared", round = 2.0, reward = 4000000.0, progress = 4100.0, quota = 4000.0 })
	ok(d.title == "Round 2 cleared", d.title)
end)

test("unknown key or nil params fall back to a generic notification", function()
	eq(notification.useDataState({ key = "nope" }).title, "Quota Run")
	eq(notification.useDataState(nil).title, "Quota Run")
end)

test("keys emitted by quota_logic all have dedicated texts (driven through the real logic)", function()
	local seen = {}
	local function collect(intents)
		for _, it in ipairs(intents) do
			if it.kind == "notify" then
				local p = { key = it.key }
				for k, v in pairs(it.params) do p[k] = v end
				local d = render(p)
				ok(d.title ~= "Quota Run", "no dedicated text for " .. it.key)
				seen[it.key] = true
			end
		end
	end
	local s, intents = logic.activate(nil, { gameTime = 0, seed = 1, monthDuration = 1000 })
	collect(intents)
	-- bankruptcy warning (3 red months), halfway (behind), then a cleared round
	s, intents = logic.tick(s, { gameTime = 3 * 1000, balance = -1 })
	collect(intents)
	s, intents = logic.tick(s, { gameTime = s.roundStartTime + (s.roundEndTime - s.roundStartTime) // 2 + 1, balance = 1 })
	collect(intents)
	s.progress = s.quota
	s, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	collect(intents)
	-- fail the next round
	s.phase = "running"
	s, intents = logic.tick(s, { gameTime = s.roundEndTime, balance = 1 })
	collect(intents)
	eq(seen, { roundStart = true, halfway = true, bankruptWarn = true, roundCleared = true, runOver = true })
end)

-- v2: roundStart names the boss, the rule and next round's boss --------------------------

test("v2: roundStart without rule/boss/nextBoss keeps the v1 text", function()
	local d = render({ key = "roundStart", round = 2, quota = 4000, months = 24 })
	eq(d.title, "Round 2 started")
	eq(d.description, "Move 4000 units within 24 months.")
end)

test("v2: boss round roundStart names the boss and its rule", function()
	local d = render({ key = "roundStart", round = 3, quota = 6400, months = 24,
		boss = "inspector", rule = "freight_only" })
	eq(d.title, "Boss round 3 started")
	eq(d.description, "Move 6400 units within 24 months."
		.. " Boss round: The Inspector - All vehicles run at 75% top speed."
		.. " Scoring rule: Freight Only - Cargo counts triple, passengers not at all.")
end)

test("v2: roundStart announces next round's boss", function()
	local d = render({ key = "roundStart", round = 2, quota = 4000, months = 24, nextBoss = "recession" })
	eq(d.title, "Round 2 started")
	ok(d.description:find("Next round's boss: Recession - Ticket income x0.6.", 1, true), d.description)
end)

test("v2: rule only (round-modifier card) is named; unknown ids are skipped", function()
	local d = render({ key = "roundStart", round = 4, quota = 9000, months = 24, rule = "freight_only",
		boss = "no_such_boss", nextBoss = 7 })
	eq(d.title, "Round 4 started")
	eq(d.description, "Move 9000 units within 24 months. Scoring rule: Freight Only - Cargo counts triple, passengers not at all.")
end)

-- v2.1 addendum: roundStart names the rule target (town / cargo type) -----------------------

test("v2.1: local_hero roundStart names the target town", function()
	local d = render({ key = "roundStart", round = 2, quota = 4000, months = 24, rule = "local_hero", ruleTarget = 7 })
	eq(d.description, "Move 4000 units within 24 months."
		.. " Scoring rule: Local Hero - Deliveries into one town count x4."
		.. " Target town: Springfield. Only deliveries into it count.")
end)

test("v2.1: specialist roundStart names the target cargo; float id after save/load", function()
	local d = render({ key = "roundStart", round = 3, quota = 6400, months = 24, boss = "inspector",
		rule = "specialist", ruleTarget = 3.0 })
	eq(d.title, "Boss round 3 started")
	ok(d.description:find(" Scoring rule: Specialist - One cargo type counts x10. Target cargo: Coal.", 1, true), d.description)
end)

test("v2.1: unresolvable target (deleted town, empty name, engine error, bad types) is skipped", function()
	local base = "Move 4000 units within 24 months. Scoring rule: Local Hero - Deliveries into one town count x4."
	for _, target in ipairs({ 99, 8, "7", true }) do
		eq(render({ key = "roundStart", round = 2, quota = 4000, months = 24, rule = "local_hero", ruleTarget = target }).description,
			base, tostring(target))
	end
	eq(render({ key = "roundStart", round = 2, quota = 4000, months = 24, rule = "local_hero" }).description, base)
	local d = render({ key = "roundStart", round = 2, quota = 4000, months = 24, rule = "specialist", ruleTarget = 77 })
	eq(d.description, "Move 4000 units within 24 months. Scoring rule: Specialist - One cargo type counts x10.")
	-- a target on a rule without a target kind is ignored
	d = render({ key = "roundStart", round = 2, quota = 4000, months = 24, rule = "freight_only", ruleTarget = 7 })
	eq(d.description, "Move 4000 units within 24 months. Scoring rule: Freight Only - Cargo counts triple, passengers not at all.")
end)
