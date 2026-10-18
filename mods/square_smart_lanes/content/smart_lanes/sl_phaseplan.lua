-- Smart Lanes: designed traffic light phase plans (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_phaseplan.lua. Steps 2 and 3 of PHASES_PLAN.md: from the conflict
-- map of sl_phases.lua (P.build) to a list of phases the game can run (TrafficLightState: lockedLanes,
-- duration, minDuration, canSkip; docs/findings.md "Traffic light phase records, units and defaults").
-- Step 4 (the setting "Light phases", sl_write.lua W.planLights / W.remapLights) writes the plan;
-- the calibration below comes from the game's measured default phases (findings.md "Default traffic
-- light phases, measured in game": 6 phases, greens 18.9-27.1 s, all-red 6 / 6 / 9 s, a 3 s
-- pedestrian phase, canSkip everywhere with minDuration 1.5, cycles 71-78 s).
--
-- TF3 has no permissive movement: an unlocked connection drives as if green and never gives way
-- (findings.md "A connection unlocked in a phase does not give way"), so every phase is conflict-free
-- under the map M except where explicitly accepted: the axis plan (below) accepts, as the game's own
-- default phases do, the conflicts within one road (a far turn against the opposite straight), explicitly
-- and narrowly (plan.axis, PP.validatePlan opts.axis); never between roads, never with a green crosswalk.
-- Every plan passes PP.validatePlan before it is returned (else nil, reason: the caller keeps the game's
-- phases).
--
-- No classic fallback (user decision 2026-10-16, PLAN.md "No classic fallback"): the axis plan is the only
-- Smart Lanes plan. The classic patterns (protected / split / lead-lag / t3, the default before rev 8) lost
-- to the game's phases in every bench set (RESULTS.md) and are gone, with the generic colouring for other
-- shapes. Where no axis plan can be made PP.plan returns nil and the reason, and every caller keeps the
-- game's phases there (logged PHASES ... pattern=none plan_fail=<reason>):
--   "no_axis_shape"  the junction is no x4 (4 arms in two opposite pairs) and no t3 (3 arms with a main road)
--   "axis_extra"     a lane finds no road phase (it conflicts with its own road's phase)
--   "invalid_<why>"  the axis plan fails PP.validatePlan
--   "too_many_phases" more states than PP.MAX_STATES
--
-- Axis plan (the default since rev 8, the only plan since 2026-10-16; x4 and t3; PHASES_PLAN.md "Axis plan
-- (default since rev 8)"). A player's report 2026-10-14 (not verified in game): at a lit city crossroads (1 car lane
-- and a curbside bus lane each way, tram) the classic x4 plan (4 approach phases of ~16 s, an all-red after
-- each) backed traffic up across town; the game's default and their own 5-phase plan (head start 12.6 s,
-- main road both directions 23.7 s, pedestrians 6 s, cross road 21.6 s, pedestrians 6 s; every vehicle
-- phase skippable with 1.5 s, the pedestrian phases not) run far better: 2 long greens per cycle.
--   * Roads: x4 = the two axes (axesOf), the one with more demand first (lane counts without laneDemand;
--     ties: more lanes, then the lower segment id); t3 = the main road (tShape), then the side road.
--   * Per road one phase, every connection of its approaches (bus-lane, tram and U-turn connections
--     included): each approach whole. Conflicts between connections of the road's own approaches are
--     accepted there (fits with the phase's axis set; plan.axis[state] = its approach segments). Lanes of
--     the other road join only conflict-free (step 3) or, a dedicated curb lane, where it only merges (step
--     4b, as When safe; beside a bus lane only while that bus lane is green). Crosswalks stay red.
--   * After each road phase a pedestrian phase (tag "ped"): every crosswalk green, every vehicle red,
--     opts.pedPhase s (6, the player's; the game runs a 3 s walk + 9 s all-red). It is the clearance
--     between the roads: no all-red phases (opts.allRed is for fan plans). Without crosswalks an all-red
--     clearance instead (PP.vehClear: 2..4 s).
--     Both may skip (canSkip, as every phase of the game's default; user decision 2026-10-14) with
--     minDuration = opts.pedClearance (3 s, 0.5 s steps; at most the phase's duration): the junction is still
--     cleared every cycle (cars left inside the box drive out, as with the game's phases), but an empty
--     pedestrian phase ends early instead of holding every road red for its full 6 s.
--   * Head start (tag "head", before its road's phase): one approach alone, every movement, only when
--     measured demand (info / opts.laneDemand) makes it >= opts.headStartRatio (1.5) x its opposite's;
--     never from lane counts. Weight: the excess (dominant - opposite) with green base 0; the road's phase
--     then weighs the opposite's demand. No caller passes laneDemand yet (Re-time changes only lengths).
--   * Weights: a road phase = its larger approach's demand (a lane = 1); greens from the calibration below
--     (15 s + 4 s x weight, the cycle scaled into 40..90 s). canSkip with minDuration 1.5 s on road and head
--     start phases. The player's crossroads: 24 s / 6 s / 24 s / 6 s = 60 s (theirs 57.3 s without the
--     head start).
--   * Green floor (opts.gameGreenFloor, rev 8, user 2026-10-14 "shorter phases than default harm busy
--     junctions"): a road phase is never shorter than the game's own default green for its lanes
--     (PP.gameGreen: entry lanes of the road's larger approach, from the measured defaults: 2 lanes 23.7 s,
--     3 lanes 27.1 s; 1 lane 18.9 s, the shortest default seen; beyond 3 lanes +3.4 s per lane), so a fresh
--     axis plan gives every road at least the default's green.
--   * Every lane must find its road phase; otherwise ("axis_extra", or an invalid plan) no plan: the game's
--     phases stay. Other shapes (5+ arms, a skewed or one-sided crossing): no plan ("no_axis_shape").
--
-- Pipeline (PP.plan):
--   Whole lanes (2026-10-14, a player's report: "every phase needs to allow all connected lanes of a
--   direction to go at the same time, or the one car in the line that wants to turn left while
--   everybody else goes straight blocks the flow and prevents the phase skip"): an entry lane
--   (segment0, lane0) is all green or all red in every phase. In a part-green lane the car at the
--   head may wait for a red movement, so the green ones behind it gain nothing, and the lane, never
--   empty, keeps a demand-actuated phase from ending (canSkip). Every step below adds whole lanes
--   (all-or-nothing, joinLane), and PP.validatePlan refuses a part-green lane ("part_lane:"). A lane is
--   keyed by its connections' entry (segment0, lane0) whatever they carry: a lane shared by road and
--   tram connections is one lane, a tram-only track or a bus-only lane is a lane of its own. Fan plans
--   too (their lanes fan to every exit, so another approach's lane rarely joins a fan phase).
--   1. Shape and pattern: seed movements per phase (the axis plan above, or the fan plan below).
--   2. Seeds go in as whole entry lanes: a seed pulls in every connection of its lane. A seed lane
--      that conflicts with something already green in its phase is skipped there and placed below with
--      the lanes the pattern did not place (bus lanes not placed in 2b): the first phase where it fits
--      whole, else a new phase (an axis plan: no new phase, "axis_extra").
--   2b. Bus lanes go with their approach (2026-10-14, the same player: a stopped bus on a red curbside
--      bus lane blocks the car lane's right turn beside it, "the collision check of the stopped vehicles
--      stretches ahead to let them cut into traffic"): a bus-only entry lane (info.bus, the view's bus
--      set; its connections are kept as read) joins, whole, every phase where a car connection of its
--      approach (same segment0) is green. Its conflicts with its own approach's connections (it crosses
--      or merges with the car lanes beside it) are accepted (fits, PP.validatePlan with plan.bus); a
--      conflict with another approach's green movement or a green crosswalk is not: the bus lane then
--      stays red in that phase, all of it (e.g. a bus left turn in a phase where the opposite straight is
--      green). Axis and fan plans seed every connection of an approach, bus lanes included.
--   3. Maximal phases: every lane is added to every phase where all its connections conflict with
--      nothing green (in lane order). Before a car lane of an approach with a bus lane, the bus lane
--      tries to join (2b's rule); a car lane carrying a curb turn there joins only where a bus lane of
--      its approach is green (the turn would wait behind the stopped buses otherwise).
--   4. Crosswalks: added to every phase where they conflict with nothing. A crosswalk that fits
--      nowhere takes a phase from connections that are green in another phase as well (fewest
--      straights, then fewest connections, then the earliest phase; whole lanes only): the parallel
--      crosswalk beats the kerb turn into its road, which keeps its other phases. Still nowhere (an
--      unknown crosswalk entity conflicts with every connection): one pedestrian phase with every
--      vehicle red (opts.unknownCrosswalk "ped_phase", default) or no plan ("refuse").
--   4b. Kerb merges (opts.kerbMerge, default true; not in fan plans): after the crosswalks, every lane
--      whose connections are all kerb turns (class "kerb") is added to every phase where their only
--      conflicts with green entries are merges (another approach's green stream ending in its exit
--      lane); a crossing or a crosswalk still keeps it out. A kerb lane beside a bus lane only where a
--      bus lane of its approach is green (step 3). The same rule as "Free kerb turn: When safe" (sl_lights L.kerbPhases SAFE,
--      user decision 2026-10-12: in game a freed turner merged into the green stream tolerably and
--      the junction ran more efficiently; findings roads.md "A connection unlocked in a phase does
--      not give way", "Later observations"), so the plan subsumes When safe. Done last, on top of
--      the strict plan, so no straight or crosswalk ever loses a phase to a merging kerb turn (steps
--      2-4 are unchanged); the plan lists the kerb turns it treated so (plan.kerb, 0-based set) and
--      PP.validatePlan accepts exactly those merges.
--   5. All-red clearance (opts.allRed, default "auto"; fan plans only): one fully locked phase after every phase, as
--      the game's defaults have (6 / 6 / 9 s there). Vehicles: clamp(round(junction width /
--      clearSpeed 8 m/s), 2, 4) s, the width = the widest arm's road (driving lanes x 4.5 m), 3 s when
--      unknown; after the pedestrian phase max(that, pedClear 3 s). A number: that after every phase;
--      0: none.
--   6. canSkip and timing (below), states, validation.
--
-- Fan plan:
--   * fan (opts.fan, the sl_fan zone's measuring mode: PHASES_PLAN.md "Fan mode"; kind x4_fan / t3_fan /
--     fan): the connections are sl_cross X.fanConns (every entry lane to every exit lane of every other
--     arm), whose movements of one approach cross and merge among themselves by design. Seeds: one
--     phase per approach (all its connections), approaches in arm order; then steps 3-6 as everywhere:
--     every other approach's lane that conflicts with nothing green joins a phase (whole), crosswalks
--     (a full fan uses every arm, so they mostly get the pedestrian phase), all-red, timing. Conflicts
--     between two connections of the same approach (M.seg0) are accepted in fan plans only (fits,
--     PP.validatePlan with opts.fan); a conflict between approaches, or with a crosswalk, never is.
--     A fan plan that fails is no plan (the fan's lanes are then not written: sl_write W.remapLights).
--
-- canSkip (opts.skip):
--   "all" (default, the game's way): every phase may skip / end early with minDuration 1.5 s
--     (skipMinGreen); the all-red clearances never skip (a fully locked phase has no lanes that would
--     hold it: it could end at once and lose the clearance). No starvation rule is needed: canSkip ends a
--     phase only "when these lanes are empty and traffic is waiting on another phase" (Crossing window),
--     so a phase with waiting traffic runs. Pedestrian crossing time goes into the green, not
--     minDuration (inferred: a crosswalk with pedestrians on it is a lane that is not empty).
--   "turns" (an option, no caller uses it): a phase may skip when everything green only in it is a turn connection
--     (a far turn or U-turn); a phase that is the only green of a straight, a kerb turn or a
--     crosswalk never skips; at least one phase never skips; minDuration = skipMinGreen or the
--     pedestrian need. "none": no phase skips.
--
-- Timing (PP.timing):
--   * Weight of a phase: per approach, the demand of its entry lanes whose seed movements are first
--     placed in that phase (a lane with k movement classes counts 1/k per class; demand = 1 per lane,
--     or info/opts.laneDemand["seg:lane"]; a unit whose seeds a crosswalk took is shared by the phases
--     it is green in); the phase weight is the largest over approaches (approaches run side by side).
--     Lane counts stand in for traffic until the traffic log gives numbers. (Rev 8 had a main-road
--     factor from the arms' lane counts; removed 2026-10-14: a player's busiest road has fewer lanes on
--     purpose, so lane counts guessed the main road wrong. Re-time, sl_retime.lua, measures instead.)
--   * Floors: every vehicle phase >= minGreen, a pedestrian-only phase >= pedClear. Pedestrians: a
--     crosswalk green in phase p needs, from the start of p to the end of its run of consecutive green
--     phases plus the all-red right after it, crossing length / pedSpeed + pedClear seconds (skip
--     "turns": a skippable phase counts its minDuration for itself, 0 when a later one; a skippable
--     phase that would need more than MAX_MIN_DURATION never skips). The crossing length is the
--     crossed road's width (info.crossLen, else roadLanes x laneWidth, else defaultCrossLen; an
--     unknown crosswalk takes the widest arm).
--   * Green: target g = greenBase + greenPerLane x weight (15 s + 4 s per lane: 19 / 23 / 27 s for 1 /
--     2 / 3 lanes, the game's measured 18.9-27.1 s), d = max(floor, s x g) with one factor s for every
--     phase so that the cycle (all-red included) lies in [cycleMin, cycleMax] (s = 1 when the targets
--     already do; above only when the floors need it, plan.warnings "cycle_over_max"); whole seconds
--     in 1..60 (a floor rounds up), minDuration in 0.5 s steps <= min(duration, 30) (the Crossing
--     window's sliders; findings.md).
--
-- Bounded: the map's bounds (sl_phases), at most opts.maxPhases phases (else nil "too_many_phases"),
-- bisection and loops by fixed counts.

local Phases = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"

local PP = {}

PP.DEFAULTS = {
	minGreen = 6,           -- s, least green of a vehicle phase
	pedSpeed = 1.2,         -- m/s
	pedClear = 3,           -- s added to the walk time (a pedestrian-only phase's green, as the game's 3 s)
	laneWidth = 4.5,        -- m per driving lane (town roads: 4 m inner, 5 m kerb lanes)
	defaultCrossLen = 14,   -- m, when nothing is known about the crossed road
	cycleMin = 40,          -- s
	cycleMax = 90,          -- s (the game's default cycles: 71-78 s, findings.md)
	-- green target of a phase = greenBase + greenPerLane x weight (lanes): 1 / 2 / 3 lanes -> 19 / 23 / 27 s,
	-- the game's measured 18.9 / 21.6 / 23.7 / 27.1 s (findings.md "Default traffic light phases, measured in game")
	greenBase = 15,         -- s
	greenPerLane = 4,       -- s per weight unit (one lane)
	skipMinGreen = 1.5,     -- s, minDuration of a skippable phase (the game's 1.5)
	allRed = "auto",        -- clearance after every phase (fan plans): "auto" (see clearances) | seconds | 0 (none)
	clearSpeed = 8,         -- m/s a vehicle clears the junction at ("auto")
	clearMin = 2,           -- s ("auto": vehicle clearance range)
	clearMax = 4,           -- s
	clearDefault = 3,       -- s, vehicle clearance when no road width is known
	maxPhases = 8,
	unknownCrosswalk = "ped_phase", -- "ped_phase" | "refuse"
	skip = "all",           -- "all" (the game: every phase but the all-red) | "turns" | "none"
	pedYield = false,       -- true: turning vehicles wait for pedestrians (unverified): "ped" conflicts allowed
	fan = false,            -- true: fan plan (sl_fan zones): one phase per approach, conflicts within an approach accepted
	kerbMerge = true,       -- step 4b: kerb turns also go where they only merge into a green stream (as When safe)
	pedPhase = 6,           -- s, the axis plan's pedestrian phase after each road (a player's 6 s; the game: 3 s walk + 9 s all-red)
	pedClearance = 3,       -- s, minDuration of the axis plan's pedestrian / no-crosswalk all-red phases (they may skip); 0.5 s steps
	gameGreenFloor = true,  -- axis plan: a road phase at least the game's default green for its lanes (PP.gameGreen)
	headStartRatio = 1.5,   -- axis plan: a head start when one approach's demand >= this x its opposite's (laneDemand only); false: never
	axis = false,           -- PP.validatePlan only: true accepts the conflicts within a state's road (plan.axis), see there
}
PP.MIN_DURATION = 1         -- the Crossing window's duration slider: 1..60 whole seconds
PP.MAX_DURATION = 60
PP.MAX_MIN_DURATION = 30    -- minDuration slider: 0..30 s in 0.5 s steps
PP.MIN_CLEAR = 1            -- s, least minDuration of a skippable clearance phase (PP.validatePlan "clear_min")
PP.MAX_STATES = 32          -- validation bound (8 phases + all-red after each, with room)
PP.AXIS_TOL = 45            -- deg off 180 for two arms to form an axis
-- The game's default green by entry lanes of a road's larger approach (docs/findings/roads.md "Default traffic light
-- phases, measured in game", probe session 2026-10-12_0753: a 2x2 crossroads 23.70 s, a 3x3 one 27.09 s; the
-- single-approach phases of a 2-lane / 3-lane T 18.86 / 21.55 s; no 1-lane default was measured: the shortest seen).
PP.GAME_GREENS = { 18.9, 23.7, 27.1 }
PP.GAME_GREEN_PER_LANE = 3.4 -- s per lane beyond the table (27.09 - 23.70)

--- The game's default green (s) for a road whose larger approach has `lanes` entry lanes (see PP.GAME_GREENS):
-- 1 -> 18.9, 2 -> 23.7, 3 -> 27.1, then +3.4 s per lane; at most PP.MAX_DURATION.
function PP.gameGreen(lanes)
	local l = math.floor(tonumber(lanes) or 1)
	if l < 1 then l = 1 end
	local t = PP.GAME_GREENS
	local g = t[l] or (t[#t] + PP.GAME_GREEN_PER_LANE * (l - #t))
	return math.min(PP.MAX_DURATION, g)
end

local function isTurnCls(c) return c == "far" or c == "u_turn" end

local function sortedKeys(set)
	local out = {}
	for k in pairs(set) do out[#out + 1] = k end
	table.sort(out)
	return out
end

local function options(opts)
	local o = {}
	for k, v in pairs(PP.DEFAULTS) do o[k] = v end
	for k, v in pairs(opts or {}) do o[k] = v end
	return o
end
PP.options = options

--- Classes from the arm angles alone (for connections the caller has no class for): signed turn from
-- the heading into the node to the exit's direction, left positive; within 45 deg straight; towards
-- the driving side (side "right": right turns) kerb, else far; segment0 == segment1 u_turn.
function PP.classesFromArms(conns, arms, side)
	local ang = {}
	for _, a in ipairs(arms or {}) do ang[a.seg] = a.angle end
	local out = {}
	for i, c in ipairs(conns or {}) do
		if c.segment0 == c.segment1 then out[i] = "u_turn"
		elseif ang[c.segment0] ~= nil and ang[c.segment1] ~= nil then
			local t = Phases.norm(ang[c.segment1] - ang[c.segment0] - 180)
			if t > 180 then t = t - 360 end
			if math.abs(t) <= 45 then out[i] = "straight"
			elseif (t < 0) == (side ~= "left") then out[i] = "kerb"
			else out[i] = "far" end
		end
	end
	return out
end

--- Planner input from an sl_cross view: arms from the world, classes from the view (angles for the
-- rest), the driving side, road lanes per arm (driving lanes both ways, for the crossing length), the
-- view's bus-only lane ends (Ring.busLanes: { [seg] = { [lane] = true } }, nil without; step 2b).
function PP.infoFromView(v, world, n, conns)
	local arms = Phases.armsFromWorld(world, n)
	local roadLanes = {}
	for _, a in ipairs(arms) do
		local s = world.seg(a.seg)
		local k = 0
		for _, l in ipairs((s and s.lanes) or {}) do
			if l.road or l.tram then k = k + 1 end
		end
		if k > 0 then roadLanes[a.seg] = k end
	end
	return { conns = conns, arms = arms, cls = Phases.classesFromView(conns, v), side = v and v.side, roadLanes = roadLanes,
		bus = v and v.bus or nil }
end

---------------------------------------------------------------------------
-- Context: approaches, lanes, classes

local function context(M, info, o)
	local conns = info.conns or {}
	local arms = {}
	for _, a in ipairs(info.arms or {}) do
		if a.seg ~= nil and type(a.angle) == "number" then arms[#arms + 1] = { seg = a.seg, angle = Phases.norm(a.angle) } end
	end
	table.sort(arms, function(p, q)
		if p.angle ~= q.angle then return p.angle < q.angle end
		return tostring(p.seg) < tostring(q.seg)
	end)
	local derived = PP.classesFromArms(conns, arms, info.side)
	local given = info.cls or M.cls or {}
	local ctx = { n = M.n, conns = conns, cls = {}, arms = arms, rank = {}, angle = {}, ap = {}, apOrder = {},
		used = {}, lanesOf = {}, laneConns = {}, laneKey = {}, laneOrder = {}, laneSeg = {}, o = o, info = info,
		busConn = {}, busLane = {}, apBus = {}, laneKerb = {}, laneAllKerb = {} }
	local bus = type(info.bus) == "table" and info.bus or nil
	for r, a in ipairs(arms) do
		if ctx.rank[a.seg] == nil then ctx.rank[a.seg], ctx.angle[a.seg] = r, a.angle end
	end
	for i, c in ipairs(conns) do
		local x = i - 1
		ctx.cls[x] = given[i] or derived[i]
		ctx.used[c.segment0], ctx.used[c.segment1] = true, true
		local s = c.segment0
		if ctx.ap[s] == nil then ctx.ap[s] = {} end
		table.insert(ctx.ap[s], x)
		local key = tostring(s) .. ":" .. tostring(c.lane0)
		ctx.laneKey[x] = key
		if ctx.laneConns[key] == nil then
			ctx.laneConns[key] = {}
			ctx.laneOrder[#ctx.laneOrder + 1] = key
			ctx.laneSeg[key] = s
			if ctx.lanesOf[s] == nil then ctx.lanesOf[s] = {} end
			table.insert(ctx.lanesOf[s], key)
			-- a bus-only entry lane (step 2b): its connections are kept as read, they go with their approach
			if bus ~= nil and type(bus[s]) == "table" and bus[s][c.lane0] == true then
				ctx.busLane[key] = true
				if ctx.apBus[s] == nil then ctx.apBus[s] = {} end
				table.insert(ctx.apBus[s], key)
				ctx.anyBus = true
			end
		end
		table.insert(ctx.laneConns[key], x)
		if ctx.busLane[key] then ctx.busConn[x] = true end
	end
	-- lanes carrying a kerb turn (car lanes only), and lanes of kerb turns only (step 4b)
	for _, key in ipairs(ctx.laneOrder) do
		local any, all = false, true
		for _, x in ipairs(ctx.laneConns[key]) do
			if ctx.cls[x] == "kerb" then any = true else all = false end
		end
		ctx.laneKerb[key] = any and not ctx.busLane[key]
		ctx.laneAllKerb[key] = all
	end
	-- fan plans: the approach of every connection (conflicts within one are accepted, fits)
	if o.fan then
		ctx.fanSeg = {}
		for i, c in ipairs(conns) do ctx.fanSeg[i - 1] = c.segment0 end
	end
	-- approaches in arm order (segments without an arm last, by id)
	local list = {}
	for s in pairs(ctx.ap) do list[#list + 1] = s end
	table.sort(list, function(p, q)
		local rp, rq = ctx.rank[p] or math.huge, ctx.rank[q] or math.huge
		if rp ~= rq then return rp < rq end
		return tostring(p) < tostring(q)
	end)
	ctx.apOrder = list
	return ctx
end

local function demandOf(ctx, key)
	local d = ctx.info.laneDemand and ctx.info.laneDemand[key]
	if d == nil then d = ctx.o.laneDemand and ctx.o.laneDemand[key] end
	if type(d) ~= "number" or d < 0 then d = 1 end
	return d
end

local function lanesCount(ctx, s) return #(ctx.lanesOf[s] or {}) end

---------------------------------------------------------------------------
-- Phase building

--- Whether the conflict of kind `kind` between connections x and j is one between a bus-lane
-- connection and another connection of its own approach (step 2b: accepted). busConn: { [conn] = true }.
local function busOwn(M, busConn, x, j, kind)
	return busConn ~= nil and kind ~= Phases.PED and (busConn[x] or busConn[j]) == true
		and M.seg0[x] ~= nil and M.seg0[x] == M.seg0[j]
end

--- Whether entry x conflicts with nothing in green. pedYield: crosswalk conflicts ("ped") allowed.
-- fanSeg (fan plans only): { [conn] = approach segment }; a conflict between two connections of one
-- approach is accepted (the fan's lanes cross by design), never one with a crosswalk. busConn
-- (optional): a bus-lane connection's conflicts with its own approach are accepted (step 2b).
local function fits(M, green, x, pedYield, fanSeg, busConn, axisSet)
	for j, kind in pairs(M.kinds[x] or {}) do
		if green[j] and not (pedYield and kind == Phases.PED)
			and not (fanSeg ~= nil and kind ~= Phases.PED and fanSeg[x] ~= nil and fanSeg[x] == fanSeg[j])
			and not busOwn(M, busConn, x, j, kind)
			and not PP.axisAccepts(M, axisSet, x, j, kind) then
			return false
		end
	end
	return true
end

--- Whether the conflict of kind `kind` between entries x and j lies within one road of an axis phase:
-- both are connections (no crosswalk) whose approaches (M.seg0) are in axisSet ({ [seg] = true }: the
-- phase's road, its one or two approaches). Axis plans only (the pattern "axis"; PP.validatePlan with
-- opts.axis and plan.axis).
function PP.axisAccepts(M, axisSet, x, j, kind)
	if axisSet == nil or kind == Phases.PED or x >= M.n or j >= M.n then return false end
	local a, b = M.seg0[x], M.seg0[j]
	return a ~= nil and b ~= nil and axisSet[a] == true and axisSet[b] == true
end

local function fitsIn(M, ctx, green, x, axisSet) return fits(M, green, x, ctx.o.pedYield, ctx.fanSeg, ctx.busConn, axisSet) end

--- Step 4b: whether kerb turn x may join `green`: every conflict with a green entry is a merge
-- (pedYield: crosswalk conflicts allowed, as fits; busConn: as fits).
local function fitsMerging(M, green, x, pedYield, busConn)
	for j, kind in pairs(M.kinds[x] or {}) do
		if green[j] and kind ~= Phases.MERGE and not (pedYield and kind == Phases.PED)
			and not busOwn(M, busConn, x, j, kind) then return false end
	end
	return true
end

local function newPhase(tag) return { green = {}, seeds = {}, tag = tag } end

local function addGreen(ph, x, seed)
	ph.green[x] = true
	if seed then ph.seeds[#ph.seeds + 1] = x end
end

--- Adds every connection of entry lane `key` to phase ph, each fitting with the ones before it
-- (pred(m), default fitsIn), or none (all-or-nothing: whole lanes). seed: they count as seeds.
-- Returns whether the lane joined.
local function joinLane(M, ctx, ph, key, seed, pred)
	local added = {}
	for _, m in ipairs(ctx.laneConns[key]) do
		if not ph.green[m] then
			local okM
			if pred ~= nil then okM = pred(m) else okM = fitsIn(M, ctx, ph.green, m, ph.axis) end
			if not okM then
				for _, a in ipairs(added) do ph.green[a] = nil end
				if seed then
					for _ = 1, #added do table.remove(ph.seeds) end
				end
				return false
			end
			addGreen(ph, m, seed)
			added[#added + 1] = m
		end
	end
	return true
end

local function laneGreen(ctx, ph, key) return ph.green[ctx.laneConns[key][1]] == true end

--- Whether a bus lane of approach s is green in ph.
local function busGreen(ctx, ph, s)
	for _, key in ipairs(ctx.apBus[s] or {}) do
		if laneGreen(ctx, ph, key) then return true end
	end
	return false
end

--- Step 2b: every bus lane of approach s not green in ph tries to join it (whole).
local function joinBus(M, ctx, ph, s)
	for _, key in ipairs(ctx.apBus[s] or {}) do
		if not laneGreen(ctx, ph, key) then joinLane(M, ctx, ph, key, false) end
	end
end

--- Step 3 for one phase: every lane not green in ph joins where it fits whole; a car lane of an
-- approach with a bus lane after that bus lane tried to join, a car lane with a kerb turn there only
-- where a bus lane of its approach is green (step 2b).
local function fillLanes(M, ctx, ph)
	for _, key in ipairs(ctx.laneOrder) do
		if not laneGreen(ctx, ph, key) then
			local s = ctx.laneSeg[key]
			if ctx.apBus[s] ~= nil and not ctx.busLane[key] then
				joinBus(M, ctx, ph, s)
				if not ctx.laneKerb[key] or busGreen(ctx, ph, s) then joinLane(M, ctx, ph, key, false) end
			else
				joinLane(M, ctx, ph, key, false)
			end
		end
	end
end

--- Phases from seed lists (steps 2-4). seedPhases = { {tag, seeds = {0-based conns}} } (axis plans also
-- axis / axisList (the phase's road), w / base (its weight and green base), ped (a pedestrian phase follows)).
-- axisMode (the pattern "axis"): every lane must find a seed phase (else nil "axis_extra"), crosswalks only
-- in the pedestrian phases added after each road (see the header "Axis plan"). Returns phases or nil, reason.
local function realise(M, ctx, seedPhases, axisMode)
	local o, n = ctx.o, M.n
	local phases = {}
	-- step 2: seeds as whole lanes
	for _, sp in ipairs(seedPhases) do
		local ph = newPhase(sp.tag)
		ph.axis, ph.axisList, ph.w, ph.base, ph.ped, ph.lanes = sp.axis, sp.axisList, sp.w, sp.base, sp.ped, sp.lanes
		for _, x in ipairs(sp.seeds) do
			-- a seed lane that does not fit is placed below, whole (first phase it fits, else a new one)
			if not ph.green[x] then joinLane(M, ctx, ph, ctx.laneKey[x], true) end
		end
		if #ph.seeds > 0 then phases[#phases + 1] = ph end
	end
	-- the seed phases count too
	if #phases > o.maxPhases then return nil, "too_many_phases" end
	-- step 2b: bus lanes with their approach's car lanes
	if ctx.anyBus then
		for _, ph in ipairs(phases) do
			for _, s in ipairs(ctx.apOrder) do
				if ctx.apBus[s] ~= nil then
					local car = false
					for _, x in ipairs(ctx.ap[s]) do
						if ph.green[x] and not ctx.busConn[x] then car = true break end
					end
					if car then joinBus(M, ctx, ph, s) end
				end
			end
		end
	end
	-- lanes green nowhere: the first phase they fit (whole), else a new one
	for _, key in ipairs(ctx.laneOrder) do
		local any = false
		for _, ph in ipairs(phases) do
			if laneGreen(ctx, ph, key) then any = true break end
		end
		if not any then
			local home = nil
			for _, ph in ipairs(phases) do
				if joinLane(M, ctx, ph, key, true) then home = ph break end
			end
			if home == nil then
				-- an axis plan has no room for an extra phase (no pedestrian clearance after it)
				if axisMode then return nil, "axis_extra" end
				if #phases >= o.maxPhases then return nil, "too_many_phases" end
				home = newPhase("extra")
				phases[#phases + 1] = home
				-- connections of one entry lane never conflict (sl_phases: same entry port)
				if not joinLane(M, ctx, home, key, true) then return nil, "lane_conflict" end
			end
		end
	end
	-- step 3: maximal phases, whole lanes
	for _, ph in ipairs(phases) do fillLanes(M, ctx, ph) end
	-- crosswalks (axis plans: only in their pedestrian phases, added below)
	local walk = nil
	for k = 1, axisMode and 0 or M.nCross do
		local x = n + k - 1
		local any = false
		for _, ph in ipairs(phases) do
			if fitsIn(M, ctx, ph.green, x) then
				addGreen(ph, x, false)
				any = true
			end
		end
		if not any then
			-- take a phase from connections green elsewhere too
			local best, bestCost, bestList = nil, nil, nil
			for p, ph in ipairs(phases) do
				local list = {}
				for j in pairs(M.kinds[x] or {}) do
					if ph.green[j] then list[#list + 1] = j end
				end
				table.sort(list)
				local okAll, straights = true, 0
				local inList = {}
				for _, j in ipairs(list) do inList[j] = true end
				for _, j in ipairs(list) do
					if j >= n then okAll = false break end
					-- never leave part of a lane green: a red movement at its head blocks the rest
					for _, mate in ipairs(ctx.laneConns[ctx.laneKey[j]]) do
						if ph.green[mate] and not inList[mate] then okAll = false end
					end
					if not okAll then break end
					local elsewhere = false
					for q, other in ipairs(phases) do
						if q ~= p and other.green[j] then elsewhere = true break end
					end
					if not elsewhere then okAll = false break end
					if ctx.cls[j] == "straight" then straights = straights + 1 end
				end
				if okAll and #list > 0 then
					local cost = straights * 1000 + #list
					if bestCost == nil or cost < bestCost then best, bestCost, bestList = ph, cost, list end
				end
			end
			if best ~= nil then
				for _, j in ipairs(bestList) do
					best.green[j] = nil
					for s = #best.seeds, 1, -1 do
						if best.seeds[s] == j then table.remove(best.seeds, s) end
					end
				end
				addGreen(best, x, false)
			else
				if o.unknownCrosswalk == "refuse" then return nil, "crosswalk_unplaced" end
				if walk == nil then
					if #phases >= o.maxPhases then return nil, "too_many_phases" end
					walk = newPhase("walk")
					phases[#phases + 1] = walk
				end
				addGreen(walk, x, false)
			end
		end
	end
	-- maximal again (the pedestrian phase; nothing else changed): whole lanes, then crosswalks
	if walk ~= nil then
		fillLanes(M, ctx, walk)
		for x = M.n, M.size - 1 do
			if not walk.green[x] and fitsIn(M, ctx, walk.green, x) then addGreen(walk, x, false) end
		end
	end
	-- step 4b: lanes of kerb turns only also where they only merge (in phase order, then lane order);
	-- a car one beside a bus lane only where a bus lane of its approach is green (step 3)
	if o.kerbMerge ~= false and ctx.fanSeg == nil then
		for _, ph in ipairs(phases) do
			local function merging(m) return fitsMerging(M, ph.green, m, o.pedYield, ctx.busConn) end
			for _, key in ipairs(ctx.laneOrder) do
				local s = ctx.laneSeg[key]
				if ctx.laneAllKerb[key] and not laneGreen(ctx, ph, key)
					and (ctx.busLane[key] or ctx.apBus[s] == nil or busGreen(ctx, ph, s)) then
					joinLane(M, ctx, ph, key, false, merging)
				end
			end
		end
	end
	-- axis plans: a pedestrian phase after each road (every vehicle red, every crosswalk green, opts.pedPhase s);
	-- without crosswalks an all-red clearance of the vehicle clearance instead. Both may skip once their
	-- clearance (opts.pedClearance, at most the phase) has run (skipMin: skipFlags, floors)
	if axisMode then
		local out = {}
		local pedSec = math.min(PP.MAX_DURATION, math.max(PP.MIN_DURATION, math.floor((tonumber(o.pedPhase) or 6) + 0.5)))
		local clear = math.floor((tonumber(o.pedClearance) or 3) * 2 + 0.5) / 2
		clear = math.min(PP.MAX_MIN_DURATION, math.max(0.5, clear))
		for _, ph in ipairs(phases) do
			out[#out + 1] = ph
			if ph.ped then
				local w = newPhase(M.nCross > 0 and "ped" or "all_red")
				for k = 1, M.nCross do addGreen(w, n + k - 1, false) end
				w.fixed = M.nCross > 0 and pedSec or PP.vehClear(ctx)
				w.skipMin = math.min(clear, w.fixed)
				out[#out + 1] = w
			end
		end
		if #out > PP.MAX_STATES then return nil, "too_many_phases" end
		phases = out
	end
	return phases
end

---------------------------------------------------------------------------
-- Patterns: seed phases

local function axesOf(ctx)
	local arms = ctx.arms
	if #arms ~= 4 then return nil end
	local function opposite(a, b)
		local d = Phases.norm(b.angle - a.angle)
		return math.abs(d - 180) <= PP.AXIS_TOL
	end
	if not (opposite(arms[1], arms[3]) and opposite(arms[2], arms[4])) then return nil end
	-- each pair and the two axes ordered by segment id (ties), so a rotation changes nothing
	local function less(a, b)
		if type(a) == "number" and type(b) == "number" then return a < b end
		return tostring(a) < tostring(b)
	end
	local ax = { { arms[1].seg, arms[3].seg }, { arms[2].seg, arms[4].seg } }
	for _, pr in ipairs(ax) do
		if less(pr[2], pr[1]) then pr[1], pr[2] = pr[2], pr[1] end
	end
	local function lanes(a) return lanesCount(ctx, a[1]) + lanesCount(ctx, a[2]) end
	local l1, l2 = lanes(ax[1]), lanes(ax[2])
	if l2 > l1 or (l2 == l1 and less(ax[2][1], ax[1][1])) then ax[1], ax[2] = ax[2], ax[1] end
	return ax
end

local function tShape(ctx)
	local arms = ctx.arms
	if #arms ~= 3 then return nil end
	local pairsList = { { 1, 2 }, { 2, 3 }, { 1, 3 } }
	local withStraight = {}
	for _, pr in ipairs(pairsList) do
		local s1, s2 = arms[pr[1]].seg, arms[pr[2]].seg
		local found = false
		for x = 0, ctx.n - 1 do
			local cn = ctx.conns[x + 1]
			if ctx.cls[x] == "straight" and ((cn.segment0 == s1 and cn.segment1 == s2) or (cn.segment0 == s2 and cn.segment1 == s1)) then
				found = true
			end
		end
		if found then withStraight[#withStraight + 1] = pr end
	end
	local main = nil
	if #withStraight == 1 then main = withStraight[1]
	else
		local bestD = nil
		for _, pr in ipairs(pairsList) do
			local d = math.abs(Phases.norm(arms[pr[2]].angle - arms[pr[1]].angle) - 180)
			if d <= PP.AXIS_TOL and (bestD == nil or d < bestD) then main, bestD = pr, d end
		end
	end
	if main == nil then return nil end
	local side = 6 - main[1] - main[2]
	return { arms[main[1]].seg, arms[main[2]].seg }, arms[side].seg
end

--- Fan seeds (opts.fan): one phase per approach, every connection of it, approaches in arm order.
local function fanPattern(ctx)
	local seeds = {}
	for _, s in ipairs(ctx.apOrder) do seeds[#seeds + 1] = { tag = "approach", seeds = ctx.ap[s] } end
	local kind = "fan"
	if axesOf(ctx) ~= nil then kind = "x4_fan" elseif tShape(ctx) ~= nil then kind = "t3_fan" end
	return { kind = kind, seeds = seeds, why = string.format("fan %d approaches %d arms", #ctx.apOrder, #ctx.arms) }
end

--- Demand of approach s: the sum over its entry lanes (bus-only and tram-only lanes included) of their
-- demand (1 per lane, or laneDemand).
local function approachDemand(ctx, s)
	local d = 0
	for _, key in ipairs(ctx.lanesOf[s] or {}) do d = d + demandOf(ctx, key) end
	return d
end

--- Axis pattern, the seed phases of one road (approach segments `road`, one or two): an optional head
-- start (one approach alone; only with measured demand, see the header) and the road's phase (every
-- connection of its approaches), appended to out. Returns the head start's approach or nil; nil, false
-- when no approach of the road is present.
local function roadPhases(ctx, road, out)
	local present = {}
	for _, s in ipairs(road) do
		if ctx.ap[s] ~= nil then present[#present + 1] = s end
	end
	if #present == 0 then return nil, false end
	local d, w, lanes = {}, 0, 1
	for _, s in ipairs(present) do
		d[s] = approachDemand(ctx, s)
		if d[s] > w then w = d[s] end
		if lanesCount(ctx, s) > lanes then lanes = lanesCount(ctx, s) end
	end
	local set = {}
	for _, s in ipairs(present) do set[s] = true end
	local head = nil
	local ratio = ctx.o.headStartRatio
	local measured = type(ctx.info.laneDemand) == "table" or type(ctx.o.laneDemand) == "table"
	if #present == 2 and measured and type(ratio) == "number" and ratio > 1 then
		local dom, opp = present[1], present[2]
		if d[opp] > d[dom] then dom, opp = opp, dom end
		if d[opp] > 0 and d[dom] >= ratio * d[opp] - 1e-9 then
			head = dom
			-- the head start serves the dominant's excess (green base 0: greenPerLane x excess, at least
			-- minGreen); the road's phase then serves both approaches for the opposite's demand
			out[#out + 1] = { tag = "head", seeds = ctx.ap[dom], w = d[dom] - d[opp], base = 0,
				axis = { [dom] = true }, axisList = { dom } }
			w = d[opp]
		end
	end
	local seeds = {}
	for _, s in ipairs(present) do
		for _, x in ipairs(ctx.ap[s]) do seeds[#seeds + 1] = x end
	end
	out[#out + 1] = { tag = "axis", seeds = seeds, w = w, axis = set, axisList = present, ped = true, lanes = lanes }
	return head, true
end

--- The axis candidate (opts.pattern "axis", x4 and t3 only; PHASES_PLAN.md "Axis plan"): per road both
-- directions whole, then a pedestrian phase. x4: the road with more demand first (lane counts without
-- laneDemand; ties: sl_phaseplan's axis order, more lanes, then the lower segment id); t3: the main road,
-- then the side road. nil for other shapes.
local function axisPattern(ctx)
	local roads, kind = nil, nil
	local axes = axesOf(ctx)
	if axes ~= nil then
		local function dem(ax)
			local t = 0
			for _, s in ipairs(ax) do
				if ctx.ap[s] ~= nil then t = t + approachDemand(ctx, s) end
			end
			return t
		end
		if dem(axes[2]) > dem(axes[1]) + 1e-9 then axes = { axes[2], axes[1] } end
		roads, kind = axes, "x4_axis"
	else
		local main, side = tShape(ctx)
		if main == nil then return nil end
		roads, kind = { main, { side } }, "t3_axis"
	end
	local seeds, parts = {}, {}
	for _, road in ipairs(roads) do
		local head, any = roadPhases(ctx, road, seeds)
		local names = {}
		for _, s in ipairs(road) do names[#names + 1] = tostring(s) end
		if any then parts[#parts + 1] = table.concat(names, "-") .. (head ~= nil and (" head " .. tostring(head)) or "") end
	end
	if #seeds == 0 then return nil end
	return { kind = kind, seeds = seeds, axisPlan = true, why = "axis " .. table.concat(parts, ", ") }
end

---------------------------------------------------------------------------
-- Timing

--- Width (m) of the road of arm segment seg: info.crossLen, else roadLanes x laneWidth; nil unknown.
local function roadWidth(ctx, seg)
	local o, info = ctx.o, ctx.info
	if info.crossLen and type(info.crossLen[seg]) == "number" then return info.crossLen[seg] end
	if info.roadLanes and type(info.roadLanes[seg]) == "number" then return info.roadLanes[seg] * o.laneWidth end
	return nil
end

--- The widest arm's road width (m), nil when none is known.
local function widestArm(ctx)
	local len = nil
	for _, a in ipairs(ctx.arms) do
		local l = roadWidth(ctx, a.seg)
		if l ~= nil and (len == nil or l > len) then len = l end
	end
	return len
end

--- Crossing length (m) of crosswalk k: the crossed road's width; unmapped: the widest arm; else
-- defaultCrossLen.
local function crossLen(M, ctx, k)
	local seg = M.cwSeg[k]
	local len = nil
	if seg then len = roadWidth(ctx, seg) else len = widestArm(ctx) end
	if len == nil then len = ctx.o.defaultCrossLen end
	return len
end

--- Crossing time (s) of crosswalk k: crossed road width / pedSpeed + pedClear.
local function pedMin(M, ctx, k)
	return crossLen(M, ctx, k) / ctx.o.pedSpeed + ctx.o.pedClear
end
PP.pedMin = pedMin

--- All-red clearance (whole s) after a vehicle phase and after a pedestrian-only phase (0: none).
-- opts.allRed a number: that after every phase. "auto": vehicles clamp(round(junction width /
-- clearSpeed), clearMin, clearMax), the junction width = the widest arm's road (clearDefault when
-- unknown); after the pedestrian phase max(that, pedClear): the pedestrian floor (crossing length /
-- pedSpeed + pedClear) split as walk green (crossing length / pedSpeed, the floors) + this clearance.
-- (The game runs 3 s walk + 9 s all-red; a long all-red runs every cycle as it never skips, a long
-- walk green only when pedestrians wait.)
local function clearances(M, ctx)
	local o = ctx.o
	if type(o.allRed) == "number" then
		local v = 0
		if o.allRed > 0 then v = math.min(PP.MAX_DURATION, math.max(PP.MIN_DURATION, math.floor(o.allRed + 0.5))) end
		return v, v
	end
	if o.allRed ~= "auto" then return 0, 0 end
	local veh = PP.vehClear(ctx)
	return veh, math.max(veh, math.min(PP.MAX_DURATION, math.ceil(o.pedClear - 1e-9)))
end
PP.clearances = clearances

--- The "auto" vehicle clearance (whole s): clamp(round(junction width / clearSpeed), clearMin, clearMax),
-- clearDefault when no width is known (also an axis plan's clearance without crosswalks).
function PP.vehClear(ctx)
	local o = ctx.o
	local width = widestArm(ctx)
	local veh = o.clearDefault
	if width ~= nil then veh = math.floor(width / o.clearSpeed + 0.5) end
	return math.min(o.clearMax, math.max(o.clearMin, veh))
end

--- Phases where entry x is green.
local function greenIn(phases, x)
	local out = {}
	for p, ph in ipairs(phases) do
		if ph.green[x] then out[#out + 1] = p end
	end
	return out
end

--- canSkip per phase (opts.skip "turns"): every entry green in it that is no turn connection (a
-- straight, a kerb turn, a crosswalk) is green in a phase that never skips as well. Phases with such
-- an entry green only there never skip; then, in phase order, a phase whose non-turn entry has no
-- fixed phase yet becomes fixed. At least one phase is fixed.
local function skipFlags(M, ctx, phases)
	local flags = {}
	if ctx.o.skip == "all" then
		-- the game's way: every phase is demand-actuated; the all-red clearance never skips (a fully
		-- locked phase has no lanes that would hold it: it could end at once and lose the clearance)
		-- (an axis plan's pedestrian / clearance phase skips too, after its clearance: ph.skipMin)
		for p, ph in ipairs(phases) do flags[p] = ph.fixed == nil or ph.skipMin ~= nil end
		return flags
	end
	local function needsFixed(x) return x >= M.n or not isTurnCls(ctx.cls[x]) end
	for p, ph in ipairs(phases) do
		local can = ctx.o.skip == "turns" and ph.fixed == nil and ph.tag ~= "walk"
		if can then
			for _, x in ipairs(sortedKeys(ph.green)) do
				if needsFixed(x) and #greenIn(phases, x) == 1 then can = false break end
			end
		end
		flags[p] = can
	end
	for _ = 1, #phases do
		local changed = false
		for p, ph in ipairs(phases) do
			if flags[p] then
				for _, x in ipairs(sortedKeys(ph.green)) do
					if needsFixed(x) then
						local fixed = false
						for _, q in ipairs(greenIn(phases, x)) do
							if not flags[q] then fixed = true break end
						end
						if not fixed then
							flags[p] = false
							changed = true
							break
						end
					end
				end
			end
		end
		if not changed then break end
	end
	local anyFixed = false
	for p = 1, #phases do
		if not flags[p] then anyFixed = true end
	end
	if not anyFixed and #phases > 0 then flags[1] = false end
	return flags
end

--- Duration floors f[p] and minDuration floors mf[p] (pedestrians, minGreen); may clear skip flags.
local function floors(M, ctx, phases, skip)
	local o = ctx.o
	local allSkip = o.skip == "all"
	local np = #phases
	local f, mf = {}, {}
	for _ = 1, np + 1 do
		local changed = false
		for p, ph in ipairs(phases) do
			if ph.fixed ~= nil then
				f[p], mf[p] = ph.fixed, 0
				-- an axis plan's skippable clearance: minDuration = the clearance (realise: at most the phase)
				if skip[p] and ph.skipMin ~= nil then mf[p] = math.min(ph.skipMin, ph.fixed) end
			else
				-- a pedestrian-only phase: the game's 3 s walk start (its clearance follows as all-red)
				local onlyWalk = next(ph.green) ~= nil
				for x in pairs(ph.green) do
					if x < M.n then onlyWalk = false break end
				end
				f[p] = onlyWalk and o.pedClear or o.minGreen
				mf[p] = skip[p] and o.skipMinGreen or 0
				if mf[p] > f[p] then f[p] = mf[p] end
				-- an axis plan's road phase: at least the game's default green for its lanes (PP.gameGreen)
				if ph.lanes ~= nil and o.gameGreenFloor ~= false and f[p] < PP.gameGreen(ph.lanes) then
					f[p] = PP.gameGreen(ph.lanes)
				end
			end
		end
		for k = 1, M.nCross do
			local x = M.n + k - 1
			local need0 = pedMin(M, ctx, k)
			local on = {}
			local count = 0
			for p, ph in ipairs(phases) do
				on[p] = ph.green[x] == true
				if on[p] then count = count + 1 end
			end
			if count > 0 and count < np then
				-- runs of consecutive green phases (cyclic), each walked from its last phase back
				for start = 1, np do
					local prev = (start - 2) % np + 1
					if on[start] and not on[prev] then
						local run = {}
						local p = start
						while on[p] and #run < np do
							run[#run + 1] = p
							p = p % np + 1
						end
						-- the all-red right after the run clears the crossing too (fully locked, fixed)
						local tail = 0
						local after = phases[run[#run] % np + 1]
						if after ~= nil and after.tag == "all_red" and not on[run[#run] % np + 1] then tail = after.fixed or 0 end
						for r = #run, 1, -1 do
							local q = run[r]
							local need = need0 - tail
							if skip[q] and allSkip then
								-- skip "all" (the game's way): the crossing time goes into the green only;
								-- minDuration stays the game's 1.5 s (inferred: a crosswalk with pedestrians on
								-- it is a lane that is not empty, so the phase does not end early under them)
								-- (a fixed phase keeps its length: the axis plan's skippable pedestrian phase)
								if need > f[q] and phases[q].fixed == nil then f[q] = need end
							elseif skip[q] then
								if need > mf[q] then
									if need > PP.MAX_MIN_DURATION then
										skip[q] = false
										changed = true
									else
										mf[q] = need
										if f[q] < need then f[q] = need end
									end
								end
							elseif need > f[q] and phases[q].fixed == nil then
								-- (a fixed phase keeps its length: the axis plan's pedestrian phase, opts.pedPhase)
								f[q] = need
							end
							if not skip[q] or allSkip then tail = tail + f[q] end
						end
					end
				end
			end
			if changed then break end
		end
		if not changed then break end
	end
	return f, mf
end

--- Phase weights: per approach the demand of the (lane, class) units first seeded in the phase,
-- the largest approach per phase.
local function weights(M, ctx, phases)
	local home = {}
	for p, ph in ipairs(phases) do
		for _, x in ipairs(ph.seeds) do
			local u = ctx.laneKey[x] .. "/" .. tostring(ctx.cls[x])
			if home[u] == nil then home[u] = p end
		end
	end
	local per = {}
	for p = 1, #phases do per[p] = {} end
	-- sorted keys: the float sums below must not depend on pairs() order
	for _, key in ipairs(sortedKeys(ctx.laneConns)) do
		local list = ctx.laneConns[key]
		local classes = {}
		for _, x in ipairs(list) do classes[tostring(ctx.cls[x])] = x end
		local names = sortedKeys(classes)
		local d = demandOf(ctx, key) / #names
		for _, cname in ipairs(names) do
			local x = classes[cname]
			local s = ctx.conns[x + 1].segment0
			local p = home[key .. "/" .. cname]
			if p ~= nil then per[p][s] = (per[p][s] or 0) + d
			else
				-- no seed left (a crosswalk took its phase): shared by the phases it is green in
				local list = greenIn(phases, x)
				for _, q in ipairs(list) do per[q][s] = (per[q][s] or 0) + d / #list end
			end
		end
	end
	local w = {}
	for p = 1, #phases do
		local m = 0
		for _, v in pairs(per[p]) do
			if v > m then m = v end
		end
		w[p] = m
	end
	return w
end

--- Durations from weights and floors: the green target g[p] = greenBase + greenPerLane x w[p] (0 for
-- w = 0), d[p] = max(f[p], s * g[p]) with one factor s for every phase so that the cycle lies in
-- [cycleMin, cycleMax] (s = 1 when the targets already do); whole seconds within 1..60. All-red
-- phases keep their fixed length. Returns d, cycle, warnings.
local function durations(phases, w, f, o)
	local g = {}
	local fixed, raw, sumF = 0, 0, 0
	for p, ph in ipairs(phases) do
		-- (an axis plan's head start has its own green base: ph.base = 0)
		g[p] = (w[p] > 0) and ((ph.base or o.greenBase) + o.greenPerLane * w[p]) or 0
		if ph.fixed ~= nil then fixed = fixed + f[p]
		else
			raw = raw + math.max(f[p], g[p])
			sumF = sumF + f[p]
		end
	end
	local warnings = {}
	local target = math.min(math.max(raw + fixed, o.cycleMin), o.cycleMax) - fixed
	if target < sumF then
		target = sumF
		if sumF + fixed > o.cycleMax then warnings[#warnings + 1] = "cycle_over_max" end
	end
	local function total(s)
		local t = 0
		for p, ph in ipairs(phases) do
			if ph.fixed == nil then t = t + math.max(f[p], s * g[p]) end
		end
		return t
	end
	local d = {}
	local hi = 0
	for p, ph in ipairs(phases) do
		if ph.fixed == nil and g[p] > 0 then hi = math.max(hi, target / g[p]) end
	end
	local s = 0
	if hi > 0 then
		local lo = 0
		for _ = 1, 60 do
			local mid = (lo + hi) / 2
			if total(mid) < target then lo = mid else hi = mid end
		end
		s = hi
	end
	local cycle = 0
	for p, ph in ipairs(phases) do
		local v
		if ph.fixed ~= nil then v = f[p]
		else v = math.max(f[p], s * g[p]) end
		local r = math.floor(v + 0.5)
		local floorUp = math.ceil(f[p] - 1e-9)
		if r < floorUp then r = floorUp end
		if r > PP.MAX_DURATION then
			r = PP.MAX_DURATION
			warnings[#warnings + 1] = "phase_over_60"
		end
		if r < PP.MIN_DURATION then r = PP.MIN_DURATION end
		d[p] = r
		cycle = cycle + r
	end
	return d, cycle, warnings
end

---------------------------------------------------------------------------
-- Plan

local function finish(M, ctx, phases, cand)
	local o = ctx.o
	-- axis plans have no all-red phases: their pedestrian phases clear the junction between the roads
	local veh, ped = 0, 0
	if not cand.axisPlan then veh, ped = clearances(M, ctx) end
	if veh > 0 or ped > 0 then
		local withRed = {}
		for _, ph in ipairs(phases) do
			withRed[#withRed + 1] = ph
			local v = ph.tag == "walk" and ped or veh
			if v > 0 then
				local r = newPhase("all_red")
				r.fixed = v
				withRed[#withRed + 1] = r
			end
		end
		phases = withRed
	end
	local skip = skipFlags(M, ctx, phases)
	local f, mf = floors(M, ctx, phases, skip)
	local w = weights(M, ctx, phases)
	-- axis plans: the weights the pattern set (per road the larger approach's demand; a head start the excess)
	for p, ph in ipairs(phases) do
		if ph.w ~= nil then w[p] = ph.w end
	end
	local d, cycle, warnings = durations(phases, w, f, o)
	local states = {}
	for p, ph in ipairs(phases) do
		local locked, green = {}, {}
		for x = 0, M.size - 1 do
			if ph.green[x] then green[#green + 1] = x else locked[#locked + 1] = x end
		end
		local minD = 0
		if skip[p] then
			minD = math.ceil(mf[p] * 2 - 1e-9) / 2
			if minD > d[p] then minD = d[p] end
			if minD > PP.MAX_MIN_DURATION then minD = PP.MAX_MIN_DURATION end
		end
		states[p] = { locked = locked, green = green, duration = d[p], minDuration = minD, canSkip = skip[p] == true,
			tag = ph.tag, weight = w[p] }
	end
	-- the kerb turns step 4b may let merge (PP.validatePlan accepts their merges)
	local kerb = nil
	if o.kerbMerge ~= false and not o.fan then
		for x = 0, M.n - 1 do
			if ctx.cls[x] == "kerb" then
				kerb = kerb or {}
				kerb[x] = true
			end
		end
	end
	-- the bus-lane connections (step 2b: PP.validatePlan accepts their conflicts with their own approach)
	local bus = nil
	for x in pairs(ctx.busConn) do
		bus = bus or {}
		bus[x] = true
	end
	-- axis plans: per state the road whose conflicts within it are accepted (PP.validatePlan with opts.axis)
	local axis = nil
	if cand.axisPlan then
		axis = {}
		for p, ph in ipairs(phases) do
			if ph.axisList ~= nil then
				local list = {}
				for i, s in ipairs(ph.axisList) do list[i] = s end
				axis[p] = list
			end
		end
	end
	return { states = states, kind = cand.kind, why = cand.why, cycle = cycle, warnings = warnings,
		floors = f, phases = phases, fan = o.fan == true or nil, kerb = kerb, bus = bus, axis = axis,
		pattern = cand.axisPlan and "axis" or "fan" }
end

--- Plans the phases of one lit node. M: sl_phases P.build map; info = { conns (the list M was built
-- from), arms = {seg, angle}, cls (1-based per connection; else M.cls; else from the angles), side
-- ("right" | "left", for classes from angles), roadLanes / crossLen per arm segment, laneDemand
-- ["seg:lane"], bus (bus-only lane ends: { [seg] = { [lane] = true } }, step 2b) }; opts: PP.DEFAULTS
-- overrides (fan = true: the fan plan, else the axis plan; see the header). Returns plan = { states = {
-- {locked (0-based), green, duration, minDuration, canSkip, tag, weight} }, kind, why, cycle, warnings, fan
-- (true for a fan plan), kerb (step 4b's kerb turns), bus (bus-lane connections, 0-based set), axis (axis
-- plans: { [state] = { approach segments of its road } }, for PP.validatePlan opts.axis), pattern ("axis" |
-- "fan") } or nil, reason ("no_axis_shape", "axis_extra", "invalid_<why>", "too_many_phases", ...: the
-- caller keeps the game's phases; see the header "No classic fallback").
function PP.plan(M, info, opts)
	if M == nil then return nil, "no_map" end
	info = info or {}
	local o = options(opts)
	if #(info.conns or {}) ~= M.n then return nil, "conns_mismatch" end
	if M.n == 0 then return nil, "no_conns" end
	local ctx = context(M, info, o)
	local cand
	if o.fan then
		cand = fanPattern(ctx)
	else
		-- the axis plan (x4 and t3); any other shape keeps the game's phases
		cand = axisPattern(ctx)
		if cand == nil then return nil, "no_axis_shape" end
	end
	local phases, why = realise(M, ctx, cand.seeds, cand.axisPlan == true)
	if phases == nil then return nil, why end
	local plan = finish(M, ctx, phases, cand)
	local vo = o
	if plan.axis ~= nil then
		vo = options(o)
		vo.axis = true
	end
	local okV, reason = PP.validatePlan(M, plan, M.n, M.nCross, vo)
	if not okV then return nil, "invalid_" .. tostring(reason) end
	plan.phases, plan.floors = nil, nil
	return plan
end

--- Whether arm segments a and b form one road (an axis plan's pair): different arms, opposite within
-- AXIS_TOL of 180 deg (M.armAngle), or with a straight connection between them (M.cls, M.seg1: a T's
-- main road).
local function roadPair(M, a, b)
	if a == nil or b == nil or a == b then return false end
	local A, B = M.armAngle and M.armAngle[a], M.armAngle and M.armAngle[b]
	if type(A) == "number" and type(B) == "number" and math.abs(Phases.norm(B - A) - 180) <= PP.AXIS_TOL then return true end
	if M.cls == nil or M.seg1 == nil then return false end
	for x = 0, M.n - 1 do
		if M.cls[x + 1] == "straight" and ((M.seg0[x] == a and M.seg1[x] == b) or (M.seg0[x] == b and M.seg1[x] == a)) then
			return true
		end
	end
	return false
end
PP.roadPair = roadPair

--- Checks a plan against the map: states present and bounded, every index an integer in range and
-- not repeated, every connection and crosswalk green in some phase, no conflicting pair green in a
-- phase (opts.pedYield: crosswalk conflicts allowed), durations whole seconds 1..60, minDuration
-- 0..min(duration, 30) in 0.5 s steps, canSkip boolean, at least one phase that never skips (unless
-- opts.skip is "all", the default), a skippable phase with every vehicle connection red (a pedestrian or all-red
-- clearance) at least PP.MIN_CLEAR s minDuration (else "clear_min:<state>"). opts.fan (explicit, fan plans only): a conflict between two
-- connections of the same approach (M.seg0) is accepted; between approaches or with a crosswalk never.
-- A merge with a kerb turn (step 4b: one the plan lists in plan.kerb, or class "kerb" in M.cls) is
-- accepted unless opts.kerbMerge is false or opts.fan; a listed connection whose class M.cls knows
-- must be "kerb" (else "kerb_class:x"). A conflict between a bus-lane connection the plan lists
-- (plan.bus, step 2b) and another connection of its own approach (M.seg0) is accepted; with another
-- approach or a crosswalk never. Whole lanes: in every phase the connections of one entry lane
-- (M.seg0 + M.lane0, road and tram alike) are all green or all red (else "part_lane:<state>:<seg>:<lane>").
-- Axis plans (opts.axis = true, explicit, as opts.fan): a conflict between two connections whose approaches
-- both lie in the state's road (plan.axis[s] = { seg } or { segA, segB }, the pair one road: PP.roadPair;
-- else "axis_road:<state>") is accepted: the two opposite approaches of the road, and within one of them.
-- Never between roads (a connection of another approach), never with a crosswalk. Without the flag, or
-- for a state plan.axis does not list, such a plan fails "conflict:..".
-- Returns true, or false, reason.
function PP.validatePlan(M, plan, nConns, nCross, opts)
	if M == nil or type(plan) ~= "table" or type(plan.states) ~= "table" then return false, "no_plan" end
	local size = (nConns or 0) + (nCross or 0)
	if size ~= M.size or nConns ~= M.n then return false, "size_mismatch" end
	local states = plan.states
	if #states == 0 then return false, "no_states" end
	local fanSeg = (opts and opts.fan == true) and M.seg0 or nil
	if #states > PP.MAX_STATES then return false, "too_many_states" end
	-- step 4b's kerb turns: the plan's list (checked against M.cls), else M.cls itself (a plan read
	-- back from a config has no list)
	local kerb = nil
	if not (opts and (opts.kerbMerge == false or opts.fan == true)) then
		kerb = {}
		if type(plan.kerb) == "table" then
			for x in pairs(plan.kerb) do
				if type(x) ~= "number" or x < 0 or x >= M.n then return false, "kerb_index" end
				local c = M.cls and M.cls[x + 1]
				if c ~= nil and c ~= "kerb" then return false, "kerb_class:" .. x end
				kerb[x] = true
			end
		end
		for i, c in pairs(M.cls or {}) do
			if c == "kerb" and type(i) == "number" and i >= 1 and i <= M.n then kerb[i - 1] = true end
		end
	end
	local bus = nil
	if type(plan.bus) == "table" then
		bus = {}
		for x in pairs(plan.bus) do
			if type(x) ~= "number" or x < 0 or x >= M.n or x ~= math.floor(x) then return false, "bus_index" end
			bus[x] = true
		end
	end
	-- axis plans (opts.axis, explicit): per state the road whose conflicts within it are accepted
	-- (plan.axis[s]: one approach segment, or two that form a road)
	local axisOf = nil
	if opts and opts.axis == true and type(plan.axis) == "table" then
		axisOf = {}
		for s, list in pairs(plan.axis) do
			if type(s) ~= "number" or s ~= math.floor(s) or s < 1 or s > #states or type(list) ~= "table" then
				return false, "axis_index"
			end
			if #list < 1 or #list > 2 or (#list == 2 and not roadPair(M, list[1], list[2])) then
				return false, "axis_road:" .. s
			end
			local set = {}
			for _, seg in ipairs(list) do set[seg] = true end
			axisOf[s] = set
		end
	end
	local everGreen = {}
	local anyFixed = false
	for s, st in ipairs(states) do
		if type(st.locked) ~= "table" then return false, "locked:" .. s end
		local red = {}
		for _, l in ipairs(st.locked) do
			if type(l) ~= "number" or l ~= math.floor(l) or l < 0 or l >= size then return false, "index:" .. s end
			if red[l] then return false, "duplicate:" .. s end
			red[l] = true
		end
		for x = 0, size - 1 do
			if not red[x] then everGreen[x] = true end
		end
		local list = Phases.phaseConflicts(M, st.locked)
		if list == nil then return false, "index:" .. s end
		for _, c in ipairs(list) do
			local intra = fanSeg ~= nil and c[3] ~= Phases.PED and c[1] < M.n and c[2] < M.n
				and fanSeg[c[1]] ~= nil and fanSeg[c[1]] == fanSeg[c[2]]
			local kerbMerge = kerb ~= nil and c[3] == Phases.MERGE and (kerb[c[1]] or kerb[c[2]])
			local busOwnAp = bus ~= nil and c[2] < M.n and busOwn(M, bus, c[1], c[2], c[3])
			local inRoad = axisOf ~= nil and PP.axisAccepts(M, axisOf[s], c[1], c[2], c[3])
			if not (opts and opts.pedYield and c[3] == Phases.PED) and not intra and not kerbMerge and not busOwnAp
				and not inRoad then
				return false, string.format("conflict:%d:%d-%d:%s", s, c[1], c[2], c[3])
			end
		end
		-- whole lanes: one entry lane all green or all red
		if M.lane0 ~= nil then
			local laneOn = {}
			for x = 0, M.n - 1 do
				local key = tostring(M.seg0[x]) .. ":" .. tostring(M.lane0[x])
				local on = not red[x]
				local was = laneOn[key]
				if was == nil then laneOn[key] = on
				elseif was ~= on then return false, string.format("part_lane:%d:%s", s, key) end
			end
		end
		local d = st.duration
		if type(d) ~= "number" or d ~= math.floor(d) or d < PP.MIN_DURATION or d > PP.MAX_DURATION then
			return false, "duration:" .. s
		end
		local m = st.minDuration
		if type(m) ~= "number" or m < 0 or m > d or m > PP.MAX_MIN_DURATION or m * 2 ~= math.floor(m * 2) then
			return false, "min_duration:" .. s
		end
		if type(st.canSkip) ~= "boolean" then return false, "can_skip:" .. s end
		if not st.canSkip then anyFixed = true end
		-- a skippable phase with every vehicle connection red (a pedestrian or all-red clearance) keeps at least
		-- MIN_CLEAR s (its minDuration): with nothing green to hold it, it could end at once and lose the clearance
		-- (the game's own all-reds: 1.5 s)
		if st.canSkip and m < PP.MIN_CLEAR then
			local vehGreen = false
			for x = 0, (nConns or 0) - 1 do
				if not red[x] then vehGreen = true break end
			end
			if not vehGreen then return false, "clear_min:" .. s end
		end
	end
	for x = 0, size - 1 do
		if not everGreen[x] then
			return false, (x < nConns and "never_green:" or "crosswalk_never_green:") .. x
		end
	end
	-- skip "all" (the default, the game's way): every phase may skip, the engine runs a phase while its
	-- lanes have traffic; else at least one phase never skips
	if not anyFixed and options(opts).skip ~= "all" then return false, "all_skip" end
	return true
end

--- The pattern a plan was made with, for the log (PHASES pattern=): "axis" | "fan"; "none" without a plan.
function PP.patternName(plan)
	if type(plan) ~= "table" then return "none" end
	return tostring(plan.pattern or "none")
end

--- Index list as text: runs of 3+ consecutive indices as "a-b" (prefix p on every number).
local function rangesText(list, p)
	local out, i = {}, 1
	while i <= #list do
		local j = i
		while j < #list and list[j + 1] == list[j] + 1 do j = j + 1 end
		if j - i >= 2 then out[#out + 1] = p .. list[i] .. "-" .. p .. list[j]
		else
			for k = i, j do out[#out + 1] = p .. list[k] end
		end
		i = j + 1
	end
	return table.concat(out, ",")
end

--- One-line text of a plan for the log: kind cycle= then per phase duration[/skip<min>] and the green
-- entries (connections as indices, crosswalks as w<k>, runs as a-b). At most maxLen characters
-- (default 190, under Rules.line's 200 cut per field): phases that do not fit become "+N".
function PP.planText(plan, nConns, maxLen)
	if plan == nil then return "none" end
	maxLen = maxLen or 190
	local head = string.format("%s cycle=%s", tostring(plan.kind), tostring(plan.cycle))
	local states = plan.states or {}
	local text = head
	for i, st in ipairs(states) do
		local conns, walks = {}, {}
		for _, x in ipairs(st.green or {}) do
			if nConns and x >= nConns then walks[#walks + 1] = x - nConns + 1 else conns[#conns + 1] = x end
		end
		local g = rangesText(conns, "")
		local w = rangesText(walks, "w")
		if g ~= "" and w ~= "" then g = g .. "," .. w else g = g .. w end
		local skip = st.canSkip and string.format("/skip%g", st.minDuration) or ""
		local part = string.format(" %d:%ds%s[%s]", i, st.duration, skip, g)
		-- an all-red clearance (nothing green): " i:red<d>"
		if g == "" then part = string.format(" %d:red%d%s", i, st.duration, skip) end
		local more = i < #states and #(" +" .. (#states - i + 1)) or 0
		if #text + #part + more > maxLen then return text .. " +" .. (#states - i + 1) end
		text = text .. part
	end
	return text
end

return PP
