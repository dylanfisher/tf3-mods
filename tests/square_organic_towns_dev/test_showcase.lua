-- Showcase (otd_showcase via otd_runner) against the REAL main-mod modules and a fake multi-town engine: layout on
-- a square island, serial town creation (diff of the town list, rename), round-robin growth (style towns build,
-- vanilla towns only grow), consecutive-refusal stops, stop + resume without duplicates, focus and status.
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

local D, SV, OG, PR, H, ST, I, MT = main("ot_driver"), main("ot_saved"), main("ot_graph"), main("ot_proposal"),
	main("ot_hooks"), main("ot_style"), main("ot_inputs"), main("ot_metrics")
local T = main("ot_terrain")
local S = ug_require "/organic_towns_dev/otd_shared.lua"
local UN = ug_require "/organic_towns_dev/otd_undo.lua"
local R = ug_require "/organic_towns_dev/otd_runner.lua"
local L = ug_require "/organic_towns_dev/otd_layout.lua"
local SC = ug_require "/organic_towns_dev/otd_showcase.lua"

-- The tests of the showcase mechanics (create, rounds, settle, density levers, probe twins, concurrent builds) run
-- with the v7 rows (Control B, four density levers, four probe twins, no form row: 34 towns without the roundabout
-- mod); the v8 rows have their own test at the end ("v8 rows").
local V8 = { density = L.DENSITY, probes = L.PROBES, forms = L.FORMS, controlB = L.CONTROL_B }
local function v7rows() L.DENSITY, L.PROBES, L.FORMS, L.CONTROL_B = L.DENSITY_V7, L.PROBES_V7, {}, true end
local function v8rows() L.DENSITY, L.PROBES, L.FORMS, L.CONTROL_B = V8.density, V8.probes, V8.forms, V8.controlB end
before_each(v7rows)

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local FLAT = T.sampler(function() return 20 end)
local HALF = 9000   -- island: |x|, |y| < HALF (v3: 30 towns need an 18 km island)

local function dist(x0, y0, x1, y1) return math.sqrt((x0 - x1) ^ 2 + (y0 - y1) ^ 2) end

--- Fake engine with towns created on demand: each new town is a 3 x 3 block grid (100 m) with two dead ends.
local function fakes(o)
	o = o or {}
	local W = { nodes = {}, edges = {}, nextNode = 0, nextEdge = 100, towns = {}, order = {} }
	local E = { t = 0, logs = {}, grows = {}, W = W, creates = 0, renames = 0, refuse = o.refuse or {} }
	local function node(x, y)
		W.nextNode = W.nextNode + 1
		W.nodes[W.nextNode] = { id = W.nextNode, x = x, y = y, z = 10, cfg = true }
		return W.nextNode
	end
	local function edge(a, b, built)
		W.nextEdge = W.nextEdge + 1
		local na, nb = W.nodes[a], W.nodes[b]
		W.edges[#W.edges + 1] = { id = W.nextEdge, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
			t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
			objects = 0, owned = false, inConstruction = false, parcels = built and 10 or nil, built = built and 10 or 0 }
	end
	local function townAt(cx, cy, id, name)
		local at = {}
		for _, dx in ipairs({ -100, 0, 100 }) do
			for _, dy in ipairs({ -100, 0, 100 }) do at[dx .. ":" .. dy] = node(cx + dx, cy + dy) end
		end
		for _, dx in ipairs({ -100, 0, 100 }) do
			edge(at[dx .. ":-100"], at[dx .. ":0"], true); edge(at[dx .. ":0"], at[dx .. ":100"], true)
		end
		for _, dy in ipairs({ -100, 0, 100 }) do
			edge(at["-100:" .. dy], at["0:" .. dy], true); edge(at["0:" .. dy], at["100:" .. dy], true)
		end
		edge(at["100:0"], node(cx + 200, cy), true)
		edge(at["0:100"], node(cx, cy + 200), true)
		W.towns[id] = { id = id, x = cx, y = cy, name = name, sf = { 1, 1, 1 } }
		W.order[#W.order + 1] = id
	end
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return { nameList = "square_names_us_texas::/names/usa/usa.names", climate = "temperate" } end
	end
	function E.modParams() return { act_on = 3 }, {} end
	function E.gameTime() return 10 * SV.FRESH_GAME_TIME end
	function E.year() return o.year or 1970 end
	function E.balance() return 1e6 end
	function E.towns()
		local out = {}
		for _, id in ipairs(W.order) do out[#out + 1] = id end
		table.sort(out)
		return out
	end
	function E.name(t) return W.towns[t] and W.towns[t].name or "?" end
	function E.boxCentre(t) local tw = W.towns[t] if tw then return tw.x, tw.y end return nil end
	function E.townCaps(t)
		local tw = W.towns[t]
		if tw == nil then return nil end
		return { target = 1000, actual = 950, sizeFactors = { tw.sf[1], tw.sf[2], tw.sf[3] } }
	end
	function E.town2buildings() return {} end
	function E.townBuildings(t)
		local tw = W.towns[t]
		if tw == nil then return {}, {} end
		local pts, builtBy = {}, {}
		for x = -90, 90, 30 do for y = -90, 90, 30 do pts[#pts + 1] = { tw.x + x, tw.y + y } end end
		for _, e in ipairs(W.edges) do builtBy[e.id] = e.built end
		return pts, builtBy
	end
	function E.parcelMap()
		local m = {}
		for _, e in ipairs(W.edges) do if e.parcels then m[e.id] = { n = e.parcels } end end
		return m
	end
	function E.parcelCount(pd) return pd.n end
	function E.closestTown(x, y)
		local best, bd = nil, math.huge
		for id, tw in pairs(W.towns) do
			local d = dist(x, y, tw.x, tw.y)
			if d < bd then best, bd = id, d end
		end
		return best
	end
	function E.streets(x, y, r)
		local out = {}
		for _, e in ipairs(W.edges) do
			if dist(e.p0[1], e.p0[2], x, y) <= r or dist(e.p1[1], e.p1[2], x, y) <= r then out[#out + 1] = e end
		end
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
		local town = E.closestTown(p.spec.edges[1].p0[1], p.spec.edges[1].p0[2])
		if E.refuse[E.name(town)] then
			return { ok = false, critical = true, msgs = { "Construction_Not_Possible" }, collisions = 0, buildings = 0, us = 100 }
		end
		return { ok = true, msgs = {}, collisions = 0, buildings = 0, cost = 1000, us = 100 }
	end
	function E.sendBuild(p, _ctx, cb)
		-- the engine applies the spec at once (new node ids, then edges), then calls back
		local spec = p.spec
		local map = {}
		for _, nd in ipairs(spec.nodes) do
			W.nextNode = W.nextNode + 1
			W.nodes[W.nextNode] = { id = W.nextNode, x = nd.pos[1], y = nd.pos[2], z = nd.pos[3], cfg = false }
			map[nd.entity] = W.nextNode
		end
		for _, e in ipairs(spec.edges) do
			W.nextEdge = W.nextEdge + 1
			W.edges[#W.edges + 1] = { id = W.nextEdge, n0 = map[e.node0] or e.node0, n1 = map[e.node1] or e.node1, p0 = e.p0,
				p1 = e.p1, t0 = e.t0, t1 = e.t1, template = SMALL, lanes = 4, objects = 0, owned = false, inConstruction = false,
				locked = e.locked == true or spec.locked == true }
		end
		cb(true, { cost = 400000, msgs = {} })
	end
	function E.sendEvent() end
	-- the driver's fill (main engine's developAt): recorded apart from the dev window's X.developAt
	E.develops = {}
	function E.developAt(x, y, streets, upgrade, cb)
		E.develops[#E.develops + 1] = { x, y, streets, upgrade }
		cb(true)
	end
	function E.growTown(t, f, cb)
		E.grows[#E.grows + 1] = { town = t, f = f }
		W.towns[t].sf = { f[1], f[2], f[3] }
		for _, nd in pairs(W.nodes) do nd.cfg = true end   -- growth adopts our streets
		cb(true)
	end
	local X = { pushed = {}, develops = {}, freezes = {}, destroyed = {} }
	function X.edgeGeom(id)
		for _, e in ipairs(W.edges) do if e.id == id then return { p0 = e.p0, p1 = e.p1 } end end
		return nil
	end
	function X.developAt(x, y, streets, upgrade, cb)
		X.develops[#X.develops + 1] = { x, y, streets, upgrade }
		cb(true)
	end
	function X.setDevelopmentActive(t, on, cb)
		X.freezes[#X.freezes + 1] = { t, on }
		cb(true)
	end
	function X.destroyTown(t, cb)
		-- the town goes; its streets stay (exercises the layout offset)
		X.destroyed[#X.destroyed + 1] = t
		W.towns[t] = nil
		for i = #W.order, 1, -1 do if W.order[i] == t then table.remove(W.order, i) end end
		cb(true)
	end
	function X.edge(id)
		for _, e in ipairs(W.edges) do
			if e.id == id then return { n0 = e.n0, n1 = e.n1, objects = 0, owned = false, locked = e.locked == true } end
		end
		return nil
	end
	function X.hasLights() return false end
	function X.markers() return 0 end
	function X.pushStatus(st) X.pushed[#X.pushed + 1] = st return true end
	function X.log(l) E.logs[#E.logs + 1] = l end
	function X.terrainBox() return { minX = -9500, maxX = 9500, minY = -9500, maxY = 9500 } end
	X.speed, X.speeds, X.weights = 1, {}, {}
	-- calendar: one game month per 10 s of (fake) real time; settle sets the speed
	function X.calendarMonths() return 2020 * 12 + E.t / 1e7 end
	function X.gameSpeed() return X.speed end
	function X.setGameSpeed(v, cb) X.speed = v; X.speeds[#X.speeds + 1] = v; cb(true) end
	function X.townWeights(t, w, cb) X.weights[#X.weights + 1] = { t, w }; cb(true) end
	function X.isWater(x, y) return math.abs(x) > HALF or math.abs(y) > HALF end
	function X.createTown(c, cb)
		E.creates = E.creates + 1
		local id = 1000 + E.creates
		-- the game names the town itself sometimes: exercise the rename
		townAt(c.x, c.y, id, E.creates % 2 == 0 and ("Town" .. id) or c.name)
		cb(true)
		return true, { angle0 = 0, initAngle0 = 0, caps0 = "100/100/100", angleSet = c.angle ~= nil }
	end
	function X.rename(t, name, cb)
		E.renames = E.renames + 1
		W.towns[t].name = name
		cb(true)
	end
	local r = R.new({ D = D, E = E, SV = SV, OG = OG, PR = PR, H = H, X = X, UN = UN, ST = ST, I = I, MT = MT, S = S, L = L,
		SC = SC, RB = o.RB, rbGeom = o.rbGeom, rbWhy = o.rbGeom and nil or "noMod" })
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

local function run(r, E, n)
	for _ = 1, n or 200000 do
		r:tick(E.t)
		E.t = E.t + 100000
		if r.task == nil and #r.tasks == 0 then return true end
	end
	return false
end

--- Spies on every driver's startJob (the dev driver and the showcase's pool drivers share the Driver class):
--- fn(town, opts) per job. Returns the restore function.
local function spyJobs(r, fn)
	local Drv = getmetatable(r.driver)
	local orig = Drv.startJob
	Drv.startJob = function(self, t, now, o)
		fn(t, o)
		return orig(self, t, now, o)
	end
	return function() Drv.startJob = orig end
end

local function dump(E, k)
	for i = math.max(1, #E.logs - (k or 40)), #E.logs do print(E.logs[i]) end
end

before_each(function()
	H.paused, H.devBusy, H.debug, H.main, H.player, H.diagnose = false, false, nil, nil, nil, false
	SC.PASS_S = 0
end)

test("shared: the window's N picker matches the showcase's", function()
	eq(S.SHOW_N, SC.NS)
end)

test("showcase: layout, 34 towns created one by one and renamed, N rounds, settle, report; main driver paused", function()
	local r, E = fakes()
	r:command({ action = "showcase", sn = 1 }, E.t, S)   -- N = 10
	local fin = run(r, E)
	if not fin then dump(E) end
	ok(fin, "finished")
	ok(H.paused, "main driver held after the showcase")
	ok(has(E, "[SQOT_DEV] SHOWCASE START n=10 resume=false"))
	ok(has(E, "SHOWCASE ISLAND"))
	local lay = has(E, "SHOWCASE LAYOUT towns=34 of=34 dropped=0")
	ok(lay, tostring(has(E, "SHOWCASE LAYOUT")))
	eq(count(E, "SHOWCASE PLACE"), 34)
	ok(has(E, "SHOWCASE PLACE key=NORDIC") and has(E, "SHOWCASE PLACE key=NORDIC"):find("coast=420m_", 1, true),
		tostring(has(E, "SHOWCASE PLACE key=NORDIC")))
	eq(E.creates, 34, "one create per town")
	eq(count(E, "SHOWCASE CREATED key="), 34)
	eq(E.renames, 17, "towns the game named otherwise were renamed")
	for _, id in ipairs(E.towns()) do ok(not E.name(id):find("^Town"), "renamed: " .. E.name(id)) end
	eq(has(E, "SHOWCASE CREATE key=PROBE_C_45"), nil, "Probe C off since v5")
	ok(has(E, "SHOWCASE PLACE key=SHAPE_LINEAR_LOCKFILL label=Shape:_linear_(locked+fill)")
		and has(E, "SHOWCASE PLACE key=SHAPE_LINEAR_LOCKFILL"):find("probe=lockfill twinOf=SHAPE_LINEAR", 1, true),
		tostring(has(E, "SHOWCASE PLACE key=SHAPE_LINEAR_LOCKFILL")))
	-- style towns built increments in their style, vanilla ones only grew
	ok(has(E, "STEP task=") == nil, "no Grow now steps")
	ok(has(E, "SHOWCASE STEP key=EU_ORGANIC") ~= nil)
	ok(count(E, "[SQOT_DEV] BUILT") >= 10, "built " .. count(E, "[SQOT_DEV] BUILT"))
	ok(has(E, "SEND town=") and has(E, "style=EU_ORGANIC"), "EU organic increments sent in their style")
	-- (2026-10-13: round 5's form weights drew the EU organic twin wide with 3 green reserves over both dead ends: it
	-- planned nothing; ot_core now relaxes the greens next to the dead ends when an increment comes out empty)
	ok(r.show.towns.EU_ORGANIC.built >= 1, "EU organic built " .. tostring(r.show.towns.EU_ORGANIC.built))
	local ctrl = has(E, "SHOWCASE STEP key=CONTROL_A")
	ok(ctrl and ctrl:find("outcome=growth", 1, true), tostring(ctrl))
	-- growth schedule: sizeFactors 1 + step x 0.25 for everyone
	local maxF = 0
	for _, g in ipairs(E.grows) do maxF = math.max(maxF, g.f[1]) end
	-- (+3 steps: the default settle's three passes, each one step further)
	ok(maxF <= 1 + 13 * SC.STEP_ADD + 1e-9 and maxF >= 1 + 1 * SC.STEP_ADD, "max factor " .. maxF)
	eq(count(E, "SHOWCASE TOWN key="), 34)
	local sum = has(E, "SHOWCASE SUMMARY towns=34 n=10")
	ok(sum, tostring(has(E, "SHOWCASE SUMMARY")))
	ok(has(E, "DONE task=Showcase") and has(E, "DONE task=Showcase"):find("result=done", 1, true))
	-- the era towns build as of 1900 with the old templates
	local era = r.show.towns.ERA_NA_1900
	ok(era and era.newTemplates == false and era.year == 1900)
	ok(has(E, "templates=old"), "a STYLE line with the old templates")
	ok(has(E, "SHOWCASE PLACE key=ERA_EU_1900") and has(E, "SHOWCASE PLACE key=ERA_EU_1900"):find("era=1900:old", 1, true))
	ok(has(E, "SHOWCASE PLACE key=NA_GRID") and has(E, "SHOWCASE PLACE key=NA_GRID "):find("era=1970:new", 1, true))
	-- rounds: growth batches (every active town back to back), ROUND lines, mod edges and adoption in TOWN lines
	ok(has(E, "batch=34"), "growth sent as one batch for all towns")
	eq(count(E, "SHOWCASE ROUND round="), 10)
	ok(has(E, "SHOWCASE TOWN key=NA_GRID ") and has(E, "SHOWCASE TOWN key=NA_GRID "):find("adoption=", 1, true))
	ok(sum:find("roundS=", 1, true) and sum:find("laneAssert=", 1, true), sum)
	local st = r:status()
	eq(#st.show.towns, 34)
	ok(st.show.head:find("34/34 towns", 1, true), st.show.head)
	ok(st.show.results and #st.show.results > 10, "results lines for the window")
end)

test("showcase: K consecutive refusals stop a town, the reason is logged; others go on", function()
	local r, E = fakes({ refuse = { ["EU organic"] = true } })
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	local stop = has(E, "SHOWCASE STOP key=EU_ORGANIC")
	ok(stop, "stopped")
	-- refused builds exclude their first piece; once those cut the plan off, empty plans stop it as well
	ok(stop:find("refused_x3", 1, true) or stop:find("empty_x4", 1, true), stop)
	ok(r.show.towns.EU_ORGANIC.fails >= 1)
	eq(r.show.towns.EU_ORGANIC.built, 0)
	local step = has(E, "SHOWCASE STEP key=EU_ORGANIC")
	-- (since the shape envelope, 2026-10-12, the fake town's seeded twin plans smaller: a refused plan halved to a
	-- tiny leftover counts as empty, why=tiny)
	ok((step:find("outcome=fail", 1, true) and step:find("Construction_Not_Possible", 1, true))
		or (step:find("outcome=empty", 1, true) and step:find("why=tiny", 1, true)), step)
	ok(r.show.towns.NA_GRID.built >= 1)
	local town = has(E, "SHOWCASE TOWN key=EU_ORGANIC")
	ok(town and not town:find("stopped=-", 1, true), tostring(town))
end)

test("showcase: Stop ends after the current step with the numbers so far; Showcase again resumes, no duplicates", function()
	local r, E = fakes()
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	-- run until a few towns exist, then stop
	for _ = 1, 100000 do
		r:tick(E.t)
		E.t = E.t + 100000
		if E.creates >= 5 then break end
	end
	r:command({ action = "stop" }, E.t, S)
	ok(run(r, E))
	ok(has(E, "result=stopped"))
	ok(has(E, "SHOWCASE SUMMARY"), "numbers so far")
	local made = E.creates
	ok(made >= 5 and made < 34, tostring(made))
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "SHOWCASE START n=10 resume=true"))
	eq(E.creates, 34, "the rest created, none twice")
	eq(#E.towns(), 34)
	-- a larger N resumes the growth of a finished showcase
	local function steps()
		local n = 0
		for _, tw in pairs(r.show.towns) do n = n + tw.steps end
		return n
	end
	local before = steps()
	r:command({ action = "showcase", sn = 2 }, E.t, S)
	ok(run(r, E))
	ok(steps() > before, steps() .. " vs " .. before)
	eq(r.show.towns.CONTROL_A.steps, 20, "a vanilla town (never stopped) reached the new N")
	eq(E.creates, 34)
end)

test("showcase: after a reset (or reload) towns named like the items are reused", function()
	local r, E = fakes()
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	r:command({ action = "showReset" }, E.t, S)
	eq(r.show, nil)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	eq(E.creates, 34, "nothing created again")
	ok(has(E, "existing=1"), "PLACE lines name the existing towns")
end)

test("showcase: focus lines for Next / Previous town", function()
	local r, E = fakes()
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	local st = r:command({ action = "showFocus", key = "JP_DENSE" }, E.t, S)
	ok(has(E, "SHOWCASE FOCUS key=JP_DENSE"))
	eq(st.show.focusKey, "JP_DENSE")
	local text = table.concat(st.show.focus, "\n")
	ok(text:find("JP dense (JP_DENSE", 1, true), text)
	ok(text:find("Buildings", 1, true) and text:find("Shape: drift=", 1, true), text)
	local t = st.show.towns[1]
	ok(t.x and t.y and t.label and t.key)
end)

test("showcase: a map whose centre is sea fails the layout cleanly", function()
	local r, E, X = fakes()
	function X.isWater() return true end
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "SHOWCASE LAYOUT ok=false why=mapCentreIsWater"))
	ok(has(E, "result=failed"))
	eq(r.show, nil)
	eq(E.creates, 0)
end)

test("showcase before 1940: no era row (only old templates), 32 towns", function()
	local r, E = fakes({ year = 1900 })
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "SHOWCASE SKIP item=ERA_*"))
	eq(E.creates, 32)
end)

test("showcase options: fill mod streets (DevelopAt beside new mod streets), freeze style towns", function()
	local r, E, X = fakes()
	r:command({ action = "showOpt", opt = "fill" }, E.t, S)
	r:command({ action = "showOpt", opt = "freeze" }, E.t, S)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "SHOWCASE START") and has(E, "SHOWCASE START"):find("fill=true freeze=true", 1, true))
	local fills = 0
	for _, d in ipairs(X.develops) do
		ok(d[3] == false, "no streets")
		if d[4] == false then fills = fills + 1 end
	end
	ok(fills > 0, "DevelopAt (no upgrade) sent beside mod streets")
	ok(has(E, "SHOWCASE FILL key="))
	eq(#X.freezes, 32, "every style town frozen (9 styles + 2 era + 8 shapes + 4 density + 4 probe twins + 5 metropolis), vanilla ones not")
	ok(has(E, "SHOWCASE FREEZE key="))
	ok(has(E, "vanilla="), "STEP lines split new edges into mod / vanilla")
end)

test("reset showcase: towns destroyed one by one, streets left -> next layout offset", function()
	local r, E, X = fakes()
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	r:command({ action = "showDestroy" }, E.t, S)
	ok(run(r, E))
	eq(#X.destroyed, 34)
	eq(#E.towns(), 0)
	ok(has(E, "SHOWCASE DESTROYED key=") == nil)
	ok(has(E, "SHOWCASE DESTROYED town="))
	local reset = has(E, "SHOWCASE RESET destroyed=34")
	ok(reset and reset:find("nextOffset=1250,1250", 1, true), tostring(reset))
	eq(r.show, nil)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "offset=1250,1250"), "the second layout moved")
	ok(E.creates > 34, "created again at the moved spots (some may fall into the sea on this small island)")
end)

local RB_DIR = here .. "../../mods/square_roundabouts/content"
local rbCache = {}
local function rbReq(path)
	if rbCache[path] ~= nil then return rbCache[path] end
	local rel = path:match("^square_roundabouts::(/.*)$")
	if rel == nil then error("not found " .. path) end
	local env = setmetatable({ ug_require = rbReq }, { __index = _ENV })
	local m = assert(loadfile(RB_DIR .. rel, "t", env))()
	rbCache[path] = m
	return m
end
local RBM = ug_require "/organic_towns_dev/otd_roundabout.lua"

test("roundabouts: the roundabout town gets one at its frontier (step RB_STEP), adoption logged after", function()
	local geom = assert(RBM.load(rbReq))
	local r, E = fakes({ RB = RBM, rbGeom = geom })
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "SHOWCASE LAYOUT towns=36 of=36"), tostring(has(E, "SHOWCASE LAYOUT")))
	-- (2026-10-14) the main mod's roundabout town: its jobs plan as the kind roundabout_town (ot_character): its form, and
	-- its rings (here without the main mod's ring geometry: RB event=off why=noRoundabouts)
	local rt = r.show.towns.RB_TOWN
	ok(rt ~= nil and rt.charKind == "roundabout_town", "the roundabout town")
	ok(rt.formWhy == "char:roundabout_town", tostring(rt.formWhy))
	local plan = has(E, "SHOWCASE RB PLAN")
	ok(plan, "planned")
	local built = has(E, "SHOWCASE RB BUILT")
	ok(built and built:find("ring=4 arms=4", 1, true), tostring(built) .. " / " .. tostring(plan))
	ok(has(E, "SHOWCASE RB SEND") and has(E, "SHOWCASE RB SEND"):find("newNodeConfigs=7/7", 1, true), tostring(has(E, "SHOWCASE RB SEND")))
	ok(has(E, "SHOWCASE RB SEND"):find("ring=oneway", 1, true), "the one-way ring by default")
	ok(count(E, "SHOWCASE RB ADOPT") >= 1)
	local tw = r.show.towns.RB_EU
	ok(tw.rb and tw.rb.edges and #tw.rb.edges == 8)
	eq(tw.rb.step, SC.RB_STEP)
	ok(has(E, "SHOWCASE TOWN key=RB_EU"):find("roundabout=built_step_3_ring_oneway", 1, true))
end)

test("Roundabout here: at the dead end nearest the camera; refused cleanly without square_roundabouts", function()
	local geom = assert(RBM.load(rbReq))
	local r, E, X = fakes({ RB = RBM, rbGeom = geom })
	X.createTown({ x = 0, y = 0, name = "Fresh" }, function() end)   -- a fresh town with dead ends at (200, 0) and (0, 200)
	r:command({ action = "roundabout", x = 260, y = 10 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "[SQOT_DEV] RB BUILT"), tostring(has(E, "[SQOT_DEV] RB ")))
	ok(r:status().rbProbe ~= nil)
	r:command({ action = "rbAdopt" }, E.t, S)
	ok(has(E, "[SQOT_DEV] RB ADOPT town="))
	local r2, E2 = fakes()
	r2:command({ action = "roundabout", x = 0, y = 0, town = 1 }, E2.t, S)
	ok(run(r2, E2))
	ok(has(E2, "RB town=1 ok=false why=noRoundaboutMod"), tostring(has(E2, "RB ")))
end)

test("showcase v3: shape row passes shape to the jobs, density levers, settle (speed up, restore), auto tour signal", function()
	local r, E, X = fakes()
	local asked = {}
	local restore = spyJobs(r, function(_t, o) asked[#asked + 1] = o end)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	restore()
	local shapes, medium = {}, 0
	for _, o in ipairs(asked) do
		if o.shape then shapes[o.shape] = true end
		if o.override and o.override.templates and o.override.templates.small == "medium" then medium = medium + 1 end
	end
	for _, id in ipairs(L.SHAPES) do ok(shapes[id], "a job with shape " .. id) end
	ok(medium >= 1, "density lever medium: templates overridden")
	ok(has(E, "SHOWCASE PLACE key=SHAPE_LINEAR") and has(E, "SHOWCASE PLACE key=SHAPE_LINEAR"):find("shape=linear", 1, true))
	ok(has(E, "SHOWCASE TOWN key=SHAPE_FAN") and has(E, "SHOWCASE TOWN key=SHAPE_FAN"):find("shapeAsked=fan", 1, true))
	-- weights once at creation; upgrade once (v4), at step UPGRADE_STEP, its effect at the next STEP line
	eq(#X.weights, 1)
	eq(#X.weights[1][2], 3, "three land uses")
	eq(#X.weights[1][2][1], 4, "four levels")
	ok(has(E, "SHOWCASE DENSITY key=DENS_WEIGHTS") and has(E, "SHOWCASE DENSITY key=DENS_WEIGHTS"):find("ok=true", 1, true))
	local ups = 0
	for _, d in ipairs(X.develops) do if d[4] == true then ups = ups + 1 end end
	eq(ups, 1, "DevelopAt upgrade at the centre once")
	eq(count(E, "SHOWCASE DENSITY key=DENS_UPGRADE"), 1)
	local up = has(E, "SHOWCASE DENSITY key=DENS_UPGRADE")
	ok(up:find("lever=upgrade once=true step=3 x=", 1, true) and up:find("ok=true", 1, true), up)
	local eff = has(E, "SHOWCASE DENSITY effect key=DENS_UPGRADE")
	ok(eff and eff:find("step=3 upgradeStep=3 when=same buildings=49->49 capacity=950->950 edges=", 1, true), tostring(eff))
	-- v5: once more a round later (v4: the wave came the round after the lever)
	local nxt = has(E, "SHOWCASE DENSITY effect key=DENS_UPGRADE town=")
	for _, l in ipairs(E.logs) do if l:find("DENSITY effect", 1, true) and l:find("when=next", 1, true) then nxt = l end end
	ok(nxt and nxt:find("step=4 upgradeStep=3 when=next buildings=49->", 1, true), tostring(nxt))
	eq(count(E, "DENSITY effect"), 2)
	ok(has(E, "SHOWCASE TOWN key=DENS_CONTROL") and has(E, "SHOWCASE TOWN key=DENS_CONTROL"):find("lever=control", 1, true))
	-- settle (v6 default: 3 forced passes back to back, each one STEP_ADD further, no speed change), sizes before /
	-- after, then the report
	local st = has(E, "SHOWCASE SETTLE start mode=passes target=3passes capMin=20")
	ok(st, tostring(has(E, "SETTLE")))
	eq(X.speeds, {}, "the passes don't touch the game speed")
	eq(count(E, "SHOWCASE SETTLE pass n="), 3)
	ok(has(E, "SHOWCASE SETTLE pass n=3 towns=34") and has(E, "SHOWCASE SETTLE pass n=3"):find("extra=3", 1, true),
		tostring(has(E, "SHOWCASE SETTLE pass n=3")))
	eq(count(E, "SHOWCASE SETTLE sample n="), 4, "the baseline and one after each pass")
	local maxF = 0
	for _, g in ipairs(E.grows) do maxF = math.max(maxF, g.f[1]) end
	ok(math.abs(maxF - (1 + 13 * SC.STEP_ADD)) < 1e-9, "the last pass grows to step 10 + 3: " .. maxF)
	eq(count(E, "SHOWCASE SETTLE town key="), 34)
	local fin = has(E, "SHOWCASE SETTLE end")
	ok(fin and fin:find("timedOut=false", 1, true) and fin:find("tour=true", 1, true) and fin:find("reason=passes", 1, true),
		tostring(fin))
	ok(has(E, "SHOWCASE SETTLE town key=NA_GRID") :find("adoption=", 1, true))
	local iSettle, iSum
	for i, l in ipairs(E.logs) do
		if l:find("SHOWCASE SETTLE end", 1, true) then iSettle = i end
		if l:find("SHOWCASE SUMMARY", 1, true) then iSum = i end
	end
	ok(iSettle < iSum, "report after the settle")
	eq(r:status().show.autoTour, 1)
	-- settle off: no SETTLE lines
	local r2, E2, X2 = fakes()
	r2:command({ action = "showOpt", opt = "settle", value = 1 }, E2.t, S)
	r2:command({ action = "showOpt", opt = "shapes" }, E2.t, S)
	r2:command({ action = "showOpt", opt = "density" }, E2.t, S)
	r2:command({ action = "showcase", sn = 1 }, E2.t, S)
	ok(run(r2, E2))
	eq(has(E2, "SETTLE start"), nil)
	eq(#X2.speeds, 0)
	eq(E2.creates, 13, "without the v3 rows (and Probe C, off since v5)")
	eq(r2:status().show.autoTour, 0)
end)

test("showcase v3: settle without a readable calendar waits real time; time that doesn't move times out", function()
	local r, E, X = fakes()
	X.calendarMonths = function() return nil end
	r:command({ action = "showOpt", opt = "shapes" }, E.t, S)
	r:command({ action = "showOpt", opt = "density" }, E.t, S)
	r:command({ action = "showOpt", opt = "settle", value = 2 }, E.t, S)   -- 1 year: 12 x MONTH_REAL_S < the 20 min cap
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	ok(has(E, "SHOWCASE SETTLE start mode=years target=12months capMin=20 forcePasses=true clock=real"))
	local fin = has(E, "SHOWCASE SETTLE end")
	ok(fin and fin:find("timedOut=false", 1, true) and fin:find("reason=target", 1, true), tostring(fin))
	-- a sample every SAMPLE_REAL_S: 12 months x 40 s / 20 s = 24, plus the baseline
	local smp = count(E, "SHOWCASE SETTLE sample n=")
	ok(smp >= 24 and smp <= 26, tostring(smp))
	local r2, E2, X2 = fakes()
	X2.calendarMonths = function() return 100 end   -- frozen calendar
	r2:command({ action = "showOpt", opt = "settle", value = 3 }, E2.t, S)   -- 2 years
	r2:command({ action = "showOpt", opt = "shapes" }, E2.t, S)
	r2:command({ action = "showOpt", opt = "density" }, E2.t, S)
	r2:command({ action = "showcase", sn = 1 }, E2.t, S)
	ok(run(r2, E2))
	ok(has(E2, "SHOWCASE SETTLE end") and has(E2, "SHOWCASE SETTLE end"):find("reason=cap", 1, true)
		and has(E2, "SHOWCASE SETTLE end"):find("timedOut=true", 1, true), tostring(has(E2, "SHOWCASE SETTLE end")))
	eq(X2.speeds, { SC.SETTLE_SPEED, 1 }, "speed restored after a timeout too")
end)

test("roundabouts: the one-way ring is the default; a refused one-way ring falls back to the two-way ring", function()
	local geom = assert(RBM.load(rbReq))
	local r, E, X = fakes({ RB = RBM, rbGeom = geom })
	X.createTown({ x = 0, y = 0, name = "Fresh" }, function() end)
	eq(r.showOpts.ringMode, "oneway")
	r:command({ action = "roundabout", x = 260, y = 10 }, E.t, S)
	ok(run(r, E))
	local send = has(E, "[SQOT_DEV] RB SEND")
	ok(send and send:find("ring=oneway", 1, true) and send:find("newNodeConfigs=7/7", 1, true)
		and send:find("fallback=false", 1, true), tostring(send))
	-- every one-way size refused: the two-way ring, logged
	local r2, E2, X2 = fakes({ RB = RBM, rbGeom = geom })
	X2.createTown({ x = 0, y = 0, name = "Fresh" }, function() end)
	local pre = E2.precheck
	function E2.precheck(p)
		for _, e in ipairs(p.spec.edges) do
			if e.override and e.override:find("one_way", 1, true) then
				return { ok = false, msgs = { "Construction_Not_Possible" }, collisions = 0, buildings = 0, us = 100 }
			end
		end
		return pre(p)
	end
	r2:command({ action = "roundabout", x = 260, y = 10 }, E2.t, S)
	ok(run(r2, E2))
	ok(has(E2, "[SQOT_DEV] RB FALLBACK") and has(E2, "[SQOT_DEV] RB FALLBACK"):find("to=town", 1, true),
		tostring(has(E2, "[SQOT_DEV] RB FALLBACK")))
	local send2 = has(E2, "[SQOT_DEV] RB SEND")
	ok(send2 and send2:find("ring=town", 1, true) and send2:find("fallback=true", 1, true), tostring(send2))
	-- the toggle switches to the two-way ring
	r:command({ action = "showOpt", opt = "ring" }, E.t, S)
	eq(r.showOpts.ringMode, "town")
end)

--- Showcase with only the 13 base towns, buildings that grow by `perMonth` per town and game month of the settle
--- (up to `upTo` per town; nil = forever), and the settle options. Returns r, E, X, info (settle start / end times,
--- growth commands during the settle).
local function settleRun(o)
	local r, E, X = fakes()
	local info = { grows0 = nil, grows1 = nil, t0 = nil }
	local setSpeed = X.setGameSpeed
	function X.setGameSpeed(v, cb)
		if v == SC.SETTLE_SPEED then info.t0, info.grows0 = E.t, #E.grows else info.grows1, info.t1 = #E.grows, E.t end
		return setSpeed(v, cb)
	end
	local tb = E.townBuildings
	function E.townBuildings(t, ...)
		local pts, builtBy = tb(t, ...)
		if info.t0 ~= nil then
			local months = (math.min(E.t, info.t1 or E.t) - info.t0) / 1e7
			local extra = math.floor(months * (o.perMonth or 0))
			if o.upTo then extra = math.min(extra, o.upTo) end
			local tw = E.W.towns[t]
			for i = 1, extra do pts[#pts + 1] = { tw.x + (i % 10) * 7, tw.y + 95 + math.floor(i / 10) * 7 } end
		end
		return pts, builtBy
	end
	r:command({ action = "showOpt", opt = "shapes" }, E.t, S)
	r:command({ action = "showOpt", opt = "density" }, E.t, S)
	r.showOpts.settleForce = false   -- (default ON since v5; these tests set it themselves)
	for k, v in pairs(o.opts or {}) do
		if k == "settleForce" then r.showOpts.settleForce = v
		elseif v == true then r:command({ action = "showOpt", opt = k }, E.t, S)
		else r:command({ action = "showOpt", opt = k, value = v }, E.t, S) end
	end
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	local fin = run(r, E, 400000)
	if not fin then dump(E) end
	ok(fin, "finished")
	return r, E, X, info
end

local function field(line, name)
	return line and line:match(" " .. name .. "=([^ ]+)") or nil
end

test("settle v4: years mode ends at the target months; a sample per game month with buildings total(+delta)", function()
	local r, E, X = settleRun({ perMonth = 1, opts = { settle = 2 } })   -- 1 year
	ok(has(E, "SHOWCASE SETTLE start mode=years target=12months capMin=20 forcePasses=false clock=calendar"))
	local fin = has(E, "SHOWCASE SETTLE end")
	eq(field(fin, "reason"), "target")
	eq(field(fin, "timedOut"), "false")
	ok(tonumber(field(fin, "passed")) >= 12 and tonumber(field(fin, "passed")) < 12.2, fin)
	eq(field(fin, "passes"), "0")
	local smp = count(E, "SHOWCASE SETTLE sample n=")
	eq(tonumber(field(fin, "samples")), smp)
	ok(smp >= 12 and smp <= 14, tostring(smp))
	ok(has(E, "SHOWCASE SETTLE sample n=1 ") and has(E, "SHOWCASE SETTLE sample n=1 "):find("buildings=637(+0)", 1, true),
		tostring(has(E, "SHOWCASE SETTLE sample n=1 ")))
	local s2 = has(E, "SHOWCASE SETTLE sample n=3 ")
	ok(s2 and s2:find("(+13)", 1, true) and s2:find("towns=13 grew=13", 1, true), tostring(s2))
	eq(X.speeds, { SC.SETTLE_SPEED, 1 })
	eq(count(E, "SHOWCASE SETTLE town key="), 13)
	ok(has(E, "SHOWCASE SETTLE town key=CONTROL_A"):find("buildings=49->60", 1, true),
		tostring(has(E, "SHOWCASE SETTLE town key=CONTROL_A")))
	ok(fin:find("buildings=637->780", 1, true), fin)
	ok(r.show.settled == 1)
end)

test("settle v4: plateau mode ends once three samples added < 1 % and < 2 per town, not before 6 months", function()
	local _, E = settleRun({ perMonth = 3, upTo = 30, opts = { settle = 5 } })   -- grows 10 months, then flat
	ok(has(E, "SHOWCASE SETTLE start mode=plateau target=plateau capMin=20"))
	local fin = has(E, "SHOWCASE SETTLE end")
	eq(field(fin, "reason"), "plateau")
	local passed = tonumber(field(fin, "passed"))
	ok(passed >= 12.9 and passed <= 14.1, fin)
	-- an early plateau needs 6 months: no growth at all still waits PLATEAU_MIN_MONTHS
	local _, E2 = settleRun({ perMonth = 0, opts = { settle = 5 } })
	local fin2 = has(E2, "SHOWCASE SETTLE end")
	eq(field(fin2, "reason"), "plateau")
	ok(tonumber(field(fin2, "passed")) >= SC.PLATEAU_MIN_MONTHS and tonumber(field(fin2, "passed")) < 7.1, fin2)
	-- the pure test
	eq((SC.plateau({ 1000, 1005, 1007, 1008 }, 29)), true)
	eq((SC.plateau({ 1000, 1010, 1012, 1013 }, 29)), false, "+13 is over 1 %")
	eq((SC.plateau({ 1000, 1100, 1110, 1112 }, 29)), false, "+112 over 3 samples")
	eq((SC.plateau({ 1000, 1000, 1001, 1001 }, 1)), true)
	eq((SC.plateau({ 100, 101, 102 }, 1)), false, "too few samples")
	eq((SC.plateau({ 10000, 10050, 10080, 10090 }, 29)), false, "< 1 % but 90 > 2 per town")
end)

test("settle v4: the real-time cap ends any mode (reason=cap, timedOut), speed restored", function()
	local _, E, X = settleRun({ perMonth = 5, opts = { settle = 5, settleCap = 1 } })   -- never flat; 5 min cap
	ok(has(E, "SHOWCASE SETTLE start mode=plateau target=plateau capMin=5"))
	local fin = has(E, "SHOWCASE SETTLE end")
	eq(field(fin, "reason"), "cap")
	eq(field(fin, "timedOut"), "true")
	local s = tonumber(field(fin, "s"))
	ok(s >= 300 and s < 301, fin)
	eq(X.speeds, { SC.SETTLE_SPEED, 1 })
	-- 5 years at one month per 10 s = 600 s: the 5 min cap ends it too
	local _, E2 = settleRun({ opts = { settle = 4, settleCap = 1 } })
	eq(field(has(E2, "SHOWCASE SETTLE end"), "reason"), "cap")
end)

test("settle v4: forced growth passes every 2 game months, sent as one batch per pass and counted", function()
	local _, E, _, info = settleRun({ opts = { settle = 2, settleForce = true } })   -- 1 year, forced passes
	ok(has(E, "SHOWCASE SETTLE start mode=years target=12months capMin=20 forcePasses=true"))
	local fin = has(E, "SHOWCASE SETTLE end")
	local passes = tonumber(field(fin, "passes"))
	eq(passes, 5, fin)   -- months 2, 4, 6, 8, 10 (the target at 12 ends it first)
	eq(count(E, "SHOWCASE SETTLE pass n="), passes)
	ok(has(E, "SHOWCASE SETTLE pass n=1 towns=13"), tostring(has(E, "SHOWCASE SETTLE pass")))
	eq(info.grows1 - info.grows0, passes * 13, "one growth command per town and pass")
	ok(has(E, "SHOWCASE SETTLE sample n=13") and has(E, "SHOWCASE SETTLE sample n=13"):find("passes=5", 1, true),
		tostring(has(E, "SHOWCASE SETTLE sample n=13")))
	-- off: none
	local _, E2, _, info2 = settleRun({ opts = { settle = 2 } })
	eq(count(E2, "SHOWCASE SETTLE pass n="), 0)
	eq(info2.grows1 - info2.grows0, 0)
end)

test("settle v4: options travel in the status; the mode table", function()
	local r, E = fakes()
	local st = r:status()
	eq(st.showOpts.settle, "passes", "v6: a few forced passes, no game time to wait for")
	eq({ SC.settleMode(S, "passes") }, { "passes", 3 })
	eq(st.showOpts.settleCap, 20)
	eq(st.showOpts.settleForce, true, "forced passes on by default (v5)")
	r:command({ action = "showOpt", opt = "settle", value = 5 }, E.t, S)
	r:command({ action = "showOpt", opt = "settleCap", value = 4 }, E.t, S)
	st = r:command({ action = "showOpt", opt = "settleForce" }, E.t, S)
	eq(st.showOpts.settle, "plateau")
	eq(st.showOpts.settleCap, 40)
	eq(st.showOpts.settleForce, false)
	ok(has(E, "settle=plateau settleCapMin=40 settleForce=false"), tostring(has(E, "SHOWCASE OPTS")))
	eq({ SC.settleMode(S, "off") }, { "off" })
	eq({ SC.settleMode(S, "5y") }, { "years", 60 })
	eq({ SC.settleMode(S, "plateau") }, { "plateau" })
end)

test("upgrade lever: once per town even when a larger N resumes the showcase", function()
	local r, E, X = fakes()
	r:command({ action = "showOpt", opt = "settle", value = 1 }, E.t, S)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	r:command({ action = "showcase", sn = 2 }, E.t, S)
	ok(run(r, E))
	eq(r.show.towns.CONTROL_A.steps, 20, "the resume ran the larger N")
	local ups = 0
	for _, d in ipairs(X.develops) do if d[4] == true then ups = ups + 1 end end
	eq(ups, 1)
	eq(r.show.towns.DENS_UPGRADE.upgrade.step, SC.UPGRADE_STEP)
end)

test("camera: distance picker per view; shape-row towns top-down one step wider; status carries key/kind/shape/row", function()
	local plain = { key = "NA_GRID", kind = "style" }
	local shape = { key = "SHAPE_LINEAR", kind = "style", shape = "linear", row = 4 }
	eq({ S.view(plain, {}) }, { 1800, false, "picked" })
	eq({ S.view(shape, {}) }, { 2500, true, "shapeRow" })
	eq({ S.view(shape, { distIdx = 1 }) }, { 1800, true, "shapeRow" })
	eq({ S.view(shape, { distIdx = 3 }) }, { 2500, true, "shapeRow" })
	eq({ S.view(shape, { shapeTop = false }) }, { 1800, false, "picked" })
	eq({ S.view(plain, { distIdx = 1, topDown = true }) }, { 1000, true, "picked" })
	eq({ S.view(shape, { forceTop = false }) }, { 2500, false, "shapeRow" }, "the tour's oblique view keeps the distance")
	eq({ S.view({ key = "SHAPE_FAN" }, {}) }, { 2500, true, "shapeRow" }, "the key alone is enough")
	eq(S.CAM_DIST[S.CAM_DIST_DEFAULT], 1800)
	local r, E = fakes()
	r:command({ action = "showOpt", opt = "settle", value = 1 }, E.t, S)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	local towns = r:status().show.towns
	local n = 0
	for _, t in ipairs(towns) do
		ok(t.key and t.kind, "key and kind")
		if t.key:find("^SHAPE_") then
			n = n + 1
			eq(t.row, t.probe and 6 or 4)
			ok(t.shape ~= nil)
			eq((S.view(t, {})), 2500)
		elseif t.key == "CONTROL_A" then
			eq(t.kind, "vanilla")
			eq((S.view(t, {})), 1800)
		end
	end
	eq(n, 8 + 4, "the shape row and its probe twins")
end)

test("showcase v6 probes: plain / locked+fill / metropolis / DevelopAt-flag twins, LOCK lines with their shape twins", function()
	local r, E, X = fakes()
	local asked = {}
	local restore = spyJobs(r, function(t, o) asked[#asked + 1] = { o = o, t = t } end)
	-- a side street the "town" attaches to a mod node after each growth pass (vanilla growth off our streets),
	-- only in the plain linear town
	local grow = E.growTown
	local attachedOnce = {}
	function E.growTown(t, f, cb)
		local tw = r.show and r.show.towns.SHAPE_LINEAR
		if tw and tw.town == t and #tw.modEdges > 0 and not attachedOnce[#tw.modEdges] then
			attachedOnce[#tw.modEdges] = true
			local e = X.edge(tw.modEdges[#tw.modEdges])
			local n = E.W.nodes[e.n1]
			E.W.nextNode = E.W.nextNode + 1
			E.W.nodes[E.W.nextNode] = { id = E.W.nextNode, x = n.x + 30, y = n.y + 30, z = 10, cfg = true }
			E.W.nextEdge = E.W.nextEdge + 1
			E.W.edges[#E.W.edges + 1] = { id = E.W.nextEdge, n0 = e.n1, n1 = E.W.nextNode, p0 = { n.x, n.y, 10 },
				p1 = { n.x + 30, n.y + 30, 10 }, t0 = { 30, 30, 0 }, t1 = { 30, 30, 0 }, template = SMALL, lanes = 4, objects = 0,
				owned = false, inConstruction = false }
		end
		return grow(t, f, cb)
	end
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(run(r, E))
	restore()
	-- the jobs' lock / fill options per probe town; the shape row runs the defaults (nil)
	local byTown = {}
	for key, tw in pairs(r.show.towns) do if tw.town then byTown[tw.town] = key end end
	local seen = {}
	for _, a in ipairs(asked) do
		local key = byTown[a.t]
		seen[key] = a.o
	end
	eq(seen.SHAPE_LINEAR.lock, nil); eq(seen.SHAPE_LINEAR.fill, nil)
	eq(seen.SHAPE_LINEAR_PLAIN.lock, "off"); eq(seen.SHAPE_LINEAR_PLAIN.fill, "off")
	eq(seen.SHAPE_FINGERS_LOCKFILL.lock, "all"); eq(seen.SHAPE_FINGERS_LOCKFILL.fill, "dose")
	-- v7 metropolis row: a forced variant, the main mod's defaults otherwise
	eq(seen.METRO_RADIAL.metro, "radial"); eq(seen.METRO_RADIAL.fill, nil)
	eq(seen.METRO_POLYCENTRIC.metro, "polycentric"); eq(seen.METRO_POLYCENTRIC.metroCentres, true)
	-- no freeze twins any more (the global toggle is off), no dev-window fill
	eq(#X.freezes, 0)
	eq(count(E, "SHOWCASE FILL key="), 0)
	-- the metropolis towns' builds are filled by the driver: FILL kind=metro (the style's metro), METRO lines
	local mt = r.show.towns.METRO_GRID.town
	local fl = has(E, "[SQOT_DEV] FILL town=" .. mt .. " ")
	ok(fl and fl:find("kind=metro why=big", 1, true), tostring(fl))
	ok(has(E, "[SQOT_DEV] METRO town=" .. mt .. " ") and has(E, "[SQOT_DEV] METRO town=" .. mt .. " "):find("variant=grid", 1, true))
	local tl = has(E, "SHOWCASE TOWN key=METRO_POLYCENTRIC")
	ok(tl and tl:find("metro=polycentric_1centres", 1, true) and tl:find(" green=", 1, true), tostring(tl))
	ok(#E.develops >= 1, "the driver sent DevelopAt")
	local fe = has(E, "[SQOT_DEV] FILL effect town=" .. mt .. " ")
	ok(fe and fe:find("kind=metro", 1, true) and fe:find("near=", 1, true), tostring(fe))
	-- the plain twins never fill
	eq(has(E, "[SQOT_DEV] FILL town=" .. r.show.towns.SHAPE_LINEAR_PLAIN.town .. " "), nil)
	-- LOCK lines for the probe twins and the shape-row towns they are compared with, per step and in the report
	local lk = has(E, "SHOWCASE LOCK key=SHAPE_LINEAR_LOCKFILL")
	ok(lk and lk:find("role=lockfill twinOf=SHAPE_LINEAR when=step lockMode=all fill=dose", 1, true), tostring(lk))
	local plain = has(E, "SHOWCASE LOCK key=SHAPE_LINEAR ")
	ok(plain and plain:find("role=twin twinOf=- when=step lockMode=default fill=default", 1, true), tostring(plain))
	ok(has(E, "SHOWCASE LOCK key=SHAPE_FINGERS_LOCKFILL"))
	ok(has(E, "SHOWCASE LOCK key=SHAPE_FINGERS "))
	eq(has(E, "SHOWCASE LOCK key=SHAPE_CROSS"), nil, "other shape towns have no probe lines")
	eq(has(E, "SHOWCASE FREEZE effect"), nil)
	local last
	for _, l in ipairs(E.logs) do if l:find("SHOWCASE LOCK key=SHAPE_LINEAR ", 1, true) and l:find("when=report", 1, true) then last = l end end
	ok(last, "report line")
	ok(tonumber(last:match(" attached=(%d+)")) >= 1, "the side street off a mod node counts: " .. last)
	-- the locked twin: every edge sent locked and read back so
	local lastLock
	for _, l in ipairs(E.logs) do if l:find("SHOWCASE LOCK key=SHAPE_LINEAR_LOCKFILL", 1, true) and l:find("when=report", 1, true) then lastLock = l end end
	ok(lastLock and tonumber(lastLock:match(" alive=(%d+)")) >= 1, tostring(lastLock))
	eq(lastLock:match(" locked=(%d+)"), lastLock:match(" alive=(%d+)"), "all locked")
	eq(lastLock:match(" attached=(%d+)"), "0", "no side streets in the lock twin")
	-- TOWN lines: metrics with arms / side / waist, houses (building metrics when ot_metrics has points), probe
	local town = has(E, "SHOWCASE TOWN key=SHAPE_LINEAR_LOCKFILL")
	ok(town and town:find("probe=lockfill", 1, true) and town:find("_arms=", 1, true) and town:find(" houses=", 1, true), tostring(town))
	if MT.points then ok(not town:find(" houses=- ", 1, true), "houses metrics: " .. town) end
end)

test("tour: waits while the showcase settles (S.tourMayStart)", function()
	eq(S.tourMayStart(nil), true)
	eq(S.tourMayStart({ phase = "grow" }), true)
	eq(S.tourMayStart({ phase = "settle" }), false)
	eq(S.tourMayStart({ phase = "done" }), true)
end)

---------------------------------------------------------------------------
-- concurrent builds (Showcase v7+: r:buildBatch, R.BUILD_INFLIGHT town jobs at once)

--- Deferred engine callbacks: builds and DevelopAt queue up and are delivered every other tick, newest first (out
--- of order), the build applied to the world only then. o.failBuild = { [town name] = true }: that town's builds
--- fail at build time. Counts builds in flight (E.maxInflight) and out-of-order deliveries (E.reordered).
local function deferred(E, o)
	o = o or {}
	local q = {}
	E.inflight, E.maxInflight, E.reordered, E.seq, E.lastDelivered = 0, 0, 0, 0, 0
	local send, dev = E.sendBuild, E.developAt
	function E.sendBuild(p, ctx, cb)
		E.inflight = E.inflight + 1
		E.maxInflight = math.max(E.maxInflight, E.inflight)
		E.seq = E.seq + 1
		local seq = E.seq
		q[#q + 1] = function()
			E.inflight = E.inflight - 1
			if seq < E.lastDelivered then E.reordered = E.reordered + 1 end
			E.lastDelivered = seq
			local town = E.closestTown(p.spec.edges[1].p0[1], p.spec.edges[1].p0[2])
			if o.failBuild and o.failBuild[E.name(town)] then return cb(false, { msgs = { "Collision" } }) end
			return send(p, ctx, cb)
		end
	end
	function E.developAt(x, y, streets, upgrade, cb)
		q[#q + 1] = function() return dev(x, y, streets, upgrade, cb) end
	end
	if o.slowClock then
		-- every clock read 3 ms later: the pool's per-tick CPU budget (R.TICK_BUDGET_US) runs out after a few stages
		-- (the main driver's hang guard reads the clock every PLAN_HOOK_COUNT instructions: with this clock a plan would
		-- pass PLAN_HANG_US in fake time; the guard is off for this fake, test_driver.lua tests it)
		D.PLAN_GUARD = false
		local calls = 0
		function E.nowUs() calls = calls + 1; return E.t + calls * 3000 end
	end
	function E.pump(i)
		if i % 2 ~= 0 then return end
		local list = {}
		for k = #q, 1, -1 do list[#list + 1] = q[k]; q[k] = nil end
		for _, f in ipairs(list) do f() end
	end
end

local function runPumped(r, E, n)
	for i = 1, n or 200000 do
		if E.pump then E.pump(i) end
		r:tick(E.t)
		E.t = E.t + 100000
		if r.task == nil and #r.tasks == 0 then return true end
	end
	return false
end

--- Per style town: { built, mod edges, refused, empty } and every mod edge attributed to the town it lies in.
local function perTown(r, E)
	local out = {}
	for key, tw in pairs(r.show.towns) do
		if tw.kind == "style" and tw.town then
			out[key] = string.format("built=%d mod=%d refused=%d empty=%d", tw.built, #tw.modEdges, tw.fails, tw.empties)
			for _, id in ipairs(tw.modEdges) do
				local g = r.X.edgeGeom(id)
				ok(g, "mod edge exists: " .. id)
				eq(E.closestTown(g.p0[1], g.p0[2]), tw.town, key .. ": mod edge " .. id .. " lies in its own town")
			end
			-- the town's BUILT lines match its count and each found its own edges
			local n = 0
			for _, l in ipairs(E.logs) do
				if l:find("[SQOT_DEV] BUILT town=" .. tw.town .. " ", 1, true) then
					n = n + 1
					eq(l:match(" found=(%d+)"), l:match(" edges=(%d+)"), "found its own edges: " .. l)
				end
			end
			eq(n, tw.built + (tw.settleBuilds or 0), key .. " BUILT lines (rounds + settle checks)")
		end
	end
	return out
end

test("concurrent builds: out-of-order callbacks, every town's result is its own and matches the one-by-one run", function()
	-- one by one (the pool limited to one job; callbacks at once)
	local r1, E1 = fakes()
	r1:command({ action = "showcase", sn = 1 }, E1.t, S)
	local R = getmetatable(r1).__index
	local bb = R.buildBatch
	R.buildBatch = function(self, t, items, onResult) return bb(self, t, items, onResult, 1) end
	ok(runPumped(r1, E1))
	R.buildBatch = bb
	local serial = perTown(r1, E1)
	ok(has(E1, "SHOWCASE ROUND round=1 ") and has(E1, "SHOWCASE ROUND round=1 "):find("inflight=1 peak=1", 1, true),
		tostring(has(E1, "SHOWCASE ROUND round=1 ")))
	-- concurrent, deferred callbacks delivered newest first
	local r2, E2 = fakes()
	deferred(E2)
	r2:command({ action = "showcase", sn = 1 }, E2.t, S)
	local fin = runPumped(r2, E2)
	if not fin then dump(E2) end
	ok(fin, "finished")
	ok(E2.maxInflight > 1, "builds in flight at once: " .. E2.maxInflight)
	ok(E2.reordered > 0, "callbacks out of order: " .. E2.reordered)
	local conc = perTown(r2, E2)
	eq(conc, serial, "per-town results equal the one-by-one run")
	eq(count(E2, "SHOWCASE ROUND round="), 10)
	local rl = has(E2, "SHOWCASE ROUND round=2 ")
	ok(rl and rl:find(" build=", 1, true) and rl:find(" grow=", 1, true) and rl:find(" other=", 1, true), tostring(rl))
	local peak = tonumber(field(rl, "peak"))
	eq(tonumber(field(rl, "inflight")), r2.BUILD_INFLIGHT or 12)
	ok(peak > 1 and peak <= 12, rl)
	eq(tonumber(field(rl, "builds")), 32, "every style town's job in the batch")
	-- the pool drivers share the dev driver's per-town state: history (undo) and counts
	local tw = r2.show.towns.NA_GRID
	eq(#r2:records(tw.town), math.min(tw.built, 20))
	eq(r2.driver.counts.builds, count(E2, "[SQOT_DEV] BUILT"))
end)

test("concurrent builds: a pre-check refusal and a build-time failure mid-batch stay with their towns", function()
	local r, E = fakes({ refuse = { ["EU organic"] = true } })
	deferred(E, { failBuild = { ["NA suburb"] = true }, slowClock = true })
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	local fin = runPumped(r, E)
	D.PLAN_GUARD = true
	if not fin then dump(E) end
	ok(fin)
	local eu, na = r.show.towns.EU_ORGANIC, r.show.towns.NA_SUBURB
	eq(eu.built, 0); ok(eu.fails + eu.empties >= 1)
	ok(has(E, "SHOWCASE STOP key=EU_ORGANIC"), "refused town stopped")
	eq(na.built, 0); ok(na.fails >= 1)
	local failed = has(E, "[SQOT_DEV] FAILED town=" .. na.town)
	ok(failed and failed:find("msgs=Collision", 1, true), tostring(failed))
	-- (its failed pieces are excluded: refused x3, or the plan runs dry first)
	local stop = has(E, "SHOWCASE STOP key=NA_SUBURB")
	ok(stop and (stop:find("refused_x3", 1, true) or stop:find("empty_x4", 1, true)), tostring(stop))
	-- nobody else is affected (the fake's oldcore metropolis plans nothing in any run: empty, not refused)
	local others = 0
	for key, tw in pairs(r.show.towns) do
		if tw.kind == "style" and tw.town and key ~= "EU_ORGANIC" and key ~= "NA_SUBURB" then
			eq(tw.fails, 0, key .. " fails")
			if tw.built >= 1 then others = others + 1 end
		end
	end
	ok(others >= 28, "other towns built: " .. others)
	perTown(r, E)
	local lp = r.lastPool
	ok(lp and lp.cpuMax >= 1 and lp.cpuMax < 12, "CPU stages per tick capped by the budget: " .. tostring(lp and lp.cpuMax))
end)

test("concurrent builds: the roundabout step after the batch, Stop mid-batch lets the running jobs finish", function()
	local geom = assert(RBM.load(rbReq))
	local r, E = fakes({ RB = RBM, rbGeom = geom })
	deferred(E)
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	-- stop while the first round's batch runs
	for i = 1, 200000 do
		E.pump(i)
		r:tick(E.t)
		E.t = E.t + 100000
		if r.task and r.task.pool and r.task.pool.done >= 3 then break end
	end
	ok(r.task and r.task.pool, "stopped mid-batch")
	local started = r.task.pool.next - 1
	r:command({ action = "stop" }, E.t, S)
	ok(runPumped(r, E))
	ok(has(E, "result=stopped"))
	eq(E.inflight, 0, "no build left in flight")
	local rec = 0
	for _, tw in pairs(r.show.towns) do if tw.kind == "style" and tw.steps == 1 and (tw.built + tw.fails + tw.empties) == 1 then rec = rec + 1 end end
	eq(rec, started, "every started job recorded, no other")
	for _, d in ipairs(r.pool) do eq(d.job, nil); eq(d.inflight, false) end
	-- resume: the round's other towns build, nothing twice
	r:command({ action = "showcase", sn = 1 }, E.t, S)
	ok(runPumped(r, E))
	ok(has(E, "SHOWCASE START n=10 resume=true"))
	for key, tw in pairs(r.show.towns) do
		if tw.kind == "style" and tw.town then eq(tw.built + tw.fails + tw.empties, tw.steps, key .. " one outcome per step") end
	end
	local built = has(E, "SHOWCASE RB BUILT")
	ok(built and built:find("ring=4 arms=4", 1, true), tostring(built))
	local tw = r.show.towns.RB_EU
	ok(tw.rb and tw.rb.edges and #tw.rb.edges == 8)
	eq(tw.rb.step, SC.RB_STEP)
	local lastTown
	for _, l in ipairs(E.logs) do if l:find("SHOWCASE TOWN key=RB_EU", 1, true) then lastTown = l end end
	ok(lastTown:find("roundabout=built_step_3_ring_oneway", 1, true), lastTown)
	perTown(r, E)
end)

test("batches: a callback of an earlier (timed-out) batch is LATE and doesn't count for the next one", function()
	local r, E = fakes()
	local held = {}
	local t = {}
	r.nowUs = 0
	r:sendBatch(t, { { town = 1 }, { town = 2 } }, function(_it, cb) held[#held + 1] = cb end, 0, "GROW")
	eq(t.cmdTimeoutS, R.BATCH_TIMEOUT_S)
	held[1](true)
	eq(t.batchLeft, 1)
	-- (the task timed out on town 2) the next batch
	r:sendBatch(t, { { town = 1 }, { town = 2 } }, function(_it, cb) held[#held + 1] = cb end, 0, "GROW")
	held[2](true)   -- the first batch's town 2, late
	eq(t.batchLeft, 2, "the late callback is not counted")
	eq(t.cmdDone, nil)
	ok(has(E, "[SQOT_DEV] LATE what=GROW town=2 ok=true"), tostring(has(E, "LATE")))
	held[3](true); held[4](true)
	eq(t.cmdDone, true)
end)

test("v8 rows: form row (JP dense, forced forms), metropolis band, one control and one probe twin; TOWN lines carry form / orient / own / dens", function()
	v8rows()
	local okRun, err = pcall(function()
		local r, E = fakes()
		local seen = {}
		local D0 = r.driver
		local sj = getmetatable(D0).__index.startJob
		getmetatable(D0).__index.startJob = function(self, t, now, o)
			if o and o.form then seen[o.form] = (seen[o.form] or 0) + 1 end
			return sj(self, t, now, o)
		end
		r:command({ action = "showcase", sn = 1 }, E.t, S)
		local fin = runPumped(r, E)
		getmetatable(D0).__index.startJob = sj
		if not fin then dump(E) end
		ok(fin, "finished")
		-- 9 styles + Control A + 2 era + 8 shapes + 1 density + 3 probes (§65: + 2 old-lock twins) + 4 forms + 5 metropolis
		-- (no roundabout mod)
		local lay = has(E, "SHOWCASE LAYOUT towns=33 of=33 dropped=0")
		ok(lay, tostring(has(E, "SHOWCASE LAYOUT")))
		eq(has(E, "SHOWCASE PLACE key=CONTROL_B"), nil)
		eq(has(E, "SHOWCASE PLACE key=DENS_WEIGHTS"), nil)
		eq(has(E, "SHOWCASE PLACE key=SHAPE_FINGERS_LOCKFILL"), nil)
		for _, f in ipairs(L.FORMS) do
			local pl = has(E, "SHOWCASE PLACE key=FORM_" .. f:upper())
			ok(pl and pl:find("style=" .. L.FORM_STYLE, 1, true) and pl:find("form=" .. f, 1, true), tostring(pl))
			ok((seen[f] or 0) >= 1, f .. " passed to the jobs")
			local town = has(E, "SHOWCASE TOWN key=FORM_" .. f:upper())
			ok(town and town:find("form=" .. f, 1, true), tostring(town))
		end
		-- metropolis towns in the band below the grid, >= 3.5 km apart
		local ms = {}
		for key, tw in pairs(r.show.towns) do if tw.metro then ms[#ms + 1] = tw end end
		eq(#ms, 5)
		for i, a in ipairs(ms) do
			for j = i + 1, #ms do ok(dist(a.x, a.y, ms[j].x, ms[j].y) >= 3500, a.key .. "-" .. ms[j].key) end
		end
		local t = has(E, "SHOWCASE TOWN key=NA_GRID ")
		ok(t and t:find(" orient=", 1, true) and t:find(" own=", 1, true) and t:find(" dens=", 1, true), tostring(t))
		-- form towns seen top-down like the shape row
		local st = r:status()
		local formTown
		for _, x in ipairs(st.show.towns) do if x.key == "FORM_LINEAR" then formTown = x end end
		ok(formTown and S.isShapeTown(formTown), "form row top-down")
		-- Tour all towns (Real map test): every town measured, the biggest first, ALLTOWN lines, status for the HUD
		local st2 = r:command({ action = "allTowns" }, E.t, S)
		ok(st2.allTowns and #st2.allTowns >= 20 and #st2.allTowns <= R.ALL_TOWNS_MAX, tostring(st2.allTowns and #st2.allTowns))
		local first = has(E, "[SQOT_DEV] ALLTOWN n=1 ")
		ok(first and first:find(" orient=", 1, true) and first:find(" dens=", 1, true) and first:find(" form=", 1, true)
			and first:find(" style=", 1, true), tostring(first))
		local prev = math.huge
		for _, l in ipairs(E.logs) do
			local b = l:find("ALLTOWN n=", 1, true) and tonumber(l:match(" buildings=(%d+)"))
			if b then ok(b <= prev, "biggest first"); prev = b end
		end
		ok(has(E, "ALLTOWNS towns="))
		eq(st2.allTowns[1].kind, "all")
		ok(not S.isShapeTown(st2.allTowns[1]), "the map's towns: the picked view")
	end)
	v7rows()
	assert(okRun, err)
end)

test("§65 / §69 lock A/B: the lock-all twin (mod) and old-lock twins (shape) beside the main mod's default (steer); LOCK lines log game edges and cap / target", function()
	v8rows()
	local okRun, err = pcall(function()
		local r, E = fakes()
		local asked = {}
		local restore = spyJobs(r, function(t, o) asked[#asked + 1] = { o = o, t = t } end)
		r:command({ action = "showcase", sn = 2 }, E.t, S)
		local fin = runPumped(r, E)
		restore()
		ok(fin, "finished")
		local byTown = {}
		for key, tw in pairs(r.show.towns) do if tw.town then byTown[tw.town] = key end end
		local seen = {}
		for _, a in ipairs(asked) do seen[byTown[a.t]] = a.o end
		eq(seen.EU_ORGANIC_LOCKALL.lock, "mod"); eq(seen.SHAPE_LINEAR_OLDLOCK.lock, "shape")
		eq(seen.EU_ORGANIC.lock, nil, "the row town runs the main mod's default")
		local function lastLock(key, when)
			local out
			for _, l in ipairs(E.logs) do
				if l:find("SHOWCASE LOCK key=" .. key .. " ", 1, true) and l:find("when=" .. when, 1, true) then out = l end
			end
			return out
		end
		for _, key in ipairs({ "EU_ORGANIC_LOCKALL", "EU_ORGANIC", "SHAPE_LINEAR_OLDLOCK", "SHAPE_LINEAR", "SHAPE_LINEAR_PLAIN" }) do
			local l = lastLock(key, "step")
			ok(l and l:find(" gameEdges=%d+") and l:find(" cap=%d+/%d+") and l:find(" capRatio=%d") and l:find(" edges=%d+")
				and l:find(" gameShare=", 1, true), key .. ": " .. tostring(l))
			ok(lastLock(key, "report"), key .. " report line")
		end
		ok(lastLock("EU_ORGANIC_LOCKALL", "step"):find("role=lockall twinOf=EU_ORGANIC when=step lockMode=mod", 1, true))
		-- (the lock the driver used, once a town built: the fake EU organic twin may build nothing)
		local function used(key, want)
			local l = lastLock(key, "step")
			if l:find(" modEdges=0 ", 1, true) then return 0 end
			ok(l:find("lockUsed=" .. want, 1, true), key .. ": " .. l)
			return 1
		end
		local built = used("EU_ORGANIC_LOCKALL", "mod") + used("SHAPE_LINEAR_OLDLOCK", "shape")
		ok(built >= 1, "a twin built")
		ok(used("EU_ORGANIC", "steer") + used("SHAPE_LINEAR", "steer") >= 1, "a default town built")
		used("SHAPE_LINEAR_PLAIN", "off")
		ok(lastLock("EU_ORGANIC", "step"):find("role=twin", 1, true))
		-- the lock-all twin's mod streets are all locked (read back); the steer towns' at most all
		local a = lastLock("EU_ORGANIC_LOCKALL", "report")
		if not a:find(" alive=0 ", 1, true) then
			eq(a:match(" locked=(%d+)"), a:match(" alive=(%d+)"), "lock all: every live mod edge locked")
		end
		for _, key in ipairs({ "EU_ORGANIC", "SHAPE_LINEAR" }) do
			local b = lastLock(key, "report")
			ok(tonumber(b:match(" locked=(%d+)")) <= tonumber(b:match(" alive=(%d+)")), key .. ": " .. b)
		end
	end)
	v7rows()
	assert(okRun, err)
end)
