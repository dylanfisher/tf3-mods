-- Organic Towns: site classifier -> street style per town (pure). NEXT_PHASE_BRIEF 8 (user, 2026-10-11): "one map
-- should have various styles, not 'European map = all European dense': big flat open areas -> sprawling
-- (superblock, suburb, wide grids); coastal or mountain towns -> denser and spidery (hug coasts, wind between
-- valleys)". The region only biases the odds; the era gates the modern styles.
--
-- Features (0..1) from the town's terrain stats (ot_terrain.stats, 600 m disc) and the wide survey
-- (ot_terrain.wide, 2 km rays):
--   open    flat land with little water around: low local slope, low height spread over 2 km, mostly dry
--   rough   hills / mountains: local slope or a wide height spread
--   coast   sea or a lake within ~700 m (or much water in the wide survey; a pond doesn't count)
--   river   a river through the town disc
--   valley  a valley or crest axis (ot_terrain.dirRelief) on sloped ground
-- weight(style) = region bias x era gate x exp(sum_k AFFINITY[style][k] x feature_k); the pick is a weighted
-- draw from the town seed, so towns of one map differ and a town keeps its style (it is also saved with the
-- plan frame at the first build, ot_saved).

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local GR = ug_require "square_organic_towns::/organic_towns/ot_grid.lua"
local DV = ug_require "square_organic_towns::/organic_towns/ot_diverse.lua"

local M = {}

M.FEATURES = { "open", "rough", "coast", "river", "valley" }

-- log-affinity of each style for each site feature (sprawl on open plains; dense, winding styles on coasts,
-- hills and valleys)
M.AFFINITY = {
	NA_GRID = { open = 0.5, rough = -1.0, coast = -0.3, river = 0, valley = -0.8 },
	NA_SUBURB = { open = 0.9, rough = -0.8, coast = -0.5, river = 0, valley = -0.8 },
	SUPERBLOCK = { open = 1.1, rough = -2.0, coast = -1.0, river = -0.3, valley = -1.5 },
	MED_ENSANCHE = { open = 0.5, rough = -1.5, coast = -0.2, river = 0, valley = -1.2 },
	EU_EXTENSION = { open = 0.4, rough = -0.5, coast = -0.2, river = 0.3, valley = -0.4 },
	EU_ORGANIC = { open = -0.2, rough = 0.4, coast = 0.4, river = 0.4, valley = 0.4 },
	MED_HILL = { open = -1.0, rough = 1.2, coast = 0.6, river = 0, valley = 0.8 },
	JP_DENSE = { open = -0.2, rough = 0.5, coast = 0.5, river = 0.2, valley = 0.6 },
	NORDIC = { open = -0.4, rough = 0.6, coast = 0.6, river = 0.2, valley = 0.4 },
}
-- feature pairs that only count together (2026-10-13): Nordic = rough AND coast (fjords, skerry coasts); a hilly inland
-- town or a flat coast alone no longer pulls it (the English test map had 6 of 14 styled towns Nordic: hills and
-- valleys everywhere)
M.PAIRS = { NORDIC = { { "rough", "coast", 0.9 } } }

-- region bias (the map's name set): the home style dominates, the others stay possible
M.REGION = {
	US = { NA_GRID = 4, NA_SUBURB = 2, SUPERBLOCK = 0.4, EU_EXTENSION = 0.3, NORDIC = 0.2, EU_ORGANIC = 0.2,
		MED_HILL = 0.15, MED_ENSANCHE = 0.15 },
	OCEANIA = { NA_GRID = 4, NA_SUBURB = 2.5, SUPERBLOCK = 0.3, EU_EXTENSION = 0.4, NORDIC = 0.2, EU_ORGANIC = 0.3,
		MED_HILL = 0.2 },
	-- (2026-10-13: ensanche / NA grid up from 0.3 / 0.4, the planned grid towns of a European map; ot_grid scales them
	-- with the era and the Town layout setting)
	EU = { EU_ORGANIC = 4, EU_EXTENSION = 2.5, NA_SUBURB = 1, SUPERBLOCK = 0.7, NORDIC = 0.25, MED_HILL = 0.6,
		NA_GRID = 0.5, MED_ENSANCHE = 0.6 },
	MED = { MED_HILL = 4, MED_ENSANCHE = 2, EU_ORGANIC = 1, EU_EXTENSION = 0.8, NA_SUBURB = 0.5, SUPERBLOCK = 0.4,
		NA_GRID = 0.2 },
	NORDIC = { NORDIC = 4, EU_ORGANIC = 1, EU_EXTENSION = 1, NA_SUBURB = 0.8, SUPERBLOCK = 0.4, NA_GRID = 0.3 },
	RU = { SUPERBLOCK = 3, EU_ORGANIC = 2.5, EU_EXTENSION = 1.5, NORDIC = 0.5, NA_SUBURB = 0.4, NA_GRID = 0.3 },
	JP = { JP_DENSE = 4, NA_SUBURB = 0.5, SUPERBLOCK = 0.6, EU_EXTENSION = 0.3, NA_GRID = 0.3 },
	EAST_ASIA = { JP_DENSE = 3, SUPERBLOCK = 2.5, NA_GRID = 0.5, NA_SUBURB = 0.4, EU_ORGANIC = 0.3 },
	-- (2026-10-14, NEXT_PHASE_BRIEF 48 item 3: the pan-Asian list, Karachi to Seoul and the Middle East. As EAST_ASIA 14
	-- of 16 towns came out JP_DENSE (the superblock is gated to 1950, so JP_DENSE was alone before). A broad mix: old
	-- organic cores and bazaar towns, dense East Asian quarters, the dry belt's hill towns, colonial and planned grids,
	-- superblocks from 1950; no home style over the others)
	ASIA = { EU_ORGANIC = 2, JP_DENSE = 1.6, MED_HILL = 1.4, SUPERBLOCK = 1.6, NA_GRID = 1.1, EU_EXTENSION = 1.1,
		MED_ENSANCHE = 0.9, NA_SUBURB = 0.6, NORDIC = 0.1 },
	-- (2026-10-14, NEXT_PHASE_BRIEF 55: "Mixed" in the Town style setting only: every regional style alike, the site
	-- and the climate decide)
	MIXED = { NA_GRID = 1, NA_SUBURB = 1, SUPERBLOCK = 1, MED_ENSANCHE = 1, EU_EXTENSION = 1, EU_ORGANIC = 1,
		MED_HILL = 1, JP_DENSE = 1, NORDIC = 1 },
}

-- era gates: styles of a later age don't appear before it (years: superblocks and car suburbs from 1950, the ensanche
-- from 1920, the 19th-century extension from 1900, i.e. always: its weight follows ot_grid's era trend). Era range 1900+
-- (2026-10-13: TF3 starts in 1900 at the earliest; the ensanche (1860) and extension (1850) gates never closed, so the
-- early game had the ensanche grid; now the first two decades stay organic)
M.FROM_YEAR = { SUPERBLOCK = 1950, NA_SUBURB = 1950, MED_ENSANCHE = 1920, EU_EXTENSION = 1900 }
-- climate bias (x the region's): dry: dense hill towns and planned grids, no fjord towns; subarctic: Nordic, few
-- Mediterranean hill towns. Tropical (2026-10-14, NEXT_PHASE_BRIEF 48 item 3; was none): looser and lower towns on
-- wider plots, spread along the coasts and roads: suburbs, the extension ring and organic towns up, the dense compact
-- styles (JP dense, Mediterranean hill, Nordic, superblock) down. The plots: ot_style's tropical block x BLOCK_TROPICAL;
-- the spread: ot_form CLIMATE (sprawling / linear / shore forms).
M.CLIMATE = {
	dry = { MED_HILL = 2, MED_ENSANCHE = 1.5, NORDIC = 0.3 },
	subarctic = { NORDIC = 2, MED_HILL = 0.5, MED_ENSANCHE = 0.7 },
	tropical = { NA_SUBURB = 1.8, EU_EXTENSION = 1.5, EU_ORGANIC = 1.2, NA_GRID = 1.1, JP_DENSE = 0.6, MED_HILL = 0.6,
		SUPERBLOCK = 0.7, NORDIC = 0.3 },
}

M.GRID_ROUGH = 0.8      -- ot_grid's boost of the gridded styles x (1 - this x max(rough, coast, valley))
M.GRID_HOME = 2         -- ... none on a map whose region weighs a gridded style this much (US / Oceania)
M.SEA_WIDE = 0.3        -- an open shore (traced beyond its budget) is the sea when this share of the wide survey is wet
M.ISLAND_DIRS = 11      -- water on at least this many of the wide survey's 16 rays ...
M.ISLAND_WET = 0.35     -- ... and this share wet: an island (or a narrow peninsula: both ring their coast)
M.SHORE_MIN_LEN = 600   -- m of traced shoreline a shore town needs
M.SHORE_DIST = 600      -- m: the water at most this far from the centre (450 until the 2026-10-13 final test: three of
                        -- eight sea / lake towns sat 575 m from their shore and grew onto it as normal towns)

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

--- Site features from terrain stats and the wide survey (either may be nil). Returns { open, rough, coast,
--- river, valley, kind = "plain"|"coast"|"valley"|"ridge"|"river"|"hills"|"mixed", body = "sea"|"lake"|"pond"|
--- "river"|nil, island = bool, shore = 0..1 (a shore the town can follow), shoreLen = m traced }.
function M.features(stats, wide, forestShare)
	stats = stats or {}
	local slope = stats.meanSlope or 0
	local sd = wide and wide.sd or 0
	local wetLocal = stats.waterFraction or 0
	local wetWide = wide and wide.water or 0
	local flat = clamp(1 - (slope - 0.015) / 0.06, 0, 1) * clamp(1 - (sd - 6) / 30, 0, 1)
	local dry = 1 - math.max(wetLocal, wetWide)
	local f = {}
	f.open = flat * clamp((dry - 0.55) / 0.4, 0, 1)
	-- rough: the town's own slope, or the wide height spread damped on a flat town floor (2026-10-13: on a hilly map the
	-- 2 km spread saturated every town, so a flat river-valley town read as hills: rough 1.00 everywhere)
	local slopeR = clamp((slope - 0.03) / 0.08, 0, 1)
	f.rough = math.max(slopeR, clamp((sd - 10) / 40, 0, 1) * (0.5 + 0.5 * slopeR))
	f.floor = clamp(1 - (slope - 0.015) / 0.06, 0, 1)   -- a flat town floor (local slope only; ot_metro valley floor)
	local w = stats.water
	-- water body (shore towns, 2026-10-12): river, lake / pond (a closed shore around water, ot_terrain.shoreline),
	-- sea or a large lake (the shore runs on: told apart by the wide survey's water share, SEA_WIDE). A pond is no
	-- coast; an island (a closed shore around land, or water on most of the wide survey's rays) rings its coast.
	f.body = w and w.body or nil
	if f.body == "open" then f.body = wetWide >= M.SEA_WIDE and "sea" or "lake" end
	local sh = stats.shore
	f.island = (sh ~= nil and sh.island == true) or ((wide and wide.waterDirs or 0) >= M.ISLAND_DIRS and wetWide >= M.ISLAND_WET)
	f.coast = 0
	if w and w.kind == "coast" and f.body ~= "pond" then f.coast = clamp(1.2 - (w.distance or 600) / 600, 0, 1) end
	if wetWide >= 0.2 and (w == nil or w.kind ~= "river") then f.coast = math.max(f.coast, clamp(wetWide * 2, 0, 0.6)) end
	-- shore: how strongly the town sits on a sea / lake shore it could follow (a traced shoreline of SHORE_MIN_LEN, the
	-- water within SHORE_DIST of the centre); 0 elsewhere. ot_form draws the shore form from it.
	f.shore, f.shoreLen = 0, sh and sh.L or 0
	if sh and w and w.kind == "coast" and (f.body == "sea" or f.body == "lake") and sh.L >= M.SHORE_MIN_LEN
		and (w.distance or math.huge) <= M.SHORE_DIST then
		f.shore = clamp(1.25 - (w.distance or 0) / 400, 0.2, 1)
	end
	f.river = (w and w.kind == "river") and 1 or 0
	local dr = stats.dirRelief
	f.valley = (dr and (dr.valley or dr.ridge) and slope > 0.02) and 1 or 0
	if f.valley > 0 then f.kind = dr.ridge and "ridge" or "valley"
	elseif f.coast >= 0.5 then f.kind = "coast"
	elseif f.river > 0 then f.kind = "river"
	elseif f.rough >= 0.5 then f.kind = "hills"
	elseif f.open >= 0.6 then f.kind = "plain"
	else f.kind = "mixed" end
	-- squeeze (2026-10-14, user: "I like the condensed cities and pushing between canyon and mountains", High Wycombe's
	-- narrow shape between forests): how hemmed in the town is by steep slopes, water and forest (0..1); ot_form leans
	-- such towns a little toward compact forms (SQUEEZE_K). Hills, canyons and valleys keep their own shapes.
	local steep = clamp(((stats.p95Slope or 0) - M.SQUEEZE_STEEP) / 0.15, 0, 1)
	local wetS = clamp(math.max(wetLocal, wetWide) * 1.6, 0, 1)
	local forest = clamp(((tonumber(forestShare) or 0) - 0.15) / 0.5, 0, 1)
	-- (squeezed BETWEEN things: one constraint alone counts half, so a town in open forest stays a forest town)
	local n = (steep > 0 and 1 or 0) + (wetS > 0 and 1 or 0) + (forest > 0 and 1 or 0) + (f.valley > 0 and 1 or 0)
	f.squeeze = clamp(0.5 * steep + 0.4 * wetS + 0.3 * forest + 0.2 * f.valley, 0, 1) * (n >= 2 and 1 or 0.5)
	return f
end
M.SQUEEZE_STEEP = 0.10

--- Style weights for a town: list of { id, w } (descending, w > 0). inputs: ot_inputs.build result (region,
--- climate, year); f: M.features result.
function M.weights(inputs, f)
	local bias = M.REGION[inputs.region] or M.REGION.EU
	local clim = M.CLIMATE[inputs.climate] or {}
	local out = {}
	-- (a region whose home style is a grid, US / Oceania: the map is gridded already, no grid boost at all)
	local gridHome = false
	for id, w in pairs(bias) do if w >= M.GRID_HOME and GR.GROUP[id] == "GRIDDED" then gridHome = true end end
	for id, aff in pairs(M.AFFINITY) do
		local b = (bias[id] or 0.1) * (clim[id] or 1)
		if (inputs.year or 1960) < (M.FROM_YEAR[id] or -math.huge) then b = 0 end
		-- organic <-> gridded (ot_grid): the gridded styles weigh more in later years and with the Town layout setting
		-- (a boost counts less on rough ground: grids and superblocks stay a thing of open land, GRID_ROUGH)
		-- (... and on coasts / in valleys, and not for the region's home styles: a US map is gridded already)
		local gf = GR.factor(inputs.gridBias, id)
		-- (on a grid-home map the organic styles shrink instead: 1 / sqrt(the gridded boost))
		if gridHome and GR.GROUP[id] == nil and inputs.gridBias and inputs.gridBias.gridded > 1 then
			b = b / math.sqrt(inputs.gridBias.gridded)
		end
		if gf > 1 then
			if gridHome then gf = 1 end
			local tight = math.max(f.rough or 0, f.coast or 0, (f.valley or 0) > 0 and 1 or 0)
			gf = 1 + (gf - 1) * (1 - M.GRID_ROUGH * tight)
		end
		b = b * gf
		if b > 0 then
			local e = 0
			for _, k in ipairs(M.FEATURES) do e = e + (aff[k] or 0) * (f[k] or 0) end
			for _, pr in ipairs(M.PAIRS[id] or {}) do e = e + pr[3] * (f[pr[1]] or 0) * (f[pr[2]] or 0) end
			out[#out + 1] = { id = id, w = b * math.exp(e) }
		end
	end
	table.sort(out, function(a, b)
		if a.w ~= b.w then return a.w > b.w end
		return a.id < b.id
	end)
	return out
end

--- The style of a town from its site: id, why ("plain:open=0.86,rough=0.00 EU NA_SUBURB=2.4/EU_EXTENSION=3.7/..."),
--- weights, features. seed: the town seed (ot_rng). (weights x ot_grid's factor: inputs.gridBias)
function M.pick(inputs, seed)
	local f = M.features(inputs.terrain, inputs.wide)
	local ws = M.weights(inputs, f)
	-- neighbour diversity (ot_diverse): a style the towns nearby use weighs a little less (weak: forms carry it)
	local dv = DV.factors(inputs.nbrPicks, "style")
	if next(dv) ~= nil then
		local used = {}
		for _, x in ipairs(ws) do
			if dv[x.id] then
				x.w = x.w * dv[x.id]
				used[x.id] = dv[x.id]
			end
		end
		DV.note(inputs, "style", used)
		table.sort(ws, function(a, b)
			if a.w ~= b.w then return a.w > b.w end
			return a.id < b.id
		end)
	end
	local total = 0
	for _, x in ipairs(ws) do total = total + x.w end
	-- (§68: stays on rng.unit, the anchor of its 9-letter group: satellite and shoreForm draw with rng.decide)
	local r = rng.unit(seed or 1, "siteStyle") * total
	local id = ws[#ws] and ws[#ws].id or "EU_ORGANIC"
	for _, x in ipairs(ws) do
		r = r - x.w
		if r <= 0 then id = x.id break end
	end
	local top = {}
	for i = 1, math.min(3, #ws) do top[i] = string.format("%s=%.1f", ws[i].id, ws[i].w) end
	local why = string.format("%s:open=%.2f,rough=%.2f,coast=%.2f,river=%d,valley=%d,water=%s,island=%d|%s|%s", f.kind,
		f.open, f.rough, f.coast, f.river, f.valley, f.body or "-", f.island and 1 or 0, tostring(inputs.region),
		table.concat(top, "/"))
	return id, why, ws, f
end

return M
