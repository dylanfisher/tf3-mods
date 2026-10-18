-- Round after the 0502 run (2026-10-14; NEXT_PHASE_BRIEF 44): the level weights' engine baseline, the mature hold, the
-- satellite core watch, the bridge's far bank, the district name reserve, the dev Simulate's fill skip, and the game
-- script's stop-name gate.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local UP = ug_require(F.DIR .. "ot_upward.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")
local SAT = ug_require(F.DIR .. "ot_satellite.lua")
local BR = ug_require(F.DIR .. "ot_bridge.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local H = ug_require(F.DIR .. "ot_hooks.lua")
local NM = ug_require(F.DIR .. "ot_names.lua")

---------------------------------------------------------------------------
-- 1. LEVELS vs the engine's own weights

test("level weights: sig / unsig round trip, owner engine / ours / player / none", function()
	local engine = { { 0.26, 0.11, 0, 0 }, { 0.26, 0.11, 0, 0 }, { 0.26, 0.11, 0, 0 } }
	local sig = UP.levelSig(engine)
	eq(sig, "0.26/0.11/0/0;0.26/0.11/0/0;0.26/0.11/0/0")
	eq(UP.levelSig(nil), "-")
	local back = UP.levelUnsig(sig)
	eq(back[2][1], 0.26)
	eq(UP.levelUnsig("-"), nil)
	eq(UP.levelUnsig("1/2/3"), nil, "malformed")
	-- float noise from the engine reads the same
	eq(UP.levelSig({ { 0.2600000012, 0.11, 0, 0 }, { 0.26, 0.11, 0, 0 }, { 0.26, 0.11, 0, 0 } }), sig)
	eq(UP.levelOwner("-", sig, 0), "none")
	eq(UP.levelOwner(sig, sig, 0), "engine")
	eq(UP.levelOwner(sig, nil, 0), "player", "no baseline (an old save): custom weights are the player's")
	local ours = UP.levelSig(UP.levelWeights(0.5))
	eq(UP.levelOwner(ours, sig, 0.5), "ours")
	eq(UP.levelOwner("1/1/1/1;1/1/1/1;1/1/1/1", sig, 0.5), "player", "changed and not ours")
	-- levelDecide: the engine's weights let LEVELS run; the player's never
	local base = { buildings = 400, pb = 3, mat = 1, on = true, nowUs = 1e9, town = 1, top = 2 }
	local function dec(o)
		local x = {}
		for k, v in pairs(base) do x[k] = v end
		for k, v in pairs(o) do x[k] = v end
		return UP.levelDecide(x)
	end
	eq(dec({ custom = true, owner = "engine" }), "set")
	eq(select(3, dec({ custom = true, owner = "player" })), "player")
	eq(select(3, dec({ custom = true, owner = "player", ours = 0.5 })), "player", "the player changed ours: left alone")
	eq(select(3, dec({ custom = true })), "player", "no owner read: custom and not ours, as before")
end)

test("level baseline saved once (lb / lbs), normalize keeps it, a second event is ignored", function()
	local s, ch = SV.applyLevelBase(nil, { towns = { { t = 5, c = "0.26/0.11/0/0;0.26/0.11/0/0;0.26/0.11/0/0" }, { t = 6, c = "-" } } })
	ok(ch)
	local lb = SV.levelBase(SV.normalize(s))
	eq(lb[5], "0.26/0.11/0/0;0.26/0.11/0/0;0.26/0.11/0/0")
	eq(lb[6], "-")
	local _, ch2 = SV.applyLevelBase(s, { towns = { { t = 5, c = "-" } } })
	ok(not ch2, "the first baseline stays")
	eq(SV.levelBase(nil), nil, "no baseline")
	local e, che = SV.applyLevelBase(nil, { towns = {} })
	ok(che)
	ok(SV.levelBase(e) ~= nil, "taken, even with no town")
	local _, bad = SV.applyLevelBase(nil, { towns = { { t = 1, c = string.rep("x", SV.LEVELSIG_MAX + 1) } } })
	ok(bad)
end)

---------------------------------------------------------------------------
-- 2. The mature hold

local function lots(free, built) return { free = free, built = built, edges = 40, length = 4000, open = 10, ownOpen = 0 } end

test("mature hold: young towns untouched; grown towns over the free line hold demand builds, demK capped", function()
	local function dem(persons, free, built)
		local ledger = {}
		local caps = { target = persons * 1.05, actual = persons, sizeFactors = { 1, 1, 1 }, initials = { 100, 50, 50 } }
		A.demand(ledger, caps, lots(free, built), 2, built)
		caps.sizeFactors = { 3, 2, 2 }   -- the target grew: demand
		caps.target = persons * 1.6
		return A.demand(ledger, caps, lots(free, built), 2, built), caps
	end
	-- young (mat 0): demK 1 whatever the free lots
	local y = dem(1000, 700, 300)
	eq(y.mat, 0)
	eq(y.demK, 1)
	eq(y.matureCap, nil)
	local needs, _, why = A.needsRoom(lots(700, 300), { target = 1600, actual = 1000 }, 2, y)
	ok(needs and why == "demand", "a young town builds: " .. tostring(why))
	-- grown (mat 1), 58 % free: the cap (at 70 % freeK alone is lower already)
	local g = dem(4000, 580, 420)
	eq(g.mat, 1)
	ok(g.demK <= A.MATURE_DEMK + 1e-9, "demK capped at " .. g.demK)
	ok(g.matureCap ~= nil)
	local n2, _, why2 = A.needsRoom(lots(700, 300), { target = 6400, actual = 4000 }, 2, { edges = 10, mat = 1, freeShare = 0.7, lead = 50 })
	ok(not n2 and why2 == "mature", tostring(why2))
	-- grown, 45 % free: neither the hold nor the cap
	local g2 = dem(4000, 450, 550)
	eq(g2.matureCap, nil)
	local n3, _, why3 = A.needsRoom(lots(450, 550), { target = 6400, actual = 4000 }, 2, { edges = 10, mat = 1, freeShare = 0.45, lead = 50 })
	ok(n3 and why3 == "demand", tostring(why3))
	-- the hold line by maturity: none under MATURE_HOLD_MAT, 0.85 at 0.5, 0.60 at 1
	eq(A.matureHoldLine(0.3), nil)
	near(A.matureHoldLine(0.5), 0.85, 1e-9)
	near(A.matureHoldLine(1), 0.60, 1e-9)
	ok(not A.matureHold(0.5, 0.8))
	ok(A.matureHold(1, 0.61))
end)

---------------------------------------------------------------------------
-- 4. Satellites: small core, the watch

test("satellite: a 3-edge core; the watch doses twice after REDOSE_S, then retires an empty one; houses reset it", function()
	local streets = SAT.streets({ x = 1000, y = 0, deadEnd = { 0, 0, 7 }, link = { { 0, 0 }, { 500, 0 }, { 1000, 0 } } })
	local core = 0
	for _, s in ipairs(streets) do if s.sat == "core" then core = core + (#s.pts - 1) end end
	eq(core, 3, "main street block + the cross street at the site")
	local st = { us = 0, doses = 0 }
	local S = 1e6
	eq(SAT.watch(st, 0, 10 * S), nil, "too early: the lots don't exist yet")
	eq(SAT.watch(st, 0, SAT.REDOSE_S * S), "dose")
	st.doses, st.lastDoseUs = 1, SAT.REDOSE_S * S
	eq(SAT.watch(st, 0, SAT.REDOSE_S * S + 5 * S), nil)
	eq(SAT.watch(st, 0, 2 * SAT.REDOSE_S * S), "dose")
	st.doses, st.lastDoseUs = 2, 2 * SAT.REDOSE_S * S
	local what
	for k = 1, SAT.RETIRE_CHECKS do what = SAT.watch(st, 0, (100 + k) * S) end
	eq(what, "retire")
	local st2 = { us = 0, doses = 2, emptyChecks = SAT.RETIRE_CHECKS - 1 }
	eq(SAT.watch(st2, 3, 1000 * S), nil, "housed")
	eq(st2.emptyChecks, 0)
	eq(SAT.watch({ retired = true }, 0, 0), nil)
	local cp = SAT.corePoints({ x = 100, y = 100, link = { { 0, 100 }, { 100, 100 } } }, 20)
	eq(#cp, 2)
	for _, p in ipairs(cp) do ok(G.dist(p[1], p[2], 100, 100) < SAT.CORE_R) end
end)

test("fillKind: a lane's far end / satellite core is never held by the surge rule; Simulate rounds skip the others", function()
	local last = { buildings0 = 100, us = 0 }
	local job = { fill = "dose", fillPts = { { 0, 0 } }, style = {}, town = 1 }
	eq(select(1, D.fillKind(job, {}, nil, last, 500, 1e6, nil)), "dose", "surge: a core dose still goes")
	job.fillWhy = "bridgeEnd"
	eq(select(2, D.fillKind(job, {}, nil, last, 500, 1e6, nil)), "bridgeEnd")
	local shaped = { style = { shape = { id = "radial" } }, town = 1 }
	eq(select(1, D.fillKind(shaped, {}, nil, nil, 200, 0)), "dose")
	H.simNoFills = true
	local k, why = D.fillKind(shaped, {}, nil, nil, 200, 0)
	H.simNoFills = false
	eq(k, nil)
	eq(why, "sim")
	H.simNoFills = true
	eq(select(1, D.fillKind(job, {}, nil, nil, 200, 0)), "dose", "the core dose goes in the rounds too")
	H.simNoFills = false
end)

---------------------------------------------------------------------------
-- 5. Bridges: far bank without a cross street, approach cap and bow

local TPL = "::/infrastructure/street/town/town_new_small.street_template"

test("bridge: no cross street at the far end (CROSS_LATER), the far-bank dose points, a long approach bends, none over APPROACH_MAX", function()
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	local T = ug_require(F.DIR .. "ot_terrain.lua")
	local function plan(dist)
		local g = OG.new()
		local a = OG.addNode(g, nil, 0, 0, 5.5)
		local b = OG.addNode(g, nil, 0, -40, 5.3)
		OG.addEdge(g, nil, a.id, b.id, "small")
		local c, w = -40 - dist - 20, 40
		local s = T.sampler(function(_, y)
			local d = math.abs(y - c)
			if d < w / 2 then return -2 end
			return 5 + math.min(d - w / 2, 400) * 0.002
		end)
		return BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, TPL } }, axis = 0, g = g, seed = 3 })
	end
	local short = plan(80)
	ok(short ~= nil, "a short crossing")
	eq(#short.inc.edges, 3, "approach, span, far: no cross street yet")
	ok(not short.bowed)
	local fp = BR.farPoints(short, 20)
	eq(#fp, 2)
	local C = short.inc.nodes[3]
	for _, p in ipairs(fp) do ok(G.dist(p[1], p[2], C.x, C.y) < 60, "beside the far end") end
	local long = plan(200)
	ok(long ~= nil, "a 200 m approach")
	ok(long.bowed, "bowed")
	eq(#long.inc.edges, 4)
	local W
	for _, nd in ipairs(long.inc.nodes) do if nd.entity == -11 then W = nd end end
	ok(W and math.abs(W.x) > 5, "the waypoint off the straight line")
	ok(long.lockKeys[long.key and ("br:" .. long.deadEnd .. ":approach2")], "both approach pieces locked")
	eq(plan(BR.APPROACH_MAX + 40), nil, "no approach over APPROACH_MAX")
end)

---------------------------------------------------------------------------
-- 6. District name reserve (landscape names)

test("name reserve: real names the assignment left unused, per tag", function()
	local DT = ug_require(F.DIR .. "ot_district.lua")
	local pool = { names = { "Hilltop", "Lakeside", "Coombe", "Mereby" }, buckets = { hill = { 1, 3 }, lake = { 2, 4 } } }
	local r = NM.reserve(pool, { Lakeside = true }, 1, 6)
	eq(#r.hill, 2)
	eq(#r.lake, 1)
	eq(r.lake[1], "Mereby")

end)

---------------------------------------------------------------------------
-- 9. The game script's stop-name gate (ot_gs.script.lua stopsWanted, coordinator fix 2026-10-14)

test("game script: new Road Stops are queued with Landscape / Generated names, never with Game names, Act on Off or in the editor", function()
	local function run(params, editor)
		local mp = { square_organic_towns = params, [""] = editor and { isMapEditor = true } or {} }
		set_global("api", {
			engine = {
				config = { getModParams = function() return mp end },
				system = { stationGroupSystem = { getStationGroup = function() return 500 end } },
				util = { getEntityName = function() return "Park Road" end },
			},
		})
		set_global("data", nil)
		reset_modules()
		ug_require("square_organic_towns::/organic_towns/ot_gs.script.lua")
		local script = data()
		local saved = nil
		local state = { get = function() return saved end, set = function(_, s) saved = s end }
		local param = { { proposal = { edgeObjectsToAdd = { { category = 0, resultEntity = 50,
			modelInstance = { transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 600, 70, 0, 1 } } } } } }, nil, nil, true }
		script.handleEvent(nil, state, nil, "apply_command", "onPostBuildProposal", param)
		set_global("api", nil)
		return saved and saved.sq and #saved.sq or 0
	end
	eq(run({ act_on = 2, town_names = 1 }), 1, "Landscape names")
	eq(run({ act_on = 2, town_names = 3 }), 1, "Generated names")
	eq(run({ act_on = 2, town_names = 2 }), 0, "Game names")
	eq(run({ act_on = 1, town_names = 1 }), 0, "Act on Off")
	eq(run({ act_on = 2, town_names = 1 }, true), 0, "map editor")
end)

---------------------------------------------------------------------------
-- 8 / 13. Generated names: tags that misfired on seed `a` (run 2026-10-14_0613_sqot)

local PN = ug_require(F.DIR .. "ot_placename.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

test("site tags: a plain open town gets no edge / lake / vale / island / spit; species by rarity on the map", function()
	-- a flat open town, some scattered trees, distant hills (wide spread 25 m), no water in the disc
	local plain = { feat = { open = 0.7, floor = 0.9 }, stats = { meanSlope = 0.01, highZ = 52, lowZ = 49 },
		wide = { sd = 25, range = 90 }, forestShare = 0.15, forestEdge = false,
		species = { ash = 500, oak = 200 }, speciesMap = { ash = 8000, oak = 3200 }, read = { alt = 30, relH = -2 } }
	local w = PN.siteTags(plain)
	ok(not w.edge, "no edge without contrast")
	ok(not w.lake and not w.mere and not w.tarn, "no lake")
	ok(not w.vale and not w.valley, "no vale on a flat town (wide spread only)")
	ok(not w.hill, "no hill")
	ok(not w.ash and not w.oak, "the map's common trees: no species tag")
	ok(w.plain and w.forest, "plain + some forest")
	-- the same town at a real forest edge, with birch special to it
	plain.forestEdge = true
	plain.species = { ash = 300, birch = 300 }
	plain.speciesMap = { ash = 8000, birch = 600, oak = 3000 }
	w = PN.siteTags(plain)
	ok(w.edge, "edge with contrast")
	ok(w.birch and not w.ash, "birch special here, ash everywhere")
	-- own relief: vale on a valley floor with its own height range
	w = PN.siteTags({ feat = { floor = 0.8 }, stats = { meanSlope = 0.01, highZ = 70, lowZ = 45 }, wide = { sd = 25 } })
	ok(w.vale, "vale with the town's own relief")
	-- island only with a closed shore; a peninsula is a headland
	w = PN.siteTags({ feat = { island = true, coast = 0.8 }, stats = { water = { kind = "coast" } } })
	ok(not w.island and w.headland, "peninsula: headland")
	w = PN.siteTags({ feat = { island = true, coast = 0.8 }, stats = { water = { kind = "coast" }, shore = { island = true } } })
	ok(w.island, "island")
	-- spit: only with the tip near and water at the town
	w = PN.siteTags({ feat = {}, stats = { spit = { tip = 1600, neck = 200, width = 300 } } })
	ok(not w.spit, "a spit 1.6 km out with no water near: none")
	w = PN.siteTags({ feat = { coast = 0.6 }, stats = { spit = { tip = 500, neck = 200, width = 120 } } })
	ok(w.spit, "a spit at the town")
	-- slope near the water level counts little ("Upper" at altitude 2)
	w = PN.siteTags({ feat = {}, stats = { relief = { grade = 0.06 } }, read = { alt = 2, relH = 0 } })
	ok((w.slope or 0) <= 0.3, "low slope weight at altitude 2")
end)

test("read: a narrow river 350 m from the town (the disc and arm ring miss it) is read by the rays", function()
	-- a 30 m river along y = 350 and another along y = -380
	local s = T.sampler(function() return 20 end, function(_, y) return (y > 335 and y < 365) or (y < -365 and y > -395) end, 0)
	local r = PN.read(s, 0, 0)
	ok(r.rivRays >= PN.RIV_RAYS, "rays " .. tostring(r.rivRays))
	ok(PN.nearRiver(r))
	local w = PN.siteTags({ feat = {}, stats = {}, read = r })
	ok(w.river, "river tag")
	-- an open plain: no crossing
	local dry = T.sampler(function() return 20 end, function() return false end, 0)
	eq(PN.read(dry, 0, 0).rivRays, 0)
	ok(PN.readText(r):find("riv:", 1, true))
end)

test("lake names: no tarn on low ground; forest edge needs woods on one side and open land on another", function()
	local ctx = PN.newCtx("en", 1, {}, {})
	for k = 1, 30 do
		local l = PN.lakeName(ctx, k, false)
		if l then ok(not l.n:lower():find("tarn", 1, true), l.n) end
	end
	-- forest east of 300 m, the town open: an edge; all around: no edge (a clearing / deep town)
	local east = FO.fromFunction(0, 0, function(x) return x > 300 and 60 or 0 end, 1200, 50)
	local around = FO.fromFunction(0, 0, function(x, y) return (x * x + y * y > 300 * 300) and 60 or 0 end, 1200, 50)
	ok(FO.isEdge(east), "edge")
	ok(not FO.isEdge(around), "woods all around: no edge")
	ok(not FO.isEdge(nil))
end)

---------------------------------------------------------------------------
-- 10. Offshoot links: a dead end pointing away leads out along its street and swings round

test("link: a lead-out route from a dead end whose street points toward the target, clear of its own street", function()
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	local LK = ug_require(F.DIR .. "ot_link.lua")
	local g = OG.new()
	OG.addNode(g, 1, 0, 0, 0, true)
	OG.addNode(g, 2, 100, 0, 0, true)
	OG.addEdge(g, 3, 1, 2, "small", true)
	OG.addNode(g, 4, 600, 30, 0, true)
	OG.addNode(g, 5, 700, 30, 0, true)
	OG.addEdge(g, 6, 4, 5, "small", true)
	local LEAD0 = LK.LEAD
	LK.LEAD = false
	local l0, why0 = LK.candidates({ sampler = F.flat, from = { { 0, 0, 1 } }, to = { { 600, 30, 4 } }, g = g })
	LK.LEAD = LEAD0
	eq(#l0, 0, "the straight routes double back")
	eq(why0, "back")
	local l1 = LK.candidates({ sampler = F.flat, from = { { 0, 0, 1 } }, to = { { 600, 30, 4 } }, g = g })
	ok(#l1 >= 1, "a lead-out route")
	ok(type(l1[1].off) == "string" and l1[1].off:find("^lead") ~= nil, tostring(l1[1].off))
	for _, p in ipairs(l1[1].pts) do
		if G.dist(p[1], p[2], 0, 0) > LK.END_SKIP then ok(G.pointSegDist(p[1], p[2], 0, 0, 100, 0) >= LK.CLEAR - 1e-6, "clear of its street") end
	end
end)
