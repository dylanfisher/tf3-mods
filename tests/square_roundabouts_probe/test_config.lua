-- Probe settings: mod params -> config, and mod.json params agree with probe_config.lua.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local config = ug_require "/probe/probe_config.lua"
local grid = ug_require "/probe/probe_grid.lua"

test("defaults when the mod params are missing or bad", function()
	local d = config.fromModParams(nil)
	eq(d.run, true)
	eq(d.subset, "smoke")
	eq(d.delay, 15)
	eq(d.batch, 4)
	eq(d.x, 0)
	eq(d.y, 0)
	eq(d.context, "none")
	eq(d.logOk, true)
	eq(d.pos, "setting")
	eq(config.fromModParams({ sqrb_probe_subset = 99, sqrb_probe_batch = 0, sqrb_probe_x = 1.5 }), d)
end)

test("1-based indices select values", function()
	local c = config.fromModParams({
		sqrb_probe_run = 1, sqrb_probe_subset = 5, sqrb_probe_delay = 4, sqrb_probe_batch = 5,
		sqrb_probe_x = 1, sqrb_probe_y = 9, sqrb_probe_context = 2, sqrb_probe_log_ok = 2, sqrb_probe_pos = 2,
	})
	eq(c, { run = false, subset = "main", delay = 60, batch = 16, x = -4000, y = 4000, context = "player", logOk = false, pos = "camera" })
	ok(config.describe(c):find("pos=camera", 1, true))
	ok(config.describe(c):find("subset=main", 1, true))
end)

test("mod.json params match KEYS, VALUES and DEFAULTS", function()
	local mod = H.readJson("mod.json")
	eq(mod.modId, config.MOD_ID)
	local byKey = {}
	for _, p in ipairs(mod.params) do byKey[p.key] = p end
	local n = 0
	for name, key in pairs(config.KEYS) do
		n = n + 1
		local p = byKey[key]
		ok(p, "mod.json has no param " .. key)
		eq(#p.values, #config.VALUES[name], key .. " values")
		eq(p.defaultIndex + 1, config.DEFAULTS[name], key .. " defaultIndex (0-based)")
		eq(p.numbers, nil, key .. ": no numbers, the config maps indices")
	end
	eq(#mod.params, n)
	for i, name in ipairs(grid.SUBSET_ORDER) do eq(byKey.sqrb_probe_subset.values[i], name) end
	for i, v in ipairs(config.VALUES.x) do eq(byKey.sqrb_probe_x.values[i], tostring(v)) end
end)

test("dev-only markers are present", function()
	local info = H.readJson("_metadata/modinfo.json")
	ok(info.summary:find("NOT FOR UPLOAD", 1, true))
	ok(info.description:find("NOT FOR UPLOAD", 1, true))
	local f = io.open(H.PROBE_ROOT .. "NOT_FOR_UPLOAD.txt", "r")
	ok(f, "NOT_FOR_UPLOAD.txt")
	if f then f:close() end
end)
