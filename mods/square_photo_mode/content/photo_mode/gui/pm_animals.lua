-- gui/pm_animals.lua (Photo Mode round 16b, groups and suitable places round 17, its own tab round 20): groups of
-- the base game's animals added to the view (user: "We should have various groups, e.g. a whole herd of elk, flocks
-- of birds, a lone cougar"). PLAN.md "Round 16b" item 3, "Round 17" and "Round 20"; TESTING.md AN, AG, R20.
--
-- What the API allows (api/tealdef/api/cmd.d.tl):
--   makeAnimalSpawnAtCmd(fileName, position : Vec2f, lookAt? : Vec2f): a new animal entity of a base model at a map
--     point, lookAt the direction it faces (result: resultEntity; ok=true and an entity in 2026-10-14_0842_session).
--   makeAnimalSetStateCmd: no position and no target: an existing animal can't be MOVED.
--   makeCustomEntityDestroyCmd(entity): removes an animal ("Remove all": ours only; ok=true in 0842).
--
-- Groups (M.GROUPS): presets of one species and a size, from the models' own metadata (base/content/animal/*.mdl
-- metadata.animal): cranes, salmon and discus are ONE entity each that flies / swims as a flock of 6-15
-- (flockFormationFn animal.script.lua flock.crane / salmon / discus), so a "flock" of them is 1-3 entities; the
-- others have no flock function, so a herd / pack / flock is that many single animals spawned close together.
-- There is no elk (or moose) model in the game: the herd is deer. Round 20: the draft horse
-- (animal/draft_horse/draft_horse.mdl) is an animal too (metadata.animal with Walk / Trot / Canter / Gallop, density
-- 0: the game never spawns it), and its suitableAreas are all 0: no spot scores below 0, so it lives anywhere. The
-- four discus models (cr_fish_01-04) are one species; each school takes one at random. cow / horse / sheep .mdl
-- have no metadata.animal (farm props): not spawnable as animals.
--
-- Why animals die (2026-10-14_0842_session, desert): all 18 cougars spawned ok=true, four were gone within 6 s and
-- the rest within 25 s, while gulls and eagles lived on. The wiki (modding/environment/animals.md "Suitable
-- Areas") and the models: every animal sums a score from its `suitableAreas` (bias, height, noise, slope, and the
-- civilisation / forest / predator / shore / water areas); "If an animal gets into an area with negative score, it
-- will try to run away. If it fails to leave the non suitable area it will eventually die" (each land model has a
-- "Dying" movement type with despawnAtEnd = true; the component counts `invalidTileElapsed`). Each spot is scored
-- here the engine's way (M.score) from what a GUI script can read: height (terrain), slope (terrain probes), noise
-- (emissionGridSystem, in dB as the game's own tooltips convert it), water and shore (waterAt), civilisation
-- (roads, tracks, constructions, town buildings near: octree), forest (tree groups near), predators (the ones we
-- added).
-- Round 20 (2026-10-14_2150_r19-test; user: "cougar keeps saying no place these animals can live, even on flat. we
-- should allow putting wrong animals in environment even if they die right away, just note that"): every cougar
-- click was refused with "noise 60" (each of 60 tries; the noise map {60, 150} -> {0, -1000} reads the probe's dB,
-- whose scale against the engine's is unconfirmed). The score now only PREFERS a spot (M.BAD_SPOT added to its
-- cost); nothing is refused for it, the status says the spot may not suit them, and the tab's note says such
-- animals die within seconds. Only the impossible is refused: land animals on water, fish off water.
--
-- Round 20 placement (user: "try to make sure when inserted you can see them (take into account the perspective,
-- how far on horizon they should be, etc.)"): round 17 sampled map points between the eye and the view's centre,
-- which for a high or steep view put the animals a few pixels tall or off the screen. Now rays are cast through a
-- grid of screen points (api.gui.camera.screen2World at depth 0 and 1, gui.d.tl) and marched onto the terrain
-- (M.march), each hit is projected back (world2Screen) with the animal's height above it (a bird: at the height
-- it flies at, its model's heightOffset; that point must be on the screen), and the hit whose on-screen height is
-- nearest the Distance choice's share of the screen height (M.DIST_FRAC: Close / Middle / Far) wins, near the
-- middle of the frame. The
-- members then stand in the chosen formation (Group, Line across, Single file, Spread out) facing the chosen way,
-- each kept on the screen. A view with no ground in it (looking at the sky) is the one refusal.
--
-- Save impact (said in the tooltip): a sim change. The animals are ordinary base-game animals, saved with the game
-- like the ones the game spawns itself, moved and despawned by the engine as its own; removing Photo Mode leaves
-- only base animals. At most PER_PRESS per click; no total limit (round 19): the rows list the added ones per
-- species with a count and a Remove each. The life checks take at most LIFE_PER_STEP animals a frame.
-- Logs "[PhotoMode] animals ..." with every command's callback, VERIFY_MS later where each is, and every second
-- whether each still lives ("life": a death with its lifetime and its last invalidTileElapsed).

local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local world = ug_require "square_photo_mode::/photo_mode/gui/pm_world.lua"
local weather = ug_require "square_photo_mode::/photo_mode/gui/pm_weather.lua"

local M = {}

-- The models' metadata.animal.suitableAreas (base/content/animal/*/*.mdl, read 2026-10-14): bias, height / noise /
-- slope maps (mapFrom -> mapTo, clamped), and the area scores.
local function area(bias, h, n, s, sc)
	return { bias = bias, height = h, noise = n, slope = s, scores = sc }
end
local LAND_SC = function(forest, predator)
	return { civilisation = -1000, forest = forest, predator = predator, shore = -1000, water = -1000 }
end
local FISH = area(-2000, nil, nil, nil, { civilisation = -1000, forest = -1000, predator = 0, shore = -5000, water = 2001 })
local ANYWHERE = area(0, nil, nil, nil, { civilisation = 0, forest = 0, predator = 0, shore = 0, water = 0 })

-- key, model file(s), climates (nil = all; where the game itself spawns them), kind, predator, suitableAreas;
-- round 20: size (m: the model's height, a flock's or school's spread, what has to show on the screen), gap (m
-- between two of a group), fly (m: a bird's flying height over the ground, the model's heightOffset)
M.SPECIES = {
	{ key = "deer", file = "::/animal/wildlife_deer/wildlife_deer.mdl", climates = { temperate = true, subarctic = true },
		kind = "land", size = 2.2, gap = 3,
		area = area(0, { 400, 4000, 0, -500 }, { 60, 100, 0, -2000 }, { 0.3, 2, 0, -1000 }, LAND_SC(999, -1000)) },
	{ key = "fox", file = "::/animal/wildlife_fox/wildlife_fox.mdl", climates = { temperate = true, subarctic = true, tropical = true },
		kind = "land", size = 1.0, gap = 2,
		area = area(5, { 400, 2000, 0, -1000 }, { 60, 150, 0, -1000 }, { 0.3, 2, 0, -1000 }, LAND_SC(-4, 0)) },
	{ key = "wolf", file = "::/animal/wolf/wolf.mdl", climates = { temperate = true, subarctic = true }, kind = "land",
		predator = true, size = 1.0, gap = 2.5,
		area = area(5, { 400, 2000, 0, -1000 }, { 60, 150, 0, -1000 }, { 0.3, 2, 0, -1000 }, LAND_SC(-4, 0)) },
	{ key = "bear", file = "::/animal/wildlife_bear/wildlife_bear.mdl", climates = { temperate = true, subarctic = true },
		kind = "land", predator = true, size = 1.7, gap = 4,
		area = area(0, { 400, 2000, 0, -1000 }, { 60, 150, 0, -1000 }, { 0.3, 2, 0, -1000 }, LAND_SC(0, 0)) },
	{ key = "cougar", file = "::/animal/cougar/cougar.mdl", climates = { dry = true }, kind = "land", predator = true,
		size = 0.8, gap = 2.5,
		area = area(5, { 400, 2000, 0, -1000 }, { 60, 150, 0, -1000 }, { 0.3, 2, 0, -1000 }, LAND_SC(-4, 0)) },
	{ key = "horse", file = "::/animal/draft_horse/draft_horse.mdl", climates = nil, kind = "land", size = 2.8, gap = 4,
		area = ANYWHERE },
	{ key = "crane", file = "::/animal/bird_crane/bird_crane.mdl", climates = { temperate = true, subarctic = true, tropical = true },
		kind = "bird", flock = true, size = 6, gap = 25, fly = 40 },
	{ key = "eagle", file = "::/animal/bird_eagle/bird_eagle.mdl", climates = { dry = true }, kind = "bird", size = 2.1,
		gap = 15, fly = 60 },
	{ key = "gull", file = "::/animal/bird_gull/bird_gull.mdl", climates = nil, kind = "bird", size = 1.3, gap = 6, fly = 50 },
	{ key = "salmon", file = "::/animal/fish_salmon/fish_salmon.mdl", climates = { temperate = true, subarctic = true, dry = true },
		kind = "fish", flock = true, area = FISH, size = 4, gap = 12 },
	{ key = "discus", file = "::/animal/cr_fish/cr_fish_01.mdl", files = { "::/animal/cr_fish/cr_fish_01.mdl",
		"::/animal/cr_fish/cr_fish_02.mdl", "::/animal/cr_fish/cr_fish_03.mdl", "::/animal/cr_fish/cr_fish_04.mdl" },
		climates = { tropical = true }, kind = "fish", flock = true, area = FISH, size = 3, gap = 10 },
}
local BY_KEY = {}
for __, sp in ipairs(M.SPECIES) do BY_KEY[sp.key] = sp end
M.BY_KEY = BY_KEY

-- Group presets: species, how many entities (min..max), how far apart they may be from the group's middle (m).
M.GROUPS = {
	{ key = "deer_herd", sp = "deer", min = 6, max = 12, r = 30 },
	{ key = "deer_few", sp = "deer", min = 2, max = 3, r = 12 },
	{ key = "deer_lone", sp = "deer", min = 1, max = 1, r = 0 },
	{ key = "fox_lone", sp = "fox", min = 1, max = 1, r = 0 },
	{ key = "fox_pair", sp = "fox", min = 2, max = 2, r = 8 },
	{ key = "wolf_pack", sp = "wolf", min = 3, max = 6, r = 20 },
	{ key = "wolf_lone", sp = "wolf", min = 1, max = 1, r = 0 },
	{ key = "bear_lone", sp = "bear", min = 1, max = 1, r = 0 },
	{ key = "bear_pair", sp = "bear", min = 2, max = 2, r = 10 },
	{ key = "cougar_lone", sp = "cougar", min = 1, max = 1, r = 0 },
	{ key = "cougar_pair", sp = "cougar", min = 2, max = 2, r = 10 },
	{ key = "horse_lone", sp = "horse", min = 1, max = 1, r = 0 },
	{ key = "horse_pair", sp = "horse", min = 2, max = 2, r = 8 },
	{ key = "horse_herd", sp = "horse", min = 5, max = 9, r = 25 },
	{ key = "crane_flock", sp = "crane", min = 1, max = 1, r = 0 },
	{ key = "crane_flocks", sp = "crane", min = 3, max = 3, r = 60 },
	{ key = "eagle_lone", sp = "eagle", min = 1, max = 1, r = 0 },
	{ key = "eagle_circling", sp = "eagle", min = 3, max = 5, r = 40 },
	{ key = "gull_flock", sp = "gull", min = 8, max = 20, r = 35 },
	{ key = "gull_few", sp = "gull", min = 2, max = 3, r = 15 },
	{ key = "salmon_school", sp = "salmon", min = 1, max = 1, r = 0 },
	{ key = "salmon_schools", sp = "salmon", min = 3, max = 3, r = 25 },
	{ key = "discus_school", sp = "discus", min = 1, max = 1, r = 0 },
	{ key = "discus_schools", sp = "discus", min = 3, max = 3, r = 20 },
}
M.PER_PRESS = 20
M.CIV_R = { edge = 40, construction = 60 } -- civilisation: no road / track or building this near (m, inferred)
M.FOREST_R = 30 -- tree groups this near: the forest area (inferred)
M.SHORE_R = 20 -- water this near: the shore (inferred)
M.PREDATOR_R = 150 -- deer kept this far from the predators we added (inferred)
M.SLOPE_STEP = 4 -- m between the slope probes
M.SPACING = 3 -- between two animals of one group at least (m)
M.VERIFY_MS = 1500
M.LIFE_MS = 1000 -- each added animal checked this often ...
M.LIFE_MAX_MS = 180000 -- ... for this long after its spawn
M.LIFE_PER_STEP = 40 -- round 19: life checks per frame at most (no total limit: hundreds may be added)
M.JUMP_M = 200 -- an id whose animal moved farther in one check belongs to another entity now (ids are reused)

-- Round 20 placement (the header). Choices: Distance (the share of the screen height an animal fills), Formation,
-- Facing; their keys in the order of the tab's buttons.
M.DISTANCES = { "close", "middle", "far" }
M.DIST_FRAC = { close = 0.12, middle = 0.06, far = 0.03 }
M.FORMATIONS = { "group", "line", "file", "spread" }
M.FACINGS = { "any", "camera", "side", "away" }
-- the screen points the rays go through (shares of the width / height from the top left): the middle first, the
-- lower half before the upper (the ground)
M.RAY_U = { 0.5, 0.38, 0.62, 0.26, 0.74 }
M.RAY_V = { 0.6, 0.7, 0.5, 0.8, 0.4, 0.88, 0.3 }
M.RAY_T0, M.RAY_GROW, M.RAY_STEPS, M.RAY_MAX = 2, 1.12, 80, 6000 -- the march: first step (m), growth, cap, reach
M.RAY_BISECT = 8
M.EDGE = 0.04 -- a member stands at least this share of the screen inside its edges
M.AIM_V = 0.62 -- the preferred height of the group on the screen (a little under the middle)
M.BAD_SPOT = 0.7 -- added to a spot's cost when its score is below 0 (prefer spots the animals live on)
M.MEMBER_TRIES = 12 -- spots tried per member
M.FAR_SHARE = 0.4 -- the best spot's on-screen height under this share of the chosen one: "far" in the status

local S = { sel = 1, dist = 2, form = 1, face = 1, added = {}, verify = nil, lifeAt = 0, lifeNext = 1 }
M.S = S
M.changed = function() end

local function log(msg) core.log("animals " .. msg) end
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function native(sp, climate)
	return climate == nil or sp.climates == nil or sp.climates[climate] == true
end
M.native = native

--- Round 20: every group (the user: "allow putting wrong animals in environment"), the map climate's own first
--- (an unknown climate: all are its own). A list of GROUPS entries.
function M.available(climate)
	local own, other = {}, {}
	for __, g in ipairs(M.GROUPS) do
		local sp = BY_KEY[g.sp]
		if sp ~= nil then
			if native(sp, climate) then own[#own + 1] = g else other[#other + 1] = g end
		end
	end
	for __, g in ipairs(other) do own[#own + 1] = g end
	return own
end

local function labels()
	return {
		deer_herd = _("Herd of deer"), deer_few = _("A few deer"), deer_lone = _("Lone deer"), fox_lone = _("Lone fox"),
		fox_pair = _("Pair of foxes"), wolf_pack = _("Wolf pack"), wolf_lone = _("Lone wolf"), bear_lone = _("Lone bear"),
		bear_pair = _("Two bears"), cougar_lone = _("Lone cougar"), cougar_pair = _("Pair of cougars"),
		horse_lone = _("Lone horse"), horse_pair = _("Pair of horses"), horse_herd = _("Herd of horses"),
		crane_flock = _("Flock of cranes"), crane_flocks = _("Three flocks of cranes"), eagle_lone = _("Lone eagle"),
		eagle_circling = _("Eagles circling"), gull_flock = _("Flock of gulls"), gull_few = _("A few gulls"),
		salmon_school = _("School of salmon"), salmon_schools = _("Three schools of salmon"),
		discus_school = _("School of discus fish"), discus_schools = _("Three schools of discus fish"),
	}
end

local function speciesNames()
	return {
		deer = _("Deer"), fox = _("Foxes"), wolf = _("Wolves"), bear = _("Bears"), cougar = _("Cougars"),
		horse = _("Horses"), crane = _("Crane flocks"), eagle = _("Eagles"), gull = _("Gulls"),
		salmon = _("Salmon schools"), discus = _("Discus fish schools"),
	}
end

--- The size a group gets (pure: r() 0..1).
function M.groupSize(g, r)
	if g.max <= g.min then return g.min end
	return g.min + math.min(g.max - g.min, math.floor(r() * (g.max - g.min + 1)))
end

--- A suitableAreas map {from0, from1, to0, to1} at v (clamped), 0 for a nil map or value.
function M.map(m, v)
	if m == nil or not finite(v) then return 0 end
	local f0, f1, t0, t1 = m[1], m[2], m[3], m[4]
	if v <= f0 then return t0 end
	if v >= f1 then return t1 end
	return t0 + (t1 - t0) * (v - f0) / (f1 - f0)
end

--- The engine's score of species sp at (x, y), as far as probes read it (pure apart from the probes).
--- probes: ground(x, y), water(x, y), busy(x, y, r, what), noise(x, y) dB or nil, forest(x, y, r), predator(x, y, r).
--- Returns score, parts { why = value } (the non-zero parts, for the log), the first fatal reason or nil.
function M.score(sp, x, y, probes)
	local a = sp.area
	if a == nil then return 0, {}, nil end
	local parts = { bias = a.bias }
	local sc = a.scores
	local w = probes.water(x, y) == true
	if sp.kind == "fish" then
		if not w then return -math.huge, parts, "not water" end
		parts.water = sc.water
		for k = 0, 7 do
			local an = k * math.pi / 4
			if probes.water(x + M.SHORE_R * math.cos(an), y + M.SHORE_R * math.sin(an)) ~= true then
				parts.shore = sc.shore
				break
			end
		end
	else
		if w then return -math.huge, parts, "water" end
		local g = probes.ground(x, y)
		if not finite(g) then return -math.huge, parts, "no ground" end
		parts.height = M.map(a.height, g)
		local slope = 0
		for k = 0, 7 do
			local an = k * math.pi / 4
			local g2 = probes.ground(x + M.SLOPE_STEP * math.cos(an), y + M.SLOPE_STEP * math.sin(an))
			if finite(g2) then slope = math.max(slope, math.abs(g2 - g) / M.SLOPE_STEP) end
		end
		parts.slope = M.map(a.slope, slope)
		parts.slopeIs = slope
		if sc.shore ~= 0 then
			for k = 0, 7 do
				local an = k * math.pi / 4
				if probes.water(x + M.SHORE_R * math.cos(an), y + M.SHORE_R * math.sin(an)) == true then
					parts.shore = sc.shore
					break
				end
			end
		end
		if sc.civilisation ~= 0 and (probes.busy(x, y, M.CIV_R.edge, "BASE_EDGE")
			or probes.busy(x, y, M.CIV_R.construction, "CONSTRUCTION")
			or probes.busy(x, y, M.CIV_R.construction, "TOWN_BUILDING")) then
			parts.civilisation = sc.civilisation
		end
		if sc.forest ~= 0 and probes.forest ~= nil and probes.forest(x, y, M.FOREST_R) then parts.forest = sc.forest end
		if sc.predator ~= 0 and probes.predator ~= nil and probes.predator(x, y, M.PREDATOR_R) then
			parts.predator = sc.predator
		end
		local n = (a.noise ~= nil and probes.noise ~= nil) and probes.noise(x, y) or nil
		if finite(n) then
			parts.noise = M.map(a.noise, n)
			parts.noiseDb = n
		end
	end
	local total = 0
	for k, v in pairs(parts) do
		if k ~= "slopeIs" and k ~= "noiseDb" and finite(v) then total = total + v end
	end
	local why = nil
	if total < 0 then
		local worst, wv = nil, 0
		for k, v in pairs(parts) do
			if k ~= "slopeIs" and k ~= "noiseDb" and k ~= "bias" and finite(v) and v < wv then worst, wv = k, v end
		end
		why = worst == "slope" and "steep" or (worst == "civilisation" and "roads or buildings") or worst or "score"
	end
	return total, parts, why
end

--- Whether (x, y) suits species sp: birds anywhere; land and fish where the score is not negative. ok, why-not.
function M.suits(sp, x, y, probes)
	if sp.kind == "bird" then return true end
	local total, __, why = M.score(sp, x, y, probes)
	if total >= 0 then return true end
	return false, why or "score"
end

--- Round 20: a ray from (ox, oy, oz) along the unit (dx, dy, dz) marched onto the surface surf(x, y) + zOff (pure
--- apart from surf): growing steps from M.RAY_T0, then M.RAY_BISECT halvings. Returns x, y, t or nil (no hit
--- within maxT, M.RAY_STEPS steps).
function M.march(ox, oy, oz, dx, dy, dz, maxT, surf, zOff)
	if not (finite(ox) and finite(oy) and finite(oz) and finite(dx) and finite(dy) and finite(dz)) then return nil end
	maxT = math.min(finite(maxT) and maxT or M.RAY_MAX, M.RAY_MAX)
	zOff = zOff or 0
	local function below(t)
		local g = surf(ox + dx * t, oy + dy * t)
		return finite(g) and oz + dz * t <= g + zOff
	end
	if below(0) then return nil end -- the start under the surface: no clean hit
	local lo, t = 0, M.RAY_T0
	for __ = 1, M.RAY_STEPS do
		if t > maxT then t = maxT end
		if below(t) then
			local hi = t
			for __ = 1, M.RAY_BISECT do
				local mid = (lo + hi) / 2
				if below(mid) then hi = mid else lo = mid end
			end
			return ox + dx * hi, oy + dy * hi, hi
		end
		if t >= maxT then return nil end
		lo = t
		t = t * M.RAY_GROW
	end
	return nil
end

--- The on-screen height (share of the screen height) of something h m tall standing at (x, y, z): ctx.proj, nil when
--- either end is off the projection.
local function apparent(ctx, x, y, z, h)
	local u0, v0 = ctx.proj(x, y, z)
	local u1, v1 = ctx.proj(x, y, z + h)
	if not (finite(v0) and finite(v1)) then return nil end
	return math.abs(v1 - v0), u0, v0
end

local function onScreen(u, v, edge)
	return finite(u) and finite(v) and u >= edge and u <= 1 - edge and v >= edge and v <= 1 - edge
end

--- The surface a species stands on at (x, y): its z (ground; a bird its flying height over it), nil when the spot is
--- impossible for it (land on water, fish off water, no ground).
local function standZ(sp, ctx, x, y)
	local g = ctx.surf(x, y)
	if not finite(g) then return nil end
	local w = ctx.water(x, y) == true
	if sp.kind == "fish" and not w then return nil end
	if sp.kind == "land" and w then return nil end
	return g + (sp.kind == "bird" and (sp.fly or 0) or 0)
end

--- The group's middle (pure apart from ctx): the screen-grid ray hit whose animal shows nearest the chosen on-screen
--- height, near the frame's middle, preferring spots the species lives on. ctx: ray(u, v) -> ox, oy, oz, dx, dy, dz,
--- maxT (or nil); proj(x, y, z) -> u, v; surf(x, y); water(x, y); eye { x, y, z }; aspect. Returns the best
--- { x, y, z, u, v, frac, score, cost }, the number of rays with a hit, or nil, 0.
function M.middle(sp, want, ctx, r, probes)
	local best, hits = nil, 0
	for __, v0 in ipairs(M.RAY_V) do
		for __, u0 in ipairs(M.RAY_U) do
			local u, v = u0 + (r() - 0.5) * 0.04, v0 + (r() - 0.5) * 0.04
			local ox, oy, oz, dx, dy, dz, maxT = ctx.ray(u, v)
			local x, y = nil, nil
			if ox ~= nil then x, y = M.march(ox, oy, oz, dx, dy, dz, maxT, ctx.surf, 0) end
			local z = x ~= nil and standZ(sp, ctx, x, y) or nil
			if z ~= nil then
				local frac, pu, pv = apparent(ctx, x, y, z, sp.size)
				if frac ~= nil and frac > 0 and onScreen(pu, pv, M.EDGE) then
					hits = hits + 1
					local score = 0
					if sp.kind ~= "bird" and probes ~= nil then score = M.score(sp, x, y, probes) end
					local cost = math.abs(math.log(frac / want)) + 0.8 * math.sqrt((pu - 0.5) ^ 2 + (pv - M.AIM_V) ^ 2)
						+ ((finite(score) and score >= 0) and 0 or M.BAD_SPOT)
					if best == nil or cost < best.cost then
						best = { x = x, y = y, z = z, u = pu, v = pv, frac = frac, score = score, cost = cost }
					end
				end
			end
		end
	end
	return best, hits
end

--- The direction an animal at (x, y) faces for choice `face` (M.FACINGS): a unit { x, y }. side: +1 / -1 (one per
--- group), (rx, ry) the camera's right on the ground.
function M.facing(face, x, y, eye, rx, ry, side, r)
	local dx, dy = eye.x - x, eye.y - y
	local h = math.sqrt(dx * dx + dy * dy)
	if face == "camera" and h > 1e-6 then return { x = dx / h, y = dy / h } end
	if face == "away" and h > 1e-6 then return { x = -dx / h, y = -dy / h } end
	if face == "side" then return { x = side * rx, y = side * ry } end
	local a = r() * 2 * math.pi
	return { x = math.cos(a), y = math.sin(a) }
end

--- Places a group of n of species sp in the view (pure apart from ctx and the probes). opts: dist, form, face (keys
--- of M.DISTANCES / M.FORMATIONS / M.FACINGS), r = group radius (m). Returns { points = { { x, y, look } },
--- mid, want, hits } or nil, why ("no ground" / "no water").
function M.place(sp, n, opts, ctx, r, probes)
	local want = M.DIST_FRAC[opts.dist] or M.DIST_FRAC.middle
	local mid, hits = M.middle(sp, want, ctx, r, probes)
	if mid == nil then return nil, sp.kind == "fish" and "no water" or "no ground" end
	local eye = ctx.eye
	local fx, fy = mid.x - eye.x, mid.y - eye.y
	local fl = math.sqrt(fx * fx + fy * fy)
	if fl < 1e-6 then fx, fy, fl = 1, 0, 1 end
	fx, fy = fx / fl, fy / fl
	local rx, ry = fy, -fx
	-- the frame's width in metres at the middle (the screen height there is size / frac)
	local width = sp.size / mid.frac * (ctx.aspect or 16 / 9)
	local gap = math.max(M.SPACING, sp.gap or M.SPACING)
	local form = opts.form or "group"
	local side = r() < 0.5 and -1 or 1
	local pts = { }
	local function spaced(x, y)
		for __, p in ipairs(pts) do
			if (p.x - x) ^ 2 + (p.y - y) ^ 2 < M.SPACING ^ 2 then return false end
		end
		return true
	end
	local function try(x, y)
		local z = standZ(sp, ctx, x, y)
		if z == nil or not spaced(x, y) then return false end
		local u, v = ctx.proj(x, y, z)
		if not onScreen(u, v, M.EDGE) then return false end
		pts[#pts + 1] = { x = x, y = y, look = M.facing(opts.face, x, y, eye, rx, ry, side, r) }
		return true
	end
	-- a group grows around the middle; the other formations give every member its own slot (the middle one too)
	local first = 1
	if form == "group" then
		try(mid.x, mid.y)
		first = 2
	end
	local R = math.min(math.max(opts.r or 0, gap * math.sqrt(n) * 0.8), 0.3 * width)
	for i = first, n do
		local placed = false
		for k = 1, M.MEMBER_TRIES do
			local x, y
			local j = (k - 1) / M.MEMBER_TRIES -- later tries: more scatter
			if form == "line" then
				local step = math.min(gap * 2, 0.7 * width / math.max(1, n - 1))
				local off = (i - 1 - (n - 1) / 2) * step + (r() - 0.5) * gap * (0.3 + j)
				x, y = mid.x + rx * off, mid.y + ry * off
			elseif form == "file" then
				local off = (i - 1 - (n - 1) / 2) * gap * 1.8
				local lat = (r() - 0.5) * gap * (0.6 + j)
				x, y = mid.x + fx * off + rx * lat, mid.y + fy * off + ry * lat
			elseif form == "spread" then
				local u = 0.12 + 0.76 * (i - 0.5) / n + (r() - 0.5) * 0.06
				local v = mid.v + (r() - 0.5) * (0.1 + 0.2 * j)
				local ox, oy, oz, dx, dy, dz, maxT = ctx.ray(u, v)
				if ox ~= nil then x, y = M.march(ox, oy, oz, dx, dy, dz, maxT, ctx.surf, 0) end
			else
				local a, rad = r() * 2 * math.pi, R * math.sqrt(r()) * (1 + j)
				x, y = mid.x + rad * math.cos(a), mid.y + rad * math.sin(a)
			end
			if x ~= nil and try(x, y) then placed = true break end
		end
		if not placed and form ~= "group" then
			-- the formation's own spot failed (water, off the screen): one try in the group around the middle
			local a, rad = r() * 2 * math.pi, R * math.sqrt(r())
			try(mid.x + rad * math.cos(a), mid.y + rad * math.sin(a))
		end
	end
	if #pts == 0 then return nil, sp.kind == "fish" and "no water" or "no ground" end
	return { points = pts, mid = mid, want = want, hits = hits, width = width }
end

local function octreeAny(x, y, r, what)
	local ok, list = pcall(function()
		return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(x, y), r, api.type.ComponentType[what])
	end)
	return ok and type(list) == "table" and #list > 0
end

local probes = {
	ground = function(x, y) return world.groundAt(x, y) end,
	water = function(x, y) return world.waterAt(x, y) end,
	busy = octreeAny,
	forest = function(x, y, r) return octreeAny(x, y, r, "ASSET_GROUP") end,
	noise = function(x, y)
		local ok, db = pcall(function()
			local p = api.engine.system.emissionGridSystem.getInterpolatedEmission(api.type.Vec2f.new(x, y), true,
				api.type.EmissionGrid.Type.Noise)
			return api.util.powerToDecibel(p)
		end)
		return ok and finite(db) and db or nil
	end,
	predator = function(x, y, r)
		for __, a in ipairs(S.added) do
			local sp = BY_KEY[a.key]
			if a.entity ~= nil and not a.dead and sp ~= nil and sp.predator and (a.x - x) ^ 2 + (a.y - y) ^ 2 <= r * r then return true end
		end
		return false
	end,
}
M.probes = probes

--- The camera as M.place reads it (api.gui.camera: getSize, getEye, screen2World at depth 0 and 1, world2Screen),
--- nil when unreadable.
local function camCtx()
	local cam = api.gui.camera
	local ok, sz, e = pcall(function() return cam.getSize(), cam.getEye() end)
	if not ok or sz == nil or e == nil then return nil end
	local W, H = sz.x, sz.y
	if not (finite(W) and finite(H) and W > 0 and H > 0) then return nil end
	local eye = { x = e.x, y = e.y, z = e.z }
	return {
		eye = eye,
		aspect = W / H,
		ray = function(u, v)
			local okR, a, b = pcall(function()
				return cam.screen2World(api.type.Vec3f.new(u * W, v * H, 0)), cam.screen2World(api.type.Vec3f.new(u * W, v * H, 1))
			end)
			if not okR or b == nil then return nil end
			local ax, ay, az = eye.x, eye.y, eye.z
			if a ~= nil then ax, ay, az = a.x, a.y, a.z end
			-- ordered by the distance to the eye (as Better Minimap's corner rays: a reversed depth range works too)
			local da = (ax - eye.x) ^ 2 + (ay - eye.y) ^ 2 + (az - eye.z) ^ 2
			local db = (b.x - eye.x) ^ 2 + (b.y - eye.y) ^ 2 + (b.z - eye.z) ^ 2
			local bx, by, bz = b.x, b.y, b.z
			if db < da then ax, ay, az, bx, by, bz = bx, by, bz, ax, ay, az end
			local dx, dy, dz = bx - ax, by - ay, bz - az
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			if not finite(len) or len < 1e-6 then return nil end
			return ax, ay, az, dx / len, dy / len, dz / len, len
		end,
		proj = function(x, y, z)
			local okP, s = pcall(cam.world2Screen, api.type.Vec3f.new(x, y, z))
			if not okP or s == nil then return nil end
			return s.x / W, s.y / H
		end,
		surf = probes.ground,
		water = probes.water,
	}
end
M.camCtx = camCtx

local function climate()
	local ok, c = pcall(weather.climate)
	return ok and c or nil
end

function M.groups()
	local list = M.available(climate())
	if S.sel > #list then S.sel = 1 end
	return list
end

local function liveCount()
	local n = 0
	for __, a in ipairs(S.added) do if a.entity ~= nil and not a.dead then n = n + 1 end end
	return n
end

--- Round 19: the added animals still there per species, in M.SPECIES order: { { key, n } }, and the total.
function M.counts()
	local by, total = {}, 0
	for __, a in ipairs(S.added) do
		if a.entity ~= nil and not a.dead then
			by[a.key] = (by[a.key] or 0) + 1
			total = total + 1
		end
	end
	local out = {}
	for __, sp in ipairs(M.SPECIES) do
		if by[sp.key] ~= nil then out[#out + 1] = { key = sp.key, n = by[sp.key] } end
	end
	return out, total
end

local function partsText(parts)
	local out = {}
	for k, v in pairs(parts or {}) do out[#out + 1] = string.format("%s %.4g", k, v) end
	table.sort(out)
	return table.concat(out, " ")
end

local function exists(e)
	if type(e) ~= "number" or e < 0 then return false end
	local ok, r = pcall(api.engine.entityExists, e)
	return ok and r == true
end

local function animalOf(e)
	if not exists(e) then return nil end
	local ok, an = pcall(api.engine.getComponent, e, api.type.ComponentType.ANIMAL)
	return ok and an or nil
end

local function fileOf(sp)
	if sp.files ~= nil and #sp.files > 0 then
		return sp.files[1 + math.floor(world.rnd() * #sp.files) % #sp.files]
	end
	return sp.file
end

--- Adds the selected group into the current view. Returns how many were sent.
function M.add()
	local list = M.groups()
	local g = list[S.sel]
	local sp = g and BY_KEY[g.sp]
	if sp == nil then return 0 end
	local ctx = camCtx()
	if ctx == nil then
		log("not added: no camera read")
		M.status = _("The camera could not be read: try again.")
		M.changed()
		return 0
	end
	local n = math.min(M.groupSize(g, world.rnd), M.PER_PRESS)
	local opts = { dist = M.DISTANCES[S.dist], form = M.FORMATIONS[S.form], face = M.FACINGS[S.face], r = g.r }
	local okP, res, why = pcall(M.place, sp, n, opts, ctx, world.rnd, probes)
	if not okP then
		log("place ERROR " .. tostring(res))
		res, why = nil, "error"
	end
	if res == nil then
		log(string.format("%s (%s): not added: %s in the view (eye %.0f,%.0f,%.0f)", g.key, sp.kind, tostring(why),
			ctx.eye.x, ctx.eye.y, ctx.eye.z))
		M.status = why == "no water" and _("No open water in the view for fish.")
			or _("No ground in the view to put animals on: tilt the camera down.")
		M.changed()
		return 0
	end
	local mid = res.mid
	local okClimate = native(sp, climate())
	log(string.format("%s (%s, %s): %d of %d placed, %s, %s, facing %s; middle %.0f,%.0f on screen %.2f,%.2f, %.1f %% "
		.. "of the screen high (asked %.1f %%), %.0f m from the eye, frame %.0f m wide; score there %.4g%s; %d rays hit",
		g.key, sp.file, sp.kind, #res.points, n, opts.dist, opts.form, opts.face, mid.x, mid.y, mid.u, mid.v,
		mid.frac * 100, res.want * 100, math.sqrt((mid.x - ctx.eye.x) ^ 2 + (mid.y - ctx.eye.y) ^ 2 + (mid.z - ctx.eye.z) ^ 2),
		res.width, mid.score, okClimate and "" or " (not this climate's animal)", res.hits))
	local t = world.nowMs()
	for __, p in ipairs(res.points) do
		local parts = nil
		if sp.kind ~= "bird" then parts = select(2, M.score(sp, p.x, p.y, probes)) end
		local rec = { key = sp.key, x = p.x, y = p.y, t0 = t, parts = parts }
		S.added[#S.added + 1] = rec
		local file = fileOf(sp)
		local ok, err = pcall(function()
			local cmd = api.cmd.makeAnimalSpawnAtCmd(file, api.type.Vec2f.new(p.x, p.y), api.type.Vec2f.new(p.look.x, p.look.y))
			api.cmd.sendCommand(cmd, function(r, success)
				local ent = nil
				pcall(function() ent = r.resultEntity end)
				rec.entity = (success and type(ent) == "number" and ent >= 0) and ent or nil
				rec.t0 = world.nowMs()
				log(string.format("spawn %s at %.0f,%.0f: ok=%s entity=%s; score parts there: %s", sp.key, p.x, p.y,
					tostring(success), tostring(ent), partsText(rec.parts)))
				M.changed()
			end)
		end)
		if not ok then log("spawn " .. sp.key .. " ERROR " .. tostring(err)) end
	end
	S.verify = { at = world.nowMs() + M.VERIFY_MS }
	if sp.kind ~= "bird" and not (finite(mid.score) and mid.score >= 0) then
		M.status = _("Added, but this spot doesn't suit them (steep ground, roads, buildings or water): they may die within seconds.")
	elseif not okClimate then
		M.status = _("Added. They don't live in this map's climate in the game; they may not stay long.")
	elseif mid.frac < M.FAR_SHARE * res.want then
		M.status = _("Added, but far from the camera: bring the camera lower or closer to see them.")
	else
		M.status = nil
	end
	M.changed()
	return #res.points
end

--- Removes the animals added this session that still exist (key: only that species; nil: all). Returns how many
--- were sent.
function M.removeAdded(key)
	local n, keep = 0, {}
	for __, a in ipairs(S.added) do
		if key ~= nil and a.key ~= key then
			keep[#keep + 1] = a
		else
			local ent = a.entity
			if ent ~= nil and not a.dead then
				if animalOf(ent) ~= nil then
					n = n + 1
					pcall(function()
						api.cmd.sendCommand(api.cmd.makeCustomEntityDestroyCmd(ent), function(__, success)
							log(string.format("remove %s entity %d: ok=%s", a.key, ent, tostring(success)))
						end)
					end)
				else
					log(string.format("remove %s entity %d: gone already (the game despawned it)", a.key, ent))
				end
			end
		end
	end
	log(string.format("remove%s: %d sent of %d added", key and (" " .. key) or "", n, #S.added - #keep))
	S.added = keep
	S.lifeNext = 1
	M.status = nil
	M.changed()
	return n
end

local function watching()
	for __, a in ipairs(S.added) do
		if a.entity ~= nil and not a.dead and not a.lifeDone then return true end
	end
	return false
end

function M.busy() return S.verify ~= nil or watching() end

--- One life check of an added animal (now ms): a death logs its lifetime, the last invalidTileElapsed and the
--- score parts at its spot; the first invalid tile is logged once; LIFE_MAX_MS alive ends the watch.
local function lifeCheck(a, now)
	local an = animalOf(a.entity)
	local p = nil
	if an ~= nil then pcall(function() p = an.worldPosition end) end
	local life = (now - (a.t0 or now)) / 1000
	if an == nil or p == nil or (a.lastX ~= nil and (p.x - a.lastX) ^ 2 + (p.y - a.lastY) ^ 2 > M.JUMP_M ^ 2) then
		a.dead = true
		log(string.format("life %s entity %d: GONE after %.0f s (last invalidTileElapsed %s, movementType %s, at %s); "
			.. "score parts at its spot: %s", a.key, a.entity, life, tostring(a.lastInvalid), tostring(a.lastMove),
			a.lastX and string.format("%.0f,%.0f", a.lastX, a.lastY) or "-", partsText(a.parts)))
		return
	end
	a.lastX, a.lastY = p.x, p.y
	pcall(function() a.lastInvalid, a.lastMove = an.invalidTileElapsed, an.movementType end)
	if finite(a.lastInvalid) and a.lastInvalid > 0 and not a.invalidSeen then
		a.invalidSeen = true
		log(string.format("life %s entity %d: on an invalid tile %.1f s after the spawn (invalidTileElapsed %.1f, "
			.. "movementType %s, at %.0f,%.0f)", a.key, a.entity, life, a.lastInvalid, tostring(a.lastMove), p.x, p.y))
	end
	if now - (a.t0 or now) >= M.LIFE_MAX_MS then
		a.lifeDone = true
		log(string.format("life %s entity %d: alive after %.0f s (invalidTileElapsed %s)", a.key, a.entity, life,
			tostring(a.lastInvalid)))
	end
end

--- Every frame while busy: VERIFY_MS after a click where each added animal is; every LIFE_MS whether each lives.
function M.step()
	local now = world.nowMs()
	local v = S.verify
	if v ~= nil and now >= v.at then
		S.verify = nil
		for __, a in ipairs(S.added) do
			if a.entity ~= nil and not a.verified and not a.dead then
				a.verified = true
				local an = animalOf(a.entity)
				local ok, txt = pcall(function()
					if an == nil then return "gone already" end
					local p = an.worldPosition
					return string.format("at %.0f,%.0f,%.0f (asked %.0f,%.0f: %.1f m off), movementType %s, speed %.2f, "
						.. "invalidTileElapsed %s", p.x, p.y, p.z, a.x, a.y, math.sqrt((p.x - a.x) ^ 2 + (p.y - a.y) ^ 2),
						tostring(an.movementType), an.movementSpeed or -1, tostring(an.invalidTileElapsed))
				end)
				log(string.format("check %s entity %d: %s", a.key, a.entity, ok and txt or ("ERROR " .. tostring(txt))))
			end
		end
	end
	if now >= S.lifeAt then
		-- round 19: a slice of at most LIFE_PER_STEP checks a frame, round robin through the list; a new round every
		-- LIFE_MS once the list is through
		local n, i, gone = 0, S.lifeNext, false
		while i <= #S.added and n < M.LIFE_PER_STEP do
			local a = S.added[i]
			if a.entity ~= nil and not a.dead and not a.lifeDone then
				lifeCheck(a, now)
				n = n + 1
				if a.dead then gone = true end
			end
			i = i + 1
		end
		if i > #S.added then
			S.lifeNext = 1
			S.lifeAt = now + M.LIFE_MS
		else
			S.lifeNext = i
		end
		if gone then M.changed() end
	end
end

--- A new game: the list belongs to the old one.
function M.reset()
	S.added, S.verify, S.lifeAt, S.lifeNext = {}, nil, 0, 1
	M.status = nil
end

local function tipFor(g, clim)
	local sp = BY_KEY[g.sp]
	local size = g.min == g.max and tostring(g.min) or (g.min .. "-" .. g.max)
	local lines = {}
	if sp.kind == "bird" then
		lines[#lines + 1] = _("Flies over the view.")
	elseif sp.kind == "fish" then
		lines[#lines + 1] = _("Swims under the surface of open water in the view.")
	elseif sp.area == ANYWHERE then
		lines[#lines + 1] = _("Stands on the ground in the view.\nLives anywhere on land.")
	else
		lines[#lines + 1] = _("Stands on the ground in the view. Lives on flat open\nground away from roads, buildings and water.")
	end
	lines[#lines + 1] = sp.flock and core.fmt(_("Each one is a whole flock or school: %s."), size)
		or core.fmt(_("How many: %s."), size)
	if not native(sp, clim) then lines[#lines + 1] = _("Not an animal of this map's climate.") end
	return table.concat(lines, "\n")
end

--- The Animals tab's rows (pm_window's helpers UI = { heading, labelled, dropdown, choiceGroup, grid, button, note }).
function M.rows(UI)
	local clim = climate()
	local list = M.groups()
	local nm = labels()
	local names, tips = {}, {}
	for i, g in ipairs(list) do
		names[i] = nm[g.key] or g.key
		tips[i] = tipFor(g, clim)
	end
	local function choice(lbls, tipsC, sel, field, labelText, tip)
		return UI.labelled(labelText, UI.choiceGroup(lbls, tipsC, sel, function(i) S[field] = i M.changed() end), tip)
	end
	local out = {
		UI.heading(_("Add animals")),
		UI.labelled(_("Animals"), UI.dropdown(names, tips, S.sel, function(i) S.sel = i M.changed() end)),
		choice({ _("Close"), _("Middle"), _("Far") },
			{ _("Close to the camera: each animal about an eighth\nof the screen high."),
				_("A little way off: each animal about a sixteenth\nof the screen high."),
				_("Farther off, small in the landscape.") }, S.dist, "dist", _("Distance"),
			_("How far from the camera they go: the size they show at.")),
		choice({ _("Group"), _("Line across"), _("Single file"), _("Spread out") },
			{ _("Together around one spot."), _("Side by side in a row across the view."),
				_("One behind the other, from the camera into the distance."),
				_("Spaced out across the whole width of the view.") }, S.form, "form", _("Formation"),
			_("How the animals of a group stand.")),
		choice({ _("Any way"), _("To the camera"), _("Side-on"), _("Away") },
			{ _("Each one faces a random way."), _("They look toward the camera."),
				_("They stand side-on to the camera, all the same way."), _("They face away from the camera.") },
			S.face, "face", _("Facing"), _("Which way they face when they appear.\nThey soon start to move.")),
		UI.grid({
			UI.button(_("Add to the view"),
				_("Adds this group where the camera looks, at the distance\nyou picked, so you can see them. They are the game's own\nanimals: they join your save and roam and leave like any other."),
				function() M.add() end, #list > 0, true),
			UI.button(_("Remove all"), _("Removes the animals added here since the game was loaded."),
				function() M.removeAdded() end, liveCount() > 0, true),
		}),
	}
	if M.status ~= nil then out[#out + 1] = UI.note(M.status) end
	-- round 19: the added ones per species, each with its own Remove
	local counts, total = M.counts()
	if total > 0 then
		local spNames = speciesNames()
		out[#out + 1] = UI.note(core.fmt(_("Added here: %d animals (a flock or school counts as one)."), total))
		for __, c in ipairs(counts) do
			local key = c.key
			out[#out + 1] = UI.labelled(spNames[key] or key, UI.button(core.fmt(_("Remove %d"), c.n),
				_("Removes the animals of this kind added here."), function() M.removeAdded(key) end, true, false))
		end
	end
	-- round 20 (user: "add note about animals dying immediately in wrong zones")
	out[#out + 1] = UI.note(_("Animals put where they can't live (steep ground, near roads, buildings or water) die within seconds and the game removes them. Horses and birds live anywhere. Fish swim under the surface."))
	return out
end

return M
