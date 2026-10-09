-- Probe runner with fake deps: batching, START/PROGRESS/END lines, exceptions, logOk.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local grid = ug_require "/probe/probe_grid.lua"
local runner = ug_require "/probe/probe_runner.lua"

local function fake(evaluate, opts)
	local lines, t = {}, 0
	opts = opts or {}
	local r = runner.new({
		combos = opts.combos or grid.expand("magic"),
		subset = "magic",
		header = { { "x", 0 } },
		progressEvery = opts.progressEvery or 25,
		logOk = opts.logOk,
		deps = {
			evaluate = evaluate,
			log = function(l) lines[#lines + 1] = l end,
			now = function() t = t + 1 return t end,
		},
	})
	return r, lines
end

local function kinds(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = (H.parseLine(l)) end
	return out
end

test("runs in batches and logs START, one R per combo, PROGRESS, END", function()
	local calls = 0
	local r, lines = fake(function(c)
		calls = calls + 1
		if c.labels[2] == "town_l" then return { ok = false, critical = true, messages = { "Construction not possible" } } end
		return { ok = true, critical = false, messages = {} }
	end)
	local steps = 0
	while not r:step(7) do steps = steps + 1 end
	eq(calls, 60)
	eq(steps, 8) -- 9 steps of up to 7 combos
	ok(r:step(7), "stays finished")
	eq(calls, 60)
	local k = kinds(lines)
	eq(k[1], "START")
	eq(k[#k], "END")
	local nR, nP = 0, 0
	for _, x in ipairs(k) do
		if x == "R" then nR = nR + 1 elseif x == "PROGRESS" then nP = nP + 1 end
	end
	eq(nR, 60)
	eq(nP, 2) -- after 25 and 50
	local _, s = H.parseLine(lines[1])
	eq(s.total, "60")
	eq(s.x, "0")
	local _, e = H.parseLine(lines[#lines])
	eq(e.ok, "50")
	eq(e.fail, "10")
	eq(e.errors, "0")
	eq(e.top, "Construction not possible:10")
end)

test("exceptions become error results and the run goes on", function()
	local r, lines = fake(function(c)
		if c.indices[1] == 1 then error("boom") end
		return { ok = true, messages = {} }
	end, { logOk = false })
	while not r:step(100) do end
	eq(r.counts.error, 12)
	eq(r.counts.ok, 48)
	-- logOk = false: only failing combos get R lines
	local nR = 0
	for _, l in ipairs(lines) do
		local kind, f = H.parseLine(l)
		if kind == "R" then
			nR = nR + 1
			ok(f.err:find("boom", 1, true), f.err)
			eq(f.ok, "false")
		end
	end
	eq(nR, 12)
end)

test("empty grid finishes at once", function()
	local r, lines = fake(function() return { ok = true } end, { combos = {} })
	ok(r:step(4))
	eq(kinds(lines), { "START", "END" })
end)
