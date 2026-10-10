-- Better Roundabouts: "Magic Roundabout", a separate menu entry (none of the main entry's ring
-- params apply to it, and without checkEnabledScript every param must always mean something).
-- Five mini roundabouts on a two-way central ring, after Swindon's Magic Roundabout. Every node is
-- freed, so after placement it is ordinary, editable streets built from base templates.
-- Geometry: square_roundabouts_magic.lua; result table: square_roundabouts_result.lua via
-- square_roundabouts_magic.script.lua.

local magic = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_magic.lua"

local K = magic.PARAM_KEYS

local function sizes()
	local out = {}
	for i = 1, #magic.SIZES do
		out[i] = _(magic.SIZE_NAMES[i])
	end
	return out
end

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
		name = _("Magic Roundabout"),
		description = _("Five mini roundabouts around a two-way central ring, like Swindon's Magic Roundabout: traffic can go round either way. Each mini roundabout has one approach road; Size scales the whole layout. Once built, everything is ordinary roads you can edit or connect."),
		-- own menu icon: square_roundabouts_magic@2x.tga (240x150), rendered by tools/render_icon_square_roundabouts.py
		icon = "square_roundabouts_magic.tga",
		-- own hover preview: square_roundabouts_magic_preview@2x.tga (720x405), rendered by tools/render_preview_square_roundabouts.py
		previewIcon = "square_roundabouts_magic_preview.tga",
	},
	-- As early as the templates allow (PHASE5.md "Phase 5a notes"): the mini roundabouts' one-way templates
	-- (highway_new_small, town_new_one_way_*) and the new-era arm roads exist from 1940; there is no
	-- pre-1940 one-way road template in the street menu. tests/square_roundabouts/test_short_edges.lua
	-- checks this year against every template the updateFn emits.
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
				order = 3011,
			},
		},
	},
	-- No checkEnabledScript (PLAN.md Phase 2a): every param applies to every layout.
	params = {
		{
			key = K.size,
			name = _("Size"),
			tooltip = _("Size of the whole layout, extra small to extra large:\nthe mini roundabouts (XS 8 m, S 10 m, M 12 m, L 20 m,\nXL 35 m radius) and the central ring between them.\nIt grows if the arm road doesn't fit."),
			uiType = "Button",
			displayMode = "Horizontal",
			values = sizes(),
			defaultIndex = magic.DEFAULT_SIZE, -- XS, the smallest (user 2026-10-09)
		},
		{
			key = K.armType,
			name = _("Arm road"),
			tooltip = _("Road type of the five approach arms (30 m long).\nWide roads may need a larger size."),
			uiType = "ComboBox",
			values = {
				_("Town, small"), _("Town, medium"), _("Town, large"),
				_("Country, small"), _("Country, medium"), _("Country, large"),
			},
			defaultIndex = 1,
		},
		{
			key = K.lanes,
			name = _("Mini roundabout lanes"),
			tooltip = _("Lanes on each one-way mini roundabout.\n2 lanes need size L or bigger: smaller sizes grow to L.\nThe central ring keeps one lane each way."),
			uiType = "Button",
			values = { "1", "2" },
			defaultIndex = 1,
		},
		{
			key = K.direction,
			name = _("Direction"),
			tooltip = _("Direction of the mini roundabouts. CCW: counterclockwise,\nfor right-hand traffic. CW: clockwise, for left-hand traffic.\nThe central ring is two-way: its inner lane runs the other way."),
			uiType = "Button",
			values = { _("CCW"), _("CW") },
			tooltips = { _("Right-hand traffic"), _("Left-hand traffic") },
			defaultIndex = 1,
		},
		{
			key = K.island,
			name = _("Centre island"),
			tooltip = _("Island inside the central ring and the mini roundabouts.\nMini roundabouts below 15 m get a flat island:\ntrees and fountain become paving."),
			uiType = "ComboBox",
			values = { _("None"), _("Grass"), _("Grass and trees"), _("Fountain"), _("Paved") },
			defaultIndex = 1,
		},
	},
	updateScript = {
		fileName = "square_roundabouts_magic.script@updateFn",
		params = {},
	},
})
end
