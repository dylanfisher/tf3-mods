-- Stress Test bench, the city run's build (gui/stress_citylights.tl; plans/square_stress_test/BENCH.md "City lights at
-- scale") against a fake game: the cities through towns.createGrid / lockTowns / densify (stubs), every inner crossing of
-- each wide grid found among the street nodes, the dark ones lit (one command each), a CITY line and a traffic log zone
-- per city, and the enroll (SmartLanes.auto add events for the auto cities' crossings only).

local bench = ug_require "square_stress_test::/stress/stress_bench.tl"

local T, NODES, EDGES, SENT, AUTO_SENT, GRID_OPTS, LOCKS, DENSE

local YES, AUTO_PREF = 2, 0
local E0 = 100000   -- edge ids
local REMOVED

--- A wide grid at (cx, cy): 11 x 11 nodes 80 m apart (the ring's T-junctions: 3 streets, its corners 2), edges between
--- neighbours; `lit`: inner crossings already lit by the game's AUTO.
local function addGrid(cx, cy, lit)
	local ids = {}
	for i = -5, 5 do
		ids[i] = {}
		for j = -5, 5 do
			local id = #NODES + 1
			local ring = math.abs(i) == 5 or math.abs(j) == 5
			local corner = math.abs(i) == 5 and math.abs(j) == 5
			NODES[id] = { x = cx + i * 80, y = cy + j * 80, deg = corner and 2 or (ring and 3 or 4), lit = (not ring) and lit(i, j) or false }
			ids[i][j] = id
		end
	end
	for i = -5, 5 do
		for j = -5, 5 do
			if i < 5 then EDGES[#EDGES + 1] = { ids[i][j], ids[i + 1][j] } end
			if j < 5 then EDGES[#EDGES + 1] = { ids[i][j], ids[i][j + 1] } end
		end
	end
end

--- A city's grid in a layout (stress_grid_streets.lua grid.layout): only its kept streets, each node's degree from them;
--- `extra`: town streets {x0, y0, x1, y1} (relative) added as well (a stray street in a gap).
local function addLayoutGrid(cx, cy, L, extra)
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	local at = {}
	local function node(x, y)
		local k = string.format("%.0f,%.0f", x, y)
		if at[k] == nil then
			NODES[#NODES + 1] = { x = cx + x, y = cy + y, deg = 0, lit = false }
			at[k] = #NODES
		end
		return at[k]
	end
	local function edge(a, b)
		EDGES[#EDGES + 1] = { a, b }
		NODES[a].deg = NODES[a].deg + 1
		NODES[b].deg = NODES[b].deg + 1
	end
	for _, e in ipairs(grid.layoutEdges(400, L)) do
		if math.abs(e[3][1]) <= 400 and math.abs(e[3][2]) <= 400 then edge(node(e[1][1], e[1][2]), node(e[3][1], e[3][2])) end
	end
	for _, x in ipairs(extra or {}) do edge(node(x[1], x[2]), node(x[3], x[4])) end
end

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			enum = { TrafficLightPreference = { YES = YES, NO = 1, AUTO = AUTO_PREF } },
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p)
				if p.streetProposal ~= nil then return { remove = p.streetProposal.edgesToRemove } end
				return { light = p.node }
			end,
			sendCommand = function(cmd, cb)
				if cmd.remove then
					REMOVED[#REMOVED + 1] = #cmd.remove
					for _, e in ipairs(cmd.remove) do
						local ed = EDGES[e - E0]
						ed.gone = true
						NODES[ed[1]].deg = NODES[ed[1]].deg - 1
						NODES[ed[2]].deg = NODES[ed[2]].deg - 1
					end
					if cb then cb(cmd, true) end
					return
				end
				if cmd.light then
					SENT[#SENT + 1] = cmd.light
					-- one node refuses its light
					if cmd.light ~= 62 then NODES[cmd.light].lit = true end
				end
				if cb then cb(cmd, cmd.light ~= 62) end
			end,
		},
		engine = {
			terrain = { getBoundingBox = function() return { min = { x = -8000, y = -8000 }, max = { x = 8000, y = 8000 } } end },
			getComponent = function(e, ct)
				if e >= E0 then
					local ed = EDGES[e - E0]
					if ed == nil or ed.gone then return nil end
					if ct == "BASE_EDGE_STREET" then return {} end
					if ct == "BASE_EDGE" then return { node0 = ed[1], node1 = ed[2] } end
					return nil
				end
				local n = NODES[e]
				if n == nil then return nil end
				if ct == "BASE_NODE" then return { position = { x = n.x, y = n.y } } end
				if ct == "BASE_NODE_CONFIG" then
					return { trafficLightPreference = n.lit and YES or AUTO_PREF, trafficLightConfig = { clone = function(self) return self end } }
				end
				return nil
			end,
			system = { streetSystem = { getNodeSegments = function(n)
				local out = {}
				for k = 1, NODES[n].deg do out[k] = k end
				return out
			end } },
			util = {
				octree = { findEntitiesInCircle = function(pos, r, _ct)
					local out = {}
					for k, ed in ipairs(EDGES) do
						local a, b = NODES[ed[1]], NODES[ed[2]]
						local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
						if not ed.gone and (mx - pos.x) ^ 2 + (my - pos.y) ^ 2 <= r * r then out[#out + 1] = E0 + k end
					end
					return out
				end },
				proposal = { createTrafficLightProposal = function(n, _tlc, pref) return { node = n, pref = pref } end },
				getYear = function() return 1950 end,
			},
		},
	}
end

local rt, cl, towns, slz

before_each(function()
	T = 0
	NODES, EDGES, SENT, AUTO_SENT, LOCKS, DENSE, REMOVED = {}, {}, {}, {}, {}, {}, {}
	GRID_OPTS = nil
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	towns = {
		createGrid = function(opts, onDone)
			GRID_OPTS = opts
			-- the towns of every point but the 6th (no land there)
			local created = {}
			for k, p in ipairs(opts.points) do
				if k ~= 6 then created[k] = 500 + k end
			end
			onDone(created, opts.points, { [6] = true }, {})
		end,
		lockTowns = function(name, areas, opts) LOCKS[#LOCKS + 1] = { name = name, areas = areas, opts = opts } opts.onDone(10) end,
		densify = function(name, areas, opts) DENSE[#DENSE + 1] = { name = name, areas = areas, opts = opts } opts.onDone(20) end,
	}
	stub_module("square_stress_test::/stress/gui/stress_towns.tl", towns)
	slz = {
		present = function() return true end,
		sendAutoNodes = function(payloads) AUTO_SENT[#AUTO_SENT + 1] = payloads return #payloads end,
		sendAuto = function(op, by) AUTO_SENT[#AUTO_SENT + 1] = { op = op, by = by } return "r" end,
		setLocal = function(zones, run) slz.local_ = { zones = zones, run = run } end,
	}
	stub_module("square_stress_test::/stress/gui/stress_slzones.tl", slz)
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	cl = ug_require "square_stress_test::/stress/gui/stress_citylights.tl"
end)

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.msg end
	return table.concat(out, "\n")
end

local function runUntil(cond, max)
	for _ = 1, max or 5000 do
		if cond() then return true end
		T = T + 100000
		rt.tick()
	end
	return cond()
end

test("build: six Large wide-grid cities (no links), locked, one size command each, every inner crossing lit (Yes where dark), a CITY line and a zone per city; the enroll asks for the auto cities' crossings only", function()
	local plan = bench.cityPlan(16000, 16000, 400, bench.CITY)
	-- the grids where createGrid would put them; every second inner crossing already lit by the game
	for _, c in ipairs(plan.cities) do addGrid(c.x, c.y, function(i, j) return (i + j) % 2 == 0 end) end
	local zones
	ok(cl.build(bench.CITY, 7, function(z) zones = z end, function(why) error("aborted: " .. why) end))
	ok(not cl.build(bench.CITY, 8, function() end, function() end), "one build at a time")
	eq({ GRID_OPTS.streets, GRID_OPTS.connect, GRID_OPTS.batch, GRID_OPTS.skipNoLand, GRID_OPTS.size.label, #GRID_OPTS.points },
		{ 3, 1, true, true, "Large", 6 })
	eq({ GRID_OPTS.points[1].x, GRID_OPTS.points[1].y, GRID_OPTS.points[1].name, GRID_OPTS.points[1].size, GRID_OPTS.points[1].pop },
		{ -4000, -2000, "City auto 1", 3, 3000 })
	eq(#LOCKS[1].areas, 5, "the city without land is left out")
	eq({ LOCKS[1].opts.pass, LOCKS[1].opts.stubs, LOCKS[1].areas[1].half, LOCKS[1].areas[1].target }, { "towns", true, 400, 3000 })
	eq({ DENSE[1].opts.target, DENSE[1].opts.passes, DENSE[1].opts.factor }, { 3000, 1, 1.9 })
	ok(runUntil(function() return zones ~= nil end), "the build finished: " .. logText())
	-- 5 cities x 81 inner crossings, 40 of each dark (41 lit by AUTO): 200 lights sent, the one refused counted
	eq(#SENT, 200)
	local all = logText()
	ok(all:find("[SQST] bench_city_lights: 405 inner crossings found, 200 dark: lights on", 1, true), all)
	ok(all:find("[SQST] CITY id=cityg1v pair=cityg1 role=auto town=501 name=City_auto_1 x=-4000 y=-2000 half=400 crossings=81 found=81 lit_before=41 forced=39 refused=1", 1, true), all)
	ok(all:find("[SQST] CITY id=cityg3b pair=cityg3 role=control town=- name=City_control_3 x=4000 y=2000 half=400 crossings=81 found=0 lit_before=0 forced=0 refused=0", 1, true), all)
	ok(all:find("[SQST] showcase zone id=cityg2v pair=cityg2 ab=city_auto kind=other type=City_auto_2 x=0 y=2000 r=400", 1, true), all)
	eq(#zones, 5)
	eq(slz.local_.run, "city-7")
	eq(#slz.local_.zones, 5)
	for _, z in ipairs(zones) do ok(z.built, z.id) end
	-- the enroll: the three auto cities' 243 crossings in 5 events of at most 60, never a control city's
	local n = cl.enroll(bench.CITY, cl.last.run, cl.last.crossings, cl.last.plan)
	eq(n, 243)
	local pl = AUTO_SENT[1]
	eq(#pl, 5)
	local nodes = {}
	for _, p in ipairs(pl) do
		ok(#p.nodes <= 60)
		eq({ p.op, p.src }, { "add", "stress" })
		for _, e in ipairs(p.nodes) do nodes[#nodes + 1] = e end
	end
	eq(#nodes, 243)
	local autoAt = {}
	for _, c in ipairs(plan.cities) do if c.role == "auto" then autoAt[#autoAt + 1] = c end end
	for _, e in ipairs(nodes) do
		local near = false
		for _, c in ipairs(autoAt) do
			if math.abs(e[2] - c.x) <= 400 and math.abs(e[3] - c.y) <= 400 then near = true end
		end
		ok(near, "an auto city's crossing: " .. tostring(e[1]))
	end
	ok(logText():find("[SQST] CITY_ENROLL run=city-7 op=add cities=3 nodes=243 events=5 baseline_s=900 by=bench smart_lanes=yes", 1, true), logText())
	cl.unenroll()
	eq(AUTO_SENT[2], { op = "clear", by = "bench_city" })
end)

test("build: no city created ends the build (onAbort); without control cities the enroll is SmartLanes.auto op=all", function()
	towns.createGrid = function(opts, onDone) onDone({}, opts.points, {}, {}) end
	local why
	ok(cl.build(bench.CITY, 1, function() error("no zones expected") end, function(w) why = w end))
	eq(why, "no city was created")
	local solo = { id = "bench_city", baselineS = 900, city = { pairs = 3, size = 3, pop = 3000, spacing = 4000, control = false } }
	local plan = bench.cityPlan(16000, 16000, 400, solo)
	eq(cl.enroll(solo, "city-1", {}, plan), 243)
	eq(AUTO_SENT[1], { op = "all", by = "bench_city" })
	ok(logText():find("[SQST] CITY_ENROLL run=city-1 op=all cities=3 nodes=243 events=1 ", 1, true), logText())
end)

test("build, Hourglass + Busy + Swap roles: the grid construction asked for the layout, a stray street in a gap removed (CITY_GAPS), every 4-way and T crossing lit, the weights and people of Busy; gapCheck at the end", function()
	local sheet = bench.citySheet({ layout = 2, busy = true, swap = true, baseline = 2 })
	local plan = bench.cityPlan(16000, 16000, 400, sheet)
	local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"
	local L = grid.layout(400, "hourglass")
	for k, c in ipairs(plan.cities) do
		-- the first city: a town street across its west gap (from the band's south edge to its north edge)
		addLayoutGrid(c.x, c.y, L, k == 1 and { { -240, -80, -240, 80 } } or nil)
	end
	local zones
	ok(cl.build(sheet, 7, function(z) zones = z end, function(why) error("aborted: " .. why) end))
	eq({ GRID_OPTS.gridLayout, GRID_OPTS.gridHoles }, { 2, nil }, "the construction's layout param")
	ok(runUntil(function() return zones ~= nil end), "the build finished: " .. logText())
	eq({ DENSE[1].opts.target, DENSE[1].opts.weights, DENSE[1].opts.factor }, { 7500, { 0.0, 0.0, 0.25, 1.0 }, 4.7 })  -- after the gaps were cleared
	eq(REMOVED, { 1 }, "the stray street, one proposal")
	local all = logText()
	ok(all:find("[SQST] bench_city cities=6 auto=3 control=3 size=Large pop=7500 spacing=4000 half=400 crossings=450 enrolled=225 run=city-7 layout=hourglass busy=1 baseline_s=1800 role_swap=1 neck_streets=3 holes=0 holes_pattern=0 holes_at=- x4=61 t3=14 weights={0,0,0.25,1}", 1, true), all)
	ok(all:find("[SQST] CITY_GAPS id=cityg1b pair=cityg1 role=control at=build layout=hourglass gap_streets=1 removed=1", 1, true), all)
	ok(all:find("[SQST] CITY_GAPS id=cityg1v pair=cityg1 role=auto at=build layout=hourglass gap_streets=0 removed=0", 1, true), all)
	-- 5 cities (the 6th has no land) x 75 crossings, every one dark
	ok(all:find("[SQST] bench_city_lights: 375 inner crossings found, 375 dark: lights on (layout=hourglass found4=305 found3=70)", 1, true), all)
	ok(all:find("[SQST] CITY id=cityg1b pair=cityg1 role=control town=501 name=City_control_1 x=-4000 y=-2000 half=400 crossings=75 found=75 lit_before=0 forced=74 refused=1 layout=hourglass neck_streets=3 holes=0 found4=61 found3=14 lit4=61 lit3=13 pop=- gap_streets=1 gap_removed=1", 1, true), all)
	-- the enroll: the auto cities only (swapped: on the other rows), 3 x 75
	clear_logs()
	eq(cl.enroll(sheet, cl.last.run, cl.last.crossings, cl.last.plan), 225 - 75, "the 6th city (no land) is an auto one")
	ok(logText():find("by=bench smart_lanes=yes layout=hourglass busy=1 role_swap=1", 1, true), logText())
	-- the end: the gaps counted again, no removal
	clear_logs()
	eq(cl.gapCheck("end"), 0)
	ok(logText():find("[SQST] CITY_GAPS id=cityg1b pair=cityg1 role=control at=end layout=hourglass gap_streets=0 removed=0", 1, true), logText())
	eq(#REMOVED, 1)
end)
