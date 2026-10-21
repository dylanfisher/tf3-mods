-- Better Auto Vehicle Renamer: the sweep planner. Pure: no api.* (every game read goes through `reader`), Lua 5.1
-- syntax. PLAN.md "How it works", "Performance", "Sweep strategy (2026-10-20)", "Naming one vehicle", "Hand-typed
-- names", "Replace", "Phase 2" (the lazy state read).
--
-- The game script (bavr_game.lua) calls, once per update while the game runs (not when paused):
--   local rt = Sweep.newRuntime()                  -- one per Lua state (module local): caches, id set, queues
--   local phase, st = Sweep.stepLazy(rt, cfg, reader, nowMs, fetch)
--       fetch() -> Reg.validate(state:get()): called at most once per step, and only when this slice needs the
--       register (a vehicle off the per-state fast path, a prune, a pass); st is what it returned, or nil.
--   for i = 1, rt.nops do send makeEntitySetNameCmd(rt.ops[2i-1], rt.ops[2i]) (no callback) end
--   if rt.dirty then state:set(st) end               -- only when the register changed (st is never nil then)
--   rt.stats: phase, inspected, fast, renamed, deferred, gets, listNew, back, ... (the `[SQFN] sweep` log line)
--   Sweep.wake(rt): the next cycle starts at the next 2 s window (the welcome answer, the GUI's words)
--   rt.perf (optional, set by the game script): an SQPERF instrument; sections list / lines / scan
-- Sweep.step(st, rt, cfg, reader, nowMs) is the same with a state already read (the phase 1 entry; st.standDown
-- stands it down).
-- reader (bavr_reader.lua implements it with api.engine / api.res, each call in pcall):
--   reader.list() -> array of the player's TRANSPORT_VEHICLE entity ids, or nil when the read failed (the cycle
--       waits: a failed read is never taken for "every vehicle sold")
--   reader.read(id, buf) -> bool: fills buf.carrier (Carrier enum number), buf.depot (GOING_TO_DEPOT),
--       buf.line (line entity id or nil), buf.model (lead model id: Classify.lead), buf.pt (part 1 purchaseTime),
--       buf.name (current name), buf.year (purchase year or nil); with reader.wantParts also buf.exp (game ms the
--       vehicle is past its lifespan, or nil), buf.parts (part count), buf.wagons (parts without power). false when
--       the entity is gone.
--   reader.modelInfo(modelId) -> { name = display name, key = file name, heli = bool, pax = bool } or nil
--       (called once per model per Lua state)
--   reader.lineName(lineId) -> string or nil
--   reader.exists(id) -> bool (checked right before a rename is queued)
--   reader.lines() -> array of the player's line ids or nil; reader.lineVehicles(lineId) -> array of vehicle ids or
--       nil (optional, both: the line watch; without them line names are re-read once per cycle, as before)
-- Optional rt fields set by the game script: rt.defaultWords (set of the game's default name words, Text.isDefault),
-- rt.matchGone (false turns off Replace matching across ids), rt.standDown (reason: stepLazy does nothing), rt.perf.
--
-- A cycle (PLAN.md "Sweep strategy"): "list" -> "prune" -> ("lines") -> "scan" -> "end".
-- - list: due when the cycle interval has passed (CYCLE_MS, stretched up to IDLE_MAX_W windows while nothing
--   changes: the idle back-off; or an old-mark expiry is due). reader.list() and a diff with this Lua state's id set
--   (rt.mark / rt.ring, no allocation per id): new ids, vanished ids (their per-state entries dropped).
-- - prune: the register read and Reg.prune only when something vanished, the welcome / pass may change, or every
--   PRUNE_MS (backstop); then the cycle's work queue: a full cycle (every vehicle: an Apply pass collecting, the
--   settings hash or the welcome answer this state knows changed, the first cycle of a Lua state) or the
--   vehicles from the last cycle that are not settled (renamed, pending, deferred, waiting...), the new ids, the
--   vehicles whose lifespan just passed (an expiry heap, only with the old-vehicle mark on) and the backstop slice
--   (BACKSTOP vehicles per CYCLE_MS of game time, a rotating cursor over the id set: Replace keeping the id,
--   line changes, consist changes, an id reused within one cycle).
-- - lines (only when a setting shows the line: a line format or counting "Per line"): the line watch, LINE_RATE lines
--   per CYCLE_MS: a changed line name queues that line's vehicles, a vehicle that joined or left a line (the line's
--   vehicle list against what this state last read) queues that vehicle; a vanished line queues its vehicles.
-- - scan: at most INSPECT vehicles read per update. Once this window's rename budget is spent (a deferral), the rest
--   of the queue is carried to the next cycle unread (not while an Apply pass collects or the untouched vehicles are
--   counted); the lease holder (and a claimer) instead waits at that vehicle for the next window, up to HOLD_MS per
--   cycle ("The rename lease" below).
-- - end: the Apply pass's oldest-first numbering, per-line renumbering, the untouched count, the back-off.
--
-- Per-vehicle inputs of the fast path: name, purchase time, line, line name, lead model, settings hash, "old" (now
-- >= buf.exp, one compare: the expiry is read once per consist) and the train count; plus, in the register check, the
-- number shown. Counting "Per line": the positions (rec.lp) are renumbered at a cycle's "end" for the lines whose
-- membership changed in it, and once for every line at the first "prune" of a Lua state; a vehicle whose position
-- moved is dropped from this state's fast path and queued, so it is renamed on the next cycle (within the budget).
--
-- The state read (state:get() may copy the whole register per call; PLAN.md "Phase 2"): each vehicle first meets a
-- per-Lua-state check that needs no register: the inputs this state last confirmed for a name of ours, a hand-typed
-- name it saw, or an untouched vehicle ("Not now"). Only a vehicle that fails it reads the register (one fetch for
-- the whole slice). Every number is taken from a state read in the same update as its state:set.
--
-- The rename lease (PLAN.md "Rename lease"): update runs in ~11 Lua states, and a get / set pair is not atomic, so
-- one Lua state at a time sends renames: the one named in the register's lease (st.lo = its token rt.me, st.le = the
-- game ms the lease ends, st.lq = its epoch: +1 per claim). A state about to rename (it holds a fresh read then, so
-- no extra state:get) with no live lease writes a claim and waits; it renames only from the next 2 s window on, and
-- only while its reads still name it (two claims racing: the later write wins, the other state sees it lost; the old
-- leader may have spent the claim's window, the next one is the new leader's alone). Sticky leadership (the 08:15Z
-- run, PLAN.md "Rename lease (2026-10-20)": each Lua state runs update in only some ticks, so a lease that lapsed
-- between the leader's cycles hopped between states):
-- - the leader renews the lease in every update of a rename run (a rename or a spent window: its write anyway);
-- - another state takes a lease as ended only LEASE_MARGIN_MS after its end (the holder only until its end);
-- - each state remembers the newest lease it saw (rt.lLo / lLe / lLq): a read whose lease is older (a lower epoch:
--   a stale snapshot or a lost write) or missing does not make it look free;
-- - the leader and a claimer wait for the next window in the scan (rt.holdW: the cycle's queue stays where it is, up
--   to HOLD_MS), instead of ending the cycle: a leader that runs update in only some ticks renames in every window
--   it runs in, not once per cycle (a cycle is at least 4 of its updates).
-- The others defer like a spent budget (stats.follow: the rest of their queue is carried unread). The leader counts
-- the window's renames itself too (rt.wW / rt.wUsed), so another state's stale write that lowers st.used cannot
-- raise the rate.

local Text = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_text.lua"
local Classify = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_classify.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"

local M = {}

M.CYCLE_MS = 2000     -- one window: the shortest cycle interval and the rename budget window
M.IDLE_MAX_W = 5      -- idle back-off: the interval doubles per cycle without change, up to this many windows (10 s)
M.INSPECT = 200       -- vehicles read per update
M.BACKSTOP = 50       -- backstop: vehicles re-read per CYCLE_MS of game time (a 2000-vehicle fleet in 80 s)
M.BACKSTOP_MAX = 500  -- backstop vehicles per cycle at most
M.LINE_RATE = 32      -- line watch: lines checked per CYCLE_MS of game time
M.LINE_MAX = 400      -- lines checked per cycle at most
M.MAX_LINES = 20000   -- line list cap
M.MAX_LINE_VEH = 10000 -- vehicles read per line list
M.MAX_LIST = 100000   -- list cap (longer lists are cut: stats.capped)
M.MAX_GAP_MS = 60000  -- game ms counted between two cycles at most (the backstop and line allowances)
M.MAX_EXP_POP = 1000  -- expiries taken from the heap per cycle
M.MAX_HEAP = 200000   -- expiry heap entries (rebuilt from the live expiries beyond)
M.PENDING_MS = 10000  -- a sent name is awaited this long before it is sent again
M.RETRY_MAX = 3       -- sends of the same name before giving up (until an input changes)
M.PRUNE_MS = 30000    -- game ms between two register reads in "prune" when nothing vanished (backstop)
M.MAX_MODELS = 4096   -- loop cap on the per-model counter guard
M.LEASE_MS = 20000    -- the rename lease: game ms it lasts past the leader's last update in a rename run
M.LEASE_MARGIN_MS = 10000 -- another Lua state takes a lease as ended only this long after its end (stale reads)
M.HOLD_MS = 40000     -- a leader / claimer waits in the scan for the next window at most this long per cycle

-- inspection results: settled (nothing to do until an input changes), or queued for the next cycle
-- HOLD: the leader's window budget is spent or the claim waits: the scan stays at this vehicle until the next window
local URGENT, LATER, HOLD = 1, 2, 3

local STAT_KEYS = { "inspected", "fast", "ok", "renamed", "deferred", "pending", "user", "untouched", "waiting",
	"collected", "new", "replaced", "reused", "matched", "modelChanged", "pruned", "skipped", "depot", "dup", "gone",
	"failed", "passCreated", "gets", "race", "follow", "claims", "old", "lineMoved", "lineWait", "listNew", "listGone", "back", "queued",
	"full", "expDue", "carried", "lineChecks", "lineHits", "listErr", "lineErr" }
M.STAT_KEYS = STAT_KEYS

local NOPERF = { start = function() return 0 end, stop = function() end, count = function() end }

function M.newRuntime()
	local rt = {
		phase = "list", n = 0, cyc = 0, cycW = nil, listAt = nil, cycDt = 0, ivW = 1, pruneAt = nil,
		-- this Lua state's id set: mark[id] = the cycle that last listed it, ring = the ids in a stable order
		mark = {}, ring = {}, rn = 0, newIds = {}, nNew = 0, vanished = false, bpos = 1, bAcc = 0,
		-- the cycle's work queue (todo[1..tn], tpos the cursor; tB / tQ / tN / tE: where the backstop, retried, new
		-- and expired parts end; the line watch appends) and the next cycle's (nextQ[1..nn]); inTodo / inNext: the
		-- cycle an id was queued in
		todo = nil, todoBuf = {}, tmpQ = {}, tn = 0, tpos = 1, tQ = 0, tN = 0, tE = 0, tB = 0, full = false, noCarry = false,
		inTodo = {}, inNext = {}, nextQ = {}, nn = 0, carryW = nil, builtGen = nil, builtHash = nil,
		cycNew = 0, cycGone = 0, cycUrgent = 0, cycRenamed = 0, cycDirty = false, cycHits = 0, cycExp = 0,
		-- the expiry heap (old-vehicle mark): hE / hI the min-heap of (expiry, id), expOf[id] the live expiry
		hE = {}, hI = {}, hn = 0, expOf = {},
		-- the line watch: vl[id] the line this state last read for a vehicle, lineN[line] how many; the line set
		vl = {}, lineN = {}, lmark = {}, lring = {}, lrn = 0, lpos = 1, lAcc = 0, lineRaw = {}, lwOk = false,
		lwSeen = {}, lwTok = 0,
		mod = {}, modHash = nil, line = {}, lineCyc = {},
		-- the per-state fast path: inputs last confirmed for our name (L line, LN line name, M model, H settings hash,
		-- N name, P purchase time); uN / uP / uS / uG: a hand-typed ("user") or "untouched" vehicle as last seen
		inL = {}, inLN = {}, inM = {}, inH = {}, inN = {}, inP = {}, inO = {}, inC = {}, inS = {},
		curOld = false, curCnt = false, lineTouch = {}, lpOut = {}, lpInit = false,
		uN = {}, uP = {}, uS = {}, uG = {}, uL = {}, gen = 0, known = nil,
		hiT = {}, hiA = nil, hiM = {}, cycUnt = 0,
		ops = {}, nops = 0, sent = {}, sentN = 0, pq = {}, npq = 0, passOn = false,
		-- per cycle: vehicles that waited for a rename (lease, budget) / for a number (a pass, a line position)
		cycDeferred = 0, lastDeferred = nil, cycWait = 0, lastWait = nil, stats = {}, dirty = false, buf = {},
		defaultWords = nil, matchGone = true, standDown = nil, perf = nil,
		-- the rename lease: this Lua state's token, the window of its last claim, whether it led in its last rename
		-- attempt; its own count of renames in window wW
		me = nil, claimW = nil, leads = false, wW = nil, wUsed = 0,
		-- the newest lease this state saw (holder, end, epoch); the window the scan waits for; when it began waiting
		lLo = nil, lLe = nil, lLq = nil, holdW = nil, holdT0 = nil,
	}
	rt.me = tostring(rt) -- unique per Lua state while it lives (the table's address)
	for i = 1, #STAT_KEYS do rt.stats[STAT_KEYS[i]] = 0 end
	return rt
end

local function resetStats(s)
	for i = 1, #STAT_KEYS do s[STAT_KEYS[i]] = 0 end
	s.capped = false
	s.autoApply = false
end

--- The next cycle starts at the next window (an event that may change what the sweep does).
function M.wake(rt)
	rt.ivW = 1
end

---------------------------------------------------------------------------
-- The expiry heap (old-vehicle mark): a min-heap of (expiry game ms, id); stale entries (expOf moved on) are skipped

local function heapPush(rt, e, id)
	local hE, hI = rt.hE, rt.hI
	local i = rt.hn + 1
	rt.hn = i
	while i > 1 do
		local p = math.floor(i / 2)
		if hE[p] <= e then break end
		hE[i], hI[i] = hE[p], hI[p]
		i = p
	end
	hE[i], hI[i] = e, id
end

local function heapPop(rt)
	local hE, hI, n = rt.hE, rt.hI, rt.hn
	local e, id = hE[1], hI[1]
	local le, li = hE[n], hI[n]
	hE[n], hI[n] = nil, nil
	n = n - 1
	rt.hn = n
	if n > 0 then
		local i = 1
		while true do
			local c = i * 2
			if c > n then break end
			if c < n and hE[c + 1] < hE[c] then c = c + 1 end
			if hE[c] >= le then break end
			hE[i], hI[i] = hE[c], hI[c]
			i = c
		end
		hE[i], hI[i] = le, li
	end
	return e, id
end

-- a vehicle of ours that is not old yet: remember when it will be (one heap entry per new expiry)
local function noteExp(rt, id, exp)
	if rt.expOf[id] == exp then return end
	rt.expOf[id] = exp
	if rt.hn >= M.MAX_HEAP then
		-- too many stale entries: rebuild from the live expiries (capped)
		rt.hE, rt.hI, rt.hn = {}, {}, 0
		local walked = 0
		for vid, e in pairs(rt.expOf) do
			walked = walked + 1
			if walked > M.MAX_HEAP then break end
			heapPush(rt, e, vid)
		end
		return
	end
	heapPush(rt, exp, id)
end

---------------------------------------------------------------------------
-- Caches

-- model info per model id, cached for the Lua state (display name shortened per cfg)
local function modelInfo(rt, reader, cfg, modelId)
	if modelId == nil then return nil end
	if rt.modHash ~= cfg.hash then
		rt.mod = {}
		rt.modHash = cfg.hash
	end
	local mi = rt.mod[modelId]
	if mi == nil then
		local info = reader.modelInfo(modelId)
		if type(info) == "table" then
			mi = { disp = Text.modelName(cfg, info.name), key = type(info.key) == "string" and info.key or nil,
				heli = info.heli == true, pax = info.pax == true }
		else
			mi = false
		end
		rt.mod[modelId] = mi
	end
	return mi or nil
end

-- line display name per line id: nil when no setting shows the line (no read at all); cached until the line watch
-- sees a change, or re-read once per cycle when the line watch is not available
local function lineName(rt, reader, cfg, li)
	if not cfg.usesLine or li == nil or li <= 0 then return nil end
	local v = rt.line[li]
	if v == nil or (not rt.lwOk and rt.lineCyc[li] ~= rt.cyc) then
		rt.lineCyc[li] = rt.cyc
		local raw = reader.lineName(li)
		rt.lineRaw[li] = raw or false
		v = Text.lineName(cfg, raw) or false
		rt.line[li] = v
	end
	return v or nil
end

local function forget(rt, id)
	rt.inL[id], rt.inLN[id], rt.inM[id], rt.inH[id], rt.inN[id], rt.inP[id] = nil, nil, nil, nil, nil, nil
	rt.inO[id], rt.inC[id], rt.inS[id] = nil, nil, nil
	rt.uN[id], rt.uP[id], rt.uS[id], rt.uG[id], rt.uL[id] = nil, nil, nil, nil, nil
end

-- the line this state last read for a vehicle (the line watch's membership check)
local function setVl(rt, id, li)
	local old = rt.vl[id]
	if old == li then return end
	if old ~= nil and old > 0 then rt.lineN[old] = (rt.lineN[old] or 1) - 1 end
	if li ~= nil and li > 0 then rt.lineN[li] = (rt.lineN[li] or 0) + 1 end
	rt.vl[id] = li
end

-- a vehicle gone from the list: every per-state entry of it
local function drop(rt, id)
	forget(rt, id)
	setVl(rt, id, nil)
	rt.mark[id], rt.expOf[id], rt.inTodo[id], rt.inNext[id], rt.lwSeen[id] = nil, nil, nil, nil, nil
end

-- into this cycle's queue (nothing when the cycle reads every vehicle anyway, or the id is not listed)
local function qNow(rt, id)
	if rt.full or rt.mark[id] == nil or rt.inTodo[id] == rt.cyc then return false end
	rt.inTodo[id] = rt.cyc
	local tn = rt.tn + 1
	rt.tn = tn
	rt.todo[tn] = id
	return true
end

-- into the next cycle's queue; urgent: it keeps the interval at one window (no back-off)
local function qNext(rt, id, urgent)
	if urgent then rt.cycUrgent = rt.cycUrgent + 1 end
	if rt.inNext[id] == rt.cyc then return end
	rt.inNext[id] = rt.cyc
	local n = rt.nn + 1
	rt.nn = n
	rt.nextQ[n] = id
end

-- a vehicle seen as hand-typed ("user") or "untouched": skipped without the register while name, purchase time
-- and line stay (untouched also while the welcome answer / cutoff / pass this state knows stay: rt.gen)
local function seen(rt, id, kind, name, pt, li)
	rt.uN[id], rt.uP[id], rt.uS[id], rt.uG[id], rt.uL[id] = name, pt, kind, rt.gen, li
end

--- What this Lua state knows of the register's answer fields after a read; a change bumps rt.gen (drops the
--- untouched entries: the next cycle reads every vehicle). Also opens the rename window and guards the counters
--- against a lost write (below).
--- The lease this Lua state goes by after a read: the snapshot's, unless the newest one it saw is newer (a higher
--- epoch, or the same lease renewed later): then a stale snapshot or a lost write does not make the lease look free.
local function noteLease(st, rt)
	local lo, le, lq = st.lo, st.le, st.lq
	if type(lo) ~= "string" or type(le) ~= "number" then lo, le, lq = nil, nil, nil end
	if lo ~= nil and type(lq) ~= "number" then lq = 0 end
	local rlo = rt.lLo
	if rlo ~= nil then
		if lo == nil or lq < rt.lLq then
			return -- (older than what this state saw: keep that)
		elseif lq == rt.lLq and lo == rlo and rt.lLe > le then
			le = rt.lLe
		end
	end
	rt.lLo, rt.lLe, rt.lLq = lo, le, lq
end

local function noteFetch(st, rt, now)
	rt.stats.gets = rt.stats.gets + 1
	noteLease(st, rt)
	local w = math.floor(now / M.CYCLE_MS)
	if st.win ~= w then
		st.win = w
		st.used = 0
	end
	local k = rt.known
	local passAt = st.pass ~= nil and st.pass.at or nil
	if k == nil then
		k = {}
		rt.known = k
		rt.gen = rt.gen + 1
	elseif k.welcome ~= st.welcome or k.cutoff ~= st.cutoff or k.passAt ~= passAt then
		rt.gen = rt.gen + 1
	end
	k.welcome, k.cutoff, k.passAt, k.count = st.welcome, st.cutoff, passAt, st.count
	if st.standDown ~= nil then rt.standDown = st.standDown end
	-- counter guard: a counter below a number this Lua state handed out means another state's write replaced ours
	-- (a lost update); move it past that number so it is never given twice
	for l, n in pairs(rt.hiT) do
		if (st.nt[l] or 0) <= n then
			st.nt[l] = n + 1
			rt.stats.race = rt.stats.race + 1
			rt.dirty = true
		end
	end
	if rt.hiA ~= nil and (st.na or 0) <= rt.hiA then
		st.na = rt.hiA + 1
		rt.stats.race = rt.stats.race + 1
		rt.dirty = true
	end
	local walked = 0
	for mk, n in pairs(rt.hiM) do
		walked = walked + 1
		if walked > M.MAX_MODELS then break end
		if (st.nm[mk] or 0) <= n then
			st.nm[mk] = n + 1
			rt.stats.race = rt.stats.race + 1
			rt.dirty = true
		end
	end
end

--- The highest numbers handed out so far (from the counters of a state about to be written; for noteFetch).
function M.noteCounters(rt, st)
	for l, n in pairs(st.nt) do
		if (rt.hiT[l] or 0) < n - 1 then rt.hiT[l] = n - 1 end
	end
	if st.na ~= nil and (rt.hiA or 0) < st.na - 1 then rt.hiA = st.na - 1 end
	local walked = 0
	for mk, n in pairs(st.nm) do
		walked = walked + 1
		if walked > M.MAX_MODELS then break end
		if (rt.hiM[mk] or 0) < n - 1 then rt.hiM[mk] = n - 1 end
	end
end

---------------------------------------------------------------------------
-- One vehicle

--- Tier 1 of one vehicle: read, classify and the per-state checks that need no register. Returns the letter and
--- model info when the vehicle needs the full check (inspectFull); else nil and the result (nil settled, URGENT /
--- LATER queued for the next cycle).
local function inspectPre(rt, cfg, reader, id, now)
	local s, buf = rt.stats, rt.buf
	s.inspected = s.inspected + 1
	buf.carrier, buf.depot, buf.line, buf.model, buf.pt, buf.name, buf.year = nil, nil, nil, nil, nil, nil, nil
	buf.exp, buf.parts, buf.wagons = nil, nil, nil
	if not reader.read(id, buf) then
		s.gone = s.gone + 1
		return nil
	end
	if cfg.usesLine then setVl(rt, id, buf.line or 0) end
	local mi = modelInfo(rt, reader, cfg, buf.model)
	local letter = Classify.letter(buf.carrier, mi and mi.pax, mi and mi.heli)
	if letter == nil or not cfg.enabled[letter] then
		s.skipped = s.skipped + 1
		return nil
	end
	if buf.depot then
		s.depot = s.depot + 1
		return nil, LATER
	end
	local name, pt = buf.name or "", buf.pt
	-- the two inputs that are no game field: past its lifespan (precomputed expiry vs now) and the train count
	local old = cfg.oldMark ~= "" and buf.exp ~= nil and now ~= nil and now >= buf.exp
	rt.curOld = old
	rt.curCnt = Text.trainCount(cfg, buf.carrier, buf.parts, buf.wagons) or false
	if old then s.old = s.old + 1 end
	local n = rt.inN[id]
	if n ~= nil and n == name and rt.inP[id] == pt then
		local li = buf.line or 0
		if rt.inL[id] == li and rt.inM[id] == buf.model and rt.inH[id] == cfg.hash and rt.inO[id] == old
			and rt.inC[id] == rt.curCnt and rt.inLN[id] == (lineName(rt, reader, cfg, li) or false) then
			s.fast = s.fast + 1
			if not old and buf.exp ~= nil and cfg.oldMark ~= "" then noteExp(rt, id, buf.exp) end
			return nil
		end
	end
	local kind = rt.uS[id]
	if kind ~= nil and rt.uP[id] == pt and rt.uL[id] == (buf.line or 0) then
		if kind == "user" and rt.uN[id] == name and not cfg.takeOver then
			s.user = s.user + 1
			return nil
		end
		if kind == "untouched" and rt.uG[id] == rt.gen then
			s.untouched = s.untouched + 1
			return nil
		end
	end
	return letter, mi
end

--- Tier 2 of one vehicle (rt.buf filled by inspectPre): the register checks; may queue a rename into rt.ops.
--- Returns nil (settled) or URGENT / LATER (queued for the next cycle).
local function inspectFull(st, rt, cfg, reader, now, id, letter, mi)
	local s, buf = rt.stats, rt.buf
	local key = Reg.key(id)
	local rec = st.v[key]
	local li = buf.line or 0
	local pt = buf.pt
	if rec ~= nil and pt ~= nil and rec.pt ~= nil and rec.pt ~= pt then
		if li > 0 and rec.li == li and rec.k == letter then
			-- Replace that keeps the id: same line and type, new parts. Keep the numbers.
			rec.pt = pt
			rt.dirty = true
			s.replaced = s.replaced + 1
		else
			-- the id was reused after a sale: the old number stays retired
			if cfg.counter == "line" and (rec.li or 0) > 0 then rt.lineTouch[rec.li] = true end
			st.v[key] = nil
			rec = nil
			forget(rt, id)
			rt.dirty = true
			s.reused = s.reused + 1
		end
	end
	local mk = mi and mi.key or nil
	local name = buf.name or ""
	if rec == nil then
		local pass = st.pass
		if pass ~= nil then
			if rt.passOn and (pt or 0) < (pass.cutoff or 0) then
				if rt.npq < Reg.MAX_PASS then
					local b = rt.npq * Reg.PASS_FIELDS
					rt.pq[b + 1], rt.pq[b + 2], rt.pq[b + 3], rt.pq[b + 4], rt.pq[b + 5] = id, pt or 0, letter, mk or "", li
					rt.npq = rt.npq + 1
					s.collected = s.collected + 1
					rt.cycWait = rt.cycWait + 1
				else
					s.capped = true
				end
				return URGENT -- numbered at the cycle's end, named on the next
			end
			-- while an Apply pass is due, nothing new is numbered (the pass numbers oldest first)
			s.waiting = s.waiting + 1
			rt.cycWait = rt.cycWait + 1
			return URGENT
		end
		if st.cutoff ~= nil and (pt or 0) < st.cutoff then
			s.untouched = s.untouched + 1
			seen(rt, id, "untouched", name, pt, li)
			return nil
		end
		local g = rt.matchGone ~= false and Reg.takeGone(st, li, letter, now) or nil
		if g ~= nil then
			-- the gone vehicle's numbers and its place on the line (its join time)
			rec = { k = letter, t = g[3], a = g[4], m = (g[5] or 0) > 0 and g[5] or nil, mk = g[6] ~= "" and g[6] or nil,
				pt = pt, li = li, lj = (g[8] or 0) > 0 and g[8] or Reg.join(st) }
			st.v[key] = rec
			s.matched = s.matched + 1
		else
			rec = Reg.create(st, cfg, id, letter, mk, pt, li)
			s.new = s.new + 1
		end
		if cfg.counter == "line" and li > 0 then rt.lineTouch[li] = true end
		rt.dirty = true
	end
	if rec.li ~= li then
		-- moved to another line (or joined / left one): it goes to the end of its new line; the old line closes up
		if cfg.counter == "line" then
			if (rec.li or 0) > 0 then rt.lineTouch[rec.li] = true end
			if li > 0 then rt.lineTouch[li] = true end
		end
		rec.li, rec.lj, rec.lp = li, Reg.join(st), nil
		rt.dirty = true
	end
	if mk ~= nil and rec.mk ~= mk then
		Reg.setModel(st, rec, mk, cfg)
		rt.dirty = true
		s.modelChanged = s.modelChanged + 1
	end
	if rec.user == 1 and not cfg.takeOver then
		if name ~= rec.last and not Text.isDefault(name, rt.defaultWords) then
			s.user = s.user + 1
			seen(rt, id, "user", name, pt, li)
			return nil
		end
		rec.user = nil -- cleared back to a default name: ours again
		rt.dirty = true
	end
	local lname = lineName(rt, reader, cfg, li)
	if cfg.counter == "line" and li > 0 and rec.lp == nil then
		-- no position on its line yet: the cycle's end numbers the line, the next cycle names it
		rt.lineTouch[li] = true
		s.lineWait = s.lineWait + 1
		rt.cycWait = rt.cycWait + 1
		return URGENT
	end
	local shown, perLine = Reg.shown(rec, cfg)
	if perLine and lname == nil then shown, perLine = rec.t, false end -- an unnamed line: the per-type number
	local old, cnt = rt.curOld, rt.curCnt
	-- fast path: same inputs as when the name was last confirmed, and still our name
	if name == rec.last and rt.inL[id] == li and rt.inLN[id] == (lname or false) and rt.inM[id] == buf.model
		and rt.inH[id] == cfg.hash and rt.inS[id] == shown and rt.inO[id] == old and rt.inC[id] == cnt then
		rt.inN[id], rt.inP[id] = name, pt
		s.fast = s.fast + 1
		if not old and buf.exp ~= nil and cfg.oldMark ~= "" then noteExp(rt, id, buf.exp) end
		return nil
	end
	local want = Text.render(cfg, mi and mi.disp or nil, lname, letter, shown, buf.year, old, cnt or nil, perLine)
	if name == want then
		rt.inL[id], rt.inLN[id], rt.inM[id], rt.inH[id] = li, lname or false, buf.model, cfg.hash
		rt.inN[id], rt.inP[id] = name, pt
		rt.inS[id], rt.inO[id], rt.inC[id] = shown, old, cnt
		if rec.last ~= want then
			rec.last = want
			rt.dirty = true
		end
		if rec.rc ~= nil or rec.ts ~= nil then
			rec.rc, rec.ts = nil, nil -- the send arrived: no longer pending
			rt.dirty = true
		end
		s.ok = s.ok + 1
		if not old and buf.exp ~= nil and cfg.oldMark ~= "" then noteExp(rt, id, buf.exp) end
		return nil
	end
	if rec.last == want and rec.ts ~= nil and now - rec.ts < M.PENDING_MS then
		s.pending = s.pending + 1
		return URGENT
	end
	if not (name == rec.last or cfg.takeOver or Text.isDefault(name, rt.defaultWords)) then
		rec.user = 1 -- typed by the player: never touched again (the number stays in the register)
		rt.dirty = true
		forget(rt, id)
		seen(rt, id, "user", name, pt, li)
		s.user = s.user + 1
		return nil
	end
	if rec.last == want and (rec.rc or 0) >= M.RETRY_MAX then
		s.failed = s.failed + 1
		return nil -- given up until an input changes (the backstop sees that)
	end
	local w = math.floor(now / M.CYCLE_MS)
	-- the rename lease: only the Lua state the register names sends renames (the newest lease this state saw)
	noteLease(st, rt)
	local lo, le, lq = rt.lLo, rt.lLe, rt.lLq
	local sane = lo ~= nil and le - now <= M.LEASE_MS -- (a lease further ahead: time went back)
	local mine = sane and lo == rt.me and now < le
	if not mine or rt.claimW == w then
		if sane and lo ~= rt.me and now < le + M.LEASE_MARGIN_MS then
			rt.leads = false -- another Lua state leads: it renames this vehicle, or its lease ends
			s.follow = s.follow + 1
			-- (wait like a spent budget: the rest of the queue is carried to the next cycle)
			rt.cycDeferred = rt.cycDeferred + 1
			rt.carryW = w
			return URGENT
		end
		if not mine then
			-- no live lease: claim it, a new epoch (renames from the next window on, if a read then still names
			-- this state)
			lq = (lq or 0) + 1
			st.lo, st.le, st.lq = rt.me, now + M.LEASE_MS, lq
			rt.lLo, rt.lLe, rt.lLq = rt.me, now + M.LEASE_MS, lq
			rt.claimW = w
			rt.dirty = true
			s.claims = s.claims + 1
		end
		-- the claim waits for the next window (the scan stays here)
		rt.cycDeferred = rt.cycDeferred + 1
		rt.carryW = w
		return HOLD
	end
	rt.leads = true
	-- the leader renews the lease in every update of a run (and writes it back when the read lacked it)
	st.lo, st.le, st.lq = rt.me, now + M.LEASE_MS, lq
	rt.lLe = now + M.LEASE_MS
	rt.dirty = true
	local used = st.used or 0
	if rt.wW == w and rt.wUsed > used then used = rt.wUsed end
	if used >= cfg.budget then
		s.deferred = s.deferred + 1
		rt.cycDeferred = rt.cycDeferred + 1
		rt.carryW = w
		return HOLD
	end
	if rt.sent[want] == rt.cyc then
		s.dup = s.dup + 1
		return URGENT
	end
	if not reader.exists(id) then
		s.gone = s.gone + 1
		return nil
	end
	local n = rt.nops * 2
	rt.ops[n + 1], rt.ops[n + 2] = id, want
	rt.nops = rt.nops + 1
	rt.sent[want] = rt.cyc
	rt.sentN = rt.sentN + 1
	st.used = used + 1
	if rt.wW ~= w then rt.wW, rt.wUsed = w, 0 end
	rt.wUsed = rt.wUsed + 1
	if rec.last == nil and rec.orig == nil then rec.orig = name end
	rec.rc = rec.last == want and (rec.rc or 0) + 1 or 1
	rec.last = want
	rec.ts = now
	forget(rt, id)
	rt.dirty = true
	s.renamed = s.renamed + 1
	rt.cycRenamed = rt.cycRenamed + 1
	return URGENT -- the next cycle sees the name arrive
end

--- Inspect one vehicle against a register already read (tests; the scan uses the two tiers). Returns the result.
function M.inspect(st, rt, cfg, reader, now, id)
	local letter, mi, res = inspectPre(rt, cfg, reader, id, now)
	if letter ~= nil then res = inspectFull(st, rt, cfg, reader, now, id, letter, mi) end
	if res == HOLD then res = URGENT end
	return res
end

---------------------------------------------------------------------------
-- The cycle

--- Whether "prune" needs the register this cycle (see the header).
local function pruneNeedsState(rt, cfg, now)
	local k = rt.known
	if k == nil or k.welcome == nil or k.passAt ~= nil or rt.vanished then return true end
	if k.welcome == "later" and cfg.renumberNext then return true end
	return rt.pruneAt == nil or now < rt.pruneAt or now - rt.pruneAt >= M.PRUNE_MS
end

-- "Not now" + "Number existing vehicles on next load" Yes: the untouched vehicles are counted for the window
local function countMode(rt, cfg)
	local k = rt.known
	return cfg.renumberNext and k ~= nil and k.welcome == "later" and k.passAt == nil
end

--- Counting "Per line": renumber the positions on `lines` (nil = every line); a vehicle whose position moved leaves
--- this state's fast path and is queued (named on the next cycle; nowQ: in this cycle's queue).
local function renumberLines(st, rt, lines, nowQ)
	local out = rt.lpOut
	local n = Reg.linePositions(st, lines, out)
	for i = 1, n do
		local id = out[i]
		if id ~= nil then
			forget(rt, id)
			if nowQ then qNow(rt, id) else qNext(rt, id, true) end
		end
		out[i] = nil
	end
	if n > 0 then rt.dirty = true end
	rt.stats.lineMoved = rt.stats.lineMoved + n
end

-- the cycle is due: its interval (back-off) passed, an expiry is due, or time went back
local function due(rt, now, w)
	if rt.cycW == nil or w < rt.cycW then return true end
	if w >= rt.cycW + rt.ivW then return true end
	return rt.hn > 0 and rt.hE[1] <= now
end

--- "list": the id list against this state's id set. Returns false when the list could not be read.
local function listDiff(rt, reader, now, w)
	local s = rt.stats
	local list = reader.list()
	if type(list) ~= "table" then
		s.listErr = s.listErr + 1
		return false
	end
	local n = #list
	if n > M.MAX_LIST then
		n = M.MAX_LIST
		s.capped = true
	end
	local prevC = rt.cyc
	local cyc = prevC + 1
	rt.cyc = cyc
	local mark, nw = rt.mark, rt.newIds
	local nnew, kept = 0, 0
	for i = 1, n do
		local id = list[i]
		local m = mark[id]
		if m ~= cyc then -- (a duplicate in the list counts once)
			if m == nil then
				nnew = nnew + 1
				nw[nnew] = id
			else
				kept = kept + 1
			end
			mark[id] = cyc
		end
	end
	-- vanished: the ring holds exactly the ids of the previous list; only walked when one is missing
	local ring, rn, gone = rt.ring, rt.rn, 0
	if kept < rn then
		local j, before, bpos = 0, 0, rt.bpos
		for i = 1, rn do
			local id = ring[i]
			if mark[id] == cyc then
				j = j + 1
				ring[j] = id
			else
				gone = gone + 1
				drop(rt, id)
				if i < bpos then before = before + 1 end
			end
		end
		for i = j + 1, rn do ring[i] = nil end
		rn = j
		rt.bpos = bpos - before
		if rt.bpos < 1 then rt.bpos = 1 end
	end
	for i = 1, nnew do
		rn = rn + 1
		ring[rn] = nw[i]
	end
	rt.rn, rt.n, rt.nNew = rn, rn, nnew
	rt.vanished = gone > 0
	s.listNew, s.listGone = nnew, gone
	rt.cycNew, rt.cycGone = nnew, gone
	-- the game ms since the last cycle (the backstop and line watch allowances)
	local dt = rt.listAt ~= nil and now - rt.listAt or 0
	if dt ~= dt or dt < 0 then dt = 0 end
	if dt > M.MAX_GAP_MS then dt = M.MAX_GAP_MS end
	rt.cycDt = dt
	rt.cycW, rt.listAt = w, now
	if rt.sentN > 0 then
		rt.sent, rt.sentN = {}, 0
	end
	rt.cycDeferred, rt.cycUrgent, rt.cycRenamed, rt.cycDirty, rt.cycHits, rt.cycExp = 0, 0, 0, false, 0, 0
	rt.holdW, rt.holdT0, rt.cycWait = nil, nil, 0
	rt.cycUnt = 0
	return true
end

--- The cycle's work queue (after prune; see the header). Order: the backstop slice first (so it is read even while a
--- budgeted rename run carries the rest), then the vehicles not settled last cycle, the new ids, the expiries due.
local function build(rt, cfg, now)
	local s = rt.stats
	local full = rt.passOn or rt.builtGen ~= rt.gen or rt.builtHash ~= cfg.hash
	rt.builtGen, rt.builtHash = rt.gen, cfg.hash
	rt.full = full
	rt.noCarry = rt.passOn or countMode(rt, cfg)
	local cyc, mark, inT = rt.cyc, rt.mark, rt.inTodo
	local q, qn = rt.nextQ, rt.nn
	rt.nn = 0
	-- the queued part goes into rt.tmpQ first (stamped), the backstop then takes ids that are not in it
	local t, tn = rt.tmpQ, 0
	if not full then
		for i = 1, qn do
			local id = q[i]
			if mark[id] ~= nil and inT[id] ~= cyc then
				inT[id] = cyc
				tn = tn + 1
				t[tn] = id
			end
		end
		local nq = tn
		local nw = rt.newIds
		for i = 1, rt.nNew do
			local id = nw[i]
			if inT[id] ~= cyc then
				inT[id] = cyc
				tn = tn + 1
				t[tn] = id
			end
		end
		rt.tQ, rt.tN = nq, tn
	end
	-- expiries due (old-vehicle mark): taken in either case (a full cycle reads them anyway)
	local pops = 0
	while rt.hn > 0 and rt.hE[1] <= now and pops < M.MAX_EXP_POP do
		local e, id = heapPop(rt)
		pops = pops + 1
		if rt.expOf[id] == e then
			rt.expOf[id] = nil
			rt.cycExp = rt.cycExp + 1
			s.expDue = s.expDue + 1
			if not full and mark[id] ~= nil and inT[id] ~= cyc then
				inT[id] = cyc
				tn = tn + 1
				t[tn] = id
			end
		end
	end
	if full then
		rt.todo, rt.tn = rt.ring, rt.rn
		rt.tQ, rt.tN, rt.tE, rt.tB = 0, 0, 0, 0
		rt.bAcc = 0
		rt.tpos = 1
		s.full = rt.rn
		return
	end
	local queued = tn
	-- the backstop: BACKSTOP vehicles per CYCLE_MS of game time, the cursor moving over the ring
	local out, on = rt.todoBuf, 0
	local rn = rt.rn
	local allow = rt.bAcc + rt.cycDt * M.BACKSTOP / M.CYCLE_MS
	if allow > M.BACKSTOP_MAX then allow = M.BACKSTOP_MAX end
	local k = math.floor(allow)
	rt.bAcc = allow - k
	if k > rn then k = rn end
	local ring, p = rt.ring, rt.bpos
	for _ = 1, k do
		if p > rn then p = 1 end
		local id = ring[p]
		p = p + 1
		if inT[id] ~= cyc then
			inT[id] = cyc
			on = on + 1
			out[on] = id
		end
	end
	rt.bpos = p
	local tb = on
	for i = 1, queued do
		on = on + 1
		out[on] = t[i]
	end
	rt.tB = tb
	rt.tQ, rt.tN, rt.tE = tb + rt.tQ, tb + rt.tN, tb + queued
	rt.todo, rt.tn, rt.tpos = out, on, 1
end

--- "lines": the line watch (only with a setting that shows the line; see the header).
local function lineWatch(rt, cfg, reader)
	local s = rt.stats
	local lines = reader.lines()
	if type(lines) ~= "table" then
		s.lineErr = s.lineErr + 1
		rt.lwOk = false -- line names are re-read once per cycle until the watch works again
		return
	end
	rt.lwOk = true
	local n = #lines
	if n > M.MAX_LINES then
		n = M.MAX_LINES
		s.capped = true
	end
	local lmark, cyc = rt.lmark, rt.cyc
	local hits = nil -- line id -> "name" (all its vehicles) | token (the vehicles not seen in its list: they left)
	local kept, nnew = 0, 0
	local lring, lrn = rt.lring, rt.lrn
	for i = 1, n do
		local li = lines[i]
		local m = lmark[li]
		if m ~= cyc then
			if m == nil then
				nnew = nnew + 1
				lring[lrn + nnew] = li
			else
				kept = kept + 1
			end
			lmark[li] = cyc
		end
	end
	if kept < lrn then
		-- a line vanished: its vehicles are queued (they have no line now, or are gone)
		local j, before, lpos = 0, 0, rt.lpos
		for i = 1, lrn + nnew do
			local li = lring[i]
			if lmark[li] == cyc then
				j = j + 1
				lring[j] = li
			else
				lmark[li] = nil
				rt.lineRaw[li], rt.line[li] = nil, nil
				hits = hits or {}
				hits[li] = "name"
				if i < lpos then before = before + 1 end
			end
		end
		for i = j + 1, lrn + nnew do lring[i] = nil end
		lrn = j
		rt.lpos = lpos - before
		if rt.lpos < 1 then rt.lpos = 1 end
	else
		lrn = lrn + nnew
	end
	rt.lrn = lrn
	-- LINE_RATE lines per CYCLE_MS of game time, a cursor over the line set
	local allow = rt.lAcc + rt.cycDt * M.LINE_RATE / M.CYCLE_MS
	if allow > M.LINE_MAX then allow = M.LINE_MAX end
	local k = math.floor(allow)
	rt.lAcc = allow - k
	if k > lrn then k = lrn end
	local p = rt.lpos
	local vl, mark, seenT = rt.vl, rt.mark, rt.lwSeen
	for _ = 1, k do
		if p > lrn then p = 1 end
		local li = lring[p]
		p = p + 1
		s.lineChecks = s.lineChecks + 1
		local raw = reader.lineName(li) or false
		local was = rt.lineRaw[li]
		if was ~= nil and was ~= raw then
			hits = hits or {}
			hits[li] = "name"
			s.lineHits = s.lineHits + 1
		end
		if was ~= raw then
			rt.lineRaw[li] = raw
			rt.line[li] = Text.lineName(cfg, raw or nil) or false
		end
		local ids = reader.lineVehicles ~= nil and reader.lineVehicles(li) or nil
		if type(ids) == "table" then
			local tok = rt.lwTok + 1
			rt.lwTok = tok
			local nids = #ids
			if nids > M.MAX_LINE_VEH then nids = M.MAX_LINE_VEH end
			local matched = 0
			for i = 1, nids do
				local id = ids[i]
				if mark[id] ~= nil then
					seenT[id] = tok
					if vl[id] == li then
						matched = matched + 1
					elseif qNow(rt, id) then
						s.lineHits = s.lineHits + 1 -- joined this line (or not read yet)
					end
				end
			end
			if matched < (rt.lineN[li] or 0) then
				-- a vehicle this state read on the line is no longer in its list: it left
				hits = hits or {}
				if hits[li] ~= "name" then hits[li] = tok end
				s.lineHits = s.lineHits + 1
			end
		end
	end
	rt.lpos = p
	if hits ~= nil then
		-- one walk of the id set for every line with a hit
		local ring = rt.ring
		for i = 1, rt.rn do
			local id = ring[i]
			local h = hits[vl[id] or 0]
			if h ~= nil and (h == "name" or seenT[id] ~= h) then qNow(rt, id) end
		end
	end
	rt.cycHits = rt.cycHits + s.lineHits
end

local function stepBody(rt, cfg, reader, now, fetch)
	local s = rt.stats
	resetStats(s)
	rt.nops = 0
	rt.dirty = false
	if rt.standDown ~= nil then
		s.phase = "stand"
		return s.phase, nil
	end
	local P = rt.perf or NOPERF
	local st = nil
	local function S()
		if st == nil then
			st = fetch()
			noteFetch(st, rt, now)
		end
		return st
	end
	local w = math.floor(now / M.CYCLE_MS)
	if rt.phase == "list" then
		if not due(rt, now, w) then
			s.phase = "wait"
			return s.phase, st
		end
		local t0 = P:start()
		local okL = listDiff(rt, reader, now, w)
		P:stop("list", t0)
		if not okL then
			-- the list could not be read: try again next window, nothing taken for sold
			rt.cycW = w
			rt.ivW = 1
			s.phase = "wait"
			return s.phase, st
		end
		rt.phase = "prune"
		s.phase = "list"
		return s.phase, st
	elseif rt.phase == "prune" then
		s.phase = "prune"
		rt.npq = 0
		rt.passOn = false
		if pruneNeedsState(rt, cfg, now) then
			S()
			rt.pruneAt = now
			if rt.standDown ~= nil then
				s.phase = "stand"
				return s.phase, st
			end
			local lineMode = cfg.counter == "line"
			local pruned = Reg.prune(st, rt.mark, rt.listAt, now, lineMode and rt.lineTouch or nil)
			s.pruned = pruned
			if pruned > 0 then rt.dirty = true end
			if st.welcome == nil then
				-- nothing is renamed before the welcome answer; a save without vehicles needs no question
				if rt.n == 0 then
					Reg.answer(st, "apply", now)
					st.pass = nil
					rt.dirty = true
					s.autoApply = true
					rt.known.welcome, rt.known.passAt = st.welcome, nil
				elseif st.count ~= rt.n then
					st.count = rt.n
					rt.dirty = true
				end
				rt.phase = "list"
				return s.phase, st
			end
			rt.passOn = st.pass ~= nil and rt.listAt >= (st.pass.at or 0)
		end
		build(rt, cfg, now)
		if st ~= nil and cfg.counter == "line" and not rt.lpInit then
			-- once per Lua state: every line's positions (they may be stale from a load with another counting)
			rt.lpInit = true
			renumberLines(st, rt, nil, true)
		end
		local watch = cfg.usesLine and reader.lines ~= nil
		if not watch then rt.lwOk = false end -- (no line watch: line names are re-read once per cycle)
		rt.phase = watch and "lines" or "scan"
		return s.phase, st
	elseif rt.phase == "lines" then
		s.phase = "lines"
		local t0 = P:start()
		lineWatch(rt, cfg, reader)
		P:stop("lines", t0)
		rt.phase = "scan"
		return s.phase, st
	elseif rt.phase == "scan" then
		local t0 = P:start()
		local todo, reads = rt.todo, 0
		local carry = not rt.noCarry
		while rt.tpos <= rt.tn and reads < M.INSPECT do
			if rt.holdW == w then break end -- (waiting in the scan for the next window: the lease, the budget)
			if carry and rt.carryW == w then
				-- this window's rename budget is spent: the rest waits for the next cycle, unread
				-- (backstop ids are settled ones: not carried, the rotation goes on)
				local c = 0
				for i = rt.tpos, rt.tn do
					if rt.full or i > rt.tB then
						qNext(rt, todo[i], true)
						c = c + 1
					end
				end
				s.carried = s.carried + c
				rt.cycDeferred = rt.cycDeferred + c
				rt.tpos = rt.tn + 1
				break
			end
			local i = rt.tpos
			local id = todo[i]
			rt.tpos = i + 1
			reads = reads + 1
			if rt.full then
				-- (counted at build: full)
			elseif i <= rt.tB then
				s.back = s.back + 1
			elseif i <= rt.tQ or i > rt.tE then
				s.queued = s.queued + 1 -- (retried, or added by the line watch)
			end -- (new ids: listNew; expiries: expDue)
			local letter, mi, res = inspectPre(rt, cfg, reader, id, now)
			if letter ~= nil then
				S()
				if rt.standDown ~= nil then
					P:stop("scan", t0)
					s.phase = "stand"
					return s.phase, st
				end
				res = inspectFull(st, rt, cfg, reader, now, id, letter, mi)
			end
			if res == HOLD then
				-- the leader's window is spent or this state's claim waits: stay at this vehicle until the next
				-- window, so the run goes on in the same cycle (up to HOLD_MS; a pass collecting reads on)
				if rt.holdT0 == nil then rt.holdT0 = now end
				if carry and now - rt.holdT0 < M.HOLD_MS and now >= rt.holdT0 then
					rt.holdW = w
					rt.tpos = i
					break
				end
				res = URGENT
			end
			if res ~= nil then qNext(rt, id, res == URGENT) end
		end
		P:stop("scan", t0)
		if rt.tpos > rt.tn then rt.phase = "end" end
		s.phase = "scan"
		return s.phase, st
	end
	-- "end": the cycle is complete
	if rt.passOn then
		S()
		if st.pass ~= nil then
			local created = Reg.assignPass(st, cfg, rt.pq, rt.npq)
			st.ptotal = created
			s.passCreated = created
			rt.dirty = true
			if cfg.counter == "line" and created > 0 then renumberLines(st, rt, nil, false) end
		end
	end
	-- counting "Per line": renumber the lines whose membership changed in this cycle
	if cfg.counter == "line" and next(rt.lineTouch) ~= nil then
		S()
		renumberLines(st, rt, rt.lineTouch, false)
	end
	if next(rt.lineTouch) ~= nil then rt.lineTouch = {} end
	-- "Not now" + "Number existing vehicles on next load" Yes: the welcome window shows how many are untouched
	-- (counted over the id set: every vehicle was read once since the answer this state knows, a full cycle)
	if countMode(rt, cfg) then
		local c, ring, uS, uG, gen = 0, rt.ring, rt.uS, rt.uG, rt.gen
		for i = 1, rt.rn do
			local id = ring[i]
			if uS[id] == "untouched" and uG[id] == gen then c = c + 1 end
		end
		rt.cycUnt = c
		local k = rt.known
		if k.count ~= c then
			S()
			if st.welcome == "later" and st.pass == nil and st.count ~= c then
				st.count = c
				rt.dirty = true
			end
			rt.known.count = st.count
		end
	end
	-- the idle back-off: a cycle without change doubles the interval (up to IDLE_MAX_W windows), any change resets it
	if rt.dirty then rt.cycDirty = true end
	local k = rt.known
	local changed = k == nil or k.welcome == nil or k.passAt ~= nil or rt.full or rt.passOn or rt.cycNew > 0
		or rt.cycGone > 0 or rt.cycUrgent > 0 or rt.cycRenamed > 0 or rt.cycDirty or rt.cycHits > 0 or rt.cycExp > 0
	if changed then
		rt.ivW = 1
	else
		rt.ivW = rt.ivW * 2
		if rt.ivW > M.IDLE_MAX_W then rt.ivW = M.IDLE_MAX_W end
	end
	rt.passOn = false
	rt.pq, rt.npq = {}, 0
	rt.todo = nil
	rt.lastDeferred, rt.lastWait = rt.cycDeferred, rt.cycWait
	rt.phase = "list"
	s.phase = "end"
	return s.phase, st
end

--- One update's slice of work, reading the register only when needed (see the header). Returns the phase that ran
--- and the register read in this step (nil when none was).
function M.stepLazy(rt, cfg, reader, now, fetch)
	local phase, st = stepBody(rt, cfg, reader, now, fetch)
	if rt.dirty and st ~= nil then
		M.noteCounters(rt, st)
		rt.cycDirty = true
	end
	return phase, st
end

--- One update's slice with a register already read (phase 1 entry): st.standDown stands it down.
function M.step(st, rt, cfg, reader, now)
	if st.standDown ~= nil then rt.standDown = st.standDown end
	local phase = M.stepLazy(rt, cfg, reader, now, function() return st end)
	return phase
end

return M
