-- Organic Towns: the landscape-aware skeleton (pure; §63, 2026-10-15; PLAN.md 6.2 "Landscape-aware skeleton").
--
-- User, after run 2026-10-15_0539_sqot (seed `a`, 1900, Quick 40 years): "it still seems like the towns take over
-- forest too quickly. the initial locked streets play an important part of the early growth, and they aren't drawn
-- aggressively enough in some situations. remember that roads built houses on them, which then take over the forest.
-- so ideally we take that into account when considering spacing".
--
-- A shaped town's arms (ot_shape: linear / ridge / cross / fingers) are its skeleton: their corridors cost least in
-- the selector (SH.distance), lead furthest (ot_select arm fronts), and their streets are locked (ot_driver lockKeys
-- "arm"). Houses fill along any street to lot depth (~36-40 m each side, ot_forest LOT_OFFSETS) and the game's
-- developer removes the trees under them, so an arm laid 30 m from a wood edge costs the wood. §62's landscape pull
-- only reordered pieces; the arms still went out at their seeded headings, into or along the woods.
--
-- Per arm, a survey along its heading from the town's edge (START_F x the houses' extent) SURVEY_M out, every STEP m:
-- the clearance = the distance from the centreline to the nearest dense forest cell (cover >= DENSE) on either side
-- (both sides' lots, as ot_forest.corridor), scanned to SCAN_M. The open run = how far the arm goes before the
-- clearance first drops under CLEAR_M (lot depth + a margin). Then per arm:
--   keep   open all the way (and `long`: lengthened, below)
--   bend   another heading runs BEND_GAIN_M further in the open (organic plans: an unused master-plan spoke within
--          BEND_MAX, the deep arms sit on spokes; other plans: BEND_STEPS turns; linear / ridge at most LINE_BEND_MAX)
--   short  the arm stops where its clearance runs out (shape.armMax: beyond it the corridor costs like the core and is
--          no arm, so not locked as one)
--   drop   an open run under MIN_ARM_M while the shape keeps MIN_ARMS
--   boxed  no alternative (every heading wooded, the shape at its minimum): kept as it was (a boxed-in town still
--          grows; the hug / deep per-piece logic does the rest)
-- Arms with a long open run get a longer reach and lead (shape.armK, up to 1 + LONG_MAX, + DROP_BONUS per dropped /
-- shortened arm, at most K_MAX), more where the §62 lean favours them: "drawn aggressively" into open land.
-- Exempt: deep forest towns (they live in the woods), metropolis variants and dev-forced shapes (the driver). Character
-- towns and site-picked arms (valley, ridge, coast, river, hillside: shape.site) keep their headings (no bend / drop;
-- shortened / lengthened only); strict grids don't bend. Every loop runs over the arms, the candidate headings and a
-- fixed number of survey steps.
-- Saved: the result is decided once, before the town's first build, and saved on its frame (`sk`, ot_saved) so the
-- skeleton never changes as the town clears trees; an older frame without `sk` keeps its arms exactly as before.
-- Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local LAND = ug_require "square_organic_towns::/organic_towns/ot_land.lua"

local M = {}

local cos, sin, abs, floor, max, min = math.cos, math.sin, math.abs, math.floor, math.max, math.min

M.ON = true
M.ARMED = { linear = true, ridge = true, cross = true, fingers = true }
M.DENSE = FO.FOREST_COVER      -- a cell this wooded is forest (0.5: ~24 trees / ha)
-- clearance: lot depth (36-40 m: 4 x 8 m lots, ot_style; ot_forest LOT_OFFSETS 20 / 36) + ~25-30 m margin (the grid's
-- 50 m cells are smoothed: one cell off the trees reads ~0.2, so the measured edge sits up to ~25 m off the real one)
M.CLEAR_M = 65
M.SCAN_M = 100                 -- m: the perpendicular scan reaches this far (a clearance of SCAN_M reads "open")
M.SCAN_STEP = 10
M.STEP = 25                    -- m between survey points along an arm
M.SURVEY_M = 900               -- m surveyed beyond the town's edge (the early arms reach ~400-700 m)
M.START_F = 0.8                -- the survey starts at this x the houses' extent radius ...
M.START_MIN = 100              -- ... at least this far (m; and at least one block)
M.MIN_ARM_M = 200              -- an open run under this is no arm
M.BEND_GAIN_M = 150            -- a bent heading must run this much further in the open
M.BEND_MAX = math.rad(75)      -- organic plans: a spoke within this of the arm (6 spokes: the neighbours, 60 deg)
M.LINE_BEND_MAX = math.rad(65) -- linear / ridge: one end turns at most this
M.BEND_STEPS = { math.rad(20), math.rad(40), math.rad(60) }   -- other plans: turns tried both ways
M.MIN_SEP = math.rad(35)       -- two arms never closer than this
M.LEAN_M = 150                 -- m of open run a full §62 lean (+1) is worth when headings are compared
M.MIN_ARMS = { linear = 1, ridge = 1, cross = 2, fingers = 3 }
M.LONG_RUN_F = 0.6             -- an open run over this x SURVEY_M lengthens the arm ...
M.LONG_MAX = 0.4               -- ... its reach x up to 1 + this (open all the way, the lean for it)
M.DROP_BONUS = 0.15            -- + this per dropped / shortened arm (the town's growth goes to its open arms)
M.K_MAX = 1.6
M.SAVE_MAX = 160               -- chars of the saved `sk` text at most
M.MAX_ARMS = 8

--- Clearance (m) at centreline point (x, y) with unit normal (nx, ny): the nearest offset on either side (0 = the
--- point itself) whose cover is at least DENSE, SCAN_M when none within the scan. The lots: both sides along the normal.
--- isWood (optional, §71): function(fg, x, y) -> bool in place of the plain dense test (ot_forest.bigWoodAt: the lock
--- policy's face rules count only woods big enough to matter).
local function denseAt(fg, x, y) return FO.cover(fg, x, y) >= M.DENSE end
M.denseAt = denseAt
function M.clearAt(fg, x, y, nx, ny, isWood)
	isWood = isWood or denseAt
	local n = floor(M.SCAN_M / M.SCAN_STEP)
	for k = 0, n do
		local o = k * M.SCAN_STEP
		if isWood(fg, x + nx * o, y + ny * o) or isWood(fg, x - nx * o, y - ny * o) then return o end
	end
	return M.SCAN_M
end

-- (§70, 2026-10-15; run 2026-10-15_2031_sqot: Two Waters' south grew into clearings between woods, each side farther
-- than CLEAR_M from its street) a narrow clearing: woods on BOTH sides of (x, y) across normal (nx, ny) within
-- CORRIDOR_W in all (each side scanned in CORRIDOR_STEP steps)
M.CORRIDOR_W = 220
M.CORRIDOR_STEP = 20

--- The width (m) of the clearing at (x, y) across normal (nx, ny) when woods stand on both sides within CORRIDOR_W in
--- all, else nil. isWood as M.clearAt's.
function M.corridorAt(fg, x, y, nx, ny, isWood)
	if fg == nil or fg.cover == nil then return nil end
	isWood = isWood or denseAt
	local n = floor(M.CORRIDOR_W / M.CORRIDOR_STEP)
	local d1, d2 = nil, nil
	for k = 0, n do
		local o = k * M.CORRIDOR_STEP
		if d1 == nil and isWood(fg, x + nx * o, y + ny * o) then d1 = o end
		if d2 == nil and isWood(fg, x - nx * o, y - ny * o) then d2 = o end
		if d1 and d2 then break end
	end
	if d1 and d2 and d1 + d2 <= M.CORRIDOR_W then return d1 + d2 end
	return nil
end

local R2 = math.sqrt(0.5)
--- The arm's clearance at (x, y) heading (ux, uy): clearAt plus ahead and the two forward diagonals (the street's tip
--- and corner lots; a wood edge met head-on or at a slant stops the arm CLEAR_M short of it). isWood as M.clearAt's.
function M.clearAhead(fg, x, y, ux, uy, isWood)
	isWood = isWood or denseAt
	local nx, ny = -uy, ux
	local best = M.clearAt(fg, x, y, nx, ny, isWood)
	local n = floor(math.min(best, M.SCAN_M) / M.SCAN_STEP)
	local dirs = { { ux, uy }, { (ux + nx) * R2, (uy + ny) * R2 }, { (ux - nx) * R2, (uy - ny) * R2 } }
	for k = 1, n do
		local o = k * M.SCAN_STEP
		if o >= best then break end
		for _, d in ipairs(dirs) do
			if isWood(fg, x + d[1] * o, y + d[2] * o) then return o end
		end
	end
	return best
end

--- Survey of heading a from (cx, cy), r0 .. r0 + SURVEY_M: { run = open run (m from r0), clear = the least clearance
--- over the open run (SCAN_M: open), wood = mean cover on the centreline over the whole survey }.
function M.survey(fg, cx, cy, a, r0)
	local ux, uy = cos(a), sin(a)
	local steps = floor(M.SURVEY_M / M.STEP)
	local run, least, blocked, wood = M.SURVEY_M, M.SCAN_M, false, 0
	for k = 0, steps do
		local s = r0 + k * M.STEP
		local x, y = cx + ux * s, cy + uy * s
		wood = wood + FO.cover(fg, x, y)
		if not blocked then
			local c = M.clearAhead(fg, x, y, ux, uy)
			if c < M.CLEAR_M then
				run, blocked = k * M.STEP, true
			elseif c < least then
				least = c
			end
		end
	end
	return { run = run, clear = least, wood = wood / (steps + 1) }
end

local function deg(a) return floor(math.deg(a) % 360 + 0.5) % 360 end

--- The skeleton for a shape: nil when it has no arms to steer (or no grid); else { arms = { { a, a0, act, run, clear,
--- k, max, why } } (the kept arms, in order), dropped = { { a0, why } }, boxed = n, mode, why }. o = { fg (the tree
--- grid, ot_forest), field (ot_land, §62; nil: none), deep (bool), extR (the houses' extent radius, m), thetas (the
--- master plan's spoke headings for organic plans, or nil), strict (a strict grid: no bending), char (a character
--- town), site (site-picked arms: no bend / drop) }.
function M.plan(shape, o)
	if not M.ON or shape == nil or not M.ARMED[shape.id] or shape.arms == nil or #shape.arms == 0 then return nil end
	o = o or {}
	local fg = o.fg
	if fg == nil or fg.cover == nil then return nil end
	local cx, cy = shape.centre[1], shape.centre[2]
	local res = { arms = {}, dropped = {}, boxed = 0, mode = "forest" }
	local n0 = math.min(#shape.arms, M.MAX_ARMS)
	if o.deep then
		res.mode, res.why = "deep", "deep"
		for i = 1, n0 do
			local a = shape.arms[i]
			res.arms[i] = { a = a, a0 = a, act = "deep", run = nil, clear = nil, k = 1 }
		end
		return res
	end
	local r0 = max(M.START_MIN, shape.block or 0, M.START_F * (tonumber(o.extR) or 0))
	res.r0 = r0
	local cache = {}
	local function sv(a)
		local key = floor(G.wrap(a) * 1000 + 0.5)
		local s = cache[key]
		if s == nil then
			s = M.survey(fg, cx, cy, a, r0)
			s.score = s.run + M.LEAN_M * LAND.at(o.field, a)
			cache[key] = s
		end
		return s
	end
	local noTurn = o.char or o.site or shape.site
	local line = shape.id == "linear" or shape.id == "ridge"
	-- every arm's own survey first
	local list = {}
	for i = 1, n0 do
		local a = shape.arms[i]
		local s = sv(a)
		list[i] = { a = a, a0 = a, run = s.run, clear = s.clear, act = s.run >= M.SURVEY_M and "keep" or nil, k = 1, i = i }
	end
	local function farFromOthers(a, self)
		for _, e in ipairs(list) do
			if e ~= self and not e.drop and G.angleDiff(e.a, a) < M.MIN_SEP then return false end
		end
		return true
	end
	-- bend the blocked arms (worst first) toward a heading that runs further in the open
	if not noTurn and not o.strict then
		local order = {}
		for _, e in ipairs(list) do if e.act == nil then order[#order + 1] = e end end
		table.sort(order, function(p, q) if p.run ~= q.run then return p.run < q.run end return p.i < q.i end)
		for _, e in ipairs(order) do
			local cands = {}
			local lim = line and M.LINE_BEND_MAX or M.BEND_MAX
			if o.thetas then
				for _, t in ipairs(o.thetas) do
					local d = G.angleDiff(t, e.a0)
					if d > 1e-3 and d <= lim then cands[#cands + 1] = { a = t, d = d } end
				end
			else
				for _, st in ipairs(M.BEND_STEPS) do
					if st <= lim + 1e-9 then
						cands[#cands + 1] = { a = G.wrap(e.a0 + st), d = st }
						cands[#cands + 1] = { a = G.wrap(e.a0 - st), d = st }
					end
				end
			end
			local best, bs = nil, sv(e.a0).score + M.BEND_GAIN_M
			for _, c in ipairs(cands) do
				local s = sv(c.a)
				if s.run >= M.MIN_ARM_M and farFromOthers(c.a, e) and (s.score > bs + 1e-9 or (best and abs(s.score - bs) < 1e-9 and c.d < best.d)) then
					best, bs = c, s.score
				end
			end
			if best then
				local s = sv(best.a)
				e.a, e.run, e.clear, e.act = best.a, s.run, s.clear, "bend"
				e.why = "wood:" .. deg(e.a0)
			end
		end
	end
	-- shorten or drop the arms still blocked (worst first); a shape at its minimum keeps them (boxed)
	local minArms = M.MIN_ARMS[shape.id] or 1
	local alive = #list
	local order = {}
	for _, e in ipairs(list) do if e.act == nil or (e.act == "bend" and e.run < M.SURVEY_M) then order[#order + 1] = e end end
	table.sort(order, function(p, q) if p.run ~= q.run then return p.run < q.run end return p.i < q.i end)
	local cut = 0
	-- (an arm is dropped only while another runs at least MIN_ARM_M in the open: else every arm is boxed)
	local anyOpen = false
	for _, e in ipairs(list) do if e.run >= M.MIN_ARM_M then anyOpen = true end end
	for _, e in ipairs(order) do
		if e.run >= M.MIN_ARM_M then
			if e.act == nil then e.act = "short" end
			e.max = r0 + e.run
			e.why = e.why or "wood"
			cut = cut + 1
		elseif not o.char and anyOpen and alive > minArms then
			e.drop, e.act, e.why = true, "drop", "wood"
			alive = alive - 1
			cut = cut + 1
		else
			e.act = "boxed"
			e.why = o.char and "intent" or "noAlternative"
			res.boxed = res.boxed + 1
		end
	end
	-- lengthen the open arms (more with the lean, more when others were cut)
	for _, e in ipairs(list) do
		if not e.drop and e.act ~= "boxed" then
			local f = G.clamp((e.run / M.SURVEY_M - M.LONG_RUN_F) / (1 - M.LONG_RUN_F), 0, 1)
			local lean = LAND.at(o.field, e.a)
			local k = 1 + M.LONG_MAX * f * G.clamp(0.6 + 0.4 * lean, 0.2, 1) + M.DROP_BONUS * cut * f
			e.k = math.min(M.K_MAX, k)
			if e.k > 1.005 and (e.act == "keep") then e.act = "long" end
		end
	end
	for _, e in ipairs(list) do
		if e.drop then
			res.dropped[#res.dropped + 1] = { a0 = e.a0, why = e.why, run = e.run }
		else
			res.arms[#res.arms + 1] = { a = e.a, a0 = e.a0, act = e.act or "keep", run = e.run, clear = e.clear, k = e.k,
				max = e.max, why = e.why }
		end
	end
	res.why = res.boxed > 0 and "boxed" or ((#res.dropped > 0 or cut > 0) and "wood" or "open")
	return res
end

--- Puts the skeleton on the shape: arms (headings), armK (reach / lead x, per arm), armMax (along-distance cap, m, per
--- arm). A deep result changes nothing. Returns the shape.
function M.apply(shape, res)
	if shape == nil or res == nil or res.mode == "deep" or #res.arms == 0 then return shape end
	local arms, ks, mx = {}, {}, {}
	local anyK, anyM = false, false
	for i, e in ipairs(res.arms) do
		arms[i] = e.a
		ks[i] = e.k or 1
		mx[i] = e.max or false
		if ks[i] ~= 1 then anyK = true end
		if e.max then anyM = true end
	end
	shape.arms = arms
	shape.armK = anyK and ks or nil
	shape.armMax = anyM and mx or nil
	shape.skel = res
	return shape
end

--- The saved `sk` text: "<heading deg x 10>:<k x 100>:<max m, 0 none>" per kept arm, joined by ";" (nil for none / deep).
function M.encode(res)
	if res == nil or res.mode == "deep" or #res.arms == 0 then return nil end
	local parts = {}
	for i, e in ipairs(res.arms) do
		if i > M.MAX_ARMS then break end
		parts[#parts + 1] = string.format("%d:%d:%d", floor((math.deg(e.a) % 360) * 10 + 0.5) % 3600,
			floor((e.k or 1) * 100 + 0.5), e.max and floor(e.max + 0.5) or 0)
	end
	local s = table.concat(parts, ";")
	if #s > M.SAVE_MAX then return nil end
	return s
end

--- A saved `sk` text back into a result ({ arms, dropped = {}, boxed = 0, mode = "saved" }), nil when malformed. thetas:
--- the plan's spoke headings (organic plans): a heading within 1 deg of a spoke snaps onto it (the deep arms' match).
function M.decode(s, thetas)
	if type(s) ~= "string" or #s == 0 or #s > M.SAVE_MAX or s:find("[^%d:;]") then return nil end
	local arms = {}
	for part in s:gmatch("[^;]+") do
		if #arms >= M.MAX_ARMS then break end
		local h, k, m = part:match("^(%d+):(%d+):(%d+)$")
		if h == nil then return nil end
		local a = G.wrap(math.rad(tonumber(h) / 10))
		for _, t in ipairs(thetas or {}) do
			if G.angleDiff(t, a) < math.rad(1) then a = t break end
		end
		local kk = tonumber(k) / 100
		if not (kk >= 0.5 and kk <= 2) then return nil end
		local mm = tonumber(m)
		arms[#arms + 1] = { a = a, a0 = a, act = "saved", k = kk, max = (mm and mm > 0) and mm or nil }
	end
	if #arms == 0 then return nil end
	return { arms = arms, dropped = {}, boxed = 0, mode = "saved", why = "saved" }
end

--- SKEL `arms=` text: "<deg>:<act>:<run m or ->:<least clearance m or ->:k<x>" per kept arm joined by "/", with
--- ":from<deg>" for a bent arm and ":max<m>" for a shortened one; "-" for none.
function M.armsText(res)
	if res == nil or #res.arms == 0 then return "-" end
	local parts = {}
	for _, e in ipairs(res.arms) do
		local p = string.format("%d:%s:%s:%s:k%.2f", deg(e.a), e.act or "keep", e.run and string.format("%.0f", e.run) or "-",
			e.clear and string.format("%.0f", e.clear) or "-", e.k or 1)
		if e.a0 and G.angleDiff(e.a0, e.a) > 1e-3 then p = p .. ":from" .. deg(e.a0) end
		if e.max then p = p .. string.format(":max%.0f", e.max) end
		parts[#parts + 1] = p
	end
	return table.concat(parts, "/")
end

--- SKEL `dropped=` text: "<deg>:<why>:<run m>" joined by "/", "-" for none.
function M.droppedText(res)
	if res == nil or #res.dropped == 0 then return "-" end
	local parts = {}
	for _, d in ipairs(res.dropped) do parts[#parts + 1] = string.format("%d:%s:%.0f", deg(d.a0), d.why or "-", d.run or 0) end
	return table.concat(parts, "/")
end

--- The least clearance (m) of the kept arms that were surveyed ("-" for none): SKEL `minClear=`.
function M.minClear(res)
	local m = nil
	for _, e in ipairs(res and res.arms or {}) do
		if e.clear and e.act ~= "boxed" and (m == nil or e.clear < m) then m = e.clear end
	end
	return m
end

---------------------------------------------------------------------------
-- points: lobes / hotspots of unshaped towns, satellite sites

M.POINT_R = 120               -- m: a hotspot / lobe pulls the streets within about this of it
M.POINT_TURNS = { math.rad(20), math.rad(40), math.rad(60) }
M.POINT_SHRINK = { 0.75, 0.55 }

--- The least clearance around a point: the nearest dense cell within POINT_R + CLEAR_M along 8 rays (m), SCAN_M +
--- POINT_R when none. A hotspot / site is clear when this is at least POINT_R + CLEAR_M x 0.5. isWood as M.clearAt's.
function M.pointClear(fg, x, y, isWood)
	isWood = isWood or denseAt
	local reach = M.POINT_R + M.CLEAR_M
	local n = floor(reach / M.SCAN_STEP)
	local best = reach
	for d = 0, 7 do
		local a = d * math.pi / 4
		local ux, uy = cos(a), sin(a)
		for k = 0, n do
			local o = k * M.SCAN_STEP
			if o >= best then break end
			if isWood(fg, x + ux * o, y + uy * o) then
				best = o
				break
			end
		end
	end
	return best
end

function M.pointOk(fg, x, y)
	return M.pointClear(fg, x, y) >= M.POINT_R + 0.5 * M.CLEAR_M
end

--- A hotspot at heading a, radius r from (cx, cy) moved off the woods: the first of the turns (both ways) and shrinks
--- whose point is clear, else the original. Returns x, y, moved (bool).
function M.movePoint(fg, cx, cy, a, r)
	local x, y = cx + r * cos(a), cy + r * sin(a)
	if fg == nil or fg.cover == nil or M.pointOk(fg, x, y) then return x, y, false end
	for _, f in ipairs({ 1, M.POINT_SHRINK[1], M.POINT_SHRINK[2] }) do
		for _, t in ipairs(M.POINT_TURNS) do
			for _, sgn in ipairs({ 1, -1 }) do
				local b = a + sgn * t
				local px, py = cx + r * f * cos(b), cy + r * f * sin(b)
				if M.pointOk(fg, px, py) then return px, py, true end
			end
		end
		if f ~= 1 then
			local px, py = cx + r * f * cos(a), cy + r * f * sin(a)
			if M.pointOk(fg, px, py) then return px, py, true end
		end
	end
	return x, y, false
end

return M
