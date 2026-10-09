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
