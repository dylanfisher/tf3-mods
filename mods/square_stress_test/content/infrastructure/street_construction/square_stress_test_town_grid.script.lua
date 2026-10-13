-- Stress Test: updateFn of square_stress_test_town_grid.con.lua (geometry: stress/stress_grid_streets.lua).
-- Exports through data() (a .script.lua that returns a table fails in game with "Expected table at path").

local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"

function data()
return {
	updateFn = function(_captureParams, params)
		return grid.result(params)
	end,
}
end
