-- Better Roundabouts: updateFn for square_roundabouts_channel.con.lua ("Channelized Junction").
-- Pure (no api.*): square_roundabouts_channel.build() makes the arms, slip lanes, splitter legs and
-- islands, square_roundabouts_result.lua maps them to the construction result. Exports through data().

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local channel = ug_require(DIR .. "square_roundabouts_channel.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")

function data()
return {
	updateFn = function(captureParams, params)
		return result.build(channel.build(channel.readParams(params)))
	end,
}
end
