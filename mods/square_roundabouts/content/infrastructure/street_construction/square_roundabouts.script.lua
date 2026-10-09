-- Better Roundabouts: updateFn for square_roundabouts.con.lua.
--
-- No checkEnabledScript functions: the base params panel only applies a "Disabled" state when the
-- menu is reopened, and "Hidden" breaks the info panel of hovered base constructions (base
-- gui/construction/construction.tl updateDisabledParams ~1588 vs getParamsForValidIndices ~1519).
-- Every param is meaningful for every other param's value instead (PLAN.md "Phase 2a notes",
-- "Phase 3 notes").
--
-- The updateFn is pure (no api.*): square_roundabouts_geometry.build() turns the params into
-- ring, arms, splitter legs, a through road and islands, and square_roundabouts_result.lua maps
-- them to the construction result.
--
-- Exports through data() (a .script.lua that returns a table fails in game with
-- "Expected table at path").

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")

function data()
return {
	updateFn = function(captureParams, params)
		return result.build(geom.build(geom.readParams(params)))
	end,
}
end
