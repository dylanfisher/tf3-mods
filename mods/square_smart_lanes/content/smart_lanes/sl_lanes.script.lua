-- Smart Lanes game script functions (registered by sl_lanes.gs.lua). Phase 1: automatic roundabout
-- lanes. plans/square_smart_lanes/PLAN.md explains the design, TESTING.md the in-game checks.
--
-- Engine thread:
--   update      lazy subscription (once per load) to onPostBuildProposal and SmartLanes.zones (no lifecycle event reaches a mod added to
--               an old save); drops jobs nobody picked up (ttl), so the saved state stays empty.
--   handleEvent player builds that add street segments: the job's seeds (nodeConfigsToAdd, addedNodes and the
--               end nodes of addedSegments) go into a job in the game-script state, with the existing ones the
--               build did not change marked quiet (quietNodes: as many arms added as removed there, each with
--               the road it had; e.g. the far end of a stretch a road joined partway along, which the game
--               rebuilds as a replacement segment; none in a build that places or removes a street stop; PLAN.md
--               "Nearby junctions stay as they are"). Off a ring a quiet seed's lanes are not written (SKIP
--               reason=unchanged where the rule would change them; lanes already Smart Lanes': the same path as
--               before, its phases); on a ring it counts as not touched (the ring is still planned whole from it,
--               with the hand-edit guard there); its lights stay. Builds that only change node configs (our own
--               write, the Crossing Tool) are ignored, so we never loop. No sendCommand here: it asserts
--               !m_betweenChanges inside a build event (square_full_refund refund.script.tl:345-347).
--               While all lights are kept adjusted, every player build (config-only ones included) also saves the
--               nodes it touched as alit for the runtime's new-lights look (handleNewLights; also with Apply
--               automatically Off); with Light phases = Smart Lanes and Apply automatically On, a config-only build
--               (a light switched on) saves them with the phases look too (new lights get Smart lights).
-- GUI thread:
--   guiUpdate   picks up new jobs, finds one-way rings through the job's nodes (sl_ring), computes the
--               connections (sl_rules) and sends one node-config proposal per ring from the GUI thread;
--               a ring is planned whole (sl_rules autoSeeds, PLAN.md "Whole rings in the automatic pass"):
--               every arm junction is written, also those the build did not touch, so a ring gets the same
--               lanes (exit-only outer lane where it qualifies) whatever order its arms were built in; a
--               junction the build did not touch whose lanes are neither Smart Lanes' nor the engine's (a
--               Crossing Tool edit) keeps the ring at the build's nodes (matched lanes there: SKIP
--               reason=hand_edit); one the job would add that a proposal of ours still names makes the job
--               wait (WAIT kind=ring, once per ring) and read it again in a later frame;
--               then the job's other nodes that are slip-lane junctions (sl_slip: diverge / merge of a
--               slip lane, splitter leg or ramp) get the slip rule, in one proposal per frame
--               with a callback (the pattern of .cache/subscribed/undo_tf3_test/content/undo/
--               tool_probe.script.lua:118-135; a callback from the engine update fails, docs/findings.md).
--               A job runs in steps over several frames (stepJob, PERF_REVIEW.md 2026-10-12): each frame
--               reads a fresh world, takes nodes one per step (ring search with its ring's proposal,
--               classification with the node's entry, audit) until BUDGET_MS of Clock time is used, then
--               sends that frame's slip entries in one proposal. A node's plan and entry come from the reads
--               of one frame, a ring's junctions go in one proposal, each node in one proposal of the job.
--               One job at a time: build events meanwhile wait in pending (a waiting job sharing a node
--               with a newer one takes it in: SUMMARY merged=). The job's lines are those of a job done
--               in one frame (one WRITE kind=slip / VERIFY for all its parts); verifies, re-checks and
--               lights-off proposals are spread over frames the same way.
--
-- The read / write path (live world, current connections, LaneConnection construction, the
-- proposal) is sl_write.lua, shared with the Phase 2 road tool (sl_tool.script.lua).
--
-- Game-script state (saved with the game, tiny and normally empty): { seq = n, jobs = { {seq, ttl, nodes, quiet} },
-- zones = { {x, y, r, ab} } (at most 400), zrun = run id, zseq = n } (zones: sl_zones.lua); for the Stress Test bench
-- (plans/square_stress_test/BENCH.md SL-4 / SL-5) also zmodes = accepted zone modes and zerr = { run, reason } of the
-- last refused payload (both written on zones events only), qlen / qgui / qseen = Smart Lanes' queue length (only
-- while zones are set: our GUI reports it with the SmartLanes.qlen event); kept = { {n, x, y} } (at most 2000) and
-- kseq = n: the nodes the tool's Reset kept (sl_kept.lua; written from the first Reset on only); auto = { {n, x, y} }
-- (at most 1000), aseq, aall, areq, arun: the junctions whose timing is kept adjusted, and rlast = { {n, x, y, t, k,
-- c0, c1, d} } (at most 1000), lseq: the last measurement of each junction either Re-time mode measured (sl_auto.lua,
-- RETIME_PLAN.md "Step B v4"; each written from its first use on only, events SmartLanes.auto); amode, aout (at most
-- 1000), wel, mpass, alit: "Automatic light timing" and the first-load welcome (sl_allmode.lua; SmartLanes.auto ops mode /
-- welcome / pass; WELCOME op=answer|ignored, AUTORETIME op=mode|optout|optin|optout_drop|new_lights); sset, sseq: this save's
-- in-game settings (sl_settings.lua; SmartLanes.auto op=setting; SETTINGS op=set key= value= param= src= seq=; the GUI
-- state below re-derives its settings when they change and logs MODE ... src=save); trec (at most 1000), tseq: the
-- last traffic recording of each junction / roundabout (sl_record.lua; SmartLanes.auto op=traffic, from the tool's
-- first saved recording on only).
-- The existing-junctions pass (the welcome's Apply with its lanes box ticked; mapPassStep below): MAPPASS lines, its
-- slices go through the automatic pass as jobs "m<n>" (rings whole, slips, crossroads, T-junctions; kept nodes,
-- rings with a hand-edited junction (SKIP reason=hand_edit) and crossroads / T-junctions whose lanes are not the
-- game's (hand_edit) or whose phases are flagged user-modified (hand_timed) are left alone; no lights switched).
-- Exports through data(): a .script.lua that returns a table fails in game ("Expected table at path").
-- Log lines start with [SQRL]: one APPLY line per changed node, SKIP for ring nodes left alone,
-- WRITE / VERIFY per ring, ERROR (at most 20 per session). Slip nodes: APPLY / SKIP / WRITE /
-- VERIFY with kind=slip (SKIP only for slip candidates that do not fit, not for every plain node).
-- Plain nodes where a road gains or drops a lane (sl_slip case "D", PHASE7.md step 2) go the same way
-- with APPLY / SKIP kind=drop, in the slip proposal; they keep their traffic lights.
-- SUMMARY (PHASE7.md step 6): one line per processed job that handled a ring or a candidate node:
--   job= nodes= rings= ring=applied/same/skipped slip= cross= drop= same= skip= skips=reason:count,...
-- AUDIT (sl_audit.lua, TESTING.md X): after the proposals are sent, the job's handled junctions (ring arm
-- junctions and slip / crossing / drop nodes planned apply or same) are audited with the connections just
-- planned: one line per junction with avoidable findings
--   AUDIT node= case= shape= findings=kind:n,... [forced=kind:n,...] detail=.. src=auto job=..
-- (forced kinds: squeeze, shared, weave the lane counts force; shared_lit, turbo_gap by design)
-- (at most Audit.MAX_LINES per job; unlogged= in the summary counts the rest)
-- and one AUDIT_SUMMARY src=auto job= audited= flagged= findings= forced= [unlogged=] skips= per job that logged a
-- SUMMARY. Always on (no setting): quiet junctions log nothing, and the audit reads no more than the plan
-- did (weave looks only at junctions of the same job). Errors are logged (ERROR where=audit), never thrown.
-- Traffic lights ("No lights at roundabouts and ramps", sl_lights.lua): the ring's arm junctions the job
-- seeded (not those the whole-ring plan adds; a ring layout variant zone: all) and the slip
-- nodes are set to no lights after their lane write answered (right away when the lanes were
-- already right): one LIGHTS line per node sent, VERIFY kind=lights.
-- Free kerb turn ("Free kerb turn at traffic lights", sl_lights.lua L.kerbPhases; Off / When safe /
-- Always): crossroads and T-junctions (case X) written by the slip proposal get their kerb turns
-- freed in that same proposal (W.sendConfigs item.phase): When safe only in the phases where
-- nothing green crosses and no crosswalk is green (Lights.SAFE; merges allowed), Always in every phase (Lights.FREE); one whose lanes are
-- already right gets a phases-only light proposal (W.kerbLights, LIGHTS src=auto to=free_turn).
-- SUMMARY free_turn=<kerb connections freed in at least one phase> free_phases=<(kerb connection,
-- phase) unlocks> [kept=cross:n,ped:n: pairs When safe kept red (merges are allowed since 2026-10-12, so
-- no merge:n) merge_free=<pairs freed while a green stream ends in the same lane>] shared_held=<kerb
-- connections not freed because their entry lane also carries another movement (Lights.sharedKerb)>
-- (free_turn=off: Off).
-- A node whose light state was unknown at the read (AUTO, no light yet: Lights.litOf nil)
-- is read again RECHECK_FRAMES after the write: when the game made phases since that lock a kerb turn
-- (lights that came later, or phases re-made), they are freed then (LIGHTS src=recheck), logged as
-- RECHECK kind=free_turn job= nodes= phases=<nodes with phases> locked=<nodes with a kerb turn red in
-- some phase (When safe: also the phases it conflicts in; then W.kerbLights sends nothing)>
-- sent=<proposals> changed=<nodes whose lanes are no longer ours: left alone>.
-- Light phases ("Light phases", sqrl_light_phases; PHASES_PLAN.md step 4): Game default (the default)
-- changes nothing above. Smart Lanes: a lit crossroads / T-junction (case X, X.litOf true) written by the
-- slip proposal gets a Smart Lanes phase plan (sl_phaseplan.lua) from its final connections and
-- crosswalks in that same proposal (W.sendConfigs item.lightPlan; one PHASES line per node: plan= or
-- plan_fail=); the free kerb turn is not applied on top. No valid plan: the free kerb turn and the
-- plain re-pointing as before (plan_fail= says why). Lanes already right: a phases-only light proposal
-- (W.planLights, LIGHTS src=auto to=sl_phases plan=..), never while a write on the node is pending;
-- a failed plan falls back to the free kerb turn there too. Unknown light at the read: the re-checks
-- above write the plan once a light stands and the lanes are still ours (LIGHTS src=recheck;
-- RECHECK kind=phases job= nodes= phases= sent= same= fail= changed=).
-- SUMMARY gets phases=game|sl and, for sl, sl_plans=<nodes whose plan was sent> plan_fail=<reason:count>.
-- MODE phases=game|sl free_turn=off|safe|always: once per load (GUI state init), so a traffic report
-- can tell the settings of the run (plans/square_stress_test/FLOW.md).
-- Zones (sl_zones.lua; FLOW.md "[SQRL] ZONES"): another mod's GUI sends "SmartLanes.zones"
-- (makeScriptingSendEventCmd, id "square_smart_lanes") with circles marked game / sl / sl_phases / sl_fan /
-- sl_lock; handleEvent validates and stores them: ZONES op=set|clear n= run=
-- by_ab=game:a,sl:b,sl_phases:c[,sl_fan:d][,sl_lock:e] (the last two only when non-zero; ZONES op=ignored
-- reason= for a bad payload, at most 20 per session). The GUI state mirrors them (re-read only when zseq
-- changed) and logs ZONES op=loaded n= run= once per load. In the automatic pass a game zone's nodes are
-- left alone (one SKIP kind=zone zone=game job= nodes= reason=zone_game per job; a ring with any node in one:
-- SKIP ring= node= reason=zone_game; skips=zone_game:n in SUMMARY); an sl_phases zone's crossroads /
-- T-junctions get the Smart Lanes phase plan as with Light phases = Smart Lanes (SUMMARY zone_phases=<nodes>
-- when the setting is Game default). Where no axis plan can be made (other shapes, a lane without a road phase:
-- PLAN.md "No classic fallback") the junction keeps the game's phases, re-pointed onto the new lanes with the free
-- curb turn as set (PHASES ... pattern=none plan_fail=no_axis_shape|axis_extra|invalid_..). An sl_fan
-- zone (PHASES_PLAN.md "Fan mode", a measuring mode): a lit
-- crossroads / T-junction gets the full fan (every entry lane to every exit lane of every other arm,
-- Slip.plan opts.fan) and the fan phase plan (one approach per phase) in ONE proposal (APPLY ... mode=fan,
-- PHASES ... plan=x4_fan|t3_fan|fan ..); a fan whose plan fails is not written (SKIP reason=lights:fan_..).
-- Unlit nodes there keep the rule (APPLY ... fan=unlit), as in an sl_phases zone; a node whose light is
-- unknown at the read gets the rule and the re-checks: once a light stands and the lanes are still ours,
-- the fan and its plan go out in one proposal (APPLY src=recheck ... mode=fan; RECHECK kind=phases counts
-- it as sent). Fan nodes are not audited (their crossings are by design). SUMMARY zone_fan=<crossroads /
-- T-junctions of the job in sl_fan zones (fan, or the rule while unlit)>. An sl_lock zone (a measuring mode:
-- sl vs sl_lock is the free kerb turn alone): Smart Lanes lanes as in an sl zone, but its crossroads /
-- T-junctions keep the game's light phases and their kerb turns locked whatever "Free kerb turn" and "Light
-- phases" say: the lane write carries phase mode Lights.LOCK (as the tool's Reset), so a kerb turn freed
-- earlier is locked back with its approach; lanes already right: a phases-only lock (W.kerbLights LOCK,
-- LIGHTS src=auto to=lock_turn, sent only when a kerb turn is green somewhere). Their APPLY and AUDIT lines
-- end in zone=sl_lock free_turn=off; SUMMARY zone_lock=<those nodes> lock_turn=<kerb connections locked
-- back> lock_phases=<(connection, phase) locks> (free_turn= never counts them). No re-check after the
-- write (phases the game makes later lock the kerb turn), but a node busy at the read is locked by the
-- re-check. The subscriptions are saved with the game: they are made again once
-- per load (findings "Game-script event subscriptions are saved"), the zones and kept events also with Apply
-- automatically Off (the tool reads them too), nothing in the map editor.
-- Kept nodes (sl_kept.lua, PLAN.md "Reset sticks", rev 7): the tool sends "SmartLanes.kept" { op = add | remove,
-- nodes = { {n, x, y} } } when the player Resets (add) or Applies (remove) junctions; handleEvent validates and
-- stores them (KEPT op=add|remove n= total= src=, KEPT op=dropped n= at the cap, KEPT op=ignored reason=). The GUI
-- state mirrors them (re-read only when kseq changed). In the automatic pass a kept node (matched by id or within
-- 1 m) is left alone as a game-zone node: one SKIP kind=kept job= nodes= reason=reset_kept per job, a ring with a
-- kept node: SKIP ring= node= reason=reset_kept; skips=reset_kept:n in SUMMARY. At load, entries whose node is
-- gone are pruned (KEPT op=remove src=prune).
--
-- SQPERF (plans/sqperf/README.md): this file loads in the engine Lua states and the GUI one.
-- Instrument `perf` (ctx gs): load time of the state (phase=init), sections update and event;
-- `perfGui` (ctx gui), per frame: gui_update with job_step (one frame's share of the job in progress)
-- and verify (one frame's share of the verifies and re-checks) nested; counters job_nodes and job_frames
-- (frames per job = job_frames / jobs). `perfJob` (ctx gui_job), one call per job, the sums of its
-- frames' work (not frame time, so never slow lines): job, and inside it (PHASE7.md step 7) job_ring (ring
-- search at every job node, ring plans, their proposals), job_classify (Slip.plan of the other nodes:
-- classification with its walks), job_write (the proposals: each node's entry, its config read, light
-- phases, the sends), job_audit (the AUDIT lines, sl_audit.lua). Slow calls are always logged; the
-- "Debug: performance log" setting (sqperf_log) adds a 30 s summary. Local counters only.

local sqperf = ug_require "square_smart_lanes::/sqperf/square_smart_lanes.lua"
local perf = sqperf.new({ mod = "square_smart_lanes", ctx = "gs", paramKey = "sqperf_log", first = { "update" } })
local perfGui = sqperf.new({ mod = "square_smart_lanes", ctx = "gui", paramKey = "sqperf_log", first = { "gui_update" } })
-- per-job sums of work spread over frames (job, job_ring, job_classify, job_write, job_audit): not frame time,
-- so never "slow" lines (a stall shows as job_step / gui_update in perfGui)
local perfJob = sqperf.new({ mod = "square_smart_lanes", ctx = "gui_job", paramKey = "sqperf_log", slowMs = math.huge })
local perfInit = perf:start()

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Lights = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"
local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
local Split = ug_require "square_smart_lanes::/smart_lanes/sl_split.lua"
local Kept = ug_require "square_smart_lanes::/smart_lanes/sl_kept.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"
local Retime = ug_require "square_smart_lanes::/smart_lanes/sl_retime.lua"
local Rec = ug_require "square_smart_lanes::/smart_lanes/sl_record.lua"

local EV_POST = "onPostBuildProposal"
-- SL-5 (plans/square_stress_test/BENCH.md): our own GUI state reports its queue length to the game-script state
local EV_QLEN = "SmartLanes.qlen"
local QLEN_EVERY = 30 -- GUI frames between two reports at most once (a change waits for it)
local MAX_JOBS = 3
local MAX_SEEDS = 160      -- nodes per job
local JOB_TTL = 300        -- engine updates a job stays in the state
local JOB_SWEEP = 100      -- engine updates between reads of the state (expiring jobs: they live JOB_TTL..+JOB_SWEEP)
local JOB_POLL = 5         -- GUI frames between reads of the state (new jobs)
local JOB_DELAY = 10       -- GUI frames after a job appears before it is processed
local VERIFY_DELAY = 30    -- GUI frames after a write before the nodes are re-read
local LIGHTS_LATE_FRAMES = 600 -- SL-6: one late look at the lights of every lights-off entry, this long after it
local RECHECK_FRAMES = { 60, 600 } -- free kerb turn: GUI frames after the write when unknown-lit nodes are read again
local MAX_RECHECK = 64     -- nodes per job re-checked
local INFLIGHT_TIMEOUT = 600 -- GUI frames after which an unanswered proposal no longer holds its nodes (busyNode)
-- Frame budget (PERF_REVIEW.md 2026-10-12): a job runs in steps over several GUI frames, one node per step
-- (ring search and its ring's proposal, or classification and the node's entry, or its audit), until the
-- frame has used BUDGET_MS (Clock time; a step starts only when its running average still fits), then the
-- frame's entries go out in one proposal. Verifies share the budget the same way (one node per step).
-- A refused part of 2+ entries is sent again entry by entry from fresh reads (retryStep; RETRY lines, WRITE
-- retry=<queued> retry_ok=<landed>), each once, its nodes held until then (PERF_REVIEW.md 2026-10-12 "Open").
-- A slip part or retry whose callback has not come INFLIGHT_TIMEOUT frames after its send is given up
-- (expireWaits, at the top of guiBody, before heldNode's own timeout): its nodes are released, one
-- TIMEOUT kind=slip job= parts= retries= entries= line per job, RETRY result=timeout per retry, and the
-- job's WRITE line (timeout=<entries>) with its verify, re-checks and lights-off runs for what landed
-- (timed-out nodes are neither verified, re-checked nor relit). A callback after that is ignored
-- (one LATE kind=slip job= nodes= success= line; nothing released or counted twice).
local BUDGET_MS = 8
local STEP_EST_MS = 0.5    -- the first guess of a step's cost (then a running average per kind of step)

-- SL-3 (plans/square_stress_test/BENCH.md): zid=<zone id> on the lines of nodes in a zone (set below, once G exists)
local zidHook = nil
local function out(kind, fields)
	if zidHook ~= nil then pcall(zidHook, kind, fields) end
	local text = Rules.line(kind, fields)
	if log and log.message then log.message(text) else print(text) end
end

local errors = 0
local function err(where, e)
	errors = errors + 1
	if errors > 20 then return end -- a per-frame error must not flood stdout.txt
	out("ERROR", { { "where", where }, { "err", e } })
end

local function count(list)
	if list == nil then return 0 end
	local n = 0
	for _ in ipairs(list) do n = n + 1 end
	return n
end

local function modParams()
	local ok, all = pcall(api.engine.config.getModParams)
	if ok and type(all) == "table" then return all[Rules.MOD_ID], all end
	return nil, nil
end

--- The settings in force: the mod params with this save's in-game overrides (sl_settings.lua: the mirror of this Lua
-- state, set from the saved state by guiBody; the engine Lua states never set it and use the mod params, they read
-- only Apply automatically and Automatic light timing, which the panel does not override this way).
local function settings()
	local raw, all = modParams()
	local cfg = Rules.fromModParams(Settings.merged(raw, Settings.overNow()))
	local g = all and all[""]
	cfg.mapEditor = type(g) == "table" and g.isMapEditor == true
	cfg.active = cfg.auto and cfg.ring ~= "game" and not cfg.mapEditor
	-- "Automatic light timing" (sl_allmode.lua): "pick" (Junctions I choose) | "all" (All lights) | "off" (Off)
	cfg.autoLights = AllMode.settingOf(raw)
	return cfg
end

---------------------------------------------------------------------------
-- Engine thread

-- subscribed: this Lua state made the subscriptions in this load (module-local, so every load and every
-- simulation Lua state starts false and subscribes once more; idempotent). Subscriptions are saved with the
-- game: a save from before the zones event knows only onPostBuildProposal (square_problem_radar's
-- ensureSubscribed, radar.script.tl:1346-1380).
local E = { cfg = nil, ticks = 0, subscribed = false }

-- onPostBuildProposal is subscribed also with Apply automatically Off (handleBuild returns at once then): the new
-- lights' look (handleNewLights) runs whatever Apply automatically says. Before 2026-10-16 it was subscribed only with
-- Apply automatically On, so with it Off the new-lights path never fired (subscribeToNoEvents drops the rest).
local function ensureSubscribed(state, active)
	if E.subscribed and state:hasEventSubscriptions() then return end
	state:subscribeToNoEvents()
	state:subscribeToEvent(Zones.EV_ZONES)
	state:subscribeToEvent(Kept.EV_KEPT)
	state:subscribeToEvent(Auto.EV_AUTO)
	state:subscribeToEvent(EV_POST)
	if active then
		state:subscribeToEvent(EV_QLEN)
	end
	E.subscribed = true
end

--- SL-4: the zone modes this Smart Lanes accepts (Zones.AB), as stored in the state's zmodes.
local function zmodesList()
	local l = {}
	for i, ab in ipairs(Zones.AB) do l[i] = ab end
	return l
end

--- SL-5: qlen = the GUI's last reported queue (qgui) + the jobs it had not seen then (seq > qseen).
local function setQlen(s)
	local n, seen = 0, s.qseen
	for _, j in ipairs(s.jobs or {}) do
		if seen == nil or (type(j.seq) == "number" and j.seq > seen) then n = n + 1 end
	end
	s.qlen = (s.qgui or 0) + n
end

local function doUpdate(state)
	if E.cfg == nil then E.cfg = settings() end
	if E.cfg.mapEditor then return end
	ensureSubscribed(state, E.cfg.active)

	if not E.cfg.active then return end
	-- the state is read every JOB_SWEEP updates only (handleEvent runs in another Lua state, so
	-- there is no flag to tell whether a job was added; findings.md "separate Lua states")
	E.ticks = E.ticks + 1
	if E.ticks % JOB_SWEEP ~= 0 then return end
	local s = state:get()
	if type(s) == "table" and s.jobs and #s.jobs > 0 then
		local keep = {}
		for _, j in ipairs(s.jobs) do
			j.ttl = (j.ttl or 0) - JOB_SWEEP
			if j.ttl > 0 then keep[#keep + 1] = j end
		end
		s.jobs = keep
		if s.qlen ~= nil then setQlen(s) end
		state:set(s)
	end
end

--- An arm's road as seen from its end node n (quietNodes): the edge type and street type (typeIndex), then each lane
-- from n's side (o leaving n, i arriving) with its transport modes, so a replacement drawn the other way gives the same
-- key. nil when the segment cannot be read (the node then counts as changed).
local function armKey(sg, n)
	local parts = {}
	local ok = pcall(function()
		local c = sg.comp
		parts[1] = tostring(sg.type) .. "/" .. tostring(c.typeIndex)
		local list = {}
		for _, lc in ipairs(c.laneConfigs or {}) do
			local modes = {}
			for k, v in pairs(lc.transportModes or {}) do
				if v then modes[#modes + 1] = tostring(k) end
			end
			table.sort(modes)
			list[#list + 1] = { fwd = lc.forward == true, m = table.concat(modes, "+") }
		end
		local at1 = c.node1 == n and c.node0 ~= n
		local from, to, step = 1, #list, 1
		if at1 then from, to, step = #list, 1, -1 end
		for i = from, to, step do
			parts[#parts + 1] = ((list[i].fwd ~= at1) and "o" or "i") .. list[i].m
		end
	end)
	if not ok then return nil end
	return table.concat(parts, ",")
end

--- The existing nodes among `seeds` the build did not change (PLAN.md "Nearby junctions stay as they are"): not added
-- by it, as many arms added as removed there (addedSegments vs removedSegments end nodes), each arm with the road it
-- had (armKey). A road joined partway along a street replaces that stretch, so its far end (an existing junction) gets
-- a replacement segment and nothing else; the engine keeps that junction's config, re-pointed (docs/findings/roads.md
-- "A replaced arm keeps the junction's lanes"). A build that places or removes a street stop (edge objects on its
-- added vs removed segments; the stop rebuilds its road piece) has none: the stop opens or closes exit lanes there
-- (PLAN.md "Open exit lanes near stops and close junctions"). Returns the list (in seed order) or nil when there is none.
local function quietNodes(sp, seeds)
	local new, arms, objects = {}, {}, 0
	for _, n in ipairs(sp.addedNodes or {}) do
		if type(n.entity) == "number" then new[n.entity] = true end
	end
	local function tally(list, d)
		for _, sg in ipairs(list or {}) do
			local c = sg.comp
			if c then
				local okO, nO = pcall(function() return count(c.objects) end)
				objects = objects + d * (okO and nO or 0)
				for _, n in ipairs({ c.node0, c.node1 }) do
					if type(n) == "number" and n >= 0 then
						local a = arms[n] or { n = 0, k = {} }
						arms[n] = a
						a.n = a.n + d
						local key = armKey(sg, n)
						if key == nil then a.bad = true else a.k[key] = (a.k[key] or 0) + d end
					end
				end
			end
		end
	end
	tally(sp.addedSegments, 1)
	tally(sp.removedSegments, -1)
	if objects ~= 0 then return nil end
	local out = {}
	for _, n in ipairs(seeds) do
		local a = arms[n]
		local same = not new[n] and (a == nil or (a.n == 0 and not a.bad))
		if same and a ~= nil then
			for _, d in pairs(a.k) do
				if d ~= 0 then
					same = false
					break
				end
			end
		end
		if same then out[#out + 1] = n end
	end
	return #out > 0 and out or nil
end

local function handleBuild(state, p)
	if type(p) ~= "table" or p[4] ~= true then return end -- player builds only
	local proposal = p[1]
	local sp = proposal and proposal.proposal
	if sp == nil or count(sp.addedSegments) == 0 then return end
	local seeds, seen = {}, {}
	local function add(id)
		if type(id) == "number" and id >= 0 and not seen[id] and #seeds < MAX_SEEDS then
			seen[id] = true
			seeds[#seeds + 1] = id
		end
	end
	for _, e in ipairs(sp.nodeConfigsToAdd or {}) do add(e.entity) end
	for _, n in ipairs(sp.addedNodes or {}) do add(n.entity) end
	for _, sg in ipairs(sp.addedSegments or {}) do
		local c = sg.comp
		if c then
			add(c.node0)
			add(c.node1)
		end
	end
	if #seeds == 0 then return end
	local s = state:get() or {}
	s.seq = (s.seq or 0) + 1
	s.jobs = s.jobs or {}
	s.jobs[#s.jobs + 1] = { seq = s.seq, ttl = JOB_TTL, nodes = seeds, quiet = quietNodes(sp, seeds) }
	while #s.jobs > MAX_JOBS do table.remove(s.jobs, 1) end
	-- SL-5 only while zones are set (or a qlen was reported): an ordinary save's state gets nothing new
	if s.zones ~= nil or s.qlen ~= nil then setQlen(s) end
	state:set(s)
	perf:count("jobs")
end

local zoneNotes = 0

--- "SmartLanes.zones" (sl_zones.lua): validated, then stored (set replaces, clear removes); the state
-- keeps only the cleaned list, never the raw payload.
local function handleZones(state, param)
	local op, list, run = Zones.validate(param)
	if op == nil then
		zoneNotes = zoneNotes + 1
		if zoneNotes <= 20 then out("ZONES", { { "op", "ignored" }, { "reason", list } }) end
		-- SL-4: the refused payload's run (when it is a valid run id, else "-") and the reason
		local okR, r = pcall(function() return type(param) == "table" and Zones.runOf(param.run) or nil end)
		local s = state:get() or {}
		s.zerr = { run = (okR and r) or "-", reason = tostring(list) }
		s.zmodes = zmodesList()
		state:set(s)
		return
	end
	local s = state:get() or {}
	s.zmodes = zmodesList()
	s.zones = (op == "set" and #list > 0) and list or nil
	s.zrun = run
	s.zseq = (s.zseq or 0) + 1
	state:set(s)
	out("ZONES", { { "op", op }, { "n", #list }, { "run", run }, { "by_ab", Zones.byAbText(list) } })
end

local keptNotes = 0

--- "SmartLanes.kept" (sl_kept.lua, rev 7 "Reset sticks"): validated, then applied to the saved list (add / remove
-- by id or position, cap Kept.MAX with the oldest dropped). An event that changes nothing writes nothing (a save
-- that never used Reset gets no `kept`). KEPT op=add|remove n=<nodes in the event> total=<entries> src=..;
-- KEPT op=dropped n= when the cap dropped old entries; KEPT op=ignored reason= for a bad payload (20 per session).
local function handleKept(state, param)
	local op, nodes, src = Kept.validate(param)
	if op == nil then
		keptNotes = keptNotes + 1
		if keptNotes <= 20 then out("KEPT", { { "op", "ignored" }, { "reason", nodes } }) end
		return
	end
	local s = state:get() or {}
	local list, st = Kept.apply(s.kept, op, nodes)
	if op == "remove" and st.removed == 0 then return end
	s.kept = #list > 0 and list or nil
	s.kseq = (s.kseq or 0) + 1
	state:set(s)
	out("KEPT", { { "op", op }, { "n", #nodes }, { "total", #list }, { "src", src } })
	if st.dropped > 0 then out("KEPT", { { "op", "dropped" }, { "n", st.dropped }, { "total", #list } }) end
end

local autoNotes, autoLines = 0, 0
local AUTO_LINES_MAX = 2000
local newLines = 0
local NEW_LINES_MAX = 200

--- An AUTORETIME line of the handler (at most AUTO_LINES_MAX per session in this Lua state), with zid= of the zone
-- the position lies in (from the saved zones: this engine Lua state has no zones mirror).
local function autoLine(s, fields, x, y)
	if autoLines >= AUTO_LINES_MAX then return end
	autoLines = autoLines + 1
	if autoLines == AUTO_LINES_MAX then fields[#fields + 1] = { "more", "suppressed" } end
	if x ~= nil and type(s.zones) == "table" and #s.zones > 0 then
		local id = Zones.idOf(Zones.zoneAt(s.zones, x, y))
		if id ~= nil then fields[#fields + 1] = { "zid", id } end
	end
	out("AUTORETIME", fields)
end

--- All lights, new lights at once (sl_allmode.lua "New lights at once", PLAN.md "New lights at once"): a player
-- build (streets placed by hand or by a tool, a Crossing Tool click, our own writes too: all are player-initiated)
-- while all lights are kept adjusted saves the nodes it touched (nodeConfigsToAdd / nodeConfigsToRemove, added nodes,
-- the added segments' ends; at most AllMode.NEW_SEEDS_MAX), without those enrolled or opted out by id, as alit (aseq
-- +1); the runtime (sl_autoretime.lua) looks at them at once and enrolls the lit ones (SmartLanes.auto add src=build).
-- Independent of "Apply automatically to new roads". AUTORETIME op=new_lights phase=queued src=build nodes= segs=
-- cfgs= plan=0|1 (at most NEW_LINES_MAX per session).
-- New lights get Smart lights (sl_allmode.lua, PLAN.md "New lights get Smart lights"): a config-only build (no added
-- streets: a light switched on in the Crossing Tool / node window, also our own writes) while Light phases is Smart
-- Lanes (the setting, this save's in-game setting sset.phases, or a saved sl_phases / sl_auto zone) and Apply
-- automatically is On saves its nodes with the phases look (plan=1), also without all lights and enrolled ones
-- included; the runtime decides per node (only the game's own default phases get the plan).
local PLAN_ZONES = { sl_phases = true, sl_auto = true }
local function phasesLookWanted(s0, sp)
	if not E.cfg.active or count(sp.addedSegments) > 0 then return false end
	local over = type(s0) == "table" and Settings.clean(s0.sset) or nil
	local ph = E.cfg.phases
	if over ~= nil and over.phases ~= nil then ph = over.phases == 2 and "sl" or "game" end
	if ph == "sl" then return true end
	for i, z in ipairs(type(s0) == "table" and type(s0.zones) == "table" and s0.zones or {}) do
		if i > Zones.MAX then break end
		if type(z) == "table" and PLAN_ZONES[z.ab] then return true end
	end
	return false
end

local function handleNewLights(state, p)
	if type(p) ~= "table" or p[4] ~= true then return end -- player builds only
	local proposal = p[1]
	local sp = proposal and proposal.proposal
	if sp == nil then return end
	local s0 = state:get()
	local amode = type(s0) == "table" and s0.amode or nil
	local allOn = AllMode.effective(E.cfg.autoLights, amode) == "all"
	local plan = phasesLookWanted(s0, sp)
	if not allOn and not plan then return end
	local skip = {}
	-- the phases look takes enrolled and opted-out nodes too (the runtime skips their enrollment)
	if type(s0) == "table" and not plan then
		for i, e in ipairs(type(s0.auto) == "table" and s0.auto or {}) do
			if i > Auto.MAX then break end
			if type(e) == "table" and e[1] ~= nil then skip[e[1]] = true end
		end
		for i, e in ipairs(type(s0.aout) == "table" and s0.aout or {}) do
			if i > AllMode.OUT_MAX then break end
			if type(e) == "table" and e[1] ~= nil then skip[e[1]] = true end
		end
	end
	local ids, seen = {}, {}
	local function add(id)
		if type(id) == "number" and id >= 0 and not seen[id] and not skip[id] and #ids < AllMode.NEW_SEEDS_MAX then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	for _, e in ipairs(sp.nodeConfigsToAdd or {}) do add(e.entity) end
	for _, n in ipairs(sp.nodeConfigsToRemove or {}) do add(n) end
	for _, n in ipairs(sp.addedNodes or {}) do add(n.entity) end
	for _, sg in ipairs(sp.addedSegments or {}) do
		local c = sg.comp
		if c then
			add(c.node0)
			add(c.node1)
		end
	end
	if #ids == 0 then return end
	local s = type(s0) == "table" and s0 or {}
	local alit, added = AllMode.litAdd(s.alit, ids, plan)
	if added == 0 then return end
	s.alit = alit
	s.aseq = (s.aseq or 0) + 1
	state:set(s)
	if newLines < NEW_LINES_MAX then
		newLines = newLines + 1
		local f = { { "op", "new_lights" }, { "phase", "queued" }, { "src", "build" }, { "nodes", added },
			{ "segs", count(sp.addedSegments) }, { "cfgs", count(sp.nodeConfigsToAdd) }, { "plan", plan and 1 or 0 } }
		if newLines == NEW_LINES_MAX then f[#f + 1] = { "more", "suppressed" } end
		out("AUTORETIME", f)
	end
end

--- "SmartLanes.auto" (sl_auto.lua, RETIME_PLAN.md "Step B": Keep timing adjusted): validated, then stored. add /
-- remove / update change the list (aseq +1 when anything changed), now stores areq, all stores aall (the GUI runtime
-- answers it), clear empties the list; all / clear store arun. Lines: AUTORETIME op=enroll|unenroll node= pos= src=
-- total= [zid=] per node; op=refuse reason=cap node= pos= src= total= (the cap, Auto.MAX); op=now node= pos=;
-- op=enroll_all phase=request run= src=; op=unenroll all=1 n= run= src= (clear); op=ignored reason= (bad payload,
-- 20 per session). An update (re-attach) and last (records: rlast, lseq) log nothing (the runtime and the tool log
-- their decisions). Writes nothing for a change of nothing.
local function handleAuto(state, param)
	local op, nodes, src, run, extra = Auto.validate(param)
	if op == nil then
		autoNotes = autoNotes + 1
		if autoNotes <= 20 then out("AUTORETIME", { { "op", "ignored" }, { "reason", nodes } }) end
		return
	end
	local s = state:get() or {}
	-- "Automatic light timing" (sl_allmode.lua, PLAN.md "Automatic timing for all lights + first-load welcome")
	if op == "welcome" then
		local okW, ch = AllMode.applyWelcome(s, extra.answer, extra.lanes, extra.lights)
		if not okW then
			out("WELCOME", { { "op", "ignored" }, { "reason", "answered" }, { "answer", extra.answer } })
			return
		end
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
		out("WELCOME", { { "op", "answer" }, { "answer", extra.answer }, { "lanes", extra.lanes and 1 or 0 },
			{ "lights", extra.lights and 1 or 0 }, { "mode", ch.mode or "-" }, { "pass", ch.pass or "-" } })
		return
	end
	if op == "mode" then
		local n = type(s.auto) == "table" and #s.auto or 0
		local outs = type(s.aout) == "table" and #s.aout or 0
		-- pick stops what all lights enrolled; off only pauses (the list and the opt-outs stay for the next mode)
		local was = AllMode.effective(E.cfg and E.cfg.autoLights, s.amode)
		s.amode = extra.mode
		if extra.mode == "off" then outs = 0 else s.aout = nil end
		if extra.mode == "pick" and was == "all" then s.auto = nil else n = 0 end
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
		autoLine(s, { { "op", "mode" }, { "mode", extra.mode }, { "src", src }, { "unenrolled", n }, { "optouts_cleared", outs } })
		return
	end
	-- an in-game setting of this save (sl_settings.lua; the panel in the Smart Lanes tool or the Crossing Tool)
	if op == "setting" then
		if not Settings.apply(s, extra.key, extra.value) then return end
		state:set(s)
		out("SETTINGS", { { "op", "set" }, { "key", extra.key }, { "value", extra.value },
			{ "param", Settings.BY_NAME[extra.key].key }, { "src", src }, { "seq", s.sseq } })
		return
	end
	if op == "pass" then
		local mp = type(s.mpass) == "table" and s.mpass or {}
		if (tonumber(mp.done) or 0) >= extra.seq then return end
		s.mpass = { seq = math.max(tonumber(mp.seq) or 0, extra.seq), done = extra.seq }
		-- the tool's mirror re-reads the extras only when aseq changed (its "Setting smart lanes ..." line ends)
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
		return
	end
	if op == "all" then
		local prev = type(s.aall) == "table" and tonumber(s.aall.seq) or 0
		s.aall = { seq = (prev or 0) + 1, run = run }
		s.arun = run
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
		autoLine(s, { { "op", "enroll_all" }, { "phase", "request" }, { "run", run }, { "src", src } })
		return
	end
	if op == "clear" then
		local n = type(s.auto) == "table" and #s.auto or 0
		s.auto = nil
		s.arun = run
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
		autoLine(s, { { "op", "unenroll" }, { "all", 1 }, { "n", n }, { "run", run }, { "src", src } })
		return
	end
	if op == "last" then
		-- last-measured records (both modes): rlast and lseq only (the runtime's aseq mirror is not re-read); no line
		-- (the runtime and the tool log their decisions)
		local list, st = Auto.applyLast(s.rlast, nodes)
		if not st.changed then return end
		s.rlast = #list > 0 and list or nil
		s.lseq = (s.lseq or 0) + 1
		state:set(s)
		return
	end
	if op == "traffic" then
		-- the tool's traffic recordings (sl_record.lua): trec and tseq only; no line (the tool logs TRAFFIC)
		local list, st = Rec.apply(s.trec, nodes)
		if not st.changed then return end
		s.trec = #list > 0 and list or nil
		s.tseq = (s.tseq or 0) + 1
		state:set(s)
		return
	end
	if op == "now" then
		local prev = type(s.areq) == "table" and tonumber(s.areq.seq) or 0
		s.areq = { seq = (prev or 0) + 1, nodes = nodes }
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
		for _, e in ipairs(nodes) do
			autoLine(s, { { "op", "now" }, { "node", e[1] }, { "pos", Auto.posKey(e[2], e[3]) }, { "src", src } }, e[2], e[3])
		end
		return
	end
	-- all lights' own adds (src=build: a new light at a build's nodes; src=select: the tool selected an eligible
	-- junction) only while all lights are in force
	if op == "add" and (src == "build" or src == "select")
		and AllMode.effective(E.cfg and E.cfg.autoLights, s.amode) ~= "all" then
		return
	end
	-- a whole-map enroll (src=all: the all-lights listing, the Stress Test's op=all) and all lights' own adds (build,
	-- select) never enroll a junction the player opted out (one read before the opt-out landed)
	if op == "add" and (src == "all" or src == "build" or src == "select") and type(s.aout) == "table" then
		local idx, keep = Auto.index(s.aout), {}
		for _, e in ipairs(nodes) do
			if Auto.match(idx, e[1], e[2], e[3]) == nil then keep[#keep + 1] = e end
		end
		if #keep == 0 then return end
		nodes = keep
	end
	local list, st = Auto.apply(s.auto, op, nodes)
	-- All lights (the setting or the save's amode): a junction the player unticks is remembered as opted out (never
	-- enrolled again by the listing), one ticked by hand leaves the opt-outs
	local optLines = {}
	if src == "tool" and (op == "add" or op == "remove") then
		local outList, added, dropped, removed = s.aout, 0, 0, 0
		if op == "remove" and AllMode.effective(E.cfg and E.cfg.autoLights, s.amode) == "all" then
			outList, added, dropped = AllMode.optOut(s.aout, nodes, Auto.matches)
		elseif op == "add" and type(s.aout) == "table" then
			outList, removed = AllMode.optIn(s.aout, nodes, Auto.matches)
		end
		if added > 0 or dropped > 0 or removed > 0 then
			s.aout = #outList > 0 and outList or nil
			st.changed = true
			for _, e in ipairs(nodes) do
				optLines[#optLines + 1] = { { "op", op == "remove" and "optout" or "optin" }, { "node", e[1] },
					{ "pos", Auto.posKey(e[2], e[3]) }, { "src", src }, { "optouts", #outList } }
			end
			if dropped > 0 then optLines[#optLines + 1] = { { "op", "optout_drop" }, { "n", dropped }, { "max", AllMode.OUT_MAX } } end
		end
	end
	if not st.changed and #st.refused == 0 then return end
	if st.changed then
		s.auto = #list > 0 and list or nil
		s.aseq = (s.aseq or 0) + 1
		state:set(s)
	end
	if op == "update" then return end
	local refused = {}
	for _, e in ipairs(st.refused) do refused[e] = true end
	for _, e in ipairs(nodes) do
		if refused[e] then
			autoLine(s, { { "op", "refuse" }, { "reason", "cap" }, { "node", e[1] }, { "pos", Auto.posKey(e[2], e[3]) },
				{ "src", src }, { "total", #list } }, e[2], e[3])
		else
			autoLine(s, { { "op", op == "add" and "enroll" or "unenroll" }, { "node", e[1] }, { "pos", Auto.posKey(e[2], e[3]) },
				{ "src", src }, { "total", #list } }, e[2], e[3])
		end
	end
	for _, f in ipairs(optLines) do autoLine(s, f) end
end

--- SL-5: our GUI's queue report { qlen = n (its queued and unanswered work), seen = the last job seq it took }.
local function handleQlen(state, param)
	if type(param) ~= "table" then return end
	local n, seen = tonumber(param.qlen), tonumber(param.seen)
	if n == nil or n < 0 or n ~= math.floor(n) or n > 1e6 then return end
	local s = state:get() or {}
	s.qgui, s.qseen = n, seen
	setQlen(s)
	state:set(s)
end

local function doHandleEvent(state, id, name, param)
	if id == Zones.EVENT_ID and name == EV_QLEN then
		if E.cfg == nil then E.cfg = settings() end
		if E.cfg.mapEditor then return end
		handleQlen(state, param)
		return
	end
	if id == Zones.EVENT_ID and name == Zones.EV_ZONES then
		if E.cfg == nil then E.cfg = settings() end
		if E.cfg.mapEditor then return end
		handleZones(state, param)
		return
	end
	if id == Kept.EVENT_ID and name == Kept.EV_KEPT then
		if E.cfg == nil then E.cfg = settings() end
		if E.cfg.mapEditor then return end
		handleKept(state, param)
		return
	end
	if id == Auto.EVENT_ID and name == Auto.EV_AUTO then
		if E.cfg == nil then E.cfg = settings() end
		if E.cfg.mapEditor then return end
		handleAuto(state, param)
		return
	end
	if id ~= "apply_command" or name ~= EV_POST then return end
	if E.cfg == nil then E.cfg = settings() end
	-- all lights: new lights at a build's nodes, whatever "Apply automatically to new roads" says (never the editor)
	if not E.cfg.mapEditor then
		local okL, eL = pcall(handleNewLights, state, param)
		if not okL then err("new_lights", eL) end
	end
	if not E.cfg.active then return end
	handleBuild(state, param)
end

---------------------------------------------------------------------------
-- GUI thread

-- inflight: node -> number of our proposals naming it that have not answered yet (slip parts, ring
-- proposals, light proposals; a phases-only light proposal never goes out for such a node: built from
-- reads before that write lands, its phases would index the old connections; a job does not start
-- while one of its nodes is held); inflightAt: node -> frame of the last send naming it (a callback
-- that never comes holds the node INFLIGHT_TIMEOUT frames at most)
-- zones / zseq: the mirror of the saved zones (sl_zones.lua), re-read when the state's zseq changes
-- kept / kseq / keptIdx: the mirror of the saved kept nodes (sl_kept.lua; Kept.index of it), re-read when kseq changes
-- active: the job in progress (stepJob, one at a time; new jobs wait in pending); inJob: true while its
-- steps run; now: the frame-budget clock (ms); est: running average cost (ms) per kind of step
-- retryQ: { job, node } entries of a refused slip part, each sent again alone (retryStep, guiBody)
-- waits: the slip parts and retries sent and not answered yet, { at = send frame, job, kind = "part" |
-- "retry", n = entries, done, expire } (expireWaits gives them up INFLIGHT_TIMEOUT frames after at)
local G = { init = false, cfg = nil, frames = 0, nextPoll = 0, lastSeq = nil, pending = {}, verify = {}, w = nil, inflight = {},
	inflightAt = {}, zones = nil, zseq = nil, active = nil, inJob = false, now = nil, est = {}, lightsQ = {}, retryQ = {},
	waits = {}, splits = {}, kept = nil, kseq = nil, keptIdx = nil }

--- Milliseconds of api.type.Clock (wall clock; safe on every GUI thread, findings "Timers and threads").
-- Without a Clock (G.now false: an api without one, e.g. offline tests without a fake Clock) there is no
-- budget: a job runs in one frame, as before the budget; the timings then use os.clock.
local function now()
	if G.now == nil then
		local ok, c = pcall(function() return api.type.Clock.new() end)
		if ok and c ~= nil and pcall(function() return c:getTime() end) then
			G.now = function() return c:getTime() / 1000 end
		else
			G.now = false
		end
	end
	if G.now == false then return os.clock() * 1000 end
	return G.now()
end

--- Whether a step of kind k still fits in the frame that started at t0 (always the first one).
local function fits(k, t0, steps)
	if steps == 0 then return true end
	local t = now()
	return G.now == false or (t - t0) + (G.est[k] or STEP_EST_MS) <= BUDGET_MS
end

--- Records a step of kind k that took ms (running average).
local function stepCost(k, ms)
	local e = G.est[k] or STEP_EST_MS
	G.est[k] = e + (ms - e) * 0.25
end

--- Counts a proposal naming n as on its way (busyNode) until inflightDone(n).
local function inflightAdd(n)
	G.inflight[n] = (G.inflight[n] or 0) + 1
	G.inflightAt[n] = G.frames
end

local function inflightDone(n)
	local k = (G.inflight[n] or 1) - 1
	G.inflight[n] = k > 0 and k or nil
	if k <= 0 then G.inflightAt[n] = nil end
end

--- Whether a proposal of ours naming n (lanes or lights) is still unanswered.
local function heldNode(n)
	if (G.inflight[n] or 0) > 0 then
		if G.frames - (G.inflightAt[n] or G.frames) <= INFLIGHT_TIMEOUT then return true end
		-- no callback came: never hold the node for good
		G.inflight[n], G.inflightAt[n] = nil, nil
	end
	return false
end

--- Whether a proposal naming n is still unanswered, or a job not yet processed lists n (also the
-- job in progress, for callers outside its steps: it may write n in a later frame).
local function busyNode(n)
	if heldNode(n) then return true end
	if G.active ~= nil and not G.inJob and G.active.nodeSet[n] then return true end
	for _, job in ipairs(G.pending) do
		for _, x in ipairs(job.nodes) do
			if x == n then return true end
		end
	end
	return false
end

--- The shared GUI-thread read / write path (sl_write.lua), made on first use: `api` is read at
-- call time, so the offline tests can load this file with a fake api.
local function W()
	-- PROBE phases (W.probePhases) only with the "Debug: performance log" setting On
	if G.w == nil then G.w = Write.new(api, out, { probeOn = function() return perfGui.on == true end }) end
	return G.w
end

--- The zone (sl_zones.lua record) node n lies in, from the zones mirror (G.zones) and the node's position; nil
-- outside every zone, without zones or without a position. One BASE_NODE read.
local function zoneOfNode(n)
	if G.zones == nil or #G.zones == 0 or type(n) ~= "number" then return nil end
	local ok, p = pcall(function()
		local bn = api.engine.getComponent(n, api.type.ComponentType.BASE_NODE)
		return bn and bn.position
	end)
	if not ok or p == nil then return nil end
	return Zones.zoneAt(G.zones, p.x, p.y)
end

-- SL-3: zid=<the zone's id label> appended to APPLY, SKIP, LIGHTS, PHASES, AUDIT and RSPLIT lines whose node lies in a
-- zone with an id (lines without a node field, or zones without an id, stay as they are; the SKIP kind=zone
-- line lists its nodes' ids itself, zoneFilter)
local ZID_KINDS = { APPLY = true, SKIP = true, LIGHTS = true, PHASES = true, AUDIT = true, RSPLIT = true, SPLIT = true,
	AUTORETIME = true }
zidHook = function(kind, fields)
	if not ZID_KINDS[kind] or type(fields) ~= "table" or G.zones == nil or #G.zones == 0 then return end
	local node = nil
	for _, kv in ipairs(fields) do
		if kv[1] == "zid" then return end
		if kv[1] == "node" and type(kv[2]) == "number" then node = kv[2] end
	end
	local id = node ~= nil and Zones.idOf(zoneOfNode(node)) or nil
	if id ~= nil then fields[#fields + 1] = { "zid", id } end
end

--- SL-1: nodes of `nodes` that lie in an sl_keeplights zone keep their lights: each one whose lights the
-- setting would switch off (Lights.needs) logs LIGHTS src=<src> node= to=kept zone=sl_keeplights [zid=]; the
-- others are returned (the setting On; Off: every node, nothing logged). t (optional): the job's tally
-- (lightsKept). Nodes outside such a zone: unchanged.
local function keepLights(nodes, src, t)
	if not G.cfg.lights or G.zones == nil or #G.zones == 0 or #nodes == 0 then return nodes end
	local keep = {}
	for _, n in ipairs(nodes) do
		local z = zoneOfNode(n)
		if z ~= nil and z.ab == "sl_keeplights" then
			local okS, st = pcall(W().lightState, n)
			if okS and Lights.needs(st, Lights.OFF, W().lightEnum()) then
				out("LIGHTS", { { "src", src }, { "node", n }, { "to", "kept" }, { "zone", "sl_keeplights" } })
				if t ~= nil then t.lightsKept = (t.lightsKept or 0) + 1 end
			end
		else
			keep[#keep + 1] = n
		end
	end
	return keep
end

--- Lights off at `nodes` (when the setting is On). Called after the lane write answered, so the
-- two proposals never race on one node's config. Queued (G.lightsQ) and sent one node per step in the
-- next GUI frames within the frame budget (lightsStep), before any job step: a big job's light proposals
-- never pile into one frame, and no job writes while lights it switched off are still to go out.
local function lightsOff(nodes, key, late)
	if not G.cfg.lights or #nodes == 0 then return end
	G.lightsQ[#G.lightsQ + 1] = { nodes = nodes, key = key, i = 1, pending = 0, sent = 0, expect = {}, closed = false, late = late }
end

--- One verify of the lights of entry q once every light proposal of it answered (as W.setLights' onDone:
-- only when at least one was sent; expect = the nodes whose proposal was accepted).
local function lightsFinish(q)
	if q.finished or not q.closed or q.pending > 0 or q.sent == 0 then return end
	q.finished = true
	G.verify[#G.verify + 1] = { kind = "lights", job = q.key, expect = q.expect, due = G.frames + VERIFY_DELAY }
end

--- One frame's share of a lights-off entry (W.setLights per node; its LIGHTS line each). Returns done, steps.
local function lightsStep(q, t0, steps)
	local used = 0
	while q.i <= #q.nodes do
		if not fits("lights", t0, steps + used) then return false, used end
		local s0 = now()
		local n = q.nodes[q.i]
		q.i, used = q.i + 1, used + 1
		-- held until it answered: a lane write built from a read before the light change lands is refused
		-- (findings roads.md "pending traffic light change"), so the next job waits for it (guiBody)
		inflightAdd(n)
		local held = true
		local function release()
			if held then
				held = false
				inflightDone(n)
			end
		end
		local ok, k = pcall(W().setLights, { n }, Lights.OFF, "auto", function(expect)
			release()
			for x in pairs(expect) do q.expect[x] = true end
			q.pending = q.pending - 1
			lightsFinish(q)
		end)
		if not ok then
			release()
			err("lights", k)
		elseif k > 0 then
			q.sent, q.pending = q.sent + 1, q.pending + 1
		else
			release() -- nothing sent: no callback comes
		end
		stepCost("lights", now() - s0)
	end
	q.closed = true
	lightsFinish(q)
	-- SL-6: one late look at these nodes when they lie in a zone (the bench's twins; outside every zone nothing
	-- changes): a light the game put there after this pass is switched off then. Never for the late entry
	-- itself, so it runs once per entry
	if not q.late and G.zones ~= nil and #G.zones > 0 then
		local list = {}
		for _, n in ipairs(q.nodes) do
			if zoneOfNode(n) ~= nil then list[#list + 1] = n end
		end
		if #list > 0 then
			G.verify[#G.verify + 1] = { kind = "lights_late", job = q.key, nodes = list, due = G.frames + LIGHTS_LATE_FRAMES }
		end
	end
	return true, used
end

--- SL-6: the late look of a lights-off entry: its nodes whose lights the setting still switches off
-- (Lights.needs: a light or a preference other than NO came back; a node in an sl_keeplights zone by now, or
-- busy with a proposal in flight, is left alone) go into one more lights-off entry, marked late (no further
-- look). One RECHECK kind=lights job= nodes= lit= queued= line. Returns done, the steps taken.
local function lightsLate(v, t0, steps)
	local used = 0
	v.i, v.need = v.i or 1, v.need or {}
	while v.i <= #v.nodes do
		if not fits("verify_lights", t0, steps + used) then return false, used end
		local n = v.nodes[v.i]
		v.i, used = v.i + 1, used + 1
		if not busyNode(n) then
			local okS, st = pcall(W().lightState, n)
			if okS and Lights.needs(st, Lights.OFF, W().lightEnum()) then v.need[#v.need + 1] = n end
		end
	end
	local list = keepLights(v.need, "recheck", nil)
	out("RECHECK", { { "kind", "lights" }, { "job", v.job }, { "nodes", #v.nodes }, { "lit", #v.need }, { "queued", #list } })
	if #list > 0 then lightsOff(list, tostring(v.job) .. "_late", true) end
	return true, used
end

--- Per-job outcome counts for the SUMMARY line (PHASE7.md step 6).
local function newTally()
	return { rings = 0, ringApply = 0, ringSame = 0, ringSkip = 0, slip = 0, cross = 0, drop = 0, same = 0, skip = 0, reasons = {},
		freeTurn = 0, freeStats = { phases = 0, merge = 0, cross = 0, ped = 0, merged = 0, shared = 0 }, slPlans = 0, planFails = {}, zonePhases = 0,
		zoneFan = 0, zoneLock = 0, lockTurn = 0, lockPhases = 0, zoneExitFan = 0, exitFan = 0, zoneKeepLights = 0, lightsKept = 0,
		zoneRing = 0 }
end

--- The fields an sl_lock zone's crossroads / T-junction adds to its APPLY / AUDIT lines (appended to f):
-- zone=sl_lock free_turn=off (its kerb turn stays locked whatever the setting, sl_zones.lua).
local function lockFields(f)
	f[#f + 1] = { "zone", "sl_lock" }
	f[#f + 1] = { "free_turn", "off" }
	return f
end

--- The field an sl_exitfan zone's crossroads / T-junction adds to its APPLY / AUDIT lines: zone=sl_exitfan
-- (Slip.logFields adds exit_fan=yes | unlit | lit_unknown | <off the model>).
local function exitFanFields(f)
	f[#f + 1] = { "zone", "sl_exitfan" }
	return f
end

--- A failed Smart Lanes plan under its reason's first word ("plan_fail:invalid_conflict:..." -> invalid_conflict).
local function tallyPlanFail(t, reason)
	local k = tostring(reason or "?"):gsub("^plan_fail:", ""):match("^[^:]+") or "?"
	t.planFails[k] = (t.planFails[k] or 0) + 1
end

--- A skip under its reason's first word ("lights:2>5" -> lights, "no_strategy:subset=.." -> no_strategy).
local function tallySkip(t, reason)
	local k = tostring(reason or "?"):match("^[^:]+") or "?"
	t.skip = t.skip + 1
	t.reasons[k] = (t.reasons[k] or 0) + 1
end

--- sendConfigs' onSkip for tally t: a node the write layer refused (phases, no config, read-only
-- strategy) moves from its applied count to skip.
local function refused(t)
	return function(it, reason)
		local k = it.tally
		if k and t[k] and t[k] > 0 then t[k] = t[k] - 1 end
		if k == "ringApply" then t.ringSkip = t.ringSkip + 1 end
		tallySkip(t, reason)
	end
end

--- The ring's proposal (its apply junctions, whole, in one proposal). Returns the ms the write took.
-- lightSeeds: set of the nodes whose lights the setting may switch off (nil: every planned junction).
local function sendRing(ring, plan, t, lightSeeds)
	local items = {}
	for _, r in ipairs(plan.nodes) do
		if r.status == "apply" then items[#items + 1] = { node = r.node, conns = r.conns, tally = "ringApply" } end
	end
	local key = ring.key
	local ringLights = Lights.ringNodes(plan)
	if lightSeeds ~= nil then
		local keep = {}
		for _, n in ipairs(ringLights) do
			if lightSeeds[n] then keep[#keep + 1] = n end
		end
		ringLights = keep
	end
	local lightNodes = keepLights(ringLights, "auto", t)
	if #items == 0 then
		lightsOff(lightNodes, key)
		return 0
	end
	-- the re-read is timed from the callback: with several rings in one build (Magic Roundabout)
	-- the commands queue, and a fixed delay from the send re-read before they were applied
	local tWrite = now()
	-- the ring's nodes are held (busyNode) until the proposal answered, as a slip proposal's
	local held = {}
	for _, it in ipairs(items) do
		held[#held + 1] = it.node
		inflightAdd(it.node)
	end
	local function release()
		for _, n in ipairs(held) do inflightDone(n) end
		held = {}
	end
	local okS, sent = pcall(W().sendConfigs, "ring", key, items, function(success, expect, nodes)
		release()
		out("WRITE", { { "ring", key }, { "nodes", nodes }, { "success", success } })
		if success then
			G.verify[#G.verify + 1] = { ring = key, expect = expect, due = G.frames + VERIFY_DELAY }
		end
		lightsOff(lightNodes, key)
	end, refused(t))
	if not okS then
		release() -- not sent: no callback comes
		error(sent, 0)
	end
	local ms = now() - tWrite
	if sent == 0 then
		release()
		lightsOff(lightNodes, key)
	end
	return ms
end

--- One SUMMARY line per processed job that handled anything (a ring, or a slip / crossing / drop
-- candidate planned as apply, same or skip); jobs of plain road only stay quiet. Logged when the
-- proposals are sent: ring=applied/same/skipped ring junctions; slip (cases A / B), cross (X), drop
-- (D) the nodes sent; same / skip over all of them (skip includes nodes the write layer refused);
-- the WRITE / VERIFY lines tell whether the proposals landed.
local function summary(job, t)
	if t.rings == 0 and t.slip + t.cross + t.drop + t.same + t.skip == 0 then return false end
	local f = { { "job", job.seq }, { "nodes", count(job.nodes) }, { "rings", t.rings },
		{ "ring", t.ringApply .. "/" .. t.ringSame .. "/" .. t.ringSkip }, { "slip", t.slip }, { "cross", t.cross },
		{ "drop", t.drop }, { "same", t.same }, { "skip", t.skip }, { "skips", Rules.countsText(t.reasons) },
		{ "phases", G.cfg.phases } }
	if G.cfg.phases == "sl" or t.zonePhases > 0 or t.zoneFan > 0 then
		f[#f + 1] = { "sl_plans", t.slPlans }
		f[#f + 1] = { "plan_fail", Rules.countsText(t.planFails) }
	end
	-- crossroads / T-junctions planned with Smart Lanes phases only because they lie in an sl_phases zone
	if t.zonePhases > 0 then f[#f + 1] = { "zone_phases", t.zonePhases } end
	-- crossroads / T-junctions in an sl_fan zone (the fan when lit, else the rule until a light stands)
	if t.zoneFan > 0 then f[#f + 1] = { "zone_fan", t.zoneFan } end
	-- crossroads / T-junctions in an sl_lock zone (kerb turn kept locked, game phases), the kerb connections
	-- locked back there (a turn freed earlier) and their (connection, phase) locks; free_turn= counts none of them
	if t.zoneLock > 0 then
		f[#f + 1] = { "zone_lock", t.zoneLock }
		f[#f + 1] = { "lock_turn", t.lockTurn }
		f[#f + 1] = { "lock_phases", t.lockPhases }
	end
	-- crossroads / T-junctions in an sl_exitfan zone (game phases), and those written with the exit fan (lit)
	if t.zoneExitFan > 0 then
		f[#f + 1] = { "zone_exitfan", t.zoneExitFan }
		f[#f + 1] = { "exit_fan", t.exitFan }
	end
	-- SL-1: the job's nodes in sl_keeplights zones, and the nodes there whose lights stayed (LIGHTS to=kept)
	if t.zoneKeepLights > 0 then
		f[#f + 1] = { "zone_keeplights", t.zoneKeepLights }
		f[#f + 1] = { "lights_kept", t.lightsKept }
	end
	-- rings planned with a ring layout variant (their zones)
	if t.zoneRing > 0 then f[#f + 1] = { "zone_ring", t.zoneRing } end
	f[#f + 1] = { "free_turn", Lights.modeFor(G.cfg.freeTurn) and t.freeTurn or "off" }
	local mode = Lights.modeFor(G.cfg.freeTurn)
	if mode ~= nil then f[#f + 1] = { "free_phases", t.freeStats.phases } end
	if mode == Lights.SAFE then
		f[#f + 1] = { "kept", Lights.keptText(t.freeStats) }
		f[#f + 1] = { "merge_free", t.freeStats.merged or 0 }
	end
	if mode ~= nil then f[#f + 1] = { "shared_held", t.freeStats.shared or 0 } end
	-- later jobs that arrived while this one waited and shared nodes with it (enqueue): one job now
	if job.merged ~= nil then f[#f + 1] = { "merged", table.concat(job.merged, ",") } end
	out("SUMMARY", f)
	return true
end

--- Records a planned junction for the audit (planned: { order = {node...}, [node] = { conns, view, ring } }).
local function plannedAdd(planned, n, conns, view, ring)
	if conns == nil or planned[n] ~= nil then return end
	planned[n] = { conns = conns, view = view, ring = ring }
	planned.order[#planned.order + 1] = n
end

--- AUDIT lines of the job's planned junctions and the job's AUDIT_SUMMARY (sl_audit.lua), one junction
-- per step (auditStep) and the summary at the end (auditEnd). Runs after the proposals were sent; weave looks
-- only at junctions planned in this job (no extra config reads). world: the step's frame world (the
-- views and connections are the plan's; the geometry is read again in that frame).
local function auditStep(world, job, n)
	local a, planned = job.audit, job.planned
	local p = planned[n]
	local res, e = Audit.safe(world, n, p.conns, { view = p.view, ring = p.ring, connsOf = a.connsOf, connsFirst = true })
	-- the first failure of the job is logged (the summary counts them all: failed=)
	if res == nil and a.sum.failed == 0 then err("audit", e) end
	Audit.addTo(a.sum, res)
	if res ~= nil and res.total > 0 then
		-- at most MAX_LINES lines per job (a big build stays readable; the summary has the totals)
		if a.logged < Audit.MAX_LINES then
			local extra = { { "src", "auto" }, { "job", job.seq } }
			if job.zoneAb ~= nil and job.zoneAb[n] == "sl_lock" and p.view ~= nil and p.view.case == "X" then lockFields(extra) end
			if job.zoneAb ~= nil and job.zoneAb[n] == "sl_exitfan" and p.view ~= nil and p.view.case == "X" then exitFanFields(extra) end
			out("AUDIT", Audit.fields(res, extra))
			a.logged = a.logged + 1
		else
			a.sum.unlogged = a.sum.unlogged + 1
		end
	end
end

local function auditEnd(job)
	local f = Audit.summaryFields(job.audit.sum, { { "src", "auto" }, { "job", job.seq } })
	f[#f + 1] = { "skips", Rules.countsText(job.t.reasons) }
	out("AUDIT_SUMMARY", f)
end

--- Free kerb turn re-checks (see the header): list = { {node, text, bus, kerb, mode} } of nodes whose lanes
-- are ours (text = Rules.carText with the view's bus set: bus-lane connections left out) and whose lights
-- were unknown at the read; one entry per delay.
local function scheduleRecheck(job, list)
	if #list == 0 then return end
	for _, d in ipairs(RECHECK_FRAMES) do
		G.verify[#G.verify + 1] = { kind = "recheck", job = job, nodes = list, due = G.frames + d }
	end
end

--- A light proposal naming n is on its way (busyNode): until its callback.
local function lightSent(n)
	inflightAdd(n)
	local released = false
	return function()
		if released then return end
		released = true
		inflightDone(n)
	end
end

--- Smart Lanes phases at a crossroads whose lanes are already right (status same): a phases-only
-- light proposal (W.planLights); a failed plan falls back to the free kerb turn (freeSame, when
-- the setting is not Off). Returns the reason when nothing was sent. Errors are logged, never thrown.
local freeSame
local function planSame(n, lp, kerb, mode, t, src)
	if busyNode(n) then return "busy" end
	local done = lightSent(n)
	-- keepTiming: the plan's phases re-timed (Re-time, Keep timing adjusted, the Crossing window) count as set, so a
	-- build nearby never throws the fitted timing away; changed lanes give another plan structure and still write
	local ok, k, why = pcall(W().planLights, n, lp, src or "auto", function() done() end, nil, true)
	if not ok then
		done()
		err("phases", k)
		return "error"
	end
	if k > 0 then
		t.slPlans = t.slPlans + 1
		return nil
	end
	done() -- nothing sent: no callback comes
	if tostring(why):find("^plan_fail") then
		tallyPlanFail(t, why)
		if kerb ~= nil and mode ~= nil then freeSame(n, kerb, mode, t) end
	end
	return why
end

--- Kerb turns freed at a crossroads whose lanes are already right (status same): a phases-only light
-- proposal (W.kerbLights). Errors are logged, never thrown.
function freeSame(n, kerb, mode, t)
	if busyNode(n) then return end -- the re-check frees it once that write answered
	local ok, k, _, stats = pcall(W().kerbLights, n, kerb, mode, "auto")
	if not ok then
		err("free_turn", k)
	elseif mode == Lights.LOCK then
		-- an sl_lock zone: a kerb turn freed earlier locked back (LIGHTS ... to=lock_turn)
		if k > 0 then t.lockTurn = t.lockTurn + k end
		if stats ~= nil then t.lockPhases = t.lockPhases + (stats.phases or 0) end
	else
		if k > 0 then t.freeTurn = t.freeTurn + k end
		-- conflicts kept red count even when nothing was sent (phases is 0 then)
		if stats ~= nil then Lights.addStats(t.freeStats, stats) end
	end
end

--- The light nodes not in the set `gone` (nodes of a timed-out proposal: not known written, never relit).
local function lightsKept(nodes, gone)
	if next(gone) == nil then return nodes end
	local keep = {}
	for _, n in ipairs(nodes) do
		if not gone[n] then keep[#keep + 1] = n end
	end
	return keep
end

--- The job's WRITE kind=slip line, verify, re-checks and lights-off, once every slip proposal of the job
-- (one per frame that built entries: flushSlip) answered and the slip phase is over (closeSlip). The
-- line is the one a single proposal gave: nodes in item order, success when every part landed; the
-- verify and the re-checks cover the nodes of the parts that landed.
local function slipFinish(job)
	local sl, agg = job.slip, job.slip.agg
	if agg.finished or not agg.closed or agg.pending > 0 or agg.retryPending > 0 then return end
	agg.finished = true
	local key = "slip" .. tostring(job.seq)
	if agg.sent == 0 then
		lightsOff(lightsKept(sl.lightNodes, agg.timedOut), key)
		return
	end
	local f = { { "kind", "slip" }, { "job", job.seq }, { "nodes", table.concat(agg.nodes, ",") }, { "success", agg.ok },
		{ "phases", G.cfg.phases } }
	if sl.anyPlans then
		local planN, failN = 0, 0
		for _, it in ipairs(sl.items) do
			if it.planText ~= nil then planN = planN + 1 elseif it.planFail ~= nil then failN = failN + 1 end
		end
		f[#f + 1] = { "sl_plans", planN }
		f[#f + 1] = { "plan_fails", failN }
	end
	-- entries of refused parts sent again one by one (retryStep): queued, landed
	if agg.retry > 0 then
		f[#f + 1] = { "retry", agg.retry }
		f[#f + 1] = { "retry_ok", agg.retryOk }
	end
	-- entries whose proposal never answered (expireWaits)
	if agg.timeout > 0 then f[#f + 1] = { "timeout", agg.timeout } end
	out("WRITE", f)
	if agg.landed > 0 then
		G.verify[#G.verify + 1] = { kind = "slip", job = job.seq, expect = agg.expect, due = G.frames + VERIFY_DELAY }
		-- only the nodes that went into a proposal that landed (expect): a refused one was not written
		local list = {}
		for _, x in ipairs(sl.recheck) do
			if agg.expect[x.node] ~= nil then list[#list + 1] = x end
		end
		scheduleRecheck(job.seq, list)
	end
	lightsOff(lightsKept(sl.lightNodes, agg.timedOut), key)
end

--- Sends the entries this frame built (fb, slipStep) in one proposal. Every entry was built from reads of
-- this frame (W.addItem in slipStep), so the proposal never carries an older read.
local function flushSlip(job, fb)
	local sl, t, agg = job.slip, job.t, job.slip.agg
	local tWrite = now()
	local held = fb.inflight
	local function landed()
		for _, n in ipairs(held) do inflightDone(n) end
		held = {}
	end
	local part = fb.batch.nodesText
	-- the nodes whose entries are in the proposal (a refused part sends them again one by one)
	local partNodes = {}
	for i, n in ipairs(fb.batch.removes) do partNodes[i] = n end
	local answered = false
	local wait = { at = G.frames, job = job, kind = "part", n = #partNodes, done = false }
	-- no answer INFLIGHT_TIMEOUT frames after the send (expireWaits): the part is given up, its nodes released
	wait.expire = function()
		wait.done, wait.timedOut = true, true
		for _, n in ipairs(partNodes) do agg.timedOut[n] = true end
		agg.timeout = agg.timeout + #partNodes
		agg.ok = false
		landed()
		agg.pending = agg.pending - 1
	end
	local okS, sent, kerbN, kerbStats = pcall(W().sendBatch, fb.batch, function(success, expect)
		if wait.timedOut then
			-- after expireWaits gave it up: the job's lines are written, its nodes released; only logged
			out("LATE", { { "kind", "slip" }, { "job", job.seq }, { "nodes", #partNodes }, { "success", success == true } })
			return
		end
		answered = true
		wait.done = true
		if not success and #partNodes > 1 then
			-- the engine refuses a whole proposal for one bad entry (a stale segment, another mod's pending
			-- light change): every entry goes again alone, built from fresh reads in the next frames
			-- (retryStep), each once; the node stays held until its retry is over
			for _, n in ipairs(partNodes) do
				inflightAdd(n)
				G.retryQ[#G.retryQ + 1] = { job = job, node = n }
				agg.retry = agg.retry + 1
				agg.retryPending = agg.retryPending + 1
			end
		end
		landed()
		agg.pending = agg.pending - 1
		if success then
			agg.landed = agg.landed + 1
			for n, text in pairs(expect) do agg.expect[n] = text end
		else
			agg.ok = false
		end
		slipFinish(job)
	end)
	if okS and sent > 0 then
		-- counted before the callback can come (a fake game answers at once)
		agg.sent = agg.sent + 1
		for _, x in ipairs(part) do agg.nodes[#agg.nodes + 1] = x end
	end
	if not okS then
		-- the proposal could not be sent (no callback comes): release the nodes, report the error
		landed()
		agg.ok = false
		if answered then agg.pending = agg.pending + 1 end -- undo the answer's count (nothing was counted)
		job.ms.job_write = job.ms.job_write + (now() - tWrite)
		error(sent, 0)
	end
	if sent > 0 then agg.pending = agg.pending + 1 else landed() end -- nothing went out: no callback comes
	if sent > 0 and not answered then G.waits[#G.waits + 1] = wait end
	-- kerb connections locked back in sl_lock zones (items with phase.mode LOCK) are not freed ones
	local lockN, lockPh = 0, 0
	if sent ~= nil and sent > 0 then
		for _, it in ipairs(fb.items) do
			if it.phase ~= nil and it.phase.mode == Lights.LOCK and it.kerbChanged ~= nil then
				lockN = lockN + it.kerbChanged
				lockPh = lockPh + (it.kerbStats and it.kerbStats.phases or 0)
			end
		end
	end
	t.lockTurn, t.lockPhases = t.lockTurn + lockN, t.lockPhases + lockPh
	t.freeTurn = t.freeTurn + math.max(0, (kerbN or 0) - lockN)
	Lights.addStats(t.freeStats, kerbStats)
	t.freeStats.phases = math.max(0, t.freeStats.phases - lockPh)
	-- Smart Lanes plans built into the proposal (it.planText / it.planFail: set when it was built)
	for _, it in ipairs(fb.items) do
		if it.planText ~= nil then t.slPlans = t.slPlans + 1
		elseif it.planFail ~= nil then tallyPlanFail(t, it.planFail) end
	end
	job.ms.job_write = job.ms.job_write + (now() - tWrite)
	-- an answer that came during the send (fake game) waits for the count above; check again
	slipFinish(job)
end

--- One node of the slip phase (the job's nodes not on a ring): classified in this frame's world; an apply
-- node's entry is built at once into this frame's batch fb (W.addItem: the node's config read now), so plan
-- and entry come from the same frame's reads. zoneAb: node -> zone mode (sl_zones.lua) of the job's nodes
-- inside a zone (game-zone nodes are not in the job's nodes).
--- One entry of a refused slip part (flushSlip) sent again alone: the node planned again in this frame's
-- world and its entry built from this frame's reads (as slipStep), in its own proposal. Never retried
-- again. One RETRY line when it is over: result=landed | refused | same | skip:<reason> | not_built |
-- error. The node was held since the refusal; released when this is over. The job's WRITE line waits
-- for every retry (slipFinish: retry=<queued> retry_ok=<landed>); the tally (SUMMARY) is not changed.
local retryStep

--- Bench (plans/square_stress_test/BENCH.md "As implemented in Smart Lanes", SL-3): inside a zone only, one line for
-- a node the job looked at and left unchanged, so every twin node shows up: SKIP kind=<ring|cross|slip|drop|node>
-- [ring=<key>] node=<n> reason=same|plain [zid=<id>] (same: its lanes are already the rule's; plain: nothing to do
-- there). Once per node per job; outside every zone nothing is logged (the default logs stay as they were).
local function zoneKept(job, world, n, kind, reason, ringKey)
	if job.zones == nil or #job.zones == 0 or type(n) ~= "number" then return end
	job.keptLogged = job.keptLogged or {}
	if job.keptLogged[n] then return end
	local inZone = job.zoneAb ~= nil and job.zoneAb[n] ~= nil
	if not inZone then
		local node = world.node(n)
		inZone = node ~= nil and Zones.zoneAt(job.zones, node.x, node.y) ~= nil
	end
	if not inZone then return end
	job.keptLogged[n] = true
	local f = { { "kind", kind } }
	if ringKey ~= nil then f[#f + 1] = { "ring", ringKey } end
	f[#f + 1] = { "node", n }
	f[#f + 1] = { "reason", reason }
	out("SKIP", f)
end

--- A slip node's plan in `world` (slipStep, retryStep): r = Slip.plan, its case, the kerb pairs to free
-- (setting not Off, crossroads / T-junctions) and lp (the Smart Lanes phase plan's input, or nil), the
-- zone flags, and the node's kerb mode (the setting's; Lights.LOCK in an sl_lock zone).
-- An sl_lock zone: the kerb pairs of every crossroads / T-junction with mode Lights.LOCK (whatever the
-- setting: a turn freed earlier is locked back with its approach, as the tool's Reset), no phase plan.
local function slipPlan(job, world, n)
	local sl, zoneAb = job.slip, job.zoneAb or {}
	local mode, slGlobal = sl.mode, sl.slGlobal
	local zoneLock = zoneAb[n] == "sl_lock"
	if zoneLock then mode, slGlobal = Lights.LOCK, false end
	-- an sl_exitfan zone: the game's phases whatever "Light phases" says (the fan is planned for them:
	-- sl_cross X.phaseGroups); the lanes come from Slip.plan (world.exitFan), the kerb mode is the setting's
	local zoneExitFan = zoneAb[n] == "sl_exitfan"
	if zoneExitFan then slGlobal = false end
	-- an sl_fan zone: the full fan at a lit crossroads (r.fan), the rule elsewhere (Slip.plan opts.fan)
	local zoneFan = zoneAb[n] == "sl_fan"
	local r = Slip.plan(world, n, W().currentConns, zoneFan and { fan = true } or nil)
	local case = r.view and r.view.case
	local isX = case == "X" and (r.status == "apply" or r.status == "same")
	-- crossroads and T-junctions: the kerb turns to free in the phases (setting not Off)
	local kerb = (mode ~= nil and isX) and Slip.kerbPairs(r.view) or nil
	-- Light phases = Smart Lanes, or the node lies in an sl_phases / sl_auto / sl_fan zone: the planned
	-- phases (lit nodes only; unknown: the re-checks); the fan's own plan with its lanes, elsewhere the axis plan
	-- (none possible: the game's phases stay, sl_write W.remapLights)
	local zonePh = zoneAb[n] == "sl_phases" or zoneAb[n] == "sl_auto" or zoneFan
	local lp = ((slGlobal or zonePh) and isX)
		and { view = r.view, world = world, fan = r.fan == true } or nil
	return r, case, kerb, lp, zoneFan, zonePh, mode, zoneLock and isX, zoneExitFan and isX
end

--- The write item of an apply node (slipStep, retryStep): its tally kind and the item.
local function slipItem(r, n, case, kerb, lp, mode, src)
	local k = case == "X" and "cross" or (case == "D" and "drop" or "slip")
	local it = { node = n, conns = r.conns, tally = k, src = src }
	if kerb ~= nil then it.phase = { mode = mode, kerb = kerb } end
	if lp ~= nil then
		if r.view.lit == true then it.lightPlan = lp
		else it.planFail = r.view.lit == false and "unlit" or "lit_unknown" end
	end
	return it, k
end

--- The existing-junctions pass's hand-edit guard at a node the rule would change (sl_allmode.lua; PLAN.md "Automatic
-- timing for all lights + first-load welcome"): a crossroads / T-junction (a model of the game's lanes exists) whose
-- current lanes are neither the game's (Slip.isDefault, per movement) nor none is left alone (hand_edit), as is one
-- whose light phases look timed by hand (hand_timed: AllMode.handTimed, the flag plus whole-second greens; the flag
-- alone is set by Smart Lanes' own phase writes too, docs/findings/roads.md). Slip-lane junctions and lane drops have
-- no model of the game's lanes: they are written as after a build. Returns the reason or nil.
local function mapPassHandEdit(n, r, case)
	if case ~= "X" or r.view == nil then return nil end
	local cur = W().currentConns(n) or {}
	if #cur > 0 then
		local model = Slip.defaultConns(r.view)
		local bus = r.view.bus
		local same = model ~= nil and Rules.roadText(model, bus) == Rules.roadText(cur, bus)
		if not same and Slip.isDefault(r.view, cur) ~= true then return "hand_edit" end
	end
	if r.view.lit == true then
		local okR, lr = pcall(W().lightRead, n)
		local um = nil
		if okR and lr ~= nil then pcall(function() um = lr.cfg.userModifiedTrafficLightStates end) end
		if um == true then
			local states, greens = {}, {}
			for i, st in ipairs(lr.tlc.states) do
				local l = {}
				for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
				states[i] = { locked = l, duration = st.duration }
			end
			local kinds = Retime.kinds(#(lr.conns or {}), #(lr.cws or {}), states)
			for i, st in ipairs(states) do
				if kinds[i] == "veh" then greens[#greens + 1] = st.duration end
			end
			if AllMode.handTimed(true, greens, false, G.cfg.phases == "sl") then return "hand_timed" end
		end
	end
	return nil
end

local function slipStep(job, world, n, fb)
	local sl, t = job.slip, job.t
	local slGlobal = sl.slGlobal
	-- read-only dump of a lit node's phases (debug setting On; once per node, capped)
	pcall(W().probePhases, n, world)
	local r, case, kerb, lp, zoneFan, zonePh, mode, lockX, exitX = slipPlan(job, world, n)
	local quiet = job.jobIn.quiet ~= nil and job.jobIn.quiet[n] == true
	-- an existing junction the build did not change (PLAN.md "Nearby junctions stay as they are"): its lanes are not
	-- written; with Smart Lanes' lanes kept by the engine (status same) it takes the same path below (its phases)
	if quiet and r.status == "apply" then
		out("SKIP", { { "kind", case == "X" and "cross" or (case == "D" and "drop" or "slip") }, { "node", n }, { "reason", "unchanged" } })
		tallySkip(t, "unchanged")
		return 0
	end
	if lockX then t.zoneLock = t.zoneLock + 1 end
	if exitX then
		t.zoneExitFan = t.zoneExitFan + 1
		if r.view.exitFan then t.exitFan = t.exitFan + 1 end
	end
	if lp ~= nil and zonePh then
		sl.anyPlans = true
		if zoneFan then t.zoneFan = t.zoneFan + 1
		elseif not slGlobal then t.zonePhases = t.zonePhases + 1 end
	end
	-- fan nodes are not audited: their lanes cross by design
	if (r.status == "apply" or r.status == "same") and not r.fan then plannedAdd(job.planned, n, r.conns, r.view) end
	local writeMs = 0
	if r.status == "apply" and job.jobIn.mapPass ~= nil then
		local why = mapPassHandEdit(n, r, case)
		if why ~= nil then
			out("SKIP", { { "kind", case == "X" and "cross" or (case == "D" and "drop" or "slip") }, { "node", n }, { "reason", why } })
			tallySkip(t, why)
			return 0
		end
	end
	if r.status == "apply" then
		local fields = Slip.logFields(r)
		if lockX then lockFields(fields) end
		if exitX then exitFanFields(fields) end
		out("APPLY", fields)
		local it, k = slipItem(r, n, case, kerb, lp, mode, "auto")
		-- an sl_lock node needs no re-check after its write: phases the game makes later lock the kerb turn
		-- an sl_exitfan node whose light was unknown: its lanes again once a light stands (exitFan, recheckFree)
		if (kerb ~= nil or lp ~= nil or exitX) and not lockX and r.view.lit == nil and #sl.recheck < MAX_RECHECK then
			sl.recheck[#sl.recheck + 1] = { node = n, text = Rules.carText(r.conns, r.view.bus), bus = r.view.bus, kerb = kerb, mode = mode, sl = lp ~= nil,
				fan = zoneFan or nil, exitFan = exitX or nil }
		end
		sl.items[#sl.items + 1] = it
		fb.items[#fb.items + 1] = it
		t[k] = t[k] + 1
		-- held from now until this frame's proposal answered (busyNode)
		fb.inflight[#fb.inflight + 1] = n
		inflightAdd(n)
		local w0 = now()
		W().addItem(fb.batch, "slip_job", job.seq, it, refused(t))
		writeMs = now() - w0
	elseif r.status == "skip" then
		out("SKIP", { { "kind", case == "D" and "drop" or "slip" }, { "node", n }, { "reason", r.reason } })
		tallySkip(t, r.reason)
	elseif r.status == "same" then
		t.same = t.same + 1
		zoneKept(job, world, n, case == "X" and "cross" or (case == "D" and "drop" or "slip"), "same")
		local rs = sl.recheckSame
		if lp ~= nil then
			if r.view.lit == false then
				tallyPlanFail(t, "unlit")
			else
				planSame(n, lp, kerb, mode, t)
			end
			if (r.view.lit == nil or busyNode(n)) and #sl.recheck + #rs < MAX_RECHECK then
				rs[#rs + 1] = { node = n, text = Rules.carText(r.conns, r.view.bus), bus = r.view.bus, kerb = kerb, mode = mode, sl = true, fan = zoneFan or nil }
			end
		elseif kerb ~= nil or exitX then
			if kerb ~= nil then freeSame(n, kerb, mode, t) end
			-- sl_lock: only a busy node is looked at again (unknown light: no phases, nothing freed)
			if ((r.view.lit == nil and not lockX) or busyNode(n)) and #sl.recheck + #rs < MAX_RECHECK then
				rs[#rs + 1] = { node = n, text = Rules.carText(r.conns, r.view.bus), bus = r.view.bus, kerb = kerb, mode = mode, exitFan = exitX or nil }
			end
		end
	end
	-- nothing to do at this node (a plain road node, a dead end, not a junction the rules handle): inside zones only
	if r.status ~= "apply" and r.status ~= "skip" and r.status ~= "same" then zoneKept(job, world, n, "node", "plain") end
	-- the existing-junctions pass changes no lights ("No lights at roundabouts and ramps" acts on what you build),
	-- nor does a build at a quiet junction
	if job.jobIn.mapPass == nil and not quiet and Lights.slipNode(r) and #keepLights({ n }, "auto", t) > 0 then sl.lightNodes[#sl.lightNodes + 1] = n end
	return writeMs
end

retryStep = function(x, world)
	local job, n = x.job, x.node
	local agg = job.slip.agg
	local over = false
	local wait = nil
	local function finish(result, landedOk, expect)
		if over then return end
		over = true
		if wait ~= nil then wait.done = true end
		inflightDone(n)
		if landedOk then
			agg.retryOk = agg.retryOk + 1
			agg.landed = agg.landed + 1
			for k, text in pairs(expect or {}) do agg.expect[k] = text end
		end
		agg.retryPending = agg.retryPending - 1
		out("RETRY", { { "kind", "slip" }, { "job", job.seq }, { "node", n }, { "result", result } })
		local okF, e = pcall(slipFinish, job)
		if not okF then err("retry", e) end
	end
	local ok, e = pcall(function()
		local r, case, kerb, lp, _, _, mode = slipPlan(job, world, n)
		if r.status ~= "apply" then
			finish(r.status == "skip" and ("skip:" .. tostring(r.reason)) or tostring(r.status), false)
			return
		end
		local it = slipItem(r, n, case, kerb, lp, mode, "retry")
		local b = W().newBatch()
		if not W().addItem(b, "slip_job", job.seq, it, nil) then
			finish("not_built", false)
			return
		end
		-- held from this send (heldNode's timeout counts from it; expireWaits releases it first)
		G.inflightAt[n] = G.frames
		wait = { at = G.frames, job = job, kind = "retry", n = 1, done = false }
		wait.expire = function()
			wait.timedOut = true
			agg.timedOut[n] = true
			agg.timeout = agg.timeout + 1
			finish("timeout", false)
		end
		local sent = W().sendBatch(b, function(success, expect)
			if wait.timedOut then
				-- after expireWaits gave it up (RETRY result=timeout): only logged
				out("LATE", { { "kind", "slip" }, { "job", job.seq }, { "nodes", 1 }, { "success", success == true } })
				return
			end
			finish(success and "landed" or "refused", success == true, expect)
		end)
		if sent == 0 then finish("not_built", false)
		elseif not over then G.waits[#G.waits + 1] = wait end
	end)
	if not ok then
		finish("error", false)
		err("retry", e)
	end
end

--- The end of the slip phase: the same-lane re-checks, and the job's WRITE / verify / lights-off once every
-- part answered (slipFinish).
local function closeSlip(job)
	scheduleRecheck(job.seq, job.slip.recheckSame)
	job.slip.agg.closed = true
	slipFinish(job)
end

--- The job with only its nodes outside game zones (sl_zones.lua), and node -> zone mode of the kept nodes
-- inside a zone. One SKIP line for the nodes left alone (each tallied zone_game).
local function zoneFilter(world, job, t, zones)
	local zoneAb = {}
	if zones == nil or #zones == 0 then return job, zoneAb end
	local keep, skipped, ids, idSet = {}, 0, {}, {}
	for _, n in ipairs(job.nodes) do
		local node = world.node(n)
		local z = node and Zones.zoneAt(zones, node.x, node.y) or nil
		local ab = z and z.ab or nil
		if ab == "game" then
			skipped = skipped + 1
			tallySkip(t, "zone_game")
			local id = Zones.idOf(z)
			if id ~= nil and not idSet[id] then
				idSet[id] = true
				ids[#ids + 1] = id
			end
		else
			if ab ~= nil then zoneAb[n] = ab end
			if ab == "sl_keeplights" then t.zoneKeepLights = t.zoneKeepLights + 1 end
			keep[#keep + 1] = n
		end
	end
	if skipped == 0 then return job, zoneAb end
	local f = { { "kind", "zone" }, { "zone", "game" }, { "job", job.seq }, { "nodes", skipped }, { "reason", "zone_game" } }
	-- SL-3: the id labels of the game zones the skipped nodes lie in (sorted, comma separated)
	if #ids > 0 then
		table.sort(ids)
		f[#f + 1] = { "zid", table.concat(ids, ",") }
	end
	out("SKIP", f)
	return { seq = job.seq, nodes = keep }, zoneAb
end

--- Whether any node of the ring lies in a game zone (the ring is then left alone as a whole).
local function ringInGame(world, ring, zones)
	if zones == nil or #zones == 0 then return false end
	for rn in pairs(ring.nodeSet) do
		if Zones.nodeAb(zones, world, rn) == "game" then return true end
	end
	return false
end

--- Kept nodes (sl_kept.lua, rev 7 "Reset sticks"): the job without the nodes the tool's Reset kept (matched by id
-- or within Kept.R m of their position), as zoneFilter does for game zones. One SKIP kind=kept job= nodes=
-- reason=reset_kept line (each node tallied reset_kept). A kept node matched by position under another id (a
-- rebuild replaced the node) gets its entry moved to the new id (one KEPT add, src=auto), so the mark survives the
-- pruning of gone ids at the next load.
local function keptFilter(world, job, t, idx)
	if idx == nil or (idx.n or 0) == 0 then return job end
	local keep, skipped, rekey = {}, 0, {}
	for _, n in ipairs(job.nodes) do
		local node = world.node(n)
		local e = Kept.match(idx, n, node and node.x, node and node.y)
		if e ~= nil then
			skipped = skipped + 1
			tallySkip(t, "reset_kept")
			if e[1] ~= n and node ~= nil and #rekey < Kept.EVENT_MAX then rekey[#rekey + 1] = { n, node.x, node.y } end
		else
			keep[#keep + 1] = n
		end
	end
	if skipped == 0 then return job end
	out("SKIP", { { "kind", "kept" }, { "job", job.seq }, { "nodes", skipped }, { "reason", "reset_kept" } })
	if #rekey > 0 then
		pcall(function()
			api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", Kept.EVENT_ID, Kept.EV_KEPT, { op = "add", nodes = rekey, src = "auto" }))
		end)
	end
	return { seq = job.seq, nodes = keep }
end

--- Whether any node of the ring is kept (the ring is then left alone as a whole, as with a game zone).
local function ringKept(world, ring, idx)
	if idx == nil or (idx.n or 0) == 0 then return false end
	for rn in pairs(ring.nodeSet) do
		local node = world.node(rn)
		if Kept.match(idx, rn, node and node.x, node and node.y) ~= nil then return true end
	end
	return false
end

--- A job in progress (stepJob): jobIn = { seq, nodes, merged } from pending; phases start -> ring -> slip ->
-- audit -> done. Built up over its frames: the tally, the rings done, the nodes on a ring, the junctions
-- planned for the audit, the slip items and the parts sent (slip.agg).
local function newJob(jobIn)
	local nodeSet = {}
	for _, n in ipairs(jobIn.nodes) do nodeSet[n] = true end
	local mode = Lights.modeFor(G.cfg.freeTurn) -- nil: Off
	local slGlobal = G.cfg.phases == "sl" -- Light phases: Smart Lanes
	-- the existing-junctions pass: the rings done and the nodes on a ring are shared by all its slices (a ring
	-- reached from two slices is planned once)
	local pass = jobIn.mapPass
	return { jobIn = jobIn, seq = jobIn.seq, nodeSet = nodeSet, phase = "start", i = 1, frames = 0, t = newTally(),
		doneRings = pass and pass.doneRings or {}, onRing = pass and pass.onRing or {}, planned = { order = {} },
		ms = { job = 0, job_ring = 0, job_classify = 0, job_write = 0, job_audit = 0 }, wrote = false,
		slip = { mode = mode, slGlobal = slGlobal, anyPlans = slGlobal, items = {}, lightNodes = {}, recheck = {}, recheckSame = {},
			agg = { pending = 0, sent = 0, landed = 0, ok = true, closed = false, finished = false, expect = {}, nodes = {},
				retry = 0, retryOk = 0, retryPending = 0, timeout = 0, timedOut = {} } } }
end

--- The start of a job (its first frame): game-zone nodes left out (zoneFilter, in this frame's world).
local function startJob(job, world)
	-- the zones as they stand when the job starts, for all its frames
	job.zones = G.zones
	-- the kept nodes likewise (sl_kept.lua): left out after the game zones
	job.keptIdx = G.keptIdx
	local j, zoneAb = zoneFilter(world, job.jobIn, job.t, job.zones)
	j = keptFilter(world, j, job.t, job.keptIdx)
	job.job, job.zoneAb = j, zoneAb
	-- touched: the seeds the build changed (not quiet: PLAN.md "Nearby junctions stay as they are")
	job.seeds, job.touched = {}, {}
	local quiet = job.jobIn.quiet or {}
	for _, n in ipairs(j.nodes) do
		job.seeds[n] = true
		if not quiet[n] then job.touched[n] = true end
	end
	perfGui:count("job_nodes", #j.nodes)
	job.phase, job.i = "ring", 1
end

--- One node of the ring phase: the ring through n (when it is new to the job) planned and sent whole in one
-- proposal, all in this frame's world. Returns the ms of the ring's write.
--- The ring layout variant (Rules.RING_VARIANTS) of the zone the ring lies in, else nil: the mode of the first
-- ring node (in ring order) inside a zone of such a mode. Ring nodes in other zones or none: no variant.
local function ringVariant(job, world, ring)
	if job.zones == nil or #job.zones == 0 then return nil end
	for _, rn in ipairs(ring.nodes) do
		local node = world.node(rn)
		local z = node and Zones.zoneAt(job.zones, node.x, node.y) or nil
		if z ~= nil and Rules.RING_VARIANT_SET[z.ab] then return z.ab end
	end
	return nil
end

local function ringStep(job, world, n)
	local t, onRing, doneRings = job.t, job.onRing, job.doneRings
	if onRing[n] then return 0 end
	local ring = Ring.ringThrough(world, n)
	if ring and not doneRings[ring.key] and ringInGame(world, ring, job.zones) then
		doneRings[ring.key] = true
		for rn in pairs(ring.nodeSet) do onRing[rn] = true end
		out("SKIP", { { "ring", ring.key }, { "node", n }, { "reason", "zone_game" } })
		tallySkip(t, "zone_game")
	elseif ring and not doneRings[ring.key] and ringKept(world, ring, job.keptIdx) then
		-- a ring with a junction the tool's Reset kept (sl_kept.lua): the whole ring stays the game's
		doneRings[ring.key] = true
		for rn in pairs(ring.nodeSet) do onRing[rn] = true end
		out("SKIP", { { "ring", ring.key }, { "node", n }, { "reason", "reset_kept" } })
		tallySkip(t, "reset_kept")
	elseif ring and not doneRings[ring.key] then
		-- a ring layout variant zone (Rules.RING_VARIANTS, PLAN.md "Ring layout variants (bench)"): the whole ring
		-- with the zone's rule, every time (all its junctions as seeds); elsewhere the automatic rule on the whole
		-- ring too (Rules.autoSeeds: every arm junction a seed, unless one the build did not touch was edited by
		-- hand), so in both the layout does not depend on the build order (PLAN.md "Whole rings in the automatic pass")
		local variant = ringVariant(job, world, ring)
		local seeds, auto = job.seeds, nil
		if variant ~= nil then
			seeds = {}
			for rn in pairs(ring.nodeSet) do seeds[rn] = true end
		else
			-- the existing-junctions pass (sl_allmode.lua): no junction counts as touched by a build, so every arm
			-- junction must pass the hand-edit guard (Rules.ringForm) before the ring is planned
			local mapPass = job.jobIn.mapPass ~= nil
			-- a quiet seed (a ring junction the build reached only through a replaced segment) counts as not
			-- touched: the ring is still planned whole from it, with the hand-edit guard at that junction too
			auto = Rules.autoSeeds(world, ring, mapPass and {} or job.touched, W().currentConns, heldNode)
			-- a junction the job adds is still being written by a proposal of ours (an earlier job's ring or
			-- lights): this node again in a later frame, read after that write answered (heldNode gives up
			-- INFLIGHT_TIMEOUT frames after its send, so the wait is bounded)
			if auto.wait ~= nil then return 0, auto.wait, ring.key end
			seeds = auto.seeds
			local touched = false
			for rn in pairs(ring.nodeSet) do
				if job.touched[rn] then
					touched = true
					break
				end
			end
			-- a ring with a junction edited by hand and none the build changed: left alone too
			if (mapPass or not touched) and #auto.handEdit > 0 then
				-- a ring with a junction edited by hand: left alone as a whole (no lanes, no split, no lights)
				doneRings[ring.key] = true
				for rn in pairs(ring.nodeSet) do onRing[rn] = true end
				for _, hn in ipairs(auto.handEdit) do
					out("SKIP", { { "ring", ring.key }, { "node", hn }, { "reason", "hand_edit" } })
					tallySkip(t, "hand_edit")
				end
				return 0
			end
		end
		doneRings[ring.key] = true
		for rn in pairs(ring.nodeSet) do onRing[rn] = true end
		if variant ~= nil then t.zoneRing = t.zoneRing + 1 end
		local plan = Rules.planRing(world, ring, seeds, variant or G.cfg.ring, W().currentConns)
		t.rings = t.rings + 1
		-- the default spiral without mid nodes (a ring placed from the construction menu, whose plain nodes the game
		-- joined away; PLAN.md "Smart Lanes adds the mid nodes"): split the stretches' edges first; this job writes no
		-- lanes on the ring, the next pass (a job queued on the split's answer, or the build event of the split itself)
		-- plans it with its new nodes. Never twice in one job (doneRings), at most Split.MAX_PER_RING per ring a session.
		-- (also an sl_rmid2 zone's ring: Rules.SPLIT_VARIANTS; plan.splitWanted)
		if plan.splitWanted then
			local sent, why = 0, nil
			if job.jobIn.noSplit then
				why = "replan"
			elseif not Split.allowed(G.splits, ring.key) then
				why = "cap"
			else
				local views = {}
				for _, rn in ipairs(ring.nodes) do views[rn] = Ring.nodeView(world, ring, rn) end
				local list
				list, why = Split.edges(world, ring, views)
				if list ~= nil then
					for _, it in ipairs(list) do
						if heldNode(it.from) or heldNode(it.to) then why, list = "busy", nil break end
					end
				end
				if list ~= nil then
					local held = {}
					for _, it in ipairs(list) do
						for _, nd in ipairs({ it.from, it.to }) do
							if not held[nd] then
								held[nd] = true
								inflightAdd(nd)
							end
						end
					end
					local key = ring.key
					local junctions = {}
					for _, rn in ipairs(ring.nodes) do
						if views[rn].kind ~= "plain" then junctions[#junctions + 1] = rn end
					end
					local okS, nS, whyS = pcall(W().sendSplit, list, function(success)
						for nd in pairs(held) do inflightDone(nd) end
						out("WRITE", { { "kind", "split" }, { "ring", key }, { "success", success } })
						-- the ring again, with its new nodes (or, refused, with what it has: noSplit then)
						if G.enqueue ~= nil then
							G.enqueue({ seq = job.seq, nodes = junctions, due = G.frames + JOB_DELAY, noSplit = not success,
								mapPass = job.jobIn.mapPass })
						end
					end)
					if okS and (nS or 0) > 0 then
						sent = nS
						G.splits[key] = (G.splits[key] or 0) + 1
						local ids = {}
						for _, it in ipairs(list) do ids[#ids + 1] = tostring(it.seg) end
						out("SPLIT", { { "ring", key }, { "node", key }, { "len", math.floor((ring.length or 0) + 0.5) },
							{ "edges", table.concat(ids, ",") }, { "nodes_added", nS } })
					else
						for nd in pairs(held) do inflightDone(nd) end
						why = okS and (whyS or "not_sent") or ("error:" .. tostring(nS))
					end
				end
			end
			if sent > 0 then
				job.wrote = true
				return 0
			end
			if why ~= nil and why ~= "replan" then
				out("SPLIT", { { "ring", ring.key }, { "node", ring.key }, { "len", math.floor((ring.length or 0) + 0.5) }, { "refused", why } })
			end
		end
		-- sl_rsplit / sl_rmid (PLAN.md "Mid-node spiral (sl_rsplit)", "Mid-node lane changes (sl_rmid)"): one line per
		-- ring, its mid nodes or why it fell back
		-- (the default spiral only: the matched default of 2-lane rings with wide exits has no mid nodes)
		if (variant ~= nil and Rules.MID_VARIANTS[variant]) or (variant == nil and plan.default and plan.defaultWhy == "one_lane_exits") then
			if plan.split ~= nil then
				-- len: the ring's length (m), which tells a roundabout's scale in a log (TESTING.md "DS")
				out("RSPLIT", { { "ring", ring.key }, { "node", ring.key }, { "len", math.floor((ring.length or 0) + 0.5) },
					{ "mids", 0 }, { "fallback", plan.layout }, { "reason", plan.split } })
			else
				local mids = {}
				for _, r in ipairs(plan.nodes) do
					if r.mid then mids[#mids + 1] = tostring(r.node) end
				end
				out("RSPLIT", { { "ring", ring.key }, { "node", ring.key }, { "len", math.floor((ring.length or 0) + 0.5) },
					{ "mids", plan.mids or 0 },
					{ "per_stretch", plan.midsPerStretch or 0 }, { "nodes", table.concat(mids, ",") } })
			end
		end
		-- junctions the build did not touch with connections of neither Smart Lanes nor the engine (a Crossing
		-- Tool edit): left alone, and the ring keeps the build's seeds (matched lanes there, as before)
		if auto ~= nil then
			for _, hn in ipairs(auto.handEdit) do
				out("SKIP", { { "ring", ring.key }, { "node", hn }, { "reason", "hand_edit" } })
				tallySkip(t, "hand_edit")
			end
		end
		for _, r in ipairs(plan.nodes) do
			if (r.status == "apply" or r.status == "same") and r.view and r.view.kind == "arm" then
				plannedAdd(job.planned, r.node, r.conns, r.view, ring)
			end
			if r.status == "apply" then
				t.ringApply = t.ringApply + 1
				local v = r.view
				local f = Rules.withEntry({ { "ring", ring.key }, { "node", r.node }, { "lanes", ring.lanes },
					{ "dir", ring.side == 1 and "ccw" or "cw" }, { "exits", #v.x }, { "entries", #v.e },
					{ "turbo", plan.turbo }, { "fresh", plan.fresh }, { "before", r.before }, { "after", r.after } }, r)
				-- inside a ring layout variant zone only: layout=<mode> (the mode the ring got: sl_rsplit without mid
				-- nodes is written as sl_rspiral, plan.layout, as sl_rmid); their mid nodes also mid=yes
				if variant ~= nil then f[#f + 1] = { "layout", plan.layout or variant } end
				-- the default rule's spiral (a 2-lane ring with one-lane exits, PLAN.md "Default: the mid-node spiral") and
				-- its matched lanes (a 2-lane ring with wide exits, "Default: matched lanes on 2-lane rings with wide exits"):
				-- layout= and why (layout=sl_rmid|sl_rspiral default=one_lane_exits, layout=matched default=two_lane_exits),
				-- outside the zones too
				if variant == nil and plan.default then
					f[#f + 1] = { "layout", plan.layout }
					f[#f + 1] = { "default", plan.defaultWhy }
				end
				if r.mid then f[#f + 1] = { "mid", "yes" } end
				out("APPLY", f)
			elseif r.status == "skip" then
				out("SKIP", { { "ring", ring.key }, { "node", r.node }, { "reason", r.reason } })
				t.ringSkip = t.ringSkip + 1
				tallySkip(t, r.reason)
			elseif r.status == "same" then
				t.ringSame = t.ringSame + 1
				t.same = t.same + 1
				zoneKept(job, world, r.node, "ring", "same", ring.key)
			end
		end
		-- the job's plain ring nodes (no junction there): logged inside zones only
		if job.zones ~= nil and #job.zones > 0 then
			local inPlan = {}
			for _, r in ipairs(plan.nodes) do inPlan[r.node] = true end
			local list = {}
			for rn in pairs(ring.nodeSet) do
				if job.seeds[rn] and not inPlan[rn] then list[#list + 1] = rn end
			end
			table.sort(list)
			for _, rn in ipairs(list) do zoneKept(job, world, rn, "ring", "plain", ring.key) end
		end
		job.wrote = true
		-- lights off ("No lights at roundabouts and ramps") only at the junctions the build touched (a variant zone:
		-- the whole ring, as before): a light the player put at a junction the job only adds stays
		-- the existing-junctions pass changes no lights (a light the player set stays; Save safety), nor does a build
		-- at a quiet junction (one it reached only through a replaced segment)
		local lightSeeds = variant ~= nil and seeds or job.touched
		if job.jobIn.mapPass ~= nil then lightSeeds = {} end
		return sendRing(ring, plan, t, lightSeeds)
	end
	return 0
end

--- The per-job sums of the work spread over its frames (perfJob, ctx gui_job) and the frames it took.
local function recordJob(job)
	local function rec(name, ms) perfJob:stop(name, perfJob:start() - ms) end
	rec("job", job.ms.job)
	rec("job_ring", job.ms.job_ring)
	rec("job_classify", job.ms.job_classify)
	if job.wrote then rec("job_write", job.ms.job_write) end
	if job.audit ~= nil then rec("job_audit", job.ms.job_audit) end
	perfGui:count("job_frames", job.frames)
end

--- A job whose step failed: nodes held by this frame's unsent entries are released, and the parts already
-- sent still log their WRITE (slipFinish) when they answered.
local function abortJob(job)
	if job.fb ~= nil then
		for _, n in ipairs(job.fb.inflight) do inflightDone(n) end
		job.fb = nil
	end
	if job.phase == "slip" then
		job.slip.agg.closed = true
		pcall(slipFinish, job)
	end
	job.phase = "done"
end

--- One frame of the job in progress: node steps while the frame budget lasts (fits), in a world read in this
-- frame (a world from an earlier frame may be stale: other builds, town growth, scripts), then this frame's
-- slip entries in one proposal. Every write is built from reads of the frame it is sent in; what carries over
-- between frames is the job's bookkeeping (rings done, nodes on a ring, the tally, the planned connections the
-- audit compares with). Returns true when the job is done.
local function stepJob(job, t0, steps0)
	job.frames = job.frames + 1
	local world = W().makeWorld()
	local steps = steps0 or 0
	if job.phase == "start" then startJob(job, world) end
	-- the job's zones for all its frames (startJob's snapshot, as job.zoneAb): world.exitFan reads these,
	-- never the zones mirror that may change mid-job
	world.zones = job.zones or {}
	local nodes = job.job.nodes
	while job.phase ~= "done" do
		if job.phase == "ring" then
			if job.i > #nodes then
				job.phase, job.i = "slip", 1
			elseif not fits("ring", t0, steps) then
				break
			else
				local s0 = now()
				local w, waitN, waitRing = ringStep(job, world, nodes[job.i])
				local d = now() - s0
				job.ms.job_ring = job.ms.job_ring + d
				if waitN ~= nil then
					-- the same node again next frame (ringStep: a ring junction it would add is held by a
					-- proposal of ours); one WAIT line per job and ring
					job.waited = job.waited or {}
					if not job.waited[waitRing] then
						job.waited[waitRing] = true
						out("WAIT", { { "kind", "ring" }, { "job", job.seq }, { "ring", waitRing }, { "node", waitN } })
					end
					break
				end
				job.i, steps = job.i + 1, steps + 1
				job.ms.job_write = job.ms.job_write + w
				stepCost("ring", d)
			end
		elseif job.phase == "slip" then
			if job.i > #nodes then
				if job.fb ~= nil then
					local fb = job.fb
					job.fb = nil
					flushSlip(job, fb)
				end
				closeSlip(job)
				if summary(job.jobIn, job.t) then
					-- after every proposal of the job was sent: the audit never delays a write
					local a = { sum = Audit.newSum(), logged = 0 }
					local planned = job.planned
					function a.connsOf(J)
						local p = planned[J]
						return p and p.conns
					end
					job.audit = a
					job.phase, job.i = "audit", 1
				else
					job.phase = "done"
				end
			elseif not fits("slip", t0, steps) then
				break
			else
				local n = nodes[job.i]
				job.i = job.i + 1
				if not job.onRing[n] then
					if job.fb == nil then job.fb = { batch = W().newBatch(), items = {}, inflight = {} } end
					local s0 = now()
					-- one bad node never stops the job: its error is logged, the next node goes on
					local okS, w = pcall(slipStep, job, world, n, job.fb)
					if not okS then
						err("slip_step", w)
						w = 0
					end
					steps = steps + 1
					local d = now() - s0
					job.ms.job_classify = job.ms.job_classify + (d - w)
					job.ms.job_write = job.ms.job_write + w
					if w > 0 then job.wrote = true end
					stepCost("slip", d)
				end
			end
		elseif job.phase == "audit" then
			local order = job.planned.order
			if job.i > #order then
				auditEnd(job)
				job.phase = "done"
			elseif not fits("audit", t0, steps) then
				break
			else
				local s0 = now()
				local n = order[job.i]
				job.i, steps = job.i + 1, steps + 1
				local ok, e = pcall(auditStep, world, job, n)
				local d = now() - s0
				job.ms.job_audit = job.ms.job_audit + d
				stepCost("audit", d)
				if not ok then
					-- as before: a failing audit ends the job's audit (no AUDIT_SUMMARY), never the job's writes
					err("audit", e)
					job.phase = "done"
				end
			end
		end
	end
	-- this frame's slip entries: one proposal, sent in the frame they were built in
	if job.fb ~= nil then
		local fb = job.fb
		job.fb = nil
		flushSlip(job, fb)
	end
	return job.phase == "done"
end

--- The fan of an sl_fan zone's node whose light stands now (recheckFree; its lanes are still the rule's
-- of the write): the fan lanes and the fan plan in one proposal (as slipStep), or, the fan already in
-- place, the fan plan alone (W.planLights). Returns k (1 sent, 0 not) and the reason ("same",
-- "plan_fail:..", a sendConfigs refusal); onDone when a proposal answered.
local function fanRecheck(world, n, onDone)
	local r = Slip.plan(world, n, W().currentConns, { fan = true })
	if not r.fan or (r.status ~= "apply" and r.status ~= "same") then return 0, "plan_fail:" .. tostring(r.reason or r.fanWait or r.status) end
	local lp = { view = r.view, world = world, fan = true }
	if r.status == "same" then return W().planLights(n, lp, "recheck", onDone, nil, true) end
	local fields = { { "src", "recheck" } }
	for _, f in ipairs(Slip.logFields(r)) do fields[#fields + 1] = f end
	out("APPLY", fields)
	local why = nil
	local item = { node = n, conns = r.conns, lightPlan = lp, src = "recheck" }
	local sent = W().sendConfigs("fan_recheck", n, { item }, function(success, expect)
		out("WRITE", { { "kind", "fan" }, { "node", n }, { "success", success }, { "plan", item.planText or "-" } })
		if success then G.verify[#G.verify + 1] = { kind = "slip", job = "fan" .. tostring(n), expect = expect, due = G.frames + VERIFY_DELAY } end
		onDone()
	end, function(_, reason) why = reason end)
	if sent == 0 then return 0, "plan_fail:" .. tostring(why or "none") end
	return 1
end

--- An sl_exitfan zone's node whose light was unknown at its write (recheckFree; its lanes are still the
-- rule's of the write): once a light stands, the exit fan's lanes in one proposal with the kerb turn's
-- phase change (the setting's mode, only into the exit's kerb lane: X.kerbPairs kerbLaneOnly), the game's
-- phases re-pointed (W.remapLights). Returns 1 when sent, else 0 and the reason (the view's exitFanWhy,
-- "same", a sendConfigs refusal); onDone when the proposal answered.
local function exitFanRecheck(world, x, onDone)
	local r = Slip.plan(world, x.node, W().currentConns)
	if not (r.view and r.view.exitFan) then return 0, tostring(r.view and r.view.exitFanWhy or r.status) end
	if r.status ~= "apply" then return 0, tostring(r.status) end
	local fields = { { "src", "recheck" } }
	for _, f in ipairs(Slip.logFields(r)) do fields[#fields + 1] = f end
	exitFanFields(fields)
	out("APPLY", fields)
	local why = nil
	local kerb = x.mode ~= nil and Slip.kerbPairs(r.view) or nil
	local item = { node = x.node, conns = r.conns, src = "recheck" }
	if kerb ~= nil then item.phase = { mode = x.mode, kerb = kerb } end
	local sent = W().sendConfigs("exitfan_recheck", x.node, { item }, function(success, expect)
		out("WRITE", { { "kind", "exit_fan" }, { "node", x.node }, { "success", success } })
		if success then
			G.verify[#G.verify + 1] = { kind = "slip", job = "exitfan" .. tostring(x.node), expect = expect, due = G.frames + VERIFY_DELAY }
		end
		onDone()
	end, function(_, reason) why = reason end)
	if sent == 0 then return 0, "refused:" .. tostring(why or "none") end
	return 1
end

--- A free kerb turn / Smart Lanes phases re-check (scheduleRecheck): frees kerb turns the game locked
-- since the write, or (entries with sl) writes the Smart Lanes plan once a light stands (entries with
-- fan: the fan and its plan, fanRecheck). One node per step while the frame budget lasts (fits; reads and
-- any proposal of a node in one frame, the node's world read in that frame); the RECHECK lines count all
-- its nodes, logged after the last. Returns done, the steps taken.
local function recheckFree(v, t0, steps)
	local c = v.c
	if c == nil then
		c = { i = 1, phases = 0, locked = 0, sent = 0, changed = 0, slN = 0, slPhases = 0, slSent = 0, slSame = 0, slFail = 0,
			slChanged = 0 }
		v.c = c
	end
	local world = nil -- read in this frame, at the first node that needs it
	local used = 0
	while c.i <= #v.nodes do
		if not fits("recheck", t0, steps + used) then return false, used end
		local s0 = now()
		local x = v.nodes[c.i]
		c.i, used = c.i + 1, used + 1
		if x.sl then c.slN = c.slN + 1 end
		if busyNode(x.node) then
			-- a newer write or job on it: that one handles the node
			if x.sl then c.slChanged = c.slChanged + 1 else c.changed = c.changed + 1 end
		elseif Rules.carText(W().currentConns(x.node), x.bus) ~= x.text then
			-- rebuilt or edited since: not ours to change (bus-lane connections do not count, Rules.carText)
			if x.sl then c.slChanged = c.slChanged + 1 else c.changed = c.changed + 1 end
		elseif x.exitFan and (function()
			-- an sl_exitfan node: its fan once a light stands (else the kerb turn as below)
			world = world or W().makeWorld()
			local done = lightSent(x.node)
			local ok, k = pcall(exitFanRecheck, world, x, function() done() end)
			if not ok then err("recheck", k) end
			if not ok or k == 0 then
				done()
				return false
			end
			c.sent = c.sent + 1
			return true
		end)() then
			-- sent: the fan's lanes and phases in one proposal
		elseif x.sl then
			-- the view anew (the junction may have changed around it); a plan only for case X
			world = world or W().makeWorld()
			local okV, view = pcall(Slip.classify, world, x.node)
			local done = lightSent(x.node)
			local ok, k, why = false, 0, "not_x"
			if okV and view and view.case == "X" and x.fan and view.lit == true then
				-- an sl_fan zone whose light came after the write: the fan and its plan in one proposal
				ok, k, why = pcall(fanRecheck, world, x.node, function() done() end)
			elseif okV and view and view.case == "X" then
				ok, k, why = pcall(W().planLights, x.node, { view = view, world = world }, "recheck", function() done() end, nil, true)
			else
				ok = true
			end
			if k == 0 or not ok then done() end
			if not ok then
				err("recheck", k)
			elseif k > 0 then
				c.slPhases, c.slSent = c.slPhases + 1, c.slSent + 1
			elseif why == "same" then
				c.slPhases, c.slSame = c.slPhases + 1, c.slSame + 1
			elseif tostring(why):find("^plan_fail") or why == "not_x" then
				c.slPhases, c.slFail = c.slPhases + 1, c.slFail + 1
				-- no plan: the free kerb turn as before (setting not Off)
				if x.kerb ~= nil then
					local okK, n = pcall(W().kerbLights, x.node, x.kerb, x.mode or Lights.SAFE, "recheck")
					if not okK then err("recheck", n) elseif n > 0 then c.sent = c.sent + 1 end
				end
			end
		elseif x.mode == Lights.LOCK then
			-- an sl_lock zone's node (busy at its write): its kerb turns locked back (sends only on a change)
			local ok, n = pcall(W().kerbLights, x.node, x.kerb, Lights.LOCK, "recheck")
			if not ok then err("recheck", n) elseif n > 0 then c.sent = c.sent + 1 end
		else
			local k = W().kerbLocked(x.node, x.kerb)
			if k ~= nil then c.phases = c.phases + 1 end
			if k ~= nil and k > 0 then
				c.locked = c.locked + 1
				local ok, n = pcall(W().kerbLights, x.node, x.kerb, x.mode or Lights.SAFE, "recheck")
				if not ok then err("recheck", n) elseif n > 0 then c.sent = c.sent + 1 end
			end
		end
		stepCost("recheck", now() - s0)
	end
	if c.slN > 0 then
		out("RECHECK", { { "kind", "phases" }, { "job", v.job }, { "nodes", c.slN }, { "phases", c.slPhases }, { "sent", c.slSent },
			{ "same", c.slSame }, { "fail", c.slFail }, { "changed", c.slChanged } })
	end
	if c.slN < #v.nodes then
		out("RECHECK", { { "kind", "free_turn" }, { "job", v.job }, { "nodes", #v.nodes - c.slN }, { "phases", c.phases },
			{ "locked", c.locked }, { "sent", c.sent }, { "changed", c.changed } })
	end
	return true, used
end

--- One frame's share of a verify entry: a re-check runs whole; a re-read (slip, ring, lights) one node per
-- step while the frame budget lasts (fits), its VERIFY line (the counts of all its nodes) when the last node
-- was read. Returns done, the steps taken.
local function verifyStep(v, t0, steps)
	if v.kind == "recheck" then return recheckFree(v, t0, steps) end
	if v.kind == "lights_late" then return lightsLate(v, t0, steps) end
	if v.list == nil then
		v.list, v.i, v.a, v.b, v.c = {}, 1, 0, 0, 0
		for n in pairs(v.expect) do v.list[#v.list + 1] = n end
	end
	local k = v.kind == "lights" and "verify_lights" or "verify"
	local used = 0
	while v.i <= #v.list do
		if not fits(k, t0, steps + used) then return false, used end
		local s0 = now()
		local n = v.list[v.i]
		v.i, used = v.i + 1, used + 1
		if v.kind == "lights" then
			local done, total, gone = W().verifyLights({ [n] = true }, Lights.OFF)
			v.a, v.b, v.c = v.a + done, v.b + total, v.c + gone
		else
			local same, total = W().verify({ [n] = v.expect[n] })
			v.a, v.b = v.a + same, v.b + total
		end
		stepCost(k, now() - s0)
	end
	if v.kind == "lights" then
		out("VERIFY", { { "kind", "lights" }, { "job", v.job }, { "off", v.a }, { "nodes", v.b }, { "gone", v.c } })
	elseif v.kind == "slip" then
		out("VERIFY", { { "kind", "slip" }, { "job", v.job }, { "same", v.a }, { "nodes", v.b } })
	else
		out("VERIFY", { { "ring", v.ring }, { "same", v.a }, { "nodes", v.b } })
	end
	return true, used
end

--- A new job from the state goes into pending; one that shares a node with a job still waiting there
-- (not started) joins it instead (its nodes added, SUMMARY merged=<seq>), unless that would pass
-- MAX_SEEDS: a node is then planned once, in a world read after both builds, never by two jobs in a row
-- whose first write may not have landed when the second reads.
local function enqueue(job)
	local mine = {}
	for _, n in ipairs(job.nodes) do mine[n] = true end
	for _, p in ipairs(G.pending) do
		local seen, shared = {}, false
		for _, x in ipairs(p.nodes) do
			seen[x] = true
			if mine[x] then shared = true end
		end
		if shared then
			local add = {}
			for _, x in ipairs(job.nodes) do
				if not seen[x] then add[#add + 1] = x end
			end
			if #p.nodes + #add <= MAX_SEEDS then
				for _, x in ipairs(add) do p.nodes[#p.nodes + 1] = x end
				-- quiet stays quiet only where no build of the two changed it
				if p.quiet ~= nil then
					for x in pairs(p.quiet) do
						if mine[x] and not (job.quiet and job.quiet[x]) then p.quiet[x] = nil end
					end
				end
				for _, x in ipairs(add) do
					if job.quiet and job.quiet[x] then
						p.quiet = p.quiet or {}
						p.quiet[x] = true
					end
				end
				-- the later build's nodes get their JOB_DELAY too
				if job.due ~= nil and (p.due == nil or job.due > p.due) then p.due = job.due end
				p.merged = p.merged or {}
				p.merged[#p.merged + 1] = job.seq
				-- a re-plan after a split (noSplit) keeps the merged job from splitting the ring again
				if job.noSplit then p.noSplit = true end
				return
			end
		end
	end
	G.pending[#G.pending + 1] = job
end
G.enqueue = enqueue

--- Slip parts and retries (G.waits) still unanswered INFLIGHT_TIMEOUT frames after their send are given up
-- (the callback never came and sendCommand did not throw): one TIMEOUT line per job, then each one's
-- nodes released (before heldNode's own timeout drops their counts, so nothing is released twice), and
-- the job's WRITE / verify / re-checks / lights-off for what landed (slipFinish). A late callback is
-- ignored (LATE line).
local function expireWaits()
	if #G.waits == 0 then return end
	local keep, gone, jobs, per = {}, {}, {}, {}
	for _, w in ipairs(G.waits) do
		if not w.done then
			if G.frames - w.at >= INFLIGHT_TIMEOUT then
				gone[#gone + 1] = w
				local c = per[w.job]
				if c == nil then
					c = { parts = 0, retries = 0, entries = 0 }
					per[w.job] = c
					jobs[#jobs + 1] = w.job
				end
				if w.kind == "part" then c.parts = c.parts + 1 else c.retries = c.retries + 1 end
				c.entries = c.entries + w.n
			else
				keep[#keep + 1] = w
			end
		end
	end
	G.waits = keep
	if #gone == 0 then return end
	for _, job in ipairs(jobs) do
		local c = per[job]
		out("TIMEOUT", { { "kind", "slip" }, { "job", job.seq }, { "parts", c.parts }, { "retries", c.retries },
			{ "entries", c.entries } })
	end
	for _, w in ipairs(gone) do
		local ok, e = pcall(w.expire)
		if not ok then err("timeout", e) end
	end
	for _, job in ipairs(jobs) do
		local ok, e = pcall(slipFinish, job)
		if not ok then err("timeout", e) end
	end
end

--- SL-5: this GUI state's queued and unanswered work: the job in progress, waiting jobs, lights-off entries,
-- verifies and re-checks (G.verify), refused parts to retry, slip parts and retries awaiting their answer, nodes
-- held by a proposal in flight. The tool's own writes (another Lua state) are not counted.
local function queueLen()
	local n = (G.active ~= nil and 1 or 0) + #G.pending + #G.lightsQ + #G.verify + #G.retryQ + #G.waits
	for _, c in pairs(G.inflight) do
		if type(c) == "number" and c > 0 then n = n + 1 end
	end
	return n
end

--- SL-5: sends { qlen, seen } to the game-script state (EV_QLEN, sl_zones' event channel) when it changed,
-- at most once per QLEN_EVERY frames (the last change goes out at the latest QLEN_EVERY frames later); only
-- while zones are set (and once more after they were cleared, until it reported 0): outside the bench nothing
-- is sent.
local function reportQueue()
	-- only while zones are set (the bench), and until a last report after they were cleared says how it ended
	if (G.zones == nil or #G.zones == 0) and (G.qSent == nil or (G.qSent.n == 0 and G.qSent.seen == (G.lastSeq or 0))) then return end
	local n, seen = queueLen(), G.lastSeq or 0
	if G.qSent ~= nil and G.qSent.n == n and G.qSent.seen == seen then return end
	if G.qAt ~= nil and G.frames - G.qAt < QLEN_EVERY then return end
	local ok = pcall(function()
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", Zones.EVENT_ID, EV_QLEN, { qlen = n, seen = seen }))
	end)
	G.qAt = G.frames
	if ok then G.qSent = { n = n, seen = seen } end
end

--- At load: the kept entries whose node id no longer exists (BASE_NODE gone) are removed (KEPT remove src=prune,
-- in events of Kept.EVENT_MAX). Bounded: one BASE_NODE read per entry (at most Kept.MAX).
local function pruneKept()
	local gone = {}
	for i, e in ipairs(G.kept) do
		if i > Kept.MAX then break end
		local a = Kept.entryOf(e)
		if a ~= nil then
			local okN, bn = pcall(api.engine.getComponent, a[1], api.type.ComponentType.BASE_NODE)
			if okN and bn == nil then gone[#gone + 1] = a end
		end
	end
	if #gone == 0 then return end
	for _, p in ipairs(Kept.payloads("remove", gone, "prune")) do
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", Kept.EVENT_ID, Kept.EV_KEPT, p))
	end
end

---------------------------------------------------------------------------
-- The existing-junctions pass (sl_allmode.lua; PLAN.md "Automatic timing for all lights + first-load welcome"): the
-- welcome's Apply with "Convert all existing junctions to Smart Lanes" ticked stores mpass.seq; this GUI state lists the
-- street nodes once (BASE_NODE_CONFIG, else BASE_NODE, else the octree around the map centre), scans them in
-- time-budgeted frames (AllMode.passStep: a visited set, hard caps) and hands every slice of junctions to the
-- automatic pass as one job (the build path; enqueue), one slice at a time and only while no build job waits. Log:
-- MAPPASS op=start seq= src= list= resume=, op=progress (every PASS_PROGRESS_EVERY slices), op=cap what= max=, op=end
-- seq= reason= slices= junctions= scanned= list= frames=. The end is sent back (SmartLanes.auto op=pass), so a
-- finished pass never runs again; one cut short by quitting runs again at the next load (resume=1).
local MP_POLL_OFF = 120 -- GUI frames between two state reads while Apply automatically is Off (only a pass runs then)

local function mapPassList()
	local CT = api.type.ComponentType
	for _, c in ipairs({ { CT.BASE_NODE_CONFIG, "config" }, { CT.BASE_NODE, "node" } }) do
		if c[1] ~= nil then
			local ok, l = pcall(api.engine.getEntitiesWithComponent, c[1])
			if ok and type(l) == "table" then return l, c[2] end
		end
	end
	local ok, l = pcall(function()
		return api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(0, 0), AllMode.PASS_R, CT.BASE_NODE)
	end)
	if ok and type(l) == "table" then return l, "octree" end
	return nil, "none"
end

local function mapPassPoll(es)
	local first = not G.mpPolled
	G.mpPolled = true
	if G.mp ~= nil or type(es) ~= "table" then return end
	local seq = AllMode.passWanted(es)
	if seq == nil or seq == G.mpDone then return end
	local list, src = mapPassList()
	local p = AllMode.newPass(seq, list, src)
	p.doneRings, p.onRing, p.frame0, p.n = {}, {}, G.frames, 0
	G.mp = p
	out("MAPPASS", { { "op", "start" }, { "seq", seq }, { "src", src }, { "list", list and #list or 0 },
		{ "resume", first and 1 or 0 } })
	if list ~= nil and #list > AllMode.PASS_LIST_MAX then
		out("MAPPASS", { { "op", "cap" }, { "seq", seq }, { "what", "list" }, { "max", AllMode.PASS_LIST_MAX }, { "list", #list } })
	end
end

local function isJunction(n)
	local ok, ss = pcall(function() return api.engine.system.streetSystem.getNodeStreetSegments(n) end)
	if not ok or type(ss) ~= "table" then return false end
	local c = 0
	for _ in ipairs(ss) do c = c + 1 end
	return c >= AllMode.PASS_MIN_SEGS
end

--- One frame of the pass: a slice when no job runs or waits, the end once the last slice's job is done.
local function mapPassStep()
	local p = G.mp
	if p == nil or G.active ~= nil or #G.pending > 0 then return end
	if p.phase == "scan" then
		local slice = AllMode.passStep(p, isJunction, now)
		if slice ~= nil then
			p.n = p.n + 1
			enqueue({ seq = "m" .. p.n, nodes = slice, due = G.frames, mapPass = p })
			if p.n % AllMode.PASS_PROGRESS_EVERY == 0 then
				out("MAPPASS", { { "op", "progress" }, { "seq", p.seq }, { "slices", p.slices }, { "junctions", p.junctions },
					{ "scanned", p.scanned }, { "list", #p.list }, { "frames", G.frames - p.frame0 } })
			end
		end
		if p.phase ~= "done" then return end
		if p.capped == "cap_junctions" then
			out("MAPPASS", { { "op", "cap" }, { "seq", p.seq }, { "what", "junctions" }, { "max", AllMode.PASS_JUNCTIONS_MAX } })
		end
		-- the last slice (if any) runs first; the end is logged once its job is done
		if #G.pending > 0 then return end
	end
	out("MAPPASS", { { "op", "end" }, { "seq", p.seq }, { "reason", p.reason }, { "slices", p.slices },
		{ "junctions", p.junctions }, { "scanned", p.scanned }, { "list", #p.list }, { "frames", G.frames - p.frame0 } })
	G.mp, G.mpDone = nil, p.seq
	pcall(function()
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", Auto.EVENT_ID, Auto.EV_AUTO,
			{ op = "pass", phase = "done", seq = p.seq, src = "auto" }))
	end)
end
G.mapPassStep = mapPassStep

local function guiBody(state)
	G.frames = G.frames + 1
	if not G.init then
		G.init = true
		-- this save's in-game settings (sl_settings.lua) before the first decode
		local s0 = state and state:get()
		local zs = type(s0) == "table" and s0 or {}
		pcall(Settings.setMirror, zs.sseq, zs.sset, zs.amode)
		G.cfg = settings()
		G.setVer = Settings.mirror.version
		-- the settings of this load, once (FLOW.md: the traffic report splits runs by them), and again with src=save
		-- whenever an in-game setting changes them (below)
		-- SL-2: lights= the "No lights at roundabouts and ramps" setting (on | off)
		out("MODE", { { "phases", G.cfg.phases }, { "free_turn", G.cfg.freeTurn }, { "lights", G.cfg.lights and "on" or "off" } })
		if not G.cfg.mapEditor then
			-- the zones of this load (sl_zones.lua), once: a reload keeps them (saved state)
			G.zseq = zs.zseq
			G.zones = type(zs.zones) == "table" and zs.zones or nil
			W().zones = G.zones -- worlds see them (sl_write world.exitFan: sl_exitfan zones)
			out("ZONES", { { "op", "loaded" }, { "n", count(G.zones) }, { "run", zs.zrun or "-" } })
			-- the kept nodes (sl_kept.lua), once; entries whose node is gone are pruned (Apply automatically On
			-- only: a node a rebuild replaced was moved to its new id by the job that saw it, keptFilter)
			G.kseq = zs.kseq
			G.kept = type(zs.kept) == "table" and zs.kept or nil
			G.keptIdx = Kept.index(G.kept)
			if G.cfg.active and G.kept ~= nil then
				local ok, e = pcall(pruneKept)
				if not ok then err("kept", e) end
			end
		end
	end
	if G.cfg.mapEditor then return end
	-- Apply automatically Off: nothing but the existing-junctions pass the welcome asked for (polled every MP_POLL_OFF
	-- frames; no build jobs are made then)
	if not G.cfg.active and G.mp == nil and G.frames < G.nextPoll then return end
	expireWaits()
	-- new jobs: the state is read every JOB_POLL frames (a job waits JOB_DELAY frames anyway), and copied whole
	-- (state:get) only when its change stamp moved (Auto.readStamp: a few state_native finds; unreadable: every poll)
	local es = nil
	local poll = G.frames >= G.nextPoll
	if poll then
		G.nextPoll = G.frames + (G.cfg.active and JOB_POLL or MP_POLL_OFF)
		local stamp = Auto.readStamp(api)
		if stamp ~= nil and stamp == G.stamp then
			poll = false
		else
			G.stamp = stamp
		end
	end
	if poll then
		es = state and state:get()
		local okP, eP = pcall(mapPassPoll, es)
		if not okP then err("map_pass", eP) end
		local seq = (type(es) == "table" and es.seq) or 0
		if G.lastSeq == nil then G.lastSeq = seq end -- jobs saved before this load are old
		-- the zones mirror, re-read only when they changed. A zones event handled before a build is in
		-- the same read as that build's job (or an earlier one): the job never sees older zones.
		if type(es) == "table" and es.zseq ~= G.zseq then
			G.zseq = es.zseq
			G.zones = type(es.zones) == "table" and es.zones or nil
			W().zones = G.zones
		end
		if type(es) == "table" and es.kseq ~= G.kseq then
			G.kseq = es.kseq
			G.kept = type(es.kept) == "table" and es.kept or nil
			G.keptIdx = Kept.index(G.kept)
		end
		-- the in-game settings (sl_settings.lua): re-derived when the values in force changed (this read, or the
		-- write path's own poll, sl_write W.modRaw); a job planned from now on uses them
		pcall(Settings.setMirror, type(es) == "table" and es.sseq or nil,
			type(es) == "table" and es.sset or nil, type(es) == "table" and es.amode or nil)
		if Settings.mirror.version ~= G.setVer then
			G.setVer = Settings.mirror.version
			local active, editor = G.cfg.active, G.cfg.mapEditor
			G.cfg = settings()
			G.cfg.active, G.cfg.mapEditor = active, editor
			out("MODE", { { "phases", G.cfg.phases }, { "free_turn", G.cfg.freeTurn }, { "lights", G.cfg.lights and "on" or "off" },
				{ "src", "save" } })
		end
	end
	if type(es) == "table" then
		for _, job in ipairs(es.jobs or {}) do
			if job.seq > G.lastSeq then
				G.lastSeq = job.seq
				local nodes = {}
				for _, n in ipairs(job.nodes or {}) do nodes[#nodes + 1] = n end
				-- the existing nodes the build did not change (handleBuild quietNodes)
				local quiet = nil
				for _, n in ipairs(type(job.quiet) == "table" and job.quiet or {}) do
					quiet = quiet or {}
					quiet[n] = true
				end
				enqueue({ seq = job.seq, nodes = nodes, due = G.frames + JOB_DELAY, quiet = quiet })
			end
		end
	end
	reportQueue()
	if G.mp ~= nil and #G.lightsQ == 0 then
		local okM, eM = pcall(mapPassStep)
		if not okM then
			-- a failing pass ends (never restarted in this session: mpDone)
			err("map_pass", eM)
			if G.mp ~= nil then G.mpDone = G.mp.seq end
			G.mp = nil
		end
	end
	if G.active == nil and #G.pending == 0 and #G.verify == 0 and #G.lightsQ == 0 and #G.retryQ == 0 then return end
	local t0 = now()
	-- lights-off first (lightsOff): queued after a write answered
	local lsteps = 0
	while #G.lightsQ > 0 do
		local okL, done, used = pcall(lightsStep, G.lightsQ[1], t0, lsteps)
		if not okL then err("lights", done) end
		lsteps = lsteps + (okL and used or 1)
		if okL and not done then break end
		table.remove(G.lightsQ, 1)
	end
	-- entries of refused slip parts, one per step, each from this frame's reads (retryStep)
	local rworld = nil
	while #G.retryQ > 0 and fits("retry", t0, lsteps) do
		local s0 = now()
		local x = table.remove(G.retryQ, 1)
		local okW, w = pcall(function() return rworld or W().makeWorld() end)
		if okW then
			rworld = w
			retryStep(x, w)
		else
			-- no world this frame: the entry is dropped (its node released), never retried again
			err("retry", w)
			retryStep(x, nil)
		end
		lsteps = lsteps + 1
		stepCost("retry", now() - s0)
	end
	-- one job at a time, in steps over frames (stepJob); the next one starts when it is done; none while
	-- lights-off are still queued
	-- The first due job waits while a proposal of ours naming one of its nodes is unanswered (the last
	-- frame's slip part, a ring, lights-off of the job before): its reads would miss that write.
	if G.active == nil and #G.lightsQ == 0 then
		for i, job in ipairs(G.pending) do
			if G.frames >= job.due then
				local free = true
				for _, n in ipairs(job.nodes) do
					if heldNode(n) then
						free = false
						break
					end
				end
				if free then
					table.remove(G.pending, i)
					G.active = newJob(job)
				end
				break
			end
		end
	end
	local job = G.active
	if job ~= nil and #G.lightsQ == 0 then
		local tStep = perfGui:start()
		local s0 = now()
		G.inJob = true
		local ok, res = pcall(stepJob, job, t0, lsteps)
		G.inJob = false
		job.ms.job = job.ms.job + (now() - s0)
		perfGui:stop("job_step", tStep)
		if not ok then
			err("job" .. job.seq, res)
			pcall(abortJob, job)
		end
		if not ok or res then
			G.active = nil
			recordJob(job)
		end
	end
	-- verifies share the frame's budget (at least one node per frame, so they never starve behind a long
	-- queue of jobs); re-checks may send light proposals, so they wait while a job is in progress (as when a
	-- job ran in one frame: never between its writes)
	local i, steps = 1, lsteps
	while i <= #G.verify do
		local v = G.verify[i]
		if G.frames >= v.due and not (v.kind == "recheck" and G.active ~= nil) then
			local k = v.kind == "recheck" and "recheck" or (v.kind == "lights" and "verify_lights" or "verify")
			if not fits(k, t0, steps) then break end
			local tVerify = perfGui:start()
			local ok, done, used = pcall(verifyStep, v, t0, steps)
			perfGui:stop("verify", tVerify)
			if not ok then err("verify", done) end
			if not ok or done then table.remove(G.verify, i) else i = i + 1 end
			steps = steps + (ok and used or 1)
		else
			i = i + 1
		end
	end
end

function data()
return {
	update = function(_userParams, state, _dt)
		local t0 = perf:start()
		local ok, e = pcall(doUpdate, state)
		perf:stop("update", t0)
		if not ok then err("update", e) end
	end,
	handleEvent = function(_userParams, state, _src, id, name, param)
		local t0 = perf:start()
		local ok, e = pcall(doHandleEvent, state, id, name, param)
		perf:stop("event", t0)
		if not ok then err("handleEvent", e) end
	end,
	guiUpdate = function(_userParams, state, _guiState)
		local t0 = perfGui:start()
		local ok, e = pcall(guiBody, state)
		perfGui:stop("gui_update", t0)
		if not ok then err("guiUpdate", e) end
	end,
}
end

perf:phase("init", perfInit)
