-- The steering lock (§69, 2026-10-15; ot_lockpol + ot_glock tips + the ot_select look rules + the driver wiring): which
-- streets a steer town locks (young vs grown, inside the outline vs at the rim and beyond, toward forest / water /
-- neighbours / against the land), the share falling with the maturity, the game-street lock only at the rim, a locked
-- branch with its tip open (and never by the woods), the lead cap and the continuous arm front (no bare spikes), the
-- bridge's target rule, the rake and wiggle rules, old saves, the loop caps.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local LP = ug_require(F.DIR .. "ot_lockpol.lua")
local GL = ug_require(F.DIR .. "ot_glock.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")
local SK = ug_require(F.DIR .. "ot_skeleton.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local BR = ug_require(F.DIR .. "ot_bridge.lua")

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN = 7

-- a town of radius ~300 m: housed streets all round
local function roundTown(r)
	local items = {}
	for k = 0, 31 do
		local a = (k + 0.5) * 2 * math.pi / 32
		for _, f in ipairs({ 0.3, 0.65, 1.0 }) do items[#items + 1] = { math.cos(a) * r * f, math.sin(a) * r * f, 3 } end
	end
	return LP.outline(items, 0, 0)
end

local function leanField(to)
	local lean = {}
	for i = 1, 16 do lean[i] = math.cos((i - 1) * 2 * math.pi / 16 - to) end
	return { n = 16, lean = lean, k = 0.3, peak = to }
end

local function radial(a, d0, d1)
	return { math.cos(a) * d0, math.sin(a) * d0 }, { math.cos(a) * d1, math.sin(a) * d1 }
end

test("outline: per sector the housed streets' quantile, smoothed; empty sectors lower; none without houses", function()
	local ol = roundTown(300)
	ok(ol and ol.n == LP.SECTORS)
	for i = 1, ol.n do ok(math.abs(ol.r[i] - 300) < 40, "sector " .. i .. ": " .. ol.r[i]) end
	near(LP.rAt(ol, 0.3), LP.rAt(ol, 0.3 + 2 * math.pi), 1e-6)
	-- a town reaching 600 m east only
	local items = {}
	for x = 50, 600, 25 do items[#items + 1] = { x, 0, 2 } end
	for k = 0, 15 do items[#items + 1] = { 100 * math.cos(k * math.pi / 8), 100 * math.sin(k * math.pi / 8), 2 } end
	local ol2 = LP.outline(items, 0, 0)
	ok(LP.rAt(ol2, 0) > 2 * LP.rAt(ol2, math.pi), string.format("east %.0f west %.0f", LP.rAt(ol2, 0), LP.rAt(ol2, math.pi)))
	eq(LP.outline({ { 10, 10, 0 } }, 0, 0), nil, "no housed street")
	eq(LP.outline({}, 0, 0), nil)
	local ro = LP.roundOutline(5, 5, 50)
	eq(LP.rAt(ro, 1), LP.OUTLINE_MIN, "at least OUTLINE_MIN")
	-- bad coordinates are skipped
	ok(LP.outline({ { 0 / 0, 0, 3 }, { 100, 0, 3 } }, 0, 0) ~= nil)
end)

test("innerK: 0 young, INNER_K[2] grown, monotone", function()
	eq(LP.innerK(0), LP.INNER_K[1])
	near(LP.innerK(1), LP.INNER_K[2], 1e-9)
	near(LP.innerK(nil), LP.INNER_K[2], 1e-9)
	local last = -1
	for m = 0, 1, 0.05 do
		local k = LP.innerK(m)
		ok(k >= last - 1e-12)
		last = k
	end
end)

test("policy: young -> every mod street locked; grown -> inside open (fill), the rim and beyond locked", function()
	local ol = roundTown(300)
	local inner = { radial(0.4, 80, 160) }
	local e = { p0 = inner[1], p1 = select(2, radial(0.4, 80, 160)) }
	local young, wy = LP.decide(e, { outline = ol, mat = 0 })
	eq(young, true); eq(wy, "rim")
	local grown, wg = LP.decide(e, { outline = ol, mat = 1 })
	eq(grown, false); eq(wg, "fill")
	-- beyond the outline: "out" at any maturity
	local p0, p1 = radial(1.0, 330, 420)
	eq(select(2, LP.decide({ p0 = p0, p1 = p1 }, { outline = ol, mat = 1 })), "out")
	-- between the inner zone and the outline: "rim"
	p0, p1 = radial(1.0, 265, 290)
	eq(select(2, LP.decide({ p0 = p0, p1 = p1 }, { outline = ol, mat = 1 })), "rim")
	-- half grown: the inner zone is smaller
	p0, p1 = radial(2.0, 170, 200)
	eq(select(2, LP.decide({ p0 = p0, p1 = p1 }, { outline = ol, mat = 1 })), "fill")
	eq(select(2, LP.decide({ p0 = p0, p1 = p1 }, { outline = ol, mat = 0.35 })), "rim")
end)

test("policy: toward forest / water / a neighbour's gap locked inside too; against the land lean only at the rim", function()
	local ol = roundTown(300)
	-- woods east beyond x = 260 (an inner street at 150-220 m east faces them within the skeleton's clearance)
	local fg = FO.fromFunction(0, 0, function(x, _y) return x > 260 and 200 or 0 end, 1500, 50)
	local e = { p0 = { 150, 0 }, p1 = { 220, 0 } }
	eq(select(2, LP.decide(e, { outline = ol, mat = 1, ctx = { fg = fg } })), "face:forest")
	eq(select(2, LP.decide({ p0 = { -150, 0 }, p1 = { -220, 0 } }, { outline = ol, mat = 1, ctx = { fg = fg } })), "fill")
	-- water north
	local wet = function(_x, y) return y > 300 end
	eq(select(2, LP.decide({ p0 = { 0, 150 }, p1 = { 0, 220 } }, { outline = ol, mat = 1, ctx = { wet = wet } })), "face:water")
	-- a neighbour 1 km south
	local gp = GP.build({ 0, 0 }, { { x = 0, y = -900, town = 2 } }, 3)
	eq(select(2, LP.decide({ p0 = { 0, -250 }, p1 = { 0, -280 } }, { outline = ol, mat = 1, ctx = { gaps = gp } })), "face:neighbour")
	-- the lean toward the east: a rim street west is "against the land"; an inner one west is not
	local field = leanField(0)
	eq(select(2, LP.decide({ p0 = { -270, 0 }, p1 = { -290, 0 } }, { outline = ol, mat = 1, ctx = { field = field } })), "face:lean")
	eq(select(2, LP.decide({ p0 = { -100, 0 }, p1 = { -150, 0 } }, { outline = ol, mat = 1, ctx = { field = field } })), "fill")
	-- a street running round the town (tangential) probes outward, not along itself
	local ox, oy, ux, uy = LP.outward({ 150, -30 }, { 150, 30 }, 0, 0)
	ok(ux > 0.9, string.format("%.2f %.2f %.2f %.2f", ox, oy, ux, uy))
end)

test("policy: a skeleton arm stays locked while young (ARM_FREE_MAT), open inside once grown", function()
	local ol = roundTown(300)
	local sh = { id = "linear", centre = { 0, 0 }, axis = 0, arms = { 0, math.pi }, block = 100, ka = 2, kb = 0.6 }
	local e = { p0 = { 100, 0 }, p1 = { 180, 0 } }
	local SH = ug_require(F.DIR .. "ot_shape.lua")
	ok(SH.inArm(sh, 140, 0))
	eq(select(2, LP.decide(e, { outline = ol, mat = 0.5, shape = sh })), "arm")
	eq(select(2, LP.decide(e, { outline = ol, mat = 0.9, shape = sh })), "fill")
	eq(select(2, LP.decide(e, { outline = ol, mat = 0.9 })), "fill")
end)

test("lock share falls with the maturity (the same streets: young ~all locked, grown under 0.6)", function()
	local ol = roundTown(300)
	local edges = {}
	for k = 0, 23 do
		local a = k * 2 * math.pi / 24
		for _, d in ipairs({ 60, 120, 180, 240, 300, 360 }) do
			local p0, p1 = radial(a, d, d + 40)
			edges[#edges + 1] = { p0 = p0, p1 = p1 }
		end
	end
	local function share(mat)
		local n = 0
		for _, e in ipairs(edges) do if LP.decide(e, { outline = ol, mat = mat }) then n = n + 1 end end
		return n / #edges
	end
	local s0, s5, s1 = share(0), share(0.5), share(1)
	ok(s0 >= 0.95, "young " .. s0)
	ok(s5 < s0 and s1 < s5, string.format("%.2f > %.2f > %.2f", s0, s5, s1))
	ok(s1 <= 0.6, "grown " .. s1)
end)

test("game streets: inside never locked; at the rim only facing forest / water / against the land, or beyond while young", function()
	local ol = roundTown(300)
	local fg = FO.fromFunction(0, 0, function(x, _y) return x > 380 and 200 or 0 end, 1500, 50)
	local c = { outline = ol, mat = 1, ctx = { fg = fg, field = leanField(math.pi / 2) } }
	local why, open = LP.gameLock({ p0 = { 50, 0 }, p1 = { 120, 0 } }, c)
	eq(why, nil); eq(open, "inside")
	eq(LP.gameLock({ p0 = { 270, 0 }, p1 = { 330, 0 } }, c), "face:forest")
	-- north: the lean's heading, open land: stays open (the game develops there)
	why, open = LP.gameLock({ p0 = { 0, 280 }, p1 = { 0, 340 } }, c)
	eq(why, nil); eq(open, "open")
	-- south: against the lean
	eq(LP.gameLock({ p0 = { 0, -280 }, p1 = { 0, -340 } }, c), "face:lean")
	-- young: north beyond the outline is locked too (the early steering); on the rim inside the outline not
	c.mat = 0
	eq(LP.gameLock({ p0 = { 0, 320 }, p1 = { 0, 380 } }, c), "young")
	eq(select(2, LP.gameLock({ p0 = { 0, 262 }, p1 = { 0, 290 } }, c)), "open")
	-- the probes are cached per edge id (static): a second call reads the cache
	local fc = {}
	local cc0 = { outline = ol, mat = 1, ctx = c.ctx, faceCache = fc }
	eq(LP.gameLock({ id = 9, p0 = { 270, 0 }, p1 = { 330, 0 } }, cc0), "face:forest")
	eq(fc[9], "forest")
	fc[9] = false
	eq(LP.gameLock({ id = 9, p0 = { 270, 0 }, p1 = { 330, 0 } }, cc0), nil, "from the cache")
	-- classify uses it: the open ones are skipped as steerIn / steerOk
	local ed = { id = 1, n0 = 1, n1 = 2, p0 = { 50, 0, 0 }, p1 = { 120, 0, 0 }, template = SMALL, objects = 0, etype = "normal" }
	local cc = { own = {}, seen = { [1] = -1e9 }, nowUs = 0, steer = function(e) return LP.gameLock(e, c) end }
	eq(select(2, GL.classify(ed, cc)), "steerIn")
	ed.p0, ed.p1 = { 270, 0, 0 }, { 330, 0, 0 }
	eq(select(2, GL.classify(ed, cc)), nil, "facing the woods: locked")
end)

-- a branch east from the rim: three new edges, the last a dead end
local function branch(x0)
	return {
		{ key = "b1", node0 = 5, node1 = -1, p0 = { x0, 0 }, p1 = { x0 + 80, 0 } },
		{ key = "b2", node0 = -1, node1 = -2, p0 = { x0 + 80, 0 }, p1 = { x0 + 160, 0 } },
		{ key = "b3", node0 = -2, node1 = -3, p0 = { x0 + 160, 0 }, p1 = { x0 + 240, 0 } },
	}
end

test("tips: a locked branch keeps its outward dead end open; never by the woods, too far in, past the max or too close to another", function()
	local edges = branch(300)
	local locked = { b1 = "out", b2 = "out", b3 = "out" }
	local ctx = { field = leanField(0) }
	local picks, rej = GL.pickTips(edges, locked, ctx, 0, 0, 300, {}, 2)
	eq(#picks, 1); eq(picks[1].key, "b3")
	-- the tip by dense forest (within CLEAR_M of the dead end): no tip
	local fg = FO.fromFunction(0, 0, function(x, y) return (x > 560 and math.abs(y) < 300) and 200 or 0 end, 1500, 50)
	picks, rej = GL.pickTips(edges, locked, { fg = fg }, 0, 0, 300, {}, 2)
	eq(#picks, 0); eq(rej.forest, 1)
	ok(SK.pointClear(fg, 540, 0) < SK.CLEAR_M)
	-- an inner branch (dead end inside TIP_OUT x the extent): no tip
	picks, rej = GL.pickTips(branch(-50), locked, ctx, 0, 0, 600, {}, 2)
	eq(#picks, 0); eq(rej.inner, 1)
	-- the policy's reason must be a branch's: a "face:" or "fill" street is no tip
	picks = GL.pickTips(edges, { b3 = "face:forest" }, ctx, 0, 0, 300, {}, 2)
	eq(#picks, 0)
	-- max 0: none; an open valve in the same heading: kept apart
	eq(#GL.pickTips(edges, locked, ctx, 0, 0, 300, {}, 0), 0)
	picks, rej = GL.pickTips(edges, locked, ctx, 0, 0, 300, { { a = 0.1 } }, 2)
	eq(#picks, 0); eq(rej.sep, 1)
end)

test("steerKeys: the branch is built locked along its length, its tip open (PR.build); the tally; without inputs all locked", function()
	local ol = roundTown(300)
	local inc = { edges = branch(300) }
	local job = { inc = inc, style = {}, ext = { cx = 0, cy = 0, r = 300 }, steerTipMax = 2, steerOpen = {},
		steerC = { outline = ol, cx = 0, cy = 0, mat = 1, ctx = { field = leanField(0) } } }
	local keys, n, mode = D.steerKeys(job)
	eq(mode, "steer")
	ok(keys.b1 and keys.b2 and not keys.b3, "locked along, the tip open")
	eq(n, 2)
	eq(job.steerTally.out, 2); eq(job.steerTally.tip, 1)
	eq(#job.steerTips, 1)
	ok(LP.tallyText(job.steerTally):find("tip:1", 1, true))
	-- without the policy's inputs: every street locked (as "mod")
	local k2, n2 = D.steerKeys({ inc = { edges = branch(300) }, style = {} })
	eq(n2, 3); ok(k2.b3)
	-- PR.build: the tip edge goes out unlocked, the rest locked
	local pinc = { nodes = { { entity = -1, x = 380, y = 0, z = 10 }, { entity = -2, x = 460, y = 0, z = 10 },
		{ entity = -3, x = 540, y = 0, z = 10 } }, edges = {}, joins = { { node = 5, edge = -11 } } }
	local prev = 5
	for i, e in ipairs(branch(300)) do
		pinc.edges[i] = { entity = -10 - i, node0 = prev, node1 = -i, p0 = { e.p0[1], 0, 10 }, p1 = { e.p1[1], 0, 10 },
			t0 = { 80, 0, 0 }, t1 = { 80, 0, 0 }, class = "small", template = SMALL, key = e.key }
		prev = -i
	end
	local info = { nodes = { [5] = { hasConfig = true, edges = { 1 }, lanes = 4, src = 1, template = SMALL } },
		sources = { [SMALL] = 1 }, fallback = 1, edgeLanes = { [1] = 4 }, lock = false, lockKeys = keys, unlockKeys = { b3 = true } }
	local spec = PR.build(pinc, info)
	ok(spec, "built")
	local lk = {}
	for _, e in ipairs(spec.edges) do lk[e.key] = e.locked == true end
	ok(lk.b1 and lk.b2 and not lk.b3)
end)

-------------------------------------------------------------------------------------------------------------------
-- driver

local function edge(id, x0, y0, x1, y1, extra)
	local e = { id = id, n0 = id * 10, n1 = id * 10 + 1, p0 = { x0, y0, 10 }, p1 = { x1, y1, 10 },
		t0 = { x1 - x0, y1 - y0, 0 }, t1 = { x1 - x0, y1 - y0, 0 }, template = SMALL, lanes = 4, objects = 0,
		owned = false, inConstruction = false, locked = false, etype = "normal" }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

local function fakeE()
	local E = { t = 0, logs = {}, events = {}, sent = {} }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.name(t) return "Town" .. t end
	function E.closestTown() return TOWN end
	function E.context() return {} end
	function E.sendEvent(_id, name, param) E.events[#E.events + 1] = { name = name, param = param } end
	return E
end

local function logsWith(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do if l:find("[SQOT] " .. what, 1, true) then out[#out + 1] = l end end
	return out
end

local function steerDriver(E, mat)
	local d = D.new(E)
	d.opts = { debug = false }
	d:townState(TOWN).lockMode = "steer"
	d:townState(TOWN).lockMat = mat
	local fg = FO.fromFunction(0, 0, function(x, _y) return x > 420 and 200 or 0 end, 1500, 50)
	d:townState(TOWN).forest = fg
	d:glockState(TOWN).ctx = { grower = "organic", field = leanField(math.pi / 2), fg = fg }
	return d
end

-- a measured town: housed streets round the centre (radius ~300), rim streets east (toward the woods), north (open, the
-- lean), and inner game streets
local function measured()
	local edges, built, lot = {}, {}, {}
	local id = 0
	for k = 0, 15 do
		local a = k * 2 * math.pi / 16
		for _, d0 in ipairs({ 100, 200 }) do
			id = id + 1
			local p0, p1 = radial(a, d0, d0 + 60)
			edges[#edges + 1] = edge(id, p0[1], p0[2], p1[1], p1[2])
			built[id] = 3
		end
	end
	edges[#edges + 1] = edge(101, 280, 0, 340, 0)     -- rim east, toward the woods
	edges[#edges + 1] = edge(102, 0, 280, 0, 340)     -- rim north, open land
	edges[#edges + 1] = edge(103, 0, 50, 0, 90)       -- inner
	for _, e in ipairs(edges) do lot[#lot + 1] = { id = e.id } end
	return { ext = { cx = 0, cy = 0, r = 300 }, edges = edges, lotEdges = lot, builtBy = built, dem = { mat = nil } }
end

test("driver (steer, grown): the CHECK keeps the inner and the open rim game streets; queues the rim street facing the woods", function()
	local E = fakeE()
	local d = steerDriver(E, 1)
	local m = measured()
	m.dem.mat = 1
	d:steerNote(TOWN, m, nil)
	ok(d:townState(TOWN).outline ~= nil)
	eq(d:townState(TOWN).lockShare, 0)
	local job = { town = TOWN }
	d:glockNote(job, TOWN, m, 0, nil)
	E.t = (GL.SETTLE_S + 1) * 1e6
	local gs = d:glockNote(job, TOWN, m, E.t, nil)
	local q = {}
	for _, c in ipairs(job.glockQ or {}) do q[c.id] = true end
	ok(q[101], "east rim street toward the woods queued")
	ok(not q[102] and not q[103], "north (open, the lean) and inner kept")
	ok((gs.tally.steerIn or 0) > 0 and (gs.tally.steerOk or 0) > 0)
	-- steer towns pick no game anchor and no stub: their valves are tips
	eq(#gs.valves, 0); eq(gs.stubWant, nil)
	eq(#logsWith(E, "VALVE"), 0)
end)

test("driver (steer, young): rim game streets beyond the outline locked too; the share counted", function()
	local E = fakeE()
	local d = steerDriver(E, 0)
	local m = measured()
	m.dem.mat = 0
	m.edges[#m.edges + 1] = edge(104, 0, 330, 0, 400)   -- north, beyond the outline
	m.edges[#m.edges].locked = false
	m.lotEdges[#m.lotEdges + 1] = { id = 104 }
	m.edges[1].locked = true
	d:steerNote(TOWN, m, nil)
	ok(d:townState(TOWN).lockShare > 0)
	local job = { town = TOWN }
	d:glockNote(job, TOWN, m, 0, nil)
	E.t = (GL.SETTLE_S + 1) * 1e6
	d:glockNote(job, TOWN, m, E.t, nil)
	local q = {}
	for _, c in ipairs(job.glockQ or {}) do q[c.id] = true end
	ok(q[104], "young: beyond the outline locked")
	ok(not q[103], "inner kept")
end)

test("driver (steer): a build's tips open as tip valves; buildInfo leaves them unlocked; the CHECK counts them", function()
	local E = fakeE()
	local d = steerDriver(E, 1)
	local m = measured()
	m.dem.mat = 1
	d:steerNote(TOWN, m, nil)
	-- a branch north into the open land (the lean)
	local inc = { edges = {
		{ key = "n1", node0 = 5, node1 = -1, p0 = { 0, 300 }, p1 = { 0, 380 } },
		{ key = "n2", node0 = -1, node1 = -2, p0 = { 0, 380 }, p1 = { 0, 460 } } } }
	local job = { town = TOWN, inc = inc, ext = m.ext, style = { grower = "organic" }, edges = {} }
	d:jobLock(job)
	eq(job.townLock, "steer")
	d:steerPrep(job)
	ok(job.steerC and job.steerTipMax >= 1, tostring(job.steerTipMax))
	job.lockKeys, job.lockN, job.lockModeUsed = D.lockKeys(job)
	eq(job.lockModeUsed, "steer")
	ok(job.lockKeys.n1 and not (job.lockKeys.n2), "n1 locked, the tip n2 open")
	local info = d:buildInfo(job)
	eq(info.lock, false)
	ok(info.unlockKeys and info.unlockKeys.n2)
	job.spec = { edges = { { key = "n1", locked = true, p0 = { 0, 300 }, p1 = { 0, 380 } }, { key = "n2", p0 = { 0, 380 }, p1 = { 0, 460 } } } }
	d:glockStubBuilt(job, 0)
	local gs = d:glockState(TOWN)
	eq(#gs.valves, 1); eq(gs.valves[1].kind, "tip")
	eq(D.tipCount(gs.valves), 1)
	ok(logsWith(E, "VALVE")[1]:find("kind=tip", 1, true))
	-- the tip's zone keeps the game's new streets there open while it is open
	local x, y = gs.valves[1].x, gs.valves[1].y
	ok(GL.inZone(gs.valves[1], x, y + 100))
	-- a Works link of a steer town: locked all along
	local wj = { town = TOWN, edges = {}, style = {}, lockModeUsed = "works", lockKeys = {} }
	eq(d:buildInfo(wj).lock, true)
end)

test("old saves: lm = 1 stays \"mod\" (everything locked), no lm legacy, lm = 2 steer; new frames save lm = 2 and gk", function()
	local E = fakeE()
	local d = D.new(E)
	local saved = SV.normalize(nil)
	saved = SV.applyFrame(saved, { town = 1, a = 0, x = 0, y = 0, lm = 1, gk = 1 })
	saved = SV.applyFrame(saved, { town = 2, a = 0, x = 0, y = 0 })
	saved = SV.applyFrame(saved, { town = 3, a = 0, x = 0, y = 0, lm = 2, gk = 1 })
	eq(d:townLockMode(1, saved), "mod")
	eq(d:townLockMode(2, saved), "legacy")
	eq(d:townLockMode(3, saved), "steer")
	eq(d:townLockMode(4, saved), "steer", "no frame: the default")
	ok(d:townGameLock(3, saved) and d:townGameLock(1, saved) and not d:townGameLock(2, saved))
	local fp = SV.frameParam(5, { axis = 0, centre = { 0, 0 } }, nil, nil, nil, { lock = "steer", gameLock = true })
	eq(fp.lm, 2); eq(fp.gk, 1)
	eq(SV.frame(SV.applyFrame(nil, fp), 5).lockMode, "steer")
	-- (a "mod" town's job locks every street: no policy keys)
	eq(D.lockKeys({ townLock = "mod", inc = { edges = branch(300) } }), nil)
	ok(D.lockFamily("steer") and D.lockFamily("mod") and not D.lockFamily("legacy"))
end)

-------------------------------------------------------------------------------------------------------------------
-- spikes: the lead cap and the continuous arm front

test("lead cap: LEAD_BLOCKS blocks within LEAD_CAP; the select holds a piece farther from housed (2+) streets", function()
	eq(LP.leadCap({ block = { len = 40, depth = 30 } }), LP.LEAD_CAP[1])
	eq(LP.leadCap({ block = { len = 200, depth = 40 } }), LP.LEAD_CAP[2])
	eq(LP.leadCap({ block = { len = 90, depth = 40 } }), 180)
	-- a housed street 0..100 m (its midpoint at 50 m), a dead end at 100 m, plan pieces on east to 400 m
	-- (a street west to -400 m, unhoused: the growth front's quantile reaches past the pieces)
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 100, y = 0 }, { id = 3, x = -100, y = 0 },
		{ id = 4, x = -200, y = 0 }, { id = 5, x = -300, y = 0 }, { id = 6, x = -400, y = 0 } },
		edges = { { id = 10, node0 = 1, node1 = 2, built = 4 }, { id = 11, node0 = 3, node1 = 1, built = 0 },
			{ id = 12, node0 = 4, node1 = 3, built = 0 }, { id = 13, node0 = 5, node1 = 4, built = 0 },
			{ id = 14, node0 = 6, node1 = 5, built = 0 } } })
	local mp = { junctions = { A = { 100, 0 }, B = { 200, 0 }, C = { 300, 0 }, D = { 400, 0 } },
		pieces = { { key = "p1", a = "A", b = "B", pts = { { 100, 0 }, { 200, 0 } }, class = "small" },
			{ key = "p2", a = "B", b = "C", pts = { { 200, 0 }, { 300, 0 } }, class = "small" },
			{ key = "p3", a = "C", b = "D", pts = { { 300, 0 }, { 400, 0 } }, class = "small" } } }
	local style = F.style({ forceStyle = "EU_ORGANIC" })
	style.centre = { 0, 0 }
	local function keys(lim)
		local st, rep = SEL.select(g, mp, style, { join = "deadEnd", joinR = 100, maxEdges = 6, limits = lim })
		local out = {}
		for _, s in ipairs(st) do out[s.key] = true end
		return out, rep
	end
	local free, frep = keys(nil)
	ok(free.p1, "MAX_LEAD_M 400")
	eq(frep.leadHeld, 0)
	local capped, crep = keys({ leadCap = 150, housedMin = 2 })
	ok(capped.p1 and not capped.p2 and not capped.p3, "within 150 m of the housed street only")
	ok(crep.leadHeld >= 1)
	-- one house is no front (housedMin 2): a 2-house street west counts, the 1-house one does not
	g.edgeById[10].built = 1
	g.edgeById[11].built = 2
	local one, orep = keys({ leadCap = 150, housedMin = 2 })
	ok(not one.p1 and orep.leadHeld >= 1, "measured from the 2-house street (-50 m): 250 m to p1's far end")
	-- none with housedMin: the plain index (a young core is never left without a limit)
	g.edgeById[11].built = 0
	local fb = keys({ leadCap = 150, housedMin = 2 })
	ok(fb.p1 and not fb.p2)
	g.edgeById[10].built = 4
end)

test("continuous arm front: one far house no longer moves an arm's front out (the Merehythe spike)", function()
	near(LP.contFront({ 150, 220, 300 }, 100, 100), 300, 1e-9)
	near(LP.contFront({ 150, 600 }, 100, 100), 150, 1e-9, "the gap to 600 is too wide")
	near(LP.contFront({}, 120, 100), 120, 1e-9)
	near(LP.contFront({ 50, 80 }, 120, 100), 120, 1e-9)
	eq(LP.armGap({ block = { len = 60, depth = 30 } }), LP.ARM_GAP_MIN)
	-- the select's arm fill front: a linear town east, houses to 200 m and one far house at 900 m along the arm
	local style = F.style({ forceStyle = "EU_ORGANIC" })
	local sh = { id = "linear", centre = { 0, 0 }, axis = 0, arms = { 0, math.pi }, ka = 2, kb = 0.6, reach = 1 }
	style.shape = sh
	local nodes, edges = {}, {}
	local id = 0
	local function add(x0, x1, b)
		id = id + 1
		nodes[#nodes + 1] = { id = 2 * id, x = x0, y = 0 }
		nodes[#nodes + 1] = { id = 2 * id + 1, x = x1, y = 0 }
		edges[#edges + 1] = { id = id, node0 = 2 * id, node1 = 2 * id + 1, built = b, template = SMALL }
	end
	for x = -200, 150, 50 do add(x, x + 50, 3) end
	add(880, 920, 3)
	add(-300, -260, 3)
	local g = OG.fromSnapshot({ nodes = nodes, edges = edges })
	local raw = SEL.armBuiltFronts(g, style, nil, nil)
	local cont = SEL.armBuiltFronts(g, style, nil, { armCont = 100, housedMin = 2, leadCap = 200 })
	ok(raw and cont)
	ok(cont.trimmed >= 1, "trimmed " .. tostring(cont.trimmed))
	ok(cont[1] < raw[1] - 300, string.format("east front %.0f < %.0f", cont[1], raw[1]))
	-- (the lead cap binds the skeleton's reach: at most leadCap beyond the continuous front)
	ok(cont[1] <= math.max(cont.rq, 200) + 200 + 1e-6)
end)

-------------------------------------------------------------------------------------------------------------------
-- bridges: a target or a short crossing

test("bridge target: far-bank houses, an industry or a town ahead; not back across the water; the length rule", function()
	-- a crossing heading north: C at (0, 300), far street 70 m
	local bp = { heading = math.pi / 2, far = 70, approach = 64, span = 136,
		inc = { nodes = { { x = 0, y = 70 }, { x = 0, y = 230 }, { x = 0, y = 300 } } } }
	eq(BR.length(bp), 270)
	eq(BR.target(bp, {}), nil)
	eq(BR.target(bp, { { x = 100, y = 380, kind = "houses" } }), "houses")
	eq(BR.target(bp, { { x = 0, y = 0, kind = "houses" } }), nil, "the near bank")
	eq(BR.target(bp, { { x = 100, y = 1400, kind = "town" } }), "town", "ahead within the cone")
	eq(BR.target(bp, { { x = 1300, y = 400, kind = "town" } }), nil, "off the heading")
	eq(BR.target(bp, { { 120, 340, kind = "industry" } }), "industry", "positional")
	ok(BR.length(bp) > BR.EMPTY_MAX_M, "Merehythe's 270 m crossing needs a target")
end)

-------------------------------------------------------------------------------------------------------------------
-- look rules: rakes and wiggles

local function spine()
	-- a street east 0..400 with three north spurs (80 m) at x = 100, 200, 400; x = 300 has none yet
	local nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 100, y = 0 }, { id = 3, x = 200, y = 0 }, { id = 4, x = 300, y = 0 },
		{ id = 5, x = 400, y = 0 }, { id = 6, x = 500, y = 0 }, { id = 12, x = 100, y = 80 }, { id = 13, x = 200, y = 80 },
		{ id = 15, x = 400, y = 80 } }
	local edges = { { id = 101, node0 = 1, node1 = 2 }, { id = 102, node0 = 2, node1 = 3 }, { id = 103, node0 = 3, node1 = 4 },
		{ id = 104, node0 = 4, node1 = 5 }, { id = 105, node0 = 5, node1 = 6 }, { id = 112, node0 = 2, node1 = 12 },
		{ id = 113, node0 = 3, node1 = 13 }, { id = 115, node0 = 5, node1 = 15 } }
	return OG.fromSnapshot({ nodes = nodes, edges = edges })
end

test("rake: a third parallel spur waits; a cross street joining two spurs' tips closes the block", function()
	local g = spine()
	local mp = { junctions = { J4 = { 300, 0 }, T4 = { 300, 80 }, T2 = { 100, 80 }, T3 = { 200, 80 } },
		pieces = { { key = "spur4", a = "J4", b = "T4", pts = { { 300, 0 }, { 300, 80 } }, class = "small" },
			{ key = "join23", a = "T2", b = "T3", pts = { { 100, 80 }, { 200, 80 } }, class = "small" } } }
	local style = F.style({ forceStyle = "EU_ORGANIC" })
	style.centre = { 250, 0 }
	style.block = { len = 100, depth = 40 }
	local function run(lim)
		local st, rep = SEL.select(g, mp, style, { join = "any", joinR = 60, maxEdges = 6, limits = lim, terrain = F.flat })
		local out = {}
		for _, s in ipairs(st) do out[s.key] = true end
		return out, rep
	end
	local plain = run(nil)
	ok(plain.spur4, "without the rule: the third tooth")
	local st, rep = run({ steer = true })
	ok(not st.spur4, "the third tooth waits")
	ok(st.join23, "the block closed")
	ok(rep.rakeHeld >= 1 and rep.rakeJoin >= 1, string.format("held %d join %d", rep.rakeHeld, rep.rakeJoin))
	-- only the held spur left: it gives way rather than an empty increment
	local mp2 = { junctions = mp.junctions, pieces = { mp.pieces[1] } }
	local st2 = SEL.select(g, mp2, style, { join = "any", joinR = 60, maxEdges = 6, limits = { steer = true }, terrain = F.flat })
	ok(#st2 >= 1, "relaxed when nothing else fits")
end)

test("wiggle: an arm extending a dead end may not turn back against its last corner or over TURN_MAX", function()
	-- A (-100, -60) -> B (0, 0) -> C (100, 0): the street turned right at B; a dead end at C
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = -100, y = -60 }, { id = 2, x = 0, y = 0 }, { id = 3, x = 100, y = 0 },
		{ id = 4, x = -100, y = 80 } },
		edges = { { id = 11, node0 = 1, node1 = 2 }, { id = 12, node0 = 2, node1 = 3 }, { id = 13, node0 = 2, node1 = 4 } } })
	local mp = { junctions = { C = { 100, 0 }, D = { 200, 60 }, E = { 200, 0 }, K = { 150, 95 } },
		pieces = { { key = "zig", a = "C", b = "D", pts = { { 100, 0 }, { 200, 60 } }, class = "main" },
			{ key = "straight", a = "C", b = "E", pts = { { 100, 0 }, { 200, 0 } }, class = "main" },
			{ key = "sharp", a = "C", b = "K", pts = { { 100, 0 }, { 150, 95 } }, class = "main" } } }
	local style = F.style({ forceStyle = "EU_ORGANIC" })
	style.centre = { 0, 0 }
	local function run(lim)
		local st, rep = SEL.select(g, mp, style, { join = "any", joinR = 60, maxEdges = 6, limits = lim, terrain = F.flat,
			leadDepth = false })
		local out = {}
		for _, s in ipairs(st) do out[s.key] = true end
		return out, rep
	end
	local plain = run(nil)
	ok(plain.zig or plain.sharp, "without the rule a turning piece comes")
	local st, rep = run({ steer = true })
	ok(st.straight, "straight on")
	ok(not st.zig and not st.sharp, "no zig back, no sharp turn")
	ok(rep.wiggleHeld >= 2, "held " .. rep.wiggleHeld)
end)

test("loop caps: outline, pickTips, contFront and steerKeys read at most SCAN_MAX entries", function()
	local cap = LP.SCAN_MAX
	LP.SCAN_MAX = 5
	local items = {}
	for i = 1, 50 do items[i] = { i * 10, 0, 1 } end
	local ol = LP.outline(items, 0, 0)
	eq(ol.housed, 5)
	local along = {}
	for i = 1, 50 do along[i] = i * 10 end
	ok(LP.contFront(along, 0, 100) <= 50)
	local edges = {}
	for i = 1, 40 do edges[i] = { key = "k" .. i, node0 = -i, node1 = -i - 1, p0 = { i * 10, 0 }, p1 = { i * 10 + 10, 0 } } end
	local keys, n = D.steerKeys({ inc = { edges = edges }, style = {} })
	eq(n, 5)
	LP.SCAN_MAX = cap
	local gcap = GL.SCAN_MAX
	GL.SCAN_MAX = 3
	local why = {}
	for i = 1, 40 do why["k" .. i] = "out" end
	local picks = GL.pickTips(edges, why, {}, 0, 0, 100, {}, 10)
	ok(#picks <= 3)
	GL.SCAN_MAX = gcap
	ok(keys.k1)
end)
