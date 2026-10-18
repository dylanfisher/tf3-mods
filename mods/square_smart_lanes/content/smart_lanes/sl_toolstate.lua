-- Smart Lanes tool: the GUI state shared by the tool script (sl_tool.script.lua: its recipe, toolbar callbacks and
-- the controller g.core) and the background plugin (sl_bg.script.lua: steps a Re-time run while the tool is closed,
-- sl_toolcore C.bgStep). One table per Lua state through ug_require's cache; the fields are set by the tool script.
-- Not saved: a load starts empty (a running Re-time ends with the game it ran in).
return {}
