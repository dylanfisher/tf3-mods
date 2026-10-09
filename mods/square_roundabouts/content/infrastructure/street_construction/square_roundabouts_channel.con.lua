-- Better Roundabouts: "Channelized Junction", a separate menu entry (none of the ring params apply).
-- A T or X junction with one-way slip lanes across its corners, triangle islands and optional
-- splitter islands on the side road. Every node is freed, so after placement it is ordinary,
-- editable streets built from base templates.
-- Geometry: square_roundabouts_channel.lua; result table: square_roundabouts_result.lua via
-- square_roundabouts_channel.script.lua.

local channel = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_channel.lua"

local K = channel.PARAM_KEYS

local function metres(list)
	local out = {}
	for i = 1, #list do out[i] = tostring(list[i]) .. " m" end
	return out
end

local ROADS = {
	_("Town, small"), _("Town, medium"), _("Town, large"),
	_("Country, small"), _("Country, medium"), _("Country, large"),
}

function data()
return {
	configureLayerScript = {
		fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
		params = {
			heightmapContours = true,
		},
	},
	configureHudIconsScript = {
		fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStreetConstructionHudIconsFn",
	},
	description = {
		name = _("Channelized Junction"),
		description = _("A T or X junction with one-way slip lanes that bypass it across the corners, triangle islands between them and optional splitter islands on the side road. Choose the main and side road, which turns get a slip lane and the traffic side. Once built, everything is ordinary roads you can edit or connect."),
		-- own menu icon: square_roundabouts_channel@2x.tga (240x150), rendered by tools/render_icon_square_roundabouts.py
		icon = "square_roundabouts_channel.tga",
		-- hover preview: the main entry's for now (replace with an in-game capture, PHASE5.md 5e)
		previewIcon = "square_roundabouts_channel_preview.tga",
	},
	-- As early as the templates allow (PHASE5.md "Phase 5a notes"): the slip lanes need a one-way
	-- template (town_new_one_way_*, 1940) and the new-era roads exist from 1940; two-way slip lanes
	-- on the old roads would defeat the point. tests/square_roundabouts/test_short_edges.lua checks
	-- this year against every template the updateFn emits.
	availability = {
		yearFrom = 1940,
	},
	soundConfig = {
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
	},
	menuCategory = {
		categories = {
			{
				category = "street_constructions",
				order = 3012,
			},
		},
	},
	-- No checkEnabledScript (PLAN.md Phase 2a): every param applies to every layout. Without slip
	-- lanes and splitter islands, Islands and Traffic side change nothing (the accepted precedent of
	-- Arm road with Arms None).
	params = {
		{
			key = K.layout,
			name = _("Layout"),
			tooltip = _("T: a side road on one side of the main road.\nX: side roads on both sides."),
			uiType = "Button",
			values = { _("T"), _("X") },
			defaultIndex = channel.LAYOUT_T,
		},
		{
			key = K.main,
			name = _("Main road"),
			tooltip = _("Road type of the main road (the straight one through the junction)."),
			uiType = "ComboBox",
			values = ROADS,
			defaultIndex = channel.DEFAULT_MAIN,
		},
		{
			key = K.side,
			name = _("Side road"),
			tooltip = _("Road type of the side road(s)."),
			uiType = "ComboBox",
			values = ROADS,
			defaultIndex = channel.DEFAULT_SIDE,
		},
		{
			key = K.slips,
			name = _("Slip lanes"),
			tooltip = _("One-way lanes that bypass the junction across a corner.\nNear-side corners: the short turns (right turns in\nright-hand traffic, left turns in left-hand traffic).\nAll turns off the main road: every turn from the main road\nonto the side road. Wider roads set the lanes further out,\nat a steeper angle (wide roads: a wider one-way road)."),
			uiType = "Button",
			values = { _("Near-side corners"), _("All turns off the main road"), _("None") },
			defaultIndex = channel.SLIPS_NEAR,
		},
		{
			key = K.splitter,
			name = _("Side-road splitter islands"),
			tooltip = _("Splits each side road into a one-way entry and exit lane\nwhere it meets the main road. With slip lanes the junction\ngets much larger: they join the side road beyond the split."),
			uiType = "Button",
			values = { _("Off"), _("On") },
			defaultIndex = channel.SPLITTER_OFF,
		},
		{
			key = K.armLength,
			name = _("Arm length"),
			tooltip = _("How far each road runs on beyond the junction's\noutermost node (slip lane or splitter)."),
			uiType = "Slider",
			values = metres(channel.ARM_LENGTHS),
			defaultIndex = channel.DEFAULT_ARM_LENGTH,
		},
		{
			key = K.direction,
			name = _("Traffic side"),
			tooltip = _("Which side the slip lanes and splitter lanes are built for."),
			uiType = "Button",
			values = { _("Right-hand traffic"), _("Left-hand traffic") },
			defaultIndex = 1,
		},
		{
			key = K.island,
			name = _("Islands"),
			tooltip = _("Surface of the triangle islands between the slip lanes\nand the corners, and of the splitter islands."),
			uiType = "Button",
			values = { _("None"), _("Grass"), _("Paved") },
			defaultIndex = 1,
		},
	},
	updateScript = {
		fileName = "square_roundabouts_channel.script@updateFn",
		params = {},
	},
}
end
