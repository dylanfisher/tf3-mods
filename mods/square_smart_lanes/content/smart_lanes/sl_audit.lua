-- Smart Lanes: junction audit (pure, no api.* calls), unit-tested in tests/square_smart_lanes/test_audit.lua.
-- User request 2026-10-11: find inefficient lane setups automatically instead of checking every junction by
-- eye. A.audit looks at one junction's road connections (the planned ones of a write, or the current ones of
-- a pick) and counts findings; the automatic pass and the tool log them as AUDIT lines (TESTING.md X), and
-- tools/sqrl_audit.py (make audit) sums them up from stdout.txt.
--
-- Counts are of exit lanes (squeeze, shared, unfed), incoming lanes (dead) or movements (approach > exit:
-- across, ramp_ramp, u_turn, bypassed_turn, weave). Only AVOIDABLE findings count (res.counts); squeeze,
-- shared and weave that the lane counts force, and what the rule does on purpose (shared_lit, turbo_gap),
-- go to res.forced (logged, never a reason for an AUDIT line):
--   * squeeze: an exit lane fed by k > 1 lanes of one approach adds k - 1. The exit road's pressure is
--     minEx = sum over the movements into it of need(a, b) = max(1, N_a - lanes of a's other candidate
--     exits) (what approach a must put into b even when its other exits take all they can), less the exit
--     road's lanes: the fewest extra feeds any allocation has there. Forced squeeze: an approach needing more
--     lanes than the road has (need - lanes: a lane drop 3 -> 2, a ring entry wider than the ring), then the
--     pressure the forced sharing below does not take (a ramp's own-lane merge, a ring's ramp entry); the
--     rest is avoidable (four lanes into one where the approach had room elsewhere).
--   * shared: an exit lane fed by m > 1 approaches (movements) adds m - 1. Avoidable only when an allocation
--     without sharing exists at that exit road (the needs fit its lanes: a cheap per-exit approximation,
--     ignoring that the approaches' other exits compete for the same lanes); else forced (a 2x2 crossroads:
--     three movements into two lanes; a give-way merge). Also forced: as many shares at an approach's exits
--     as its excess, the lanes over what its candidate exits have left once every other movement into them
--     has a lane (at least 1 per exit): a 2x3 T's side road, 3 lanes and one free lane in each main road exit. A ring's entry lanes meeting circulating lanes in
--     the ring-out segment are the roundabout's give-way: forced.
--     shared_lit (by design, in res.forced, never a reason for a line): at a crossroads with traffic
--     lights (view.lit true, sl_cross X.litOf), avoidable sharing of a lane by a straight movement and a
--     turn from another approach: the rule keeps its extra straight shares there (the movements run in
--     different phases; user decision 2026-10-11). At an unlit node the rule drops them, so such sharing
--     there stays `shared`; unknown (AUTO without a light standing) is reported as `shared` too.
--     The exit fan (sl_exitfan zones, view.exitFan): every share of a lane by movements of different game phases,
--     and one boundary lane per neighbouring pair of one phase's movements, is shared_lit; only shares within one
--     phase beyond those count as `shared`.
--   * across: a move across the opposing carriageway into or out of a shallow ramp (sl_cross X.shallowRamps /
--     X.shallowBlocked), unless it is the exit road's only feed or the approach's only way on (or the
--     crossing rule kept it: view.shallowKept).
--   * ramp_ramp: a ramp straight back onto a ramp at a node with a two-way road, while a road is there.
--     A ring's own segments (opts.ring.segSet) are never ramps: one-way and without sidewalks on
--     interchange and Magic Roundabout rings, their circulating move is no ramp_ramp.
--   * u_turn: a move back onto its own segment or turning over MAX_TURN_DEG (135), while the approach has
--     another way on.
--   * unfed: an outgoing road lane nobody feeds although some approach could (one of its candidate exits).
--     turbo_gap (by design, in res.forced): at a ring junction with exits and no entry where the ring-in
--     outer lane only exits (turbo, Rules.twoLaneConns), the ring-out outer lane stays empty up to the
--     next entry, which then joins the ring without giving way.
--   * dead: an incoming road lane without a connection although its road has a way on.
--   * bypassed_turn: a turn allowed at a crossroads although a slip lane serves it (sl_cross X.bypasses, kept
--     in view.bypassMap), not the straight move, while the approach has another exit that is no bypassed
--     turn and the exit road another feed that is no bypassed turn itself (as sl_cross dropBypassed: an
--     approach whose every turn has a slip lane keeps them, and when every feed of an exit road is one,
--     the crossing rule keeps them all, so the road stays fed).
--   * weave (heuristic): an exit road whose far end, at most WEAVE_M m away, is a junction J: per movement
--     into it, the exits of J that no lane it feeds reaches there (its traffic must change lanes within that
--     distance). Avoidable (res.counts) only as far as lanes of the exit road next to the movement's that
--     no movement feeds would reach those exits (it could fan out into them, no crossing, no sharing); the
--     rest goes to res.forced.weave: the lanes the other movements into the road take force it (a kerb
--     turn into the kerb lane of a 3-lane town street that is a turn lane again one block on). Needs
--     opts.connsOf(J); one segment only (no lane mapping through plain nodes); ring segments and junctions
--     without known connections are not looked at.
--   * lights: a roundabout arm junction or a slip node (cases A / B) that still has a traffic light, when
--     opts.lightsOf(n) tells (the tool's pick; the automatic pass removes them after its write anyway).
--   * bad: a road connection naming a segment or lane that is no road lane of the node now (stale).
-- Bounded: at most MAX_ROADS road segments (else skipped "roads"), MAX_CONNS connections, one shallow-ramp
-- measure (walks of 50 m), and connsOf / roadSegs of at most one far node per exit road. Nil-safe: a missing
-- world, node or segment gives a result with `skipped` set and no findings. Callers pcall it anyway (A.safe).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Walk = ug_require "square_smart_lanes::/smart_lanes/sl_walk.lua"

local A = {}

A.MAX_TURN_DEG = Cross.MAX_TURN_DEG -- 135: sharper turns are U-turns
A.WEAVE_M = 80     -- an exit road shorter than this to the next junction is looked along (weave)
A.MAX_ROADS = 6    -- nodes with more road segments are not audited
A.MAX_CONNS = 512  -- connections looked at per node
A.MAX_DETAIL = 6   -- detail entries per node
A.MAX_LINES = 40   -- AUDIT lines per automatic job (the rest only in AUDIT_SUMMARY: flagged, unlogged=)
A.KINDS = { "squeeze", "shared", "across", "ramp_ramp", "u_turn", "unfed", "dead", "bypassed_turn", "weave",
	"lights", "bad" }

local function add(map, k, n)
	if n ~= nil and n > 0 then map[k] = (map[k] or 0) + n end
end

local function ringShape(v)
	if v == nil or v.kind ~= "arm" then return nil end
	local x, e = #(v.x or {}), #(v.e or {})
	if x > 0 and e > 0 then return "arm" end
	return x > 0 and "exit" or "entry"
end

--- Audits node n of `world` with road connections `conns` (plain tables; tram-only ones are ignored).
-- opts: view (sl_slip view or sl_ring nodeView: case / shape, driving side, bypassMap, approaches' exit
--   categories), ring (sl_ring ring when n is a ring junction: its ring-out give-way is forced, its segments
--   are no weave roads), connsOf(J) -> connections of junction J or nil (weave), lightsOf(n) -> { light }
--   or nil (lights), connsFirst (call connsOf before reading J's roads: callers whose connsOf knows only
--   planned junctions, so the look-ahead reads nothing new), case / shape (log labels overriding the view's).
-- Returns { node, case, shape, counts = { kind = n } (avoidable), forced = { squeeze, shared, shared_lit,
-- turbo_gap, weave }, detail =
-- { short strings }, total (sum of counts), skipped (reason, nil when audited) }.
function A.audit(world, n, conns, opts)
	opts = opts or {}
	local v = opts.view
	local res = { node = n, counts = {}, forced = {}, detail = {}, total = 0 }
	res.case = opts.case or (v and v.case) or (v and v.kind == "arm" and "ring") or "-"
	res.shape = opts.shape or (v and v.shape) or ringShape(v) or "-"
	local function stop(why)
		res.skipped = why
		return res
	end
	if world == nil or type(n) ~= "number" then return stop("no_world") end
	local roads, why = Walk.roadSegs(world, n)
	if roads == nil then return stop(why or "no_node") end
	if #roads < 2 then return stop("dead_end") end
	if #roads > A.MAX_ROADS then return stop("roads") end
	local function note(s)
		if #res.detail < A.MAX_DETAIL then res.detail[#res.detail + 1] = s end
	end

	-- the node's road segments
	local list, R, hasTwoWay, anyRamp = {}, {}, false, false
	-- a ring's own segments are one-way and often have no sidewalk (interchange and Magic Roundabout rings):
	-- never ramps (showcase 2026-10-12: 86 ramp_ramp at ring arms were the circulating ringIn > ringOut)
	local ringSegs = opts.ring ~= nil and type(opts.ring.segSet) == "table" and opts.ring.segSet or nil
	for _, x in ipairs(roads) do
		if x.la.busOnly then return stop("bus_lane") end
		local r = { sid = x.sid, la = x.la, N = #x.la.incoming, W = #x.la.outgoing, inSet = {}, outSet = {} }
		for _, l in ipairs(x.la.incoming) do r.inSet[l] = true end
		for _, l in ipairs(x.la.outgoing) do r.outSet[l] = true end
		r.twoWay = r.N > 0 and r.W > 0
		if r.twoWay then hasTwoWay = true end
		r.ramp = not (ringSegs ~= nil and ringSegs[x.sid]) and Rules.isRampSeg(world, x.sid)
		if r.ramp then anyRamp = true end
		list[#list + 1] = r
		R[x.sid] = r
	end
	local degMemo = {}
	local function deg(a, b)
		local k = a .. ">" .. b
		local d = degMemo[k]
		if d == nil then
			d = a == b and 180 or Slip.turnDeg(world, n, a, b)
			degMemo[k] = d
		end
		return d
	end
	local side = v and v.side
	if side == nil then
		for _, r in ipairs(list) do
			if side == nil and r.twoWay then side = Slip.sideOf(r.la) end
		end
	end
	-- shallow ramps: moves across the opposing carriageway (the crossing rule's measure)
	local sh = nil
	if hasTwoWay and anyRamp and side ~= nil then
		local okS, s = pcall(Cross.shallowRamps, world, n, list, side)
		if okS then sh = s end
	end
	-- moves the crossing rule kept although blocked (the exit road's only feed, the ramp's only way on)
	local kept = {}
	for _, k in ipairs(v and v.shallowKept or {}) do kept[k] = true end
	local function blocked(a, b) return sh ~= nil and Cross.shallowBlocked(sh, R[a], R[b]) == true end

	-- candidate exits per approach: the rule's own model where the view has one (crossroads: the
	-- approaches' exits after the shallow-ramp and bypass filters; slip nodes and lane drops: the streams;
	-- ring junctions: ring on, exit, enter), else by geometry as the crossing rule picks them: not across
	-- a carriageway into a shallow ramp, no U-turn, no ramp onto a ramp at a road node, each only when
	-- nothing better is there
	local model = {}
	local function allow(a, b)
		if a ~= nil and b ~= nil and R[a] and R[b] and R[a].N > 0 and R[b].W > 0 and a ~= b then
			model[a] = model[a] or {}
			if not model[a][b] then
				model[a][b] = true
				model[a][#model[a] + 1] = b
			end
		end
	end
	if v ~= nil then
		if v.case == "X" then
			for _, ap in ipairs(v.approaches or {}) do
				for _, ex in ipairs(ap.exits or {}) do allow(ap.seg, ex.seg) end
			end
		elseif v.kind == "arm" then
			allow(v.ringIn, v.ringOut)
			if #(v.x or {}) > 0 then allow(v.ringIn, v.arm) end
			if #(v.e or {}) > 0 then allow(v.arm, v.ringOut) end
		else
			for _, st in ipairs(v.streams or {}) do
				if st.shape == "straight" then allow(st.inSeg, st.outSeg)
				elseif st.shape == "diverge" then
					allow(st.inSeg, st.throughSeg)
					allow(st.inSeg, st.branchSeg)
				elseif st.shape == "merge" then
					allow(st.throughSeg, st.outSeg)
					allow(st.branchSeg, st.outSeg)
				end
			end
		end
	end
	local cand, candSet = {}, {}
	for _, ra in ipairs(list) do
		local a = ra.sid
		if model[a] ~= nil then
			cand[a], candSet[a] = {}, {}
			for _, b in ipairs(model[a]) do
				cand[a][#cand[a] + 1] = b
				candSet[a][b] = true
			end
		elseif ra.N > 0 then
			local exits, ramps, sharp, blk = {}, {}, {}, {}
			for _, rb in ipairs(list) do
				local b = rb.sid
				if b ~= a and rb.W > 0 then
					if blocked(a, b) then blk[#blk + 1] = b
					elseif math.abs(deg(a, b)) > A.MAX_TURN_DEG then sharp[#sharp + 1] = b
					elseif hasTwoWay and ra.ramp and rb.ramp then ramps[#ramps + 1] = b
					else exits[#exits + 1] = b end
				end
			end
			local c = (#exits > 0 and exits) or (#ramps > 0 and ramps) or (#sharp > 0 and sharp) or blk
			cand[a], candSet[a] = c, {}
			for _, b in ipairs(c) do candSet[a][b] = true end
		end
	end
	local function need(a, b)
		local ra = R[a]
		if not (candSet[a] and candSet[a][b]) then return 1 end
		local other = 0
		for _, c in ipairs(cand[a]) do if c ~= b then other = other + R[c].W end end
		return math.max(1, ra.N - other)
	end

	-- the connections: feeders per exit lane and approach, movements, lanes used
	local feeds, moves, used, fed, order = {}, {}, {}, {}, {}
	for i, c in ipairs(conns or {}) do
		if i > A.MAX_CONNS then break end
		if type(c) == "table" and c.withRoad then
			local ra, rb = R[c.segment0], R[c.segment1]
			if not (ra and rb and ra.inSet[c.lane0] and rb.outSet[c.lane1]) then
				add(res.counts, "bad", 1)
				note("bad:" .. tostring(c.segment0) .. ">" .. tostring(c.segment1))
			else
				local a, b = c.segment0, c.segment1
				moves[a] = moves[a] or {}
				local mv = moves[a][b]
				if mv == nil then
					mv = { a = a, b = b, to = {} }
					moves[a][b] = mv
					order[#order + 1] = mv
				end
				mv.to[c.lane1] = true
				used[a] = used[a] or {}
				used[a][c.lane0] = true
				fed[b] = fed[b] or {}
				fed[b][c.lane1] = true
				feeds[b] = feeds[b] or {}
				feeds[b][c.lane1] = feeds[b][c.lane1] or {}
				local f = feeds[b][c.lane1]
				f[a] = f[a] or {}
				f[a][c.lane0] = true
			end
		end
	end

	-- crossroads (case X): the category of every movement (kerb turn, straight, far turn) for the detail
	local catOf = {}
	for _, ap in ipairs(v and v.approaches or {}) do
		catOf[ap.seg] = {}
		for _, ex in ipairs(ap.allExits or ap.exits or {}) do catOf[ap.seg][ex.seg] = ex.cat end
	end
	local LETTER = { kerb = "k", straight = "s", far = "f" }
	-- a crossroads with traffic lights (sl_cross X.litOf: the view's lit, true only when known)
	local litX = v ~= nil and v.case == "X" and v.lit == true
	-- per approach, the lanes no share-free allocation can place (excess): its lanes over the exit lanes
	-- its candidate exits have left once every other movement into them has one, at least one per exit
	-- (2x3 T: the side road's 3 lanes, 1 free lane in each 2-lane main road exit, excess 1; 3x3 T: none,
	-- a main road straight lane less frees one). need() looks at one exit road and lets
	-- the other exits take every lane; this budget makes that many shares at its exits forced
	local excess = {}
	for _, ra in ipairs(list) do
		local a = ra.sid
		if moves[a] ~= nil and cand[a] ~= nil then
			local room = 0
			for _, c in ipairs(cand[a]) do
				local others = 0
				for _, rx in ipairs(list) do
					if rx.sid ~= a and moves[rx.sid] and moves[rx.sid][c] then others = others + 1 end
				end
				-- at least 1: into an exit already over its lanes a lane folds or shares there (counted there)
				room = room + math.max(1, R[c].W - others)
			end
			if ra.N > room then excess[a] = ra.N - room end
		end
	end

	-- squeeze and shared, per exit road
	local ringOut = opts.ring ~= nil and v ~= nil and v.ringOut or nil
	for _, rb in ipairs(list) do
		local b = rb.sid
		if feeds[b] ~= nil then
			local S, H, HS, kinds = 0, 0, 0, nil
			for _, l in ipairs(rb.la.outgoing) do
				local byA = feeds[b][l]
				if byA ~= nil then
					local apps, ks, straight = 0, {}, false
					for _, ra in ipairs(list) do
						local set = byA[ra.sid]
						if set ~= nil then
							apps = apps + 1
							local k = 0
							for _ in pairs(set) do k = k + 1 end
							S = S + k - 1
							local cat = catOf[ra.sid] and catOf[ra.sid][b]
							if cat == "straight" then straight = true end
							ks[#ks + 1] = LETTER[cat] or ""
						end
					end
					H = H + math.max(0, apps - 1)
					-- a lane a straight movement shares with a turn from another approach
					if apps > 1 and straight then HS = HS + apps - 1 end
					if apps > 1 and kinds == nil then
						-- the first shared lane's movements, e.g. "sf" (straight + far turn)
						table.sort(ks)
						kinds = table.concat(ks)
					end
				end
			end
			-- the exit road's pressure: what the movements into it need at least, over its lanes (minEx: the
			-- fewest extra feeds any allocation has here); an approach needing more lanes than the road has
			-- must fold its own lanes (strict squeeze)
			local needs, strict = 0, 0
			for _, ra in ipairs(list) do
				if moves[ra.sid] and moves[ra.sid][b] then
					local nd = need(ra.sid, b)
					needs = needs + nd
					strict = strict + math.max(0, nd - rb.W)
				end
			end
			local minEx = math.max(0, needs - rb.W)
			local sharedForced = H > 0 and (needs > rb.W or b == ringOut)
			-- the exit fan (an sl_exitfan zone, view.exitFan): movements of different game phases share lanes
			-- by design, and the movements of one phase into the road share one boundary lane per neighbour
			-- pair; only shares within one phase beyond those count (the rest: shared_lit)
			local fanGroups = v ~= nil and v.exitFan == true and type(v.phaseGroup) == "table" and v.phaseGroup or nil
			if H > 0 and fanGroups ~= nil then
				local within, mvs = 0, {}
				for _, l in ipairs(rb.la.outgoing) do
					local byA = feeds[b][l]
					if byA ~= nil then
						local per = {}
						for a in pairs(byA) do
							local g = fanGroups[a] or a
							per[g] = (per[g] or 0) + 1
						end
						for _, k in pairs(per) do within = within + math.max(0, k - 1) end
					end
				end
				for _, ra in ipairs(list) do
					if moves[ra.sid] and moves[ra.sid][b] then
						local g = fanGroups[ra.sid] or ra.sid
						mvs[g] = (mvs[g] or 0) + 1
					end
				end
				local designed = 0
				for _, k in pairs(mvs) do designed = designed + math.max(0, k - 1) end
				local extra = math.min(H, math.max(0, within - designed))
				add(res.forced, "shared_lit", H - extra)
				if extra > 0 then
					add(res.counts, "shared", extra)
					note("shared:" .. b .. ((kinds ~= nil and kinds ~= "") and (":" .. kinds) or ""))
				end
				H, sharedForced = 0, false
			end
			if H > 0 then
				if sharedForced then
					add(res.forced, "shared", H)
				else
					-- shares an approach's excess forces somewhere (each excess lane forgives one share once)
					local fx = 0
					for _, ra in ipairs(list) do
						local e = excess[ra.sid]
						if e ~= nil and fx < H and moves[ra.sid] and moves[ra.sid][b] then
							local take = math.min(e, H - fx)
							fx, excess[ra.sid] = fx + take, e - take
						end
					end
					add(res.forced, "shared", fx)
					-- at a lit crossroads the straight movement and the turn sharing its lane run in
					-- different phases: the rule's extra straight shares stay there by design (shared_lit)
					local lit = litX and math.min(HS, H - fx) or 0
					add(res.forced, "shared_lit", lit)
					if H - fx - lit > 0 then
						add(res.counts, "shared", H - fx - lit)
						note("shared:" .. b .. ((kinds ~= nil and kinds ~= "") and (":" .. kinds) or ""))
					end
				end
			end
			-- forced squeeze: the strict part, then whatever pressure the forced sharing does not take
			local sqStrict = math.min(S, strict)
			local sqF = sqStrict + math.min(S - sqStrict, math.max(0, minEx - sqStrict - (sharedForced and H or 0)))
			add(res.forced, "squeeze", sqF)
			if S - sqF > 0 then
				add(res.counts, "squeeze", S - sqF)
				note("squeeze:" .. b)
			end
		end
	end

	-- the turbo gap (by design): at a ring junction with exits and no entry, the ring-in outer lane that only
	-- exits (Rules.twoLaneConns, turbo: the outer lane is exit-only) leaves the ring-out outer lane empty up
	-- to the next entry, which then joins the ring without giving way (showcase 2026-10-12: 21 unfed at the
	-- exit nodes of turbo rings with splitter arms)
	local gapLane = nil
	if ringOut ~= nil and v.kind == "arm" and #(v.e or {}) == 0 and #(v.x or {}) > 0 and v.o_in ~= nil
		and v.o_out ~= nil then
		local outer = v.o_in[1]
		if outer ~= nil and used[v.ringIn] and used[v.ringIn][outer] then
			local cont = false
			for _, byA in pairs(feeds[v.ringOut] or {}) do
				if byA[v.ringIn] and byA[v.ringIn][outer] then cont = true end
			end
			if not cont then gapLane = v.o_out[1] end
		end
	end

	-- unfed outgoing lanes, dead incoming lanes
	for _, rb in ipairs(list) do
		if rb.W > 0 then
			-- some approach may go there (a candidate exit of it: no U-turn needed)
			local feedable = false
			for _, ra in ipairs(list) do
				if candSet[ra.sid] and candSet[ra.sid][rb.sid] then feedable = true end
			end
			if feedable then
				local k = 0
				for _, l in ipairs(rb.la.outgoing) do
					if not (fed[rb.sid] and fed[rb.sid][l]) then
						if rb.sid == ringOut and l == gapLane then add(res.forced, "turbo_gap", 1) else k = k + 1 end
					end
				end
				if k > 0 then
					add(res.counts, "unfed", k)
					note("unfed:" .. rb.sid)
				end
			end
		end
		if rb.N > 0 and cand[rb.sid] and #cand[rb.sid] > 0 then
			local k = 0
			for _, l in ipairs(rb.la.incoming) do
				if not (used[rb.sid] and used[rb.sid][l]) then k = k + 1 end
			end
			if k > 0 then
				add(res.counts, "dead", k)
				note("dead:" .. rb.sid)
			end
		end
	end

	-- movements
	-- another approach could feed b (no U-turn, not across into a shallow ramp)
	local function otherFeed(a, b)
		for _, rd in ipairs(list) do
			local d = rd.sid
			if d ~= a and d ~= b and rd.N > 0 and math.abs(deg(d, b)) <= A.MAX_TURN_DEG and not blocked(d, b) then
				return true
			end
		end
		return false
	end
	local function otherExit(a, b, test)
		for _, c in ipairs(cand[a] or {}) do
			if c ~= b and test(c) then return true end
		end
		return false
	end
	local byMap = v and v.bypassMap
	-- a turn a slip lane serves (not the straight move)
	local function bypassedMove(a, b)
		return byMap ~= nil and byMap[a] ~= nil and byMap[a][b] == true and not (catOf[a] and catOf[a][b] == "straight")
	end
	-- another movement into b that the rule keeps there anyway (not itself a bypassed turn: when every feed
	-- of b is one, the crossing rule keeps them all, so b and the stretch along it stay fed; showcase
	-- 2026-10-12, T-junctions 117874 / 123825: both turns into the side road had slip lanes)
	local function keptFeed(a, b)
		for _, rd in ipairs(list) do
			local d = rd.sid
			if d ~= a and d ~= b and moves[d] and moves[d][b] and not bypassedMove(d, b) then return true end
		end
		return false
	end
	for _, mv in ipairs(order) do
		local a, b = mv.a, mv.b
		local d = deg(a, b)
		local tag = a .. ">" .. b
		if a == b or math.abs(d) > A.MAX_TURN_DEG then
			if otherExit(a, b, function(c) return c ~= a and math.abs(deg(a, c)) <= A.MAX_TURN_DEG end) then
				add(res.counts, "u_turn", 1)
				note("u_turn:" .. tag)
			end
		elseif hasTwoWay and R[a].ramp and R[b].ramp then
			if otherExit(a, b, function(c) return not R[c].ramp end) then
				add(res.counts, "ramp_ramp", 1)
				note("ramp_ramp:" .. tag)
			end
		end
		if blocked(a, b) and not kept[tag] and otherExit(a, b, function(c) return not blocked(a, c) end)
			and otherFeed(a, b) then
			add(res.counts, "across", 1)
			note("across:" .. tag)
		end
		-- as sl_cross dropBypassed: only while the approach has another exit that is no bypassed turn (a side
		-- road whose turns both have slip lanes keeps them)
		if bypassedMove(a, b) and otherExit(a, b, function(c) return not bypassedMove(a, c) end) and keptFeed(a, b) then
			add(res.counts, "bypassed_turn", 1)
			note("bypassed:" .. tag)
		end
	end

	-- weave (heuristic): one junction ahead along each short exit road
	if type(opts.connsOf) == "function" then
		for _, rb in ipairs(list) do
			local b = rb.sid
			local s = feeds[b] and world.seg(b)
			local J = s and ((s.node0 == n and s.node1) or (s.node1 == n and s.node0)) or nil
			local onRing = opts.ring ~= nil and opts.ring.segSet ~= nil and opts.ring.segSet[b]
			if J ~= nil and J ~= n and not onRing and Ring.segLength(s) <= A.WEAVE_M then
				-- connsFirst (the automatic pass: only the job's planned junctions are known): ask first, so
				-- a junction outside the plan costs no world read; else (the tool's config reads) only a
				-- junction (3+ road segments) is asked
				local okC, cJ = false, nil
				if opts.connsFirst then
					okC, cJ = pcall(opts.connsOf, J)
					if okC and type(cJ) == "table" and #cJ > 0 then
						local rJ = Walk.roadSegs(world, J)
						if rJ == nil or #rJ < 3 then cJ = nil end
					end
				else
					local rJ = Walk.roadSegs(world, J)
					if rJ ~= nil and #rJ >= 3 then okC, cJ = pcall(opts.connsOf, J) end
				end
				if okC and type(cJ) == "table" and #cJ > 0 then
					-- exits of J per arriving lane of b (lane index at J)
					local ex, all = {}, {}
					for i, c in ipairs(cJ) do
						if i > A.MAX_CONNS then break end
						if type(c) == "table" and c.withRoad and c.segment0 == b and c.segment1 ~= b then
							ex[c.lane0] = ex[c.lane0] or {}
							ex[c.lane0][c.segment1] = true
							all[c.segment1] = true
						end
					end
					local function reachOf(l, into)
						for sid in pairs(ex[Ring.otherEndIndex(s, l)] or {}) do into[sid] = true end
					end
					local function missing(reach)
						local miss = 0
						for sid in pairs(all) do if not reach[sid] then miss = miss + 1 end end
						return miss
					end
					local outs = rb.la.outgoing -- lane indices in lateral order
					for _, ra in ipairs(list) do
						local mv = moves[ra.sid] and moves[ra.sid][b]
						if mv ~= nil then
							local reach = {}
							for l in pairs(mv.to) do reachOf(l, reach) end
							local miss = missing(reach)
							if miss > 0 then
								-- avoidable only as far as lanes of b next to the movement's that nothing feeds
								-- would reach the missed exits (the movement could fan out into them without
								-- crossing or sharing); the rest is forced by the lanes the other movements
								-- into b take (a kerb turn into a town street's kerb lane that turns again
								-- at the next block: every 3-lane grid crossroads, showcase 2026-10-12)
								local more = {}
								for sid in pairs(reach) do more[sid] = true end
								for i, l in ipairs(outs) do
									if mv.to[l] then
										for _, step in ipairs({ -1, 1 }) do
											local k = i + step
											while outs[k] ~= nil and not fed[b][outs[k]] do
												reachOf(outs[k], more)
												k = k + step
											end
										end
									end
								end
								local left = missing(more)
								add(res.forced, "weave", left)
								if miss - left > 0 then
									add(res.counts, "weave", miss - left)
									note("weave:" .. ra.sid .. ">" .. b .. "@" .. J)
								end
							end
						end
					end
				end
			end
		end
	end

	-- lights at a node that should give way instead (roundabout arms, slip nodes)
	if type(opts.lightsOf) == "function" and v ~= nil and (v.kind == "arm" or v.case == "A" or v.case == "B") then
		local okL, st = pcall(opts.lightsOf, n)
		if okL and type(st) == "table" and st.light == true then
			add(res.counts, "lights", 1)
			note("lights")
		end
	end

	for _, k in ipairs(A.KINDS) do res.total = res.total + (res.counts[k] or 0) end
	return res
end

--- A.audit in a pcall: the result, or nil and the error (an audit never throws into its caller).
function A.safe(world, n, conns, opts)
	local ok, res = pcall(A.audit, world, n, conns, opts)
	if ok then return res end
	return nil, res
end

--- Log fields of an audit result (the AUDIT line): node, case, shape, findings, [forced], detail, then
-- `extra` ({key, value} pairs, e.g. src / job).
function A.fields(res, extra)
	local f = { { "node", res.node }, { "case", res.case }, { "shape", res.shape }, { "findings", Rules.countsText(res.counts) } }
	if next(res.forced) ~= nil then f[#f + 1] = { "forced", Rules.countsText(res.forced) } end
	f[#f + 1] = { "detail", #res.detail > 0 and table.concat(res.detail, ",") or "-" }
	for _, x in ipairs(extra or {}) do f[#f + 1] = x end
	return f
end

--- Totals over several audits: A.addTo(sum, res) for each, then A.summaryFields.
function A.newSum()
	return { audited = 0, flagged = 0, failed = 0, unlogged = 0, counts = {}, forced = {} }
end

function A.addTo(sum, res)
	if res == nil then
		sum.failed = sum.failed + 1
		return sum
	end
	if res.skipped ~= nil then return sum end
	sum.audited = sum.audited + 1
	if res.total > 0 then sum.flagged = sum.flagged + 1 end
	for k, c in pairs(res.counts) do add(sum.counts, k, c) end
	for k, c in pairs(res.forced) do add(sum.forced, k, c) end
	return sum
end

--- AUDIT_SUMMARY fields: `head` pairs first, then audited, flagged, findings, forced, failed and unlogged
-- (flagged junctions over the caller's line cap, A.MAX_LINES) when any.
function A.summaryFields(sum, head)
	local f = {}
	for _, x in ipairs(head or {}) do f[#f + 1] = x end
	f[#f + 1] = { "audited", sum.audited }
	f[#f + 1] = { "flagged", sum.flagged }
	f[#f + 1] = { "findings", Rules.countsText(sum.counts) }
	f[#f + 1] = { "forced", Rules.countsText(sum.forced) }
	if sum.failed > 0 then f[#f + 1] = { "failed", sum.failed } end
	if (sum.unlogged or 0) > 0 then f[#f + 1] = { "unlogged", sum.unlogged } end
	return f
end

return A
