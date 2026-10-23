-- DEV ONLY (never upload): updateFns of the two "DEV SQRB Bridge probe" entries
-- (sqrb_probe_bridge.con.lua: updateFn, sqrb_probe_bridge_ix.con.lua: updateFnIx). Pure: the main
-- mod's own geometry and result mapping, unchanged, then sqrb_probe_bridge.apply (Probe structure,
-- Probe islands). Exports through data() (a .script.lua that returns a table fails in game with
-- "Expected table at path").

local RB = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(RB .. "square_roundabouts_geometry.lua")
local interchange = ug_require(RB .. "square_roundabouts_interchange.lua")
local result = ug_require(RB .. "square_roundabouts_result.lua")
local bridge = ug_require "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_bridge.lua"

function data()
return {
	updateFn = function(captureParams, params)
		return bridge.apply(result.build(geom.build(geom.readParams(params))), bridge.readParams(params))
	end,
	updateFnIx = function(captureParams, params)
		return bridge.apply(result.build(interchange.build(interchange.readParams(params))), bridge.readParams(params))
	end,
}
end
