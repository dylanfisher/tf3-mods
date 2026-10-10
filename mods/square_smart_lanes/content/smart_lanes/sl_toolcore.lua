-- Smart Lanes tool (Phase 2 step 1): the controller behind the road tool's UI (sl_tool.script.lua).
-- Picking, the selection, Apply (layouts from sl_rules), Reset (writes the game default model) and
-- the frame-timed re-reads. No React here, so tests/square_smart_lanes/test_tool.lua drives it with
-- a fake api. Runs on the GUI thread (the construction menu's Lua state).
--
-- Log lines ([SQRL], stdout.txt):
--   PROBE hover entity=.. kind=node|edge promoted=.. d=.. r=.. target=..  (rate-limited, on change)
--   PICK target=.. ring=.. lanes=.. arms=.. conns=.. badge=smart|default|custom|partial|na
--                                                                  (a click selected something)
--   APPLY src=tool layout=.. ring=.. node=.. ... turbo=.. turbo_reason=.. before=.. after=..
--   WRITE src=tool ring=.. nodes=.. success=..  /  VERIFY src=tool ring=.. same=.. nodes=..
--   RESET mode=model scope=node|ring   then APPLY / WRITE / VERIFY src=tool layout=game
--   Slip-lane junctions (sl_slip): APPLY / WRITE / VERIFY src=tool kind=slip node=..;
--   RESET mode=snapshot|unavailable kind=slip node=.. (no engine-default model for slip nodes: Reset
--   writes back what the node had before the tool's first Apply on it in this session)

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"

local Core = {}

Core.VERIFY_DELAY = 30      -- frames after a write callback before the nodes are re-read
Core.CALLBACK_TIMEOUT = 600 -- frames without a callback after which a reset is judged anyway
Core.HOVER_LOG_GAP = 0.3    -- s between PROBE hover lines (only on a change of target)
Core.REFRESH_FRAMES = 30    -- frames between re-reads of the selection (counts, overlay)
Core.HOVER_STALE_FRAMES = 10 -- frames without onHover after which the hover highlight goes
Core.BADGE_CACHE_MAX = 64   -- lane status badge cache entries (cleared when full)

-- Display name of a layout (Rules.LAYOUT_NAMES stays English: the game script and the log use it).
-- Translated when called (the tool's GUI Lua state).
local function layoutText(layout)
	local names = { matched = _("Matched lanes"), turbo = _("Smart lanes"), game = _("Game default") }
	return names[layout] or tostring(layout)
end

--- api: game api (or fake); out(kind, fields): log; clock(): seconds (os.clock in game).
function Core.new(api, out, clock)
	local W = Write.new(api, out)
	local C = {
		W = W,
		frames = 0,
		hover = nil,        -- pick target under the cursor
		sel = nil,          -- selected pick target
		result = nil,       -- last result text (status chip)
		version = 0,        -- bumped whenever hover / sel / overlay data change
		verifies = {},      -- writes waiting for their re-read
		hoverLim = {},
		hoverCache = { key = nil, at = 0, target = nil, info = nil },
		hoverFrame = 0,     -- frame of the last onHover call
		lastRefresh = 0,
		snapshots = {},     -- slip node -> its connections before the tool's first Apply on it
		badgeCache = {},    -- "ring:<key>" / "slip:<node>" -> { text, res } (lane status badge)
		badgeStats = { hits = 0, misses = 0 },
	}
	clock = clock or os.clock

	local function bump() C.version = C.version + 1 end
	local function setResult(text)
		C.result = text
		bump()
	end

	local function CT() return api.type.ComponentType end

	local function segsText(segs)
		local ids = {}
		for i, sid in ipairs(segs or {}) do ids[i] = tostring(sid) end
		return table.concat(ids, ",")
	end

	local function cachePut(ck, text, res)
		local n = 0
		for _ in pairs(C.badgeCache) do n = n + 1 end
		if n >= Core.BADGE_CACHE_MAX then C.badgeCache = {} end
		C.badgeCache[ck] = { text = text, res = res }
	end

	--- Per ring junction: { smart = bool, default = bool } or { skip = true }, keyed by node.
	-- Cached by ring key + every ring node's road connections + the ring's segments, so the two
	-- planRing passes run only when something changed.
	local function ringStatuses(world, ring)
		local cur, road, parts, seeds = {}, {}, { segsText(ring.segs) }, {}
		for _, n in ipairs(ring.nodes) do
			seeds[n] = true
			cur[n] = W.currentConns(n)
			road[n] = Rules.roadText(cur[n])
			parts[#parts + 1] = tostring(n) .. "=" .. road[n]
		end
		local ck, text = "ring:" .. tostring(ring.key), table.concat(parts, ";")
		local hit = C.badgeCache[ck]
		if hit ~= nil and hit.text == text then
			C.badgeStats.hits = C.badgeStats.hits + 1
			return hit.res
		end
		C.badgeStats.misses = C.badgeStats.misses + 1
		local function get(n) return cur[n] or W.currentConns(n) end
		local smart = Rules.planRing(world, ring, seeds, "turbo", get)
		local engine = Rules.planRing(world, ring, seeds, "engine", get)
		local eng = {}
		for _, r in ipairs(engine.nodes) do eng[r.node] = r end
		local res = {}
		for _, r in ipairs(smart.nodes) do
			if (r.status == "same" or r.status == "apply") and r.conns ~= nil then
				local e = eng[r.node]
				res[r.node] = {
					smart = Rules.roadText(r.conns) == road[r.node],
					default = e ~= nil and e.conns ~= nil and Rules.roadText(e.conns) == road[r.node],
				}
			else
				res[r.node] = { skip = true }
			end
		end
		cachePut(ck, text, res)
		return res
	end

	--- Badge info of a slip node: smart or not (no engine-default model there).
	local function slipBadgeInfo(world, n)
		local cur = W.currentConns(n)
		local node = world.node(n)
		local text = segsText(node and node.segs) .. ";" .. Rules.roadText(cur)
		local ck = "slip:" .. tostring(n)
		local hit = C.badgeCache[ck]
		if hit ~= nil and hit.text == text then
			C.badgeStats.hits = C.badgeStats.hits + 1
			return hit.res
		end
		C.badgeStats.misses = C.badgeStats.misses + 1
		local r = Slip.plan(world, n, function() return cur end)
		local info
		if (r.status == "same" or r.status == "apply") and r.conns ~= nil then
			info = { kind = "slip", total = 1, smart = Rules.roadText(r.conns) == Rules.roadText(cur) and 1 or 0 }
		else
			info = { kind = "na" }
		end
		cachePut(ck, text, info)
		return info
	end

	--- Lane status badge info of a pick target (sl_pick.badge input).
	function C.badgeInfo(world, t)
		if t == nil then return nil end
		if t.ring ~= nil then
			local st = ringStatuses(world, t.ring)
			local list = t.kind == "ring" and (t.junctionNodes or {}) or { t.node }
			local info = { kind = t.kind == "ring" and "ring" or "node", total = 0, smart = 0, default = 0 }
			for _, n in ipairs(list) do
				local s = st[n]
				if s ~= nil and not s.skip then
					info.total = info.total + 1
					if s.smart then info.smart = info.smart + 1 end
					if s.default then info.default = info.default + 1 end
				end
			end
			if info.total == 0 then return { kind = "na" } end
			return info
		end
		if t.kind == "node" and t.slip ~= nil then return slipBadgeInfo(world, t.node) end
		return { kind = "na" }
	end

	--- Everything a target shows (texts, badge, segments, the overlay's connections), so a re-read
	-- that found nothing new does not re-render the tool's world layer.
	local function targetSig(world, t)
		local parts = { Pick.targetKey(t), Pick.describe(t), Pick.detail(t), t.badge and t.badge.label or "-" }
		local nodes
		if t.kind == "ring" then
			parts[#parts + 1] = segsText(t.ring.segs)
			nodes = t.junctionNodes or {}
		else
			local node = world.node(t.node)
			parts[#parts + 1] = segsText(node and node.segs)
			nodes = { t.node }
		end
		for _, n in ipairs(nodes) do parts[#parts + 1] = Rules.connsText(W.currentConns(n)) end
		return table.concat(parts, "|")
	end

	--- Which toolbar buttons would change something for target t: { applyNode, applyRing, reset }.
	-- From the same per-junction statuses as the badge (cached), so a button is enabled exactly
	-- when its click would write: Apply where a handled junction is not smart lanes yet, Reset
	-- where one differs from the game default model (slip nodes: from the snapshot of the first Apply).
	function C.canInfo(world, t)
		local can = { applyNode = false, applyRing = false, reset = false }
		if t.ring ~= nil then
			local st = ringStatuses(world, t.ring)
			for _, n in ipairs(t.junctionNodes or {}) do
				local s = st[n]
				if s ~= nil and not s.skip then
					if not s.smart then can.applyRing = true end
					if t.kind == "ring" and not s.default then can.reset = true end
				end
			end
			if t.kind == "node" then
				local s = st[t.node]
				if s ~= nil and not s.skip then
					can.applyNode = not s.smart
					can.reset = not s.default
				end
			end
		elseif t.kind == "node" and t.slip ~= nil then
			local info = slipBadgeInfo(world, t.node)
			can.applyNode = info.kind == "slip" and info.smart == 0
			local snap = C.snapshots[t.node]
			can.reset = snap ~= nil and Rules.connsText(snap) ~= Rules.connsText(W.currentConns(t.node))
		end
		return can
	end

	--- Sets t.badge (sl_pick.badge result; a failure is logged and leaves t.badge nil), t.can
	-- (C.canInfo; all false on a failure) and t.sig.
	local function addBadge(world, t)
		if t == nil then return t end
		local ok, info = pcall(C.badgeInfo, world, t)
		if ok then
			t.badge = Pick.badge(info)
		else
			out("ERROR", { { "where", "badge" }, { "err", info } })
		end
		local okC, can = pcall(C.canInfo, world, t)
		if okC then
			t.can = can
		else
			out("ERROR", { { "where", "can" }, { "err", can } })
		end
		t.sig = targetSig(world, t)
		return t
	end

	--- Pick-target info for node n (nil when n is not a street node).
	-- { kind = "node", node, roads, conns, ring, ringKey, ringLanes, junctions, junctionNodes,
	--   nodeKind, exits, entries, reason }
	local function nodeTarget(world, n)
		local node = world.node(n)
		if not node or #node.segs == 0 then return nil end
		local t = { kind = "node", node = n, roads = #node.segs, conns = #W.currentConns(n), x = node.x, y = node.y, z = node.z }
		local ring = Ring.ringThrough(world, n)
		if ring then
			C.fillRing(world, ring, t)
			local v = Ring.nodeView(world, ring, n)
			t.nodeKind, t.reason = v.kind, v.reason
			t.exits, t.entries = #(v.x or {}), #(v.e or {})
		else
			local v = Slip.classify(world, n)
			if v.kind == "slip" then
				t.slip, t.nodeKind = v, "slip"
				t.slipShape, t.slipLanes, t.slipSummary = v.shape, Slip.mainLanes(v), Slip.summary(v)
			elseif v.kind == "skip" then
				t.slipReason = v.reason
			end
		end
		return addBadge(world, t)
	end

	function C.fillRing(world, ring, t)
		t.ring, t.ringKey, t.ringLanes = ring, ring.key, ring.lanes
		t.junctionNodes = {}
		for _, rn in ipairs(ring.nodes) do
			if Ring.nodeView(world, ring, rn).kind ~= "plain" then t.junctionNodes[#t.junctionNodes + 1] = rn end
		end
		t.junctions = #t.junctionNodes
		return t
	end

	local function ringTarget(world, ring)
		return addBadge(world, C.fillRing(world, ring, { kind = "ring" }))
	end

	--- Pick target for a Selector hit. entity: what the Selector reports; cursor: {x, y} or nil.
	-- Node hit -> that node; street edge hit near an end (Pick.promote) -> that end node; street edge
	-- hit in the middle of a ring segment -> the whole ring; anything else -> nil.
	-- Returns target, info {entityKind = "node"|"edge"|"other", promoted, d, r}.
	function C.resolve(entity, cursor)
		local info = { entityKind = "other", promoted = false }
		if type(entity) ~= "number" or entity < 0 then return nil, info end
		local world = W.makeWorld()
		if W.getComp(entity, CT().BASE_NODE) ~= nil then
			info.entityKind = "node"
			return nodeTarget(world, entity), info
		end
		if W.getComp(entity, CT().BASE_EDGE) == nil or W.getComp(entity, CT().BASE_EDGE_STREET) == nil then
			return nil, info
		end
		info.entityKind = "edge"
		local s = world.seg(entity)
		if not s then return nil, info end
		if cursor then
			local n, d, r = Pick.promote(cursor, { node0 = s.node0, node1 = s.node1, p0 = s.p0, p1 = s.p1 })
			info.d, info.r = d, r
			if n then
				info.promoted = true
				return nodeTarget(world, n), info
			end
		end
		local _a, b = Ring.travel(s)
		if b then
			local ring = Ring.ringThrough(world, b)
			if ring and ring.segSet[entity] then return ringTarget(world, ring), info end
		end
		return nil, info
	end

	--- Cheap key of what a hit resolves to (one component read): "n:<node>" for a node or a
	-- promoted edge end, "e:<edge>" for an edge middle, "x:<entity>" otherwise.
	local function quickKey(entity, cursor)
		if W.getComp(entity, CT().BASE_NODE) ~= nil then return "n:" .. entity end
		local e = W.getComp(entity, CT().BASE_EDGE)
		if e == nil or e.position0 == nil or e.position1 == nil then return "x:" .. entity end
		if cursor then
			local n = Pick.promote(cursor, { node0 = e.node0, node1 = e.node1, p0 = e.position0, p1 = e.position1 })
			if n then return "n:" .. n end
		end
		return "e:" .. entity
	end

	--- Selector onHover. Re-resolves (ring search) only when the quick key changes, or every
	-- REFRESH_FRAMES frames.
	function C.onHover(entity, cursor)
		C.hoverFrame = C.frames
		local target, info
		local okK, qk = pcall(quickKey, entity, cursor)
		if okK then qk = tostring(entity) .. "|" .. qk end -- info (edge / node, promoted) is per entity
		local hc = C.hoverCache
		if type(entity) == "number" and entity >= 0 and okK and hc.key == qk and C.frames - hc.at < Core.REFRESH_FRAMES then
			target, info = hc.target, hc.info
		else
			local okR, t, inf = pcall(C.resolve, entity, cursor)
			if not okR then
				out("ERROR", { { "where", "hover" }, { "err", t } })
				t, inf = nil, { entityKind = "other", promoted = false }
			end
			target, info = t, inf
			C.hoverCache = { key = okK and qk or nil, at = C.frames, target = target, info = info }
		end
		local key = Pick.targetKey(target)
		if key ~= Pick.targetKey(C.hover) or (target ~= nil and target.sig ~= C.hover.sig) then
			C.hover = target
			bump()
		end
		if type(entity) == "number" and entity >= 0
			and Pick.allow(C.hoverLim, tostring(entity) .. "/" .. key, clock(), Core.HOVER_LOG_GAP) then
			out("PROBE hover", { { "entity", entity }, { "kind", info.entityKind }, { "promoted", info.promoted },
				{ "d", info.d and string.format("%.1f", info.d) or "-" }, { "r", info.r and string.format("%.1f", info.r) or "-" },
				{ "target", key } })
		end
		return target
	end

	function C.onExitHover()
		if C.hover ~= nil then
			C.hover = nil
			bump()
		end
	end

	--- Selector onSelect (left click): selects the target under the cursor. Returns the target.
	function C.select(entity, cursor)
		local okR, target = pcall(C.resolve, entity, cursor)
		if not okR then
			out("ERROR", { { "where", "select" }, { "err", target } })
			target = nil
		end
		C.sel = target
		C.result = nil
		C.lastRefresh = C.frames
		bump()
		if target then
			out("PICK", { { "target", Pick.targetKey(target) }, { "ring", target.ringKey or "-" }, { "lanes", target.ringLanes or "-" },
				{ "arms", target.junctions or "-" }, { "node_kind", target.nodeKind or "-" }, { "conns", target.conns or "-" },
				{ "badge", target.badge and target.badge.key or "-" } })
		end
		return target
	end

	function C.clear()
		if C.sel ~= nil or C.result ~= nil then
			C.sel = nil
			C.result = nil
			bump()
			return true
		end
		return false
	end

	--- Re-reads the selection from the live game (counts, ring); drops it when the node is gone.
	function C.refresh()
		local s = C.sel
		if s == nil then return end
		local world = W.makeWorld()
		local t
		if s.kind == "node" then
			t = nodeTarget(world, s.node)
		else
			local ring = s.ring and Ring.ringThrough(world, s.ring.nodes[1])
			t = ring and ringTarget(world, ring) or nil
		end
		if t == nil then
			C.sel = nil
			setResult(_("The selected junction is gone"))
			return
		end
		local changed = t.sig == nil or t.sig ~= s.sig
		C.sel = t
		if changed then bump() end
	end

	local function scheduleVerify(src, key, expect, kind)
		C.quietUntil = 0 -- from here on the pending verify keeps the NodeViewer off
		C.verifies[#C.verifies + 1] = { src = src, ring = key, kind = kind, expect = expect, due = C.frames + Core.VERIFY_DELAY }
	end

	--- Writes one slip node's connections (Apply or the Reset snapshot). Returns the result text.
	local function writeSlip(node, conns, src, done)
		local answered = false
		C.quietUntil = C.frames + Core.CALLBACK_TIMEOUT
		local sent = W.sendConfigs("slip", node, { { node = node, conns = conns } }, function(success, expect, nodes)
			C.quietUntil = 0
			answered = true
			out("WRITE", { { "src", src }, { "kind", "slip" }, { "node", node }, { "nodes", nodes }, { "success", success } })
			if success then
				scheduleVerify(src, node, expect, "slip")
				setResult(done)
			else
				setResult(_("The game refused the change (see log)"))
			end
		end)
		if sent == 0 then
			setResult(_("Could not build the change (see log)"))
		elseif not answered then
			setResult(_("Applying..."))
		end
		return C.result
	end

	--- Apply / Reset on a selected slip-lane junction.
	function C.applySlip(scope, layout)
		local s = C.sel
		if scope == "ring" then
			setResult(_("Not a roundabout: use Apply to junction"))
			return C.result
		end
		local world = W.makeWorld()
		local cur = W.currentConns(s.node)
		if layout == "game" then
			local snap = C.snapshots[s.node]
			if snap == nil then
				out("RESET", { { "mode", "unavailable" }, { "kind", "slip" }, { "node", s.node } })
				setResult(_("Reset not available here (no Apply yet)"))
				return C.result
			end
			out("RESET", { { "mode", "snapshot" }, { "kind", "slip" }, { "node", s.node }, { "conns", #snap } })
			if Rules.connsText(snap) == Rules.connsText(cur) then
				setResult(_("Already as before Apply"))
				return C.result
			end
			return writeSlip(s.node, snap, "reset", _("Lanes restored as before Apply"))
		end
		local r = Slip.plan(world, s.node, function() return cur end)
		if r.status == "none" or r.status == "skip" then
			setResult(_("Not a slip-lane junction any more; select it again"))
			return C.result
		end
		if r.status == "same" then
			setResult(_("Smart lanes already set"))
			return C.result
		end
		if C.snapshots[s.node] == nil then C.snapshots[s.node] = cur end
		local fields = { { "src", "tool" } }
		for _, f in ipairs(Slip.logFields(r)) do fields[#fields + 1] = f end
		out("APPLY", fields)
		return writeSlip(s.node, r.conns, "tool", _("Smart lanes applied to the slip junction"))
	end

	--- The current ring of the selection, re-found in a fresh world (nil, reason when none).
	local function liveRing(world)
		local s = C.sel
		if s == nil then return nil, _("Select a junction or a roundabout first") end
		if s.ring == nil then return nil, _("Not a roundabout junction: not handled yet") end
		local start = s.kind == "node" and s.node or s.ring.nodes[1]
		local ring = Ring.ringThrough(world, start)
		if ring == nil then return nil, _("The roundabout changed; select it again") end
		return ring
	end

	--- Apply the layout to the selected junction (scope "node") or its whole ring (scope "ring").
	-- layout: "matched" | "turbo" | "game" (game = Reset). Returns the result text.
	function C.apply(scope, layout)
		local s = C.sel
		if s == nil then
			setResult(_("Select a junction or a roundabout first"))
			return C.result
		end
		if scope == "node" and s ~= nil and s.kind ~= "node" then
			setResult(_("Click near a junction to pick it, or use Apply to roundabout"))
			return C.result
		end
		if s.kind == "node" and s.ring == nil and s.slip ~= nil then return C.applySlip(scope, layout) end
		local world = W.makeWorld()
		local ring, why = liveRing(world)
		if ring == nil then
			setResult(why)
			return C.result
		end
		local seeds = {}
		if scope == "node" then
			seeds[s.node] = true
		else
			for _, n in ipairs(ring.nodes) do seeds[n] = true end
		end
		-- the tool's Game default writes the engine default model as a full config ("engine")
		local plan = Rules.planRing(world, ring, seeds, layout == "game" and "engine" or layout, W.currentConns)
		local items, same, skipped = {}, 0, 0
		for _, r in ipairs(plan.nodes) do
			if r.status == "apply" then
				local v = r.view
				out("APPLY", { { "src", "tool" }, { "layout", layout }, { "ring", ring.key }, { "node", r.node }, { "lanes", ring.lanes },
					{ "dir", ring.side == 1 and "ccw" or "cw" }, { "exits", #v.x }, { "entries", #v.e },
					{ "turbo", plan.turbo }, { "turbo_reason", plan.turboReason or "-" }, { "before", r.before }, { "after", r.after } })
				items[#items + 1] = { node = r.node, conns = r.conns }
			elseif r.status == "same" then
				same = same + 1
			elseif r.status == "skip" then
				skipped = skipped + 1
				out("SKIP", { { "src", "tool" }, { "ring", ring.key }, { "node", r.node }, { "reason", r.reason } })
			end
		end
		local name = layoutText(layout)
		-- turboReason is an internal id (sl_rules), shown as it is
		local why = (layout == "turbo" and not plan.turbo) and tostring(plan.turboReason) or nil
		if #items == 0 then
			if skipped > 0 and same == 0 then
				setResult(_("Left alone: this junction type is not handled yet"))
			elseif why ~= nil then
				setResult(string.format(_("%s already set (no exit-only lane: %s)"), name, why))
			else
				setResult(string.format(_("%s already set"), name))
			end
			return C.result
		end
		local key = ring.key
		local answered = false
		C.quietUntil = C.frames + Core.CALLBACK_TIMEOUT -- no NodeViewer until the write is judged
		local sent = W.sendConfigs("ring", key, items, function(success, expect, nodes)
			C.quietUntil = 0
			answered = true
			out("WRITE", { { "src", "tool" }, { "ring", key }, { "nodes", nodes }, { "success", success } })
			if success then
				scheduleVerify("tool", key, expect)
				local fmt
				if why ~= nil then
					fmt = #items == 1 and _("%s applied to %d junction (no exit-only lane: %s)")
						or _("%s applied to %d junctions (no exit-only lane: %s)")
				else
					fmt = #items == 1 and _("%s applied to %d junction") or _("%s applied to %d junctions")
				end
				setResult(string.format(fmt, name, #items, why))
			else
				setResult(_("The game refused the change (see log)"))
			end
		end)
		if sent == 0 then
			setResult(_("Could not build the change (see log)"))
		elseif not answered then
			setResult(string.format(_("Applying %s..."), name))
		end
		return C.result
	end

	--- Reset to the game default = Apply with the Game default layout (a full config write).
	-- Never a remove-only proposal: in game (2026-10-08) nodeConfigsToRemove without an add deleted
	-- the node's BASE_NODE_CONFIG (0 connections, no config to edit afterwards) and the simulation
	-- crashed seconds later in Engine.cpp:693 PostRemoveComponent (findings.md).
	function C.reset(scope)
		local s = C.sel
		if s ~= nil and s.kind == "node" and s.ring == nil and s.slip ~= nil then return C.applySlip("node", "game") end
		out("RESET", { { "mode", "model" }, { "scope", scope } })
		return C.apply(scope, "game")
	end

	--- One GUI frame: due reset judgements, due re-reads, periodic refresh of the selection.
	function C.step()
		C.frames = C.frames + 1
		local i = 1
		while i <= #C.verifies do
			local v = C.verifies[i]
			if C.frames >= v.due then
				table.remove(C.verifies, i)
				local ok, same, total = pcall(W.verify, v.expect)
				if ok then
					if v.kind == "slip" then
						out("VERIFY", { { "src", v.src }, { "kind", "slip" }, { "node", v.ring }, { "same", same }, { "nodes", total } })
					else
						out("VERIFY", { { "src", v.src }, { "ring", v.ring }, { "same", same }, { "nodes", total } })
					end
					C.lastRefresh = -Core.REFRESH_FRAMES -- re-read the selection now
					C.hoverCache.at = -Core.REFRESH_FRAMES
				else
					out("ERROR", { { "where", "verify" }, { "err", same } })
				end
			else
				i = i + 1
			end
		end
		-- the Selector stops calling onHover off street objects: drop a stale hover
		if C.hover ~= nil and C.frames - C.hoverFrame > Core.HOVER_STALE_FRAMES then
			C.hover = nil
			bump()
		end
		if C.sel ~= nil and C.frames - C.lastRefresh >= Core.REFRESH_FRAMES then
			C.lastRefresh = C.frames
			local ok, e = pcall(C.refresh)
			if not ok then out("ERROR", { { "where", "refresh" }, { "err", e } }) end
		end
	end

	--- The tool closes: forget the selection and pending re-reads (writes already sent still land).
	function C.flush()
		C.verifies = {}
		C.hover = nil
		C.sel = nil
		C.result = nil
		bump()
	end

	--- Nodes whose connections the overlay shows: the selected junction, or every junction of the
	-- selected ring.
	function C.viewNodes()
		local s = C.sel
		if s == nil then return {} end
		if s.kind == "node" then return { s.node } end
		return s.junctionNodes or {}
	end

	--- Edges of node n's own transport network (nil when unreadable).
	local function networkEdges(n)
		local ok, tn = pcall(api.engine.getComponent, n, CT().TRANSPORT_NETWORK)
		if not ok or tn == nil or tn.edges == nil then return nil end
		local k = 0
		for _ in ipairs(tn.edges) do k = k + 1 end
		return k
	end

	--- NodeViewer plan: { [node] = { {edgeIdx (0-based), color (palette index)} } }.
	-- edgeIdx = lane connection index (as double_slip_switch.tl:113-118), but the native renderer
	-- asserts edgeIdx < #transportNetwork.edges and the game crashes (2026-10-08: a plain 2-segment
	-- ring node had 2 lane connections and 1 network edge). So a node is drawn only when its network
	-- has at least as many edges as it has connections, and nothing is drawn while a write is
	-- pending (the network is rebuilt after the config changes).
	function C.nodeViewerSpec()
		local spec = {}
		if next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0) then return spec end
		for _, n in ipairs(C.viewNodes()) do
			local conns = W.currentConns(n)
			local nEdges = networkEdges(n)
			if #conns > 0 and nEdges ~= nil and nEdges >= #conns then
				local colors = Pick.colorIndices(conns)
				local list = {}
				for i = 1, #conns do list[#list + 1] = { edgeIdx = i - 1, color = colors[i] } end
				spec[n] = list
			end
		end
		return spec
	end

	local function segsOf(world, t)
		if t == nil then return {} end
		if t.kind == "ring" then return t.ring.segs end
		local node = world.node(t.node)
		return node and node.segs or {}
	end

	--- Entities to highlight (street segments of the hovered and the selected target) and circle
	-- markers { x, y, z, r, kind = "sel" | "ring" | "hover" }.
	function C.highlight()
		local ents, seen = {}, {}
		local function add(list)
			for _, e in ipairs(list) do
				if not seen[e] then
					seen[e] = true
					ents[#ents + 1] = e
				end
			end
		end
		local world = W.makeWorld()
		add(segsOf(world, C.hover))
		add(segsOf(world, C.sel))
		if C.sel and C.sel.ring then add(C.sel.ring.segs) end
		local markers = {}
		local function mark(n, r, kind)
			local node = world.node(n)
			if node then markers[#markers + 1] = { x = node.x, y = node.y, z = node.z, r = r, kind = kind } end
		end
		if C.sel then
			for _, n in ipairs(C.sel.junctionNodes or {}) do
				if n ~= C.sel.node then mark(n, 2.5, "ring") end
			end
			if C.sel.kind == "node" then mark(C.sel.node, 4, "sel") end
		end
		if C.hover and C.hover.kind == "node" and (C.sel == nil or C.hover.node ~= C.sel.node) then
			mark(C.hover.node, 4, "hover")
		end
		return ents, markers
	end

	--- Toolbar buttons that may be clicked now: { applyNode, applyRing, reset } (booleans). All off
	-- without a selection and while a write waits for its callback or re-read (the selection is stale
	-- until then). Cheap: the construction menu asks every step (checkEnabledFn).
	function C.actions()
		local s = C.sel
		local busy = next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0)
		local can = (not busy and s ~= nil and s.can) or {}
		return { applyNode = can.applyNode == true, applyRing = can.applyRing == true, reset = can.reset == true }
	end

	--- Lane status badge of the selection: sl_pick.badge result, or Pick.badgeNone().
	function C.badge()
		if C.sel == nil then return Pick.badgeNone() end
		return C.sel.badge or Pick.badgeNone()
	end

	--- Toolbar status chip for the shown layout.
	function C.status(layout)
		return Pick.status(C.sel, layoutText(layout), C.result)
	end

	return C
end

return Core
