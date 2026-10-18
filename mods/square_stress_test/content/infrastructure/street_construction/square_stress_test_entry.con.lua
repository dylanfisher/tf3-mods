-- Stress Test town entry roundabout: a 3-lane (or 2-lane) roundabout with four short large country road arms, built
-- by the Stress Test window (Lights showcase) in place of each town grid's side-middle crossroads. Not in
-- the build menu (no menuCategory). Every node is freed, so once built it is ordinary streets.
-- Geometry: stress/stress_entry_streets.lua. Its templates exist from 1940; the window checks the year too.

local entry = ug_require "square_stress_test::/stress/stress_entry_streets.lua"

function data()
	return {
		description = {
			name = "Stress Test entry roundabout",
			description = "A roundabout at a test town's entry, built by the Stress Test window.",
		},
		availability = {
			yearFrom = entry.FROM_YEAR,
		},
		params = {
			{
				key = entry.KEYS.dir,
				name = "Direction",
				uiType = "Button",
				values = { "Anticlockwise", "Clockwise" },
				defaultIndex = entry.DIR_CCW,
			},
			{
				key = entry.KEYS.ring,
				name = "Ring",
				uiType = "Button",
				values = { "2 lanes", "3 lanes" },
				defaultIndex = entry.RING_DEFAULT,
			},
			{
				key = entry.KEYS.inAxis,
				name = "Shorter arm",
				uiType = "Button",
				values = { "None", "East", "North", "West", "South" },
				defaultIndex = 1,
			},
			{
				key = entry.KEYS.inReach,
				name = "Its length",
				uiType = "Button",
				values = (function()
					local out = {}
					for i, r in ipairs(entry.IN_REACHES) do out[i] = tostring(r) .. " m" end
					return out
				end)(),
				defaultIndex = 1,
			},
			{
				-- ring mid nodes per quarter (the bench's 3-lane ring with mid nodes; stress_entry_streets entry.midNodes)
				key = entry.KEYS.mid,
				name = "Ring mid nodes",
				uiType = "Button",
				values = { "None", "1", "2", "3" },
				defaultIndex = 1,
			},
		},
		updateScript = {
			fileName = "square_stress_test_entry.script@updateFn",
			params = {},
		},
	}
end
