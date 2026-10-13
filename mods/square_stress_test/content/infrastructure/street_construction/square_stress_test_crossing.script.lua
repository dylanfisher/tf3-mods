-- Stress Test: updateFn of square_stress_test_crossing.con.lua (geometry: stress/stress_crossing.lua).
-- Exports through data() (a .script.lua that returns a table fails in game with "Expected table at path").

local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"

function data()
return {
	updateFn = function(_captureParams, params)
		return cross.result(params)
	end,
}
end
