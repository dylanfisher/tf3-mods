-- Smart Lanes tool (Phase 2 step 1): the controller behind the road tool's UI (sl_tool.script.lua).
-- Picking, the selection, Apply (layouts from sl_rules), Reset (writes the game default model) and
-- the frame-timed re-reads. No React here, so tests/square_smart_lanes/test_tool.lua drives it with
-- a fake api. Runs on the GUI thread (the construction menu's Lua state).
--
-- Log lines ([SQRL], stdout.txt):
--   PROBE hover entity=.. kind=node|edge promoted=.. d=.. r=.. target=..  (rate-limited, on change)
--   PICK target=.. ring=.. lanes=.. arms=.. conns=.. badge=smart|default|custom|partial|na findings=.. [skipped=no_config:n]
--                                                                  (a click selected something)
--   APPLY src=tool layout=.. ring=.. node=.. ... turbo=.. turbo_reason=.. before=.. after=.. [entry=.. why=..]
--   WRITE src=tool ring=.. nodes=.. success=..  /  VERIFY src=tool ring=.. same=.. nodes=..
--   Every APPLY src=tool line of a node inside a game zone (sl_zones.lua; the automatic pass leaves those
--   alone) ends in zone=game: Apply there is the player's manual override and works as anywhere else.
--   Inside an sl_fan zone (PHASES_PLAN.md "Fan mode") Apply writes the full fan with its fan plan at a lit
--   crossroads (APPLY ... mode=fan, not audited) and the badge counts that fan as smart; Reset as anywhere.
--   Inside an sl_lock zone Apply keeps the game's light phases and locks the kerb turns (lock_turn=, as
--   Reset; APPLY ... zone=sl_lock free_turn=off), whatever "Free kerb turn" and "Light phases" say.
--   RESET mode=model scope=node|ring   then APPLY / WRITE / VERIFY src=tool layout=game
--   Slip-lane junctions (sl_slip): APPLY / WRITE / VERIFY src=tool kind=slip node=..;
--   Crossroads / T-junctions (sl_cross): RESET mode=model kind=slip node=.. writes the game-default model.
--   Free kerb turn (setting "Free kerb turn at traffic lights", sl_lights.lua L.kerbPhases): Apply at a
--   crossroads / T-junction frees its kerb turns in the lane write itself, When safe only in the
--   phases where nothing green crosses (merges allowed), Always in every phase (WRITE .. free_turn=<kerb connections>
--   free_phases=<(connection, phase) unlocks> [kept=cross:n,ped:n merge_free=n]); Reset locks them back
--   with their approach (lock_turn=.. lock_phases=..). Where
--   the lanes stay, a phases-only light proposal does it (LIGHTS src=tool|reset to=free_turn|lock_turn).
--   Light phases (setting "Light phases", PHASES_PLAN.md step 4): Game default (the default) changes
--   nothing here. Smart Lanes: Apply at a lit crossroads / T-junction (case X, X.litOf true) writes a
--   Smart Lanes phase plan (sl_phaseplan.lua) with the lanes, from the final connections and crosswalks
--   of the same proposal (no free kerb turn on top; no valid plan: the free kerb turn as before). WRITE
--   gains phases=game|sl, single nodes plan=<PP.planText> | plan_fail=<reason>, batches sl_plans=
--   plan_fails=; each planned node logs PHASES src=tool node= phases=sl plan=|plan_fail=. Lanes already
--   right: a phases-only proposal (W.planLights, LIGHTS src=tool to=sl_phases plan=..). Reset with Smart
--   Lanes: the game's default phases back with the Crossing window's own "Reset to Default" (states =
--   {}, W.defaultLights, LIGHTS src=reset to=game_phases), sent after the lane write answered (the
--   lane write itself re-points the phases with the kerb turns locked, as with Game default).
--   RESET mode=snapshot|unavailable kind=slip node=.. (no engine-default model for slip nodes: Reset
--   writes back what the node had before the tool's first Apply on it in this session)
--   Lane drops / gains (sl_slip case "D"): as slip nodes (APPLY kind=drop, snapshot Reset), lights kept.
--   Streets (PHASE7.md step 4, sl_street.lua; user decision 2026-10-11 "Ends only, Shift extends"):
--   a click (and hover) in the middle of an ordinary segment selects the handled junctions at the
--   segment's two ends (through plain nodes to the first junction each way, lane drops between
--   included: Street.walk ends mode); Shift+click (C.shiftHeld at the click) follows the street
--   through junctions (follow mode, caps Street.MAX_JUNCTIONS / MAX_DIST). Rings excluded, they have
--   Apply to roundabout. Target key "street:<seg>" (ends) / "street+:<seg>" (follow).
--   PICK target=street:<seg> mode=ends|follow junctions=.. segs=.. dist=.. stops=<end b>,<end a> nodes=<ids>
--   STREET op=apply|reset street=<seg> mode=ends|follow junctions=.. batches=..   (Apply to junction / Reset clicked)
--   APPLY src=tool scope=street street=<seg> kind=slip|drop node=.. ...   (one per node written)
--   RESET mode=model|snapshot|unavailable|stale scope=street street=<seg> node=..
--   SKIP src=tool scope=street street=<seg> node=.. reason=gone|no_config|ring|<classify reason>|conns
--   WRITE src=tool|reset scope=street street=<seg> batch=<i>/<n> nodes=.. success=..   (per batch of
--   at most BATCH_NODES nodes: one proposal through W.sendConfigs, one batch per frame)
--   VERIFY src=tool|reset scope=street street=<seg> same=.. nodes=..   (per batch)
--   Multi selection (PHASE7.md step 5b): Shift+click with something selected adds a junction (or
--   removes it when it is in the selection already), adds a road's junctions (the Shift street,
--   Street.walk follow mode) or a roundabout's; the selection becomes target kind "multi" (cap
--   Core.MULTI_MAX junctions). Ring junctions join too: Apply plans them with Rules.planRing seeded
--   with the selected junctions of that ring (the ring node rules, as Apply to junction), Reset
--   writes the engine-default model, both in the same batch job as streets. A street or ring
--   Shift+clicked that holds the whole selection replaces it (a plain-clicked street Shift+clicked
--   follows it further, step 4b). A plain click starts a new selection; right click / Esc clears.
--   PICK target=multi op=add|remove|none item=node:<id>|street+:<seg>|ring:<key> added=.. removed=..
--     junctions=.. nodes=<ids> badge=..   (op=none: the item has no handled junction, not added)
--   SKIP src=tool scope=multi reason=cap max=60 dropped=..   (Shift+click past the cap)
--   SKIP src=tool scope=multi nodes=<ids> reason=gone   (refresh: selected junctions bulldozed)
--   MULTI op=apply|reset junctions=.. batches=..   (Apply to junction / Reset clicked)
--   APPLY src=tool scope=multi kind=slip|drop node=.. ...  /  APPLY src=tool scope=multi layout=..
--     ring=.. node=.. ...   (a ring junction)
--   RESET mode=model|snapshot|unavailable|stale scope=multi [ring=..] node=..
--   SKIP src=tool scope=multi node=.. reason=..  /  WRITE / VERIFY src=tool|reset scope=multi ..
--   Audit (sl_audit.lua, TESTING.md X): a pick audits the picked junction(s) with their current connections
--   (a node; a ring's or street's junctions; the junctions a Shift+click adds): PICK gains findings=<kind:n,..
--   summed> and each junction with findings logs AUDIT node=.. case=.. shape=.. findings=.. [forced=..]
--   detail=.. src=pick (lights read too: a slip / ring arm node that still has a light). Apply to junction /
--   roundabout / street / multi audits the connections it planned (written or already set): AUDIT .. src=tool
--   [scope=..], after the proposal was sent. Never throws (ERROR where=audit).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Lights = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local Street = ug_require "square_smart_lanes::/smart_lanes/sl_street.lua"
local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"
local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"

local Core = {}

Core.VERIFY_DELAY = 30      -- frames after a write callback before the nodes are re-read
Core.CALLBACK_TIMEOUT = 600 -- frames without a callback after which a reset is judged anyway
Core.HOVER_LOG_GAP = 0.3    -- s between PROBE hover lines (only on a change of target)
Core.REFRESH_FRAMES = 30    -- frames between re-reads of the selection (counts, overlay)
Core.HOVER_STALE_FRAMES = 10 -- frames without onHover after which the hover highlight goes
Core.BADGE_CACHE_MAX = 64   -- lane status badge cache entries (cleared when full)
Core.NODE_STATUS_MAX = 256  -- per-junction status cache entries (cleared when full)
Core.NODE_STATUS_FRAMES = 300 -- frames a per-junction status is reused (its segments and connections unchanged)
Core.BATCH_NODES = 40       -- street Apply / Reset: nodes per proposal (one batch per frame)
Core.MULTI_MAX = 60         -- junctions in a Shift+click (multi) selection
Core.VIEW_MAX = 60          -- junctions the NodeViewer draws at once
-- The game's "(Hold)" modifier, Shift by default, read as Bulk Bulldozer does
-- (bulk_bulldozer.script.tl shiftHeld; base script_param_util.tl:171).
Core.IA_SHIFT = "IA_PRECISION_MODE"

-- Display name of a layout (Rules.LAYOUT_NAMES stays English: the game script and the log use it).
-- Translated when called (the tool's GUI Lua state).
local function layoutText(layout)
	local names = { matched = _("Matched lanes"), turbo = _("Smart lanes"), game = _("Game default") }
	return names[layout] or tostring(layout)
end

-- SQPERF stand-in when the caller passes no instrument (tests): the same calls, no clock.
local NO_PERF = { start = function() return 0 end, stop = function() end, count = function() end }

--- api: game api (or fake); out(kind, fields): log; clock(): seconds (os.clock in game); perf: the
-- tool script's SQPERF instrument (plans/sqperf/README.md) or nil. Sections (PHASE7.md step 7; they
-- nest inside the script's hover / select / step / apply_* sections): resolve (a pick: world reads,
-- ring search, street walk, badge), badge (badge and button states of a target), refresh (the
-- selection's re-read every REFRESH_FRAMES), multi_add (a Shift+click into the selection), batch
-- (one street / multi batch: planning and its proposal), nv_spec (the lane view's spec, when built),
-- highlight (the highlighted segments and markers per world render).
function Core.new(api, out, clock, perf)
	perf = perf or NO_PERF
	-- PROBE phases (W.probePhases on picks) only with the "Debug: performance log" setting On
	-- through `out` as wrapped below (SL-3 zid= on the write path's LIGHTS / PHASES lines too)
	local W = Write.new(api, function(kind, fields) return out(kind, fields) end, { probeOn = function() return perf.on == true end })
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
		badgeCache = {},    -- "ring:<key>" / "street:<seg>" / multi key -> { text, res } (lane status badge)
		nodeStatus = {},    -- junction -> { key, at, res, ringChecked } (C.nodeStatusOf; badge of nodes, streets, multi)
		nodeStatusCount = 0,
		nodeKind = {},      -- node -> { key, at, slip, ring } (C.nodeKindOf; street walks)
		nodeKindCount = 0,
		hoverWorld = nil,   -- { world, at }: the world hover resolves share (display only, C.onHover)
		job = nil,          -- street / multi Apply / Reset in progress (batches sent one per frame)
		multiSeq = 0,       -- id of the latest multi selection (a Shift+click makes a new one)
		nvCache = nil,      -- street / multi NodeViewer spec { ident, sig, at, spec } (C.nodeViewerSpec)
		nvHeld = false,     -- an empty spec was handed out while a write was pending (C.step re-renders)
		badgeStats = { hits = 0, misses = 0 },
	}
	clock = clock or os.clock

	-- Zones (sl_zones.lua): the tool's Apply is the player's choice and works in a game zone too (a manual
	-- override); its APPLY lines there carry zone=game. The zones are read from the game script's saved state
	-- (Zones.readSaved, GAME_SCRIPT component) at most once per frame, when an Apply / Reset starts.
	C.zones, C.zonesFrame = nil, nil
	local function refreshZones()
		if C.zonesFrame == C.frames then return end
		C.zonesFrame = C.frames
		C.zones = Zones.readSaved(api)
		-- worlds made from now on see them (sl_write world.exitFan: the exit fan in sl_exitfan zones)
		W.zones = C.zones
	end
	--- The zone record (sl_zones.lua) node n lies in, from the last zone read; nil outside or without zones.
	local function zoneRecOf(n)
		if C.zones == nil or #C.zones == 0 or type(n) ~= "number" then return nil end
		local ok, p = pcall(function()
			local bn = api.engine.getComponent(n, api.type.ComponentType.BASE_NODE)
			return bn and bn.position
		end)
		if not ok or p == nil then return nil end
		return Zones.zoneAt(C.zones, p.x, p.y)
	end
	local function zoneOfNode(n)
		local z = zoneRecOf(n)
		return z and z.ab or nil
	end
	--- Slip.plan opts for node n of `world`: { fan = true } inside an sl_fan zone (PHASES_PLAN.md "Fan
	-- mode": Apply writes the full fan with its fan plan at a lit crossroads; the badge counts the fan as
	-- smart there), else nil. Uses the zones of the last refreshZones.
	local function planOpts(world, n)
		if C.zones == nil or #C.zones == 0 then return nil end
		if Zones.nodeAb(C.zones, world, n) == "sl_fan" then return { fan = true } end
		return nil
	end
	local rawOut = out
	out = function(kind, fields)
		if kind == "APPLY" and C.zones ~= nil and #C.zones > 0 and type(fields) == "table" then
			local node, tool = nil, false
			for _, kv in ipairs(fields) do
				if kv[1] == "node" then node = kv[2] end
				if kv[1] == "src" and kv[2] == "tool" then tool = true end
			end
			if tool then
				local ab = zoneOfNode(node)
				if ab == "game" then fields[#fields + 1] = { "zone", "game" }
				elseif ab == "sl_lock" then
					-- the kerb turn stays locked there (phaseFor), whatever the setting
					fields[#fields + 1] = { "zone", "sl_lock" }
					fields[#fields + 1] = { "free_turn", "off" }
				elseif ab == "sl_exitfan" then
					-- the exit fan at lit crossroads, the game's phases (phasesAt)
					fields[#fields + 1] = { "zone", "sl_exitfan" }
				end
			end
		end
		-- SL-3: zid=<the zone's id label> on the lines of nodes in a zone with an id
		if (kind == "APPLY" or kind == "SKIP" or kind == "LIGHTS" or kind == "PHASES" or kind == "AUDIT")
			and C.zones ~= nil and #C.zones > 0 and type(fields) == "table" then
			local node, has = nil, false
			for _, kv in ipairs(fields) do
				if kv[1] == "node" and type(kv[2]) == "number" then node = kv[2] end
				if kv[1] == "zid" then has = true end
			end
			local id = (node ~= nil and not has) and Zones.idOf(zoneRecOf(node)) or nil
			if id ~= nil then fields[#fields + 1] = { "zid", id } end
		end
		return rawOut(kind, fields)
	end

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

	--- Identity of a selection for "is this still the selection the job / overlay was made for":
	-- the target key, for a multi selection its id (kept by C.refresh, new on every Shift+click).
	local function selIdent(t)
		if t ~= nil and t.kind == "multi" then return "multi#" .. tostring(t.multiId) end
		return Pick.targetKey(t)
	end

	--- Whether a Reset snapshot still fits node n (crash rule 3): every connection names segments
	-- attached to the node now, with lane indices inside them. A road rebuilt since the Apply (an
	-- upgrade at a lane drop gives new segment ids) makes the snapshot stale: never written.
	local function snapFits(world, n, snap)
		local node = world.node(n)
		if node == nil then return false end
		local here = {}
		for _, sid in ipairs(node.segs or {}) do here[sid] = true end
		for _, c in ipairs(snap) do
			local s0 = here[c.segment0] and world.seg(c.segment0)
			local s1 = here[c.segment1] and world.seg(c.segment1)
			if not s0 or not s1 then return false end
			if c.lane0 < 0 or c.lane0 >= #s0.lanes or c.lane1 < 0 or c.lane1 >= #s1.lanes then return false end
		end
		return true
	end

	--- Node n's current connections for the badge, the buttons and the signature (display only, never
	-- for a write): read once per world (world.memo of W.makeWorld), so one refresh or pick reads each
	-- junction's config once instead of three times.
	local function connsIn(world, n)
		local memo = world.memo
		if memo == nil then return W.currentConns(n) end
		local m = memo.conns
		if m == nil then
			m = {}
			memo.conns = m
		end
		local c = m[n]
		if c == nil then
			c = W.currentConns(n)
			m[n] = c
		end
		return c
	end

	--- AUDIT lines (sl_audit.lua) of junctions `items` ({ node, conns, view, ring }) in `world`. Returns the
	-- sum (Audit.newSum) and the lines' field lists, which the caller logs (after its PICK line). planned:
	-- { [node] = conns } the weave look-ahead prefers (a write's plan), else the junction's current
	-- connections. lights: read each node's traffic light (picks). Never throws (an error is logged).
	local function auditItems(world, items, extra, planned, lights)
		local sum, lines = Audit.newSum(), {}
		local function connsOf(J)
			local p = planned and planned[J]
			if p ~= nil then return p end
			return connsIn(world, J)
		end
		local lightsOf = nil
		if lights then lightsOf = function(n) return W.lightState(n) end end
		local ok, e = pcall(function()
			for _, it in ipairs(items) do
				local res, eA = Audit.safe(world, it.node, it.conns, { view = it.view, ring = it.ring, connsOf = connsOf,
					lightsOf = lightsOf })
				-- the first failure of this call is logged (a 60-junction pick never floods the log)
				if res == nil and sum.failed == 0 then out("ERROR", { { "where", "audit" }, { "node", it.node }, { "err", eA } }) end
				Audit.addTo(sum, res)
				if res ~= nil and res.total > 0 then lines[#lines + 1] = Audit.fields(res, extra) end
			end
		end)
		if not ok then out("ERROR", { { "where", "audit" }, { "err", e } }) end
		return sum, lines
	end
	local function logAudit(_sum, lines)
		for _, f in ipairs(lines or {}) do out("AUDIT", f) end
	end

	--- The audit of picked junctions `nodes` (at most Core.MULTI_MAX) with their current connections: ring
	-- junctions with their ring view, others with Slip.classify's (unhandled junctions too: their
	-- connections are what the game made). Returns sum, lines (nil, {} when it failed). A node without a
	-- BASE_NODE_CONFIG (the game routes it without one: a plain road continuation, a dual carriageway's
	-- split; the automatic pass skips it as no_config) is not audited: its empty connection list is no
	-- dead or unfed lane. sum.skips counts them by reason: no_config, or config_error when the read threw
	-- (PICK skipped=..).
	local function auditPick(world, nodes)
		local skips = {}
		local ok, items = pcall(function()
			local list = {}
			for i, n in ipairs(nodes or {}) do
				if i > Core.MULTI_MAX then break end
				local okC, cfg = pcall(api.engine.getComponent, n, CT().BASE_NODE_CONFIG)
				local reason = (not okC and "config_error") or (cfg == nil and "no_config") or nil
				if reason ~= nil and world.node(n) ~= nil then
					skips[reason] = (skips[reason] or 0) + 1
				elseif world.node(n) ~= nil then
					local it = { node = n, conns = connsIn(world, n) }
					local ring = Ring.ringThrough(world, n)
					if ring ~= nil then
						it.ring, it.view = ring, Ring.nodeView(world, ring, n)
					else
						it.view = Slip.classify(world, n)
					end
					list[#list + 1] = it
				end
			end
			return list
		end)
		if not ok then
			out("ERROR", { { "where", "audit" }, { "err", items } })
			return nil, {}
		end
		-- read-only dump of each picked lit node's phases (debug setting On; once per node, capped)
		for _, it in ipairs(items) do pcall(W.probePhases, it.node, world) end
		local sum, lines = auditItems(world, items, { { "src", "pick" } }, nil, true)
		if next(skips) ~= nil then sum.skips = skips end
		return sum, lines
	end
	local function findingsText(sum) return sum and Rules.countsText(sum.counts) or "?" end
	--- Appends skipped=<reason:n,..> to PICK fields f when the pick audit skipped junctions (auditPick).
	local function skippedField(f, sum)
		if sum and sum.skips then f[#f + 1] = { "skipped", Rules.countsText(sum.skips) } end
		return f
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
			cur[n] = connsIn(world, n)
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
		local function get(n) return cur[n] or connsIn(world, n) end
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

	--- Status of a non-ring junction n from its plan: { smart = bool, model = bool, case, default = bool
	-- or nil (no model there) } or { skip = true }. Kept per junction (C.nodeStatus), keyed by the
	-- node's segments and its road connections, for at most NODE_STATUS_FRAMES frames (the plan also
	-- looks along the roads, and a crossroads plans with its traffic lights, sl_cross X.litOf: a change
	-- further away or a light switched on or off shows within that time), and shared by the node,
	-- street and multi targets, so a Shift+click into a big selection plans only the junction it adds.
	-- Display only: Apply and Reset plan every junction again in a world read in their frame.
	-- ringCheck: the caller needs to know the node is on no ring (a multi selection or a junction
	-- pick): an entry made without that check (a street junction) is not used, and a node on a ring
	-- returns nil, ring (its status is the ring's).
	function C.nodeStatusOf(world, n, cur, ringCheck)
		local node = world.node(n)
		-- an sl_fan zone's fan counts as smart there (zones read at most once per frame)
		refreshZones()
		local opts = planOpts(world, n)
		local exitFan = C.zones ~= nil and #C.zones > 0 and Zones.nodeAb(C.zones, world, n) == "sl_exitfan"
		local key = segsText(node and node.segs) .. ":" .. Rules.roadText(cur) .. (opts and ":fan" or "") .. (exitFan and ":exitfan" or "")
		local e = C.nodeStatus[n]
		if e ~= nil and e.key == key and C.frames - e.at < Core.NODE_STATUS_FRAMES and (e.ringChecked or not ringCheck) then
			C.badgeStats.hits = C.badgeStats.hits + 1
			return e.res
		end
		C.badgeStats.misses = C.badgeStats.misses + 1
		if ringCheck then
			local ring = Ring.ringThrough(world, n)
			if ring ~= nil then return nil, ring end
		end
		local res
		-- one odd node never loses the whole badge
		local okP, r = pcall(Slip.plan, world, n, function() return cur end, opts)
		if okP and (r.status == "same" or r.status == "apply") and r.conns ~= nil then
			local road = Rules.roadText(cur)
			local model = Slip.defaultConns(r.view)
			-- default: per movement (Slip.isDefault), the engine's lane choice varies per approach
			res = { smart = Rules.roadText(r.conns) == road, model = model ~= nil, case = r.view.case,
				default = model ~= nil and (Rules.roadText(model) == road or Slip.isDefault(r.view, cur) == true) or nil }
		else
			res = { skip = true }
		end
		if e == nil then
			if C.nodeStatusCount >= Core.NODE_STATUS_MAX then
				C.nodeStatus, C.nodeStatusCount = {}, 0
			end
			C.nodeStatusCount = C.nodeStatusCount + 1
		end
		C.nodeStatus[n] = { key = key, at = C.frames, res = res, ringChecked = ringCheck == true }
		return res
	end

	--- Badge info of a slip node (no ring through it): smart or not, and default where the game has a
	-- model (crossroads).
	local function slipBadgeInfo(world, n)
		local st = C.nodeStatusOf(world, n, connsIn(world, n), true)
		if st == nil or st.skip then return { kind = "na" } end
		local info = { kind = "slip", total = 1, smart = st.smart and 1 or 0 }
		if st.model then info.default = st.default and 1 or 0 end
		return info
	end

	--- Per street (or multi selection) junction: { smart = bool, default = bool or nil (no model
	-- there), model = bool, case, ring } or { skip = true }, keyed by node. One cache entry per
	-- street, keyed by the clicked segment + every junction's segments and road connections, so an
	-- unchanged selection costs one config read per junction; on a change only the junctions whose own
	-- segments or connections changed are planned again (C.nodeStatusOf). A multi selection (target
	-- key: its node ids) may hold ring junctions: their status is the ring's (ringStatuses, one ring
	-- search per ring), with the engine-default model. Kept per world too (badge and buttons of one
	-- pick ask twice).
	local function streetStatuses(world, t)
		local memo = world.memo
		local wm = memo and memo.street
		if wm ~= nil and wm[t] ~= nil then return wm[t] end
		local cur, parts = {}, {}
		for _, n in ipairs(t.junctionNodes or {}) do
			cur[n] = connsIn(world, n)
			local node = world.node(n)
			parts[#parts + 1] = tostring(n) .. "=" .. segsText(node and node.segs) .. ":" .. Rules.roadText(cur[n])
		end
		local ck, text = Pick.targetKey(t), table.concat(parts, ";") -- ends / follow apart
		local hit = C.badgeCache[ck]
		local res
		if hit ~= nil and hit.text == text then
			C.badgeStats.hits = C.badgeStats.hits + 1
			res = hit.res
		else
			C.badgeStats.misses = C.badgeStats.misses + 1
			res = {}
			local multi = t.kind == "multi"
			local rings = {} -- node -> ring found in this pass (several junctions of one ring: one search)
			for _, n in ipairs(t.junctionNodes or {}) do
				local ring = rings[n]
				local st = nil
				if ring == nil then
					local okN, a, b = pcall(C.nodeStatusOf, world, n, cur[n], multi)
					if not okN then
						-- unknown whether n is on a ring: no status (one odd node never loses the badge)
						st = { skip = true }
					elseif a ~= nil then
						st = a
					elseif b ~= nil then
						ring = b
						for _, rn in ipairs(b.nodes or {}) do rings[rn] = b end
					end
				end
				if ring ~= nil then
					local okS, rst = pcall(ringStatuses, world, ring)
					local rs = okS and rst[n] or nil
					if rs ~= nil and not rs.skip then
						res[n] = { smart = rs.smart, default = rs.default, model = true, ring = ring.key }
					else
						res[n] = { skip = true }
					end
				else
					res[n] = st or { skip = true }
				end
			end
			cachePut(ck, text, res)
		end
		if memo ~= nil then
			memo.street = wm or {}
			memo.street[t] = res
		end
		return res
	end

	--- Lane status badge info of a pick target (sl_pick.badge input).
	function C.badgeInfo(world, t)
		if t == nil then return nil end
		if t.kind == "street" or t.kind == "multi" then
			-- default: counted only when every junction has a game-default model (crossroads, rings)
			local st = streetStatuses(world, t)
			local info = { kind = t.kind, total = 0, smart = 0, default = 0 }
			local models = true
			for _, n in ipairs(t.junctionNodes or {}) do
				local s = st[n]
				if s ~= nil and not s.skip then
					info.total = info.total + 1
					if s.smart then info.smart = info.smart + 1 end
					if s.default then info.default = info.default + 1 end
					if not s.model then models = false end
				end
			end
			if info.total == 0 then return { kind = "na" } end
			if not models then info.default = nil end
			return info
		end
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
		elseif t.kind == "street" then
			parts[#parts + 1] = segsText(t.segs)
			nodes = t.junctionNodes or {}
		elseif t.kind == "multi" then
			nodes = t.junctionNodes or {}
			for _, n in ipairs(nodes) do
				local node = world.node(n)
				parts[#parts + 1] = segsText(node and node.segs)
			end
		else
			local node = world.node(t.node)
			parts[#parts + 1] = segsText(node and node.segs)
			nodes = { t.node }
		end
		for _, n in ipairs(nodes) do parts[#parts + 1] = Rules.connsText(connsIn(world, n)) end
		return table.concat(parts, "|")
	end

	--- Which toolbar buttons would change something for target t: { applyNode, applyRing, reset }.
	-- From the same per-junction statuses as the badge (cached), so a button is enabled exactly
	-- when its click would write: Apply where a handled junction is not smart lanes yet, Reset
	-- where one differs from the game default model (slip nodes: from the snapshot of the first Apply).
	function C.canInfo(world, t)
		local can = { applyNode = false, applyRing = false, reset = false }
		if t.kind == "street" or t.kind == "multi" then
			-- Apply to junction writes the whole street / selection; Apply to roundabout stays off
			local st = streetStatuses(world, t)
			for _, n in ipairs(t.junctionNodes or {}) do
				local s = st[n]
				if s ~= nil and not s.skip then
					if not s.smart then can.applyNode = true end
					if s.model then
						if not s.default then can.reset = true end
					elseif not can.reset then
						local snap = C.snapshots[n]
						can.reset = snap ~= nil and Rules.connsText(snap) ~= Rules.connsText(connsIn(world, n))
							and snapFits(world, n, snap)
					end
				end
			end
		elseif t.ring ~= nil then
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
			if info.default ~= nil then
				-- crossroads: Reset writes the game-default model
				can.reset = info.kind == "slip" and info.default == 0
			else
				local snap = C.snapshots[t.node]
				can.reset = snap ~= nil and Rules.connsText(snap) ~= Rules.connsText(connsIn(world, t.node))
					and snapFits(world, t.node, snap)
			end
		end
		return can
	end

	--- Sets t.badge (sl_pick.badge result; a failure is logged and leaves t.badge nil), t.can
	-- (C.canInfo; all false on a failure) and t.sig.
	local function addBadge(world, t)
		if t == nil then return t end
		local tBadge = perf:start()
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
		perf:stop("badge", tBadge)
		return t
	end

	--- Pick-target info for node n (nil when n is not a street node).
	-- { kind = "node", node, roads, conns, ring, ringKey, ringLanes, junctions, junctionNodes,
	--   nodeKind, exits, entries, reason }
	local function nodeTarget(world, n)
		local node = world.node(n)
		if not node or #node.segs == 0 then return nil end
		local t = { kind = "node", node = n, roads = #node.segs, conns = #connsIn(world, n), x = node.x, y = node.y, z = node.z }
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

	--- Whether node n is handled (Slip.classify kind "slip") or, what = "ring", on a roundabout
	-- (Ring.ringThrough), for street walks: kept per node (C.nodeKind) keyed by its segments, for at
	-- most NODE_STATUS_FRAMES frames, so the refresh of a selected street (every REFRESH_FRAMES) does
	-- not classify every junction again nor search a ring at every one-way junction. A failing check
	-- is "not handled" / "a ring" (the walk stops there) and is not kept. Display and selection only:
	-- Apply plans every junction again (gone, no config, on a ring, no longer handled: skipped).
	function C.nodeKindOf(world, n, what)
		local node = world.node(n)
		local key = segsText(node and node.segs)
		local e = C.nodeKind[n]
		if e == nil or e.key ~= key or C.frames - e.at >= Core.NODE_STATUS_FRAMES then
			if e == nil then
				if C.nodeKindCount >= Core.NODE_STATUS_MAX then
					C.nodeKind, C.nodeKindCount = {}, 0
				end
				C.nodeKindCount = C.nodeKindCount + 1
			end
			e = { key = key, at = C.frames }
			C.nodeKind[n] = e
		end
		if what == "ring" then
			if e.ring == nil then
				local ok, r = pcall(Ring.ringThrough, world, n)
				if not ok then return true end
				e.ring = r ~= nil
			end
			return e.ring
		end
		if e.slip == nil then
			local ok, v = pcall(Slip.classify, world, n)
			if not ok or v == nil then return false end
			e.slip = v.kind == "slip"
		end
		return e.slip
	end

	--- The street through segment seg (sl_street.lua): nil when it has no handled junction.
	-- Handled = Slip.classify kind "slip" (cases A, B, X, D); ring junctions end the street.
	-- follow: Shift+click, Street.walk follow mode; else ends mode (the junctions at both ends).
	local function streetTarget(world, seg, follow)
		follow = follow == true
		-- one odd node never loses the whole street: a failing check is "not handled" / "a ring" (stop)
		local st = Street.walk(world, seg, {
			ends = not follow,
			handled = function(n) return C.nodeKindOf(world, n, "slip") end,
			isRing = function(n) return C.nodeKindOf(world, n, "ring") end,
		})
		if st == nil or #st.junctions == 0 then return nil end
		local segSet = {}
		for _, sid in ipairs(st.segs) do segSet[sid] = true end
		local t = { kind = "street", seg = seg, follow = follow, segs = st.segs, segSet = segSet,
			junctionNodes = st.junctions, junctions = #st.junctions, dist = st.dist, stops = st.stops }
		return addBadge(world, t)
	end

	--- A multi selection of `nodes` (PHASE7.md step 5b): the ones still in the world (with road
	-- segments), duplicates dropped, at most Core.MULTI_MAX; nil when none is left. pos: each node's
	-- position for the overlay markers (no reads per render). id: selIdent (C.multiSeq).
	local function multiTarget(world, nodes, id)
		local list, set, pos = {}, {}, {}
		for _, n in ipairs(nodes or {}) do
			if #list >= Core.MULTI_MAX then break end
			if not set[n] then
				local node = world.node(n)
				if node ~= nil and #node.segs > 0 then
					set[n] = true
					list[#list + 1] = n
					pos[n] = { x = node.x, y = node.y, z = node.z }
				end
			end
		end
		if #list == 0 then return nil end
		return addBadge(world, { kind = "multi", multiId = id, junctionNodes = list, junctions = #list,
			nodeSet = set, pos = pos })
	end

	--- Pick target for a Selector hit. entity: what the Selector reports; cursor: {x, y} or nil.
	-- Node hit -> that node; street edge hit near an end (Pick.promote) -> that end node; street edge
	-- hit in the middle of a ring segment -> the whole ring; in the middle of another segment -> the
	-- street through it (the handled junctions at its ends, or with opts.shift every one along it;
	-- nil when none); anything else -> nil.
	-- Returns target, info {entityKind = "node"|"edge"|"other", promoted, d, r}.
	-- opts.world: the world to read (the hover world, C.onHover); else one read now.
	local function resolveBody(entity, cursor, opts)
		local info = { entityKind = "other", promoted = false }
		if type(entity) ~= "number" or entity < 0 then return nil, info end
		local world = (opts ~= nil and opts.world) or W.makeWorld()
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
		return streetTarget(world, entity, opts ~= nil and opts.shift == true), info
	end
	function C.resolve(entity, cursor, opts)
		local t0 = perf:start()
		local t, info = resolveBody(entity, cursor, opts)
		perf:stop("resolve", t0)
		return t, info
	end

	--- Whether Shift (Core.IA_SHIFT) is held now. Read at the click only (the GUI Main Thread, the
	-- Selector's onSelect); false when it cannot be read (the click then acts as a plain one).
	function C.shiftHeld()
		local ok, on = pcall(function()
			return api.gui.inputAction.modifierOnlyActionIsActive(Core.IA_SHIFT)
		end)
		return ok and on == true
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

	--- A street target already resolved that runs through edge `entity` (its middle hovered): the
	-- selected street (re-read every REFRESH_FRAMES by C.refresh), else the street hovered less than
	-- REFRESH_FRAMES ago. Returns target, frame it was read at; nil when none. Moving the cursor
	-- along a street then costs no new walk. Hover shows the plain-click (ends) street, so only an
	-- ends street is reused: a Shift-selected (follow) street is not what a click there would select.	-- A capped ends street (max_drops / max_dist / max_nodes: the shared caps count from the clicked
	-- segment) depends on where it was clicked, so it is only reused for that segment.
	local CAP_STOPS = { max_drops = true, max_dist = true, max_nodes = true }
	local function reusable(t, entity)
		if t == nil or t.kind ~= "street" or t.follow or t.segSet == nil or not t.segSet[entity] then return false end
		local stops = t.stops or {}
		return entity == t.seg or not (CAP_STOPS[stops.a] or CAP_STOPS[stops.b])
	end
	local function knownStreet(entity)
		local s = C.sel
		if reusable(s, entity) then
			return s, C.frames
		end
		local hc = C.hoverCache
		local h = hc.target
		if reusable(h, entity)
			and C.frames - hc.at < Core.REFRESH_FRAMES then
			return h, hc.at
		end
		return nil
	end

	--- The world hover resolves read: kept for at most REFRESH_FRAMES frames (as long as a hover target
	-- is reused anyway) and dropped at every write and re-read (C.dropHoverWorld), so moving the
	-- cursor along a street, or from junction to junction, reads and classifies each node once. Hover
	-- only shows things: a click (C.select), a refresh and every write read a world of their own.
	local function hoverWorld()
		local hw = C.hoverWorld
		if hw == nil or C.frames - hw.at >= Core.REFRESH_FRAMES then
			hw = { world = W.makeWorld(), at = C.frames }
			C.hoverWorld = hw
		end
		return hw.world
	end
	function C.dropHoverWorld() C.hoverWorld = nil end

	--- Selector onHover. Re-resolves (ring search, street walk) only when the quick key changes, or
	-- every REFRESH_FRAMES frames; an edge middle on a street already resolved reuses it.
	function C.onHover(entity, cursor)
		C.hoverFrame = C.frames
		local target, info
		local okK, qk = pcall(quickKey, entity, cursor)
		local edgeMid = okK and qk == "e:" .. tostring(entity)
		if okK then qk = tostring(entity) .. "|" .. qk end -- info (edge / node, promoted) is per entity
		local hc = C.hoverCache
		local known, knownAt
		if edgeMid and not (hc.key == qk and C.frames - hc.at < Core.REFRESH_FRAMES) then
			known, knownAt = knownStreet(entity)
		end
		if type(entity) == "number" and entity >= 0 and okK and hc.key == qk and C.frames - hc.at < Core.REFRESH_FRAMES then
			target, info = hc.target, hc.info
		elseif known ~= nil then
			target, info = known, { entityKind = "edge", promoted = false }
			C.hoverCache = { key = qk, at = knownAt, target = target, info = info }
		else
			local okR, t, inf = pcall(function() return C.resolve(entity, cursor, { world = hoverWorld() }) end)
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

	--- A junction the tool writes when Shift+clicked into a multi selection: a slip-lane junction
	-- (cases A, B, X, D) or a roundabout arm junction.
	local function handledNode(t)
		return t ~= nil and t.kind == "node" and (t.slip ~= nil or (t.ring ~= nil and t.nodeKind == "arm"))
	end

	--- The junctions of a selection as a new list (a single junction only when handled).
	local function memberNodes(s)
		local list = {}
		if s == nil then return list end
		if s.kind == "node" then
			if handledNode(s) then list[1] = s.node end
			return list
		end
		for _, n in ipairs(s.junctionNodes or {}) do list[#list + 1] = n end
		return list
	end

	--- Shift+click with a selection (C.select): the clicked item joins the selection, which becomes
	-- a multi one. Returns true when done; false when the click is to act as a plain one (nothing
	-- handled selected yet, or a street / ring that holds the whole selection).
	local function addToSelection(target)
		local base = memberNodes(C.sel)
		if #base == 0 then return false end
		local item = Pick.targetKey(target)
		local function pick(op, added, removed, t, audit)
			local ids = {}
			for i, n in ipairs(t and t.junctionNodes or {}) do ids[i] = tostring(n) end
			local f = { { "target", "multi" }, { "op", op }, { "item", item }, { "added", added }, { "removed", removed },
				{ "junctions", #ids }, { "nodes", #ids > 0 and table.concat(ids, ",") or "-" },
				{ "badge", t and t.badge and t.badge.key or "-" } }
			-- the audit of the junctions this click added (false: it failed)
			if audit ~= nil then
				f[#f + 1] = { "findings", findingsText(audit or nil) }
				skippedField(f, audit or nil)
			end
			out("PICK", f)
		end
		if target == nil or (target.kind == "node" and not handledNode(target))
			or (target.kind ~= "node" and #(target.junctionNodes or {}) == 0) then
			-- the selection stays as it is
			pick("none", 0, 0, C.sel.kind == "multi" and C.sel or nil)
			setResult(_("Not handled: not added to the selection"))
			return true
		end
		local set = {}
		for _, n in ipairs(base) do set[n] = true end
		local list, adds, added, removed, dropped = base, {}, 0, 0, 0
		local addedNodes = {}
		if target.kind == "node" then
			if set[target.node] then
				list = {}
				for _, n in ipairs(base) do
					if n ~= target.node then list[#list + 1] = n end
				end
				removed = 1
			else
				adds = { target.node }
			end
		else
			-- a street / ring holding the whole selection is the selection (Step 4b: a plain-clicked
			-- street Shift+clicked again is followed further)
			adds = target.junctionNodes
			local inside = {}
			for _, n in ipairs(adds) do inside[n] = true end
			local all = true
			for _, n in ipairs(base) do
				if not inside[n] then
					all = false
					break
				end
			end
			if all then return false end
		end
		for _, n in ipairs(adds) do
			if not set[n] then
				if #list >= Core.MULTI_MAX then
					dropped = dropped + 1
				else
					set[n] = true
					list[#list + 1] = n
					added = added + 1
					addedNodes[#addedNodes + 1] = n
				end
			end
		end
		C.lastRefresh = C.frames
		C.result = nil
		if #list == 0 then
			-- the last junction Shift+clicked off: nothing selected
			C.sel = nil
			pick("remove", 0, removed, nil)
			bump()
			return true
		end
		C.multiSeq = C.multiSeq + 1
		local world = W.makeWorld()
		local t = multiTarget(world, list, C.multiSeq)
		C.sel = t
		local sum, lines = nil, {}
		if #addedNodes > 0 then sum, lines = auditPick(world, addedNodes) end
		pick(removed > 0 and "remove" or "add", added, removed, t, #addedNodes > 0 and (sum or false) or nil)
		logAudit(sum, lines)
		if t == nil then
			setResult(_("The selected junction is gone"))
		elseif dropped > 0 then
			out("SKIP", { { "src", "tool" }, { "scope", "multi" }, { "reason", "cap" }, { "max", Core.MULTI_MAX },
				{ "dropped", dropped } })
			setResult(string.format(_("Selection full: at most %d junctions"), Core.MULTI_MAX))
		end
		bump()
		return true
	end

	--- Selector onSelect (left click): selects the target under the cursor. Returns the selection.
	-- opts.shift: Shift was held at the click (C.shiftHeld, read by the caller): a street click
	-- follows the street further; with something selected, the clicked junction / road / roundabout
	-- joins the selection instead (addToSelection; a selected junction Shift+clicked leaves it).
	function C.select(entity, cursor, opts)
		-- one world for the pick and its audit (the audit reuses the classification and the walks)
		local okW, world = pcall(W.makeWorld)
		if not okW then world = nil end
		local okR, target = pcall(C.resolve, entity, cursor, { world = world, shift = opts ~= nil and opts.shift == true })
		if not okR then
			out("ERROR", { { "where", "select" }, { "err", target } })
			target = nil
		end
		if opts ~= nil and opts.shift == true and C.sel ~= nil then
			local tAdd = perf:start()
			local okA, done = pcall(addToSelection, target)
			perf:stop("multi_add", tAdd)
			if not okA then
				-- never lose the click: it acts as a plain one
				out("ERROR", { { "where", "multi" }, { "err", done } })
			elseif done then
				return C.sel
			end
		end
		C.sel = target
		C.result = nil
		C.lastRefresh = C.frames
		bump()
		-- the audit of the picked junction(s), current connections (PICK findings=, AUDIT lines after it)
		local sum, lines = nil, {}
		if target and world then
			sum, lines = auditPick(world, target.kind == "node" and { target.node } or target.junctionNodes)
		end
		if target and target.kind == "street" then
			-- a street: one line with its junctions (no CONN dump: up to 10 junctions)
			out("PICK", skippedField({ { "target", Pick.targetKey(target) }, { "mode", target.follow and "follow" or "ends" },
				{ "junctions", target.junctions }, { "segs", #target.segs },
				{ "dist", string.format("%.0f", target.dist or 0) },
				{ "stops", tostring(target.stops.b or "-") .. "," .. tostring(target.stops.a or "-") },
				{ "nodes", table.concat(target.junctionNodes, ",") }, { "badge", target.badge and target.badge.key or "-" },
				{ "findings", findingsText(sum) } }, sum))
			logAudit(sum, lines)
		elseif target then
			out("PICK", skippedField({ { "target", Pick.targetKey(target) }, { "ring", target.ringKey or "-" }, { "lanes", target.ringLanes or "-" },
				{ "arms", target.junctions or "-" }, { "node_kind", target.nodeKind or "-" }, { "conns", target.conns or "-" },
				{ "badge", target.badge and target.badge.key or "-" }, { "findings", findingsText(sum) } }, sum))
			logAudit(sum, lines)
			-- every lane connection of the picked junction(s), so an edit made with the Crossing Tool can
			-- be read back from stdout.txt (CONNS: the roads, CONN: one connection each)
			local okD, errD = pcall(function()
				local world = W.makeWorld()
				local nodes = {}
				if target.kind == "node" then nodes = { target.node }
				elseif target.ring ~= nil then nodes = target.ring.nodes or {} end
				for _, n in ipairs(nodes) do
					local d = Slip.describe(world, n, W.currentConns(n))
					out("CONNS", d.roads)
					for _, f in ipairs(d.conns) do out("CONN", f) end
				end
			end)
			if not okD then out("ERROR", { { "where", "describe" }, { "err", errD } }) end
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
		elseif s.kind == "street" then
			-- the clicked segment, else the first of the street's segments still there (a rebuilt
			-- segment gets a new id); a few component reads, one walk
			for i, sid in ipairs(s.segs or { s.seg }) do
				if i > 8 then break end
				if world.seg(sid) then
					t = streetTarget(world, sid, s.follow)
					break
				end
			end
		elseif s.kind == "multi" then
			-- bounded: at most MULTI_MAX node reads; bulldozed junctions leave the selection
			local keep, gone = {}, {}
			for _, n in ipairs(s.junctionNodes or {}) do
				local node = world.node(n)
				if node ~= nil and #node.segs > 0 then keep[#keep + 1] = n else gone[#gone + 1] = tostring(n) end
			end
			if #gone > 0 then
				out("SKIP", { { "src", "tool" }, { "scope", "multi" }, { "nodes", table.concat(gone, ",") }, { "reason", "gone" } })
			end
			t = multiTarget(world, keep, s.multiId)
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
		C.hoverWorld = nil -- the write changed connections: hover reads anew
		C.quietUntil = 0 -- from here on the pending verify keeps the NodeViewer off
		C.verifies[#C.verifies + 1] = { src = src, ring = key, kind = kind, expect = expect, due = C.frames + Core.VERIFY_DELAY }
	end

	--- Traffic lights at the handled junctions (sl_lights.lua): Apply switches them off when the
	-- setting "No lights at roundabouts and ramps" is On; Reset ("game") gives the game its AUTO choice back.
	-- Sent after the lane write answered (or right away when no lanes change).
	local function toolLightsBody(nodes, layout, key)
		local target
		if layout == "game" then
			target = Lights.AUTO
		elseif W.removeLights() then
			target = Lights.OFF
			-- SL-1: nodes in an sl_keeplights zone keep their lights (one LIGHTS ... to=kept line each that
			-- would have been switched off)
			if C.zones ~= nil and #C.zones > 0 then
				local keep = {}
				for _, n in ipairs(nodes) do
					if zoneOfNode(n) == "sl_keeplights" then
						if Lights.needs(W.lightState(n), Lights.OFF, W.lightEnum()) then
							out("LIGHTS", { { "src", "tool" }, { "node", n }, { "to", "kept" }, { "zone", "sl_keeplights" } })
						end
					else
						keep[#keep + 1] = n
					end
				end
				nodes = keep
				if #nodes == 0 then return end
			end
		else
			return
		end
		W.setLights(nodes, target, layout == "game" and "reset" or "tool", function(expect)
			C.verifies[#C.verifies + 1] = { src = "tool", ring = key, kind = "lights", target = target, expect = expect,
				due = C.frames + Core.VERIFY_DELAY }
		end)
	end
	-- never let the lights break the lane result: errors are logged
	local function toolLights(nodes, layout, key)
		local ok, e = pcall(toolLightsBody, nodes, layout, key)
		if not ok then out("ERROR", { { "where", "lights" }, { "err", e } }) end
	end

	--- The kerb turn phase change of a crossroads view (sl_lights): Reset ("game") locks the kerb
	-- turns back, Apply frees them with the setting's mode (When safe: Lights.SAFE, Always:
	-- Lights.FREE); nil otherwise (Off: phases only re-pointed). Inside an sl_lock zone (sl_zones.lua)
	-- Apply locks them back too, whatever the setting.
	local function phaseFor(view, layout)
		local kerb = Slip.kerbPairs(view)
		if kerb == nil then return nil end
		if layout == "game" or zoneOfNode(view.node) == "sl_lock" then return { mode = Lights.LOCK, kerb = kerb } end
		local mode = W.freeTurn()
		if mode ~= nil then return { mode = mode, kerb = kerb } end
		return nil
	end

	--- Light phases = Smart Lanes: the plan input of a crossroads view ({ view, world }) for Apply at a
	-- lit node; at an unlit or unknown one the reason as a string ("unlit" | "lit_unknown": logged as
	-- plan_fail=); nil for Game default, other nodes and Reset.
	-- The Light phases mode at a view's node: "sl" for the setting Smart Lanes or a node inside an
	-- sl_phases zone (sl_zones.lua; the automatic pass plans phases there too), "game" inside an sl_lock
	-- zone (game phases with the kerb turn locked) or an sl_exitfan zone (the exit fan is planned for the
	-- game's phases), else the setting.
	local function phasesAt(view)
		local mode = W.phasesMode()
		if view ~= nil then
			local ab = zoneOfNode(view.node)
			if mode ~= "sl" and (ab == "sl_phases" or ab == "sl_fan") then return "sl" end
			if ab == "sl_lock" or ab == "sl_exitfan" then return "game" end
		end
		return mode
	end
	C.phasesAt = phasesAt

	-- fan: the plan is for the full fan (Slip.plan's r.fan, an sl_fan zone): the fan plan.
	local function lightPlanFor(view, world, layout, fan)
		if layout == "game" or view == nil or view.case ~= "X" then return nil end
		-- fan lanes never go out without their plan (Slip.plan gives r.fan only at a lit node): not
		-- dependent on a second zone read agreeing with planOpts'
		if fan == true and view.lit == true then return { view = view, world = world, fan = true } end
		if phasesAt(view) ~= "sl" then return nil end
		if view.lit == true then return { view = view, world = world, fan = fan == true or nil } end
		return view.lit == false and "unlit" or "lit_unknown"
	end

	--- A lane write item; lp: lightPlanFor's result (a plan input, or a reason string).
	local function itemFor(node, conns, phase, lp, src)
		local it = { node = node, conns = conns, phase = phase, src = src }
		if type(lp) == "table" then it.lightPlan = lp elseif type(lp) == "string" then it.planFail = lp end
		return it
	end

	--- Whether a Reset gives the game's default phases back (Light phases = Smart Lanes, a crossroads).
	local function resetDefaultFor(view, layout)
		return layout == "game" and view ~= nil and view.case == "X" and phasesAt(view) == "sl"
	end

	--- The log fields of a phase change (appended to f): free_turn=n free_phases=p [kept=.. merge_free=n] /
	-- lock_turn=n lock_phases=p. stats: W.remapLights' (nil: zeros).
	local function phaseFields(f, mode, n, stats)
		local lock = mode == Lights.LOCK
		f[#f + 1] = { lock and "lock_turn" or "free_turn", n or 0 }
		f[#f + 1] = { lock and "lock_phases" or "free_phases", stats and stats.phases or 0 }
		if mode == Lights.SAFE then
			f[#f + 1] = { "kept", Lights.keptText(stats) }
			f[#f + 1] = { "merge_free", stats and stats.merged or 0 }
		end
		return f
	end

	--- A light proposal where the lanes stay; never breaks the lane result. send(onDone) sends it and
	-- returns the number sent (0: nothing). Holds the tool's buttons (C.actions: C.phaseHold) until the
	-- light proposal answered and VERIFY_DELAY frames more: a write built from reads before it lands
	-- would be refused or index stale phases.
	local function lightOnly(node, send)
		local answered, counted, gen = false, false, nil
		local ok, n = pcall(send, function()
			answered = true
			if counted and gen == C.phaseGen then
				counted = false
				C.phasePending = math.max((C.phasePending or 1) - 1, 0)
			end
			-- a street batch may send several: the buttons stay held while any is unanswered (each
			-- still bounded by its CALLBACK_TIMEOUT hold)
			if (C.phasePending or 0) == 0 then C.phaseHold = C.frames + Core.VERIFY_DELAY end
			bump()
		end)
		if not ok then
			out("ERROR", { { "where", "kerb_lights" }, { "node", node }, { "err", n } })
			return 0
		end
		if n > 0 and not answered then
			counted = true
			-- no hold in force: any earlier unanswered one timed out (never count it again)
			if C.frames >= (C.phaseHold or 0) then
				C.phasePending = 0
				C.phaseGen = (C.phaseGen or 0) + 1
			end
			gen = C.phaseGen
			C.phasePending = (C.phasePending or 0) + 1
			C.phaseHold = math.max(C.phaseHold or 0, C.frames + Core.CALLBACK_TIMEOUT)
		end
		return n
	end

	--- A phase change where the lanes stay (lightOnly): with lp (Light phases = Smart Lanes) the plan
	-- (W.planLights; a failed plan falls back to the free kerb turn), else the kerb turns (W.kerbLights).
	local function phaseOnly(node, phase, src, lp)
		if type(lp) ~= "table" then lp = nil end
		if phase == nil and lp == nil then return 0 end
		return lightOnly(node, function(onDone)
			if lp ~= nil then
				local n, why = W.planLights(node, lp, src, onDone)
				if n > 0 or phase == nil or not tostring(why):find("^plan_fail") then return n end
			end
			return (W.kerbLights(node, phase.kerb, phase.mode, src, onDone))
		end)
	end

	--- The game's default phases back where the lanes stay or after their write answered (W.defaultLights).
	local function defaultOnly(node, src)
		return lightOnly(node, function(onDone) return (W.defaultLights(node, src, onDone)) end)
	end

	--- WRITE fields of the Light phases setting for one written item (appended to f).
	local function planFields(f, it)
		-- an item with a plan or plan_fail was planned under "sl" (the setting or an sl_phases zone); an
		-- sl_lock zone's node keeps the game's phases (phasesAt)
		local ph = "sl"
		if it.planText == nil and it.planFail == nil then
			local ab = zoneOfNode(it.node)
			ph = (ab == "sl_lock" or ab == "sl_exitfan") and "game" or W.phasesMode()
		end
		f[#f + 1] = { "phases", ph }
		if it.planText ~= nil then f[#f + 1] = { "plan", it.planText }
		elseif it.planFail ~= nil then f[#f + 1] = { "plan_fail", it.planFail } end
		return f
	end

	--- Writes one slip node's connections (Apply or the Reset snapshot). Returns the result text.
	-- phase: optional kerb turn change in the same proposal (phaseFor).
	local function writeSlip(node, conns, src, done, layout, lights, phase, lp, resetDefault)
		local answered = false
		C.quietUntil = C.frames + Core.CALLBACK_TIMEOUT
		local item = itemFor(node, conns, phase, lp, src)
		local sent = W.sendConfigs("slip", node, { item }, function(success, expect, nodes)
			C.quietUntil = 0
			answered = true
			local f = { { "src", src }, { "kind", "slip" }, { "node", node }, { "nodes", nodes }, { "success", success } }
			if phase ~= nil then phaseFields(f, phase.mode, item.kerbChanged, item.kerbStats) end
			planFields(f, item)
			out("WRITE", f)
			if success then
				scheduleVerify(src, node, expect, "slip")
				setResult(done)
				-- Reset (Light phases = Smart Lanes): the game's default phases, now the lane write landed
				if resetDefault then defaultOnly(node, "reset") end
			else
				setResult(_("The game refused the change (see log)"))
			end
			if lights then toolLights({ node }, layout, node) end
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
		refreshZones()
		local s = C.sel
		if scope == "ring" then
			setResult(_("Not a roundabout: use Apply to junction"))
			return C.result
		end
		local world = W.makeWorld()
		local cur = W.currentConns(s.node)
		-- crossroads and lane drops keep their lights (Lights.keepsLights): never touched here
		local case = s.slip and s.slip.case
		local lights = not Lights.keepsLights(case)
		if layout == "game" and case == "X" then
			-- crossroads: the game-default model (Slip.defaultConns), tram connections kept
			local v = Slip.classify(world, s.node)
			local model = v.kind == "slip" and Slip.defaultConns(v) or nil
			if model == nil then
				setResult(_("Not a slip-lane junction any more; select it again"))
				return C.result
			end
			local conns = Rules.mergeTram(model, cur)
			-- the game's phases too: the kerb turns locked again with their approach (Light phases = Smart
			-- Lanes: then the game's default phases, states = {})
			local phase = phaseFor(v, "game")
			local resetDefault = resetDefaultFor(v, "game")
			out("RESET", { { "mode", "model" }, { "kind", "slip" }, { "node", s.node }, { "conns", #conns } })
			-- the game's own lanes (per movement, Slip.isDefault) count as set: never rewritten to the model
			if Rules.connsText(conns) == Rules.connsText(cur) or Slip.isDefault(v, cur) == true then
				if resetDefault then defaultOnly(s.node, "reset") else phaseOnly(s.node, phase, "reset") end
				setResult(string.format(_("%s already set"), layoutText("game")))
				return C.result
			end
			return writeSlip(s.node, conns, "reset", string.format(_("%s applied to %d junction"), layoutText("game"), 1), "game", false,
				phase, nil, resetDefault)
		end
		-- slip nodes and lane drops (no model of the game's connections there): the snapshot
		if layout == "game" then
			local snap = C.snapshots[s.node]
			if snap == nil then
				out("RESET", { { "mode", "unavailable" }, { "kind", "slip" }, { "node", s.node } })
				setResult(_("Reset not available here (no Apply yet)"))
				return C.result
			end
			if not snapFits(world, s.node, snap) then
				-- the roads changed since the Apply: the old connections name segments gone from the node
				C.snapshots[s.node] = nil
				out("RESET", { { "mode", "stale" }, { "kind", "slip" }, { "node", s.node } })
				setResult(_("Reset not available here (no Apply yet)"))
				return C.result
			end
			local now = Slip.classify(world, s.node)
			if now.kind == "slip" then lights = not Lights.keepsLights(now.case) end
			out("RESET", { { "mode", "snapshot" }, { "kind", "slip" }, { "node", s.node }, { "conns", #snap } })
			if Rules.connsText(snap) == Rules.connsText(cur) then
				if lights then toolLights({ s.node }, "game", s.node) end
				setResult(_("Already as before Apply"))
				return C.result
			end
			return writeSlip(s.node, snap, "reset", _("Lanes restored as before Apply"), "game", lights)
		end
		local r = Slip.plan(world, s.node, function() return cur end, planOpts(world, s.node))
		if r.status == "none" or r.status == "skip" then
			setResult(_("Not a slip-lane junction any more; select it again"))
			return C.result
		end
		-- the node as it is now (the selection's case may be stale: a road built or upgraded since)
		lights = not Lights.keepsLights(r.view.case)
		local phase = phaseFor(r.view, layout)
		local lp = lightPlanFor(r.view, world, layout, r.fan)
		local function audit()
			-- a fan (sl_fan zone) crosses by design: not audited
			if r.fan then return end
			logAudit(auditItems(world, { { node = s.node, conns = r.conns, view = r.view } }, { { "src", "tool" } },
				{ [s.node] = r.conns }))
		end
		if r.status == "same" then
			if lights then toolLights({ s.node }, layout, s.node) end
			phaseOnly(s.node, phase, "tool", lp)
			setResult(_("Smart lanes already set"))
			audit()
			return C.result
		end
		if C.snapshots[s.node] == nil then C.snapshots[s.node] = cur end
		local fields = { { "src", "tool" } }
		for _, f in ipairs(Slip.logFields(r)) do fields[#fields + 1] = f end
		out("APPLY", fields)
		local done = lights and _("Smart lanes applied to the slip junction")
			or string.format(_("%s applied to %d junction"), layoutText("turbo"), 1)
		local text = writeSlip(s.node, r.conns, "tool", done, layout, lights, phase, lp)
		-- after the proposal was sent: the audit never delays the write
		audit()
		return text
	end

	---------------------------------------------------------------------------
	-- Streets and multi selections: Apply / Reset on every selected junction, in batches

	--- Log fields naming a job's selection: scope=street street=<seg> | scope=multi.
	local function scopeFields(job)
		if job.scope == "multi" then return { { "scope", "multi" } } end
		return { { "scope", "street" }, { "street", job.key } }
	end

	--- The field lists one after the other (log lines).
	local function join(...)
		local res = {}
		for _, list in ipairs({ ... }) do
			for _, f in ipairs(list) do res[#res + 1] = f end
		end
		return res
	end

	--- Plans one street node in `world` (read in this frame). Returns "write", conns, lights, phase, lp,
	-- resetDefault | "same", nil, lights, phase, lp, resetDefault | "skip", reason. lp: the Light phases plan
	-- input (lightPlanFor), resetDefault: Reset gives the game's default phases back (resetDefaultFor). lights: the node's lights follow the write (Lights
	-- rules, as C.applySlip); phase: the crossroads' kerb turn change (phaseFor) or nil. Never plans from the selection: the node is classified again here, and a node
	-- that is gone, has no config, is on a ring now or is no longer handled is skipped.
	-- notRing: the caller found no ring through n in this world (multi jobs plan ring junctions
	-- themselves, planRingGroup).
	-- audits: list the turbo plan's junction (apply or same) is added to for the batch's audit, or nil.
	local function planStreetNode(world, n, layout, job, notRing, audits)
		local tag = scopeFields(job)
		local function skip(reason)
			out("SKIP", join({ { "src", "tool" } }, tag, { { "node", n }, { "reason", reason } }))
			return "skip", reason
		end
		if world.node(n) == nil then return skip("gone") end
		if W.getComp(n, CT().BASE_NODE_CONFIG) == nil then return skip("no_config") end
		if not notRing and Ring.ringThrough(world, n) ~= nil then return skip("ring") end
		local cur = W.currentConns(n)
		local conns, lights, phase, lp, resetDefault
		if layout == "game" then
			local v = Slip.classify(world, n)
			if v.kind ~= "slip" then return skip(tostring(v.reason or v.kind)) end
			local model = Slip.defaultConns(v)
			if model ~= nil then
				-- crossroads: the game-default model, tram kept; lights stay (Lights.keepsLights), the
				-- kerb turns locked again in the phases
				conns, lights, phase = Rules.mergeTram(model, cur), false, phaseFor(v, "game")
				resetDefault = resetDefaultFor(v, "game")
				-- the game's own lanes (per movement, Slip.isDefault): kept, only the phases go back
				if Slip.isDefault(v, cur) == true then conns = cur end
				out("RESET", join({ { "mode", "model" } }, tag, { { "node", n }, { "conns", #conns } }))
			else
				local snap = C.snapshots[n]
				if snap == nil then
					out("RESET", join({ { "mode", "unavailable" } }, tag, { { "node", n } }))
					return "skip", "unavailable"
				end
				if not snapFits(world, n, snap) then
					C.snapshots[n] = nil
					out("RESET", join({ { "mode", "stale" } }, tag, { { "node", n } }))
					return "skip", "stale"
				end
				conns, lights = snap, not Lights.keepsLights(v.case)
				out("RESET", join({ { "mode", "snapshot" } }, tag, { { "node", n }, { "conns", #snap } }))
			end
		else
			local r = Slip.plan(world, n, function() return cur end, planOpts(world, n))
			if r.status ~= "apply" and r.status ~= "same" then return skip(tostring(r.reason or r.status)) end
			if audits ~= nil and not r.fan then audits[#audits + 1] = { node = n, conns = r.conns, view = r.view } end
			lights = Lights.slipNode(r)
			phase = phaseFor(r.view, layout)
			lp = lightPlanFor(r.view, world, layout, r.fan)
			if r.status == "same" then return "same", nil, lights, phase, lp end
			conns = r.conns
			if C.snapshots[n] == nil then C.snapshots[n] = cur end
			out("APPLY", join({ { "src", "tool" } }, tag, Slip.logFields(r)))
		end
		if Rules.connsText(conns) == Rules.connsText(cur) then return "same", nil, lights, phase, lp, resetDefault end
		-- crash rule 3: every connection names a segment attached now, lanes inside it
		if not snapFits(world, n, conns) then return skip("conns") end
		return "write", conns, lights, phase, lp, resetDefault
	end

	--- The street job's result text, once every batch answered (or timed out).
	local function finishJob(job)
		if job.done then return end
		job.done = true
		if C.job == job then C.job = nil end
		-- every batch answered or timed out (a pending re-read keeps the NodeViewer off by itself)
		C.quietUntil = 0
		C.lastRefresh = -Core.REFRESH_FRAMES -- re-read the selection now
		-- the tool closed (C.flush) or another target was selected since the click: the log has the
		-- outcome, the status chip belongs to the new selection (it can only show busyJob's text)
		if job.cancelled or C.sel == nil or selIdent(C.sel) ~= job.ident then
			if C.result ~= nil then setResult(nil) end
			return
		end
		local name = layoutText(job.layout)
		if job.written > 0 then
			setResult(string.format(job.written == 1 and _("%s applied to %d junction") or _("%s applied to %d junctions"),
				name, job.written))
		elseif job.refused > 0 then
			setResult(_("The game refused the change (see log)"))
		elseif job.failed > 0 then
			setResult(_("Could not build the change (see log)"))
		elseif job.same > 0 then
			setResult(string.format(_("%s already set"), name))
		elseif job.layout == "game" then
			setResult(_("Reset not available here (no Apply yet)"))
		else
			setResult(_("Left alone: this junction type is not handled yet"))
		end
	end

	local function maybeFinish(job)
		if job.next > #job.batches and job.pending <= 0 then finishJob(job) end
	end

	--- Sends the job's next batch: a fresh world and fresh connections read now (crash rule 3), one
	-- proposal through W.sendConfigs; the batch's lights after its write answered.
	--- Ring junctions of a multi job's batch, one ring at a time: Rules.planRing seeded with the
	-- batch's junctions of that ring (the ring node rules of Apply to junction; Reset: the engine
	-- default model), in the batch's fresh world. Adds to items / lightNodes and the job's counts.
	local function planRingGroup(world, ring, seeds, job, items, lightNodes, audits)
		local tag = scopeFields(job)
		local function skip(n, reason)
			out("SKIP", join({ { "src", "tool" } }, tag, { { "ring", ring.key }, { "node", n }, { "reason", reason } }))
			job.skipped = job.skipped + 1
		end
		local plan = Rules.planRing(world, ring, seeds, job.layout == "game" and "engine" or "turbo", W.currentConns)
		local planned = {}
		for _, r in ipairs(plan.nodes or {}) do
			if seeds[r.node] then
				planned[r.node] = true
				if audits ~= nil and job.layout ~= "game" and (r.status == "apply" or r.status == "same") and r.conns ~= nil
					and r.view and r.view.kind == "arm" then
					audits[#audits + 1] = { node = r.node, conns = r.conns, view = r.view, ring = ring }
				end
				if W.getComp(r.node, CT().BASE_NODE_CONFIG) == nil then
					skip(r.node, "no_config")
				elseif r.status == "apply" and r.conns ~= nil then
					-- crash rule 3: every connection names a segment attached now, lanes inside it
					if snapFits(world, r.node, r.conns) then
						if job.layout == "game" then
							out("RESET", join({ { "mode", "model" } }, tag, { { "ring", ring.key }, { "node", r.node },
								{ "conns", #r.conns } }))
						else
							local v = r.view
							out("APPLY", Rules.withEntry(join({ { "src", "tool" } }, tag, { { "layout", job.layout }, { "ring", ring.key },
								{ "node", r.node }, { "lanes", ring.lanes }, { "dir", ring.side == 1 and "ccw" or "cw" },
								{ "exits", #(v.x or {}) }, { "entries", #(v.e or {}) }, { "turbo", plan.turbo },
								{ "turbo_reason", plan.turboReason or "-" }, { "before", r.before }, { "after", r.after } }), r))
						end
						items[#items + 1] = { node = r.node, conns = r.conns }
						if r.view and r.view.kind == "arm" then lightNodes[#lightNodes + 1] = r.node end
					else
						skip(r.node, "conns")
					end
				elseif r.status == "same" then
					job.same = job.same + 1
					if r.view and r.view.kind == "arm" then lightNodes[#lightNodes + 1] = r.node end
				else
					skip(r.node, tostring(r.reason or r.status))
				end
			end
		end
		-- a seed that is a plain ring node now (its arm removed): not a junction any more
		for n in pairs(seeds) do
			if not planned[n] then skip(n, "plain") end
		end
	end

	local function sendBatch(job)
		local i = job.next
		job.next = i + 1
		job.lastSend = C.frames
		local world = W.makeWorld()
		local items, lightNodes = {}, {}
		local rings, ringOrder = {}, {} -- multi jobs: ring key -> { ring, seeds }
		local audits = job.layout ~= "game" and {} or nil -- the batch's planned junctions (sl_audit.lua)
		local function auditBatch()
			if audits == nil or #audits == 0 then return end
			local planned = {}
			for _, it in ipairs(audits) do planned[it.node] = it.conns end
			logAudit(auditItems(world, audits, join({ { "src", "tool" } }, scopeFields(job)), planned))
		end
		for _, n in ipairs(job.batches[i]) do
			local ring, ringErr = nil, nil
			if job.scope == "multi" and world.node(n) ~= nil then
				local okR, rr = pcall(Ring.ringThrough, world, n)
				if okR then ring = rr else ringErr = rr end
			end
			if ringErr ~= nil then
				-- unknown whether n is on a ring: never planned as a street node (review 5b)
				out("ERROR", { { "where", "multi_ring" }, { "node", n }, { "err", ringErr } })
				job.skipped = job.skipped + 1
			elseif ring ~= nil then
				local grp = rings[ring.key]
				if grp == nil then
					grp = { ring = ring, seeds = {} }
					rings[ring.key] = grp
					ringOrder[#ringOrder + 1] = ring.key
				end
				grp.seeds[n] = true
			else
				local okP, what, conns, lights, phase, lp, resetDefault = pcall(planStreetNode, world, n, job.layout, job,
					job.scope == "multi", audits)
				if not okP then
					out("ERROR", { { "where", "street_plan" }, { "node", n }, { "err", what } })
					job.skipped = job.skipped + 1
				elseif what == "write" then
					local it = itemFor(n, conns, phase, lp, job.layout == "game" and "reset" or "tool")
					it.resetDefault = resetDefault
					items[#items + 1] = it
					if lights then lightNodes[#lightNodes + 1] = n end
				elseif what == "same" then
					job.same = job.same + 1
					if lights then lightNodes[#lightNodes + 1] = n end
					-- lanes already right: the kerb turns through a phases-only light proposal (this node is
					-- not in the batch's lane proposal)
					if resetDefault then
						defaultOnly(n, "reset")
					else
						phaseOnly(n, phase, job.layout == "game" and "reset" or "tool", lp)
					end
				else
					job.skipped = job.skipped + 1
				end
			end
		end
		for _, k in ipairs(ringOrder) do
			local grp = rings[k]
			local okG, eG = pcall(planRingGroup, world, grp.ring, grp.seeds, job, items, lightNodes, audits)
			if not okG then
				out("ERROR", { { "where", "multi_ring_plan" }, { "ring", k }, { "err", eG } })
				for _ in pairs(grp.seeds) do job.skipped = job.skipped + 1 end
			end
		end
		local src = job.layout == "game" and "reset" or "tool"
		if #items == 0 then
			toolLights(lightNodes, job.layout, job.key)
			auditBatch()
			return maybeFinish(job)
		end
		job.pending = job.pending + 1
		C.quietUntil = C.frames + Core.CALLBACK_TIMEOUT
		local batch = tostring(i) .. "/" .. tostring(#job.batches)
		local keyName, keyVal = "street", job.key
		if job.scope == "multi" then keyName, keyVal = "scope", "multi" end
		local sent = W.sendConfigs(keyName, keyVal, items, function(success, expect, nodes)
			job.pending = job.pending - 1
			-- kerb connections changed in the batch's phases (it.kerbChanged: set when the proposal was built)
			local kerbN, stats, mode = 0, { phases = 0, merge = 0, cross = 0, ped = 0, merged = 0 }, nil
			for _, it in ipairs(items) do
				kerbN = kerbN + (it.kerbChanged or 0)
				Lights.addStats(stats, it.kerbStats)
				if it.phase ~= nil then mode = it.phase.mode end
			end
			if mode == nil then mode = job.layout == "game" and Lights.LOCK or Lights.FREE end
			local pf = { { "phases", W.phasesMode() } }
			local planN, failN = 0, 0
			for _, it in ipairs(items) do
				if it.planText ~= nil then planN = planN + 1 elseif it.planFail ~= nil then failN = failN + 1 end
			end
			if planN + failN > 0 then pf[1][2] = "sl" end -- planned in an sl_phases zone
			if pf[1][2] == "sl" then
				pf[2] = { "sl_plans", planN }
				pf[3] = { "plan_fails", failN }
			end
			out("WRITE", join({ { "src", src } }, scopeFields(job), { { "batch", batch }, { "nodes", nodes },
				{ "success", success } }, phaseFields({}, mode, kerbN, stats), pf))
			if success then
				-- Reset (Light phases = Smart Lanes): the game's default phases, now the lane write landed
				for _, it in ipairs(items) do
					if it.resetDefault and expect[it.node] ~= nil then defaultOnly(it.node, "reset") end
				end
				local k = 0
				for _ in pairs(expect) do k = k + 1 end
				job.written = job.written + k
				scheduleVerify(src, job.key, expect, job.scope)
			else
				job.refused = job.refused + 1
			end
			toolLights(lightNodes, job.layout, job.key)
			maybeFinish(job)
		end)
		if sent == 0 then
			-- nothing could be built (logged as SKIP by sendConfigs); onDone is not called
			job.pending = job.pending - 1
			job.failed = job.failed + #items
			maybeFinish(job)
		end
		-- after the proposal was sent: the audit never delays the write
		auditBatch()
	end

	--- While a street job runs, no other write starts (its nodes may be the selection's): the
	-- "Applying..." text. The buttons are off then too (C.actions); this guards direct calls.
	local function busyJob()
		setResult(string.format(_("Applying %s..."), layoutText(C.job.layout)))
		return C.result
	end

	--- Apply (layout "turbo") or Reset (layout "game") on the selected street or multi selection:
	-- every junction, in batches of at most BATCH_NODES nodes, the first now, then one per frame
	-- (C.step). The job keeps its own node lists: a Shift+click meanwhile changes only the selection.
	function C.applyStreet(layout)
		refreshZones()
		local s = C.sel
		if C.job ~= nil then return busyJob() end
		local nodes = s.junctionNodes or {}
		local batches = {}
		for i = 1, #nodes, Core.BATCH_NODES do
			local b = {}
			for j = i, math.min(i + Core.BATCH_NODES - 1, #nodes) do b[#b + 1] = nodes[j] end
			batches[#batches + 1] = b
		end
		local multi = s.kind == "multi"
		local job = { scope = multi and "multi" or "street", key = multi and "multi" or s.seg, ident = selIdent(s),
			layout = layout, batches = batches, next = 1, pending = 0, written = 0, same = 0,
			skipped = 0, refused = 0, failed = 0, lastSend = C.frames }
		local op = layout == "game" and "reset" or "apply"
		if multi then
			out("MULTI", { { "op", op }, { "junctions", #nodes }, { "batches", #batches } })
		else
			out("STREET", { { "op", op }, { "street", s.seg }, { "mode", s.follow and "follow" or "ends" },
				{ "junctions", #nodes }, { "batches", #batches } })
		end
		C.job = job
		C.result = nil
		if #batches == 0 then
			finishJob(job)
		else
			local tBatch = perf:start()
			local okB, eB = pcall(sendBatch, job)
			perf:stop("batch", tBatch)
			if not okB then
				out("ERROR", { { "where", "street_batch" }, { "err", eB } })
				job.next, job.pending = #job.batches + 1, 0
				finishJob(job)
			end
		end
		if not job.done then setResult(string.format(_("Applying %s..."), layoutText(layout))) end
		return C.result
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
		refreshZones()
		local s = C.sel
		if s == nil then
			setResult(_("Select a junction or a roundabout first"))
			return C.result
		end
		if C.job ~= nil then return busyJob() end
		if s.kind == "street" or s.kind == "multi" then
			if scope == "ring" then
				setResult(_("Not a roundabout: use Apply to junction"))
				return C.result
			end
			return C.applyStreet(layout == "game" and "game" or "turbo")
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
				out("APPLY", Rules.withEntry({ { "src", "tool" }, { "layout", layout }, { "ring", ring.key }, { "node", r.node }, { "lanes", ring.lanes },
					{ "dir", ring.side == 1 and "ccw" or "cw" }, { "exits", #v.x }, { "entries", #v.e },
					{ "turbo", plan.turbo }, { "turbo_reason", plan.turboReason or "-" }, { "before", r.before }, { "after", r.after } }, r))
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
		local lightNodes = Lights.ringNodes(plan)
		-- the audit of the planned ring junctions (apply or same), after the proposal was sent
		local function auditRing()
			if layout == "game" then return end
			local list, planned = {}, {}
			for _, r in ipairs(plan.nodes) do
				if (r.status == "apply" or r.status == "same") and r.conns ~= nil and r.view and r.view.kind == "arm" then
					list[#list + 1] = { node = r.node, conns = r.conns, view = r.view, ring = ring }
					planned[r.node] = r.conns
				end
			end
			logAudit(auditItems(world, list, { { "src", "tool" }, { "ring", ring.key } }, planned))
		end
		if #items == 0 then
			toolLights(lightNodes, layout, ring.key)
			auditRing()
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
			toolLights(lightNodes, layout, key)
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
		auditRing()
		return C.result
	end

	--- Reset to the game default = Apply with the Game default layout (a full config write).
	-- Never a remove-only proposal: in game (2026-10-08) nodeConfigsToRemove without an add deleted
	-- the node's BASE_NODE_CONFIG (0 connections, no config to edit afterwards) and the simulation
	-- crashed seconds later in Engine.cpp:693 PostRemoveComponent (findings.md).
	function C.reset(scope)
		local s = C.sel
		if C.job ~= nil then return busyJob() end
		if s ~= nil and s.kind == "node" and s.ring == nil and s.slip ~= nil then return C.applySlip("node", "game") end
		if s ~= nil and (s.kind == "street" or s.kind == "multi") then return C.applyStreet("game") end
		out("RESET", { { "mode", "model" }, { "scope", scope } })
		return C.apply(scope, "game")
	end

	--- Whether the NodeViewer is held off: a write waits for its callback or re-read.
	local function nvHeld()
		return next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0)
	end

	--- One GUI frame: due reset judgements, due re-reads, periodic refresh of the selection.
	function C.step()
		C.frames = C.frames + 1
		local i = 1
		while i <= #C.verifies do
			local v = C.verifies[i]
			if C.frames >= v.due then
				table.remove(C.verifies, i)
				local ok, same, total, gone
				if v.kind == "lights" then
					ok, same, total, gone = pcall(W.verifyLights, v.expect, v.target)
				else
					ok, same, total = pcall(W.verify, v.expect)
				end
				if ok then
					if v.kind == "lights" then
						out("VERIFY", { { "src", v.src }, { "kind", "lights" }, { "ring", v.ring }, { "to", v.target }, { "done", same }, { "nodes", total }, { "gone", gone } })
					elseif v.kind == "slip" then
						out("VERIFY", { { "src", v.src }, { "kind", "slip" }, { "node", v.ring }, { "same", same }, { "nodes", total } })
					elseif v.kind == "street" then
						out("VERIFY", { { "src", v.src }, { "scope", "street" }, { "street", v.ring }, { "same", same }, { "nodes", total } })
					elseif v.kind == "multi" then
						out("VERIFY", { { "src", v.src }, { "scope", "multi" }, { "same", same }, { "nodes", total } })
					else
						out("VERIFY", { { "src", v.src }, { "ring", v.ring }, { "same", same }, { "nodes", total } })
					end
					C.lastRefresh = -Core.REFRESH_FRAMES -- re-read the selection now
					C.hoverCache.at = -Core.REFRESH_FRAMES
					C.hoverWorld = nil
				else
					out("ERROR", { { "where", "verify" }, { "err", same } })
				end
			else
				i = i + 1
			end
		end
		-- a street job: its next batch (one proposal per frame); a batch without an answer for
		-- CALLBACK_TIMEOUT frames is judged anyway
		local job = C.job
		if job ~= nil then
			if job.next <= #job.batches then
				local tBatch = perf:start()
				local okB, eB = pcall(sendBatch, job)
				perf:stop("batch", tBatch)
				if not okB then
					out("ERROR", { { "where", "street_batch" }, { "err", eB } })
					job.next, job.pending = #job.batches + 1, 0
					finishJob(job)
				end
			elseif job.pending > 0 and C.frames - job.lastSend > Core.CALLBACK_TIMEOUT then
				out("ERROR", { { "where", "street_timeout" }, { "street", job.key }, { "pending", job.pending } })
				job.pending = 0
				finishJob(job)
			end
		end
		-- the Selector stops calling onHover off street objects: drop a stale hover
		if C.hover ~= nil and C.frames - C.hoverFrame > Core.HOVER_STALE_FRAMES then
			C.hover = nil
			bump()
		end
		if C.sel ~= nil and C.frames - C.lastRefresh >= Core.REFRESH_FRAMES then
			C.lastRefresh = C.frames
			local tRefresh = perf:start()
			local ok, e = pcall(C.refresh)
			perf:stop("refresh", tRefresh)
			if not ok then out("ERROR", { { "where", "refresh" }, { "err", e } }) end
		end
		-- the last render got an empty lane view (a write was pending) and the write is judged now:
		-- render again, with a spec read from now on. The re-read after the write often finds the
		-- same signature as the refresh right after the callback, so nothing else would re-render
		-- (in game 2026-10-11: no lane view for 20+ s after a multi Apply).
		if C.nvHeld and not nvHeld() then
			C.nvHeld = false
			C.nvCache = nil
			bump()
		end
	end

	--- The tool closes: forget the selection and pending re-reads (writes already sent still land).
	function C.flush()
		if C.job ~= nil then C.job.cancelled = true end
		if C.job ~= nil and C.job.next <= #C.job.batches then
			out("SKIP", join({ { "src", "tool" } }, scopeFields(C.job),
				{ { "batches", #C.job.batches - C.job.next + 1 }, { "reason", "tool_closed" } }))
		end
		C.job = nil
		C.verifies = {}
		C.hover = nil
		C.hoverWorld = nil
		C.sel = nil
		C.result = nil
		C.nvCache = nil
		C.nvHeld = false
		bump()
	end

	--- Nodes whose connections the overlay shows: the selected junction, or every junction of the
	-- selected ring, street or multi selection (at most Core.VIEW_MAX). The game's NodeViewer takes
	-- several nodes in one nodeConfig map (builtin.d.tl NodeViewerParam; a whole ring is drawn so
	-- since Phase 2), so one NodeViewer shows them all.
	function C.viewNodes()
		local s = C.sel
		if s == nil then return {} end
		if s.kind == "node" then return { s.node } end
		local list = {}
		for i, n in ipairs(s.junctionNodes or {}) do
			if i > Core.VIEW_MAX then break end
			list[i] = n
		end
		return list
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
	-- Each node's entry comes from that node's connections and network read together, here; a node
	-- that is gone (no config, no network) is left out. A street or multi selection (up to
	-- VIEW_MAX nodes, two reads each) keeps its spec while the selection's signature (its re-read
	-- connections, C.refresh) is unchanged and it was built after the last refresh (so at most
	-- REFRESH_FRAMES old), so a re-render for a hover change does not read every node again.
	function C.nodeViewerSpec()
		local spec = {}
		if nvHeld() then
			-- remembered: C.step re-renders once the write is judged (C.nvHeld)
			C.nvCache = nil
			C.nvHeld = true
			return spec
		end
		local s = C.sel
		local many = s ~= nil and (s.kind == "street" or s.kind == "multi")
		local nc = C.nvCache
		-- never older than the selection's last re-read (C.refresh): a node whose network or config
		-- changed without changing the signature (its network edge count) is checked again then
		if many and nc ~= nil and nc.ident == selIdent(s) and nc.sig == s.sig and nc.at >= C.lastRefresh
			and C.frames - nc.at < Core.REFRESH_FRAMES then
			return nc.spec
		end
		local tSpec = perf:start()
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
		C.nvCache = many and { ident = selIdent(s), sig = s.sig, at = C.frames, spec = spec } or nil
		perf:stop("nv_spec", tSpec)
		return spec
	end

	local function segsOf(world, t)
		if t == nil then return {} end
		if t.kind == "ring" then return t.ring.segs end
		if t.kind == "street" then return t.segs or {} end
		if t.kind ~= "node" then return {} end -- a multi selection: markers only
		local node = world.node(t.node)
		return node and node.segs or {}
	end

	--- Entities to highlight (street segments of the hovered and the selected target) and circle
	-- markers { x, y, z, r, kind = "sel" | "ring" | "hover" }. Targets are up to REFRESH_FRAMES old
	-- (a street reused while hovering along it): only segments that still exist are passed on.
	function C.highlight()
		local tHi = perf:start()
		local ents, seen = {}, {}
		local function add(list)
			for _, e in ipairs(list) do
				if not seen[e] then
					seen[e] = true
					if W.getComp(e, CT().BASE_EDGE) ~= nil then ents[#ents + 1] = e end
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
		if C.sel and C.sel.kind == "multi" then
			-- the positions read with the selection (C.refresh): no node reads per render
			for _, n in ipairs(C.sel.junctionNodes or {}) do
				local p = C.sel.pos and C.sel.pos[n]
				if p then markers[#markers + 1] = { x = p.x, y = p.y, z = p.z, r = 4, kind = "sel" } end
			end
		elseif C.sel then
			for _, n in ipairs(C.sel.junctionNodes or {}) do
				if n ~= C.sel.node then mark(n, 2.5, "ring") end
			end
			if C.sel.kind == "node" then mark(C.sel.node, 4, "sel") end
		end
		if C.hover and C.hover.kind == "node" and (C.sel == nil or C.hover.node ~= C.sel.node) then
			mark(C.hover.node, 4, "hover")
		end
		perf:stop("highlight", tHi)
		return ents, markers
	end

	--- Toolbar buttons that may be clicked now: { applyNode, applyRing, reset } (booleans). All off
	-- without a selection and while a write waits for its callback or re-read (the selection is stale
	-- until then). Cheap: the construction menu asks every step (checkEnabledFn).
	function C.actions()
		local s = C.sel
		local busy = C.job ~= nil or next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0) or C.frames < (C.phaseHold or 0)
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
