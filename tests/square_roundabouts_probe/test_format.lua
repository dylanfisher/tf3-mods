-- Probe log lines: one parseable line per combo, free text quoted and cleaned.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local grid = ug_require "/probe/probe_grid.lua"

local function combo() return grid.expand({ { entry = "main", arms = { "6" }, splitter = { "on" }, arm = { "town_l" } } })[1] end

test("result line has every axis, the verdict and the replay key", function()
	local c = combo()
	local line = grid.resultLine(7, 432, c, {
		ok = false, critical = true,
		messages = { "Construction not possible", 'Too "steep"|x' },
		warnings = {}, infos = { "info\nline" },
		collisions = 0, buildings = 0, added = 1, cost = 12345,
		geom = { effR = 30, forced = false, fork = 1, a = 41, b = 41.5, edges = 40 },
		mode = "proposal", ms = 12,
	})
	ok(line:sub(1, 15) == "[SQRB_PROBE] R ", line)
	ok(not line:find("\n"), "single line")
	local kind, f, order = H.parseLine("[2026-10-08 01:40:43Z - MESSAGE  - Main Thread - Main ]  " .. line)
	eq(kind, "R")
	eq(f.n, "7")
	eq(f.total, "432")
	eq(f.entry, "main")
	eq(f.shape, "round")
	eq(f.lanes, "2")
	eq(f.radius, "20")
	eq(f.arms, "6")
	eq(f.splitter, "on")
	eq(f.arm, "town_l")
	eq(f.ok, "false")
	eq(f.critical, "true")
	eq(f.nmsg, "2")
	eq(f.msgs, "Construction not possible|Too 'steep'/x")
	eq(f.warnings, "")
	eq(f.infos, "info line")
	eq(f.effR, "30")
	eq(f.b, "41.50")
	eq(f.fork, "1")
	eq(f.forced, "false")
	eq(f.err, "")
	eq(f.key, c.key)
	eq(order[1], "n")
	eq(order[#order], "key")
end)

test("missing values are '-' and errors are quoted", function()
	local line = grid.resultLine(1, 1, combo(), { ok = false, error = 'attempt to index "x"\n stack' })
	local _, f = H.parseLine(line)
	eq(f.critical, "-")
	eq(f.coll, "-")
	eq(f.effR, "-")
	eq(f.err, "attempt to index 'x'  stack")
	eq(f.msgs, "")
end)

test("generic lines: bare values lose whitespace, numbers are formatted", function()
	local line = grid.line("END", { { "subset", "main x" }, { "seconds", 12.345 }, { "n", 3 }, { "top", { "a", "b c" }, "l" } })
	eq(line, '[SQRB_PROBE] END subset=main_x seconds=12.35 n=3 top="a|b c"')
end)

test("Phase 5e entries: entry column, their axes, set-back / bridge fields, replay keys", function()
	local c = grid.expand({ { entry = "channel", layout = { "X" }, splitter = { "on" } } })[1]
	local _, f, order = H.parseLine(grid.resultLine(1, 2, c, { ok = true, geom = { setback = "58.3/64.7", edges = 30 } }))
	eq(f.entry, "channel"); eq(f.layout, "X"); eq(f.splitter, "on"); eq(f.main, "town_m"); eq(f.dir, "rht")
	eq(f.setback, "58.3/64.7"); eq(f.bridge, "-"); eq(f.key, "c:2,2,1,1,2,1,1,1")
	eq(order[#order], "key")
	local x = grid.expand({ { entry = "interchange", layout = { "peanut" }, year = { "1969" } } })[1]
	local _, g = H.parseLine(grid.resultLine(2, 2, x, { ok = false, messages = { "m" }, geom = { effR = 15, bridge = "steel" } }))
	eq(g.entry, "interchange"); eq(g.layout, "peanut"); eq(g.year, "1969"); eq(g.bridge, "steel"); eq(g.effR, "15")
	eq(g.key, "x:3,2,1,2,2,2,2,1,1,1,1")
	local m = grid.expand({ { entry = "main", centre = { "lights" }, through = { "country_l" } } })[1]
	local _, h = H.parseLine(grid.resultLine(1, 1, m, { ok = true }))
	eq(h.centre, "lights"); eq(h.through, "country_l"); eq(h.key, "m:1,2,5,3,1,4,1,1,1,1,1,7")
end)
