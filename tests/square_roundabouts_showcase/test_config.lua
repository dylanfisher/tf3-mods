-- Showcase settings: mod params -> config, and mod.json params agree with sc_config.lua.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local config = ug_require "/showcase/sc_config.lua"

test("defaults when the mod params are missing or bad", function()
	local d = config.fromModParams(nil)
	-- DEV defaults (user 2026-10-10): run and build at once, at the map centre, repeats to fill
	eq(d.run, true)
	eq(d.mode, "build")
	eq(d.delay, 5)
	eq(d.combos, "showcase")
	eq(d.pattern, "kaleido4")
	eq(d.cap, 2000)
	eq(d.fill, true)
	eq(d.batch, 16)
	eq(d.gap, 10)
	eq(d.pos, "setting")
	eq(d.x, 0)
	eq(d.y, 0)
	eq(#d.entries, 7)
	eq(config.fromModParams({ sqrb_show_pattern = 99, sqrb_show_batch = 0, sqrb_show_x = 1.5 }), d)
end)

test("1-based indices select values", function()
	local c = config.fromModParams({ sqrb_show_run = 1, sqrb_show_mode = 1, sqrb_show_pattern = 9, sqrb_show_entries = 4, sqrb_show_fill = 1 })
	eq(c.run, false)
	eq(c.mode, "dry")
	eq(c.fill, false)
	eq(c.pattern, "scatter")
	eq(c.entries, { "magic" })
	ok(config.describe(c):find("pattern=scatter", 1, true))
end)

test("mod.json params match KEYS, VALUES and DEFAULTS", function()
	local mod = H.readJson("mod.json")
	eq(mod.modId, config.MOD_ID)
	eq(mod.severityAdd, "None")
	local byKey = {}
	for _, p in ipairs(mod.params) do byKey[p.key] = p end
	local n = 0
	for name, key in pairs(config.KEYS) do
		n = n + 1
		local p = byKey[key]
		ok(p, "mod.json has " .. key)
		eq(#p.values, #config.VALUES[name], key .. ": value count")
		eq(p.defaultIndex + 1, config.DEFAULTS[name], key .. ": default")
	end
	eq(#mod.params, n, "no extra params")
	-- numbers in the labels match the values
	for _, name in ipairs({ "delay", "batch", "cap", "gap", "x", "y", "radius", "seed" }) do
		for i, label in ipairs(byKey[config.KEYS[name]].values) do
			eq(tonumber(label:match("^%-?%d+")), config.VALUES[name][i], name .. " label " .. label)
		end
	end
	-- DEV markers
	local info = H.readJson("_metadata/modinfo.json")
	ok(info.summary:find("DEV ONLY - NOT FOR UPLOAD", 1, true))
	ok(info.description:find("DEV ONLY - NOT FOR UPLOAD", 1, true))
	eq(info.authors[1].name, "square")
	eq(mod.dependencies[1].mod.modId, "square_roundabouts")
end)

test("every entry set names known entries", function()
	for _, set in ipairs(config.ENTRY_SETS) do
		for _, id in ipairs(set) do ok(config.entryById(id), id) end
	end
end)
