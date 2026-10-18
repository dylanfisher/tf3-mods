-- Industrial satellite towns, "Works" (ot_works, round after the names run 2026-10-13): who gets one (new maps only, a
-- seeded share, a quota, never a Works town), where (0.8-1.5 km out, a harbour / station / the far bank best, dry,
-- gentle, never by a character town's core or past a gap line), the name per list language (unique), the link road
-- (a country middle between two joined town-street ends) and the saved state.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local LD = ug_require(F.DIR .. "ot_lead.lua")
local LN = ug_require(F.DIR .. "ot_lane.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")

local function core()
	local g = F.roundCore(OG.new(), { rings = { 90, 180, 270 }, counts = { 6, 10, 14 } })
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do
		local node = g.nodeById[n]
		ends[#ends + 1] = { node.x, node.y, n }
	end
	return g, ends
end

local function site(o)
	local g, ends = core()
	local r = { cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 11, deadEnds = ends, g = g }
	for k, v in pairs(o or {}) do r[k] = v end
	return WK.pickSite(r)
end

test("eligible: new maps only, grown towns, a seeded ~35 %, never a Works town, the quota", function()
	local on = 0
	for seed = 1, 400 do
		if WK.eligible({ fresh = true, seed = seed, buildings = 500 }) then on = on + 1 end
	end
	ok(on >= 110 and on <= 170, "share " .. on / 400)
	local function why(o)
		local _, w = WK.eligible(o)
		return w
	end
	eq(why({ fresh = false, seed = 1, buildings = 900 }), "notNewMap")
	eq(why({ fresh = true, seed = 1, buildings = 100 }), "small")
	eq(why({ fresh = true, seed = 1, buildings = 900, isWorks = true }), "works")
	eq(why({ fresh = true, seed = 1, buildings = 900, has = true }), "has")
	local s0 = nil
	for seed = 1, 50 do if WK.eligible({ fresh = true, seed = seed, buildings = 900 }) then s0 = seed break end end
	eq(why({ fresh = true, seed = s0, buildings = 900, quotaLeft = false }), "quota")
	eq(WK.quota(5), 1); eq(WK.quota(16), 2); eq(WK.quota(100), WK.MAP_MAX)
end)

test("site: 0.8-1.5 km out, reachable from a dead end; a harbour or station wins; water, neighbours, characters avoided", function()
	local s, n = site()
	ok(s ~= nil, tostring(n))
	ok(s.d >= 800 and s.d <= 1500, "d " .. s.d)
	eq(s.kind, "plain")
	ok(s.deadEnd ~= nil and #s.link >= 2, "a link line")
	-- a harbour 1 km north: the site goes beside it
	local h = site({ harbours = { { x = 0, y = 1000 } } })
	eq(h.kind, "harbour")
	ok(G.dist(h.x, h.y, 0, 1000) <= WK.HARBOUR_R, "beside the harbour")
	-- a station 1.2 km west, no harbour
	local r = site({ rails = { { x = -1200, y = 0 } } })
	eq(r.kind, "rail")
	-- a neighbour town 2 km east: never on that side (nearer it)
	for seed = 1, 6 do
		local nb = site({ seed = seed, neighbours = { { 2000, 0 } } })
		ok(nb == nil or G.dist(nb.x, nb.y, 2000, 0) > nb.d * 1.15, "nearer this town")
	end
	-- a character town 1.6 km south: not within CHAR_CORE_M of its centre
	for seed = 1, 6 do
		local c = site({ seed = seed, characters = { { 0, -1600 } } })
		ok(c == nil or G.dist(c.x, c.y, 0, -1600) > WK.CHAR_CORE_M, "away from the character town")
	end
	-- the sea everywhere beyond 600 m: no site
	local sea = T.sampler(function() return 5 end, function(x, y) return x * x + y * y > 600 * 600 end, 0)
	eq(select(2, site({ sampler = sea })), "noSite")
	-- the far bank of a river (x 500..560): across, the link line still dry (it goes round to the north? no: the
	-- river runs north-south, every link to the far bank is wet), so sites stay this side
	local river = T.sampler(function() return 5 end, function(x) return x > 500 and x < 560 end, 0)
	for seed = 1, 4 do
		local rv = site({ seed = seed, sampler = river })
		ok(rv == nil or not T.wetAlong(river, rv.link, 20, 40), "the link stays dry")
	end
	-- the gap toward a neighbour 3 km east
	local gp = GP.build({ 0, 0 }, { { dir = 0, dist = 3000, town = 2 } }, 11)
	for seed = 1, 4 do
		local gs = site({ seed = seed, gaps = gp })
		ok(gs == nil or GP.held(gp, { { gs.x, gs.y } }, "small") == nil, "never in the gap")
	end
	eq(select(2, WK.pickSite({ cx = 0, cy = 0, sampler = F.flat, deadEnds = {} })), "noDeadEnd")
end)

test("names: per list language and site kind, unique on the map", function()
	-- (2026-10-14, NEXT_PHASE_BRIEF 47: through ot_offname; test_offname.lua holds the variety rules)
	for _, e in ipairs({ { "en", "Ellesmere Port" }, { "de", "Ulm" }, { "fr", "Rouen" }, { "sv", "Mora" }, { "it", "Pisa" },
		{ "usa", "Dayton" }, { "ja", "大垣" }, { "xx", "Town" } }) do
		for _, kind in ipairs({ "plain", "harbour", "rail" }) do
			local nm = WK.name(e[1], e[2], kind, {}, { seed = 3 })
			ok(nm ~= nil and nm ~= e[2], e[1] .. " " .. kind .. " " .. tostring(nm))
		end
	end
	-- unique on the map, and no second water word on a water-named parent
	local u = WK.name("en", "Ferryhill", "plain", {}, { seed = 1 })
	ok(WK.name("en", "Ferryhill", "plain", { [u] = true }, { seed = 1 }) ~= u)
	for seed = 1, 10 do
		local w = WK.name("en", "Ellesmere Port", "harbour", {}, { seed = seed })
		ok(not w:find("^Port ") and not w:find("Quay", 1, true) and not w:find("Harbour", 1, true), w)
	end
	local pc = WK.name("en", "100%", "plain", {}, { seed = 2 })
	ok(pc ~= nil, "a % in a town name: " .. tostring(pc))
end)

test("link road: the nearest dry, clear pair of dead ends; a country middle between two joined town-street ends", function()
	local g, ends = core()
	-- the Works town's streets: a short street 1 km east with a dead end at x = 950
	local wn0, wn1 = 90001, 90002
	OG.addNode(g, wn0, 1050, 0, 0, true)
	OG.addNode(g, wn1, 950, 0, 0, true)
	OG.addEdge(g, 90003, wn0, wn1, "small", true)
	local lk, why = WK.link({ sampler = F.flat, seed = 3, deadEnds = ends, worksEnds = { { 950, 0, wn1 } }, g = g })
	ok(lk ~= nil, tostring(why))
	eq(lk.to[3], wn1)
	ok(lk.from[1] > 150, "from an east dead end: " .. lk.from[1])
	local streets = WK.linkStreets(lk)
	local inc = PL.plan(g, streets, { terrain = F.flat, maxSeg = 100, snapR = 8, minLen = 10, minAngle = 25, maxEdges = 40,
		join = "deadEnd" })
	local joined = {}
	for _, j in ipairs(inc.joins) do joined[j.node] = true end
	ok(joined[wn1] and joined[lk.from[3]], "both ends joined")
	local lane = LD.mark(inc, streets, LN.templateFor({}))
	ok(lane >= 3, "a country middle: " .. lane)
	for _, e in ipairs(inc.edges) do
		if (e.node0 or 0) > 0 or (e.node1 or 0) > 0 then ok(e.forestLane == nil, "joined ends stay town streets") end
	end
	-- water between: no link
	local river = T.sampler(function() return 5 end, function(x) return x > 600 and x < 660 end, 0)
	local lk2, why2 = WK.link({ sampler = river, deadEnds = ends, worksEnds = { { 950, 0, wn1 } }, g = g })
	eq(lk2, nil); eq(why2, "wet")
	eq(select(2, WK.link({ sampler = F.flat, deadEnds = ends, worksEnds = {} })), "noDeadEnds")
end)

test("saved: the Works towns (wk) and the parent's frame (wp), once; normalize and frame() keep them", function()
	local s = SV.applyFrame(nil, { town = 7, a = 0.5, x = 10, y = 20 })
	local s2, ch = SV.applyWorks(s, { parent = 7, town = 99 })
	ok(ch)
	local _, ch2 = SV.applyWorks(s2, { parent = 7, town = 99 })
	ok(not ch2, "idempotent")
	local n = SV.normalize(s2)
	ok(SV.worksSet(n)[99])
	eq(SV.frame(n, 7).works, 99)
	-- no frame: the town is still known as a Works town
	local s3 = SV.applyWorks(nil, { parent = 8, town = 98 })
	ok(SV.worksSet(s3)[98])
end)
