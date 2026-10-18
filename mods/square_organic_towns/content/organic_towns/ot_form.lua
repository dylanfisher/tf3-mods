-- Organic Towns: town form (pure). Showcase v8 round (2026-10-12, NEXT_PHASE_BRIEF 15).
--
-- User (Showcase v7): "It would be great if these different variations could be incorporated into each style, e.g.
-- JP dense clustered and radiating from centre vs JP dense sprawling, etc." So a town's look has two axes:
--   CHARACTER  the style's street pattern (ot_style: grid, organic rings, superblock lattice, ...)
--   FORM       how the town spreads (this module): clustered, radiating, sprawling, linear, wide, fingers
-- The same style varies between towns. A form sets the town's outline (an ot_shape archetype) and how loosely it
-- grows (block size, how far the growth front may leapfrog, the seeded sector preference, meadows left open):
--   clustered  compact and dense: round (compact shape), slightly smaller blocks, a tight front, no meadows
--   radiating  a star from the centre: arms on the spokes (organic: fingers, grids: cross) with a medium reach,
--              main streets lead (ribbon)
--   sprawling  low density, loose: larger blocks, a far front with hotspots (leapfrog patches), meadows between,
--              the style's mild outline
--   linear     long and narrow: linear shape, strong reach (arms fill before they extend, ot_select)
--   wide       a broad oval: lens shape
--   fingers    corridors with green wedges: fingers shape, strong reach
--   shore      (2026-10-12) a strip along the sea / lake shore, following its curve: shore shape (ot_shape, the traced
--              shoreline), strong reach, a waterfront street with a row of small blocks behind it (ot_shore), limited
--              depth inland, streets near the water first (style.waterPremium)
--
-- Pick (FM.pick): the dev tools force one; a saved plan frame keeps the town's (frame field `f`, older frames have
-- none: no form, the town keeps growing exactly as before); a shape that came from the site or the roads (valley,
-- coast, ridge, river, road exits, a close neighbour) decides the form (FROM_SHAPE); else a seeded draw from the
-- style's weights x the site (open plains favour sprawling, rough / coast / valley sites clustered and linear).
-- Deterministic per town (seed, site), nothing new is needed in the save before the first build.

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local DV = ug_require "square_organic_towns::/organic_towns/ot_diverse.lua"

local FM = {}

FM.ENABLED = true   -- (the offline tests of the other rules turn it off: their baselines were measured without forms)

FM.IDS = { "clustered", "radiating", "sprawling", "linear", "wide", "fingers", "shore" }   -- (append only: saved index)
FM.INDEX = {}
for i, id in ipairs(FM.IDS) do FM.INDEX[id] = i end

-- shape = ot_shape id (organicShape: organic growers; nil: keep the shape the style's weights drew), reach =
-- shape.reach (1 strong, < 1 mild), block = x block size, front = x the selector's front reach, sector = x the
-- seeded sector preference amplitude, hotspots / pull = added hotspots, greens = meadows (nil: the style's),
-- ribbon = x main-street corridor gain
FM.DEF = {
	-- (2026-10-13, real map round 3: "most towns look the same", forms made more distinct: clustered tighter, sprawling
	-- looser with more leapfrog patches, radiating stronger ribbons, linear / fingers longer and narrower arms)
	-- (2026-10-13 round 5, "not just radiating from the centre": even a clustered town puts out one lobe along its
	-- main road or the hillside, ot_select LOBE_R; sprawling ones up to four, along every road out)
	clustered = { shape = "compact", block = 0.9, front = 0.6, sector = 0.4, greens = 0, hotspots = 1, pull = 0.3 },
	radiating = { shape = "cross", reach = 1, ribbon = 1.8 },
	sprawling = { block = 1.35, front = 1.9, sector = 1.6, hotspots = 4, pull = 0.65, greensAdd = 2, greensMin = 3 },
	linear = { shape = "linear", reach = 1, kaMul = 1.15, kbMul = 0.9 },
	wide = { shape = "lens", reach = 1 },
	fingers = { shape = "fingers", reach = 1, kbMul = 0.9 },
	shore = { shape = "shore", reach = 1, front = 0.8, shore = true },
}

-- Character towns (2026-10-13; user: "There should always be secluded towns (maybe near the edge of the map, or on an
-- island, etc.) that really want to sprawl and not build out from the centre", the favourite Acton "has some nice gaps
-- in it"): the map's most secluded towns (ot_map.characters: far from other towns, near the map edge; island towns by a
-- seeded CHARACTER_ISLAND_P) take one of these extreme forms. Sprawling: unshaped (compact field, so the seeded hotspots
-- pull patches out along the main streets), much larger blocks, a far front, 5 leapfrog patches, many meadows between:
-- clusters with gaps. Linear / fingers: much longer, narrower arms. Shore: a long strip.
FM.CHARACTER = {
	sprawling = { shape = "compact", block = 1.5, front = 2.4, sector = 2.0, hotspots = 5, pull = 0.85, greensAdd = 4,
		greensMin = 6 },
	linear = { shape = "linear", reach = 1, kaMul = 1.45, kbMul = 0.75, block = 1.15, greensAdd = 1, greensMin = 2 },
	fingers = { shape = "fingers", reach = 1, kaMul = 1.35, kbMul = 0.75, greensAdd = 2, greensMin = 3 },
	shore = { shape = "shore", reach = 1, front = 0.8, shore = true, kaMul = 1.3 },
}
-- Coastal huggers (2026-10-14, user: "Could be more extreme coastal city hugging in at least 1-2 cities per map"): the
-- map's 1-2 towns with the most coastline (ot_map.coastal) take this strong shore form: a long, shallow strip along the
-- shore both ways from the town's foot (kaMul / kbMul), the depth cap COASTAL_DEPTH m, the waterfront street.
FM.COASTAL = { shape = "shore", reach = 1, front = 0.7, shore = true, kaMul = 1.6, kbMul = 0.75, coastal = true }
FM.COASTAL_DEPTH = { 150, 230 }   -- m: the shore strip's depth cap (ot_shape shoreData depthCap), clamped to this
FM.COASTAL_DEPTH_F = 0.85         -- x the shape's own cap first

FM.CHARACTER_WEIGHTS = { sprawling = 3, linear = 1.5, fingers = 1.5 }
FM.CHARACTER_SITE = { valley = 2, river = 1, shore = 2, island = 1 }   -- added weights (linear; shore / island: shore)
FM.CHARACTER_ISLAND_P = 0.3   -- an island town not among the map's most secluded is a character town this often


-- Shore towns (2026-10-12, user: "some coastal towns prefer spreading across the coastline, similar to how high real
-- estate can be on the coast ... more prevalent on island maps, but lakes also act like this"): a town on a sea or
-- lake shore it can follow (ot_site features.shore > 0: a traced shoreline, the water within 450 m; not a pond, not a
-- river) takes the shore form with probability SHORE_P.base (+ island on an island, + near when the water is within
-- nearM of the centre) x the style's SHORE_STYLE factor (strict grids less: their lattice can't follow a curve),
-- x weak when features.shore < 0.5, at most max. A seeded draw per town (rng "shoreForm").
-- 2026-10-13 (real map run: 7 of 14 styled towns took the shore form, the user asked for "some"): with the site shape
-- candidate (ot_shape SHORE_GAIN) about a fifth of the sea / lake towns, a third on islands.
-- 2026-10-13 round 5 (user: "Hugging coastlines more often is probably not a bad idea"): back up, ~35-45 % of the sea /
-- lake towns (with the shape candidate), ~60 % on islands.
-- 2026-10-13 final test (user: "it wasn't obvious to me if any of these towns were doing the spread across coastline":
-- 3 shore towns of 16 readings with sea / lake water, all reading as normal towns): up again, most sea / lake towns
-- within nearM of the water.
FM.SHORE_P = { base = 0.34, island = 0.25, near = 0.16, nearM = 400, weak = 0.75, max = 0.85 }
FM.SHORE_STYLE = { SUPERBLOCK = 0.5, MED_ENSANCHE = 0.6, NA_GRID = 0.8, NORDIC = 1.1, JP_DENSE = 1.1, MED_HILL = 1.1 }

-- style weights on flat land without site evidence (seeded draw x the site factors below)
-- (2026-10-13 round 5, user: "I still wish cities were more spread out around the landscape, not just radiating from
-- the centre": fewer clustered / wide outcomes, more linear / fingers / sprawling; the real map run had 7 of 16 towns
-- clustered or wide)
FM.STYLE_WEIGHTS = {
	NA_GRID = { sprawling = 2, linear = 1.5, clustered = 0.75, radiating = 1, wide = 0.4 },
	NA_SUBURB = { sprawling = 2.5, fingers = 1.5, radiating = 1, clustered = 0.4 },
	EU_ORGANIC = { clustered = 1.1, radiating = 1.25, sprawling = 1.5, linear = 1.4, wide = 0.35, fingers = 0.8 },
	EU_EXTENSION = { clustered = 0.75, radiating = 1.5, sprawling = 1.25, fingers = 1, linear = 1.1, wide = 0.3 },
	MED_HILL = { clustered = 1.5, radiating = 0.6, linear = 1.5, fingers = 0.6 },
	MED_ENSANCHE = { clustered = 1.4, sprawling = 1, wide = 0.6, linear = 0.6 },
	JP_DENSE = { clustered = 2, radiating = 1.5, sprawling = 1, linear = 1 },
	NORDIC = { linear = 2, clustered = 0.6, sprawling = 1.25, fingers = 1, wide = 0.4 },
	SUPERBLOCK = { sprawling = 2, clustered = 1, radiating = 1, linear = 0.5 },
}
FM.DEFAULT_WEIGHTS = { clustered = 2, sprawling = 1, radiating = 1 }

-- a shape picked from the site / roads / a neighbour decides the form
-- (2026-10-13: a coast fan no longer decides "wide": every coast town drew the fan from the site, so 7 of 16 towns of
-- the real map run were wide ovals; a fan now only adds FAN_WIDE to the wide form in the seeded draw)
FM.FROM_SHAPE = { linear = "linear", ridge = "linear", lens = "wide", fingers = "fingers",
	cross = "radiating", twin = "clustered", compact = "clustered", shore = "shore" }
FM.FAN_WIDE = 1

--- Probability that a town with site features f and style id takes the shore form (0 without a usable shore).
function FM.shoreChance(f, styleId, waterDist, climate)
	if f == nil or (f.shore or 0) <= 0 then return 0 end
	local P = FM.SHORE_P
	local p = P.base + (f.island and P.island or 0) + ((waterDist or math.huge) <= P.nearM and P.near or 0)
	p = p * (FM.SHORE_STYLE[styleId] or 1) * (f.shore < 0.5 and P.weak or 1)
	p = p * (FM.CLIMATE_SHORE[climate or ""] or 1)
	return math.min(P.max, p)
end

-- climate bias of the form draw (2026-10-14, NEXT_PHASE_BRIEF 48 item 3, with ot_site CLIMATE): tropical towns spread
-- loose and low along the coasts and roads: sprawling, linear and radiating (ribbons on the roads out) up, clustered
-- down, and the shore form more often (CLIMATE_SHORE, still at most SHORE_P.max). The forms' own geometry is unchanged.
FM.CLIMATE = { tropical = { sprawling = 1.5, linear = 1.3, radiating = 1.25, clustered = 0.6 } }
FM.CLIMATE_SHORE = { tropical = 1.3 }

-- (round 5; until then sprawlTight 0.7, clusteredTight 0.8, linearRough 0, fingersRough 0)
FM.SITE_K = { sprawlTight = 0.6, clusteredTight = 0.3, linearRough = 0.5, fingersRough = 0.3 }

--- Site factors for the draw: { [form] = x } from ot_site features (open, rough, coast, valley) and the nearest
--- neighbour distance (m, nil: none).
function FM.siteFactors(f, nearDist)
	f = f or {}
	local open, rough = f.open or 0, f.rough or 0
	local tight = math.max(rough, f.coast or 0, (f.valley or 0) > 0 and 1 or 0)
	-- (2026-10-13 round 5: rough land made towns clustered; real towns in rough country follow the land instead, along
	-- the contour, the valley floor, the ridges: rough favours linear / fingers, clustered only a little)
	local K = FM.SITE_K
	local x = {
		sprawling = (0.5 + 1.5 * open) * (1 - K.sprawlTight * tight),
		clustered = 1 + K.clusteredTight * tight,
		linear = 1 + 0.8 * ((f.valley or 0) > 0 and 1 or 0) + K.linearRough * rough,
		radiating = 1 + 0.5 * open,
		wide = 1, fingers = 1 + 0.3 * open + K.fingersRough * rough,
	}
	if nearDist and nearDist < 2000 then x.sprawling = x.sprawling * 0.5 end
	-- (terrain-squeezed towns, 2026-10-14: a little more compact and dense; linear / fingers along the valley stay)
	-- (only a real squeeze: SQUEEZE_MIN and more; below it the draw stays as it was)
	local sq = math.max(0, ((f.squeeze or 0) - FM.SQUEEZE_MIN) / (1 - FM.SQUEEZE_MIN))
	if sq > 0 then
		local Q = FM.SQUEEZE_K
		x.clustered = x.clustered * (1 + Q.clustered * sq)
		x.sprawling = x.sprawling * (1 - Q.sprawling * sq)
		x.wide = x.wide * (1 - Q.wide * sq)
	end
	return x
end

FM.SQUEEZE_K = { clustered = 1.0, sprawling = 0.7, wide = 0.5 }
FM.SQUEEZE_MIN = 0.3

--- Form of a town: { id, why, def } or nil (no form: legacy saved frame, dev-forced shape).
--- inputs: ot_inputs.build result (form = forced id, frame.form, shape = dev-forced shape); p: the resolved style
--- (id, seed, grower); shape: the first ot_shape pick (reason "style" = drawn from the style's weights);
--- features: ot_site.features or nil.
function FM.pick(inputs, p, shape, features)
	if not FM.ENABLED then return nil end
	local forced = inputs.form
	if forced and FM.DEF[forced] then return { id = forced, why = "forced", def = FM.DEF[forced], forced = true } end
	-- a strong character's form (ot_character, 2026-10-14): before the saved form (the kind is saved on the frame, `ck`,
	-- and gives the same def every session) and before the coastal / secluded / shore / drawn forms
	local cf = inputs.charForm
	if cf and cf.def and FM.DEF[cf.id] then
		return { id = cf.id, why = "char:" .. tostring(cf.kind), def = cf.def, charKind = cf.kind }
	end
	local fr = inputs.frame
	if fr and fr.form == "shore" and fr.coastal then
		return { id = "shore", why = "saved:coastal", def = FM.COASTAL, saved = true, coastal = true }
	end
	if fr and fr.form and FM.DEF[fr.form] then
		local ch = fr.character and FM.CHARACTER[fr.form] ~= nil
		return { id = fr.form, why = "saved", def = ch and FM.CHARACTER[fr.form] or FM.DEF[fr.form], saved = true,
			character = ch or nil }
	end
	if fr and fr.axis then return nil end   -- a frame saved before forms existed: the town keeps its growth
	if inputs.shape then return nil end      -- dev-forced shape (shape row): the shape alone
	-- coastal huggers (ot_map.coastal, 2026-10-14): the map's 1-2 most coastal towns, on a shore the shape can follow
	local co = inputs.coastal
	if co and co.coastal and features and (features.shore or 0) > 0 then
		return { id = "shore", why = string.format("coastal:rank=%d,score=%.2f", co.rank or 0, co.score or 0),
			def = FM.COASTAL, coastal = true }
	end
	-- character towns (ot_map): the map's most secluded towns, and island towns now and then, take an extreme form
	local chi = inputs.character
	local isChar, chWhy = chi ~= nil and chi.character == true, "secluded"
	-- (§68: stays on rng.unit: no other decision has a 15-letter label)
	if not isChar and features and features.island and rng.unit(p.seed or 1, "characterIsland") < FM.CHARACTER_ISLAND_P then
		isChar, chWhy = true, "island"
	end
	if isChar then
		local id, why = FM.characterPick(p.seed or 1, features)
		return { id = id, why = "character:" .. chWhy .. ":" .. why, def = FM.CHARACTER[id], character = true }
	end
	-- shore towns: a seeded share of the towns on a sea / lake shore follow it
	local w = inputs.terrain and inputs.terrain.water
	local pShore = FM.shoreChance(features, p.id, w and w.distance, inputs.climate)
	if pShore > 0 and rng.decide(p.drawV, p.seed or 1, "shoreForm") < pShore then
		return { id = "shore", why = string.format("shore:p=%.2f,%s%s", pShore, tostring(features.body),
			features.island and ",island" or ""), def = FM.DEF.shore }
	end
	local fan = shape and shape.id == "fan" and shape.reason ~= "style"
	if shape and shape.reason and shape.reason ~= "style" and FM.FROM_SHAPE[shape.id] then
		local id = FM.FROM_SHAPE[shape.id]
		return { id = id, why = "shape:" .. shape.id, def = FM.DEF[id], fromShape = true }
	end
	local ws = FM.STYLE_WEIGHTS[p.id] or FM.DEFAULT_WEIGHTS
	local cw = FM.CLIMATE[inputs.climate or ""] or {}
	local near = inputs.neighbours and inputs.neighbours[1]
	local sf = FM.siteFactors(features, near and near.dist)
	-- neighbour diversity (ot_diverse, 2026-10-13): forms the towns nearby use weigh less, closer = stronger
	local dv = DV.factors(inputs.nbrPicks, "form")
	local used = {}
	local list, total = {}, 0
	for _, id in ipairs(FM.IDS) do
		local w = ((ws[id] or 0) + ((fan and id == "wide") and FM.FAN_WIDE or 0)) * (sf[id] or 1) * (cw[id] or 1)
		if dv[id] and w > 0 then
			w = w * dv[id]
			used[id] = dv[id]
		end
		if w > 0 then
			list[#list + 1] = { id = id, w = w }
			total = total + w
		end
	end
	if total <= 0 then return nil end
	DV.note(inputs, "form", used)
	-- (§68: the form pick stays on rng.unit: no other decision has a 4-letter label)
	local r = rng.unit(p.seed or 1, "form") * total
	local id = list[#list].id
	for _, x in ipairs(list) do
		r = r - x.w
		if r <= 0 then id = x.id break end
	end
	local parts = {}
	for _, x in ipairs(list) do parts[#parts + 1] = string.format("%s=%.1f", x.id, x.w) end
	return { id = id, why = "draw:" .. table.concat(parts, "/"), def = FM.DEF[id] }
end

--- Character form for a town: id, why (the weights). Seeded (rng "characterForm"); the site adds weight (valley /
--- river: linear; a shore it can follow: shore, more on islands).
function FM.characterPick(seed, f)
	f = f or {}
	local w = {}
	for k, v in pairs(FM.CHARACTER_WEIGHTS) do w[k] = v end
	local S = FM.CHARACTER_SITE
	if (f.valley or 0) > 0 then w.linear = w.linear + S.valley end
	if (f.river or 0) > 0 then w.linear = w.linear + S.river end
	if (f.shore or 0) > 0 then w.shore = S.shore + (f.island and S.island or 0) end
	local list, total = {}, 0
	for _, id in ipairs(FM.IDS) do
		if (w[id] or 0) > 0 then
			list[#list + 1] = { id = id, w = w[id] }
			total = total + w[id]
		end
	end
	-- (§68: stays on rng.unit, the anchor of its 13-letter group: satpace:ready / every / phase draw with rng.decide)
	local r = rng.unit(seed, "characterForm") * total
	local id = list[#list].id
	for _, x in ipairs(list) do
		r = r - x.w
		if r <= 0 then id = x.id break end
	end
	local parts = {}
	for _, x in ipairs(list) do parts[#parts + 1] = string.format("%s=%.1f", x.id, x.w) end
	return id, table.concat(parts, "/")
end

--- The shape id the form wants for style p (nil: keep the drawn shape).
function FM.shapeFor(form, p)
	if form == nil then return nil end
	local d = form.def
	if p.grower == "organic" and d.organicShape then return d.organicShape end
	return d.shape
end

--- Applies the form's block scale to style p (before the shape pick: shape.block follows p.block).
function FM.applyBlock(form, p)
	if form == nil or form.def.block == nil or form.def.block == 1 then return end
	p.block.len = p.block.len * form.def.block
	p.block.depth = p.block.depth * form.def.block
end

--- Applies the growth modifiers (front, sector, hotspots, ribbon, reach) to style p after the shape pick; sets
--- p.form = { id, why, front }. Greens: the caller passes the count FM.greens gives to ot_style.greenReserves.
function FM.apply(form, p)
	if form == nil then return end
	local d = form.def
	p.form = { id = form.id, why = form.why, front = d.front or 1, character = form.character or nil,
		coastal = form.coastal or nil, charKind = form.charKind }
	local irr = p.irregular
	if irr then
		if d.sector then irr.sector = math.min(0.5, (irr.sector or 0) * d.sector) end
		if d.hotspots then irr.hotspots = (irr.hotspots or 0) + d.hotspots end
		if d.pull then irr.pull = math.max(irr.pull or 0, d.pull) end
		if d.ribbon then irr.ribbon = (irr.ribbon or 1) * d.ribbon end
	end
	if p.shape and d.reach and FM.shapeFor(form, p) == p.shape.id then
		p.shape.reach = d.reach
		p.shape.strong = d.reach >= 1
	end
	-- longer / narrower arms (ot_shape kaMul / kbMul: linear, ridge, cross, fingers, lens, shore along the shore)
	if p.shape and FM.shapeFor(form, p) == p.shape.id then
		p.shape.kaMul, p.shape.kbMul = d.kaMul, d.kbMul
	end
	-- (a coastal hugger: a shallower strip)
	-- (a strong character's own cap range, ot_character: the clifftop strip)
	local dc = d.depthCap or (d.coastal and FM.COASTAL_DEPTH) or nil
	if dc and p.shape and p.shape.shore and p.shape.shore.depthCap then
		local sd = p.shape.shore
		sd.depthCap = math.max(dc[1], math.min(dc[2], sd.depthCap * FM.COASTAL_DEPTH_F))
	end
end

--- Green reserve count for the form (nil: the style's default).
function FM.greens(form, styleCount)
	if form == nil then return nil end
	local d = form.def
	if d.greens then return d.greens end
	if d.greensAdd then return math.max(d.greensMin or 0, (styleCount or 0) + d.greensAdd) end
	return nil
end

return FM
