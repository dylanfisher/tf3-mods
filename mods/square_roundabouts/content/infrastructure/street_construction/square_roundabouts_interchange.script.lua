-- Better Roundabouts: updateFn for square_roundabouts_interchange.con.lua ("Roundabout Interchange").
-- Pure (no api.*): square_roundabouts_interchange.build() makes the highway, rings, bridges, slip
-- roads and islands, square_roundabouts_result.lua maps them to the construction result.
-- Exports through data().

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local interchange = ug_require(DIR .. "square_roundabouts_interchange.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")

function data()
return {
	updateFn = function(captureParams, params)
		return result.build(interchange.build(interchange.readParams(params)))
	end,
}
end
