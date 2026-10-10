-- Channelized Junction builds unchanged (INTERCHANGES.md Phase 7a,
-- section 6): every group of its shipped sweep (golden.lua G.entryGroups, the grid of
-- test_short_edges.lua) gives exactly the fingerprints in golden_entries.lua, rounded (1e-4, as
-- golden_default.lua) and exact (%.17g). Recorded before the Phase 7a extraction of
-- square_roundabouts_ramps.lua; regenerate only on purpose (a deliberate geometry change):
--   SQRB_GOLDEN_WRITE=1 uv run tests/run_tests.py -k "entries golden" mods/square_roundabouts
-- prints the lines; paste them into golden_entries.lua. One file per entry so they run in parallel.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local mod = ug_require(DIR .. "square_roundabouts_channel.lua")

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local G = loadfile(here .. "golden.lua", "t", _ENV)()
local golden = loadfile(here .. "golden_entries.lua", "t", _ENV)()

ug_require(DIR .. "square_roundabouts_channel.script.lua")
G.entryTest("channel", mod, geom, data().updateFn, golden)
