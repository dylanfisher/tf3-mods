-- Organic Towns: strong town characters (pure; 2026-10-14, CHARACTERS_BRIEF.md, NEXT_PHASE_BRIEF 54).
--
-- User: "identifying more characters with strong preference, like deep forest. these should spawn less often, maybe 1
-- or 2 on a map depending on how many cities, and should be very distinct and really push the parameters"; "one
-- character could push roundabouts more"; "some sprawling towns are good, but some others should get dense at some
-- point" (the densify trait, NEXT_PHASE_BRIEF 52 item 2).
--
-- The registry (like ot_motif): CH.register(kind) with
--   id          string [a-z_]; saved frames store its index in CH.IDS (`ck`, append only) and the map record `cm`
--   selectable  false: the kind has its own per-town pick (deep_forest: ot_forest deepPick, frame `fd`, its own quota of
--               3 per map, unchanged); true: picked once per map by CH.select
--   eligible    fn(site) -> score 0..1, why. site = CH.site(...) (terrain stats, wide survey, ot_site features, the
--               character probe, industries, the era, the region)
--   style       fn(site or inputs) -> a style id (ot_style) the kind plans with, or nil (the town's own)
--   form        the town form the kind forces (an ot_form def with id; no `block` below 1 there: the kinds scale their
--               blocks in `apply`, never below MIN_BLOCK); nil: the town's own
--   apply       fn(p, ctx) (optional): planner knobs pushed on the resolved style before the shape / form (blocks,
--               curves, spokes, rings, templates, slopes; never below ot_style.MIN_BLOCK, never sharper than the
--               planner's own radius checks: the geometry safety limits stay the planner's)
--   post        fn(p, ctx) (optional): after the form and the waterfront (premiums, ring settings)
--   motifs      { prefer = { ids }, forbid = { ids } } (ot_motif.pick: preferred kinds weigh CH.MOTIF_PREFER x and fill
--               the first slot when eligible; forbidden ones are never drawn)
--   offshoots   false: no district / Works town (the town stays one place)
--   levels      "early" (level weights from a young age: ot_upward EARLY_MAT / EARLY_K) | "off" (none) | nil (as any town)
--   names       { tag = site tag for the name generator, words = { cue words / affixes } } (the naming hook: CH.nameCue)
--   stats       fn(style) -> short text for PLAN `char=` (optional)
--
-- Selection (CH.select, once per map; the driver's "chars" phase after the map's towns' terrain is read):
--   quota CH.quota(n): 1 per ~QUOTA_PER towns (rounded), at least 1 and at most QUOTA_MAX, 2 only from TWO_FROM towns;
--   never two towns of one kind, never a metropolis-sized town, never within NEIGHBOUR_M of another pick, never a town
--   framed as a secluded character town (ot_map.characters) or created by the mod (Works / districts); the highest
--   eligibility wins (a seeded jitter breaks ties; a kind few towns of the map qualify for gets up to RARE_W more);
--   saved picks (`fixed`) stay first and count in the quota.
--
-- Secluded "character" towns (ot_map / ot_form CHARACTER, 2026-10-13) stay a separate mechanism: an extreme FORM for the
-- map's most remote towns, not a kind with its own site test. The two never stack: the strong kinds are picked first
-- (remote towns often sit on the most striking sites), a picked town is never a secluded one, and the secluded quota
-- passes to the next most remote town (the driver's characterOf); a town framed as secluded keeps its form and gets no
-- kind. Deep forest keeps its own pick too (a strong-kind town is never deep: the driver's deepFor says why=character).
--
-- Densify (CH.densifyDraw): a non-exclusive trait, decided once per town when it first reads mature (saved `dz` on the
-- frame: 1 densify, 2 decided no), about a third of the towns, seeded, weighted by size, centrality, rail and form;
-- never a strong-kind / deep / secluded / coastal-hug / created town, few linear ones.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"

local CH = {}

CH.ON = true
-- save indices (frame `ck`, map record `cm`): append only
CH.IDS = { "deep_forest", "hilltop", "clifftop", "harbour_cove", "waterfront", "street_village", "company_town",
	"garden_city", "island_town", "roundabout_town" }
CH.INDEX = {}
for i, id in ipairs(CH.IDS) do CH.INDEX[id] = i end
CH.KINDS = {}
CH.BY_ID = {}

CH.MIN_SCORE = 0.4        -- a kind needs this eligibility to be picked
CH.QUOTA_PER = 8          -- one strong character per this many towns ...
CH.QUOTA_MAX = 3          -- ... at most this many ...
CH.TWO_FROM = 10          -- ... two only from this many towns
CH.NEIGHBOUR_M = 3000     -- m: no two picks closer than this
CH.JITTER = 0.03          -- seeded tie-break added to the score
CH.RARE_W = 0.3           -- a kind few of the map's towns qualify for: its score x up to 1 + RARE_W (the share that don't)
CH.TOWNS_MAX = 400        -- towns scored at most (cap)
CH.MOTIF_PREFER = 4       -- ot_motif.pick: a preferred kind's weight x this
CH.METRO_CAP = 6000       -- persons: a town this big at the start is a metropolis-to-be: never a kind
-- a kind's pick weight (x its score in the ranking; 2026-10-14 seed-a runs: once the coast kinds scored on a real map,
-- the roundabout town (the user: "one character could push roundabouts more") lost its slot to them)
CH.KIND_W = { roundabout_town = 1.5 }

-- the probe (CH.probe): rings around the town, PROBE_DIRS directions each
CH.PROBE_R = { 300, 600, 1000, 1500 }
CH.PROBE_DIRS = 16
CH.FLAT_DH = 8            -- m: a ring point within this of the centre's height is flat
CH.AXIS_REACH = 1200      -- m: the valley floor sampled along the valley axis this far each way
CH.AXIS_STEP = 200
CH.ACROSS_M = 400         -- m: the valley sides sampled this far across

local function clamp(v, a, b) return G.clamp(v, a, b) end

---------------------------------------------------------------------------
-- registry

--- Registers (or replaces) a kind; an unknown id is appended to CH.IDS.
function CH.register(kind)
	assert(type(kind) == "table" and type(kind.id) == "string" and kind.id:match("^[a-z_]+$"), "character kind id")
	assert(type(kind.eligible) == "function", "character kind eligible()")
	if CH.INDEX[kind.id] == nil then
		CH.IDS[#CH.IDS + 1] = kind.id
		CH.INDEX[kind.id] = #CH.IDS
	end
	if CH.BY_ID[kind.id] == nil then CH.KINDS[#CH.KINDS + 1] = kind
	else
		for i, k in ipairs(CH.KINDS) do if k.id == kind.id then CH.KINDS[i] = kind end end
	end
	CH.BY_ID[kind.id] = kind
	return kind
end

--- The kind of a saved index (nil for an unknown one).
function CH.byIndex(i)
	local id = CH.IDS[tonumber(i) or 0]
	return id and CH.BY_ID[id] or nil, id
end

local function safeEligible(kind, site)
	local ok, s, why = pcall(kind.eligible, site)
	if not ok then return 0, "error:" .. tostring(s) end
	s = tonumber(s) or 0
	if s ~= s then s = 0 end
	return clamp(s, 0, 1), why or "-"
end

---------------------------------------------------------------------------
-- the probe: heights and water on rings around the town (cheap: 64 samples + the valley axis' 40)

--- s = an ot_terrain sampler. axis (rad, optional): the valley axis to sample along / across. Returns { h0, rings =
--- { [k] = { r, h = { [dir] = height or false (water) }, wet = share, arcs = wet arcs, mean = mean dry height, flat =
--- share of dry points within FLAT_DH of h0 } }, flat = share over every ring, floor (along the axis: share of points
--- within 20 m of h0), sides (across: the lower of the two sides' mean rise, m) }.
function CH.probe(s, cx, cy, axis)
	local out = { h0 = T.height(s, cx, cy), rings = {} }
	local nFlat, nAll = 0, 0
	for k, r in ipairs(CH.PROBE_R) do
		local ring = { r = r, h = {}, wet = 0, arcs = 0, mean = 0, flat = 0 }
		local dry, sum, flat, wet = 0, 0, 0, 0
		local prev, first = nil, nil
		for d = 1, CH.PROBE_DIRS do
			local a = (d - 1) / CH.PROBE_DIRS * 2 * math.pi
			local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
			local isW = T.isWater(s, x, y) == true
			if isW then
				wet = wet + 1
				ring.h[d] = false
			else
				local h = T.height(s, x, y)
				ring.h[d] = h
				dry, sum = dry + 1, sum + h
				if math.abs(h - out.h0) <= CH.FLAT_DH then flat = flat + 1 end
			end
			if prev ~= nil and isW and not prev then ring.arcs = ring.arcs + 1 end
			if first == nil then first = isW end
			prev = isW
		end
		if prev ~= nil and first and not prev then ring.arcs = ring.arcs + 1 end
		if wet == CH.PROBE_DIRS then ring.arcs = 1 end
		ring.wet = wet / CH.PROBE_DIRS
		ring.mean = dry > 0 and sum / dry or out.h0
		ring.flat = dry > 0 and flat / CH.PROBE_DIRS or 0
		nFlat, nAll = nFlat + flat, nAll + CH.PROBE_DIRS
		out.rings[k] = ring
	end
	out.flat = nAll > 0 and nFlat / nAll or 0
	if axis ~= nil then
		local ca, sa = math.cos(axis), math.sin(axis)
		local floor, n = 0, 0
		for d = -CH.AXIS_REACH, CH.AXIS_REACH, CH.AXIS_STEP do
			if d ~= 0 then
				local x, y = cx + ca * d, cy + sa * d
				n = n + 1
				if not T.isWater(s, x, y) and math.abs(T.height(s, x, y) - out.h0) <= 20 then floor = floor + 1 end
			end
		end
		out.floor = n > 0 and floor / n or 0
		local rise = {}
		for _, sg in ipairs({ 1, -1 }) do
			local sumR, c = 0, 0
			for _, f in ipairs({ 0.5, 1 }) do
				for _, along in ipairs({ -400, 0, 400 }) do
					local x = cx + ca * along - sa * sg * CH.ACROSS_M * f
					local y = cy + sa * along + ca * sg * CH.ACROSS_M * f
					if not T.isWater(s, x, y) then sumR, c = sumR + (T.height(s, x, y) - out.h0), c + 1 end
				end
			end
			rise[#rise + 1] = c > 0 and sumR / c or 0
		end
		out.sides = math.min(rise[1], rise[2])
	end
	return out
end

--- Probe ring k's dry heights below z - drop: count of directions.
local function lowDirs(ring, z, drop)
	local n = 0
	for d = 1, CH.PROBE_DIRS do
		local h = ring and ring.h[d]
		if h == false or (h and h <= z - drop) then n = n + 1 end
	end
	return n
end
CH.lowDirs = lowDirs

---------------------------------------------------------------------------
-- the site of a town

--- A site record from what the driver reads. o = { id, x, y, stats (ot_terrain.stats), wide (ot_terrain.wide), feats
--- (ot_site.features), probe (CH.probe), year, era, region, country, climate, cap (persons), newTemplates, industry =
--- { d, kind = "heavy"|"medium"|"light", x, y } (the nearest heavy / medium industry within reach) or nil, rbOk (the
--- one-way ring geometry is available: ot_roundabout), nnd (m to the nearest town), forest (forest share or nil) }.
function CH.site(o)
	o = o or {}
	o.stats = o.stats or {}
	o.wide = o.wide or {}
	o.feats = o.feats or {}
	return o
end

local function eraRamp(year, from, full)
	local y = tonumber(year) or 1960
	if y < from then return 0 end
	if y >= full then return 1 end
	return 0.5 + 0.5 * (y - from) / math.max(1, full - from)
end

-- region groups for the kinds' style choice
local US = { US = true, OCEANIA = true }
local EASTASIA = { JP = true, EAST_ASIA = true }

---------------------------------------------------------------------------
-- the kinds

-- (= ot_style.MIN_BLOCK, 44 m: a 16 m street + a row of 3-cell lots; ot_style requires this module, so a copy)
CH.MIN_BLOCK = 44

local function blockScale(p, kl, kd)
	if p.block == nil then return end
	local b = p.block
	b.len = math.max(math.min(b.len, CH.MIN_BLOCK), b.len * (kl or 1))
	b.depth = math.max(math.min(b.depth, CH.MIN_BLOCK), b.depth * (kd or kl or 1))
end
CH.blockScale = blockScale

-- deep forest: its own pick and geometry (ot_forest deepPick / deepStyle, frame `fd`); listed so the index, the logs
-- and the naming hook know it
CH.register({ id = "deep_forest", selectable = false,
	eligible = function() return 0, "ownPick" end,
	offshoots = false, levels = "off",
	names = { tag = "forest", words = { "Wood", "Holt", "Hurst", "-in-the-Forest", "Forest" } } })

-- hilltop (perched borgo): an isolated hill, the summit 25 m and more above the land around it
CH.HILL_RISE = 20          -- m (25 until the 2026-10-14 seed-a run): the summit over the 1000 / 1500 m rings' mean at least this ...
CH.HILL_DIRS = 10          -- ... and lower by HILL_DROP in at least this many of the 16 directions on the 1000 m ring
CH.HILL_DROP = 15
CH.HILL_SUMMIT_D = 380     -- m: the summit (the 600 m disc's highest point) at most this far from the town centre
CH.register({ id = "hilltop", selectable = true,
	eligible = function(site)
		local st, pr = site.stats, site.probe
		if pr == nil or st.high == nil then return 0, "noProbe" end
		local z = st.high[3]
		local sd = G.dist(site.x or 0, site.y or 0, st.high[1], st.high[2])
		if sd > CH.HILL_SUMMIT_D then return 0, string.format("summitFar:%.0f", sd) end
		local r3, r4 = pr.rings[3], pr.rings[4]
		if r3 == nil or r4 == nil then return 0, "noRings" end
		if r3.wet > 0.4 then return 0, "water" end
		local rise = z - (r3.mean + r4.mean) / 2
		local low = lowDirs(r3, z, CH.HILL_DROP)
		local why = string.format("rise=%.0f,low=%d", rise, low)
		if rise < CH.HILL_RISE then return 0, "low:" .. why end
		if low < CH.HILL_DIRS then return 0, "notIsolated:" .. why end
		return clamp(0.45 + (rise - CH.HILL_RISE) / 60, 0, 1) * clamp(0.6 + 0.4 * (low - CH.HILL_DIRS) / 4, 0, 1), why
	end,
	style = function() return "MED_HILL" end,
	form = { id = "clustered", def = { shape = "compact", front = 0.35, sector = 0.2, greens = 0, hotspots = 0, pull = 0 } },
	apply = function(p, ctx)
		blockScale(p, 0.85, 0.9)
		p.curve = math.max(p.curve or 0, 35)
		p.jitter = math.max(p.jitter or 0, 22)
		p.contour = 1.0
		p.gridness = math.min(p.gridness or 0.5, 0.1)
		-- (steep lanes: the planner's grade limit up from 0.10; the street checks keep their own limits)
		p.maxSlope = math.max(p.maxSlope or 0.1, 0.14)
		-- (rings 118 m apart, 110 until 2026-10-18: the narrowest wobbled ring gap, 0.75 x ringEvery, still holds two
		-- 44 m minimum blocks and the lane between them; at 110 those cells lost their lane and the town stalled)
		if p.radial then p.radial = { spokes = 5, ringEvery = 118 } end
		p.templates = { main = "small", medium = "small", small = "xsmall" }
		p.outer, p._outerCache = nil, nil
		if p.irregular then p.irregular.ribbon, p.irregular.hotspots, p.irregular.sector = 0.5, 0, 0.1 end
		p.housedLead = 1
		-- (the summit is the plan centre, a fresh plan only)
		local hi = ctx and ctx.terrain and ctx.terrain.high
		local c = ctx and ctx.pos
		if hi and c and not ctx.framed and G.dist(c[1], c[2], hi[1], hi[2]) <= CH.HILL_SUMMIT_D then
			p.charCentre = { hi[1], hi[2] }
		end
	end,
	motifs = { prefer = { "hill_climb", "switchbacks" }, forbid = { "ring_road", "culdesac_pods", "workers_terraces" } },
	offshoots = false, levels = "early",
	names = { tag = "hill", words = { "-on-the-Hill", "Mount", "Hill", "Castle", "Crest" } } })

-- clifftop / headland: a cliff over the sea or a lake
CH.CLIFF_H = 18            -- m above the water at least
CH.CLIFF_D = 420           -- m from the town at most
CH.register({ id = "clifftop", selectable = true,
	eligible = function(site)
		local c, f = site.stats.cliff, site.feats
		if c == nil then return 0, "noCliff" end
		if f.body ~= "sea" and f.body ~= "lake" then return 0, "body:" .. tostring(f.body) end
		local why = string.format("h=%.0f,d=%.0f", c.h or 0, c.d or 0)
		if (c.h or 0) < CH.CLIFF_H then return 0, "low:" .. why end
		if (c.d or math.huge) > CH.CLIFF_D then return 0, "far:" .. why end
		return clamp(0.5 + ((c.h or 0) - CH.CLIFF_H) / 40, 0, 1) * clamp(1.2 - (c.d or 0) / 600, 0, 1), why
	end,
	style = function(site)
		local r = site.region
		if US[r or ""] then return "NA_SUBURB" end
		if EASTASIA[r or ""] then return "JP_DENSE" end
		return "EU_ORGANIC"
	end,
	form = { id = "shore", def = { shape = "shore", reach = 1, front = 0.6, shore = true, kaMul = 1.8, kbMul = 0.6,
		depthCap = { 100, 160 }, charShore = true } },
	apply = function(p)
		-- terraces stepping back: shallow blocks; nothing down the cliff: a low grade limit
		blockScale(p, 1, 0.75)
		p.maxSlope = math.min(p.maxSlope or 0.1, 0.07)
		p.contour = math.max(p.contour or 0, 0.8)
		p.outer, p._outerCache = nil, nil
	end,
	post = function(p)
		if p.waterPremium then p.waterPremium.gain = math.max(p.waterPremium.gain or 0, 0.5) end
	end,
	motifs = { prefer = { "headland_street" }, forbid = { "ring_road", "culdesac_pods" } },
	offshoots = false,
	names = { tag = "cliff", words = { "Clifftop", "-on-the-Cliff", "Head", "Ness", "Point" } } })

-- harbour cove: a small bay with steep sides
-- (2026-10-14, seed-a run 2026-10-14_2237 load 2: no pick on a map of lake coasts, bays and hills: the probe's exact bay
-- pattern (one wet arc on the 300 m and 600 m rings) failed every lake town. Now the site's own coast reading leads:
-- the water within COVE_D, a coast share of COVE_COAST at least (water round much of the town), steep ground (p95 slope,
-- the wide survey's relief, the rough share); the probe's bay pattern adds COVE_BAY_K, open water on the 300 m ring
-- (wet > COVE_OPEN) rules it out)
CH.COVE_D = 380
CH.COVE_COAST = 0.45
CH.COVE_BAY_K = 1.15
CH.COVE_OPEN = 0.6
CH.register({ id = "harbour_cove", selectable = true,
	eligible = function(site)
		local f, st, pr = site.feats, site.stats, site.probe
		if f.body ~= "sea" and f.body ~= "lake" then return 0, "body:" .. tostring(f.body) end
		if f.island then return 0, "island" end
		local w = st.water
		if w == nil or w.kind ~= "coast" or (w.distance or math.huge) > CH.COVE_D then return 0, "far" end
		local coast = f.coast or 0
		local r1, r2 = pr and pr.rings and pr.rings[1], pr and pr.rings and pr.rings[2]
		local why = string.format("coast=%.2f,rough=%.2f,sd=%.0f,p95=%.2f,wet=%.2f", coast, f.rough or 0, site.wide.sd or 0,
			st.p95Slope or 0, r1 and r1.wet or -1)
		if coast < CH.COVE_COAST then return 0, "coast:" .. why end
		if r1 and r1.wet > CH.COVE_OPEN then return 0, "open:" .. why end
		local steep = math.max(clamp(((st.p95Slope or 0) - 0.08) / 0.12, 0, 1), clamp(((site.wide.sd or 0) - 12) / 25, 0, 1),
			clamp(((f.rough or 0) - 0.15) / 0.4, 0, 1))
		if steep <= 0.15 then return 0, "flat:" .. why end
		local bay = (r1 and r2 and r1.arcs == 1 and r2.arcs == 1 and r1.wet >= 0.1 and r2.wet >= r1.wet) and CH.COVE_BAY_K or 1
		local mid = 1 - math.max(0, 0.65 - coast) * 1.2
		return clamp((0.35 + 0.5 * steep) * mid * bay, 0, 1), why
	end,
	style = function(site)
		local r = site.region
		if r == "NORDIC" then return "NORDIC" end
		if EASTASIA[r or ""] then return "JP_DENSE" end
		if US[r or ""] then return "EU_ORGANIC" end
		return "MED_HILL"
	end,
	form = { id = "clustered", def = { shape = "compact", front = 0.85, sector = 0.3, greens = 0, hotspots = 0, pull = 0 } },
	apply = function(p)
		blockScale(p, 0.75, 0.8)
		p.templates = { main = "small", medium = "small", small = "xsmall" }
		p.curve = math.max(p.curve or 0, 25)
		p.contour = math.max(p.contour or 0, 0.8)
		p.outer, p._outerCache = nil, nil
	end,
	post = function(p)
		if p.waterPremium then
			p.waterPremium.gain = math.max(p.waterPremium.gain or 0, 0.6)
			p.waterPremium.band = math.max(p.waterPremium.band or 0, 300)
		end
	end,
	motifs = { prefer = { "harbour_crescent", "fishing_village" }, forbid = { "ring_road", "culdesac_pods", "workers_terraces" } },
	offshoots = false, levels = "early",
	names = { tag = "cove", words = { "Cove", "Harbour", "Haven", "Port", "Quay" } } })

-- waterfront: a river through the site
CH.RIVER_D = 320
CH.register({ id = "waterfront", selectable = true,
	eligible = function(site)
		local f, w = site.feats, site.stats.water
		if (f.river or 0) <= 0 or w == nil then return 0, "noRiver" end
		local d = w.distance or math.huge
		-- (2026-10-14 seed-a run: the map's river town read its river at 250 m; was 220)
		if d > CH.RIVER_D then return 0, string.format("far:%.0f", d) end
		return clamp(0.55 + 0.3 * (f.open or 0) + 0.15 * (1 - d / CH.RIVER_D), 0, 1), string.format("d=%.0f", d)
	end,
	style = function(site)
		local r = site.region
		if US[r or ""] then return "NA_GRID" end
		if EASTASIA[r or ""] then return "JP_DENSE" end
		return "EU_EXTENSION"
	end,
	form = { id = "linear", def = { shape = "linear", reach = 1, kaMul = 1.5, kbMul = 0.8, ribbon = 1.6 } },
	apply = function(p)
		-- streets parallel to the water (the grid takes the bank's axis; organic plans straighter)
		p.gridness = math.max(p.gridness or 0, 0.85)
		p.jitter = math.min(p.jitter or 5, 4)
		p.curve = math.min(p.curve or 10, 8)
		p.charBridges = true
	end,
	post = function(p)
		p.waterPremium = p.waterPremium or nil
		if p.waterPremium then p.waterPremium.gain = math.max(p.waterPremium.gain or 0, 0.45) end
	end,
	motifs = { prefer = {}, forbid = { "culdesac_pods" } },
	names = { tag = "river", words = { "Wharf", "Bridge", "-on-River", "Quay", "Ford" } } })

-- street village (Strassendorf): one long main street along a valley floor
CH.register({ id = "street_village", selectable = true,
	eligible = function(site)
		local f, pr, dr = site.feats, site.probe, site.stats.dirRelief
		if pr == nil or pr.floor == nil then return 0, "noAxis" end
		if dr == nil or not dr.valley then return 0, "noValley" end
		local why = string.format("floor=%.2f,sides=%.0f", pr.floor, pr.sides or 0)
		if pr.floor < 0.6 then return 0, "floor:" .. why end
		if (pr.sides or 0) < 12 then return 0, "sides:" .. why end
		return clamp(0.4 + 0.4 * (pr.floor - 0.6) / 0.4 + 0.2 * clamp(((pr.sides or 0) - 12) / 30, 0, 1), 0, 1)
			* ((f.valley or 0) > 0 and 1 or 0.8), why
	end,
	style = function(site)
		if US[site.region or ""] then return "NA_GRID" end
		return "EU_ORGANIC"
	end,
	form = { id = "linear", def = { shape = "linear", reach = 1, kaMul = 2.4, kbMul = 0.4, front = 1.3, greens = 0, ribbon = 2.0 } },
	apply = function(p)
		-- one long main street, almost no side streets; long plots along it
		blockScale(p, 1.3, 1)
		if p.radial then p.radial = { spokes = 2, ringEvery = 900 } end
		p.arterialEvery = 0
		p.collectorEvery = nil
		p.sub, p.cluster, p.lattice = nil, nil, nil
		p.curve = math.min(p.curve or 10, 14)
		p.jitter = math.min(p.jitter or 5, 6)
		p.deadEnds = 0
		p.crescents = 0
		p.outer, p._outerCache = nil, nil
		if p.irregular then p.irregular.ribbon, p.irregular.hotspots, p.irregular.sector = 2.0, 0, 0.05 end
	end,
	motifs = { prefer = { "ribbon_village" }, forbid = { "village_green", "ring_road", "culdesac_pods", "crossroads_hamlet",
		"workers_terraces", "valley_fishbone", "hill_climb", "switchbacks" } },
	offshoots = false,
	names = { tag = "valley", words = { "Street", "-in-the-Vale", "Dale", "Strassendorf", "Long" } } })

-- company town: a large industry within ~1.7 km (medium ~1.5 km), on flat land.
-- (2026-10-15, NEXT_PHASE_BRIEF 68: the score was 1.25 - d / 1500, the pick needs MIN_SCORE 0.4, so a heavy works had to
-- be within ~1275 m. The archived maps' starting towns have theirs at 1236-1577 m: 0 company towns on 16 maps. Now full
-- within COMPANY_FULL, MIN_SCORE at COMPANY_AT for a heavy works (a medium one, x 0.75, at ~1545 m), 0 at ~2170 m;
-- 5 of the 16 maps would now have an eligible town. The slope rule stays at 0.05: the near-misses were 0.08-0.11.)
CH.COMPANY_FULL = 1000     -- m: a heavy works this near scores full ...
CH.COMPANY_AT = 1700       -- ... and still MIN_SCORE this far
CH.COMPANY_R = 2200        -- m: industries farther away are not read (Driver:charIndustry)
CH.COMPANY_SLOPE = 0.05    -- mean slope at most this

--- The company town's distance score (0..1) for its nearest heavy / medium works at d m.
function CH.companyDist(d)
	d = tonumber(d)
	if d == nil or d ~= d or d > CH.COMPANY_R then return 0 end
	local span = math.max(1, CH.COMPANY_AT - CH.COMPANY_FULL)
	return clamp(1 - (1 - CH.MIN_SCORE) * (d - CH.COMPANY_FULL) / span, 0, 1)
end
CH.register({ id = "company_town", selectable = true,
	eligible = function(site)
		local ind, st = site.industry, site.stats
		if ind == nil then return 0, "noIndustry" end
		if ind.kind ~= "heavy" and ind.kind ~= "medium" then return 0, "light" end
		if (ind.d or math.huge) > CH.COMPANY_R then return 0, string.format("far:%.0f", ind.d or -1) end
		if (st.meanSlope or 0) > CH.COMPANY_SLOPE then return 0, string.format("steep:%.3f", st.meanSlope or 0) end
		local era = 1 - 0.5 * clamp(((tonumber(site.year) or 1960) - 1940) / 30, 0, 1)
		return clamp((ind.kind == "heavy" and 1 or 0.75) * CH.companyDist(ind.d or 0) * era, 0, 1),
			string.format("%s:%.0f", ind.kind, ind.d or 0)
	end,
	style = function() return "NA_GRID" end,
	form = { id = "clustered", def = { shape = "compact", block = 1, front = 0.7, sector = 0.2, greens = 0, hotspots = 0, pull = 0 } },
	apply = function(p, ctx)
		-- a strict grid of terraced rows, the main street to the works gate
		p.gridness, p.jitter, p.curve, p.angleRange = 1.0, 0, 0, 0
		p.block = { len = 110, depth = 44, sd = 0.02 }
		p.arterialEvery = 4
		p.collectorEvery = 2
		p.mech = p.mech or { lockAll = true, maxEdges = 28, fill = "dose" }
		p.outer, p._outerCache = nil, nil
		local ind = ctx and ctx.site and ctx.site.industry
		local c = ctx and ctx.pos or p.centre
		if ind and ind.x and not ctx.framed and c then
			p.charAxis = G.heading(c[1], c[2], ind.x, ind.y)
		end
	end,
	motifs = { prefer = { "workers_terraces" }, forbid = { "crescent", "village_green", "culdesac_pods", "ring_road" } },
	offshoots = false, levels = "early",
	names = { tag = "works", words = { "Works", "Colliery", "Mill", "-ton", "Furnace" } } })

-- garden city: wide flat open land, era 1900+
CH.GARDEN_YEAR = { 1895, 1905 }
CH.GARDEN_OPEN = 0.55
CH.register({ id = "garden_city", selectable = true,
	eligible = function(site)
		local f, pr = site.feats, site.probe
		if pr == nil then return 0, "noProbe" end
		-- (2026-10-14 seed-a run, a 1900 start: the ramp from 1900 halved every score (0.30 / 0.34 at the two open
		-- plains, below MIN_SCORE): Letchworth is 1903, so the ramp runs 1895-1905 and a plain open site scores ~0.5)
		local era = eraRamp(site.year, CH.GARDEN_YEAR[1], CH.GARDEN_YEAR[2])
		if era <= 0 then return 0, "era" end
		local why = string.format("open=%.2f,flat=%.2f,coast=%.2f", f.open or 0, pr.flat or 0, f.coast or 0)
		if (f.open or 0) < CH.GARDEN_OPEN or (pr.flat or 0) < 0.7 then return 0, "notOpen:" .. why end
		if (f.coast or 0) > 0.3 then return 0, "coast:" .. why end
		return clamp((0.25 + 0.75 * (f.open or 0) * (pr.flat or 0)) * era, 0, 1), why
	end,
	style = function() return "EU_EXTENSION" end,
	form = { id = "radiating", def = { shape = "compact", front = 1.0, ribbon = 1.6, greensAdd = 4, greensMin = 7 } },
	apply = function(p)
		-- concentric rings and radial boulevards, low density, a green belt
		p.grower = "organic"
		p.radial = { spokes = 8, ringEvery = 220 }
		p.gridness = 0.5
		p.curve = math.max(p.curve or 0, 18)
		p.jitter = math.min(p.jitter or 4, 4)
		blockScale(p, 1.35, 1.3)
		p.crescents = 3
		p.outer, p._outerCache = nil, nil
	end,
	motifs = { prefer = { "ring_road", "village_green" }, forbid = { "workers_terraces", "culdesac_pods" } },
	levels = "off",
	names = { tag = "garden", words = { "Garden City", "Green", "Park", "-Garden", "Grove" } } })

-- island town: a town on an island it can cover
CH.ISLAND_L = { 1200, 9000 }   -- m: the island's traced coast (a closed loop) within this
CH.ISLAND_DIRS_OPEN = 12       -- wide survey rays with water: an island whose shore trace did not close
CH.register({ id = "island_town", selectable = true,
	eligible = function(site)
		local f, sh = site.feats, site.stats.shore
		if not f.island then return 0, "notIsland" end
		-- (2026-10-14 seed-a run: an island read from the wide survey (water on 13 of 16 rays) whose shore trace stopped
		-- at a steep stretch: a narrow island / peninsula the town can still cover, a lower score)
		if sh == nil or not sh.island then
			local ww, dirs = site.wide.water or 0, site.wide.waterDirs or 0
			if dirs < CH.ISLAND_DIRS_OPEN then return 0, "openShore" end
			return clamp(0.4 + 0.4 * (ww - 0.35) / 0.3, 0, 0.7), string.format("open:dirs=%d,wet=%.2f", dirs, ww)
		end
		local L = sh.L or 0
		if L < CH.ISLAND_L[1] or L > CH.ISLAND_L[2] then return 0, string.format("size:%.0f", L) end
		return clamp(0.6 + 0.4 * (1 - (L - CH.ISLAND_L[1]) / (CH.ISLAND_L[2] - CH.ISLAND_L[1])), 0, 1), string.format("L=%.0f", L)
	end,
	style = function(site)
		if EASTASIA[site.region or ""] then return "JP_DENSE" end
		return "EU_ORGANIC"
	end,
	form = { id = "shore", def = { shape = "shore", reach = 1, front = 2.4, shore = true, kaMul = 2.0, kbMul = 1.2, charShore = true } },
	apply = function(p)
		blockScale(p, 0.85, 0.85)
		p.outer, p._outerCache = nil, nil
	end,
	post = function(p)
		if p.waterPremium then p.waterPremium.gain = math.max(p.waterPremium.gain or 0, 0.4) end
	end,
	motifs = { prefer = { "harbour_crescent", "peninsula_tip", "fishing_village" }, forbid = { "culdesac_pods" } },
	offshoots = false, levels = "early",
	names = { tag = "island", words = { "Isle", "-on-Sea", "Holm", "Ey", "Island" } } })

-- roundabout town (new town): wide flat open land, a later era; needs the one-way ring geometry (ot_roundabout)
CH.RB_YEAR = { france = 1940, EU = 1950, default = 1955 }
function CH.rbYear(site)
	if site.country == "france" then return CH.RB_YEAR.france end
	local r = site.region
	if r == "EU" or r == "MED" or r == "NORDIC" then return CH.RB_YEAR.EU end
	return CH.RB_YEAR.default
end
CH.register({ id = "roundabout_town", selectable = true,
	eligible = function(site)
		local f, pr = site.feats, site.probe
		if not site.rbOk then return 0, "noRoundabouts" end
		if pr == nil then return 0, "noProbe" end
		local from = CH.rbYear(site)
		local era = eraRamp(site.year, from, from + 10)
		if era <= 0 or not site.newTemplates then return 0, "era:" .. from end
		local why = string.format("open=%.2f,flat=%.2f,from=%d", f.open or 0, pr.flat or 0, from)
		if (f.open or 0) < 0.6 or (pr.flat or 0) < 0.65 then return 0, "notOpen:" .. why end
		-- (2026-10-14 seed-a runs: a floor, so an open plain of the era scores like the other kinds' good sites)
		return clamp((0.3 + 0.7 * (f.open or 0) * (pr.flat or 0)) * era, 0, 1), why
	end,
	style = function(site)
		if US[site.region or ""] then return "NA_GRID" end
		return "EU_EXTENSION"
	end,
	form = { id = "radiating", def = { shape = "cross", reach = 1, ribbon = 1.5, greensAdd = 2, greensMin = 3 } },
	apply = function(p)
		-- distributor roads between neighbourhood cells: main lines every few blocks, the lattice ahead
		if p.grower == "grid" then
			p.arterialEvery = 3
			p.collectorEvery = nil
			p.lattice = { lead = 1, depth = 3, discount = 0.7 }
		elseif p.radial then
			p.radial = { spokes = 6, ringEvery = 240 }
		end
		blockScale(p, 1.35, 1.3)
		p.outer, p._outerCache = nil, nil
		-- (2026-10-14 §56, showcase run 2026-10-14_2150: the strong cross arms ran ~1 km out empty, zig-zag lanes and
		-- deep-arm back-row loops with no houses (emptyLen 2 -> 7 km): no street more than ~1.25 blocks from a street with
		-- houses (the housed front, ot_select), no deep-arm back rows; the rings sit among houses, ot_ring armsOk. A mild
		-- reach starved the plan instead (test_rings))
		p.housedLead = 1.25
		p.noDeepArms = true
		-- (ot_ring: share of the eligible new crossings that become one-way rings; RG.townShare adds gateways and pairs)
		p.rings = { main = 0.95, mini = 0.5 }
	end,
	motifs = { prefer = {}, forbid = { "culdesac_pods", "workers_terraces" } },
	names = { tag = "newtown", words = { "New", "-Ville-Nouvelle", "Park", "Rise", "Cross" } } })

---------------------------------------------------------------------------
-- selection

--- The number of strong characters for a map of n own towns (see the header).
function CH.quota(n)
	n = tonumber(n) or 0
	if n <= 0 then return 0 end
	local q = math.floor(n / CH.QUOTA_PER + 0.5)
	q = clamp(q, 1, CH.QUOTA_MAX)
	if n < CH.TWO_FROM then q = 1 end
	return q
end

--- Every selectable kind's score for a site: list { { kind, score, why } } (descending; score 0 entries kept for the log).
function CH.scores(site)
	local out = {}
	for _, k in ipairs(CH.KINDS) do
		if k.selectable then
			local s, why = safeEligible(k, site)
			out[#out + 1] = { kind = k.id, score = s, why = why }
		end
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.kind < b.kind
	end)
	return out
end

--- The map's picks. sites = { site } (CH.site records with id, x, y; the caller leaves out created towns), o = {
--- fixed = { [id] = kind id | false } (saved picks: a kind stays, false never becomes one), excluded = { [id] = why }
--- (secluded, metropolis-sized ...), seed = map seed }. Returns picks = { [id] = { kind, score, why, fixed } }, count
--- (the quota), log = { { id, best kind, score, why, picked = bool, skip = reason } }.
function CH.select(sites, o)
	o = o or {}
	local fixed, excluded = o.fixed or {}, o.excluded or {}
	local n = math.min(#sites, CH.TOWNS_MAX)
	local count = CH.quota(n)
	local picks, used, chosen = {}, {}, {}
	local logL = {}
	local byId = {}
	for i = 1, n do byId[sites[i].id] = sites[i] end
	-- saved picks first
	local ids = {}
	for i = 1, n do ids[#ids + 1] = sites[i].id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local k = fixed[id]
		if type(k) == "string" and CH.BY_ID[k] then
			picks[id] = { kind = k, score = 1, why = "saved", fixed = true }
			used[k] = true
			chosen[#chosen + 1] = byId[id]
		end
	end
	local cands = {}
	local scored, elig = {}, {}
	for i = 1, n do
		local sc = CH.scores(sites[i])
		scored[i] = sc
		for _, c in ipairs(sc) do
			if c.score >= CH.MIN_SCORE then elig[c.kind] = (elig[c.kind] or 0) + 1 end
		end
	end
	for i = 1, n do
		local s = sites[i]
		local sc = scored[i]
		local best = sc[1]
		local entry = { id = s.id, kind = best and best.kind or "-", score = best and best.score or 0, why = best and best.why or "-",
			scores = sc }
		logL[#logL + 1] = entry
		if picks[s.id] then entry.picked, entry.skip = true, "saved"
		elseif fixed[s.id] == false then entry.skip = "framed"
		elseif excluded[s.id] then entry.skip = excluded[s.id]
		else
			for _, c in ipairs(sc) do
				if c.score >= CH.MIN_SCORE then
					-- (rarity: a kind only a few of the map's towns qualify for is the more distinct there)
					local rare = 1 + CH.RARE_W * (1 - math.min(1, (elig[c.kind] or 1) / math.max(1, n)))
					cands[#cands + 1] = { site = s, kind = c.kind, score = c.score, why = c.why,
						key = c.score * rare * (CH.KIND_W[c.kind] or 1) + CH.JITTER * rng.draw(o.seed or 1, "charPick", s.id, CH.INDEX[c.kind] or 0) }
				end
			end
			if (best and best.score or 0) < CH.MIN_SCORE then entry.skip = "low" end
		end
	end
	table.sort(cands, function(a, b)
		if a.key ~= b.key then return a.key > b.key end
		if a.site.id ~= b.site.id then return a.site.id < b.site.id end
		return a.kind < b.kind
	end)
	local nPicked = 0
	for _ in pairs(picks) do nPicked = nPicked + 1 end
	for _, c in ipairs(cands) do
		if nPicked >= count then break end
		local id = c.site.id
		if picks[id] == nil and not used[c.kind] then
			local near = false
			for _, q in ipairs(chosen) do
				if G.dist(q.x or 0, q.y or 0, c.site.x or 0, c.site.y or 0) < CH.NEIGHBOUR_M then near = true break end
			end
			if not near then
				picks[id] = { kind = c.kind, score = c.score, why = c.why }
				used[c.kind] = true
				chosen[#chosen + 1] = c.site
				nPicked = nPicked + 1
			end
		end
	end
	for _, e in ipairs(logL) do
		local p = picks[e.id]
		if p then e.picked, e.kind, e.score, e.why = true, p.kind, p.score, p.why
		elseif e.skip == nil then
			e.skip = (e.score >= CH.MIN_SCORE) and "quota" or "low"
		end
	end
	return picks, count, logL
end

--- A map seed from the towns (ids and rounded positions; order-free).
function CH.mapSeed(sites)
	local h = 7
	local list = {}
	for _, s in ipairs(sites or {}) do list[#list + 1] = s end
	table.sort(list, function(a, b) return a.id < b.id end)
	for _, s in ipairs(list) do h = rng.hash(h, s.id, math.floor((s.x or 0) / 10), math.floor((s.y or 0) / 10)) end
	return h
end

---------------------------------------------------------------------------
-- application (ot_style.resolve, ot_form.pick, ot_motif.pick)

--- The style id kind wants for site / inputs (nil: the town's own).
function CH.styleFor(kindId, site)
	local k = CH.BY_ID[kindId or ""]
	if k == nil or k.style == nil then return nil end
	local ok, id = pcall(k.style, site or {})
	return ok and id or nil
end

--- The forced form of a kind for ot_form.pick: { id, def, kind } or nil.
function CH.formFor(kindId)
	local k = CH.BY_ID[kindId or ""]
	if k == nil or k.form == nil then return nil end
	return { id = k.form.id, def = k.form.def, kind = k.id }
end

--- The motif preferences of a kind ({ prefer, forbid }) or nil.
function CH.motifsFor(kindId)
	local k = CH.BY_ID[kindId or ""]
	return k and k.motifs or nil
end

--- Runs the kind's apply hook on the resolved style p (before the shape / form). ctx = { terrain, site, framed }.
function CH.apply(p, kindId, ctx)
	local k = CH.BY_ID[kindId or ""]
	if k == nil or p == nil then return false end
	if k.apply then
		local ok, err = pcall(k.apply, p, ctx or {})
		if not ok then p.charErr = tostring(err) end
	end
	p.charKind = k.id
	-- (the frame saves selectable kinds, `ck`; deep forest keeps its own `fd`)
	if k.selectable then p.charIndex = CH.INDEX[k.id] end
	return true
end

--- Runs the kind's post hook (after the form and the waterfront).
function CH.post(p, kindId, ctx)
	local k = CH.BY_ID[kindId or ""]
	if k == nil or p == nil or k.post == nil then return end
	local ok, err = pcall(k.post, p, ctx or {})
	if not ok then p.charErr = tostring(err) end
end

--- May a town of this kind found districts / Works?
function CH.offshootsOk(kindId)
	local k = CH.BY_ID[kindId or ""]
	return k == nil or k.offshoots ~= false
end

--- The kind's levels mode ("early" | "off" | nil).
function CH.levels(kindId)
	local k = CH.BY_ID[kindId or ""]
	return k and k.levels or nil
end

-- the naming phase's character kinds (ot_placename charForms, NEXT_PHASE_BRIEF 53 Part B: hilltop, harbour, cove,
-- street, company, garden, island, market, church; an unknown one is an ordinary character town)
CH.NAME_KIND = { hilltop = "hilltop", clifftop = "hilltop", harbour_cove = "cove", waterfront = "harbour",
	street_village = "street", company_town = "company", garden_city = "garden", island_town = "island",
	roundabout_town = "market",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61: deep forest; the driver's naming phase adds "secluded" (an ordinary character
	-- town, ot_map.characters) and "coastal" (the coastal hugger, ot_map.coastal), CH.NAME_SECLUDED / CH.NAME_COASTAL)
	deep_forest = "forest" }
CH.NAME_SECLUDED, CH.NAME_COASTAL = "secluded", "coastal"

--- The naming phase's kind for a strong kind (CH.NAME_KIND), or nil.
function CH.nameKind(kindId)
	return CH.NAME_KIND[kindId or ""]
end

--- The naming hook: { kind, tag, words } for a kind (nil: none). The name generator may read the tag as a site tag and
--- the words as cue affixes ("-on-the-Hill", "Cove", "Wharf", "Garden City" ...); the driver hands it out with
--- Driver:characterNameCue(t).
function CH.nameCue(kindId)
	local k = CH.BY_ID[kindId or ""]
	if k == nil or k.names == nil then return nil end
	local words = {}
	for i, w in ipairs(k.names.words or {}) do words[i] = w end
	return { kind = k.id, tag = k.names.tag, words = words, nameKind = CH.nameKind(k.id) }
end

--- PLAN / STYLE / ALLTOWN `char=` text: the kind id (+ ":densify" for a densify town), "-" for none.
function CH.text(kindId, densify)
	local t = kindId or "-"
	if densify then t = (kindId and (kindId .. "+") or "") .. "densify" end
	return t
end

---------------------------------------------------------------------------
-- densify (NEXT_PHASE_BRIEF 52 item 2)

CH.DZ_ON = true
CH.DZ_P = 0.45             -- the share of towns, before the weights (0.33 until the 2026-10-14 seed-a run: its shore /
                           -- linear towns drew at 0.13-0.16, 1 of 16 on)
CH.DZ_P_MIN, CH.DZ_P_MAX = 0.05, 0.85
CH.DZ_MAT = 0.5            -- the trait is drawn when a town first reads this mature (ot_assess.maturity)
CH.DZ_FORM = { linear = 0.3, sprawling = 0.7, fingers = 0.8, shore = 0.85, clustered = 1.25, radiating = 1.15, wide = 1 }
CH.DZ_RAIL = 1.4           -- a rail passenger station near the town
CH.DZ_SIZE = { 0.7, 1.4 }  -- by the town's size rank (smallest .. biggest)
CH.DZ_CENTRAL = { 0.75, 1.25 }   -- by its distance from the map centre (rim .. centre)

--- The densify draw for a town. o = { seed, form (id), sizeRank (0 smallest .. 1 biggest), central (0 rim .. 1 centre),
--- rail (bool), blocked = reason or nil (strong kind / deep / secluded / coastal / created / metro) }. Returns on (bool),
--- why ("p=..,u=.." or the reason), p.
function CH.densifyDraw(o)
	o = o or {}
	if not CH.DZ_ON then return false, "off", 0 end
	if o.blocked then return false, o.blocked, 0 end
	local w = (CH.DZ_FORM[o.form or ""] or 1)
	w = w * G.lerp(CH.DZ_SIZE[1], CH.DZ_SIZE[2], clamp(o.sizeRank or 0.5, 0, 1))
	w = w * G.lerp(CH.DZ_CENTRAL[1], CH.DZ_CENTRAL[2], clamp(o.central or 0.5, 0, 1))
	if o.rail then w = w * CH.DZ_RAIL end
	local p = clamp(CH.DZ_P * w, CH.DZ_P_MIN, CH.DZ_P_MAX)
	local u = rng.decide(o.dv, o.seed or 1, "densify")
	local why = string.format("p=%.2f,u=%.2f", p, u)
	return u < p, why, p
end

-- a densify town once mature: its demand builds held harder (ot_assess), level weights toward the higher levels
-- (ot_upward), smaller blocks in new pieces, the upward dose from fewer buildings
CH.DZ_HOLD_FREE = 0.42     -- the mature hold's free-lot line (ot_assess MATURE_HOLD_FREE 0.60)
CH.DZ_DEMK = 0.06          -- the mature cap's demand share (ot_assess MATURE_DEMK 0.18)
-- (the level weights of a densify town: ot_upward DZ_PB_AIM / DZ_K_MIN / DZ_CLEAR_PB)
CH.DZ_BLOCK = 0.75         -- new pieces' blocks x this (at least MIN_BLOCK)
CH.DZ_UP_BUILDINGS = 300   -- the upward dose from this many buildings (ot_upward MIN_BUILDINGS 1500)
CH.DZ_RAMP_MAT = 0.75      -- (2026-10-15) the levers ramp in from the draw (DZ_MAT) to this level maturity (mirrors
                           -- ot_upward DZ_RAMP_MAT: the level tilt; the driver's densifyDemand: the hold)

--- The densify levers' strength (0..1) at level maturity mat: 0 at DZ_MAT, 1 from DZ_RAMP_MAT.
function CH.dzRamp(mat)
	return clamp(((mat or 0) - CH.DZ_MAT) / math.max(0.01, CH.DZ_RAMP_MAT - CH.DZ_MAT), 0, 1)
end

--- Applies the densify core to a resolved style (smaller blocks, denser cross streets).
function CH.densifyStyle(p)
	if p == nil then return end
	blockScale(p, CH.DZ_BLOCK, CH.DZ_BLOCK)
	if (p.arterialEvery or 0) > 2 then p.arterialEvery = math.max(2, math.floor(p.arterialEvery / 2)) end
	if p.collectorEvery and p.collectorEvery > 1 then p.collectorEvery = math.max(1, math.floor(p.collectorEvery / 2)) end
	if p.radial and p.radial.ringEvery then
		p.radial = { spokes = p.radial.spokes, ringEvery = math.max(120, p.radial.ringEvery * 0.7) }
	end
	if p.greens then
		-- (the core fills: no new meadow reserves)
		p.greens = {}
	end
	p.densify = true
end

return CH
