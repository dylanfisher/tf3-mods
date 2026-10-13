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
-- under the map M: protected turns only. Every plan passes PP.validatePlan before it is returned
-- (else nil, reason: the caller keeps the game's phases).
--
-- Pipeline (PP.plan):
--   1. Shape and pattern: seed movements per phase (see the patterns below).
--   2. Seeds go into their phase only when they conflict with nothing green there (in seed order);
--      a seed that does not fit, and every connection the pattern did not place (U-turns, unknown
--      classes), goes into the first phase it fits, else into a new phase.
--   3. Maximal phases: every connection is added to every phase where it conflicts with nothing green
--      (in index order).
--   4. Crosswalks: added to every phase where they conflict with nothing. A crosswalk that fits
--      nowhere takes a phase from connections that are green in another phase as well (fewest
--      straights, then fewest connections, then the earliest phase): the parallel crosswalk beats
--      the kerb turn into its road, which keeps its other phases. Still nowhere (an unknown
--      crosswalk entity conflicts with every connection): one pedestrian phase with every vehicle
--      red (opts.unknownCrosswalk "ped_phase", default) or no plan ("refuse").
--   4b. Kerb merges (opts.kerbMerge, default true; not in fan plans): after the crosswalks, every kerb
--      turn (class "kerb") is added to every phase where its only conflicts with green entries are
--      merges (another approach's green stream ending in its exit lane); a crossing or a crosswalk
--      still keeps it out. The same rule as "Free kerb turn: When safe" (sl_lights L.kerbPhases SAFE,
--      user decision 2026-10-12: in game a freed turner merged into the green stream tolerably and
--      the junction ran more efficiently; findings roads.md "A connection unlocked in a phase does
--      not give way", "Later observations"), so the plan subsumes When safe. Done last, on top of
--      the strict plan, so no straight or crosswalk ever loses a phase to a merging kerb turn (steps
--      2-4 are unchanged); the plan lists the kerb turns it treated so (plan.kerb, 0-based set) and
--      PP.validatePlan accepts exactly those merges.
--   5. All-red clearance (opts.allRed, default "auto"): one fully locked phase after every phase, as
--      the game's defaults have (6 / 6 / 9 s there). Vehicles: clamp(round(junction width /
--      clearSpeed 8 m/s), 2, 4) s, the width = the widest arm's road (driving lanes x 4.5 m), 3 s when
--      unknown; after the pedestrian phase max(that, pedClear 3 s). A number: that after every phase;
--      0: none.
--   6. canSkip and timing (below), states, validation.
--
-- Patterns (arms ordered counter-clockwise by angle; "turn" = class far or u_turn, "non" = the rest;
-- an approach "shares" when one entry lane carries a turn and a non-turn connection):
--   * x4 (4 arms in two opposite pairs, each within AXIS_TOL of 180 deg), per axis:
--       single     one approach on the axis (the other arm one-way out): one phase;
--       plain      no turn movement on the axis: one phase, both approaches;
--       protected  turns, no shared lane: opposing turns (leading) -> both approaches' straights and
--                  kerb turns;
--       split      a shared lane: one phase per approach (all its movements);
--       leadlag    exactly one approach shares: its approach (lead) -> both non-turn -> the other's
--                  turns (lag); a candidate next to split, chosen when its estimated cycle is
--                  shorter (PP.score: lane service incl. head-of-line blocking, see there). With lane
--                  counts as demand split always wins by one phase change; lead-lag needs real demand
--                  (opts.laneDemand, later from the traffic log).
--     The axis with more entry lanes goes first (ties: the lower segment id). kind "x4_<mode>" when both axes agree, else
--     "x4_mixed" (plan.axes lists both).
--   * t3 (3 arms; the main road = the arm pair with straight movements between them, else the pair
--     nearest 180 deg within AXIS_TOL): main approaches' non-turn movements (straights both ways +
--     kerb turns into the side road) -> per main approach with turns: its turns + its straight
--     (lead) -> the side road (every movement). kind "t3".
--   * generic (other shapes: 5+ arms, a skewed or one-sided crossing): greedy colouring of the
--     approaches (all movements of one approach together; split where they conflict among
--     themselves) in arm order, every unit into the first phase it fits. kind "generic".
--   A pattern whose plan fails (too many phases) falls back to generic.
--   * fan (opts.fan, the sl_fan zone's measuring mode: PHASES_PLAN.md "Fan mode"; kind x4_fan / t3_fan /
--     fan): the connections are sl_cross X.fanConns (every entry lane to every exit lane of every other
--     arm), whose movements of one approach cross and merge among themselves by design. Seeds: one
--     phase per approach (all its connections), approaches in arm order; then steps 3-6 as everywhere:
--     every other approach's movement that conflicts with nothing green joins a phase, crosswalks
--     (a full fan uses every arm, so they mostly get the pedestrian phase), all-red, timing. Conflicts
--     between two connections of the same approach (M.seg0) are accepted in fan plans only (fits,
--     PP.validatePlan with opts.fan); a conflict between approaches, or with a crosswalk, never is.
--     No generic fallback.
--
-- canSkip (opts.skip):
--   "all" (default, the game's way): every phase may skip / end early with minDuration 1.5 s
--     (skipMinGreen); the all-red clearances never skip (a fully locked phase has no lanes that would
--     hold it: it could end at once and lose the clearance). No starvation rule is needed: canSkip ends a
--     phase only "when these lanes are empty and traffic is waiting on another phase" (Crossing window),
--     so a phase with waiting traffic runs. Pedestrian crossing time goes into the green, not
--     minDuration (inferred: a crosswalk with pedestrians on it is a lane that is not empty).
--   "turns": a phase may skip when everything green only in it is a turn connection (protected turn
--     arrows, the T's lead phase); a phase that is the only green of a straight, a kerb turn or a
--     crosswalk never skips; at least one phase never skips; minDuration = skipMinGreen or the
--     pedestrian need. "none": no phase skips.
--
-- Timing (PP.timing):
--   * Weight of a phase: per approach, the demand of its entry lanes whose seed movements are first
--     placed in that phase (a lane with k movement classes counts 1/k per class; demand = 1 per lane,
--     or info/opts.laneDemand["seg:lane"]; a unit whose seeds a crosswalk took is shared by the phases
--     it is green in); the phase weight is the largest over approaches (approaches run side by side).
--     Lane counts stand in for traffic until the traffic log gives numbers.
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
	secPerLane = 10,        -- s of green per weight unit, for PP.score only
	lostTime = 4,           -- s per phase change (start-up, amber animation), for PP.score only
	skipMinGreen = 1.5,     -- s, minDuration of a skippable phase (the game's 1.5)
	allRed = "auto",        -- clearance after every phase: "auto" (see clearances) | seconds | 0 (none)
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
}
PP.MIN_DURATION = 1         -- the Crossing window's duration slider: 1..60 whole seconds
PP.MAX_DURATION = 60
PP.MAX_MIN_DURATION = 30    -- minDuration slider: 0..30 s in 0.5 s steps
PP.MAX_STATES = 32          -- validation bound (8 phases + all-red after each, with room)
PP.AXIS_TOL = 45            -- deg off 180 for two arms to form an axis

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
-- rest), the driving side, road lanes per arm (driving lanes both ways, for the crossing length).
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
	return { conns = conns, arms = arms, cls = Phases.classesFromView(conns, v), side = v and v.side, roadLanes = roadLanes }
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
		used = {}, lanesOf = {}, laneConns = {}, laneKey = {}, o = o, info = info }
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
			if ctx.lanesOf[s] == nil then ctx.lanesOf[s] = {} end
			table.insert(ctx.lanesOf[s], key)
		end
		table.insert(ctx.laneConns[key], x)
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

--- Turn / non-turn connections of approach s, and whether one of its lanes carries both.
local function splitApproach(ctx, s)
	local turn, non = {}, {}
	for _, x in ipairs(ctx.ap[s] or {}) do
		if isTurnCls(ctx.cls[x]) then turn[#turn + 1] = x else non[#non + 1] = x end
	end
	local shared = false
	for _, key in ipairs(ctx.lanesOf[s] or {}) do
		local t, u = false, false
		for _, x in ipairs(ctx.laneConns[key]) do
			if isTurnCls(ctx.cls[x]) then t = true else u = true end
		end
		if t and u then shared = true end
	end
	return turn, non, shared
end

local function concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, x in ipairs(list) do out[#out + 1] = x end
	end
	return out
end

local function lanesCount(ctx, s) return #(ctx.lanesOf[s] or {}) end

---------------------------------------------------------------------------
-- Phase building

--- Whether entry x conflicts with nothing in green. pedYield: crosswalk conflicts ("ped") allowed.
-- fanSeg (fan plans only): { [conn] = approach segment }; a conflict between two connections of one
-- approach is accepted (the fan's lanes cross by design), never one with a crosswalk.
local function fits(M, green, x, pedYield, fanSeg)
	for j, kind in pairs(M.kinds[x] or {}) do
		if green[j] and not (pedYield and kind == Phases.PED)
			and not (fanSeg ~= nil and kind ~= Phases.PED and fanSeg[x] ~= nil and fanSeg[x] == fanSeg[j]) then
			return false
		end
	end
	return true
end

--- Step 4b: whether kerb turn x may join `green`: every conflict with a green entry is a merge
-- (pedYield: crosswalk conflicts allowed, as fits).
local function fitsMerging(M, green, x, pedYield)
	for j, kind in pairs(M.kinds[x] or {}) do
		if green[j] and kind ~= Phases.MERGE and not (pedYield and kind == Phases.PED) then return false end
	end
	return true
end

local function newPhase(tag) return { green = {}, seeds = {}, tag = tag } end

local function addGreen(ph, x, seed)
	ph.green[x] = true
	if seed then ph.seeds[#ph.seeds + 1] = x end
end

--- Phases from seed lists (steps 2-4). seedPhases = { {tag, seeds = {0-based conns}} }.
-- Returns phases or nil, reason.
local function realise(M, ctx, seedPhases)
	local o, n = ctx.o, M.n
	local phases = {}
	for _, sp in ipairs(seedPhases) do
		local ph = newPhase(sp.tag)
		for _, x in ipairs(sp.seeds) do
			-- a seed that does not fit is placed below (first phase it fits, else a new one)
			if not ph.green[x] and fits(M, ph.green, x, o.pedYield, ctx.fanSeg) then addGreen(ph, x, true) end
		end
		if #ph.seeds > 0 then phases[#phases + 1] = ph end
	end
	-- the seed phases count too (genericSeeds makes as many as the colouring needs)
	if #phases > o.maxPhases then return nil, "too_many_phases" end
	-- connections green nowhere: the first phase they fit, else a new one
	for x = 0, n - 1 do
		local any = false
		for _, ph in ipairs(phases) do
			if ph.green[x] then any = true break end
		end
		if not any then
			local home = nil
			for _, ph in ipairs(phases) do
				if fits(M, ph.green, x, o.pedYield, ctx.fanSeg) then home = ph break end
			end
			if home == nil then
				if #phases >= o.maxPhases then return nil, "too_many_phases" end
				home = newPhase("extra")
				phases[#phases + 1] = home
			end
			addGreen(home, x, true)
		end
	end
	-- maximal phases: connections
	for _, ph in ipairs(phases) do
		for x = 0, n - 1 do
			if not ph.green[x] and fits(M, ph.green, x, o.pedYield, ctx.fanSeg) then addGreen(ph, x, false) end
		end
	end
	-- crosswalks
	local walk = nil
	for k = 1, M.nCross do
		local x = n + k - 1
		local any = false
		for _, ph in ipairs(phases) do
			if fits(M, ph.green, x, o.pedYield, ctx.fanSeg) then
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
	-- maximal again (the pedestrian phase; nothing else changed)
	if walk ~= nil then
		for x = 0, M.size - 1 do
			if not walk.green[x] and fits(M, walk.green, x, o.pedYield, ctx.fanSeg) then addGreen(walk, x, false) end
		end
	end
	-- step 4b: kerb turns also where they only merge (in phase order, then index order)
	if o.kerbMerge ~= false and ctx.fanSeg == nil then
		for _, ph in ipairs(phases) do
			for x = 0, n - 1 do
				if ctx.cls[x] == "kerb" and not ph.green[x] and fitsMerging(M, ph.green, x, o.pedYield) then
					addGreen(ph, x, false)
				end
			end
		end
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

--- Candidate seed lists of one axis: { {mode, phases = {seed lists}} }.
local function axisCandidates(ctx, axis)
	local present = {}
	for _, s in ipairs(axis) do
		if ctx.ap[s] ~= nil then present[#present + 1] = s end
	end
	if #present == 0 then return { { mode = "none", phases = {} } } end
	local turn, non, shared, anyTurn, nShared = {}, {}, {}, false, 0
	for _, s in ipairs(present) do
		turn[s], non[s], shared[s] = splitApproach(ctx, s)
		if #turn[s] > 0 then anyTurn = true end
		if shared[s] then nShared = nShared + 1 end
	end
	local a, c = present[1], present[2]
	if c == nil then
		-- one approach (the other arm one-way out): nothing opposes it, one phase
		return { { mode = "single", phases = { { tag = "approach", seeds = concat(non[a], turn[a]) } } } }
	end
	if not anyTurn then
		return { { mode = "plain", phases = { { tag = "axis", seeds = concat(non[a], c and non[c] or {}) } } } }
	end
	if nShared == 0 then
		return { { mode = "protected", phases = {
			{ tag = "turn", seeds = concat(turn[a], c and turn[c] or {}) },
			{ tag = "axis", seeds = concat(non[a], c and non[c] or {}) } } } }
	end
	local out = {}
	local split = { mode = "split", phases = {} }
	for _, s in ipairs(present) do
		split.phases[#split.phases + 1] = { tag = "approach", seeds = concat(non[s], turn[s]) }
	end
	out[1] = split
	if c ~= nil and nShared == 1 then
		local lead, other = a, c
		if shared[c] then lead, other = c, a end
		local ll = { mode = "leadlag", phases = { { tag = "approach", seeds = concat(non[lead], turn[lead]) },
			{ tag = "axis", seeds = concat(non[lead], non[other]) } } }
		if #turn[other] > 0 then ll.phases[3] = { tag = "turn", seeds = turn[other] } end
		out[2] = ll
	end
	return out
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
local function fanPatterns(ctx)
	local seeds = {}
	for _, s in ipairs(ctx.apOrder) do seeds[#seeds + 1] = { tag = "approach", seeds = ctx.ap[s] } end
	local kind = "fan"
	if axesOf(ctx) ~= nil then kind = "x4_fan" elseif tShape(ctx) ~= nil then kind = "t3_fan" end
	return { { kind = kind, seeds = seeds, why = string.format("fan %d approaches %d arms", #ctx.apOrder, #ctx.arms) } }
end

local function patterns(M, ctx)
	if ctx.o.fan then return fanPatterns(ctx) end
	local out = {}
	local axes = axesOf(ctx)
	if axes ~= nil then
		local c1, c2 = axisCandidates(ctx, axes[1]), axisCandidates(ctx, axes[2])
		for _, p1 in ipairs(c1) do
			for _, p2 in ipairs(c2) do
				local seeds = concat(p1.phases, p2.phases)
				local m1, m2 = p1.mode, p2.mode
				local kind
				if m1 == m2 or m2 == "none" then kind = "x4_" .. m1
				elseif m1 == "none" then kind = "x4_" .. m2
				else kind = "x4_mixed" end
				out[#out + 1] = { kind = kind, seeds = seeds, axes = { m1, m2 },
					why = string.format("x4 axes %s-%s %s, %s-%s %s", tostring(axes[1][1]), tostring(axes[1][2]), m1,
						tostring(axes[2][1]), tostring(axes[2][2]), m2) }
			end
		end
		return out
	end
	local main, side = tShape(ctx)
	if main ~= nil then
		local seeds = {}
		local p1 = {}
		local leads = {}
		for _, s in ipairs(main) do
			if ctx.ap[s] ~= nil then
				local turn, non = splitApproach(ctx, s)
				for _, x in ipairs(non) do p1[#p1 + 1] = x end
				if #turn > 0 then
					local own = {}
					for _, x in ipairs(non) do
						if ctx.cls[x] == "straight" then own[#own + 1] = x end
					end
					leads[#leads + 1] = { tag = "turn", seeds = concat(turn, own) }
				end
			end
		end
		if #p1 > 0 then seeds[#seeds + 1] = { tag = "main", seeds = p1 } end
		for _, l in ipairs(leads) do seeds[#seeds + 1] = l end
		if ctx.ap[side] ~= nil then seeds[#seeds + 1] = { tag = "side", seeds = ctx.ap[side] } end
		out[#out + 1] = { kind = "t3", seeds = seeds,
			why = string.format("t3 main %s-%s side %s", tostring(main[1]), tostring(main[2]), tostring(side)) }
		return out
	end
	return out
end

--- Generic: approach units (split where their own movements conflict), greedy colouring in arm order.
local function genericSeeds(M, ctx)
	local phases = {}
	for _, s in ipairs(ctx.apOrder) do
		local units = {}
		for _, x in ipairs(ctx.ap[s]) do
			local home = nil
			for _, u in ipairs(units) do
				if fits(M, u.set, x, ctx.o.pedYield, ctx.fanSeg) then home = u break end
			end
			if home == nil then
				home = { set = {}, list = {} }
				units[#units + 1] = home
			end
			home.set[x] = true
			home.list[#home.list + 1] = x
		end
		for _, u in ipairs(units) do
			local home = nil
			for _, ph in ipairs(phases) do
				local okAll = true
				for _, x in ipairs(u.list) do
					if not fits(M, ph.set, x, ctx.o.pedYield, ctx.fanSeg) then okAll = false break end
				end
				if okAll then home = ph break end
			end
			if home == nil then
				home = { tag = "approach", seeds = {}, set = {} }
				phases[#phases + 1] = home
			end
			for _, x in ipairs(u.list) do
				home.set[x] = true
				home.seeds[#home.seeds + 1] = x
			end
		end
	end
	return phases
end

---------------------------------------------------------------------------
-- Scoring and timing

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
	local width = widestArm(ctx)
	local veh = o.clearDefault
	if width ~= nil then veh = math.floor(width / o.clearSpeed + 0.5) end
	veh = math.min(o.clearMax, math.max(o.clearMin, veh))
	return veh, math.max(veh, math.min(PP.MAX_DURATION, math.ceil(o.pedClear - 1e-9)))
end
PP.clearances = clearances

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
		for p, ph in ipairs(phases) do flags[p] = ph.tag ~= "all_red" end
		return flags
	end
	local function needsFixed(x) return x >= M.n or not isTurnCls(ctx.cls[x]) end
	for p, ph in ipairs(phases) do
		local can = ctx.o.skip == "turns" and ph.tag ~= "all_red" and ph.tag ~= "walk"
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
			if ph.tag == "all_red" then f[p], mf[p] = ph.fixed, 0
			else
				-- a pedestrian-only phase: the game's 3 s walk start (its clearance follows as all-red)
				local onlyWalk = next(ph.green) ~= nil
				for x in pairs(ph.green) do
					if x < M.n then onlyWalk = false break end
				end
				f[p] = onlyWalk and o.pedClear or o.minGreen
				mf[p] = skip[p] and o.skipMinGreen or 0
				if mf[p] > f[p] then f[p] = mf[p] end
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
								if need > f[q] then f[q] = need end
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
							elseif need > f[q] then
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
		g[p] = (w[p] > 0) and (o.greenBase + o.greenPerLane * w[p]) or 0
		if ph.tag == "all_red" then fixed = fixed + f[p]
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
			if ph.tag ~= "all_red" then t = t + math.max(f[p], s * g[p]) end
		end
		return t
	end
	local d = {}
	local hi = 0
	for p, ph in ipairs(phases) do
		if ph.tag ~= "all_red" and g[p] > 0 then hi = math.max(hi, target / g[p]) end
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
		if ph.tag == "all_red" then v = f[p]
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

--- Lane service model for choosing between candidates: an entry lane is served in a phase when all
-- its connections are green there (a red movement at the head of a shared lane blocks the lane);
-- a lane never fully green counts where any of its connections is. Each lane needs its demand;
-- a greedy cover gives each phase the green time (in demand units) it needs. Returns the
-- estimated cycle: sum of max(cover * secPerLane, floor) + lostTime per phase.
function PP.score(M, ctx, phases, f)
	local o = ctx.o
	local units = {}
	for _, key in ipairs(sortedKeys(ctx.laneConns)) do
		local list = ctx.laneConns[key]
		local full, anyP = {}, {}
		for p, ph in ipairs(phases) do
			local all, any = true, false
			for _, x in ipairs(list) do
				if ph.green[x] then any = true else all = false end
			end
			if all then full[#full + 1] = p end
			if any then anyP[#anyP + 1] = p end
		end
		local serve = #full > 0 and full or anyP
		local set = {}
		for _, p in ipairs(serve) do set[p] = true end
		units[#units + 1] = { need = demandOf(ctx, key), set = set }
	end
	local cover = {}
	for p = 1, #phases do cover[p] = 0 end
	for _ = 1, #units + 1 do
		-- the unmet unit with the largest need, served by the phase that serves the most remaining need
		local u0 = nil
		for _, u in ipairs(units) do
			if u.need > 1e-9 and next(u.set) ~= nil and (u0 == nil or u.need > u0.need) then u0 = u end
		end
		if u0 == nil then break end
		local bestP, bestGain = nil, -1
		for p = 1, #phases do
			if u0.set[p] then
				local gain = 0
				for _, u in ipairs(units) do
					if u.need > 1e-9 and u.set[p] then gain = gain + u.need end
				end
				if gain > bestGain then bestP, bestGain = p, gain end
			end
		end
		local delta = math.huge
		for _, u in ipairs(units) do
			if u.need > 1e-9 and u.set[bestP] and u.need < delta then delta = u.need end
		end
		cover[bestP] = cover[bestP] + delta
		for _, u in ipairs(units) do
			if u.set[bestP] then u.need = math.max(0, u.need - delta) end
		end
	end
	local est = 0
	for p = 1, #phases do
		est = est + math.max(cover[p] * o.secPerLane, f[p] or 0) + o.lostTime
	end
	return est, cover
end

---------------------------------------------------------------------------
-- Plan

local function finish(M, ctx, phases, cand)
	local o = ctx.o
	local veh, ped = clearances(M, ctx)
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
	return { states = states, kind = cand.kind, axes = cand.axes, why = cand.why, cycle = cycle, warnings = warnings,
		floors = f, phases = phases, fan = o.fan == true or nil, kerb = kerb }
end

--- Plans the phases of one lit node. M: sl_phases P.build map; info = { conns (the list M was built
-- from), arms = {seg, angle}, cls (1-based per connection; else M.cls; else from the angles), side
-- ("right" | "left", for classes from angles), roadLanes / crossLen per arm segment, laneDemand
-- ["seg:lane"] }; opts: PP.DEFAULTS overrides (fan = true: the fan plan, see the header). Returns plan =
-- { states = { {locked (0-based), green, duration, minDuration, canSkip, tag, weight} }, kind, axes, why,
-- cycle, warnings, score, fan (true for a fan plan) } or nil, reason.
function PP.plan(M, info, opts)
	if M == nil then return nil, "no_map" end
	info = info or {}
	local o = options(opts)
	if #(info.conns or {}) ~= M.n then return nil, "conns_mismatch" end
	if M.n == 0 then return nil, "no_conns" end
	local ctx = context(M, info, o)
	local cands = patterns(M, ctx)
	local best, bestScore, firstWhy = nil, nil, nil
	local function try(cand)
		local phases, why = realise(M, ctx, cand.seeds)
		if phases == nil then
			firstWhy = firstWhy or why
			return
		end
		local plan = finish(M, ctx, phases, cand)
		local okV, reason = PP.validatePlan(M, plan, M.n, M.nCross, o)
		if not okV then
			firstWhy = firstWhy or ("invalid_" .. tostring(reason))
			return
		end
		plan.score = PP.score(M, ctx, plan.phases, plan.floors)
		if bestScore == nil or plan.score < bestScore - 1e-6 then best, bestScore = plan, plan.score end
	end
	for _, cand in ipairs(cands) do try(cand) end
	if best == nil and not o.fan then
		try({ kind = "generic", why = (#cands > 0 and "pattern failed, " or "") .. "generic " .. #ctx.arms .. " arms",
			seeds = genericSeeds(M, ctx) })
	end
	if best == nil then return nil, firstWhy or "no_plan" end
	if #cands > 1 then best.why = best.why .. string.format(" (best of %d, est %.0f s)", #cands, bestScore) end
	best.phases, best.floors = nil, nil
	return best
end

--- Checks a plan against the map: states present and bounded, every index an integer in range and
-- not repeated, every connection and crosswalk green in some phase, no conflicting pair green in a
-- phase (opts.pedYield: crosswalk conflicts allowed), durations whole seconds 1..60, minDuration
-- 0..min(duration, 30) in 0.5 s steps, canSkip boolean, at least one phase that never skips (unless
-- opts.skip is "all", the default). opts.fan (explicit, fan plans only): a conflict between two
-- connections of the same approach (M.seg0) is accepted; between approaches or with a crosswalk never.
-- A merge with a kerb turn (step 4b: one the plan lists in plan.kerb, or class "kerb" in M.cls) is
-- accepted unless opts.kerbMerge is false or opts.fan; a listed connection whose class M.cls knows
-- must be "kerb" (else "kerb_class:x").
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
			if not (opts and opts.pedYield and c[3] == Phases.PED) and not intra and not kerbMerge then
				return false, string.format("conflict:%d:%d-%d:%s", s, c[1], c[2], c[3])
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
