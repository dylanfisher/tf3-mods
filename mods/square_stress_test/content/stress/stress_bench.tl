-- Stress Test bench (plans/square_stress_test/BENCH.md): the pure part. A bench "sheet" is a list of tests
-- (a junction variant, its twins, its sets, which arms get a town); bench.plan packs every test's sets onto one
-- map (point clearances, not circles: BENCH.md "Layout") and returns a SquareStressShowcaseLayout, so the shared
-- Showcase build (gui/stress_junctions.tl buildRun) builds it with its towns, entries, links, zones and growth.
-- No api use: unit-tested offline (tests/square_stress_test/test_bench.lua).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
-- the wide street grid's layouts (the City lights Layout option; plain Lua, shared with the construction's updateFn)
local gridStreets = ug_require "square_stress_test::/stress/stress_grid_streets.lua" as SquareStressGridStreets

local bench : SquareStressBench = {
	VERSION = 1,               -- the presets' version (BENCH_START spec=<sheet>@<VERSION>): results pool only within one
	STEP = 100.0,              -- m: the packer's raster step
	LINK_TOWN = 625.0,         -- m: a link (junction -> its town) at least this far from another group's town centre
	LINK_JUNCTION = 400.0,     -- m: a link at least another group's junction reach + this from its centre
	LINK_LINK = 100.0,         -- m: two links of different groups at least this far apart (and never crossing)
	BUCKET = 2000.0,           -- m: the placed groups' lookup grid
	SIZE = 2,                  -- TOWN_SIZES index of every bench town (Medium)
	POP = 400,                 -- people per town (growFactorForCap)
	PERSONS_PER_TOWN = 400,    -- sim persons per town (runs 5-6)
	DRIVER_SHARE = 0.36,       -- drivers of them at a time (run 6: 9920 of 27569)
	BUILD_S_PER_TOWN = 5.0,    -- s of build per town (runs 5-6: 4.6-5.3 s)
}

---------------------------------------------------------------------------
-- Twins and variants

local LIGHTS_AB = logic.LIGHTS_AB
-- the twin modes the bench builds (zone ab names; the letter is the zone id's: stress_flow TWIN_LETTER)
bench.AB = {
	sl = LIGHTS_AB[1],
	game = LIGHTS_AB[2],
	sl_lock = LIGHTS_AB[4],
	-- Smart Lanes lanes with the game's lights left standing at rings and slip / ramp nodes (BENCH.md SL-1)
	sl_keeplights = { ab = "sl_keeplights", twin = "f", label = "Keep lights",
		note = "Smart Lanes lanes, lights at rings and ramps left as the game made them" } as SquareStressShowcaseAb,
	-- Smart Lanes' ring layout variants (square_smart_lanes PLAN.md "Ring layout variants (bench)"; letters h-m)
	sl_rturbo = { ab = "sl_rturbo", twin = "h", label = "Ring turbo", note = "turbo, written whole" } as SquareStressShowcaseAb,
	sl_rmatch = { ab = "sl_rmatch", twin = "i", label = "Ring matched", note = "matched lanes, written whole" } as SquareStressShowcaseAb,
	sl_rout1 = { ab = "sl_rout1", twin = "j", label = "Ring outer exit", note = "only the outer lane exits, fanned" } as SquareStressShowcaseAb,
	sl_r2exit = { ab = "sl_r2exit", twin = "k", label = "Ring two exits", note = "the two outer lanes exit" } as SquareStressShowcaseAb,
	sl_rspiral = { ab = "sl_rspiral", twin = "l", label = "Ring spiral", note = "spiral by destination (turbo roundabout)" } as SquareStressShowcaseAb,
	sl_rspread = { ab = "sl_rspread", twin = "m", label = "Ring spread", note = "turbo plus the centre lanes" } as SquareStressShowcaseAb,
	-- the spiral with its inward lane change on a plain ring node half way between the arms (Smart Lanes PLAN.md
	-- "Mid-node spiral (sl_rsplit)"; Sheet 4 v3 only: its ring has those nodes, bench_rb2tm); not in RING_MODES (the
	-- micro bench's rings have no mid nodes: it would be sl_rspiral there)
	sl_rsplit = { ab = "sl_rsplit", twin = "n", label = "Ring split", note = "spiral, lane change at the mid nodes" } as SquareStressShowcaseAb,
	-- no lane change at the arms, every one (both ways) at the mid nodes (Smart Lanes PLAN.md "Mid-node lane changes
	-- (sl_rmid)"; Sheet 4 v4 only, as sl_rsplit)
	sl_rmid = { ab = "sl_rmid", twin = "o", label = "Ring mid", note = "lane changes only at the mid nodes" } as SquareStressShowcaseAb,
	-- ring lane use (square_smart_lanes PLAN.md "Ring lane use"; Sheet 5): sl_rmid for exits wider than its exit-only lanes
	-- (Smart Lanes adds the mid nodes itself), and turbo with the inner lanes fed. Letters w and y: a-v are taken (stress_flow
	-- TWIN_LETTER, MID_LETTER p-t, u (the dropped sl_classic, older saves), sl_auto v), g is the zone id's set marker, x the fallback letter
	sl_rmid2 = { ab = "sl_rmid2", twin = "w", label = "Ring mid 2", note = "mid-node lane changes, wide exits fed by the first circulating lane" } as SquareStressShowcaseAb,
	sl_rturbo_in = { ab = "sl_rturbo_in", twin = "y", label = "Ring turbo in", note = "turbo with the inner ring lanes fed" } as SquareStressShowcaseAb,
}
-- the ring layout modes in Smart Lanes' by_ab order
bench.RING_MODES = { "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread" }

--- A ring layout test's twins (game, sl, the six modes) and comparisons (sl vs game, every mode vs sl and vs game).
local function ringTwins() : {string}, {{string}}
	local twins : {string} = { "game", "sl" }
	local compare : {{string}} = { { "sl", "game" } }
	for _, m in ipairs(bench.RING_MODES) do twins[#twins + 1] = m end
	for _, m in ipairs(bench.RING_MODES) do compare[#compare + 1] = { m, "sl" } end
	for _, m in ipairs(bench.RING_MODES) do compare[#compare + 1] = { m, "game" } end
	return twins, compare
end

local function variant(id : string, label : string, file : string, kind : string, fixed : {string : number}) : SquareStressShowcaseType
	return { id = id, label = label, file = file, kind = kind, fixed = fixed, ranges = {}, short = label }
end

-- square_roundabouts' param indices (their .con.lua value lists; tests check the labels): arm / main / side roads
-- 1-6 = Town small, medium, large, Country small, medium, large; sqrb_arms 3 = "4"; sqrb_signals 1 = Off (the
-- game's AUTO decides); sqrb_ix_highway 2 = M (highway_new_medium: 2 lanes a carriageway); sqrb_ix_cross 6 = Country large.
bench.VARIANTS = {
	rb4 = variant("bench_rb4", "RB4 2L", "square_roundabouts.con", "rb", { sqrb_shape = 1, sqrb_centre = 1, sqrb_lanes = 2,
		sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1, sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1, sqrb_arm_type = 5 }),
	cht = variant("bench_cht", "Channel T", "square_roundabouts_channel.con", "rb", { sqrb_ch_layout = 1, sqrb_ch_scale = 1,
		sqrb_ch_main = 5, sqrb_ch_side = 5, sqrb_ch_slips = 1, sqrb_ch_splitter = 1, sqrb_ch_arm_length = 1, sqrb_ch_island = 1 }),
	dia = variant("bench_dia", "Diamond S", "square_roundabouts_highway_diamond.con", "ix", { sqrb_ix_highway = 2, sqrb_hx_level = 1,
		sqrb_hx_scale = 1, sqrb_hx_ramp = 1, sqrb_hx_arm_length = 1, sqrb_ix_cross = 6 }),
	-- stress_crossing shape 4 (Straight): the west arm Country large (3 + 3), the east arm (main2 6 = ROADS[5]) Country medium (2 + 2)
	drop = variant("bench_drop", "Lane drop 3-2", logic.SHOWCASE_PLAIN_FILE, "plain", { sqst_x_shape = 4, sqst_x_main = 6,
		sqst_x_main2 = 6, sqst_x_side = 5, sqst_x_angle = 1, sqst_x_lights = 1 }),
}

-- The 3-lane ring: the Stress Test's own entry roundabout (stress_entry_streets: highway_new_large ring, 4 country large
-- arms ending 46 m out; square_roundabouts' rings come in 1, 2 or 4 lanes only). Anticlockwise (right-hand traffic),
-- no shortened arm. The 4-lane ring: square_roundabouts' Roundabout, ring lanes "4" (town_new_one_way_medium), scale XS
-- (sqrb_radius_size 1: 10 m inside the ring; the ring grows if the roads don't fit),
-- country large arms.
bench.VARIANTS.rb3 = variant("bench_rb3", "RB 3-lane", logic.ENTRY_FILE, "rb", { sqst_entry_dir = 1, sqst_entry_ring = 2,
	sqst_entry_in_axis = 1, sqst_entry_in_reach = 1 })
bench.VARIANTS.rb4l = variant("bench_rb4l", "RB 4-lane", "square_roundabouts.con", "rb", { sqrb_shape = 1, sqrb_centre = 1, sqrb_lanes = 3,
	sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1, sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1, sqrb_arm_type = 6 })
-- Sheet 4's ring: sheet 1's 2-lane ring (square_roundabouts' Roundabout, ring lanes "2", scale XS, signals Off) with
-- 1-lane town streets as arms (sqrb_arm_type 1 = town_new_small: 1 + 1 lanes, sidewalks), a player's town roundabout
bench.VARIANTS.rb2t = variant("bench_rb2t", "RB 2L town", "square_roundabouts.con", "rb", { sqrb_shape = 1, sqrb_centre = 1, sqrb_lanes = 2,
	sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1, sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1, sqrb_arm_type = 1 })
-- Sheet 4 v3's ring: rb2t with a plain ring node half way between every two neighbouring arms (square_roundabouts' dev
-- override sqrb_dev_ring_mid = 1: 8 ring nodes, 45 degrees apart, same radius and arms; plans/square_roundabouts/PLAN.md
-- "Ring mid nodes (dev)"), where Smart Lanes' sl_rsplit writes its lane change; every twin gets it (same geometry)
bench.VARIANTS.rb2tm = variant("bench_rb2tm", "RB 2L town mid", "square_roundabouts.con", "rb", { sqrb_shape = 1, sqrb_centre = 1,
	sqrb_lanes = 2, sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1, sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1,
	sqrb_arm_type = 1, sqrb_dev_ring_mid = 1 })
-- Sheet 4 v4's wider rings with mid nodes (the user: "same idea for 3 and 4 lane roundabouts, so we use all lanes and allow
-- mid-roundabout switching"): the micro bench's 3-lane ring (rb3: the Stress Test's own entry roundabout,
-- highway_new_large at 22 m, 4 country large arms) with 1 plain node per quarter (sqst_entry_mid 2: 2 leave no room
-- beside its 30 m arms, stress_entry_streets), and its 4-lane ring (rb4l) with 2 per gap (sqrb_dev_ring_mid 2: the
-- ring grows from 10 to 20 m inside so the junctions keep their room; 1 node would leave the mid-node layout one exit
-- lane, 3 grow it to 35 m)
bench.VARIANTS.rb3m = variant("bench_rb3m", "RB 3-lane mid", logic.ENTRY_FILE, "rb", { sqst_entry_dir = 1, sqst_entry_ring = 2,
	sqst_entry_in_axis = 1, sqst_entry_in_reach = 1, sqst_entry_mid = 2 })
bench.VARIANTS.rb4lm = variant("bench_rb4lm", "RB 4-lane mid", "square_roundabouts.con", "rb", { sqrb_shape = 1, sqrb_centre = 1,
	sqrb_lanes = 3, sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1, sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1,
	sqrb_arm_type = 6, sqrb_dev_ring_mid = 2 })

-- Sheet 4 v4's twins and comparisons, the same for its three rings
bench.MID_TWINS = { "game", "sl", "sl_rspiral", "sl_rsplit", "sl_rmid" }
bench.MID_COMPARE = { { "sl_rmid", "sl_rsplit" }, { "sl_rmid", "sl_rspiral" }, { "sl_rmid", "game" }, { "sl_rsplit", "sl_rspiral" },
	{ "sl", "game" } }

-- Sheet 4 v5: twins of one set on two ring geometries, "<ab>@<geom>" (BENCH.md "Sheet 4" v5): the zone's mode stays the
-- Smart Lanes mode (ab), the twin letter of a twin on the mid-node ring is its own (no clash with the plain ring's
-- game / sl twins in one set), its town names end in " mid"
bench.MID_LETTER = { game = "p", sl = "q", sl_rspiral = "r", sl_rsplit = "s", sl_rmid = "t" }

--- The mode record of a test's twin: bench.AB[tw], or for "<ab>@<geom>" a copy with geom set (mid: its own letter
--- bench.MID_LETTER and " mid" after its label). nil for an unknown ab.
function bench.twinMode(tw : string) : SquareStressShowcaseAb
	local ab, geom = tw:match("^([%w_]+)@(%w+)$")
	if ab == nil then return bench.AB[tw] end
	local base = bench.AB[ab]
	if base == nil then return nil end
	local mid = geom == "mid"
	return { ab = base.ab, twin = mid and (bench.MID_LETTER[ab] or base.twin) or base.twin,
		label = mid and ((base.label or base.ab) .. " mid") or base.label, note = base.note, litPlainOnly = base.litPlainOnly,
		geom = geom } as SquareStressShowcaseAb
end

-- Sheet 4 v5's twins and comparisons: the decision question (the mid-node candidate vs the game on the plain ring),
-- the candidate vs Smart Lanes' shipped default on the plain ring, what the nodes alone do (game mid vs plain), and the
-- shipped default vs the game
bench.PLAIN_MID_TWINS = { "game@plain", "sl@plain", "game@mid", "sl_rsplit@mid" }
bench.PLAIN_MID_COMPARE = { { "sl_rsplit@mid", "game@plain" }, { "sl_rsplit@mid", "sl@plain" }, { "game@mid", "game@plain" },
	{ "sl@plain", "game@plain" } }
bench.PLAIN_MID_COMPARE2 = { { "sl_rsplit@mid", "game@plain" }, { "sl_rsplit@mid", "sl@plain" }, { "game@mid", "game@plain" },
	{ "sl@plain", "game@plain" }, { "sl_rmid@mid", "game@plain" }, { "sl_rmid@mid", "sl_rsplit@mid" } }

-- Sheet 5, ring lane use (square_smart_lanes PLAN.md "Ring lane use", BENCH.md "Sheet 5"): traffic mixes made from town
-- sizes per arm, one mix per set (every twin of the set sees it): even (four equal towns), straight (the N and S towns
-- large: their trips take the 2nd exit both ways), adjacent (N and E large: mostly 1st + 3rd exits; a true first-exit mix
-- needs one-way demand). Equal total people per ring (4 x 350 = 2 x 600 + 2 x 100). Town names end in the word.
bench.LU_MIXES = { "even", "straight", "adjacent" }
bench.LU_POPS = { large = 600, small = 100, even = 350 }
bench.LU_SIDES = {
	straight = { N = "large", S = "large", E = "small", W = "small" },
	adjacent = { N = "large", E = "large", S = "small", W = "small" },
} as {string : {string : string}}

-- Sheet 6 (BENCH.md "Sheet 6"): the same mixes at heavy traffic, 2400 people per ring (s5: 1400; s4 v5's town ring: 1600)
bench.HM_POPS = { large = 1000, small = 200, even = 600 }

--- One town's people in a set of a mix: (people, the name word "large" / "small"; nil word for an even town). pops: the
--- test's own town sizes (nil: bench.LU_POPS).
function bench.mixPop(mix : string, side : string, pops? : {string : number}) : number, string
	local p = pops or bench.LU_POPS
	local sides = bench.LU_SIDES[mix]
	if sides == nil then return p.even, nil end
	local word = sides[side] or "small"
	return p[word], word
end

--- The mix of a test's k-th set (its mixes in turn; nil without mixes).
function bench.setMix(t : SquareStressBenchTest, k : integer) : string
	if t.mixes == nil or #t.mixes == 0 then return nil end
	return t.mixes[(k - 1) % #t.mixes + 1]
end

local function test(t : SquareStressBenchTest) : SquareStressBenchTest
	t.linkLanes = t.linkLanes or 0
	return t
end

local function lit(i : integer) : SquareStressShowcaseType
	return logic.LIGHTS_SHAPES[i]
end

-- The sheets (BENCH.md "The first bench", 16 km maps). Tests in priority order: a test that does not fit whole
-- loses its last sets, the later ones fill what is left.
---------------------------------------------------------------------------
-- MICRO BENCH: SWAP TESTS HERE (plans/square_stress_test/BENCH.md "Micro bench").
-- A small one-off sheet with its own button ("Micro"). To run another test: edit `tests` below (a variant from
-- bench.VARIANTS or a new one above, the arms that get a town, the twins, the comparisons, the sets), bump `version`
-- (results of different versions never pool), rebuild (make test MOD=mods/square_stress_test, make link). Keep it to
-- what a 16 km map holds (the window's plan line says; the offline test prints it). `pop` is every town's people.
-- `pool`: the report adds a row pooling every test's pairs of the same comparison (the tests ask one question).
local RT, RC = ringTwins()
bench.MICRO = {
	-- version 2 (2026-10-13): the ring layout variants. v1 (3- / 4-lane rings, game vs sl, 6 sets each, 800 people): session
	-- 2026-10-13_0837_bench-micro-560595 (RESULTS.md)
	version = 2,
	title = "Micro bench: ring layouts on 2-, 3- and 4-lane roundabouts",
	-- 600 people a town: v1's 800 ran at ~52 % standing map-wide (too close to a jam to rank layouts); 600 fills x1.5 by
	-- capacity, where a forced size command still fills its target fully (docs/findings/towns.md)
	pop = 600,
	pool = true,
	rank = true,
	-- one set of every ring type before any second set: each type gets at least one
	roundRobin = true,
	-- the 4- and 3-lane rings first (the user's questions: the 4-lane ring's unused centre lane, "all 3 lanes into all 3"),
	-- so a second set, when it fits, goes to them; 16 km: 4 sets (32 junctions, 128 towns), see BENCH.md
	tests = {
		test({ id = "rb4l", title = "Roundabout, 4-lane ring, 4 country large arms", variants = { bench.VARIANTS.rb4l },
			towns = { "N", "E", "S", "W" }, twins = RT, compare = RC, sets = 2 }),
		test({ id = "rb3", title = "Roundabout, 3-lane ring, 4 country large arms", variants = { bench.VARIANTS.rb3 },
			towns = { "N", "E", "S", "W" }, twins = RT, compare = RC, sets = 2 }),
		test({ id = "rb2", title = "Roundabout, 2-lane ring, 4 country medium arms", variants = { bench.VARIANTS.rb4 },
			towns = { "N", "E", "S", "W" }, twins = RT, compare = RC, sets = 2 }),
	},
}
-- END OF THE MICRO BENCH BLOCK
---------------------------------------------------------------------------

bench.SHEETS = {
	-- version 2 (2026-10-13): the lane drop test is gone (its game default already equals Smart Lanes' rule: Smart Lanes
	-- logged "same" at every drop centre of session 2026-10-13_0610_session; no other lane drop is known to differ), its
	-- room to roundabout sets: 11, the most a 16 km map holds
	{ id = "bench_s1", key = "s1", title = "Bench sheet 1: roundabouts", version = 2, minKm = 16, slLights = true,
		tests = {
			test({ id = "rb4", title = "Roundabout, 2-lane ring, 4 country medium arms", variants = { bench.VARIANTS.rb4 },
				towns = { "N", "E", "S", "W" }, twins = { "game", "sl", "sl_keeplights" }, compare = { { "sl", "game" }, { "sl", "sl_keeplights" } },
				sets = 11 }),
		} },
	{ id = "bench_s2", key = "s2", title = "Bench sheet 2: slip lanes and interchanges", version = 1, minKm = 16, slLights = true,
		tests = {
			test({ id = "cht", title = "Channelized T, near-side slip lanes, country medium", variants = { bench.VARIANTS.cht },
				towns = { "E", "N", "W" }, twins = { "game", "sl", "sl_keeplights" }, compare = { { "sl", "game" }, { "sl", "sl_keeplights" } },
				sets = 9 }),
			-- towns W, E (highway) and N (cross road): every ramp and both terminals carry traffic; the S arm stays a stub
			test({ id = "dia", title = "Diamond S, 2-lane highway, country large cross road", variants = { bench.VARIANTS.dia },
				towns = { "E", "N", "W" }, twins = { "game", "sl" }, compare = { { "sl", "game" } }, sets = 6, pairLanes = 4 }),
		} },
	{ id = "bench_s3", key = "s3", title = "Bench sheet 3: lit crossroads and T-junctions", version = 1, minKm = 16, slLights = false,
		tests = {
			test({ id = "lt22", title = "Lit T, 2 lanes each way", variants = { lit(4) }, towns = { "E", "N", "W" },
				twins = { "sl", "game", "sl_lock" }, compare = { { "sl", "game" }, { "sl", "sl_lock" } }, sets = 9, litYes = true }),
			test({ id = "lx", title = "Lit crossroads 2x2 / 3x3 / 3x2 in turn", variants = { lit(1), lit(2), lit(3) },
				towns = { "N", "E", "S", "W" }, twins = { "sl", "game", "sl_lock" }, compare = { { "sl", "game" }, { "sl", "sl_lock" } },
				sets = 3, litYes = true }),
		} },
	-- sheet 4 (2026-10-13): one question. A player's 2-lane one-way roundabout with 1-lane town streets as arms runs
	-- best with their hand-made spiral (the outer ring lane exit-only, the inner lane stays or moves out, the entry
	-- joins both): Smart Lanes' sl_rspiral. Its default (sl) falls back to matched lanes there (every exit has one
	-- lane: narrow_exit), so the inner lane is never entered or left at a junction. Micro v2 had this ring only with
	-- 2 + 2 country arms, one set, saturated. 3 twins x 9 sets (27 junctions, 108 towns): 9 pairs per comparison
	-- (8 of 9 significant); a 4th twin (sl_rspread) leaves room for 8 sets only (8 of 8 needed: power 0.43 instead of
	-- 0.77 at q = 0.9). Towns of 400 people (the least a Medium town takes: x1), BENCH.md "Sheet 4".
	-- Version 2 (2026-10-13): one set (3 junctions, 12 towns; user: "keep it simpler, sample size of 1": a quick
	-- direction, no significance), links on the 2 + 2 country road (v1's 1 + 1 country links were all refused,
	-- session of 2026-10-13 23:02; Sheet 1 joined 2 + 2 links to the 3-lane entries), falling back to copies of the
	-- town street, then the 1 + 1 country road (showToTown); session 2026-10-13_2341_bench-s4-774314 (BENCH_DONE ok=yes)
	-- Version 3 (2026-10-14): a 4th twin sl_rsplit (the user: "spiral, but the outer to inner lane change on a node between
	-- the arms, so entering traffic doesn't overlap as much"): the ring gets a plain node half way between neighbouring
	-- arms (bench_rb2tm), for every twin, so all four drive the same geometry (game, sl and sl_rspiral leave those nodes
	-- straight on, as the game makes them: tested); test id rb2tm (not rb2t: other geometry). Still one set
	-- Version 5 (2026-10-14, after v4's live samples: every twin of the 4-lane mid-node ring jammed, the game's too; the
	-- user: "we're missing the default baseline"): per ring size twins on the PLAIN ring (as players have it: game, and
	-- Smart Lanes' shipped default) next to twins on the mid-node ring (game: what the nodes alone do; sl_rsplit; on the
	-- 2-lane ring also sl_rmid), one set each: 13 junctions, 52 towns. Twins "<ab>@plain" / "<ab>@mid" (bench.twinMode)
	-- Version 4 (2026-10-14, after v3 ran: mid nodes written, VERIFY same=8): a 5th twin sl_rmid (the user: "don't allow
	-- the inner to outer merge at an intersection, they would do it mid-node"), and the same five twins on a 3-lane and a
	-- 4-lane ring with mid nodes (rb3m, rb4lm; their links at the arms' own lanes, as the micro bench): 15 junctions,
	-- 60 towns
	{ id = "bench_s4", key = "s4", title = "Bench sheet 4: roundabouts with and without nodes between the arms", version = 5, minKm = 16,
		slLights = true, rank = true,
		tests = {
			test({ id = "rb2v", title = "Roundabout, 2-lane ring, 4 one-lane town street arms, plain and with mid nodes",
				variants = { bench.VARIANTS.rb2t, bench.VARIANTS.rb2tm }, geoms = { plain = 1, mid = 2 }, towns = { "N", "E", "S", "W" },
				twins = { "game@plain", "sl@plain", "game@mid", "sl_rsplit@mid", "sl_rmid@mid" },
				compare = bench.PLAIN_MID_COMPARE2, sets = 1, linkLanes = 4 }),
			test({ id = "rb3v", title = "Roundabout, 3-lane ring, 4 country large arms, plain and with mid nodes",
				variants = { bench.VARIANTS.rb3, bench.VARIANTS.rb3m }, geoms = { plain = 1, mid = 2 }, towns = { "N", "E", "S", "W" },
				twins = bench.PLAIN_MID_TWINS, compare = bench.PLAIN_MID_COMPARE, sets = 1 }),
			test({ id = "rb4v", title = "Roundabout, 4-lane ring, 4 country large arms, plain and with mid nodes",
				variants = { bench.VARIANTS.rb4l, bench.VARIANTS.rb4lm }, geoms = { plain = 1, mid = 2 }, towns = { "N", "E", "S", "W" },
				twins = bench.PLAIN_MID_TWINS, compare = bench.PLAIN_MID_COMPARE, sets = 1 }),
		} },
	-- sheet 5 (2026-10-15): ring lane use (square_smart_lanes PLAN.md "Ring lane use", BENCH.md "Sheet 5"). The user's
	-- 2-lane ring with 2-lane arms queues every car past the first exit in the inner entry lane (turbo: one circulating
	-- lane); on 4-lane rings with 3-lane arms nothing uses the inner lane. Per ring 3 sets, one per traffic mix (even,
	-- straight, adjacent: town sizes per arm, bench.LU_MIXES), so every twin mode sees every mix. Each ring twin logs its
	-- measured turning mix (RINGMIX) and its ring lane occupancy (RINGLANE). The 3-lane ring with 2-lane arms is left
	-- out: the entry roundabout's arms are country large only (new geometry). 24 junctions, 96 towns
	{ id = "bench_s5", key = "s5", title = "Bench sheet 5: ring lane use", version = 1, minKm = 16, slLights = true, rank = true,
		pop = bench.LU_POPS.even,
		tests = {
			test({ id = "lu2", title = "Roundabout, 2-lane ring, 4 country medium arms, three traffic mixes", variants = { bench.VARIANTS.rb4 },
				towns = { "N", "E", "S", "W" }, twins = { "game", "sl_rturbo", "sl_rmid2", "sl_rmatch" },
				compare = { { "sl_rturbo", "game" }, { "sl_rmid2", "game" }, { "sl_rmatch", "game" }, { "sl_rmid2", "sl_rturbo" },
					{ "sl_rmatch", "sl_rturbo" } },
				sets = 3, mixes = bench.LU_MIXES, ringMix = true }),
			test({ id = "lu4", title = "Roundabout, 4-lane ring, 4 country large arms, three traffic mixes", variants = { bench.VARIANTS.rb4l },
				towns = { "N", "E", "S", "W" }, twins = { "game", "sl_rturbo", "sl_rturbo_in", "sl_rspread" },
				compare = { { "sl_rturbo", "game" }, { "sl_rturbo_in", "game" }, { "sl_rspread", "game" }, { "sl_rturbo_in", "sl_rturbo" },
					{ "sl_rspread", "sl_rturbo" } },
				sets = 3, mixes = bench.LU_MIXES, ringMix = true }),
		} },
	-- sheet 6 (2026-10-15): the shipped mid-node default under heavy traffic (BENCH.md "Sheet 6"). Bench s5's sl_rmid2 (crossing
	-- lane changes at mid nodes, 2-lane arms) gridlocked at 1400 people a ring (session 2026-10-15_0602_bench-s5-ring-34019);
	-- the default Smart Lanes ships for a 2-lane ring whose exits all have one lane is sl_rmid (the same crossing changes at
	-- mid nodes Smart Lanes adds itself), won only at lighter traffic (Sheet 4 v3-v5: 1600 a ring, 30-42 % standing). Sheet 4's
	-- town ring (bench_rb2t, plain: the sl twin must split it itself and log layout=sl_rmid default=one_lane_exits), the
	-- Sheet 5 mixes at 2400 people a ring (bench.HM_POPS), 30 game min recorded so a lock has time to form. sl_rturbo writes
	-- matched lanes on this ring (turbo needs 2+ lane exits: APPLY turbo=false), so sl_rturbo vs sl_rmatch is an A/A pair:
	-- the noise of identical twins. 12 junctions, 48 towns
	{ id = "bench_s6", key = "s6", title = "Bench sheet 6: the mid-node default under heavy traffic", version = 1, minKm = 16,
		slLights = true, rank = true, pop = bench.HM_POPS.even, recordS = 1800,
		tests = {
			test({ id = "hm2", title = "Roundabout, 2-lane ring, 4 one-lane town street arms, heavy traffic, three traffic mixes",
				variants = { bench.VARIANTS.rb2t }, towns = { "N", "E", "S", "W" }, twins = { "game", "sl", "sl_rmatch", "sl_rturbo" },
				compare = { { "sl", "game" }, { "sl_rmatch", "game" }, { "sl_rturbo", "game" }, { "sl", "sl_rmatch" }, { "sl_rmatch", "sl_rturbo" } },
				sets = 3, mixes = bench.LU_MIXES, pops = bench.HM_POPS, ringMix = true, linkLanes = 4 }),
		} },
	-- the micro bench (its tests: bench.MICRO above); zone ids "microg3a"
	{ id = "bench_micro", key = "micro", button = "Micro", title = bench.MICRO.title, version = bench.MICRO.version, minKm = 16,
		slLights = true, pop = bench.MICRO.pop, pool = bench.MICRO.pool, roundRobin = bench.MICRO.roundRobin, rank = bench.MICRO.rank,
		tests = bench.MICRO.tests },
} as {SquareStressBenchSheet}

---------------------------------------------------------------------------
-- City lights at scale (BENCH.md "City lights at scale"; user 2026-10-15: "make every light in the big grid cities be
-- auto timer lights so we can see what happens with many at once"). Not a junction sheet (not in bench.SHEETS): big
-- grid towns (Large: the wide 800 m street grid, locked, a country ring), every inner crossing of the grid lit (Yes where
-- the game's AUTO lit none), in pairs: one city whose lit junctions Smart Lanes keeps re-timing ("auto", enrolled through
-- SmartLanes.auto op=add after the baseline), one never enrolled ("control"), side by side, never linked. The run: the
-- baseline (the phases Smart Lanes' setting gives every city alike) for baselineS, the enroll, then the rest of recordS.
-- Each city is one traffic log zone, not sent to Smart Lanes (its lanes and phases are its global ones, every city alike).
bench.CITY = {
	id = "bench_city", key = "city", button = "City lights", title = "City lights at scale: automatic light timing on big grid towns",
	-- v2 (2026-10-15): the options (Layout, Busy, Baseline, Swap roles; bench.citySheet); the defaults build v1's run
	version = 2, minKm = 16, slLights = false, tests = {},
	-- 4x (the pass criteria are per frame at 4x), 15 game min baseline + 90 after the enroll (Smart Lanes step B v4: a
	-- junction is first decided after 8 snapshots, ~16 game min; a saturated one settles ~45 game min after enrolling; the
	-- report compares from 45 game min after the enroll, flow_report --auto-settle 2700), the shots from 700 m up
	speed = 4, recordS = 6300, baselineS = 900, shotDist = 700.0,
	city = {
		pairs = 3,          -- auto + control side by side; 3 pairs = 243 enrolled junctions (Smart Lanes' cap: 1000)
		size = 3,           -- TOWN_SIZES index: Large (capacity 1600; its wide grid is 800 m, 9 x 9 inner crossings 80 m apart)
		pop = 3000,         -- people a city grows to (growFactorForCap from its capacity: x1.9)
		spacing = 4000.0,   -- m between neighbouring city centres (columns), rows the same
		control = true,     -- false: no control cities, the enroll is SmartLanes.auto op=all
		layout = "plain",
		busy = false,
		swap = false,
	},
} as SquareStressBenchSheet
-- The City lights options (BENCH.md "Funnel layouts"; user 2026-10-15: "force streets into narrow sections like an hour
-- glass, or with holes in the grid"; runs 1 and 2 were too quiet and their pairs unequal at baseline):
--   Layout: the wide grid plain (as v1), as an hourglass (a band through the middle where only the 3 central north-south
--     streets go on) or with holes (4 holes of 2 x 2 blocks, placed by the run's seed, the same in every city),
--     stress_grid_streets.lua grid.layout; the streets left out are never built,
--   Busy: about 2.5 x the people (CITY_BUSY: 7500 wanted; the grid's lots cap it, the log has the real pop),
--   Baseline: 15 or 30 game min before the enroll (90 after it either way),
--   Swap roles: the other city of each pair gets the automatic timing (a second run with swapped roles cancels the
--     pairs' own differences; the report pairs the two runs).
bench.CITY_LAYOUTS = { "plain", "hourglass", "holes" }        -- stress_grid_streets.lua LAYOUTS (the construction's index)
bench.CITY_LAYOUT_LABELS = { "Plain grid", "Hourglass", "Holes" }
bench.CITY_BASELINES = { 900, 1800 }                          -- game s before the enroll
bench.CITY_BASELINE_LABELS = { "15 min", "30 min" }
bench.CITY_AFTER_S = 5400                                     -- game s recorded after the enroll (v1: 6300 - 900)
-- Busy: 2.5 x v1's 3000 people wanted, the size command from the Large town's capacity (x4.7); the level weights pushed
-- further to level 4 (v1 run 2: x1.9 for 3000 gave 1974-2117 on the locked grid: the lots, not the factor, cap it)
bench.CITY_BUSY = { pop = 7500, weights = { 0.0, 0.0, 0.25, 1.0 } } as SquareStressBenchCityOpts
bench.CITY_BLOCK = 80.0      -- stress_grid_streets.BLOCK: the wide grid's target block
bench.CITY_SNAP = 4.0        -- m: a node this close to an inner grid point is that crossing
bench.CITY_ZONE_LETTER = { auto = "v", control = "b" }   -- the zone ids' twin letters (sl_auto's v, game's b)
bench.CITY_AB = { auto = "city_auto", control = "city_control" }
bench.CITY_EVENT_MAX = 60    -- Smart Lanes' sl_auto.lua EVENT_MAX: nodes per SmartLanes.auto event (a larger one is ignored whole)

--- The sheet of a key ("s1") or id ("bench_s1"); nil when none. "city": bench.CITY.
function bench.sheet(key : string) : SquareStressBenchSheet
	for _, s in ipairs(bench.SHEETS) do
		if s.key == key or s.id == key then return s end
	end
	if key == bench.CITY.key or key == bench.CITY.id then return bench.CITY end
	return nil
end

--- The inner grid lines of a wide grid of half side `half` (stress_grid_streets.lines without the ring): offsets from the
--- centre, and the step.
function bench.cityLines(half : number) : {number}, number
	local n = 2 * math.max(1, math.floor(half / bench.CITY_BLOCK + 0.5))
	local step = 2 * half / n
	local out : {number} = {}
	for k = 1, n - 1 do out[#out + 1] = -half + k * step end
	return out, step
end

--- The City lights sheet for the window's options (nil ui: the defaults, the v1 run): a copy of bench.CITY.
function bench.citySheet(ui : SquareStressBenchCityUi) : SquareStressBenchSheet
	local u : SquareStressBenchCityUi = ui or {}
	local base = bench.CITY
	local c0 = base.city
	local layout = bench.CITY_LAYOUTS[u.layout or 1] or "plain"
	local baselineS = bench.CITY_BASELINES[u.baseline or 1] or bench.CITY_BASELINES[1]
	local city : SquareStressBenchCityOpts = { pairs = c0.pairs, size = c0.size, pop = c0.pop, spacing = c0.spacing, control = c0.control,
		layout = layout, busy = u.busy == true, swap = u.swap == true }
	if city.busy then
		city.pop = bench.CITY_BUSY.pop
		city.weights = bench.CITY_BUSY.weights
	end
	return { id = base.id, key = base.key, button = base.button, title = base.title, version = base.version, minKm = base.minKm,
		slLights = base.slLights, tests = base.tests, speed = base.speed, recordS = baselineS + bench.CITY_AFTER_S, baselineS = baselineS,
		shotDist = base.shotDist, city = city } as SquareStressBenchSheet
end

--- The holes pattern of a run's seed (stress_grid_streets.lua HOLE_PATTERNS of them): the same seed, the same holes.
function bench.cityHolesPattern(seed : integer) : integer
	local n = gridStreets.HOLE_PATTERNS
	return math.floor((math.floor(seed or 1) - 1) % n) + 1
end

--- The street grid layout of a city of the sheet (its holes from the seed; nil seed: pattern 1, every pattern has the
--- same counts).
function bench.cityLayout(sheet : SquareStressBenchSheet, seed? : integer) : SquareStressStreetLayout
	local c = sheet.city
	return gridStreets.layout(logic.gridHalfOfSize(c.size), c.layout or "plain", seed ~= nil and bench.cityHolesPattern(seed) or 1,
		bench.CITY_BLOCK)
end

--- "layout=plain busy=0 baseline_s=900 role_swap=0" (bench_city line).
function bench.cityOptionKeys(sheet : SquareStressBenchSheet) : string
	local c = sheet.city
	return string.format("layout=%s busy=%d baseline_s=%d role_swap=%d", c.layout or "plain", c.busy and 1 or 0,
		math.floor(sheet.baselineS or 0), c.swap and 1 or 0)
end

--- The options in words (the confirm dialog).
function bench.cityOptionsText(sheet : SquareStressBenchSheet) : string
	local c = sheet.city
	local L = bench.cityLayout(sheet)
	local what = "plain grid"
	if L.name == "hourglass" then
		what = string.format("hourglass (a band through the middle where only the %d central streets go on)", L.neck)
	elseif L.name == "holes" then
		what = string.format("%d holes of 2 x 2 blocks (placed by the seed, the same in every city)", #L.holes)
	end
	return string.format("Layout: %s, %d lit crossings per city. People: about %d wanted per city%s. Baseline: %d game min, then %d after the automatic timing starts. Roles: %s.",
		what, L.crossings, math.floor(c.pop), c.busy and " (Busy; the grid's lots may cap it)" or "", math.floor((sheet.baselineS or 0) / 60),
		math.floor(bench.CITY_AFTER_S / 60), c.swap and "swapped (the other city of each pair is auto)" or "as usual")
end

--- The cities on a w x h map (offsets from the map centre): with controls, pairs in columns, the auto city on the first
--- row (y < 0) in odd columns and on the second in even ones (positions balanced; Swap roles: the other way round);
--- without, one row of auto cities. nil and why when they do not fit.
function bench.cityPlan(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet) : SquareStressBenchCityPlan, string
	local c = sheet.city
	local half = logic.gridHalfOfSize(c.size)
	local L = gridStreets.layout(half, c.layout or "plain", 1, bench.CITY_BLOCK)
	local per = L.crossings
	local rows = c.control and 2 or 1
	local cols = c.pairs
	local x0 = -(cols - 1) * c.spacing / 2
	local y0 = -(rows - 1) * c.spacing / 2
	local reach = half + 60.0   -- the ring's corner stubs
	if -x0 + reach > w / 2 - mapMargin or -y0 + reach > h / 2 - mapMargin then
		return nil, string.format("%d cities %.0f m apart need %.1f x %.1f km", cols * rows, c.spacing, 2 * (-x0 + reach + mapMargin) / 1000,
			2 * (-y0 + reach + mapMargin) / 1000)
	end
	local out : SquareStressBenchCityPlan = { cities = {}, auto = 0, control = 0, crossings = 0, enrolled = 0, persons = 0, half = half,
		layout = L.name, neck = L.neck, holes = #L.holes, x4 = L.x4, t3 = L.t3, swap = c.swap == true, busy = c.busy == true }
	for col = 1, cols do
		for row = 1, rows do
			local auto = (not c.control) or (((row == 1) == (col % 2 == 1)) ~= (c.swap == true))
			local role = auto and "auto" or "control"
			local x, y = x0 + (col - 1) * c.spacing, y0 + (row - 1) * c.spacing
			out.cities[#out.cities + 1] = { id = string.format("cityg%d%s", col, bench.CITY_ZONE_LETTER[role]), pair = string.format("cityg%d", col),
				role = role, ab = bench.CITY_AB[role], x = x == 0 and 0.0 or x, y = y == 0 and 0.0 or y,
				name = string.format("City %s %d", role, col), half = half, pop = c.pop, crossings = per, layout = L.name }
			out.crossings = out.crossings + per
			if auto then
				out.auto = out.auto + 1
				out.enrolled = out.enrolled + per
			else
				out.control = out.control + 1
			end
			out.persons = out.persons + c.pop
		end
	end
	return out, nil
end

--- The inner crossings of a city's grid among street nodes {id, x, y, streets} (absolute positions): every node with at
--- least minDeg streets (default 4; the funnel layouts 3: their T at the neck / a hole's edge) within CITY_SNAP of an
--- inner grid point, as {id, x, y, streets} sorted by id. The ring's T-junctions and the town's own nodes between the
--- grid points are left out.
function bench.cityInterior(nodes : {{number}}, cx : number, cy : number, half : number, minDeg? : integer) : {{number}}
	local lines, step = bench.cityLines(half)
	local lo, hi = lines[1], lines[#lines]
	local out : {{number}} = {}
	if lo == nil then return out end
	local snap = bench.CITY_SNAP
	for _, n in ipairs(nodes or {}) do
		local dx, dy, deg = n[2] - cx, n[3] - cy, n[4] or 0
		if deg >= (minDeg or 4) and dx >= lo - snap and dx <= hi + snap and dy >= lo - snap and dy <= hi + snap then
			local kx = math.floor((dx - lo) / step + 0.5)
			local ky = math.floor((dy - lo) / step + 0.5)
			if math.abs(dx - (lo + kx * step)) <= snap and math.abs(dy - (lo + ky * step)) <= snap then
				out[#out + 1] = { n[1], n[2], n[3], deg }
			end
		end
	end
	table.sort(out, function(a : {number}, b : {number}) : boolean return a[1] < b[1] end)
	return out
end

--- SmartLanes.auto add payloads for {node, x, y} entries: CITY_EVENT_MAX nodes each, src "stress".
function bench.cityPayloads(entries : {{number}}) : {{string : any}}
	local out : {{string : any}} = {}
	local i = 1
	while i <= #entries do
		local part : {{number}} = {}
		for j = i, math.min(i + bench.CITY_EVENT_MAX - 1, #entries) do
			local e = entries[j]
			part[#part + 1] = { math.floor(e[1]), e[2], e[3] }
		end
		out[#out + 1] = { op = "add", nodes = part, src = "stress" }
		i = i + bench.CITY_EVENT_MAX
	end
	return out
end

--- A city's traffic log zone: the whole grid (r = half: the measured circle reaches r + 200 m, past the ring's corners).
function bench.cityZone(c : SquareStressBenchCity) : SquareStressShowcaseZone
	return { id = c.id, pair = c.pair, ab = c.ab, kind = "city", label = c.name, x = c.x, y = c.y, r = c.half, towns = 1,
		built = false } as SquareStressShowcaseZone
end

--- "[SQST] CITY id= pair= role= town= name= x= y= half= crossings= found= lit_before= forced= refused=" (one per city
--- after its lights; x, y absolute).
--- extra (v2): " layout= neck_streets= holes= found4= found3= lit4= lit3= pop= gap_streets= gap_removed=" appended.
function bench.cityLine(c : SquareStressBenchCity, x : number, y : number, town : integer, found : integer, litBefore : integer,
		forced : integer, refused : integer, extra? : SquareStressCityLineExtra) : string
	local s = string.format("[SQST] CITY id=%s pair=%s role=%s town=%s name=%s x=%.0f y=%.0f half=%.0f crossings=%d found=%d lit_before=%d forced=%d refused=%d",
		c.id, c.pair, c.role, town ~= nil and tostring(town) or "-", (c.name:gsub("%s+", "_")), x, y, c.half, c.crossings, found, litBefore,
		forced, refused)
	if extra ~= nil then
		local e = extra
		s = s .. string.format(" layout=%s neck_streets=%d holes=%d found4=%d found3=%d lit4=%d lit3=%d pop=%s gap_streets=%d gap_removed=%d",
			e.layout or "plain", e.neck or 0, e.holes or 0, e.found4 or 0, e.found3 or 0, e.lit4 or 0, e.lit3 or 0,
			e.pop ~= nil and tostring(math.floor(e.pop)) or "-", e.gapStreets or 0, e.gapRemoved or 0)
	end
	return s
end

--- "[SQST] CITY_GAPS id= pair= role= at=<label> layout= gap_streets= removed=": streets found in a city's layout gaps
--- (after the lock: removed; at the run's end: counted only).
function bench.cityGapLine(c : SquareStressBenchCity, label : string, found : integer, removed : integer) : string
	return string.format("[SQST] CITY_GAPS id=%s pair=%s role=%s at=%s layout=%s gap_streets=%d removed=%d", c.id, c.pair, c.role, label,
		c.layout or "plain", found, removed)
end

--- "[SQST] CITY_ENROLL run= op=add|all cities= nodes= events= baseline_s= by=bench smart_lanes=" (the report's before /
--- after split).
function bench.cityEnrollLine(run : string, op : string, cities : integer, nodes : integer, events : integer, baselineS : number,
		sl : boolean, sheet? : SquareStressBenchSheet) : string
	local s = string.format("[SQST] CITY_ENROLL run=%s op=%s cities=%d nodes=%d events=%d baseline_s=%d by=bench smart_lanes=%s", run or "-", op,
		cities, nodes, events, math.floor(baselineS), sl and "yes" or "no")
	if sheet ~= nil and sheet.city ~= nil then
		local c = sheet.city
		s = s .. string.format(" layout=%s busy=%d role_swap=%d", c.layout or "plain", c.busy and 1 or 0, c.swap and 1 or 0)
	end
	return s
end

--- The window's plan line for the city run.
function bench.cityPlanText(p : SquareStressBenchCityPlan, why : string, w : number, h : number) : string
	if p == nil then return string.format("does not fit this %.1f x %.1f km map (%s)", w / 1000, h / 1000, why or "?") end
	local layout = ""
	if p.layout == "hourglass" then layout = string.format(", hourglass with a %d-street neck", p.neck or 0)
	elseif p.layout == "holes" then layout = string.format(", %d holes each", p.holes or 0) end
	return string.format("%d grid cities (%d auto, %d control%s%s), %d inner crossings lit (%d enrolled), ~%dk people; %.1f x %.1f km map",
		#p.cities, p.auto, p.control, p.swap and ", roles swapped" or "", layout, p.crossings, p.enrolled, math.floor(p.persons / 1000 + 0.5),
		w / 1000, h / 1000)
end

---------------------------------------------------------------------------
-- Footprints

local type Foot = SquareStressBenchFoot
local type Shape = SquareStressBenchShape

local function townClear() : number
	return logic.TOWN_SIZES[bench.SIZE].spacing * logic.SHOWCASE_TOWN_R + logic.SHOWCASE_GAP
end

--- The shape of variant v with towns on the arms whose compass point is in sides (rotation 0, towns on the axes
--- at one distance: showcaseTownDists, the farthest, rounded up, as the Lights showcase's square layout). nil and
--- why when an arm with a town is not on an axis or a side has no arm.
function bench.shape(v : SquareStressShowcaseType, sides : {string}) : Shape, string
	local params : {string : number} = {}
	for k, x in pairs(v.fixed) do params[k] = x end
	local case_ : SquareStressJunctionCase = { id = v.id, label = v.label, file = v.file, params = params }
	local arms = logic.showcaseArms(case_)
	if arms == nil then return nil, "unknown arms" end
	local want : {string : boolean} = {}
	for _, s in ipairs(sides) do want[s] = true end
	local sh : Shape = { case_ = case_, reach = logic.showcaseReach(case_), degs = {}, offsets = {}, sides = {} }
	for _, d in ipairs(arms) do
		local side = logic.compassOf(d)
		if want[side] then
			if logic.axisUnit(d) == nil then return nil, string.format("arm %g deg is not on an axis", d) end
			sh.degs[#sh.degs + 1] = d
			sh.sides[#sh.sides + 1] = side
			want[side] = nil
		end
	end
	for s in pairs(want) do return nil, "no arm " .. s end
	local spacings : {number} = {}
	for i = 1, #sh.degs do spacings[i] = logic.TOWN_SIZES[bench.SIZE].spacing end
	local far = 0.0
	for _, d in ipairs(logic.showcaseTownDists(sh.reach, sh.degs, spacings, logic.SHOWCASE_TOWN_R)) do far = math.max(far, d) end
	sh.dist = math.ceil(far) + 0.0
	for i, d in ipairs(sh.degs) do
		local u = logic.axisUnit(d)
		sh.offsets[i] = { sh.dist * u[1] + 0.0, sh.dist * u[2] + 0.0 }
	end
	sh.sig = string.format("%s|%s", v.id, table.concat(sh.sides, ","))
	return sh, nil
end

local function footAt(sh : Shape, x : number, y : number) : Foot
	local f : Foot = { jx = x, jy = y, reach = sh.reach, towns = {}, x0 = x - sh.reach, x1 = x + sh.reach, y0 = y - sh.reach, y1 = y + sh.reach }
	for i, o in ipairs(sh.offsets) do
		local tx, ty = x + o[1], y + o[2]
		f.towns[i] = { tx, ty }
		f.x0, f.x1 = math.min(f.x0, tx), math.max(f.x1, tx)
		f.y0, f.y1 = math.min(f.y0, ty), math.max(f.y1, ty)
	end
	return f
end

local function segDist(px : number, py : number, ax : number, ay : number, bx : number, by : number) : number
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = 0.0
	if l2 > 0 then t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) end
	local qx, qy = ax + t * dx - px, ay + t * dy - py
	return math.sqrt(qx * qx + qy * qy)
end

local function orient(ax : number, ay : number, bx : number, by : number, cx : number, cy : number) : number
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

local function crosses(a : {number}, b : {number}, c : {number}, d : {number}) : boolean
	return orient(a[1], a[2], b[1], b[2], c[1], c[2]) * orient(a[1], a[2], b[1], b[2], d[1], d[2]) < 0
		and orient(c[1], c[2], d[1], d[2], a[1], a[2]) * orient(c[1], c[2], d[1], d[2], b[1], b[2]) < 0
end

--- Whether two groups' footprints clear each other (BENCH.md "Layout": town to town, junction to town, link to
--- town, link to junction, link to link).
function bench.clear(f : Foot, g : Foot) : boolean
	local tc = townClear()
	local tt = 2 * tc
	local function one(p : Foot, q : Foot) : boolean
		local pj = { p.jx, p.jy }
		for _, t in ipairs(p.towns) do
			for _, u in ipairs(q.towns) do
				if (t[1] - u[1]) ^ 2 + (t[2] - u[2]) ^ 2 < tt * tt then return false end
			end
			local rj = q.reach + tc
			if (t[1] - q.jx) ^ 2 + (t[2] - q.jy) ^ 2 < rj * rj then return false end
			-- p's link to t against q's towns and junction
			for _, u in ipairs(q.towns) do
				if segDist(u[1], u[2], p.jx, p.jy, t[1], t[2]) < bench.LINK_TOWN then return false end
			end
			if segDist(q.jx, q.jy, p.jx, p.jy, t[1], t[2]) < q.reach + bench.LINK_JUNCTION then return false end
			for _, u in ipairs(q.towns) do
				local qj = { q.jx, q.jy }
				if crosses(pj, t, qj, u) then return false end
				local d = math.min(segDist(pj[1], pj[2], qj[1], qj[2], u[1], u[2]), segDist(t[1], t[2], qj[1], qj[2], u[1], u[2]),
					segDist(qj[1], qj[2], pj[1], pj[2], t[1], t[2]), segDist(u[1], u[2], pj[1], pj[2], t[1], t[2]))
				if d < bench.LINK_LINK then return false end
			end
		end
		return true
	end
	return one(f, g) and one(g, f)
end

---------------------------------------------------------------------------
-- The packer

local record Packer
	left : number
	right : number
	bottom : number
	top : number
	placed : {Foot}
	buckets : {integer : {integer}}
	cursor : {string : {number}}   -- shape signature -> the {x, y} of its last spot (every spot before it is taken for it)
end

local function bucketKey(cx : integer, cy : integer) : integer
	return (cx + 5000) * 10007 + (cy + 5000)
end

local function margin() : number
	return 2 * townClear() + 100
end

local function addFoot(pk : Packer, f : Foot)
	pk.placed[#pk.placed + 1] = f
	local m = margin()
	local c = bench.BUCKET
	for cx = math.floor((f.x0 - m) / c), math.floor((f.x1 + m) / c) do
		for cy = math.floor((f.y0 - m) / c), math.floor((f.y1 + m) / c) do
			local k = bucketKey(cx, cy)
			local b = pk.buckets[k]
			if b == nil then b = {} pk.buckets[k] = b end
			b[#b + 1] = #pk.placed
		end
	end
end

local function fits(pk : Packer, f : Foot, extra : {Foot}) : boolean
	for _, t in ipairs(f.towns) do
		if t[1] < pk.left or t[1] > pk.right or t[2] < pk.bottom or t[2] > pk.top then return false end
	end
	if f.jx - f.reach < pk.left or f.jx + f.reach > pk.right or f.jy - f.reach < pk.bottom or f.jy + f.reach > pk.top then return false end
	local c = bench.BUCKET
	local seen : {integer : boolean} = {}
	for cx = math.floor(f.x0 / c), math.floor(f.x1 / c) do
		for cy = math.floor(f.y0 / c), math.floor(f.y1 / c) do
			for _, i in ipairs(pk.buckets[bucketKey(cx, cy)] or {}) do
				if not seen[i] then
					seen[i] = true
					if not bench.clear(f, pk.placed[i]) then return false end
				end
			end
		end
	end
	for _, g in ipairs(extra) do
		if not bench.clear(f, g) then return false end
	end
	return true
end

--- The first spot (rows top to bottom, STEP apart, left to right) for shape sh, from its cursor on.
local function findSpot(pk : Packer, sh : Shape, extra : {Foot}) : Foot
	local cur = pk.cursor[sh.sig]
	local y = cur ~= nil and cur[2] or pk.top
	local x = cur ~= nil and cur[1] or pk.left
	while y >= pk.bottom do
		while x <= pk.right do
			local f = footAt(sh, x, y)
			if fits(pk, f, extra) then
				pk.cursor[sh.sig] = { x, y }
				return f
			end
			x = x + bench.STEP
		end
		x = pk.left
		y = y - bench.STEP
	end
	pk.cursor[sh.sig] = { pk.right + 1, pk.bottom - 1 }
	return nil
end

--- The bench layout of a sheet on a w x h map (offsets from the map centre, town centres and junctions at least
--- `mapMargin` inside): every test in turn, each set whole or not at all (a set that does not fit ends its test;
--- later tests fill what is left), each set's twins one after another in the order rotated by the set (so every
--- twin mode is placed first equally often). Groups and towns as showcaseLayout makes them (Lights showcase names:
--- "<mode> <set> <side>"), with the bench fields (test, variant, litYes, linkLanes, pairLanes). The plan's per-test
--- counts and the estimates come with it.
local memoKey : string = nil
local memoPlan : SquareStressBenchPlan = nil

local function planKey(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet, seed : integer) : string
	-- no seed: the layout does not depend on it (only its seed field, set on every call)
	local parts : {string} = { sheet.id, tostring(w), tostring(h), tostring(mapMargin), tostring(bench.STEP) }
	for _, t in ipairs(sheet.tests) do parts[#parts + 1] = t.id .. ":" .. tostring(t.sets) .. ":" .. tostring(#t.variants) .. ":" .. tostring(#t.twins) end
	return table.concat(parts, "|")
end

function bench.plan(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet, seed? : integer) : SquareStressBenchPlan
	-- the same sheet on the same map again (the window's plan line, then the build): the last plan (it takes ~1 s)
	local key = planKey(w, h, mapMargin, sheet, seed)
	if key == memoKey and memoPlan ~= nil then
		memoPlan.layout.seed = seed or 0
		return memoPlan
	end
	local out : SquareStressBenchPlan = { sheet = sheet, tests = {}, groups = 0, towns = 0, cut = {}, problems = {},
		layout = { seed = seed or 0, towns = {}, groups = {}, square = true, idPrefix = sheet.key } }
	local pk : Packer = { left = -w / 2 + mapMargin, right = w / 2 - mapMargin, bottom = -h / 2 + mapMargin, top = h / 2 - mapMargin,
		placed = {}, buckets = {}, cursor = {} }
	local L = out.layout
	local set = 0
	-- per test: its plan row, shapes (one per variant) and twin modes
	local ctx : {{any}} = {}
	for ti, t in ipairs(sheet.tests) do
		local tp : SquareStressBenchTestPlan = { test = t, wanted = t.sets, sets = 0, groups = 0, towns = 0 }
		out.tests[#out.tests + 1] = tp
		local shapes : {Shape} = {}
		for i, v in ipairs(t.variants) do
			local sh, why = bench.shape(v, t.towns)
			if sh == nil then out.problems[#out.problems + 1] = string.format("%s variant %d: %s", t.id, i, why) else shapes[i] = sh end
		end
		local modes : {SquareStressShowcaseAb} = {}
		for i, tw in ipairs(t.twins) do modes[i] = bench.twinMode(tw) end
		ctx[ti] = { tp, shapes, modes, not (#shapes == #t.variants and #shapes > 0) }
	end
	local persons = 0.0
	--- Set k of test ti: every twin placed (whole) or nothing; false when it does not fit (the test is done then).
	local function placeSet(ti : integer, k : integer) : boolean
		local t = sheet.tests[ti]
		local tp = ctx[ti][1] as SquareStressBenchTestPlan
		local shapes = ctx[ti][2] as {Shape}
		local modes = ctx[ti][3] as {SquareStressShowcaseAb}
		local vi = (k - 1) % #t.variants + 1
		local sh, v = shapes[vi], t.variants[vi]
		local feet : {Foot} = {}
		local order : {integer} = {}
		local saved : {string : {number}} = {}
		for sig, c in pairs(pk.cursor) do saved[sig] = c end
		local n = #modes
		for j = 1, n do order[j] = (j - 1 + k - 1) % n + 1 end
		-- a twin on a named geometry (t.geoms) takes that variant, every other twin the set's
		local function shapeOf(m : SquareStressShowcaseAb) : Shape, SquareStressShowcaseType
			local gi = m ~= nil and m.geom ~= nil and t.geoms ~= nil and t.geoms[m.geom] or nil
			if gi ~= nil and shapes[gi] ~= nil then return shapes[gi], t.variants[gi] end
			return sh, v
		end
		for j = 1, n do
			local f = findSpot(pk, (shapeOf(modes[order[j]])), feet)
			if f == nil then
				pk.cursor = saved
				out.cut[#out.cut + 1] = string.format("%s: %d of %d sets", t.id, tp.sets, t.sets)
				return false
			end
			feet[j] = f
		end
		set = set + 1
		tp.sets = tp.sets + 1
		for j = 1, n do
			local f = feet[j]
			addFoot(pk, f)
			local m = modes[order[j]]
			local tsh, tv = shapeOf(m)
			-- a test with traffic mixes (Sheet 5): the set's mix, every twin alike
			local mix = bench.setMix(t, tp.sets)
			local g : SquareStressShowcaseGroup = { name = string.format("Group %d%s", set, m.twin), kind = tv.kind, slot = t.id,
				place = { case_ = tsh.case_, x = f.jx + 0.0, y = f.jy + 0.0, angle = 0.0, reach = tsh.reach, lightsOff = false },
				towns = {}, oneWay = {}, R = tsh.dist + townClear(), set = set, twin = m.twin, ab = m.ab, test = t.id, variant = tv.label,
				litYes = t.litYes == true, linkLanes = t.linkLanes, pairLanes = t.pairLanes, geom = m.geom, mix = mix,
				ringMix = t.ringMix == true or nil }
			for i, tw in ipairs(f.towns) do
				local tix = #L.towns + 1
				local pop, word : number, string = nil, nil
				if mix ~= nil then pop, word = bench.mixPop(mix, tsh.sides[i], t.pops) end
				L.towns[tix] = { x = tw[1] + 0.0, y = tw[2] + 0.0, row = 1, col = tix, size = bench.SIZE,
					name = logic.showcaseTownName(tv, m, set, tsh.sides[i], true, word), pop = pop }
				-- a town wanted below a Medium town's initial capacity is created with that capacity (as the light plans A/B)
				local caps = logic.TOWN_SIZES[bench.SIZE].caps
				if pop ~= nil and pop < caps then L.towns[tix].townCaps = math.floor(pop) end
				persons = persons + bench.PERSONS_PER_TOWN * (pop or sheet.pop or bench.POP) / bench.POP
				g.towns[i] = tix
			end
			L.groups[#L.groups + 1] = g
			tp.groups = tp.groups + 1
			tp.towns = tp.towns + #f.towns
		end
		return true
	end
	if sheet.roundRobin then
		-- one set of every test in turn (the micro bench: every test gets its first set before any its second)
		local most = 0
		for _, t in ipairs(sheet.tests) do most = math.max(most, t.sets) end
		for k = 1, most do
			for ti, t in ipairs(sheet.tests) do
				if not ctx[ti][4] and k <= t.sets and not placeSet(ti, k) then ctx[ti][4] = true end
			end
		end
	else
		for ti, t in ipairs(sheet.tests) do
			for k = 1, t.sets do
				if ctx[ti][4] or not placeSet(ti, k) then break end
			end
		end
	end
	for _, c in ipairs(ctx) do
		local tp = c[1] as SquareStressBenchTestPlan
		out.groups = out.groups + tp.groups
		out.towns = out.towns + tp.towns
	end
	out.persons = math.floor(persons + 0.5)
	out.drivers = math.floor(out.persons * bench.DRIVER_SHARE)
	out.buildMin = math.floor(out.towns * bench.BUILD_S_PER_TOWN / 6 + 0.5) / 10
	memoKey, memoPlan = key, out
	return out
end

---------------------------------------------------------------------------
-- The build spec and the log lines

--- The modes of a sheet (every test's twins, each once, in first-use order).
function bench.modes(sheet : SquareStressBenchSheet) : {SquareStressShowcaseAb}
	local out : {SquareStressShowcaseAb} = {}
	local seen : {string : boolean} = {}
	for _, t in ipairs(sheet.tests) do
		for _, tw in ipairs(t.twins) do
			-- "<ab>@<geom>" twins count as their Smart Lanes mode
			local ab = tw:match("^([%w_]+)@") or tw
			if not seen[ab] then
				seen[ab] = true
				out[#out + 1] = bench.AB[ab]
			end
		end
	end
	return out
end

--- The zone ab names a sheet needs from Smart Lanes beyond game and sl.
function bench.needs(sheet : SquareStressBenchSheet) : {string}
	-- the city run: the automatic re-timing (a Smart Lanes whose zones know sl_auto has SmartLanes.auto: rev 8)
	if sheet.city ~= nil then return { "sl_auto" } end
	local out : {string} = {}
	for _, m in ipairs(bench.modes(sheet)) do
		if m.ab ~= "game" and m.ab ~= "sl" then out[#out + 1] = m.ab end
	end
	return out
end

--- The Showcase spec of a sheet: the Lights showcase's town, entry, lock and growth settings, one kind slot per
--- test (its variants as types), every link at its arm's own lanes (BENCH.md "A confound in runs 5 and 6"), and
--- layoutFn giving the bench layout for the map.
function bench.spec(sheet : SquareStressBenchSheet) : SquareStressShowcaseSpec
	local kinds : {string} = {}
	local types : {string : {SquareStressShowcaseType}} = {}
	local kindLog : {string : string} = {}
	local kindWords : {string : string} = {}
	for _, t in ipairs(sheet.tests) do
		kinds[#kinds + 1] = t.id
		types[t.id] = t.variants
		kindLog[t.id] = t.id
		kindWords[t.id] = t.title
	end
	return {
		id = sheet.id, title = sheet.title, kinds = kinds, types = types, kindLog = kindLog, kindWords = kindWords,
		modes = bench.modes(sheet), size = bench.SIZE, misses = 1, litOnly = false,
		-- the fallback factor (a town whose capacity can't be read): the sheet's people over a Medium town's capacity (x1 for
		-- 400, x2 for the micro bench's 800)
		growFactor = logic.growFactorForCap(sheet.pop or bench.POP, logic.TOWN_SIZES[bench.SIZE].caps) or logic.LIGHTS_GROW_FACTOR,
		growTarget = sheet.pop or bench.POP, growPasses = 1, lockStreets = true, denseWeights = logic.DENSE_WEIGHTS,
		square = true, noBusLines = true, modeNames = true, entries = true, linkLanes = nil, bench = true,
		layoutFn = function(w : number, h : number, mapMargin : number, seed : integer) : SquareStressShowcaseLayout
			return bench.plan(w, h, mapMargin, sheet, seed).layout
		end,
	} as SquareStressShowcaseSpec
end

local function pairsText(list : {{string}}) : string
	local parts : {string} = {}
	for i, p in ipairs(list or {}) do parts[i] = p[1] .. ":" .. p[2] end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- "[SQST] BENCH_TEST sheet= id= ..." (BENCH.md "Log contract additions"), one per test.
function bench.testLine(sheet : SquareStressBenchSheet, tp : SquareStressBenchTestPlan) : string
	local t = tp.test
	local labels : {string} = {}
	for i, v in ipairs(t.variants) do labels[i] = (v.label:gsub("[%s,]+", "_")) end
	local s = string.format("[SQST] BENCH_TEST sheet=%s id=%s title=%s kind=%s variants=%s twins=%s compare=%s sets=%d/%d groups=%d towns=%d towns_per_twin=%d pop=%d lights=%s",
		sheet.key, t.id, (t.title:gsub("%s+", "_")), t.variants[1] ~= nil and t.variants[1].kind or "-", table.concat(labels, ","),
		table.concat(t.twins, ","), pairsText(t.compare), tp.sets, tp.wanted, tp.groups, tp.towns, #t.towns, math.floor(sheet.pop or bench.POP),
		t.litYes and "yes" or "game")
	-- keys only added: the traffic mixes in set order and their town sizes, the ring mix log (Sheet 5)
	if t.mixes ~= nil and #t.mixes > 0 then
		local pops = t.pops or bench.LU_POPS
		s = s .. string.format(" mixes=%s pops=large:%d,small:%d,even:%d", table.concat(t.mixes, ","), math.floor(pops.large),
			math.floor(pops.small), math.floor(pops.even))
	end
	if t.ringMix then s = s .. " ring_mix=yes" end
	return s
end

--- The window's plan line: "39 junctions, 132 towns (~53k people), about 11 min to build; 16.0 km map: everything fits".
function bench.planText(p : SquareStressBenchPlan, w : number, h : number) : string
	local cut = #p.cut > 0 and ("; cut: " .. table.concat(p.cut, ", ")) or ": everything fits"
	return string.format("%d junctions, %d towns (~%dk people), about %g min to build; %.1f x %.1f km map%s", p.groups, p.towns,
		math.floor(p.persons / 1000 + 0.5), p.buildMin, w / 1000, h / 1000, cut)
end

---------------------------------------------------------------------------
-- The run (gui/stress_bench_run.tl's pure helpers)

bench.YEAR = 1950            -- the game's automatic traffic lights start this year (traffic_light_config.res.lua)
bench.WARMUP_S = 180         -- game s before the record (flow_report drops --warmup 180 per zone anyway)
bench.RECORD_S = 1200        -- game s recorded (20 game minutes)
bench.INTERVAL = 1           -- the traffic log's interval index: 10 game s (positional thru: every car seen on its approach)
bench.SPEED = 2              -- the game speed while recording (a sweep of ~25k drivers fits a 10 s interval at 2x)
bench.SL_KEYS = { auto = "sqrl_auto", lights = "sqrl_lights", freeTurn = "sqrl_free_turn", phases = "sqrl_light_phases", perf = "sqperf_log" }

--- A sheet's record length (game s) and game speed (its own when it sets them: Sheet 6, the city run; else RECORD_S, SPEED).
function bench.recordS(sheet : SquareStressBenchSheet) : integer
	return math.floor(sheet.recordS or bench.RECORD_S)
end
function bench.speed(sheet : SquareStressBenchSheet) : integer
	return math.floor(sheet.speed or bench.SPEED)
end

--- Smart Lanes' settings from its raw mod params (1-based option indices; anything else its default, as its own
--- sl_rules.fromModParams): auto / lights booleans, freeTurn "off" | "safe" | "always", phases "game" | "sl".
function bench.slSettings(raw : {string : any}) : SquareStressBenchSl
	local function pick(key : string, n : integer, default : integer) : integer
		local i = tonumber(raw ~= nil and raw[key] or nil)
		if i == nil or i < 1 or i > n or i ~= math.floor(i) then return default end
		return math.floor(i)
	end
	return {
		auto = pick(bench.SL_KEYS.auto, 2, 1) == 1,
		lights = pick(bench.SL_KEYS.lights, 2, 1) == 1,
		freeTurn = ({ "off", "safe", "always" })[pick(bench.SL_KEYS.freeTurn, 3, 3)],
		phases = ({ "game", "sl" })[pick(bench.SL_KEYS.phases, 2, 1)],
		-- its "Debug: performance log" (SQPERF level 3: the 30 s window lines the city run's frame-time check reads; the DEV
		-- master switch square_sqperf_all counts too: info.perfAll)
		perf = pick(bench.SL_KEYS.perf, 2, 1) == 2,
	}
end

--- What stops a sheet from running (empty: nothing). info: the preflight's reads.
function bench.problems(sheet : SquareStressBenchSheet, info : SquareStressBenchInfo) : {string}
	local out : {string} = {}
	if info.busy ~= nil then out[#out + 1] = "A test is still queued or running (" .. info.busy .. "). Wait for it to finish." end
	if info.paused then out[#out + 1] = "The game is paused: unpause it (any speed) and press again." end
	if sheet.city ~= nil then
		-- the city run: its cities fit, Smart Lanes with the automatic re-timing (zone mode sl_auto: rev 8), its SQPERF windows
		if info.cityPlan == nil then
			out[#out + 1] = string.format("The cities do not fit this map (%s). Use a %g km map.", info.cityWhy or "?", sheet.minKm)
		end
		if not info.slPresent then
			out[#out + 1] = "Smart Lanes is not enabled: nothing would re-time the lights."
			return out
		end
		local sl = info.sl
		if sl ~= nil and not sl.perf and not info.perfAll then
			out[#out + 1] = "Smart Lanes' \"Debug: performance log\" is Off: turn it On (mod settings) or enable DEV SQPERF: all mods, so the log gets its frame times."
		end
		local have = false
		for _, m in ipairs(info.slModes or {}) do
			if m == "sl_auto" then have = true end
		end
		if info.slModes ~= nil and not have then
			out[#out + 1] = "This Smart Lanes has no automatic re-timing (zone mode sl_auto, rev 8): update Smart Lanes."
		end
		return out
	end
	if info.plan == nil or info.plan.groups == 0 then
		out[#out + 1] = string.format("Nothing fits this map (%.1f x %.1f km). The bench needs a %g km map.", (info.w or 0) / 1000,
			(info.h or 0) / 1000, sheet.minKm)
	end
	if info.needsRb and not info.rbOk then
		out[#out + 1] = "Roundabouts & Interchanges is not enabled (this sheet builds its roundabouts / interchanges)."
	end
	if not info.slPresent then
		out[#out + 1] = "Smart Lanes is not enabled: the twins would all be the game's."
	else
		local sl = info.sl
		if sl ~= nil and not sl.auto then out[#out + 1] = "Smart Lanes' \"Apply automatically to new roads\" is Off: turn it On (mod settings)." end
		if sl ~= nil and sheet.slLights and not sl.lights then
			out[#out + 1] = "Smart Lanes' \"No lights at roundabouts and ramps\" is Off: this sheet compares it On against kept lights; turn it On."
		end
		local missing : {string} = {}
		local have : {string : boolean} = {}
		for _, m in ipairs(info.slModes or {}) do have[m] = true end
		for _, m in ipairs(bench.needs(sheet)) do
			if info.slModes == nil or not have[m] then missing[#missing + 1] = m end
		end
		if #missing > 0 then
			out[#out + 1] = string.format("This Smart Lanes does not know the zone mode%s %s (update Smart Lanes)%s.", #missing == 1 and "" or "s",
				table.concat(missing, ", "), info.slModes == nil and ": it reported no modes" or "")
		end
	end
	return out
end

--- "[SQST] BENCH_START sheet= spec= seed= map= tests= groups= towns= year= sl_auto= sl_lights= sl_free_turn= sl_phases= sl_modes="
function bench.startLine(sheet : SquareStressBenchSheet, info : SquareStressBenchInfo, seed : integer) : string
	local sl = info.sl or {} as SquareStressBenchSl
	local p = info.plan
	if sheet.city ~= nil then
		local cp = info.cityPlan
		local n = cp ~= nil and #cp.cities or 0
		return string.format("[SQST] BENCH_START sheet=%s spec=%s@%d seed=%d map=%.0fx%.0f tests=0 groups=0 towns=%d year=%s sl_auto=%s sl_lights=%s sl_free_turn=%s sl_phases=%s sl_modes=%s warmup_s=%d record_s=%d interval_s=%d speed=%d pop=%d pool=no rank=no city=yes cities=%d auto=%d control=%d crossings=%d enrolled=%d baseline_s=%d sl_perf=%s",
			sheet.key, sheet.id, sheet.version, seed, info.w or 0, info.h or 0, n, info.year ~= nil and tostring(info.year) or "?",
			sl.auto and "on" or "off", sl.lights and "on" or "off", sl.freeTurn or "-", sl.phases or "-",
			info.slModes ~= nil and table.concat(info.slModes, ",") or "-", bench.WARMUP_S, bench.recordS(sheet), 10, bench.speed(sheet),
			math.floor(sheet.city.pop), n, cp ~= nil and cp.auto or 0, cp ~= nil and cp.control or 0, cp ~= nil and cp.crossings or 0,
			cp ~= nil and cp.enrolled or 0, math.floor(sheet.baselineS or 0), (sl.perf or info.perfAll) and "on" or "off")
			.. string.format(" layout=%s busy=%d role_swap=%d", sheet.city.layout or "plain", sheet.city.busy and 1 or 0, sheet.city.swap and 1 or 0)
	end
	return string.format("[SQST] BENCH_START sheet=%s spec=%s@%d seed=%d map=%.0fx%.0f tests=%d groups=%d towns=%d year=%s sl_auto=%s sl_lights=%s sl_free_turn=%s sl_phases=%s sl_modes=%s warmup_s=%d record_s=%d interval_s=%d speed=%d pop=%d pool=%s rank=%s",
		sheet.key, sheet.id, sheet.version, seed, info.w or 0, info.h or 0, #sheet.tests, p ~= nil and p.groups or 0, p ~= nil and p.towns or 0,
		info.year ~= nil and tostring(info.year) or "?", sl.auto and "on" or "off", sl.lights and "on" or "off", sl.freeTurn or "-",
		sl.phases or "-", info.slModes ~= nil and table.concat(info.slModes, ",") or "-", bench.WARMUP_S, bench.recordS(sheet), 10, bench.speed(sheet),
		math.floor(sheet.pop or bench.POP), sheet.pool and "yes" or "no", sheet.rank and "yes" or "no")
end

return bench
