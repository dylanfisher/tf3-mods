-- Organic Towns: industrial satellite towns, "Works" (pure; 2026-10-13, round after the names run).
--
-- The dev "Industrial satellite probe" (run 2026-10-13_2113_sqot-dev, docs/findings/towns.md "A town created with
-- industrial-heavy initial capacities grows industrial"): a separate town made with makeTownCreateCmd and initial land
-- use capacities 10 / 10 / 200 grew ~92-93 % industrial (Ferryhill Works 17 / 17 / 395, Ellesmere Port Works 17 / 14 /
-- 398 after three growth passes); the user: "Ellesmere Port and satellite port works looks awesome together". The API
-- has town-wide capacities only (no per-area zoning), so an industrial quarter beside a town has to be its own town.
--
-- Sparingly (M.eligible): only on a map that was new when the mod first saw it (the saved `fresh` flag: adding the mod
-- to an old save never creates towns), a growing town past MIN_BUILDINGS, seeded CHANCE, at most one per town (the
-- frame's `wp`), a map quota (MAP_PER towns per Works, MAP_MAX at most), never for a Works town itself.
-- Where (M.pickSite): RING_D 0.8-1.5 km from the town's centre, by a harbour (HARBOUR_R) or a rail station (RAIL_R)
-- best, else across water from the centre (a river between: the far bank), else open land; dry within WET_R, gentle,
-- inside the map margin, nearer this town than any other and NEIGHBOUR_MIN from other town centres, never within
-- CHAR_CORE_M of a character town's centre, never past a gap line (ot_gap), CLEAR_R clear of streets / constructions /
-- fields (room for the new town's own streets), and reachable: a dry, gentle link line from one of the town's joinable
-- dead ends to LINK_SHORT m before the site.
-- The name (M.name): "<Town> Works" / "<Town> Docks" by a harbour / "<Town> Junction" by a station ..., in the name
-- list's language (de "<Town>-Werk" / "<Town>-Hafen", fr "<Town>-les-Forges" / "Port-<Town>", sv "<Town> bruk" ...),
-- unique among the map's town names.
-- The driver creates it (ot_engine.createTown, CAPS), fills its capacity target once (makeTownUpdateSizeCmd x1: a
-- forced size command fills it at once, docs/findings/towns.md), and at the parent's next demand build links the two
-- by a road: a street from the parent's dead end to the Works town's nearest dead end, its middle the era's country
-- template (locked, no houses), both joined ends plain town streets (M.linkStreets).
-- 2026-10-14 (run 2026-10-13_2355_sqot: no link ever built, `notJoined` / `crossing` / `obstacle`): the link goes
-- through ot_link (many pairs, detours, obstacles, zones; the driver plans the candidates in turn until both ends join),
-- and a town with an industry within IND_MAX gets its Works on the line to it, at about 2/3 of the way, named by the
-- industry's type (M.industrySite, "<Town> Quarry" / "<Town> Colliery" / "<Town>-Zeche" ...).
--
-- Save-safe: the created town is a normal town (removing the mod leaves it as it is); the mod only saves the ids
-- (ot_saved `wk`, the parent frame's `wp`). Every loop is bounded by RING_D x DIRS x dead ends. Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local SAT = ug_require "square_organic_towns::/organic_towns/ot_satellite.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local LK = ug_require "square_organic_towns::/organic_towns/ot_link.lua"

local M = {}

M.ON = true
M.MIN_BUILDINGS = 300     -- a town this big (buildings) may get one
M.CHANCE = 0.35           -- seeded share of the eligible towns
M.MAP_PER = 8             -- map quota: one Works per this many towns ...
M.MAP_MIN = 1             -- ... at least this many ...
M.MAP_MAX = 3             -- ... at most this many
M.CAPS = { 10, 10, 200 }  -- initial land use capacities (residential, commercial, industrial): the probe's
M.RING_D = { 800, 1000, 1200, 1500 }
M.DIRS = 24
M.WET_R = 100
M.MAX_SLOPE = 0.08
M.CORE_R = 220            -- m: the new town's room (map margin + this; slope read over half of it)
M.GAP_EXTENT = 300        -- m beyond the parent's houses' extent at least
M.NEIGHBOUR_MIN = 1300    -- m from any other town centre
M.CHAR_CORE_M = 1500      -- m from a character town's centre at least
M.HARBOUR_R = 350
M.RAIL_R = 400
M.CLEAR_R = 150           -- m: no street, track, construction or field this close to the site
M.LINK_SHORT = 150        -- m: the link line is tested to this far short of the site (the Works' own streets)
M.LINK_GRADE = 0.10
M.KIND_BONUS = { harbour = 1.0, rail = 0.7, across = 0.5, plain = 0, hill = 0 }
M.HILL_DZ = 25            -- m above the town centre: a plain site in the hills ("hill": pit / colliery / quarry names)

--- Is town t a Works parent? o = { fresh (the map was new when the mod first saw it), seed, buildings, has (one
--- already), isWorks (t is a Works town), character (a character town: its seclusion stays), quotaLeft }. Returns
--- true / false, why ("off" | "notNewMap" | "works" | "character" | "has" | "small" | "quota" | "rare" | "seeded").
function M.eligible(o)
	if not M.ON then return false, "off" end
	if not o.fresh then return false, "notNewMap" end
	if o.isWorks then return false, "works" end
	if o.character then return false, "character" end
	-- (a deep forest town founds none, 2026-10-14)
	if o.deep then return false, "deep" end
	if o.has then return false, "has" end
	if (o.buildings or 0) < M.MIN_BUILDINGS then return false, "small" end
	-- (2026-10-15, §64: rng.draw, not rng.unit: "works" was the "shape" / "metro" draw shifted, ot_rng M.draw)
	-- (§66: a town that leans industrial by deliveries draws more often, a residential one less; ot_rci CHANCE_MUL)
	if rng.draw(o.seed or 1, "works") >= M.CHANCE * (tonumber(o.chanceMul) or 1) then return false, "rare" end
	if o.quotaLeft == false then return false, "quota" end
	return true, "seeded"
end

--- The map quota for n towns.
function M.quota(n)
	return math.min(M.MAP_MAX, math.max(M.MAP_MIN, math.floor((n or 0) / M.MAP_PER)))
end

local function wetNear(s, x, y, r)
	if T.isWater(s, x, y) then return true end
	for k = 0, 7 do
		local a = k * math.pi / 4
		if T.isWater(s, x + math.cos(a) * r, y + math.sin(a) * r) then return true end
	end
	return false
end

local function meanSlope(s, x, y, r)
	local sum = 0
	for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		sum = sum + T.slope(s, x + d[1] * r * 0.6, y + d[2] * r * 0.6, 8)
	end
	return sum / 5
end

local function nearAny(list, x, y, r)
	for _, p in ipairs(list or {}) do
		local px, py = p.x or p[1], p.y or p[2]
		if px and G.dist(x, y, px, py) <= r then return true end
	end
	return false
end

-- Forest (2026-10-14, run 2026-10-14_0119_sqot: "we had a nice forest going and then a residential city spawned near it
-- and grew over it"): a new town's houses and streets come from the game's own growth, which ignores forest, so a site
-- whose growth radius FOREST_R holds more than FOREST_MAX forest cover (the parent's tree grid, ot_forest) is no site
-- (why "forest"); open land that touches the forest edge (FOREST_EDGE cover on the ring just beyond) is preferred.
M.FOREST_R = 450          -- m: the new town's expected growth radius
M.FOREST_RINGS = { 150, 300, 450 }
M.FOREST_MAX = 0.2        -- mean cover within FOREST_R at most
M.FOREST_EDGE = 0.35      -- mean cover on the ring FOREST_R + 150 m at least: a forest-edge site (score bonus)
M.FOREST_EDGE_BONUS = 0.15

--- Forest share around (x, y): cover = function(x, y) -> 0..1 or nil (unknown: outside the grid). Returns share (the
--- mean of the known samples within FOREST_R, nil when none is known), edge (true: forest just beyond), known samples.
function M.forestShare(cover, x, y)
	if cover == nil then return nil, false, 0 end
	local sum, n = 0, 0
	local c0 = cover(x, y)
	if c0 then sum, n = sum + c0, n + 1 end
	for _, r in ipairs(M.FOREST_RINGS) do
		for k = 0, 7 do
			local a = k * math.pi / 4
			local c = cover(x + math.cos(a) * r, y + math.sin(a) * r)
			if c then sum, n = sum + c, n + 1 end
		end
	end
	local esum, en = 0, 0
	local er = M.FOREST_R + 150
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local c = cover(x + math.cos(a) * er, y + math.sin(a) * er)
		if c then esum, en = esum + c, en + 1 end
	end
	local edge = en > 0 and esum / en >= M.FOREST_EDGE
	if n == 0 then return nil, edge, 0 end
	return sum / n, edge, n
end

-- Landscape (2026-10-15, §64; the §62 / §63 rules for the offshoot towns, which now stand in for the streets-only
-- satellites): a site whose surroundings are wooded scores worse (the new town's own streets fill with houses to lot
-- depth and the woods go: ot_skeleton.pointClear against POINT_R + CLEAR_M, like the satellite sites), so does a
-- wooded link (ot_forest.pen), and a heading the §62 lean favours (ot_land.at: open land, away from forest and steep
-- ground) scores better. o.forest = the parent's tree grid (nil: no forest terms), o.deep (a deep forest town: none),
-- o.land = the parent's lean field (style.land; nil: no lean).
M.WOOD_W = 1.2            -- score + this x how wooded the site's surroundings are (0..1) ...
M.LINK_WOOD_W = 0.5       -- ... + this x the link's mean cover ...
M.LEAN_W = 0.35           -- ... - this x the §62 lean at the site's heading (-1..1)

--- The landscape terms of a site: score delta (lower is better), info { wood, clear (m), lean }.
function M.landScore(o, x, y, a, link)
	local SK = ug_require "square_organic_towns::/organic_towns/ot_skeleton.lua"
	local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
	local LAND = ug_require "square_organic_towns::/organic_towns/ot_land.lua"
	local d, info = 0, { wood = 0, lean = 0 }
	if o.forest and o.forest.cover and not o.deep then
		local reach = SK.POINT_R + SK.CLEAR_M
		local clear = SK.pointClear(o.forest, x, y)
		info.clear = clear
		info.wood = 1 - math.min(1, clear / reach)
		d = d + M.WOOD_W * info.wood + M.LINK_WOOD_W * FO.pen({ grid = o.forest }, link)
	end
	if o.land and a then
		local okL, lean = pcall(LAND.at, o.land, a)
		if okL and type(lean) == "number" and lean == lean then
			info.lean = lean
			d = d - M.LEAN_W * math.max(-1, math.min(1, lean))
		end
	end
	return d, info
end

local function reject(o, why)
	if o.rejects then o.rejects[why] = (o.rejects[why] or 0) + 1 end
end

--- "forest:3/slope:2" from a rejects table (or "-").
function M.rejectText(r)
	if r == nil or next(r) == nil then return "-" end
	local keys = {}
	for k in pairs(r) do keys[#keys + 1] = k end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do out[#out + 1] = k .. ":" .. r[k] end
	return table.concat(out, "/")
end

-- One site test (both pickers, and ot_district's): ok, slope, dead end, link points, forest share. o.wetR /
-- o.neighbourMin override WET_R / NEIGHBOUR_MIN (districts sit by the shore and nearer their parent); o.rejects (a table)
-- counts the reasons a site failed; o.cover (function(x, y) -> cover or nil) the forest test.
local function siteOk(o, x, y, d, minD)
	local s = o.sampler
	local ok = d >= (minD or ((o.r or 0) + M.GAP_EXTENT))
	ok = ok and not MAP.nearEdge(o.bounds, x, y, MAP.MARGIN + M.CORE_R)
	ok = ok and not wetNear(s, x, y, o.wetR or M.WET_R)
	ok = ok and GP.held(o.gaps, { { x, y } }, "small") == nil
	ok = ok and (o.owner == nil or o.owner(x, y))
	if ok then
		for _, nb in ipairs(o.neighbours or {}) do
			local dn = G.dist(x, y, nb[1] or nb.x, nb[2] or nb.y)
			if dn < (o.neighbourMin or M.NEIGHBOUR_MIN) or dn < d * 1.15 then ok = false break end
		end
	end
	ok = ok and not nearAny(o.characters, x, y, M.CHAR_CORE_M)
	-- (the industry keep-clear zones, ot_industry: the new town's core never in one)
	ok = ok and not (o.zones and IND.inZone(o.zones, x, y, M.CORE_R * 0.5))
	local sl = ok and meanSlope(s, x, y, M.CORE_R * 0.5) or 1
	ok = ok and sl <= M.MAX_SLOPE
	-- room for the new town's own streets
	if ok and o.obstacles then
		local cr = M.CLEAR_R
		ok = SAT.clearOfObstacles(o.obstacles, { { x - cr, y }, { x + cr, y } })
			and SAT.clearOfObstacles(o.obstacles, { { x, y - cr }, { x, y + cr } })
	end
	if not ok then reject(o, "site"); return false, sl end
	local fs, edge = M.forestShare(o.cover, x, y)
	if fs and fs > M.FOREST_MAX then reject(o, "forest"); return false, sl end
	-- reachable: a dry, gentle link line from a joinable dead end to LINK_SHORT short of the site
	local near = {}
	for _, e in ipairs(o.deadEnds) do
		local dd = G.dist(x, y, e[1], e[2])
		if dd <= d + 50 then near[#near + 1] = { e = e, d = dd } end
	end
	table.sort(near, function(p, q)
		if p.d ~= q.d then return p.d < q.d end
		return p.e[3] < q.e[3]
	end)
	for i = 1, math.min(#near, 3) do
		local e = near[i].e
		local L = near[i].d
		if L > M.LINK_SHORT + 100 then
			local f = (L - M.LINK_SHORT) / L
			local ex, ey = e[1] + (x - e[1]) * f, e[2] + (y - e[2]) * f
			local pts = SAT.linkPts(e[1], e[2], ex, ey, o.seed)
			if not T.wetAlong(s, pts, 20, 40) and T.pathMaxGrade(s, pts, 40) <= M.LINK_GRADE
				and SAT.linkClear(o.g, pts, e[3]) then
				return true, sl, e, pts, fs, edge
			end
		end
	end
	reject(o, "link")
	return false, sl
end
M.siteOk = siteOk

--- The site, or nil, why. o = { cx, cy, r (the houses' extent), sampler, seed, neighbours = { {x, y} } (other town
--- centres), characters = { {x, y} } (character towns' centres), bounds, gaps (ot_gap), harbours = { {x, y} }, rails =
--- { {x, y} }, obstacles (ot_engine.obstacles), deadEnds = { {x, y, node} } (the town's joinable dead ends), g (its graph:
--- the link clear of its streets), owner = function(x, y) (the engine's closest town is this one) or nil, zones (an
--- ot_industry info: its keep-clear zones), industries = { {x, y, file} } (the map's: the industry site, M.industrySite) }.
--- Returns { x, y, d, heading, kind, deadEnd, link (pts), score[, industry, ind, at, nudge] }, candidates count.
--- (2026-10-14, user: "the industrial offshoots probably make the most sense if they get spawned closer to factories,
--- like 2/3 distance to a factory"): with an industry within IND_MAX the site is the industry site; a harbour / station
--- site of the ring only when it lies nearer the town.
function M.pickSite(o)
	local s = o.sampler
	if s == nil then return nil, "noSampler" end
	if o.deadEnds == nil or #o.deadEnds == 0 then return nil, "noDeadEnd" end
	o.rejects = o.rejects or {}
	o.cz = o.cz or s.height(o.cx, o.cy)
	local ind, nInd = nil, 0
	if o.industries and #o.industries > 0 then ind, nInd = M.industrySite(o) end
	local rot = rng.unit(o.seed or 1, "worksRot") * 2 * math.pi / M.DIRS
	local best, n = nil, 0
	for k = 0, M.DIRS - 1 do
		local a = rot + k * 2 * math.pi / M.DIRS
		for _, d in ipairs(M.RING_D) do
			local x, y = o.cx + math.cos(a) * d, o.cy + math.sin(a) * d
			local ok, sl, de, link, fs, edge = siteOk(o, x, y, d)
			if ok then
				n = n + 1
				local kind = "plain"
				if nearAny(o.harbours, x, y, M.HARBOUR_R) then kind = "harbour"
				elseif nearAny(o.rails, x, y, M.RAIL_R) then kind = "rail"
				else
					for f = 0.15, 0.85, 0.05 do
						if T.isWater(s, o.cx + (x - o.cx) * f, o.cy + (y - o.cy) * f) then kind = "across" break end
					end
				end
				-- (2026-10-14: a plain site well above the town: a pit / colliery / quarry name)
				if kind == "plain" and s.height(x, y) - (o.cz or s.height(o.cx, o.cy)) >= M.HILL_DZ then kind = "hill" end
				local land, li = M.landScore(o, x, y, a, link)
				local score = -(M.KIND_BONUS[kind] or 0) + 0.3 * d / 1500 + sl / M.MAX_SLOPE * 0.3
					+ 0.25 * rng.unit(o.seed or 1, "worksSite", k, d) - (edge and M.FOREST_EDGE_BONUS or 0) + land
				if best == nil or score < best.score then
					best = { x = x, y = y, d = d, heading = a, kind = kind, deadEnd = de, link = link, score = score, slope = sl,
						forest = fs, forestEdge = edge, wood = li.wood, clear = li.clear, lean = li.lean }
				end
			end
		end
	end
	if ind and not (best and (best.kind == "harbour" or best.kind == "rail") and best.d < ind.d) then
		return ind, n + nInd
	end
	if best == nil then return nil, (o.rejects and (o.rejects.forest or 0) > 0) and "forest" or "noSite" end
	return best, n + nInd
end

-- Works by a factory (2026-10-14): the site on the line from the town centre to an industry within IND_MAX, at about
-- IND_AT of the way (IND_FRACS tried), never inside the industry's keep-clear zone or IND_KEEP of it, nudged sideways
-- (IND_NUDGE) when blocked; the nearest industries first (IND_MAX_N). The Works is named by the industry's type.
M.IND_MAX = 3000          -- m from the town centre
M.IND_MIN = 500           -- m: an industry nearer than this is in the town (none of it)
M.IND_AT = 2 / 3
M.IND_FRACS = { 2 / 3, 0.6, 0.73, 0.55 }
M.IND_NUDGE = { 0, 120, -120, 240, -240, 360, -360 }
M.IND_KEEP = 250          -- m from the industry at least (beyond its zone)
M.IND_MAX_N = 6
M.IND_MIN_D = 500         -- m from the centre at least (and the houses' extent + IND_GAP)
M.IND_GAP = 200
M.IND_MAX_D = 2300

--- The industry site (see above) or nil, candidates count. Same o as pickSite (o.industries).
function M.industrySite(o)
	local SN = ug_require "square_organic_towns::/organic_towns/ot_stopname.lua"
	local list = {}
	for _, it in ipairs(o.industries or {}) do
		local ix, iy = it[1] or it.x, it[2] or it.y
		if ix and iy then
			local d = G.dist(o.cx, o.cy, ix, iy)
			if d >= M.IND_MIN and d <= M.IND_MAX then list[#list + 1] = { x = ix, y = iy, d = d, file = it.file } end
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		return a.x < b.x
	end)
	local n = 0
	local minD = math.max(M.IND_MIN_D, (o.r or 0) + M.IND_GAP)
	for i = 1, math.min(#list, M.IND_MAX_N) do
		local it = list[i]
		local ux, uy = (it.x - o.cx) / it.d, (it.y - o.cy) / it.d
		local zr = IND.zoneRadius(it.file, it.x, it.y, o.cx, o.cy) or 0
		local keep = math.max(M.IND_KEEP, zr + M.CORE_R * 0.5)
		local best = nil
		for _, f in ipairs(M.IND_FRACS) do
			for _, nudge in ipairs(M.IND_NUDGE) do
				local x = o.cx + ux * it.d * f - uy * nudge
				local y = o.cy + uy * it.d * f + ux * nudge
				local d = G.dist(o.cx, o.cy, x, y)
				if d <= M.IND_MAX_D and G.dist(x, y, it.x, it.y) >= keep then
					local ok, sl, de, link, fs, edge = siteOk(o, x, y, d, minD)
					if ok then
						n = n + 1
						local score = math.abs(f - M.IND_AT) * 2 + math.abs(nudge) / 600 + sl / M.MAX_SLOPE * 0.2
							- (edge and M.FOREST_EDGE_BONUS or 0)
						if best == nil or score < best.score then
							best = { x = x, y = y, d = d, heading = G.atan2(y - o.cy, x - o.cx), kind = SN.indKind(it.file),
								deadEnd = de, link = link, score = score, slope = sl, industry = it, forest = fs, forestEdge = edge,
								ind = SN.indKind(it.file), at = f, nudge = nudge, indDist = it.d }
						end
					end
				end
			end
		end
		if best then return best, n end
	end
	return nil, n
end

---------------------------------------------------------------------------
-- names (the name list's classifier, ot_names.classOf; "en" by default). Each kind's forms first, then the others.
-- (2026-10-14, run 2026-10-14_0119_sqot, user: "too many industrial satellites all called Works; avoid the same suffix
-- when possible"): more forms per kind, era-aware generic forms (LATE: estates and parks from 1950 / 1980), "hill" sites
-- (pits, collieries, quarries); a name takes the form of its kind used least on the map (M.formCount over the map's town
-- names: stateless, the same after a reload), and never a water word twice (M.hasWater: "Ellesmere Port-on-Sea").

M.NAMES = {
	en = { harbour = { "%s Docks", "%s Wharf", "%s Quay", "Port %s", "%s Harbour" },
		rail = { "%s Junction", "%s Sidings", "%s Yard", "%s Depot" },
		across = { "%s Works", "%s Bridge Works", "%s Wharf" },
		plain = { "%s Works", "%s Ironworks", "%s Foundry", "%s Mills", "%s Forge", "%s Brickworks", "%s Gasworks",
			"%s Yard", "%s Depot", "%s Tannery", "%s Sawmill" },
		hill = { "%s Pit", "%s Colliery", "%s Quarry" } },
	usa = { harbour = { "Port %s", "%s Harbor", "%s Landing", "%s Wharf" }, rail = { "%s Junction", "%s Yards", "%s Depot" },
		across = { "%s Mills", "%s Works", "%s Landing" },
		plain = { "%s Mills", "%s Works", "%s Furnace", "%s Foundry", "%s Ironworks", "%s Brickyard", "%s Tannery",
			"%s Lumber Mill", "%s Depot" },
		hill = { "%s Mines", "%s Diggings", "%s Quarry" } },
	de = { harbour = { "%s-Hafen", "Hafen %s", "%s-Werft", "%s-Kai" }, rail = { "%s-Bahnhof", "%s-Güterbahnhof", "%s-Rangierbahnhof" },
		across = { "%s-Werk", "%s-Hütte", "%s-Werft" },
		plain = { "%s-Werk", "%s-Hütte", "%s-Hammer", "%s-Ziegelei", "%s-Gaswerk", "%s-Giesserei", "%s-Mühle", "%s-Gerberei",
			"%s-Sägewerk" },
		hill = { "%s-Zeche", "%s-Grube", "%s-Steinbruch" } },
	nl = { harbour = { "%s-Haven", "Haven %s", "%s-Kade", "%s-Werf" }, rail = { "%s-Station", "%s-Emplacement" },
		across = { "%s-Werken", "%s-Werf" },
		plain = { "%s-Werken", "%s-Fabriek", "%s-Gieterij", "%s-Steenfabriek", "%s-Gasfabriek", "%s-Molen", "%s-Zagerij",
			"%s-Looierij" },
		hill = { "%s-Mijn", "%s-Groeve" } },
	fr = { harbour = { "Port-%s", "%s-Port", "%s-le-Quai", "%s-les-Docks" }, rail = { "%s-Gare", "%s-Triage" },
		across = { "%s-les-Forges", "%s-le-Quai" },
		plain = { "%s-les-Forges", "%s-l'Usine", "%s-la-Fonderie", "%s-les-Moulins", "%s-la-Briqueterie", "%s-la-Tannerie",
			"%s-la-Scierie", "%s-les-Ateliers" },
		hill = { "%s-les-Mines", "%s-les-Carrières" } },
	it = { harbour = { "Porto %s", "Marina di %s", "%s Darsena" }, rail = { "%s Scalo", "%s Smistamento" },
		across = { "%s Officine", "%s Darsena" },
		plain = { "%s Officine", "%s Industriale", "%s Fonderia", "%s Ferriere", "%s Mulini", "%s Fornace", "%s Conceria",
			"%s Segheria" },
		hill = { "%s Miniere", "%s Cave" } },
	es = { harbour = { "Puerto de %s", "El Puerto de %s", "Muelle de %s", "Astillero de %s" },
		rail = { "Estación de %s", "Cargadero de %s" }, across = { "Fábricas de %s", "Muelle de %s" },
		plain = { "Fábricas de %s", "Fundición de %s", "Ferrería de %s", "Molinos de %s", "Tejar de %s", "Curtidos de %s",
			"Aserradero de %s", "Talleres de %s" },
		hill = { "Minas de %s", "Canteras de %s" } },
	pt = { harbour = { "Porto de %s", "Cais de %s", "Estaleiro de %s" }, rail = { "Estação de %s", "Ramal de %s" },
		across = { "Fábrica de %s", "Cais de %s" },
		plain = { "Fábrica de %s", "Fundição de %s", "Moinhos de %s", "Olaria de %s", "Serração de %s", "Oficinas de %s",
			"Curtumes de %s" },
		hill = { "Minas de %s", "Pedreiras de %s" } },
	sv = { harbour = { "%s hamn", "%s kaj", "%s varv" }, rail = { "%s station", "%s bangård" }, across = { "%s bruk", "%s varv" },
		plain = { "%s bruk", "%s verk", "%s gjuteri", "%s kvarn", "%s tegelbruk", "%s såg", "%s garveri", "%s hytta" },
		hill = { "%s gruva", "%s stenbrott" } },
	nb = { harbour = { "%s havn", "%s kai", "%s verft" }, rail = { "%s stasjon", "%s godsterminal" }, across = { "%s verk", "%s verft" },
		plain = { "%s verk", "%s bruk", "%s støperi", "%s mølle", "%s teglverk", "%s sag", "%s garveri", "%s hytte" },
		hill = { "%s gruve", "%s steinbrudd" } },
	ja = { harbour = { "%s港", "%s埠頭", "%s造船" }, rail = { "%s駅前", "%s操車場" }, across = { "%s工業", "%s埠頭" },
		plain = { "%s工業", "新%s", "%s製鉄", "%s鋳物", "%s製粉", "%s煉瓦", "%s製材", "%s工場" },
		hill = { "%s鉱山", "%s石切" } },
	ja_r = { harbour = { "%s-kō", "%s-futō", "%s-zōsen" }, rail = { "%s-ekimae", "%s-sōshajō" }, across = { "%s-kōgyō", "%s-futō" },
		plain = { "%s-kōgyō", "Shin-%s", "%s-seitetsu", "%s-imono", "%s-seifun", "%s-renga", "%s-seizai", "%s-kōjō" },
		hill = { "%s-kōzan", "%s-ishikiri" } },
	ru = { harbour = { "Порт %s", "%s-Пристань", "%s-Верфь" }, rail = { "%s-Сортировочная", "%s-Товарная" },
		across = { "%s-Заводской", "%s-Пристань" },
		plain = { "%s-Заводской", "%s-Фабричный", "%s-Литейный", "%s-Кирпичный", "%s-Мельничный", "%s-Лесопильный" },
		hill = { "Рудник %s", "%s-Карьерный" } },
	ru_r = { harbour = { "Port %s", "%s-Pristan", "%s-Verf" }, rail = { "%s-Sortirovochnaya", "%s-Tovarnaya" },
		across = { "%s-Zavodskoy", "%s-Pristan" },
		plain = { "%s-Zavodskoy", "%s-Fabrichny", "%s-Liteyny", "%s-Kirpichny", "%s-Melnichny", "%s-Lesopilny" },
		hill = { "Rudnik %s", "%s-Karyerny" } },
}
-- later eras: generic forms put in front of "plain" from the year given
M.LATE = {
	en = { { 1950, "%s Trading Estate" }, { 1950, "%s Industrial Estate" }, { 1980, "%s Business Park" } },
	usa = { { 1950, "%s Industrial Park" }, { 1980, "%s Business Park" } },
	de = { { 1950, "%s-Industriegebiet" }, { 1950, "%s-Gewerbegebiet" }, { 1980, "%s-Gewerbepark" } },
	nl = { { 1950, "%s-Industrieterrein" }, { 1980, "%s-Bedrijvenpark" } },
	fr = { { 1950, "Zone industrielle de %s" }, { 1980, "Parc d'activités de %s" } },
	it = { { 1950, "%s Zona Industriale" }, { 1980, "%s Polo Industriale" } },
	es = { { 1950, "Polígono de %s" }, { 1980, "Parque Empresarial de %s" } },
	pt = { { 1950, "Zona Industrial de %s" }, { 1980, "Parque Empresarial de %s" } },
	sv = { { 1950, "%s industriområde" }, { 1980, "%s företagspark" } },
	nb = { { 1950, "%s industriområde" }, { 1980, "%s næringspark" } },
	ja = { { 1950, "%s工業団地" } },
	ja_r = { { 1950, "%s-kōgyōdanchi" } },
	ru = { { 1950, "Промзона %s" } },
	ru_r = { { 1950, "Promzona %s" } },
}
-- (2026-10-14) Works by an industry: named by its type (ot_stopname.indKind: works / quarry / mine / farm / mill / brewery /
-- timber); a kind a language lacks falls back to the site kinds
local IK = {
	en = { works = { "%s Works", "%s Foundry" }, quarry = { "%s Quarry", "%s Delph" }, mine = { "%s Colliery", "%s Pit" },
		mill = { "%s Mills" }, farm = { "%s Grange", "%s Mills" }, brewery = { "%s Maltings" }, timber = { "%s Sawmills" } },
	usa = { works = { "%s Works", "%s Furnace" }, quarry = { "%s Quarry" }, mine = { "%s Mines", "%s Diggings" },
		mill = { "%s Mills" }, farm = { "%s Farms", "%s Mills" }, brewery = { "%s Brewery" }, timber = { "%s Lumber" } },
	de = { works = { "%s-Werk", "%s-Hütte" }, quarry = { "%s-Steinbruch" }, mine = { "%s-Zeche", "%s-Grube" },
		mill = { "%s-Mühle" }, farm = { "%s-Gut" }, brewery = { "%s-Brauerei" }, timber = { "%s-Sägewerk" } },
	nl = { works = { "%s-Werken" }, quarry = { "%s-Groeve" }, mine = { "%s-Mijn" }, mill = { "%s-Molen" },
		farm = { "%s-Hoeve" }, brewery = { "%s-Brouwerij" }, timber = { "%s-Zagerij" } },
	fr = { works = { "%s-les-Forges" }, quarry = { "%s-les-Carrières" }, mine = { "%s-les-Mines" },
		mill = { "%s-les-Moulins" }, farm = { "%s-la-Ferme" }, brewery = { "%s-la-Brasserie" }, timber = { "%s-la-Scierie" } },
	it = { works = { "%s Officine" }, quarry = { "%s Cave" }, mine = { "%s Miniere" }, mill = { "%s Mulini" },
		farm = { "%s Cascina" }, brewery = { "%s Birrificio" }, timber = { "%s Segheria" } },
	es = { works = { "Fábricas de %s" }, quarry = { "Canteras de %s" }, mine = { "Minas de %s" }, mill = { "Molinos de %s" },
		farm = { "Granja de %s" }, brewery = { "Cervecería de %s" }, timber = { "Aserradero de %s" } },
	pt = { works = { "Fábrica de %s" }, quarry = { "Pedreiras de %s" }, mine = { "Minas de %s" }, mill = { "Moinhos de %s" },
		farm = { "Quinta de %s" }, brewery = { "Cervejaria de %s" }, timber = { "Serração de %s" } },
	sv = { works = { "%s bruk" }, quarry = { "%s stenbrott" }, mine = { "%s gruva" }, mill = { "%s kvarn" },
		farm = { "%s gård" }, brewery = { "%s bryggeri" }, timber = { "%s såg" } },
	nb = { works = { "%s verk" }, quarry = { "%s steinbrudd" }, mine = { "%s gruve" }, mill = { "%s mølle" },
		farm = { "%s gård" }, brewery = { "%s bryggeri" }, timber = { "%s sag" } },
	ja = { works = { "%s工業" }, quarry = { "%s石切" }, mine = { "%s鉱山" }, mill = { "%s製粉" }, farm = { "%s農場" },
		brewery = { "%s醸造" }, timber = { "%s製材" } },
	ja_r = { works = { "%s-kōgyō" }, quarry = { "%s-ishikiri" }, mine = { "%s-kōzan" }, mill = { "%s-seifun" },
		farm = { "%s-nōjō" }, brewery = { "%s-jōzō" }, timber = { "%s-seizai" } },
	ru = { works = { "%s-Заводской" }, quarry = { "%s-Карьерный" }, mine = { "Рудник %s" }, mill = { "%s-Мельничный" },
		farm = { "Совхоз %s" }, brewery = { "%s-Пивоваренный" }, timber = { "Лесозавод %s" } },
	ru_r = { works = { "%s-Zavodskoy" }, quarry = { "%s-Karyerny" }, mine = { "Rudnik %s" }, mill = { "%s-Melnichny" },
		farm = { "Sovkhoz %s" }, brewery = { "%s-Pivovarenny" }, timber = { "Lesozavod %s" } },
}
for cls, kinds in pairs(IK) do
	local L = M.NAMES[cls]
	if L then
		for kind, fmts in pairs(kinds) do
			local list = {}
			for _, f in ipairs(fmts) do list[#list + 1] = f end
			-- ("works": the industry type's forms first, then the plain ones)
			if kind == "works" then
				local seen = {}
				for _, f in ipairs(list) do seen[f] = true end
				for _, f in ipairs(L.plain or {}) do if not seen[f] then list[#list + 1] = f end end
			end
			L["ind_" .. kind] = list
		end
	end
end
M.IND_KINDS = { "works", "quarry", "mine", "mill", "farm", "brewery", "timber" }
M.KIND_ORDER = { "plain", "across", "hill", "rail", "harbour" }
M.MAX_NAME_LEN = 40

-- water words (lower case; ASCII tokens also by ending): a parent name with one gets no second (M.hasWater)
M.WATER = {}
for _, w in ipairs({ "port", "sea", "bay", "mouth", "haven", "quay", "sands", "sand", "mere", "water", "waterside", "lake",
	"beach", "shore", "shores", "strand", "harbour", "harbor", "marina", "lido", "cove", "pool", "see", "hafen", "meer",
	"bucht", "zee", "mer", "plage", "lac", "bains", "mare", "porto", "lago", "mar", "puerto", "playa", "praia", "cais",
	"hamn", "sjö", "sjöstad", "vik", "havn", "sjø", "more", "ozere", "ozero", "hama", "kohan", "kō", "kaigan",
	"море", "Море", "порт", "Порт", "озере", "Озере", "озеро", "Озеро" }) do M.WATER[w] = true end
M.WATER_END = { "mouth", "haven", "pool", "mere", "port", "sea", "bay", "water", "sands" }
M.WATER_CJK = { "浜", "海", "港", "湖", "浦", "津", "湾" }

--- Does a name (or a form's added words) hold a water word?
function M.hasWater(text)
	if type(text) ~= "string" then return false end
	for _, c in ipairs(M.WATER_CJK) do if text:find(c, 1, true) then return true end end
	for tok in text:gmatch("[^%s%-']+") do
		local l = tok:lower()
		if M.WATER[l] or M.WATER[tok] then return true end
		if #l >= 5 and not l:find("[\128-\255]") then
			for _, e in ipairs(M.WATER_END) do
				if l:sub(-#e) == e then return true end
			end
		end
	end
	return false
end

--- The form's added words ("%s-on-Sea" -> "-on-Sea").
function M.formWords(fmt)
	return (fmt:gsub("%%[sl]", " "))
end

--- How many of the names (a set { [name] = true } or a list) take the form fmt ("%s Works": any "<x> Works").
function M.formCount(fmt, names)
	local pre, post = fmt:match("^(.-)%%[sl](.*)$")
	if pre == nil or names == nil then return 0 end
	local n = 0
	local function test(nm)
		if type(nm) == "string" and #nm > #pre + #post and nm:sub(1, #pre) == pre and (post == "" or nm:sub(-#post) == post) then
			n = n + 1
		end
	end
	for k, v in pairs(names) do
		if type(k) == "string" then test(k) elseif type(v) == "string" then test(v) end
	end
	return n
end

--- The name from groups of forms (the kind's forms first, the fallbacks after): in the first group with a usable form,
--- the one used least on the map (ties: the first). fill(fmt, stem) -> name or nil; used = { [name] = true }; o =
--- { parent, maxLen }. Returns name, form.
function M.pickForm(groups, stem, used, fill, o)
	o = o or {}
	used = used or {}
	local wet = M.hasWater(o.parent or stem)
	for _, group in ipairs(groups) do
		local best, bc, bf = nil, nil, nil
		for _, f in ipairs(group) do
			local nm = fill(f, stem)
			if nm and #nm <= (o.maxLen or M.MAX_NAME_LEN) and not used[nm] and nm ~= o.parent
				and not (wet and M.hasWater(M.formWords(f))) and (o.ok == nil or o.ok(nm)) then
				local c = M.formCount(f, used)
				if bc == nil or c < bc then best, bc, bf = nm, c, f end
			end
		end
		if best then return best, bf end
	end
	return nil
end

local function fillS(fmt, t) return (fmt:gsub("%%s", function() return t end)) end

--- The Works town's name for parent name `parent`, site kind and classifier cls (nil: a list without classifier, no
--- composed name; an unknown one: en), unique against `used` ({ [name] = true }: the map's town names). Since
--- 2026-10-14 (NEXT_PHASE_BRIEF 47, user: "industrial satellites seem like they always say 'works'") through ot_offname:
--- the industry's own type, the site and the survey's cues, parent / company / cue / generic patterns, each suffix once
--- per map while others fit. o = { year, ok = function(name) (the map's word budget, ot_namewords), seed, file (the
--- industry's file), site = { sea, lake, river, valley, falls ..., dz } }. Returns name, info (ot_offname.works) or nil.
function M.name(cls, parent, kind, used, o)
	if type(parent) ~= "string" or parent == "" or cls == false then return nil end
	o = o or {}
	local OFF = ug_require "square_organic_towns::/organic_towns/ot_offname.lua"
	local c = cls
	if c == nil or OFF.worksOf(c) == nil then c = "en" end
	local site = {}
	for k, v in pairs(o.site or {}) do site[k] = v end
	site.kind, site.file, site.year = kind, o.file or site.file, o.year or site.year
	return OFF.works(c, parent, site, used or {}, { seed = o.seed, ok = o.ok, okGen = o.okGen, extra = o.extra })
end

---------------------------------------------------------------------------
-- the created town (2026-10-14 late, run 2026-10-14_0119_sqot: several parents claimed one new town, "the newest
-- town not in my list" mixed up concurrent creates). The driver keeps one creation in flight map-wide and claims a
-- town only by the name it gave and a position near its site.

M.IDENT_R = 600           -- m: the created town's centre within this of the site (when it can be read)

local function normName(n)
	return (tostring(n or ""):gsub("[%s_]", ""):lower())
end

--- The created town among cands = { {id, name, x, y} } (towns new since the creation was sent, unclaimed; x / y nil when
--- unreadable): the one named `name` (spaces / underscores ignored) within IDENT_R of the site (sx, sy) when its
--- position is known. Returns id, how ("name" | "name+pos") or nil, why ("none" | "far" | "ambiguous").
function M.identify(cands, name, sx, sy)
	local hits, far = {}, false
	local want = normName(name)
	for _, c in ipairs(cands or {}) do
		if c.name ~= nil and (c.name == name or normName(c.name) == want) then
			if c.x == nil or sx == nil then hits[#hits + 1] = { c = c, d = nil }
			else
				local d = G.dist(c.x, c.y, sx, sy)
				if d <= M.IDENT_R then hits[#hits + 1] = { c = c, d = d } else far = true end
			end
		end
	end
	if #hits == 1 then return hits[1].c.id, hits[1].d and "name+pos" or "name" end
	if #hits > 1 then
		-- (several of that name near the site: the nearest with a known position, when only one is that near)
		table.sort(hits, function(a, b) return (a.d or 1e9) < (b.d or 1e9) end)
		if hits[1].d and (hits[2].d == nil or hits[2].d - hits[1].d > 100) then return hits[1].c.id, "name+pos" end
		return nil, "ambiguous"
	end
	return nil, far and "far" or "none"
end

---------------------------------------------------------------------------
-- the link road

--- The link: from one of the parent's dead ends (deadEnds { {x, y, node} }) to one of the Works town's (worksEnds),
--- through ot_link (many pairs, detours, obstacles, zones). Returns the best { from, to, pts, len } or nil, why; the
--- whole list (best first) and the link info as third and fourth results.
function M.link(o)
	local list, why, info = LK.candidates({ sampler = o.sampler, seed = o.seed, from = o.deadEnds, to = o.worksEnds, g = o.g,
		obstacles = o.obstacles, zones = o.zones, maxGrade = M.LINK_GRADE })
	if #list == 0 then return nil, why, list, info end
	return list[1], nil, list, info
end

--- ot_plan streets of the link (key "works:link", lead = "lane": ot_lead.mark makes its middle the country lane).
function M.linkStreets(lk)
	return LK.streets(lk, "works")
end

return M
