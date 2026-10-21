-- Street provenance (§75 follow-up, 2026-10-19; ot_prov): the source of each built edge, the saved record (ot_saved
-- `pv`), the driver's PROV lines and event, and the console lookup (ot_prov.who) against a fake engine.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local PV = ug_require(F.DIR .. "ot_prov.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

test("source: near-miss joins, job kinds, plan pieces by origin and key", function()
	eq(PV.source(nil, { nearMiss = true, nearMissKind = "tee", key = "nm:4:9", origin = "nearMiss" }), "nm:tee")
	eq(PV.source(nil, { nearMiss = true, nearMissKind = "pair", nearMissCorner = true }), "nm:pairc")
	eq(PV.source(nil, { origin = "plain", key = "ln3:2:1:2" }), "plain/ln")
	eq(PV.source(nil, { origin = "plain", key = "sr1:2:3#1" }), "plain/sr")
	eq(PV.source(nil, { origin = "link", key = "conn:812" }), "link/conn")
	eq(PV.source(nil, { origin = "m:village_green", key = "mvg1" }), "m:village_green/mvg")
	eq(PV.source(nil, { origin = "ring", key = "rg2:3#1" }), "ring/rg")
	eq(PV.source("lead", { key = "lead:1" }), "lead", "the piece repeating the kind: left out")
	eq(PV.source("frame", { key = "frame:tail:35" }), "frame")
	eq(PV.source(nil, {}), "plain")
	eq(PV.clean("a,b;c d"), "a_b_c_d", "no separators")
	eq(#PV.clean(string.rep("x", 99)), PV.SRC_MAX)
	eq(D.provKind({ leadPlan = {} }), "lead")
	eq(D.provKind({ satPlan = {} }), "sat")
	eq(D.provKind({}), nil)
end)

test("entry / parse: compact (plain/ short, trig letter, far end and middle as offsets), rounded, no -0", function()
	local e = PV.entry({ id = 345, src = "plain/ln", trig = "demand", year = 1932.4, p0 = { 100.4, -0.2 },
		p1 = { 200.6, 0 }, t0 = { 100, 40 }, t1 = { 100, -40 } })
	eq(e, "345,/ln,d,1932,100,0,101,0,0,10")
	local r = PV.parseOne("12," .. e)
	eq(r.town, 12)
	eq(r.id, 345)
	eq(r.src, "plain/ln")
	eq(r.trig, "demand")
	eq(r.year, 1932)
	eq(r.pts[3][1], 201)
	near(r.pts[2][1], 150.5, 1e-9)
	eq(r.pts[2][2], 10)
	eq(PV.entry({ id = 1, src = "x", p0 = { 0, 0 }, p1 = { 10, 0 } }), "1,x,-,0,0,0,10,0,0,0")
	eq(PV.entry({ id = 1, src = "x", trig = "stallFix", p0 = { 0, 0 }, p1 = { 10, 0 } }), "1,x,stallF,0,0,0,10,0,0,0")
	eq(PV.entry({ id = 1, p0 = { 0 / 0, 0 }, p1 = { 1, 1 } }), nil)
	eq(PV.entry({ src = "x", p0 = { 0, 0 }, p1 = { 1, 1 } }), nil)
	eq(#PV.parse("1,1,x,-,0,0,0,5,0,10,0;junk;2,2,y,-,0,0,1,2;3,3,z,-,0,0,0,0,1,1,2,2"), 1)
	eq(#PV.parse(nil), 0)
	-- a typical entry is about 40 chars (the cost estimate in PLAN §75)
	local typical = PV.entry({ id = 68724, src = "plain/sr", trig = "demand", year = 1901, p0 = { -5276.3, -5053.1 },
		p1 = { -5254.2, -5109.4 }, t0 = { 22, -56 }, t1 = { 22, -56 } })
	ok(#typical <= 42, typical .. " #" .. #typical)
end)

local function E_(id, x, y, src)
	return PV.entry({ id = id, src = src or "plain/ln", trig = "demand", year = 1930, p0 = { x, y }, p1 = { x + 60, y } })
end

test("append: each edge of a town once (idempotent), the town cap and the total cap drop the oldest", function()
	local a, b = E_(1, 0, 0), E_(2, 0, 10)
	local s1, ch1 = PV.append(nil, 7, { a, b })
	ok(ch1)
	eq(s1, "7," .. a .. ";7," .. b)
	local s2, ch2 = PV.append(s1, 7, { b, a })
	ok(not ch2, "the same edges again: no change")
	eq(s2, s1)
	local s2b, ch2b = PV.append(s1, 17, { a })
	ok(ch2b, "town 17 is not town 7")
	eq(#PV.parse(s2b), 3)
	local s3, ch3 = PV.append(s1, 7, { "3,x;y", "nope", "4,x,d" })
	ok(not ch3, "bad entries are not stored")
	eq(s3, s1)
	-- the town cap: town 7 keeps its newest 3, town 8 untouched
	local s4 = PV.append("", 8, { E_(50, 0, 0) })
	local list = {}
	for i = 1, 5 do list[i] = E_(100 + i, i, 0) end
	s4 = PV.append(s4, 7, list, nil, 3)
	local ids = {}
	for _, r in ipairs(PV.parse(s4)) do ids[#ids + 1] = r.town .. ":" .. r.id end
	eq(table.concat(ids, " "), "8:50 7:103 7:104 7:105")
	-- again later, interleaved with another town
	s4 = PV.append(s4, 9, { E_(60, 0, 0) }, nil, 3)
	s4 = PV.append(s4, 7, { E_(106, 0, 0) }, nil, 3)
	ids = {}
	for _, r in ipairs(PV.parse(s4)) do ids[#ids + 1] = r.town .. ":" .. r.id end
	eq(table.concat(ids, " "), "8:50 7:104 7:105 9:60 7:106")
	-- the total cap: the map's oldest go first, whole entries
	local s5 = ""
	for i = 1, 10 do s5 = PV.append(s5, i, { E_(200 + i, i, 0) }, 120) end
	ok(#s5 <= 120, "#" .. #s5)
	local p5 = PV.parse(s5)
	eq(p5[#p5].id, 210, "the newest kept")
	ok(p5[1].id > 201, "the oldest dropped")
	eq(PV.trim(string.rep("x", 50), 20), "", "one entry over the cap: nothing kept")
	eq(PV.trim("aa;bb;cc", 5), "bb;cc")
	eq(PV.trim("aa;bb;cc", 4), "cc")
end)

test("saved state: applyProv appends, normalize keeps it (no parse), twice is no change; old saves", function()
	local en = E_(77, 0, 0)
	local s, ch = SV.applyProv(nil, { town = 12, add = { en } })
	ok(ch)
	eq(s.pv, "12," .. en)
	local s2, ch2 = SV.applyProv(s, { town = 12, add = { en } })
	ok(not ch2, "idempotent: handleEvent may run in more than one simulation state")
	eq(SV.normalize(s2).pv, "12," .. en, "normalize keeps the record")
	local s3, ch3 = SV.applyProv(s2, { town = "x", add = { en } })
	ok(not ch3)
	eq(SV.applyProv(s3, nil), s3)
	eq(SV.EV_PROV, "square_organic_towns.prov")
	-- a save from before: no pv, nothing made
	eq(SV.normalize({ v = 1 }).pv, nil)
	eq(PV.norm(nil), nil)
	eq(PV.norm(""), nil)
	eq(PV.norm(5), nil)
	-- an over-long string (another build's caps): cut, oldest first
	local long = string.rep("1,2,x,-,0,0,0,10,0,0,0;", 3000) .. "1,3,x,-,0,0,0,10,0,0,0"
	local n = PV.norm(long)
	ok(#n <= PV.TOTAL_MAX)
	eq(n:sub(-22), "1,3,x,-,0,0,0,10,0,0,0")
	-- the per-town tables of the first dev build (2026-10-19): converted by year, the middle kept
	local v1 = { ["12"] = "345,plain/ln,demand,14,1932,100,0,151,10,201,0;346,nm:tee,head,15,1934,0,50,50,50,100,50",
		["13"] = "500,lead/lead,demand,1,1930,500,0,550,0,600,0", bad = "x", ["14"] = 5 }
	local c = PV.norm(v1)
	local p = PV.parse(c)
	eq(#p, 3)
	eq(p[1].id, 500)
	eq(p[1].town, 13)
	eq(p[2].id, 345)
	eq(p[2].src, "plain/ln")
	near(p[2].pts[2][1], 151, 0.51, "the middle to half a metre")
	eq(p[2].pts[2][2], 10)
	eq(p[3].trig, "head")
end)

test("worst case: 1,000 towns building for a long game stay under the caps, appends stay cheap", function()
	local pv = nil
	local t0 = os.clock()
	local id = 1000
	for round = 1, 12 do
		for town = 1, 1000 do
			local add = {}
			for k = 1, 3 do
				id = id + 1
				add[k] = PV.entry({ id = id, src = "m:village_green/mvgL", trig = "offshoot", year = 1900 + round,
					p0 = { -12345.6 + k, -23456.7 }, p1 = { -12000.2, -23000.9 }, t0 = { 300, 400 }, t1 = { 340, 380 } })
			end
			pv = SV.applyProv({ v = 1, pv = pv }, { town = 100000 + town, add = add }).pv
		end
	end
	local dt = os.clock() - t0
	local bytes, entries = PV.size(pv)
	ok(bytes <= PV.TOTAL_MAX, "bytes " .. bytes)
	ok(entries > 400, "entries " .. entries)
	local last = PV.parse(pv)
	eq(last[#last].id, id, "the newest kept")
	ok(dt < 6, string.format("36,000 events in %.2f s", dt))
	-- one town building alone: its own cap
	local one = nil
	for i = 1, 400 do one = PV.add(one, 5, { E_(10000 + i, i, 0) }) end
	local _, n1 = PV.size(one)
	eq(n1, PV.TOWN_N)
end)

test("find / nearest: by edge id, and by position for a street split or rebuilt since", function()
	local pv = "12," .. PV.entry({ id = 345, src = "plain/ln", year = 1931, p0 = { 0, 0 }, p1 = { 100, 0 } })
		.. ";12," .. PV.entry({ id = 346, src = "nm:tee", year = 1932, p0 = { 0, 50 }, p1 = { 100, 50 } })
		.. ";13," .. PV.entry({ id = 3450, src = "lead", year = 1930, p0 = { 500, 0 }, p1 = { 600, 0 } })
	local r, town = PV.find(pv, 345)
	eq(r.src, "plain/ln")
	eq(town, "12")
	eq(select(2, PV.find(pv, 3450)), "13", "345 is a prefix of 3450: the exact id")
	eq(PV.find(pv, 999), nil)
	eq(PV.find(nil, 345), nil)
	local rn, tn, d = PV.nearest(pv, 40, 3)
	eq(rn.id, 345)
	eq(tn, "12")
	near(d, 3, 1e-9)
	eq(PV.nearest(pv, 40, 25), nil, "between the two: nothing within NEAR_M")
	ok(PV.describe(r):find("cross lane", 1, true) ~= nil, PV.describe(r))
	ok(PV.describe(select(1, PV.find(pv, 346))):find("near-miss join (tee)", 1, true) ~= nil)
	ok(PV.describe({ src = "nm:pairc" }):find("corner", 1, true) ~= nil)
	eq(PV.describe(nil), "-")
	eq(PV.size(nil), 0)
end)

test("driver: PROV lines per built edge (debug, capped) and the record event; nothing for a dry run", function()
	local logs, events = {}, {}
	local E = { log = function(l) logs[#logs + 1] = l end, name = function(t) return "Town" .. t end,
		year = function() return 1931 end, sendEvent = function(id, name, p) events[#events + 1] = { id, name, p } end,
		nowUs = function() return 0 end }
	local d = D.new(E)
	d.verbose = true
	local s = d:townState(12)
	s.builds = 7
	local function pair(i, e)
		return { e, { id = 900 + i, n0 = 10 + i, n1 = 20 + i, p0 = { i * 10, 0, 0 }, p1 = { i * 10, 60, 0 },
			t0 = { 0, 60, 0 }, t1 = { 0, 60, 0 } } }
	end
	d:provNote({ town = 12, trigger = "demand" }, { pair(1, { origin = "plain", key = "ln3:2:1:2", length = 60, locked = true }),
		pair(2, { nearMiss = true, nearMissKind = "pair", nearMissCorner = true, key = "nm:4:9", length = 61 }) })
	eq(#logs, 2)
	ok(logs[1]:find("[SQOT] PROV town=12 name=Town12 edge=901 n=11,21 a=10,0 b=10,60 len=60 d=- src=plain/ln key=ln3:2:1:2 "
		.. "trig=demand seq=7 year=1931 lock=1", 1, true), logs[1])
	ok(logs[2]:find("src=nm:pairc", 1, true) and logs[2]:find("lock=0", 1, true), logs[2])
	eq(#events, 1)
	eq(events[1][2], SV.EV_PROV)
	eq(events[1][3].town, 12)
	eq(#events[1][3].add, 2)
	local st = SV.applyProv(nil, events[1][3])
	eq(select(1, PV.find(st.pv, 902)).src, "nm:pairc")
	-- (§75 follow-up: `d=` the edge middle's distance from the town centre: the style's, else the houses' mean)
	logs = {}
	d:provNote({ town = 12, trigger = "demand", style = { centre = { 30, -20 } } }, { pair(3, { origin = "plain", key = "sr1:1:1" }) })
	ok(logs[1]:find(" d=50 src=", 1, true), logs[1])
	logs = {}
	d:provNote({ town = 12, trigger = "demand", ext = { cx = 30, cy = 30 } }, { pair(3, { origin = "plain", key = "sr1:1:1" }) })
	ok(logs[1]:find(" d=0 src=", 1, true), logs[1])
	-- the cap: LINES_MAX lines and one `more=`; the record keeps every edge
	logs, events = {}, {}
	local many = {}
	for i = 1, PV.LINES_MAX + 3 do many[i] = pair(i, { origin = "plain", key = "sr1:1:1" }) end
	d:provNote({ town = 12, head = true }, many)
	eq(#logs, PV.LINES_MAX + 1)
	ok(logs[#logs]:find("more=3", 1, true), logs[#logs])
	ok(logs[1]:find("trig=head", 1, true))
	eq(#events[1][3].add, PV.LINES_MAX + 3)
	-- debug off: no lines, the record still goes
	logs, events = {}, {}
	d.verbose = false
	d.opts = { debug = false }
	d:provNote({ town = 12 }, { pair(1, { origin = "plain" }) })
	eq(#logs, 0)
	eq(#events, 1)
	-- a dry run: nothing
	events = {}
	d:provNote({ town = 12, dry = true }, { pair(1, { origin = "plain" }) })
	eq(#events, 0)
end)

--- A fake engine for the console lookup: edges { [id] = { p0, p1, locked } }, the saved state { pv, gx }, the cursor.
local function fakeApi(edges, state, cursor)
	local CT = { BASE_EDGE = 1, BASE_EDGE_STREET = 2, GAME_SCRIPT = 3 }
	local GS = 5000
	local function v3(p) return { x = p[1], y = p[2], z = 0 } end
	return {
		type = { ComponentType = CT, Vec2f = { new = function(x, y) return { x = x, y = y } end } },
		gui = { mouse = { getTerrainPosition = function() return cursor and v3(cursor) or nil end } },
		engine = {
			system = { gameScriptSystem = { getEntityForGameScript = function(name)
				return name == PV.GS_NAME and state and GS or -1 end } },
			getComponent = function(e, ct)
				if e == GS and ct == CT.GAME_SCRIPT then
					return { state_native = { find = function(_, k) return state[k] end } }
				end
				local ed = edges[e]
				if ed == nil then return nil end
				if ct == CT.BASE_EDGE_STREET then return {} end
				if ct == CT.BASE_EDGE then
					local t = { ed.p1[1] - ed.p0[1], ed.p1[2] - ed.p0[2], 0 }
					return { position0 = v3(ed.p0), position1 = v3(ed.p1), tangent0 = v3(t), tangent1 = v3(t),
						roadDevelopmentLocked = ed.locked == true }
				end
				return nil
			end,
			util = { octree = { findEntitiesInCircle = function(c, r, _ct)
				local out = {}
				for id, ed in pairs(edges) do
					local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
					-- (by the edge's middle, as the game: findings roads.md "Octree edge search")
					if math.sqrt((mx - c.x) ^ 2 + (my - c.y) ^ 2) <= r then out[#out + 1] = id end
				end
				table.sort(out)
				return out
			end } },
		},
	}
end

test("console who(): ours by id, ours by position after a split, a §67 game lock, locked without record, not ours", function()
	local pv = "12," .. PV.entry({ id = 345, src = "plain/ln", trig = "demand", year = 1931, p0 = { 0, 0 },
		p1 = { 100, 0 } })
	local edges = {
		[345] = { p0 = { 0, 0 }, p1 = { 100, 0 }, locked = true },
		[777] = { p0 = { 0, 200 }, p1 = { 100, 200 }, locked = true },          -- locked, no record
		[778] = { p0 = { 0, 400 }, p1 = { 100, 400 } },                         -- the game's
		[779] = { p0 = { 0, 600 }, p1 = { 100, 600 }, locked = true },          -- a §67 game lock
		[880] = { p0 = { 1000, 0 }, p1 = { 1050, 0 }, locked = true },          -- split off a recorded one below
	}
	pv = pv .. ";13," .. PV.entry({ id = 870, src = "plain/sr", year = 1930, p0 = { 1000, 0 }, p1 = { 1100, 0 } })
	set_global("api", fakeApi(edges, { pv = pv, gx = { ["12"] = { 779 } } }, { 40, 2 }))
	local t = PV.who(345)
	ok(t:find("ours=yes town=12 src=plain/ln", 1, true), t)
	t = PV.who()
	ok(t:find("edge=345", 1, true) and t:find("ours=yes", 1, true), "the street under the cursor: " .. t)
	t = PV.who(50, 198)
	ok(t:find("edge=777", 1, true) and t:find("ours=probably", 1, true), t)
	t = PV.who(778)
	ok(t:find("ours=no (no record", 1, true), t)
	t = PV.who(779)
	ok(t:find("rebuilt locked", 1, true), t)
	t = PV.who(880)
	ok(t:find("ours=likely town=13 src=plain/sr", 1, true) and t:find("recorded as edge 870", 1, true), t)
	t = PV.who(4242)
	ok(t:find("is no edge", 1, true), t)
	t = PV.who(5000, 5000)
	ok(t:find("no street within", 1, true), t)
	-- a save without our script state
	set_global("api", fakeApi(edges, nil, nil))
	t = PV.who(778)
	ok(t:find("no game script state", 1, true), t)
	set_global("api", fakeApi(edges, { gx = {} }, nil))
	t = PV.who(778)
	ok(t:find("no record on this save yet", 1, true), t)
	t = PV.who()
	ok(t:find("no point", 1, true), t)
end)

test("source through the proposal: the spec edges keep origin and the near-miss kind (2026-10-20 run: all plain/<key>)", function()
	local PR = ug_require(F.DIR .. "ot_proposal.lua")
	local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
	local inc = {
		nodes = { { entity = -4, x = 100, y = 0, z = 0 }, { entity = -5, x = 200, y = 0, z = 0 },
			{ entity = -6, x = 300, y = 0, z = 0 } },
		edges = {
			{ entity = -1, node0 = 500, node1 = -4, p0 = { 0, 0, 0 }, p1 = { 100, 0, 0 }, t0 = { 100, 0, 0 },
				t1 = { 100, 0, 0 }, class = "small", template = SMALL, key = "conn:812", origin = "link" },
			{ entity = -2, node0 = -4, node1 = -5, p0 = { 100, 0, 0 }, p1 = { 200, 0, 0 }, t0 = { 100, 0, 0 },
				t1 = { 100, 0, 0 }, class = "small", template = SMALL, key = "nm:4:9", origin = "nearMiss",
				nearMiss = true, nearMissKind = "pair", nearMissCorner = true },
			{ entity = -3, node0 = -5, node1 = -6, p0 = { 200, 0, 0 }, p1 = { 300, 0, 0 }, t0 = { 100, 0, 0 },
				t1 = { 100, 0, 0 }, class = "small", template = SMALL, key = "mvg1", origin = "m:village_green" },
		},
		joins = { { node = 500, edge = -1 } },
	}
	local spec = assert(PR.build(inc, { nodes = { [500] = { hasConfig = true, edges = { 900 }, lanes = 4, src = 900,
		template = SMALL } }, sources = { [SMALL] = 901 }, fallback = 902 }))
	eq(PV.source(nil, spec.edges[1]), "link/conn")
	eq(PV.source(nil, spec.edges[2]), "nm:pairc")
	eq(PV.source(nil, spec.edges[3]), "m:village_green/mvg")
end)

test("console who(): a long street under the cursor (its middle far off: the octree matches middles), errors print", function()
	-- (2026-10-20_0228_sqot-sqrl: "no street within 40 m" with the cursor on a street)
	local edges = { [901] = { p0 = { 0, 0 }, p1 = { 400, 0 }, locked = true }, [902] = { p0 = { 0, 100 }, p1 = { 60, 100 } } }
	local pv = "12," .. PV.entry({ id = 901, src = "link/conn", year = 1931, p0 = { 0, 0 }, p1 = { 400, 0 } })
	set_global("api", fakeApi(edges, { pv = pv }, { 20, 5 }))
	local t = PV.who()
	ok(t:find("edge=901", 1, true) and t:find("ours=yes", 1, true), t)
	-- nothing within PICK_R: says how far the nearest is
	t = PV.who(200, 60)
	ok(t:find("no street within 40 m", 1, true) and t:find("the nearest street 60 m", 1, true), t)
	-- an engine error: still one WHO line, with the reason
	local A = fakeApi(edges, { pv = pv }, { 20, 5 })
	A.engine.getComponent = function() error("boom") end
	A.engine.util.octree.findEntitiesInCircle = function() error("octree down") end
	set_global("api", A)
	t = PV.who()
	ok(t:find("[SQOT] WHO no street", 1, true) and t:find("octree down", 1, true), t)
	A.gui = nil
	t = PV.who()
	ok(t:find("[SQOT] WHO no point", 1, true), t)
	set_global("api", nil)
	t = PV.who(5)
	ok(t:find("[SQOT] WHO", 1, true), t)
end)
