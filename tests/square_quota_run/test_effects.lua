-- quota_effects.tl Phase 2 (PLAN §6 Phase 2): vehicle ChangeModifier scans, industry
-- productivity composition, clearEffects, notifications. Fake `api` world below; the fake
-- cmd table has no makeVehicleSetModifiersCmd, so any raw vehicle-modifier call would error.

local MD = 1000
local PLAYER = 2

local W -- fake world for the current test
local util_calls

local function installApi()
	W = {
		entities = {},       -- entity -> true
		vehicles = {},       -- ordered list of {entity, owner}
		industries = {},     -- ordered list of industry entities
		industry = {},       -- industry entity -> stockList entity
		productivity = {},   -- stock-list entity -> current productivity (nil = no STOCK_LIST)
		boosted = {},        -- stock-list entity -> true when the base worker boost applies
		boost = {},          -- stock-list entity -> boost factor
		sent = {},
		filters = nil,
	}
	local CT = { TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE", INDUSTRY = "INDUSTRY", STOCK_LIST = "STOCK_LIST",
		GAME_SPEED = "GAME_SPEED" }
	set_global("api", {
		type = {
			ComponentType = CT,
			StockList = { Modifiers = { new = function() return { productivity = 1.0 } end } },
		},
		engine = {
			entityExists = function(e) return W.entities[e] == true end,
			getEntitiesWithComponent = function(ct, filters)
				local out = {}
				if ct == CT.TRANSPORT_VEHICLE then
					W.filters = filters
					for _, v in ipairs(W.vehicles) do
						if W.entities[v[1]] and (filters == nil or filters.requireOwnedByPlayer == nil
							or filters.requireOwnedByPlayer == v[2]) then
							out[#out + 1] = v[1]
						end
					end
				elseif ct == CT.INDUSTRY then
					for _, e in ipairs(W.industries) do if W.entities[e] then out[#out + 1] = e end end
				end
				return out
			end,
			getComponent = function(e, ct)
				if not W.entities[e] then return nil end
				if ct == CT.INDUSTRY and W.industry[e] then return { stockList = W.industry[e] } end
				if ct == CT.STOCK_LIST and W.productivity[e] then
					return { modifiers = { productivity = W.productivity[e] } }
				end
				return nil
			end,
			util = { getPlayer = function() return PLAYER end },
		},
		cmd = {
			sendCommand = function(cmd)
				W.sent[#W.sent + 1] = cmd
				if cmd.kind == "stock" then W.productivity[cmd.entity] = cmd.modifiers.productivity end
			end,
			makeScriptingSendEventCmd = function(src, id, name, param)
				return { kind = "event", src = src, id = id, name = name, param = param }
			end,
			makeStockListSetModifiersCmd = function(e, mods)
				return { kind = "stock", entity = e, modifiers = { productivity = mods.productivity } }
			end,
		},
		util = { getDefaultMonthDuration = function() return MD end },
	})
end

stub_module("::/industries/industry_productivity_util.tl", {
	isIndustryWorkersBoosted = function(e)
		util_calls[#util_calls + 1] = "boosted:" .. tostring(e)
		return W.boosted[e] == true
	end,
	getPersonCapacityPotentialBoost = function(e)
		util_calls[#util_calls + 1] = "boost:" .. tostring(e)
		return W.boost[e] or 2.0
	end,
})

local effects = ug_require "/quota/quota_effects.tl"
local config = ug_require "/quota/quota_config.tl"
local cards = ug_require "/quota/quota_cards.tl"
local logic = ug_require "/quota/quota_logic.tl".new(config, cards)

local function addVehicle(e, owner)
	W.entities[e] = true
	W.vehicles[#W.vehicles + 1] = { e, owner or PLAYER }
end

local function addIndustry(e, stockList, productivity)
	W.entities[e] = true
	W.entities[stockList] = true
	W.industries[#W.industries + 1] = e
	W.industry[e] = stockList
	W.productivity[stockList] = productivity or 1.0
end

local function newState(seed)
	return {
		active = true, phase = "running", rngSeed = seed or 12345, round = 1, monthDuration = MD,
		fx = { vehicleMods = {}, vehicleModsRev = 0, vehicleApplied = {}, industryMods = {}, nextScanTime = 0 },
	}
end

--- Simulate a vehicle card as quota_logic applies it (fx updated + rev bumped), then the intent.
local function vehicleCard(s, mods)
	for k, v in pairs(mods) do s.fx.vehicleMods[k] = (s.fx.vehicleMods[k] or 1.0) + (v - 1) end
	s.fx.vehicleModsRev = s.fx.vehicleModsRev + 1
	effects.run(s, { { kind = "vehicleMods" } })
end

local function events(name)
	local out = {}
	for _, c in ipairs(W.sent) do
		if c.kind == "event" and (name == nil or c.name == name) then out[#out + 1] = c end
	end
	return out
end

local function changeFor(e)
	local out = {}
	for _, c in ipairs(events("ChangeModifier")) do
		if c.param.entity == e then out[#out + 1] = c.param.modifications end
	end
	return out
end

local function stockCmds()
	local out = {}
	for _, c in ipairs(W.sent) do if c.kind == "stock" then out[c.entity] = c.modifiers.productivity end end
	return out
end

local function countStock()
	local n = 0
	for _, c in ipairs(W.sent) do if c.kind == "stock" then n = n + 1 end end
	return n
end

before_each(function()
	installApi()
	util_calls = {}
	clear_logs()
end)

-- vehicles --------------------------------------------------------------------------------------

test("vehicleMods intent: ChangeModifier event per player vehicle with our single id", function()
	addVehicle(101); addVehicle(102); addVehicle(150, 9) -- 150 belongs to another company
	local s = newState()
	vehicleCard(s, { TopSpeed = 1.15 })
	local evs = events()
	eq(#evs, 2)
	for _, c in ipairs(evs) do
		eq(c.src, "")
		eq(c.id, "VehicleModifier")
		eq(c.name, "ChangeModifier")
		eq(c.param.id, "square_quota_run")
		eq(c.param.modifications, { TopSpeed = 1.15 })
	end
	eq(W.filters, { requireOwnedByPlayer = PLAYER })
	eq(s.fx.vehicleApplied, { [101] = 1, [102] = 1 })
	-- each event gets its own modifications table
	ok(evs[1].param.modifications ~= evs[2].param.modifications)
end)

test("vehicle scan: rev bookkeeping (only new vehicles, all on rev bump)", function()
	addVehicle(101); addVehicle(102)
	local s = newState()
	vehicleCard(s, { TopSpeed = 1.15 })
	W.sent = {}
	-- nothing changed: due scan sends nothing
	ok(effects.onUpdate(s, 0))
	eq(#events(), 0)
	-- a new vehicle is picked up by the next scan only
	addVehicle(103)
	ok(not effects.onUpdate(s, MD // 4 - 1), "not due yet")
	eq(#events(), 0)
	ok(effects.onUpdate(s, MD // 4))
	eq(#events(), 1)
	eq(changeFor(103), { { TopSpeed = 1.15 } })
	eq(s.fx.vehicleApplied[103], 1)
	-- second card: rev 2, aggregate 1 + sum(v - 1), everyone resent immediately
	W.sent = {}
	vehicleCard(s, { TopSpeed = 1.30, Pollution = 2.0, Noise = 1.5 })
	eq(#events(), 3)
	near(changeFor(101)[1].TopSpeed, 1.45, 1e-9)
	eq(changeFor(101)[1].Pollution, 2.0)
	eq(changeFor(101)[1].Noise, 1.5)
	eq(changeFor(101)[1].Comfort, nil)
	eq(s.fx.vehicleApplied, { [101] = 2, [102] = 2, [103] = 2 })
end)

test("vehicle scan: dead entities are dropped from vehicleApplied, never sent", function()
	addVehicle(101); addVehicle(102)
	local s = newState()
	vehicleCard(s, { Comfort = 1.3 })
	W.entities[102] = nil
	W.sent = {}
	s.fx.nextScanTime = 0
	ok(effects.onUpdate(s, 10))
	eq(s.fx.vehicleApplied, { [101] = 1 })
	eq(#events(), 0)
	-- a rev bump does not resurrect it
	vehicleCard(s, { Comfort = 1.1 })
	eq(#changeFor(102), 0)
	eq(#changeFor(101), 1)
end)

test("onUpdate: interval = monthDuration * SCAN_INTERVAL_FRACTION; idle runs never write state", function()
	addVehicle(101)
	local s = newState()
	-- idle: no effects yet -> no scan, no enumeration, no state change
	ok(not effects.onUpdate(s, 0))
	eq(s.fx.nextScanTime, 0)
	eq(W.filters, nil)
	vehicleCard(s, { TopSpeed = 1.15 })
	ok(effects.onUpdate(s, 500))
	eq(s.fx.nextScanTime, 500 + math.floor(MD * config.SCAN_INTERVAL_FRACTION))
	ok(not effects.onUpdate(s, 500 + 1))
end)

test("clearEffects (vehicles): {} to each applied live vehicle, then empty", function()
	addVehicle(101); addVehicle(102); addVehicle(103)
	local s = newState()
	vehicleCard(s, { TopSpeed = 1.15 })
	W.entities[103] = nil
	W.sent = {}
	effects.run(s, { { kind = "clearEffects" } })
	eq(changeFor(101), { {} })
	eq(changeFor(102), { {} })
	eq(#changeFor(103), 0)
	eq(s.fx.vehicleApplied, {})
	for _, c in ipairs(events()) do eq(c.param.id, "square_quota_run") end
end)

test("vehicle scan: neutral aggregate removes our entry and skips the fleet enumeration", function()
	addVehicle(101); addVehicle(102)
	local s = newState()
	vehicleCard(s, { TopSpeed = 1.15 })
	s.fx.vehicleMods = { TopSpeed = 1.0 }
	s.fx.vehicleModsRev = 2
	W.sent, W.filters = {}, nil
	effects.run(s, { { kind = "vehicleMods" } })
	eq(changeFor(101), { {} })
	eq(changeFor(102), { {} })
	eq(s.fx.vehicleApplied, {})
	eq(W.filters, nil)
end)

-- industries ------------------------------------------------------------------------------------

test("industry desired formula: unboosted = ours, boosted = boost * ours", function()
	addIndustry(201, 301, 1.0)  -- unboosted
	addIndustry(202, 302, 1.8)  -- boosted by the base workers (boost 1.8)
	W.boosted[302], W.boost[302] = true, 1.8
	local s = newState()
	effects.run(s, { { kind = "industryMods", mult = 1.5 } })
	eq(s.fx.industryMods, { [301] = 1.5, [302] = 1.5 })
	local cmds = stockCmds()
	near(cmds[301], 1.5)
	near(cmds[302], 2.7)
	-- the boost factor is only asked for boosted industries (same as the base script)
	for _, c in ipairs(util_calls) do ok(c ~= "boost:301", "boost asked for an unboosted industry") end
end)

test("industry scan: no command when within 0.001; re-asserts after a base reset", function()
	addIndustry(201, 301, 1.0)
	local s = newState()
	effects.run(s, { { kind = "industryMods", mult = 1.5 } })
	W.sent = {}
	ok(effects.onUpdate(s, 0))
	eq(countStock(), 0)
	W.productivity[301] = 1.5004
	s.fx.nextScanTime = 0
	effects.onUpdate(s, 0)
	eq(countStock(), 0)
	-- base worker script resets the unboosted industry to 1.0 -> next scan restores ours
	W.productivity[301] = 1.0
	s.fx.nextScanTime = 0
	effects.onUpdate(s, 0)
	near(stockCmds()[301], 1.5)
	-- workers arrive: base keeps 1.5 (it already looks "boosted"); scan composes boost * ours
	W.boosted[301], W.boost[301] = true, 2.0
	W.sent = {}
	s.fx.nextScanTime = 0
	effects.onUpdate(s, 0)
	near(stockCmds()[301], 3.0)
end)

test("industryMods: all industries (count nil), deduplicated; multiple cards multiply", function()
	addIndustry(201, 301); addIndustry(202, 302); addIndustry(203, 303)
	W.entities[204] = true; W.industries[#W.industries + 1] = 204; W.industry[204] = 301 -- shares 301
	local s = newState()
	local seed = s.rngSeed
	effects.run(s, { { kind = "industryMods", mult = 1.15 } })
	eq(s.rngSeed, seed, "'all' draws no random numbers")
	effects.run(s, { { kind = "industryMods", mult = 1.5 } })
	for _, e in ipairs({ 301, 302, 303 }) do
		near(s.fx.industryMods[e], 1.725)
		near(W.productivity[e], 1.725)
	end
	local n = 0
	for _ in pairs(s.fx.industryMods) do n = n + 1 end
	eq(n, 3)
end)

test("industryMods: N random industries are distinct and deterministic for a seed (state LCG)", function()
	for i = 1, 10 do addIndustry(200 + i, 300 + i) end
	local function pick(seed)
		local s = newState(seed)
		effects.run(s, { { kind = "industryMods", industryCount = 3, mult = 1.5 } })
		local chosen = {}
		for e in pairs(s.fx.industryMods) do chosen[#chosen + 1] = e end
		table.sort(chosen)
		return chosen, s.rngSeed
	end
	local a, seedA = pick(777)
	local b, seedB = pick(777)
	eq(#a, 3)
	eq(a, b)
	eq(seedA, seedB)
	ok(seedA ~= 777, "rngSeed advanced")
	-- reference: partial Fisher-Yates over the sorted stock lists with logic.rngNext
	local ref = newState(777)
	local list = {}
	for i = 1, 10 do list[i] = 300 + i end
	local expect = {}
	for i = 1, 3 do
		local j = i - 1 + logic.rngNext(ref, #list - i + 1)
		list[i], list[j] = list[j], list[i]
		expect[i] = list[i]
	end
	table.sort(expect)
	eq(a, expect)
	eq(ref.rngSeed, seedA)
	-- different seeds give different picks at least sometimes
	local differs = false
	for seed = 1, 20 do
		local c = pick(seed * 7919)
		if table.concat(c, ",") ~= table.concat(a, ",") then differs = true end
	end
	ok(differs)
	-- count >= number of industries means all of them
	local s = newState(5)
	effects.run(s, { { kind = "industryMods", industryCount = 50, mult = 1.5 } })
	local n = 0
	for _ in pairs(s.fx.industryMods) do n = n + 1 end
	eq(n, 10)
end)

test("industry scan: dead or stock-list-less entries are dropped", function()
	addIndustry(201, 301); addIndustry(202, 302)
	local s = newState()
	effects.run(s, { { kind = "industryMods", mult = 1.5 } })
	W.entities[301] = nil
	W.productivity[302] = nil
	W.sent = {}
	s.fx.nextScanTime = 0
	effects.onUpdate(s, 0)
	eq(s.fx.industryMods, {})
	eq(countStock(), 0)
end)

test("clearEffects (industries): back to the base value (boost or 1.0), then empty", function()
	addIndustry(201, 301); addIndustry(202, 302); addIndustry(203, 303)
	W.boosted[302], W.boost[302] = true, 1.7
	local s = newState()
	effects.run(s, { { kind = "industryMods", mult = 1.5 } })
	near(W.productivity[302], 2.55)
	W.entities[303] = nil
	W.sent = {}
	effects.run(s, { { kind = "clearEffects" } })
	local cmds = stockCmds()
	near(cmds[301], 1.0)
	near(cmds[302], 1.7)
	eq(cmds[303], nil)
	eq(s.fx.industryMods, {})
end)

test("effects tolerate a state without fx maps", function()
	local s = { active = true, phase = "running", rngSeed = 3, monthDuration = MD }
	ok(not effects.onUpdate(s, 0))
	effects.run(s, { { kind = "clearEffects" } })
	eq(s.fx.vehicleApplied, {})
	eq(s.fx.industryMods, {})
end)

-- notifications ---------------------------------------------------------------------------------

test("notify: Notifications/add with our type string, key merged into params", function()
	local s = newState()
	effects.run(s, { { kind = "notify", key = "roundCleared", params = { round = 2, reward = 4000000, progress = 9, quota = 8 } } })
	local evs = events("add")
	eq(#evs, 1)
	eq(evs[1].src, "")
	eq(evs[1].id, "Notifications")
	eq(evs[1].param.type, "square_quota_run::/quota/notify/quota_notification.script")
	eq(evs[1].param.params, { key = "roundCleared", round = 2, reward = 4000000, progress = 9, quota = 8 })
	eq(evs[1].param.autoDismissDuration, 60000)
end)

-- Phase 4: capped ChangeModifier fan-out ------------------------------------------------------

test("vehicle scan is capped at VEHICLE_SENDS_PER_FRAME and continues next frame", function()
	local old = config.VEHICLE_SENDS_PER_FRAME
	config.VEHICLE_SENDS_PER_FRAME = 4
	for e = 101, 110 do addVehicle(e) end
	local s = newState()
	vehicleCard(s, { TopSpeed = 1.15 })
	eq(#events("ChangeModifier"), 4)
	eq(s.fx.nextScanTime, 0, "capped intent makes the next scan due")
	ok(effects.onUpdate(s, 500))
	eq(#events("ChangeModifier"), 8)
	eq(s.fx.nextScanTime, 500, "still capped: continue next frame")
	ok(effects.onUpdate(s, 501))
	eq(#events("ChangeModifier"), 10)
	eq(s.fx.nextScanTime, 501 + math.floor(MD * config.SCAN_INTERVAL_FRACTION), "done: regular interval")
	for e = 101, 110 do eq(#changeFor(e), 1) end
	config.VEHICLE_SENDS_PER_FRAME = old
end)

test("clearEffects is capped too: neutral aggregate, removal continues via onUpdate", function()
	local old = config.VEHICLE_SENDS_PER_FRAME
	config.VEHICLE_SENDS_PER_FRAME = 3
	for e = 101, 107 do addVehicle(e) end
	local s = newState()
	vehicleCard(s, { TopSpeed = 1.15 }) -- 3 sent
	ok(effects.onUpdate(s, 0)); ok(effects.onUpdate(s, 0)) -- 7 applied
	eq(#events("ChangeModifier"), 7)
	W.sent = {}
	effects.run(s, { { kind = "clearEffects" } })
	eq(#events("ChangeModifier"), 3)
	eq(s.fx.vehicleMods, {})
	eq(s.fx.nextScanTime, 0)
	ok(effects.onUpdate(s, 10))
	ok(effects.onUpdate(s, 10))
	eq(#events("ChangeModifier"), 7)
	eq(s.fx.vehicleApplied, {})
	for e = 101, 107 do eq(changeFor(e), { {} }) end
	ok(not effects.onUpdate(s, 10), "idle after the clear")
	config.VEHICLE_SENDS_PER_FRAME = old
end)

test("industryMods logs a PERSON_CAPACITY probe for the first chosen stock list", function()
	addIndustry(201, 301)
	local s = newState()
	effects.run(s, { { kind = "industryMods", industryCount = 1, mult = 1.5 } })
	local found = false
	for _, e in ipairs(log_entries()) do
		if e.msg:find("industryMods probe: stockList 301 PERSON_CAPACITY=false", 1, true) then found = true end
	end
	ok(found)
end)
