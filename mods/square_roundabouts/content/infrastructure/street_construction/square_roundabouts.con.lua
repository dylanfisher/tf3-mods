-- Better Roundabouts: a configurable roundabout stamp. Like the base roundabout
-- (base infrastructure/street_construction/roundabout.con.lua) every node is freed, so after
-- placement the ring and arms are ordinary, editable streets built from base templates.
-- Geometry: square_roundabouts_geometry.lua; result table: square_roundabouts_result.lua via
-- square_roundabouts.script.lua. The Magic Roundabout is a separate entry
-- (square_roundabouts_magic.con.lua) because none of the ring params apply to it.

local geom = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"
local result = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_result.lua"

local K = geom.PARAM_KEYS

-- Arm road names, in geom.ARM_TEMPLATES order (Arm road and Through road)
local function armRoads()
	return {
		_("Town, small"), _("Town, medium"), _("Town, large"),
		_("Country, small"), _("Country, medium"), _("Country, large"),
	}
end

local function throughRoads()
	local out, roads = { _("Same as arms") }, armRoads()
	for i = 1, #roads do out[i + 1] = roads[i] end
	return out
end

-- Phase 7c3: button labels (a row like the base interchanges'): Round, then the oval ratios
local function shapes(list)
	local out = {}
	for i = 1, #list do
		out[i] = list[i] == 1 and _("Round") or (string.format("%g", list[i]) .. ":1")
	end
	return out
end

-- Radius preset buttons (geom.RADIUS_PRESETS): size codes XS / S / M / L / XL, the same in every
-- language (the tooltip explains them; it lists their radii as one translatable text, so
-- tests/square_roundabouts/test_menu_labels.lua checks it against geom.RADII).
local function presetNames(names)
	local out = {}
	for i = 1, #names do out[i] = names[i] end
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
		name = _("Better Roundabouts"),
		description = _("A roundabout with approach roads, optional splitter islands, a road or tram line through the centre, tram tracks and a centre island. Choose the shape, lanes, scale, arms, arm road and traffic direction. Once built, everything is ordinary roads you can edit or connect."),
		-- own menu icon: square_roundabouts@2x.tga (240x150), rendered by tools/render_icon_square_roundabouts.py
		icon = "square_roundabouts.tga",
		-- own hover preview: square_roundabouts_preview@2x.tga (720x405), rendered by tools/render_preview_square_roundabouts.py
		previewIcon = "square_roundabouts_preview.tga",
	},
	-- As early as the templates allow (PHASE5.md "Phase 5a notes"): the one-way ring templates
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
				order = 3010,
			},
		},
	},
	-- No checkEnabledScript: the base params panel does not refresh a greyed-out state until the
	-- menu is reopened, so every param here means something for every value of the others
	-- (PLAN.md Phase 2a and Phase 3 notes).
	params = {
		{
			key = K.shape,
			name = _("Shape"),
			tooltip = _("Round, or an oval stretched along its length (length : width)"),
			uiType = "Button",
			displayMode = "Horizontal",
			values = shapes(geom.SHAPE_RATIOS),
			defaultIndex = geom.SHAPE_ROUND,
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
			-- Phase 7c3: presets on their own key (geom.RADIUS_PRESET_KEY), not the old slider's
			key = geom.RADIUS_PRESET_KEY,
			name = _("Scale"),
			tooltip = _("Size of the roundabout, extra small to extra large:\nthe radius inside the ring road (the narrow side of\nan oval): XS 10 m, S 15 m, M 20 m, L 35 m, XL 60 m.\nXS: a mini roundabout with a flat island. The ring\ngrows if the chosen roads don't fit."),
			uiType = "Button",
			displayMode = "Horizontal",
			values = presetNames(geom.RADIUS_PRESET_NAMES),
			defaultIndex = geom.DEFAULT_RADIUS_PRESET, -- XS, the smallest (user 2026-10-09)
		},
		{
			key = K.arms,
			name = _("Arms"),
			tooltip = _("Number of approach roads. 3 (T): a T junction,\n3 (Y): three evenly spaced. None: just the ring."),
			uiType = "ComboBox",
			values = { _("3 (T)"), _("3 (Y)"), "4", "5", "6", _("None") },
			defaultIndex = 3,
		},
		{
			key = K.splitter,
			name = _("Splitter islands"),
			tooltip = _("Splits each arm into a one-way entry and exit lane.\nAdds a small island between them if a centre island is set.\nThe ring grows if the lanes don't fit."),
			uiType = "Button",
			values = { _("Off"), _("On") },
			defaultIndex = geom.SPLITTER_OFF,
		},
		{
			key = K.armType,
			name = _("Arm road"),
			tooltip = _("Road type of the approach arms (30 m long).\nWide roads may make the ring grow\nor the splitter islands spread wider."),
			uiType = "ComboBox",
			values = armRoads(),
			defaultIndex = 1,
		},
		{
			key = K.centre,
			name = _("Through the centre"),
			tooltip = _("A straight road or tram line across the island,\nbetween two opposite arms.\nLayouts without opposite arms get one extra arm.\nTram line: tracks run only along that straight line\n(its two arms and across), not on the ring.\nRoad + traffic lights (experimental): lights where\nthe road crosses the ring (from 1950)."),
			uiType = "ComboBox",
			-- appended values only: saved indices keep their meaning
			values = { _("Nothing"), _("Road"), _("Tram line"), _("Road + traffic lights") },
			defaultIndex = geom.CENTRE_NONE,
		},
		{
			key = K.throughRoad,
			name = _("Through road"),
			tooltip = _("Road type of the road through the centre\n(Road, Road + traffic lights), so a larger road can\ncut through the roundabout. The ring grows if it\ndoesn't fit."),
			uiType = "ComboBox",
			values = throughRoads(),
			defaultIndex = geom.THROUGH_SAME,
		},
		{
			key = K.tram,
			name = _("Tram tracks"),
			tooltip = _("Electrified tram tracks on the ring, every arm,\nthe splitter lanes and a through road."),
			uiType = "Button",
			values = { _("Off"), _("On") },
			defaultIndex = geom.TRAM_OFF,
		},
		{
			key = K.direction,
			name = _("Direction"),
			tooltip = _("CCW: counterclockwise, for right-hand traffic.\nCW: clockwise, for left-hand traffic."),
			uiType = "Button",
			values = { _("CCW"), _("CW") },
			tooltips = { _("Right-hand traffic"), _("Left-hand traffic") },
			defaultIndex = 1,
		},
		{
			key = K.island,
			name = _("Centre island"),
			tooltip = _("Also used for the splitter islands.\nMini roundabouts (below 15 m) get a flat island:\ntrees and fountain become paving."),
			uiType = "ComboBox",
			values = { _("None"), _("Grass"), _("Grass and trees"), _("Fountain"), _("Paved") },
			defaultIndex = 1,
		},
		{
			key = K.signals,
			name = _("Traffic lights"),
			tooltip = _("Experimental. On: traffic lights where traffic enters\nthe ring (from 1950). Odd and even arms ask in two different ways,\nto find out which one the game uses."),
			uiType = "Button",
			values = { _("Off"), _("On") },
			defaultIndex = geom.SIGNALS_OFF,
		},
		-- last on every entry (square_roundabouts_result.lua "Structure")
		result.structureParam(_),
	},
	updateScript = {
		fileName = "square_roundabouts.script@updateFn",
		params = {},
	},
})
end
