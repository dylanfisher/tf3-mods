-- DEV ONLY (never upload): "DEV SQRB Bridge probe: Roundabout" (square_roundabouts_probe). The main
-- Better Roundabouts entry's geometry (square_roundabouts_geometry.build, unchanged) with two probe
-- params: Probe structure (Embankment / Bridge / No align / Bridge + no align) and Probe islands
-- (Keep / Drop). Place it raised with the game's Height control and compare the modes:
-- plans/square_roundabouts/PROBE.md "Phase 8: bridge probe". Post-processing: sqrb_probe_bridge.lua.
--
-- Params: the main entry's (same keys, values and 1-based defaults as square_roundabouts.con.lua)
-- except Through the centre, Through road, Tram tracks and Traffic lights (readParams defaults:
-- nothing through the centre, no tram, no lights) and Centre island defaults to Grass (so Probe
-- islands has islands to drop), then the two probe params. English only (DEV).

local geom = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"
local bridge = ug_require "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_bridge.lua"

local K = geom.PARAM_KEYS

local function shapes()
	local out = {}
	for i, r in ipairs(geom.SHAPE_RATIOS) do out[i] = r == 1 and "Round" or (string.format("%g", r) .. ":1") end
	return out
end

local function presets()
	local out = {}
	for i, n in ipairs(geom.RADIUS_PRESET_NAMES) do out[i] = n end
	return out
end

local function toolbar(con)
	for _, p in ipairs(con.params) do p.location = "Toolbar" end
	return con
end

function data()
	local params = {
		{ key = K.shape, name = "Shape", uiType = "Button", displayMode = "Horizontal", values = shapes(), defaultIndex = geom.SHAPE_ROUND },
		{ key = K.lanes, name = "Ring lanes", uiType = "Button", values = { "1", "2", "4" }, defaultIndex = 2 },
		{ key = geom.RADIUS_PRESET_KEY, name = "Scale", tooltip = "XS 10 m, S 15 m, M 20 m, L 35 m, XL 60 m",
			uiType = "Button", displayMode = "Horizontal", values = presets(), defaultIndex = geom.DEFAULT_RADIUS_PRESET },
		{ key = K.arms, name = "Arms", uiType = "ComboBox", values = { "3 (T)", "3 (Y)", "4", "5", "6", "None" }, defaultIndex = 3 },
		{ key = K.splitter, name = "Splitter islands", uiType = "Button", values = { "Off", "On" }, defaultIndex = geom.SPLITTER_OFF },
		{ key = K.armType, name = "Arm road", uiType = "ComboBox",
			values = { "Town, small", "Town, medium", "Town, large", "Country, small", "Country, medium", "Country, large" }, defaultIndex = 1 },
		{ key = K.direction, name = "Direction", uiType = "Button", values = { "CCW", "CW" }, defaultIndex = geom.DIRECTION_CCW },
		{ key = K.island, name = "Centre island", uiType = "ComboBox",
			values = { "None", "Grass", "Grass and trees", "Fountain", "Paved" }, defaultIndex = geom.ISLAND_GRASS },
	}
	for _, p in ipairs(bridge.params()) do params[#params + 1] = p end
	return toolbar({
		configureLayerScript = {
			fileName = "::/gui/construction/construction_desc_layers.script@configureDefaultLayerFn",
			params = { heightmapContours = true },
		},
		configureHudIconsScript = {
			fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStreetConstructionHudIconsFn",
		},
		description = {
			name = _("DEV SQRB Bridge probe: Roundabout (NOT FOR UPLOAD)"),
			description = _("DEV ONLY - NOT FOR UPLOAD. Better Roundabouts with Probe structure (Embankment / Bridge / No align / Bridge + no align) and Probe islands. Raise it with Height and compare. plans/square_roundabouts/PROBE.md Phase 8."),
			-- base icons (the main mod's own .tga live in another mod's folder)
			icon = "::/infrastructure/street_construction/roundabout.tga",
			previewIcon = "::/infrastructure/street_construction/roundabout_preview.tga",
		},
		availability = { yearFrom = 1940 },
		soundConfig = {
			builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
		},
		-- beside the real entries: after Better Roundabouts (3010), before the Roundabout Interchange (3013)
		menuCategory = { categories = { { category = "street_constructions", order = 3011 } } },
		params = params,
		updateScript = {
			fileName = "sqrb_probe_bridge.script@updateFn",
			params = {},
		},
	})
end
