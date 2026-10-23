-- Better Roundabouts: the three Highway Interchange menu entries (INTERCHANGES.md "Phase 7c2 notes",
-- "Phase 7c3 notes"): "Parclo" (A4 / B4), "Parclo, two quadrants" (A2 / B2 / AB2) and "Diamond",
-- menu orders 3014-3016: right after our Roundabout Interchange (3013), before every base
-- interchange (T / trumpet 5000, cloverleaf 6000, diverging diamond 6001, diamond 7000; user
-- request 2026-10-14; were 6002 / 6003 / 7001 beside the base ones). Each
-- square_roundabouts_highway_<id>.con.lua is `return menu.data("<id>", _)`. The A / B mirrors are a "Layout" button row (hx.LAYOUT_KEY); the
-- entry's updateScript params carry its types (captureParams.types, hx.specFor). Every setting is a
-- button row like the base interchanges' (displayMode "Horizontal"), except the cross road (six road
-- types, a ComboBox as on the other entries). Every param applies to every type (tested), so no
-- checkEnabledScript (PLAN.md Phase 2a). Every param sits in the left toolbar (location "Toolbar",
-- 2026-10-09: the menu's hover tooltip no longer covers the settings there); its buttons fit about
-- 6 characters, so labels are short (S / M / L) and the tooltips explain them.
-- Pure data (no api.*); the translation function comes from the .con.lua (its `_`).

local hx = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_highway.lua"
local result = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_result.lua"

local K = hx.PARAM_KEYS
local menu = {}

-- The entries: file stem (square_roundabouts_highway_<id>), menu name, order, the description's
-- description, the types (hx.TYPE_*) behind the Layout buttons (one type: no Layout row), the
-- button labels (type codes, the same in every language) and the Layout tooltip. name, description
-- and layoutTip are translation keys (strings.json; `_(e.name)` below returns the key, the game
-- translates it on display), each a whole text: never build them from parts.
-- i18n: keys begin name description layoutTip
menu.ENTRIES = {
	{ id = "parclo", name = "Parclo", order = 3014,
		types = { hx.TYPE_A4, hx.TYPE_B4 }, labels = { "A", "B" },
		description = "A highway crossed by a road on another level, joined by one-way ramps. A partial cloverleaf: ramps in all four quadrants, loops in two of them; the other ramps are straight and wrap around the loops. Once built, everything is ordinary roads and bridges you can edit or connect.",
		layoutTip = "A: loop on-ramps, in the quadrants before the cross\nroad. B: loop exits, in the quadrants after it.\nThe other ramps are straight." },
	{ id = "parclo2", name = "Parclo, two quadrants", order = 3015,
		types = { hx.TYPE_A2, hx.TYPE_B2, hx.TYPE_AB2 }, labels = { "A", "B", "AB" },
		description = "A highway crossed by a road on another level, joined by one-way ramps. A partial cloverleaf with ramps in two quadrants only: in each, a loop and a straight ramp wrapped around it. Once built, everything is ordinary roads and bridges you can edit or connect.",
		layoutTip = "A: the two quadrants before the cross road (loop\non-ramps). B: the two after it (loop exits).\nAB: both quadrants on one side of the highway." },
	{ id = "diamond", name = "Diamond", order = 3016,
		types = { hx.TYPE_DIAMOND },
		description = "A highway crossed by a road on another level, joined by one-way ramps. Four straight ramps, one per quadrant, no loops. Once built, everything is ordinary roads and bridges you can edit or connect." },
}
-- i18n: keys end
menu.BY_ID = {}
for _, e in ipairs(menu.ENTRIES) do menu.BY_ID[e.id] = e end

local function metres(list)
	local out = {}
	for i = 1, #list do out[i] = tostring(list[i]) .. " m" end
	return out
end

--- The .con.lua table of entry `id` (menu.ENTRIES); tr = the .con.lua's `_`.
function menu.data(id, tr)
	local _ = tr or function(s) return s end
	local e = assert(menu.BY_ID[id], id)
	local loops = e.types[1] ~= hx.TYPE_DIAMOND
	local roads = {
		_("Town, small"), _("Town, medium"), _("Town, large"),
		_("Country, small"), _("Country, medium"), _("Country, large"),
	}
	-- the Scale tooltips name hx.LOOP_RADII / hx.TERMINAL_DISTANCES in one translatable text each
	-- (tests/square_roundabouts/test_highway.lua checks the numbers)
	local scaleTip, rampTip
	if loops then
		scaleTip = _("S, M, L: small, medium, large. Size of the whole\nfootprint (M about 1.6 x, L 2.5 x S): loop ramp radius\n25, 45 or 80 m, with longer ramps and wider gaps to match.\nA minimum: grows if the roads don't fit.")
		rampTip = _("Extra length of the straight ramps along the highway\nover the shortest that wraps around the loop\n(short: +0, medium: +30, long: +60 m). Longer: gentler\nramps and a longer run beside the highway before\na ramp leaves or joins it. At Scale L, ramps\nstop at the longest the game accepts (the highway\nends at most about 460-480 m from the centre).")
	else
		scaleTip = _("S, M, L: small, medium, large. Size of the whole\nfootprint (M about 1.6 x, L 2.5 x S): the ramps meet\nthe cross road 0, 40 or 100 m beyond\nthe bridge and run 120, 192 or 300 m along the highway.\nA minimum: grows if the roads don't fit.")
		rampTip = _("Extra length of the ramps along the highway over the\nScale's (short: +0, medium: +30, long: +60 m).\nLonger: gentler ramps.")
	end
	local con = {
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
			name = _(e.name), -- i18n: ignore (keys marked in menu.ENTRIES)
			description = _(e.description), -- i18n: ignore (keys marked in menu.ENTRIES)
			-- menu icon square_roundabouts_highway_<id>@2x.tga (240x150) and hover preview
			-- ..._preview@2x.tga (720x405), drawn from the entry's default build (first Layout) by
			-- tools/render_icon_square_roundabouts.py (replace the previews with in-game captures later)
			icon = "square_roundabouts_highway_" .. e.id .. ".tga",
			previewIcon = "square_roundabouts_highway_" .. e.id .. "_preview.tga",
		},
		-- As the Roundabout Interchange: the highway and ramp templates and the steel bridge exist from
		-- 1940 (the base interchanges unlock in 1960). tests/square_roundabouts/test_short_edges.lua
		-- checks this year against every template and bridge the updateFn emits before 1970.
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
					order = e.order,
				},
			},
		},
		params = {
			{
				key = K.highway,
				name = _("Highway"),
				tooltip = _("Highway type, built as two one-way carriageways.\nS, M, L: small, medium, large highway\n(1, 2 or 3 lanes each way)."),
				uiType = "Button",
				displayMode = "Horizontal",
				values = { "S", "M", "L" }, -- size codes, the same in every language
				defaultIndex = 2,
			},
			{
				key = K.level,
				name = _("On top"),
				tooltip = _("Which one crosses over the other.\nRoad: the cross road 8 m up on a bridge, the highway\nat ground level.\nHwy: the highway 8 m up on two bridges, the cross\nroad at ground level.\nThe ramps climb the 8 m."),
				uiType = "Button",
				displayMode = "Horizontal",
				values = { _("Road"), _("Hwy") },
				defaultIndex = hx.LEVEL_ROAD_OVER,
			},
			{
				key = K.cross,
				name = _("Cross road"),
				tooltip = _("Road type of the two-way road across the highway."),
				uiType = "ComboBox",
				values = roads,
				defaultIndex = hx.DEFAULT_CROSS,
			},
			{
				key = K.size,
				name = _("Scale"),
				tooltip = scaleTip,
				uiType = "Button",
				displayMode = "Horizontal",
				values = { "S", "M", "L" }, -- size codes, the same in every language
				defaultIndex = hx.DEFAULT_SIZE,
			},
			{
				key = K.rampLength,
				name = _("Ramp length"),
				tooltip = rampTip,
				uiType = "Button",
				displayMode = "Horizontal",
				values = { _("Short"), _("Medium"), _("Long") },
				defaultIndex = hx.DEFAULT_RAMP_LENGTH,
			},
			{
				key = K.armLength,
				name = _("Arm length"),
				tooltip = _("How far the cross road runs on beyond the ramps,\nand the highway beyond the outermost ramps."),
				uiType = "Button",
				displayMode = "Horizontal",
				values = metres(hx.ARM_LENGTHS),
				defaultIndex = hx.DEFAULT_ARM_LENGTH,
			},
			{
				key = K.direction,
				name = _("Traffic side"),
				tooltip = loops and _("Right: right-hand traffic, loops turn right.\nLeft: left-hand traffic, everything mirrored.")
					or _("Right: right-hand traffic.\nLeft: left-hand traffic, everything mirrored."),
				uiType = "Button",
				displayMode = "Horizontal",
				values = { _("Right"), _("Left") },
				defaultIndex = 1,
			},
			-- last on every entry (square_roundabouts_result.lua "Structure")
			result.structureParam(_, result.STRUCTURE_BRIDGE),
		},
		updateScript = {
			fileName = "square_roundabouts_highway.script@updateFn",
			params = {
				types = e.types,
			},
		},
	}
	if #e.types > 1 then
		local labels = {}
		for i, l in ipairs(e.labels) do labels[i] = l end -- type codes, the same in every language
		table.insert(con.params, 1, {
			key = hx.LAYOUT_KEY,
			name = _("Layout"),
			tooltip = _(e.layoutTip), -- i18n: ignore (keys marked in menu.ENTRIES)
			uiType = "Button",
			displayMode = "Horizontal",
			values = labels,
			defaultIndex = 1,
		})
	end
	-- every param in the left toolbar (see the top of this file)
	for _, p in ipairs(con.params) do p.location = "Toolbar" end
	return con
end

return menu
