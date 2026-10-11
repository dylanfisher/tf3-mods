-- DEV ONLY (never upload): Roundabouts Showcase settings.
-- Pure Lua (no api.*), unit-tested. Mod params arrive as 1-based value indices through
-- api.engine.config.getModParams()[modId] (as square_roundabouts_probe's probe_config.lua).
-- Each list in VALUES must match the `values` of the mod.json param with the same key
-- (tests/square_roundabouts_showcase/test_config.lua checks that).

local config = {}

config.MOD_ID = "square_roundabouts_showcase"
config.PREFIX = "[SQRB-SHOW]"

config.KEYS = {
	run = "sqrb_show_run",
	mode = "sqrb_show_mode",
	delay = "sqrb_show_delay",
	batch = "sqrb_show_batch",
	entries = "sqrb_show_entries",
	combos = "sqrb_show_combos",
	cap = "sqrb_show_cap",
	pattern = "sqrb_show_pattern",
	gap = "sqrb_show_gap",
	rotation = "sqrb_show_rotation",
	pos = "sqrb_show_pos",
	x = "sqrb_show_x",
	y = "sqrb_show_y",
	radius = "sqrb_show_radius",
	seed = "sqrb_show_seed",
	fill = "sqrb_show_fill",
}

-- The entries the "Constructions" setting selects (ids of config.ENTRIES).
config.ENTRY_SETS = {
	{ "ring", "interchange", "magic", "channel", "parclo", "parclo2", "diamond" },
	{ "ring" }, { "interchange" }, { "magic" }, { "channel" },
	{ "parclo" }, { "parclo2" }, { "diamond" },
	{ "parclo", "parclo2", "diamond" },
	{ "ring", "interchange", "magic", "channel" },
}

config.VALUES = {
	run = { false, true },
	mode = { "dry", "build" },
	delay = { 5, 15, 30, 60 },
	batch = { 1, 2, 4, 8, 16, 32 },
	entries = config.ENTRY_SETS,
	combos = { "showcase", "every", "one", "random" },
	cap = { 25, 50, 100, 250, 500, 1000, 2000, 5000, 10000 },
	pattern = { "grid", "mosaic", "kaleido4", "kaleido8", "mandala", "spiral", "gradient", "checker", "scatter" },
	gap = { 0, 5, 10, 20, 40, 60, 100, 150 },
	rotation = { "pattern", "fixed", "face", "random90", "random" },
	pos = { "setting", "camera" },
	x = { -4000, -2000, -1000, -500, 0, 500, 1000, 2000, 4000 },
	y = { -4000, -2000, -1000, -500, 0, 500, 1000, 2000, 4000 },
	radius = { 1000, 2000, 3000, 4000, 6000, 8000 },
	seed = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 },
	fill = { false, true },
}

-- 1-based default index of each setting (mod.json defaultIndex + 1)
config.DEFAULTS = {
	run = 2,
	mode = 2,
	delay = 1,
	batch = 5,
	entries = 1,
	combos = 1,
	cap = 7,
	pattern = 3,
	gap = 3,
	rotation = 1,
	pos = 1,
	x = 5,
	y = 5,
	radius = 3,
	seed = 1,
	fill = 2,
}

-- Not in the mod params (edit here if needed) ------------------------------------------------

-- The square_roundabouts entries: short id, one-letter map symbol, resource file (resolved with
-- api.res.constructionRep.find as the probe does: with the "square_roundabouts::/" prefix first).
config.TARGET_MOD = "square_roundabouts"
config.ENTRIES = {
	{ id = "ring", symbol = "R", file = "infrastructure/street_construction/square_roundabouts.con" },
	{ id = "interchange", symbol = "I", file = "infrastructure/street_construction/square_roundabouts_interchange.con" },
	{ id = "magic", symbol = "M", file = "infrastructure/street_construction/square_roundabouts_magic.con" },
	{ id = "channel", symbol = "C", file = "infrastructure/street_construction/square_roundabouts_channel.con" },
	{ id = "parclo", symbol = "P", file = "infrastructure/street_construction/square_roundabouts_highway_parclo.con" },
	{ id = "parclo2", symbol = "Q", file = "infrastructure/street_construction/square_roundabouts_highway_parclo2.con" },
	{ id = "diamond", symbol = "D", file = "infrastructure/street_construction/square_roundabouts_highway_diamond.con" },
}

-- Only params whose key matches this are enumerated (every square_roundabouts param is prefixed
-- sqrb_, geom.PARAM_KEYS); anything else the rep may hold stays at its default and is logged.
config.PARAM_KEY_PATTERN = "^sqrb_"
-- "Every combination" with the largest cap still stops here.
config.HARD_CAP = 10000
-- Footprint growth: each street's own half width (api.res.streetTemplateRep laneConfigs) + a kerb,
-- plus earth slopes for raised streets: sc_footprint.KERB / SLOPE / MIN_GROW.
-- Footprint (m, square) of an entry whose geometry module is unknown or fails.
config.FALLBACK_SIZE = 400
-- Footprints computed per guiUpdate (geometry builds are pure Lua; the highway ones take a few ms).
config.MEASURE_PER_UPDATE = 8
-- Build mode: up to "Per update" builds in flight at once, but a placement is checked and sent
-- only when its box, grown by FLIGHT_MARGIN (m) more on every side, overlaps no build still in
-- flight: far-apart pieces build in parallel, neighbours one after another (each check then sees
-- its built neighbours). The queue is interleaved by BUCKET-sized cells so consecutive pieces are
-- far apart; the first free one among the next WINDOW queued pieces is taken.
config.FLIGHT_MARGIN = 50
config.BUCKET = 1000
config.WINDOW = 64
-- The layout runs in a coroutine and yields after this many seconds of work (os.clock), so a big
-- filled layout is spread over several GUI updates instead of one long freeze.
config.LAYOUT_SLICE = 0.05
-- A refused placement (or one on water / off the map) moves to the nearest free spot this many
-- times before it counts as refused (not in a kaleidoscope: a moved copy would break the symmetry).
config.MAX_RETRIES = 2
-- Give up waiting for callbacks after this many seconds at the end.
config.CALLBACK_TIMEOUT = 60
-- Progress line every this many placements.
config.PROGRESS_EVERY = 25
-- ASCII preview size (characters).
config.PREVIEW_COLS = 96
config.PREVIEW_ROWS = 48
-- PLAN lines: one per placement up to this many (the preview and summary always come).
config.MAX_PLAN_LINES = 2000
-- Context flags of the proposal check and the build command (engine Context, api/type.d.tl).
config.CONTEXT_FLAGS = { checkTerrainAlignment = true, cleanupStreetGraph = false, gatherBuildings = true, gatherFields = true }

--- Settings from the raw mod params of this mod (nil or a table of 1-based indices).
-- Unknown or out-of-range values fall back to the defaults.
function config.fromModParams(raw)
	raw = type(raw) == "table" and raw or {}
	local cfg = {}
	for name, key in pairs(config.KEYS) do
		local list = config.VALUES[name]
		local i = tonumber(raw[key])
		if i == nil or i < 1 or i > #list or i ~= math.floor(i) then i = config.DEFAULTS[name] end
		cfg[name] = list[i]
	end
	return cfg
end

--- One line describing the settings.
function config.describe(cfg)
	return string.format("mode=%s entries=%s combos=%s cap=%d fill=%s pattern=%s gap=%dm rotation=%s pos=%s x=%d y=%d radius=%dm seed=%d delay=%ds inFlight=%d",
		tostring(cfg.mode), table.concat(cfg.entries or {}, ","), tostring(cfg.combos), cfg.cap, tostring(cfg.fill), tostring(cfg.pattern),
		cfg.gap, tostring(cfg.rotation), tostring(cfg.pos), cfg.x, cfg.y, cfg.radius, cfg.seed, cfg.delay, cfg.batch)
end

function config.entryById(id)
	for _, e in ipairs(config.ENTRIES) do if e.id == id then return e end end
	return nil
end

return config
