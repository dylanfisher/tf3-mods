-- Organic Towns: generated place names (pure; 2026-10-14, NEXT_PHASE_BRIEF 42).
--
-- User: "do we have an option for custom names? skip the european name set and use our own more interesting and very
-- procedural and reactive to environment names?" and "the more specific to the terrain the better". With the setting
-- "Town and stop names" = Generated names, every town of a new map gets a name built from morphemes of the name list's
-- language (ot_placename_lang: en, usa, de, fr, it, es, pt, nl, sv, nb, ja / ja_r) that fit what the mod measured at
-- the town:
--   * M.read: a cheap extra read of the town (80 height / water samples): water arms on a 450 m ring (a confluence has
--     three, a river mouth or a spring one, a bend two at an angle; their width), the ring's water share and heights at
--     1100 m (a bay, a headland, the town above / below its surroundings, a pass between two heights), the altitude.
--   * M.siteTags: fine site tags from that read plus what the driver already has (ot_terrain stats / wide survey, ot_site
--     features, the spit, the cliff, the forest share and the tree species of the forest read, size, character, era):
--     river mouth / ford / bridge / bend / confluence / spring / brook; lake / mere / pool / tarn; sandy / rocky / cliff
--     coast, bay, headland, spit, island; hilltop / slope / ridge / pass / foot / mountain, valley / vale / gorge / combe,
--     rock; marsh / fen / moor / heath; forest edge / clearing and the species (oak, ash, beech, birch, pine, fir,
--     alder, willow ...); plain / field / meadow; market, church, big, small, character, district, works, old, new.
--     Each tag has a specificity (M.SPEC): a confluence beats "river", a tarn "lake", a gorge "valley".
--   * M.assign: per town a specific part (stem) and a generic part from the language's inventory, scored by fit
--     (specificity x site weight x morpheme weight, minus a penalty for each feature the morpheme claims that the site
--     lacks: no "-mouth" inland), a bonus when the two parts name two different features ("Alderbrook Combe"-style:
--     the stem the trees, the generic the water), the town's dialect area (M.regions: 2-3 areas per map with borders
--     along the main valley or range, a Norse -by / -thorpe coast, a Saxon -ton / -ham core, a Celtic edge), rarer
--     striking forms for character towns, a penalty for parts already used on the map, and the affix of the town's shape
--     ("-on-Sea", "-upon-<River>", "Bad ...", "... an der <River>", "Saint-...", "Upper ...").
--   * Shapes first (2026-10-14, NEXT_PHASE_BRIEF 53 Part A, names/review/REVIEW_ANSWERS.md): M.planShapes hands each
--     language's share of frames, whole names, qualifiers, saints ... to the towns with the strongest claim, every other
--     town is plain (and the weakest sites quiet: no terrain word); qualifiers mark twins; each named river, lake, peak
--     or bay goes into at most two names (M.featureGrants); at most 3 words and 2 features per name.
--   * Part B (2026-10-14, review Q3 / Q6): each town has a settlement layer (M.layers: old / middle / late by size and
--     site; its parts first), the climate brings its own shape shares and forms (M.climateOf: Port X and Xtown on a
--     tropical map, the Spanish settlers of a dry US map, Fort X and Glen- in the subarctic), civic names only on late
--     towns away from confluences, a character town of a kind (town.character = "hilltop" ...) one of its kind's forms;
--     leftover feature claims go to districts and stops (M.leftClaim, M.claimName).
--   * Literal names first (2026-10-15, NEXT_PHASE_BRIEF 60, the rules "s60"; o.rules = "s53" keeps the review's rules):
--     readable site words before everything (M.siteWord), multi-word names on en / usa maps ("Oak Hill", "Mill Creek"),
--     quiet names about 10 %, opaque stems (+u, +p) at most one per 16 towns, national / dialect flavor (+n: Aber-,
--     -by, -thwaite ...) on 1-3 planned flavor towns per 16, the cue-bearing shapes up to about a third (M.quota60).
--   * Evocative names, every character town's kind, the industry as a cue (2026-10-15, NEXT_PHASE_BRIEF 61, M.RULES
--     "s61", the default): whole names that plainly describe the site on their gates ("Two Waters", "Seven Oaks"),
--     the deep forest / secluded / coastal towns' forms, the industry near a town ("Oil Springs"); see EVOC_SHARE.
--   * Rivers and lakes get names too (M.riverSystems / M.lakeSystems: towns along one river share its name, "Ashford-
--     upon-Avon", "Lindenau an der Lahn"); the driver saves them compactly (ot_saved `rv`) for the stop names. Twins
--     (M.planShapes) take their anchor's base: "Little Ashford", "Oberaschbach".
--   * Phonotactics: no triple letters, no doubled junction letters a language doesn't double, consonant clusters capped,
--     a final -e dropped before a vowel suffix, romance elision (Villa + alta = Villalta), no two parts of one class
--     ("Bridgeford"), at most MAX_BASE characters before the affix; a blocklist (offensive words, brands; substrings and
--     whole words, case-insensitive); never a name of the game's own lists (o.real) or one already on the map.
--   * Deterministic per map seed and town; unique on the map.
-- Districts and Works: M.related (the parent's stem with another generic that fits the site: Ashford -> Ashdown) and
-- M.works (an industrial stem: Coalbrookdale-style), else the composed forms of ot_district / ot_works.
-- Since 2026-10-14 (NEXT_PHASE_BRIEF 49, user: "in landscape name mode i'd prefer not to use real existing city names, and
-- instead all generated names from region and geography cues") both "Landscape names" and "Generated names" run this
-- generator, with the climate as an input of every part (ot_climate: tropical / dry / subarctic words and vetoes, the
-- finished name's word check, misfits logged on `NAMES words misfit=`) and the town's tags checked against the map
-- survey (M.agreeSurvey: no lake word without a lake). Lists without a generator language (china, korea, asia, poland,
-- russia and europe ru / ko) keep the game's names (`NAMES on=false why=untaggedList | noGenerator`); oceania speaks
-- the English generator (M.LIST_LANG).
-- Names only (strings); nothing in the world depends on them. Every loop is bounded by the inventories, MAX_TOWNS and
-- the WIDE_* caps. Plain Lua, pre-5.3.

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local LD = ug_require "square_organic_towns::/organic_towns/ot_placename_lang.lua"
local NW = ug_require "square_organic_towns::/organic_towns/ot_namewords.lua"
local CL = ug_require "square_organic_towns::/organic_towns/ot_climate.lua"

local M = {}

M.ON = true
M.MAX_TOWNS = 2000
M.MAX_BASE = 16           -- characters of the name before its affix
M.MAX_FULL = 30           -- characters of the whole name
M.MAX_KANJI = 4           -- kanji of a Japanese base
M.TOP_SPEC = 14           -- stems tried per town first ...
M.TOP_GEN = 8             -- ... with this many generics
M.WIDE_SPEC = 80          -- then this many (no unique name among the first)
M.WIDE_GEN = 40
M.JITTER = 0.2            -- seeded score jitter per town and part
M.SPEC_K = 0.8            -- the stem's fit counts this much (the generic's 1)
M.PAIR_BONUS = 0.25       -- stem and generic name two different features
M.USE_GEN = 0.45          -- per use of the generic on the map
M.USE_SPEC = 0.7          -- per use of the stem on the map
M.RARE_OFF = 0.35         -- a rare part on an ordinary town costs this; on a character town it gains RARE_ON
M.RARE_ON = 0.35
M.AFFIX_COST = 0.55       -- an affix must fit better than this (character towns: AFFIX_COST_CH)
M.USE_AFFIX = 0.35        -- per use of the affix on the map
M.AFFIX_COST_CH = 0.15
M.ANY = 0.25              -- every site's weight of "any" (personal names, neutral stems)
M.PERS_K = 0.7            -- a personal-name stem's fit counts this much (the terrain's stems first)
M.RIVER_LINK_M = 7000     -- river towns this close ...
M.RIVER_DEG = 40          -- ... along each other's river axis share one river
M.LAKE_LINK_M = 3500
M.MAX_RIVER_TOWNS = 200
M.WATER_CAP = 32          -- river / lake entries kept for the save (ot_saved `rv`)
M.ALT_HIGH = 450          -- m above the water level: mountain
M.ALT_MOOR = 200
M.ALT_TARN = 250
M.SPIT_M = 800            -- m: a spit's tip at most this far for the `spit` tag (2026-10-14)
M.OWN_RANGE = 12          -- m: the town disc's own dry height range for hill / vale (2026-10-14)
M.SPECIES_LIFT = 1.15     -- a species' share here over its map share at least this for its tag (with map totals)
M.LOW_ALT = 20            -- m above the water level: low ground for the slope weight
M.HIGH_RELH = 12          -- m above the ring for "Upper" / "Heights" / a tarn lake (2026-10-14: both fired at altitude 2)
M.BUDGET_PEN = 2.0        -- a part whose own word the map's budget holds now ranks this much lower (the search stays short)
M.FULL_MIN = 0.4          -- an affix without the base ("%t Falls", "Three Rivers", "Divide": the whole name) fits this well
-- name shapes chosen per map (2026-10-14, NEXT_PHASE_BRIEF 53 Part A, names/review/REVIEW_ANSWERS.md; M.planShapes)
M.SHAPE_SLACK = 0.05      -- a shape's count never rounds above (share + this) x towns
M.SHAPE_OVER = 1.0        -- a soft shape (separate, personal, civic) or a word over the map's count: a candidate's penalty
M.MAX_TOKENS = 3          -- words of a name at most (articles and prepositions not counted)
M.MAX_IDEAS = 2           -- features one name may name ("Mytmere-in-the-Vale": three)
M.QUIET_SHARE = 0.1       -- towns with the weakest site claims get a quiet name (no terrain word; NEXT_PHASE_BRIEF 60:
                          -- about 10 %, readable: Newton, Kingsbury; s53: QUIET_SHARE_53) ...
M.QUIET_PEN = 1.0         -- ... a part naming a feature ranks this much lower there
M.TWIN_MAX_M = 6000       -- twins (Upper / Lower, Little, North / South X) at most this far apart
M.TWIN_RATIO = 1.6        -- caps: the smaller of two towns this much smaller is the "Little" one
M.TWIN_FLOW = 0.15        -- share of the river's course between two river twins for Upper / Lower ...
M.TWIN_DZ = 25            -- ... or this many m of height
M.RIVER_QUAL_CUE = 0.6    -- Upper / Lower on a named river's stem: the town's upper / lower cue at least this
M.RIVER_QUAL_MAX = 1      -- such names per map
M.FEAT_PER = 6            -- a named feature: one town name per this many towns along it ...
M.FEAT_CAP = 2            -- ... and this many at most
M.FEAT_BONUS = 0.3        -- a granted feature's stem ranks this much higher (Arunford over a frame) ...
M.FEAT_FIRST = 1.0        -- ... the strongest claim's this much
M.CLAIM_MIN = { whole = 0.95, frame = 0.55, saint = 0.3, civic = 0.4, article = 0.3, single = 0.35, qualifier = 0.35 }
M.CLAIM_MIN_CH = 0.15     -- a character town's whole name or frame
M.SAINT_ANY = 0.1         -- a saint share this high: any town may be a saint town (fr, it, es, pt)
M.FRAME_PER = 32          -- each frame template once per this many towns (at least once)
M.NEED_WIDE = 200         -- candidates a shaped town's affix is tried on in the wide search (then plain)
-- dialect areas (Q5): 2-3 per map, borders along the main valley or range
M.DIALECT_OWN = 1.9
M.DIALECT_SHARED = 1.7
M.DIALECT_FOREIGN = 0.3
M.DIALECT_PEN = 1.5       -- a part of another area's group ranks this much lower
M.BORROW_P = 0.2          -- a town's name from the neighbouring area (about 80 % in the area's own)
M.BORDER_M = 1500         -- hybrids (Saxon + Norse) only this near a border
M.AREAS3_MIN = 10         -- towns for three areas ...
M.AREAS3_P = 0.6          -- ... seeded this often
M.FRINGE = 0.25           -- the edge area's share of the towns (three areas)
-- settlement layers and climate shape tables (2026-10-14, NEXT_PHASE_BRIEF 53 Part B, review Q3 / Q6)
M.LAYERS = { "old", "mid", "late" }
M.LAYER_OLD = 0.35        -- share of the map's towns in the oldest layer (the biggest, the crossings, mouths, markets)
M.LAYER_LATE = 0.25       -- ... in the latest (the smallest, plain sites)
M.LAYER_LATE_1900 = 0.3   -- ... on a map that starts in 1900 or later
M.LAYER_ON = 0.35         -- a part of the town's own layer ranks this much higher ...
M.LAYER_OFF = 0.2         -- ... a part only of other layers this much lower
M.LAYER_SITE = { { "ford", 1 }, { "bridge", 0.8 }, { "confluence", 1 }, { "mouth", 1 }, { "market", 0.9 }, { "big", 0.6 },
	{ "church", 0.5 }, { "twin", 0.8 } }
M.LAYER_CAP_K = 0.55      -- the oldness score: size share x this + the site's best LAYER_SITE claim x (1 - this)
M.YEAR_LATE = 1945        -- a created town (district, Works) from this year on is of the late layer, before: middle
M.CLIMATE_BOOST = 0.4     -- a climate's own form (its `boost`) ranks this much higher
M.DRY_WATER = 0.3         -- on a dry map a water part that the site has ranks this much higher (water is scarce)
M.WATER_TAG = { spring = true, brook = true, river = true, ford = true, lake = true, pool = true, mere = true, falls = true }
M.CIVIC_CONFLUENCE = 0.2  -- a town with a confluence claim this high is a natural confluence: never a civic name
M.GLAYER_K = 1.2          -- a climate's settler group (`group`, the Spanish of a dry US map): its towns' parts rank this
                          -- much higher there, and DIALECT_PEN lower on every other town
-- literal, context-aware names first, a little national flavor (2026-10-15, NEXT_PHASE_BRIEF 60; user: "i think more
-- literal representation of surrounding it more fun ... maybe we just really push the simple context aware naming and
-- then just a little nationality mixed in" and "descriptive names and multi word names that help make it clear its
-- context-aware"). The rules of NEXT_PHASE_BRIEF 53 (the naming review's gazetteer realism: 40 % quiet names, dialect
-- stems and personal names everywhere) stay selectable as o.rules = "s53" for the name lab's comparison.
M.RULES = "s61"           -- (NEXT_PHASE_BRIEF 61; "s60" the §60 rules, "s53" the review's)
M.QUIET_SHARE_53 = 0.4    -- (s53) the quiet share of the review
M.OPAQUE_PER = 16         -- opaque stems (+p personal names, +u morphemes: Myt-, Twy-, Ac-, Pad-, Ulf-, Trefach) at most
M.OPAQUE_PEN = 2.0        -- one per this many towns (at least one per map); each ranks this much lower
M.FLAVOR_SHARE = 0.125    -- national / dialect flavor (+n parts: Aber-, Llan-, Kirk-, -by, -thwaite, -beck ...): about 2
M.FLAVOR_MAX = 3          -- per 16 towns, at most FLAVOR_MAX per 16; on the planned flavor towns only ...
M.FLAVOR_ON = 0.6         -- ... where such a part ranks this much higher
M.FLAVOR_MIN = 0.3        -- a flavor town's claim (its best +n part's fit) at least this
M.CUE_K = { whole = 3, qualifier = 2, frame = 2.5 }   -- the cue-bearing shapes' shares x this ...
M.CUE_CAP = 0.12          -- ... each at most this (or its old share) ...
M.CUE_TOTAL = 0.34        -- ... together at most about a third of the towns
M.SHAPE_K60 = { personal = 0.25, single = 0.4, saint = 0.4 }  -- personal-name, lone-element and saint shapes rarer
M.SEP60 = { en = 0.32, usa = 0.36 }                   -- multi-word names ("Oak Hill", "Stony Brook", "Mill Creek") ...
M.WORDS60 = { en = 1.6, usa = 1.7 }                   -- ... and the words per name they need (en / usa) ...
M.LITERAL_PEN = 0.5       -- a pair of parts that names no feature, on a town that is not quiet, ranks this much lower
M.SEP_BONUS = 0.35        -- ... and a multi-word candidate ranks this much higher while the map's count lasts
-- tags that make no site word (a readable site word names what the town has: trees, water, land, coast, human marks)
M.READ_SKIP = { any = true, new = true, old = true, big = true, small = true, character = true, district = true,
	works = true, plain = true, dir = true, north = true, south = true, east = true, west = true, central = true,
	tropic = true, arid = true, boreal = true }
-- evocative environment names, every character town's kind, the industry as a cue (2026-10-15, NEXT_PHASE_BRIEF 61;
-- user after run 0429: "i like two waters name a lot. anything that is kind of obviously part of the environment is
-- neat", "if character names don't already factor into city name that would be cool, too" and "city name could
-- potentially take into account what type of industry they are"). The rules "s61" (default) add them to "s60"; the
-- languages' `affix61` lines (each +61) and `charForms61` only count under them.
--   * evocative names (+g: shape "evoc"): a whole name that plainly describes the site ("Two Waters", "Seven Oaks",
--     "Windy Ridge", "Sandy Point"), only where its gate holds (?tag[:min] on the town's own reading, before the
--     tags' rarity; ?a|b either; ?lakes2 two lakes near, the survey), about EVOC_SHARE of the towns, each once;
--   * every character town of a kind takes one of its kind's forms; the s61 kinds (KINDS61): deep forest ("forest"),
--     the secluded character towns ("secluded") and the coastal hugger ("coastal");
--   * the industry as a cue (+i !<family>: shape "industry"): a town with an industry of a cue family near (the
--     driver's t.ind = { fam, d }) may take one of its family's forms ("Oil Springs", "Brickfield"), at most IND_PER16
--     per 16 towns (at least one per map), one per family.
M.EVOC_SHARE = 0.21       -- evocative names: about this share of the towns ...
M.EVOC_MAX = 0.25         -- ... at most this share
M.EVOC_MIN = 0.5          -- a gate tag's weight (before rarity) at least this (or the gate's own :min)
M.EVOC_CLAIM = 0.5        -- an evocative name's fit at least this for the plan to hand it
M.EVOC_RIVER = 0.3        -- a town granted its river spends it: an evocative name ranks this much lower there
M.EVOC_SEP = 1.0          -- each multi-word evocative name the plan hands takes this many separate names off the count
M.IND_SHARE = 0.09        -- industry cue names: about this share of the towns (1.4 per 16) ...
M.IND_PER16 = 2           -- ... at most this many per 16 towns
M.IND_R = 1500            -- m: an industry this near the town centre is its cue (the driver's t.ind.d)
M.IND_FAM_K = { fish = 1.0, oil = 1.0, coal = 0.95, iron = 0.95, clay = 0.9, stone = 0.85, timber = 0.8, farm = 0.55 }
M.KINDS61 = { forest = true, secluded = true, coastal = true }
M.WORDS61 = { en = 1.75 }                             -- en words per name under s61 (more whole names; usa keeps 1.7)

---------------------------------------------------------------------------
-- tags

M.SPECIES = { "oak", "ash", "beech", "birch", "elm", "lime", "maple", "hazel", "alder", "willow", "poplar", "pine", "fir",
	"spruce", "larch", "yew", "holly", "apple", "elder", "palm", "cypress" }
M.TAGS = { "river", "mouth", "ford", "bridge", "bend", "confluence", "spring", "brook",
	"lake", "mere", "pool", "tarn",
	"coast", "sandy", "rocky", "cliff", "bay", "headland", "spit", "island",
	"hill", "hilltop", "slope", "ridge", "pass", "foot", "mountain", "valley", "vale", "gorge", "combe", "rock",
	"marsh", "fen", "moor", "heath",
	"forest", "edge", "clearing" }
for _, s in ipairs(M.SPECIES) do M.TAGS[#M.TAGS + 1] = s end
-- the climate (2026-10-14, NEXT_PHASE_BRIEF 49, ot_climate): the climate's own tag and its features
M.CLIMATE_TAGS = { "tropic", "arid", "boreal", "reef", "lagoon", "mangrove", "dune", "mesa", "wadi", "snow" }
for _, t in ipairs(M.CLIMATE_TAGS) do M.TAGS[#M.TAGS + 1] = t end
-- the map survey's cues (ot_mapshape.townCues, 2026-10-14 NEXT_PHASE_BRIEF 45): the compass on the map, the river's
-- course, the big named features
M.CUE_TAGS = { "north", "south", "east", "west", "central", "dir", "upper", "lower", "falls", "twin", "summit", "divide",
	"peak", "range", "mainvalley", "biglake", "bigbay", "narrows", "isthmus" }
for _, t in ipairs(M.CUE_TAGS) do M.TAGS[#M.TAGS + 1] = t end
for _, t in ipairs({ "plain", "field", "meadow", "market", "church", "big", "small", "character", "district", "works",
	"old", "new", "any" }) do M.TAGS[#M.TAGS + 1] = t end
M.TAG_INDEX = {}
for i, t in ipairs(M.TAGS) do M.TAG_INDEX[t] = i end

-- a fine tag's broader ones (a "river" morpheme fits a confluence; a confluence morpheme doesn't fit any river)
M.PARENT = { mouth = { "river", "coast" }, ford = { "river" }, bridge = { "river" }, bend = { "river" },
	confluence = { "river" }, spring = { "brook" }, brook = { "river" }, mere = { "lake" }, pool = { "lake" },
	tarn = { "lake" }, sandy = { "coast" }, rocky = { "coast" }, cliff = { "rocky" }, bay = { "coast" },
	headland = { "coast" }, spit = { "headland" }, island = { "coast" }, hilltop = { "hill" }, slope = { "hill" },
	ridge = { "hill" }, pass = { "hill" }, foot = { "hill" }, mountain = { "hill" }, vale = { "valley" },
	gorge = { "valley" }, combe = { "valley" }, rock = { "hill" }, fen = { "marsh" }, moor = { "heath" },
	edge = { "forest" }, clearing = { "forest" }, field = { "plain" }, meadow = { "plain" }, big = { "market" } }
for _, s in ipairs(M.SPECIES) do M.PARENT[s] = { "forest" } end
-- (cues: an upper-course town fits the "Upper" / "Ober-" / "-le-Haut" forms of a slope, a lower one the foot's; the
-- compass sides are each a direction)
M.PARENT.north, M.PARENT.south, M.PARENT.east, M.PARENT.west = { "dir" }, { "dir" }, { "dir" }, { "dir" }
M.PARENT.upper, M.PARENT.lower = { "slope" }, { "foot" }
M.PARENT.falls, M.PARENT.twin = { "river" }, { "river" }
M.PARENT.summit, M.PARENT.divide, M.PARENT.peak, M.PARENT.range = { "hilltop" }, { "ridge" }, { "mountain" }, { "foot" }
M.PARENT.mainvalley, M.PARENT.biglake, M.PARENT.bigbay = { "valley" }, { "lake" }, { "bay" }
M.PARENT.narrows, M.PARENT.isthmus = { "coast" }, { "headland" }
M.PARENT.reef, M.PARENT.lagoon, M.PARENT.mangrove, M.PARENT.dune = { "coast" }, { "bay" }, { "marsh" }, { "sandy" }
M.PARENT.mesa, M.PARENT.wadi, M.PARENT.snow = { "hilltop" }, { "valley" }, { "mountain" }

-- specificity: the most distinctive feature present wins
M.SPEC = { river = 0.9, mouth = 1.5, ford = 1.1, bridge = 1.0, bend = 1.2, confluence = 1.6, spring = 1.4, brook = 1.1,
	lake = 1.0, mere = 1.2, pool = 1.3, tarn = 1.6, coast = 0.9, sandy = 1.1, rocky = 1.1, cliff = 1.4, bay = 1.3,
	headland = 1.4, spit = 1.5, island = 1.6, hill = 0.9, hilltop = 1.3, slope = 1.0, ridge = 1.3, pass = 1.6,
	foot = 1.3, mountain = 1.3, valley = 1.0, vale = 1.1, gorge = 1.6, combe = 1.4, rock = 1.1, marsh = 1.0, fen = 1.2,
	moor = 1.2, heath = 1.1, forest = 0.9, edge = 1.0, clearing = 1.2, plain = 0.6, field = 0.7, meadow = 0.8,
	market = 0.8, church = 0.8, big = 0.8, small = 0.8, character = 1.0, district = 0.8, works = 0.9, old = 0.7,
	new = 0.7, any = 1.0 }
for _, s in ipairs(M.SPECIES) do M.SPEC[s] = 1.2 end
for t, v in pairs({ north = 0.8, south = 0.8, east = 0.8, west = 0.8, central = 0.7, dir = 0.7, upper = 1.1, lower = 1.1,
	falls = 1.6, twin = 1.5, summit = 1.4, divide = 1.6, peak = 1.5, range = 1.1, mainvalley = 1.2, biglake = 1.2,
	bigbay = 1.3, narrows = 1.6, isthmus = 1.6 }) do M.SPEC[t] = v end
for t, v in pairs({ tropic = 0.8, arid = 0.8, boreal = 0.8, reef = 1.3, lagoon = 1.4, mangrove = 1.4, dune = 1.3,
	mesa = 1.4, wadi = 1.4, snow = 1.2 }) do M.SPEC[t] = v end

-- what a morpheme costs per unit weight when it claims a feature the site lacks
M.CONTRA = {}
for _, t in ipairs({ "river", "mouth", "ford", "bridge", "bend", "confluence", "brook", "lake", "mere", "pool", "tarn",
	"coast", "sandy", "rocky", "cliff", "bay", "headland", "spit", "island" }) do M.CONTRA[t] = 1.0 end
for _, t in ipairs({ "valley", "vale", "gorge", "combe", "hill", "hilltop", "slope", "ridge", "pass", "foot", "mountain",
	"rock", "marsh", "fen", "moor" }) do M.CONTRA[t] = 0.6 end
M.CONTRA.spring = 0.4
for _, t in ipairs({ "forest", "edge", "clearing", "heath", "meadow" }) do M.CONTRA[t] = 0.3 end
for _, s in ipairs(M.SPECIES) do M.CONTRA[s] = 0.2 end
M.CONTRA.small, M.CONTRA.big, M.CONTRA.new, M.CONTRA.old = 0.4, 0.3, 0.3, 0.2
-- (a "North ..." name in the south, "Falls" without falls: as wrong as "-mouth" inland)
for t, v in pairs({ north = 1.0, south = 1.0, east = 1.0, west = 1.0, central = 0.6, dir = 0.8, upper = 0.6, lower = 0.6,
	falls = 1.0, twin = 1.0, summit = 0.6, divide = 0.8, peak = 0.8, range = 0.6, mainvalley = 0.5, biglake = 1.0,
	bigbay = 1.0, narrows = 1.0, isthmus = 1.0 }) do M.CONTRA[t] = v end
-- (a climate word on another climate's map: never; its features as wrong as "-mouth" inland)
for t, v in pairs({ tropic = 3.0, arid = 3.0, boreal = 3.0, reef = 1.0, lagoon = 1.0, mangrove = 1.0, dune = 0.8,
	mesa = 0.8, wadi = 0.8, snow = 0.6 }) do M.CONTRA[t] = v end

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

-- A seeded draw for the map's plan (2026-10-14, NEXT_PHASE_BRIEF 53): ot_rng's unit is close to linear in its first
-- number (seeds 38, 75, 112 ... gave 0.15, 0.17, 0.18 ...: every test map drew the same shape counts). The seed and the
-- item go through the hash once more, as numbers it splits into pieces.
local function draw(seed, item, salt)
	return rng.unit(rng.hash(rng.hash(seed, "plan53"), item or 0), salt)
end
M.draw = draw

---------------------------------------------------------------------------
-- strings

local UP = { ["à"] = "À", ["á"] = "Á", ["â"] = "Â", ["ä"] = "Ä", ["å"] = "Å", ["æ"] = "Æ", ["ç"] = "Ç", ["è"] = "È",
	["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ñ"] = "Ñ", ["ó"] = "Ó", ["ô"] = "Ô", ["ö"] = "Ö", ["ø"] = "Ø", ["ú"] = "Ú",
	["ü"] = "Ü", ["ō"] = "Ō", ["ū"] = "Ū" }
local DOWN = {}
for k, v in pairs(UP) do DOWN[v] = k end

local function firstChar(s)
	local c = s:sub(1, 1)
	if c:byte() and c:byte() >= 192 then
		local n = c:byte() >= 240 and 4 or (c:byte() >= 224 and 3 or 2)
		return s:sub(1, n), s:sub(n + 1)
	end
	return c, s:sub(2)
end

--- First letter in upper / lower case (ASCII and the Latin-1 / macron letters the inventories use).
function M.capFirst(s)
	if s == "" then return s end
	local c, rest = firstChar(s)
	return (UP[c] or c:upper()) .. rest
end
function M.lowerFirst(s)
	if s == "" then return s end
	local c, rest = firstChar(s)
	if #c == 1 then return c:lower() .. rest end
	return (DOWN[c] or c) .. rest
end

local LOWER = {}
for c = 65, 90 do LOWER[string.char(c)] = string.char(c + 32) end
local function lower(s) return (s:gsub("[A-Z]", LOWER)) end
local function lowerAll(s)
	s = lower(s)
	return (s:gsub("[\195\197][\128-\191]", function(ch) return DOWN[ch] or ch end))
end
M.lowerAll = lowerAll

--- Characters of a UTF-8 string.
function M.chars(s)
	local _, n = tostring(s or ""):gsub("[^\128-\191]", "")
	return n
end

local function split(s, sep)
	local out = {}
	if type(s) ~= "string" or s == "" then return out end
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return out
end

---------------------------------------------------------------------------
-- inventories (parsed once per language)

M.BAD = {}   -- unknown tags met while parsing (the tests require none)

local function newEntry(text)
	return { text = text, tl = {}, flags = {} }
end

local function parseTags(toks, i0, e)
	for i = i0, #toks do
		local t = toks[i]
		local c = t:sub(1, 1)
		if c == "@" then e.grp = t:sub(2)
		elseif t == "*" then e.rare = true
		elseif c == "=" then e.cls = t:sub(2)
		elseif c == "+" then e.flags[t:sub(2)] = true
		elseif c == "~" then e.gender = t:sub(2)
		-- (NEXT_PHASE_BRIEF 61: ?tag[:min] an evocative name's gate on the town's reading, !fam an industry form's family)
		elseif c == "?" then
			e.gate = e.gate or {}
			local alts, mn = t:sub(2):match("^([%a_|%d]+):?([%d%.]*)$")
			if alts then
				local g = { min = tonumber(mn) }
				for a in alts:gmatch("[^|]+") do g[#g + 1] = a end
				e.gate[#e.gate + 1] = g
			else
				M.BAD[#M.BAD + 1] = t
			end
		elseif c == "!" then e.fam = t:sub(2)
		else
			local name, w = t:match("^([%a_]+):?([%d%.]*)$")
			if name and M.TAG_INDEX[name] then
				e.tl[#e.tl + 1] = { name, tonumber(w) or 1 }
			else
				M.BAD[#M.BAD + 1] = t
			end
		end
	end
	-- expanded: own tags and their parents (x 0.5), tag order
	local x = {}
	for _, p in ipairs(e.tl) do
		local t, w = p[1], p[2]
		if (x[t] or 0) < w then x[t] = w end
		local function up(tag, f, depth)
			for _, par in ipairs(M.PARENT[tag] or {}) do
				if (x[par] or 0) < w * f then x[par] = w * f end
				if depth < 3 then up(par, f * 0.5, depth + 1) end
			end
		end
		up(t, 0.5, 1)
	end
	e.x = {}
	for _, t in ipairs(M.TAGS) do if x[t] then e.x[#e.x + 1] = { t, x[t] } end end
	-- the best own tag (log, the pair bonus)
	local bt, bw = nil, -1
	for _, p in ipairs(e.tl) do if p[2] > bw and p[1] ~= "any" then bt, bw = p[1], p[2] end end
	e.main = bt
end

local function lines(s)
	local out = {}
	for line in (s or ""):gmatch("[^\n]+") do
		local toks = {}
		-- (explicit blanks: %S is locale-dependent and a UTF-8 locale counts some continuation bytes as space)
		for tok in line:gmatch("[^ \t\r]+") do toks[#toks + 1] = tok end
		if #toks > 0 then out[#out + 1] = toks end
	end
	return out
end

local function parseSpec(toks, script)
	local raw = toks[1]
	local e
	if script then
		local k, r = raw:match("^([^/]+)/(.+)$")
		e = newEntry(k)
		e.k, e.r, e.kind = k, r, "stem"
	elseif raw:find("|", 1, true) then
		e = newEntry(raw)
		e.forms = split(raw, "|")
		e.text = e.forms[1]
		e.kind = "adj"
	else
		e = newEntry((raw:gsub("_", " ")))
		e.kind = (e.text:find(" ", 1, true) and e.text:sub(1, 1):match("[a-z]")) and "phrase" or "stem"
	end
	parseTags(toks, 2, e)
	if e.flags.j then e.kind = "noun" end
	return e
end

local function parseGen(toks, script)
	local raw = toks[1]
	local e
	if script then
		local k, r, rd = raw:match("^([^/]+)/([^/]+)/(.+)$")
		e = newEntry(k)
		e.k, e.r, e.rd, e.form = k, r, rd, "ja"
	elseif raw:sub(1, 1) == "-" then
		e = newEntry(raw:sub(2))
		e.form = "suf"
	elseif raw:sub(1, 1) == "_" then
		e = newEntry((raw:sub(2):gsub("_", " ")))
		e.form = "after"
	elseif raw:sub(-1) == "_" then
		e = newEntry((raw:sub(1, -2):gsub("_", " ")))
		e.form = "before"
	elseif raw:sub(-1) == "^" then
		e = newEntry(raw:sub(1, -2))
		e.form = "pre"
	elseif raw:sub(-1) == "-" then
		e = newEntry(raw)
		e.form = "hyph"
	else
		e = newEntry(raw)
		e.form = "after"
	end
	e.raw = raw
	parseTags(toks, 2, e)
	return e
end

local function parseAffix(toks, script)
	local raw = toks[1]
	local e
	if script then
		local k, r = raw:match("^([^/]+)/(.+)$")
		e = newEntry(k)
		e.k, e.r = k, r
	else
		e = newEntry((raw:gsub("_", " ")))
	end
	e.raw = raw
	e.needR = (e.text:find("%r", 1, true) or (e.r or ""):find("%r", 1, true)) ~= nil
	e.needK = e.text:find("%k", 1, true) ~= nil
	e.needP = e.text:find("%p", 1, true) ~= nil
	-- (2026-10-14, the map survey: %t the river's stem, %m / %M the mountain's stem / name, %b / %B the bay's, %D the
	-- town's compass side on the map, %E its side of the big lake)
	e.needT = e.text:find("%t", 1, true) ~= nil or (e.r or ""):find("%t", 1, true) ~= nil
	e.needM = e.text:find("%m", 1, true) ~= nil or e.text:find("%M", 1, true) ~= nil
	e.needB = e.text:find("%b", 1, true) ~= nil or e.text:find("%B", 1, true) ~= nil
	e.needD = e.text:find("%D", 1, true) ~= nil
	e.needE = e.text:find("%E", 1, true) ~= nil
	e.hasS = e.text:find("%s", 1, true) ~= nil or e.text:find("%l", 1, true) ~= nil
	parseTags(toks, 2, e)
	-- (2026-10-14, NEXT_PHASE_BRIEF 50: a bare one-word whole name, "Narrows", "Divide", "Summit", reads unfinished: it
	-- takes the town's own name in front, "Ashford Narrows"; NEXT_PHASE_BRIEF 61: never an evocative or industry name,
	-- "Watersmeet", "Brickfield", which are whole words)
	if not script and not e.hasS and not e.text:find("%", 1, true) and not e.text:find("[ %-]") and not e.flags.g
		and not e.flags.i then
		e.bare = e.text
		e.text = "%s " .. e.text
		e.hasS = true
	end
	return e
end

local CACHE = {}

--- The compiled inventory of generator language id (nil: none).
function M.lang(id)
	local base = id == "ja_r" and "ja" or id
	if CACHE[id] then return CACHE[id] end
	local D = LD[base or ""]
	if D == nil or type(D) ~= "table" or D.spec == nil then return nil end
	local L = { id = id, data = D, script = D.script and (id == "ja" and "kanji" or "romaji") or nil, specs = {}, gens = {},
		affixes = {}, maxCons = D.maxCons or 3, dbl = D.dbl or "", dropE = D.dropE, vv = D.vv, pOnly = D.pOnly, noPhrasePre = D.noPhrasePre }
	for _, toks in ipairs(lines(D.spec)) do L.specs[#L.specs + 1] = parseSpec(toks, D.script) end
	for _, toks in ipairs(lines(D.gen)) do L.gens[#L.gens + 1] = parseGen(toks, D.script) end
	for _, toks in ipairs(lines(D.affix)) do L.affixes[#L.affixes + 1] = parseAffix(toks, D.script) end
	-- (NEXT_PHASE_BRIEF 61: the s61 lines, each +61: evocative names, the new kinds' forms, the industry forms)
	for _, toks in ipairs(lines(D.affix61)) do
		local a = parseAffix(toks, D.script)
		a.flags["61"] = true
		L.affixes[#L.affixes + 1] = a
	end
	L.saints = split(D.saints, "|")
	-- (2026-10-14, NEXT_PHASE_BRIEF 53: shapes, areas, common bases, articles)
	L.quota = {}
	for sh, v in tostring(D.shapes or ""):gmatch("([%a_]+):([%d%.]+)") do L.quota[sh] = tonumber(v) end
	L.common = split(D.common, "|")
	L.areas = D.areas
	L.shared = {}
	for _, g in ipairs(split(D.shared, "|")) do L.shared[g] = true end
	L.articles = D.articles
	-- (NEXT_PHASE_BRIEF 53 Part B: each layer's raw gens / affixes, "+p" for the personal stems; the character kinds'
	-- raw affixes)
	L.layerSet, L.layerAny, L.layerP = {}, {}, {}
	for _, lay in ipairs(M.LAYERS) do
		local set = {}
		for tok in tostring((type(D.layers) == "table" and D.layers[lay]) or ""):gmatch("[^ \t\r\n]+") do
			if tok == "+p" then L.layerP[lay] = true else set[tok] = true; L.layerAny[tok] = true end
		end
		L.layerSet[lay] = set
	end
	L.charForms = {}
	if type(D.charForms) == "table" then
		for kind, cs in pairs(D.charForms) do
			local set = {}
			for tok in tostring(cs):gmatch("[^ \t\r\n]+") do set[tok] = true end
			L.charForms[kind] = set
		end
	end
	-- (NEXT_PHASE_BRIEF 61: the s61 kinds' forms, per kind replacing the base set)
	L.charForms61 = {}
	for kind, set in pairs(L.charForms) do L.charForms61[kind] = set end
	if type(D.charForms61) == "table" then
		for kind, cs in pairs(D.charForms61) do
			local set = {}
			for tok in tostring(cs):gmatch("[^ \t\r\n]+") do set[tok] = true end
			L.charForms61[kind] = set
		end
	end
	for _, a in ipairs(L.affixes) do M.affixShape(a) end
	L.groups = {}
	do
		local seen = {}
		local function addG(g) if g and not seen[g] then seen[g] = true; L.groups[#L.groups + 1] = g end end
		if type(D.areas) == "table" then
			addG(D.areas.core); addG(D.areas.coast)
			for _, g in ipairs(D.areas.edge or {}) do addG(g) end
		end
		for _, e in ipairs(L.specs) do addG(e.grp) end
		for _, e in ipairs(L.gens) do addG(e.grp) end
	end
	-- (dialect groups that may meet in one name, NEXT_PHASE_BRIEF 50 item 3)
	L.compatSet = {}
	for _, pr in ipairs(D.compat or {}) do
		local a, b = pr:match("^([^:]+):([^:]+)$")
		if a then L.compatSet[a .. ":" .. b], L.compatSet[b .. ":" .. a] = true, true end
	end
	-- compass words for %D / %E ("North|South|East|West")
	L.dirWords = {}
	local dw = split(D.dirs, "|")
	for i, t in ipairs({ "north", "south", "east", "west" }) do if dw[i] then L.dirWords[t] = dw[i] end end
	-- works stems per industry kind
	L.works = {}
	for kind, s in pairs(D.works or {}) do
		local list = {}
		for _, w in ipairs(split(s, "|")) do
			local e
			if D.script then
				local k, r = w:match("^([^/]+)/(.+)$")
				e = newEntry(k or w)
				e.k, e.r = k or w, r or w
			else
				e = newEntry(w)
			end
			e.kind = "stem"
			parseTags({ w, "works" }, 2, e)
			list[#list + 1] = e
		end
		L.works[kind] = list
	end
	L.worksGens = {}
	for _, g in ipairs(split(D.worksGens, "|")) do L.worksGens[#L.worksGens + 1] = parseGen({ g, "works:.5", "any:.5" }, D.script) end
	-- (NEXT_PHASE_BRIEF 60: does the language have flavor parts, +n)
	L.hasFlavor = false
	for _, e in ipairs(L.specs) do if e.flags.n then L.hasFlavor = true end end
	for _, e in ipairs(L.gens) do if e.flags.n then L.hasFlavor = true end end
	-- the stem index (longest first) for M.stemOf
	L.byLen = {}
	for _, e in ipairs(L.specs) do if e.kind == "stem" and not e.flags.c then L.byLen[#L.byLen + 1] = e end end
	table.sort(L.byLen, function(a, b)
		local ta, tb = a.k or a.text, b.k or b.text
		if #ta ~= #tb then return #ta > #tb end
		return ta < tb
	end)
	CACHE[id] = L
	return L
end

--- The language's table for a climate (2026-10-14, NEXT_PHASE_BRIEF 53 Part B, review Q6: climate as shape, not just
--- words): quota (the shape shares: the climate's `shapes`, else the language's), words (per name at most), boost /
--- veto (sets of raw gens / affixes), shared (groups that go with every dialect area), saints, areas, three (always three
--- areas). Cached per language and climate.
function M.climateOf(L, climate)
	if L == nil then return nil end
	L.clim = L.clim or {}
	local key = climate or "temperate"
	if L.clim[key] then return L.clim[key] end
	local C = type(L.data.climate) == "table" and L.data.climate[key] or nil
	local out = { quota = L.quota, words = tonumber(L.data.words), boost = {}, veto = {}, shared = {}, saints = L.saints,
		areas = L.areas, three = false }
	if type(C) == "table" then
		if C.shapes then
			out.quota = {}
			for sh, v in tostring(C.shapes):gmatch("([%a_]+):([%d%.]+)") do out.quota[sh] = tonumber(v) end
		end
		if tonumber(C.words) then out.words = tonumber(C.words) end
		for tok in tostring(C.boost or ""):gmatch("[^ \t\r\n]+") do out.boost[tok] = true end
		for tok in tostring(C.veto or ""):gmatch("[^ \t\r\n]+") do out.veto[tok] = true end
		for _, g in ipairs(split(C.shared, "|")) do out.shared[g] = true end
		if C.saints then out.saints = split(C.saints, "|") end
		if type(C.areas) == "table" then out.areas = C.areas end
		out.three = C.three == true
		-- (a settler group on one side of the map: "spanish:.3", the share of the towns)
		local gg, gs = tostring(C.group or ""):match("^([%a_]+):([%d%.]+)$")
		if gg then out.group = { grp = gg, share = tonumber(gs) } end
	end
	L.clim[key] = out
	return out
end

--- The layer bonus of entry e for a town of layer lay (M.LAYERS): LAYER_ON for a part of that layer, -LAYER_OFF for a
--- part only of others, 0 for the rest (a personal stem: the layers with "+p").
function M.layerAdj(L, e, lay)
	if L == nil or lay == nil or L.layerSet == nil then return 0 end
	local own, any = false, false
	if e.raw then
		own = L.layerSet[lay] ~= nil and L.layerSet[lay][e.raw] == true
		any = L.layerAny[e.raw] == true
	elseif e.flags and e.flags.p then
		own = L.layerP[lay] == true
		any = L.layerP.old == true or L.layerP.mid == true or L.layerP.late == true
	end
	if own then return M.LAYER_ON end
	if any then return -M.LAYER_OFF end
	return 0
end

--- An opaque part (NEXT_PHASE_BRIEF 60): a personal-name stem or generic (+p: Pad-, Kel-, Hayes-, -ington, -ac) or a
--- morpheme a reader can't read (+u: Myt-, Twy-, Ac-, the Celtic fach / wyn / garth).
function M.opaque(e)
	return type(e) == "table" and type(e.flags) == "table" and (e.flags.p == true or e.flags.u == true)
end

--- A national / dialect flavor part (+n: Aber-, Llan-, Kirk-, -by, -thwaite, -beck; de -reuth, -büttel ...).
function M.flavorPart(e)
	return type(e) == "table" and type(e.flags) == "table" and e.flags.n == true
end

--- The shape shares of the s60 rules (NEXT_PHASE_BRIEF 60) from a language's / climate's table Q: the cue-bearing
--- shapes (whole, qualifier, frame) x CUE_K, each at most CUE_CAP (or its old share), together at most CUE_TOTAL;
--- personal and single shapes x SHAPE_K60; en / usa multi-word names (separate) at least SEP60. Returns a new table.
function M.quota60(Q, lang)
	local out = {}
	for k, v in pairs(Q or {}) do out[k] = v end
	local sum = 0
	for sh, k in pairs(M.CUE_K) do
		local v = out[sh]
		if v and v > 0 then
			out[sh] = math.min(v * k, math.max(v, M.CUE_CAP))
			sum = sum + out[sh]
		end
	end
	if sum > M.CUE_TOTAL then
		for sh in pairs(M.CUE_K) do if out[sh] then out[sh] = math.max(Q[sh], out[sh] * M.CUE_TOTAL / sum) end end
	end
	for sh, k in pairs(M.SHAPE_K60) do if out[sh] then out[sh] = out[sh] * k end end
	local sep = M.SEP60[lang or ""]
	if sep and out.separate then out.separate = math.max(out.separate, sep) end
	return out
end

--- Is there a readable site word in a name (NEXT_PHASE_BRIEF 60 item 7)? info = nameTown's info, w = the town's site
--- weights with the survey's cues. A part counts when it is no opaque or flavor part and its main tag (not READ_SKIP:
--- -ton's plain is none) is on the site (>= 0.2, its broader tags too); a named feature (the river's stem, -on-%r,
--- %t Head, Mount %m, the big lake's side) always counts.
function M.siteWord(info, w)
	if type(info) ~= "table" then return false end
	local x = M.expandSite(w or {})
	local function partOk(e)
		if type(e) ~= "table" or e.text == "-" or e.tl == nil then return false end
		if e.river then return true end
		if M.opaque(e) or M.flavorPart(e) or (e.flags and e.flags.c) then return false end
		local t = e.main
		return t ~= nil and not M.READ_SKIP[t] and (x[t] or 0) >= 0.2
	end
	if partOk(info.sE) or partOk(info.gE) then return true end
	local a = info.aE
	if type(a) == "table" then
		if a.needR or a.needT or a.needK or a.needM or a.needB or a.needE then return true end
		if info.twin == nil and partOk(a) then return true end
	end
	return false
end

-- name list classifier (ot_names.classOf) -> generator language; nil = no generator (landscape names instead)
M.GEN_OF_CLS = { en = "en", usa = "usa", de = "de", fr = "fr", it = "it", es = "es", pt = "pt", nl = "nl", sv = "sv",
	nb = "nb", ja = "ja", ja_r = "ja_r" }
M.LANGS = { "en", "usa", "de", "fr", "it", "es", "pt", "nl", "sv", "nb", "ja", "ja_r" }

--- The generator language for a name list classifier, or nil and why ("noGenerator").
-- lists the generator speaks without an ot_names classifier (2026-10-14, NEXT_PHASE_BRIEF 49: oceania in the English
-- settler style)
M.LIST_LANG = { oceania = "en" }
function M.listLang(path) return M.LIST_LANG[path or ""] end
M.climateKey = CL.key

function M.langOf(cls)
	local g = M.GEN_OF_CLS[cls or ""]
	if g == nil then return nil, "noGenerator" end
	return g, nil
end

---------------------------------------------------------------------------
-- the extra read (cheap: 48 + 32 water tests, 33 heights)

M.ARM_R = 450
M.ARM_N = 48
M.RING_R = 1100
M.RING_N = 32
M.PASS_UP = 15
M.PASS_DOWN = 10

--- { arms (wet runs on the 450 m ring; -1 all wet), armDeg (angle between two arms), width (m, rough), ringWet (share
--- at 1100 m), relH (m: the centre above the ring's dry mean), pass = bool, alt (m above the water level) } or nil.
function M.read(s, cx, cy)
	if type(s) ~= "table" or type(s.height) ~= "function" then return nil end
	local out = {}
	local hc = s.height(cx, cy)
	local wet, nWet = {}, 0
	for k = 0, M.ARM_N - 1 do
		local a = k / M.ARM_N * 2 * math.pi
		wet[k] = T.isWater(s, cx + math.cos(a) * M.ARM_R, cy + math.sin(a) * M.ARM_R)
		if wet[k] then nWet = nWet + 1 end
	end
	if nWet == M.ARM_N then
		out.arms = -1
	else
		local start = 0
		while wet[start] do start = start + 1 end
		local runs, cur = {}, nil
		for i = 1, M.ARM_N do
			local k = (start + i) % M.ARM_N
			if wet[k] then
				if cur == nil then cur = { a = k, n = 0 } end
				cur.n = cur.n + 1
			elseif cur then
				runs[#runs + 1] = cur
				cur = nil
			end
		end
		if cur then runs[#runs + 1] = cur end
		out.arms = #runs
		if #runs > 0 then out.width = nWet * (2 * math.pi * M.ARM_R / M.ARM_N) / #runs end
		if #runs == 2 then
			local c1 = runs[1].a + (runs[1].n - 1) / 2
			local c2 = runs[2].a + (runs[2].n - 1) / 2
			local d = math.abs(c2 - c1) % M.ARM_N
			if d > M.ARM_N / 2 then d = M.ARM_N - d end
			out.armDeg = d / M.ARM_N * 360
		end
	end
	local sum, n, rw = 0, 0, 0
	local h8 = {}
	for k = 0, M.RING_N - 1 do
		local a = k / M.RING_N * 2 * math.pi
		local x, y = cx + math.cos(a) * M.RING_R, cy + math.sin(a) * M.RING_R
		if T.isWater(s, x, y) then
			rw = rw + 1
		else
			local h = s.height(x, y)
			sum, n = sum + h, n + 1
			if k % 4 == 0 then h8[k / 4] = h end
		end
	end
	out.ringWet = rw / M.RING_N
	if n > 0 then out.relH = hc - sum / n end
	for d = 0, 3 do
		local a, b, c, e = h8[d], h8[d + 4], h8[(d + 2) % 8], h8[(d + 6) % 8]
		if a and b and c and e and a - hc >= M.PASS_UP and b - hc >= M.PASS_UP and hc - c >= M.PASS_DOWN and hc - e >= M.PASS_DOWN then
			out.pass = true
		end
	end
	out.alt = hc - (s.waterLevel or 0)
	-- (2026-10-14, run 2026-10-14_0613_sqot: rivers 300-400 m from Thurgrove went unread (the 600 m disc's 50 m grid and
	-- the 450 m arm ring step over a narrow river) and Haywater's wide river read as a lake: RIV_N rays every RIV_STEP m
	-- out to RIV_R; a ray's first wet run no wider than RIV_W_MAX with RIV_DRY m of dry land beyond is a river crossing)
	local rays, minD, widths = 0, nil, {}
	for k = 0, M.RIV_N - 1 do
		local a = k / M.RIV_N * 2 * math.pi
		local ca, sa = math.cos(a), math.sin(a)
		local d0, d1 = nil, nil
		local d = M.RIV_STEP
		while d <= M.RIV_R do
			local w = T.isWater(s, cx + ca * d, cy + sa * d)
			if w and d0 == nil then d0 = d
			elseif not w and d0 ~= nil and d1 == nil then d1 = d
			elseif d1 ~= nil and w then d0, d1 = nil, nil; break   -- (water again right beyond: not a crossing)
			end
			if d1 ~= nil and d - d1 >= M.RIV_DRY then break end
			d = d + M.RIV_STEP
		end
		if d0 ~= nil and d1 ~= nil and d1 - d0 <= M.RIV_W_MAX and d - d1 >= M.RIV_DRY then
			rays = rays + 1
			widths[#widths + 1] = d1 - d0
			if minD == nil or d0 < minD then minD = d0 end
		end
	end
	out.rivRays = rays
	if rays > 0 then
		table.sort(widths)
		out.rivW = widths[math.floor((#widths + 1) / 2)]
		out.rivD = minD
	end
	return out
end
M.RIV_N = 16
M.RIV_STEP = 10
M.RIV_R = 700
M.RIV_W_MAX = 160
M.RIV_DRY = 30
M.RIV_RAYS = 3            -- rays with a crossing for a river near the town (a lake arm crosses one or two)

--- READ field for the log: "arms:2/120,w:60,ring:0.12,rel:-14,alt:85,pass".
function M.readText(r)
	if r == nil then return "-" end
	local p = { string.format("arms:%d%s", r.arms or 0, r.armDeg and string.format("/%.0f", r.armDeg) or "") }
	if r.width then p[#p + 1] = string.format("w:%.0f", r.width) end
	p[#p + 1] = string.format("ring:%.2f", r.ringWet or 0)
	if r.relH then p[#p + 1] = string.format("rel:%.0f", r.relH) end
	p[#p + 1] = string.format("alt:%.0f", r.alt or 0)
	if r.pass then p[#p + 1] = "pass" end
	if (r.rivRays or 0) > 0 then p[#p + 1] = string.format("riv:%d/%.0f@%.0f", r.rivRays, r.rivW or 0, r.rivD or 0) end
	return table.concat(p, ",")
end

---------------------------------------------------------------------------
-- site tags

--- A river near the town from M.read's rays (RIV_RAYS crossings or more)?
function M.nearRiver(rd)
	return type(rd) == "table" and (rd.rivRays or 0) >= M.RIV_RAYS
end

--- The town's fine site tags. info = { feat = ot_site.features, stats = ot_terrain.stats, wide = ot_terrain.wide,
--- forestShare, species = { [species] = trees }, read = M.read, big, small, character, year, kind = "town" |
--- "district" | "works" }. Returns the weights { [tag] = w } (w >= 0.2) and the ranked list { {tag, score} } (by
--- specificity x weight).
function M.siteTags(info)
	info = info or {}
	local f, st, wide, rd = info.feat or {}, info.stats or {}, info.wide or {}, info.read or {}
	local w = {}
	local function put(t, v) if v and v > (w[t] or 0) then w[t] = math.min(1, v) end end
	local water = st.water
	local wetWide = wide.water or 0
	local slope = st.meanSlope or 0
	local alt = tonumber(rd.alt)
	-- rivers (2026-10-14: also a river the rays crossed near the town, M.read rivRays: narrow ones the disc missed, a wide
	-- one read as a lake)
	local near = M.nearRiver(rd)
	local river = (f.river or 0) > 0 or (water ~= nil and water.kind == "river") or near
	if river then
		put("river", 1)
		put("ford", 0.6)
		put("bridge", 0.6)
		local arms = rd.arms
		if arms and arms >= 3 then put("confluence", 1) end
		if arms == 1 then
			if wetWide >= 0.12 or (f.coast or 0) >= 0.3 then put("mouth", 1) else put("spring", 0.8) end
		end
		if arms == 2 and rd.armDeg and rd.armDeg < 125 then put("bend", 0.9) end
		local width = tonumber(rd.width)
		if width and width <= 30 then put("brook", 0.9); put("ford", 0.9) end
		if width and width >= 90 then put("bridge", 0.9); w.ford = 0.3 end
		if arms == nil and (wetWide >= 0.12 or (f.coast or 0) >= 0.3) then put("mouth", 0.8) end
	end
	-- lakes
	local body = f.body
	if body == "lake" then
		put("lake", 1)
		if alt and alt >= M.ALT_TARN then put("tarn", 1)
		elseif (f.floor or 0) >= 0.7 then put("mere", 0.9) end
	elseif body == "pond" then
		put("pool", 1)
		if alt and alt >= M.ALT_TARN then put("tarn", 0.8) end
	end
	-- coast
	local c = f.coast or 0
	if body ~= "lake" and body ~= "pond" and (c > 0 or (f.shore or 0) > 0) then
		put("coast", math.max(c, f.shore or 0))
		local cl = st.cliff
		if cl and tonumber(cl.h) and tonumber(cl.d) and cl.h >= 6 and cl.d <= 700 then
			put("cliff", clamp((cl.h - 4) / 14, 0.4, 1))
			put("rocky", 0.8)
		elseif (st.p95Slope or 0) >= 0.15 then
			put("rocky", 0.7)
		elseif slope < 0.03 then
			put("sandy", 0.8)
		end
		local rw = tonumber(rd.ringWet)
		if rw and rw >= 0.12 and rw <= 0.4 and wetWide >= 0.15 then put("bay", 0.8) end
		if (rw and rw >= 0.55) or ((wide.waterDirs or 0) >= 9 and not f.island) then put("headland", 0.9) end
	end
	-- (2026-10-14, run 0613: a peninsula read as an island (the wide survey's water on most rays): `island` only when a
	-- closed shore rings the land (ot_terrain.shoreline), else a headland; `spit` only with the spit's tip within SPIT_M
	-- and water in the town's disc (Ashness got one from 1.6 km out with no water near))
	local sh = st.shore
	if f.island and sh ~= nil and sh.island == true then put("island", 1)
	elseif f.island then put("headland", 0.9) end
	local sp = st.spit
	if sp and (tonumber(sp.tip) == nil or sp.tip <= M.SPIT_M) and (water ~= nil or c > 0) then put("spit", 1); put("headland", 0.7) end
	-- relief
	local rough = f.rough or 0
	-- (2026-10-14, run 0613: the wide survey's spread (15-38 m from distant hills) made flat towns hilly and vales: hill,
	-- vale and valley-from-the-wide-survey need the town's own relief, the disc's dry height range OWN_RANGE m)
	local ownRange = (tonumber(st.highZ) and tonumber(st.lowZ)) and (st.highZ - st.lowZ) or nil
	local ownRelief = ownRange == nil or ownRange >= M.OWN_RANGE
	if rough >= 0.3 and ownRelief then put("hill", rough) end
	local dr = st.dirRelief
	local rel = st.relief
	local grade = rel and tonumber(rel.grade) or 0
	if dr and dr.ridge and slope > 0.02 then put("ridge", 1); put("hill", 0.8) end
	if dr and dr.valley and slope > 0.02 then
		put("valley", 1)
		if (st.p95Slope or 0) >= 0.25 and (dr.contrast or 0) >= 40 then put("gorge", 1) end
		if grade >= 0.04 then put("combe", 0.9) end
		if (dr.contrast or 0) < 25 and (f.floor or 0) >= 0.7 then put("vale", 0.8) end
	end
	if (f.floor or 0) >= 0.6 and (wide.sd or 0) >= 15 and ownRelief then put("vale", 0.7); put("valley", 0.5) end
	local relH = tonumber(rd.relH)
	if relH and relH >= 18 then put("hilltop", clamp(relH / 40, 0.5, 1)); put("hill", 0.6) end
	if relH and relH <= -25 and (wide.range or 0) >= 120 then put("foot", 0.9) end
	-- (2026-10-14, run 0613: "Upper" (the slope affixes) on a headland at altitude 2: a slope near the water level and not
	-- above its surroundings counts little)
	if grade >= 0.04 and (relH == nil or math.abs(relH) < 18) then
		local low = alt ~= nil and alt < M.LOW_ALT and (relH or 0) < M.HIGH_RELH
		put("slope", low and 0.3 or 0.8)
	end
	if rd.pass then put("pass", 1) end
	if alt and alt >= M.ALT_HIGH then put("mountain", clamp((alt - M.ALT_HIGH) / 300 + 0.6, 0.6, 1)) end
	if (wide.range or 0) >= 250 then put("mountain", 0.6) end
	if (st.p95Slope or 0) >= 0.3 and (tonumber(info.forestShare) or 0) < 0.1 then put("rock", 0.7) end
	-- wet ground, heath
	local fs = tonumber(info.forestShare) or 0
	if (f.floor or 0) >= 0.85 and slope < 0.012 and (river or (wetWide >= 0.05 and wetWide <= 0.6)) then
		put("marsh", (wide.range or 99) < 15 and 0.8 or 0.6)
		if alt == nil or alt < 30 then put("fen", 0.9) end
	end
	if alt and alt >= M.ALT_MOOR and rough < 0.5 and fs < 0.1 and slope < 0.06 then put("moor", 0.8) end
	if (f.open or 0) >= 0.5 and fs < 0.08 and not river and wetWide < 0.05 and (alt == nil or alt < M.ALT_MOOR) then
		put("heath", 0.5)
	end
	-- forest and its trees
	if fs >= 0.08 then
		put("forest", clamp((fs - 0.04) / 0.3, 0.3, 1))
		-- (2026-10-14, run 0613: `edge` 0.70 on all 16 towns, from any share 0.08-0.35. Now only with a real contrast:
		-- info.forestEdge, ot_forest.isEdge: an open town, woods on one side, open land on another)
		if fs >= 0.35 then put("clearing", 0.9) elseif info.forestEdge then put("edge", 0.7) end
		local total, list = 0, {}
		for sp, n in pairs(info.species or {}) do
			if M.TAG_INDEX[sp] and tonumber(n) then
				total = total + n
				list[#list + 1] = { sp, n }
			end
		end
		-- (2026-10-14, run 0613: ash topped all 16 towns, the temperate climate's mix. With the map's totals
		-- (info.speciesMap) a species ranks by its share here over its share on the map (lift): what is special about
		-- this town's woods, not what grows everywhere; it needs SPECIES_LIFT, and the common one never tags every town)
		local mapTot, mapSp = 0, info.speciesMap
		if type(mapSp) == "table" then for sp, n in pairs(mapSp) do if M.TAG_INDEX[sp] and tonumber(n) then mapTot = mapTot + n end end end
		for _, e in ipairs(list) do
			local share = total > 0 and e[2] / total or 0
			local lift = 1
			if mapTot > 0 and tonumber(mapSp[e[1]]) and mapSp[e[1]] > 0 then lift = share / (mapSp[e[1]] / mapTot) end
			e[3], e[4] = share, lift
			e[5] = mapTot > 0 and share * math.min(lift, 3) or share
		end
		table.sort(list, function(a, b)
			if a[5] ~= b[5] then return a[5] > b[5] end
			return a[1] < b[1]
		end)
		for i = 1, math.min(2, #list) do
			local share, lift = list[i][3], list[i][4]
			if share >= 0.2 and (mapTot <= 0 or lift >= M.SPECIES_LIFT) then
				put(list[i][1], clamp(share * 1.4 * (mapTot > 0 and math.min(lift, 1.5) / 1.5 or 1), 0.4, 1))
			end
		end
	end
	-- open land
	if (f.open or 0) > 0 then
		put("plain", f.open)
		if river or (f.valley or 0) > 0 then put("meadow", 0.7 * f.open + 0.2) else put("field", 0.6 * f.open + 0.2) end
	end
	-- the climate (2026-10-14, NEXT_PHASE_BRIEF 49): its own tag, its features beside the right ground, and the tags it
	-- never takes dropped (no heath / moor / oak on a tropical map, no marsh on a dry one)
	local clim = info.climate
	if clim and clim ~= "temperate" then
		for t, v in pairs(CL.SITE[clim] or {}) do put(t, v) end
		if clim == "tropical" then
			if (w.coast or 0) > 0 then put("reef", (w.rocky or w.headland) and 0.8 or 0.5) end
			if (w.bay or 0) > 0 or (w.spit or 0) > 0 or (w.island or 0) > 0 then put("lagoon", 0.8) end
			if (w.marsh or 0) > 0 or ((w.mouth or 0) > 0 and (w.coast or 0) > 0) then put("mangrove", 0.9) end
		elseif clim == "dry" then
			if (w.sandy or 0) > 0 or ((w.plain or 0) > 0.5 and (w.hill or 0) < 0.3) then put("dune", 0.6) end
			if (w.hilltop or 0) > 0 or (w.ridge or 0) > 0 then put("mesa", 0.8) end
			if (w.valley or 0) > 0 and not river then put("wadi", 0.8) end
		elseif clim == "subarctic" then
			if (w.mountain or 0) > 0 or (w.hilltop or 0) > 0 then put("snow", 0.7) end
			if (w.hill or 0) > 0 then put("moor", 0.5) end
		end
	end
	if clim then
		for t in pairs(w) do if CL.vetoTag(clim, t) then w[t] = nil end end
	end
	-- town
	if info.big then put("market", 0.8); put("big", 0.8) end
	if info.small then put("small", 0.6) end
	if info.character then put("character", 1); put("church", 0.4) end
	if info.kind == "district" then put("district", 1) elseif info.kind == "works" then put("works", 1) end
	local y = tonumber(info.year)
	if y and y < 1870 then put("old", 0.5) elseif y and y >= 1950 then put("new", 0.6) end
	local ranked = {}
	for _, t in ipairs(M.TAGS) do
		if (w[t] or 0) >= 0.2 then ranked[#ranked + 1] = { t, w[t] * (M.SPEC[t] or 1) } else w[t] = nil end
	end
	table.sort(ranked, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return M.TAG_INDEX[a[1]] < M.TAG_INDEX[b[1]]
	end)
	return w, ranked
end

--- The site weights w against the map survey's water near the town (ot_mapshape.waterNear: { sea, lake, river } or nil;
--- 2026-10-14, NEXT_PHASE_BRIEF 49, run 0814 load 4: `lake:1.00` on an island map with `lakes=0 sea=true` gave "Lake in
--- the Hills"): no lake word without a lake (not the sea) within reach, a sea inlet or lagoon becomes coast / bay. Changes
--- w in place; returns the misfits { "lake:sea", ... }.
function M.agreeSurvey(w, wn)
	local out = {}
	if type(w) ~= "table" or type(wn) ~= "table" or wn.lake then return out end
	for _, tag in ipairs({ "lake", "mere", "pool", "tarn" }) do
		local v = w[tag]
		if v then
			w[tag] = nil
			out[#out + 1] = tag .. ":" .. (wn.sea and "sea" or "noLake")
			if wn.sea then
				w.coast = math.max(w.coast or 0, v * 0.8)
				w.bay = math.max(w.bay or 0, v * 0.6)
			end
		end
	end
	return out
end

--- The weights with their broader tags (x 0.7 per level) and "any".
function M.expandSite(w)
	local x = {}
	for _, t in ipairs(M.TAGS) do
		local v = w[t]
		if v then
			if (x[t] or 0) < v then x[t] = v end
			local function up(tag, f, depth)
				for _, par in ipairs(M.PARENT[tag] or {}) do
					if (x[par] or 0) < v * f then x[par] = v * f end
					if depth < 3 then up(par, f * 0.7, depth + 1) end
				end
			end
			up(t, 0.7, 1)
		end
	end
	x.any = math.max(x.any or 0, M.ANY)
	return x
end

--- "confluence:1.60,river:0.90" (the first n ranked tags), "-" when empty.
function M.rankedText(ranked, n)
	local parts = {}
	for i, r in ipairs(ranked or {}) do
		if i > (n or 5) then break end
		parts[#parts + 1] = string.format("%s:%.2f", r[1], r[2])
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

---------------------------------------------------------------------------
-- fit

--- How well entry e fits the expanded site x: the best match (site x morpheme x specificity) + 0.3 x the second,
--- minus CONTRA for each of its own tags the site lacks (softer when a broader tag is there). Returns score, tag.
function M.fit(e, x)
	local best, second, bt = 0, 0, nil
	for _, p in ipairs(e.x) do
		local s = x[p[1]]
		if s then
			local v = s * p[2] * (M.SPEC[p[1]] or 1)
			if v > best then second, best, bt = best, v, p[1] elseif v > second then second = v end
		end
	end
	local pen = 0
	for _, p in ipairs(e.tl) do
		local t = p[1]
		if x[t] == nil then
			local c = M.CONTRA[t] or 0
			if c > 0 then
				local par = false
				for _, q in ipairs(M.PARENT[t] or {}) do if x[q] then par = true end end
				pen = pen + p[2] * c * (par and 0.3 or 1)
			end
		end
	end
	return best + 0.3 * second - pen, bt
end

---------------------------------------------------------------------------
-- joining

local VOWEL = "[aeiouy\128-\255]"

local function sufJoin(L, a, b)
	local la = lowerAll(a)
	local first = b:sub(1, 1)
	if L.dropE and la:sub(-1) == "e" and first:match(VOWEL) and #la > 2 then
		a, la = a:sub(1, -2), la:sub(1, -2)
	end
	local x = la:sub(-1)
	if x == first and x:match("[a-z]") then
		if not L.dbl:find(x, 1, true) then return nil end
		if la:sub(-2, -2) == x or b:sub(2, 2) == x then return nil end
	end
	if x:match(VOWEL) and first:match(VOWEL) and not L.vv then return nil end
	local tc = #(la:match("[^aeiouy\128-\255]*$") or "")
	local lc = #(b:match("^[^aeiouy\128-\255]*") or "")
	if tc + lc > L.maxCons then return nil end
	return a .. b
end

local function elide(g, s)
	if g:sub(-1):match("[aeiou]") and s:sub(1, 1):match("[aeiouAEIOU]") then return g:sub(1, -2) .. s end
	return g .. s
end

local function adjForm(e, gender)
	if e.kind ~= "adj" then return e.text end
	local i = ({ m = 1, f = 2, mp = 3, fp = 4 })[gender or "m"] or 1
	if e.forms[i] then return e.forms[i] end
	-- (plurals the data leaves out: + s after a vowel, + es after a consonant: blancas, mayores)
	if i >= 3 then
		local w = e.forms[i - 2] or e.forms[1]
		return w .. (w:sub(-1):match("[aeiouy]") and "s" or "es")
	end
	return e.forms[1]
end

--- Do two parts share a word ("Isla" / "de la Isla", "Pine" / "Pines", "Vega" / "de la Vega")? Words of 3+ letters
--- compared on their first four.
function M.sameWord(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then return false end
	local wa = {}
	for tok in lowerAll(a):gmatch("[^ %-']+") do if #tok >= 3 then wa[tok:sub(1, 4)] = true end end
	for tok in lowerAll(b):gmatch("[^ %-']+") do if #tok >= 3 and wa[tok:sub(1, 4)] then return true end end
	return false
end

--- May parts of dialect groups a and b meet in one name (NEXT_PHASE_BRIEF 50 item 3: "Invercoed", Gaelic Inver- with
--- Welsh coed)? An ungrouped part goes with every group; two groups only when the language lists the pair (compat).
function M.compatible(L, a, b)
	if a == nil or b == nil or a == b then return true end
	return L ~= nil and L.compatSet ~= nil and L.compatSet[a .. ":" .. b] == true
end

--- The base name of stem s and generic g in language L, or nil (the pair doesn't make a name). Kanji / romaji for
--- Japanese (L.script). strict: no hybrid of two groups (2026-10-14, NEXT_PHASE_BRIEF 53 item 3: only a town near a
--- dialect border blends Saxon and Norse; a shared group, Celtic, goes with its partners anywhere).
function M.join(L, s, g, strict)
	if s.cls and g.cls and s.cls == g.cls then return nil end
	if L.script then
		if g.form ~= "ja" or s.k == nil then return nil end
		if s.k == g.k then return nil end
		if L.script == "kanji" then return s.k .. g.k end
		local r2 = s.flags.r and g.rd or g.r
		local r1 = s.r
		if r1:sub(-1) == "n" and r2:sub(1, 1):match("[aeiouy]") then r1 = r1 .. "'" end
		return M.capFirst(r1 .. r2)
	end
	if M.sameWord(s.text, g.text) then return nil end
	-- (a generic that wants a whole word before it never takes a stem fragment or a personal name: "Acbottom")
	if g.flags.w and (s.flags.f or s.flags.p) then return nil end
	if not M.compatible(L, s.grp, g.grp) then return nil end
	-- (+x, NEXT_PHASE_BRIEF 53 Part B: parts that only meet their own group, "Agua Fria", "Fort Fraser", "Georgetown";
	-- such a generic's gender agrees: an adjective after m / f, a noun of the same gender, "Los Alamos", "San Lucas")
	if (g.flags.x or s.flags.x) and s.grp ~= g.grp then return nil end
	if g.flags.x and g.gender then
		if s.kind == "adj" then
			if g.gender ~= "m" and g.gender ~= "f" then return nil end
		elseif s.gender ~= g.gender then
			return nil
		end
	end
	if strict and s.grp and g.grp and s.grp ~= g.grp and not (L.shared[s.grp] or L.shared[g.grp]) then return nil end
	local need = g.flags
	if need.p and not s.flags.p then return nil end
	if need.c and not (s.flags.c or s.river) then return nil end
	if s.flags.c and not need.c then return nil end
	if L.pOnly and s.flags.p and not need.p then return nil end
	if need.t and not s.flags.t then return nil end
	local form = g.form
	if form == "suf" then
		if s.kind ~= "stem" then return nil end
		local ls, lg = lowerAll(s.text), g.text
		if #ls >= 3 and (lg:find(ls, 1, true) or ls:find(lg, 1, true)) then return nil end
		if #lg >= 3 and ls:sub(-#lg) == lg then return nil end
		return sufJoin(L, s.text, g.text)
	elseif form == "after" then
		if s.kind ~= "stem" then return nil end
		if lowerAll(s.text) == lowerAll(g.text) then return nil end
		return s.text .. " " .. g.text
	elseif form == "before" then
		if s.river and L.id ~= "usa" then return nil end
		if s.kind == "stem" or s.kind == "phrase" then
			if s.kind == "stem" and s.text:sub(1, 1):match("[a-z]") then return nil end
			return g.text .. " " .. s.text
		elseif s.kind == "adj" then
			return g.text .. " " .. M.capFirst(adjForm(s, g.gender))
		end
		return nil
	elseif form == "pre" then
		if s.kind == "phrase" then
			if L.noPhrasePre then return nil end
			return g.text .. " " .. s.text
		end
		if s.kind == "adj" then return elide(g.text, adjForm(s, g.gender)) end
		if s.kind == "noun" then return elide(g.text, s.text) end
		if s.flags.c or s.river then return g.text .. M.lowerFirst(s.text) end
		return nil
	elseif form == "hyph" then
		if s.kind == "stem" and (s.river or s.flags.c) then return g.text .. s.text end
		-- (French: "Pont-des-Saules", "Bois-de-la-Combe")
		if s.kind == "phrase" then return g.text .. (s.text:gsub(" ", "-")) end
		return nil
	end
	return nil
end

---------------------------------------------------------------------------
-- the blocklist

local BLOCK_SUB, BLOCK_WORD, BLOCK_CJK = LD.BLOCK_SUB, {}, LD.BLOCK_CJK
for _, w in ipairs(LD.BLOCK_WORD) do BLOCK_WORD[w] = true end

--- Is the name blocked (an offensive or brand string, case-insensitive; substrings and whole words)?
function M.blocked(name)
	if type(name) ~= "string" then return true end
	for _, c in ipairs(BLOCK_CJK) do if name:find(c, 1, true) then return true end end
	local l = lowerAll(name)
	for _, s in ipairs(BLOCK_SUB) do if l:find(s, 1, true) then return true end end
	for tok in l:gmatch("[^ \t%-'%.]+") do if BLOCK_WORD[tok] then return true end end
	return false
end

--- Is the base well formed: length, no triple letters?
function M.wellFormed(L, base)
	if type(base) ~= "string" or base == "" then return false end
	if L.script == "kanji" then return M.chars(base) <= M.MAX_KANJI end
	if M.chars(base) > M.MAX_BASE then return false end
	if lowerAll(base):find("([a-z])%1%1") then return false end
	return true
end

---------------------------------------------------------------------------
-- context, regions, waters

--- A naming context for one map: lang = generator language id, seed, real = { [lower name] = true } (the game's
--- list names: never generated), used = { [name] = true } (names already taken).
function M.newCtx(lang, seed, real, used)
	local L = M.lang(lang)
	if L == nil then return nil end
	local ctx = { L = L, lang = lang, seed = tonumber(seed) or 1, real = real or {}, used = {}, usedLower = {},
		specUse = {}, genUse = {}, affUse = {}, anchors = {}, rivers = {}, lakes = {}, budget = nil, featUse = {},
		featWords = {}, riverFrame = {}, shapeUse = {}, rules = M.RULES, opaqueN = 0, flavorN = 0 }
	for n in pairs(used or {}) do M.take(ctx, n) end
	return ctx
end

function M.take(ctx, name)
	ctx.used[name] = true
	ctx.usedLower[lowerAll(name)] = true
end

function M.free(ctx, name)
	if type(name) ~= "string" then return false end
	local l = lowerAll(name)
	return not ctx.used[name] and not ctx.usedLower[l] and not ctx.real[l] and not M.blocked(name)
end

--- The map's dialect areas (2026-10-14, NEXT_PHASE_BRIEF 53 item 3, review Q5: "fewer, larger areas with borders that
--- follow the land"; they replace the 2-6 seeded anchors of REGION_KM). towns = { { x, y, alt, id } }, ws = their site
--- weights with the survey's cues (index-aligned). A border line runs along the main valley's towns (else the range's,
--- else across the towns' longer extent); the side with more coast and east is the coast area (Norse), the other the
--- core (Saxon); with three areas (AREAS3_MIN towns, seeded AREAS3_P) the core side's far fringe (FRINGE of the towns)
--- is the edge area (Gaelic or Welsh, seeded); with two, the side with the stronger case (coast / east or high / west)
--- takes its role. Sets ctx.areas = { c = {x, y}, n = {x, y} (the border's normal), coastSide = 1 | -1, three, fringe
--- (m beyond the border on the core side), core, coast, edge (the area objects) } or nil.
function M.regions(ctx, towns, ws)
	ctx.anchors = {}
	ctx.areas = nil
	local L = ctx.L
	-- (NEXT_PHASE_BRIEF 53 Part B: the climate may set the areas and a group shared with all of them)
	local cl = ctx.cl
	local A = (cl and cl.areas) or L.areas
	if type(A) ~= "table" or A.core == nil then return end
	local pts = {}
	for i, t in ipairs(towns) do
		if tonumber(t.x) and tonumber(t.y) then pts[#pts + 1] = { x = t.x, y = t.y, w = (ws and ws[i]) or t.w or {}, alt = tonumber(t.alt) } end
	end
	if #pts < 2 then return end
	local function line(sel)
		local n, cx, cy = 0, 0, 0
		for _, p in ipairs(sel) do n, cx, cy = n + 1, cx + p.x, cy + p.y end
		if n < 2 then return nil end
		cx, cy = cx / n, cy / n
		local sxx, syy, sxy = 0, 0, 0
		for _, p in ipairs(sel) do
			local dx, dy = p.x - cx, p.y - cy
			sxx, syy, sxy = sxx + dx * dx, syy + dy * dy, sxy + dx * dy
		end
		if sxx + syy < 1 then return nil end
		local ang = 0.5 * G.atan2(2 * sxy, sxx - syy)
		return { x = cx, y = cy }, { x = math.cos(ang), y = math.sin(ang) }
	end
	local function pick(f)
		local out = {}
		for _, p in ipairs(pts) do if f(p.w) then out[#out + 1] = p end end
		return out
	end
	local c, d = line(pick(function(w) return (w.mainvalley or 0) > 0 end))
	if c == nil then c, d = line(pick(function(w) return (w.range or 0) > 0 or (w.summit or 0) > 0 or (w.divide or 0) > 0 end)) end
	if c == nil then
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		local cx, cy = 0, 0
		for _, p in ipairs(pts) do
			x0, y0, x1, y1 = math.min(x0, p.x), math.min(y0, p.y), math.max(x1, p.x), math.max(y1, p.y)
			cx, cy = cx + p.x, cy + p.y
		end
		c = { x = cx / #pts, y = cy / #pts }
		-- (across the longer extent: a north-south line splits west from east)
		d = (x1 - x0 >= y1 - y0) and { x = 0, y = 1 } or { x = 1, y = 0 }
	end
	local nrm = { x = -d.y, y = d.x }
	-- (both sides need towns: a border along a river at the map's edge moves, parallel, to the towns' median)
	do
		local ss, pos = {}, 0
		for _, p in ipairs(pts) do
			local v = (p.x - c.x) * nrm.x + (p.y - c.y) * nrm.y
			ss[#ss + 1] = v
			if v >= 0 then pos = pos + 1 end
		end
		local minSide = math.max(1, math.floor(#pts * 0.2))
		if pos < minSide or #pts - pos < minSide then
			table.sort(ss)
			local m = ss[math.floor((#ss + 1) / 2)]
			if #ss % 2 == 0 then m = (ss[#ss / 2] + ss[#ss / 2 + 1]) / 2 end
			c = { x = c.x + nrm.x * m, y = c.y + nrm.y * m }
		end
	end
	local function sideOf(x, y) return (x - c.x) * nrm.x + (y - c.y) * nrm.y end
	local function coastScore(p)
		local w = p.w
		return math.max(w.coast or 0, w.bay or 0, w.headland or 0, w.island or 0, w.spit or 0, w.mouth or 0) + 0.7 * (w.east or 0)
	end
	local function highScore(p)
		local w = p.w
		local alt = p.alt and clamp(p.alt / 400, 0, 1) or 0
		return math.max(w.hill or 0, w.mountain or 0, w.moor or 0, w.summit or 0, w.range or 0, w.peak or 0, w.hilltop or 0)
			+ 0.7 * (w.west or 0) + alt
	end
	local sum = { [1] = { n = 0, c = 0, h = 0 }, [-1] = { n = 0, c = 0, h = 0 } }
	for _, p in ipairs(pts) do
		p.s = sideOf(p.x, p.y)
		local k = p.s >= 0 and 1 or -1
		sum[k].n, sum[k].c, sum[k].h = sum[k].n + 1, sum[k].c + coastScore(p), sum[k].h + highScore(p)
	end
	local function mean(k, f) return sum[k].n > 0 and sum[k][f] / sum[k].n or 0 end
	local dC = mean(1, "c") - mean(-1, "c")
	local dH = mean(1, "h") - mean(-1, "h")
	local seedSide = draw(ctx.seed, 1, "areaside") < 0.5 and 1 or -1
	local three = #pts >= M.AREAS3_MIN and A.edge ~= nil and #A.edge > 0 and ((cl and cl.three) or draw(ctx.seed, 2, "areas3") < M.AREAS3_P)
	local edges = A.edge or {}
	local edgeName = #edges > 0 and edges[math.floor(draw(ctx.seed, 3, "areaedge") * #edges) % #edges + 1] or nil
	local R = { c = c, n = nrm, three = three }
	local roleA, roleB    -- the + side's and the - side's role
	if three or math.abs(dC) >= math.abs(dH) or edgeName == nil then
		local cs = dC > 0 and 1 or (dC < 0 and -1 or seedSide)
		R.coastSide = cs
		roleA, roleB = (cs == 1) and "coast" or "core", (cs == 1) and "core" or "coast"
	else
		local es = dH > 0 and 1 or (dH < 0 and -1 or seedSide)
		R.coastSide = 0
		R.edgeSide = es
		roleA, roleB = (es == 1) and "edge" or "core", (es == 1) and "core" or "edge"
	end
	R.roleOf = { [1] = roleA, [-1] = roleB }
	if three then
		-- (the core side's far fringe: the FRINGE share of all towns farthest from the border)
		local coreK = R.coastSide == 1 and -1 or 1
		local far = {}
		for _, p in ipairs(pts) do if (p.s >= 0 and 1 or -1) == coreK then far[#far + 1] = math.abs(p.s) end end
		table.sort(far, function(a, b) return a > b end)
		local k = math.min(math.max(1, math.floor(M.FRINGE * #pts + 0.5)), #far - 1)
		if k >= 1 then R.fringe, R.coreK = far[k], coreK else R.three = false end
	end
	local own = { core = A.core, coast = A.coast, edge = edgeName or A.core }
	for role, g in pairs(own) do
		local w = {}
		for _, gg in ipairs(L.groups) do
			if gg == g then w[gg] = M.DIALECT_OWN
			elseif (L.shared[gg] or (cl and cl.shared[gg])) and M.compatible(L, g, gg) then w[gg] = M.DIALECT_SHARED
			else w[gg] = M.DIALECT_FOREIGN end
		end
		R[role] = { name = g, role = role, w = w }
	end
	ctx.areas = R
end

--- The dialect area at (x, y): { name, role, w (group multipliers), hybrid (near a border: Saxon + Norse may blend),
--- other (the area across the nearest border) } or nil without areas.
function M.dialectAt(ctx, x, y)
	local R = ctx.areas
	if R == nil or not tonumber(x) or not tonumber(y) then return nil end
	local s = (x - R.c.x) * R.n.x + (y - R.c.y) * R.n.y
	local k = s >= 0 and 1 or -1
	local role = R.roleOf[k]
	local dist = math.abs(s)
	local otherRole = R.roleOf[-k]
	if R.three and k == R.coreK then
		if math.abs(s) >= R.fringe then
			role, otherRole, dist = "edge", "core", math.abs(s) - R.fringe
		elseif R.fringe - math.abs(s) < dist then
			otherRole, dist = "edge", R.fringe - math.abs(s)
		end
	end
	local a = R[role]
	return { name = a.name, role = role, w = a.w, hybrid = dist <= M.BORDER_M, other = R[otherRole] }
end

local function angDiffAxis(a, b)
	local d = math.abs(a - b) % math.pi
	if d > math.pi / 2 then d = math.pi - d end
	return d
end

--- River systems: towns = { { id, x, y, river = bool, axis = river axis (rad) or nil } }. Two river towns share a river
--- when within RIVER_LINK_M and the line between them runs along both towns' river axes (within RIVER_DEG). Returns
--- { [townId] = system index }, systems { { ids, x, y } } (in the order of their lowest town id).
function M.riverSystems(towns)
	local list = {}
	for _, t in ipairs(towns) do
		if t.river and tonumber(t.x) and #list < M.MAX_RIVER_TOWNS then list[#list + 1] = t end
	end
	table.sort(list, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
	local parent = {}
	for i = 1, #list do parent[i] = i end
	local function find(i)
		while parent[i] ~= i do i = parent[i] end
		return i
	end
	local lim = math.rad(M.RIVER_DEG)
	for i = 1, #list do
		for j = i + 1, #list do
			local a, b = list[i], list[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
			if d <= M.RIVER_LINK_M then
				local bearing = G.atan2(b.y - a.y, b.x - a.x)
				local okA = a.axis == nil or angDiffAxis(a.axis, bearing) <= lim
				local okB = b.axis == nil or angDiffAxis(b.axis, bearing) <= lim
				if (a.axis == nil and b.axis == nil) then okA = d <= M.RIVER_LINK_M / 2 end
				if okA and okB then
					local ri, rj = find(i), find(j)
					if ri ~= rj then parent[math.max(ri, rj)] = math.min(ri, rj) end
				end
			end
		end
	end
	local sysOf, systems, idx = {}, {}, {}
	for i, t in ipairs(list) do
		local r = find(i)
		if idx[r] == nil then
			systems[#systems + 1] = { ids = {}, x = 0, y = 0 }
			idx[r] = #systems
		end
		local s = systems[idx[r]]
		s.ids[#s.ids + 1] = t.id
		s.x, s.y = s.x + t.x, s.y + t.y
		sysOf[t.id] = idx[r]
	end
	for _, s in ipairs(systems) do s.x, s.y = s.x / #s.ids, s.y / #s.ids end
	return sysOf, systems
end

--- Lake clusters: towns with lake = true within LAKE_LINK_M of each other. Same returns as riverSystems.
function M.lakeSystems(towns)
	local list = {}
	for _, t in ipairs(towns) do if t.lake and tonumber(t.x) then list[#list + 1] = { id = t.id, x = t.x, y = t.y, river = true } end end
	local old = M.RIVER_LINK_M
	M.RIVER_LINK_M = M.LAKE_LINK_M * 2
	local a, b = M.riverSystems(list)
	M.RIVER_LINK_M = old
	return a, b
end

local function gen2(syl, seed, i)
	local s1, s2 = split(syl[1], "|"), split(syl[2], "|")
	if #s1 == 0 or #s2 == 0 then return nil end
	return s1[rng.hash(seed, "rs1", i) % #s1 + 1] .. s2[rng.hash(seed, "rs2", i) % #s2 + 1]
end

--- A river name for system k: { n = the full name, s = the stem towns use } or nil. Unique on the map.
function M.riverName(ctx, k)
	local L, D = ctx.L, ctx.L.data
	if L.script then
		-- a water / colour stem + 川
		local cands = {}
		for _, e in ipairs(L.specs) do
			for _, p in ipairs(e.tl) do
				if p[1] == "spring" or p[1] == "river" or p[1] == "brook" or (p[1] == "any" and p[2] <= 0.3) then cands[#cands + 1] = e break end
			end
		end
		local gk, gr, grd = (D.riverGens or "川/kawa/gawa"):match("^([^/]+)/([^/]+)/(.+)$")
		local start = rng.hash(ctx.seed, "river", k)
		for i = 0, #cands - 1 do
			local e = cands[(start + i) % #cands + 1]
			local n = L.script == "kanji" and (e.k .. gk) or M.capFirst(e.r .. (e.flags.r and grd or gr))
			ctx.riverNames = ctx.riverNames or {}
			if M.free(ctx, n) and not ctx.riverNames[n] then
				ctx.riverNames[n] = true
				return { n = n, s = L.script == "kanji" and e.k or e.r, e = e }
			end
		end
		return nil
	end
	local list = split(D.rivers, "|")
	local suffixes = split(D.riverSuffix, "|")
	ctx.riverNames = ctx.riverNames or {}
	local start = #list > 0 and rng.hash(ctx.seed, "river", k) % #list or 0
	local function try(stem, i)
		if stem == nil or ctx.riverNames[stem] then return nil end
		local full = stem
		if #suffixes > 0 then full = stem .. suffixes[rng.hash(ctx.seed, "rsuf", k, i) % #suffixes + 1] end
		if M.free(ctx, full) and M.free(ctx, stem) and not M.blocked(full) and not M.climateWord(ctx, full) then
			ctx.riverNames[stem] = true
			return { n = full, s = stem }
		end
		return nil
	end
	for i = 0, #list - 1 do
		local r = try(list[(start + i) % #list + 1], i)
		if r then return r end
	end
	if D.riverSyl then
		for i = 1, 60 do
			local r = try(gen2(D.riverSyl, ctx.seed + k, i), i)
			if r then return r end
		end
	end
	return nil
end

--- Does the context's climate rule a word of name out (ot_climate.wordMisfit; counted as a misfit)?
function M.climateWord(ctx, name)
	if ctx == nil or ctx.climate == nil then return false end
	local bad = CL.wordMisfit(name, ctx.climate, M.CLS_OF_GEN[ctx.lang] or ctx.lang)
	if bad then M.misfit(ctx, bad, ctx.climate) return true end
	return false
end

--- A lake name for cluster k: { n, s } or nil. high = the cluster sits on high ground (a town with the `tarn` tag): only
--- then the "tarn" generic (2026-10-14, run 0613: Branttarn at altitude 2).
function M.lakeName(ctx, k, high, grp)
	local D = ctx.L.data
	local stems = split(D.lakes, "|")
	if #stems == 0 then return nil end
	local gens = {}
	-- (2026-10-14, NEXT_PHASE_BRIEF 53 item 3: the dialect area of the lake's towns sets its word: -water / tarn in the
	-- Norse area, -mere in the Saxon one)
	local by = type(D.lakeGensBy) == "table" and grp and D.lakeGensBy[grp] or nil
	for _, g in ipairs(split(by or D.lakeGens, "|")) do
		if high or not g:find("tarn", 1, true) then gens[#gens + 1] = g end
	end
	if #gens == 0 and by then
		for _, g in ipairs(split(D.lakeGens, "|")) do if high or not g:find("tarn", 1, true) then gens[#gens + 1] = g end end
	end
	ctx.lakeNames = ctx.lakeNames or {}
	local start = rng.hash(ctx.seed, "lake", k) % #stems
	for i = 0, #stems - 1 do
		local stem = stems[(start + i) % #stems + 1]
		local full
		if D.lakeForm then full = string.format(D.lakeForm, stem)
		elseif #gens > 0 then
			local g = gens[rng.hash(ctx.seed, "lgen", k, i) % #gens + 1]
			full = sufJoin(ctx.L, stem, g) or (stem .. g)
		end
		if full and not ctx.lakeNames[full] and M.free(ctx, full) and not M.climateWord(ctx, full) then
			ctx.lakeNames[full] = true
			return { n = full, s = stem }
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- naming one town

--- Does affix a repeat a word of the base ("Seebrunn am See", "Collelago del Lago", "Maraislieu-le-Marais")?
function M.repeats(a, base)
	local words = (a.text:gsub("%%%a", " "))
	local lb = lowerAll(base)
	for tok in lowerAll(words):gmatch("[^ %-']+") do
		if #tok >= 5 and tok:sub(-1) == "s" then tok = tok:sub(1, -2) end
		if #tok >= 3 and lb:find(tok, 1, true) then return true end
		if #tok >= 4 and lb:find(tok:sub(1, 4), 1, true) then return true end
	end
	-- (no second phrase: "Cabo de la Peña de Arriba", "Souto do Pinhal do Rio")
	if base:find(" [a-z]") and words:find(" [a-z]") then return true end
	return false
end

local function fillAffix(L, a, base, t)
	local tpl = (L.script == "romaji") and a.r or a.text
	if tpl == nil then return nil end
	if a.needR and not (t.river and t.river.n) then return nil end
	if (a.needT) and not (t.river and t.river.s) then return nil end
	if a.needK and not (t.lake and t.lake.n) then return nil end
	if a.needM and not (t.mount and t.mount.s) then return nil end
	if a.needB and not (t.bay and t.bay.s) then return nil end
	if a.needD and not (t.dir and L.dirWords[t.dir]) then return nil end
	if a.needE and not (t.ldir and L.dirWords[t.ldir]) then return nil end
	local saint = nil
	if a.needP then
		local saints = t.saints or L.saints
		if #saints == 0 then return nil end
		saint = saints[rng.hash(t.seed or 1, "saint", t.id or 0) % #saints + 1]
	end
	local out = tpl:gsub("%%(%a)", function(c)
		if c == "s" then return base
		elseif c == "l" then return M.lowerFirst(base)
		elseif c == "r" then return t.river.n
		elseif c == "t" then return t.river.s
		elseif c == "k" then return t.lake.n
		elseif c == "m" then return t.mount.s
		elseif c == "M" then return t.mount.n
		elseif c == "b" then return t.bay.s
		elseif c == "B" then return t.bay.n
		elseif c == "D" then return L.dirWords[t.dir]
		elseif c == "E" then return L.dirWords[t.ldir]
		elseif c == "p" then return saint end
		return "%" .. c
	end)
	return out
end

local function regionMul(e, dia)
	if dia == nil or e.grp == nil then return 1 end
	return dia.w[e.grp] or 1
end

-- ranked parts of a list for site x: { { e, f, bt } } by fit + region + rare + use + jitter
--- The budget words of a part (cached on the entry per lexicon): its text as a word and as a suffix ("-wood": "wood").
function M.partKeys(e, cls)
	if cls == nil then return {} end
	e.wkeys = e.wkeys or {}
	local c = e.wkeys[cls]
	if c == nil then
		local seen = {}
		c = {}
		local txt = e.k or e.text or ""
		for _, k in ipairs(NW.keys(txt, cls)) do if not seen[k] then seen[k] = true; c[#c + 1] = k end end
		for _, k in ipairs(NW.keys("Zz" .. NW.lower(txt), cls)) do if not seen[k] then seen[k] = true; c[#c + 1] = k end end
		-- (a stem's root, NEXT_PHASE_BRIEF 50 item 2: "Myt" of Mytmere and North Mytdale)
		if e.form == nil and e.k == nil and e.kind == "stem" and #txt >= 2 then
			local r = "^" .. NW.fold(lowerAll(txt))
			if not seen[r] then seen[r] = true; c[#c + 1] = r end
		end
		table.sort(c)
		e.wkeys[cls] = c
	end
	return c
end

---------------------------------------------------------------------------
-- roots and affix patterns in the word budget (2026-10-14, NEXT_PHASE_BRIEF 50 item 2, run 2026-10-14_1729: "Myt" on
-- Mytmere-in-the-Vale, North Mytdale and Mytsands; "-under-Dun" twice and "-under-Edge"; Mount Spruce and South Spruce
-- Valley). Read from the finished name (stateless: the same for names on the map after a reload): each word's stem
-- from the inventory ("^myt"), and the affix the name follows: its family ("%under": the first literal word of the
-- template) and, for a rare template, the template itself ("%!%s-under-%m": once per map). The word budget counts them
-- like its words (cap per ~8 towns, never within NEAR_M or among the HOOD nearest towns).

M.ROOT_CACHE = 4000

local function patEsc(c)
	if c:match("[%^%$%(%)%%%.%[%]%*%+%-%?]") then return "%" .. c end
	return c
end

-- the language's root index (stems, longest first), generic texts and affix patterns (r61: with the s61 affixes,
-- NEXT_PHASE_BRIEF 61; without them the s53 / s60 budgets stay as they were)
local function rootIndex(L, r61)
	local key = r61 and "rootIdx61" or "rootIdx"
	if L[key] then return L[key] end
	local R = { stems = {}, suf = {}, pre = {}, words = {}, pats = {}, cache = {}, n = 0 }
	for _, e in ipairs(L.specs) do
		local t = e.k or e.text
		if (e.kind == "stem" or e.kind == "noun") and type(t) == "string" and not t:find(" ", 1, true) and #t >= 2 then
			R.stems[#R.stems + 1] = lowerAll(t)
		end
	end
	table.sort(R.stems, function(a, b) if #a ~= #b then return #a > #b end return a < b end)
	for _, g in ipairs(L.gens) do
		local t = lowerAll(g.text or "")
		if g.form == "suf" then R.suf[t] = true
		elseif g.form == "pre" or g.form == "hyph" then R.pre[#R.pre + 1] = (t:gsub("%-$", ""))
		end
		for w in t:gmatch("[^ %-']+") do R.words[w] = true end
	end
	for _, a in ipairs(L.affixes) do
		if not (a.flags["61"] and not r61) then
			local tpl = lowerAll(a.text or "")
			local lit = tpl:gsub("%%%a", " ")
			-- (NEXT_PHASE_BRIEF 61: an evocative or industry name's words keep their roots: "Ashgrove" counts ^ash)
			if not (a.flags.g or a.flags.i) then
				for w in lit:gmatch("[^ %-']+") do R.words[w] = true end
			end
			-- (a template without a literal word, "%s %p", "%e %k", "%b", has no family: its pattern would match any name)
			local fam = lit:match("[^ %-']+")
			if fam then
				-- (placeholders: any text)
				local pat = "^" .. (tpl:gsub("%%%a", "\001"):gsub(".", patEsc):gsub("\001", ".+")) .. "$"
				R.pats[#R.pats + 1] = { pat = pat, fam = "%" .. fam, rare = a.rare and ("%!" .. tpl:gsub("%s+", "_")) or nil,
					lit = #(lit:gsub("[%s%-']", "")) }
			end
		end
	end
	L[key] = R
	return R
end
M.rootIndex = rootIndex

-- the stem a word starts with ("mytdale" -> "myt"), or nil
local function wordRoot(R, w)
	if R.words[w] or NW.STOP[w] then return nil end
	for _, p in ipairs(R.pre) do
		if #p >= 2 and #w > #p + 2 and w:sub(1, #p) == p then
			local r = wordRoot(R, w:sub(#p + 1))
			if r then return r end
		end
	end
	for i, st in ipairs(R.stems) do
		if i > 4000 then break end
		if #w >= #st and w:sub(1, #st) == st then
			local rem = w:sub(#st + 1)
			if (rem == "" or rem == "s" or rem == "es") and #st >= 3 then return st end
			if rem ~= "" and R.suf[rem] then return st end
			if #st >= 4 and #rem >= 2 then return st end
		end
	end
	return nil
end

--- The budget's extra keys of a name in generator language L: roots ("^<stem>") and affix patterns ("%<family>",
--- "%!<rare template>"). skipWords = { [lower word] = true } (feature names: a shared river's stem is no root).
function M.extraKeys(L, name, skipWords, r61)
	if L == nil or L.script or type(name) ~= "string" then return {} end
	local R = rootIndex(L, r61)
	local c = R.cache[name]
	if c and skipWords == nil then return c end
	local out, seen = {}, {}
	local low = lowerAll(name)
	for w in low:gmatch("[^ %-']+") do
		if #w >= 2 and not (skipWords and skipWords[w]) then
			local r = wordRoot(R, w)
			if r then
				r = "^" .. NW.fold(r)
				if not seen[r] then seen[r] = true; out[#out + 1] = r end
			end
		end
	end
	-- (a name may match several templates, "X-under-Edge" also "%s-under-%m": the rare key of the most literal one)
	local rareKey, rareLit = nil, -1
	for _, p in ipairs(R.pats) do
		if low:find(p.pat) then
			if not seen[p.fam] then seen[p.fam] = true; out[#out + 1] = p.fam end
			if p.lit > rareLit then rareKey, rareLit = p.rare, p.lit end
		end
	end
	if rareKey and not seen[rareKey] then seen[rareKey] = true; out[#out + 1] = rareKey end
	table.sort(out)
	if skipWords == nil then
		if R.n >= M.ROOT_CACHE then R.cache, R.n = {}, 0 end
		R.cache[name], R.n = out, R.n + 1
	end
	return out
end

--- Gives budget B the generator's extra keys for language lang (roots, affix patterns); features = { [lower word] =
--- true } (the map's river / lake / mountain / bay stems, counted by the qualifier rule instead). Returns B.
function M.attachExtra(B, lang, features, r61)
	local L = lang and M.lang(lang) or nil
	if B == nil or L == nil or L.script then return B end
	B.features = features
	local cache, n = {}, 0
	B.extra = function(name)
		local c = cache[name]
		if c == nil then
			c = M.extraKeys(L, name, B.features, r61)
			if n >= M.ROOT_CACHE then cache, n = {}, 0 end
			cache[name], n = c, n + 1
		end
		return c
	end
	return B
end

--- Does the context's climate rule entry e out (an own tag the climate never takes, ot_climate.VETO_TAGS)? Counts the
--- misfit (the log's misfit=). Returns true / false.
function M.climateVeto(ctx, e)
	local c = ctx and ctx.climate
	if c == nil then return false end
	-- (NEXT_PHASE_BRIEF 53 Part B: forms the climate never takes, a tropical map's -thorpe / -by / -ham)
	if ctx.cl and e.raw and ctx.cl.veto[e.raw] then
		M.misfit(ctx, e.k or e.text, c .. "/form")
		return true
	end
	for _, p in ipairs(e.tl or {}) do
		if p[2] >= CL.VETO_MIN and CL.vetoTag(c, p[1]) then
			M.misfit(ctx, e.k or e.text, c .. "/" .. p[1])
			return true
		end
	end
	return false
end

--- Counts a misfit word (ctx.misfit: { [word:reason] = n }).
function M.misfit(ctx, word, reason)
	if ctx == nil then return end
	ctx.misfit = ctx.misfit or {}
	local k = tostring(word or "?"):gsub("[%s,:=]", "_") .. ":" .. tostring(reason or "?")
	if ctx.misfit[k] == nil then ctx.misfitN = (ctx.misfitN or 0) + 1 end
	if ctx.misfit[k] or (ctx.misfitN or 0) <= 64 then ctx.misfit[k] = (ctx.misfit[k] or 0) + 1 end
end

--- "Oak:tropical/oak:3,..." (the climate's and the survey's rejects), "-" for none.
function M.misfitText(m, n)
	local list = {}
	for k, v in pairs(m or {}) do list[#list + 1] = { k, v } end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	local parts = {}
	for i, e in ipairs(list) do
		if i > (n or 12) then break end
		parts[#parts + 1] = e[1] .. (e[2] > 1 and ("x" .. e[2]) or "")
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- Is entry e out under the map's rules (NEXT_PHASE_BRIEF 60 / 61: s53 without the +60 entries, s53 and s60 without
--- the +61 ones)?
function M.ruleOut(ctx, e)
	local f = e.flags or {}
	if f["61"] and ctx.rules ~= "s61" then return true end
	return ctx.rules == "s53" and f["60"] == true
end

local function rankParts(ctx, list, x, t, which, useTbl, useK)
	local out = {}
	for i, e in ipairs(list) do
		local f, bt = M.fit(e, x)
		local blk = nil
		if M.climateVeto(ctx, e) then f = -1e6 end
		-- (the s53 rules, the lab's comparison: without the entries NEXT_PHASE_BRIEF 60 added, +60)
		if M.ruleOut(ctx, e) then f, blk = -1e6, true end
		if e.flags.p and f > 0 and not t.quiet then f = f * M.PERS_K end
		-- (2026-10-14, NEXT_PHASE_BRIEF 53: a quiet town's parts name no feature; a granted feature's stem first; a part of
		-- another dialect area's group far down)
		if t.quiet and M.ideaOf(e.river and "river" or e.main) then f = f - M.QUIET_PEN end
		if e.boost then f = f + e.boost end
		-- (NEXT_PHASE_BRIEF 53 Part B: the town's settlement layer, the climate's own forms, water on a dry map)
		if t.layer then f = f + M.layerAdj(ctx.L, e, t.layer) end
		if ctx.cl and e.raw and ctx.cl.boost[e.raw] then f = f + M.CLIMATE_BOOST end
		if ctx.climate == "dry" and e.main and M.WATER_TAG[e.main] and (x[e.main] or 0) > 0 then f = f + M.DRY_WATER end
		if e.grp and ctx.cl and ctx.cl.group and e.grp == ctx.cl.group.grp then
			if t.glayer == e.grp then f = f + M.GLAYER_K else f = f - M.DIALECT_PEN end
		end
		if t.dialect and e.grp and (t.dialect.w[e.grp] or 1) < 1 then f = f - M.DIALECT_PEN end
		local m = regionMul(e, t.dialect)
		-- (the dialect shapes the generics; stems feel it less: a Norse area is not a row of Norse personal names)
		if which == "s" then m = math.sqrt(m) end
		if f > 0 then f = f * m else f = f - 0.1 * (1 - m) end
		f = f + 0.15 * (m - 1)
		if e.rare then f = f + (t.character and M.RARE_ON or -M.RARE_OFF) end
		f = f - (useTbl[e.k or e.text] or 0) * useK
		-- (2026-10-14: a part whose own word the budget holds here: far down, so the first candidates fit the budget)
		if t.blocked and next(t.blocked) ~= nil then
			for _, k in ipairs(M.partKeys(e, t.cls)) do
				if t.blocked[k] then f = f - M.BUDGET_PEN break end
			end
		end
		-- (NEXT_PHASE_BRIEF 60, a map's towns: an opaque stem or generic far down and at most opaqueCap per map; a flavor
		-- part only on a planned flavor town, while the map's flavor names are under flavorCap)
		if ctx.opaqueCap and M.opaque(e) then
			if ctx.opaqueN >= ctx.opaqueCap then f, blk = -1e6, true else f = f - M.OPAQUE_PEN end
		end
		if ctx.flavorCap and M.flavorPart(e) then
			if t.flavor and ctx.flavorN < ctx.flavorCap then f = f + M.FLAVOR_ON else f, blk = -1e6, true end
		end
		-- (the climate's settler group, the Spanish of a dry US map, is flavor too: only on its own towns, under the cap)
		if ctx.flavorCap and e.grp and ctx.cl and ctx.cl.group and e.grp == ctx.cl.group.grp
			and (t.glayer ~= e.grp or ctx.flavorN >= ctx.flavorCap) then f, blk = -1e6, true end
		f = f + M.JITTER * rng.unit(ctx.seed, which, t.id or 0, i)
		out[#out + 1] = { e = e, f = f, bt = bt, i = i, blk = blk }
	end
	table.sort(out, function(a, b)
		if a.f ~= b.f then return a.f > b.f end
		return a.i < b.i
	end)
	return out
end

local function family(tag)
	-- (the root of a tag's broader ones: mouth -> river, spit -> coast, oak -> forest)
	if tag == nil then return nil end
	local p = M.PARENT[tag]
	while p and p[1] do
		tag = p[1]
		p = M.PARENT[tag]
	end
	return tag
end

M.family = family

---------------------------------------------------------------------------
-- name shapes (2026-10-14, NEXT_PHASE_BRIEF 53 Part A; names/review/REVIEW_ANSWERS.md Q1, Q4, Q7). Run 1729 framed 11 of
-- 16 names: each town scored stem, generic and affix together, and on a map with a strong survey a frame fits almost
-- everywhere. Now the map picks each town's shape first (M.planShapes: per language a share for each shape, handed to
-- the towns with the strongest claim), then the words fill that shape (M.nameTown with t.shape).
--   plain      a compound ("Ashford", "Swainthorpe"; a personal name + generic too, except usa)
--   single     one element ("Combe", "Hagen", "Torre": a +o generic alone)
--   separate   name + separate generic ("Cedar Rapids", "Hayes City": a word generic after or before)
--   personal   (usa) a personal name + generic ("Hayesville")
--   article    "La Hoya", "Le Val" (a gendered generic with its article)
--   qualifier  Upper / Little / North ... (+q): twins only (a town with the same base within TWIN_MAX_M), Upper / Lower
--              on the stem of the town's named river ("Lower Arunmouth"), joined ones by the site ("Oberdorf")
--   frame      "-on-X", "-sur-X", "an der X": on a common base or a base already on the map, once per river
--   saint      "%s St %p", "Saint-Aubin"
--   whole      a landmark name ("Three Rivers", "Middle Fork", "Port X")
--   civic      Junction, Station, Center (+v)

--   character  (NEXT_PHASE_BRIEF 53 Part B) a character town of a kind (town.character = "hilltop" ...): one of the
--              kind's striking forms (the language's charForms: "-on-the-Hill", "Cove", "Garden City", "Market X")
--   evoc       (NEXT_PHASE_BRIEF 61) an evocative whole name that plainly describes the site, on its gate ("Two Waters",
--              "Seven Oaks", "Windy Ridge")
--   industry   (NEXT_PHASE_BRIEF 61) a form of the industry near the town ("Oil Springs", "Brickfield", "X Harbour")
M.SHAPES = { "plain", "single", "separate", "personal", "article", "qualifier", "frame", "saint", "whole", "civic",
	"character", "evoc", "industry" }
M.AFFIX_SHAPES = { qualifier = true, frame = true, saint = true, whole = true, civic = true, character = true, evoc = true,
	industry = true }
-- tags that name no feature of the land (a quiet name has none)
M.NON_IDEA = { any = true, plain = true, field = true, market = true, big = true, small = true, character = true,
	district = true, works = true, old = true, new = true, church = true }
-- words a name's token count skips
M.FUNC_WORDS = {}
for w in ("on upon in the by under over of and at sur sous les le la de du des di del della dello da do dos das am an "
	.. "der den die dem im aan het op bij en aux au"):gmatch("%S+") do M.FUNC_WORDS[w] = true end

--- An affix's shape, qualifier kind and form (set on the entry): a.shape ("civic" | "whole" | "saint" | "qualifier" |
--- "frame"), a.qkind ("compass" with a.qdir, "small", "big", "upper", "lower", "age", "other"), a.joined (no space or
--- hyphen: "Ober%l", "新%s"), a.mapDir (the town's side of the map, %D: never; a compass word relates to a twin or a
--- named feature).
function M.affixShape(a)
	-- (NEXT_PHASE_BRIEF 61: an industry form, +i, and an evocative name, +g, have their own shapes)
	if a.flags.i then a.shape = "industry"
	elseif a.flags.g and not a.hasS then a.shape = "evoc"
	elseif a.flags.v then a.shape = "civic"
	elseif a.needP then a.shape = "saint"
	elseif a.bare or not a.hasS then a.shape = "whole"
	elseif a.flags.q then a.shape = "qualifier"
	else a.shape = "frame" end
	a.mapDir = a.needD == true
	a.joined = not (a.text or ""):find("[ %-]")
	if a.shape == "qualifier" then
		local kind, dir = "other", nil
		for _, p in ipairs(a.tl) do
			local t = p[1]
			if t == "north" or t == "south" or t == "east" or t == "west" then kind, dir = "compass", t break end
		end
		if kind == "other" then
			for _, p in ipairs(a.tl) do
				local t = p[1]
				if t == "small" then kind = "small" break
				elseif t == "big" then kind = "big" break
				elseif t == "upper" or t == "slope" or t == "hilltop" then kind = "upper" break
				elseif t == "lower" or t == "foot" then kind = "lower" break
				elseif t == "new" or t == "old" then kind = "age" break end
			end
		end
		a.qkind, a.qdir = kind, dir
	end
	return a.shape
end

--- The feature a tag names (its family), or nil for a tag that names none (M.NON_IDEA).
function M.ideaOf(tag)
	if tag == nil or M.NON_IDEA[tag] then return nil end
	local f = family(tag)
	if f == nil or M.NON_IDEA[f] then return nil end
	return f
end

--- The features a name names: its stem's, its generic's and its affix's (a twin's qualifier marks the twin, no
--- feature). Returns the count.
function M.ideas(sE, gE, aE, twin)
	local seen, n = {}, 0
	local function add(tag)
		local f = M.ideaOf(tag)
		if f and not seen[f] then seen[f] = true; n = n + 1 end
	end
	if aE and not aE.hasS then
		add(aE.main)
		return n
	end
	if sE then add(sE.river and "river" or sE.main) end
	if gE then add(gE.main) end
	if aE and not twin then add(aE.main) end
	return n
end

--- Words of a name (spaces and hyphens; articles and prepositions not counted; at least 1).
function M.tokens(name)
	if type(name) ~= "string" then return 0 end
	if not name:find("[ %-]") then return 1 end
	local n = 0
	for w in lowerAll(name):gmatch("[^ %-]+") do
		if not M.FUNC_WORDS[w] then n = n + 1 end
	end
	return math.max(n, 1)
end

-- the shape of a candidate without an affix (Q: the map's shape shares, ot_placename.climateOf; default the language's)
local function baseShape(L, c, Q)
	if c.shape then return c.shape end
	Q = Q or L.quota
	local g, s = c.g.e, c.s.e
	if g.flags.v then return "civic" end
	if (g.form == "after" or g.form == "before") and Q.separate then return "separate" end
	if s.flags.p and Q.personal then return "personal" end
	return "plain"
end
M.baseShape = baseShape

-- (2026-10-14, NEXT_PHASE_BRIEF 50 items 1-2: a shared river or mountain qualifier repeats once at most, never as the
-- same kind: run 1729 load 4 had Port Big Sandy, Big Sandy Valley and Big Sandy Junction on one river, Mount Spruce and
-- South Spruce Valley) The feature stems a candidate uses: { { stem, qual, whole } }.
local function featureUses(ctx, t, c, a)
	local out = {}
	local whole = a ~= nil and not a.hasS
	local function low(x) return type(x) == "string" and lowerAll(x) or nil end
	if a then
		if (a.needR or a.needT) and t.river then out[#out + 1] = { low(t.river.s or t.river.n), true, whole } end
		if a.needM and t.mount then out[#out + 1] = { low(t.mount.s), true, whole } end
		if a.needK and t.lake then out[#out + 1] = { low(t.lake.s or t.lake.n), true, whole } end
		if a.needB and t.bay then out[#out + 1] = { low(t.bay.s), true, whole } end
	end
	local se = c and c.s and c.s.e
	if se then
		local st = low(se.k or se.text)
		if se.river then out[#out + 1] = { st, true, false }
		elseif st and ctx.featWords and ctx.featWords[st] then out[#out + 1] = { st, false, false } end
	end
	return out
end

-- May the candidate use those feature stems? At most FEAT_MAX uses per feature, the second only as a qualifier after a
-- qualifier, and one whole-name form per feature.
M.FEAT_MAX = 2
local function featureOk(ctx, uses)
	for _, u in ipairs(uses) do
		local f = u[1] and ctx.featUse[u[1]]
		if f then
			if f.n >= M.FEAT_MAX or not u[2] or f.plain > 0 or (u[3] and f.whole > 0) then
				M.misfit(ctx, u[1], "feature")
				return false
			end
		end
	end
	return true
end

local function featureTake(ctx, uses)
	for _, u in ipairs(uses) do
		if u[1] then
			local f = ctx.featUse[u[1]] or { n = 0, plain = 0, whole = 0 }
			f.n = f.n + 1
			if not u[2] then f.plain = f.plain + 1 end
			if u[3] then f.whole = f.whole + 1 end
			ctx.featUse[u[1]] = f
		end
	end
end

-- placeholder parts of the shapes without a stem or a generic (single, article, a frame's common base)
local EMPTY_S = newEntry("-")
EMPTY_S.kind, EMPTY_S.x = "stem", {}
local EMPTY_G = newEntry("-")
EMPTY_G.form, EMPTY_G.x = "none", {}

local function commonEntry(L, base)
	L.commonE = L.commonE or {}
	local e = L.commonE[base]
	if e == nil then
		e = newEntry(base)
		e.kind, e.x, e.common = "stem", {}, true
		L.commonE[base] = e
	end
	return e
end

-- (the map's words: an extra word per name beyond the first counts against ctx.wordAllow; a planned affix shape's first
-- extra word was reserved by the plan)
function M.countWords(ctx, nm, reserved)
	if ctx.wordAllow == nil then return end
	local extra = M.tokens(nm) - 1 - (reserved and 1 or 0)
	if extra > 0 then ctx.wordExtra = ctx.wordExtra + extra end
	ctx.wordN = ctx.wordN + 1
end

--- Would extra more words go over the map's words so far (the allowance pro rata of the towns named, + half a word)?
function M.wordsOver(ctx, extra)
	if ctx.wordAllow == nil or extra <= 0 then return false end
	return ctx.wordExtra + extra > ctx.wordAllow * (ctx.wordN + 1) / math.max(1, ctx.wordTowns) + 0.5
end

--- Names town t: t = { id, x, y, w (site weights, M.siteTags), character, river = { n, s } or nil, lake = { n, s } or
--- nil, specs = extra stems in front (the river's), specList / gens = stems / generics instead of the language's
--- (M.works), fixedSpec = the one stem every candidate uses (M.related), noAffix, noSuffix (no 市), shape (M.SHAPES:
--- the shape M.planShapes gave the town; nil: any, as for districts and Works), quiet, qualMode = "river" with qualKind
--- "upper" | "lower" (a qualifier on the named river's stem) }. Returns name, info = { spec, gen, affix, feature, score,
--- dialect, shape, quiet, hybrid } or nil, why ("noUnique").
function M.nameTown(ctx, t)
	local L = ctx.L
	t.seed = ctx.seed
	-- (NEXT_PHASE_BRIEF 53 Part B: the map's shape shares and saints by its climate)
	local Q = ctx.quota or L.quota
	if t.saints == nil and ctx.cl then t.saints = ctx.cl.saints end
	local x = M.expandSite(t.w or {})
	t.dialect = t.dialect or M.dialectAt(ctx, t.x, t.y)
	local shape = t.shape
	-- (a town away from a dialect border never blends two groups)
	local strict = shape ~= nil and t.dialect ~= nil and not t.dialect.hybrid
	local specList = t.fixedSpec and { t.fixedSpec } or t.specList or L.specs
	if t.specs and not t.fixedSpec then
		local base = specList
		specList = {}
		for _, e in ipairs(t.specs) do specList[#specList + 1] = e end
		for _, e in ipairs(base) do specList[#specList + 1] = e end
	end
	if ctx.budget then
		t.cls = ctx.budget.cls
		t.blocked = NW.blockedKeys(ctx.budget, t.x, t.y, t.skipWords)
	end
	local gens = rankParts(ctx, t.gens or L.gens, x, t, "g", ctx.genUse, M.USE_GEN)
	local specs = rankParts(ctx, specList, x, t, "s", ctx.specUse, M.USE_SPEC)
	local count = ctx.plan and ctx.plan.count or {}
	ctx.shapeUse = ctx.shapeUse or {}
	local need = shape ~= nil and M.AFFIX_SHAPES[shape] == true
	local function search(ns, ng)
		local cands = {}
		for si = 1, math.min(ns, #specs) do
			local s = specs[si]
			for gi = 1, math.min(ng, #gens) do
				local g = gens[gi]
				local base = (not s.blk and not g.blk) and M.join(L, s.e, g.e, strict) or nil
				-- (+e, NEXT_PHASE_BRIEF 60: a generic in front that wants a noun after it, never an adjective +a: no
				-- "Lake Shady")
				if base and g.e.flags.e and s.e.flags.a and ctx.rules ~= "s53" then base = nil end
				-- (a civic generic only on a late town that is no natural confluence, NEXT_PHASE_BRIEF 53 Part B)
				if base and g.e.flags.v and t.noCivic then base = nil end
				if base and M.wellFormed(L, base) then
					local sc = g.f + M.SPEC_K * s.f
					if s.bt and g.bt and s.bt ~= g.bt and family(s.bt) ~= family(g.bt) and s.f > 0.3 and g.f > 0.3 then
						sc = sc + M.PAIR_BONUS
					end
					-- (NEXT_PHASE_BRIEF 60: descriptive first; a town that isn't one of the map's few quiet towns names a
					-- feature of its site: a pair that names none ranks LITERAL_PEN lower)
					if ctx.opaqueCap and shape ~= nil and not t.quiet and M.ideas(s.e, g.e) == 0 then sc = sc - M.LITERAL_PEN end
					local c = { base = base, s = s, g = g, sc = sc }
					-- (a soft shape over its count on the map: separate / personal names go back to plain compounds)
					if shape ~= nil then
						local bs = baseShape(L, c, Q)
						if (bs == "separate" or bs == "personal" or bs == "civic") and (ctx.shapeUse[bs] or 0) >= (count[bs] or 0) then
							c.sc = c.sc - M.SHAPE_OVER
						elseif bs == "separate" and ctx.rules ~= "s53" and not need then
							-- (NEXT_PHASE_BRIEF 60: "multi word names that help make it clear its context-aware" while the
							-- map's count of them lasts)
							c.sc = c.sc + M.SEP_BONUS
						end
						-- (a character town's forms go on a one-word base: those first)
						if shape == "character" and M.tokens(base) > 1 then c.sc = c.sc - M.SHAPE_OVER end
						-- (the map's words: a plain town's extra word only while the language's average allows it)
						if ctx.wordAllow and not need and M.tokens(base) > 1 and M.wordsOver(ctx, M.tokens(base) - 1) then
							c.sc = c.sc - M.SHAPE_OVER
						end
					end
					cands[#cands + 1] = c
				end
			end
		end
		table.sort(cands, function(a, b)
			if a.sc ~= b.sc then return a.sc > b.sc end
			return a.base < b.base
		end)
		return cands
	end
	local final = function(full) return (L.script == "kanji" and not t.noSuffix) and (full .. "市") or full end
	local function within(nm, skip)
		-- (the finished name's words against the climate, ot_climate.wordMisfit: a river or lake name, a cue word)
		if ctx.climate then
			local bad = CL.wordMisfit(nm, ctx.climate, M.CLS_OF_GEN[ctx.lang] or ctx.lang)
			if bad then M.misfit(ctx, bad, ctx.climate) return false end
		end
		-- (the map's word budget, ot_namewords: a generic word at most once per PER_TOWNS towns, never twice within NEAR_M;
		-- a derived name skips its parent's words)
		return NW.allow(ctx.budget, nm, t.x, t.y, skip or t.skipWords)
	end
	-- (a shaped town: at most MAX_TOKENS words, MAX_IDEAS features)
	local function sized(nm, c, a)
		if shape == nil then return true end
		local k = M.tokens(nm)
		-- (an affix's second extra word only while the map's words allow it: no "Rock Falls Center" over the average)
		if a and k > 2 and shape ~= "character" and M.wordsOver(ctx, k - 2) then return false end
		-- (NEXT_PHASE_BRIEF 61: a character town's form names its kind on top: one feature more)
		local extraIdea = (shape == "character" and ctx.rules == "s61") and 1 or 0
		return k <= M.MAX_TOKENS and M.ideas(c.s.e, c.g.e, a) <= M.MAX_IDEAS + extraIdea
	end
	local function affixOk(a, c)
		-- (a character kind's own forms, +k, only on such a town; civic forms only where civic names may go)
		if a.flags.k and shape ~= "character" then return false end
		-- (NEXT_PHASE_BRIEF 61: evocative and industry names only on their shapes)
		if (a.shape == "evoc" or a.shape == "industry") and shape ~= a.shape then return false end
		if shape == "character" then
			local set = t.charKind and (ctx.charForms or L.charForms)[t.charKind]
			-- (NEXT_PHASE_BRIEF 61: a romance base of two words, "Campo Grande", may take its kind's form too; a one-word
			-- base ranks first, search)
			return set ~= nil and set[a.raw or ""] == true and not a.mapDir and (M.tokens(c.base) == 1 or ctx.rules == "s61")
		end
		if shape == "evoc" then return a.shape == "evoc" and M.gateOk(a, t.wraw, t.facts) end
		if shape == "industry" then
			if a.shape ~= "industry" or t.ind == nil or a.fam ~= t.ind.fam then return false end
			return true
		end
		if a.flags.v and t.noCivic then return false end
		if shape == nil then return true end
		if a.shape ~= shape or a.mapDir then return false end
		if shape == "qualifier" then
			-- (on a one-word base, where names of separate words aren't the language's own: no "Vega del Sauce de Arriba")
			if not Q.separate and M.tokens(c.base) > 1 then return false end
			if t.qualMode == "river" then return a.qkind == t.qualKind and not a.joined and c.s.e.river == true end
			return a.qkind == "age" or a.qkind == "other" or (a.joined and (a.qkind == "upper" or a.qkind == "lower"))
		end
		if shape == "frame" then
			if t.frameFeat and not (a.needR or a.needT or a.needK or a.needM or a.needB) then return false end
			-- (each frame once per FRAME_PER towns, at most one per river)
			if (ctx.affUse[a.k or a.text] or 0) >= ctx.frameCap then return false end
			if (a.needR or a.needT) and t.river and ctx.riverFrame[t.river.s or t.river.n] then return false end
			-- (a frame goes on a one-word base and never names the base's river twice: no "Val-des-Chênes-aux-Bois",
			-- "Sioulelieu-sur-Sioule")
			if M.tokens(c.base) > 1 then return false end
			if (a.needR or a.needT) and t.river and t.river.s and lowerAll(c.base):find(lowerAll(t.river.s), 1, true) then return false end
		end
		return true
	end
	local function choose(cands, anyAffix, maxC, need)
		local cost = t.character and M.AFFIX_COST_CH or M.AFFIX_COST
		for ci, c in ipairs(cands) do
			if ci > (maxC or 40) then break end
			-- the affix that fits best (a feature the generic doesn't already say)
			local bestA, bestS, bestN = nil, (anyAffix or need) and -math.huge or 0, nil
			if not t.noAffix and (shape == nil or need) then
				for ai, a in ipairs(L.affixes) do
					if affixOk(a, c) and not M.ruleOut(ctx, a) then
						local raw, abt = M.fit(a, x)
						local af = raw
						if M.climateVeto(ctx, a) then af = -1e6 end
						if a.rare then af = af + (t.character and M.RARE_ON or -M.RARE_OFF) end
						af = af - cost + 0.1 * rng.unit(ctx.seed, "a", t.id or 0, ai)
						af = af - (ctx.affUse[a.k or a.text] or 0) * M.USE_AFFIX
						local fam = family(abt)
						local clash = a.cls ~= nil and (a.cls == c.s.e.cls or a.cls == c.g.e.cls)
						-- (an affix without the base is the whole name: "Cedar Falls", "Three Rivers", only on a strong cue)
						local whole = not a.hasS
						-- (a shaped town takes its shape's best affix that claims nothing the site lacks; a saint fits anywhere)
						local fits = raw > 0 or a.shape == "saint" or shape == "character" or shape == "industry"
						local okWhole = whole and (t.character or af >= M.FULL_MIN or (need and fits))
						if (af > bestS) and not clash and (a.hasS or okWhole) and (not need or fits)
							and (whole or (not M.repeats(a, c.base) and not (fam and fam == family(c.g.bt) and fam ~= "any"))) then
							local full = fillAffix(L, a, c.base, t)
							if full and M.chars(full) <= M.MAX_FULL and M.free(ctx, final(full)) and sized(final(full), c, a)
								and featureOk(ctx, featureUses(ctx, t, c, a)) and within(final(full), c.skip) then
								bestA, bestS, bestN = a, af, full
							end
						end
					end
				end
			end
			if bestA then return c, bestA, bestN, bestS end
			if not anyAffix and not need and M.free(ctx, final(c.base)) and sized(final(c.base), c, nil)
				and featureOk(ctx, featureUses(ctx, t, c, nil)) and within(final(c.base), c.skip) then return c, nil, c.base, 0 end
		end
		return nil
	end
	-- the candidates of the shapes without a stem + generic pair
	local function singleCands()
		local out = {}
		if L.script then return out end
		for _, g in ipairs(gens) do
			if #out >= 30 then break end
			if g.e.flags.o and g.f > -1e5 then
				local base = M.capFirst(g.e.text)
				if M.wellFormed(L, base) then out[#out + 1] = { base = base, s = { e = EMPTY_S, f = 0 }, g = g, sc = g.f, shape = "single" } end
			end
		end
		return out
	end
	local function articleCands()
		local out = {}
		local A = L.articles
		if type(A) ~= "table" or L.script then return out end
		for _, g in ipairs(gens) do
			if #out >= 30 then break end
			local e = g.e
			if e.gender and A[e.gender] and (e.form == "before" or e.form == "pre") and g.f > -1e5 then
				local base
				if A.el and e.text:sub(1, 1):match("[AEIOUaeiou]") then base = A.el .. e.text
				else base = A[e.gender] .. " " .. e.text end
				out[#out + 1] = { base = base, s = { e = EMPTY_S, f = 0 }, g = g, sc = g.f, shape = "article" }
			end
		end
		return out
	end
	-- (a frame goes on a common base, "Sutton-on-Arun", or on a base already on the map: "Ashford" and "Ashford-on-Dart")
	local function frameBases()
		local out = {}
		for i, b in ipairs(L.common) do
			out[#out + 1] = { base = b, s = { e = commonEntry(L, b), f = 0 }, g = { e = EMPTY_G, f = 0 },
				sc = M.JITTER * rng.unit(ctx.seed, "cb", t.id or 0, i), common = true }
		end
		for i, pb in ipairs(ctx.rules ~= "s53" and {} or ctx.plainBases or {}) do
			if not pb.framed then
				out[#out + 1] = { base = pb.base, s = { e = commonEntry(L, pb.base), f = 0 }, g = { e = EMPTY_G, f = 0 },
					sc = 0.15 + M.JITTER * rng.unit(ctx.seed, "rb", t.id or 0, i), reuse = pb, skip = pb.keys }
			end
		end
		table.sort(out, function(a, b)
			if a.sc ~= b.sc then return a.sc > b.sc end
			return a.base < b.base
		end)
		return out
	end
	local function attempt(need)
		local cc, aa, nn, ss = choose(search(M.TOP_SPEC, M.TOP_GEN), false, nil, need)
		if cc == nil then
			local wide = search(M.WIDE_SPEC, M.WIDE_GEN)
			-- (a shape's affix that fits none of the first NEED_WIDE candidates: the town goes plain)
			cc, aa, nn, ss = choose(wide, false, need and M.NEED_WIDE or M.WIDE_SPEC * M.WIDE_GEN, need)
			if cc == nil and shape == nil then cc, aa, nn, ss = choose(wide, true, 200) end
			-- (the budget left nothing: the best name over it, counted as `over`)
			if cc == nil and ctx.budget and not t.strictBudget and not need then
				local b = ctx.budget
				ctx.budget = nil
				cc, aa, nn, ss = choose(wide, false, M.WIDE_SPEC * M.WIDE_GEN)
				ctx.budget = b
				if cc then b.over = (b.over or 0) + 1 end
			end
		end
		return cc, aa, nn, ss
	end
	local first = nil
	if shape == "single" then first = singleCands()
	elseif shape == "article" then first = articleCands()
	elseif shape == "frame" and #L.common > 0 then first = frameBases() end
	local c, a, nm, as
	-- (NEXT_PHASE_BRIEF 60, "frame on a feature": a descriptive base framed by the town's named river, lake, peak or bay
	-- first, "Oakhaven-on-Blackmere"; then the common bases)
	if shape == "frame" and ctx.rules ~= "s53" then
		t.frameFeat = true
		c, a, nm, as = attempt(need)
		t.frameFeat = nil
	end
	if c == nil then
		if first then c, a, nm, as = choose(first, false, 400, need)
		else c, a, nm, as = attempt(need) end
	end
	-- (NEXT_PHASE_BRIEF 61: a character town always carries its kind: its forms over the word budget before a plain name,
	-- counted as `over`)
	if c == nil and shape == "character" and ctx.rules == "s61" and ctx.budget then
		local b = ctx.budget
		ctx.budget = nil
		c, a, nm, as = attempt(need)
		ctx.budget = b
		if c then b.over = (b.over or 0) + 1 end
	end
	-- (a shape that found no name: a plain one)
	if c == nil and shape ~= nil and shape ~= "plain" then
		ctx.shapeMiss = (ctx.shapeMiss or 0) + 1
		shape, need = "plain", false
		c, a, nm, as = attempt(false)
	end
	if c == nil then return nil, "noUnique" end
	nm = final(nm)
	M.take(ctx, nm)
	local opq = M.opaque(c.s.e) or M.opaque(c.g.e)
	local grp0 = ctx.cl and ctx.cl.group and ctx.cl.group.grp
	local flv = M.flavorPart(c.s.e) or M.flavorPart(c.g.e) or M.flavorPart(a)
		or (grp0 ~= nil and (c.s.e.grp == grp0 or c.g.e.grp == grp0))
	if opq then ctx.opaqueN = ctx.opaqueN + 1 end
	if flv then ctx.flavorN = ctx.flavorN + 1 end
	featureTake(ctx, featureUses(ctx, t, c, a))
	NW.add(ctx.budget, nm, t.x, t.y, c.skip or t.skipWords)
	local sk, gk = c.s.e.k or c.s.e.text, c.g.e.k or c.g.e.text
	ctx.specUse[sk] = (ctx.specUse[sk] or 0) + 1
	ctx.genUse[gk] = (ctx.genUse[gk] or 0) + 1
	if a then ctx.affUse[a.k or a.text] = (ctx.affUse[a.k or a.text] or 0) + 1 end
	local got = (a and a.shape) or baseShape(L, c, Q)
	if a and shape == "character" then got = "character" end
	if t.shape ~= nil then
		ctx.shapeUse[got] = (ctx.shapeUse[got] or 0) + 1
		M.countWords(ctx, nm, need)
		if a and a.shape == "frame" and (a.needR or a.needT) and t.river then ctx.riverFrame[t.river.s or t.river.n] = true end
		if c.reuse then c.reuse.framed = true end
		if a == nil and got ~= "single" and got ~= "article" and not L.script then
			ctx.plainBases = ctx.plainBases or {}
			if #ctx.plainBases < M.MAX_TOWNS then
				ctx.plainBases[#ctx.plainBases + 1] = { base = c.base, keys = ctx.budget and NW.budgetKeys(ctx.budget, c.base) or {} }
			end
		end
	end
	local feat = c.g.bt or c.s.bt or "-"
	return nm, { spec = sk, gen = gk, affix = a and (a.k or a.text) or nil, whole = a ~= nil and not a.hasS, feature = feat, specTag = c.s.bt,
		genTag = c.g.bt, score = c.sc + (as or 0), dialect = t.dialect and t.dialect.name or nil, base = c.base, layer = t.layer,
		charKind = t.charKind, ind = (got == "industry" and t.ind) and t.ind.fam or nil,
		gate = got == "evoc" and M.gateText(a, t.wraw, t.facts) or nil,
		-- (NEXT_PHASE_BRIEF 61: an evocative name, an industry or character form names a cue of the town: never quiet)
		sE = c.s.e, gE = c.g.e, aE = a, shape = got,
		quiet = M.ideas(c.s.e, c.g.e, a) == 0
			and not (ctx.rules == "s61" and (got == "evoc" or got == "industry" or got == "character")), reuse = c.reuse and c.reuse.base or nil,
		opaque = opq, flavor = flv,
		hybrid = t.dialect ~= nil and t.dialect.hybrid == true }
end

--- "Ash+ford+%s-upon-%r" for the log.
function M.partsText(info)
	if info == nil then return "-" end
	if info.whole then return "whole:" .. (info.affix or "-"):gsub(" ", "_") end
	return string.format("%s+%s+%s", info.spec or "-", info.gen or "-", info.affix and (info.affix:gsub(" ", "_")) or "-")
end

---------------------------------------------------------------------------
-- the map

--- The map's cue tags merged into a town's site weights (cue = ot_mapshape.townCues: { w = { [tag] = weight } }).
function M.withCues(w, cue)
	local out = {}
	for k, v in pairs(w or {}) do out[k] = v end
	if type(cue) == "table" and type(cue.w) == "table" then
		for k, v in pairs(cue.w) do
			if M.TAG_INDEX[k] and tonumber(v) and v > (out[k] or 0) then out[k] = math.min(1, v) end
		end
	end
	return out
end

--- Ranked tags of weights w (>= 0.2, x specificity), as siteTags returns them.
function M.rankOf(w)
	local ranked = {}
	for _, t in ipairs(M.TAGS) do
		if (w[t] or 0) >= 0.2 then ranked[#ranked + 1] = { t, w[t] * (M.SPEC[t] or 1) } end
	end
	table.sort(ranked, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return M.TAG_INDEX[a[1]] < M.TAG_INDEX[b[1]]
	end)
	return ranked
end

-- the name list classifier of a generator language (the word budget's lexicon)
M.CLS_OF_GEN = { en = "en", usa = "usa", de = "de", fr = "fr", it = "it", es = "es", pt = "pt", nl = "nl", sv = "sv",
	nb = "nb", ja = "ja", ja_r = "ja_r" }

--- A named big feature for the map: kind "mount" (D.peaks, D.peakForm) or "bay" (D.bays else D.lakes, D.bayForm).
--- Returns { n, s } or nil (no data for the language).
function M.featName(ctx, kind, grp)
	local D = ctx.L.data
	if ctx.L.script then return nil end
	local stems = split(kind == "mount" and D.peaks or (D.bays or D.lakes), "|")
	local form = kind == "mount" and D.peakForm or D.bayForm
	-- (the peak's dialect area: a Fell in the Norse area, a Down in the Saxon core)
	if kind == "mount" and grp and type(D.peakFormBy) == "table" and D.peakFormBy[grp] then form = D.peakFormBy[grp] end
	if #stems == 0 or form == nil then return nil end
	ctx.featNames = ctx.featNames or {}
	local start = rng.hash(ctx.seed, "feat", kind) % #stems
	for i = 0, #stems - 1 do
		local stem = stems[(start + i) % #stems + 1]
		local full = (form:gsub("_", " "):gsub("%%s", function() return stem end))
		if not ctx.featNames[stem] and M.free(ctx, full) and M.free(ctx, stem) then
			ctx.featNames[stem] = true
			return { n = full, s = stem }
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- the map's plan: named features, shapes, twins (2026-10-14, NEXT_PHASE_BRIEF 53 Part A)

-- a climate veto without counting a misfit (claims are only estimates)
local function vetoed(ctx, e)
	local c = ctx and ctx.climate
	if c == nil then return false end
	if ctx.cl and e.raw and ctx.cl.veto[e.raw] then return true end
	for _, p in ipairs(e.tl or {}) do
		if p[2] >= CL.VETO_MIN and CL.vetoTag(c, p[1]) then return true end
	end
	return false
end

--- Can affix a be filled for naming input q (its river, lake, mountain, bay, the big lake's side, a saint)?
function M.fillable(L, a, q)
	if a.needR and not (q.river and q.river.n) then return false end
	if a.needT and not (q.river and q.river.s) then return false end
	if a.needK and not (q.lake and q.lake.n) then return false end
	if a.needM and not (q.mount and q.mount.s) then return false end
	if a.needB and not (q.bay and q.bay.s) then return false end
	if a.needE and not (q.ldir and L.dirWords[q.ldir]) then return false end
	if a.needD then return false end
	if a.needP and #(q.saints or L.saints) == 0 then return false end
	return true
end

-- the cue tags that claim each kind of named feature
M.FEAT_TAGS = { river = { "mouth", "confluence", "falls", "bend", "twin", "ford", "bridge", "upper", "lower", "river" },
	lake = { "biglake", "tarn", "mere", "pool", "lake" }, mount = { "peak", "summit", "divide", "range", "pass", "mountain" },
	bay = { "bigbay", "bay" } }

--- The named-feature budget (review Q2): each named river, lake, peak or bay goes into at most one town name per
--- FEAT_PER towns along it (FEAT_CAP at most), spent by the strongest claims first: the town's cue weight x how unique
--- its claim is (the only mouth beats one of three bends) x its size. feats = { { kind, key, members = { town index } } }.
--- Returns grants { [index] = { [kind] = true } }, the count of leftover claims (members with a claim but no grant) and
--- their list { { i, kind } } (NEXT_PHASE_BRIEF 53 Part B: they go to districts and stop names, M.leftClaim).
function M.featureGrants(ctx, list, ws, feats)
	local grants, left, leftList = {}, 0, {}
	local maxCap = 1
	for _, t in ipairs(list) do if (tonumber(t.cap) or 0) > maxCap then maxCap = tonumber(t.cap) end end
	for _, F in ipairs(feats) do
		local tags = M.FEAT_TAGS[F.kind] or {}
		local cl, tops = {}, {}
		for _, i in ipairs(F.members) do
			local best, bt = 0, nil
			for _, tag in ipairs(tags) do
				local v = (ws[i][tag] or 0) * (M.SPEC[tag] or 1)
				if v > best then best, bt = v, tag end
			end
			cl[#cl + 1] = { i = i, v = best, tag = bt }
			if bt then tops[bt] = (tops[bt] or 0) + 1 end
		end
		for _, e in ipairs(cl) do
			local uniq = e.tag and 1 / tops[e.tag] or 0
			local size = 0.6 + 0.4 * math.min(1, (tonumber(list[e.i].cap) or 0) / maxCap)
			e.c = e.v * uniq * size
		end
		table.sort(cl, function(a, b)
			if a.c ~= b.c then return a.c > b.c end
			return (tonumber(list[a.i].id) or 0) < (tonumber(list[b.i].id) or 0)
		end)
		local lim = clamp(math.floor(#F.members / M.FEAT_PER + 0.5), 1, M.FEAT_CAP)
		local n = 0
		for _, e in ipairs(cl) do
			if n < lim and e.c > 0 then
				grants[e.i] = grants[e.i] or {}
				-- (the strongest claim spends it: its stem first; the second may)
				grants[e.i][F.kind] = n == 0 and "first" or "second"
				n = n + 1
			elseif e.c > 0 then
				left = left + 1
				leftList[#leftList + 1] = { i = e.i, kind = F.kind }
			end
		end
	end
	return grants, left, leftList
end

-- the qualifier forms for twins by kind ("upper", "lower", "small", "big", "north" ...): affixes of no feature
local function twinForms(L)
	if L.twinF then return L.twinF end
	local F = {}
	for _, a in ipairs(L.affixes) do
		if a.shape == "qualifier" and not (a.needR or a.needT or a.needK or a.needM or a.needB or a.needE or a.needP) then
			local k = a.qkind == "compass" and a.qdir or a.qkind
			if k == "upper" or k == "lower" or k == "small" or k == "big" or k == "north" or k == "south" or k == "east" or k == "west" then
				F[k] = F[k] or {}
				F[k][#F[k] + 1] = a
			end
		end
	end
	L.twinF = F
	return F
end
M.twinForms = twinForms

local function dirFrom(dx, dy)
	if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "east" or "west" end
	return dy >= 0 and "north" or "south"
end
M.dirFrom = dirFrom

M.TWIN_MAX_TOWNS = 400    -- towns the twin search looks at (pairs: its square)

--- The oldness of a town for its settlement layer: its size share (cap / the map's largest) x LAYER_CAP_K + its best
--- LAYER_SITE claim (a crossing, a mouth, a market) x (1 - LAYER_CAP_K) + 0.1 for a character town. w = the town's site
--- weights with the survey's cues (before the tags' rarity).
function M.oldness(t, w, maxCap)
	local site = 0
	for _, p in ipairs(M.LAYER_SITE) do
		local v = math.min(1, tonumber((w or {})[p[1]]) or 0) * p[2]
		if v > site then site = v end
	end
	local size = math.min(1, (tonumber(t.cap) or 0) / math.max(1, tonumber(maxCap) or 1))
	return M.LAYER_CAP_K * size + (1 - M.LAYER_CAP_K) * site + (t.character and 0.1 or 0), site, size
end

--- The settlement layers of the map's towns (2026-10-14, NEXT_PHASE_BRIEF 53 Part B, review Q3: "Towns on the map at start:
--- layer by size and site. Crossings, mouths and market towns are oldest"): by oldness (M.oldness, ties by id) the first
--- LAYER_OLD share "old", the last LAYER_LATE share (LAYER_LATE_1900 from 1900) "late", the rest "mid". The rivers and
--- peaks keep the oldest names (the languages' river and peak lists are the oldest layer). list = the towns, ws = their
--- weights with cues (index-aligned), year = the game year or nil. Returns { [i] = "old" | "mid" | "late" }, counts.
function M.layers(list, ws, year)
	local N = #list
	local out, n = {}, { old = 0, mid = 0, late = 0 }
	if N == 0 then return out, n end
	local maxCap = 1
	for _, t in ipairs(list) do if (tonumber(t.cap) or 0) > maxCap then maxCap = tonumber(t.cap) end end
	local sc = {}
	for i, t in ipairs(list) do sc[i] = { i = i, v = M.oldness(t, ws[i], maxCap), id = tonumber(t.id) or 0 } end
	table.sort(sc, function(a, b)
		if a.v ~= b.v then return a.v > b.v end
		return a.id < b.id
	end)
	local late = (tonumber(year) and year >= 1900) and M.LAYER_LATE_1900 or M.LAYER_LATE
	local nOld = math.floor(N * M.LAYER_OLD + 0.5)
	local nLate = math.min(N - nOld, math.floor(N * late + 0.5))
	for k, e in ipairs(sc) do
		local lay = k <= nOld and "old" or (k > N - nLate and "late" or "mid")
		out[e.i] = lay
		n[lay] = n[lay] + 1
	end
	return out, n
end

--- The layer of a town created in game year `year` (a district, a Works): "late" from YEAR_LATE, else "mid"; nil without
--- a year.
function M.yearLayer(year)
	if not tonumber(year) then return nil end
	return year >= M.YEAR_LATE and "late" or "mid"
end

--- Does the town's reading hold an evocative name's gate (NEXT_PHASE_BRIEF 61)? a.gate = { { tag, tag ..., min } } (each
--- entry: one of its tags at least min, else EVOC_MIN; "lakes2": two lakes near, facts.lakes), wraw = the town's site
--- weights with the survey's cues before the tags' rarity, facts = { lakes = n } or nil. An evocative name (+g) without
--- a gate never fits.
function M.gateOk(a, wraw, facts)
	if type(a.gate) ~= "table" or #a.gate == 0 then return not a.flags.g end
	wraw = wraw or {}
	for _, g in ipairs(a.gate) do
		local ok = false
		for _, tag in ipairs(g) do
			if tag == "lakes2" then
				if (tonumber(facts and facts.lakes) or 0) >= 2 then ok = true end
			elseif (tonumber(wraw[tag]) or 0) >= (g.min or M.EVOC_MIN) then
				ok = true
			end
		end
		if not ok then return false end
	end
	return true
end

--- The gate's reading for the log: "confluence:1.00,oak:0.72" (each entry's best tag), "-" without a gate.
function M.gateText(a, wraw, facts)
	if type(a) ~= "table" or type(a.gate) ~= "table" then return "-" end
	local parts = {}
	for _, g in ipairs(a.gate) do
		local bt, bv = nil, -1
		for _, tag in ipairs(g) do
			local v = tag == "lakes2" and (tonumber(facts and facts.lakes) or 0) or (tonumber((wraw or {})[tag]) or 0)
			if v > bv then bt, bv = tag, v end
		end
		if bt then parts[#parts + 1] = string.format("%s:%.2f", bt, bv) end
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- The map's shapes (review Q1, Q4): per shape of the language (L.quota) a count of floor(towns x share + seeded u),
--- never above (share + SHAPE_SLACK) x towns; the scarce shapes go to the towns with the strongest claim (whole names,
--- qualifiers, frames, saints, civic names, articles, single elements, in that order), every other town is plain, and
--- the QUIET_SHARE with the weakest site claims among them quiet. Qualifiers: one Upper / Lower on a named river's stem
--- (RIVER_QUAL_MAX), then twins (two towns within TWIN_MAX_M: the smaller takes the other's base with Upper / Lower by
--- the river's course or height, Little by size, else the compass side it lies on), then site qualifiers ("Kings X",
--- "New X", joined "Oberdorf"). qs = the towns' naming inputs (index-aligned: river / lake / mount / bay granted,
--- specs, ldir), rsys = { [id] = river system }. Returns the plan { shape = { [i] = shape }, count, used, quiet = { [i] =
--- true }, qual = { [i] = { mode, kind } }, twinOf = { [i] = { anchor, kind } }, twins (list) }.
function M.planShapes(ctx, list, ws, qs, rsys)
	local L = ctx.L
	local N = #list
	local Q = ctx.quota or L.quota
	local P = { shape = {}, count = {}, used = {}, quiet = {}, qual = {}, twinOf = {}, twins = {}, anchor = {} }
	-- (a shape never outnumbers its forms: one saint name per saint for "%p", one name per article or single generic)
	local forms = { saint = 0, article = 0, single = 0 }
	local saints = (ctx.cl and ctx.cl.saints) or L.saints
	for _, a in ipairs(L.affixes) do
		if a.shape == "saint" and not a.flags.k then forms.saint = forms.saint + (a.hasS and N or #saints) end
	end
	for _, g in ipairs(L.gens) do
		if g.flags.o then forms.single = forms.single + 1 end
		if g.gender and type(L.articles) == "table" and L.articles[g.gender] and (g.form == "before" or g.form == "pre") then
			forms.article = forms.article + 1
		end
	end
	for _, sh in ipairs(M.SHAPES) do
		local share = Q[sh] or 0
		if share > 0 then
			local n = math.floor(N * share + draw(ctx.seed, 4, sh))
			n = math.max(0, math.min(n, math.floor(N * (share + M.SHAPE_SLACK))))
			if forms[sh] then n = math.min(n, forms[sh]) end
			P.count[sh] = n
		end
	end
	local taken = {}
	local function free(i) return not taken[i] and not list[i].keep end
	local xs = {}
	for i = 1, N do xs[i] = M.expandSite(ws[i]) end
	local function idOf(i) return tonumber(list[i].id) or 0 end
	local function byClaim(a, b)
		if a.c ~= b.c then return a.c > b.c end
		return idOf(a.i) < idOf(b.i)
	end
	-- the best claim of town i on affix shape sh (raw fit; filter(a) narrows the affixes)
	local function affixClaim(i, sh, filter)
		local q, best, bestA = qs[i], -math.huge, nil
		for ai, a in ipairs(L.affixes) do
			if a.shape == sh and not a.mapDir and not a.flags.k and not (a.flags.v and q.noCivic) and (filter == nil or filter(a))
				and not M.ruleOut(ctx, a)
				and M.fillable(L, a, q) and not vetoed(ctx, a) then
				local f = M.fit(a, xs[i])
				if a.rare then f = f + (list[i].character and M.RARE_ON or -M.RARE_OFF) end
				-- (the town's settlement layer: Market X and St X in the middle layer, New X and -on-Sea late)
				if q.layer then f = f + M.layerAdj(L, a, q.layer) end
				f = f + 0.05 * rng.unit(ctx.seed, "claim", idOf(i), ai)
				if f > best then best, bestA = f, a end
			end
		end
		return best, bestA
	end
	local function hand(sh, cands, cap, onTake)
		table.sort(cands, byClaim)
		local n = 0
		for _, e in ipairs(cands) do
			if n >= cap then break end
			if free(e.i) and (onTake == nil or onTake(e)) then
				taken[e.i], P.shape[e.i] = true, sh
				n = n + 1
			end
		end
		P.used[sh] = (P.used[sh] or 0) + n
		return n
	end
	local function minOf(i, sh)
		if list[i].character and (sh == "whole" or sh == "frame") then return M.CLAIM_MIN_CH end
		return M.CLAIM_MIN[sh] or 0
	end
	-- 0. character towns of a kind (the strong-characters hook, NEXT_PHASE_BRIEF 53 Part B): one of the kind's forms
	-- (NEXT_PHASE_BRIEF 61: the s61 kinds' forms, ctx.charForms)
	local CF = ctx.charForms or L.charForms
	for i = 1, N do
		local k = qs[i].charKind
		if free(i) and k and CF[k] then
			taken[i], P.shape[i] = true, "character"
			P.used.character = (P.used.character or 0) + 1
		end
	end
	if ctx.rules == "s61" then
		-- 0b. (NEXT_PHASE_BRIEF 61) the industry as a cue: towns with an industry of a cue family near (q.ind), the
		-- nearest and most telling first, one per family, about IND_SHARE of the towns (at most IND_PER16 per 16)
		local nI = math.floor(N * M.IND_SHARE + draw(ctx.seed, 12, "ind"))
		nI = math.max(N >= 6 and 1 or 0, math.min(nI, math.floor(N * M.IND_PER16 / 16 + 0.5)))
		local cands = {}
		for i = 1, N do
			local ind = qs[i].ind
			if free(i) and ind and M.IND_FAM_K[ind.fam] then
				local ok = false
				for _, a in ipairs(L.affixes) do
					if a.shape == "industry" and a.fam == ind.fam and M.fillable(L, a, qs[i]) and not vetoed(ctx, a) then ok = true break end
				end
				if ok then
					local c = M.IND_FAM_K[ind.fam] * (1 - math.min(1, (tonumber(ind.d) or 0) / M.IND_R)) + 0.05 * rng.unit(ctx.seed, "indclaim", idOf(i))
					cands[#cands + 1] = { i = i, c = c, fam = ind.fam }
				end
			end
		end
		local famUsed = {}
		hand("industry", cands, nI, function(e)
			if famUsed[e.fam] then return false end
			famUsed[e.fam] = true
			return true
		end)
	end
	-- 1. whole names (the big geography cues: Three Rivers, Middle Fork, Port X)
	if (P.count.whole or 0) > 0 then
		local cands = {}
		for i = 1, N do
			if free(i) then
				local c, a = affixClaim(i, "whole")
				-- (NEXT_PHASE_BRIEF 60: a town granted its river spends it, Arunford; a whole name that drops the river
				-- ranks lower there)
				if ctx.rules ~= "s53" and qs[i].river and a and not (a.needR or a.needT) then c = c - 0.5 end
				if c >= minOf(i, "whole") then cands[#cands + 1] = { i = i, c = c } end
			end
		end
		hand("whole", cands, P.count.whole)
	end
	-- 2. qualifiers
	local nq = P.count.qualifier or 0
	if nq > 0 then
		local has = {}
		for _, a in ipairs(L.affixes) do
			if a.shape == "qualifier" and not a.joined and not a.mapDir then has[a.qkind] = true end
		end
		-- a. Upper / Lower on the stem of the town's named river ("Lower Arunmouth" at the real mouth)
		local cands = {}
		for i = 1, N do
			if free(i) and qs[i].river and qs[i].specs then
				local w = ws[i]
				local k = (w.upper or 0) >= (w.lower or 0) and "upper" or "lower"
				local v = w[k] or 0
				if v >= M.RIVER_QUAL_CUE and has[k] then cands[#cands + 1] = { i = i, c = v, k = k } end
			end
		end
		local nr = hand("qualifier", cands, math.min(nq, M.RIVER_QUAL_MAX), function(e)
			P.qual[e.i] = { mode = "river", kind = e.k }
			return true
		end)
		-- b. twins: two close towns share a base, the smaller marked by Upper / Lower, Little or its compass side
		local left = nq - nr
		if left > 0 and ctx.twins ~= false then
			local F = twinForms(L)
			local pairsL = {}
			local M2 = math.min(N, M.TWIN_MAX_TOWNS)
			for i = 1, M2 do
				local ti = list[i]
				if free(i) and tonumber(ti.x) then
					for j = i + 1, M2 do
						local tj = list[j]
						if free(j) and tonumber(tj.x) then
							local d = math.sqrt((ti.x - tj.x) ^ 2 + (ti.y - tj.y) ^ 2)
							if d <= M.TWIN_MAX_M then
								local ci, cj = tonumber(ti.cap) or 0, tonumber(tj.cap) or 0
								-- (the smaller one is the twin; never a character town)
								local an, tw = i, j
								if cj > ci or (cj == ci and idOf(j) < idOf(i)) then an, tw = j, i end
								if list[tw].character then an, tw = tw, an end
								if not list[tw].character then
									local ta, tt = list[an], list[tw]
									local kind = nil
									local fa = type(ta.cue) == "table" and tonumber(ta.cue.flow) or nil
									local ft = type(tt.cue) == "table" and tonumber(tt.cue.flow) or nil
									local sameRiver = rsys[ta.id] ~= nil and rsys[ta.id] == rsys[tt.id]
									if sameRiver and fa and ft and math.abs(fa - ft) >= M.TWIN_FLOW then
										kind = ft > fa and "upper" or "lower"
									elseif tonumber(ta.alt) and tonumber(tt.alt) and math.abs(ta.alt - tt.alt) >= M.TWIN_DZ then
										kind = tt.alt > ta.alt and "upper" or "lower"
									end
									if kind and not F[kind] then kind = nil end
									local ca, ct = tonumber(ta.cap) or 0, tonumber(tt.cap) or 0
									if kind == nil and ct > 0 and ca >= M.TWIN_RATIO * ct and F.small then kind = "small" end
									local bonus = (kind == "upper" or kind == "lower") and 0.3 or (kind == "small" and 0.2 or 0)
									if kind == nil then
										local dr = dirFrom(tt.x - ta.x, tt.y - ta.y)
										if F[dr] then kind = dr end
									end
									if kind then
										pairsL[#pairsL + 1] = { an = an, tw = tw, kind = kind, c = 1 - d / M.TWIN_MAX_M + bonus }
									end
								end
							end
						end
					end
				end
			end
			table.sort(pairsL, function(a, b)
				if a.c ~= b.c then return a.c > b.c end
				if idOf(a.tw) ~= idOf(b.tw) then return idOf(a.tw) < idOf(b.tw) end
				return idOf(a.an) < idOf(b.an)
			end)
			local nt = 0
			for _, pr in ipairs(pairsL) do
				if nt >= left then break end
				if free(pr.an) and free(pr.tw) then
					taken[pr.an], taken[pr.tw] = true, true
					P.anchor[pr.an] = true
					P.shape[pr.tw] = "qualifier"
					P.twinOf[pr.tw] = { anchor = pr.an, kind = pr.kind }
					P.twins[#P.twins + 1] = pr.tw
					nt = nt + 1
				end
			end
			P.used.qualifier = (P.used.qualifier or 0) + nt
			left = left - nt
		end
		-- c. site qualifiers (Kings X, New X; joined Oberdorf / Unterdorf by the slope)
		if left > 0 then
			local sc = {}
			for i = 1, N do
				if free(i) then
					local c = affixClaim(i, "qualifier", function(a)
						return a.qkind == "age" or a.qkind == "other" or (a.joined and (a.qkind == "upper" or a.qkind == "lower"))
					end)
					if c >= minOf(i, "qualifier") then sc[#sc + 1] = { i = i, c = c } end
				end
			end
			hand("qualifier", sc, left, function(e) P.qual[e.i] = { mode = "site" } return true end)
		end
	end
	if ctx.rules == "s61" then
		-- 2b. (NEXT_PHASE_BRIEF 61) evocative names, after the whole names and the twins: the towns whose reading holds
		-- an evocative name's gate, the best fit first, each name once in the plan; they take multi-word names off the
		-- separate count
		local nE = math.floor(N * M.EVOC_SHARE + draw(ctx.seed, 11, "evoc"))
		nE = math.max(0, math.min(nE, math.floor(N * M.EVOC_MAX)))
		local ec = {}
		for i = 1, N do
			if free(i) then
				local opts = {}
				-- (a town granted its river first spends it: Arunford, Lower Arunmouth; never an evocative name there)
				for ai, a in ipairs(qs[i].riverGrant == "first" and {} or L.affixes) do
					if a.shape == "evoc" and not M.ruleOut(ctx, a) and M.gateOk(a, qs[i].wraw, qs[i].facts) and M.fillable(L, a, qs[i])
						and not vetoed(ctx, a) then
						local f = M.fit(a, xs[i])
						if a.rare then f = f + (list[i].character and M.RARE_ON or -M.RARE_OFF) end
						if qs[i].river then f = f - M.EVOC_RIVER end
						f = f + 0.2 * rng.unit(ctx.seed, "evclaim", idOf(i), ai)
						if f >= M.EVOC_CLAIM then opts[#opts + 1] = { a = a, f = f } end
					end
				end
				if #opts > 0 then
					table.sort(opts, function(a, b) if a.f ~= b.f then return a.f > b.f end return (a.a.k or a.a.text) < (b.a.k or b.a.text) end)
					ec[#ec + 1] = { i = i, c = opts[1].f, opts = opts }
				end
			end
		end
		local planned, multi = {}, 0
		hand("evoc", ec, nE, function(e)
			for _, o in ipairs(e.opts) do
				local k = o.a.k or o.a.text
				if not planned[k] then
					planned[k] = true
					if M.tokens(o.a.r or o.a.text) >= 2 then multi = multi + 1 end
					return true
				end
			end
			return false
		end)
		if multi > 0 and P.count.separate then
			P.count.separate = math.max(0, P.count.separate - math.floor(multi * M.EVOC_SEP + 0.5))
		end
	end
	-- 3. frames (at most one per river), saints, civic names
	if (P.count.frame or 0) > 0 then
		local cands = {}
		for i = 1, N do
			if free(i) then
				local c, a = affixClaim(i, "frame")
				if c >= minOf(i, "frame") then
					cands[#cands + 1] = { i = i, c = c, a = a, rv = a and (a.needR or a.needT) and qs[i].river and (qs[i].river.s or qs[i].river.n) or nil }
				end
			end
		end
		local framed, tpl = {}, {}
		local cap = math.max(1, math.floor(N / M.FRAME_PER))
		hand("frame", cands, P.count.frame, function(e)
			if e.rv and framed[e.rv] then return false end
			local k = e.a and (e.a.k or e.a.text) or "-"
			if (tpl[k] or 0) >= cap then return false end
			if e.rv then framed[e.rv] = true end
			tpl[k] = (tpl[k] or 0) + 1
			return true
		end)
	end
	if (P.count.saint or 0) > 0 then
		local cands = {}
		local any = (Q.saint or 0) >= M.SAINT_ANY
		for i = 1, N do
			if free(i) then
				local c = affixClaim(i, "saint")
				if c > -math.huge and (any or c >= minOf(i, "saint")) then cands[#cands + 1] = { i = i, c = c } end
			end
		end
		hand("saint", cands, P.count.saint)
	end
	if (P.count.civic or 0) > 0 then
		local cands = {}
		for i = 1, N do
			if free(i) and not qs[i].noCivic then
				local c = affixClaim(i, "civic")
				if c >= minOf(i, "civic") then cands[#cands + 1] = { i = i, c = c } end
			end
		end
		hand("civic", cands, P.count.civic)
	end
	-- 4. articles and single elements (their generics' fit)
	local function genClaim(i, f)
		local best = -math.huge
		for gi, g in ipairs(L.gens) do
			if f(g) and not vetoed(ctx, g) then
				local v = M.fit(g, xs[i]) + 0.05 * rng.unit(ctx.seed, "gclaim", idOf(i), gi)
				if v > best then best = v end
			end
		end
		return best
	end
	if (P.count.article or 0) > 0 and type(L.articles) == "table" and not L.script then
		local cands = {}
		for i = 1, N do
			if free(i) then
				local c = genClaim(i, function(g) return g.gender ~= nil and L.articles[g.gender] ~= nil and (g.form == "before" or g.form == "pre") end)
				if c >= minOf(i, "article") then cands[#cands + 1] = { i = i, c = c } end
			end
		end
		hand("article", cands, P.count.article)
	end
	if (P.count.single or 0) > 0 and not L.script then
		local cands = {}
		for i = 1, N do
			if free(i) then
				local c = genClaim(i, function(g) return g.flags.o == true end)
				if c >= minOf(i, "single") then cands[#cands + 1] = { i = i, c = c } end
			end
		end
		hand("single", cands, P.count.single)
	end
	-- 5. quiet names: the plain towns with the weakest site claims (review Q7: at least 35 % with no terrain word)
	local plain = {}
	for i = 1, N do
		if (P.shape[i] == nil or P.shape[i] == "plain") and not list[i].keep and not list[i].character then
			local rk = M.rankOf(ws[i])
			local top = 0
			for _, r in ipairs(rk) do
				if M.ideaOf(r[1]) then top = r[2] break end
			end
			plain[#plain + 1] = { i = i, c = top }
		end
	end
	table.sort(plain, function(a, b)
		if a.c ~= b.c then return a.c < b.c end
		return idOf(a.i) < idOf(b.i)
	end)
	-- (NEXT_PHASE_BRIEF 61: the share of the towns left plain; the evocative, industry and character towns name a cue)
	local nPlainish = N
	if ctx.rules == "s61" then
		for i = 1, N do
			local sh = P.shape[i]
			if sh == "evoc" or sh == "industry" or sh == "character" then nPlainish = nPlainish - 1 end
		end
	end
	local nQuiet = math.floor((ctx.rules == "s53" and M.QUIET_SHARE_53 or M.QUIET_SHARE) * nPlainish + 0.5)
	for k = 1, math.min(nQuiet, #plain) do P.quiet[plain[k].i] = true end
	-- 6. flavor towns (NEXT_PHASE_BRIEF 60: "a little nationality mixed in", about 2 per 16 towns, at most FLAVOR_MAX per
	-- 16): the plain, non-quiet towns with the best claim on a +n part (Aber- at a mouth with its river, Kirk- at a
	-- church, -thwaite in a clearing), towns of the coast and edge dialect areas first
	P.flavor = {}
	if ctx.rules ~= "s53" and L.hasFlavor and N > 0 then
		local nF = math.floor(N * M.FLAVOR_SHARE + draw(ctx.seed, 9, "flavor"))
		nF = math.max(N >= 6 and 1 or 0, math.min(nF, math.floor(N * M.FLAVOR_MAX / 16 + 0.5)))
		local cands = {}
		for i = 1, N do
			if (P.shape[i] == nil or P.shape[i] == "plain") and not P.quiet[i] and not P.anchor[i] and not list[i].keep and not list[i].character then
				local best = -math.huge
				for _, lst in ipairs({ L.gens, L.specs }) do
					for _, e in ipairs(lst) do
						if e.flags.n and not M.opaque(e) and not vetoed(ctx, e) then
							local v = M.fit(e, xs[i])
							if v > best then best = v end
						end
					end
				end
				local q = qs[i]
				if q.river then best = best + 0.3 end
				if q.dialect and q.dialect.role ~= "core" then best = best + 0.3 end
				best = best + 0.1 * draw(ctx.seed, idOf(i), "flavorpick")
				if best >= M.FLAVOR_MIN then cands[#cands + 1] = { i = i, c = best } end
			end
		end
		table.sort(cands, byClaim)
		for k = 1, math.min(nF, #cands) do P.flavor[cands[k].i] = true end
	end
	return P
end

--- The NAMES shapes line's fields: quota (the plan's counts), used (shapes of the names given), frames, whole,
--- twins, quiet (names with no terrain word), miss (shapes that fell back to plain), left (feature claims without
--- a grant).
function M.shapeFields(st)
	local sh = st and st.shapes
	if sh == nil then return { { "quota", "-" } } end
	local function text(t)
		local parts = {}
		for _, k in ipairs(M.SHAPES) do if (t[k] or 0) > 0 then parts[#parts + 1] = k .. ":" .. t[k] end end
		return #parts > 0 and table.concat(parts, ",") or "-"
	end
	local ly = sh.layers or {}
	return { { "quota", text(sh.quota) }, { "used", text(sh.used) }, { "frames", sh.used.frame or 0 },
		{ "whole", sh.used.whole or 0 }, { "twins", sh.twins }, { "quiet", sh.quiet }, { "towns", sh.towns },
		{ "miss", sh.miss }, { "left", sh.left },
		{ "layers", string.format("old:%d,mid:%d,late:%d", ly.old or 0, ly.mid or 0, ly.late or 0) },
		{ "desc", sh.desc or 0 }, { "opaque", sh.opaque or 0 }, { "flavor", sh.flavor or 0 }, { "multi", sh.multi or 0 },
		{ "rules", sh.rules or M.RULES }, { "evoc", sh.evoc or 0 },
		{ "charCue", string.format("%d/%d", sh.charCue or 0, sh.charN or 0) }, { "indCue", sh.indCue or 0 } }
end

--- Names every town of a new map. towns = { { id, name, x, y, w (M.siteTags weights), ranked, character, cap, river =
--- bool, axis, lake = bool, alt (m above the water level, or nil), cue = ot_mapshape.townCues (or nil), keep = true
--- (not renamed: its name stays and counts for the word budget) } } (at most MAX_TOWNS); o = { lang, seed, real = {
--- [lower] = true }, used = { [name] = true } (names to keep free of), budget = false (no word budget), rarity = false,
--- sat = false (no twins), shapes = false (no shape plan: every town scores stem, generic and affix together, as before
--- NEXT_PHASE_BRIEF 53; the morpheme tests and the lab's comparison) }. Returns results (input order: { id, old, new, info, river, lake }) and stats { named, none,
--- rivers, lakes, waters = { { n, x, y, k = "r" | "l" } } (for the save, at most WATER_CAP), budget (ot_namewords),
--- rarity (factors), mount, bay (the named features), shapes (the plan's counts and what was used; M.shapeFields) }, or
--- nil, why.
function M.assign(towns, o)
	o = o or {}
	local ctx = M.newCtx(o.lang, o.seed, o.real, o.used)
	if ctx == nil then return nil, "noGenerator" end
	ctx.climate = o.climate
	-- (NEXT_PHASE_BRIEF 53 Part B: the climate's shape table)
	ctx.cl = M.climateOf(ctx.L, o.climate)
	ctx.quota = ctx.cl.quota
	ctx.twins = o.sat ~= false
	-- (NEXT_PHASE_BRIEF 60: the descriptive rules, unless o.rules = "s53"; the opaque and flavor caps per map)
	ctx.rules = o.rules or M.RULES
	local words = tonumber(ctx.cl.words)
	if ctx.rules ~= "s53" then
		ctx.quota = M.quota60(ctx.quota, o.lang)
		if M.WORDS60[o.lang or ""] then words = math.max(words or 0, M.WORDS60[o.lang]) end
		if ctx.rules == "s61" and M.WORDS61[o.lang or ""] then words = math.max(words or 0, M.WORDS61[o.lang]) end
		local n0 = math.min(#towns, M.MAX_TOWNS)
		ctx.opaqueCap = math.max(1, math.floor(n0 / M.OPAQUE_PER))
		ctx.flavorCap = math.max(1, math.floor(n0 * M.FLAVOR_MAX / 16 + 0.5))
	end
	-- (NEXT_PHASE_BRIEF 61: the s61 character kinds' forms; under the older rules a secluded town is an ordinary character
	-- town and deep forest / coastal towns none, as before)
	ctx.charForms = ctx.rules == "s61" and ctx.L.charForms61 or ctx.L.charForms
	local list = {}
	for i = 1, math.min(#towns, M.MAX_TOWNS) do
		local t = towns[i]
		local k = t.character
		if type(k) == "string" and M.KINDS61[k] and ctx.rules ~= "s61" then
			local c = {}
			for kk, v in pairs(t) do c[kk] = v end
			c.character = k == "secluded"
			t = c
		end
		list[i] = t
	end
	if o.budget ~= false then ctx.budget = NW.newBudget(M.CLS_OF_GEN[o.lang] or o.lang, #list) end
	-- (2026-10-14: the map survey's cues join the site weights; then every tag is weighed by its rarity on the map: a
	-- feature most towns share is no cue)
	local ws = {}
	for i, t in ipairs(list) do ws[i] = M.withCues(t.w, t.cue) end
	-- (NEXT_PHASE_BRIEF 53 Part B: the settlement layers by size and site, before the tags' rarity; the natural
	-- confluences, never a civic name)
	local layers, layerN = M.layers(list, ws, o.year)
	local wcue = {}
	for i = 1, #list do wcue[i] = ws[i] end
	ctx.layers = layers
	local rar = (o.rarity ~= false) and NW.rarity(ws) or {}
	for i = 1, #list do ws[i] = NW.applyRarity(ws[i], rar) end
	M.regions(ctx, list, ws)
	-- rivers and lakes first: their names are parts of the town names. Towns on one river of the survey share it (its
	-- component); the others link by their river axes
	local riv = {}
	local byComp, compSys = {}, {}
	for _, t in ipairs(list) do
		local comp = type(t.cue) == "table" and t.cue.river or nil
		if comp then byComp[comp] = true
		elseif t.river then riv[#riv + 1] = t end
	end
	local rsys, rsystems = M.riverSystems(riv)
	local comps = {}
	for comp in pairs(byComp) do comps[#comps + 1] = comp end
	table.sort(comps)
	for _, comp in ipairs(comps) do
		rsystems[#rsystems + 1] = { ids = {}, x = 0, y = 0, comp = comp }
		compSys[comp] = #rsystems
	end
	for _, t in ipairs(list) do
		local comp = type(t.cue) == "table" and t.cue.river or nil
		if comp then
			rsys[t.id] = compSys[comp]
			local sy = rsystems[compSys[comp]]
			sy.ids[#sy.ids + 1] = t.id
		end
	end
	-- lakes: the big lake's towns are one system (the survey), the rest cluster by distance
	local lakeList, bigIds = {}, {}
	for _, t in ipairs(list) do
		if type(t.cue) == "table" and t.cue.lake then bigIds[#bigIds + 1] = t.id
		elseif t.lake then lakeList[#lakeList + 1] = t end
	end
	local lsys, lsystems = M.lakeSystems(lakeList)
	if #bigIds > 0 then
		lsystems[#lsystems + 1] = { ids = bigIds, x = 0, y = 0, big = true }
		for _, id in ipairs(bigIds) do lsys[id] = #lsystems end
	end
	-- (the dialect area of a set of towns: at their centre)
	local idx = {}
	for i, t in ipairs(list) do idx[t.id] = i end
	local function areaOf(ids)
		local n, cx, cy = 0, 0, 0
		for _, id in ipairs(ids) do
			local t = list[idx[id] or 0]
			if t and tonumber(t.x) then n, cx, cy = n + 1, cx + t.x, cy + t.y end
		end
		if n == 0 then return nil end
		local d = M.dialectAt(ctx, cx / n, cy / n)
		return d and d.name or nil
	end
	local rnames, lnames = {}, {}
	for k = 1, #rsystems do rnames[k] = M.riverName(ctx, k) end
	local lhigh = {}
	for _, t in ipairs(list) do
		local k = lsys[t.id]
		if k and type(t.w) == "table" and t.w.tarn then lhigh[k] = true end
	end
	for k = 1, #lsystems do lnames[k] = M.lakeName(ctx, k, lhigh[k] == true, areaOf(lsystems[k].ids)) end
	-- the big named features (once per map, reused as qualifiers: "Mount Eagle", "Eagle Gap", "Heron Bay")
	local mountIds, bayIds = {}, {}
	for i = 1, #list do
		local w = ws[i]
		if (w.peak or 0) > 0 or (w.summit or 0) > 0 or (w.range or 0) > 0 or (w.divide or 0) > 0 then mountIds[#mountIds + 1] = list[i].id end
		if (w.bigbay or 0) > 0 then bayIds[#bayIds + 1] = list[i].id end
	end
	local mount = #mountIds > 0 and M.featName(ctx, "mount", areaOf(mountIds)) or nil
	local bay = #bayIds > 0 and M.featName(ctx, "bay") or nil
	-- (2026-10-14, NEXT_PHASE_BRIEF 50: the feature stems are qualifiers, counted by featureOk; every other word's root
	-- and the affix patterns join the word budget, and the budget knows the towns' positions for its neighbourhood rule)
	local function featWord(x) if x and type(x.s) == "string" then ctx.featWords[lowerAll(x.s)] = true end end
	for k = 1, #rsystems do featWord(rnames[k]) end
	for k = 1, #lsystems do featWord(lnames[k]) end
	featWord(mount)
	featWord(bay)
	if ctx.budget then
		M.attachExtra(ctx.budget, o.lang, ctx.featWords, ctx.rules == "s61")
		local pos = {}
		for _, t in ipairs(list) do pos[#pos + 1] = { t.x, t.y } end
		NW.setTowns(ctx.budget, pos)
	end
	local waters = {}
	local function addWater(n, x, y, kind)
		if #waters < M.WATER_CAP and n and tonumber(x) then waters[#waters + 1] = { n = n, x = math.floor(x + 0.5), y = math.floor(y + 0.5), k = kind } end
	end
	-- the names that stay (player-renamed towns): their words count first
	for _, t in ipairs(list) do
		if t.keep and type(t.name) == "string" then
			M.take(ctx, t.name)
			NW.add(ctx.budget, t.name, t.x, t.y)
		end
	end
	-- the named-feature budget (2026-10-14, NEXT_PHASE_BRIEF 53 item 2): which towns may name each river, lake, peak, bay
	local feats = {}
	for k = 1, #rsystems do
		if rnames[k] then
			local mem = {}
			for _, id in ipairs(rsystems[k].ids) do if idx[id] and not list[idx[id]].keep then mem[#mem + 1] = idx[id] end end
			feats[#feats + 1] = { kind = "river", members = mem }
		end
	end
	for k = 1, #lsystems do
		if lnames[k] then
			local mem = {}
			for _, id in ipairs(lsystems[k].ids) do if idx[id] and not list[idx[id]].keep then mem[#mem + 1] = idx[id] end end
			feats[#feats + 1] = { kind = "lake", members = mem }
		end
	end
	local function memOf(ids)
		local mem = {}
		for _, id in ipairs(ids) do if idx[id] and not list[idx[id]].keep then mem[#mem + 1] = idx[id] end end
		return mem
	end
	if mount then feats[#feats + 1] = { kind = "mount", members = memOf(mountIds) } end
	local bayCue = {}
	for i, t in ipairs(list) do if type(t.cue) == "table" and t.cue.bigbay then bayCue[#bayCue + 1] = t.id end end
	if bay then feats[#feats + 1] = { kind = "bay", members = memOf(bayCue) } end
	local grants, leftClaims, leftList = M.featureGrants(ctx, list, ws, feats)
	-- (NEXT_PHASE_BRIEF 53 Part B: a climate's settler group, the Spanish of a dry US map, on one side of the map: the
	-- share of the towns farthest along a seeded direction)
	local glayer = {}
	local G0 = ctx.cl.group
	if G0 and #list > 0 then
		local ang = draw(ctx.seed, 7, "glayer") * 2 * math.pi
		local ca, sa = math.cos(ang), math.sin(ang)
		local pr = {}
		for i, t in ipairs(list) do
			if tonumber(t.x) and tonumber(t.y) then pr[#pr + 1] = { i = i, v = t.x * ca + t.y * sa, id = tonumber(t.id) or 0 } end
		end
		table.sort(pr, function(a, b) if a.v ~= b.v then return a.v > b.v end return a.id < b.id end)
		-- (NEXT_PHASE_BRIEF 60: the settler group is the map's national flavor, a few towns: about FLAVOR_SHARE)
		local share = ctx.rules ~= "s53" and math.min(G0.share, M.FLAVOR_SHARE + 0.03) or G0.share
		for k = 1, math.min(#pr, math.floor(#list * share + 0.5)) do glayer[pr[k].i] = G0.grp end
	end
	-- each town's naming input
	local qs = {}
	for i, t in ipairs(list) do
		local cue = type(t.cue) == "table" and t.cue or {}
		local g = grants[i] or {}
		local rv = rsys[t.id] and rnames[rsys[t.id]] or nil
		local lk = lsys[t.id] and lnames[lsys[t.id]] or nil
		local q = { id = t.id, x = t.x, y = t.y, w = ws[i], character = t.character, river = g.river and rv or nil,
			riverGrant = g.river and rv and g.river or nil,
			lake = g.lake and lk or nil, mount = g.mount and mount or nil, bay = (g.bay and cue.bigbay and bay) or nil,
			dir = cue.dir, ldir = cue.ldir, layer = layers[i], saints = ctx.cl.saints, glayer = glayer[i] }
		-- (NEXT_PHASE_BRIEF 61: the reading the evocative names' gates read, the survey's facts, the industry near)
		if ctx.rules == "s61" then
			q.wraw, q.facts = wcue[i], type(t.facts) == "table" and t.facts or nil
			if type(t.ind) == "table" and type(t.ind.fam) == "string" and tonumber(t.ind.d) and t.ind.d <= M.IND_R then
				q.ind = { fam = t.ind.fam, d = tonumber(t.ind.d) }
			end
		end
		-- (civic names, Junction / Station / Center: a late town that is no natural confluence; the character kind)
		q.noCivic = layers[i] ~= "late" or (wcue[i].confluence or 0) >= M.CIVIC_CONFLUENCE or (wcue[i].twin or 0) >= M.CIVIC_CONFLUENCE
		if type(t.character) == "string" and t.character ~= "" then q.charKind = t.character end
		if q.river then
			local e
			if ctx.L.script then e = rv.e
			else
				e = newEntry(rv.s)
				e.kind = "stem"
				parseTags({ rv.s, "river", "mouth:.8", "ford:.8", "bridge:.8", "confluence:.6", "bend:.6", "brook:.5" }, 2, e)
				e.river = true
				e.boost = g.river == "first" and M.FEAT_FIRST or M.FEAT_BONUS
			end
			if e then q.specs = { e } end
		end
		-- (the dialect: the area's, or the neighbouring area's for BORROW_P of the towns)
		local d = M.dialectAt(ctx, t.x, t.y)
		if d and d.other and draw(ctx.seed, tonumber(t.id) or 0, "borrow") < M.BORROW_P then
			d = { name = d.other.name, role = d.other.role, w = d.other.w, hybrid = false, borrowed = true }
		end
		q.dialect = d
		qs[i] = q
	end
	ctx.frameCap = math.max(1, math.floor(#list / M.FRAME_PER))
	local plan = o.shapes == false and { shape = {}, count = {}, used = {}, quiet = {}, qual = {}, twinOf = {}, twins = {}, anchor = {} }
		or M.planShapes(ctx, list, ws, qs, rsys)
	ctx.plan = plan
	-- (review Q7: en at most 1.4 words per name on average, usa 1.8; the planned affix shapes reserve one extra word each)
	local target = words
	if target then
		local reserved = 0
		for i = 1, #list do if plan.shape[i] and M.AFFIX_SHAPES[plan.shape[i]] then reserved = reserved + 1 end end
		ctx.wordAllow, ctx.wordExtra, ctx.wordN, ctx.wordTowns = math.floor(#list * (target - 1)) - reserved, 0, 0, #list
	end
	-- order: character towns, then the most distinctive sites (after rarity), then id
	local order = {}
	for i, t in ipairs(list) do
		local rk = M.rankOf(ws[i])
		local top = (rk[1] and rk[1][2]) or 0
		-- (NEXT_PHASE_BRIEF 61: the evocative towns right after the character towns: their words first)
		local ch = t.character and 0 or ((plan.shape[i] == "evoc" or plan.shape[i] == "industry") and 1 or 2)
		order[#order + 1] = { i = i, ch = ch, top = top, id = tonumber(t.id) or 0 }
	end
	table.sort(order, function(a, b)
		if a.ch ~= b.ch then return a.ch < b.ch end
		if a.top ~= b.top then return a.top > b.top end
		return a.id < b.id
	end)
	local res = {}
	local st = { named = 0, none = 0, rivers = 0, lakes = 0, kept = 0 }
	for k = 1, #rsystems do if rnames[k] then st.rivers = st.rivers + 1 end end
	for k = 1, #lsystems do if lnames[k] then st.lakes = st.lakes + 1 end end
	local function nameOne(i, shape)
		local t, q = list[i], qs[i]
		q.shape = o.shapes ~= false and (shape or plan.shape[i] or "plain") or nil
		q.quiet = plan.quiet[i] == true
		q.flavor = plan.flavor ~= nil and plan.flavor[i] == true
		local ql = plan.qual[i]
		q.qualMode, q.qualKind = ql and ql.mode or nil, ql and ql.kind or nil
		local nm, info = M.nameTown(ctx, q)
		local rv = rsys[t.id] and rnames[rsys[t.id]] or nil
		local lk = lsys[t.id] and lnames[lsys[t.id]] or nil
		res[i] = { id = t.id, old = t.name, new = nm or t.name, info = info, river = rv and rv.n or nil, lake = lk and lk.n or nil,
			why = nm == nil and info or nil }
		if nm then st.named = st.named + 1 else st.none = st.none + 1 end
	end
	for _, od in ipairs(order) do
		local t = list[od.i]
		if t.keep then
			local rv = rsys[t.id] and rnames[rsys[t.id]] or nil
			local lk = lsys[t.id] and lnames[lsys[t.id]] or nil
			res[od.i] = { id = t.id, old = t.name, new = t.name, info = nil, river = rv and rv.n or nil, lake = lk and lk.n or nil,
				why = "keep" }
			st.kept = st.kept + 1
		elseif plan.twinOf[od.i] == nil then
			nameOne(od.i)
		end
	end
	-- twins: the anchor's base with the twin's qualifier ("Little Ashford", "Lower Ashford", "North Ashford"); the twin
	-- pays only for the words its anchor lacks. A twin that can't take one is named on its own.
	local nTwins = 0
	for _, i in ipairs(plan.twins) do
		local tw = plan.twinOf[i]
		local r = res[tw.anchor]
		local done = false
		local inf = r and r.info
		if inf and inf.affix == nil and inf.base and (inf.shape == "plain" or inf.shape == "separate" or inf.shape == "personal")
			and not (ctx.opaqueCap and (inf.opaque or inf.flavor)) then
			local q = qs[i]
			local forms = twinForms(ctx.L)[tw.kind] or {}
			local ranked = {}
			for k, a in ipairs(forms) do
				-- (the language's first form of the kind leads: Upper before High, Little before Parva; the twin relation, not
				-- the site, picks it)
				local f = -(k - 1) + 1.6 * draw(ctx.seed, (tonumber(list[i].id) or 0) * 7 + k, "twin")
				if a.rare then f = f - M.RARE_OFF end
				ranked[#ranked + 1] = { a = a, f = f, k = k }
			end
			table.sort(ranked, function(a, b) if a.f ~= b.f then return a.f > b.f end return a.k < b.k end)
			local skip = ctx.budget and NW.budgetKeys(ctx.budget, r.new) or nil
			local uses = featureUses(ctx, q, { s = { e = inf.sE } }, nil)
			for _, e in ipairs(ranked) do
				local full = fillAffix(ctx.L, e.a, inf.base, q)
				if full then
					local nm = (ctx.L.script == "kanji") and (full .. "市") or full
					local over = M.tokens(nm) > 2 and M.wordsOver(ctx, M.tokens(nm) - 2)
					if not over and M.chars(full) <= M.MAX_FULL and M.free(ctx, nm) and M.tokens(nm) <= M.MAX_TOKENS and featureOk(ctx, uses)
						and not M.climateWord(ctx, nm) and NW.allow(ctx.budget, nm, list[i].x, list[i].y, skip) then
						M.take(ctx, nm)
						featureTake(ctx, uses)
						NW.add(ctx.budget, nm, list[i].x, list[i].y, skip)
						ctx.shapeUse.qualifier = (ctx.shapeUse.qualifier or 0) + 1
						M.countWords(ctx, nm, true)
						ctx.affUse[e.a.k or e.a.text] = (ctx.affUse[e.a.k or e.a.text] or 0) + 1
						local rv = rsys[list[i].id] and rnames[rsys[list[i].id]] or nil
						local lk = lsys[list[i].id] and lnames[lsys[list[i].id]] or nil
						res[i] = { id = list[i].id, old = list[i].name, new = nm, river = rv and rv.n or nil, lake = lk and lk.n or nil,
							info = { spec = inf.spec, gen = inf.gen, affix = e.a.k or e.a.text, whole = false, feature = "twin",
								specTag = inf.specTag, genTag = inf.genTag, score = 0, dialect = inf.dialect, base = inf.base,
								sE = inf.sE, gE = inf.gE, aE = e.a, shape = "qualifier", quiet = false, twin = list[tw.anchor].id,
								twinKind = tw.kind, hybrid = inf.hybrid, layer = q.layer } }
						st.named = st.named + 1
						nTwins = nTwins + 1
						done = true
						break
					end
				end
			end
		end
		if not done then nameOne(i, "plain") end
	end
	for i, t in ipairs(list) do
		local r = res[i]
		if r and r.river then addWater(r.river, t.x, t.y, "r") end
		if r and r.lake then addWater(r.lake, t.x, t.y, "l") end
	end
	-- the shapes the map got; (NEXT_PHASE_BRIEF 60) its names with a readable site word, opaque, flavor and multi-word names
	local used, quiet = {}, 0
	local nDesc, nOpq, nFlv, nMulti, nNamed = 0, 0, 0, 0, 0
	-- (NEXT_PHASE_BRIEF 61: evocative names, character towns of a kind that carry it, industry cue names)
	local nEvoc, nChar, nCharCue, nInd = 0, 0, 0, 0
	for i, r in ipairs(res) do
		if qs[i] and qs[i].charKind and (ctx.charForms or {})[qs[i].charKind] then
			nChar = nChar + 1
			if r.info and r.info.shape == "character" then nCharCue = nCharCue + 1 end
		end
		if r.info and r.info.shape == "evoc" then nEvoc = nEvoc + 1 end
		if r.info and r.info.shape == "industry" then nInd = nInd + 1 end
	end
	for i, r in ipairs(res) do
		if r.info and r.info.shape then
			used[r.info.shape] = (used[r.info.shape] or 0) + 1
			if r.info.quiet then quiet = quiet + 1 end
		end
		if r.info then
			r.info.site = M.siteWord(r.info, wcue[i])
			nNamed = nNamed + 1
			if r.info.site then nDesc = nDesc + 1 end
			if r.info.opaque then nOpq = nOpq + 1 end
			if r.info.flavor then nFlv = nFlv + 1 end
			if M.tokens(r.new) >= 2 then nMulti = nMulti + 1 end
		end
	end
	st.shapes = { quota = plan.count, used = used, twins = nTwins, quiet = quiet, towns = #list, miss = ctx.shapeMiss or 0,
		left = leftClaims, layers = layerN, desc = nDesc, opaque = nOpq, flavor = nFlv, multi = nMulti, named = nNamed,
		rules = ctx.rules, evoc = nEvoc, charN = nChar, charCue = nCharCue, indCue = nInd }
	st.layers = layers
	st.leftList = leftList
	st.plan = plan
	st.satellite = 0
	st.waters = waters
	st.ctx = ctx
	st.budget = ctx.budget
	st.misfit, st.climate = ctx.misfit, ctx.climate
	st.rarity = rar
	st.mount, st.bay = mount, bay
	st.weights = ws
	return res, st
end

---------------------------------------------------------------------------
-- districts and Works (2026-10-14: related to the parent town)

-- ot_district site kinds -> site weights
M.DISTRICT_SITE = { upper = { hilltop = 0.9, slope = 0.8, hill = 0.8 }, shore = { coast = 1, sandy = 0.6, bay = 0.5 },
	shoreLake = { lake = 1, mere = 0.6 }, shoreRock = { coast = 1, rocky = 0.8, cliff = 0.6, headland = 0.5 }, across = { bridge = 1, ford = 0.8, river = 0.8 },
	lead = { field = 0.8, plain = 0.6, edge = 0.4 }, valley = { valley = 1, vale = 0.7, combe = 0.6 },
	clearing = { clearing = 1, edge = 0.8, forest = 0.7 } }
-- ot_works site kinds
M.WORKS_SITE = { harbour = { coast = 1, bay = 0.8 }, rail = { plain = 0.8, field = 0.5 }, across = { river = 0.9, bridge = 0.8 },
	plain = { plain = 0.8, field = 0.6 }, hill = { slope = 0.8, rock = 0.6, hill = 0.7 } }

--- The parent name's stem in language L (the longest stem of the inventory that starts it, leaving 2+ characters), or
--- nil (romance names start with their generic: no stem).
function M.stemOf(L, name)
	if type(name) ~= "string" then return nil end
	for _, e in ipairs(L.byLen) do
		local s = e.k or e.text
		if #name >= #s + 2 and name:sub(1, #s) == s then return e end
	end
	return nil
end

--- A district's generated name: the parent's stem with a generic that fits the site kind ("Ashford" upper ->
--- "Ashdown"). lang = generator language, used = { [name] = true } (the map's names), o = { seed, lake, budget (the
--- map's ot_namewords budget), x, y (the district's site) }. Returns name, info or nil.
function M.related(lang, parent, kind, used, o)
	o = o or {}
	local L = M.lang(lang)
	if L == nil then return nil end
	local stem = M.stemOf(L, parent)
	if stem == nil then return nil end
	-- (NEXT_PHASE_BRIEF 60: a district named from the parent reads naturally: never from an opaque stem, "Mytbridge"; the
	-- composed forms with the parent's whole name take it)
	-- (nor from the first word of a multi-word parent: "Middle Fork" -> "Middle Heights")
	if (o.rules or M.RULES) ~= "s53" and (M.opaque(stem) or parent:find("[ %-]")) then return nil end
	local ctx = M.newCtx(lang, o.seed, o.real, used)
	if ctx then ctx.climate, ctx.cl = o.climate, M.climateOf(L, o.climate) end
	ctx.used[parent] = true
	local w = {}
	-- (2026-10-14, NEXT_PHASE_BRIEF 50 item 1: a shore is a sandy sea beach only when the site read says so; a lake shore
	-- takes lake words, any other shore rocky ones)
	local sk = kind
	if kind == "shore" then sk = o.lake and "shoreLake" or (o.sandy and "shore" or "shoreRock") end
	for k, v in pairs(M.DISTRICT_SITE[sk] or {}) do w[k] = v end
	w.district = 1
	ctx.budget = o.budget
	local nm, info = M.nameTown(ctx, { id = rng.hash(parent, kind), w = w, fixedSpec = stem, noAffix = true, noSuffix = true,
		strictBudget = true, x = o.x, y = o.y, skipWords = NW.keys(parent, o.budget and o.budget.cls), layer = M.yearLayer(o.year) })
	if nm == nil or nm == parent then return nil end
	return nm, info
end

--- A Works town's generated name: an industrial stem of the industry kind (ot_stopname.indKind: works / quarry / mine /
--- mill / farm / brewery / timber; others: works) with a generic that fits the site kind ("Coalbrookdale"-style), or
--- (romance languages) the language's works form with the parent's name. Returns name, info or nil.
function M.works(lang, parent, indKind, siteKind, used, o)
	o = o or {}
	local L = M.lang(lang)
	if L == nil then return nil end
	local stems = L.works[indKind or ""] or L.works.works
	if stems == nil or #stems == 0 then return nil end
	local D = L.data
	if D.worksForm then
		-- (romance: "Forges-de-Belleville", "Officine di Montalto")
		local forms = split((D.worksForm:gsub("_", " ")), "|")
		local start = rng.hash(o.seed or 1, "wform", parent)
		for i = 0, #forms * #stems - 1 do
			local f = forms[(start + i) % #forms + 1]
			local s = stems[(start + i) % #stems + 1].text
			local nm = f:gsub("%%(%a)", function(c) if c == "w" then return s elseif c == "s" then return parent end end)
			if M.chars(nm) <= M.MAX_FULL and not (used or {})[nm] and not M.blocked(nm)
				and NW.allow(o.budget, nm, o.x, o.y, NW.keys(parent, o.budget and o.budget.cls)) then
				return nm, { spec = s, gen = f }
			end
		end
		return nil
	end
	local ctx = M.newCtx(lang, o.seed, o.real, used)
	if ctx then ctx.climate, ctx.cl = o.climate, M.climateOf(L, o.climate) end
	local w = { works = 1 }
	for k, v in pairs(M.WORKS_SITE[siteKind or ""] or M.WORKS_SITE.plain) do w[k] = v end
	ctx.budget = o.budget
	local nm, info = M.nameTown(ctx, { id = rng.hash(parent, siteKind or "-"), w = w, specList = stems, gens = L.worksGens,
		noAffix = true, noSuffix = true, strictBudget = true, x = o.x, y = o.y, layer = M.yearLayer(o.year) })
	if nm == parent then return nil end
	return nm, info
end

---------------------------------------------------------------------------
-- leftover named-feature claims (2026-10-14, NEXT_PHASE_BRIEF 53 item 2 / Part B: "Leftover cue claims can go to stop
-- names or districts (a 'Big Sandy' station) instead of a town", review Q2). Stateless: read from the saved water names
-- (ot_saved `rv`: one entry per river / lake town, at the town) and the names on the map, so a later session finds the
-- same claims.

M.CLAIM_NEAR_M = 1500     -- m: a water name's entry this near the town's centre is the town's claim

--- The town's unspent named-feature claim: the nearest water entry (waters = { { n, s, x, y, k } }) within o.maxD
--- (CLAIM_NEAR_M) of (x, y) whose stem (s, else n) is not in o.own (the town's name: it spent it) and is in fewer than
--- o.cap (FEAT_CAP + 1) of names (a list or a set of the map's names). Returns { n, s, k, uses } or nil.
function M.leftClaim(waters, names, x, y, o)
	o = o or {}
	if type(waters) ~= "table" or not tonumber(x) or not tonumber(y) then return nil end
	local maxD = tonumber(o.maxD) or M.CLAIM_NEAR_M
	local cap = tonumber(o.cap) or (M.FEAT_CAP + 1)
	local own = type(o.own) == "string" and lowerAll(o.own) or nil
	local list = {}
	if type(names) == "table" then
		if #names > 0 then
			for i = 1, math.min(#names, M.MAX_TOWNS * 10) do if type(names[i]) == "string" then list[#list + 1] = lowerAll(names[i]) end end
		else
			for nm in pairs(names) do
				if #list >= M.MAX_TOWNS * 10 then break end
				if type(nm) == "string" then list[#list + 1] = lowerAll(nm) end
			end
		end
	end
	local best, bd = nil, maxD
	for k, e in ipairs(waters) do
		if k > M.WATER_CAP * 4 then break end
		local stem = type(e) == "table" and (e.s or e.n) or nil
		if type(stem) == "string" and stem ~= "" and tonumber(e.x) and tonumber(e.y) then
			local d = math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2)
			if d <= bd then
				local ls = lowerAll(stem)
				if not (own and own:find(ls, 1, true)) then
					local uses = 0
					for _, nm in ipairs(list) do if nm:find(ls, 1, true) then uses = uses + 1 end end
					if uses < cap then best, bd = { n = e.n, s = stem, k = e.k, uses = uses }, d end
				end
			end
		end
	end
	return best
end

--- A district's name from a leftover claim (M.leftClaim): the feature's stem with a generic that fits the site kind
--- ("Glavenside", "Glaven Bridge"; a lake's: "Hawesmead"), as M.related names. Returns name, info or nil.
function M.claimName(lang, claim, kind, used, o)
	o = o or {}
	local L = M.lang(lang)
	if L == nil or L.script or type(claim) ~= "table" or type(claim.s) ~= "string" then return nil end
	local ctx = M.newCtx(lang, o.seed, o.real, used)
	ctx.climate, ctx.cl = o.climate, M.climateOf(L, o.climate)
	local e = newEntry(claim.s)
	e.kind = "stem"
	if claim.k == "l" then parseTags({ claim.s, "lake", "mere:.8", "pool:.6" }, 2, e)
	else parseTags({ claim.s, "river", "mouth:.8", "ford:.8", "bridge:.8", "confluence:.6", "bend:.6", "brook:.5" }, 2, e) end
	e.river = true
	local w = {}
	for k, v in pairs(M.DISTRICT_SITE[kind or ""] or {}) do w[k] = v end
	if claim.k == "l" then w.lake = math.max(w.lake or 0, 1) else w.river = math.max(w.river or 0, 1) end
	w.district = 1
	ctx.budget = o.budget
	local nm, info = M.nameTown(ctx, { id = rng.hash(claim.s, kind or "-"), w = w, fixedSpec = e, noAffix = true, noSuffix = true,
		strictBudget = true, x = o.x, y = o.y, layer = M.yearLayer(o.year) })
	if nm == nil or nm == claim.s or nm == claim.n then return nil end
	return nm, info
end

--- The form of a generated name for ot_offname's suffix count ("%ssands", "%s Falls", "Inver%s"): from the info of
--- nameTown (its generic entry) or of the romance works form; nil when unknown.
function M.formOf(info)
	if type(info) ~= "table" then return nil end
	local g = info.gE
	if type(g) == "table" and type(g.text) == "string" then
		local t = g.text
		if g.form == "suf" then return "%s" .. t
		elseif g.form == "after" then return "%s " .. t
		elseif g.form == "before" then return t .. " %s"
		elseif g.form == "pre" or g.form == "hyph" then return t .. "%s"
		elseif g.form == "ja" then return "%s" .. (g.k or t) end
	end
	if type(info.gen) == "string" and info.gen:find("%s", 1, true) then
		return (info.gen:gsub("%%w", function() return info.spec or "" end))
	end
	return nil
end

return M
