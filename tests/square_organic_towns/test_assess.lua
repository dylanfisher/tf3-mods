-- ot_assess (extent, lots, needs room, scheduler), ot_params and ot_saved.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local A = ug_require(F.DIR .. "ot_assess.lua")
local PA = ug_require(F.DIR .. "ot_params.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")

test("extent: mean centre and 90th percentile radius of building positions", function()
	eq(A.extent({}), nil)
	local pts = {}
	for i = 1, 9 do pts[#pts + 1] = { 10 * math.cos(i), 10 * math.sin(i) } end
	pts[#pts + 1] = { 0, 0 }
	local e = A.extent(pts)
	ok(math.abs(e.cx) < 3 and math.abs(e.cy) < 3)
	eq(e.n, 10)
	ok(e.r > 5 and e.r <= e.rMax)
	-- one far outlier doesn't stretch the radius
	local spread = {}
	for i = 1, 19 do spread[i] = { (i % 5) * 10, math.floor(i / 5) * 10 } end
	spread[20] = { 5000, 0 }
	local s = A.extent(spread)
	ok(s.r < 1000, "r " .. s.r)
	ok(s.rMax > 4000)
end)

local EXT = { cx = 0, cy = 0, r = 200 }

test("lots: free = parcels - built; unparcelled town edges count virtual lots; inner lots count half", function()
	local l = A.lots({
		{ id = 1, mx = 150, my = 0, len = 100, parcels = 20, built = 15, town = true },   -- outer: 5 free
		{ id = 2, mx = 10, my = 0, len = 100, parcels = 20, built = 10, town = true },    -- inner: 10 free x 0.5
		{ id = 3, mx = 180, my = 0, len = 120, parcels = nil, built = 0, town = true },   -- 120 / 12 = 10 virtual
		{ id = 4, mx = 180, my = 0, len = 120, parcels = nil, built = 0, town = false },  -- not a town street
		{ id = 5, mx = 160, my = 0, len = 80, parcels = 10, built = 14, town = true },    -- over-full: 0 free
	}, EXT)
	eq(l.free, 15)
	eq(l.virtual, 10)
	eq(l.room, 5 + 5 + 10)
	eq(l.built, 39)
	eq(l.total, 50)
	eq(l.withParcels, 3)
	eq(l.unparcelled, 1)
end)

test("lots: open frontage = free lots on edges filled below OPEN_FILL (+ virtual); fuller edges are gaps", function()
	local l = A.lots({
		{ id = 1, mx = 150, my = 0, len = 100, parcels = 20, built = 2, town = true },    -- 10 % filled: 18 open
		{ id = 2, mx = 150, my = 0, len = 100, parcels = 20, built = 10, town = true },   -- 50 %: 10 gap lots
		{ id = 3, mx = 10, my = 0, len = 100, parcels = 20, built = 0, town = true },     -- inner, empty: 20 x 0.5
		{ id = 4, mx = 180, my = 0, len = 120, parcels = nil, built = 0, town = true },   -- 10 virtual
		{ id = 5, mx = 180, my = 0, len = 120, parcels = 0, built = 0, town = true },     -- in the map, no lots
	}, EXT)
	eq(l.open, 18 + 10 + 10)
	eq(l.openEdges, 2)
	eq(l.gaps, 10)
	eq(l.free, 18 + 10 + 20)
	eq(l.room, 18 + 10 + 10 + 10)
end)

test("needsRoom: open frontage under max(min, built x share); hungry towns want more; shrinking towns none", function()
	local lots = { open = 30, room = 500, built = 200 }
	local needs, th, why = A.needsRoom(lots, nil, 2)     -- max(24, 200 * 0.2 = 40)
	eq(th, 40)
	ok(needs)
	eq(why, "low")
	needs, th, why = A.needsRoom(lots, nil, 1)           -- max(12, 20)
	eq(th, 20)
	ok(not needs)
	eq(why, "open")
	local n2, th2, why2, ratio = A.needsRoom({ open = 50, built = 200 }, { target = 1000, actual = 800 }, 2)
	near(ratio, 0.8, 1e-9)
	eq(th2, 40 * A.HUNGRY_FACTOR, "a hungry town (target just rose) wants more open frontage")
	ok(n2)
	eq(why2, "low")
	local n3, _, why3 = A.needsRoom({ open = 0, built = 200 }, { target = 1000, actual = 1200 }, 2)
	ok(not n3)
	eq(why3, "over")
	local n4, th4 = A.needsRoom({ open = 0, built = 0 }, nil, 3)
	eq(th4, 40)
	ok(n4, "a town with no open frontage at all needs room")
	eq(A.maxEdges(1), 12)
	eq(A.maxEdges(3), 24)
	eq(A.maxEdges(nil), 18)
end)

test("needsRoom: a fresh town at its target with half its lots in gaps needs room (first in-game run)", function()
	-- Dickinson, 2026-10-11: buildings=162 edges=52 free=527 built=457 cap=856/870 -> needsRoom=false with the
	-- old free-lots rule. Its free lots are mostly gaps on partly built edges (lots ~19 per edge, ~46 % filled).
	local edges = {}
	for i = 1, 52 do
		local parcels = 19
		local built = (i <= 49) and 9 or 2    -- three nearly empty edges at the edge of town
		edges[i] = { id = i, mx = 100 + i, my = 0, len = 100, parcels = parcels, built = built, town = true }
	end
	local l = A.lots(edges, { cx = 0, cy = 0, r = 120 })
	ok(l.free > 500, "free " .. l.free)
	local needs, th, why = A.needsRoom(l, { target = 870, actual = 856 }, 2)
	ok(needs, string.format("open %s vs need %s", l.open, th))
	eq(why, "low")
	-- an 18-edge increment (~100 m each) not adopted yet: 18 x 8 virtual lots is enough frontage for a while
	for i = 1, 18 do edges[#edges + 1] = { id = 100 + i, mx = 300, my = 0, len = 100, parcels = nil, built = 0, town = true } end
	local l2 = A.lots(edges, { cx = 0, cy = 0, r = 120 })
	local needs2 = A.needsRoom(l2, { target = 870, actual = 856 }, 2)
	ok(not needs2, "open " .. l2.open)
end)

test("scheduler: round-robin over towns off cooldown, fail backoff doubles and is capped", function()
	local s = A.newSched()
	local ids = { 3, 7, 9 }
	eq(A.pick(s, ids, 0), 3)
	eq(A.pick(s, ids, 0), 7)
	eq(A.cooldown(s, 9, 0, "room"), 30)
	eq(A.pick(s, ids, 0), 3, "9 is cooling down, wraps to 3")
	eq(A.pick(s, ids, 0), 7)
	A.cooldown(s, 3, 0, "built")
	A.cooldown(s, 7, 0, "built")
	eq(A.pick(s, ids, 1e6), nil, "everyone cooling down")
	eq(A.pick(s, ids, 31e6), 9)
	eq(A.cooldown(s, 9, 0, "fail"), 120)
	eq(A.cooldown(s, 9, 0, "fail"), 240)
	for _ = 1, 10 do A.cooldown(s, 9, 0, "fail") end
	eq(A.cooldown(s, 9, 0, "fail"), A.FAIL_CAP_S)
	A.cooldown(s, 9, 0, "built")
	eq(A.cooldown(s, 9, 0, "fail"), 120, "a build resets the backoff")
	eq(A.pick(s, {}, 0), nil)
	-- a town id that vanished: the cursor moves on to the next larger one
	local s2 = A.newSched()
	s2.cursor = 8
	eq(A.pick(s2, ids, 0), 9)
end)

test("params: 1-based value indices, defaults for missing or bad values, map editor flag", function()
	local o = PA.parse(nil, nil)
	eq(o.actOn, "new")
	eq(o.forceGrid, false)
	eq(o.lookahead, 2)
	eq(o.debug, false)
	eq(o.mapEditor, false)
	o = PA.parse({ act_on = 1, style = 2, lookahead = 3, debug_log = 2 }, { [""] = { isMapEditor = true } })
	eq(o.actOn, "off")
	eq(o.forceGrid, true)
	eq(o.lookahead, 3)
	eq(o.debug, true)
	eq(o.mapEditor, true)
	o = PA.parse({ act_on = 3, lookahead = 9, debug_log = "x" })
	eq(o.actOn, "all")
	eq(o.lookahead, 2)
	eq(o.debug, false)
	ok(o.raw:find("act_on=3", 1, true))
end)

test("params: mod.json keys, value counts and defaults match ot_params", function()
	local f = io.open(here .. "../../mods/square_organic_towns/mod.json", "r")
	local txt = f:read("*a")
	f:close()
	for key, spec in pairs(PA.KEYS) do
		local block = txt:match('"key": "' .. key .. '".-"defaultIndex": (%d+)')
		ok(block ~= nil, "mod.json has " .. key)
		eq(tonumber(block) + 1, spec.default, key .. " default (mod.json is 0-based)")
		local values = txt:match('"key": "' .. key .. '".-"values": (%b[])')
		local n = 0
		for _ in values:gmatch('"[^"]*"') do n = n + 1 end
		eq(n, #spec.values, key .. " value count")
	end
end)

test("saved: init once (fresh map -> no known towns), frames first-wins, normalize drops junk", function()
	local fresh = SV.initParam({ 5, 6 }, 1000)
	ok(fresh.fresh)
	eq(fresh.known, {})
	local old = SV.initParam({ 5, 6 }, 10 * SV.FRESH_GAME_TIME)
	ok(not old.fresh)
	eq(old.known, { 5, 6 })
	ok(not SV.initialised(nil))
	local s, changed = SV.applyInit(nil, old)
	ok(changed)
	ok(SV.initialised(s))
	local s2, changed2 = SV.applyInit(s, { known = { 99 }, fresh = true })
	ok(not changed2, "a second init (another sim state) is ignored")
	eq(s2.known, { 5, 6 })
	eq(SV.knownSet(s2), { [5] = true, [6] = true })
	eq(SV.knownSet({ v = 1 }), nil)
	local s3, c3 = SV.applyFrame(s2, { town = 6, a = 0.25, x = 10, y = -4 })
	ok(c3)
	local _, c4 = SV.applyFrame(s3, { town = 6, a = 1, x = 0, y = 0 })
	ok(not c4)
	eq(SV.frame(s3, 6), { axis = 0.25, origin = { 10, -4 } })
	eq(SV.frame(s3, 5), nil)
	local _, c5 = SV.applyFrame(s3, { town = "x" })
	ok(not c5)
	local n = SV.normalize({ v = 1, known = { 1, "2", "z" }, frames = { ["3"] = { a = 1, x = 2, y = 3 }, bad = 5 } })
	eq(n.known, { 1, 2 })
	eq(n.frames, { ["3"] = { a = 1, x = 2, y = 3 } })
	eq(SV.normalize({ v = 99, known = { 1 } }).known, nil)
end)

test("saved: frame param rounds and never carries -0", function()
	local fp = SV.frameParam(4, { axis = -0.0, centre = { 0, 0 } }, { origin = { -0.0, -0.0001 } })
	eq(fp.town, 4)
	ok(1 / fp.a > 0 and 1 / fp.x > 0, "no -0")
	eq(fp.y, 0)
	ok(1 / fp.y > 0 or fp.y ~= 0)
	eq(SV.frameParam(4, nil, nil), nil)
end)
