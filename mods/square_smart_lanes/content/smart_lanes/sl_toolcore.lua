-- Smart Lanes tool (Phase 2 step 1): the controller behind the road tool's UI (sl_tool.script.lua).
-- Picking, the selection, Apply (layouts from sl_rules), Reset (writes the game default model) and
-- the frame-timed re-reads. No React here, so tests/square_smart_lanes/test_tool.lua drives it with
-- a fake api. Runs on the GUI thread (the construction menu's Lua state).
--
-- Log lines ([SQRL], stdout.txt):
--   PROBE hover entity=.. kind=node|edge promoted=.. d=.. r=.. target=..  (rate-limited, on change)
--   PICK target=.. ring=.. lanes=.. arms=.. conns=.. badge=smart|default|kept|custom|partial|na findings=.. [skipped=no_config:n]
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
--   free_phases=<(connection, phase) unlocks> [kept=cross:n,ped:n merge_free=n] shared_held=n: kerb turns
--   not freed because their entry lane also carries another movement, Lights.sharedKerb); Reset locks them back
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
--   Toolbar (rev 8, PLAN.md "Toolbar: rows, hidden when nothing to do"; C.buttons): row 1 Smart lanes | Reset, each
--   shown only when it would change something, row 2 Smart lights | Re-time at a junction with a standing light; a
--   button is grayed with its reason (C.buttonTip, the button's tooltip) only for a passing state (a change landing,
--   the most recordings or Re-time runs at once elsewhere); Smart lights also when the phases are its plan already, and hidden where no
--   axis plan can be made (PLAN.md "No classic fallback": the detail line says why, Pick.lightsText).
--   Record traffic (PLAN.md "Traffic rate at a junction", sl_record.lua): a last row at any selected real junction
--   (3 roads or more) or roundabout (C.record): counts the vehicles passing (a roundabout: entering) for up to 20 game min with a second
--   Re-time sampler (C.recorder), 30 s buckets; the status shows the rates (C.recordLines); the saved last result per
--   junction (trec). Logs TRAFFIC op=start|checkpoint|bg|done|refuse.
--   Smart lights (rev 8 "Lights only", PLAN.md "Lights only"): a toolbar button at a selected crossroads / T-junction with a
--   standing traffic light (C.lightsOnly): new Smart Lanes phases for the junction's lanes as they are (the
--   player's Crossing Tool edits included), no lane written: W.planLights with the plan input of the current
--   connections (whatever "Light phases" says). Hidden when no valid plan exists (the game's phases stay), grayed when
--   it equals the phases (C.lightsStatus, cached per node by its connections, crosswalks and phases). Logs PHASES src=tool
--   action=lights_only node= phases=sl pattern= plan=<PP.planText> | plan_fail=<reason> | same=1, and the LIGHTS
--   src=tool to=sl_phases ... action=lights_only line of the proposal. Held by phaseHold like every phases-only
--   proposal (never sent while a write or light proposal of the tool is pending).
--   Reset at a lit crossroads / T-junction also gives the game's default phases back (W.defaultLights, states = {})
--   when they are not the default (C.phasesDefault: the measured 6-phase shape with fractional greens; Lights only,
--   Re-time and the Crossing window write whole seconds), and is enabled for that alone.
--   Re-time (rev 8, PLAN.md "Re-time", RETIME_PLAN.md): at a junction with a standing light and phases, C.retime
--   measures its traffic for 180 game s (sl_retimer.lua, within a frame budget) and then writes a new cycle and
--   phase durations (sl_retime.lua R.plan, Webster's cycle; W.retimeLights: lockedLanes and canSkip as read). The
--   run goes on whatever is selected and with the tool closed (C.bgStep from the background plugin sl_bg.script.lua);
--   the button at that junction cancels it; a lane / phase change or the light gone stops it. Up to
--   Core.RETIME_MAX_RUNNING runs at once (rev 9, PLAN.md "Several Re-time runs at once"), each at its own junction, in
--   one shared sampler run with one per-frame budget; the next start is grayed with its reason. Elsewhere the status
--   says how many run (C.retimeCountLine). At a selected junction the status shows its run's progress or its
--   last-measured line (C.retimeLines, C.lastLine: the saved record of either mode, sl_auto.lua rlast; the manual
--   run sends its own with op=last src=tool). Logs RETIME
--   op=start|cancel|refuse|bg|measured|plan|write|probe|reroute (PLAN.md "Logging") and the proposal's LIGHTS
--   src=tool to=retime ... action=retime.
--   Keep timing adjusted (rev 8 step B, RETIME_PLAN.md "Step B", PLAN.md "Keep timing adjusted"): a Yes / No toggle in a
--   third row (twin params, shown with the light row) enrolls / unenrolls the selected lit junction (C.setAuto: SmartLanes.auto add / remove,
--   sl_auto.lua; the click's value is the intent). The tool mirrors the saved list (C.auto, re-read every
--   AUTO_MIRROR_FRAMES when aseq changed); C.autoChecked is the toggle's displayed state. Re-time at an enrolled junction
--   runs the manual measurement as anywhere (step B v4: the automatic mode only counts queues now and then). The
--   status's first Re-time line at an enrolled junction is "Keep timing adjusted: ..." (C.autoLine: counts so far,
--   next check). C.autoBusy(node) tells the runtime (sl_autoretime.lua) when a tool proposal is pending or the manual
--   Re-time is there (its writes wait). All lights (sl_allmode.lua): selecting a lit junction not enrolled yet enrolls
--   it at once where the rules allow it (C.allSelect: add src=select, the mirror at once, so the toggle shows Yes);
--   otherwise the status says why it stays No (C.allWhy: turned off / timed by hand / the cap).
--   Kept nodes (sl_kept.lua, PLAN.md "Reset sticks", rev 7): Reset (any selection) marks the junctions it covers
--   as kept (a ring: every ring node), Apply clears the marks of the junctions it covers (sent only for nodes that
--   are kept), through the SmartLanes.kept event (the game script logs KEPT). The automatic pass leaves kept
--   nodes alone. The badge of a target whose handled junctions all have the game's lanes and are kept: key
--   "kept", "Game default (locked)". The tool mirrors the saved list (re-read when kseq changed, at most once
--   per frame) and applies its own events to the mirror at once.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Pick = ug_require "square_smart_lanes::/smart_lanes/sl_pick.lua"
local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Lights = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local Street = ug_require "square_smart_lanes::/smart_lanes/sl_street.lua"
local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"
local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
local MidView = ug_require "square_smart_lanes::/smart_lanes/sl_midview.lua"
local Split = ug_require "square_smart_lanes::/smart_lanes/sl_split.lua"
local Kept = ug_require "square_smart_lanes::/smart_lanes/sl_kept.lua"
local Retime = ug_require "square_smart_lanes::/smart_lanes/sl_retime.lua"
local Retimer = ug_require "square_smart_lanes::/smart_lanes/sl_retimer.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local Rec = ug_require "square_smart_lanes::/smart_lanes/sl_record.lua"

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
Core.RETIME_WAIT_FRAMES = 600 -- frames a finished Re-time waits for a pending proposal of the tool before it gives up
Core.RETIME_LINES_MAX = 400   -- RETIME lines per session (each run logs ~12)
Core.RETIME_BASE_BEFORE = 35  -- game s before the window's end the re-route baseline snapshot is taken
Core.RETIME_MAX_RUNNING = 5   -- Re-time runs at once (each at its own junction; one shared sampler run)
Core.AUTO_MIRROR_FRAMES = 30  -- frames between reads of the saved "Keep timing adjusted" list (its aseq)

-- Display name of a layout (Rules.LAYOUT_NAMES stays English: the game script and the log use it).
-- Translated when called (the tool's GUI Lua state).
local function layoutText(layout)
	local names = { matched = _("Matched lanes"), turbo = _("Smart lanes"), game = _("Game default") }
	-- a ring layout variant (bench zones only) shows as Smart lanes: no new text
	if names[layout] == nil and Rules.RING_VARIANT_SET[layout] then return names.turbo end
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
		lightsCache = {},   -- crossroads -> { key, at, res } (C.lightsStatus: the "Lights only" mode)
		lightsCacheCount = 0,
		nodeKind = {},      -- node -> { key, at, slip, ring } (C.nodeKindOf; street walks)
		nodeKindCount = 0,
		hoverWorld = nil,   -- { world, at }: the world hover resolves share (display only, C.onHover)
		job = nil,          -- street / multi Apply / Reset in progress (batches sent one per frame)
		multiSeq = 0,       -- id of the latest multi selection (a Shift+click makes a new one)
		nvCache = nil,      -- street / multi NodeViewer spec { ident, sig, at, spec } (C.nodeViewerSpec)
		nvHeld = false,     -- an empty spec was handed out while a write was pending (C.step re-renders)
		badgeStats = { hits = 0, misses = 0 },
		rts = {},           -- the Re-time runs by node (C.retime): { node, phase = "measuring" | "waiting", tg, ... }
		rtList = {},        -- the same in start order (at most Core.RETIME_MAX_RUNNING)
		rtCount = 0,
		rtLines = 0,        -- RETIME lines logged this session (Core.RETIME_LINES_MAX)
		toolSteps = 0,      -- C.step calls (C.bgStep: is the tool stepping?)
	}
	clock = clock or os.clock
	-- the Re-time measuring runtime (sl_retimer.lua); C.retimeNow: game seconds (tests set it)
	C.retimer = Retimer.new(api, clock, function() if C.retimeNow then return C.retimeNow() end return nil end,
		{ perf = perf, perfName = "retime_gather" })

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
	--- The ring layout variant (Rules.RING_VARIANTS) of the zone a ring lies in (its first node in such a zone), else
	-- nil: the tool's Apply and badge then use that variant instead of "turbo" (Reset stays the game's model).
	local function ringVariantOf(ring)
		if C.zones == nil or #C.zones == 0 or ring == nil then return nil end
		for _, rn in ipairs(ring.nodes or {}) do
			local ab = zoneOfNode(rn)
			if ab ~= nil and Rules.RING_VARIANT_SET[ab] then return ab end
		end
		return nil
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
		if (kind == "APPLY" or kind == "SKIP" or kind == "LIGHTS" or kind == "PHASES" or kind == "AUDIT" or kind == "RETIME"
			or kind == "AUTORETIME")
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

	-- Kept nodes (sl_kept.lua): the mirror of the saved list (seq = its kseq), re-read at most once per frame and
	-- only when kseq changed; the tool's own events are applied to it at once (the game script answers a tick later).
	C.kept = { seq = nil, list = nil, idx = Kept.index(nil), frame = nil }
	local function refreshKept()
		local k = C.kept
		if k.frame == C.frames then return end
		k.frame = C.frames
		local seq, list = Kept.readSaved(api, k.seq)
		-- replaced on the first read and when kseq changed only: the tool's own events stay in the mirror until the
		-- game script has stored them (kseq then changes)
		if list ~= nil and (not k.read or seq ~= k.seq) then
			k.read = true
			k.seq, k.list = seq, list
			k.idx = Kept.index(list)
		end
	end
	--- Node n's position (BASE_NODE), nil when gone or unreadable.
	local function nodeXY(n)
		local ok, p = pcall(function()
			local bn = api.engine.getComponent(n, api.type.ComponentType.BASE_NODE)
			return bn and bn.position
		end)
		if not ok or p == nil or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
		return p
	end
	--- Whether node n is kept (by id or position; the mirror as last refreshed).
	local function isKept(n)
		if (C.kept.idx.n or 0) == 0 or type(n) ~= "number" then return false end
		local p = nodeXY(n)
		return Kept.match(C.kept.idx, n, p and p.x, p and p.y) ~= nil
	end
	C.isKept = function(n)
		refreshKept()
		return isKept(n)
	end
	--- Marks (op "add", Reset) or unmarks (op "remove", Apply) nodes: SmartLanes.kept events of at most
	-- Kept.EVENT_MAX nodes, and the same change on the mirror. A remove names only the nodes that are kept (an
	-- Apply elsewhere sends nothing). Never throws (ERROR where=kept).
	local function markKept(op, nodes)
		local ok, e = pcall(function()
			refreshKept()
			local list, seen = {}, {}
			for _, n in ipairs(nodes or {}) do
				if type(n) == "number" and not seen[n] then
					seen[n] = true
					local p = nodeXY(n)
					if p ~= nil and (op == "add" or Kept.match(C.kept.idx, n, p.x, p.y) ~= nil) then
						list[#list + 1] = { n, p.x, p.y }
					end
				end
			end
			if #list == 0 then return end
			local cmd = api.cmd
			if cmd == nil or cmd.makeScriptingSendEventCmd == nil then return end
			for _, pl in ipairs(Kept.payloads(op, list, "tool")) do
				cmd.sendCommand(cmd.makeScriptingSendEventCmd("", Kept.EVENT_ID, Kept.EV_KEPT, pl))
				C.kept.list = Kept.apply(C.kept.list, op, pl.nodes)
			end
			C.kept.idx = Kept.index(C.kept.list)
			-- the badges show the change (the statuses' caches hold no kept state)
			C.badgeCache = {}
		end)
		if not ok then out("ERROR", { { "where", "kept" }, { "err", e } }) end
	end
	--- The nodes a Reset / Apply on selection s covers: a street or multi selection its junctions, a roundabout
	-- (scope "ring" or a selected ring) every ring node, else the selected node.
	local function coveredNodes(s, scope)
		if s == nil then return {} end
		if s.kind == "street" or s.kind == "multi" then return s.junctionNodes or {} end
		if (scope == "ring" or s.kind == "ring") and s.ring ~= nil then return s.ring.nodes or {} end
		if s.kind == "node" and (s.ring ~= nil or s.slip ~= nil) then return { s.node } end
		return {}
	end
	C.coveredNodes = coveredNodes
	C.markKept = markKept

	-- "Keep timing adjusted" (sl_auto.lua, RETIME_PLAN.md "Step B"): the mirror of the saved list (seq = its aseq),
	-- re-read every AUTO_MIRROR_FRAMES frames at most and only when aseq changed; the tool's own events are applied to it
	-- at once. C.autoRt (set by the tool script): the runtime of this Lua state (sl_autoretime.lua, g.auto) or nil.
	C.auto = { seq = nil, list = nil, idx = Auto.index(nil), frame = nil, read = false }
	local function refreshAuto(force)
		local a = C.auto
		if not force and a.frame ~= nil and C.frames - a.frame < Core.AUTO_MIRROR_FRAMES and C.frames >= a.frame then return end
		a.frame = C.frames
		local seq, list, extra = Auto.readSaved(api, a.read and a.seq or nil)
		if list ~= nil and (not a.read or seq ~= a.seq) then
			a.read = true
			a.seq, a.list = seq, list
			a.idx = Auto.index(list)
			a.extra = extra or {}
		end
	end
	C.refreshAuto = refreshAuto
	--- The saved entry of node n ({n, x, y, t, e, c}: by id or position), nil when it is not enrolled.
	local function autoEntry(n)
		if type(n) ~= "number" then return nil end
		refreshAuto(false)
		if (C.auto.idx.n or 0) == 0 then return nil end
		-- once per frame and node (the toolbar asks every step for each param)
		local m = C.autoMemo
		if m ~= nil and m.frame == C.frames and m.node == n and m.idx == C.auto.idx then return m.entry end
		local p = nodeXY(n)
		local e = Auto.match(C.auto.idx, n, p and p.x, p and p.y)
		C.autoMemo = { frame = C.frames, node = n, idx = C.auto.idx, entry = e }
		return e
	end
	C.autoEntry = autoEntry
	local function autoRuntime()
		if C.autoRt == nil then return nil end
		local ok, rt = pcall(C.autoRt)
		if ok then return rt end
		return nil
	end
	-- The "last measured" records of both Re-time modes (sl_auto.lua rlast, RETIME_PLAN.md "Step B v4"): the mirror
	-- (seq = its lseq), re-read every AUTO_MIRROR_FRAMES frames at most and only when lseq changed; the tool's own
	-- records are applied to it at once.
	C.lastm = { seq = nil, list = nil, idx = Auto.lastIndex(nil), frame = nil, read = false }
	local function refreshLast(force)
		local a = C.lastm
		if not force and a.frame ~= nil and C.frames - a.frame < Core.AUTO_MIRROR_FRAMES and C.frames >= a.frame then return end
		a.frame = C.frames
		local seq, list = Auto.readLast(api, a.read and a.seq or nil)
		if list ~= nil and (not a.read or seq ~= a.seq) then
			a.read = true
			a.seq, a.list = seq, list
			a.idx = Auto.lastIndex(list)
		end
	end
	C.refreshLast = refreshLast
	--- The saved record of node n ({n, x, y, t, k, c0, c1}), nil when none.
	local function lastEntry(n)
		if type(n) ~= "number" then return nil end
		refreshLast(false)
		if (C.lastm.idx.n or 0) == 0 then return nil end
		local p = nodeXY(n)
		return Auto.match(C.lastm.idx, n, p and p.x, p and p.y)
	end
	C.lastEntry = lastEntry
	--- Sends one SmartLanes.auto event and applies it to the mirror (add / remove). Never throws.
	local function sendAuto(payload)
		local ok, e = pcall(function()
			local cmd = api.cmd
			if cmd == nil or cmd.makeScriptingSendEventCmd == nil then return end
			cmd.sendCommand(cmd.makeScriptingSendEventCmd("", Auto.EVENT_ID, Auto.EV_AUTO, payload))
			if payload.op == "add" or payload.op == "remove" then
				C.auto.list = Auto.apply(C.auto.list, payload.op, payload.nodes)
				C.auto.idx = Auto.index(C.auto.list)
			end
		end)
		if not ok then out("ERROR", { { "where", "auto" }, { "err", e } }) end
		-- the runtime of this Lua state reads the change soon, also while idle (sl_autoretime R.wake)
		local art = autoRuntime()
		if art ~= nil and art.wake ~= nil then pcall(art.wake) end
	end
	--- Records applied to the mirror at once (the status reads them before their event lands): the manual Re-time's
	-- own, and the runtime's (sl_autoretime opts.lastSent, when it shares this Lua state) so Smart lights does not read
	-- a fresh write of Keep timing adjusted as a hand edit until its batch lands. Never throws.
	function C.noteLast(records)
		if type(records) ~= "table" or #records == 0 then return end
		pcall(function()
			refreshLast(false)
			C.lastm.list = Auto.applyLast(C.lastm.idx.list, records)
			C.lastm.idx = Auto.lastIndex(C.lastm.list)
		end)
	end
	--- The durations of node n's phases now (a light read), nil when unreadable.
	local function durationsOf(n)
		local okR, r = pcall(W.lightRead, n)
		if not okR or r == nil or r.tlc == nil then return nil end
		local d = {}
		for i, st in ipairs(r.tlc.states or {}) do
			if i > Auto.DSIG_PHASES then break end
			d[i] = st.duration
		end
		return d
	end
	--- The manual Re-time's last-measured record at node (out: "written" | "fits" | "small" | "notwritten"; c0 / c1
	-- the cycle before / after; written: the durations it wrote, for the record's signature, else the previous
	-- record's is carried: Auto.carrySig). Saved like the automatic mode's (SmartLanes.auto op=last src=tool).
	local function sendRecord(node, outcome, c0, c1, written)
		local p = nodeXY(node)
		if p == nil then return end
		local d
		if outcome == "written" then d = Auto.durSig(written) or 0
		else d = Auto.carrySig(lastEntry(node), durationsOf(node)) end
		local r = Auto.record(node, p.x, p.y, C.retimer.now(), "manual", outcome, c0, c1, d)
		if r == nil then return end
		C.noteLast({ r })
		sendAuto({ op = "last", src = "tool", nodes = { r } })
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
		-- the zones first (at most once per frame): a ring in a ring layout variant zone is judged by that variant
		-- (ringVariantOf). Without this a single junction pick before any Apply / multi pick read them judged an
		-- sl_rsplit ring by turbo: "custom" (Sheet 4 v4, ring 269911, 2026-10-14)
		refreshZones()
		local cur, road, parts, seeds = {}, {}, { segsText(ring.segs) }, {}
		for _, n in ipairs(ring.nodes) do
			seeds[n] = true
			cur[n] = connsIn(world, n)
			-- connections touching a bus-only lane never count (kept as the player has them)
			road[n] = Rules.roadText(cur[n], Ring.busLanes(world, n))
			parts[#parts + 1] = tostring(n) .. "=" .. road[n]
		end
		local ck, text = "ring:" .. tostring(ring.key) .. ":" .. (ringVariantOf(ring) or ""), table.concat(parts, ";")
		local hit = C.badgeCache[ck]
		if hit ~= nil and hit.text == text then
			C.badgeStats.hits = C.badgeStats.hits + 1
			return hit.res
		end
		C.badgeStats.misses = C.badgeStats.misses + 1
		local function get(n) return cur[n] or connsIn(world, n) end
		local smart = Rules.planRing(world, ring, seeds, ringVariantOf(ring) or "turbo", get)
		local engine = Rules.planRing(world, ring, seeds, "engine", get)
		local eng = {}
		-- the ring's plain nodes count too (PLAN.md "Default: the mid-node spiral"): its smart lanes need every mid
		-- node of the plan written, its game default every plain node straight on (the engine plan lists those
		-- that are not); a junction's status carries the ring's mid-node state
		local midSmart, midDefault = true, true
		for _, r in ipairs(engine.nodes) do
			eng[r.node] = r
			if r.mid and r.status == "apply" then midDefault = false end
		end
		for _, r in ipairs(smart.nodes) do
			if r.mid and r.conns ~= nil and r.status == "apply" then midSmart = false end
		end
		local res = {}
		for _, r in ipairs(smart.nodes) do
			if r.mid then
				-- (not a junction: no status of its own)
			elseif (r.status == "same" or r.status == "apply") and r.conns ~= nil then
				local e = eng[r.node]
				local bus = Ring.busLanes(world, r.node)
				res[r.node] = {
					smart = midSmart and Rules.roadText(r.conns, bus) == road[r.node],
					default = midDefault and e ~= nil and e.conns ~= nil and Rules.roadText(e.conns, bus) == road[r.node],
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
		-- connections touching a bus-only lane never count (kept as the player has them): not in the key either
		local bus = Ring.busLanes(world, n)
		local key = segsText(node and node.segs) .. ":" .. Rules.roadText(cur, bus) .. (opts and ":fan" or "") .. (exitFan and ":exitfan" or "")
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
			local road = Rules.roadText(cur, bus)
			local model = Slip.defaultConns(r.view)
			-- default: per movement (Slip.isDefault), the engine's lane choice varies per approach
			res = { smart = Rules.roadText(r.conns, bus) == road, model = model ~= nil, case = r.view.case,
				default = model ~= nil and (Rules.roadText(model) == road or Slip.isDefault(r.view, cur) == true) or nil,
				-- the lane status names the reason when smart = default: one car lane per approach; bus lanes kept
				oneLane = Rules.oneLaneEach(r.conns, bus), bus = bus ~= nil }
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
		local info = { kind = "slip", total = 1, smart = st.smart and 1 or 0, oneLane = st.oneLane == true, bus = st.bus == true }
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
			parts[#parts + 1] = tostring(n) .. "=" .. segsText(node and node.segs) .. ":" .. Rules.roadText(cur[n], Ring.busLanes(world, n))
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
			local info = { kind = t.kind, total = 0, smart = 0, default = 0, oneLane = true, bus = false }
			local models = true
			for _, n in ipairs(t.junctionNodes or {}) do
				local s = st[n]
				if s ~= nil and not s.skip then
					info.total = info.total + 1
					if s.smart then info.smart = info.smart + 1 end
					if s.default then info.default = info.default + 1 end
					if not s.model then models = false end
					if s.oneLane ~= true then info.oneLane = false end
					if s.bus == true then info.bus = true end
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

	--- Whether the read phases of a node (W.lightRead result r) are the game's own default: true, or false and why
	-- ("user_modified" | "shape" | "whole_s" | "no_phases"). Retime.phasesDefault (sl_retime.lua; shared with the
	-- runtime's new-light Smart lights, sl_autoretime.lua), or any phases the engine made (Retime.phasesEngineMade:
	-- a 1-lane T's 7-phase default, the flag set by a light switch; in game 2026-10-16), so Reset is not offered there.
	function C.phasesDefault(r)
		local d, why = Retime.phasesDefault(r)
		if d == true then return true end
		local okE, e = pcall(Retime.phasesEngineMade, r)
		if okE and e == true then return true end
		return false, why
	end
	--- The phases a Reset of ours gave back (PLAN.md "Reset hides after a Reset"): the heuristic above reads them as
	-- changed (our states = {} write sets userModifiedTrafficLightStates, and a T-junction's default can differ from
	-- the 6-phase shape), so Reset stayed shown after a Reset (user 2026-10-16, node 35512: four Resets in a row).
	-- C.resetPhases[n] = true when a Reset's default write landed, then the signature of the first read with phases;
	-- phases equal to it count as default until something changes them (Re-time, Keep timing adjusted, the Crossing
	-- window). Session only (cleared when full): after a reload the heuristic decides again.
	C.resetPhases, C.resetPhasesCount = {}, 0
	function C.markReset(n)
		if type(n) ~= "number" then return end
		if C.resetPhases[n] == nil then
			if C.resetPhasesCount >= Core.NODE_STATUS_MAX then C.resetPhases, C.resetPhasesCount = {}, 0 end
			C.resetPhasesCount = C.resetPhasesCount + 1
		end
		C.resetPhases[n] = true
	end
	function C.clearReset(n)
		if C.resetPhases[n] == nil then return end
		C.resetPhases[n] = nil
		C.resetPhasesCount = math.max(C.resetPhasesCount - 1, 0)
	end
	--- Whether node n's read phases r are the ones its last Reset gave back.
	local function phasesFromReset(n, r)
		local m = C.resetPhases[n]
		if m == nil or r == nil or r.tlc == nil then return false end
		local okS, sig = pcall(W.statesSig, r.tlc)
		if not okS then return false end
		if m == true then
			-- the first read after the write landed: the engine's new default (none yet: wait for it)
			if #r.tlc.states == 0 then return true end
			C.resetPhases[n] = sig
			return true
		end
		if m == sig then return true end
		C.clearReset(n)
		return false
	end
	C.phasesFromReset = phasesFromReset

	--- Node n has a standing light whose phases are not the game's default (C.phasesDefault); false when unlit,
	-- unreadable, default or as its last Reset left them.
	local function phasesChanged(n)
		if type(n) ~= "number" then return false end
		local okR, r = pcall(W.lightRead, n)
		if not okR or r == nil then return false end
		if phasesFromReset(n, r) then return false end
		local okD, d = pcall(C.phasesDefault, r)
		return okD and d == false
	end
	C.phasesChanged = phasesChanged

	--- "Lights only" at crossroads / T-junction n (sl_cross case "X"): { ok = true, same, timed, hand } when a Smart
	-- Lanes plan for its current connections and crosswalks exists (same: the phases are that plan already; timed:
	-- they are the plan's phases with durations Smart Lanes wrote, Re-time or Keep timing adjusted; hand: the plan's
	-- phases with durations we did not write, the player's Crossing window: Smart lights is offered again, PLAN.md
	-- "Smart lights stays on after its timing changed"), else
	-- { why = "not_x" | "no_light" | "no_phases" | "no_config" | "stale_conns" | "crosswalks" | "plan_fail:<reason>" }.
	-- Cached per node by its connections, crosswalks and phases (NODE_STATUS_FRAMES at most), so a refresh plans
	-- again only when one of them changed; timed vs hand is decided on every call from the junction's last-measured
	-- record (Auto.timingOf: the signature of the durations we last wrote). lp: the plan input (C.lightsOnly builds
	-- the same).
	local timedOrHand
	local function lightsInput(world, n)
		local v = Slip.classify(world, n)
		if v.kind ~= "slip" or v.case ~= "X" then return nil end
		local o = planOpts(world, n)
		return { view = v, world = world, fan = (o and o.fan) or nil }
	end
	--- A cached lightsStatus result with its structure-only match resolved: timed when the durations are the ones
	-- Smart Lanes last wrote there (user 2026-10-16: Smart lights stays on over its fitted timing), else hand (user
	-- 2026-10-16: "if i manually change the timing of a light phase it should know it wasnt the re-time doing it":
	-- Smart lights and Reset are offered). A fresh table only for a structure match.
	timedOrHand = function(n, res)
		if type(res) ~= "table" or not res.struct then return res end
		local who = Auto.timingOf(lastEntry(n), res.durs)
		if who == "ours" then return { ok = true, same = false, timed = true } end
		return { ok = true, same = false, hand = true }
	end
	function C.lightsStatus(world, n)
		local lp = lightsInput(world, n)
		if lp == nil then return { why = "not_x" } end
		-- the world's light read first (once per node and world, as the plan's X.litOf): no second read
		-- of an unlit junction
		if type(world.lit) == "function" and world.lit(n) ~= true then return { why = "no_light" } end
		local r, why = W.lightRead(n)
		if r == nil then return { why = why } end
		local key = Rules.connsText(r.conns) .. "|" .. table.concat(r.cws, ",") .. "|" .. W.statesSig(r.tlc)
			.. (lp.fan and "|fan" or "")
		local e = C.lightsCache[n]
		if e ~= nil and e.key == key and C.frames - e.at < Core.NODE_STATUS_FRAMES then return timedOrHand(n, e.res) end
		local okP, plan, whyP = pcall(W.planFor, n, r.conns, r.cws, lp)
		local res
		if okP and plan ~= nil then
			local same = W.samePlan(r.tlc.states, plan)
			-- structure: the plan's phases in other durations (Re-time, Keep timing adjusted, or the Crossing window;
			-- timedOrHand tells which)
			local struct = (not same and W.samePlan(r.tlc.states, plan, true)) or nil
			res = { ok = true, same = same, struct = struct, durs = struct and durationsOf(n) or nil }
		else
			res = { why = "plan_fail:" .. (okP and tostring(whyP) or ("error:" .. tostring(plan):gsub("^.-:%d+: ", ""))) }
		end
		if e == nil then
			if C.lightsCacheCount >= Core.NODE_STATUS_MAX then C.lightsCache, C.lightsCacheCount = {}, 0 end
			C.lightsCacheCount = C.lightsCacheCount + 1
		end
		C.lightsCache[n] = { key = key, at = C.frames, res = res }
		return timedOrHand(n, res)
	end

	--- Which toolbar buttons would change something for target t: { applyNode, applyRing, reset, lights, retime }.
	-- From the same per-junction statuses as the badge (cached), so a button is shown exactly
	-- when its click would write (C.actions): Apply where a handled junction is not smart lanes yet, Reset
	-- where one differs from the game default model (slip nodes: from the snapshot of the first Apply).
	function C.canInfo(world, t)
		local can = { applyNode = false, applyRing = false, reset = false, lights = false }
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
						-- bus-lane connections do not count (Reset keeps the player's: Rules.keepBus)
						local bus = Ring.busLanes(world, n)
						can.reset = snap ~= nil and Rules.carText(snap, bus) ~= Rules.carText(connsIn(world, n), bus)
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
			-- Lights only: a crossroads / T-junction with a light and a plan that differs from its phases
			if t.slip.case == "X" then
				local okL, ls = pcall(C.lightsStatus, world, t.node)
				if not okL then ls = { why = "error" } end
				t.lights = ls
				can.lights = ls.ok == true and not ls.same and not ls.timed
			end
			if info.default ~= nil then
				-- crossroads: Reset writes the game-default model
				can.reset = info.kind == "slip" and info.default == 0
			else
				local snap = C.snapshots[t.node]
				local bus = Ring.busLanes(world, t.node)
				can.reset = snap ~= nil and Rules.carText(snap, bus) ~= Rules.carText(connsIn(world, t.node), bus)
					and snapFits(world, t.node, snap)
			end
		end
		-- Re-time: any single junction with a standing traffic light and phases, whatever made them (C.retime)
		-- (the world's light read first, once per node and world: no second read of an unlit junction)
		if t.kind == "node" and type(t.node) == "number" and type(world.lit) == "function" and world.lit(t.node) == true then
			local okR, r = pcall(W.lightRead, t.node)
			can.retime = okR and r ~= nil
			-- a lit junction that is no crossroads / T-junction (5 arms, a slip node, a ring junction): Smart lights has
			-- no plan there (the game's phases stay, PLAN.md "No classic fallback"); the detail line says so
			if can.retime and (t.ring ~= nil or type(t.lights) ~= "table" or t.lights.why == "not_x") then
				t.lights = { why = "shape" }
			end
			-- Reset at a lit crossroads / T-junction also gives the game's default phases back (C.applySlip): it can
			-- act when they are not the default (Lights only, Re-time, the Crossing window)
			if can.retime and t.slip ~= nil and t.slip.case == "X" and t.ring == nil then
				local okD, d = pcall(C.phasesDefault, r)
				can.resetPhases = okD and d == false and not phasesFromReset(t.node, r)
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
		if ok and type(info) == "table" and info.kind ~= "na" then
			-- kept junctions (sl_kept.lua): Pick.badge shows "Game default (locked)" when every handled one is
			local okK, nK = pcall(function()
				refreshKept()
				if (C.kept.idx.n or 0) == 0 then return 0 end
				local list = (t.kind == "street" or t.kind == "multi" or t.kind == "ring") and (t.junctionNodes or {}) or { t.node }
				local k = 0
				for _, n in ipairs(list) do
					if isKept(n) then k = k + 1 end
				end
				return k
			end)
			info.kept = okK and nK or 0
		end
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
		-- the badge checks what is applied: "√ Smart lanes | √ Smart lights" (user 2026-10-16; C.canInfo set t.lights)
		local ls = t.kind == "node" and t.ring == nil and t.lights or nil
		t.badge = Pick.badgeChecks(t.badge, type(ls) == "table" and ls.ok == true and (ls.same == true or ls.timed == true))
		t.sig = targetSig(world, t)
		perf:stop("badge", tBadge)
		return t
	end

	--- Pick-target info for node n (nil when n is not a street node).
	-- { kind = "node", node, roads, conns, ring, ringKey, ringLanes, junctions, junctionNodes,
	--   nodeKind, exits, entries, reason, busKept (a handled junction with a bus-only lane: Ring.busLanes) }
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
			t.busKept = v.bus ~= nil or nil
		else
			local v = Slip.classify(world, n)
			if v.kind == "slip" then
				t.slip, t.nodeKind = v, "slip"
				t.slipShape, t.slipLanes, t.slipSummary = v.shape, Slip.mainLanes(v), Slip.summary(v)
				t.slipCounts = Slip.streamCounts(v)
				t.busKept = v.bus ~= nil or nil
			elseif v.busRoad then
				-- a bus-only road among its roads: the plain reason (user 2026-10-17: "simple and friendly")
				t.slipReason = "bus_road"
			elseif v.kind == "skip" then
				t.slipReason = v.reason
			end
		end
		return addBadge(world, t)
	end

	function C.fillRing(world, ring, t)
		t.ring, t.ringKey, t.ringLanes = ring, ring.key, ring.lanes
		t.junctionNodes = {}
		t.midNodes = 0
		for _, rn in ipairs(ring.nodes) do
			if Ring.nodeView(world, ring, rn).kind ~= "plain" then
				t.junctionNodes[#t.junctionNodes + 1] = rn
			elseif Rules.roadCount(connsIn(world, rn)) > (ring.lanes or 0) then
				-- a plain ring node with lane changes (the mid-node spiral's): shown in the detail line, drawn by C.highlight
				t.midNodes = t.midNodes + 1
			end
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
		-- all lights: a lit junction not enrolled yet is enrolled at once where the rules allow it (C.allSelect)
		local okAS, eAS = pcall(C.allSelect, target)
		if not okAS then out("ERROR", { { "where", "all_select" }, { "err", eAS } }) end
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
	-- sl_phases / sl_auto / sl_fan zone (sl_zones.lua; the automatic pass plans phases there too), "game" inside an sl_lock
	-- zone (game phases with the kerb turn locked) or an sl_exitfan zone (the exit fan is planned for the
	-- game's phases), else the setting.
	local function phasesAt(view)
		local mode = W.phasesMode()
		if view ~= nil then
			local ab = zoneOfNode(view.node)
			if mode ~= "sl" and (ab == "sl_phases" or ab == "sl_auto" or ab == "sl_fan") then return "sl" end
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

	--- Whether a Reset gives the game's default phases back: at a crossroads with Light phases = Smart Lanes, and at
	-- any lit crossroads whose phases are not the game's default (C.phasesDefault: Lights only, Re-time, the
	-- Crossing window; rev 8, user 2026-10-14: Reset undoes a phase change too).
	local function resetDefaultFor(view, layout)
		if layout ~= "game" or view == nil or view.case ~= "X" then return false end
		return phasesAt(view) == "sl" or phasesChanged(view.node)
	end

	--- The log fields of a phase change (appended to f): free_turn=n free_phases=p [kept=.. merge_free=n] shared_held=n /
	-- lock_turn=n lock_phases=p. stats: W.remapLights' (nil: zeros).
	local function phaseFields(f, mode, n, stats)
		local lock = mode == Lights.LOCK
		f[#f + 1] = { lock and "lock_turn" or "free_turn", n or 0 }
		f[#f + 1] = { lock and "lock_phases" or "free_phases", stats and stats.phases or 0 }
		if mode == Lights.SAFE then
			f[#f + 1] = { "kept", Lights.keptText(stats) }
			f[#f + 1] = { "merge_free", stats and stats.merged or 0 }
		end
		if not lock then f[#f + 1] = { "shared_held", stats and stats.shared or 0 } end
		return f
	end

	--- A light proposal where the lanes stay; never breaks the lane result. send(onDone) sends it and
	-- returns the number sent (0: nothing). Holds the tool's buttons (C.actions: C.phaseHold) until the
	-- light proposal answered and VERIFY_DELAY frames more: a write built from reads before it lands
	-- would be refused or index stale phases.
	local function lightOnly(node, send)
		local answered, counted, gen = false, false, nil
		-- any light write of ours ends what the last Reset left (C.resetPhases; a Reset marks it again on landing)
		C.clearReset(node)
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
				-- the plan's phases with adjusted timing stay (keepTiming: Smart lights is on there already)
				local n, why = W.planLights(node, lp, src, onDone, nil, true)
				if n > 0 or phase == nil or not tostring(why):find("^plan_fail") then return n end
			end
			return (W.kerbLights(node, phase.kerb, phase.mode, src, onDone))
		end)
	end

	--- The game's default phases back where the lanes stay or after their write answered (W.defaultLights).
	local function defaultOnly(node, src)
		return lightOnly(node, function(onDone)
			return (W.defaultLights(node, src, function(success)
				if success and src == "reset" then C.markReset(node) end
				if onDone then onDone(success) end
			end))
		end)
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
		C.clearReset(node)
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
			setResult(_("Not a roundabout"))
			return C.result
		end
		local world = W.makeWorld()
		local cur = W.currentConns(s.node)
		-- crossroads, lane drops and junctions with a bus lane keep their lights (Lights.keepsLights): never
		-- touched here
		local case = s.slip and s.slip.case
		local lights = not Lights.keepsLights(case, s.slip and s.slip.bus)
		if layout == "game" and case == "X" then
			-- crossroads: the game-default model (Slip.defaultConns), tram and bus-lane connections kept
			local v = Slip.classify(world, s.node)
			local model = v.kind == "slip" and Slip.defaultConns(v) or nil
			if model == nil then
				setResult(_("Not a slip-lane junction any more; select it again"))
				return C.result
			end
			local conns = Rules.mergeTram(model, cur, v.bus)
			-- the game's phases too: the kerb turns locked again with their approach (Light phases = Smart
			-- Lanes: then the game's default phases, states = {})
			local phase = phaseFor(v, "game")
			local resetDefault = resetDefaultFor(v, "game")
			out("RESET", { { "mode", "model" }, { "kind", "slip" }, { "node", s.node }, { "conns", #conns } })
			-- the game's own lanes (per movement, Slip.isDefault) count as set: never rewritten to the model
			if Rules.connsText(conns) == Rules.connsText(cur) or Slip.isDefault(v, cur) == true then
				local changed = resetDefault and phasesChanged(s.node)
				if resetDefault then defaultOnly(s.node, "reset") else phaseOnly(s.node, phase, "reset") end
				if changed then
					setResult(_("Light phases reset to the game default"))
				else
					setResult(string.format(_("%s already set"), layoutText("game")))
				end
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
				setResult(_("Reset not available here (no smart lanes set yet)"))
				return C.result
			end
			if not snapFits(world, s.node, snap) then
				-- the roads changed since the Apply: the old connections name segments gone from the node
				C.snapshots[s.node] = nil
				out("RESET", { { "mode", "stale" }, { "kind", "slip" }, { "node", s.node } })
				setResult(_("Reset not available here (no smart lanes set yet)"))
				return C.result
			end
			local now = Slip.classify(world, s.node)
			if now.kind == "slip" then lights = not Lights.keepsLights(now.case, now.bus) end
			-- the lanes as before the Apply, the bus-lane connections as they are now (Rules.keepBus)
			local back = Rules.keepBus(snap, cur, Ring.busLanes(world, s.node))
			out("RESET", { { "mode", "snapshot" }, { "kind", "slip" }, { "node", s.node }, { "conns", #back } })
			if Rules.connsText(back) == Rules.connsText(cur) then
				if lights then toolLights({ s.node }, "game", s.node) end
				setResult(_("Already the lanes from before smart lanes"))
				return C.result
			end
			return writeSlip(s.node, back, "reset", _("Lanes from before smart lanes restored"), "game", lights)
		end
		local r = Slip.plan(world, s.node, function() return cur end, planOpts(world, s.node))
		if r.status == "none" or r.status == "skip" then
			setResult(_("Not a slip-lane junction any more; select it again"))
			return C.result
		end
		-- the node as it is now (the selection's case may be stale: a road built or upgraded since)
		lights = not Lights.keepsLights(r.view.case, r.view.bus)
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

	--- "Lights only" (the toolbar's Lights only button): Smart Lanes phases for the selected crossroads / T-junction's
	-- lanes as they are (see the header). Whatever "Light phases" says: the click asks for them. Never while a
	-- job, a write or a light proposal of the tool is pending (C.actions; lightOnly holds the buttons until the
	-- proposal answered). Returns the result text.
	function C.lightsOnly()
		refreshZones()
		local s = C.sel
		if C.job ~= nil then
			-- busyJob's text (defined further down)
			setResult(string.format(_("Applying %s..."), layoutText(C.job.layout)))
			return C.result
		end
		if s == nil or s.kind ~= "node" or s.ring ~= nil or s.slip == nil or s.slip.case ~= "X" then
			setResult(string.format(_("Smart lights: %s"), _("select a crossroads or T-junction")))
			return C.result
		end
		local node = s.node
		local world = W.makeWorld()
		local lp = lightsInput(world, node)
		local function phases(f)
			local fields = { { "src", "tool" }, { "action", "lights_only" }, { "node", node }, { "phases", "sl" } }
			for _, kv in ipairs(f) do fields[#fields + 1] = kv end
			out("PHASES", fields)
		end
		if lp == nil then
			phases({ { "plan_fail", "not_x" } })
			setResult(string.format(_("Smart lights: %s"), _("select a crossroads or T-junction")))
			return C.result
		end
		-- the plan's phases timed by the player (not by Re-time / Keep timing adjusted): the click puts the plan's
		-- timing back; timed by us: kept (nothing sent)
		local okL, ls = pcall(C.lightsStatus, world, node)
		local keepTiming = not (okL and type(ls) == "table" and ls.hand == true)
		local why, text, answered, okSent, pattern, timed = nil, nil, false, nil, nil, nil
		local n = lightOnly(node, function(onDone)
			local k, w, t, pat, tm = W.planLights(node, lp, "tool", function(success)
				answered, okSent = true, success
				onDone(success)
				if success then
					setResult(_("Light phases set for the current lanes"))
				else
					setResult(_("The game refused the change (see log)"))
				end
			end, { { "action", "lights_only" } }, keepTiming)
			why, text, pattern, timed = w, t, pat, tm
			return k
		end)
		C.lightsCache[node] = nil
		if n > 0 then
			local f = { { "pattern", pattern or "none" }, { "plan", text } }
			if not keepTiming then table.insert(f, 1, { "hand", 1 }) end
			phases(f)
			if not answered then setResult(_("Applying...")) end
			return C.result
		end
		if why == "same" then
			phases({ { "same", 1 }, { "timed", timed and 1 or 0 }, { "pattern", pattern or "none" }, { "plan", text } })
			setResult(string.format(_("Smart lights: %s"), timed and _("on, timing adjusted") or _("Smart Lanes phases already set")))
		elseif why == "no_light" or why == "no_phases" or why == "no_config" then
			phases({ { "plan_fail", why } })
			setResult(string.format(_("Smart lights: %s"), _("no traffic light here")))
		elseif tostring(why):find("^plan_fail:") then
			-- no axis plan (PLAN.md "No classic fallback"): the game's phases stay
			phases({ { "pattern", "none" }, { "plan_fail", (tostring(why):gsub("^plan_fail:", "")) } })
			setResult(string.format(_("Smart lights: %s"), Pick.lightsText({ why = why }) or _("no phase plan for these lanes")))
		else
			phases({ { "plan_fail", tostring(why) } })
			setResult(_("Could not build the change (see log)"))
		end
		return C.result
	end

	---------------------------------------------------------------------------
	-- Re-time (the toolbar's Re-time button, rev 8; PLAN.md "Re-time: phase lengths from measured traffic",
	-- RETIME_PLAN.md step A): measures the traffic of the selected junction with a standing light and phases
	-- (sl_retimer.lua, in the background over frames) and then writes new phase durations only (sl_retime.lua
	-- R.plan; W.retimeLights: lockedLanes and canSkip as read). Cancelled by the button (rev 8 v2: deselecting, another
	-- junction and closing the tool no longer cancel), or (aborted) when the junction's lanes or phases change or it is gone.
	-- Up to Core.RETIME_MAX_RUNNING runs at once (rev 9, 2026-10-17; before: one): C.rts by node, C.rtList in start
	-- order, each a target of C.retimer's one shared sampler run (sl_retimer.lua M.startShared: one pass over every
	-- run's candidates, Retimer.BUDGET_S per frame for all; more runs make a sample take more frames, never more time
	-- per frame). The sampler run starts with the first run and ends when the last one's window is over, so with no run
	-- measuring nothing is sampled; a finished, canceled or failed run is dropped (rtDrop). In memory only: a load
	-- starts with none running. Each run's window ends on its own; its write waits while a proposal of the tool is
	-- pending (job, write re-read, phaseHold: another run's write too, so runs ending together write one after the
	-- other) and is held like every phases-only proposal (lightOnly). After it, the probe logs RETIME op=probe / op=reroute lines (format: PLAN.md
	-- "Logging"); the re-route baseline is taken RETIME_BASE_BEFORE s before the window ends.

	--- A RETIME line (at most Core.RETIME_LINES_MAX per session).
	local function rtLog(fields)
		if C.rtLines >= Core.RETIME_LINES_MAX then return end
		C.rtLines = C.rtLines + 1
		if C.rtLines == Core.RETIME_LINES_MAX then fields[#fields + 1] = { "more", "suppressed" } end
		out("RETIME", fields)
	end

	--- The node's phases as read now: { r (W.lightRead), sig, conns (text), states (plain) }, or nil, why.
	local function rtRead(node)
		local r, why = W.lightRead(node)
		if r == nil then return nil, why end
		local states = {}
		for i, st in ipairs(r.tlc.states) do
			local l = {}
			for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
			states[i] = { locked = l, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip == true }
		end
		return { r = r, sig = W.statesSig(r.tlc), conns = Rules.connsText(r.conns), states = states }
	end

	--- Timers of the Re-time runs and their probes: { at = game s | frame = n, run = fn, node, base = true }.
	C.rtTimers = {}

	--- Whether node is the selected junction (Re-time's texts go to the status only then: the run goes on whatever
	-- is selected, with the tool closed too).
	local function selAt(node)
		local s = C.sel
		return s ~= nil and s.kind == "node" and s.node == node
	end
	--- A Re-time result text for the status, only while its junction is selected.
	local function rtSay(node, text)
		if selAt(node) then setResult(text) end
	end

	--- The running Re-time runs in start order (a copy: a run may end while the caller walks it; at most
	-- Core.RETIME_MAX_RUNNING).
	local function rtRuns()
		local list = {}
		for i, rt in ipairs(C.rtList) do
			if i > Core.RETIME_MAX_RUNNING then break end
			list[#list + 1] = rt
		end
		return list
	end

	--- Whether any Re-time run measures (sl_bg.script.lua opts.manualBusy: Keep timing adjusted takes no snapshot
	-- meanwhile). Nothing running: false at once.
	function C.rtMeasuring()
		if C.rtCount <= 0 then return false end
		for i, rt in ipairs(C.rtList) do
			if i > Core.RETIME_MAX_RUNNING then break end
			if rt.phase == "measuring" then return true end
		end
		return false
	end

	--- Takes run rt's target out of the shared sampler run (its window is over or it ends); the last one ends the
	-- sampler run, so nothing is sampled while no run measures.
	local function rtRelease(rt)
		if rt.tg == nil then return end
		rt.tg = nil
		C.retimer.removeTarget(rt.node)
		local run = C.retimer.run
		if run ~= nil and (run.targetCount or 0) <= 0 then C.retimer.cancel() end
	end

	--- Drops run rt (written, kept, canceled or failed): nothing of it stays.
	local function rtDrop(rt)
		if rt == nil or C.rts[rt.node] ~= rt then return end
		rtRelease(rt)
		C.rts[rt.node] = nil
		C.rtCount = C.rtCount - 1
		for i, x in ipairs(C.rtList) do
			if x == rt then
				table.remove(C.rtList, i)
				break
			end
		end
		if C.rtCount <= 0 then C.rts, C.rtList, C.rtCount = {}, {}, 0 end
	end

	--- Drops every run and the sampler run (an error).
	local function rtDropAll()
		C.rts, C.rtList, C.rtCount = {}, {}, 0
		C.retimer.cancel()
	end

	--- Game s run rt has measured (its window's elapsed time; after its window the time it measured).
	local function rtElapsed(rt)
		if rt.tg ~= nil then return math.max(0, math.min(rt.windowS, C.retimer.now() - rt.tg.t0)) end
		return rt.measuredS or 0
	end

	--- Ends run rt; reason for the log, text (translated phrase) for the status; drops its baseline timers.
	local function rtCancel(rt, reason, text)
		if rt == nil or C.rts[rt.node] ~= rt then return end
		local samples = rt.tg ~= nil and rt.tg.samples or rt.samples or 0
		rtLog({ { "op", "cancel" }, { "node", rt.node }, { "reason", reason }, { "elapsed_s", string.format("%.0f", rtElapsed(rt)) },
			{ "samples", samples }, { "running", C.rtCount } })
		rtDrop(rt)
		local keep = {}
		for _, t in ipairs(C.rtTimers) do
			if not (t.base and t.node == rt.node) then keep[#keep + 1] = t end
		end
		C.rtTimers = keep
		if text ~= nil then rtSay(rt.node, string.format(_("Re-time: %s"), text)) end
		bump()
	end

	--- The status re-renders once per elapsed game second while the measured junction is selected (C.retimeLines
	-- reads the progress).
	local function rtProgress(rt)
		local el = math.floor(rtElapsed(rt))
		if el == rt.shown then return end
		rt.shown = el
		if selAt(rt.node) then bump() end
	end

	--- RETIME op=probe at=<label>: the node's light now (sl_retimer lightNow) against the plan and before.
	local function probeLine(p, label, extra)
		local now = C.retimer.lightNow(p.node)
		local f = { { "op", "probe" }, { "node", p.node }, { "at", label }, { "exists", now.exists }, { "config", now.config },
			{ "light", now.light }, { "state", tostring(now.state) }, { "time", now.time and string.format("%.1f", now.time) or "nil" },
			{ "state_times", now.stateTimes or "-" }, { "user_modified", tostring(now.userModified) },
			{ "durations", now.durations or "-" } }
		-- after the write: the durations written, the red lanes as before it
		if p.want ~= nil and p.before ~= nil then
			f[#f + 1] = { "same_durations", now.durations == p.want }
			f[#f + 1] = { "same_locked", now.locked == p.before.locked }
		end
		if p.writeAt ~= nil then f[#f + 1] = { "since_s", string.format("%.1f", C.retimer.now() - p.writeAt) } end
		for _, kv in ipairs(extra or {}) do f[#f + 1] = kv end
		rtLog(f)
		return now
	end

	local function rerouteLine(node, label)
		return function(lbl, counts)
			rtLog({ { "op", "reroute" }, { "node", node }, { "at", lbl or label }, { "tracked", counts.tracked },
				{ "same", counts.same }, { "exit_changed", counts.exit_changed }, { "dropped", counts.dropped },
				{ "gone", counts.gone } })
		end
	end

	--- Schedules re-route checks of snap at +5 and +30 game s (labels prefix .. "5" / "30").
	local function scheduleReroute(node, snap, prefix, base)
		local t = C.retimer.now()
		for _, d in ipairs({ 5, 30 }) do
			local label = prefix .. d
			C.rtTimers[#C.rtTimers + 1] = { at = t + d, node = node, base = base, run = function()
				C.retimer.recheck(label, node, snap, rerouteLine(node, label))
			end }
		end
	end

	--- Sends the planned durations (the run's phase "waiting" and nothing pending: one write at a time, so runs whose
	-- windows end together write one after the other, each after the last one landed).
	local function rtWrite(rt)
		local node, plan = rt.node, rt.plan
		local c0, c1 = plan.oldCycle or 0, plan.cycle or plan.oldCycle or 0
		local p = { node = node, want = Retime.listText(plan.durations) }
		p.before = probeLine(p, "before")
		local snap = rt.snap or {}
		rtDrop(rt)
		p.writeAt = C.retimer.now()
		local n = lightOnly(node, function(onDone)
			local k, why = W.retimeLights(node, plan.durations, plan.minDurations, rt.sig, rt.conns, "tool", function(success)
				onDone(success)
				p.answered = true
				probeLine(p, "cb", { { "success", success } })
				local cbFrame = C.frames
				C.rtTimers[#C.rtTimers + 1] = { frame = cbFrame + Core.VERIFY_DELAY, node = node, run = function()
					probeLine(p, "f" .. Core.VERIFY_DELAY)
				end }
				if success then sendRecord(node, "written", c0, c1, plan.durations) else sendRecord(node, "notwritten", c0, c0) end
				if success then
					rtSay(node, _("Phase lengths set from the measured traffic"))
				else
					rtSay(node, _("The game refused the change (see log)"))
				end
				bump()
			end, { { "action", "retime" } })
			p.why = why
			return k
		end)
		rtLog({ { "op", "write" }, { "node", node }, { "sent", n }, { "why", p.why or "-" },
			{ "durations", Retime.listText(plan.durations) }, { "min", Retime.listText(plan.minDurations) } })
		if n > 0 then
			for _, d in ipairs({ 5, 30 }) do
				C.rtTimers[#C.rtTimers + 1] = { at = p.writeAt + d, node = node, run = function() probeLine(p, "s" .. d) end }
			end
			scheduleReroute(node, snap, "s", false)
			if not p.answered then rtSay(node, _("Applying...")) end
		else
			sendRecord(node, "notwritten", c0, c0)
			if p.why == "changed" then
				rtSay(node, string.format(_("Re-time: %s"), _("the junction changed, stopped")))
			else
				rtSay(node, _("Could not build the change (see log)"))
			end
		end
		bump()
	end

	local function rtBusy()
		return C.job ~= nil or next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0) or C.frames < (C.phaseHold or 0)
	end

	--- For the automatic re-timing runtime (sl_bg.script.lua, opts.toolBusy): a proposal of the tool pending, or the
	-- tool's own Re-time at node (measuring or waiting to write).
	function C.autoBusy(node)
		return rtBusy() or (C.rtCount > 0 and C.rts[node] ~= nil)
	end

	--- The "Keep timing adjusted" toggle (sl_tool.script.lua): on = the clicked side is Yes. Enrolls or unenrolls the
	-- selected lit junction (SmartLanes.auto add / remove, src=tool; the game script logs AUTORETIME
	-- op=enroll|unenroll). The click's value is the player's intent; the side already in force changes nothing. Refused beyond Auto.MAX junctions. Returns the result.
	function C.setAuto(on)
		local s = C.sel
		if s == nil or s.kind ~= "node" or type(s.node) ~= "number" then return C.result end
		local p = nodeXY(s.node)
		if p == nil then return C.result end
		refreshAuto(true)
		local was = Auto.match(C.auto.idx, s.node, p.x, p.y) ~= nil
		if on and not was then
			if (C.auto.idx.n or 0) >= Auto.MAX then
				setResult(string.format(_("Keep timing adjusted: at most %d junctions"), Auto.MAX))
				return C.result
			end
			sendAuto({ op = "add", src = "tool", nodes = { { s.node, p.x, p.y } } })
			setResult(_("Timing kept adjusted at this junction"))
		elseif not on and was then
			sendAuto({ op = "remove", src = "tool", nodes = { { s.node, p.x, p.y } } })
			setResult(_("Timing no longer adjusted at this junction"))
		end
		-- all lights: an untick is an opt-out, a tick an opt-in (the game script keeps aout); the mirror at once, so a
		-- selection before the event lands does not enroll it again (C.allSelect)
		if C.allMode() == "all" then
			C.auto.extra = C.auto.extra or {}
			local x = C.auto.extra
			local e = { { s.node, p.x, p.y } }
			if on then
				x.out = AllMode.optIn(x.out, e, Auto.matches)
				C.allWhy = nil
			elseif was then
				x.out = AllMode.optOut(x.out, e, Auto.matches)
				C.allWhy = { node = s.node, why = "optout" }
			end
		end
		bump()
		return C.result
	end

	-- "Automatic light timing" (sl_allmode.lua, PLAN.md "Automatic timing for all lights + first-load welcome"): the
	-- setting (read once) and the save's override (the mirror's amode)
	local function allSetting()
		if C.allSetting == nil then
			local ok, all = pcall(function() return api.engine.config.getModParams() end)
			C.allSetting = AllMode.settingOf(ok and type(all) == "table" and all[Rules.MOD_ID] or nil)
		end
		return C.allSetting
	end
	--- The mode in force ("all" | "pick" | "off"), the junctions enrolled, and the saved extras (sl_auto M.readSaved).
	function C.allMode()
		refreshAuto(false)
		local x = C.auto.extra or {}
		return AllMode.effective(allSetting(), x.mode), C.auto.idx.n or 0, x
	end
	--- The settings panel's "Automatic light timing" (sl_settingsui.lua, shown with nothing selected; rev 8 had the
	-- rows Adjust all lights / Stop for all lights): All lights / Junctions I choose / Off ("all" | "pick" | "off")
	-- send SmartLanes.auto op=mode (the save's amode; pick from all also unenrolls every junction, off keeps the list
	-- and the opt-outs: the game script's handleAuto). The mirror follows at once.
	function C.setLightMode(mode)
		local was = C.allMode()
		sendAuto({ op = "mode", mode = mode, src = "tool" })
		C.auto.extra = C.auto.extra or {}
		C.auto.extra.mode = mode
		if mode ~= "off" then C.auto.extra.out = nil end
		if mode == "pick" and was == "all" then
			C.auto.list = {}
			C.auto.idx = Auto.index(nil)
		end
		if mode == "all" then
			setResult(_("Timing kept adjusted at all traffic lights"))
		elseif mode == "off" then
			setResult(_("Automatic light timing is off"))
		else
			setResult(_("Timing no longer adjusted at any junction"))
		end
		bump()
		return C.result
	end
	--- The status line with nothing selected: the mode in force and how many junctions; the existing-junctions pass
	-- while it runs. A list of translated lines.
	function C.allLines()
		local mode, n, x = C.allMode()
		local lines = {}
		if mode == "all" then
			lines[1] = string.format(_("Light timing: all lights (%d junctions)"), n)
		elseif mode == "off" then
			lines[1] = _("Light timing: off")
		else
			lines[1] = string.format(_("Light timing: junctions you choose (%d)"), n)
		end
		if AllMode.passWanted({ mpass = x.pass }) ~= nil then lines[#lines + 1] = _("Setting smart lanes at all junctions...") end
		return lines
	end

	--- All lights at a selected junction (sl_allmode.lua AllMode.decide, PLAN.md "New lights at once"): a lit junction
	-- that is not enrolled is enrolled at once when the rules allow it (not opted out, not timed by hand, under
	-- Auto.MAX, not the map editor): SmartLanes.auto add src=select (the game script logs op=enroll ... src=select),
	-- applied to the mirror at once so the toggle shows Yes. Otherwise C.allWhy = { node, why = "optout" | "hand" |
	-- "cap" } for the status line (C.retimeLines). Returns the decision (nil: not a lit junction not enrolled).
	function C.allSelect(t)
		C.allWhy = nil
		if t == nil or t.kind ~= "node" or type(t.node) ~= "number" then return nil end
		if not (type(t.can) == "table" and t.can.retime == true) then return nil end
		local mode, n, x = C.allMode()
		if mode ~= "all" or autoEntry(t.node) ~= nil then return nil end
		local p = nodeXY(t.node)
		if p == nil then return nil end
		local okP, all = pcall(function() return api.engine.config.getModParams() end)
		local editor = okP and AllMode.isMapEditor(all)
		local optedOut = Auto.match(Auto.index(type(x.out) == "table" and x.out or nil), t.node, p.x, p.y) ~= nil
		local hand = false
		if not optedOut then
			local okR, r = pcall(W.lightRead, t.node)
			if okR and r ~= nil then
				local um = nil
				pcall(function() um = r.cfg.userModifiedTrafficLightStates end)
				hand = AllMode.handTimedOf(um, AllMode.statesOf(r.tlc.states), #r.conns, #r.cws, Retime.kinds,
					lastEntry(t.node) ~= nil, W.phasesMode() == "sl")
			end
		end
		local why = AllMode.decide(mode, editor, optedOut, hand, n, Auto.MAX)
		if why == "enroll" then
			sendAuto({ op = "add", src = "select", nodes = { { t.node, p.x, p.y } } })
		elseif why ~= "off" then
			C.allWhy = { node = t.node, why = why }
		end
		return why
	end

	--- Why all lights leave the selected junction not adjusted (a translated line), nil when they don't.
	local function allWhyLine(node)
		local w = C.allWhy
		if w == nil or w.node ~= node then return nil end
		if w.why == "optout" then return _("Not adjusted: you turned it off") end
		if w.why == "hand" then return _("Not adjusted: timed by hand") end
		if w.why == "cap" then return string.format(_("Keep timing adjusted: at most %d junctions"), Auto.MAX) end
		return nil
	end

	--- Whether the selected junction is enrolled (the toggle's displayed state: which twin shows).
	function C.autoChecked()
		local s = C.sel
		if s == nil or s.kind ~= "node" then return false end
		return autoEntry(s.node) ~= nil
	end

	--- Run rt's window is over: the measured result (its target out of the sampler run: the drivers ahead at its last
	-- sample kept for the re-route probe), the plan, then the write (or why not).
	local function rtFinish(rt)
		local res = C.retimer.targetResult(rt.tg)
		rt.snap = C.retimer.snapshot(rt.node)
		rt.samples, rt.measuredS = res.samples, res.windowS
		rtRelease(rt)
		local qArm = {}
		for k, v in pairs(res.queue) do
			local a = Retime.approachOf(k)
			qArm[a] = (qArm[a] or 0) + v
		end
		rtLog({ { "op", "measured" }, { "node", rt.node }, { "samples", res.samples }, { "window_s", string.format("%.0f", res.windowS) },
			{ "time", res.timeSrc }, { "src", res.src }, { "cand_max", res.candMax }, { "cand_mean", string.format("%.0f", res.candMean) },
			{ "near_mean", string.format("%.1f", res.nearMean) }, { "far_skipped", res.farSkipped or 0 }, { "reads", res.reads },
			{ "calls", res.calls or 0 }, { "calls_per_sample", string.format("%.0f", res.samples > 0 and (res.calls or 0) / res.samples or 0) },
			{ "frames", res.frames }, { "busy_ms", string.format("%.1f", res.busyMs) }, { "gaps", res.gaps or 0 },
			{ "gap_s", string.format("%.0f", res.gapS or 0) }, { "lost", res.lost }, { "capped", res.capped },
			{ "passes", Retime.mapText(res.passes) }, { "queue", Retime.mapText(res.queue) }, { "q_arm", Retime.mapText(qArm) },
			{ "err", res.err or "-" }, { "running", C.rtCount } })
		-- pedestrian floors: each crosswalk's crossed road (its segment's road and tram lanes)
		local roadLanes = {}
		for _, cw in ipairs(rt.cws) do
			local sg = rt.world.seg(cw)
			if sg ~= nil then
				local k = 0
				for _, l in ipairs(sg.lanes or {}) do
					if l.road or l.tram then k = k + 1 end
				end
				if k > 0 then roadLanes[cw] = k end
			end
		end
		local plan = Retime.plan({ conns = rt.connList, nCross = #rt.cws, states = rt.states, passes = res.passes,
			queue = res.queue, windowS = res.windowS, samples = res.samples, pedNeed = Retime.pedNeed(rt.cws, roadLanes) })
		local old = {}
		for i, st in ipairs(rt.states) do old[i] = st.duration end
		rtLog({ { "op", "plan" }, { "node", rt.node }, { "result", plan.reason }, { "total", plan.total },
			{ "queued", string.format("%.1f", plan.queued) }, { "unmapped", plan.unmapped }, { "always", plan.always },
			{ "kinds", Retime.listText(plan.kinds) }, { "load", Retime.mapText(plan.load or {}) },
			{ "old", Retime.listText(old) }, { "new", Retime.listText(plan.durations or old) },
			{ "cycle", string.format("%.0f>%.0f", plan.oldCycle or 0, plan.cycle or plan.oldCycle or 0) },
			{ "y", string.format("%.2f", plan.y or 0) }, { "lost", string.format("%.0f", plan.lost or 0) },
			{ "sat", string.format("%.0f", plan.sat or 0) }, { "sat_src", plan.satSrc or "-" },
			{ "cycle_reason", plan.cycleReason or "-" }, { "max_delta", plan.maxDelta or 0 } })
		bump()
		if plan.keep or not plan.changed then
			-- the last-measured record (the status shows it when the junction is selected: C.retimeLines); a write's
			-- record follows its callback (rtWrite)
			sendRecord(rt.node, plan.reason == "fits" and "fits" or "small", plan.oldCycle or 0, plan.oldCycle or 0)
			rtDrop(rt)
			if plan.reason == "fits" then
				rtSay(rt.node, string.format(_("Re-time: %s"), _("the phase lengths already fit the traffic")))
			else
				rtSay(rt.node, string.format(_("Re-time: %s"), _("too little traffic measured, phases kept")))
			end
			return
		end
		rt.plan = plan
		rt.phase = "waiting"
		rt.waitFrom = C.frames
		if not rtBusy() then rtWrite(rt) end
	end

	--- The Re-time button: starts measuring the selected junction, or cancels the measurement running there. Up to
	-- Core.RETIME_MAX_RUNNING at once, each at its own junction (one shared sampler run, sl_retimer.lua M.startShared):
	-- a start beyond that is refused (the button is grayed). Returns the result text.
	function C.retime()
		local s = C.sel
		local here = (s ~= nil and s.kind == "node") and C.rts[s.node] or nil
		-- (also at a junction whose timing is kept adjusted: the deliberate 3-minute measurement; the automatic mode
		-- only counts queues now and then, RETIME_PLAN.md "Step B v4", and holds its writes there meanwhile: C.autoBusy)
		if here ~= nil then
			if here.phase == "measuring" then rtCancel(here, "button", _("canceled")) end
			return C.result
		end
		if s == nil or s.kind ~= "node" or type(s.node) ~= "number" then
			setResult(string.format(_("Re-time: %s"), _("select a junction with traffic lights")))
			return C.result
		end
		local node = s.node
		if C.rtCount >= Core.RETIME_MAX_RUNNING then
			rtLog({ { "op", "refuse" }, { "node", node }, { "reason", "full" }, { "running", C.rtCount } })
			setResult(string.format(_("Re-time is measuring %d junctions, the most at once"), C.rtCount))
			return C.result
		end
		if rtBusy() then
			setResult(string.format(_("Re-time: %s"), _("waiting for the last change to land")))
			return C.result
		end
		local rd, why = rtRead(node)
		local world = W.makeWorld()
		local nd = world.node(node)
		if rd == nil or nd == nil then
			rtLog({ { "op", "refuse" }, { "node", node }, { "reason", tostring(why or "gone") } })
			setResult(string.format(_("Re-time: %s"), _("no traffic light here")))
			return C.result
		end
		local run = C.retimer.run
		if run == nil then run = C.retimer.startShared({ everyS = Retimer.EVERY_S }) end
		local tg, whyT = C.retimer.addTarget(node, { nodes = { node }, segs = nd.segs, x = nd.x, y = nd.y, retime = true,
			windowS = Retimer.WINDOW_S })
		if tg == nil then
			rtLog({ { "op", "refuse" }, { "node", node }, { "reason", tostring(whyT) }, { "running", C.rtCount } })
			setResult(_("Could not build the change (see log)"))
			if C.rtCount == 0 then C.retimer.cancel() end
			return C.result
		end
		local rt = { node = node, phase = "measuring", sig = rd.sig, conns = rd.conns, connList = rd.r.conns, cws = rd.r.cws,
			states = rd.states, world = world, startFrame = C.frames, tg = tg, windowS = Retimer.WINDOW_S }
		C.rts[node] = rt
		C.rtList[#C.rtList + 1] = rt
		C.rtCount = C.rtCount + 1
		local old = {}
		for i, st in ipairs(rd.states) do old[i] = st.duration end
		rtLog({ { "op", "start" }, { "node", node }, { "window_s", rt.windowS }, { "every_s", run.everyS }, { "time", run.timeSrc },
			{ "segs", table.concat(nd.segs, ",") }, { "conns", #rd.r.conns }, { "crosswalks", #rd.r.cws }, { "states", #rd.states },
			{ "kinds", Retime.listText(Retime.kinds(#rd.r.conns, #rd.r.cws, rd.states)) }, { "durations", Retime.listText(old) },
			{ "user_modified", tostring(rd.r.cfg.userModifiedTrafficLightStates) }, { "running", C.rtCount } })
		-- the progress is the status's Re-time line (C.retimeLines), not the result line
		C.result = nil
		bump()
		return C.result
	end

	--- One frame of Re-time: the runs, their timers and the re-route checks. Runs from C.step while the tool is open
	-- and from C.bgStep (the background plugin) while it is closed: a measurement goes on whatever is selected and with
	-- the tool closed; the button cancels it, a lane / phase change or the light gone stops it. The measuring runs share
	-- one sampler step (one per-frame budget for all); after a sample each one's junction is re-checked, a run whose
	-- window is over is planned and written.
	function C.retimeStep()
		if C.rtCount > 0 then
			local list = rtRuns()
			local measuring = false
			for _i, rt in ipairs(list) do
				if rt.phase == "measuring" then measuring = true end
			end
			if measuring then
				local st = C.retimer.step()
				if st ~= "measuring" and st ~= "sample" and st ~= "done" then
					-- the sampler stopped (idle) under the measuring runs: they end (logged)
					out("ERROR", { { "where", "retime_sampler" }, { "err", tostring(st) } })
					for _i, rt in ipairs(list) do
						if rt.phase == "measuring" then rtCancel(rt, "sampler", nil) end
					end
				end
				for _i, rt in ipairs(list) do
					if C.rts[rt.node] == rt and rt.phase == "measuring" and rt.tg ~= nil then
						local tg = rt.tg
						local ended = st == "done" and tg.over
						local okRun = true
						if st == "sample" or ended then
							-- the junction as it was: same lanes, same phases (durations too), still lit
							local rd, why = rtRead(rt.node)
							if rd == nil then
								rtCancel(rt, "gone:" .. tostring(why), _("the junction changed, stopped"))
								okRun = false
							elseif rd.sig ~= rt.sig or rd.conns ~= rt.conns then
								rtCancel(rt, rd.conns ~= rt.conns and "changed:lanes" or "changed:phases",
									_("the junction changed, stopped"))
								okRun = false
							end
						end
						if okRun then
							-- the re-route baseline: a snapshot RETIME_BASE_BEFORE s before the end, re-read 5 and 30 s later
							if not rt.baseTaken and rtElapsed(rt) >= rt.windowS - Core.RETIME_BASE_BEFORE then
								rt.baseTaken = true
								scheduleReroute(rt.node, C.retimer.snapshot(rt.node), "base", true)
							end
							if ended then
								rtFinish(rt)
							else
								rtProgress(rt)
							end
						end
					end
				end
			end
			for _i, rt in ipairs(list) do
				if C.rts[rt.node] == rt and rt.phase == "waiting" then
					if not rtBusy() then
						rtWrite(rt)
					elseif C.frames - rt.waitFrom > Core.RETIME_WAIT_FRAMES then
						sendRecord(rt.node, "notwritten", rt.plan.oldCycle or 0, rt.plan.oldCycle or 0)
						rtCancel(rt, "busy", _("stopped, another change is still pending"))
					end
				end
			end
		end
		if #C.rtTimers > 0 then
			local now = C.retimer.now()
			local keep, due = {}, {}
			for _, t in ipairs(C.rtTimers) do
				if (t.at ~= nil and now >= t.at) or (t.frame ~= nil and C.frames >= t.frame) then due[#due + 1] = t
				else keep[#keep + 1] = t end
			end
			C.rtTimers = keep
			for _, t in ipairs(due) do
				local okT, eT = pcall(t.run)
				if not okT then out("ERROR", { { "where", "retime_probe" }, { "err", eT } }) end
			end
		end
		C.retimer.stepChecks()
	end

	--- Re-time work pending (a run, its timers or re-route checks).
	local function rtPending()
		return C.rtCount > 0 or #C.rtTimers > 0 or #C.retimer.checks > 0
	end
	--- C.retimeStep within the "retime" SQPERF section; an error ends the run (logged).
	local function rtTick()
		if not rtPending() then return end
		local tRt = perf:start()
		local okT, eT = pcall(C.retimeStep)
		perf:stop("retime", tRt)
		if not okT then
			out("ERROR", { { "where", "retime" }, { "err", eT } })
			rtDropAll()
		end
	end

	--- One frame of the background plugin (sl_bg.script.lua, a ModEntryPointExtension that is always mounted): while
	-- the tool's own step runs (the tool open) it does nothing; else it counts the frame and runs Re-time
	-- (C.retimeStep) and the traffic recordings (C.recordTick), so a measurement goes on and writes with the tool
	-- closed; with no run, timer, re-route check or recording it returns at once. Logs RETIME op=bg once per run,
	-- TRAFFIC op=bg once per recording.
	function C.bgStep()
		local steps = C.toolSteps
		local toolRunning = C.bgSeenSteps ~= nil and steps ~= C.bgSeenSteps
		C.bgSeenSteps = steps
		if toolRunning then return false end
		if not rtPending() and C.recCount <= 0 then return false end
		C.frames = C.frames + 1
		if C.rtCount > 0 then
			for _i, rt in ipairs(rtRuns()) do
				if not rt.bgLogged then
					rt.bgLogged = true
					rtLog({ { "op", "bg" }, { "node", rt.node }, { "phase", rt.phase }, { "running", C.rtCount } })
				end
			end
		end
		rtTick()
		-- the traffic recording (C.recordTick, defined below)
		if C.recCount > 0 and C.recordTick ~= nil then
			for i, r in ipairs(C.recList) do
				if i > Rec.MAX_RUNNING then break end
				if not r.bgLogged then
					r.bgLogged = true
					out("TRAFFIC", { { "op", "bg" }, { "kind", r.kind }, { "node", r.n }, { "running", C.recCount } })
				end
			end
			C.recordTick()
		end
		return true
	end

	--- "12 min ago" (translated) of a game time.
	local function agoText(t)
		local ago = math.max(0, C.retimer.now() - (t or 0))
		if ago < 60 then return _("just now") end
		if ago < 7200 then return string.format(_("%d min ago"), math.floor(ago / 60)) end
		return string.format(_("%d h ago"), math.floor(ago / 3600))
	end

	--- The last-measured line of node n (both modes read alike, RETIME_PLAN.md "Step B v4"): "Last measured 12 min ago
	-- (manual): cycle 50 -> 75 s" | "... (auto): already fits" | "too little traffic" | "not written (see log)" |
	-- "greens adjusted (cycle 50 s)"; nil without a record.
	function C.lastLine(node)
		local parts = Auto.recordParts(lastEntry(node))
		if parts == nil then return nil end
		local what
		if parts.out == "written" then
			if parts.c0 ~= parts.c1 then what = string.format(_("cycle %d -> %d s"), parts.c0, parts.c1)
			else what = string.format(_("greens adjusted (cycle %d s)"), parts.c1) end
		elseif parts.out == "fits" then what = _("already fits")
		elseif parts.out == "small" then what = _("too little traffic")
		else what = _("not written (see log)") end
		if parts.src == "auto" then return string.format(_("Last measured %s (auto): %s"), agoText(parts.t), what) end
		return string.format(_("Last measured %s (manual): %s"), agoText(parts.t), what)
	end

	--- The status lines of Re-time at a selected junction (at most 2, translated): "Keep timing adjusted" at an enrolled
	-- junction (C.autoLine), then the manual measurement there or the last-measured line. nil: nothing to say.
	function C.retimeLines(node)
		local lines = {}
		local e = autoEntry(node)
		if e ~= nil then
			local okA, al = pcall(C.autoLine, node, e)
			if okA and al ~= nil then lines[#lines + 1] = al end
		else
			local wl = allWhyLine(node)
			if wl ~= nil then lines[#lines + 1] = wl end
		end
		local rt = C.rtCount > 0 and C.rts[node] or nil
		if rt ~= nil then
			if rt.phase == "measuring" and rt.tg ~= nil then
				lines[#lines + 1] = string.format(_("Re-time: measuring traffic (%d of %d s)"), math.floor(rtElapsed(rt)), rt.windowS)
			else
				lines[#lines + 1] = string.format(_("Re-time: %s"), _("waiting for the last change to land"))
			end
		else
			local l = C.lastLine(node)
			if l ~= nil then lines[#lines + 1] = l end
		end
		if #lines == 0 then return nil end
		return lines
	end

	--- "Re-time measuring junctions: 3" (translated) while any run measures or waits to write, else nil: the status
	-- line where the selection is not one of them (nothing selected, another junction, a street).
	function C.retimeCountLine()
		if C.rtCount <= 0 then return nil end
		return string.format(_("Re-time measuring junctions: %d"), C.rtCount)
	end

	--- The "Keep timing adjusted" line of an enrolled node (saved entry e): paused while Automatic light timing is
	-- Off, else its snapshots so far, or when it is decided next (the runtime of this Lua state); without it (another
	-- Lua state) the plain enrolled state.
	function C.autoLine(node, e)
		if C.allMode() == "off" then return _("Keep timing adjusted: paused while Automatic light timing is Off") end
		local art = autoRuntime()
		local st = nil
		if art ~= nil then
			local ok, v = pcall(art.statusOf, node, e[2], e[3])
			if ok then st = v end
		end
		if st == nil then return _("Timing kept adjusted at this junction") end
		if not st.active or (st.snaps or 0) < (st.need or 0) or st.due == nil then
			return string.format(_("Keep timing adjusted: counting waiting cars (%d of %d)"),
				math.min(st.snaps or 0, st.need or 0), st.need or 0)
		end
		local nextMin = math.max(0, math.ceil((st.due - C.retimer.now()) / 60))
		return string.format(_("Keep timing adjusted: next check in %d min"), nextMin)
	end

	---------------------------------------------------------------------------
	-- Record traffic (the toolbar's Record traffic button, PLAN.md "Traffic rate at a junction"; sl_record.lua): counts
	-- the vehicles passing the selected junction (a node target: every movement through it, as Re-time counts) or
	-- entering the selected roundabout (a ring target: passes at its junctions whose approach is not a ring segment)
	-- with a second instance of Re-time's sampler (C.recorder: the same reads and its cheaper sampling, a sample every
	-- Rec.EVERY_S game s within Rec.BUDGET_S per frame), into 30 s buckets, for up to Rec.MAX_S game s. Never changes the
	-- lights or lanes. Up to Rec.MAX_RUNNING recordings at once (2026-10-16), all in one shared sampler run (sl_retimer.lua
	-- M.startShared: one pass over every recording's candidates, the same Rec.BUDGET_S per frame for all; with many the
	-- samples come later instead of costing more frame time). Each goes on whatever is selected and with the tool closed
	-- (C.bgStep), the button at its junction stops it, the junction gone ends it. Its result (and a checkpoint every Rec.CHECKPOINT_S)
	-- is saved as the junction's last recording (SmartLanes.auto op=traffic: trec), shown when it is selected later. A
	-- Re-time run at the same junction keeps its own sampler (another interval, window and end; Keep timing adjusted
	-- counts no passes). Logs TRAFFIC op=start|checkpoint|bg|done|refuse (PLAN.md "Logging").
	C.recorder = Retimer.new(api, clock, function() if C.retimeNow then return C.retimeNow() end return nil end,
		{ perf = perf, perfName = "record_gather" })
	-- the running recordings by key ("node:<id>" | "ring:<ring key>"), each { key, kind = "node" | "ring", n (node id |
	-- ring key), x, y, nodes, ringSegs, buckets, seen, lastAt (game s of its last counted sample), checkI, nextCheckpoint,
	-- prev (the saved result there when it started, { t, d, v } | nil: kept in its record, shown muted to compare), tg
	-- (its sampler target: t0, counted, passes, samples) }; C.recList in start order; in memory only (a save keeps the
	-- checkpoints and results, never a running recording)
	C.recs, C.recList, C.recCount = {}, {}, 0

	-- the mirror of the saved recordings (tseq / trec), as C.lastm
	C.tmirror = { seq = nil, list = nil, idx = Rec.index(nil), frame = nil, read = false }
	local function refreshTraffic(force)
		local a = C.tmirror
		if not force and a.frame ~= nil and C.frames - a.frame < Core.AUTO_MIRROR_FRAMES and C.frames >= a.frame then return end
		a.frame = C.frames
		local seq, list = Auto.readTraffic(api, a.read and a.seq or nil)
		if list ~= nil and (not a.read or seq ~= a.seq) then
			a.read = true
			a.seq, a.list = seq, list
			a.idx = Rec.index(list)
		end
	end
	C.refreshTraffic = refreshTraffic

	--- What a selection records: { kind, n, x, y, nodes, segs, candEnts, ringSegs (set), radius } for a junction (node
	-- target) or a roundabout (ring target: its junctions, the arm segments as candidates, the center and a radius
	-- reaching 200 m beyond its farthest junction), else nil. Bounded: at most 32 junctions read.
	local function recTargetOf(s)
		if s == nil then return nil end
		local world = W.makeWorld()
		if s.kind == "node" and type(s.node) == "number" then
			local nd = world.node(s.node)
			-- a junction: 3 roads or more (a bend, joint or lane drop of one road is none: no Record traffic there)
			if nd == nil or #nd.segs < 3 then return nil end
			return { kind = "node", n = s.node, x = nd.x, y = nd.y, nodes = { s.node }, segs = nd.segs }
		end
		if s.kind ~= "ring" or s.ring == nil or type(s.ringKey) ~= "number" then return nil end
		local ringSegs = {}
		for _, sg in ipairs(s.ring.segs or {}) do ringSegs[sg] = true end
		local nodes, pos, cand, seen = {}, {}, {}, {}
		local sx, sy = 0, 0
		for i, n in ipairs(s.junctionNodes or {}) do
			if i > 32 then break end
			local nd = world.node(n)
			if nd ~= nil then
				nodes[#nodes + 1] = n
				pos[#pos + 1] = nd
				sx, sy = sx + nd.x, sy + nd.y
				for _, sg in ipairs(nd.segs) do
					if not ringSegs[sg] and not seen[sg] then
						seen[sg] = true
						cand[#cand + 1] = sg
					end
				end
			end
		end
		if #nodes == 0 then return nil end
		local cx, cy = sx / #nodes, sy / #nodes
		local far = 0
		for _, nd in ipairs(pos) do far = math.max(far, math.sqrt((nd.x - cx) ^ 2 + (nd.y - cy) ^ 2)) end
		return { kind = "ring", n = s.ringKey, x = cx, y = cy, nodes = nodes, segs = cand, candEnts = cand,
			ringSegs = ringSegs, radius = Retimer.RADIUS + far }
	end
	C.recTargetOf = recTargetOf

	--- Whether Record traffic is offered for selection s: a roundabout, or a node where 3 roads or more meet (a real
	-- junction, a roundabout junction included); never a bend, joint or lane drop of one road ("no junction here").
	-- Cheap (the selection's road count, no world read): the toolbar asks every step.
	local function recordable(s)
		if s == nil then return false end
		if s.kind == "ring" then return true end
		return s.kind == "node" and (s.roads or 0) >= 3
	end
	C.recordable = recordable

	--- The key of selection s's recording: "node:<id>" | "ring:<ring key>", nil when it records nothing.
	local function recKey(s)
		if s == nil then return nil end
		if s.kind == "node" and type(s.node) == "number" then return "node:" .. s.node end
		if s.kind == "ring" and type(s.ringKey) == "number" then return "ring:" .. s.ringKey end
		return nil
	end

	--- The running recording at selection s, nil: none there.
	local function recOf(s)
		local k = recKey(s)
		if k == nil then return nil end
		return C.recs[k]
	end
	C.recOf = recOf

	--- Whether selection s is the target of recording r (default: any running recording there).
	local function recAt(s, r)
		if s == nil then return false end
		if r == nil then return recOf(s) ~= nil end
		if r.kind == "node" then return s.kind == "node" and s.node == r.n end
		return s.kind == "ring" and s.ringKey == r.n
	end
	C.recAt = recAt

	--- A TRAFFIC line (at most Core.RETIME_LINES_MAX per session, counted with RETIME's).
	local function trLog(fields)
		if C.rtLines >= Core.RETIME_LINES_MAX then return end
		C.rtLines = C.rtLines + 1
		if C.rtLines == Core.RETIME_LINES_MAX then fields[#fields + 1] = { "more", "suppressed" } end
		out("TRAFFIC", fields)
	end

	--- Recording r's result (Rec.result at its last counted sample: the counts' time) and the game s elapsed now.
	local function recResult(r)
		local tg = r.tg
		if tg == nil then return Rec.result(r.buckets, 0), 0 end
		local el = math.max(0, math.min(Rec.MAX_S, C.recorder.now() - tg.t0))
		return Rec.result(r.buckets, r.lastAt or 0), el
	end

	--- The counted vehicles per approach (a roundabout: per entry segment) of a recording's passes, for the log.
	local function armCounts(r, passes)
		local arms, k = {}, 0
		for key, v in pairs(passes or {}) do
			k = k + 1
			if k > 512 then break end
			local mv = tostring(key):match("@(.+)$") or tostring(key)
			local a = Retime.approachOf(mv)
			if r.kind == "node" or (a ~= nil and not r.ringSegs[a]) then
				local ak = a ~= nil and a or "nil"
				arms[ak] = (arms[ak] or 0) + v
			end
		end
		return arms
	end

	--- Saves a result as the junction's last recording (the mirror at once). Returns whether a record was sent.
	local function recSave(r, res)
		local rec = Rec.record(r.kind, r.n, r.x, r.y, C.recorder.now(), res, r.prev)
		if rec == nil then return false end
		refreshTraffic(false)
		local a = C.tmirror
		local list, st = Rec.apply(a.idx.list, { rec })
		a.list, a.idx = list, Rec.index(list)
		sendAuto({ op = "traffic", src = "tool", nodes = { rec } })
		-- the game script bumps tseq by one for this change (handleAuto op=traffic, the same Rec.apply; none saved yet: 1):
		-- expected here, so
		-- the next refresh does not convert the whole saved list again for our own save (user 2026-10-17: ~7 ms
		-- checkpoint frames). A seq that differs (another change, or the event lost) is read in full as before.
		if a.read and st.changed and (a.seq == nil or type(a.seq) == "number") then a.seq = (a.seq or 0) + 1 end
		return true
	end

	--- Ends recording r: reason button | max | gone | error; its result saved when at least Rec.MIN_SAVE_S game s were
	-- recorded; the result text only while its target is selected. The last one ends the shared sampler run.
	local function recFinish(r, reason)
		if r == nil or C.recs[r.key] ~= r then return end
		local running = C.recCount
		C.recs[r.key] = nil
		C.recCount = C.recCount - 1
		for i, x in ipairs(C.recList) do
			if x == r then
				table.remove(C.recList, i)
				break
			end
		end
		local res, el = recResult(r)
		if reason == "max" then el = Rec.MAX_S end
		local saved = el >= Rec.MIN_SAVE_S and recSave(r, res)
		local m = (r.tg ~= nil and C.recorder.targetResult(r.tg)) or {}
		C.recorder.removeTarget(r.key)
		if C.recCount <= 0 then
			C.recCount = 0
			C.recorder.cancel()
		end
		local samples = m.samples or 0
		trLog({ { "op", "done" }, { "kind", r.kind }, { "node", r.n }, { "reason", reason }, { "elapsed_s", string.format("%.0f", el) },
			{ "samples", samples }, { "vehicles", res.v }, { "rate_all", Rec.rateText(Rec.rate(res.v, res.d)) },
			{ "rate_recent", Rec.rateText(Rec.rate(res.v3, res.d3)) }, { "recent_s", string.format("%.0f", res.d3) },
			{ "saved", saved and 1 or 0 }, { "src", m.src or "-" }, { "cand_mean", string.format("%.0f", m.candMean or 0) },
			{ "near_mean", string.format("%.1f", m.nearMean or 0) }, { "far_skipped", m.farSkipped or 0 }, { "reads", m.reads or 0 },
			{ "calls", m.calls or 0 }, { "calls_per_sample", string.format("%.0f", samples > 0 and (m.calls or 0) / samples or 0) },
			{ "frames", m.frames or 0 }, { "busy_ms", string.format("%.1f", m.busyMs or 0) },
			{ "ms_per_sample", string.format("%.2f", samples > 0 and (m.busyMs or 0) / samples or 0) },
			{ "gaps", m.gaps or 0 }, { "gap_s", string.format("%.0f", m.gapS or 0) }, { "lost", m.lost or 0 },
			{ "capped", m.capped or 0 }, { "arm", Retime.mapText(armCounts(r, m.passes)) }, { "err", m.err or "-" },
			{ "running", running }, { "every_max_s", string.format("%.0f", m.everyMax or 0) }, { "late", m.late or 0 } })
		if recAt(C.sel, r) then
			if reason == "gone" then setResult(_("Traffic recording stopped: the junction is gone"))
			elseif not saved then setResult(_("Traffic recording: too short to save (under 30 s)"))
			elseif reason == "max" then setResult(_("Traffic recording finished"))
			else setResult(_("Traffic recording stopped")) end
		end
		bump()
	end

	--- Ends every running recording (the sampler stopped, an error).
	local function recFinishAll(reason)
		local list = {}
		for i, r in ipairs(C.recList) do
			if i > Rec.MAX_RUNNING then break end
			list[#list + 1] = r
		end
		for _, r in ipairs(list) do pcall(recFinish, r, reason) end
		C.recs, C.recList, C.recCount = {}, {}, 0
		C.recorder.cancel()
	end

	--- The Record traffic button: starts recording the selected junction or roundabout, or stops the recording there.
	-- Up to Rec.MAX_RUNNING at once, each at its own junction (one shared sampler run, sl_retimer.lua M.startShared):
	-- a start beyond that is refused (the button is grayed). Returns the result text.
	function C.record()
		local s = C.sel
		local cur = recOf(s)
		if cur ~= nil then
			recFinish(cur, "button")
			return C.result
		end
		local tg = recTargetOf(s)
		if tg == nil then
			setResult(_("Select a junction or a roundabout to record its traffic"))
			return C.result
		end
		if C.recCount >= Rec.MAX_RUNNING then
			trLog({ { "op", "refuse" }, { "node", tg.n }, { "reason", "full" }, { "running", C.recCount } })
			setResult(string.format(_("%d recordings running, the most at once"), C.recCount))
			return C.result
		end
		local key = recKey(s)
		local t = { nodes = tg.nodes, segs = tg.segs, candEnts = tg.candEnts, x = tg.x, y = tg.y, radius = tg.radius }
		if tg.kind == "ring" then
			local rs = tg.ringSegs
			t.countFn = function(_n, inS, _outS) return inS ~= nil and not rs[inS] end
		end
		-- the saved result there (fresh read): kept as the new record's previous, shown muted while it records
		refreshTraffic(true)
		local prev = Rec.prevOf(C.savedRecordAt(s))
		local run = C.recorder.run
		if run == nil or not run.shared then
			C.recorder.cancel()
			run = C.recorder.startShared({ everyS = Rec.EVERY_S, budgetS = Rec.BUDGET_S })
		end
		local target, why = C.recorder.addTarget(key, t)
		if target == nil then
			trLog({ { "op", "refuse" }, { "node", tg.n }, { "reason", tostring(why) }, { "running", C.recCount } })
			setResult(_("Could not build the change (see log)"))
			if C.recCount == 0 then C.recorder.cancel() end
			return C.result
		end
		local r = { key = key, kind = tg.kind, n = tg.n, x = tg.x, y = tg.y, nodes = tg.nodes, ringSegs = tg.ringSegs or {},
			buckets = Rec.newBuckets(), seen = 0, lastAt = 0, checkI = 0, nextCheckpoint = Rec.CHECKPOINT_S, prev = prev,
			tg = target }
		C.recs[key] = r
		C.recList[#C.recList + 1] = r
		C.recCount = C.recCount + 1
		local cand = table.concat(tg.candEnts or {}, ",")
		trLog({ { "op", "start" }, { "kind", tg.kind }, { "node", tg.n }, { "nodes", table.concat(tg.nodes, ",") },
			{ "cand_ents", cand ~= "" and cand or "node+segs" },
			{ "radius", string.format("%.0f", tg.radius or Retimer.RADIUS) }, { "every_s", run.everyS }, { "window_s", Rec.MAX_S },
			{ "bucket_s", Rec.BUCKET_S }, { "time", run.timeSrc }, { "pos", Auto.posKey(tg.x, tg.y) }, { "running", C.recCount } })
		-- the progress is the status's recording lines (C.recordLines), not the result line
		C.result = nil
		bump()
		return C.result
	end

	--- One frame of the recordings (C.step while the tool is open, C.bgStep while it is closed): the shared sampler (one
	-- pass for all, within Rec.BUDGET_S), each recording's new passes into its bucket after a sample it took part in
	-- (a sample at or after its Rec.MAX_S end not counted), its junction still there (at most Rec.EXIST_MAX reads per
	-- sample, round robin), its checkpoint, its end at Rec.MAX_S.
	function C.recordStep()
		if C.recCount <= 0 then return end
		local st = C.recorder.step()
		local run = C.recorder.run
		if (st ~= "measuring" and st ~= "sample") or run == nil then
			-- the sampler stopped (idle): end the recordings with what they have
			recFinishAll("error")
			return
		end
		local list = {}
		for i, r in ipairs(C.recList) do
			if i > Rec.MAX_RUNNING then break end
			list[#list + 1] = r
		end
		if st == "sample" then
			local per = math.max(1, math.floor(Rec.EXIST_MAX / math.max(1, #list)))
			for _, r in ipairs(list) do
				local tg = r.tg
				if tg.lastSampleAt ~= nil and tg.lastSampleAt == run.lastSampleAt then
					local d = (tg.counted or 0) - r.seen
					r.seen = tg.counted or 0
					local at = tg.lastSampleAt - tg.t0
					if at < Rec.MAX_S then
						if d > 0 then Rec.add(r.buckets, math.max(0, at), d) end
						r.lastAt = math.max(0, at)
					end
				end
				local nn = #r.nodes
				for _ = 1, math.min(per, nn) do
					r.checkI = r.checkI % nn + 1
					local okX, ex = pcall(api.engine.entityExists, r.nodes[r.checkI])
					if okX and ex == false then
						recFinish(r, "gone")
						break
					end
				end
			end
		end
		local now = C.recorder.now()
		for _, r in ipairs(list) do
			if C.recs[r.key] == r then
				local el = now - r.tg.t0
				if el >= Rec.MAX_S and r.tg.samples > 0 then
					recFinish(r, "max")
				elseif el >= r.nextCheckpoint then
					r.nextCheckpoint = r.nextCheckpoint + Rec.CHECKPOINT_S
					local res = Rec.result(r.buckets, r.lastAt or 0)
					local saved = recSave(r, res)
					trLog({ { "op", "checkpoint" }, { "kind", r.kind }, { "node", r.n }, { "elapsed_s", string.format("%.0f", el) },
						{ "vehicles", res.v }, { "rate_all", Rec.rateText(Rec.rate(res.v, res.d)) }, { "saved", saved and 1 or 0 },
						{ "running", C.recCount } })
				end
			end
		end
	end

	--- C.recordStep within the "record" SQPERF section; an error ends the recordings (logged, saved when long enough).
	function C.recordTick()
		if C.recCount <= 0 then return end
		local t = perf:start()
		local okT, eT = pcall(C.recordStep)
		perf:stop("record", t)
		if not okT then
			out("ERROR", { { "where", "record" }, { "err", eT } })
			recFinishAll("error")
		end
	end

	--- "Traffic recordings running: 3" (translated) while any runs, else nil: the status line where the selection is
	-- not one of them (nothing selected, another junction, a street).
	function C.recordCountLine()
		if C.recCount <= 0 then return nil end
		return string.format(_("Traffic recordings running: %d"), C.recCount)
	end

	--- The status lines of the recording at selection s (a junction or a roundabout; translated): while it records
	-- there "Recording traffic: 7 of 20 min" and the rates; else its saved last recording ("Traffic recorded 12 min ago
	-- (20 min)" and the rates); nil: nothing. Below them the recording before ("Previous recording: ...", Rec.prevLine)
	-- when there is one: while it records the saved result it started from, else the one the saved record replaced.
	-- Second value: the indices of the lines to show muted (the previous one), nil: none.
	function C.recordLines(s)
		if s == nil or (s.kind ~= "node" and s.kind ~= "ring") then return nil end
		local lines, prev, kind
		local r = recOf(s)
		if r ~= nil then
			local res, el = recResult(r)
			lines = { Rec.runningLine(el) }
			local rl = Rec.ratesLine(r.kind, res)
			if rl ~= nil then lines[#lines + 1] = rl end
			prev, kind = r.prev, r.kind
		else
			local e = C.savedRecordAt(s)
			if e == nil then return nil end
			lines = Rec.savedLines(e, agoText(e[4]))
			if lines == nil then return nil end
			local p = Rec.parts(e)
			prev, kind = p and p.prev, p and p.kind
		end
		local pl = prev ~= nil and Rec.prevLine(kind, prev, agoText(prev.t)) or nil
		if pl == nil then return lines, nil end
		lines[#lines + 1] = pl
		return lines, { #lines }
	end

	--- The saved record (Rec) of selection s (a junction or a roundabout): by id, else by position (a junction
	-- re-created under another id); nil: none.
	function C.savedRecordAt(s)
		if s == nil or (s.kind ~= "node" and s.kind ~= "ring") then return nil end
		refreshTraffic(false)
		local idx = C.tmirror.idx
		if (idx.n or 0) == 0 then return nil end
		local kind = s.kind == "ring" and "ring" or "node"
		local n = kind == "ring" and s.ringKey or s.node
		local e = Rec.match(idx, kind, n, nil, nil)
		if e == nil then
			-- by position (a junction re-created under another id): the node's, or the roundabout's center
			local x, y
			if kind == "node" then
				local p = nodeXY(n)
				x, y = p and p.x, p and p.y
			else
				if s.recXY == nil then
					local tg = recTargetOf(s)
					s.recXY = tg and { tg.x, tg.y } or false
				end
				if s.recXY then x, y = s.recXY[1], s.recXY[2] end
			end
			e = Rec.match(idx, kind, n, x, y)
		end
		return e
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
				-- crossroads: the game-default model, tram and bus-lane connections kept; lights stay
				-- (Lights.keepsLights), the kerb turns locked again in the phases
				conns, lights, phase = Rules.mergeTram(model, cur, v.bus), false, phaseFor(v, "game")
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
				-- the lanes as before the Apply, the bus-lane connections as they are now (Rules.keepBus)
				conns, lights = Rules.keepBus(snap, cur, v.bus), not Lights.keepsLights(v.case, v.bus)
				out("RESET", join({ { "mode", "snapshot" } }, tag, { { "node", n }, { "conns", #conns } }))
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
			setResult(_("Reset not available here (no smart lanes set yet)"))
		else
			setResult(_("Not handled: no rule for this junction"))
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
		local plan = Rules.planRing(world, ring, seeds, job.layout == "game" and "engine" or (ringVariantOf(ring) or "turbo"), W.currentConns)
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
		if s.ring == nil then return nil, _("Not handled: no rule for this junction") end
		local start = s.kind == "node" and s.node or s.ring.nodes[1]
		local ring = Ring.ringThrough(world, start)
		if ring == nil then return nil, _("The roundabout changed; select it again") end
		return ring
	end

	--- Apply the layout to the selected junction (scope "node") or its whole ring (scope "ring").
	-- layout: "matched" | "turbo" | "game" (game = Reset). Returns the result text.
	--- The tool's one Apply button: the whole roundabout when the roundabout itself is selected (clicked
	-- between its junctions), else the selected junction, street or Shift+click junctions.
	function C.applySelection(layout)
		local s = C.sel
		return C.apply((s ~= nil and s.kind == "ring") and "ring" or "node", layout)
	end

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
				setResult(_("Not a roundabout"))
				return C.result
			end
			if layout ~= "game" then markKept("remove", coveredNodes(s, scope)) end
			return C.applyStreet(layout == "game" and "game" or "turbo")
		end
		if scope == "node" and s ~= nil and s.kind ~= "node" then
			setResult(_("Click near a junction to pick it"))
			return C.result
		end
		-- Apply clears the kept marks of what it covers (sl_kept.lua); Reset (layout "game") set them in C.reset
		if layout ~= "game" then markKept("remove", coveredNodes(s, scope)) end
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
		-- a ring layout variant zone: its variant instead of the tool's layout (logged as layout=<variant>)
		if layout ~= "game" then layout = ringVariantOf(ring) or layout end
		local plan = Rules.planRing(world, ring, seeds, layout == "game" and "engine" or layout, W.currentConns)
		-- the default spiral on a ring without mid nodes (its plain nodes joined away at a menu placement): Apply to the
		-- roundabout splits its stretches first (sl_split, W.sendSplit, as the automatic pass), then applies again a
		-- few frames after the split answered (C.step: C.reapply), with the new nodes; once per Apply (noSplit then)
		-- (also the ring of an sl_rmid2 zone: Rules.SPLIT_VARIANTS, plan.splitWanted)
		if scope == "ring" and plan.splitWanted and not C.noSplit then
			local views = {}
			for _, rn in ipairs(ring.nodes) do views[rn] = Ring.nodeView(world, ring, rn) end
			local list, why = Split.edges(world, ring, views)
			if list ~= nil then
				local key = ring.key
				C.quietUntil = C.frames + Core.CALLBACK_TIMEOUT
				local okS, nS, whyS = pcall(W.sendSplit, list, function(success)
					C.quietUntil = 0
					out("WRITE", { { "src", "tool" }, { "kind", "split" }, { "ring", key }, { "success", success } })
					C.reapply = { due = C.frames + 5, layout = layout }
				end)
				if okS and (nS or 0) > 0 then
					local ids = {}
					for _, it in ipairs(list) do ids[#ids + 1] = tostring(it.seg) end
					out("SPLIT", { { "src", "tool" }, { "ring", key }, { "node", key }, { "len", math.floor((ring.length or 0) + 0.5) },
						{ "edges", table.concat(ids, ",") }, { "nodes_added", nS } })
					return C.result
				end
				C.quietUntil = 0
				why = okS and (whyS or "not_sent") or ("error:" .. tostring(nS))
			end
			out("SPLIT", { { "src", "tool" }, { "ring", ring.key }, { "node", ring.key }, { "len", math.floor((ring.length or 0) + 0.5) },
				{ "refused", why } })
		end
		local items, same, skipped = {}, 0, 0
		for _, r in ipairs(plan.nodes) do
			if r.status == "apply" then
				local v = r.view
				out("APPLY", Rules.withEntry({ { "src", "tool" }, { "layout", layout }, { "ring", ring.key }, { "node", r.node }, { "lanes", ring.lanes },
					{ "dir", ring.side == 1 and "ccw" or "cw" }, { "exits", #v.x }, { "entries", #v.e },
					{ "turbo", plan.turbo }, { "turbo_reason", plan.turboReason or "-" }, { "before", r.before }, { "after", r.after } }, r))
				items[#items + 1] = { node = r.node, conns = r.conns, mid = r.mid }
			elseif r.status == "same" then
				same = same + 1
			elseif r.status == "skip" then
				skipped = skipped + 1
				out("SKIP", { { "src", "tool" }, { "ring", ring.key }, { "node", r.node }, { "reason", r.reason } })
			end
		end
		local name = layoutText(layout)
		-- turboReason is an internal id (sl_rules), shown as a phrase
		-- (the default spiral on a 2-lane ring with one-lane exits has its exit-only outer lane: no reason shown)
		local why = (layout == "turbo" and not plan.turbo and not plan.default) and Pick.exitOnlyText(plan.turboReason) or nil
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
				setResult(_("Not handled: no rule for this junction"))
			elseif why ~= nil then
				setResult(string.format(_("%s already set; no exit-only outer lane: %s"), name, why))
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
				-- junctions only (a mid node's write is part of the roundabout's, not a junction)
				local nJ = 0
				for _, it in ipairs(items) do
					if not it.mid then nJ = nJ + 1 end
				end
				if nJ == 0 then nJ = #items end
				if why ~= nil then
					fmt = nJ == 1 and _("%s applied to %d junction; no exit-only outer lane: %s")
						or _("%s applied to %d junctions; no exit-only outer lane: %s")
				else
					fmt = nJ == 1 and _("%s applied to %d junction") or _("%s applied to %d junctions")
				end
				setResult(string.format(fmt, name, nJ, why))
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
		-- the junctions stay the game's when a build next to them comes (sl_kept.lua); Apply clears it
		markKept("add", coveredNodes(s, scope))
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
		C.toolSteps = C.toolSteps + 1
		-- the Apply after a split of the selected ring (C.apply): the ring with its new nodes, without splitting again
		if C.reapply ~= nil and C.frames >= C.reapply.due and C.job == nil then
			local r = C.reapply
			C.reapply = nil
			C.noSplit = true
			pcall(C.apply, "ring", r.layout)
			C.noSplit = false
		end
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
		-- Re-time: measuring, waiting to write, the probe after the write (C.retimeStep; C.bgStep while the tool is closed)
		rtTick()
		-- Record traffic (C.recordTick; C.bgStep while the tool is closed)
		C.recordTick()
		-- Keep timing adjusted and Record traffic: the selected junction's lines (measuring progress, last / next check,
		-- the recording's minutes and rates) change with the game clock and the runtime, not with the selection:
		-- re-rendered when their text changed (every 30 frames)
		if C.sel ~= nil and (C.sel.kind == "node" or C.sel.kind == "ring") and C.frames % Core.AUTO_MIRROR_FRAMES == 0 then
			local text = ""
			if C.sel.kind == "node" then
				local okL, lines = pcall(C.retimeLines, C.sel.node)
				text = (okL and type(lines) == "table") and table.concat(lines, "\n") or ""
			end
			local okR, rl = pcall(C.recordLines, C.sel)
			if okR and type(rl) == "table" then text = text .. "\n" .. table.concat(rl, "\n") end
			if text ~= (C.autoSeen or "") then
				C.autoSeen = text
				bump()
			end
		end
	end

	--- The tool closes: forget the selection and pending re-reads (writes already sent still land). A Re-time run goes
	-- on (C.bgStep), so do its probe timers.
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
		-- the selected ring's plain nodes with lane changes (the mid nodes): their connections as curves (sl_midview),
		-- as the NodeViewer can't draw them; none while a write of ours is pending (the network is being rebuilt)
		local lines = {}
		local ring = C.sel and C.sel.ring
		if ring ~= nil and not nvHeld() then
			for _, n in ipairs(ring.nodes or {}) do
				local node = world.node(n)
				local conns = node and #node.segs == 2 and connsIn(world, n) or nil
				if conns ~= nil and Rules.roadCount(conns) > (ring.lanes or 0) then
					for _, cv in ipairs(MidView.curves(world, n, conns)) do
						cv.z = node.z or 0
						lines[#lines + 1] = cv
					end
				end
				if #lines >= MidView.MAX_CURVES then break end
			end
		end
		perf:stop("highlight", tHi)
		return ents, markers, lines
	end

	--- Smart lights has something to do at the selection: a lit crossroads / T-junction (not a ring junction) whose
	-- axis plan can be made (C.lightsStatus ok) and whose phases are not that plan yet (nor the plan re-timed by Smart
	-- Lanes; the player's hand timing offers it again). Elsewhere the button is hidden: no axis plan (user 2026-10-16,
	-- PLAN.md "No classic fallback": the game's phases stay; the detail line says why, Pick.lightsText), or the plan
	-- is on (user 2026-10-16: "after applying smart lights the button should hide instead of disable"; the badge
	-- says "√ Smart lights", Pick.badgeChecks).
	local function lightsOffered(t)
		local ls = t ~= nil and t.kind == "node" and t.ring == nil and t.lights or nil
		return type(ls) == "table" and ls.ok == true and not ls.same and not ls.timed
	end
	C.lightsOffered = lightsOffered

	--- The toolbar's Smart lanes button (C.applySelection; the rev 8 "Lights only" checkbox mode is gone: Smart lights
	-- is its own button, C.lightsOnly).
	function C.applyAction(layout)
		return C.applySelection(layout)
	end

	--- The toolbar now (rev 8; user 2026-10-14 "back to buttons, two rows only when relevant", 2026-10-16 "hide what
	-- has nothing to do"): per button (apply, reset, lights, retime, auto, record) { show, can (a click would change
	-- something), enabled (may be clicked now), why (translated reason it is grayed, nil when enabled), tip
	-- (translated: what a click does here, or nil) }.
	-- Row 1: Smart lanes (apply) and Reset, each shown only when a click would change something (hidden where Smart
	-- Lanes has no rule, nothing to change or nothing to reset: the lane status and the detail line say which); with
	-- both hidden the row is gone. Grayed with the reason only while a change is landing. Row 2 (Smart lights,
	-- Re-time) only at a selected junction with a standing traffic light (or one Re-time measures), its buttons
	-- grayed with their reason when they can't act (Re-time: while Core.RETIME_MAX_RUNNING measure elsewhere). Record
	-- traffic: at a real junction (3 roads or more) or a roundabout, grayed while Rec.MAX_RUNNING record elsewhere.
	-- Depends on the selection, the Re-time runs, the recordings and pending writes, never on the hover. Cheap: the construction menu asks every step (checkEnabledFn).
	function C.buttons()
		local s = C.sel
		local B = {
			apply = { show = false }, reset = { show = false }, lights = { show = false }, retime = { show = false },
			auto = { show = false }, record = { show = false },
		}
		-- nothing selected: no button row (the settings panel shows instead, sl_settingsui.lua)
		if s == nil then return B end
		local busy = C.job ~= nil or next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0) or C.frames < (C.phaseHold or 0)
		local landing = _("A write is still landing")
		local can = s.can or {}
		local rt = (C.rtCount > 0 and s.kind == "node") and C.rts[s.node] or nil
		local rtHere = rt ~= nil
		-- row 1: hidden where a click would change nothing; grayed only while a change lands
		local applyCan = ((s.kind == "ring") and can.applyRing or can.applyNode) == true
		B.apply = { show = applyCan, can = applyCan, enabled = applyCan and not busy, why = busy and landing or nil }
		local resetCan = can.reset == true or can.resetPhases == true
		local resetTip = nil
		if can.resetPhases == true then
			resetTip = can.reset == true and _("Reset lanes and light phases to the game default")
				or _("Reset the light phases to the game default")
		end
		B.reset = { show = resetCan, can = resetCan, enabled = resetCan and not busy, why = busy and landing or nil,
			tip = resetTip }
		-- the last row: Record traffic at a real junction or a roundabout (never writes: not held by a pending write);
		-- the running recording's own target always shows it (the click stops it)
		if recAt(s) then
			B.record = { show = true, can = true, enabled = true, tip = _("Recording here: click to stop") }
		elseif recordable(s) then
			if C.recCount >= Rec.MAX_RUNNING then
				B.record = { show = true, can = false, enabled = false,
					why = string.format(_("%d recordings running, the most at once"), C.recCount) }
			else
				B.record = { show = true, can = true, enabled = true }
			end
		end
		-- row 2: a lit junction
		local lit = s.kind == "node" and (can.retime == true or rtHere)
		if not lit then return B end
		-- Smart lights: hidden where no axis plan can be made (lightsOffered; the detail line says why)
		if lightsOffered(s) then
			local lightsWhy = nil
			local lightsCan = can.lights == true
			if rtHere then lightsWhy = _("Re-time is measuring here")
			elseif busy then lightsWhy = landing end
			B.lights = { show = true, can = lightsCan, enabled = lightsCan and not busy and not rtHere, why = lightsWhy }
		end
		local rtB
		local enrolled = autoEntry(s.node) ~= nil
		if rtHere and rt.phase == "measuring" then
			rtB = { show = true, can = true, enabled = true, tip = _("Measuring: click to cancel") }
		elseif rtHere then
			rtB = { show = true, can = false, enabled = false, why = _("Waiting for the last change to land") }
		elseif C.rtCount >= Core.RETIME_MAX_RUNNING then
			rtB = { show = true, can = false, enabled = false,
				why = string.format(_("Re-time is measuring %d junctions, the most at once"), C.rtCount) }
		else
			local c = can.retime == true
			rtB = { show = true, can = c, enabled = c and not busy, why = (c and busy) and landing or nil }
		end
		B.retime = rtB
		-- row 3: "Keep timing adjusted" (a Yes / No toggle: this junction's on / off state, never a menu mode), shown
		-- with the light row, its displayed value the selected junction's enrolled state (sl_tool.script.lua twins)
		B.auto = { show = true, can = true, enabled = true, checked = enrolled }
		return B
	end

	--- Toolbar state as booleans: { apply, applyNode, applyRing, reset, lights, retime (may be clicked now), show =
	-- { apply, reset, lights, retime } (drawn at all), none (a selection where no button can act: the status detail
	-- says so, sl_pick P.status) } (C.buttons).
	function C.actions()
		local s = C.sel
		local B = C.buttons()
		local busy = C.job ~= nil or next(C.verifies) ~= nil or C.frames < (C.quietUntil or 0) or C.frames < (C.phaseHold or 0)
		local can = (s ~= nil and s.can) or {}
		return { apply = B.apply.enabled == true, applyNode = not busy and can.applyNode == true,
			applyRing = not busy and can.applyRing == true, reset = B.reset.enabled == true, lights = B.lights.enabled == true,
			retime = B.retime.enabled == true,
			show = { apply = B.apply.show, reset = B.reset.show, lights = B.lights.show, retime = B.retime.show },
			none = s ~= nil and not (B.apply.can or B.reset.can or B.lights.can or B.retime.can) }
	end

	--- The construction menu's checkEnabledFn result for a toolbar button (which = "apply" | "reset" | "lights" |
	-- "retime" | "auto" (the toggle) | "record"; sl_tool.script.lua): "Hidden" where it has nothing to do (C.buttons
	-- show), "Disabled" (grayed, with its reason in the tooltip: C.buttonTip) when it can't act right now, else
	-- "Enabled".
	function C.paramState(which)
		local b = C.buttons()[which]
		if b == nil or not b.show then return "Hidden" end
		if b.enabled then return "Enabled" end
		return "Disabled"
	end

	--- The dynamic part of a button's tooltip (translated): why it is grayed, else what it does here; nil: nothing.
	function C.buttonTip(which)
		local b = C.buttons()[which]
		if b == nil or not b.show then return nil end
		if not b.enabled and b.why ~= nil then return string.format(_("Grayed out: %s"), b.why) end
		return b.tip
	end

	--- Lane status badge of the selection: sl_pick.badge result, or Pick.badgeNone().
	function C.badge()
		if C.sel == nil then return Pick.badgeNone() end
		return C.sel.badge or Pick.badgeNone()
	end

	--- Toolbar status chip for the shown layout: { head, detail, extra = { Re-time lines } | nil }.
	function C.status(layout)
		local st = Pick.status(C.sel, layoutText(layout), C.result, C.actions())
		local s = C.sel
		if s ~= nil and (s.kind == "node" or s.kind == "ring") then
			if s.kind == "node" then
				local ok, lines = pcall(C.retimeLines, s.node)
				if ok then st.extra = lines end
			end
			-- the traffic recording's lines below Re-time's (C.recordLines); st.muted: the indices in extra of the lines
			-- shown muted (the previous recording)
			local okR, rl, mu = pcall(C.recordLines, s)
			if okR and type(rl) == "table" and #rl > 0 then
				local ex = {}
				for _, l in ipairs(st.extra or {}) do ex[#ex + 1] = l end
				local base = #ex
				for _, l in ipairs(rl) do ex[#ex + 1] = l end
				st.extra = ex
				if type(mu) == "table" and #mu > 0 then
					st.muted = {}
					for _, i in ipairs(mu) do st.muted[#st.muted + 1] = base + i end
				end
			end
		elseif s == nil then
			local ok, lines = pcall(C.allLines)
			if ok then st.extra = lines end
		end
		-- Re-time runs elsewhere: one count line (not where the selection is one of them: its own line says so)
		if C.rtCount > 0 and not (s ~= nil and s.kind == "node" and C.rts[s.node] ~= nil) then
			local ex = {}
			for _, l in ipairs(st.extra or {}) do ex[#ex + 1] = l end
			ex[#ex + 1] = C.retimeCountLine()
			st.extra = ex
		end
		-- recordings running elsewhere: one count line (not where the selection is one of them: its own lines say so)
		if C.recCount > 0 and not recAt(s) then
			local okC, cl = pcall(C.recordCountLine)
			if okC and cl ~= nil then
				local ex = {}
				for _, l in ipairs(st.extra or {}) do ex[#ex + 1] = l end
				ex[#ex + 1] = cl
				st.extra = ex
			end
		end
		-- why a shown button is grayed: also a status line (user 2026-10-17: "if re-time button is disabled it should
		-- have tooltip saying why"; the tooltip inside a disabled button did not show in game, TESTING.md "Toolbar rows")
		local okG, gl = pcall(C.grayLines)
		if okG and type(gl) == "table" and #gl > 0 then
			local ex = {}
			for _, l in ipairs(st.extra or {}) do ex[#ex + 1] = l end
			for _, l in ipairs(gl) do ex[#ex + 1] = l end
			st.extra = ex
		end
		return st
	end

	--- "Grayed out: <why>" for each shown, grayed toolbar button with a reason (C.buttons), the same reason once; not
	-- where Re-time measures the selected junction (its own progress line says so), nor while a write lands (a moment;
	-- Re-time's own line says it waits).
	function C.grayLines()
		local B = C.buttons()
		local lines, seen = {}, { [_("Re-time is measuring here")] = true, [_("A write is still landing")] = true,
			[_("Waiting for the last change to land")] = true }
		for _i, which in ipairs({ "apply", "reset", "lights", "retime", "record" }) do
			local b = B[which]
			if b ~= nil and b.show and not b.enabled and b.why ~= nil and not seen[b.why] then
				seen[b.why] = true
				lines[#lines + 1] = string.format(_("Grayed out: %s"), b.why)
			end
		end
		return lines
	end

	return C
end

return Core
