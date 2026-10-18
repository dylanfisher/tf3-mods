-- Organic Towns: district towns, residential offshoots of a bigger town (pure; 2026-10-14, round after the 2355 run).
--
-- User (run 2026-10-13_2355_sqot): "I like the industrial offshoots like Haslemere Works. I wonder if we should push
-- offshoot towns more. Maybe that works better than trying to extend long arms that the game doesn't use to build on.
-- Or create a small offshoot residential and then fill in the game to main town. These could be like different
-- districts." So a grown town (MIN_BUILDINGS) founds 1-2 small towns of its own, made the proven Works way
-- (makeTownCreateCmd, ot_engine.createTown) but mostly residential (CAPS), on a site feature RING_D 0.6-1.5 km out:
--   upper     a hilltop or terrace UPPER_DZ m above the town centre ("Upper X")
--   shore     a sea or lake shore: water within SHORE_FAR m, none within SHORE_NEAR ("X-on-Sea" / "X Waterside")
--   across    across a river or lake arm from the centre (only when a dead end of the town is over there: the link
--             stays dry; the bridgehead quarter of a bridged town) ("X Bridge" / "Neu-X")
--   lead      the far end of the town's country lane ahead (ot_lead, LEAD_R) ("X End")
--   valley    a valley head: both sides VALLEY_DZ m higher, the site above the centre ("X Dale")
--   (clearing  a forest clearing: dropped 2026-10-14, run 2026-10-14_0119_sqot: Winchcombe Heath, founded in a clearing,
--             grew over the forest the user liked; a new town's houses and streets come from the game's own growth,
--             which ignores forest. Every site now needs open land within ot_works.FOREST_R (FOREST_MAX cover at most,
--             why "forest"), and open land at the forest edge scores better.)
-- A site with none of these is no district site. The rest of the site rules are the Works' (ot_works.siteOk: dry,
-- gentle, inside the map margin, nearer this town than any other, never by a character town's core, no gap line,
-- outside the industry keep-clear zones, room for its streets, a reachable link line), a second district at least
-- SECOND_APART m and SECOND_DEG from the first.
-- The name (M.name, through ot_offname since 2026-10-14, NEXT_PHASE_BRIEF 47): composed per list language from the
-- site, its water and the compass, each suffix once per map while others fit; never a real list name.
-- The driver links it to the parent by a road (ot_link), lowers the parent's arm reach (DISTRICT_KA: districts instead
-- of long arms), and waives the R3 gap between the two along the link (ot_gap waive), so the game fills in between.
-- Save-safe: the district is an ordinary town (removing the mod leaves it as it is); only ids are saved (ot_saved
-- `wk`, the parent frame's `dp`). New maps only. Every loop is bounded by RING_D x DIRS. Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local WK = ug_require "square_organic_towns::/organic_towns/ot_works.lua"

local M = {}

M.ON = true
M.MIN_BUILDINGS = 300     -- a town this big (buildings) may found one
M.SECOND_BUILDINGS = 700  -- ... a second one from this size, after the first is linked
M.MAX_PER_TOWN = 2
M.CHANCE = 0.6            -- seeded share of the eligible towns
M.MAP_PER = 4             -- map quota: one district per this many towns ...
M.MAP_MIN = 1
M.MAP_MAX = 6
M.CAPS = { 200, 30, 10 }  -- initial land use capacities (residential, commercial, industrial)
M.RING_D = { 600, 800, 1000, 1250, 1500 }
M.DIRS = 24
M.MIN_GAP = 150           -- m beyond the parent's houses' extent at least
M.NEIGHBOUR_MIN = 1000    -- m from any other town centre (the parent's Works and districts too)
M.UPPER_DZ = 18           -- m above the centre: a hilltop / terrace
M.SHORE_NEAR = 50         -- m: no water this near (the district's own room) ...
M.SHORE_FAR = 170         -- ... but water within this: a shore site
M.VALLEY_DZ = 12          -- m: both sides this much higher at VALLEY_SIDE m
M.VALLEY_SIDE = 250
M.LEAD_R = 350            -- m from the lane ahead's far end
M.SECOND_APART = 900      -- m between a town's two districts at least
M.SECOND_DEG = 60         -- deg between their headings from the centre at least
M.KINDS = { "upper", "shore", "across", "lead", "valley", "cross", "open" }
M.KIND_BONUS = { upper = 1.0, shore = 1.0, across = 0.9, lead = 0.85, valley = 0.8, cross = 0.75, open = 0.45 }
-- (2026-10-15, §64: the offshoot towns stand in for the streets-only satellite villages, so a district may also sit
-- by a country-road crossroads (o.junctions, the satellite's hamlet sites: "cross", named like the lane's end) or,
-- when no feature is there, on plain open land ("open": the lowest bonus; generic / size / compass names). OPEN =
-- false: features only, as before.)
M.OPEN = true
M.CROSS_R = 250           -- m from a country-road crossroads
M.SHORT_NAME = 14         -- parent names longer than this compose from their first word

--- Does town t found a district now? o = { fresh, seed, buildings, isOffshoot (t was made by the mod), character, count
--- (districts it has), linkedAll (every one of them linked or given up), quotaLeft }. Returns ok, why ("off" | "notNewMap" |
--- "offshoot" | "character" | "max" | "small" | "waitLink" | "quota" | "rare" | "seeded").
function M.eligible(o)
	if not M.ON then return false, "off" end
	if not o.fresh then return false, "notNewMap" end
	if o.isOffshoot then return false, "offshoot" end
	if o.character then return false, "character" end
	-- (a deep forest town founds none, 2026-10-14: it stays a secluded town in the woods)
	if o.deep then return false, "deep" end
	local c = o.count or 0
	if c >= M.MAX_PER_TOWN then return false, "max" end
	if (o.buildings or 0) < (c == 0 and M.MIN_BUILDINGS or M.SECOND_BUILDINGS) then return false, "small" end
	if c > 0 and not o.linkedAll then return false, "waitLink" end
	if o.quotaLeft == false then return false, "quota" end
	-- (2026-10-15, §64: rng.draw: "district" was the "leadLane" draw shifted, so every lane-ahead town was rare)
	-- (§66: a residential lean by deliveries draws more often, an industrial one less; ot_rci CHANCE_MUL)
	if c == 0 and rng.draw(o.seed or 1, "district") >= M.CHANCE * (tonumber(o.chanceMul) or 1) then return false, "rare" end
	return true, "seeded"
end

--- The map quota for n towns.
function M.quota(n)
	return math.min(M.MAP_MAX, math.max(M.MAP_MIN, math.floor((n or 0) / M.MAP_PER)))
end

local function wetAny(s, x, y, r)
	for k = 0, 7 do
		local a = k * math.pi / 4
		if T.isWater(s, x + math.cos(a) * r, y + math.sin(a) * r) then return true end
	end
	return false
end

--- The site features at (x, y), heading a and distance d from the centre: { [kind] = true }, count. o as pickSite
--- (cz = the centre's height).
function M.features(o, x, y, a, d)
	local s = o.sampler
	local out, n = {}, 0
	local function add(k) out[k] = true; n = n + 1 end
	local hz = s.height(x, y)
	local cz = o.cz or s.height(o.cx, o.cy)
	if hz - cz >= M.UPPER_DZ then add("upper") end
	if not wetAny(s, x, y, M.SHORE_NEAR) and (wetAny(s, x, y, M.SHORE_FAR) or wetAny(s, x, y, (M.SHORE_NEAR + M.SHORE_FAR) / 2)) then
		add("shore")
	end
	for f = 0.15, 0.85, 0.05 do
		if T.isWater(s, o.cx + (x - o.cx) * f, o.cy + (y - o.cy) * f) then add("across") break end
	end
	if o.lead and G.dist(x, y, o.lead[1], o.lead[2]) <= M.LEAD_R then add("lead") end
	local px, py = -math.sin(a), math.cos(a)
	local hl = s.height(x + px * M.VALLEY_SIDE, y + py * M.VALLEY_SIDE)
	local hr = s.height(x - px * M.VALLEY_SIDE, y - py * M.VALLEY_SIDE)
	if hl >= hz + M.VALLEY_DZ and hr >= hz + M.VALLEY_DZ and hz > cz + 2 then add("valley") end
	for i, j in ipairs(o.junctions or {}) do
		if i > 64 then break end
		local jx, jy = j.x or j[1], j.y or j[2]
		if jx and G.dist(x, y, jx, jy) <= M.CROSS_R then add("cross") break end
	end
	-- (no feature: plain open land, the lowest kind)
	if n == 0 and M.OPEN then add("open") end
	return out, n
end

--- The district site, or nil, why. o = ot_works.pickSite's o (cx, cy, r, sampler, seed, neighbours, characters, bounds,
--- gaps, obstacles, deadEnds, g, owner, zones) plus lead = {x, y} (the lane ahead's far end) or nil, cover =
--- function(x, y) -> forest cover 0..1 or nil (unknown; ot_works.siteOk's forest test), others = { {x, y} } (this
--- town's districts already founded), lake (the town's water is a lake), rejects (a table: the reasons sites failed).
--- Returns { x, y, d, heading, kind, kinds (text), deadEnd, link, score, forest, forestEdge }, candidates count; nil,
--- "forest" when the forest test turned sites down and none was left, else nil, "noSite".
function M.pickSite(o)
	local s = o.sampler
	if s == nil then return nil, "noSampler" end
	if o.deadEnds == nil or #o.deadEnds == 0 then return nil, "noDeadEnd" end
	local so = {}
	for k, v in pairs(o) do so[k] = v end
	so.wetR, so.neighbourMin = M.SHORE_NEAR, M.NEIGHBOUR_MIN
	so.rejects = o.rejects or {}
	o.rejects = so.rejects
	so.cz = s.height(o.cx, o.cy)
	local minD = (o.r or 0) + M.MIN_GAP
	local rot = rng.unit(o.seed or 1, "districtRot") * 2 * math.pi / M.DIRS
	local best, n = nil, 0
	for k = 0, M.DIRS - 1 do
		local a = rot + k * 2 * math.pi / M.DIRS
		local okDir = true
		for _, p in ipairs(o.others or {}) do
			local ha = G.atan2(p[2] - o.cy, p[1] - o.cx)
			if math.abs(G.angleDiff(ha, a)) < math.rad(M.SECOND_DEG) then okDir = false end
		end
		if okDir then
			for _, d in ipairs(M.RING_D) do
				local x, y = o.cx + math.cos(a) * d, o.cy + math.sin(a) * d
				local apart = true
				for _, p in ipairs(o.others or {}) do
					if G.dist(x, y, p[1], p[2]) < M.SECOND_APART then apart = false end
				end
				local feats, nf = nil, 0
				if apart and d >= minD then feats, nf = M.features(so, x, y, a, d) end
				if nf > 0 then
					local ok, sl, de, link, fs, edge = WK.siteOk(so, x, y, d, minD)
					if ok then
						n = n + 1
						local kind, kb = nil, -1
						for _, kk in ipairs(M.KINDS) do
							if feats[kk] and (M.KIND_BONUS[kk] or 0) > kb then kind, kb = kk, M.KIND_BONUS[kk] end
						end
						local list = {}
						for _, kk in ipairs(M.KINDS) do if feats[kk] then list[#list + 1] = kk end end
						-- (§64: the landscape terms, ot_works.landScore: open surroundings, an open link, the §62 lean)
						local land, li = WK.landScore(o, x, y, a, link)
						local score = -kb - 0.1 * (nf - 1) + 0.3 * d / 1500 + sl / WK.MAX_SLOPE * 0.3
							+ 0.25 * rng.unit(o.seed or 1, "districtSite", k, d) - (edge and WK.FOREST_EDGE_BONUS or 0) + land
						if best == nil or score < best.score then
							best = { x = x, y = y, d = d, heading = a, kind = kind, kinds = table.concat(list, "+"),
								deadEnd = de, link = link, score = score, slope = sl, forest = fs, forestEdge = edge,
								wood = li.wood, clear = li.clear, lean = li.lean }
						end
					end
				end
			end
		end
	end
	if best == nil then return nil, (so.rejects.forest or 0) > 0 and "forest" or "noSite" end
	return best, n
end

---------------------------------------------------------------------------
-- names ("%s" = the parent's name; "%l" = the parent's name with its first letter in lower case, ASCII only)

M.NAMES = {
	en = { upper = { "Upper %s", "%s Heights", "High %s", "%s Hill", "%s Rise" },
		shore = { "%s-on-Sea", "%s Sands", "%s Bay", "%s Strand", "%s Shore" },
		shoreLake = { "%s Waterside", "%s-on-the-Water", "%s Lakeside" }, across = { "%s Bridge", "Over %s", "Far %s", "%s Ferry" },
		lead = { "%s End", "%s Green", "%s Cross" }, valley = { "%s Dale", "%s Head", "%s Bottom", "%s Vale" },
		clearing = { "%s Wood", "%s Heath", "%s Green" } },
	usa = { upper = { "%s Heights", "Upper %s", "%s Hills" }, shore = { "%s Beach", "%s Shores", "%s Point" },
		shoreLake = { "%s Shores", "Lake %s", "%s Lakeside" },
		across = { "West %s", "East %s", "%s Crossing" }, lead = { "%s Corners", "%s Center", "%s Crossroads" },
		valley = { "%s Hollow", "%s Glen", "%s Valley" }, clearing = { "%s Woods", "%s Park" } },
	de = { upper = { "Ober%l", "%s-Oberstadt", "%s-Höhe", "%s-Berg" }, shore = { "%s-Strand", "%s an der See", "%s-Bad" },
		shoreLake = { "%s am See", "%s-Seebad" }, across = { "Neu-%s", "%s-Brückenkopf", "%s-Überfahrt" },
		lead = { "%s-Siedlung", "%s-Ausbau", "%s-Feld" }, valley = { "%s-Tal", "%s im Grund", "%s-Grund" }, clearing = { "%s-Waldsiedlung", "%s-Rodung" } },
	nl = { upper = { "Hoog-%s", "Boven-%s" }, shore = { "%s aan Zee", "%s-Strand" }, shoreLake = { "%s aan het Meer" },
		across = { "Over-%s", "Nieuw-%s" }, lead = { "%s-Buiten" }, valley = { "%s-Dal" }, clearing = { "%s-Bos" } },
	fr = { upper = { "%s-le-Haut", "Haut-%s", "%s-les-Hauts" }, shore = { "%s-sur-Mer", "%s-Plage", "%s-la-Côte" },
		shoreLake = { "%s-les-Bains", "%s-sur-Lac" },
		across = { "Pont-de-%s", "%s-Outre" }, lead = { "%s-le-Hameau" }, valley = { "Val-de-%s", "%s-le-Val" },
		clearing = { "%s-les-Bois", "%s-la-Clairière" } },
	it = { upper = { "%s Alta", "%s Superiore" }, shore = { "Marina di %s", "Lido di %s" }, shoreLake = { "%s Lago" },
		across = { "Ponte di %s", "Oltre %s" }, lead = { "Borgo %s" }, valley = { "Val di %s" }, clearing = { "%s Bosco" } },
	es = { upper = { "%s de Arriba", "Alto de %s" }, shore = { "Playa de %s", "%s del Mar" }, shoreLake = { "%s del Lago" },
		across = { "Puente de %s" }, lead = { "Barrio de %s" }, valley = { "Valle de %s" }, clearing = { "%s del Monte" } },
	pt = { upper = { "%s de Cima", "Alto de %s" }, shore = { "Praia de %s", "%s do Mar" }, shoreLake = { "%s do Lago" },
		across = { "Ponte de %s" }, lead = { "Bairro de %s" }, valley = { "Vale de %s" }, clearing = { "%s do Mato" } },
	sv = { upper = { "Övre %s" }, shore = { "%s strand" }, shoreLake = { "%s sjöstad" }, across = { "Nya %s" },
		lead = { "%s by" }, valley = { "%s dal" }, clearing = { "%s skog" } },
	nb = { upper = { "Øvre %s" }, shore = { "%s strand" }, shoreLake = { "%s sjø" }, across = { "Nye %s" },
		lead = { "%s grend" }, valley = { "%s dal" }, clearing = { "%s skog" } },
	ja = { upper = { "上%s", "%s台" }, shore = { "%s浜", "%s海岸" }, shoreLake = { "%s湖畔" }, across = { "新%s", "%s橋" },
		lead = { "%s新田" }, valley = { "%s谷" }, clearing = { "%s林" } },
	ja_r = { upper = { "Kami-%s", "%s-dai" }, shore = { "%s-hama" }, shoreLake = { "%s-kohan" }, across = { "Shin-%s" },
		lead = { "%s-shinden" }, valley = { "%s-dani" }, clearing = { "%s-bayashi" } },
	ru = { upper = { "%s-Нагорный" }, shore = { "%s-на-Море" }, shoreLake = { "%s-на-Озере" }, across = { "%s-Заречный" },
		lead = { "Выселки %s" }, valley = { "%s-Дол" }, clearing = { "%s-Лесной" } },
	ru_r = { upper = { "%s-Nagorny" }, shore = { "%s-na-More" }, shoreLake = { "%s-na-Ozere" }, across = { "%s-Zarechny" },
		lead = { "Vyselki %s" }, valley = { "%s-Dol" }, clearing = { "%s-Lesnoy" } },
}
M.MAX_NAME_LEN = 32

--- The part of a parent name a district name is made from: the name (<= SHORT_NAME bytes), else its first word (3+
--- bytes, "Henley-in-Arden" -> "Henley"), else nil.
function M.stem(parent)
	if type(parent) ~= "string" or parent == "" then return nil end
	if #parent <= M.SHORT_NAME then return parent end
	local w = parent:match("^([^%s%-]+)")
	if w and #w >= 3 and #w <= M.SHORT_NAME then return w end
	return nil
end

local function fill(fmt, t)
	if fmt:find("%l", 1, true) then
		local c = t:sub(1, 1)
		if not c:match("%u") then return nil end
		return (fmt:gsub("%%l", function() return c:lower() .. t:sub(2) end))
	end
	return (fmt:gsub("%%s", function() return t end))
end

--- The district's name: cls = the list's classifier (nil: a list without classifier, no composed name; an unknown one:
--- en), parent = its name, kind (the site kind), used = { [name] = true } (the map's town names), o = { seed, lake (the
--- parent's water is a lake: a shore site there is a lake shore), ok = function(name) (the map's word budget, ot_namewords), site = { sea, sandy, rocky,
--- lake, river, dz, dir, forestEdge, falls, confluence, mouth, year } (ot_offname) }. Since 2026-10-14 (NEXT_PHASE_BRIEF
--- 47) through ot_offname.district: water words only where the site's water says so, the compass, Upper / Lower,
--- generics; each suffix once per map while others fit. Returns name, src ("composed"),
--- info (ot_offname) or nil.
function M.name(cls, parent, kind, used, o)
	o = o or {}
	used = used or {}
	if type(parent) ~= "string" or parent == "" or cls == false then return nil end
	local OFF = ug_require "square_organic_towns::/organic_towns/ot_offname.lua"
	local c = cls
	if c == nil or OFF.districtOf(c) == nil then c = "en" end
	local site = {}
	for k, v in pairs(o.site or {}) do site[k] = v end
	site.kind = kind
	-- (no site read: a shore by the parent's lake is a lake shore; any other shore is no proof of a sea beach)
	if kind == "shore" and o.site == nil and o.lake then site.lake = true end
	local nm, info = OFF.district(c, parent, site, used, { seed = o.seed, ok = o.ok, okGen = o.okGen, extra = o.extra })
	if nm == nil then return nil end
	return nm, (info and info.pattern == "generated") and "generated" or "composed", info
end

--- An unclaimed town named like a district or Works of another town (the load check's orphan line, 2026-10-14 late):
--- name = the town's name, names = { [id] = name } (the map's towns), cls = the list's classifier. Returns the other
--- town's name, the form ("%s Heath"), the kind ("district" | "works") and the other town's id, or nil.
function M.orphanOf(name, names, cls)
	if type(name) ~= "string" then return nil end
	local stems, ids = {}, {}
	for id, nm in pairs(names or {}) do
		if type(nm) == "string" and nm ~= name then
			local st = M.stem(nm)
			if st then stems[st] = nm; ids[st] = id end
		end
	end
	local function try(f)
		local pre, post = f:match("^(.-)%%[sl](.*)$")
		if pre == nil or #name <= #pre + #post then return nil end
		if name:sub(1, #pre) ~= pre or (post ~= "" and name:sub(-#post) ~= post) then return nil end
		local mid = name:sub(#pre + 1, #name - #post)
		if f:find("%l", 1, true) then mid = mid:sub(1, 1):upper() .. mid:sub(2) end
		return stems[mid], ids[mid]
	end
	local OFF = ug_require "square_organic_towns::/organic_towns/ot_offname.lua"
	local lists = { { M.NAMES[cls or ""] or M.NAMES.en, "district" }, { WK.NAMES[cls or ""] or WK.NAMES.en, "works" },
		{ { off = OFF.parentForms(OFF.districtOf(cls) and cls or "en", "district") }, "district" },
		{ { off = OFF.parentForms(OFF.worksOf(cls) and cls or "en", "works") }, "works" } }
	for _, LK in ipairs(lists) do
		local keys = {}
		for k in pairs(LK[1]) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do
			for _, f in ipairs(LK[1][k]) do
				local p, id = try(f)
				if p then return p, f, LK[2], id end
			end
		end
	end
	for _, e in ipairs(WK.LATE[cls or ""] or {}) do
		local p, id = try(e[2])
		if p then return p, e[2], "works", id end
	end
	return nil
end

return M
