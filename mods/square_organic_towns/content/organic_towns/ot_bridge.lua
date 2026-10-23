-- Organic Towns: a river town's bridge to the far bank (pure; 2026-10-13, real map round 3).
--
-- User: "Cities that jump across a river are interesting." A river town (ot_site river: a river through the 600 m
-- disc) now and then (a seeded CHANCE, once a MIN_BUILDINGS town grows: a demand build) builds ONE street across the
-- river at a narrow point and grows a quarter on the far bank. Research (2026-10-13, tealdefs + Move It): a street edge
-- is a bridge when its BaseEdge `type` is api.type.enum.BaseEdgeType.BRIDGE and `typeIndex` names a bridgeTypeRep entry
-- (base stone / steel / concrete carry ROAD; ot_engine.bridgeType picks one by year); Move It converts ground edges to
-- bridges that way in one SimpleProposal. Creating a NEW bridge edge from a script is unverified in game, so the
-- increment is all or nothing, pre-checked (makeProposalData) before it is sent, tried once per town and session and
-- logged (BRIDGE lines); a refusal is never retried with a smaller piece.
--
-- The increment (M.plan): from a joinable dead end D of the town, straight across the river on the river's normal:
--   D -> A  approach on land (A: BANK m before the first water), rising to the deck height
--   A -> B  the bridge edge (straight; B: BANK m beyond the last water), deck = max(bank heights) + LIFT, or CLEARANCE
--           over the water level where ships may pass (R6, below)
--   B -> C  a street on the far bank, down to the ground
--   C -> L, C -> R  a cross street at C (a T): the seed of the far quarter (its two dead ends are the town's, so
--           the planner grows the quarter from them; housed front / lead rules apply as everywhere). Since 2026-10-14
--           (CROSS_LATER, below) not built: the far street ends at C, dosed, and the planner grows from there.
-- Every new node gets a node config (ot_proposal: 2-street nodes the junction pattern, dead ends an empty one), the
-- joined dead end a full one (the crash rule). All edges take the dead end's own template (one lane layout). The
-- approach and the bridge are locked (roadDevelopmentLocked); the far streets not, so the town builds there too.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"

local M = {}

local function wet(s, x, y) return T.isWater(s, x, y) end

-- Bridges and ships (round R6, 2026-10-13; docs/findings/roads.md "A low road bridge cuts a ship lane", verified by the
-- user): a low deck blocks ships. The API reads no navigability and no ship path (research 2026-10-13: only
-- terrain.isOnWater, the water mesh, ship positions; the line manager's navigable layer is drawn by the engine), so:
--   ship=path       a ship line has a stop on the water body the crossing spans (a capped flood fill over the water from
--                   the crossing, SHIP_CELLS cells of SHIP_CELL m; a stop within STOP_R of a visited wet cell), or the
--                   fill was capped with a ship stop within SHIP_R: the conservative "active path". The deck must clear
--                   the water by CLEARANCE (over waterLevel); the approaches at MAX_GRADE get longer, and a crossing
--                   whose approaches don't fit is skipped (never low over an active path)
--   ship=navigable  no ship stop on it, but the water is NAV_SPAN m wide or more (a proxy: navigability isn't readable):
--                   a high deck when it fits (a line may come later), else low (the user accepts it)
--   ship=none       narrower water and no ships: the low deck (higher bank + LIFT); preferred (NAV_PEN, PATH_PEN)
M.CLEARANCE = 11          -- m over the water level (unmeasured; about 10-12 m)
M.NAV_SPAN = 45           -- m: water at least this wide counts as navigable (proxy, unverified)
M.NAV_PEN = 40            -- score penalty of a navigable crossing (lower scores win)
M.PATH_PEN = 25           -- ... of one over an active path (on top: its long approaches)
M.FAR_MAX_HIGH = 240      -- m: the far street of a high deck at most
M.SHIP_CELL = 40          -- m: the flood fill's cell
M.SHIP_CELLS = 2500       -- cells at most per fill
M.SHIP_R = 6000           -- m: a capped fill with a ship stop this near counts as a path
M.STOP_R = 200            -- m: a harbour this near a wet cell sits on that water

--- The water body test from a wet point (x, y): ships = { { x, y, line } } (the ship lines' stops), cache = {} (cells
--- already filled: one fill per water body). Returns "path" | "none", why ("stop:<line>" | "cap:<m>" | "noShips" |
--- "noStop"), cells.
function M.shipCheck(s, x, y, ships, cache)
	if ships == nil or #ships == 0 then return "none", "noShips", 0 end
	cache = cache or {}
	local c = M.SHIP_CELL
	local function key(i, j) return i * 1000003 + j end
	local i0, j0 = math.floor(x / c), math.floor(y / c)
	local hit = cache[key(i0, j0)]
	if hit then return hit.kind, hit.why, 0 end
	-- the stops in a coarse index (STOP_R cells)
	local sidx = {}
	local sc = M.STOP_R
	for _, st in ipairs(ships) do
		if st.x == st.x and st.y == st.y then
			local k = math.floor(st.x / sc) * 1000003 + math.floor(st.y / sc)
			sidx[k] = sidx[k] or {}
			local l = sidx[k]
			l[#l + 1] = st
		end
	end
	local function stopNear(px, py)
		local a, b = math.floor(px / sc), math.floor(py / sc)
		for da = -1, 1 do
			for db = -1, 1 do
				for _, st in ipairs(sidx[(a + da) * 1000003 + (b + db)] or {}) do
					if G.dist(px, py, st.x, st.y) <= M.STOP_R then return st end
				end
			end
		end
		return nil
	end
	local seen, queue, qi = { [key(i0, j0)] = true }, { { i0, j0 } }, 1
	local res = nil
	while qi <= #queue and qi <= M.SHIP_CELLS do
		local cell = queue[qi]
		qi = qi + 1
		local px, py = (cell[1] + 0.5) * c, (cell[2] + 0.5) * c
		local st = stopNear(px, py)
		if st then res = { kind = "path", why = "stop:" .. tostring(st.line or "?") } break end
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local a, b = cell[1] + d[1], cell[2] + d[2]
			local k = key(a, b)
			if not seen[k] then
				seen[k] = true
				if wet(s, (a + 0.5) * c, (b + 0.5) * c) then queue[#queue + 1] = { a, b } end
			end
		end
	end
	if res == nil then
		if qi <= #queue then
			-- (capped: a big lake / the sea; any ship stop near enough counts, the conservative side)
			local nearest = math.huge
			for _, st in ipairs(ships) do nearest = math.min(nearest, G.dist(x, y, st.x, st.y)) end
			if nearest <= M.SHIP_R then res = { kind = "path", why = string.format("cap:%.0f", nearest) }
			else res = { kind = "none", why = "noStop" } end
		else
			res = { kind = "none", why = "noStop" }
		end
	end
	for _, cell in ipairs(queue) do cache[key(cell[1], cell[2])] = res end
	return res.kind, res.why, #queue
end

M.ON = true
M.CHANCE = 0.75           -- seeded share of the river towns (0.4 until 2026-10-13: with one or two river towns a map
                          -- rarely saw a bridge tried at all)
M.MIN_BUILDINGS = 150     -- a town this big (buildings) may bridge
M.SEARCH_R = 450          -- m: dead ends this close to the river are tried
M.STEP = 4                -- m: march step across the river
M.MAX_RUN = 700           -- m: how far a crossing line is followed
M.MIN_SPAN, M.MAX_SPAN = 12, 160   -- m of water the bridge spans (a narrow point)
M.BANK = 12               -- m of land between the water and each bridge end
M.APPROACH_MIN = 30       -- m: the approach from the dead end at least this long
M.LIFT = 4                -- m: deck above the higher bank
M.MAX_GRADE = 0.08        -- approach / far street grade at most
M.FAR_MIN = 70            -- m: the far street at least this long (longer when the deck is high)
M.FAR_MAX = 160
M.CROSS = 55              -- m: each half of the cross street at the far end
M.CLEAR = 30              -- m: far-bank streets keep this far from existing streets
M.TURNS = { 0, math.rad(-20), math.rad(20), math.rad(-40), math.rad(40) }   -- tried off the river's normal
-- (2026-10-14, run 2026-10-14_0502_sqot: High Wycombe's bridge ended at an empty cross street on the far bank, Budleigh
-- Salterton's ran 384 m straight from its dead end to the water: a long empty straight lane.)
-- CROSS_LATER: the far street ends at C as a dead end (no cross street yet); the driver doses beside it after the build
-- and again once the far bank has lots (BR_REDOSE), and the town's planner grows the quarter from C once houses stand
-- (housed front, as everywhere). APPROACH_MAX: no longer approach than this; APPROACH_BOW_M: a longer approach bends once
-- (a waypoint BOW x its length to one side, seeded), like the satellite links and lanes ahead (one template: no lane
-- count changes next to the bridge).
M.CROSS_LATER = true
M.APPROACH_MAX = 260
M.APPROACH_BOW_M = 120
M.BOW = 0.07

-- Narrow water near a town (2026-10-13, real map run 2026-10-13_0232_sqot-dev: 0 BRIDGE lines; no town read "river"
-- (the 600 m disc's water test, ot_terrain), although Bootle had a river ~1 km out flowing into its lake): rays from
-- the centre find stretches of water NARROW_MIN..MAX_SPAN m wide with dry land beyond (a river or a narrow arm of a
-- lake), within NARROW_R; such a town is a bridge candidate too, and its crossings are searched toward them.
M.NARROW_R = 1500         -- m: rays from the centre this long
M.NARROW_RAYS = 24
M.NARROW_STEP = 12        -- m: sample step along a ray (a river is wider than one step)
M.NARROW_DRY = 40         -- m of dry land beyond the water at least

-- (2026-10-14, run 2026-10-13_2355_sqot: 14 of 16 towns `noRiver`) also from ORIGINS around the centre (ORIGIN_D m
-- out, ORIGIN_RAYS rays of ORIGIN_R m): narrow lake arms and river bends the centre's rays pass by.
M.ORIGINS = 4
M.ORIGIN_D = 450
M.ORIGIN_RAYS = 16
M.ORIGIN_R = 700

--- Narrow water points around (cx, cy): { {x, y, width, heading} } (heading: the ray's, from the centre). s: sampler.
--- yield: nil, or called between the rays (the driver's step note, 2026-10-21).
function M.narrowWater(s, cx, cy, yield)
	local out = {}
	if s == nil then return out end
	local origins = { { cx, cy, M.NARROW_RAYS, M.NARROW_R } }
	for k = 0, M.ORIGINS - 1 do
		local a = k * 2 * math.pi / M.ORIGINS + math.pi / M.ORIGINS
		origins[#origins + 1] = { cx + math.cos(a) * M.ORIGIN_D, cy + math.sin(a) * M.ORIGIN_D, M.ORIGIN_RAYS, M.ORIGIN_R }
	end
	for oi, org in ipairs(origins) do
	local ox, oy, rays, maxR = org[1], org[2], org[3], org[4]
	if oi == 1 or not wet(s, ox, oy) then
	for k = 0, rays - 1 do
		if yield then yield() end
		local h = k * 2 * math.pi / rays
		local ca, sa = math.cos(h), math.sin(h)
		local w1, dryRun = nil, 0
		local d = 0
		local wetAt0 = wet(s, ox, oy)
		while d <= maxR do
			local isW = wet(s, ox + ca * d, oy + sa * d)
			if isW then
				if w1 == nil and not wetAt0 then w1 = d end
				dryRun = 0
			else
				wetAt0 = false
				if w1 ~= nil then
					-- end of a wet stretch: narrow enough, and dry beyond for NARROW_DRY?
					local w2 = d
					local okDry = true
					for k2 = M.NARROW_STEP, M.NARROW_DRY, M.NARROW_STEP do
						if wet(s, ox + ca * (d + k2), oy + sa * (d + k2)) then okDry = false break end
					end
					local width = w2 - w1
					if okDry and width >= M.MIN_SPAN and width <= M.MAX_SPAN then
						local m = (w1 + w2) / 2
						local px, py = ox + ca * m, oy + sa * m
						if G.dist(px, py, cx, cy) <= M.NARROW_R then out[#out + 1] = { px, py, width, h } end
					end
					w1 = nil
				end
				dryRun = dryRun + M.NARROW_STEP
			end
			d = d + M.NARROW_STEP
		end
	end
	end
	end
	return out
end

--- Is town t a bridge candidate? o = { seed, buildings, river (bool), done (bool) }. Returns bool, why.
function M.eligible(o)
	if not M.ON then return false, "off" end
	if o.done then return false, "done" end
	if not o.river then return false, "noRiver" end
	-- (o.always: a waterfront town, ot_character 2026-10-14: always, and from half the size)
	if (o.buildings or 0) < (o.always and M.MIN_BUILDINGS / 2 or M.MIN_BUILDINGS) then return false, "small" end
	if not o.always and rng.decide(o.dv, o.seed or 1, "bridge") >= M.CHANCE then return false, "rare" end
	return true, "seeded"
end

--- The crossing along heading h from (x, y): distances to the first and last water and the land beyond, or nil.
--- Returns { w1, w2 } (m from the start) when water starts after a dry stretch, ends within MAX_SPAN and dry land
--- follows for at least BANK + FAR_MIN.
function M.crossing(s, x, y, h)
	local ca, sa = math.cos(h), math.sin(h)
	local w1, w2 = nil, nil
	local d = 0
	while d <= M.MAX_RUN do
		local px, py = x + ca * d, y + sa * d
		local isW = wet(s, px, py)
		if w1 == nil then
			if isW then w1 = d
			elseif d > M.SEARCH_R + M.STEP then return nil end
		elseif not isW then
			w2 = d
			break
		elseif d - w1 > M.MAX_SPAN then
			return nil
		end
		d = d + M.STEP
	end
	if w1 == nil or w2 == nil then return nil end
	-- dry beyond: the far street and a margin
	for k = 0, M.BANK + M.FAR_MIN + M.CROSS, M.STEP do
		if wet(s, x + ca * (w2 + k), y + sa * (w2 + k)) then return nil end
	end
	return { w1 = w1, w2 = w2 }
end

local function v3(x, y, z) return { G.z0(G.round(x, 3)), G.z0(G.round(y, 3)), G.z0(G.round(z, 3)) } end

--- The best crossing plan, or nil, why. o = { sampler, deadEnds = { { x, y, node, z, template } }, axis = river axis
--- (rad), g = street graph (existing streets: no crossing, clearance), bounds (ot_map), seed, ships = { { x, y, line } }
--- (R6: the ship lines' stops), waterLevel (m, default 0) }. Returns { inc (ot_plan increment), span, approach, far,
--- deck, deadEnd, heading, ship ("none" | "navigable" | "path"), shipWhy, clearance (deck over the water level), cands }.
function M.plan(o)
	local s = o.sampler
	if s == nil or o.deadEnds == nil or #o.deadEnds == 0 then return nil, "noDeadEnd" end
	if o.axis == nil and (o.points == nil or #o.points == 0) then return nil, "noAxis" end
	local best, n = nil, 0
	local all = {}
	local nearest = math.huge
	local shipCache, highNoFit = {}, 0
	for _, de in ipairs(o.deadEnds) do
		-- base headings: the river's normal both ways (a river town), and toward the nearest narrow water point
		local bases = {}
		if o.axis then
			bases[#bases + 1] = o.axis + math.pi / 2
			bases[#bases + 1] = o.axis + 3 * math.pi / 2
		end
		local np, nd = nil, M.SEARCH_R + M.MAX_SPAN
		for _, p in ipairs(o.points or {}) do
			local d = G.dist(de[1], de[2], p[1], p[2])
			if d < nd then np, nd = p, d end
		end
		if np then bases[#bases + 1] = G.atan2(np[2] - de[2], np[1] - de[1]) end
		for _, normal in ipairs(bases) do
			for _, turn in ipairs(M.TURNS) do
				if o.yield then o.yield() end   -- (2026-10-21: the driver's step note between the headings, TICKCOST atStep)
				local h = G.wrap(normal + turn)
				local c = M.crossing(s, de[1], de[2], h)
				if c then nearest = math.min(nearest, c.w1) end
				if c and c.w1 <= M.SEARCH_R then
					local span = c.w2 - c.w1
					local dA = c.w1 - M.BANK
					if span >= M.MIN_SPAN and dA >= M.APPROACH_MIN and dA <= M.APPROACH_MAX then
						local ca, sa = math.cos(h), math.sin(h)
						local ax, ay = de[1] + ca * dA, de[2] + sa * dA
						local dB = c.w2 + M.BANK
						local bx, by = de[1] + ca * dB, de[2] + sa * dB
						local hD = de[4] or T.height(s, de[1], de[2])
						local hA, hB = T.height(s, ax, ay), T.height(s, bx, by)
						-- (R6: ships. The water body's ship lines decide the deck: see the header)
						local mx, my = de[1] + ca * (c.w1 + c.w2) / 2, de[2] + sa * (c.w1 + c.w2) / 2
						local ship, shipWhy = M.shipCheck(s, mx, my, o.ships, shipCache)
						if ship == "none" and span >= M.NAV_SPAN then ship, shipWhy = "navigable", string.format("span:%.0f", span) end
						local low = math.max(hA, hB) + M.LIFT
						local high = math.max(low, (o.waterLevel or 0) + M.CLEARANCE)
						local tries = ship == "path" and { high } or (ship == "navigable" and { high, low } or { low })
						local deck, cx, cy, hC, far, okGrade
						for _, dk in ipairs(tries) do
							deck = dk
							local farMax = dk > low + 1e-6 and M.FAR_MAX_HIGH or M.FAR_MAX
							cx, cy = bx + ca * M.FAR_MIN, by + sa * M.FAR_MIN
							hC = T.height(s, cx, cy)
							far = G.clamp(math.abs(deck - hC) / M.MAX_GRADE, M.FAR_MIN, farMax)
							cx, cy = bx + ca * far, by + sa * far
							hC = T.height(s, cx, cy)
							okGrade = math.abs(deck - hD) / dA <= M.MAX_GRADE and math.abs(deck - hC) / far <= M.MAX_GRADE + 1e-9
							if okGrade then break end
						end
						if not okGrade and ship == "path" then highNoFit = highNoFit + 1 end
						-- the cross street at C (perpendicular), its ends dry
						local px, py = -sa, ca
						local lx, ly = cx + px * M.CROSS, cy + py * M.CROSS
						local rx, ry = cx - px * M.CROSS, cy - py * M.CROSS
						local ok = okGrade and not wet(s, cx, cy) and not wet(s, lx, ly) and not wet(s, rx, ry)
						-- (2026-10-14: the far street and the cross street dry all along: a high deck's far street runs up
						-- to FAR_MAX_HIGH, beyond the dry margin crossing() checked; one guess for Darley Dale's "Place on
						-- Land" in run 2026-10-13_2113_sqot-dev)
						ok = ok and not T.wetAlong(s, { { bx, by }, { cx, cy } }, 0, M.STEP * 2)
							and not T.wetAlong(s, { { lx, ly }, { rx, ry } }, 0, M.STEP * 2)
						local key = string.format("%d:%d", de[3], math.floor(math.deg(G.wrap(h)) % 360 + 0.5))
						ok = ok and not (o.skip and o.skip[key])
						-- inside the map margin
						if ok and o.bounds then
							for _, p in ipairs({ { ax, ay }, { bx, by }, { cx, cy }, { lx, ly }, { rx, ry } }) do
								if MAP.nearEdge(o.bounds, p[1], p[2]) then ok = false break end
							end
						end
						-- no existing street crossed, the far bank clear of streets
						-- (the bowed approach's waypoint, APPROACH_BOW_M: dry, inside the map, no street crossed)
						local W = nil
						if ok and dA > M.APPROACH_BOW_M then
							local side = rng.unit(o.seed or 1, "bridgeBow", de[3]) < 0.5 and 1 or -1
							local f = 0.5
							local wx = de[1] + ca * dA * f + px * side * M.BOW * dA
							local wy = de[2] + sa * dA * f + py * side * M.BOW * dA
							W = { wx, wy, hD + (deck - hD) * f }
							if wet(s, wx, wy) or T.wetAlong(s, { { de[1], de[2] }, { wx, wy }, { ax, ay } }, 0, M.STEP * 2) then ok = false end
							if ok and o.bounds and MAP.nearEdge(o.bounds, wx, wy) then ok = false end
							if ok and o.g and (OG.crossing(o.g, de[1], de[2], wx, wy, { [de[3]] = true })
								or OG.crossing(o.g, wx, wy, ax, ay, { [de[3]] = true })) then ok = false end
						end
						if ok and o.g then
							local skip = { [de[3]] = true }
							if OG.crossing(o.g, de[1], de[2], cx, cy, skip) or OG.crossing(o.g, lx, ly, rx, ry, skip) then ok = false end
							for _, p in ipairs({ { bx, by }, { cx, cy }, { lx, ly }, { rx, ry } }) do
								if ok and OG.distToEdges(o.g, p[1], p[2], M.CLEAR, skip) then ok = false end
							end
						end
						if ok then
							n = n + 1
							local score = span + 0.25 * dA + 0.1 * far + 8 * math.abs(turn) / math.rad(20)
								+ (ship == "navigable" and M.NAV_PEN or 0) + (ship == "path" and (M.NAV_PEN + M.PATH_PEN) or 0)
							local c = { score = score, de = de, h = h, dA = dA, span = span, far = far, deck = deck,
								ship = ship, shipWhy = shipWhy, clearance = deck - (o.waterLevel or 0), key = key,
								A = { ax, ay, deck }, B = { bx, by, deck }, C = { cx, cy, hC },
								L = { lx, ly, T.height(s, lx, ly) }, R = { rx, ry, T.height(s, rx, ry) }, hD = hD, W = W }
							all[#all + 1] = c
							if best == nil or score < best.score - 1e-9 or (math.abs(score - best.score) <= 1e-9 and de[3] < best.de[3]) then
								best = c
							end
						end
					end
				end
			end
		end
	end
	if best == nil then
		if highNoFit > 0 then return nil, "shipPath:highNoFit=" .. highNoFit, n end
		return nil, (nearest == math.huge and "noCrossing" or (nearest > M.SEARCH_R and "far" or "noSite")), n
	end
	-- (2026-10-14) the other candidates, best first, one per dead end and heading (M.MAX_CANDS): the driver tests them
	-- against the obstacles beyond the snapshot and tries the next after a refusal
	table.sort(all, function(a, b)
		if math.abs(a.score - b.score) > 1e-9 then return a.score < b.score end
		return a.de[3] < b.de[3]
	end)
	local cands = {}
	for _, c in ipairs(all) do
		if #cands >= M.MAX_CANDS then break end
		cands[#cands + 1] = M.increment(c, o)
	end
	local first = cands[1]
	first.cands = cands
	return first, nil, n
end
M.MAX_CANDS = 6

-- §69 (2026-10-15, run 2026-10-15_1936_sqot-glprobe: Merehythe's bridge led a straight ~1 km road onto an empty
-- peninsula): in "steer" towns (ot_driver) a crossing needs a target on the far bank, a reason to cross: one of
-- targets ({ { x, y, kind } }: a neighbour town, an industry, the town's own housed streets) within TARGET_R of the far
-- end C on the far side (not back across the water), or ahead of it within TARGET_FAR inside TARGET_DEG of the
-- crossing's heading; else only a short crossing (approach + span + far street at most EMPTY_MAX_M), no long link to
-- empty land.
M.TARGET_R = 300
M.TARGET_FAR = 1500
M.TARGET_DEG = 35
M.EMPTY_MAX_M = 220

--- The crossing's length (m): approach + span + far street.
function M.length(bp)
	return (bp.approach or 0) + (bp.span or 0) + (bp.far or 0)
end

--- The far bank's target of a crossing plan (bp from M.plan / increment): the nearest target's kind and distance, or nil.
function M.target(bp, targets)
	local cN = bp and bp.inc and bp.inc.nodes and bp.inc.nodes[3]
	if cN == nil or bp.heading == nil then return nil end
	local ux, uy = math.cos(bp.heading), math.sin(bp.heading)
	local cosT = math.cos(math.rad(M.TARGET_DEG))
	local best, bd = nil, math.huge
	for i = 1, math.min(#(targets or {}), 4000) do
		local tg = targets[i]
		local x, y = tg.x or tg[1], tg.y or tg[2]
		if x and y and x == x and y == y then
			local dx, dy = x - cN.x, y - cN.y
			local d = math.sqrt(dx * dx + dy * dy)
			local along = dx * ux + dy * uy
			-- (the far side: not back across the river, whose far street is bp.far long)
			local farSide = along >= -0.5 * (bp.far or 0)
			local ok = (d <= M.TARGET_R and farSide) or (d <= M.TARGET_FAR and d > 1e-6 and along / d >= cosT)
			if ok and d < bd then best, bd = tg.kind or "target", d end
		end
	end
	return best, best and bd or nil
end

--- The polylines of a crossing plan (bp from M.plan / increment) for an obstacle test: { approach + span + far, cross }.
function M.lines(bp)
	local nd = {}
	for _, x in ipairs(bp.inc.nodes) do nd[x.entity] = { x.x, x.y } end
	local e1 = bp.inc.edges[1]
	local main = { { e1.p0[1], e1.p0[2] } }
	if nd[-11] then main[#main + 1] = nd[-11] end
	main[#main + 1] = nd[-6]
	main[#main + 1] = nd[-7]
	main[#main + 1] = nd[-8]
	if nd[-9] == nil then return { main } end
	return { main, { nd[-9], nd[-8], nd[-10] } }
end

--- The far-bank dose points of a bridge plan (CROSS_LATER): beside the far street's end at C, both sides, `off` m out.
function M.farPoints(bp, off)
	off = off or 20
	local nd = {}
	for _, x in ipairs(bp.inc.nodes) do nd[x.entity] = { x.x, x.y } end
	local B, C = nd[-7], nd[-8]
	if B == nil or C == nil then return {} end
	local dx, dy = C[1] - B[1], C[2] - B[2]
	local l = math.sqrt(dx * dx + dy * dy)
	if l < 1 then return {} end
	local ux, uy = dx / l, dy / l
	local mx, my = C[1] - ux * math.min(30, l * 0.3), C[2] - uy * math.min(30, l * 0.3)
	return { { mx - uy * off, my + ux * off }, { mx + uy * off, my - ux * off } }
end

--- The ot_plan-shaped increment for a chosen crossing (edges -1..-5, nodes -6..-10).
function M.increment(b, o)
	local de = b.de
	local tpl = de[5]
	local nodes = {
		{ entity = -6, x = b.A[1], y = b.A[2], z = b.A[3] },
		{ entity = -7, x = b.B[1], y = b.B[2], z = b.B[3] },
		{ entity = -8, x = b.C[1], y = b.C[2], z = b.C[3] },
	}
	if not M.CROSS_LATER then
		nodes[#nodes + 1] = { entity = -9, x = b.L[1], y = b.L[2], z = b.L[3] }
		nodes[#nodes + 1] = { entity = -10, x = b.R[1], y = b.R[2], z = b.R[3] }
	end
	if b.W then nodes[#nodes + 1] = { entity = -11, x = b.W[1], y = b.W[2], z = b.W[3] } end
	for _, nd in ipairs(nodes) do
		nd.x, nd.y, nd.z = G.z0(G.round(nd.x, 3)), G.z0(G.round(nd.y, 3)), G.z0(G.round(nd.z, 3))
	end
	local pos = { [de[3]] = { de[1], de[2], b.hD } }
	for _, nd in ipairs(nodes) do pos[nd.entity] = { nd.x, nd.y, nd.z } end
	local edges = {}
	local total = 0
	local function edge(ent, n0, n1, key, class, bridge)
		local p0, p1 = pos[n0], pos[n1]
		local dx, dy, dz = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
		local L = math.sqrt(dx * dx + dy * dy)
		local t = v3(dx, dy, dz)
		edges[#edges + 1] = { entity = ent, node0 = n0, node1 = n1, p0 = v3(p0[1], p0[2], p0[3]), p1 = v3(p1[1], p1[2], p1[3]),
			t0 = t, t1 = { t[1], t[2], t[3] }, class = class, template = tpl, length = G.round(L, 3), key = key,
			bridge = bridge or nil, street = #edges + 1 }
		total = total + L
	end
	local k = "br:" .. tostring(de[3])
	local lock = { [k .. ":approach"] = true, [k .. ":span"] = true }
	if b.W then
		edge(-1, de[3], -11, k .. ":approach", "main")
		edge(-12, -11, -6, k .. ":approach2", "main")
		lock[k .. ":approach2"] = true
	else
		edge(-1, de[3], -6, k .. ":approach", "main")
	end
	edge(-2, -6, -7, k .. ":span", "main", true)
	edge(-3, -7, -8, k .. ":far", "main")
	if not M.CROSS_LATER then
		edge(-4, -8, -9, k .. ":crossL", "small")
		edge(-5, -8, -10, k .. ":crossR", "small")
	end
	local inc = { nodes = nodes, edges = edges, joins = { { node = de[3], edge = -1 } }, dropped = {},
		stats = { edges = #edges, nodes = #nodes, length = G.round(total, 1) } }
	return { inc = inc, span = b.span, approach = b.dA, far = b.far, deck = b.deck, deadEnd = de[3], heading = b.h, key = b.key,
		ship = b.ship or "none", shipWhy = b.shipWhy or "-", clearance = b.clearance,
		bowed = b.W ~= nil, lockKeys = lock }
end

return M
