-- Organic Towns: green wedges that survive growth (pure; 2026-10-13, real map round 4).
--
-- Real map run 2026-10-13_0232_sqot-dev (towns grew ~9x): at 1000-3500 buildings the linear, fingers and radiating
-- towns (Harwich, Holsworthy, Bingley, Bootle) read as one organic blob. The game still built ~60 % of the new streets,
-- from its own unlocked core streets (their dead ends at the core rim face every direction, the wedges between the
-- arms too), and the mod's own planner filled the wedges as well once the envelope (area-preserving, ot_select) grew
-- past them. Two levers, both for the armed shapes (linear, ridge, cross, fingers; style.wedges set by the driver):
--
-- * Wedge reserve (M.inWedge, ot_select): outside the core zone (M.coreR: the shape's core circle at the envelope
--   level, x CORE_PAD) and outside every arm corridor (ot_shape.inArm) the mod plans nothing, never relaxed. The core
--   zone grows with the envelope (the town's street length), so the wedges keep their proportion as the town grows.
-- * Wedge frame (M.frameStreets / M.frameIncrement): the game's growth comes from unlocked dead ends (findings
--   towns.md: towns hang their streets on free dead ends, attach 0-1 side streets to locked ones). At a demand build the
--   driver links the unlocked dead ends that lie in a wedge (beyond MIN_R_K x the core zone, not yet inside a frame (a
--   locked street within INSIDE_RAY outward)) in angular order, wedge by wedge, with one locked small street each (LINK_MIN..
--   LINK_MAX m): a ring road along the town's edge on the wedge sides. The game's tips there are consumed (no free dead
--   end faces the wedge) and a new game street would have to cross the locked frame, so its growth stays inside (the
--   core fills denser) while the mod's arms carry the town outward. The frame's outer side gets houses like any locked
--   street; it sits at the game's tips, so no empty ring runs ahead of the houses (the lead rule's housed index holds it
--   within LEAD_M of a housed street).
-- Plain base town streets, locked like the arms (removing the mod leaves ordinary, locked streets). Nothing saved: the
-- frame is found again from the locked streets of the snapshot after a reload.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local A = ug_require "square_organic_towns::/organic_towns/ot_assess.lua"

local M = {}

M.ON = true
-- (shore: 2026-10-13 final-test round: the strip along the water is the arm, the land beyond the depth cap (off the link
-- from the centre to the shore) the wedge; the frame chains the town's inland tips so the game's growth stays in)
M.IDS = { linear = true, ridge = true, cross = true, fingers = true, shore = true }
M.SHORE_LINK = 1.0         -- x block: a shore town's link corridor (centre -> its foot on the shore) is no wedge
M.CORE_PAD = 1.15          -- the core zone reaches this x the shape's core circle at the envelope level
M.CORE_MIN_M = 180         -- ... at least this
M.MIN_R_K = 0.6            -- frame: dead ends beyond this x the core zone radius count ...
M.INSIDE_RAY = 350         -- m: a tip whose outward ray meets a locked street within this is inside a frame already
                           -- (tips in the arm corridors count too: a gap beside the arm's spine let the game's streets
                           -- run out along the arm and then sideways, offline)
M.GATE_M = 70              -- m: tips this close to an arm's axis (ahead of the centre) stay free: the arm's seed
M.TAIL_GAP = 45            -- m: a chain's end tip gets a locked tail toward its wedge's arm axis, stopping this short
M.TAIL_MIN, M.TAIL_MAX = 30, 160   -- m: tail length range
M.LINK_MIN, M.LINK_MAX = 25, 280   -- m: a frame link between two neighbouring tips
M.LEAD_M = 250             -- m: every frame link's ends within this of a housed street (with house data)
-- (§59) a link the ring lead holds still comes when it is at most FAR_LINK_M long and no point of it lies farther from the
-- houses than its farther tip (+ FAR_SLACK_M): short closures between the game's tips (see frameStreets)
M.FAR_LINK_M = 160
M.FAR_SLACK_M = 15
M.MIN_LINKS = 2            -- a frame increment needs at least this many links
M.MAX_EDGES = 48           -- edges per frame increment (24 cut the first frame short: the game ran out through the gap)
M.EVERY = 1                -- at most every this many demand builds of a town one goes to the frame
-- Frame tip cap (§75 follow-up "Far-out streets after an extent jump", 2026-10-20): the frame had a floor (MIN_R_K x
-- the core zone) and the housed test (LEAD_M) but no outer limit, so once the game's growth put an outlying group of a
-- town's houses 0.7-1.2 km out (runs 2026-10-19_1949 / 2026-10-20_0205: CHECK r jumped 478 -> 1070, 682 -> 998 m) its
-- dead ends there were tips like any other (Merehythe / Dovemouth frame pieces ~950 m out). A tip farther from the frame
-- centre than tipCap = the main body's reach + TIP_LEAD_M is dropped before linking (M.lastTipCut; FRAME tipCut= /
-- maxTipR= / tipCap=). The main body (ot_assess.body: the houses on 100 m cells flood-filled across gaps up to 200 m,
-- the largest group) is read from the snapshot's housed streets (midpoints, e.built houses each); its reach is its
-- farthest house from the centre. A tip needs a housed street within LEAD_M anyway, so a town that is one body never
-- loses a tip (the cap lies beyond every tip it has: offline, test_bigform / test_spread towns, 0 of 289 frames
-- changed); only tips beyond the body's reach, i.e. at an outlying group's houses, go. Not a multiple of a radius: the
-- game's tips run up to LEAD_M ahead of the houses, up to 2.5 x the 75 % house radius and 2.2 x env offline, so a cap
-- of ~1.3 x any radius either cut normal frames (q75 x 1.6: 56 of 272 calls) or let the outlying group through; env (the
-- street-length envelope level) is an effective distance whose plain reach differs by shape and is low in the wedges.
-- PLAN.md 6.2 §75 "Far-out streets after an extent jump" has the numbers.
M.TIP_CAP = true
M.TIP_LEAD_M = 300         -- m: beyond the body's farthest house (LEAD_M + 50 m: the tip's street half length)
M.TIP_EDGES_MAX = 4000     -- body: at most this many edges read (every k-th beyond)
M.FRAME_AND_BUILD = true   -- a frame build serves no demand: the town's normal build follows (the driver's "more" re-check)

--- Does the wedge rule apply to this style? (armed shape, not a metropolis or a mech grid style, M.ON)
function M.applies(style)
	if not M.ON or style == nil then return false end
	local sh = style.shape
	if sh == nil or not M.IDS[sh.id or ""] then return false end
	if style.metro or style.mech then return false end
	return true
end

--- Core zone radius (m) of a shape at envelope level env (ot_select.envelopeCap): the shape's core circle (radius
--- level / cf; fingers: its core of `core` blocks, beyond it the wedge factor), x CORE_PAD.
function M.coreR(shape, env)
	if shape == nil or env == nil then return nil end
	local g = SH.GEOM[shape.id]
	if g == nil or g.cf == nil then return nil end
	local r = env / g.cf
	if shape.id == "fingers" then
		local rc = g.core * (shape.block or 100)
		if env > rc * g.cf then r = rc + (env - rc * g.cf) / (g.cf * g.wedge) end
	end
	return math.max(M.CORE_MIN_M, r * M.CORE_PAD)
end

--- true when (x, y) lies in a green wedge: beyond the core zone radius coreR and outside every arm corridor.
function M.inWedge(shape, x, y, coreR)
	if shape == nil or coreR == nil then return false end
	local cx, cy = shape.centre[1], shape.centre[2]
	if G.dist(cx, cy, x, y) <= coreR then return false end
	if shape.id == "shore" then
		-- (the whole strip within the depth cap, also at the foot where SH.inArm's along > block doesn't hold, and the link)
		local sd = shape.shore
		if sd == nil then return false end
		local _, perp, wet = SH.shoreAt(sd, x, y)
		if wet or perp <= sd.depthCap then return false end
		if G.pointSegDist(x, y, cx, cy, sd.foot[1], sd.foot[2]) <= M.SHORE_LINK * (shape.block or 100) then return false end
		return true
	end
	return not SH.inArm(shape, x, y)
end

--- true when any point of the polyline (or its midpoint) lies in a wedge.
function M.polyInWedge(shape, pts, coreR)
	if coreR == nil then return false end
	local mx, my = G.polyAt(pts, 0.5)
	if M.inWedge(shape, mx, my, coreR) then return true end
	for _, p in ipairs(pts) do
		if M.inWedge(shape, p[1], p[2], coreR) then return true end
	end
	return false
end

--- true when (x, y) lies on an arm's gate: ahead of the centre and within GATE_M of the arm's axis (the tip there is
--- the arm's seed: never chained into a frame, or the arm could not grow out of the core; offline the linear town's
--- second arm stayed shut).
function M.atGate(shape, x, y)
	local cx, cy = shape.centre[1], shape.centre[2]
	for _, a in ipairs(shape.arms or { shape.axis }) do
		local ca, sa = math.cos(a), math.sin(a)
		local along = (x - cx) * ca + (y - cy) * sa
		if along > 0 and math.abs(-(x - cx) * sa + (y - cy) * ca) <= M.GATE_M then return true end
	end
	return false
end

--- The frame tip cap (m from (cx, cy)) for g: the main body's reach (ot_assess.body over the housed streets'
--- midpoints, e.built houses each; at most TIP_EDGES_MAX edges) + TIP_LEAD_M, and the body; nil when off or without
--- house data.
function M.tipCap(g, cx, cy)
	if not M.TIP_CAP or g == nil or not g.hasBuilt or #g.edges == 0 then return nil end
	local stride = math.max(1, math.ceil(#g.edges / M.TIP_EDGES_MAX))
	local pts = {}
	for i = 1, #g.edges, stride do
		local e = g.edges[i]
		local w = e.built or 0
		if w > 0 then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then pts[#pts + 1] = { (a.x + b.x) / 2, (a.y + b.y) / 2, w } end
		end
	end
	local body = A.body(pts, { cx = cx, cy = cy })
	if body == nil or body.reachC == nil then return nil end
	return body.reachC + M.TIP_LEAD_M, body
end

local function wedgeIndex(arms, a)
	-- arms sorted by heading; the wedge between arms[i] and arms[i + 1] (wrapping) is index i
	local n = #arms
	if n == 0 then return 1, a end
	for i = 1, n do
		local a0, a1 = arms[i], arms[i % n + 1]
		local span = (a1 - a0) % (2 * math.pi)
		if span == 0 then span = 2 * math.pi end
		local rel = (a - a0) % (2 * math.pi)
		if rel < span then return i, rel end
	end
	return 1, (a - arms[1]) % (2 * math.pi)
end

--- Streets of a wedge frame for graph g (ot_plan input: startNode / endNode joins, key "frame:a:b", class small) or
--- {} and why. o = { coreR, housedIdx (ot_select.housedIndexM or nil), maxLinks, maxTipR (m from the centre: farther
--- tips dropped, M.lastTipCut; M.lastMaxTipR the farthest tip kept), accept = fn(x, y) (only tips it
--- accepts: ot_meadow's sectors), noTails (no tails toward the arm axes: a meadow frame leaves the lobes free) }. Candidates: dead ends (degree 1,
--- joinable: not noJoin), their street not locked, beyond MIN_R_K x coreR and not inside a frame (a locked street
--- within INSIDE_RAY on the ray outward); linked in angular order within each wedge.
function M.frameStreets(g, shape, o)
	o = o or {}
	local coreR = o.coreR
	M.lastTipCut, M.lastMaxTipR, M.lastCutMaxR = 0, 0, 0
	if shape == nil or coreR == nil or g == nil or #g.edges == 0 then return {}, "noShape" end
	local cx, cy = shape.centre[1], shape.centre[2]
	-- (a tip already inside a frame: the ray from it outward meets a locked street within INSIDE_RAY)
	local function insideLocked(x, y)
		local d = G.dist(cx, cy, x, y)
		if d < 1e-6 then return true end
		local ox, oy = x + (x - cx) / d * M.INSIDE_RAY, y + (y - cy) / d * M.INSIDE_RAY
		-- (the graph's edge hash: only edges near the ray)
		for _, id in ipairs(OG.edgesNear(g, x, y, ox, oy, 1)) do
			local e = g.edgeById[id]
			if e.locked then
				local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
				if a and b and G.segIntersect(x, y, ox, oy, a.x, a.y, b.x, b.y, 1e-4) then return true end
			end
		end
		return false
	end
	local arms = {}
	for _, a in ipairs(shape.arms or { shape.axis }) do arms[#arms + 1] = a % (2 * math.pi) end
	table.sort(arms)
	local byWedge = {}
	local nCand = 0
	for _, id in ipairs(OG.deadEnds(g)) do
		local node = g.nodeById[id]
		local e = g.edgeById[g.adj[id][1]]
		if node and not node.noJoin and e and not e.locked then
			local r = G.dist(cx, cy, node.x, node.y)
			if r >= M.MIN_R_K * coreR and not M.atGate(shape, node.x, node.y)
				and (o.accept == nil or o.accept(node.x, node.y))
				and (o.housedIdx == nil or o.housedDist(o.housedIdx, node.x, node.y) <= M.LEAD_M)
				and not insideLocked(node.x, node.y) then
				if o.maxTipR and r > o.maxTipR then
					-- (beyond the tip cap: an outlying group's tip, not the town's edge)
					M.lastTipCut = M.lastTipCut + 1
					if r > M.lastCutMaxR then M.lastCutMaxR = r end
				else
					if r > M.lastMaxTipR then M.lastMaxTipR = r end
					local wi, rel = wedgeIndex(arms, G.atan2(node.y - cy, node.x - cx))
					byWedge[wi] = byWedge[wi] or {}
					local l = byWedge[wi]
					l[#l + 1] = { node = node, rel = rel, r = r }
					nCand = nCand + 1
				end
			end
		end
	end
	if nCand < 2 then return {}, "fewTips", nCand end
	local streets = {}
	local wis = {}
	for wi in pairs(byWedge) do wis[#wis + 1] = wi end
	table.sort(wis)
	for _, wi in ipairs(wis) do
		local l = byWedge[wi]
		table.sort(l, function(p, q)
			if p.rel ~= q.rel then return p.rel < q.rel end
			return p.node.id < q.node.id
		end)
		-- tails: from the first and last tip toward the arm axis bounding the wedge (closes the gap beside the arm)
		local nArms = #arms
		if nArms > 0 and not o.noTails then
			for side = 1, 2 do
				local c = side == 1 and l[1] or l[#l]
				local ah = side == 1 and arms[wi] or arms[wi % nArms + 1]
				local ux, uy = math.cos(ah), math.sin(ah)
				local dx, dy = c.node.x - cx, c.node.y - cy
				local along = dx * ux + dy * uy
				if along > 0 then
					local fx, fy = cx + ux * along, cy + uy * along
					local d = G.dist(c.node.x, c.node.y, fx, fy)
					local len = math.min(M.TAIL_MAX, d - M.TAIL_GAP)
					if len >= M.TAIL_MIN and not (side == 2 and #l == 1) then
						local tx, ty = c.node.x + (fx - c.node.x) / d * len, c.node.y + (fy - c.node.y) / d * len
						streets[#streets + 1] = { pts = { { c.node.x, c.node.y }, { tx, ty } }, class = "small",
							startNode = c.node.id, key = "frame:tail:" .. c.node.id, frame = true, tail = true }
					end
				end
			end
		end
		for i = 2, #l do
			local a, b = l[i - 1].node, l[i].node
			local d = G.dist(a.x, a.y, b.x, b.y)
			if d >= M.LINK_MIN and d <= M.LINK_MAX then
				streets[#streets + 1] = { pts = { { a.x, a.y }, { b.x, b.y } }, class = "small", startNode = a.id, endNode = b.id,
					key = "frame:" .. a.id .. ":" .. b.id, frame = true }
				if o.maxLinks and #streets >= o.maxLinks then return streets, nil, nCand end
			end
		end
	end
	-- (the ring lead, 2026-10-14 §57 round 3: in-game run 2026-10-15_0234 the EU organic town's wedge frame, 35 edges at
	-- once, ran as one empty loop round the town far beyond its houses: its links join tips within LEAD_M, but a straight
	-- link of up to LINK_MAX m runs on through empty land between them. Every point of a link or tail now lies within
	-- o.ringLead (ot_select RING_LEAD_M, 160 m) of a street with houses, like the ring arcs and the ring road)
	if o.ringLead and o.housedIdx then
		local kept, held, short = {}, 0, 0
		for _, st in ipairs(streets) do
			local a, b = st.pts[1], st.pts[#st.pts]
			local far = 0
			for k = 0, 4 do
				local f = k / 4
				far = math.max(far, o.housedDist(o.housedIdx, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f))
			end
			if far <= o.ringLead then
				kept[#kept + 1] = st
			else
				-- (2026-10-15 §59: most held links were held by their own far tip, 160-250 m from the houses, not by a
				-- stretch through empty land between the tips; held, both tips stayed free and the game's streets ran out
				-- from them into the wedge (test_bigform's fingers town: wedge share at 10x 0.34 vs 0.35 without wedges). A
				-- short link (FAR_LINK_M) between two tips still comes when no point of it lies farther from the houses
				-- than its farther tip (+ FAR_SLACK_M): it closes the wedge where the game's tips already are and runs no
				-- farther out. Long links and tails keep the ring lead.)
				local len = G.dist(a[1], a[2], b[1], b[2])
				local tipFar = math.max(o.housedDist(o.housedIdx, a[1], a[2]), o.housedDist(o.housedIdx, b[1], b[2]))
				if M.FAR_LINK_M and not st.tail and st.endNode and len <= M.FAR_LINK_M and tipFar <= M.LEAD_M
					and far <= tipFar + M.FAR_SLACK_M then
					kept[#kept + 1] = st
					short = short + 1
				else
					held = held + 1
				end
			end
		end
		streets = kept
		M.lastHeld, M.lastShort = held, short
	end
	local links = 0
	for _, st in ipairs(streets) do if not st.tail then links = links + 1 end end
	if links + 0.5 * (#streets - links) < M.MIN_LINKS then return streets, "fewLinks", nCand end
	return streets, nil, nCand
end

return M
