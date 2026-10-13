-- Stress Test test crossing: one plain street crossing (X, T or skewed X) of two chosen roads, built
-- by the Stress Test window (Crossing test; Showcase plain groups: side road angle, own road per arm;
-- Lights showcase: Traffic light Yes). Not in the build menu (no menuCategory).
-- Every node is freed, so once built it is ordinary streets. Geometry: stress/stress_crossing.lua.

local cross = ug_require "square_stress_test::/stress/stress_crossing.lua"

function data()
	local roads = {}
	for i, r in ipairs(cross.ROADS) do roads[i] = r.label end
	local own = { "Same" }
	for i, r in ipairs(cross.ROADS) do own[i + 1] = r.label end
	local angles = {}
	for i, a in ipairs(cross.ANGLES) do angles[i] = tostring(a) end
	return {
		description = {
			name = "Stress Test crossing",
			description = "A plain street crossing of two roads, built by the Stress Test window.",
		},
		params = {
			{ key = cross.KEYS.shape, name = "Shape", uiType = "Button", values = cross.SHAPES, defaultIndex = 1 },
			{ key = cross.KEYS.main, name = "Main road", uiType = "ComboBox", values = roads, defaultIndex = 3 },
			{ key = cross.KEYS.side, name = "Side road", uiType = "ComboBox", values = roads, defaultIndex = 2 },
			{ key = cross.KEYS.angle, name = "Side road angle", uiType = "ComboBox", values = angles, defaultIndex = 1 },
			{ key = cross.KEYS.main2, name = "Main road, east arm", uiType = "ComboBox", values = own, defaultIndex = 1 },
			{ key = cross.KEYS.side2, name = "Side road, second arm", uiType = "ComboBox", values = own, defaultIndex = 1 },
			{ key = cross.KEYS.lights, name = "Traffic light", uiType = "Button", values = cross.LIGHTS, defaultIndex = 1 },
		},
		updateScript = {
			fileName = "square_stress_test_crossing.script@updateFn",
			params = {},
		},
	}
end
