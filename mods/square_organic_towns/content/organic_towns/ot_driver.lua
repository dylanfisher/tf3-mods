-- Organic Towns: the growth driver. One instance per Lua state, ticked from the game script's guiUpdate
-- (Main Thread, ~110 Hz). Decision logic only: every engine call goes through `E` (ot_engine in game, a fake
-- in tests/square_organic_towns/test_driver.lua).
--
-- Why guiUpdate (HANDOFF "What is proven in game"): runFn's region/climate global is visible in game-script
-- update and guiUpdate but not in GUI plugin states; guiUpdate runs on the Main Thread, where commands get
-- callbacks (engine `update` can't use callbacks, findings "Street names and Road Stops"). No GUI calls, no
-- sendCommand from build events, one command in flight.
--
-- Flow: init (params, map editor / Act on gate, saved "known towns" for New towns only) -> run: every CHECK_S seconds
-- the next town off cooldown (round-robin, ot_assess) goes through one stage per tick:
--   assess   buildings -> extent, streets near it, free vs built lots, growth demand (ot_assess.demand: the
--            target's rise since the last build, unless the town's own streets still wait for houses) -> needs room?
--   terrain  terrain stats of the town disc (once per town and session)
--   snapshot street graph, joinable dead ends, style (cached per town), template sources
--   plan     ot_core.planIncrement (join = dead ends only)
--   send     ot_proposal spec -> proposal -> pre-check; refused -> plan again with half the edges; else log
--            the proposal, then send it (context without player unless ot_hooks.player == true)
--   diag     dev tools only (ot_hooks.diagnose): after a Construction_Not_Possible pre-check or a dry run,
--            each new edge pre-checked alone, failures logged (DIAG / DIAGSUM); then as send
--   wait     the build's callback; then log, cooldown, save the town's plan frame after its first build
--   fill     shaped towns (dose) and metropolis towns (ot_metro, automatic): makeTownDevelopAtCmd beside a few
--            of the build's new streets, one command at a time (FILL; FILL effect at the town's next check)
-- Log lines start with "[SQOT]" (stdout.txt).
--
-- Dev tools (square_organic_towns_dev, never uploaded) reuse this module: a second Driver instance runs single
-- jobs through the same stages (startJob / advance: forced, another style, dry run), and ot_hooks lets them hold
-- this game script's driver (paused / devBusy) and override the debug log. Without the dev mod the hooks keep
-- their defaults. Each successful build records the edges it added (townState(t).history, this session only) and,
-- since 2026-10-19, their provenance (Driver:provNote: debug PROV lines, the saved record ot_saved `pv` that the
-- console lookup ot_prov.who reads in any later session).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local I = ug_require "square_organic_towns::/organic_towns/ot_inputs.lua"
local ST = ug_require "square_organic_towns::/organic_towns/ot_style.lua"
local core = ug_require "square_organic_towns::/organic_towns/ot_core.lua"
local A = ug_require "square_organic_towns::/organic_towns/ot_assess.lua"
local PR = ug_require "square_organic_towns::/organic_towns/ot_proposal.lua"
local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"
local SV = ug_require "square_organic_towns::/organic_towns/ot_saved.lua"
local H = ug_require "square_organic_towns::/organic_towns/ot_hooks.lua"
local CK = ug_require "square_organic_towns::/organic_towns/ot_check.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local MT = ug_require "square_organic_towns::/organic_towns/ot_metrics.lua"
local MET = ug_require "square_organic_towns::/organic_towns/ot_metro.lua"
local SITE = ug_require "square_organic_towns::/organic_towns/ot_site.lua"
local SEL = ug_require "square_organic_towns::/organic_towns/ot_select.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"
local SAT = ug_require "square_organic_towns::/organic_towns/ot_satellite.lua"
local WG = ug_require "square_organic_towns::/organic_towns/ot_wedge.lua"
local PL = ug_require "square_organic_towns::/organic_towns/ot_plan.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"
local GR = ug_require "square_organic_towns::/organic_towns/ot_grid.lua"
local BR = ug_require "square_organic_towns::/organic_towns/ot_bridge.lua"
local DV = ug_require "square_organic_towns::/organic_towns/ot_diverse.lua"
local TS = ug_require "square_organic_towns::/organic_towns/ot_townsize.lua"
local MO = ug_require "square_organic_towns::/organic_towns/ot_motif.lua"
local PT = ug_require "square_organic_towns::/organic_towns/ot_motif_point.lua"
local RDS = ug_require "square_organic_towns::/organic_towns/ot_roads.lua"
local TW = ug_require "square_organic_towns::/organic_towns/ot_motif_town.lua"
local RL = ug_require "square_organic_towns::/organic_towns/ot_motif_relief.lua"
local UP = ug_require "square_organic_towns::/organic_towns/ot_upward.lua"
local MD = ug_require "square_organic_towns::/organic_towns/ot_meadow.lua"
local EN = ug_require "square_organic_towns::/organic_towns/ot_entry.lua"
local PO = ug_require "square_organic_towns::/organic_towns/ot_poly.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local LAND = ug_require "square_organic_towns::/organic_towns/ot_land.lua"
local SK = ug_require "square_organic_towns::/organic_towns/ot_skeleton.lua"
local LN = ug_require "square_organic_towns::/organic_towns/ot_lane.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"
local NM = ug_require "square_organic_towns::/organic_towns/ot_names.lua"
local PN = ug_require "square_organic_towns::/organic_towns/ot_placename.lua"
local MS = ug_require "square_organic_towns::/organic_towns/ot_mapshape.lua"
local NW = ug_require "square_organic_towns::/organic_towns/ot_namewords.lua"
local RNG = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local SN = ug_require "square_organic_towns::/organic_towns/ot_stopname.lua"
local LD = ug_require "square_organic_towns::/organic_towns/ot_lead.lua"
local WK = ug_require "square_organic_towns::/organic_towns/ot_works.lua"
local DT = ug_require "square_organic_towns::/organic_towns/ot_district.lua"
local OFF = ug_require "square_organic_towns::/organic_towns/ot_offname.lua"
local LK = ug_require "square_organic_towns::/organic_towns/ot_link.lua"
local SP = ug_require "square_organic_towns::/organic_towns/ot_satpace.lua"
local CH = ug_require "square_organic_towns::/organic_towns/ot_character.lua"
local RG = ug_require "square_organic_towns::/organic_towns/ot_ring.lua"
local RCI = ug_require "square_organic_towns::/organic_towns/ot_rci.lua"
local GL = ug_require "square_organic_towns::/organic_towns/ot_glock.lua"
local LP = ug_require "square_organic_towns::/organic_towns/ot_lockpol.lua"
local KN = ug_require "square_organic_towns::/organic_towns/ot_knot.lua"
local CARD = ug_require "square_organic_towns::/organic_towns/ot_card.lua"
-- (not `NM`: that is ot_names)
local NMISS = ug_require "square_organic_towns::/organic_towns/ot_nearmiss.lua"
local PV = ug_require "square_organic_towns::/organic_towns/ot_prov.lua"

local D = {}

D.hooks = H

D.PREFIX = "[SQOT]"
D.CONFIG_GLOBAL = "SQOT_CONFIG"
D.CHECK_S = 3              -- one town check every 3 s of real time
D.AFTER_BUILD_S = 6        -- pause after a build before the next check
D.MIN_BUILDINGS = 5        -- towns with fewer buildings are left alone (no extent yet)
D.SNAP_MARGIN = 300        -- street snapshot radius beyond the building extent (m)
D.TOWN_EDGE_FACTOR = 1.25  -- streets within this x extent radius count as the town's (lots, sources)
-- The town's own network beyond the snapshot circle (SHAPES_BRIEF 2026-10-12): Showcase v4's shape towns stopped
-- their arms ~300 m beyond the houses because the snapshot only held streets within the building extent + 300 m,
-- so arm tips further out were invisible (never reached, never joined). Town streets connected to the snapshot
-- are now followed node by node (true node degree, E.edge) up to NET_RADIUS from the extent centre, at most
-- NET_MAX edges; a street whose far node is closer to another town ends the walk there.
D.NET_RADIUS = 2500
D.NET_MAX = 1200
D.NET_BUDGET_US = 50000
D.NET_CHECK_US = 15000    -- the CHECK's town network budget (R1: CHECK frames up to ~54 ms; the rest next check)
D.CHECK_SPLIT_US = 12000  -- CHECK: reads that took this long end the tick; the network / lots / demand run next tick
D.MIN_EDGES = 3            -- smallest increment tried after pre-check refusals
D.WAIT_TIMEOUT_S = 30
D.INIT_RETRY_S = 15
D.INIT_TRIES = 4
D.TOWNS_REFRESH_S = 30
D.SLICE_PLAN = true        -- plan stage sliced over ticks (coroutine), PLAN_SLICE_US per tick at most per step
D.PLAN_SLICE_US = 4000
-- plan hang guard (2026-10-13, real map run 2026-10-13_1848_sqot: Henley-on-Thames' head-start round 2 froze the Main
-- Thread after SNAPSHOT until the game's watchdog killed it): a debug count hook on the plan coroutine (and on the one-go
-- planners, D.guard) ends a plan whose slice runs longer than PLAN_HANG_US or whose plan as a whole passes PLAN_TOTAL_US
-- with an error that carries the Lua traceback (log WARN stage=plan msg=planHang). The town finishes "fail" (no plan,
-- never retried in the same tick) and is cooled down like any failure. Off when the game Lua has no debug.sethook.
D.PLAN_GUARD = true
D.PLAN_HANG_US = 1500000
D.PLAN_TOTAL_US = 4000000
D.PLAN_HOOK_COUNT = 20000  -- VM instructions between the hook's clock reads
D.HANG_TAG = "planHang"
D.STAGE_HANG_US = 4000000  -- the other job stages (assess, terrain, snapshot, send, ...): one tick at most this long
D.STATS_RADIUS = 600
D.WIDE_RADIUS = 2000       -- site classifier survey (ot_terrain.wide, ot_site)
D.SPIT_WATER = 0.02        -- wide-survey water share from which the peninsula tip's spit is looked for
D.MAX_EXCLUDE = 200
D.SAMPLER_RENEW_S = 600
D.RETIRE_CHECKS = 4       -- R4: an own dead end without a house in more than this many snapshots in a row is retired
D.GAPS = true              -- gaps between towns (ot_gap, R3): new streets stop short of the halfway line to a neighbour
D.LAND = true              -- the landscape pull (ot_land, §62): the town's big-scale lean on its style each snapshot
D.SKEL = true              -- the landscape-aware skeleton (ot_skeleton, §63): arms into open land, clear of the woods
D.LAND_EDGE_M = 100        -- m: wide survey points this close to the map edge (or off it) count as no land (ot_land)
D.FOREST = true            -- forest-aware towns (ot_forest, phase F): read the trees around a town (stage "forest")
D.HISTORY_MAX = 20         -- built increments remembered per town (edge ids, for dev tools' undo)
D.MATCH_M = 1.5            -- a built edge matches its spec edge when both ends lie this close
-- Joining a dead end the mod built itself (no BASE_NODE_CONFIG): off until verified in game (HANDOFF; the
-- config can only be added there, never removed). Per instance: driver.allowNoConfig (the dev tools' toggle).
D.ALLOW_NO_CONFIG = false
D.DIAG_PER_TICK = 6        -- diagnosis: single-edge pre-checks per tick (~1-3 ms each)
D.DIAG_LOG = 6             -- diagnosis: failing edges logged per increment
D.PRUNE_ROUNDS = 2         -- refused pre-check: drop the edges that fail alone and plan again (same size), twice
D.MIN_USEFUL = 3           -- an increment this small is built only when it closes a loop (joins >= 2)
D.DEMAND_MIN_INC = 6       -- a growth-demand build (ot_assess.demand) plans at least this many edges
-- Houses onto the arms (NEXT_PHASE_BRIEF 13, 2026-10-12). Showcase v5: shaped towns' arms stayed empty street
-- skeletons (~25 % of our edges had parcels; houses elong 1.07-1.48), the game rounded the town out with its own
-- side streets. Two levers, both on by default for shaped towns (compact / unshaped towns: neither):
-- * Lock: new streets in an arm corridor (ot_shape.inArm) or near the envelope rim go out roadDevelopmentLocked.
--   v5 lock probe: the flag stuck (157/157), houses still built along them, the town attached 0-1 side streets to
--   them instead of 33, the fingers town had 426 houses on our streets vs 168.
-- * Dosed fill: after a build, makeTownDevelopAtCmd(point, false, false) beside a few of its new arm / rim streets,
--   once. v5's fill twin (12 points every round) grew 12x (7196 buildings vs ~580) and round: DevelopAt resets the
--   town's initial land use capacities to its current capacities, so its growth target (initial x size factors)
--   becomes size factor x its size (750 -> 105231 at the same size factors) and the town keeps growing toward a
--   target it never had. So after the dose's DevelopAt the driver puts the initial capacities back
--   (makeTownSetInitialLandUseCapacitiesCmd, FILL restore): at most FILL_EXTRA above what they were, and never
--   above FILL_CAP x their sum at the town's first build (saved with the plan frame, `ic`; else the first one seen
--   this session). A dose is skipped at that cap, or while a fill's growth wave may still be coming (FILL_SURGE
--   within FILL_SURGE_S). Whether DevelopAt also builds right at the point (the undo_tf3 mod rebuilds a house that
--   way) is what FILL effect near= / far= measures.
-- Metropolis (automatic city style since 2026-10-12, ot_metro; the "Metropolis growth" setting is gone): big towns on
-- big flat open land (seeded share) get v5's strong fill (METRO_POINTS beside the build's new streets the variant
-- picks, ot_metro.fillEdges; since Showcase v8 round restored with a looser brake, ot_metro FILL_EXTRA / POLY_EXTRA)
-- up to METRO_MAX_CAP, the variant's road mix, shape and lock (ot_metro.apply / lockKeys: every new street since v8
-- round), METRO_MAX_EDGES per increment. METRO line per planned increment (debug).
D.LOCK_SHAPE = true        -- the legacy lock (towns framed before §65, or LOCK_DEFAULT "legacy"): "shape" (false: "off")
-- §65 (2026-10-15, run 2026-10-15_0629_sqot: the game's own town developer built ~2/3 of the new streets, branching off
-- every unlocked street, ours included; findings towns.md "Locked town streets"): the lock a town without a saved frame
-- gets. "mod": every street the mod builds is roadDevelopmentLocked (increments, rings, links, lanes, bridges, frames,
-- offshoot streets); the town's own starting streets, the game's and the player's stay unlocked, so the game branches
-- only off its own streets. "legacy": the shape lock (LOCK_SHAPE: arm / rim / forest / motif / zone keys) as before.
-- The town keeps the lock its first build saved in its frame (`lm`); frames from before §65 stay legacy. A job may
-- override (startJob lock); the dev tools may set ot_hooks.lockDefault for the towns framed this session.
-- §69 (2026-10-15, run 2026-10-15_1936_sqot-glprobe: with every street locked (§65 + §67) the towns lost their
-- organic texture and grew bare locked spikes; the user: "lock ... many of them, especially early when trying to steer
-- direction"): "steer", the default for towns framed from now on (frame `lm = 2`): the policy of ot_lockpol (lock
-- what steers: facing forest / water / a neighbour / against the land, the skeleton's arms while young, beyond the
-- town's inner zone, which opens with the maturity; the game's streets only at the rim where they face something
-- unwanted), a locked branch's far tip left open as a growth point (ot_glock.pickTips, a tip valve), the lead beyond
-- housed streets capped (ot_lockpol.leadCap), and the look rules against rakes and wiggles (ot_select RAKE / WIGGLE).
-- "mod" (every street locked, §65) and "legacy" stay selectable (ot_hooks.lockDefault) for A/B; a town keeps the lock
-- its frame saved (`lm` 1: "mod", none: "legacy").
D.LOCK_DEFAULT = "steer"
D.LOCK_LEAD_K = 1.5        -- "mod" towns: open lots allowed on the mod's own streets x this (ot_assess.demand lockK):
                           -- the game no longer adds frontage off them, so the mod keeps more ahead of the demand
D.STEER_LEAD_K = 1.2       -- "steer" towns: the same, less (the game fills inside the town again)
D.STEER_LIMITS = true      -- "steer" towns' plans: the lead cap, the continuous arm front, the rake / wiggle rules
-- §74 close the gap (ot_nearmiss, 2026-10-17): every town plan joins up to MAX_PER_INC near-miss dead ends to the street
-- ahead (a bend into another dead end, a T or a crossroads at a street node); the street nodes joined pass
-- Driver:midJoinOk (a node config, plain town streets of this town only, no track, no construction)
D.NEAR_MISS = true
D.NEAR_MISS_US = 8000      -- us: the pass's time per plan at most (it runs in one slice: no yield inside its pcall);
                           -- offline ~8-12 ms for a 500-edge town with 60-100 dead ends, the nearest gaps go first
D.NEAR_MISS_RETIRED = true -- (2026-10-18) a retired own dead end (empty, never extended) may still be closed by a join
                           -- (Driver:retiredJoinOk): a join adds no street out into the field, it ends the stub
D.LOCK_RIM = 0.75          -- rim: effective distance above this x the envelope level (ot_select.envelopeCap)
D.FILL_POINTS = 2          -- dosed fill: DevelopAt points per build of a shaped town (0 = off)
D.FILL_SHORE_M = 300       -- shore towns: the dose beside the build's streets within this of the shore (waterfront first)
D.FILL_SHORE_MIN = 10      -- ... a point nearer the shore than this goes to the street's other side
D.FILL_OFFSET = 20         -- ... this far beside a new street's midpoint (sides alternate)
D.FILL_MIN_LEN = 20        -- ... streets at least this long
-- (2026-10-14, the same-seed vanilla comparison BASELINE_VANILLA.md: FILL_EXTRA 0.15 per dose up to FILL_CAP 1.3 x base
-- raised 7 towns' initial capacities by 14-30 %, so they ended with more people than vanilla for the same transport.
-- A dose now puts the initial capacities back exactly (FILL restore to the pre-fill values; INIT / FILL restore
-- `capsBoost=0`); DevelopAt still places houses on our streets. Capacities an older build raised stay as they are (never
-- lowered: that could demolish buildings), they just rise no more. FILL_CAP applies only while FILL_EXTRA > 0.)
D.FILL_CAP = 1.3           -- ... only while the initial capacity sum <= FILL_CAP x its base (only with FILL_EXTRA > 0)
D.FILL_EXTRA = 0           -- ... and each dose raises the initial capacities by at most this share (FILL restore)
D.FILL_SURGE = 0.25        -- ... and not when the buildings grew more than this share since the last fill ...
D.FILL_SURGE_S = 300       -- ... less than this many real seconds ago (DevelopAt's growth comes a round later, v4)
D.METRO_POINTS = 12        -- metropolis: points per build (both sides of each new street, as v5's fill twin)
D.METRO_MAX_EDGES = 36     -- metropolis: edges per increment (Showcase v8 round; v7's 18 housed a tenth of the growth)
D.METRO_MIN_CAP = MET.MIN_CAP   -- ... towns from this person capacity (~900-1000 buildings; ot_metro.decide)
D.METRO_MAX_CAP = 50000    -- ... up to this one (v5's fill twin: 43901 after 10 rounds; each fill multiplies the
                           -- town's target by its size factor, so without a ceiling it never stops)
D.FILL_NEAR = 60           -- FILL effect line: buildings within FILL_NEAR / FILL_FAR m of the points, before the
D.FILL_FAR = 200           -- ... fill and at the town's next check (where DevelopAt's growth goes)
D.FILL_TIMEOUT_S = 10      -- a DevelopAt callback that never comes
D.FILL_CONCURRENT = true   -- a build's DevelopAt calls go out back to back (Showcase v8 round), the restore after all
-- Metropolis mechanics at a smaller scale (Showcase v9 round, user: "Metropolis grid starts to feel almost like it
-- could be the American grid or suburbs"): a style's `mech` (ot_style: NA grid, NA suburb, ensanche, superblock) locks
-- every new street, plans mech.maxEdges per increment and doses the fill beside any new street (mech.fill "dose",
-- restored like a shaped town's dose). false: the styles grow as in v8.
D.MECH = true
D.IND_REFRESH_S = 300      -- away from industries (ot_industry): the map's industry list re-read this often (real s)
D.FAC_REFRESH_S = 120      -- away from player facilities (ot_industry FAC_KINDS): depots / stations re-read this often
                           -- (real s); the towns' info is redone only when the list changed
D.STATION_REFRESH_S = 120  -- station quarter (M3, ot_motif_town): the map's rail stations re-read this often (real s)
D.STATION_REACH = 1500     -- m from a town's centre: stations kept for it
D.STATION_TRACKS_R = 350   -- m around a station: its tracks read once per listing (the quarter keeps off them)
D.FILL_SURGE_JITTER = 0.5  -- the surge window per town: FILL_SURGE_S x (1 - J/2 .. 1 + J/2) by town id, so towns whose
                           -- first doses came together don't all dose again in the same round (v6 round 9: 23 doses)

local function fmt(v)
	local t = type(v)
	if t == "number" then
		if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.2f", v)
	end
	if t == "table" then
		local parts = {}
		for i, x in ipairs(v) do parts[i] = fmt(x) end
		return table.concat(parts, ",")
	end
	return (tostring(v):gsub("%s+", "_"))
end

--- "[SQOT] WHAT k=v k=v" from an ordered list of {key, value} (prefix: another tag, e.g. the dev tools').
function D.line(what, fields, prefix)
	local parts = { prefix or D.PREFIX, what }
	for _, f in ipairs(fields or {}) do parts[#parts + 1] = f[1] .. "=" .. fmt(f[2]) end
	return table.concat(parts, " ")
end

local function isTownTemplate(path)
	return type(path) == "string" and path:find("town_", 1, true) ~= nil and path:find("one_way", 1, true) == nil
end

local function classOf(path)
	if type(path) ~= "string" then return "small" end
	if path:find("large", 1, true) then return "main" end
	if path:find("medium", 1, true) then return "medium" end
	return "small"
end

--- An edge we may copy or join to: a plain town street, not player owned, no stops, not part of a
--- construction, an even lane count with at least one lane each way.
function D.plainTownEdge(ed)
	return ed ~= nil and isTownTemplate(ed.template) and not ed.owned and (ed.objects or 0) == 0
		and not ed.inConstruction and (ed.lanes or 0) >= 4 and ed.lanes % 2 == 0
end

---------------------------------------------------------------------------
-- lock and fill decisions (pure; NEXT_PHASE_BRIEF 13)

--- Lock mode of a job: "all" (every new edge: the dev lock probe), "steer" (the §69 default: ot_lockpol per street,
--- D.steerKeys), "mod" (every new edge: §65, every street the mod builds), "shape" (arm / rim streets of shaped towns:
--- the legacy lock while LOCK_SHAPE) or "off". job.lock: true | "all" | "steer" | "mod" | "shape" | false | "off" | nil
--- (the town's lock, job.townLock: "steer" | "mod" | "legacy", set by Driver:jobLock; nil: legacy).
function D.lockMode(job)
	local l = job and job.lock
	if l == true or l == "all" then return "all" end
	if l == false or l == "off" then return "off" end
	if l == "shape" then return "shape" end
	if l == "mod" then return "mod" end
	if l == "steer" then return "steer" end
	if job and job.townLock == "mod" then return "mod" end
	if job and job.townLock == "steer" then return "steer" end
	return D.LOCK_SHAPE and "shape" or "off"
end

--- Is a town lock ("mod" | "steer" | "legacy") one of the §65+ locks (the game branches mostly off what we leave open:
--- the stall guard, the game-street lock, the lead floor)?
function D.lockFamily(m)
	return m == "mod" or m == "steer"
end

--- Does lock mode `mode` lock every new edge of a build (PR.build info.lock)?
function D.locksAll(mode)
	return mode == "all" or mode == "mod"
end

--- true, "arm" | "rim" when (x, y) lies in an arm corridor of the shape or beyond LOCK_RIM x the envelope level
--- env (effective m; nil: arms only). Compact / no shape: false.
function D.armOrRim(sh, x, y, env, sampler)
	if sh == nil or sh.id == nil or sh.id == "compact" then return false end
	if SH.inArm(sh, x, y) then return true, "arm" end
	if env ~= nil and SH.distance(sh, x, y, sampler) > D.LOCK_RIM * env then return true, "rim" end
	return false
end

--- The envelope level of a planned increment (report.envCap x envScale) or nil.
function D.envLevel(report)
	if report == nil or report.envCap == nil then return nil end
	return report.envCap * (report.envScale or 1)
end

--- Plan edges of job.inc to lock: { [key] = true } or nil, count, mode. Mode "shape": the arm / rim edges of a
--- shaped town (job.style.shape, job.report's envelope); "all" / "off": nil (PR.build's info.lock covers "all").
--- Industry keep-clear zones (2026-10-13): the build's new streets within IND.ZONE_LOCK_M of a zone are added to keys
--- (locked: the game hangs no side streets of its own off them into the zone). Returns keys, n.
function D.zoneLock(job, keys, n)
	local ind = job.style and job.style.industry
	job.zoneLockN = 0
	if not (IND.ZONE and ind and ind.zones and #ind.zones > 0) or job.inc == nil then return keys, n end
	keys = keys or {}
	for _, e in ipairs(job.inc.edges) do
		if e.key ~= nil and not keys[e.key] and not e.forestLane then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			if IND.zoneHit(ind, { e.p0, { mx, my }, e.p1 }, IND.ZONE_LOCK_M) then
				keys[e.key] = true
				n = n + 1
				job.zoneLockN = job.zoneLockN + 1
			end
		end
	end
	return keys, n
end

function D.lockKeys(job)
	local mode = D.lockMode(job)
	-- (§69 "steer": the policy per street, D.steerKeys; a metropolis / mech style keeps its own rule below)
	if mode == "steer" and job.inc ~= nil and not (job.style and (job.style.metro or (job.style.mech and job.style.mech.lockAll and D.MECH))) then
		return D.steerKeys(job)
	end
	-- ("mod" / "all": PR.build's info.lock locks every new edge; no keys needed)
	if mode ~= "shape" and mode ~= "steer" or job.inc == nil then return nil, 0, mode end
	-- a metropolis locks by its variant (ot_metro.lockKeys) instead of the shape's arms / rim
	if job.style and job.style.metro then
		local keys, n = MET.lockKeys(job.style, job.inc)
		keys, n = D.zoneLock(job, keys, n or 0)
		return keys, n, "metro"
	end
	-- metropolis mechanics at a smaller scale (style.mech, Showcase v9 round: grid styles): every new street locked
	local mech = job.style and job.style.mech
	if mech and mech.lockAll and D.MECH then
		local keys, n = {}, 0
		for _, e in ipairs(job.inc.edges) do
			if e.key ~= nil and not keys[e.key] then keys[e.key] = true; n = n + 1 end
		end
		if n == 0 then return nil, 0, mode end
		return keys, n, "mech"
	end
	local sh = job.style and job.style.shape
	local env = D.envLevel(job.report)
	local keys, n = {}, 0
	-- motifs with `lock` (M2: the ribbon village's and the village green's streets: no game side streets on them)
	local pre = MO.lockPrefixes(job.style)
	for _, e in ipairs(job.inc.edges) do
		local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
		local lock = false
		if e.key ~= nil and type(e.key) == "string" then
			for _, p in ipairs(pre) do if e.key:sub(1, #p) == p then lock = true; break end end
		end
		if e.key ~= nil and not lock and sh ~= nil and D.armOrRim(sh, mx, my, env, job.sampler) then lock = true end
		if lock and not keys[e.key] then
			keys[e.key] = true
			n = n + 1
		end
	end
	-- forest-facing streets of a hug town (round after the names run, ot_forest.facesForest): locked, so the game hangs
	-- no streets of its own off them into the trees (Brentwood: the game built ~3 of 4 of its streets, into the forest)
	local fo = job.style and job.style.forest
	if D.FOREST_LOCK and FO.active(fo) then
		local deg = {}
		for _, e in ipairs(job.inc.edges) do
			for _, nd in ipairs({ e.node0, e.node1 }) do if nd then deg[nd] = (deg[nd] or 0) + 1 end end
		end
		local side, tip, near = 0, 0, 0
		for _, e in ipairs(job.inc.edges) do
			if e.key ~= nil and not keys[e.key] and not e.forestLane then
				local tip0 = (e.node0 or 0) < 0 and deg[e.node0] == 1
				local tip1 = (e.node1 or 0) < 0 and deg[e.node1] == 1
				-- (deep forest towns, 2026-10-14: any forest within lot depth or just beyond, ot_forest.facesForest)
				local face, why = FO.facesForest(fo, e.p0, e.p1, tip0, tip1)
				if face then
					keys[e.key] = true
					n = n + 1
					if why == "tip" then tip = tip + 1 elseif why == "near" then near = near + 1 else side = side + 1 end
				end
			end
		end
		job.forestLockN = { side = side, tip = tip, near = near }
	end
	keys, n = D.zoneLock(job, keys, n)
	if n == 0 then return nil, 0, mode end
	return keys, n, mode
end
D.FOREST_LOCK = true

--- §69 "steer" keys: per new street of job.inc the ot_lockpol policy (job.steerC = { outline, cx, cy, mat, shape, ctx },
--- Driver:steerPrep; without it every street is locked, as "mod"), plus the motif / ring / zone locks; the tips
--- (ot_glock.pickTips, job.steerTipMax open at most) left unlocked. Sets job.steerTally ({ [why] = n }), job.steerTips
--- ({ key, x, y, a, score }), job.steerTipRej, job.steerSmall (§71: the faces and tips small woods alone would have made
--- forest). Returns keys, n, "steer".
function D.steerKeys(job)
	local keys, n = {}, 0
	local small = 0
	local c = job.steerC
	local edges = job.inc.edges
	local tally, why = {}, {}
	local deg = {}
	for i = 1, math.min(#edges, LP.SCAN_MAX) do
		local e = edges[i]
		for _, nd in ipairs({ e.node0, e.node1 }) do if nd then deg[nd] = (deg[nd] or 0) + 1 end end
	end
	local pre = MO.lockPrefixes(job.style)
	for i = 1, math.min(#edges, LP.SCAN_MAX) do
		local e = edges[i]
		if e.key ~= nil and not keys[e.key] and not e.existing then
			local lock, w, sm
			if c == nil or not LP.ON then lock, w = true, "out"
			else
				lock, w, sm = LP.decide({ p0 = e.p0, p1 = e.p1, key = e.key,
					tip0 = (e.node0 or 0) < 0 and deg[e.node0] == 1, tip1 = (e.node1 or 0) < 0 and deg[e.node1] == 1 }, c)
				if sm then small = small + 1 end
			end
			if not lock and type(e.key) == "string" then
				for _, p in ipairs(pre) do if e.key:sub(1, #p) == p then lock, w = true, "rim" break end end
			end
			if lock then keys[e.key] = true; n = n + 1 end
			why[e.key] = w
			tally[w] = (tally[w] or 0) + 1
		end
	end
	keys, n = D.zoneLock(job, keys, n)
	-- (the tips: a locked branch's far end into open land stays open, the growth point the game develops from)
	job.steerTips, job.steerTipRej = nil, nil
	if c ~= nil and (job.steerTipMax or 0) > 0 and job.ext ~= nil then
		local picks, rej, smT = GL.pickTips(edges, why, c.ctx or {}, job.ext.cx, job.ext.cy, job.ext.r, job.steerOpen, job.steerTipMax)
		small = small + (smT or 0)
		for _, p in ipairs(picks) do
			if keys[p.key] then
				keys[p.key] = nil
				n = n - 1
				tally[why[p.key]] = (tally[why[p.key]] or 1) - 1
				tally.tip = (tally.tip or 0) + 1
			end
		end
		job.steerTips, job.steerTipRej = picks, rej
	end
	job.steerTally = tally
	job.steerSmall = small
	return keys, n, "steer"
end

--- Which fill a successful build gets: "dose" | "metro" | nil, and why not (or the kind's reason).
--- job.fill: "dose" | "metro" | "off" | nil (default: metro for a metropolis (job.style.metro, ot_metro), else dose
--- for shaped towns while FILL_POINTS > 0). caps = { actual, target, initial } before the build; last = the town's
--- previous fill record (s.fill) or nil; buildings = the town's buildings before the build; nowUs; base = the
--- town's initial capacity sum at its first build (nil: no brake known).
D.MEADOWS = true           -- sprawling / unarmed character towns: protected meadows between the lobes (ot_meadow)
D.LOBE_FILL = true         -- sprawling towns' builds get the dose fill beside their outer streets (2026-10-13, round 5)
D.MOTIF_FILL = true        -- motifs with a dose hook (ot_motif MO.dose: the harbour crescent) get it beside their streets (M1)
function D.fillKind(job, opts, caps, last, buildings, nowUs, base)
	local f = job and job.fill
	if f == "off" or f == false then return nil, "off" end
	local metro = f == "metro" or (f == nil and job.style ~= nil and job.style.metro ~= nil)
	if metro then
		if caps ~= nil and (caps.actual or 0) >= D.METRO_MAX_CAP then return nil, "metroMax" end
		return "metro", f == "metro" and "forced" or "big"
	end
	if f ~= "dose" and D.FILL_POINTS <= 0 then return nil, "off" end
	local sh = job.style and job.style.shape
	local mechFill = D.MECH and job.style ~= nil and job.style.mech ~= nil and job.style.mech.fill == "dose"
	-- (2026-10-13 round 5: sprawling towns' lobes stayed empty, Barrow-in-Furness's own unhoused streets reached the empty
	-- budget, 2.8 km, and the game filled its core: a blob. Their builds get the dose beside the outer new streets too)
	local lobes = D.LOBE_FILL and job.style ~= nil and job.style.form ~= nil and job.style.form.id == "sprawling"
	-- (motifs with a dose hook, M1: the harbour crescent's row facing the water, when the build has crescent streets)
	local motif = D.MOTIF_FILL and job.style ~= nil and job.spec ~= nil
		and #(MO.dose(job.style, job.spec.edges, D.FILL_OFFSET, D.FILL_POINTS)) > 0
	-- (job.fillPts: a lane ahead's far end, its own points whatever the town's shape)
	if (sh == nil or sh.id == "compact") and not mechFill and not lobes and not motif and job.fillPts == nil then return nil, "unshaped" end
	if D.FILL_EXTRA > 0 and caps ~= nil and caps.initial ~= nil and base ~= nil and base > 0 and caps.initial > D.FILL_CAP * base then
		return nil, "cap"
	end
	-- (a lane's far end / a satellite seed's core, 2026-10-14: never held by the surge rule; run 2026-10-14_0502_sqot:
	-- five of ten satellite seeds got no core dose, `skip=surge`. Its restore still applies)
	if job.fillPts ~= nil then return "dose", job.fillWhy or "leadEnd" end
	-- (the dev Simulate's build rounds, 2026-10-14: its Fast fill covers the dose; run 0502's year 8 timed out on them)
	if H.simNoFills and not job.force then return nil, "sim" end
	if last ~= nil and last.buildings0 ~= nil and nowUs ~= nil and last.us ~= nil and nowUs - last.us < D.surgeWindowS(job.town) * 1e6
		and (buildings or 0) > last.buildings0 * (1 + D.FILL_SURGE) then return nil, "surge" end
	local unshaped = sh == nil or sh.id == "compact"
	return "dose", f == "dose" and "forced" or (motif and "motif") or (mechFill and unshaped and "mech")
		or (lobes and unshaped and "lobes") or "shape"
end

--- The largest share a fill (dose, metropolis, polycentric, upward) may raise a town's initial capacities by (INIT /
--- FILL restore `capsBoost=`); 0 since 2026-10-14.
function D.capsBoost()
	return math.max(D.FILL_EXTRA, MET.FILL_EXTRA, MET.POLY_EXTRA, UP.EXTRA)
end

--- The fill surge window of town t in seconds: FILL_SURGE_S spread by FILL_SURGE_JITTER from a hash of the id.
function D.surgeWindowS(t)
	local u = (((tonumber(t) or 0) * 2654435761) % 1000) / 1000
	return D.FILL_SURGE_S * (1 + D.FILL_SURGE_JITTER * (u - 0.5))
end

local function streetNormal(e)
	local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
	local l = math.sqrt(dx * dx + dy * dy)
	if l < 1e-6 then return nil end
	return (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2, -dy / l, dx / l, l
end

--- Away from industries (ot_industry FILL_AVOID): the entries of list outside the buffers (pos(entry) -> x, y), or
--- the whole list when none is outside (a town boxed in by works still gets its dose).
function D.outsideBuffers(list, ind, pos)
	if ind == nil or not IND.FILL_AVOID or #list == 0 then return list end
	local out = {}
	for _, c in ipairs(list) do
		local x, y = pos(c)
		if not IND.inBuffer(ind, x, y) then out[#out + 1] = c end
	end
	if #out == 0 then return list end
	return out
end

--- DevelopAt points for a build: { {x, y} }. edges = the built spec edges (p0, p1). "metro": both sides of every
--- street's midpoint (FILL_OFFSET out), at most METRO_POINTS; of a metropolis (style.metro) only the streets its
--- variant fills (ot_metro.fillEdges: corridor band, centre discs, nearest the centre first). "dose": the arm / rim streets (D.armOrRim with
--- env) of at least FILL_MIN_LEN, FILL_POINTS of them spread evenly from the innermost to the outermost (shape
--- centre distance), one side each, sides alternating.
function D.fillPoints(kind, edges, sh, env, sampler, style)
	local pts = {}
	-- (forest lanes, R2: no dose beside a country lane, its houses are held off on purpose)
	if edges then
		local keep, drop = {}, false
		for _, e in ipairs(edges) do
			if e.forestLane then drop = true else keep[#keep + 1] = e end
		end
		if drop then edges = keep end
	end
	if kind == "metro" then
		if style and style.metro then edges = MET.fillEdges(style, edges) end
		for _, e in ipairs(edges or {}) do
			local mx, my, nx, ny = streetNormal(e)
			if mx then
				local ax, ay, bx, by = mx + nx * D.FILL_OFFSET, my + ny * D.FILL_OFFSET, mx - nx * D.FILL_OFFSET, my - ny * D.FILL_OFFSET
				-- (forest-hugging towns, phase F: both points on the open side when one lies in the forest)
				local fo = style and style.forest
				pts[#pts + 1] = { FO.openSide(fo, ax, ay, bx, by) }
				pts[#pts + 1] = { FO.openSide(fo, bx, by, ax, ay) }
			end
			if #pts >= D.METRO_POINTS then break end
		end
		while #pts > D.METRO_POINTS do table.remove(pts) end
		return D.outsideBuffers(pts, style and style.industry, function(p) return p[1], p[2] end)
	end
	-- (motifs, M1: the harbour crescent's dose on the land side of its new waterfront streets)
	if kind == "dose" and D.MOTIF_FILL and style ~= nil then
		local mp = MO.dose(style, edges, D.FILL_OFFSET, D.FILL_POINTS)
		if #mp > 0 then return D.outsideBuffers(mp, style.industry, function(p) return p[1], p[2] end) end
	end
	-- (style.mech: a grid town's dose goes beside any of the build's new streets, not only arm / rim ones)
	local any = D.MECH and style ~= nil and style.mech ~= nil and style.mech.fill == "dose"
		and (sh == nil or sh.id == "compact")
	-- (sprawling towns, round 5: beside the build's outer streets, the lobes, outermost first)
	local lobes = D.LOBE_FILL and style ~= nil and style.form ~= nil and style.form.id == "sprawling"
		and (sh == nil or sh.id == "compact")
	any = any or lobes
	if kind ~= "dose" or (sh == nil and not any) then return pts end
	local cand = {}
	local cx, cy = (sh and sh.centre or (style and style.centre) or { 0, 0 })[1], (sh and sh.centre or (style and style.centre) or { 0, 0 })[2]
	-- shore towns (2026-10-12): the dose goes to the build's streets near the water (within FILL_SHORE_M of the traced
	-- shore; the arm / rim ones when none is), spread along the shore, never onto the water side's last metres
	local sd = sh and sh.id == "shore" and sh.shore or nil
	for _, e in ipairs(edges or {}) do
		local mx, my, nx, ny, l = streetNormal(e)
		if mx and l >= D.FILL_MIN_LEN then
			local perp, sAbs = nil, nil
			if sd then
				local _, pp, _, sa = SH.shoreAt(sd, mx, my)
				perp, sAbs = pp, sa
			end
			if any or D.armOrRim(sh, mx, my, env, sampler) or (perp and perp <= D.FILL_SHORE_M) then
				cand[#cand + 1] = { mx = mx, my = my, nx = nx, ny = ny, r = G.dist(cx, cy, mx, my), perp = perp, s = sAbs }
			end
		end
	end
	if sd then
		local near = {}
		for _, c in ipairs(cand) do if c.perp <= D.FILL_SHORE_M then near[#near + 1] = c end end
		if #near > 0 then
			cand = near
			table.sort(cand, function(a, b) return a.s < b.s end)
		else
			table.sort(cand, function(a, b) return a.r < b.r end)
		end
	elseif lobes then
		table.sort(cand, function(a, b) return a.r > b.r end)
		-- the outer half of the build's streets only (the lobe, not the town's edge)
		while #cand > 2 and #cand > math.ceil(#cand / 2) and cand[#cand].r < 0.5 * cand[1].r do table.remove(cand) end
	else
		table.sort(cand, function(a, b) return a.r < b.r end)
	end
	cand = D.outsideBuffers(cand, style and style.industry, function(c) return c.mx, c.my end)
	local n = math.min(D.FILL_POINTS, #cand)
	for k = 1, n do
		local c = cand[math.max(1, math.min(#cand, math.floor((k - 0.5) * #cand / n) + 1))]
		local side = (k % 2 == 1) and 1 or -1
		local px, py = c.mx + side * c.nx * D.FILL_OFFSET, c.my + side * c.ny * D.FILL_OFFSET
		-- forest-hugging towns (phase F): the dose on the street's open side, the houses facing the trees across it
		px, py = FO.openSide(style and style.forest, px, py, c.mx - side * c.nx * D.FILL_OFFSET, c.my - side * c.ny * D.FILL_OFFSET)
		if sd then
			local _, pp, wet = SH.shoreAt(sd, px, py)
			if wet or pp < D.FILL_SHORE_MIN then px, py = c.mx - side * c.nx * D.FILL_OFFSET, c.my - side * c.ny * D.FILL_OFFSET end
		end
		pts[#pts + 1] = { G.round(px, 1), G.round(py, 1) }
	end
	return pts
end

--- Buildings of pts (list of {x, y}) within r of (x, y).
function D.countNear(pts, x, y, r)
	local n, r2 = 0, r * r
	for _, p in ipairs(pts or {}) do
		local dx, dy = p[1] - x, p[2] - y
		if dx * dx + dy * dy <= r2 then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------------

local Driver = {}
Driver.__index = Driver

--- The lock of a town (§65, §69): "steer", "mod" or "legacy". Its saved frame decides (`lm` = 2: "steer", 1: "mod"; a
--- frame without it, from before §65: "legacy"); a town without a frame gets ot_hooks.lockDefault or LOCK_DEFAULT.
--- Cached on the town state.
function Driver:townLockMode(t, saved)
	local s = self:townState(t)
	if s.lockMode ~= nil then return s.lockMode end
	local fr = SV.frame(saved or self.saved, t)
	local m
	if fr ~= nil then
		m = (fr.lockMode == "mod" or fr.lockMode == "steer") and fr.lockMode or "legacy"
	else
		local d = H.lockDefault or D.LOCK_DEFAULT
		m = (d == "mod" or d == "steer") and d or "legacy"
	end
	s.lockMode = m
	return m
end

--- The lock mode of a job (D.lockMode with its town's lock, Driver:townLockMode, on job.townLock).
function Driver:jobLock(job)
	if job.townLock == nil and job.town ~= nil then job.townLock = self:townLockMode(job.town) end
	return D.lockMode(job)
end


--- A driver over engine E. log(line) defaults to E.log or log.message. prefix: log tag (default D.PREFIX).
function D.new(E, prefix)
	local d = setmetatable({
		E = E, phase = "init", prefix = prefix, sched = A.newSched(), towns = {}, job = nil, nextUs = 0, inflight = false,
		initSent = 0, initNextUs = 0, townList = nil, townListUs = -1e18,
		counts = { checks = 0, builds = 0, fails = 0, refused = 0 },
	}, Driver)
	return d
end

---------------------------------------------------------------------------
-- Pause (2026-10-17, player report: "roads are built while the game is paused"). The driver runs from guiUpdate, which
-- ticks while the game is paused, and its pacing was wall-clock time. Now its clock is running time: real time with
-- every paused stretch left out (Driver:gameClock, from the world's GAME_SPEED.speedup, ot_engine.gameSpeed), so every
-- cooldown, the head start's gap, CHECK_S, AFTER_BUILD_S and the callback timeouts stand still while paused and nothing
-- fires at once on unpause. While paused a tick starts nothing (no check, head-start job, fill, satellite, name, stop,
-- level or RCI command); only a build callback that already came is handled (Driver:pausedTick). Not scaled by the
-- speed: speed x2 / x4 still build at the real-time pace (the old behaviour at every speed). One PAUSE line per change.
D.PAUSE_GATE = true

--- The driver's clock (us): the engine's real-time clock minus the paused time (Driver:gameClock). Every stamp and
--- timeout in the driver uses it; durations inside one tick are the same as real time (the offset changes between ticks).
function Driver:nowUs()
	return self.E.nowUs() - (self.pausedUs or 0)
end

--- Driver:nowUs as a plain function (the hang guards' clock).
function Driver:clockFn()
	local f = self.clockFnC
	if f == nil then
		f = function() return self:nowUs() end
		self.clockFnC = f
	end
	return f
end

--- Is the simulation paused? GAME_SPEED.speedup 0 (ot_engine.gameSpeed); unreadable / no accessor: running.
function Driver:gamePausedNow()
	if not D.PAUSE_GATE or self.E.gameSpeed == nil then return false end
	local ok, v = pcall(self.E.gameSpeed)
	v = ok and tonumber(v) or nil
	return v ~= nil and v <= 0
end

--- Turns the tick's real-time stamp (us) into the driver's running time: the time since the last tick counts as paused
--- when the game is paused now. Logs PAUSE state=on|off on a change (not while the mod is off). Returns now, paused.
function Driver:gameClock(raw)
	raw = tonumber(raw) or 0
	local paused = self:gamePausedNow()
	local last = self.clockRawUs
	if paused and last ~= nil and raw > last then self.pausedUs = (self.pausedUs or 0) + (raw - last) end
	self.clockRawUs = raw
	if paused ~= (self.gamePaused == true) then
		self.gamePaused = paused
		if paused then self.pauses = (self.pauses or 0) + 1 end
		if self.phase ~= "off" then
			self:log("PAUSE", { { "state", paused and "on" or "off" }, { "pausedS", string.format("%.0f", (self.pausedUs or 0) / 1e6) },
				{ "pauses", self.pauses or 0 }, { "at", self:costStage() } })
		end
	end
	return raw - (self.pausedUs or 0), paused
end

--- A tick while paused: nothing new starts; a build (or lock build) whose callback already came is handled, which
--- books its refund and moves the job on to its next stage, which waits for the game to run again.
function Driver:pausedTick(now, saved)
	local job = self.job
	if job == nil then return end
	if (job.stage == "wait" and job.result ~= nil) or (job.stage == "glockWait" and job.glockResult ~= nil) then
		self:advance(now, saved)
	end
end

---------------------------------------------------------------------------
-- Refunds (2026-10-17, player report: "a new game at $0 plunges into the red"). Every mod build runs with ctx.player set
-- (the crash-free setting, ot_engine.context) and is charged to the player. The driver books each charge back: the
-- player's balance at the send minus after the callback, at most the build's cost (ot_glock.refund, the §68 rule, its
-- tolerance included), booked as street construction income (ot_engine.bookStreetRefund). Growth increments, the head
-- start, frames, satellites, leads, Works links and bridges go through Driver:afterPrecheck / done (REFUND kind=build
-- line); the game-street lock rebuild through glockFire / glockWait (its GLOCK event=refund line). Each build has its own
-- send / callback window (one command in flight), so none is refunded twice. A booking sent but not yet applied counts
-- into the next send's balance (Driver:balanceAtSend), so it isn't taken for that build's charge.
D.REFUND_PENDING_S = 10    -- a booking whose callback never came stops counting after this (running time)

--- The player's balance as it will be once the refund bookings in flight have landed; nil with infinite money (or
--- no balance accessor / no booking accessor: no refund).
function Driver:balanceAtSend(now)
	local E = self.E
	if not (GL.REFUND and E.balance and E.bookStreetRefund) then return nil end
	local okB, b = pcall(E.balance)
	b = okB and tonumber(b) or nil
	if b == nil or b ~= b then return nil end
	local keep = {}
	for _, p in ipairs(self.refundsPending or {}) do
		if not p.done and now - p.us <= D.REFUND_PENDING_S * 1e6 then
			b = b + p.amount
			keep[#keep + 1] = p
		end
	end
	self.refundsPending = keep
	return b
end

--- Books the refund of one build (bal0 = Driver:balanceAtSend at the send, cost = the result's cost, else the
--- pre-check's). Returns amount (0 = none), why, bal1. kind = "build" | "glock" (session totals refundSum /
--- glockRefundSum; refundSum counts both).
function Driver:refundBuild(kind, bal0, cost, now)
	local E = self.E
	if bal0 == nil or not (E.balance and E.bookStreetRefund) then return 0, "noBalance", nil end
	local okB, b = pcall(E.balance)
	local bal1 = okB and tonumber(b) or nil
	local amount, why = GL.refund(bal0, bal1, cost)
	if amount > 0 then
		local p = { amount = amount, us = now or self:nowUs() }
		self.refundsPending = self.refundsPending or {}
		self.refundsPending[#self.refundsPending + 1] = p
		local okR, sent = pcall(E.bookStreetRefund, amount, function() p.done = true end)
		if not okR or sent == false then p.done = true end
		self.refundSum = (self.refundSum or 0) + amount
		self.refundN = (self.refundN or 0) + 1
		if kind == "glock" then self.glockRefundSum = (self.glockRefundSum or 0) + amount end
	end
	return amount, why, bal1
end

function Driver:log(what, fields)
	local l = D.line(what, fields, self.prefix)
	if self.E.log then self.E.log(l) else log.message(l) end
	return l
end

-- Frame cost (2026-10-14, real-play prep): the game script's guiUpdate times every tick (state:get() and Driver:tick)
-- and hands it to Driver:costNote; every COST_EVERY_S real seconds one TICKCOST line (always on, not debug): the ticks,
-- their mean and slowest cost, the stage of the slowest (chars / names:<phase> / job:<stage> / idle), the slowest
-- state:get() and how many ticks passed 4 / 16 / 50 ms. Nothing is logged while the mod is off. (2026-10-20: the state read
-- copies only on a change, ot_saved Reader: `getN` copies per window, `stateMode`, `revMiss`.)
D.COST_EVERY_S = 300
D.COST_MS = { 4, 16, 50 }

--- What the driver is doing now (the TICKCOST line's `at=`).
function Driver:costStage()
	if self.charPhase then return "chars" end
	if self.names then return "names:" .. tostring(self.names.phase or "?") end
	if self.job then return "job:" .. tostring(self.job.stage or "?") end
	return self.phase == "run" and "idle" or tostring(self.phase or "?")
end

--- Adds one tick's cost (us = the whole tick, getUs = its state read part, at = its stage, full = the read copied the
--- whole state (nil: counted as a full read, the old path), mode = the reader's mode, miss = its copies that disagreed
--- with the native number so far (session total), ot_saved Reader); returns the
--- TICKCOST line when the window closed, else nil. Since 2026-10-20 getUs is the change-number read plus the copy when
--- one ran: getMaxUs stays a copy's cost, getAvgUs falls with the copies (`getN` per window; `stateMode` rev | get).
function Driver:costNote(now, us, getUs, at, full, mode, miss)
	if self.phase == "off" then
		self.cost = nil
		return nil
	end
	now, us, getUs = tonumber(now) or 0, tonumber(us) or 0, tonumber(getUs) or 0
	if us ~= us or us < 0 or us == math.huge then us = 0 end
	if getUs ~= getUs or getUs < 0 or getUs == math.huge then getUs = 0 end
	local c = self.cost
	if c == nil or now < c.t0 then
		c = { t0 = now, n = 0, sum = 0, max = 0, at = "-", getMax = 0, getSum = 0, getN = 0, over = { 0, 0, 0 } }
		self.cost = c
	end
	c.n = c.n + 1
	if full ~= false then c.getN = c.getN + 1 end
	if mode ~= nil then c.mode = tostring(mode) end
	if tonumber(miss) then c.miss = tonumber(miss) end
	c.sum = c.sum + us
	if us > c.max then c.max, c.at = us, at or "-" end
	if getUs > c.getMax then c.getMax = getUs end
	c.getSum = c.getSum + getUs
	for i, ms in ipairs(D.COST_MS) do
		if us > ms * 1000 then c.over[i] = c.over[i] + 1 end
	end
	if now - c.t0 < D.COST_EVERY_S * 1e6 then return nil end
	self.cost = nil
	-- (the provenance record's size, ot_prov: copied with the state every frame; read here once a window)
	local pvB, pvN = PV.size(type(self.saved) == "table" and self.saved.pv or nil)
	return self:log("TICKCOST", { { "s", string.format("%.0f", (now - c.t0) / 1e6) }, { "ticks", c.n },
		{ "avgUs", math.floor(c.sum / math.max(1, c.n) + 0.5) }, { "maxUs", math.floor(c.max + 0.5) }, { "at", c.at },
		{ "getMaxUs", math.floor(c.getMax + 0.5) }, { "getAvgUs", math.floor(c.getSum / math.max(1, c.n) + 0.5) },
		{ "over4ms", c.over[1] }, { "over16ms", c.over[2] }, { "over50ms", c.over[3] }, { "pvB", pvB }, { "pvN", pvN }, { "getN", c.getN },
		{ "stateMode", c.mode or "get" }, { "revMiss", c.miss or "-" } })
end

--- Debug lines on? The dev tools' hook overrides the param for the session; a verbose instance (the dev
--- tools' own driver) always logs them.
function Driver:debugOn()
	if self.verbose then return true end
	if H.debug ~= nil then return H.debug == true end
	return self.opts ~= nil and self.opts.debug == true
end

function Driver:debug(what, fields)
	if self:debugOn() then return self:log(what, fields) end
	return nil
end

--- Held by the dev tools (paused, or a dev action running): no new checks, no testing growth.
function D.held()
	return H.paused == true or H.devBusy == true
end

function Driver:townState(t)
	local s = self.towns[t]
	if s == nil then
		-- own: ids of the street edges this session's builds added (with the locked edges: the town's own streets,
		-- ot_assess.lots own); ledger: the growth-demand ledger (ot_assess.demand)
		s = { exclude = {}, nExclude = 0, builds = 0, history = {}, styles = {}, own = {}, ledger = {} }
		self.towns[t] = s
	end
	return s
end

function Driver:exclude(t, key)
	local s = self:townState(t)
	if key == nil or s.exclude[key] or s.nExclude >= D.MAX_EXCLUDE then return end
	s.exclude[key] = true
	s.nExclude = s.nExclude + 1
end

function Driver:townIds(now)
	if self.townList == nil or now - self.townListUs > D.TOWNS_REFRESH_S * 1e6 then
		self.townList = self.E.towns()
		self.townListUs = now
	end
	return self.townList
end

---------------------------------------------------------------------------
-- Map edge and character towns (ot_map, 2026-10-13). The map's bounding box (E.mapBounds: api.engine.terrain.
-- getBoundingBox, pcall-guarded; nil when unknown: no edge limit), re-read every BOUNDS_REFRESH_S (the map editor can
-- resize a map); the character towns from every town's position and the bounds, redone when the town count changes.
D.BOUNDS_REFRESH_S = 600

function Driver:mapBounds(now)
	if self.boundsUs == nil or now - self.boundsUs > D.BOUNDS_REFRESH_S * 1e6 then
		self.boundsUs = now
		local b = nil
		if self.E.mapBounds then
			local ok, r = pcall(self.E.mapBounds)
			if ok and type(r) == "table" and tonumber(r[1]) and tonumber(r[4]) and r[3] > r[1] and r[4] > r[2] then b = r end
		end
		local key = b and string.format("%.0f:%.0f:%.0f:%.0f", b[1], b[2], b[3], b[4]) or "-"
		if key ~= self.boundsKey then
			self.boundsKey = key
			self:log("MAP", { { "bounds", key }, { "margin", MAP.MARGIN } })
		end
		self.bounds = b
	end
	return self.bounds
end

--- The driver that owns this session's records: the game script's main driver (ot_hooks.main) when this one shares
--- its per-town state (the dev tools' pool drivers: otd_runner poolDriver shares `towns` but not the rest), else self.
--- (2026-10-14, NEXT_PHASE_BRIEF 50 item 4, run 2026-10-14_1729 load 3: under the dev Simulate the CHARACTER line said
--- `created=0 fixed=0` at towns=19 / 21 / 22 and the picks changed: the pool drivers that ran the builds had no saved
--- state, no created-town sets and their own character cache.)
function Driver:root()
	local m = H.main
	if m ~= nil and m ~= self and type(m) == "table" and m.towns ~= nil and m.towns == self.towns then return m end
	return self
end

--- The saved state as the session's owner last read it (a pool driver never ticks: its own `saved` is nil).
function Driver:savedNow(saved)
	if type(saved) == "table" then return saved end
	if type(self.saved) == "table" then return self.saved end
	local r = self:root()
	return r.saved
end

--- The towns the mod created, from every record: the saved claims (`wk`, `dk`), this session's claimed sets and the
--- creation records on the parents' town state (a created town found by offshootCreated: `w.town`). { [id] = parent
--- id or true }.
function Driver:createdTowns(saved)
	local r = self:root()
	saved = self:savedNow(saved)
	local out = {}
	for id in pairs(SV.worksSet(saved)) do out[id] = true end
	for id, par in pairs(SV.districtSet(saved)) do out[id] = par end
	for _, d in ipairs({ self, r }) do
		for id in pairs(d.worksTowns or {}) do out[id] = out[id] or true end
		for id, par in pairs(d.districtTowns or {}) do out[id] = out[id] or par end
	end
	local n = 0
	for par, st in pairs(r.towns or {}) do
		n = n + 1
		if n > D.CREATED_SCAN_MAX then break end
		if type(st) == "table" then
			local w = st.works
			if type(w) == "table" and w.town and not w.restored then out[w.town] = out[w.town] or true end
			for i, dw in ipairs(st.districts or {}) do
				if i > 16 then break end
				if type(dw) == "table" and dw.town then out[dw.town] = out[dw.town] or par end
			end
		end
	end
	return out
end
D.CREATED_SCAN_MAX = 4000   -- town states read for creation records at most

--- The town's character entry (ot_map.characters: { character, score, rank, nnd, edgeDist }) or nil.
--- (2026-10-14, NEXT_PHASE_BRIEF 48 item 4, run 2026-10-14_0814_sqot load 3: `CHARACTER towns=16 count=2`, then
--- `towns=17 count=3` once a created town appeared, and Shanghai became a character town. Now the quota counts the
--- map's own towns only: the towns the mod created (Works, districts: isOffshootTown) are left out of the ranking and
--- never picked; and a pick stays once saved: a town whose frame saved `ch` keeps it, a town with a frame without it
--- never becomes one (ot_map.characters `fixed`).)
--- (2026-10-14, NEXT_PHASE_BRIEF 50 item 4: the cache, the created towns and the picks live on the session's owner
--- (Driver:root), the created towns come from every record (Driver:createdTowns), and a pick made this session stays
--- a pick (`charSticky`) even before its frame is saved.)
function Driver:characterOf(t, now)
	local r = self:root()
	local ids = self:townIds(now)
	local saved = self:savedNow(nil)
	local createdSet = self:createdTowns(saved)
	-- (a creation in flight: a town that appeared after it was sent and isn't identified yet is no town of the map's own)
	local n = 0
	for _, st in pairs(r.towns or {}) do
		n = n + 1
		if n > D.CREATED_SCAN_MAX then break end
		local recs = {}
		if type(st) == "table" then
			if type(st.works) == "table" then recs[1] = st.works end
			for i, dw in ipairs(st.districts or {}) do if i <= 16 then recs[#recs + 1] = dw end end
		end
		for _, w in ipairs(recs) do
			if type(w) == "table" and w.phase == "create" and type(w.before) == "table" and not w.dropped then
				for _, id in ipairs(ids) do
					if not w.before[id] and createdSet[id] == nil then createdSet[id] = "pending" end
				end
			end
		end
	end
	local nOff = 0
	for _ in pairs(createdSet) do nOff = nOff + 1 end
	r.charSticky = r.charSticky or {}
	local nSticky = 0
	for _ in pairs(r.charSticky) do nSticky = nSticky + 1 end
	-- (strong characters, ot_character 2026-10-14: a town with a strong kind is never a secluded one; its slot goes on)
	local nKind = 0
	for _ in pairs(r.charPick and r.charPick.picks or {}) do nKind = nKind + 1 end
	local key = #ids .. ":" .. nOff .. ":" .. nSticky .. ":" .. nKind
	if r.charKey ~= key or r.chars == nil then
		local list, fixed, created, nFixed = {}, {}, 0, 0
		for _, id in ipairs(ids) do
			if createdSet[id] ~= nil then
				created = created + 1
			else
				local x, y = self.E.boxCentre(id)
				if x then
					list[#list + 1] = { id, x, y }
					local fr = SV.frame(saved, id)
					if fr then fixed[id], nFixed = fr.character == true, nFixed + 1
					elseif r.charPick and r.charPick.picks and r.charPick.picks[id] then fixed[id] = false
					elseif r.charSticky[id] then fixed[id], nFixed = true, nFixed + 1 end
				end
			end
		end
		local chars, count = MAP.characters(list, self:mapBounds(now), fixed)
		for id, c in pairs(chars) do
			if c.character and not createdSet[id] then r.charSticky[id] = true end
		end
		local nS2 = 0
		for _ in pairs(r.charSticky) do nS2 = nS2 + 1 end
		r.chars, r.charN, r.charKey = chars, #list, #ids .. ":" .. nOff .. ":" .. nS2 .. ":" .. nKind
		local picks = {}
		for _, id in ipairs(ids) do
			local c = chars[id]
			if c and c.character then
				picks[#picks + 1] = string.format("%s:%.2f:nnd%.0f:edge%s%s", tostring(self.E.name(id)), c.score, c.nnd,
					c.edgeDist == math.huge and "-" or string.format("%.0f", c.edgeDist), c.saved and ":saved" or "")
			end
		end
		self:debug("CHARACTER", { { "towns", #list }, { "created", created }, { "fixed", nFixed }, { "count", count },
			{ "picks", #picks > 0 and table.concat(picks, ",") or "-" } })
	end
	-- (the naming hook, 2026-10-14: a strong-character town's entry carries its kind for the names, ot_character
	-- NAME_KIND; `character` stays false: it is no secluded town)
	local e = r.chars and r.chars[t] or nil
	if e ~= nil then
		local k = self:charKindOf(t)
		e.nameKind = k and CH.nameKind(k) or nil
	end
	return e
end

--- Coastal huggers (ot_map.coastal, 2026-10-14): the map's 1-2 towns with the most coastline take ot_form COASTAL. The
--- ranking is read once per town count (COAST_R rings around each town, the sampler's water test; character and mod-made
--- towns left out); a town whose frame saved the pick (`cs`) stays one. Returns { coastal, score, rank } or nil.
D.COASTAL = true
function Driver:coastalOf(t, now, saved)
	if not D.COASTAL then return nil end
	local fr = SV.frame(saved, t)
	if fr and fr.coastal then return { coastal = true, score = 0, rank = 0, saved = true } end
	if fr and fr.axis then return nil end   -- (a framed town keeps its form)
	local ids = self:townIds(now)
	if self.coastN ~= #ids or self.coastPicks == nil then
		local E = self.E
		local t0 = self:nowUs()
		local sm = E.sampler()
		local list = {}
		for _, id in ipairs(ids) do
			local ch = self:characterOf(id, now)
			-- (a strong-character town keeps its kind's form, ot_character 2026-10-14)
			if not (ch and ch.character) and not self:isOffshootTown(id, saved) and not self:charKindOf(id, saved) then
				local x, y = E.boxCentre(id)
				if x then list[#list + 1] = { id, x, y } end
			end
		end
		local picks, scored, n = MAP.coastal(list, function(x, y) return T.isWater(sm, x, y) end)
		self.coastPicks, self.coastN = picks, #ids
		local parts = {}
		for i, e in ipairs(scored) do
			if i > 5 then break end
			parts[#parts + 1] = string.format("%s:%.2f", tostring(E.name(e.id)), e.score)
		end
		local pk = {}
		for _, e in ipairs(scored) do
			if picks[e.id] then pk[#pk + 1] = string.format("%s:%.2f", tostring(E.name(e.id)), e.score) end
		end
		self:log("COASTAL", { { "pick", #pk > 0 and table.concat(pk, ",") or "-" }, { "n", n }, { "towns", #list },
			{ "top", #parts > 0 and table.concat(parts, ",") or "-" }, { "min", MAP.COAST_MIN }, { "us", self:nowUs() - t0 } })
	end
	return self.coastPicks[t]
end

--- STYLE field `character`: "yes:<why>" for a character town (rank / seclusion score), "no:rank=r/n" else.
function D.characterText(style, ch, n)
	local f = style.form
	local rank = ch and string.format("rank=%d/%d,score=%.2f", ch.rank or 0, n or 0, ch.score or 0) or "-"
	if f and f.character then return "yes:" .. rank end
	return "no:" .. rank
end

---------------------------------------------------------------------------
-- Strong town characters (ot_character, 2026-10-14, CHARACTERS_BRIEF / NEXT_PHASE_BRIEF 54). Once per new map, before
-- the names and the head start, phase "chars" reads every own town's terrain (the stage the names survey would run
-- anyway: nothing is read twice) and the character probe (CHARS_SLICE_US per tick, CHARS_MAX_S at most), scores the
-- kinds (CH.select) and saves the picks (EV_CHARS, map record `cm`); a town's frame saves its kind at its first build
-- (`ck`). A reload reads the saved picks; a save from before (no `cm`) never gets strong characters (`why=oldMap`), nor
-- does a map with the setting Off (`why=setting`). Deep forest keeps its own per-town pick (deepFor), the secluded
-- "character" towns their form (ot_map); a strong-kind town is neither. Log lines: `CHARACTER pick`, `CHARACTER town=`
-- (event pick / apply), `RB` (one-way rings), `DENSIFY`.
D.CHARS = true
D.CHARS_SLICE_US = 6000    -- us per tick for the chars phase's reads
D.CHARS_MAX_S = 90         -- the phase ends after this (the towns read so far are scored)

--- Is the strong-characters setting on? (the main mod's "Strong town characters"; pool drivers read the root's)
function Driver:charsOn()
	if not (D.CHARS and CH.ON) then return false end
	local o = self.opts or self:root().opts
	return not (o and o.strongCharacters == false)
end

--- Sets up the chars phase at the run start, or the saved / no picks (CHARACTER pick line).
function Driver:charsStart(now, saved)
	local r = self:root()
	if not (D.CHARS and CH.ON) then return end
	if not self:charsOn() then
		r.charPick = { done = true, picks = {}, why = "setting" }
		self:log("CHARACTER pick", { { "on", false }, { "why", "setting" } })
		return
	end
	local savedPicks, has = SV.chars(saved)
	if has then
		local picks = {}
		for t, k in pairs(savedPicks) do
			local kind = CH.byIndex(k)
			if kind then picks[t] = { kind = kind.id, score = 1, why = "saved", fixed = true } end
		end
		r.charPick = { done = true, picks = picks, why = "saved" }
		self:charPickLine(picks, nil, "saved", nil)
		return
	end
	if self.newMap ~= true then
		r.charPick = { done = true, picks = {}, why = "oldMap" }
		self:log("CHARACTER pick", { { "on", false }, { "why", "oldMap" } })
		return
	end
	self.charPhase = { i = 0, startUs = now, sites = {} }
end

--- One chars step (true while the phase runs: the names, the head start and the checks wait).
function Driver:charsTick(now)
	local c = self.charPhase
	if c == nil then return false end
	local ok, err = D.guard(self:clockFn(), D.STAGE_HANG_US, self.charsStep, self, c, now)
	if not ok then
		self:log("ERROR", { { "stage", "chars" }, { "err", err } })
		self:charsFinish(c, now, "error")
	end
	return self.charPhase ~= nil
end

function Driver:charsStep(c, now)
	local E = self.E
	if c.ids == nil then
		c.ids = {}
		local created = self:createdTowns(self.saved)
		for _, t in ipairs(self:townIds(now)) do
			if #c.ids >= CH.TOWNS_MAX then break end
			if created[t] == nil then c.ids[#c.ids + 1] = t end
		end
		local year = E.year and E.year() or 1960
		c.year = year
		c.inp = I.build({ nameList = self.cfg and self.cfg.nameList, climate = self.cfg and self.cfg.climate, year = year,
			styleRegion = self.opts and self.opts.styleRegion })
		c.rbOk, c.rbWhy = self:rbGeo()
		return
	end
	local t0 = self:nowUs()
	local n = 0
	while c.i < #c.ids do
		if n > 0 and self:nowUs() - t0 > D.CHARS_SLICE_US then return end
		if now - c.startUs > D.CHARS_MAX_S * 1e6 then
			c.capped = true
			break
		end
		c.i = c.i + 1
		n = n + 1
		local t = c.ids[c.i]
		local x, y = E.boxCentre(t)
		if x then
			local s = self:townState(t)
			if s.stats == nil then self:terrain({ town = t, ext = { cx = x, cy = y, r = 0 }, stage = "terrain" }) end
			if s.stats and s.pos then
				c.sites[#c.sites + 1] = self:charSite(t, s, c, now)
			end
		end
	end
	self:charsFinish(c, now, c.capped and "timeout" or "ok")
end

--- The CH.site record of town t (state s already read: stats, wide, pos).
function Driver:charSite(t, s, c, now)
	local E = self.E
	local dr = s.stats.dirRelief
	local okP, pr = pcall(CH.probe, E.sampler(), s.pos[1], s.pos[2], (dr and dr.valley) and dr.axis or nil)
	local okF, feats = pcall(SITE.features, s.stats, s.wide)
	local caps = E.townCaps and E.townCaps(t) or nil
	local inp = c.inp or {}
	local nb = self:neighbours(t, s.pos)
	return CH.site({ id = t, x = s.pos[1], y = s.pos[2], stats = s.stats, wide = s.wide, feats = okF and feats or {},
		probe = okP and pr or nil, year = c.year, era = inp.era, region = inp.region, country = inp.country,
		climate = inp.climate, newTemplates = I.newTemplates(c.year), cap = caps and caps.target or 0,
		industry = self:charIndustry(s.pos[1], s.pos[2], now), rbOk = c.rbOk ~= nil,
		nnd = nb and nb[1] and nb[1].dist or nil, probeErr = (not okP) and tostring(pr) or nil })
end

--- The nearest heavy / medium industry within ot_character COMPANY_R of (x, y): { d, kind, x, y, file } or nil.
function Driver:charIndustry(x, y, now)
	local E = self.E
	if E.industries == nil then return nil end
	if self.indAll == nil then
		local okL, all = pcall(E.industries)
		self.indAll, self.indAllUs = okL and all or {}, now
	end
	local best = nil
	for i, it in ipairs(self.indAll or {}) do
		if i > 4000 then break end
		-- (ot_engine.industries returns { x, y, file =, e = } arrays; until §62 this read it.x / it.y only, so no town was
		-- ever a company town: every CHARACTER line said noIndustry. Both forms are read now.)
		local ix = type(it) == "table" and tonumber(it[1] or it.x) or nil
		local iy = type(it) == "table" and tonumber(it[2] or it.y) or nil
		if ix and iy then
			local kind = IND.classify(it.file)
			if kind == "heavy" or kind == "medium" then
				local d = G.dist(x, y, ix, iy)
				if d <= CH.COMPANY_R and (best == nil or d < best.d) then
					best = { d = d, kind = kind, x = ix, y = iy, file = it.file }
				end
			end
		end
	end
	return best
end

--- Left-hand traffic? (2026-10-20, the Left Hand Traffic mod: ot_engine.driveSide from the loaded street templates),
--- once per session on the root driver, with one DRIVE line. Junction lane connections are mirrored then
--- (ot_proposal.junctionConns) and the one-way rings stay off (rbGeo "leftHand": they run counter-clockwise).
function Driver:leftHand()
	local r = self:root()
	if r.driveSide == nil then
		local side, from = "right", nil
		if self.E.driveSide then
			local ok, s1, s2 = pcall(self.E.driveSide, PR.leftHandFrom)
			if ok and (s1 == "left" or s1 == "right") then side, from = s1, s2 end
		end
		r.driveSide = side
		self:log("DRIVE", { { "side", side }, { "from", from or "default" } })
	end
	return r.driveSide == "left"
end

--- The one-way ring geometry (ot_ring.load: square_roundabouts' sizes), once per session on the root driver.
function Driver:rbGeo()
	local r = self:root()
	if r.rbGeoTried == nil and self:leftHand() then
		r.rbGeoTried, r.rbGeoData, r.rbGeoWhy = true, nil, "leftHand"
	end
	if r.rbGeoTried == nil then
		r.rbGeoTried = true
		local okL, geo, why = pcall(RG.load, ug_require)
		if okL then r.rbGeoData, r.rbGeoWhy = geo, why else r.rbGeoData, r.rbGeoWhy = nil, "error" end
	end
	return r.rbGeoData, r.rbGeoWhy
end

--- Ends the chars phase: the pick, its lines, the saved record.
function Driver:charsFinish(c, now, why)
	local E = self.E
	local r = self:root()
	self.charPhase = nil
	local excluded, fixed = {}, {}
	for _, st in ipairs(c.sites) do
		-- (a secluded town of ot_map may take a strong kind: the kind wins, and the secluded quota passes to the next
		-- most secluded town, characterOf; a framed secluded town keeps its form: its frame says no kind)
		local fr0 = SV.frame(self.saved, st.id)
		if fr0 and fr0.character then excluded[st.id] = "secluded"
		elseif (st.cap or 0) >= CH.METRO_CAP then excluded[st.id] = "metro" end
		local fr = SV.frame(self.saved, st.id)
		if fr then
			local k = fr.charKind and CH.byIndex(fr.charKind)
			fixed[st.id] = k and k.id or false
		end
	end
	local okS, picks, count, rows = pcall(CH.select, c.sites, { fixed = fixed, excluded = excluded,
		seed = CH.mapSeed(c.sites) })
	if not okS then
		self:log("ERROR", { { "stage", "charSelect" }, { "err", picks } })
		picks, count, rows = {}, 0, {}
	end
	r.charPick = { done = true, picks = picks, why = why, count = count }
	for _, st in ipairs(c.sites) do self:townState(st.id).charSite = st end
	for _, row in ipairs(rows) do
		-- (every selectable kind's score and why: the 2026-10-14 seed-a run's top-3 hid why the others scored 0)
		local cands, whys = {}, {}
		for _, sc in ipairs(row.scores or {}) do
			cands[#cands + 1] = string.format("%s:%.2f", sc.kind, sc.score)
			whys[#whys + 1] = sc.kind .. "=" .. tostring(sc.why or "-"):gsub("[%s;]", "_")
		end
		local f = { { "town", row.id }, { "name", E.name(row.id) }, { "event", "pick" }, { "kind", row.picked and row.kind or "-" },
			{ "score", string.format("%.2f", row.score or 0) }, { "why", row.why or "-" },
			{ "applied", row.picked and "pending" or ("no:" .. tostring(row.skip or "-")) }, { "best", row.kind or "-" },
			{ "top", #cands > 0 and table.concat(cands, ",") or "-" }, { "whys", #whys > 0 and table.concat(whys, ";") or "-" } }
		if row.picked then self:log("CHARACTER", f) else self:debug("CHARACTER", f) end
	end
	self:charPickLine(picks, count, why, #c.sites, c)
	local list = {}
	for t, p in pairs(picks) do list[#list + 1] = { t = t, k = CH.INDEX[p.kind] } end
	table.sort(list, function(a, b) return a.t < b.t end)
	if E.sendEvent then E.sendEvent(SV.EVENT_ID, SV.EV_CHARS, { p = list }) end
end

--- The CHARACTER pick line: map seed, towns, quota, the picks (kind:name), the ring geometry.
function Driver:charPickLine(picks, count, src, towns, c)
	local E = self.E
	local parts = {}
	for t, p in pairs(picks or {}) do parts[#parts + 1] = string.format("%s:%s", p.kind, tostring(E.name(t))) end
	table.sort(parts)
	local rb, rbWhy = self:rbGeo()
	self:log("CHARACTER pick", { { "on", true }, { "map", c and CH.mapSeed(c.sites) or "-" }, { "towns", towns or "-" },
		{ "count", count or "-" }, { "picked", #parts }, { "kinds", #parts > 0 and table.concat(parts, ",") or "-" },
		{ "src", src or "-" }, { "rings", rb and "yes" or ("no:" .. tostring(rbWhy)) },
		{ "read", c and c.i or "-" }, { "s", c and string.format("%.1f", (self:nowUs() - c.startUs) / 1e6) or "-" } })
end

--- The strong character kind of town t (ot_character id) or nil: the dev force first, then the saved frame (`ck`; a
--- frame without it: none, for good), then the map's pick. Off with the setting.
function Driver:charKindOf(t, saved)
	local s = self.towns and self.towns[t]
	if s and s.forceChar then return s.forceChar end
	if not self:charsOn() then return nil end
	local fr = SV.frame(saved or self:savedNow(nil), t)
	if fr then
		local k = fr.charKind and CH.byIndex(fr.charKind)
		return k and k.id or nil
	end
	local r = self:root()
	local p = r.charPick and r.charPick.picks and r.charPick.picks[t]
	return p and p.kind or nil
end

--- The naming hook (2026-10-14, for the naming phase to wire in): { kind, tag, words } of town t's strong character
--- (ot_character.nameCue; deep forest towns too), or nil.
function Driver:characterNameCue(t, saved)
	local k = self:charKindOf(t, saved)
	if k == nil and self:isDeepTown(t, saved) then k = "deep_forest" end
	return k and CH.nameCue(k) or nil
end

--- Dev (OT Dev Town tab "Force character"): town t plans as kind `kind` (an ot_character id, or "densify": the densify
--- trait active now, or nil: back to the pick) from its next snapshot. Session only.
function Driver:devCharacter(t, kind)
	local s = self:townState(t)
	if kind == "densify" then
		s.forceDense = true
	elseif kind == nil or kind == "-" then
		s.forceChar, s.forceDense = nil, nil
	elseif CH.BY_ID[kind] and kind ~= "deep_forest" then
		s.forceChar = kind
	elseif kind == "deep_forest" then
		return self:devDeep(t, true) and "deep_forest" or nil
	end
	s.styles = {}
	s.charLogged = nil
	return s.forceChar or (s.forceDense and "densify") or "-"
end

--- Is the densify trait active for town t (drawn, saved / this session, and the town mature; or the dev force)?
function Driver:densifyActive(t, saved)
	local s = self.towns and self.towns[t]
	if s and s.forceDense then return true end
	if not (self:charsOn() and CH.DZ_ON) then return false end
	local dz = s and s.dz
	if dz == nil then
		local fr = SV.frame(saved or self:savedNow(nil), t)
		dz = fr and fr.densify or nil
	end
	return dz == 1 and s ~= nil and (s.mat or 0) >= CH.DZ_MAT
end

--- Is town t a drawn densify town (whatever its maturity; or the dev force)? The level weights ramp its effect in by
--- the level maturity (ot_upward.levelPhase "densify").
function Driver:densifyDrawn(t, saved)
	local s = self.towns and self.towns[t]
	if s and s.forceDense then return true end
	if not (self:charsOn() and CH.DZ_ON) then return false end
	local dz = s and s.dz
	if dz == nil then
		local fr = SV.frame(saved or self:savedNow(nil), t)
		dz = fr and fr.densify or nil
	end
	return dz == 1
end

--- The densify draw and its DENSIFY lines (after a check's measure m): drawn once per town when it first reads half
--- grown (CH.DZ_MAT of the level maturity, ot_upward.levelMat: persons or buildings, 2026-10-15), on a map with strong
--- characters (picked this session or saved), saved on the frame (EV_DENSE). (Run 2026-10-14_2347_sqot-dev: no town drew
--- during the dev Simulate: its pool drivers have no `saved` of their own, so the frame read nil; now savedNow.)
function Driver:densifyCheck(t, m, now)
	if not (self:charsOn() and CH.DZ_ON) or m == nil then return end
	local E = self.E
	local s = self:townState(t)
	local mat = m.dem and m.dem.mat or nil
	if mat ~= nil then mat = UP.levelMat(mat, m.buildings) end
	if mat ~= nil then s.mat = mat end
	local r = self:root()
	local cp = r.charPick
	if not s.forceDense and not (cp and cp.done and cp.why ~= "oldMap" and cp.why ~= "setting") then return end
	local fr = SV.frame(self:savedNow(nil), t)
	if s.dz == nil and fr and fr.densify then s.dz = fr.densify end
	local pb = (m.buildings or 0) > 0 and m.caps and (m.caps.actual or 0) / m.buildings or nil
	if s.dz == nil and fr ~= nil and (mat or 0) >= CH.DZ_MAT then
		local blocked = nil
		if self:charKindOf(t) then blocked = "character"
		elseif self:isDeepTown(t) then blocked = "deep"
		elseif fr.character then blocked = "secluded"
		elseif fr.coastal then blocked = "coastal"
		elseif self:isOffshootTown(t, self.saved) then blocked = "created"
		elseif (m.caps and m.caps.target or 0) >= D.METRO_MIN_CAP then blocked = "metro" end
		local b = self:mapBounds(now)
		local central = 0.5
		if b and s.pos then
			local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
			local half = math.max(1, G.dist(b[1], b[2], b[3], b[4]) / 2)
			central = G.clamp(1 - G.dist(cx, cy, s.pos[1], s.pos[2]) / half, 0, 1)
		end
		local persons = m.caps and m.caps.actual or 0
		local sizeRank = G.clamp(math.log(math.max(1, persons) / A.MAT_LO) / math.log(8), 0, 1)
		local okR, st = pcall(self.stationsFor, self, t, now, m.ext)
		local rail = okR and type(st) == "table" and #st > 0
		local form = s.pick and s.pick.form or nil
		local pos = s.pos or { m.ext.cx, m.ext.cy }
		local on, why, p = CH.densifyDraw({ seed = RNG.seed(t, pos[1], pos[2]), dv = fr.drawV or 1, form = form, sizeRank = sizeRank,
			central = central, rail = rail, blocked = blocked })
		s.dz = on and 1 or 2
		if E.sendEvent then E.sendEvent(SV.EVENT_ID, SV.EV_DENSE, { town = t, v = s.dz }) end
		self:log("DENSIFY", { { "town", t }, { "name", E.name(t) }, { "event", "draw" }, { "on", on }, { "why", why },
			{ "p", string.format("%.2f", p or 0) }, { "mat", string.format("%.2f", mat or 0) }, { "form", form or "-" },
			{ "rail", rail == true }, { "central", string.format("%.2f", central) }, { "size", string.format("%.2f", sizeRank) },
			{ "core", "-" }, { "levels", s.lvK or 0 }, { "pb", pb and string.format("%.2f", pb) or "?" } })
	end
	if self:densifyActive(t) and not s.dzLogged then
		s.dzLogged = true
		s.styles = {}
		self:log("DENSIFY", { { "town", t }, { "name", E.name(t) }, { "event", "apply" }, { "on", true },
			{ "why", s.forceDense and "force" or "mature" }, { "mat", string.format("%.2f", mat or 0) },
			{ "core", string.format("%.0f", UP.coreR(m.ext and m.ext.r or 0)) }, { "levels", s.lvK or 0 },
			{ "pb", pb and string.format("%.2f", pb) or "?" }, { "hold", CH.DZ_HOLD_FREE }, { "pbAim", UP.DZ_PB_AIM } })
	end
end

--- One-way rings in a town's increment (ot_ring.mark): RB lines. The roundabout town at its own high shares (RG.townShare:
--- gateways, pairs, up to RG.TOWN.max a plan); every other town at its era / region rate (RG.rate, 2026-10-14 §56: rare
--- before 1960, common in France / Europe from the 1970s, few in the US, none in JP dense towns), at most RG.ORDINARY
--- rings a plan and per town (counted in the graph); never on satellite / bridge / lead / Works / frame plans. The rings
--- come out again on a refused pre-check (send stage, RING_MAX_REFUSED per town).
D.RINGS = true
D.RING_MAX_REFUSED = 3
D.STUCK_AT = 6          -- (§59) the STUCK line: after this many empty plans in a row, then every STUCK_EVERY more
D.STUCK_EVERY = 10
D.FORCED_EMPTY = true   -- forced increments keep the own empty budget (floored) and the sparse-street hold (§57)
function Driver:ringMark(job, inc)
	local st = job.style
	if not (D.RINGS and RG.ON) or st == nil or inc == nil or job.ringsStripped then return end
	if job.satPlan or job.bridgePlan or job.leadPlan or job.worksPlan or job.framePlan then return end
	local t, E = job.town, self.E
	local s = self:townState(t)
	if s.ringOff then return end
	local town = st.rings ~= nil
	local share, swhy
	if town then
		share = RG.townShare(st.rings)
	else
		share, swhy = RG.rate({ year = st.year, region = st.region, country = st.country, style = st.id })
	end
	local geo, gwhy = self:rbGeo()
	local why = nil
	if geo == nil then why = "noRoundabouts:" .. tostring(gwhy)
	elseif not st.newTemplates then why = "era"
	elseif share == nil then why = "rate:" .. tostring(swhy) end
	local existing = (why == nil) and RG.existing(job.g) or {}
	if why == nil and share.cap and #existing >= share.cap then why = "cap:" .. #existing end
	if why then
		if s.ringWhy ~= why then
			s.ringWhy = why
			-- (the roundabout town's reasons always; an ordinary town's in the debug log)
			local fields = { { "town", t }, { "name", E.name(t) }, { "event", "off" }, { "why", why }, { "roundaboutTown", town } }
			if town then self:log("RB", fields) else self:debug("RB", fields) end
		end
		return
	end
	local maxN = share.max or RG.MAX_PER_INC
	if share.cap then maxN = math.min(maxN, share.cap - #existing) end
	local hidx = SEL.housedIndexM(job.g, RG.ARM_LEAD)
	local seed = st.seed or 1
	-- (a deferred pair, saved on the frame: read once a session)
	if s.rbPending == nil then
		local fr = SV.frame(self.saved, t)
		s.rbPending = (fr and fr.pendingPair) or false
	end
	local pending = s.rbPending or nil
	local okM, res = pcall(RG.mark, inc, { geo = geo, g = job.g, share = share, max = maxN, centre = st.centre,
		radius = st.radius, existing = existing, armLead = RG.ARM_LEAD, pending = pending,
		-- (§57 round 2: the twin is kept in memory and saved on the frame when there is one; the 2347 run's hubs came
		-- before / without a readable frame, so no twin was ever reserved)
		canDefer = true,
		-- (the roundabout town's hubs, §57: the new arms' templates and their ends' height)
		templates = st.templatePaths, height = job.sampler and function(x, y) return T.height(job.sampler, x, y) end or nil,
		housedDist = hidx and function(x, y) return SEL.housedDist(hidx, x, y) end or nil,
		draw = function(x, y, tag)
			local k = (tag == nil or tag == "ring") and "rb" or ("rb" .. tostring(tag))
			return RNG.unit(seed, k, math.floor(x / 10), math.floor(y / 10))
		end })
	if not okM then
		self:log("WARN", { { "stage", "ring" }, { "town", t }, { "err", res } })
		RG.strip(inc)
		return
	end
	-- the deferred pair: placed (or not: one plan less, gone after RG.PAIR_WAIT), a new reservation; saved on the frame
	local function savePending(p)
		s.rbPending = p or false
		if E.sendEvent then
			E.sendEvent(SV.EVENT_ID, SV.EV_PAIR, p and { town = t, x = p.x, y = p.y, h = p.h, r = p.R, n = p.n, k = p.k }
				or { town = t, n = 0 })
		end
	end
	local dp = res.deferred
	if pending and dp then
		if dp.ok then
			savePending(nil)
		else
			local n = (pending.n or 1) - 1
			savePending(n > 0 and { x = pending.x, y = pending.y, h = pending.h, R = pending.R, n = n, k = pending.k } or nil)
			if n <= 0 then dp.why = "expired:" .. tostring(dp.why) end
		end
		local fields = { { "town", t }, { "name", E.name(t) }, { "event", "pair" }, { "kind", dp.kind or "street" }, { "deferred", true },
			{ "ok", dp.ok }, { "size", dp.size or "-" }, { "R", dp.R and string.format("%.0f", dp.R) or "-" },
			{ "d", dp.d and dp.d < math.huge and string.format("%.0f", dp.d) or "-" }, { "why", dp.why or "-" },
			{ "left", s.rbPending and s.rbPending.n or 0 }, { "hub", dp.hub == true } }
		if dp.ok or not s.rbPending then self:log("RB", fields) else self:debug("RB", fields) end
	end
	if res.pending then
		savePending(res.pending)
		job.rbNewPending = true
		self:log("RB", { { "town", t }, { "name", E.name(t) }, { "event", "pairWait" }, { "x", string.format("%.0f", res.pending.x) },
			{ "y", string.format("%.0f", res.pending.y) }, { "heading", string.format("%.0f", math.deg(res.pending.h)) },
			{ "R", string.format("%.0f", res.pending.R) }, { "plans", res.pending.n },
			{ "kind", res.pending.k == 2 and "opposite" or "street" } })
	end
	local pr = res.pair
	if pr then
		local fields = { { "town", t }, { "name", E.name(t) }, { "event", "pair" }, { "kind", pr.kind }, { "ok", pr.ok },
			{ "size", pr.size or "-" }, { "R", pr.R and string.format("%.0f", pr.R) or "-" }, { "d", string.format("%.0f", pr.d or 0) },
			{ "x1", string.format("%.0f", pr.x1) }, { "y1", string.format("%.0f", pr.y1) }, { "x2", string.format("%.0f", pr.x2) },
			{ "y2", string.format("%.0f", pr.y2) }, { "why", pr.why or "-" }, { "rate", string.format("%.3f", share.pair or 0) } }
		if pr.ok then self:log("RB", fields) else self:debug("RB", fields) end
	end
	for _, rc in ipairs(res.rings) do
		self:log("RB", { { "town", t }, { "name", E.name(t) }, { "event", "ring" }, { "size", rc.class or rc.size },
			{ "R", string.format("%.0f", rc.R or 0) }, { "ring", RG.text(rc) }, { "wanted", rc.wanted or "-" },
			{ "gate", rc.gate == true }, { "pair", rc.pair or "-" }, { "hub", rc.hub == true }, { "fell", rc.fell or "-" },
			{ "x", string.format("%.0f", rc.centre[1]) }, { "y", string.format("%.0f", rc.centre[2]) }, { "oneway", true },
			{ "ringEdges", #rc.keys }, { "nodes", rc.nodes }, { "edges", #inc.edges }, { "roundaboutTown", town },
			{ "rate", string.format("%.3f", share.main or 0) } })
	end
	-- the roundabout town's ring hubs (ot_ring §57): where, which size, a gateway, its arms, a twin reserved
	for _, hb in ipairs(res.hubs or {}) do
		local rc = hb.rec
		self:log("RB", { { "town", t }, { "name", E.name(t) }, { "event", "hub" }, { "size", rc.class or "-" },
			{ "R", string.format("%.0f", rc.R or 0) }, { "wanted", rc.wanted or "-" }, { "gate", hb.site.gate == true },
			{ "street", hb.site.cls or "-" }, { "arms", rc.hubArms or 0 }, { "split", hb.site.edge ~= nil },
			{ "partner", hb.partner == true }, { "reserved", hb.reserved or "-" },
			{ "x", string.format("%.0f", rc.centre[1]) }, { "y", string.format("%.0f", rc.centre[2]) } })
	end
	for _, sk in ipairs(res.skipped) do
		self:debug("RB", { { "town", t }, { "event", "skip" }, { "why", sk.why }, { "class", sk.class or "-" }, { "arms", sk.arms },
			{ "main", sk.main }, { "x", string.format("%.0f", sk.x) }, { "y", string.format("%.0f", sk.y) } })
	end
	s.rbPlanned = (s.rbPlanned or 0) + #res.rings
end

--- CHARACTER event=apply: once per town, kind and session, what the kind changed (applied=yes, or partial:<what> when a
--- dev-forced form / shape or the NA grid setting kept part of it).
function Driver:charApplyLine(t, kind, style)
	local s = self:townState(t)
	if s.charLogged == kind then return end
	s.charLogged = kind
	local miss = {}
	if style.charKind ~= kind then miss[#miss + 1] = "knobs" end
	if CH.formFor(kind) and not (style.form and style.form.charKind == kind) then miss[#miss + 1] = "form" end
	if style.styleSource ~= "character" and style.styleSource ~= "saved" then miss[#miss + 1] = "style:" .. tostring(style.styleSource) end
	local r = self:root()
	local p = r.charPick and r.charPick.picks and r.charPick.picks[t]
	self:log("CHARACTER", { { "town", t }, { "name", self.E.name(t) }, { "event", "apply" }, { "kind", kind },
		{ "score", p and string.format("%.2f", p.score or 0) or (s.forceChar and "force" or "saved") },
		{ "why", p and p.why or (s.forceChar and "force" or "frame") },
		{ "applied", #miss == 0 and "yes" or ("partial:" .. table.concat(miss, "/")) }, { "style", style.id },
		{ "form", style.form and style.form.id or "-" }, { "shape", style.shape and style.shape.id or "-" },
		{ "block", style.block and string.format("%.0fx%.0f", style.block.len, style.block.depth) or "-" },
		{ "motifs", D.motifText(style) }, { "rings", style.rings and "on" or "-" }, { "err", style.charErr or "-" } })
end

--- The densify town's demand brake (ot_assess.demand `dz`) or nil.
function Driver:densifyDemand(t)
	-- (2026-10-15: ramping in from the draw, half grown, to UP.DZ_RAMP_MAT: the plain mature hold's line and cap -> the
	-- densify ones)
	if self:densifyActive(t) then
		local s = self.towns and self.towns[t]
		local e = s and s.forceDense and 1 or CH.dzRamp(s and s.mat or 1)
		return { holdFree = G.lerp(A.MATURE_HOLD_FREE, CH.DZ_HOLD_FREE, e), demK = G.lerp(A.MATURE_DEMK, CH.DZ_DEMK, e) }
	end
	return nil
end

--- ALLTOWN (dev) / summary text of a town's strong character: "<kind or ->[+densify]/rb=<built>".
function Driver:charTownText(t)
	local s = self.towns and self.towns[t]
	local k = self:charKindOf(t)
	if k == nil and self:isDeepTown(t) then k = "deep_forest" end
	return CH.text(k, self:densifyActive(t)), (s and s.rbBuilt) or 0
end

--- Industries near town t (ot_industry.forTown, or nil when there are none): the map's list is read once per
--- IND_REFRESH_S (industries rarely change: one listing for all towns), each town's share recomputed when the list
--- was re-read. An industry file name the classifier doesn't know is logged once per session (IND unknown).
--- Player facilities (harbors, airports, depots, freight stations: ot_industry FAC_KINDS, soft only) join the info:
--- re-read every FAC_REFRESH_S (debug line `FAC`), the towns' share redone only when the classified list changed.
function Driver:industryFor(t, now, ext)
	local E = self.E
	if not IND.ON or (E.industries == nil and E.facilities == nil) then return nil end
	self:facilitiesRead(now)
	if E.industries == nil then
		self.indAll, self.indVer = self.indAll or {}, self.indVer or 1
	elseif self.indAll == nil or now - (self.indAllUs or 0) > D.IND_REFRESH_S * 1e6 then
		local t0 = self:nowUs()
		local okL, all = pcall(E.industries)
		self.indAll = okL and all or {}
		self.indAllUs = now
		self.indVer = (self.indVer or 0) + 1
		self:debug("IND", { { "industries", #self.indAll }, { "ok", okL and all ~= nil }, { "us", self:nowUs() - t0 } })
	end
	local s = self:townState(t)
	-- (the read reaches the town's radius + IND.ZONE_REACH: a grown town meets the industries out there, run
	-- 2026-10-13_2240_sqot-dev; recomputed when the radius moved by 250 m)
	local reach = math.max(IND.SEARCH_R, ((ext and ext.r) or s.indR or 0) + IND.ZONE_REACH)
	local rKey = math.floor(reach / 250)
	if s.indVer ~= self.indVer or s.indRKey ~= rKey or s.facVer ~= self.facVer then
		local cx, cy
		if s.pos then cx, cy = s.pos[1], s.pos[2] else cx, cy = E.boxCentre(t) end
		if cx == nil and ext then cx, cy = ext.cx, ext.cy end
		if cx == nil then return s.ind end
		local info, unknown = IND.forTown(self.indAll, cx, cy, E.year(), reach, self.facAll)
		s.ind, s.indVer, s.indRKey, s.facVer = info, self.indVer, rKey, self.facVer
		if ext and ext.r then s.indR = ext.r end
		self.indUnknown = self.indUnknown or {}
		for file in pairs(unknown or {}) do
			if not self.indUnknown[file] then
				self.indUnknown[file] = true
				self:log("IND unknown", { { "file", file }, { "kind", "medium" } })
			end
		end
	end
	return s.ind
end

--- The map's player facilities (E.facilities, ot_industry.classifyFacility; unverified in game), re-read every
--- FAC_REFRESH_S: self.facAll keeps the classified ones; self.facVer moves only when that list changed (a new or removed
--- depot / harbor / airport / freight station), so the towns' info and the planner's caches stay put otherwise.
function Driver:facilitiesRead(now)
	local E = self.E
	if not IND.FAC_ON or E.facilities == nil then
		self.facAll = nil
		return
	end
	if self.facAllUs ~= nil and now - self.facAllUs <= D.FAC_REFRESH_S * 1e6 then return end
	local t0 = self:nowUs()
	local okL, all = pcall(E.facilities)
	self.facAllUs = now
	local keep, parts, counts = {}, {}, {}
	if okL and type(all) == "table" then
		for i, it in ipairs(all) do
			if i > 20000 then break end
			local kind = IND.classifyFacility(it)
			local x, y = tonumber(it[1] or it.x), tonumber(it[2] or it.y)
			if kind and x and y then
				keep[#keep + 1] = it
				counts[kind] = (counts[kind] or 0) + 1
				parts[#parts + 1] = string.format("%s:%.0f:%.0f", kind, x, y)
			end
		end
	end
	table.sort(parts)
	local sig = table.concat(parts, ";")
	if sig ~= self.facSig then
		self.facSig, self.facAll = sig, keep
		self.facVer = (self.facVer or 0) + 1
		self:debug("FAC", { { "facilities", #keep }, { "port", counts.port or 0 }, { "airport", counts.airport or 0 },
			{ "heliport", counts.heliport or 0 }, { "depot", counts.depot or 0 }, { "freight", counts.freight or 0 },
			{ "read", okL and type(all) == "table" and #all or -1 }, { "ok", okL and all ~= nil },
			{ "us", self:nowUs() - t0 } })
	end
end

--- Rail passenger stations near town t (M3 station quarter, ot_motif_town; E.railStations, unverified in game): the
--- map's list is read once per STATION_REFRESH_S (stations appear over time), each town's share (within STATION_REACH)
--- recomputed when the list was re-read, with every kept station's tracks (E.obstacles, STATION_TRACKS_R). Debug lines
--- `STATIONS stations=` per listing and `STATIONS town=` when a town's stations change. Returns the list (may be empty)
--- or nil (no reader).
function Driver:stationsFor(t, now, ext)
	local E = self.E
	if not TW.ON or E.railStations == nil then return nil end
	if self.stAll == nil or now - (self.stAllUs or 0) > D.STATION_REFRESH_S * 1e6 then
		local t0 = self:nowUs()
		local okL, all = pcall(E.railStations)
		self.stAll = (okL and type(all) == "table") and all or {}
		self.stAllUs = now
		self.stVer = (self.stVer or 0) + 1
		local dirs = 0
		for _, st in ipairs(self.stAll) do if st.fx then dirs = dirs + 1 end end
		self:debug("STATIONS", { { "stations", #self.stAll }, { "dirs", dirs }, { "ok", okL and all ~= nil },
			{ "err", okL and "-" or tostring(all) }, { "us", self:nowUs() - t0 } })
	end
	local s = self:townState(t)
	if s.stVer ~= self.stVer then
		local cx, cy
		if s.pos then cx, cy = s.pos[1], s.pos[2] elseif ext then cx, cy = ext.cx, ext.cy end
		if cx == nil then return s.stations end
		local near = {}
		for _, st in ipairs(self.stAll) do
			if st.x and st.y and G.dist(cx, cy, st.x, st.y) <= D.STATION_REACH then near[#near + 1] = st end
		end
		table.sort(near, function(a, b) return G.dist(cx, cy, a.x, a.y) < G.dist(cx, cy, b.x, b.y) end)
		for _, st in ipairs(near) do
			if st.tracks == nil then
				st.tracks = {}
				if E.obstacles then
					local okO, ob = pcall(E.obstacles, st.x, st.y, D.STATION_TRACKS_R)
					if okO and ob then
						for _, sg in ipairs(ob.segs or {}) do
							if sg.kind == "track" then st.tracks[#st.tracks + 1] = { sg[1], sg[2], sg[3], sg[4] } end
						end
					end
				end
			end
		end
		local key = TW.stationKey(near)
		if key ~= (s.stKey or "") then
			local n1 = near[1]
			self:debug("STATIONS", { { "town", t }, { "n", #near },
				{ "nearest", n1 and string.format("%.0f@%.0f", G.dist(cx, cy, n1.x, n1.y),
					math.deg(G.wrap(G.heading(cx, cy, n1.x, n1.y))) % 360) or "-" },
				{ "front", n1 and (n1.fx and string.format("%.2f,%.2f", n1.fx, n1.fy) or "unknown") or "-" },
				{ "tracks", n1 and #(n1.tracks or {}) or 0 }, { "file", n1 and n1.file or "-" } })
		end
		s.stations, s.stVer, s.stKey = near, self.stVer, key
	end
	return s.stations
end

---------------------------------------------------------------------------
-- init

--- Region/climate from runFn's global (only runFn gets them, findings "Organic Towns probe").
function Driver:readConfig()
	local cfg = self.E.global(D.CONFIG_GLOBAL)
	if type(cfg) ~= "table" then return {} end
	return { nameList = cfg.nameList, climate = cfg.climate }
end

--- Params, region/climate and the map's profile (no log line). Returns the map-level inputs.
function Driver:loadConfig()
	local mine, all = self.E.modParams()
	self.opts = PA.parse(mine, all)
	self.cfg = self:readConfig()
	local inputs = I.build({ nameList = self.cfg.nameList, climate = self.cfg.climate, year = self.E.year(),
		styleRegion = self.opts.styleRegion })
	-- the style region (the "Town style" setting, else the name list, else the climate) and the name list's own
	-- region, which the names follow whatever the setting (nameCls)
	self.region, self.nameRegion = inputs.region, inputs.nameRegion
	self.profile = ST.pickProfile(inputs)
	return inputs
end

function Driver:init(now, saved)
	if self.opts == nil then
		local inputs = self:loadConfig()
		local reason = nil
		if self.opts.mapEditor then reason = "mapEditor"
		elseif self.opts.actOn == "off" then reason = "param" end
		self:log("INIT", { { "on", reason == nil }, { "reason", reason or "-" }, { "actOn", self.opts.actOn },
			{ "region", inputs.region }, { "regionSource", inputs.regionSource }, { "profile", self.profile },
			{ "forceGrid", self.opts.forceGrid }, { "lookahead", self.opts.lookahead }, { "nameList", self.cfg.nameList or "nil" },
			{ "climate", self.cfg.climate or "nil" }, { "lock", H.lockDefault or D.LOCK_DEFAULT },
			{ "lockLegacy", D.LOCK_SHAPE and "shape" or "off" },
			{ "fill", D.FILL_POINTS > 0 and ("dose" .. D.FILL_POINTS) or "off" },
			-- (2026-10-14: the largest share any fill may raise a town's initial capacities by: 0 = the game's balance)
			{ "capsBoost", D.capsBoost() },
			{ "metropolis", "auto_from_" .. D.METRO_MIN_CAP }, { "townSize", self.opts.townSize or "-" },
			{ "popDensity", self.E.townPopulationDensity and self.E.townPopulationDensity() or "-" },
			-- (later-ideas phase: upward density from UP.MIN_BUILDINGS, protected meadows, tree-lined entries)
			{ "upward", UP.ON and ("from" .. UP.MIN_BUILDINGS) or "off" },
			{ "levels", UP.LEVELS and ("pbAim" .. UP.PB_AIM) or "off" }, { "meadows", (D.MEADOWS and MD.ON) and "on" or "off" },
			{ "trees", EN.ON and "on" or "off" },
			-- (§66: the supply-driven district weighting, "Town growth")
			{ "townGrowth", self.opts.townGrowth or "-" },
			-- (the plan hang guard needs debug.sethook in the game's Lua: "on" or "off", 2026-10-13)
			{ "hangGuard", (D.PLAN_GUARD and type(debug) == "table" and type(debug.sethook) == "function") and "on" or "off" },
			{ "params", self.opts.raw } })
		-- (the name list and the founded towns' name language, NEXT_PHASE_BRIEF 72)
		if reason == nil then self:nameListLine(inputs) end
		if reason then
			self.phase = "off"
			self.offReason = reason
			return
		end
	end
	if self.opts.actOn == "new" and not SV.initialised(saved) then
		if self.initSent < D.INIT_TRIES and now >= self.initNextUs then
			local towns = self:townIds(now)
			local param = SV.initParam(towns, self.E.gameTime())
			self.E.sendEvent(SV.EVENT_ID, SV.EV_INIT, param)
			self.initSent = self.initSent + 1
			self.initNextUs = now + D.INIT_RETRY_S * 1e6
			self:log("SAVE", { { "event", "init" }, { "try", self.initSent }, { "fresh", param.fresh },
				{ "known", #param.known }, { "gameTime", self.E.gameTime() } })
		end
		return
	end
	local fresh = true
	if self.opts.actOn == "new" then
		local s = SV.normalize(saved)
		fresh = s.fresh == true
		self:log("RUN", { { "actOn", "new" }, { "knownTowns", #s.known }, { "fresh", s.fresh } })
	else
		self:log("RUN", { { "actOn", self.opts.actOn } })
	end
	self.phase = "run"
	-- (a new map: Act on New towns keeps the saved fresh flag; Act on All towns only knows the game clock at this load.
	-- The Works towns, ot_works, are only created on one)
	if self.opts.actOn == "new" then self.newMap = fresh
	else self.newMap = (tonumber(self.E.gameTime()) or 0) < SV.FRESH_GAME_TIME end
	self:levelBaseStart(saved)
	if UP.LEVELS then self:levelsProbe("load", true) end
	self:charsStart(now, saved)
	self:namesStart(now, saved, fresh)
	self:headStart(now, saved, fresh)
end

---------------------------------------------------------------------------
-- Head start (2026-10-13): on the first load of a new map every styled town gets HEAD_ROUNDS small increments in the
-- first minutes (one job every HEAD_GAP_S, round 1 for every town before round 2), so the style shows from day one.
-- No forced growth (no fill, no size change): the streets wait for the houses as the town grows (they count as the
-- town's own streets, so the demand trigger holds back until they are housed). Only while the game clock is under
-- HEAD_GAME_TIME at load, on a fresh map (Act on New towns: the saved fresh flag), for towns without a saved plan
-- frame (a town that already built once is skipped after a reload). Existing saves never qualify.
D.HEAD = true
D.HEAD_ROUNDS = 2          -- rounds at least (every town) ...
D.HEAD_ROUNDS_MAX = 5      -- ... and at most (big towns, long / spidery forms, character towns)
D.HEAD_PER_ROUND = 120     -- + one round per this many buildings
-- + rounds per form (2026-10-13, user: "Especially in the beginning, most towns look the same ... longer, skinny,
-- sprawling, etc. Is that possible when it first starts?"): the long and spidery forms draw their arms from day one
D.HEAD_FORM_ROUNDS = { linear = 1, fingers = 1, radiating = 1, shore = 1, sprawling = 1 }
D.HEAD_EDGES = 12          -- edges per head-start increment (a normal demand increment: 6-18)
D.HEAD_EDGES_FORM = { clustered = 10 }
D.HEAD_LEAD_M = 280        -- every head-start piece within this of a street with houses (ot_select lead limit), and
                           -- the arms' fill lead (2026-10-13: Axbridge's round 2 laid ~800 m of empty street to the edge)
D.HEAD_GAP_S = 3           -- real seconds between head-start jobs (frame time stays smooth: one job at a time)
D.HEAD_GAME_TIME = 600000  -- ms of game time: a load later than this is no new map

D.HEAD_ENV_MUL = 1.6       -- armed shapes: envelope x this in the head start (ot_select limits.envMul) ...
D.HEAD_ARM_EXTRA = 2       -- ... and the arm fronts this many blocks further

--- The head start's planner limits (ot_select opts.limits).
function D.headLimits()
	return { leadM = D.HEAD_LEAD_M, armFillM = D.HEAD_LEAD_M, headForm = true, envMul = D.HEAD_ENV_MUL,
		armExtra = D.HEAD_ARM_EXTRA }
end

--- Head-start rounds for a town of `buildings` with form id `form` (character: an extreme form). extra: the
--- "Starting town size" setting's added rounds (ot_townsize.head: smaller starting towns get more; the max rises too).
function D.headRounds(buildings, form, character, extra)
	extra = tonumber(extra) or 0
	local r = D.HEAD_ROUNDS + math.floor((tonumber(buildings) or 0) / D.HEAD_PER_ROUND)
	r = r + (D.HEAD_FORM_ROUNDS[form or ""] or 0) + (character and 1 or 0) + extra
	return math.max(D.HEAD_ROUNDS + extra, math.min(D.HEAD_ROUNDS_MAX + extra, r))
end

--- Edges per head-start increment for form id `form` and the setting's edge factor (ot_townsize.head edgesMul).
function D.headEdges(form, mul)
	local n = D.HEAD_EDGES_FORM[form or ""] or D.HEAD_EDGES
	return math.floor(n * (tonumber(mul) or 1) + 0.5)
end

--- The head start's scaling by the "Starting town size" setting: { rounds = +n, edgesMul = x }.
function Driver:headScale()
	return TS.head(self.opts and self.opts.townSize or "game")
end

--- [SQOT] START (2026-10-13, the "Starting town size" test): every town's size as the generator made it, before the
--- head start (buildings, its town street edges and their length, the capacity target), and a summary line. Returns
--- the rows.
D.START_BUDGET_US = 250000   -- START rows: the towns measured after this much time get only their capacities (audit)
function Driver:startSizes(towns)
	local rows = {}
	local E = self.E
	local t0 = self:nowUs()
	local skipped = 0
	for _, t in ipairs(towns) do
		if self:nowUs() - t0 > D.START_BUDGET_US then
			skipped = skipped + 1
		else
			local okM, m, _why, n = pcall(function() return self:measure(t, { noNet = true }) end)
			local row = { town = t, buildings = 0, edges = 0, length = 0, cap = 0, actual = 0 }
			if okM and m then
				row.buildings = m.buildings or 0
				for _, e in ipairs(m.lotEdges or {}) do
					row.edges = row.edges + 1
					row.length = row.length + (e.len or 0)
				end
				row.cap = m.caps and m.caps.target or 0
				row.actual = m.caps and m.caps.actual or 0
			elseif okM then
				-- (too few buildings for an extent: the count, and the capacity alone)
				row.buildings = tonumber(n) or 0
				local c = self.E.townCaps(t)
				row.cap, row.actual = c and c.target or 0, c and c.actual or 0
			end
			rows[#rows + 1] = row
			self:log("START", { { "town", t }, { "name", self.E.name(t) }, { "buildings", row.buildings }, { "edges", row.edges },
				{ "length", math.floor(row.length + 0.5) }, { "cap", math.floor(row.cap + 0.5) },
				{ "actual", math.floor(row.actual + 0.5) }, { "townSize", self.opts and self.opts.townSize or "-" } })
		end
	end
	local fields = TS.summaryFields(TS.summary(rows), self.opts and self.opts.townSize or "-")
	fields[#fields + 1] = { "skipped", skipped }
	fields[#fields + 1] = { "us", self:nowUs() - t0 }
	self:log("START summary", fields)
	return rows
end

--- Plans the head start at the run start (HEAD start line), or nothing.
function Driver:headStart(now, saved, fresh)
	if not D.HEAD or not fresh then return end
	local gt = self.E.gameTime()
	if (tonumber(gt) or 0) >= D.HEAD_GAME_TIME then return end
	local towns = {}
	for _, t in ipairs(self:townIds(now)) do
		if SV.frame(saved, t) == nil then towns[#towns + 1] = t end
	end
	if #towns == 0 then return end
	self:startSizes(towns)
	local sc = self:headScale()
	local queue = {}
	for r = 1, D.HEAD_ROUNDS_MAX + sc.rounds do
		for _, t in ipairs(towns) do queue[#queue + 1] = { town = t, round = r } end
	end
	self.head = { queue = queue, i = 0, nextUs = now + D.HEAD_GAP_S * 1e6, built = 0, edges = 0, skipped = 0, forms = {},
		scale = sc }
	self:log("HEAD start", { { "towns", #towns }, { "rounds", (D.HEAD_ROUNDS + sc.rounds) .. "-" .. (D.HEAD_ROUNDS_MAX + sc.rounds) },
		{ "edges", D.headEdges(nil, sc.edgesMul) }, { "leadM", D.HEAD_LEAD_M }, { "gapS", D.HEAD_GAP_S }, { "gameTime", gt },
		{ "townSize", self.opts and self.opts.townSize or "-" } })
end

--- HEAD done field `forms`: "linear:3/2x12+...": towns per form, their head-start edges.
local function headFormsText(forms)
	local ids = {}
	for id in pairs(forms) do ids[#ids + 1] = id end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		local f = forms[id]
		parts[#parts + 1] = string.format("%s:%d/%de/%dch", id, f.towns, f.edges, f.character)
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- Ends the head start early (the dev simulation's Quick / Build out take over at once: their build rounds give
--- every town its turn; 2026-10-14, the user: waiting for HEAD done before Quick was too long). A job in flight
--- finishes normally. Returns the jobs left, 0 without a head start.
function Driver:headEnd(why)
	local h = self.head
	if h == nil then return 0 end
	local left = math.max(0, #h.queue - h.i)
	self:log("HEAD done", { { "jobs", h.i }, { "built", h.built }, { "edges", h.edges }, { "skipped", h.skipped },
		{ "forms", headFormsText(h.forms) }, { "cut", why or "-" }, { "left", left } })
	self.head = nil
	return left
end

--- Starts the next head-start job when the driver is idle (true when one started).
function Driver:headTick(now)
	local h = self.head
	if h == nil or self.job ~= nil or self.inflight or now < h.nextUs or D.held() then return false end
	local e
	while true do
		h.i = h.i + 1
		e = h.queue[h.i]
		if e == nil then break end
		-- (rounds beyond the town's own count: skipped without a job; unknown count: the minimum)
		local s = self:townState(e.town)
		if e.round <= (s.headRounds or (D.HEAD_ROUNDS + h.scale.rounds)) then break end
	end
	if e == nil then
		self:log("HEAD done", { { "jobs", h.i - 1 }, { "built", h.built }, { "edges", h.edges }, { "skipped", h.skipped },
			{ "forms", headFormsText(h.forms) } })
		self.head = nil
		return false
	end
	h.nextUs = now + D.HEAD_GAP_S * 1e6
	local s0 = self:townState(e.town)
	local sc = h.scale
	local job = self:startJob(e.town, now, { force = true, maxEdges = s0.headEdges or D.headEdges(nil, sc.edgesMul), fill = "off",
		limits = D.headLimits(),
		onDone = function(j, outcome)
			local s = self:townState(e.town)
			local st = j.style or j.baseStyle
			local form = st and st.form and st.form.id or "-"
			local ch = st and st.form and st.form.character == true
			if e.round == 1 and st then
				-- (a strong character, ot_character 2026-10-14: one more round, as a secluded town, so its form shows early)
				s.headRounds = D.headRounds(j.pts and #j.pts or 0, form, ch or st.charKind ~= nil, sc.rounds)
				s.headEdges = D.headEdges(form, sc.edgesMul)
			end
			local n = j.spec and #j.spec.edges or 0
			if outcome == "built" then
				h.built = h.built + 1
				h.edges = h.edges + n
				local f = h.forms[form]
				if f == nil then
					f = { towns = 0, edges = 0, character = 0 }
					h.forms[form] = f
				end
				if e.round == 1 then
					f.towns = f.towns + 1
					if ch then f.character = f.character + 1 end
				end
				f.edges = f.edges + n
			else
				h.skipped = h.skipped + 1
			end
			local rep = j.report or {}
			self:log("HEAD", { { "town", e.town }, { "name", self.E.name(e.town) }, { "round", e.round },
				{ "of", s.headRounds or (D.HEAD_ROUNDS + sc.rounds) }, { "outcome", outcome }, { "edges", n }, { "form", form },
				{ "character", ch }, { "shape", st and st.shape and st.shape.id or "-" },
				{ "buildings", j.pts and #j.pts or 0 }, { "leadM", rep.leadM or "-" }, { "leadHeld", rep.leadHeld or 0 },
				{ "armFill", rep.armFill or 0 }, { "edge", rep.edgeHeld or 0 }, { "why", j.why or "-" } })
		end })
	if job then job.head = true end
	return job ~= nil
end

---------------------------------------------------------------------------
-- Landscape names (ot_names, 2026-10-13): on a new map, before the head start, every town gets a real name from the
-- game's own list that fits its site. Phases, one step per tick (each under the stage hang guard):
--   load      the list's language folders (E.townList, one per tick); the folder in use = the game language's when the
--             map's town names are in it, else the one holding most of them (ot_names.pickDir; E.language is logged)
--   classify  the pool's names -> site tags (NAMES_SLICE_US per tick)
--   survey    each town's terrain stats + tree grid (the head start's own terrain / forest stages, so nothing is read
--             twice; forest reads stop after NAMES_SURVEY_MAX_S)
--   assign    town tags (ot_names.townTags) -> names (ot_names.assign); the saved done flag (EV_NAMES) goes out here,
--             so a reload never renames again; NAME debug lines
--   rename    makeEntitySetNameCmd per town (NAMES_PER_TICK, NAMES_INFLIGHT, callbacks: guiUpdate is the Main Thread),
--             only while the town still has the name the game drew
--   indwait   NAMES_IND_WAIT_S, then the industries' names re-read: those the engine renamed itself are counted
--             (`indEngine=`), the rest named "<old town> <type>" get the new town name (ot_names.industryRenames)
--   industry  their renames; then the NAMES summary line.
-- Any error or NAMES_MAX_S ends it (why=error / timeout): the towns not yet renamed keep the game's names.
-- Names from the map's shape (2026-10-14, NEXT_PHASE_BRIEF 45): after the survey, phase `shape` reads the whole map once
-- (ot_mapshape: rivers as a network, the compass, the big lake, peaks and ranges, bays, capes, narrows; NAMES_SLICE_US
-- per tick, NAMES_SHAPE_MAX_S at most, then capped=timeout and the rest skipped; `NAMES survey` line), and both modes
-- name with the towns' cues and the map's word budget (ot_namewords; `NAMES words` line, NAME `cue=`).
-- Generated names (setting value 3, ot_placename, 2026-10-14): the same phases without classify; the survey adds
-- ot_placename.read per town, assign builds the names from morphemes (rivers and lakes named too, saved as `rv` with
-- the done flag); a list without a generator (ot_placename.langOf) falls back to landscape names (`fallback=`).
D.NAMES = true
D.NAMES_GAME_TIME = 600000   -- ms of game time at load (Act on New towns: with the saved fresh flag)
D.NAMES_MAX_S = 240
D.NAMES_SLICE_US = 2000
D.NAMES_PER_TICK = 2
D.NAMES_INFLIGHT = 4
D.NAMES_CMD_TIMEOUT_S = 10
D.NAMES_IND_WAIT_S = 2
D.NAMES_FOREST_SLICES = 40
D.NAMES_SURVEY_MAX_S = 90
D.NAMES_SHAPE = true
D.NAMES_SHAPE_MAX_S = 45     -- the map survey stops after this (capped=timeout)

--- Sets up the names phase at the run start, or logs why not (NAMES on=false why=...).
function Driver:namesStart(now, saved, fresh)
	if not (D.NAMES and NM.ON) then return end
	local why = nil
	if self.opts.townNames ~= "landscape" and self.opts.townNames ~= "generated" then why = "setting"
	elseif not (self.E.townList and self.E.setName) then why = "noEngine"
	elseif SV.namesDone(saved) then why = "done"
	elseif not fresh then why = "notNewMap"
	else
		local gt = tonumber(self.E.gameTime()) or 0
		local limit = self.opts.actOn == "new" and D.NAMES_GAME_TIME or SV.FRESH_GAME_TIME
		if gt >= limit then why = "notNewMap" end
	end
	local path = nil
	if why == nil then path, why = NM.basePath(self.cfg.nameList) end
	if why then
		self:log("NAMES", { { "on", false }, { "why", why }, { "mode", self.opts.townNames or "-" }, { "list", self.cfg.nameList or "nil" } })
		return
	end
	self.names = { phase = "load", path = path, mode = self.opts.townNames, dirs = NM.langDirs(path), di = 0, lists = {}, matches = {},
		startUs = now, deadlineUs = now + D.NAMES_MAX_S * 1e6, si = 0, queue = {}, qi = 0, inflight = 0,
		c = { sent = 0, ok = 0, failed = 0, changed = 0, timeouts = 0, indSent = 0, indEngine = 0, indFound = 0 } }
end

--- One names step (true while the names phase runs: the head start and the checks wait).
function Driver:namesTick(now)
	local n = self.names
	if n == nil then return false end
	if now > n.deadlineUs then
		self:namesEnd("timeout")
		return false
	end
	local ok, err = D.guard(self:clockFn(), D.STAGE_HANG_US, self.namesStep, self, n, now)
	if not ok then
		self:log("ERROR", { { "stage", "names" }, { "phase", n.phase }, { "err", err } })
		self:namesEnd("error")
		return false
	end
	return self.names ~= nil
end

function Driver:namesStep(n, now)
	local E = self.E
	if n.phase == "load" then
		if n.ids == nil then
			n.ids, n.cur = {}, {}
			for i, t in ipairs(self:townIds(now)) do
				if i > NM.MAX_TOWNS then break end
				n.ids[#n.ids + 1] = t
				n.cur[t] = E.name(t)
			end
			return
		end
		n.di = n.di + 1
		local dir = n.dirs[n.di]
		if dir ~= nil then
			local list, err = E.townList(n.path, dir)
			if list then
				local set, m = {}, 0
				for i = 1, math.min(#list, NM.MAX_POOL) do set[list[i]] = true end
				for _, t in ipairs(n.ids) do if set[n.cur[t]] then m = m + 1 end end
				n.lists[dir], n.matches[dir] = list, m
			else
				n.loadErr = err
			end
			return
		end
		n.lang, n.langRaw = E.language()
		local pick, src = NM.pickDir(n.path, n.lang, n.matches, #n.ids)
		n.dir, n.langSource = pick, src
		if pick == nil or n.lists[pick] == nil then return self:namesEnd(pick == nil and src or "listLoad") end
		n.cls = NM.classOf(n.path, pick)
		-- (2026-10-14, NEXT_PHASE_BRIEF 49, user: "in landscape name mode i'd prefer not to use real existing city names,
		-- and instead all generated names from region and geography cues": Landscape and Generated names both run the
		-- generator (ot_placename) with the climate; a list it has no language for keeps the game's names, but the map
		-- survey still runs (NEXT_PHASE_BRIEF 48 items 1 and 5: `NAMES on=false why=untaggedList`))
		if n.mode == "landscape" or n.mode == "generated" then
			local g, gwhy = PN.langOf(n.cls or PN.listLang(n.path))
			if g and PN.ON then
				n.glang = g
				if n.glang == "ja" and pick ~= "ja" then n.glang = "ja_r" end
				n.climate = PN.climateKey(self.cfg.climate)
				-- the game's own names of every folder: never generated
				n.real = {}
				for _, list in pairs(n.lists) do
					for i = 1, math.min(#list, NM.MAX_POOL) do
						if type(list[i]) == "string" then n.real[PN.lowerAll(list[i])] = true end
					end
				end
				n.pool = NM.newPool(n.lists[pick], n.cls)
				n.lists = nil
				n.phase = "survey"
				return
			end
			-- (no generator language: keep the game's names; the survey still runs for the later steps)
			n.noNames = n.cls == nil and "untaggedList" or (gwhy or "noGenerator")
			n.lists = nil
			n.phase = "shape"
			return
		end
		-- (the old list matcher, ot_names.assign, retired 2026-10-14 with NEXT_PHASE_BRIEF 49: no mode reaches it)
		return self:namesEnd("setting")
	elseif n.phase == "survey" then
		local job = n.job
		if job == nil then
			n.si = n.si + 1
			local t = n.ids[n.si]
			if t == nil then
				n.phase = "shape"
				return
			end
			local x, y = E.boxCentre(t)
			if x == nil then return end
			job = { town = t, ext = { cx = x, cy = y, r = 0 }, stage = "terrain", slices = 0 }
			if self:townState(t).stats then job.stage = self:afterTerrain(t, now) end
			n.job = job
			-- (generated names: the generator's own cheap read, ot_placename.read)
			if n.glang then
				local okR, rd = pcall(PN.read, E.sampler(), x, y)
				self:townState(t).pnRead = okR and rd or nil
			end
		end
		if job.stage == "terrain" then
			self:terrain(job)
		elseif job.stage == "forest" and job.slices < D.NAMES_FOREST_SLICES
			and now - n.startUs < D.NAMES_SURVEY_MAX_S * 1e6 then
			job.slices = job.slices + 1
			self:forest(job, now)
		else
			n.job = nil
		end
	elseif n.phase == "shape" then
		self:namesShape(n, now)
	elseif n.phase == "assign" then
		if n.noNames then return self:namesEnd(n.noNames) end
		self:namesAssignGen(n, now)
	elseif n.phase == "rename" or n.phase == "industry" then
		self:namesSend(n, now)
		if n.qi >= #n.queue and n.inflight <= 0 then
			if n.phase == "industry" then return self:namesEnd("ok") end
			n.phase, n.waitUs = "indwait", now + D.NAMES_IND_WAIT_S * 1e6
		end
	elseif n.phase == "indwait" then
		if now < n.waitUs then return end
		self:namesIndustries(n)
	end
end

--- Phase shape: the map survey (ot_mapshape), sliced; then phase assign. No bounds, off, or an error: no survey (the
--- names go without cues; `NAMES survey on=false why=`).
function Driver:namesShape(n, now)
	local E = self.E
	if n.shapeSt == nil then
		if not (D.NAMES_SHAPE and MS.ON) then n.shapeWhy = "off"
		else
			local st, why = MS.new(self:mapBounds(now))
			n.shapeSt, n.shapeWhy = st, why
			n.shapeS, n.shapeUs, n.shapeT0 = st and E.sampler() or nil, 0, now
		end
		if n.shapeSt == nil then
			self:log("NAMES survey", { { "on", false }, { "why", n.shapeWhy or "-" } })
			n.phase = "assign"
		end
		return
	end
	local st = n.shapeSt
	local t0 = self:nowUs()
	local done = MS.step(st, n.shapeS, function() return self:nowUs() - t0 < D.NAMES_SLICE_US end)
	n.shapeUs = n.shapeUs + (self:nowUs() - t0)
	if not done and now - n.shapeT0 > D.NAMES_SHAPE_MAX_S * 1e6 then
		MS.stop(st, "timeout")
		done = true
	end
	if not done then return end
	n.shape, n.shapeS = st, nil
	-- (kept for the session: Works and district names read the site's water and cues from it, ot_offname)
	self.mapShape = st
	local fields = MS.surveyFields(st)
	fields[#fields + 1] = { "ms", string.format("%.0f", n.shapeUs / 1000) }
	fields[#fields + 1] = { "s", string.format("%.1f", (now - n.shapeT0) / 1e6) }
	self:log("NAMES survey", fields)
	n.phase = "assign"
end

--- The map survey's cues of the town at (x, y), or nil (no survey).
function Driver:namesCue(n, x, y)
	if n.shape == nil or x == nil then return nil end
	local okC, cue = pcall(MS.townCues, n.shape, x, y)
	return okC and cue or nil
end

--- The NAMES words line: the word budget's use and what it turned down.
function Driver:namesWordsLine(n, B, rarity, extra)
	local f = { { "used", NW.usedText(B) }, { "held", NW.heldText(B) }, { "cap", B and B.cap or 0 },
		{ "near", B and B.near or 0 }, { "over", B and B.over or 0 }, { "rare", NW.rarityText(rarity) } }
	for _, e in ipairs(extra or {}) do f[#f + 1] = e end
	self:log("NAMES words", f)
end

--- Phase assign, generated names (ot_placename): site tags from the survey + the extra read, the names (rivers and lakes
--- first), the done flag with the water names, the rename queue. Only towns that still carry a name of the game's list
--- are renamed (a player-renamed town keeps its name: `notDrawn`).
D.NAMES_SMALL_CAP = 400   -- target capacity under this: a small town
function Driver:namesAssignGen(n, now)
	local E = self.E
	-- (2026-10-14, real-play prep: this phase runs in one tick; its cost goes on the NAMES words line, `assignMs=`)
	local tA = self:nowUs()
	local towns = {}
	local year = E.year and E.year() or nil
	for _, t in ipairs(n.ids) do
		local x, y = E.boxCentre(t)
		local caps = E.townCaps(t)
		local ch = self:characterOf(t, now)
		-- (NEXT_PHASE_BRIEF 53 Part B, the naming hook for strong characters: a character town's kind, ch.nameKind
		-- ("hilltop", "harbour", "street", "company", "garden", "island", "market", "church"), picks a striking form of its
		-- kind, ot_placename charForms; true: an ordinary character town)
		-- (a strong-character town, ot_character 2026-10-14: its kind's nameKind, set by characterOf)
		local isCh = ch ~= nil and (ch.character == true or type(ch.nameKind) == "string")
		towns[#towns + 1] = { id = t, name = n.cur[t], x = x, y = y, cap = caps and caps.target or 0,
			character = isCh and ((type(ch.nameKind) == "string" and ch.nameKind ~= "") and ch.nameKind or true) or false }
	end
	-- (NEXT_PHASE_BRIEF 61: every character town carries its kind; the s61 kinds the driver knows by now: the deep forest
	-- pick (made here, from the forest read: FO.deepSite and the draw, at most DEEP_MAX on the map; the plan's deep pick
	-- then follows it, s.nameDeep), the secluded character towns, the coastal hugger)
	self:namesKinds(towns, now)
	local big = NM.bigTowns(towns)
	-- (2026-10-14: the map's tree species, so a town's species tag is what is special about its woods)
	local speciesMap = {}
	for _, tw in ipairs(towns) do
		for sp, k in pairs(self:townState(tw.id).species or {}) do speciesMap[sp] = (speciesMap[sp] or 0) + (tonumber(k) or 0) end
	end
	for _, tw in ipairs(towns) do
		local s = self:townState(tw.id)
		local okF, feat = pcall(SITE.features, s.stats, s.wide)
		feat = okF and feat or nil
		local okE, fEdge = pcall(FO.isEdge, s.forest)
		tw.w, tw.ranked = PN.siteTags({ feat = feat, stats = s.stats, wide = s.wide, forestShare = s.forest and s.forest.share or nil,
			species = s.species, speciesMap = speciesMap, forestEdge = okE and fEdge == true, read = s.pnRead,
			big = big[tw.id] == true, small = (tw.cap or 0) > 0 and tw.cap < D.NAMES_SMALL_CAP,
			character = tw.character ~= false, year = year, kind = "town", climate = n.climate })
		local w = s.stats and s.stats.water
		tw.river = (feat and (feat.river or 0) > 0) or (w ~= nil and w.kind == "river") or PN.nearRiver(s.pnRead)
		tw.axis = w and w.axis or nil
		tw.lake = feat ~= nil and (feat.body == "lake" or feat.body == "pond")
		-- (2026-10-14, NEXT_PHASE_BRIEF 53: the height for Upper / Lower twins and the dialect areas' high edge)
		tw.alt = s.pnRead and tonumber(s.pnRead.alt) or nil
		tw.cue = self:namesCue(n, tw.x, tw.y)
		-- (2026-10-14, NEXT_PHASE_BRIEF 49, run 0814 load 4: `lake:1.00` on two towns of an island map with `lakes=0
		-- sea=true`: "Lake in the Hills", "Canyon Lake". The town's tags agree with the survey: no lake word without a
		-- lake (not the sea) within reach; a sea inlet or lagoon is coast / bay)
		local wn = n.shape and MS.waterNear(n.shape, tw.x, tw.y) or nil
		for _, m in ipairs(PN.agreeSurvey(tw.w, wn)) do
			n.misfit = n.misfit or {}
			n.misfit[m] = (n.misfit[m] or 0) + 1
			tw.lake = false
		end
		-- (NEXT_PHASE_BRIEF 61: two lakes near for "Twin Lakes"; the industry near the town as a cue)
		if wn and tonumber(wn.lakes) then tw.facts = { lakes = wn.lakes } end
		tw.ind = self:namesIndustryCue(tw.x, tw.y, now)
		-- (a town whose name isn't from the game's list (player-renamed) keeps it; its words count for the budget)
		tw.keep = not (type(tw.name) == "string" and n.real[PN.lowerAll(tw.name)] == true)
	end
	local seed = NM.mapSeed(towns)
	local res, st = PN.assign(towns, { lang = n.glang, seed = seed, real = n.real, climate = n.climate, year = year })
	if res == nil then return self:namesEnd(st or "noGenerator") end
	n.stats, n.res, n.gst = { renamed = 0, kept = 0, notDrawn = 0 }, res, st
	n.indSnap = E.industryNames and E.industryNames(NM.MAX_INDUSTRIES) or {}
	-- (the town window's card, 2026-10-17: why each renamed town got its name, ot_card.originCode; towns that keep a
	-- name not drawn from the game's list, or their game name, get none)
	local origins = {}
	for _, r in ipairs(res) do
		local drawn = type(r.old) == "string" and n.real[PN.lowerAll(r.old)] == true
		local code = (drawn and r.new and r.new ~= r.old) and CARD.originCode(r.info) or nil
		if code and #origins < SV.ORIGIN_CAP then origins[#origins + 1] = { t = r.id, o = code } end
	end
	-- (the done flag before any rename, with the folder and the water names for the stop names of later sessions)
	E.sendEvent(SV.EVENT_ID, SV.EV_NAMES, { done = 1, nd = n.dir, rv = st.waters, no = origins })
	self:log("CARD", { { "event", "origins" }, { "towns", #origins }, { "of", #res } })
	self.listDir = n.dir
	self.namesWaters = st.waters
	n.renames, n.oldNames = {}, {}
	for i, r in ipairs(res) do
		n.oldNames[#n.oldNames + 1] = r.old
		local drawn = type(r.old) == "string" and n.real[PN.lowerAll(r.old)] == true
		local s = self:townState(r.id)
		self:debug("NAME", { { "town", r.id }, { "old", r.old or "-" }, { "new", r.new or "-" }, { "src", "generated" },
			{ "parts", PN.partsText(r.info) }, { "feature", r.info and r.info.feature or "-" },
			{ "tags", PN.rankedText(towns[i].ranked, 6) }, { "river", r.river or "-" }, { "lake", r.lake or "-" },
			{ "dialect", r.info and r.info.dialect or "-" }, { "read", PN.readText(s.pnRead) },
			{ "cue", MS.cueText(towns[i].cue) }, { "words", table.concat(NW.keys(r.new, st.budget and st.budget.cls), "+") },
			{ "score", string.format("%.2f", r.info and r.info.score or 0) }, { "drawn", drawn },
			{ "character", towns[i].character ~= false }, { "cap", math.floor((towns[i].cap or 0) + 0.5) },
			{ "shape", r.info and r.info.shape or "-" }, { "layer", r.info and r.info.layer or "-" },
			{ "char", type(towns[i].character) == "string" and towns[i].character or "-" },
			{ "ind", towns[i].ind and string.format("%s:%.0f", towns[i].ind.fam, towns[i].ind.d) or "-" },
			{ "evoc", r.info and r.info.gate or "-" },
			{ "x", math.floor((towns[i].x or 0) + 0.5) }, { "y", math.floor((towns[i].y or 0) + 0.5) },
			{ "alt", towns[i].alt and math.floor(towns[i].alt + 0.5) or "-" } })
		if not drawn then
			n.stats.notDrawn = n.stats.notDrawn + 1
		elseif r.new and r.old and r.new ~= r.old then
			n.queue[#n.queue + 1] = { id = r.id, old = r.old, new = r.new }
			n.renames[r.old] = r.new
			n.stats.renamed = n.stats.renamed + 1
		else
			n.stats.kept = n.stats.kept + 1
		end
	end
	local mis = {}
	for k, v in pairs(st.misfit or {}) do mis[k] = v end
	for k, v in pairs(n.misfit or {}) do mis[k] = (mis[k] or 0) + v end
	-- (NEXT_PHASE_BRIEF 53: the map's name shapes, once per map)
	self:log("NAMES shapes", PN.shapeFields(st))
	self:namesWordsLine(n, st.budget, st.rarity, { { "mode", n.mode or "generated" }, { "mount", st.mount and st.mount.n or "-" },
		{ "bay", st.bay and st.bay.n or "-" }, { "climate", n.climate or "-" }, { "misfit", PN.misfitText(mis) },
		{ "towns", #towns }, { "assignMs", string.format("%.0f", (self:nowUs() - tA) / 1000) } })
	n.phase = "rename"
end

--- The s61 character kinds of the naming phase (2026-10-15, NEXT_PHASE_BRIEF 61): a town with no strong kind takes
--- "forest" (deep forest: FO.deepSite on its forest read and the seeded draw, DEEP_MAX on the map at most, the saved
--- deep towns counted; the town's s.nameDeep is set either way for the plan's pick), else "secluded" (an ordinary
--- character town), else "coastal" (the coastal hugger, Driver:coastalOf). Changes towns[i].character in place.
function Driver:namesKinds(towns, now)
	local nDeep = select(1, SV.deepTowns(self.saved))
	local cands = {}
	for i, tw in ipairs(towns) do
		local s = self:townState(tw.id)
		if type(tw.character) ~= "string" and not self:charKindOf(tw.id) then
			local fr = SV.frame(self.saved, tw.id)
			if fr and fr.deep then
				tw.character = CH.nameKind("deep_forest")
			elseif fr == nil and s.forest and s.forest.done then
				local okD, deep, ring = pcall(FO.deepSite, s.forest)
				local p = FO.DEEP_P * FO.deepEraF(tonumber(self.E.year and self.E.year()) or 1950)
				local u = RNG.unit(NM.mapSeed(towns), "nameDeep", tonumber(tw.id) or i)
				if okD and deep and u < p then cands[#cands + 1] = { i = i, ring = ring } end
				s.nameDeep = false
			end
		end
	end
	table.sort(cands, function(a, b)
		if a.ring ~= b.ring then return a.ring > b.ring end
		return (tonumber(towns[a.i].id) or 0) < (tonumber(towns[b.i].id) or 0)
	end)
	for k, c in ipairs(cands) do
		if nDeep + k > FO.DEEP_MAX then break end
		towns[c.i].character = CH.nameKind("deep_forest")
		self:townState(towns[c.i].id).nameDeep = true
	end
	for _, tw in ipairs(towns) do
		if tw.character == true then
			tw.character = CH.NAME_SECLUDED
		elseif tw.character == false then
			local okC, co = pcall(self.coastalOf, self, tw.id, now)
			if okC and co and co.coastal then tw.character = CH.NAME_COASTAL end
		end
	end
end

-- the industry families (ot_offname.indType) that are a town name's cue, NEXT_PHASE_BRIEF 61 (ore mines read as coal's
-- pits; the base game's forest industry is timber)
D.IND_CUE_FAM = { fish = "fish", oil = "oil", clay = "clay", coal = "coal", ore = "coal", stone = "stone", timber = "timber",
	farm = "farm", iron = "iron" }

--- The nearest industry of a cue family within PN.IND_R of (x, y): { fam, d } or nil (the map's industry list, read
--- once for the planner anyway; at most 4000 looked at).
function Driver:namesIndustryCue(x, y, now)
	local E = self.E
	if x == nil or E.industries == nil then return nil end
	if self.indAll == nil then
		local okL, all = pcall(E.industries)
		self.indAll, self.indAllUs = okL and all or {}, now
	end
	local best = nil
	for i, it in ipairs(self.indAll or {}) do
		if i > 4000 then break end
		local ix, iy = it[1] or it.x, it[2] or it.y
		if tonumber(ix) and tonumber(iy) then
			local d = G.dist(x, y, ix, iy)
			if d <= PN.IND_R and (best == nil or d < best.d) then
				local file = string.lower(tostring(it.file or ""))
				local fam = file:find("/forest/", 1, true) and "timber" or D.IND_CUE_FAM[OFF.indType(file)]
				if fam then best = { fam = fam, d = d } end
			end
		end
	end
	return best
end

--- Sends the queued renames (NAMES_PER_TICK per tick, NAMES_INFLIGHT waiting at most); an entity whose name is no
--- longer the one read before (player-renamed meanwhile) is skipped.
function Driver:namesSend(n, now)
	local E = self.E
	for _, it in ipairs(n.queue) do
		if it.sentUs and not it.done and now - it.sentUs > D.NAMES_CMD_TIMEOUT_S * 1e6 then
			it.done = true
			n.inflight = n.inflight - 1
			n.c.timeouts = n.c.timeouts + 1
		end
	end
	local sent = 0
	while sent < D.NAMES_PER_TICK and n.inflight < D.NAMES_INFLIGHT and n.qi < #n.queue do
		n.qi = n.qi + 1
		local it = n.queue[n.qi]
		if E.name(it.id) ~= it.old then
			n.c.changed = n.c.changed + 1
		else
			sent = sent + 1
			n.inflight = n.inflight + 1
			it.sentUs = now
			if n.phase == "industry" then n.c.indSent = n.c.indSent + 1 else n.c.sent = n.c.sent + 1 end
			E.setName(it.id, it.new, function(success)
				if it.done then return end
				it.done = true
				n.inflight = n.inflight - 1
				if success then n.c.ok = n.c.ok + 1 else n.c.failed = n.c.failed + 1 end
			end)
		end
	end
end

--- Phase indwait done: which industries the engine renamed itself, the rest's renames queued (phase industry).
function Driver:namesIndustries(n)
	local E = self.E
	local now = {}
	for _, e in ipairs(E.industryNames and E.industryNames(NM.MAX_INDUSTRIES) or {}) do now[e.id] = e.name end
	local expect = {}
	for _, r in ipairs(NM.industryRenames(n.indSnap, n.renames, n.oldNames)) do expect[r.id] = r end
	local still = {}
	for _, e in ipairs(n.indSnap) do
		local cur = now[e.id]
		local r = expect[e.id]
		if r then n.c.indFound = n.c.indFound + 1 end
		if r and cur == r.new then n.c.indEngine = n.c.indEngine + 1
		elseif cur == e.name then still[#still + 1] = e end
	end
	n.queue, n.qi = {}, 0
	for _, r in ipairs(NM.industryRenames(still, n.renames, n.oldNames)) do
		n.queue[#n.queue + 1] = { id = r.id, old = r.old, new = r.new }
		self:debug("NAME", { { "industry", r.id }, { "old", r.old }, { "new", r.new } })
	end
	n.phase = "industry"
end

--- The NAMES summary line; ends the names phase.
function Driver:namesEnd(why)
	local n = self.names
	self.names = nil
	if n == nil then return end
	local p, st, c = n.pool, n.stats or {}, n.c
	local gst = n.gst or {}
	-- (a list without a generator language keeps the game's names: on=false why=untaggedList list=asia, NEXT_PHASE_BRIEF 48)
	if n.noNames and why == n.noNames then
		self:log("NAMES", { { "on", false }, { "why", why }, { "list", n.path or "-" }, { "lang", n.dir or "-" },
			{ "cls", n.cls or "-" }, { "mode", n.mode or "-" }, { "survey", n.shape ~= nil },
			{ "s", string.format("%.1f", (self:nowUs() - n.startUs) / 1e6) } })
		return
	end
	self:log("NAMES", { { "on", true }, { "why", why }, { "mode", n.mode or "landscape" }, { "gen", n.glang or "-" },
		{ "fallback", n.fallback or "-" }, { "rivers", gst.rivers or 0 }, { "lakes", gst.lakes or 0 },
		{ "list", n.path }, { "lang", n.dir or "-" },
		{ "langSource", n.langSource or "-" }, { "apiLang", n.lang or "-" }, { "apiRaw", n.langRaw or "-" },
		{ "cls", n.cls or "-" }, { "pool", p and #p.names or 0 }, { "tagged", p and p.tagged or 0 },
		{ "tags", p and p.counts and NM.countsText(p) or "-" }, { "towns", n.ids and #n.ids or 0 },
		{ "renamed", st.renamed or 0 }, { "fit", st.fit or 0 }, { "plain", st.plain or 0 }, { "random", st.random or 0 },
		{ "satellite", st.satellite or 0 }, { "kept", st.kept or 0 }, { "notDrawn", st.notDrawn or 0 },
		{ "sent", c.sent }, { "ok", c.ok }, { "failed", c.failed }, { "changed", c.changed }, { "timeouts", c.timeouts },
		{ "industries", n.indSnap and #n.indSnap or 0 }, { "indPrefixed", c.indFound }, { "indEngine", c.indEngine },
		{ "indSent", c.indSent }, { "loadErr", n.loadErr or "-" }, { "s", string.format("%.1f", (self:nowUs() - n.startUs) / 1e6) } })
end

---------------------------------------------------------------------------
-- Landscape stop names (ot_names stop part, 2026-10-13): a new player Road Stop in a town gets a street-style name that
-- fits its spot. The game script's handleEvent queues new stops in the saved state (onPostBuildProposal, ot_saved
-- addStops: player builds only, never a stop a road upgrade re-created); here, at least STOP_DELAY_S after the build,
-- one stop per STOP_CHECK_S: its group must still carry the name it got at the build (else player-renamed) and hold only
-- queued stops (else it joined an existing group), the spot is read (height against the town centre and a 200 m ring,
-- water beside it, the town's water kind, the tree grid, the nearest rail station, the distance from the centre), the
-- name picked (ot_names.pickStop: unused in that town) and sent; the stop leaves the queue by the "stops" event.
-- Only on a base name list with a stop classifier and "Landscape names"; the list folder comes from the names phase
-- (saved `nd`), else from matching the map's town names against the list's folders (one folder per check).
D.STOPS = true
D.STOP_CHECK_S = 0.5
D.STOP_DELAY_S = 1
D.STOP_RING_M = 200
D.STOP_WET_R = { 40, 80, 130 }
D.STOP_RAIL_S = 120
D.STOP_SAMPLER_S = 600

--- The stop names' settings, or nil while the list folder is still being found. { on = bool, why, path, dir, cls,
--- streets }.
function Driver:stopsConfig(now, saved)
	local c = self.stopsCfg
	if c and c.on ~= nil then return c end
	if c == nil then
		c = {}
		self.stopsCfg = c
		local why = nil
		if self.opts.townNames ~= "landscape" and self.opts.townNames ~= "generated" then why = "setting"
		elseif not (self.E.streetList and self.E.setName and self.E.stationGroup) then why = "noEngine" end
		-- (generated names: the rivers' and lakes' names, ot_saved `rv`, for "Avon Street" / "Lahnweg")
		c.waters = SV.waters(saved)
		local path = nil
		if why == nil then path, why = NM.basePath(self.cfg.nameList) end
		if why then
			c.on, c.why = false, why
			return c
		end
		c.path = path
		c.dir = (type(saved) == "table" and type(saved.nd) == "string" and saved.nd) or self.listDir
		if c.dir == nil then c.find = { dirs = NM.langDirs(path), di = 0, matches = {} } end
	end
	if c.dir == nil then
		local f = c.find
		local E = self.E
		if f.ids == nil then
			f.ids, f.cur = {}, {}
			for i, t in ipairs(self:townIds(now)) do
				if i > NM.MAX_TOWNS then break end
				f.ids[#f.ids + 1] = t
				f.cur[t] = E.name(t)
			end
			return nil
		end
		f.di = f.di + 1
		local d = f.dirs[f.di]
		if d ~= nil then
			local list = E.townList and E.townList(c.path, d) or nil
			local set, m = {}, 0
			for i = 1, math.min(list and #list or 0, NM.MAX_POOL) do set[list[i]] = true end
			for _, t in ipairs(f.ids) do if set[f.cur[t]] then m = m + 1 end end
			f.matches[d] = m
			return nil
		end
		local lang = E.language and E.language() or nil
		c.dir, c.dirSource = NM.pickDir(c.path, lang, f.matches, #f.ids)
		c.find = nil
		if c.dir == nil then
			c.on, c.why = false, c.dirSource or "noListMatch"
			return c
		end
	end
	c.cls = NM.classOf(c.path, c.dir)
	if c.cls == nil or (SN.LANG[c.cls] == nil and NM.STOP[c.cls] == nil) then
		c.on, c.why = false, "noStopNames"
		return c
	end
	c.streets = self.E.streetList(c.path, c.dir)
	c.on, c.why = true, "-"
	return c
end

D.STOP_WATER_NAME_M = 2500
D.GEN_OFFSHOOT_P = 0.6    -- generated names: a district / Works takes a generated name this often (else the composed forms)
--- The stem of the nearest saved water name of kind k ("r" | "l") within STOP_WATER_NAME_M of (x, y), or nil.
function D.waterNameAt(waters, x, y, k)
	if waters == nil or k == nil or not tonumber(x) then return nil end
	local best, bd = nil, D.STOP_WATER_NAME_M
	for _, e in ipairs(waters) do
		if e.k == k and tonumber(e.x) then
			local d = G.dist(x, y, e.x, e.y)
			if d <= bd then best, bd = e.s or e.n, d end
		end
	end
	return best
end

--- Dev tools (square_organic_towns_dev "Place test stops (named)"): script-built Road Stops the build event's player
--- filter never queues. list = { {st, g, n, x, y} }; they join the stop queue of this session (not saved), at most
--- SV.STOP_CAP waiting, and are named like a player's (the dev flag only skips the "stops" event). Returns how many.
function Driver:addDevStops(list)
	self.devStops = self.devStops or {}
	local n = 0
	local t = self.E.osTime and self.E.osTime() or 0
	for _, e in ipairs(list or {}) do
		if #self.devStops >= SV.STOP_CAP then break end
		if tonumber(e.st) then
			self.devStops[#self.devStops + 1] = { st = tonumber(e.st), g = tonumber(e.g) or -1, n = e.n, x = tonumber(e.x),
				y = tonumber(e.y), t = t, dev = true }
			n = n + 1
		end
	end
	return n
end

--- One stop-name step (from tick while running; never more than one stop per STOP_CHECK_S).
function Driver:stopsTick(now, saved)
	if not (D.STOPS and NM.ON) or self.phase ~= "run" then return end
	if now < (self.stopNextUs or 0) then return end
	self.stopNextUs = now + D.STOP_CHECK_S * 1e6
	local q = SV.stopQueue(saved)
	if self.devStops and #self.devStops > 0 then
		local keep = {}
		for _, e in ipairs(self.devStops) do
			if not (self.stopSeen and self.stopSeen[e.st]) then
				q[#q + 1] = e
				keep[#keep + 1] = e
			end
		end
		self.devStops = keep
	end
	if #q == 0 then return end
	self.stopSeen = self.stopSeen or {}
	local c = self:stopsConfig(now, saved)
	if c == nil then return end
	local E = self.E
	local done = {}
	if not c.on then
		-- (stops queued while names are off for this map: they leave the queue with the game's names)
		for _, e in ipairs(q) do
			if not self.stopSeen[e.st] then
				self.stopSeen[e.st] = true
				if not e.dev then done[#done + 1] = e.st end
			end
		end
		if not self.stopsOffLogged then
			self.stopsOffLogged = true
			self:log("STOPNAME", { { "on", false }, { "why", c.why }, { "list", self.cfg.nameList or "nil" } })
		end
	else
		local t = E.osTime and E.osTime() or 0
		local fresh = {}
		for _, e in ipairs(q) do fresh[e.st] = true end
		for _, e in ipairs(q) do
			if not self.stopSeen[e.st] and (t - (e.t or 0) >= D.STOP_DELAY_S or t < (e.t or 0)) then
				self.stopSeen[e.st] = true
				if not e.dev then done[#done + 1] = e.st end
				local ok, err = D.guard(self:clockFn(), D.STAGE_HANG_US, self.stopName, self, e, c, fresh, now)
				if not ok then self:log("ERROR", { { "stage", "stopName" }, { "station", e.st }, { "err", err } }) end
				break
			end
		end
	end
	if #done > 0 then E.sendEvent(SV.EVENT_ID, SV.EV_STOPS, { done = done }) end
end

--- The spot of a stop at (x, y) in town t: the ot_names.stopThemes site table. st: the street stop's station entity
--- (the bridge cue, ot_stopname.bridgeCue; nil for stations).
function Driver:stopSite(t, x, y, now, st)
	local E = self.E
	local s = self:townState(t)
	if s.stats == nil then
		local cx, cy = E.boxCentre(t)
		if cx then self:terrain({ town = t, ext = { cx = cx, cy = cy, r = 0 }, stage = "terrain" }) end
	end
	if self.stopSampler == nil or now - (self.stopSamplerUs or 0) > D.STOP_SAMPLER_S * 1e6 then
		self.stopSampler, self.stopSamplerUs = E.sampler(), now
	end
	local sm = self.stopSampler
	local pos = s.pos
	local site = {}
	local hz = sm.height(x, y)
	if pos then
		site.dz = hz - sm.height(pos[1], pos[2])
		site.dist = G.dist(x, y, pos[1], pos[2])
	end
	local sum, n, wet = 0, 0, false
	for k = 0, 7 do
		local a = k / 8 * 2 * math.pi
		local ca, sa = math.cos(a), math.sin(a)
		for _, r in ipairs(D.STOP_WET_R) do
			if sm.water(x + ca * r, y + sa * r) then wet = true end
		end
		local rx, ry = x + ca * D.STOP_RING_M, y + sa * D.STOP_RING_M
		if not sm.water(rx, ry) then
			sum, n = sum + sm.height(rx, ry), n + 1
		end
	end
	if n > 0 then site.ring = hz - sum / n end
	if wet then
		local w = s.stats and s.stats.water
		site.wet = (w and w.kind == "river") and "river" or "shore"
		-- (the nearest water's kind: a lake / pond shore gets the lake's words, not the sea's)
		site.lake = w ~= nil and (w.body == "lake" or w.body == "pond")
		-- (generated names: the nearest named river / lake of the stop's kind of water)
		site.waterName = D.waterNameAt(self.namesWaters or (self.stopsCfg and self.stopsCfg.waters), x, y,
			site.wet == "river" and "r" or (site.lake and "l" or nil))
	end
	-- (stop names' climate fit, 2026-10-14, NEXT_PHASE_BRIEF 49: the map's climate, and the survey's water read: no lake
	-- within SN.LAKE_NEAR_M -> no lake words, "Lakeside" on a map without lakes; a "lake" the town's stats read is the sea)
	site.climate = SN.climateKey(self.cfg.climate)
	local shape = self.mapShape
	if shape then
		local okW, wn = pcall(MS.waterNear, shape, x, y, SN.LAKE_NEAR_M)
		if okW and type(wn) == "table" then
			site.noLake = not wn.lake
			if site.lake and not wn.lake then site.lake, site.lakeFix = false, wn.sea and "sea" or "noLake" end
		end
	end
	local okF, f = pcall(SITE.features, s.stats, s.wide)
	site.valleyTown = okF and f and f.kind == "valley" or false
	if s.forest then
		local okC, cv = pcall(FO.cover, s.forest, x, y)
		if okC then site.forest = cv end
	end
	if E.railStations and (self.stopRail == nil or now - (self.stopRailUs or 0) > D.STOP_RAIL_S * 1e6) then
		self.stopRail, self.stopRailUs = E.railStations() or {}, now
	end
	for i, st in ipairs(self.stopRail or {}) do
		if i > 500 then break end
		local d = G.dist(x, y, st.x, st.y)
		if site.station == nil or d < site.station then site.station = d end
	end
	-- (unique stop names, ot_stopname 2026-10-13: the parts of a name the spot offers)
	site.seed = math.floor(x) * 7919 + math.floor(y) * 104729 + (tonumber(t) or 0)
	site.town = E.name(t)
	site.high = (site.dz or 0) >= SN.HIGH_DZ or (site.ring or 0) >= NM.STOP_CREST_DZ
	site.trees = SN.treesFor(s.species, self.cfg.climate, site.wet ~= nil, self.stopsCfg and self.stopsCfg.cls)
	if pos and site.dist and site.dist >= SN.COMPASS_MIN_M then site.compass = SN.compass(pos[1], pos[2], x, y) end
	-- the neighbour town the street heads toward: a stop past the town's inner part whose bearing from the centre points
	-- at a town (within TOWARD_DEG, TOWARD_MAX_M; the nearest such)
	local r = s.extR or 0
	if pos and site.dist and site.dist >= math.max(SN.TOWARD_MIN_M, SN.TOWARD_MIN_F * r) then
		local a = G.atan2(y - pos[2], x - pos[1])
		for _, nb in ipairs(self:neighbours(t, pos)) do
			if nb.dist <= SN.TOWARD_MAX_M and math.abs(G.angleDiff(nb.dir, a)) <= math.rad(SN.TOWARD_DEG) then
				local nm = E.name(nb.town)
				if type(nm) == "string" and nm ~= "" then site.toward = nm break end
			end
		end
	end
	-- works / quarries / farms within IND_R (the map's industry list, read for the planner anyway)
	if self.indAll == nil and E.industries then
		local okL, all = pcall(E.industries)
		self.indAll, self.indAllUs = okL and all or {}, now
	end
	local best = nil
	for i, it in ipairs(self.indAll or {}) do
		if i > 4000 then break end
		local ix, iy = it[1] or it.x, it[2] or it.y
		if ix and iy then
			local d = G.dist(x, y, ix, iy)
			if d <= SN.IND_R and (best == nil or d < best) then best, site.ind, site.indE = d, SN.indKind(it.file), it.e end
		end
	end
	-- the industry's own name, without its town's ("Crop Farm" -> "Crop Farm Gate")
	if site.indE and E.name then
		local okN, nm = pcall(E.name, site.indE)
		if okN and type(nm) == "string" then
			local towns = {}
			for i, tt in ipairs(self:townIds(now)) do
				if i > 400 then break end
				local tn = E.name(tt)
				if type(tn) == "string" then towns[#towns + 1] = tn end
			end
			site.indName = SN.indShort(nm, towns)
		end
	end
	-- (bridge stops, 2026-10-14: a stop on a bridge edge, or just off its end, takes the bridge's names first)
	if st ~= nil and SN.BRIDGE_ON and E.stopBridge then
		local okB, info = pcall(E.stopBridge, st, x, y)
		if not okB then site.bridgeRead = "fail" else
			site.bridge, site.bridgeRead = SN.bridgeCue(info, x, y)
			if site.bridgeRead == nil then site.bridgeRead = (type(info) == "table" and info.read) and "edge" or "noEdge" end
		end
		if site.bridge then
			site.riverName = D.waterNameAt(self.namesWaters or (self.stopsCfg and self.stopsCfg.waters), x, y, "r")
			local okY, yr = pcall(E.year)
			site.year = okY and tonumber(yr) or nil
		end
	end
	return site
end

--- The map's industry names as a set (re-read every STOP_USED_S x 3).
function Driver:industryNameSet(now)
	local E = self.E
	if self.stopIndNames == nil or now - (self.stopIndUs or 0) > D.STOP_USED_S * 3e6 then
		local set = {}
		if E.industryNames then
			for _, it in ipairs(E.industryNames(NM.MAX_INDUSTRIES) or {}) do
				if type(it.name) == "string" then set[it.name] = true end
			end
		end
		self.stopIndNames, self.stopIndUs = set, now
	end
	return self.stopIndNames
end

--- The names on the map a new stop name must not repeat: every station group's name, read live (run
--- 2026-10-13_2240_sqot-dev: a 60 s cache missed a stop the game had just named "The Grove", and another stop was renamed
--- to it), plus the names sent and not yet applied. With E.stationGroups the names are kept per group and only new
--- groups are read (the stop's own group and the queued ones always afresh), all of them again every STOP_USED_S;
--- without it the whole map is read each time (E.mapStopNames).
D.STOP_USED_S = 60
function Driver:stopUsed(town, skip, now, fresh)
	local E = self.E
	local used = {}
	if E.stationGroups then
		if self.stopGroupNames == nil or now - (self.stopMapUs or 0) > D.STOP_USED_S * 1e6 then
			self.stopGroupNames, self.stopMapUs = {}, now
		end
		local cache = self.stopGroupNames
		local again = {}
		if skip then again[skip] = true end
		for st in pairs(fresh or {}) do
			local g = E.stationGroup and E.stationGroup(st)
			if g then again[g] = true end
		end
		for i, g in ipairs(E.stationGroups() or {}) do
			if i > 20000 then break end
			if cache[g] == nil or again[g] then
				local okN, n = pcall(E.name, g)
				cache[g] = (okN and type(n) == "string") and n or false
			end
			if cache[g] then used[cache[g]] = true end
		end
	elseif E.mapStopNames then
		for n in pairs(E.mapStopNames(nil) or {}) do used[n] = true end
	elseif E.townStopNames and town then
		-- (an engine without the map-wide read: the town's own stops at least)
		for n in pairs(E.townStopNames(town, skip) or {}) do used[n] = true end
	end
	for n in pairs(self.stopGiven or {}) do used[n] = true end
	return used
end

D.STOP_SECTIONS = true
D.STOP_SECTION_R = 700        -- m: the streets read around a stop for its section
D.STOP_DEV_BASES = true       -- dev test stops save their bases too (they are real stops)

--- The street section through the stop at (x, y) (ot_stopname.section on the streets around it), or nil.
function Driver:stopSection(x, y)
	local E = self.E
	if E.streets == nil then return nil end
	local snap = { nodes = {}, edges = {} }
	local seen = {}
	for _, ed in ipairs(E.streets(x, y, D.STOP_SECTION_R) or {}) do
		for k = 0, 1 do
			local n, p = k == 0 and ed.n0 or ed.n1, k == 0 and ed.p0 or ed.p1
			if n and p and not seen[n] then
				seen[n] = true
				snap.nodes[#snap.nodes + 1] = { id = n, x = p[1], y = p[2], z = p[3] }
			end
		end
		if ed.n0 and ed.n1 then
			snap.edges[#snap.edges + 1] = { id = ed.id, node0 = ed.n0, node1 = ed.n1, class = "small", t0 = ed.t0, t1 = ed.t1 }
		end
	end
	if #snap.edges == 0 then return nil end
	return SN.section(OG.fromSnapshot(snap), x, y)
end

--- The section bases: saved (ot_saved `sb`) and this session's.
function Driver:stopBaseList()
	local out, seen = {}, {}
	for _, b in ipairs(self.stopBasesNew or {}) do out[#out + 1] = b; seen[b.b] = true end
	for _, b in ipairs(SV.stopBases(self.saved)) do if not seen[b.b] then out[#out + 1] = b end end
	return out
end

--- Names one queued stop e (see stopsTick); fresh = every queued station.
function Driver:stopName(e, c, fresh, now)
	local E = self.E
	local g = E.stationGroup(e.st)
	local why = nil
	local cur = g and E.name(g) or nil
	if g == nil then why = "noGroup"
	elseif e.n ~= nil and cur ~= e.n then why = "renamed" end
	if why == nil then
		for _, m in ipairs(E.groupStations(g)) do
			if not fresh[m] then why = "joined" break end
		end
	end
	-- (a stop the game named after the industry beside it, "Whitehill Clay Pit" in run 2026-10-13_2113_sqot-dev, keeps
	-- that name: it tells the player what the stop serves)
	if why == nil and cur and self:industryNameSet(now)[cur] then why = "industry" end
	local town = why == nil and E.stationTown(e.st) or nil
	if why == nil and town == nil then why = "noTown" end
	local x, y = e.x, e.y
	if why == nil and x == nil then x, y = E.boxCentre(e.st) end
	if why == nil and x == nil then why = "noPos" end
	if why then
		self:debug("STOPNAME", { { "group", g or -1 }, { "station", e.st }, { "old", cur or "-" }, { "new", "-" }, { "why", why } })
		return
	end
	local site = self:stopSite(town, x, y, now, e.k == nil and e.st or nil)
	if e.k ~= nil then return self:stationName(e, g, cur, town, x, y, site, c, fresh, now) end
	local themes = NM.stopThemes(site)
	-- (no theme: the outskirts / centre band between them still gets a name, as the "outskirts" kind of street)
	if #themes == 0 then themes = { "outskirts" } end
	-- (unique on the whole map, ot_stopname 2026-10-13: every station group's name plus this session's names)
	local used = self:stopUsed(town, g, now, fresh)
	self.stopCache = self.stopCache or {}
	-- (NEXT_PHASE_BRIEF 53 Part B: the town's leftover named-feature claim, a river or lake beside it that its name doesn't
	-- carry, goes to its first stop away from that water: "Glaven Lane"; once a stop name carries it, it is spent)
	if site.waterName == nil and not site.bridge then
		local waters = self.namesWaters or (self.stopsCfg and self.stopsCfg.waters)
		local okC, claim = pcall(PN.leftClaim, waters, used, x, y, { own = E.name(town), cap = 1, maxD = D.STOP_WATER_NAME_M })
		if okC and claim then site.claimName = claim.s or claim.n end
	end
	-- (street sections, 2026-10-14: a later stop on the section of a named stop takes a variant of its name)
	local sec, base, along = nil, nil, nil
	if D.STOP_SECTIONS then
		local okS, sc = pcall(self.stopSection, self, x, y)
		if okS then sec = sc end
		if sec then base, along = SN.findBase(sec, self:stopBaseList(), x, y) end
	end
	local name, theme, info = nil, nil, nil
	local hz = self.stopSampler and self.stopSampler.height(x, y) or 0
	-- (a bridge stop: the bridge's names before a section variant; none left: the section and the other themes)
	if site.bridge then
		local bn, bt, bi = SN.pick(c.cls, themes, site, c.streets, used, self.stopCache)
		if bt == "bridge" then name, theme, info = bn, bt, bi end
	end
	if base and name == nil then
		local cands = SN.candidates(c.cls, SN.themesFor(themes, site), site, c.streets, self.stopCache)
		local mark = nil
		for _, e in ipairs(cands) do
			if e.spec and (e.kind == "mark" or e.kind == "theme" or e.kind == "tree") then
				mark = SN.markWord(c.cls, e.spec, base.b)
				if mark then break end
			end
		end
		local pos = self:townState(town).pos
		local core = pos and (G.dist(x, y, pos[1], pos[2]) - G.dist(base.x, base.y, pos[1], pos[2])) or 0
		local vn, how = SN.sectionName(c.cls, base.b, { dir = SN.compass(base.x, base.y, x, y), along = along,
			dz = hz - (base.h or 0), core = core, mark = mark }, used)
		if vn then name, theme, info = vn, "section", { kind = "variant:" .. how, gen = "-", left = 0, total = 0 } end
	end
	if name == nil then name, theme, info = SN.pick(c.cls, themes, site, c.streets, used, self.stopCache) end
	info = info or {}
	local fields = { { "group", g }, { "station", e.st }, { "town", town }, { "old", cur or "-" }, { "new", name or "-" },
		{ "dev", e.dev == true },
		{ "tags", table.concat(themes, ",") }, { "theme", theme or "-" },
		{ "kind", info.kind or "-" }, { "gen", info.gen or "-" }, { "uniq", string.format("%d/%d", info.left or 0, info.total or 0) },
		{ "toward", site.toward or "-" }, { "ind", site.ind or "-" }, { "trees", site.trees and site.trees[1] or "-" },
		{ "compass", site.compass or "-" }, { "high", site.high == true },
		{ "dz", site.dz and string.format("%.0f", site.dz) or "-" }, { "ring", site.ring and string.format("%.0f", site.ring) or "-" },
		{ "wet", site.wet or "-" }, { "forest", site.forest and string.format("%.2f", site.forest) or "-" },
		{ "rail", site.station and string.format("%.0f", site.station) or "-" },
		{ "dist", site.dist and string.format("%.0f", site.dist) or "-" } }
	if site.indName then fields[#fields + 1] = { "indName", site.indName } end
	if site.claimName then fields[#fields + 1] = { "claim", site.claimName } end
	fields[#fields + 1] = { "bridge", site.bridge == "on" and 1 or (site.bridge == "end" and "end" or 0) }
	fields[#fields + 1] = { "bridgeRead", site.bridgeRead or "-" }
	if site.bridge then fields[#fields + 1] = { "river", site.riverName or "-" } end
	-- (climate fit: the climate, the survey's lake read, the candidates dropped for a climate / lake word)
	fields[#fields + 1] = { "climate", site.climate or "-" }
	fields[#fields + 1] = { "noLake", site.noLake == nil and "-" or site.noLake }
	if site.lakeFix then fields[#fields + 1] = { "lakeFix", site.lakeFix } end
	local dr = info.drop
	fields[#fields + 1] = { "misfit", dr and string.format("climate:%d,lake:%d", dr.climate or 0, dr.lake or 0) or "-" }
	if name == nil or name == cur then
		-- (no unique fitting name: the game's name stays)
		fields[#fields + 1] = { "why", name == nil and "noUnique" or "same" }
		self:debug("STOPNAME", fields)
		return
	end
	fields[#fields + 1] = { "section", sec and string.format("%d:%.0f", sec.key, sec.len) or "-" }
	fields[#fields + 1] = { "base", base and base.b or "-" }
	self:log("STOPNAME", fields)
	self.stopGiven = self.stopGiven or {}
	self.stopGiven[name] = true
	-- (the first named stop on a section is its base: saved, so later stops find it after a reload too)
	if sec and base == nil then
		local b = { b = name, x = x, y = y, h = hz }
		self.stopBasesNew = self.stopBasesNew or {}
		self.stopBasesNew[#self.stopBasesNew + 1] = b
		if not e.dev or D.STOP_DEV_BASES then E.sendEvent(SV.EVENT_ID, SV.EV_STOPBASE, b) end
	end
	if self.stopGroupNames then self.stopGroupNames[g] = name end
	E.setName(g, name, function(success)
		if not success then self:log("STOPNAME", { { "group", g }, { "new", name }, { "outcome", "failed" } }) end
	end)
end

--- A new player station (e.k: rail / harbor / street construction) beside an industry: "<Town> Works" / "<Town> Docks"
--- / "<Industry> Halt" (ot_stopname.stationName) when an industry lies within SN.STATION_IND_R and nearer than the
--- town centre; else the game's name stays (debug `why=noIndustry`). Same uniqueness as the stops.
function Driver:stationName(e, g, cur, town, x, y, site, c, fresh, now)
	local E = self.E
	local best, bi = nil, nil
	for i, it in ipairs(self.indAll or {}) do
		if i > 4000 then break end
		local ix, iy = it[1] or it.x, it[2] or it.y
		if ix and iy then
			local d = G.dist(x, y, ix, iy)
			if d <= SN.STATION_IND_R and (best == nil or d < best) then best, bi = d, it end
		end
	end
	local fields = { { "group", g }, { "station", e.st }, { "town", town }, { "old", cur or "-" }, { "kind", "station:" .. e.k },
		{ "indDist", best and string.format("%.0f", best) or "-" }, { "dist", site.dist and string.format("%.0f", site.dist) or "-" } }
	if bi == nil or (site.dist ~= nil and best >= site.dist) then
		fields[#fields + 1] = { "new", "-" }
		fields[#fields + 1] = { "why", bi == nil and "noIndustry" or "nearerTown" }
		self:debug("STOPNAME", fields)
		return
	end
	local ind = SN.indKind(bi.file)
	local indName = nil
	if bi.e and E.name then
		local okN, nm = pcall(E.name, bi.e)
		if okN and type(nm) == "string" then
			local towns = {}
			for i, tt in ipairs(self:townIds(now)) do
				if i > 400 then break end
				local tn = E.name(tt)
				if type(tn) == "string" then towns[#towns + 1] = tn end
			end
			indName = SN.indShort(nm, towns)
		end
	end
	local used = self:stopUsed(town, g, now, fresh)
	local name, form = SN.stationName(c.cls, E.name(town), ind, indName, e.k == "harbor", used)
	fields[#fields + 1] = { "new", name or "-" }
	fields[#fields + 1] = { "ind", ind }
	fields[#fields + 1] = { "form", form or "-" }
	if name == nil or name == cur then
		fields[#fields + 1] = { "why", name == nil and "noUnique" or "same" }
		self:debug("STOPNAME", fields)
		return
	end
	fields[#fields + 1] = { "section", sec and string.format("%d:%.0f", sec.key, sec.len) or "-" }
	fields[#fields + 1] = { "base", base and base.b or "-" }
	self:log("STOPNAME", fields)
	self.stopGiven = self.stopGiven or {}
	self.stopGiven[name] = true
	-- (the first named stop on a section is its base: saved, so later stops find it after a reload too)
	if sec and base == nil then
		local b = { b = name, x = x, y = y, h = hz }
		self.stopBasesNew = self.stopBasesNew or {}
		self.stopBasesNew[#self.stopBasesNew + 1] = b
		if not e.dev or D.STOP_DEV_BASES then E.sendEvent(SV.EVENT_ID, SV.EV_STOPBASE, b) end
	end
	if self.stopGroupNames then self.stopGroupNames[g] = name end
	E.setName(g, name, function(success)
		if not success then self:log("STOPNAME", { { "group", g }, { "new", name }, { "outcome", "failed" } }) end
	end)
end

---------------------------------------------------------------------------
-- stages

function Driver:finish(t, outcome, now)
	local job = self.job
	-- (§67: a job with game streets to lock locks them first, stages glock / glockWait, then finishes with this outcome)
	if job ~= nil and job.town == t and job.glockQ and not job.glockStarted and not self.inflight
		and outcome ~= "skip" and outcome ~= "dry"
		and not (type(job.why) == "string" and (job.why:sub(1, 6) == "error:" or job.why == "timeout")) then
		job.glockStarted = true
		job.glockOutcome = outcome
		job.stage = "glock"
		return nil
	end
	-- a demand build that left demand (a fast grower): checked again soon and first (ot_assess "more", 2026-10-13);
	-- job.outcome stays "built"
	local cd = outcome
	if outcome == "built" and job and job.town == t and job.trigger == "demand" and job.dem and job.spec
		and job.dem.edges - #job.spec.edges >= A.MORE_MIN_EDGES then
		cd = "more"
	end
	-- (a wedge frame serves little of the demand: the town's normal build follows soon)
	if outcome == "built" and job and job.town == t and job.framePlan and job.dem and job.dem.edges >= A.DEMAND_MIN_EDGES then
		cd = "more"
	end
	local s = A.cooldown(self.sched, t, now, cd)
	-- (§59: the empty plans in a row end with a build)
	if outcome == "built" and self.towns[t] then self.towns[t].emptyRun = 0 end
	self.job = nil
	if job ~= nil then
		job.outcome = outcome
		if job.onDone then
			local ok, err = pcall(job.onDone, job, outcome)
			if not ok then self:log("ERROR", { { "stage", "onDone" }, { "town", t }, { "err", err } }) end
		end
	end
	return s
end

--- The whole-map reads every measure needs (E.town2buildings, E.parcelMap), shared for MAP_CACHE_US (audit 2026-10-13:
--- the head start's START rows and every CHECK read both maps for the whole map per town). Returns t2b, pmap.
D.MAP_CACHE_US = 500000
function Driver:mapReads(now)
	local c = self.mapCache
	if c == nil or not (now - c.us >= 0 and now - c.us < D.MAP_CACHE_US) then
		c = { us = now, t2b = self.E.town2buildings(), pmap = self.E.parcelMap() }
		self.mapCache = c
	end
	return c.t2b, c.pmap
end

--- Reads one town: buildings -> extent, the streets near it and their lots, capacities, the growth demand and the
--- needs-room verdict (ot_assess). Returns { ext, edges, caps, lots, needs, threshold, why, ratio, dem, buildings,
--- parcelMap, us },
--- or nil, "buildings", count when the town has too few buildings for an extent.
function Driver:measure(t, o)
	local part, reason, n = self:measureReads(t, o)
	if part == nil then return nil, reason, n end
	return self:measureFinish(t, part, o)
end

--- measure, first half (R1, 2026-10-13: CHECK took up to ~54 ms in one frame, Redruth / Okehampton): the town's caps,
--- the whole-map maps (shared), its buildings and the street read. Returns the part (with `us`), or nil, reason, n.
function Driver:measureReads(t, o)
	local E = self.E
	local t0 = self:nowUs()
	local caps = E.townCaps(t)
	local t1 = self:nowUs()
	local t2b, pmap = self:mapReads(t0)
	local t2 = self:nowUs()
	local pts, builtBy = E.townBuildings(t, t2b)
	if #pts < D.MIN_BUILDINGS then return nil, "buildings", #pts end
	local t3 = self:nowUs()
	local ext = A.extent(pts)
	local edges = E.streets(ext.cx, ext.cy, ext.r + D.SNAP_MARGIN)
	-- (§67: the game streets we locked read as the game's, not as the mod's own locked streets)
	self:glockMark(t, edges)
	local t4 = self:nowUs()
	-- (round after the names run: 77 of 786 CHECK lines still took 15-62 ms in one slice; `parts=` says which read)
	return { caps = caps, pmap = pmap, pts = pts, builtBy = builtBy, ext = ext, edges = edges, us = t4 - t0,
		parts = string.format("caps:%d,map:%d,bld:%d,str:%d", t1 - t0, t2 - t1, t3 - t2, t4 - t3) }
end

--- measure, second half: the town network (o.netUs: its budget, default NET_BUDGET_US), the lots, the demand.
function Driver:measureFinish(t, part, o)
	local E = self.E
	local t0 = self:nowUs()
	local caps, pmap, pts, builtBy, ext, edges = part.caps, part.pmap, part.pts, part.builtBy, part.ext, part.edges
	-- (o.noNet: the START rows skip the town network's API reads, audit 2026-10-13)
	local net = (o and o.noNet) and 0 or self:townNetwork(t, ext, edges, o and o.netUs)
	if net > 0 then self:glockMark(t, edges) end
	local townR = ext.r * D.TOWN_EDGE_FACTOR + 50
	local lotEdges = {}
	local s = self:townState(t)
	for _, ed in ipairs(edges) do
		local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
		-- (the town's own streets count wherever they are: arms run beyond the houses' extent, and their empty
		-- frontage must hold the demand trigger back, ot_assess.demand)
		local own = ed.locked == true or s.own[ed.id] == true
		if not ed.owned and isTownTemplate(ed.template) and (own or G.dist(ext.cx, ext.cy, mx, my) <= townR) then
			local pd = pmap and pmap[ed.id] or nil
			lotEdges[#lotEdges + 1] = { id = ed.id, mx = mx, my = my, len = G.dist(ed.p0[1], ed.p0[2], ed.p1[1], ed.p1[2]),
				parcels = pd ~= nil and E.parcelCount(pd) or nil, built = builtBy[ed.id] or 0, town = true, own = own }
		end
	end
	local lots = A.lots(lotEdges, ext)
	-- (§65: a town whose mod streets are all locked keeps more of its own frontage ahead of the demand)
	local lm0 = self:townLockMode(t)
	local lockK = (D.LOCK_LEAD_K and lm0 == "mod") and D.LOCK_LEAD_K or ((D.STEER_LEAD_K and lm0 == "steer") and D.STEER_LEAD_K or nil)
	local dem = A.demand(s.ledger, caps, lots, self.opts.lookahead, #pts, self:densifyDemand(t), lockK)
	local needs, threshold, why, ratio = A.needsRoom(lots, caps, self.opts.lookahead, dem)
	local us2 = self:nowUs() - t0
	return { ext = ext, edges = edges, caps = caps, lots = lots, needs = needs, threshold = threshold, why = why,
		ratio = ratio, dem = dem, buildings = #pts, parcelMap = pmap ~= nil, us = part.us + us2, pts = pts, net = net, builtBy = builtBy,
		lotEdges = lotEdges, sliceUs = math.max(part.us, us2), parts = (part.parts or "-") .. string.format(",fin:%d", us2) }
end

--- Adds (in place) the town streets connected to `edges` that lie beyond the snapshot circle: from every node of
--- the set whose true degree (E.nodeStreetEdges) is larger than in the set, the missing edges are fetched (E.edge)
--- and followed while they are plain town street templates, not player owned, within NET_RADIUS of the extent
--- centre and their far node's closest town is t. Returns the number of edges added (0 without E.edge).
function Driver:townNetwork(t, ext, edges, budgetUs)
	local E = self.E
	if E.edge == nil or E.nodeStreetEdges == nil or E.closestTown == nil then return 0 end
	local have, deg = {}, {}
	for _, ed in ipairs(edges) do
		have[ed.id] = true
		deg[ed.n0] = (deg[ed.n0] or 0) + 1
		deg[ed.n1] = (deg[ed.n1] or 0) + 1
	end
	local r2 = D.NET_RADIUS * D.NET_RADIUS
	local queue, qi, added, townOf = {}, 1, 0, {}
	-- only nodes near the snapshot circle can miss edges (the octree returns every edge reaching into it)
	local inner = math.max(0, ext.r + D.SNAP_MARGIN - 150)
	local pos = {}
	for _, ed in ipairs(edges) do pos[ed.n0], pos[ed.n1] = ed.p0, ed.p1 end
	for n in pairs(deg) do
		local p = pos[n]
		if p and (p[1] - ext.cx) ^ 2 + (p[2] - ext.cy) ^ 2 >= inner * inner then queue[#queue + 1] = n end
	end
	table.sort(queue)
	local visited = {}
	-- (audit 2026-10-13: up to NET_MAX API reads per measure; also ends after NET_BUDGET_US, the rest next check)
	local t0 = self:nowUs()
	while qi <= #queue and added < D.NET_MAX do
		if qi % 32 == 0 and self:nowUs() - t0 > (budgetUs or D.NET_BUDGET_US) then break end
		local n = queue[qi]
		qi = qi + 1
		if not visited[n] then
			visited[n] = true
			local ids = E.nodeStreetEdges(n)
			if #ids > (deg[n] or 0) then
				for _, id in ipairs(ids) do
					if not have[id] and added < D.NET_MAX then
						have[id] = true
						local ed = E.edge(id)
						if ed and isTownTemplate(ed.template) and not ed.owned then
							local far = ed.n0 == n and ed.n1 or ed.n0
							local fp = ed.n0 == n and ed.p1 or ed.p0
							if (fp[1] - ext.cx) ^ 2 + (fp[2] - ext.cy) ^ 2 <= r2 then
								if townOf[far] == nil then townOf[far] = E.closestTown(fp[1], fp[2]) or false end
								if townOf[far] == t then
									edges[#edges + 1] = ed
									added = added + 1
									deg[ed.n0] = (deg[ed.n0] or 0) + 1
									deg[ed.n1] = (deg[ed.n1] or 0) + 1
									queue[#queue + 1] = far
								end
							end
						end
					end
				end
			end
		end
	end
	return added
end

---------------------------------------------------------------------------
-- §65 (2026-10-15): street builders, the stall guard

D.FAST_FRONT = 1           -- (2026-10-18) blocks beyond the growth front per unit of a demand build's fast factor above 1
D.STALL = true             -- the stall guard (ot_assess.stall) for "mod"-locked towns; false: off
D.STALL_INC_MUL = 1.5      -- a stalled town's increment: this x its usual size ...
D.STALL_MAX_EDGES = 36     -- ... at most this many edges
D.STALL_OWN_EMPTY_M = 600  -- ... and this many m more own empty budget (ot_core OWN_EMPTY_BASE; never the tight base)
D.STALL_ENV_SCALE = 1.3    -- level 2+: the shape's envelope starts this much wider (ot_core opts.envScale0)
D.STALL_FOREST_STEP = 1    -- level 3: the forest hold this many HOLD_STEPs looser (ot_select limits.forestStep), last
D.STREETS_EVERY_S = 600    -- real s between two STREETS lines (always on: the map's mod vs game street edges)

--- The town's street edges by builder (ot_assess.edgeSplit) with its core: the saved frame's `e0`, else the edges not
--- the mod's at this session's first check of the town.
function Driver:streetSplit(t, lots, saved)
	local s = self:townState(t)
	local fr = SV.frame(saved or self.saved, t)
	local core = fr and fr.core or nil
	if core == nil then
		if s.core0 == nil and lots and lots.edges then s.core0 = lots.edges - (lots.ownEdges or 0) end
		core = s.core0
	end
	return A.edgeSplit(lots, core)
end

--- The stall guard fired for town t at this check (level, or ev = "capped"): STALL line (always on); unless the town is
--- held (hold) or over its target, the check builds (why=stall when it would not) and the job carries the level (m.stall).
function Driver:stallGuard(job, t, m, level, ev, hold)
	local st = self:townState(t).stall or {}
	local fields = { { "town", t }, { "name", self.E.name(t) }, { "event", ev or "fire" }, { "level", level or 0 },
		{ "streak", st.n or 0 }, { "fires", st.fires or 0 }, { "max", A.STALL_MAX },
		{ "capRatio", m.ratio and string.format("%.3f", m.ratio) or "?" }, { "buildings", m.buildings },
		{ "since", st.b0 or "-" }, { "why", m.why or "-" }, { "open", m.lots and m.lots.open or 0 },
		{ "ownOpen", m.lots and m.lots.ownOpen or 0 }, { "lead", m.dem and m.dem.lead or "-" } }
	local applied = false
	if level and not hold and m.why ~= "over" then
		applied = true
		m.stall = level
		if not m.needs then m.needs, m.why = true, "stall" end
		-- (§67: each fire opens one more valve, at most GL.VALVE_STALL_MAX: before level 3 relaxes the forest hold)
		if self:townGameLock(t) then
			local gs = self:glockState(t)
			gs.extra = math.min(GL.VALVE_STALL_MAX, (gs.extra or 0) + 1)
			fields[#fields + 1] = { "valveExtra", gs.extra }
		end
	end
	fields[#fields + 1] = { "applied", applied }
	fields[#fields + 1] = { "held", hold and tostring(hold) or "-" }
	self.counts.stalls = (self.counts.stalls or 0) + (applied and 1 or 0)
	self:log("STALL", fields)
end

--- Notes the town's street split for the STREETS line; logs it every STREETS_EVERY_S (always on, one line for the map):
--- towns seen, their edges, the mod's, the game's (beyond the cores), the cores, the game's share of the new streets, the
--- towns in a stall streak (STALL_N checks or more), the guard's fires, and the towns per lock.
function Driver:streetsNote(t, m, split, now)
	local s = self:townState(t)
	s.streets = { edges = m.lots and m.lots.edges or 0, mod = split.mod, game = split.game, core = split.core,
		stall = s.stall and s.stall.n or 0, fires = s.stall and s.stall.fires or 0, lock = s.lockMode,
		valves = s.glock and #s.glock.valves or 0, glocked = s.glock and s.glock.tally and s.glock.tally.glocked or 0,
		open = s.glock and s.glock.tally and s.glock.tally.open or 0, gk = s.gameLock == true,
		lockShare = s.lockShare, tips = s.glock and D.tipCount(s.glock.valves) or 0, spikeTrim = s.spikeTrim,
		rakeJoin = s.rakeJoin, wiggleHeld = s.wiggleHeld, knotHeld = s.knotHeld, hookHeld = s.hookHeld, wideRuns = s.wideRuns,
		nearMiss = s.nearMissBuilt }
	if self.streetsUs == nil then self.streetsUs = now end
	if now - self.streetsUs < D.STREETS_EVERY_S * 1e6 then return end
	self.streetsUs = now
	local n, edges, mod, game, core, stalled, fires, nMod, nLegacy = 0, 0, 0, 0, 0, 0, 0, 0, 0
	local valves, glocked, open, nGk = 0, 0, 0, 0
	local nSteer, lsN, lsSum, tips, spike, rake, wig, knot, hook = 0, 0, 0, 0, 0, 0, 0, 0, 0
	local nmBuilt = 0
	-- (§73: the towns' medium / large runs summed, from their last SNAPSHOT)
	local wide = { runs = 0, edges = 0, len = 0, short = 0, lone = 0, max = 0, by = {} }
	local wideTowns = 0
	for _, st in pairs(self.towns) do
		local x = type(st) == "table" and st.streets or nil
		local xw = x and x.wideRuns
		if xw then
			wideTowns = wideTowns + 1
			for _, k in ipairs({ "runs", "edges", "len", "short", "lone" }) do wide[k] = wide[k] + (xw[k] or 0) end
			wide.max = math.max(wide.max, xw.max or 0)
			for k, v in pairs(xw.by or {}) do wide.by[k] = (wide.by[k] or 0) + v end
		end
		if x then
			n = n + 1
			edges, mod = edges + x.edges, mod + (x.mod or 0)
			game, core = game + (x.game or 0), core + (x.core or 0)
			if (x.stall or 0) >= A.STALL_N then stalled = stalled + 1 end
			fires = fires + (x.fires or 0)
			if x.lock == "mod" then nMod = nMod + 1 elseif x.lock == "steer" then nSteer = nSteer + 1 else nLegacy = nLegacy + 1 end
			if x.lockShare then lsN, lsSum = lsN + 1, lsSum + x.lockShare end
			tips, spike, rake, wig = tips + (x.tips or 0), spike + (x.spikeTrim or 0), rake + (x.rakeJoin or 0), wig + (x.wiggleHeld or 0)
			knot = knot + (x.knotHeld or 0)
			hook = hook + (x.hookHeld or 0)
			nmBuilt = nmBuilt + (x.nearMiss or 0)
			valves, glocked, open = valves + (x.valves or 0), glocked + (x.glocked or 0), open + (x.open or 0)
			if x.gk then nGk = nGk + 1 end
		end
	end
	self:log("STREETS", { { "towns", n }, { "edges", edges }, { "modEdges", mod }, { "gameEdges", game }, { "coreEdges", core },
		{ "gameShare", (game + mod) > 0 and string.format("%.2f", game / (game + mod)) or "-" }, { "stalled", stalled },
		{ "stallFires", fires }, { "lockMod", nMod }, { "lockLegacy", nLegacy }, { "gameLock", nGk }, { "valves", valves },
		{ "glocked", glocked }, { "gameOpen", open }, { "glockedSession", self.glockN or 0 },
		{ "glockRefund", self.glockRefundSum or 0 }, { "refund", self.refundSum or 0 }, { "lockSteer", nSteer },
		{ "lockShare", lsN > 0 and string.format("%.2f", lsSum / lsN) or "-" }, { "tips", tips }, { "spikeTrim", spike },
		{ "rakeJoin", rake }, { "wiggleHeld", wig }, { "knotHeld", knot }, { "hookHeld", hook },
		{ "wideRuns", wideTowns > 0 and D.wideAuditText(wide) or "-" }, { "nearMiss", nmBuilt } })
end

---------------------------------------------------------------------------
-- §67 (2026-10-15): lock the game's own streets, steer with valves (ot_glock)

D.GLOCK = true             -- game-street locking and valves (ot_glock) for "mod"-locked towns; false: off
D.GLOCK_DEFAULT = true     -- towns framed from now on get it (ot_hooks.glockDefault overrides); a frame keeps its `gk`
D.GLOCK_SEEN_MAX = 20000   -- first-seen stamps kept per town at most (then reset: the settle time starts again)
D.VALVE_CANDS = 120        -- valve anchor candidates scored per check at most (the outermost)
D.VALVE_ANCHOR_M = 20      -- m: an unlocked edge whose midpoint lies this close to a valve's point is its anchor
D.STEER_FACE_MAX = 20000   -- §69: steer towns' cached per-edge probes (ot_lockpol.gameLock) at most, then reset

--- Does town t get its game streets locked and the valves (§67)? Only "mod"-locked towns; a saved frame decides (`gk`;
--- a frame without it: no, the §65 lock only), a town without a frame gets ot_hooks.glockDefault or GLOCK_DEFAULT.
function Driver:townGameLock(t, saved)
	if not (D.GLOCK and GL.ON) then return false end
	local s = self:townState(t)
	if s.gameLock ~= nil then return s.gameLock end
	local on = false
	if D.lockFamily(self:townLockMode(t, saved)) then
		local fr = SV.frame(saved or self.saved, t)
		if fr ~= nil then
			on = fr.gameLock == true
		else
			local d = H.glockDefault
			if d == nil then d = D.GLOCK_DEFAULT end
			on = d == true
		end
	end
	s.gameLock = on
	return on
end

--- The town's lock state (session): ids (the game streets we rebuilt locked, with the saved `gx`), seen (first seen us),
--- bad (left alone), fails, n (locked this session), valves (open), rest (headings closed lately), bo (backoff), extra
--- (the stall guard's valves), core (edges at the first sight before the first frame), ctx (the valve context).
function Driver:glockState(t, saved)
	local s = self:townState(t)
	local gs = s.glock
	if gs == nil then
		gs = { ids = SV.glocked(saved or self.saved, t), seen = {}, seenN = 0, bad = {}, fails = {}, n = 0, valves = {},
			rest = {}, bo = {}, extra = 0, other = {} }
		s.glock = gs
	end
	return gs
end

--- Marks the edges we locked (§67) so the rest of the mod still reads `locked` as the mod's own streets: ed.locked =
--- false, ed.glocked = true. In place; edges = edge records.
function Driver:glockMark(t, edges, saved)
	if not self:townGameLock(t, saved) then return end
	local ids = self:glockState(t, saved).ids
	if next(ids) == nil then return end
	for i = 1, math.min(#(edges or {}), GL.SCAN_MAX) do
		local ed = edges[i]
		if ed.locked and ids[ed.id] then
			ed.locked, ed.glocked = false, true
		end
	end
end

--- The valve context from a plan's style (snapshot stage): the land lean, the tree grid, the gaps, the arms, the grower,
--- the water probe. Never for dev-forced jobs.
function Driver:glockCtx(job, style)
	if style == nil or job.force or job.dry or job.pure or job.shape or job.form then return end
	if not self:townGameLock(job.town) then return end
	local gs, s = self:glockState(job.town), self:townState(job.town)
	local sh = style.shape
	gs.ctx = { field = style.land, fg = s.forest, gaps = style.gaps, arms = sh and sh.arms or nil,
		grower = style.grower == "organic" and "organic" or "grid", wet = s.sampler and s.sampler.water or nil }
end

local function unlockedTown(ed)
	return GL.isTownTemplate(ed.template) and not ed.owned and not ed.locked and not ed.glocked
end

--- One check of the town's valves (§67): the open ones counted and closed (quota / age / gone), new ones picked
--- (GL.pickValves), and, when still short, the heading a valve stub should take (gs.stubWant). VALVE lines (always on).
function Driver:glockValves(t, m, gs, now)
	local ctx = gs.ctx
	if ctx == nil then gs.vwhy = "noCtx"; return end
	local s = self:townState(t)
	ctx.cx, ctx.cy, ctx.extR, ctx.rest = m.ext.cx, m.ext.cy, m.ext.r, gs.rest
	local edges = m.edges or {}
	local n = math.min(#edges, GL.SCAN_MAX)
	for i = #gs.valves, 1, -1 do
		local v = gs.valves[i]
		local zone, anchorOk = {}, false
		for k = 1, n do
			local ed = edges[k]
			if unlockedTown(ed) then
				local mx, my = GL.mid(ed)
				if ed.id == v.anchor or G.dist(mx, my, v.x, v.y) <= D.VALVE_ANCHOR_M then anchorOk = true end
				if not s.own[ed.id] and GL.inZone(v, mx, my) then zone[#zone + 1] = ed.id end
			end
		end
		local why = GL.valveCheck(v, zone, anchorOk)
		if why then
			table.remove(gs.valves, i)
			gs.rest[#gs.rest + 1] = v.a
			while #gs.rest > 8 do table.remove(gs.rest, 1) end
			self:log("VALVE", { { "town", t }, { "name", self.E.name(t) }, { "event", "close" }, { "heading", GL.deg(v.a) },
				{ "dir", LAND.compass(v.a) }, { "kind", v.kind }, { "why", why }, { "n", v.n or 0 }, { "quota", v.quota },
				{ "checks", v.checks or 0 }, { "valves", #gs.valves } })
		end
	end
	local want = GL.wantValves(ctx.grower, m.ext.r, gs.extra)
	gs.want = want
	if #gs.valves >= want then gs.stubWant = nil; return end
	-- (§69 steer towns: the valves are the tips their builds leave open (Driver:steerPrep / glockStubBuilt); their rim
	-- streets toward open land stay open anyway, so no game anchor and no stub is picked)
	if self:townLockMode(t) == "steer" then gs.stubWant = nil; return end
	local cands = {}
	local minD = GL.VALVE_OUT_MIN * math.max(100, m.ext.r or 0)
	for k = 1, n do
		local ed = edges[k]
		if unlockedTown(ed) and (ed.objects or 0) == 0 and not ed.inConstruction and (ed.etype == nil or ed.etype == "normal") then
			local mx, my = GL.mid(ed)
			local d = G.dist(m.ext.cx, m.ext.cy, mx, my)
			if d >= minD then
				cands[#cands + 1] = { id = ed.id, mx = mx, my = my, d = d, tip = false, ed = ed,
					kind = s.own[ed.id] and "stub" or ((gs.core and gs.core[ed.id]) and "core" or "game") }
			end
		end
	end
	table.sort(cands, function(a, b)
		if math.abs(a.d - b.d) > 1e-6 then return a.d > b.d end
		return a.id < b.id
	end)
	while #cands > D.VALVE_CANDS do cands[#cands] = nil end
	-- (a dead-end tip: one of its nodes has no other edge in the read)
	local deg = {}
	for k = 1, n do
		local ed = edges[k]
		deg[ed.n0] = (deg[ed.n0] or 0) + 1
		deg[ed.n1] = (deg[ed.n1] or 0) + 1
	end
	for _, c in ipairs(cands) do c.tip = deg[c.ed.n0] == 1 or deg[c.ed.n1] == 1 end
	local picks, rej = GL.pickValves(cands, ctx, gs.valves, want)
	for _, p in ipairs(picks) do
		local v = { anchor = p.id, x = p.x, y = p.y, a = p.a, kind = p.kind, why = p.why, score = p.score,
			quota = GL.valveQuota(ctx.grower), checks = 0, n = 0, z0 = {}, openUs = now }
		for k = 1, n do
			local ed = edges[k]
			if unlockedTown(ed) and not s.own[ed.id] then
				local mx, my = GL.mid(ed)
				if GL.inZone(v, mx, my) then v.z0[ed.id] = true end
			end
		end
		gs.valves[#gs.valves + 1] = v
		self:valveOpenLog(t, v, want, gs)
	end
	if #gs.valves < want then
		local a, sc = GL.stubHeading(ctx, gs.valves)
		local rt = {}
		for k, c in pairs(rej) do rt[#rt + 1] = k .. ":" .. c end
		table.sort(rt)
		local txt = a and tostring(GL.deg(a)) or "-"
		if gs.stubLogged ~= txt then
			gs.stubLogged = txt
			self:log("VALVE", { { "town", t }, { "name", self.E.name(t) }, { "event", "want" },
				{ "heading", a and GL.deg(a) or "-" }, { "dir", a and LAND.compass(a) or "-" },
				{ "score", sc and string.format("%.2f", sc) or "-" }, { "valves", #gs.valves }, { "want", want },
				{ "rejected", #rt > 0 and table.concat(rt, ",") or "-" } })
		end
		gs.stubWant = a
	else
		gs.stubWant = nil
	end
end

--- Open tip valves (§69) among a valve list.
function D.tipCount(list)
	local n = 0
	for _, v in ipairs(list or {}) do if v.kind == "tip" then n = n + 1 end end
	return n
end

function Driver:valveOpenLog(t, v, want, gs)
	self:log("VALVE", { { "town", t }, { "name", self.E.name(t) }, { "event", "open" }, { "heading", GL.deg(v.a) },
		{ "dir", LAND.compass(v.a) }, { "kind", v.kind }, { "why", v.why or "-" },
		{ "score", v.score and string.format("%.2f", v.score) or "-" },
		{ "at", string.format("%.0f,%.0f", v.x, v.y) }, { "quota", v.quota }, { "valves", #gs.valves }, { "want", want },
		{ "extra", gs.extra or 0 } })
end

--- At a CHECK (§67): the town's edges first seen, its valves, and the game / core edges to lock this job (job.glockQ,
--- at most GL.BATCH; locked when the job ends, Driver:finish). Returns the town's lock state (CHECK fields) or nil.
function Driver:glockNote(job, t, m, now, saved)
	if not self:townGameLock(t, saved) or m == nil or m.ext == nil then return nil end
	local gs = self:glockState(t, saved)
	local s = self:townState(t)
	local edges = m.edges or {}
	local n = math.min(#edges, GL.SCAN_MAX)
	local inTown = {}
	for _, le in ipairs(m.lotEdges or {}) do inTown[le.id] = true end
	-- (the core: the town's unlocked streets at its first sight before its first frame; a framed town's core is unknown)
	if gs.core == nil and SV.frame(saved or self.saved, t) == nil and not s.frameSent then
		gs.core = {}
		for i = 1, n do
			local ed = edges[i]
			if inTown[ed.id] and unlockedTown(ed) and not s.own[ed.id] then gs.core[ed.id] = true end
		end
	end
	if gs.seenN > D.GLOCK_SEEN_MAX then gs.seen, gs.seenN = {}, 0 end
	for i = 1, n do
		local id = edges[i].id
		if gs.seen[id] == nil then gs.seen[id], gs.seenN = now, gs.seenN + 1 end
	end
	if not job.dry then
		local okV, errV = pcall(self.glockValves, self, t, m, gs, now)
		if not okV then self:log("WARN", { { "stage", "valves" }, { "town", t }, { "err", errV } }) end
	end
	local c = { own = s.own, core = gs.core, built = m.builtBy, bad = gs.bad, seen = gs.seen, nowUs = now,
		valve = function(ed)
			local x, y = GL.mid(ed)
			for _, v in ipairs(gs.valves) do if GL.inZone(v, x, y) then return v end end
			return nil
		end }
	-- (§69 steer towns: only rim streets facing something unwanted, or beyond the outline while young; ot_lockpol)
	if LP.ON and self:townLockMode(t, saved) == "steer" and gs.ctx ~= nil then
		local smp = s.sampler
		-- (the probes cached per edge, D.STEER_FACE_MAX entries at most, then started again: engine water reads)
		if gs.faceCache == nil or (gs.faceN or 0) > D.STEER_FACE_MAX then gs.faceCache, gs.faceN = {}, 0 end
		local fc = setmetatable({}, { __index = gs.faceCache, __newindex = function(_, k, v)
			gs.faceCache[k] = v
			gs.faceN = (gs.faceN or 0) + 1
		end })
		local pc = { outline = s.outline or LP.roundOutline(m.ext.cx, m.ext.cy, 0.8 * (m.ext.r or 0)), cx = m.ext.cx,
			cy = m.ext.cy, mat = s.lockMat, faceCache = fc, ctx = { fg = gs.ctx.fg, gaps = gs.ctx.gaps, field = gs.ctx.field,
			wet = smp and function(x, y) return T.isWater(smp, x, y) end or nil } }
		c.steer = function(ed) return LP.gameLock(ed, pc) end
		-- (§71: the rim streets small woods alone would have locked, this check: CHECK smallWood=)
		pc.small = 0
		c.steerPc = pc
	end
	local list, tally = GL.queue(edges, inTown, c, { cx = m.ext.cx, cy = m.ext.cy, max = 2 * GL.BATCH })
	gs.tally = tally
	gs.smallWood = c.steerPc and c.steerPc.small or nil
	local why = nil
	if job.force or job.dry or job.head then why = "job"
	-- (no plan of the town yet this session: no valves known, nothing locked)
	elseif gs.ctx == nil then why = "noCtx"
	elseif gs.bo.off then why = "off"
	elseif now < (gs.bo.nextUs or 0) then why = "backoff"
	elseif gs.n >= GL.TOWN_MAX then why = "townCap"
	elseif (self.glockN or 0) >= GL.MAP_MAX then why = "mapCap" end
	local q = {}
	if why == nil then
		local E = self.E
		for _, cd in ipairs(list) do
			if #q >= GL.BATCH then break end
			-- (another town's street inside the read: asked once, left alone)
			local mx, my = GL.mid(cd.ed)
			if gs.other[cd.id] == nil and E.closestTown then
				local ct = E.closestTown(mx, my)
				gs.other[cd.id] = ct ~= nil and ct ~= t
			end
			if not gs.other[cd.id] then q[#q + 1] = cd end
		end
		if #q > 0 then job.glockQ = q end
	end
	gs.why = why or (#q == 0 and "none" or "queued")
	return gs
end

--- One proposal try: the lock proposal for ids (E.lockProposal), pre-checked. Returns { ok, why, proposal, ctx, pre,
--- list, skipped }.
function Driver:glockTry(ids)
	local E = self.E
	local okP, prop, list, skipped = pcall(E.lockProposal, ids)
	if not okP then return { ok = false, why = "proposal", err = tostring(prop), list = {}, skipped = {} } end
	local r = { proposal = prop, list = list or {}, skipped = skipped or {} }
	if prop == nil then r.why = "none"; return r end
	local ctx = E.context(H.player == true)
	local pre = E.precheck(prop, ctx)
	r.pre, r.ctx = pre, ctx
	if not pre.ok then r.why = (pre.buildings or 0) > 0 and "buildings" or "precheck"; return r end
	local cost = tonumber(pre.cost)
	if cost and #r.list > 0 and cost / #r.list > GL.COST_MAX then r.why = "cost"; return r end
	r.ok = true
	return r
end

--- GLOCK line of one edge.
function Driver:glockLine(job, e, ok, why, extra)
	local t = job.town
	local c = job.glock and job.glock.info[e.old or e.id] or nil
	local f = { { "town", t }, { "name", self.E.name(t) }, { "edge", e.old or e.id }, { "len", string.format("%.0f", e.len or (c and c.len) or 0) },
		{ "ok", ok }, { "why", why }, { "kind", c and c.kind or "-" }, { "tip", c and c.tip or false } }
	for _, x in ipairs(extra or {}) do f[#f + 1] = x end
	self:log("GLOCK", f)
end

--- Edges refused (alone or as a batch): counted per edge (EDGE_FAILS: left alone), GLOCK lines.
function Driver:glockRefused(job, ids, r)
	local gs = self:glockState(job.town)
	local msgs = r.pre and r.pre.msgs or {}
	for _, id in ipairs(ids) do
		local skip = r.skipped and r.skipped[id]
		if skip then
			-- (it changed since the check: locked, gone, a stop on it, ... left alone for the session unless gone)
			if skip ~= "gone" then gs.bad[id] = true end
			self:glockLine(job, { id = id }, false, "skip:" .. skip)
		else
			gs.fails[id] = (gs.fails[id] or 0) + 1
			if gs.fails[id] >= GL.EDGE_FAILS then gs.bad[id] = true end
			self:glockLine(job, { id = id }, false, r.why or "refused", { { "msgs", fmt(msgs) },
				{ "cost", r.pre and r.pre.cost or "-" }, { "fails", gs.fails[id] }, { "err", r.err or "-" } })
		end
	end
end

--- Stage "glock" (§67): the job's queued edges as one lock proposal; refused as a batch -> each edge pre-checked alone
--- (one per tick), the passing ones sent together; refused alone -> counted (GL.EDGE_FAILS) and the town backs off.
function Driver:glockSend(job, now)
	local gl = job.glock
	if gl == nil then
		gl = { ids = {}, info = {}, pass = nil, i = 0 }
		for _, c in ipairs(job.glockQ or {}) do
			gl.ids[#gl.ids + 1] = c.id
			gl.info[c.id] = c
		end
		job.glock = gl
	end
	if self.E.lockProposal == nil or #gl.ids == 0 then return self:glockEnd(job, now) end
	if gl.pass == nil then
		local r = self:glockTry(gl.ids)
		if r.ok then return self:glockFire(job, now, r) end
		if #gl.ids <= 1 or r.proposal == nil then
			self:glockRefused(job, gl.ids, r)
			if r.proposal ~= nil then GL.backoff(self:glockState(job.town).bo, now, false) end
			return self:glockEnd(job, now)
		end
		gl.pass, gl.i, gl.batchWhy = {}, 0, r.why
		return
	end
	gl.i = gl.i + 1
	if gl.i <= #gl.ids then
		local id = gl.ids[gl.i]
		local r = self:glockTry({ id })
		if r.ok then gl.pass[#gl.pass + 1] = id else self:glockRefused(job, { id }, r) end
		return
	end
	if #gl.pass == 0 then
		local pause, off = GL.backoff(self:glockState(job.town).bo, now, false)
		self:log("GLOCK", { { "town", job.town }, { "name", self.E.name(job.town) }, { "event", "backoff" },
			{ "why", gl.batchWhy or "-" }, { "pause", pause }, { "off", off } })
		return self:glockEnd(job, now)
	end
	local r = self:glockTry(gl.pass)
	if r.ok then return self:glockFire(job, now, r) end
	self:glockRefused(job, gl.pass, r)
	GL.backoff(self:glockState(job.town).bo, now, false)
	return self:glockEnd(job, now)
end

--- Sends a pre-checked lock proposal (SEND-style GLOCK line first: crash forensics); stage "glockWait".
function Driver:glockFire(job, now, r)
	local ids = {}
	for _, e in ipairs(r.list) do ids[#ids + 1] = e.old end
	for id, why in pairs(r.skipped or {}) do
		if why ~= "gone" then self:glockState(job.town).bad[id] = true end
	end
	self:log("GLOCK", { { "town", job.town }, { "name", self.E.name(job.town) }, { "event", "send" },
		{ "edges", table.concat(ids, ",") }, { "preCost", r.pre and r.pre.cost or "-" },
		{ "player", H.player == true and "on" or "off" } })
	self.inflight = true
	-- (§68: the balance at the send, for the refund of the rebuild's charge; no player set: not charged, no refund)
	local bal0 = H.player == true and self:balanceAtSend(now) or nil
	job.glockSent = { us = now, list = r.list, cost = r.pre and r.pre.cost, bal0 = bal0 }
	job.glockResult = nil
	job.stage = "glockWait"
	self.E.sendBuild(r.proposal, r.ctx, function(success, info)
		job.glockResult = { success = success, info = info or {} }
	end)
end

--- The refund of a lock build's charge (§68, Driver:refundBuild): the balance change since the send, at most the build's
--- cost, booked back as street construction income. GLOCK event=refund line; session totals glockRefund and refund
--- (STREETS).
function Driver:glockRefund(job, sent, res, now)
	local E = self.E
	if not (GL.REFUND and sent.bal0 and E.balance and E.bookStreetRefund) then return end
	local cost = tonumber(res.info and res.info.cost)
	if cost == nil or cost <= 0 then cost = tonumber(sent.cost) end
	local amount, why, bal1 = self:refundBuild("glock", sent.bal0, cost, now)
	self:log("GLOCK", { { "town", job.town }, { "name", E.name(job.town) }, { "event", "refund" }, { "amount", amount },
		{ "why", why }, { "paid", bal1 and string.format("%.0f", sent.bal0 - bal1) or "-" }, { "cost", fmt(cost) },
		{ "session", self.glockRefundSum or 0 } })
end

--- Stage "glockWait": the lock build's callback (GL.WAIT_S at most). Built: the new edges found between the same nodes
--- (their ids saved, `gx`), one GLOCK line per edge; refused: counted per edge, the town backs off.
function Driver:glockWait(job, now)
	local E, t = self.E, job.town
	local res, sent = job.glockResult, job.glockSent
	local gs = self:glockState(t)
	if res == nil then
		if now - sent.us <= GL.WAIT_S * 1e6 then return end
		res = { success = false, info = { msgs = { "timeout" } } }
	end
	self.inflight = false
	if res.success then
		local newIds = {}
		for _, e in ipairs(sent.list) do
			local nid, locked = nil, nil
			if E.edgeBetween then nid, locked = E.edgeBetween(e.n0, e.n1, e.old) end
			if nid then
				gs.ids[nid] = true
				newIds[#newIds + 1] = nid
			end
			local c = job.glock and job.glock.info[e.old]
			self:glockLine(job, e, true, c and c.kind or "-", { { "new", nid or "-" }, { "locked", locked == true },
				{ "batch", #sent.list }, { "cost", fmt(res.info.cost) } })
		end
		gs.n = gs.n + #sent.list
		self.glockN = (self.glockN or 0) + #sent.list
		self.counts.glocked = (self.counts.glocked or 0) + #sent.list
		GL.backoff(gs.bo, now, true)
		if #newIds > 0 and E.sendEvent then E.sendEvent(SV.EVENT_ID, SV.EV_GLOCK, { town = t, ids = newIds }) end
		self:glockRefund(job, sent, res, now)
	else
		local ids = {}
		for _, e in ipairs(sent.list) do ids[#ids + 1] = e.old end
		local msgs = res.info and res.info.msgs or {}
		self:glockRefused(job, ids, { why = (msgs[1] == "timeout") and "timeout" or "failed", pre = { msgs = msgs } })
		local pause, off = GL.backoff(gs.bo, now, false)
		self:log("GLOCK", { { "town", t }, { "name", E.name(t) }, { "event", "backoff" }, { "why", "failed" },
			{ "pause", pause }, { "off", off } })
	end
	return self:glockEnd(job, now)
end

--- The job's lock part is over: the job finishes with the outcome it had (Driver:finish).
function Driver:glockEnd(job, now)
	job.glockQ = nil
	return self:finish(job.town, job.glockOutcome or "room", now)
end

--- §69 steer towns: the policy's inputs on the job (job.steerC: the town's outline from its last check (a round one
--- of the extent without houses yet), its maturity, the shape, the forest / water / gap / land context) and the tips it
--- may leave open (job.steerTipMax: the valves wanted less the open ones; job.steerOpen). Nothing for other locks.
function Driver:steerPrep(job)
	job.steerC, job.steerTipMax, job.steerOpen = nil, 0, nil
	if D.lockMode(job) ~= "steer" or job.inc == nil then return end
	local t = job.town
	local s = self:townState(t)
	local style = job.style or {}
	local ext = job.ext or { cx = style.centre and style.centre[1] or 0, cy = style.centre and style.centre[2] or 0, r = 200 }
	local smp = job.sampler or s.sampler
	local ctx = { fg = s.forest, gaps = style.gaps, field = style.land, fo = style.forest,
		wet = smp and function(x, y) return T.isWater(smp, x, y) end or nil,
		arms = style.shape and style.shape.arms or nil }
	local ol = s.outline or LP.roundOutline(ext.cx, ext.cy, 0.8 * (ext.r or 0))
	local mat = s.lockMat
	if mat == nil then mat = (job.caps and job.caps.actual) and A.maturity(job.caps.actual) or 0 end
	local sh = style.shape
	job.steerC = { outline = ol, cx = ext.cx, cy = ext.cy, mat = mat, shape = (sh and sh.id ~= "compact") and sh or nil, ctx = ctx }
	if not job.force and not job.dry and t ~= nil and self:townGameLock(t) then
		local gs = self:glockState(t)
		ctx.rest = gs.rest
		local grower = style.grower == "organic" and "organic" or "grid"
		local want = GL.wantValves(grower, ext.r, gs.extra)
		job.steerTipMax = math.max(0, want - #gs.valves)
		job.steerOpen = gs.valves
	end
end

--- §69 at a CHECK: the town's locked share (its lot edges locked by us or the game-street lock) and, for steer towns,
--- its built outline (ot_lockpol.outline) and maturity for the next plan.
function Driver:steerNote(t, m, saved)
	local s = self:townState(t)
	local inTown = {}
	for _, le in ipairs(m.lotEdges or {}) do inTown[le.id] = true end
	local nE, nL, items = 0, 0, {}
	local edges = m.edges or {}
	for i = 1, math.min(#edges, LP.SCAN_MAX) do
		local ed = edges[i]
		if inTown[ed.id] and ed.p0 and ed.p1 then
			nE = nE + 1
			if ed.locked or ed.glocked then nL = nL + 1 end
			items[#items + 1] = { (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2, (m.builtBy and m.builtBy[ed.id]) or 0 }
		end
	end
	s.lockShare = nE > 0 and nL / nE or nil
	if self:townLockMode(t, saved) == "steer" and m.ext ~= nil then
		s.outline = LP.outline(items, m.ext.cx, m.ext.cy)
		-- (§70: the lock maturity, ot_lockpol.maturity: the persons measure, the town's size and its age since its first
		-- frame; s.lockMat, apart from s.mat, the densify draw's level maturity, which §69 overwrote here)
		local base = (m.dem and m.dem.mat) or ((m.caps and m.caps.actual) and A.maturity(m.caps.actual)) or nil
		local fr = SV.frame(saved or self:savedNow(nil), t)
		local yNow = self.E.yearF and self.E.yearF() or nil
		local age = (fr and fr.year and tonumber(yNow)) and math.max(0, yNow - fr.year) or nil
		-- (the grower from the §67 context of the town's last plan; none yet: organic)
		local gctx = s.glock and s.glock.ctx or nil
		local style = { grower = (gctx and gctx.grower == "grid") and "grid" or "organic" }
		local scale = LP.sizeScale(style, tonumber(yNow) or (self.E.year and self.E.year()) or nil)
		s.lockMat, s.lockMatParts = LP.maturity(base, m.buildings, age, scale)
	end
end

--- §67 valve stub: the key of the one street of this build left unlocked (GL.pickStub toward gs.stubWant), or nil.
function Driver:glockStubKey(job)
	if job.inc == nil or job.force or job.dry or job.town == nil or not self:townGameLock(job.town) then return nil end
	if job.bridgePlan or job.leadPlan or job.worksPlan or job.satPlan then return nil end
	local gs = self:glockState(job.town)
	if gs.stubWant == nil or job.ext == nil then return nil end
	return GL.pickStub(job.inc.edges, gs.stubWant, job.ext.cx, job.ext.cy, job.ext.r)
end

--- After a build with a valve stub: the stub is the town's new valve (VALVE event=open kind=stub).
function Driver:glockStubBuilt(job, now)
	-- (§69 steer: each built tip becomes a tip valve)
	if job.steerTips ~= nil and job.spec ~= nil and #job.steerTips > 0 and self:townGameLock(job.town) then
		local gs = self:glockState(job.town)
		local grower = gs.ctx and gs.ctx.grower or "grid"
		for _, p in ipairs(job.steerTips) do
			for _, e in ipairs(job.spec.edges) do
				if e.key == p.key and not e.locked then
					local x, y = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
					local v = { anchor = nil, x = x, y = y, a = p.a, kind = "tip", why = p.why or "tip", score = p.score,
						quota = GL.valveQuota(grower), checks = 0, n = 0, z0 = {}, openUs = now }
					gs.valves[#gs.valves + 1] = v
					gs.tipsOpened = (gs.tipsOpened or 0) + 1
					self:valveOpenLog(job.town, v, gs.want or 0, gs)
					break
				end
			end
		end
	end
	local key = job.glockStub
	if key == nil or job.spec == nil then return end
	for _, e in ipairs(job.spec.edges) do
		if e.key == key and not e.locked then
			local gs = self:glockState(job.town)
			local x, y = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			local a = G.atan2(y - job.ext.cy, x - job.ext.cx)
			local grower = gs.ctx and gs.ctx.grower or "grid"
			local v = { anchor = nil, x = x, y = y, a = a, kind = "stub", why = "stub", quota = GL.valveQuota(grower),
				checks = 0, n = 0, z0 = {}, openUs = now }
			gs.valves[#gs.valves + 1] = v
			gs.stubWant, gs.stubLogged = nil, nil
			self:valveOpenLog(job.town, v, gs.want or 0, gs)
			return
		end
	end
end

--- assess: is the town acted on, how big, how much open frontage is left on its streets? A forced job (dev
--- tools) skips the "New towns only" and needs-room tests.
function Driver:assess(job, now, saved)
	local E, t = self.E, job.town
	self.counts.checks = self.counts.checks + 1
	if self.opts.actOn == "new" and not job.force then
		local known = SV.knownSet(saved)
		if known == nil or known[t] then
			if not self:townState(t).skipLogged then
				self:townState(t).skipLogged = true
				self:debug("SKIP", { { "town", t }, { "name", E.name(t) }, { "reason", "existingTown" } })
			end
			return self:finish(t, "skip", now)
		end
	end
	-- (R1: the reads and the rest in two ticks when the reads alone took CHECK_SPLIT_US; the check's town network gets
	-- NET_CHECK_US)
	local m, reason, n
	local mo = { netUs = D.NET_CHECK_US }
	if job.mPart then
		local part = job.mPart
		job.mPart = nil
		m, reason, n = self:measureFinish(t, part, mo)
		if m then m.slices = 2 end
	else
		local part
		part, reason, n = self:measureReads(t, mo)
		if part ~= nil and D.CHECK_SPLIT_US and part.us >= D.CHECK_SPLIT_US then
			job.mPart = part
			self.counts.checks = self.counts.checks - 1   -- (counted once, when it finishes)
			return
		end
		if part ~= nil then m = self:measureFinish(t, part, mo) end
	end
	if m == nil then
		self:debug("SKIP", { { "town", t }, { "reason", reason }, { "buildings", n } })
		return self:finish(t, "skip", now)
	end
	self:fillEffect(t, m, now)
	self:upwardEffect(t, m, now)
	if not job.force and not job.dry then self:levelsCheck(t, m, now) end
	-- (the town window's card, 2026-10-17: the town's phase and offshoot readiness for the saved summary)
	if not job.force and not job.dry then
		local okU, errU = pcall(self.uiNote, self, t, m)
		if not okU and not self.uiErrLogged then
			self.uiErrLogged = true
			self:log("WARN", { { "stage", "card" }, { "town", t }, { "err", errU } })
		end
	end
	-- (the densify trait, ot_character 2026-10-14: drawn once mature)
	if not job.dry then
		local okD, errD = pcall(self.densifyCheck, self, t, m, now)
		if not okD then self:log("WARN", { { "stage", "densify" }, { "town", t }, { "err", errD } }) end
	end
	local lots, caps = m.lots, m.caps
	-- (§65: who built the town's streets, and the stall guard's streak)
	local split, stallLv, stallEv = self:streetSplit(t, lots, saved), nil, nil
	local ts = self:townState(t)
	if D.STALL and not job.force and not job.dry and D.lockFamily(self:townLockMode(t, saved)) then
		ts.stall = ts.stall or {}
		stallLv, stallEv = A.stall(ts.stall, m.ratio, m.buildings, lots.open, m.threshold)
	end
	-- (§69: the locked share, a steer town's outline and maturity)
	local okSN, errSN = pcall(self.steerNote, self, t, m, saved)
	if not okSN then self:log("WARN", { { "stage", "steerNote" }, { "town", t }, { "err", errSN } }) end
	-- (§67: the game's new streets queued to lock at the job's end, the valves)
	local okG, gls = pcall(self.glockNote, self, job, t, m, now, saved)
	if not okG then
		self:log("WARN", { { "stage", "glock" }, { "town", t }, { "err", gls } })
		gls, job.glockQ = nil, nil
	end
	-- (§75 follow-up, 2026-10-20: the main body, ot_assess.body; only when the debug line is written; logging only)
	local bRBody, bR50, bOut, bFar, bUs = "-", "-", "-", "-", "-"
	if self:debugOn() and m.pts then
		local b0 = self:nowUs()
		local okB, b = pcall(A.body, m.pts)
		if okB and b then bRBody, bR50, bOut, bFar = A.bodyFields(b, #m.pts) end
		bUs = self:nowUs() - b0
	end
	self:debug("CHECK", { { "town", t }, { "name", E.name(t) }, { "buildings", m.buildings }, { "r", m.ext.r },
		{ "rBody", bRBody }, { "r50", bR50 }, { "out", bOut }, { "outFar", bFar }, { "bodyUs", bUs },
		{ "edges", lots.edges }, { "free", lots.free }, { "open", lots.open }, { "openEdges", lots.openEdges },
		{ "gaps", lots.gaps }, { "virtual", lots.virtual }, { "built", lots.built }, { "need", m.threshold },
		{ "cap", caps and string.format("%.0f/%.0f", caps.actual, caps.target) or "?" },
		{ "uses", (caps and caps.uses) and string.format("%.0f/%.0f/%.0f", caps.uses[1] or 0, caps.uses[2] or 0, caps.uses[3] or 0) or "-" },
		{ "initials", (caps and caps.initials and caps.initials[3]) and string.format("%.0f/%.0f/%.0f", caps.initials[1], caps.initials[2], caps.initials[3]) or "-" },
		{ "capRatio", m.ratio and string.format("%.3f", m.ratio) or "?" },
		{ "demand", m.dem and string.format("%.1f", m.dem.edges) or "?" },
		{ "perEdge", m.dem and string.format("%.1f", m.dem.perEdge) or "?" },
		{ "raw", m.dem and m.dem.raw and string.format("%.1f", m.dem.raw) or "?" },
		{ "fast", m.dem and m.dem.fast and string.format("%.2f", m.dem.fast) or "?" },
		{ "freeK", m.dem and m.dem.freeK and string.format("%.2f", m.dem.freeK) or "?" },
		{ "pbK", m.dem and m.dem.pbK and string.format("%.2f", m.dem.pbK) or "?" },
		{ "demK", m.dem and m.dem.demK and string.format("%.2f", m.dem.demK) or "?" },
		{ "mat", m.dem and m.dem.mat and string.format("%.2f", m.dem.mat) or "?" },
		{ "pb", (m.caps and m.buildings and m.buildings > 0) and string.format("%.2f", m.caps.actual / m.buildings) or "?" },
		{ "ownOpen", lots.ownOpen },
		{ "ownEdges", lots.ownEdges }, { "lead", m.dem and m.dem.lead or "?" }, { "why", m.why }, { "needsRoom", m.needs },
		{ "ind", IND.text(self:industryFor(t, now, m.ext)) },
		{ "sat", D.satText(self:townState(t).sat, m.pts) },
		{ "force", job.force == true }, { "parcelMap", m.parcelMap }, { "us", m.us }, { "slices", m.slices or 1 },
		{ "sliceUs", m.sliceUs or m.us }, { "parts", m.parts or "-" },
		{ "lockMode", self:townLockMode(t, saved) }, { "modEdges", split.mod }, { "gameEdges", split.game or "-" },
		{ "coreEdges", split.core or "-" }, { "gameShare", split.share and string.format("%.2f", split.share) or "-" },
		{ "stallStreak", ts.stall and ts.stall.n or 0 }, { "stallFires", ts.stall and ts.stall.fires or 0 },
		{ "valves", gls and GL.valvesText(gls.valves) or "-" }, { "glocked", gls and gls.tally and gls.tally.glocked or "-" },
		{ "gameOpen", gls and gls.tally and gls.tally.open or "-" }, { "glock", gls and gls.why or "-" },
		{ "lockShare", ts.lockShare and string.format("%.2f", ts.lockShare) or "-" },
		{ "tips", gls and D.tipCount(gls.valves) or 0 },
		{ "gameKept", gls and gls.tally and string.format("%d/%d", gls.tally.steerIn or 0, gls.tally.steerOk or 0) or "-" },
		{ "outline", ts.outline and string.format("%.0f", ts.outline.rq) or "-" },
		{ "lockMat", LP.matText(ts.lockMat, ts.lockMatParts) }, { "smallWood", gls and gls.smallWood or "-" } })
	self:streetsNote(t, m, split, now)
	self:matureLog(t, m)
	self:paceSeen(t, m, now)
	if not job.force and not job.dry and (self:satWatch(job, m, now) or self:bridgeWatch(job, m, now)) then return end
	-- (2026-10-14 late, Penkridge Sands: a Works / district town below OFFSHOOT_HOLD_B buildings gets no mod streets of
	-- its own: it only grows when served by transport, and the game fills its first streets. NEXT_PHASE_BRIEF 52.3: also
	-- any town whose growth is empty (A.growthEmpty), before the offshoot turn too; the verdict stays on the town state
	-- for the send guard (other towns' plans into a held created town); OFFSHOOT event=hold when it changes)
	local hold = nil
	if not job.force then hold = self:holdWhy(t, m, job, saved) end
	self:townState(t).hold = hold or false
	if stallLv or stallEv then self:stallGuard(job, t, m, stallLv, stallEv, hold) end
	if hold and m.needs then
		self:holdLog(t, m, hold)
		return self:finish(t, "room", now)
	end
	-- (2026-10-14: a town that needs no streets may still be due for its satellite / Works / district decision, or a
	-- link: an offshoot turn takes the snapshot for those alone, so the brake no longer starves them)
	if not m.needs and not job.force and not job.dry and not hold then
		local due, what = self:offshootTurnDue(t, m, now, saved)
		if due then
			self:townState(t).offTurnUs = now
			m.needs, m.why = true, "offshoot"
			self:debug("OFFSHOOT", { { "event", "turn" }, { "town", t }, { "name", E.name(t) }, { "for", what },
				{ "buildings", m.buildings }, { "size", D.offshootSize(m.buildings, m.caps) } })
		end
	end
	if not m.needs and not job.force then return self:finish(t, "room", now) end
	job.ext, job.edges, job.caps, job.lots, job.net, job.pts = m.ext, m.edges, m.caps, lots, m.net, m.pts
	job.dem, job.trigger = m.dem, job.head and "head" or m.why
	job.builtBy = m.builtBy
	job.stall = m.stall or job.stall
	job.stage = self:townState(t).stats and self:afterTerrain(t, now) or "terrain"
end

--- STYLE field `water` (shore towns, 2026-10-12): "kind:body:distance island=0|1 shore=m" (ot_site / ot_terrain), or "-".
local function waterText(stats, wide)
	local w = stats and stats.water
	if w == nil then return "-" end
	local okF, f = pcall(SITE.features, stats, wide)
	f = okF and f or {}
	return string.format("%s:%s:%.0f island=%d shore=%.0f%s", tostring(w.kind), tostring(f.body or w.body or "-"),
		w.distance or -1, f.island and 1 or 0, stats.shore and stats.shore.L or 0,
		stats.shore and ("/" .. tostring(stats.shore.stops)) or "")
end

function Driver:terrain(job)
	local E, t = self.E, job.town
	local s = self:townState(t)
	local cx, cy = E.boxCentre(t)
	if cx == nil then cx, cy = job.ext.cx, job.ext.cy end
	s.pos = { G.round(cx, 1), G.round(cy, 1) }
	if job.ext and tonumber(job.ext.r) and job.ext.r > 0 then s.extR = job.ext.r end
	local t0 = self:nowUs()
	local sampler = E.sampler()
	s.stats = T.stats(sampler, s.pos[1], s.pos[2], D.STATS_RADIUS, 24)
	s.wide = T.wide(sampler, s.pos[1], s.pos[2], D.WIDE_RADIUS)
	-- (the landscape pull, ot_land: the wide survey's points off the map are no land to grow onto)
	D.markOffMap(s.wide, self:mapBounds(t0))
	-- (the peninsula tip motif's spit, ot_motif_point: towns with water in the disc or the wide survey)
	if PT.ON and (s.stats.water ~= nil or (s.wide.water or 0) > D.SPIT_WATER) then
		local bounds = self:mapBounds(t0)
		local okS, sp = pcall(PT.findSpit, sampler, s.pos[1], s.pos[2],
			{ offEdge = bounds and function(x, y) return MAP.nearEdge(bounds, x, y) end or nil })
		s.stats.spit = okS and sp or nil
	end
	local rel = s.stats.relief
	self:debug("TERRAIN", { { "town", t }, { "meanSlope", s.stats.meanSlope }, { "water", s.stats.waterFraction },
		{ "wideWater", s.wide.water }, { "wideSd", s.wide.sd }, { "wideRange", s.wide.range },
		{ "waterDirs", s.wide.waterDirs or 0 }, { "waterKind", waterText(s.stats, s.wide) },
		{ "grade", rel and string.format("%.3f", rel.grade) or "-" }, { "spit", PT.text(s.stats.spit) },
		{ "us", self:nowUs() - t0 } })
	job.stage = self:afterTerrain(t, t0)
end

--- The stage after the terrain stats: "forest" when the town's tree grid is missing or older than FO.RENEW_S (and the
--- engine can read trees), else "snapshot".
function Driver:afterTerrain(t, now)
	if not (D.FOREST and FO.ON and self.E.forestReader) then return "snapshot" end
	local s = self:townState(t)
	if s.forestFail then return "snapshot" end
	if s.forest == nil or now - (s.forestUs or 0) > FO.RENEW_S * 1e6 then return "forest" end
	-- (R1: the town and the player clear trees as it grows: re-read after RENEW_BUILDS builds or RENEW_EDGES new edges)
	if (s.forestBuilds or 0) >= FO.RENEW_BUILDS or (s.forestEdges or 0) >= FO.RENEW_EDGES then return "forest" end
	return "snapshot"
end

--- Stage "forest" (phase F): reads the trees within FO.R of the town centre into a coarse grid (ot_forest), FO.SLICE_US
--- per tick; when done the grid sits on the town's terrain stats (`stats.forest`, also `s.forest`) and a FOREST debug line
--- logs the read (groups, instance reads, trees, stride, dense cells, share, density p50 / p90, time, slices). A reader
--- error leaves the town without a grid for the session (mode none: the plan as before).
function Driver:forest(job, now)
	local E, t = self.E, job.town
	local s = self:townState(t)
	local pos = s.pos or { job.ext.cx, job.ext.cy }
	local fr = job.forestRead
	if fr == nil then
		local fg = FO.newGrid(pos[1], pos[2], FO.R, FO.CELL)
		fr = { grid = fg, slices = 0, us = 0, species = {} }
		local tally = fr.species
		fr.reader = E.forestReader(pos[1], pos[2], FO.R * 1.415, { readMax = FO.READ_MAX,
			add = function(x, y, w) FO.addTree(fg, x, y, w) end,
			-- (stop names: the trees' species, ot_stopname.species from the model file names)
			speciesOf = SN.species, species = function(sp, w) tally[sp] = (tally[sp] or 0) + (w or 1) end })
		job.forestRead = fr
	end
	local t0 = self:nowUs()
	local done = fr.reader:step(FO.SLICE_US)
	fr.slices, fr.us = fr.slices + 1, fr.us + (self:nowUs() - t0)
	if not done then return end
	local st = fr.reader.stats
	fr.grid.stride = st.stride   -- (ot_forest coverOf: a lone sampled tree reads open land)
	local fg = FO.finish(fr.grid)
	job.forestRead = nil
	if st.err and st.groups == 0 then s.forestFail = true end
	local why = s.forest == nil and "first" or (((s.forestBuilds or 0) >= FO.RENEW_BUILDS or (s.forestEdges or 0) >= FO.RENEW_EDGES)
		and string.format("builds:%d/edges:%d", s.forestBuilds or 0, s.forestEdges or 0) or "age")
	s.forest, s.forestUs = fg, now
	s.forestBuilds, s.forestEdges = 0, 0
	if next(fr.species) ~= nil then s.species = fr.species end
	if s.stats then s.stats.forest = fg end
	-- (the styles pick the new grid up at the next snapshot: style.forest = FO.forStyle(s.forest, style))
	self:debug("FOREST", { { "town", t }, { "name", E.name(t) }, { "groups", st.groups }, { "reads", st.reads },
		{ "trees", st.trees }, { "nonTree", st.nonTree }, { "stride", st.stride }, { "capped", st.capped },
		{ "cells", fg.treeCells }, { "dense", fg.denseCells }, { "share", string.format("%.2f", fg.share or 0) },
		{ "p50", string.format("%.0f", fg.p50 or 0) }, { "p90", string.format("%.0f", fg.p90 or 0) },
		{ "listUs", st.listUs }, { "us", fr.us }, { "slices", fr.slices }, { "err", st.err or "-" }, { "renew", why },
		{ "species", D.speciesText(fr.species) } })
	job.stage = "snapshot"
end

--- FOREST `species=`: the read's top species by trees ("oak:420,pine:300,..." at most 4), "-" without.
function D.speciesText(tally)
	local list = {}
	for sp, n in pairs(tally or {}) do list[#list + 1] = { sp, n } end
	if #list == 0 then return "-" end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return a[1] < b[1]
	end)
	local out = {}
	for i = 1, math.min(4, #list) do out[i] = string.format("%s:%d", list[i][1], list[i][2]) end
	return table.concat(out, ",")
end

--- ot_core.wideAuditText (the STREETS line's sum: Driver:streetsNote has a local `core`, the core edge count, that
--- shadows the module there).
function D.wideAuditText(w) return core.wideAuditText(w) end

--- PLAN `runs=` (§73): the increment's medium / large runs kept / cut (all passes) / the longest kept (m), or "-".
function D.runsText(h)
	local r = h and h.runs
	if r == nil then return "-" end
	return string.format("%d/%d/%.0f", r.kept or 0, r.cut or 0, r.maxLen or 0)
end

--- Builder of a snapshot edge for the SNAPSHOT `wideRuns` audit (§73): "mod" (ours: locked or built this session),
--- "game" (the game's, locked by us after it built them, §67), else "other" (the town's core and the game's open streets).
function D.edgeBuilder(s, ed)
	if ed == nil then return "other" end
	if ed.locked == true or (s and s.own and s.own[ed.id]) then return "mod" end
	if ed.glocked then return "game" end
	return "other"
end

--- Street graph + join info for the town's dead ends (noJoin marks every dead end we must not touch).
function Driver:snapshotGraph(job)
	local E, t = self.E, job.town
	local snap = { nodes = {}, edges = {} }
	local seen, local1 = {}, {}
	local edgeById = {}
	-- (the mod's own streets built this session: ot_knot.emptyOurs, one empty row at a time; locked ones say so anyway)
	local ownIds = self.towns[t] and self.towns[t].own or nil
	for _, ed in ipairs(job.edges) do
		edgeById[ed.id] = ed
		for k = 0, 1 do
			local n = k == 0 and ed.n0 or ed.n1
			local p = k == 0 and ed.p0 or ed.p1
			if not seen[n] then
				seen[n] = true
				snap.nodes[#snap.nodes + 1] = { id = n, x = p[1], y = p[2], z = p[3] }
			end
			local1[n] = (local1[n] or 0) + 1
		end
		snap.edges[#snap.edges + 1] = { id = ed.id, node0 = ed.n0, node1 = ed.n1, class = classOf(ed.template),
			t0 = ed.t0, t1 = ed.t1, template = ed.template, built = job.builtBy and (job.builtBy[ed.id] or 0) or nil,
			locked = ed.locked == true or nil, own = (ownIds and ownIds[ed.id]) or nil }
	end
	local g = OG.fromSnapshot(snap)
	local joinInfo, joinable, why = {}, 0, {}
	-- (R4 2026-10-13, empty streets: the mod's own dead-end streets that stay without a house for RETIRE_CHECKS
	-- snapshots in a row are retired: never extended this session (noJoin retired), until a house stands on them)
	local s = self:townState(t)
	s.emptyDE = s.emptyDE or {}
	local seenDE = {}
	local retired = 0
	for _, n in ipairs(OG.deadEnds(g)) do
		local eid = g.adj[n][1]
		local ed = edgeById[eid]
		local reason = nil
		if D.RETIRE_CHECKS and not job.regraph and ed and job.builtBy and (ed.locked == true or (s.own and s.own[eid]))
			and not LN.isCountry(ed.template) then
			seenDE[n] = true
			if (job.builtBy[eid] or 0) > 0 then s.emptyDE[n] = nil else s.emptyDE[n] = (s.emptyDE[n] or 0) + 1 end
		end
		local real = E.nodeStreetEdges(n)
		local isRetired = (s.emptyDE[n] or 0) > D.RETIRE_CHECKS
		local info = nil
		if #real ~= 1 then reason = "degree"
		elseif not D.plainTownEdge(ed) then reason = "edge"
		elseif E.nodeInConstruction(n) then reason = "construction"
		else
			local hasCfg = E.hasConfig(n)
			if not hasCfg and not (self.allowNoConfig or D.ALLOW_NO_CONFIG) then reason = "noConfig"
			else
				local node = g.nodeById[n]
				local ct = E.closestTown(node.x, node.y)
				-- (a Works link job: the Works town's dead ends may be joined too, job.otherTownOk)
				if ct ~= t and not (job.otherTownOk ~= nil and ct == job.otherTownOk) then reason = "otherTown"
				else
					info = { hasConfig = hasCfg, edges = real, lanes = ed.lanes, src = ed.id, template = ed.template }
				end
			end
		end
		-- (retired comes first in the report, as before; §74 2026-10-18: a dead end retired for nothing else is marked
		-- nmRetired with its join info in g.nmRetiredInfo, so a near-miss join may still close it: Driver:retiredJoinOk)
		if isRetired then
			retired = retired + 1
			if reason == nil and info then
				g.nmRetiredInfo = g.nmRetiredInfo or {}
				g.nmRetiredInfo[n] = info
				g.nodeById[n].nmRetired = true
			end
			reason = "retired"
		elseif info then
			joinInfo[n] = info
			joinable = joinable + 1
		end
		if reason then
			g.nodeById[n].noJoin = true
			-- (a snapshot dead end with more street edges in the game: the snapshot's cut, no dead end; §74 `cut`)
			if reason == "degree" then g.nodeById[n].nmCut = true end
			why[reason] = (why[reason] or 0) + 1
		end
	end
	if not job.regraph then
		for n in pairs(s.emptyDE) do if not seenDE[n] then s.emptyDE[n] = nil end end   -- (gone or joined: forgotten)
	end
	s.retired = retired
	local whyText = {}
	for _, k in ipairs({ "retired", "degree", "edge", "construction", "noConfig", "otherTown" }) do
		if why[k] then whyText[#whyText + 1] = k .. ":" .. why[k] end
	end
	return g, joinInfo, joinable, table.concat(whyText, "/")
end

--- §74 (2026-10-18): may a near-miss join start or end at retired dead end n (the snapshot's nmRetired: the mod's own
--- empty dead end, retired for nothing else)? Its join info goes to job.nmInfo[n] for ot_proposal, as midJoinOk's.
function Driver:retiredJoinOk(job, n)
	local info = job.g and job.g.nmRetiredInfo and job.g.nmRetiredInfo[n]
	if info == nil then return false end
	job.nmInfo = job.nmInfo or {}
	job.nmInfo[n] = info
	return true
end

--- §74 (ot_nearmiss): may a near-miss join end at street node n (degree 2 / 3 in the snapshot: a T or a crossroads)?
--- Only a node with a node config (rewritten with the new segment in the engine pattern, ot_proposal, as at a joined dead
--- end), whose street segments are all in the snapshot and plain town streets (no country road, bridge object, player
--- owned or construction street), no track segment at it (a level crossing), not in a construction, in this town.
--- The join info for ot_proposal goes to job.nmInfo[n] (the narrowest segment as the copy source).
function Driver:midJoinOk(job, n)
	local E = self.E
	if job.g == nil or job.g.nodeById[n] == nil or job.g.nodeById[n].noJoin then return false end
	local byId = job.nmEdgeById
	if byId == nil then
		byId = {}
		for _, ed in ipairs(job.edges or {}) do byId[ed.id] = ed end
		job.nmEdgeById = byId
	end
	local real = E.nodeStreetEdges(n)
	if #real < 2 or #real ~= OG.degree(job.g, n) then return false end
	if E.nodeSegmentCount and E.nodeSegmentCount(n) ~= #real then return false end
	local src, edgeLanes = nil, {}
	for _, id in ipairs(real) do
		local ed = byId[id]
		if ed == nil or not D.plainTownEdge(ed) or LN.isCountry(ed.template) then return false end
		edgeLanes[id] = ed.lanes
		if src == nil or (ed.lanes or 0) < (src.lanes or 0) then src = ed end
	end
	if not E.hasConfig(n) then return false end
	if E.nodeInConstruction(n) then return false end
	local node = job.g.nodeById[n]
	if E.closestTown(node.x, node.y) ~= job.town then return false end
	job.nmInfo = job.nmInfo or {}
	job.nmInfo[n] = { hasConfig = true, edges = real, lanes = src.lanes, src = src.id, template = src.template,
		edgeLanes = edgeLanes, mid = true }
	return true
end

--- Edges to copy: one per wanted template, plus a plain town street as the fallback.
function Driver:sources(job, style)
	local sources, fallback, fallbackSmall = {}, nil, nil
	local want = {}
	for _, path in pairs(style.templatePaths or {}) do want[path] = true end
	local townR = job.ext.r * D.TOWN_EDGE_FACTOR + 50
	for _, ed in ipairs(job.edges) do
		local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
		-- (never a tree-lined street as the copy source: its decorations would come along, ot_entry)
		if D.plainTownEdge(ed) and not EN.isTrees(ed.template) and G.dist(job.ext.cx, job.ext.cy, mx, my) <= townR then
			if want[ed.template] and sources[ed.template] == nil then sources[ed.template] = ed.id end
			if fallback == nil then fallback = ed.id end
			if fallbackSmall == nil and classOf(ed.template) == "small" then fallbackSmall = ed.id end
		end
	end
	return sources, fallbackSmall or fallback
end

--- Style modes: "main" (what the mod builds: NA grid when the setting forces it, else the town's site style, ot_site), "region" (the
--- profile the region/climate picks, any style; dev tools), or a profile id from ot_style (dev tools; keeps the
--- era's outer zone). One StyleParams table per town and mode, so ot_core's master plan cache works.
function Driver:styleFor(job, g, saved)
	local E, t = self.E, job.town
	local s = self:townState(t)
	local mode = job.styleMode or "main"
	local year = job.year or E.year()   -- dev tools: an era other than the map's (showcase era row)
	local newT = I.newTemplates(year)
	if job.newTemplates ~= nil then newT = job.newTemplates == true end   -- dev tools: era comparison
	local frame = SV.frame(saved, t)
	-- strong characters (ot_character, 2026-10-14): the main pick only, or the dev force in any mode; densify once mature
	local charKind = (s.forceChar or (mode == "main" and not job.pure and not job.shape and not job.form))
		and self:charKindOf(t, saved) or nil
	if job.charKind and CH.BY_ID[job.charKind] then charKind = job.charKind end   -- (dev showcase: a kind per job)
	local dense = (mode == "main" and self:densifyActive(t, saved)) or s.forceDense == true
	-- (the decade: the outer zone follows the years, ot_grid; re-resolved once per simulated decade)
	local key = mode .. (newT and ":new" or ":old") .. (frame ~= nil and ":framed" or "") .. (job.pure and ":pure" or "")
		.. (job.year and (":y" .. job.year) or (":d" .. math.floor((tonumber(year) or 1960) / 10)))
		.. (job.shape and (":s" .. job.shape) or "")
		.. (job.override and ":override" or "") .. (job.form and (":f" .. job.form) or "")
		.. (job.motif and (":m" .. job.motif) or "")
		.. ((mode == "main" and D.DISTRICTS and self:hasDistrict(t, saved)) and ":dist" or "")
		.. ((mode == "main" and self:coastalOf(t, self:nowUs(), saved)) and ":coast" or "")
		.. (charKind and (":c" .. charKind) or "") .. (dense and ":dz" or "")
	local cached = s.styles[key]
	if cached then
		s.frameSaved = s.frameSaved or frame ~= nil
		return cached
	end
	local ax, strength = OG.dominantAxis(g)
	local forceStyle, keepOuter = nil, false
	if mode == "main" then
		forceStyle = self.opts.forceGrid and "NA_GRID" or nil
	elseif mode ~= "region" then
		forceStyle, keepOuter = mode, not job.pure   -- pure (dev showcase): the profile alone, no outer zone
	end
	-- shape context (ot_shape): roads leaving the town's extent, neighbouring towns
	local pos = s.pos or { job.ext.cx, job.ext.cy }
	-- the country roads around the town, followed beyond the snapshot (ot_roads; M2 road motifs, satellites' crossroads)
	local roads = self:countryRoads(job, t, pos)
	-- (the exits from the snapshot plus the wide road read: the final test's `exits=0` everywhere)
	local exits = SH.exits(job.roadEdges or job.edges, pos[1], pos[2], job.ext.r)
	local inputs = I.build({
		nameList = self.cfg.nameList, climate = self.cfg.climate, year = year,
		styleRegion = self.opts and self.opts.styleRegion or nil,   -- the "Town style" setting's region (ot_params)
		capacity = job.caps and job.caps.actual or 0, townId = t, pos = s.pos, terrain = s.stats,
		axis = { angle = ax, strength = strength }, radius = job.ext.r,
		forceStyle = forceStyle, keepOuter = keepOuter, frame = frame,
		shape = job.shape, form = job.form, exits = exits, neighbours = self:neighbours(t, pos),
		-- Automatic: the style comes from the town's site, the region only biases (ot_site)
		wide = s.wide, autoStyle = mode == "main" and forceStyle == nil,
		-- away from industries (ot_industry): a seeded shape axis turns away from the works near the town
		industry = s.ind,
		-- organic <-> gridded (ot_grid, the Town layout setting), the map edge and character towns (ot_map)
		layout = self.opts and self.opts.townLayout or nil, bounds = self:mapBounds(self:nowUs()),
		character = self:characterOf(t, self:nowUs()),
		-- neighbour diversity (ot_diverse): the main pick only (dev styles / forced shapes and forms stay as asked)
		-- (a town with a saved frame never changes: no diversity at all, also for older frames without a saved style)
		nbrPicks = (mode == "main" and frame == nil and not job.pure and not job.shape and not job.form and not job.motif)
			and self:nbrPicks(t, pos, saved) or nil,
		-- a motif kind forced by the dev tools (ot_motif)
		motif = job.motif,
		roads = roads,
		-- rail passenger stations near the town (M3 station quarter; refreshed per plan in snapshot)
		railStations = self:stationsFor(t, self:nowUs(), job.ext),
		-- coastal huggers (ot_map.coastal, 2026-10-14): the main pick only
		coastal = (mode == "main" and not job.pure and not job.shape and not job.form) and self:coastalOf(t, self:nowUs(), saved) or nil,
		forestShare = s.forest and s.forest.share or nil,
	})
	if charKind then
		inputs.charKind, inputs.charForm, inputs.charMotifs = charKind, CH.formFor(charKind), CH.motifsFor(charKind)
		inputs.charSite = s.charSite
	end
	inputs.densify = dense or nil
	local style = ST.resolve(inputs)
	-- deep forest towns (ot_forest deepPick, 2026-10-14): picked once per town before its first build (saved on the frame,
	-- `fd`); a deep town's style is resolved again with its winding geometry (ot_forest.deepStyle)
	local deep, deepWhy = self:deepFor(t, s, style, frame, mode, job)
	if deep then
		inputs.deep = true
		style = ST.resolve(inputs)
		style.deep = { why = deepWhy }
	end
	style.stationKey = TW.stationKey(style.railStations)
	if charKind then self:charApplyLine(t, charKind, style) end
	-- lobes along the landscape (ot_select.irregularity, 2026-10-13 round 5): the hotspots of unshaped towns go out along
	-- the roads leaving town, else along the hillside's contour / the valley
	style.lobeDirs, style._irr = D.lobeDirs(exits, s.stats), nil
	-- (§62: the landscape pull re-orders them toward favoured land each snapshot, from this base)
	style._lobeBase, style._landText = style.lobeDirs, nil
	if style.newTemplates ~= newT then
		-- template era forced (dev tools): the other era's base templates (town_old_* stay buildable after 1940)
		style.newTemplates = newT
		for _, c in ipairs(ST.CLASSES) do style.templatePaths[c] = ST.templatePath(style.templates[c], newT) end
	end
	if job.override then D.applyOverride(style, job.override) end
	-- (districts instead of long arms, 2026-10-14: a town with a district reaches less far along its arms)
	if mode == "main" and D.DISTRICTS and self:hasDistrict(t, saved) and style.shape and D.DISTRICT_ARMED[style.shape.id] then
		style.shape.kaMul = (style.shape.kaMul or 1) * D.DISTRICT_KA
		style.shape.districtKa = D.DISTRICT_KA
		style._irr = nil
	end
	if mode == "main" and not job.pure and not job.shape and not job.form and not job.motif then
		-- (what this town uses, for its neighbours' diversity: a town with a higher id reads it this session)
		s.pick = { style = style.id, form = style.form and style.form.id or nil, shape = style.shape and style.shape.id or nil,
			motifs = MO.ids(style.motifs) }
	end
	s.styles[key] = style
	s.frameSaved = s.frameSaved or frame ~= nil
	if inputs.coastal and not s.coastLogged then
		s.coastLogged = true
		local f = style.form
		self:log("COASTAL", { { "town", t }, { "name", E.name(t) }, { "rank", inputs.coastal.rank or 0 },
			{ "score", string.format("%.2f", inputs.coastal.score or 0) }, { "saved", inputs.coastal.saved == true },
			{ "applied", f ~= nil and f.coastal == true }, { "form", f and f.id or "-" },
			{ "shape", style.shape and style.shape.id or "-" },
			{ "depthCap", style.shape and style.shape.shore and string.format("%.0f", style.shape.shore.depthCap or 0) or "-" },
			{ "front", style.shoreFront ~= nil }, { "why", (f and f.coastal) and "-" or (f and f.why or "noForm") } })
	end
	local sh = style.shape
	local foS = FO.forStyle(s.forest, style)
	self:debug("STYLE", { { "town", t }, { "mode", mode }, { "style", style.id }, { "outer", style.outer and style.outer.id or "-" },
		{ "styleSource", style.styleSource or "-" }, { "styleWhy", style.styleWhy or "-" },
		{ "hierarchy", style.hierarchy or "-" },
		{ "axisDeg", math.deg(style.axis) }, { "axisSource", style.axisSource }, { "templates", newT and "new" or "old" },
		{ "frame", frame ~= nil }, { "draws", style.drawV or "-" }, { "form", style.form and style.form.id or "-" },
		{ "formWhy", style.form and style.form.why or "-" }, { "shape", sh and sh.id or "-" }, { "shapeWhy", sh and sh.reason or "-" },
		{ "shapeGeom", SH.text(sh) }, { "water", waterText(s.stats, s.wide) }, { "exits", #exits }, { "neighbour", inputs.neighbours[1]
			and string.format("%.0fm@%d", inputs.neighbours[1].dist, math.floor(math.deg(G.wrap(inputs.neighbours[1].dir)) % 360)) or "-" },
		{ "override", job.override and "yes" or "-" }, { "ind", IND.text(s.ind) },
		{ "character", D.characterText(style, inputs.character, self.charN) },
		{ "edgeDist", MAP.edgeText(inputs.bounds, pos[1], pos[2]) }, { "gridBias", GR.text(style.gridBias) },
		{ "gridLook", style.gridLook and string.format("%.2f", style.gridLook) or "-" },
		{ "nbr", DV.nbrText(inputs.nbrPicks) }, { "divPen", DV.penText(inputs) }, { "motifs", D.motifText(style) },
		{ "forest", FO.text(foS) },
		-- (§59: the mode draw, p=..(s,e,t,c),u=.., so the era odds can be read back from a run)
		{ "forestWhy", foS and foS.why or "-" },
		{ "deep", style.deep and style.deep.why or "-" },
		{ "char", CH.text(style.charKind, style.densify) },
		{ "squeeze", style.squeeze and string.format("%.2f", style.squeeze) or "-" },
		{ "districtKa", style.shape and style.shape.districtKa or "-" },
		{ "roads", RDS.text(roads) } })
	-- motifs (ot_motif): one line per motif when the town's style is resolved (once per style key and session)
	for _, m in ipairs(MO.list(style)) do
		self:debug("MOTIF", { { "town", t }, { "name", E.name(t) }, { "event", "pick" }, { "kind", m.id },
			{ "src", MO.source(m) }, { "why", m.why or "-" }, { "score", string.format("%.2f", m.score or 0) },
			{ "edges", "-" }, { "houses", "-" } })
	end
	-- (2026-10-13 final test: why each drawn kind was or wasn't eligible, with the terrain numbers it read)
	if style._motifElig then
		self:debug("MOTIF", { { "town", t }, { "name", E.name and E.name(t) or "-" }, { "event", "elig" }, { "free", style._motifFree or "-" },
			{ "terrain", MO.terrainText(s.stats, s.wide) }, { "kinds", style._motifElig } })
		style._motifElig = nil
	end
	return style
end

--- The country roads around town t (ot_roads.trace over the snapshot's edges, followed beyond it through
--- E.nodeStreetEdges / E.edge, junctions marked `own` when nearest this town), once per town and session (roads seldom
--- change; ROADS_RENEW_S). ROADS debug line.
D.ROADS_RENEW_S = 1800
D.ROAD_REACH = 1700        -- m from the centre
D.ROAD_MAX_FETCH = 250     -- engine edge reads per trace at most
D.VIRTUAL_ROADS = true     -- no country road near a town: virtual roads (ot_roads.virtual, 2026-10-13 final test)
D.ROADS_WIDE = true        -- the road edges read wide around the town (ot_engine.roadEdges), not only the snapshot's
D.ROADS_WIDE_M = 400       -- m beyond the snapshot radius

--- ROADS `wide=` text: "edges/streets/noStreetComp/tracks:country=n,town=n,other=n;tpl:n,..." or "-".
function D.wideText(w)
	if w == nil then return "-" end
	local st = w.stats or {}
	local t = {}
	for k, n in pairs(st.templates or {}) do
		if not tostring(k):find("town_", 1, true) then t[#t + 1] = k .. ":" .. n end
	end
	table.sort(t)
	return string.format("%d/%d/%d/%d:country=%d,town=%d,other=%d;%s", st.edges or 0, st.streets or 0, st.noStreetComp or 0,
		st.tracks or 0, st.country or 0, st.town or 0, st.other or 0, #t > 0 and table.concat(t, ",") or "-")
end
function Driver:countryRoads(job, t, pos)
	local E = self.E
	local s = self:townState(t)
	local now = self:nowUs()
	if s.roads and now - (s.roadsUs or 0) < D.ROADS_RENEW_S * 1e6 then
		job.roadEdges = s.roadEdges
		return s.roads
	end
	local t0 = now
	local fetch = nil
	if E.edge and E.nodeStreetEdges then
		fetch = function(n)
			local out = {}
			for _, id in ipairs(E.nodeStreetEdges(n)) do
				local ed = E.edge(id)
				if ed then out[#out + 1] = ed end
			end
			return out
		end
	end
	-- (2026-10-13, after the final test: the snapshot held no country road in any town although earlier tours show dirt
	-- country roads leaving towns: the road edges are read wide around the town too, every BASE_EDGE that isn't a track,
	-- classified by the template's `country` flag; ROADS `wide=` says what was found)
	local edges, wide = job.edges or {}, nil
	if D.ROADS_WIDE and E.roadEdges then
		local okW, w = pcall(E.roadEdges, pos[1], pos[2], job.ext.r + D.SNAP_MARGIN + D.ROADS_WIDE_M)
		if okW and w then
			wide = w
			local seen, merged = {}, {}
			for _, ed in ipairs(w.list) do seen[ed.id] = true; merged[#merged + 1] = ed end
			for _, ed in ipairs(edges) do if not seen[ed.id] then merged[#merged + 1] = ed end end
			edges = merged
		end
	end
	job.roadEdges = edges
	s.roadEdges = wide and edges or nil
	local ok, roads = pcall(RDS.trace, edges, pos[1], pos[2], job.ext.r, { fetch = fetch,
		snapR = job.ext.r + D.SNAP_MARGIN + (wide and D.ROADS_WIDE_M or 0), reach = D.ROAD_REACH, maxFetch = D.ROAD_MAX_FETCH })
	if not ok then
		self:log("WARN", { { "stage", "roads" }, { "town", t }, { "err", roads } })
		roads = nil
	elseif E.closestTown then
		for _, j in ipairs(roads.junctions) do
			local ct = E.closestTown(j.x, j.y)
			j.own = ct == nil or ct == t
		end
	end
	s.roads, s.roadsUs = roads, now
	-- (what the snapshot held: street edges that aren't town streets, and their templates; the evidence for "no country
	-- roads on this map", session 2026-10-13_0856_sqot-dev)
	local nonTown, tpls = 0, {}
	for _, ed in ipairs(job.edges or {}) do
		if RDS.isRoad(ed) then
			nonTown = nonTown + 1
			local short = tostring(ed.template):match("([%w_]+)%.street_template") or tostring(ed.template)
			tpls[short] = (tpls[short] or 0) + 1
		end
	end
	local tplText = {}
	for k, n in pairs(tpls) do tplText[#tplText + 1] = k .. ":" .. n end
	table.sort(tplText)
	local traced = roads and #roads.roads or 0
	local wideCountry = 0
	if wide then
		for _, ed in ipairs(wide.list) do if RDS.isRoad(ed) then wideCountry = wideCountry + 1 end end
	end
	-- no country road at all near the town (TF3's new maps lay none between towns): virtual roads toward the
	-- neighbours / along the land (ot_roads.virtual) for the road motifs and the tree-lined entries
	if D.VIRTUAL_ROADS and roads and traced == 0 and nonTown == 0 and wideCountry == 0 then
		local bounds = self:mapBounds(now)
		local okV, vr = pcall(RDS.virtual, pos[1], pos[2], job.ext.r, { sampler = job.sampler or s.sampler or (E.sampler and E.sampler()),
			neighbours = self:neighbours(t, pos), dirs = D.lobeDirs(nil, s.stats), seed = t,
			offEdge = bounds and function(x, y) return MAP.nearEdge(bounds, x, y) end or nil })
		if okV and vr then
			roads = vr
			s.roads = roads
		elseif not okV then
			self:log("WARN", { { "stage", "virtualRoads" }, { "town", t }, { "err", vr } })
		end
	end
	if roads then
		local own = 0
		for _, j in ipairs(roads.junctions) do if j.own ~= false then own = own + 1 end end
		local why = {}
		for _, rd in ipairs(roads.roads) do if rd.why then why[#why + 1] = rd.why end end
		self:debug("ROADS", { { "town", t }, { "name", E.name and E.name(t) or "-" }, { "roads", #roads.roads }, { "text", RDS.text(roads) },
			{ "junctions", string.format("%d/%d", own, #roads.junctions) }, { "segs", #roads.segs },
			{ "fetched", roads.fetched }, { "snapEdges", #(job.edges or {}) }, { "nonTown", nonTown },
			{ "templates", #tplText > 0 and table.concat(tplText, ",") or "-" }, { "traced", traced },
			{ "virtual", roads.virtual and table.concat(why, "/") or "-" }, { "wide", D.wideText(wide) }, { "us", self:nowUs() - t0 } })
	end
	return roads
end

--- Puts the town's current rail stations on the planner's style (and the base style); logs the station quarter's MOTIF
--- pick line when it becomes eligible (M3).
function Driver:stationRefresh(job, style, now)
	local rs = self:stationsFor(job.town, now, job.ext)
	if rs == nil then return end
	local key = TW.stationKey(rs)
	local changed = false
	for _, stl in ipairs({ job.baseStyle, style }) do
		if stl and (stl.stationKey or "") ~= key then
			stl.railStations, stl.stationKey = rs, key
			changed = true
		end
	end
	if changed then
		local k = MO.BY_ID.station_quarter
		local okE, sc, why = pcall(k.eligible, { style = style })
		if okE and (tonumber(sc) or 0) > 0 then
			self:debug("MOTIF", { { "town", job.town }, { "name", self.E.name(job.town) }, { "event", "pick" },
				{ "kind", "station_quarter" }, { "src", "derived" }, { "why", why or "-" },
				{ "score", string.format("%.2f", sc) }, { "edges", "-" }, { "houses", "-" } })
		end
	end
end

--- Puts the town's bridge record on the planner's style (and the base style): this session's build (its far junction
--- and heading, ot_bridge plan) or the frame's `br` flag (found in the snapshot); a change rebuilds the master plan
--- (ot_core: mp.bridgeKey) and logs the bridgehead quarter's MOTIF pick line (M4).
function Driver:bridgeRefresh(job, style, saved)
	local s = self:townState(job.town)
	local rec = nil
	if s.bridgeHead then
		rec = { built = true, src = "session", C = s.bridgeHead.C, heading = s.bridgeHead.heading }
	else
		local fr = SV.frame(saved, job.town)
		if fr and fr.bridge then rec = { built = true, src = "frame" } end
	end
	local key = RL.bridgeKey(rec)
	local changed = false
	for _, stl in ipairs({ job.baseStyle, style }) do
		if stl and (stl.bridgeKey or "") ~= key then
			stl.bridge, stl.bridgeKey = rec, key
			changed = true
		end
	end
	if changed and rec then
		local k = MO.BY_ID.bridgehead_quarter
		local okE, sc, why = pcall(k.eligible, { style = style })
		if okE and (tonumber(sc) or 0) > 0 then
			self:debug("MOTIF", { { "town", job.town }, { "name", self.E.name(job.town) }, { "event", "pick" },
				{ "kind", "bridgehead_quarter" }, { "src", "derived" }, { "why", why or "-" },
				{ "score", string.format("%.2f", sc) }, { "edges", "-" }, { "houses", "-" } })
		end
	end
end

--- STYLE / ALLTOWN field `motifs=` (ot_motif): "id:score:source,..." or "-".
function D.motifText(style)
	return MO.text(MO.list(style))
end

--- MOTIF build lines (ot_motif): per motif of the build's style that measured something, the motif's edges in this
--- build / in the town, the houses along it and the kind's own numbers.
function Driver:motifBuilt(job)
	local style = job.style
	if style == nil then return end
	local list = MO.list(style)
	if #list == 0 then return end
	local env = { g = job.g, inc = job.inc, style = style, mp = job.mp, pts = job.pts, sampler = job.sampler, MT = MT,
		SH = SH, sat = self:townState(job.town).sat }
	for _, m in ipairs(list) do
		local r = MO.measure(m, env)
		-- (only where the kind measured something: no plan (satellite / bridge / frame builds), no crescent meadows)
		if r then
			self:debug("MOTIF", { { "town", job.town }, { "name", self.E.name(job.town) }, { "event", "build" },
				{ "kind", m.id }, { "src", MO.source(m) }, { "why", m.why or "-" },
				{ "score", string.format("%.2f", m.score or 0) },
				{ "edges", string.format("%d/%d", r.edges or 0, r.total or 0) }, { "houses", r.houses or 0 },
				{ "info", r.text or "-" } })
		end
	end
end

--- Neighbour diversity (ot_diverse.gather): the styles / forms / shapes of the towns within ot_diverse.RADIUS, from
--- their saved frames, else (a lower town id only) from this session's pick.
function Driver:nbrPicks(t, pos, saved)
	if not DV.ON then return {} end
	local E = self.E
	local ids = self.townList or (E.towns and E.towns()) or {}
	local cands = {}
	for _, id in ipairs(ids) do
		if id ~= t then
			local x, y = E.boxCentre(id)
			if x then cands[#cands + 1] = { id, x, y } end
		end
	end
	return DV.gather(t, pos, cands,
		function(id)
			local fr = SV.frame(saved, id)
			if fr == nil or not (fr.style or fr.form or fr.shape or (fr.motifs and #fr.motifs > 0)) then return nil end
			return { style = fr.style, form = fr.form, shape = fr.shape, motifs = fr.motifs }
		end,
		function(id)
			local st = self.towns[id]
			return st and st.pick or nil
		end)
end

--- The metropolis style of a town (ot_metro): `base` (styleFor's style) with the variant applied when the town is
--- one (decided from its size, site, region, era and seed; job.metro forces a variant, job.metroCentres the
--- polycentric centres from the start: dev showcase), else base. Cached per town, base style and variant (+ centre
--- count); METRO decide line when the decision changes (also "no" with the reason, debug).
function Driver:metroStyle(job, base)
	local t = job.town
	local s = self:townState(t)
	local cap = job.caps and job.caps.actual or 0
	local d, why = MET.decide({ styleId = base.id, cap = cap, features = SITE.features(s.stats, s.wide), region = base.region,
		year = base.year, seed = base.seed, dv = base.drawV, forced = job.metro })
	if d == nil then
		if s.metroWhy ~= why then
			s.metroWhy = why
			self:debug("METRO", { { "town", t }, { "on", false }, { "why", why }, { "cap", cap } })
		end
		return base
	end
	local n = d.variant == "polycentric" and MET.centreCount(cap, job.metroCentres) or 0
	local key = d.variant .. ":" .. n
	s.metroStyles = s.metroStyles or {}
	local c = s.metroStyles[key]
	if c and c.base == base then return c.style end
	if s.sampler == nil then s.sampler, s.samplerUs = self.E.sampler(), self:nowUs() end
	local st = MET.apply(base, d, { cap = cap, sampler = s.sampler, forcedCentres = job.metroCentres })
	s.metroStyles[key] = { base = base, style = st }
	s.metroWhy = key
	local ctext = {}
	for _, x in ipairs(st.metro.centres) do
		ctext[#ctext + 1] = string.format("%.0f:%.0f@%.0f:%s:%s", x[1], x[2], x[3], x.src or "ring", x.core or "plan")
	end
	-- (centres added over time, later-ideas phase: a polycentric town gains a centre at 2 x / 30000 persons)
	if d.variant == "polycentric" and (s.polyN or 0) > 0 and n > s.polyN then
		self:log("METRO", { { "town", t }, { "name", self.E.name(t) }, { "event", "centreAdded" }, { "centres", n },
			{ "was", s.polyN }, { "cap", cap } })
	end
	if d.variant == "polycentric" then s.polyN = n end
	self:log("METRO", { { "town", t }, { "name", self.E.name(t) }, { "on", true }, { "variant", d.variant }, { "why", d.why },
		{ "cap", cap }, { "style", base.id }, { "shape", st.shape and st.shape.id or "-" }, { "centres", #st.metro.centres },
		{ "at", #ctext > 0 and table.concat(ctext, "/") or "-" }, { "templates", string.format("%s/%s/%s", st.templates.main,
			st.templates.medium, st.templates.small) }, { "outer", st.outer and st.outer.id or "-" } })
	return st
end

--- METRO line per planned increment of a metropolis (debug): variant, centres, density per centre vs between
--- (buildings per ha, ot_metro.density), this increment's locked edges, the town's green gaps (ot_metrics).
function Driver:metroLine(job)
	local st = job.style
	if st == nil or st.metro == nil or not self:debugOn() then return end
	local ok, f = pcall(function()
		local dn = MET.density(st, job.pts, job.ext and job.ext.r or 0)
		local dt, bt = MET.densityText(dn)
		local gg = MT.greenGaps(job.g, job.pts)
		return { { "town", job.town }, { "variant", st.metro.variant }, { "centres", #st.metro.centres }, { "dens", dt },
			{ "between", bt }, { "buildings", job.pts and #job.pts or 0 }, { "lock", job.lockN or 0 },
			{ "green", MT.greenText(gg) }, { "cores", PO.text(job.mp, job.g) } }
	end)
	if ok then self:debug("METRO step", f) else self:log("WARN", { { "stage", "metro" }, { "town", job.town }, { "err", f } }) end
end

--- Other towns around town t (position pos): { {dir = rad, dist = m} } within ot_shape.NEIGHBOUR_FAR,
--- nearest first (the shape's "growing toward a neighbour").
function Driver:neighbours(t, pos)
	local out = {}
	local E = self.E
	local ids = self.townList or (E.towns and E.towns()) or {}
	for _, id in ipairs(ids) do
		if id ~= t then
			local x, y = E.boxCentre(id)
			if x then
				local d = G.dist(pos[1], pos[2], x, y)
				if d > 1 and d <= SH.NEIGHBOUR_FAR then out[#out + 1] = { dir = G.atan2(y - pos[2], x - pos[1]), dist = d, town = id } end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.town < b.town
	end)
	return out
end

--- Dev tools: style fields overridden after resolve (`templates` merged per class, template paths redone;
--- other keys replace the field), e.g. { templates = { main = "medium", medium = "medium", small = "medium" } }.
function D.applyOverride(style, o)
	for k, v in pairs(o) do
		if k == "templates" and type(v) == "table" then
			for c, size in pairs(v) do style.templates[c] = size end
			for _, c in ipairs(ST.CLASSES) do style.templatePaths[c] = ST.templatePath(style.templates[c], style.newTemplates) end
		else
			style[k] = v
		end
	end
end

--- Compact one-line traceback (the innermost `n` frames of this mod's files, "file:line<fn" joined by "|").
function D.traceText(tb, n)
	local out = {}
	for line in tostring(tb or ""):gmatch("[^\n]+") do
		-- (chunk names "...ot_x.lua:12:" or [string "...ot_x.lua"]:12:)
		local f, l, fn = line:match("([%w_]+%.lua)\"?%]?:(%d+): in [%w ]-'?([%w_%.:]*)'?$")
		if f == nil then f, l = line:match("([%w_]+%.lua)\"?%]?:(%d+):") end
		if f and f ~= "ot_driver.lua" or (f and #out == 0) then
			out[#out + 1] = f .. ":" .. l .. ((fn and fn ~= "") and ("<" .. fn) or "")
			if #out >= (n or 8) then break end
		end
	end
	return #out > 0 and table.concat(out, "|") or "-"
end

--- Installs the hang guard's count hook on coroutine co (nil: the running thread): an error tagged D.HANG_TAG with the
--- traceback once nowUs() passes deadline (us). Returns true when installed (debug.sethook available).
function D.guardOn(co, nowUs, deadline)
	if not D.PLAN_GUARD or type(debug) ~= "table" or type(debug.sethook) ~= "function" then return false end
	local function hook()
		if nowUs() > deadline then
			local tb = type(debug.traceback) == "function" and debug.traceback("", 2) or ""
			if co then debug.sethook(co) else debug.sethook() end
			error(D.HANG_TAG .. ":" .. D.traceText(tb), 0)
		end
	end
	local ok = pcall(function()
		if co then debug.sethook(co, hook, "", D.PLAN_HOOK_COUNT) else debug.sethook(hook, "", D.PLAN_HOOK_COUNT) end
	end)
	return ok
end

--- Removes the hang guard's hook from co (nil: the running thread).
function D.guardOff(co)
	if type(debug) ~= "table" or type(debug.sethook) ~= "function" then return end
	pcall(function() if co then debug.sethook(co) else debug.sethook() end end)
end

--- Runs fn(...) in protected mode with the hang guard on the running thread (at most limitUs): ok, results... like
--- pcall; a hang comes back as (false, "planHang:<trace>").
function D.guard(nowUs, limitUs, fn, ...)
	local on = D.guardOn(nil, nowUs, nowUs() + limitUs)
	local ok, a, b, c, d = pcall(fn, ...)
	if on then D.guardOff(nil) end
	return ok, a, b, c, d
end

--- true when err is the hang guard's error.
function D.isHang(err)
	return type(err) == "string" and err:sub(1, #D.HANG_TAG) == D.HANG_TAG
end

-- the selector's holds an empty plan names (§59), in this order: report field, short name
D.HELD_FIELDS = { { "leadHeld", "lead" }, { "sparseHeld", "sparse" }, { "ringHeld", "ring" }, { "housedHeld", "housed" },
	{ "wedgeHeld", "wedge" }, { "meadowHeld", "meadow" }, { "headHeld", "head" }, { "edgeHeld", "edge" },
	{ "indHeld", "ind" }, { "forestHeld", "forest" }, { "gapHeld", "gap" }, { "zoneHeld", "zone" },
	{ "groveHeld", "grove" }, { "emptyLoopHeld", "emptyLoop" }, { "envHeld", "env" }, { "armFill", "armFill" },
	{ "armFrontHeld", "armFront" }, { "wideHeld", "wide" }, { "frontHeld", "front" } }

--- The knot holds of a plan report as text: "<held>:<cross>/<parallel>/<loop>/<side>/<row>" ("0" without a knot report;
--- row: one empty row at a time, 2026-10-19, ot_knot ROW).
--- (§75 follow-up, 2026-10-19: also on the empty PLAN and STUCK lines, as side / parallel never give way: the
--- 2026-10-19_1949 run could not tell whether they emptied a plan)
function D.knotText(report)
	if type(report) ~= "table" or report.knotWhy == nil then return "0" end
	return string.format("%d:%s", report.knotHeld or 0, KN.text(report.knotWhy))
end

--- The holds of a plan report as text ("sparse=14,lead=2", "-" for none) and the one holding the most pieces (or nil).
function D.heldText(report)
	if type(report) ~= "table" then return "-", nil end
	local parts, top, topN = {}, nil, 0
	for _, f in ipairs(D.HELD_FIELDS) do
		local n = tonumber(report[f[1]]) or 0
		if n > 0 then
			parts[#parts + 1] = f[2] .. "=" .. n
			if n > topN then top, topN = f[2], n end
		end
	end
	if report.sparseRelax then parts[#parts + 1] = "sparseRelax" end
	return #parts > 0 and table.concat(parts, ",") or "-", top
end

function Driver:snapshot(job, now, saved)
	local t0 = self:nowUs()
	local g, joinInfo, joinable, why = self:snapshotGraph(job)
	local style = self:styleFor(job, g, saved)
	job.baseStyle = style
	style = self:metroStyle(job, style)
	-- away from industries: the town's current industry info on the style the planner uses (refreshed with the map's
	-- list; the cached sector preference is redone when it changed)
	local si = self:townState(job.town).ind
	if style.industry ~= si then
		style.industry = si
		style._irr = nil
	end
	-- gaps between towns (ot_gap, R3): the halfway lines to the neighbours, the gap short of them (job.noGaps: none;
	-- satellites, bridges and frames are planned without the planner's holds)
	style.gaps = nil
	if D.GAPS and not job.noGaps then
		local E = self.E
		local s0 = self:townState(job.town)
		local pos = s0.pos or { job.ext.cx, job.ext.cy }
		-- (a Works / district and its parent: the gap is waived along their link, ot_gap waive, 2026-10-14)
		local nbs = self:neighbours(job.town, pos)
		local partners = self:offshootPartners(job.town, saved)
		for _, nb in ipairs(nbs) do if partners[nb.town] then nb.waive = true end end
		local okG, gp = pcall(GP.build, pos, nbs, job.town, {
			owner = E.closestTown and function(x, y)
				local ct = E.closestTown(x, y)
				return ct == nil or ct == job.town
			end or nil })
		if okG then style.gaps = gp end
	end
	-- forest-aware towns (ot_forest, phase F): the town's tree grid and this plan's mode (hug / clear / none) on the style
	-- (a Works / district town hugs the forest from its first build: its streets facing the forest locked, the corridor
	-- cost, the clearing budget; 2026-10-14 late, Winchcombe Heath)
	style.offshoot = self:isOffshootTown(job.town, saved) or nil
	style.forest = FO.forStyle(self:townState(job.town).forest, style)
	-- (R1: a hug town's clearing budget for this decade of game time: forest under lots, hectares)
	-- (dev forest-lane test, job.forestLane "force": the plan builds through the forest (a hug town as clear), so a lane
	-- comes out where the plan crosses forest)
	if job.forestLane == "force" and style.forest and (style.forest.mode == "hug" or style.forest.mode == "deep") then
		style.forest.mode = "clear"
	end
	if FO.active(style.forest) then
		-- (deep forest towns, 2026-10-14: a quarter of the budget; groves inside the houses' extent x FRAME_F are kept)
		local deepF = FO.isDeep(style.forest) and FO.DEEP.BUDGET_F or nil
		style.forest.budget = FO.budgetFor(self:townState(job.town), style.year, style.tier, job.pts and #job.pts or nil, deepF)
		if deepF then style.forest.frameR = FO.DEEP.FRAME_F * ((job.ext and job.ext.r) or 0) end
		-- (forest lanes through a held strip, round after the names run: ot_select lets a held piece that closes a gap
		-- in the town through as a lane, ot_lane.free; nothing when lanes are off for the session)
		local ts = self:townState(job.town)
		if LN.ON and not self.lanesOff then
			style.forest.laneFree = function(pc, co) return LN.free(style, pc, co, ts.lanes or 0, LN.MAX_PER_TOWN) end
		end
	end
	if style.outer and style._outerCache then style._outerCache.forest = style.forest end
	-- the landscape pull (ot_land, §62): the town's big-scale lean from its tree grid and wide survey, after the forest
	-- mode (a clear town feels the woods less)
	self:landRefresh(job, style)
	-- the landscape-aware skeleton (ot_skeleton, §63): the arms' headings, reach and caps from the tree grid and the lean,
	-- decided once before the first build and saved on the frame
	self:skeletonRefresh(job, style, saved)
	-- station quarter (M3): the town's current rail stations (re-read every STATION_REFRESH_S); a change rebuilds the
	-- master plan (ot_core: mp.stationKey) and a quarter that becomes eligible logs its MOTIF pick line
	self:stationRefresh(job, style, now)
	-- bridgehead quarter (M4): the town's river bridge (its frame's `br`, or this session's build with its geometry)
	self:bridgeRefresh(job, style, saved)
	local sources, fallback = self:sources(job, style)
	-- (§73: the town's medium / large runs, short and lone ones, by builder; also on the STREETS line)
	local wideText = "-"
	local okW, wa = pcall(function()
		local byId = {}
		for _, ed in ipairs(job.edges or {}) do byId[ed.id] = ed end
		local ts = self:townState(job.town)
		return core.wideAudit(g, function(e) return D.edgeBuilder(ts, byId[e.id]) end)
	end)
	if okW and wa then
		wideText = core.wideAuditText(wa)
		-- (not `wide`: that field is the town's 2 km site survey, ot_terrain.wide, read by the site classifier)
		self:townState(job.town).wideRuns = wa
	end
	-- (§75 follow-up, 2026-10-20: the town's own empty rows, ot_knot.emptyRows; only when the debug line is written)
	-- (`us` the snapshot without it, `rowsUs` the measure)
	local snapUs, rowsText, rowsUs = self:nowUs() - t0, nil, nil
	if self:debugOn() then
		local r0 = self:nowUs()
		local okR, rows = pcall(function() return KN.emptyRows(g, KN.limits(style)) end)
		rowsText = okR and KN.rowsText(rows) or "err"
		rowsUs = self:nowUs() - r0
	end
	self:debug("SNAPSHOT", { { "town", job.town }, { "nodes", #g.nodes }, { "edges", #g.edges }, { "net", job.net or 0 },
		{ "deadEnds", #OG.deadEnds(g) }, { "joinable", joinable }, { "noJoin", why }, { "wideRuns", wideText },
		{ "emptyRows", rowsText or "-" }, { "us", snapUs }, { "rowsUs", rowsUs or "-" } })
	if joinable == 0 then
		job.why = "noJoinableDeadEnd:" .. (why ~= "" and why or "none")
		return self:finish(job.town, "empty", now)
	end
	if fallback == nil then
		self:debug("SKIP", { { "town", job.town }, { "reason", "noTownStreetToCopy" } })
		return self:finish(job.town, "skip", now)
	end
	job.g, job.joinInfo, job.style, job.sources, job.fallback = g, joinInfo, style, sources, fallback
	self:satelliteDecide(job, now, saved)
	if job.satPlan == nil then self:worksLinkDecide(job, now, saved) end
	local offTurn = job.trigger == "offshoot"
	if job.satPlan == nil and job.worksPlan == nil and not offTurn then self:leadDecide(job, now, saved) end
	if job.satPlan == nil and job.worksPlan == nil and job.leadPlan == nil then self:worksDecide(job, now, saved) end
	if job.satPlan == nil and job.worksPlan == nil and job.leadPlan == nil then self:districtDecide(job, now, saved) end
	if job.satPlan == nil and job.leadPlan == nil and job.worksPlan == nil and not offTurn then self:bridgeDecide(job, now, saved) end
	-- (an offshoot turn builds only a satellite or a link; a Works / district creation was sent above)
	if offTurn and job.satPlan == nil and job.worksPlan == nil then
		job.why = "offshoot:noPlan"
		return self:finish(job.town, "room", now)
	end
	job.maxEdges = job.maxEdgesOverride or A.maxEdges(self.opts.lookahead)
	-- a metropolis builds bigger increments (Showcase v8 round): its demand must land on our streets, not the game's
	if style.metro and job.maxEdgesOverride == nil then job.maxEdges = math.max(job.maxEdges, D.METRO_MAX_EDGES) end
	-- ... and grid styles a smaller copy of that (style.mech.maxEdges, Showcase v9 round): whole blocks / frames at once
	if D.MECH and not style.metro and style.mech and style.mech.maxEdges and job.maxEdgesOverride == nil then
		job.maxEdges = math.max(job.maxEdges, style.mech.maxEdges)
		-- a fast grower's frames may be bigger (ot_assess FAST: up to 36 edges)
		if job.trigger == "demand" and job.dem and job.dem.incMax then job.maxEdges = math.max(job.maxEdges, job.dem.incMax) end
	elseif not style.metro and job.maxEdgesOverride == nil and job.trigger == "demand" and job.dem then
		-- a demand build is sized to the demand (the other styles; metropolis / mech frames need their whole size), up
		-- to the fast grower's increment (ot_assess FAST, 2026-10-13: 18 -> up to 36 edges)
		job.maxEdges = math.max(D.DEMAND_MIN_INC, math.min(math.max(job.maxEdges, job.dem.incMax or 0), math.ceil(job.dem.edges)))
	end
	-- (§65 stall guard: a stalled "mod"-locked town plans a bigger increment, Driver:stallGuard)
	if job.stall and job.maxEdgesOverride == nil then
		job.maxEdges = math.min(D.STALL_MAX_EDGES, math.max(job.maxEdges, math.ceil(job.maxEdges * D.STALL_INC_MUL)))
	end
	-- upward density (ot_upward, later-ideas phase): a big town (or one whose form can't absorb its demand) builds a
	-- smaller demand increment and gets an upward dose in its core after it (upwardStart)
	self:upwardDecide(job, style, now)
	-- one memoised terrain sampler per town (ot_core caches the master plan per style and sampler);
	-- renewed now and then so terraforming and our own cut/fill show up
	local s = self:townState(job.town)
	if s.sampler == nil or now - s.samplerUs > D.SAMPLER_RENEW_S * 1e6 then
		s.sampler, s.samplerUs = self.E.sampler(), now
	end
	job.sampler = s.sampler
	-- green wedges (ot_wedge, 2026-10-13): armed towns keep their wedges free of the mod's own pieces (ot_select), and a
	-- demand build may first frame the game's tips in them (frameDecide)
	style.wedges = (D.WEDGES and job.wedges ~= false and WG.applies(style)) or nil
	-- protected meadows (ot_meadow, later-ideas phase): sprawling and unarmed character towns keep meadow sectors between
	-- their lobes free of the mod's pieces, and a demand build may frame the game's tips in them (frameDecide)
	style.meadows = (D.MEADOWS and job.wedges ~= false and MD.applies(style)) or nil
	if style.meadows and not s.meadowLogged then
		s.meadowLogged = true
		local z = MD.zone(g, style, SEL.irregularity(style))
		local lob = {}
		for _, a in ipairs(z and z.lobes or MD.lobes(style, SEL.irregularity(style))) do lob[#lob + 1] = string.format("%.0f", math.deg(a)) end
		self:log("MEADOW", { { "town", job.town }, { "name", self.E.name(job.town) }, { "form", style.form and style.form.id or "-" },
			{ "character", style.form and style.form.character == true }, { "shape", style.shape and style.shape.id or "-" },
			{ "lobes", #lob > 0 and table.concat(lob, "/") or "-" }, { "meadows", MD.text(z) } })
	end
	if job.satPlan == nil and job.bridgePlan == nil and job.leadPlan == nil and job.worksPlan == nil then self:frameDecide(job, now) end
	-- (§67: the valves' context from this plan's style)
	local okV, errV = pcall(self.glockCtx, self, job, style)
	if not okV then self:log("WARN", { { "stage", "glockCtx" }, { "town", job.town }, { "err", errV } }) end
	job.stage = "plan"
end

function Driver:plan(job, now)
	if job.satPlan then return self:satellitePlan(job, now) end
	if job.leadPlan then return self:leadPlanStage(job, now) end
	if job.worksPlan then return self:worksPlanStage(job, now) end
	if job.bridgePlan then return self:bridgePlanStage(job, now) end
	if job.framePlan then return self:framePlanStage(job, now) end
	local E, t = self.E, job.town
	local s = self:townState(t)
	local t0 = self:nowUs()
	-- planning is sliced over ticks (2026-10-12: big EU towns took ~17-25 ms per increment): ot_core yields
	-- between its rounds once PLAN_SLICE_US passed in this tick; without coroutines (or if one fails) in one go
	local opts = { terrain = job.sampler, stats = s.stats, maxEdges = job.maxEdges, join = "deadEnd", exclude = s.exclude,
		jointRule = job.jointRule, limits = job.limits }
	-- (§74: near-miss joins; the street nodes they may end at checked against the engine, cached on the job)
	if D.NEAR_MISS and NMISS.ON then
		-- (a new plan starts afresh; a plan going on in its coroutine keeps what its earlier slices found)
		if job.planCo == nil then job.nmInfo = {} end
		opts.nearMiss = { midOk = function(n) return self:midJoinOk(job, n) end,
			retiredOk = D.NEAR_MISS_RETIRED and function(n) return self:retiredJoinOk(job, n) end or nil, buildings = job.pts,
			clock = self:clockFn(), budgetUs = D.NEAR_MISS_US }
	end
	-- own empty budget (ot_core OWN_EMPTY_*, 2026-10-13): the mod's own unhoused streets (locked or built this session)
	-- (forced increments, 2026-10-14 §57: the showcase forces increments regardless of demand; its roundabout town's long
	-- empty snaking roads, Shape cross's empty combs and EU organic's thin fingers came from forced plans skipping the own
	-- empty budget. They keep it now, down to a floor of core.OWN_EMPTY_MIN edges, and hold pieces among sparse streets,
	-- ot_select SPARSE)
	local forcedEmpty = D.FORCED_EMPTY and job.force and not job.head
	if forcedEmpty then
		local lim = {}
		for k, v in pairs(job.limits or {}) do lim[k] = v end
		lim.sparse = true
		opts.limits = lim
		opts.ownEmptyFloor = core.OWN_EMPTY_MIN
	end
	-- (2026-10-18: a fast grower's demand increment, up to 2 x the usual edges, may reach FAST_FRONT blocks per unit of
	-- its fast factor beyond the growth front, ot_select FRONT_RELAX note; the housed front and the lead limit hold)
	-- (... and a demand build of a town whose last plan came out empty (s.emptyRun) may take the front up to
	-- ot_select.FRONT_RELAX blocks wider when it would come out empty again: the town is not stuck for good)
	local demandJob = job.trigger == "demand" and not job.force
	local fast = demandJob and job.dem and tonumber(job.dem.fast) or 1
	local stuck = demandJob and (s.emptyRun or 0) > 0
	if (D.FAST_FRONT > 0 and fast > 1) or stuck then
		local lim = {}
		for k, v in pairs(opts.limits or {}) do lim[k] = v end
		if D.FAST_FRONT > 0 and fast > 1 then lim.frontExtra = (fast - 1) * D.FAST_FRONT end
		if stuck then lim.frontRelax = SEL.FRONT_RELAX end
		opts.limits = lim
	end
	if D.OWN_EMPTY and (forcedEmpty or not job.force) and not job.head then
		local own = s.own or {}
		-- (forest lanes, R2: a country lane stays empty on purpose; it never counts)
		opts.ownEmpty = function(e) return (e.locked == true or own[e.id] == true) and not LN.isCountry(e.template) end
		-- (R4: a town with retired empty dead ends gets the tighter own empty budget: fewer streets ahead of the houses)
		if (s.retired or 0) > 0 then opts.ownEmptyBase = core.OWN_EMPTY_TIGHT end
	end
	-- (§69 steer towns: the lead beyond housed streets capped (no bare spikes: ot_lockpol.leadCap, housed = HOUSED_MIN_B
	-- buildings), an arm's housed front continuous (armCont), the rake / wiggle look rules (ot_select RAKE / WIGGLE))
	if self:jobLock(job) == "steer" and D.STEER_LIMITS then
		local lim = {}
		for k, v in pairs(opts.limits or {}) do lim[k] = v end
		lim.steer = true
		-- (forced increments, the dev tools: no lead cap; they grow regardless of demand and keep the own empty floor)
		if not job.force or job.head then
			lim.leadCap = LP.leadCap(job.style)
			lim.housedMin = LP.HOUSED_MIN_B
		else
			-- (one empty row at a time, ot_knot ROW: forced plans grow regardless of the houses)
			lim.rowHold = false
		end
		lim.armCont = LP.armGap(job.style)
		opts.limits = lim
	end
	-- (§65 stall guard, Driver:stallGuard: more own empty budget; level 2 the envelope wider; level 3 the forest hold a
	-- step looser, last: open land first)
	if job.stall then
		opts.ownEmptyBase = core.OWN_EMPTY_BASE + D.STALL_OWN_EMPTY_M
		if job.stall >= 2 then opts.envScale0 = D.STALL_ENV_SCALE end
		if job.stall >= 3 then
			local lim = {}
			for k, v in pairs(opts.limits or {}) do lim[k] = v end
			lim.forestStep = D.STALL_FOREST_STEP
			opts.limits = lim
		end
	end
	local inc, report, mp
	if job.planCo == nil and D.SLICE_PLAN and type(coroutine) == "table" then
		job.planUs, job.planSlices = 0, 0
		opts.yield = function()
			if self:nowUs() - job.sliceUs > D.PLAN_SLICE_US then coroutine.yield() end
		end
		job.planCo = coroutine.create(function() return core.planIncrement(job.g, job.style, opts) end)
	end
	if job.planCo then
		job.sliceUs = t0
		-- hang guard: this slice ends by PLAN_HANG_US, the plan as a whole by PLAN_TOTAL_US
		local deadline = t0 + math.min(D.PLAN_HANG_US, math.max(0, D.PLAN_TOTAL_US - (job.planUs or 0)))
		local co = job.planCo
		local guarded = D.guardOn(co, self:clockFn(), deadline)
		local ok, a, b, c = coroutine.resume(co)
		if guarded then D.guardOff(co) end
		job.planUs = (job.planUs or 0) + (self:nowUs() - t0)
		job.planSlices = (job.planSlices or 0) + 1
		if not ok then
			-- (2026-10-13 hang fix: no second try in one go in the same tick; the town gets no plan this time)
			job.planCo = nil
			local hang = D.isHang(a)
			self:log("WARN", { { "stage", "plan" }, { "town", t }, { "name", E.name(t) },
				{ "msg", hang and "planHang" or "plan_coroutine_failed" }, { "us", job.planUs }, { "slices", job.planSlices },
				{ "err", hang and a:sub(#D.HANG_TAG + 2) or a } })
			job.why = hang and "planHang" or ("planError:" .. tostring(a))
			job.planUs, job.planSlices = nil, nil
			return self:finish(t, "fail", now)
		elseif coroutine.status(job.planCo) ~= "dead" then
			return   -- next tick goes on
		else
			job.planCo = nil
			inc, report, mp = a, b, c
		end
	else
		local ok, a, b, c = D.guard(self:clockFn(), D.PLAN_TOTAL_US, core.planIncrement, job.g, job.style, opts)
		if not ok then
			self:log("WARN", { { "stage", "plan" }, { "town", t }, { "msg", D.isHang(a) and "planHang" or "planError" }, { "err", a } })
			job.why = D.isHang(a) and "planHang" or ("planError:" .. tostring(a))
			return self:finish(t, "fail", now)
		end
		inc, report, mp = a, b, c
	end
	local us = job.planUs and job.planUs > 0 and job.planUs or (self:nowUs() - t0)
	local slices = job.planSlices or 1
	job.planUs, job.planSlices = nil, nil
	-- (M4: a waiting motif branch whose main line's next piece kept being refused is dropped, ot_select WAIT_GIVEUP)
	for _, w in ipairs(report and report.waitGaveUp or {}) do
		self:debug("MOTIF", { { "town", t }, { "name", E.name(t) }, { "event", "waitGiveUp" }, { "piece", w.key },
			{ "line", w.line or "-" }, { "plans", w.plans } })
	end
	-- (upward density: demand plans held in a row are the "form can't absorb the demand" signal, ot_upward.held)
	if job.trigger == "demand" and not job.force and not job.head then
		s.upPressure = UP.held(job.maxEdges, #inc.edges, report) and (s.upPressure or 0) + 1 or 0
	end
	if #inc.edges == 0 then
		local r = {}
		for _, dd in ipairs(inc.dropped) do r[dd.reason] = (r[dd.reason] or 0) + 1 end
		local rt = {}
		for k, v in pairs(r) do rt[#rt + 1] = k .. ":" .. v end
		table.sort(rt)
		-- (§59: which holds emptied the plan, and how many plans in a row came out empty: the 2026-10-15_0234 showcase's
		-- EU organic stopped after four empty plans whose line named no hold)
		local heldText, heldTop = D.heldText(report)
		s.emptyRun = (s.emptyRun or 0) + 1
		self:debug("PLAN", { { "town", t }, { "edges", 0 }, { "reached", report and report.reached or 0 },
			{ "blocked", report and report.blocked or 0 }, { "excluded", report and report.excluded or 0 },
			{ "dropped", table.concat(rt, "/") },
			{ "ownEmpty", report and report.ownEmpty and string.format("%.0f/%s", report.ownEmpty, tostring(report.ownEmptyCap or "-")) or "-" },
			{ "forestHeld", report and report.forestHeld or 0 }, { "gapHeld", report and report.gapHeld or 0 },
			{ "zoneHeld", report and report.zoneHeld or 0 }, { "held", heldText }, { "knotHeld", D.knotText(report) },
			{ "knotRelax", report and report.knotRelax == true }, { "emptyRun", s.emptyRun },
			{ "forced", job.force == true }, { "stall", job.stall or 0 }, { "us", us }, { "slices", slices },
			{ "nearMiss", (NMISS.text(report and report.nearMiss)) }, { "nmKept", select(2, NMISS.text(report and report.nearMiss)) },
			{ "nmErr", report and report.nearMissErr or "-" } })
		-- (a town held for many plans in a row: one line in every log, also without debug, then every STUCK_EVERY more)
		if s.emptyRun == D.STUCK_AT or (s.emptyRun > D.STUCK_AT and (s.emptyRun - D.STUCK_AT) % D.STUCK_EVERY == 0) then
			self:log("STUCK", { { "town", t }, { "name", E.name(t) }, { "emptyRun", s.emptyRun }, { "held", heldText },
				{ "knotHeld", D.knotText(report) },
				{ "reached", report and report.reached or 0 }, { "blocked", report and report.blocked or 0 },
				{ "excluded", report and report.excluded or 0 },
				{ "ownEmpty", report and report.ownEmpty and string.format("%.0f/%s", report.ownEmpty, tostring(report.ownEmptyCap or "-")) or "-" },
				{ "forced", job.force == true }, { "trigger", job.trigger or "-" } })
		end
		local fb = job.jointFallback
		if fb then
			-- the joint-rule replan after a refusal left nothing: go on with that refusal (halve / exclude)
			job.jointFallback = nil
			job.jointRule, job.jointTried = false, true   -- the halved plans keep their joints as before
			job.inc = fb.inc
			return self:refusedOnward(job, now, fb.why, fb.fields)
		end
		job.why = "planEmpty:" .. table.concat(rt, "/") .. (heldTop and ("held:" .. heldTop) or "")
		if report and report.ownEmptyCap == 0 then job.why = string.format("ownEmpty:%.0f", report.ownEmpty or 0) end
		-- (an upward town whose plan came out empty still gets its core dose: the demand goes up, not out)
		if self:upwardStart(job, now, "empty") then return end
		return self:finish(t, "empty", now)
	end
	job.jointFallback = nil
	-- tree-lined entries (ot_entry, later-ideas phase): the increment's streets along a country road's first stretch out
	-- of town take the `_trees` variant of their template (seeded per town; off for the session after refusals)
	self:entryMark(job, inc)
	-- forest lanes (ot_lane, R2): stretches through forest on both sides go out as locked country lanes (no houses)
	self:laneMark(job, inc, report)
	-- (2026-10-14 late) no straight town street longer than CK.STRAIGHT_MAX ahead of the houses: the far part goes
	local straightText = self:straightGuard(job, inc)
	if #inc.edges == 0 then
		job.why = "straight"
		return self:finish(t, "empty", now)
	end
	-- (§73) the run rule again on what goes out: a run the straight guard cut or a forest lane split may have become
	-- too short (its edges get the narrower template, no medium stub is left)
	local okRun, errRun = pcall(core.continuity, job.g, inc, job.style)
	if okRun then inc.mix = core.mix(inc)
	else self:log("WARN", { { "stage", "continuity" }, { "town", t }, { "err", errRun } }) end
	-- the offline geometry checker over what goes to the engine (curve radius vs the town templates' 44/60 m,
	-- angles at the nodes, kinks where one line continues; ot_check)
	local geo = CK.increment(inc, job.g)
	local selfC = CK.selfClearance(inc)
	job.diagDone = false
	-- (gap holds and frames per SIMGROW year, dev ALLTOWN / SIMGROW year: the vanilla comparison, 2026-10-14)
	self.counts.gapHeld = (self.counts.gapHeld or 0) + (report and report.gapHeld or 0)
	self:debug("PLAN", { { "town", t }, { "edges", #inc.edges }, { "nodes", #inc.nodes }, { "joins", #inc.joins },
		{ "maxEdges", job.maxEdges }, { "length", inc.stats.length }, { "minR", geo.minRadius },
		{ "minAngle", geo.minAngle }, { "maxKink", geo.maxKink }, { "maxCorner", geo.maxCorner },
		{ "shortest", geo.shortest }, { "geoBad", CK.badText(geo) }, { "geoSide", geo.counts.side or 0 }, { "self", #selfC }, { "pruned", job.pruneRounds or 0 },
		{ "shape", job.style.shape and job.style.shape.id or "-" },
		{ "hier", (core.hierText(inc.hier)) }, { "wideDefl", select(2, core.hierText(inc.hier)) or "-" },
		{ "runs", D.runsText(inc.hier) },
		{ "armFill", report and report.armFill or 0 }, { "armBuilt", report and report.armBuilt or "-" }, { "armWait", report and report.armWait or 0 },
		{ "mix", core.mixText(inc.mix) }, { "gridShare", D.gridShare(inc, job.style) },
		{ "emptyLen", D.emptyText(job.g) }, { "emptyCap", report and report.emptyCap or "-" },
		{ "ownEmpty", report and report.ownEmpty and string.format("%.0f/%s", report.ownEmpty, tostring(report.ownEmptyCap or "-")) or "-" },
		{ "housedHeld", report and report.housedHeld or 0 },
		{ "wedgeHeld", report and report.wedgeR and string.format("%d@%.0f", report.wedgeHeld or 0, report.wedgeR) or "-" },
		{ "leadHeld", report and report.leadHeld or 0 }, { "ringHeld", report and report.ringHeld or 0 },
		{ "sparseHeld", report and report.sparseHeld or 0 }, { "sparseRelax", report and report.sparseRelax == true },
		{ "origins", D.originsText(inc, job.g) },
		{ "edgeHeld", report and report.edgeHeld or 0 },
		{ "crescents", D.crescentText(job.mp or mp) },
		{ "footprint", D.countDropped(inc, "footprint") }, { "kinks", #core.jointIssues(job.g, inc) },
		{ "jointRule", job.jointRule and "on" or "off" }, { "indPen", D.indPenText(inc, job.style) },
		{ "forestMode", job.style.forest and job.style.forest.mode or "-" }, { "forestCut", D.forestCutText(inc, job.style) },
		{ "land", LAND.text(job.style.land) },
		{ "forestHeld", report and report.forestHeld or 0 }, { "forestRelax", report and report.forestRelax or 0 },
		{ "forestLot", D.forestLotText(inc, job.style) }, { "forestBudget", D.forestBudgetSpend(inc, job.style) },
		{ "us", us },
		{ "slices", slices }, { "greenRelax", report and report.greenRelax or "-" },
		{ "upCut", job.upward and string.format("%s:%.2f:%d", job.upward.why, job.upward.cut, job.upward.asked or 0) or "-" },
		{ "meadowHeld", report and report.meadowR and string.format("%d@%.0f", report.meadowHeld or 0, report.meadowR) or "-" },
		{ "trees", D.treesText(inc) }, { "lanes", inc.lanes or 0 }, { "gapHeld", report and report.gapHeld or 0 },
		{ "retired", self:townState(t).retired or 0 }, { "emptyLoopHeld", report and report.emptyLoopHeld or 0 },
		{ "gaps", GP.text(job.style.gaps) }, { "zoneHeld", report and report.zoneHeld or 0 },
		{ "zones", IND.zoneText(job.style.industry) }, { "fac", IND.facText(job.style.industry) },
		{ "zoneLock", job.zoneLockN or 0 }, { "straight", straightText },
		{ "deepLocks", D.deepLockText(inc, job.style) }, { "bends", D.deepWind(inc, job.style).bends },
		{ "maxStraight", D.deepWind(inc, job.style).maxStraight }, { "groveHeld", report and report.groveHeld or 0 },
		{ "char", CH.text(job.style.charKind, job.style.densify) }, { "roundabouts", self:townState(t).rbBuilt or 0 },
		{ "stall", job.stall or 0 }, { "forestStep", report and report.forestStep or 0 },
		{ "lockMode", self:jobLock(job) },
		{ "spikeTrim", string.format("%d/%d", report and report.leadHeld or 0, report and report.armTrim or 0) },
		{ "leadCap", report and report.leadM and string.format("%.0f", report.leadM) or "-" },
		{ "rakeHeld", report and report.rakeHeld or 0 }, { "rakeJoin", report and report.rakeJoin or 0 },
		{ "wiggleHeld", report and report.wiggleHeld or 0 }, { "lookRelax", report and report.lookRelax == true },
		{ "knotHeld", D.knotText(report) },
		{ "knotRelax", report and report.knotRelax == true },
		{ "hookHeld", report and report.hookWhy and string.format("%d:%d/%d", report.hookHeld or 0, report.hookWhy.turn or 0,
			report.hookWhy.back or 0) or "0" },
		{ "hookRelax", report and report.hookRelax == true },
		{ "nearMiss", (NMISS.text(report and report.nearMiss)) }, { "nmKept", select(2, NMISS.text(report and report.nearMiss)) },
		{ "nmJoins", report and report.nearMiss and #report.nearMiss.joins > 0 and table.concat(report.nearMiss.joins, ",") or "-" },
		{ "nmErr", report and report.nearMissErr or "-" } })
	do
		local s9 = self:townState(t)
		if report then
			s9.spikeTrim = (s9.spikeTrim or 0) + (report.leadHeld or 0) + (report.armTrim or 0)
			s9.rakeJoin = (s9.rakeJoin or 0) + (report.rakeJoin or 0)
			s9.rakeHeld = (s9.rakeHeld or 0) + (report.rakeHeld or 0)
			s9.wiggleHeld = (s9.wiggleHeld or 0) + (report.wiggleHeld or 0)
			s9.knotHeld = (s9.knotHeld or 0) + (report.knotHeld or 0)
			s9.hookHeld = (s9.hookHeld or 0) + (report.hookHeld or 0)
		end
	end
	if job.style.shape then self:shapeLine(job, inc, report) end
	self:motifFallbackLines(job)
	-- a tiny leftover (after drops) is built only when it closes a loop: lone 1-2 edge stubs and zigzag
	-- bits read as noise and the town doesn't adopt them
	if #inc.edges < D.MIN_USEFUL and #inc.joins < 2 and (job.pruneRounds or 0) + (job.halved or 0) > 0 then
		job.why = "tiny:" .. #inc.edges
		if inc.edges[1] then self:exclude(t, inc.edges[1].key) end   -- the next try plans elsewhere
		self:debug("TINY", { { "town", t }, { "why", job.why }, { "joins", #inc.joins } })
		return self:finish(t, "empty", now)
	end
	-- one-way rings at the plan's own new crossings (roundabout towns, ot_ring 2026-10-14): RB lines
	self:ringMark(job, inc)
	job.inc, job.mp, job.report = inc, mp, report
	self:jobLock(job)
	-- (§69 steer towns: the policy's inputs and the tips allowed)
	local okSP, errSP = pcall(self.steerPrep, self, job)
	if not okSP then
		job.steerC = nil
		self:log("WARN", { { "stage", "steerPrep" }, { "town", t }, { "err", errSP } })
	end
	job.lockKeys, job.lockN, job.lockModeUsed = D.lockKeys(job)
	if inc.rings then
		-- (the ring quarters locked: the town hangs no streets on them)
		job.lockKeys = job.lockKeys or {}
		for k in pairs(RG.lockKeys(inc)) do
			if not job.lockKeys[k] then job.lockKeys[k], job.lockN = true, (job.lockN or 0) + 1 end
		end
	end
	local fl = job.forestLockN
	if fl and fl.side + fl.tip + (fl.near or 0) > 0 then
		self:debug("FOREST", { { "town", t }, { "lock", fl.side + fl.tip + (fl.near or 0) }, { "side", fl.side }, { "tip", fl.tip },
			{ "near", fl.near or 0 }, { "edges", #inc.edges }, { "mode", job.style.forest and job.style.forest.mode or "-" } })
	end
	self:metroLine(job)
	job.stage = "send"
end

--- PLAN `forestCut=` (phase F): share of the increment's street length in forest (ot_forest cover >= FOREST_COVER, the
--- grid as read before the build), "-" without a tree grid.
function D.forestCutText(inc, style)
	local fo = style and style.forest
	if fo == nil then return "-" end
	local segs = {}
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.p0 and e.p1 then segs[#segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2] } end
	end
	local sh = FO.cutShare(fo, segs)
	return sh and string.format("%.2f", sh) or "-"
end

--- The forest under the increment's lots (R1, ot_forest.corridor over each edge; hectares), nil without a tree grid.
function D.forestLot(inc, style, spend)
	local fo = style and style.forest
	if fo == nil or fo.grid == nil then return nil end
	local ha = 0
	for _, e in ipairs(inc and inc.edges or {}) do
		-- (a forest lane has no lots: it clears no plots)
		-- (spend: the clearing budget's hectares, a deep town's wooded pieces x DEEP.SPEND_F, ot_forest.lotSpend)
		if e.p0 and e.p1 and not e.forestLane then
			local co = FO.corridor(fo, { e.p0, e.p1 })
			ha = ha + (spend and FO.lotSpend(fo, co) or co.lotHa)
		end
	end
	return ha
end

--- PLAN `forestLot=` (R1): hectares of forest under the increment's lots, "-" without a tree grid.
function D.forestLotText(inc, style)
	local ha = D.forestLot(inc, style)
	return ha and string.format("%.2f", ha) or "-"
end

--- PLAN `forestBudget=` (R1): a hug town's clearing budget spends the increment's forest under lots; returns the budget
--- left / total after it ("-" for other towns). (Spent when planned: a refused plan re-plans smaller and may spend twice,
--- the conservative side.)
function D.forestBudgetSpend(inc, style)
	local fo = style and style.forest
	local b = fo and fo.budget
	if b == nil then return "-" end
	-- (round after the names run: spent when built, Driver:forestBudgetCommit; a refused plan re-planned smaller spent
	-- twice before. The text shows what is left once this increment is built, and the window: first / decade / growth)
	inc.forestLotHa = D.forestLot(inc, style, true) or 0
	return FO.budgetText(b, inc.forestLotHa) .. ":" .. tostring(b.win or "-")
end

--- After a build: a hug town's clearing budget spends the increment's forest under lots (D.forestBudgetSpend).
function D.forestBudgetCommit(job)
	local fo = job and job.style and job.style.forest
	local b = fo and fo.budget
	if b == nil or job.inc == nil or job.inc.forestLotHa == nil then return end
	b.used = b.used + job.inc.forestLotHa
	job.inc.forestLotHa = nil
end

--- Deep forest towns (2026-10-14): PLAN `deepLocks=` "<edges ot_forest.facesForest locks>/<edges>" ("-" for other towns).
function D.deepLockText(inc, style)
	local fo = style and style.forest
	if not FO.isDeep(fo) then return "-" end
	local n, tot = 0, 0
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.p0 and e.p1 and not e.forestLane then
			tot = tot + 1
			if FO.facesForest(fo, e.p0, e.p1, false, false) then n = n + 1 end
		end
	end
	return string.format("%d/%d", n, tot)
end

--- Deep forest towns: PLAN `bends=` "<edges bending >= ot_forest.BEND_DEG>/<edges>" and `maxStraight=` (m: the longest
--- straight stretch of one edge or of a chain of straight edges, ot_forest.windStats); "-" for other towns. Cached on inc.
function D.deepWind(inc, style)
	if not FO.isDeep(style and style.forest) or inc == nil then return { bends = "-", maxStraight = "-" } end
	if inc._deepWind then return inc._deepWind end
	local okR, rep = pcall(CK.straightRuns, inc, {})
	local mx, b, n = FO.windStats(inc, okR and rep and rep.max or 0)
	inc._deepWind = { bends = string.format("%d/%d", b, n), maxStraight = string.format("%.0f", mx), max = mx }
	return inc._deepWind
end

--- Deep forest towns (ot_forest deepPick, 2026-10-14): is town t deep? Its saved frame decides once there is one (`fd`:
--- deep; a frame without it: never deep, so towns built before this round keep their plan); before the first build the
--- draw (main style mode only, the map's quota: saved frames + this session's picks); the dev "Force deep forest"
--- (s.forceDeep) any town. A FOREST mode=deep line per town and reason. Returns deep, why.
D.DEEP = true
function Driver:deepFor(t, s, style, frame, mode, job)
	if not (D.DEEP and FO.DEEP_ON) then return false, "off" end
	local deep, why
	if s.forceDeep then
		deep, why = true, "force"
	elseif s.forceChar or (frame == nil and self:charKindOf(t)) then
		-- (a strong-character town is never deep forest too, ot_character 2026-10-14)
		deep, why = false, "character"
	elseif frame ~= nil then
		deep, why = frame.deep == true, frame.deep and "saved" or "framed"
	elseif mode ~= "main" or job.pure or job.shape or job.form or job.motif then
		deep, why = false, "devStyle"
	else
		local count = self:deepCount(t)
		-- (NEXT_PHASE_BRIEF 61: the naming phase's deep forest pick, s.nameDeep: true named for it, false named otherwise)
		local okP, d, w = pcall(FO.deepPick, s.forest, style, { count = count, named = s.nameDeep })
		if okP then deep, why = d, w else deep, why = false, "err" end
	end
	s.deep = deep or nil
	if s.deepWhy ~= why then
		s.deepWhy = why
		local fg = s.forest
		local fields = { { "town", t }, { "name", self.E.name and self.E.name(t) or "-" }, { "mode", deep and "deep" or "notDeep" },
			{ "why", why or "-" }, { "share", fg and fg.share and string.format("%.2f", fg.share) or "-" },
			{ "ring", fg and string.format("%.2f", FO.ringShare(fg, FO.DEEP_RING[1], FO.DEEP_RING[2])) or "-" },
			{ "dense", fg and fg.denseCells or "-" }, { "count", self:deepCount(t) + (deep and 1 or 0) } }
		if deep then self:log("FOREST", fields)
		elseif fg ~= nil and (fg.share or 0) >= FO.MIN_SHARE then self:debug("FOREST", fields) end
		-- (deep forest is the first strong character kind, ot_character: its own pick, the CHARACTER line too)
		if deep then
			self:debug("CHARACTER", { { "town", t }, { "name", self.E.name and self.E.name(t) or "-" }, { "event", "pick" },
				{ "kind", "deep_forest" }, { "score", fg and string.format("%.2f", FO.ringShare(fg, FO.DEEP_RING[1], FO.DEEP_RING[2])) or "-" },
				{ "why", why or "-" }, { "applied", "yes" } })
		end
	end
	return deep, why
end

--- Deep forest towns on the map other than t: the saved frames' `fd` plus this session's picks not saved yet.
function Driver:deepCount(t)
	local n, set = SV.deepTowns(self.saved)
	if set[t] then n = n - 1 end
	for id, st in pairs(self.towns or {}) do
		if id ~= t and type(st) == "table" and st.deep and not set[id] then n = n + 1 end
	end
	return n
end

--- Is town t a deep forest town (this session's pick or its saved frame)?
function Driver:isDeepTown(t, saved)
	local s = self.towns and self.towns[t]
	if s and s.deep then return true end
	local fr = SV.frame(saved or self.saved, t)
	return fr ~= nil and fr.deep == true
end

--- Dev (OT Dev "Force deep forest"): town t plans as a deep forest town from its next snapshot (on = false: back to the
--- draw); its styles are resolved again. Session only; the frame saves `fd` at its first build as for any deep town.
function Driver:devDeep(t, on)
	local s = self:townState(t)
	s.forceDeep = (on ~= false) or nil
	s.styles = {}
	s.deepWhy = nil
	return s.forceDeep == true
end

--- STYLE / SHAPE / ALLTOWN `forest=` (phase F): "<share>:<mode>" (ot_forest.text), "-" without a tree grid.
function D.forestText(style)
	return FO.text(style and style.forest)
end

--- PLAN `indPen=`: share of the increment's street length inside industry buffers (ot_industry), "-" without
--- industries near the town.
function D.indPenText(inc, style)
	local ind = style and style.industry
	if ind == nil then return "-" end
	local segs = {}
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.p0 and e.p1 then segs[#segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2] } end
	end
	local sh = IND.penShare(ind, segs)
	return sh and string.format("%.2f", sh) or "-"
end

--- Share of an increment's edge length on the town's grid axes (ot_metrics.axisShare vs style.axis, PLAN `gridShare=`;
--- Showcase v9 round: NA grid should lay grid streets from step 1).
function D.gridShare(inc, style)
	local segs = {}
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.p0 and e.p1 then segs[#segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2] } end
	end
	if #segs == 0 then return "-" end
	return string.format("%.2f", (MT.axisShare(segs, style and style.axis or 0)))
end

--- PLAN `origins=`: the increment's new street metres by where they come from (ot_select.origin: arm, m:<motif>, ring,
--- crescent, link, plain, rb: a ring or hub arm) and the farthest new point from a street with houses, with its origin
--- ("arm:320/plain:80@far=290:arm"); 2026-10-14 §57, the 2347 run's empty roads could not be traced to their source.
function D.originsText(inc, g)
	if inc == nil or #(inc.edges or {}) == 0 then return "-" end
	local m, order = {}, {}
	local idx = g and SEL.housedIndexM(g, 1000) or nil
	local far, farO = -1, "-"
	for _, e in ipairs(inc.edges) do
		local o = e.origin or ((e.ring or e.hubArm or e.ringArm) and "rb") or "plain"
		if m[o] == nil then m[o] = 0; order[#order + 1] = o end
		m[o] = m[o] + (e.length or 0)
		if idx and e.p0 and e.p1 then
			for _, p in ipairs({ e.p0, e.p1 }) do
				local d = SEL.housedDist(idx, p[1], p[2])
				if d > far then far, farO = d, o end
			end
		end
	end
	local parts = {}
	for _, o in ipairs(order) do parts[#parts + 1] = string.format("%s:%.0f", o, m[o]) end
	local farT = far < 0 and "-" or (far == math.huge and ">2000" or string.format("%.0f", far))
	return table.concat(parts, "/") .. "@far=" .. farT .. ":" .. farO
end

--- Unhoused street length of the snapshot (ot_metrics.emptyLen; PLAN `emptyLen=` m/edges, "-" without parcel data).
function D.emptyText(g)
	local len, n = MT.emptyLen(g)
	if len == nil then return "-" end
	return string.format("%.0f/%d", len, n)
end

--- Crescents of the master plan with arcs / all (ot_crescent; PLAN `crescents=`), "-" for none.
function D.crescentText(mp)
	local cs = mp and mp.crescents
	if cs == nil or #cs == 0 then return "-" end
	local n = 0
	for _, c in ipairs(cs) do if (c.arcs or 0) > 0 then n = n + 1 end end
	return string.format("%d/%d", n, #cs)
end

--- Dropped planner edges with this reason (PLAN line: `footprint=`).
function D.countDropped(inc, reason)
	local n = 0
	for _, d in ipairs(inc.dropped or {}) do if d.reason == reason then n = n + 1 end end
	return n
end

function Driver:refused(job, now, why, fields)
	local t = job.town
	self.counts.refused = self.counts.refused + 1
	local f = { { "town", t }, { "why", why }, { "edges", #job.inc.edges }, { "maxEdges", job.maxEdges } }
	for _, x in ipairs(fields or {}) do f[#f + 1] = x end
	self:debug("REFUSED", f)
	-- sharp turns at existing dead ends (ot_select.JOINT_TURN; Showcase v4 DIAGJOINT): replan once without them
	-- at the same size before halving
	if not job.jointRule and not job.jointTried and #core.jointIssues(job.g, job.inc) > 0 then
		job.jointRule = true
		self.counts.jointReplans = (self.counts.jointReplans or 0) + 1
		self:debug("JOINTRULE", { { "town", t }, { "kinks", #core.jointIssues(job.g, job.inc) }, { "edges", #job.inc.edges } })
		job.jointFallback = { inc = job.inc, why = why, fields = fields }
		job.stage = "plan"
		return
	end
	return self:refusedOnward(job, now, why, fields)
end

--- Refusal handling after the joint-rule replan: halve the increment, then leave the smallest one's first piece out.
function Driver:refusedOnward(job, now, why, fields)
	if job.bridgePlan then
		-- a bridge is all or nothing (no smaller retries); the refused crossing is skipped from now on, the next
		-- candidate comes at a later demand build (BRIDGE_TRIES per session); a "Construction not possible" without a
		-- collision tries the next bridge type too
		local s = self:townState(job.town)
		s.bridgeBad = s.bridgeBad or {}
		if job.bridgePlan.key then s.bridgeBad[job.bridgePlan.key] = true end
		local cnp = false
		for _, f in ipairs(fields or {}) do
			if f[1] == "msgs" and D.notPossible(f[2]) then cnp = true end
			if f[1] == "collisions" and (tonumber(f[2]) or 0) > 0 then cnp = false end
		end
		if cnp and job.bridgePlan.typePath then
			s.bridgeTypeSkip = s.bridgeTypeSkip or {}
			s.bridgeTypeSkip[job.bridgePlan.typePath] = true
		end
		local bf = { { "town", job.town }, { "name", self.E.name(job.town) }, { "outcome", "refused" }, { "why", why } }
		for _, f in ipairs(fields or {}) do bf[#bf + 1] = f end
		self:log("BRIDGE", bf)
		job.why = "bridge:" .. tostring(why)
		self.counts.fails = self.counts.fails + 1
		return self:finish(job.town, "fail", now)
	end
	if job.framePlan then
		-- a frame is not halved: tried again after FRAME_GAP_S (its refused links are left out: exclude)
		local s = self:townState(job.town)
		s.frameNextUs = now + D.FRAME_GAP_S * 1e6
		self:log("FRAME", { { "town", job.town }, { "outcome", "refused" }, { "why", why } })
		job.why = "frame:" .. tostring(why)
		for _, e in ipairs(job.inc.edges or {}) do self:exclude(job.town, e.key) end
		self.counts.fails = self.counts.fails + 1
		return self:finish(job.town, "fail", now)
	end
	if job.worksPlan then
		self:worksLinkFailed(job, now, "refused:" .. tostring(why), fields)
		job.why = "works:" .. tostring(why)
		self.counts.fails = self.counts.fails + 1
		return self:finish(job.town, "fail", now)
	end
	if job.leadPlan then
		-- a lane ahead is all or nothing: another site / later (LEAD_RETRY_S), at most LEAD_TRIES per session
		self:leadFailed(job, now, "refused:" .. tostring(why), fields)
		job.why = "lead:" .. tostring(why)
		self.counts.fails = self.counts.fails + 1
		return self:finish(job.town, "fail", now)
	end
	if job.satPlan then
		-- a satellite increment is all or nothing: no halving; try again (another site / later) after SAT_RETRY_S
		local s = self:townState(job.town)
		if job.satPlan.kind == "seed" then self:satSeedFailed(job, now) else s.satNextUs = now + D.SAT_RETRY_S * 1e6 end
		local sf = { { "town", job.town }, { "kind", job.satPlan.kind }, { "refused", why } }
		for _, f in ipairs(fields or {}) do
			if f[1] == "msgs" or f[1] == "collisions" or f[1] == "partners" then sf[#sf + 1] = f end
		end
		sf[#sf + 1] = { "tries", s.satTries or 0 }
		self:log("SATELLITE", sf)
		job.why = "satellite:" .. tostring(why)
		self.counts.fails = self.counts.fails + 1
		return self:finish(job.town, "fail", now)
	end
	local t = job.town
	if #job.inc.edges > D.MIN_EDGES then
		job.maxEdges = math.max(D.MIN_EDGES, math.floor(#job.inc.edges / 2))
		job.halved = (job.halved or 0) + 1
		job.stage = "plan"
		return
	end
	-- the smallest increment is refused too: leave its first piece out from now on (this session)
	local msgs = ""
	for _, x in ipairs(fields or {}) do if x[1] == "msgs" or x[1] == "err" then msgs = msgs .. fmt(x[2]) end end
	job.why = why .. ":" .. msgs
	self:exclude(t, job.inc.edges[1].key)
	self.counts.fails = self.counts.fails + 1
	return self:finish(t, "fail", now)
end

--- SHAPE line (debug, SHAPES_BRIEF 2026-10-12): per planned increment of a town, the shape and how the whole town
--- reads so far, so a showcase log tells the story without screenshots. Fields: shape, axis (deg), net (streets
--- followed beyond the snapshot circle), env (envelope level, m of effective distance; scale when widened),
--- streets = elong/arms/side/waist of every street in the snapshot (game core + ours), houses = the same for the
--- town's buildings, inc = share of this increment's new length in the shape's arm corridors (ot_shape.inArm,
--- linear / ridge / cross / fingers / twin) and beyond the envelope.
function Driver:shapeLine(job, inc, report)
	if not self:debugOn() then return end   -- (metrics, green gaps: debug only)
	local sh = job.style.shape
	local ok, f = pcall(function()
		local cx, cy = sh.centre[1], sh.centre[2]
		local streets = MT.graph(job.g, cx, cy)
		local houses = (job.pts and #job.pts > 0) and MT.points(job.pts, cx, cy) or nil
		local L, inArm, out = 0, 0, 0
		local env = report and report.envCap and report.envCap * (report.envScale or 1) or nil
		for _, e in ipairs(inc.edges) do
			local l = G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			L = L + l
			if SH.inArm(sh, mx, my) then inArm = inArm + l end
			if env and SH.distance(sh, mx, my, job.sampler) > env then out = out + l end
		end
		local ownIds, st = {}, self:townState(job.town)
		for _, ed in ipairs(job.edges or {}) do if ed.locked or st.own[ed.id] then ownIds[ed.id] = true end end
		return { { "town", job.town }, { "shape", sh.id }, { "form", job.style.form and job.style.form.id or "-" }, { "axis", math.floor(math.deg(G.wrap(sh.axis or 0)) % 360 + 0.5) },
			{ "net", job.net or 0 }, { "env", report and report.envCap or "-" },
			{ "envScale", report and report.envScale or 1 }, { "streets", MT.short(streets) },
			{ "houses", houses and MT.short(houses) or "-" }, { "buildings", job.pts and #job.pts or 0 },
			{ "inc", string.format("arm%.0f/out%.0f", L > 0 and 100 * inArm / L or 0, L > 0 and 100 * out / L or 0) },
			{ "edges", #job.g.edges }, { "reach", (sh.reach or 1) >= 1 and "strong" or "mild" },
			-- per arm: metres the streets run beyond the farthest housed street / the farthest street (along the arm)
			{ "armGap", SEL.armGapText(SEL.armGaps(job.g, job.style)) },
			{ "armFill", report and report.armFill or 0 }, { "green", MT.greenText(MT.greenGaps(job.g, job.pts)) },
			-- shore towns: share of streets / buildings within 300 m of the water, shoreline covered, inland depth
			{ "shore", MT.shoreText(MT.shore(job.g, sh.shore or (job.style.waterPremium and job.style.waterPremium.shore),
				job.pts)) },
			-- the same for the mod's own streets only (locked or built this session; 2026-10-13: was the depth ours or
			-- the game's?)
			{ "ownShore", MT.shoreText(MT.shore(job.g, sh.shore or (job.style.waterPremium and job.style.waterPremium.shore),
				nil, function(e) return ownIds[e.id] == true end)) }, { "shoreFront", job.style.shoreFront and (job.style.shoreFront.row and "row" or "promenade") or "-" },
			{ "ind", IND.text(job.style.industry) }, { "fac", IND.facText(job.style.industry) },
			{ "indTurned", sh.indTurned == true },
			{ "forest", D.forestText(job.style) },
			-- (round 5, 2026-10-13) land spread of the buildings (ratio / % beyond 1.5 x the equal-area disc / lobes) and the
			-- armed towns' steepest arm (length / climb / houses along it)
			{ "spread", MT.spreadText(MT.landSpread(job.pts, cx, cy)) },
			{ "hillRoad", MT.hillText(MT.hillRoad(job.g, sh, job.pts, job.sampler)) } }
	end)
	if ok then self:debug("SHAPE", f) else self:log("WARN", { { "stage", "shape" }, { "town", job.town }, { "err", f } }) end
end

--- PR.build info: join nodes, source edges, and the lane count of every edge a new edge may copy (per edge id
--- and per template), so a new node's config uses each street's own lanes (mixed lane counts at one node
--- asserted lane_config_util.cpp:364 GetLaneOffset in the pre-check, 2026-10-11 showcase).
function Driver:buildInfo(job)
	local edgeLanes, templateLanes = {}, {}
	for _, ed in ipairs(job.edges or {}) do
		edgeLanes[ed.id] = ed.lanes
		if ed.template and ed.lanes and templateLanes[ed.template] == nil then templateLanes[ed.template] = ed.lanes end
	end
	if self.E.templateLanes then
		for _, path in pairs((job.style and job.style.templatePaths) or {}) do
			if templateLanes[path] == nil then templateLanes[path] = self.E.templateLanes(path) end
		end
	end
	-- (§67 valve stub: one outward tip of a locked build left unlocked toward the wanted heading)
	local stub = nil
	local mode = self:jobLock(job)
	if D.locksAll(mode) then
		local okS, k = pcall(self.glockStubKey, self, job)
		if okS then stub = k end
	end
	job.glockStub = stub
	local unlock = stub and { [stub] = true } or nil
	-- (§69 steer: the policy's tips stay open; a Works link is locked all along, nothing sprouts off it midway)
	if mode == "steer" and job.steerTips ~= nil and #job.steerTips > 0 then
		unlock = unlock or {}
		for _, p in ipairs(job.steerTips) do unlock[p.key] = true end
	end
	local lockAll = D.locksAll(mode) or (mode == "steer" and job.lockModeUsed == "works")
	-- (§74: the street nodes a near-miss join ends at, Driver:midJoinOk, beside the dead ends)
	local nodes = job.joinInfo
	if job.nmInfo and next(job.nmInfo) ~= nil then
		nodes = {}
		for k, v in pairs(job.joinInfo or {}) do nodes[k] = v end
		for k, v in pairs(job.nmInfo) do if nodes[k] == nil then nodes[k] = v end end
	end
	return { nodes = nodes, sources = job.sources, fallback = job.fallback, edgeLanes = edgeLanes,
		templateLanes = templateLanes, allowNoConfig = self.allowNoConfig or D.ALLOW_NO_CONFIG, leftHand = self:leftHand(),
		lock = lockAll, lockKeys = job.lockKeys, unlockKeys = unlock,
		bridgeType = job.bridgePlan and job.bridgePlan.typeIndex or nil }
end

function Driver:send(job, now)
	local E, t = self.E, job.town
	-- industry keep-clear zones (2026-10-13): no mod street or its lots in one, whatever planned it (the town plan holds
	-- them in ot_select; satellites, lanes ahead, Works links, bridges and frames are checked here). The offending pieces
	-- are excluded for the session.
	local ind = job.style and job.style.industry
	if IND.ZONE and ind and ind.zones and #ind.zones > 0 and job.inc and not job.zoneChecked then
		job.zoneChecked = true
		local hit = 0
		for _, e in ipairs(job.inc.edges or {}) do
			if e.p0 and e.p1 and not e.existing then
				local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
				if IND.zoneHit(ind, { e.p0, { mx, my }, e.p1 }) then
					hit = hit + 1
					self:exclude(t, e.key)
				end
			end
		end
		if hit > 0 then return self:refusedOnward(job, now, "industryZone", { { "zoneEdges", hit } }) end
	end
	-- held created towns (NEXT_PHASE_BRIEF 52.3): no street of another town's plan (demand, satellite pod, lane ahead,
	-- lead-out, bridge, frame) in the land of a Works / district town while it is held; the pieces are excluded as above
	if D.HOLD_GUARD and job.inc and job.holdChecked ~= job.inc and not job.force then
		job.holdChecked = job.inc   -- (each replan's increment once)
		local hits, who = self:heldHits(job)
		if hits > 0 then
			self:debug("OFFSHOOT", { { "event", "hold" }, { "town", who.town }, { "name", E.name(who.town) },
				{ "why", "guard:" .. tostring(who.why) }, { "edges", hits }, { "by", t } })
			-- (a town plan: planned again at the same size without them, HOLD_REPLANS times; a lane, link, bridge, frame
			-- or satellite piece is all or nothing: its refusal path)
			local whole = job.bridgePlan or job.framePlan or job.worksPlan or job.leadPlan or job.satPlan
			if not whole and (job.holdReplans or 0) < D.HOLD_REPLANS then
				job.holdReplans = (job.holdReplans or 0) + 1
				job.stage = "plan"
				return
			end
			return self:refusedOnward(job, now, "heldTown", { { "heldEdges", hits }, { "held", who.town } })
		end
	end
	local spec, err = PR.build(job.inc, self:buildInfo(job))
	if spec == nil then return self:refused(job, now, "mapping", { { "err", err } }) end
	if not PR.noNegativeZero(spec) then return self:refused(job, now, "negativeZero") end
	local okP, proposal = pcall(E.proposal, spec)
	if not okP then return self:refused(job, now, "proposal", { { "err", proposal } }) end
	local asPlayer = H.player == true
	local ctx = E.context(asPlayer)
	local pre = E.precheck(proposal, ctx)
	local fields = { { "msgs", pre.msgs }, { "collisions", pre.collisions }, { "buildings", pre.buildings },
		{ "err", pre.err or "-" }, { "us", pre.us } }
	if pre.partners then fields[#fields + 1] = { "partners", self:partnerText(job, pre.partners) } end
	-- "Construction Not Possible" with no collision: what the lane assertion (lane_config_util.cpp:364) looked like
	if not pre.ok and D.notPossible(pre.msgs) and (pre.collisions or 0) == 0 then
		self.counts.notPossible = (self.counts.notPossible or 0) + 1
	end
	-- a refused pre-check: one pre-check per edge (stage "diag", a few per tick) finds the edges that fail
	-- alone; they are dropped and the increment planned again at the same size (PRUNE_ROUNDS), instead of
	-- halving it (halved plans left kinked chains and stubs, showcase 2026-10-11). The dev tools' diagnosis
	-- (ot_hooks.diagnose) logs each failing edge (DIAG) and also runs on dry runs.
	-- (tree-lined entries, ot_entry: a refused pre-check with tree-lined edges goes out once more without them; after
	-- EN.MAX_REFUSED such refusals the trees are off for the session)
	-- (one-way rings, ot_ring 2026-10-14: a refused pre-check with rings goes out once more with the plain crossings; after
	-- RING_MAX_REFUSED such refusals the town plans no more rings this session)
	if not pre.ok and job.inc.rings and not job.ringsStripped then
		job.ringsStripped = true
		local s = self:townState(t)
		local nearT = RG.nearText(job.g, job.inc.rings)
		local n = RG.strip(job.inc)
		s.ringRefused = (s.ringRefused or 0) + 1
		-- (a pair reserved on a ring that is not built: gone)
		if job.rbNewPending and s.rbPending then
			s.rbPending = false
			if E.sendEvent then E.sendEvent(SV.EVENT_ID, SV.EV_PAIR, { town = t, n = 0 }) end
		end
		if s.ringRefused >= D.RING_MAX_REFUSED then s.ringOff = true end
		self:log("RB", { { "town", t }, { "name", E.name(t) }, { "event", "refused" }, { "rings", n }, { "msgs", pre.msgs },
			{ "collisions", pre.collisions }, { "refusals", s.ringRefused }, { "off", s.ringOff == true }, { "near", nearT } })
		return
	end
	if not pre.ok and job.inc.trees and not job.treesStripped then
		job.treesStripped = true
		self.treesRefused = (self.treesRefused or 0) + 1
		local n = EN.strip(job.inc)
		if self.treesRefused >= EN.MAX_REFUSED and not self.treesOff then
			self.treesOff = true
		end
		self:log("ENTRY", { { "town", t }, { "outcome", "refused" }, { "edges", n }, { "msgs", pre.msgs },
			{ "refusals", self.treesRefused }, { "off", self.treesOff == true } })
		return
	end
	-- (forest lanes, ot_lane R2: the same for the country lanes; LN.MAX_REFUSED refusals turn them off for the session)
	if not pre.ok and job.inc.lanes and not job.lanesStripped then
		job.lanesStripped = true
		self.lanesRefused = (self.lanesRefused or 0) + 1
		local n = LN.strip(job.inc)
		if self.lanesRefused >= LN.MAX_REFUSED then self.lanesOff = true end
		self:log("FORESTLANE", { { "town", t }, { "outcome", "refused" }, { "edges", n }, { "msgs", pre.msgs },
			{ "refusals", self.lanesRefused }, { "off", self.lanesOff == true } })
		return
	end
	local pruneOk = not pre.ok and #job.inc.edges >= 2 and (job.pruneRounds or 0) < D.PRUNE_ROUNDS and not job.bridgePlan
		and not job.leadPlan and not job.worksPlan   -- (a lane ahead / a Works link is all or nothing)
	if not job.diagDone and (pruneOk or (H.diagnose == true and job.dry)) then
		job.diagDone = true
		job.diag = { i = 0, failed = {}, nFailed = 0, us = 0, ctx = ctx, info = self:buildInfo(job),
			pre = pre, fields = fields, spec = spec, proposal = proposal, asPlayer = asPlayer }
		job.stage = "diag"
		return
	end
	return self:afterPrecheck(job, now, spec, proposal, ctx, pre, fields, asPlayer)
end

--- Pre-check result of the whole increment: refused -> plan again smaller; dry -> log; else log and send.
function Driver:afterPrecheck(job, now, spec, proposal, ctx, pre, fields, asPlayer)
	local E, t = self.E, job.town
	if not pre.ok then return self:refused(job, now, "precheck", fields) end
	job.balance0 = E.balance()
	job.spec, job.pre = spec, pre
	if job.dry then
		-- dev tools' dry run: planned and pre-checked, never sent
		self:log("DRY", { { "town", t }, { "name", E.name(t) }, { "style", job.style.id }, { "spec", PR.summary(spec) },
			{ "preCost", pre.cost }, { "preUs", pre.us }, { "open", job.lots and job.lots.open },
			{ "player", asPlayer and "on" or "off" } })
		return self:finish(t, "dry", now)
	end
	-- every proposal is logged BEFORE it is sent (crash forensics)
	self:log("SEND", { { "town", t }, { "name", E.name(t) }, { "style", job.style.id }, { "spec", PR.summary(spec) },
		{ "preCost", pre.cost }, { "preUs", pre.us }, { "open", job.lots and job.lots.open }, { "balance", job.balance0 },
		{ "player", asPlayer and "on" or "off" } })
	self.inflight = true
	job.sentUs = now
	job.stage = "wait"
	-- (2026-10-17: the balance at the send, for the refund of the build's charge; no player set: not charged)
	job.refundBal0 = asPlayer and self:balanceAtSend(now) or nil
	E.sendBuild(proposal, ctx, function(success, info)
		job.result = { success = success, info = info or {}, us = self:nowUs() - now }
	end)
end

function Driver:done(job, now)
	local E, t = self.E, job.town
	local r = job.result
	self.inflight = false
	local s = self:townState(t)
	local fields = { { "town", t }, { "name", E.name(t) }, { "ok", r.success }, { "edges", #job.spec.edges },
		{ "ms", r.us / 1000 }, { "cost", r.info.cost }, { "msgs", r.info.msgs or {} },
		{ "balance", string.format("%s->%s", fmt(job.balance0), fmt(E.balance())) } }
	if r.success then
		self.counts.builds = self.counts.builds + 1
		s.builds = s.builds + 1
		job.cost = r.info.cost
		local rec = self:recordBuilt(job, now)
		job.rec = rec
		fields[#fields + 1] = { "found", rec and #rec.edges or 0 }
		-- the build serves its edges' worth of the town's growth demand (ot_assess.served)
		if job.dem then
			local len = 0
			for _, e in ipairs(job.spec.edges) do len = len + G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2]) end
			A.served(s.ledger, job.caps, len * job.dem.perM)
		end
		fields[#fields + 1] = { "trigger", job.trigger or "-" }
		-- street mix (large / medium / small % of new length) of this build and of all builds in this town so far
		-- (this session); the hierarchy target for the late styles: large <= ~20 %, small >= ~50 %
		if job.inc and job.inc.mix then
			s.mix = core.addMix(s.mix, job.inc.mix)
			fields[#fields + 1] = { "mix", core.mixText(job.inc.mix) }
			fields[#fields + 1] = { "townMix", core.mixText(s.mix) }
		end
		local nLocked = 0
		for _, e in ipairs(job.spec.edges) do if e.locked then nLocked = nLocked + 1 end end
		fields[#fields + 1] = { "locked", nLocked }
		fields[#fields + 1] = { "lockMode", D.lockMode(job) }
		-- (§69 steer: why each new street is locked or open, and the tips left open)
		if job.steerTally then
			fields[#fields + 1] = { "steer", LP.tallyText(job.steerTally) }
			fields[#fields + 1] = { "tips", job.steerTips and #job.steerTips or 0 }
			local rt = {}
			for k, c in pairs(job.steerTipRej or {}) do rt[#rt + 1] = k .. ":" .. c end
			table.sort(rt)
			fields[#fields + 1] = { "tipRej", #rt > 0 and table.concat(rt, ",") or "-" }
			fields[#fields + 1] = { "smallWood", job.steerSmall or 0 }
		end
		self:log("BUILT", fields)
		self:buildRefund(job, now)
		if job.inc and job.inc.rings then
			s.rbBuilt = (s.rbBuilt or 0) + #job.inc.rings
			self:log("RB", { { "town", t }, { "name", E.name(t) }, { "event", "built" }, { "rings", #job.inc.rings },
				{ "total", s.rbBuilt }, { "oneway", true } })
		end
		local okM, errM = pcall(self.motifBuilt, self, job)
		if not okM then self:log("WARN", { { "stage", "motif" }, { "town", t }, { "err", errM } }) end
		local okSt, errSt = pcall(self.glockStubBuilt, self, job, now)
		if not okSt then self:log("WARN", { { "stage", "valveStub" }, { "town", t }, { "err", errSt } }) end
		if not s.frameSaved and not s.frameSent then
			-- (the town's own style and shape, not a metropolis variant's: ot_metro decides that again each session)
			-- (§65: the town's lock and its core, the street edges not the mod's before this first build)
			local lots = job.lots
			local fp = SV.frameParam(t, job.baseStyle or job.style, job.mp, job.caps and job.caps.initial,
				D.offshootSize(job.pts and #job.pts or 0, job.caps), { lock = self:townLockMode(t),
					core = lots and lots.edges and (lots.edges - (lots.ownEdges or 0)) or nil,
					gameLock = self:townGameLock(t), year = E.yearF and E.yearF() or nil })
			if fp then
				E.sendEvent(SV.EVENT_ID, SV.EV_FRAME, fp)
				s.frameSent = true
				self:debug("SAVE", { { "event", "frame" }, { "town", t }, { "axis", fp.a }, { "x", fp.x }, { "y", fp.y } })
			end
		end
		self.nextUs = now + D.AFTER_BUILD_S * 1e6
		if job.trigger == "demand" then s.demandBuilds = (s.demandBuilds or 0) + 1 end
		-- (R1: builds / edges since the town's tree grid was read; FO.RENEW_BUILDS / RENEW_EDGES re-read it)
		s.forestBuilds = (s.forestBuilds or 0) + 1
		s.forestEdges = (s.forestEdges or 0) + (job.spec and #job.spec.edges or 0)
		D.forestBudgetCommit(job)
		if job.satPlan then self:satelliteBuilt(job, now) end
		if job.leadPlan then self:leadBuilt(job, now) end
		if job.worksPlan then self:worksLinked(job, now) end
		if job.bridgePlan then self:bridgeBuilt(job, now) end
		if job.framePlan then self:frameBuilt(job, now) end
		if job.inc and job.inc.trees then self:entryBuilt(job) end
		if job.inc and job.inc.lanes then self:laneBuilt(job) end
		if self:upwardStart(job, now, "built") then return end
		if self:fillStart(job, now) then return end
		return self:finish(t, "built", now)
	end
	-- refused at build time (also silently, e.g. a street touching water): leave all its pieces out
	if job.bridgePlan then
		s.bridgeBad = s.bridgeBad or {}
		if job.bridgePlan.key then s.bridgeBad[job.bridgePlan.key] = true end
		self:log("BRIDGE", { { "town", t }, { "name", E.name(t) }, { "outcome", "failed" }, { "msgs", fmt(r.info.msgs or {}) },
			{ "key", job.bridgePlan.key or "-" }, { "deck", string.format("%.1f", job.bridgePlan.deck or 0) },
			{ "ship", job.bridgePlan.ship or "-" } })
	end
	if job.satPlan then
		if job.satPlan.kind == "seed" then self:satSeedFailed(job, now) else s.satNextUs = now + D.SAT_RETRY_S * 1e6 end
	end
	if job.leadPlan then self:leadFailed(job, now, "failed", { { "msgs", fmt(r.info.msgs or {}) } }) end
	if job.worksPlan then self:worksLinkFailed(job, now, "failed", { { "msgs", fmt(r.info.msgs or {}) } }) end
	self.counts.fails = self.counts.fails + 1
	self:log("FAILED", fields)
	job.why = "buildFailed:" .. fmt(r.info.msgs or {})
	for _, e in ipairs(job.spec.edges) do self:exclude(t, e.key) end
	return self:finish(t, "fail", now)
end

--- The refund of a successful build's charge (Driver:refundBuild): REFUND kind=build line with the amount and the
--- session total (STREETS refund=). Nothing without a balance at the send (infinite money, no player set, a dry run).
function Driver:buildRefund(job, now)
	if job.refundBal0 == nil then return end
	local r = job.result or {}
	local cost = tonumber(r.info and r.info.cost)
	if cost == nil or cost <= 0 then cost = tonumber(job.pre and job.pre.cost) end
	local bal0 = job.refundBal0
	job.refundBal0 = nil
	local amount, why, bal1 = self:refundBuild("build", bal0, cost, now)
	job.refund = amount
	self:log("REFUND", { { "kind", "build" }, { "town", job.town }, { "name", self.E.name(job.town) }, { "amount", amount },
		{ "why", why }, { "paid", bal1 and string.format("%.0f", bal0 - bal1) or "-" }, { "cost", fmt(cost) },
		{ "session", self.refundSum or 0 }, { "n", self.refundN or 0 } })
end

--- After a build: finds the street edges it added (each spec edge matched by both end positions, in either
--- direction, among edges that weren't in the job's snapshot) and remembers them in the town's history
--- (newest last, at most HISTORY_MAX). Returns the record { edges, nodes (new node ids), joins, us, style, mode,
--- expected } or nil.
function Driver:recordBuilt(job, now)
	local spec = job.spec
	if spec == nil or #spec.edges == 0 then return nil end
	local old = {}
	for _, ed in ipairs(job.edges or {}) do old[ed.id] = true end
	local sx, sy, n = 0, 0, 0
	for _, e in ipairs(spec.edges) do
		sx, sy, n = sx + e.p0[1] + e.p1[1], sy + e.p0[2] + e.p1[2], n + 2
	end
	local cx, cy = sx / n, sy / n
	local r = 0
	for _, e in ipairs(spec.edges) do
		r = math.max(r, G.dist(cx, cy, e.p0[1], e.p0[2]), G.dist(cx, cy, e.p1[1], e.p1[2]))
	end
	local found = {}
	for _, ed in ipairs(self.E.streets(cx, cy, r + 10)) do
		if not old[ed.id] then found[#found + 1] = ed end
	end
	local function near(a, b) return G.dist(a[1], a[2], b[1], b[2]) <= D.MATCH_M end
	local joins = {}
	for _, j in ipairs(spec.joins or {}) do joins[j] = true end
	local rec = { edges = {}, nodes = {}, joins = spec.joins or {}, us = now, style = job.style and job.style.id,
		mode = job.styleMode or "main", expected = #spec.edges }
	local used, nodeSeen = {}, {}
	local pairs_ = {}
	for _, e in ipairs(spec.edges) do
		for _, ed in ipairs(found) do
			if not used[ed.id] and ((near(ed.p0, e.p0) and near(ed.p1, e.p1)) or (near(ed.p0, e.p1) and near(ed.p1, e.p0))) then
				used[ed.id] = true
				rec.edges[#rec.edges + 1] = ed.id
				pairs_[#pairs_ + 1] = { e, ed }
				for _, nd in ipairs({ ed.n0, ed.n1 }) do
					if not joins[nd] and not nodeSeen[nd] then
						nodeSeen[nd] = true
						rec.nodes[#rec.nodes + 1] = nd
					end
				end
				break
			end
		end
	end
	local s = self:townState(job.town)
	for _, id in ipairs(rec.edges) do s.own[id] = true end
	-- (§74: near-miss joins built, STREETS `nearMiss=`)
	for _, e in ipairs(spec.edges) do
		if type(e.key) == "string" and e.key:sub(1, 3) == "nm:" then s.nearMissBuilt = (s.nearMissBuilt or 0) + 1 end
	end
	s.history[#s.history + 1] = rec
	while #s.history > D.HISTORY_MAX do table.remove(s.history, 1) end
	local okP, errP = pcall(self.provNote, self, job, pairs_)
	if not okP then self:log("WARN", { { "stage", "prov" }, { "town", job.town }, { "err", errP } }) end
	return rec
end

--- The job's kind for the provenance source (ot_prov.source): "sat" | "lead" | "works" | "bridge" | "frame" | nil (a
--- plan).
function D.provKind(job)
	if job.satPlan then return "sat" end
	if job.leadPlan then return "lead" end
	if job.worksPlan then return "works" end
	if job.bridgePlan then return "bridge" end
	if job.framePlan then return "frame" end
	return nil
end

--- Street provenance (§75 follow-up, 2026-10-19; ot_prov): after a build, one debug PROV line per built edge (at most
--- PV.LINES_MAX, then one with `more=`) and the record sent to the game script (ot_saved `pv`, always: the console lookup
--- ot_prov.who reads it). pairs = { { spec edge, built edge (ot_engine edgeTable) } }. Nothing for a dry run.
function Driver:provNote(job, pairs_)
	if job.dry or #pairs_ == 0 then return end
	local E, t = self.E, job.town
	local s = self:townState(t)
	local kind = D.provKind(job)
	local trig = job.head and "head" or (job.force and "force") or job.trigger or "-"
	local year = E.year and E.year() or nil
	local entries, n = {}, 0
	local dbg = self:debugOn()
	-- (§75 follow-up, 2026-10-20: `d=` the edge middle's distance from the town centre (the style's, as the plans and
	-- frames use; the houses' mean without a style), to read far-out builds against CHECK r / rBody)
	local ctr = (job.style and job.style.centre) or (job.ext and { job.ext.cx, job.ext.cy }) or nil
	for _, pr in ipairs(pairs_) do
		local e, ed = pr[1], pr[2]
		local src = PV.source(kind, e)
		local en = PV.entry({ id = ed.id, src = src, trig = trig, year = year, p0 = ed.p0, p1 = ed.p1,
			t0 = ed.t0, t1 = ed.t1 })
		if en then entries[#entries + 1] = en end
		n = n + 1
		if dbg and n <= PV.LINES_MAX then
			self:log("PROV", { { "town", t }, { "name", E.name(t) }, { "edge", ed.id },
				{ "n", string.format("%s,%s", tostring(ed.n0), tostring(ed.n1)) },
				{ "a", string.format("%.0f,%.0f", ed.p0[1], ed.p0[2]) }, { "b", string.format("%.0f,%.0f", ed.p1[1], ed.p1[2]) },
				{ "len", string.format("%.0f", tonumber(e.length) or G.dist(ed.p0[1], ed.p0[2], ed.p1[1], ed.p1[2])) },
				{ "d", ctr and string.format("%.0f", G.dist(ctr[1], ctr[2], (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2)) or "-" },
				{ "src", src }, { "key", PV.clean(e.key or "-") }, { "trig", trig }, { "seq", s.builds or 0 },
				{ "year", year or "-" }, { "lock", e.locked and 1 or 0 } })
		end
	end
	if dbg and n > PV.LINES_MAX then
		self:log("PROV", { { "town", t }, { "name", E.name(t) }, { "more", n - PV.LINES_MAX }, { "seq", s.builds or 0 } })
	end
	if #entries > 0 and E.sendEvent then E.sendEvent(SV.EVENT_ID, SV.EV_PROV, { town = t, add = entries }) end
end

---------------------------------------------------------------------------
-- fill (NEXT_PHASE_BRIEF 13): DevelopAt beside a build's new streets, one command at a time

--- After a successful build: plans the fill (D.fillKind / D.fillPoints), logs FILL (before any command, as
--- every build) and moves the job to stage "fill". Returns true when a fill starts; a skipped fill logs why
--- (debug).
function Driver:fillStart(job, now)
	local E, t = self.E, job.town
	if E.developAt == nil or job.spec == nil then return false end
	local s = self:townState(t)
	local caps = job.caps
	-- the brake's base: the initial capacity at the town's first build (saved frame), else the first seen
	if s.baseInitial == nil then
		local fr = SV.frame(self.saved, t)
		s.baseInitial = (fr and fr.initial) or (caps and caps.initial) or nil
	end
	local kind, why = D.fillKind(job, self.opts, caps, s.fill, job.pts and #job.pts or 0, now, s.baseInitial)
	if kind == nil then
		if why ~= "off" and why ~= "unshaped" then self:debug("FILL", { { "town", t }, { "skip", why },
			{ "initial", caps and caps.initial and string.format("%.0f/%.0f", caps.initial, s.baseInitial or 0) or "?" } }) end
		return false
	end
	local sh = job.style and job.style.shape
	local env = D.envLevel(job.report)
	local pts = D.fillPoints(kind, job.spec.edges, sh, env, job.sampler, job.style)
	-- (a lane ahead's far end: its own points, ot_lead.endFillPoints)
	if job.fillPts then pts = job.fillPts end
	-- (industry keep-clear zones, 2026-10-13: never a dose point in one, whatever else the build has)
	local ind = job.style and job.style.industry
	if ind and ind.zones and #ind.zones > 0 then
		local keep = {}
		for _, p in ipairs(pts) do
			if IND.inZone(ind, p[1], p[2], IND.ZONE_LOT) == nil then keep[#keep + 1] = p end
		end
		if #keep < #pts then self:debug("FILL", { { "town", t }, { "kind", kind }, { "zoneDropped", #pts - #keep } }) end
		pts = keep
	end
	if #pts == 0 then
		self:debug("FILL", { { "town", t }, { "kind", kind }, { "skip", "noStreet" } })
		return false
	end
	local rec = { us = now, kind = kind, buildings0 = job.pts and #job.pts or 0, cap0 = caps and caps.actual or 0,
		target0 = caps and caps.target or 0, initial0 = caps and caps.initial or nil,
		initials0 = caps and caps.initials and { caps.initials[1], caps.initials[2], caps.initials[3] } or nil, sf0 = caps and caps.sizeFactors and { caps.sizeFactors[1], caps.sizeFactors[2],
		caps.sizeFactors[3] } or nil, points = {}, streets = job.fillStreets == true, upgrade = job.fillUpgrade == true,
		active0 = caps and caps.active }
	-- (FILL reactivate, 2026-10-13: remembered per session whether the town's development was on before our first fill;
	-- a town a player switched off stays off)
	if s.devBefore == nil and caps and caps.active ~= nil then s.devBefore = caps.active end
	local near, far = 0, 0
	for i, p in ipairs(pts) do
		local n0, f0 = D.countNear(job.pts, p[1], p[2], D.FILL_NEAR), D.countNear(job.pts, p[1], p[2], D.FILL_FAR)
		rec.points[i] = { p[1], p[2], n0, f0 }
		near, far = near + n0, far + f0
	end
	s.fill = rec
	s.fills = (s.fills or 0) + 1
	self.counts.fills = (self.counts.fills or 0) + #pts
	local ptxt = {}
	for i, p in ipairs(pts) do if i <= 4 then ptxt[#ptxt + 1] = string.format("%.0f:%.0f", p[1], p[2]) end end
	self:log("FILL", { { "town", t }, { "name", E.name(t) }, { "kind", kind }, { "why", why }, { "points", #pts },
		{ "edges", #job.spec.edges }, { "streets", rec.streets }, { "upgrade", rec.upgrade },
		{ "cap", caps and string.format("%.0f/%.0f", rec.cap0, rec.target0) or "?" },
		{ "initial", rec.initial0 and string.format("%.0f/%.0f", rec.initial0, s.baseInitial or 0) or "?" },
		{ "buildings", rec.buildings0 },
		{ "near", near }, { "far", far }, { "at", table.concat(ptxt, "/") }, { "fills", s.fills } })
	job.fillRun = { pts = pts, i = 0, ok = 0, rec = rec }
	job.stage = "fill"
	return true
end

---------------------------------------------------------------------------
-- tree-lined entries (ot_entry, later-ideas phase 2026-10-13)

--- Marks the increment's tree-lined entry edges (EN.mark) unless the trees are off for the session; logs ENTRY once per
--- town (whether it lines its entries, its roads).
function Driver:entryMark(job, inc)
	inc.trees = nil
	if not EN.ON or self.treesOff then return end
	local s = self:townState(job.town)
	local E = self.E
	local okFn = E.templateExists and function(path) return E.templateExists(path) end or nil
	local n = EN.mark(inc, job.style, okFn)
	if not s.entryLogged then
		s.entryLogged = true
		local on, p = EN.on(job.style)
		self:log("ENTRY", { { "town", job.town }, { "name", E.name(job.town) }, { "on", on }, { "p", string.format("%.2f", p) },
			{ "roads", RDS.text(job.style.roads) } })
	end
	return n
end

--- R5: MOTIF event=fallback lines for the motif fallbacks of this plan (ot_motif.fallback; once per town, from, to).
function Driver:motifFallbackLines(job)
	local list = job.style and job.style._motifFallbacks
	if list == nil or #list == 0 then return end
	job.style._motifFallbacks = nil
	local s = self:townState(job.town)
	s.motifFb = s.motifFb or {}
	for _, f in ipairs(list) do
		local key = f.from .. ">" .. f.to
		if not s.motifFb[key] then
			s.motifFb[key] = true
			self:debug("MOTIF", { { "town", job.town }, { "name", self.E.name(job.town) }, { "event", "fallback" },
				{ "from", f.from }, { "why", f.why }, { "to", f.to }, { "ok", f.ok }, { "toWhy", f.toWhy or "-" } })
		end
	end
end

---------------------------------------------------------------------------
-- forest lanes (ot_lane, round R2 2026-10-13)

--- Marks the increment's forest lanes (LN.mark) unless they are off for the session; a FORESTLANE line per lane
--- (`town= edge= len= why=`; debug: the skipped ones with `skip=draw|cap|template`).
function Driver:laneMark(job, inc, report)
	inc.lanes = nil
	if not LN.ON or (self.lanesOff and job.forestLane ~= "force") or job.bridgePlan or job.satPlan or job.framePlan then return 0 end
	local s = self:townState(job.town)
	local E = self.E
	local okFn = E.templateExists and function(path) return E.templateExists(path) end or nil
	local marked, skipped = LN.mark(inc, job.style, { seed = job.style.seed, used = s.lanes or 0, max = LN.MAX_PER_TOWN, ok = okFn,
		force = job.forestLane == "force", freed = report and report.laneFree or nil })
	-- (round after the names run: why the increment's wooded edges made no lane; debug, only when some were wooded)
	local st = inc.laneStats
	if st and st.wooded > 0 then
		self:debug("FORESTLANE", { { "town", job.town }, { "check", true }, { "wooded", st.wooded }, { "joined", st.joined },
			{ "line", st.line }, { "lineKey", st.lineKey or "-" }, { "tip", st.tip }, { "short", st.short }, { "long", st.long },
			{ "runs", st.runs },
			{ "freed", report and report.laneFreed or 0 }, { "marked", #marked }, { "skipped", #skipped } })
	end
	for _, r in ipairs(marked) do
		self:log("FORESTLANE", { { "town", job.town }, { "name", E.name(job.town) }, { "edge", tostring(inc.edges[r.first].key) },
			{ "edges", #r.edges }, { "len", string.format("%.0f", r.len) }, { "why", r.why }, { "template", r.template:match("([%w_]+)%.street_template$") or r.template } })
	end
	for _, r in ipairs(skipped) do
		self:debug("FORESTLANE", { { "town", job.town }, { "edge", tostring(inc.edges[r.first].key) }, { "len", string.format("%.0f", r.len) },
			{ "why", r.why }, { "skip", r.skip } })
	end
	return inc.lanes or 0
end

--- After a build with forest lanes: counts them per town (LN.MAX_PER_TOWN), FORESTLANE outcome=built.
function Driver:laneBuilt(job)
	local s = self:townState(job.town)
	local n = 0
	for _, e in ipairs(job.spec and job.spec.edges or {}) do if e.forestLane then n = n + 1 end end
	if n == 0 then return end
	s.lanes = (s.lanes or 0) + (job.inc.laneRuns or 1)
	self.counts.lanes = (self.counts.lanes or 0) + 1
	self:log("FORESTLANE", { { "town", job.town }, { "name", self.E.name(job.town) }, { "outcome", "built" }, { "edges", n },
		{ "town_total", s.lanes } })
end

--- Dev ALLTOWN `later=` (later-ideas phase): "ups=<n>,pb=<persons per building>,meadow=on|-,frames=<n>,trees=<n>" from
--- the main driver's town state s (may be nil), its style st and a measure m ({ buildings, caps }).
function D.laterText(s, st, m)
	local pb = m and m.caps and UP.perBuilding(m.caps.actual, m.buildings) or nil
	return string.format("ups=%d,pb=%s,meadow=%s,frames=%d,trees=%d", s and s.ups or 0, pb and string.format("%.2f", pb) or "?",
		(st and st.meadows) and "on" or "-", s and s.frames or 0, s and s.trees or 0)
end

--- PLAN `trees=` (tree-lined entry edges of the increment), "-" without.
function D.treesText(inc)
	return inc and inc.trees and tostring(inc.trees) or "-"
end

--- After a build with tree-lined entry edges: counts them per town and session, ENTRY outcome=built.
function Driver:entryBuilt(job)
	local s = self:townState(job.town)
	local n = 0
	for _, e in ipairs(job.spec and job.spec.edges or {}) do if e.decor == "template" then n = n + 1 end end
	if n == 0 then return end
	s.trees = (s.trees or 0) + n
	self.counts.trees = (self.counts.trees or 0) + n
	self:log("ENTRY", { { "town", job.town }, { "name", self.E.name(job.town) }, { "outcome", "built" }, { "edges", n },
		{ "town_total", s.trees }, { "fallback", type(self.E.treesFallback) == "number" and self.E.treesFallback or 0 } })
end

---------------------------------------------------------------------------
-- upward density (ot_upward, later-ideas phase 2026-10-13): big towns grow taller in their core instead of outward

--- Snapshot stage: is the town an upward town (UP.decide without the gap / surge)? Sets job.upward = { why, cut, due,
--- skip, asked } and cuts a demand build's maxEdges by the cut (never below DEMAND_MIN_INC).
function Driver:upwardDecide(job, style, now)
	job.upward = nil
	if not UP.ON or job.dry then return end
	local s = self:townState(job.town)
	local caps = job.caps
	if s.baseInitial == nil then
		local fr = SV.frame(self.saved, job.town)
		s.baseInitial = (fr and fr.initial) or (caps and caps.initial) or nil
	end
	local last = s.fill
	local surge = last ~= nil and last.buildings0 ~= nil and last.us ~= nil and now - last.us < D.surgeWindowS(job.town) * 1e6
		and (job.pts and #job.pts or 0) > last.buildings0 * (1 + D.FILL_SURGE)
	local why, skip, whyAnyway = UP.decide({ buildings = job.pts and #job.pts or 0, metro = style.metro ~= nil,
		pressure = s.upPressure, forced = job.force, head = job.head, last = s.up, nowUs = now, town = job.town,
		initial = caps and caps.initial, base = s.baseInitial, surge = surge, persons = caps and caps.actual,
		-- (§66: a town that leans commercial by deliveries doses its core as a densify town does: a denser centre)
		densify = self:densifyActive(job.town) or self:rciLean(job.town) == "com", dzMin = CH.DZ_UP_BUILDINGS })
	local kind = why or whyAnyway
	-- (a skip reason is logged when it changes, not every check)
	if skip ~= s.upSkip then
		s.upSkip = skip
		if skip ~= nil and skip ~= "small" and skip ~= "off" and skip ~= "forced" then
			self:debug("UPWARD", { { "town", job.town }, { "skip", skip }, { "kind", kind or "-" } })
		end
	end
	if kind == nil then return end
	local cut = UP.cut(job.pts and #job.pts or 0, kind)
	job.upward = { why = kind, cut = cut, due = why ~= nil, skip = skip, asked = job.maxEdges }
	if cut > 0 and job.trigger == "demand" and job.maxEdgesOverride == nil and job.maxEdges then
		job.maxEdges = math.max(D.DEMAND_MIN_INC, math.floor(job.maxEdges * (1 - cut) + 0.5))
	end
end

-- (dev ALLTOWN, 2026-10-14 late) the level text of a town (E.levelInfo) and the industries it encloses
function D.levelText(info) return UP.levelText(info) end
function D.industryEnclosure(all, cx, cy, r, pts, segs) return IND.enclosure(all, cx, cy, r, pts, segs) end

--- MATURE line (2026-10-14, ot_assess MATURE_*): logged when a grown town's mature hold or cap starts or ends (`event=hold`
--- the demand builds wait while its free lots are over the line; `cap` demK capped; `off` neither), with its maturity,
--- free share, the hold line and demK. Once per change per town (a world-level decision, so a log line, not debug).
function Driver:matureLog(t, m)
	local dem = m and m.dem
	if dem == nil or dem.mat == nil or dem.mat <= 0 then return end
	local ev = (m.why == "mature") and "hold" or (dem.matureCap ~= nil and "cap" or "off")
	local s = self:townState(t)
	if s.matureEv == ev or (s.matureEv == nil and ev == "off") then return end
	s.matureEv = ev
	local line = A.matureHoldLine(dem.mat)
	self:log("MATURE", { { "town", t }, { "name", self.E.name(t) }, { "event", ev },
		{ "mat", string.format("%.2f", dem.mat) }, { "free", string.format("%.2f", dem.freeShare or 0) },
		{ "line", line and string.format("%.2f", line) or "-" }, { "demK", string.format("%.2f", dem.demK or 1) },
		{ "demand", string.format("%.1f", dem.edges or 0) }, { "buildings", m.buildings },
		{ "pb", (m.caps and (m.buildings or 0) > 0) and string.format("%.2f", m.caps.actual / m.buildings) or "?" } })
end

--- The level baseline (2026-10-14, run 2026-10-14_0502_sqot: every generated town carried custom level weights
--- `c:0.26/0.11/0/0` the mod never sent, so LEVELS read them as the player's and never ran). On a new map whose save has
--- no baseline yet and whose clock is still under SV.FRESH_GAME_TIME (the mod's first sight), every town's current
--- weights are the engine's baseline: kept in self.lvBase and saved (EV_LEVELBASE `lb`). A saved baseline is read back
--- at later loads. No baseline (an old save, or a map first seen by an older build): self.lvBase stays nil and any
--- custom weights count as the player's, as before. Then the probe (LEVELS read, every town).
function Driver:levelBaseStart(saved)
	local E = self.E
	self.lvBase = nil
	if not UP.LEVELS or E.levelInfo == nil or self.newMap ~= true then return end
	local have = SV.levelBase(saved)
	if have ~= nil then
		self.lvBase = have
		local n = 0
		for _ in pairs(have) do n = n + 1 end
		self:log("LEVELS", { { "event", "base" }, { "from", "save" }, { "towns", n } })
	elseif (tonumber(E.gameTime and E.gameTime()) or 0) < SV.FRESH_GAME_TIME then
		local base, list, custom = {}, {}, 0
		for _, t in ipairs(E.towns and E.towns() or {}) do
			local okI, inf = pcall(E.levelInfo, t)
			if okI and inf ~= nil then
				local sig = UP.levelSig(inf.custom)
				base[t] = sig
				if sig ~= "-" then custom = custom + 1 end
				if #list < SV.LEVELBASE_MAX then list[#list + 1] = { t = t, c = sig } end
			end
		end
		self.lvBase = base
		if E.sendEvent then E.sendEvent(SV.EVENT_ID, SV.EV_LEVELBASE, { towns = list }) end
		self:log("LEVELS", { { "event", "base" }, { "from", "firstSight" }, { "towns", #list }, { "custom", custom } })
	else
		self:log("LEVELS", { { "event", "base" }, { "from", "none" }, { "why", "noBaseline" } })
	end
end

D.LEVELS_PROBE_MAX = 64    -- towns per LEVELS read dump

--- The level-weight probe (2026-10-14): when does the engine set a town's custom weights? `LEVELS read at=<when>
--- towns= custom= changed=` and per town `LEVELS read town= name= custom=<sig> base=<sig> at=` (all = true: every
--- town, the load; else only towns whose weights changed since the last probe). The dev Simulate calls it per round
--- and chunk (H.main:levelsProbe("year=N")). Returns the number of changed towns.
function Driver:levelsProbe(at, all)
	local E = self.E
	if E.levelInfo == nil or E.towns == nil then return 0 end
	self.lvSeen = self.lvSeen or {}
	local n, custom, changed, shown = 0, 0, 0, 0
	for _, t in ipairs(E.towns() or {}) do
		local okI, inf = pcall(E.levelInfo, t)
		if okI and inf ~= nil then
			n = n + 1
			local sig = UP.levelSig(inf.custom)
			if sig ~= "-" then custom = custom + 1 end
			local was = self.lvSeen[t]
			local ch = was ~= nil and was ~= sig
			if ch then changed = changed + 1 end
			self.lvSeen[t] = sig
			if (all or ch) and shown < D.LEVELS_PROBE_MAX then
				shown = shown + 1
				self:log("LEVELS read", { { "town", t }, { "name", E.name(t) }, { "custom", sig },
					{ "base", self.lvBase and (self.lvBase[t] or "?") or "none" }, { "was", ch and was or "=" }, { "at", at } })
			end
		end
	end
	self:log("LEVELS read", { { "at", at }, { "towns", n }, { "custom", custom }, { "changed", changed } })
	return changed
end

D.LEVELS_TIMEOUT_S = 30   -- a level-weight command whose callback never came: the town may try again after this

--- "a/b/c/d" of a weight set's first land use (LEVELS from= / to=), "-" for none.
local function lvRow(rows)
	if type(rows) ~= "table" or type(rows[1]) ~= "table" then return "-" end
	local r = rows[1]
	return string.format("%g/%g/%g/%g", math.floor((r[1] or 0) * 1000 + 0.5) / 1000, math.floor((r[2] or 0) * 1000 + 0.5) / 1000,
		math.floor((r[3] or 0) * 1000 + 0.5) / 1000, math.floor((r[4] or 0) * 1000 + 0.5) / 1000)
end
D.lvRow = lvRow

--- The engine baseline of the level weights (root driver's: the dev tools' pool drivers have none of their own; run
--- 2026-10-14_2347_sqot-dev: their checks read every town without a baseline).
function Driver:levelBaseOf()
	return self.lvBase or self:root().lvBase
end

--- The tilt and sig of the level weights the mod last sent to town t (session, else the saved frame `lw` / `ls`).
function Driver:levelOurs(t)
	local s = self:townState(t)
	if s.lvK ~= nil then return s.lvK, s.lvSent end
	local fr = SV.frame(self:savedNow(nil), t)
	return (fr and fr.levels) or 0, fr and fr.levelSig or nil
end

--- Level weights (2026-10-14 late; by maturity 2026-10-15, NEXT_PHASE_BRIEF 58, ot_upward.levelDecide / levelPhase):
--- at a town's check on a new map, the town's phase from its level maturity (young: nothing; blend: a tilt toward
--- level 1 easing back to the engine's weights; mature: the engine's weights or above them; densify: above them,
--- ramping in) gives the weights (makeTownCustomDistributionWeightsCmd; the capacity and the target stay the game's),
--- up to the era's top level. A player's own weights are never touched; the engine's fill weights (owner "fill", the
--- write after the mod's FILL restore) may be replaced from the blend on. Saved on the frame (EV_LEVELS `lw` tilt x 4,
--- `ls` sig). LEVELS line per change (always, a world change: phase, tilt from -> to, weights from -> to); skips debug,
--- once per reason. Fire and forget like FILL reactivate: no command slot.
function Driver:levelsCheck(t, m, now)
	local E = self.E
	if not UP.LEVELS or E.setLevelWeights == nil or E.levelInfo == nil or m == nil or m.caps == nil then return end
	local s = self:townState(t)
	if s.lvPending and now - (s.lvUs or 0) < D.LEVELS_TIMEOUT_S * 1e6 then return end
	s.lvPending = false
	local ours, sentSig = self:levelOurs(t)
	local info = nil
	local pb = (m.buildings or 0) > 0 and (m.caps.actual or 0) / m.buildings or nil
	local mat = m.dem and m.dem.mat or nil
	local matL = UP.levelMat(mat, m.buildings)
	-- (the read only when something could happen: the cheap rules first)
	-- (deep forest towns stay low, 2026-10-14: no level weights, UP.levelDecide deep)
	local deepT = self:isDeepTown(t)
	local owner = nil
	-- (strong characters / densify, ot_character 2026-10-14: early levels for the dense kinds, none for the garden city, the
	-- densify town's higher aim)
	local charLv, dz = CH.levels(self:charKindOf(t)), self:densifyDrawn(t)
	local top = UP.eraTop(E.year and E.year() or nil)
	local act, k, why, phase = UP.levelDecide({ buildings = m.buildings, pb = pb, mat = mat, custom = false, ours = ours,
		on = self.newMap == true, last = s.lvUs, nowUs = now, town = t, deep = deepT, char = charLv, densify = dz, top = top })
	if phase ~= nil then s.lvPhase = phase end
	if act ~= nil then
		local okI, inf = pcall(E.levelInfo, t)
		info = okI and inf or nil
		-- (whose weights, 2026-10-14: the engine's baseline taken at the first sight of the new map, ours, the player's,
		-- or the engine's write after a FILL restore, 2026-10-15)
		local lb = self:levelBaseOf()
		local base = lb and (lb[t] or "-") or nil
		owner = info ~= nil and UP.levelOwner(UP.levelSig(info.custom), base, ours, info.custom, sentSig) or nil
		act, k, why, phase = UP.levelDecide({ buildings = m.buildings, pb = pb, mat = mat, custom = info ~= nil and info.custom ~= nil,
			owner = owner, ours = ours, on = self.newMap == true, last = s.lvUs, nowUs = now, town = t, deep = deepT,
			char = charLv, densify = dz, top = top, u = info and info.unweighted and info.unweighted[1] or nil,
			w = info and info.weighted and info.weighted[1] or nil })
		if phase ~= nil then s.lvPhase = phase end
		-- (no read: whether a player set the town's weights is unknown, so nothing is sent)
		if info == nil then act, why = nil, "noRead" end
	end
	if act == nil then
		if why ~= s.lvWhy then
			s.lvWhy = why
			if why ~= "small" and why ~= "gap" and why ~= "notNew" and why ~= "off" then
				self:debug("LEVELS", { { "town", t }, { "skip", why }, { "phase", phase or "-" },
					{ "pb", pb and string.format("%.2f", pb) or "?" }, { "matL", string.format("%.2f", matL) },
					{ "ours", ours }, { "owner", owner or "-" } })
			end
		end
		return
	end
	s.lvWhy = nil
	s.lvUs, s.lvPending = now, true
	-- (a clear returns the town to its engine baseline when it had one, else to the game's default)
	local lb = self:levelBaseOf()
	local baseRows = lb and UP.levelUnsig(lb[t]) or nil
	local w = act == "set" and UP.levelWeights(k, top) or baseRows
	local sig = UP.levelSig(w)
	self:log("LEVELS", { { "town", t }, { "name", E.name(t) }, { "action", act }, { "phase", phase or "-" }, { "why", why },
		{ "owner", owner or "-" }, { "buildings", m.buildings }, { "pb", pb and string.format("%.2f", pb) or "?" },
		{ "mat", mat and string.format("%.2f", mat) or "-" }, { "matL", string.format("%.2f", matL) },
		{ "tilt", string.format("%g->%g", ours or 0, act == "set" and k or 0) }, { "era", top },
		{ "from", lvRow(info and info.custom) }, { "to", w and lvRow(w) or "default" }, { "base", act == "clear" and baseRows ~= nil },
		{ "lvl", UP.levelText(info) } })
	E.setLevelWeights(t, w, function(ok)
		s.lvPending = false
		if ok then
			s.lvK = act == "set" and k or 0
			s.lvSent = act == "set" and sig or nil
			if E.sendEvent then
				E.sendEvent(SV.EVENT_ID, SV.EV_LEVELS, { town = t, k4 = math.floor(s.lvK * 4 + 0.5), sig = s.lvSent })
			end
		else
			self:log("LEVELS", { { "town", t }, { "action", act }, { "ok", false } })
		end
	end)
end

--- After a FILL restore (2026-10-15, NEXT_PHASE_BRIEF 58): the engine rewrites the town's level weights in step with
--- makeTownSetInitialLandUseCapacitiesCmd (run 2026-10-14_2347_sqot-dev: every custom weight appeared or changed after
--- one; inferred). A town whose weights the mod manages (sent this session or saved, past the young phase) gets them
--- back at once: `LEVELS event=refill`. A young town keeps the engine's (the young hold, as before); a player's are
--- never touched (the mod only re-sends its own, and only when the current ones are not the player's).
function Driver:levelsAfterRestore(t)
	local E = self.E
	if not UP.LEVELS or E.setLevelWeights == nil or E.levelInfo == nil or self.newMap ~= true then return end
	local s = self:townState(t)
	if s.lvPhase == nil or s.lvPhase == "young" or s.lvPending or s.lvRefill then return end
	local ours, sentSig = self:levelOurs(t)
	if ours == 0 or sentSig == nil then return end
	local okI, info = pcall(E.levelInfo, t)
	if not okI or info == nil then return end
	local cur = UP.levelSig(info.custom)
	if cur == sentSig then return end
	-- (the town editor's kind of weights: the player's now, left alone)
	if info.custom ~= nil and UP.editorLike(info.custom) then return end
	local w = UP.levelUnsig(sentSig)
	if w == nil then return end
	s.lvRefill = true
	s.refills = (s.refills or 0) + 1
	self:log("LEVELS", { { "town", t }, { "name", E.name(t) }, { "event", "refill" }, { "phase", s.lvPhase },
		{ "tilt", ours }, { "from", lvRow(info.custom) }, { "to", lvRow(w) }, { "n", s.refills } })
	E.setLevelWeights(t, w, function(ok)
		s.lvRefill = false
		if not ok then self:log("LEVELS", { { "town", t }, { "event", "refill" }, { "ok", false } }) end
	end)
end

--- The straight-run guard (2026-10-14 late, ot_check.straightRuns): the edges of a straight run of new town streets
--- ahead of the houses beyond CK.STRAIGHT_MAX (from the end at the town) leave the increment (ot_plan.dropEdges, with
--- whatever hung only on them). Returns the PLAN `straight=` text "<longest run m>/<edges dropped>" ("0/0" none).
function Driver:straightGuard(job, inc)
	if not D.STRAIGHT_GUARD then return "-" end
	local okR, rep = pcall(CK.straightRuns, inc, job.pts)
	if not okR or rep == nil then return "err" end
	local drop, n = {}, 0
	for _, run in ipairs(rep.runs) do
		for _, i in ipairs(run.drop) do
			if not drop[i] then drop[i] = true; n = n + 1 end
		end
	end
	local removed = 0
	if n > 0 then
		local _, r = PL.dropEdges(inc, drop)
		removed = r
		inc.mix = core.mix(inc)
		local trees, lanes = 0, 0
		for _, e in ipairs(inc.edges) do
			if e.trees then trees = trees + 1 end
			if e.forestLane then lanes = lanes + 1 end
		end
		inc.trees = trees > 0 and trees or nil
		inc.lanes = lanes > 0 and lanes or nil
		self.counts.straightCut = (self.counts.straightCut or 0) + removed
	end
	return string.format("%.0f/%d", rep.max, removed)
end
D.STRAIGHT_GUARD = true

--- After a build (outcome "built") or an empty plan ("empty") of an upward town (any trigger but the head start) whose dose is due: the
--- core points (UP.points) get makeTownDevelopAtCmd(point, false, true), then the initial capacities go back exactly
--- (fillRestore, UP.EXTRA 0). Logs UPWARD. Returns true when the dose started (stage "fill"; the job then finishes with
--- `outcome`).
function Driver:upwardStart(job, now, outcome)
	local u = job.upward
	if u == nil or not u.due or job.trigger == "head" or job.head or job.force then return false end
	-- (the dev Simulate's build rounds, 2026-10-14: its Fast fill covers the upward dose too)
	if H.simNoFills then
		self:debug("UPWARD", { { "town", job.town }, { "skip", "sim" } })
		return false
	end
	local E, t = self.E, job.town
	if E.developAt == nil or E.setInitialCaps == nil or job.g == nil then return false end
	local s = self:townState(t)
	local caps = job.caps
	if caps == nil or caps.initials == nil then return false end
	local ext = job.ext or {}
	local c = (job.style and job.style.centre) or { ext.cx or 0, ext.cy or 0 }
	local coreR = UP.coreR(ext.r)
	local ind = job.style and job.style.industry
	local pts = UP.points(job.g, job.pts, c, coreR, { recent = s.upRecent,
		skip = (ind and IND.FILL_AVOID) and function(x, y) return IND.inBuffer(ind, x, y) end or nil })
	s.up = { us = now }   -- (the gap runs from this try on, also without points)
	if #pts == 0 then
		self:debug("UPWARD", { { "town", t }, { "skip", "noPoint" }, { "coreR", math.floor(coreR) } })
		return false
	end
	s.upRecent = UP.remember(s.upRecent, pts)
	local nb = job.pts and #job.pts or 0
	local rec = { us = now, kind = "upward", buildings0 = nb, cap0 = caps.actual or 0, target0 = caps.target or 0,
		initial0 = caps.initial, initials0 = { caps.initials[1], caps.initials[2], caps.initials[3] },
		sf0 = caps.sizeFactors and { caps.sizeFactors[1], caps.sizeFactors[2], caps.sizeFactors[3] } or nil, points = {},
		streets = false, upgrade = true, active0 = caps.active }
	if s.devBefore == nil and caps.active ~= nil then s.devBefore = caps.active end
	local near, ptxt, classes = 0, {}, {}
	for i, p in ipairs(pts) do
		rec.points[i] = { p[1], p[2], p.n }
		near = near + p.n
		ptxt[#ptxt + 1] = string.format("%.0f:%.0f", p[1], p[2])
		classes[p.class] = (classes[p.class] or 0) + 1
	end
	s.up = { us = now, rec = rec, perB0 = UP.perBuilding(caps.actual, nb) }
	s.ups = (s.ups or 0) + 1
	s.fills = (s.fills or 0) + 1   -- (FILL reactivate: a DevelopAt of ours may switch the town's development off)
	self.counts.ups = (self.counts.ups or 0) + 1
	self:log("UPWARD", { { "town", t }, { "name", E.name(t) }, { "why", u.why }, { "after", outcome }, { "buildings", nb },
		{ "cut", string.format("%.2f", u.cut) }, { "asked", u.asked or "-" }, { "edges", job.spec and #job.spec.edges or 0 },
		{ "coreR", math.floor(coreR) }, { "points", #pts }, { "main", classes.main or 0 }, { "medium", classes.medium or 0 },
		{ "near", near }, { "at", table.concat(ptxt, "/") },
		{ "cap", string.format("%.0f/%.0f", rec.cap0, rec.target0) },
		{ "perBuilding", s.up.perB0 and string.format("%.2f", s.up.perB0) or "?" },
		{ "initial", string.format("%.0f/%.0f", rec.initial0 or 0, s.baseInitial or 0) }, { "pressure", s.upPressure or 0 },
		{ "n", s.ups } })
	job.fillRun = { pts = pts, i = 0, ok = 0, rec = rec, outcome = outcome }
	job.stage = "fill"
	return true
end

--- UPWARD effect at the town's first check after an upward dose: buildings near the points, the whole town's buildings
--- and person capacity per building before -> now (does upgradeBuildings raise the core?), initial capacity sum.
function Driver:upwardEffect(t, m, now)
	local s = self.towns[t]
	local u = s and s.up
	if u == nil or u.rec == nil or u.reported or m == nil then return end
	u.reported = true
	local r = u.rec
	local n0, n1 = 0, 0
	for _, p in ipairs(r.points) do
		n0 = n0 + (p[3] or 0)
		n1 = n1 + D.countNear(m.pts, p[1], p[2], UP.NEAR)
	end
	local caps = m.caps
	local perB1 = UP.perBuilding(caps and caps.actual, m.buildings)
	self:log("UPWARD effect", { { "town", t }, { "s", string.format("%.0f", (now - r.us) / 1e6) }, { "points", #r.points },
		{ "near", string.format("%d->%d", n0, n1) }, { "buildings", string.format("%d->%d", r.buildings0, m.buildings) },
		{ "cap", string.format("%.0f->%.0f", r.cap0, caps and caps.actual or 0) },
		{ "perBuilding", string.format("%s->%s", u.perB0 and string.format("%.2f", u.perB0) or "?",
			perB1 and string.format("%.2f", perB1) or "?") },
		{ "initial", string.format("%.0f->%s", r.initial0 or 0, caps and caps.initial and string.format("%.0f", caps.initial) or "?") },
		{ "target", string.format("%.0f->%s", r.target0 or 0, caps and caps.target and string.format("%.0f", caps.target) or "?") },
		{ "active", string.format("%s->%s", tostring(r.active0), tostring(caps and caps.active)) } })
	self:reactivate(t, caps, "check")
end

--- Stage "fill": the build's DevelopAt calls (all at once with FILL_CONCURRENT, else one in flight); when all are
--- answered (or timed out) the initial capacities are restored (dose, metropolis) and the job finishes as "built".
function Driver:fill(job, now)
	local f = job.fillRun
	if D.FILL_CONCURRENT and not f.restoring then
		if not f.sent then
			-- (Showcase v8 round: a metropolis's 12 calls one after another took ~5 s of a showcase round; the engine
			-- runs queued commands in order, so sending them back to back changes nothing but the wait)
			f.sent, f.sentUs, f.answers = true, now, {}
			self.inflight = true
			for i, p in ipairs(f.pts) do
				self.E.developAt(p[1], p[2], f.rec.streets, f.rec.upgrade, function(ok) f.answers[i] = ok == true end)
			end
			return
		end
		local n, okN = 0, 0
		for i = 1, #f.pts do
			if f.answers[i] ~= nil then
				n = n + 1
				if f.answers[i] then okN = okN + 1 end
			end
		end
		if n < #f.pts and now - f.sentUs <= D.FILL_TIMEOUT_S * 1e6 then return end
		f.ok, f.timeouts = okN, #f.pts - n
		self.inflight = false
		if self:fillRestore(job, now) then return end
		self:debug("FILL", { { "town", job.town }, { "kind", f.rec.kind }, { "sent", #f.pts }, { "ok", f.ok },
			{ "timeouts", f.timeouts }, { "concurrent", true } })
		self:reactivate(job.town, self.E.townCaps(job.town), "develop")
		return self:finish(job.town, f.outcome or "built", now)
	end
	if f.pending then
		if f.answered == nil then
			if now - f.sentUs <= D.FILL_TIMEOUT_S * 1e6 then return end
			f.timeouts = (f.timeouts or 0) + 1
		elseif f.answered then
			f.ok = f.ok + 1
		end
		f.pending = false
		self.inflight = false
	end
	if f.restoring then
		if f.restored == nil and now - f.restoreUs <= D.FILL_TIMEOUT_S * 1e6 then return end
		self.inflight = false
		local c1 = self.E.townCaps(job.town)
		self:debug("FILL", { { "town", job.town }, { "kind", f.rec.kind }, { "sent", #f.pts }, { "ok", f.ok },
			{ "timeouts", f.timeouts or 0 }, { "restored", f.restored == true },
			{ "active", string.format("%s->develop:%s->restore:%s", tostring(f.rec.active0), tostring(f.activeDev),
				tostring(c1 and c1.active)) } })
		self:reactivate(job.town, c1, f.activeDev == false and "develop" or "restore")
		return self:finish(job.town, f.outcome or "built", now)
	end
	f.i = f.i + 1
	local p = f.pts[f.i]
	if p == nil then
		if self:fillRestore(job, now) then return end
		self:debug("FILL", { { "town", job.town }, { "kind", f.rec.kind }, { "sent", #f.pts }, { "ok", f.ok },
			{ "timeouts", f.timeouts or 0 } })
		self:reactivate(job.town, self.E.townCaps(job.town), "develop")
		return self:finish(job.town, f.outcome or "built", now)
	end
	f.pending, f.answered, f.sentUs = true, nil, now
	self.inflight = true
	self.E.developAt(p[1], p[2], f.rec.streets, f.rec.upgrade, function(ok) f.answered = ok == true end)
end

--- The initial capacities a dose may leave: per land use min(now, before x r), r = min(1 + FILL_EXTRA, FILL_CAP x
--- base / sum before), never below before. Returns the list, or nil when nothing is above it. before / now = {3}.
function D.restoreCaps(before, now, base, extra, capF)
	if before == nil or now == nil then return nil end
	local sum = (before[1] or 0) + (before[2] or 0) + (before[3] or 0)
	if sum <= 0 then return nil end
	local r = 1 + (extra or D.FILL_EXTRA)
	if base ~= nil and base > 0 then r = math.min(r, (capF or D.FILL_CAP) * base / sum) end
	r = math.max(r, 1)
	local out, above = {}, false
	for i = 1, 3 do
		local allowed = math.floor((before[i] or 0) * r + 0.5)
		local n = now[i] or 0
		if n > allowed then above = true; out[i] = allowed else out[i] = math.floor(n + 0.5) end
	end
	if not above then return nil end
	return out
end

--- The exact restore of a weighted town (§66): before (rounded) when any land use differs from now, else nil.
function D.restoreExact(before, now)
	if before == nil or now == nil then return nil end
	local out, diff = {}, false
	for i = 1, 3 do
		out[i] = math.floor((tonumber(before[i]) or 0) + 0.5)
		if out[i] < 1 then return nil end
		if math.floor((tonumber(now[i]) or 0) + 0.5) ~= out[i] then diff = true end
	end
	if not diff then return nil end
	return out
end

--- After a dose's DevelopAt calls: puts the town's initial capacities back (D.restoreCaps; FILL restore line, as
--- every world change). Returns true when a command went out (the fill stage waits for it).
function Driver:fillRestore(job, now)
	local E, f = self.E, job.fillRun
	-- (which command switches development off? the town's flag right after the DevelopAt calls, FILL activeAfter)
	local c0 = E.townCaps(job.town)
	f.activeDev = c0 and c0.active
	-- (a metropolis restores too, with its looser brake: ot_metro FILL_EXTRA per fill and no base cap; polycentric
	-- POLY_EXTRA / POLY_CAP. Showcase v7: without it the target ran to 2.6 x the town and the game built its own streets)
	local metro = f.rec.kind == "metro" and job.style and job.style.metro or nil
	local poly = metro ~= nil and metro.variant == "polycentric"
	local upward = f.rec.kind == "upward"
	if (f.rec.kind ~= "dose" and metro == nil and not upward) or E.setInitialCaps == nil or f.rec.initials0 == nil then return false end
	local caps = E.townCaps(job.town)
	local base = self:townState(job.town).baseInitial
	if (metro ~= nil and not poly) or upward then base = nil end
	-- (an upward dose (ot_upward) puts them back exactly: UP.EXTRA 0, the town's target unchanged)
	-- (§66: a town the supply weighting has written gets its weighted values back exactly, the districts DevelopAt
	-- lowered too; otherwise a dose would undo the weighting)
	local keep = self:rciManaged(job.town)
	local list
	if keep then list = caps and D.restoreExact(f.rec.initials0, caps.initials)
	else
		list = caps and D.restoreCaps(f.rec.initials0, caps.initials, base,
			(upward and UP.EXTRA) or (poly and MET.POLY_EXTRA) or (metro and MET.FILL_EXTRA) or nil, poly and MET.POLY_CAP or nil)
	end
	if list == nil then return false end
	self:log("FILL restore", { { "town", job.town }, { "initials", string.format("%s->%s->%s", fmt(f.rec.initials0),
		fmt(caps.initials), fmt(list)) }, { "base", self:townState(job.town).baseInitial or "?" }, { "capsBoost", D.capsBoost() },
		{ "rci", keep and "keep" or "-" } })
	f.restoring, f.restored, f.restoreUs = true, nil, now
	self.inflight = true
	E.setInitialCaps(job.town, list, function(ok)
		f.restored = ok == true
		-- (the engine rewrites the level weights with the capacities: a managed town gets the mod's back, 2026-10-15)
		if ok then
			local okL, errL = pcall(self.levelsAfterRestore, self, job.town)
			if not okL then self:log("WARN", { { "stage", "levelsRestore" }, { "town", job.town }, { "err", errL } }) end
		end
	end)
	return true
end

--- FILL effect (debug) at the town's first check after a fill: buildings near / around the points and in the
--- whole town, person capacity vs target and size factors, before -> now. Where DevelopAt's growth goes.
function Driver:fillEffect(t, m, now)
	local s = self.towns[t]
	local f = s and s.fill
	if f == nil or f.reported or m == nil then return end
	f.reported = true
	local n0, n1, f0, f1 = 0, 0, 0, 0
	for _, p in ipairs(f.points) do
		n0, f0 = n0 + p[3], f0 + p[4]
		n1 = n1 + D.countNear(m.pts, p[1], p[2], D.FILL_NEAR)
		f1 = f1 + D.countNear(m.pts, p[1], p[2], D.FILL_FAR)
	end
	local caps = m.caps
	local sf1 = caps and caps.sizeFactors or nil
	f.buildings1 = m.buildings
	self:debug("FILL effect", { { "town", t }, { "kind", f.kind }, { "s", string.format("%.0f", (now - f.us) / 1e6) },
		{ "points", #f.points }, { "streets", f.streets }, { "upgrade", f.upgrade },
		{ "near", string.format("%d->%d", n0, n1) }, { "far", string.format("%d->%d", f0, f1) },
		{ "buildings", string.format("%d->%d", f.buildings0, m.buildings) },
		{ "cap", string.format("%.0f/%.0f->%.0f/%.0f", f.cap0, f.target0, caps and caps.actual or 0, caps and caps.target or 0) },
		{ "initial", string.format("%s->%s", f.initial0 and string.format("%.0f", f.initial0) or "?",
			caps and caps.initial and string.format("%.0f", caps.initial) or "?") },
		{ "sizeFactors", string.format("%s->%s", f.sf0 and fmt(f.sf0) or "?", sf1 and fmt({ sf1[1], sf1[2], sf1[3] }) or "?") },
		{ "active", string.format("%s->%s", tostring(f.active0), tostring(caps and caps.active)) } })
	self:reactivate(t, caps, "check")
end

--- FILL reactivate (2026-10-13): the dev simulation stopped growing towns after the mod's dose fill, the town's
--- developmentActive was false after it (session 2026-10-13_0137_sqot-dev: Thornaby-on-Tees reactivated once, then
--- every later fill read active=false->false and the town stayed off from year 29 to 40). Which command does it is
--- logged (FILL active=before->develop:x->restore:y). Now: whenever a town whose development was on before the mod's
--- first fill this session (s.devBefore) reads off after one of our fills, it is switched back on (at the fill's end
--- and at the next check), every time, not only after the first fill. A town a player switched off before stays off.
function Driver:reactivate(t, caps, after)
	local s = self.towns[t]
	if s == nil or s.devBefore ~= true or (s.fills or 0) == 0 or caps == nil or caps.active ~= false then return end
	if not self.E.setDevelopmentActive then return end
	s.reactivations = (s.reactivations or 0) + 1
	self:log("FILL reactivate", { { "town", t }, { "name", self.E.name(t) }, { "after", after }, { "n", s.reactivations } })
	self.E.setDevelopmentActive(t, true, function(ok)
		if not ok then self:log("FILL reactivate", { { "town", t }, { "ok", false } }) end
	end)
end

---------------------------------------------------------------------------
-- Supply-driven district weighting, "Town growth: By deliveries" (§66, 2026-10-15; ot_rci, PLAN.md 6.2 "Supply-driven
-- district weighting"). Beside the jobs, one town at a time: at most once per game month (RCI.STEP_YEARS) a town the
-- mod acts on ("Act on": New towns only skips the known towns; the mod's Works / district towns are skipped too) gets
-- its usage read (E.townSupply: the base town_util helpers), smoothed, and its initial capacities re-split
-- (RCI.step) through E.setInitialCaps, the same writer as the FILL restore; a restore after a dose puts the weighted
-- values back exactly (fillRestore `rci=keep`). Never while a job runs (its fill could restore stale values) or a
-- command is in flight. RCI_PER_TICK towns per RCI_TICK_S and RCI_BUDGET_US at most; one command per tick.
-- RCI line per write (always: a world change), debug RCI skip lines once per reason, RCI summary every RCI_LOG_S.
D.RCI_TICK_S = 1
D.RCI_PER_TICK = 4
D.RCI_BUDGET_US = 2000
D.RCI_LOG_S = 600
D.RCI_MAX_TOWNS = 4000     -- towns walked at most (the cursor's list)

--- The setting: By deliveries and Act on not Off (the dev pool drivers share the main driver's opts).
function Driver:rciSetting()
	return RCI.ON and self.opts ~= nil and self.opts.townGrowth == "deliveries" and self.opts.actOn ~= "off"
end

function Driver:rciOn()
	return self.phase == "run" and self:rciSetting()
end

--- The town's lean ("res" | "com" | "ind") from its last weighting read, or nil (setting off, not read, no lean).
function Driver:rciLean(t)
	if not self:rciSetting() then return nil end
	local s = self.towns and self.towns[t]
	return s and s.rci and s.rci.lean or nil
end

--- Has the weighting written this town (this session or saved)? Its FILL restore then keeps the weighted values.
function Driver:rciManaged(t)
	local s = self.towns and self.towns[t]
	if s and s.rci and (s.rci.k or 0) > 0 then return true end
	local r = SV.rci(self:savedNow(nil), t)
	return r ~= nil and (r.k or 0) > 0
end

--- The towns the weighting may touch: Act on (New towns only: not the known ones), not the mod's Works / districts.
function Driver:rciEligible(t, saved, known)
	if known and known[t] then return false, "known" end
	if self:isOffshootTown(t, saved) then return false, "offshoot" end
	return true
end

local function rciRow(v)
	if type(v) ~= "table" then return "-" end
	return string.format("%d,%d,%d", math.floor((tonumber(v[1]) or 0) + 0.5), math.floor((tonumber(v[2]) or 0) + 0.5),
		math.floor((tonumber(v[3]) or 0) + 0.5))
end

--- The dev readout of town t: "r/c/i=40/30/30 aim=.. use=.. lean=.. k=.." or "-".
function Driver:rciText(t)
	local s = self.towns and self.towns[t]
	local r = s and s.rci
	if r == nil then return "-" end
	return string.format("%s:aim=%s:use=%s:lean=%s:k=%d:why=%s", RCI.pct(r.shares), RCI.pct(r.w), RCI.frac(r.e),
		r.lean or "-", r.k or 0, r.why or "-")
end

--- The dev readout of town t from the engine's reads (works with the setting off or the main driver not visible):
--- "40/30/30:use=0.00/0.00/0.90:aim=12/12/76:lean=-" plus the main driver's state (rciText) when it has one.
function D.rciReadout(E, t, main)
	local caps = E and E.townCaps and E.townCaps(t) or nil
	local shares = caps and RCI.shares(caps.initials or {}, caps.sizeFactors or {}) or nil
	local u = (E and E.townSupply) and RCI.usage(E.townSupply(t)) or nil
	local txt = string.format("%s:use=%s:aim=%s:lean=%s", RCI.pct(shares), RCI.frac(u), RCI.pct(RCI.aim(u)),
		RCI.lean(shares) or "-")
	if main and main.rciText then
		local m = main:rciText(t)
		if m ~= "-" then txt = txt .. "|main:" .. m end
	end
	return txt
end

--- One tick of the weighting. Returns true when a command went out.
function Driver:rciTick(now, saved)
	if not self:rciOn() or self.inflight or self.job ~= nil then return false end
	if now < (self.rciNextUs or 0) then return false end
	self.rciNextUs = now + D.RCI_TICK_S * 1e6
	local ids = self:townIds(now) or {}
	local n = math.min(#ids, D.RCI_MAX_TOWNS)
	if n == 0 then return false end
	local known = self.opts.actOn == "new" and SV.knownSet(saved) or nil
	local E = self.E
	local t0 = self:nowUs()
	local sent = false
	for _ = 1, math.min(n, D.RCI_PER_TICK) do
		self.rciCursor = ((self.rciCursor or 0) % n) + 1
		local t = ids[self.rciCursor]
		local ok, res = pcall(self.rciTown, self, t, now, saved, known)
		if not ok then
			if not self.rciErrLogged then
				self.rciErrLogged = true
				self:log("ERROR", { { "stage", "rci" }, { "town", t }, { "err", res } })
			end
		elseif res == "sent" then
			sent = true
			break
		end
		if self:nowUs() - t0 > D.RCI_BUDGET_US then break end
	end
	self:rciSummary(now)
	return sent
end

function Driver:rciSkip(t, r, why, fields)
	self.rciCounts = self.rciCounts or { writes = 0, skips = {} }
	self.rciCounts.skips[why] = (self.rciCounts.skips[why] or 0) + 1
	if r.why == why then return end
	r.why = why
	local f = { { "town", t }, { "name", self.E.name(t) }, { "skip", why } }
	for _, x in ipairs(fields or {}) do f[#f + 1] = x end
	self:debug("RCI", f)
end

--- One town's weighting step (RCI.step). Returns "sent", "due" (read, nothing sent) or nil (not due / not eligible).
function Driver:rciTown(t, now, saved, known)
	if t == nil then return nil end
	local s = self:townState(t)
	local r = s.rci
	if r == nil then
		local okE, whyE = self:rciEligible(t, saved, known)
		if not okE then
			s.rci = { off = true, why = whyE, k = 0 }
			return nil
		end
		r = { k = 0 }
		local sv = SV.rci(saved, t)
		if sv then r.e, r.S, r.y, r.n0, r.k = sv.e, sv.s, sv.y, sv.n0, sv.k or 0 end
		s.rci = r
	elseif r.off then
		return nil
	end
	local E = self.E
	local yf = E.yearF and E.yearF() or nil
	-- (due: a game month since the last read; real seconds when the date can't be read; a date moved back resets)
	if r.y ~= nil and yf ~= nil then
		if yf < r.y then r.y = yf end
		-- (half a game day of slack: the calendar's month steps are not exact twelfths)
		if yf - r.y < RCI.STEP_YEARS - 1 / 730 then return nil end
	elseif r.us ~= nil and now - r.us < RCI.STEP_S * 1e6 then
		return nil
	end
	local okE, whyE = self:rciEligible(t, saved, known)
	if not okE then
		r.off = true
		self:rciSkip(t, r, whyE)
		return nil
	end
	local caps = E.townCaps(t)
	local dt = (r.y ~= nil and yf ~= nil) and (yf - r.y) or RCI.STEP_YEARS
	r.y, r.us = yf, now
	if caps == nil or caps.initials == nil or caps.initials[3] == nil or caps.sizeFactors == nil then
		self:rciSkip(t, r, "noCaps")
		return "due"
	end
	local shares, S = RCI.shares(caps.initials, caps.sizeFactors)
	r.shares = shares
	r.lean = RCI.lean(shares)
	local sd = E.townSupply and E.townSupply(t) or nil
	local u = RCI.usage(sd)
	if u == nil then
		self:rciSkip(t, r, "noSupply")
		return "due"
	end
	r.u = u
	r.e = RCI.smooth(r.e, u, dt)
	r.w = RCI.aim(r.e)
	if S == nil then
		self:rciSkip(t, r, "zero")
		return "due"
	end
	-- (the growth since the last step: a first sight has none; a target that fell restarts from it)
	if r.S == nil or S < r.S then r.S = S end
	local st = RCI.step({ init = caps.initials, sf = caps.sizeFactors, uses = caps.uses, w = r.w, grown = S - r.S,
		n0 = r.n0 })
	if st.why ~= "ok" then
		-- (too little growth yet: it adds up until it can move a step; anything else uses the growth up)
		if st.why ~= "noGrowth" and st.why ~= "tiny" then r.S = S end
		self:rciSkip(t, r, st.why, { { "r/c/i", RCI.pct(shares) }, { "aim", RCI.pct(r.w) }, { "supply", RCI.frac(u) } })
		return "due"
	end
	r.why = "ok"
	r.n0 = r.n0 or st.N
	r.k = (r.k or 0) + 1
	r.S = st.S1
	r.shares = st.s1
	r.lean = RCI.lean(st.s1)
	self.rciCounts = self.rciCounts or { writes = 0, skips = {} }
	self.rciCounts.writes = self.rciCounts.writes + 1
	self:log("RCI", { { "town", t }, { "name", E.name(t) },
		{ "r/c/i", RCI.pct(shares) .. "->" .. RCI.pct(st.s1) }, { "aim", RCI.pct(r.w) }, { "supply", RCI.frac(u) },
		{ "smoothed", RCI.frac(r.e) }, { "caps", rciRow(caps.initials) .. "->" .. rciRow(st.list) },
		{ "built", rciRow(caps.uses) }, { "target", string.format("%.0f->%.0f", st.S, st.S1) },
		{ "sum", string.format("%d->%d", math.floor(st.N + 0.5), st.N1) }, { "n0", r.n0 },
		{ "move", string.format("%.3f", st.move or 0) }, { "budget", string.format("%.3f", st.budget or 0) },
		{ "lean", r.lean or "-" }, { "n", r.k } })
	-- (the level weights before the write: the engine may rewrite them with the capacities, findings towns.md
	-- "Restoring a town's initial capacities writes its custom level weights")
	local sig0 = nil
	if E.levelInfo then
		local okI, info = pcall(E.levelInfo, t)
		if okI and info then sig0 = UP.levelSig(info.custom) end
	end
	self.inflight = true
	E.setInitialCaps(t, st.list, function(ok)
		self.inflight = false
		if not ok then
			self:log("RCI", { { "town", t }, { "ok", false } })
			return
		end
		local okL, errL = pcall(self.rciLevels, self, t, sig0)
		if not okL then self:log("WARN", { { "stage", "rciLevels" }, { "town", t }, { "err", errL } }) end
	end)
	if E.sendEvent then
		E.sendEvent(SV.EVENT_ID, SV.EV_RCI, { town = t, e = RCI.pack(r.e), s = math.floor(st.S1 + 0.5),
			y = math.floor((yf or 0) * 100 + 0.5), n0 = r.n0, k = r.k })
	end
	return "sent"
end

--- After a weighting write: the town's level weights stay as they were. A town whose weights the mod manages gets its
--- own back (levelsAfterRestore, §58); any other town whose weights changed with the write gets its old ones back
--- (none: the game's default). `RCI levels=` line when something was put back.
function Driver:rciLevels(t, sig0)
	local E = self.E
	if E.levelInfo == nil or E.setLevelWeights == nil or sig0 == nil then return end
	local ours = self:levelOurs(t)
	if ours ~= 0 then return self:levelsAfterRestore(t) end
	local okI, info = pcall(E.levelInfo, t)
	if not okI or info == nil then return end
	local sig1 = UP.levelSig(info.custom)
	if sig1 == sig0 then return end
	local back = UP.levelUnsig(sig0)
	self:log("RCI", { { "town", t }, { "levels", "putBack" }, { "from", sig1 }, { "to", sig0 } })
	E.setLevelWeights(t, back, function(ok)
		if not ok then self:log("RCI", { { "town", t }, { "levels", "putBack" }, { "ok", false } }) end
	end)
end

--- RCI summary every RCI_LOG_S real seconds (on only): towns read, written ever / this window, leans, skips.
function Driver:rciSummary(now)
	if self.rciLogUs == nil then self.rciLogUs = now return end
	if now - self.rciLogUs < D.RCI_LOG_S * 1e6 then return end
	self.rciLogUs = now
	local seen, written, leans = 0, 0, { res = 0, com = 0, ind = 0 }
	local cnt = 0
	for _, s in pairs(self.towns) do
		cnt = cnt + 1
		if cnt > D.RCI_MAX_TOWNS then break end
		local r = s.rci
		if r and not r.off then
			seen = seen + 1
			if (r.k or 0) > 0 then written = written + 1 end
			if r.lean then leans[r.lean] = leans[r.lean] + 1 end
		end
	end
	local c = self.rciCounts or { writes = 0, skips = {} }
	local sk = {}
	for k, v in pairs(c.skips) do sk[#sk + 1] = k .. ":" .. v end
	table.sort(sk)
	self:log("RCI summary", { { "towns", seen }, { "weighted", written }, { "writes", c.writes },
		{ "lean", string.format("res:%d,com:%d,ind:%d", leans.res, leans.com, leans.ind) },
		{ "skips", #sk > 0 and table.concat(sk, ",") or "-" } })
	self.rciCounts = { writes = 0, skips = {} }
end

---------------------------------------------------------------------------

--- true when the pre-check messages name Construction_Not_Possible.
function D.notPossible(msgs)
	for _, m in ipairs(msgs or {}) do
		-- the engine's text is "Construction Not Possible" (spaces; the log line shows "_" because fmt replaces
		-- whitespace): the old exact "Construction_Not_Possible" match never fired, so no DIAG in the showcase
		local t = tostring(m):lower():gsub("[%s_]+", "")
		if t:find("constructionnotpossible", 1, true) then return true end
	end
	return false
end

--- Per-edge diagnosis lines (DIAG / DIAGSUM): with the dev tools' diagnosis hook or the debug log.
function Driver:diagOn()
	return H.diagnose == true or self:debugOn()
end

function Driver:diagLog(what, fields)
	if self:diagOn() then return self:log(what, fields) end
	return nil
end

--- What a pre-check collided with: up to 4 entities as "edge<id>:<size>@<m>" for streets of the job's snapshot
--- (distance from the edge `e` when given, else from the increment), "node<id>" for its nodes, else "ent<id>".
function Driver:partnerText(job, ids, e)
	local byId, nodes = {}, {}
	for _, ed in ipairs(job.edges or {}) do
		byId[ed.id] = ed
		nodes[ed.n0], nodes[ed.n1] = ed.p0, ed.p1
	end
	local function distTo(px, py)
		local best = math.huge
		for _, x in ipairs(e and { e } or (job.inc and job.inc.edges) or {}) do
			best = math.min(best, G.pointSegDist(px, py, x.p0[1], x.p0[2], x.p1[1], x.p1[2]))
		end
		return best
	end
	local out = {}
	for i = 1, math.min(#ids, 4) do
		local id = ids[i]
		local ed = byId[id]
		if ed then
			local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
			local size = (ed.template or ""):match("_(%a+)%.street_template$") or "?"
			out[#out + 1] = string.format("edge%d:%s@%.0f", id, size, distTo(mx, my))
		elseif nodes[id] then
			out[#out + 1] = string.format("node%d@%.0f", id, distTo(nodes[id][1], nodes[id][2]))
		else
			-- (entity kind: street / track / node / field / con ..., 2026-10-13)
			local kind = self.E.entityKind and self.E.entityKind(id) or nil
			out[#out + 1] = "ent" .. tostring(id) .. (kind and (":" .. kind) or "")
		end
	end
	if #ids > 4 then out[#out + 1] = "+" .. (#ids - 4) end
	return table.concat(out, ",")
end

local function v3text(v)
	return string.format("%.1f,%.1f,%.1f", v[1] or 0, v[2] or 0, v[3] or 0)
end

--- Diagnosis stage (dev tools, ot_hooks.diagnose): pre-checks the increment's edges one by one, each with its
--- new end nodes (a join edge with its D3 joint config), DIAG_PER_TICK per tick; logs the first DIAG_LOG
--- failing edges with the checker's numbers (DIAG) and a summary (DIAGSUM), then resumes the send stage.
function Driver:diag(job, now)
	local E, t, dg = self.E, job.town, job.diag
	local inc = job.inc
	for _ = 1, D.DIAG_PER_TICK do
		dg.i = dg.i + 1
		local i = dg.i
		if i > #inc.edges then break end
		local e = inc.edges[i]
		local sub = PR.single(inc, i)
		local spec, err = PR.build(sub, dg.info)
		local r
		if spec == nil then
			r = { ok = false, msgs = { "spec:" .. tostring(err) }, collisions = 0, us = 0 }
		else
			local okP, proposal = pcall(E.proposal, spec)
			if okP then r = E.precheck(proposal, dg.ctx) else r = { ok = false, msgs = { "proposal:" .. tostring(proposal) }, collisions = 0, us = 0 } end
		end
		dg.us = dg.us + (r.us or 0)
		if not r.ok then
			dg.nFailed = dg.nFailed + 1
			dg.failed[#dg.failed + 1] = i
			if dg.nFailed <= D.DIAG_LOG and self:diagOn() then
				local g = CK.edge(e)
				local join = (e.node0 > 0 and e.node0) or (e.node1 > 0 and e.node1) or "-"
				self:log("DIAG", { { "town", t }, { "i", i }, { "edge", e.entity }, { "key", e.key or "-" },
					{ "class", e.class or "-" }, { "join", join }, { "len", g.chord }, { "arc", g.length },
					{ "minR", g.minRadius }, { "dev", string.format("%.1f/%.1f", g.dev0, g.dev1) }, { "slope", g.slope },
					{ "p0", v3text(e.p0) }, { "t0", v3text(e.t0) }, { "t1", v3text(e.t1) }, { "msgs", r.msgs },
					{ "collisions", r.collisions }, { "partners", r.partners and self:partnerText(job, r.partners, e) or "-" },
					{ "err", r.err or "-" } })
			end
			-- a joint edge refused with no collision (showcase v3: 18 of 20 such failures were `conn:` joint edges):
			-- pin the cause with variant pre-checks (dev diagnosis only)
			if H.diagnose == true and (dg.joints or 0) < D.DIAG_LOG and D.notPossible(r.msgs) and (r.collisions or 0) == 0
				and (e.node0 > 0) ~= (e.node1 > 0) then
				dg.joints = (dg.joints or 0) + 1
				self:diagJoint(job, dg, i)
			end
		end
	end
	if dg.i < #inc.edges then return end
	-- every edge passes alone but the whole is refused (showcase v2: 46 x "Construction Not Possible" with no
	-- collision): pre-check each junction star (a node with its new edges) to find the combination that fails
	if not dg.pre.ok and dg.nFailed == 0 and #inc.edges >= 2 and dg.stars == nil then
		dg.stars, dg.si, dg.starFailed = D.stars(inc), 0, {}
		if #dg.stars > 0 then return end
	end
	if dg.stars and dg.si < #dg.stars then
		for _ = 1, D.DIAG_PER_TICK do
			dg.si = dg.si + 1
			local st = dg.stars[dg.si]
			if st == nil then break end
			local spec, err = PR.build(D.subIncrement(inc, st.edges), dg.info)
			local r
			if spec == nil then
				r = { ok = false, msgs = { "spec:" .. tostring(err) }, collisions = 0, us = 0 }
			else
				local okP, proposal = pcall(E.proposal, spec)
				if okP then r = E.precheck(proposal, dg.ctx) else r = { ok = false, msgs = { "proposal:" .. tostring(proposal) }, collisions = 0, us = 0 } end
			end
			dg.us = dg.us + (r.us or 0)
			if not r.ok then
				dg.starFailed[#dg.starFailed + 1] = st
				if #dg.starFailed <= D.DIAG_LOG and self:diagOn() then
					local keys, classes = {}, {}
					for _, i in ipairs(st.edges) do
						keys[#keys + 1] = inc.edges[i].key or "-"
						classes[#classes + 1] = inc.edges[i].class or "-"
					end
					self:log("DIAGNODE", { { "town", t }, { "node", st.node }, { "new", st.node < 0 }, { "edges", #st.edges },
						{ "keys", table.concat(keys, ",") }, { "classes", table.concat(classes, ",") },
						{ "minAngle", string.format("%.1f", st.minAngle or 0) }, { "shortest", string.format("%.1f", st.shortest or 0) },
						{ "msgs", r.msgs }, { "collisions", r.collisions },
						{ "partners", r.partners and self:partnerText(job, r.partners) or "-" } })
				end
			end
		end
		if dg.si < #dg.stars then return end
	end
	local geo = CK.increment(inc, job.g)
	self:diagLog("DIAGSUM", { { "town", t }, { "whole", dg.pre.ok and "ok" or "refused" }, { "tested", #inc.edges },
		{ "failed", dg.nFailed }, { "stars", dg.stars and #dg.stars or 0 }, { "starsFailed", dg.starFailed and #dg.starFailed or 0 },
		{ "joints", dg.joints or 0 }, { "player", dg.asPlayer and "on" or "off" }, { "geo", CK.summary(geo) }, { "us", dg.us } })
	job.diag = nil
	-- the newest edge of each failing star (edges are in planning order: the last one completed the combination)
	local starDrop = {}
	for _, st in ipairs(dg.starFailed or {}) do
		local last = st.edges[#st.edges]
		if last then starDrop[#starDrop + 1] = last end
	end
	-- drop what fails alone (or the edge completing a failing star) and plan again at the same size
	local drop = dg.failed
	if dg.nFailed == 0 then drop = starDrop end
	if not dg.pre.ok and #drop > 0 and #drop < #inc.edges and (job.pruneRounds or 0) < D.PRUNE_ROUNDS then
		job.pruneRounds = (job.pruneRounds or 0) + 1
		local keys = {}
		for _, i in ipairs(drop) do
			local k = inc.edges[i].key
			if k and not keys[k] then
				keys[k] = true
				self:exclude(t, k)
			end
		end
		local list = {}
		for k in pairs(keys) do list[#list + 1] = k end
		table.sort(list)
		self:debug("PRUNE", { { "town", t }, { "round", job.pruneRounds }, { "dropped", #drop }, { "of", #inc.edges },
			{ "by", dg.nFailed > 0 and "edge" or "star" },
			{ "pieces", table.concat(list, ",") }, { "msgs", dg.pre.msgs } })
		self.counts.refused = self.counts.refused + 1
		job.stage = "plan"
		return
	end
	return self:afterPrecheck(job, now, dg.spec, dg.proposal, dg.ctx, dg.pre, dg.fields, dg.asPlayer)
end

--- Geometry of a joint edge (one end on an existing node) against the existing street there: { node, atStart,
--- h (heading leaving the node), out (the dead end's street continued outward), turn (rad), len, fp (footprint
--- with the existing street, ot_check), exLen (the existing street's length), near (m to the nearest other
--- existing node), x, y, z } or nil.
function D.jointInfo(g, e)
	local j = e.node0 > 0 and e.node0 or e.node1
	local jn = g and g.nodeById[j]
	if jn == nil then return nil end
	local atStart = e.node0 == j
	local h = atStart and G.atan2(e.t0[2], e.t0[1]) or G.atan2(-e.t1[2], -e.t1[1])
	local p = atStart and e.p0 or e.p1
	local out = { node = j, atStart = atStart, h = h, len = G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2]), x = p[1], y = p[2],
		z = p[3] or jn.z or 0, fp = 0, exLen = 0, near = math.huge }
	local other = {}
	for _, id in ipairs(g.adj[j] or {}) do
		local ex = g.edgeById[id]
		other[OG.other(ex, j)] = true
		local eh = OG.headingFrom(g, ex, j)
		out.out = out.out or G.wrap(eh + math.pi)
		out.fp = math.max(out.fp, CK.footprint(h, CK.halfWidth(e.class, e.template), eh, CK.halfWidth(ex.class, ex.template)))
		out.exLen = math.max(out.exLen, OG.edgeLength(g, ex))
	end
	out.turn = out.out and G.angleDiff(out.out, h) or 0
	for _, n in ipairs(g.nodes) do
		if n.id ~= j and not other[n.id] then
			local d = G.dist(n.x, n.y, p[1], p[2])
			if d < out.near then out.near = d end
		end
	end
	return out
end

--- A joint edge alone, re-aimed (dev diagnosis): kind "straight" = along the dead end's street, same length;
--- "long" = its own heading, max(40 m, twice the length). An ot_plan-shaped increment (edge -1, new node -2).
function D.jointVariant(inc, i, ji, kind)
	local e = inc.edges[i]
	local heading = kind == "straight" and (ji.out or ji.h) or ji.h
	local L = kind == "long" and math.max(40, 2 * ji.len) or ji.len
	local fx, fy = ji.x + math.cos(heading) * L, ji.y + math.sin(heading) * L
	local c = {}
	for k, v in pairs(e) do c[k] = v end
	c.entity, c.node0, c.node1 = -1, ji.node, -2
	c.p0 = { ji.x, ji.y, ji.z }
	c.p1 = { G.round(fx), G.round(fy), ji.z }
	c.t0 = { G.round(math.cos(heading) * L), G.round(math.sin(heading) * L), 0 }
	c.t1 = { c.t0[1], c.t0[2], 0 }
	c.length = L
	return { nodes = { { entity = -2, x = c.p1[1], y = c.p1[2], z = ji.z } }, edges = { c },
		joins = { { node = ji.node, edge = -1 } }, dropped = {}, stats = { edges = 1, nodes = 1, length = L } }
end

--- Dev diagnosis of a joint edge refused alone with no collision: its geometry and three variant pre-checks (no
--- config change at the joint = plain join; straight along the dead end's street; the same heading, longer).
--- Pre-checks only, nothing is sent; new nodes keep their configs. Logs DIAGJOINT.
function Driver:diagJoint(job, dg, i)
	local E, inc = self.E, job.inc
	local e = inc.edges[i]
	local ji = D.jointInfo(job.g, e)
	if ji == nil then return end
	local function check(sub, plain)
		local spec, err = PR.build(sub, dg.info)
		if spec == nil then return "spec:" .. tostring(err) end
		if plain then
			local keep = {}
			for _, c in ipairs(spec.cfgAdd) do if c.node ~= ji.node then keep[#keep + 1] = c end end
			spec.cfgAdd = keep
			local rm = {}
			for _, n in ipairs(spec.cfgRemove) do if n ~= ji.node then rm[#rm + 1] = n end end
			spec.cfgRemove = rm
		end
		local okP, proposal = pcall(E.proposal, spec)
		if not okP then return "proposal" end
		local r = E.precheck(proposal, dg.ctx)
		dg.us = dg.us + (r.us or 0)
		if r.ok then return "ok" end
		return (#(r.msgs or {}) > 0 and fmt(r.msgs[1]) or "refused") .. ((r.collisions or 0) > 0 and ("+c" .. r.collisions) or "")
	end
	local plain = check(PR.single(inc, i), true)
	local straight = check(D.jointVariant(inc, i, ji, "straight"), false)
	local long = check(D.jointVariant(inc, i, ji, "long"), false)
	self:diagLog("DIAGJOINT", { { "town", job.town }, { "i", i }, { "key", e.key or "-" }, { "node", ji.node },
		{ "len", ji.len }, { "turn", string.format("%.1f", math.deg(ji.turn)) },
		{ "deadEndDeg", ji.out and string.format("%.1f", math.deg(ji.out)) or "-" },
		{ "edgeDeg", string.format("%.1f", math.deg(ji.h)) }, { "footprint", string.format("%.1f", ji.fp) },
		{ "existingLen", string.format("%.1f", ji.exLen) }, { "nearNode", string.format("%.1f", ji.near) },
		{ "plain", plain }, { "straight", straight }, { "long", long } })
end

--- Junction stars of an increment: every node (new or existing) where 2+ of its new edges meet, as
--- { node, edges = { edge indices, ascending }, minAngle (deg, between the new edges' tangents), shortest (m) }.
function D.stars(inc)
	local at, order = {}, {}
	for i, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if at[n] == nil then at[n] = {}; order[#order + 1] = n end
			local l = at[n]
			if l[#l] ~= i then l[#l + 1] = i end
		end
	end
	local out = {}
	for _, n in ipairs(order) do
		local l = at[n]
		if #l >= 2 then
			local hs, shortest = {}, math.huge
			for _, i in ipairs(l) do
				local e = inc.edges[i]
				local h
				if e.node0 == n then h = G.atan2(e.t0[2], e.t0[1]) else h = G.atan2(-e.t1[2], -e.t1[1]) end
				hs[#hs + 1] = h
				shortest = math.min(shortest, G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2]))
			end
			local minA = 180
			for a = 1, #hs do
				for b = a + 1, #hs do minA = math.min(minA, math.deg(G.angleDiff(hs[a], hs[b]))) end
			end
			out[#out + 1] = { node = n, edges = l, minAngle = minA, shortest = shortest }
		end
	end
	return out
end

--- The increment reduced to the edges at `indices` (renumbered -1..-k, their new nodes after them; joins at
--- existing nodes), as ot_plan shapes (dev diagnosis of a star).
function D.subIncrement(inc, indices)
	local out = { nodes = {}, edges = {}, joins = {}, dropped = {} }
	local nodeById = {}
	for _, nd in ipairs(inc.nodes) do nodeById[nd.entity] = nd end
	local k = #indices
	local map, nextId = {}, -(k + 1)
	local function ref(n)
		if n > 0 then return n end
		if map[n] == nil then
			local nd = nodeById[n]
			map[n] = nextId
			out.nodes[#out.nodes + 1] = { entity = nextId, x = nd.x, y = nd.y, z = nd.z }
			nextId = nextId - 1
		end
		return map[n]
	end
	for j, i in ipairs(indices) do
		local e = inc.edges[i]
		local c = {}
		for kk, v in pairs(e) do c[kk] = v end
		c.entity, c.node0, c.node1 = -j, ref(e.node0), ref(e.node1)
		out.edges[j] = c
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n > 0 then out.joins[#out.joins + 1] = { node = n, edge = -j } end
		end
	end
	out.stats = { edges = #out.edges, nodes = #out.nodes, length = 0 }
	return out
end

--- CHECK `sat=`: the satellite's "buildings near/own core edges@distance" or "-".
function D.satText(sat, pts)
	if sat == nil then return "-" end
	return string.format("%d/%d@%.0f", SAT.buildingsNear(sat, pts), sat.edges or 0, sat.dist or sat.linkLen or 0)
end

---------------------------------------------------------------------------
-- Staggered offshoots (ot_satpace, 2026-10-14, NEXT_PHASE_BRIEF 51; user: "make sure satellites don't get built during
-- the same period"): every founding (satellite seed, Works, district) asks Driver:paceGate after its own gates pass and
-- before its site search: per-town readiness (seeded size milestones over the town's starting size: frame `b0`), at
-- most one founding per map-wide slot (the map's size, every town's persons / OFFSHOOT_PB, grew by SP.need since the
-- last founding's mark, or game years when the calendar moves), the slot to the ready town with the highest seeded key.
-- A failed founding gives the slot back (paceRefund). The pacing record is saved (`sp`, EV_PACE), so a reload keeps the
-- gap. A pod's growth (kind=grow) follows SP.growDue. Lines: SATPACE (one per decision; `wait` lines only when the
-- town's reason changes, debug), SATPACE summary (foundings per decade).
D.PACE = true
D.PACE_SUM_S = 2           -- real s: the map's size re-read after this
D.PACE_MAX_TOWNS = 4000    -- loop cap of the map's size
D.PACE_SUMMARY_S = 600     -- real s between two SATPACE summary lines after foundings (debug)

--- The session's pacing state (on the root driver, shared with the dev tools' pool drivers), from the saved `sp`.
function Driver:pace(saved)
	local r = self:root()
	if r.satPace == nil then
		local sv = self:savedNow(saved)
		r.satPace = SP.new(sv)
		self:debug("SATPACE", { { "event", "init" }, { "restored", r.satPace.restored == true }, { "n", r.satPace.n },
			{ "mark", r.satPace.mark and string.format("%.0f", r.satPace.mark) or "-" } })
	end
	return r.satPace
end

--- The map's seeded salt (the smallest town id: the same map, the same draws).
function Driver:paceSalt(now)
	local r = self:root()
	if r.paceSaltV then return r.paceSaltV end
	local lo = nil
	for i, t in ipairs(self:townIds(now) or {}) do
		if i > D.PACE_MAX_TOWNS then break end
		if lo == nil or t < lo then lo = t end
	end
	r.paceSaltV = RNG.hash("satpace", lo or 1)
	return r.paceSaltV
end

--- A town's starting size for its readiness (offshoot size units): the frame's `b0`, else its initial capacity /
--- OFFSHOOT_PB, else its size at the first sight this session. pb = true: persons / OFFSHOOT_PB units (the map base).
function Driver:paceStart(t, saved, size, pb)
	local fr = SV.frame(self:savedNow(saved), t)
	local ic = fr and tonumber(fr.initial) or nil
	if pb and ic and ic > 0 then return ic / D.OFFSHOOT_PB end
	if not pb and fr and tonumber(fr.start) and fr.start > 0 then return fr.start end
	if ic and ic > 0 then return ic / D.OFFSHOOT_PB end
	local s = self:townState(t)
	if pb then
		s.paceP0 = s.paceP0 or size
		return s.paceP0 or 0
	end
	s.paceB0 = s.paceB0 or size
	return s.paceB0 or size or 0
end

--- The map's size for the pacing, cached PACE_SUM_S: { sum = every town's persons / OFFSHOOT_PB (not the mod's own
--- Works / district towns), base = their starting sizes, n = towns }.
function Driver:paceMap(now, saved)
	local r = self:root()
	local c = r.paceMapC
	if c and now - c.us >= 0 and now - c.us < D.PACE_SUM_S * 1e6 then return c end
	local E = self.E
	local created = self:createdTowns(saved)
	local sum, base, n = 0, 0, 0
	for i, t in ipairs(self:townIds(now) or {}) do
		if i > D.PACE_MAX_TOWNS then break end
		if not created[t] then
			local caps = E.townCaps and E.townCaps(t) or nil
			local p = caps and tonumber(caps.actual) or nil
			if p and p == p and p >= 0 and p < 1e9 then
				n = n + 1
				sum = sum + p / D.OFFSHOOT_PB
				base = base + self:paceStart(t, saved, p / D.OFFSHOOT_PB, true)
			end
		end
	end
	c = { us = now, sum = sum, base = base, n = n }
	r.paceMapC = c
	return c
end

--- How many offshoots town t has founded (satellite, Works, districts: this session's records or its frame).
function Driver:paceCount(t, saved)
	local s = self:townState(t)
	local fr = SV.frame(self:savedNow(saved), t)
	local k = 0
	if s.sat or (fr and fr.sat) then k = k + 1 end
	if s.works or (fr and fr.works) then k = k + 1 end
	local d = #(s.districts or {})
	if d == 0 and fr and tonumber(fr.districts) then d = fr.districts end
	return k + d
end

--- The elapsed years for the history: game years since the first sight, plus the dev Simulate's years.
function Driver:paceElapsed(st, yr)
	local e = (yr and st.y0) and (yr - st.y0) or 0
	return math.max(0, e) + (tonumber(H.simYears) or 0)
end

function Driver:paceSave()
	local st = self:root().satPace
	if st == nil or self.E.sendEvent == nil then return end
	st.dirty = nil
	self.E.sendEvent(SV.EVENT_ID, SV.EV_PACE, SP.param(st))
end

--- The pacing decision for this job's founding (kind "seed" | "works" | "district"): "found" | "wait" | "deferred",
--- once per job (the job's next decision reuses it). Logs SATPACE.
function Driver:paceGate(job, kind, now, saved)
	if not (D.PACE and SP.ON) then return "found" end
	if job.pace then return job.pace end
	local E, t = self.E, job.town
	local st = self:pace(saved)
	local s = self:townState(t)
	local size = D.offshootSize(job.pts and #job.pts or 0, job.caps)
	local seed = (job.style and job.style.seed) or t
	s.paceSeed = seed
	s.paceDv = job.style and job.style.drawV or nil   -- (§68: rng.decide's version for the readiness)
	local mp = self:paceMap(now, saved)
	local yr = E.yearF and E.yearF() or nil
	if st.y0 == nil and yr then st.y0 = yr end
	local k = self:paceCount(t, saved)
	local start = self:paceStart(t, saved, size)
	local out, why, info = SP.decide(st, { t = t, kind = kind, size = size, start = start, k = k, seed = seed, dv = s.paceDv,
		quality = 1 / (1 + (s.paceFails or 0)), now = now, sum = mp.sum, base = mp.base, year = yr, nTowns = mp.n,
		salt = self:paceSalt(now), epoch = H.simRound, elapsed = self:paceElapsed(st, yr) })
	job.pace = out
	-- (the card's offshoot readiness, 2026-10-17: the last ratio read, Driver:uiNote)
	if type(info.ratio) == "number" and info.ratio == info.ratio then s.paceRatio = info.ratio end
	local key = out .. ":" .. why .. ":" .. k
	if out ~= "wait" or s.paceLast ~= key then
		s.paceLast = key
		local f = { { "town", t }, { "name", E.name(t) }, { "kind", kind }, { "k", k },
			{ "ready", string.format("%.2f", info.ratio or 0) }, { "size", string.format("%.0f", size) },
			{ "target", string.format("%.0f", info.target or 0) }, { "start", string.format("%.0f", start or 0) },
			{ "mapGrowth", string.format("%.0f", info.growth or 0) }, { "need", string.format("%.0f", info.need or 0) },
			{ "years", string.format("%.1f", info.years or 0) }, { "cands", info.cands or "-" }, { "winner", info.winner or "-" },
			{ "outcome", out }, { "why", why }, { "n", st.n }, { "simYear", H.simYears or "-" } }
		if out == "wait" then self:debug("SATPACE", f) else self:log("SATPACE", f) end
	end
	if out == "found" then
		self:paceSave()
		local r = self:root()
		if now - (r.paceSummaryUs or -1e18) >= D.PACE_SUMMARY_S * 1e6 or st.n <= 1 then
			r.paceSummaryUs = now
			if self:debugOn() then self:satPaceSummary("found", now) end
		end
	elseif st.dirty then
		self:paceSave()
	end
	return out
end

--- This job's founding failed (no site, no name, not sent, refused): the slot goes back, the town sits it out.
function Driver:paceRefund(t, why, job)
	if job then job.pace = "wait" end
	if not (D.PACE and SP.ON) then return end
	local st = self:root().satPace
	if st == nil then return end
	if SP.refund(st, t) then
		local s = self:townState(t)
		s.paceFails = (s.paceFails or 0) + 1
		self:log("SATPACE", { { "town", t }, { "name", self.E.name(t) }, { "outcome", "refund" }, { "why", why },
			{ "n", st.n }, { "simYear", H.simYears or "-" } })
		self:paceSave()
	end
end

--- A check of town t (every measure): its first-seen size, and during the dev Simulate's founding round the mark to be.
function Driver:paceSeen(t, m, now)
	if not (D.PACE and SP.ON) then return end
	local s = self:townState(t)
	s.paceB0 = s.paceB0 or D.offshootSize(m.buildings, m.caps)
	local st = self:root().satPace
	if st and st.epoch ~= nil then
		local mp = self:paceMap(now)
		if SP.observe(st, mp.sum, H.simRound) then self:paceSave() end
	end
end

--- May a town that needs no streets get an offshoot turn for a founding now (cheap: readiness and the slot)?
function Driver:paceTurnOk(t, size, now, saved)
	if not (D.PACE and SP.ON) then return true end
	local s = self:townState(t)
	if s.paceSeed == nil then return true end
	local ready = SP.readiness({ size = size, start = self:paceStart(t, saved, size), k = self:paceCount(t, saved),
		seed = s.paceSeed, dv = s.paceDv })
	if not ready then return false end
	local st = self:pace(saved)
	local mp = self:paceMap(now, saved)
	if st.mark == nil then st.mark = mp.base end
	local open = SP.slot(st, { sum = mp.sum, year = self.E.yearF and self.E.yearF() or nil,
		need = SP.need(mp.n, st.n, self:paceSalt(now)) })
	return open
end

--- Is the satellite pod of this job's town due to grow (SP.growDue)? Moves the marks when it is. Logs SATPACE kind=grow.
function Driver:paceGrowDue(job, s, n, now, saved)
	if not (D.PACE and SP.ON) then return n % SAT.EVERY == 0 end
	local st = self:pace(saved)
	local mp = self:paceMap(now, saved)
	local size = D.offshootSize(job.pts and #job.pts or 0, job.caps)
	if st.growMark == nil then st.growMark = mp.sum end
	if s.sat.podMark == nil then s.sat.podMark = size end
	local need = SP.need(mp.n, st.n, self:paceSalt(now))
	local seed = RNG.hash((job.style and job.style.seed) or job.town, "pod")
	local due, why = SP.growDue({ seed = seed, dv = job.style and job.style.drawV, n = n, size = size, podMark = s.sat.podMark, sum = mp.sum,
		growMark = st.growMark, need = need })
	local key = "grow:" .. why
	if due or s.paceGrowLast ~= key then
		s.paceGrowLast = key
		self:debug("SATPACE", { { "town", job.town }, { "name", self.E.name(job.town) }, { "kind", "grow" },
			{ "n", n }, { "size", string.format("%.0f", size) },
			{ "podGrowth", s.sat.podMark and string.format("%.0f", size - s.sat.podMark) or "-" },
			{ "mapGrowth", string.format("%.0f", mp.sum - st.growMark) },
			{ "need", string.format("%.0f", need * SP.GROW_MAP_F) }, { "outcome", due and "found" or "wait" }, { "why", why },
			{ "simYear", H.simYears or "-" } })
	end
	if due then
		s.sat.podMark, st.growMark = size, mp.sum
		st.grows = (st.grows or 0) + 1
	end
	return due
end

--- SATPACE summary: foundings so far, per decade of elapsed years (game years + the dev Simulate's), the smallest gap.
function Driver:satPaceSummary(why, now)
	local st = self:root().satPace
	if st == nil then
		self:log("SATPACE summary", { { "why", why or "-" }, { "on", D.PACE and SP.ON }, { "founded", 0 }, { "decades", "-" } })
		return
	end
	now = now or self:nowUs()
	local mp = self:paceMap(now)
	local gap = SP.minGap(st.hist)
	self:log("SATPACE summary", { { "why", why or "-" }, { "on", D.PACE and SP.ON }, { "founded", st.n },
		{ "decades", SP.decades(st.hist) }, { "years", #st.hist > 0 and table.concat((function()
			local o = {}
			for _, y in ipairs(st.hist) do o[#o + 1] = string.format("%.0f", y) end
			return o
		end)(), "/") or "-" }, { "minGap", gap and string.format("%.1f", gap) or "-" }, { "grows", st.grows or 0 },
		{ "mapGrowth", st.mark and string.format("%.0f", mp.sum - st.mark) or "-" },
		{ "need", string.format("%.0f", SP.need(mp.n, st.n, self:paceSalt(now))) }, { "towns", mp.n },
		{ "simYear", H.simYears or "-" } })
end

---------------------------------------------------------------------------
-- Satellite villages (ot_satellite, 2026-10-13): seeded at a demand build of a grown town (since 2026-10-14 paced
-- map-wide: Driver:paceGate), then grown on the pod's own cadence (Driver:paceGrowDue; SAT.EVERY-th demand build with the
-- pacing off) while its houses keep up. All its streets locked (the game can't branch them out into
-- the meadow), no fill. The site is saved with the town's frame (EV_SAT), so a reload neither seeds a second one nor
-- forgets the meadow between.
D.SAT_RETRY_S = 300        -- after no site: try again this much later (real s; 600 until 2026-10-13)
D.SAT_REFUSED_RETRY_S = 90 -- after a refused / empty seed: the next site this much later (2026-10-13, round 5)
D.SAT_TRIES = 4            -- seed attempts per town and session (2 until 2026-10-13: a refusal ended the town's turn)
D.SAT_MAP_MIN = 2          -- map quota: while fewer satellites than this are known this session, a town the seeded
D.SAT_QUOTA_BUILDINGS = 400 -- draw passed over ("rare") seeds one anyway from this size on
D.SAT_OBSTACLE_R = 1900    -- m: obstacles (ot_engine.obstacles) read around the town centre for the site search
-- (2026-10-15, §64: retired. In run 2026-10-15_0539_sqot every founding slot went to a streets-only seed (5 of 5), the
-- seeds stayed bare crossings (Two Waters' at -873:917: one dose, never filled), and a town's seed held its job's pacing
-- verdict, so its Works / district never got a turn. New seeds only with STREET_SAT; a satellite already in a save (its
-- frame's `sat`) is restored and grows as before; the dev tools' forced crossroads hamlet still seeds one.)
D.STREET_SAT = false

-- Offshoot size and turns (2026-10-14, run 2026-10-14_0302_sqot-sqrl: 3 satellites, 0 districts, 0 Works against 8 / 9 /
-- 3 the run before, because their decisions came only with demand builds (20 against 170 with the brake) and their
-- gates counted buildings, which a denser town has fewer of). The size a satellite / Works / district gate reads is
-- the town's buildings or its persons / OFFSHOOT_PB, whichever is more (300 buildings ~ 1200 persons), and a town
-- that needs no streets gets an offshoot turn (snapshot, the three decisions and a waiting link, nothing else) at most
-- every OFFSHOOT_TURN_S while one of them is still open. OFFSHOOT event=turn lines.
D.OFFSHOOT_TURN = true
D.OFFSHOOT_TURN_S = 240
D.OFFSHOOT_PB = 4

--- The size (in buildings) the offshoot gates read: buildings, or persons (caps.actual) / OFFSHOOT_PB if more.
function D.offshootSize(buildings, caps)
	local b = buildings or 0
	local p = caps and tonumber(caps.actual) or 0
	return math.max(b, math.floor(p / D.OFFSHOOT_PB))
end

--- Is a town that needs no streets due for an offshoot turn? Returns due (bool), what ("satellite" | "works" |
--- "district" | "link"). Cheap: the town state, the saved sets and the gates' sizes only.
function Driver:offshootTurnDue(t, m, now, saved)
	if not D.OFFSHOOT_TURN or self.newMap ~= true or m == nil then return false end
	if self:isOffshootTown(t, saved) then return false end
	local s = self:townState(t)
	if now < (s.offTurnUs or 0) + D.OFFSHOOT_TURN_S * 1e6 then return false end
	local size = D.offshootSize(m.buildings, m.caps)
	local cands = {}
	if s.works then cands[#cands + 1] = s.works end
	for _, d in ipairs(s.districts or {}) do cands[#cands + 1] = d end
	for _, c in ipairs(cands) do
		if c.phase == "link" and now >= (c.linkAfterUs or 0) then return true, "link" end
	end
	-- (staggered offshoots, ot_satpace: no turn for a founding while the town isn't ready or the map's slot is closed)
	if not self:paceTurnOk(t, size, now, saved) then return false end
	local fr = SV.frame(saved, t)
	if D.STREET_SAT and SAT.ON and s.sat == nil and not (fr and fr.sat) and (s.satTries or 0) < D.SAT_TRIES and now >= (s.satNextUs or 0)
		and size >= SAT.MIN_BUILDINGS
		and (not s.satLogged or (size >= D.SAT_QUOTA_BUILDINGS and self:satKnown(saved) < D.SAT_MAP_MIN)) then
		return true, "satellite"
	end
	if self:createBusy(now) then return false end
	-- (§64: the quotas of Works and districts together; a town passed over by the draw stays due while the map is under
	-- its minimum and Works is the kind it lacks)
	local q = self:offshootQuotaState(now, saved)
	if not q.left then return false end
	local worksFallback = q.short and q.fallbackKind == "works" and size >= D.OFF_QUOTA_BUILDINGS
	if D.WORKS and WK.ON and self:offshootAllowed("works") and s.works == nil and not (fr and fr.works)
		and (not s.worksLogged or worksFallback)
		and (s.worksTries or 0) < D.WORKS_TRIES and now >= (s.worksNextUs or 0) and size >= WK.MIN_BUILDINGS
		and self:worksKnown(saved) < q.worksQuota then
		return true, "works"
	end
	local count = #(s.districts or {})
	if count == 0 and fr and (fr.districts or 0) > 0 then count = fr.districts end
	local districtWait = s.districtLogged == "rare:quotaWait"
		and not (q.short and q.fallbackKind == "district" and size >= D.OFF_QUOTA_BUILDINGS)
	if D.DISTRICTS and DT.ON and self:offshootAllowed("district") and (s.districtTries or 0) < D.DISTRICT_TRIES
		and now >= (s.districtNextUs or 0) and count < DT.MAX_PER_TOWN and not districtWait
		and size >= (count == 0 and DT.MIN_BUILDINGS or DT.SECOND_BUILDINGS)
		and self:districtKnown(saved) < q.districtQuota then
		return true, "district"
	end
	return false
end

--- Decides at the snapshot whether this demand build seeds or grows the town's satellite (job.satPlan), and puts
--- the meadow between town and satellite into the town's style (style.greens).
function Driver:satelliteDecide(job, now, saved)
	-- (dev: a forced crossroads hamlet motif (Grow now) seeds its hamlet at once, M2)
	local forcedHamlet = job.force and job.motif == "crossroads_hamlet" and not job.dry
	if not SAT.ON or job.dry or (job.force and not forcedHamlet) then return end
	local t, E = job.town, self.E
	-- (a town the mod created, ot_works / ot_district: no satellite village of its own)
	if self:isOffshootTown(t, saved) then return end
	local s = self:townState(t)
	if s.sat == nil then
		local fr = SV.frame(saved, t)
		if fr and fr.sat then
			local cx, cy = (s.pos and s.pos[1]) or job.ext.cx, (s.pos and s.pos[2]) or job.ext.cy
			s.sat = { x = fr.sat[1], y = fr.sat[2], restored = true, link = { { cx, cy }, { fr.sat[1], fr.sat[2] } },
				linkLen = G.dist(cx, cy, fr.sat[1], fr.sat[2]) }
		end
	end
	local style = job.style
	-- (a retired satellite, 2026-10-14: its meadow gap goes, so the town may grow toward it; no more streets)
	if s.sat and s.sat.retired then
		if style and style._satGreens == s.sat then
			local drop = {}
			for _, gr in ipairs(s.sat.greens or {}) do drop[gr] = true end
			local greens = {}
			for _, gr in ipairs(style.greens or {}) do if not drop[gr] then greens[#greens + 1] = gr end end
			style.greens, style._satGreens = greens, "retired"
		end
		return
	end
	if s.sat and style and style._satGreens ~= s.sat then
		local greens = {}
		for _, gr in ipairs(style.greens or {}) do greens[#greens + 1] = gr end
		s.sat.greens = SAT.gapGreens(s.sat)
		for _, gr in ipairs(s.sat.greens) do greens[#greens + 1] = gr end
		style.greens, style._satGreens = greens, s.sat
	end
	local turn = job.trigger == "demand" or job.trigger == "offshoot"
	if (not turn and not forcedHamlet) or (now < (s.satNextUs or 0) and not forcedHamlet) then return end
	if s.sat then
		if job.trigger == "offshoot" then return end   -- (a satellite grows with the town's demand builds only)
		-- growth: every EVERY-th demand build, while its houses keep up and it is under MAX_EDGES
		local n = (s.demandBuilds or 0) + 1
		local near = SAT.buildingsNear(s.sat, job.pts)
		local edges = s.sat.edges or SAT.CORE_EDGES
		-- (2026-10-14, ot_satpace: every EVERY_K-th demand build per pod, seeded, once town and map grew: paceGrowDue)
		if not s.sat.full and edges < SAT.MAX_EDGES and near >= SAT.HOUSED_PER_EDGE * edges
			and self:paceGrowDue(job, s, n, now, saved) then
			job.satPlan = { kind = "grow", site = s.sat, near = near }
		end
		return
	end
	if (s.satTries or 0) >= D.SAT_TRIES then return end
	-- (§64: no new streets-only seeds; the town's offshoots are named towns, ot_works / ot_district)
	if not D.STREET_SAT and not forcedHamlet then
		if not s.satLogged then
			s.satLogged = true
			self:debug("SATELLITE", { { "town", t }, { "on", false }, { "why", "retired" } })
		end
		return
	end
	local nb0 = D.offshootSize(job.pts and #job.pts or 0, job.caps)
	-- (the crossroads hamlet motif, M2: the satellite goes beside its crossroads; smaller towns, no seeded draw)
	local hamlet = style and style.hamlet or nil
	local ok, why = SAT.eligible({ seed = style and style.seed, dv = style and style.drawV, buildings = nb0,
		styleId = style and style.id, metro = style and style.metro ~= nil, has = false, hamlet = hamlet })
	-- map quota (2026-10-13, round 5: "at least 1-3 per map"): a big town passed over by the seeded draw seeds one while
	-- the map has fewer than SAT_MAP_MIN known this session
	if not ok and why == "rare" and nb0 >= D.SAT_QUOTA_BUILDINGS and self:satKnown(saved) < D.SAT_MAP_MIN then
		ok, why = true, "quota"
	end
	if not ok then
		if why ~= "small" and not s.satLogged then
			s.satLogged = true
			self:debug("SATELLITE", { { "town", t }, { "on", false }, { "why", why } })
		end
		return
	end
	-- (staggered offshoots, ot_satpace: the town ready, the map's slot open, the draw won; a forced hamlet goes at once)
	if not forcedHamlet and self:paceGate(job, "seed", now, saved) ~= "found" then return end
	local deadEnds = {}
	for n, ji in pairs(job.joinInfo or {}) do
		local node = job.g.nodeById[n]
		if node then deadEnds[#deadEnds + 1] = { node.x, node.y, n } end
	end
	table.sort(deadEnds, function(a, b) return a[3] < b[3] end)
	local roads = {}
	for _, ed in ipairs(job.edges or {}) do
		if not isTownTemplate(ed.template) and not ed.owned then
			roads[#roads + 1] = { (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2 }
		end
	end
	local pos = s.pos or { job.ext.cx, job.ext.cy }
	local nbs = {}
	for _, nb in ipairs(self:neighbours(t, pos)) do
		local x, y = E.boxCentre(nb.town)
		if x then nbs[#nbs + 1] = { x, y } end
	end
	local t0 = self:nowUs()
	-- (2026-10-13: the snapshot holds only the town's streets; fields, tracks, country roads and constructions out at the
	-- site come from a wider read)
	local obstacles = E.obstacles and E.obstacles(pos[1], pos[2], D.SAT_OBSTACLE_R) or nil
	-- (country-road crossroads nearer this town: hamlet sites, ot_roads via countryRoads)
	local junctions = {}
	for _, j in ipairs(s.roads and s.roads.junctions or {}) do
		if j.own ~= false then junctions[#junctions + 1] = j end
	end
	-- (§63: sites and links keep off the woods, unless the town is a deep forest town)
	local satDeep = (style and (style.deep ~= nil or FO.isDeep(style.forest))) or false
	local site, n = SAT.pickSite({ cx = pos[1], cy = pos[2], r = job.ext.r, sampler = job.sampler or E.sampler(),
		seed = style and style.seed, industry = s.ind, neighbours = nbs, roads = roads, deadEnds = deadEnds,
		bounds = self:mapBounds(now), g = job.g, obstacles = obstacles, bad = s.satBad, junctions = junctions,
		hamlet = hamlet, forest = s.forest, deep = satDeep })
	-- (R5 2026-10-13: the crossroads hamlet was always `waiting`: its junction's quadrants found no site (Towcester
	-- noHamletSite). It now falls back to the town's normal satellite search with that junction among the crossroads
	-- (HAMLET_BONUS): a village near the crossroads, else on the ring)
	if site == nil and hamlet ~= nil and n == "noHamletSite" then
		local js = { hamlet }
		for _, j in ipairs(junctions or {}) do if j ~= hamlet then js[#js + 1] = j end end
		site, n = SAT.pickSite({ cx = pos[1], cy = pos[2], r = job.ext.r, sampler = job.sampler or E.sampler(),
			seed = style and style.seed, industry = s.ind, neighbours = nbs, roads = roads, deadEnds = deadEnds,
			bounds = self:mapBounds(now), g = job.g, obstacles = obstacles, bad = s.satBad, junctions = js,
			forest = s.forest, deep = satDeep })
		why = why .. ":hamletFallback"
		if site == nil and type(n) == "string" then n = n .. ":hamletFallback" end
	end
	if site and E.closestTown and E.closestTown(site.x, site.y) ~= t then site, n = nil, "otherTown" end
	if site == nil then
		s.satNextUs = now + D.SAT_RETRY_S * 1e6
		s.satTries = (s.satTries or 0) + 1
		self:paceRefund(t, "seed:" .. tostring(n), job)
		self:log("SATELLITE", { { "town", t }, { "name", E.name(t) }, { "seed", "none" }, { "why", n },
			{ "us", self:nowUs() - t0 } })
		return
	end
	job.satPlan = { kind = "seed", site = site, cands = n, us = self:nowUs() - t0, why = why,
		obst = obstacles and string.format("%d/%d", #obstacles.segs, #obstacles.boxes) or "-" }
end

--- Satellites known this session (seeded, built or restored from a saved frame), for the map quota.
function Driver:satKnown(saved)
	local n, seen = 0, {}
	for t, st in pairs(self.towns or {}) do
		if st.sat then n = n + 1; seen[tostring(t)] = true end
	end
	if type(saved) == "table" and type(saved.frames) == "table" then
		for k, f in pairs(saved.frames) do
			if not seen[tostring(k)] and type(f) == "table" and f.sx ~= nil then n = n + 1 end
		end
	end
	return n
end

--- A seed that was refused or came out empty: its site is skipped from now on, the next try comes sooner.
function Driver:satSeedFailed(job, now)
	local s = self:townState(job.town)
	local sp = job.satPlan
	self:paceRefund(job.town, "seed:failed")
	s.satNextUs = now + D.SAT_REFUSED_RETRY_S * 1e6
	s.satTries = (s.satTries or 0) + 1
	if sp and sp.site then
		s.satBad = s.satBad or {}
		s.satBad[#s.satBad + 1] = { sp.site.x, sp.site.y }
	end
end

--- Plans the satellite increment (seed: link + core; grow: one block on from its dead ends) and goes on as Driver:plan.
function Driver:satellitePlan(job, now)
	local E, t = self.E, job.town
	local s = self:townState(t)
	local sp = job.satPlan
	local t0 = self:nowUs()
	local streets
	if sp.kind == "seed" then streets = SAT.streets(sp.site)
	else streets = SAT.growStreets(job.g, sp.site, job.style.seed) end
	local maxEdges = sp.kind == "seed" and 60 or SAT.GROW_EDGES
	local inc = PL.plan(job.g, streets, { terrain = job.sampler, maxSeg = core.MAX_SEG_FLAT, snapR = 8, minLen = 10,
		minAngle = 25, maxGrade = job.style.maxSlope, waterSetback = job.style.waterSetback, maxEdges = maxEdges,
		join = "deadEnd", templatePaths = job.style.templatePaths })
	inc.mix = core.mix(inc)
	-- (2026-10-14 late: the seed's link goes out as the era's locked country lane, ot_lead.mark: no lots, no empty town
	-- street; its first edge at the town's dead end stays a town street. SATELLITE `laneEdges= laneLen=`)
	local laneN, laneLen = 0, 0
	if sp.kind == "seed" and SAT.LINK_COUNTRY then
		local path = LN.templateFor(job.style)
		if not (E.templateExists and not E.templateExists(path)) then
			local okM, a, _, c = pcall(LD.mark, inc, streets, path)
			if okM then laneN, laneLen = a or 0, c or 0 end
		end
	end
	sp.laneEdges, sp.laneLen = laneN, laneLen
	local linkEdges, coreEdges = 0, 0
	for _, e in ipairs(inc.edges) do
		local st = streets[e.street]
		if st and st.sat == "link" then linkEdges = linkEdges + 1 else coreEdges = coreEdges + 1 end
	end
	local linkOk = sp.kind ~= "seed" or (linkEdges > 0 and coreEdges > 0 and coreEdges <= SAT.CORE_EDGES)
	-- the link must reach the site: its last accepted edge ends within 10 m of it
	if sp.kind == "seed" and linkOk then
		local reach = false
		for _, e in ipairs(inc.edges) do
			local st = streets[e.street]
			if st and st.sat == "link" and (G.dist(e.p1[1], e.p1[2], sp.site.x, sp.site.y) <= 10
				or G.dist(e.p0[1], e.p0[2], sp.site.x, sp.site.y) <= 10) then reach = true end
		end
		linkOk = reach
	end
	local dropped = {}
	for _, d in ipairs(inc.dropped or {}) do dropped[d.reason] = (dropped[d.reason] or 0) + 1 end
	local dt = {}
	for k, v in pairs(dropped) do dt[#dt + 1] = k .. ":" .. v end
	table.sort(dt)
	self:log("SATELLITE", { { "town", t }, { "name", E.name(t) }, { "kind", sp.kind },
		{ "site", string.format("%.0f:%.0f", sp.site.x, sp.site.y) }, { "dist", sp.site.dist and string.format("%.0f", sp.site.dist) or "-" },
		{ "link", sp.site.linkLen and string.format("%.0f", sp.site.linkLen) or "-" }, { "road", sp.site.road == true },
		{ "low", sp.site.low == true }, { "slope", sp.site.slope and string.format("%.3f", sp.site.slope) or "-" },
		{ "score", sp.site.score and string.format("%.2f", sp.site.score) or "-" }, { "cands", sp.cands or "-" },
		{ "edges", #inc.edges }, { "linkEdges", linkEdges }, { "coreEdges", coreEdges }, { "near", sp.near or 0 },
		{ "dropped", #dt > 0 and table.concat(dt, "/") or "-" }, { "ok", linkOk and #inc.edges > 0 },
		{ "why", sp.why or "-" }, { "obst", sp.obst or "-" }, { "tries", s.satTries or 0 },
		{ "at", sp.site.at or "-" }, { "junction", sp.site.junction and string.format("%.0f@%.0f", G.dist(sp.site.x,
			sp.site.y, sp.site.junction.x, sp.site.junction.y), sp.site.junction.d) or "-" },
		{ "light", sp.site.light and string.format("%.0f", sp.site.light) or "-" },
		{ "laneEdges", sp.laneEdges or 0 }, { "laneLen", string.format("%.0f", sp.laneLen or 0) },
		{ "straight", sp.kind == "seed" and sp.site.link and string.format("%.0f", G.maxStraightRun(sp.site.link, SAT.STRAIGHT_TOL)) or "-" },
		{ "us", (sp.us or 0) + self:nowUs() - t0 } })
	if sp.kind == "grow" and #inc.edges == 0 then
		-- the core has no room left to grow compactly: done with it; this build goes to the town as usual
		s.sat.full = true
		job.satPlan = nil
		return self:plan(job, now)
	end
	if #inc.edges == 0 or not linkOk then
		if sp.kind == "seed" then self:satSeedFailed(job, now) else s.satNextUs = now + D.SAT_RETRY_S * 1e6 end
		job.why = "satellite:" .. (#inc.edges == 0 and "empty" or "link")
		return self:finish(t, "empty", now)
	end
	job.inc, job.mp, job.report = inc, nil, nil
	-- every satellite street locked (no game side streets into the meadow); no fill (no forced growth)
	local keys, n = {}, 0
	for _, e in ipairs(inc.edges) do
		if e.key ~= nil and not keys[e.key] then keys[e.key] = true; n = n + 1 end
	end
	job.lockKeys, job.lockN, job.lockModeUsed = keys, n, "satellite"
	job.fill = "off"
	-- (2026-10-14 late: the seed's core, at the end of its lane, gets a dose like a lane ahead's far end: its houses
	-- start there instead of waiting for the town to reach them)
	if sp.kind == "seed" and SAT.CORE_FILL then
		job.fillPts = LD.endFillPoints(inc, streets, D.FILL_OFFSET, D.FILL_POINTS)
		if #job.fillPts > 0 then job.fill = "dose" else job.fillPts = nil end
	end
	job.satCoreEdges = coreEdges
	job.stage = "send"
end

--- The satellite's watch at a check of its town (2026-10-14, SAT.watch): a core dose once its lots exist (the seed's
--- own came before them), and a satellite still empty after its doses is retired (SATELLITE retire: no more streets,
--- the meadow gap released). A dose is a fill job of its own on this check (FILL kind=dose why=satCore; the CHECK's
--- build waits for the next check). Returns true when the job went on to the fill.
function Driver:satWatch(job, m, now)
	local t, E = job.town, self.E
	local s = self:townState(t)
	local st = s.sat
	if st == nil or st.retired or st.x == nil or m == nil or m.pts == nil then return false end
	local near = SAT.buildingsNear(st, m.pts)
	local what = SAT.watch(st, near, now)
	if what == "retire" then
		st.retired, st.full = true, true
		self:log("SATELLITE retire", { { "town", t }, { "name", E.name(t) }, { "site", string.format("%.0f:%.0f", st.x, st.y) },
			{ "edges", st.edges or 0 }, { "doses", st.doses or 0 }, { "checks", st.emptyChecks or 0 }, { "near", near },
			{ "restored", st.restored == true } })
		return false
	end
	if what ~= "dose" then return false end
	-- (the dev Simulate's rounds: its Fast fill doesn't reach the satellite either, so the core dose still goes)
	return self:coreDose(job, m, now, st, st.dosePts or SAT.corePoints(st, D.FILL_OFFSET), "satCore", near)
end

--- A dose of its own at a check (the satellite's core, a bridge's far bank; 2026-10-14): DevelopAt at pts as a fill job
--- (FILL kind=dose why=<why>; restore and reactivate as every dose). st counts the doses (st.doses, st.lastDoseUs).
--- Returns true when the job went on to the fill.
function Driver:coreDose(job, m, now, st, pts, why, near)
	local t, E = job.town, self.E
	local s = self:townState(t)
	if E.developAt == nil or m.caps == nil or m.caps.initials == nil or pts == nil or #pts == 0 then return false end
	st.doses = (st.doses or 0) + 1
	st.lastDoseUs = now
	local caps = m.caps
	local rec = { us = now, kind = "dose", buildings0 = m.buildings or 0, cap0 = caps.actual or 0, target0 = caps.target or 0,
		initial0 = caps.initial, initials0 = { caps.initials[1], caps.initials[2], caps.initials[3] },
		sf0 = caps.sizeFactors and { caps.sizeFactors[1], caps.sizeFactors[2], caps.sizeFactors[3] } or nil, points = {},
		streets = false, upgrade = false, active0 = caps.active }
	if s.devBefore == nil and caps.active ~= nil then s.devBefore = caps.active end
	if s.baseInitial == nil then
		local fr = SV.frame(self.saved, t)
		s.baseInitial = (fr and fr.initial) or caps.initial or nil
	end
	local ptxt = {}
	for i, p in ipairs(pts) do
		rec.points[i] = { p[1], p[2], D.countNear(m.pts, p[1], p[2], D.FILL_NEAR), D.countNear(m.pts, p[1], p[2], D.FILL_FAR) }
		ptxt[#ptxt + 1] = string.format("%.0f:%.0f", p[1], p[2])
	end
	s.fill = rec
	s.fills = (s.fills or 0) + 1
	self.counts.fills = (self.counts.fills or 0) + #pts
	self:log("FILL", { { "town", t }, { "name", E.name(t) }, { "kind", "dose" }, { "why", why }, { "points", #pts },
		{ "dose", st.doses }, { "of", SAT.REDOSES }, { "near", near or 0 }, { "at", table.concat(ptxt, "/") },
		{ "sinceS", string.format("%.0f", (now - (st.us or now)) / 1e6) } })
	job.pts, job.caps = m.pts, m.caps
	job.fillRun = { pts = pts, i = 0, ok = 0, rec = rec, outcome = "room" }
	job.stage = "fill"
	return true
end

--- The bridge's far bank (2026-10-14, ot_bridge CROSS_LATER): a dose beside the far street's end once its lots exist
--- (SAT.watch timing), up to SAT.REDOSES; no retire (the planner grows the quarter from C once houses stand).
D.BRIDGE_NEAR_R = 150
function Driver:bridgeWatch(job, m, now)
	local s = self:townState(job.town)
	local st = s.bridgeEnd
	if st == nil or st.done or m == nil or m.pts == nil then return false end
	local near = D.countNear(m.pts, st.x, st.y, D.BRIDGE_NEAR_R)
	local what = SAT.watch(st, near, now)
	if what == "retire" or (near > 0) then
		st.done = true
		self:debug("BRIDGE", { { "town", job.town }, { "event", "farBank" }, { "near", near }, { "doses", st.doses or 0 } })
		return false
	end
	if what ~= "dose" then return false end
	return self:coreDose(job, m, now, st, st.pts, "bridgeEnd", near)
end

--- After a satellite build: the town's satellite state, the saved site (seed), SATELLITE built line.
function Driver:satelliteBuilt(job, now)
	local s = self:townState(job.town)
	local sp = job.satPlan
	if sp.kind == "seed" then
		s.sat = { x = sp.site.x, y = sp.site.y, link = sp.site.link, linkLen = sp.site.linkLen, dist = sp.site.dist,
			edges = job.satCoreEdges or 0, builds = 1, us = now, at = sp.site.at, junction = sp.site.junction,
			dosePts = job.fillPts, doses = 0, podMark = D.offshootSize(job.pts and #job.pts or 0, job.caps) }
		self.E.sendEvent(SV.EVENT_ID, SV.EV_SAT, { town = job.town, x = math.floor(sp.site.x * 1000 + 0.5) / 1000,
			y = math.floor(sp.site.y * 1000 + 0.5) / 1000 })
		job.style._satGreens = nil   -- the meadow discs go in at the next snapshot
	else
		s.sat.edges = (s.sat.edges or SAT.CORE_EDGES) + (job.satCoreEdges or 0)
		s.sat.builds = (s.sat.builds or 0) + 1
	end
	self:log("SATELLITE built", { { "town", job.town }, { "kind", sp.kind }, { "edges", #job.spec.edges },
		{ "coreEdges", s.sat.edges }, { "builds", s.sat.builds }, { "near", sp.near or 0 } })
end

---------------------------------------------------------------------------
-- Country lanes laid well ahead (ot_lead, 2026-10-13, round after the names run: "Country roads built way off in
-- advance would make more sense, and then offshoots of streets at the end"): at a demand build a seeded share of the
-- young towns (map quota) lays one locked country lane from a dead end at its edge toward a neighbour / along its axis /
-- toward its satellite, with a few unlocked town streets at its far end for the town to grow on later. LEADLANE lines:
-- decide (none / plan), refused / failed, built. The frame keeps `ld` once built (EV_LEAD: never a second one).
D.LEAD_RETRY_S = 300      -- after no site / a refusal: the next try this much later (real s)
D.LEAD_TRIES = 3          -- tries per town and session

--- Lanes ahead known this session or saved (the map quota).
function Driver:leadKnown(saved)
	local n, seen = 0, {}
	for t, st in pairs(self.towns or {}) do
		if st.leadDone and st.leadBuilt then n = n + 1; seen[tostring(t)] = true end
	end
	if type(saved) == "table" and type(saved.frames) == "table" then
		for k, f in pairs(saved.frames) do
			if not seen[tostring(k)] and type(f) == "table" and tonumber(f.ld) == 1 then n = n + 1 end
		end
	end
	return n
end

--- Decides at the snapshot of a demand build whether this town lays its lane ahead now (job.leadPlan).
function Driver:leadDecide(job, now, saved)
	if not LD.ON or job.dry or job.force or job.trigger ~= "demand" then return end
	local t, E = job.town, self.E
	if self:isOffshootTown(t, saved) then return end
	-- (districts instead of long arms and lanes ahead, 2026-10-14)
	if D.DISTRICTS and self:hasDistrict(t, saved) then return end
	local s = self:townState(t)
	if s.leadDone or (s.leadTries or 0) >= D.LEAD_TRIES or now < (s.leadNextUs or 0) then return end
	local fr = SV.frame(saved, t)
	if fr and fr.lead then s.leadDone = true return end
	local style = job.style
	local nb0 = job.pts and #job.pts or 0
	local quotaLeft = self:leadKnown(saved) < LD.quota(#self:townIds(now))
	local ok, why = LD.eligible({ seed = style and style.seed, dv = style and style.drawV, buildings = nb0, metro = style and style.metro ~= nil,
		styleId = style and style.id, quotaLeft = quotaLeft, has = false, chanceMul = RCI.chanceMul(self:rciLean(t), "lead") })
	if not ok then
		if why ~= "small" and why ~= "quota" and not s.leadLogged then
			s.leadLogged = true
			self:debug("LEADLANE", { { "town", t }, { "name", E.name(t) }, { "on", false }, { "why", why } })
		end
		if why == "rare" or why == "metro" or why == "style" or why == "big" then s.leadDone = true end
		return
	end
	local deadEnds = {}
	for n in pairs(job.joinInfo or {}) do
		local node = job.g.nodeById[n]
		if node then deadEnds[#deadEnds + 1] = { node.x, node.y, n } end
	end
	table.sort(deadEnds, function(a, b) return a[3] < b[3] end)
	local roads = {}
	for _, ed in ipairs(job.edges or {}) do
		if not isTownTemplate(ed.template) and not ed.owned then
			roads[#roads + 1] = { (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2 }
		end
	end
	local pos = s.pos or { job.ext.cx, job.ext.cy }
	local t0 = self:nowUs()
	local targets = LD.targets({ cx = pos[1], cy = pos[2], neighbours = self:neighbours(t, pos),
		axis = style.shape and style.shape.axis or nil, sat = s.sat and { s.sat.x, s.sat.y } or nil, frameAxis = style.axis })
	local obstacles = E.obstacles and E.obstacles(pos[1], pos[2], D.SAT_OBSTACLE_R) or nil
	local site, n = LD.pick({ cx = pos[1], cy = pos[2], r = job.ext.r, sampler = job.sampler or E.sampler(),
		seed = style.seed, dv = style.drawV, deadEnds = deadEnds, targets = targets, gaps = style.gaps, bounds = self:mapBounds(now),
		g = job.g, obstacles = obstacles, roads = roads, forest = style.forest,
		owner = E.closestTown and function(x, y)
			local ct = E.closestTown(x, y)
			return ct == nil or ct == t
		end or nil })
	if site == nil then
		s.leadTries = (s.leadTries or 0) + 1
		s.leadNextUs = now + D.LEAD_RETRY_S * 1e6
		self:log("LEADLANE", { { "town", t }, { "name", E.name(t) }, { "outcome", "none" }, { "why", n },
			{ "targets", #targets }, { "deadEnds", #deadEnds }, { "tries", s.leadTries }, { "us", self:nowUs() - t0 } })
		return
	end
	job.leadPlan = { site = site, cands = n, us = self:nowUs() - t0 }
end

--- Plans the lane ahead (ot_lead.streets + ot_plan), marks its country edges and goes on to send; a lane that came
--- out short or without its country stretch hands the build back to the town's normal plan.
function Driver:leadPlanStage(job, now)
	local E, t = self.E, job.town
	local s = self:townState(t)
	local lp = job.leadPlan
	local t0 = self:nowUs()
	local streets = LD.streets(lp.site)
	local inc = PL.plan(job.g, streets, { terrain = job.sampler, maxSeg = core.MAX_SEG_FLAT, snapR = 8, minLen = 10,
		minAngle = 25, maxGrade = job.style.maxSlope, waterSetback = job.style.waterSetback, maxEdges = 40,
		join = "deadEnd", templatePaths = job.style.templatePaths })
	inc.mix = core.mix(inc)
	local path = LN.templateFor(job.style)
	local okT = not (E.templateExists and not E.templateExists(path))
	local lane, ends, len = 0, 0, 0
	if okT then lane, ends, len = LD.mark(inc, streets, path) end
	-- the lane must reach its far end: an edge of the lane street ending within 10 m of it
	local far = lp.site.pts[#lp.site.pts]
	local reach = false
	for _, e in ipairs(inc.edges) do
		local st = streets[e.street]
		if st and st.lead == "lane" and (G.dist(e.p1[1], e.p1[2], far[1], far[2]) <= 10 or G.dist(e.p0[1], e.p0[2], far[1], far[2]) <= 10) then
			reach = true
		end
	end
	if lp.site.endKind == "ribbon" then reach = reach or ends > 0 end
	-- (the far end's town streets must hang on the lane: one network with the joined first edge, else they'd be a loose
	-- street the town never houses)
	local endJ, endN = LD.endJoined(inc, streets)
	local why = (not okT and "template") or (lane == 0 and "noLane") or (not reach and "short")
		or (endJ < endN and "endLoose") or nil
	self:log("LEADLANE", { { "town", t }, { "name", E.name(t) }, { "outcome", why and "dropped" or "plan" },
		{ "target", lp.site.target }, { "heading", string.format("%.0f", math.deg(lp.site.heading)) },
		{ "len", string.format("%.0f", lp.site.len) }, { "laneEdges", lane }, { "laneLen", string.format("%.0f", len) },
		{ "endKind", lp.site.endKind }, { "endEdges", ends }, { "endJoined", string.format("%d/%d", endJ, endN) }, { "edges", #inc.edges },
		{ "cover", string.format("%.2f", lp.site.cover or 0) }, { "grade", string.format("%.3f", lp.site.grade or 0) },
		{ "deadEnd", lp.site.deadEnd[3] }, { "template", path:match("([%w_]+)%.street_template$") or path },
		{ "why", why or "-" }, { "us", (lp.us or 0) + self:nowUs() - t0 } })
	if why then
		s.leadTries = (s.leadTries or 0) + 1
		s.leadNextUs = now + D.LEAD_RETRY_S * 1e6
		LN.strip(inc)
		job.leadPlan = nil
		return self:plan(job, now)
	end
	job.inc, job.mp, job.report = inc, nil, nil
	-- (the lane locks as a country edge in ot_proposal; the far end's town streets stay unlocked: the game grows there)
	job.lockKeys, job.lockN, job.lockModeUsed = {}, 0, "lead"
	-- (round after the 2240 run: the far end gets a dose, so its houses start there; the lane itself none)
	job.fillPts = LD.endFillPoints(inc, streets, D.FILL_OFFSET, D.FILL_POINTS)
	job.fill = #job.fillPts > 0 and "dose" or "off"
	job.leadLane = lane
	job.stage = "send"
end

--- After the lane ahead was built: the town's state, the saved flag, LEADLANE built.
function Driver:leadBuilt(job, now)
	local s = self:townState(job.town)
	local lp = job.leadPlan
	s.leadDone, s.leadBuilt = true, { x = lp.site.pts[#lp.site.pts][1], y = lp.site.pts[#lp.site.pts][2], us = now }
	self.E.sendEvent(SV.EVENT_ID, SV.EV_LEAD, { town = job.town })
	local n = 0
	for _, e in ipairs(job.spec and job.spec.edges or {}) do if e.forestLane then n = n + 1 end end
	self:log("LEADLANE", { { "town", job.town }, { "name", self.E.name(job.town) }, { "outcome", "built" },
		{ "edges", job.spec and #job.spec.edges or 0 }, { "laneEdges", n }, { "endKind", lp.site.endKind },
		{ "far", string.format("%.0f:%.0f", s.leadBuilt.x, s.leadBuilt.y) } })
end

--- A refused / failed lane ahead: another try later (LEAD_RETRY_S), LEADLANE line.
function Driver:leadFailed(job, now, why, fields)
	local s = self:townState(job.town)
	s.leadTries = (s.leadTries or 0) + 1
	s.leadNextUs = now + D.LEAD_RETRY_S * 1e6
	local lf = { { "town", job.town }, { "outcome", "refused" }, { "why", why } }
	for _, f in ipairs(fields or {}) do
		if f[1] == "msgs" or f[1] == "collisions" or f[1] == "partners" then lf[#lf + 1] = f end
	end
	lf[#lf + 1] = { "tries", s.leadTries }
	self:log("LEADLANE", lf)
end

---------------------------------------------------------------------------
-- Industrial satellite towns, "Works" (ot_works, 2026-10-13, round after the names run; the dev probe SATIND proved the
-- path in run 2026-10-13_2113_sqot-dev): on a map that was new when the mod first saw it, a seeded share of the grown
-- towns (map quota) gets a small industrial-heavy town 0.8-1.5 km out (by a harbour / station / across water best),
-- made with makeTownCreateCmd (initial capacities WK.CAPS) and filled once; at the parent's next demand build after
-- WORKS_LINK_DELAY_S a road links the two (a country lane between two joined town-street ends). WORKS lines: decide
-- (none), create, created / refused, link (plan / none / dropped), linked / refused. Saved: `wk` (the created towns) and
-- the parent frame's `wp` (EV_WORKS): never a second one; a Works town gets no satellite, lane ahead or Works itself.
D.WORKS = true
D.WORKS_TRIES = 2             -- site / create tries per town and session
D.WORKS_RETRY_S = 300
D.WORKS_CREATE_TIMEOUT_S = 30
D.WORKS_LINK_DELAY_S = 20     -- real s after the creation before the link (its streets are laid out)
D.WORKS_LINK_TRIES = 5       -- (3 until 2026-10-14)
-- (2026-10-14, run 2026-10-14_0613_sqot: every failed link had one try: the 300 s retry never came in a 3-minute Quick
-- run. A failed link is tried again after WORKS_LINK_RETRY_S, with another seed for the routes' bends)
D.WORKS_LINK_RETRY_S = 60
D.WORKS_READ_R = 450          -- m around the Works town: its streets added to the link job's network
D.WORKS_HARBOUR_S = 120       -- the harbour listing re-read after this
D.OFFSHOOT_HOLD_B = 120       -- buildings: a Works / district town below this gets no mod streets (assess)
-- (NEXT_PHASE_BRIEF 52.3, 2026-10-14) held towns get no mod streets of any kind:
D.HOLD_EMPTY_GROWTH = true    -- ... nor a town whose growth is empty (A.growthEmpty; the head start excepted)
D.HOLD_GUARD = true           -- ... nor other towns' plans in a held created town's land (send: E.closestTown)
D.HOLD_GUARD_R = 1500         -- m: new edges this close to a held created town are asked for their closest town
D.HOLD_GUARD_MAX = 64         -- held created towns read per send at most
D.HOLD_REPLANS = 2            -- a town plan with pieces in a held town: planned again without them this often

--- Why town t gets no mod streets now ("below": a Works / district town under OFFSHOOT_HOLD_B buildings; "noGrowth":
--- its growth is empty, A.growthEmpty), or nil. m = a measure ({ buildings, caps }); job may be nil.
function Driver:holdWhy(t, m, job, saved)
	if m == nil then return nil end
	if self:isOffshootTown(t, saved) then
		if (tonumber(m.buildings) or 0) < D.OFFSHOOT_HOLD_B then return "below" end
		if D.HOLD_EMPTY_GROWTH and A.growthEmpty(m.caps) then return "noGrowth" end
		return nil
	end
	if D.HOLD_EMPTY_GROWTH and not (job and job.head) and A.growthEmpty(m.caps) then return "noGrowth" end
	return nil
end

--- OFFSHOOT event=hold line for a held check: once per town and verdict, again when its street count changed.
function Driver:holdLog(t, m, why)
	local st = self:townState(t)
	local edges = m.lots and m.lots.edges or 0
	local key = tostring(why) .. ":" .. tostring(edges)
	if st.holdLogged == key then return end
	st.holdLogged = key
	self:debug("OFFSHOOT", { { "event", "hold" }, { "town", t }, { "name", self.E.name(t) }, { "why", why },
		{ "edges", edges }, { "buildings", m.buildings }, { "until", why == "below" and D.OFFSHOOT_HOLD_B or "growth" } })
end

--- The created towns other than t that are held (their last check's verdict; a created town not checked yet counts
--- as held: it starts small), with their centres: { { town, x, y, why } }. At most HOLD_GUARD_MAX.
function Driver:heldOthers(t, saved)
	local out, n = {}, 0
	local E = self.E
	for id in pairs(self:createdTowns(saved)) do
		n = n + 1
		if n > D.HOLD_GUARD_MAX then break end
		if id ~= t then
			local s = self.towns[id]
			local why = s and s.hold
			if why == nil then why = "unchecked" end
			if why then
				local x, y = E.boxCentre(id)
				if x ~= nil and y ~= nil and x == x and y == y then out[#out + 1] = { town = id, x = x, y = y, why = why } end
			end
		end
	end
	return out
end

--- The send guard (NEXT_PHASE_BRIEF 52.3): the new edges of job's increment whose closest town is a held created town
--- (other than the job's own town and a Works / district link's own target). Returns hits, the held town hit (or nil).
--- Each hit's key is excluded for the job's town (as the industry zones).
function Driver:heldHits(job)
	local E, t = self.E, job.town
	if not D.HOLD_GUARD or E.closestTown == nil or job.inc == nil then return 0, nil end
	local held = self:heldOthers(t)
	if #held == 0 then return 0, nil end
	local target = job.worksPlan and job.worksPlan.works or nil
	local r2 = D.HOLD_GUARD_R * D.HOLD_GUARD_R
	local hits, who = 0, nil
	for _, e in ipairs(job.inc.edges or {}) do
		if e.p0 and e.p1 and not e.existing then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			local near = false
			for _, h in ipairs(held) do
				if h.town ~= target and (mx - h.x) ^ 2 + (my - h.y) ^ 2 <= r2 then near = true break end
			end
			if near then
				local ct = E.closestTown(mx, my)
				for _, h in ipairs(held) do
					if ct ~= nil and ct == h.town and h.town ~= target then
						hits = hits + 1
						who = who or h
						self:exclude(t, e.key)
						break
					end
				end
			end
		end
	end
	return hits, who
end

--- Is t a Works town (created by the mod: saved or this session)?
function Driver:isWorksTown(t, saved)
	local r = self:root()
	saved = self:savedNow(saved)
	return (self.worksTowns ~= nil and self.worksTowns[t] == true) or (r.worksTowns ~= nil and r.worksTowns[t] == true)
		or SV.worksSet(saved)[t] == true
end

--- Is t a town the mod created (a Works or a district town, saved or this session)? Such a town founds no satellite,
--- lane ahead, Works or district of its own.
function Driver:isOffshootTown(t, saved)
	return self:isWorksTown(t, saved) or self:createdTowns(saved)[t] ~= nil
end

--- Works towns known this session or saved (the map quota).
function Driver:worksKnown(saved)
	local set = SV.worksSet(saved)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	for t, st in pairs(self.towns or {}) do
		local w = st.works
		if w and (w.phase == "create" or ((w.phase == "link" or w.phase == "done") and not set[w.town])) and not w.restored then
			n = n + 1
		end
	end
	return n
end

--- District towns known this session or saved (the map quota).
function Driver:districtKnown(saved)
	local set = SV.districtSet(saved)
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	for _, st in pairs(self.towns or {}) do
		for _, w in ipairs(st.districts or {}) do
			if w.phase == "create" or ((w.phase == "link" or w.phase == "done") and set[w.town] == nil) then n = n + 1 end
		end
	end
	return n
end

-- Offshoot towns per map (2026-10-15, §64; user after run 2026-10-15_0539_sqot: "I don't see any satellite towns",
-- meaning the separately named Works / district towns; agreed: every satellite a real named town, about 2-4 per 16
-- towns, staggered, never zero because of a seeded roll). Works and districts together: at most OFF_PER16[2] per 16
-- towns (the map's own towns, the mod's offshoots not counted), and while the map has fewer than OFF_PER16[1], a town
-- of OFF_QUOTA_BUILDINGS (size units, D.offshootSize) the seeded draw passed over ("rare") founds one anyway
-- (why=quota; the kind the map has fewer of, a district first), like the old satellites' SAT_QUOTA_BUILDINGS. The
-- pacing (ot_satpace) still decides when.
D.OFF_PER16 = { 2, 4 }
D.OFF_QUOTA_BUILDINGS = 400

--- The map's offshoot range for n towns: min, max (min >= 1, max >= min).
function D.offshootQuota(n)
	n = math.max(0, tonumber(n) or 0)
	local mn = math.max(1, math.floor(D.OFF_PER16[1] * n / 16 + 0.5))
	local mx = math.max(mn, math.floor(D.OFF_PER16[2] * n / 16 + 0.5))
	return mn, mx
end

--- The kind a quota founding takes (w / d: Works / districts known, wq / dq: their own quotas): the one the map has
--- fewer of, a district on a tie, nil when both are full.
function D.offshootFallbackKind(w, d, wq, dq)
	if w < d and w < wq then return "works" end
	if d < dq then return "district" end
	if w < wq then return "works" end
	return nil
end

--- The quota fallback on top of a kind's eligible verdict (ok, why): a "rare" town founds one anyway (why "quota")
--- while the map is under its minimum (q.short), this is the kind it lacks (q.fallbackKind) and the town has size
--- OFF_QUOTA_BUILDINGS; smaller, it waits for that (quotaWait: its tries are not used up). Returns ok, why, quotaWait.
function D.offshootFallback(kind, ok, why, size, q)
	if ok or why ~= "rare" or q == nil or not q.short or q.fallbackKind ~= kind then return ok, why, false end
	if (tonumber(size) or 0) >= D.OFF_QUOTA_BUILDINGS then return true, "quota", false end
	return false, why, true
end

--- The map's own towns (the mod's Works / district towns left out) for the offshoot quotas.
function Driver:offshootMapN(now, saved)
	local n = 0
	local okP, mp = pcall(self.paceMap, self, now, saved)
	if okP and mp and (mp.n or 0) > 0 then n = mp.n end
	if n == 0 then
		local created = self:createdTowns(saved)
		for i, t in ipairs(self:townIds(now) or {}) do
			if i > D.PACE_MAX_TOWNS then break end
			if not created[t] then n = n + 1 end
		end
	end
	return n
end

--- Works and district towns known (this session or saved).
function Driver:offshootKnown(saved)
	return self:worksKnown(saved) + self:districtKnown(saved)
end

--- The quota state for a founding of `kind` ("works" | "district"): left (the map's max not reached), short (under its
--- min), fallbackKind (the kind a quota founding takes: the one the map has fewer of, districts on a tie), n, min, max.
function Driver:offshootQuotaState(now, saved)
	local n = self:offshootMapN(now, saved)
	local mn, mx = D.offshootQuota(n)
	local w, d = self:worksKnown(saved), self:districtKnown(saved)
	local known = w + d
	local wq, dq = WK.quota(n), DT.quota(n)
	local fb = D.offshootFallbackKind(w, d, wq, dq)
	return { left = known < mx, short = known < mn, fallbackKind = fb, n = n, min = mn, max = mx, known = known,
		works = w, districts = d, worksQuota = wq, districtQuota = dq }
end

--- The towns paired with t by the mod (its Works and districts, or the parent of a Works / district town): { [id] = true }.
--- The R3 gap between such a pair is waived along their link (ot_gap waive).
function Driver:offshootPartners(t, saved)
	local out = {}
	local s = self.towns and self.towns[t]
	if s then
		if s.works and s.works.town then out[s.works.town] = true end
		for _, w in ipairs(s.districts or {}) do if w.town then out[w.town] = true end end
	end
	local fr = SV.frame(saved, t)
	if fr and fr.works then out[fr.works] = true end
	for d, par in pairs(SV.districtSet(saved)) do
		if par == t then out[d] = true end
		if d == t and par and par > 0 then out[par] = true end
	end
	for d, par in pairs(self.districtTowns or {}) do
		if par == t then out[d] = true end
		if d == t then out[par] = true end
	end
	if type(saved) == "table" and type(saved.frames) == "table" and self:isWorksTown(t, saved) then
		for k, f in pairs(saved.frames) do
			if type(f) == "table" and tonumber(f.wp) == t and tonumber(k) then out[tonumber(k)] = true end
		end
	end
	return out
end

--- Has town t founded a district (this session or saved)? Its arms reach less (DISTRICT_KA).
function Driver:hasDistrict(t, saved)
	local s = self.towns and self.towns[t]
	if s and s.districts and #s.districts > 0 then return true end
	local fr = SV.frame(saved, t)
	return fr ~= nil and (fr.districts or 0) > 0
end

--- The name list's classifier for composed names (stop names' folder, else the names phase's, else the list's
--- fallback; another mod's list: its language, Driver:listLang; else "usa" on a US map, else "en").
function Driver:nameCls(saved)
	if self.stopsCfg and self.stopsCfg.cls then return self.stopsCfg.cls end
	local path = NM.basePath(self.cfg and self.cfg.nameList)
	if path and NM.LISTS[path] then
		local dir = (type(saved) == "table" and type(saved.nd) == "string" and saved.nd) or self.listDir or NM.LISTS[path].langs.fallback
		local cls = NM.classOf(path, dir)
		if cls then return cls end
	elseif path == nil then
		local L = self:listLang()
		if L.cls then return L.cls end
	end
	return self.nameRegion == "US" and "usa" or "en"
end

--- The language of another mod's name list for the towns the mod founds (2026-10-17, NEXT_PHASE_BRIEF 72; the
--- list's own towns and stops keep their names: basePath "notBase"). Once per session: { base = bool, region, country,
--- word (the path word that named the country), cls (a classifier id; false: unused names of the list itself),
--- clsSource ("base" | "country" | "guess" | "list" | "fallback"), guess (the shares, log), list, listPath, tries, why }.
--- The classifier: the country the list's path names (ot_names.countryCls), else a confident guess from the map's town
--- names (ot_names.guessCls, at most GUESS_MAX names), else the list's own towns.lua (Driver:moddedTownList: offshoots
--- take unused names of it, as base lists without a classifier do), else the old composed English / US names.
function Driver:listLang()
	local L = self.nameLang
	if L then return L end
	local nl = self.cfg and self.cfg.nameList
	local path, why = NM.basePath(nl)
	local region, country, word = I.region(nl)
	L = { base = path ~= nil, region = region, country = country, word = word, tries = 0 }
	self.nameLang = L
	if path then
		L.clsSource = "base"
		return L
	end
	local fb = self.nameRegion == "US" and "usa" or "en"
	if why == "noList" then
		L.cls, L.clsSource, L.why = fb, "fallback", why
		return L
	end
	local E = self.E
	local names = {}
	if E.towns and E.name then
		local okT, ids = pcall(E.towns)
		for i, id in ipairs((okT and type(ids) == "table") and ids or {}) do
			if #names >= NM.GUESS_MAX or i > NM.MAX_TOWNS then break end
			local okN, nm = pcall(E.name, id)
			if okN and type(nm) == "string" then names[#names + 1] = nm end
		end
	end
	local c = NM.countryCls(country, names)
	if c then
		L.cls, L.clsSource = c, "country"
		return L
	end
	local g, gwhy, gtxt = NM.guessCls(names)
	L.guess = gtxt
	if g then
		L.cls, L.clsSource = g, "guess"
		return L
	end
	local list, lpath, lwhy = self:moddedTownList(nl, country, L)
	if list then
		L.cls, L.clsSource, L.list, L.listPath = false, "list", list, lpath
		return L
	end
	L.cls, L.clsSource, L.why = fb, "fallback", tostring(gwhy) .. "+" .. tostring(lwhy)
	return L
end

--- Another mod's towns.lua (ot_names.moddedTownPaths: the game language's folder, the country's, en, common ones; at
--- most MAX_MOD_TRIES requires, each in pcall), or nil and why ("noEngine" | "noPath" | "noTownsFile"). L.tries counts.
function Driver:moddedTownList(nl, country, L)
	local E = self.E
	if E.townListAt == nil then return nil, nil, "noEngine" end
	local lang = nil
	if E.language then
		local okG, code = pcall(E.language)
		if okG and type(code) == "string" then lang = code end
	end
	local paths = NM.moddedTownPaths(nl, lang, NM.COUNTRY_DIR[country or ""])
	if #paths == 0 then return nil, nil, "noPath" end
	for _, p in ipairs(paths) do
		if L then L.tries = (L.tries or 0) + 1 end
		local okL, list = pcall(E.townListAt, p)
		if okL and type(list) == "table" and #list > 0 then return list, p, nil end
	end
	return nil, nil, "noTownsFile"
end

--- The NAMELIST line (once per session at the driver's start): which list, how its region and the founded towns'
--- name language were found.
function Driver:nameListLine(inputs)
	local okL, L = pcall(self.listLang, self)
	if not okL or type(L) ~= "table" then
		self:log("NAMELIST", { { "list", self.cfg and self.cfg.nameList or "nil" }, { "error", tostring(L) } })
		return
	end
	local cls = L.cls
	if L.base then cls = self:nameCls(nil) end
	self:log("NAMELIST", { { "list", self.cfg and self.cfg.nameList or "nil" }, { "base", L.base },
		{ "region", inputs and inputs.region or self.region or "-" },
		{ "country", L.country or "-" }, { "regionSource", inputs and inputs.regionSource or "-" },
		{ "nameRegion", self.nameRegion or "-" }, { "word", L.word or "-" },
		{ "cls", cls == false and "list" or tostring(cls) }, { "clsSource", L.clsSource or "-" },
		{ "guess", L.guess or "-" }, { "listPath", L.listPath or "-" }, { "listN", L.list and #L.list or 0 },
		{ "tries", L.tries or 0 }, { "why", L.why or "-" } })
end

--- The classifier for an offshoot's composed name, or false on a list ot_names has no classes for (asia, oceania,
--- china, korea, poland: 2026-10-14, NEXT_PHASE_BRIEF 48 item 2, "High Wuhan", "Wenzhou Works": no English words glued
--- onto its names; the offshoot takes an unused name of the list, Driver:offshootListName). Another mod's list:
--- false when Driver:listLang read its own towns.lua (no classifier for its language), else nameCls.
function Driver:offshootCls(saved)
	if self.stopsCfg and self.stopsCfg.cls then return self.stopsCfg.cls end
	local path = NM.basePath(self.cfg and self.cfg.nameList)
	local L = path and NM.LISTS[path]
	if L then
		local dir = (type(saved) == "table" and type(saved.nd) == "string" and saved.nd) or self.listDir or L.langs.fallback
		-- (a list the generator speaks without a classifier: oceania in English, NEXT_PHASE_BRIEF 49)
		if NM.classOf(path, dir) == nil then return PN.listLang(path) or false end
	elseif path == nil and self:listLang().cls == false then
		-- (another mod's list in a language without a classifier: unused names of its own towns.lua, NEXT_PHASE_BRIEF 72)
		return false
	end
	return self:nameCls(saved)
end

--- An unused name of the map's own list (lists without a classifier), or nil. The list is read once per session.
function Driver:offshootListName(saved, used, seed, ok)
	local path = NM.basePath(self.cfg and self.cfg.nameList)
	local L = path and NM.LISTS[path]
	if L == nil and path == nil then
		-- (another mod's list: its towns.lua, read once by Driver:listLang)
		local LL = self:listLang()
		if type(LL.list) ~= "table" then return nil end
		return OFF.listName(LL.list, used, seed, ok, NW.clean)
	end
	if L == nil or self.E.townList == nil then return nil end
	if self.offList == nil then
		local dir = (type(saved) == "table" and type(saved.nd) == "string" and saved.nd) or self.listDir or L.langs.fallback
		local okL, list = pcall(self.E.townList, path, dir)
		self.offList = (okL and type(list) == "table") and list or {}
	end
	return OFF.listName(self.offList, used, seed, ok, NW.clean)
end

--- The offshoot site's water and cues for its name (ot_offname): the survey's when this session has one, else a local
--- read (a few dozen height / water samples). pos = the parent's centre; lakeBody = the parent's water is a lake.
function Driver:offshootSite(sampler, site, pos, lakeBody)
	local out = { dir = OFF.compass(pos[1], pos[2], site.x, site.y), year = self.E.year and self.E.year() or nil,
		climate = PN.climateKey(self.cfg and self.cfg.climate) }
	if sampler and sampler.height then
		local okH, hz, cz = pcall(function() return sampler.height(site.x, site.y), sampler.height(pos[1], pos[2]) end)
		if okH and tonumber(hz) and tonumber(cz) then out.dz = hz - cz end
	end
	local okW, wat = pcall(OFF.readWater, sampler, site.x, site.y, { isWater = T.isWater, lakeBody = lakeBody,
		slope = function(s, x, y) return T.slope(s, x, y) end })
	if okW and wat then
		for k, v in pairs(wat) do out[k] = v end
	end
	local st = self.mapShape
	if st then
		local okC, cue = pcall(MS.townCues, st, site.x, site.y)
		if okC and cue and cue.w then
			for _, tag in ipairs({ "falls", "bend", "confluence", "mouth", "bay" }) do
				if (cue.w[tag] or 0) >= 0.7 then out[tag] = true end
			end
			if out.near and not out.river then
				-- (the survey tells the sea from a big lake: the big lake's shore is no sea beach)
				if cue.w.biglake then out.sea, out.lake = nil, true end
				local okN, wn = pcall(MS.waterNear, st, site.x, site.y, 600)
				if okN and wn then
					if wn.sea and not wn.lake then out.sea, out.lake = true, nil
					elseif wn.lake and not wn.sea then out.sea, out.lake = nil, true end
				end
			end
		end
	end
	return out
end

--- The NAMES offshoot line: the suffixes the mod's offshoot towns carry map-wide (ot_offname.usedText).
function Driver:offshootNamesLine(saved, cls, newName, info)
	local names = {}
	for id in pairs(self:claimedTowns(saved)) do
		local nm = self.E.name(id)
		if type(nm) == "string" then names[#names + 1] = nm end
	end
	if newName then names[#names + 1] = newName end
	table.sort(names)
	self:log("NAMES offshoot", { { "used", OFF.usedText(cls or "en", names) }, { "n", #names },
		{ "new", newName or "-" }, { "pattern", info and info.pattern or "-" }, { "suffix", info and info.suffix or "-" } })
end

--- The map's word budget over the names on it now (towns, districts, Works: ot_namewords) for a district / Works of the
--- town named `parent` at (x, y): budget, ok(name) (the parent's own words don't count again). Read when such a town is
--- named (rare): one name and one position per town, at most NM.MAX_TOWNS.
--- (2026-10-14, NEXT_PHASE_BRIEF 50 item 2: the budget also counts the generator's roots and affix patterns, and keeps
--- every key out of the HOOD nearest towns.) Returns budget, ok(name) (a composed form: the parent's words, roots and
--- pattern don't count again) and okGen(name) (a generated name: only the parent's generic words are skipped; a glued
--- stem of the parent's, "Mytsands", pays for its root).
function Driver:offshootBudget(saved, parent, x, y)
	local E = self.E
	local cls = self:nameCls(saved)
	local list = {}
	for i, id in ipairs(E.towns() or {}) do
		if i > NM.MAX_TOWNS then break end
		local tx, ty = E.boxCentre(id)
		list[#list + 1] = { E.name(id), tx, ty }
	end
	local B = NW.newBudget(cls, #list)
	local g = PN.langOf(cls)
	if g then PN.attachExtra(B, g, nil) end
	local pos = {}
	for _, e in ipairs(list) do pos[#pos + 1] = { e[2], e[3] } end
	NW.setTowns(B, pos)
	for _, e in ipairs(list) do NW.add(B, e[1], e[2], e[3]) end
	local pk = NW.budgetKeys(B, parent)
	local pg = NW.keys(parent, cls)
	return B, function(nm) return NW.allow(B, nm, x, y, pk) end, function(nm) return NW.allow(B, nm, x, y, pg) end
end

--- The one path of every created town's name (2026-10-14, NEXT_PHASE_BRIEF 50 item 1, run 1729 load 3: Mytsands,
--- Norsands, Strathsands came from ot_placename.related with `pattern=generated suffix=-`, past the suffix count, the
--- siblings and the site's water read; Mytsands sits by a lake). kind = "works" | "district"; the generator's name (in
--- Landscape / Generated names, drawn GEN_OFFSHOOT_P) joins ot_offname's candidates and wins only under the same rules:
--- the map-wide suffix count, sibling avoidance, the word budget (roots and affix patterns too), the climate, the
--- survey / local water read (beach words on a sandy sea shore only). A list without a classifier takes an unused name
--- of its own list. Returns name, src ("composed" | "generated" | "list"), info { pattern, suffix, fam } or nil.
function Driver:offshootName(kind, job, t, site, pos, o)
	local E = self.E
	local saved = o.saved
	local style = job.style or {}
	local seed = o.seed or style.seed or 1
	local parent = E.name(t)
	local used = {}
	for _, id in ipairs(E.towns() or {}) do used[E.name(id)] = true end
	local _, okName, okGen = self:offshootBudget(saved, parent, site.x, site.y)
	local ocls = self:offshootCls(saved)
	if ocls == false then
		local nm = self:offshootListName(saved, used, o.listSeed, okName) or self:offshootListName(saved, used, o.listSeed)
		if nm then return nm, "list", { pattern = "list", suffix = "-" } end
		-- (another mod's list with every name used: the old composed name rather than no offshoot, NEXT_PHASE_BRIEF 72)
		local LL = NM.basePath(self.cfg and self.cfg.nameList) == nil and self:listLang() or nil
		if LL == nil or LL.base then return nil end
		if not LL.usedUp then
			LL.usedUp = true
			self:log("NAMELIST", { { "event", "listUsedUp" }, { "listN", type(LL.list) == "table" and #LL.list or 0 },
				{ "fallback", self.nameRegion == "US" and "usa" or "en" } })
		end
		ocls = self.nameRegion == "US" and "usa" or "en"
	end
	local osite = self:offshootSite(job.sampler or E.sampler(), site, pos, o.lake)
	if kind == "district" then osite.forestEdge = site.forestEdge else osite.harbour = site.kind == "harbour" end
	-- the generator's candidate
	local extra = nil
	if self.opts.townNames == "generated" or self.opts.townNames == "landscape" then
		local g = PN.langOf(self:nameCls(saved))
		local u = kind == "works" and RNG.unit(style.seed or 1, "worksGen", t) or RNG.unit(style.seed or 1, "districtGen", t, o.count or 0)
		if g and u < D.GEN_OFFSHOOT_P then
			local B2 = self:offshootBudget(saved, parent, site.x, site.y)
			local po = { seed = seed, budget = B2, x = site.x, y = site.y, climate = PN.climateKey(self.cfg and self.cfg.climate),
				lake = osite.lake == true and not osite.sea, sandy = osite.sea == true and osite.sandy == true,
				year = E.year and E.year() or nil }
			local okP, nm, info
			if kind == "works" then okP, nm, info = pcall(PN.works, g, parent, site.ind or "works", site.kind, used, po)
			else okP, nm, info = pcall(PN.related, g, parent, site.kind, used, po) end
			if okP and type(nm) == "string" then extra = { { name = nm, form = PN.formOf(info) } } end
		end
		-- (NEXT_PHASE_BRIEF 53 Part B: the parent's leftover named-feature claim, a river or lake no town name spent,
		-- goes to its district first, "Glavenside", still under the feature's budget and the word budget)
		if kind == "district" and g and pos then
			local names = {}
			for nm in pairs(used) do names[#names + 1] = nm end
			table.sort(names)
			local waters = self.namesWaters or SV.waters(saved)
			local okC, claim = pcall(PN.leftClaim, waters, names, pos[1], pos[2], { own = parent })
			if okC and claim then
				local okN, cn, ci = pcall(PN.claimName, g, claim, site.kind, used, { seed = seed,
					budget = self:offshootBudget(saved, parent, site.x, site.y), x = site.x, y = site.y,
					climate = PN.climateKey(self.cfg and self.cfg.climate), year = E.year and E.year() or nil })
				if okN and type(cn) == "string" then
					extra = extra or {}
					table.insert(extra, 1, { name = cn, form = PN.formOf(ci), first = true })
				end
			end
		end
	end
	local name, src, info
	local wo = { seed = seed, ok = okName, okGen = okGen, site = osite, extra = extra, lake = o.lake,
		year = E.year and E.year() or nil, file = site.industry and site.industry.file or nil }
	for pass = 1, 2 do
		if kind == "works" then
			name, info = WK.name(ocls, parent, site.kind, used, wo)
			src = (info and info.pattern == "generated") and "generated" or "composed"
		else
			name, src, info = DT.name(ocls, parent, site.kind, used, wo)
		end
		if name ~= nil then break end
		-- (a repeated word rather than no offshoot; the generated name stays under its budget)
		wo.ok = nil
	end
	if name == nil then return nil end
	if info and info.pattern == "feature" then src = "claim" end
	return name, src, info
end

--- The site search's shared inputs for a Works / district of the job's town: { deadEnds, pos, nbs, chars, owner }.
function Driver:offshootInputs(job, saved)
	local E, t = self.E, job.town
	local s = self:townState(t)
	local deadEnds = {}
	for n in pairs(job.joinInfo or {}) do
		local node = job.g.nodeById[n]
		if node then deadEnds[#deadEnds + 1] = { node.x, node.y, n } end
	end
	table.sort(deadEnds, function(a, b) return a[3] < b[3] end)
	local pos = s.pos or { job.ext.cx, job.ext.cy }
	local nbs = {}
	for _, nb in ipairs(self:neighbours(t, pos)) do
		local x, y = E.boxCentre(nb.town)
		if x then nbs[#nbs + 1] = { x, y } end
	end
	local chars = {}
	if type(saved) == "table" and type(saved.frames) == "table" then
		for k, f in pairs(saved.frames) do
			if type(f) == "table" and tonumber(f.ch) == 1 and tostring(k) ~= tostring(t) then chars[#chars + 1] = { f.x, f.y } end
		end
	end
	local owner = E.closestTown and function(x, y)
		local ct = E.closestTown(x, y)
		return ct == nil or ct == t
	end or nil
	-- (the forest test of the site, ot_works.forestShare: the parent's tree grid; nil outside it)
	local cover = s.forest and function(x, y) return FO.coverAt(s.forest, x, y) end or nil
	-- (§64: the landscape terms, ot_works.landScore: the grid itself and whether the parent is a deep forest town)
	local style = job.style
	local deep = (style and (style.deep ~= nil or FO.isDeep(style.forest))) or false
	return { deadEnds = deadEnds, pos = pos, nbs = nbs, chars = chars, owner = owner, cover = cover, forest = s.forest,
		deep = deep }
end

D.WORKS_IND_OBST_R = 2500     -- m: obstacles read for a Works by a factory (sites up to ot_works IND_MAX_D)

--- Decides at the snapshot of a demand build whether this town gets its Works now: picks the site and the name and
--- sends the creation (the build goes on as usual; worksTick finds the new town).
function Driver:worksDecide(job, now, saved)
	if not (D.WORKS and WK.ON) or job.dry or job.force or (job.trigger ~= "demand" and job.trigger ~= "offshoot") then return end
	local E, t = self.E, job.town
	if E.createTown == nil then return end
	-- ("Satellite towns" setting, 2026-10-14 late: Off / Residential only found no Works)
	if not self:offshootAllowed("works") then return end
	-- (one town creation in flight map-wide, Works and districts together: the created town is told apart by its name)
	if self:createBusy(now) then return end
	local s = self:townState(t)
	if s.works or (s.worksTries or 0) >= D.WORKS_TRIES or now < (s.worksNextUs or 0) then return end
	local fr = SV.frame(saved, t)
	if fr and fr.works then
		s.works = { phase = "done", town = fr.works, restored = true, kind = "works" }
		return
	end
	local style = job.style
	local size = D.offshootSize(job.pts and #job.pts or 0, job.caps)
	local q = self:offshootQuotaState(now, saved)
	local ok, why = WK.eligible({ fresh = self.newMap == true, seed = style and style.seed,
		chanceMul = RCI.chanceMul(self:rciLean(t), "works"),
		buildings = size, isWorks = self:isOffshootTown(t, saved), has = false,
		character = (style and style.form and style.form.character == true) or not CH.offshootsOk(style and style.charKind),
		deep = self:isDeepTown(t, saved),
		quotaLeft = self:worksKnown(saved) < q.worksQuota and q.left })
	-- (§64: the map under its offshoot minimum: a big town the draw passed over founds one anyway, when Works is the
	-- kind the map lacks; until it is big enough it stays a candidate)
	local quotaWait
	ok, why, quotaWait = D.offshootFallback("works", ok, why, size, q)
	if not ok then
		if why ~= "small" and why ~= "quota" and not s.worksLogged then
			s.worksLogged = true
			self:debug("WORKS", { { "town", t }, { "name", E.name(t) }, { "on", false }, { "why", why },
				{ "quota", string.format("%d/%d-%d", q.known, q.min, q.max) }, { "quotaWait", quotaWait } })
		end
		if (why == "rare" and not quotaWait) or why == "notNewMap" or why == "works" or why == "character" or why == "deep" then
			s.worksTries = D.WORKS_TRIES
		end
		return
	end
	s.worksWhy = why
	-- (staggered offshoots, ot_satpace)
	if self:paceGate(job, "works", now, saved) ~= "found" then return end
	local inp = self:offshootInputs(job, saved)
	local pos = inp.pos
	if E.harbours and (self.harbourList == nil or now - (self.harbourUs or 0) > D.WORKS_HARBOUR_S * 1e6) then
		self.harbourList, self.harbourUs = E.harbours() or {}, now
	end
	if E.railStations and self.stopRail == nil then self.stopRail, self.stopRailUs = E.railStations() or {}, now end
	-- (2026-10-14: the industries within ot_works IND_MAX: the Works goes 2/3 of the way to the nearest that fits)
	self:industryFor(t, now, job.ext)
	local inds = {}
	for i, it in ipairs(self.indAll or {}) do
		if i > 4000 then break end
		local ix, iy = it[1] or it.x, it[2] or it.y
		if ix and G.dist(pos[1], pos[2], ix, iy) <= WK.IND_MAX then inds[#inds + 1] = it end
	end
	local t0 = self:nowUs()
	local rejects = {}
	local site, n = WK.pickSite({ cx = pos[1], cy = pos[2], r = job.ext.r, sampler = job.sampler or E.sampler(),
		seed = style.seed, neighbours = inp.nbs, characters = inp.chars, bounds = self:mapBounds(now), gaps = style.gaps,
		harbours = self.harbourList, rails = self.stopRail, deadEnds = inp.deadEnds, g = job.g, industries = inds,
		zones = s.ind, cover = inp.cover, rejects = rejects, forest = inp.forest, land = style.land, deep = inp.deep,
		obstacles = E.obstacles and E.obstacles(pos[1], pos[2], #inds > 0 and D.WORKS_IND_OBST_R or D.SAT_OBSTACLE_R) or nil,
		owner = inp.owner })
	if site == nil then
		s.worksTries = (s.worksTries or 0) + 1
		s.worksNextUs = now + D.WORKS_RETRY_S * 1e6
		self:paceRefund(t, "works:" .. tostring(n), job)
		self:log("WORKS", { { "town", t }, { "name", E.name(t) }, { "event", "none" }, { "why", n }, { "tries", s.worksTries },
			{ "rejects", WK.rejectText(rejects) }, { "industries", #inds }, { "us", self:nowUs() - t0 } })
		return
	end
	local wat = s.stats and s.stats.water
	local name, src, oinfo = self:offshootName("works", job, t, site, pos, { saved = saved, seed = style.seed,
		listSeed = (style.seed or 1) + t, lake = wat ~= nil and (wat.body == "lake" or wat.body == "pond") })
	local ocls = self:offshootCls(saved)
	if name == nil then
		s.worksTries = D.WORKS_TRIES
		self:paceRefund(t, "works:noName", job)
		self:log("WORKS", { { "town", t }, { "name", E.name(t) }, { "event", "none" }, { "why", "noName" } })
		return
	end
	local before = {}
	for _, id in ipairs(E.towns() or {}) do before[id] = true end
	local w = { phase = "create", site = site, name = name, kind = "works", siteKind = site.kind, sentUs = now, before = before,
		simYear = H.simYears, year = E.yearF and E.yearF() or nil }
	s.works = w
	local sent, info = E.createTown({ x = site.x, y = site.y, name = name, caps = WK.CAPS, seed = "sqot" .. tostring(t) },
		function(success) w.created = success == true end)
	if sent then self:root().createInFlight = { town = t, rec = w, sentUs = now } end
	self:log("WORKS", { { "town", t }, { "name", E.name(t) }, { "event", "create" }, { "works", name }, { "kind", site.kind },
		{ "site", string.format("%.0f:%.0f", site.x, site.y) }, { "d", string.format("%.0f", site.d) },
		{ "forest", D.forestSiteText(site) }, { "rejects", WK.rejectText(rejects) },
		{ "industry", site.industry and string.format("%s:%.0f", site.ind or "-", site.indDist or 0) or "-" }, { "src", src },
		{ "pattern", oinfo and oinfo.pattern or src }, { "suffix", oinfo and oinfo.suffix or "-" },
		{ "fam", oinfo and oinfo.fam or "-" },
		{ "at", site.at and string.format("%.2f", site.at) or "-" }, { "nudge", site.nudge or "-" },
		{ "caps", string.format("%d/%d/%d", WK.CAPS[1], WK.CAPS[2], WK.CAPS[3]) }, { "cands", n }, { "industries", #inds },
		{ "land", D.landSiteText(site) }, { "why", s.worksWhy or "-" }, { "simYear", H.simYears or "-" },
		{ "sent", sent }, { "err", info and info.err or "-" }, { "us", self:nowUs() - t0 } })
	if sent then self:offshootNamesLine(saved, ocls or nil, name, oinfo) end
	if not sent then
		s.works = nil
		s.worksTries = (s.worksTries or 0) + 1
		s.worksNextUs = now + D.WORKS_RETRY_S * 1e6
		self:paceRefund(t, "works:notSent", job)
	end
end

---------------------------------------------------------------------------
-- District towns (ot_district, 2026-10-14, round after the 2355 run; user: "push offshoot towns more ... create a small
-- offshoot residential and then fill in the game to main town. These could be like different districts"): on a new
-- map a grown town founds 1-2 small residential towns (DT.CAPS) on a site feature 0.6-1.5 km out (hilltop, shore,
-- across water, the lane ahead's far end, a valley head, a forest clearing), made like the Works, linked by a road
-- (ot_link), its arms shortened (DISTRICT_KA) and the gap between the two waived along the link. DISTRICT lines:
-- decide (none), create, created / refused, link (plan / none / dropped), linked / refused. Saved: `dk` (with the
-- parent) and the parent frame's `dp` (EV_WORKS kind=district). Dev: OT Dev "Found a district" (Driver:devDistrict).
D.DISTRICTS = true
D.DISTRICT_TRIES = 3          -- site / create tries per town and session
D.DISTRICT_RETRY_S = 240
D.DISTRICT_KA = 0.75          -- arm reach (ot_shape kaMul) of a town with a district: districts instead of long arms
D.DISTRICT_ARMED = { linear = true, ridge = true, cross = true, fingers = true }

--- The country-road crossroads nearer this town (ot_roads, the satellite's hamlet sites; the crossroads hamlet motif's
--- own first): district "cross" sites (§64). { {x, y} }.
function Driver:offshootJunctions(s)
	local out = {}
	for _, j in ipairs(s.roads and s.roads.junctions or {}) do
		if #out >= 64 then break end
		if j.own ~= false and (j.x or j[1]) then out[#out + 1] = { j.x or j[1], j.y or j[2] } end
	end
	return out
end

function Driver:districtDecide(job, now, saved)
	if not (D.DISTRICTS and DT.ON) or job.dry then return end
	local E, t = self.E, job.town
	if E.createTown == nil then return end
	local s = self:townState(t)
	local dev = s.devDistrict == true
	if not dev and (job.force or (job.trigger ~= "demand" and job.trigger ~= "offshoot")) then return end
	-- ("Satellite towns" setting: Off / Industrial only found no districts, the dev button neither)
	if not self:offshootAllowed("district") then
		if dev then
			s.devDistrict = nil
			self:log("DISTRICT", { { "town", t }, { "name", E.name(t) }, { "event", "none" }, { "why", "setting" }, { "dev", true } })
		end
		return
	end
	-- (one town creation in flight map-wide, Works and districts together)
	if self:createBusy(now) then return end
	s.districts = s.districts or {}
	local count, linkedAll = 0, true
	for _, w in ipairs(s.districts) do
		count = count + 1
		if w.phase == "create" then return end
		if w.phase ~= "done" then linkedAll = false end
	end
	local fr = SV.frame(saved, t)
	if count == 0 and fr and (fr.districts or 0) > 0 then count = fr.districts end
	if not dev and ((s.districtTries or 0) >= D.DISTRICT_TRIES or now < (s.districtNextUs or 0)) then return end
	local style = job.style
	local size = D.offshootSize(job.pts and #job.pts or 0, job.caps)
	local q = self:offshootQuotaState(now, saved)
	local ok, why = DT.eligible({ fresh = self.newMap == true, seed = style and style.seed,
		chanceMul = RCI.chanceMul(self:rciLean(t), "district"),
		buildings = size, isOffshoot = self:isOffshootTown(t, saved),
		character = (style and style.form and style.form.character == true) or not CH.offshootsOk(style and style.charKind),
		count = count, linkedAll = linkedAll,
		deep = self:isDeepTown(t, saved),
		quotaLeft = self:districtKnown(saved) < q.districtQuota and q.left })
	-- (§64: the map under its offshoot minimum: a big town the draw passed over founds one anyway)
	local quotaWait
	ok, why, quotaWait = D.offshootFallback("district", ok, why, size, q)
	if dev and not ok and why ~= "offshoot" and why ~= "max" then ok, why = true, "dev:" .. why end
	if not ok then
		local key = why .. (quotaWait and ":quotaWait" or "")
		if why ~= "small" and why ~= "quota" and why ~= "waitLink" and s.districtLogged ~= key then
			s.districtLogged = key
			self:debug("DISTRICT", { { "town", t }, { "name", E.name(t) }, { "on", false }, { "why", why }, { "count", count },
				{ "quota", string.format("%d/%d-%d", q.known, q.min, q.max) }, { "quotaWait", quotaWait } })
		end
		if (why == "rare" and not quotaWait) or why == "notNewMap" or why == "offshoot" or why == "character" or why == "max"
			or why == "deep" then
			s.districtTries = D.DISTRICT_TRIES
		end
		if dev then s.devDistrict = nil end
		return
	end
	s.districtWhy = why
	-- (staggered offshoots, ot_satpace; the dev button founds at once)
	if not dev and self:paceGate(job, "district", now, saved) ~= "found" then return end
	local inp = self:offshootInputs(job, saved)
	local pos = inp.pos
	local others = {}
	for _, w in ipairs(s.districts) do others[#others + 1] = { w.site.x, w.site.y } end
	for d, par in pairs(SV.districtSet(saved)) do
		if par == t then
			local x, y = E.boxCentre(d)
			if x then others[#others + 1] = { x, y } end
		end
	end
	local wat = s.stats and s.stats.water
	local t0 = self:nowUs()
	local rejects = {}
	local site, n = DT.pickSite({ cx = pos[1], cy = pos[2], r = job.ext.r, sampler = job.sampler or E.sampler(),
		seed = (style.seed or 1) + 17 * count, neighbours = inp.nbs, characters = inp.chars, bounds = self:mapBounds(now),
		gaps = style.gaps, deadEnds = inp.deadEnds, g = job.g, zones = s.ind, owner = inp.owner, others = others,
		obstacles = E.obstacles and E.obstacles(pos[1], pos[2], D.SAT_OBSTACLE_R) or nil,
		lead = s.leadBuilt and { s.leadBuilt.x, s.leadBuilt.y } or nil,
		cover = inp.cover, rejects = rejects, forest = inp.forest, land = style.land, deep = inp.deep,
		junctions = self:offshootJunctions(s) })
	if site == nil then
		s.districtTries = (s.districtTries or 0) + 1
		s.districtNextUs = now + D.DISTRICT_RETRY_S * 1e6
		self:paceRefund(t, "district:" .. tostring(n), job)
		self:log("DISTRICT", { { "town", t }, { "name", E.name(t) }, { "event", "none" }, { "why", n }, { "count", count },
			{ "rejects", WK.rejectText(rejects) }, { "dev", dev }, { "tries", s.districtTries }, { "us", self:nowUs() - t0 } })
		if dev then s.devDistrict = nil end
		return
	end
	local lake = wat ~= nil and (wat.body == "lake" or wat.body == "pond")
	local name, src, oinfo = self:offshootName("district", job, t, site, pos, { saved = saved, seed = (style.seed or 1) + count,
		count = count, listSeed = (style.seed or 1) + 31 * t + count, lake = lake })
	local ocls = self:offshootCls(saved)
	if name == nil then
		s.districtTries = D.DISTRICT_TRIES
		self:paceRefund(t, "district:noName", job)
		self:log("DISTRICT", { { "town", t }, { "name", E.name(t) }, { "event", "none" }, { "why", "noName" } })
		if dev then s.devDistrict = nil end
		return
	end
	local before = {}
	for _, id in ipairs(E.towns() or {}) do before[id] = true end
	local w = { phase = "create", site = site, name = name, kind = "district", siteKind = site.kind, sentUs = now, before = before,
		simYear = H.simYears, year = E.yearF and E.yearF() or nil }
	s.districts[#s.districts + 1] = w
	local sent, info = E.createTown({ x = site.x, y = site.y, name = name, caps = DT.CAPS, seed = "sqotd" .. tostring(t) .. "_" .. count },
		function(success) w.created = success == true end)
	if sent then self:root().createInFlight = { town = t, rec = w, sentUs = now } end
	self:log("DISTRICT", { { "town", t }, { "name", E.name(t) }, { "event", "create" }, { "district", name }, { "src", src },
		{ "kind", site.kind }, { "kinds", site.kinds }, { "site", string.format("%.0f:%.0f", site.x, site.y) },
		{ "forest", D.forestSiteText(site) }, { "rejects", WK.rejectText(rejects) },
		{ "d", string.format("%.0f", site.d) }, { "caps", string.format("%d/%d/%d", DT.CAPS[1], DT.CAPS[2], DT.CAPS[3]) },
		{ "count", count + 1 }, { "cands", n }, { "dev", dev }, { "land", D.landSiteText(site) }, { "why", s.districtWhy or "-" },
		{ "simYear", H.simYears or "-" }, { "sent", sent }, { "err", info and info.err or "-" },
		{ "pattern", oinfo and oinfo.pattern or src or "-" }, { "suffix", oinfo and oinfo.suffix or "-" },
		{ "us", self:nowUs() - t0 } })
	if sent then self:offshootNamesLine(saved, ocls or nil, name, oinfo) end
	if not sent then
		table.remove(s.districts)
		s.districtTries = (s.districtTries or 0) + 1
		s.districtNextUs = now + D.DISTRICT_RETRY_S * 1e6
		self:paceRefund(t, "district:notSent", job)
	end
	-- (the town's arms reach less from now on: styleFor's key changes)
	if dev then s.devDistrict = "link" end
end

--- Dev tools (OT Dev "Found a district"): the next build of town t founds a district whatever the seed, size and quota
--- say (site rules apply), a second press after its creation links it at once. Starts a forced job when none runs.
function Driver:devDistrict(t, now)
	local s = self:townState(t)
	local pending = nil
	for _, w in ipairs(s.districts or {}) do if w.phase == "link" then pending = w end end
	if pending then
		pending.linkAfterUs, pending.dev = 0, true
	else
		s.devDistrict, s.districtTries, s.districtNextUs = true, 0, 0
	end
	local started = self:startJob(t, now, { force = true }) ~= nil
	self:log("DISTRICT", { { "town", t }, { "name", self.E.name(t) }, { "event", "dev" },
		{ "action", pending and "link" or "found" }, { "started", started } })
	return pending and "link" or "found", started
end

--- Pending creations (Works and districts): the new town found by diffing the town list (docs/findings.md: find new
--- entities by diffing), saved, filled once (makeTownUpdateSizeCmd x1), its link due after WORKS_LINK_DELAY_S; a refusal or
--- timeout frees the parent for another try later.
function Driver:worksTick(now, saved)
	if not D.WORKS then return end
	local E = self.E
	for t, s in pairs(self.towns or {}) do
		local recs = {}
		if s.works then recs[#recs + 1] = s.works end
		for _, w in ipairs(s.districts or {}) do recs[#recs + 1] = w end
		for _, w in ipairs(recs) do
			if w.phase == "create" then self:offshootCreated(t, s, w, now) end
		end
		-- (refused / timed-out districts leave the list)
		if s.districts then
			local keep = {}
			for _, w in ipairs(s.districts) do if not w.dropped then keep[#keep + 1] = w end end
			s.districts = keep
		end
	end
	self:offshootStatus(now, saved)
end

-- OFFSHOOTS (2026-10-15, §64; "count houses per offshoot over time in the log, so we can see they fill"): every
-- OFFSHOOT_LOG_S real s, and once per dev Simulate round, while the map has offshoot towns, one line with each one's
-- buildings: `OFFSHOOTS n= quota=<known>/<min>-<max> towns=<id>:<name>:<works|district>:<parent>:y<founded>:b<buildings>/...
-- simYear= year=` (founded: the dev Simulate's year, else the game year, "-" after a reload). At most OFFSHOOT_LOG_MAX.
D.OFFSHOOT_LOG_S = 300
D.OFFSHOOT_LOG_MAX = 64

function Driver:offshootStatus(now, saved)
	local r = self:root()
	local round = H.simRound
	local due = now - (r.offLogUs or -1e18) >= D.OFFSHOOT_LOG_S * 1e6 or (round ~= nil and round ~= r.offLogRound)
	if not due then return false end
	local created = self:createdTowns(saved)
	if next(created) == nil then return false end
	r.offLogUs, r.offLogRound = now, round
	local E = self.E
	local t2b = self:mapReads(now)
	local works = SV.worksSet(self:savedNow(saved))
	local info = {}
	for par, st in pairs(r.towns or {}) do
		if type(st) == "table" then
			local recs = {}
			if type(st.works) == "table" then recs[#recs + 1] = st.works end
			for i, w in ipairs(st.districts or {}) do if i <= 16 then recs[#recs + 1] = w end end
			for _, w in ipairs(recs) do
				if type(w) == "table" and w.town then info[w.town] = { parent = par, rec = w } end
			end
		end
	end
	local ids = {}
	for id in pairs(created) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for i, id in ipairs(ids) do
		if i > D.OFFSHOOT_LOG_MAX then break end
		local inf = info[id]
		local par = inf and inf.parent or (created[id] ~= true and created[id]) or "-"
		local kind = (works[id] or (inf and inf.rec.kind == "works")) and "works" or "district"
		local w = inf and inf.rec or nil
		local fy = w and (w.simYear and string.format("%d", w.simYear) or (w.year and string.format("%d", math.floor(w.year)))) or "-"
		local b = t2b and t2b[id] and #t2b[id] or 0
		local okN, nm = pcall(E.name, id)
		parts[#parts + 1] = string.format("%s:%s:%s:%s:y%s:b%d", tostring(id), okN and tostring(nm) or "?", kind,
			tostring(par), fy, b)
	end
	local q = self:offshootQuotaState(now, saved)
	self:log("OFFSHOOTS", { { "n", #ids }, { "quota", string.format("%d/%d-%d", q.known, q.min, q.max) },
		{ "towns", table.concat(parts, "/") }, { "simYear", H.simYears or "-" },
		{ "year", E.year and E.year() or "-" } })
	return true
end

--- Is founding this kind of town ("works" | "district") allowed by the "Satellite towns" setting (opts.satelliteTowns:
--- "on" | "residential" | "industrial" | "off"; missing: on)?
function Driver:offshootAllowed(kind)
	local v = self.opts and self.opts.satelliteTowns or "on"
	if v == "off" then return false end
	if kind == "works" then return v ~= "residential" end
	return v ~= "industrial"
end

--- A town creation in flight (one map-wide, Works and districts together)? A record stuck past twice the timeout is let go.
function Driver:createBusy(now)
	local r = self:root()
	local f = r.createInFlight
	if f == nil then return false end
	if f.rec == nil or f.rec.phase ~= "create" or f.rec.dropped
		or now - (f.sentUs or 0) > 2 * D.WORKS_CREATE_TIMEOUT_S * 1e6 then
		r.createInFlight = nil
		return false
	end
	return true
end

--- `land=` on a Works / district create (§64): "wood<0..1>:clear<m>:lean<-1..1>", "-" parts unknown.
function D.landSiteText(site)
	if site == nil then return "-" end
	local function f(v, fmt) return type(v) == "number" and string.format(fmt, v) or "-" end
	return string.format("wood%s:clear%s:lean%s", f(site.wood, "%.2f"), f(site.clear, "%.0f"), f(site.lean, "%.2f"))
end

--- `forest=` on a Works / district create: "<share>" within ot_works.FOREST_R ("+edge": forest just beyond), "-" unknown.
function D.forestSiteText(site)
	if site == nil or site.forest == nil then return site and site.forestEdge and "-+edge" or "-" end
	return string.format("%.2f%s", site.forest, site.forestEdge and "+edge" or "")
end

--- The towns the mod claimed (this session or saved): { [id] = true }.
function Driver:claimedTowns(saved)
	local out = {}
	for id in pairs(self:createdTowns(saved)) do out[id] = true end
	return out
end

--- A pending creation: once the command answered, the new town is the one named as we named it near our site
--- (ot_works.identify; 2026-10-14 late: never "the newest town", which mixed up concurrent creates in run
--- 2026-10-14_0119_sqot); it is claimed (saved with its site), filled once, its link due after WORKS_LINK_DELAY_S. A
--- town that can't be identified within WORKS_CREATE_TIMEOUT_S is never claimed (`created ... why=unidentified`, once;
--- it stays an ordinary town) and the parent tries no more this session; a refusal or timeout frees the parent for
--- another try later.
function Driver:offshootCreated(t, s, w, now)
	local E = self.E
	local district = w.kind == "district"
	local what = district and "DISTRICT" or "WORKS"
	local key = district and "district" or "works"
	local function release()
		local r = self:root()
		if r.createInFlight and r.createInFlight.rec == w then r.createInFlight = nil end
	end
	if w.created == true then
		local claimed = self:claimedTowns(self.saved)
		local cands = {}
		for _, id in ipairs(E.towns() or {}) do
			if not w.before[id] and not claimed[id] then
				local x, y = E.boxCentre(id)
				cands[#cands + 1] = { id = id, name = E.name(id), x = x, y = y }
			end
		end
		local new, how = WK.identify(cands, w.name, w.site.x, w.site.y)
		if new ~= nil then
			w.town, w.phase, w.linkAfterUs = new, "link", now + D.WORKS_LINK_DELAY_S * 1e6
			if district then
				self.districtTowns = self.districtTowns or {}
				self.districtTowns[new] = t
			else
				self.worksTowns = self.worksTowns or {}
				self.worksTowns[new] = true
			end
			release()
			self.townList = nil   -- (the new town joins the round-robin)
			E.sendEvent(SV.EVENT_ID, SV.EV_WORKS, { parent = t, town = new, kind = key,
				x = math.floor(w.site.x + 0.5), y = math.floor(w.site.y + 0.5) })
			-- (the game's notification feed, 2026-10-17: once per created town, ot_card.shouldNotify)
			local okN, errN = pcall(self.noteNewTown, self, new, t, key)
			if not okN then self:log("WARN", { { "stage", "notify" }, { "town", new }, { "err", errN } }) end
			if E.growTown then E.growTown(new, { 1, 1, 1 }, function(ok) w.grown = ok end) end
			self:log(what, { { "town", t }, { "event", "created" }, { key, new }, { "name", E.name(new) },
				{ "kind", w.siteKind or w.kind }, { "how", how }, { "cands", #cands }, { "ms", math.floor((now - w.sentUs) / 1000) } })
			if district and s.devDistrict == "link" then w.linkAfterUs, w.dev = now + D.WORKS_LINK_DELAY_S * 1e6, true end
			return
		elseif now - w.sentUs > D.WORKS_CREATE_TIMEOUT_S * 1e6 then
			-- (created but not found by its name near the site: never claimed; no new try this session, so no second
			-- town for the same parent)
			if district then
				w.dropped = true
				s.districtTries = D.DISTRICT_TRIES
			else
				s.works = nil
				s.worksTries = D.WORKS_TRIES
			end
			release()
			self:log(what, { { "town", t }, { "event", "created" }, { key, "-" }, { "name", w.name }, { "why", "unidentified" },
				{ "detail", how }, { "cands", #cands } })
		end
		return
	end
	if w.created == false or (w.created == nil and now - w.sentUs > D.WORKS_CREATE_TIMEOUT_S * 1e6) then
		if district then
			w.dropped = true
			s.districtTries = (s.districtTries or 0) + 1
			s.districtNextUs = now + D.DISTRICT_RETRY_S * 1e6
		else
			s.works = nil
			s.worksTries = (s.worksTries or 0) + 1
			s.worksNextUs = now + D.WORKS_RETRY_S * 1e6
		end
		release()
		self:paceRefund(t, key .. ":" .. (w.created == false and "refused" or "timeout"))
		self:log(what, { { "town", t }, { "event", "refused" }, { key, w.name },
			{ "why", w.created == false and "refused" or "timeout" },
			{ "tries", district and s.districtTries or s.worksTries } })
	end
end

---------------------------------------------------------------------------
-- The load check of the saved Works / districts (2026-10-14 late; run 2026-10-14_0119_sqot: the created-town race had
-- several parents claim one town, e.g. Ringwood's district `dk` entry pointing at Heywood Works 14 km away). Once per
-- session: entries whose town is gone, away from its saved site, or (older entries without a site) farther than
-- ot_saved.OFFSHOOT_MAX_D from its parent are dropped (EV_WORKS kind=drop: out of `dk` / `wk`, the parent's count
-- lowered; the town stays an ordinary town; until the event lands the driver reads a filtered view). OFFSHOOT lines
-- (drop, and once per town an unclaimed town named like one: orphan).

function Driver:offshootCheck(now, saved)
	if self.offshootChecked or type(saved) ~= "table" or not SV.initialised(saved) then return end
	self.offshootChecked = true
	local E = self.E
	local live = {}
	for _, id in ipairs(E.towns() or {}) do live[id] = true end
	local drops = SV.offshootCheck(saved, function(id)
		if not live[id] then return nil end
		local x, y = E.boxCentre(id)
		if x == nil then return nil, "unknown" end
		return x, y
	end)
	self.offshootDrop = self.offshootDrop or {}
	for _, d in ipairs(drops) do
		self.offshootDrop[d.t] = true
		E.sendEvent(SV.EVENT_ID, SV.EV_WORKS, { kind = "drop", town = d.t, parent = d.p })
		self:log("OFFSHOOT", { { "event", "drop" }, { "town", d.t }, { "name", E.name(d.t) or "-" }, { "kind", d.kind },
			{ "parent", d.p }, { "parentName", d.p and d.p > 0 and E.name(d.p) or "-" }, { "why", d.why },
			{ "d", string.format("%.0f", d.d or -1) } })
	end
	-- (orphans: towns named like a district / Works of another town but claimed by none, e.g. the race's lost creates.
	-- On a new map, within ot_saved.OFFSHOOT_MAX_D of that town, and when it has room for one (no Works yet / fewer than
	-- ot_district.MAX_PER_TOWN districts), the town adopts it (EV_WORKS with its kind: `adopt`); else it stays an
	-- ordinary town (`orphan`). Logged once per load.)
	local view = SV.withoutOffshoots(saved, self.offshootDrop)
	local claimed = self:claimedTowns(view)
	local ids = E.towns() or {}
	local names = {}
	for _, id in ipairs(ids) do names[id] = E.name(id) end
	local cls = self:nameCls(saved)
	local dropsOf = {}
	for _, d in ipairs(drops) do
		if d.kind == "district" and d.p then dropsOf[d.p] = (dropsOf[d.p] or 0) + 1 end
	end
	local adoptedW, adoptedD = {}, {}
	local n = 0
	for _, id in ipairs(ids) do
		if not claimed[id] and n < 20 then
			local parent, form, kind, pid = DT.orphanOf(names[id], names, cls)
			if parent then
				n = n + 1
				local fr = pid and SV.frame(view, pid) or nil
				local x, y = E.boxCentre(id)
				local px, py = nil, nil
				if fr and fr.origin then px, py = fr.origin[1], fr.origin[2] elseif pid then px, py = E.boxCentre(pid) end
				local dist = (x and px) and G.dist(x, y, px, py) or nil
				local room = false
				if kind == "works" then room = fr ~= nil and fr.works == nil and not adoptedW[pid]
				else room = (((fr and fr.districts) or 0) - (dropsOf[pid] or 0) + (adoptedD[pid] or 0)) < DT.MAX_PER_TOWN end
				local adopt = saved.fresh == true and room and dist ~= nil and dist <= SV.OFFSHOOT_MAX_D
					and not self:isOffshootTown(pid, view)
				if adopt then
					if kind == "works" then adoptedW[pid] = true else adoptedD[pid] = (adoptedD[pid] or 0) + 1 end
					E.sendEvent(SV.EVENT_ID, SV.EV_WORKS, { parent = pid, town = id, kind = kind,
						x = math.floor(x + 0.5), y = math.floor(y + 0.5) })
					if kind == "works" then
						self.worksTowns = self.worksTowns or {}
						self.worksTowns[id] = true
					else
						self.districtTowns = self.districtTowns or {}
						self.districtTowns[id] = pid
					end
				end
				self:log("OFFSHOOT", { { "event", adopt and "adopt" or "orphan" }, { "town", id }, { "name", names[id] },
					{ "like", parent }, { "parent", pid or "-" }, { "kind", kind }, { "form", form },
					{ "d", dist and string.format("%.0f", dist) or "-" } })
			end
		end
	end
end

--- At the parent's demand build after a creation: the link road to the Works / district town (job.worksPlan). The new
--- town's streets are read around it and added to this job's network; its dead ends may be joined (job.otherTownOk).
--- ot_link gives up to ot_link.MAX_OUT routes, planned in turn by worksPlanStage.
function Driver:worksLinkDecide(job, now, saved)
	if not D.WORKS or job.dry then return end
	local E, t = self.E, job.town
	local s = self:townState(t)
	local w = nil
	local cands = {}
	if s.works then cands[#cands + 1] = s.works end
	for _, d in ipairs(s.districts or {}) do cands[#cands + 1] = d end
	for _, c in ipairs(cands) do
		if w == nil and c.phase == "link" and now >= (c.linkAfterUs or 0) and (c.dev or ((job.trigger == "demand" or job.trigger == "offshoot") and not job.force)) then
			w = c
		end
	end
	if w == nil then return end
	local what = w.kind == "district" and "DISTRICT" or "WORKS"
	local wx, wy = E.boxCentre(w.town)
	if wx == nil then wx, wy = w.site.x, w.site.y end
	local seen, merged = {}, {}
	for _, ed in ipairs(job.edges or {}) do seen[ed.id] = true; merged[#merged + 1] = ed end
	for _, ed in ipairs(E.streets(wx, wy, D.WORKS_READ_R)) do
		if not seen[ed.id] then merged[#merged + 1] = ed end
	end
	job.edges = merged
	job.otherTownOk, job.regraph = w.town, true
	job.g, job.joinInfo = self:snapshotGraph(job)
	local deadEnds, worksEnds = {}, {}
	for n in pairs(job.joinInfo or {}) do
		local node = job.g.nodeById[n]
		if node then
			local ct = E.closestTown(node.x, node.y)
			if ct == w.town then worksEnds[#worksEnds + 1] = { node.x, node.y, n }
			else deadEnds[#deadEnds + 1] = { node.x, node.y, n } end
		end
	end
	table.sort(deadEnds, function(a, b) return a[3] < b[3] end)
	table.sort(worksEnds, function(a, b) return a[3] < b[3] end)
	local mx, my = (wx + (s.pos and s.pos[1] or job.ext.cx)) / 2, (wy + (s.pos and s.pos[2] or job.ext.cy)) / 2
	local t0 = self:nowUs()
	local lk, why, list, info = WK.link({ sampler = job.sampler or E.sampler(), seed = (job.style.seed or 1) + 7 * (w.linkTries or 0), deadEnds = deadEnds,
		worksEnds = worksEnds, g = job.g, zones = s.ind,
		obstacles = E.obstacles and E.obstacles(mx, my, D.SAT_OBSTACLE_R) or nil })
	if lk == nil then
		w.linkTries = (w.linkTries or 0) + 1
		w.linkAfterUs = now + D.WORKS_LINK_RETRY_S * 1e6
		if w.linkTries >= D.WORKS_LINK_TRIES then w.phase, w.linked = "done", false end
		self:log(what, { { "town", t }, { "event", "link" }, { "outcome", "none" }, { w.kind or "works", w.town }, { "why", why },
			{ "fails", LK.failText(info) }, { "pairs", info and info.pairs or 0 }, { "routes", info and info.tests or 0 },
			{ "deadEnds", #deadEnds }, { "worksEnds", #worksEnds }, { "tries", w.linkTries }, { "us", self:nowUs() - t0 } })
		-- (this build goes on as the town's own: the new town's nodes must not be joined by it)
		job.otherTownOk = nil
		job.g, job.joinInfo = self:snapshotGraph(job)
		return
	end
	job.worksPlan = { link = lk, list = list, info = info, works = w.town, rec = w, us = self:nowUs() - t0 }
end

--- Plans the link road (ot_link.streets + ot_plan; its middle the era's country lane) and goes on to send: the routes of
--- worksLinkDecide in turn, the first whose both ends are joined.
function Driver:worksPlanStage(job, now)
	local E, t = self.E, job.town
	local wp = job.worksPlan
	local w = wp.rec
	local what = w.kind == "district" and "DISTRICT" or "WORKS"
	local path = LN.templateFor(job.style)
	local okT = not (E.templateExists and not E.templateExists(path))
	local inc, chosen, lane, len, joined, why, tried = nil, nil, 0, 0, 0, nil, 0
	for i, lk in ipairs(wp.list or { wp.link }) do
		tried = i
		local streets = LK.streets(lk, w.kind or "works")
		local cand = PL.plan(job.g, streets, { terrain = job.sampler, maxSeg = core.MAX_SEG_FLAT, snapR = 8, minLen = 10,
			minAngle = 25, maxGrade = job.style.maxSlope, waterSetback = job.style.waterSetback, maxEdges = 40,
			join = "deadEnd", templatePaths = job.style.templatePaths })
		local j = 0
		for _, jn in ipairs(cand.joins or {}) do
			if jn.node == lk.to[3] or jn.node == lk.from[3] then j = j + 1 end
		end
		why = (#cand.edges == 0 and "empty") or (j < 2 and "notJoined") or nil
		joined = j
		if why == nil then
			inc, chosen = cand, lk
			inc.mix = core.mix(inc)
			if okT then
				local l, _, ln = LD.mark(inc, streets, path)
				lane, len = l, ln
			end
			break
		end
	end
	local lk = chosen or wp.link
	self:log(what, { { "town", t }, { "event", "link" }, { "outcome", why and "dropped" or "plan" }, { w.kind or "works", wp.works },
		{ "edges", inc and #inc.edges or 0 }, { "laneEdges", lane }, { "laneLen", string.format("%.0f", len) },
		{ "len", string.format("%.0f", lk.len) }, { "joined", joined }, { "tries", string.format("%d/%d", tried, #(wp.list or { 1 })) },
		{ "pair", lk.pair or "-" }, { "route", lk.route or "-" }, { "detour", string.format("%.0f", lk.offM or 0) },
		{ "pairs", wp.info and wp.info.pairs or 0 }, { "routes", wp.info and wp.info.tests or 0 },
		{ "fails", LK.failText(wp.info) }, { "why", why or "-" }, { "us", wp.us or 0 } })
	if why then
		w.linkTries = (w.linkTries or 0) + 1
		w.linkAfterUs = now + D.WORKS_LINK_RETRY_S * 1e6
		if w.linkTries >= D.WORKS_LINK_TRIES then w.phase, w.linked = "done", false end
		job.why = "works:" .. why
		return self:finish(t, "empty", now)
	end
	wp.link = lk
	job.inc, job.mp, job.report = inc, nil, nil
	-- (the country middle locks itself, ot_proposal; the joined ends stay plain town streets)
	job.lockKeys, job.lockN, job.lockModeUsed = {}, 0, "works"
	job.fill = "off"
	job.stage = "send"
end

function Driver:worksLinked(job, now)
	local w = job.worksPlan.rec
	if w then w.phase, w.linked = "done", true end
	local s = self:townState(job.town)
	if w and w.kind == "district" and s.devDistrict then s.devDistrict = nil end
	self:log(w and w.kind == "district" and "DISTRICT" or "WORKS", { { "town", job.town }, { "event", "linked" },
		{ w and w.kind or "works", job.worksPlan.works }, { "edges", job.spec and #job.spec.edges or 0 },
		{ "len", string.format("%.0f", job.worksPlan.link and job.worksPlan.link.len or 0) } })
end

function Driver:worksLinkFailed(job, now, why, fields)
	local w = job.worksPlan and job.worksPlan.rec
	if w then
		w.linkTries = (w.linkTries or 0) + 1
		w.linkAfterUs = now + D.WORKS_LINK_RETRY_S * 1e6
		if w.linkTries >= D.WORKS_LINK_TRIES then w.phase, w.linked = "done", false end
	end
	local lf = { { "town", job.town }, { "event", "link" }, { "outcome", "refused" }, { "why", why } }
	for _, f in ipairs(fields or {}) do
		if f[1] == "msgs" or f[1] == "collisions" or f[1] == "partners" then lf[#lf + 1] = f end
	end
	lf[#lf + 1] = { "tries", w and w.linkTries or 0 }
	self:log(w and w.kind == "district" and "DISTRICT" or "WORKS", lf)
end

---------------------------------------------------------------------------
-- River bridges (ot_bridge, 2026-10-13): a seeded share of the river towns, at a demand build once grown, builds one
-- street across the river at a narrow point (its far end a T: the far quarter's seed). Unverified in game: all or
-- nothing, pre-checked, one try per town and session, saved on the town's frame once built (EV_BRIDGE: never a
-- second one). BRIDGE lines: decide (none / plan), refused, failed, built.
D.BRIDGE_TRIES = 3            -- (2026-10-14: 1 until now) a refused crossing is skipped, the next candidate tried
D.BRIDGE_OBST_SKIP = 30       -- m at the dead end not tested against obstacles (its own street)

function Driver:bridgeDecide(job, now, saved)
	if not BR.ON or job.force or job.dry or job.trigger ~= "demand" then return end
	local t, E = job.town, self.E
	local s = self:townState(t)
	if s.bridgeDone or (s.bridgeTries or 0) >= D.BRIDGE_TRIES then return end
	local fr = SV.frame(saved, t)
	local w = s.stats and s.stats.water
	local style = job.style
	local river = w ~= nil and w.kind == "river"
	-- narrow water within BR.NARROW_R (a river or lake arm outside the 600 m disc; once per town and session)
	if s.narrow == nil and (job.pts and #job.pts or 0) >= BR.MIN_BUILDINGS then
		local t0 = self:nowUs()
		local pos = s.pos or { job.ext.cx, job.ext.cy }
		s.narrow = BR.narrowWater(job.sampler or s.sampler or E.sampler(), pos[1], pos[2])
		s.narrowUs = self:nowUs() - t0
	end
	local narrow = s.narrow or {}
	local ok, why = BR.eligible({ seed = style and style.seed, dv = style and style.drawV, buildings = job.pts and #job.pts or 0,
		always = style ~= nil and style.charBridges == true,
		river = river or #narrow > 0, done = fr ~= nil and fr.bridge == true })
	if not ok then
		-- (once per town and session: why no bridge is tried; "small" waits for the town to grow)
		if why ~= "small" and not s.bridgeLogged then
			s.bridgeLogged = true
			self:log("BRIDGE", { { "town", t }, { "name", E.name(t) }, { "outcome", "none" }, { "why", why },
				{ "river", river }, { "narrow", #narrow }, { "us", s.narrowUs or 0 } })
		end
		if why == "done" then s.bridgeDone = true end
		return
	end
	s.bridgeTries = (s.bridgeTries or 0) + 1
	local idx, path = nil, nil
	if E.bridgeType then idx, path = E.bridgeType(tonumber(style and style.year) or E.year(), s.bridgeTypeSkip) end
	if idx == nil and s.bridgeTypeSkip and E.bridgeType then
		idx, path = E.bridgeType(tonumber(style and style.year) or E.year())
	end
	if idx == nil then
		self:log("BRIDGE", { { "town", t }, { "name", E.name(t) }, { "outcome", "none" }, { "why", "noBridgeType" } })
		return
	end
	local deadEnds = {}
	for n, ji in pairs(job.joinInfo or {}) do
		local node = job.g.nodeById[n]
		if node then deadEnds[#deadEnds + 1] = { node.x, node.y, n, node.z, ji.template } end
	end
	table.sort(deadEnds, function(a, b) return a[3] < b[3] end)
	local t0 = self:nowUs()
	-- (R6: the ship lines' stops and the water level decide the deck: ot_bridge shipCheck)
	local ships, wl = self:shipStops(now)
	local bp, bwhy, cands = BR.plan({ sampler = job.sampler or E.sampler(), deadEnds = deadEnds,
		axis = river and w.axis or nil, points = narrow, g = job.g, skip = s.bridgeBad,
		bounds = self:mapBounds(now), seed = style and style.seed, ships = ships, waterLevel = wl })
	-- (2026-10-14, run 2026-10-13_2355_sqot: Haslemere's crossing collided with 8 street entities beyond the town's
	-- snapshot. Each candidate, best first: the far quarter must belong to this town, and its lines must keep clear of
	-- every street / track / construction / field the octree holds there (ot_satellite.clearOfObstacles), else the next)
	local nOther, nObst, nEmpty = 0, 0, 0
	-- (§69 steer towns: a crossing needs a target on the far bank or must be short, ot_bridge.target / EMPTY_MAX_M)
	local targets = nil
	if self:townLockMode(t) == "steer" then targets = self:bridgeTargets(job, now) end
	if bp then
		local list = bp.cands or { bp }
		bp = nil
		for _, c in ipairs(list) do
			local okC = true
			local cN = c.inc.nodes[3]
			if targets ~= nil then
				c.target = BR.target(c, targets)
				if c.target == nil and BR.length(c) > BR.EMPTY_MAX_M then okC, nEmpty = false, nEmpty + 1 end
			end
			if okC and E.closestTown and E.closestTown(cN.x, cN.y) ~= t then okC, nOther = false, nOther + 1 end
			if okC and E.obstacles then
				local ln = BR.lines(c)
				local mx, my = (ln[1][1][1] + cN.x) / 2, (ln[1][1][2] + cN.y) / 2
				local obs = E.obstacles(mx, my, 700)
				-- (the town's own streets in the snapshot were tested by ot_bridge: only what lies beyond them counts)
				local known = {}
				for _, ed in ipairs(job.edges or {}) do known[ed.id] = true end
				local keep = { segs = {}, boxes = obs and obs.boxes or {} }
				for _, sg in ipairs(obs and obs.segs or {}) do if not known[sg.id] then keep.segs[#keep.segs + 1] = sg end end
				-- (since 2026-10-14 a bridge may have no far cross street: one line only; run 0814 indexed the missing one)
				if not SAT.clearOfObstacles(keep, ln[1], D.BRIDGE_OBST_SKIP) or (ln[2] ~= nil and not SAT.clearOfObstacles(keep, ln[2])) then
					okC, nObst = false, nObst + 1
				end
			end
			if okC then bp = c break end
		end
		if bp == nil then bwhy = nObst > 0 and "obstacle" or (nOther > 0 and "otherTown" or "noTarget") end
	end
	if bp == nil then
		self:log("BRIDGE", { { "town", t }, { "name", E.name(t) }, { "outcome", "none" }, { "why", bwhy },
			{ "cands", cands or 0 }, { "otherTown", nOther }, { "obstacle", nObst }, { "noTarget", nEmpty }, { "deadEnds", #deadEnds },
			{ "narrow", #narrow }, { "try", s.bridgeTries }, { "us", self:nowUs() - t0 } })
		return
	end
	bp.typeIndex, bp.typePath = idx, path
	job.bridgePlan = bp
	self:log("BRIDGE", { { "town", t }, { "name", E.name(t) }, { "outcome", "plan" }, { "span", string.format("%.0f", bp.span) },
		{ "approach", string.format("%.0f", bp.approach) }, { "far", string.format("%.0f", bp.far) },
		{ "deck", string.format("%.1f", bp.deck) }, { "ship", bp.ship or "none" }, { "shipWhy", bp.shipWhy or "-" },
		{ "clearance", bp.clearance and string.format("%.1f", bp.clearance) or "-" }, { "deadEnd", bp.deadEnd },
		{ "heading", math.floor(math.deg(G.wrap(bp.heading)) % 360 + 0.5) }, { "type", path }, { "typeIndex", idx },
		{ "edges", #bp.inc.edges }, { "nodes", #bp.inc.nodes }, { "cands", cands or 0 }, { "skipped", nOther + nObst },
		{ "key", bp.key or "-" }, { "try", s.bridgeTries }, { "narrow", #narrow },
		{ "target", bp.target or (targets and "short" or "-") }, { "len", string.format("%.0f", BR.length(bp)) },
		{ "us", self:nowUs() - t0 } })
end

--- §69: what a steer town's bridge may cross to (ot_bridge.target): its neighbours (the gap list), the industries near
--- it, its own housed streets (2+ buildings). { { x, y, kind } }, capped.
function Driver:bridgeTargets(job, now)
	local out = {}
	local gp = job.style and job.style.gaps
	for _, nb in ipairs(gp and gp.list or {}) do out[#out + 1] = { x = nb.x, y = nb.y, kind = "town" } end
	local okI, ind = pcall(self.industryFor, self, job.town, now, job.ext)
	for _, it in ipairs((okI and ind and ind.list) or {}) do
		if #out >= 400 then break end
		out[#out + 1] = { x = it[1] or it.x, y = it[2] or it.y, kind = "industry" }
	end
	for _, ed in ipairs(job.edges or {}) do
		if #out >= 3000 then break end
		if (job.builtBy and job.builtBy[ed.id] or 0) >= 2 and ed.p0 and ed.p1 then
			out[#out + 1] = { x = (ed.p0[1] + ed.p1[1]) / 2, y = (ed.p0[2] + ed.p1[2]) / 2, kind = "houses" }
		end
	end
	return out
end

--- R6: the ship lines' stops { {x, y, line} } (E.shipLines, re-read every SHIP_REFRESH_S) and the water level (E.waterLevel,
--- else 0); a SHIPS debug line per read.
D.SHIP_REFRESH_S = 60
function Driver:shipStops(now)
	local E = self.E
	local c = self.shipCache
	if c and now - c.us < D.SHIP_REFRESH_S * 1e6 then return c.stops, c.wl end
	local stops, nLines, nVeh = {}, 0, 0
	local lines, read = nil, nil
	if E.shipLines then
		local ok, a, b = pcall(E.shipLines)
		if ok then lines, read = a, b end
	end
	for _, ln in ipairs(lines or {}) do
		nLines = nLines + 1
		nVeh = nVeh + (ln.vehicles or 0)
		for _, p in ipairs(ln.stops or {}) do stops[#stops + 1] = { x = p[1], y = p[2], line = ln.line } end
	end
	local wl, src = 0, "default"
	if E.waterLevel then
		local ok, a, b = pcall(E.waterLevel)
		if ok and tonumber(a) then wl, src = a, b or "?" end
	end
	self.shipCache = { us = now, stops = stops, wl = wl }
	self:debug("SHIPS", { { "lines", nLines }, { "read", type(read) == "number" and read or tostring(read or "-") },
		{ "stops", #stops }, { "vehicles", nVeh }, { "waterLevel", string.format("%.1f", wl) }, { "source", src } })
	return stops, wl
end

--- The bridge increment goes out as planned (no planner, no pruning): locked approach + span, no fill.
function Driver:bridgePlanStage(job, now)
	local bp = job.bridgePlan
	job.inc, job.mp, job.report = bp.inc, nil, nil
	job.inc.mix = core.mix(job.inc)
	local n = 0
	for _ in pairs(bp.lockKeys) do n = n + 1 end
	job.lockKeys, job.lockN, job.lockModeUsed = bp.lockKeys, n, "bridge"
	job.fill = "off"
	-- (CROSS_LATER, 2026-10-14: the far bank's dead end gets a dose at the build, again once its lots exist)
	if BR.CROSS_LATER then
		job.fillPts = BR.farPoints(bp, D.FILL_OFFSET)
		if #job.fillPts > 0 then job.fill, job.fillWhy = "dose", "bridgeEnd" else job.fillPts = nil end
	end
	job.stage = "send"
end

--- After a bridge build: saved on the town's frame, BRIDGE built line.
function Driver:bridgeBuilt(job, now)
	local s = self:townState(job.town)
	s.bridgeDone = true
	-- (the far end's cross-street junction and the crossing's heading: the bridgehead quarter's origin, M4)
	local cN = job.bridgePlan.inc and job.bridgePlan.inc.nodes and job.bridgePlan.inc.nodes[3]
	if cN then s.bridgeHead = { C = { cN.x, cN.y }, heading = job.bridgePlan.heading } end
	if cN and BR.CROSS_LATER then s.bridgeEnd = { x = cN.x, y = cN.y, pts = job.fillPts, us = now, doses = 0 } end
	self.E.sendEvent(SV.EVENT_ID, SV.EV_BRIDGE, { town = job.town })
	local nb = 0
	for _, e in ipairs(job.spec.edges) do if e.bridge then nb = nb + 1 end end
	self:log("BRIDGE", { { "town", job.town }, { "name", self.E.name(job.town) }, { "outcome", "built" },
		{ "edges", #job.spec.edges }, { "bridgeEdges", nb }, { "span", string.format("%.0f", job.bridgePlan.span) },
		{ "approach", string.format("%.0f", job.bridgePlan.approach or 0) }, { "bowed", job.bridgePlan.bowed == true },
		{ "crossLater", BR.CROSS_LATER }, { "type", job.bridgePlan.typePath } })
end

---------------------------------------------------------------------------
-- Green wedge frames (ot_wedge, 2026-10-13, real map run 2026-10-13_0232_sqot-dev: big armed towns blurred into blobs, the
-- game building ~60 % of the streets from its own unlocked tips). At a demand build of an armed town (ot_wedge.applies),
-- at most every FRAME_GAP_S, the unlocked dead ends in its wedges are linked by locked small streets (a ring road on the
-- wedge sides, the arm gates left open); the town's normal build follows (finish: "more"). FRAME lines.
D.WEDGES = true            -- false: no wedge reserve, no frames (the old behaviour)
D.OWN_EMPTY = true         -- the own empty budget (ot_core OWN_EMPTY_*) for unforced builds
D.FRAME_GAP_S = 90         -- real s between two frame attempts of a town (after a build, a refusal or none found)

function Driver:frameDecide(job, now)
	if not D.WEDGES or not WG.ON or job.force or job.dry or job.trigger ~= "demand" then return end
	if not job.style.wedges and not job.style.meadows then return end
	local E, t = self.E, job.town
	local s = self:townState(t)
	if now < (s.frameNextUs or 0) then return end
	s.frameNextUs = now + D.FRAME_GAP_S * 1e6
	local t0 = self:nowUs()
	local inc, why, info = core.frameIncrement(job.g, job.style, { terrain = job.sampler, exclude = s.exclude })
	info = info or {}
	if inc == nil then
		self:debug("FRAME", { { "town", t }, { "outcome", "none" }, { "kind", info.kind or "-" }, { "why", why }, { "cands", info.cands or 0 },
			{ "links", info.links or 0 }, { "coreR", info.coreR and math.floor(info.coreR) or "-" }, { "tipCap", D.tipCapText(info) },
			{ "tipCut", D.tipCutText(info) }, { "maxTipR", info.maxTipR and math.floor(info.maxTipR) or "-" },
			{ "bodyOut", info.bodyOut or "-" }, { "us", self:nowUs() - t0 } })
		return
	end
	job.framePlan = { inc = inc, info = info }
	self:log("FRAME", { { "town", t }, { "name", E.name(t) }, { "outcome", "plan" }, { "kind", info.kind or "wedge" },
		{ "shape", job.style.shape and job.style.shape.id or "-" },
		{ "cands", info.cands or 0 }, { "links", info.links or 0 }, { "edges", #inc.edges },
		{ "coreR", math.floor(info.coreR or 0) }, { "env", math.floor(info.env or 0) }, { "tipCap", D.tipCapText(info) },
		{ "tipCut", D.tipCutText(info) }, { "maxTipR", info.maxTipR and math.floor(info.maxTipR) or "-" },
		{ "bodyOut", info.bodyOut or "-" }, { "us", self:nowUs() - t0 } })
end

--- FRAME fields of the §75 tip cap (ot_wedge.tipCap; info from ot_core.frameIncrement): `tipCap=<m>` ("-": no cap, no
--- house data), `tipCut=<tips dropped>` (+ "@<m>" the farthest of them).
function D.tipCapText(info)
	return info and info.tipCap and string.format("%.0f", info.tipCap) or "-"
end
function D.tipCutText(info)
	local n = info and info.tipCut or 0
	if n > 0 and info.cutMaxR and info.cutMaxR > 0 then return string.format("%d@%.0f", n, info.cutMaxR) end
	return tostring(n)
end

--- The frame increment goes out as planned: every edge locked, no fill.
function Driver:framePlanStage(job, now)
	local fp = job.framePlan
	-- (real map run 2026-10-13_0342_sqot: Aylsham's frame was refused twice with the identical plan: the prune after the
	-- per-edge diagnosis excluded the colliding links and planned again, but this stage re-sent the stored increment.
	-- Now the excluded links (whole streets) are left out of it; links that remain go out on their own.)
	if (job.pruneRounds or 0) > 0 then
		local inc, kept, dropped = D.frameWithout(fp.inc, self:townState(job.town).exclude)
		if dropped > 0 then
			self:debug("FRAME", { { "town", job.town }, { "outcome", "pruned" }, { "kept", kept }, { "dropped", dropped } })
		end
		if kept == 0 then
			job.why = "frame:pruned"
			self:townState(job.town).frameNextUs = now + D.FRAME_GAP_S * 1e6
			return self:finish(job.town, "empty", now)
		end
		fp.inc = inc
	end
	job.inc, job.mp, job.report = fp.inc, nil, nil
	job.inc.mix = job.inc.mix or core.mix(job.inc)
	local keys, n = {}, 0
	for _, e in ipairs(job.inc.edges) do
		if e.key ~= nil and not keys[e.key] then keys[e.key] = true; n = n + 1 end
	end
	job.lockKeys, job.lockN, job.lockModeUsed = keys, n, "frame"
	job.fill = "off"
	job.stage = "send"
end

--- Marks the wide survey's points off the map (or within LAND_EDGE_M of its edge) `off` (ot_land: no land there).
function D.markOffMap(wide, bounds)
	if wide == nil or wide.rays == nil or bounds == nil then return end
	for _, ray in ipairs(wide.rays) do
		for _, p in ipairs(ray) do
			if MAP.nearEdge(bounds, p.x, p.y, D.LAND_EDGE_M) then p.off = true end
		end
	end
end

--- The landscape pull on the plan's style (ot_land, §62): the town's raw readings (cached per tree grid, wide survey
--- and forest ring radius), the style's field (forest mode, character, coast lean); when its text changes the cached
--- sector preference is redone, the lobe headings re-ordered, and one LAND line logged (always on, once per change).
function Driver:landRefresh(job, style)
	if not (D.LAND and LAND.ON) then
		if style.land ~= nil then style.land, style._irr, style._landText = nil, nil, nil end
		return
	end
	local t = job.town
	local s = self:townState(t)
	local extR = s.extR or (job.ext and job.ext.r) or 0
	local r0 = LAND.r0For(extR)
	local fg = s.forest
	if s.landWide ~= s.wide or s.landFg ~= fg or s.landR0 ~= r0 or s.landStats ~= s.stats or s.landTried == nil then
		local okR, rd = pcall(LAND.read, fg, s.wide, extR, s.stats)
		s.landRead, s.landWide, s.landFg, s.landR0, s.landStats, s.landTried = okR and rd or nil, s.wide, fg, r0, s.stats, true
		if not okR and not s.landErr then
			s.landErr = true
			self:log("LAND", { { "town", t }, { "err", tostring(rd) } })
		end
	end
	local okF, field = pcall(LAND.forStyle, s.landRead, style)
	if not okF then field = nil end
	local txt = LAND.text(field)
	if txt ~= style._landText then
		style.land, style._landText, style._irr = field, txt, nil
		style._lobeBase = style._lobeBase or style.lobeDirs
		style.lobeDirs = LAND.orderDirs(style._lobeBase, field)
	end
	if field and s.landLogged ~= txt then
		s.landLogged = txt
		local lb = {}
		for i, a in ipairs(style.lobeDirs or {}) do
			if i > 4 then break end
			lb[#lb + 1] = string.format("%.0f", math.deg(a) % 360)
		end
		self:log("LAND", { { "town", t }, { "name", self.E.name and self.E.name(t) or "-" },
			{ "cues", LAND.cuesText(field) }, { "k", string.format("%.2f", field.k) },
			{ "kRaw", string.format("%.2f", field.kRaw or field.k) }, { "A", string.format("%.2f", field.A or 0) },
			{ "to", string.format("%.0f", math.deg(field.peak) % 360) },
			{ "away", string.format("%.0f", math.deg(field.low) % 360) }, { "r0", field.r0 or 0 },
			{ "forest", s.landRead and s.landRead.forest ~= nil }, { "why", field.why or "-" },
			{ "shape", style.shape and style.shape.id or "-" }, { "lobes", #lb > 0 and table.concat(lb, "/") or "-" } })
	end
end

--- The landscape-aware skeleton on the plan's style (ot_skeleton, §63). A town with a saved frame: its `sk` (decoded
--- onto the shape's arms), or, a frame without one (an older save, or no arms to steer at its first build), the arms
--- exactly as the shape draws them. A town without a frame yet: planned from its tree grid and the §62 lean (cached
--- per grid until the frame goes out, so the first build and the saved frame agree). Skipped for a metropolis variant,
--- dev jobs (forced shape / form / pure) and towns without a grid. One SKEL line (always on) per town and change:
--- `town= name= shape= src=new|saved|old mode= arms=<deg>:<act>:<run>:<clear>:k<x>[:from<deg>][:max<m>]/...
--- dropped=<deg>:<why>:<run>/... minClear= boxed= why= hot=<hotspots moved>/<hotspots> clearM= r0=`.
function Driver:skeletonRefresh(job, style, saved)
	if not (D.SKEL and SK.ON) or style == nil or style.metro or job.pure or job.shape or job.form then return end
	local sh = style.shape
	local t = job.town
	local s = self:townState(t)
	local res, src = nil, "-"
	if sh ~= nil and SK.ARMED[sh.id] and not sh.dev then
		-- (the shape's own arms, before any skeleton: a frame-less town's skeleton is redone from them on a new grid)
		if sh._skArms0 == nil then sh._skArms0 = sh.arms end
		if sh._skDone then
			res, src = sh.skel, sh._skSrc
		else
			local frame = SV.frame(saved, t)
			local fo = style.forest
			local thetas = (style.grower == "organic" and style.radial) and SH.spokeHeadings(style) or nil
			if frame ~= nil and frame.skel then
				res, src = SK.decode(frame.skel, thetas), "saved"
				if res == nil then src = "badSave" end
			elseif frame ~= nil or s.frameSaved then
				src = "old"
			elseif s.forest ~= nil and s.forest.cover ~= nil then
				src = "new"
				local base = { id = sh.id, arms = sh._skArms0, centre = sh.centre, block = sh.block, site = sh.site }
				local key = SH.text(base)
				local c = s.skel
				if c and c.key == key and (c.fg == s.forest or s.frameSent) then
					res = c.res
				else
					local okP, r = pcall(SK.plan, base, { fg = s.forest, field = style.land,
						deep = FO.isDeep(fo) or style.deep ~= nil, extR = s.extR or (job.ext and job.ext.r) or 0, thetas = thetas,
						strict = style.grower ~= "organic" and (style.angleRange or 0) <= 10, char = style.charKind ~= nil })
					if not okP then
						self:log("SKEL", { { "town", t }, { "err", tostring(r) } })
						r = nil
					end
					res = r
					s.skel = { key = key, fg = s.forest, res = res }
				end
			else
				src = "noGrid"
			end
			sh.arms, sh.armK, sh.armMax, sh.skel = sh._skArms0, nil, nil, nil
			style.skelKey = nil
			if res ~= nil then
				SK.apply(sh, res)
				style.skelKey = SK.encode(res)
			end
			-- (a frame-less town decides again on a new grid (s.skel's cache) until its first build's frame went out)
			sh._skDone = (src ~= "new" and src ~= "noGrid") or s.frameSent == true or nil
			sh._skSrc = src
		end
	end
	-- (the hotspots of unshaped towns move off the woods, ot_select.irregularity)
	local irr = nil
	if sh == nil or sh.id == "compact" then
		local okI, c = pcall(SEL.irregularity, style)
		if okI then irr = c end
	end
	local hot = irr and string.format("%d/%d", irr.hotMoved or 0, #(irr.hotspots or {})) or "-"
	local txt = (sh and sh.id or "-") .. "|" .. src .. "|" .. SK.armsText(res) .. "|" .. SK.droppedText(res) .. "|" .. hot
	if s.skelLogged ~= txt and (res ~= nil or src == "old" or (irr and (irr.hotMoved or 0) > 0)) then
		s.skelLogged = txt
		local mc = SK.minClear(res)
		self:log("SKEL", { { "town", t }, { "name", self.E.name and self.E.name(t) or "-" }, { "shape", sh and sh.id or "-" },
			{ "src", src }, { "mode", res and res.mode or "-" }, { "arms", SK.armsText(res) }, { "dropped", SK.droppedText(res) },
			{ "minClear", mc and string.format("%.0f", mc) or "-" }, { "boxed", res and res.boxed or 0 },
			{ "why", res and res.why or "-" }, { "hot", hot }, { "clearM", SK.CLEAR_M },
			{ "r0", res and res.r0 and string.format("%.0f", res.r0) or "-" } })
	end
end

--- Headings for the lobes of an unshaped town (ot_select LOBE_R): the road exits (strongest first, at most 4), else the
--- two contour directions of a hillside / the valley axis both ways, else nil (the seeded preference decides).
function D.lobeDirs(exits, stats)
	local out = {}
	for i = 1, math.min(#(exits or {}), 4) do out[#out + 1] = exits[i][1] end
	if #out > 0 then return out end
	local dr = stats and stats.dirRelief
	if dr and (stats.meanSlope or 0) > 0.03 and (dr.valley or dr.ridge) and dr.axis then
		return { dr.axis, G.wrap(dr.axis + math.pi) }
	end
	local rel = stats and stats.relief
	if rel and (rel.grade or 0) > SH.HILLSIDE_GRADE and rel.dir then
		return { G.wrap(rel.dir + math.pi / 2), G.wrap(rel.dir - math.pi / 2) }
	end
	return nil
end

--- The frame increment without the streets (links) that have an excluded piece key: (inc, kept edges, dropped edges).
--- Whole links go, never a part of one (a half link would be a locked stub into the wedge).
function D.frameWithout(inc, exclude)
	local bad = {}
	for _, e in ipairs(inc.edges) do
		if e.key ~= nil and exclude and exclude[e.key] then bad[e.street or e.key] = true end
	end
	local keep = {}
	for i, e in ipairs(inc.edges) do
		if not bad[e.street or e.key] then keep[#keep + 1] = i end
	end
	if #keep == #inc.edges then return inc, #keep, 0 end
	local out = D.subIncrement(inc, keep)
	out.mix = inc.mix
	return out, #keep, #inc.edges - #keep
end

function Driver:frameBuilt(job, now)
	local s = self:townState(job.town)
	s.frames = (s.frames or 0) + 1
	self.counts.frames = (self.counts.frames or 0) + 1
	self:log("FRAME", { { "town", job.town }, { "name", self.E.name(job.town) }, { "outcome", "built" },
		{ "kind", job.framePlan and job.framePlan.info and job.framePlan.info.kind or "wedge" }, { "edges", #job.spec.edges },
		{ "frames", s.frames } })
end

local STAGES = { assess = Driver.assess, terrain = Driver.terrain, forest = Driver.forest, snapshot = Driver.snapshot, plan = Driver.plan,
	send = Driver.send, diag = Driver.diag, fill = Driver.fill, glock = Driver.glockSend, glockWait = Driver.glockWait }

--- Starts a job for town t outside the round-robin (dev tools). o = { force = bool (ignore needs room and
--- "New towns only"), styleMode = "main" | "region" | profile id, pure = bool (a profile id without its era's
--- outer zone), newTemplates = bool (force the template era; nil: the year decides), year = n (style inputs as of
--- that year instead of the map's; its template era unless newTemplates says otherwise), dry = bool (plan and
--- pre-check, never send), maxEdges = n, shape = ot_shape id (forced town shape), override = style fields
--- (D.applyOverride), lock = true|"all"|"shape"|false|"off" (D.lockMode; nil: the default), fill = "dose"|"metro"|
--- "off" (D.fillKind; nil: the default), fillStreets / fillUpgrade = DevelopAt's flags for the fill (dev probe),
--- metro = ot_metro variant (forced metropolis), metroCentres = true (polycentric centres from the first build),
--- form = ot_form id (forced town form), limits = { leadM, armFillM, headForm } (ot_select: the head start's lead
--- limit and form steering), motif = ot_motif kind id (forced motif, dev tools),
--- onDone = function(job, outcome) }. Returns the job, or nil while a job
--- or command is running. After it ends, job.why says why it didn't build (empty / fail) and job.cost what a
--- build cost.
function Driver:startJob(t, now, o)
	if self.job ~= nil or self.inflight then return nil end
	o = o or {}
	self.job = { town = t, stage = "assess", startUs = now, force = o.force == true, styleMode = o.styleMode,
		pure = o.pure == true, newTemplates = o.newTemplates, dry = o.dry == true, maxEdgesOverride = o.maxEdges,
		year = o.year, shape = o.shape, override = o.override, onDone = o.onDone, lock = o.lock, fill = o.fill,
		fillStreets = o.fillStreets == true, fillUpgrade = o.fillUpgrade == true, metro = o.metro,
		metroCentres = o.metroCentres == true, form = o.form, limits = o.limits, motif = o.motif, forestLane = o.forestLane,
		charKind = o.charKind }
	return self.job
end

--- Runs one stage of the current job (or checks its callback / timeout). Returns true while a job is active.
function Driver:advance(now, saved)
	local job = self.job
	if job == nil then return false end
	if job.stage == "wait" then
		if job.result then
			local ok, err = pcall(self.done, self, job, now)
			if not ok then
				self.inflight = false
				self:log("ERROR", { { "stage", "done" }, { "town", job.town }, { "err", err } })
				job.glockStarted = true
				self:finish(job.town, "fail", now)
			end
		elseif now - job.sentUs > D.WAIT_TIMEOUT_S * 1e6 then
			self.inflight = false
			self:log("FAILED", { { "town", job.town }, { "why", "timeout" } })
			job.why = "timeout"
			self:finish(job.town, "fail", now)
		end
		return self.job ~= nil
	end
	local fn = STAGES[job.stage]
	-- (hang guard, 2026-10-13: every other stage ends by STAGE_HANG_US; the plan stage guards its own coroutine slices)
	local ok, err
	if job.stage == "plan" then ok, err = pcall(fn, self, job, now, saved)
	else ok, err = D.guard(self:clockFn(), D.STAGE_HANG_US, fn, self, job, now, saved) end
	if not ok then
		if job.stage == "wait" or job.stage == "fill" or job.stage == "glockWait" then self.inflight = false end
		job.glockStarted = true
		self.counts.fails = self.counts.fails + 1
		self:log("ERROR", { { "stage", job.stage }, { "town", job.town }, { "err", err } })
		job.why = "error:" .. tostring(err)
		-- an error while filling: the build itself stands
		local out = job.stage == "fill" and "built" or "fail"
		if (job.stage == "glock" or job.stage == "glockWait") and job.glockOutcome then out = job.glockOutcome end
		self:finish(job.town, out, now)
	end
	return self.job ~= nil
end

--- One tick. now = the engine's real-time clock (us; the driver's running time follows from it, Driver:gameClock);
--- saved = the game script's state (read-only copy: state:get()).
function Driver:tick(now, saved)
	local paused
	now, paused = self:gameClock(now)
	-- (the saved Works / districts the load check dropped: a filtered view until the drop event lands)
	if self.offshootDrop then saved = SV.withoutOffshoots(saved, self.offshootDrop) end
	self.saved = saved
	if self.phase == "off" then return end
	-- (2026-10-17: paused, nothing new starts; a build callback that came is handled)
	if paused then return self:pausedTick(now, saved) end
	-- (landscape stop names: independent of the growth jobs, one stop per STOP_CHECK_S at most)
	if self.phase == "run" then
		local okS, errS = pcall(self.stopsTick, self, now, saved)
		if not okS and not self.stopsErrLogged then
			self.stopsErrLogged = true
			self:log("ERROR", { { "stage", "stops" }, { "err", errS } })
		end
		-- (industrial satellites, ot_works: a created town is found once its command answered)
		local okC, errC = pcall(self.offshootCheck, self, now, saved)
		if not okC and not self.offshootErrLogged then
			self.offshootErrLogged = true
			self:log("ERROR", { { "stage", "offshootCheck" }, { "err", errC } })
		end
		local okW, errW = pcall(self.worksTick, self, now, saved)
		if not okW and not self.worksErrLogged then
			self.worksErrLogged = true
			self:log("ERROR", { { "stage", "works" }, { "err", errW } })
		end
		-- (the town window's card, 2026-10-17: the towns' summaries, in batches)
		local okU, errU = pcall(self.uiTick, self, now, saved)
		if not okU and not self.uiTickErrLogged then
			self.uiTickErrLogged = true
			self:log("ERROR", { { "stage", "card" }, { "err", errU } })
		end
	end
	if self.phase == "init" then
		local ok, err = pcall(self.init, self, now, saved)
		if not ok then
			self.phase = "off"
			self:log("ERROR", { { "stage", "init" }, { "err", err } })
		end
		return
	end
	if self.job == nil then
		if self.inflight or now < self.nextUs or D.held() then return end
		-- (landscape names first: the head start and the checks wait until they are done, NAMES_MAX_S at most)
		-- (strong characters first, 2026-10-14: the names can read the picks, ot_character; the terrain read is shared)
		if self:charsTick(now) then return end
		if self:namesTick(now) then return end
		if self:headTick(now) then return self:advance(now, saved) end
		-- (the supply-driven weighting, §66: its own pace, one command at a time, never beside a job)
		if self:rciTick(now, saved) then return end
		self.nextUs = now + D.CHECK_S * 1e6
		local t = A.pick(self.sched, self:townIds(now), now)
		if t == nil then return end
		self.job = { town = t, stage = "assess", startUs = now }
	end
	self:advance(now, saved)
end

---------------------------------------------------------------------------
-- The town window's Organic Towns card (2026-10-17, ot_card; gui/ot_card.script.tl reads the saved state). The card
-- computes most of what it shows from the saved frames, offshoot lists and weighting; two values only the driver has:
-- the growth phase (ot_upward.levelPhase from the level maturity of the town's check, `low` for a kind without level
-- weights) and the offshoot readiness (ot_satpace ratio, from the last paceGate). Driver:uiNote keeps them per town at
-- each check on a new map; Driver:uiTick writes the towns whose summary moved (ot_card.summaryMoved) in one EV_UI event
-- at most every UI_FLUSH_S, UI_BATCH towns at most. One CARD line for the session's first batch, then debug lines.
D.UI = true
D.UI_FLUSH_S = 30

function Driver:uiNote(t, m)
	if not D.UI or m == nil or self.newMap ~= true then return end
	local s = self:townState(t)
	local pb = (m.buildings or 0) > 0 and m.caps and (m.caps.actual or 0) / m.buildings or nil
	local matL = UP.levelMat(m.dem and m.dem.mat or nil, m.buildings)
	local lv = CH.levels(self:charKindOf(t))
	local phase
	if lv == "off" or self:isDeepTown(t) then
		phase = "low"
	else
		phase = UP.levelPhase(matL, pb, self:densifyDrawn(t) == true, lv == "early",
			UP.eraTop(self.E.year and self.E.year() or nil))
	end
	local ready = nil
	if s.paceRatio ~= nil and not self:isOffshootTown(t) then ready = s.paceRatio end
	local v = CARD.summary({ phase = phase, mat = matL, ready = ready })
	if v == nil then return end
	self.uiPending = self.uiPending or {}
	self.uiPending[t] = v
end

function Driver:uiTick(now, saved)
	if not D.UI or self.uiPending == nil or now < (self.uiNextUs or 0) or self.E.sendEvent == nil then return end
	self.uiNextUs = now + D.UI_FLUSH_S * 1e6
	self.uiSent = self.uiSent or {}
	local list, keep, n = {}, {}, 0
	for t, v in pairs(self.uiPending) do
		n = n + 1
		if n > SV.UI_CAP then break end
		if CARD.summaryMoved(self.uiSent[t] or SV.ui(saved, t), v) then
			if #list < SV.UI_BATCH then list[#list + 1] = { t = t, v = v } else keep[t] = v end
		end
	end
	self.uiPending = next(keep) ~= nil and keep or nil
	if #list == 0 then return end
	table.sort(list, function(a, b) return a.t < b.t end)
	for _, e in ipairs(list) do self.uiSent[e.t] = e.v end
	self.E.sendEvent(SV.EVENT_ID, SV.EV_UI, { towns = list })
	local f = { { "event", "summary" }, { "towns", #list }, { "first", list[1].t .. "=" .. list[1].v } }
	if not self.uiLogged then
		self.uiLogged = true
		self:log("CARD", f)
	else
		self:debug("CARD", f)
	end
end

--- The game's notification feed when the mod created a Works / district town (kind "works" | "district"): the
--- "Notifications" / "add" scripting event with our type (notify/ot_new_town.*), once per town (ot_card.shouldNotify:
--- this session's set and the saved offshoot lists). The new town's creation revision guards the click against a
--- reused id. One CARD line per notification.
function Driver:noteNewTown(town, parent, kind)
	local E = self.E
	if E.sendEvent == nil then return end
	self.noted = self.noted or {}
	if not CARD.shouldNotify(self.saved, self.noted, town) then return end
	self.noted[town] = true
	local rev = E.revision and E.revision(town) or nil
	local p = CARD.noteParams(town, parent, kind, E.name(town), E.name(parent), rev)
	E.sendEvent("Notifications", "add", { type = CARD.NOTE_TYPE, params = p, autoDismissDuration = CARD.NOTE_DISMISS_MS })
	self:log("CARD", { { "event", "notify" }, { "town", town }, { "name", p.name }, { "kind", p.kind }, { "parent", parent },
		{ "parentName", p.parentName }, { "rev", rev or "-" } })
end

return D
