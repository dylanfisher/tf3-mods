-- otd_runner against the REAL main-mod modules (ot_driver & co., loaded from mods/square_organic_towns with a small
-- loader, as the game's cross-mod ug_require would) and a fake engine: inspector, Grow now (increments + forced
-- growth passes), city-type styles, dry run, undo, fast-forward, hooks (pause, debug, devBusy), main busy wait.
-- run_tests: no-split

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns_dev/"
local MAIN_DIR = here .. "../../mods/square_organic_towns/content"

local mainCache = {}
local function mainReq(path)
	if mainCache[path] ~= nil then return mainCache[path] end
	local rel = path:match("^square_organic_towns::(/.*)$")
	assert(rel, "not a main-mod path: " .. tostring(path))
	local env = setmetatable({ ug_require = mainReq }, { __index = _ENV })
	local chunk = assert(loadfile(MAIN_DIR .. rel, "t", env))
	local m = chunk()
	mainCache[path] = m
	return m
end
local function main(name) return mainReq("square_organic_towns::/organic_towns/" .. name .. ".lua") end

local D, SV, OG, PR, H, ST = main("ot_driver"), main("ot_saved"), main("ot_graph"), main("ot_proposal"), main("ot_hooks"),
	main("ot_style")
local T = main("ot_terrain")
local S = ug_require "/organic_towns_dev/otd_shared.lua"
local UN = ug_require "/organic_towns_dev/otd_undo.lua"
local R = ug_require "/organic_towns_dev/otd_runner.lua"

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN, TOWN2 = 100, 200
local FLAT = T.sampler(function() return 20 end)

local function dist(p, x, y) return math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) end

--- A 3 x 3 block town (100 m) with two plain dead ends (east, north), all lots built (no open frontage).
local function world()
	local W = { nodes = {}, edges = {}, nextNode = 0, nextEdge = 100 }
	local at = {}
	local function node(x, y, cfg)
		W.nextNode = W.nextNode + 1
		W.nodes[W.nextNode] = { id = W.nextNode, x = x, y = y, z = 10, cfg = cfg ~= false }
		at[x .. ":" .. y] = W.nextNode
		return W.nextNode
	end
	local function edge(a, b)
		W.nextEdge = W.nextEdge + 1
		local na, nb = W.nodes[a], W.nodes[b]
		W.edges[#W.edges + 1] = { id = W.nextEdge, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
			t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
			objects = 0, owned = false, inConstruction = false, parcels = 10, built = 10 }
	end
	for _, x in ipairs({ -100, 0, 100 }) do for _, y in ipairs({ -100, 0, 100 }) do node(x, y) end end
	for _, x in ipairs({ -100, 0, 100 }) do edge(at[x .. ":-100"], at[x .. ":0"]); edge(at[x .. ":0"], at[x .. ":100"]) end
	for _, y in ipairs({ -100, 0, 100 }) do edge(at["-100:" .. y], at["0:" .. y]); edge(at["0:" .. y], at["100:" .. y]) end
	local e1 = node(200, 0); edge(at["100:0"], e1)
	local e3 = node(0, 200); edge(at["0:100"], e3)
	W.deadEnds = { e1, e3 }
	W.nextNode, W.nextEdge = 1000, 5000
	return W
end

local function fakes(o)
	o = o or {}
	local W = world()
	local E = { t = 0, logs = {}, grows = {}, prechecks = {}, W = W, sf = { 1, 1, 1 }, events = {} }
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return o.cfg or { nameList = "square_names_us_texas::/names/usa/usa.names", climate = "temperate" } end
	end
	function E.modParams() return o.params or { act_on = 3 }, {} end
	function E.gameTime() return 10 * SV.FRESH_GAME_TIME end
	function E.year() return 1970 end
	function E.balance() return 1e6 end
	function E.towns() return { TOWN, TOWN2 } end
	function E.name(t) return "Town" .. t end
	function E.boxCentre(t) if t == TOWN2 then return 5000, 5000 end return 0, 0 end
	function E.townCaps(t)
		if t == TOWN2 then return { target = 100, actual = 100, sizeFactors = { 1, 1, 1 } } end
		return { target = 1000, actual = 950, sizeFactors = { E.sf[1], E.sf[2], E.sf[3] } }
	end
	function E.town2buildings() return {} end
	function E.townBuildings(t)
		if t == TOWN2 then return {}, {} end
		local pts, builtBy = {}, {}
		for x = -90, 90, 30 do for y = -90, 90, 30 do pts[#pts + 1] = { x, y } end end
		for _, e in ipairs(W.edges) do builtBy[e.id] = e.built end
		return pts, builtBy
	end
	function E.parcelMap()
		local m = {}
		for _, e in ipairs(W.edges) do if e.parcels then m[e.id] = { n = e.parcels } end end
		return m
	end
	function E.parcelCount(pd) return pd.n end
	function E.closestTown(x, y) if dist({ x, y }, 5000, 5000) < 1000 then return TOWN2 end return TOWN end
	function E.streets(x, y, r)
		local out = {}
		for _, e in ipairs(W.edges) do if dist(e.p0, x, y) <= r or dist(e.p1, x, y) <= r then out[#out + 1] = e end end
		return out
	end
	function E.nodeStreetEdges(n)
		local out = {}
		for _, e in ipairs(W.edges) do if e.n0 == n or e.n1 == n then out[#out + 1] = e.id end end
		return out
	end
	function E.hasConfig(n) return W.nodes[n] ~= nil and W.nodes[n].cfg end
	function E.nodeInConstruction() return false end
	function E.sampler() return FLAT end
	function E.proposal(spec) return { spec = spec } end
	function E.context() return {} end
	function E.precheck(p)
		E.prechecks[#E.prechecks + 1] = p
		return { ok = true, msgs = {}, collisions = 0, buildings = 0, cost = 1000, us = 100 }
	end
	function E.sendBuild(p, _ctx, cb) E.pending = { spec = p.spec, cb = cb } end
	function E.sendEvent(id, name, param) E.events[#E.events + 1] = { id = id, name = name, param = param } end
	function E.growTown(t, f, cb)
		E.grows[#E.grows + 1] = { town = t, f = f }
		if t == TOWN then E.sf = { f[1], f[2], f[3] } end
		-- growth adopts our streets: their nodes get configs (so the next increment can join their dead ends)
		if not o.noAdoption then for _, nd in pairs(W.nodes) do nd.cfg = true end end
		cb(true)
	end
	--- the engine applies a sent spec (new node ids from 1001, edges from 5001), then calls back
	function E.apply()
		local spec, cb = E.pending.spec, E.pending.cb
		E.pending = nil
		local map = {}
		for _, nd in ipairs(spec.nodes) do
			W.nextNode = W.nextNode + 1
			W.nodes[W.nextNode] = { id = W.nextNode, x = nd.pos[1], y = nd.pos[2], z = nd.pos[3], cfg = false }
			map[nd.entity] = W.nextNode
		end
		for _, n in ipairs(spec.joins) do W.nodes[n].cfg = true end
		for _, e in ipairs(spec.edges) do
			W.nextEdge = W.nextEdge + 1
			W.edges[#W.edges + 1] = { id = W.nextEdge, n0 = map[e.node0] or e.node0, n1 = map[e.node1] or e.node1, p0 = e.p0,
				p1 = e.p1, t0 = e.t0, t1 = e.t1, template = SMALL, lanes = 4, objects = 0, owned = false, inConstruction = false }
		end
		cb(true, { cost = 300000, msgs = {} })
	end
	local X = { markersCalls = {}, sent = nil, pushed = {} }
	function X.edge(id)
		for _, e in ipairs(W.edges) do
			if e.id == id then return { n0 = e.n0, n1 = e.n1, owned = e.owned, objects = e.objects } end
		end
		return nil
	end
	function X.hasLights() return false end
	function X.removalProposal(plan) return { removal = plan }, #plan.cfgPrune end
	function X.send(p, _ctx, cb) X.sent = { p = p, cb = cb } end
	function X.markers(edges, s) X.markersCalls[#X.markersCalls + 1] = { n = #edges, s = s } return #edges * 3 end
	function X.pushStatus(st) X.pushed[#X.pushed + 1] = st return true end
	function X.log(l) E.logs[#E.logs + 1] = l end
	local r = R.new({ D = D, E = E, SV = SV, OG = OG, PR = PR, H = H, X = X, UN = UN })
	return r, E, X
end

local function has(E, text)
	for _, l in ipairs(E.logs) do if l:find(text, 1, true) then return l end end
	return nil
end

local function count(E, text)
	local n = 0
	for _, l in ipairs(E.logs) do if l:find(text, 1, true) then n = n + 1 end end
	return n
end

--- Ticks the runner (0.1 s steps); the engine applies sent builds at once. Stops when idle or after n ticks.
local function run(r, E, n, keepPending)
	for _ = 1, n or 2000 do
		r:tick(E.t)
		E.t = E.t + 100000
		if E.pending and not keepPending then E.apply() end
		if r.task == nil and #r.tasks == 0 then return true end
	end
	return false
end

before_each(function()
	H.paused, H.devBusy, H.debug, H.main, H.player, H.diagnose = false, false, nil, nil, nil, false
end)

test("styles: the picker lists main, region and every ot_style profile", function()
	eq(S.STYLES[1].id, "main")
	eq(S.STYLES[2].id, "region")
	eq(#S.STYLES, #ST.IDS + 2)
	for i, id in ipairs(ST.IDS) do eq(S.STYLES[i + 2].id, id) end
end)

test("select by camera position -> inspector lines and status", function()
	local r, E = fakes()
	local st = r:command({ action = "select", x = 10, y = 20 }, E.t, S)
	eq(r.selected, TOWN)
	eq(st.town, "Town100")
	local text = table.concat(st.townLines, "\n")
	ok(text:find("Needs room: YES", 1, true), text)
	ok(text:find("Main mod style: NA_", 1, true) and text:find("style from site (plain:", 1, true), text)
	ok(text:find("Dead ends: 2 joinable", 1, true), text)
	ok(text:find("main driver not visible", 1, true), text)
	ok(has(E, "[SQOT_DEV] INSPECT town=100"))
	eq(st.main, false)
	-- a town without buildings
	local st2 = r:command({ action = "select", town = TOWN2 }, E.t, S)
	ok(st2.townLines[2]:find("Too few buildings", 1, true), st2.townLines[2])
	-- picking a style re-inspects with a second style line
	r:command({ action = "select", town = TOWN }, E.t, S)
	local st3 = r:command({ action = "style", style = S.index(S.STYLES, "EU_ORGANIC") }, E.t, S)
	ok(table.concat(st3.townLines, "\n"):find("Picked style (EU_ORGANIC): EU_ORGANIC", 1, true))
end)

test("actions need a picked town; unknown actions are refused", function()
	local r, E = fakes()
	r:command({ action = "grow" }, E.t, S)
	eq(#r.tasks, 0)
	ok(has(E, "REFUSED action=grow why=pick_a_town_first"))
	r:command({ action = "nonsense" }, E.t, S)
	ok(has(E, "why=unknown_action"))
end)

test("Grow now: n increments, each built (forced) then 3 growth passes; devBusy while it runs", function()
	local r, E = fakes()
	for _, e in ipairs(E.W.edges) do e.built = 2 end   -- plenty of open frontage: the trigger would say no
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "grow", n = 2, factor = 2 }, E.t, S)   -- 3 increments? no: S.N[2] = 3
	eq(#r.tasks, 1)
	eq(r.tasks[1].n, S.N[2])
	r:tick(E.t)
	ok(H.devBusy, "the main driver is held while dev tasks run")
	local fin = run(r, E)
	if not fin then for i = math.max(1, #E.logs - 25), #E.logs do print(E.logs[i]) end end
	ok(fin, "finished")
	ok(not H.devBusy)
	local built = count(E, "[SQOT_DEV] BUILT")
	if built < 2 then for _, l in ipairs(E.logs) do if not l:find("PLANEDGE") then print(l) end end end
	ok(built >= 2, "built " .. built)
	eq(#E.grows, built * R.GROW_PASSES)
	near(E.grows[1].f[1], 1.5, 1e-9)          -- S.FACTORS[2]
	near(E.grows[2].f[1], 1.5, 1e-9)          -- second pass at the reached size
	ok(has(E, "STEP task=grow town=100 increment=1/3 outcome=built"))
	ok(has(E, "DONE task=Grow_now"))
	eq(#r.driver.towns[TOWN].history, built)
	eq(r.driver.towns[TOWN].builds, built)
	ok(#E.events >= 1 and E.events[1].name == SV.EV_FRAME, "the first build saves the town's frame (main mod event)")
end)

test("Grow now stops when the planner finds nothing", function()
	local r, E = fakes()
	for _, n in ipairs(E.W.deadEnds) do E.W.nodes[n].cfg = false end   -- no joinable dead end
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "grow", n = 4 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "outcome=empty"))
	ok(has(E, "result=stopped:empty"))
	eq(#E.grows, 0)
end)

test("city types: Grow now in EU organic and JP dense builds with that style", function()
	for _, id in ipairs({ "EU_ORGANIC", "JP_DENSE", "region" }) do
		local r, E = fakes()
		r:command({ action = "select", town = TOWN }, E.t, S)
		r:command({ action = "grow", n = 1, style = S.index(S.STYLES, id) }, E.t, S)
		ok(run(r, E))
		local want = id == "region" and "NA_GRID" or id    -- a US map's region picks the grid
		ok(has(E, "STEP task=grow town=100 increment=1/1 outcome=built style=" .. want), id)
	end
end)

test("Plan only: planned and pre-checked, never sent; edges logged and marked", function()
	local r, E, X = fakes()
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "dry", style = S.index(S.STYLES, "NA_GRID") }, E.t, S)
	ok(run(r, E, 2000, true))
	eq(E.pending, nil, "nothing sent")
	ok(has(E, "[SQOT_DEV] DRY town=100"))
	ok(count(E, "PLANEDGE") > 0)
	eq(#X.markersCalls, 1)
	eq(X.markersCalls[1].s, R.MARKER_S)
	local st = r:status()
	ok(st.plan:find("Town100", 1, true), st.plan)
	r:command({ action = "markers" }, E.t, S)
	eq(#X.markersCalls, 2)
	-- the dev mod turns the per-edge diagnosis on: a dry run pre-checks every edge alone
	eq(H.diagnose, true)
	local sum = has(E, "[SQOT_DEV] DIAGSUM town=100 whole=ok")
	ok(sum and sum:find("failed=0", 1, true), tostring(sum))
end)

test("Build as player toggle: off by default (SEND player=off), on sends with the player", function()
	local r, E = fakes()
	local args = {}
	function E.context(asPlayer) args[#args + 1] = asPlayer return {} end
	eq(r:status().player, false, "default off")
	r:command({ action = "player", on = false }, E.t, S)
	eq(H.player, false)
	eq(r:status().player, false)
	ok(has(E, "[SQOT_DEV] PLAYER on=false"))
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "grow", n = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "player=off"), "SEND says player=off")
	eq(args[#args], false)
	r:command({ action = "player", on = true }, E.t, S)
	eq(H.player, true)
	ok(r:status().player)
end)

test("Undo: removes the last increment's edges, prunes the joint config, forgets the record", function()
	local r, E, X = fakes()
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "grow", n = 1 }, E.t, S)
	ok(run(r, E))
	local rec = r.driver.towns[TOWN].history[1]
	ok(rec and #rec.edges > 0)
	r:command({ action = "undo" }, E.t, S)
	run(r, E, 5)
	if not X.sent then for _, l in ipairs(E.logs) do if not l:find("PLANEDGE") then print(l) end end end
	ok(X.sent, "removal sent")
	local plan = X.sent.p.removal
	eq(plan.edges, (function() local c = {} for i, e in ipairs(rec.edges) do c[i] = e end table.sort(c) return c end)())
	for _, n in ipairs(plan.cfgPrune) do ok(E.W.nodes[n].cfg, "pruned only nodes with a config: " .. n) end
	ok(#plan.cfgPrune >= 1, "the joint gets its config back to a dead end")
	ok(has(E, "[SQOT_DEV] UNDO town=100 edges="))
	X.sent.cb(true, { cost = 5 })
	ok(run(r, E))
	ok(has(E, "UNDONE town=100"))
	eq(#r.driver.towns[TOWN].history, 0)
	-- nothing left to undo
	r:command({ action = "undo" }, E.t, S)
	ok(run(r, E))
	ok(has(E, "why=nothing_built_this_session"))
end)

test("Undo picks the newest record of the main driver when it is visible; main busy delays dev tasks", function()
	local r, E, X = fakes()
	local mainDriver = D.new(E)
	mainDriver.saved = SV.applyInit(nil, { known = {}, fresh = true })
	mainDriver:townState(TOWN).history[1] = { edges = { 101 }, us = 50, joins = {}, nodes = {} }
	H.main = mainDriver
	r:command({ action = "select", town = TOWN }, E.t, S)
	ok(r:status().main)
	mainDriver.job = { town = TOWN, stage = "assess" }
	r:command({ action = "undo" }, E.t, S)
	run(r, E, 10)
	eq(X.sent, nil, "waits while the main driver has a job")
	mainDriver.job = nil
	run(r, E, 5)
	ok(X.sent)
	eq(X.sent.p.removal.edges, { 101 })
end)

test("Fast-forward: every acted-on town grows one pass, then the trigger decides", function()
	local r, E = fakes({ params = { act_on = 3 } })
	r:command({ action = "fast", m = 1, factor = 1 }, E.t, S)
	ok(run(r, E))
	eq(#E.grows, 2, "both towns grown once")
	near(E.grows[1].f[1], 1.25, 1e-9)
	ok(has(E, "[SQOT_DEV] CHECK town=100"), "the normal check ran")
	ok(count(E, "[SQOT_DEV] BUILT") == 1, "town 100 has no open frontage: built")
	ok(has(E, "ROUND round=1 of=1 built=1"))
end)

test("Fast-forward with New towns only skips the towns the main mod leaves alone", function()
	local r, E = fakes({ params = { act_on = 2 } })
	local mainDriver = D.new(E)
	mainDriver.saved = SV.applyInit(nil, { known = { TOWN }, fresh = false })
	H.main = mainDriver
	r:command({ action = "fast", m = 1 }, E.t, S)
	ok(run(r, E))
	eq(#E.grows, 1)
	eq(E.grows[1].town, TOWN2)
end)

test("pause, debug and stop commands", function()
	local r, E = fakes()
	r:command({ action = "pause", on = true }, E.t, S)
	ok(H.paused)
	ok(r:status().paused)
	r:command({ action = "pause", on = false }, E.t, S)
	ok(not H.paused)
	r:command({ action = "debug", mode = "on" }, E.t, S)
	eq(H.debug, true)
	eq(r:status().debug, "on")
	r:command({ action = "debug", mode = "off" }, E.t, S)
	eq(H.debug, false)
	r:command({ action = "debug", mode = "param" }, E.t, S)
	eq(H.debug, nil)
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "growTown" }, E.t, S)
	r:command({ action = "growAll" }, E.t, S)
	eq(#r.tasks, 2)
	r:tick(E.t)
	r:command({ action = "stop" }, E.t, S)
	eq(#r.tasks, 0)
	ok(run(r, E))
	ok(has(E, "result=stopped"))
end)

-- (2026-10-13: the fake town has two game dead ends (configured). Which form the seeded draw picks decides whether the
-- first increment uses both or one (round 5's NA_SUBURB weights draw radiating -> cross, one arm per increment), so the
-- test no longer counts on one build: Grow stops once only our own config-less dead ends are left.)
test("own dead ends: without adoption Grow stops once only our own dead ends are left; the toggle joins them", function()
	local r, E = fakes({ noAdoption = true })
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "grow", n = 4 }, E.t, S)
	ok(run(r, E))
	local built = count(E, "[SQOT_DEV] BUILT")
	ok(built >= 1 and built <= 2, "at most one build per game dead end: " .. built)
	ok(has(E, "result=stopped:empty"), "stopped with nothing joinable")
	local snap
	for _, l in ipairs(E.logs) do if l:find("[SQOT_DEV] SNAPSHOT", 1, true) then snap = l end end
	ok(snap and snap:find("joinable=0", 1, true) and snap:find("noConfig:", 1, true),
		"our own config-less dead ends are not joined (noJoin=...noConfig:n): " .. tostring(snap))
	r:command({ action = "ownJoins", on = true }, E.t, S)
	ok(r:status().ownJoins)
	r:command({ action = "grow", n = 1 }, E.t, S)
	ok(run(r, E))
	eq(count(E, "[SQOT_DEV] BUILT"), built + 1)
	local first
	for _, l in ipairs(E.logs) do if first == nil and l:find("[SQOT_DEV] SEND", 1, true) then first = l end end
	ok(first and first:find("cfgRemove=%d+[,%d]*_cfgAdd="), "first build removed the engine configs: " .. tostring(first))
	-- the second build joined script nodes (no config): added, never removed
	local last
	for _, l in ipairs(E.logs) do if l:find("[SQOT_DEV] SEND", 1, true) then last = l end end
	ok(last:find("cfgRemove=_", 1, true), last)
end)

-- Motifs (main mod ot_motif, M0 2026-10-13): the Town tab's motif picker forces a kind on the picked town's Grow now /
-- Plan only through startJob opts.motif; the STYLE / MOTIF lines and the inspector show it; ALLTOWN carries motifs=.
test("motifs: the picker lists main + every ot_motif kind", function()
	local MO = main("ot_motif")
	eq(S.MOTIFS[1].id, "main")
	local ids = {}
	for _, id in ipairs(MO.IDS) do if MO.BY_ID[id] and not MO.BY_ID[id].test then ids[#ids + 1] = id end end
	eq(#S.MOTIFS, #ids + 1)
	for i, id in ipairs(ids) do eq(S.MOTIFS[i + 1].id, id) end
end)

test("motifs: a forced motif (dev) reaches the job, the STYLE and MOTIF lines; main keeps its own", function()
	local r, E = fakes()
	r:command({ action = "select", town = TOWN }, E.t, S)
	ok(has(E, "STYLE town=100 mode=main") and has(E, "STYLE town=100 mode=main"):find("motifs=", 1, true))
	eq(has(E, "src=forced"), nil, "no forced motif before the picker")
	r:command({ action = "style", motif = S.index(S.MOTIFS, "hill_road") }, E.t, S)
	eq(r:status().motif, "hill_road")
	local text = table.concat(r:status().townLines, "\n")
	ok(text:find("force hill_road", 1, true), text)
	r:command({ action = "dry" }, E.t, S)
	ok(has(E, "QUEUE task=Plan_only") and has(E, "QUEUE task=Plan_only"):find("motif=hill_road", 1, true))
	ok(run(r, E))
	local st
	for _, l in ipairs(E.logs) do if l:find("STYLE town=100", 1, true) and l:find("motifs=hill_road", 1, true) then st = l end end
	ok(st, "STYLE line with the forced motif")
	ok(st:find("shape=linear", 1, true), "forced hill road: the shape linear " .. st)
	local mo = has(E, "MOTIF town=100")
	ok(has(E, "MOTIF town=100 name=Town100 event=pick kind=hill_road src=forced why=forced(dev)"), tostring(mo))
	-- back to the main mod's own motifs
	r:command({ action = "style", motif = 1 }, E.t, S)
	eq(r:status().motif, "main")
	r:command({ action = "allTowns" }, E.t, S)
	ok(has(E, "ALLTOWN n=1") and has(E, "ALLTOWN n=1"):find("motifs=", 1, true), tostring(has(E, "ALLTOWN n=1")))
	local at = has(E, "ALLTOWN n=1")
	ok(at:find("bareLen=", 1, true) and at:find("foreignLen=", 1, true) and at:find("modLen=", 1, true), at)
end)

test("streetMeasures (NEXT_PHASE_BRIEF 52.3): empty streets split into bare / another town's houses; mod streets", function()
	local function ed(id, x0, x1, locked) return { id = id, n0 = id * 10, n1 = id * 10 + 1, p0 = { x0, 0 }, p1 = { x1, 0 }, locked = locked } end
	-- a Works town's snapshot: its own housed edge 1, the parent's housed edges 2-3, a bare edge 4 (a mod street)
	local m = { edges = { ed(1, 0, 100), ed(2, 100, 300), ed(3, 300, 400), ed(4, 400, 450, true) }, builtBy = { [1] = 3 } }
	local ctx = { any = { [1] = 3, [2] = 5, [3] = 1 }, mod = { [3] = true } }
	local sm = R.streetMeasures(m, ctx)
	eq(math.floor(sm.len + 0.5), 450)
	eq(math.floor(sm.emptyLen + 0.5), 350, "empty for the town itself (as before)")
	eq(math.floor(sm.foreignLen + 0.5), 300, "the parent's houses")
	eq(math.floor(sm.bareLen + 0.5), 50, "no house of any town")
	eq(math.floor(sm.modLen + 0.5), 150, "locked or built this session")
	local old = R.streetMeasures(m)
	eq(math.floor(old.emptyLen + 0.5), 350)
	eq(old.bareLen, 0)
	eq(old.foreignLen, 0)
end)

test("Place test stops (named): one stop per theme the town offers, capped, handed to the main driver's naming", function()
	local r, E, X = fakes()
	r.NM = main("ot_names")
	local handed = {}
	-- the main driver: stop themes by position (east: hill, west: shore, else centre) and the dev-stop hook
	H.main = { phase = "run", job = nil, inflight = false, towns = {}, counts = { checks = 0, builds = 0, fails = 0, refused = 0 } }
	function H.main:stopSite(_t, x, _y)
		if x > 20 then return { dz = 30, dist = 400 } elseif x < -20 then return { wet = "shore", dist = 400 } end
		return { dist = 50 }
	end
	function H.main:addDevStops(list) for _, e in ipairs(list) do handed[#handed + 1] = e end return #list end
	local groups, nextG = { [1] = true }, 1
	local built = {}
	function X.stopModel() return "::/stations/street/small_stops/small_new.con" end
	function X.stopProposal(id, model, name) return { stopOn = id, model = model, name = name }, nil end
	function X.stationGroups()
		local s = {}
		for g in pairs(groups) do s[g] = true end
		return s
	end
	function X.send(p, _ctx, cb)
		built[#built + 1] = p.stopOn
		nextG = nextG + 1
		groups[nextG] = true
		cb(true, { msgs = {} })
	end
	function E.groupStations(g) return { g * 10 } end
	local nameOf = E.name
	function E.name(e) if groups[e] then return "High Street" end return nameOf(e) end
	r:command({ action = "select", x = 10, y = 20 }, E.t, S)
	r:command({ action = "testStops" }, E.t, S)
	ok(run(r, E, 3000), "the task ends")
	ok(has(E, "TESTSTOP planned=3"), "hill, shore, centre")
	eq(#built, 3)
	eq(#handed, 3)
	ok(handed[1].st == handed[1].g * 10 and handed[1].n == "High Street")
	ok(has(E, "tag=hill") and has(E, "tag=shore") and has(E, "tag=centre"))
	ok(has(E, "named=main"))
	-- caps
	local old = R.TESTSTOP_MAX
	R.TESTSTOP_MAX = 1
	built, handed = {}, {}
	r:command({ action = "testStops" }, E.t, S)
	ok(run(r, E, 3000))
	R.TESTSTOP_MAX = old
	eq(#built, 1)
	-- without a town picked / all towns
	r.selected = nil
	r:command({ action = "testStops", all = true }, E.t, S)
	ok(run(r, E, 3000))
	H.main = nil
end)

test("Forest lane test (R2): a forced increment with lanes, growth, a second increment, LANETEST", function()
	local r, E = fakes()
	for _, e in ipairs(E.W.edges) do e.built = 2 end
	-- forest everywhere beyond 230 m of the centre (the town's streets end at 200 m)
	function E.forestReader(_cx, _cy, _rr, o)
		return { stats = { groups = 1, reads = 0, trees = 0, nonTree = 0, stride = 1, capped = false, listUs = 0 },
			step = function(self)
				for x = -1500, 1500, 10 do
					for y = -1500, 1500, 10 do
						if x * x + y * y > 230 * 230 then o.add(x, y, 1) end
					end
				end
				return true
			end }
	end
	r.driver.E.forestReader = E.forestReader
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "forestLane" }, E.t, S)
	eq(#r.tasks, 1)
	ok(run(r, E), "finished")
	local first = has(E, "LANETEST town=100 increment=1")
	ok(first, "first increment logged")
	ok(has(E, "FORESTLANE town=100") and has(E, "why=force"), "a forced lane")
	ok(has(E, "template=country_new_small"), "the 1970 era's country template")
	local fin = has(E, "laneLen=")
	ok(fin and fin:find("housesOnLane=0", 1, true) and fin:find("ok=true", 1, true), tostring(fin))
	ok(has(E, "LANETEST town=100 increment=2 outcome=built"), "the town builds on")
	ok(has(E, "DONE task=Forest_lane_test"))
	-- the houses-near helper
	eq(R.housesNear({ { 0, 10 }, { 0, 50 } }, { { { -100, 0 }, { 100, 0 } } }, 30), 1)
end)

test("Forest lane test without a town picked: it dry-runs the towns and builds where a plan crosses the forest", function()
	local r, E = fakes()
	for _, e in ipairs(E.W.edges) do e.built = 2 end
	function E.forestReader(_cx, _cy, _rr, o)
		return { stats = { groups = 1, reads = 0, trees = 0, nonTree = 0, stride = 1, capped = false, listUs = 0 },
			step = function(self)
				for x = -1500, 1500, 10 do
					for y = -1500, 1500, 10 do
						if x * x + y * y > 230 * 230 then o.add(x, y, 1) end
					end
				end
				return true
			end }
	end
	r.driver.E.forestReader = E.forestReader
	r.selected = nil
	r:command({ action = "forestLane" }, E.t, S)
	eq(#r.tasks, 1)
	ok(run(r, E), "finished")
	local p = has(E, "LANETEST pick=100")
	ok(p and not p:find("lanes=0", 1, true), tostring(p))
	ok(has(E, "LANETEST town=100 increment=2 outcome=built"), "built on the picked town")
	-- the candidate order: the picked town first, then by forest share
	local c = R.laneCandidates(5, { 1, 2, 3, 5 }, function(id) return ({ [1] = 0.1, [2] = 0.6 })[id] end)
	eq(c[1], 5); eq(c[2], 2); eq(c[3], 1); eq(c[4], 3)
end)

test("Forest lane test without a forest: noLane", function()
	local r, E = fakes()
	for _, e in ipairs(E.W.edges) do e.built = 2 end
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "forestLane" }, E.t, S)
	ok(run(r, E))
	ok(has(E, "result=noLane"), "no lane without trees")
end)

test("Industrial satellite probe (R7): a town with 10/10/200 across the water, grown, SATIND result", function()
	local r, E, X = fakes()
	-- a river at x = 500 (between the town and the site east of it)
	local wetS = T.sampler(function(x) return (x > 480 and x < 560) and -2 or 20 end)
	E.sampler = function() return wetS end
	r.driver.E.sampler = E.sampler
	local towns = { TOWN, TOWN2 }
	E.towns = function() return towns end
	local created
	function X.createTown(o, cb)
		created = o
		towns = { TOWN, TOWN2, 300 }
		cb(true)
		return true, {}
	end
	function X.landUse(t) if t == 300 then return { 12, 8, 190 } end end
	function X.townGrowth(t) return { initials = { 10, 10, 200 }, sizeFactors = { 1, 1, 1 } } end
	function X.buildingCounts() return { [300] = 14 } end
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "satInd" }, E.t, S)
	ok(run(r, E), "finished")
	ok(created and created.capsList[3] == 200, "industrial-heavy capacities")
	local l = has(E, "SATIND town=100 name=Town100 event=create")
	ok(l and l:find("across=true", 1, true), tostring(l))
	local res = has(E, "event=result")
	ok(res and res:find("indShare=0.90", 1, true) and res:find("onlyIndustry=true", 1, true), tostring(res))
	eq(#E.grows, R.SATIND_PASSES)
	ok(has(E, "DONE task=Industrial_satellite_probe"))
end)

test("Force deep forest (main mod deep forest round): the picked town plans deep on the dev drivers (DEEPDEV)", function()
	local r, E = fakes()
	r:command({ action = "deepForest" }, E.t, S)
	ok(not has(E, "DEEPDEV"), "no town picked: nothing")
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "deepForest" }, E.t, S)
	local l = has(E, "DEEPDEV town=" .. TOWN)
	ok(l and l:find("ok=true", 1, true), tostring(l))
	eq(r.driver:townState(TOWN).forceDeep, true)
	local deep, why = r.driver:deepFor(TOWN, r.driver:townState(TOWN), { id = "NA_GRID" }, nil, "main", {})
	ok(deep and why == "force", tostring(why))
end)

-- Strong characters (main mod ot_character, 2026-10-14): the Town tab's "Force character" sets the kind on the picked
-- town (CHARDEV); its list matches ot_character.IDS, plus "-" and "densify".
test("Force character: the picker lists every ot_character kind; the picked town plans as the kind (CHARDEV)", function()
	local CH = main("ot_character")
	eq(S.CHARS[1], "-")
	eq(S.CHARS[#S.CHARS], "densify")
	local listed = {}
	for _, id in ipairs(S.CHARS) do listed[id] = true end
	for _, id in ipairs(CH.IDS) do ok(listed[id], id .. " listed") end
	eq(#S.CHARS, #CH.IDS + 2)
	local r, E = fakes()
	r:command({ action = "forceChar", kind = "hilltop" }, E.t, S)
	ok(not has(E, "CHARDEV"), "no town picked: nothing")
	r:command({ action = "select", town = TOWN }, E.t, S)
	r:command({ action = "forceChar", kind = "hilltop" }, E.t, S)
	local l = has(E, "CHARDEV town=" .. TOWN)
	ok(l and l:find("kind=hilltop", 1, true) and l:find("ok=true", 1, true), tostring(l))
	eq(r.driver:charKindOf(TOWN), "hilltop")
	r:command({ action = "forceChar", kind = "densify" }, E.t, S)
	ok(r.driver:densifyActive(TOWN), "densify now")
	r:command({ action = "forceChar", kind = "-" }, E.t, S)
	eq(r.driver:townState(TOWN).forceChar, nil)
	eq(r.driver:densifyActive(TOWN), false)
end)
