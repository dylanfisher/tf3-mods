-- Probe geometry correlation with the real square_roundabouts modules.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local grid = ug_require "/probe/probe_grid.lua"
local geomInfo = ug_require "/probe/probe_geom.lua"

local rb = H.loadRoundabouts()

local function one(block) return grid.expand({ block })[1] end

test("default main combo keeps its 20 m radius", function()
	local c = one({ entry = "main" })
	local g = geomInfo.forEntry("main", rb, c.params)
	eq(g.error, nil)
	eq(g.effR, 20)
	eq(g.forced, false)
	eq(g.fork, 0)
	ok(g.edges > 0)
end)

test("town large arms with splitter islands grow the ring to the engine floor (40 m, Phase 4b)", function()
	local c = one({ entry = "main", splitter = { "on" }, arm = { "town_l" } })
	eq(geomInfo.forEntry("main", rb, c.params).effR, 40)
end)

test("Magic with town large arms builds size Large (engine size floor, search_magic_sizes)", function()
	local c = one({ entry = "magic", size = { "compact" }, arm = { "town_l" } })
	eq(geomInfo.forEntry("magic", rb, c.params).effSize, 4)
end)

test("every combo of the splitter6 and magic subsets has geometry", function()
	for _, name in ipairs({ "splitter6", "magic", "smoke" }) do
		for _, c in ipairs(grid.expand(name)) do
			local g = geomInfo.forEntry(c.entry, rb, c.params)
			ok(g.error == nil, c.key .. ": " .. tostring(g.error))
		end
	end
end)

test("missing modules or a raising build give an error, not an exception", function()
	eq(geomInfo.main(nil, {}).error, "geometry module unavailable")
	local bad = { readParams = function() return {} end, build = function() error("nope") end }
	ok(geomInfo.main(bad, {}).error:find("nope", 1, true))
end)

test("Phase 5e sweeps: every combo has sane geometry; channel set-backs, interchange radius and bridge", function()
	for _, name in ipairs({ "p5_all", "p5f_all", "p5g_verify" }) do
		for _, c in ipairs(grid.expand(name)) do
			local g = geomInfo.forEntry(c.entry, rb, c.params)
			ok(g.error == nil, c.key .. ": " .. tostring(g.error))
			ok(g.sane, c.key .. ": " .. tostring(g.insane))
			if c.entry == "channel" then ok(g.setback:match("^%d+%.%d/%d+%.%d$"), c.key .. " " .. tostring(g.setback)) end
			if c.entry == "interchange" then
				eq(g.forced, false, c.key)
				eq(g.bridge, c.params.year < 1970 and "steel" or "concrete", c.key)
			end
		end
	end
	local ch = geomInfo.forEntry("channel", rb, grid.expand({ { entry = "channel" } })[1].params)
	eq(ch.setback, "42.2/41.4") -- PHASE5.md "Phase 5b notes": default town medium + town small
	eq(geomInfo.channel(nil, {}).error, "channel module unavailable")
	eq(geomInfo.interchange(nil, {}).error, "interchange module unavailable")
end)

test("Phase 7d / 7e sweeps p7_hx_all, p7_verify: every combo has sane, unforced geometry; size, loop radius, ramp, terminals, bridge", function()
	local hx = rb.highway
	local combos = grid.expand("p7_hx_all")
	for _, c in ipairs(grid.expand("p7_verify")) do combos[#combos + 1] = c end
	for _, c in ipairs(combos) do
		local g = geomInfo.forEntry(c.entry, rb, c.params)
		ok(g.error == nil, c.key .. ": " .. tostring(g.error))
		ok(g.sane, c.key .. ": " .. tostring(g.insane))
		eq(g.forced, false, c.key)
		eq(g.bridge, c.params.year < 1970 and "steel" or "concrete", c.key)
		local spec = hx.specFor({ type = c.params[hx.PARAM_KEYS.type] }, c.params)
		local loops = hx.hasLoops(spec)
		eq(g.effSize, (loops and hx.LOOP_RADII or hx.TERMINAL_DISTANCES)[spec.size], c.key .. " no growth")
		eq(g.effR, loops and g.effSize or nil, c.key)
		ok(type(g.xm) == "number" and g.xm > 0, c.key)
		ok(g.term:match(loops and "^%d+%.%d/%d+%.%d$" or "^%-/%d+%.%d$"), c.key .. " " .. tostring(g.term))
		ok(g.edges > 10, c.key)
	end
	-- the default (Parclo A4, Scale Medium = 45 m loops, Short ramps)
	local d = geomInfo.forEntry("highway", rb, grid.expand({ { entry = "highway" } })[1].params)
	eq(d.effSize, 45); eq(d.effR, 45); eq(d.bridge, "concrete")
	-- the diamond combo builds what its own entry builds (captureParams.type = 6)
	local dc = grid.expand({ { entry = "highway", type = { "diamond" } } })[1]
	eq(geomInfo.forEntry("highway", rb, dc.params).effR, nil)
	eq(geomInfo.forEntry("highway", rb, dc.params).effSize, hx.TERMINAL_DISTANCES[2])
	eq(geomInfo.highway(nil, {}).error, "highway module unavailable")
	local bad = { readParams = function() return {} end, build = function() error("nope") end }
	ok(geomInfo.highway(bad, {}).error:find("nope", 1, true))
end)

test("Phase 7e fix-up: geomInfo.nodes (unique end points) and toWorld (rotation about z)", function()
	local m = H.loadRoundabouts()
	local nodes = geomInfo.nodes("highway", m, grid.combo("highway", { 2, 1, 1, 6, 1, 1, 1, 1, 2 }).params)
	ok(nodes and #nodes > 20, "highway nodes")
	local seen = {}
	for _, p in ipairs(nodes) do
		local k = string.format("%.3f,%.3f,%.3f", p[1], p[2], p[3])
		ok(not seen[k], "duplicate " .. k)
		seen[k] = true
	end
	ok(seen["0.000,-96.500,8.000"], "outer terminal node at 8 m")
	ok(#geomInfo.nodes("interchange", m, grid.expand({ { entry = "interchange" } })[1].params) > 4)
	-- Phase 8: the main roundabout has nodes too (p8_bridge D lines); other entries none
	ok(#geomInfo.nodes("main", m, {}) > 4)
	local n, err = geomInfo.nodes("magic", m, {})
	eq(n, nil); ok(err)
	local x, y, z = geomInfo.toWorld({ 100, 200, 5 }, 90, { 10, 0, 8 })
	ok(math.abs(x - 100) < 1e-9 and math.abs(y - 210) < 1e-9 and z == 13)
	x, y = geomInfo.toWorld({ 0, 0, 0 }, 350, { 10, 0, 0 })
	ok(math.abs(x - 10 * math.cos(math.rad(10))) < 1e-9 and math.abs(y + 10 * math.sin(math.rad(10))) < 1e-9)
end)

-- Phase 7d2: p7_hx_scale builds sane, unforced geometry with no growth at every Scale (offline the
-- 7c3 Scale test says so for the shipped mod; this checks the probe's combos reach it), and
-- p7_presets' preset keys build exactly what the full-range index builds.
test("Phase 7d2 p7_hx_scale, p7_presets: sane, unforced, no growth; preset key = full-range index", function()
	local hx = rb.highway
	local seenSize = {}
	for _, c in ipairs(grid.expand("p7_hx_scale")) do
		local g = geomInfo.forEntry(c.entry, rb, c.params)
		ok(g.error == nil, c.key .. ": " .. tostring(g.error))
		ok(g.sane, c.key .. ": " .. tostring(g.insane))
		eq(g.forced, false, c.key)
		eq(g.bridge, c.params.year < 1970 and "steel" or "concrete", c.key)
		local spec = hx.specFor({ type = c.params[hx.PARAM_KEYS.type] }, c.params)
		local loops = hx.hasLoops(spec)
		eq(g.effSize, (loops and hx.LOOP_RADII or hx.TERMINAL_DISTANCES)[spec.size], c.key .. " no growth")
		seenSize[spec.size] = true
	end
	ok(seenSize[1] and seenSize[2] and seenSize[3], "Small / Medium / Large")
	for _, c in ipairs(grid.expand("p7_presets")) do
		local g = geomInfo.forEntry(c.entry, rb, c.params)
		ok(g.error == nil, c.key .. ": " .. tostring(g.error))
		ok(g.sane, c.key .. ": " .. tostring(g.insane))
		if c.entry == "main" or c.entry == "interchange" then
			local plain = {}
			for k, v in pairs(c.params) do plain[k] = v end
			plain.sqrb_radius_size, plain.sqrb_ix_radius_size = nil, nil
			eq(geomInfo.forEntry(c.entry, rb, plain).effR, g.effR, c.key .. " preset = full-range index")
		end
	end
end)

-- Phase 7e2: p7_hx_scale_verify builds sane, unforced geometry at Scale Large (no growth) within the
-- engine's reach (hx.MAX_REACH), and the refused combos now build a smaller layout than they did.
test("Phase 7e2 p7_hx_scale_verify: sane, unforced, no growth, within hx.MAX_REACH", function()
	local hx = rb.highway
	local capped = 0
	for _, c in ipairs(grid.expand("p7_hx_scale_verify")) do
		local g = geomInfo.forEntry(c.entry, rb, c.params)
		ok(g.error == nil, c.key .. ": " .. tostring(g.error))
		ok(g.sane, c.key .. ": " .. tostring(g.insane))
		eq(g.forced, false, c.key)
		local spec = hx.specFor({ type = c.params[hx.PARAM_KEYS.type] }, c.params)
		eq(g.effSize, hx.LOOP_RADII[3], c.key .. " no growth")
		local b = hx.build(spec)
		local lim = hx.MAX_REACH[spec.level]
		ok(hx.reach(b) <= lim + 1e-9, c.key .. ": reach " .. hx.reach(b))
		if hx.reach(b) >= lim - 1e-9 then capped = capped + 1 end
	end
	ok(capped >= 190, "capped " .. capped)
end)
