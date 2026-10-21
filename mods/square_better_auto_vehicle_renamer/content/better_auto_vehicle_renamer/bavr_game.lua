-- Better Auto Vehicle Renamer: the game script's logic per Lua state (update, the GUI's events, stand-down, logs).
-- Lua 5.1 syntax; every game call goes through `env` (bavr.script.lua builds it on the real API, tests on a fake one),
-- so this module holds no api.* at all. PLAN.md "Phase 2".
--
-- Entry points (bavr.script.lua, each call inside its pcall):
--   Game.newEngine() -> E                       one per Lua state (module local)
--   Game.update(E, env, state, dt)              the game script's update
--   Game.handleEvent(E, env, state, id, name, param)
--   Game.conflict(allModParams) -> reason | nil  ("destination_displays" while Gameburrow's Destination Displays is
--       active: getModParams() has an entry for every active mod, docs/findings/scripting.md)
-- env: now() -> game ms | nil (GAME_TIME.gameTime), speedup() -> number | nil (GAME_SPEED.speedup, 0 = paused),
--   params() -> getModParams(), log(line), send(id, name) (makeEntitySetNameCmd, entityExists checked right
--   before, no callback), reader (bavr_reader.lua), perf (SQPERF instrument; optional), tr(s) (optional: the game
--   script's _(), only probed for the init log line), realTime() -> wall-clock seconds | nil (optional: os.time,
--   only for telling one load's Lua states from the next for the init line).
--
-- Update, per Lua state: subscribe to the GUI event once per load (subscriptions are saved with the game, so a
-- load re-subscribes: docs/findings/scripting.md); init once (settings, stand-down, the init log line); then, while
-- the game runs (speedup > 0, dt > 0), one Sweep.stepLazy slice; the register is read (state:get) only when the
-- slice needs it, written (state:set) only when it changed. SQPERF sections: update (all), get (state:get +
-- validate), step (the slice, its reads included), set (state:set), event (handleEvent), and inside step the
-- sweep's own list (list + id diff), lines (the line watch), scan (the vehicle reads); counters renamed, and per
-- kind of vehicle read: insNew (new ids), insBack (the backstop), insQueue (retried / line watch), insFull (full
-- cycles), carried (left unread for the next cycle: the rename budget was spent).
-- Log lines ([SQFN], rate-limited, never per vehicle): init (once per load), standDown reason=, sweep (a cycle with
-- work, at most every LOG_MS game ms per Lua state), the run lines (below), welcome op=answer, words src=, error (at
-- most MAX_ERRORS per Lua state).
-- Run lines: a rename run is an Apply pass (st.ptotal: the vehicles it numbered) or a re-render (a load whose
-- settings hash differs from the one the names were rendered with, st.rh; st.rb: the names of ours then). The Lua
-- state that sends renames (the lease holder) counts them in the register (st.pdone / st.rr, in its write anyway)
-- and logs "pass progress a/b" or "rerender progress a/b" at most once per LOG_MS in all (st.plog), only while
-- a < b; the run ends at a cycle of the leader (or a full cycle of any state) with no vehicle waiting: one "pass
-- done n=" (the vehicles numbered) or "rerender done n=" (the renames sent; none when nothing needed one) line, and
-- the run fields are cleared. Run fields stored in a save carry over a load: the save's unfinished run goes on (its
-- progress keeps counting). A save from before st.rh (rev 1, run fields never cleared) drops its pass total once,
-- at the load that sets st.rh. The rename lease is dropped at the first init of a new load (firstOfLoad: no Lua
-- state of the last load lives on), never by a late Lua state of the same load; a lease the rule misses (a reload it
-- takes for the same load) ends by game time, at most LEASE_MS + LEASE_MARGIN_MS after the load.

local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Sweep = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_sweep.lua"

local M = {}

M.MOD_ID = Settings.MOD_ID
M.EVENT_ID = Settings.MOD_ID
M.EV = "BAVR.gui"                 -- the GUI's event name (op = welcome | words | sdseen)
M.GS_NAME = "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr.gs"
M.TAG = "[SQFN]"
M.LOG_MS = 10000                  -- game ms between two sweep / pass lines of one Lua state
M.BOOT_MS = 60000                 -- no wall clock: an init within this game ms of the stored boot is the same load
M.BOOT_REAL_S = 300               -- an init within this many real seconds of the stored boot (game time not gone
                                  -- back) is the same load: no init line (see initOnce)
M.WORDS_WAIT_MS = 30000           -- "Full word" prefix: game ms to wait for the GUI's translated words
M.MAX_ERRORS = 5                  -- error lines per Lua state

-- mods that rename vehicles themselves: we stand down while one is active (PLAN.md "Conflicts")
M.CONFLICTS = {
	{ modId = "gameburrow_destinationdisplays", reason = "destination_displays" }, -- i18n: ignore
}

local NOPERF = { start = function() return 0 end, stop = function() end, count = function() end }

function M.conflict(all)
	if type(all) ~= "table" then return nil end
	for i = 1, #M.CONFLICTS do
		local c = M.CONFLICTS[i]
		if all[c.modId] ~= nil then return c.reason end
	end
	return nil
end

-- sweep stats summed over the cycles between two sweep log lines
local ACC_KEYS = { "inspected", "fast", "renamed", "new", "deferred", "user", "untouched", "skipped", "depot",
	"pruned", "matched", "replaced", "reused", "modelChanged", "failed", "dup", "gone", "gets", "race", "collected",
	"passCreated", "waiting", "old", "lineMoved", "lineWait", "listNew", "listGone", "back", "queued", "full",
	"expDue", "carried", "lineChecks", "lineHits", "listErr", "lineErr", "follow", "claims" }
-- SQPERF counters per kind of vehicle read (sweep stats -> counter name)
local PERF_COUNTS = { { "listNew", "insNew" }, { "back", "insBack" }, { "queued", "insQueue" }, { "full", "insFull" },
	{ "carried", "carried" } }
-- a cycle with any of these logs a line
local WORK_KEYS = { "renamed", "new", "pruned", "matched", "replaced", "reused", "modelChanged", "failed", "race",
	"passCreated", "lineMoved", "lineHits", "listErr", "lineErr" }

function M.newEngine()
	local E = { rt = Sweep.newRuntime(), cfg = nil, mine = nil, subscribed = false, init = false, conflict = nil,
		t0 = nil, validated = false, wordsKey = nil, wordsSeen = false, wordsW = nil, wordsLogged = false,
		lastLog = nil, ptotal = nil, rb = nil, runLed = false, errors = 0, acc = {}, accCycles = 0, sets = 0, paused = 0 }
	for i = 1, #ACC_KEYS do E.acc[ACC_KEYS[i]] = 0 end
	return E
end

local function emit(env, text)
	pcall(env.log, M.TAG .. " " .. text)
end

function M.error(E, env, where, err)
	if E.errors >= M.MAX_ERRORS then return end
	E.errors = E.errors + 1
	emit(env, "error where=" .. tostring(where) .. " err=" .. tostring(err))
end

local function setCfg(E, words)
	E.cfg = Settings.parse(E.mine, words) -- a new hash: the sweep's caches and fast path follow it
end

--- What a register read tells this Lua state beyond the sweep: the GUI's words (the settings when they changed).
local function noteState(E, st)
	if st.words ~= nil then
		local key = Reg.wordsKey(st.words)
		if key ~= E.wordsKey then
			E.wordsKey = key
			setCfg(E, st.words)
		end
		E.wordsSeen = true
	end
	E.ptotal, E.rb = st.ptotal, st.rb
end

local function makeFetch(E, env, state, perf)
	return function()
		local t0 = perf:start()
		local raw = state:get()
		local st
		if E.validated then
			st = Reg.validateLight(raw)
		else
			st = Reg.validate(raw)
			E.validated = true
		end
		perf:stop("get", t0)
		noteState(E, st)
		return st
	end
end

local function write(E, state, st, perf)
	local t0 = perf:start()
	state:set(st)
	perf:stop("set", t0)
	E.sets = E.sets + 1
end

local function subscribe(E, state)
	if E.subscribed then return end
	E.subscribed = true
	state:subscribeToNoEvents()
	state:subscribeToEvent(M.EV)
end

--- Wall-clock seconds (env.realTime: os.time in game), nil when missing or unusable.
local function realNow(env)
	if type(env.realTime) ~= "function" then return nil end
	local ok, t = pcall(env.realTime)
	if not ok or type(t) ~= "number" or t ~= t or t < 0 or t == math.huge then return nil end
	return t
end

--- Whether this init is the first of a load (the init log line, the lease drop). Each Lua state's
--- first update comes at its own time: in the 19:20Z load of 2026-10-20 one came 84 s game time after the first,
--- so game time alone can't tell a late Lua state from a reload (a reload starts at the save's game time, which is
--- at or past the boot stored in it too). Same load: game time did not go back, and the wall clock says the stored
--- boot is recent (BOOT_REAL_S: well above the observed spread of first updates, far below a quit-and-reload of a
--- big save after some play). Either mistake is safe: a reload within BOOT_REAL_S of the first init of the session
--- that saved it skips its init line and keeps the save's lease (it ends by game time: renames wait up to ~30 s
--- game time); a Lua state whose first update comes later than that logs a second init line and drops the live
--- lease (the leader writes it back or another state claims it: a lost write, which the lease tolerates). Without
--- a wall clock: the game-time rule (BOOT_MS).
local function firstOfLoad(st, now, real)
	if st.boot == nil or now == nil or now < st.boot then return true end
	if real ~= nil and st.bootT ~= nil then
		return real < st.bootT or real - st.bootT >= M.BOOT_REAL_S
	end
	return now - st.boot >= M.BOOT_MS
end

--- The run a load starts with, for the init line: pass:a/b, rerender:a/b or none.
local function runText(st)
	if st.ptotal ~= nil then return string.format("pass:%d/%d", st.pdone or 0, st.ptotal) end
	if st.rb ~= nil then return string.format("rerender:%d/%d", st.rr or 0, st.rb) end
	return "none"
end

--- Once per Lua state per load: settings, stand-down, the state's own fields, the init line (first state only).
local function initOnce(E, env, state, perf, now)
	E.init = true
	local okP, all = pcall(env.params)
	if not okP then all = nil end
	E.mine = type(all) == "table" and all[M.MOD_ID] or nil
	E.conflict = M.conflict(all)
	setCfg(E, nil)
	E.rt.standDown = E.conflict
	local st = makeFetch(E, env, state, perf)()
	local changed = false
	if st.standDown ~= E.conflict then
		st.standDown = E.conflict
		changed = true
	end
	local real = realNow(env)
	local first = firstOfLoad(st, now, real)
	if first and now ~= nil then
		-- a new load: no Lua state of the last one lives on, so its rename lease is dropped (else every state of
		-- this load waits for it to end and they all claim at once; bavr_sweep.lua); the run fields stay (header)
		st.boot, st.bootT = now, real
		st.lo, st.le, st.lq = nil, nil, nil
		changed = true
	end
	local rh0 = st.rh
	-- a re-render: the names were rendered with other settings (or this save predates st.rh)
	if E.conflict == nil and st.welcome ~= nil and E.cfg.hash ~= st.rh then
		local n = Reg.ours(st)
		if st.rh == nil then
			-- a save from before st.rh: its pass total is from a finished run (rev 1 never cleared it)
			st.ptotal, st.pdone, st.plog = nil, nil, nil
		end
		st.rh = E.cfg.hash
		if n > 0 then st.rb, st.rr = n, 0 else st.rb, st.rr = nil, nil end
		changed = true
	end
	E.ptotal, E.rb = st.ptotal, st.rb
	if changed then write(E, state, st, perf) end
	if first then
		local tr = "n/a"
		if type(env.tr) == "function" then
			local okT, t = pcall(env.tr, "Truck")
			tr = okT and tostring(t) or "error"
		end
		local cfg = E.cfg
		emit(env, string.format("init welcome=%s records=%d count=%s pass=%s standDown=%s format=%s prefix=%s "
			.. "counter=%s year=%s old=%s trainLen=%s speed=%d words=%s hash=%s rh=%s run=%s gsTr=%s", tostring(st.welcome),
			Reg.size(st), tostring(st.count), tostring(st.pass ~= nil), tostring(E.conflict), cfg.format, cfg.prefix,
			cfg.counter, cfg.year, cfg.old, cfg.trainLen, cfg.budget, st.words ~= nil and "gui" or "english", cfg.hash,
			tostring(rh0), runText(st), tr))
		if E.conflict ~= nil then emit(env, "standDown reason=" .. E.conflict .. " renamed=none") end
	end
end

local function accumulate(E, s)
	local acc = E.acc
	for i = 1, #ACC_KEYS do
		local k = ACC_KEYS[i]
		acc[k] = acc[k] + (s[k] or 0)
	end
	if s.capped then acc.capped = true end
end

local function hasWork(acc)
	for i = 1, #WORK_KEYS do
		if acc[WORK_KEYS[i]] > 0 then return true end
	end
	return acc.capped == true
end

--- At a cycle's end: the sweep line (a cycle with work, rate-limited) and the pass progress / done lines.
local function cycleLog(E, env, state, perf, fetch, st, now)
	E.accCycles = E.accCycles + 1
	local acc, rt = E.acc, E.rt
	if E.lastLog ~= nil and now - E.lastLog < M.LOG_MS and now >= E.lastLog then return end
	if hasWork(acc) then
		E.lastLog = now
		emit(env, string.format("sweep n=%d cycles=%d inspected=%d fast=%d renamed=%d new=%d deferred=%d user=%d "
			.. "untouched=%d skipped=%d depot=%d pruned=%d matched=%d replaced=%d reused=%d modelChanged=%d failed=%d "
			.. "dup=%d gone=%d gets=%d race=%d old=%d lineMoved=%d lineWait=%d budget=%d capped=%s listNew=%d "
			.. "listGone=%d back=%d queued=%d full=%d expDue=%d carried=%d lineChecks=%d lineHits=%d listErr=%d lineErr=%d "
			.. "follow=%d claims=%d iv=%d",
			rt.n or 0, E.accCycles, acc.inspected, acc.fast, acc.renamed, acc.new, acc.deferred, acc.user,
			acc.untouched, acc.skipped, acc.depot, acc.pruned, acc.matched, acc.replaced, acc.reused, acc.modelChanged,
			acc.failed, acc.dup, acc.gone, acc.gets, acc.race, acc.old, acc.lineMoved, acc.lineWait, E.cfg.budget,
			tostring(acc.capped == true), acc.listNew, acc.listGone, acc.back, acc.queued, acc.full, acc.expDue,
			acc.carried, acc.lineChecks, acc.lineHits, acc.listErr, acc.lineErr, acc.follow, acc.claims, math.floor((rt.ivW or 1) * Sweep.CYCLE_MS / 1000)))
		if acc.passCreated > 0 then
			emit(env, string.format("pass created=%d collected=%d", acc.passCreated, acc.collected))
		end
		for i = 1, #ACC_KEYS do acc[ACC_KEYS[i]] = 0 end
		acc.capped = nil
		E.accCycles = 0
	end
	-- the end of a rename run: a cycle of the state that renamed in it (or a full cycle of any state: nothing needed
	-- a rename) in which no vehicle waited for one (not the cycle that collected a pass: its renames start next)
	if (E.ptotal ~= nil or E.rb ~= nil) and rt.lastDeferred == 0 and rt.lastWait == 0 and (E.runLed or rt.full)
		and rt.stats.passCreated == 0 then
		local s2 = st or fetch()
		if s2.ptotal ~= nil then
			emit(env, string.format("pass done n=%d", s2.ptotal))
		elseif s2.rb ~= nil and (s2.rr or 0) > 0 then
			emit(env, string.format("rerender done n=%d", s2.rr))
		end
		if s2.ptotal ~= nil or s2.pdone ~= nil or s2.rb ~= nil or s2.rr ~= nil then
			s2.ptotal, s2.pdone, s2.rb, s2.rr, s2.plog = nil, nil, nil, nil, nil
			write(E, state, s2, perf)
		end
		E.ptotal, E.rb, E.runLed = nil, nil, false
	end
end

--- After a step that sent renames (st: the register read in it, written after this): count them for the run and
--- log its progress (at most once per LOG_MS in all, only while vehicles wait).
local function runProgress(E, env, st, nops, now)
	local kind, a, b
	if st.ptotal ~= nil then
		st.pdone = (st.pdone or 0) + nops
		kind, a, b = "pass", st.pdone, st.ptotal
	elseif st.rb ~= nil then
		st.rr = (st.rr or 0) + nops
		kind, a, b = "rerender", st.rr, st.rb
	else
		return
	end
	E.runLed = true
	if a < b and (st.plog == nil or now - st.plog >= M.LOG_MS or now < st.plog) then
		st.plog = now
		emit(env, string.format("%s progress %d/%d", kind, a, b))
	end
end

--- "Full word" prefix or the "Word" old marker: whether the translated words are known (or waiting for them is
--- over). Reads the state at most once per 2 s window while waiting.
local function wordsReady(E, env, fetch, now)
	if not E.cfg.needWords or E.wordsSeen then return true end
	if now - (E.t0 or now) >= M.WORDS_WAIT_MS then
		if not E.wordsLogged then
			E.wordsLogged = true
			emit(env, "words src=english reason=timeout")
		end
		E.wordsSeen = true
		return true
	end
	local w = math.floor(now / Sweep.CYCLE_MS)
	if E.wordsW ~= w then
		E.wordsW = w
		fetch()
	end
	return E.wordsSeen
end

function M.update(E, env, state, dt)
	local perf = env.perf or NOPERF
	local tU = perf:start()
	subscribe(E, state)
	local okN, now = pcall(env.now)
	if not okN or type(now) ~= "number" then now = nil end
	if not E.init then initOnce(E, env, state, perf, now) end
	if E.conflict ~= nil or now == nil then
		perf:stop("update", tU)
		return
	end
	local okS, speed = pcall(env.speedup)
	if (okS and speed == 0) or (type(dt) == "number" and dt <= 0) then
		E.paused = E.paused + 1 -- paused: no sweep work at all
		perf:stop("update", tU)
		return
	end
	if E.t0 == nil then E.t0 = now end
	local fetch = makeFetch(E, env, state, perf)
	if not wordsReady(E, env, fetch, now) then
		perf:stop("update", tU)
		return
	end
	local cfg = E.cfg
	local reader = env.reader
	reader.wantYear = cfg.year ~= "off"
	reader.wantParts = cfg.oldMark ~= "" or cfg.trainLen ~= "off"
	local rt = E.rt
	if env.perf ~= nil then rt.perf = env.perf end
	local tS = perf:start()
	local phase, st = Sweep.stepLazy(rt, cfg, reader, now, fetch)
	perf:stop("step", tS)
	local s = rt.stats
	for i = 1, #PERF_COUNTS do
		local pc = PERF_COUNTS[i]
		local c = s[pc[1]]
		if c ~= nil and c > 0 then perf:count(pc[2], c) end
	end
	for i = 1, rt.nops do
		local okC, e = pcall(env.send, rt.ops[2 * i - 1], rt.ops[2 * i])
		if not okC then M.error(E, env, "send", e) end
	end
	if rt.nops > 0 then perf:count("renamed", rt.nops) end
	if st ~= nil and s.passCreated > 0 then
		-- an Apply pass: its renames are the pass's (not a re-render's); the names follow these settings
		st.rh, st.pdone, st.rb, st.rr = cfg.hash, 0, nil, nil
		E.ptotal, E.rb = st.ptotal, nil
	end
	if rt.nops > 0 and st ~= nil then runProgress(E, env, st, rt.nops, now) end
	if rt.dirty and st ~= nil then write(E, state, st, perf) end
	accumulate(E, rt.stats)
	if phase == "end" then cycleLog(E, env, state, perf, fetch, st, now) end
	perf:stop("update", tU)
end

--- The GUI's answer (op = welcome: answer apply | later, number = the checkbox), its translated full type words
--- (op = words) and the stand-down notice seen (op = sdseen).
function M.handleEvent(E, env, state, id, name, param)
	if id ~= M.EVENT_ID or name ~= M.EV or type(param) ~= "table" then return end
	local perf = env.perf or NOPERF
	local t0 = perf:start()
	local st = Reg.validate(state:get())
	local okN, now = pcall(env.now)
	if not okN or type(now) ~= "number" then now = 0 end
	local op = param.op
	if op == "welcome" then
		if st.welcome == "apply" then
			emit(env, "welcome op=answer ignored=answered")
		else
			local kind = st.welcome == nil and "first" or "renumber"
			local answer = (param.answer == "apply" and param.number ~= false) and "apply" or "later"
			local count = st.count
			Reg.answer(st, answer, now)
			write(E, state, st, perf)
			E.rt.known = nil -- this state reads the register at its next prune
			Sweep.wake(E.rt) -- and starts its next cycle at the next window (no idle back-off)
			emit(env, string.format("welcome op=answer answer=%s kind=%s count=%s button=%s", answer, kind,
				tostring(count), tostring(param.answer)))
		end
	elseif op == "words" then
		local w = Reg.cleanWords(param.words)
		if w ~= nil and Reg.wordsKey(w) ~= Reg.wordsKey(st.words) then
			st.words = w
			write(E, state, st, perf)
			emit(env, "words src=gui " .. Reg.wordsKey(w))
			Sweep.wake(E.rt) -- a new settings hash: the next cycle re-reads every vehicle
		end
		noteState(E, st)
	elseif op == "sdseen" then
		if st.sdSeen ~= 1 then
			st.sdSeen = 1
			write(E, state, st, perf)
		end
	end
	perf:stop("event", t0)
end

return M
