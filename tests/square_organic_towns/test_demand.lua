-- Growth-demand trigger (ot_assess.demand, real map + Simulate natural growth 2026-10-12): the driver against a fake
-- town that grows like the game. Each cycle (one check interval) the "game" raises the town's size factors, places
-- houses on free lots (the developer's pace) and adds its own streets at its own unlocked dead ends; then the driver
-- runs. In game the room trigger never fired at that pace (262 CHECK lines, all why=open, 0 builds).
--
-- Vanilla street models:
--   independent  the game adds one street per VAN_P persons of target growth whatever frontage is free (what the
--                live log shows: Aldershot 58 -> 133 edges while open frontage was ~3x the need)
--   frontage     the game adds streets only while the free lots are under its own want (our streets pre-empt it)

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local D = ug_require(F.DIR .. "ot_driver.lua")
local LP = ug_require(F.DIR .. "ot_lockpol.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
-- (the offshoot mechanism tests below run without the map-wide pacing, ot_satpace: test_satpace covers it)
local SP = ug_require(F.DIR .. "ot_satpace.lua")

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN = 100
local US_NAMES = "square_names_us_texas::/names/usa/usa.names"
local EU_NAMES = "::/names/germany/germany.names"

local CAP_PER_LOT = 2.0     -- persons per built lot (the run: 1.6-3.5)
local LOT_M = 8             -- parcels per metre of street (both sides): a 100 m edge has 12
local PACE = 0.5            -- the developer builds this share of the missing capacity per cycle
local VAN_P = 25            -- independent model: persons of target growth per vanilla street (the run: 18-26 in
                            -- the towns that kept up, 71 in Aldershot, which fell behind)
local GAP_W = 0.3           -- a free lot on an edge filled OPEN_FILL or more gets a house this much less often (the
                            -- run: gaps 251 -> 571 while the built lots doubled: the developer leaves them empty)
local VAN_OPEN = 0.75       -- frontage model: open frontage the game keeps, x its built lots
local FILLED = 0.45         -- the engine town's lots built at the start (the run: 37-45 %, half of them in gaps)
local ADOPT_CYCLES = 1      -- our edges get parcels this many cycles after the build

--- An engine-made town about the run's Aldershot at its start (58 edges, 415 built lots, 190 buildings): 5 x 5
--- blocks of 100 m with FILLED of their lots built (gaps) and eight empty dead-end stubs (open frontage), so open
--- frontage sits well over the need and the room rule doesn't fire.
local function world()
	local W = { nodes = {}, edges = {}, nid = 0, eid = 100 }
	local at = {}
	local function node(x, y)
		W.nid = W.nid + 1
		W.nodes[W.nid] = { id = W.nid, x = x, y = y, z = 10, cfg = true }
		at[x .. ":" .. y] = W.nid
		return W.nid
	end
	W.node = node
	function W.edge(a, b, extra)
		W.eid = W.eid + 1
		local na, nb = W.nodes[a], W.nodes[b]
		local len = math.sqrt((nb.x - na.x) ^ 2 + (nb.y - na.y) ^ 2)
		local e = { id = W.eid, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
			t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
			objects = 0, owned = false, inConstruction = false, locked = false, parcels = math.floor(len / LOT_M),
			built = math.floor(len / LOT_M * FILLED), len = len }
		for k, v in pairs(extra or {}) do e[k] = v end
		W.edges[#W.edges + 1] = e
		return e
	end
	local C = { -200, -100, 0, 100, 200 }
	for _, x in ipairs(C) do
		for _, y in ipairs(C) do node(x, y) end
	end
	for _, a in ipairs(C) do
		for i = 1, #C - 1 do
			W.edge(at[a .. ":" .. C[i]], at[a .. ":" .. C[i + 1]])
			W.edge(at[C[i] .. ":" .. a], at[C[i + 1] .. ":" .. a])
		end
	end
	for _, a in ipairs({ -100, 100 }) do
		W.edge(at["200:" .. a], node(300, a), { built = 0 })
		W.edge(at["-200:" .. a], node(-300, a), { built = 0 })
		W.edge(at[a .. ":200"], node(a, 300), { built = 0 })
		W.edge(at[a .. ":-200"], node(a, -300), { built = 0 })
	end
	return W
end

local upgrade   -- (the upgrade model, below houses)

local function rng(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function fakeEngine(o)
	local W = world()
	local E = { t = 0, logs = {}, W = W, sf = { 1, 1, 1 } }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return { nameList = o.names or US_NAMES, climate = "::/climates/temperate" } end
		return nil
	end
	function E.modParams() return o.params, {} end
	function E.gameTime() return o.gameTime or 10 * SV.FRESH_GAME_TIME end
	function E.year() return o.year or 1970 end
	function E.balance() return 5000000 end
	function E.towns() return { o.town or TOWN } end
	function E.name(t) return "Growville" .. t end
	function E.boxCentre(_t) return 0, 0 end
	function E.target()
		local t = 0
		for i = 1, 3 do t = t + E.ini[i] * E.sf[i] end
		return t
	end
	function E.builtLots()
		local n = 0
		for _, e in ipairs(W.edges) do n = n + (e.built or 0) end
		return n
	end
	-- the town starts at 98 % of its target (the run: 0.95-0.99)
	local a0 = E.builtLots() * CAP_PER_LOT / 0.98
	E.cpl = CAP_PER_LOT   -- persons per built lot (the upgrade model raises it, simulate o.upgrade)
	E.ini = { a0 * 0.6, a0 * 0.2, a0 * 0.2 }
	function E.townCaps(_t)
		local ini, sf = {}, {}
		for i = 1, 3 do ini[i], sf[i] = E.ini[i], E.sf[i] end
		return { target = E.target(), actual = E.builtLots() * E.cpl, sizeFactors = sf, initials = ini,
			initial = ini[1] + ini[2] + ini[3] }
	end
	function E.town2buildings() return {} end
	function E.townBuildings(_t, _m)
		local pts, builtBy = {}, {}
		for _, e in ipairs(W.edges) do
			builtBy[e.id] = e.built or 0
			for k = 1, math.ceil((e.built or 0) / 2) do
				local f = k / (math.ceil(e.built / 2) + 1)
				pts[#pts + 1] = { e.p0[1] + (e.p1[1] - e.p0[1]) * f, e.p0[2] + (e.p1[2] - e.p0[2]) * f }
			end
		end
		return pts, builtBy
	end
	function E.parcelMap()
		local m = {}
		for _, e in ipairs(W.edges) do if e.parcels then m[e.id] = { n = e.parcels } end end
		return m
	end
	function E.parcelCount(pd) return pd.n end
	function E.closestTown(_x, _y) return o.town or TOWN end
	local function dist(p, x, y) return math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) end
	function E.streets(x, y, r)
		local out = {}
		for _, e in ipairs(W.edges) do
			if dist(e.p0, x, y) <= r or dist(e.p1, x, y) <= r then out[#out + 1] = e end
		end
		return out
	end
	function E.edge(id)
		for _, e in ipairs(W.edges) do if e.id == id then return e end end
		return nil
	end
	function E.nodeStreetEdges(n)
		local out = {}
		for _, e in ipairs(W.edges) do if e.n0 == n or e.n1 == n then out[#out + 1] = e.id end end
		return out
	end
	function E.hasConfig(n) return W.nodes[n] ~= nil and W.nodes[n].cfg end
	function E.nodeInConstruction(_n) return false end
	function E.sampler() return F.flat end
	function E.templateExists(_p) return true end
	function E.templateLanes(_p) return 4 end
	function E.proposal(spec) return { spec = spec } end
	function E.context() return {} end
	function E.precheck(_p, _ctx)
		return { ok = true, msgs = {}, collisions = 0, buildings = 0, cost = 1000, us = 1000 }
	end
	function E.sendBuild(p, _ctx, cb) E.pending = { spec = p.spec, cb = cb } end
	function E.sendEvent() end
	function E.growTown() end
	return E
end

--- Builds a sent spec into the world (new nodes get their config, as the proposal's cfgAdd does in game); the
--- new edges have no parcels until adopted. Returns the new edges.
local function applySpec(E, spec, cycle)
	local W = E.W
	local map, out = {}, {}
	for _, nd in ipairs(spec.nodes) do
		W.nid = W.nid + 1
		W.nodes[W.nid] = { id = W.nid, x = nd.pos[1], y = nd.pos[2], z = nd.pos[3], cfg = true }
		map[nd.entity] = W.nid
	end
	for _, e in ipairs(spec.edges) do
		W.eid = W.eid + 1
		local len = math.sqrt((e.p1[1] - e.p0[1]) ^ 2 + (e.p1[2] - e.p0[2]) ^ 2)
		local ne = { id = W.eid, n0 = map[e.node0] or e.node0, n1 = map[e.node1] or e.node1, p0 = e.p0, p1 = e.p1,
			t0 = e.t0, t1 = e.t1, template = SMALL, lanes = 4, objects = 0, owned = false, inConstruction = false,
			locked = e.locked == true, parcels = nil, built = 0, len = len, mod = true, bornCycle = cycle }
		W.edges[#W.edges + 1] = ne
		out[#out + 1] = ne
	end
	return out
end

local function degree(W)
	local deg = {}
	for _, e in ipairs(W.edges) do
		deg[e.n0] = (deg[e.n0] or 0) + 1
		deg[e.n1] = (deg[e.n1] or 0) + 1
	end
	return deg
end

--- One vanilla street (60-100 m): an extension of one of the game's own dead ends (not ours, never a locked street;
--- the one nearest the centre of three picks: the game grows compact), turned up to 45°; else a branch off a game
--- street's end node. Returns the new edge.
local function vanillaStreet(E, rnd)
	local W = E.W
	local deg = degree(W)
	local cands = {}
	for _, e in ipairs(W.edges) do
		if not e.mod and not e.locked then
			for k = 0, 1 do
				local n = k == 0 and e.n1 or e.n0
				local other = k == 0 and e.n0 or e.n1
				if deg[n] == 1 then cands[#cands + 1] = { n = n, from = other } end
			end
		end
	end
	local function r2(c) local nd = W.nodes[c.n] return nd.x * nd.x + nd.y * nd.y end
	local pick
	if #cands > 0 then
		for _ = 1, 3 do
			local c = cands[math.floor(rnd() * #cands) + 1]
			if pick == nil or r2(c) < r2(pick) then pick = c end
		end
	else
		local e
		for _ = 1, 50 do
			e = W.edges[math.floor(rnd() * #W.edges) + 1]
			if not e.mod and not e.locked then break end
		end
		pick = { n = e.n1, from = e.n0, branch = true }
	end
	local a, b = W.nodes[pick.n], W.nodes[pick.from]
	local ang = math.atan(a.y - b.y, a.x - b.x) + (rnd() - 0.5) * math.pi / 2
	if pick.branch then ang = ang + (rnd() < 0.5 and 1 or -1) * math.pi / 2 end
	local len = 60 + rnd() * 40
	local n = W.node(a.x + math.cos(ang) * len, a.y + math.sin(ang) * len)
	local e = W.edge(pick.n, n)
	e.built = 0
	return e
end

--- Houses: the developer adds PACE of the missing capacity as built lots, on free lots picked at random (an edge
--- with more free lots gets more houses; lots in gaps on fuller edges GAP_W as often). Returns the lots built on mod / game streets this cycle.
local function houses(E, rnd)
	local W = E.W
	local missing = (E.target() - E.builtLots() * E.cpl) / E.cpl
	local n = math.floor(math.max(0, missing) * PACE + 0.5)
	local onMod, onGame = 0, 0
	for _ = 1, n do
		local free, total = {}, 0
		for _, e in ipairs(W.edges) do
			local f = e.parcels and math.max(0, e.parcels - e.built) or 0
			if f > 0 and e.built >= e.parcels * A.OPEN_FILL then f = f * GAP_W end
			if f > 0 then
				free[#free + 1] = { e = e, f = f }
				total = total + f
			end
		end
		if total == 0 then break end
		local r = rnd() * total
		for _, x in ipairs(free) do
			r = r - x.f
			if r <= 0 then
				x.e.built = x.e.built + 1
				if x.e.mod then onMod = onMod + 1 else onGame = onGame + 1 end
				break
			end
		end
	end
	return onMod, onGame
end

--- The upgrade model (2026-10-14, for the maturity test): where the town's free share of lots is under UPG_FREE (the
--- game's own level at the EU 35° angle, ~60 %), UPG_K of the capacity the houses left missing goes into the built
--- lots (bigger buildings on the same lots; the two same-seed runs: 2.9 persons per building with the mod's frontage,
--- 6.3 with the brake), in full UPG_BAND below. A model, not the game's rule.
local UPG_FREE, UPG_BAND, UPG_K = 0.62, 0.12, 0.5
upgrade = function(E)
	local free, total = 0, 0
	for _, e in ipairs(E.W.edges) do
		if e.parcels then free, total = free + math.max(0, e.parcels - e.built), total + e.parcels end
	end
	local built = E.builtLots()
	if total == 0 or built == 0 then return end
	local k = math.max(0, math.min(1, (UPG_FREE - free / total) / UPG_BAND))
	local missing = E.target() - built * E.cpl
	if missing > 0 and k > 0 then E.cpl = E.cpl + missing * UPG_K * k / built end
end

local function ownOpenLots(W)
	local n = 0
	for _, e in ipairs(W.edges) do
		if e.mod then
			if e.parcels == nil then n = n + math.floor(e.len / A.VIRTUAL_LOT_M)
			elseif e.built < e.parcels * A.OPEN_FILL then n = n + (e.parcels - e.built) end
		end
	end
	return n
end

--- Runs the growth simulation; returns the stats.
local function simulate(o)
	local savedFill = D.FILL_POINTS
	D.FILL_POINTS = 0
	local savedDemand = A.DEMAND
	A.DEMAND = o.demand ~= false
	-- (2026-10-14 late: this model's lots hold CAP_PER_LOT persons whatever the frontage, so the persons-per-building
	-- factor of the demand (ot_assess.pbK) would only scale every run down; it is tested on its own. PB_AIM =
	-- CAP_PER_LOT: pbK 1 here)
	local savedPbAim = A.PB_AIM
	A.PB_AIM = o.pbAim or CAP_PER_LOT
	local E = fakeEngine({ params = o.params or { act_on = 3, debug_log = 2, style = 2 }, names = o.names, year = o.year,
		town = o.town, gameTime = o.gameTime })
	if o.onEngine then o.onEngine(E) end
	local d = D.new(E)
	if o.onDriver then o.onDriver(d) end
	local rnd = rng(o.seed or 1)
	local st = { modEdges = 0, gameEdges = 0, modLen = 0, gameLen = 0, builds = 0, why = {}, maxOwnOpen = 0, onMod = 0, onGame = 0,
		perCycle = {} }
	local acc = 0
	local nLogs = 0
	local ok, err = pcall(function()
		for cycle = 1, o.cycles or 24 do
			-- the game: size factors up, the developer's houses, its own streets
			local t0 = E.target()
			for i = 1, 3 do E.sf[i] = E.sf[i] * (1 + (o.growth or 0.08)) end
			local dT = E.target() - t0
			for _, e in ipairs(E.W.edges) do
				if e.mod and e.parcels == nil and cycle - e.bornCycle >= ADOPT_CYCLES then
					e.parcels = math.floor(e.len / LOT_M)
				end
			end
			local m, g = houses(E, rnd)
			st.onMod, st.onGame = st.onMod + m, st.onGame + g
			if o.upgrade then upgrade(E) end
			local nVan = 0
			if o.model == "frontage" then
				-- the game's want: open frontage (lots on edges filled below OPEN_FILL, our unadopted streets' virtual
				-- lots) of VAN_OPEN x its built lots (the run: Aldershot 1.03 -> 0.73)
				local free = 0
				for _, e in ipairs(E.W.edges) do
					if e.parcels == nil then free = free + math.floor(e.len / A.VIRTUAL_LOT_M)
					elseif e.built < e.parcels * A.OPEN_FILL then free = free + e.parcels - e.built end
				end
				local want = E.builtLots() * (o.vanOpen or VAN_OPEN)
				while free < want and nVan < 12 do
					local e = vanillaStreet(E, rnd)
					free = free + e.parcels
					nVan = nVan + 1
					st.gameLen = st.gameLen + e.len
				end
			elseif o.model ~= "none" then
				acc = acc + dT / VAN_P
				while acc >= 1 do
					st.gameLen = st.gameLen + vanillaStreet(E, rnd).len
					acc = acc - 1
					nVan = nVan + 1
				end
			end
			st.gameEdges = st.gameEdges + nVan
			-- the driver: one check interval (48 s of real time in the run's 16-town round-robin)
			local nMod = 0
			local nTicks = (o.checkEvery and cycle % o.checkEvery ~= 0) and 0 or (o.ticks or 480)
			for _ = 1, nTicks do
				d:tick(E.t, nil)
				E.t = E.t + 100000
				if E.pending then
					local p = E.pending
					E.pending = nil
					for _, e in ipairs(applySpec(E, p.spec, cycle)) do
						nMod = nMod + 1
						st.modLen = st.modLen + e.len
					end
					p.cb(true, { cost = 1000, msgs = {} })
				end
			end
			st.modEdges = st.modEdges + nMod
			for i = nLogs + 1, #E.logs do
				local l = E.logs[i]
				if l:find("[SQOT] CHECK", 1, true) then
					local why = l:match(" why=(%a+)")
					st.why[why] = (st.why[why] or 0) + 1
				elseif l:find("[SQOT] BUILT", 1, true) and l:find("ok=true", 1, true) then
					st.builds = st.builds + 1
				end
			end
			nLogs = #E.logs
			st.maxOwnOpen = math.max(st.maxOwnOpen, ownOpenLots(E.W))
			local pts = E.townBuildings(TOWN)
			st.perCycle[cycle] = { mod = nMod, game = nVan, persons = E.target(),
				pb = #pts > 0 and E.builtLots() * E.cpl / #pts or nil }
		end
	end)
	D.FILL_POINTS = savedFill
	A.DEMAND = savedDemand
	A.PB_AIM = savedPbAim
	assert(ok, err)
	st.share = st.modEdges / math.max(1, st.modEdges + st.gameEdges)
	st.lenShare = st.modLen / math.max(1, st.modLen + st.gameLen)
	st.E = E
	return st
end

local function whyText(w)
	local o = {}
	for _, k in ipairs({ "demand", "ahead", "low", "open", "over", "free", "mature" }) do
		if w[k] then o[#o + 1] = k .. ":" .. w[k] end
	end
	return table.concat(o, " ")
end

local function report(name, st)
	print(string.format("        %s: builds %d, new edges mod %d / game %d (mod %.0f %%, by length %.0f %%), houses on mod / game streets %d / %d, max own open lots %d, why %s",
		name, st.builds, st.modEdges, st.gameEdges, st.share * 100, st.lenShare * 100, st.onMod, st.onGame, st.maxOwnOpen,
		whyText(st.why)))
end

test("lots: own streets (locked / built this session) count their open frontage apart; length sums the streets", function()
	local l = A.lots({
		{ id = 1, mx = 150, my = 0, len = 100, parcels = 12, built = 2, town = true, own = true },    -- 10 open lots
		{ id = 2, mx = 150, my = 0, len = 120, parcels = nil, built = 0, town = true, own = true },   -- 10 virtual
		{ id = 3, mx = 150, my = 0, len = 100, parcels = 12, built = 6, town = true, own = true },    -- half full: gaps
		{ id = 4, mx = 150, my = 0, len = 100, parcels = 12, built = 0, town = true },                -- the game's
	}, { cx = 0, cy = 0, r = 200 })
	eq(l.ownOpen, 20)
	eq(l.ownEdges, 3)
	eq(l.open, 10 + 10 + 12)
	eq(l.length, 420)
end)

test("demand ledger: target growth since the last build in edges; builds serve it; a long hold is capped", function()
	local caps = { target = 1000, actual = 1000, sizeFactors = { 1, 1, 1 }, initials = { 600, 200, 200 } }
	local lots = { edges = 50, built = 500, ownOpen = 0, length = 5000 }
	local L = {}
	-- (2026-10-14 late: 2 persons per built lot here; the persons-per-building factor is checked below on its own)
	local pbAim0 = A.PB_AIM
	A.PB_AIM = 2
	local dem = A.demand(L, caps, lots, 2)
	eq(dem.edges, 0, "first sight: the current size is no demand")
	-- (2026-10-14: counted at DENSIFY x the town's persons per metre: fewer edges per unit of growth)
	near(dem.perEdge, 20 * A.DENSIFY, 1e-9)
	caps.sizeFactors = { 1.1, 1.1, 1.1 }
	caps.target = 1100
	dem = A.demand(L, caps, lots, 2)
	near(dem.cap, 100, 1e-9)
	near(dem.edges, 5 / A.DENSIFY, 1e-9)
	-- the free-lot brake: 60 % of the lots free asks less (a grown town: 2026-10-14 the brake phases in with the
	-- maturity, so this 1000-person town is made mature here; the young case below)
	local matLo0, matHi0 = A.MAT_LO, A.MAT_HI
	A.MAT_LO, A.MAT_HI = 0, 0
	local d2 = A.demand({ sf = { 1, 1, 1 } }, caps, { edges = 50, built = 400, free = 600, ownOpen = 0, length = 5000 }, 2)
	ok(d2.freeK < 1 and d2.edges < dem.edges, "free lots brake: " .. d2.freeK)
	A.MAT_LO, A.MAT_HI = matLo0, matHi0
	local dy = A.demand({ sf = { 1, 1, 1 } }, caps, { edges = 50, built = 400, free = 600, ownOpen = 0, length = 5000 }, 2)
	eq(dy.mat, 0, "1000 persons: young")
	eq(dy.demK, 1, "a young town asks its whole demand")
	near(dy.edges, dem.edges, 1e-9)
	A.MAT_LO, A.MAT_HI = 0, 0
	A.PB_AIM = pbAim0
	-- (2026-10-14 late) the brake follows the free lots around FREE_AIM and the persons per building around PB_AIM
	-- (2026-10-14: FREE_AIM 0.5 -> 0.55, band 0.45-0.6 -> 0.5-0.7: the game's own 35° towns keep ~60 % free)
	eq(A.freeK(0.40), 1)
	eq(A.freeK(A.FREE_AIM - A.FREE_BAND_LO), 1)
	near(A.freeK(0.58), 1 - (1 - A.FREE_MIN) * (0.58 - (A.FREE_AIM - A.FREE_BAND_LO)) / (A.FREE_BAND_LO + A.FREE_BAND_HI),
		1e-9, "the 0119 run's 58 % free")
	ok(A.freeK(0.58) < 0.7, "58 % free asks under 0.7 (0.3 with the 0.5 aim)")
	ok(A.freeK(0.60) > 0.5 and A.freeK(0.60) < 0.6, "the game's own 60 % free: about half")
	near(A.freeK(0.70), A.FREE_MIN, 1e-6)
	eq(A.maturity(1000), 1, "(made mature)")
	A.MAT_LO, A.MAT_HI = matLo0, matHi0
	eq(A.maturity(nil), 1)
	eq(A.maturity(A.MAT_LO), 0)
	eq(A.maturity(A.MAT_HI + 1), 1)
	near(A.maturity((A.MAT_LO + A.MAT_HI) / 2), 0.5, 1e-9)
	A.MAT_LO, A.MAT_HI = 0, 0
	eq(A.pbK(nil), 1)
	eq(A.pbK(6.4), 1, "vanilla's density: no brake")
	near(A.pbK(2.9), 2.9 / A.PB_AIM, 1e-9)
	eq(A.pbK(1.0), A.PB_K_MIN)
	local d3 = A.demand({ sf = { 1, 1, 1 } }, caps, { edges = 50, built = 500, free = 0, ownOpen = 0, length = 5000 }, 2)
	near(d3.pbK, math.max(A.PB_K_MIN, 2 / A.PB_AIM), 1e-9, "1000 persons on 500 built lots")
	near(d3.demK, math.max(A.K_MIN, d3.freeK * d3.pbK), 1e-9)
	-- (2026-10-14: persons per building when the buildings are known; 1000 persons in 200 buildings: no brake)
	local d4 = A.demand({ sf = { 1, 1, 1 } }, caps, { edges = 50, built = 500, free = 0, ownOpen = 0, length = 5000 }, 2, 200)
	eq(d4.pbK, 1, "5 persons per building, though 2 per built lot")
	-- a town with most of its lots free gets no streets for room either (why=free); demand still decides first
	local nf, _, whyF = A.needsRoom({ open = 0, built = 300, ownOpen = 0 }, caps, 2, { edges = 0, freeShare = 0.65, lead = 0 })
	ok(not nf)
	eq(whyF, "free")
	-- (2026-10-14) ... but a young town still builds for room
	local ny, _, whyY = A.needsRoom({ open = 0, built = 300, ownOpen = 0 }, caps, 2, { edges = 0, freeShare = 0.65, lead = 0, mat = 0 })
	ok(ny, "young: room")
	eq(whyY, "low")
	A.MAT_LO, A.MAT_HI = matLo0, matHi0
	A.PB_AIM = 2
	local needs, _, why = A.needsRoom({ open = 900, built = 500, ownOpen = 0 }, caps, 2, dem)
	ok(needs, "demand builds although the town has plenty of open frontage")
	eq(why, "demand")
	-- own streets still empty: hold
	local n2, _, why2 = A.needsRoom({ open = 900, built = 500, ownOpen = dem.lead }, caps, 2, dem)
	ok(not n2)
	eq(why2, "ahead")
	-- a dose fill raising the initial capacities is no demand (size factors only)
	caps.initials = { 900, 300, 300 }
	caps.target = 1650
	dem = A.demand(L, caps, lots, 2)
	near(dem.cap, 150, 1e-9, "Σ initial x Δ size factor")
	A.served(L, caps, 150)
	dem = A.demand(L, caps, lots, 2)
	near(dem.cap, 0, 1e-6, "served")
	-- under DEMAND_MIN_EDGES: the old room rule decides
	caps.sizeFactors = { 1.101, 1.101, 1.101 }
	dem = A.demand(L, caps, lots, 2)
	ok(dem.edges < A.DEMAND_MIN_EDGES)
	local _, _, why3 = A.needsRoom({ open = 900, built = 500, ownOpen = 0 }, caps, 2, dem)
	eq(why3, "open")
	-- a huge jump keeps at most DEMAND_BANK x fast increments (fast growers, 2026-10-13: up to FAST_MAX x the bank,
	-- increments up to 2 x maxEdges); the fast factor decays when the growth slows
	caps.sizeFactors = { 5, 5, 5 }
	dem = A.demand(L, caps, lots, 2)
	eq(dem.fast, A.FAST_MAX)
	-- (2026-10-13: the bank's own factor runs to BANK_FAST_MAX: 4-year chunks of the dev simulation)
	near(dem.edges, A.DEMAND_BANK * A.BANK_FAST_MAX * A.maxEdges(2), 1e-6)
	eq(dem.incMax, 2 * A.maxEdges(2))
	A.served(L, caps, dem.cap)
	dem = A.demand(L, caps, lots, 2)
	near(dem.fast, math.min(A.FAST_MAX, A.BANK_FAST_MAX * A.FAST_DECAY), 1e-9, "decays")
	for _ = 1, 3 do dem = A.demand(L, caps, lots, 2) end
	ok(dem.fast < A.FAST_MAX, "decays below the cap: " .. dem.fast)
	for _ = 1, 10 do dem = A.demand(L, caps, lots, 2) end
	eq(dem.fast, 1)
	eq(dem.incMax, A.maxEdges(2))
	-- a moderate jump (1.5 x the normal bank): fast 1.5, increments 1.25 x
	local L3 = {}
	local c3 = { target = 1000, actual = 1000, sizeFactors = { 1, 1, 1 }, initials = { 600, 200, 200 } }
	A.demand(L3, c3, lots, 2)
	local f = 1 + 1.5 * A.DEMAND_BANK * A.maxEdges(2) * 20 * A.DENSIFY / 1000
	c3.sizeFactors = { f, f, f }
	local d3 = A.demand(L3, c3, lots, 2)
	near(d3.fast, 1.5, 1e-6)
	near(d3.edges, 1.5 * A.DEMAND_BANK * A.maxEdges(2), 1e-6, "not capped")
	-- the scheduler: "more" puts a town on a short cooldown and picks it first when due
	local sched = A.newSched()
	A.cooldown(sched, 7, 0, "more")
	A.cooldown(sched, 3, 0, "room")
	eq(A.pick(sched, { 3, 5, 7 }, 1), 5, "7 and 3 still cooling, 5 due")
	eq(A.pick(sched, { 3, 5, 7 }, A.COOLDOWN_S.more * 1e6 + 1), 7, "hot town first")
	eq(sched.towns[7].hot, false)
	-- without size factors (older fakes): the target itself
	local L2 = {}
	A.demand(L2, { target = 1000, actual = 900 }, lots, 2)
	local d2 = A.demand(L2, { target = 1200, actual = 900 }, lots, 2)
	near(d2.cap, 200, 1e-9)
	eq(A.demand({}, nil, lots, 2), nil)
A.PB_AIM = pbAim0
end)

--- Runs a scenario over SEEDS and reports each run; returns the runs and their pooled stats.
local SEEDS = { 1, 2, 3, 4, 5 }
local function scenario(name, o)
	local runs, pool = {}, { modEdges = 0, gameEdges = 0, builds = 0, minBuilds = math.huge }
	for _, seed in ipairs(SEEDS) do
		local oo = { seed = seed }
		for k, v in pairs(o) do oo[k] = v end
		local st = simulate(oo)
		report(string.format("%s seed %d", name, seed), st)
		runs[#runs + 1] = st
		pool.modEdges, pool.gameEdges = pool.modEdges + st.modEdges, pool.gameEdges + st.gameEdges
		pool.builds = pool.builds + st.builds
		pool.minBuilds = math.min(pool.minBuilds, st.builds)
	end
	pool.share = pool.modEdges / math.max(1, pool.modEdges + pool.gameEdges)
	print(string.format("        %s pooled: mod share of new edges %.0f %%, builds %d (min %d per run)", name,
		pool.share * 100, pool.builds, pool.minBuilds))
	return runs, pool
end

test("old room trigger at the game's growth pace: the town grows, the mod builds (almost) nothing (the real-map run)", function()
	-- the frontage model reproduces the run: the game keeps open frontage ahead, the room rule never fires
	local runs, pool = scenario("room only / frontage", { demand = false, model = "frontage" })
	ok(pool.builds <= #SEEDS, "builds " .. pool.builds)
	for _, st in ipairs(runs) do
		ok(st.gameEdges > 150, "the game added its own streets: " .. st.gameEdges)
		-- (2026-10-14 late: a town with most lots free answers why=free instead of open; was open >= 30)
		ok((st.why.open or 0) + (st.why.free or 0) >= 30, whyText(st.why))
	end
	if os.getenv("SQOT_SIM_LOG") then for _, l in ipairs(runs[1].E.logs) do print(l) end end
end)

test("growth demand (NA grid, game streets regardless of frontage): regular builds, most new streets the mod's", function()
	local runs, pool = scenario("NA grid / independent", {})
	ok(pool.minBuilds >= 4, "builds per run >= 4")
	ok(pool.share >= 0.5, string.format("pooled mod share %.2f", pool.share))
	for _, st in ipairs(runs) do
		ok((st.why.demand or 0) >= st.builds, whyText(st.why))
		ok(st.onMod > 0, "houses on our streets")
		-- never far ahead of the houses: the lead's cap plus one 28-edge increment's lots
		ok(st.maxOwnOpen <= st.E.builtLots() * A.OWN_CAP + 28 * 100 / LOT_M, "own open lots " .. st.maxOwnOpen)
	end
end)

test("growth demand (EU organic from the site, demand-sized increments): regular builds, a substantial share", function()
	-- (a European town in 1900: the site picks EU organic, no style.mech, so the increments follow the demand)
	local runs, pool = scenario("EU organic / independent", { names = EU_NAMES, params = { act_on = 3, debug_log = 2 },
		year = 1900 })
	local sizes = {}
	for _, l in ipairs(runs[1].E.logs) do
		local m = l:match("%[SQOT%] PLAN .- maxEdges=(%d+)")
		if m then sizes[#sizes + 1] = m end
	end
	print("        EU organic seed 1 PLAN maxEdges: " .. table.concat(sizes, " "))
	local style
	for _, l in ipairs(runs[1].E.logs) do style = style or l:match("%[SQOT%] STYLE .- style=(%S+)") end
	eq(style, "EU_ORGANIC")
	local varied = false
	for _, m in ipairs(sizes) do if tonumber(m) < A.maxEdges(2) then varied = true end end
	ok(varied, "some increments sized below maxEdges by the demand")
	ok(pool.minBuilds >= 6, "builds per run >= 6")
	ok(pool.share >= 0.45, string.format("pooled mod share %.2f", pool.share))
end)

test("growth demand (game streets only while frontage is short, as in the run): the mod builds, the game builds less", function()
	local runs, pool = scenario("NA grid / frontage", { model = "frontage" })
	local baseGame = 0
	for _, seed in ipairs(SEEDS) do baseGame = baseGame + simulate({ seed = seed, model = "frontage", demand = false }).gameEdges end
	ok(pool.minBuilds >= 4, "builds per run >= 4")
	ok(pool.share >= 0.35, string.format("pooled mod share %.2f", pool.share))
	ok(pool.gameEdges < baseGame * 0.85, string.format("game streets %d vs %d with the room rule", pool.gameEdges, baseGame))
	for _, st in ipairs(runs) do ok(st.why.demand and st.why.demand >= st.builds, whyText(st.why)) end
	local euRuns, eu = scenario("EU organic / frontage", { model = "frontage", names = EU_NAMES,
		params = { act_on = 3, debug_log = 2 }, year = 1900 })
	-- (2026-10-14: the demand at DENSIFY x density, the free-lot brake: fewer, denser builds; was >= 4)
	print(string.format("        EU organic / frontage: minBuilds %d share %.2f", eu.minBuilds, eu.share))
	-- (2026-10-14 late: the game's own frontage keeps ~43 % of this model's lots open, so the free-lot brake (FREE_AIM)
	-- holds the mod back most checks: EU minBuilds 1, share 0.14-0.18. Was >= 3 / >= 0.25. 2026-10-14, maturity: this
	-- ~1000-person town is young, so no brake: minBuilds 3, share 0.51 again; the thresholds stay)
	-- (2026-10-18, 44 m minimum block: at most one of the 5 runs builds nothing; was minBuilds >= 1. A run that never
	-- builds is a town boxed in by the game's streets from its first check, in either plan: over 40 seeds 10 runs with the
	-- old 40 m plan, 14 with the 44 m plan, 7 with it and a stuck town's wider front (ot_select.FRONT_RELAX); seed 3 is one
	-- of them since the 44 m plan, so "every one of 5 seeds" held with 0.75^5 = 24 % luck before)
	local zero = 0
	for _, st in ipairs(euRuns) do if st.builds == 0 then zero = zero + 1 end end
	ok(zero <= 1, "EU organic: runs that build nothing " .. zero)
	-- (2026-10-14: in this model the game lays whatever frontage the mod leaves out, so the denser demand hands it a
	-- larger share; the real run's mod frontage came on top of the game's: BASELINE_VANILLA.md. Was >= 0.35)
	ok(eu.share >= 0.10, string.format("EU organic pooled mod share %.2f", eu.share))
end)

test("a fast grower (13x in 14 checks): the fast allowance (bank and increments scaled) raises the mod share", function()
	-- (the real-map run 2026-10-13: Bexley 47 -> 462 edges with 3 builds of <= 18 edges, mod ~9 %; the bank sat at its
	-- cap. Here: +20 % target per check, the driver's attention one check interval per cycle)
	local o = { names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, growth = 0.2, cycles = 14 }
	local savedMax, savedBank = A.FAST_MAX, A.BANK_FAST_MAX
	A.FAST_MAX, A.BANK_FAST_MAX = 1, 1
	local _, old = scenario("fast grower, old cap (bank 2 x 18)", o)
	A.FAST_MAX, A.BANK_FAST_MAX = savedMax, savedBank
	local runs, new = scenario("fast grower, fast allowance", o)
	local sizes = {}
	for _, l in ipairs(runs[1].E.logs) do
		local m = l:match("%[SQOT%] PLAN .- maxEdges=(%d+)")
		if m then sizes[#sizes + 1] = m end
	end
	print("        fast grower seed 1 PLAN maxEdges: " .. table.concat(sizes, " "))
	print(string.format("        fast grower pooled share: old %.2f -> new %.2f", old.share, new.share))
	-- (§75 follow-up "one empty row at a time", 2026-10-19: a lane piece beside an empty street of ours waits for its
	-- houses, in both arms: pooled 0.40 -> 0.45 became 0.38 -> 0.43 (+0.047); the allowance still raises the share, the
	-- margin was + 0.05)
	ok(new.share >= old.share + 0.04, string.format("share %.2f vs %.2f", new.share, old.share))
	ok(new.share >= 0.4, string.format("pooled mod share %.2f", new.share))
	-- scarce attention (the run: ~6 checks per town in 40 years): the driver runs only every 3rd cycle
	local o3 = {}
	for k, v in pairs(o) do o3[k] = v end
	o3.checkEvery = 3
	A.FAST_MAX = 1
	local _, old3 = scenario("fast grower, checked every 3rd cycle, old cap", o3)
	A.FAST_MAX = savedMax
	local _, new3 = scenario("fast grower, checked every 3rd cycle, fast allowance", o3)
	print(string.format("        fast grower, scarce checks, pooled share: old %.2f -> new %.2f", old3.share, new3.share))
	-- (round 5, 2026-10-13: the town's form draw changed with the new weights, 0.27 -> 0.34 before, 0.25 -> 0.29 now)
	-- (§75, 2026-10-19: the side-street rule (60 deg at a junction, never relaxed) holds some of the organic lattice's
	-- 45-60 deg junctions in both runs: 0.19 -> 0.22 here, 0.20 -> 0.23 with SIDE off; pooled 0.40 -> 0.45 (0.44 -> 0.51
	-- off). The allowance still raises the share; was + 0.03, the margin of one or two builds)
	ok(new3.share >= old3.share + 0.02, string.format("scarce: share %.2f vs %.2f", new3.share, old3.share))
end)

test("a stalled town (no houses on our streets): the mod waits (why=ahead) instead of laying empty streets", function()
	-- the developer builds nothing at all: our first increment stays empty
	local savedPace = PACE
	PACE = 0
	local st = simulate({ cycles = 12, model = "none" })
	PACE = savedPace
	report("stalled", st)
	ok(st.builds <= 1, "builds " .. st.builds)
	-- (2026-10-14 late: with no houses at all every lot is free, so most checks say why=free; was ahead >= 10)
	ok((st.why.ahead or 0) + (st.why.free or 0) >= 10, whyText(st.why))
end)

test("head start on a new map: HEAD_ROUNDS small increments right away, no fill, no size change; none on a later load", function()
	local savedFill = D.FILL_POINTS
	D.FILL_POINTS = 2
	local function run(gameTime)
		-- (strong characters Off, 2026-10-14: this one-town map would make its town a garden city, ot_character, with one
		-- more head-start round; test_character covers that)
		local E = fakeEngine({ params = { act_on = 3, debug_log = 2, strong_characters = 2 }, names = EU_NAMES, year = 1900,
			gameTime = gameTime })
		local d = D.new(E)
		local sf0 = E.sf[1]
		for _ = 1, 400 do
			d:tick(E.t, nil)
			E.t = E.t + 100000
			if E.pending then
				local p = E.pending
				E.pending = nil
				applySpec(E, p.spec, 1)
				p.cb(true, { cost = 1000, msgs = {} })
			end
		end
		return E, sf0
	end
	local E, sf0 = run(0)
	local head, built, fills, start = {}, 0, 0, nil
	for _, l in ipairs(E.logs) do
		if l:find("[SQOT] HEAD start", 1, true) then start = l
		elseif l:find("[SQOT] HEAD ", 1, true) and not l:find("HEAD done", 1, true) then head[#head + 1] = l
		elseif l:find("[SQOT] BUILT", 1, true) and l:find("trigger=head", 1, true) then built = built + 1
		elseif l:find("[SQOT] FILL", 1, true) and not l:find("skip=", 1, true) then fills = fills + 1 end
	end
	ok(start and start:find("rounds=" .. D.HEAD_ROUNDS .. "-" .. D.HEAD_ROUNDS_MAX, 1, true), tostring(start))
	-- (2026-10-13: rounds by the town's size and form, D.headRounds: 120 buildings, no form -> 3)
	local want = D.headRounds(120, nil, false)
	eq(want, 3)
	eq(#head, want, table.concat(head, "\n"))
	eq(built, want, "every round built")
	-- (§69: a steer town's head start leads at most the steer cap, ot_lockpol.leadCap, beyond the housed streets)
	local hl = tonumber(head[1]:match("leadM=(%d+)"))
	ok(head[1]:find("of=" .. want, 1, true) and hl and hl <= D.HEAD_LEAD_M and hl <= LP.LEAD_CAP[2], head[1])
	local sizes = {}
	for _, l in ipairs(E.logs) do
		local m = l:match("%[SQOT%] PLAN .- maxEdges=(%d+)")
		if m then sizes[#sizes + 1] = tonumber(m) end
	end
	for i = 1, want do eq(sizes[i], D.HEAD_EDGES, "head increments are small") end
	eq(fills, 0, "no fill: no forced growth")
	eq(E.sf[1], sf0, "no size change")
	-- a later load (the game clock past HEAD_GAME_TIME): no head start
	local E2 = run(D.HEAD_GAME_TIME + 1)
	for _, l in ipairs(E2.logs) do ok(not l:find("HEAD", 1, true), l) end
	D.FILL_POINTS = savedFill
end)

test("starting town size: START lines before the head start; Small scales the head start up (more rounds, larger increments)", function()
	local savedFill = D.FILL_POINTS
	D.FILL_POINTS = 2
	local function run(size)
		local E = fakeEngine({ params = { act_on = 3, debug_log = 2, starting_town_size = size }, names = EU_NAMES, year = 1900,
			gameTime = 0 })
		local d = D.new(E)
		for _ = 1, 600 do
			d:tick(E.t, nil)
			E.t = E.t + 100000
			if E.pending then
				local p = E.pending
				E.pending = nil
				applySpec(E, p.spec, 1)
				p.cb(true, { cost = 1000, msgs = {} })
			end
		end
		local out = { start = {}, head = {}, sizes = {} }
		for i, l in ipairs(E.logs) do
			if l:find("[SQOT] START summary", 1, true) then out.summary, out.summaryAt = l, i
			elseif l:find("[SQOT] START ", 1, true) then out.start[#out.start + 1] = l
			elseif l:find("[SQOT] HEAD start", 1, true) then out.headStart, out.headAt = l, i
			elseif l:find("[SQOT] HEAD ", 1, true) and not l:find("HEAD done", 1, true) then out.head[#out.head + 1] = l end
			local m = l:match("%[SQOT%] PLAN .- maxEdges=(%d+)")
			if m then out.sizes[#out.sizes + 1] = tonumber(m) end
			if l:find("[SQOT] INIT", 1, true) then out.init = l end
		end
		return out
	end
	local g, sm = run(1), run(3)
	eq(#g.start, 1, "one START line per town")
	ok(g.start[1]:find("buildings=%d+") and g.start[1]:find("edges=%d+") and g.start[1]:find("length=%d+")
		and g.start[1]:find("cap=%d+"), g.start[1])
	ok(g.summary and g.summary:find("towns=1 townSize=game", 1, true), tostring(g.summary))
	ok(g.summaryAt < g.headAt, "START before the head start")
	ok(g.init:find("townSize=game", 1, true), g.init)
	ok(sm.headStart:find("rounds=" .. (D.HEAD_ROUNDS + 2) .. "-" .. (D.HEAD_ROUNDS_MAX + 2), 1, true), sm.headStart)
	ok(sm.headStart:find("townSize=small", 1, true), sm.headStart)
	ok(#sm.head > #g.head, string.format("more head rounds: %d vs %d", #sm.head, #g.head))
	eq(sm.sizes[1], D.headEdges(nil, 1.5), "larger head increments")
	eq(g.sizes[1], D.HEAD_EDGES)
	print(string.format("        head start: game %d rounds of %d edges, small %d rounds of %d", #g.head, g.sizes[1], #sm.head,
		sm.sizes[1]))
	D.FILL_POINTS = savedFill
end)

--- (§64, 2026-10-15: the streets-only satellites are retired, D.STREET_SAT false. The tests below were measured with
--- them and still check that code path, kept for the dev tools' forced hamlet and an easy way back; the maturity
--- model's grown phase is path-dependent and its streets included the satellites.)
local function withStreetSat(fn)
	return function()
		local was = D.STREET_SAT
		D.STREET_SAT = true
		local okR, err = pcall(fn)
		D.STREET_SAT = was
		assert(okR, err)
	end
end

test("satellite village in the driver: a growing town seeds one (country-lane link + core, all locked, the core dosed), grows it, saves it", withStreetSat(function()
	local SAT = ug_require(F.DIR .. "ot_satellite.lua")
	local saved = { SAT.CHANCE, SAT.MIN_BUILDINGS, D.FILL_POINTS }
	SAT.CHANCE, SAT.MIN_BUILDINGS, D.FILL_POINTS, SP.ON = 1, 50, 2, false
	local events = {}
	local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 24,
		onEngine = function(E)
			E.sendEvent = function(_id, name, param) events[#events + 1] = { name = name, param = param } end
			-- (2026-10-14 late: the core's dose needs DevelopAt; the model's houses ignore it)
			E.developAt = function(_x, _y, _s, _u, cb) cb(true) end
			E.setInitialCaps = function(_t, _l, cb) cb(true) end
		end,
		-- (simulate turns the fill off; the dose points need FILL_POINTS)
		onDriver = function() D.FILL_POINTS = 2 end })
	SAT.CHANCE, SAT.MIN_BUILDINGS, D.FILL_POINTS, SP.ON = saved[1], saved[2], saved[3], true
	local seeds, grows, built, satLines = 0, 0, {}, {}
	for _, l in ipairs(st.E.logs) do
		if l:find("[SQOT] SATELLITE", 1, true) then satLines[#satLines + 1] = l end
		if l:find("[SQOT] SATELLITE built", 1, true) then
			built[#built + 1] = l
			if l:find("kind=seed", 1, true) then seeds = seeds + 1 else grows = grows + 1 end
		end
	end
	for _, l in ipairs(satLines) do print("      " .. l:sub(1, 230)) end
	eq(seeds, 1, "one satellite")
	ok(grows >= 1, "it grows: " .. grows)
	local ev
	for _, e in ipairs(events) do if e.name == SV.EV_SAT then ev = e end end
	ok(ev and ev.param.town and ev.param.x and ev.param.y, "site saved")
	-- the seed build: every edge locked (the dose: below)
	local seedBuilt
	for i, l in ipairs(st.E.logs) do
		if l:find("[SQOT] SATELLITE built", 1, true) and l:find("kind=seed", 1, true) then seedBuilt = i end
	end
	local bl
	for i = seedBuilt - 1, 1, -1 do
		if st.E.logs[i]:find("[SQOT] BUILT", 1, true) then bl = st.E.logs[i] break end
	end
	ok(bl:find("[SQOT] BUILT", 1, true), bl)
	local e, lk = bl:match(" edges=(%d+)"), bl:match(" locked=(%d+)")
	eq(e, lk, "all locked: " .. bl)
	-- (2026-10-14 late) the link went out as a country lane, its core got a dose (lane end) at the seed build
	local seedPlan
	for _, l in ipairs(satLines) do if l:find("kind=seed", 1, true) and l:find(" laneEdges=", 1, true) then seedPlan = l end end
	ok(seedPlan and tonumber(seedPlan:match(" laneEdges=(%d+)")) > 0, tostring(seedPlan))
	ok(tonumber(seedPlan:match(" straight=(%d+)")) <= SAT.MAX_STRAIGHT, seedPlan)
	local dosed = false
	for i = 1, math.min(#st.E.logs, seedBuilt + 4) do
		local l = st.E.logs[i]
		if l:find("[SQOT] FILL town", 1, true) and l:find("why=leadEnd", 1, true) then dosed = true end
	end
	ok(dosed, "the core dosed")
	-- the satellite sits 0.65-1.2 km out (2026-10-14 late; was 0.8-1.5)
	local sx, sy = ev.param.x, ev.param.y
	local d = math.sqrt(sx * sx + sy * sy)
	ok(d >= 600 and d <= 1250, "distance " .. d)
end))

test("wedge frame in the driver: an armed town frames the game's wedge tips with locked streets, then builds as usual", function()
	local saved = D.FILL_POINTS
	D.FILL_POINTS = 0
	local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 16,
		onDriver = function(d)
			local orig = d.styleFor
			d.styleFor = function(self, job, g, sv)
				job.shape = job.shape or "fingers"
				return orig(self, job, g, sv)
			end
		end })
	D.FILL_POINTS = saved
	local plans, builts, frameBuilt = {}, 0, nil
	for i, l in ipairs(st.E.logs) do
		if l:find("[SQOT] FRAME", 1, true) and l:find("outcome=plan", 1, true) then plans[#plans + 1] = l end
		if l:find("[SQOT] FRAME", 1, true) and l:find("outcome=built", 1, true) then
			builts = builts + 1
			frameBuilt = frameBuilt or i
		end
	end
	for _, l in ipairs(plans) do print("      " .. l:sub(1, 200)) end
	ok(#plans >= 1, "a frame planned")
	ok(builts >= 1, "a frame built")
	-- the frame's BUILT line: every edge locked
	local bl
	for i = frameBuilt - 1, 1, -1 do
		if st.E.logs[i]:find("[SQOT] BUILT", 1, true) then bl = st.E.logs[i] break end
	end
	ok(bl ~= nil, "BUILT before FRAME built")
	eq(bl:match(" edges=(%d+)"), bl:match(" locked=(%d+)"), "all locked: " .. tostring(bl))
	ok(st.builds > builts, string.format("normal builds too: %d builds, %d frames", st.builds, builts))
	-- PLAN lines carry the wedge reserve
	local wl = false
	for _, l in ipairs(st.E.logs) do
		if l:find("[SQOT] PLAN", 1, true) and l:match(" wedgeHeld=%d+@%d+") then wl = true break end
	end
	ok(wl, "PLAN wedgeHeld=n@coreR")
end)

test("frame refused for one link (real map run 2026-10-13_0342_sqot, Aylsham): the prune drops that link and the rest is sent, not the same plan again", function()
	local saved = D.FILL_POINTS
	D.FILL_POINTS = 0
	local badKey, refusedWith, sentFrames = nil, 0, {}
	local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 16,
		onEngine = function(E)
			E.precheck = function(p, _ctx)
				local spec = p.spec or { edges = {} }
				local hit, frame = false, false
				for _, e in ipairs(spec.edges) do
					local k = tostring(e.key or "")
					if k:find("^frame:") then
						frame = true
						badKey = badKey or k
						if k == badKey then hit = true end
					end
				end
				if hit then
					refusedWith = refusedWith + 1
					return { ok = false, msgs = { "Collision" }, collisions = 2, buildings = 0, cost = 0, us = 1000,
						partners = { 999999, 999999 } }
				end
				if frame then sentFrames[#sentFrames + 1] = #spec.edges end
				return { ok = true, msgs = {}, collisions = 0, buildings = 0, cost = 1000, us = 1000 }
			end
		end,
		onDriver = function(d)
			local orig = d.styleFor
			d.styleFor = function(self, job, g, sv)
				job.shape = job.shape or "fingers"
				return orig(self, job, g, sv)
			end
		end })
	D.FILL_POINTS = saved
	local builts, refusedFrames, pruned = 0, 0, 0
	for _, l in ipairs(st.E.logs) do
		if l:find("[SQOT] FRAME", 1, true) and l:find("outcome=built", 1, true) then builts = builts + 1 end
		if l:find("[SQOT] FRAME", 1, true) and l:find("outcome=refused", 1, true) then refusedFrames = refusedFrames + 1 end
		if l:find("[SQOT] FRAME", 1, true) and l:find("outcome=pruned", 1, true) then pruned = pruned + 1 end
	end
	ok(badKey ~= nil, "a frame link was planned")
	ok(refusedWith >= 1, "the bad link was pre-checked")
	ok(pruned >= 1, "FRAME outcome=pruned")
	ok(builts >= 1, "the other links built: " .. builts)
	eq(refusedFrames, 0, "no frame refused for one link")
	print(string.format("        frame link %s refused %d x; %d frames built, sent sizes %s", badKey, refusedWith, builts,
		table.concat(sentFrames, ",")))
end)

test("lane ahead in the driver: a young town lays one locked country lane out from its edge, a town street T at its end, saved", function()
	local LD = ug_require(F.DIR .. "ot_lead.lua")
	local SAT = ug_require(F.DIR .. "ot_satellite.lua")
	local saved = { LD.CHANCE, LD.MIN_BUILDINGS, SAT.CHANCE, D.FILL_POINTS }
	LD.CHANCE, LD.MIN_BUILDINGS, SAT.CHANCE, D.FILL_POINTS = 1, 20, 0, 2
	local events = {}
	local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 16,
		onEngine = function(E)
			E.sendEvent = function(_id, name, param) events[#events + 1] = { name = name, param = param } end
		end })
	LD.CHANCE, LD.MIN_BUILDINGS, SAT.CHANCE, D.FILL_POINTS = saved[1], saved[2], saved[3], saved[4]
	local plans, builts, builtAt = {}, 0, nil
	for i, l in ipairs(st.E.logs) do
		if l:find("[SQOT] LEADLANE", 1, true) then
			plans[#plans + 1] = l
			if l:find("outcome=built", 1, true) then builts = builts + 1; builtAt = builtAt or i end
		end
	end
	for _, l in ipairs(plans) do print("      " .. l:sub(1, 260)) end
	eq(builts, 1, "one lane ahead")
	local ev
	for _, e in ipairs(events) do if e.name == SV.EV_LEAD then ev = e end end
	ok(ev and ev.param.town, "saved on the frame")
	-- its BUILT line: only the lane edges locked (the far end's town streets stay open for the town)
	local bl
	for i = builtAt - 1, 1, -1 do
		if st.E.logs[i]:find("[SQOT] BUILT", 1, true) then bl = st.E.logs[i] break end
	end
	local e, lk = tonumber(bl:match(" edges=(%d+)")), tonumber(bl:match(" locked=(%d+)"))
	-- (§65: a "mod"-locked town locks the far end's town streets too, every street the mod builds; the legacy lock left
	-- them open for the game)
	if bl:find("lockMode=mod", 1, true) then eq(lk, e, "every street locked: " .. bl)
	else ok(lk >= 2 and lk < e, "lane locked, end open: " .. bl) end
	-- (run 2240: the far end gets a dose, so its houses start there; simulate() runs with D.FILL_POINTS = 0, so the fill
	-- kind is checked directly: a job with the far end's points is a dose whatever the town's shape)
	local k, why = D.fillKind({ fill = "dose", fillPts = { { 0, 0 } }, style = {} }, {}, nil, nil, 0, 0, nil)
	eq(k, "dose"); eq(why, "leadEnd")
	local planL
	for _, l in ipairs(plans) do if l:find("outcome=plan", 1, true) then planL = l end end
	ok(planL and planL:find("endJoined=(%d+)/%1"), tostring(planL))
end)

test("Works in the driver: on a new map a grown town creates one industrial town (10/10/200) once, saves it, fills it", function()
	local WK = ug_require(F.DIR .. "ot_works.lua")
	local LD = ug_require(F.DIR .. "ot_lead.lua")
	local SAT = ug_require(F.DIR .. "ot_satellite.lua")
	local saved = { WK.CHANCE, WK.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE, D.FILL_POINTS, WK.NEIGHBOUR_MIN }
	WK.CHANCE, WK.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE, D.FILL_POINTS, SP.ON = 1, 20, 0, 0, 2, false
	local events, creates, grows = {}, {}, {}
	local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 16, gameTime = 1000,
		onEngine = function(E)
			E.sendEvent = function(_id, name, param) events[#events + 1] = { name = name, param = param } end
			local extra = nil
			local towns0 = E.towns
			E.towns = function()
				local l = towns0()
				if extra then l[#l + 1] = extra end
				return l
			end
			-- (2026-10-14 late: the new town is claimed by its name and its position near the site)
			local name0, box0 = E.name, E.boxCentre
			E.name = function(t) if t == 999 and creates[1] then return creates[1].name end return name0(t) end
			E.boxCentre = function(t) if t == 999 and creates[1] then return creates[1].x, creates[1].y end return box0(t) end
			E.createTown = function(o, cb)
				creates[#creates + 1] = o
				extra = 999
				cb(true)
				return true, {}
			end
			E.growTown = function(t, f, cb) grows[#grows + 1] = { t, f }; cb(true) end
		end })
	WK.CHANCE, WK.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE, D.FILL_POINTS, SP.ON = saved[1], saved[2], saved[3], saved[4], saved[5], true
	local lines = {}
	for _, l in ipairs(st.E.logs) do if l:find("[SQOT] WORKS", 1, true) then lines[#lines + 1] = l end end
	for _, l in ipairs(lines) do print("      " .. l:sub(1, 240)) end
	eq(#creates, 1, "one Works")
	eq(creates[1].caps[3], 200)
	-- (the fixture's name list is German; since 2026-10-14 (NEXT_PHASE_BRIEF 47, ot_offname) the parent's name or a
	-- German company / site compound: "Growville100-Werk", "Hammerhausen", "Kolonie Ewald")
	local OFF = ug_require(F.DIR .. "ot_offname.lua")
	local okDe = false
	for _, f in ipairs(OFF.parentForms("de", "works")) do
		if creates[1].name == (f:gsub("%%s", "Growville100")) then okDe = true end
	end
	for _, w in ipairs({ "hausen", "hütte", "Kolonie", "Siedlung", "Zeche", "Grube", "Schacht", "dorf", "feld", "stadt",
		"bach", "tal", "berg", "scheid", "hafen", "Neu-" }) do
		if creates[1].name:find(w, 1, true) then okDe = true end
	end
	-- (or the generator's own industrial name: Landscape names run the generator since NEXT_PHASE_BRIEF 49)
	for _, l in ipairs(lines) do if l:find("event=create", 1, true) and l:find("src=generated", 1, true) then okDe = true end end
	ok(okDe, creates[1].name)
	ok(creates[1].name:find("Works", 1, true) == nil, "no English words: " .. creates[1].name)
	local ev
	for _, e in ipairs(events) do if e.name == SV.EV_WORKS then ev = e end end
	ok(ev and ev.param.town == 999 and ev.param.parent, "saved")
	eq(#grows, 1); eq(grows[1][1], 999)
	local d2 = math.sqrt(creates[1].x ^ 2 + creates[1].y ^ 2)
	ok(d2 >= 790 and d2 <= 1510, "0.8-1.5 km out: " .. d2)
	-- an old map (not fresh) never creates one
	creates = {}
	WK.CHANCE, WK.MIN_BUILDINGS = 1, 20
	simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 8,
		onEngine = function(E) E.createTown = function(o, cb) creates[#creates + 1] = o; cb(true); return true, {} end end })
	WK.CHANCE, WK.MIN_BUILDINGS = saved[1], saved[2]
	eq(#creates, 0, "not on an old save")
end)

test("districts in the driver (2026-10-14): a grown town founds a residential town on a terrace and saves it", function()
	local WK = ug_require(F.DIR .. "ot_works.lua")
	local DT = ug_require(F.DIR .. "ot_district.lua")
	local LD = ug_require(F.DIR .. "ot_lead.lua")
	local SAT = ug_require(F.DIR .. "ot_satellite.lua")
	local T = ug_require(F.DIR .. "ot_terrain.lua")
	local saved = { WK.CHANCE, DT.CHANCE, DT.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE, D.FILL_POINTS }
	WK.CHANCE, DT.CHANCE, DT.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE, D.FILL_POINTS = 0, 1, 20, 0, 0, 2
	SP.ON = false
	-- a terrace 30 m up beyond 650 m all round: every direction an "upper" site
	local terrace = T.sampler(function(x, y)
		local d = math.sqrt(x * x + y * y)
		return 20 + 30 * math.max(0, math.min(1, (d - 400) / 400))
	end)
	local events, creates = {}, {}
	local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 16, gameTime = 1000,
		onEngine = function(E)
			E.sampler = function() return terrace end
			E.sendEvent = function(_id, name, param) events[#events + 1] = { name = name, param = param } end
			local extra = nil
			local towns0 = E.towns
			E.towns = function()
				local l = towns0()
				if extra then l[#l + 1] = extra end
				return l
			end
			local name0, box0 = E.name, E.boxCentre
			E.name = function(t) if t == 888 and creates[1] then return creates[1].name end return name0(t) end
			E.boxCentre = function(t) if t == 888 and creates[1] then return creates[1].x, creates[1].y end return box0(t) end
			E.createTown = function(o, cb)
				creates[#creates + 1] = o
				extra = 888
				cb(true)
				return true, {}
			end
			E.growTown = function(_t, _f, cb) cb(true) end
		end })
	WK.CHANCE, DT.CHANCE, DT.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE, D.FILL_POINTS = table.unpack(saved)
	SP.ON = true
	local lines = {}
	for _, l in ipairs(st.E.logs) do if l:find("[SQOT] DISTRICT", 1, true) then lines[#lines + 1] = l end end
	for _, l in ipairs(lines) do print("      " .. l:sub(1, 240)) end
	eq(#creates, 1, "one district (the second waits for the first's link)")
	eq(creates[1].caps[1], DT.CAPS[1])
	ok(creates[1].name:find("Growville100", 1, true) or creates[1].name:find("rowville100", 1, true), creates[1].name)
	local ev
	for _, e in ipairs(events) do if e.name == SV.EV_WORKS and e.param.kind == "district" then ev = e end end
	ok(ev and ev.param.town == 888, "saved as a district")
	local d = math.sqrt(creates[1].x ^ 2 + creates[1].y ^ 2)
	ok(d >= 590 and d <= 1510, "0.6-1.5 km: " .. d)
	ok(lines[1]:find("kind=upper", 1, true), lines[1])
end)

test("created towns (2026-10-14 late, run 0119): concurrent creates resolve to the right towns by name and site, or stay unidentified; one in flight", function()
	local WK = ug_require(F.DIR .. "ot_works.lua")
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 }, names = EU_NAMES })
	local towns = { [1] = { "Winchcombe", 0, 0 }, [2] = { "Penkridge", 5000, 0 } }
	local list = { 1, 2 }
	E.towns = function() local l = {} for _, id in ipairs(list) do l[#l + 1] = id end return l end
	E.name = function(t) return towns[t] and towns[t][1] end
	E.boxCentre = function(t) if towns[t] then return towns[t][2], towns[t][3] end end
	local events, notes = {}, {}
	-- (the new-town notifications, 2026-10-17, go to their own list)
	E.sendEvent = function(id, _name, param)
		if id == "Notifications" then notes[#notes + 1] = param else events[#events + 1] = param end
	end
	E.growTown = function(_, _, cb) cb(true) end
	local d = D.new(E)
	d.saved = {}
	local now = 1e6
	local before = { [1] = true, [2] = true }
	local wA = { phase = "create", kind = "district", name = "Winchcombe Heath", site = { x = 800, y = 0 }, sentUs = now,
		before = before, created = true }
	local wB = { phase = "create", kind = "district", name = "Penkridge Sands", site = { x = 5600, y = 0 }, sentUs = now,
		before = before, created = true }
	local sA, sB = d:townState(1), d:townState(2)
	sA.districts, sB.districts = { wA }, { wB }
	-- both new towns are in the list when the answers come (the old "a town not in my list" rule gave both the same one)
	towns[10] = { "Penkridge Sands", 5600, 20 }
	towns[11] = { "Winchcombe Heath", 790, 10 }
	list = { 1, 2, 10, 11 }
	d:offshootCreated(1, sA, wA, now + 1e5)
	d:offshootCreated(2, sB, wB, now + 1e5)
	eq(wA.town, 11, "Winchcombe's own")
	eq(wB.town, 10, "Penkridge's own")
	eq(events[1].town, 11); eq(events[1].x, 800, "the site saved")
	-- a Works whose name turns up far from its site (another parent's town of that name): waits, then never claimed
	local wC = { phase = "create", kind = "works", name = "Heywood Works", site = { x = -3000, y = 0 }, sentUs = now,
		before = before, created = true }
	local sC = d:townState(3)
	sC.works = wC
	towns[12] = { "Heywood Works", 9000, 9000 }
	list = { 1, 2, 10, 11, 12 }
	d:offshootCreated(3, sC, wC, now + 1e5)
	eq(wC.town, nil, "waits")
	d:offshootCreated(3, sC, wC, now + (D.WORKS_CREATE_TIMEOUT_S + 1) * 1e6)
	eq(wC.town, nil, "never claimed")
	eq(sC.works, nil)
	eq(sC.worksTries, D.WORKS_TRIES, "no second try this session")
	local un = 0
	for _, l in ipairs(E.logs) do if l:find("why=unidentified", 1, true) then un = un + 1 end end
	eq(un, 1, "one unidentified line")
	eq(#events, 2, "two claims saved")
	eq(#notes, 2, "one notification per claimed town")
	eq(notes[1].params.town, 11); eq(notes[1].params.parent, 1); eq(notes[1].params.kind, "district")
	eq(notes[1].params.name, "Winchcombe Heath"); eq(notes[1].params.parentName, "Winchcombe")
	eq(notes[1].type, "square_organic_towns::/organic_towns/notify/ot_new_town.script")
	d:noteNewTown(11, 1, "district")
	eq(#notes, 2, "never twice in a session")
	-- one creation in flight map-wide, let go after twice the timeout
	d.createInFlight = { town = 1, rec = { phase = "create" }, sentUs = now }
	ok(d:createBusy(now + 1e6), "busy")
	ok(not d:createBusy(now + (2 * D.WORKS_CREATE_TIMEOUT_S + 1) * 1e6), "let go")
	-- the pure picker: by name (spaces / underscores), near the site, ambiguity
	eq(WK.identify({ { id = 5, name = "A_B", x = 0, y = 0 } }, "A B", 10, 0), 5)
	eq(select(2, WK.identify({ { id = 5, name = "A B", x = 5000, y = 0 } }, "A B", 0, 0)), "far")
	eq(select(2, WK.identify({ { id = 5, name = "Z", x = 0, y = 0 } }, "A B", 0, 0)), "none")
	eq(select(2, WK.identify({ { id = 5, name = "A B", x = 0, y = 0 }, { id = 6, name = "A B", x = 10, y = 0 } }, "A B", 0, 0)),
		"ambiguous")
	eq(WK.identify({ { id = 5, name = "A B" } }, "A B", 0, 0), 5, "position unknown: the name")
end)

test("load check in the driver (2026-10-14 late): the run-0119 save's wrong claim dropped, lost creates adopted by their parent", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 }, names = EU_NAMES })
	local towns = { [29] = { "Winchcombe", 7000, -7500 }, [36] = { "Penkridge", 3300, 7100 }, [41] = { "Ringwood", -4800, 4700 },
		[42] = { "Heywood", 7000, -2500 }, [128852] = { "Penkridge Sands", 3176, 6528 },
		[147514] = { "Heywood Works", 7517, -3115 }, [87691] = { "Winchcombe Heath", 7256, -6911 }, [50] = { "Settle", 0, 0 } }
	E.towns = function() local l = {} for id in pairs(towns) do l[#l + 1] = id end table.sort(l) return l end
	E.name = function(t) return towns[t] and towns[t][1] end
	E.boxCentre = function(t) if towns[t] then return towns[t][2], towns[t][3] end end
	local events = {}
	E.sendEvent = function(_, _name, param) events[#events + 1] = param end
	-- the save as the race left it (first event wins in applyWorks): Ringwood "owns" Heywood Works as a district
	local s0 = { v = SV.VERSION, frames = {}, known = {}, fresh = true }
	for _, t in ipairs({ 29, 36, 41, 42 }) do s0 = SV.applyFrame(s0, { town = t, a = 0, x = towns[t][2], y = towns[t][3] }) end
	s0.known, s0.fresh = {}, true
	s0 = SV.applyWorks(s0, { parent = 36, town = 128852, kind = "district" })
	s0 = SV.applyWorks(s0, { parent = 41, town = 147514, kind = "district" })
	local d = D.new(E)
	d:offshootCheck(1e6, s0)
	local by = {}
	for _, e in ipairs(events) do by[#by + 1] = string.format("%s:%s:%s", e.kind, e.town, tostring(e.parent)) end
	local txt = table.concat(by, " ")
	ok(txt:find("drop:147514:41", 1, true), txt)
	ok(txt:find("works:147514:42", 1, true), "Heywood adopts its Works: " .. txt)
	ok(txt:find("district:87691:29", 1, true), "Winchcombe adopts its Heath: " .. txt)
	ok(not txt:find(":128852:", 1, true), "the right claim untouched: " .. txt)
	ok(not txt:find(":50:", 1, true), "an ordinary town untouched")
	-- applied in order, the save ends right
	local s1 = s0
	for _, e in ipairs(events) do s1 = SV.applyWorks(s1, e) end
	eq(SV.districtSet(s1)[147514], nil); eq(SV.worksSet(s1)[147514], true); eq(SV.frame(s1, 42).works, 147514)
	eq(SV.frame(s1, 41).districts, nil); eq(SV.districtSet(s1)[87691], 29); eq(SV.districtSet(s1)[128852], 36)
	-- once per session
	local n = #events
	d:offshootCheck(2e6, s1)
	eq(#events, n)
end)

test("Satellite towns setting (2026-10-14 late): Off founds no Works or district; Residential only no Works", function()
	local PA = ug_require(F.DIR .. "ot_params.lua")
	eq(PA.parse({}).satelliteTowns, "on")
	eq(PA.parse({ satellite_towns = 4 }).satelliteTowns, "off")
	local d = D.new(fakeEngine({ params = { act_on = 3 } }))
	d.opts = { satelliteTowns = "off" }
	ok(not d:offshootAllowed("works") and not d:offshootAllowed("district"), "off")
	d.opts = { satelliteTowns = "residential" }
	ok(not d:offshootAllowed("works") and d:offshootAllowed("district"), "residential")
	d.opts = { satelliteTowns = "industrial" }
	ok(d:offshootAllowed("works") and not d:offshootAllowed("district"), "industrial")
	local WK = ug_require(F.DIR .. "ot_works.lua")
	local DT = ug_require(F.DIR .. "ot_district.lua")
	local LD = ug_require(F.DIR .. "ot_lead.lua")
	local SAT = ug_require(F.DIR .. "ot_satellite.lua")
	local sv = { WK.CHANCE, WK.MIN_BUILDINGS, DT.CHANCE, DT.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE }
	WK.CHANCE, WK.MIN_BUILDINGS, DT.CHANCE, DT.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE = 1, 20, 1, 20, 0, 0
	local creates = 0
	simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2, satellite_towns = 4 }, year = 1900, cycles = 10,
		gameTime = 1000, onEngine = function(E)
			E.createTown = function(_o, cb) creates = creates + 1; cb(true); return true, {} end
		end })
	WK.CHANCE, WK.MIN_BUILDINGS, DT.CHANCE, DT.MIN_BUILDINGS, LD.CHANCE, SAT.CHANCE = table.unpack(sv)
	eq(creates, 0, "Off: no create")
end)

test("density (2026-10-14): a sparse town of 250+ buildings under 4.5 persons per building gets the upward dose", function()
	local UP = ug_require(F.DIR .. "ot_upward.lua")
	eq(UP.decide({ buildings = 600, persons = 1800 }), "sparse")
	eq(UP.decide({ buildings = 600, persons = 3000 }), nil)
	-- (2026-10-14 late: SPARSE_BUILDINGS 400 -> 250, SPARSE_PB 4.0 -> 4.5)
	eq(UP.decide({ buildings = 300, persons = 600 }), "sparse")
	eq(UP.decide({ buildings = 200, persons = 400 }), nil)
	eq(UP.decide({ buildings = 600, persons = 2600 }), "sparse", "4.33 per building")
	eq(UP.cut(600, "sparse"), UP.CUT_SPARSE)
end)

test("level weights (2026-10-14 late): strength from persons per building, weights toward bigger buildings, who", function()
	local UP = ug_require(F.DIR .. "ot_upward.lua")
	eq(UP.levelK(6.4), 0, "vanilla's density: none")
	eq(UP.levelK(UP.PB_AIM), 0)
	eq(UP.levelK(2.5), 1)
	eq(UP.levelK(2.9), 0.75, "the run's 2.9: (4.5 - 2.9) / 2 = 0.8 -> 0.75")
	eq(UP.levelK(3.5), 0.5)
	local w = UP.levelWeights(1)
	eq(#w, 3)
	eq(w[1][4], 1)
	ok(w[1][1] < w[1][2] and w[1][2] < w[1][3] and w[1][3] < w[1][4], "rising with the level")
	near(w[1][1], math.floor(1 / (1 + UP.LV_STEP) ^ 3 * 1000 + 0.5) / 1000, 1e-9)
	-- (2026-10-15: top = 2, a 1900 town: a grown town's pb tilt is the era's; from 1950 a plain grown town keeps the
	-- engine's weights, LV_MATURE_K)
	local base = { buildings = 600, pb = 2.9, custom = false, ours = 0, on = true, nowUs = 1e9, town = 5, top = 2 }
	local function dec(over)
		local o = {}
		for k, v in pairs(base) do o[k] = v end
		for k, v in pairs(over or {}) do o[k] = v end
		return UP.levelDecide(o)
	end
	eq(select(1, dec()), "set")
	eq(select(2, dec()), 0.75)
	eq(select(3, dec({ on = false })), "notNew", "existing maps: never")
	eq(select(3, dec({ custom = true })), "player", "a player's own weights: never touched")
	eq(select(1, dec({ custom = true, ours = 0.75 })), nil, "ours at the same strength: nothing")
	eq(select(3, dec({ custom = true, ours = 0.75 })), "same")
	eq(select(1, dec({ custom = true, ours = 0.5 })), "set", "ours, sparser now: stronger")
	eq(select(3, dec({ buildings = 100 })), "small")
	-- (2026-10-14) grown towns only; (2026-10-15, NEXT_PHASE_BRIEF 58) by the level maturity: persons or buildings
	eq(select(3, dec({ mat = 0.3, buildings = 400 })), "young")
	eq(select(1, dec({ mat = 0.3, buildings = 400, custom = true, ours = 0.5 })), nil, "ours stay on a young town (until the clear rule)")
	eq(select(3, dec({ mat = 0.3 })), "hold", "600 buildings read half grown: the blend's hold, never level 1 alone")
	ok(select(2, dec({ mat = 0.5 })) < select(2, dec({ mat = 1 })), "half grown: a tilt below the grown town's")
	eq(UP.levelK(2.5, 0.5), 0.5)
	eq(UP.levelK(2.5), 1)
	eq(select(3, dec({ last = 1e9 - 10e6 })), "gap")
	eq(select(3, dec({ pb = 5 })), "dense")
	eq(select(3, dec({ pb = 5, custom = true, ours = 0.5 })), "keep", "between the aim and the clear line: kept")
	eq(select(1, dec({ pb = 6, custom = true, ours = 0.5 })), "clear", "dense again: back to the game's default")
	eq(UP.levelShares({ 50, 30, 20, 0 }), "50/30/20/0")
	eq(UP.levelText(nil), "-")
	ok(UP.levelText({ actual = { { 1, 1, 0, 0 } }, custom = { { 0.5, 1, 1, 1 } } }):find("a:50/50/0/0", 1, true))
end)

test("level weights in the driver: LEVELS set on a new map, saved on the frame, never on a player's weights", function()
	local function run(custom, gameTime, later)
		local sent, events = {}, {}
		local reads = 0
		-- (strong characters Off, 2026-10-14: the one town would be a garden city, which sends no level weights)
		local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2, strong_characters = 2 }, year = 1900,
			cycles = 6, gameTime = gameTime, onEngine = function(E)
				E.levelInfo = function(_t)
					reads = reads + 1
					-- (later: no custom weights at the first sight, `later` from then on: a change that isn't ours)
					local c = custom
					if later ~= nil then c = reads > 2 and later or nil end
					return { custom = c, actual = { { 60, 30, 10, 0 }, { 1, 0, 0, 0 }, { 1, 0, 0, 0 } } }
				end
				E.setLevelWeights = function(t, wts, cb) sent[#sent + 1] = { t = t, w = wts }; cb(true) end
				local se = E.sendEvent
				E.sendEvent = function(id, name, param)
					if name == "square_organic_towns.levels" then events[#events + 1] = param end
					if se then return se(id, name, param) end
				end
			end })
		local lines = {}
		for _, l in ipairs(st.E.logs) do if l:find("[SQOT] LEVELS", 1, true) and l:find("action=", 1, true) then lines[#lines + 1] = l end end
		return sent, events, lines, st
	end
	-- (2026-10-14: weights for grown towns only; this model town has ~1000 persons: made mature, then young)
	local matLo0, matHi0 = A.MAT_LO, A.MAT_HI
	local sentY = run(nil, 1000)
	eq(#sentY, 0, "a young town: no weights")
	A.MAT_LO, A.MAT_HI = 0, 0
	local sent, events, lines = run(nil, 1000)
	ok(#sent >= 1, "weights sent")
	ok(sent[1].w and sent[1].w[1][4] == 1, "toward the top level")
	ok(#events >= 1 and events[1].k4 >= 1, "saved on the frame (EV_LEVELS)")
	ok(lines[1]:find("action=set", 1, true) and lines[1]:find("lvl=a:60/30/10/0", 1, true), lines[1])
	ok(lines[1]:find("owner=none", 1, true), lines[1])
	-- (2026-10-14, run 2026-10-14_0502_sqot: generated towns carry custom weights the mod never sent. Weights present at
	-- the mod's first sight of the new map are the engine's baseline: LEVELS runs; a clear goes back to them)
	local engineW = { { 0.26, 0.11, 0, 0 }, { 0.26, 0.11, 0, 0 }, { 0.26, 0.11, 0, 0 } }
	local sentE, _, linesE, stE = run(engineW, 1000)
	ok(#sentE >= 1, "the engine's own weights at the first sight: LEVELS runs")
	ok(linesE[1]:find("owner=engine", 1, true), linesE[1])
	local baseLine, readLine = nil, nil
	for _, l in ipairs(stE.E.logs) do
		if l:find("LEVELS event=base", 1, true) then baseLine = l end
		if l:find("LEVELS read at=load", 1, true) then readLine = l end
	end
	ok(baseLine and baseLine:find("from=firstSight", 1, true) and baseLine:find("custom=1", 1, true), tostring(baseLine))
	ok(readLine and readLine:find("custom=1", 1, true), tostring(readLine))
	-- (weights that appear later and aren't ours: the player's)
	local sent2 = run(nil, 1000, { { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 } })
	eq(#sent2, 0, "a player's own weights (changed after the first sight): none sent")
	local sent3 = run(nil, 10e6)
	eq(#sent3, 0, "an old map: none sent")
	A.MAT_LO, A.MAT_HI = matLo0, matHi0
end)

test("saved (2026-10-14 late): the level-weight strength goes on the town's frame (lw), cleared with k4 = 0", function()
	local SV = ug_require(F.DIR .. "ot_saved.lua")
	local s = SV.applyFrame(nil, { town = 7, a = 0.5, x = 10, y = 20 })
	local s2, ch = SV.applyLevels(s, { town = 7, k4 = 3 })
	ok(ch)
	eq(SV.frame(SV.normalize(s2), 7).levels, 0.75)
	local _, ch2 = SV.applyLevels(s2, { town = 7, k4 = 3 })
	ok(not ch2, "idempotent")
	local _, ch3 = SV.applyLevels(s2, { town = 8, k4 = 3 })
	ok(not ch3, "no frame: ignored")
	local s4, ch4 = SV.applyLevels(s2, { town = 7, k4 = 0 })
	ok(ch4)
	eq(SV.frame(s4, 7).levels, nil, "cleared: the game's default")
end)

--- (§65) fn with ot_driver.LOCK_DEFAULT "legacy", restored after.
local function withLegacyLock(fn)
	return function()
		local was = D.LOCK_DEFAULT
		D.LOCK_DEFAULT = "legacy"
		local okR, err = pcall(fn)
		D.LOCK_DEFAULT = was
		assert(okR, err)
	end
end

--- (§68) fn with the street satellites' pod cadence (ot_satpace.growDue: every / phase) drawn with rng.unit, as measured.
local function withLegacyPods(fn)
	return function()
		local was = SP.growDue
		SP.growDue = function(o)
			local oo = {}
			for k, v in pairs(o or {}) do oo[k] = v end
			oo.dv = 1
			return was(oo)
		end
		local okR, err = pcall(fn)
		SP.growDue = was
		assert(okR, err)
	end
end

test("maturity (2026-10-14, run 0302): a young town branches out like before the density round, a grown one builds up", withLegacyLock(withStreetSat(withLegacyPods(function()
	-- (the 0302 run: the brake held 235 of 279 checks from the first years, the mod built 11 % of the edges against 24 %
	-- in 0119. Here one town grows ~430 -> ~5600 persons through MAT_LO / MAT_HI in the frontage model, at the real
	-- PB_AIM, and the game builds bigger on its lots when they run short (the upgrade model). The young phase is
	-- exact (demK 1 there); the grown phase of this model is path-dependent (seeds, other open levels: the gap
	-- between the variants changes sign at VAN_OPEN 1.2), so its checks are directional only. 3 seeds:
	--   no brake 48 % young / 32 % grown, pb 4.31; brake from the start 30 % / 56 %, 4.29; maturity 48 % / 25 %, 4.38)
	-- (§65, 2026-10-15: measured with the legacy lead floor. The "mod" lock's young-town lead floor (ot_driver
	-- LOCK_LEAD_K) moves this path-dependent grown phase: no brake 29 % grown, maturity + mature hold 36 %; the young
	-- phase stays 48 %. The legacy lock here, so the brakes are compared as measured.)
	-- (D.LOCK_DEFAULT is set by withLegacyLock below)
	-- (§68: this grown phase is mostly the street satellite's pod growth (retired since §64; withStreetSat). The pods'
	-- cadence (ot_satpace.growDue every / phase, two 13-letter labels: one draw shifted) draws with rng.decide now,
	-- which moved the grown edges of these 3 seeds 122 / 136 / 63 -> 41 / 10 / 35 (fixed cadences of 3, 4 or 5 swing it as
	-- much either way). withLegacyPods keeps the pods' measured rng.unit cadence: the brakes are compared as measured.)
	local o = { names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, model = "frontage",
		upgrade = true, growth = 0.08, cycles = 34, pbAim = 4.5 }
	local lo0, hi0 = A.MAT_LO, A.MAT_HI
	local function phases(name, lo, hi)
		A.MAT_LO, A.MAT_HI = lo, hi
		local y, m, pbs = { mod = 0, game = 0 }, { mod = 0, game = 0 }, {}
		for _, seed in ipairs({ 1, 2, 3 }) do
			local oo = { seed = seed }
			for k, v in pairs(o) do oo[k] = v end
			local st = simulate(oo)
			for _, c in ipairs(st.perCycle) do
				local ph = c.persons < lo0 and y or (c.persons > hi0 and m or nil)
				if ph then ph.mod, ph.game = ph.mod + c.mod, ph.game + c.game end
			end
			pbs[#pbs + 1] = st.perCycle[#st.perCycle].pb
			if os.getenv("SQOT_MAT_DEBUG") then
				print(name, seed, whyText(st.why))
				local tags = {}
				for _, l in ipairs(st.E.logs) do local t = l:match("%[SQOT%] (%u+)") or "?"; tags[t] = (tags[t] or 0) + 1 end
				local tt = {}
				for t, n in pairs(tags) do tt[#tt + 1] = t .. "=" .. n end
				print(table.concat(tt, " "))
				for _, l in ipairs(st.E.logs) do if l:find("SKIP", 1, true) or l:find("FAILED", 1, true) then print(l:sub(1, 200)) end end
				for _, l in ipairs(st.E.logs) do
					if l:find("[SQOT] CHECK", 1, true) then
						print((l:match("(cap=%S+)") or "") .. " " .. (l:match("(free=%S+)") or "") .. " " .. (l:match("(built=%S+)") or "")
							.. " " .. (l:match("(demK=%S+)") or "") .. " " .. (l:match("(mat=%S+)") or "") .. " " .. (l:match("(why=%S+)") or ""))
					end
				end
				local pc = {}
				for i, c in ipairs(st.perCycle) do pc[#pc + 1] = string.format("%d:%d/%d/%.0f/%.1f", i, c.mod, c.game, c.persons, c.pb or 0) end
				print(table.concat(pc, " "))
			end
		end
		A.MAT_LO, A.MAT_HI = lo0, hi0
		local r = { young = y.mod / math.max(1, y.mod + y.game), grown = m.mod / math.max(1, m.mod + m.game),
			pb = (pbs[1] + pbs[2] + pbs[3]) / 3, youngEdges = y.mod, grownEdges = m.mod }
		print(string.format("        %-34s mod share young %.0f %% (%d edges), grown %.0f %% (%d edges); pb at the end %.2f", name,
			r.young * 100, r.youngEdges, r.grown * 100, r.grownEdges, r.pb))
		return r
	end
	local free = phases("no brake (0119)", 1e9, 2e9)
	local always = phases("brake from the start (0302)", 0, 0)
	-- (2026-10-14, run 0502: the mature hold / cap (A.MATURE_*) off, as in that run)
	local dk0, hm0 = A.MATURE_DEMK, A.MATURE_HOLD_MAT
	A.MATURE_DEMK, A.MATURE_HOLD_MAT = 1, 2
	local mat0502 = phases("maturity without the mature hold", lo0, hi0)
	A.MATURE_DEMK, A.MATURE_HOLD_MAT = dk0, hm0
	local mat = phases("maturity + mature hold (1800-3600)", lo0, hi0)
	ok(mat.grown <= mat0502.grown, string.format("the mature hold: grown share %.2f not over %.2f", mat.grown, mat0502.grown))
	ok(mat.young >= 0.85 * free.young, string.format("young share %.2f near the unbraked %.2f", mat.young, free.young))
	ok(mat.young > always.young, string.format("young share %.2f over the 0302 brake's %.2f", mat.young, always.young))
	ok(mat.grown < free.grown, string.format("grown share %.2f under the unbraked %.2f", mat.grown, free.grown))
	ok(mat.pb > free.pb, string.format("pb at the end %.2f over the unbraked %.2f", mat.pb, free.pb))
end))))

test("offshoot turns (2026-10-14, run 0302): a town that needs no streets is still due for its satellite / Works / district", withStreetSat(function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 }, names = EU_NAMES, year = 1900 })
	local d = D.new(E)
	d.newMap = true
	local now = 1e9
	-- size: buildings, or persons / OFFSHOOT_PB
	eq(D.offshootSize(100, { actual = 1300 }), 325)
	eq(D.offshootSize(400, { actual = 1300 }), 400)
	eq(D.offshootSize(100, nil), 100)
	local small = { buildings = 60, caps = { actual = 300 } }
	eq(select(1, d:offshootTurnDue(TOWN, small, now, nil)), false, "small: nothing due")
	local m = { buildings = 100, caps = { actual = 1300 } }
	local due, what = d:offshootTurnDue(TOWN, m, now, nil)
	ok(due, "a 1300-person town of 100 buildings: due")
	eq(what, "satellite")
	local s = d:townState(TOWN)
	s.offTurnUs = now
	eq(select(1, d:offshootTurnDue(TOWN, m, now + 10e6, nil)), false, "at most every OFFSHOOT_TURN_S")
	s.offTurnUs = nil
	s.satLogged = true   -- (the seeded draw passed it over: rare)
	local due2, what2 = d:offshootTurnDue(TOWN, m, now, nil)
	ok(not due2 or what2 ~= "satellite", "a passed-over satellite is not asked again under the quota size")
	d.newMap = false
	eq(select(1, d:offshootTurnDue(TOWN, m, now, nil)), false, "an old map: no offshoot turns")
end))

test("offshoot turns in the driver (2026-10-14): turns on a new map, a satellite decision without a demand build", withStreetSat(function()
	local function run(gameTime)
		-- (the room rule only, at the game's frontage: every check `open`, no build of its own, as the brake's holds)
		local st = simulate({ names = EU_NAMES, params = { act_on = 3, debug_log = 2 }, year = 1900, cycles = 16,
			gameTime = gameTime, model = "frontage", demand = false })
		local turns, sat, fin = 0, 0, 0
		for _, l in ipairs(st.E.logs) do
			if l:find("[SQOT] OFFSHOOT event=turn", 1, true) then turns = turns + 1 end
			if l:find("[SQOT] SATELLITE", 1, true) then sat = sat + 1 end
		end
		return turns, sat, st
	end
	SP.ON = false
	local turns, sat, st0 = run(1000)
	SP.ON = true
	local satTurn = false
	for _, l in ipairs(st0.E.logs) do
		if l:find("OFFSHOOT event=turn", 1, true) and l:find("for=satellite", 1, true) then satTurn = true end
	end
	ok(satTurn, "a turn for the satellite")
	print(string.format("        new map: %d offshoot turns, %d SATELLITE lines", turns, sat))
	ok(turns >= 1, "offshoot turns: " .. turns)
	ok(sat >= 1, "a satellite decision")
	SP.ON = false
	local turnsOld = run(10e6)
	SP.ON = true
	eq(turnsOld, 0, "an old map: none")
end))
