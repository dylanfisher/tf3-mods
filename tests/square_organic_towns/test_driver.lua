-- ot_driver against a fake engine: gate, saved init, assess -> plan -> pre-check -> send -> result,
-- refusal retries, failures, the testing grow param. The fake town is an engine-made 3 x 3 block grid
-- (100 m) with four dead-end stubs; one stub is player owned and one has no node config.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN = 100
local US_NAMES = "square_names_us_texas::/names/usa/usa.names"

--- The fake world: nodes 1..13, edges 101..116.
local function world()
	local nodes, edges = {}, {}
	local id = 0
	local at = {}
	local function node(x, y)
		id = id + 1
		nodes[id] = { id = id, x = x, y = y, z = 10, cfg = true }
		at[x .. ":" .. y] = id
		return id
	end
	for _, x in ipairs({ -100, 0, 100 }) do
		for _, y in ipairs({ -100, 0, 100 }) do node(x, y) end
	end
	local eid = 100
	local function edge(a, b, extra)
		eid = eid + 1
		local na, nb = nodes[a], nodes[b]
		local e = { id = eid, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
			t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
			objects = 0, owned = false, inConstruction = false, parcels = 10, built = 10 }
		for k, v in pairs(extra or {}) do e[k] = v end
		edges[#edges + 1] = e
		return e
	end
	for _, x in ipairs({ -100, 0, 100 }) do
		edge(at[x .. ":-100"], at[x .. ":0"])
		edge(at[x .. ":0"], at[x .. ":100"])
	end
	for _, y in ipairs({ -100, 0, 100 }) do
		edge(at["-100:" .. y], at["0:" .. y])
		edge(at["0:" .. y], at["100:" .. y])
	end
	local e1 = node(200, 0); edge(at["100:0"], e1)
	local e2 = node(-200, 0); edge(at["-100:0"], e2, { owned = true })
	local e3 = node(0, 200); edge(at["0:100"], e3)
	local e4 = node(0, -200); edge(at["0:-100"], e4)
	nodes[e4].cfg = false
	return { nodes = nodes, edges = edges, deadEnds = { east = e1, west = e2, north = e3, south = e4 } }
end

local function fakeEngine(o)
	o = o or {}
	local W = world()
	local E = { t = 0, logs = {}, events = {}, prechecks = {}, grows = {}, W = W, bal = 5000000 }
	E.precheckOk = o.precheckOk or function() return true end
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return o.cfg or { nameList = US_NAMES, climate = "::/climates/temperate" } end
		return nil
	end
	-- default: the grid forced (these tests were written for the NA grid; Automatic picks per site, see below)
	function E.modParams() return o.params or { act_on = 3, debug_log = 2, style = 2 }, {} end
	function E.gameTime() return o.gameTime or 10 * SV.FRESH_GAME_TIME end
	function E.year() return o.year or 1970 end
	function E.balance() return E.bal end
	-- (GAME_SPEED.speedup: running unless a test pauses it)
	function E.gameSpeed() return E.speed or 1 end
	function E.towns() return { TOWN } end
	function E.name(t) return "Testville" .. t end
	function E.boxCentre(_t) return 0, 0 end
	function E.townCaps(_t) return { target = 1000, actual = 900, sizeFactors = { 1, 1, 1 } } end
	function E.town2buildings() return {} end
	function E.townBuildings(_t, _m)
		local pts, builtBy = {}, {}
		for x = -90, 90, 30 do
			for y = -90, 90, 30 do pts[#pts + 1] = { x, y } end
		end
		for _, e in ipairs(W.edges) do builtBy[e.id] = e.built end
		return pts, builtBy
	end
	function E.parcelMap()
		local m = {}
		for _, e in ipairs(W.edges) do if e.parcels then m[e.id] = { n = e.parcels } end end
		return m
	end
	function E.parcelCount(pd) return pd.n end
	function E.closestTown(_x, _y) return TOWN end
	function E.streets(x, y, r)
		if o.streetsError then error("octree exploded") end
		local out = {}
		for _, e in ipairs(W.edges) do
			if F_dist(e.p0, x, y) <= r or F_dist(e.p1, x, y) <= r then out[#out + 1] = e end
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
		local okP = E.precheckOk(p.spec)
		return { ok = okP, msgs = okP and {} or { "Collision" }, collisions = okP and 0 or 3, buildings = 0, cost = 1234,
			us = 1500 }
	end
	function E.sendBuild(p, _ctx, cb)
		E.pending = { spec = p.spec, cb = cb }
	end
	function E.sendEvent(id, name, param) E.events[#E.events + 1] = { id = id, name = name, param = param } end
	function E.growTown(t, f, cb) E.grows[#E.grows + 1] = { town = t, f = f, cb = cb } end
	return E
end

function F_dist(p, x, y) return math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) end

--- Ticks the driver every 0.1 s of fake real time until pred() or n ticks.
local function run(d, E, n, saved, pred)
	for _ = 1, n do
		d:tick(E.t, saved)
		E.t = E.t + 100000
		if pred and pred() then return true end
	end
	return false
end

local function logsWith(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do
		if l:find("[SQOT] " .. what, 1, true) then out[#out + 1] = l end
	end
	return out
end

test("gate: every map runs (Automatic: the style from each town's site); Act on Off and the map editor stop", function()
	local E = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" }, params = { act_on = 3 } })
	local d = D.new(E)
	run(d, E, 10)
	eq(d.phase, "run")
	local init = logsWith(E, "INIT")
	eq(#init, 1)
	ok(init[1]:find("on=true", 1, true), init[1])
	local E2 = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names" }, params = { act_on = 3, style = 2 } })
	local d2 = D.new(E2)
	run(d2, E2, 10)
	eq(d2.phase, "run")
	local E3 = fakeEngine({ params = { act_on = 1 } })
	local d3 = D.new(E3)
	run(d3, E3, 10)
	eq(d3.phase, "off")
	ok(logsWith(E3, "INIT")[1]:find("reason=param", 1, true))
end)

test("Automatic: a European town gets a site style (logged with its reason), saved with the frame", function()
	local E = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" },
		params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local job = d:startJob(TOWN, E.t, { force = true, dry = true })
	for _ = 1, 40 do
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	eq(job.style.styleSource, "site")
	local line = logsWith(E, "STYLE")[1]
	ok(line:find("styleSource=site", 1, true) and line:find("styleWhy=plain:", 1, true), line)
	local fp = SV.frameParam(TOWN, job.style, nil)
	ok(fp.st ~= nil, "style index saved")
	local saved = SV.applyFrame(nil, fp)
	eq(SV.frame(saved, TOWN).style, job.style.id)
end)

test("happy path: assess -> plan -> pre-check -> SEND (logged first) -> BUILT, frame saved once", function()
	local E = fakeEngine()
	local d = D.new(E)
	ok(run(d, E, 400, nil, function() return E.pending ~= nil end), "a proposal was sent")
	local spec = E.pending.spec
	ok(#spec.edges > 0)
	ok(PR.noNegativeZero(spec))
	local W = E.W
	for _, n in ipairs(spec.joins) do
		ok(n == W.deadEnds.east or n == W.deadEnds.north, "joined only plain dead ends with a config: " .. n)
	end
	eq(#spec.joins, 2, "both plain dead ends grow (the east one 8 m off the lattice is adopted)")
	for _, n in ipairs(spec.cfgRemove) do ok(W.nodes[n].cfg, "config removed only where it exists") end
	for _, e in ipairs(spec.edges) do
		ok(e.src ~= nil)
		if e.node0 > 0 or e.node1 > 0 then
			local dead = e.node0 > 0 and e.node0 or e.node1
			local srcEdge
			for _, x in ipairs(W.edges) do if x.id == e.src then srcEdge = x end end
			ok(srcEdge.n0 == dead or srcEdge.n1 == dead, "a joining edge copies the dead end's own edge")
		end
	end
	local send = logsWith(E, "SEND")
	eq(#send, 1)
	ok(send[1]:find("town=100", 1, true))
	eq(#logsWith(E, "BUILT"), 0, "nothing reported before the callback")
	E.bal = E.bal - 0
	E.pending.cb(true, { cost = 300000, msgs = {} })
	run(d, E, 2)
	local built = logsWith(E, "BUILT")
	eq(#built, 1)
	ok(built[1]:find("ok=true", 1, true))
	eq(#E.events, 1)
	eq(E.events[1].name, SV.EV_FRAME)
	eq(E.events[1].param.town, TOWN)
	-- cooldown: no second proposal for this town right away
	E.pending = nil
	run(d, E, 300)
	eq(E.pending, nil)
	eq(d.counts.builds, 1)
end)

test("enough free lots: the check ends without planning", function()
	local E = fakeEngine()
	for _, e in ipairs(E.W.edges) do e.built = 2 end
	local d = D.new(E)
	run(d, E, 100)
	local checks = logsWith(E, "CHECK")
	ok(#checks >= 1)
	ok(checks[1]:find("needsRoom=false", 1, true), checks[1])
	-- (§75 follow-up: the main body on CHECK, logging only)
	ok(checks[1]:find(" rBody=%d+ r50=%d+ out=%d+/%d+ outFar=") ~= nil, checks[1])
	eq(#E.prechecks, 0)
end)

test("New towns only: init event first; existing towns are skipped, a fresh map's towns are not", function()
	local E = fakeEngine({ params = { act_on = 2, debug_log = 2 } })
	local d = D.new(E)
	run(d, E, 5, nil)
	eq(#E.events, 1)
	eq(E.events[1].name, SV.EV_INIT)
	eq(E.events[1].param.known, { TOWN })
	eq(d.phase, "init")
	local saved = SV.applyInit(nil, E.events[1].param)
	run(d, E, 400, saved)
	eq(d.phase, "run")
	eq(#E.prechecks, 0, "the town existed when the mod came: left alone")
	ok(#logsWith(E, "SKIP") >= 1)

	local E2 = fakeEngine({ params = { act_on = 2 }, gameTime = 0 })
	local d2 = D.new(E2)
	run(d2, E2, 5, nil)
	ok(E2.events[1].param.fresh)
	local saved2 = SV.applyInit(nil, E2.events[1].param)
	ok(run(d2, E2, 400, saved2, function() return E2.pending ~= nil end), "fresh map: every town grows")
end)

test("pre-check refusals: re-planned with half the edges, then the first piece is excluded", function()
	local E = fakeEngine({ precheckOk = function() return false end })
	local d = D.new(E)
	run(d, E, 200)
	ok(#E.prechecks >= 2, "retried " .. #E.prechecks)
	local first, last = E.prechecks[1], E.prechecks[#E.prechecks]
	ok(#last.edges <= #first.edges, "never larger")
	eq(E.pending, nil, "nothing sent")
	local s = d.towns[TOWN]
	ok(s.nExclude >= 1, "a piece is left out next time")
	-- either refused at the smallest size (fail) or the leftover was too small to build alone (tiny -> empty)
	local tiny = 0
	for _, l in ipairs(E.logs) do if l:find("tiny", 1, true) then tiny = tiny + 1 end end
	ok(d.counts.fails + tiny >= 1)
	ok(#logsWith(E, "REFUSED") >= 1)
	ok(#logsWith(E, "DIAGSUM") >= 1, "every edge pre-checked alone first (all fail here: no drop, halving)")
end)

test("pre-check refusal: the edges that fail alone are dropped and the increment planned again at full size", function()
	local badKey = nil
	local E = fakeEngine({ precheckOk = function(spec)
		for _, e in ipairs(spec.edges) do
			if badKey == nil then badKey = e.key end   -- the first edge ever pre-checked collides
			if e.key == badKey then return false end
		end
		return true
	end })
	local d = D.new(E)
	local sent = run(d, E, 400, nil, function() return E.pending ~= nil end)
	if not sent then for _, l in ipairs(E.logs) do print(l) end end
	ok(sent, "sent after the drop")
	local first = E.prechecks[1]
	for _, e in ipairs(E.pending.spec.edges) do ok(e.key ~= badKey, "colliding piece left out") end
	-- planned again at the same size (maxEdges kept), not halved; the result may be smaller when the loop rule
	-- (no loop hanging off one gateway) leaves only a tree at the remaining dead end
	ok(#E.pending.spec.edges >= 3, "built: " .. #E.pending.spec.edges .. " (first " .. #first.edges .. ")")
	local plans = logsWith(E, "PLAN")
	local m1 = plans[1]:match("maxEdges=(%d+)")
	for _, l in ipairs(plans) do eq(l:match("maxEdges=(%d+)"), m1, "same size: " .. l) end
	ok(d.towns[TOWN].exclude[badKey])
	eq(#logsWith(E, "PRUNE") >= 0, true)
	eq(D.notPossible({ "Construction Not Possible" }), true, "the engine's text has spaces")
	eq(D.notPossible({ "Construction_Not_Possible" }), true)
	eq(D.notPossible({ "Collision" }), false)
end)

test("a build refused by the engine is logged and all its pieces are left out next time", function()
	local E = fakeEngine()
	local d = D.new(E)
	run(d, E, 400, nil, function() return E.pending ~= nil end)
	local spec = E.pending.spec
	E.pending.cb(false, { msgs = {} })
	run(d, E, 2)
	eq(#logsWith(E, "FAILED"), 1)
	for _, e in ipairs(spec.edges) do ok(d.towns[TOWN].exclude[e.key], "excluded " .. e.key) end
	eq(#E.events, 0, "no frame saved for a failed build")
end)

test("errors in a stage are logged and cost only that check", function()
	local E = fakeEngine({ streetsError = true })
	local d = D.new(E)
	run(d, E, 50)
	local errs = logsWith(E, "ERROR")
	eq(#errs, 1)
	ok(errs[1]:find("stage=assess", 1, true))
	eq(d.phase, "run")
end)

test("a callback that never comes times out and frees the queue", function()
	local E = fakeEngine()
	local d = D.new(E)
	run(d, E, 400, nil, function() return E.pending ~= nil end)
	ok(d.inflight)
	run(d, E, (D.WAIT_TIMEOUT_S + 1) * 10)
	ok(not d.inflight)
	ok(logsWith(E, "FAILED")[1]:find("why=timeout", 1, true))
end)

--- Adds a sent spec's edges to the fake world, as the engine would (new ids above 1000).
local function applySpec(E, spec)
	local W = E.W
	local map = {}
	local nid = 1000 + #W.edges * 10
	for _, nd in ipairs(spec.nodes) do
		nid = nid + 1
		W.nodes[nid] = { id = nid, x = nd.pos[1], y = nd.pos[2], z = nd.pos[3], cfg = false }
		map[nd.entity] = nid
	end
	local eid = 5000 + #W.edges
	for _, e in ipairs(spec.edges) do
		eid = eid + 1
		W.edges[#W.edges + 1] = { id = eid, n0 = map[e.node0] or e.node0, n1 = map[e.node1] or e.node1, p0 = e.p0, p1 = e.p1,
			t0 = e.t0, t1 = e.t1, template = SMALL, lanes = 4, objects = 0, owned = false, inConstruction = false }
	end
end

before_each(function()
	D.hooks.paused, D.hooks.devBusy, D.hooks.debug, D.hooks.main, D.hooks.player = false, false, nil, nil, nil
end)

test("trigger: a town at its target whose lots sit in half-built edges (gaps) gets an increment", function()
	local E = fakeEngine()
	for _, e in ipairs(E.W.edges) do e.parcels, e.built = 20, 10 end    -- 50 % filled: lots of free lots, no open frontage
	local d = D.new(E)
	ok(run(d, E, 400, nil, function() return E.pending ~= nil end), "sent")
	local check = logsWith(E, "CHECK")[1]
	ok(check:find("why=low", 1, true) and check:find("free=150", 1, true) and check:find("open=0 ", 1, true), check)
end)

test("history: a successful build records the edges it added; BUILT says how many were found", function()
	local E = fakeEngine()
	local d = D.new(E)
	run(d, E, 400, nil, function() return E.pending ~= nil end)
	local spec = E.pending.spec
	applySpec(E, spec)
	E.pending.cb(true, { cost = 1, msgs = {} })
	run(d, E, 2)
	local h = d.towns[TOWN].history
	eq(#h, 1)
	eq(#h[1].edges, #spec.edges)
	eq(h[1].expected, #spec.edges)
	eq(h[1].joins, spec.joins)
	for _, n in ipairs(h[1].nodes) do ok(n > 1000, "only new nodes: " .. n) end
	ok(logsWith(E, "BUILT")[1]:find("found=" .. #spec.edges, 1, true))
end)

test("hooks: paused / devBusy hold the driver (no checks); debug overrides the param", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 1 } })
	local d = D.new(E)
	D.hooks.paused = true
	run(d, E, 400)
	eq(d.phase, "run")
	eq(d.counts.checks, 0)
	D.hooks.paused = false
	D.hooks.devBusy = true
	run(d, E, 100)
	eq(d.counts.checks, 0)
	D.hooks.devBusy = false
	D.hooks.debug = true
	ok(d:debugOn())
	run(d, E, 100)
	ok(d.counts.checks >= 1)
	ok(#logsWith(E, "CHECK") >= 1, "debug forced on by the hook")
	D.hooks.debug = false
	ok(not d:debugOn())
end)

test("startJob: a forced dry run plans and pre-checks a town with enough room, never sends", function()
	local E = fakeEngine({ params = { act_on = 2 } })   -- New towns only, the town is known: still forced
	for _, e in ipairs(E.W.edges) do e.built = 2 end
	local d = D.new(E, "[DEV]")
	d:loadConfig()
	d.phase = "manual"
	local outcome
	local job = d:startJob(TOWN, E.t, { force = true, dry = true, onDone = function(_j, o) outcome = o end })
	ok(job ~= nil)
	eq(d:startJob(TOWN, E.t, {}), nil, "one job at a time")
	for _ = 1, 20 do
		if not d:advance(E.t, SV.applyInit(nil, { known = { TOWN } })) then break end
		E.t = E.t + 100000
	end
	eq(outcome, "dry")
	eq(E.pending, nil)
	ok(#job.spec.edges > 0)
	ok(job.pre.ok)
	local dry = logsWith(E, "DRY")
	eq(#dry, 0, "own prefix")
	local found = false
	for _, l in ipairs(E.logs) do if l:find("[DEV] DRY", 1, true) then found = true end end
	ok(found)
end)

test("startJob: style modes (main = site style in Automatic, region follows the map, a profile id overrides)", function()
	local E = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" }, params = { act_on = 3 } })
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local function styleOf(mode)
		local job = d:startJob(TOWN, E.t, { force = true, dry = true, styleMode = mode })
		for _ = 1, 30 do
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
		end
		return job.style
	end
	eq(styleOf(nil).styleSource, "site", "main mode, Automatic: the site style")
	local r = styleOf("region")
	eq(r.id, "EU_ORGANIC")
	ok(r.outer ~= nil and r.outer.id == "EU_EXTENSION")
	local m = styleOf("MED_HILL")
	eq(m.id, "MED_HILL")
	local j = styleOf("JP_DENSE")
	eq(j.id, "JP_DENSE")
	-- (the cache key also carries the decade since 2026-10-13: the outer zone follows the years, ot_grid)
	local key = nil
	for k in pairs(d.towns[TOWN].styles) do if k:find("^region:new") then key = k end end
	ok(key ~= nil and d.towns[TOWN].styles[key] == r, "one style table per mode (master plan cache)")
end)

test("player toggle: no player by default (SEND player=off); hooks.player = true sends with one", function()
	local function sendLine(playerHook)
		local E = fakeEngine()
		local ctxArgs = {}
		function E.context(asPlayer) ctxArgs[#ctxArgs + 1] = asPlayer; return {} end
		D.hooks.player = playerHook
		local d = D.new(E)
		run(d, E, 400, nil, function() return E.pending ~= nil end)
		D.hooks.player = nil
		return logsWith(E, "SEND")[1], ctxArgs
	end
	local off, argsOff = sendLine(nil)
	ok(off:find("player=off", 1, true), off)
	eq(argsOff[#argsOff], false)
	local on, argsOn = sendLine(true)
	ok(on:find("player=on", 1, true), on)
	eq(argsOn[#argsOn], true)
end)

test("diagnosis: a Construction_Not_Possible pre-check is followed by one pre-check per edge (DIAG, DIAGSUM)", function()
	local E = fakeEngine()
	local badKey
	-- the whole increment and every single-edge proposal containing edge 2's geometry fail
	function E.precheck(p, _ctx)
		E.prechecks[#E.prechecks + 1] = p.spec
		local bad = false
		for _, e in ipairs(p.spec.edges) do if badKey == nil or e.key == badKey then bad = true end end
		if #p.spec.edges > 1 then bad = true end
		return { ok = not bad, msgs = bad and { "Construction_Not_Possible" } or {}, collisions = 0, buildings = 0,
			cost = 1, us = 1000 }
	end
	D.hooks.diagnose = true
	D.hooks.debug = true
	local d = D.new(E)
	-- learn edge 2's key from the first plan, then let the driver run
	local orig = d.plan
	d.plan = function(self, job, now)
		orig(self, job, now)
		if job.inc and badKey == nil then badKey = job.inc.edges[2].key or "none" end
	end
	run(d, E, 600, nil, function() return #logsWith(E, "DIAGSUM") > 0 end)
	D.hooks.diagnose, D.hooks.debug = false, nil
	local sums = logsWith(E, "DIAGSUM")
	eq(#sums, 1, "diagnosed once per job")
	ok(sums[1]:find("whole=refused", 1, true), sums[1])
	local diags = logsWith(E, "DIAG ")
	ok(#diags >= 1, "failing edges logged")
	ok(#diags <= D.DIAG_LOG)
	ok(diags[1]:find("minR=", 1, true) and diags[1]:find("msgs=Construction_Not_Possible", 1, true), diags[1])
	-- single-edge proposals: one edge each, entity -1
	local singles = 0
	for _, sp in ipairs(E.prechecks) do
		if #sp.edges == 1 and sp.edges[1].entity == -1 then singles = singles + 1 end
	end
	ok(singles >= 3, "single-edge pre-checks: " .. singles)
	-- afterwards the normal refusal path ran (re-plan smaller)
	ok(#logsWith(E, "REFUSED") >= 1)
end)

test("diagnosis off (default): no single-edge pre-checks; a dry run with it on logs DIAGSUM whole=ok", function()
	local E = fakeEngine({ precheckOk = function(spec) return #spec.edges > 0 end })
	local d = D.new(E)
	run(d, E, 400, nil, function() return E.pending ~= nil end)
	eq(#logsWith(E, "DIAGSUM"), 0)
	local E2 = fakeEngine({ params = { act_on = 3 } })
	local d2 = D.new(E2, "[DEV]")
	d2:loadConfig()
	d2.phase = "manual"
	D.hooks.diagnose = true
	local outcome
	d2:startJob(TOWN, E2.t, { force = true, dry = true, styleMode = "EU_ORGANIC", onDone = function(_j, o) outcome = o end })
	for _ = 1, 40 do
		if not d2:advance(E2.t, nil) then break end
		E2.t = E2.t + 100000
	end
	D.hooks.diagnose = false
	eq(outcome, "dry")
	local sum
	for _, l in ipairs(E2.logs) do if l:find("[DEV] DIAGSUM", 1, true) then sum = l end end
	ok(sum and sum:find("whole=ok", 1, true) and sum:find("failed=0", 1, true), tostring(sum))
end)

test("organic styles on the engine town: every planned edge passes the geometry checker", function()
	local CK = ug_require(F.DIR .. "ot_check.lua")
	-- (NA suburb's 16 m jittered lattice finds no free junction next to this small 100 m grid: test_check)
	for _, mode in ipairs({ "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "JP_DENSE", "NORDIC", "NA_GRID" }) do
		local E = fakeEngine({ params = { act_on = 3 } })
		local d = D.new(E)
		d:loadConfig()
		d.phase = "manual"
		local job = d:startJob(TOWN, E.t, { force = true, dry = true, styleMode = mode })
		for _ = 1, 40 do
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
		end
		ok(job.inc and #job.inc.edges > 0, mode .. ": planned")
		local rep = CK.increment(job.inc, job.g)
		-- slope left out: the fake town's nodes sit at z 10 on a flat sampler at 20 m
		ok(CK.passes(rep, { "radius", "short", "angle", "tangent", "kink" }), mode .. ": " .. CK.summary(rep))
	end
end)

test("diagnosis: whole refused, every edge passes alone -> junction stars pre-checked (DIAGNODE), the star's newest edge pruned", function()
	local E = fakeEngine()
	local bad
	local function sig(e) return string.format("%.1f,%.1f>%.1f,%.1f", e.p0[1], e.p0[2], e.p1[1], e.p1[2]) end
	function E.precheck(p, _ctx)
		E.prechecks[#E.prechecks + 1] = p.spec
		if bad == nil and #p.spec.edges > 2 then
			-- the first whole increment: its first junction star is the failing combination
			local st = D.stars(p.spec)[1]
			bad = { n = #st.edges }
			for _, i in ipairs(st.edges) do bad[sig(p.spec.edges[i])] = true end
		end
		local hit = 0
		if bad then for _, e in ipairs(p.spec.edges) do if bad[sig(e)] then hit = hit + 1 end end end
		local fail = bad ~= nil and hit >= bad.n
		return { ok = not fail, msgs = fail and { "Construction Not Possible" } or {}, collisions = 0, buildings = 0, cost = 1,
			us = 1000 }
	end
	D.hooks.diagnose = true
	D.hooks.debug = true
	local d = D.new(E)
	run(d, E, 800, nil, function() return #logsWith(E, "PRUNE") > 0 end)
	D.hooks.diagnose, D.hooks.debug = false, nil
	local nodes = logsWith(E, "DIAGNODE")
	ok(#nodes >= 1, "failing star logged")
	ok(nodes[1]:find("msgs=Construction_Not_Possible", 1, true), nodes[1])
	local sum = logsWith(E, "DIAGSUM")[1]
	ok(sum and sum:find("failed=0", 1, true) and sum:find("starsFailed=", 1, true), tostring(sum))
	local pr = logsWith(E, "PRUNE")[1]
	ok(pr and pr:find("by=star", 1, true), tostring(pr))
end)

test("stars / subIncrement: junction stars of an increment and their sub-proposals", function()
	local inc = { nodes = { { entity = -4, x = 0, y = 0, z = 1 }, { entity = -5, x = 50, y = 0, z = 1 }, { entity = -6, x = 0, y = 50, z = 1 } },
		edges = {
			{ entity = -1, node0 = -4, node1 = -5, p0 = { 0, 0, 1 }, p1 = { 50, 0, 1 }, t0 = { 50, 0, 0 }, t1 = { 50, 0, 0 }, key = "a" },
			{ entity = -2, node0 = -4, node1 = -6, p0 = { 0, 0, 1 }, p1 = { 0, 50, 1 }, t0 = { 0, 50, 0 }, t1 = { 0, 50, 0 }, key = "b" },
			{ entity = -3, node0 = -6, node1 = 9, p0 = { 0, 50, 1 }, p1 = { 0, 90, 1 }, t0 = { 0, 40, 0 }, t1 = { 0, 40, 0 }, key = "c" },
		} }
	local st = D.stars(inc)
	eq(#st, 2)
	eq(st[1].node, -4)
	eq(st[1].edges, { 1, 2 })
	near(st[1].minAngle, 90, 1e-6)
	eq(st[2].node, -6)
	local sub = D.subIncrement(inc, { 2, 3 })
	eq(#sub.edges, 2)
	eq(sub.edges[1].entity, -1)
	eq(sub.edges[2].node1, 9)
	eq(#sub.nodes, 2)
	eq(sub.joins, { { node = 9, edge = -2 } })
	eq(sub.edges[1].node1, sub.edges[2].node0, "shared new node renumbered once")
end)

test("startJob: a forced shape and a template override reach the style; STYLE logs shape and reason", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local job = d:startJob(TOWN, E.t, { force = true, dry = true, styleMode = "EU_EXTENSION", shape = "linear",
		override = { templates = { main = "medium", medium = "medium", small = "medium" } } })
	for _ = 1, 60 do
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	ok(job.style and job.style.shape, "style has a shape")
	eq(job.style.shape.id, "linear")
	ok(job.style.shape.reason:find("forced", 1, true), job.style.shape.reason)
	for _, c in ipairs({ "main", "medium", "small" }) do
		ok(job.style.templatePaths[c]:find("town_new_medium", 1, true), c .. ": " .. job.style.templatePaths[c])
	end
	local st = logsWith(E, "STYLE")[1]
	ok(st and st:find("shape=linear", 1, true) and st:find("shapeWhy=forced", 1, true) and st:find("override=yes", 1, true),
		tostring(st))
	local plan = logsWith(E, "PLAN")[1]
	ok(plan and plan:find("shape=linear", 1, true) and plan:find("self=0", 1, true), tostring(plan))
	-- the main mode keeps its seeded shape (no override): another cached style table
	local job2 = d:startJob(TOWN, E.t, { force = true, dry = true, styleMode = "EU_EXTENSION" })
	for _ = 1, 60 do
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	ok(job2.style ~= job.style, "separate style per shape / override")
	ok(job2.style.templatePaths.small:find("town_new_small", 1, true))
end)

test("diagnosis: a joint edge refused alone with no collision gets DIAGJOINT with variant pre-checks", function()
	-- the engine refuses any joint edge that carries a config at its existing node (only the plain variant passes)
	local E = fakeEngine()
	function E.precheck(p, _ctx)
		E.prechecks[#E.prechecks + 1] = p.spec
		local joint = false
		for _, c in ipairs(p.spec.cfgAdd) do if c.node > 0 then joint = true end end
		return { ok = not joint, msgs = joint and { "Construction Not Possible" } or {}, collisions = 0, buildings = 0,
			cost = 1, us = 1000 }
	end
	D.hooks.diagnose = true
	D.hooks.debug = true
	local d = D.new(E)
	run(d, E, 600, nil, function() return #logsWith(E, "DIAGSUM") > 0 end)
	D.hooks.diagnose, D.hooks.debug = false, nil
	local j = logsWith(E, "DIAGJOINT")
	ok(#j >= 1, "joint diagnosed")
	ok(#j <= D.DIAG_LOG)
	ok(j[1]:find("plain=ok", 1, true) and j[1]:find("straight=Construction", 1, true) and j[1]:find("turn=", 1, true)
		and j[1]:find("footprint=", 1, true), j[1])
	ok(logsWith(E, "DIAGSUM")[1]:find("joints=" .. #j, 1, true))
	-- nothing is ever sent by the diagnosis
	eq(E.pending, nil)
end)

test("jointInfo / jointVariant: the turn at the dead end and a straight re-aim", function()
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = -100, y = 0, z = 5 }, { id = 2, x = 0, y = 0, z = 5 } },
		edges = { { id = 10, node0 = 1, node1 = 2, class = "small" } } })
	local e = { entity = -1, node0 = 2, node1 = -2, p0 = { 0, 0, 5 }, p1 = { 0, 20, 5 }, t0 = { 0, 20, 0 }, t1 = { 0, 20, 0 },
		class = "small", key = "conn:2" }
	local inc = { nodes = { { entity = -2, x = 0, y = 20, z = 5 } }, edges = { e }, joins = { { node = 2, edge = -1 } } }
	local ji = D.jointInfo(g, e)
	near(math.deg(ji.turn), 90, 1e-6)
	near(ji.fp, 8, 1e-6)
	near(ji.exLen, 100, 1e-6)
	local v = D.jointVariant(inc, 1, ji, "straight")
	near(v.edges[1].p1[1], 20, 1e-6, "along the dead end's street")
	near(v.edges[1].p1[2], 0, 1e-6)
	local l = D.jointVariant(inc, 1, ji, "long")
	near(l.edges[1].p1[2], 40, 1e-6)
end)

test("planning is sliced over ticks when it runs long (coroutine); the result is the same as in one go", function()
	local function planned(slice)
		local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
		local clock = 0
		function E.nowUs()   -- every clock read costs 3 ms: the plan stage overruns its slice
			clock = clock + 3000
			return E.t + clock
		end
		D.SLICE_PLAN = slice
		local d = D.new(E)
		d:loadConfig()
		d.phase = "manual"
		local job = d:startJob(TOWN, E.t, { force = true, dry = true, styleMode = "EU_EXTENSION" })
		for _ = 1, 80 do
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
		end
		D.SLICE_PLAN = true
		local plan = logsWith(E, "PLAN")[1]
		return job, plan
	end
	local j1, p1 = planned(true)
	local j2, p2 = planned(false)
	ok(tonumber(p1:match("slices=(%d+)")) >= 2, p1)
	eq(p2:match("slices=(%d+)"), "1")
	eq(#j1.inc.edges, #j2.inc.edges, "same increment")
	eq(F.dump({ j1.inc }), F.dump({ j2.inc }))
end)

test("refused with a sharp turn at a dead end: planned again once with the joint rule, then halved", function()
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	local E = fakeEngine()
	local d = D.new(E)
	local g = OG.new()
	OG.addNode(g, 1, 0, 0, 0)
	OG.addNode(g, 2, 100, 0, 0)
	OG.addEdge(g, 10, 1, 2, "small")
	local edges = {}
	for i = 1, 8 do
		edges[i] = { entity = -i, node0 = i == 1 and 2 or -i, node1 = -(i + 1), p0 = { 100, 0 }, p1 = { 100, 80 },
			key = "k" .. i }
	end
	local job = { town = TOWN, g = g, inc = { edges = edges }, maxEdges = 24 }
	d:refused(job, 0, "precheck", {})
	eq(job.jointRule, true)
	eq(job.stage, "plan")
	eq(job.maxEdges, 24, "same size")
	eq(d.counts.jointReplans, 1)
	d:refused(job, 0, "precheck", {})
	eq(job.maxEdges, 4, "then halved")
end)

---------------------------------------------------------------------------
-- shapes round (SHAPES_BRIEF 2026-10-12)

--- The fake world plus an arm of town street from the east dead end (200, 0) out to x = 1600 in 100 m steps
--- (beyond the snapshot circle: buildings within 90 m, extent + 300 m). Past x = 1200 the closest town is another.
local function withArm(E)
	local W = E.W
	local prev = W.deadEnds.east
	local nid, eid = 1000, 1000
	for x = 300, 1600, 100 do
		nid, eid = nid + 1, eid + 1
		W.nodes[nid] = { id = nid, x = x, y = 0, z = 10, cfg = true }
		local a = W.nodes[prev]
		W.edges[#W.edges + 1] = { id = eid, n0 = prev, n1 = nid, p0 = { a.x, a.y, 10 }, p1 = { x, 0, 10 }, t0 = { 100, 0, 0 },
			t1 = { 100, 0, 0 }, template = SMALL, lanes = 4, objects = 0, owned = false, inConstruction = false }
		prev = nid
	end
	function E.edge(id)
		for _, e in ipairs(W.edges) do if e.id == id then return e end end
		return nil
	end
	function E.closestTown(x, _y) return x > 1200 and 999 or TOWN end
	return E
end

test("town network: streets connected beyond the snapshot circle are followed (arm tips stay visible)", function()
	local E = withArm(fakeEngine({}))
	local d = D.new(E)
	d:loadConfig()
	local m = d:measure(TOWN)
	eq(m.net, 7, "arm edges 500 -> 1200 m added")
	local far, other = false, false
	for _, ed in ipairs(m.edges) do
		local x = math.max(ed.p0[1], ed.p1[1])
		if x >= 1100 and x <= 1200 then far = true end
		if x > 1250 then other = true end
	end
	ok(far, "the arm out to 1200 m is in the snapshot")
	ok(not other, "streets nearer another town are left out")
	eq(#m.pts > 0, true, "building positions kept (SHAPE line houses)")
	-- without E.edge (older engine layer) nothing changes
	local E2 = fakeEngine({})
	local d2 = D.new(E2)
	d2:loadConfig()
	local m2 = d2:measure(TOWN)
	eq(m2.net, 0)
end)

test("SHAPE line per planned increment of a shaped town; the lock probe sends locked edges", function()
	local E = withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } }))
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local job = d:startJob(TOWN, E.t, { force = true, styleMode = "EU_EXTENSION", shape = "linear", lock = true })
	for _ = 1, 80 do
		if E.pending then break end
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	local line = logsWith(E, "SHAPE")[1]
	ok(line and line:find("shape=linear", 1, true) and line:find("streets=", 1, true) and line:find("houses=", 1, true)
		and line:find("inc=arm", 1, true) and line:find("net=", 1, true), tostring(line))
	local snap = logsWith(E, "SNAPSHOT")[1]
	ok(snap and snap:find("net=", 1, true), tostring(snap))
	ok(E.pending ~= nil, "sent")
	if E.pending then
		for _, e in ipairs(E.pending.spec.edges) do eq(e.locked, true, "locked edge") end
	end
	ok(job.lock, "job carries the lock")
end)

test("proposal spec: edges are unlocked unless the build asks for the lock", function()
	local PRm = ug_require(F.DIR .. "ot_proposal.lua")
	local inc = { nodes = { { entity = -2, x = 300, y = 0, z = 10 } },
		edges = { { entity = -1, node0 = 9, node1 = -2, p0 = { 200, 0, 10 }, p1 = { 300, 0, 10 }, t0 = { 100, 0, 0 },
			t1 = { 100, 0, 0 }, class = "small", template = SMALL, key = "k" } }, joins = { { node = 9, edge = -1 } } }
	local info = { nodes = { [9] = { hasConfig = true, edges = { 1 }, lanes = 4, src = 1, template = SMALL } },
		sources = { [SMALL] = 1 }, fallback = 1, edgeLanes = { [1] = 4 } }
	local spec = PRm.build(inc, info)
	ok(spec, "built")
	if spec then eq(spec.edges[1].locked, nil) end
	info.lock = true
	local spec2 = PRm.build(inc, info)
	if spec2 then eq(spec2.edges[1].locked, true) end
end)

---------------------------------------------------------------------------
-- houses onto the arms (NEXT_PHASE_BRIEF 13): lock arm / rim streets, dosed fill, metropolis

--- Runs a forced job of a shaped town until it sends; returns the job.
local function shapedJob(E, d, o)
	o = o or {}
	local opts = { force = true, styleMode = "EU_EXTENSION", shape = o.shape or "linear" }
	for k, v in pairs(o) do opts[k] = v end
	local job = d:startJob(TOWN, E.t, opts)
	for _ = 1, 120 do
		if E.pending then break end
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	return job
end

local function withDevelop(E)
	E.develops = {}
	function E.developAt(x, y, streets, upgrade, cb)
		E.develops[#E.develops + 1] = { x = x, y = y, streets = streets, upgrade = upgrade, cb = cb }
	end
	return E
end

test("lock (legacy): a shaped town sends its arm / rim streets locked, the rest unlocked", function()
	local E = withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } }))
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	-- (§65: the legacy lock of towns framed before it; LOCK_DEFAULT "legacy" gives it to new towns too)
	local def0 = D.LOCK_DEFAULT
	D.LOCK_DEFAULT = "legacy"
	local job = shapedJob(E, d)
	D.LOCK_DEFAULT = def0
	ok(E.pending ~= nil, "sent")
	eq(job.townLock, "legacy")
	eq(D.lockMode(job), "shape")
	local sh = job.style.shape
	local env = D.envLevel(job.report)
	local nLocked = 0
	for _, e in ipairs(E.pending.spec.edges) do
		local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
		local want = D.armOrRim(sh, mx, my, env, job.sampler) and true or nil
		eq(e.locked, want, "locked exactly on arm / rim streets")
		if e.locked then nLocked = nLocked + 1 end
	end
	-- (the fake town's one-edge increment sits by the core: nothing to lock there; D.lockKeys below)
	E.pending.cb(true, { cost = 1, msgs = {} })
	d:advance(E.t, nil)
	ok(logsWith(E, "BUILT")[1]:find("locked=" .. nLocked, 1, true), "BUILT counts the locked edges")
	-- lock off for a job, and the old default (NA grid, no shape): nothing locked
	local E2 = withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } }))
	local d2 = D.new(E2)
	d2:loadConfig()
	d2.phase = "manual"
	shapedJob(E2, d2, { lock = "off" })
	for _, e in ipairs(E2.pending.spec.edges) do eq(e.locked, nil) end
	-- D.lockKeys on a synthetic linear town (axis east): arm streets and rim streets locked, the core not
	local sh2 = { id = "linear", centre = { 0, 0 }, axis = 0, arms = { 0, math.pi }, block = 100 }
	local inc = { edges = {
		{ key = "arm", p0 = { 400, 0 }, p1 = { 500, 0 } },
		{ key = "core", p0 = { 0, 20 }, p1 = { 0, 90 } },
		{ key = "rim", p0 = { 0, 600 }, p1 = { 0, 700 } } } }
	local keys, n, mode = D.lockKeys({ style = { shape = sh2 }, inc = inc, report = { envCap = 500, envScale = 1 } })
	eq(mode, "shape"); eq(n, 2)
	ok(keys.arm and keys.rim and not keys.core)
	eq(D.lockKeys({ style = { shape = sh2 }, inc = inc, lock = "off" }), nil)
	eq(select(3, D.lockKeys({ style = { shape = sh2 }, inc = inc, lock = true })), "all")
	-- compact / no shape: never arm or rim
	ok(not D.armOrRim(nil, 0, 0, 100))
	ok(not D.armOrRim({ id = "compact", centre = { 0, 0 } }, 500, 0, 100))
end)

-- (§69: the default is "steer" now; the §65 tests below run under the "mod" lock through the dev hook)
local function withLock(mode, fn)
	local H = ug_require(F.DIR .. "ot_hooks.lua")
	local old = H.lockDefault
	H.lockDefault = mode
	local okR, err = pcall(fn)
	H.lockDefault = old
	assert(okR, err)
end

test("lock (§65 \"mod\"): a new town sends every street locked; BUILT lockMode=mod; the frame saves lm=1 and its core", function()
	withLock("mod", function()
	local E = withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } }))
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	eq(D.LOCK_DEFAULT, "steer")
	local job = shapedJob(E, d)
	ok(E.pending ~= nil, "sent")
	eq(job.townLock, "mod")
	eq(D.lockMode(job), "mod")
	eq(job.lockKeys, nil, "no keys: info.lock covers every edge")
	ok(#E.pending.spec.edges > 0)
	for _, e in ipairs(E.pending.spec.edges) do eq(e.locked, true, "every mod street locked") end
	E.pending.cb(true, { cost = 1, msgs = {} })
	d:advance(E.t, nil)
	local built = logsWith(E, "BUILT")[1]
	ok(built:find("locked=" .. #job.spec.edges, 1, true) and built:find("lockMode=mod", 1, true), built)
	local fr
	for _, ev in ipairs(E.events) do if ev.name == SV.EV_FRAME then fr = ev.param end end
	ok(fr, "frame sent")
	eq(fr.lm, 1)
	ok(type(fr.e0) == "number" and fr.e0 > 0, "core edges saved: " .. tostring(fr.e0))
	local saved = SV.applyFrame(nil, fr)
	eq(SV.frame(saved, TOWN).lockMode, "mod")
	eq(SV.frame(saved, TOWN).core, fr.e0)
	-- (the saved copy survives the save's normalize)
	local again = SV.normalize(saved)
	eq(again.frames[tostring(TOWN)].lm, 1)
	eq(again.frames[tostring(TOWN)].e0, fr.e0)
	-- a job's own lock still wins: "shape" / "off" / the dev "all"
	eq(D.lockMode({ lock = "shape", townLock = "mod" }), "shape")
	eq(D.lockMode({ lock = "off", townLock = "mod" }), "off")
	eq(D.lockMode({ lock = "mod" }), "mod")
	ok(D.locksAll("mod") and D.locksAll("all") and not D.locksAll("shape") and not D.locksAll("off"))
	end)
end)

test("lock (§69 steer default): a new town's build locks by the policy (BUILT steer=), its frame saves lm=2 and gk", function()
	local E = withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } }))
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local job = shapedJob(E, d)
	ok(E.pending ~= nil, "sent")
	eq(job.townLock, "steer")
	eq(job.lockModeUsed, "steer")
	ok(job.steerC ~= nil and job.steerTally ~= nil, "the policy ran")
	local nl, n = 0, 0
	for _, e in ipairs(E.pending.spec.edges) do
		n = n + 1
		if e.locked then nl = nl + 1 end
	end
	ok(n > 0 and nl > 0, string.format("%d of %d locked", nl, n))
	E.pending.cb(true, { cost = 1, msgs = {} })
	d:advance(E.t, nil)
	local built = logsWith(E, "BUILT")[1]
	ok(built:find("lockMode=steer", 1, true) and built:find(" steer=", 1, true) and built:find(" tips=", 1, true), built)
	local fr
	for _, ev in ipairs(E.events) do if ev.name == SV.EV_FRAME then fr = ev.param end end
	ok(fr, "frame sent")
	eq(fr.lm, 2); eq(fr.gk, 1)
	eq(SV.frame(SV.applyFrame(nil, fr), TOWN).lockMode, "steer")
	-- the PLAN line carries the steer fields
	local plan = logsWith(E, "PLAN")[1]
	ok(plan and plan:find("lockMode=steer", 1, true) and plan:find("spikeTrim=", 1, true) and plan:find("rakeJoin=", 1, true), tostring(plan))
end)

test("lock (§65): old saves keep the legacy lock (frame without lm), framed towns keep theirs, new towns the default", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	local old = SV.applyFrame(nil, { town = TOWN, a = 0, x = 0, y = 0 })
	eq(old.frames[tostring(TOWN)].lm, nil)
	eq(d:townLockMode(TOWN, old), "legacy", "a frame from before §65")
	eq(D.lockMode({ townLock = "legacy" }), D.LOCK_SHAPE and "shape" or "off")
	local d2 = D.new(E)
	d2:loadConfig()
	eq(d2:townLockMode(TOWN, SV.applyFrame(nil, { town = TOWN, a = 0, x = 0, y = 0, lm = 1 })), "mod")
	local d3 = D.new(E)
	d3:loadConfig()
	eq(d3:townLockMode(TOWN, nil), "steer", "no frame: LOCK_DEFAULT (§69)")
	-- cached on the town state: a frame arriving later this session changes nothing
	eq(d3:townLockMode(TOWN, old), "steer")
	-- (§69: a steer frame, lm = 2)
	local d5 = D.new(E)
	d5:loadConfig()
	eq(d5:townLockMode(TOWN, SV.applyFrame(nil, { town = TOWN, a = 0, x = 0, y = 0, lm = 2 })), "steer")
	-- the dev hook sets the default for towns framed this session
	local H = ug_require(F.DIR .. "ot_hooks.lua")
	H.lockDefault = "legacy"
	local d4 = D.new(E)
	d4:loadConfig()
	eq(d4:townLockMode(TOWN, nil), "legacy")
	H.lockDefault = nil
	-- a legacy town's frame has no lm, an unknown core no e0
	local fp = SV.frameParam(TOWN, { axis = 0, centre = { 0, 0 } }, nil, nil, nil, { lock = "legacy" })
	eq(fp.lm, nil); eq(fp.e0, nil)
	local fp2 = SV.frameParam(TOWN, { axis = 0, centre = { 0, 0 } }, nil, nil, nil, { lock = "mod", core = 12.4 })
	eq(fp2.lm, 1); eq(fp2.e0, 12)
end)

test("lock (§65): every proposal kind of a mod-locked town builds locked (buildInfo), a legacy one by its keys", function()
	withLock("mod", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	local kinds = { {}, { satPlan = {} }, { leadPlan = {} }, { worksPlan = {} }, { bridgePlan = { typeIndex = 2 } },
		{ framePlan = {} }, { head = true }, { inc = { rings = {} } } }
	for i, k in ipairs(kinds) do
		local job = { town = TOWN, edges = {}, style = {} }
		for kk, v in pairs(k) do job[kk] = v end
		local info = d:buildInfo(job)
		eq(info.lock, true, "kind " .. i .. " locked")
		eq(job.townLock, "mod")
	end
	-- a legacy town: info.lock off, the kind's keys decide (PR.build)
	local dl = D.new(E)
	dl:loadConfig()
	dl:townLockMode(TOWN, SV.applyFrame(nil, { town = TOWN, a = 0, x = 0, y = 0 }))
	local job = { town = TOWN, edges = {}, style = {}, lockKeys = { a = true } }
	local info = dl:buildInfo(job)
	eq(info.lock, false)
	eq(info.lockKeys.a, true)
	-- PR.build with info.lock: forest lanes, ring quarters and keyed edges all locked
	local inc = { nodes = { { entity = -2, x = 300, y = 0, z = 10 }, { entity = -3, x = 400, y = 0, z = 10 } },
		edges = { { entity = -1, node0 = 9, node1 = -2, p0 = { 200, 0, 10 }, p1 = { 300, 0, 10 }, t0 = { 100, 0, 0 },
			t1 = { 100, 0, 0 }, class = "small", template = SMALL, key = "k1" },
			{ entity = -4, node0 = -2, node1 = -3, p0 = { 300, 0, 10 }, p1 = { 400, 0, 10 }, t0 = { 100, 0, 0 },
			t1 = { 100, 0, 0 }, class = "small", template = SMALL, key = "k2" } }, joins = { { node = 9, edge = -1 } } }
	local pinfo = { nodes = { [9] = { hasConfig = true, edges = { 1 }, lanes = 4, src = 1, template = SMALL } },
		sources = { [SMALL] = 1 }, fallback = 1, edgeLanes = { [1] = 4 }, lock = true }
	local spec = PR.build(inc, pinfo)
	ok(spec, "built")
	for _, e in ipairs(spec.edges) do eq(e.locked, true) end
	end)
end)

test("stall guard (§65): a mod-locked town under its target whose buildings stand still fires, levels up, is capped", function()
	local A = ug_require(F.DIR .. "ot_assess.lua")
	local st = {}
	local fired = {}
	for i = 1, 3 * A.STALL_N do
		local lv = A.stall(st, 0.6, 100)
		if lv then fired[#fired + 1] = { i, lv } end
	end
	eq(#fired, 3)
	eq(fired[1][1], A.STALL_N); eq(fired[1][2], 1)
	eq(fired[2][2], 2); eq(fired[3][2], 3)
	-- the level stays at STALL_LEVELS
	for _ = 1, A.STALL_N do A.stall(st, 0.6, 100) end
	eq(st.level, A.STALL_LEVELS)
	-- growth ends the streak, so does a ratio back above STALL_RATIO, or an unknown / NaN one
	A.stall(st, 0.6, 200)
	eq(st.n, 1); eq(st.level, 0)
	A.stall(st, 0.9, 200)
	eq(st.n, 0)
	A.stall(st, 0 / 0, 200)
	eq(st.n, 0)
	-- slow growth below STALL_GROW still counts as standing still
	local s2 = {}
	A.stall(s2, 0.5, 100)
	A.stall(s2, 0.5, 101)
	eq(A.stall(s2, 0.5, 102), 1)
	-- capped: at most STALL_MAX fires, then one "capped", then nothing (bounded however long the town stalls)
	local s3, fires, capped = {}, 0, 0
	for _ = 1, 10000 do
		local lv, ev = A.stall(s3, 0.5, 100)
		if lv then fires = fires + 1 end
		if ev == "capped" then capped = capped + 1 end
	end
	eq(fires, A.STALL_MAX)
	eq(capped, 1)
	eq(s3.fires, A.STALL_MAX)
end)

test("stall guard (§65, driver): STALL line, a check that would wait builds (why=stall), never when held or over", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	d:townState(TOWN).stall = { n = 3, fires = 1, b0 = 49 }
	local m = { needs = false, why = "ahead", ratio = 0.6, buildings = 49, lots = { open = 10, ownOpen = 30 }, dem = { lead = 20 } }
	d:stallGuard({ town = TOWN }, TOWN, m, 1, nil, nil)
	eq(m.needs, true); eq(m.why, "stall"); eq(m.stall, 1)
	local l = logsWith(E, "STALL")[1]
	ok(l and l:find("event=fire level=1 streak=3 fires=1", 1, true) and l:find("applied=true", 1, true), tostring(l))
	local m2 = { needs = false, why = "ahead", ratio = 0.6, buildings = 49 }
	d:stallGuard({ town = TOWN }, TOWN, m2, 2, nil, "created")
	eq(m2.needs, false); eq(m2.stall, nil)
	ok(logsWith(E, "STALL")[2]:find("applied=false held=created", 1, true))
	local m3 = { needs = false, why = "over", ratio = 0.6, buildings = 49 }
	d:stallGuard({ town = TOWN }, TOWN, m3, 1, nil, nil)
	eq(m3.needs, false)
	d:stallGuard({ town = TOWN }, TOWN, { needs = false, why = "open", buildings = 49 }, nil, "capped", nil)
	ok(logsWith(E, "STALL")[4]:find("event=capped", 1, true))
end)

test("stall guard (§65, driver): checks of a town at half its target with constant buildings fire at STALL_N; the plan is bigger", function()
	withLock("mod", function()
	local A = ug_require(F.DIR .. "ot_assess.lua")
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	function E.townCaps(_t) return { target = 1000, actual = 500, sizeFactors = { 1, 1, 1 } } end
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local plans = {}
	for i = 1, A.STALL_N do
		local job = d:startJob(TOWN, E.t, {})
		for _ = 1, 200 do
			if E.pending then
				E.pending.cb(true, { cost = 1, msgs = {} })
				E.pending = nil
			end
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
		end
		plans[i] = job
	end
	local st = logsWith(E, "STALL")
	eq(#st, 1, "one fire at the STALL_N-th check")
	ok(st[1]:find("level=1", 1, true) and st[1]:find("capRatio=0.500", 1, true), st[1])
	local ck = logsWith(E, "CHECK")
	ok(ck[#ck]:find("lockMode=mod", 1, true) and ck[#ck]:find("stallStreak=" .. A.STALL_N, 1, true)
		and ck[#ck]:find("gameEdges=", 1, true) and ck[#ck]:find("modEdges=", 1, true), ck[#ck])
	eq(plans[A.STALL_N].stall, 1)
	-- a stalled plan asks for STALL_INC_MUL x the usual increment (at most STALL_MAX_EDGES)
	local base = A.maxEdges(d.opts.lookahead)
	local cut = plans[A.STALL_N].upward and plans[A.STALL_N].upward.cut or 0
	ok(cut > 0 or plans[A.STALL_N].maxEdges >= math.min(D.STALL_MAX_EDGES, math.ceil(base * D.STALL_INC_MUL)),
		"maxEdges " .. tostring(plans[A.STALL_N].maxEdges))
	ok(plans[1].maxEdges < plans[A.STALL_N].maxEdges, string.format("%s < %s", tostring(plans[1].maxEdges),
		tostring(plans[A.STALL_N].maxEdges)))
	local pl = logsWith(E, "PLAN")
	ok(pl[#pl]:find(" stall=1", 1, true), pl[#pl])
	ok(plans[1].stall == nil)
	end)
end)

test("street split (§65): mod / game / core edges, the game's share; STREETS line every STREETS_EVERY_S", function()
	local A = ug_require(F.DIR .. "ot_assess.lua")
	local sp = A.edgeSplit({ edges = 300, ownEdges = 100 }, 50)
	eq(sp.mod, 100); eq(sp.game, 150); eq(sp.core, 50)
	ok(math.abs(sp.share - 0.6) < 1e-9)
	eq(A.edgeSplit({ edges = 40, ownEdges = 0 }, 50).game, 0, "never below 0")
	eq(A.edgeSplit({ edges = 40, ownEdges = 0 }, 50).share, nil)
	eq(A.edgeSplit({ edges = 40, ownEdges = 5 }, nil).game, nil, "no core: unknown")
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	-- (the session's first check gives the core when no frame has one; the frame's e0 wins)
	local s1 = d:streetSplit(TOWN, { edges = 20, ownEdges = 0 }, nil)
	eq(s1.core, 20); eq(s1.game, 0)
	local s2 = d:streetSplit(TOWN, { edges = 50, ownEdges = 10 }, nil)
	eq(s2.core, 20); eq(s2.game, 20)
	local framed = SV.applyFrame(nil, { town = TOWN, a = 0, x = 0, y = 0, e0 = 12 })
	eq(d:streetSplit(TOWN, { edges = 50, ownEdges = 10 }, framed).game, 28)
	d:streetsNote(TOWN, { lots = { edges = 50 } }, s2, 0)
	eq(#logsWith(E, "STREETS"), 0, "not before the window")
	d:streetsNote(TOWN, { lots = { edges = 50 } }, s2, D.STREETS_EVERY_S * 1e6)
	local l = logsWith(E, "STREETS")[1]
	ok(l and l:find("towns=1 edges=50 modEdges=10 gameEdges=20 coreEdges=20 gameShare=0.67", 1, true), tostring(l))
end)

test("demand (§65): a young mod-locked town's lead floor is LOCK_LEAD_K x the legacy one, a grown town's unchanged", function()
	local A = ug_require(F.DIR .. "ot_assess.lua")
	local caps = { target = 2000, actual = 1000, sizeFactors = { 1.5, 1.5, 1.5 }, initials = { 400, 400, 400 } }
	local grown = { target = 8000, actual = 6000, sizeFactors = { 1.5, 1.5, 1.5 }, initials = { 1600, 1600, 1600 } }
	local lg = { edges = 50, length = 5000, free = 0, built = 300, open = 0, ownOpen = 0 }
	eq(A.demand({}, grown, lg, 2, 300, nil, 1.5).lead, A.demand({}, grown, lg, 2, 300, nil, nil).lead, "grown: the brake holds")
	local lots = { edges = 50, length = 5000, free = 0, built = 300, open = 0, ownOpen = 0 }
	local a = A.demand({}, caps, lots, 2, 300, nil, nil)
	local b = A.demand({}, caps, lots, 2, 300, nil, D.LOCK_LEAD_K)
	ok(b.lead > a.lead, string.format("%.1f > %.1f", b.lead, a.lead))
	ok(math.abs(b.lead - a.lead * D.LOCK_LEAD_K) < 1e-6)
	eq(A.demand({}, caps, lots, 2, 300, nil, 0.5).lead, a.lead, "never below the legacy floor")
end)

test("dosed fill: after a shaped town's build, FILL_POINTS DevelopAt beside its arm streets, back to back", function()
	local E = withDevelop(withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } })))
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local outcome
	-- the fake town's increment sits by the core: count every street as rim for this test
	local rim0 = D.LOCK_RIM
	D.LOCK_RIM = 0
	local job = shapedJob(E, d, { onDone = function(_j, o) outcome = o end })
	ok(E.pending ~= nil, "sent")
	E.pending.cb(true, { cost = 1, msgs = {} })
	d:advance(E.t, nil)
	D.LOCK_RIM = rim0
	local fl = logsWith(E, "FILL")[1]
	local nPts = math.min(D.FILL_POINTS, #job.spec.edges)
	ok(fl and fl:find("kind=dose", 1, true) and fl:find("points=" .. nPts, 1, true) and fl:find("near=", 1, true), tostring(fl))
	eq(job.stage, "fill")
	eq(outcome, nil, "the job runs on until the fill is answered")
	d:advance(E.t, nil)
	-- (Showcase v8 round, D.FILL_CONCURRENT: all of a build's DevelopAt calls go out at once, the job waits for all)
	eq(#E.develops, nPts, "all commands sent back to back")
	ok(d.inflight)
	eq(E.develops[1].streets, false)
	eq(E.develops[1].upgrade, false)
	for i = #E.develops, 1, -1 do
		d:advance(E.t, nil)
		eq(outcome, nil, "waits for every callback")
		E.develops[i].cb(true)   -- (answered out of order)
	end
	d:advance(E.t, nil)
	eq(outcome, "built")
	ok(not d.inflight)
	-- the points lie FILL_OFFSET beside arm / rim streets
	local sh = job.style.shape
	for _, p in ipairs(E.develops) do
		local best = math.huge
		for _, e in ipairs(job.spec.edges) do
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			best = math.min(best, math.sqrt((p.x - mx) ^ 2 + (p.y - my) ^ 2))
		end
		ok(math.abs(best - D.FILL_OFFSET) < 1.5, "beside a new street's midpoint: " .. best)
	end
	ok(sh ~= nil)
	-- the next check of the town logs where the growth went
	d:startJob(TOWN, E.t, { force = true, styleMode = "EU_EXTENSION", shape = "linear", dry = true })
	for _ = 1, 5 do d:advance(E.t, nil) end
	local fe = logsWith(E, "FILL effect")[1]
	ok(fe and fe:find("near=", 1, true) and fe:find("buildings=", 1, true) and fe:find("cap=", 1, true)
		and fe:find("sizeFactors=", 1, true), tostring(fe))
end)

test("fill decisions: off, unshaped, capacity cap, surge, metropolis from METRO_MIN_CAP, forced kinds", function()
	local shaped = { style = { shape = { id = "linear", centre = { 0, 0 } } } }
	local caps = { actual = 900, target = 1000 }
	eq(D.fillKind(shaped, {}, caps, nil, 200, 0), "dose")
	eq(D.fillKind({ style = {} }, {}, caps, nil, 200, 0), nil)
	eq(select(2, D.fillKind({ style = { shape = { id = "compact" } } }, {}, caps, nil, 200, 0)), "unshaped")
	-- the brake: DevelopAt raises the initial capacities; stop at FILL_CAP x the town's base (first build) only while a
	-- dose may raise them (FILL_EXTRA > 0); since 2026-10-14 the restore is exact, so a raised old save still doses
	eq(D.fillKind(shaped, {}, { actual = 900, target = 1000, initial = 1400 }, nil, 200, 0, 1000), "dose", "no boost: no cap")
	local fe0 = D.FILL_EXTRA
	D.FILL_EXTRA = 0.15
	eq(select(2, D.fillKind(shaped, {}, { actual = 900, target = 1000, initial = 1400 }, nil, 200, 0, 1000)), "cap")
	D.FILL_EXTRA = fe0
	eq(D.fillKind(shaped, {}, { actual = 900, target = 1000, initial = 1200 }, nil, 200, 0, 1000), "dose")
	eq(D.fillKind(shaped, {}, { actual = 9000, target = 1000, initial = 1400 }, nil, 200, 0, nil), "dose", "no base: no brake")
	local last = { us = 0, buildings0 = 100 }
	eq(select(2, D.fillKind(shaped, {}, caps, last, 130, 10e6)), "surge")
	eq(D.fillKind(shaped, {}, caps, last, 130, (D.FILL_SURGE_S + 1) * 1e6), "dose", "an old fill no longer blocks")
	eq(D.fillKind(shaped, {}, caps, last, 120, 10e6), "dose")
	-- the surge window is spread per town (D.FILL_SURGE_JITTER), so the doses of towns built together drift apart
	local wins, lo, hi = {}, math.huge, 0
	for t = 1, 40 do
		local w = D.surgeWindowS(t * 37 + 4000)
		wins[w] = true
		lo, hi = math.min(lo, w), math.max(hi, w)
	end
	ok(lo >= D.FILL_SURGE_S * (1 - D.FILL_SURGE_JITTER / 2) - 1e-6 and hi <= D.FILL_SURGE_S * (1 + D.FILL_SURGE_JITTER / 2) + 1e-6)
	ok(hi - lo > D.FILL_SURGE_S * D.FILL_SURGE_JITTER * 0.6, "spread: " .. lo .. ".." .. hi)
	eq(D.surgeWindowS(1234), D.surgeWindowS(1234), "deterministic")
	-- metropolis: a metropolis style (ot_metro, automatic; the old setting is ignored), no cap but METRO_MAX_CAP
	eq(D.fillKind({ style = { metro = { variant = "grid" } } }, {}, { actual = D.METRO_MIN_CAP, target = 100 }, nil, 900, 0), "metro")
	eq(D.fillKind({ style = {} }, { metropolis = true }, { actual = D.METRO_MIN_CAP, target = 9000 }, nil, 900, 0), nil,
		"an old Metropolis setting value does nothing")
	eq(D.fillKind({ style = {}, fill = "metro" }, {}, caps, nil, 10, 0), "metro", "forced (dev)")
	eq(select(2, D.fillKind({ style = {}, fill = "metro" }, {}, { actual = D.METRO_MAX_CAP, target = 1 }, nil, 10, 0)), "metroMax")
	eq(D.fillKind({ style = { metro = { variant = "grid" }, shape = shaped.style.shape }, fill = "off" }, {},
		{ actual = 9999, target = 1 }, nil, 10, 0), nil)
	-- the base is saved with the plan frame (ic); older frames load without
	local fp = SV.frameParam(5, { axis = 0.5, centre = { 1, 2 } }, nil, 1234.4)
	eq(fp.ic, 1234)
	local st = SV.applyFrame(SV.applyInit(nil, { known = {} }), fp)
	eq(SV.frame(st, 5).initial, 1234)
	eq(SV.frame(SV.normalize({ v = 1, known = {}, frames = { ["5"] = { a = 0, x = 1, y = 2 } } }), 5).initial, nil)
	eq(SV.frameParam(5, { axis = 0.5, centre = { 1, 2 } }, nil, nil).ic, nil)
	-- metro points: both sides of every street, at most METRO_POINTS
	local edges = {}
	for i = 1, 10 do edges[i] = { p0 = { i * 100, 0, 0 }, p1 = { i * 100 + 80, 0, 0 } } end
	local mp = D.fillPoints("metro", edges)
	eq(#mp, D.METRO_POINTS)
	eq(mp[1][1], 140); eq(mp[1][2], D.FILL_OFFSET); eq(mp[2][2], -D.FILL_OFFSET)
	-- dose points: only arm / rim streets, spread, sides alternating
	local sh = { id = "linear", centre = { 0, 0 }, axis = 0, arms = { 0, math.pi }, block = 100 }
	local dp = D.fillPoints("dose", edges, sh, nil, nil)
	eq(#dp, math.min(D.FILL_POINTS, 10))
	if #dp >= 2 then ok(dp[1][2] * dp[2][2] < 0, "sides alternate") end
	local off = D.fillPoints("dose", { { p0 = { 0, 600, 0 }, p1 = { 0, 680, 0 } } }, sh, nil, nil)
	eq(#off, 0, "a street across the arm, off the corridor: no dose")
end)

test("metropolis setting removed: an old param value is ignored; INIT logs lock / fill / metropolis=auto", function()
	local PA = ug_require(F.DIR .. "ot_params.lua")
	eq(PA.parse({}).metropolis, nil)
	eq(PA.parse({ metropolis = 2 }).metropolis, nil, "old saves' value: not read")
	ok(not PA.parse({ metropolis = 2 }).raw:find("metropolis", 1, true))
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2, metropolis = 2 } })
	local d = D.new(E)
	run(d, E, 3)
	local init = logsWith(E, "INIT")[1]
	ok(init and init:find("capsBoost=0", 1, true), tostring(init))
	ok(init and init:find("lock=steer lockLegacy=shape", 1, true) and init:find("fill=dose", 1, true)
		and init:find("metropolis=auto_from_", 1, true), tostring(init))
end)

test("fill restore: after a dose's DevelopAt the initial capacities go back to at most FILL_EXTRA above (FILL_CAP x base)", function()
	-- D.restoreCaps
	eq(D.restoreCaps({ 100, 100, 100 }, { 100, 100, 100 }, 300), nil, "nothing raised: no command")
	local l = D.restoreCaps({ 100, 100, 100 }, { 400, 90, 400 }, 300)
	eq(l, { math.floor(100 * (1 + D.FILL_EXTRA) + 0.5), 90, math.floor(100 * (1 + D.FILL_EXTRA) + 0.5) })
	-- (2026-10-14) no boost: back exactly to the pre-fill values, and nothing above them is ever lowered further
	eq(D.FILL_EXTRA, 0)
	eq(D.capsBoost(), 0, "no fill raises a town's capacities")
	eq(D.restoreCaps({ 120, 120, 120 }, { 400, 400, 400 }, 300), { 120, 120, 120 }, "exact restore")
	eq(D.restoreCaps({ 500, 500, 500 }, { 900, 900, 900 }, 300), { 500, 500, 500 }, "an old save's raised caps stay, rise no more")
	local near = D.restoreCaps({ 120, 120, 120 }, { 400, 400, 400 }, 300, 0.15)   -- base 300: cap 390 in all
	eq(near, { 130, 130, 130 }, "with a boost the FILL_CAP x base bound wins")
	eq(D.restoreCaps({ 150, 150, 150 }, { 400, 400, 400 }, 300), { 150, 150, 150 }, "never below before")
	-- in the driver: the fake DevelopAt resets the initial capacities to the town's capacity (as in game)
	local E = withDevelop(withArm(fakeEngine({ params = { act_on = 3, debug_log = 2 } })))
	local initials = { 250, 250, 250 }
	function E.townCaps(_t)
		local sum = initials[1] + initials[2] + initials[3]
		return { target = sum * 2, actual = 1500, sizeFactors = { 2, 2, 2 }, initial = sum, initials = { initials[1], initials[2], initials[3] } }
	end
	local dev = E.developAt
	function E.developAt(x, y, st, up, cb)
		initials = { 500, 500, 500 }
		return dev(x, y, st, up, cb)
	end
	E.restores = {}
	function E.setInitialCaps(t, list, cb) E.restores[#E.restores + 1] = { t = t, list = list }; initials = list; cb(true) end
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local rim0 = D.LOCK_RIM
	D.LOCK_RIM = 0
	local outcome
	shapedJob(E, d, { onDone = function(_j, o) outcome = o end })
	E.pending.cb(true, { cost = 1, msgs = {} })
	d:advance(E.t, nil)
	D.LOCK_RIM = rim0
	for _ = 1, 20 do
		if outcome then break end
		for _, dv in ipairs(E.develops) do
			if dv.cb then
				local cb = dv.cb
				dv.cb = nil
				cb(true)
			end
		end
		d:advance(E.t, nil)
	end
	eq(outcome, "built")
	eq(#E.restores, 1, "one restore after the dose")
	local want = math.floor(250 * (1 + D.FILL_EXTRA) + 0.5)
	eq(E.restores[1].list, { want, want, want })
	ok(logsWith(E, "FILL restore")[1]:find("initials=250,250,250->500,500,500->250,250,250", 1, true), logsWith(E, "FILL restore")[1])
	ok(logsWith(E, "FILL restore")[1]:find("capsBoost=0", 1, true), logsWith(E, "FILL restore")[1])
	ok(not d.inflight)
end)

test("metropolis: a forced variant reaches the style (METRO line), the frame keeps the town's own style", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local job = d:startJob(TOWN, E.t, { force = true, dry = true, styleMode = "EU_EXTENSION", metro = "polycentric",
		metroCentres = true })
	for _ = 1, 40 do
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	local m = logsWith(E, "METRO")[1]
	ok(m and m:find("variant=polycentric", 1, true) and m:find("centres=1", 1, true) and m:find("on=true", 1, true), tostring(m))
	ok(job.style.metro and job.style.metro.variant == "polycentric")
	eq(job.baseStyle.metro, nil)
	eq(job.style.shape.id, "twin")
	-- (Showcase v8 round) bigger increments, every street locked, the fill restored with the metropolis brake
	eq(job.maxEdges, D.METRO_MAX_EDGES)
	ok(logsWith(E, "PLAN")[1]:find("maxEdges=" .. D.METRO_MAX_EDGES, 1, true))
	local MET = ug_require(F.DIR .. "ot_metro.lua")
	local r = math.floor(100 * (1 + MET.FILL_EXTRA) + 0.5)
	eq(D.restoreCaps({ 100, 100, 100 }, { 400, 400, 90 }, nil, MET.FILL_EXTRA), { r, r, 90 }, "metro brake: no base cap")
	local st = logsWith(E, "METRO step")[1]
	ok(st and st:find("dens=core:", 1, true) and st:find("green=", 1, true), tostring(st))
	-- a small town without force: no metropolis (logged once, debug)
	local E2 = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d2 = D.new(E2)
	d2:loadConfig()
	d2.phase = "manual"
	local j2 = d2:startJob(TOWN, E2.t, { force = true, dry = true, styleMode = "EU_EXTENSION" })
	for _ = 1, 40 do
		if not d2:advance(E2.t, nil) then break end
		E2.t = E2.t + 100000
	end
	eq(j2.style.metro, nil)
	local no = logsWith(E2, "METRO")[1]
	ok(no and no:find("on=false", 1, true) and no:find("why=small", 1, true), tostring(no))
end)

test("away from industries: ind= on CHECK / STYLE, indPen= on PLAN, unknown names logged once; none = no field change", function()
	local E = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" },
		params = { act_on = 3, debug_log = 2 } })
	local reads = 0
	function E.industries()
		reads = reads + 1
		return { { 450, 0, file = "industries/steel_mill/steel_mill.con" }, { 600, 100, file = "some_mod/industries/widget.con" },
			{ 5000, 0, file = "industries/farm/farm.con" } }
	end
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	for _ = 1, 2 do
		local job = d:startJob(TOWN, E.t, { force = true, dry = true })
		for _ = 1, 40 do
			if not d:advance(E.t, nil) then break end
			E.t = E.t + 100000
		end
		ok(job.style.industry ~= nil, "plan style carries the industry info")
	end
	eq(reads, 1, "the map's industry list is read once per refresh")
	local check = logsWith(E, "CHECK")[1]
	ok(check and check:find("ind=2/450/1", 1, true), tostring(check))
	ok(logsWith(E, "STYLE")[1]:find("ind=2/450/1", 1, true), logsWith(E, "STYLE")[1])
	local plan = logsWith(E, "PLAN")[1]
	ok(plan and plan:find("indPen=0.", 1, true) or plan:find("indPen=1.", 1, true), tostring(plan))
	eq(#logsWith(E, "IND unknown"), 1, "unknown file logged once")
	-- without E.industries (or none near): ind=0, indPen=-
	local E2 = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" },
		params = { act_on = 3, debug_log = 2 } })
	local d2 = D.new(E2)
	d2:loadConfig()
	d2.phase = "manual"
	local job2 = d2:startJob(TOWN, E2.t, { force = true, dry = true })
	for _ = 1, 40 do
		if not d2:advance(E2.t, nil) then break end
		E2.t = E2.t + 100000
	end
	eq(job2.style.industry, nil)
	ok(logsWith(E2, "CHECK")[1]:find("ind=0", 1, true))
	ok(logsWith(E2, "PLAN")[1]:find("indPen=-", 1, true))
end)

test("away from player facilities: FAC debug line, fac= on PLAN, soft info only, re-read keeps the version unless changed", function()
	local E = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" },
		params = { act_on = 3, debug_log = 2 } })
	local reads, list = 0, nil
	list = { { 400, 0, file = "stations/water/harbor_modular.con", cargo = true, passenger = false },
		{ -300, 0, file = "stations/rail/modular_station/modular_station.con", passenger = true } }
	function E.facilities()
		reads = reads + 1
		return list
	end
	local d = D.new(E)
	d:loadConfig()
	d.phase = "manual"
	local job = d:startJob(TOWN, E.t, { force = true, dry = true })
	for _ = 1, 40 do
		if not d:advance(E.t, nil) then break end
		E.t = E.t + 100000
	end
	local ind = job.style.industry
	ok(ind ~= nil and ind.fac == 1 and ind.n == 0 and #ind.zones == 0, "harbor only, soft, no zone")
	local fl = logsWith(E, "FAC")[1]
	ok(fl and fl:find("facilities=1", 1, true) and fl:find("port=1", 1, true), tostring(fl))
	local plan = logsWith(E, "PLAN")[1]
	ok(plan and plan:find("fac=1:1/0/0/0/0", 1, true) and plan:find("zones=-", 1, true), tostring(plan))
	ok(plan:find("indHeld=0", 1, true) or not plan:find("indHeld=", 1, true), "never held")
	local v = d.facVer
	d:facilitiesRead(E.t + (D.FAC_REFRESH_S + 1) * 1e6)
	eq(reads, 2, "re-read after FAC_REFRESH_S")
	eq(d.facVer, v, "same list: same version")
	list = { list[1], { -500, 0, file = "depots/road/road_depot/road_depot.con", depot = true } }
	d:facilitiesRead(E.t + (2 * D.FAC_REFRESH_S + 2) * 1e6)
	eq(d.facVer, v + 1, "a new depot: new version")
	eq(#logsWith(E, "FAC"), 2)
end)

-- Upward density (ot_upward, later-ideas phase 2026-10-13)
local UP = ug_require(F.DIR .. "ot_upward.lua")
local OGu = ug_require(F.DIR .. "ot_graph.lua")

test("upward: who (big / pressure, not metro / forced, gap, cap, surge), the cut, held plans", function()
	eq(UP.decide({ buildings = 1000 }), nil, "small")
	eq(select(2, UP.decide({ buildings = 1000 })), "small")
	eq(UP.decide({ buildings = 1600 }), "big")
	eq(UP.decide({ buildings = 800, pressure = UP.PRESSURE_PLANS }), "pressure")
	eq(UP.decide({ buildings = 600, pressure = 9 }), nil, "too small even under pressure")
	eq(UP.decide({ buildings = 5000, metro = true }), nil, "metropolis: its own fill")
	eq(UP.decide({ buildings = 5000, forced = true }), nil, "forced / dev jobs: none")
	eq(UP.decide({ buildings = 5000, head = true }), nil, "head start: none")
	local why, skip, anyway = UP.decide({ buildings = 5000, town = 3, last = { us = 0 }, nowUs = 10e6 })
	eq(why, nil); eq(skip, "gap"); eq(anyway, "big", "still an upward town (the cut applies)")
	eq(UP.decide({ buildings = 5000, town = 3, last = { us = 0 }, nowUs = (UP.gapS(3) + 1) * 1e6 }), "big", "after the gap")
	eq(select(2, UP.decide({ buildings = 5000, initial = 2000, base = 1000 })), "cap", "above CAP_K x base: none")
	-- (2026-10-14 late: the surge rule no longer holds an upward dose, its restore is exact; was "surge")
	eq(UP.decide({ buildings = 5000, surge = true }), "big", "a fill's surge: upward anyway")
	UP.SURGE_BLOCKS = true
	eq(select(2, UP.decide({ buildings = 5000, surge = true })), "surge")
	UP.SURGE_BLOCKS = false
	ok(UP.gapS(1) >= 0.75 * UP.GAP_S and UP.gapS(1) <= 1.25 * UP.GAP_S)
	eq(UP.cut(1000), 0)
	eq(UP.cut(UP.MIN_BUILDINGS), UP.CUT[1])
	eq(UP.cut(UP.CUT_FULL), UP.CUT[2])
	eq(UP.cut(800, "pressure"), UP.CUT[1])
	ok(UP.held(18, 0, nil), "empty: held")
	ok(not UP.held(18, 12, { housedHeld = 4 }), "most of the ask: not held")
	ok(UP.held(18, 4, { wedgeHeld = 2 }), "a small increment with holds: held")
	ok(not UP.held(18, 4, {}), "a small increment without holds (little demand): not held")
	ok(UP.held(18, 4, { ownEmptyCap = 0 }), "own empty budget spent: held")
	-- the restore after an upward dose allows nothing (EXTRA 0): the town's target stays
	eq(D.restoreCaps({ 300, 200, 100 }, { 900, 800, 700 }, nil, UP.EXTRA), { 300, 200, 100 })
	eq(D.restoreCaps({ 300, 200, 100 }, { 300, 200, 100 }, nil, UP.EXTRA), nil, "nothing raised: no command")
end)

test("upward: points in the core, along main streets where houses stand, spaced, off industry buffers", function()
	-- a 9 x 9 grid of 80 m blocks, the middle row and column main streets, houses everywhere within 300 m
	local g = OGu.new()
	local id = {}
	for i = -4, 4 do
		id[i] = {}
		for j = -4, 4 do id[i][j] = OGu.addNode(g, nil, i * 80, j * 80, 20).id end
	end
	for i = -4, 4 do
		for j = -4, 4 do
			if i < 4 then OGu.addEdge(g, nil, id[i][j], id[i + 1][j], j == 0 and "main" or "small") end
			if j < 4 then OGu.addEdge(g, nil, id[i][j], id[i][j + 1], i == 0 and "main" or "small") end
		end
	end
	local pts = {}
	for x = -300, 300, 20 do
		for y = -300, 300, 20 do pts[#pts + 1] = { x, y } end
	end
	local coreR = UP.coreR(700)
	eq(coreR, UP.CORE_K * 700)
	local list = UP.points(g, pts, { 0, 0 }, coreR)
	eq(#list, UP.POINTS)
	for i, p in ipairs(list) do
		ok(math.sqrt(p[1] ^ 2 + p[2] ^ 2) <= coreR + UP.OFFSET + 1, "in the core")
		ok(p.n >= UP.MIN_HOUSES, "houses stand there")
		eq(p.class, "main", "along a main street first")
		for j = 1, i - 1 do ok(F_dist(list[j], p[1], p[2]) >= UP.SPACING, "spaced") end
	end
	-- the next dose keeps off the last points
	local recent = UP.remember(nil, list)
	local again = UP.points(g, pts, { 0, 0 }, coreR, { recent = recent })
	for _, p in ipairs(again) do
		for _, q in ipairs(recent) do ok(F_dist(q, p[1], p[2]) >= UP.SPACING, "away from the last dose") end
	end
	-- no houses: no point; a skip function (industry buffer) drops points
	eq(#UP.points(g, {}, { 0, 0 }, coreR), 0)
	local none = UP.points(g, pts, { 0, 0 }, coreR, { skip = function() return true end })
	eq(#none, 0)
end)

test("upward (driver): a big town's demand build is cut, then DevelopAt(upgrade) in its core and an exact restore", function()
	local E = withDevelop(fakeEngine({ params = { act_on = 3, debug_log = 2 } }))
	local initials = { 400, 300, 100 }
	function E.townCaps(_t)
		local sum = initials[1] + initials[2] + initials[3]
		return { target = sum * 3, actual = 1500, sizeFactors = { 3, 3, 3 }, initial = sum,
			initials = { initials[1], initials[2], initials[3] }, active = true }
	end
	local dev = E.developAt
	function E.developAt(x, y, st, up, cb)
		initials = { 700, 600, 500 }   -- (DevelopAt resets them to the town's size, as in game)
		return dev(x, y, st, up, cb)
	end
	E.restores = {}
	function E.setInitialCaps(t, list, cb) E.restores[#E.restores + 1] = { t = t, list = list }; initials = list; cb(true) end
	local min0, gap0 = UP.MIN_BUILDINGS, UP.GAP_S
	UP.MIN_BUILDINGS = 20   -- (the fake town has 49 buildings)
	local d = D.new(E)
	local okRun, err = pcall(function()
		ok(run(d, E, 400, nil, function() return E.pending ~= nil end), "a proposal was sent")
		local plan = logsWith(E, "PLAN")
		local last = plan[#plan]
		local check = logsWith(E, "CHECK")[1]
		if check:find("why=demand", 1, true) then
			ok(last:find("upCut=big:", 1, true), last)
		end
		E.pending.cb(true, { cost = 1, msgs = {} })
		local job = d.job
		run(d, E, 3)
		ok(job ~= nil, "the job")
		do
			ok(#E.develops >= 1, "upward DevelopAt calls")
			for _, dv in ipairs(E.develops) do
				eq(dv.streets, false, "no streets")
				eq(dv.upgrade, true, "upgrade buildings")
				if dv.cb then local cb = dv.cb; dv.cb = nil; cb(true) end
			end
			run(d, E, 5)
			eq(#E.restores, 1, "one restore")
			eq(E.restores[1].list, { 400, 300, 100 }, "the initial capacities exactly as before (no runaway)")
			local up = logsWith(E, "UPWARD")
			ok(#up >= 1 and up[1]:find("why=big", 1, true) and up[1]:find("after=built", 1, true), up[1])
			ok(not d.inflight)
		end
	end)
	UP.MIN_BUILDINGS, UP.GAP_S = min0, gap0
	assert(okRun, err)
end)

-- Tree-lined entries (ot_entry, later-ideas phase 2026-10-13)
local EN = ug_require(F.DIR .. "ot_entry.lua")

test("entry (driver): ENTRY once per town; a pre-check refused with tree-lined edges goes out again without them", function()
	local E = fakeEngine()
	local mark0, on0 = EN.mark, EN.ON
	EN.ON = true   -- (off by default since 2026-10-18: plain streets only)
	-- (the fake town has no country roads: every planned edge with a trees variant is flagged)
	EN.mark = function(inc)
		local n = 0
		for _, e in ipairs(inc.edges) do
			if EN.treesPath(e.template) then e.trees = true; n = n + 1 end
		end
		inc.trees = n > 0 and n or nil
		return n
	end
	E.precheckOk = function(spec)
		for _, e in ipairs(spec.edges) do if e.decor == "template" then return false end end
		return true
	end
	local d = D.new(E)
	local okRun, err = pcall(function()
		ok(run(d, E, 400, nil, function() return E.pending ~= nil end), "a proposal was sent")
		local entry = logsWith(E, "ENTRY")
		ok(#entry >= 2, "ENTRY town line + refused line")
		ok(entry[1]:find("on=", 1, true), entry[1])
		local refused = {}
		for _, l in ipairs(entry) do if l:find("outcome=refused", 1, true) then refused[#refused + 1] = l end end
		eq(#refused, 1, "one refusal with trees")
		ok(refused[1]:find("off=false", 1, true), refused[1])
		for _, e in ipairs(E.pending.spec.edges) do ok(e.decor ~= "template", "sent without trees") end
		ok(E.prechecks[1] ~= nil and #E.prechecks >= 2)
	end)
	EN.mark, EN.ON = mark0, on0
	assert(okRun, err)
	-- trees off: entryMark leaves increments plain
	local d2 = D.new(E)
	d2.treesOff = true
	local inc = { edges = { { template = "::/infrastructure/street/town/town_old_small.street_template", p0 = { 0, 0 }, p1 = { 100, 0 } } } }
	d2:entryMark({ town = TOWN, style = { roads = { roads = {} } } }, inc)
	eq(inc.trees, nil)
end)

-- Hang guard (2026-10-13, real map run 2026-10-13_1848_sqot: Henley-on-Thames' head-start round 2 froze the Main Thread
-- after its SNAPSHOT line until the game's watchdog killed it). A plan that never ends is stopped by the count hook on the
-- plan coroutine: WARN planHang with the Lua trace, the town finishes "fail" (no second try in one go), the driver goes on.
local core = ug_require(F.DIR .. "ot_core.lua")

test("hang guard: an endless plan ends as WARN planHang + fail, the driver goes on", function()
	local E = fakeEngine()
	E.nowUs = function() return math.floor(os.clock() * 1e6) end
	local saved = { core.planIncrement, D.PLAN_HANG_US, D.PLAN_TOTAL_US }
	local calls = 0
	core.planIncrement = function(g, style, opts)
		calls = calls + 1
		if opts.yield then opts.yield() end
		local x = 0
		while true do x = x + 1 end   -- the endless loop: no yield, no exit
	end
	D.PLAN_HANG_US, D.PLAN_TOTAL_US = 50000, 200000
	local d = D.new(E)
	local okRun, err = pcall(run, d, E, 120, nil, function() return #logsWith(E, "WARN") > 0 and d.job == nil end)
	core.planIncrement, D.PLAN_HANG_US, D.PLAN_TOTAL_US = saved[1], saved[2], saved[3]
	ok(okRun, tostring(err))
	local warn = logsWith(E, "WARN")
	ok(#warn >= 1, "a WARN line")
	ok(warn[1]:find("stage=plan", 1, true) and warn[1]:find("msg=planHang", 1, true), warn[1])
	ok(warn[1]:find("test_driver.lua", 1, true), "the trace names the looping file: " .. warn[1])
	print("      " .. warn[1])
	eq(calls, 1, "planned once: no second try in one go")
	eq(d.job, nil, "the job finished")
	eq(E.pending, nil, "nothing sent")
end)

test("hang guard: D.guard ends an endless one-go call (the other stages) with a planHang error", function()
	local now = function() return math.floor(os.clock() * 1e6) end
	local okG, err = D.guard(now, 30000, function() local x = 0; while true do x = x + 1 end end)
	eq(okG, false)
	ok(D.isHang(err), tostring(err))
	-- a call that ends returns its results; the hook is gone afterwards
	local ok2, a, b = D.guard(now, 30000, function(p, q) return p + q, "x" end, 2, 3)
	eq(ok2, true); eq(a, 5); eq(b, "x")
	eq(debug.gethook(), nil)
end)

test("hang guard: D.traceText reads both chunk name forms, innermost mod frames first", function()
	local tb = "stack traceback:\n\t[string \"square_organic_towns::/organic_towns/ot_select.lua\"]:1725: in upvalue 'withTips'\n"
		.. "\tsquare_organic_towns::/organic_towns/ot_core.lua:500: in function <x>\n\tot_driver.lua:12: in function 'foo'\n"
	local t = D.traceText(tb)
	ok(t:find("^ot_select.lua:1725<withTips|ot_core.lua:500"), t)
	eq(D.traceText(nil), "-")
end)

test("R1 CHECK: slow reads split the check over two ticks (slices=2), the result as in one tick", function()
	local function checkLine(split)
		local E = fakeEngine()
		for _, e in ipairs(E.W.edges) do e.built = 2 end
		local old = D.CHECK_SPLIT_US
		D.CHECK_SPLIT_US = split
		local d = D.new(E)
		-- (each street read costs 20 ms of fake time: the reads cross CHECK_SPLIT_US)
		local streets = E.streets
		E.streets = function(...) E.t = E.t + 20000; return streets(...) end
		run(d, E, 100)
		D.CHECK_SPLIT_US = old
		return logsWith(E, "CHECK")[1], d
	end
	local one = checkLine(nil)
	local two, d = checkLine(12000)
	ok(one and one:find("slices=1", 1, true), tostring(one))
	ok(two and two:find("slices=2", 1, true), tostring(two))
	ok(two:find("sliceUs=", 1, true))
	ok(two:find("needsRoom=false", 1, true) and one:find("needsRoom=false", 1, true), "same result")
	eq(d.counts.checks >= 1, true)
end)

test("R4 retire: an own dead end without a house for more than RETIRE_CHECKS snapshots is not extended", function()
	local E = fakeEngine()
	local d = D.new(E)
	local W = E.W
	local de = W.deadEnds.east
	local eid
	for _, e in ipairs(W.edges) do if e.n0 == de or e.n1 == de then eid = e.id end end
	local s = d:townState(TOWN)
	s.own = { [eid] = true }
	local function snap(built)
		local edges, builtBy = {}, {}
		for _, e in ipairs(W.edges) do edges[#edges + 1] = e; builtBy[e.id] = e.id == eid and built or 5 end
		local g, joinInfo, _, why = d:snapshotGraph({ town = TOWN, edges = edges, builtBy = builtBy })
		return joinInfo, why, g
	end
	for _ = 1, D.RETIRE_CHECKS do
		local ji = snap(0)
		ok(ji[de] ~= nil, "still joinable")
	end
	local ji, why, g = snap(0)
	eq(ji[de], nil, "retired")
	ok(why:find("retired:1", 1, true), why)
	eq(s.retired, 1)
	-- (§74 2026-10-18) still closable by a near-miss join: marked nmRetired, its join info kept aside for retiredJoinOk
	ok(g.nodeById[de].noJoin and g.nodeById[de].nmRetired, "nmRetired")
	local job = { g = g }
	eq(d:retiredJoinOk(job, de), true)
	eq(job.nmInfo[de].src, eid)
	eq(d:retiredJoinOk(job, W.deadEnds.west or -1), false, "not retired: not this path")
	-- a house on it: back in play
	ji = snap(2)
	ok(ji[de] ~= nil, "a house: joinable again")
	eq(s.retired, 0)
end)

test("headEnd: the dev simulation's start cuts the head start at once (HEAD done cut= left=); no head: 0", function()
	local E = fakeEngine({ cfg = { nameList = "::/names/germany/germany.names", climate = "temperate" } })
	local d = D.new(E)
	eq(d:headEnd("simgrow"), 0)
	d.head = { queue = { {}, {}, {}, {}, {} }, i = 2, built = 1, edges = 12, skipped = 0, forms = {} }
	eq(d:headEnd("simgrow"), 3)
	eq(d.head, nil)
	local done = logsWith(E, "HEAD done")
	eq(#done, 1)
	ok(done[1]:find("cut=simgrow", 1, true) and done[1]:find("left=3", 1, true), done[1])
end)

-- Frame cost (2026-10-14, real-play prep): Driver:costNote sums the game script's tick timings into one TICKCOST line
-- per window; nothing while the mod is off; bad timings (NaN, negative) count as 0.
test("TICKCOST: one line per window with the slowest tick's stage, none while off, NaN-safe", function()
	local E = { logs = {} }
	function E.log(l) E.logs[#E.logs + 1] = l end
	local d = D.new(E)
	d.phase = "run"
	local W = D.COST_EVERY_S * 1e6
	eq(d:costStage(), "idle")
	ok(d:costNote(0, 1000, 100, "idle") == nil)
	ok(d:costNote(1e6, 20000, 300, "job:plan") == nil)
	ok(d:costNote(2e6, 0 / 0, -5, "idle") == nil)
	ok(d:costNote(3e6, 60000, 50, "names:assign") == nil)
	local l = d:costNote(W + 1, 2000, 10, "idle")
	ok(l, "line at the window's end")
	for _, part in ipairs({ "TICKCOST", "ticks=5", "maxUs=60000", "at=names:assign", "getMaxUs=300", "over4ms=2",
		"over16ms=2", "over50ms=1", "avgUs=16600" }) do
		ok(l:find(part, 1, true), part .. " in " .. l)
	end
	eq(#E.logs, 1)
	ok(d:costNote(W + 2, 1000, 0, "idle") == nil, "a new window starts")
	d.phase = "off"
	ok(d:costNote(3 * W, 1000, 0, "idle") == nil, "off: nothing")
	eq(#E.logs, 1)
	d.phase = "run"
	d.job = { stage = "assess" }
	eq(d:costStage(), "job:assess")
	d.names = { phase = "survey" }
	eq(d:costStage(), "names:survey")
	d.charPhase = {}
	eq(d:costStage(), "chars")
end)

-- Pause and refunds (2026-10-17, player report: roads built while paused; a $0 start plunged into the red). The driver's
-- clock is running time (paused stretches left out); a paused tick starts nothing but handles a callback that came;
-- every build's charge is booked back (min(balance drop, cost), ot_glock.refund).

--- A fake engine whose builds charge `charge` when their callback comes and whose refund bookings land at once.
--- A fake engine whose builds are charged: the player is in the context (hooks.player = true, the dev toggle).
local function payingEngine(o)
	local E = fakeEngine(o)
	D.hooks.player = true
	E.booked = {}
	function E.bookStreetRefund(a, cb)
		E.booked[#E.booked + 1] = a
		E.bal = E.bal + a
		if cb then cb(true) end
		return true
	end
	return E
end

--- Delivers the pending build's callback: the build charges `charge`, reports `cost`.
local function answer(E, charge, cost)
	local p = E.pending
	E.pending = nil
	E.bal = E.bal - charge
	p.cb(true, { cost = cost, msgs = {} })
end

test("pause: a paused game starts nothing (no init, check or build); one PAUSE line per change; running time resumes", function()
	local E = payingEngine()
	E.speed = 0
	local d = D.new(E)
	run(d, E, 400)
	eq(d.phase, "init", "no init while paused")
	eq(#E.events, 0)
	eq(#E.prechecks, 0)
	eq(E.pending, nil)
	eq(#logsWith(E, "PAUSE state=on"), 1)
	eq(d.pausedUs, 399 * 100000, "every paused tick's time left out (not the first: no previous tick)")
	eq(d:nowUs(), E.t - d.pausedUs)
	E.speed = 1
	ok(run(d, E, 400, nil, function() return E.pending ~= nil end), "builds once running")
	eq(#logsWith(E, "PAUSE state=off"), 1)
	eq(#logsWith(E, "PAUSE"), 2)
	-- unreadable speed (no accessor / an error / nil): running
	local E2 = fakeEngine()
	E2.gameSpeed = nil
	local d2 = D.new(E2)
	ok(run(d2, E2, 400, nil, function() return E2.pending ~= nil end))
	local E3 = fakeEngine()
	function E3.gameSpeed() error("no world") end
	local d3 = D.new(E3)
	ok(run(d3, E3, 400, nil, function() return E3.pending ~= nil end))
	eq(#logsWith(E3, "PAUSE"), 0)
	-- paused mid-run, between jobs: no check, no new job, no send
	E.pending = nil
	local pre = #E.prechecks
	E.speed = 0
	d.job, d.inflight, d.nextUs = nil, false, 0
	run(d, E, 300)
	eq(#E.prechecks, pre)
	eq(d.job, nil)
	eq(E.pending, nil)
end)

test("pause: the head start does not advance while paused; on resume it waits its gap in running time", function()
	local E = fakeEngine()
	function E.towns() return {} end   -- (no regular check beside the head start)
	local d = D.new(E)
	d:loadConfig()
	d.phase = "run"
	d.head = { queue = { { town = TOWN, round = 1 } }, i = 0, nextUs = E.t + D.HEAD_GAP_S * 1e6, built = 0, edges = 0,
		skipped = 0, forms = {}, scale = { rounds = 0, edgesMul = 1 } }
	E.speed = 0
	run(d, E, 600)   -- a minute paused
	eq(d.head.i, 0)
	eq(d.job, nil)
	eq(#E.prechecks, 0)
	E.speed = 1
	local ticks = 0
	for _ = 1, 100 do
		d:tick(E.t, nil)
		E.t = E.t + 100000
		ticks = ticks + 1
		if d.head == nil or d.head.i > 0 then break end
	end
	ok(d.head == nil or d.head.i == 1, "the head start's first job started")
	ok(ticks >= D.HEAD_GAP_S * 10 - 1, "not at once on unpause: after its gap of running time (" .. ticks .. " ticks)")
	ok(ticks <= D.HEAD_GAP_S * 10 + 2, ticks)
end)

test("pause: a build's callback that comes while paused is handled (BUILT, refund); its timeout doesn't run", function()
	local E = payingEngine()
	local d = D.new(E)
	ok(run(d, E, 400, nil, function() return E.pending ~= nil end))
	E.speed = 0
	run(d, E, 2 * D.WAIT_TIMEOUT_S * 10)   -- paused for twice the callback timeout
	eq(#logsWith(E, "FAILED"), 0, "no timeout while paused")
	eq(d.job.stage, "wait")
	answer(E, 2000, 2000)
	run(d, E, 2)
	eq(#logsWith(E, "BUILT"), 1, "handled while paused")
	eq(#E.booked, 1)
	eq(E.booked[1], 2000)
	eq(E.bal, 5000000, "the balance is back where it was")
	-- nothing new while still paused
	run(d, E, 300)
	eq(E.pending, nil)
	eq(#logsWith(E, "SEND"), 1)
end)

test("refund: every build books min(balance drop, cost) (REFUND line, STREETS total); none without a charge", function()
	local cases = {
		{ charge = 2000, cost = 2000, want = 2000 },
		{ charge = 1500, cost = 2000, want = 1500 },   -- paid less: what was paid
		{ charge = 2600, cost = 2000, want = 2000 },   -- other spending in the same frames: the cost at most
		{ charge = 0, cost = 2000, want = 0 },         -- not charged
		{ charge = 2000, cost = 0, want = 1234 },      -- no cost in the result: the pre-check's (1234), capped by it
	}
	for _, c in ipairs(cases) do
		local E = payingEngine()
		local d = D.new(E)
		ok(run(d, E, 400, nil, function() return E.pending ~= nil end))
		answer(E, c.charge, c.cost)
		run(d, E, 2)
		local got = 0
		for _, a in ipairs(E.booked) do got = got + a end
		eq(got, c.want, "charge " .. c.charge .. " cost " .. c.cost)
		eq(#E.booked, c.want > 0 and 1 or 0)
		local rl = logsWith(E, "REFUND kind=build")
		eq(#rl, 1)
		ok(rl[1]:find("amount=" .. c.want, 1, true), rl[1])
		eq(d.refundSum or 0, c.want)
	end
	-- the head start's jobs go the same way
	local E = payingEngine()
	local d = D.new(E)
	d:loadConfig()
	d.phase = "run"
	d.head = { queue = { { town = TOWN, round = 1 } }, i = 0, nextUs = 0, built = 0, edges = 0, skipped = 0, forms = {},
		scale = { rounds = 0, edgesMul = 1 } }
	ok(run(d, E, 400, nil, function() return E.pending ~= nil end))
	ok(d.job and d.job.limits and d.job.limits.headForm, "a head-start job")
	answer(E, 900, 900)
	run(d, E, 2)
	eq(E.booked[1], 900)
	-- no player set (the default): not charged, nothing booked
	local H = ug_require(F.DIR .. "ot_hooks.lua")
	local E2 = payingEngine()
	H.player = nil
	local d2 = D.new(E2)
	ok(run(d2, E2, 400, nil, function() return E2.pending ~= nil end))
	answer(E2, 2000, 2000)
	run(d2, E2, 2)
	H.player = true
	eq(#E2.booked, 0)
	-- infinite money (no balance): nothing booked
	local E3 = payingEngine()
	function E3.balance() return nil end
	local d3 = D.new(E3)
	ok(run(d3, E3, 400, nil, function() return E3.pending ~= nil end))
	answer(E3, 2000, 2000)
	run(d3, E3, 2)
	eq(#E3.booked, 0)
end)

test("refund: every sendBuild in the driver records the balance at the send (one refunded window per build)", function()
	local fh = assert(io.open(here .. "../../mods/square_organic_towns/content/organic_towns/ot_driver.lua", "r"))
	local src = fh:read("*a")
	fh:close()
	local n, refunded = 0, 0
	local pos = 1
	for _ = 1, 50 do
		local a = src:find("E.sendBuild(", pos, true)
		if a == nil then break end
		n = n + 1
		local before = src:sub(math.max(1, a - 400), a)
		if before:find("refundBal0 = asPlayer and self:balanceAtSend(now)", 1, true)
			or before:find("bal0 = H.player == true and self:balanceAtSend(now)", 1, true) then refunded = refunded + 1 end
		pos = a + 1
	end
	eq(n, 2, "the growth / head-start / satellite / lead / Works / bridge / frame send and the lock send")
	eq(refunded, n)
end)

test("refund: a booking in flight counts into the next send's balance; a build is refunded once", function()
	local E = payingEngine()
	local d = D.new(E)
	E.bal = 1000
	d.refundsPending = { { amount = 500, us = 0 } }
	eq(d:balanceAtSend(0), 1500, "the booking not yet landed")
	eq(d:balanceAtSend((D.REFUND_PENDING_S + 1) * 1e6), 1000, "a booking whose callback never came stops counting")
	d.refundsPending = { { amount = 500, us = 0, done = true } }
	eq(d:balanceAtSend(0), 1000, "landed")
	-- the same job's refund booked once, however often it is asked
	local job = { town = TOWN, refundBal0 = 1000, result = { info = { cost = 400 } }, pre = { cost = 400 } }
	E.bal = 600
	d:buildRefund(job, 0)
	d:buildRefund(job, 0)
	eq(#E.booked, 1)
	eq(E.booked[1], 400)
end)

test("near-miss joins (§74): a stub ending 25 m short of a street becomes a T; the node's config in the spec, PLAN nearMiss=", function()
	local NMISS = ug_require(F.DIR .. "ot_nearmiss.lua")
	local pn, pf = NMISS.P_NEAR, NMISS.P_FAR
	NMISS.P_NEAR, NMISS.P_FAR = 1.01, 1.01
	local okT, errT = pcall(function()
		local E = fakeEngine()
		local W = E.W
		-- the east stub carried on to (300, 0): its old dead end (200, 0) becomes a street node; a stub from (100, 100) east
		-- then south ends at (200, 25), pointing at it
		local function node(id, x, y) W.nodes[id] = { id = id, x = x, y = y, z = 10, cfg = true } end
		local function edge(id, a, b)
			local na, nb = W.nodes[a], W.nodes[b]
			W.edges[#W.edges + 1] = { id = id, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
				t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
				objects = 0, owned = false, inConstruction = false, parcels = 10, built = 10 }
		end
		local mid = W.deadEnds.east
		node(301, 300, 0); edge(901, mid, 301)
		local corner = nil
		for id, n in pairs(W.nodes) do if n.x == 100 and n.y == 100 then corner = id end end
		node(302, 200, 100); edge(902, corner, 302)
		node(303, 200, 25); edge(903, 302, 303)
		function E.nodeSegmentCount(n) return #E.nodeStreetEdges(n) end
		local d = D.new(E)
		local sent = run(d, E, 400, nil, function() return E.pending ~= nil end)
		ok(sent, "sent")
		local plan = logsWith(E, "PLAN")[1]
		ok(plan and plan:find("nearMiss=", 1, true), tostring(plan))
		local key = "nm:303:" .. mid
		local join = nil
		for _, e in ipairs(E.pending.spec.edges) do if e.key == key then join = e end end
		if join == nil then
			-- (the grower may have used the stub itself: then the pass names it `inc`)
			ok(plan:find("nmKept=[^ ]*inc", 1) or plan:find("nmKept=[^ ]*taken", 1), plan)
			return
		end
		ok(plan:find("nmJoins=tee:25", 1, true), plan)
		local cfg = nil
		for _, c in ipairs(E.pending.spec.cfgAdd) do if c.node == mid then cfg = c end end
		ok(cfg ~= nil, "the street node's config rewritten")
		eq(#cfg.conns, 6, "three segments: one connection per ordered pair")
		local rm = false
		for _, n in ipairs(E.pending.spec.cfgRemove) do if n == mid then rm = true end end
		ok(rm, "its old config removed first (it has one)")
		-- built: counted for STREETS
		E.pending.cb(true, { cost = 1, msgs = {} })
		d:advance(E.t, nil)
		eq(d.towns[TOWN].nearMissBuilt, 1)
		-- the driver's street-node rule: a config, all segments plain town streets in the snapshot, no track, this town
		local OG = ug_require(F.DIR .. "ot_graph.lua")
		local snap = { nodes = {}, edges = {} }
		for id, n in pairs(W.nodes) do snap.nodes[#snap.nodes + 1] = { id = id, x = n.x, y = n.y, z = n.z } end
		for _, e in ipairs(W.edges) do snap.edges[#snap.edges + 1] = { id = e.id, node0 = e.n0, node1 = e.n1 } end
		local job = { g = OG.fromSnapshot(snap), town = TOWN, edges = W.edges }
		eq(d:midJoinOk(job, 302), true)
		eq(job.nmInfo[302].src ~= nil and #job.nmInfo[302].edges, 2)
		W.nodes[302].cfg = false
		job.nmInfo = nil
		eq(d:midJoinOk(job, 302), false, "no config")
		W.nodes[302].cfg = true
		function E.nodeSegmentCount(_n) return 3 end
		eq(d:midJoinOk(job, 302), false, "a track at the node")
		function E.nodeSegmentCount(n) return #E.nodeStreetEdges(n) end
		W.edges[#W.edges].owned = true
		eq(d:midJoinOk(job, 302), false, "a player-owned street at it")
		W.edges[#W.edges].owned = false
		function E.closestTown(_x, _y) return TOWN + 1 end
		eq(d:midJoinOk(job, 302), false, "another town's")
	end)
	NMISS.P_NEAR, NMISS.P_FAR = pn, pf
	assert(okT, errT)
end)

-- The saved state off the frame path (2026-10-20, ot_saved Reader): the game script copies the whole state only when its
-- change number moved. Two drivers on two identical fake engines, the events applied to a master state as handleEvent
-- does (apply, bumpRev, set); one gets a full copy every frame (the old path), the other the reader's copy (cached, the
-- native number optionally lagging the copy): the same events, the same log lines, and the cached copy never written to.
local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = deepCopy(x) end
	return o
end

local function ser(v)
	if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local APPLY = {
	[SV.EV_INIT] = SV.applyInit, [SV.EV_FRAME] = SV.applyFrame, [SV.EV_SAT] = SV.applySat, [SV.EV_BRIDGE] = SV.applyBridge,
	[SV.EV_NAMES] = SV.applyNames, [SV.EV_STOPS] = SV.applyStopsDone, [SV.EV_LEAD] = SV.applyLead,
	[SV.EV_WORKS] = SV.applyWorks, [SV.EV_STOPBASE] = SV.applyStopBase, [SV.EV_LEVELS] = SV.applyLevels,
	[SV.EV_LEVELBASE] = SV.applyLevelBase, [SV.EV_PACE] = SV.applyPace, [SV.EV_CHARS] = SV.applyChars,
	[SV.EV_DENSE] = SV.applyDense, [SV.EV_PAIR] = SV.applyPair, [SV.EV_RCI] = SV.applyRci, [SV.EV_GLOCK] = SV.applyGlock,
	[SV.EV_UI] = SV.applyUi, [SV.EV_PROV] = SV.applyProv }

local function twinRun(lag, frames)
	local function side()
		local E = fakeEngine({ params = { act_on = 2, debug_log = 2 }, gameTime = 0 })
		return { E = E, d = D.new(E), master = nil, applied = 0, revs = {} }
	end
	local A, B = side(), side()
	local reader = SV.newReader()
	local fulls, written = 0, 0
	local function apply(S)
		while S.applied < #S.E.events do
			S.applied = S.applied + 1
			local ev = S.E.events[S.applied]
			local fn = APPLY[ev.name]
			if fn then
				local s, changed = fn(deepCopy(S.master), deepCopy(ev.param))
				if changed then S.master = SV.bumpRev(s) end
			end
		end
	end
	for f = 1, frames do
		A.d:tick(A.E.t, deepCopy(A.master))
		B.revs[f] = SV.revOf(B.master)
		local saved, full = reader:read(function() return deepCopy(B.master) end,
			function() return B.revs[math.max(1, f - lag)] end, function() return B.E.t end)
		if full then fulls = fulls + 1 end
		local before, sent = ser(saved), #B.E.events
		B.d:tick(B.E.t, saved)
		if ser(saved) ~= before then written = written + 1 end
		if #B.E.events ~= sent then reader:expect(B.E.t) end   -- (the game script: ot_engine.sentN moved)
		for _, S in ipairs({ A, B }) do
			if S.E.pending then
				local p = S.E.pending
				S.E.pending = nil
				p.cb(true, { cost = 300000, msgs = {} })
			end
			apply(S)
			S.E.t = S.E.t + 100000
		end
	end
	return A, B, reader, fulls, written
end

test("state reader: the driver sends the same events and logs the same lines as with a full copy every frame", function()
	for _, lag in ipairs({ 0, 3, 25 }) do
		local A, B, reader, fulls, written = twinRun(lag, 900)
		eq(reader.mode, "rev", "no fallback")
		eq(written, 0, "the driver never writes into the saved copy")
		ok(#A.E.events >= 3, "init, frame and more were sent: " .. #A.E.events)
		eq(#B.E.events, #A.E.events)
		for i = 1, #A.E.events do
			eq(B.E.events[i].name, A.E.events[i].name)
			eq(ser(B.E.events[i].param), ser(A.E.events[i].param), "event " .. i)
		end
		eq(#B.E.logs, #A.E.logs)
		for i = 1, #A.E.logs do eq(B.E.logs[i], A.E.logs[i]) end
		ok(SV.revOf(A.master) ~= nil and SV.revOf(A.master) >= 2, "changes bumped the number")
		ok(fulls < 900 / 4, "full copies " .. fulls .. " of 900 frames (lag " .. lag .. ")")
	end
end)

test("TICKCOST: getN counts the full copies (nil: the old path, every tick), stateMode and revMiss", function()
	local E = { logs = {} }
	function E.log(l) E.logs[#E.logs + 1] = l end
	local d = D.new(E)
	d.phase = "run"
	local W = D.COST_EVERY_S * 1e6
	d:costNote(0, 1000, 150, "idle", true, "rev", 0)
	d:costNote(1e6, 1000, 3, "idle", false, "rev", 0)
	d:costNote(2e6, 1000, 3, "idle", false, "rev", 1)
	local l = d:costNote(W + 1, 1000, 3, "idle", false, "rev", 1)
	for _, part in ipairs({ "getN=1", "stateMode=rev", "revMiss=1", "getMaxUs=150", "getAvgUs=40", "pvB=0" }) do
		ok(l:find(part, 1, true), part .. " in " .. l)
	end
	-- the old call (no reader fields): every tick a copy, mode get
	d:costNote(W + 2, 1000, 100, "idle")
	local l2 = d:costNote(2 * W + 3, 1000, 100, "idle")
	for _, part in ipairs({ "getN=2", "stateMode=get", "revMiss=-" }) do ok(l2:find(part, 1, true), part .. " in " .. l2) end
end)

test("SNAPSHOT: the empty-row measure (emptyRows= m/dead-end m/edges) and its own time, with the debug log on", function()
	local E = fakeEngine()
	local d = D.new(E)
	run(d, E, 400, nil, function() return E.pending ~= nil end)
	local snap = logsWith(E, "SNAPSHOT")
	ok(#snap >= 1)
	ok(snap[1]:find("emptyRows=0/0/0", 1, true) and snap[1]:find("rowsUs=", 1, true), snap[1])
end)

test("left-hand traffic (2026-10-20): mirrored junctions in buildInfo, rings off; right-hand by default", function()
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	local d = D.new(E)
	d:loadConfig()
	local job = { town = TOWN, edges = {}, style = {} }
	eq(d:buildInfo(job).leftHand, false, "no driveSide: the base game's right-hand traffic")
	local EL = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	-- (the Left Hand Traffic mod's flipped template: forward lane first)
	EL.driveSide = function(from) return from({ true, false }) and "left" or "right", SMALL end
	local dl = D.new(EL)
	dl:loadConfig()
	eq(dl:buildInfo({ town = TOWN, edges = {}, style = {} }).leftHand, true)
	local geo, why = dl:rbGeo()
	eq(geo, nil, "no one-way rings: they run counter-clockwise")
	eq(why, "leftHand")
	local EE = fakeEngine({ params = { act_on = 3, debug_log = 2 } })
	EE.driveSide = function() error("boom") end
	local de = D.new(EE)
	de:loadConfig()
	eq(de:buildInfo({ town = TOWN, edges = {}, style = {} }).leftHand, false, "a failing read stays right-hand")
end)
