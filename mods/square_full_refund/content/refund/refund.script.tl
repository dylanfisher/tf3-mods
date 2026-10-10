-- Full Refund Window game script (sim thread). Tops up the engine's bulldoze refund to 100 % for player
-- objects bulldozed within the refund window.
--
-- Flow (apply_command events, src: .cache/game/base/content/game_mechanics/achievements/achievements.script.tl:294-328,
-- towns/towns.script.tl:266-273; param = {Proposal, ProposalData, {Entity}, playerInitiated}):
--   post, with additions        -> ledger += new constructions (p[3]) with data.costs, or else the added
--                                  street/track segments keyed by geometry, cost split by length
--   pre, pure removal           -> take the ledger hits inside the window, remember owed + balance
--   post, same removal          -> engine refund = balance now - balance before; credit owed - refund
--   pre, rebuild (adds+removes) -> drop the removed entries, no credit; their paid cost is carried
--   post, rebuild                  onto the new objects together with the rebuild's data.costs
-- Everything runs inside one pcall per entry point: an error is logged once, never thrown at the engine.
-- Lazy init only (works when added to an existing save); state is a small, self-pruning ledger.

-- SQPERF (plans/sqperf/README.md): load time of this game-script Lua state (one per simulation
-- worker), the first update (lazy subscription + first state read), calls slower than 50 ms (at most
-- one line per section per minute) and, with the "Debug: performance log" mod setting On, a 30 s
-- summary. Sections: "update" / "event" around the entry points' pcalls, "update_work" (the state
-- read, settle and payout part of update), "on_pre" / "on_post" (a player build's pre / post event).
-- Local counters only; nothing is saved.
local sqperf = ug_require "square_full_refund::/sqperf/square_full_refund.lua" as SquareFullRefundSqPerf
local perf = sqperf.new({ mod = "square_full_refund", ctx = "gs", paramKey = "sqperf_log", first = { "update" } })
local perfInit = perf:start()

local logic = ug_require "/refund/refund_logic.tl" as FullRefundLogic

local MOD_ID <const> = "square_full_refund"
local PREFIX <const> = "[FullRefund] "
local EV_PRE <const> = "onPreBuildProposal"
local EV_POST <const> = "onPostBuildProposal"
-- Finance line of our booking: true = Construction > "Bulldozer" (finances_util.tl:56-57),
-- false = "Other" (as the campaign's bookings, mission_story.tl:1015-1019).
local BOOK_AS_BULLDOZER <const> = true
-- Probe lines for the first in-game test.
-- Verbose "[FullRefund]" trace of every build/bulldoze for in-game debugging. Warnings always log.
local PROBE <const> = false

local warned : {string : boolean} = {}
local function warnOnce(key : string, msg : string)
	if warned[key] then return end
	warned[key] = true
	log.warning(PREFIX .. msg)
end

local function probe(msg : string)
	if PROBE then log.message(PREFIX .. msg) end
end

-- Per-frame cost control (this Lua state only, nothing saved).
-- updateWork: an event may have left work for update (state.payout, or a pending.await re-measure).
-- Starts true so a payout saved in the game is still booked after a load. update reads the state
-- (state:get() converts the whole ledger, up to MAX_ENTRIES) only when set, or once per os.time()
-- second as a safety net, instead of on every frame.
local updateWork = true
local nextStateCheck = 0      -- os.time() of the next safety-net state read
local nextEditorCheck = 0     -- os.time() of the next isMapEditor() (getModParams copy) while unsubscribed

local function getGameTime() : integer
	-- src: mods/square_quota_run/content/quota/quota.script.tl:34-38; api/tealdef/api/engine.d.tl:424-438
	local gt : Engine.Component.GameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gt.gameTime
end

local function getBalance() : integer
	-- nil = infinite money. src: .cache/game/base/content/game_mechanics/finance/loan.script.tl:47
	local ok, b = pcall(api.engine.util.finance.getPlayersBalance, api.engine.util.getPlayer())
	if not ok then
		warnOnce("balance", "reading the balance failed: " .. tostring(b))
		return nil
	end
	return b as integer
end

local function isMapEditor() : boolean
	-- src: .cache/game/base/content/game_mechanics/company/company_growth.script.tl:74
	local ok, params = pcall(api.engine.config.getModParams)
	if not ok or params == nil then return false end
	local base = params[""] as {string : any}
	return base ~= nil and base["isMapEditor"] == true
end

--- Raw "refundWindow" mod param. The game hands every script the params chosen for this
--- game load via api.engine.config.getModParams() (api/tealdef/api/engine.d.tl:1806-1807;
--- read the same way in base towns.script.tl:58 and by mods/square_better_minimap).
local function rawWindowParam() : any
	local ok, all = pcall(api.engine.config.getModParams)
	if not ok then
		warnOnce("params", "reading the mod params failed: " .. tostring(all))
		return nil
	end
	local mine = all ~= nil and (all as {string : any})[MOD_ID] as {string : any} or nil
	return mine ~= nil and mine["refundWindow"] or nil
end

local function windowMs() : integer, any
	local raw = rawWindowParam()
	return math.floor(logic.windowSeconds(raw) * 1000), raw
end

local function money(n : number) : string
	if n == nil then return "nil" end
	return string.format("%d", math.floor(n + 0.5))
end

local function idList(ids : {integer}) : string
	local parts : {string} = {}
	for i, e in ipairs(ids) do
		if i > 6 then
			parts[#parts + 1] = "...(" .. #ids .. ")"
			break
		end
		parts[#parts + 1] = tostring(e)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function book(amount : integer)
	-- src: mods/square_quota_run/content/quota/quota_effects.tl:256-266 (proven from handleEvent);
	-- api/tealdef/api/cmd.d.tl:747; base/tealdef/scripts/journal.d.tl (categories)
	local entry = api.type.JournalEntry.new()
	entry.amount = amount
	entry.time = -1
	if BOOK_AS_BULLDOZER then
		entry.category.type = api.type.JournalEntry.Type.CONSTRUCTION
		entry.category.construction = api.type.JournalEntry.Construction.BULLDOZER
	else
		entry.category.type = api.type.JournalEntry.Type.OTHER
	end
	api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
end

---------------------------------------------------------------------------
-- Segment geometry
--
-- Street/track segments can't be keyed by entity id: after a street build p[3] is empty and
-- data.old2new maps nothing (in game 2026-10-08), and the post's ids are placeholders (< 0).
-- So segments are keyed by their endpoint positions instead (logic.edgeKey / sameEdge).
-- Fields: Proposal.proposal : StreetProposal {addedSegments, removedSegments : {SegmentAndEntity},
-- addedNodes, removedNodes : {NodeAndEntity}} (api/tealdef/api/type.d.tl:2511-2559);
-- SegmentAndEntity.comp : Engine.Component.BaseEdge {node0, node1, position0, position1, tangent0,
-- tangent1} (api/tealdef/api/engine.d.tl:99-127); BaseNode.position (engine.d.tl:157-162).
-- comp.position0/1 are read from build-event proposals by parallel_tracks_1
-- (parallel_tracks.script.lua:119-137); BASE_NODE lookups as in move_it.script.tl:1327.

local function v3(v : Vec3f) : {number}
	if v == nil then return nil end
	local x, y, z = v.x, v.y, v.z
	if x == nil or y == nil then return nil end
	return { x, y, z or 0 }
end

local function dist(a : {number}, b : {number}) : number
	local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function vlen(v : {number}) : number
	if v == nil then return 0 end
	return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end

local function nodePos(node : integer, newNodes : {integer : {number}}) : {number}
	if node == nil then return nil end
	local p = newNodes[node]
	if p ~= nil then return p end
	if node < 0 then return nil end
	local ok, p2 = pcall(function() : {number}
		local n : Engine.Component.BaseNode = api.engine.getComponent(node, api.type.ComponentType.BASE_NODE)
		return n ~= nil and v3(n.position) or nil
	end)
	if not ok then return nil end
	return p2
end

local function usable(p0 : {number}, p1 : {number}) : boolean
	-- A default (unset) BaseEdge has zero positions: treat a degenerate segment as missing.
	return p0 ~= nil and p1 ~= nil and dist(p0, p1) > 0.01
end

--- Geometry of one segment and where it came from ("comp" | "edge" | "nodes"), nil if unreadable.
--- live: the segment still exists, so its BASE_EDGE may be read (pre events).
local function segGeom(seg : api.type.SegmentAndEntity, newNodes : {integer : {number}}, live : boolean) : FullRefundEdge, string
	local comp = seg.comp
	local p0, p1, t0, t1 : {number}, {number}, {number}, {number}
	local src = "comp"
	if comp ~= nil then
		p0, p1, t0, t1 = v3(comp.position0), v3(comp.position1), v3(comp.tangent0), v3(comp.tangent1)
	end
	if not usable(p0, p1) and live and seg.entity ~= nil and seg.entity >= 0 then
		local ok, e = pcall(function() : Engine.Component.BaseEdge
			return api.engine.getComponent(seg.entity, api.type.ComponentType.BASE_EDGE)
		end)
		if ok and e ~= nil then
			comp = e
			p0, p1, t0, t1 = v3(comp.position0), v3(comp.position1), v3(comp.tangent0), v3(comp.tangent1)
			src = "edge"
		end
	end
	if not usable(p0, p1) and comp ~= nil then
		p0, p1 = nodePos(comp.node0, newNodes), nodePos(comp.node1, newNodes)
		src = "nodes"
	end
	if not usable(p0, p1) then return nil, "none" end
	-- Tangent length ~ arc length in TF's cubic segments; the chord is the fallback.
	local len = (vlen(t0) + vlen(t1)) / 2
	local chord = dist(p0, p1)
	if len < chord then len = chord end
	return { p0 = p0, p1 = p1, len = len }, src
end

--- Geometries of a list of segments; unreadable segments are counted, not returned.
local function geoms(segs : {api.type.SegmentAndEntity}, nodes : {api.type.NodeAndEntity}, live : boolean) : {FullRefundEdge}, {string}, integer
	local newNodes : {integer : {number}} = {}
	for _, n in ipairs(nodes or {}) do
		local ok, p = pcall(function() : {number} return v3(n.comp.position) end)
		if ok and p ~= nil and n.entity ~= nil then newNodes[n.entity] = p end
	end
	local out : {FullRefundEdge} = {}
	local srcs : {string} = {}
	local bad = 0
	for _, seg in ipairs(segs or {}) do
		local ok, g, src = pcall(segGeom, seg, newNodes, live)
		if ok and g ~= nil then
			out[#out + 1] = g
			srcs[#srcs + 1] = src
		else
			bad = bad + 1
			if not ok then warnOnce("geom", "reading a segment failed: " .. tostring(g)) end
		end
	end
	return out, srcs, bad
end

local function edgeList(edges : {FullRefundEdge}, srcs : {string}) : string
	local parts : {string} = {}
	for i, ed in ipairs(edges) do
		if i > 4 then
			parts[#parts + 1] = "...(" .. #edges .. ")"
			break
		end
		local k = logic.edgeKey(ed.p0, ed.p1)
		parts[#parts + 1] = string.format("%s len=%.1f src=%s", k, ed.len, srcs[i] or "?")
	end
	return "[" .. table.concat(parts, "; ") .. "]"
end

---------------------------------------------------------------------------
-- Proposal reading

local record Shape
	numToAdd : integer          -- constructions added
	numToRemove : integer       -- proposal.toRemove
	addedSegs : integer         -- street/track segments added
	removedSegs : integer
	removedNodes : integer
	removed : {integer}         -- every existing entity removed: toRemove + removed segments + nodes
	result : {integer}          -- p[3]
	costs : integer
	kind : string
end

local function streetProposal(proposal : api.type.Proposal) : api.type.StreetProposal
	return proposal.proposal
end

local function readShape(proposal : api.type.Proposal, data : api.type.ProposalData, result : {integer}) : Shape
	local toAdd = proposal.toAdd or {}
	local toRemove = proposal.toRemove or {}
	local sp = streetProposal(proposal)
	local addedSegments = sp ~= nil and sp.addedSegments or {}
	local removedSegments = sp ~= nil and sp.removedSegments or {}
	local removedNodes = sp ~= nil and sp.removedNodes or {}

	local removed : {integer} = {}
	local seen : {integer : boolean} = {}
	local function push(e : integer)
		if e ~= nil and e >= 0 and not seen[e] then
			seen[e] = true
			removed[#removed + 1] = e
		end
	end
	for _, e in ipairs(toRemove) do push(e) end
	for _, s in ipairs(removedSegments) do push(s.entity) end
	for _, n in ipairs(removedNodes) do push(n.entity) end

	local res : {integer} = {}
	for _, e in ipairs(result or {}) do res[#res + 1] = e end

	local shape : Shape = {
		numToAdd = #toAdd,
		numToRemove = #toRemove,
		addedSegs = #addedSegments,
		removedSegs = #removedSegments,
		removedNodes = #removedNodes,
		removed = removed,
		result = res,
		costs = data ~= nil and data.costs or nil,
	}
	-- Count from the proposal, not from `removed`: by post the removed ids are no longer valid.
	shape.kind = logic.classify(shape.numToAdd + shape.addedSegs, #toRemove + #removedSegments + #removedNodes)
	return shape
end

--- Pairs a removal's pre and post events. Removed ids differ between pre and post (the engine
-- has already deleted them by post), so match on the proposal's counts instead.
local function removalKey(shape : Shape) : string
	return string.format("%d:%d:%d", shape.numToRemove, shape.removedSegs, shape.removedNodes)
end

--- New constructions of an addition: p[3] (non-negative ids).
local function newConstructions(shape : Shape) : {integer}
	local out : {integer} = {}
	for _, e in ipairs(shape.result) do
		if e >= 0 then out[#out + 1] = e end
	end
	return out
end

--- Takes the ledger entries of everything the proposal removes (constructions by id, segments by
--- geometry read while they still exist). Returns the entries and a probe description.
local function takeRemoved(s : FullRefundState, proposal : api.type.Proposal, shape : Shape) : {FullRefundEntry}, string
	local taken = logic.take(s, shape.removed)
	-- The description is only for the probe trace: not built when PROBE is off.
	local desc = PROBE and idList(shape.removed) or ""
	if shape.removedSegs > 0 then
		local sp = streetProposal(proposal)
		local edges, srcs, bad = geoms(sp.removedSegments, sp.removedNodes, true)
		local hits = logic.takeEdges(s, edges)
		for _, en in ipairs(hits) do taken[#taken + 1] = en end
		if PROBE then desc = desc .. string.format(" segs %s (%d edge hit(s), %d unreadable)", edgeList(edges, srcs), #hits, bad) end
	end
	return taken, desc
end

local function sumCost(entries : {FullRefundEntry}) : integer
	local n = 0
	for _, en in ipairs(entries) do n = n + en.c end
	return n
end

---------------------------------------------------------------------------
-- Event handling

local function onPre(state : GameScriptState<FullRefundState>, proposal : api.type.Proposal, shape : Shape, now : integer)
	local s = logic.normalize(state:get())
	local wms = windowMs()
	logic.prune(s, now, wms)
	s.carry = nil
	if shape.kind == "remove" then
		local taken, desc = takeRemoved(s, proposal, shape)
		local owed, hits = logic.owed(taken, now, wms)
		if hits > 0 then
			local bal = getBalance()
			s.pending = { key = removalKey(shape), owed = owed, hits = hits, balance = bal, t = now, await = false }
			probe(string.format("pre removal: %d ledger hit(s) %s, owed %s, balance before %s",
				hits, desc, money(owed), money(bal)))
		else
			s.pending = nil
			probe("pre removal: no ledger hit for " .. desc)
		end
	elseif shape.kind == "rebuild" then
		local dropped, desc = takeRemoved(s, proposal, shape)
		s.pending = nil
		-- No credit now. What was paid for the replaced objects moves to the rebuild's new
		-- objects in post, so building, rebuilding and bulldozing everything is still a full refund.
		if #dropped > 0 then
			s.carry = sumCost(dropped)
			probe(string.format("pre rebuild: dropped %d ledger entr(ies) %s, no credit, carry %s",
				#dropped, desc, money(s.carry)))
		else
			probe("pre rebuild: no ledger hit for " .. desc)
		end
	else
		s.pending = nil
	end
	state:set(s)
end

local function settle(s : FullRefundState, balanceNow : integer, where : string)
	local p = s.pending
	s.pending = nil
	if p.balance == nil or balanceNow == nil then
		probe(where .. ": balance unavailable (infinite money?), no credit; owed was " .. money(p.owed))
		return
	end
	local actual = balanceNow - p.balance
	local credit = logic.credit(p.owed, actual)
	probe(string.format("%s: balance %s -> %s, engine refunded %s of owed %s -> credit %s",
		where, money(p.balance), money(balanceNow), money(actual), money(p.owed), money(credit)))
	if credit > 0 then
		updateWork = true
		-- Booking here crashes: sendCommand inside a build event asserts '!m_betweenChanges'
		-- (in game 2026-10-08). Queue it for the next update instead.
		s.payout = (s.payout or 0) + credit
	end
end

--- Records an addition/rebuild. Cost = data.costs plus, for a rebuild, the carried cost of the
--- replaced entries (never below 0). Constructions in p[3] take the whole cost (a construction's
--- auto-built connecting street is part of its price and usually goes away with it); segments are
--- recorded only when the proposal added no construction we can identify, split by length.
local function record(s : FullRefundState, proposal : api.type.Proposal, shape : Shape, now : integer)
	local cost = (shape.costs or 0) + (s.carry or 0)
	s.carry = nil
	local ents = newConstructions(shape)
	if cost > 0 and #ents > 0 then
		logic.add(s, ents, cost, now)
		if PROBE then probe(string.format("ledger +%d construction(s) %s, cost %s (%d segment(s) included), ledger size %d",
			#ents, idList(ents), money(cost), shape.addedSegs, #s.ledger)) end
		return
	end
	if shape.addedSegs > 0 then
		local sp = streetProposal(proposal)
		local edges, srcs, bad = geoms(sp.addedSegments, sp.addedNodes, false)
		if cost > 0 and #edges > 0 then
			local added = logic.addEdges(s, edges, cost, now)
			if PROBE then
				local shares : {string} = {}
				for i, en in ipairs(added) do
					if i > 4 then break end
					shares[#shares + 1] = money(en.c)
				end
				probe(string.format("ledger +%d segment(s) %s shares {%s}, cost %s, %d unreadable, ledger size %d",
					#added, edgeList(edges, srcs), table.concat(shares, ","), money(cost), bad, #s.ledger))
			end
			return
		end
		probe(string.format("ledger: nothing recorded (cost %s, %d segment(s) readable, %d unreadable)",
			money(cost), #edges, bad))
		return
	end
	probe(string.format("ledger: nothing recorded (cost %s, %d new construction(s))", money(cost), #ents))
end

local function onPost(state : GameScriptState<FullRefundState>, proposal : api.type.Proposal,
		shape : Shape, now : integer)
	local s = logic.normalize(state:get())
	if shape.kind == "add" or shape.kind == "rebuild" then
		record(s, proposal, shape, now)
		state:set(s)
	elseif shape.kind == "remove" and s.pending ~= nil then
		s.carry = nil
		if s.pending.key ~= removalKey(shape) then
			probe(string.format("post removal %s (ids %s) does not match the pending pre %s, dropped",
				removalKey(shape), idList(shape.removed), s.pending.key))
			s.pending = nil
		else
			local bal = getBalance()
			if bal ~= nil and s.pending.balance ~= nil and bal - s.pending.balance <= 0 then
				-- The engine's refund is not visible yet: measure again on the next update.
				s.pending.await = true
				updateWork = true
				probe(string.format("post removal: balance %s -> %s, no refund visible yet, measuring next update",
					money(s.pending.balance), money(bal)))
			else
				settle(s, bal, "post removal")
			end
		end
		state:set(s)
	end
end

-- SQPERF sections "on_pre" / "on_post" (inside handleEvent's pcall; an error passes through untimed).
local timedOnPre = perf:wrap("on_pre", onPre)
local timedOnPost = perf:wrap("on_post", onPost)

local function handleApply(state : GameScriptState<FullRefundState>, name : string, param : any)
	local p = param as {any}
	if p == nil then return end
	local playerInitiated = p[4] as boolean
	if not playerInitiated then return end
	local proposal = p[1] as api.type.Proposal
	local data = p[2] as api.type.ProposalData
	if proposal == nil then return end
	local shape = readShape(proposal, data, p[3] as {integer})
	local now = getGameTime()
	local pre = name == EV_PRE
	if PROBE then probe(string.format("%s %s t=%d toAdd=%d toRemove=%d addedSegs=%d removedSegs=%d removedNodes=%d costs=%s #p3=%d p3=%s balance=%s",
		pre and "pre" or "post", shape.kind, now, shape.numToAdd, shape.numToRemove, shape.addedSegs,
		shape.removedSegs, shape.removedNodes, money(shape.costs), #shape.result, idList(shape.result),
		money(getBalance()))) end
	if pre then timedOnPre(state, proposal, shape, now) else timedOnPost(state, proposal, shape, now) end
end

local function doUpdate(state : GameScriptState<FullRefundState>) : any
	if not state:hasEventSubscriptions() then
		-- Never in the map editor: without subscriptions no event ever reaches us.
		-- isMapEditor() copies every mod's params: in the editor, ask once per second, not every frame.
		local t = os.time()
		if t < nextEditorCheck then return end
		if isMapEditor() then
			nextEditorCheck = t + 1
			return
		end
		-- Lazy subscription: no lifecycle event reaches a mod added to an existing save.
		-- src: mods/square_problem_radar/content/radar/radar.script.tl:1258-1262; gamescript.d.tl:40-49
		state:subscribeToNoEvents()
		state:subscribeToEvent(EV_PRE)
		state:subscribeToEvent(EV_POST)
		local wms, raw = windowMs()
		probe(string.format("subscribed; refundWindow param raw=%s -> window %d s", tostring(raw), wms // 1000))
	end
	if not updateWork then
		local t = os.time()
		if t < nextStateCheck then return end
		nextStateCheck = t + 1
	end
	updateWork = false
	local tWork = perf:start() -- SQPERF section "update_work"
	local s = state:get()
	if s ~= nil and s.pending ~= nil and s.pending.await then
		settle(s, getBalance(), "update")
		state:set(s)
	end
	if s ~= nil and s.payout ~= nil then
		local amount = s.payout
		s.payout = nil
		state:set(s)
		if amount > 0 then
			book(amount)
			probe("credited " .. money(amount) .. (BOOK_AS_BULLDOZER and " (Construction/Bulldozer)" or " (Other)"))
		end
	end
	perf:stop("update_work", tWork)
end

local function doHandleEvent(state : GameScriptState<FullRefundState>, id : string, name : string, param : any) : any
	if id == "apply_command" and (name == EV_PRE or name == EV_POST) then
		handleApply(state, name, param)
	end
end

local script : GameScript<FullRefundState> = {
	update = function(_userParams : table, state : GameScriptState<FullRefundState>, _dt : number) : any
		local tPerf = perf:start() -- SQPERF section "update" (failed calls count too)
		local ok, err = pcall(doUpdate, state)
		perf:stop("update", tPerf)
		if not ok then warnOnce("update", "update failed: " .. tostring(err)) end
	end,

	handleEvent = function(_userParams : table, state : GameScriptState<FullRefundState>, _src : string, id : string, name : string, param : any) : any
		local tPerf = perf:start() -- SQPERF section "event"
		local ok, err = pcall(doHandleEvent, state, id, name, param)
		perf:stop("event", tPerf)
		if not ok then warnOnce("handleEvent", "event '" .. tostring(name) .. "' failed: " .. tostring(err)) end
	end,
}

perf:phase("init", perfInit)

return script
