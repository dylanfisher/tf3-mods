-- Offshoot towns instead of streets-only satellites (2026-10-15, NEXT_PHASE_BRIEF 64; run 2026-10-15_0539_sqot: no
-- Works or district town on the map, every founding slot taken by a bare satellite crossing). Covers: the non-linear
-- draw (ot_rng.draw) and why the old one hit "rare" (equal-length labels are one draw shifted), the draw's distribution
-- over many seeds, the per-map quota (2-4 per 16 towns) with its fallback, the stagger (ot_satpace) in a 40-year model
-- of many maps, the landscape terms of the sites, the retired seeds and an old save's satellite, the OFFSHOOTS line.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local rng = ug_require(F.DIR .. "ot_rng.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local DT = ug_require(F.DIR .. "ot_district.lua")
local SP = ug_require(F.DIR .. "ot_satpace.lua")
local SAT = ug_require(F.DIR .. "ot_satellite.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local function townSeed(i)
	return rng.seed(60000 + (i * 7919) % 3000, (i * 104729) % 16000 - 8000, (i * 1299709) % 16000 - 8000)
end

--- chi-square of two [0, 1) samples over a 10 x 10 table (81 degrees of freedom: 0.1 % critical ~124).
local function chi2(a, b)
	local k, c, n = 10, {}, #a
	for i = 1, k * k do c[i] = 0 end
	for i = 1, n do
		local x, y = math.floor(a[i] * k), math.floor(b[i] * k)
		c[x * k + y + 1] = c[x * k + y + 1] + 1
	end
	local e, s = n / (k * k), 0
	for i = 1, k * k do s = s + (c[i] - e) ^ 2 / e end
	return s
end

test("rng: the old draw shifts equal-length labels (the root cause of 'rare'), rng.draw doesn't; unit unchanged", function()
	-- (the user's numbers: a nil seed falls back to 1)
	near(rng.unit(1, "works"), 0.55, 0.005)
	near(rng.unit(1, "district"), 0.463, 0.005)
	-- unit(seed, "district") - unit(seed, "leadLane") is the same for every seed (8-letter labels): a lane-ahead town
	-- (u_leadLane < 0.3) always had u_district in [0.649, 0.949), i.e. "rare" at CHANCE 0.6
	local shift = nil
	for i = 1, 200 do
		local s = townSeed(i)
		local dd = (rng.unit(s, "district") - rng.unit(s, "leadLane")) % 1
		if shift == nil then shift = dd end
		near(dd, shift, 1e-6, "shift " .. i)
		dd = (rng.unit(s, "works") - rng.unit(s, "shape")) % 1
		near(dd, 0.43, 0.001, "works = shape + 0.43")
	end
	print(string.format("old draw: district = leadLane + %.3f, works = shape + 0.430 (mod 1)", shift))
	-- rng.draw: in [0, 1), deterministic, labels and nearby numbers independent
	for i = 1, 100 do
		local u = rng.draw(townSeed(i), "works")
		ok(u >= 0 and u < 1, "range")
		eq(u, rng.draw(townSeed(i), "works"))
	end
	local N = FULL and 20000 or 4000
	local w, dd, ll, sh, w2, sat = {}, {}, {}, {}, {}, {}
	for i = 1, N do
		local s = townSeed(i)
		w[i], dd[i] = rng.draw(s, "works"), rng.draw(s, "district")
		ll[i], sh[i], sat[i] = rng.unit(s, "leadLane"), rng.unit(s, "shape"), rng.unit(s, "satellite")
		w2[i] = rng.draw(s + 2, "works")
	end
	local crit = 135
	for _, p in ipairs({ { "works/district", w, dd }, { "district/leadLane", dd, ll }, { "works/shape", w, sh },
		{ "works seed/seed+2", w, w2 }, { "district/satellite", dd, sat } }) do
		local c = chi2(p[2], p[3])
		ok(c < crit, p[1] .. " chi2 " .. c)
	end
end)

test("draw distribution over many seeds: works ~35 %, districts ~60 %, lane-ahead towns get districts too", function()
	local N = FULL and 20000 or 4000
	local w, d, lead, leadD = 0, 0, 0, 0
	for i = 1, N do
		local s = townSeed(i)
		if WK.eligible({ fresh = true, seed = s, buildings = 500 }) then w = w + 1 end
		local okD = DT.eligible({ fresh = true, seed = s, buildings = 500 })
		if okD then d = d + 1 end
		if rng.draw(s, "leadLane") < 0.3 then   -- (§68: the lead gate draws with rng.decide too)
			lead = lead + 1
			if okD then leadD = leadD + 1 end
		end
	end
	near(w / N, WK.CHANCE, 0.03, "works share")
	near(d / N, DT.CHANCE, 0.03, "district share")
	near(leadD / lead, DT.CHANCE, 0.06, "districts among lane-ahead towns (0 with the old draw)")
	print(string.format("works %.3f, districts %.3f, districts of lane-ahead towns %.3f (N %d)", w / N, d / N, leadD / lead, N))
	-- a nil seed still draws (falls back to 1)
	local okN = WK.eligible({ fresh = true, buildings = 500 })
	ok(okN == true or okN == false)
end)

test("quota: 2-4 offshoots per 16 towns, at least 1; the fallback kind and the 'rare' fallback", function()
	local function q(n) return { D.offshootQuota(n) } end
	eq(q(16)[1], 2); eq(q(16)[2], 4)
	eq(q(8)[1], 1); eq(q(8)[2], 2)
	eq(q(4)[1], 1); eq(q(4)[2], 1)
	eq(q(0)[1], 1); eq(q(32)[1], 4); eq(q(32)[2], 8)
	eq(D.offshootFallbackKind(0, 0, 2, 4), "district", "a tie: district first")
	eq(D.offshootFallbackKind(0, 1, 2, 4), "works")
	eq(D.offshootFallbackKind(2, 1, 2, 4), "district", "works full")
	eq(D.offshootFallbackKind(1, 4, 2, 4), "works", "districts full")
	eq(D.offshootFallbackKind(2, 4, 2, 4), nil)
	local short = { short = true, fallbackKind = "district" }
	local a, b, c = D.offshootFallback("district", false, "rare", 450, short)
	eq(a, true); eq(b, "quota"); eq(c, false)
	a, b, c = D.offshootFallback("district", false, "rare", 320, short)
	eq(a, false); eq(b, "rare"); eq(c, true, "waits to OFF_QUOTA_BUILDINGS")
	a, b = D.offshootFallback("works", false, "rare", 900, short)
	eq(a, false, "not the kind the map lacks")
	a, b = D.offshootFallback("district", false, "rare", 900, { short = false, fallbackKind = "district" })
	eq(a, false, "the map has its minimum")
	a, b = D.offshootFallback("district", false, "character", 900, short)
	eq(b, "character", "only a rare town")
	a, b = D.offshootFallback("district", true, "seeded", 300, short)
	eq(b, "seeded")
end)

-- A 40-year model of one map: 16 towns (the 0539 run's start -> year 40 sizes, scaled per map), 3-5 character towns
-- (no offshoots), each Simulate round every town's decision in the driver's order: Works (WK.eligible + the quota
-- fallback), else a district (DT.eligible + fallback), through the map's pacing (SP.decide); a seeded 15 % of the
-- foundings find no site (refund). Returns the foundings { year, kind, why }.
local TOWNS = {
	{ 118, 949 }, { 287, 1413 }, { 145, 1121 }, { 104, 985 }, { 73, 435 }, { 126, 729 }, { 92, 1015 }, { 189, 1040 },
	{ 165, 664 }, { 77, 959 }, { 91, 429 }, { 57, 550 }, { 129, 505 }, { 101, 616 }, { 132, 685 }, { 104, 1097 },
}
local ROUNDS = { 1, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40 }

local function mapModel(m)
	local st = SP.new(nil)
	local towns = {}
	local scale = 0.7 + 0.6 * rng.draw(m, "scale")
	local nChar = 3 + math.floor(rng.draw(m, "chars") * 3)
	for i, tw in ipairs(TOWNS) do
		towns[i] = { id = 1000 + i, seed = rng.seed(1000 + i, m * 37 + i * 911, m * 53 - i * 613), s0 = tw[1],
			s1 = tw[1] + (tw[2] - tw[1]) * scale, works = false, districts = 0, char = false, wDone = false, dDone = false }
	end
	for k = 1, nChar do towns[1 + math.floor(rng.draw(m, k, "char") * #towns)].char = true end
	local base = 0
	for _, t in ipairs(towns) do base = base + 0.8 * t.s0 end
	local out, nW, nD, now = {}, 0, 0, 0
	local mn, mx = D.offshootQuota(#towns)
	local wq, dq = WK.quota(#towns), DT.quota(#towns)
	for _, Y in ipairs(ROUNDS) do
		local sum = 0
		for _, t in ipairs(towns) do t.size = t.s0 + (t.s1 - t.s0) * Y / 40; sum = sum + 0.8 * t.size end
		for _, t in ipairs(towns) do
			now = now + 2e6
			SP.observe(st, sum, Y)
			local known = nW + nD
			local q = { left = known < mx, short = known < mn, fallbackKind = D.offshootFallbackKind(nW, nD, wq, dq) }
			local kind, why = nil, nil
			if not t.wDone and not t.works then
				local okW, wy = WK.eligible({ fresh = true, seed = t.seed, buildings = t.size, character = t.char,
					quotaLeft = nW < wq and q.left })
				local wait
				okW, wy, wait = D.offshootFallback("works", okW, wy, t.size, q)
				if okW then kind, why = "works", wy
				elseif wy ~= "small" and wy ~= "quota" and not wait then t.wDone = true end
			end
			if kind == nil and not t.dDone and t.districts == 0 then
				local okD, dy = DT.eligible({ fresh = true, seed = t.seed, buildings = t.size, character = t.char,
					count = 0, quotaLeft = nD < dq and q.left })
				local wait
				okD, dy, wait = D.offshootFallback("district", okD, dy, t.size, q)
				if okD then kind, why = "district", dy
				elseif dy ~= "small" and dy ~= "quota" and not wait then t.dDone = true end
			end
			if kind then
				local k = (t.works and 1 or 0) + t.districts
				local res = SP.decide(st, { t = t.id, kind = kind, size = t.size, start = t.s0, k = k, seed = t.seed,
					now = now, sum = sum, base = base, year = 1900, nTowns = #towns, salt = rng.hash("satpace", m), elapsed = Y,
					epoch = Y })
				if res == "found" then
					if rng.draw(m, t.id, Y, "fail") < 0.15 then
						SP.refund(st, t.id)
					else
						if kind == "works" then t.works = true; nW = nW + 1 else t.districts = 1; nD = nD + 1 end
						out[#out + 1] = { y = Y, kind = kind, why = why }
					end
				end
			end
		end
	end
	return out
end

test("model: every map of 16 towns gets 2-4 named offshoot towns, staggered over the years, some via the quota", function()
	local MAPS = FULL and 300 or 60
	local hist, viaQuota, kinds, firstY, lastY = {}, 0, { works = 0, district = 0 }, {}, {}
	local zeroWithoutFallback = 0
	for m = 1, MAPS do
		local fs = mapModel(m)
		hist[#fs] = (hist[#fs] or 0) + 1
		ok(#fs >= 2 and #fs <= 4, "map " .. m .. ": " .. #fs .. " offshoots")
		local per = {}
		for _, f in ipairs(fs) do
			per[f.y] = (per[f.y] or 0) + 1
			ok(per[f.y] <= 1, "map " .. m .. ": one per round, year " .. f.y)
			ok(f.y > 1, "map " .. m .. ": none in the head start round (" .. f.y .. ")")
			kinds[f.kind] = kinds[f.kind] + 1
			if f.why == "quota" then viaQuota = viaQuota + 1 end
		end
		if fs[1] then firstY[#firstY + 1] = fs[1].y; lastY[#lastY + 1] = fs[#fs].y end
		if #fs >= 3 then ok(fs[#fs].y - fs[1].y >= 8, "map " .. m .. ": spread " .. fs[1].y .. "-" .. fs[#fs].y) end
	end
	-- without the fallback a map can end with none: show it happens (the reason for the quota)
	local saved = D.OFF_QUOTA_BUILDINGS
	D.OFF_QUOTA_BUILDINGS = 1e9
	for m = 1, MAPS do if #mapModel(m) == 0 then zeroWithoutFallback = zeroWithoutFallback + 1 end end
	D.OFF_QUOTA_BUILDINGS = saved
	ok(kinds.works > 0 and kinds.district > 0, "both kinds")
	table.sort(firstY)
	table.sort(lastY)
	print(string.format("offshoots per map: 2:%d 3:%d 4:%d; works %d, districts %d, via quota %d; first at year %d-%d (median %d), "
		.. "last at %d-%d (median %d); maps with none without the fallback %d of %d", hist[2] or 0, hist[3] or 0, hist[4] or 0,
		kinds.works, kinds.district, viaQuota, firstY[1], firstY[#firstY], firstY[math.ceil(#firstY / 2)], lastY[1], lastY[#lastY],
		lastY[math.ceil(#lastY / 2)], zeroWithoutFallback, MAPS))
end)

test("sites: the landscape terms prefer open surroundings, an open link and the lean's heading", function()
	-- a forest grid: dense east of x = 700 (the woods), open elsewhere
	local FO = ug_require(F.DIR .. "ot_forest.lua")
	local o = { forest = FO.fromFunction(0, 0, function(x) return x > 700 and 200 or 0 end, FO.R, FO.CELL) }
	ok(o.forest and o.forest.cover, "grid")
	if o.forest and o.forest.cover then
		local dWood = WK.landScore(o, 1000, 0, 0, { { 300, 0 }, { 1000, 0 } })
		local dOpen = WK.landScore(o, -1000, 0, math.pi, { { -300, 0 }, { -1000, 0 } })
		ok(dWood > dOpen + 0.5, string.format("wooded %.2f vs open %.2f", dWood, dOpen))
		local _, info = WK.landScore(o, 1000, 0, 0, nil)
		ok(info.clear ~= nil and info.wood > 0.5, "clearance read")
		-- a deep forest town: no forest terms
		o.deep = true
		eq((WK.landScore(o, 1000, 0, 0, nil)), 0)
	end
	-- the lean: +1 toward the north, -1 toward the south (n sectors)
	local lean = {}
	for k = 1, 16 do lean[k] = math.sin((k - 1) * 2 * math.pi / 16) end
	local land = { n = 16, lean = lean }
	local north = WK.landScore({ land = land }, 0, 1000, math.pi / 2, nil)
	local south = WK.landScore({ land = land }, 0, -1000, -math.pi / 2, nil)
	near(north, -WK.LEAN_W, 0.01)
	near(south, WK.LEAN_W, 0.01)
	eq((WK.landScore({}, 0, 0, 0, nil)), 0, "no grid, no lean: no terms")
	-- a district on flat land with the lean: the site goes the lean's way
	local g = F.roundCore(OG.new(), { rings = { 90, 180, 270 }, counts = { 6, 10, 14 } })
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do local node = g.nodeById[n]; ends[#ends + 1] = { node.x, node.y, n } end
	local s = DT.pickSite({ cx = 0, cy = 0, r = 300, seed = 5, deadEnds = ends, g = g, sampler = F.flat, land = land })
	ok(s ~= nil and s.kind == "open", s and s.kind or "none")
	ok(s.y > 0, "north half (the lean): " .. string.format("%.0f:%.0f", s.x, s.y))
	ok(s.lean and s.lean > 0, "lean logged")
	-- a country crossroads 900 m west: a "cross" district beside it
	local c = DT.pickSite({ cx = 0, cy = 0, r = 300, seed = 5, deadEnds = ends, g = g, sampler = F.flat,
		junctions = { { -900, 0 } } })
	ok(c ~= nil and c.kind == "cross" and G.dist(c.x, c.y, -900, 0) <= DT.CROSS_R, c and c.kind or "none")
	eq(D.landSiteText({ wood = 0.25, clear = 150, lean = -0.5 }), "wood0.25:clear150:lean-0.50")
	eq(D.landSiteText({}), "wood-:clear-:lean-")
end)

-- a minimal engine for the driver glue
local function engine(towns)
	local E = { t = 1e9, logs = {}, created = {} }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.towns() return towns end
	function E.name(t) return "T" .. tostring(t) end
	function E.townCaps(t) return { actual = 2000, target = 2000 } end
	function E.boxCentre(t) return (t % 100) * 5000, 0 end
	function E.closestTown() return nil end
	function E.yearF() return 1920.5 end
	function E.year() return 1920 end
	function E.sendEvent() end
	function E.sampler() return F.flat end
	function E.createTown(o, cb)
		E.created[#E.created + 1] = o
		return true, {}
	end
	return E
end

local function job(t, size, seed)
	return { town = t, trigger = "demand", pts = setmetatable({}, { __len = function() return size end }),
		caps = { actual = size * 3 }, style = { seed = seed }, ext = { cx = 0, cy = 0, r = 300 }, g = OG.new(),
		joinInfo = {}, sampler = F.flat }
end

local function lines(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do if l:find("[SQOT] " .. what, 1, true) then out[#out + 1] = l end end
	return out
end

test("driver: a rare town founds a district by the quota; the map's max stops more; no street satellite is seeded", function()
	local towns = {}
	for i = 1, 16 do towns[i] = 100 + i end
	local E = engine(towns)
	local d = D.new(E)
	d.newMap, d.opts = true, { debug = true }
	local pace = D.PACE
	D.PACE = false
	local pick = DT.pickSite
	DT.pickSite = function(o) return { x = 900, y = 0, d = 900, heading = 0, kind = "open", kinds = "open", link = {}, score = 0,
		wood = 0, lean = 0.2 }, 3 end
	d.offshootName = function() return "T101 Green", "composed", { pattern = "parent", suffix = "green" } end
	d.offshootNamesLine = function() end
	-- a seed the district draw passes over
	local seed = nil
	for i = 1, 500 do
		local s = townSeed(i)
		if rng.draw(s, "district") >= DT.CHANCE then seed = s break end
	end
	ok(seed ~= nil)
	local okE, err = pcall(function()
		-- 320 buildings: rare, waits for the quota's size (its tries kept)
		d:districtDecide(job(101, 320, seed), E.t, nil)
		eq(#E.created, 0)
		ok((d:townState(101).districtTries or 0) < D.DISTRICT_TRIES, "tries kept while the map is short")
		local l = lines(E, "DISTRICT")
		ok(#l == 1 and l[1]:find("why=rare", 1, true) and l[1]:find("quotaWait=true", 1, true), tostring(l[1]))
		-- an offshoot turn (a town that needs no streets): Works or a district, never a satellite
		local due, what = d:offshootTurnDue(103, { buildings = 500, caps = { actual = 2000 } }, E.t, nil)
		ok(due and (what == "works" or what == "district"), tostring(what))
		-- 450: founds one by the quota
		E.t = E.t + 1e6
		d:districtDecide(job(101, 450, seed), E.t, nil)
		eq(#E.created, 1)
		local c = lines(E, "DISTRICT")
		ok(c[#c]:find("event=create", 1, true) and c[#c]:find("why=quota", 1, true) and c[#c]:find("land=wood0.00", 1, true),
			c[#c])
		-- the street satellite is retired: a new town gets no seed
		local j = job(102, 900, seed)
		d:satelliteDecide(j, E.t, nil)
		eq(j.satPlan, nil)
		ok(#lines(E, "SATELLITE") == 1 and lines(E, "SATELLITE")[1]:find("why=retired", 1, true), "SATELLITE retired")
		-- the map's max (4 per 16 towns): with 4 known, a seeded town founds none (quota)
		local st = d:townState(101)
		st.districts[1].phase = "done"
		for i = 2, 4 do d:townState(100 + i).districts = { { phase = "done", town = 900 + i, kind = "district" } } end
		eq(d:offshootKnown(nil), 4)
		local good = nil
		for i = 1, 500 do
			local s = townSeed(i)
			if rng.draw(s, "district") < DT.CHANCE then good = s break end
		end
		d:districtDecide(job(110, 900, good), E.t, nil)
		eq(#E.created, 1, "the map's max reached")
	end)
	DT.pickSite, D.PACE = pick, pace
	ok(okE, tostring(err))
end)

test("old save: a satellite on the frame is restored and grows as before; existing offshoots are kept", function()
	local E = engine({ 201, 202 })
	local d = D.new(E)
	d.newMap = true
	local pace = D.PACE
	D.PACE = false
	local saved = SV.normalize({ v = SV.VERSION, known = {}, frames = { ["201"] = { a = 0, x = 0, y = 0, sx = 900, sy = 0 } },
		wk = { 301 }, dk = { { t = 302, p = 202 } } })
	local okE, err = pcall(function()
		local j = job(201, 600, 5)
		local pts = {}
		for i = 1, 40 do pts[i] = { 900 + (i % 7) * 10, (i % 5) * 10 } end
		j.pts = pts
		d:townState(201).demandBuilds = 2
		d:satelliteDecide(j, E.t, saved)
		local s = d:townState(201)
		ok(s.sat ~= nil and s.sat.restored, "restored")
		ok(j.satPlan ~= nil and j.satPlan.kind == "grow", "grows: " .. tostring(j.satPlan and j.satPlan.kind))
		-- the saved Works / district towns stay claimed and count toward the quota
		ok(d:isOffshootTown(301, saved) and d:isOffshootTown(302, saved))
		eq(d:offshootKnown(saved), 2)
	end)
	D.PACE = pace
	ok(okE, tostring(err))
end)

test("OFFSHOOTS line: each offshoot's buildings over time, once per interval / Simulate round, capped", function()
	local towns = { 401, 402, 501, 502 }
	local E = engine(towns)
	local blds = { [501] = 12, [502] = 3 }
	function E.town2buildings()
		local m = {}
		for id, n in pairs(blds) do m[id] = {}; for i = 1, n do m[id][i] = i end end
		return m
	end
	function E.parcelMap() return {} end
	local d = D.new(E)
	d.newMap = true
	ok(not d:offshootStatus(E.t, nil), "no offshoots: no line")
	d:townState(401).works = { phase = "done", town = 501, kind = "works", simYear = 16 }
	d:townState(402).districts = { { phase = "done", town = 502, kind = "district", year = 1931.2 } }
	ok(d:offshootStatus(E.t, nil))
	local l = lines(E, "OFFSHOOTS")
	eq(#l, 1)
	ok(l[1]:find("501:T501:works:401:y16:b12", 1, true) and l[1]:find("502:T502:district:402:y1931:b3", 1, true), l[1])
	ok(l[1]:find("n=2", 1, true) and l[1]:find("quota=2/1-1", 1, true), l[1])
	ok(not d:offshootStatus(E.t + 1e6, nil), "not again within OFFSHOOT_LOG_S")
	local H = ug_require(F.DIR .. "ot_hooks.lua")
	H.simRound = 7
	blds[501] = 40
	ok(d:offshootStatus(E.t + 2e6, nil), "a new Simulate round")
	ok(lines(E, "OFFSHOOTS")[2]:find(":b40", 1, true))
	H.simRound = nil
	ok(d:offshootStatus(E.t + (D.OFFSHOOT_LOG_S + 3) * 1e6, nil), "after the interval")
end)

test("loop caps: OFFSHOOTS lists at most OFFSHOOT_LOG_MAX towns; crossroads read at most 64; the quota on odd inputs", function()
	local towns = {}
	for i = 1, 80 do towns[i] = 600 + i end
	local E = engine(towns)
	function E.town2buildings() return {} end
	function E.parcelMap() return {} end
	local d = D.new(E)
	for i = 1, 40 do d:townState(600 + i).districts = { { phase = "done", town = 700 + i, kind = "district" } } end
	local cap = D.OFFSHOOT_LOG_MAX
	D.OFFSHOOT_LOG_MAX = 5
	ok(d:offshootStatus(E.t, nil))
	D.OFFSHOOT_LOG_MAX = cap
	local l = lines(E, "OFFSHOOTS")[1]
	local _, parts = l:gsub(":district:", "")
	eq(parts, 5, l)
	ok(l:find("n=40", 1, true), "n counts every one")
	-- a thousand crossroads: the feature read stops at 64, a site is still found (or none), no hang
	local js = {}
	for i = 1, 1000 do js[i] = { 5000 + i, 5000 } end
	js[1000] = { -900, 0 }
	local feats = DT.features({ sampler = F.flat, cx = 0, cy = 0, junctions = js }, -900, 0, math.pi, 900)
	eq(feats.cross, nil, "the 1000th crossroads is past the cap")
	feats = DT.features({ sampler = F.flat, cx = 0, cy = 0, junctions = { { -900, 0 } } }, -900, 0, math.pi, 900)
	eq(feats.cross, true)
	local mn, mx = D.offshootQuota(0 / 0)
	ok(mn == 1 and mx == 1, "NaN towns")
	mn, mx = D.offshootQuota(-5)
	ok(mn == 1 and mx == 1, "negative towns")
	-- the landscape lean ignores a NaN field value
	local land = { n = 4, lean = { 0 / 0, 0 / 0, 0 / 0, 0 / 0 } }
	eq((WK.landScore({ land = land }, 0, 0, 0, nil)), 0)
end)
