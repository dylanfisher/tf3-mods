-- Presence marker: another mod tells whether square_sqperf_all is active in the current game with
--   pcall(ug_require, "square_sqperf_all::/square_sqperf_all_presence.lua")
-- (CLAUDE.md "Detecting another of our mods"). Keep it side-effect free.
-- square_sqperf_all has no scripts and no params: SQPERF mods only look for its entry in the mod params
-- table (sqperf.debugOn, tools/sqperf/sqperf.lua). This file is only here so the mod has content.
return { modId = "square_sqperf_all" }
