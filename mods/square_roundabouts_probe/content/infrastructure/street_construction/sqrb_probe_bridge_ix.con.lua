-- DEV ONLY (never upload): "DEV SQRB Bridge probe: Roundabout Interchange" (square_roundabouts_probe).
-- The Roundabout Interchange's geometry (square_roundabouts_interchange.build, unchanged) with the two
-- probe params of sqrb_probe_bridge.lua (Probe structure, Probe islands). Its own bridges keep their
-- type in Bridge mode; every other road becomes a bridge. plans/square_roundabouts/PROBE.md
-- "Phase 8: bridge probe".
--
-- Params: every param of square_roundabouts_interchange.con.lua (same keys, values and 1-based
-- defaults, except Centre island: Grass, so Probe islands has islands to drop), then the two probe
-- params. English only (DEV).

local ix = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_interchange.lua"
local bridge = ug_require "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_bridge.lua"

local K = ix.PARAM_KEYS
local ROADS = { "Town, small", "Town, medium", "Town, large", "Country, small", "Country, medium", "Country, large" }

local function metres(list)
	local out = {}
	for i = 1, #list do out[i] = tostring(list[i]) .. " m" end
	return out
end

local function presets()
	local out = {}
	for i, n in ipairs(ix.RADIUS_PRESET_NAMES) do out[i] = n end
	return out
end

local function toolbar(con)
	for _, p in ipairs(con.params) do p.location = "Toolbar" end
	return con
end

function data()
	local params = {
		{ key = K.layout, name = "Layout", uiType = "ComboBox", values = { "Two-bridge ring", "Dumbbell", "Peanut" }, defaultIndex = ix.LAYOUT_TWO_BRIDGE },
		{ key = K.highway, name = "Highway", uiType = "Button", values = { "S", "M", "L" }, defaultIndex = ix.DEFAULT_HIGHWAY },
		{ key = K.level, name = "On top", tooltip = "Ring: the roundabout 8 m up.\nHwy: the highway 8 m up.",
			uiType = "Button", values = { "Ring", "Hwy" }, defaultIndex = ix.LEVEL_RING_OVER },
		{ key = K.lanes, name = "Ring lanes", uiType = "Button", values = { "1", "2", "4" }, defaultIndex = 2 },
		{ key = ix.RADIUS_PRESET_KEY, name = "Scale", tooltip = "S 15 m, M 20 m, L 30 m, XL 45 m",
			uiType = "Button", displayMode = "Horizontal", values = presets(), defaultIndex = ix.DEFAULT_RADIUS_PRESET },
		{ key = K.cross, name = "Cross road", uiType = "ComboBox", values = ROADS, defaultIndex = ix.DEFAULT_CROSS },
		{ key = K.slipLength, name = "Slip road length", uiType = "Button", displayMode = "Horizontal",
			values = metres(ix.SLIP_LENGTHS), defaultIndex = ix.DEFAULT_SLIP_LENGTH },
		{ key = K.armLength, name = "Arm length", uiType = "Button", displayMode = "Horizontal",
			values = metres(ix.ARM_LENGTHS), defaultIndex = ix.DEFAULT_ARM_LENGTH },
		{ key = K.direction, name = "Traffic side", uiType = "Button", values = { "Right", "Left" }, defaultIndex = 1 },
		{ key = K.island, name = "Centre island", uiType = "ComboBox",
			values = { "None", "Grass", "Grass and trees", "Fountain", "Paved" }, defaultIndex = 2 },
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
			name = _("DEV SQRB Bridge probe: Roundabout Interchange (NOT FOR UPLOAD)"),
			description = _("DEV ONLY - NOT FOR UPLOAD. The Roundabout Interchange with Probe structure (Embankment / Bridge / No align / Bridge + no align) and Probe islands. Raise it with Height and compare. plans/square_roundabouts/PROBE.md Phase 8."),
			-- base icons (the main mod's own .tga live in another mod's folder)
			icon = "::/infrastructure/street_construction/diamond_interchange.tga",
			previewIcon = "::/infrastructure/street_construction/diamond_interchange_preview.tga",
		},
		availability = { yearFrom = 1940 },
		soundConfig = {
			builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
		},
		-- beside the real entries: before the Roundabout Interchange (3013)
		menuCategory = { categories = { { category = "street_constructions", order = 3012 } } },
		params = params,
		updateScript = {
			fileName = "sqrb_probe_bridge.script@updateFnIx",
			params = {},
		},
	})
end
