-- Bridges and ships (round R6, 2026-10-13; ot_bridge shipCheck / plan, ot_driver shipStops): a low road bridge cuts a
-- ship lane (docs/findings/roads.md). A crossing over water a ship line uses gets a high deck (CLEARANCE over the water
-- level) or none; navigable-looking water (wide) a high deck when it fits; narrow water without ships the low deck.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local T = ug_require(F.DIR .. "ot_terrain.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local BR = ug_require(F.DIR .. "ot_bridge.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

-- a river along y = c, w m wide, flat banks (height h) rising gently
local function riverSampler(c, w, h)
	return T.sampler(function(x, y)
		local d = math.abs(y - c)
		if d < w / 2 then return -2 end
		return (h or 5) + math.min(d - w / 2, 400) * 0.005
	end)
end

local TPL = "::/infrastructure/street/town/town_new_small.street_template"
local function town(deY)
	local g = OG.new()
	local a = OG.addNode(g, nil, 0, 0, 5.5)
	local b = OG.addNode(g, nil, 0, deY or -80, 5.3)
	local c = OG.addNode(g, nil, 80, 0, 5.5)
	OG.addEdge(g, nil, a.id, b.id, "small")
	OG.addEdge(g, nil, a.id, c.id, "small")
	return g, b
end

test("shipCheck: a stop on the same river is a path; none far away; a capped fill with a stop near counts", function()
	local s = riverSampler(-200, 60)
	eq(BR.shipCheck(s, 0, -200, {}, {}), "none")
	local k, why = BR.shipCheck(s, 0, -200, { { x = 1500, y = -250, line = 7 } }, {})
	eq(k, "path")
	eq(why, "stop:7")
	local k2, why2 = BR.shipCheck(s, 0, -200, { { x = 40000, y = 40000, line = 8 } }, {})
	eq(k2, "none", tostring(why2))
	-- (the endless test river caps the fill: a harbour 3 km away on dry land counts as a path, the conservative side)
	local k3, why3 = BR.shipCheck(s, 0, -200, { { x = 0, y = 3000, line = 9 } }, {})
	eq(k3, "path")
	ok(why3:find("^cap:"), why3)
	-- one fill per water body (cached)
	local cache = {}
	local _, _, n1 = BR.shipCheck(s, 0, -200, { { x = 1500, y = -250, line = 7 } }, cache)
	local _, _, n2 = BR.shipCheck(s, 400, -200, { { x = 1500, y = -250, line = 7 } }, cache)
	ok(n1 > 0)
	eq(n2, 0, "the second crossing of the same river reads the cache")
end)

test("plan: narrow water without ships gets the low deck (ship=none)", function()
	local s = riverSampler(-200, 30)
	local g, b = town()
	local bp, why = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1 })
	ok(bp, tostring(why))
	eq(bp.ship, "none")
	ok(bp.deck <= 5 + 0.5 + BR.LIFT, "low deck " .. bp.deck)
end)

test("plan: wide water (navigable proxy) gets a high deck when it fits", function()
	local s = riverSampler(-200, 60)
	local g, b = town()
	local bp, why = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1 })
	ok(bp, tostring(why))
	eq(bp.ship, "navigable")
	ok(bp.clearance >= BR.CLEARANCE - 1e-6, "high: clearance " .. bp.clearance)
	-- too short an approach for the high deck: low (accepted over navigable water without ships)
	local g2, b2 = town(-110)
	local bp2 = BR.plan({ sampler = s, deadEnds = { { b2.x, b2.y, b2.id, 5.3, TPL } }, axis = 0, g = g2, seed = 1 })
	ok(bp2, "built low")
	print(string.format("      short approach %.0f m: deck %.1f clearance %.1f ship %s", bp2.approach, bp2.deck, bp2.clearance, bp2.ship))
	eq(bp2.ship, "navigable")
	ok(bp2.clearance < BR.CLEARANCE, "low over navigable water without ships")
end)

test("plan: an active ship path gets the high deck, or no bridge when its approaches don't fit", function()
	local s = riverSampler(-200, 60)
	local ships = { { x = 1500, y = -250, line = 3 } }
	local g, b = town()
	local bp, why = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1, ships = ships })
	ok(bp, tostring(why))
	eq(bp.ship, "path")
	ok(bp.clearance >= BR.CLEARANCE - 1e-6, "never low over a path: " .. bp.clearance)
	-- a dead end close to the water: the high deck's approach can't fit -> no bridge at all
	local g2, b2 = town(-110)
	local bp2, why2 = BR.plan({ sampler = s, deadEnds = { { b2.x, b2.y, b2.id, 5.3, TPL } }, axis = 0, g = g2, seed = 1, ships = ships })
	print("      short approach over a ship path: " .. tostring(bp2 and bp2.deck) .. " " .. tostring(why2))
	eq(bp2, nil, "never low over a path")
	ok(tostring(why2):find("shipPath:highNoFit", 1, true), tostring(why2))
	-- a raised water level lifts the deck with it
	local bp3 = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1, ships = ships,
		waterLevel = -1 })
	ok(bp3 == nil or bp3.deck >= -1 + BR.CLEARANCE - 1e-6)
end)

test("driver: shipStops reads the ship lines once per SHIP_REFRESH_S, SHIPS line, water level", function()
	local calls, logs = 0, {}
	local E = { nowUs = function() return 0 end,
		shipLines = function()
			calls = calls + 1
			return { { line = 5, stops = { { 10, 20 }, { 30, 40 } }, vehicles = 2 } }, 9
		end,
		waterLevel = function() return 0.5, "terrain" end }
	local d = D.new(E, "[T]")
	d.debug = function(_, what, f) logs[#logs + 1] = what .. " " .. f[1][1] .. "=" .. tostring(f[1][2]) end
	local stops, wl = d:shipStops(0)
	eq(#stops, 2)
	eq(stops[1].line, 5)
	eq(wl, 0.5)
	d:shipStops(1e6)
	eq(calls, 1, "cached")
	d:shipStops((D.SHIP_REFRESH_S + 1) * 1e6)
	eq(calls, 2)
	ok(logs[1]:find("SHIPS lines=1", 1, true), logs[1])
	-- an engine without the reads: no ships, water level 0
	local d2 = D.new({ nowUs = function() return 0 end }, "[T]")
	d2.debug = function() end
	local st2, wl2 = d2:shipStops(0)
	eq(#st2, 0)
	eq(wl2, 0)
end)

test("plan (2026-10-14): candidates best first, a refused crossing skipped, dry far streets, the lines for the obstacle test", function()
	local s = riverSampler(-200, 30)
	local g, b = town()
	local bp = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1 })
	ok(bp and bp.cands and #bp.cands >= 2, "several candidates")
	ok(bp.key ~= nil, "a key")
	for i = 2, #bp.cands do ok(bp.cands[i].key ~= bp.cands[1].key, "distinct") end
	local bp2 = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1,
		skip = { [bp.key] = true } })
	ok(bp2 and bp2.key ~= bp.key, "the refused one skipped")
	local ln = BR.lines(bp)
	-- (2026-10-14: CROSS_LATER, no cross street at the far end yet; a long approach bends once: 5 points)
	if BR.CROSS_LATER then
		eq(#ln, 1); eq(#ln[1], bp.bowed and 5 or 4)
	else
		eq(#ln, 2); eq(#ln[1], bp.bowed and 5 or 4); eq(#ln[2], 3)
	end
	-- a second channel beyond the far bank (the far street would cross it): every crossing toward it refused
	local two = T.sampler(function() return 5 end, function(_, y) return (y < -185 and y > -215) or (y < -320 and y > -340) end, 0)
	local bp3 = BR.plan({ sampler = two, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 1 })
	if bp3 then
		for _, c in ipairs(bp3.cands) do
			local L = BR.lines(c)
			ok(not T.wetAlong(two, { L[1][3], L[1][4] }, 0, 8), "far street dry")
		end
	end
	-- narrow water near but off the centre's rays: the origins around the centre find it
	local arm = T.sampler(function() return 5 end, function(x, y) return x > 300 and x < 340 and y > 200 and y < 700 end, 0)
	ok(#BR.narrowWater(arm, 0, 0) >= 1, "found")
end)

-- (2026-10-14, run 2026-10-14_0814_sqot: 9x "ERROR stage=snapshot ... ot_satellite.lua:240: attempt to index local
-- 'pts' (a nil value)": since CROSS_LATER a plan has one line only, BR.lines(c)[2] is nil, and the driver's obstacle test
-- passed it on. Now the driver skips the missing far cross street and clearOfObstacles takes nil / short polylines)
test("bridgeDecide (run 0814): a one-line plan through the obstacle test is planned, an obstacle on it refuses it", function()
	local function run(obstacles)
		local s = riverSampler(-200, 30)
		local g, b = town()
		local logs, obsCalls = {}, 0
		local E = { nowUs = function() return 0 end, name = function(t) return "Town" .. tostring(t) end,
			year = function() return 1900 end, bridgeType = function() return 4, "::/infrastructure/bridge/stone.bridge" end,
			sampler = function() return s end, closestTown = function() return 1 end,
			obstacles = function() obsCalls = obsCalls + 1; return obstacles end,
			log = function(l) logs[#logs + 1] = l end }
		local d = D.new(E, "[T]")
		d.debug = function() end
		local seed = nil
		for k = 1, 200 do
			if BR.eligible({ seed = k, buildings = 200, river = true }) then seed = k break end
		end
		ok(seed ~= nil, "an eligible seed")
		local st = d:townState(1)
		st.stats, st.narrow, st.pos = { water = { kind = "river", axis = 0 } }, {}, { 0, 0 }
		local pts = {}
		for i = 1, 200 do pts[i] = { 0, 0 } end
		local job = { town = 1, trigger = "demand", style = { seed = seed, year = 1900 }, pts = pts, ext = { cx = 0, cy = 0, r = 300 },
			sampler = s, g = g, joinInfo = { [b.id] = { template = TPL } }, edges = {} }
		local okR, err = pcall(d.bridgeDecide, d, job, 0, {})
		ok(okR, "no error: " .. tostring(err))
		return job, logs, obsCalls
	end
	-- nothing in the way: the first candidate, a single line (no far cross street yet), is planned
	local job, logs, n = run({ segs = {}, boxes = {} })
	ok(n >= 1, "the obstacle test ran")
	ok(job.bridgePlan ~= nil, "planned: " .. table.concat(logs, " | "))
	if BR.CROSS_LATER then eq(#BR.lines(job.bridgePlan), 1, "one line only") end
	ok(logs[#logs]:find("outcome=plan", 1, true), logs[#logs])
	-- a street across every candidate's approach (beyond the town's snapshot): all refused as obstacles, no error
	local job2, logs2 = run({ segs = { { -2000, -120, 2000, -120, id = 99999, kind = "street" } }, boxes = {} })
	eq(job2.bridgePlan, nil, "refused")
	ok(logs2[#logs2]:find("why=obstacle", 1, true), logs2[#logs2])
end)
