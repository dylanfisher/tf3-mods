-- Script functions referenced from mod.json as "square_industry_flows::mod.script@<function>".
-- See docs/wiki/modding/general/modscripts.md

local mod = {}

mod.runFn = function(_configDict : {{string, string}}, _allModParams : {string : {string : integer}})
	log.message("square_industry_flows loaded")
end

return mod
