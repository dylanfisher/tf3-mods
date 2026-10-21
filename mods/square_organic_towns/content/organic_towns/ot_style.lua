-- Organic Towns: style profiles (data, PLAN.md section 3) and the resolver inputs -> StyleParams.
-- Pure. Lengths in metres, angles in degrees inside profiles; the resolved `axis` is in radians.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local SITE = ug_require "square_organic_towns::/organic_towns/ot_site.lua"
local FM = ug_require "square_organic_towns::/organic_towns/ot_form.lua"
local GR = ug_require "square_organic_towns::/organic_towns/ot_grid.lua"
local MO = ug_require "square_organic_towns::/organic_towns/ot_motif.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local CH = ug_require "square_organic_towns::/organic_towns/ot_character.lua"

local M = {}

-- Street classes used by the planners, and the base template size each maps to by default.
M.CLASSES = { "main", "medium", "small" }
M.TEMPLATE_DIR = "::/infrastructure/street/town/"

-- Lots: the town developer cuts parcels in 8 m cells, up to 4 cells deep (TOWN_BUILDING.depth 1-4). MIN_BLOCK is the
-- least spacing of two parallel street centerlines; no grower makes blocks below it. The small town street is 16 m
-- wide with its sidewalks (town_{old,new}_small laneConfigs 3 + 5 + 5 + 3; medium 24, large 32), so 44 m leaves 28 m
-- of land: one row of 3-cell lots, no 1-cell slivers. A compromise (2026-10-18, user: "too frequent" one-building
-- blocks at the old 40 m, which counted the street as 8 m): 48 m would fit two 2-cell lots back to back, but thins
-- the towns more than wanted.
M.LOT_CELL = 8
M.MIN_BLOCK = 44
-- Grids at or above this gridness are strict: no junction jitter, no bent pieces (NA grid, MED ensanche).
M.STRICT_GRID = 0.9
M.LATE_ERA = 4   -- era band (ot_inputs: 1950-1980) from which `lateTemplates` apply

-- Shared defaults; each profile overrides what differs.
local DEFAULTS = {
	grower = "grid",
	block = { len = 120, depth = 80, sd = 0.1 },
	gridness = 0.8, jitter = 5, curve = 10,
	radial = nil,
	arterialEvery = 6,
	-- collector (medium) lines every this many blocks (nil: half way between the arterials when arterialEvery >= 4)
	collectorEvery = nil,
	-- small pieces curve gently and some cross streets end as cul-de-sacs in this profile itself, not only as
	-- the outer zone of another style (NA suburb)
	curvyLocal = false,
	-- superblock interior (ot_grow_grid): each lattice cell (block.len x block.depth, the arterial grid) is
	-- subdivided by local streets: u / v = fine lines per cell along each axis, cross[s + 1] = the fine u offsets
	-- (1 .. u - 1) whose streets cross strip s (0 .. v - 1, between two interior lines along the axis) of the cell;
	-- art = every this many cell lines main, the others medium (collectors)
	sub = nil,
	-- lattice-first growth (Showcase v8 round; superblock from LATE_ERA): the arterial / collector cell lines lead by
	-- `lead` cells beyond the junction front, up to `depth` new pieces from the network, at `discount` x their cost,
	-- so the superblock frame is laid out early and its interior fills behind it
	lattice = nil,
	-- cluster loops (ot_grow_grid, with `sub`; Nordic): { depth = cul-de-sac length x cell depth, green = share of
	-- cells left without streets, bow = loop side bow x cell length }
	cluster = nil,
	-- growth mechanics borrowed from the metropolis at a smaller scale (Showcase v9 round; user: "the metropolis ideas
	-- are best so far. Metropolis grid starts to feel almost like it could be the American grid or suburbs"):
	-- { lockAll = every new street roadDevelopmentLocked (the town can't branch its own organic streets off our
	-- grid), maxEdges = edges per increment (whole blocks / frames at once), fill = "dose" (makeTownDevelopAtCmd
	-- beside the build's new streets, the initial capacities restored after, ot_driver) } or nil
	mech = nil,
	-- housed front (ot_select.HOUSED): new streets at most this many blocks from a street with houses, nil = off
	housedLead = nil,
	-- empty budget (ot_core): unhoused street length (m) the town may have after an increment, nil = off (polycentric)
	emptyBudget = nil,
	-- crescents around a green (ot_crescent; user on the EU organic town: "the empty green space and big curve is
	-- interesting"): this many of the green reserves get a long smooth arc around them, interior left open
	crescents = 0,
	-- overrides applied from LATE_ERA together with lateTemplates (street hierarchy 2026-10-12: few arterials,
	-- collectors between them, mostly local streets), e.g. { arterialEvery = 4, collectorEvery = 2 }
	late = nil,
	-- class of the cross axis (the lattice line through the centre across the town axis; nil: main)
	crossAxis = nil,
	-- town street widths: towns build mostly small streets, a few medium ones on their main axes; our large
	-- main streets read far wider than the town around them (showcase screenshots 2026-10-11), so a planned main
	-- street is medium, a medium (collector) street small like the minor ones
	templates = { main = "medium", medium = "small", small = "small" },
	deadEnds = 0,
	maxSlope = 0.10, contour = 0.3,
	waterSetback = 25, waterfront = false,
	stationPull = 0.3,
	lead = 1, ribbon = 0.3,
	angleRange = 10,
	weights = { res = { 1, 1, 1, 1 } },
	outer = nil,   -- { id = profile id, from = radius in m }: growth beyond `from` uses that profile
	-- street hierarchy by era (user 2026-10-11: more wide streets in later years where they fit): from LATE_ERA
	-- (1950) the sprawling styles map arterial = large, collector = medium, local = small; old cores, MED hill,
	-- JP and the EU styles keep `templates`. Wide streets only on through routes (ot_select.through, ot_core
	-- hierarchy), never on dead-end stubs, and only as runs of 300 m or more that reach an anchor (§73,
	-- ot_core.continuity: a planned main street otherwise goes out at the narrower template).
	lateTemplates = nil,
	-- Irregular growth (ot_select cost; PLAN.md 6.2 "Irregular growth"): real towns don't grow as even rings.
	--   sector    0..0.5 amplitude of a seeded angular preference (growth reaches 1 +- sector x as far)
	--   lobes     harmonics of that preference (1 = one favoured side, 2 = two opposite lobes)
	--   ribbon    gain on `ribbon`: corridors along main streets (arterials, spokes) grow ahead (<= RIBBON_MAX)
	--   hotspots  seeded attractors 3-6 blocks out (leapfrog patches reached along a main street), `pull`
	--   coast     0..1 bias of the preference toward the water side (coast towns grow toward and along it)
	irregular = { sector = 0.2, lobes = 2, ribbon = 1, hotspots = 0, pull = 0, coast = 0.3 },
}

M.PROFILES = {
	NA_GRID = { logName = "NA grid", block = { len = 200, depth = 100, sd = 0.05 }, gridness = 0.98, jitter = 0, curve = 0,
		lateTemplates = { main = "large", medium = "medium", small = "small" },
		late = { arterialEvery = 6, collectorEvery = 2, crossAxis = "medium", lattice = { lead = 1, depth = 6, discount = 0.7 } },
		arterialEvery = 8, maxSlope = 0.12, contour = 0.1, lead = 2, ribbon = 0.6, angleRange = 0,
		mech = { lockAll = true, maxEdges = 28, fill = "dose" }, housedLead = 1.5,
		weights = { res = { 1, 0.6, 0.3, 0.1 }, core = { 0.3, 0.6, 1, 0.8 } },
		irregular = { sector = 0.15, lobes = 2, ribbon = 0.6, hotspots = 0, pull = 0, coast = 0.2 } },
	NA_SUBURB = { logName = "NA suburb", block = { len = 150, depth = 90, sd = 0.25 }, gridness = 0.4, jitter = 10, curve = 25,
		lateTemplates = { main = "large", medium = "medium", small = "small" },
		late = { arterialEvery = 8, collectorEvery = 2, crossAxis = "medium" }, curvyLocal = true,
		arterialEvery = 0, deadEnds = 0.2, maxSlope = 0.10, contour = 0.5, lead = 2, ribbon = 0.3,
		mech = { lockAll = true, maxEdges = 28, fill = "dose" }, housedLead = 2,
		weights = { res = { 1, 0.3, 0, 0 } },
		irregular = { sector = 0.3, lobes = 1, ribbon = 0.8, hotspots = 2, pull = 0.5, coast = 0.3 } },
	EU_ORGANIC = { logName = "EU organic", grower = "organic", block = { len = 60, depth = 45, sd = 0.4 }, gridness = 0.3,
		jitter = 15, curve = 20, radial = { spokes = 6, ringEvery = 300 }, arterialEvery = 0, maxSlope = 0.10,
		contour = 0.5, lead = 1, ribbon = 0.2, angleRange = 30, weights = { res = { 0.3, 0.8, 1, 0.5 } }, crescents = 2,
		irregular = { sector = 0.35, lobes = 2, ribbon = 1.5, hotspots = 0, pull = 0, coast = 0.4 } },
	EU_EXTENSION = { logName = "EU 19th-c. extension", grower = "organic", block = { len = 110, depth = 80, sd = 0.15 },
		gridness = 0.8, jitter = 4, curve = 5, radial = { spokes = 6, ringEvery = 300 }, arterialEvery = 5,
		maxSlope = 0.10, contour = 0.3, lead = 1, ribbon = 0.3, weights = { res = { 0.2, 0.6, 1, 0.8 } }, crescents = 1,
		irregular = { sector = 0.25, lobes = 2, ribbon = 1.2, hotspots = 0, pull = 0, coast = 0.3 } },
	-- (block.len 44 = MIN_BLOCK, 40 until 2026-10-18: the blocks never come smaller; the depth stays the lanes' nominal 30)
	MED_HILL = { logName = "MED hill town", grower = "organic", block = { len = 44, depth = 30, sd = 0.4 }, gridness = 0.2,
		jitter = 20, curve = 30, radial = { spokes = 4, ringEvery = 150 }, arterialEvery = 0, maxSlope = 0.10,
		contour = 0.9, lead = 0, ribbon = 0.1, angleRange = 45,
		templates = { main = "small", medium = "small", small = "xsmall" },
		weights = { res = { 0.1, 0.4, 1, 0.6 } }, crescents = 1,
		irregular = { sector = 0.2, lobes = 1, ribbon = 1, hotspots = 0, pull = 0, coast = 0.3 } },
	MED_ENSANCHE = { logName = "MED ensanche", block = { len = 113, depth = 113, sd = 0.02 }, gridness = 1.0, jitter = 0,
		lateTemplates = { main = "large", medium = "medium", small = "small" },
		curve = 0, arterialEvery = 6, maxSlope = 0.06, contour = 0, lead = 1, ribbon = 0.2, angleRange = 0,
		mech = { lockAll = true, maxEdges = 28, fill = "dose" }, housedLead = 2,
		weights = { res = { 0, 0.2, 0.8, 1 } },
		irregular = { sector = 0.1, lobes = 2, ribbon = 0.5, hotspots = 0, pull = 0, coast = 0.1 } },
	JP_DENSE = { logName = "JP dense", block = { len = 50, depth = 35, sd = 0.3 }, gridness = 0.6, jitter = 5, curve = 8,
		arterialEvery = 6, maxSlope = 0.12, contour = 0.6, stationPull = 0.8, lead = 1, ribbon = 0.5, angleRange = 10,
		templates = { main = "small", medium = "small", small = "xsmall" },
		weights = { res = { 1, 0.9, 0.3, 0.2 }, core = { 0.2, 0.5, 1, 1 } },
		irregular = { sector = 0.3, lobes = 1, ribbon = 1, hotspots = 1, pull = 0.3, coast = 0.3 } },
	-- Nordic (Showcase v9 round; was a plain 90 x 70 m grid that read as a generic town). Scandinavian post-war
	-- suburbs (Stockholm's Vallingby / Farsta, Oslo's drabantbyer, Tapiola "forest town"; Copenhagen's Finger Plan and
	-- Stockholm's green wedges): curving collector loops around neighbourhood cells, houses in small clusters on short
	-- dead-end streets off the loops, much green between the clusters and whole cells left as meadow / forest, low
	-- density. Cells 190 x 150 m (cluster loops), cul-de-sacs 0.42 of the cell deep, 30 % green cells, one crescent.
	NORDIC = { logName = "Nordic", block = { len = 190, depth = 150, sd = 0.12 }, gridness = 0.6, jitter = 6, curve = 20,
		sub = { u = 3, v = 1, cross = { {} }, art = 3 }, cluster = { depth = 0.42, green = 0.3, bow = 0.12 },
		arterialEvery = 3, maxSlope = 0.10, contour = 0.8, lead = 1, ribbon = 0.6, angleRange = 10,
		housedLead = 1, crescents = 1,
		weights = { res = { 1, 0.7, 0.2, 0 } },
		irregular = { sector = 0.3, lobes = 1, ribbon = 1, hotspots = 0, pull = 0, coast = 0.6 } },
	SUPERBLOCK = { logName = "Superblock", block = { len = 350, depth = 250, sd = 0.1 }, gridness = 0.9, jitter = 2, curve = 0,
		lateTemplates = { main = "large", medium = "medium", small = "small" },
		arterialEvery = 1, maxSlope = 0.08,
		sub = { u = 4, v = 3, cross = { { 2 }, { 1, 3 }, { 2 } }, art = 3 },
		late = { crossAxis = "medium", lattice = { lead = 0.5, depth = 8, discount = 0.6 } }, contour = 0.2, lead = 1, ribbon = 0.3, angleRange = 0,
		mech = { lockAll = true, maxEdges = 30 }, housedLead = 1,
		weights = { res = { 0, 0.2, 0.6, 1 } },
		irregular = { sector = 0.15, lobes = 2, ribbon = 0.5, hotspots = 0, pull = 0, coast = 0.1 } },
}

-- Ids in display order (SVG preview, a future style param).
M.IDS = { "NA_GRID", "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "MED_ENSANCHE", "JP_DENSE", "NORDIC",
	"SUPERBLOCK" }

local function copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = copy(x) end
	return t
end

--- Profile `id` merged over the defaults (a fresh table).
function M.profile(id)
	local p = M.PROFILES[id]
	if p == nil then return nil end
	local out = copy(DEFAULTS)
	for k, v in pairs(p) do out[k] = copy(v) end
	out.id = id
	return out
end

--- Base template resource for a street class in a year band (`newTemplates` from ot_inputs).
function M.templatePath(size, newTemplates)
	return M.TEMPLATE_DIR .. "town_" .. (newTemplates and "new" or "old") .. "_" .. size .. ".street_template"
end

local function meanSlope(inputs)
	return inputs.terrain and inputs.terrain.meanSlope or 0
end

M.BLOCK_TROPICAL = 1.15   -- x block length / depth on a tropical map

--- Profile id for the inputs (before modifiers).
function M.pickProfile(inputs)
	if inputs.forceStyle and M.PROFILES[inputs.forceStyle] then return inputs.forceStyle end
	local r = inputs.region
	if r == "US" or r == "OCEANIA" then return "NA_GRID" end
	if r == "EU" then
		if inputs.climate == "dry" then return "MED_HILL" end
		return "EU_ORGANIC"
	end
	if r == "MED" then
		-- (the ensanche from 1920, ot_site FROM_YEAR: era range 1900+)
		if inputs.country == "spain" and inputs.year >= 1920 and meanSlope(inputs) < 0.04 then return "MED_ENSANCHE" end
		return "MED_HILL"
	end
	if r == "NORDIC" then return "NORDIC" end
	if r == "RU" then return inputs.era >= 4 and "SUPERBLOCK" or "EU_ORGANIC" end
	if r == "JP" then return "JP_DENSE" end
	if r == "EAST_ASIA" then return inputs.era >= 4 and "SUPERBLOCK" or "JP_DENSE" end
	-- (the pan-Asian list: old organic cores, the dry belt's hill towns, superblocks from 1950)
	if r == "ASIA" then
		if inputs.era >= 4 then return "SUPERBLOCK" end
		return inputs.climate == "dry" and "MED_HILL" or "EU_ORGANIC"
	end
	return "EU_ORGANIC"
end

--- Outer-zone profile (growth beyond `from` metres switches to it), or nil. look: the outer zone's grid look
--- (ot_grid, organic <-> gridded, 2026-10-13): the zone starts closer as the look rises, and from OUTER_LOOK_MIN an
--- EU extension town gets a straighter extension ring of its own (later districts more regular, the core unchanged).
M.OUTER_LOOK_MIN = 0.2
M.EXT_OUTER_FROM = 450
-- the EU organic town's extension ring from this year (era range 1900+, 2026-10-13: was era band 2, from 1850, i.e.
-- always; now the first years of a 1900 game grow organic all the way out)
M.EXT_OUTER_YEAR = 1915
-- Organic ring geometry (2026-10-14, NEXT_PHASE_BRIEF 56; user on the showcase run 2026-10-14_2150: "eu organic looks
-- strange with the big equal circles on the outside"): the organic grower's rings wobble per spoke and are spaced
-- unevenly (ot_grow_organic), the ring road's radius wobbles (ot_motif_town), crescents bulge (ot_crescent), the ring
-- pieces wait for the houses (ot_select RING_LEAD_M) and the outer zone blends in over ZONE_BLEND m. p.ringWobble for a
-- town without a frame, or whose frame says so (ot_saved `og`); a town framed before keeps its even rings.
M.ORGANIC_RINGS = true
M.ZONE_BLEND = 1.5          -- x radial.ringEvery: the outer zone blends in over this much beyond its `from`
M.LOOK_ZONE = true          -- (2026-10-14 §57) an organic town's high grid look as an outer zone of its own style
M.LOOK_CORE = 0.35          -- ... the core's look at most
M.LOOK_ZONE_MAX = 0.5       -- ... the zone's (an organic style never a full lattice)
M.LOOK_FROM = 320           -- m: ... from here, blended over ZONE_BLEND
M.ZONE_BLEND_STEPS = 3
function M.pickOuter(id, inputs)
	local b = inputs.gridBias
	local look = b and math.min(GR.LOOK_MAX, b.look + GR.OUTER_EXTRA) or nil
	local shrink = look and GR.OUTER_SHRINK * math.max(0, look) or 0
	if id == "NA_GRID" and inputs.era >= 4 then return { id = "NA_SUBURB", from = 500 } end
	if id == "EU_ORGANIC" and (inputs.year or 1960) >= M.EXT_OUTER_YEAR then return { id = "EU_EXTENSION", from = 300 - shrink, look = look } end
	if id == "EU_EXTENSION" and look and look >= M.OUTER_LOOK_MIN then
		return { id = "EU_EXTENSION", from = M.EXT_OUTER_FROM - shrink, look = look }
	end
	return nil
end

--- StyleParams for a town: the profile with climate, region, size, era and terrain modifiers applied, the
--- templates resolved to base resource paths, the grid axis (radians) and the plan centre.
function M.resolve(inputs)
	local seed = rng.seed(inputs.townId, inputs.pos[1], inputs.pos[2])
	-- (§68: the decision draws, rng.decide: 1 for a town framed before §68 (no `dv` on its frame), 2 otherwise)
	local drawV = (inputs.frame and inputs.frame.axis and inputs.frame.drawV ~= 2) and 1 or 2
	-- a motif forced by the dev tools may set inputs first (ot_motif: hill road -> the shape linear)
	MO.applyInputs(inputs)
	-- the style: forced (setting / dev tools), saved with the town's plan frame, from the town's site (Automatic:
	-- ot_site, the region only biases), else the region's profile
	local id, source, why
	if inputs.forceStyle and M.PROFILES[inputs.forceStyle] then
		id, source = inputs.forceStyle, "forced"
	elseif inputs.frame and inputs.frame.style and M.PROFILES[inputs.frame.style] then
		id, source, why = inputs.frame.style, "saved", "saved"
	elseif inputs.charKind and M.PROFILES[CH.styleFor(inputs.charKind, inputs.charSite or inputs) or ""] then
		-- (a strong character, ot_character 2026-10-14: its kind's style before the site draw and the diversity penalty)
		id, source, why = CH.styleFor(inputs.charKind, inputs.charSite or inputs), "character", "char:" .. inputs.charKind
	elseif inputs.autoStyle then
		id, why = SITE.pick(inputs, seed)
		source = "site"
	else
		id, source = M.pickProfile(inputs), "region"
	end
	local p = M.profile(id)
	p.styleSource, p.styleWhy = source, why or source
	p.region, p.climate, p.era, p.tier, p.year = inputs.region, inputs.climate, inputs.era, inputs.tier, inputs.year
	p.country = inputs.country     -- (the name list's country: France's roundabouts, ot_ring.rate, 2026-10-14 §56)
	p.newTemplates = inputs.newTemplates
	p.seed = seed
	p.drawV = drawV
	-- (organic ring geometry, 2026-10-14 §56: new towns and towns framed with it)
	if M.ORGANIC_RINGS and (not (inputs.frame and inputs.frame.axis) or inputs.frame.organicRings) then p.ringWobble = true end
	p.radius = inputs.radius or 0
	p.industry = inputs.industry   -- ot_industry (away from industries; the driver refreshes it per plan)
	p.roads = inputs.roads         -- ot_roads: the country roads around the town (M2 road motifs), or nil
	p.bounds = inputs.bounds       -- ot_map: the map's bounding box (no plan piece within MARGIN of it), or nil
	p.character = inputs.character -- ot_map: the town's seclusion rank (character towns, ot_form CHARACTER), or nil
	p.railStations = inputs.railStations -- ot_engine.railStations near the town (M3 station quarter; the driver refreshes it)

	-- climate / region
	if inputs.climate == "subarctic" then
		p.block.len, p.block.depth = p.block.len * 1.2, p.block.depth * 1.2
	elseif inputs.climate == "tropical" then
		-- (wider plots: tropical towns are looser and lower, NEXT_PHASE_BRIEF 48 item 3; the style / form bias: ot_site
		-- CLIMATE, ot_form CLIMATE. Kept at the subarctic's 1.2 at most: the block limits of the shapes stay met)
		p.block.len, p.block.depth = p.block.len * M.BLOCK_TROPICAL, p.block.depth * M.BLOCK_TROPICAL
	end
	if inputs.region == "OCEANIA" then p.block.depth = p.block.depth * 1.2 end
	-- organic <-> gridded (ot_grid): a fresh town's organic plan straighter in later years / with the Town layout
	-- setting; a town with a saved frame keeps its core plan (its spokes come from the jitter), only its outer zone
	-- (below) follows the years
	p.gridBias = inputs.gridBias
	-- (a look zone, 2026-10-14 §57: showcase run 2026-10-14_2237's EU organic town (a 2060 look of 0.59 on the whole
	-- plan) grew a regular rectangle into its east side. An organic town with the organic ring geometry and no outer zone
	-- of its own keeps at most LOOK_CORE in its core; the rest of its look (at most LOOK_ZONE_MAX) comes as an outer zone
	-- of its own style from LOOK_FROM m, blended in over ZONE_BLEND: the town gets more regular outward, no seam)
	-- (a framed town: its saved core look (gl), the zone from this decade's look, as any outer zone)
	local lookZone = nil
	local framed = inputs.frame and inputs.frame.axis
	if inputs.gridBias and M.LOOK_ZONE and p.ringWobble and p.grower == "organic" and (inputs.gridBias.look or 0) > M.LOOK_CORE then
		lookZone = math.min(inputs.gridBias.look, M.LOOK_ZONE_MAX)
	end
	if lookZone and not framed then
		GR.applyLook(p, M.LOOK_CORE)
	elseif inputs.gridBias and not framed then GR.applyLook(p, inputs.gridBias.look)
	elseif inputs.frame and inputs.frame.gridLook then GR.applyLook(p, inputs.frame.gridLook) end   -- (the saved look, ot_saved gl)

	-- era: the late street hierarchy (lateTemplates below) also spaces the arterial / collector lines
	local late = p.lateTemplates and inputs.newTemplates and (inputs.era or 0) >= M.LATE_ERA
	if late and p.late then
		for k, v in pairs(p.late) do p[k] = copy(v) end
	end

	-- size: small towns get fewer spokes and no arterial lines yet (only the main axes)
	if p.radial and inputs.tier <= 1 then p.radial.spokes = math.min(p.radial.spokes, 4) end
	if inputs.tier <= 1 and p.arterialEvery > 0 then
		p.arterialEvery = p.arterialEvery * 2
		if p.collectorEvery then p.collectorEvery = p.collectorEvery * 2 end
	end

	-- era: outer zone (suburbs, 19th-c. extension; a forced style has none unless keepOuter); templates
	if not inputs.forceStyle or inputs.keepOuter then p.outer = M.pickOuter(id, inputs) end
	if lookZone then
		if p.outer == nil then
			p.outer = { id = id, from = M.LOOK_FROM, look = lookZone, lookZone = true }
		elseif p.outer.look == nil or p.outer.look < lookZone then
			-- (an outer zone of its own: it takes the look; the core keeps LOOK_CORE)
			p.outer.look = lookZone
		end
	end
	if late then
		p.templates = copy(p.lateTemplates)
		p.hierarchy = "late"
	else
		p.hierarchy = "plain"
	end
	p.templatePaths = {}
	for _, c in ipairs(M.CLASSES) do p.templatePaths[c] = M.templatePath(p.templates[c], inputs.newTemplates) end
	-- deep forest towns (ot_forest.deepStyle, 2026-10-14; the driver decides, saved on the frame `fd`): winding, smaller
	-- blocks, organic all the way out, before the shape / form / greens / motifs read the blocks
	if inputs.deep then FO.deepStyle(p) end
	-- strong characters (ot_character, 2026-10-14): the kind's planner knobs, before the shape / form / greens read them
	if inputs.charKind then
		CH.apply(p, inputs.charKind, { terrain = inputs.terrain, site = inputs.charSite, pos = inputs.pos,
			framed = inputs.frame ~= nil and inputs.frame.axis ~= nil })
		-- (a kind may change the templates: their paths again)
		for _, c in ipairs(M.CLASSES) do p.templatePaths[c] = M.templatePath(p.templates[c], inputs.newTemplates) end
	end

	-- terrain
	local t = inputs.terrain
	if t and t.water then p.waterfront = true end

	-- axis: shore/bank, station, or a seeded angle within angleRange; an existing street grid wins (never
	-- rotate a town), turned by a multiple of 90 deg to the candidate nearest that fresh axis so a grid we grew
	-- keeps its long blocks along the same direction
	local axis
	if t and t.water and p.grower == "grid" then
		axis = t.water.axis
		p.axisSource = "water"
	elseif inputs.stations[1] and p.stationPull >= 0.5 then
		local s = inputs.stations[1]
		axis = G.heading(inputs.pos[1], inputs.pos[2], s[1] or s.x, s[2] or s.y)
		p.axisSource = "station"
	else
		axis = math.rad((rng.unit(p.seed, "axis") - 0.5) * p.angleRange)
		p.axisSource = "seed"
	end
	-- (a strong character's own axis, ot_character: the company town's main street to the works)
	if p.charAxis then
		axis = p.charAxis
		p.axisSource = "character"
	end
	if inputs.frame and inputs.frame.axis then
		-- a frame saved when we first built in this town (ot_saved): the plan must not turn or move later
		axis = inputs.frame.axis
		p.axisSource = "saved"
		if inputs.frame.origin then p.frame = { origin = { inputs.frame.origin[1], inputs.frame.origin[2] } } end
	elseif inputs.axis and (inputs.axis.strength or 0) >= 0.35 then
		local base = inputs.axis.angle
		local best, bd = base, math.huge
		for k = -2, 2 do
			local cand = base + k * math.pi / 2
			local d = G.angleDiff(cand, axis)
			if d < bd - 1e-9 then best, bd = cand, d end
		end
		axis = G.wrap(best)
		p.axisSource = "streets"
	end
	if t and t.water then
		p.waterFrontAxis = t.water.axis
		-- irregular growth leans this way (not toward a pond, 2026-10-12)
		if t.water.kind == "coast" and t.water.body ~= "pond" then p.waterDir = t.water.dir end
	end
	p.axis = G.z0(axis)

	-- centre: a small new MED hill town moves its plan centre to the nearby hilltop
	local cx, cy = inputs.pos[1], inputs.pos[2]
	if id == "MED_HILL" and t and t.high and (inputs.radius or 0) < 150 and t.meanSlope > 0.03 then
		if G.dist(cx, cy, t.high[1], t.high[2]) < 300 then cx, cy = t.high[1], t.high[2] end
	end
	-- (a strong character's centre, ot_character: the hilltop town's summit; a fresh plan only)
	if p.charCentre and not (inputs.frame and inputs.frame.axis) then cx, cy = p.charCentre[1], p.charCentre[2] end
	p.centre = { cx, cy }
	p.stations = inputs.stations
	-- town shape (ot_shape): where the town grows, independent of the street style; a fresh plan turns its axis
	-- to the shape's (spokes / lines along the corridors)
	p.shape = SH.pick(inputs, p)
	-- town form (ot_form, Showcase v8 round): the same style spreads differently per town (clustered, radiating,
	-- sprawling, linear, wide, fingers): from the dev tools, the saved frame, the site-picked shape or a seeded draw
	local okF, feats = pcall(SITE.features, inputs.terrain, inputs.wide, inputs.forestShare)
	local form = FM.pick(inputs, p, p.shape, okF and feats or nil)
	p.squeeze = okF and feats and feats.squeeze or nil
	if form then
		local want = FM.shapeFor(form, p)
		local scaled = form.def.block ~= nil and form.def.block ~= 1
		if scaled then FM.applyBlock(form, p) end
		if scaled or (want and want ~= p.shape.id and not (inputs.frame and inputs.frame.shape)) then
			p.shape = SH.pick(inputs, p, want ~= p.shape.id and want or nil)
		end
		FM.apply(form, p)
	end
	p.greens = M.greenReserves(p, form and FM.greens(form, M.GREEN_STYLES[p.id]) or nil)
	-- waterfront (shore towns, 2026-10-12): a new town (one with a form; older saved frames have none and grow as
	-- before) on a sea / lake shore within WATERFRONT_DIST gets streets near the water first (waterPremium, ot_select
	-- cost) and a waterfront street along the shore's curve (shoreFront, ot_shore); a shore town also the row of small
	-- blocks behind it and the stronger premium
	-- (a coastal hugger, 2026-10-14: always its waterfront street)
	if form and t and SH.shoreUsable(t) and ((t.water.distance or math.huge) <= M.WATERFRONT_DIST
		or ((form.coastal or form.def.charShore) and p.shape and p.shape.id == "shore")) then
		local isShore = p.shape ~= nil and p.shape.id == "shore"
		local sd = isShore and p.shape.shore or SH.shoreData(t, p.centre, p.block.depth, okF and feats and feats.island)
		if sd then
			local W = isShore and M.WATERFRONT.shore or M.WATERFRONT.coast
			p.waterPremium = { gain = W.gain, band = W.band, shore = sd }
			-- (the promenade: a main street, built medium; late hierarchies map main to large, so medium there)
			p.shoreFront = { sd = sd, row = isShore, class = (p.templates.main == "large") and "medium" or "main" }
		end
	end
	-- motifs (ot_motif, M0 2026-10-13): the saved / forced / drawn ones (the derived looks, crescents and the hill road,
	-- come from the fields above), then their steering and reservations
	-- (the town's river bridge, ot_bridge: built when the frame says so (`br`); the driver adds this session's build with
	-- its geometry, ot_driver.bridgeRefresh. M4 bridgehead quarter)
	if inputs.frame and inputs.frame.bridge then p.bridge = { built = true, src = "frame" } end
	p.motifs = MO.pick({ style = p, inputs = inputs, feats = okF and feats or nil, terrain = t, year = inputs.year,
		era = inputs.era, tier = inputs.tier, cap = inputs.capacity, form = form and form.id or nil,
		shape = p.shape and p.shape.id or nil, character = form and form.character or nil })
	MO.applyStyle(p, { greenReserves = M.greenReserves, terrain = t, feats = okF and feats or nil, frame = inputs.frame })
	-- strong characters: the kind's last knobs (premiums), and a densify town's core (ot_character, 2026-10-14)
	if inputs.charKind then CH.post(p, inputs.charKind, { terrain = t, site = inputs.charSite }) end
	if inputs.densify then CH.densifyStyle(p) end
	return p
end

M.WATERFRONT_DIST = 600   -- m: the water at most this far from the centre (400 until the 2026-10-13 final-test round;
                          -- ot_site SHORE_DIST 600 for the shore towns)
M.WATERFRONT = { shore = { gain = 0.35, band = 250 }, coast = { gain = 0.2, band = 250 } }

-- Green reserves (ot_select.inGreen; user 2026-10-12 on the Density: control twin): GREEN_COUNT discs of
-- GREEN_R x block (clamped to GREEN_MIN..GREEN_MAX m) at GREEN_FROM..GREEN_TO blocks from the plan centre, seeded,
-- off the shape's arm corridors (the arms run on). Organic growers and the NA suburb (curving streets around open
-- land); strict grids (NA grid, ensanche, superblock) and JP dense fill every block. A metropolis gets parks
-- instead (ot_metro.apply). Not saved: derived from the seed and the plan centre each session.
M.GREEN_STYLES = { EU_ORGANIC = 3, EU_EXTENSION = 2, MED_HILL = 2, NORDIC = 4, NA_SUBURB = 3 }
M.GREEN_R = { 1.2, 2.0 }
M.GREEN_MIN, M.GREEN_MAX = 70, 160
M.GREEN_FROM, M.GREEN_TO = 2.5, 6
-- the first style.crescents reserves are crescent meadows (entry [4] = true): radius CRESCENT_R m (the user's EU
-- organic example: a meadow ~150 x 200 m wrapped by an arc of ~150-250 m radius)
M.CRESCENT_R = { 85, 130 }

--- Reserves for a resolved style p: { {x, y, r} } (n = count, default by style).
function M.greenReserves(p, n)
	n = n or M.GREEN_STYLES[p.id] or 0
	local out = {}
	if n <= 0 then return out end
	local blk = math.max(p.block.len, p.block.depth)
	local nc = math.min(n, p.crescents or 0)
	for k = 1, n do
		local r = G.clamp(blk * (M.GREEN_R[1] + (M.GREEN_R[2] - M.GREEN_R[1]) * rng.unit(p.seed or 1, "greenR", k)),
			M.GREEN_MIN, M.GREEN_MAX)
		-- (a crescent's meadow: CRESCENT_R, the arc around it a long sweep, ot_crescent)
		if k <= nc then r = M.CRESCENT_R[1] + (M.CRESCENT_R[2] - M.CRESCENT_R[1]) * rng.unit(p.seed or 1, "crescentR", k) end
		-- (beyond the town's current extent: inside it the streets are there already; a later session, with a larger
		-- town, places them farther out, so the meadows come in rings as the town grows)
		local d = math.max(blk * (M.GREEN_FROM + (M.GREEN_TO - M.GREEN_FROM) * rng.unit(p.seed or 1, "greenD", k)), r + 2 * blk,
			(p.radius or 0) + r + blk)
		local a = rng.unit(p.seed or 1, "greenA", k) * 2 * math.pi
		for _ = 1, 12 do
			local x, y = p.centre[1] + math.cos(a) * d, p.centre[2] + math.sin(a) * d
			-- (v9: never overlapping another reserve, else a crescent's arc ran inside the other meadow and was left out)
			local clear = true
			for _, o in ipairs(out) do
				if G.dist(o[1], o[2], x, y) < o[3] + r + blk then clear = false break end
			end
			if clear and not (p.shape and SH.inArm(p.shape, x, y)) then
				out[#out + 1] = { G.round(x, 1), G.round(y, 1), G.round(r, 1), k <= nc or nil }
				break
			end
			a = a + math.pi / 6
		end
	end
	return out
end

--- The profile that applies at distance `d` from the centre (the outer profile beyond its radius), with the
--- resolved fields (axis, templates, seed ...) carried over.
function M.zone(p, d)
	if p.outer == nil then return p end
	-- (organic ring geometry, 2026-10-14 §56: an organic town's outer zone blends in over ZONE_BLEND x ringEvery beyond
	-- `from` in ZONE_BLEND_STEPS steps (gridness, jitter, curve, blocks), so its seam is no cut-off grid patch)
	local blend = (p.ringWobble and p.grower == "organic") and M.ZONE_BLEND * ((p.radial and p.radial.ringEvery) or 250) or 0
	if d < p.outer.from then return p end
	if blend > 0 and d < p.outer.from + blend then
		local o = M.zone(p, p.outer.from + blend)
		local k = math.floor((d - p.outer.from) / blend * (M.ZONE_BLEND_STEPS + 1)) + 1
		if k > M.ZONE_BLEND_STEPS then return o end
		-- (cached per outer profile: a reset _outerCache makes a new one)
		if p._blendFor ~= o then p._blendCache, p._blendFor = {}, o end
		if p._blendCache[k] == nil then
			local f = k / (M.ZONE_BLEND_STEPS + 1)
			local b = {}
			for key, v in pairs(o) do b[key] = v end
			local function lerp(a, c) if type(a) ~= "number" or type(c) ~= "number" then return c end return a + (c - a) * f end
			b.gridness, b.jitter, b.curve = lerp(p.gridness, o.gridness), lerp(p.jitter, o.jitter), lerp(p.curve, o.curve)
			b.block = { len = lerp(p.block.len, o.block.len), depth = lerp(p.block.depth, o.block.depth),
				sd = lerp(p.block.sd, o.block.sd) }
			b.blendStep = k
			p._blendCache[k] = b
		end
		return p._blendCache[k]
	end
	if p._outerCache == nil then
		local o = M.profile(p.outer.id)
		for _, k in ipairs({ "region", "climate", "era", "tier", "year", "newTemplates", "seed", "radius", "axis",
			"axisSource", "centre", "stations", "templatePaths", "waterFrontAxis", "waterDir", "frame", "shape",
			"waterPremium", "shoreFront", "industry", "bounds", "character", "gridBias", "roads", "railStations", "forest",
			"charKind", "rings", "charBridges", "densify", "country", "ringWobble" }) do
			o[k] = p[k]
		end
		o.waterfront = p.waterfront
		-- (organic <-> gridded: the outer zone's own grid look, ot_grid)
		if p.outer.look then GR.applyLook(o, p.outer.look) end
		p._outerCache = o
	end
	return p._outerCache
end

return M
