-- Better Auto Vehicle Renamer: the fleet register (the per-save game-script state). Pure: no api.*, Lua 5.1 syntax.
-- PLAN.md "Per-save state", "First load of a save", "Replace".
--
-- The state holds only plain numbers, strings and string-keyed / array tables (the shape other square game scripts
-- store; numeric entity-id keys are avoided: ids are keys as strings, Reg.key):
--   ver      VERSION
--   nt       { [letter] = next per-type number }        na   next number of "One for all"
--   nm       { [model key] = next per-model number }    (model key: the model's file name, stable across loads)
--   nj       next line-join sequence number (rec.lj: the order of the vehicles on a line, counting "Per line")
--   v        { [Reg.key(id)] = rec }
--   welcome  "apply" | "later" | nil (not answered: nothing is renamed)
--   cutoff   game ms: with welcome "later", a vehicle bought before it that has no record is left alone ("untouched")
--   pass     { at = ms, cutoff = ms } while an "Apply" pass (number the existing vehicles, oldest first) is due
--   count    vehicle count while the welcome is unanswered (for the window's "Number your N existing vehicles")
--   standDown reason string when a conflicting mod is active (nothing is renamed)
--   win, used  the current 2 s rename window and the renames sent in it (shared budget across Lua states)
--   lo, le, lq  the rename lease: the token of the one Lua state that sends renames, the game ms it ends and its
--            epoch (+1 per claim) (bavr_sweep.lua "The rename lease"; dropped at the first init of a new load,
--            bavr_game.lua firstOfLoad)
--   gone     { { li, k, t, a, m, mk, at, lj }, ... } records of vehicles that just disappeared, for Replace matching
--   ptotal, pdone  vehicles the Apply pass numbered and the renames sent for it, while its renames run (pass
--            progress; the game script clears both with the "pass done" line; a save made mid-run goes on counting
--            after a load; a save from before rh drops them once; bavr_game.lua)
--   rh       the settings hash the names were last rendered with (a load with another one starts a re-render)
--   rb, rr   a re-render's vehicles (names of ours when it started) and the renames sent for it, until "rerender
--            done" (bavr_game.lua)
--   plog     game ms of the last progress line (pass / rerender: one line per LOG_MS from whichever state renames)
--   words    { [letter] = full type word, O = the "(old)" marker word } in the player's language, from the GUI
--            (bavr_game.lua "words")
--   sdSeen   1 once the stand-down notice was shown (the welcome window shows it once per save)
--   boot     game ms of this load's first game-script init (one init log line per load; bavr_game.lua)
--   bootT    wall-clock seconds (os.time) of that init, when the game script has a clock
-- rec = { k, t, a, m, mk, pt, li, lj, lp, last, orig, user, ts, rc }:
--   k letter; t / a / m the per-type / global / per-model numbers (all three are kept, so switching "Counting" never
--   renumbers); mk the model key m belongs to; pt purchase time of part 1 (game ms; catches a reused id); li line id
--   (0 = none); lj the vehicle's join sequence number on that line (st.nj; counting "Per line": the order on the
--   line, unique, so no two vehicles tie; missing = 0, then purchase time);
--   lp its position on the line (1-based, Reg.linePositions; nil until computed or after a line change); last the
--   name we last sent; orig the name before we first renamed it; user = 1 when the player typed a
--   name; ts game ms of the last send (a send is "pending" for PENDING_MS); rc sends of the same name (RETRY_MAX).
-- Numbers only go up: `nt` / `na` / `nm` never decrease, so a pruned record's number stays retired. The per-line
-- position `lp` is the one number that moves: it closes up when a vehicle ahead on the line leaves (PLAN.md "Per line").
--
-- Entry points:
--   Reg.new(), Reg.validate(raw) -> st (repairs or upgrades anything else; never errors)
--   Reg.validateLight(raw) -> st: the top level only, for later reads of a state this load already validated (a
--       full validate walks every record); falls back to Reg.validate on anything unexpected
--   Reg.cleanWords(w) -> { [letter] = word } | nil  (the GUI's words: strings of 1..MAX_WORD_BYTES bytes)
--   Reg.wordsKey(w) -> string (one string of the words, to tell a change)
--   Reg.key(id), Reg.get(st, id)
--   Reg.create(st, cfg, id, letter, mk, pt, li) -> rec      Reg.join(st) -> the next join sequence number
--   Reg.shown(rec, cfg) -> number, perLine   (the number the name shows; perLine: it is the position on the line)
--   Reg.linePositions(st, lines, out) -> n   (renumber the positions on the lines in the set `lines`, or on
--       every line when lines is nil; the ids whose position moved go into out[1..n])
--   Reg.setModel(st, rec, mk, cfg) -> changed               (Replace with another model: next per-model number)
--   Reg.prune(st, present, listAt, now) -> pruned            (records whose id is gone, into st.gone)
--   Reg.takeGone(st, li, k, now) -> entry | nil              (a new id on the same line and type: Replace)
--   Reg.answer(st, answer, now)                              (welcome: "apply" | "later")
--   Reg.welcomeDue(st, cfg, count) -> "first" | "renumber" | nil
--   Reg.assignPass(st, cfg, entries, n) -> created           (oldest first; entries flat {id, pt, k, mk, li, ...})
--   Reg.size(st) -> records (capped count, for logs)
--   Reg.ours(st) -> records that show a name of ours (sent, not hand-typed; capped)

local M = {}

M.VERSION = 1
M.MAX_RECORDS = 100000  -- loop cap on record walks
M.MAX_GONE = 64         -- gone entries kept for Replace matching
M.GONE_MS = 10000       -- game ms a gone entry can still be matched (about one cycle: a sale and a new purchase
                        -- on the same line later than that keep their own numbers)
M.PASS_FIELDS = 5       -- id, pt, letter, model key, line id
M.MAX_PASS = 50000      -- vehicles one Apply pass numbers (more is cut, with a log reason in the stats)
M.MAX_WORD_BYTES = 40   -- a full type word from the GUI

local LETTER_OK = { B = true, T = true, R = true, L = true, S = true, A = true, H = true }

local KEYS = {}
local nkeys = 0
--- The record key of an entity id (memoized; the memo is dropped past MAX_RECORDS * 2 entries).
function M.key(id)
	local k = KEYS[id]
	if k ~= nil then return k end
	if nkeys >= M.MAX_RECORDS * 2 then
		KEYS, nkeys = {}, 0
	end
	k = tostring(math.floor(id))
	KEYS[id] = k
	nkeys = nkeys + 1
	return k
end

function M.new()
	return { ver = M.VERSION, nt = {}, na = nil, nm = {}, v = {}, gone = {} }
end

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v < 0 or v == math.huge then return nil end
	return math.floor(v)
end

local function str(v) return type(v) == "string" and v or nil end

--- A record cleaned (nil when unusable).
local function cleanRec(r)
	if type(r) ~= "table" or not LETTER_OK[r.k] then return nil end
	local out = { k = r.k, t = num(r.t), a = num(r.a), m = num(r.m), mk = str(r.mk), pt = num(r.pt), li = num(r.li),
		lj = num(r.lj), lp = num(r.lp), last = str(r.last), orig = str(r.orig), user = r.user == 1 and 1 or nil, ts = num(r.ts), rc = num(r.rc) }
	if out.t == nil then return nil end
	return out
end

--- The state for whatever state:get() returned: a fresh one for nil / garbage / a newer version, the same table
--- (cleaned in place) otherwise. Second result: "new" | "ok" | "repaired".
function M.validate(raw)
	if type(raw) ~= "table" or raw.ver == nil then return M.new(), "new" end
	if tonumber(raw.ver) ~= M.VERSION then return M.new(), "new" end -- a newer version: never guess its layout
	local repaired = false
	local function tbl(k)
		if type(raw[k]) ~= "table" then
			raw[k] = {}
			repaired = true
		end
	end
	tbl("nt"); tbl("nm"); tbl("v"); tbl("gone")
	for k, v in pairs(raw.nt) do
		if not LETTER_OK[k] or num(v) == nil then raw.nt[k] = nil; repaired = true end
	end
	if raw.na ~= nil and num(raw.na) == nil then raw.na = nil; repaired = true end
	if raw.nj ~= nil and num(raw.nj) == nil then raw.nj = nil; repaired = true end
	local n = 0
	for k, r in pairs(raw.v) do
		n = n + 1
		if n > M.MAX_RECORDS then break end
		local c = cleanRec(r)
		if c == nil or type(k) ~= "string" then
			raw.v[k] = nil
			repaired = true
		elseif r.user ~= c.user or r.t ~= c.t or r.lp ~= c.lp or r.lj ~= c.lj then
			raw.v[k] = c
			repaired = true
		end
	end
	if raw.welcome ~= nil and raw.welcome ~= "apply" and raw.welcome ~= "later" then raw.welcome = nil; repaired = true end
	if raw.pass ~= nil and (type(raw.pass) ~= "table" or num(raw.pass.at) == nil) then raw.pass = nil; repaired = true end
	if raw.standDown ~= nil and type(raw.standDown) ~= "string" then raw.standDown = nil; repaired = true end
	if raw.words ~= nil then
		local w = M.cleanWords(raw.words)
		if w == nil then raw.words = nil; repaired = true else raw.words = w end
	end
	if raw.sdSeen ~= nil and raw.sdSeen ~= 1 then raw.sdSeen = nil; repaired = true end
	if raw.boot ~= nil and num(raw.boot) == nil then raw.boot = nil; repaired = true end
	if raw.bootT ~= nil and num(raw.bootT) == nil then raw.bootT = nil; repaired = true end
	if raw.count ~= nil and num(raw.count) == nil then raw.count = nil; repaired = true end
	for _, k in ipairs({ "ptotal", "pdone", "rb", "rr", "plog" }) do
		if raw[k] ~= nil and num(raw[k]) == nil then raw[k] = nil; repaired = true end
	end
	if raw.rh ~= nil and type(raw.rh) ~= "string" then raw.rh = nil; repaired = true end
	if (raw.lo ~= nil or raw.le ~= nil) and (type(raw.lo) ~= "string" or num(raw.le) == nil) then
		raw.lo, raw.le, raw.lq = nil, nil, nil
		repaired = true
	end
	if raw.lq ~= nil and num(raw.lq) == nil then raw.lq = nil; repaired = true end
	return raw, repaired and "repaired" or "ok"
end

function M.validateLight(raw)
	if type(raw) ~= "table" or tonumber(raw.ver) ~= M.VERSION then return M.validate(raw) end
	if type(raw.nt) ~= "table" or type(raw.nm) ~= "table" or type(raw.v) ~= "table" or type(raw.gone) ~= "table" then
		return M.validate(raw)
	end
	return raw, "ok"
end

--- The full type words as stored: every letter a string of 1..MAX_WORD_BYTES bytes, else nil (all or nothing);
--- O (the old-vehicle marker word) is optional and dropped when unusable.
function M.cleanWords(w)
	if type(w) ~= "table" then return nil end
	local out = {}
	for l in pairs(LETTER_OK) do
		local s = w[l]
		if type(s) ~= "string" or s == "" or #s > M.MAX_WORD_BYTES then return nil end
		out[l] = s
	end
	local o = w.O
	if type(o) == "string" and o ~= "" and #o <= M.MAX_WORD_BYTES then out.O = o end
	return out
end

--- One string of the words (to tell a change; letters in a fixed order).
local WORD_ORDER = { "B", "T", "R", "L", "S", "A", "H", "O" }
function M.wordsKey(w)
	if type(w) ~= "table" then return "" end
	local parts = {}
	for i = 1, #WORD_ORDER do parts[i] = tostring(w[WORD_ORDER[i]]) end
	return table.concat(parts, "|")
end

function M.get(st, id) return st.v[M.key(id)] end

-- next number of a counter table entry (numbers only go up; start raises it, never lowers it)
local function takeFrom(t, k, start)
	local n = t[k]
	if n == nil or n < start then n = start end
	t[k] = n + 1
	return n
end

local function takeAll(st, start)
	local n = st.na
	if n == nil or n < start then n = start end
	st.na = n + 1
	return n
end

--- A new record with all three numbers taken (per type, global, per model).
--- The next line-join sequence number (counting "Per line": the order on a line).
function M.join(st)
	local n = st.nj
	if n == nil or n < 1 then n = 1 end
	st.nj = n + 1
	return n
end

function M.create(st, cfg, id, letter, mk, pt, li)
	local start = cfg.start or 1
	local rec = { k = letter, t = takeFrom(st.nt, letter, start), a = takeAll(st, start), pt = pt, li = li or 0,
		lj = M.join(st) }
	if mk ~= nil then
		rec.mk = mk
		rec.m = takeFrom(st.nm, mk, start)
	end
	st.v[M.key(id)] = rec
	return rec
end

--- The number the name shows under the "Counting" setting, and whether it is a position on the line ("Per line"
--- with a line and a computed position; a vehicle without a line shows its per-type number).
function M.shown(rec, cfg)
	if cfg.counter == "all" then return rec.a or rec.t, false end
	if cfg.counter == "model" then return rec.m or rec.t, false end
	if cfg.counter == "line" and (rec.li or 0) > 0 and rec.lp ~= nil then return rec.lp, true end
	return rec.t, false
end

--- Counting "Per line": number the vehicles of each line in `lines` (a set { [line id] = true }; nil = every line)
--- 1, 2, 3 ... in the order they joined it (lj, then purchase time, then id: stable and the same in every Lua state).
--- A vehicle that leaves closes the gap: the ones after it move up by one; a vehicle that joins comes last, so it
--- moves nobody. Hand-typed vehicles keep their place (their name is never changed). Writes rec.lp; the ids whose
--- position changed go into out (out[1..n]; optional). Returns n. One walk of the records (capped at MAX_RECORDS)
--- plus a sort per line asked for.
function M.linePositions(st, lines, out)
	local groups = {}
	local walked = 0
	for k, rec in pairs(st.v) do
		walked = walked + 1
		if walked > M.MAX_RECORDS then break end
		local li = rec.li or 0
		if li > 0 and (lines == nil or lines[li]) then
			local g = groups[li]
			if g == nil then
				g = {}
				groups[li] = g
			end
			g[#g + 1] = k
		end
	end
	local v, n = st.v, 0
	local function before(x, y)
		local rx, ry = v[x], v[y]
		local jx, jy = rx.lj or 0, ry.lj or 0
		if jx ~= jy then return jx < jy end
		local px, py = rx.pt or 0, ry.pt or 0
		if px ~= py then return px < py end
		return (tonumber(x) or 0) < (tonumber(y) or 0)
	end
	for _, g in pairs(groups) do
		if #g > 1 then table.sort(g, before) end
		for i = 1, #g do
			local rec = v[g[i]]
			if rec.lp ~= i then
				rec.lp = i
				n = n + 1
				if out ~= nil then out[n] = tonumber(g[i]) end
			end
		end
	end
	return n
end

--- The lead model changed (Replace): the per-model number follows the new model. True when it changed.
function M.setModel(st, rec, mk, cfg)
	if mk == nil or rec.mk == mk then return false end
	rec.mk = mk
	rec.m = takeFrom(st.nm, mk, cfg.start or 1)
	return true
end

--- Drop the records whose id is not in `present` (set of ids from the list taken at game ms listAt). A record of a
--- vehicle bought after listAt is kept (another Lua state may have a newer list). Pruned records with a line go to
--- st.gone for Replace matching, and their line into the set `lines` when given (counting "Per line": those lines
--- are renumbered). Returns the number pruned.
function M.prune(st, present, listAt, now, lines)
	local drop, n = {}, 0
	local walked = 0
	for k, rec in pairs(st.v) do
		walked = walked + 1
		if walked > M.MAX_RECORDS then break end
		local id = tonumber(k)
		if id == nil or (not present[id] and (rec.pt == nil or listAt == nil or rec.pt < listAt)) then
			n = n + 1
			drop[n] = k
		end
	end
	-- in a fixed order (purchase time, then id), so st.gone (and Replace matching, oldest first) never depends on
	-- the hash order of pairs()
	if n > 1 then
		local v = st.v
		table.sort(drop, function(x, y)
			local px, py = v[x].pt or 0, v[y].pt or 0
			if px ~= py then return px < py end
			return (tonumber(x) or 0) < (tonumber(y) or 0)
		end)
	end
	for i = 1, n do
		local rec = st.v[drop[i]]
		st.v[drop[i]] = nil
		if rec.li and rec.li > 0 then
			if lines ~= nil then lines[rec.li] = true end
			local g = st.gone
			if #g >= M.MAX_GONE then table.remove(g, 1) end
			g[#g + 1] = { rec.li, rec.k, rec.t, rec.a, rec.m or 0, rec.mk or "", now or 0, rec.lj or 0 }
		end
	end
	-- expire old gone entries
	local g, kept = st.gone, {}
	for i = 1, math.min(#g, M.MAX_GONE * 2) do
		local e = g[i]
		if type(e) == "table" and (now or 0) - (e[7] or 0) <= M.GONE_MS then kept[#kept + 1] = e end
	end
	st.gone = kept
	return n
end

--- A gone record on line li with letter k (the oldest one), removed from st.gone; nil when none.
function M.takeGone(st, li, k, now)
	if li == nil or li <= 0 then return nil end
	local g = st.gone
	for i = 1, math.min(#g, M.MAX_GONE * 2) do
		local e = g[i]
		if e[1] == li and e[2] == k and (now or 0) - (e[7] or 0) <= M.GONE_MS then
			table.remove(g, i)
			return e
		end
	end
	return nil
end

--- The welcome window's answer. "apply": number the existing vehicles (a pass, oldest first); "later": leave the
--- vehicles bought before now as they are; only new ones get numbers.
function M.answer(st, answer, now)
	if answer == "apply" then
		st.welcome = "apply"
		st.pass = { at = now, cutoff = now }
		st.cutoff = nil
	else
		st.welcome = "later"
		st.cutoff = st.cutoff or now
		st.pass = nil
	end
	st.count = nil
end

--- Whether the welcome window is due: "first" (never answered, the save has vehicles), "renumber" (answered "Not
--- now" and the setting "Number existing vehicles on next load" is Yes), nil otherwise.
function M.welcomeDue(st, cfg, count)
	if st.standDown then return nil end
	if st.welcome == nil then return (count or 0) > 0 and "first" or nil end
	if st.welcome == "later" and cfg.renumberNext and st.pass == nil then return "renumber" end
	return nil
end

--- The Apply pass: create records for the collected vehicles, oldest first (purchase time, then id). entries is a
--- flat array of PASS_FIELDS values per vehicle, n vehicles. Duplicates and vehicles that already have a record are
--- skipped. Clears st.pass and st.cutoff. Returns the number of records created.
function M.assignPass(st, cfg, entries, n)
	if n > M.MAX_PASS then n = M.MAX_PASS end
	local order = {}
	for i = 1, n do order[i] = i end
	local F = M.PASS_FIELDS
	table.sort(order, function(x, y)
		local px, py = entries[(x - 1) * F + 2], entries[(y - 1) * F + 2]
		if px ~= py then return px < py end
		return entries[(x - 1) * F + 1] < entries[(y - 1) * F + 1]
	end)
	local created = 0
	for i = 1, n do
		local b = (order[i] - 1) * F
		local id = entries[b + 1]
		if st.v[M.key(id)] == nil then
			local mk = entries[b + 4]
			M.create(st, cfg, id, entries[b + 3], mk ~= "" and mk or nil, entries[b + 2], entries[b + 5])
			created = created + 1
		end
	end
	st.pass = nil
	st.cutoff = nil
	return created
end

--- Number of records (capped at MAX_RECORDS).
function M.size(st)
	local n = 0
	for _ in pairs(st.v) do
		n = n + 1
		if n >= M.MAX_RECORDS then break end
	end
	return n
end

function M.ours(st)
	local n, walked = 0, 0
	for _, r in pairs(st.v) do
		walked = walked + 1
		if walked > M.MAX_RECORDS then break end
		if r.last ~= nil and r.user ~= 1 then n = n + 1 end
	end
	return n
end

return M
