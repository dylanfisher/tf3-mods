-- Strong town characters (ot_character, 2026-10-14; CHARACTERS_BRIEF.md, NEXT_PHASE_BRIEF 54): the kinds' site tests
-- (a site that picks each kind, one that must not), the kinds' signature metrics on planned increments, the map's
-- selection (quota, no duplicate kind, no neighbours, deterministic, stable after a reload), the save fields, the
-- densify trait, and the roundabout town's one-way rings (ot_ring: one-way, a node config on every node, no live
-- junction touched).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local SITE = ug_require(F.DIR .. "ot_site.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")
local RG = ug_require(F.DIR .. "ot_ring.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local A = ug_require(F.DIR .. "ot_assess.lua")
local UP = ug_require(F.DIR .. "ot_upward.lua")
local MO = ug_require(F.DIR .. "ot_motif.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local RB_DIR = here .. "../../mods/square_roundabouts/content"
local cache = {}
--- ug_require for square_roundabouts' modules (loaded from the repo, as the dev mod's test does).
local function req(path)
	if cache[path] ~= nil then return cache[path] end
	local mod, rel = path:match("^([%w_]+)::(/.*)$")
	if mod ~= "square_roundabouts" then return ug_require(path) end
	local env = setmetatable({ ug_require = req }, { __index = _ENV })
	local m = assert(loadfile(RB_DIR .. rel, "t", env))()
	cache[path] = m
	return m
end

---------------------------------------------------------------------------
-- synthetic sites (town at the origin)

local S = {}
S.flat = F.flat
--- an isolated round hill: the summit 70 m over the plain at the origin
S.hill = T.sampler(function(x, y) return 20 + 70 * math.exp(-(x * x + y * y) / (350 * 350)) end)
S.cliff = F.cliff(0)
S.beach = F.coast(300)
--- a narrow cove opening east to the sea (beyond x = 700), steep sides (9 %)
S.cove = T.sampler(function(x, y)
	if x > 700 then return -3 end
	if x > 60 and math.abs(y) < 80 + 0.4 * (x - 60) then return -3 end
	local dSea = 700 - x
	local dIn = x > 60 and (math.abs(y) - (80 + 0.4 * (x - 60))) or math.sqrt((x - 60) ^ 2 + math.max(0, math.abs(y) - 80) ^ 2)
	return 2 + 0.09 * math.max(1, math.min(dSea, dIn))
end)
S.river = F.river(-120)
S.valley = F.valley(0)
--- an island of radius 520 m in the sea
S.island = T.sampler(function(x, y)
	local r = math.sqrt(x * x + y * y)
	if r > 520 then return -3 end
	return 2 + (520 - r) * 0.02
end)

--- A CH.site record for sampler s at the origin. o = { year, region, country, industry, rbOk }.
local function siteOf(s, o)
	o = o or {}
	local stats = T.stats(s, 0, 0, 600, 24)
	local wide = T.wide(s, 0, 0, 2000)
	local feats = SITE.features(stats, wide)
	local dr = stats.dirRelief
	local probe = CH.probe(s, 0, 0, (dr and dr.valley) and dr.axis or nil)
	local year = o.year or 1925
	return CH.site({ id = o.id or 1, x = o.x or 0, y = o.y or 0, stats = stats, wide = wide, feats = feats, probe = probe,
		year = year, era = I.era(year), region = o.region or "EU", country = o.country, newTemplates = I.newTemplates(year),
		cap = o.cap or 600, industry = o.industry, rbOk = o.rbOk })
end

local function score(kind, site)
	local k = CH.BY_ID[kind]
	return k.eligible(site)
end

local HEAVY = { d = 650, kind = "heavy", x = 650, y = 0 }

-- each kind: the site that picks it, the site that must not
local CASES = {
	{ kind = "hilltop", yes = function() return siteOf(S.hill) end, no = function() return siteOf(S.flat) end },
	{ kind = "clifftop", yes = function() return siteOf(S.cliff) end, no = function() return siteOf(S.beach) end },
	{ kind = "harbour_cove", yes = function() return siteOf(S.cove) end, no = function() return siteOf(S.beach) end },
	{ kind = "waterfront", yes = function() return siteOf(S.river) end, no = function() return siteOf(S.flat) end },
	{ kind = "street_village", yes = function() return siteOf(S.valley) end, no = function() return siteOf(S.hill) end },
	{ kind = "company_town", yes = function() return siteOf(S.flat, { industry = HEAVY }) end,
		no = function() return siteOf(S.hill, { industry = HEAVY }) end },
	{ kind = "garden_city", yes = function() return siteOf(S.flat, { year = 1925 }) end,
		no = function() return siteOf(S.valley, { year = 1925 }) end },
	{ kind = "island_town", yes = function() return siteOf(S.island) end, no = function() return siteOf(S.beach) end },
	{ kind = "roundabout_town", yes = function() return siteOf(S.flat, { year = 1965, rbOk = true }) end,
		no = function() return siteOf(S.flat, { year = 1965, rbOk = false }) end },
}

test("site tests: each kind picks its site and not the other", function()
	for _, c in ipairs(CASES) do
		local sy, wy = score(c.kind, c.yes())
		local sn, wn = score(c.kind, c.no())
		print(string.format("%-16s yes %.2f %-40s no %.2f %s", c.kind, sy, wy, sn, wn))
		ok(sy >= CH.MIN_SCORE, c.kind .. " yes " .. sy .. " " .. tostring(wy))
		ok(sn < CH.MIN_SCORE, c.kind .. " no " .. sn .. " " .. tostring(wn))
	end
end)

test("company town (§68): full within 1 km, a heavy works picks to ~1.7 km, a medium to ~1.5 km; steep never", function()
	local function sc(d, kind, slope, year)
		local site = siteOf(S.flat, { industry = { d = d, kind = kind, x = d, y = 0 }, year = year or 1900 })
		if slope then site.stats = setmetatable({ meanSlope = slope }, { __index = site.stats }) end
		return score("company_town", site)
	end
	near(sc(900, "heavy"), 1, 1e-9, "full within COMPANY_FULL")
	ok(sc(1275, "heavy") > 0.7, "the old threshold distance now scores well")
	ok(sc(1690, "heavy") >= CH.MIN_SCORE, "heavy at 1690 m picks")
	ok(sc(1800, "heavy") < CH.MIN_SCORE, "heavy at 1800 m does not")
	ok(sc(1530, "medium") >= CH.MIN_SCORE, "medium at 1530 m picks")
	ok(sc(1600, "medium") < CH.MIN_SCORE, "medium at 1600 m does not")
	eq(sc(2300, "heavy"), 0, "beyond COMPANY_R")
	eq(sc(1000, "heavy", 0.06), 0, "steep")
	-- the archived maps' best company sites (session 2026-10-13_1848_sqot 66044, 2026-10-14_0119_sqot 61035,
	-- 2026-10-14_0814_sqot 60343, 2026-10-13_2355_sqot 58806): every one scored under 0.4 with 1.25 - d / 1500
	for _, r in ipairs({ { 1346, "heavy", 0.03 }, { 1516, "heavy", 0.02 }, { 1559, "heavy", 0.02 }, { 1436, "medium", 0.02 } }) do
		local old = (r[2] == "heavy" and 1 or 0.75) * math.max(0, math.min(1, 1.25 - r[1] / 1500))
		ok(old < CH.MIN_SCORE, "old score " .. old)
		ok(sc(r[1], r[2], r[3]) >= CH.MIN_SCORE, string.format("%s at %d m now picks: %.2f", r[2], r[1], sc(r[1], r[2], r[3])))
	end
	-- 81939 (2026-10-14_2237_sqot-dev): a heavy works at 1277 m but mean slope 0.09: still none
	eq(sc(1277, "heavy", 0.09), 0)
	-- the late era halves it, as before
	ok(sc(1500, "heavy", nil, 1970) < CH.MIN_SCORE, "1970: half")
end)

---------------------------------------------------------------------------
-- signature metrics

local MT = ug_require(F.DIR .. "ot_metrics.lua")

--- The resolved style of a town at the origin on sampler s: kind (or nil: the plain town, styleId forced or drawn).
local function styleAt(s, kind, o)
	o = o or {}
	local r = { townId = o.town or 11, year = o.year or 1925, nameList = o.list or "::/names/europe/europe.names",
		pos = { 0, 0 }, capacity = o.cap or 900 }
	r.terrain = T.stats(s, 0, 0, 600, 24)
	local inp = I.build(r)
	inp.wide = T.wide(s, 0, 0, 2000)
	if kind then
		inp.charKind, inp.charForm, inp.charMotifs = kind, CH.formFor(kind), CH.motifsFor(kind)
		inp.charSite = o.site or { region = inp.region, industry = o.industry }
		inp.autoStyle = true
	elseif o.style then
		inp.forceStyle = o.style
	else
		inp.autoStyle = true
	end
	return ST.resolve(inp)
end

--- n increments of up to `edges` from a round core on sampler s. Returns { segs, incs, g, style }.
local function grow(style, s, n, edges)
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local out = { segs = {}, incs = {}, g = g, style = style }
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = s, join = "deadEnd", maxEdges = edges or 18 })
		if #inc.edges == 0 then break end
		for _, e in ipairs(inc.edges) do out.segs[#out.segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2], class = e.class } end
		out.incs[#out.incs + 1] = inc
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return out
end

local function lengthOf(segs)
	local L = 0
	for _, sg in ipairs(segs) do L = L + G.dist(sg[1], sg[2], sg[3], sg[4]) end
	return L
end

--- r90 of the new streets' midpoints and the length per hectare of that disc.
local function spread(segs, cx, cy)
	local d = {}
	for _, sg in ipairs(segs) do d[#d + 1] = G.dist(cx or 0, cy or 0, (sg[1] + sg[3]) / 2, (sg[2] + sg[4]) / 2) end
	table.sort(d)
	local r90 = d[math.max(1, math.floor(#d * 0.9))] or 0
	return r90, lengthOf(segs) / math.max(1, math.pi * r90 * r90 / 10000)
end

--- Share of the length within `tol` deg of heading a (or of a + 90 when both).
local function alongShare(segs, a, tol, both)
	local L, ok_ = 0, 0
	for _, sg in ipairs(segs) do
		local l = G.dist(sg[1], sg[2], sg[3], sg[4])
		local h = G.atan2(sg[4] - sg[2], sg[3] - sg[1])
		local d = math.deg(G.lineAngleDiff(h, a))
		if both then d = math.min(d, math.abs(90 - d)) end
		L = L + l
		if d <= tol then ok_ = ok_ + l end
	end
	return L > 0 and ok_ / L or 0
end

--- Share of the length running round the centre (more than 60 deg off the radial line).
local function ringShare(segs, cx, cy)
	local L, rg = 0, 0
	for _, sg in ipairs(segs) do
		local l = G.dist(sg[1], sg[2], sg[3], sg[4])
		local mx, my = (sg[1] + sg[3]) / 2, (sg[2] + sg[4]) / 2
		local rad = G.atan2(my - (cy or 0), mx - (cx or 0))
		local h = G.atan2(sg[4] - sg[2], sg[3] - sg[1])
		L = L + l
		if math.deg(G.lineAngleDiff(h, rad)) > 60 then rg = rg + l end
	end
	return L > 0 and rg / L or 0
end


--- Share of the land within radius R of the origin (50 m cells) within 80 m of a new street.
local function cover(segs, R)
	local cells, hit = 0, 0
	for x = -R, R, 50 do
		for y = -R, R, 50 do
			if x * x + y * y <= R * R then
				cells = cells + 1
				for _, sg in ipairs(segs) do
					if (G.pointSegDist(x, y, sg[1], sg[2], sg[3], sg[4])) < 80 then hit = hit + 1 break end
				end
			end
		end
	end
	return cells > 0 and hit / cells or 0
end

--- Share of the length on main streets along heading a (within tol deg).
local function mainAlong(segs, a, tol)
	local L, m = 0, 0
	for _, sg in ipairs(segs) do
		local l = G.dist(sg[1], sg[2], sg[3], sg[4])
		L = L + l
		if sg.class == "main" and math.deg(G.lineAngleDiff(G.atan2(sg[4] - sg[2], sg[3] - sg[1]), a)) <= tol then m = m + l end
	end
	return L > 0 and m / L or 0
end

--- Runs fn with town forms on (ot_form; the fixtures turn them off).
local function withForms(fn)
	FM.ENABLED = true
	local okF, err = pcall(fn)
	FM.ENABLED = false
	assert(okF, err)
end

local N = 8

test("signature: hilltop is compact and dense on its summit", function()
	withForms(function()
		local k = grow(styleAt(S.hill, "hilltop"), S.hill, N)
		local p = grow(styleAt(S.hill, nil), S.hill, N)
		local rk, dk = spread(k.segs)
		local rp, dp = spread(p.segs)
		print(string.format("hilltop %s/%s r90 %.0f dens %.0f m/ha | plain %s/%s r90 %.0f dens %.0f", k.style.id, k.style.form.id,
			rk, dk, p.style.id, p.style.form and p.style.form.id or "-", rp, dp))
		eq(k.style.id, "MED_HILL")
		eq(k.style.form.id, "clustered")
		ok(dk >= 1.5 * dp, "denser")
		ok(rk <= rp + 20, "no farther out")
		ok(k.style.maxSlope > 0.1, "steep lanes")
		ok(k.style.block.len >= ST.MIN_BLOCK and k.style.block.len <= 40, "small blocks, never below MIN_BLOCK")
	end)
end)

test("signature: clifftop is a shallow strip along the cliff", function()
	withForms(function()
		local k = grow(styleAt(S.cliff, "clifftop"), S.cliff, N)
		local p = grow(styleAt(S.cliff, nil), S.cliff, N)
		local function depth(segs)
			local d = 0
			for _, sg in ipairs(segs) do d = math.max(d, 320 - math.min(sg[1], sg[3])) end
			return d
		end
		print(string.format("clifftop %s/%s depth %.0f m | plain %s depth %.0f m", k.style.form.id, k.style.shape.id, depth(k.segs),
			p.style.form and p.style.form.id or "-", depth(p.segs)))
		eq(k.style.shape.id, "shore")
		ok(depth(k.segs) <= 230, "strip depth")
		ok(depth(k.segs) < depth(p.segs), "shallower than the plain town")
		ok(k.style.maxSlope <= 0.07, "nothing down the cliff")
		ok(k.style.shoreFront ~= nil, "the promenade")
	end)
end)

test("signature: harbour cove is tight and dense around its bay", function()
	withForms(function()
		-- (§68: the comparison runs without motifs. The motif draws moved to rng.decide and swapped this site's picks
		-- (cove fishing_village -> harbour_crescent, the plain town harbour_crescent -> hill_climb), and the kind's
		-- tightness is its own geometry, not a motif's; the cove's motif is checked on its own below)
		local kd = styleAt(S.cove, "harbour_cove")
		local keepMO = MO.ON
		MO.ON = false
		local okG, k, p = pcall(function() return grow(styleAt(S.cove, "harbour_cove"), S.cove, N), grow(styleAt(S.cove, nil), S.cove, N) end)
		MO.ON = keepMO
		assert(okG, k)
		local rk, dk = spread(k.segs)
		local rp, dp = spread(p.segs)
		local function mos(st)
			local ids = {}
			for _, m in ipairs(st.motifs or {}) do ids[#ids + 1] = m.id end
			return #ids > 0 and table.concat(ids, "+") or "-"
		end
		print(string.format("cove %s r90 %.0f dens %.0f block %.0fx%.0f motifs %s | plain %s r90 %.0f dens %.0f motifs %s", k.style.id,
			rk, dk, k.style.block.len, k.style.block.depth, mos(k.style), p.style.id, rp, dp, mos(p.style)))
		ok(dk >= 1.5 * dp, "denser")
		ok(rk < rp, "tighter")
		ok(k.style.waterPremium and k.style.waterPremium.gain >= 0.6, "streets to the water first")
		ok(#(kd.motifs or {}) >= 1 and (kd.motifs[1].id == "harbour_crescent" or kd.motifs[1].id == "fishing_village"),
			"a harbour motif: " .. mos(kd))
	end)
end)

test("signature: waterfront streets run with the river", function()
	withForms(function()
		local k = grow(styleAt(S.river, "waterfront"), S.river, N)
		local p = grow(styleAt(S.river, nil), S.river, N)
		local pk, pp = alongShare(k.segs, 0, 15, true), alongShare(p.segs, 0, 15, true)
		print(string.format("waterfront parallel/across share %.2f | plain %.2f; bridges always %s", pk, pp, tostring(k.style.charBridges)))
		ok(pk >= pp + 0.1, "parallel to the water")
		ok(k.style.charBridges == true)
	end)
end)

test("signature: street village is one long main street", function()
	withForms(function()
		local k = grow(styleAt(S.valley, "street_village"), S.valley, N)
		local p = grow(styleAt(S.valley, nil), S.valley, N)
		local sk, sp = mainAlong(k.segs, 0, 25), mainAlong(p.segs, 0, 25)
		print(string.format("street village main street share %.2f (%d edges) | plain %.2f (%d edges)", sk, #k.segs, sp, #p.segs))
		ok(sk >= 0.45, "the main street")
		ok(sp < 0.25)
		ok(k.style.radial and k.style.radial.spokes == 2, "two spokes: the street both ways")
	end)
end)

test("signature: company town is a strict grid to the works", function()
	withForms(function()
		local k = grow(styleAt(S.flat, "company_town", { industry = HEAVY, site = { industry = HEAVY } }), S.flat, N)
		local p = grow(styleAt(S.flat, nil), S.flat, N)
		local gk = alongShare(k.segs, k.style.axis or 0, 4, true)
		local gp = alongShare(p.segs, p.style.axis or 0, 4, true)
		print(string.format("company town grid share %.2f axis %.0f deg (works at 0 deg) | plain %.2f", gk, math.deg(k.style.axis), gp))
		ok(gk >= 0.7, "grid")
		ok(gk >= gp + 0.3)
		near(k.style.axis, 0, 1e-6, "main street toward the works")
	end)
end)

test("signature: garden city has rings and boulevards", function()
	withForms(function()
		local k = grow(styleAt(S.flat, "garden_city"), S.flat, N)
		local p = grow(styleAt(S.flat, nil, { style = "EU_EXTENSION" }), S.flat, N)
		local rk, rp = ringShare(k.segs), ringShare(p.segs)
		print(string.format("garden city ring share %.2f spokes %d greens %d | plain %.2f", rk, k.style.radial.spokes, #k.style.greens, rp))
		ok(rk >= 0.35 and rk >= rp + 0.15, "rings")
		ok(k.style.radial.spokes >= 8, "boulevards")
		ok(#k.style.greens >= 5, "a green belt")
	end)
end)

test("signature: island town covers its island", function()
	withForms(function()
		local k = grow(styleAt(S.island, "island_town"), S.island, N)
		local p = grow(styleAt(S.island, nil), S.island, N)
		local ck, cp = cover(k.segs, 520), cover(p.segs, 520)
		local _, dk = spread(k.segs)
		local _, dp = spread(p.segs)
		print(string.format("island cover %.2f dens %.0f | plain %.2f dens %.0f", ck, dk, cp, dp))
		ok(ck >= cp, "covers more of the island")
		ok(dk >= dp, "denser")
	end)
end)

---------------------------------------------------------------------------
-- the roundabout town

local function ringTown(n, share)
	local geo = assert(RG.load(req))
	local st = styleAt(S.flat, "roundabout_town", { year = 1965 })
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local out = { rings = 0, incs = {}, skipped = {}, style = st, geo = geo }
	for k = 1, n do
		local inc = core.planIncrement(g, st, { terrain = F.flat, join = "deadEnd", maxEdges = 24 })
		if #inc.edges == 0 then break end
		local before = {}
		for _, e in ipairs(inc.edges) do
			if e.node0 > 0 then before[e.node0] = true end
			if e.node1 > 0 then before[e.node1] = true end
		end
		local res = RG.mark(inc, { geo = geo, g = g, share = share or st.rings, draw = function(x, y)
			return rng.unit(st.seed, "rb", math.floor(x / 10), math.floor(y / 10)) end })
		out.rings = out.rings + #res.rings
		for _, sk in ipairs(res.skipped) do out.skipped[#out.skipped + 1] = sk end
		local nodesBefore = {}
		for _, gn in ipairs(g.nodes) do nodesBefore[#nodesBefore + 1] = { x = gn.x, y = gn.y } end
		out.incs[#out.incs + 1] = { inc = inc, before = before, nodes = nodesBefore }
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return out
end

--- The proposal info for an increment on graph g (every joined node an existing town node with a config).
local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local function infoFor(inc)
	local nodes = {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n > 0 then nodes[n] = { hasConfig = true, edges = { 9000 + n }, lanes = 4, src = 9000 + n, template = SMALL } end
		end
	end
	return { nodes = nodes, sources = { [SMALL] = 77 }, fallback = 77 }
end

test("roundabout town: rings at its own new crossings, one-way, every node configured, no live junction touched", function()
	withForms(function()
		local o = ringTown(10)
		print(string.format("roundabout town %s/%s: %d rings in %d increments, skipped %d", o.style.id,
			o.style.form and o.style.form.id or "-", o.rings, #o.incs, #o.skipped))
		ok(o.rings >= 2, "rings: " .. o.rings)
		local checked = 0
		for _, rec in ipairs(o.incs) do
			local inc = rec.inc
			if inc.rings then
				-- (no existing node gained an edge: the joins are those of the plain plan)
				for _, e in ipairs(inc.edges) do
					if e.node0 > 0 then ok(rec.before[e.node0], "join kept") end
					if e.node1 > 0 then ok(rec.before[e.node1], "join kept") end
					if e.ring then
						ok(e.node0 < 0 and e.node1 < 0, "ring nodes are new")
						ok(e.oneway == true and e.template == RG.ONEWAY)
					end
				end
				for _, r in ipairs(inc.rings) do
					local cx, cy = r.centre[1], r.centre[2]
					for _, e in ipairs(inc.edges) do
						if e.ring and G.dist((e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2, cx, cy) < r.R * 1.2 then
							-- counter-clockwise: the tangent turns left of the radius
							local rx, ry = e.p0[1] - cx, e.p0[2] - cy
							ok(rx * e.t0[2] - ry * e.t0[1] > 0, "counter-clockwise")
							near(G.dist(e.p0[1], e.p0[2], cx, cy), r.R, 0.5, "on the ring")
						end
					end
					-- no existing street within the ring
					for _, gn in ipairs(rec.nodes) do ok(G.dist(gn.x, gn.y, cx, cy) > r.R + RG.CLEAR, "empty land") end
				end
				local spec, err = PR.build(inc, infoFor(inc))
				ok(spec ~= nil, tostring(err))
				-- every new node has a config, every lane index exists, no -0
				local cfg = {}
				for _, c in ipairs(spec.cfgAdd) do cfg[c.node] = c end
				for _, nd in ipairs(inc.nodes) do ok(cfg[nd.entity] ~= nil, "config on new node " .. nd.entity) end
				ok(PR.noNegativeZero(spec))
				-- one-way at the ring nodes: ring in -> ring out yes, ring out -> anything never
				local byEnt = {}
				for _, e in ipairs(inc.edges) do byEnt[e.entity] = e end
				for _, nd in ipairs(inc.nodes) do
					if nd.ring then
						local conns = cfg[nd.entity].conns
						local inOut = false
						for _, cn in ipairs(conns) do
							local a, b = byEnt[cn[1]], byEnt[cn[3]]
							if a.ring then ok(a.node1 == nd.entity, "only the arriving ring edge leads on") end
							if b.ring then ok(b.node0 == nd.entity, "only into the leaving ring edge") end
							if a.ring and b.ring then inOut = true end
						end
						ok(inOut, "the ring goes round")
					end
				end
				checked = checked + 1
				-- and out again: the plain crossing as planned
				local nE = #inc.edges
				local nR = #inc.rings
				eq(RG.strip(inc), nR)
				ok(#inc.edges < nE and inc.rings == nil and inc.ringUndo == nil, "stripped")
			end
		end
		ok(checked >= 1)
	end)
end)

test("roundabout town: no rings without square_roundabouts, before 1940, or for other kinds", function()
	local none, why = RG.load(function() error("no such module") end)
	eq(none, nil)
	eq(why, "noMod")
	local site = siteOf(S.flat, { year = 1965, rbOk = false })
	eq(select(2, score("roundabout_town", site)), "noRoundabouts")
	local early = siteOf(S.flat, { year = 1935, rbOk = true })
	ok(score("roundabout_town", early) == 0, "era")
	local fr = siteOf(S.flat, { year = 1945, rbOk = true, country = "france" })
	ok(score("roundabout_town", fr) > 0, "France from 1940")
	-- a garden city plans no rings
	withForms(function()
		local st = styleAt(S.flat, "garden_city")
		eq(st.rings, nil)
	end)
end)

---------------------------------------------------------------------------
-- selection

S.plain = F.steep(0.11)

test("selection: quota by town count", function()
	eq(CH.quota(0), 0)
	eq(CH.quota(1), 1)
	eq(CH.quota(5), 1)
	eq(CH.quota(9), 1)
	eq(CH.quota(10), 1)
	eq(CH.quota(12), 2)
	eq(CH.quota(16), 2)
	eq(CH.quota(24), 3)
	eq(CH.quota(60), 3)
end)

local SITES = {}
local function siteCopy(name, id, x, y, o)
	SITES[name] = SITES[name] or siteOf(S[name], o)
	local s = {}
	for k, v in pairs(SITES[name]) do s[k] = v end
	s.id, s.x, s.y = id, x, y
	return s
end

--- 12 towns: a hill at the origin, a cliff 1.5 km away (a neighbour), a valley far off, flat towns, the rest plain.
local function mapSites(flat)
	local out = {}
	out[#out + 1] = siteCopy("hill", 101, 0, 0)
	out[#out + 1] = siteCopy("cliff", 102, 1500, 0)
	out[#out + 1] = siteCopy("valley", 103, 20000, 0)
	for i = 1, 9 do
		if flat and i <= 4 then out[#out + 1] = siteCopy("flat", 200 + i, -8000 * i, 9000, { year = 1965, rbOk = true })
		else out[#out + 1] = siteCopy("plain", 200 + i, -8000 * i, -9000) end
	end
	return out
end

test("selection: highest first, no duplicate kind, no neighbours, deterministic, stable after a reload", function()
	local sites = mapSites(false)
	local picks, count, rows = CH.select(sites, { seed = 5 })
	eq(count, 2)
	ok(picks[101] and picks[101].kind == "hilltop", "the hill")
	ok(picks[103] and picks[103].kind == "street_village", "the valley")
	ok(picks[102] == nil, "the cliff is the hill's neighbour")
	local n = 0
	for _ in pairs(picks) do n = n + 1 end
	eq(n, 2)
	eq(#rows, 12)
	-- deterministic, whatever the order
	local rev = {}
	for i = #sites, 1, -1 do rev[#rev + 1] = sites[i] end
	local p2 = CH.select(rev, { seed = 5 })
	for id, p in pairs(picks) do eq(p2[id] and p2[id].kind, p.kind) end
	-- many flat towns: garden city and roundabout town both score 1, but one kind once
	local flat = mapSites(true)
	local p3 = CH.select(flat, { seed = 9 })
	local kinds = {}
	for _, p in pairs(p3) do
		ok(not kinds[p.kind], "no duplicate " .. p.kind)
		kinds[p.kind] = true
	end
	-- a reload: the saved picks stay (fixed), a framed town without one never becomes one, the quota counts them
	local fixed = { [102] = "clifftop", [101] = false }
	local p4 = CH.select(sites, { seed = 5, fixed = fixed })
	eq(p4[102].kind, "clifftop")
	eq(p4[101], nil)
	ok(p4[103] and p4[103].kind == "street_village")
	-- excluded towns (secluded, metropolis) never
	local p5 = CH.select(sites, { seed = 5, excluded = { [101] = "secluded" } })
	eq(p5[101], nil)
end)

test("save: the map's picks and the frame's kind round-trip; old saves have none", function()
	local raw = SV.applyChars(nil, { p = { { t = 101, k = CH.INDEX.hilltop }, { t = 103, k = CH.INDEX.street_village } } })
	local picks, has = SV.chars(raw)
	ok(has)
	eq(picks[101], CH.INDEX.hilltop)
	eq(CH.byIndex(picks[103]).id, "street_village")
	-- the first record wins
	local raw2, changed = SV.applyChars(raw, { p = { { t = 5, k = 2 } } })
	eq(changed, false)
	eq(SV.chars(raw2)[5], nil)
	-- an old save: no record
	eq(SV.chars(SV.normalize({ v = 1, frames = {} })), nil)
	withForms(function()
		local st = styleAt(S.hill, "hilltop")
		eq(st.styleSource, "character")
		eq(st.charIndex, CH.INDEX.hilltop)
		local fp = SV.frameParam(101, st, nil)
		eq(fp.ck, CH.INDEX.hilltop)
		ok(fp.st ~= nil, "its style saved")
		local r3 = SV.normalize(SV.applyFrame(raw, fp))
		eq(SV.frame(r3, 101).charKind, CH.INDEX.hilltop)
		-- a plain town's frame has none
		local fp2 = SV.frameParam(102, styleAt(S.flat, nil), nil)
		eq(fp2.ck, nil)
		-- densify draw saved on the frame, first wins, no frame ignored
		local r4 = SV.applyDense(r3, { town = 101, v = 2 })
		eq(SV.frame(r4, 101).densify, 2)
		local r5, ch2 = SV.applyDense(r4, { town = 101, v = 1 })
		eq(ch2, false)
		eq(SV.frame(r5, 101).densify, 2)
		local _, ch3 = SV.applyDense(r4, { town = 999, v = 1 })
		eq(ch3, false)
	end)
end)

test("apply: the kind's style, form and motif taste win over the draw; forbidden motifs never drawn", function()
	withForms(function()
		local hits = 0
		for town = 1, 30 do
			local st = styleAt(S.valley, "street_village", { town = town })
			eq(st.form.charKind, "street_village")
			for _, m in ipairs(st.motifs or {}) do
				ok(m.id ~= "valley_fishbone" and m.id ~= "village_green" and m.id ~= "ring_road", "forbidden " .. m.id)
				if m.id == "ribbon_village" then hits = hits + 1 end
			end
		end
		print("street village with a ribbon village motif: " .. hits .. " of 30 (needs a country road)")
		-- a hill site's own draw would be EU organic linear: the kind gives MED hill, clustered, the summit as centre
		local st = styleAt(S.hill, "hilltop")
		eq(st.id, "MED_HILL")
		eq(st.form.why, "char:hilltop")
		near(st.centre[1], 0, 30)
	end)
end)

test("unchanged: a town without a kind never runs the character hooks", function()
	local a0, p0, d0 = CH.apply, CH.post, CH.densifyStyle
	CH.apply = function() error("apply called") end
	CH.post = function() error("post called") end
	CH.densifyStyle = function() error("densify called") end
	local okR, err = pcall(function()
		withForms(function()
			for _, s in ipairs({ S.flat, S.hill, S.river, S.cliff, S.island }) do
				for town = 1, 5 do
					local st = styleAt(s, nil, { town = town })
					ok(st.charKind == nil and st.rings == nil and st.densify == nil)
				end
			end
		end)
	end)
	CH.apply, CH.post, CH.densifyStyle = a0, p0, d0
	ok(okR, tostring(err))
end)

---------------------------------------------------------------------------
-- densify

test("densify: about a third of the towns, few linear ones, never a blocked town", function()
	local forms = { "clustered", "radiating", "sprawling", "linear", "wide", "fingers", "shore" }
	local on, n, lin, linOn, cl, clOn = 0, 0, 0, 0, 0, 0
	for i = 1, 700 do
		local f = forms[(i % #forms) + 1]
		local d = CH.densifyDraw({ seed = rng.hash("t", i), form = f, sizeRank = (i % 11) / 10, central = (i % 7) / 6,
			rail = i % 3 == 0 })
		n = n + 1
		if d then on = on + 1 end
		if f == "linear" then lin = lin + 1; if d then linOn = linOn + 1 end end
		if f == "clustered" then cl = cl + 1; if d then clOn = clOn + 1 end end
	end
	print(string.format("densify: %d of %d (%.0f %%), linear %d/%d, clustered %d/%d", on, n, 100 * on / n, linOn, lin, clOn, cl))
	-- (0.42 until the 2026-10-14 seed-a recalibration: this synthetic mix has more big, central, rail and compact
	-- towns than a real map, whose own mix is checked in "replay seed-a map")
	ok(on / n >= 0.3 and on / n <= 0.5, "a third")
	ok(linOn / lin < 0.5 * clOn / cl, "few linear")
	eq(CH.densifyDraw({ seed = 1, blocked = "character" }), false)
end)

test("densify: the levers (hold, levels) and persons per building rise after maturity, not in a sprawl town", function()
	-- the levers
	ok(not A.matureHold(1, 0.5), "a plain grown town builds at 50 % free lots")
	ok(A.matureHold(1, 0.5, { holdFree = CH.DZ_HOLD_FREE, demK = CH.DZ_DEMK }), "a densify town holds")
	local act, k = UP.levelDecide({ buildings = 600, pb = 5, mat = 0.8, on = true, ours = 0, densify = true })
	eq(act, "set")
	ok(k >= UP.DZ_K_MIN)
	eq(UP.levelDecide({ buildings = 600, pb = 5, mat = 0.95, on = true, ours = 0 }), nil, "a grown plain town at pb 5: the engine's")
	eq(select(2, UP.levelDecide({ buildings = 600, pb = 5, mat = 0.8, on = true, ours = 0 })), -0.25, "still easing back (blend)")
	eq(UP.levelDecide({ buildings = 600, pb = 3, mat = 0.8, on = true, ours = 0, char = "off" }), nil)
	-- a yearly model (an offline proxy of the game): persons grow 4 % a year; the mod's demand build adds 40 lots unless
	-- the mature hold holds; the game adds 30 lots of its own streets when the town has fewer than 10 free; new persons
	-- move into new buildings whose size follows the level mix: the game's base shares x the level weights (levels 3 /
	-- 4 exist from 1950 / 1990)
	local CAP, BASE = { 4, 8, 16, 30 }, { 0.7, 0.2, 0.07, 0.03 }
	local function model(dense)
		local P, B, L, kk = 2000, 370, 560, 0
		local pb0, pbEnd = nil, nil
		for _ = 1990, 2040 do
			local P2 = P * 1.04
			local mat = A.maturity(P2)
			local active = dense and mat >= CH.DZ_MAT
			local dz = active and { holdFree = CH.DZ_HOLD_FREE, demK = CH.DZ_DEMK } or nil
			if not A.matureHold(mat, (L - B) / L, dz) then L = L + 40 end
			if L - B < 10 then L = L + 30 end
			local a, k2 = UP.levelDecide({ buildings = B, pb = P / B, mat = mat, on = true, ours = kk, densify = active })
			if a == "set" then kk = k2 elseif a == "clear" then kk = 0 end
			local w = UP.levelWeights(kk)[1]
			local sw, sc = 0, 0
			for l = 1, 4 do sw, sc = sw + BASE[l] * w[l], sc + BASE[l] * w[l] * CAP[l] end
			local per = sc / sw
			B = B + math.min(L - B, math.max(0, (P2 - P) / per))
			P = P2
			if mat >= CH.DZ_MAT and pb0 == nil then pb0 = P / B end
			pbEnd = P / B
		end
		return pb0, pbEnd
	end
	local d0, d1 = model(true)
	local s0, s1 = model(false)
	print(string.format("persons per building from maturity to 2040: densify %.2f -> %.2f, sprawl %.2f -> %.2f", d0, d1, s0, s1))
	ok(d1 >= d0 * 1.2, "densify rises")
	ok(d1 > s1 * 1.15, "above the sprawl town")
	ok(s1 <= s0 * 1.3, "the sprawl town stays about as it was")
end)

---------------------------------------------------------------------------
-- the driver: the chars phase, the saved picks, the setting, the dev force, the densify draw

local D = ug_require(F.DIR .. "ot_driver.lua")

--- A fake engine over a map: a hill town at the origin, a valley town 20 km east, ten towns on a plain slope.
local function fakeMap()
	local towns = { { 101, 0, 0 }, { 103, 20000, 0 } }
	for i = 1, 10 do towns[#towns + 1] = { 200 + i, -8000 * i, -9000 } end
	local sam = T.sampler(function(x, y)
		if x * x + y * y < 3000 * 3000 then return 20 + 70 * math.exp(-(x * x + y * y) / (350 * 350)) end
		if math.abs(x - 20000) < 3000 then return 20 + 0.0004 * y * y end
		return 3000 + 0.11 * x
	end)
	local E = { t = 0, logs = {}, events = {} }
	function E.nowUs() return E.t end
	function E.name(t) return "T" .. t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.towns()
		local o = {}
		for _, t in ipairs(towns) do o[#o + 1] = t[1] end
		return o
	end
	function E.boxCentre(id)
		for _, t in ipairs(towns) do if t[1] == id then return t[2], t[3] end end
		return nil
	end
	function E.sampler() return sam end
	function E.townCaps() return { target = 800, actual = 700 } end
	function E.year() return 1925 end
	function E.sendEvent(_id, name, p) E.events[#E.events + 1] = { name = name, param = p } end
	return E
end

local function newDriver(E, o)
	local d = D.new(E, "[T]")
	d.opts = { debug = true, strongCharacters = not (o and o.off) }
	d.newMap = not (o and o.old)
	return d
end

local function runChars(d, E)
	for _ = 1, 400 do
		E.t = E.t + 100000
		if not d:charsTick(E.t) then return true end
	end
	return false
end

local function logged(E, pat)
	for _, l in ipairs(E.logs) do if l:find(pat, 1, true) then return l end end
	return nil
end

test("driver: the chars phase picks once per new map, saves it, a reload keeps it; old maps and Off get none", function()
	local E = fakeMap()
	local d = newDriver(E)
	d:charsStart(0, nil)
	ok(runChars(d, E), "the phase ends")
	local picks = d.charPick.picks
	eq(picks[101] and picks[101].kind, "hilltop")
	eq(picks[103] and picks[103].kind, "street_village")
	ok(logged(E, "CHARACTER pick on=true"), "pick line")
	ok(logged(E, "kinds=hilltop:T101,street_village:T103"), "kinds")
	ok(logged(E, "CHARACTER town=101 name=T101 event=pick kind=hilltop"), "town line")
	local ev = nil
	for _, e in ipairs(E.events) do if e.name == SV.EV_CHARS then ev = e end end
	ok(ev ~= nil and #ev.param.p == 2, "saved")
	eq(d:charKindOf(101), "hilltop")
	-- the secluded towns (ot_map): never a strong-kind town, the quota passes on
	local nSec = 0
	for _, id in ipairs(E.towns()) do
		local c = d:characterOf(id, E.t)
		if c and c.character then
			nSec = nSec + 1
			ok(id ~= 101 and id ~= 103, "a kind town is no secluded town")
		end
	end
	ok(nSec >= 2, "secluded towns " .. nSec)
	-- a frame without a kind: none, for good
	local framed = SV.applyFrame(nil, { town = 101, a = 0, x = 0, y = 0 })
	eq(d:charKindOf(101, framed), nil)
	-- a reload: the saved record
	local saved = SV.applyChars(nil, ev.param)
	local E2 = fakeMap()
	local d2 = newDriver(E2, { old = true })
	d2:charsStart(0, saved)
	eq(d2.charPick.why, "saved")
	eq(d2.charPick.picks[101].kind, "hilltop")
	eq(d2.charPick.picks[103].kind, "street_village")
	ok(not d2:charsTick(0), "no phase")
	-- an old map: none
	local E3 = fakeMap()
	local d3 = newDriver(E3, { old = true })
	d3:charsStart(0, nil)
	eq(d3.charPick.why, "oldMap")
	eq(d3:charKindOf(101), nil)
	ok(logged(E3, "CHARACTER pick on=false why=oldMap"))
	-- the setting Off: none, saved ones ignored too
	local E4 = fakeMap()
	local d4 = newDriver(E4, { off = true })
	d4:charsStart(0, saved)
	eq(d4.charPick.why, "setting")
	eq(d4:charKindOf(101), nil)
	-- the dev force
	eq(d:devCharacter(205, "garden_city"), "garden_city")
	eq(d:charKindOf(205), "garden_city")
	eq(d:devCharacter(205, "-"), "-")
	eq(d:charKindOf(205), nil)
	-- the naming hook: the character record carries the names' kind (ot_placename charForms), never a secluded flag
	local c101 = d:characterOf(101, E.t)
	eq(c101.nameKind, "hilltop")
	eq(c101.character, false)
	eq(d:characterOf(103, E.t).nameKind, "street")
	for _, k in ipairs(CH.KINDS) do
		if k.selectable then ok(CH.nameKind(k.id) ~= nil, k.id .. " has a name kind") end
	end
	local cue = d:characterNameCue(101)
	eq(cue.nameKind, "hilltop")
	eq(cue.kind, "hilltop")
	eq(cue.tag, "hill")
	ok(#cue.words >= 3)
end)

test("driver: densify is drawn once a town is mature, saved on its frame, never for a strong-character town", function()
	local E = fakeMap()
	local d = newDriver(E)
	d:charsStart(0, nil)
	runChars(d, E)
	local saved = SV.applyFrame(nil, { town = 205, a = 0, x = -40000, y = -9000 })
	saved = SV.applyFrame(saved, { town = 101, a = 0, x = 0, y = 0, ck = CH.INDEX.hilltop })
	d.saved = SV.normalize(saved)
	local function m(mat) return { dem = { mat = mat }, caps = { actual = 2400, target = 2400 }, buildings = 420,
		ext = { cx = -40000, cy = -9000, r = 300 } } end
	d:densifyCheck(205, m(0.3), E.t)
	eq(d:townState(205).dz, nil, "young: not drawn")
	ok(not d:densifyActive(205))
	d:densifyCheck(205, m(0.8), E.t)
	local dz = d:townState(205).dz
	ok(dz == 1 or dz == 2, "drawn")
	ok(logged(E, "DENSIFY town=205 name=T205 event=draw"), "DENSIFY line")
	local ev = nil
	for _, e in ipairs(E.events) do if e.name == SV.EV_DENSE then ev = e end end
	ok(ev and ev.param.town == 205 and ev.param.v == dz, "saved")
	eq(d:densifyActive(205), dz == 1)
	-- a strong-character town: never
	d:densifyCheck(101, m(0.8), E.t)
	eq(d:townState(101).dz, 2)
	ok(logged(E, "DENSIFY town=101 name=T101 event=draw on=false why=character"))
	-- the demand brake follows
	if dz == 1 then ok(d:densifyDemand(205) ~= nil) else eq(d:densifyDemand(205), nil) end
end)

test("params: Strong town characters On by default, Off read", function()
	local PA = ug_require(F.DIR .. "ot_params.lua")
	eq(PA.parse({}, {}).strongCharacters, true)
	eq(PA.parse({ strong_characters = 2 }, {}).strongCharacters, false)
	ok(PA.parse({}, {}).raw:find("strong_characters=", 1, true) ~= nil)
end)

---------------------------------------------------------------------------
-- replay of the seed-a map (run 2026-10-14_2237 load 2: europe list, temperate, a 1900 start; 16 towns, coasts, lake
-- bays, a river, hills; no pick then: every town `applied=no:low`). The sites as the log read them (TERRAIN, STYLE
-- styleWhy, the garden city whys' probe flat); the probe's rings and the summit were not logged (nil here: the hill and
-- bay probes add nothing), the probe flat of the towns without a garden line is estimated from the rough share.

local SEED_A = {
	-- id, x, y, open, rough, coast, river, body, island, water kind, water m, shore L, meanSlope, wideSd, wideRange,
	-- wideWater, waterDirs, flat (nil: estimated), cap
	{ 60255, -2012, -2748, 0.00, 0.57, 0.74, 0, "lake", 0, "coast", 275, 3290, 0.08, 36.22, 111.35, 0.12, 5, nil, 3240 },
	{ 60256, -1696, 44, 0.10, 0.26, 0.00, 1, "river", 0, "river", 250, 0, 0.04, 28.27, 107.01, 0.09, 4, nil, 4467 },
	{ 60257, -5500, -5320, 0.05, 0.26, 0.82, 0, "lake", 0, "coast", 225, 6039, 0.03, 30.49, 106.80, 0.30, 10, nil, 3825 },
	{ 60258, -7256, 4896, 0.07, 0.35, 0.57, 0, "lake", 0, "coast", 375, 6019, 0.06, 24.25, 86.00, 0.19, 8, nil, 3082 },
	{ 60259, 2804, 144, 0.46, 0.10, 0.74, 0, "lake", 0, "coast", 275, 5324, 0.02, 17.93, 70.95, 0.12, 6, nil, 1462 },
	{ 60260, 364, 2640, 0.66, 0.07, 0.00, 0, nil, 0, nil, nil, nil, 0.02, 15.72, 58.78, 0.03, 2, 0.86, 2216 },
	{ 60261, -3968, 2568, 0.11, 0.26, 0.32, 0, "lake", 0, "coast", 525, 4460, 0.05, 24.64, 84.15, 0.17, 4, nil, 2574 },
	{ 60262, 1436, 6640, 0.67, 0.07, 0.00, 0, nil, 0, nil, nil, nil, 0.02, 15.78, 84.87, 0.00, 0, 0.95, 2866 },
	{ 60263, 4340, 3204, 0.00, 0.28, 0.60, 0, "sea", 1, "coast", 400, 4138, 0.05, 25.43, 84.82, 0.47, 13, nil, 2953 },
	{ 60264, -2412, 7324, 0.10, 0.35, 0.00, 0, nil, 0, nil, nil, nil, 0.06, 24.00, 88.60, 0.09, 5, nil, 2338 },
	{ 60265, 4280, -6416, 0.56, 0.08, 0.00, 0, nil, 0, nil, nil, nil, 0.02, 16.61, 73.18, 0.05, 3, nil, 1247 },
	{ 60266, 7124, -616, 0.15, 0.25, 0.00, 0, nil, 0, nil, nil, nil, 0.02, 29.83, 94.96, 0.12, 4, nil, 1818 },
	{ 60267, 5516, -3240, 0.11, 0.23, 0.70, 0, "lake", 0, "coast", 300, 3129, 0.03, 28.11, 113.98, 0.23, 6, nil, 2032 },
	{ 60268, 5004, 6388, 0.01, 0.36, 0.00, 0, nil, 0, nil, nil, nil, 0.04, 35.32, 129.60, 0.02, 1, nil, 1718 },
	{ 60269, 1780, -3508, 0.38, 0.13, 0.00, 0, nil, 0, nil, nil, nil, 0.03, 20.41, 94.62, 0.03, 2, nil, 2235 },
	{ 60270, 724, -6788, 0.00, 0.57, 0.00, 0, nil, 0, nil, nil, nil, 0.08, 38.52, 140.60, 0.09, 5, nil, 3981 },
}

local function seedASites(year, region)
	year, region = year or 1900, region or "EU"
	local out = {}
	for _, r in ipairs(SEED_A) do
		local water = r[10] and { kind = r[10], distance = r[11] } or nil
		local stats = { meanSlope = r[13], water = water, shore = r[12] and r[12] > 0 and { L = r[12], island = false } or nil }
		out[#out + 1] = CH.site({ id = r[1], x = r[2], y = r[3], stats = stats,
			wide = { sd = r[14], range = r[15], water = r[16], waterDirs = r[17] },
			feats = { open = r[4], rough = r[5], coast = r[6], river = r[7], valley = 0, body = r[8], island = r[9] == 1 },
			probe = { flat = r[18] or math.max(0, 1 - 1.5 * r[5]), rings = {} },
			year = year, era = I.era(year), region = region, newTemplates = I.newTemplates(year), cap = r[19] * 0.6,
			rbOk = true })
	end
	return out
end

test("replay seed-a map: its 16 sites give 2 picks of different kinds", function()
	local sites = seedASites()
	local picks, count, rows = CH.select(sites, { seed = CH.mapSeed(sites) })
	local kinds, list = {}, {}
	for id, p in pairs(picks) do
		kinds[p.kind] = (kinds[p.kind] or 0) + 1
		list[#list + 1] = string.format("%d:%s:%.2f", id, p.kind, p.score)
	end
	table.sort(list)
	local elig = {}
	for _, row in ipairs(rows) do
		for _, sc in ipairs(row.scores) do
			if sc.score >= CH.MIN_SCORE then elig[#elig + 1] = string.format("%d:%s:%.2f", row.id, sc.kind, sc.score) end
		end
	end
	print("seed-a picks " .. table.concat(list, " ") .. " | eligible " .. table.concat(elig, " "))
	eq(count, 2)
	eq(#list, 2)
	for k, n in pairs(kinds) do ok(n == 1, "one of each kind " .. k) end
end)

test("replay seed-a map: densify draws about a third of the towns it may draw", function()
	-- (the three drawn towns of the run, as logged: form, size rank, centrality)
	local drawn = { { "shore", 0.26, 0.71 }, { "shore", 0.36, 0.34 }, { "shore", 0.26, 0.24 } }
	local sum = 0
	for _, d in ipairs(drawn) do
		local _, _, p = CH.densifyDraw({ seed = 1, form = d[1], sizeRank = d[2], central = d[3] })
		sum = sum + p
	end
	print(string.format("seed-a densify p (logged towns) mean %.2f (was 0.13-0.16)", sum / #drawn))
	ok(sum / #drawn >= 0.27 and sum / #drawn <= 0.4, "about a third")
	-- the map's form mix (STYLE form of the 16 towns), size / centre mid: about a third drawn over many seeds
	local forms = { "shore", "linear", "shore", "shore", "linear", "shore", "linear", "shore", "clustered", "linear",
		"radiating", "clustered", "radiating", "linear", "shore", "fingers" }
	local on, n = 0, 0
	for i = 1, 400 do
		for j, f in ipairs(forms) do
			n = n + 1
			if CH.densifyDraw({ seed = rng.hash("seedA", i, j), form = f, sizeRank = 0.3, central = 0.5 }) then on = on + 1 end
		end
	end
	print(string.format("seed-a form mix: %d of %d drawn (%.0f %%)", on, n, 100 * on / n))
	ok(on / n >= 0.27 and on / n <= 0.4, "about a third on this map")
end)

test("replay seed-a map, usa list from 1960 (load 3): the roundabout town keeps its pick", function()
	-- (the run picked garden_city at 60262 and roundabout_town at 60260; the coast kinds now score here too)
	local sites = seedASites(1960, "US")
	local picks = CH.select(sites, { seed = CH.mapSeed(sites) })
	local list, kinds = {}, {}
	for id, p in pairs(picks) do
		list[#list + 1] = string.format("%d:%s:%.2f", id, p.kind, p.score)
		kinds[p.kind] = id
	end
	table.sort(list)
	print("seed-a usa 1960 picks " .. table.concat(list, " "))
	eq(#list, 2)
	ok(kinds.roundabout_town ~= nil, "a roundabout town")
end)
