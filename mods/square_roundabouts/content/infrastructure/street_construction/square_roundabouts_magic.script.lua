-- Better Roundabouts: updateFn for square_roundabouts_magic.con.lua ("Magic Roundabout").
-- Pure (no api.*): square_roundabouts_magic.build() makes the satellites, links, arms and islands,
-- square_roundabouts_result.lua maps them to the construction result. Exports through data().

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")

function data()
return {
	updateFn = function(captureParams, params)
		return result.build(magic.build(magic.readParams(params)))
	end,
}
end
