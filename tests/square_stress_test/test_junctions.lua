-- Junction test (Towns tab): stress_logic's pure layout helpers, the case list against the
-- square_roundabouts files, and stress_junctions.tl against a fake api: towns first, then one
-- junction per cell (45 deg, +0 transform), arm ends found by the node diff, carriageway pairs merged
-- in one node with each carriageway extended in its own direction, links to the nearest town node.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl"

---------------------------------------------------------------------------
-- Pure logic

test("junction cases: every set's ids exist; All types has every case once", function()
	local byId = {}
	for _, c in ipairs(logic.JUNCTION_CASES) do
		ok(byId[c.id] == nil, "duplicate " .. c.id)
		byId[c.id] = c
	end
	for _, set in ipairs(logic.JUNCTION_SETS) do
		for _, id in ipairs(set.ids) do ok(byId[id] ~= nil, set.label .. ": " .. id) end
		eq(#logic.junctionCases(set), #set.ids)
	end
	eq(#logic.junctionCases(logic.JUNCTION_SETS[1]), #logic.JUNCTION_CASES)
end)

test("crossing construction: X / T / skewed arms, two roads meeting in one centre node, +0 only", function()
	local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"
	local cases = {}
	for shape = 1, 3 do
		for main = 1, #cross.ROADS do
			cases[#cases + 1] = { params = { sqst_x_shape = shape, sqst_x_main = main, sqst_x_side = (main % #cross.ROADS) + 1 } }
		end
	end
	for shape = 1, 3 do
		for _, c in ipairs(cases) do
			local r = cross.result(c.params)
			eq(#r.edgeLists, 2)
			local arms = 0
			for li, el in ipairs(r.edgeLists) do
				eq(el.type, "STREET")
				ok(el.params.type:find("::/infrastructure/street/", 1, true), el.params.type)
				eq(#el.freeNodes, #el.edges, "every node free")
				for k = 1, #el.edges, 2 do
					arms = arms + 1
					local a, b = el.edges[k][1], el.edges[k + 1][1]
					-- one end of every edge is the centre
					ok((a[1] == 0 and a[2] == 0) or (b[1] == 0 and b[2] == 0), "edge at the centre")
					for _, v in ipairs({ a[1], a[2], b[1], b[2] }) do ok(1 / v ~= -math.huge, "no -0") end
				end
			end
			eq(arms, c.params.sqst_x_shape == 2 and 3 or 4)
		end
		local mainDirs, sideDirs = cross.arms(shape)
		eq(#mainDirs, 2)
		eq(#sideDirs, shape == 2 and 1 or 2)
	end
	-- the one-way main road flows west -> centre -> east
	local r = cross.result({ sqst_x_shape = 1, sqst_x_main = 8, sqst_x_side = 3 })
	local e = r.edgeLists[1].edges
	eq(e[1][1][1], -cross.ARM)
	eq(e[2][1][1], 0)
	eq(e[3][1][1], 0)
	eq(e[4][1][1], cross.ARM)
	-- tram: the track type rides along
	eq(cross.result({ sqst_x_main = 10 }).edgeLists[1].params.tramTrackType, "ELECTRIC")
	eq(cross.label(2, 3, 1), "Town large x Town small, T")
end)

test("junction and in-line cases name real square_roundabouts files and param keys", function()
	local dir = "mods/square_roundabouts/content/" .. logic.JUNCTION_DIR
	local f = io.open(dir .. "square_roundabouts.con.lua")
	if f == nil then return end -- not run from the repo root
	f:close()
	-- every key must appear quoted in one of the construction sources
	local text = ""
	for _, name in ipairs({ "square_roundabouts_geometry.lua", "square_roundabouts_magic.lua", "square_roundabouts_channel.lua",
		"square_roundabouts_interchange.lua", "square_roundabouts_highway.lua", "square_roundabouts_highway_menu.lua" }) do
		local g = assert(io.open(dir .. name))
		text = text .. g:read("a")
		g:close()
	end
	local all = {}
	for _, list in ipairs({ logic.JUNCTION_CASES, logic.INLINE_ROAD, logic.INLINE_HIGHWAY }) do
		for _, c in ipairs(list) do all[#all + 1] = c end
	end
	-- our own crossing construction and its keys
	local own = "mods/square_stress_test/content/" .. logic.JUNCTION_DIR
	do
		local g = assert(io.open("mods/square_stress_test/content/stress/stress_crossing.lua"))
		text = text .. g:read("a")
		g:close()
	end
	local ids = {}
	for _, c in ipairs(all) do
		local h = io.open(dir .. c.file .. ".lua") or io.open(own .. c.file .. ".lua")
		ok(h ~= nil, c.file)
		if h then h:close() end
		for k, v in pairs(c.params) do
			ok(text:find('"' .. k .. '"', 1, true) or text:find(k .. " =", 1, true), "unknown key " .. k)
			ok(v >= 1 and v == math.floor(v), k .. " is a 1-based index")
		end
	end
	for _, list in ipairs({ logic.INLINE_ROAD, logic.INLINE_HIGHWAY }) do
		for _, c in ipairs(list) do
			ok(not ids[c.id], "unique id " .. c.id)
			ids[c.id] = true
		end
		ids = {}
	end
end)

test("inlineStops: as many as fit, evenly spread, clear of both ends", function()
	local a, b = { 0, 0 }, { 3000, 0 }
	-- free 3000 - 400 - 600 = 2000; pitch 500 -> 5 stops at 400, 900, ..., 2400
	local s = logic.inlineStops(a, b, 400, 600, 500, 20)
	eq(#s, 5)
	near(s[1][1], 400)
	near(s[5][1], 2400)
	near(s[3][1], 1400)
	near(s[2][2], 0)
	eq(#logic.inlineStops(a, b, 400, 600, 500, 2), 2, "capped")
	-- one alone sits in the middle of the free part
	local one = logic.inlineStops(a, b, 400, 600, 2500, 20)
	eq(#one, 1)
	near(one[1][1], 1400)
	eq(#logic.inlineStops(a, b, 2000, 1500, 500, 20), 0, "no room")
	-- diagonal
	local d = logic.inlineStops({ 0, 0 }, { 1000, 1000 }, 0, 0, 2000, 20)
	near(d[1][1], 500)
	near(d[1][2], 500)
end)

test("junctionGrid: fewest towns for n cells", function()
	eq({ logic.junctionGrid(1) }, { 2, 2 })
	eq({ logic.junctionGrid(4) }, { 3, 3 })
	eq({ logic.junctionGrid(6) }, { 4, 3 })
	eq({ logic.junctionGrid(7) }, { 4, 4 })
	eq({ logic.junctionGrid(10) }, { 5, 4 }, "squarer than 6 x 3: fits a map at 4 km")
end)

test("fitJunctionGrid: the squarest grid that fits, else the widest spacing that does", function()
	-- 16 x 16 km map, margin 400: 15.2 km usable
	eq({ logic.fitJunctionGrid(10, 3000, 16000, 16000, 400) }, { 5, 4, 3000 }, "4 x 3 cells fit at 3 km")
	-- 4 km: 4 cells = 16 km > 15.2; 3 x 4 doesn't fit either -> widest: 3 x 4 cells (or 4 x 3) at 3.8 km
	local c, r, s = logic.fitJunctionGrid(10, 4000, 16000, 16000, 400)
	eq(s, 3800)
	ok((c - 1) * (r - 1) >= 10)
	-- a wide map: 5 x 2 cells at 4 km need 20 x 8 km
	eq({ logic.fitJunctionGrid(10, 4000, 24000, 10000, 400) }, { 6, 3, 4000 })
	-- 4 roundabouts at 6 km: 2 x 2 cells = 12 km
	eq({ logic.fitJunctionGrid(4, 6000, 16000, 16000, 400) }, { 3, 3, 6000 })
	-- unknown map size: as asked
	eq({ logic.fitJunctionGrid(10, 4000, 0, 0, 400) }, { 5, 4, 4000 })
end)

test("junctionCells: centres and corners SW, SE, NE, NW", function()
	local pts = logic.gridPositions(0, 0, 3, 2, 2000)
	local cells = logic.junctionCells(pts, 3, 2)
	eq(#cells, 2)
	eq(cells[1].corners, { 1, 2, 5, 4 })
	near(cells[1].x, -1000)
	near(cells[1].y, 0)
	eq(cells[2].name, "Cell A2")
	near(cells[2].x, 1000)
	eq(logic.junctionLabel(10, 2000), "Build 10 junctions, 2 km")
	eq(logic.junctionLabel(1, 3000), "Build 1 junction, 3 km")
end)

test("clusterEnds: carriageway pairs group, far ends stay apart", function()
	local cl = logic.clusterEnds({ { 100, 0 }, { 0, 100 }, { 100, 20 }, { -100, 0 } }, 45)
	eq(#cl, 3)
	eq(cl[1].members, { 1, 3 })
	near(cl[1].x, 100)
	near(cl[1].y, 10)
	eq(cl[2].members, { 2 })
	eq(cl[3].members, { 4 })
end)

test("assignArms: each arm to the corner in its direction, each corner once, far-off arms unlinked", function()
	local corners = { { -10, -10 }, { 10, -10 }, { 10, 10 }, { -10, 10 } }
	local cl = {
		{ x = 5, y = 5.5 }, { x = -5, y = -5 }, { x = 4, y = 6 }, { x = 5, y = -5 },
	}
	local a = logic.assignArms(0, 0, cl, corners, 60)
	eq(a[1], 3)
	eq(a[2], 1)
	eq(a[3], nil) -- NE taken by the closer match; NW is 79 deg off
	eq(a[4], 2)
	local b = logic.assignArms(0, 0, { { x = 0, y = 7 } }, { { 10, -10 } }, 60)
	eq(b[1], nil)
end)

test("linePoints and distToSegment", function()
	local p = logic.linePoints({ 0, 0, 0 }, { 450, 0, 9 }, 200)
	eq(#p, 4)
	near(p[2][1], 150)
	near(p[2][3], 3)
	near(logic.distToSegment({ 5, 5 }, { 0, 0 }, { 10, 0 }), 5)
	near(logic.distToSegment({ -3, 4 }, { 0, 0 }, { 10, 0 }), 5)
end)

test("rankTownNodes: dead ends only, nearest first; far nodes and nodes on our roads left out", function()
	local cands = {
		{ id = 1, x = 100, y = 0, z = 0, deg = 1 },
		{ id = 2, x = 90, y = 0, z = 0, deg = 3 },  -- not a dead end (the 2026-10-11 crash case)
		{ id = 3, x = 95, y = 0, z = 0, deg = 2 },
		{ id = 4, x = 600, y = 0, z = 0, deg = 1 }, -- outside maxR
		{ id = 5, x = 80, y = 50, z = 0, deg = 1 }, -- on our earlier link road
		{ id = 6, x = 50, y = 0, z = 0, deg = 1 },
	}
	local r = logic.rankTownNodes(cands, { 300, 0 }, { 0, 0 }, 500, { { { 80, 45 }, { 300, 300 } } })
	local ids = {}
	for i, c in ipairs(r) do ids[i] = c.id end
	eq(ids, { 1, 6 })
end)

test("isLargeStreet: large two-way town and country streets; highways, one-way and small streets not", function()
	for _, n in ipairs({ "::/infrastructure/street/town/town_new_large.street_template", "town_old_large.street_template",
		"square_x::/infrastructure/street/country/country_new_large_bus.street_template", "country_old_large_barriers.street_template",
		"town_new_large_tram_electrified.street_template" }) do
		ok(logic.isLargeStreet(n), n)
	end
	for _, n in ipairs({ "town_new_medium.street_template", "town_new_small.street_template", "highway_new_large.street_template",
		"town_new_one_way_large.street_template", "country_new_medium.street_template", "", 12 }) do
		ok(not logic.isLargeStreet(n), tostring(n))
	end
	eq(logic.isLargeStreet(nil), false)
end)

test("rankTownNodes: a node on a large street first, unless much further than the nearest", function()
	local function ids(r) local out = {} for i, c in ipairs(r) do out[i] = c.id end return out end
	local cands = {
		{ id = 1, x = 100, y = 0, z = 0, deg = 1 },
		{ id = 2, x = -150, y = 0, z = 0, deg = 1, large = true },   -- 250 m further than node 1
		{ id = 3, x = 0, y = 100, z = 0, deg = 1 },
	}
	eq(ids(logic.rankTownNodes(cands, { 300, 0 }, { 0, 0 }, 500, {})), { 2, 1, 3 })
	-- 600 m further: the near small street wins (the link would cross the town)
	cands[2].x = -400
	eq(ids(logic.rankTownNodes(cands, { 300, 0 }, { 0, 0 }, 500, {})), { 1, 3, 2 })
	-- a large node that is no dead end is still never taken
	cands[2].x, cands[2].deg = -150, 2
	eq(ids(logic.rankTownNodes(cands, { 300, 0 }, { 0, 0 }, 500, {})), { 1, 3 })
end)

---------------------------------------------------------------------------
-- stress_junctions.tl against a fake api

local T = 0
local sent, nodes, edges, nextId, refuseCheck, created

local function node2edges()
	local m = {}
	for e, ed in pairs(edges) do
		for _, n in ipairs({ ed.n0, ed.n1 }) do
			m[n] = m[n] or {}
			table.insert(m[n], e)
		end
	end
	return m
end

local function newNode(x, y)
	nextId = nextId + 1
	nodes[nextId] = { x = x, y = y, z = 0 }
	return nextId
end

local function newEdge(a, b)
	nextId = nextId + 1
	edges[nextId] = { n0 = a, n1 = b }
	return nextId
end

-- laneConfigs of the fake's highway carriageways (one-way, two road lanes) and two-way streets (stress_nodecfg
-- reads directions from them): index 1 and the last are sidewalks
local function lanesOf(forwards)
	local out = { { forward = forwards[1], transportModes = { [0] = true } } }
	for k = 2, #forwards - 1 do out[#out + 1] = { forward = forwards[k], transportModes = { [2] = true, [3] = true, [4] = true } } end
	out[#out + 1] = { forward = forwards[#forwards], transportModes = { [0] = true } }
	return out
end
local ONE_WAY = lanesOf({ true, true, true, true })
local TWO_WAY = lanesOf({ false, false, true, true })

--- What is wrong with a link proposal's node configs (stress_nodecfg.problems, plus: an existing node
--- that keeps a config is listed for removal, and no connection uses a sidewalk lane). {} when nothing.
local function cfgProblems(sp)
	local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl"
	local out = nc.problems(sp, function(e) return edges[e] and edges[e].lanes and #edges[e].lanes or 4 end)
	local rm = {}
	for _, n in ipairs(sp.nodeConfigsToRemove or {}) do rm[n] = true end
	local lanes = {}
	for _, seg in ipairs(sp.edgesToAdd or {}) do lanes[seg.entity] = seg.comp.laneConfigs and #seg.comp.laneConfigs or 4 end
	for _, e in ipairs(sp.nodeConfigsToAdd or {}) do
		if e.entity >= 0 and nodes[e.entity] and not rm[e.entity] then out[#out + 1] = "existing node " .. e.entity .. " not removed first" end
		for _, c in ipairs(e.comp.laneConnections or {}) do
			for _, pr in ipairs({ { c.segment0, c.lane0 }, { c.segment1, c.lane1 } }) do
				local n = lanes[pr[1]] or (edges[pr[1]] and edges[pr[1]].lanes and #edges[pr[1]].lanes) or 4
				if pr[2] < 1 or pr[2] > n - 2 then out[#out + 1] = string.format("node %d: sidewalk lane %d of %d", e.entity, pr[2], pr[1]) end
			end
		end
	end
	return out
end

local function fakeApi()
	local function vec(x, y, z) return { x = x, y = y, z = z } end
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = { BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", BASE_NODE = "BASE_NODE",
				BASE_NODE_CONFIG = "BASE_NODE_CONFIG", TOWN = "TOWN" },
			SimpleProposal = setmetatable({ ConstructionEntity = { new = function() return {} end } },
				{ __index = { new = function() return { streetProposal = {} } end } }),
			Context = { new = function() return {} end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = vec },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
			Mat4f = { new = function(a, b, c, d) return { a, b, c, d } end },
			NodeAndEntity = { new = function() return { comp = {} } end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			LaneConnection = { new = function() return { ctor = true } end },
			SegmentAndEntity = { new = function() return {} end },
			enum = { TrafficLightPreference = { YES = 0, NO = 1, AUTO = 2 } },
		},
		res = { constructionRep = { find = function(name)
			if name:sub(1, #"square_roundabouts::/") == "square_roundabouts::/" then return 1 end
			return name == "square_stress_test::/infrastructure/street_construction/square_stress_test_crossing.con" and 2 or -1
		end } },
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb, t = T } end,
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { p = p, ctx = ctx, ignore = ignore, player = player, dust = dust }
			end,
		},
		gui = { camera = { getCameraData = function() return { x = 0, y = 0 } end } },
		engine = {
			getComponent = function(e, ct)
				if ct == "BASE_EDGE" then
					local ed = edges[e]
					return ed and { node0 = ed.n0, node1 = ed.n1, tag = "edge" .. e, roadTemplate = ed.template, laneConfigs = ed.lanes } or nil
				elseif ct == "BASE_EDGE_STREET" then
					return edges[e] and { tag = "street" .. e } or nil
				elseif ct == "BASE_NODE" then
					local n = nodes[e]
					return n and { position = vec(n.x, n.y, n.z) } or nil
				elseif ct == "BASE_NODE_CONFIG" then
					-- every node: one lane connection through each pair of its edges, one crosswalk
					if not nodes[e] then return nil end
					local list = node2edges()[e] or {}
					local lcs = {}
					for i = 1, #list do
						for j = 1, #list do
							if i ~= j then lcs[#lcs + 1] = { segment0 = list[i], lane0 = 1, segment1 = list[j], lane1 = 2, withRoad = true, withTram = false } end
						end
					end
					return { laneConnections = lcs, crosswalks = { list[1] } }
				end
			end,
			terrain = { getHeightAt = function() return 0 end },
			util = {
				getPlayer = function() return 7 end,
				-- the engine's octree matches an edge by its position (the midpoint), not its extent
				-- (docs/findings/roads.md "Octree edge search matches the edge's position"): as test_showcase's fake
				octree = { findEntitiesInCircle = function(c, r, ct)
					eq(ct, "BASE_EDGE")
					local out = {}
					for e, ed in pairs(edges) do
						local p0, p1 = nodes[ed.n0], nodes[ed.n1]
						local mx, my = (p0.x + p1.x) / 2, (p0.y + p1.y) / 2
						if (mx - c.x) ^ 2 + (my - c.y) ^ 2 <= r * r then out[#out + 1] = e end
					end
					table.sort(out)
					return out
				end },
				proposal = {
					createTrafficLightProposal = function(node, tlc, pref)
						return { streetProposal = {}, lights = { node = node, pref = pref } }
					end,
					makeProposalData = function(p)
					local ce = p.constructionsToAdd and p.constructionsToAdd[1]
					local bad = ce and refuseCheck(ce)
					return { errorState = { critical = bad and true or false, messages = bad and { bad } or {} } }
				end },
				construction = { getGlobalConstructionParams = function() return { year = 1990 } end },
			},
			system = {
				streetSystem = { getNode2StreetEdgeMap = node2edges },
				streetConnectorSystem = { getConstructionEntityForNode = function() return -1 end },
			},
		},
	}
end

--- Plays the engine for a construction: a cross of plain arms (ring) or a highway (two one-way
--- carriageways along local x, a two-way cross road along local y), in world space by its transf.
local function buildJunction(ce)
	local m = ce.transf
	local ux, uy = m[1][1], m[1][2]   -- local x in world
	local vx, vy = m[2][1], m[2][2]   -- local y in world
	local ox, oy = m[4][1], m[4][2]
	local function at(lx, ly) return newNode(ox + ux * lx + vx * ly, oy + uy * lx + vy * ly) end
	if ce.fileName:find("parclo", 1, true) then
		-- eastbound (y = -10): west end -> centre -> east end; westbound (y = +10) the other way
		local w1, c1, e1 = at(-300, -10), at(0, -10), at(300, -10)
		local cw = { newEdge(w1, c1), newEdge(c1, e1) }
		local e2, c2, w2 = at(300, 10), at(0, 10), at(-300, 10)
		cw[3], cw[4] = newEdge(e2, c2), newEdge(c2, w2)
		for _, e in ipairs(cw) do edges[e].lanes = ONE_WAY end
		local s, c3, n = at(0, -150), at(0, 0), at(0, 150)
		edges[newEdge(s, c3)].lanes = TWO_WAY
		edges[newEdge(c3, n)].lanes = TWO_WAY
	elseif ce.fileName:find("square_stress_test_crossing", 1, true) then
		-- our crossing: arms 60 m along local +-x, side +y (T) or +-y (X)
		local c = at(0, 0)
		local arms = { { 60, 0 }, { -60, 0 }, { 0, 60 } }
		if ce.params.sqst_x_shape ~= 2 then arms[#arms + 1] = { 0, -60 } end
		for _, d in ipairs(arms) do newEdge(c, at(d[1], d[2])) end
	else
		local c = at(0, 0)
		for _, d in ipairs({ { 100, 0 }, { 0, 100 }, { -100, 0 }, { 0, -100 } }) do newEdge(c, at(d[1], d[2])) end
	end
end

--- A small town street at each grid point: a centre and four dead ends 200 m out.
local function townStreets(points)
	for _, p in ipairs(points) do
		local c = newNode(p.x, p.y)
		for _, d in ipairs({ { 200, 0 }, { 0, 200 }, { -200, 0 }, { 0, -200 } }) do newEdge(c, newNode(p.x + d[1], p.y + d[2])) end
	end
end

local rt, jn, gridOpts
local failCmd
local routeCalls   -- stress_buslines.addRouteLines calls (Traffic = Bus lines)
before_each(function()
	T, sent, nodes, edges, nextId = 0, {}, {}, {}, 1000
	refuseCheck = function() return nil end
	failCmd = nil
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	gridOpts = nil
	routeCalls = {}
	stub_module("square_stress_test::/stress/gui/stress_buslines.tl", {
		addRouteLines = function(name, title, routes)
			routeCalls[#routeCalls + 1] = { name = name, title = title, routes = routes }
			return #routes
		end,
	})
	stub_module("square_stress_test::/stress/gui/stress_towns.tl", {
		createGrid = function(opts, onDone)
			gridOpts = opts
			local pts = logic.gridPositions(0, 0, opts.cols, opts.rows, opts.spacing)
			if opts.points then
				pts = {}
				for k, q in ipairs(opts.points) do pts[k] = { x = (opts.cx or 0) + q.x, y = (opts.cy or 0) + q.y, name = q.name } end
			end
			townStreets(pts)
			created = {}
			for i = 1, #pts do created[i] = 500 + i end
			onDone(created, pts)
		end,
	})
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	jn = ug_require "square_stress_test::/stress/gui/stress_junctions.tl"
end)

local function logText()
	local out = {}
	for _, e in ipairs(log_entries()) do out[#out + 1] = e.msg end
	return table.concat(out, "\n")
end

--- Runs frames, answering every command: constructions are built, links succeed.
local function run(rounds)
	for _ = 1, rounds do
		T = T + 600000
		rt.tick()
		for _, s in ipairs(sent) do
			if not s.answered then
				s.answered = true
				local ce = s.cmd.p.constructionsToAdd and s.cmd.p.constructionsToAdd[1]
				local fail = failCmd ~= nil and failCmd(s.cmd)
				if ce and not fail then buildJunction(ce) end
				s.cb(s.cmd, not fail)
			end
		end
	end
end

--- Wraps rt.later: every delayed step queued, with its name, delay and the time (T) it was queued.
local function recordLater()
	local calls = {}
	local later = rt.later
	rt.later = function(name, ms, fn)
		calls[#calls + 1] = { name = name, ms = ms, t = T }
		return later(name, ms, fn)
	end
	return calls
end

--- The names of the rt.later calls, in order.
local function laterNames(calls)
	local out = {}
	for k, c in ipairs(calls) do out[k] = c.name end
	return out
end

--- The gaps (us) between consecutive construction sends, and the gap from the last one to the first
--- link sent after it.
local function buildGaps()
	local gaps, last, linkAfter = {}, nil, nil
	for _, x in ipairs(sent) do
		if x.cmd.p.constructionsToAdd then
			if last then gaps[#gaps + 1] = x.t - last end
			last = x.t
			linkAfter = nil
		elseif linkAfter == nil and last and x.cmd.p.streetProposal.edgesToAdd then
			linkAfter = x.t - last
		end
	end
	return gaps, linkAfter
end

local function constructions()
	local out = {}
	for _, s in ipairs(sent) do
		local ce = s.cmd.p.constructionsToAdd and s.cmd.p.constructionsToAdd[1]
		if ce then out[#out + 1] = ce end
	end
	return out
end

local function links()
	local out = {}
	for _, s in ipairs(sent) do
		if s.cmd.p.streetProposal.edgesToAdd then out[#out + 1] = s.cmd.p.streetProposal end
	end
	return out
end

test("available: yes when the roundabout construction resolves", function()
	eq(jn.available(), true)
end)

test("not available: the hint path; build logs and does nothing", function()
	api.res.constructionRep.find = function() return -1 end
	eq(jn.available(), false)
	jn.build()
	eq(gridOpts, nil)
	ok(table.concat(rt.recent, "\n"):find("Constructions not found", 1, true))
	eq(#rt.warnings, 1, "shown in a dialog")
end)

test("roundabouts set: 3x3 towns, 4 junctions at the cell centres, 45 deg +0 transform, 16 links", function()
	jn.ui.set = 2
	jn.build()
	eq(gridOpts.cols, 3)
	eq(gridOpts.rows, 3)
	eq(gridOpts.connect, 1) -- no town-to-town roads
	eq(gridOpts.spacing, logic.JUNCTION_SPACINGS[1])
	run(60)
	local cons = constructions()
	eq(#cons, 4)
	eq(cons[1].fileName, "square_roundabouts::/infrastructure/street_construction/square_roundabouts.con")
	eq(cons[3].params.sqrb_ch_layout, 2)
	eq(cons[1].params.year, 1990)
	near(cons[1].transf[1][1], math.sqrt(0.5))
	near(cons[1].transf[2][1], -math.sqrt(0.5))
	eq(1 / cons[1].transf[1][3], math.huge) -- +0, never -0
	near(cons[1].transf[4][1], -1000)
	near(cons[1].transf[4][2], -1000)
	local l = links()
	eq(#l, 16)
	local first = l[1]
	for k, seg in ipairs(first.edgesToAdd) do eq(seg.entity, -k) end
	for k, n in ipairs(first.nodesToAdd) do eq(n.entity, -(#first.edgesToAdd + k)) end
	-- The link never ends on an existing node (they keep their old, empty lane setup: the dead-end
	-- sign in game): the town node and the arm end are removed and replaced by new nodes, their edges
	-- by copies, and the copies' far nodes get their lane connections re-pointed (remove + add).
	eq(#first.nodesToRemove, 2)
	eq(#first.edgesToRemove, 2) -- the town dead end's edge and the arm's edge
	for _, seg in ipairs(first.edgesToAdd) do
		ok(seg.comp.node0 < 0 or seg.comp.node1 < 0, "every added edge touches a new node")
		for _, gone in ipairs(first.nodesToRemove) do
			ok(seg.comp.node0 ~= gone and seg.comp.node1 ~= gone, "no edge on a removed node")
		end
	end
	eq(#first.nodeConfigsToRemove, 2)
	-- the two far nodes (re-pointed) and every new node (the replacements and the link's pieces)
	eq(#first.nodeConfigsToAdd, 2 + #first.nodesToAdd)
	for _, entry in ipairs(first.nodeConfigsToAdd) do
		local removedEdges = {}
		for _, e in ipairs(first.edgesToRemove) do removedEdges[e] = true end
		ok(entry.comp.laneConnections[1].ctor, "rebuilt with LaneConnection.new")
		for _, lc in ipairs(entry.comp.laneConnections) do
			ok(not removedEdges[lc.segment0] and not removedEdges[lc.segment1], "re-pointed at the copies")
		end
		ok(not removedEdges[(entry.comp.crosswalks or {})[1] or 0], "crosswalk re-pointed")
	end
	local all = table.concat(rt.recent, "\n")
	ok(all:find("junction_test summary junctions=4 built=4 refused=0 in_line built=0 refused=0 arms linked=16 unlinked=0", 1, true), all)
	-- every node of every link has a config: new ones (replacements, pieces) and the re-pointed far nodes
	for k, sp in ipairs(l) do eq(cfgProblems(sp), {}, "link " .. k) end
	-- the Junction test's links are not locked (only the Showcase towns' are)
	for k, sp in ipairs(l) do
		for _, seg in ipairs(sp.edgesToAdd) do ok(seg.comp.roadDevelopmentLocked ~= true, "link " .. k) end
	end
	-- the replaced town dead end's new node: its edge's copy and the link's piece, both ways (a.1 > b.2)
	local townRef
	for _, seg in ipairs(first.edgesToAdd) do
		if seg.comp.tag == "edge" .. first.edgesToRemove[1] then
			townRef = seg.comp.node0 < 0 and seg.comp.node0 or seg.comp.node1
		end
	end
	ok(townRef ~= nil, "the town node's new node")
	for _, entry in ipairs(first.nodeConfigsToAdd) do
		if entry.entity == townRef then
			eq(#entry.comp.laneConnections, 2)
			for _, lc in ipairs(entry.comp.laneConnections) do ok(lc.lane0 == 1 and lc.lane1 == 2 and lc.ctor, "a.1 > b.2") end
		end
	end
end)

test("highway pair: both carriageways meet in one new node, each in its own direction", function()
	jn.ui.set = 3
	jn.build()
	run(80)
	local cons = constructions()
	eq(#cons, 6)
	-- the first parclo's links: find a link that starts with two short carriageway edges
	-- a merged link: the town node + both carriageway ends replaced (3 nodes removed)
	local pair
	for _, p in ipairs(links()) do
		if #p.nodesToRemove == 3 then pair = p break end
	end
	ok(pair ~= nil, "a merged carriageway link")
	-- the merge node: the new node with exactly three new edges (two carriageways + the road on)
	local merge, mergeEdges
	for _, n in ipairs(pair.nodesToAdd) do
		local at = {}
		for _, seg in ipairs(pair.edgesToAdd) do
			if seg.comp.node0 == n.entity or seg.comp.node1 == n.entity then at[#at + 1] = seg.comp end
		end
		if #at == 3 then merge, mergeEdges = n.entity, at end
	end
	ok(merge ~= nil, "merge node")
	local into, outOf = 0, 0
	for _, e in ipairs(mergeEdges) do
		if e.node1 == merge then into = into + 1 else outOf = outOf + 1 end
	end
	-- one carriageway flows into the merge node; the other and the road on leave it
	eq({ into, outOf }, { 1, 2 })
	-- its config: the arriving carriageway's two lanes into the road on (outer lane first), the road on into
	-- the leaving carriageway, never carriageway into carriageway (a U-turn)
	local cfg
	for _, e in ipairs(pair.nodeConfigsToAdd) do if e.entity == merge then cfg = e end end
	ok(cfg ~= nil, "merge node config")
	local inSeg, outSeg, road
	for _, seg in ipairs(pair.edgesToAdd) do
		if seg.comp.node1 == merge and seg.comp.laneConfigs == ONE_WAY then inSeg = seg.entity end
		if seg.comp.node0 == merge and seg.comp.laneConfigs == ONE_WAY then outSeg = seg.entity end
		if (seg.comp.node0 == merge or seg.comp.node1 == merge) and seg.comp.laneConfigs ~= ONE_WAY then road = seg.entity end
	end
	ok(inSeg and outSeg and road, "three segments")
	local got = {}
	for _, lc in ipairs(cfg.comp.laneConnections) do got[#got + 1] = string.format("%s.%d>%s.%d", lc.segment0 == inSeg and "in" or lc.segment0 == outSeg and "out" or "road", lc.lane0,
		lc.segment1 == inSeg and "in" or lc.segment1 == outSeg and "out" or "road", lc.lane1) end
	table.sort(got)
	eq(got, { "in.1>road.2", "road.1>out.2" })
	-- a carriageway's own pieces continue lane by lane (i > m + 1 - i)
	local pieces = 0
	for _, e in ipairs(pair.nodeConfigsToAdd) do
		local at = 0
		for _, seg in ipairs(pair.edgesToAdd) do
			if (seg.comp.node0 == e.entity or seg.comp.node1 == e.entity) and seg.comp.laneConfigs == ONE_WAY then at = at + 1 end
		end
		if e.entity < 0 and e.entity ~= merge and at == 2 then
			local t = {}
			for _, lc in ipairs(e.comp.laneConnections) do t[#t + 1] = lc.lane0 .. ">" .. lc.lane1 end
			table.sort(t)
			eq(t, { "1>2", "2>1" }, "one-way piece node " .. e.entity)
			pieces = pieces + 1
		end
	end
	ok(pieces >= 2, "carriageway piece nodes: " .. pieces)
	for k, sp in ipairs(links()) do eq(cfgProblems(sp), {}, "link " .. k) end
	-- the highway runs on to the town: the merge node is ~60 m from the replaced town node, and each
	-- carriageway is several pieces long (copies of its own one-way edge)
	local mpos
	for _, n in ipairs(pair.nodesToAdd) do if n.entity == merge then mpos = n.comp.position end end
	local townNode = pair.nodesToRemove[1]
	local tp = nodes[townNode]
	near(math.sqrt((mpos.x - tp.x) ^ 2 + (mpos.y - tp.y) ^ 2), 60, 0.01)
	-- per carriageway: the replaced end edge + 2+ run pieces + the taper; plus the town edge copy and the road on
	ok(#pair.edgesToAdd >= 8, "parallel carriageways: " .. #pair.edgesToAdd .. " edges")
	local all = table.concat(rt.recent, "\n")
	ok(all:find("built=6 refused=0", 1, true), all)
	ok(all:find("ends=6 arms=4 [", 1, true), all)
	ok(all:find("2->Grid", 1, true), all)
end)

local LARGE = "::/infrastructure/street/town/town_new_large.street_template"

--- The highway town links (town node + both carriageway ends replaced) and, per link, the tag of the
--- street its merge piece copies (the new edge from the merge node to the new town node).
local function mergePieces()
	local out = {}
	for _, p in ipairs(links()) do
		if #p.nodesToRemove == 3 then
			-- the new town node replaces nodesToRemove[1]: the new node at its position
			local tp = nodes[p.nodesToRemove[1]]
			local townRef
			for _, n in ipairs(p.nodesToAdd) do
				if math.abs(n.comp.position.x - tp.x) < 1e-6 and math.abs(n.comp.position.y - tp.y) < 1e-6 then townRef = n.entity end
			end
			local count = {}
			for _, seg in ipairs(p.edgesToAdd) do
				for _, n in ipairs({ seg.comp.node0, seg.comp.node1 }) do count[n] = (count[n] or 0) + 1 end
			end
			for _, seg in ipairs(p.edgesToAdd) do
				local a, b = seg.comp.node0, seg.comp.node1
				local other = a == townRef and b or (b == townRef and a or nil)
				if other ~= nil and count[other] == 3 then out[#out + 1] = { link = p, tag = seg.comp.tag } end
			end
		end
	end
	return out
end

test("highway links: town nodes on a large street are taken, and the last piece copies a large street", function()
	jn.ui.set = 3
	jn.build()
	-- in every town only the street to the east dead end is large
	local large = {}
	for e, ed in pairs(edges) do
		local a, b = nodes[ed.n0], nodes[ed.n1]
		if b.x - a.x > 199 then ed.template = LARGE large["edge" .. e] = ed.n1 end
	end
	run(80)
	local pieces = mergePieces()
	ok(#pieces > 0, "highway links")
	local atLarge = 0
	for _, m in ipairs(pieces) do
		ok(large[m.tag] ~= nil, "merge piece copies a large street: " .. m.tag)
		-- the first link into a town takes its east dead end; later ones (that end taken) a small one
		if m.link.nodesToRemove[1] == large[m.tag] then atLarge = atLarge + 1 end
	end
	ok(atLarge > 0 and atLarge >= #pieces / 2, atLarge .. " of " .. #pieces)
	ok(table.concat(rt.recent, "\n"):find("unlinked=0", 1, true))
end)

test("highway links: no large dead end -> the nearest large street is copied", function()
	jn.ui.set = 3
	jn.build()
	-- a triangle of large streets (no dead end) 300 m north of every town centre
	local tri, centres = {}, {}
	for id, n in pairs(nodes) do
		local deg = 0
		for _, ed in pairs(edges) do if ed.n0 == id or ed.n1 == id then deg = deg + 1 end end
		if deg == 4 then centres[#centres + 1] = { id = id, x = n.x, y = n.y } end
	end
	for _, p in ipairs(centres) do
		local a, b, c = newNode(p.x, p.y + 300), newNode(p.x + 100, p.y + 350), newNode(p.x - 100, p.y + 350)
		for _, ab in ipairs({ { a, b }, { b, c }, { c, a } }) do
			local e = newEdge(ab[1], ab[2])
			edges[e].template = LARGE
			tri["edge" .. e] = p
		end
	end
	run(80)
	local pieces = mergePieces()
	ok(#pieces > 0)
	for _, m in ipairs(pieces) do
		local p = tri[m.tag]
		ok(p ~= nil, "copies a large triangle street: " .. m.tag)
		local tp = nodes[m.link.nodesToRemove[1]]
		ok((tp.x - p.x) ^ 2 + (tp.y - p.y) ^ 2 < 300 * 300, "its own town's triangle")
	end
end)

test("highway links: no large street anywhere -> the last piece copies the town node's own street", function()
	jn.ui.set = 3
	jn.build()
	run(80)
	local pieces = mergePieces()
	ok(#pieces > 0)
	for _, m in ipairs(pieces) do eq(m.tag, "edge" .. m.link.edgesToRemove[1]) end
end)

test("road links: the whole link copies the arm's (country large) street, the town street only at its node", function()
	jn.ui.set = 2
	jn.build()
	run(60)
	local n = 0
	for _, p in ipairs(links()) do
		eq(#p.edgesToRemove, 2)
		local townEdge, armEdge = "edge" .. p.edgesToRemove[1], "edge" .. p.edgesToRemove[2]
		local town, arm = 0, 0
		for _, seg in ipairs(p.edgesToAdd) do
			if seg.comp.tag == townEdge then town = town + 1 elseif seg.comp.tag == armEdge then arm = arm + 1 end
		end
		eq(town, 1, "only the copy of the town node's own edge")
		ok(arm >= 3, "the arm's copy and the run to the town: " .. arm)
		eq(town + arm, #p.edgesToAdd)
		n = n + 1
	end
	eq(n, 16)
end)

test("a junction refused by the check is skipped and counted; the others still build", function()
	jn.ui.set = 2
	refuseCheck = function(ce) return ce.fileName:find("magic", 1, true) and "Collision" or nil end
	jn.build()
	run(60)
	eq(#constructions(), 3)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("Cell A2 Magic Roundabout at 1000,-1000 refused by the check: Collision", 1, true), all)
	ok(all:find("built=3 refused=1 in_line built=0 refused=0 arms linked=12", 1, true), all)
end)

test("in line: stops on each arm's line, turned to it, every one another layout, linked in a chain", function()
	jn.ui.set = 2       -- 4 roundabouts
	jn.ui.spacing = 2   -- 3 km
	jn.ui.inline = 2
	jn.build()
	run(1500)
	local cons = constructions()
	-- per arm: 2121 m cell centre -> town, arm end 100 m out; clear 250 + (525 + 250): free = 2021 - 1025
	-- = 996 m, pitch 400 -> 3 stops; 16 arms
	eq(#cons, 4 + 16 * 3)
	local stops = {}
	for k = 5, #cons do stops[#stops + 1] = cons[k] end
	-- the first arm's three stops: on one line, turned to it (local x = the line), different layouts
	local d = {}
	for k = 1, 3 do
		local m = stops[k].transf
		d[k] = { x = m[4][1], y = m[4][2], ux = m[1][1], uy = m[1][2] }
	end
	local lx, ly = d[3].x - d[1].x, d[3].y - d[1].y
	local len = math.sqrt(lx * lx + ly * ly)
	for k = 1, 3 do
		near(d[k].ux, lx / len, 1e-6)
		near(d[k].uy, ly / len, 1e-6)
	end
	near((d[2].x - d[1].x) * ly - (d[2].y - d[1].y) * lx, 0, 1e-3, "stop 2 on the line")
	ok(stops[1].name ~= stops[2].name and stops[2].name ~= stops[3].name, "layouts cycle")
	eq(stops[1].name, "SQST " .. logic.INLINE_ROAD[1].label)
	eq(stops[4].name, "SQST " .. logic.INLINE_ROAD[4].label, "the next arm continues the cycle")
	for _, ce in ipairs(stops) do
		for k, v in pairs(ce.params) do
			ok(type(v) == "number", k)
		end
		eq(ce.params.sqrb_arm_type or ce.params.sqrb_ch_main, 6, "country large arms")
	end
	-- links: per arm 3 stop links + 1 town link
	eq(#links(), 16 * 4)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("in_line built=48 refused=0 arms linked=64 unlinked=0", 1, true), all)
end)

test("junctions back to back, one settle, then their arms read and linked", function()
	jn.ui.set = 2
	local calls = recordLater()
	jn.build()
	run(60)
	eq(laterNames(calls), { "junction_test:settle" })
	eq(calls[1].ms, 3000)
	local gaps, linkAfter = buildGaps()
	eq(#gaps, 3)
	for _, g in ipairs(gaps) do ok(g <= 600000, "back to back: " .. g) end
	ok(linkAfter >= 3000000, "first link 3 s after the last build: " .. tostring(linkAfter))
	local all = logText()
	local settleAt = all:find("junction_test: 4 junctions built; reading their arms in 3 s", 1, true)
	ok(settleAt ~= nil, all)
	ok(all:find("Cell A1 Roundabout built ms=", 1, true) > settleAt, "arms read after the settle")
	ok(all:find("arms linked=16 unlinked=0", 1, true), all)
end)

test("in line: cells back to back, a settle, every stop back to back, one more settle, then the links", function()
	jn.ui.set = 2
	jn.ui.spacing = 2
	jn.ui.inline = 2
	local calls = recordLater()
	jn.build()
	run(1500)
	-- exactly one settle before the in-line stops are planned and one before the link phase
	eq(laterNames(calls), { "junction_test:settle", "junction_test:settle" })
	local gaps, linkAfter = buildGaps()
	eq(#gaps, 4 + 48 - 1)
	local long = 0
	for k, g in ipairs(gaps) do
		if g > 600000 then
			long = long + 1
			eq(k, 4, "the only wait: between the last cell junction and the first stop")
			ok(g >= 3000000, g)
		end
	end
	eq(long, 1)
	ok(linkAfter >= 3000000, "first link 3 s after the last stop: " .. tostring(linkAfter))
	-- every construction before the first link
	local firstLink
	for k, x in ipairs(sent) do
		if x.cmd.p.streetProposal.edgesToAdd and not firstLink then firstLink = k end
		if x.cmd.p.constructionsToAdd then ok(firstLink == nil, "construction after a link") end
	end
	local all = logText()
	ok(all:find("junction_test: 48 in-line junctions built; reading their arms in 3 s", 1, true), all)
	ok(all:find("in_line built=48 refused=0 arms linked=64 unlinked=0", 1, true), all)
end)

test("in line: a refused link retry is the only extra wait (3 s), the route is still linked", function()
	jn.ui.set = 2
	jn.ui.spacing = 2
	jn.ui.inline = 2
	local failed = 0
	failCmd = function(cmd)
		local sp = cmd.p.streetProposal
		if sp and sp.edgesToAdd and failed < 1 then
			failed = failed + 1
			return true
		end
		return false
	end
	local calls = recordLater()
	jn.build()
	run(2000)
	eq(laterNames(calls), { "junction_test:settle", "junction_test:settle", "junction_test:relink" })
	eq(calls[3].ms, 3000)
	local all = logText()
	ok(all:find("trying again in 3 s (2/3)", 1, true), all)
	ok(all:find("arms linked=64 unlinked=0", 1, true), all)
end)

test("the Junction test's build step stays well within Lua 5.1's 60 upvalues per function", function()
	local captured = {}
	local enqueue = rt.enqueue
	rt.enqueue = function(name, total, step, opts)
		captured[name] = step
		return enqueue(name, total, step, opts)
	end
	jn.ui.inline = 2
	jn.build()
	local step = captured.junction_test
	ok(step ~= nil)
	-- Lua 5.4 counts _ENV too (one above the game's count); keep 10 spare below the hard limit of 60
	local n = debug.getinfo(step, "u").nups
	local names = {}
	for k = 1, n do names[k] = debug.getupvalue(step, k) end
	ok(n <= 50, "upvalues: " .. n .. " (" .. table.concat(names, " ") .. ")")
end)

test("in line on highway arms: interchanges, carriageway pairs linked to pairs", function()
	jn.ui.set = 3       -- interchanges (the fake builds parclos as highways)
	jn.ui.spacing = 5   -- 8 km
	jn.ui.inline = 2
	jn.build()
	run(3000)
	local pairLinks = 0
	for _, sp in ipairs(links()) do
		if #sp.nodesToRemove == 4 then pairLinks = pairLinks + 1 end
	end
	ok(pairLinks > 0, "linkPairProposal used")
	for k, sp in ipairs(links()) do eq(cfgProblems(sp), {}, "link " .. k) end
	local names = {}
	for _, ce in ipairs(constructions()) do names[ce.name] = true end
	ok(names["SQST " .. logic.INLINE_HIGHWAY[1].label], "interchanges on the highway arms")
	ok(names["SQST " .. logic.INLINE_ROAD[1].label], "roundabouts on the cross-road arms")
	local all = table.concat(rt.recent, "\n")
	ok(all:find("unlinked=0", 1, true), all)
end)

test("in line: a refused stop is left out, the chain links past it", function()
	jn.ui.set = 2
	jn.ui.spacing = 2
	jn.ui.inline = 2
	refuseCheck = function(ce) return ce.name == "SQST " .. logic.INLINE_ROAD[2].label and "Collision" or nil end
	jn.build()
	run(400)
	-- the refusals come in the build phase, long before the summary: the whole log, not the window's last lines
	local all = logText()
	ok(all:find("refused by the check at 5 spots: Collision", 1, true), all)
	ok(all:find("unlinked=0", 1, true), all)
end)

test("loading the module calls no engine API", function()
	set_global("api", nil)
	reset_modules()
	stub_module("square_stress_test::/stress/gui/stress_towns.tl", {})
	ug_require "square_stress_test::/stress/gui/stress_junctions.tl"
end)

test("in line: a stop refused at its spot is built a little further along the route", function()
	jn.ui.set = 2
	jn.ui.spacing = 2
	jn.ui.inline = 2
	local seen = 0
	refuseCheck = function(ce)
		if ce.name ~= "SQST " .. logic.INLINE_ROAD[1].label then return nil end
		seen = seen + 1
		return seen == 1 and "Construction Not Possible" or nil
	end
	jn.build()
	run(1500)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("in_line built=48 refused=0", 1, true), all)
	-- the first stop sits 80 m back along the route from where the second spot was planned
	local firstStop
	for _, ce in ipairs(constructions()) do
		if ce.name == "SQST " .. logic.INLINE_ROAD[1].label then firstStop = ce break end
	end
	ok(firstStop ~= nil)
end)

test("in line: a stop shifted towards the previous one keeps its own arms (scan circles overlap)", function()
	jn.ui.set = 2
	jn.ui.spacing = 3   -- 4 km: 5 stops per arm, 426 m apart
	jn.ui.inline = 2
	-- the first arm's stop 2 is refused at its spot, -80 m and +80 m: built 160 m back towards stop 1
	-- (426 - 160 = 266 m apart; its back arm end 166 m from stop 1, inside stop 1's 190 m scan circle)
	local seen = 0
	refuseCheck = function(ce)
		if ce.name ~= "SQST " .. logic.INLINE_ROAD[2].label then return nil end
		seen = seen + 1
		return seen <= 3 and "Construction Not Possible" or nil
	end
	jn.build()
	run(1500)
	local all = logText()
	ok(all:find("placed -160m along the route", 1, true), all)
	-- every stop (the fake builds a centre and 4 arm ends) read exactly its own nodes
	local stopLines = 0
	for line in all:gmatch("[^\n]+") do
		if line:find(" in line %d+/%d+ .- built ms=") then
			stopLines = stopLines + 1
			ok(line:find("nodes=5 ends=4 arms=4 through=yes", 1, true), line)
		end
	end
	eq(stopLines, 80)
	-- every stop link joins a single end to a single end (two nodes replaced)
	for _, sp in ipairs(links()) do ok(#sp.nodesToRemove == 2, "link replaces " .. #sp.nodesToRemove .. " nodes") end
	ok(all:find("in_line built=80 refused=0 arms linked=96 unlinked=0", 1, true), all)
end)

test("in line: a refused link into a stop is tried again later; the route still reaches the town", function()
	jn.ui.set = 2
	jn.ui.spacing = 2
	jn.ui.inline = 2
	local failed = 0
	failCmd = function(cmd)
		local sp = cmd.p.streetProposal
		-- the first two links (stop links come first on an arm's route)
		if sp and sp.edgesToAdd and failed < 2 then
			failed = failed + 1
			return true
		end
		return false
	end
	jn.build()
	run(2000)
	eq(failed, 2)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("arms linked=64 unlinked=0", 1, true), all)
end)


test("Lights Off: the lights go off at every junction node built", function()
	jn.ui.set = 2       -- 4 roundabouts (the fake builds a 4-arm cross: one junction node each)
	jn.ui.lights = 2
	jn.build()
	run(1500)
	local n = 0
	for _, x in ipairs(sent) do
		if x.cmd.p.lights then
			n = n + 1
			eq(x.cmd.p.lights.pref, 1)
		end
	end
	eq(n, 4)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("unlinked=0", 1, true), all)
end)

---------------------------------------------------------------------------
-- Crossing test

test("crossingLayout: 9 grid crossings of every lane pair, 12 collector junctions, 32 links, 4 towns", function()
	local L = logic.crossingLayout(0, 0, 1)
	eq(#L.junctions, 21)
	eq(#L.links, 32)
	eq(#L.towns, 4)
	local byId, pairs_ = {}, {}
	for _, j in ipairs(L.junctions) do byId[j.id] = j end
	for r = 1, 3 do
		for c = 1, 3 do
			local j = byId["x" .. r .. c]
			eq(j.shape, 1)
			pairs_[j.main .. "x" .. j.side] = true
		end
	end
	local n = 0
	for _ in pairs(pairs_) do n = n + 1 end
	eq(n, 9, "every lane-count pair once")
	-- rows north -> south, columns west -> east
	eq(byId.x11.y, logic.CROSSING_D)
	eq(byId.x11.x, -logic.CROSSING_D)
	eq(byId.x11.main, 3)
	eq(byId.x33.side, 1)
	-- collectors: T at the ends, a crossing in the middle, side arm (local +y) towards the grid
	for _, side in ipairs({ "w", "e", "n", "s" }) do
		eq(byId[side .. "1"].shape, 2)
		eq(byId[side .. "2"].shape, 1)
		eq(byId[side .. "3"].shape, 2)
		local j = byId[side .. "1"]
		local yx, yy = -math.sin(j.angle), math.cos(j.angle)
		ok(yx * (0 - j.x) + yy * (0 - j.y) > 0, side .. ": side arm points at the grid")
	end
	-- every link joins two junctions that exist, along a straight line in its arms' directions
	for _, l in ipairs(L.links) do
		local a, b = byId[l.a], byId[l.b]
		ok(a ~= nil and b ~= nil, l.a .. "-" .. l.b)
		local d = logic.CROSSING_DIRS[l.aDir]
		local dx, dy = b.x - a.x, b.y - a.y
		ok(math.abs(dx * d[2] - dy * d[1]) < 1e-6 and dx * d[1] + dy * d[2] > 0, l.a .. "." .. l.aDir)
		local e = logic.CROSSING_DIRS[l.bDir]
		eq(e[1], -d[1])
		eq(e[2], -d[2])
	end
	-- towns beyond the collectors' middle crossings, in the direction of the free arm
	for _, t in ipairs(L.towns) do
		local j = byId[t.from]
		local d = logic.CROSSING_DIRS[t.dir]
		near((t.x - j.x) * d[1] + (t.y - j.y) * d[2], logic.CROSSING_G, 1e-6)
		ok(t.name:sub(1, 5) == "Grid ", "Remove towns > Grid towns finds it")
	end
	-- scaled and moved
	local S = logic.crossingLayout(100, 200, 0.5)
	near(S.junctions[1].x, 100 - logic.CROSSING_D / 2, 1e-6)
end)

test("Crossing test: 4 towns, 21 crossings with arms by direction, 32 links + 4 town links, lights off", function()
	-- the fake builds the crossing as its arms really are (X / T, turned by the transform)
	jn.crossUi.lights = 1
	jn.buildCrossings()
	run(3000)
	local cons = constructions()
	eq(#cons, 21)
	for _, ce in ipairs(cons) do
		eq(ce.fileName, "square_stress_test::/infrastructure/street_construction/square_stress_test_crossing.con")
	end
	eq(#gridOpts.points, 4)
	local lightN = 0
	for _, x in ipairs(sent) do if x.cmd.p.lights then lightN = lightN + 1 end end
	eq(lightN, 21, "one junction node per crossing")
	local all = table.concat(rt.recent, "\n")
	ok(all:find("crossing_test summary crossings=21 built=21 refused=0 links=36 linked=36 failed=0", 1, true), all)
end)

---------------------------------------------------------------------------
-- Traffic = Bus lines (square_smart_lanes PHASE7.md step 6)

test("cellRoutes: both diagonals of every cell whose two corner arms reached their towns, capped", function()
	local cells = {
		{ name = "Cell A1", corners = { 1, 2, 5, 4 } },
		{ name = "Cell A2", corners = { 2, 3, 6, 5 } },
	}
	eq(logic.cellRoutes(cells, {}, 40), {})
	eq(logic.cellRoutes(cells, { ["Cell A1"] = { [1] = true, [2] = true, [3] = true, [4] = true } }, 40), { { 1, 5, 1 }, { 2, 4, 1 } })
	-- SE missing in A2: only its SW-NE diagonal
	eq(logic.cellRoutes(cells, { ["Cell A1"] = { [1] = true, [3] = true }, ["Cell A2"] = { [1] = true, [3] = true, [4] = true } }, 40),
		{ { 1, 5, 1 }, { 2, 6, 2 } })
	local all = { [1] = true, [2] = true, [3] = true, [4] = true }
	eq(#logic.cellRoutes(cells, { ["Cell A1"] = all, ["Cell A2"] = all }, 3), 3, "cap")
	eq(logic.cellRoutes(nil, nil, 40), {})
end)

test("crossingRoutes: straight W-E, N-S, then turning W-N, E-S; only linked towns", function()
	eq(logic.crossingRoutes({ true, true, true, true }), { { 1, 2 }, { 3, 4 }, { 1, 3 }, { 2, 4 } })
	eq(logic.crossingRoutes({ [1] = true, [2] = true, [4] = true }), { { 1, 2 }, { 2, 4 } })
	eq(logic.crossingRoutes({}), {})
	eq(logic.crossingRoutes(nil), {})
end)

test("testSummary: built and links, the bus line clause only with Traffic on", function()
	eq(logic.testSummary("Junction test", 4, 4, "junctions", 16, 16, nil), "Junction test done: 4 of 4 junctions built, 16 of 16 links.")
	eq(logic.testSummary("Crossing test", 20, 21, "crossings", 30, 36, 4),
		"Crossing test done: 20 of 21 crossings built, 30 of 36 links; 4 bus lines queued.")
	eq(logic.testSummary("Junction test", 1, 1, "junctions", 1, 4, 1), "Junction test done: 1 of 1 junctions built, 1 of 4 links; 1 bus line queued.")
	ok(logic.testSummary("Junction test", 1, 1, "junctions", 0, 4, 0):find("no bus lines", 1, true))
end)

test("Junction test, Traffic Off: the summary line, no bus lines", function()
	jn.ui.set, jn.ui.traffic = 2, 1
	jn.build()
	run(80)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("[SQST] Junction test done: 4 of 4 junctions built, 16 of 16 links.", 1, true), all)
	eq(#routeCalls, 0)
end)

test("Junction test, Traffic Bus lines: two diagonal lines per junction, a few seconds after the last link", function()
	jn.ui.set, jn.ui.traffic = 2, 2
	jn.build()
	run(60)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("[SQST] Junction test done: 4 of 4 junctions built, 16 of 16 links; 8 bus lines queued.", 1, true), all)
	run(20)
	eq(#routeCalls, 1)
	local c = routeCalls[1]
	eq(c.name, "bus_lines_junction_test")
	eq(c.title, "Junction test")
	eq(#c.routes, 8)
	-- Cell A1 of the 3 x 3 grid: corners 1 (SW), 2 (SE), 5 (NE), 4 (NW); towns 500 + grid index
	local r = c.routes[1]
	eq({ r.a.id, r.b.id }, { 501, 505 })
	eq({ c.routes[2].a.id, c.routes[2].b.id }, { 502, 504 })
	ok(r.label:find("^Cell A1 "), r.label)
	ok(r.a.x ~= nil and r.b.y ~= nil)
	-- wide grid streets (the default): each town's grid half-size keeps the stops and depots on it
	eq(r.a.half, logic.gridHalfOfSize(jn.ui.size))
	eq(r.zones, nil)
end)

test("Junction test, Traffic Bus lines: an arm whose town link is refused drops that diagonal only", function()
	jn.ui.set, jn.ui.traffic = 2, 2
	-- every link into the first town (grid point 1, the SW corner of Cell A1 only) is refused
	failCmd = function(cmd)
		local sp = cmd.p.streetProposal
		if not sp or not sp.nodesToRemove or cmd.p.constructionsToAdd then return false end
		for _, n in ipairs(sp.nodesToRemove) do
			local p = nodes[n]
			if p and (p.x + 2000) ^ 2 + (p.y + 2000) ^ 2 < 400 * 400 then return true end
		end
		return false
	end
	jn.build()
	run(100)
	eq(#routeCalls, 1)
	eq(#routeCalls[1].routes, 7)
	for _, r in ipairs(routeCalls[1].routes) do ok(r.a.id ~= 501 and r.b.id ~= 501, r.label) end
end)

test("Crossing test, Traffic Bus lines: 4 lines between its towns after the build", function()
	jn.crossUi.traffic = 2
	jn.buildCrossings()
	run(3000)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("[SQST] Crossing test done: 21 of 21 crossings built, 36 of 36 links; 4 bus lines queued.", 1, true), all)
	eq(#routeCalls, 1)
	local c = routeCalls[1]
	eq(c.name, "bus_lines_crossing_test")
	local pairs_ = {}
	for _, r in ipairs(c.routes) do pairs_[#pairs_ + 1] = { r.a.id, r.b.id } end
	eq(pairs_, { { 501, 502 }, { 503, 504 }, { 501, 503 }, { 502, 504 } })
	ok(c.routes[1].label == "Grid W -> Grid E", c.routes[1].label)
end)

test("Crossing test, Traffic Off: summary only", function()
	jn.crossUi.traffic = 1
	jn.buildCrossings()
	run(3000)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("[SQST] Crossing test done: 21 of 21 crossings built, 36 of 36 links.", 1, true), all)
	eq(#routeCalls, 0)
end)

test("busy: a test pressed while the other test or its pending bus lines run is refused, nothing stacked", function()
	jn.crossUi.traffic = 1
	jn.buildCrossings()
	jn.build()
	local all = table.concat(rt.recent, "\n")
	ok(all:find("Junction test: A test is already running (crossing_test). Wait for it to finish.", 1, true), all)
	run(3000)
	-- Junction test with bus lines: during the few seconds before they start, both tests refuse
	jn.ui.set, jn.ui.traffic = 2, 2
	jn.build()
	for _ = 1, 200 do
		if table.concat(rt.recent, "\n"):find("Junction test done:", 1, true) then break end
		run(1)
	end
	eq(#routeCalls, 0, "bus lines still waiting")
	run(2)   -- the test job is done; only the delayed bus lines are queued
	eq(#routeCalls, 0, "bus lines still waiting")
	jn.build()
	jn.buildCrossings()
	all = table.concat(rt.recent, "\n")
	ok(all:find("Junction test: A test is already running (junction_test", 1, true), all)
	ok(all:find("Crossing test: A test is already running (junction_test", 1, true), all)
	run(20)
	eq(#routeCalls, 1)
	all = table.concat(rt.recent, "\n")
	local refusedAt = all:find("Crossing test: A test is already running (junction_test", 1, true)
	ok(refusedAt and not all:find("junction_test: 4 junctions", refusedAt, true), "no second test started: " .. all)
	ok(not all:find("crossing_test: 21 crossings", refusedAt, true), all)
end)
