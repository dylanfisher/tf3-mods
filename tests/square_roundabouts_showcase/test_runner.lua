-- The run's state machine with fake game deps: dry run never sends, refused / skipped placements
-- are never sent, callbacks are counted, the in-flight limit holds.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local config = ug_require "/showcase/sc_config.lua"
local runnerMod = ug_require "/showcase/sc_runner.lua"
local footprint = ug_require "/showcase/sc_footprint.lua"

local ENTRIES = H.entries()

local function cfgWith(over)
	local cfg = config.fromModParams({ sqrb_show_run = 2 })
	for k, v in pairs(over or {}) do cfg[k] = v end
	return cfg
end

local function fakeRun(cfg, behave)
	local lines, sent, pending = {}, {}, {}
	local t = 0
	local deps = {
		log = function(l) lines[#lines + 1] = l end,
		now = function() return t end,
		measure = function(c) return footprint.measure(c, H.rbRequire, H.FP_OPTS, config.FALLBACK_SIZE) end,
		check = function(p) return behave(p) end,
		send = function(p, done)
			sent[#sent + 1] = p
			pending[#pending + 1] = done
		end,
	}
	local r = runnerMod.new({ cfg = cfg, entries = ENTRIES, deps = deps, centre = { 1000, -2000 } })
	return r, lines, sent, pending, function(dt) t = t + dt end
end

local function count(lines, kind)
	local n = 0
	for _, l in ipairs(lines) do if l:find(config.PREFIX .. " " .. kind .. " ", 1, true) then n = n + 1 end end
	return n
end

test("dry run: plan, preview and summary, never a check or a send", function()
	local checked = 0
	local r, lines, sent = fakeRun(cfgWith({ mode = "dry", cap = 25, pattern = "mandala" }), function() checked = checked + 1 return { ok = true } end)
	local steps = 0
	while not r:step() do steps = steps + 1 assert(steps < 10000) end
	eq(#sent, 0)
	eq(checked, 0)
	ok(count(lines, "PLAN") == #r.placements and #r.placements > 0)
	ok(count(lines, "PREVIEW") > 3)
	eq(count(lines, "SUMMARY"), 1)
	ok(lines[#lines]:find("dry run", 1, true))
	-- every PLAN line names the combo, position and rotation
	for _, l in ipairs(lines) do
		if l:find(" PLAN ", 1, true) then
			ok(l:find(" key=", 1, true) and l:find(" x=", 1, true) and l:find(" rot=", 1, true), l)
		end
	end
end)

test("build: independent pieces in parallel, neighbours never in flight together, retries, never forced", function()
	local n, r, badItem = 0, nil, nil
	local conflictsAtCheck, maxFlying = 0, 0
	local refusedAt = {}
	local r_, lines, sent, pending, advance = fakeRun(cfgWith({ mode = "build", cap = 120, pattern = "grid", batch = 8, fill = true }), function(p)
		n = n + 1
		if r:conflicts(p) then conflictsAtCheck = conflictsAtCheck + 1 end
		-- every 5th check is refused, and the first refused item's ground is bad everywhere
		if n % 5 == 0 or p.item == badItem then
			badItem = badItem or p.item
			refusedAt[#refusedAt + 1] = p
			return { ok = false, reasons = { "Construction Not Possible" } }
		end
		if n % 7 == 0 then return { skip = "water" } end
		return { ok = true }
	end)
	r = r_
	local steps = 0
	while not r:step() do
		steps = steps + 1
		assert(steps < 20000)
		ok(r.inFlight <= 8, "at most 8 in flight")
		maxFlying = math.max(maxFlying, r.inFlight)
		-- the engine answers the oldest two builds per update, a failure every 3rd time
		local answered = 0
		for i, d in ipairs(pending) do
			if d and answered < 2 then
				pending[i] = false
				answered = answered + 1
				d(i % 3 ~= 0, i % 3 == 0 and { "Collision" } or {})
			end
		end
		advance(1)
	end
	eq(conflictsAtCheck, 0, "no check next to a build in flight")
	ok(maxFlying > 2, "several builds in flight: " .. maxFlying)
	local total = #r.placements
	ok(total > 60, "filled: " .. total)
	eq(r.counts.sent, #sent)
	eq(r.counts.built + r.counts.failed, #sent)
	eq(r.counts.sent + r.counts.refused + r.counts.skipped + r.counts.retried, total)
	ok(r.counts.retried > 0, "retried")
	ok(r.counts.refused > 0, "the bad item gave up after its retries")
	eq(count(lines, "REFUSED"), r.counts.refused)
	eq(count(lines, "SKIP"), r.counts.skipped)
	eq(count(lines, "RETRY"), r.counts.retried)
	for _, p in ipairs(refusedAt) do for _, q in ipairs(sent) do ok(p ~= q) end end
	ok(lines[#lines]:find("SUMMARY", 1, true) and lines[#lines]:find("build finished", 1, true))
	ok(lines[#lines]:find("buildsPerSecond=", 1, true))
	ok(count(lines, "PROGRESS") > 0)
end)

test("interleave: same placements, consecutive ones far apart", function()
	local ps = {}
	for i = 0, 9 do for j = 0, 9 do ps[#ps + 1] = { x = i * 300, y = j * 300 } end end
	local q = runnerMod.interleave(ps, 1000)
	eq(#q, #ps)
	local seen = {}
	for _, p in ipairs(q) do ok(not seen[p]) seen[p] = true end
	local near = 0
	for i = 2, #q do
		if math.abs(q[i].x - q[i - 1].x) < 600 and math.abs(q[i].y - q[i - 1].y) < 600 then near = near + 1 end
	end
	ok(near < #q / 4, "mostly far apart: " .. near)
end)

test("the layout is sliced over updates with a clock, same result as in one go", function()
	local cfg = cfgWith({ mode = "dry", cap = 400, pattern = "spiral" })
	local a = fakeRun(cfg, function() return { ok = true } end)
	local steps = 0
	while not a:step() do steps = steps + 1 assert(steps < 20000) end
	local b = fakeRun(cfg, function() return { ok = true } end)
	local t = 0
	b.deps.clock = function() t = t + 0.01 return t end
	steps = 0
	while not b:step() do steps = steps + 1 assert(steps < 20000) end
	ok(b.layoutSlices > 1, "sliced: " .. tostring(b.layoutSlices))
	eq(#b.placements, #a.placements)
	for i = 1, #a.placements do
		eq(a.placements[i].x, b.placements[i].x)
		eq(a.placements[i].rot, b.placements[i].rot)
	end
end)

test("build: no retries in a kaleidoscope (a moved copy would break the symmetry)", function()
	local r = fakeRun(cfgWith({ mode = "build", cap = 20, pattern = "kaleido4", entries = { "magic" } }),
		function() return { ok = false, reasons = { "Too Much Incline" } } end)
	local steps = 0
	while not r:step() do steps = steps + 1 assert(steps < 10000) end
	eq(r.counts.retried, 0)
	eq(r.counts.refused, #r.placements)
end)

test("build: gives up on missing callbacks after the timeout", function()
	local r, lines, _, _, advance = fakeRun(cfgWith({ mode = "build", cap = 5, pattern = "grid", batch = 16 }), function() return { ok = true } end)
	local steps = 0
	while not r:step() do
		steps = steps + 1
		assert(steps < 10000)
		advance(5)
	end
	ok(lines[#lines]:find("gave up", 1, true))
end)

test("a throwing check or send is a failure, not a crash", function()
	local r = fakeRun(cfgWith({ mode = "build", cap = 3, pattern = "grid" }), function() error("boom") end)
	local steps = 0
	while not r:step() do steps = steps + 1 assert(steps < 1000) end
	-- each refused one was moved MAX_RETRIES times first
	eq(r.counts.refused, 3)
	eq(r.counts.retried, 3 * config.MAX_RETRIES)
	eq(#r.placements, 3 * (1 + config.MAX_RETRIES))
	local r2, _, _, _, advance = fakeRun(cfgWith({ mode = "build", cap = 3, pattern = "grid" }), function() return { ok = true } end)
	r2.deps.send = function() error("send boom") end
	steps = 0
	while not r2:step() do steps = steps + 1 advance(1) assert(steps < 1000) end
	eq(r2.counts.failed, #r2.placements)
	eq(r2.inFlight, 0)
end)

test("kaleidoscope measures the mirror combos and places true mirrors", function()
	local r, lines = fakeRun(cfgWith({ mode = "dry", cap = 41, pattern = "kaleido4", entries = { "channel" } }), function() return { ok = true } end)
	local steps = 0
	while not r:step() do steps = steps + 1 assert(steps < 10000) end
	ok(#r.placements > 8)
	local mirrored = 0
	for _, p in ipairs(r.placements) do
		if p.mirrored then
			mirrored = mirrored + 1
			ok(p.item.mirror and p.fp == p.item.mirror.fp)
		end
	end
	eq(mirrored, (#r.placements - 1) / 2)
	ok(count(lines, "PLAN") > 0)
	local mirrorLine = false
	for _, l in ipairs(lines) do if l:find(" mirror=yes", 1, true) then mirrorLine = true end end
	ok(mirrorLine)
end)

test("line format: kind, key=value, quoted values with spaces", function()
	eq(runnerMod.line("X", { { "a", 1 }, { "b", "two words" }, { "c", nil }, { "d", { "p", "q" } }, { "e", 1.5 } }),
		config.PREFIX .. ' X a=1 b="two words" d=p|q e=1.50')
end)

test("collision feedback: REFUSED hits name the owner and the model's clearance; SUMMARY per kind", function()
	local r
	local n = 0
	local r_, lines, _, pending = fakeRun(cfgWith({ mode = "build", cap = 6, pattern = "grid", fill = false, entries = { "magic" } }), function(p)
		n = n + 1
		if n == 1 then return { ok = true } end
		local owner = r.placements[1]
		return { ok = false, reasons = { "Collision" },
			hits = { { owner = owner, model = 2.5, kind = "highway", z = 6, text = "1234:" .. owner.item.combo.key .. "@2.5m" },
				{ text = "99:edge" } } }
	end)
	r = r_
	r.cfg.batch = 1
	local steps = 0
	while not r:step() do
		steps = steps + 1
		assert(steps < 10000)
		for i, d in ipairs(pending) do if d then pending[i] = false d(true, {}) end end
	end
	local refused
	for _, l in ipairs(lines) do if l:find(" REFUSED ", 1, true) then refused = l end end
	ok(refused and refused:find("hits=1234:", 1, true) and refused:find("|99:edge", 1, true), tostring(refused))
	ok(lines[#lines]:find("collisionKinds=highway:n", 1, true), lines[#lines])
	ok(lines[#lines]:find("raised", 1, true))
end)
