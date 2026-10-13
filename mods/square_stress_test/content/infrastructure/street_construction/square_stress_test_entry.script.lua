-- Stress Test: updateFn of square_stress_test_entry.con.lua (geometry: stress/stress_entry_streets.lua).
-- Exports through data() (a .script.lua that returns a table fails in game with "Expected table at path").

local entry = ug_require "square_stress_test::/stress/stress_entry_streets.lua"

function data()
return {
	updateFn = function(_captureParams, params)
		return entry.result(params)
	end,
}
end
