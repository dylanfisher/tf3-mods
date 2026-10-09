-- DEV ONLY (never upload): "DEV Probe: pre-1940 one-way" (square_roundabouts_probe). Answers
-- TESTING.md 11.2: does base `constructions/entrance_old_one_way.street_template` (the only
-- one-way template before 1940; the modular street station's entrance, never freed in base) place
-- as a construction's freed edge, and do the placed edges behave as ordinary one-way streets?
-- A straight one-way road, a one-way ring, or the ring with four old two-way arms (a pre-1940
-- roundabout). Geometry: sqrb_probe_old_one_way.lua; result: square_roundabouts_result.lua.

local shape = ug_require "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_old_one_way.lua"

function data()
return {
	description = {
		name = _("DEV Probe: pre-1940 one-way (NOT FOR UPLOAD)"),
		description = _("DEV ONLY - NOT FOR UPLOAD. Builds base entrance_old_one_way / entrance_new_one_way edges as freed streets: a straight road, a ring, or a ring with four old two-way arms. plans/square_roundabouts/TESTING.md 11.2."),
		icon = "::/infrastructure/street/constructions/entrance_old_one_way.tga",
		previewIcon = "::/infrastructure/street/constructions/entrance_old_one_way_preview.tga",
	},
	-- every year: the point is a pre-1940 save
	availability = {
		yearFrom = 0,
		yearTo = 0,
	},
	menuCategory = {
		categories = {
			{
				category = "street_constructions",
				order = 3099,
			},
		},
	},
	params = {
		{
			key = shape.KEYS.layout,
			name = _("Layout"),
			uiType = "Button",
			values = { _("Straight"), _("Ring"), _("Ring + old arms") },
			defaultIndex = 3,
		},
		{
			key = shape.KEYS.template,
			name = _("One-way template"),
			uiType = "Button",
			values = { "entrance_old_one_way", "entrance_new_one_way" },
			defaultIndex = 1,
		},
	},
	updateScript = {
		fileName = "sqrb_probe_old_one_way.script@updateFn",
		params = {},
	},
}
end
