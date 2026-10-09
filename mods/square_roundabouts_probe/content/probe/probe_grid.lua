-- DEV ONLY (never upload): Roundabouts placement probe, combination grid and log line format.
-- Pure Lua (no api.*), unit-tested in tests/square_roundabouts_probe/. Runs in the game's
-- pre-5.3 Lua (no `//`, no 5.3 library calls).
--
-- Edit SUBSETS below to change what the probe asks the engine about. A subset is a list of
-- blocks; a block names the entry ("main", "magic", "channel" or "interchange") and, per axis, a
-- list of value labels or
-- "*" (every value). Axes a block leaves out take the construction's default (same defaultIndex
-- as the .con.lua). Blocks expand to their cartesian product (last axis varies fastest);
-- duplicates across blocks are dropped.

local grid = {}

-- Axes in the order of their params in square_roundabouts.con.lua. `param` is the .con.lua key
-- (geom.PARAM_KEYS), `labels` name the values 1..n in the order of the .con.lua `values`,
-- `default` is the .con.lua defaultIndex. Exceptions, appended last so the replay keys of older
-- runs keep their positions: Magic's lanes axis (the .con.lua shows it after the arm road) and the
-- main entry's through road (Phase 5c; the .con.lua shows it after Through the centre). A key
-- with one value fewer means the default (1 lane / Same as arms).
-- `values` (optional): the param value per label instead of the index; `pseudo`: not a .con.lua
-- param (the interchange's year, read by its updateFn as params.year).
grid.MAIN_AXES = {
	{ key = "shape", param = "sqrb_shape", default = 1, labels = { "round", "oval1.25", "oval1.5", "oval1.75", "oval2" } },
	{ key = "lanes", param = "sqrb_lanes", default = 2, labels = { "1", "2", "4" } },
	{ key = "radius", param = "sqrb_radius", default = 5,
		labels = { "8", "10", "12", "15", "20", "25", "30", "35", "40", "45", "50", "55", "60" } },
	{ key = "arms", param = "sqrb_arms", default = 3, labels = { "T", "Y", "4", "5", "6", "none" } },
	{ key = "splitter", param = "sqrb_splitter", default = 1, labels = { "off", "on" } },
	{ key = "centre", param = "sqrb_centre", default = 1, labels = { "none", "road", "tram", "lights" } },
	{ key = "arm", param = "sqrb_arm_type", default = 1,
		labels = { "town_s", "town_m", "town_l", "country_s", "country_m", "country_l" } },
	{ key = "tram", param = "sqrb_tram", default = 1, labels = { "off", "on" } },
	{ key = "dir", param = "sqrb_direction", default = 1, labels = { "ccw", "cw" } },
	{ key = "island", param = "sqrb_island", default = 1, labels = { "none", "grass", "trees", "fountain", "paved" } },
	{ key = "signals", param = "sqrb_signals", default = 1, labels = { "off", "entries" } },
	-- "Through road" (Phase 5c): Same as arms, then the arm road list
	{ key = "through", param = "sqrb_through_road", default = 1,
		labels = { "same", "town_s", "town_m", "town_l", "country_s", "country_m", "country_l" } },
}

-- square_roundabouts_magic.con.lua
grid.MAGIC_AXES = {
	{ key = "size", param = "sqrb_magic_size", default = 3, labels = { "compact", "small", "medium", "large", "vlarge" } },
	{ key = "arm", param = "sqrb_arm_type", default = 1,
		labels = { "town_s", "town_m", "town_l", "country_s", "country_m", "country_l" } },
	{ key = "dir", param = "sqrb_direction", default = 1, labels = { "ccw", "cw" } },
	{ key = "island", param = "sqrb_island", default = 1, labels = { "none", "grass", "trees", "fountain", "paved" } },
	-- "Mini roundabout lanes" (satellite ring lanes). Last, so the replay keys of the older axes
	-- keep their positions: a 4-value key "g:size,arm,dir,island" (logs before this axis) = 1 lane.
	{ key = "lanes", param = "sqrb_magic_lanes", default = 1, labels = { "1", "2" } },
}

local ROADS = { "town_s", "town_m", "town_l", "country_s", "country_m", "country_l" }

-- square_roundabouts_channel.con.lua (Phase 5b), in .con.lua order
grid.CHANNEL_AXES = {
	{ key = "layout", param = "sqrb_ch_layout", default = 1, labels = { "T", "X" } },
	{ key = "main", param = "sqrb_ch_main", default = 2, labels = ROADS },
	{ key = "side", param = "sqrb_ch_side", default = 1, labels = ROADS },
	{ key = "slips", param = "sqrb_ch_slips", default = 1, labels = { "near", "main", "none" } },
	{ key = "splitter", param = "sqrb_ch_splitter", default = 1, labels = { "off", "on" } },
	{ key = "armlen", param = "sqrb_ch_arm_length", default = 1, labels = { "30", "40", "50", "60" } },
	{ key = "dir", param = "sqrb_direction", default = 1, labels = { "rht", "lht" } },
	{ key = "island", param = "sqrb_ch_island", default = 1, labels = { "none", "grass", "paved" } },
}

-- square_roundabouts_interchange.con.lua (Phase 5d), in .con.lua order, then the year (pseudo
-- axis: params.year picks the bridge, steel before 1970, concrete from 1970; ix.bridgeType)
grid.INTERCHANGE_AXES = {
	{ key = "layout", param = "sqrb_ix_layout", default = 1, labels = { "two_bridge", "dumbbell", "peanut" } },
	{ key = "highway", param = "sqrb_ix_highway", default = 2, labels = { "small", "medium", "large" } },
	{ key = "level", param = "sqrb_ix_level", default = 1, labels = { "ring_over", "hw_over" } },
	{ key = "lanes", param = "sqrb_lanes", default = 2, labels = { "1", "2", "4" } },
	{ key = "radius", param = "sqrb_ix_radius", default = 2,
		labels = { "15", "20", "25", "30", "35", "40", "45", "50", "55", "60" } },
	{ key = "cross", param = "sqrb_ix_cross", default = 2, labels = ROADS },
	{ key = "slip", param = "sqrb_ix_slip_length", default = 2, labels = { "120", "140", "160", "180" } },
	{ key = "armlen", param = "sqrb_ix_arm_length", default = 1, labels = { "30", "40", "50", "60" } },
	{ key = "dir", param = "sqrb_direction", default = 1, labels = { "rht", "lht" } },
	{ key = "island", param = "sqrb_island", default = 1, labels = { "none", "grass", "trees", "fountain", "paved" } },
	{ key = "year", param = "year", default = 2, labels = { "1969", "2020" }, values = { 1969, 2020 }, pseudo = true },
}

grid.ENTRIES = {
	main = {
		axes = grid.MAIN_AXES,
		file = "infrastructure/street_construction/square_roundabouts.con",
		tag = "m",
	},
	magic = {
		axes = grid.MAGIC_AXES,
		file = "infrastructure/street_construction/square_roundabouts_magic.con",
		tag = "g",
	},
	channel = {
		axes = grid.CHANNEL_AXES,
		file = "infrastructure/street_construction/square_roundabouts_channel.con",
		tag = "c",
	},
	interchange = {
		axes = grid.INTERCHANGE_AXES,
		file = "infrastructure/street_construction/square_roundabouts_interchange.con",
		tag = "x",
	},
}
-- Order the probe resolves the entries' constructions in (START line fields).
grid.ENTRY_ORDER = { "main", "magic", "channel", "interchange" }
grid.TARGET_MOD = "square_roundabouts"

-- Centre values of the Phase 3-4 subsets (Road + traffic lights, Phase 5c, has the Road geometry
-- and its own subsets: "*" would now include it).
local CENTRES = { "none", "road", "tram" }

-- The prioritised main grid (PROBE.md "Grid"): shape round / 2:1 oval, lanes 1/2/4, radius
-- min / default / mid / max, all arm layouts, splitter off/on, centre nothing/road/tram line,
-- all arm roads, tram off/on, anticlockwise; island None, signals Off.
local MAIN = {
	entry = "main",
	shape = { "round", "oval2" },
	lanes = "*",
	radius = { "8", "20", "40", "60" },
	arms = "*",
	splitter = "*",
	centre = CENTRES,
	arm = "*",
	tram = "*",
	dir = { "ccw" },
}
-- Clockwise sample: default ring, every arm layout x splitter x centre x arm road.
local MAIN_CW = {
	entry = "main",
	lanes = { "2" },
	radius = { "20" },
	arms = "*",
	splitter = "*",
	centre = CENTRES,
	arm = "*",
	dir = { "cw" },
}
local MAGIC = { entry = "magic", size = "*", arm = "*", dir = "*" }
-- The in-game failure that started this probe: 6 arms + splitter islands with wide arm roads.
local SPLITTER6 = {
	entry = "main",
	shape = { "round", "oval2" },
	lanes = "*",
	radius = { "8", "20", "40", "60" },
	arms = { "6" },
	splitter = { "on" },
	centre = CENTRES,
	arm = "*",
}

-- Search subsets (Phase 4) ---------------------------------------------------------------------
-- A block with `search = {kind = ...}` makes every combo a search job: the probe asks the engine
-- about a list of candidate dev overrides (square_roundabouts geom.DEV_KEYS, passed as extra
-- construction params) for the same base combo, one engine call per candidate, and logs a T line
-- per candidate and an S line per job. Kinds (grid.candidates):
--   radius         exact ring radius from the slider value up in RADIUS_STEP steps to RADIUS_MAX
--                  (plus the slider radii in between, RADIUS_EXTRA);
--                  stops at the first accepted radius (linear, not binary: the sweep shows
--                  failures are not monotonic in the radius, e.g. 1-lane rings fail at 40 m but
--                  not at 20 m)
--   magic_size     Magic: every size exactly (no growth); all candidates
--   magic_spacing  Magic: satellite radius fixed (block `fixed`), spacing from 2 x the satellite
--                  centreline radius up; stops at the first accepted spacing
--   splitter       leg template x fork x split distance x spread x neck, most compact first; all
--                  candidates (a rule must work across layouts, radii and lanes)
--   tram_stub      tram line: stub length beyond the ring half width; all candidates
--   grid           Phase 5e: the cartesian product of the block's `values` (dev override name ->
--                  list; `values.order` = names, the first varies slowest), shipped values first;
--                  all candidates
-- search fields: kind, first (stop at the first accepted; default per kind), fixed (list of dev
-- tables, each makes a separate job, e.g. an exact radius), values (replaces the kind's value
-- lists), requireRule ("splitter": skip jobs whose arm road has no splitter rule in the tuning
-- table yet). Block `exclude` = list of conditions ({axis = {labels}}, all must match) to drop.
grid.SEARCH = {
	RADIUS_STEP = 5,
	RADIUS_MAX = 120,
	-- slider radii between the 5 m steps (so the shipped radius is always among the candidates)
	RADIUS_EXTRA = { 12 },
	SPLIT = {
		legs = { 1, 2, 3 },          -- geom.DEV_LEGS: one-way xsmall, small, medium
		forks = { 35, 50, 65 },      -- degrees
		splits = { 20, 32, 45 },     -- m beyond the ring's outer edge
		spreads = { 6, 11 },         -- m beyond the leg half width
		necks = { 0, 15 },           -- m of the arm family's small two-way road before the split
	},
	SPLIT_QUICK = {
		legs = { 1, 2, 3 },
		forks = { 35, 50, 65 },
		splits = { 20, 32 },
		spreads = { 6 },
		necks = { 0, 15 },
	},
	TRAM_STUBS = { 6, 8, 10, 12, 16, 20, 24, 30 },
	MAGIC_SIZES = { 1, 2, 3, 4, 5 },
	-- 1-lane satellites: centreline = radius + square_roundabouts geom.RING_OFFSET[1] (magic_spacing
	-- assumes 1 lane; a 2-lane spacing search would need RING_OFFSET[2])
	MAGIC_OFFSET = 5,
	MAGIC_SPACING_FROM = 2.0,  -- x the satellite centreline radius
	MAGIC_SPACING_TO = 3.8,
}
grid.SEARCH_FIRST = { radius = true, magic_size = false, magic_spacing = true, splitter = false, tram_stub = false, grid = false }

-- Dev override params: must equal square_roundabouts geom.DEV_KEYS (a test checks). DEV_ORDER is
-- the log order of the dev* fields (grid.devField).
grid.DEV = {
	radius = "sqrb_dev_radius",
	magicSize = "sqrb_dev_magic_size",
	magicRadius = "sqrb_dev_magic_radius",
	magicDistance = "sqrb_dev_magic_distance",
	split = "sqrb_dev_split_length",
	fork = "sqrb_dev_fork",
	spread = "sqrb_dev_spread",
	leg = "sqrb_dev_leg",
	neck = "sqrb_dev_neck",
	neckType = "sqrb_dev_neck_type",
	tramStub = "sqrb_dev_tram_stub",
	-- Phase 5e: Channelized Junction / Roundabout Interchange tunables
	chSlipAngle = "sqrb_dev_ch_slip_angle",
	chCornerGap = "sqrb_dev_ch_corner_gap",
	chSlipFree = "sqrb_dev_ch_slip_free",
	ixClear = "sqrb_dev_ix_clear",
	ixGamma = "sqrb_dev_ix_gamma",
	ixGoreRun = "sqrb_dev_ix_gore_run",
	ixWaistGap = "sqrb_dev_ix_waist_gap",
	-- Phase 5f: the channel's slip lane template, the two-bridge ring's largest slip node angle
	chSlip = "sqrb_dev_ch_slip",
	ixAlphaMax = "sqrb_dev_ix_alpha_max",
}
grid.DEV_ORDER = { "radius", "magicSize", "magicRadius", "magicDistance", "split", "fork", "spread", "leg", "neck", "neckType", "tramStub",
	"chSlipAngle", "chCornerGap", "chSlipFree", "ixClear", "ixGamma", "ixGoreRun", "ixWaistGap", "chSlip", "ixAlphaMax" }

local MEDIUM_LARGE = { "town_m", "town_l", "country_m", "country_l" }
-- Radius search over the main grid. Left out: splitter on with medium/large arms (100% fail at
-- every radius in the sweep: that is the splitter search's job, then search_radius_split) and
-- splitter on with Arms None (no arm gets legs: same build as splitter off).
local S_RADIUS = {
	entry = "main",
	shape = { "round", "oval2" }, lanes = "*", radius = { "8", "20", "40", "60" }, arms = "*",
	splitter = "*", centre = CENTRES, arm = "*", tram = "*", dir = { "ccw" },
	exclude = { { splitter = { "on" }, arms = { "none" } }, { splitter = { "on" }, arm = MEDIUM_LARGE } },
	search = { kind = "radius" },
}
-- After a splitter rule is baked into the tuning table: the radius those arms need with it.
local S_RADIUS_SPLIT = {
	entry = "main",
	shape = { "round", "oval2" }, lanes = "*", radius = { "8", "20", "40", "60" },
	arms = { "T", "Y", "4", "5", "6" }, splitter = { "on" }, centre = CENTRES, arm = MEDIUM_LARGE, tram = "*", dir = { "ccw" },
	search = { kind = "radius", requireRule = "splitter" },
}
-- Tram line through the centre, clockwise at several radii (the sweep had CW only at 20 m).
local S_TRAM_CW = {
	entry = "main",
	shape = { "round", "oval2" }, lanes = "*", radius = { "8", "20", "40", "60" }, arms = "*",
	centre = { "tram" }, arm = { "town_s", "town_l" }, dir = { "cw" },
	search = { kind = "radius" },
}
-- Tram stub length at exact small radii (the tram line failed at 8-20 m, worked at 40-60 m).
local S_TRAM_STUB = {
	entry = "main",
	lanes = "*", arms = { "4" }, centre = { "tram" }, dir = "*",
	search = { kind = "tram_stub", fixed = { { radius = 10 }, { radius = 15 }, { radius = 20 }, { radius = 25 }, { radius = 30 } } },
}
local S_MAGIC_SIZE = { entry = "magic", arm = "*", dir = "*", search = { kind = "magic_size" } }
-- 2-lane satellites ("Mini roundabout lanes" 2): every arm road x direction, each size exactly.
-- gen_roundabouts_tuning.py writes these as the magic rows "armType,direction,2".
local S_MAGIC_SIZE2 = { entry = "magic", arm = "*", dir = "*", lanes = { "2" }, search = { kind = "magic_size" } }
local S_MAGIC_SPACING = {
	entry = "magic", arm = "*", dir = { "ccw" },
	search = { kind = "magic_spacing", fixed = {
		{ magicRadius = 8 }, { magicRadius = 10 }, { magicRadius = 12 }, { magicRadius = 15 }, { magicRadius = 20 }, { magicRadius = 25 },
	} },
}
-- Splitter parameters for medium/large arms at exact radii.
local S_SPLITTER = {
	entry = "main",
	lanes = "*", arms = { "T", "4", "6" }, splitter = { "on" }, arm = MEDIUM_LARGE,
	search = { kind = "splitter", fixed = { { radius = 20 }, { radius = 40 } } },
}
local S_SPLITTER_OVAL = {
	entry = "main",
	shape = { "oval2" }, lanes = { "2" }, arms = { "4" }, splitter = { "on" }, arm = MEDIUM_LARGE,
	search = { kind = "splitter", fixed = { { radius = 30 } } },
}
-- Quick versions (about 500 engine calls, well under 2 minutes).
local Q_RADIUS = {
	entry = "main",
	lanes = "*", radius = { "8", "20" }, arms = { "T", "4", "6" }, centre = CENTRES, arm = { "town_s", "town_l", "country_m" },
	search = { kind = "radius" },
}
local Q_TRAM_CW = {
	entry = "main", radius = { "8", "20", "40" }, centre = { "tram" }, dir = { "cw" }, search = { kind = "radius" },
}
local Q_TRAM_STUB = {
	entry = "main", arms = { "4" }, centre = { "tram" },
	search = { kind = "tram_stub", fixed = { { radius = 15 }, { radius = 20 } } },
}
local Q_MAGIC_SIZE = { entry = "magic", arm = "*", search = { kind = "magic_size" } }
local Q_MAGIC_SPACING = {
	entry = "magic", arm = { "town_s", "town_l" }, search = { kind = "magic_spacing", fixed = { { magicRadius = 12 } } },
}
local Q_SPLITTER = {
	entry = "main", splitter = { "on" }, arm = { "town_m", "town_l", "country_l" },
	search = { kind = "splitter", fixed = { { radius = 20 } }, values = grid.SEARCH.SPLIT_QUICK },
}

-- Phase 5e subsets (PROBE.md "Phase 5e runs") -------------------------------------------------
-- Hamburger / through-about (Phase 5c): Road and Road + traffic lights through the centre, every
-- through road other than the arm road, every arm layout and lane count, small sliders. Two arm
-- roads (town small, town large), so the through roads are both wider and narrower than the arms.
local OTHER_THAN_TOWN_S = { "town_m", "town_l", "country_s", "country_m", "country_l" }
local OTHER_THAN_TOWN_L = { "town_s", "town_m", "country_s", "country_m", "country_l" }
local HB_S = { entry = "main", lanes = "*", radius = { "8", "20" }, arms = "*", centre = { "road", "lights" },
	arm = { "town_s" }, through = OTHER_THAN_TOWN_S }
local HB_L = { entry = "main", lanes = "*", radius = { "8", "20" }, arms = "*", centre = { "road", "lights" },
	arm = { "town_l" }, through = OTHER_THAN_TOWN_L }
-- The same base combos as a radius search (Road only: the lights do not change the geometry); the
-- tuning generator reads them since Phase 5f (geom.patternKey appends the through road).
local HB_RADIUS_S = { entry = "main", lanes = "*", radius = { "8", "20" }, arms = "*", centre = { "road" },
	arm = { "town_s" }, through = OTHER_THAN_TOWN_S, search = { kind = "radius" } }
local HB_RADIUS_L = { entry = "main", lanes = "*", radius = { "8", "20" }, arms = "*", centre = { "road" },
	arm = { "town_l" }, through = OTHER_THAN_TOWN_L, search = { kind = "radius" } }

-- Channelized Junction (Phase 5b): the full grid of layout x main x side x slip lanes x splitter x
-- traffic side (islands None); paved islands (box colliders) on a sample; two more arm lengths.
local CH_ALL = { entry = "channel", layout = "*", main = "*", side = "*", slips = "*", splitter = "*", dir = "*" }
local CH_ISLANDS = { entry = "channel", layout = "*", main = { "town_s", "town_l", "country_l" }, side = { "town_s", "country_m" },
	slips = { "near", "main" }, splitter = "*", dir = "*", island = { "paved" } }
local CH_ARMS = { entry = "channel", layout = "*", splitter = "*", armlen = { "40", "60" } }
-- Set-back search: slip angle x corner gap x free length (ch.SLIP_ANGLE / CORNER_GAP / SLIP_FREE),
-- the shipped set (40 deg, 7 m, 4 m) first; every candidate (smaller = a more compact junction).
local CH_SEARCH = { entry = "channel", layout = "*", main = "*", side = "*", splitter = "*",
	search = { kind = "grid", values = { order = { "chSlipAngle", "chCornerGap", "chSlipFree" },
		chSlipAngle = { 40, 50 }, chCornerGap = { 7, 4, 1 }, chSlipFree = { 4, 2 } } } }

-- Roundabout Interchange (Phase 5d): layouts x highways x levels x lanes at the 15 m slider and
-- the default cross road (town medium), both bridge types (year 1969: steel, 2020: concrete); town
-- large / country large cross roads; 120 m slip roads; left-hand traffic; an island sample.
local IX_ALL = { entry = "interchange", layout = "*", highway = "*", level = "*", lanes = "*", radius = { "15" }, year = "*" }
local IX_CROSS = { entry = "interchange", layout = "*", highway = "*", level = "*", lanes = "*", radius = { "15" },
	cross = { "town_l", "country_l" } }
local IX_SLIP = { entry = "interchange", layout = "*", highway = "*", level = "*", lanes = "*", radius = { "15" }, slip = { "120" } }
local IX_LHT = { entry = "interchange", layout = "*", level = "*", radius = { "15" }, dir = { "lht" } }
local IX_ISLANDS = { entry = "interchange", layout = "*", level = "*", radius = { "15" }, island = { "trees" } }
-- Tunables search (ix.CLEAR / GORE_RUN / GAMMA / WAIST_GAP), shipped values first, every
-- candidate; gamma only where it applies (dumbbell, peanut), the waist gap only on the peanut.
local IX_SEARCH_2B = { entry = "interchange", layout = { "two_bridge" }, highway = "*", level = "*", radius = { "15" },
	search = { kind = "grid", values = { order = { "ixClear", "ixGoreRun" }, ixClear = { 8, 6, 4 }, ixGoreRun = { 30, 20 } } } }
local IX_SEARCH_DB = { entry = "interchange", layout = { "dumbbell" }, highway = "*", level = "*", radius = { "15" },
	search = { kind = "grid", values = { order = { "ixClear", "ixGamma", "ixGoreRun" },
		ixClear = { 8, 6, 4 }, ixGamma = { 35, 20, 50 }, ixGoreRun = { 30, 20 } } } }
local IX_SEARCH_PN = { entry = "interchange", layout = { "peanut" }, highway = "*", level = "*", radius = { "15" },
	search = { kind = "grid", values = { order = { "ixClear", "ixGamma", "ixGoreRun", "ixWaistGap" },
		ixClear = { 8, 6, 4 }, ixGamma = { 35, 20, 50 }, ixGoreRun = { 30, 20 }, ixWaistGap = { 6, 3 } } } }

-- Phase 5f subsets (PROBE.md "Phase 5f runs") -------------------------------------------------
-- Channelized Junction: the 81 base combos (layout x main x side x splitter, near-side slip lanes)
-- where the p5_channel_search accepted nothing (40 and 50 deg, one-way xsmall slip lanes), each
-- with every candidate: slip angle x slip lane template (one-way xsmall, small, medium). The
-- shipped fallback (square_roundabouts_channel.lua ch.FALLBACK: 65 deg one-way small for medium
-- roads, 50 deg one-way medium for large roads) is among them. Both dev values are always set
-- (without chSlip the tuning row's template would apply).
local CH_F_VALUES = { kind = "grid", values = { order = { "chSlipAngle", "chSlip" }, chSlipAngle = { 65, 50, 80 }, chSlip = { 2, 3, 1 } } }
local CH_F_T_WIDE = { entry = "channel", layout = { "T" }, main = "*", side = { "town_l", "country_l" }, splitter = "*", search = CH_F_VALUES }
local CH_F_T_TM = { entry = "channel", layout = { "T" }, main = "*", side = { "town_m" }, splitter = { "off" }, search = CH_F_VALUES }
local CH_F_X_MAIN = { entry = "channel", layout = { "X" }, main = { "town_m", "town_l", "country_l" }, side = "*", splitter = "*", search = CH_F_VALUES }
local CH_F_X_WIDE = { entry = "channel", layout = { "X" }, main = { "town_s", "country_s", "country_m" }, side = { "town_l", "country_l" },
	splitter = "*", search = CH_F_VALUES }
local CH_F_X_TM = { entry = "channel", layout = { "X" }, main = { "town_s", "country_s", "country_m" }, side = { "town_m" },
	splitter = { "off" }, search = CH_F_VALUES }
-- The shipped channel after the 5f tuning pass: every layout x main x side x splitter with both
-- slip lane sets and both traffic sides (islands None, 30 m arms; neither changed a verdict).
local CH_F_ALL = { entry = "channel", layout = "*", main = "*", side = "*", slips = { "near", "main" }, splitter = "*", dir = "*" }
-- Roundabout Interchange: the two-bridge ring with 4 lanes (the engine rejected all 30 in p5_all),
-- shipped now with alpha <= 40 deg; candidates for the largest alpha (ix.alphaMax), shipped first.
local IX_F_SEARCH = { entry = "interchange", layout = { "two_bridge" }, highway = "*", level = "*", lanes = { "4" }, radius = { "15" },
	search = { kind = "grid", values = { order = { "ixAlphaMax" }, ixAlphaMax = { 40, 45, 35, 30 } } } }
-- ... and the shipped 4-lane two-bridge ring: every highway x level x cross road sample x slip
-- road length, both bridge types.
local IX_F_ALL = { entry = "interchange", layout = { "two_bridge" }, highway = "*", level = "*", lanes = { "4" }, radius = { "15", "40" },
	cross = { "town_m", "country_l" }, slip = { "120", "140" }, year = "*" }
-- Main entry: 2:1 ovals with splitter islands and large arms on 4-lane rings, Y / 5 arms (forced
-- at 60 m or built at the 40 m floor the offline model rejected before; Phase 5f splits along the
-- ring normal, geom.splitAxis), plus the hamburger sweep again (the 60 combos it rejected now
-- build the radius p5_hamburger_radius accepted).
local OVAL_SPLIT = { entry = "main", shape = { "oval2" }, lanes = { "4" }, radius = { "40", "45", "60" }, arms = { "Y", "5" },
	splitter = { "on" }, arm = { "town_l", "country_l" }, centre = { "none", "road" } }

-- Phase 5g subset (PROBE.md "Phase 5g runs"): the layouts Phase 5g ships that p5f_all did not
-- place. Channel: the 81 base combos of p5f_search (now tuning rows: 65 deg one-way xsmall slip
-- lanes, else 80 deg) with both slip lane sets and both traffic sides; interchange: the 4-lane
-- two-bridge ring with alpha <= 45 deg (smaller rings) over every cross road / slip road / year
-- p5_all and p5f_all swept it with, at the 15 and 40 m sliders.
local function sweepOf(block, extra)
	local b = {}
	for k, v in pairs(block) do if k ~= "search" then b[k] = v end end
	for k, v in pairs(extra) do b[k] = v end
	return b
end
local CH_G_EXTRA = { slips = { "near", "main" }, dir = "*" }
local IX_G_VERIFY = { entry = "interchange", layout = { "two_bridge" }, highway = "*", level = "*", lanes = { "4" }, radius = { "15", "40" },
	cross = { "town_m", "town_l", "country_l" }, slip = { "120", "140" }, year = "*" }

grid.SUBSETS = {
	-- a handful of combos to check the probe itself works (about a minute)
	smoke = {
		{ entry = "main" },
		{ entry = "main", arms = { "6" }, splitter = { "on" }, arm = { "town_s", "town_m", "town_l" } },
		{ entry = "main", arms = { "4" }, centre = { "road", "tram" } },
		{ entry = "main", arms = { "4" }, radius = { "30" }, tram = { "on" } },
		{ entry = "magic", size = "*", arm = { "town_s", "town_l" } },
		-- Phase 5e: the hamburger and the two new entries once each (their constructions resolve)
		{ entry = "main", arms = { "4" }, centre = { "lights" }, through = { "town_l" } },
		{ entry = "channel" },
		{ entry = "interchange" },
	},
	splitter6 = { SPLITTER6 },
	main = { MAIN },
	main_cw = { MAIN_CW },
	magic = { MAGIC },
	-- short blocks first, so a run stopped early still has them
	all = { MAGIC, MAIN_CW, MAIN },
	-- Phase 4 searches (PROBE.md "Search runs")
	search_quick = { Q_MAGIC_SIZE, Q_MAGIC_SPACING, Q_TRAM_STUB, Q_TRAM_CW, Q_SPLITTER, Q_RADIUS },
	search_magic = { S_MAGIC_SIZE, S_MAGIC_SPACING },
	search_magic2 = { S_MAGIC_SIZE2 },
	-- every Magic size floor, 1 and 2 lanes, in one game start (after a change to magic.SIZES)
	search_magic_sizes = { S_MAGIC_SIZE, S_MAGIC_SIZE2 },
	search_tram = { S_TRAM_STUB, S_TRAM_CW },
	search_splitter = { S_SPLITTER, S_SPLITTER_OVAL },
	search_radius = { S_RADIUS },
	search_radius_split = { S_RADIUS_SPLIT },
	search = { S_MAGIC_SIZE, S_MAGIC_SPACING, S_TRAM_STUB, S_TRAM_CW, S_SPLITTER, S_SPLITTER_OVAL, S_RADIUS },
	-- Phase 5e (PROBE.md "Phase 5e runs"); tools/parse_probe.py writes them to probe_<subset>.*
	p5_channel = { CH_ALL, CH_ISLANDS, CH_ARMS },
	p5_hamburger = { HB_S, HB_L },
	p5_interchange = { IX_ALL, IX_CROSS, IX_SLIP, IX_LHT, IX_ISLANDS },
	-- every Phase 5e sweep, shortest first
	p5_all = { IX_ALL, IX_CROSS, IX_SLIP, IX_LHT, IX_ISLANDS, HB_S, HB_L, CH_ALL, CH_ISLANDS, CH_ARMS },
	p5_channel_search = { CH_SEARCH },
	p5_hamburger_radius = { HB_RADIUS_S, HB_RADIUS_L },
	p5_interchange_search = { IX_SEARCH_2B, IX_SEARCH_DB, IX_SEARCH_PN },
	-- every Phase 5e search, shortest first
	p5_search = { IX_SEARCH_2B, IX_SEARCH_DB, IX_SEARCH_PN, CH_SEARCH, HB_RADIUS_S, HB_RADIUS_L },
	-- Phase 5f (PROBE.md "Phase 5f runs"): verification sweep of the tuned geometry, and the
	-- searches for what nothing was accepted for yet
	p5f_all = { IX_F_ALL, OVAL_SPLIT, CH_F_ALL, HB_S, HB_L },
	p5f_search = { IX_F_SEARCH, CH_F_T_WIDE, CH_F_T_TM, CH_F_X_MAIN, CH_F_X_WIDE, CH_F_X_TM },
	-- Phase 5g: verification sweep of what the 5g tuning pass changed
	p5g_verify = { IX_G_VERIFY, sweepOf(CH_F_T_WIDE, CH_G_EXTRA), sweepOf(CH_F_T_TM, CH_G_EXTRA), sweepOf(CH_F_X_MAIN, CH_G_EXTRA),
		sweepOf(CH_F_X_WIDE, CH_G_EXTRA), sweepOf(CH_F_X_TM, CH_G_EXTRA) },
}
-- Order of the "Subset" mod param values (mod.json sqrb_probe_subset).
grid.SUBSET_ORDER = {
	"smoke", "splitter6", "magic", "main_cw", "main", "all",
	"search_quick", "search_magic", "search_tram", "search_splitter", "search_radius", "search_radius_split", "search",
	"search_magic2", "search_magic_sizes",
	"p5_all", "p5_channel", "p5_hamburger", "p5_interchange",
	"p5_search", "p5_channel_search", "p5_hamburger_radius", "p5_interchange_search",
	"p5f_all", "p5f_search", "p5g_verify",
}

local function indexOf(list, v)
	for i = 1, #list do if list[i] == v then return i end end
	return nil
end
grid.indexOf = indexOf

--- Value indices of one axis for a block: "*" = all, a list of labels, or nil = default.
local function axisValues(axis, spec)
	if spec == nil then return { axis.default } end
	if spec == "*" then
		local all = {}
		for i = 1, #axis.labels do all[i] = i end
		return all
	end
	if type(spec) ~= "table" then
		error("probe grid: axis '" .. axis.key .. "' must be \"*\" or a list of labels")
	end
	local out = {}
	for i, label in ipairs(spec) do
		local idx = indexOf(axis.labels, tostring(label))
		if not idx then
			error("probe grid: unknown value '" .. tostring(label) .. "' for axis '" .. axis.key ..
				"' (one of " .. table.concat(axis.labels, ", ") .. ")")
		end
		out[i] = idx
	end
	return out
end

--- Replay key of a combo: entry tag + value indices in axis order, e.g. "m:1,2,5,3,1,1,1,1,1,1,1".
function grid.key(entry, indices)
	return grid.ENTRIES[entry].tag .. ":" .. table.concat(indices, ",")
end

--- One combo from an entry and value indices (one per axis, in axis order).
function grid.combo(entry, indices)
	local e = grid.ENTRIES[entry]
	if not e then error("probe grid: unknown entry '" .. tostring(entry) .. "'") end
	local params, labels = {}, {}
	for i, axis in ipairs(e.axes) do
		local v = indices[i]
		if v ~= nil then
			params[axis.param] = axis.values and axis.values[v] or v
			labels[i] = axis.labels[v]
		end
	end
	return {
		entry = entry,
		indices = indices,
		params = params,
		labels = labels,
		key = grid.key(entry, indices),
	}
end

local BLOCK_FIELDS = { entry = true, search = true, exclude = true }

--- Whether a combo (labels by axis key) matches one exclude condition ({axis = {labels}}).
local function matches(cond, byKey)
	for k, labels in pairs(cond) do
		if indexOf(labels, byKey[k]) == nil then return false end
	end
	return true
end

local function labelsByKey(entry, combo)
	local out = {}
	for i, axis in ipairs(grid.ENTRIES[entry].axes) do out[axis.key] = combo.labels[i] end
	return out
end
grid.labelsByKey = labelsByKey

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

--- Short text of a dev table in DEV_ORDER, e.g. "radius=20 fork=35" ("" for none).
function grid.devLabel(dev)
	local parts = {}
	for _, name in ipairs(grid.DEV_ORDER) do
		if dev and dev[name] ~= nil then parts[#parts + 1] = name .. "=" .. grid.bare(dev[name]) end
	end
	return table.concat(parts, " ")
end

local function cand(fixed, extra)
	local dev = copy(fixed)
	for k, v in pairs(extra) do dev[k] = v end
	return { dev = dev, label = grid.devLabel(extra) }
end

--- Candidates of a search job: {{dev, label}} in the order the probe asks the engine.
-- combo = the base combo, search = the block's search table, fixed = the job's fixed dev table.
function grid.candidates(combo, search, fixed)
	local kind = search.kind
	local values = search.values
	local S = grid.SEARCH
	local out = {}
	if kind == "radius" then
		local r0 = tonumber(labelsByKey(combo.entry, combo).radius)
		local step, max = (values and values.step) or S.RADIUS_STEP, (values and values.max) or S.RADIUS_MAX
		local radii = { r0 }
		local r = (math.floor(r0 / step) + 1) * step
		while r <= max do
			radii[#radii + 1] = r
			r = r + step
		end
		for _, x in ipairs((values and values.extra) or S.RADIUS_EXTRA) do
			if x > r0 and x <= max and x % step ~= 0 then radii[#radii + 1] = x end
		end
		table.sort(radii)
		for _, x in ipairs(radii) do out[#out + 1] = cand(fixed, { radius = x }) end
	elseif kind == "magic_size" then
		for _, size in ipairs((values and values.sizes) or S.MAGIC_SIZES) do out[#out + 1] = cand(fixed, { magicSize = size }) end
	elseif kind == "magic_spacing" then
		local radius = fixed and fixed.magicRadius
		if not radius then error("probe grid: magic_spacing needs fixed = {{magicRadius = m}, ...}") end
		local rs = radius + S.MAGIC_OFFSET
		local step = (values and values.step) or 5
		local d = math.ceil(S.MAGIC_SPACING_FROM * rs / step) * step
		local to = (values and values.to) or S.MAGIC_SPACING_TO * rs
		while d <= to do
			out[#out + 1] = cand(fixed, { magicDistance = d })
			d = d + step
		end
	elseif kind == "splitter" then
		local v = values or S.SPLIT
		local list = {}
		for _, leg in ipairs(v.legs) do
			for _, fork in ipairs(v.forks) do
				for _, split in ipairs(v.splits) do
					for _, spread in ipairs(v.spreads) do
						for _, neck in ipairs(v.necks) do
							list[#list + 1] = { leg = leg, fork = fork, split = split, spread = spread, neck = neck }
						end
					end
				end
			end
		end
		-- most compact first: shortest split + neck, then narrowest fork, narrowest leg, least spread
		table.sort(list, function(x, y)
			local lx, ly = x.split + x.neck, y.split + y.neck
			if lx ~= ly then return lx < ly end
			if x.fork ~= y.fork then return x.fork < y.fork end
			if x.leg ~= y.leg then return x.leg < y.leg end
			if x.spread ~= y.spread then return x.spread < y.spread end
			return x.neck < y.neck
		end)
		for _, c in ipairs(list) do out[#out + 1] = cand(fixed, c) end
	elseif kind == "grid" then
		if not (values and values.order) then error("probe grid: a grid search needs values = {order = {names}, name = {values}}") end
		local list = { {} }
		for _, name in ipairs(values.order) do
			if not grid.DEV[name] then error("probe grid: unknown dev override '" .. tostring(name) .. "'") end
			local nextList = {}
			for _, c in ipairs(list) do
				for _, v in ipairs(values[name]) do
					local d = copy(c)
					d[name] = v
					nextList[#nextList + 1] = d
				end
			end
			list = nextList
		end
		for _, c in ipairs(list) do out[#out + 1] = cand(fixed, c) end
	elseif kind == "tram_stub" then
		for _, stub in ipairs((values and values.stubs) or S.TRAM_STUBS) do out[#out + 1] = cand(fixed, { tramStub = stub }) end
	else
		error("probe grid: unknown search kind '" .. tostring(kind) .. "'")
	end
	return out
end

--- Construction params of a combo plus a dev table (grid.DEV keys).
function grid.withDev(params, dev)
	local p = copy(params)
	for name, v in pairs(dev or {}) do
		local key = grid.DEV[name]
		if not key then error("probe grid: unknown dev override '" .. tostring(name) .. "'") end
		p[key] = v
	end
	return p
end

--- Expands one block into combos (appended to out, skipping keys in seen). A search block makes
-- one job per combo and fixed dev table.
local function expandBlock(block, out, seen)
	local e = grid.ENTRIES[block.entry]
	if not e then error("probe grid: unknown entry '" .. tostring(block.entry) .. "'") end
	for k in pairs(block) do
		if not BLOCK_FIELDS[k] then
			local known = false
			for _, axis in ipairs(e.axes) do if axis.key == k then known = true end end
			if not known then error("probe grid: entry '" .. block.entry .. "' has no axis '" .. tostring(k) .. "'") end
		end
	end
	local search = block.search
	if search and grid.SEARCH_FIRST[search.kind] == nil then
		error("probe grid: unknown search kind '" .. tostring(search.kind) .. "'")
	end
	local values = {}
	for i, axis in ipairs(e.axes) do values[i] = axisValues(axis, block[axis.key]) end
	local n = #values
	local pos = {}
	for i = 1, n do pos[i] = 1 end
	while true do
		local indices = {}
		for i = 1, n do indices[i] = values[i][pos[i]] end
		local combo = grid.combo(block.entry, indices)
		local excluded = false
		if block.exclude then
			local byKey = labelsByKey(block.entry, combo)
			for _, cond in ipairs(block.exclude) do
				if matches(cond, byKey) then excluded = true end
			end
		end
		if not excluded then
			if search then
				for _, fixed in ipairs(search.fixed or { {} }) do
					local fixedLabel = grid.devLabel(fixed)
					local id = combo.key .. "#" .. search.kind .. (fixedLabel ~= "" and ("#" .. fixedLabel) or "")
					if not seen[id] then
						seen[id] = true
						local job = grid.combo(block.entry, indices)
						local first = search.first
						if first == nil then first = grid.SEARCH_FIRST[search.kind] end
						job.id = id
						job.search = {
							kind = search.kind,
							first = first,
							fixed = copy(fixed),
							fixedLabel = fixedLabel,
							requireRule = search.requireRule,
							cands = grid.candidates(job, search, fixed),
						}
						out[#out + 1] = job
					end
				end
			elseif not seen[combo.key] then
				seen[combo.key] = true
				out[#out + 1] = combo
			end
		end
		local i = n
		while i >= 1 do
			pos[i] = pos[i] + 1
			if pos[i] <= #values[i] then break end
			pos[i] = 1
			i = i - 1
		end
		if i < 1 then break end
	end
end

--- All combos of a subset (a name from SUBSETS, or a list of blocks).
function grid.expand(subset)
	local blocks = subset
	if type(subset) == "string" then
		blocks = grid.SUBSETS[subset]
		if not blocks then error("probe grid: unknown subset '" .. subset .. "'") end
	end
	local out, seen = {}, {}
	for _, block in ipairs(blocks) do expandBlock(block, out, seen) end
	return out
end

--- Number of combos (jobs) of a subset (blocks may overlap: this is the upper bound). Blocks with
-- exclusions or searches are expanded to count them.
function grid.size(subset)
	local blocks = type(subset) == "string" and grid.SUBSETS[subset] or subset
	local total = 0
	for _, block in ipairs(blocks) do
		if block.exclude or block.search then
			total = total + #grid.expand({ block })
		else
			local e = grid.ENTRIES[block.entry]
			local n = 1
			for _, axis in ipairs(e.axes) do n = n * #axisValues(axis, block[axis.key]) end
			total = total + n
		end
	end
	return total
end

--- Most engine calls a list of combos/jobs can take (a search job: every candidate).
function grid.maxCalls(combos)
	local n = 0
	for _, c in ipairs(combos) do n = n + (c.search and #c.search.cands or 1) end
	return n
end

-- Log line format -------------------------------------------------------------------------------

grid.PREFIX = "[SQRB_PROBE]"

--- A free-text value for a quoted field: no double quotes, no line breaks.
function grid.clean(s)
	s = tostring(s == nil and "" or s)
	s = s:gsub("[\r\n\t]+", " "):gsub('"', "'")
	return s
end

--- A list of strings as one quoted field, joined with "|" (a "|" inside an item becomes "/").
function grid.joinList(list)
	local parts = {}
	for i, s in ipairs(list or {}) do parts[i] = grid.clean(s):gsub("|", "/") end
	return '"' .. table.concat(parts, "|") .. '"'
end

local function bare(v)
	if v == nil then return "-" end
	if type(v) == "boolean" then return v and "true" or "false" end
	if type(v) == "number" then
		if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.2f", v)
	end
	local s = tostring(v):gsub("%s+", "_")
	if s == "" then return "-" end
	return s
end
grid.bare = bare

local function quoted(v) return '"' .. grid.clean(v) .. '"' end

--- One line: prefix, kind, then key=value fields in the given order.
-- fields = {{key, value, "q"?}}: "q" quotes the value (free text), "l" joins a list.
function grid.line(kind, fields)
	local parts = { grid.PREFIX, kind }
	for _, f in ipairs(fields) do
		local k, v, mode = f[1], f[2], f[3]
		local s
		if mode == "q" then s = quoted(v)
		elseif mode == "l" then s = grid.joinList(v)
		else s = bare(v) end
		parts[#parts + 1] = k .. "=" .. s
	end
	return table.concat(parts, " ")
end

--- Result line of one combo. r = {
--   ok, critical, messages, warnings, infos, collisions, buildings, cost, added,
--   mode ("proposal" | "result_only"), error (exception text), updateFn (text, if checked),
--   geom = {effR, forced, fork, a, b, effSize, rs, setback, bridge, edges, lists} (any subset), ms }
function grid.resultLine(n, total, combo, r)
	local e = grid.ENTRIES[combo.entry]
	local fields = {
		{ "n", n }, { "total", total }, { "entry", combo.entry },
	}
	for i, axis in ipairs(e.axes) do fields[#fields + 1] = { axis.key, combo.labels[i] } end
	local g = r.geom or {}
	local rest = {
		{ "ok", r.ok == true },
		{ "critical", r.critical },
		{ "nmsg", r.messages and #r.messages or nil },
		{ "msgs", r.messages or {}, "l" },
		{ "warnings", r.warnings or {}, "l" },
		{ "infos", r.infos or {}, "l" },
		{ "coll", r.collisions },
		{ "bld", r.buildings },
		{ "added", r.added },
		{ "cost", r.cost },
		{ "effR", g.effR },
		{ "effSize", g.effSize },
		{ "forced", g.forced },
		{ "fork", g.fork },
		{ "a", g.a },
		{ "b", g.b },
		{ "rs", g.rs },
		{ "setback", g.setback },
		{ "bridge", g.bridge },
		{ "edges", g.edges },
		{ "geomErr", g.error, "q" },
		{ "mode", r.mode },
		{ "upd", r.updateFn, "q" },
		{ "err", r.error, "q" },
		{ "ms", r.ms },
		{ "key", combo.key },
	}
	for _, f in ipairs(rest) do fields[#fields + 1] = f end
	return grid.line("R", fields)
end

--- Log field of a dev override: "dev" + its name, e.g. devRadius, devNeckType (letters only, so
-- every parser's word pattern reads it).
function grid.devField(name)
	return "dev" .. name:sub(1, 1):upper() .. name:sub(2)
end

local function devFields(fields, dev)
	for _, name in ipairs(grid.DEV_ORDER) do fields[#fields + 1] = { grid.devField(name), dev and dev[name] } end
end

local function jobHead(n, total, job)
	local e = grid.ENTRIES[job.entry]
	local fields = { { "n", n }, { "total", total }, { "entry", job.entry } }
	for i, axis in ipairs(e.axes) do fields[#fields + 1] = { axis.key, job.labels[i] } end
	fields[#fields + 1] = { "kind", job.search.kind }
	fields[#fields + 1] = { "fixed", job.search.fixedLabel, "q" }
	return fields
end

--- One candidate of a search job (kind "T"): job fields, the candidate's dev overrides (dev* fields),
-- the engine verdict and what the geometry built (offline = the offline model accepted the
-- exact layout; sane = false: degenerate geometry, not sent to the engine).
function grid.trialLine(n, total, job, ci, r)
	local c = job.search.cands[ci]
	local fields = jobHead(n, total, job)
	fields[#fields + 1] = { "cand", ci }
	fields[#fields + 1] = { "ncand", #job.search.cands }
	fields[#fields + 1] = { "label", c.label, "q" }
	devFields(fields, c.dev)
	local g = r.geom or {}
	local rest = {
		{ "ok", r.ok == true },
		{ "critical", r.critical },
		{ "nmsg", r.messages and #r.messages or nil },
		{ "msgs", r.messages or {}, "l" },
		{ "coll", r.collisions },
		{ "cost", r.cost },
		{ "effR", g.effR },
		{ "effSize", g.effSize },
		{ "offline", g.offline },
		{ "forced", g.forced },
		{ "fork", g.fork },
		{ "rs", g.rs },
		{ "setback", g.setback },
		{ "bridge", g.bridge },
		{ "edges", g.edges },
		{ "sane", g.sane },
		{ "geomErr", g.error, "q" },
		{ "mode", r.mode },
		{ "upd", r.updateFn, "q" },
		{ "err", r.error, "q" },
		{ "ms", r.ms },
		{ "key", job.key },
	}
	for _, f in ipairs(rest) do fields[#fields + 1] = f end
	return grid.line("T", fields)
end

--- Summary of a search job (kind "S"). s = {tried, accepted, best (candidate index or nil),
-- rejected = {labels}, skipped (reason or nil), ship = {effR, effSize} (the shipped geometry
-- without dev overrides)}.
function grid.searchLine(n, total, job, s)
	local fields = jobHead(n, total, job)
	local best = s.best and job.search.cands[s.best]
	local ship = s.ship or {}
	local rest = {
		{ "first", job.search.first },
		{ "ncand", #job.search.cands },
		{ "tried", s.tried },
		{ "accepted", s.accepted },
		{ "found", best ~= nil },
		{ "best", best and best.label or "", "q" },
	}
	for _, f in ipairs(rest) do fields[#fields + 1] = f end
	devFields(fields, best and best.dev)
	local tail = {
		{ "acceptedList", s.acceptedLabels or {}, "l" },
		{ "rejected", s.rejected or {}, "l" },
		{ "skipped", s.skipped, "q" },
		{ "shipR", ship.effR },
		{ "shipSize", ship.effSize },
		{ "id", job.id, "q" },
		{ "key", job.key },
	}
	for _, f in ipairs(tail) do fields[#fields + 1] = f end
	return grid.line("S", fields)
end

return grid
