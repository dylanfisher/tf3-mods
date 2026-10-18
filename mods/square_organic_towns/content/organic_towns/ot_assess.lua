-- Organic Towns: does a town need more streets, and when to look at which town (pure).
--
-- The town's extent comes from its building positions (the town entity's bounding box held only 28 % of its
-- buildings, docs/findings.md "Organic Towns probe"). Lots per street edge come from getSegment2ParcelData + the
-- buildings' parcels; edges without parcels yet (our increments before the town adopts them, HANDOFF "Adoption")
-- get estimated virtual lots.
--
-- Needs room (PLAN.md 6.2 "Trigger", first in-game run 2026-10-11): a fresh town sits at ~98 % of its capacity
-- target with ~half of its parcels empty (Dickinson: 457 built of 984 lots, free 527), and those gaps stay empty:
-- the developer meets its target and, when the target rises, extends streets rather than filling them (Beccles:
-- sizeFactors 1 -> 2 doubled the buildings with +76 % streets). So free lots in general are no measure of room.
-- What the developer does use is open frontage: virtual lots on our unadopted streets and free lots on edges
-- that are still mostly empty (filled below OPEN_FILL). A town needs room when that open frontage falls under the
-- lookahead threshold; a hungry town (capacity below CAP_HUNGRY of its target: the target just rose) wants more
-- of it, a town well over its target (shrinking) gets none.
-- Growth demand (real map + Simulate natural growth, 2026-10-12): at the game's own growth pace the town developer
-- adds its own streets as the capacity target rises (Aldershot 58 -> 133 edges, free lots 711 -> 1383, open frontage
-- 426 -> 768 vs a need of 83 -> 264), so open frontage never ran low and the mod built nothing in 262 checks
-- (why=open). Room is no trigger for a growing town; its demand is. Each town keeps a session ledger of the size
-- factors it has been served up to (M.demand): the capacity the target gained since (Σ initial x Δ sizeFactor, so
-- the dose fill's initial capacity changes don't count), in street length at the town's own persons per metre (in
-- edges of the town's mean edge length for the log and the increment size), is the demand. A town with
-- DEMAND_MIN_EDGES of demand gets an increment (why=demand) unless the open frontage on its own streets (locked
-- edges and this session's builds) has reached the lead (why=ahead: the houses haven't caught up, nothing more is
-- built ahead of them). The lead matches the game's own open frontage (OWN_MATCH: our streets get as good a chance
-- at the houses as the game's), at least the lookahead threshold, at most OWN_CAP x the built lots. A build serves
-- its length's worth of capacity (M.served); demand beyond DEMAND_BANK increments is dropped (no burst after a long
-- hold). The first sight starts the ledger at the current size factors, so a loaded save's growth so far is no
-- demand. Room (why=low) still triggers below DEMAND_MIN_EDGES of demand.
-- The scheduler is a round-robin with per-town cooldowns in real time.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

-- Lookahead param (1 small, 2 medium, 3 large): free lots to keep ahead of demand, and increment size.
M.LOOKAHEAD = {
	{ share = 0.10, min = 12, maxEdges = 12 },
	{ share = 0.20, min = 24, maxEdges = 18 },
	{ share = 0.35, min = 40, maxEdges = 24 },
}
M.VIRTUAL_LOT_M = 12      -- an edge without parcels yet: one future lot per 12 m (probe J: 7-22 per edge)
M.INNER_WEIGHT = 0.5      -- free lots inside half the town radius count this much
M.OPEN_FILL = 0.25        -- an edge whose lots are filled below this share is open frontage
M.GAP_WEIGHT = 0          -- free lots on fuller edges (gaps the developer leaves empty) count this much
M.CAP_HUNGRY = 0.9        -- capacity below this share of the target: the town is about to build
M.HUNGRY_FACTOR = 1.5     -- ... so it wants this much more open frontage
M.CAP_OVER = 1.1          -- capacity above this share of the target: shrinking, no new streets
M.EXTENT_QUANTILE = 0.9
M.DEMAND = true           -- the growth-demand trigger (false: room only, as before 2026-10-12)
M.DEMAND_MIN_EDGES = 4    -- demand (edges) that starts an increment (vanilla added ~5 edges per check in the run)
M.DEMAND_BANK = 2         -- demand kept at most this many increments (maxEdges) deep
M.PER_M_MIN = 0.04        -- persons per metre of town street used for the demand: the town's own, clamped (run:
M.PER_M_MAX = 1.0         -- ~0.16 at the start, rising as the houses get denser)
M.OWN_LEAD = 1.25         -- open lots on the town's own streets allowed: this x the lookahead threshold, or
M.OWN_MATCH = 2.0         -- ... this x the open frontage on the game's streets when more (the game keeps ~0.7-1 x
                          -- its built lots open: our streets get an equal chance at its houses, no more) ...
M.OWN_CAP = 0.35          -- ... but at most this x the town's built lots (no long empty ladders; 0.5 until 2026-10-13:
                          -- 4-17 km of own streets stood empty in the real map run 2026-10-13_0232_sqot-dev)
-- Fast growers (2026-10-13, real map run 2026-10-13_0018_top-up-598153: the bank sat at its cap of 2 x 18 edges in
-- every check of the fast towns, and they got ~7 % of their new streets from the mod: Bexley 47 -> 462 edges, 38 ours
-- in 3 builds). The raw backlog (unserved capacity before the bank cap, in edges) over the normal bank gives the town's
-- fast factor (1..FAST_MAX, smoothed: it decays by FAST_DECAY a check); the bank holds DEMAND_BANK x fast increments
-- (2-6) and a demand increment may plan up to maxEdges x (1 + (fast - 1) x FAST_INC) edges (18 -> 36). The housed
-- front / arm fill / ahead rules are unchanged, so no empty streets run ahead of the houses.
M.FAST_MAX = 3
-- (2026-10-13: the dev simulation now grows towns in 4-year chunks; a fast town's chunk exceeded the 2 x 3 x 18 = 108
-- edge bank and was thrown away: the bank's own factor runs to BANK_FAST_MAX, i.e. up to 2 x 5 x 18 = 180 edges, while
-- the increments stay at most maxEdges x (1 + (FAST_MAX - 1) x FAST_INC); housed front / ahead unchanged)
M.BANK_FAST_MAX = 5
M.FAST_DECAY = 0.8
M.FAST_INC = 0.5
-- Less frontage per unit of growth (2026-10-14, the vanilla baseline: 92 street edges per 1000 persons against 63, 54 %
-- of the lots free): the demand is counted at DENSIFY x the town's own persons per metre (the town gets denser
-- instead of wider), and a town whose lots are more than FREE_SHARE free asks less (down to FREE_MIN at FREE_FULL free).
M.DENSIFY = 1.2
-- (2026-10-14 late, the same-seed comparison against true vanilla, session 2026-10-14_0119_sqot: free lots still 58 %
-- against vanilla's 52 %, 2.9 persons per building against 6.4, 7.6 m of street per person against 3.8. The brake above
-- (x0.35 at 40-65 % free) let the mod lay frontage while most of the town's lots stood empty.) Now the increment follows
-- the town's actual free lots around an aim near vanilla's (FREE_AIM 0.5): full demand up to FREE_AIM - FREE_BAND_LO
-- free, falling to FREE_MIN at FREE_AIM + FREE_BAND_HI; and its persons per building (PB_AIM, the target of ~4.5): a
-- sparse town asks less, pb / PB_AIM down to PB_K_MIN. The product is at least K_MIN. CHECK `freeK= pbK= demK=`.
-- (2026-10-14, run 2026-10-14_0302_sqot-sqrl on the same seed: the brake held 235 of 279 checks (`why=free`), the mod
-- built 122 demand edges against 1032 (11 % of the edges against 24 %), the towns came out vanilla-dense (6.3 persons
-- per building against vanilla's 6.4) but round and alike, no district or Works. Three fixes:
-- (1) MATURITY: the brake phases in with the town's size in persons (caps.actual, which the game's target sets and the
--     brake can't move, unlike the building count): none below MAT_LO, full from MAT_HI. A young town branches out
--     as before the density round; a grown one builds up. MAT_LO ~ 600 of the young town's small houses (3 persons).
-- (2) pbK counted persons per BUILT LOT (a building spans 2-3 lots: Heywood 162 buildings on 387 lots), so even a
--     vanilla-dense town asked x0.6. It now takes persons per building (M.demand's `buildings`).
-- (3) FREE_AIM 0.5 was vanilla's 0° grid; the game's own towns at the EU 35° angle keep ~60 % of their lots free
--     (Ellesmere Port 76 %, Blackwater 69 % with 0-5 % mod streets), so the old aim held every town at FREE_MIN.)
M.FREE_AIM = 0.55
M.FREE_BAND_LO = 0.05
M.FREE_BAND_HI = 0.15
M.FREE_MIN = 0.12
M.PB_AIM = 4.5
M.PB_K_MIN = 0.5
M.K_MIN = 0.06
M.MAT_LO = 1800           -- persons: a town this small is young (no brake, no free-lot hold)
M.MAT_HI = 3600           -- persons: from this size the brake is full
M.YOUNG_ROOM = 0.5        -- a young town's free-lot hold starts this much higher (x (1 - maturity)): never at 0
-- (and the room trigger: a town with more than FREE_AIM + FREE_ROOM free lots never builds for room, why=free)
M.FREE_ROOM = 0.05
-- (2026-10-14, run 2026-10-14_0502_sqot: `why=free` never fired and the grown towns stayed at 3.08 persons per building:
-- the free-lot hold above only applies under DEMAND_MIN_EDGES of demand and grown towns always had demand (the game's
-- target kept rising), while demK at maturity 1 was still 0.55-0.9 x 0.6-1. The MATURE hold works while demand exists:
-- (a) a town with more than FREE_AIM of its lots free asks at most 1 - mat x (1 - MATURE_DEMK) of its demand (0.18 at
--     maturity 1), phased in from FREE_AIM - FREE_BAND_LO free; (b) from MATURE_HOLD_MAT maturity no demand build at all while more than MATURE_HOLD_FREE (+ (1 -
--     mat) x YOUNG_ROOM, so 0.60 at maturity 1 and 0.85 at 0.5) of its lots are free (why=mature; the demand stays in
--     the bank). A young town (mat 0) is untouched. Before 1950 the game has town buildings of levels 1-2 only, so a
--     grown town gets denser by filling its free lots, not by taller buildings.)
M.MATURE_DEMK = 0.18
M.MATURE_HOLD_MAT = 0.5
M.MATURE_HOLD_FREE = 0.60
M.MORE_MIN_EDGES = 8      -- demand left after a demand build: the town is checked again soon (scheduler "more")

--- Extent of a point cloud { {x, y}, ... }: centre (mean), r (EXTENT_QUANTILE of the distances), rMax, n.
--- nil for no points.
function M.extent(points)
	local n = #points
	if n == 0 then return nil end
	local sx, sy = 0, 0
	for _, p in ipairs(points) do sx, sy = sx + p[1], sy + p[2] end
	local cx, cy = sx / n, sy / n
	local d = {}
	for i, p in ipairs(points) do d[i] = G.dist(cx, cy, p[1], p[2]) end
	table.sort(d)
	local q = d[math.max(1, math.min(n, math.floor(n * M.EXTENT_QUANTILE + 0.5)))]
	return { cx = cx, cy = cy, r = q, rMax = d[n], n = n }
end

--- Lots on a town's streets. edges = { { id, mx, my (midpoint), len, parcels = count or nil (nil: the edge
--- is not in the parcel map yet), built = count, town = bool (a town street template; only those get a
--- virtual estimate), own = bool (a street the mod built: locked, or built this session) } }; ext = M.extent result. Returns { free, built, total, virtual, room (every free lot,
--- inner ones weighted, + virtual), open (open frontage: free lots on edges filled below OPEN_FILL, inner ones
--- weighted, + virtual), gaps (free lots on fuller edges), openEdges (edges counted as open frontage), edges,
--- withParcels, unparcelled, ownOpen (open frontage on own edges, unweighted), ownEdges, length (m) }.
function M.lots(edges, ext)
	local out = { free = 0, built = 0, total = 0, virtual = 0, room = 0, open = 0, gaps = 0, openEdges = 0,
		edges = #edges, withParcels = 0, unparcelled = 0, ownOpen = 0, ownEdges = 0, length = 0 }
	local inner = ext and ext.r * 0.5 or 0
	for _, e in ipairs(edges) do
		local w = 1
		if ext and G.dist(ext.cx, ext.cy, e.mx, e.my) < inner then w = M.INNER_WEIGHT end
		local built = e.built or 0
		if e.own then out.ownEdges = out.ownEdges + 1 end
		if e.town ~= false then out.length = out.length + (e.len or 0) end
		if e.parcels ~= nil then
			out.withParcels = out.withParcels + 1
			local free = math.max(0, e.parcels - built)
			out.total = out.total + e.parcels
			out.built = out.built + built
			out.free = out.free + free
			out.room = out.room + free * w
			if e.parcels > 0 and built < e.parcels * M.OPEN_FILL then
				out.open = out.open + free * w
				out.openEdges = out.openEdges + 1
				if e.own then out.ownOpen = out.ownOpen + free end
			else
				out.gaps = out.gaps + free
				out.open = out.open + free * w * M.GAP_WEIGHT
			end
		elseif e.town then
			out.unparcelled = out.unparcelled + 1
			local v = math.floor((e.len or 0) / M.VIRTUAL_LOT_M)
			out.virtual = out.virtual + v
			out.room = out.room + v
			out.open = out.open + v
			out.built = out.built + built
			if e.own then out.ownOpen = out.ownOpen + v end
		end
	end
	return out
end

--- The free-lot factor of the demand for a town with `share` of its lots free (1 .. FREE_MIN, see M.FREE_AIM).
function M.freeK(share)
	local lo, hi = M.FREE_AIM - M.FREE_BAND_LO, M.FREE_AIM + M.FREE_BAND_HI
	if share == nil or share <= lo then return 1 end
	if share >= hi then return M.FREE_MIN end
	return 1 - (1 - M.FREE_MIN) * (share - lo) / (hi - lo)
end

--- A town's maturity (0 young .. 1 grown) from its persons (caps.actual): 0 up to MAT_LO, 1 from MAT_HI; 1 unknown.
function M.maturity(persons)
	if persons == nil then return 1 end
	if M.MAT_HI <= M.MAT_LO then return persons >= M.MAT_LO and 1 or 0 end
	return math.max(0, math.min(1, (persons - M.MAT_LO) / (M.MAT_HI - M.MAT_LO)))
end

--- The persons-per-building factor of the demand (1 at PB_AIM or more, pb / PB_AIM down to PB_K_MIN; 1 unknown).
function M.pbK(pb)
	if pb == nil or pb <= 0 then return 1 end
	return math.max(M.PB_K_MIN, math.min(1, pb / M.PB_AIM))
end

--- Growth demand of a town (see the header). ledger = the town's session table (created by the caller, {} at
--- first sight; filled here: sf = size factors served up to, or ref = target when the caps carry no size factors);
--- caps = ot_engine.townCaps result; lots = M.lots result; lookahead = 1..3; buildings = the town's building count
--- (persons per building for pbK; nil: per built lot). Returns { edges (demand in street
--- edges of the town's mean length), len (demand in metres), perM (persons per metre), perEdge (persons per mean
--- edge), cap (unserved person capacity), lead (own open lots allowed), ownOpen, raw (backlog in edges before the
--- bank cap), fast (1..FAST_MAX), incMax (edges a demand increment may plan) } or nil without caps. Drops demand
--- beyond DEMAND_BANK x fast increments from the ledger.
--- dz (2026-10-14, ot_character densify): { holdFree, demK } of a mature densify town (the mature hold's line and cap
--- harder), or nil. lockK (§65, 2026-10-15): the lead floor's factor for a young town whose mod streets are all locked
--- (ot_driver LOCK_LEAD_K; nil: 1; phased out with the maturity, so the mature brake still holds a grown town): the
--- game adds no frontage off them, so more of ours may wait ahead of the demand.
function M.demand(ledger, caps, lots, lookahead, buildings, dz, lockK)
	if caps == nil or not caps.target or not caps.actual then return nil end
	local la = M.LOOKAHEAD[lookahead or 2] or M.LOOKAHEAD[2]
	local nEdges = math.max(1, lots.edges or 0)
	local length = lots.length or 0
	local avgLen = length > 0 and length / nEdges or 100
	local perM = math.max(M.PER_M_MIN, math.min(M.PER_M_MAX, length > 0 and caps.actual / length or M.PER_M_MIN))
	perM = math.min(M.PER_M_MAX, perM * M.DENSIFY)
	local perEdge = perM * avgLen
	-- (the free-lot and persons-per-building brake: free / (free + built) lots of the whole town, persons per built lot)
	local free, built = lots.free or 0, lots.built or 0
	local freeShare = (free + built) > 0 and free / (free + built) or 0
	-- (persons per building when the caller knows the buildings, else per built lot as before 2026-10-14)
	local nb = (buildings and buildings > 0) and buildings or built
	local freeK, pbK = M.freeK(freeShare), M.pbK(nb > 0 and caps.actual / nb or nil)
	-- (the brake phases in with the town's maturity: a young town asks its whole demand)
	local mat = M.maturity(caps.actual)
	local demK = 1 - mat * (1 - math.max(M.K_MIN, freeK * pbK))
	-- (the mature cap, 2026-10-14: a grown town with more than FREE_AIM free lots fills them first)
	-- (phased in over the band below the aim, FREE_AIM - FREE_BAND_LO .. FREE_AIM: the offline model's grown town sat at
	-- 53-58 % free, right around the aim, and a hard step at the aim never acted)
	local matureCap = nil
	local lo = M.FREE_AIM - M.FREE_BAND_LO
	if mat > 0 and freeShare > lo then
		local capK = math.min(1, (freeShare - lo) / math.max(1e-6, M.FREE_BAND_LO))
		matureCap = 1 - mat * capK * (1 - ((dz and dz.demK) or M.MATURE_DEMK))
		if matureCap < demK then demK = matureCap else matureCap = nil end
	end
	local sf, ini = caps.sizeFactors, caps.initials
	local bySf = type(sf) == "table" and type(ini) == "table" and #sf >= 1 and #ini >= #sf
	local cap = 0
	if bySf then
		if type(ledger.sf) ~= "table" or #ledger.sf ~= #sf then
			ledger.sf = {}
			for i = 1, #sf do ledger.sf[i] = sf[i] end
		end
		for i = 1, #sf do
			if sf[i] < ledger.sf[i] then ledger.sf[i] = sf[i] end   -- a lowered size (never by the game): no debt
			cap = cap + ini[i] * (sf[i] - ledger.sf[i])
		end
	else
		if ledger.ref == nil or caps.target < ledger.ref then ledger.ref = caps.target end
		cap = caps.target - ledger.ref
	end
	local raw = cap / perEdge * demK
	-- (the bank's factor runs to BANK_FAST_MAX, the increment's to FAST_MAX)
	local k = math.max(1, math.min(M.BANK_FAST_MAX, raw / (M.DEMAND_BANK * la.maxEdges)))
	local fastBank = math.max(k, (ledger.fast or 1) * M.FAST_DECAY, 1)
	ledger.fast = fastBank
	local fast = math.min(M.FAST_MAX, fastBank)
	local bank = M.DEMAND_BANK * fastBank * la.maxEdges * perEdge
	if cap > bank then
		M.served(ledger, caps, cap - bank)
		cap = bank
	end
	local threshold = math.max(la.min, (lots.built or 0) * la.share)
	local gameOpen = math.max(0, (lots.open or 0) - (lots.ownOpen or 0))
	return { edges = cap / perEdge * demK, len = cap / perM * demK, perM = perM, perEdge = perEdge, cap = cap, raw = raw,
		fast = fast, freeK = freeK, pbK = pbK, demK = demK, freeShare = freeShare, mat = mat, matureCap = matureCap, dz = dz,
		incMax = math.floor(la.maxEdges * (1 + (fast - 1) * M.FAST_INC) + 0.5),
		lead = math.max(threshold * M.OWN_LEAD * (1 + (math.max(1, tonumber(lockK) or 1) - 1) * (1 - mat)),
			math.min(gameOpen * M.OWN_MATCH, (lots.built or 0) * M.OWN_CAP)),
		ownOpen = lots.ownOpen or 0 }
end

--- Marks `amount` person capacity of a town's demand as served (a build, or demand dropped from the bank): the
--- ledger's size factors move toward the current ones by that share of the unserved capacity (never past them).
function M.served(ledger, caps, amount)
	if caps == nil or amount == nil or amount <= 0 then return end
	local sf, ini = caps.sizeFactors, caps.initials
	if type(ledger.sf) == "table" and type(sf) == "table" and type(ini) == "table" and #ledger.sf == #sf then
		local cap = 0
		for i = 1, #sf do cap = cap + (ini[i] or 0) * math.max(0, sf[i] - ledger.sf[i]) end
		if cap <= 0 then return end
		local k = math.min(1, amount / cap)
		for i = 1, #sf do
			if sf[i] > ledger.sf[i] then ledger.sf[i] = ledger.sf[i] + (sf[i] - ledger.sf[i]) * k end
		end
	elseif ledger.ref ~= nil and caps.target then
		ledger.ref = math.min(caps.target, ledger.ref + amount)
	end
end

--- Needs the town more streets? lots = M.lots result; caps = { target = n, actual = n } (person capacity,
--- optional); lookahead = 1..3; dem = M.demand result (optional). Returns needs (bool), threshold (open lots
--- wanted), why, capRatio (nil without caps). why: "demand" (the target grew by DEMAND_MIN_EDGES of streets since
--- the last build and the town's own streets have room for no more than the lead: build), "ahead" (demand, but
--- the town's own streets still wait for houses), "low" (open frontage under the threshold: build), "open"
--- (enough open frontage), "over" (the town is well over its capacity target, i.e. shrinking), "free" (no demand and
--- more than FREE_AIM + FREE_ROOM of the town's lots free: no streets for room, 2026-10-14 late), "mature" (demand, but a
--- grown town with more than M.matureHoldLine of its lots free fills them first, 2026-10-14).
function M.needsRoom(lots, caps, lookahead, dem)
	local la = M.LOOKAHEAD[lookahead or 2] or M.LOOKAHEAD[2]
	local threshold = math.max(la.min, lots.built * la.share)
	local ratio = nil
	if caps and caps.target and caps.actual and caps.target > 0 then ratio = caps.actual / caps.target end
	if ratio ~= nil and ratio > M.CAP_OVER then return false, threshold, "over", ratio end
	if M.DEMAND and dem ~= nil and dem.edges >= M.DEMAND_MIN_EDGES then
		if M.matureHold(dem.mat, dem.freeShare, dem.dz) then return false, threshold, "mature", ratio end
		if (lots.ownOpen or dem.ownOpen or 0) < dem.lead then return true, threshold, "demand", ratio end
		return false, threshold, "ahead", ratio
	end
	-- (2026-10-14 late: a town with most of its lots free gets no streets for room either)
	-- (2026-10-14: phased in with the town's maturity, dem.mat; a young town still builds for room)
	if dem ~= nil and dem.freeShare ~= nil and dem.freeShare > M.FREE_AIM + M.FREE_ROOM + (1 - (dem.mat or 1)) * M.YOUNG_ROOM then
		return false, threshold, "free", ratio
	end
	if ratio ~= nil and ratio < M.CAP_HUNGRY then threshold = threshold * M.HUNGRY_FACTOR end
	local open = lots.open or lots.room or 0
	if open >= threshold then return false, threshold, "open", ratio end
	return true, threshold, "low", ratio
end

--- Is the town's growth empty (2026-10-14, NEXT_PHASE_BRIEF 52.3)? Its size factors never rose above 1 (no growth,
--- by the game or the dev Simulate) and its initial capacity is built (at least GROWTH_FULL of the target): the game
--- builds no more houses there (the last few % go on its existing lots), so new streets would stay empty. Unknown or
--- bad caps: false (not held).
M.GROWTH_SF_EPS = 0.001
M.GROWTH_FULL = 0.95
function M.growthEmpty(caps)
	if type(caps) ~= "table" or type(caps.sizeFactors) ~= "table" or #caps.sizeFactors == 0 then return false end
	for i = 1, #caps.sizeFactors do
		local v = tonumber(caps.sizeFactors[i])
		if v == nil or v ~= v or v > 1 + M.GROWTH_SF_EPS then return false end
	end
	local a, tg = tonumber(caps.actual), tonumber(caps.target)
	if a == nil or tg == nil or a ~= a or tg ~= tg or tg <= 0 then return false end
	return a >= M.GROWTH_FULL * tg
end

--- The free-lot share above which a town of maturity mat holds its demand builds (nil: never, a young town).
function M.matureHoldLine(mat, dz)
	if mat == nil or mat < M.MATURE_HOLD_MAT then return nil end
	return ((dz and dz.holdFree) or M.MATURE_HOLD_FREE) + (1 - mat) * M.YOUNG_ROOM
end

--- Does a town of maturity mat with freeShare of its lots free hold its demand builds (the mature hold)?
function M.matureHold(mat, freeShare, dz)
	local line = M.matureHoldLine(mat, dz)
	return line ~= nil and freeShare ~= nil and freeShare > line
end

---------------------------------------------------------------------------
-- Who built a town's streets (§65, 2026-10-15)

--- The town's street edges by builder: lots = M.lots result (edges, ownEdges = the mod's: locked or built this session);
--- core = its edges that were not the mod's at the first sight (the saved frame's `e0`, else this session's first check),
--- nil unknown. Returns { mod, game (edges - mod - core, at least 0; nil without a core), core, share (game / (game +
--- mod), nil without new streets) }. A game street split by a later one counts twice (the game's edge ids), a mod street
--- the game split before it was locked or after a reload counts as the game's (legacy towns: unlocked mod streets of
--- earlier sessions are the game's here too).
function M.edgeSplit(lots, core)
	local edges, mod = tonumber(lots and lots.edges) or 0, tonumber(lots and lots.ownEdges) or 0
	local out = { mod = mod, core = core }
	if tonumber(core) then
		out.game = math.max(0, edges - mod - core)
		if out.game + mod > 0 then out.share = out.game / (out.game + mod) end
	end
	return out
end

---------------------------------------------------------------------------
-- Stall guard (§65, 2026-10-15): a "mod"-locked town grows only on the mod's streets and on what the game branches off
-- its own. When its capacity stays well under its target (ratio below STALL_RATIO) and its buildings stop growing
-- (less than STALL_GROW since the streak began) while it is short of open frontage (all its streets' open frontage
-- below STALL_OPEN_K x the lookahead need: a town whose lots stay free has no street shortage, more streets would stay
-- empty) for STALL_N checks in a row, it is stalled: the guard fires at STALL_N,
-- 2 x STALL_N, ... checks of the streak, its level rising each time up to STALL_LEVELS (1: a bigger increment and more
-- own empty budget, open land first; 2: also the shape's envelope wider; 3: also the forest hold a step looser, last).
-- At most STALL_MAX fires per town and session (then `capped`). A ratio back above STALL_RATIO or the buildings growing
-- ends the streak (level back to 0).
M.STALL_RATIO = 0.85
M.STALL_GROW = 0.03
M.STALL_N = 3
M.STALL_LEVELS = 3
M.STALL_MAX = 12
M.STALL_OPEN_K = 2

--- One check of the stall guard. st = the town's session table ({} at first; updated in place: n = streak, b0 = the
--- buildings when it began, fires, capped); ratio = capacity / target (nil unknown); buildings = the town's buildings;
--- open, need = its open frontage (M.lots open) and the lookahead need (M.needsRoom threshold; nil: not checked).
--- Returns level (1..STALL_LEVELS) when the guard fires this check, else nil; second: "capped" the check it hit STALL_MAX.
function M.stall(st, ratio, buildings, open, need)
	buildings = tonumber(buildings) or 0
	st.fires = st.fires or 0
	local roomy = tonumber(open) and tonumber(need) and open >= M.STALL_OPEN_K * need
	if ratio == nil or ratio ~= ratio or ratio >= M.STALL_RATIO or roomy then
		st.n, st.b0, st.level = 0, nil, 0
		return nil
	end
	if st.b0 == nil or buildings > st.b0 * (1 + M.STALL_GROW) or buildings < st.b0 then
		-- (a new streak, or the town grew: the streak starts again from here)
		st.n, st.b0, st.level = 1, buildings, 0
		return nil
	end
	st.n = (st.n or 0) + 1
	if st.n < M.STALL_N or st.n % M.STALL_N ~= 0 then return nil end
	if st.fires >= M.STALL_MAX then
		if not st.capped then
			st.capped = true
			return nil, "capped"
		end
		return nil
	end
	st.fires = st.fires + 1
	st.level = math.min(M.STALL_LEVELS, math.floor(st.n / M.STALL_N))
	return st.level
end

--- Edges per increment for a lookahead setting.
function M.maxEdges(lookahead)
	local la = M.LOOKAHEAD[lookahead or 2] or M.LOOKAHEAD[2]
	return la.maxEdges
end

---------------------------------------------------------------------------
-- Scheduler (times in microseconds of real time, api.type.Clock)

M.COOLDOWN_S = {
	built = 90,      -- after a successful increment: let the town adopt it
	more = 30,       -- after a demand increment that left MORE_MIN_EDGES of demand: soon again, picked first (hot)
	room = 30,       -- had enough room
	empty = 240,     -- the planner found nothing to build
	skip = 600,      -- not acted on (existing town, no buildings, ...)
	fail = 120,      -- refused by the pre-check or the build (doubles per failure in a row, capped)
}
M.FAIL_CAP_S = 1800

function M.newSched()
	return { cursor = nil, towns = {} }
end

local function townState(sched, id)
	local t = sched.towns[id]
	if t == nil then
		t = { nextUs = 0, fails = 0 }
		sched.towns[id] = t
	end
	return t
end

--- Next town (ids ascending) after the cursor whose cooldown is over, round-robin; nil when none is due. A due town
--- marked hot (outcome "more": a fast grower with demand left) goes first.
function M.pick(sched, ids, nowUs)
	local n = #ids
	if n == 0 then return nil end
	for _, id in ipairs(ids) do
		local t = sched.towns[id]
		if t and t.hot and t.nextUs <= nowUs then
			t.hot = false
			return id
		end
	end
	local start = 1
	if sched.cursor ~= nil then
		start = n + 1
		for i, id in ipairs(ids) do
			if id > sched.cursor then start = i break end
		end
	end
	for k = 0, n - 1 do
		local id = ids[(start - 1 + k) % n + 1]
		if townState(sched, id).nextUs <= nowUs then
			sched.cursor = id
			return id
		end
	end
	return nil
end

--- Puts a town on cooldown after an outcome (a key of COOLDOWN_S). Returns the cooldown in seconds.
function M.cooldown(sched, id, nowUs, outcome)
	local t = townState(sched, id)
	local s = M.COOLDOWN_S[outcome] or M.COOLDOWN_S.room
	if outcome == "fail" then
		t.fails = t.fails + 1
		s = math.min(M.FAIL_CAP_S, s * 2 ^ (t.fails - 1))
	elseif outcome == "built" or outcome == "more" then
		t.fails = 0
	end
	t.hot = outcome == "more"
	t.nextUs = nowUs + s * 1e6
	return s
end

return M
