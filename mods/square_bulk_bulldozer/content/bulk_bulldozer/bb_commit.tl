-- Bulk Bulldozer commit path (PLAN "Architecture": bb_commit.tl). API layer, GUI thread only
-- (called from the BulkBulldozerAction recipe). Builds the removal proposals, previews them with
-- makeProposalData, sends them with api.cmd.sendCommand and splits failed batches (bb_batch).
--
-- Evidence (research §9):
--   SimpleProposal / SimpleStreetProposal lists          api/type.d.tl:2764-2857
--     filled by assigning a whole Lua table (the userdata setter copies it, so never append
--     after assigning): auto_bulldoze.tl:19, electrify.tl:24, overpass_probe.script.tl:3403-3409
--   makeSegmentsRemoveProposal(segments) : Proposal       api/engine/util.d.tl:934; industry_util.tl:584
--   base two-step: constructions first, edges in the callback   industry_util.tl:560-601
--   makeProposalData(SimpleProposal) (cast)               overpass_probe.script.tl:325-330
--   makeWorldBuildProposalCmd(p, ctx, ignoreErrors, playerInitiated, doDust)  api/cmd.d.tl:960-961
--   sendCommand(cmd, function(data, success, resultEntities))  api/cmd.d.tl:598-600; the callback
--     runs in the GUI VM (base calls api.gui.* in it, bridge_and_tunnel.tl:195-204)
--   player-initiated Context: player + refundable entities  bridge_and_tunnel.tl:187-194
--
-- Never sends ignoreErrors = true. Every batch is re-checked against the hard rules on fresh
-- engine reads right before it is sent (assertHardRules).

local gather = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_gather.tl" as BulkBulldozerGather
local sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl" as BulkBulldozerSelect
local batch = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_batch.tl" as BulkBulldozerBatch

local commit : BulkBulldozerCommit = {}

-- THE switch for TESTING §4: false = base two-step, true = one combined SimpleProposal.
commit.COMBINED_PROPOSAL = false
commit.CONTEXT_WITH_PLAYER = true
commit.PREVIEW_INTERVAL = 0.25

local REASON_TEXT : {string : string} = {
	gone = "gone",
	foreign = "other player",
	part = "part of a construction",
	industry = "industry",
	hq = "HQ",
	not_player = "not yours",
	filtered = "filtered",
	underground = "underground",
}

local function comp(e : integer, t : Engine.ComponentType) : any
	if e == nil or e < 0 then return nil end
	local ok, c = pcall(function() : any
		local v : any = api.engine.getComponent(e, t)
		return v
	end)
	if ok then return c end
	return nil
end

function commit.balance() : integer
	local ok, v = pcall(function() : integer
		local p = api.engine.util.getPlayer()
		local acc = api.engine.getComponent(p, api.type.ComponentType.ACCOUNT) as Engine.Component.Account
		if acc == nil then return nil end
		return acc.balance
	end)
	if ok then return v end
	return nil
end

local function makeContext() : Context
	local c = api.type.Context.new()
	if commit.CONTEXT_WITH_PLAYER then
		pcall(function() c.player = api.engine.util.getPlayer() end)
		pcall(function()
			local r = api.gui.construction.getRefundableEntities()
			if r ~= nil then c.refundableEntities = r end
		end)
	end
	return c
end

local function allOn() : BulkBulldozerFilters
	return { roads = true, tracks = true, stations = true, assets = true,
		townBuildings = true, underground = true }
end

function commit.assertHardRules(edges : {integer}, cons : {integer}, ctx : BulkBulldozerContext,
		industryRoads : {integer : boolean}) : {integer}, {integer}, {integer : string}
	local cache = gather.newCache()
	for k, v in pairs(industryRoads or {}) do if v then cache.industryRoads[k] = true end end
	local f = allOn()
	local okE : {integer} = {}
	local okC : {integer} = {}
	local dropped : {integer : string} = {}
	local seen : {integer : boolean} = {}
	for _, e in ipairs(edges or {}) do
		if not seen[e] then
			seen[e] = true
			local d = gather.describeEdge(e, cache)
			if cache.industryRoads[e] then d.industryRoad = true end
			local c = sel.classify(d, f, ctx)
			if c.reason == nil and d.isEdge then okE[#okE + 1] = e else dropped[e] = c.reason or "gone" end
		end
	end
	for _, e in ipairs(cons or {}) do
		if not seen[e] then
			seen[e] = true
			local d = gather.describeConstruction(e, cache)
			local c = sel.classify(d, f, ctx)
			if c.reason == nil and not d.isEdge then okC[#okC + 1] = e else dropped[e] = c.reason or "gone" end
		end
	end
	return okE, okC, dropped
end

-- A SimpleProposal that removes these constructions and edges. withNetwork adds the edges'
-- objects (signals, stops, waypoints) and the nodes they would leave without any edge.
local record Built
	proposal : SimpleProposal
	nodes : integer
	objects : integer
end
local function buildSimple(edges : {integer}, cons : {integer}, withNetwork : boolean) : Built
	local objects : {integer} = {}
	local ends : {{integer}} = {}
	for _, e in ipairs(edges) do
		local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		if be ~= nil then
			ends[#ends + 1] = { be.node0, be.node1 }
			if withNetwork and be.objects ~= nil then
				for _, o in ipairs(be.objects) do
					if o ~= nil and o[1] ~= nil then objects[#objects + 1] = o[1] end
				end
			end
		end
	end
	local nodes : {integer} = {}
	if withNetwork and #ends > 0 then
		local degree : {integer : integer} = {}
		local frozen : {integer : boolean} = {}
		for _, pair in ipairs(ends) do
			for k = 1, 2 do
				local n = pair[k]
				if n ~= nil and n >= 0 and frozen[n] == nil then
					local okS, segs = pcall(api.engine.system.streetSystem.getNodeSegments, n)
					if okS and segs ~= nil then degree[n] = #segs end
					local okC, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForNode, n)
					-- Unreadable owner counts as frozen: never remove a node we can't vouch for.
					frozen[n] = not okC or con == nil or con >= 0
				end
			end
		end
		nodes = batch.orphanNodes(ends, degree, frozen)
	end
	local p = api.type.SimpleProposal.new()
	-- Assign whole tables (the setter copies; appending afterwards would be lost).
	p.constructionsToRemove = cons
	p.streetProposal.edgesToRemove = edges
	p.streetProposal.edgeObjectsToRemove = objects
	p.streetProposal.nodesToRemove = nodes
	return { proposal = p, nodes = #nodes, objects = #objects }
end

local function addUnique(list : {string}, s : string)
	if s == nil or s == "" then return end
	for _, x in ipairs(list) do if x == s then return end end
	list[#list + 1] = s
end

local function addData(pv : BulkBulldozerPreview, d : ProposalData)
	if d == nil then pv.ok = false; return end
	local ok = pcall(function()
		if d.costs ~= nil then pv.cost = (pv.cost or 0) + d.costs end
		local es = d.errorState
		if es ~= nil then
			if es.critical == true then pv.critical = true end
			local msgs = (es.messages or {}) as {string}
			for i = 1, #msgs do addUnique(pv.errors, tostring(msgs[i])) end
		end
	end)
	if not ok then pv.ok = false end
end

-- The Teal declaration says Proposal; the build accepts a SimpleProposal (overpass_probe.script.tl:325-330).
local function dataOfSimple(p : SimpleProposal) : ProposalData
	local withCtx = api.engine.util.proposal.makeProposalData as function(SimpleProposal, Context) : ProposalData
	local ok, d = pcall(withCtx, p, makeContext())
	if ok and d ~= nil then return d end
	local bare = api.engine.util.proposal.makeProposalData as function(SimpleProposal) : ProposalData
	ok, d = pcall(bare, p)
	if ok then return d end
	return nil
end

local function dataOfProposal(p : Proposal) : ProposalData
	if p == nil then return nil end
	local ok, d = pcall(api.engine.util.proposal.makeProposalData, p, makeContext())
	if ok then return d end
	return nil
end

local function segmentsProposal(edges : {integer}) : Proposal
	local ok, p = pcall(api.engine.util.proposal.makeSegmentsRemoveProposal, edges)
	if ok then return p end
	return nil
end

function commit.preview(edges : {integer}, cons : {integer}) : BulkBulldozerPreview
	local t0 = os.clock()
	local pv : BulkBulldozerPreview = { ok = true, cost = nil, critical = false, errors = {}, seconds = 0 }
	edges = edges or {}
	cons = cons or {}
	if #edges + #cons == 0 then
		pv.cost = 0
		return pv
	end
	if commit.COMBINED_PROPOSAL then
		local okB, b = pcall(buildSimple, edges, cons, true)
		addData(pv, okB and dataOfSimple(b.proposal) or nil)
	else
		if #cons > 0 then
			local okB, b = pcall(buildSimple, {}, cons, false)
			addData(pv, okB and dataOfSimple(b.proposal) or nil)
		end
		if #edges > 0 then addData(pv, dataOfProposal(segmentsProposal(edges))) end
	end
	pv.seconds = os.clock() - t0
	return pv
end

local function messagesOf(data : WorldBuildProposalCommandData) : {string}
	local out : {string} = {}
	pcall(function()
		local es = data.resultProposalData.errorState
		local msgs = (es.messages or {}) as {string}
		for i = 1, #msgs do addUnique(out, tostring(msgs[i])) end
	end)
	return out
end

local function moneyText(c : integer) : string
	if c == nil then return "?" end
	local ok, s = pcall(api.util.formatMoney, c)
	if ok and s ~= nil then return s end
	return tostring(c)
end

local function concat(a : {integer}, b : {integer}) : {integer}
	local out : {integer} = {}
	for _, x in ipairs(a) do out[#out + 1] = x end
	for _, x in ipairs(b) do out[#out + 1] = x end
	return out
end

local function reasonsText(r : {string : integer}) : string
	local keys : {string} = {}
	for k in pairs(r) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts : {string} = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. ": " .. tostring(r[k]) end
	return table.concat(parts, ", ")
end

function commit.commit(edges : {integer}, cons : {integer}, ctx : BulkBulldozerContext,
		industryRoads : {integer : boolean}, pre : BulkBulldozerPreview,
		onDone : function(BulkBulldozerCommitResult), logFn : function(string))
	local t0 = os.clock()
	local log = logFn or function(_s : string) end
	edges = edges or {}
	cons = cons or {}
	local res : BulkBulldozerCommitResult = {
		requested = #edges + #cons, removed = 0, skipped = 0, reasons = {}, commands = 0,
		refused = nil, cost = nil, seconds = 0,
	}
	local finished = false
	local function skip(reason : string, n? : integer)
		res.reasons[reason] = (res.reasons[reason] or 0) + (n or 1)
	end
	local function finish()
		if finished then return end
		finished = true
		res.skipped = res.requested - res.removed
		res.seconds = os.clock() - t0
		log(string.format("commit done: removed %d of %d, skipped %d%s, %d commands, %.0f ms%s",
			res.removed, res.requested, res.skipped,
			next(res.reasons) ~= nil and (" (" .. reasonsText(res.reasons) .. ")") or "",
			res.commands, res.seconds * 1000, res.refused ~= nil and (", refused: " .. res.refused) or ""))
		if onDone ~= nil then
			local ok, err = pcall(function() : string onDone(res); return nil end)
			if not ok then log("commit onDone failed: " .. tostring(err)) end
		end
	end
	local function skipDropped(dropped : {integer : string}, where : string)
		local n = 0
		for _, r in pairs(dropped) do
			skip(REASON_TEXT[r] or r)
			n = n + 1
		end
		if n > 0 then log(string.format("hard-rule recheck (%s) dropped %d", where, n)) end
	end

	-- 1. Hard rules on fresh reads, then the preflight on what is left.
	local e1, c1, dropped = commit.assertHardRules(edges, cons, ctx, industryRoads)
	skipDropped(dropped, "before preflight")
	if #e1 + #c1 == 0 then
		res.refused = "nothing left to remove"
		finish()
		return
	end
	local pv = pre or commit.preview(e1, c1)
	res.cost = pv.cost
	local bal = commit.balance()
	log(string.format("commit: %d edges, %d constructions, mode %s, preflight cost %s (raw %s), balance %s, critical %s, errors [%s], preflight %.1f ms",
		#e1, #c1, commit.COMBINED_PROPOSAL and "combined" or "two-step", moneyText(pv.cost), tostring(pv.cost),
		tostring(bal), tostring(pv.critical), table.concat(pv.errors, "; "), pv.seconds * 1000))
	if pv.cost ~= nil and pv.cost > 0 and bal ~= nil and pv.cost > bal then
		res.refused = "not enough money"
		skip("not enough money", #e1 + #c1)
		finish()
		return
	end

	local isEdge : {integer : boolean} = {}
	for _, e in ipairs(e1) do isEdge[e] = true end
	local budget = batch.MAX_COMMANDS

	-- Sends one command; cb(success, messages) runs exactly once unless the send itself throws,
	-- in which case the whole commit stops (retrying a script error would only repeat it).
	local function send(be : {integer}, bc : {integer}, label : string, cb : function(boolean, {string}))
		local called = false
		local okS, errS = pcall(function() : string
			local cmd : Command<WorldBuildProposalCommandData>
			local extra = ""
			if commit.COMBINED_PROPOSAL or #be == 0 then
				local b = buildSimple(be, bc, commit.COMBINED_PROPOSAL)
				extra = string.format(", %d nodes, %d objects", b.nodes, b.objects)
				cmd = api.cmd.makeWorldBuildProposalCmd(b.proposal, makeContext(), false, true, true)
			else
				local p = api.engine.util.proposal.makeSegmentsRemoveProposal(be)
				cmd = api.cmd.makeWorldBuildProposalCmd(p, makeContext(), false, true, true)
			end
			local n = res.commands + 1
			api.cmd.sendCommand(cmd, function(data : WorldBuildProposalCommandData, success : boolean)
				if called then return end
				called = true
				res.commands = res.commands + 1
				local msgs = messagesOf(data)
				log(string.format("cmd %d (%s): %d edges, %d constructions%s -> %s%s", n, label, #be, #bc, extra,
					success == true and "ok" or "FAILED", #msgs > 0 and (": " .. table.concat(msgs, "; ")) or ""))
				local okC, errC = pcall(function() : string cb(success == true, msgs); return nil end)
				if not okC then
					log("commit callback failed: " .. tostring(errC))
					finish()
				end
			end)
			return nil
		end)
		if not okS and not called then
			called = true
			log("send failed: " .. tostring(errS))
			skip("script error")
			finish()
		end
	end

	local function runPlan(items : {integer}, label : string, after : function())
		local plan = batch.newPlan(items, budget)
		local step : function()
		step = function()
			if finished then return end
			local b = batch.nextBatch(plan)
			if b == nil then
				budget = budget - plan.sent
				if #plan.capSkipped > 0 then
					skip("command limit reached", #plan.capSkipped)
					log(string.format("command limit (%d) reached: %d not tried", batch.MAX_COMMANDS, #plan.capSkipped))
				end
				-- plan.failed singles already have their reason (recorded when they failed).
				after()
				return
			end
			-- Right before sending: the hard rules again, on this exact batch.
			local be : {integer} = {}
			local bc : {integer} = {}
			for _, e in ipairs(b) do
				if isEdge[e] then be[#be + 1] = e else bc[#bc + 1] = e end
			end
			local ae, ac, dr = commit.assertHardRules(be, bc, ctx, industryRoads)
			skipDropped(dr, "before send")
			local sent = concat(ac, ae)
			if #sent == 0 then
				step()
				return
			end
			send(ae, ac, label, function(success : boolean, msgs : {string})
				if success then
					res.removed = res.removed + #sent
				elseif #sent == 1 then
					local why = msgs[1]
					if why == nil then
						local single = isEdge[sent[1]] and commit.preview(sent, {}) or commit.preview({}, sent)
						why = single.errors[1]
					end
					skip(why or "refused by the game")
				end
				batch.report(plan, sent, success)
				step()
			end)
		end
		step()
	end

	if commit.COMBINED_PROPOSAL then
		runPlan(concat(c1, e1), "combined", finish)
	else
		runPlan(c1, "constructions", function()
			runPlan(e1, "edges", finish)
		end)
	end
end

return commit
