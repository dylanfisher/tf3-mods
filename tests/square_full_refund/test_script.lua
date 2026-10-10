-- refund.script.tl adapter: lazy subscription, ledger from post adds, credit on pre/post removal,
-- rebuild drops entries, infinite money skips, deferred measurement.

local W

local function installApi()
	W = { t = 0, balance = 10000000, params = { square_full_refund = { refundWindow = 120 } }, sent = {},
		edges = {}, nodes = {}, clockUs = 1e9 }
	set_global("api", {
		type = {
			-- SQPERF timer: microseconds that only move when a test moves W.clockUs.
			Clock = { new = function() return { getTime = function() return W.clockUs end } end },
			ComponentType = { GAME_TIME = "GAME_TIME", BASE_EDGE = "BASE_EDGE", BASE_NODE = "BASE_NODE" },
			JournalEntry = {
				new = function() return { category = {} } end,
				Type = { CONSTRUCTION = "CONSTRUCTION", OTHER = "OTHER" },
				Construction = { BULLDOZER = "BULLDOZER" },
			},
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
		},
		engine = {
			getComponent = function(e, ct)
				if ct == "GAME_TIME" then return { gameTime = W.t } end
				if ct == "BASE_EDGE" then return W.edges[e] end
				if ct == "BASE_NODE" then return W.nodes[e] end
			end,
			util = {
				getWorld = function() return 0 end,
				getPlayer = function() return 7 end,
				finance = { getPlayersBalance = function() return W.balance end },
			},
			config = { getModParams = function() return W.params end },
		},
		cmd = {
			makeJournalBookAssetCmd = function(player, entry, pos) return { player = player, entry = entry } end,
			sendCommand = function(cmd)
				-- The engine asserts '!m_betweenChanges' when a command is sent inside a build event.
				if W.inEvent then error("std::exception (sendCommand inside a build event)") end
				W.sent[#W.sent + 1] = cmd
			end,
		},
	})
end

local function newState()
	local st = { value = nil, subs = {}, noEvents = 0 }
	function st:get() return self.value end
	function st:set(v) self.value = v end
	function st:hasEventSubscriptions() return next(self.subs) ~= nil end
	function st:subscribeToNoEvents() self.subs = {}; self.noEvents = self.noEvents + 1 end
	function st:subscribeToEvent(n) self.subs[n] = true end
	function st:subscribeToAllEvents() error("never subscribe to all events") end
	return st
end

local script, st
before_each(function()
	installApi()
	reset_modules()
	script = ug_require "square_full_refund::/refund/refund.script.tl"
	st = newState()
	clear_logs()
end)

local function proposal(opts)
	local toAdd = {}
	for i = 1, (opts.add or 0) do toAdd[i] = {} end
	local p = { toAdd = toAdd, toRemove = opts.remove or {}, proposal = { addedSegments = {}, removedSegments = {}, removedNodes = {} } }
	-- A segment is an entity id, or a SegmentAndEntity-like table { entity = id, comp = BaseEdge }.
	local function seg(e) if type(e) == "table" then return e end return { entity = e } end
	for _, e in ipairs(opts.addSegs or {}) do p.proposal.addedSegments[#p.proposal.addedSegments + 1] = seg(e) end
	for _, e in ipairs(opts.removeSegs or {}) do p.proposal.removedSegments[#p.proposal.removedSegments + 1] = seg(e) end
	p.proposal.addedNodes = opts.addNodes or {}
	for _, e in ipairs(opts.removeNodes or {}) do p.proposal.removedNodes[#p.proposal.removedNodes + 1] = { entity = e } end
	return p
end

local function fire(name, prop, costs, result, player)
	if player == nil then player = true end
	W.inEvent = true
	script.handleEvent({}, st, "", "apply_command", name, { prop, { costs = costs }, result or {}, player })
	W.inEvent = false
	if name == "onPostBuildProposal" then script.update({}, st, 0) end
end

local function build(entities, cost, opts)
	local prop = proposal(opts or { add = 1 })
	fire("onPreBuildProposal", prop, cost, {})
	W.balance = W.balance - cost
	fire("onPostBuildProposal", prop, cost, entities)
end

local function bulldoze(opts, engineRefund)
	local prop = proposal(opts)
	fire("onPreBuildProposal", prop, 0, {})
	if W.balance then W.balance = W.balance + engineRefund end
	fire("onPostBuildProposal", prop, 0, {})
end

local function warnings()
	local n = 0
	for _, e in ipairs(log_entries()) do if e.level == "warning" or e.level == "error" then n = n + 1 end end
	return n
end

test("update subscribes lazily to the two build events only", function()
	script.update({}, st, 0.0)
	eq(st.subs, { onPreBuildProposal = true, onPostBuildProposal = true })
	eq(st.noEvents, 1)
	script.update({}, st, 0.0)
	eq(st.noEvents, 1)
end)

test("bulldozing a fresh construction tops the engine's 75 % up to 100 %", function()
	build({ 500 }, 1084412)
	eq(#st.value.ledger, 1)
	W.t = 30000
	bulldoze({ remove = { 500 } }, 813306)
	eq(#W.sent, 1)
	local entry = W.sent[1].entry
	eq(entry.amount, 271106)
	eq(entry.time, -1)
	eq(entry.category.type, "CONSTRUCTION")
	eq(entry.category.construction, "BULLDOZER")
	eq(W.sent[1].player, 7)
	eq(#st.value.ledger, 0)
	eq(st.value.pending, nil)
	eq(warnings(), 0)
end)

test("outside the window: nothing credited", function()
	build({ 500 }, 1000)
	W.t = 121000
	bulldoze({ remove = { 500 } }, 0)
	eq(#W.sent, 0)
end)

test("the window follows the mod param (60 s)", function()
	W.params.square_full_refund.refundWindow = 60
	build({ 500 }, 1000)
	W.t = 90000
	bulldoze({ remove = { 500 } }, 0)
	eq(#W.sent, 0)
end)

test("not player initiated: ignored", function()
	local prop = proposal({ add = 1 })
	fire("onPostBuildProposal", prop, 1000, { 500 }, false)
	eq(st.value, nil)
end)

test("street segments: recorded from p[3], credited on removal of the segments", function()
	build({ 900, 901 }, 2000, { addSegs = { -1, -2 } })
	eq(#st.value.ledger, 2)
	bulldoze({ removeSegs = { 900 } }, 750)
	eq(W.sent[1].entry.amount, 250)
end)

test("segments without readable geometry are not recorded", function()
	local prop = proposal({ addSegs = { -1 } })
	script.handleEvent({}, st, "", "apply_command", "onPostBuildProposal", { prop, { costs = 400, old2new = { [-1] = 77 } }, {}, true })
	eq(#st.value.ledger, 0)
	eq(warnings(), 0)
end)

test("rebuild drops the entry without a credit", function()
	build({ 500 }, 1000)
	local prop = proposal({ add = 1, remove = { 500 } })
	fire("onPreBuildProposal", prop, 300, {})
	fire("onPostBuildProposal", prop, 300, { 501 })
	eq(#W.sent, 0)
	eq(#st.value.ledger, 1)
	eq(st.value.ledger[1].e, 501)
	bulldoze({ remove = { 500 } }, 0)
	eq(#W.sent, 0)
end)

test("infinite money: no credit", function()
	W.balance = nil
	local prop = proposal({ add = 1 })
	fire("onPostBuildProposal", prop, 1000, { 500 })
	bulldoze({ remove = { 500 } }, 0)
	eq(#W.sent, 0)
end)

test("no refund visible in post: measured again on the next update", function()
	build({ 500 }, 1000)
	local prop = proposal({ remove = { 500 } })
	fire("onPreBuildProposal", prop, 0, {})
	W.inEvent = true
	script.handleEvent({}, st, "", "apply_command", "onPostBuildProposal", { prop, { costs = 0 }, {}, true })
	W.inEvent = false
	eq(#W.sent, 0)
	ok(st.value.pending.await)
	W.balance = W.balance + 750
	script.update({}, st, 0.0)
	eq(#W.sent, 1)
	eq(W.sent[1].entry.amount, 250)
	eq(st.value.pending, nil)
end)

test("depot bulldoze: removed ids differ between pre and post (in-game log 2026-10-08)", function()
	build({ 17954 }, 1090015)
	fire("onPreBuildProposal", proposal({ remove = { 17954 }, removeSegs = { 17973 }, removeNodes = { 17965, 17959 } }), -817511, {})
	W.balance = W.balance + 817511
	-- By post the engine has deleted the entities; the proposal no longer reports the same ids.
	fire("onPostBuildProposal", proposal({ remove = { -1 }, removeSegs = { -1 }, removeNodes = { -1, -1 } }), -817511, {})
	eq(#W.sent, 1)
	eq(W.sent[1].entry.amount, 272504)
	eq(st.value.pending, nil)
end)

test("a post that does not match the pending pre is not credited", function()
	build({ 500 }, 1000)
	fire("onPreBuildProposal", proposal({ remove = { 500 } }), 0, {})
	W.balance = W.balance + 750
	fire("onPostBuildProposal", proposal({ remove = { 600, 601 } }), 0, {})
	eq(#W.sent, 0)
	eq(st.value.pending, nil)
end)

test("errors in the handler are caught and warned once", function()
	script.handleEvent({}, st, "", "apply_command", "onPreBuildProposal", { 5, nil, nil, true })
	script.handleEvent({}, st, "", "apply_command", "onPreBuildProposal", { 5, nil, nil, true })
	eq(warnings(), 1)
end)

---------------------------------------------------------------------------
-- Streets keyed by geometry (Phase 1c): p[3] and old2new are empty for street builds in game.

local function V(x, y, z) return { x = x, y = y, z = z or 0 } end

-- A proposal segment: BaseEdge-like comp with positions, tangents along the chord.
local function S(entity, a, b, n0, n1)
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], (b[3] or 0) - (a[3] or 0)
	return { entity = entity, type = 0, comp = {
		node0 = n0, node1 = n1,
		position0 = V(a[1], a[2], a[3]), position1 = V(b[1], b[2], b[3]),
		tangent0 = V(dx, dy, dz), tangent1 = V(dx, dy, dz),
	} }
end

-- The live street after a build: entity id -> BaseEdge, as getComponent sees it.
local function place(id, a, b, n0, n1)
	local s = S(id, a, b, n0, n1)
	W.edges[id] = s.comp
	return s
end

local function buildStreet(segs, cost)
	local prop = proposal({ addSegs = segs })
	fire("onPreBuildProposal", prop, cost, {})
	W.balance = W.balance - cost
	fire("onPostBuildProposal", prop, cost, {})
end

-- Bulldoze one segment: the removal proposal carries only the entity (comp unset), so the script
-- has to read the still-existing BASE_EDGE in pre.
local function bulldozeSeg(id, engineRefund, removeNodes)
	local prop = proposal({ removeSegs = { id }, removeNodes = removeNodes })
	fire("onPreBuildProposal", prop, -engineRefund, {})
	W.edges[id] = nil
	W.balance = W.balance + engineRefund
	fire("onPostBuildProposal", prop, -engineRefund, {})
end

local function credited()
	local n = 0
	for _, c in ipairs(W.sent) do n = n + c.entry.amount end
	return n
end

test("3-segment street, bulldozed segment by segment: credits + engine refunds == build cost", function()
	local start = W.balance
	buildStreet({ S(-1, { 0, 0 }, { 100, 0 }, -10, -11), S(-2, { 100, 0 }, { 200, 0 }, -11, -12),
		S(-3, { 200, 0 }, { 300, 0 }, -12, -13) }, 179156)
	eq(#st.value.ledger, 3)
	ok(st.value.ledger[1].k:sub(1, 2) == "e:", "edge key prefix")
	-- The engine's ids for the built segments (unknown to the script).
	place(18879, { 0, 0 }, { 100, 0 }, 1, 2)
	place(18880, { 100, 0 }, { 200, 0 }, 2, 3)
	place(18881, { 200, 0 }, { 300, 0 }, 3, 4)
	W.t = 20000
	bulldozeSeg(18881, 44000, { 4 })
	bulldozeSeg(18879, 44500, { 1 })
	bulldozeSeg(18880, 44867, { 2, 3 })
	eq(#W.sent, 3)
	eq(credited() + 44000 + 44500 + 44867, 179156)
	eq(W.balance + credited(), start)
	eq(#st.value.ledger, 0)
	eq(warnings(), 0)
end)

test("street cost is split by segment length", function()
	buildStreet({ S(-1, { 0, 0 }, { 300, 0 }), S(-2, { 300, 0 }, { 400, 0 }) }, 4000)
	eq(st.value.ledger[1].c, 3000)
	eq(st.value.ledger[2].c, 1000)
end)

test("segment geometry falls back to node positions (addedNodes for new nodes, BASE_NODE for existing)", function()
	W.nodes[5] = { position = V(0, 0, 10) }
	local seg = { entity = -1, comp = { node0 = 5, node1 = -20 } }
	local prop = proposal({ addSegs = { seg }, addNodes = { { entity = -20, comp = { position = V(50, 0, 10) } } } })
	fire("onPostBuildProposal", prop, 1000, {})
	eq(#st.value.ledger, 1)
	eq(st.value.ledger[1].c, 1000)
	place(700, { 50, 0, 10 }, { 0, 0, 10 }, 6, 5) -- reversed orientation
	bulldozeSeg(700, 750)
	eq(credited(), 250)
end)

test("rounding tolerance: float noise and rounding boundaries still match; 2 m off does not", function()
	buildStreet({ S(-1, { 10.249, 5.05, 1.0 }, { 110.0, 5.0, 1.0 }) }, 1000)
	-- 10.249 rounds to 10.2 but 10.251 to 10.3: the key differs, the tolerant match does not.
	place(800, { 110.0003, 4.9998, 1.02 }, { 10.251, 5.049, 0.99 }, 1, 2)
	bulldozeSeg(800, 750)
	eq(credited(), 250)

	buildStreet({ S(-1, { 0, 0 }, { 100, 0 }) }, 1000)
	place(801, { 0, 2 }, { 100, 2 }, 1, 2)
	bulldozeSeg(801, 750)
	eq(credited(), 250)
	eq(#st.value.ledger, 1)
end)

test("branch-off rebuild: no credit at the rebuild; paid cost carried; bulldozing all refunds everything", function()
	local start = W.balance
	buildStreet({ S(-1, { 0, 0 }, { 100, 0 }), S(-2, { 100, 0 }, { 200, 0 }), S(-3, { 200, 0 }, { 300, 0 }) }, 3000)
	place(1, { 0, 0 }, { 100, 0 }, 11, 12)
	place(2, { 100, 0 }, { 200, 0 }, 12, 13)
	place(3, { 200, 0 }, { 300, 0 }, 13, 14)
	-- Branch off the middle of segment 2: it is replaced by two halves plus the new branch.
	local prop = proposal({ removeSegs = { 2 },
		addSegs = { S(-1, { 100, 0 }, { 150, 0 }), S(-2, { 150, 0 }, { 200, 0 }), S(-3, { 150, 0 }, { 150, 100 }) } })
	fire("onPreBuildProposal", prop, 1000, {})
	W.edges[2] = nil
	W.balance = W.balance - 1000
	fire("onPostBuildProposal", prop, 1000, {})
	eq(#W.sent, 0)
	eq(#st.value.ledger, 5)
	eq(st.value.carry, nil)
	place(4, { 100, 0 }, { 150, 0 }, 12, 15)
	place(5, { 150, 0 }, { 200, 0 }, 15, 13)
	place(6, { 150, 0 }, { 150, 100 }, 15, 16)
	local refunds = 0
	for _, id in ipairs({ 1, 3, 4, 5, 6 }) do
		local r = math.floor(W.edges[id] and 300 or 0)
		bulldozeSeg(id, r)
		refunds = refunds + r
	end
	eq(credited() + refunds, 4000)
	eq(W.balance + credited(), start)
	eq(#st.value.ledger, 0)
	eq(warnings(), 0)
end)

test("rebuild of a street that is not in the ledger records the new segments at the rebuild cost only", function()
	place(9, { 0, 0 }, { 100, 0 }, 1, 2)
	local prop = proposal({ removeSegs = { 9 }, addSegs = { S(-1, { 0, 0 }, { 50, 0 }), S(-2, { 50, 0 }, { 100, 0 }) } })
	fire("onPreBuildProposal", prop, 600, {})
	fire("onPostBuildProposal", prop, 600, {})
	eq(#st.value.ledger, 2)
	eq(st.value.ledger[1].c + st.value.ledger[2].c, 600)
end)

test("mixed construction + street: the construction takes the whole cost, its street is not recorded", function()
	local prop = proposal({ add = 1, addSegs = { S(-1, { 0, 0 }, { 40, 0 }) } })
	fire("onPreBuildProposal", prop, 1090015, {})
	W.balance = W.balance - 1090015
	fire("onPostBuildProposal", prop, 1090015, { 17954 })
	eq(#st.value.ledger, 1)
	eq(st.value.ledger[1].e, 17954)
	eq(st.value.ledger[1].c, 1090015)
	-- Bulldozing the depot removes its street too: one credit for the whole price.
	place(17973, { 0, 0 }, { 40, 0 }, 17965, 17959)
	bulldoze({ remove = { 17954 }, removeSegs = { 17973 }, removeNodes = { 17965, 17959 } }, 817511)
	eq(credited(), 272504)
	eq(#st.value.ledger, 0)
end)

test("mixed proposal without a construction id in p[3]: segments take the cost", function()
	local prop = proposal({ add = 1, addSegs = { S(-1, { 0, 0 }, { 40, 0 }) } })
	fire("onPostBuildProposal", prop, 500, {})
	eq(#st.value.ledger, 1)
	eq(st.value.ledger[1].c, 500)
end)

test("street outside the window: nothing credited", function()
	buildStreet({ S(-1, { 0, 0 }, { 100, 0 }) }, 1000)
	place(50, { 0, 0 }, { 100, 0 }, 1, 2)
	W.t = 121000
	bulldozeSeg(50, 0)
	eq(#W.sent, 0)
end)

---------------------------------------------------------------------------
-- Per-frame cost (perf review 2026-10-08): update reads the state only when an event left work.

local function countGets()
	local n = { get = 0 }
	local orig = st.get
	st.get = function(self) n.get = n.get + 1; return orig(self) end
	return n
end

test("perf: idle frames don't read the state (only the load check + a once-per-second safety net)", function()
	build({ 500 }, 1000)
	local n = countGets()
	for _ = 1, 200 do script.update({}, st, 0.0) end
	ok(n.get <= 3, "state:get() on idle frames: " .. n.get)
end)

test("perf: a payout already in the saved state is booked on the first update after load", function()
	st.value = { v = 1, ledger = {}, payout = 250 }
	st.subs = { onPreBuildProposal = true, onPostBuildProposal = true }
	script.update({}, st, 0.0)
	eq(#W.sent, 1)
	eq(W.sent[1].entry.amount, 250)
	eq(st.value.payout, nil)
end)

test("perf: credits are still booked on the next frame after idle frames", function()
	build({ 500 }, 1000)
	for _ = 1, 50 do script.update({}, st, 0.0) end
	local prop = proposal({ remove = { 500 } })
	fire("onPreBuildProposal", prop, 0, {})
	W.balance = W.balance + 750
	W.inEvent = true
	script.handleEvent({}, st, "", "apply_command", "onPostBuildProposal", { prop, { costs = 0 }, {}, true })
	W.inEvent = false
	eq(#W.sent, 0)
	script.update({}, st, 0.0)
	eq(#W.sent, 1)
	eq(W.sent[1].entry.amount, 250)
end)

test("perf: in the map editor getModParams is not called on every frame", function()
	local calls = 0
	W.params = { [""] = { isMapEditor = true } }
	api.engine.config.getModParams = function() calls = calls + 1; return W.params end
	for _ = 1, 200 do script.update({}, st, 0.0) end
	eq(next(st.subs), nil)
	-- <= 2 by the mod, plus SQPERF's "Debug: performance log" gate: once when its first window opens
	-- (first update) and once for the phase=first line, then only every 30 s.
	ok(calls <= 4, "getModParams calls: " .. calls)
	W.clockUs = W.clockUs + 31e6
	local before = calls
	for _ = 1, 200 do script.update({}, st, 0.0) end
	ok(calls - before <= 3, "getModParams calls after 30 s: " .. (calls - before))
end)

local function sqperfLines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern, 1, true)) then out[#out + 1] = e.msg end
	end
	return out
end

test("SQPERF: Debug log On gives a 30 s summary of update, events and the build handlers", function()
	W.params.square_full_refund.sqperf_log = 2
	script.update({}, st, 0.0) -- first stop opens the window (gate read: On)
	build({ 500 }, 1000)
	W.t = 1000
	bulldoze({ remove = { 500 } }, 750)
	script.handleEvent({}, st, "", "other", "x", nil)
	W.clockUs = W.clockUs + 31e6
	script.update({}, st, 0.0)
	local lines = sqperfLines("win_ms=")
	eq(#lines, 1)
	local line = lines[1]
	ok(line:find("mod=square_full_refund ctx=gs", 1, true), line)
	for _, sec in ipairs({ "event n=5 ms=", "on_pre n=2 ms=", "on_post n=2 ms=", "update n=", "update_work n=" }) do
		ok(line:find(sec, 1, true), sec .. " in " .. line)
	end
	eq(#W.sent, 1)
end)

test("SQPERF: Debug log Off: no SQPERF lines; a slow update (> 50 ms) is logged once", function()
	script.update({}, st, 0.0)
	build({ 500 }, 1000)
	W.clockUs = W.clockUs + 31e6
	script.update({}, st, 0.0)
	eq(#sqperfLines(), 0)
	st.get = function(self) W.clockUs = W.clockUs + 60000; return self.value end
	script.update({}, st, 0.0) -- the safety-net state read (one per os.time() second) may be skipped
	W.clockUs = W.clockUs + 1
	local prop = proposal({ remove = { 500 } })
	fire("onPreBuildProposal", prop, 0, {})
	ok(#sqperfLines("slow=on_pre max=60.0 over=1/") == 1, table.concat(sqperfLines(), "\n"))
	ok(#sqperfLines("slow=event max=60.0 over=1/") == 1, table.concat(sqperfLines(), "\n"))
end)
