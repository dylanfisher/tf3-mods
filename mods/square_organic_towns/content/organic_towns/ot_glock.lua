-- Organic Towns: lock the game's own streets, steer with valves (pure; §67, 2026-10-15; PLAN.md 6.2 "Game-street
-- locking and valves").
--
-- User (2026-10-15): "lets try locking the games streets after it builds them. then we try to steer early building with
-- locked streets, and intentionally build unlocked streets at the opportune places."
--
-- §65 locks every street the mod builds; run `2026-10-15_0759_rci-sqrl` still had the game build 58 % of the non-core
-- edges: it branches off the unlocked starting core and then off its own new (unlocked) streets. A town never extends
-- or branches off a `roadDevelopmentLocked` street, but houses still fill it (findings towns.md "Locked town streets").
-- `roadDevelopmentLocked` can only be set when an edge is built: no command or proposal field changes it in place
-- (SimpleStreetProposal has only add / remove lists; the base Player-owned tool's StreetEdgeNodeModifier is a GUI
-- construction action, api/type.d.tl:2761 "To modify a street, you need to remove all appropriate entities and add
-- them"). So the driver rebuilds a game street between its SAME two nodes with the same component, locked (move_it's
-- buildEdgeAbsTangentProposal pattern: edgesToRemove + edgesToAdd, the end nodes' configs re-pointed), never a node.
--
-- Which edges (M.classify): unlocked town-template streets of the town that are not the player's (PLAYER_OWNED) and not
-- the mod's (built this session and unlocked: a legacy town's or a valve stub); `core` when they were there at the
-- town's first sight before its first frame, else `game`. Edges with buildings are locked too (WITH_HOUSES: the
-- console probe of 2026-10-15 showed houses and lots survive a locked rebuild). Skipped: edge objects (stops,
-- signals), an edge or node owned by a construction (a station, a depot: inConstruction), bridges and tunnels, loops,
-- very short edges, edges seen for less than SETTLE_S (the game may still be building there), edges refused
-- EDGE_FAILS times, and the open valves' zones. Dead-end tips first, then game before core, then the outer ones.
--
-- Valves: a few unlocked places the game may branch from, the rest locked. Per town M.wantValves (organic styles
-- VALVES.organic, grids VALVES.grid; + 1 for a big town; + the stall guard's extra ones), each an anchor edge that stays
-- unlocked (a game or core street, or a mod street built unlocked: a stub) and a zone of VALVE_R around it where the
-- game's new streets stay unlocked too. The anchor is picked by M.valveScore: the §62 land lean toward its heading
-- from the centre, the §63 skeleton's arms, outward (near the town's rim), a dead-end tip; never toward dense forest
-- (ot_skeleton.clearAhead under its CLEAR_M at the probe point VALVE_AHEAD_M out, or a dense cell there), water or a
-- neighbour's gap (ot_gap.held), and away from headings closed lately. A valve closes after VALVE_EDGES new game
-- streets in its zone, after VALVE_CHECKS checks, or when its anchor is gone; its houseless streets are then locked like
-- any other and the next valve opens elsewhere (rotation). No anchor good enough: the next mod build leaves one
-- outward tip unlocked in the best heading (M.pickStub), which becomes the valve.
-- Every loop runs over a capped list (SCAN_MAX edges, the open valves, the batch).
-- Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local SK = ug_require "square_organic_towns::/organic_towns/ot_skeleton.lua"
local LAND = ug_require "square_organic_towns::/organic_towns/ot_land.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"

local M = {}

local pi, cos, sin, atan2, abs = math.pi, math.cos, math.sin, math.atan2 or math.atan, math.abs

M.ON = true
M.WITH_HOUSES = true      -- edges with buildings are rebuilt too (console probe 2026-10-15: houses and lots survive;
                          -- the pre-check still refuses a rebuild that lists buildings or costs over COST_MAX)
M.CORE = true             -- the starting core's houseless edges are locked too (dead-end tips first)
M.SETTLE_S = 3            -- real s an edge must be known before it is rebuilt (the game may still be building there;
                          -- a check stamps it, a later check of the town locks it)
M.MIN_LEN = 8             -- m: shorter edges are left alone (junction stubs)
M.BATCH = 8               -- edges per lock proposal (one proposal per job at most)
M.TOWN_MAX = 600          -- edges locked per town and session at most
M.MAP_MAX = 6000          -- ... and per session
M.EDGE_FAILS = 2          -- an edge refused this often is left alone for the session
M.BACKOFF_S = 60          -- a refused batch: the town's next lock this much later, doubling per refusal in a row ...
M.BACKOFF_MAX_S = 1800    -- ... at most this
M.TOWN_FAILS = 8          -- refusals in a row: no more locks in this town this session
M.COST_MAX = 250000       -- pre-check cost per edge above this: refused (a rebuild that would demolish something)
M.SCAN_MAX = 6000         -- edges classified per check at most (loop cap)
M.WAIT_S = 20             -- a lock proposal's callback that never comes
-- (§68, 2026-10-15: the rebuild is paid like every mod build, ctx.player set, and on top of the game's own street: about
-- twice the town's street costs. ctx.player unset might build for free but was never tried (the 2026-10-11 crash bisect,
-- findings towns.md). So the driver books the rebuild's charge back: the player's balance before the send minus after the
-- callback, at most the build's cost, booked as street construction income (makeJournalBookAssetCmd, as Full Refund and
-- Stress Test do from a GUI script). A balance change that is not the build's (other spending in the same frames) is
-- left alone: no refund unless it lies within REFUND_TOL of the cost. Seed `a` run 2026-10-15 (session
-- `2026-10-15_1936_sqot-glprobe`): with the Quick sim's months passing, 162 of 198 balance changes were above 1.5 x the
-- cost (other spending in the same frames) and only 34 refunded (0.40 M of 1.66 M). A change above the cost still
-- covers the charge, so there is no upper bound now: the refund is the cost itself, never more. Since 2026-10-17 the
-- same rule refunds every mod build, not only the lock's: ot_driver Driver:refundBuild.)
M.REFUND = true
M.REFUND_TOL = { 0.5, math.huge }   -- the balance change / the build's cost must lie within this
M.REFUND_MAX = 1000000000     -- one booking at most (findings debugging.md: Stress Test's MAX_BOOKING)

M.VALVES = { organic = 2, grid = 1 }   -- valves per town by grower ...
M.VALVE_BIG_R = 450       -- ... + 1 from this extent radius (m) ...
M.VALVE_MAX = 3           -- ... at most this many (the stall guard's extra ones on top)
M.VALVE_STALL_MAX = 2     -- extra valves the stall guard opens at most (one per fire)
M.VALVE_R = 300           -- m: the game's new streets within this of the anchor stay unlocked while the valve is open
M.VALVE_EDGES = { organic = 14, grid = 8 }   -- new game streets in the zone after which the valve closes
M.VALVE_CHECKS = 24       -- checks a valve stays open at most
M.VALVE_SEP = math.rad(60)   -- two valves at least this far apart (heading from the centre)
M.VALVE_REST = math.rad(45)  -- headings within this of a valve closed lately count as rested ...
M.VALVE_REST_N = 3           -- ... the last this many closed valves
M.VALVE_MIN = 0           -- an anchor scoring under this is no valve (a stub is asked for instead)
M.VALVE_AHEAD_M = 150     -- m: the probe point beyond the anchor (forest, water, neighbours)
M.VALVE_OUT_MIN = 0.5     -- an anchor nearer the centre than this x the extent radius is no valve
M.W = { lean = 1.0, arm = 0.6, out = 0.5, tip = 0.3, rest = 1.2 }   -- (rest: a closed heading loses even a full lean)
M.STUB_TURN = math.rad(40)   -- a stub's heading within this of the wanted one
M.STUB_OUT = 0.6          -- ... its midpoint at least this x the extent radius out

local function wrap(a)
	a = a % (2 * pi)
	if a > pi then a = a - 2 * pi end
	return a
end

local function deg(a) return math.floor(math.deg(a) % 360 + 0.5) % 360 end
M.deg = deg

local function isTownTemplate(path)
	return type(path) == "string" and path:find("town_", 1, true) ~= nil and path:find("one_way", 1, true) == nil
end
M.isTownTemplate = isTownTemplate

local function mid(ed) return (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2 end
local function len(ed) return G.dist(ed.p0[1], ed.p0[2], ed.p1[1], ed.p1[2]) end
M.mid, M.len = mid, len

--- What an edge is to the lock and why it is left alone. ed = an edge record (ot_engine edgeTable: id, n0, n1, p0, p1,
--- template, objects, owned, inConstruction, locked, etype, plus glocked = locked by us). c = { own = {id = true} (the
--- mod's this session), core = {id = true} or nil, built = {id = buildings} or nil, bad = {id = true} or nil,
--- seen = {id = first seen us} or nil, nowUs, valve = function(ed) -> valve or nil, withHouses }. Returns kind ("player"
--- | "other" | "glocked" | "mod" | "core" | "game") and skip (nil: lock it; else the reason).
function M.classify(ed, c)
	c = c or {}
	if ed == nil or ed.p0 == nil or ed.p1 == nil then return "other", "bad" end
	if ed.owned then return "player", "player" end
	if not isTownTemplate(ed.template) then return "other", "template" end
	if ed.glocked then return "glocked", "locked" end
	if ed.locked then return "mod", "locked" end
	if c.own and c.own[ed.id] then return "mod", "mod" end
	local kind = (c.core and c.core[ed.id]) and "core" or "game"
	if kind == "core" and not M.CORE then return kind, "core" end
	local withHouses = c.withHouses
	if withHouses == nil then withHouses = M.WITH_HOUSES end
	if not withHouses and c.built and (c.built[ed.id] or 0) > 0 then return kind, "houses" end
	if (ed.objects or 0) > 0 then return kind, "objects" end
	if ed.inConstruction then return kind, "construction" end
	if ed.etype ~= nil and ed.etype ~= "normal" then return kind, tostring(ed.etype) end
	if ed.n0 == ed.n1 then return kind, "loop" end
	local l = len(ed)
	if l ~= l or l < M.MIN_LEN then return kind, "short" end
	if c.bad and c.bad[ed.id] then return kind, "bad" end
	if c.valve and c.valve(ed) then return kind, "valve" end
	-- (§69 steer towns, ot_lockpol.gameLock: only rim streets facing something unwanted, or beyond the outline while
	-- young; the rest stays open, the game's own texture)
	if c.steer then
		local lockWhy, openWhy = c.steer(ed)
		if lockWhy == nil then return kind, openWhy == "inside" and "steerIn" or "steerOk" end
	end
	local t0 = c.seen and c.seen[ed.id]
	if t0 == nil or c.nowUs == nil or c.nowUs - t0 < M.SETTLE_S * 1e6 then return kind, "settle" end
	return kind, nil
end

--- The edges to lock this check: edges = the town's edge records, inTown = {id = true} (its lot edges) or nil (all), c =
--- M.classify's context, o = { cx, cy, max }. Returns list (at most o.max or BATCH: { id, kind, len, tip }), tally =
--- { [kind or reason] = n, game = unlocked game edges, open = unlocked non-mod edges }.
function M.queue(edges, inTown, c, o)
	o = o or {}
	local deg = {}
	local n = math.min(#(edges or {}), M.SCAN_MAX)
	for i = 1, n do
		local ed = edges[i]
		if ed.n0 then deg[ed.n0] = (deg[ed.n0] or 0) + 1 end
		if ed.n1 then deg[ed.n1] = (deg[ed.n1] or 0) + 1 end
	end
	local list, tally = {}, { open = 0, glocked = 0 }
	for i = 1, n do
		local ed = edges[i]
		if inTown == nil or inTown[ed.id] then
			local kind, skip = M.classify(ed, c)
			if kind == "game" or kind == "core" then tally.open = tally.open + 1 end
			-- (locked streets by whose: glocked / mod; the others by their skip reason, or their kind when queued)
			local key = (skip == nil or skip == "locked") and kind or skip
			tally[key] = (tally[key] or 0) + 1
			if skip == nil then
				local mx, my = mid(ed)
				local tip = (deg[ed.n0] or 0) == 1 or (deg[ed.n1] or 0) == 1
				list[#list + 1] = { id = ed.id, kind = kind, len = len(ed), tip = tip, ed = ed,
					d = o.cx and G.dist(o.cx, o.cy, mx, my) or 0 }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.tip ~= b.tip then return a.tip end
		if a.kind ~= b.kind then return a.kind == "game" end
		if abs(a.d - b.d) > 1e-6 then return a.d > b.d end
		return a.id < b.id
	end)
	local max = o.max or M.BATCH
	while #list > max do list[#list] = nil end
	return list, tally
end

--- Valves a town wants: grower ("organic" | other), extR (m), extra (the stall guard's). 0 with no grower known.
function M.wantValves(grower, extR, extra)
	if grower == nil then return 0 end
	local n = M.VALVES[grower] or M.VALVES.grid
	if (tonumber(extR) or 0) >= M.VALVE_BIG_R then n = n + 1 end
	n = math.min(M.VALVE_MAX, n)
	return n + math.max(0, math.min(M.VALVE_STALL_MAX, tonumber(extra) or 0))
end

--- The quota of new game streets a valve of this grower lets in before it closes.
function M.valveQuota(grower)
	return M.VALVE_EDGES[grower] or M.VALVE_EDGES.grid
end

local function restedBy(a, rest)
	for i = 1, math.min(#(rest or {}), M.VALVE_REST_N) do
		local r = rest[#rest - i + 1]
		if abs(wrap(a - r)) <= M.VALVE_REST then return true end
	end
	return false
end

--- Score of a valve anchor at (mx, my) (an edge midpoint; tip: a dead end at it). ctx = { cx, cy, extR, field (ot_land),
--- fg (ot_forest grid), gaps (ot_gap), arms = {rad} or nil, wet = function(x, y) or nil, rest = {rad} (closed lately) }.
--- Returns score, why ("land" | "arm" | "open"), heading; or nil, reject ("centre" | "forest" | "water" | "neighbour").
--- §71: only woods of at least ot_forest.WOOD_MIN_HA count as forest (M.SMALL_WOOD; ctx.small, a number when set,
--- counts the anchors small woods alone would have rejected).
M.SMALL_WOOD = true
local function bigWood(fg, x, y) return FO.bigWoodAt(fg, x, y) end
local function woodAhead(fg, mx, my, ux, uy, px, py, isWood)
	isWood = isWood or SK.denseAt
	if isWood(fg, px, py) then return true end
	return SK.clearAhead(fg, mx + ux * 30, my + uy * 30, ux, uy, isWood) < SK.CLEAR_M
end
function M.valveScore(mx, my, tip, ctx)
	local cx, cy = ctx.cx or 0, ctx.cy or 0
	local dx, dy = mx - cx, my - cy
	local d = math.sqrt(dx * dx + dy * dy)
	local extR = math.max(100, tonumber(ctx.extR) or 0)
	if d ~= d or d < M.VALVE_OUT_MIN * extR then return nil, "centre" end
	local a = atan2(dy, dx)
	local ux, uy = dx / d, dy / d
	local px, py = mx + ux * M.VALVE_AHEAD_M, my + uy * M.VALVE_AHEAD_M
	if ctx.fg ~= nil then
		if woodAhead(ctx.fg, mx, my, ux, uy, px, py, M.SMALL_WOOD and bigWood or nil) then return nil, "forest" end
		if M.SMALL_WOOD and type(ctx.small) == "number" and woodAhead(ctx.fg, mx, my, ux, uy, px, py, nil) then
			ctx.small = ctx.small + 1
		end
	end
	if ctx.wet and (ctx.wet(px, py) or ctx.wet((mx + px) / 2, (my + py) / 2)) then return nil, "water" end
	if ctx.gaps ~= nil and GP.held(ctx.gaps, { { px, py } }, "small") ~= nil then return nil, "neighbour" end
	local lean = LAND.at(ctx.field, a)
	local arm = 0
	for _, aa in ipairs(ctx.arms or {}) do
		local c = cos(wrap(a - aa))
		if c > 0 then arm = math.max(arm, c ^ 4) end
	end
	local out = math.min(1.3, d / extR)
	local s = M.W.lean * lean + M.W.arm * arm + M.W.out * out + (tip and M.W.tip or 0)
	if restedBy(a, ctx.rest) then s = s - M.W.rest end
	local why = "open"
	if M.W.arm * arm > M.W.lean * abs(lean) and arm > 0.3 then why = "arm" elseif lean > 0.1 then why = "land" end
	return s, why, a
end

--- New valves: cands = { { id, mx, my, tip, kind } } (unlocked anchors), open = the open valves ({ a = heading }), want =
--- how many in all. Returns picks { { id, x, y, a, score, why, kind } } (best first, VALVE_SEP apart from each other
--- and the open ones), best reject tally { [why] = n }.
function M.pickValves(cands, ctx, open, want)
	local need = (want or 0) - #(open or {})
	local picks, rej = {}, {}
	if need <= 0 then return picks, rej end
	local scored = {}
	for i = 1, math.min(#(cands or {}), M.SCAN_MAX) do
		local c = cands[i]
		local s, why, a = M.valveScore(c.mx, c.my, c.tip, ctx)
		if s == nil then rej[why] = (rej[why] or 0) + 1
		elseif s < M.VALVE_MIN then rej.low = (rej.low or 0) + 1
		else scored[#scored + 1] = { id = c.id, x = c.mx, y = c.my, a = a, score = s, why = why, kind = c.kind } end
	end
	table.sort(scored, function(p, q)
		if abs(p.score - q.score) > 1e-9 then return p.score > q.score end
		return (p.id or 0) < (q.id or 0)
	end)
	local function apart(a)
		for _, v in ipairs(open or {}) do if abs(wrap(a - v.a)) < M.VALVE_SEP then return false end end
		for _, v in ipairs(picks) do if abs(wrap(a - v.a)) < M.VALVE_SEP then return false end end
		return true
	end
	for _, c in ipairs(scored) do
		if #picks >= need then break end
		if apart(c.a) then picks[#picks + 1] = c end
	end
	return picks, rej
end

--- The heading a valve stub should take when no anchor is good enough: of STUB_DIRS headings around the centre, the
--- best scoring point on the town's rim (M.valveScore as a tip), VALVE_SEP from the open valves. Returns a, score or nil.
M.STUB_DIRS = 16
function M.stubHeading(ctx, open)
	local cx, cy = ctx.cx or 0, ctx.cy or 0
	local r = math.max(100, tonumber(ctx.extR) or 0)
	local best, bestS = nil, nil
	for k = 0, M.STUB_DIRS - 1 do
		local a = wrap(k * 2 * pi / M.STUB_DIRS)
		local ok = true
		for _, v in ipairs(open or {}) do if abs(wrap(a - v.a)) < M.VALVE_SEP then ok = false end end
		if ok then
			local s = M.valveScore(cx + cos(a) * r, cy + sin(a) * r, true, ctx)
			if s and s >= M.VALVE_MIN and (bestS == nil or s > bestS + 1e-9) then best, bestS = a, s end
		end
	end
	return best, bestS
end

--- Is (x, y) in valve v's zone?
function M.inZone(v, x, y)
	return v ~= nil and G.dist(v.x, v.y, x, y) <= M.VALVE_R
end

--- One check of an open valve: v = { x, y, a, quota, checks, n, z0 = {id = true} (the zone's edges at its opening) },
--- zoneIds = the unlocked non-mod edges in its zone now ({ id }), anchorOk = its anchor still stands. Updates v.n (new
--- game streets since it opened) and v.checks; returns the close reason ("quota" | "age" | "gone") or nil.
function M.valveCheck(v, zoneIds, anchorOk)
	v.checks = (v.checks or 0) + 1
	local n = 0
	for i = 1, math.min(#(zoneIds or {}), M.SCAN_MAX) do
		if not (v.z0 and v.z0[zoneIds[i]]) then n = n + 1 end
	end
	v.n = math.max(v.n or 0, n)
	if not anchorOk then return "gone" end
	if v.n >= (v.quota or M.VALVE_EDGES.grid) then return "quota" end
	if v.checks >= M.VALVE_CHECKS then return "age" end
	return nil
end

--- A stub valve among a build's new edges: edges = the increment's edges ({ key, p0, p1, node0, node1, existing,
--- forestLane, bridge }), the wanted heading a, the centre and extent radius. Returns the key of an outward dead-end
--- edge within STUB_TURN of a (nearest the heading, then farthest out), or nil.
function M.pickStub(edges, a, cx, cy, extR)
	if a == nil or a ~= a then return nil end
	local degN = {}
	for i = 1, math.min(#(edges or {}), M.SCAN_MAX) do
		local e = edges[i]
		for _, nd in ipairs({ e.node0, e.node1 }) do if nd then degN[nd] = (degN[nd] or 0) + 1 end end
	end
	local best, bestD, bestOut = nil, nil, nil
	local r = math.max(100, tonumber(extR) or 0)
	for i = 1, math.min(#(edges or {}), M.SCAN_MAX) do
		local e = edges[i]
		if e.key ~= nil and not e.existing and not e.forestLane and not e.bridge and e.p0 and e.p1 then
			local tip = (e.node0 and e.node0 < 0 and degN[e.node0] == 1) or (e.node1 and e.node1 < 0 and degN[e.node1] == 1)
			local mx, my = mid(e)
			local d = G.dist(cx, cy, mx, my)
			if tip and d >= M.STUB_OUT * r then
				local off = abs(wrap(atan2(my - cy, mx - cx) - a))
				if off <= M.STUB_TURN and (best == nil or off < bestD - 1e-9 or (abs(off - bestD) <= 1e-9 and d > bestOut)) then
					best, bestD, bestOut = e.key, off, d
				end
			end
		end
	end
	return best
end

--- §69 tips: the outward dead ends of a steer town's build left unlocked as growth points (tip valves). edges = the
--- increment's edges, locked = { [key] = why } (the policy's locks: only a locked branch's tip qualifies), ctx = the
--- valve context (M.valveScore's: forest / water / neighbour ahead rejected; fg), cx, cy, extR, open = the open
--- valves ({ a }), max = how many may open. A tip's outer node must lie TIP_CLEAR_M (ot_skeleton CLEAR_M) or more from
--- dense forest (its fill would eat the woods) and score at least VALVE_MIN. Returns { { key, x, y, a, score, why } }
--- (best first, VALVE_SEP apart), the reject tally, and the count of tips small woods alone (§71, M.SMALL_WOOD) would
--- have rejected.
M.TIP_OUT = 0.7           -- a tip's outer node at least this x the extent radius out
M.TIP_WHY = { out = true, rim = true, arm = true }   -- the policy's reasons whose dead ends may become tips
M.TIP_CORRIDOR = true     -- §70: no tip in a narrow clearing between woods (ot_skeleton.corridorAt; BUILT tipRej=corridor:n)
function M.pickTips(edges, locked, ctx, cx, cy, extR, open, max)
	local picks, rej = {}, {}
	if (max or 0) <= 0 then return picks, rej, 0 end
	local isWood = M.SMALL_WOOD and bigWood or nil
	local small = 0
	local degN = {}
	local n = math.min(#(edges or {}), M.SCAN_MAX)
	for i = 1, n do
		local e = edges[i]
		for _, nd in ipairs({ e.node0, e.node1 }) do if nd then degN[nd] = (degN[nd] or 0) + 1 end end
	end
	local r = math.max(100, tonumber(extR) or 0)
	local cands = {}
	for i = 1, n do
		local e = edges[i]
		local why = e.key ~= nil and locked and locked[e.key]
		if why and M.TIP_WHY[why] and not e.existing and not e.forestLane and not e.bridge and e.p0 and e.p1 then
			-- (the dead end: a new node with this one street)
			local tipNode, tx, ty
			if e.node1 and e.node1 < 0 and degN[e.node1] == 1 then tipNode, tx, ty = e.node1, e.p1[1], e.p1[2]
			elseif e.node0 and e.node0 < 0 and degN[e.node0] == 1 then tipNode, tx, ty = e.node0, e.p0[1], e.p0[2] end
			if tipNode then
				local d = G.dist(cx, cy, tx, ty)
				if d < M.TIP_OUT * r then rej.inner = (rej.inner or 0) + 1
				elseif ctx.fg ~= nil and ctx.fg.cover ~= nil and SK.pointClear(ctx.fg, tx, ty, isWood) < SK.CLEAR_M then
					rej.forest = (rej.forest or 0) + 1
				elseif M.TIP_CORRIDOR and ctx.fg ~= nil and d > 1e-6
					and SK.corridorAt(ctx.fg, tx, ty, -(ty - cy) / d, (tx - cx) / d, isWood) ~= nil then
					-- (§70: a tip in a narrow clearing between woods: the game's fill from it would run into them)
					rej.corridor = (rej.corridor or 0) + 1
				else
					-- (§71: small woods alone would have rejected it)
					local vc = { cx = cx, cy = cy, extR = r, field = ctx.field, fg = ctx.fg,
						gaps = ctx.gaps, arms = ctx.arms, wet = ctx.wet, rest = ctx.rest, small = 0 }
					if isWood and ctx.fg ~= nil and ctx.fg.cover ~= nil and (SK.pointClear(ctx.fg, tx, ty) < SK.CLEAR_M
						or (M.TIP_CORRIDOR and d > 1e-6 and SK.corridorAt(ctx.fg, tx, ty, -(ty - cy) / d, (tx - cx) / d) ~= nil)) then
						vc.small = 1
					end
					local s, w, a = M.valveScore(tx, ty, true, vc)
					if s ~= nil and vc.small > 0 then small = small + 1 end
					if s == nil then rej[w] = (rej[w] or 0) + 1
					elseif s < M.VALVE_MIN then rej.low = (rej.low or 0) + 1
					else cands[#cands + 1] = { key = e.key, x = tx, y = ty, a = a, score = s, why = w } end
				end
			end
		end
	end
	table.sort(cands, function(p, q)
		if abs(p.score - q.score) > 1e-9 then return p.score > q.score end
		return tostring(p.key) < tostring(q.key)
	end)
	for _, c in ipairs(cands) do
		if #picks >= max then break end
		local ok = true
		for _, v in ipairs(open or {}) do if abs(wrap(c.a - v.a)) < M.VALVE_SEP then ok = false end end
		for _, v in ipairs(picks) do if abs(wrap(c.a - v.a)) < M.VALVE_SEP then ok = false end end
		if ok then picks[#picks + 1] = c else rej.sep = (rej.sep or 0) + 1 end
	end
	return picks, rej, small
end

--- The town's lock backoff after a batch: st = { fails, nextUs } (updated in place). ok = the batch built. Returns the
--- pause in s (0 after a success) and whether the town is off for the session (TOWN_FAILS refusals in a row).
function M.backoff(st, nowUs, ok)
	if ok then
		st.fails = 0
		st.nextUs = nowUs
		return 0, false
	end
	st.fails = (st.fails or 0) + 1
	local s = math.min(M.BACKOFF_MAX_S, M.BACKOFF_S * 2 ^ (st.fails - 1))
	st.nextUs = nowUs + s * 1e6
	st.off = st.fails >= M.TOWN_FAILS or nil
	return s, st.off == true
end

--- `valves=` text: "<n>:<deg><kind initial>/..." ("0" without).
function M.valvesText(list)
	local parts = {}
	for i = 1, math.min(#(list or {}), 8) do
		local v = list[i]
		parts[#parts + 1] = string.format("%d%s", deg(v.a or 0), (v.kind or "g"):sub(1, 1))
	end
	if #parts == 0 then return "0" end
	return #parts .. ":" .. table.concat(parts, "/")
end

--- The refund of a mod build (§68; every build since 2026-10-17): bal0 = the player's balance at the send, bal1 = after the callback (nil: infinite
--- money, unknown), cost = the build's cost (the result's, else the pre-check's). Returns amount (0 = none), why.
function M.refund(bal0, bal1, cost)
	if not M.REFUND then return 0, "off" end
	bal0, bal1, cost = tonumber(bal0), tonumber(bal1), tonumber(cost)
	if bal0 == nil or bal1 == nil or bal0 ~= bal0 or bal1 ~= bal1 then return 0, "noBalance" end
	if cost == nil or cost ~= cost or cost <= 0 or cost == math.huge then return 0, "noCost" end
	local paid = bal0 - bal1
	if paid <= 0 then return 0, "notCharged" end
	if paid < cost * M.REFUND_TOL[1] or paid > cost * M.REFUND_TOL[2] then return 0, "mismatch" end
	return math.floor(math.min(paid, cost, M.REFUND_MAX) + 0.5), "paid"
end

return M
