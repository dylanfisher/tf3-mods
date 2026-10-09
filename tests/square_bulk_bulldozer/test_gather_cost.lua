-- Cost of one brush sample (PERF_REVIEW.md): engine reads per sample over a synthetic town.
-- The octree query is r + EDGE_MARGIN wide, so most entities it returns are NOT under the brush;
-- those must only be read as far as the touch / origin test needs (geometry), never in full
-- (owner, street, connector lookups, station owner, subconstruction). Results must stay the same.

local CT = {
	BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", CONSTRUCTION = "CONSTRUCTION",
	PLAYER_OWNED = "PLAYER_OWNED", PLAYER = "PLAYER", SUBCONSTRUCTION = "SUBCONSTRUCTION",
}
local ME, HQ = 1, 900

local world
local calls
local function reset()
	world = { comps = {}, segs = {}, edgeCon = {}, nodeCon = {} }
	calls = { total = 0 }
end
local function count(what)
	calls.total = calls.total + 1
	calls[what] = (calls[what] or 0) + 1
end

local function put(e, t, v)
	world.comps[e] = world.comps[e] or {}
	world.comps[e][t] = v
end

local function addEdge(e, x0, y0, x1, y1, opts)
	opts = opts or {}
	put(e, CT.BASE_EDGE, {
		type = "NORMAL", objects = {},
		node0 = opts.node0 or -1, node1 = opts.node1 or -1,
		position0 = { x = x0, y = y0, z = 0 }, position1 = { x = x1, y = y1, z = 0 },
		tangent0 = { x = x1 - x0, y = y1 - y0, z = 0 }, tangent1 = { x = x1 - x0, y = y1 - y0, z = 0 },
	})
	put(e, CT.BASE_EDGE_STREET, {})
	if opts.owner then put(e, CT.PLAYER_OWNED, { player = opts.owner }) end
end

local function addCon(e, x, y, opts)
	opts = opts or {}
	put(e, CT.CONSTRUCTION, {
		transf = { getTransl = function(_) return { x = x, y = y, z = 0 } end },
		stations = opts.stations or {}, depots = {}, industries = opts.industries or {},
		townBuildings = opts.townBuildings or {}, frozenEdges = {}, frozenNodes = {},
	})
	if opts.owner then put(e, CT.PLAYER_OWNED, { player = opts.owner }) end
	if opts.sub then put(e, CT.SUBCONSTRUCTION, {}) end
end

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
		entityExists = function(e) count("exists"); return world.comps[e] ~= nil end,
		getComponent = function(e, t)
			count(t)
			return world.comps[e] and world.comps[e][t] or nil
		end,
		util = {
			getPlayer = function() return ME end,
			octree = {
				findEntitiesInCircle = function(c, r, t)
					local out = {}
					for e, comps in pairs(world.comps) do
						if comps[t] then
							local x, y = refPoint(e)
							if (x - c.x) ^ 2 + (y - c.y) ^ 2 <= r * r then out[#out + 1] = e end
						end
					end
					table.sort(out)
					return out
				end,
			},
			construction = {
				findSegmentsToDelete = function(con, _keep) count("findSegmentsToDelete"); return world.segs[con] or {} end,
			},
		},
		system = {
			streetConnectorSystem = {
				getConstructionEntityForEdge = function(e) count("conForEdge"); return world.edgeCon[e] or -1 end,
				getConstructionEntityForNode = function(n) count("conForNode"); return world.nodeCon[n] or -1 end,
				getConstructionEntityForSubconstruction = function(_e) count("conForSub"); return -1 end,
			},
			stationGroupSystem = {
				getStationGroup = function(_st) count("stationGroup"); return -1 end,
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

local function allOn()
	return { roads = true, tracks = true, stations = true, assets = true,
		townBuildings = true, underground = true }
end

-- A 1 km town: a 40 m street grid (unowned town roads with real node ids) and a house every
-- 20 m between the streets; an industry with an access road and a station of ours in the middle.
local function buildTown()
	local id = 1000
	local node = 50000
	for gx = 0, 1000, 40 do
		for gy = 0, 1000, 40 do
			id = id + 1; node = node + 1
			addEdge(id, gx, gy, gx + 40, gy, { node0 = node, node1 = node + 100000 })
			id = id + 1
			addEdge(id, gx, gy, gx, gy + 40, { node0 = node, node1 = node + 200000 })
		end
	end
	for hx = 10, 1000, 20 do
		for hy = 10, 1000, 20 do
			id = id + 1
			addCon(id, hx + 0.5, hy + 0.5, { townBuildings = { id + 500000 } })
		end
	end
	addCon(7001, 520, 520, { industries = { 7002 } })
	world.segs[7001] = { 1001 }
	addCon(7101, 480, 480, { owner = ME, stations = { 7102 } })
end

local function snapshot(res)
	local out = {}
	for _, c in ipairs(res.candidates) do out[#out + 1] = string.format("%d:%s:%s", c.entity, c.kind, tostring(c.reason)) end
	table.sort(out)
	return table.concat(out, ",")
end

local function measure(r)
	buildTown()
	calls = { total = 0 }
	local t0 = os.clock()
	local res = gather.sample(500, 500, r, allOn(), gather.context(), gather.newCache())
	local secs = os.clock() - t0
	print(string.format("r = %d m: %d edges + %d constructions in query, %d candidates, %d engine reads (%s), %.1f ms (fake api)",
		r, res.edgeHits, res.conHits, #res.candidates, calls.total,
		string.format("exists %d, BASE_EDGE %d, PLAYER_OWNED %d, STREET %d, CONSTRUCTION %d, conForEdge %d, conForNode %d, SUB %d",
			calls.exists or 0, calls.BASE_EDGE or 0, calls.PLAYER_OWNED or 0, calls.BASE_EDGE_STREET or 0,
			calls.CONSTRUCTION or 0, calls.conForEdge or 0, calls.conForNode or 0, calls.SUBCONSTRUCTION or 0),
		secs * 1000))
	return res
end

test("cost: entities outside the brush are only read for geometry (r = 20 m)", function()
	local res = measure(20)
	-- Full reads (owner, street, connector) only for what the circle touches.
	ok((calls.PLAYER_OWNED or 0) <= #res.candidates + 2,
		"PLAYER_OWNED reads " .. tostring(calls.PLAYER_OWNED) .. " for " .. #res.candidates .. " candidates")
	ok((calls.conForEdge or 0) <= #res.candidates, "connector lookups only for touched edges")
	ok((calls.SUBCONSTRUCTION or 0) <= #res.candidates, "subconstruction reads only for hit constructions")
end)

test("cost: same for the biggest brush (r = 200 m)", function()
	local res = measure(200)
	ok((calls.PLAYER_OWNED or 0) <= #res.candidates + 2)
	ok((calls.conForEdge or 0) <= #res.candidates)
end)

test("cost: results equal a full describe of every queried entity", function()
	buildTown()
	local cache = gather.newCache()
	local ctx = gather.context()
	local res = gather.sample(500, 500, 30, allOn(), ctx, cache)
	-- A second cache where everything in the wide query was described in full first.
	local full = gather.newCache()
	for _, e in ipairs(api.engine.util.octree.findEntitiesInCircle({ x = 500, y = 500 }, 130, CT.BASE_EDGE)) do
		gather.describeEdge(e, full)
	end
	for _, e in ipairs(api.engine.util.octree.findEntitiesInCircle({ x = 500, y = 500 }, 130, CT.CONSTRUCTION)) do
		gather.describeConstruction(e, full)
	end
	local res2 = gather.sample(500, 500, 30, allOn(), ctx, full)
	eq(snapshot(res), snapshot(res2))
	ok(#res.candidates > 0)
	-- The industry access road (edge 1001 is far away) and the station are classified as before.
end)

test("cost: a light descriptor is completed when a later sample touches it", function()
	buildTown()
	local cache = gather.newCache()
	local ctx = gather.context()
	gather.sample(500, 500, 10, allOn(), ctx, cache)   -- reads (560, 560) and around only lightly
	local res = gather.sample(560, 560, 10, allOn(), ctx, cache)   -- inside the first wide query
	ok(#res.candidates > 0)
	local fresh = gather.sample(560, 560, 10, allOn(), ctx, gather.newCache())
	eq(snapshot(res), snapshot(fresh))
	for _, c in ipairs(res.candidates) do
		local d = cache.descs[c.entity]
		ok(d.owner ~= nil and (d.isEdge == false or d.isStreet ~= nil), "complete descriptor for " .. c.entity)
	end
end)

test("cost: describeEdge / describeConstruction stay complete (commit hard rules use them)", function()
	addEdge(10, 0, 0, 40, 0, { owner = ME })
	addCon(20, 500, 500, { owner = ME, sub = true })
	local cache = gather.newCache()
	local d = gather.describeEdge(10, cache)
	eq(d.owner, ME); eq(d.isStreet, true); eq(d.parentConstruction, -1)
	local c = gather.describeConstruction(20, cache)
	eq(c.owner, ME); eq(c.x, 500)
	eq(calls.conForSub, 1, "subconstruction parent looked up")
end)
