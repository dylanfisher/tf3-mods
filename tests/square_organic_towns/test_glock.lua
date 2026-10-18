-- Game-street locking and valves (§67, 2026-10-15; ot_glock + the driver wiring): which edges are locked (mod / game /
-- player / core), the fresh-edge-only rule, the skip rules (bridges, stops, constructions, ...), the budget, caps and
-- backoff, valve placement (open land, forest clearance, not toward water or neighbours), rotation, stubs, the stall
-- guard's extra valve, old saves (no `gk`: the §65 lock only), the saved ids, and the loop caps.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local GL = ug_require(F.DIR .. "ot_glock.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")
local H = ug_require(F.DIR .. "ot_hooks.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN = 7

local function edge(id, x0, y0, x1, y1, extra)
	local e = { id = id, n0 = id * 10, n1 = id * 10 + 1, p0 = { x0, y0, 10 }, p1 = { x1, y1, 10 },
		t0 = { x1 - x0, y1 - y0, 0 }, t1 = { x1 - x0, y1 - y0, 0 }, template = SMALL, lanes = 4, objects = 0,
		owned = false, inConstruction = false, locked = false, etype = "normal" }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

local OLD = -1e9   -- a first-seen stamp long ago (settled)

local function ctxFor(edges, o)
	o = o or {}
	local seen = {}
	for _, e in ipairs(edges) do seen[e.id] = OLD end
	return { own = o.own or {}, core = o.core, built = o.built or {}, bad = o.bad, seen = seen, nowUs = 0,
		valve = o.valve, withHouses = o.withHouses }
end

test("classify: player, other templates, ours (glocked), the mod's (locked or this session), core, game", function()
	local c = ctxFor({}, { own = { [5] = true }, core = { [6] = true } })
	c.seen = { [1] = OLD, [2] = OLD, [3] = OLD, [4] = OLD, [5] = OLD, [6] = OLD, [7] = OLD }
	eq(select(1, GL.classify(edge(1, 0, 0, 100, 0, { owned = true }), c)), "player")
	local k, why = GL.classify(edge(2, 0, 0, 100, 0, { template = "::/infrastructure/street/country_new_small.street_template" }), c)
	eq(k, "other"); eq(why, "template")
	k, why = GL.classify(edge(3, 0, 0, 100, 0, { glocked = true }), c)
	eq(k, "glocked"); eq(why, "locked")
	k, why = GL.classify(edge(4, 0, 0, 100, 0, { locked = true }), c)
	eq(k, "mod"); eq(why, "locked")
	k, why = GL.classify(edge(5, 0, 0, 100, 0), c)
	eq(k, "mod"); eq(why, "mod")
	k, why = GL.classify(edge(6, 0, 0, 100, 0), c)
	eq(k, "core"); eq(why, nil)
	k, why = GL.classify(edge(7, 0, 0, 100, 0), c)
	eq(k, "game"); eq(why, nil)
	-- the core off: left alone
	GL.CORE = false
	k, why = GL.classify(edge(6, 0, 0, 100, 0), c)
	GL.CORE = true
	eq(k, "core"); eq(why, "core")
	-- one-way ring streets are no plain town streets
	eq(select(1, GL.classify(edge(8, 0, 0, 100, 0, { template = "::/infrastructure/street/town/town_new_one_way_small.street_template" }), c)), "other")
end)

test("houses: an edge with buildings is locked (WITH_HOUSES on since the 2026-10-15 probe); off, it is left alone", function()
	local e = edge(1, 0, 0, 100, 0)
	local c = ctxFor({ e }, { built = { [1] = 2 } })
	eq(GL.WITH_HOUSES, true)
	eq(select(2, GL.classify(e, c)), nil, "default: locked with houses")
	c.withHouses = false
	eq(select(2, GL.classify(e, c)), "houses", "the constant off: left alone")
	c.withHouses = nil
	c.built[1] = 0
	eq(select(2, GL.classify(e, c)), nil, "no building: locked")
	c.built[1] = 3
	c.withHouses = true
	eq(select(2, GL.classify(e, c)), nil, "the constant on: locked with houses")
	-- parcels without buildings are fine (the lots come back with the new edge)
	c.withHouses = nil
	c.built[1] = nil
	eq(select(2, GL.classify(e, c)), nil)
end)

test("skip rules: stops / signals, constructions, bridges, tunnels, loops, short, unsettled, refused, valve zones", function()
	local c = ctxFor({})
	local function why(e)
		c.seen[e.id] = c.seen[e.id] or OLD
		return select(2, GL.classify(e, c))
	end
	eq(why(edge(1, 0, 0, 100, 0, { objects = 1 })), "objects")
	eq(why(edge(2, 0, 0, 100, 0, { inConstruction = true })), "construction")
	eq(why(edge(3, 0, 0, 100, 0, { etype = "bridge" })), "bridge")
	eq(why(edge(4, 0, 0, 100, 0, { etype = "tunnel" })), "tunnel")
	local lp = edge(5, 0, 0, 100, 0); lp.n1 = lp.n0
	eq(why(lp), "loop")
	eq(why(edge(6, 0, 0, 3, 0)), "short")
	c.bad = { [7] = true }
	eq(why(edge(7, 0, 0, 100, 0)), "bad")
	-- seen just now: the game may still be building there
	c.seen[8] = 0
	c.nowUs = (GL.SETTLE_S - 1) * 1e6
	eq(why(edge(8, 0, 0, 100, 0)), "settle")
	c.nowUs = GL.SETTLE_S * 1e6
	eq(why(edge(8, 0, 0, 100, 0)), nil)
	-- never seen: settle (the first check only stamps it)
	c.seen[9] = nil
	eq(select(2, GL.classify(edge(9, 0, 0, 100, 0), c)), "settle")
	c.valve = function(e) return e.id == 10 and {} or nil end
	eq(why(edge(10, 0, 0, 100, 0)), "valve")
	-- bad input never throws
	eq(select(2, GL.classify({ id = 11 }, c)), "bad")
end)

test("queue: tips first, game before core, outer first; at most the batch; tally counts ours and the open ones", function()
	local edges = {
		edge(1, 0, 0, 100, 0),                         -- inner, joined at both ends below
		edge(2, 100, 0, 200, 0),
		edge(3, 200, 0, 300, 0),                       -- tip at 300
		edge(4, 0, 0, 0, 100),                         -- tip (core)
		edge(5, 500, 0, 600, 0, { glocked = true, locked = false }),
		edge(6, 700, 0, 800, 0, { locked = true }),
	}
	-- a chain 1-2-3: share nodes
	edges[2].n0 = edges[1].n1; edges[3].n0 = edges[2].n1; edges[4].n0 = edges[1].n0
	local c = ctxFor(edges, { core = { [4] = true } })
	local list, tally = GL.queue(edges, nil, c, { cx = 0, cy = 0, max = 10 })
	eq(#list, 4)
	eq(list[1].id, 3, "the outer game tip first")
	eq(list[2].id, 4, "then the core tip")
	eq(list[3].id, 2, "then the outer of the inner ones")
	eq(tally.glocked, 1)
	eq(tally.open, 4)
	eq(tally.mod, 1)
	local cut = GL.queue(edges, nil, c, { cx = 0, cy = 0, max = 2 })
	eq(#cut, 2)
	-- only the town's lot edges
	local only = GL.queue(edges, { [2] = true }, c, { cx = 0, cy = 0 })
	eq(#only, 1); eq(only[1].id, 2)
end)

test("loop caps: queue, valveCheck, pickValves and pickStub read at most SCAN_MAX entries", function()
	local old = GL.SCAN_MAX
	GL.SCAN_MAX = 50
	local edges = {}
	for i = 1, 400 do edges[i] = edge(i, i * 10, 0, i * 10 + 9, 0) end
	local c = ctxFor(edges)
	local list, tally = GL.queue(edges, nil, c, { cx = 0, cy = 0, max = 1000 })
	ok(#list <= 50 and (tally.game or 0) <= 50, tostring(#list))
	local v = { x = 0, y = 0, a = 0, quota = 1e9 }
	local ids = {}
	for i = 1, 400 do ids[i] = i end
	eq(GL.valveCheck(v, ids, true), nil)
	ok(v.n <= 50)
	local cands = {}
	for i = 1, 400 do cands[i] = { id = i, mx = 300 + i, my = 0, tip = false, kind = "game" } end
	local picks = GL.pickValves(cands, { cx = 0, cy = 0, extR = 200 }, {}, 1)
	eq(#picks, 1)
	GL.SCAN_MAX = old
end)

test("backoff: a refusal pauses the town, doubling to the cap; TOWN_FAILS in a row: off; a success resets", function()
	local st = {}
	local s1 = GL.backoff(st, 0, false)
	eq(s1, GL.BACKOFF_S)
	eq(st.nextUs, GL.BACKOFF_S * 1e6)
	local s2 = GL.backoff(st, 0, false)
	eq(s2, 2 * GL.BACKOFF_S)
	for _ = 3, GL.TOWN_FAILS - 1 do GL.backoff(st, 0, false) end
	ok(not st.off)
	local s, off = GL.backoff(st, 0, false)
	eq(off, true)
	ok(s <= GL.BACKOFF_MAX_S)
	GL.backoff(st, 5, true)
	eq(st.fails, 0); eq(st.nextUs, 5)
end)

-- the valve context of a town at (0, 0), extent 300 m
local function vctx(o)
	o = o or {}
	return { cx = 0, cy = 0, extR = 300, field = o.field, fg = o.fg, gaps = o.gaps, arms = o.arms, wet = o.wet,
		rest = o.rest or {} }
end

-- a land lean toward heading `to` (16 sectors, cos)
local function leanField(to)
	local lean = {}
	for i = 1, 16 do lean[i] = math.cos((i - 1) * 2 * math.pi / 16 - to) end
	return { n = 16, lean = lean, k = 0.3, peak = to }
end

test("valve placement: the land lean's heading wins; too near the centre is no valve", function()
	local ctx = vctx({ field = leanField(0) })
	local east = GL.valveScore(350, 0, false, ctx)
	local west = GL.valveScore(-350, 0, false, ctx)
	ok(east > west, string.format("%.2f > %.2f", east, west))
	local s, why = GL.valveScore(50, 0, false, ctx)
	eq(s, nil); eq(why, "centre")
	-- a dead-end tip scores more; a skeleton arm pulls
	ok(GL.valveScore(0, 350, true, vctx()) > GL.valveScore(0, 350, false, vctx()))
	local armed = vctx({ arms = { math.pi / 2 } })
	ok(GL.valveScore(0, 350, false, armed) > GL.valveScore(350, 0, false, armed))
	local _, w = GL.valveScore(0, 350, false, armed)
	eq(w, "arm")
	local cands = { { id = 1, mx = 350, my = 0, kind = "game" }, { id = 2, mx = -350, my = 0, kind = "game" },
		{ id = 3, mx = 0, my = 350, kind = "game" } }
	local picks = GL.pickValves(cands, ctx, {}, 2)
	eq(#picks, 2)
	eq(picks[1].id, 1, "the favoured heading first")
	eq(picks[1].why, "land")
end)

test("valve placement: never toward dense forest (skeleton clearance), water or a neighbour's gap", function()
	-- woods east of x = 400
	local fg = FO.fromFunction(0, 0, function(x, _y) return x > 400 and 200 or 0 end, 1500, 50)
	local ctx = vctx({ fg = fg })
	local s, why = GL.valveScore(350, 0, false, ctx)
	eq(s, nil); eq(why, "forest")
	ok(GL.valveScore(-350, 0, false, ctx) ~= nil, "open land west")
	-- woods just beside the probe line, within CLEAR_M: also forest
	local fg2 = FO.fromFunction(0, 0, function(_x, y) return (y > 30 and y < 200) and 200 or 0 end, 1500, 50)
	eq(select(2, GL.valveScore(350, 0, false, vctx({ fg = fg2 }))), "forest")
	-- water north
	local wet = function(_x, y) return y > 380 end
	eq(select(2, GL.valveScore(0, 350, false, vctx({ wet = wet }))), "water")
	ok(GL.valveScore(0, -350, false, vctx({ wet = wet })) ~= nil)
	-- a neighbour 1 km south: its gap holds the probe point
	local gp = GP.build({ 0, 0 }, { { x = 0, y = -900, town = 2 } }, 3)
	eq(select(2, GL.valveScore(0, -350, false, vctx({ gaps = gp }))), "neighbour")
	ok(GL.valveScore(0, 350, false, vctx({ gaps = gp })) ~= nil)
	-- picks skip the rejected ones and tally why
	local picks, rej = GL.pickValves({ { id = 1, mx = 350, my = 0 }, { id = 2, mx = -350, my = 0 } }, ctx, {}, 2)
	eq(#picks, 1); eq(picks[1].id, 2); eq(rej.forest, 1)
end)

test("valve placement: valves keep VALVE_SEP apart, from the open ones too; a heading closed lately rests", function()
	local cands = { { id = 1, mx = 350, my = 0 }, { id = 2, mx = 340, my = 60 }, { id = 3, mx = 0, my = 350 } }
	local picks = GL.pickValves(cands, vctx({ field = leanField(0) }), {}, 3)
	eq(#picks, 2, "1 and 2 are too close")
	local open = { { a = 0 } }
	local p2 = GL.pickValves(cands, vctx(), open, 2)
	eq(#p2, 1); eq(p2[1].id, 3)
	eq(#GL.pickValves(cands, vctx(), { { a = 0 }, { a = 2 } }, 2), 0, "enough open")
	-- the east heading closed lately: north wins though the lean says east
	local rested = vctx({ field = leanField(0), rest = { 0 } })
	local p3 = GL.pickValves({ { id = 1, mx = 350, my = 0 }, { id = 3, mx = 0, my = 350 } }, rested, {}, 1)
	eq(p3[1].id, 3)
end)

test("valves wanted: organic 2, grid 1, + 1 big, at most VALVE_MAX, + the stall guard's extra (capped)", function()
	eq(GL.wantValves("organic", 200, 0), 2)
	eq(GL.wantValves("grid", 200, 0), 1)
	eq(GL.wantValves("organic", 600, 0), 3)
	eq(GL.wantValves("grid", 600, 0), 2)
	eq(GL.wantValves("organic", 600, 1), 4)
	eq(GL.wantValves("organic", 600, 99), 3 + GL.VALVE_STALL_MAX)
	eq(GL.wantValves(nil, 600, 1), 0, "no context: none")
	ok(GL.valveQuota("organic") > GL.valveQuota("grid"))
end)

test("valve rotation: a valve closes after its quota of new game streets, after VALVE_CHECKS, or without its anchor", function()
	local v = { x = 0, y = 0, a = 0, quota = 3, z0 = { [1] = true } }
	eq(GL.valveCheck(v, { 1 }, true), nil)
	eq(v.n, 0, "the zone's streets at the opening don't count")
	eq(GL.valveCheck(v, { 1, 2, 3 }, true), nil)
	eq(GL.valveCheck(v, { 1, 2, 3, 4 }, true), "quota")
	local w = { x = 0, y = 0, a = 0, quota = 99 }
	for _ = 1, GL.VALVE_CHECKS - 1 do eq(GL.valveCheck(w, {}, true), nil) end
	eq(GL.valveCheck(w, {}, true), "age")
	eq(GL.valveCheck({ x = 0, y = 0, a = 0 }, {}, false), "gone")
	ok(GL.inZone(v, GL.VALVE_R - 1, 0)); ok(not GL.inZone(v, GL.VALVE_R + 1, 0))
end)

test("valve stub: the heading from the rim's scores; the build leaves its outward tip toward it unlocked", function()
	local a = GL.stubHeading(vctx({ field = leanField(math.pi / 2) }), {})
	ok(math.abs(a - math.pi / 2) < 1e-6, tostring(a))
	-- every rim point wooded: no heading
	local fg = FO.fromFunction(0, 0, function() return 200 end, 1500, 50)
	eq(GL.stubHeading(vctx({ fg = fg }), {}), nil)
	-- an increment: a street north (tip) and one east (tip), joined at node -1
	local inc = {
		{ key = "n", node0 = -1, node1 = -2, p0 = { 0, 200 }, p1 = { 0, 300 } },
		{ key = "e", node0 = -1, node1 = -3, p0 = { 200, 0 }, p1 = { 300, 0 } },
		{ key = "x", node0 = 5, node1 = -1, p0 = { 0, 0 }, p1 = { 10, 10 }, existing = true },
	}
	eq(GL.pickStub(inc, math.pi / 2, 0, 0, 300), "n")
	eq(GL.pickStub(inc, 0, 0, 0, 300), "e")
	eq(GL.pickStub(inc, math.pi, 0, 0, 300), nil, "nothing west")
	eq(GL.pickStub(inc, 0 / 0, 0, 0, 300), nil)
	-- ot_proposal: unlockKeys keeps that one street of a locked build unlocked
	local spec = PR.build({ edges = { { key = "a", entity = -10, node0 = -1, node1 = -2, p0 = { 0, 0, 10 }, p1 = { 50, 0, 10 },
		t0 = { 50, 0, 0 }, t1 = { 50, 0, 0 }, class = "small", template = SMALL },
		{ key = "b", entity = -11, node0 = -2, node1 = -3, p0 = { 50, 0, 10 }, p1 = { 100, 0, 10 },
		t0 = { 50, 0, 0 }, t1 = { 50, 0, 0 }, class = "small", template = SMALL } },
		nodes = { { entity = -1, x = 0, y = 0, z = 10 }, { entity = -2, x = 50, y = 0, z = 10 }, { entity = -3, x = 100, y = 0, z = 10 } } },
		{ sources = { [SMALL] = 900 }, fallback = 900, lock = true, unlockKeys = { b = true } })
	ok(spec ~= nil)
	local byKey = {}
	for _, e in ipairs(spec.edges) do byKey[e.key] = e end
	eq(byKey.a.locked, true)
	eq(byKey.b.locked, nil)
end)

test("saved: frame gk, the old frames without it, the glocked ids (idempotent, capped)", function()
	local s = SV.normalize(nil)
	s = SV.applyFrame(s, { town = TOWN, a = 0, x = 0, y = 0, lm = 1, gk = 1 })
	eq(SV.frame(s, TOWN).gameLock, true)
	s = SV.applyFrame(s, { town = 8, a = 0, x = 0, y = 0, lm = 1 })
	eq(SV.frame(s, 8).gameLock, nil)
	-- frameParam writes gk only with the mod lock
	local style = { axis = 0, centre = { 0, 0 } }
	eq(SV.frameParam(1, style, nil, nil, nil, { lock = "mod", gameLock = true }).gk, 1)
	eq(SV.frameParam(1, style, nil, nil, nil, { lock = "legacy", gameLock = true }).gk, nil)
	eq(SV.frameParam(1, style, nil, nil, nil, { lock = "mod" }).gk, nil)
	-- survives a normalize (the save's round trip)
	eq(SV.frame(SV.normalize(s), TOWN).gameLock, true)
	local changed
	s, changed = SV.applyGlock(s, { town = TOWN, ids = { 11, 12 } })
	eq(changed, true)
	s, changed = SV.applyGlock(s, { town = TOWN, ids = { 12 } })
	eq(changed, false, "idempotent")
	local set = SV.glocked(SV.normalize(s), TOWN)
	ok(set[11] and set[12])
	eq(next(SV.glocked(s, 99)), nil)
	eq(select(2, SV.applyGlock(s, { town = TOWN })), false)
	local big = {}
	for i = 1, SV.GX_TOWN_CAP + 5 do big[i] = 1000 + i end
	s = SV.applyGlock(s, { town = TOWN, ids = big })
	eq(#s.gx[tostring(TOWN)], SV.GX_TOWN_CAP)
	eq(SV.glocked(s, TOWN)[11], nil, "the oldest dropped")
end)

-------------------------------------------------------------------------------------------------------------------
-- driver

local function fakeE()
	local E = { t = 0, logs = {}, events = {}, sent = {}, refuse = {} }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.name(t) return "Town" .. t end
	function E.closestTown() return TOWN end
	function E.context() return {} end
	function E.lockProposal(ids)
		local list = {}
		for _, id in ipairs(ids) do list[#list + 1] = { old = id, entity = -#list - 1, n0 = id * 10, n1 = id * 10 + 1, len = 100 } end
		return { ids = ids }, list, {}
	end
	function E.precheck(p)
		for _, id in ipairs(p.ids) do
			if E.refuse[id] then return { ok = false, msgs = { "Collision" }, buildings = 0, cost = 0 } end
		end
		return { ok = true, msgs = {}, buildings = 0, cost = 1000 * #p.ids }
	end
	function E.sendBuild(p, _ctx, cb) E.sent[#E.sent + 1] = p; E.pending = cb end
	function E.edgeBetween(n0, _n1, old) return 5000 + old, true end
	function E.sendEvent(_id, name, param) E.events[#E.events + 1] = { name = name, param = param } end
	return E
end

local function logsWith(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do if l:find("[SQOT] " .. what, 1, true) then out[#out + 1] = l end end
	return out
end

local function newDriver(E, valves, lock)
	local d = D.new(E)
	d.opts = { debug = false }
	-- (§69: the default lock is "steer"; the §67 tests here run the "mod" lock, the steer ones pass lock = "steer")
	d:townState(TOWN).lockMode = lock or "mod"
	-- (a planned town; every valve anchor "wet", so no valve protects a zone unless the test sets its own context)
	if not valves then d:glockState(TOWN).ctx = { grower = "grid", wet = function() return true end } end
	return d
end

-- a measured town: 4 game streets (2 with houses), a mod street, a player street
local function measured()
	local edges = {
		edge(1, 100, 0, 200, 0), edge(2, 200, 0, 300, 0), edge(3, 0, 100, 0, 200), edge(4, -100, 0, -200, 0),
		edge(5, 0, -100, 0, -200, { locked = true }), edge(6, 300, 300, 400, 300, { owned = true }),
	}
	local lot = {}
	for _, e in ipairs(edges) do if not e.owned then lot[#lot + 1] = { id = e.id } end end
	return { ext = { cx = 0, cy = 0, r = 250 }, edges = edges, lotEdges = lot, builtBy = { [3] = 4, [4] = 1 } }
end

local function run(d, E, job, n)
	for _ = 1, n or 50 do
		if E.pending then
			local cb = E.pending
			E.pending = nil
			cb(E.okBuild ~= false, { cost = 1000, msgs = E.okBuild == false and { "Construction not possible" } or {} })
		end
		if not d:advance(E.t, nil) then return end
		E.t = E.t + 100000
	end
end

test("old saves: a frame without gk keeps the §65 lock only; gk on; a legacy town never; no frame: the default", function()
	local d = newDriver(fakeE())
	local saved = SV.normalize(nil)
	saved = SV.applyFrame(saved, { town = 1, a = 0, x = 0, y = 0, lm = 1 })
	saved = SV.applyFrame(saved, { town = 2, a = 0, x = 0, y = 0, lm = 1, gk = 1 })
	saved = SV.applyFrame(saved, { town = 3, a = 0, x = 0, y = 0 })
	eq(d:townGameLock(1, saved), false, "§65 frame")
	eq(d:townGameLock(2, saved), true)
	eq(d:townGameLock(3, saved), false, "legacy lock")
	eq(d:townGameLock(4, saved), true, "no frame: GLOCK_DEFAULT")
	H.glockDefault = false
	local d2 = newDriver(fakeE())
	eq(d2:townGameLock(4, saved), false, "the dev hook")
	H.glockDefault = nil
	-- a town that isn't game-locked: no queue, no CHECK fields
	local job = { town = 1 }
	eq(d:glockNote(job, 1, measured(), 0, saved), nil)
	eq(job.glockQ, nil)
end)

test("driver: the CHECK queues the settled houseless game streets; the job's end locks them, saves the new ids", function()
	-- (measured with WITH_HOUSES off, the rule before the 2026-10-15 probe: the housed edge stays out of the queue)
	local wh = GL.WITH_HOUSES
	GL.WITH_HOUSES = false
	local E = fakeE()
	local d = newDriver(E)
	local m = measured()
	local job = { town = TOWN, stage = "assess" }
	d.job = job
	-- first sight: stamped, nothing settled yet
	d:glockNote(job, TOWN, m, 0, nil)
	eq(job.glockQ, nil)
	E.t = (GL.SETTLE_S + 1) * 1e6
	local gs = d:glockNote(job, TOWN, m, E.t, nil)
	ok(job.glockQ ~= nil)
	local q = {}
	for _, c in ipairs(job.glockQ) do q[#q + 1] = c.id end
	table.sort(q)
	eq(table.concat(q, ","), "1,2", "not the housed, the mod's or the player's")
	eq(gs.tally.open, 4)
	-- the core: the town had no frame at its first sight
	ok(gs.core[1] and gs.core[4] and not gs.core[5])
	-- the job ends: it locks first, then finishes with its outcome
	local outcome
	job.onDone = function(_j, o) outcome = o end
	eq(d:finish(TOWN, "room", E.t), nil)
	eq(job.stage, "glock")
	eq(outcome, nil)
	run(d, E, job)
	eq(outcome, "room")
	eq(d.job, nil)
	eq(#E.sent, 1)
	local gl = logsWith(E, "GLOCK")
	local okLines = 0
	for _, l in ipairs(gl) do if l:find("ok=true", 1, true) then okLines = okLines + 1 end end
	eq(okLines, 2, table.concat(gl, "\n"))
	ok(gl[1]:find("event=send", 1, true), gl[1])
	ok(gs.ids[5001] and gs.ids[5002])
	eq(gs.n, 2)
	eq(E.events[1].name, SV.EV_GLOCK)
	eq(#E.events[1].param.ids, 2)
	GL.WITH_HOUSES = wh
	-- the new edges read as the game's again (not the mod's own locked streets)
	local edges = { edge(5001, 100, 0, 200, 0, { locked = true }), edge(9, 0, 0, 1, 1, { locked = true }) }
	d:glockMark(TOWN, edges)
	eq(edges[1].locked, false); eq(edges[1].glocked, true)
	eq(edges[2].locked, true)
end)

test("refund (§68): the balance change, at most the build's cost; none without a balance, a cost, or off the cost", function()
	eq(GL.refund(10000, 8000, 2000), 2000, "paid exactly")
	eq(GL.refund(10000, 8500, 2000), 1500, "paid less: what was paid")
	eq(GL.refund(10000, 7500, 2000), 2000, "paid a bit more: the cost at most")
	eq(GL.refund(10000, 4000, 2000), 2000, "other spending in the same frames: the cost only (2026-10-15 run)")
	eq(select(2, GL.refund(10000, 9500, 2000)), "mismatch", "much less than the cost")
	eq(select(2, GL.refund(10000, 10000, 2000)), "notCharged")
	eq(select(2, GL.refund(10000, 12000, 2000)), "notCharged", "income in between")
	eq(select(2, GL.refund(nil, 8000, 2000)), "noBalance", "infinite money")
	eq(select(2, GL.refund(10000, 0 / 0, 2000)), "noBalance")
	eq(select(2, GL.refund(10000, 8000, nil)), "noCost")
	eq(select(2, GL.refund(10000, 8000, 0)), "noCost")
	local was = GL.REFUND
	GL.REFUND = false
	eq(select(2, GL.refund(10000, 8000, 2000)), "off")
	GL.REFUND = was
end)

test("driver: a lock build's charge is booked back (GLOCK event=refund, STREETS glockRefund); none with infinite money", function()
	H.player = true   -- a charged build: the player in the context (the dev toggle; the default sends none)
	local function runOnce(balanceFn)
		local E = fakeE()
		E.bal = 1e6
		E.booked = {}
		E.balance = balanceFn and function() return balanceFn(E) end or nil
		function E.bookStreetRefund(a) E.booked[#E.booked + 1] = a; E.bal = E.bal + a end
		local send = E.sendBuild
		-- the build charges its cost when it runs (the callback comes after)
		function E.sendBuild(p, ctx, cb)
			send(p, ctx, function(ok, info)
				E.bal = E.bal - 2000
				cb(ok, info)
			end)
		end
		local d = newDriver(E)
		local job = { town = TOWN, stage = "assess" }
		d.job = job
		d:glockNote(job, TOWN, measured(), 0, nil)
		E.t = (GL.SETTLE_S + 1) * 1e6
		d:glockNote(job, TOWN, measured(), E.t, nil)
		d:finish(TOWN, "room", E.t)
		-- the callback reports the build cost 2000 (the charge above)
		for _ = 1, 50 do
			if E.pending then
				local cb = E.pending
				E.pending = nil
				cb(true, { cost = 2000, msgs = {} })
			end
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
		end
		return E, d
	end
	local E, d = runOnce(function(e) return e.bal end)
	eq(#E.booked, 1)
	eq(E.booked[1], 2000)
	eq(E.bal, 1e6, "the balance is back where it was")
	local rl = logsWith(E, "GLOCK town=" .. TOWN .. " name=Town" .. TOWN .. " event=refund")
	eq(#rl, 1)
	ok(rl[1]:find("amount=2000", 1, true) and rl[1]:find("why=paid", 1, true), rl[1])
	eq(d.glockRefundSum, 2000)
	-- infinite money (no balance): nothing booked, no refund line
	local E2 = runOnce(nil)
	eq(#E2.booked, 0)
	eq(#logsWith(E2, "event=refund"), 0)
	H.player = nil
end)

test("driver: a lock build after a growth build's refund: each charge booked back once; the booking in flight counts", function()
	H.player = true   -- a charged build: the player in the context (the dev toggle; the default sends none)
	local E = fakeE()
	E.bal = 1e6
	E.booked, E.queued = {}, {}
	function E.balance() return E.bal end
	-- (bookings land only with the next command, as the game applies them in order: before the lock build's charge)
	function E.bookStreetRefund(a) E.booked[#E.booked + 1] = a; E.queued[#E.queued + 1] = a; return true end
	local d = newDriver(E)
	-- the growth build just before: charged 700, its refund booked but not landed yet
	E.bal = E.bal - 700
	eq(d:refundBuild("build", E.bal + 700, 700, E.t), 700)
	local job = { town = TOWN, stage = "assess" }
	d.job = job
	d:glockNote(job, TOWN, measured(), 0, nil)
	E.t = (GL.SETTLE_S + 1) * 1e6
	d:glockNote(job, TOWN, measured(), E.t, nil)
	d:finish(TOWN, "room", E.t)
	for _ = 1, 50 do
		if E.pending then
			local cb = E.pending
			E.pending = nil
			for _, a in ipairs(E.queued) do E.bal = E.bal + a end
			E.queued = {}
			E.bal = E.bal - 2000
			cb(true, { cost = 2000, msgs = {} })
		end
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	eq(#E.booked, 2)
	eq(E.booked[2], 2000, "the whole lock charge (without the in-flight booking: 1300)")
	for _, a in ipairs(E.queued) do E.bal = E.bal + a end
	eq(E.bal, 1e6, "both charges back")
	eq(#logsWith(E, "GLOCK town=" .. TOWN .. " name=Town" .. TOWN .. " event=refund"), 1)
	eq(#logsWith(E, "REFUND kind=build"), 0, "the lock build isn't refunded as a build too")
	eq(d.glockRefundSum, 2000)
	eq(d.refundSum, 2700)
	H.player = nil
end)

test("driver: a refused batch goes edge by edge; the refused edge is counted, the rest built; failures back off", function()
	local E = fakeE()
	local d = newDriver(E)
	local m = measured()
	m.builtBy = {}
	local job = { town = TOWN, stage = "assess" }
	d.job = job
	d:glockNote(job, TOWN, m, 0, nil)
	E.t = (GL.SETTLE_S + 1) * 1e6
	d:glockNote(job, TOWN, m, E.t, nil)
	E.refuse[2] = true
	d:finish(TOWN, "built", E.t)
	run(d, E, job)
	eq(d.job, nil)
	eq(#E.sent, 1)
	local gs = d:glockState(TOWN)
	eq(gs.fails[2], 1)
	ok(not gs.ids[5002])
	ok(gs.ids[5001] and gs.ids[5003] and gs.ids[5004])
	local refused = 0
	for _, l in ipairs(logsWith(E, "GLOCK")) do
		if l:find("edge=2 ", 1, true) and l:find("ok=false", 1, true) and l:find("why=precheck", 1, true) then refused = refused + 1 end
	end
	eq(refused, 1)
	-- a build refusal: every edge counted, the town backs off
	E.okBuild = false
	local job2 = { town = TOWN, stage = "assess" }
	d.job = job2
	local m2 = measured()
	m2.edges = { edge(2, 200, 0, 300, 0) }
	m2.lotEdges = { { id = 2 } }
	m2.builtBy = {}
	E.refuse[2] = nil
	E.t = E.t + 1e6
	d:glockNote(job2, TOWN, m2, E.t, nil)
	ok(job2.glockQ ~= nil)
	d:finish(TOWN, "room", E.t)
	run(d, E, job2)
	eq(gs.fails[2], 2)
	ok(gs.bad[2], "EDGE_FAILS refusals: left alone")
	ok(gs.bo.nextUs > E.t, "backoff")
	-- backed off: nothing queued
	local job3 = { town = TOWN }
	d:glockNote(job3, TOWN, measured(), E.t, nil)
	eq(job3.glockQ, nil)
	eq(gs.why, "backoff")
	-- a callback that never comes ends after WAIT_S
	E.okBuild = nil
	gs.bo.nextUs = 0
	local job4 = { town = TOWN, stage = "assess" }
	d.job = job4
	local m4 = measured()
	m4.builtBy = {}
	d:glockNote(job4, TOWN, m4, E.t, nil)
	d:finish(TOWN, "room", E.t)
	d:advance(E.t, nil)
	eq(job4.stage, "glockWait")
	E.pending = nil
	E.t = E.t + (GL.WAIT_S + 1) * 1e6
	d:advance(E.t, nil)
	eq(d.job, nil)
	eq(d.inflight, false)
end)

test("driver: caps: per town and per session; dry / forced / head jobs never lock", function()
	local E = fakeE()
	local d = newDriver(E)
	local m = measured()
	m.builtBy = {}
	d:glockNote({ town = TOWN }, TOWN, m, 0, nil)
	E.t = (GL.SETTLE_S + 1) * 1e6
	for _, o in ipairs({ { dry = true }, { force = true }, { head = true } }) do
		local job = { town = TOWN }
		for k, v in pairs(o) do job[k] = v end
		d:glockNote(job, TOWN, m, E.t, nil)
		eq(job.glockQ, nil)
	end
	local gs = d:glockState(TOWN)
	gs.n = GL.TOWN_MAX
	local j = { town = TOWN }
	d:glockNote(j, TOWN, m, E.t, nil)
	eq(j.glockQ, nil); eq(gs.why, "townCap")
	gs.n = 0
	d.glockN = GL.MAP_MAX
	d:glockNote(j, TOWN, m, E.t, nil)
	eq(j.glockQ, nil); eq(gs.why, "mapCap")
	d.glockN = 0
	d:glockNote(j, TOWN, m, E.t, nil)
	ok(j.glockQ ~= nil and #j.glockQ <= GL.BATCH)
	-- not planned yet this session: no valve context, nothing locked
	local d0 = newDriver(E, true)
	d0:glockNote({ town = TOWN }, TOWN, m, 0, nil)
	local j0 = { town = TOWN }
	d0:glockNote(j0, TOWN, m, E.t, nil)
	eq(j0.glockQ, nil); eq(d0:glockState(TOWN).why, "noCtx")
	-- another town's street inside the read: left alone
	E.closestTown = function() return 99 end
	local d2 = newDriver(E)
	d2:glockNote({ town = TOWN }, TOWN, m, 0, nil)
	local j2 = { town = TOWN }
	d2:glockNote(j2, TOWN, m, E.t, nil)
	eq(j2.glockQ, nil)
end)

test("driver: valves open on open land, protect their zone from the lock, close at their quota and rotate", function()
	local E = fakeE()
	local d = newDriver(E, true)
	local gs = d:glockState(TOWN)
	gs.ctx = { field = leanField(0), grower = "grid", arms = nil }
	-- streets east (favoured) and west, out at the rim
	local function town(extra)
		local edges = { edge(1, 200, 0, 300, 0), edge(2, -200, 0, -300, 0), edge(3, 0, 200, 0, 300) }
		for _, e in ipairs(extra or {}) do edges[#edges + 1] = e end
		local lot = {}
		for _, e in ipairs(edges) do lot[#lot + 1] = { id = e.id } end
		return { ext = { cx = 0, cy = 0, r = 300 }, edges = edges, lotEdges = lot, builtBy = {} }
	end
	local job = { town = TOWN }
	d:glockNote(job, TOWN, town(), 0, nil)
	eq(#gs.valves, 1, "a grid town: one valve")
	eq(gs.valves[1].anchor, 1, "east: the land lean")
	local op = logsWith(E, "VALVE")
	ok(op[1]:find("event=open", 1, true) and op[1]:find("heading=0", 1, true) and op[1]:find("why=land", 1, true), op[1])
	-- the anchor and the game's new streets in its zone stay unlocked; the others are queued
	E.t = (GL.SETTLE_S + 1) * 1e6
	local j2 = { town = TOWN }
	d:glockNote(j2, TOWN, town({ edge(10, 300, 0, 400, 0) }), E.t, nil)
	local q = {}
	for _, c in ipairs(j2.glockQ or {}) do q[c.id] = true end
	ok(not q[1] and not q[10] and q[2] and q[3], "zone protected")
	-- the game builds its quota in the zone: the valve closes, the next one opens elsewhere (east rests)
	local more = {}
	for i = 1, GL.valveQuota("grid") do more[#more + 1] = edge(20 + i, 300 + i * 5, 10, 300 + i * 5, 60) end
	d:glockNote({ town = TOWN }, TOWN, town(more), E.t, nil)
	local cl = logsWith(E, "VALVE")
	local closed = false
	for _, l in ipairs(cl) do if l:find("event=close", 1, true) and l:find("why=quota", 1, true) then closed = true end end
	ok(closed, table.concat(cl, "\n"))
	eq(#gs.valves, 1)
	ok(gs.valves[1].anchor ~= 1 and gs.valves[1].anchor ~= 10, "rotated: " .. tostring(gs.valves[1].anchor))
	eq(gs.rest[1], 0)
	-- the closed zone's houseless streets are lock candidates again
	local j3 = { town = TOWN }
	E.t = E.t + (GL.SETTLE_S + 1) * 1e6
	d:glockNote(j3, TOWN, town(more), E.t, nil)
	local q3 = {}
	for _, c in ipairs(j3.glockQ or {}) do q3[c.id] = true end
	ok(q3[1] or q3[10] or q3[21], "the old zone queued")
end)

test("driver: no good anchor -> a stub heading; the build's tip toward it stays unlocked and becomes the valve", function()
	local E = fakeE()
	local d = newDriver(E, true)
	local gs = d:glockState(TOWN)
	gs.ctx = { field = leanField(math.pi / 2), grower = "grid" }
	-- only an inner street: no anchor
	local m = { ext = { cx = 0, cy = 0, r = 300 }, edges = { edge(1, 0, 0, 50, 0) }, lotEdges = { { id = 1 } }, builtBy = {} }
	d:glockNote({ town = TOWN }, TOWN, m, 0, nil)
	eq(#gs.valves, 0)
	ok(gs.stubWant and math.abs(gs.stubWant - math.pi / 2) < 1e-6, tostring(gs.stubWant))
	ok(logsWith(E, "VALVE")[1]:find("event=want", 1, true))
	local job = { town = TOWN, ext = m.ext, townLock = "mod", inc = { edges = {
		{ key = "n", node0 = -1, node1 = -2, p0 = { 0, 250 }, p1 = { 0, 330 } },
		{ key = "e", node0 = -1, node1 = -3, p0 = { 250, 0 }, p1 = { 330, 0 } } } } }
	local info = d:buildInfo(job)
	ok(info.lock == true and info.unlockKeys and info.unlockKeys.n, "the north tip unlocked")
	job.spec = { edges = { { key = "n", p0 = { 0, 250 }, p1 = { 0, 330 } }, { key = "e", locked = true, p0 = { 250, 0 }, p1 = { 330, 0 } } } }
	d:glockStubBuilt(job, 0)
	eq(#gs.valves, 1); eq(gs.valves[1].kind, "stub")
	eq(gs.stubWant, nil)
	-- a legacy town's build never gets a stub
	local d2 = newDriver(fakeE())
	d2:glockState(TOWN).stubWant = 1
	eq(d2:buildInfo({ town = TOWN, townLock = "legacy", lock = "off", ext = m.ext, inc = job.inc }).unlockKeys, nil)
end)

test("stall guard: a fire opens one more valve (capped), before level 3 relaxes the forest hold", function()
	local E = fakeE()
	local d = newDriver(E)
	local gs = d:glockState(TOWN)
	for i = 1, 4 do
		local m = { needs = false, why = "open", buildings = 50, ratio = 0.5 }
		d:stallGuard({ town = TOWN }, TOWN, m, math.min(3, i), nil, nil)
	end
	eq(gs.extra, GL.VALVE_STALL_MAX)
	ok(logsWith(E, "STALL")[1]:find("valveExtra=1", 1, true))
	eq(GL.wantValves("grid", 200, gs.extra), 1 + GL.VALVE_STALL_MAX)
	-- held: no fire applied, no extra
	local d2 = newDriver(fakeE())
	d2:stallGuard({ town = TOWN }, TOWN, { needs = false, why = "open", buildings = 1 }, 1, nil, "created")
	eq(d2:glockState(TOWN).extra, 0)
	ok(A.STALL_LEVELS >= 3)
end)

test("E.lockProposal on a fake api: a lockable edge is proposed (regression: `okF and w or \"read\"` refused every edge)", function()
	local function new() return {} end
	local comps = {
		[5] = {
			BE = { roadDevelopmentLocked = false, type = 0, objects = {}, node0 = 50, node1 = 51,
				position0 = { x = 0, y = 0, z = 10 }, position1 = { x = 40, y = 0, z = 10 },
				tangent0 = { x = 40, y = 0, z = 0 }, tangent1 = { x = 40, y = 0, z = 0 } },
			BES = { streetType = 1 },
		},
		[6] = {
			BE = { roadDevelopmentLocked = false, type = 1, objects = {}, node0 = 60, node1 = 61,
				position0 = { x = 0, y = 0, z = 10 }, position1 = { x = 40, y = 0, z = 10 },
				tangent0 = { x = 40, y = 0, z = 0 }, tangent1 = { x = 40, y = 0, z = 0 } },
			BES = { streetType = 1 },
		},
	}
	set_global("api", {
		type = {
			ComponentType = { BASE_EDGE = "BE", BASE_EDGE_STREET = "BES", PLAYER_OWNED = "PO", BASE_NODE_CONFIG = "BNC" },
			enum = { BaseEdgeType = { NORMAL = 0, BRIDGE = 1, TUNNEL = 2 } },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			SegmentAndEntity = { new = new },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			BaseNodeLaneConnectionAndEntity = { new = new },
		},
		engine = {
			entityExists = function(e) return comps[e] ~= nil end,
			getComponent = function(e, ct) return comps[e] and comps[e][ct] end,
			system = { streetConnectorSystem = {
				getConstructionEntityForEdge = function() return -1 end,
				getConstructionEntityForNode = function() return -1 end,
			} },
		},
	})
	local E = ug_require(F.DIR .. "ot_engine.lua")
	local p, list, skipped = E.lockProposal({ 5, 6 })
	ok(p ~= nil, "a proposal for the lockable edge")
	eq(#list, 1)
	eq(list[1].old, 5)
	eq(skipped[5], nil, "edge 5 not skipped")
	eq(skipped[6], "bridge")
	eq(p.streetProposal.edgesToRemove[1], 5)
	eq(p.streetProposal.edgesToAdd[1].comp.roadDevelopmentLocked, true)
	set_global("api", nil)
end)
