-- Script functions referenced from mod.json as "square_passenger_destinations::mod.script@<function>".
-- See docs/wiki/modding/general/modscripts.md, but note captureParams comes first (the wiki omits it;
-- base base/base_mod.lua:8, docs/findings.md). Param values are 1-based option indices.

local mod = {}

mod.runFn = function(_captureParams : any, _settings : {{string, string}}, _allModParams : {string : {string : integer}})
	log.message("square_passenger_destinations loaded")
end

return mod
