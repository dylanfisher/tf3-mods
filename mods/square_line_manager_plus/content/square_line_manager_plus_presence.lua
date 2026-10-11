-- Presence marker: another mod tells whether square_line_manager_plus is active in the current game with
--   pcall(ug_require, "square_line_manager_plus::/square_line_manager_plus_presence.lua")
-- (CLAUDE.md "Detecting another of our mods"). Keep it side-effect free. Line Editor Undo does not use it: it checks
-- for our react-replacement-config instead (line_manager_plus/lmp_detect.lua says why).
return { modId = "square_line_manager_plus" }
