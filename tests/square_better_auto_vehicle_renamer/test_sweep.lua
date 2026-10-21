-- Better Auto Vehicle Renamer: the sliced sweep (bavr_sweep.lua) against a fake game (fakegame.lua): welcome gating,
-- the Apply pass (oldest first), Not now + "Number existing vehicles on next load", numbers never reused, id reuse,
-- hand-typed names and takeOver, Replace (same id and new id), per-model counting, slicing and budgets, the fast
-- path, pending sends and retries, depot / existence checks, caps. PLAN.md "How it works" .. "Conflicts".

local Sweep = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_sweep.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Text = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_text.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_better_auto_vehicle_renamer/"
local G = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local function fleet(g, n, f)
	local ids = {}
	for i = 1, n do
		local o = {}
		for k, v in pairs(f or {}) do o[k] = v end
		ids[i] = g:buy(o)
	end
	return ids
end

---------------------------------------------------------------------------
-- Welcome

test("welcome: nothing renamed before the answer; the count is published; an empty game answers itself", function()
	local g = G.new()
	fleet(g, 5, { line = 900 })
	ok(g:cycles(3, 200) == false, "no full cycle without an answer (list / prune only)")
	eq(#g.sent, 0)
	eq(g:state().count, 5)
	eq(g:state().welcome, nil)
	eq(Reg.welcomeDue(g:state(), g.cfg, 5), "first")
	local e = G.new()
	for _ = 1, 30 do e:update() end
	eq(e:state().welcome, "apply", "no vehicles: Apply silently")
	local id = e:buy({ line = 900 })
	e:cycles(2, 200)
	eq(e:name(id), "Mercedes-Benz Citaro B-0001")
end)

test("apply: existing vehicles numbered oldest first, then renamed within the budget per 2 s window", function()
	local g = G.new()
	local ids = {}
	for i = 1, 30 do ids[i] = g:buy({ line = 900, pt = 100000 - i * 10 }) end -- higher id = older
	g:update()
	g:answer("apply")
	ok(g:cycles(1, 100), "collect cycle")
	for i = 1, 30 do eq(g:rec(ids[i]).t, 31 - i, "oldest first: id " .. ids[i]) end
	-- renames: at most 10 per 2 s window
	local perWin = {}
	local last = #g.sent
	for _ = 1, 200 do
		g:update(200)
		local w = math.floor(g.now / 2000)
		perWin[w] = (perWin[w] or 0) + (#g.sent - last)
		last = #g.sent
	end
	for w, n in pairs(perWin) do ok(n <= 10, "window " .. w .. ": " .. n) end
	for i = 1, 30 do eq(g:name(ids[i]), string.format("Mercedes-Benz Citaro B-%04d", 31 - i)) end
	eq(#g.sent, 30, "each vehicle renamed once")
	eq(g:state().ptotal, 30, "the pass total (the game script logs and clears it)")
end)

test("not now: old vehicles untouched, new ones numbered; Number existing on next load numbers the rest", function()
	local g = G.new()
	local old = fleet(g, 4, { line = 900, pt = 50 })
	g:update()
	g:answer("later")
	g.now = g.now + 1000
	local new = g:buy({ line = 900 })
	g:cycles(3, 300)
	eq(g:name(new), "Mercedes-Benz Citaro B-0001")
	for _, id in ipairs(old) do eq(g:name(id), "Road Vehicle " .. id) end
	eq(Reg.welcomeDue(g:state(), g.cfg, 5), nil)
	g:setParams({ ["bavr.renumberNext"] = 2 })
	g:reload()
	eq(Reg.welcomeDue(g:state(), g.cfg, 5), "renumber")
	g:answer("apply")
	g:cycles(4, 400)
	for i, id in ipairs(old) do eq(g:name(id), string.format("Mercedes-Benz Citaro B-%04d", 1 + i)) end
	eq(g:name(new), "Mercedes-Benz Citaro B-0001", "unchanged")
	eq(Reg.welcomeDue(g:state(), g.cfg, 5), nil, "numbered once: not asked again")
end)

---------------------------------------------------------------------------
-- Numbers

local function answered(opts)
	local g = G.new(opts)
	g:update()
	g:answer("apply")
	g:cycles(1, 50)
	return g
end

test("numbers: a sold vehicle's number is never reused; a reused id gets a new number", function()
	local g = answered()
	local a, b, c = g:buy({ line = 900 }), g:buy({ line = 900 }), g:buy({ line = 901 })
	g:cycles(2, 100)
	eq({ g:name(a), g:name(b), g:name(c) },
		{ "Mercedes-Benz Citaro B-0001", "Mercedes-Benz Citaro B-0002", "Mercedes-Benz Citaro B-0003" })
	g:sell(b)
	g:cycles(1, 100)
	g.now = g.now + Reg.GONE_MS + 1
	local d = g:buy({ line = 900 })
	g:cycles(2, 100)
	eq(g:name(d), "Mercedes-Benz Citaro B-0004")
	-- the engine hands out c's id again after a sale (other line, other purchase time)
	g:sell(c)
	g:buy({ id = c, line = 900, pt = g.now + 5, model = 2, carrier = G.ROAD })
	g:cycles(2, 100)
	eq(g:name(c), "Scania R T-0001")
	eq(g:rec(c).k, "T")
end)

test("hand-typed names are kept (number kept in the register), take over when cleared, or with Rename them too", function()
	local g = answered()
	local a = g:buy({ line = 900 })
	local b = g:buy({ line = 900, name = "Pride of London" }) -- typed before we ever saw it
	g:cycles(3, 150) -- the rename lease claimed, the rename sent, its arrival confirmed
	eq(g:name(a), "Mercedes-Benz Citaro B-0001")
	eq(g:name(b), "Pride of London")
	eq(g:rec(b).t, 2)
	eq(g:rec(b).user, 1)
	g.vehicles[a].name = "Old Faithful"
	g:cycles(2, 100)
	eq(g:name(a), "Old Faithful")
	eq(g:rec(a).user, 1)
	g.vehicles[a].name = ""
	g:cycles(3, 150) -- (the lease lapsed while idle: claimed, renamed, confirmed)
	eq(g:name(a), "Mercedes-Benz Citaro B-0001", "cleared: ours again, same number")
	g.vehicles[a].name = "Road Vehicle 77"
	g:cycles(1, 100)
	eq(g:name(a), "Mercedes-Benz Citaro B-0001", "a default name: ours again")
	g:setParams({ ["bavr.takeOver"] = 2 })
	g:reload()
	g:cycles(2, 100)
	eq(g:name(b), "Mercedes-Benz Citaro B-0002")
	eq(g:rec(b).orig, "Pride of London", "the original name is recorded")
end)

test("replace keeping the id: same number, new model name; per-model counting takes the new model's next", function()
	local g = answered({ params = { ["bavr.counter"] = 3, ["bavr.model"] = 2, ["bavr.digits"] = 2 } })
	local a = g:buy({ line = 900 })
	local b = g:buy({ line = 900 })
	g:cycles(2, 100)
	eq({ g:name(a), g:name(b) }, { "Citaro B-01", "Citaro B-02" })
	g.vehicles[b].model, g.vehicles[b].pt = 8, g.now
	g:cycles(2, 100)
	eq(g:name(b), "Urbino B-01")
	eq(g:rec(b).t, 2, "the per-type number stays")
	local c = g:buy({ line = 900 })
	g:cycles(2, 100)
	eq(g:name(c), "Citaro B-03", "Citaro's counter went on")
	-- the same with per-type counting: number kept
	g:setParams({ ["bavr.model"] = 2 })
	g:reload()
	g:cycles(3, 300)
	eq({ g:name(a), g:name(b), g:name(c) }, { "Citaro B-0001", "Urbino B-0002", "Citaro B-0003" })
end)

test("replace with a new id: matched to the gone vehicle on the same line and type, else a new number", function()
	local g = answered()
	local a = g:buy({ line = 900 })
	local t = g:buy({ line = 901, model = 2 })
	g:cycles(2, 100)
	g:sell(a)
	local a2 = g:buy({ line = 900, model = 8 })
	g:sell(t)
	local t2 = g:buy({ line = 900, model = 2 }) -- other line: no match
	g:cycles(3, 100)
	eq(g:name(a2), "Solaris Urbino B-0001")
	eq(g:name(t2), "Scania R T-0002")
	g.rt.matchGone = false
	local a3id = a2
	g:sell(a3id)
	local a4 = g:buy({ line = 900 })
	g:cycles(3, 100)
	eq(g:name(a4), "Mercedes-Benz Citaro B-0002", "matching off: a new number")
end)

---------------------------------------------------------------------------
-- Formats and inputs

test("inputs: a line rename or line change re-renders; no line falls back to the model", function()
	local g = answered({ params = { ["bavr.format"] = 5 } })
	local a = g:buy({ line = 900 })
	local b = g:buy({})
	g:cycles(2, 100)
	eq(g:name(a), "Bus 12 · B-0001")
	eq(g:name(b), "Mercedes-Benz Citaro B-0002")
	g.lines[900] = "Bus 14"
	g:cycles(2, 100)
	eq(g:name(a), "Bus 14 · B-0001")
	g.vehicles[b].line = 901
	g:cycles(2, 100)
	eq(g:name(b), "Harbor Express · B-0002")
end)

test("settings changed between loads re-render our names (budgeted), never hand-typed ones", function()
	local g = answered()
	local ids = fleet(g, 25, { line = 900 })
	g.vehicles[ids[3]].name = "Typed"
	g:cycles(6, 600)
	g:setParams({ ["bavr.format"] = 3, ["bavr.prefix"] = 2 })
	g:reload()
	g:cycles(1, 100)
	ok(#g.sent > 0)
	g:cycles(6, 600)
	eq(g:name(ids[1]), "Bus-0001")
	eq(g:name(ids[25]), "Bus-0025")
	eq(g:name(ids[3]), "Typed")
end)

test("types switched off and vehicles going to the depot are skipped; a vanished vehicle is not renamed", function()
	local g = answered({ params = { ["bavr.type.heli"] = 1 } })
	local h = g:buy({ carrier = G.AIR, model = 5 })
	local p = g:buy({ carrier = G.AIR, model = 6 })
	local d = g:buy({ line = 900 })
	g.vehicles[d].depot = true
	local v = g:buy({ line = 900 })
	g.vehicles[v].vanish = true
	g:cycles(2, 100)
	eq(g:name(h), "Aircraft " .. h)
	eq(g:name(p), "DC-3 A-0001")
	eq(g:name(d), "Road Vehicle " .. d)
	eq(g:name(v), "Road Vehicle " .. v)
	g.vehicles[d].depot = nil
	g:cycles(1, 100)
	eq(g:name(d), "Mercedes-Benz Citaro B-0002", "B-0001 went to the vanished one (numbered when first seen)")
end)

test("every type gets its letter", function()
	local g = answered({ params = { ["bavr.format"] = 3 } })
	local ids = {
		g:buy({ model = 1 }), g:buy({ model = 2 }), g:buy({ carrier = G.TRAM, model = 7 }),
		g:buy({ carrier = G.RAIL, model = 3 }), g:buy({ carrier = G.WATER, model = 4 }),
		g:buy({ carrier = G.AIR, model = 6 }), g:buy({ carrier = G.AIR, model = 5 }),
	}
	g:cycles(2, 100)
	local names = {}
	for i, id in ipairs(ids) do names[i] = g:name(id) end
	eq(names, { "B-0001", "T-0001", "R-0001", "L-0001", "S-0001", "A-0001", "H-0001" })
end)

test("two vehicles that would get the same name in one cycle: the second waits for the next cycle", function()
	local g = answered({ params = { ["bavr.format"] = 3, ["bavr.counter"] = 3 } })
	local a = g:buy({ model = 1 })
	local b = g:buy({ model = 8 })
	local dups = 0
	for _ = 1, 50 do
		local phase = g:update()
		dups = dups + g.rt.stats.dup
		if phase == "end" and g:name(a) == "B-0001" then break end
	end
	eq(g:name(a), "B-0001")
	eq(g:name(b), "Road Vehicle " .. b, "B-0001 already sent this cycle")
	eq(dups, 1)
	-- per-model numbers without the model in the name can repeat across models (PLAN.md): the next cycle sends it
	g:cycles(2, 100)
	eq(g:name(b), "B-0001")
end)

---------------------------------------------------------------------------
-- Performance: slicing, budget, fast path, state writes

test("slicing: at most INSPECT vehicles per update, a cycle spans several updates", function()
	local g = answered({ params = { ["bavr.speed"] = 3 } })
	fleet(g, 450, { line = 900 })
	g:cycles(30, 3000)
	eq(#g.sent, 450)
	g:reload() -- a new Lua state: its first cycle reads every vehicle
	local scans, maxInspected = 0, 0
	for _ = 1, 20 do
		local phase = g:update()
		if phase == "scan" then
			scans = scans + 1
			if g.rt.stats.inspected > maxInspected then maxInspected = g.rt.stats.inspected end
		end
		if phase == "end" then break end
	end
	eq(maxInspected, Sweep.INSPECT)
	eq(scans, 3)
end)

test("speed setting: 5 / 10 / 25 renames per window", function()
	for i, want in ipairs({ 5, 10, 25 }) do
		local g = answered({ params = { ["bavr.speed"] = i } })
		fleet(g, 60, { line = 900 })
		local before = #g.sent
		-- one window: updates within the same 2 s
		g.now = math.floor(g.now / 2000) * 2000 + 2000
		for _ = 1, 9 do g:update(200) end
		ok(#g.sent - before <= want, "speed " .. i .. ": " .. (#g.sent - before))
		g:cycles(20, 2000)
		eq(#g.sent, 60, "all renamed eventually")
	end
end)

test("fast path: a settled fleet costs reads only, no model / line re-reads, no renders, no state writes", function()
	local g = answered()
	fleet(g, 300, { line = 900 })
	fleet(g, 100, { line = 901, model = 8 })
	g:cycles(60, 6000)
	eq(#g.sent, 400)
	local sets, mi, ln = g.sets, g.calls.modelInfo, g.calls.lineName
	local render, renders = Text.render, 0
	Text.render = function(...) renders = renders + 1; return render(...) end
	local fast = 0
	for _ = 1, 200 do
		local phase = g:update()
		if phase == "scan" then fast = fast + g.rt.stats.fast end
	end
	Text.render = render
	ok(fast >= 400, "fast " .. fast)
	eq(renders, 0)
	eq(g.sets, sets, "no state writes")
	eq(g.calls.modelInfo, mi, "model info cached")
	ok(g.calls.lineName - ln <= 2 * 20, "line names read once per cycle")
end)

test("pending: a sent name is not sent again while the engine catches up; retries stop after RETRY_MAX", function()
	local g = answered()
	local a = g:buy({ line = 900 })
	for _ = 1, 30 do g:update(200, true) end -- 6 s: renames are queued but never applied
	eq(#g.sent, 1, "pending: sent once")
	for _ = 1, 400 do g:update(200, true) end -- 80 s
	eq(#g.sent, Sweep.RETRY_MAX, "retried, then given up")
	g:update(200, true)
	local failed = 0
	for _ = 1, 20 do
		g:update(200, true)
		failed = failed + g.rt.stats.failed
	end
	for _ = 1, 80 do -- (settled once given up: the backstop re-reads it, at the idle interval)
		g:update(200, true)
		failed = failed + g.rt.stats.failed
	end
	ok(failed >= 1, "counted as failed")
	g.vehicles[a].model = 8 -- an input change renders a new name: sent again
	g:cycles(2, 100)
	eq(g:name(a), "Solaris Urbino B-0001")
end)

test("stand down: nothing at all", function()
	local g = answered()
	fleet(g, 3, { line = 900 })
	local lists = g.calls.list
	local st = g:state()
	st.standDown = "gameburrow_destinationdisplays"
	g.saved = G.copy(st)
	g.rt.standDown = st.standDown -- the game script's own detection (bavr_game.lua) sets it in every Lua state
	for _ = 1, 50 do eq(g:update(), "stand") end
	eq(#g.sent, 0)
	eq(g.calls.list, lists, "no list reads since")
end)

test("loop caps: the vehicle list is cut at MAX_LIST, the pass queue at MAX_PASS", function()
	local g = answered()
	fleet(g, 30, { line = 900 })
	local old = Sweep.MAX_LIST
	Sweep.MAX_LIST = 12
	local capped = false
	for _ = 1, 40 do
		local phase = g:update()
		if phase == "list" and g.rt.stats.capped then capped = true end
	end
	Sweep.MAX_LIST = old
	ok(capped, "list capped")
	eq(g.rt.n <= 12 or g.rt.list == nil, true)
	local p = G.new()
	fleet(p, 20, { line = 900, pt = 5 })
	p:update()
	p:answer("apply")
	local oldP = Reg.MAX_PASS
	Reg.MAX_PASS = 7
	local pc = false
	for _ = 1, 40 do
		p:update()
		if p.rt.stats.capped then pc = true end
	end
	Reg.MAX_PASS = oldP
	ok(pc, "pass queue capped")
	eq(Reg.size(p:state()) >= 7, true)
end)

test("several Lua states: two runtimes on one shared state never give a number twice", function()
	local g = answered()
	fleet(g, 40, { line = 900 })
	local rtA, rtB = g.rt, Sweep.newRuntime()
	for i = 1, 400 do
		g.rt = (i % 3 == 0) and rtB or rtA
		g:update(150)
	end
	local seen = {}
	for id in pairs(g.vehicles) do
		local r = g:rec(id)
		ok(r ~= nil, "numbered " .. id)
		ok(not seen[r.t], "number " .. r.t .. " once")
		seen[r.t] = true
	end
end)

test("cost: a settled 2000-vehicle fleet, 60 s game time (reads: the backstop only; ms informational)", function()
	local g = answered({ share = true, params = { ["bavr.speed"] = 3 } })
	for i = 1, 2000 do g:buy({ line = 900 + i % 2, model = (i % 3 == 0) and 8 or 1 }) end
	g:cycles(90, 20000)
	eq(#g.sent, 2000)
	for _ = 1, 100 do g:update() end -- into the idle back-off
	local r0, l0, n0, gets0 = g.calls.read, g.calls.list, g.calls.lineName, g.gets
	local worst, total, N = 0, 0, 300
	for _ = 1, N do
		g:update()
		total = total + g.stepS
		if g.stepS > worst then worst = g.stepS end
	end
	local reads, lists = g.calls.read - r0, g.calls.list - l0
	-- before this strategy (2026-10-20, the same fake): reads=46000 lists=24, mean 0.118 ms, total 35.4 ms
	print(string.format("60 s game: reads=%d lists=%d lineNames=%d gets=%d, Sweep.step mean %.4f ms, worst %.3f ms, "
		.. "total %.2f ms (fake reader, Lua 5.4)", reads, lists, g.calls.lineName - n0, g.gets - gets0, 1000 * total / N,
		1000 * worst, 1000 * total))
	ok(reads <= 60000 / Sweep.CYCLE_MS * Sweep.BACKSTOP + Sweep.BACKSTOP, "reads: the backstop only (" .. reads .. ")")
	ok(lists <= 60000 / (Sweep.IDLE_MAX_W * Sweep.CYCLE_MS) + 1, "lists at the idle interval: " .. lists)
	eq(g.calls.lineName - n0, 0, "no line format: no line name reads")
	ok(g.gets - gets0 <= math.ceil(60000 / Sweep.PRUNE_MS) + 1, "register reads: " .. (g.gets - gets0))
	ok(worst < 0.02, "a slice stays well under 20 ms even here")
end)

test("cost: the same fleet with a line format (line watch on), 60 s game time (informational; loose bounds)", function()
	local g = answered({ share = true, params = { ["bavr.speed"] = 3, ["bavr.format"] = 5 } })
	for li = 1, 60 do g.lines[2000 + li] = "Line " .. li end
	for i = 1, 2000 do g:buy({ line = 2001 + i % 60 }) end
	g:cycles(90, 20000)
	eq(#g.sent, 2000)
	for _ = 1, 100 do g:update() end
	local c0 = {}
	for k, v in pairs(g.calls) do c0[k] = v end
	local total = 0
	for _ = 1, 300 do
		g:update()
		total = total + g.stepS
	end
	local d = {}
	for k, v in pairs(g.calls) do d[k] = v - c0[k] end
	print(string.format("60 s game, 62 lines: reads=%d lists=%d lines=%d lineVehicles=%d lineNames=%d, Sweep.step "
		.. "mean %.4f ms (fake reader, Lua 5.4)", d.read, d.list, d.lines, d.lineVehicles, d.lineName, 1000 * total / 300))
	ok(d.read <= 60000 / Sweep.CYCLE_MS * Sweep.BACKSTOP + Sweep.BACKSTOP, "reads: the backstop only")
	ok(d.lineVehicles <= 60000 / Sweep.CYCLE_MS * Sweep.LINE_RATE + Sweep.LINE_RATE, "line checks at LINE_RATE")
end)

---------------------------------------------------------------------------
-- The lazy register read (Sweep.stepLazy; PLAN.md "Phase 2")

test("lazy read: untouched (Not now) and hand-named vehicles cost no register read once seen", function()
	local g = G.new()
	local old = fleet(g, 50, { line = 900, pt = 50 })
	g:update()
	g:answer("later")
	local typed = g:buy({ line = 900, pt = g.now + 1, name = "Pride of London" })
	local mine = g:buy({ line = 900, pt = g.now + 1 })
	g:cycles(4, 400)
	eq(g:name(mine), "Mercedes-Benz Citaro B-0002", "the hand-named one holds number 1 in the register")
	eq(g:name(typed), "Pride of London")
	eq(g:name(old[1]), "Road Vehicle " .. old[1])
	local gets = g.gets
	local cycles = 0
	for _ = 1, 400 do -- 80 s
		if g:update() == "end" then cycles = cycles + 1 end
	end
	ok(cycles >= 6, "cycles " .. cycles)
	ok(g.gets - gets <= math.ceil(80000 / Sweep.PRUNE_MS) + 1, "reads " .. (g.gets - gets))
end)

test("lazy read: prune reads the register when a vehicle of the previous list is gone, else skips it", function()
	local g = answered()
	local ids = fleet(g, 20, { line = 900 })
	g:cycles(6, 600)
	local function pruneReads(n)
		local reads = 0
		for _ = 1, n do
			local before = g.gets
			if g:update() == "prune" and g.gets > before then reads = reads + 1 end
		end
		return reads
	end
	g.rt.pruneAt = g.now -- away from the PRUNE_MS backstop
	eq(pruneReads(60), 0, "nothing vanished: no read in prune")
	g:sell(ids[3])
	ok(pruneReads(60) >= 1, "a sale: prune reads")
	eq(g:rec(ids[3]), nil, "pruned")
end)

test("lazy read: a counter below a number this Lua state gave (a lost write) is moved past it, never reused", function()
	local g = answered()
	local a = g:buy({ line = 900 })
	g:cycles(2, 200)
	eq(g:rec(a).t, 1)
	local before = G.copy(g.saved)
	local b = g:buy({ line = 900 })
	g:cycles(2, 200)
	eq(g:rec(b).t, 2)
	-- another Lua state's write replaces ours: b's record and the counter step are lost
	g.saved = before
	local c = g:buy({ line = 900 })
	local race = 0
	for _ = 1, 200 do
		g:update()
		race = race + g.rt.stats.race
	end
	ok(race >= 1, "the lost write was noticed")
	ok(g:rec(c).t > 2, "number 2 is never handed out again: " .. g:rec(c).t)
end)

---------------------------------------------------------------------------
-- Counting "Per line", the old-vehicle marker, train length (PLAN.md "Per line counting", "Old-vehicle marker",
-- "Train length")

local PERLINE = { ["bavr.counter"] = 4, ["bavr.format"] = 2, ["bavr.partSep"] = 4, ["bavr.model"] = 2 }

local function settle(g, n) g:cycles(n or 6, (n or 6) * 100) end

test("per line: numbers restart per line in join order; no line falls back to the per-type number", function()
	local g = answered({ params = PERLINE })
	local a = fleet(g, 3, { line = 900 })
	local b = fleet(g, 2, { line = 901 })
	local free = g:buy({})
	settle(g)
	eq({ g:name(a[1]), g:name(a[2]), g:name(a[3]) }, { "Bus 12 #01 | Citaro", "Bus 12 #02 | Citaro", "Bus 12 #03 | Citaro" })
	eq({ g:name(b[1]), g:name(b[2]) }, { "Harbor Express #01 | Citaro", "Harbor Express #02 | Citaro" })
	eq(g:name(free), "B-0006 | Citaro", "no line: the per-type number")
	eq(g:rec(a[3]).t, 3, "the permanent per-type numbers are kept beside the position")
end)

test("per line: a sale closes the gap (only the vehicles after it are renamed, within the budget); a joiner comes last", function()
	local g = answered({ params = PERLINE })
	local a = fleet(g, 12, { line = 900 })
	local other = fleet(g, 3, { line = 901 })
	settle(g, 10)
	eq(g:name(a[12]), "Bus 12 #12 | Citaro")
	local sent0 = #g.sent
	g:sell(a[5])
	settle(g, 8)
	for i = 1, 4 do eq(g:name(a[i]), string.format("Bus 12 #%02d | Citaro", i), "before the gap: unchanged") end
	for i = 6, 12 do eq(g:name(a[i]), string.format("Bus 12 #%02d | Citaro", i - 1), "after the gap: one up") end
	eq(#g.sent - sent0, 7, "exactly the 7 vehicles after the sold one were renamed")
	for i = 1, 3 do eq(g:name(other[i]), string.format("Harbor Express #%02d | Citaro", i), "other line untouched") end
	-- a vehicle moving from line 901 to 900 goes to the end of 900 and closes up 901
	sent0 = #g.sent
	g.vehicles[other[1]].line = 900
	settle(g, 8)
	eq(g:name(other[1]), "Bus 12 #12 | Citaro")
	eq({ g:name(other[2]), g:name(other[3]) }, { "Harbor Express #01 | Citaro", "Harbor Express #02 | Citaro" })
	eq(#g.sent - sent0, 3, "the mover and the two behind it on its old line")
	-- a new one comes last and renames nobody else
	sent0 = #g.sent
	local n = g:buy({ line = 900 })
	settle(g, 6)
	eq(g:name(n), "Bus 12 #13 | Citaro")
	eq(#g.sent - sent0, 1)
end)

test("per line: closing a long line's gap is spread over windows by the rename budget (no storm)", function()
	local g = answered({ params = { ["bavr.counter"] = 4, ["bavr.format"] = 3, ["bavr.speed"] = 1 } }) -- 5 per window
	local a = fleet(g, 40, { line = 900 })
	g:cycles(30, 4000)
	eq(g:name(a[40]), "Bus 12 #40")
	g:sell(a[1])
	local perWin, last = {}, #g.sent
	for _ = 1, 400 do
		g:update(200)
		local w = math.floor(g.now / 2000)
		perWin[w] = (perWin[w] or 0) + (#g.sent - last)
		last = #g.sent
	end
	for w, n in pairs(perWin) do ok(n <= 5, "window " .. w .. ": " .. n) end
	eq(g:name(a[40]), "Bus 12 #39")
	eq(g:name(a[2]), "Bus 12 #01")
end)

test("per line: a hand-typed vehicle keeps its name and its place; Replace with a new id keeps the place", function()
	local g = answered({ params = PERLINE })
	local a = fleet(g, 4, { line = 900 })
	settle(g)
	g.vehicles[a[2]].name = "Old Faithful"
	settle(g)
	eq(g:name(a[2]), "Old Faithful")
	eq({ g:name(a[3]), g:name(a[4]) }, { "Bus 12 #03 | Citaro", "Bus 12 #04 | Citaro" }, "nobody moved")
	-- Replace that makes a new id: the new vehicle inherits the number and the place on the line
	local sent0 = #g.sent
	g:sell(a[3])
	local r = g:buy({ line = 900, model = 8 })
	settle(g)
	eq(g:name(r), "Bus 12 #03 | Urbino")
	eq(g:name(a[4]), "Bus 12 #04 | Citaro", "no shift and back")
	eq(#g.sent - sent0, 1, "only the replaced vehicle renamed")
end)

test("per line: switching Counting between loads never loses the fleet numbers", function()
	local g = answered({ params = PERLINE })
	local a = fleet(g, 3, { line = 900 })
	settle(g)
	g:sell(a[1])
	settle(g)
	eq(g:name(a[3]), "Bus 12 #02 | Citaro")
	g:setParams({ ["bavr.format"] = 2, ["bavr.partSep"] = 4, ["bavr.model"] = 2 }) -- back to per type
	g:reload()
	settle(g)
	eq({ g:name(a[2]), g:name(a[3]) }, { "B-0002 | Citaro", "B-0003 | Citaro" })
	-- a sale while counting per type, then back to per line: the positions are renumbered once at load
	g:sell(a[2])
	settle(g)
	g.now = g.now + Reg.GONE_MS + 1 -- (a sale and a purchase on the same line within GONE_MS is a Replace)
	local b = g:buy({ line = 900 })
	settle(g)
	g:setParams(PERLINE)
	g:reload()
	settle(g)
	eq({ g:name(a[3]), g:name(b) }, { "Bus 12 #01 | Citaro", "Bus 12 #02 | Citaro" })
end)

test("per line: a settled fleet takes the fast path (no renders, no writes, no position walks)", function()
	local g = answered({ params = PERLINE })
	fleet(g, 300, { line = 900 })
	fleet(g, 100, { line = 901 })
	g:cycles(60, 6000)
	local Reg2 = Reg
	local lp, walks = Reg2.linePositions, 0
	Reg2.linePositions = function(...) walks = walks + 1; return lp(...) end
	local render, renders = Text.render, 0
	Text.render = function(...) renders = renders + 1; return render(...) end
	local sets = g.sets
	for _ = 1, 200 do g:update() end
	Text.render, Reg2.linePositions = render, lp
	eq({ renders, walks, g.sets - sets }, { 0, 0, 0 })
end)

test("old marker: set once the expiry passes, one rename, cleared by a Replace (new purchase time)", function()
	local g = answered({ params = { ["bavr.old"] = 3, ["bavr.format"] = 2, ["bavr.partSep"] = 4 } })
	local exp = g.now + 30000
	local a = g:buy({ line = 900, exp = exp })
	local b = g:buy({ line = 900 }) -- no lifespan known: never old
	settle(g)
	eq(g:name(a), "B-0001 | Mercedes-Benz Citaro")
	local sent0 = #g.sent
	g:cycles(20, 2000)
	ok(g.now > exp)
	eq(g:name(a), "B-0001 | Mercedes-Benz Citaro *")
	eq(g:name(b), "B-0002 | Mercedes-Benz Citaro")
	eq(#g.sent - sent0, 1, "one rename when it turned old")
	-- settled again: the marked name takes the fast path
	local render, renders = Text.render, 0
	Text.render = function(...) renders = renders + 1; return render(...) end
	g:cycles(5, 500)
	Text.render = render
	eq(renders, 0, "no string building while nothing changes")
	-- Replace keeps the id: new parts, new purchase time and expiry
	g.vehicles[a].model, g.vehicles[a].pt, g.vehicles[a].exp = 8, g.now, g.now + 1e9
	settle(g)
	eq(g:name(a), "B-0001 | Solaris Urbino", "the marker clears with the new vehicle")
end)

test("old marker Word: waits for nothing in the sweep (the word comes in the cfg); Off never marks", function()
	local g = answered({ params = { ["bavr.old"] = 4, ["bavr.format"] = 3 } })
	local a = g:buy({ line = 900, exp = 1 })
	settle(g)
	eq(g:name(a), "B-0001 (old)")
	local h = answered({ params = { ["bavr.format"] = 3 } })
	local b = h:buy({ line = 900, exp = 1 })
	settle(h)
	eq(h:name(b), "B-0001", "Off: no marker")
end)

test("train length: rail only, the count follows a changed consist; the cap keeps it", function()
	local g = answered({ params = { ["bavr.trainLen"] = 2, ["bavr.format"] = 2, ["bavr.partSep"] = 4, ["bavr.year"] = 2 } })
	local t = g:buy({ carrier = G.RAIL, model = 3, parts = 9, wagons = 8, year = 1911 })
	local tram = g:buy({ carrier = G.TRAM, model = 7, parts = 3, wagons = 2, year = 1911 })
	settle(g)
	eq(g:name(t), "L-0001 | Class 101 +8 (1911)")
	eq(g:name(tram), "R-0001 | Tatra T3 (1911)", "trams: no count")
	g.vehicles[t].parts, g.vehicles[t].wagons = 11, 10
	settle(g)
	eq(g:name(t), "L-0001 | Class 101 +10 (1911)")
	g:setParams({ ["bavr.trainLen"] = 3, ["bavr.format"] = 2, ["bavr.partSep"] = 4, ["bavr.year"] = 2 })
	g:reload()
	settle(g)
	eq(g:name(t), "L-0001 | Class 101 \195\151" .. "11 (1911)")
end)
