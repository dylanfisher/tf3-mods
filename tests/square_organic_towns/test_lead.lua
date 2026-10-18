-- Country lanes laid well ahead (ot_lead, round after the names run 2026-10-13): who lays one, where it goes (toward a
-- neighbour / the axis / the satellite, beyond the edge, short of the gap line, dry, gentle, not along a road), the
-- streets (lane + a hamlet T or a ribbon end) and the marking (country edges between new nodes, the joined edge and
-- the far end town streets).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")
local LD = ug_require(F.DIR .. "ot_lead.lua")
local LN = ug_require(F.DIR .. "ot_lane.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")

local function core()
	local g = F.roundCore(OG.new(), { rings = { 90, 180, 270 }, counts = { 6, 10, 14 } })
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do
		local node = g.nodeById[n]
		ends[#ends + 1] = { node.x, node.y, n }
	end
	return g, ends
end

local EAST = { { dir = 0, dist = 3000, town = 2 } }

local function pick(o)
	local g, ends = core()
	local r = { cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 11, deadEnds = ends, g = g,
		targets = LD.targets({ cx = 0, cy = 0, neighbours = EAST }) }
	for k, v in pairs(o or {}) do r[k] = v end
	local site, n = LD.pick(r)
	return site, n, g
end

test("eligible: a seeded ~30 % of young towns, never metropolis / block styles / big towns / past the quota", function()
	local on = 0
	for seed = 1, 400 do
		if LD.eligible({ seed = seed, buildings = 200, styleId = "EU_ORGANIC" }) then on = on + 1 end
	end
	ok(on >= 90 and on <= 150, "share " .. on / 400)
	local function why(o)
		local _, w = LD.eligible(o)
		return w
	end
	eq(why({ seed = 1, buildings = 20 }), "small")
	eq(why({ seed = 1, buildings = 5000 }), "big")
	eq(why({ seed = 1, buildings = 200, metro = true }), "metro")
	eq(why({ seed = 1, buildings = 200, styleId = "SUPERBLOCK" }), "style")
	eq(why({ seed = 1, buildings = 200, has = true }), "has")
	-- a seed that passes the draw is held by the quota
	local s0 = nil
	for seed = 1, 50 do if LD.eligible({ seed = seed, buildings = 200 }) then s0 = seed break end end
	eq(why({ seed = s0, buildings = 200, quotaLeft = false }), "quota")
	eq(LD.quota(3), 1); eq(LD.quota(20), 5)
end)

test("targets: neighbours in range first, then the satellite, then both ways along the axis", function()
	local tg = LD.targets({ cx = 0, cy = 0, neighbours = { { dir = 1, dist = 900 }, { dir = 2, dist = 3000 }, { dir = 3, dist = 9000 } },
		sat = { 0, 1000 }, axis = 0.5 })
	eq(#tg, 4)
	eq(tg[1].kind, "neighbour"); eq(tg[1].heading, 2)
	eq(tg[2].kind, "satellite")
	eq(tg[3].kind, "axis"); eq(tg[4].kind, "axis")
end)

test("pick: from an east dead end toward the neighbour, beyond the edge, short of the gap line", function()
	local site = pick()
	ok(site ~= nil, "a lane")
	eq(site.target, "neighbour")
	local de = site.deadEnd
	ok(de[1] > 150, "an east dead end: " .. de[1])
	local far = site.pts[#site.pts]
	ok(far[1] > de[1] + 300, "east, beyond the edge")
	ok(site.len >= LD.MIN_LEN and site.len <= LD.LEN[2], "length " .. site.len)
	-- with the gap toward the neighbour 3 km east (halfway 1500, gap 150-300): the far end stops before it
	local gp = GP.build({ 0, 0 }, EAST, 11)
	local s2 = pick({ gaps = gp })
	ok(s2 ~= nil)
	ok(GP.held(gp, s2.pts, "small") == nil, "never in the gap")
	local f2 = s2.pts[#s2.pts]
	ok(f2[1] < 1500, "short of the halfway line: " .. f2[1])
	-- a river across the way at x 700..760: the lane is shortened to stay dry, or no lane east
	local river = T.sampler(function() return 5 end, function(x) return x > 700 and x < 760 end, 0)
	local s3 = pick({ sampler = river })
	if s3 then ok(not T.wetAlong(river, s3.pts, 20, 40), "dry") end
	-- an existing road along the way: served, no lane there
	local roads = {}
	for x = 400, 1400, 50 do roads[#roads + 1] = { x, 0 } end
	local s4, why = pick({ roads = roads, targets = { { heading = 0, kind = "neighbour" } } })
	ok(s4 == nil or math.abs(s4.pts[#s4.pts][2]) > LD.ROAD_R, "not along the road")
	if s4 == nil then ok(why == "served" or why == "noFit", tostring(why)) end
	-- no target, no dead end
	eq(select(2, LD.pick({ cx = 0, cy = 0, sampler = F.flat, deadEnds = {}, targets = LD.targets({ cx = 0, cy = 0 }) })), "noDeadEnd")
	local _, ends = core()
	eq(select(2, LD.pick({ cx = 0, cy = 0, sampler = F.flat, deadEnds = ends, targets = {} })), "noTarget")
end)

test("streets + plan + mark: country edges between new nodes, the joined edge and the far end stay town streets", function()
	for _, kind in ipairs({ "hamlet", "ribbon" }) do
		local site, _, g = pick()
		site.endKind = kind
		local streets = LD.streets(site)
		local inc = PL.plan(g, streets, { terrain = F.flat, maxSeg = 100, snapR = 8, minLen = 10, minAngle = 25, maxEdges = 40,
			join = "deadEnd" })
		ok(#inc.edges >= 4, kind .. ": edges " .. #inc.edges)
		local path = LN.templateFor({ newTemplates = false })
		local lane, ends, len = LD.mark(inc, streets, path)
		ok(lane >= 2, kind .. ": lane edges " .. lane)
		ok(ends >= 1, kind .. ": town streets at the far end " .. ends)
		ok(len >= 200, kind .. ": lane length " .. len)
		for _, e in ipairs(inc.edges) do
			local st = streets[e.street]
			if (e.node0 or 0) > 0 or (e.node1 or 0) > 0 then ok(e.forestLane == nil, "a joined edge stays a town street") end
			if st.lead == "end" then ok(e.forestLane == nil, "the far end stays a town street") end
		end
		if kind == "hamlet" then eq(#streets, 4) else eq(#streets, 2) end
	end
end)

test("far end (run 2240): the ribbon at most RIBBON_MAX_M, every end street joined to the lane, dose points beside it", function()
	for _, kind in ipairs({ "hamlet", "ribbon" }) do
		local site, _, g = pick()
		site.endKind = kind
		local streets = LD.streets(site)
		if kind == "ribbon" then
			local rib = streets[2]
			ok(G.polyLen(rib.pts) <= LD.RIBBON_MAX_M + 60, "ribbon length " .. G.polyLen(rib.pts))
		end
		local inc = PL.plan(g, streets, { terrain = F.flat, maxSeg = 100, snapR = 8, minLen = 10, minAngle = 25, maxEdges = 40,
			join = "deadEnd" })
		LD.mark(inc, streets, LN.templateFor({ newTemplates = false }))
		local j, n = LD.endJoined(inc, streets)
		ok(n >= 1 and j == n, kind .. ": end streets joined " .. j .. "/" .. n)
		local pts = LD.endFillPoints(inc, streets, 25, 2)
		ok(#pts >= 1 and #pts <= 2, kind .. ": dose points " .. #pts)
		local far = site.pts[#site.pts]
		for _, p in ipairs(pts) do ok(G.dist(p[1], p[2], far[1], far[2]) <= LD.RIBBON_MAX_M + 80, "beside the far end") end
		-- a loose end street (cut off the lane) is found
		for _, e in ipairs(inc.edges) do
			if streets[e.street].lead == "end" then e.node0, e.node1 = -900001, -900002 break end
		end
		local j2, n2 = LD.endJoined(inc, streets)
		ok(j2 < n2, kind .. ": a loose end street")
	end
end)

test("saved: the lane ahead goes on the town's frame once; normalize and frame() keep it", function()
	local s = SV.applyFrame(nil, { town = 7, a = 0.5, x = 10, y = 20 })
	local s2, ch = SV.applyLead(s, { town = 7 })
	ok(ch)
	local _, ch2 = SV.applyLead(s2, { town = 7 })
	ok(not ch2, "idempotent")
	local _, ch3 = SV.applyLead(s2, { town = 8 })
	ok(not ch3, "no frame: ignored")
	ok(SV.frame(SV.normalize(s2), 7).lead == true)
end)
