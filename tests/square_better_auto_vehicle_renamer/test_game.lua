-- Better Auto Vehicle Renamer: the game script's logic (bavr_game.lua) against a fake engine: event subscription per
-- load, pause / dt gating, stand-down (detection, state, nothing renamed), the welcome answer and words events, the
-- init log line once per load, rate-limited sweep lines, and how often the register is read (state:get) and written.
-- PLAN.md "Phase 2".

local Game = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_game.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Sweep = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_sweep.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_better_auto_vehicle_renamer/"
local G = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local MOD = Game.MOD_ID

--- A fake engine: the fake game's vehicles and reader, a game-script state that copies on get / set (the worst case),
--- an env, and one Lua state's engine (E). w.step(n, dtMs) runs n updates.
local function world(opts)
	opts = opts or {}
	local g = G.new()
	local w = { g = g, saved = opts.saved, gets = 0, sets = 0, subs = {}, noEvents = 0, lines = {}, speed = 1,
		params = opts.params or { [MOD] = opts.mine or {} }, now = opts.now or 100000, real = 1800000000 }
	w.state = {
		get = function() w.gets = w.gets + 1; return G.copy(w.saved) end,
		set = function(st) w.sets = w.sets + 1; w.saved = G.copy(st) end,
		subscribeToNoEvents = function() w.noEvents = w.noEvents + 1; w.subs = {} end,
		subscribeToEvent = function(name) w.subs[#w.subs + 1] = name end,
		hasEventSubscriptions = function() return #w.subs > 0 end,
	}
	-- the methods take the state as self (state:get())
	local raw = w.state
	w.state = setmetatable({}, { __index = function(_, k)
		local f = raw[k]
		return function(_, ...) return f(...) end
	end })
	w.env = {
		now = function() return w.now end,
		speedup = function() return w.speed end,
		-- the expectations use the first layout (Model + number, automatic separators, no year): pinned unless set
		params = function()
			local mine = w.params[MOD]
			if mine then
				for k, v in pairs({ ["bavr.format"] = 1, ["bavr.partSep"] = 1, ["bavr.year"] = 1 }) do
					if mine[k] == nil then mine[k] = v end
				end
			end
			return w.params
		end,
		log = function(line) w.lines[#w.lines + 1] = line end,
		send = function(id, name)
			if g.vehicles[id] then g.vehicles[id].name = name end
			g.sent[#g.sent + 1] = { id, name, w.now }
		end,
		reader = g.reader,
		tr = function(s) return s end,
		-- the wall clock (os.time in game): w.real, seconds; w.step moves it with game time (1x)
		realTime = function() return w.real end,
	}
	w.E = Game.newEngine()
	function w.step(n, dtMs)
		for _ = 1, n or 1 do
			w.now = w.now + (dtMs or 200)
			w.real = w.real + (dtMs or 200) / 1000
			Game.update(w.E, w.env, w.state, (dtMs or 200) / 1000)
		end
	end
	function w.event(param, E)
		Game.handleEvent(E or w.E, w.env, w.state, Game.EVENT_ID, Game.EV, param)
	end
	function w.st() return Reg.validate(G.copy(w.saved)) end
	function w.grep(pat)
		local n = 0
		for _, l in ipairs(w.lines) do
			if string.find(l, pat) then n = n + 1 end
		end
		return n
	end
	return w
end

local function fleet(w, n, f)
	local ids = {}
	for i = 1, n do
		local o = {}
		for k, v in pairs(f or {}) do o[k] = v end
		ids[i] = w.g:buy(o)
	end
	return ids
end

---------------------------------------------------------------------------

test("subscribes to the GUI event once per Lua state and load (subscriptions are saved with the game)", function()
	local w = world()
	w.step(5)
	eq(w.noEvents, 1)
	eq(w.subs, { Game.EV })
	-- a reload: a new Lua state subscribes again, even though the saved state still has the subscription
	w.E = Game.newEngine()
	w.step(1)
	eq(w.noEvents, 2)
end)

test("paused (speedup 0) or dt 0: no sweep work, no list, no renames", function()
	local w = world()
	fleet(w, 3, { line = 900 })
	w.step(1) -- init
	w.event({ op = "welcome", answer = "apply", number = true })
	w.speed = 0
	local lists = w.g.calls.list
	w.step(100)
	eq(w.g.calls.list, lists, "nothing listed while paused")
	eq(#w.g.sent, 0)
	ok(w.E.paused >= 100)
	w.speed = 1
	for _ = 1, 50 do
		w.now = w.now + 200
		Game.update(w.E, w.env, w.state, 0)
	end
	eq(#w.g.sent, 0, "dt 0: nothing either")
	w.step(200)
	eq(#w.g.sent, 3, "running again: renamed")
end)

test("welcome: nothing renamed before the answer; Apply numbers oldest first; the answer is logged", function()
	local w = world()
	local ids = {}
	for i = 1, 6 do ids[i] = w.g:buy({ line = 900, pt = 90000 - i }) end
	w.step(60)
	eq(#w.g.sent, 0)
	eq(w.st().count, 6, "count published for the window")
	w.event({ op = "welcome", answer = "apply", number = true })
	eq(w.grep("welcome op=answer answer=apply kind=first count=6"), 1)
	w.step(200)
	for i = 1, 6 do eq(w.g:name(ids[i]), string.format("Mercedes-Benz Citaro B-%04d", 7 - i)) end
	ok(w.grep("pass created=6") == 1, "pass logged")
	eq(w.grep("pass progress"), 0, "six renames fit one window: no progress line")
	eq(w.grep("pass done n=6"), 1, "one done line")
	eq(w.st().ptotal, nil, "the done line clears the pass total")
	w.step(200)
	eq(w.grep("pass "), 2, "nothing more (pass created + pass done)")
end)

test("welcome: Apply with the box unticked is Not now; a second answer is ignored", function()
	local w = world()
	local old = fleet(w, 3, { line = 900, pt = 50 })
	w.step(20)
	w.event({ op = "welcome", answer = "apply", number = false })
	eq(w.st().welcome, "later")
	local new = w.g:buy({ line = 900, pt = w.now + 1 }) -- bought after the answer
	w.step(100)
	eq(w.g:name(new), "Mercedes-Benz Citaro B-0001")
	for _, id in ipairs(old) do eq(w.g:name(id), "Road Vehicle " .. id) end
	-- renumber on the next load (setting Yes): the welcome is due again, Apply numbers the rest
	w.params[MOD] = { ["bavr.renumberNext"] = 2 }
	w.E = Game.newEngine()
	w.step(40)
	eq(w.st().count, 3, "the untouched vehicles are counted for the window")
	w.event({ op = "welcome", answer = "apply", number = true })
	eq(w.grep("kind=renumber"), 1)
	w.step(200)
	for i, id in ipairs(old) do eq(w.g:name(id), string.format("Mercedes-Benz Citaro B-%04d", 1 + i)) end
	w.event({ op = "welcome", answer = "later" })
	eq(w.grep("ignored=answered"), 1)
	eq(w.st().welcome, "apply")
end)

test("stand-down: Destination Displays active means no list, no rename; the reason is stored and logged once", function()
	local w = world({ params = { [MOD] = {}, gameburrow_destinationdisplays = {} } })
	fleet(w, 4, { line = 900 })
	w.step(100)
	eq(#w.g.sent, 0)
	eq(w.g.calls.list, 0)
	eq(w.st().standDown, "destination_displays")
	eq(w.grep("standDown reason=destination_displays"), 1)
	-- other Lua states of the same load: no second line
	for _ = 1, 5 do
		w.E = Game.newEngine()
		w.step(1)
	end
	eq(w.grep("standDown reason="), 1)
	eq(w.grep("init "), 1)
	-- Destination Displays removed: the next load clears the stand-down and asks the welcome as usual
	w.params = { [MOD] = {} }
	w.real = w.real + Game.BOOT_REAL_S
	w.E = Game.newEngine()
	w.step(30)
	eq(w.st().standDown, nil)
	eq(w.st().count, 4)
	eq(w.grep("init "), 2, "a new load: one more init line")
end)

test("conflict detection reads the mod params table", function()
	eq(Game.conflict({ gameburrow_destinationdisplays = {} }), "destination_displays")
	eq(Game.conflict({ [MOD] = {} }), nil)
	eq(Game.conflict(nil), nil)
	eq(Game.conflict("x"), nil)
end)

test("words: the GUI's words are stored once and used for the Full word prefix; garbage is ignored", function()
	local w = world({ mine = { ["bavr.prefix"] = 3 } })
	local a = w.g:buy({ line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	-- waiting for the words: nothing renamed
	w.step(50)
	eq(#w.g.sent, 0)
	w.event({ op = "words", words = { B = "Autobus", T = "Lkw", R = "Strassenbahn", L = "Zug", S = "Schiff", A = "Flugzeug",
		H = "Hubschrauber" } })
	eq(w.grep("words src=gui"), 1)
	w.event({ op = "words", words = { B = "Autobus", T = "Lkw", R = "Strassenbahn", L = "Zug", S = "Schiff", A = "Flugzeug",
		H = "Hubschrauber" } })
	eq(w.grep("words src=gui"), 1, "the same words: no second write")
	w.step(100)
	eq(w.g:name(a), "Mercedes-Benz Citaro Autobus-0001")
	local sets = w.sets
	w.event({ op = "words", words = { B = "" } })
	w.event({ op = "words", words = "x" })
	eq(w.sets, sets, "garbage: nothing written")
	-- another Lua state of the same load picks the words up from the state
	local E2 = Game.newEngine()
	w.E = E2
	w.step(1)
	ok(E2.wordsSeen, "seen from the state")
	eq(E2.cfg.words.B, "Autobus")
end)

test("words: without the GUI's words the Full word prefix falls back to English after WORDS_WAIT_MS", function()
	local w = world({ mine = { ["bavr.prefix"] = 3 } })
	local a = w.g:buy({ line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(math.floor(Game.WORDS_WAIT_MS / 200) + 60)
	eq(w.grep("words src=english reason=timeout"), 1)
	eq(w.g:name(a), "Mercedes-Benz Citaro Bus-0001")
end)

test("init line once per load, with the settings and the game script's _() probe", function()
	local w = world()
	w.step(1)
	eq(w.grep("^%[SQFN%] init welcome=nil records=0 .* gsTr=Truck$"), 1)
	w.E = Game.newEngine()
	w.step(1)
	eq(w.grep("init "), 1)
end)

test("sweep lines: only for cycles with work, at most one per LOG_MS per Lua state; errors capped", function()
	local w = world()
	fleet(w, 30, { line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(600) -- 120 s
	local n = w.grep("sweep n=")
	ok(n >= 1, "logged")
	ok(n <= 120000 / Game.LOG_MS + 1, "rate-limited: " .. n)
	local before = w.grep("sweep n=")
	w.step(300) -- settled: no work, no lines
	eq(w.grep("sweep n="), before)
	for i = 1, 20 do Game.error(w.E, w.env, "x", "boom" .. i) end
	eq(w.grep("error where=x"), Game.MAX_ERRORS)
end)

test("state reads: a settled fleet reads the register about once per PRUNE_MS, writes it never", function()
	local w = world()
	fleet(w, 400, { line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(1500) -- numbered and renamed
	eq(#w.g.sent, 400)
	local gets, sets = w.gets, w.sets
	local cycles = 0
	for _ = 1, 600 do -- 120 s game time
		w.step(1)
		if w.E.rt.stats.phase == "end" then cycles = cycles + 1 end
	end
	ok(cycles >= 120000 / (Sweep.IDLE_MAX_W * Sweep.CYCLE_MS) - 1, "cycles " .. cycles .. " (idle back-off)")
	eq(w.sets, sets, "no writes")
	ok(w.gets - gets <= math.ceil(120000 / Sweep.PRUNE_MS) + 1, "reads " .. (w.gets - gets) .. " in " .. cycles .. " cycles")
	-- a sale: the next prune reads the register (and writes the pruned record)
	w.g:sell(w.g.order[1])
	gets = w.gets
	w.step(Sweep.IDLE_MAX_W * Sweep.CYCLE_MS / 200 + 10) -- the next cycle (one idle interval at most)
	ok(w.gets > gets, "read after a vehicle vanished")
	ok(w.sets > sets, "the pruned record written")
end)

test("errors inside a step never escape bavr.script.lua's pcall (sanity: a reader that throws counts as gone)", function()
	local w = world()
	fleet(w, 3, { line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	local read = w.g.reader.read
	w.g.reader.read = function() return false end
	w.step(50)
	w.g.reader.read = read
	eq(#w.g.sent, 0)
	w.step(100)
	eq(#w.g.sent, 3)
end)

---------------------------------------------------------------------------
-- The old-vehicle marker word, the reader's parts flag, the new log fields

test("old marker Word: waits for the GUI's words, then uses the translated marker; the init line names the settings", function()
	local w = world({ mine = { ["bavr.old"] = 4, ["bavr.trainLen"] = 2 } })
	local a = w.g:buy({ line = 900, exp = 1 })
	w.step(1)
	eq(w.grep("init .* old=word trainLen=wagons "), 1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(50)
	eq(#w.g.sent, 0, "waiting for the words")
	w.event({ op = "words", words = { B = "Autobus", T = "Lkw", R = "Strassenbahn", L = "Zug", S = "Schiff",
		A = "Flugzeug", H = "Hubschrauber", O = "(alt)" } })
	w.step(100)
	eq(w.env.reader.wantParts, true, "the reader reads the parts (expiry, train length)")
	eq(w.g:name(a), "Mercedes-Benz Citaro B-0001 (alt)")
	ok(w.grep("sweep .* old=%d+ lineMoved=0 lineWait=0 ") >= 1, "the sweep line counts old vehicles")
end)

test("marker Off and train length Off: the reader skips the parts", function()
	local w = world()
	w.step(3)
	eq(w.env.reader.wantParts, false)
end)

test("per line: the sweep line logs lineMoved after a sale", function()
	local w = world({ mine = { ["bavr.counter"] = 4 } })
	local ids = fleet(w, 4, { line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(200)
	eq(w.g:name(ids[4]), "Mercedes-Benz Citaro Bus 12 #04")
	w.g:sell(ids[1])
	w.step(200)
	eq(w.g:name(ids[4]), "Mercedes-Benz Citaro Bus 12 #03")
	ok(w.grep("sweep .* lineMoved=3 ") >= 1, "three moved up")
end)

test("sweep strategy in the game script: SQPERF sections and counters, the welcome answer wakes the back-off", function()
	local w = world()
	local secs, counts = {}, {}
	w.env.perf = {
		start = function() return 0 end,
		stop = function(_, name) secs[name] = (secs[name] or 0) + 1 end,
		count = function(_, name, n) counts[name] = (counts[name] or 0) + n end,
	}
	fleet(w, 40, { line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(400)
	eq(#w.g.sent, 40)
	ok(secs.list and secs.scan and secs.step, "sections list / scan inside step")
	ok((counts.insFull or 0) >= 40, "a full cycle counted: " .. tostring(counts.insFull))
	w.step(300)
	ok((counts.insBack or 0) > 0, "the backstop counted")
	eq(w.E.rt.ivW, Sweep.IDLE_MAX_W, "idle")
	ok(w.grep("sweep .* listNew=%d+ listGone=%d+ back=%d+ queued=%d+ full=%d+ .* iv=%d+$") >= 1, "the sweep line's new fields")
	-- a renumber answer (another load) wakes the sweep at once
	w.event({ op = "welcome", answer = "apply", number = true }) -- (ignored: answered) no wake needed
	w.E.rt.ivW = Sweep.IDLE_MAX_W
	local st = w.st()
	st.welcome, st.cutoff = "later", w.now
	w.saved = G.copy(st)
	w.event({ op = "welcome", answer = "apply", number = true })
	eq(w.E.rt.ivW, 1, "woken")
end)

test("11 Lua states: pass progress only from the state that renames, one done line, nothing after (a later load too)", function()
	local w = world()
	local N = 120 -- 12 windows of renames at the default budget
	fleet(w, N, { line = 900 })
	local Es = {}
	for i = 1, 11 do Es[i] = Game.newEngine() end
	local tagged = {}
	local function stepAll(n)
		for _ = 1, n do
			w.now = w.now + 200
			for i, E in ipairs(Es) do
				local before = #w.lines
				Game.update(E, w.env, w.state, 0.2)
				for j = before + 1, #w.lines do tagged[#tagged + 1] = { i, w.lines[j], w.now } end
			end
		end
	end
	stepAll(1)
	w.event({ op = "welcome", answer = "apply", number = true }, Es[1])
	local t0 = w.now
	stepAll(1500)
	eq(#w.g.sent, N, "each renamed once")
	local prog, done, from, lastDone = 0, 0, {}, nil
	for _, e in ipairs(tagged) do
		local a, b = string.match(e[2], "pass progress (%d+)/(%d+)")
		if a then
			prog = prog + 1
			from[e[1]] = true
			ok(tonumber(a) < tonumber(b), "progress only while vehicles wait: " .. e[2])
			ok(lastDone == nil, "no progress after the done line")
		end
		if string.find(e[2], "pass done n=" .. N, 1, true) then
			done = done + 1
			lastDone = e[3]
		end
	end
	eq(done, 1, "one done line")
	local senders = 0
	for _ in pairs(from) do senders = senders + 1 end
	ok(prog >= 1 and senders == 1, "progress from one Lua state: " .. prog .. " lines from " .. senders)
	ok(prog <= (lastDone - t0) / Game.LOG_MS + 1, "at most one progress line per LOG_MS: " .. prog)
	eq(w.st().ptotal, nil)
	-- a later load: 11 fresh states, a settled fleet: no pass lines, no sweep lines
	local n0 = #w.lines
	for i = 1, 11 do Es[i] = Game.newEngine() end
	stepAll(300)
	local pass, sweep = 0, 0
	for j = n0 + 1, #w.lines do
		if string.find(w.lines[j], "pass ", 1, true) then pass = pass + 1 end
		if string.find(w.lines[j], "sweep ", 1, true) then sweep = sweep + 1 end
	end
	eq({ pass, sweep }, { 0, 0 }, "settled fleet after a load")
end)

test("a save from before st.rh: its stored pass total (rev 1 never cleared it) is dropped once, nothing logged", function()
	local w = world()
	fleet(w, 10, { line = 900 })
	w.step(1)
	w.event({ op = "welcome", answer = "apply", number = true })
	w.step(300)
	local st = w.st()
	st.ptotal, st.pdone = 410, 3 -- as rev 1 left it (no st.rh yet)
	st.rh, st.boot = nil, nil -- (a new load)
	w.saved = G.copy(st)
	local n0 = #w.lines
	w.E = Game.newEngine()
	w.step(300)
	local pass = 0
	for j = n0 + 1, #w.lines do
		if string.find(w.lines[j], "pass ", 1, true) or string.find(w.lines[j], "rerender ", 1, true) then
			pass = pass + 1
		end
	end
	eq(pass, 0, "no pass progress 410/410 at load, no re-render (same settings)")
	eq({ w.st().ptotal, w.st().pdone, w.st().rh ~= nil }, { nil, nil, true }, "dropped once, st.rh set")
end)

--- 11 Lua states on one register (each runs update with probability p per tick: an LCG, the same run every time);
--- returns the log lines tagged { state, line, now } and a function to run n ticks.
local function states(w, p, seed)
	local Es, tagged, sd = {}, {}, seed or 1
	for i = 1, 11 do Es[i] = Game.newEngine() end
	local function stepAll(n)
		for _ = 1, n do
			w.now = w.now + 200
			w.real = w.real + 0.2
			for i, E in ipairs(Es) do
				sd = (sd * 1103515245 + 12345) % 2147483648
				if p >= 1 or (sd % 1000) < p * 1000 then
					local before = #w.lines
					Game.update(E, w.env, w.state, 0.2)
					for j = before + 1, #w.lines do tagged[#tagged + 1] = { i, w.lines[j], w.now } end
				end
			end
		end
	end
	return Es, tagged, stepAll
end

--- The run lines among tagged[from..]: progress lines (and from how many states), done lines, other run lines.
local function runLines(tagged, from, kind, n)
	local prog, done, senders, other, lastA, firstT, lastT = 0, 0, {}, 0, -1, nil, nil
	for k = from, #tagged do
		local e = tagged[k]
		local a, b = string.match(e[2], kind .. " progress (%d+)/(%d+)")
		if a then
			prog = prog + 1
			senders[e[1]] = true
			ok(tonumber(a) < tonumber(b), "progress only while vehicles wait: " .. e[2])
			eq(tonumber(b), n, "the total: " .. e[2])
			ok(tonumber(a) > lastA, "progress goes up: " .. e[2])
			ok(done == 0, "no progress after the done line")
			lastA = tonumber(a)
			if lastT ~= nil then ok(e[3] - lastT >= Game.LOG_MS, "one progress line per LOG_MS in all") end
			firstT, lastT = firstT or e[3], e[3]
		elseif string.find(e[2], kind .. " done n=" .. n, 1, true) then
			done = done + 1
		elseif string.find(e[2], "pass ", 1, true) or string.find(e[2], "rerender ", 1, true) then
			other = other + 1
		end
	end
	local ns = 0
	for _ in pairs(senders) do ns = ns + 1 end
	return prog, ns, done, other
end

test("re-render (a setting changed between loads): rerender progress a/b from one state, b = the names to redo, one done line", function()
	for _, p in ipairs({ 1, 1 / 11 }) do
		local w = world({ mine = { ["bavr.year"] = 2 } })
		local N = 150
		fleet(w, N, { line = 900, year = 1934 })
		local Es, tagged, stepAll = states(w, 1, 3)
		stepAll(1)
		w.event({ op = "welcome", answer = "apply", number = true }, Es[1])
		stepAll(800)
		eq(w.g:name(w.g.order[1]), "Mercedes-Benz Citaro B-0001 (1934)")
		eq(runLines(tagged, 1, "rerender", N), 0, "the pass is no re-render")
		eq(w.st().rb, nil)
		-- the next load with Purchase year Off: every name of ours is rendered again
		w.params[MOD]["bavr.year"] = 1
		local st = w.st()
		st.boot = nil
		w.saved = G.copy(st)
		local sent0 = #w.g.sent
		Es, tagged, stepAll = states(w, p, 5)
		stepAll(p >= 1 and 600 or 2500)
		eq(#w.g.sent - sent0, N, "p=" .. p .. ": each renamed once")
		eq(w.g:name(w.g.order[1]), "Mercedes-Benz Citaro B-0001")
		local prog, ns, done, other = runLines(tagged, 1, "rerender", N)
		print(string.format("p=%.2f: %d rerender progress lines from %d state(s), %d done line(s)", p, prog, ns, done))
		ok(prog >= 1 and ns == 1, "p=" .. p .. ": progress from one Lua state: " .. prog .. " lines from " .. ns)
		eq(done, 1, "p=" .. p .. ": one done line")
		eq(other, 0, "p=" .. p .. ": no pass line, no other run line")
		eq({ w.st().rb, w.st().rr, w.st().rh ~= nil }, { nil, nil, true })
		-- a later load with the same settings: no run lines
		st = w.st()
		st.boot = nil
		w.saved = G.copy(st)
		Es, tagged, stepAll = states(w, p, 7)
		stepAll(300)
		eq({ runLines(tagged, 1, "rerender", N) }, { 0, 0, 0, 0 }, "p=" .. p .. ": settled: nothing")
	end
end)

test("re-render with nothing to redo (a save from before st.rh, same names): no run line, the run fields cleared", function()
	local w = world()
	local N = 30
	fleet(w, N, { line = 900 })
	local Es, tagged, stepAll = states(w, 1, 9)
	stepAll(1)
	w.event({ op = "welcome", answer = "apply", number = true }, Es[1])
	stepAll(400)
	local st = w.st()
	st.rh, st.boot = nil, nil -- as the first revision left it
	w.saved = G.copy(st)
	local sent0 = #w.g.sent
	Es, tagged, stepAll = states(w, 1, 11)
	stepAll(300)
	eq(#w.g.sent, sent0, "nothing renamed")
	local runs = 0
	for _, e in ipairs(tagged) do
		if string.find(e[2], "rerender ", 1, true) or string.find(e[2], "pass ", 1, true) then runs = runs + 1 end
	end
	eq(runs, 0, "no run line")
	eq({ w.st().rb, w.st().rr, w.st().rh ~= nil }, { nil, nil, true })
end)

---------------------------------------------------------------------------
-- One load, many Lua states; a reload of a save made mid-run (PLAN.md "Sticky lease", "Run lines")

test("a late Lua state (first update 84 s game time after the first, same load): no second init line, lease and run go on", function()
	for _, clock in ipairs({ true, false }) do
		local w = world()
		if not clock then w.env.realTime = nil end -- (no wall clock: the game-time rule, BOOT_MS, as before)
		local N = 600 -- 120 s of renames at the default budget
		fleet(w, N, { line = 900 })
		w.step(1)
		w.event({ op = "welcome", answer = "apply", number = true })
		w.step(420) -- 84 s game time (the 19:20Z load of 2026-10-20: Sim Pool 5's first init 84 s after Sim Pool 6's)
		local st0 = w.st()
		ok(st0.lo ~= nil and st0.ptotal == N and st0.pdone > 0 and st0.pdone < N, "mid-run: " .. tostring(st0.pdone))
		local late = Game.newEngine()
		w.now, w.real = w.now + 200, w.real + 0.2
		Game.update(late, w.env, w.state, 0.2)
		local st1 = w.st()
		eq({ st1.ptotal, st1.pdone, st1.plog }, { st0.ptotal, st0.pdone, st0.plog }, "the run fields stay")
		if clock then
			eq(w.grep("init "), 1, "one init line")
			eq({ st1.lo, st1.lq }, { st0.lo, st0.lq }, "the lease stays")
		else
			eq(w.grep("init "), 2, "no clock: a second init line (84 s > BOOT_MS)")
			eq(st1.lo, nil, "no clock: the lease dropped (the leader writes it back)")
		end
		for _ = 1, 600 do
			w.now, w.real = w.now + 200, w.real + 0.2
			Game.update(w.E, w.env, w.state, 0.2)
			Game.update(late, w.env, w.state, 0.2)
		end
		eq(#w.g.sent, N, "each renamed once")
		eq(w.grep("pass done n=" .. N), 1, "one done line")
		if clock then eq(w.st().lq, st0.lq, "no new claim: the first state led the whole run") end
		eq(w.st().ptotal, nil)
	end
end)

--- A save made mid-run, loaded again: realDt = wall-clock seconds from the save to the load (a new load: past
--- BOOT_REAL_S since the first init; within it, the init takes the reload for the same load).
local function reloadMidRun(realDt)
	local w = world()
	local N = 300
	local ids = fleet(w, N, { line = 900 })
	local Es, tagged, stepAll = states(w, 1, 31)
	stepAll(1)
	w.event({ op = "welcome", answer = "apply", number = true }, Es[1])
	stepAll(150) -- 30 s game time: about half renamed
	-- the save: register, game time, names
	local save, saveNow, names = G.copy(w.saved), w.now, {}
	for _, id in ipairs(ids) do names[id] = w.g:name(id) end
	local pdone0 = save.pdone or 0
	ok(save.lo ~= nil and save.ptotal == N and pdone0 > 0 and pdone0 < N, "saved mid-run: " .. pdone0)
	stepAll(50) -- played on after saving (lost at the reload)
	-- the reload: the save's register, game time and names; new Lua states (the old ones kept: no token comes back)
	local old = Es
	w.saved, w.now, w.real = G.copy(save), saveNow, w.real + realDt
	for _, id in ipairs(ids) do w.g.vehicles[id].name = names[id] end
	local n0, sent0 = #w.lines, #w.g.sent
	Es, tagged, stepAll = states(w, 1, 33)
	stepAll(600)
	ok(old ~= nil)
	local inits = 0
	for j = n0 + 1, #w.lines do
		if string.find(w.lines[j], "init ", 1, true) then inits = inits + 1 end
	end
	eq(#w.g.sent - sent0, N - pdone0, "the rest renamed, each once")
	local firstT = w.g.sent[sent0 + 1][3]
	local alive = false
	for _, E in ipairs(Es) do
		if E.rt.me == w.st().lo then alive = true end
	end
	ok(alive, "the lease names a Lua state of the new load")
	local prog, ns, done, other = runLines(tagged, 1, "pass", N)
	eq({ ns <= 1, done, other }, { true, 1, 0 }, "progress from one state, one done line, nothing else")
	for _, e in ipairs(tagged) do
		local a = string.match(e[2], "pass progress (%d+)/")
		if a then ok(tonumber(a) > pdone0, "the save's count goes on: " .. e[2]) end
	end
	print(string.format("reload mid-run (%d s real later): %d of %d done at the save, first rename %d ms after the load, "
		.. "%d init line(s), %d progress line(s)", realDt, pdone0, N, firstT - saveNow, inits, prog))
	for _, id in ipairs(ids) do
		eq(w.g:name(id), string.format("Mercedes-Benz Citaro B-%04d", Reg.get(w.st(), id).t))
	end
	eq({ w.st().ptotal, w.st().pdone }, { nil, nil })
	return inits, firstT - saveNow, save, saveNow
end

test("a reload of a save made mid-run: one init line, the lease dropped, the run goes on to one done line", function()
	local inits, wait = reloadMidRun(600)
	eq(inits, 1, "one init line for the load")
	ok(wait <= 4 * Sweep.CYCLE_MS, "renames resume at once: " .. wait .. " ms")
end)

test("a reload within BOOT_REAL_S (taken for the same load): no init line, the save's lease ends by game time", function()
	local inits, wait, save, saveNow = reloadMidRun(20)
	eq(inits, 0, "no init line (cosmetic)")
	ok(saveNow + wait >= save.le + Sweep.LEASE_MARGIN_MS, "nobody renames under the save's lease")
	ok(wait <= Sweep.LEASE_MS + Sweep.LEASE_MARGIN_MS + 3 * Sweep.CYCLE_MS, "re-claimed within the bound: " .. wait .. " ms")
end)
