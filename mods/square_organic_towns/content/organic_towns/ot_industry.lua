-- Organic Towns: away from industries (pure). User 2026-10-12: "Is it also possible to make it so cities build away
-- from factories?" -> "At least have a preference away." A soft cost (and, since 2026-10-13, a hard keep-clear zone
-- the size of the industry's largest footprint, see M.ZONE): the mod's own street growth
-- prefers land away from the industries near a town (heavier industries push harder and farther), and a town boxed
-- in by them still grows (the costs only reorder; the envelope relaxation and the planner's fallbacks stay).
--
-- Input: the map's industries as plain records { x, y, file } (ot_engine.industries: every INDUSTRY component entity,
-- its construction's CONSTRUCTION.fileName, its BOUNDING_VOLUME centre; read like the base statistics window and
-- square_industry_flows). M.forTown keeps the ones near a town, classified by file name (M.PATTERNS), weighted by the
-- era (M.strength: before ~1920 worker housing beside the works is realistic, so the preference is weaker).
--
-- Where it applies (PLAN.md 6.3 "Away from industries"):
--   ot_select cost      x (1 + COST_K x pen(x, y))   pen = era x min(PEN_CAP, sum w x exp(-FALL x (d / r)^2))
--   ot_select hold      pieces with pen >= HOLD_PEN wait while the increment can fill elsewhere (the last relaxation)
--   ot_select envelope  the effective distance x (1 + ENV_K x pen) for the envelope check only (the envelope leans
--                       away; an under-filled increment widens it as before)
--   ot_select sector    the seeded sector preference / hotspots of unshaped towns lean along M.away (like the coast
--                       lean, opposite sign)
--   ot_shape axis       a seeded shape axis turns so its arms point away (M.bestAxis; site / saved axes unchanged)
--   ot_driver fill      DevelopAt dose points avoid the buffers when the build has points outside them
-- Plus a hard rule since 2026-10-13 (keep-clear zones, M.ZONE below: field industries grow into free slots around them
-- and a town grown round one caps it): ot_select never takes a piece whose street or lots enter a zone (PLAN
-- `zoneHeld=`), the driver refuses any other plan that would (satellites, lanes ahead, Works links: `industryZone`),
-- drops dose points in a zone and locks its new streets within ZONE_LOCK_M of one (PLAN `zoneLock=`).
-- Nothing is saved: existing towns get the preference from the next load on (frames keep their axis).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

M.ON = true
M.SEARCH_R = 1500     -- m from the town centre: industries farther away are ignored (beyond any buffer of its streets)
M.PEN_CAP = 1.25      -- the summed penalty at most this (several works side by side)
M.FALL = 1.5          -- pen = w x exp(-FALL x (d / r)^2): 0.22 w at the buffer radius, 0.69 w at half of it
M.COST_K = 1.6        -- select cost x (1 + COST_K x pen): next to a heavy works a piece costs ~2.6x (as if 2.6x farther)
M.ENV_K = 0.5         -- envelope check: effective distance x (1 + ENV_K x pen)
M.IRR_K = 0.5         -- unshaped towns: the away direction's weight in the sector preference at most this
M.AXIS = true         -- ot_shape: a seeded shape axis may turn away
M.AXIS_GAIN = 0.03    -- a turned shape axis must lower the arm exposure by at least this (else the seeded axis stays)
M.AXIS_REACH = 700    -- m: arm exposure sampled along each arm out to this
M.FILL_AVOID = true   -- dose points inside a buffer only when the build has none outside
M.HOLD_PEN = 0.45     -- ot_select: pieces with at least this penalty wait while the increment fills elsewhere (heavy
                      -- works: within ~0.7 x r; light ones never; before ~1900 none); they come when it would starve
M.HOLD_STEP = 0.25    -- ... a step of this at a time (least exposed first)
M.HOLD_FIRST = false  -- ... before the other limits widen (true) or as the last relaxation (false; offline: Nordic / NA grid better)
M.HOLD_FILL = 0.34    -- ... only while the increment has less than this share of its edges (0.6: no effect on grids)

-- kinds: w = weight at the works, r = buffer radius (m)
M.KINDS = {
	heavy = { w = 1.0, r = 500 },
	medium = { w = 0.75, r = 400 },
	light = { w = 0.5, r = 320 },
}

-- file name patterns (plain substrings of the lower-case CONSTRUCTION.fileName), first match wins. "ignore": no
-- nuisance on land (offshore platforms, a resort). Base game industries: base/content/industries/*; campaign ones
-- from mods/release; common community names. Anything else is "medium" and logged once (driver IND unknown).
M.PATTERNS = {
	{ "oil_platform", "ignore" }, { "resort", "ignore" }, { "toilet", "ignore" }, { "tunnel", "ignore" },
	{ "industries/track", "ignore" },
	{ "steel_mill", "heavy" }, { "steel", "heavy" }, { "chemical", "heavy" }, { "refinery", "heavy" },
	{ "coal_mine", "heavy" }, { "iron_ore", "heavy" }, { "quarry", "heavy" }, { "cement", "heavy" },
	{ "brick", "heavy" }, { "glass_works", "heavy" }, { "saw_mill", "heavy" }, { "sawmill", "heavy" },
	{ "paper_mill", "heavy" }, { "sand_excavator", "heavy" }, { "oil_well", "heavy" }, { "dump", "heavy" },
	{ "sewage", "heavy" }, { "smelter", "heavy" }, { "power_plant", "heavy" }, { "mine", "heavy" },
	{ "machine_factory", "medium" }, { "vehicle_factory", "medium" }, { "tire_factory", "medium" },
	{ "tool_factory", "medium" }, { "sand_pit", "medium" }, { "clay_pit", "medium" }, { "rocket", "medium" },
	{ "food", "light" }, { "brewery", "light" }, { "farm", "light" }, { "forest", "light" }, { "fishing", "light" },
	{ "shrimp", "light" }, { "textile", "light" }, { "weaving", "light" }, { "furniture", "light" },
	{ "printing", "light" }, { "pharma", "light" }, { "blanket", "light" }, { "bakery", "light" },
	{ "distillery", "light" }, { "winery", "light" }, { "orchard", "light" },
}

---------------------------------------------------------------------------
-- Keep-clear zones (2026-10-13, run 2026-10-13_2240_sqot-dev: Budleigh Salterton grew all round its crop farm). Read
-- from the base files (industries/*, industryutil.lua, fieldutil.lua, game_mechanics/industries/industries.script.tl;
-- not verified in game): processing industries (works, mills, breweries, refineries ...) have one fixed layout and
-- never grow; field industries (farms, plantations, forestry, mines, pits, quarries, oil wells) grow by adding a field
-- or pit stage in a free slot around the construction's origin, at most one try every half game year, only while they
-- ship (rating >= 0.25), and a slot whose field collides with anything (houses, streets, constructions) is skipped
-- silently. So a town grown round a farm caps it for good. A hard zone the mod's own pieces never enter: the farthest
-- corner of the industry's max-level footprint from its origin (rotation free) + ZONE_MARGIN, the lots of a street
-- (ZONE_LOT) kept out too. A zone that would reach within ZONE_CORE_M of the town centre shrinks (never below the
-- level-1 footprint + margin): a town that started beside a works still grows.
-- { pattern, rMax (m, max level), r1 (m, level 1) }; first match wins; unknown industries: ZONE_DEFAULT.
M.ZONE = true
M.ZONE_MARGIN = 40
M.ZONE_LOT = 30          -- m: a street's lots reach this far each side
M.ZONE_LOCK_M = 80       -- m beyond the zone: the mod's new streets this near are locked (no game side streets into it)
M.ZONE_CORE_M = 150      -- m: a zone ends at least this short of the town centre (down to its level-1 size)
M.ZONE_REACH = 900       -- m beyond the town's radius: industries this near are read (also for the penalty)
M.ZONE_DEFAULT = { 150, 110 }
M.FOOTPRINTS = {
	{ "oil_platform", 0, 0 }, { "sand_excavator", 0, 0 }, { "fishing", 0, 0 }, { "dredging", 0, 0 },
	{ "livestock", 366, 96 }, { "cotton", 362, 92 }, { "rubber", 359, 103 }, { "industries/forest", 331, 88 },
	{ "farm", 382, 108 }, { "orchard", 382, 108 },
	{ "coal_mine", 275, 178 }, { "iron_ore", 295, 120 }, { "clay_pit", 278, 131 }, { "sand_pit", 250, 127 },
	{ "quarry", 220, 136 }, { "oil_well", 272, 140 },
	{ "brewery", 99, 99 }, { "brick", 99, 99 }, { "cement", 114, 114 }, { "chemical", 127, 127 }, { "food", 108, 108 },
	{ "furniture", 93, 93 }, { "glass", 125, 125 }, { "machine", 111, 111 }, { "refinery", 138, 138 },
	{ "paper", 126, 126 }, { "printing", 85, 85 }, { "saw_mill", 120, 120 }, { "steel", 141, 141 },
	{ "textile", 114, 114 }, { "tire", 114, 114 }, { "tool", 92, 92 }, { "vehicle", 131, 131 }, { "weaving", 94, 94 },
}

--- The keep-clear radii of an industry file: rMax, r1 (m, without the margin); 0, 0 = no zone (on water).
function M.footprint(file)
	local s = string.lower(tostring(file or ""))
	for _, p in ipairs(M.FOOTPRINTS) do
		if s:find(p[1], 1, true) then return p[2], p[3] end
	end
	return M.ZONE_DEFAULT[1], M.ZONE_DEFAULT[2]
end

--- The zone of one industry at (x, y) for a town centred at (cx, cy): its radius (m, margin included) or 0.
function M.zoneRadius(file, x, y, cx, cy)
	local rMax, r1 = M.footprint(file)
	if rMax <= 0 then return 0 end
	local r = rMax + M.ZONE_MARGIN
	if cx ~= nil then
		local d = G.dist(cx, cy, x, y)
		local lim = math.max(r1 + M.ZONE_MARGIN, d - M.ZONE_CORE_M)
		if r > lim then r = lim end
	end
	return r
end

--- The zone (index into info.zones) that (x, y) lies in with pad m of slack (nil: none).
function M.inZone(info, x, y, pad)
	if info == nil or info.zones == nil then return nil end
	pad = pad or 0
	for i, z in ipairs(info.zones) do
		local rr = z.r + pad
		local dx, dy = x - z.x, y - z.y
		if dx * dx + dy * dy < rr * rr then return i end
	end
	return nil
end

--- Does a polyline (pts = { {x, y}, ... }) or its lots (pad, default ZONE_LOT) enter a zone? Sampled every ~15 m.
function M.zoneHit(info, pts, pad)
	if info == nil or info.zones == nil or #info.zones == 0 or pts == nil then return nil end
	pad = pad or M.ZONE_LOT
	for i = 1, #pts do
		local a = pts[i]
		local z = M.inZone(info, a[1], a[2], pad)
		if z then return z end
		local b = pts[i + 1]
		if b then
			local l = G.dist(a[1], a[2], b[1], b[2])
			local n = math.min(40, math.floor(l / 15))
			for k = 1, n do
				local f = k / (n + 1)
				z = M.inZone(info, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, pad)
				if z then return z end
			end
		end
	end
	return nil
end

--- "n:r1/r2/..." for PLAN `zones=` ("-" without zones).
function M.zoneText(info)
	if info == nil or info.zones == nil or #info.zones == 0 then return "-" end
	local parts = {}
	for i, z in ipairs(info.zones) do
		if i > 4 then break end
		parts[#parts + 1] = string.format("%.0f", z.r)
	end
	return string.format("%d:%s", #info.zones, table.concat(parts, "/"))
end

--- Kind of an industry from its construction file name: "heavy" | "medium" | "light" | "ignore", matched (bool).
function M.classify(file)
	local s = string.lower(tostring(file or ""))
	if s == "" then return "medium", false end
	for _, p in ipairs(M.PATTERNS) do
		if s:find(p[1], 1, true) then return p[2], true end
	end
	return "medium", false
end

--- Era weight of the preference: 0.4 up to ERA[1] (1910), rising to 1 at ERA[2] (1945) (worker housing next to the
--- works was the norm into the early 20th century; zoning and the garden-city movement separated them later). Era
--- range 1900+ (2026-10-13: TF3 starts in 1900 at the earliest; the ramp was 1890-1920, half over at a 1900 start).
M.ERA = { 1910, 1945 }
function M.strength(year)
	year = tonumber(year) or 1960
	if year <= M.ERA[1] then return 0.4 end
	if year >= M.ERA[2] then return 1.0 end
	return 0.4 + 0.6 * (year - M.ERA[1]) / (M.ERA[2] - M.ERA[1])
end

--- Industries near a town: info = { list = {{x, y, kind, w, r, file}}, n, nearest = m (or nil), heavy = count,
--- strength, away = rad or nil, awayMag = 0..1, unknown = {file = true} } or nil when there are none (so a town
--- without industries is planned exactly as before). all: { {x, y, file} }; (cx, cy): the town centre.
function M.forTown(all, cx, cy, year, reach)
	if not M.ON or all == nil then return nil end
	-- (reach: the town's radius + ZONE_REACH when bigger than SEARCH_R; run 2026-10-13_2240_sqot-dev: Budleigh
	-- Salterton reached r = 1850 m, its crop farm lay beyond the fixed 1500 m and every check said ind=0)
	reach = math.max(M.SEARCH_R, tonumber(reach) or 0)
	local list, unknown = {}, {}
	local zones = {}
	local nearest, heavy = nil, 0
	local ax, ay = 0, 0
	for _, it in ipairs(all) do
		local x, y = it[1] or it.x, it[2] or it.y
		if x and y then
			local d = G.dist(cx, cy, x, y)
			if d <= reach then
				local kind, matched = M.classify(it.file)
				if M.ZONE then
					local zr = M.zoneRadius(it.file, x, y, cx, cy)
					if zr > 0 then zones[#zones + 1] = { x = x, y = y, r = zr, file = it.file } end
				end
				if not matched and it.file and it.file ~= "" then unknown[it.file] = true end
				if kind ~= "ignore" then
					local k = M.KINDS[kind]
					list[#list + 1] = { x, y, kind = kind, w = k.w, r = k.r, file = it.file, d = d }
					if nearest == nil or d < nearest then nearest = d end
					if kind == "heavy" then heavy = heavy + 1 end
					-- away direction: from the works toward the centre, weighted by the works' pull at the centre
					if d > 1 then
						local f = k.w * math.exp(-(d / (k.r + 400)) ^ 2)
						ax, ay = ax + (cx - x) / d * f, ay + (cy - y) / d * f
					end
				end
			end
		end
	end
	if #list == 0 and #zones == 0 then return nil, unknown end
	table.sort(list, function(a, b)
		if a.d ~= b.d then return a.d < b.d end
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)
	local mag = math.sqrt(ax * ax + ay * ay)
	local info = { list = list, n = #list, nearest = nearest, heavy = heavy, strength = M.strength(year),
		awayMag = G.clamp(mag, 0, 1), away = mag > 1e-6 and G.atan2(ay, ax) or nil, unknown = unknown,
		centre = { cx, cy }, zones = zones, reach = reach }
	return info, unknown
end

--- Penalty at (x, y): era x min(PEN_CAP, sum w x exp(-FALL (d / r)^2)), 0 without info.
function M.pen(info, x, y)
	if info == nil then return 0 end
	local s = 0
	for _, it in ipairs(info.list) do
		local dx, dy = x - it[1], y - it[2]
		local q = (dx * dx + dy * dy) / (it.r * it.r)
		if q < 9 then s = s + it.w * math.exp(-M.FALL * q) end
	end
	if s > M.PEN_CAP then s = M.PEN_CAP end
	return s * (info.strength or 1)
end

--- The penalty at (x, y) from the heavy and medium works only (satellites, M2 2026-10-13: a village beside a farm or a
--- light works is fine, the user liked those vanilla clusters), 0 without info.
function M.penHeavy(info, x, y)
	if info == nil then return 0 end
	local s = 0
	for _, it in ipairs(info.list) do
		if it.kind ~= "light" then
			local dx, dy = x - it[1], y - it[2]
			local q = (dx * dx + dy * dy) / (it.r * it.r)
			if q < 9 then s = s + it.w * math.exp(-M.FALL * q) end
		end
	end
	if s > M.PEN_CAP then s = M.PEN_CAP end
	return s * (info.strength or 1)
end

--- The nearest light works (farms, food, textiles ...) to (x, y): distance (m) or nil.
function M.nearestLight(info, x, y)
	if info == nil then return nil end
	local best = nil
	for _, it in ipairs(info.list) do
		if it.kind == "light" then
			local d = G.dist(x, y, it[1], it[2])
			if best == nil or d < best then best = d end
		end
	end
	return best
end

--- true when (x, y) lies inside any buffer (d < r).
function M.inBuffer(info, x, y)
	if info == nil then return false end
	for _, it in ipairs(info.list) do
		if G.dist(x, y, it[1], it[2]) < it.r then return true end
	end
	return false
end

--- Mean penalty along a heading from (cx, cy), sampled every 100 m out to reach.
function M.rayExposure(info, cx, cy, heading, reach)
	if info == nil then return 0 end
	reach = reach or M.AXIS_REACH
	local s, n = 0, 0
	local c, sn = math.cos(heading), math.sin(heading)
	for r = 100, reach, 100 do
		s = s + M.pen(info, cx + c * r, cy + sn * r)
		n = n + 1
	end
	return n > 0 and s / n or 0
end

--- The axis among candidates whose arms (armsFn(axis) -> {headings}) are least exposed; returns axis, turned (bool).
--- The first candidate is the seeded one; another wins only when it lowers the mean exposure by AXIS_GAIN.
function M.bestAxis(info, cx, cy, cands, armsFn, reach)
	if info == nil or #cands == 0 then return cands[1], false end
	local function score(a)
		local arms = armsFn(a) or { a }
		local s = 0
		for _, h in ipairs(arms) do s = s + M.rayExposure(info, cx, cy, h, reach) end
		return s / math.max(1, #arms)
	end
	local s0 = score(cands[1])
	local best, bs = cands[1], s0
	for i = 2, #cands do
		local s = score(cands[i])
		if s < bs - 1e-9 then best, bs = cands[i], s end
	end
	if best ~= cands[1] and s0 - bs >= M.AXIS_GAIN then return best, true end
	return cands[1], false
end

--- Share of a list of segments' length inside the buffers (PLAN `indPen=`): segs = { {x0, y0, x1, y1} }; nil
--- without info or length. Sampled every ~20 m.
function M.penShare(info, segs)
	if info == nil then return nil end
	local tot, inside = 0, 0
	for _, s in ipairs(segs or {}) do
		local l = G.dist(s[1], s[2], s[3], s[4])
		if l > 0 then
			local n = math.max(1, math.ceil(l / 20))
			for k = 1, n do
				local f = (k - 0.5) / n
				local x, y = s[1] + (s[3] - s[1]) * f, s[2] + (s[4] - s[2]) * f
				tot = tot + l / n
				if M.inBuffer(info, x, y) then inside = inside + l / n end
			end
		end
	end
	if tot <= 0 then return nil end
	return inside / tot
end

--- "count/nearest m/heavy count" for CHECK / STYLE / SHAPE (`ind=`), "0" without industries nearby.
function M.text(info)
	if info == nil then return "0" end
	return string.format("%d/%.0f/%d", info.n, info.nearest or -1, info.heavy)
end

--- Industries in a town and how many it encloses (2026-10-14 late; dev ALLTOWN `ind=`, works with the main mod off).
--- all = the map's industries { {x, y, file} }; (cx, cy, r) the town's centre and radius; pts = its buildings { {x, y} };
--- segs = its streets { {x0, y0, x1, y1} }. An industry within r of the centre (its footprint not on water) is enclosed
--- when buildings or town streets (a segment's ends and midpoint) stand on ENCLOSE_SIDES or more of its four sides
--- (quadrants N / E / S / W) within its keep-clear radius (max footprint + ZONE_MARGIN, M.zoneRadius without the
--- town-centre shrink): the game's houses and streets there cap a field industry's growth. Returns n, enclosed, text
--- "n/enclosed" (kinds of the enclosed ones after a colon, "0/0" none).
M.ENCLOSE_SIDES = 3
function M.enclosure(all, cx, cy, r, pts, segs)
	local n, enc, kinds = 0, 0, {}
	for _, it in ipairs(all or {}) do
		local x, y = it[1] or it.x, it[2] or it.y
		if x and y and G.dist(cx, cy, x, y) <= (r or 0) then
			local zr = M.zoneRadius(it.file, x, y)
			if zr > 0 then
				n = n + 1
				local side = {}
				local function mark(px, py)
					local dx, dy = px - x, py - y
					if dx * dx + dy * dy <= zr * zr then
						local q
						if math.abs(dx) >= math.abs(dy) then q = dx >= 0 and 2 or 4 else q = dy >= 0 and 1 or 3 end
						side[q] = true
					end
				end
				for _, p in ipairs(pts or {}) do mark(p[1], p[2]) end
				for _, sg in ipairs(segs or {}) do
					mark(sg[1], sg[2]); mark(sg[3], sg[4]); mark((sg[1] + sg[3]) / 2, (sg[2] + sg[4]) / 2)
				end
				local k = 0
				for q = 1, 4 do if side[q] then k = k + 1 end end
				if k >= M.ENCLOSE_SIDES then
					enc = enc + 1
					kinds[#kinds + 1] = tostring(it.file or ""):match("([%w_]+)%.con$") or (M.classify(it.file))
				end
			end
		end
	end
	local text = string.format("%d/%d", n, enc)
	if #kinds > 0 then text = text .. ":" .. table.concat(kinds, ",") end
	return n, enc, text
end

return M
