-- Highway Interchange (with params.year 1969 and without it) builds unchanged: every group of its
-- shipped sweep (golden.lua G.entryGroups, the grid of test_short_edges.lua) gives exactly the
-- fingerprints in golden_entries.lua, rounded (1e-4) and exact (%.17g). Recorded in Phase 7e after
-- the engine-tuned hx.BRIDGE_PIECE (INTERCHANGES.md "Phase 7e notes"); regenerate only on purpose
-- (a deliberate geometry change):
--   SQRB_GOLDEN_WRITE=1 make test MOD=mods/square_roundabouts ARGS="-f entries_unchanged_highway"
-- prints the lines; paste them into golden_entries.lua. One file per entry so they run in parallel.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local mod = ug_require(DIR .. "square_roundabouts_highway.lua")

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local G = loadfile(here .. "golden.lua", "t", _ENV)()
local golden = loadfile(here .. "golden_entries.lua", "t", _ENV)()

ug_require(DIR .. "square_roundabouts_highway.script.lua")
G.entryTest("highway", mod, geom, data().updateFn, golden, 4)
