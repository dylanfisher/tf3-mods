-- Smart Lanes game script functions (registered by sl_lanes.gs.lua). Phase 1: automatic roundabout
-- lanes. plans/square_smart_lanes/PLAN.md explains the design, TESTING.md the in-game checks.
--
-- Engine thread:
--   update      lazy subscription to onPostBuildProposal (no lifecycle event reaches a mod added to
--               an old save); drops jobs nobody picked up (ttl), so the saved state stays empty.
--   handleEvent player builds that add street segments: the nodes the build added or changed go
--               into a job in the game-script state. Builds that only change node configs (our own
--               write, the Crossing Tool) are ignored, so we never loop. No sendCommand here: it
--               asserts !m_betweenChanges inside a build event (square_full_refund refund.script.tl:345-347).
-- GUI thread:
--   guiUpdate   picks up new jobs, finds one-way rings through the job's nodes (sl_ring), computes the
--               connections (sl_rules) and sends one node-config proposal per ring from the GUI thread;
--               then the job's other nodes that are slip-lane junctions (sl_slip: diverge / merge of a
--               slip lane, splitter leg or ramp) get the slip rule, one proposal for all of them
--               with a callback (the pattern of .cache/subscribed/undo_tf3_test/content/undo/
--               tool_probe.script.lua:118-135; a callback from the engine update fails, docs/findings.md).
--
-- The read / write path (live world, current connections, LaneConnection construction, the
-- proposal) is sl_write.lua, shared with the Phase 2 road tool (sl_tool.script.lua).
--
-- Game-script state (saved with the game, tiny and normally empty): { seq = n, jobs = { {seq, ttl, nodes} } }.
-- Exports through data(): a .script.lua that returns a table fails in game ("Expected table at path").
-- Log lines start with [SQRL]: one APPLY line per changed node, SKIP for ring nodes left alone,
-- WRITE / VERIFY per ring, ERROR (at most 20 per session). Slip nodes: APPLY / SKIP / WRITE /
-- VERIFY with kind=slip (SKIP only for slip candidates that do not fit, not for every plain node).
--
-- SQPERF (plans/sqperf/README.md): this file loads in the engine Lua states and the GUI one.
-- Instrument `perf` (ctx gs): load time of the state (phase=init), sections update and event;
-- `perfGui` (ctx gui): gui_update with job / verify nested. Slow calls are always logged; the
-- "Debug: performance log" setting (sqperf_log) adds a 30 s summary. Local counters only.

local sqperf = ug_require "square_smart_lanes::/sqperf/square_smart_lanes.lua"
local perf = sqperf.new({ mod = "square_smart_lanes", ctx = "gs", paramKey = "sqperf_log", first = { "update" } })
local perfGui = sqperf.new({ mod = "square_smart_lanes", ctx = "gui", paramKey = "sqperf_log", first = { "gui_update" } })
local perfInit = perf:start()

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"

local EV_POST = "onPostBuildProposal"
local MAX_JOBS = 3
local MAX_SEEDS = 160      -- nodes per job
local JOB_TTL = 300        -- engine updates a job stays in the state
local JOB_SWEEP = 10       -- engine updates between reads of the state (expiring jobs)
local JOB_POLL = 5         -- GUI frames between reads of the state (new jobs)
local JOB_DELAY = 10       -- GUI frames after a job appears before it is processed
local VERIFY_DELAY = 30    -- GUI frames after a write before the nodes are re-read

local function out(kind, fields)
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

local function settings()
	local raw, all = modParams()
	local cfg = Rules.fromModParams(raw)
	local g = all and all[""]
	cfg.mapEditor = type(g) == "table" and g.isMapEditor == true
	cfg.active = cfg.auto and cfg.ring ~= "game" and not cfg.mapEditor
	return cfg
end

---------------------------------------------------------------------------
-- Engine thread

local E = { cfg = nil, ticks = 0 }

local function doUpdate(state)
	if E.cfg == nil then E.cfg = settings() end
	if not E.cfg.active then return end
	if not state:hasEventSubscriptions() then
		state:subscribeToNoEvents()
		state:subscribeToEvent(EV_POST)
	end
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
		state:set(s)
	end
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
	s.jobs[#s.jobs + 1] = { seq = s.seq, ttl = JOB_TTL, nodes = seeds }
	while #s.jobs > MAX_JOBS do table.remove(s.jobs, 1) end
	state:set(s)
	perf:count("jobs")
end

local function doHandleEvent(state, id, name, param)
	if id ~= "apply_command" or name ~= EV_POST then return end
	if E.cfg == nil then E.cfg = settings() end
	if not E.cfg.active then return end
	handleBuild(state, param)
end

---------------------------------------------------------------------------
-- GUI thread

local G = { init = false, cfg = nil, frames = 0, nextPoll = 0, lastSeq = nil, pending = {}, verify = {}, w = nil }

--- The shared GUI-thread read / write path (sl_write.lua), made on first use: `api` is read at
-- call time, so the offline tests can load this file with a fake api.
local function W()
	if G.w == nil then G.w = Write.new(api, out) end
	return G.w
end

local function sendRing(ring, plan)
	local items = {}
	for _, r in ipairs(plan.nodes) do
		if r.status == "apply" then items[#items + 1] = { node = r.node, conns = r.conns } end
	end
	if #items == 0 then return end
	local key = ring.key
	-- the re-read is timed from the callback: with several rings in one build (Magic Roundabout)
	-- the commands queue, and a fixed delay from the send re-read before they were applied
	W().sendConfigs("ring", key, items, function(success, expect, nodes)
		out("WRITE", { { "ring", key }, { "nodes", nodes }, { "success", success } })
		if success then
			G.verify[#G.verify + 1] = { ring = key, expect = expect, due = G.frames + VERIFY_DELAY }
		end
	end)
end

--- Slip-lane junctions among the job's nodes that are not on a ring: one proposal for all.
local function processSlips(world, job, onRing)
	local items = {}
	for _, n in ipairs(job.nodes) do
		if not onRing[n] then
			local r = Slip.plan(world, n, W().currentConns)
			if r.status == "apply" then
				out("APPLY", Slip.logFields(r))
				items[#items + 1] = { node = n, conns = r.conns }
			elseif r.status == "skip" then
				out("SKIP", { { "kind", "slip" }, { "node", n }, { "reason", r.reason } })
			end
		end
	end
	if #items == 0 then return end
	local key = job.seq
	W().sendConfigs("slip_job", key, items, function(success, expect, nodes)
		out("WRITE", { { "kind", "slip" }, { "job", key }, { "nodes", nodes }, { "success", success } })
		if success then
			G.verify[#G.verify + 1] = { kind = "slip", job = key, expect = expect, due = G.frames + VERIFY_DELAY }
		end
	end)
end

local function processJob(job)
	local world = W().makeWorld()
	local seeds = {}
	for _, n in ipairs(job.nodes) do seeds[n] = true end
	local doneRings, onRing = {}, {}
	for _, n in ipairs(job.nodes) do
		if not onRing[n] then
			local ring = Ring.ringThrough(world, n)
			if ring and not doneRings[ring.key] then
				doneRings[ring.key] = true
				for rn in pairs(ring.nodeSet) do onRing[rn] = true end
				local plan = Rules.planRing(world, ring, seeds, G.cfg.ring, W().currentConns)
				for _, r in ipairs(plan.nodes) do
					if r.status == "apply" then
						local v = r.view
						out("APPLY", { { "ring", ring.key }, { "node", r.node }, { "lanes", ring.lanes },
							{ "dir", ring.side == 1 and "ccw" or "cw" }, { "exits", #v.x }, { "entries", #v.e },
							{ "turbo", plan.turbo }, { "fresh", plan.fresh }, { "before", r.before }, { "after", r.after } })
					elseif r.status == "skip" then
						out("SKIP", { { "ring", ring.key }, { "node", r.node }, { "reason", r.reason } })
					end
				end
				sendRing(ring, plan)
			end
		end
	end
	processSlips(world, job, onRing)
end

local function verify(v)
	local same, total = W().verify(v.expect)
	if v.kind == "slip" then
		out("VERIFY", { { "kind", "slip" }, { "job", v.job }, { "same", same }, { "nodes", total } })
	else
		out("VERIFY", { { "ring", v.ring }, { "same", same }, { "nodes", total } })
	end
end

local function guiBody(state)
	G.frames = G.frames + 1
	if not G.init then
		G.init = true
		G.cfg = settings()
	end
	if not G.cfg.active then return end
	-- new jobs: the state is read every JOB_POLL frames (a job waits JOB_DELAY frames anyway)
	local es = nil
	if G.frames >= G.nextPoll then
		G.nextPoll = G.frames + JOB_POLL
		es = state and state:get()
		local seq = (type(es) == "table" and es.seq) or 0
		if G.lastSeq == nil then G.lastSeq = seq end -- jobs saved before this load are old
	end
	if type(es) == "table" then
		for _, job in ipairs(es.jobs or {}) do
			if job.seq > G.lastSeq then
				G.lastSeq = job.seq
				local nodes = {}
				for _, n in ipairs(job.nodes or {}) do nodes[#nodes + 1] = n end
				G.pending[#G.pending + 1] = { seq = job.seq, nodes = nodes, due = G.frames + JOB_DELAY }
			end
		end
	end
	if #G.pending == 0 and #G.verify == 0 then return end
	-- at most one job per frame: each one may search rings around up to MAX_SEEDS nodes
	for i, job in ipairs(G.pending) do
		if G.frames >= job.due then
			table.remove(G.pending, i)
			local tJob = perfGui:start()
			local ok, e = pcall(processJob, job)
			perfGui:stop("job", tJob)
			if not ok then err("job" .. job.seq, e) end
			break
		end
	end
	local i = 1
	while i <= #G.verify do
		local v = G.verify[i]
		if G.frames >= v.due then
			table.remove(G.verify, i)
			local tVerify = perfGui:start()
			local ok, e = pcall(verify, v)
			perfGui:stop("verify", tVerify)
			if not ok then err("verify", e) end
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
