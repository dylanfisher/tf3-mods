-- Better Roundabouts: a configurable roundabout stamp. Like the base roundabout
-- (base infrastructure/street_construction/roundabout.con.lua) every node is freed, so after
-- placement the ring and arms are ordinary, editable streets built from base templates.
-- Geometry: square_roundabouts_geometry.lua; result table: square_roundabouts_result.lua via
-- square_roundabouts.script.lua. The Magic Roundabout is a separate entry
-- (square_roundabouts_magic.con.lua) because none of the ring params apply to it.

local geom = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"

local K = geom.PARAM_KEYS

local function metres(list, suffix)
	local out = {}
	for i = 1, #list do out[i] = tostring(list[i]) .. (suffix or " m") end
	return out
end

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

local function shapes(list)
	local out = {}
	for i = 1, #list do
		out[i] = list[i] == 1 and _("Round") or string.format(_("Oval %.2f : 1"), list[i])
	end
	return out
end

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
		name = _("Better Roundabouts"),
		description = _("A roundabout with approach roads, optional splitter islands, a road or tram line through the centre, tram tracks and a centre island. Choose the shape, lanes, size, arms, arm road and traffic direction. Once built, everything is ordinary roads you can edit or connect."),
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
			uiType = "Slider",
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
			key = K.radius,
			name = _("Radius"),
			tooltip = _("Size of the roundabout: the radius inside the ring road\n(the narrow side of an oval). Below 15 m: a mini roundabout\nwith a flat island. The ring grows if the chosen roads\ndon't fit."),
			uiType = "Slider",
			values = metres(geom.RADII),
			defaultIndex = geom.DEFAULT_RADIUS,
		},
		{
			key = K.arms,
			name = _("Arms"),
			uiType = "Button",
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
			uiType = "Button",
			-- appended values only: saved indices keep their meaning
			values = { _("Nothing"), _("Road"), _("Tram line"), _("Road + traffic lights") },
			tooltips = {
				_("No road through the island"),
				_("A road straight across the island"),
				_("Tram tracks straight across the island"),
				_("Experimental: a road across the island with traffic lights\nwhere it crosses the ring (from 1950). The two crossings ask\nin two different ways, to find out which one the game uses."),
			},
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
			uiType = "Button",
			values = { _("Counterclockwise"), _("Clockwise") },
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
			tooltip = _("Experimental: traffic lights where traffic enters the ring\n(from 1950). Odd and even arms ask in two different ways,\nto find out which one the game uses."),
			uiType = "Button",
			values = { _("Off"), _("Entries (experimental)") },
			defaultIndex = geom.SIGNALS_OFF,
		},
	},
	updateScript = {
		fileName = "square_roundabouts.script@updateFn",
		params = {},
	},
}
end
