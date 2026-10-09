-- DEV ONLY (never upload): updateFn of sqrb_probe_old_one_way.con.lua. Pure; exports through data()
-- (a .script.lua that returns a table fails in game with "Expected table at path").

local shape = ug_require "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_old_one_way.lua"
local result = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_result.lua"

function data()
return {
	updateFn = function(captureParams, params)
		return result.build(shape.build(shape.readParams(params)))
	end,
}
end
