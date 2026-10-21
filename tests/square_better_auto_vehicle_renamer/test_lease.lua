-- Better Auto Vehicle Renamer: the rename lease (bavr_sweep.lua "The rename lease", PLAN.md "Rename lease") with 11
-- Lua states on one register, as in game (update runs in ~11 "Sim Pool" Lua states: docs/findings/game-scripts.md).
-- Four ways the states can meet the state store: serial (each get / set in turn: the evidence of session
-- 2026-10-20_0539_sqot-sqfn), concurrent (every state running in a tick reads the tick's snapshot, the last write
-- wins: lost writes every tick), an injected lost write (an old copy written back mid-pass, erasing the lease and
-- the window count) and stale (half the reads miss the latest write; with each state running in ~1/11 of the
-- ticks: the 08:15Z run of 2026-10-20, where the old lease hopped between states). The global rename rate per 2 s
-- window must stay within the budget in all of them.

local Sweep = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_sweep.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_better_auto_vehicle_renamer/"
local G = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local FULL = os.getenv("TEST_FULL") ~= nil
local STATES = 11

--- n vehicles (older ones with higher ids), Apply answered; nStates runtimes; a seeded random order per tick.
local function world(n, seed, opts)
	opts = opts or {}
	local g = G.new({ params = opts.params })
	local ids = {}
	for i = 1, n do ids[i] = g:buy({ line = 900, pt = 100000 - i * 10, year = opts.year }) end
	g:update()
	g:answer("apply")
	local w = { g = g, ids = ids, rts = {}, perWin = {}, sends = {}, nSent = 0, seed = seed or 1,
		prev = nil, lastSender = nil, handovers = 0, senders = {}, firstT = nil, lastT = nil, t = 0, winUsed = {} }
	for i = 1, STATES do w.rts[i] = Sweep.newRuntime() end
	local function rnd(m) -- LCG: the same run every time
		w.seed = (w.seed * 1103515245 + 12345) % 2147483648
		return w.seed % m + 1
	end
	--- One sim tick (200 ms): each state runs with probability p (in a random order). mode "serial": each fetch
	--- sees the last write; "concurrent": every fetch of the tick sees the tick's first snapshot and the writes land
	--- in order (the last one wins); "stale": like serial, but half the fetches see the store as it was before its
	--- latest write (a snapshot one update old). Renames reach the vehicles after the tick (the engine's commands).
	function w.tick(mode, p)
		g.now = g.now + 200
		w.t = w.t + 1
		local order = {}
		for i = 1, STATES do
			if rnd(100) <= p * 100 then order[#order + 1] = w.rts[i] end
		end
		for i = #order, 2, -1 do
			local j = rnd(i)
			order[i], order[j] = order[j], order[i]
		end
		local snap, writes, ops = g.saved, {}, {}
		for _, rt in ipairs(order) do
			local function fetch()
				g.gets = g.gets + 1
				local src = g.saved
				if mode == "concurrent" then
					src = snap
				elseif mode == "stale" and w.prev ~= nil and rnd(100) <= 50 then
					src = w.prev
				end
				return Reg.validate(G.copy(src))
			end
			local _, st = Sweep.stepLazy(rt, g.cfg, g.reader, g.now, fetch)
			for i = 1, rt.nops do ops[#ops + 1] = { rt.ops[2 * i - 1], rt.ops[2 * i] } end
			if rt.nops > 0 then
				if w.lastSender ~= nil and w.lastSender ~= rt then w.handovers = w.handovers + 1 end
				w.lastSender = rt
				w.senders[rt] = true
				w.firstT = w.firstT or w.t
				w.lastT = w.t
			end
			if rt.dirty then
				if mode == "concurrent" then
					writes[#writes + 1] = G.copy(st)
				else
					w.prev = g.saved
					g.saved = G.copy(st)
				end
			end
		end
		for i = 1, #writes do g.saved = writes[i] end
		local win = math.floor(g.now / Sweep.CYCLE_MS)
		w.perWin[win] = (w.perWin[win] or 0) + #ops
		if #ops > 0 then w.winUsed[win] = true end
		for _, op in ipairs(ops) do
			if g.vehicles[op[1]] then g.vehicles[op[1]].name = op[2] end
			w.sends[op[1]] = (w.sends[op[1]] or 0) + 1
			w.nSent = w.nSent + 1
		end
	end
	function w.allNamed()
		for _, id in ipairs(ids) do
			if not string.find(g:name(id), "^Mercedes%-Benz Citaro B%-%d+$") then return false end
		end
		return true
	end
	--- ticks until every vehicle shows a fleet name (error past maxTicks); returns the ticks it took
	function w.run(mode, p, maxTicks, each)
		for t = 1, maxTicks do
			w.tick(mode, p)
			if each then each(t) end
			if w.allNamed() then return t end
		end
		error(mode .. " p=" .. p .. ": not all named within " .. maxTicks .. " ticks")
	end
	function w.maxPerWin()
		local m, over = 0, 0
		for _, c in pairs(w.perWin) do
			if c > m then m = c end
			if c > g.cfg.budget then over = over + 1 end
		end
		return m, over
	end
	--- the rename run so far: windows from its first to its last rename, windows with a rename, senders, handovers
	function w.runStats()
		local used, ns = 0, 0
		for _ in pairs(w.winUsed) do used = used + 1 end
		for _ in pairs(w.senders) do ns = ns + 1 end
		local span = w.firstT and ((w.lastT - w.firstT) * 200 / Sweep.CYCLE_MS + 1) or 0
		return span, used, ns, w.handovers
	end
	--- forget the run so far (a new run starts counting)
	function w.resetRun()
		w.perWin, w.winUsed, w.senders, w.sends = {}, {}, {}, {}
		w.nSent, w.handovers, w.lastSender, w.firstT, w.lastT = 0, 0, nil, nil, nil
	end
	--- a load (new params when given): new Lua states (the old ones kept referenced: no token comes back), the lease
	--- dropped (the game script's first init of a new load), or kept (keepLease: a reload the init took for the
	--- same load; it ends by game time)
	function w.reload(params, keepLease)
		w.old = w.old or {}
		for i = 1, STATES do
			w.old[#w.old + 1] = w.rts[i]
			w.rts[i] = Sweep.newRuntime()
		end
		if not keepLease then g.saved.lo, g.saved.le, g.saved.lq = nil, nil, nil end
		if params ~= nil then g:setParams(params) end
		w.prev = nil
	end
	--- every vehicle numbered once, numbers unique, and the name shows its number
	function w.checkNumbers()
		local seen = {}
		for _, id in ipairs(ids) do
			local r = g:rec(id)
			ok(r ~= nil, "numbered " .. id)
			ok(not seen[r.t], "number " .. r.t .. " once")
			seen[r.t] = true
			eq(g:name(id), string.format("Mercedes-Benz Citaro B-%04d", r.t))
		end
	end
	return w
end

local N = 300 -- 30 windows of renames at the default budget (10)

test("11 Lua states, serial store: at most the budget per window in all, each vehicle renamed once, one sender", function()
	for _, p in ipairs(FULL and { 1, 0.5, 0.3, 0.1 } or { 1, 0.3 }) do
		local w = world(N, 7)
		local senders = {}
		local ticks = w.run("serial", p, 20000, function()
			for i, rt in ipairs(w.rts) do
				if rt.nops > 0 then senders[i] = true end
			end
		end)
		local m, over = w.maxPerWin()
		ok(m <= w.g.cfg.budget, "p=" .. p .. ": max " .. m .. " per window")
		eq(over, 0)
		eq(w.nSent, N, "p=" .. p .. ": each vehicle renamed once")
		w.checkNumbers()
		local ns = 0
		for _ in pairs(senders) do ns = ns + 1 end
		-- sticky lease: one sender even when each state runs in only some ticks (before: 7 senders at p = 0.1)
		eq(ns, 1, "p=" .. p .. ": one Lua state sent every rename")
		-- the pass is not much slower than the budget allows (N / budget windows), even when each state runs in
		-- only some ticks (the windows the leader runs in set the pace; before: 138 windows at p = 0.1)
		local windows = ticks * 200 / Sweep.CYCLE_MS
		print(string.format("serial p=%.1f: %d renames in %.0f windows (max %d per window), %d sender(s)", p, w.nSent,
			windows, m, ns))
		ok(windows <= (N / w.g.cfg.budget) * (p >= 0.3 and 1.5 or 2.5) + 10,
			"p=" .. p .. ": " .. windows .. " windows for " .. N .. " renames")
	end
end)

test("11 Lua states, concurrent store (every tick's writes but the last are lost): still at most the budget per window", function()
	for _, p in ipairs(FULL and { 1, 0.5, 0.3 } or { 1, 0.5 }) do
		local w = world(N, 11)
		local ticks = w.run("concurrent", p, 30000)
		local m, over = w.maxPerWin()
		print(string.format("concurrent p=%.1f: %d sends for %d vehicles in %.0f windows (max %d per window)", p, w.nSent,
			N, ticks * 200 / Sweep.CYCLE_MS, m))
		ok(m <= w.g.cfg.budget, "p=" .. p .. ": max " .. m .. " per window")
		eq(over, 0)
		w.checkNumbers()
		-- a lost write can drop the pending mark of a send; the name already arrived, so a second send is rare
		ok(w.nSent <= N + N / 10, "p=" .. p .. ": sends " .. w.nSent)
	end
end)

test("lost write mid-pass: an old copy written back (no lease, window count 0) never lets the rate exceed the budget", function()
	for _, at in ipairs(FULL and { 23, 40, 57, 91, 130 } or { 40, 91 }) do
		local w = world(N, 3)
		local old = nil
		w.run("serial", 1, 20000, function(t)
			if t == 10 then old = G.copy(w.g.saved) end -- the pass numbered, no lease yet
			if t == at then
				-- the leader just renamed in this window; another state's stale write lands on top of it
				ok(w.g.saved.lo ~= nil, "a leader exists before the lost write")
				local back = G.copy(old)
				back.lo, back.le, back.used, back.win = nil, nil, 0, nil
				w.g.saved = back
			end
		end)
		local m, over = w.maxPerWin()
		ok(m <= w.g.cfg.budget, "lost write at tick " .. at .. ": max " .. m .. " per window")
		eq(over, 0)
		w.checkNumbers()
	end
end)

test("two claims racing (both from one snapshot): only the later write leads, the other renames nothing", function()
	local w = world(40, 5)
	-- both states reach their first rename in the same tick, reading the same snapshot
	for _ = 1, 400 do
		w.tick("concurrent", 1)
		if w.allNamed() then break end
	end
	ok(w.allNamed(), "all named")
	local senders = 0
	for _, rt in ipairs(w.rts) do
		if rt.leads then senders = senders + 1 end
	end
	eq(senders, 1, "one leader")
	local m = w.maxPerWin()
	ok(m <= w.g.cfg.budget, "max " .. m)
end)

test("lease lapse: after LEASE_MS without renames another Lua state can lead; a reload drops the lease", function()
	local w = world(20, 9)
	w.run("serial", 1, 4000)
	local st = w.g:state()
	local leader = st.lo
	ok(leader ~= nil, "a lease")
	-- idle past the lease: a new vehicle bought, seen first by a state that never led
	for _ = 1, Sweep.LEASE_MS / 200 + 5 do w.tick("serial", 1) end
	local id = w.g:buy({ line = 900 })
	local t0 = w.g.now
	while w.g:name(id) ~= "Mercedes-Benz Citaro B-0021" do
		w.tick("serial", 1)
		ok(w.g.now - t0 <= Sweep.IDLE_MAX_W * Sweep.CYCLE_MS + 2 * Sweep.CYCLE_MS + 1000, "named within an idle interval + 2 windows")
	end
	ok(w.g:state().lo ~= nil, "led by someone")
	-- the register validates the lease fields
	local bad = w.g:state()
	bad.lo, bad.le = 5, "x"
	local v = Reg.validate(bad)
	eq({ v.lo, v.le }, { nil, nil })
	w.g:reload()
	eq(w.g.saved.lo, nil, "a load drops the lease")
end)

test("a dead state's lease (a reload the init took for the same load) ends by game time, re-claimed within LEASE_MS + margin", function()
	for _, mode in ipairs({ "serial", "stale" }) do
		local w = world(40, 13)
		-- save mid-run: the leader's lease is live in the register
		for _ = 1, 4000 do
			w.tick(mode, 1)
			local st = w.g.saved
			if st.lo ~= nil and w.nSent >= 10 then break end
		end
		ok(not w.allNamed(), mode .. ": saved mid-run")
		local saved = w.g:state()
		ok(saved.lo ~= nil and saved.le > w.g.now, mode .. ": a live lease in the save")
		local le, lq = saved.le, saved.lq
		w.reload(nil, true)
		w.resetRun()
		local t0 = w.g.now
		w.run(mode, 1, 4000)
		ok(w.firstT ~= nil, mode .. ": renamed after the reload")
		-- the dead token holds the lease until its end + the margin, then one claim of a new epoch
		local firstMs = w.g.now - (w.t - w.firstT) * 200 -- (w.firstT: the tick of the first rename since resetRun)
		ok(firstMs >= le + Sweep.LEASE_MARGIN_MS, mode .. ": nobody renames under the dead lease")
		ok(firstMs - t0 <= Sweep.LEASE_MS + Sweep.LEASE_MARGIN_MS + 3 * Sweep.CYCLE_MS,
			mode .. ": the first rename " .. (firstMs - t0) .. " ms after the load")
		local st = w.g:state()
		ok(st.lq > lq, mode .. ": a new epoch")
		local alive = false
		for _, rt in ipairs(w.rts) do
			if rt.me == st.lo then alive = true end
		end
		ok(alive, mode .. ": the lease names a Lua state of the new load")
		local m, over = w.maxPerWin()
		ok(m <= w.g.cfg.budget, mode .. ": max " .. m)
		eq(over, 0)
		w.checkNumbers()
	end
end)

--- The game run of 2026-10-20 08:15Z (PLAN.md "Rename lease (2026-10-20)"): Purchase year switched Off between
--- loads, 483 names re-rendered by ~11 Lua states that each run update in only some ticks (~1/11), half the reads
--- one write stale. Before the sticky lease (seeds 1 / 2): 427 / 414 windows from the first to the last rename, 10 / 9
--- senders, 22 / 27 handovers, and one window with 20 renames (a stale read let two states lead).
local function sparseRerender(seed)
	local n = 483
	local ideal = math.ceil(n / 10)
	local w = world(n, seed, { year = 1934, params = { ["bavr.year"] = 2 } })
	-- the Apply pass with the year shown (fast: every state in every tick)
	local all = false
	for _ = 1, 4000 do
		w.tick("serial", 1)
		all = true
		for _, id in ipairs(w.ids) do
			if not string.find(w.g:name(id), "%(1934%)$") then all = false; break end
		end
		if all then break end
	end
	ok(all, "the pass named every vehicle with its year")
	w.reload({ ["bavr.year"] = 1 })
	w.resetRun()
	local ticks = w.run("stale", 1 / 11, 20000)
	local span, used, ns, hand = w.runStats()
	local m, over = w.maxPerWin()
	print(string.format("stale p=1/11 seed %d: %d renames, %.0f windows from the first to the last rename "
		.. "(ideal %d), %d windows with renames, %d sender(s), %d handover(s), max %d per window, %d ticks", seed,
		w.nSent, span, ideal, used, ns, hand, m, ticks))
	ok(m <= w.g.cfg.budget, "max " .. m .. " per window")
	eq(over, 0)
	eq(w.nSent, n, "each vehicle renamed once")
	ok(hand <= 1, hand .. " handovers")
	-- the leader runs in ~61 % of the windows (1 - (10/11)^10): about ideal / 0.61 = 80 windows at best
	ok(span <= ideal * 2.5, span .. " windows")
	w.checkNumbers()
end

test("sparse Lua states, stale reads: a 483-vehicle re-render keeps one sender near the budget (a)", function()
	for _, seed in ipairs(FULL and { 1, 2, 3 } or { 1 }) do sparseRerender(seed) end
end)

test("sparse Lua states, stale reads: a 483-vehicle re-render keeps one sender near the budget (b)", function()
	for _, seed in ipairs(FULL and { 4, 5, 6 } or { 4 }) do sparseRerender(seed) end
end)
