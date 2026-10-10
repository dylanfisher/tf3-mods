-- Better Roundabouts: "Roundabout Interchange", a separate menu entry. A highway (two one-way
-- carriageways) crossed by a roundabout junction on another level: a ring over the highway on
-- two bridges, two rings joined by a bridge (dumbbell) or a peanut-shaped loop, with four one-way
-- slip roads like the base diamond interchange. Every node is freed, so after placement it is
-- ordinary, editable streets and bridges built from base templates.
-- Geometry: square_roundabouts_interchange.lua; result table: square_roundabouts_result.lua via
-- square_roundabouts_interchange.script.lua.

local ix = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_interchange.lua"

local K = ix.PARAM_KEYS

local function metres(list)
	local out = {}
	for i = 1, #list do out[i] = tostring(list[i]) .. " m" end
	return out
end

-- Radius preset buttons (Phase 7c3, ix.RADIUS_PRESETS) and the tooltip's "S 15 m, ..."
local function presetNames()
	local out = {}
	for i = 1, #ix.RADIUS_PRESET_NAMES do out[i] = _(ix.RADIUS_PRESET_NAMES[i]) end
	return out
end

local function presets()
	local out = {}
	for i, ri in ipairs(ix.RADIUS_PRESETS) do out[i] = _(ix.RADIUS_PRESET_NAMES[i]) .. " " .. ix.RADII[ri] .. " m" end
	return table.concat(out, ", ")
end

local ROADS = {
	_("Town, small"), _("Town, medium"), _("Town, large"),
	_("Country, small"), _("Country, medium"), _("Country, large"),
}

-- Every param sits in the left toolbar (location "Toolbar", 2026-10-09: the menu's hover tooltip no
-- longer covers the settings there). Its buttons fit about 6 characters: button rows have at most 5
-- labels of at most 6 characters (tested), longer choices are ComboBoxes, tooltips explain them.
local function toolbar(con)
	for _, p in ipairs(con.params) do p.location = "Toolbar" end
	return con
end

function data()
return toolbar({
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
		name = _("Roundabout Interchange"),
		description = _("A highway crossed by a roundabout junction on another level, with four slip roads. Two-bridge ring: one ring over the highway on two bridges. Dumbbell: a ring each side, joined by a bridge. Peanut: one loop with two lobes and a narrow waist of two one-way bridges. Once built, everything is ordinary roads and bridges you can edit or connect."),
		-- own menu icon: square_roundabouts_interchange@2x.tga (240x150), rendered by tools/render_icon_square_roundabouts.py
		icon = "square_roundabouts_interchange.tga",
		-- hover preview: the main entry's for now (replace with an in-game capture, PHASE5.md 5e)
		previewIcon = "square_roundabouts_interchange_preview.tga",
	},
	-- As early as the templates allow (PHASE5.md "Phase 5a notes"): the highway, slip road and
	-- one-way ring templates and the steel bridge exist from 1940 (the base interchanges unlock in
	-- 1960). tests/square_roundabouts/test_short_edges.lua checks this year against every template
	-- and bridge the updateFn emits before 1970 (concrete bridges from 1970).
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
				order = 3013,
			},
		},
	},
	-- No checkEnabledScript (PLAN.md Phase 2a): every param applies to every layout. Radius is a
	-- minimum (the rings grow to fit, as on the main entry); Centre island None adds nothing.
	params = {
		{
			key = K.layout,
			name = _("Layout"),
			tooltip = _("Two-bridge ring: one ring around the highway,\ncrossing it on two bridges.\nDumbbell: a ring on each side, joined by a two-way bridge.\nPeanut: one one-way loop with a lobe on each side;\nits narrow waist is two one-way bridges."),
			uiType = "ComboBox",
			values = { _("Two-bridge ring"), _("Dumbbell"), _("Peanut") },
			defaultIndex = ix.LAYOUT_TWO_BRIDGE,
		},
		{
			key = K.highway,
			name = _("Highway"),
			tooltip = _("Highway type, built as two one-way carriageways.\nS, M, L: small, medium, large highway\n(1, 2 or 3 lanes each way)."),
			uiType = "Button",
			values = { _("S"), _("M"), _("L") },
			defaultIndex = ix.DEFAULT_HIGHWAY,
		},
		{
			key = K.level,
			name = _("On top"),
			tooltip = _("Which one crosses over the other.\nRing: the roundabout 8 m up, on bridges where it\ncrosses, the highway at ground level.\nHwy: the highway 8 m up, on a bridge across the\nroundabout at ground level.\nThe slip roads climb the 8 m."),
			uiType = "Button",
			values = { _("Ring"), _("Hwy") },
			defaultIndex = ix.LEVEL_RING_OVER,
		},
		{
			key = K.lanes,
			name = _("Ring lanes"),
			tooltip = _("Lanes on the one-way ring road"),
			uiType = "Button",
			values = { "1", "2", "4" },
			defaultIndex = 2,
		},
		{
			-- Phase 7c3: presets on their own key (ix.RADIUS_PRESET_KEY), not the old slider's
			key = ix.RADIUS_PRESET_KEY,
			name = _("Radius"),
			tooltip = _("Radius inside the ring road (each ring or lobe),\nsmall to extra large: ") .. presets() ..
				_(".\nA minimum: the rings grow if the roads don't fit.\nThe two-bridge ring must span the highway, so it\nstarts at 25-40 m (with 4 lanes: 35-55 m)."),
			uiType = "Button",
			displayMode = "Horizontal",
			values = presetNames(),
			defaultIndex = ix.DEFAULT_RADIUS_PRESET, -- S, the smallest (user 2026-10-09)
		},
		{
			key = K.cross,
			name = _("Cross road"),
			tooltip = _("Road type of the two-way road across the highway\n(its two arms, and the dumbbell's bridge)."),
			uiType = "ComboBox",
			values = ROADS,
			defaultIndex = ix.DEFAULT_CROSS,
		},
		{
			key = K.slipLength,
			name = _("Slip road length"),
			tooltip = _("Distance along the highway from a slip road's ring\nnode to where it joins the highway. Shorter is steeper\n(120 m: at most 9 % on average; the base diamond\ngoes up to 10.5 %)."),
			uiType = "Button",
			displayMode = "Horizontal",
			values = metres(ix.SLIP_LENGTHS),
			defaultIndex = ix.DEFAULT_SLIP_LENGTH,
		},
		{
			key = K.armLength,
			name = _("Arm length"),
			tooltip = _("How far the cross road runs on beyond the ring,\nand the highway beyond the slip roads."),
			uiType = "Button",
			displayMode = "Horizontal",
			values = metres(ix.ARM_LENGTHS),
			defaultIndex = ix.DEFAULT_ARM_LENGTH,
		},
		{
			key = K.direction,
			name = _("Traffic side"),
			tooltip = _("Right: right-hand traffic, rings counterclockwise.\nLeft: left-hand traffic, everything mirrored,\nrings clockwise."),
			uiType = "Button",
			values = { _("Right"), _("Left") },
			defaultIndex = 1,
		},
		{
			key = K.island,
			name = _("Centre island"),
			tooltip = _("Inside each ring (the two-bridge ring: either side of\nthe highway). The islands stay at ground level."),
			uiType = "ComboBox",
			values = { _("None"), _("Grass"), _("Grass and trees"), _("Fountain"), _("Paved") },
			defaultIndex = 1,
		},
	},
	updateScript = {
		fileName = "square_roundabouts_interchange.script@updateFn",
		params = {},
	},
})
end
