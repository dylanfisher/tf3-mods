-- bb_gather against a fake api: octree hits → descriptors → classify, with the touch test,
-- origin-in-circle, industry-road protection and pcall on failing engine reads (PLAN Phase 2).

local CT = {
	BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", CONSTRUCTION = "CONSTRUCTION",
	PLAYER_OWNED = "PLAYER_OWNED", PLAYER = "PLAYER", SUBCONSTRUCTION = "SUBCONSTRUCTION",
}
local ME, HQ = 1, 900

local world
local function reset()
	world = { comps = {}, segs = {}, edgeCon = {}, nodeCon = {}, broken = {}, queries = 0, groupOf = {} }
end

local function put(e, t, v)
	world.comps[e] = world.comps[e] or {}
	world.comps[e][t] = v
end

local function transf(x, y)
	return { getTransl = function(_) return { x = x, y = y, z = 0 } end }
end

-- Straight edge (x0,y0)-(x1,y1), position0 used as the octree point unless overridden.
local function addEdge(e, x0, y0, x1, y1, opts)
	opts = opts or {}
	put(e, CT.BASE_EDGE, {
		type = opts.tunnel and "TUNNEL" or "NORMAL",
		objects = opts.objects or {},
		node0 = opts.node0 or -1, node1 = opts.node1 or -1,
		position0 = { x = x0, y = y0, z = 0 }, position1 = { x = x1, y = y1, z = 0 },
		tangent0 = { x = x1 - x0, y = y1 - y0, z = 0 }, tangent1 = { x = x1 - x0, y = y1 - y0, z = 0 },
	})
	if opts.street ~= false then put(e, CT.BASE_EDGE_STREET, {}) end
	if opts.owner then put(e, CT.PLAYER_OWNED, { player = opts.owner }) end
end

local function addCon(e, x, y, opts)
	opts = opts or {}
	put(e, CT.CONSTRUCTION, {
		transf = transf(x, y),
		stations = opts.stations or {}, depots = opts.depots or {}, industries = opts.industries or {},
		townBuildings = opts.townBuildings or {}, frozenEdges = opts.frozenEdges or {}, frozenNodes = {},
	})
	if opts.owner then put(e, CT.PLAYER_OWNED, { player = opts.owner }) end
end

local function own(e, player) put(e, CT.PLAYER_OWNED, { player = player }) end

-- Octree fake: "position" semantics (an entity is hit when its reference point is in the circle):
-- edges by their midpoint, constructions by their origin. This is the worst case EDGE_MARGIN covers.
local function refPoint(e)
	local c = world.comps[e]
	if c[CT.BASE_EDGE] then
		local b = c[CT.BASE_EDGE]
		return (b.position0.x + b.position1.x) / 2, (b.position0.y + b.position1.y) / 2
	end
	local t = c[CT.CONSTRUCTION].transf:getTransl()
	return t.x, t.y
end

local fakeApi = {
	type = {
		ComponentType = CT,
		enum = { BaseEdgeType = { NORMAL = "NORMAL", BRIDGE = "BRIDGE", TUNNEL = "TUNNEL" } },
		Vec2f = { new = function(x, y) return { x = x, y = y } end },
	},
	engine = {
		entityExists = function(e) return world.comps[e] ~= nil end,
		getComponent = function(e, t)
			if world.broken[e] then error("boom") end
			return world.comps[e] and world.comps[e][t] or nil
		end,
		util = {
			getPlayer = function() return ME end,
			octree = {
				findEntitiesInCircle = function(c, r, t)
					world.queries = world.queries + 1
					local out = {}
					for e, comps in pairs(world.comps) do
						if comps[t] then
							local x, y = refPoint(e)
							if (x - c.x) ^ 2 + (y - c.y) ^ 2 <= r * r then out[#out + 1] = e end
						end
					end
					for _, g in ipairs(world.ghosts or {}) do if g.t == t then out[#out + 1] = g.e end end
					table.sort(out)
					return out
				end,
			},
			construction = {
				findSegmentsToDelete = function(con, keep)
					assert(keep == false, "must include industry roads")
					return world.segs[con] or {}
				end,
			},
		},
		system = {
			streetConnectorSystem = {
				getConstructionEntityForEdge = function(e) return world.edgeCon[e] or -1 end,
				getConstructionEntityForNode = function(n) return world.nodeCon[n] or -1 end,
				getConstructionEntityForSubconstruction = function(e) return -1 end,
			},
			stationGroupSystem = {
				getStationGroup = function(st) return world.groupOf[st] or -1 end,
			},
		},
	},
}

before_each(function()
	reset()
	set_global("api", fakeApi)
	put(ME, CT.PLAYER, { headquarters = HQ })
end)

local gather = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_gather.tl"
local sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl"
local brush = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_brush.tl"

local function allOn()
	return { roads = true, tracks = true, stations = true, assets = true,
		townBuildings = true, underground = true }
end

local function byEntity(res)
	local m = {}
	for _, c in ipairs(res.candidates) do m[c.entity] = c end
	return m
end

test("context: player and HQ", function()
	eq(gather.context(), { player = ME, hq = HQ })
end)

test("long edge found by its middle with a small brush (margin + touch test)", function()
	-- 180 m edge; brush 5 m at x = 20 (70 m from the midpoint the fake octree uses).
	addEdge(10, 0, 0, 180, 0, { owner = ME })
	ok(90 - 20 <= brush.EDGE_MARGIN, "test assumes the margin covers 70 m")
	local res = gather.sample(20, 0, 5, allOn(), gather.context(), gather.newCache())
	local m = byEntity(res)
	ok(m[10] ~= nil, "edge hit")
	eq(m[10].reason, nil)
	eq(m[10].kind, "road")
end)

test("edges the wide query returns but the circle doesn't touch are dropped", function()
	addEdge(10, 0, 30, 100, 30, { owner = ME })   -- parallel, 30 m away
	addEdge(11, 0, 4, 100, 4, { owner = ME })     -- 4 m away
	local res = gather.sample(50, 0, 5, allOn(), gather.context(), gather.newCache())
	eq(res.edgeHits, 2)
	local m = byEntity(res)
	eq(m[10], nil)
	ok(m[11] ~= nil)
end)

test("constructions: origin inside the circle only", function()
	addCon(20, 10, 0, { owner = ME })
	addCon(21, 40, 0, { owner = ME })
	local res = gather.sample(0, 0, 20, allOn(), gather.context(), gather.newCache())
	local m = byEntity(res)
	ok(m[20] ~= nil); eq(m[20].kind, "asset")
	eq(m[21], nil, "origin outside even though the wide query found it")
	eq(res.conHits, 2)
end)

test("industry roads are protected even with every filter on", function()
	addCon(30, 60, 0, { industries = { 31 } })    -- origin outside the circle, inside the wide query
	addEdge(40, -10, 0, 10, 0)                     -- unowned town-style road that goes with it
	addEdge(41, -10, 5, 10, 5)                     -- ordinary town road
	world.segs[30] = { 40 }
	local res = gather.sample(0, 0, 10, allOn(), gather.context(), gather.newCache())
	local m = byEntity(res)
	eq(m[30], nil, "industry origin not under the brush")
	eq(m[40].reason, "industry")
	eq(m[41].reason, nil)
	eq(m[41].kind, "road")
end)

test("unowned road ending on an industry's frozen node is protected", function()
	addCon(30, 500, 0, { industries = { 31 } })   -- far away: not in any query
	addEdge(40, -10, 0, 10, 0, { node1 = 7 })
	world.nodeCon[7] = 30
	local m = byEntity(gather.sample(0, 0, 10, allOn(), gather.context(), gather.newCache()))
	eq(m[40].reason, "industry")
end)

test("construction-owned edges, HQ, tunnels and edge objects", function()
	addEdge(40, -10, 0, 10, 0, { owner = ME })
	world.edgeCon[40] = 55
	addCon(HQ, 1, 1, { owner = ME })
	addEdge(41, -10, 3, 10, 3, { owner = ME, street = false, tunnel = true, objects = { { 99, "SIGNAL" } } })
	local f = allOn()
	f.underground = false
	local m = byEntity(gather.sample(0, 0, 10, f, gather.context(), gather.newCache()))
	eq(m[40].reason, "part")
	eq(m[HQ].reason, "hq")
	eq(m[41].reason, "underground")
	eq(m[41].kind, "track")
	eq(m[41].objects, 1)
end)

test("failing engine reads become 'gone', never an error", function()
	addEdge(40, -10, 0, 10, 0, { owner = ME })
	world.broken[40] = true
	addCon(20, 0, 0, { owner = ME })
	world.broken[20] = true
	world.ghosts = { { e = 777, t = CT.BASE_EDGE } }   -- octree returns an entity that no longer exists
	local cache = gather.newCache()
	local res = gather.sample(0, 0, 10, allOn(), gather.context(), cache)
	eq(#res.candidates, 0, "nothing usable, nothing kept")
	ok(cache.descs[40].gone and cache.descs[20].gone and cache.descs[777].gone)
end)

test("descriptor cache: each entity is read once per cache", function()
	addEdge(40, -10, 0, 10, 0, { owner = ME })
	local reads = 0
	local orig = fakeApi.engine.getComponent
	fakeApi.engine.getComponent = function(e, t) if e == 40 then reads = reads + 1 end return orig(e, t) end
	local cache = gather.newCache()
	local ctx = gather.context()
	gather.sample(0, 0, 10, allOn(), ctx, cache)
	local first = reads
	gather.sample(2, 0, 10, allOn(), ctx, cache)
	fakeApi.engine.getComponent = orig
	eq(reads, first, "second sample used the cache")
end)

test("a paint stroke over several samples merges into one set", function()
	for i = 0, 9 do addEdge(100 + i, i * 20, 0, i * 20 + 20, 0, { owner = ME }) end
	local s = sel.newStroke()
	local cache, ctx = gather.newCache(), gather.context()
	for x = 0, 200, 25 do
		for _, c in ipairs(gather.sample(x, 0, 5, allOn(), ctx, cache).candidates) do sel.add(s, c) end
	end
	eq(sel.count(s), 10)
end)

test("station ownership: construction without PLAYER_OWNED falls back to station group / depot", function()
	local f = allOn()
	local ctx = gather.context()
	-- Station whose group is ours.
	addCon(20, 0, 0, { stations = { 201 }, frozenEdges = { 1 } })
	world.comps[201] = {}
	world.groupOf[201] = 301
	world.comps[301] = {}
	own(301, ME)
	-- Depot entity owned by us.
	addCon(21, 1, 0, { depots = { 211 }, frozenEdges = { 1 } })
	world.comps[211] = {}
	own(211, ME)
	-- Station of another player (station entity says so).
	addCon(22, 2, 0, { stations = { 221 }, frozenEdges = { 1 } })
	world.comps[221] = {}
	own(221, 2)
	-- Station with no owner anywhere, and one whose station and group disagree.
	addCon(23, 3, 0, { stations = { 231 }, frozenEdges = { 1 } })
	world.comps[231] = {}
	addCon(24, 4, 0, { stations = { 241 }, frozenEdges = { 1 } })
	world.comps[241] = {}
	own(241, ME)
	world.groupOf[241] = 341
	world.comps[341] = {}
	own(341, 2)
	local m = byEntity(gather.sample(0, 0, 10, f, ctx, gather.newCache()))
	eq(m[20].kind, "station"); eq(m[20].reason, nil)
	eq(m[21].kind, "station"); eq(m[21].reason, nil)
	eq(m[22].reason, "foreign")
	eq(m[23].reason, "not_player", "no owner found: never selected")
	eq(m[24].reason, "not_player", "conflicting owners: never selected")
end)

test("station ownership: the construction's own PLAYER_OWNED wins", function()
	addCon(20, 0, 0, { owner = ME, stations = { 201 }, frozenEdges = { 1 } })
	world.comps[201] = {}
	own(201, 2)
	local m = byEntity(gather.sample(0, 0, 10, allOn(), gather.context(), gather.newCache()))
	eq(m[20].reason, nil)
end)

test("describeEdge copies the edge heights for the highlight lines (bridge deck z)", function()
	addEdge(70, 0, 0, 40, 0, { owner = ME })
	local be = world.comps[70][CT.BASE_EDGE]
	be.position0.z, be.position1.z = 12, 18
	be.tangent0.z, be.tangent1.z = 6, 6
	local d = gather.describeEdge(70, gather.newCache())
	eq(d.curve.p0z, 12)
	eq(d.curve.p1z, 18)
	eq(d.curve.t0z, 6)
	eq(d.curve.t1z, 6)
end)
