-- Better Roundabouts: updateFn of the three Highway Interchange entries
-- (square_roundabouts_highway_<id>.con.lua, built by square_roundabouts_highway_menu.lua).
-- Pure (no api.*): the entry's updateScript params (captureParams.types) and its Layout button fix
-- the type (hx.specFor),
-- square_roundabouts_highway.build() makes the highway, cross road, bridges and ramps,
-- square_roundabouts_result.lua maps them to the construction result. Exports through data().

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local highway = ug_require(DIR .. "square_roundabouts_highway.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")

function data()
return {
	updateFn = function(captureParams, params)
		return result.build(highway.build(highway.specFor(captureParams, params)))
	end,
}
end
