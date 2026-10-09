-- DEV ONLY (never upload): Roundabouts placement probe settings.
-- Pure Lua (no api.*), unit-tested. The mod params (mod.json "params", chosen in the game's mod
-- settings when starting or loading a game) arrive as 1-based value indices through
-- api.engine.config.getModParams()[modId] (api/engine.d.tl:1807; 1-based as read by
-- .cache/subscribed/zhenya_doubleclick_to_edit/content/gui/dce.script.lua:75-77).
-- Each list below must match the `values` of the param with the same key in mod.json
-- (tests/square_roundabouts_probe/test_config.lua checks that).

local grid = ug_require "square_roundabouts_probe::/probe/probe_grid.lua"

local config = {}

config.MOD_ID = "square_roundabouts_probe"

config.KEYS = {
	run = "sqrb_probe_run",
	subset = "sqrb_probe_subset",
	delay = "sqrb_probe_delay",
	batch = "sqrb_probe_batch",
	x = "sqrb_probe_x",
	y = "sqrb_probe_y",
	context = "sqrb_probe_context",
	logOk = "sqrb_probe_log_ok",
}

-- value lists by key (index = mod param value), and the default index (mod.json defaultIndex + 1)
config.VALUES = {
	run = { false, true },
	subset = grid.SUBSET_ORDER,
	delay = { 5, 15, 30, 60 },
	batch = { 1, 2, 4, 8, 16 },
	x = { -4000, -2000, -1000, -500, 0, 500, 1000, 2000, 4000 },
	y = { -4000, -2000, -1000, -500, 0, 500, 1000, 2000, 4000 },
	context = { "none", "player" },
	logOk = { true, false },
}
config.DEFAULTS = {
	run = 2,
	subset = 1,
	delay = 2,
	batch = 3,
	x = 5,
	y = 5,
	context = 1,
	logOk = 1,
}

-- Not in the mod params (edit here if needed) ------------------------------------------------
-- Progress line every this many combos.
config.PROGRESS_EVERY = 250
-- Also run the construction's updateFn through api.engine.util.construction.getConstructionResult
-- for combos the proposal rejects ("on_fail"), for every combo ("always") or never ("never").
config.UPDATE_FN_CHECK = "on_fail"
-- Extra construction params merged over the global construction params, before the sqrb_* ones
-- (e.g. { height = 0 } to mimic a builder param; PROBE.md "Unverified").
config.EXTRA_PARAMS = {}
-- After this many consecutive makeProposalData exceptions at the start of a run, the probe stops
-- asking for proposals and only runs updateFns (mode=result_only).
config.PROPOSAL_FAILS_TO_FALL_BACK = 3

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

--- One line describing the settings (for the START line).
function config.describe(cfg)
	return string.format("subset=%s delay=%ds batch=%d x=%d y=%d context=%s logOk=%s",
		tostring(cfg.subset), cfg.delay, cfg.batch, cfg.x, cfg.y, tostring(cfg.context), tostring(cfg.logOk))
end

return config
