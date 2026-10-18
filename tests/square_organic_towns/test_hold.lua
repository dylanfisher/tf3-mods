-- Held towns (NEXT_PHASE_BRIEF 52.3, run 2026-10-14_1927_sqot "203 simulated years"): a Works / district town below
-- OFFSHOOT_HOLD_B buildings, or any town whose growth is empty (A.growthEmpty), gets no mod streets of any kind, in
-- normal play and in the dev Simulate's build rounds (unforced jobs); other towns' plans keep out of a held created
-- town's land (the send guard). A created town that grows still gets streets once past the hold.
-- The fake town: test_driver's engine-made 3 x 3 block grid (100 m) with dead-end stubs, every lot built.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local D = ug_require(F.DIR .. "ot_driver.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN = 100
local OTHER = 200        -- a created town east of TOWN (the send guard)
local US_NAMES = "square_names_us_texas::/names/usa/usa.names"

local function dist(p, x, y) return math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) end

local function world()
	local nodes, edges, at, id, eid = {}, {}, {}, 0, 100
	local function node(x, y)
		id = id + 1
		nodes[id] = { id = id, x = x, y = y, z = 10, cfg = true }
		at[x .. ":" .. y] = id
		return id
	end
	for _, x in ipairs({ -100, 0, 100 }) do
		for _, y in ipairs({ -100, 0, 100 }) do node(x, y) end
	end
	local function edge(a, b)
		eid = eid + 1
		local na, nb = nodes[a], nodes[b]
		edges[#edges + 1] = { id = eid, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
			t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
			objects = 0, owned = false, inConstruction = false, parcels = 10, built = 10 }
	end
	for _, x in ipairs({ -100, 0, 100 }) do
		edge(at[x .. ":-100"], at[x .. ":0"])
		edge(at[x .. ":0"], at[x .. ":100"])
	end
	for _, y in ipairs({ -100, 0, 100 }) do
		edge(at["-100:" .. y], at["0:" .. y])
		edge(at["0:" .. y], at["100:" .. y])
	end
	edge(at["100:0"], node(200, 0))
	edge(at["-100:0"], node(-200, 0))
	edge(at["0:100"], node(0, 200))
	edge(at["0:-100"], node(0, -200))
	return { nodes = nodes, edges = edges }
end

--- o.caps (the town's caps), o.buildings (house count, default 49), o.closestTown(x, y), o.boxCentre(t)
local function fakeEngine(o)
	o = o or {}
	local W = world()
	local E = { t = 0, logs = {}, events = {}, prechecks = {}, W = W, bal = 5000000, o = o }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return { nameList = US_NAMES, climate = "::/climates/temperate" } end
		return nil
	end
	function E.modParams() return { act_on = 3, debug_log = 2, style = 2 }, {} end
	function E.gameTime() return 10 * 1e6 end
	function E.year() return 1970 end
	function E.balance() return E.bal end
	function E.towns() return { TOWN } end
	function E.name(t) return "Testville" .. t end
	function E.boxCentre(t)
		if o.boxCentre then return o.boxCentre(t) end
		return 0, 0
	end
	function E.townCaps(_t)
		local c = o.caps or { target = 1000, actual = 900, sizeFactors = { 1, 1, 1 } }
		return { target = c.target, actual = c.actual, sizeFactors = { c.sizeFactors[1], c.sizeFactors[2], c.sizeFactors[3] },
			initials = c.initials }
	end
	function E.town2buildings() return {} end
	function E.townBuildings(_t, _m)
		local pts, builtBy = {}, {}
		local n = o.buildings or 49
		local side = math.max(1, math.ceil(math.sqrt(n)))
		local step = 180 / math.max(1, side - 1)
		for i = 0, n - 1 do
			pts[#pts + 1] = { -90 + (i % side) * step, -90 + math.floor(i / side) * step }
		end
		for _, e in ipairs(W.edges) do builtBy[e.id] = e.built end
		return pts, builtBy
	end
	function E.parcelMap()
		local m = {}
		for _, e in ipairs(W.edges) do m[e.id] = { n = e.parcels } end
		return m
	end
	function E.parcelCount(pd) return pd.n end
	function E.closestTown(x, y)
		if o.closestTown then return o.closestTown(x, y) end
		return TOWN
	end
	function E.streets(x, y, r)
		local out = {}
		for _, e in ipairs(W.edges) do
			if dist(e.p0, x, y) <= r or dist(e.p1, x, y) <= r then out[#out + 1] = e end
		end
		return out
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
	function E.proposal(spec) return { spec = spec } end
	function E.context() return {} end
	function E.precheck(p, _ctx)
		E.prechecks[#E.prechecks + 1] = p.spec
		return { ok = true, msgs = {}, collisions = 0, buildings = 0, cost = 1234, us = 1500 }
	end
	function E.sendBuild(p, _ctx, cb) E.pending = { spec = p.spec, cb = cb } end
	function E.sendEvent(id, name, param) E.events[#E.events + 1] = { id = id, name = name, param = param } end
	function E.growTown() end
	return E
end

--- Normal play: ticks the driver every 0.1 s of fake time; a sent build succeeds at once (its edges added to nothing:
--- the town stays as it is, so it keeps wanting streets). Returns the number of builds sent.
local function play(d, E, n)
	local sent = 0
	for _ = 1, n do
		d:tick(E.t, nil)
		E.t = E.t + 100000
		if E.pending then
			sent = sent + 1
			local p = E.pending
			E.pending = nil
			p.cb(true, { cost = 1000, msgs = {} })
		end
	end
	return sent
end

--- Simulate build rounds (the dev runner's pool): rounds x an unforced job (opts {}) on the town, advanced to its end;
--- a sent build succeeds at once. Returns builds sent, the outcomes.
local function rounds(d, E, n)
	local sent, outs = 0, {}
	d:loadConfig()
	d.phase = "manual"
	for _ = 1, n do
		local outcome
		local job = d:startJob(TOWN, E.t, { onDone = function(_j, o) outcome = o end })
		ok(job ~= nil, "round job started")
		for _ = 1, 400 do
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
			if E.pending then
				sent = sent + 1
				local p = E.pending
				E.pending = nil
				p.cb(true, { cost = 1000, msgs = {} })
			end
		end
		outs[#outs + 1] = outcome or "-"
		E.t = E.t + 60 * 1e6   -- (a simulated chunk later: past the cooldowns)
	end
	return sent, outs
end

local function logsWith(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do if l:find("[SQOT] " .. what, 1, true) then out[#out + 1] = l end end
	return out
end

local NO_GROWTH = { target = 1000, actual = 1000, sizeFactors = { 1, 1, 1 } }
local GROWING = { target = 3000, actual = 1500, sizeFactors = { 3, 3, 3 }, initials = { 600, 200, 200 } }

test("growthEmpty: size factors at 1 and the initial capacity built; growth, a hungry town, bad caps are not", function()
	ok(A.growthEmpty(NO_GROWTH))
	ok(A.growthEmpty({ target = 1000, actual = 960, sizeFactors = { 1, 1, 1.0005 } }))
	ok(not A.growthEmpty(GROWING), "grown size factors")
	ok(not A.growthEmpty({ target = 1000, actual = 900, sizeFactors = { 1, 1, 1 } }), "initial capacity still to build")
	ok(not A.growthEmpty({ target = 1000, actual = 0 / 0, sizeFactors = { 1, 1, 1 } }), "NaN")
	ok(not A.growthEmpty({ target = 0, actual = 0, sizeFactors = { 1, 1, 1 } }), "zero target")
	ok(not A.growthEmpty({ target = 1000, actual = 1000, sizeFactors = { 0 / 0, 1, 1 } }), "NaN factor")
	ok(not A.growthEmpty({ target = 1000, actual = 1000 }), "no size factors")
	ok(not A.growthEmpty(nil))
end)

test("holdWhy: below the hold, no growth, the head start of an original town excepted", function()
	local E = fakeEngine()
	local d = D.new(E)
	d.worksTowns = { [TOWN] = true }
	eq(d:holdWhy(TOWN, { buildings = 40, caps = GROWING }, {}), "below")
	eq(d:holdWhy(TOWN, { buildings = 169, caps = NO_GROWTH }, {}), "noGrowth")
	eq(d:holdWhy(TOWN, { buildings = 169, caps = GROWING }, {}), nil)
	eq(d:holdWhy(TOWN, { buildings = 40, caps = NO_GROWTH }, { head = true }), "below", "no head start for a created town")
	d.worksTowns = nil
	eq(d:holdWhy(TOWN, { buildings = 40, caps = GROWING }, {}), nil, "an original town has no building hold")
	eq(d:holdWhy(TOWN, { buildings = 40, caps = NO_GROWTH }, {}), "noGrowth")
	eq(d:holdWhy(TOWN, { buildings = 40, caps = NO_GROWTH }, { head = true }), nil)
	eq(d:holdWhy(TOWN, nil, {}), nil)
end)

test("control: the same town, original and growing, gets streets (the fake wants them)", function()
	local E = fakeEngine({ caps = GROWING })
	local d = D.new(E)
	ok(play(d, E, 3000) >= 1, "built")
	local E2 = fakeEngine({ caps = GROWING })
	local d2 = D.new(E2)
	ok(rounds(d2, E2, 5) >= 1, "built in rounds")
end)

test("a created town with no growth gains no mod streets over many checks; OFFSHOOT hold why= edges=", function()
	-- below the hold, and past it (169 buildings) with empty growth
	for _, b in ipairs({ 40, 169 }) do
		local E = fakeEngine({ caps = NO_GROWTH, buildings = b })
		local d = D.new(E)
		d.worksTowns = { [TOWN] = true }
		eq(play(d, E, 6000), 0, "no build, buildings " .. b)
		eq(#E.prechecks, 0)
		ok(#logsWith(E, "CHECK") >= 3, "checked again and again")
		local h = logsWith(E, "OFFSHOOT event=hold")
		eq(#h, 1, "logged once while nothing changes")
		local why = b < D.OFFSHOOT_HOLD_B and "why=below" or "why=noGrowth"
		ok(h[1]:find(why, 1, true) and h[1]:find("edges=", 1, true), h[1])
		eq(#logsWith(E, "OFFSHOOT event=turn"), 0, "no offshoot turn either")
	end
	-- a growing created town below the hold: held too
	local E = fakeEngine({ caps = GROWING, buildings = 40 })
	local d = D.new(E)
	d.worksTowns = { [TOWN] = true }
	eq(play(d, E, 6000), 0)
end)

test("Simulate build rounds: a created town with no growth gets no streets in any round", function()
	for _, b in ipairs({ 40, 169 }) do
		local E = fakeEngine({ caps = NO_GROWTH, buildings = b })
		local d = D.new(E)
		d.worksTowns = { [TOWN] = true }
		local sent, outs = rounds(d, E, 30)
		eq(sent, 0, "buildings " .. b)
		eq(#E.prechecks, 0)
		for _, o in ipairs(outs) do eq(o, "room") end
	end
end)

test("a created town that grows past the hold gets streets again, in play and in rounds", function()
	local E = fakeEngine({ caps = GROWING, buildings = 169 })
	local d = D.new(E)
	d.worksTowns = { [TOWN] = true }
	ok(play(d, E, 3000) >= 1, "built in play")
	local E2 = fakeEngine({ caps = GROWING, buildings = 169 })
	local d2 = D.new(E2)
	d2.worksTowns = { [TOWN] = true }
	ok(rounds(d2, E2, 5) >= 1, "built in rounds")
	-- the same town crossing the hold mid-run: held, then built
	local E3 = fakeEngine({ caps = GROWING, buildings = 40 })
	local d3 = D.new(E3)
	d3.worksTowns = { [TOWN] = true }
	eq(play(d3, E3, 2000), 0)
	ok(d3:townState(TOWN).hold == "below")
	E3.o.buildings = 169   -- (the town grew past the hold)
	ok(play(d3, E3, 3000) >= 1, "past the hold: built")
	ok(d3:townState(TOWN).hold == false)
end)

test("an original town whose growth is empty gets no streets after the head start", function()
	local E = fakeEngine({ caps = NO_GROWTH })
	local d = D.new(E)
	eq(play(d, E, 6000), 0)
	local h = logsWith(E, "OFFSHOOT event=hold")
	ok(#h >= 1 and h[1]:find("why=noGrowth", 1, true), h[1])
end)

test("send guard: another town's increment into a held created town's land is refused, its pieces left out", function()
	-- the created town OTHER owns everything west of x = -150 (its centre at -400, 0)
	local function eng()
		return fakeEngine({ caps = GROWING,
			closestTown = function(x, _y) if x < -150 then return OTHER end return TOWN end,
			boxCentre = function(t) if t == OTHER then return -400, 0 end return 0, 0 end })
	end
	local function westEdges(E)
		local n = 0
		for _, spec in ipairs(E.prechecks) do
			for _, e in ipairs(spec.edges or {}) do
				if (e.p0[1] + e.p1[1]) / 2 < -150 then n = n + 1 end
			end
		end
		return n
	end
	-- (the demand planner already keeps to the engine's ownership: the guard is the backstop for satellites, lanes
	-- ahead, lead-outs, bridges and frames, planned without the gaps)
	local E = eng()
	local d = D.new(E)
	d.worksTowns = { [OTHER] = true }   -- (never checked: counts as held)
	play(d, E, 3000)
	eq(westEdges(E), 0, "no pre-checked edge in the held town's land")
	-- an increment reaching into it, at the send stage
	local function inc()
		return { edges = {
			{ p0 = { -100, 0 }, p1 = { -140, 0 }, key = "in" },
			{ p0 = { -140, 0 }, p1 = { -200, 0 }, key = "w1" },
			{ p0 = { -200, 0 }, p1 = { -260, 0 }, key = "w2" } } }
	end
	local E2 = eng()
	local d2 = D.new(E2)
	d2.worksTowns = { [OTHER] = true }
	d2:loadConfig()
	d2.phase = "manual"
	local job = d2:startJob(TOWN, E2.t, {})
	job.inc = inc()
	d2:send(job, E2.t)
	eq(#E2.prechecks, 0, "not pre-checked, not sent")
	local g = logsWith(E2, "OFFSHOOT event=hold")
	ok(#g == 1 and g[1]:find("why=guard:unchecked", 1, true) and g[1]:find("by=100", 1, true)
		and g[1]:find("edges=2", 1, true), g[1])
	local ex = d2:townState(TOWN).exclude
	ok(ex.w1 and ex.w2 and not ex["in"], "the pieces in its land left out")
	eq(job.stage, "plan", "a town plan: planned again without them")
	-- after HOLD_REPLANS the refusal path (halved / the first piece left out)
	for _ = 1, D.HOLD_REPLANS do
		job.inc = inc()
		d2:send(job, E2.t)
	end
	eq(#E2.prechecks, 0)
	ok(job.holdReplans == D.HOLD_REPLANS and d2.job == nil, "ended (refused) after the replans")
	-- a held verdict from its check holds as well; a town past its hold does not
	for _, v in ipairs({ { "below", 1 }, { false, 0 } }) do
		local E3 = eng()
		local d3 = D.new(E3)
		d3.worksTowns = { [OTHER] = true }
		d3:townState(OTHER).hold = v[1]
		local j3 = d3:startJob(TOWN, E3.t, {})
		j3.inc = inc()
		eq((d3:heldHits(j3)), v[1] and 2 or 0, tostring(v[1]))
		eq(#logsWith(E3, "OFFSHOOT event=hold"), 0)
	end
end)

test("send guard: a Works link to its own target is not held; the guard is capped and skips far edges", function()
	local E = fakeEngine({ closestTown = function() return OTHER end, boxCentre = function() return 400, 0 end })
	local d = D.new(E)
	d.worksTowns = { [OTHER] = true }
	local inc = { edges = { { p0 = { 300, 0 }, p1 = { 350, 0 }, key = "a" }, { p0 = { 350, 0 }, p1 = { 400, 0 }, key = "b" } } }
	eq((d:heldHits({ town = TOWN, inc = inc, worksPlan = { works = OTHER } })), 0, "the link's own town")
	eq((d:heldHits({ town = TOWN, inc = inc })), 2)
	eq((d:heldHits({ town = OTHER, inc = inc })), 0, "a town's own plan")
	local far = { edges = { { p0 = { 5000, 0 }, p1 = { 5100, 0 }, key = "f" } } }
	eq((d:heldHits({ town = TOWN, inc = far })), 0, "beyond HOLD_GUARD_R: not asked")
	local many = {}
	for i = 1, D.HOLD_GUARD_MAX + 50 do many[1000 + i] = true end
	d.worksTowns = many
	ok(#d:heldOthers(TOWN) <= D.HOLD_GUARD_MAX, "capped")
end)
