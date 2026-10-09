-- DEV ONLY (never upload): Roundabouts lane probe, game-script functions (registered by
-- lanes.gs.lua). Logs [SQRB-LANES] lines to stdout.txt; plans/square_roundabouts/PHASE6.md
-- explains every line kind, TESTING.md "Phase 6a lane probe" how to run it.
--
-- Engine thread (update / handleEvent):
--   update      lazy subscription (no lifecycle event reaches a mod added to an old save):
--               onPostBuildProposal (apply_command) and the GUI event builder.proposalApply
--               (as base game_mechanics/company/company.script.tl:387-389; guiHandleEvent only
--               fires for subscribed events, .cache/subscribed/parallel_tracks_1/.../
--               parallel_tracks.script.lua:93-99).
--   handleEvent onPostBuildProposal, player builds only: BUILD / CON / NCFG lines (payload shape,
--               constructions with file name, position, bbox and sqrb_* params, node configs the
--               proposal adds, e.g. the vanilla Crossing Tool's). For one of our constructions (or
--               the vanilla roundabout) a job {seq, entry, x, y, r} goes into the game-script state.
--               param = {Proposal, ProposalData, {Entity}, playerInitiated}: square_full_refund
--               refund.script.tl:438-447, base achievements.script.tl:294-328.
-- GUI thread (guiUpdate / guiHandleEvent):
--   guiUpdate   reads the jobs from the (read-only) engine state, waits JOB_DELAY s, then scans the
--               circle for street nodes (octree) and logs every junction node: NODE, SEG, CFG, CONN.
--               With the "Write experiment" param On it then removes one set of ring->arm
--               connections at one ring node (lanes_logic.chooseExperiment) with a node-config
--               proposal (the approach of .cache/subscribed/undo_tf3_test/content/undo/
--               tool_probe.script.lua:27-44, 120-135 and move_it.script.tl:2466-2498), and re-reads
--               that node later (PERSIST lines). Sent from the GUI thread with a callback, as
--               undo_tf3_test does: a callback from the engine update fails ("Callbacks are
--               currently disallowed", docs/findings.md), and sendCommand inside a build event
--               asserts !m_betweenChanges (square_full_refund refund.script.tl:345-347).
--   guiHandleEvent builder.proposalApply: GUIEV line (what the GUI side sees of a build).
--
-- Game-script state (saved with the game, tiny): { builds = n, seq = n, jobs = {last 6 jobs} }.
-- Exports through data(): a .script.lua that returns a table fails in game ("Expected table at path").

local L = ug_require "square_roundabouts_lanes_probe::/sqrb_lanes/lanes_logic.lua"

local EV_POST = "onPostBuildProposal"
local EV_GUI_APPLY = "builder.proposalApply"
local MAX_JOBS = 6
local JOB_DELAY = 2           -- s after the build before the GUI scans
local RECHECK = { 2, 15, 60 } -- s after a write: re-read the node
local RECHECK_BUILDS = 12     -- and after each of the next N player builds
local MAX_NODES = 60          -- junction nodes logged per job
local MAX_WRITES = 4          -- write experiments per session
local GUIEV_BUDGET = 40
local NCFG_CONNS_MAX = 64
local RING_SEGS_FALLBACK = 4  -- ring-template segments in one build that count as a roundabout

local function out(kind, fields)
	local text = L.line(kind, fields)
	if log and log.message then log.message(text) else print(text) end
end

local errors = 0
local function err(where, e)
	errors = errors + 1
	if errors > 20 then return end -- a per-frame error must not flood stdout.txt
	out("ERROR", { { "where", where }, { "err", e } })
end

local function modParams()
	local ok, all = pcall(api.engine.config.getModParams)
	if ok and type(all) == "table" then return all[L.MOD_ID], all end
	return nil, nil
end

local function isMapEditor()
	local _, all = modParams()
	local g = all and all[""]
	return type(g) == "table" and g.isMapEditor == true
end

---------------------------------------------------------------------------
-- Engine thread

local function doUpdate(state)
	if state:hasEventSubscriptions() then return end
	if isMapEditor() then return end
	state:subscribeToNoEvents()
	state:subscribeToEvent(EV_POST)
	state:subscribeToEvent(EV_GUI_APPLY)
	local raw = modParams()
	local cfg = L.fromModParams(raw)
	out("INFO", { { "msg", "DEV_ONLY_lane_probe_subscribed" }, { "write", cfg.write } })
end

local function ncfgLines(sp, build)
	local list = sp and sp.nodeConfigsToAdd
	local removed = sp and sp.nodeConfigsToRemove
	if L.count(list) == 0 and L.count(removed) == 0 then return end
	out("NCFG_REMOVE", { { "build", build }, { "n", L.count(removed) }, { "nodes", L.idsText(removed, 12) } })
	for i, e in ipairs(list or {}) do
		local comp = e.comp
		local conns = comp and comp.laneConnections
		local n = L.count(conns)
		out("NCFG", { { "build", build }, { "i", i }, { "node", e.entity }, { "nConns", n },
			{ "userModLanes", comp and comp.userModifiedLaneConnections },
			{ "userModLights", comp and comp.userModifiedTrafficLightStates },
			{ "lightPref", comp and comp.trafficLightPreference },
			{ "crosswalks", L.count(comp and comp.crosswalks) } })
		local k = 0
		for _, c in ipairs(conns or {}) do
			k = k + 1
			if k > NCFG_CONNS_MAX then break end
			out("NCFG_CONN", { { "build", build }, { "node", e.entity }, { "s0", c.segment0 }, { "l0", c.lane0 },
				{ "s1", c.segment1 }, { "l1", c.lane1 }, { "road", c.withRoad }, { "tram", c.withTram } })
		end
	end
end

local function handleBuild(state, param)
	local p = param
	if type(p) ~= "table" then return end
	local playerInitiated = p[4]
	if playerInitiated ~= true then return end
	local proposal, data, result = p[1], p[2], p[3]
	local s = state:get() or {}
	s.builds = (s.builds or 0) + 1
	s.seq = s.seq or 0
	s.jobs = s.jobs or {}
	local build = s.builds

	local sp = proposal and proposal.proposal
	local toAdd = proposal and proposal.toAdd
	out("BUILD", {
		{ "build", build }, { "shape", L.shapeText(p) },
		{ "toAdd", L.count(toAdd) }, { "toRemove", L.count(proposal and proposal.toRemove) },
		{ "addedNodes", L.count(sp and sp.addedNodes) }, { "addedSegs", L.count(sp and sp.addedSegments) },
		{ "removedNodes", L.count(sp and sp.removedNodes) }, { "removedSegs", L.count(sp and sp.removedSegments) },
		{ "ncfgAdd", L.count(sp and sp.nodeConfigsToAdd) }, { "ncfgRemove", L.count(sp and sp.nodeConfigsToRemove) },
		{ "result", L.idsText(result, 8) }, { "costs", data and data.costs },
		{ "toAddData", L.count(data and data.toAddData) },
	})

	-- a few added nodes / segments (ids are placeholders in a post event, refund.script.tl:125-127)
	local k = 0
	for _, n in ipairs((sp and sp.addedNodes) or {}) do
		k = k + 1
		if k > 4 then break end
		local pos = n.comp and n.comp.position
		out("ADDNODE", { { "build", build }, { "entity", n.entity },
			{ "x", pos and L.num(pos.x) }, { "y", pos and L.num(pos.y) }, { "z", pos and L.num(pos.z) } })
	end
	k = 0
	for _, sg in ipairs((sp and sp.addedSegments) or {}) do
		k = k + 1
		if k > 4 then break end
		local c = sg.comp
		out("ADDSEG", { { "build", build }, { "entity", sg.entity }, { "type", sg.type },
			{ "node0", c and c.node0 }, { "node1", c and c.node1 },
			{ "tpl", c and L.shortTemplate(c.roadTemplate) } })
	end

	ncfgLines(sp, build)

	local jobs = 0
	for i, con in ipairs(toAdd or {}) do
		local file = con.fileName
		local entry = L.entryOf(file)
		local bbox = nil
		local okB, b = pcall(function() return data.toAddData[i].boundingVolume.bbox end)
		if okB then bbox = b end
		local x, y, r, src = L.searchCircle(bbox, con.transf)
		local tx, ty, tz = L.translation(con.transf)
		local params = nil
		local okP, pr = pcall(function() return con.construction.params end)
		if okP then params = pr end
		local frozenN, frozenE = 0, 0
		pcall(function()
			frozenN = L.count(con.construction.frozenNodes)
			frozenE = L.count(con.construction.frozenEdges)
		end)
		out("CON", { { "build", build }, { "i", i }, { "file", file }, { "entry", entry or "-" },
			{ "tx", L.num(tx) }, { "ty", L.num(ty) }, { "tz", L.num(tz) },
			{ "cx", L.num(x) }, { "cy", L.num(y) }, { "r", L.num(r) }, { "src", src or "none" },
			{ "frozenNodes", frozenN }, { "frozenEdges", frozenE },
			{ "params", L.paramsText(params) } })
		if entry and x then
			s.seq = s.seq + 1
			s.jobs[#s.jobs + 1] = { seq = s.seq, entry = entry, x = x, y = y, r = r, build = build }
			while #s.jobs > MAX_JOBS do table.remove(s.jobs, 1) end
			out("JOB", { { "seq", s.seq }, { "entry", entry }, { "build", build } })
			jobs = jobs + 1
		end
	end
	-- Fallback: no known construction, but the build adds ring-template streets (a dissolved
	-- roundabout reported as plain streets?): scan around the added nodes.
	if jobs == 0 then
		local ringSegs = 0
		for _, sg in ipairs((sp and sp.addedSegments) or {}) do
			if sg.comp and L.isRingTemplate(sg.comp.roadTemplate) then ringSegs = ringSegs + 1 end
		end
		if ringSegs >= RING_SEGS_FALLBACK then
			local pts = {}
			for _, n in ipairs((sp and sp.addedNodes) or {}) do
				local pos = n.comp and n.comp.position
				if pos then pts[#pts + 1] = { x = pos.x, y = pos.y } end
			end
			local x, y, r = L.circleFromPoints(pts)
			if x then
				s.seq = s.seq + 1
				s.jobs[#s.jobs + 1] = { seq = s.seq, entry = "streets", x = x, y = y, r = r, build = build }
				while #s.jobs > MAX_JOBS do table.remove(s.jobs, 1) end
				out("JOB", { { "seq", s.seq }, { "entry", "streets" }, { "build", build }, { "ringSegs", ringSegs } })
			end
		end
	end
	state:set(s)
end

local function doHandleEvent(state, id, name, param)
	if id == "apply_command" and name == EV_POST then handleBuild(state, param) end
end

---------------------------------------------------------------------------
-- GUI thread

-- GUI-thread module state (not saved): one per Lua state, i.e. per game load.
local G = {
	init = false, cfg = nil, frames = 0, lastSeq = nil, lastBuilds = nil,
	pending = {}, watches = {}, writes = 0, guiEvents = 0,
}

local function now()
	local ok, t = pcall(os.time)
	if ok and type(t) == "number" then return t end
	return G.frames / 30 -- assumption: about 30 GUI updates per second
end

local function getComp(entity, ct)
	local ok, c = pcall(api.engine.getComponent, entity, ct)
	if ok then return c end
	return nil
end

local function nodeSegments(node)
	local ok, segs = pcall(function() return api.engine.system.streetSystem.getNodeStreetSegments(node) end)
	if ok and segs ~= nil then return segs, "street" end
	ok, segs = pcall(function() return api.engine.system.streetSystem.getNodeSegments(node) end)
	if ok and segs ~= nil then return segs, "all" end
	return {}, "none"
end

--- Reads one node: segments (with template, ends, lanes) and its BaseNodeConfig.
local function readNode(node)
	local CT = api.type.ComponentType
	local info = { node = node, segs = {}, conns = {} }
	local bn = getComp(node, CT.BASE_NODE)
	if bn and bn.position then info.x, info.y, info.z = bn.position.x, bn.position.y, bn.position.z end
	local segs, how = nodeSegments(node)
	info.segsHow = how
	for _, id in ipairs(segs) do
		local e = getComp(id, CT.BASE_EDGE)
		local sg = { id = id }
		if e then
			sg.tpl = e.roadTemplate
			sg.style = e.roadStyle
			sg.node0, sg.node1 = e.node0, e.node1
			sg.endAt = (e.node0 == node) and 0 or ((e.node1 == node) and 1 or -1)
			sg.type = e.type
			local okL, lt = pcall(function() return L.lanesText(e.laneConfigs) end)
			sg.lanes = okL and lt or ("err:" .. tostring(lt))
			local okN, n1 = pcall(function() return L.count(e.laneConfigs) end)
			sg.nLanes = okN and n1 or -1
			local okN2, n2 = pcall(function() return L.count(e.laneConfig) end)
			sg.nLaneConfig = okN2 and n2 or -1
		end
		info.segs[#info.segs + 1] = sg
	end
	local cfg = getComp(node, CT.BASE_NODE_CONFIG)
	info.hasConfig = cfg ~= nil
	if cfg then
		info.userModLanes = cfg.userModifiedLaneConnections
		info.userModLights = cfg.userModifiedTrafficLightStates
		info.lightPref = cfg.trafficLightPreference
		info.crosswalks = L.count(cfg.crosswalks)
		info.doubleSlip = cfg.doubleSlipSwitch
		for _, c in ipairs(cfg.laneConnections or {}) do
			info.conns[#info.conns + 1] = {
				segment0 = c.segment0, lane0 = c.lane0, segment1 = c.segment1, lane1 = c.lane1,
				withRoad = c.withRoad, withTram = c.withTram,
			}
		end
	end
	return info
end

local function logNode(tag, info)
	out("NODE", { { "tag", tag }, { "node", info.node }, { "x", L.num(info.x) }, { "y", L.num(info.y) },
		{ "z", L.num(info.z) }, { "nSegs", #info.segs }, { "segsHow", info.segsHow },
		{ "hasConfig", info.hasConfig }, { "nConns", #info.conns } })
	for _, sg in ipairs(info.segs) do
		out("SEG", { { "tag", tag }, { "node", info.node }, { "seg", sg.id }, { "tpl", L.shortTemplate(sg.tpl) },
			{ "ring", L.isRingTemplate(sg.tpl) }, { "type", sg.type }, { "node0", sg.node0 }, { "node1", sg.node1 },
			{ "endAt", sg.endAt }, { "nLanes", sg.nLanes }, { "nLaneConfig", sg.nLaneConfig },
			{ "lanes", sg.lanes }, { "style", L.shortTemplate(sg.style) } })
	end
	if info.hasConfig then
		out("CFG", { { "tag", tag }, { "node", info.node }, { "userModLanes", info.userModLanes },
			{ "userModLights", info.userModLights }, { "lightPref", info.lightPref },
			{ "crosswalks", info.crosswalks }, { "doubleSlip", info.doubleSlip },
			{ "conns", L.connsText(info.conns) } })
	end
	for _, c in ipairs(info.conns) do
		out("CONN", { { "tag", tag }, { "node", info.node }, { "s0", c.segment0 }, { "l0", c.lane0 },
			{ "s1", c.segment1 }, { "l1", c.lane1 }, { "road", c.withRoad }, { "tram", c.withTram } })
	end
end

--- Sends the write experiment for one chosen node. Returns true if the command went out.
local function sendWrite(job, choice)
	G.writes = G.writes + 1
	local k = G.writes
	local mode = L.userModifiedMode(k)
	local CT = api.type.ComponentType
	local cfg = api.engine.getComponent(choice.node, CT.BASE_NODE_CONFIG)
	if cfg == nil then
		out("WRITE", { { "k", k }, { "job", job.seq }, { "node", choice.node }, { "status", "no_config_component" } })
		return false
	end
	local removeSet = {}
	for _, c in ipairs(choice.remove) do removeSet[L.connText(c)] = true end
	local kept, removed = {}, {}
	for _, c in ipairs(cfg.laneConnections) do
		if removeSet[L.connText(c)] then removed[#removed + 1] = c else kept[#kept + 1] = c end
	end
	local before = cfg.userModifiedLaneConnections
	-- Modify the read copy first, then hand it to the entry (as move_it.script.tl:2478-2493).
	cfg.laneConnections = kept
	if mode == "set_true" then cfg.userModifiedLaneConnections = true end
	local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
	entry.entity = choice.node
	entry.comp = cfg
	local proposal = api.type.SimpleProposal.new()
	proposal.streetProposal.nodeConfigsToRemove = { choice.node }
	proposal.streetProposal.nodeConfigsToAdd = { entry }
	local context = api.type.Context.new()
	context.player = api.engine.util.getPlayer()
	context.cleanupStreetGraph = false
	local cmd = api.cmd.makeWorldBuildProposalCmd(proposal, context, false, true, true)
	local expect = L.connsText(kept)
	out("WRITE", { { "k", k }, { "job", job.seq }, { "entry", job.entry }, { "node", choice.node },
		{ "ringIn", choice.ringIn }, { "arm", choice.arm }, { "lane0", choice.lane0 },
		{ "removed", #removed }, { "kept", #kept }, { "mode", mode }, { "userModBefore", before },
		{ "removedConns", L.connsText(removed) } })
	local okSend, e = pcall(api.cmd.sendCommand, cmd, function(_res, success)
		out("WRITE_RESULT", { { "k", k }, { "node", choice.node }, { "success", success } })
	end)
	if not okSend then
		out("WRITE_SEND", { { "k", k }, { "callback", "failed" }, { "err", e } })
		okSend, e = pcall(api.cmd.sendCommand, cmd)
		out("WRITE_SEND", { { "k", k }, { "callback", "none" }, { "ok", okSend }, { "err", okSend and "-" or e } })
		if not okSend then return false end
	end
	local t = now()
	local due = {}
	for _, d in ipairs(RECHECK) do due[#due + 1] = t + d end
	G.watches[#G.watches + 1] = { k = k, node = choice.node, expect = expect, mode = mode,
		due = due, builds = RECHECK_BUILDS, t0 = t }
	return true
end

local function scanJob(job)
	local CT = api.type.ComponentType
	local ids = api.engine.util.octree.findEntitiesInCircle(api.type.Vec2f.new(job.x, job.y), job.r, CT.BASE_NODE)
	local all, junctions, deg2, logged = 0, {}, 0, 0
	for _, id in ipairs(ids or {}) do
		all = all + 1
		local segs = nodeSegments(id)
		local n = L.count(segs)
		if n >= 3 then junctions[#junctions + 1] = id elseif n == 2 then deg2 = deg2 + 1 end
	end
	table.sort(junctions)
	out("SCAN", { { "job", job.seq }, { "entry", job.entry }, { "x", L.num(job.x) }, { "y", L.num(job.y) },
		{ "r", L.num(job.r) }, { "nodes", all }, { "junctions", #junctions }, { "deg2", deg2 } })
	local infos = {}
	for _, id in ipairs(junctions) do
		logged = logged + 1
		if logged > MAX_NODES then
			out("SCAN_TRUNCATED", { { "job", job.seq }, { "logged", MAX_NODES } })
			break
		end
		local info = readNode(id)
		logNode("j" .. job.seq, info)
		infos[#infos + 1] = info
	end
	-- one degree-2 ring node too (does a plain ring node carry a config at all?)
	for _, id in ipairs(ids or {}) do
		if L.count(nodeSegments(id)) == 2 then
			local info = readNode(id)
			local ring = 0
			for _, sg in ipairs(info.segs) do if L.isRingTemplate(sg.tpl) then ring = ring + 1 end end
			if ring == 2 then
				logNode("j" .. job.seq .. "d2", info)
				break
			end
		end
	end
	if G.cfg.write then
		if G.writes >= MAX_WRITES then
			out("WRITE", { { "job", job.seq }, { "status", "skipped_max_writes" } })
			return
		end
		local choice, why = L.chooseExperiment(infos)
		if not choice then
			out("WRITE", { { "job", job.seq }, { "status", "no_candidate" }, { "why", why } })
			return
		end
		sendWrite(job, choice)
	end
end

local function recheck(w, reason)
	local info = readNode(w.node)
	local text = L.connsText(info.conns)
	local same = text == w.expect
	out("PERSIST", { { "k", w.k }, { "node", w.node }, { "reason", reason }, { "dt", L.num(now() - w.t0) },
		{ "same", same }, { "nConns", #info.conns }, { "hasConfig", info.hasConfig },
		{ "userModLanes", info.userModLanes }, { "mode", w.mode } })
	if not same and not w.loggedDiff then
		w.loggedDiff = true
		logNode("w" .. w.k .. "diff", info)
	end
end

local function guiBody(state)
	G.frames = G.frames + 1
	if not G.init then
		G.init = true
		G.cfg = L.fromModParams(modParams())
		out("INFO", { { "msg", "DEV_ONLY_lane_probe_gui_loaded" }, { "write", G.cfg.write } })
	end
	local es = state and state:get()
	if type(es) == "table" then
		-- jobs: the first read only remembers what is old (saved jobs from an earlier session)
		if G.lastSeq == nil then
			G.lastSeq = es.seq or 0
			G.lastBuilds = es.builds or 0
		end
		for _, job in ipairs(es.jobs or {}) do
			if job.seq > G.lastSeq then
				G.lastSeq = job.seq
				G.pending[#G.pending + 1] = { seq = job.seq, entry = job.entry, x = job.x, y = job.y,
					r = job.r, due = now() + JOB_DELAY }
			end
		end
		local builds = es.builds or 0
		if builds ~= G.lastBuilds then
			G.lastBuilds = builds
			for _, w in ipairs(G.watches) do
				if w.builds > 0 and now() - w.t0 > 1 then
					w.builds = w.builds - 1
					recheck(w, "build" .. builds)
				end
			end
		end
	elseif G.lastSeq == nil then
		G.lastSeq, G.lastBuilds = 0, 0
	end
	local t = now()
	local i = 1
	while i <= #G.pending do
		local job = G.pending[i]
		if t >= job.due then
			table.remove(G.pending, i)
			local ok, e = pcall(scanJob, job)
			if not ok then err("scan" .. job.seq, e) end
		else
			i = i + 1
		end
	end
	for _, w in ipairs(G.watches) do
		while #w.due > 0 and t >= w.due[1] do
			local d = table.remove(w.due, 1)
			recheck(w, "time" .. L.num(d - w.t0) .. "s")
		end
	end
end

local function guiEvent(name, param)
	if name ~= EV_GUI_APPLY or G.guiEvents >= GUIEV_BUDGET then return end
	G.guiEvents = G.guiEvents + 1
	local p = type(param) == "table" and param or {}
	local proposal, result = p[1], p[3]
	local files = {}
	local okF = pcall(function()
		for _, con in ipairs(proposal.toAdd or {}) do files[#files + 1] = L.shortTemplate(con.fileName) end
	end)
	local sp = proposal and proposal.proposal
	out("GUIEV", { { "name", name }, { "shape", L.shapeText(param) }, { "files", okF and table.concat(files, ",") or "err" },
		{ "result", L.idsText(result, 8) }, { "addedNodes", L.count(sp and sp.addedNodes) },
		{ "ncfgAdd", L.count(sp and sp.nodeConfigsToAdd) } })
end

function data()
return {
	update = function(_userParams, state, _dt)
		local ok, e = pcall(doUpdate, state)
		if not ok then err("update", e) end
	end,
	handleEvent = function(_userParams, state, _src, id, name, param)
		local ok, e = pcall(doHandleEvent, state, id, name, param)
		if not ok then err("handleEvent:" .. tostring(name), e) end
	end,
	guiUpdate = function(_userParams, state, _guiState)
		local ok, e = pcall(guiBody, state)
		if not ok then err("guiUpdate", e) end
	end,
	guiHandleEvent = function(_userParams, _state, _guiState, _src, _id, name, param)
		local ok, e = pcall(guiEvent, name, param)
		if not ok then err("guiHandleEvent:" .. tostring(name), e) end
	end,
}
end
