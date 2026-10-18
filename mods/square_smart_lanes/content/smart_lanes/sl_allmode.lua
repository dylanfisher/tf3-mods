-- Smart Lanes "Automatic light timing" (all lights) and the first-load welcome (PLAN.md "Automatic timing for all
-- lights + first-load welcome"). Pure helpers, Lua 5.1 syntax; used by the game script's event handler
-- (sl_lanes.script.lua handleAuto: the per-save mode, opt-outs, the welcome answer, the existing-junctions pass
-- request), the GUI automatic pass (sl_lanes.script.lua guiBody: the existing-junctions pass in slices), the runtime
-- (sl_autoretime.lua: the periodic all-lights listing), the settings panel (sl_settingsui.lua: Automatic light timing,
-- in the Smart Lanes tool and the Crossing Tool) and the welcome window (sl_bg.script.lua).
--
-- Mode: the mod.json setting "Automatic light timing" (sqrl_auto_lights: Junctions I choose = "pick", the default /
-- All lights = "all" / Off = "off"), overridden per save by the game-script state's `amode` ("all" | "pick" | "off"),
-- which the welcome's Apply (lights box ticked) and the settings panel's Automatic light timing write. Off (user
-- 2026-10-17, a player's "stutter fest" report): no junction is re-timed and the runtime counts no traffic; the
-- enrolled list and the opt-outs are kept, so a later Junctions I choose or All lights picks them up again.
--
-- Saved (game-script state, each written from its first use only; sl_auto.lua header lists the older keys):
--   amode = "all" | "pick" | "off"         the per-save override of the setting
--   aout  = { {n, x, y}, ... }             junctions the player unticked (Keep timing adjusted No) while all lights
--                                          are kept adjusted: never enrolled again by the listing (at most OUT_MAX,
--                                          the oldest dropped beyond: AUTORETIME op=optout_drop)
--   wel   = 1 | 2                          the welcome's answer (1 Not now / closed, 2 Apply): asked once per save
--   mpass = { seq = n, done = n }          the existing-junctions pass: requested (seq) and finished (done); a pass
--                                          that did not finish (the game quit) runs again at the next load
--   alit  = { seq = k, nodes = {{id, k [, 1]}} }
--                                          while all lights are kept adjusted: the nodes the latest player builds
--                                          touched (at most NEW_SAVED_MAX), not enrolled or opted out by id; the
--                                          runtime looks at them at once ("New lights at once" below). A third
--                                          field 1 (2026-10-16): a node of a config-only build (a light switched
--                                          on in the Crossing Tool / node window) while Light phases = Smart Lanes
--                                          and Apply automatically is On: the runtime also gives it Smart Lanes
--                                          phases ("New lights get Smart lights" below); such builds are saved
--                                          also without all lights, enrolled nodes included.
-- Size bound: OUT_MAX x 3 numbers + NEW_SAVED_MAX x 3 numbers + a short string + 4 numbers (under 45 kB in test_allmode.lua's verbose
-- serialization). Each key is written from its first use only: wel when the welcome is answered (Not now included),
-- amode / mpass by Apply or the tool, aout by an untick while all lights are kept adjusted, alit by a build while
-- all lights are kept adjusted.

local M = {}

M.PARAM = "sqrl_auto_lights"
M.MODES = { "pick", "all", "off" } -- mod.json values: Junctions I choose / All lights / Off (last: saved indices hold)
M.DEFAULT = 1                 -- 1-based: Junctions I choose
M.OUT_MAX = 1000              -- opt-outs kept (= Auto.MAX)
M.WEL = { later = 1, apply = 2 }
M.WEL_NAME = { [1] = "later", [2] = "apply" }

-- The all-lights listing (sl_autoretime.lua): once when all lights start (the mirror's first read, the mode turning
-- all), then every LIST_EVERY_S game s while all lights are kept adjusted, the lit junctions not enrolled, not opted
-- out and not timed by hand are enrolled (first come, up to Auto.MAX). The player's new lights come at once from
-- their builds ("New lights at once" below), so the repeat is only the safety net for lights no player build brought
-- (a town's own streets, a look given up): 60 game min since 2026-10-17 (was 5; user: "finding lights is the biggest
-- waste", a listing read every node of the map where the lit-node list is unreadable).
M.LIST_EVERY_S = 3600

-- The existing-junctions pass (sl_lanes.script.lua guiBody, PLAN.md "Existing junctions pass"): the street nodes
-- with a node config are listed once, then scanned in slices of at most SLICE junctions (nodes with >= 3 street
-- segments), each slice handed to the automatic pass as one job (the build path: rings whole, slips, crossroads,
-- T-junctions; kept and hand-edited nodes skipped). Hard caps: LIST_MAX list entries scanned, JUNCTIONS_MAX
-- junctions planned; a visited set (node ids) so no node is scanned twice; per frame at most SCAN_PER_FRAME entries
-- and SCAN_BUDGET_MS of clock (checked every CHECK_EVERY entries).
M.PASS_LIST_MAX = 500000
M.PASS_JUNCTIONS_MAX = 20000
M.PASS_SLICE = 160
M.PASS_SCAN_PER_FRAME = 400
M.PASS_SCAN_BUDGET_MS = 2
M.PASS_CHECK_EVERY = 16
M.PASS_PROGRESS_EVERY = 10    -- slices between two MAPPASS op=progress lines
M.PASS_R = 20000              -- m: the octree fallback's circle around (0, 0) when no component list can be read
M.PASS_MIN_SEGS = 3

-- The welcome window (sl_bg.script.lua): the saved state is read DELAY_FRAMES GUI frames after the first step (the
-- game-script state is loaded by then), then every RETRY_FRAMES frames up to TRIES times while it cannot be read.
M.WELCOME_DELAY_FRAMES = 180
M.WELCOME_RETRY_FRAMES = 60
M.WELCOME_TRIES = 10

--- The setting's mode from this mod's raw mod params (nil or a table of 1-based indices): "pick" | "all" | "off";
-- the default when missing or not one of the values.
function M.settingOf(raw)
	local i = type(raw) == "table" and tonumber(raw[M.PARAM]) or nil
	if i == nil or i ~= math.floor(i) or i < 1 or i > #M.MODES then i = M.DEFAULT end
	return M.MODES[i]
end

--- Whether s is one of the modes.
function M.isMode(s)
	for _, m in ipairs(M.MODES) do
		if s == m then return true end
	end
	return false
end

--- The mode in force: the per-save override when it is one of the modes, else the setting ("pick" when that is not
-- a mode either).
function M.effective(setting, override)
	if M.isMode(override) then return override end
	if M.isMode(setting) then return setting end
	return "pick"
end

--- Whether the game runs the map editor (getModParams()[""].isMapEditor; false when unreadable).
function M.isMapEditor(all)
	local g = type(all) == "table" and all[""] or nil
	return type(g) == "table" and g.isMapEditor == true
end

---------------------------------------------------------------------------
-- Opt-outs

--- The opt-out list after adding nodes ({n, x, y} entries, cleaned by the caller): a fresh list; a node already in
-- it (by id or within 2 m) is not added twice; beyond OUT_MAX the oldest are dropped. Returns list, added, dropped.
-- matchFn(list, n, x, y) -> bool (Auto.matches over a list; passed in so this file needs no other module).
function M.optOut(list, nodes, matches)
	local cur = {}
	for i, e in ipairs(type(list) == "table" and list or {}) do
		if i > M.OUT_MAX then break end
		if type(e) == "table" then cur[#cur + 1] = { e[1], e[2], e[3] } end
	end
	local added = 0
	for i, e in ipairs(nodes or {}) do
		if i > 60 then break end
		local hit = false
		for _, a in ipairs(cur) do
			if matches(a, e[1], e[2], e[3]) then
				hit = true
				a[1], a[2], a[3] = e[1], e[2], e[3]
				break
			end
		end
		if not hit then
			cur[#cur + 1] = { e[1], e[2], e[3] }
			added = added + 1
		end
	end
	local dropped = 0
	while #cur > M.OUT_MAX do
		table.remove(cur, 1)
		dropped = dropped + 1
	end
	return cur, added, dropped
end

--- The opt-out list without the given nodes (ticked by hand again): a fresh list and how many were removed.
function M.optIn(list, nodes, matches)
	local cur, removed = {}, 0
	for i, a in ipairs(type(list) == "table" and list or {}) do
		if i > M.OUT_MAX then break end
		local hit = false
		for j, e in ipairs(nodes or {}) do
			if j > 60 then break end
			if type(a) == "table" and matches(a, e[1], e[2], e[3]) then
				hit = true
				break
			end
		end
		if hit then removed = removed + 1 elseif type(a) == "table" then cur[#cur + 1] = a end
	end
	return cur, removed
end

---------------------------------------------------------------------------
-- Timed by hand

--- Whether a duration is a whole second (the Crossing window's slider, Lights only, Re-time and the Smart Lanes
-- phase plan write whole seconds; the game's own greens are not: 18.86 / 21.55 / 23.70 / 27.09 s, findings roads.md
-- "Default traffic light phases, measured in game").
function M.wholeSecond(d)
	return type(d) == "number" and d == d and math.abs(d - math.floor(d + 0.5)) < 0.01
end

--- Whether the all-lights listing leaves a lit junction alone as timed by hand: its config says
-- userModifiedTrafficLightStates, Smart Lanes never measured it (no rlast record: Re-time and Keep timing adjusted
-- record every junction they measured), every vehicle green is a whole second, and the Light phases setting is not
-- Smart Lanes (whose plans are whole seconds too). The engine sets the flag on any phases write, ours included
-- (docs/findings/roads.md "Phases-only writes set userModifiedTrafficLightStates"), so the flag alone can't tell.
-- greens: the vehicle phases' durations (Retime.kinds "veh"); none counts as not timed by hand.
function M.handTimed(um, greens, recorded, slPhases)
	if um ~= true or recorded or slPhases then return false end
	if type(greens) ~= "table" or #greens == 0 then return false end
	for _, d in ipairs(greens) do
		if not M.wholeSecond(d) then return false end
	end
	return true
end

--- M.handTimed from a light's phases: um (the config's userModifiedTrafficLightStates), states ({ locked, duration }
-- each: sl_autoretime readJunction's states or M.statesOf), the counts of connections and crosswalks, kindsFn
-- (Retime.kinds: which phases are vehicle phases). False when the kinds can't be told.
function M.handTimedOf(um, states, nConns, nCross, kindsFn, recorded, slPhases)
	if um ~= true or recorded or slPhases or type(states) ~= "table" then return false end
	local okK, kinds = pcall(kindsFn, nConns or 0, nCross or 0, states)
	if not okK or type(kinds) ~= "table" then return false end
	local greens = {}
	for i, st in ipairs(states) do
		if kinds[i] == "veh" then greens[#greens + 1] = st.duration end
	end
	return M.handTimed(um, greens, recorded, slPhases)
end

--- A light config's phases as { locked, duration } tables (bounded: at most 64 phases, 512 locked lanes each).
function M.statesOf(tlcStates)
	local out = {}
	for i, st in ipairs(tlcStates or {}) do
		if i > 64 then break end
		local l = {}
		for j, x in ipairs(st.lockedLanes or {}) do
			if j > 512 then break end
			l[#l + 1] = x
		end
		out[i] = { locked = l, duration = st.duration }
	end
	return out
end

---------------------------------------------------------------------------
-- New lights at once (PLAN.md "New lights at once"): the all-lights rules at one lit junction not enrolled, the
-- nodes a build touched (saved by the game script as alit, looked at by the runtime at once) and the runtime's queue
-- of them (a light the game adds a moment after the build: looked at again a few times, then given up; the periodic
-- listing stays the safety net).

M.NEW_SAVED_MAX = 60          -- node ids in the saved alit list (the latest; the oldest dropped beyond)
M.NEW_SEEDS_MAX = 60          -- node ids taken from one build
M.NEW_QUEUE_MAX = 240         -- nodes waiting in the runtime's queue (more: dropped, the listing finds them)
M.NEW_PER_FRAME = 16          -- nodes looked at per frame
M.NEW_RETRY_S = { 3, 10, 30 } -- game s after the first look: looked at again while no light (with phases) stands

-- New lights get Smart lights (PLAN.md "New lights get Smart lights", 2026-10-16): a node of a config-only player
-- build (the Crossing Tool's or the node window's light switched on) while Light phases = Smart Lanes (the setting or
-- this save's in-game setting; or an sl_phases / sl_auto zone there) and Apply automatically is On is queued with
-- .plan; the runtime (sl_autoretime.lua newStep) gives a crossroads / T-junction there whose standing light still has
-- the game's own default phases (Retime.phasesDefault: never flagged user-modified, so never timed by hand, re-timed
-- or planned by us) and that the tool's Reset did not keep the Smart Lanes axis plan (W.planLights, LIGHTS
-- src=new_light), at most NEW_PLANS_PER_FRAME a frame; the enrollment look (all lights) follows NEW_RETRY_S[1] s later,
-- so Keep timing adjusted starts from the plan. Builds that add streets are the automatic pass's (its lane write
-- carries the plan; a light that comes later: its re-check), never planned here.
M.NEW_PLANS_PER_FRAME = 1     -- phases-only proposals per frame from the new-light look (2 until 2026-10-17: frames
                              -- up to 7.3 ms, PERF_REVIEW.md "First All lights run with the sections")
M.NEW_PLAN_LINES_MAX = 200    -- PHASES src=new_light lines per session

--- What the all-lights rules do at a lit junction that is not enrolled: "enroll", or why not: "off" (Junctions I
-- choose, Off, or the map editor), "optout" (the player turned it off), "hand" (timed by hand), "cap" (max enrolled).
function M.decide(mode, editor, optedOut, hand, enrolledN, max)
	if mode ~= "all" or editor then return "off" end
	if optedOut then return "optout" end
	if hand then return "hand" end
	if (enrolledN or 0) >= (max or 0) then return "cap" end
	return "enroll"
end

--- The game script's part: the saved alit list { seq = k, nodes = { {id, k [, 1]}, ... } } with a build's node ids
-- added (a fresh table; seq + 1 once; at most NEW_SAVED_MAX entries, the oldest dropped). Ids that are not whole
-- non-negative numbers are left out. plan: the build's nodes also get the Smart Lanes phases look (third field 1).
-- Returns the list and how many were added (0: the list unchanged, nil when none).
function M.litAdd(alit, ids, plan)
	local old = type(alit) == "table" and alit or {}
	local seq = (tonumber(old.seq) or 0) + 1
	local nodes = {}
	for i, e in ipairs(type(old.nodes) == "table" and old.nodes or {}) do
		if i > M.NEW_SAVED_MAX then break end
		if type(e) == "table" and type(e[1]) == "number" and type(e[2]) == "number" then
			nodes[#nodes + 1] = { e[1], e[2], e[3] == 1 and 1 or nil }
		end
	end
	local added = 0
	for i, id in ipairs(ids or {}) do
		if i > M.NEW_SEEDS_MAX then break end
		if type(id) == "number" and id >= 0 and id == math.floor(id) then
			nodes[#nodes + 1] = { id, seq, plan and 1 or nil }
			added = added + 1
		end
	end
	if added == 0 then return alit, 0 end
	while #nodes > M.NEW_SAVED_MAX do table.remove(nodes, 1) end
	return { seq = seq, nodes = nodes }, added
end

--- The runtime's part: the node ids of a read alit list added after lastSeq, the list's seq (nil: none saved) and the
-- set of those ids that want the Smart Lanes phases look ({ [id] = true }, the third field 1).
function M.litSince(alit, lastSeq)
	if type(alit) ~= "table" then return {}, nil, {} end
	local seq = tonumber(alit.seq)
	local out, plan = {}, {}
	if lastSeq ~= nil and seq ~= nil and seq <= lastSeq then return out, seq, plan end
	for i, e in ipairs(type(alit.nodes) == "table" and alit.nodes or {}) do
		if i > M.NEW_SAVED_MAX then break end
		if type(e) == "table" and type(e[1]) == "number" and (lastSeq == nil or (tonumber(e[2]) or 0) > lastSeq) then
			out[#out + 1] = e[1]
			if e[3] == 1 then plan[e[1]] = true end
		end
	end
	return out, seq, plan
end

function M.newQueue()
	return { items = {}, byId = {} }
end

--- Adds node ids to the queue, due at `now`; a node already waiting starts again (a new build there). At most
-- NEW_QUEUE_MAX waiting. plan (optional): { [id] = true } for the ids that want the Smart Lanes phases look (the
-- entry's .plan; kept when the node is added again without it). Returns added, dropped.
function M.queueAdd(q, ids, now, plan)
	local added, dropped = 0, 0
	for i, id in ipairs(ids or {}) do
		if i > M.NEW_QUEUE_MAX then
			dropped = dropped + 1
		elseif type(id) == "number" then
			local it = q.byId[id]
			local wantPlan = type(plan) == "table" and plan[id] == true or nil
			if it ~= nil then
				it.at, it.t0, it.tries = now, now, 0
				it.plan = it.plan or wantPlan
			elseif #q.items >= M.NEW_QUEUE_MAX then
				dropped = dropped + 1
			else
				it = { n = id, at = now, t0 = now, tries = 0, plan = wantPlan }
				q.items[#q.items + 1] = it
				q.byId[id] = it
				added = added + 1
			end
		end
	end
	return added, dropped
end

--- Takes up to max entries due at `now` out of the queue (oldest added first).
function M.queueTake(q, now, max)
	local due, keep = {}, {}
	for _, it in ipairs(q.items) do
		if #due < max and now >= it.at then
			due[#due + 1] = it
			q.byId[it.n] = nil
		else
			keep[#keep + 1] = it
		end
	end
	q.items = keep
	return due
end

--- An entry taken whose node had no light yet back into the queue for its next look (NEW_RETRY_S after its first);
-- false when every look is used (given up) or the queue is full.
function M.queueRetry(q, it, now)
	it.tries = it.tries + 1
	if q.byId[it.n] ~= nil then return true end -- added again meanwhile (a new build there): waiting already
	local d = M.NEW_RETRY_S[it.tries]
	if d == nil or #q.items >= M.NEW_QUEUE_MAX then return false end
	it.at = math.max(now, it.t0 + d)
	q.items[#q.items + 1] = it
	q.byId[it.n] = it
	return true
end

function M.queueClear(q)
	q.items, q.byId = {}, {}
end

--- Drops the queued entries that do not want the phases look (all lights turned off: only the Smart lights looks
-- stay). Returns how many stay.
function M.queueKeepPlans(q)
	local keep, byId = {}, {}
	for _, it in ipairs(q.items) do
		if it.plan then
			keep[#keep + 1] = it
			byId[it.n] = it
		end
	end
	q.items, q.byId = keep, byId
	return #keep
end

---------------------------------------------------------------------------
-- The welcome: asked once per save

function M.newWelcome()
	return { phase = "wait", frames = 0, tries = 0 }
end

--- One GUI frame of the welcome's decision. readFn() -> readable (bool), answer (the saved wel or nil), editor (bool).
-- Returns the phase: "wait" (not decided yet), "show" (once: open the window now; then "shown"), "shown", "done"
-- (answered before, or the map editor: nothing to show) or "skip" (the state never became readable). The state is read
-- only at DELAY_FRAMES and every RETRY_FRAMES after, at most TRIES times.
function M.welcomeStep(w, readFn)
	if w.phase == "show" then w.phase = "shown" end
	if w.phase ~= "wait" then return w.phase end
	w.frames = w.frames + 1
	if w.frames < M.WELCOME_DELAY_FRAMES or (w.frames - M.WELCOME_DELAY_FRAMES) % M.WELCOME_RETRY_FRAMES ~= 0 then
		return "wait"
	end
	w.tries = w.tries + 1
	local ok, readable, answer, editor = pcall(readFn)
	if ok and editor then
		w.phase, w.reason = "done", "editor"
	elseif ok and readable then
		if answer ~= nil then w.phase, w.reason = "done", "answered" else w.phase = "show" end
	elseif w.tries >= M.WELCOME_TRIES then
		w.phase, w.reason = "skip", "unreadable"
	end
	return w.phase
end

--- The welcome's event payload (SmartLanes.auto op=welcome).
function M.welcomePayload(answer, lanes, lights)
	return { op = "welcome", src = "welcome", answer = answer == "apply" and "apply" or "later",
		lanes = lanes == true, lights = lights == true }
end

--- The welcome's answer applied to a game-script state table s (in place; the handler's part). Returns false (and
-- changes nothing) when s already holds an answer, else true and what changed: { mode = "all" | nil, pass = seq | nil }.
function M.applyWelcome(s, answer, lanes, lights)
	if s.wel ~= nil then return false, nil end
	local ch = {}
	s.wel = M.WEL[answer] or M.WEL.later
	if answer == "apply" and lights then
		s.amode = "all"
		s.aout = nil
		ch.mode = "all"
	end
	if answer == "apply" and lanes then
		local mp = type(s.mpass) == "table" and s.mpass or {}
		local seq = (tonumber(mp.seq) or 0) + 1
		s.mpass = { seq = seq, done = tonumber(mp.done) or 0 }
		ch.pass = seq
	end
	return true, ch
end

--- The existing-junctions pass's request in a state table s: the seq to run (requested and not finished) or nil.
function M.passWanted(s)
	local mp = type(s) == "table" and s.mpass or nil
	if type(mp) ~= "table" then return nil end
	local seq, done = tonumber(mp.seq), tonumber(mp.done) or 0
	if seq == nil or seq <= done then return nil end
	return seq
end

---------------------------------------------------------------------------
-- The existing-junctions pass: scanning in slices

--- A pass over `list` (node ids; nil: no list could be read): { seq, list, src, cursor, visited, slice, junctions,
-- scanned, slices, phase = "scan" | "done", reason }.
function M.newPass(seq, list, src)
	local p = { seq = seq, list = list or {}, src = src or "-", cursor = 1, visited = {}, slice = {}, junctions = 0,
		scanned = 0, slices = 0, phase = "scan", reason = nil, capped = nil }
	if list == nil then p.phase, p.reason = "done", "no_list" end
	return p
end

--- One frame of the scan: entries from the cursor while the frame's budget lasts (SCAN_PER_FRAME entries,
-- SCAN_BUDGET_MS of clockMs() checked every CHECK_EVERY entries). isJunction(n) -> bool (>= PASS_MIN_SEGS street
-- segments). Returns a full slice (a list of node ids, at most PASS_SLICE) or, at the end of the list or a cap, the
-- last partial one; nil while it is still filling. p.phase becomes "done" with p.reason "done" | "cap_list" |
-- "cap_junctions" (p.capped the same) once nothing is left to scan.
function M.passStep(p, isJunction, clockMs)
	if p.phase ~= "scan" then return nil end
	local t0 = clockMs and clockMs() or nil
	local n = #p.list
	local stopAt = math.min(n, M.PASS_LIST_MAX)
	local steps = 0
	local function finish(reason)
		p.phase, p.reason = "done", reason
		if reason ~= "done" then p.capped = reason end
		local s = p.slice
		p.slice = {}
		if #s > 0 then
			p.slices = p.slices + 1
			return s
		end
		return nil
	end
	while true do
		if p.cursor > stopAt then return finish(n > M.PASS_LIST_MAX and "cap_list" or "done") end
		if p.junctions >= M.PASS_JUNCTIONS_MAX then return finish("cap_junctions") end
		if steps >= M.PASS_SCAN_PER_FRAME then return nil end
		if t0 ~= nil and steps > 0 and steps % M.PASS_CHECK_EVERY == 0 and clockMs() - t0 >= M.PASS_SCAN_BUDGET_MS then
			return nil
		end
		local id = p.list[p.cursor]
		p.cursor = p.cursor + 1
		steps = steps + 1
		p.scanned = p.scanned + 1
		if type(id) == "number" and id >= 0 and not p.visited[id] then
			p.visited[id] = true
			local okJ, j = pcall(isJunction, id)
			if okJ and j == true then
				p.slice[#p.slice + 1] = id
				p.junctions = p.junctions + 1
				if #p.slice >= M.PASS_SLICE then
					local s = p.slice
					p.slice = {}
					p.slices = p.slices + 1
					return s
				end
			end
		end
	end
end

--- Breaks a display text into lines of at most `cols` columns with "\n" (the welcome window: sl_bg.script.lua line).
-- Columns: CJK and other wide glyphs count 2. Breaks at a space (dropped); a run with no space (ja / zh) breaks between
-- glyphs, never before closing punctuation. A word longer than cols stays whole on its own line. Existing "\n" kept.
-- Pure, UTF-8 aware; capped at 4000 bytes (longer text is returned as it is).
local CLOSING = { ["、"] = true, ["。"] = true, ["，"] = true, ["："] = true, ["）"] = true, ["」"] = true,
	["』"] = true, ["！"] = true, ["？"] = true, ["；"] = true, ["・"] = true }
--- Whether a UTF-8 glyph is a wide (East Asian) one: CJK, kana, Hangul, full-width forms.
local function wideGlyph(ch)
	if #ch ~= 3 then return false end
	local b1, b2, b3 = ch:byte(1, 3)
	local cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
	return (cp >= 0x1100 and cp <= 0x115F) or (cp >= 0x2E80 and cp <= 0xA4CF) or (cp >= 0xAC00 and cp <= 0xD7A3)
		or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFE30 and cp <= 0xFE4F) or (cp >= 0xFF00 and cp <= 0xFF60)
		or (cp >= 0xFFE0 and cp <= 0xFFE6)
end
function M.wrapLine(text, cols)
	if type(text) ~= "string" or #text > 4000 or type(cols) ~= "number" or cols < 4 then return text end
	local out = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		-- glyphs with their width
		local g = {}
		for ch in para:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			local w = wideGlyph(ch) and 2 or 1
			g[#g + 1] = { ch = ch, w = w, wide = w == 2 }
		end
		local lines, cur, curW, lastBreak = {}, {}, 0, nil
		local i = 1
		while i <= #g do
			local c = g[i]
			if curW + c.w > cols and #cur > 0 and c.ch ~= " " then
				-- break at the last space, else before this glyph (wide text; not before closing punctuation)
				local cut = lastBreak
				if cut == nil and c.wide and not CLOSING[c.ch] then cut = #cur + 1 end
				if cut == nil and c.wide and CLOSING[c.ch] and #cur > 1 then cut = #cur end
				if cut ~= nil then
					local head, rest = {}, {}
					for k = 1, #cur do
						if k < cut then head[#head + 1] = cur[k].ch
						elseif k > cut or cur[k].ch ~= " " then rest[#rest + 1] = cur[k] end
					end
					lines[#lines + 1] = table.concat(head)
					cur, curW, lastBreak = rest, 0, nil
					for k, r in ipairs(cur) do
						curW = curW + r.w
						if r.ch == " " then lastBreak = k end
					end
				end
			end
			cur[#cur + 1] = c
			curW = curW + c.w
			if c.ch == " " then lastBreak = #cur end
			i = i + 1
		end
		local tail = {}
		for _, r in ipairs(cur) do tail[#tail + 1] = r.ch end
		lines[#lines + 1] = table.concat(tail)
		out[#out + 1] = table.concat(lines, "\n")
	end
	return table.concat(out, "\n")
end

return M
