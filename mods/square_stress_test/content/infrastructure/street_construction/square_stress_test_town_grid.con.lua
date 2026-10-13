-- Stress Test "Wide grid" town streets: a square grid of the large 4-lane town street, built by the
-- Stress Test window (Test grid / Junction test with Streets = Wide grid) under each new town before
-- the town is created. Not in the build menu (no menuCategory). Every node is freed, so once built it
-- is ordinary streets. Geometry: stress/stress_grid_streets.lua.

local grid = ug_require "square_stress_test::/stress/stress_grid_streets.lua"

function data()
	local halves = {}
	for i, h in ipairs(grid.HALF) do halves[i] = tostring(2 * h) .. " m" end
	return {
		description = {
			name = "Stress Test town street grid",
			description = "A square grid of large town streets, built by the Stress Test window.",
		},
		params = {
			{
				key = grid.KEYS.half,
				name = "Size",
				uiType = "Button",
				values = halves,
				defaultIndex = 2,
			},
			{
				key = grid.KEYS.era,
				name = "Street",
				uiType = "Button",
				values = { "New", "Old" },
				defaultIndex = 1,
			},
			{
				key = grid.KEYS.ring,
				name = "Outer ring",
				uiType = "Button",
				values = { "Town street", "Country road" },
				defaultIndex = 1,
			},
		},
		updateScript = {
			fileName = "square_stress_test_town_grid.script@updateFn",
			params = {},
		},
	}
end
