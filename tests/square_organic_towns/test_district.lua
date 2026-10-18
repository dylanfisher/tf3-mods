-- Round after the 2355 run (2026-10-14): district towns (ot_district), the robust link road (ot_link), Works by a
-- factory (ot_works.industrySite), the saved districts / coastal flag (ot_saved), the gap waived along an offshoot's
-- link (ot_gap), coastal huggers (ot_map.coastal + ot_form COASTAL) and terrain-squeezed towns (ot_site squeeze).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")
local DT = ug_require(F.DIR .. "ot_district.lua")
local LK = ug_require(F.DIR .. "ot_link.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")
local MAP = ug_require(F.DIR .. "ot_map.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local SITE = ug_require(F.DIR .. "ot_site.lua")
local NM = ug_require(F.DIR .. "ot_names.lua")

local function core()
	local g = F.roundCore(OG.new(), { rings = { 90, 180, 270 }, counts = { 6, 10, 14 } })
	local ends = {}
	for _, n in ipairs(OG.deadEnds(g)) do
		local node = g.nodeById[n]
		ends[#ends + 1] = { node.x, node.y, n }
	end
	return g, ends
end

-- a plateau 30 m above the town to the north-east (beyond 650 m), gentle in between
local terrace = T.sampler(function(x, y)
	local d = math.sqrt(x * x + y * y)
	local up = math.max(0, math.min(1, (d - 400) / 400))
	local ne = math.max(0, (x + y) / math.max(d, 1))
	return 20 + 30 * up * ne
end)

test("district eligible: new maps, grown towns, 1-2 per town, the second after the first is linked, a quota", function()
	local on = 0
	for seed = 1, 300 do if DT.eligible({ fresh = true, seed = seed, buildings = 400 }) then on = on + 1 end end
	ok(on >= 140 and on <= 220, "share " .. on / 300)
	local function why(o) return select(2, DT.eligible(o)) end
	eq(why({ fresh = false, seed = 1, buildings = 900 }), "notNewMap")
	eq(why({ fresh = true, seed = 1, buildings = 900, isOffshoot = true }), "offshoot")
	eq(why({ fresh = true, seed = 1, buildings = 900, character = true }), "character")
	eq(why({ fresh = true, seed = 1, buildings = 200 }), "small")
	eq(why({ fresh = true, seed = 1, buildings = 900, count = 2 }), "max")
	eq(why({ fresh = true, seed = 1, buildings = 500, count = 1, linkedAll = true }), "small", "a second needs SECOND_BUILDINGS")
	eq(why({ fresh = true, seed = 1, buildings = 900, count = 1, linkedAll = false }), "waitLink")
	eq(why({ fresh = true, seed = 1, buildings = 900, count = 1, linkedAll = true }), "seeded", "the second: no seeded draw")
	eq(why({ fresh = true, seed = 1, buildings = 900, quotaLeft = false }), "quota")
	eq(DT.quota(3), 1); eq(DT.quota(16), 4); eq(DT.quota(100), DT.MAP_MAX)
end)

test("district site: only on a feature (terrace, shore, valley, lead), 0.6-1.5 km, a link line", function()
	local g, ends = core()
	local base = { cx = 0, cy = 0, r = 300, seed = 5, deadEnds = ends, g = g }
	local function pick(o)
		local r = {}
		for k, v in pairs(base) do r[k] = v end
		for k, v in pairs(o) do r[k] = v end
		return DT.pickSite(r)
	end
	-- flat land: no feature, an "open" district (§64, 2026-10-15: the offshoot towns stand in for the satellite
	-- villages); with OPEN off no district, as before
	local fl = pick({ sampler = F.flat })
	ok(fl ~= nil and fl.kind == "open", fl and fl.kind or "none")
	DT.OPEN = false
	eq(select(2, pick({ sampler = F.flat })), "noSite")
	DT.OPEN = true
	-- the terrace: an "upper" site north-east, above the town
	local s, n = pick({ sampler = terrace })
	ok(s ~= nil, tostring(n))
	eq(s.kind, "upper")
	ok(s.d >= 600 and s.d <= 1500, "d " .. s.d)
	ok(terrace.height(s.x, s.y) - 20 >= DT.UPPER_DZ, "above the town")
	ok(#s.link >= 2 and s.deadEnd ~= nil, "a link line")
	-- the far end of a lane ahead 1 km west on flat land: a "lead" site beside it
	local l = pick({ sampler = F.flat, lead = { -1000, 0 } })
	ok(l ~= nil and l.kind == "lead" and G.dist(l.x, l.y, -1000, 0) <= DT.LEAD_R, "lead site")
	-- a sea 1.1 km south (y < -1100): a shore site near it, never in the water's setback
	local sea = T.sampler(function() return 20 end, function(_, y) return y < -1100 end, 0)
	local sh = pick({ sampler = sea })
	ok(sh ~= nil and sh.kind == "shore", sh and sh.kind or "none")
	ok(not T.isWater(sea, sh.x, sh.y), "dry")
	-- (2026-10-14 late: no clearing kind any more) a forest clearing on flat land is no district site
	local cover = function(x, y)
		local d = G.dist(x, y, 1000, 0)
		if d < 120 then return 0 end
		if d < 500 then return 0.8 end
		return 0
	end
	local cl = pick({ sampler = F.flat, cover = cover })
	ok(cl == nil or (cl.kind == "open" and G.dist(cl.x, cl.y, 1000, 0) > 500), "no clearing district")
	-- a second district: far from the first and in another direction
	local s2 = pick({ sampler = terrace, others = { { s.x, s.y } } })
	ok(s2 == nil or (G.dist(s2.x, s2.y, s.x, s.y) >= DT.SECOND_APART), "apart")
	-- a character town's core and a neighbour nearer than the site: never there
	local c = pick({ sampler = terrace, characters = { { s.x, s.y } } })
	ok(c == nil or G.dist(c.x, c.y, s.x, s.y) > WK.CHAR_CORE_M, "away from the character town")
	-- an industry zone over the terrace: no site in it
	local z = pick({ sampler = terrace, zones = { zones = { { x = s.x, y = s.y, r = 400 } } } })
	ok(z == nil or G.dist(z.x, z.y, s.x, s.y) > 400, "outside the zone")
end)

test("district names: per language and kind, the stem of a long name, unique", function()
	eq(DT.name("en", "Haslemere", "upper", {}, { seed = 1 }):find("Haslemere", 1, true) ~= nil, true)
	-- (2026-10-14, NEXT_PHASE_BRIEF 47: a shore without a site read is no proof of a sea beach: no sea words)
	local en = DT.name("en", "Penkridge", "shore", {}, { seed = 2 })
	ok(en and en:find("Penkridge", 1, true) and not en:find("Sea", 1, true) and not en:find("Sands", 1, true), tostring(en))
	local lk = DT.name("en", "Penkridge", "shore", {}, { seed = 2, lake = true })
	ok(lk:find("Water", 1, true) or lk:find("Lakeside", 1, true), "lake forms: " .. lk)
	ok(DT.name("de", "Ulm", "upper", {}, { seed = 3 }) ~= nil)
	local de = {}
	for seed = 1, 20 do de[DT.name("de", "Ulm", "upper", {}, { seed = seed })] = true end
	ok(de["Oberulm"] or de["Ulm-Oberstadt"] or de["Ulm-Höhe"], "German upper forms")
	ok(DT.name("de", "Ulm", "across", {}, { seed = 1 }):find("Ulm", 1, true), "Neu-Ulm style")
	eq(DT.stem("Henley-in-Arden"), "Henley")
	eq(DT.stem("Swanscombe and Greenhithe"), "Swanscombe")
	local h = DT.name("en", "Henley-in-Arden", "upper", {}, { seed = 1 })
	ok(h and h:find("Henley", 1, true) and not h:find("Arden", 1, true), tostring(h))
	-- a list without a classifier: none
	eq(DT.name(false, "Mora", "upper", {}, { seed = 1 }), nil)
	-- the names module's reserve: unused tagged names
	local p = NM.newPool({ "Hillside", "Hill Top", "Seaton", "Oldham", "Woodley" }, "en")
	while not NM.classifyStep(p, 50) do end
	local rs = NM.reserve(p, { ["Hillside"] = true }, 1, 3)
	for _, list in pairs(rs) do for _, nm in ipairs(list) do ok(nm ~= "Hillside", "unused only") end end
end)

test("forest (2026-10-14 late, Winchcombe Heath): a site inside the forest is rejected (why=forest), open land at the edge preferred", function()
	local g, ends = core()
	-- the terrace's sites lie north-east; forest all over the north-east quadrant beyond 500 m
	local wooded = function(x, y) if x > 0 and y > 0 and G.dist(x, y, 0, 0) > 500 then return 0.9 end return 0 end
	local s, why = DT.pickSite({ cx = 0, cy = 0, r = 300, seed = 5, deadEnds = ends, g = g, sampler = terrace, cover = wooded })
	ok(s == nil or s.forest == nil or s.forest <= WK.FOREST_MAX, "never in the forest")
	if s == nil then eq(why, "forest") end
	-- the share: deep forest round the site, open land, unknown outside the grid
	ok(math.abs(WK.forestShare(function() return 0.8 end, 0, 0) - 0.8) < 1e-9, "deep forest")
	eq((WK.forestShare(function() return 0 end, 0, 0)), 0)
	eq((WK.forestShare(function() return nil end, 0, 0)), nil, "unknown")
	-- open land with forest just beyond the growth radius: an edge site
	local ring = function(x, y) return G.dist(x, y, 0, 0) > WK.FOREST_R + 60 and 0.9 or 0 end
	local sh, edge = WK.forestShare(ring, 0, 0)
	ok(sh <= WK.FOREST_MAX and edge, "open, at the edge")
	-- Works: the same test (a forest over the whole ring: no site, why=forest)
	local all = function() return 0.7 end
	local w, wwhy = WK.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 3, deadEnds = ends, g = g, cover = all })
	eq(w, nil); eq(wwhy, "forest")
	local w2 = WK.pickSite({ cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 3, deadEnds = ends, g = g,
		cover = function(x, y) return x > 0 and 0.7 or 0 end })
	ok(w2 ~= nil and w2.x < 0, "the open side")
	-- an offshoot town hugs the forest from its first build
	local FO = ug_require(F.DIR .. "ot_forest.lua")
	local fg = FO.fromFunction(0, 0, function() return 60 end, 400, 50)
	eq(FO.forStyle(fg, { id = "EU_ORGANIC", seed = 1, offshoot = true, year = 2000, tier = 4 }).mode, "hug")
	eq(FO.coverAt(fg, 5000, 5000), nil, "outside the grid: unknown")
end)

test("names (2026-10-14 late): 10 Works and 10 districts on one map repeat no form while others fit; no water word twice", function()
	local used = {}
	local parents = { "Haslemere", "Heywood", "Ringwood", "Tickhill", "Winchcombe", "Penkridge", "Settle", "Yarm",
		"Chesham", "Telscombe" }
	-- (2026-10-14, NEXT_PHASE_BRIEF 47: through ot_offname; the suffix key, standalone names included)
	local wf = {}
	for i, p in ipairs(parents) do
		local n, info = WK.name("en", p, "plain", used, { year = 1900, seed = i })
		ok(n ~= nil, p)
		used[n] = true
		wf[info.suffix] = (wf[info.suffix] or 0) + 1
		ok(wf[info.suffix] == 1, "Works suffix repeated: " .. n .. " (" .. i .. ")")
	end
	-- later eras: estates and parks among the forms from their year
	local OFF = ug_require(F.DIR .. "ot_offname.lua")
	ok(OFF.condOk("y1950", { year = 1990 }) and not OFF.condOk("y1950", { year = 1900 }), "late forms")
	local kinds = { "upper", "upper", "upper", "upper", "shore", "shore", "shore", "valley", "valley", "valley" }
	local df = {}
	for i, k in ipairs(kinds) do
		local n, _, info = DT.name("en", parents[i], k, used, { seed = i })
		ok(n ~= nil, parents[i] .. " " .. k)
		used[n] = true
		df[info.suffix] = (df[info.suffix] or 0) + 1
		ok(df[info.suffix] == 1, "district suffix repeated: " .. n)
	end
	-- never a water word twice
	for _, p in ipairs({ "Ellesmere Port", "Windermere", "Weymouth", "Milford Haven" }) do
		local n = DT.name("en", p, "shore", {}, { seed = 1 })
		ok(n and not n:find("Sea", 1, true) and not n:find("Sands", 1, true) and not n:find("Bay", 1, true), tostring(n))
		local w = WK.name("en", p, "harbour", {}, {})
		ok(w and not w:find("^Port ") and not w:find("Quay", 1, true), tostring(w))
	end
	ok(WK.hasWater("Ellesmere Port") and WK.hasWater("Windermere") and WK.hasWater("大垣港") and not WK.hasWater("Heywood"))
	-- an orphan: a town named like a district of another town, claimed by none
	eq((DT.orphanOf("Winchcombe Heath", { [1] = "Winchcombe", [2] = "Winchcombe Heath" }, "en")), "Winchcombe")
	eq(DT.orphanOf("Settle", { [1] = "Winchcombe", [2] = "Settle" }, "en"), nil)
end)

test("saved load check (2026-10-14 late): entries pointing at the wrong town are dropped, the parent's count lowered", function()
	-- the run's race: Ringwood (frame at -4800:4700) claimed Heywood Works (7500:-3100) as its district; Penkridge's
	-- district 600 m from it is right; a new entry with a site; a Works whose town stands far from its saved site
	local s = SV.applyFrame(nil, { town = 41, a = 0, x = -4800, y = 4700 })
	s = SV.applyFrame(s, { town = 36, a = 0, x = 3300, y = 7100 })
	s = SV.applyWorks(s, { parent = 41, town = 147514, kind = "district" })
	s = SV.applyWorks(s, { parent = 36, town = 128852, kind = "district" })
	s = SV.applyWorks(s, { parent = 36, town = 300, kind = "district", x = 3000, y = 7600 })
	s = SV.applyWorks(s, { parent = 41, town = 400, x = -3000, y = 4000 })
	eq(SV.frame(s, 41).districts, 1)
	eq(SV.frame(s, 41).works, 400)
	local pos = { [147514] = { 7500, -3100 }, [128852] = { 3176, 6528 }, [300] = { 3050, 7550 }, [400] = { 9000, 9000 } }
	local drops = SV.offshootCheck(s, function(id) local p = pos[id] if p then return p[1], p[2] end end)
	local by = {}
	for _, d in ipairs(drops) do by[d.t] = d end
	eq(#drops, 2)
	eq(by[147514].why, "far"); eq(by[147514].p, 41)
	eq(by[400].why, "site")
	eq(by[128852], nil, "the right claim stays")
	-- the filtered view, then the drop event
	local v = SV.withoutOffshoots(s, { [147514] = true, [400] = true })
	eq(SV.districtSet(v)[147514], nil); eq(SV.worksSet(v)[400], nil); eq(SV.districtSet(v)[128852], 36)
	local s2, ch = SV.applyWorks(s, { kind = "drop", town = 147514, parent = 41 })
	ok(ch, "dropped")
	s2 = SV.applyWorks(s2, { kind = "drop", town = 400 })
	local n = SV.normalize(s2)
	eq(SV.districtSet(n)[147514], nil)
	eq(SV.frame(n, 41).districts, nil, "Ringwood's count back to none")
	eq(SV.frame(n, 41).works, nil)
	eq(SV.worksSet(n)[400], nil)
	eq(SV.districtSet(n)[300], 36)
	local _, ch2 = SV.applyWorks(s2, { kind = "drop", town = 147514 })
	ok(not ch2, "idempotent")
end)

test("link: many pairs, detours round a blocking street, never doubling back, the best first", function()
	local g, ends = core()
	-- the other town's dead end 1 km east, and a street across the straight line between (x = 600, y -150..150)
	local wn0, wn1 = 90001, 90002
	OG.addNode(g, wn0, 1100, 0, 0, true)
	OG.addNode(g, wn1, 1000, 0, 0, true)
	OG.addEdge(g, 90003, wn0, wn1, "small", true)
	OG.addNode(g, 91001, 600, -150, 0, true)
	OG.addNode(g, 91002, 600, 150, 0, true)
	OG.addEdge(g, 91003, 91001, 91002, "small", true)
	local list, why, info = LK.candidates({ sampler = F.flat, seed = 3, from = ends, to = { { 1000, 0, wn1 } }, g = g })
	ok(#list >= 1, tostring(why) .. " " .. LK.failText(info))
	ok((info.fails.crossing or 0) >= 1, "the straight line crossed")
	for _, lk in ipairs(list) do
		ok(LK.clearOfStreets(g, lk.pts, lk.from[3], lk.to[3]), "clear")
		eq(lk.to[3], wn1)
	end
	ok(list[1].offM > 0, "a detour")
	for i = 2, #list do ok(list[i].score >= list[i - 1].score, "best first") end
	-- planned: both ends joined
	local inc = PL.plan(g, LK.streets(list[1], "district"), { terrain = F.flat, maxSeg = 100, snapR = 8, minLen = 10,
		minAngle = 25, maxEdges = 40, join = "deadEnd" })
	local j = {}
	for _, x in ipairs(inc.joins) do j[x.node] = true end
	ok(j[wn1] and j[list[1].from[3]], "both ends joined")
	-- a dead end whose street points away from the target: doubling back is refused
	local g2 = OG.new()
	OG.addNode(g2, 1, 0, 0, 0, true)
	OG.addNode(g2, 2, 100, 0, 0, true)
	OG.addEdge(g2, 3, 1, 2, "small", true)
	OG.addNode(g2, 4, 900, 0, 0, true)
	OG.addNode(g2, 5, 1000, 0, 0, true)
	OG.addEdge(g2, 6, 4, 5, "small", true)
	-- from node 2 (its street runs back west to node 1) east to node 4: fine; from node 1 east: doubles back
	-- (2026-10-14: with the lead-out routes (LK.LEAD) node 1 may leave west along its own line and swing round, clear of
	-- its street; the straight and detour routes still never double back)
	local lead0 = LK.LEAD
	LK.LEAD = false
	local l2 = LK.candidates({ sampler = F.flat, from = { { 0, 0, 1 } }, to = { { 900, 0, 4 } }, g = g2 })
	LK.LEAD = lead0
	eq(#l2, 0, "node 1 doubles back over its own street")
	local l2b = LK.candidates({ sampler = F.flat, from = { { 0, 0, 1 } }, to = { { 900, 0, 4 } }, g = g2 })
	for _, lk in ipairs(l2b) do ok(type(lk.off) == "string", "only a lead-out route from node 1") end
	local l3 = LK.candidates({ sampler = F.flat, from = { { 100, 0, 2 } }, to = { { 900, 0, 4 } }, g = g2 })
	ok(#l3 >= 1, "node 2 heads on")
	-- an industry zone across every route: none, why zone
	local _, wz = LK.candidates({ sampler = F.flat, from = { { 100, 0, 2 } }, to = { { 900, 0, 4 } }, g = g2,
		zones = { zones = { { x = 500, y = 0, r = 600 } } } })
	eq(wz, "zone")
	-- the old ot_works.link wraps it
	local lk, w0 = WK.link({ sampler = F.flat, deadEnds = { { 100, 0, 2 } }, worksEnds = { { 900, 0, 4 } }, g = g2 })
	ok(lk ~= nil, tostring(w0))
end)

test("Works by a factory: on the line to it at ~2/3, outside its zone, named by its type; harbour only when nearer", function()
	local g, ends = core()
	local o = { cx = 0, cy = 0, r = 300, sampler = F.flat, seed = 11, deadEnds = ends, g = g,
		industries = { { 0, 1800, file = "industry/quarry/quarry.con" } } }
	local s = WK.pickSite(o)
	ok(s ~= nil, "a site")
	eq(s.kind, "quarry")
	ok(s.industry ~= nil and math.abs(s.at - 2 / 3) < 0.15, "about 2/3: " .. tostring(s.at))
	ok(G.dist(s.x, s.y, 0, 1800) >= WK.IND_KEEP, "not at the quarry")
	-- (2026-10-14, NEXT_PHASE_BRIEF 47: the type's family, ot_offname)
	eq(select(2, WK.name("en", "Haslemere", s.kind, {})).fam, "stone")
	eq(select(2, WK.name("en", "Haslemere", "mine", {})).fam, "coal")
	ok(WK.name("de", "Ulm", "mine", {}) ~= nil)
	ok(WK.name("en", "Haslemere", "works", { ["Haslemere Works"] = true }) ~= "Haslemere Works")
	-- a harbour 900 m west: nearer than the quarry site, so the harbour wins
	o.harbours = { { x = -900, y = 0 } }
	local h = WK.pickSite(o)
	eq(h.kind, "harbour")
	-- an industry 4 km away: the old ring
	o.harbours, o.industries = nil, { { 0, 4000, file = "x/steel_mill.con" } }
	local r = WK.pickSite(o)
	ok(r ~= nil and r.industry == nil, "ring site")
end)

test("saved: districts (dk with the parent, dp on the frame) and the coastal flag (cs) survive normalize", function()
	local s = SV.applyFrame(nil, { town = 7, a = 0.5, x = 10, y = 20, cs = 1 })
	local s2, ch = SV.applyWorks(s, { parent = 7, town = 99, kind = "district" })
	ok(ch, "changed")
	local s3, ch3 = SV.applyWorks(s2, { parent = 7, town = 99, kind = "district" })
	ok(not ch3, "idempotent")
	local s4 = SV.applyWorks(s3, { parent = 7, town = 101, kind = "district" })
	local n = SV.normalize(s4)
	eq(SV.districtSet(n)[99], 7)
	eq(SV.districtSet(n)[101], 7)
	eq(SV.worksSet(n)[99], nil, "not a Works")
	eq(SV.frame(n, 7).districts, 2)
	eq(SV.frame(n, 7).coastal, true)
	local w = SV.applyWorks(n, { parent = 7, town = 200 })
	eq(SV.worksSet(w)[200], true)
	eq(SV.frame(w, 7).works, 200)
end)

test("gap waived along an offshoot's link: the parent may build toward it, not beside it", function()
	local gp = GP.build({ 0, 0 }, { { x = 1200, y = 0, town = 2, waive = true } }, 11)
	eq(GP.held(gp, { { 900, 0 } }, "small"), nil, "on the link corridor")
	ok(GP.held(gp, { { 900, 400 } }, "small") ~= nil, "off the corridor the gap holds")
	local gp2 = GP.build({ 0, 0 }, { { x = 1200, y = 0, town = 2 } }, 11)
	ok(GP.held(gp2, { { 900, 0 } }, "small") ~= nil, "without the waiver")
	ok(GP.text(gp):find("waive=1", 1, true), GP.text(gp))
end)

test("coastal huggers: the towns with the most coastline, 1-2 per map; the strong shore form with a shallow strip", function()
	-- sea for y < 0: towns on the shore (y = 50) score high, inland (y = 3000) zero, a river town low
	local sea = function(_, y) return y < 0 end
	local hi = MAP.coastScore(sea, 0, 50)
	local lo = MAP.coastScore(sea, 0, 3000)
	ok(hi >= 0.8, "shore " .. hi)
	eq(lo, 0)
	local river = function(x) return x > -20 and x < 20 end
	ok(MAP.coastScore(river, 0, 0) < MAP.COAST_MIN, "a river is no coast")
	local towns = {}
	for i = 1, 12 do towns[#towns + 1] = { i, i * 5000, (i <= 3) and (40 * i) or 3000 } end
	local picks, _, n = MAP.coastal(towns, sea)
	eq(n, 2)
	ok(picks[1] and picks[2] and not picks[3], "the two most coastal")
	local p1 = MAP.coastal({ towns[1], towns[2], towns[5] }, sea)
	local c = 0
	for _ in pairs(p1) do c = c + 1 end
	eq(c, 1, "one on a small map")
	-- the form: coastal before the draw, only with a shoreline to follow; saved stays
	F.withForms(function()
		local f = FM.pick({ coastal = { coastal = true, rank = 1, score = 1 } }, { id = "EU_ORGANIC", seed = 3 }, nil,
			{ shore = 0.8 })
		eq(f.id, "shore"); eq(f.coastal, true)
		local none = FM.pick({ coastal = { coastal = true, rank = 1, score = 1 } }, { id = "EU_ORGANIC", seed = 3 }, nil,
			{ shore = 0 })
		ok(none == nil or not none.coastal, "no shoreline: no coastal form")
		local sv = FM.pick({ frame = { form = "shore", coastal = true, axis = 0 } }, { id = "EU_ORGANIC", seed = 3 }, nil, {})
		eq(sv.coastal, true)
		local p = { shape = { id = "shore", shore = { depthCap = 240 } }, irregular = {} }
		FM.apply(f, p)
		ok(p.shape.shore.depthCap >= FM.COASTAL_DEPTH[1] and p.shape.shore.depthCap <= FM.COASTAL_DEPTH[2], "shallow")
		eq(p.form.coastal, true)
	end)
end)

test("terrain squeeze: steep slopes, water and forest raise it; it leans the form weights toward clustered", function()
	local open = SITE.features({ meanSlope = 0.01, p95Slope = 0.03, waterFraction = 0 }, nil, 0)
	local tight = SITE.features({ meanSlope = 0.05, p95Slope = 0.22, waterFraction = 0.2 }, nil, 0.5)
	eq(open.squeeze, 0)
	ok(tight.squeeze >= 0.6, "squeezed " .. tight.squeeze)
	local a = FM.siteFactors(open)
	local b = FM.siteFactors(tight)
	ok(b.clustered / a.clustered > 1.3, "more clustered")
	ok(b.sprawling < a.sprawling, "less sprawling")
end)
