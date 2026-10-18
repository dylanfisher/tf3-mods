-- DEV ONLY (never upload). Organic Towns showcase: what to spawn and where (pure; tests/square_organic_towns_dev).
--
-- Items: one town per style (ot_style.IDS), two vanilla control towns (no mod streets, the same forced growth),
-- the roundabout probe town (when square_roundabouts is installed), an era row (NA grid and EU extension as of
-- 1900: old templates), the shape and density rows, the v6 probe row (shape twins: plain / locked+fill /
-- metropolis / DevelopAt flags) and,
-- only with L.PROBE_C or opts.probeC, a "Probe C" row of vanilla towns with initialMajorStreetAngle 0/15/45/90.
-- Priority decides what is dropped when the island is too small for every town at MIN_SPACING: Probe C first,
-- then the probe row, density, shapes, the controls, then the era towns and the roundabout town; the styles
-- always stay.
--
-- The island (Blank Slate: one flat island at 5 m with sea all round) is measured at runtime: from the
-- terrain bounding box centre outward along both axes until isOnWater, in STEP m steps. Towns sit on a
-- row-major grid inside the land minus MARGIN, TARGET_SPACING apart when there is room (never closer than
-- MIN_SPACING). Every spot is checked for water on rings of 0 / 250 / 500 m (8 directions); a wet spot moves
-- to a spare grid cell or is dropped. A style whose grid axis follows a shore (NORDIC: ribbon + contour,
-- "fjord" towns) moves to the coast: COAST_D m from the shoreline, so its terrain disc (600 m) sees water.

local L = {}

L.TARGET_SPACING = 2500
L.MIN_SPACING = 1300
L.MARGIN = 900          -- grid box inset from the shoreline (m)
L.STEP = 50             -- island scan step (m)
L.COAST_D = 420         -- coastal town: distance from the shoreline (m)
L.RINGS = { 0, 250, 500 }
L.MAX_COLS = 6

-- Showcase styles that follow a shore (moved to the coast; logged)
L.COASTAL = { NORDIC = true }

-- Showcase v3 rows. Shape row: one town per shape archetype (ot_shape ids, kept here as a constant so the dev
-- mod doesn't depend on the module), all in SHAPE_STYLE, so only the shape differs. Density row: the same style,
-- one density lever per town (otd_showcase.DENSITY), a plain control beside them.
L.SHAPES = { "compact", "linear", "cross", "fingers", "fan", "twin", "lens", "ridge" }
L.SHAPE_STYLE = "EU_EXTENSION"
L.DENSITY_STYLE = "EU_EXTENSION"
-- Showcase v6 probe row (2026-10-12, NEXT_PHASE_BRIEF 13): twins of shape-row towns, compared with them (twinOf).
-- The shape row itself runs the main mod's defaults (lock "shape": arm / rim streets locked; dosed fill). lock /
-- fill are the driver's startJob options (ot_driver.lockMode / fillKind): plain = neither (the v5 shape row);
-- lockfill = every new street locked + dosed fill; metro = the metropolis fill (v5's fill twin: 12 DevelopAt points
-- beside every build's new streets, no cap); da* = the dosed fill without lock, with DevelopAt's developStreets /
-- upgradeBuildings flags (what the two flags do). v5's freeze twins are gone (freezing changed nothing).
-- v7 (2026-10-12): the metropolis twin and the three DevelopAt flag twins are gone (the flags changed little in v6:
-- near growth 0-5 buildings either way); the metropolis row below replaces them.
-- v8 (2026-10-12, NEXT_PHASE_BRIEF 15): only the plain linear twin stays (the lock control: v5-v7 showed the lock's
-- effect every run, findings towns.md); the locked+fill twins and the fingers plain twin are gone.
-- §65 (2026-10-15): the main mod locks every street it builds ("mod", ot_driver LOCK_DEFAULT; the town's own starting
-- streets stay unlocked), so the shape row and the styles run that. The lock A/B twins run the old default (lock
-- "shape": arm / rim / forest / motif streets locked) beside them: EU organic (the 0629 run's style) and the linear
-- shape (with the plain twin: mod / shape / off). Two only: 30 grid towns keep the 6 x 5 grid at ~2.4 km (a third
-- twin made it 6 rows at 1.9 km). Their LOCK lines (and their twins') log the game-built edges, the buildings and cap / target per step.
-- (A "rebuild and lock the core" variant is left out: it would rebuild the town's live starting streets.)
-- §69 (2026-10-15): the main mod's default is the steering lock ("steer", ot_lockpol: many streets locked, chiefly
-- early and where direction matters, the branches' tips open), so the EU organic twin now runs the §65 "lock every
-- mod street" ("mod", EU_ORGANIC_LOCKALL) beside it; the linear twins keep the old shape lock and the plain control.
L.PROBES = {
	{ key = "SHAPE_LINEAR_PLAIN", label = "Shape: linear (plain)", shape = "linear", probe = "plain", twinOf = "SHAPE_LINEAR",
		lock = "off", fill = "off" },
	{ key = "EU_ORGANIC_LOCKALL", label = "EU organic (lock all)", style = "EU_ORGANIC", probe = "lockall",
		twinOf = "EU_ORGANIC", lock = "mod" },
	{ key = "SHAPE_LINEAR_OLDLOCK", label = "Shape: linear (old lock)", shape = "linear", probe = "oldlock",
		twinOf = "SHAPE_LINEAR", lock = "shape" },
}
-- the v6 / v7 probe row (kept for the tests of the probe mechanics and a later run that wants them back)
L.PROBES_V7 = {
	L.PROBES[1],
	{ key = "SHAPE_LINEAR_LOCKFILL", label = "Shape: linear (locked+fill)", shape = "linear", probe = "lockfill",
		twinOf = "SHAPE_LINEAR", lock = "all", fill = "dose" },
	{ key = "SHAPE_FINGERS_PLAIN", label = "Shape: fingers (plain)", shape = "fingers", probe = "plain",
		twinOf = "SHAPE_FINGERS", lock = "off", fill = "off" },
	{ key = "SHAPE_FINGERS_LOCKFILL", label = "Shape: fingers (locked+fill)", shape = "fingers", probe = "lockfill",
		twinOf = "SHAPE_FINGERS", lock = "all", fill = "dose" },
}
L.CONTROL_B = false     -- v8: one vanilla control (Control B only with this on)
-- v8 form row (NEXT_PHASE_BRIEF 15, user: "JP dense clustered and radiating from centre vs JP dense sprawling"): one
-- style in several town forms (ot_form ids, forced: startJob form), so only the form differs.
L.FORMS = { "clustered", "radiating", "sprawling", "linear" }
L.FORM_STYLE = "JP_DENSE"
-- v8 metropolis band: v7's metropolis row (2.5 km apart) grew into one another (r ~1.2 km each). The metropolis towns
-- now sit in a band at the bottom of the island, METRO_BAND m high, on staggered slots (x from the box centre, y from
-- the box bottom; x scaled down on a narrower island): ~3.6 km apart. Without room for the band they join the grid.
L.METRO_BAND = 5000
L.METRO_SLOTS = { { -5400, 2950 }, { 0, 2950 }, { 5400, 2950 }, { -2700, 550 }, { 2700, 550 } }
L.METRO_HALF_W = 7250   -- the slots' x are laid out for a box this wide on each side
-- Probe C (vanilla towns at initialMajorStreetAngle 0 / 15 / 45 / 90): off since v5. v4 (2026-10-12): with the main
-- mod's "Vanilla town street angles" (baseConfig range 35, [SQOT] ANGLE) createTowns hands back 35 for every town and
-- the per-town TownInfo angles gave identical towns; v2 (baseConfig 0) had shown different layouts.
L.PROBE_C = false
-- Showcase v7 metropolis row (NEXT_PHASE_BRIEF 14): one town per ot_metro variant, forced (startJob metro), each on
-- the base style that suits it; polycentric seeds its secondary centre from the first build (metroCentres) so it
-- shows within N = 10 steps. The main mod's defaults otherwise (metro fill, the variant's lock).
-- v8: each with a forced town form (ot_form), so the run shows the form axis on a metropolis too: the radial one
-- grows fingers along its spokes (radiating), the polycentric one sprawls between its centres.
L.METROS = {
	{ variant = "grid", style = "NA_GRID", form = "clustered" },
	{ variant = "radial", style = "EU_EXTENSION", form = "radiating" },
	{ variant = "corridor", style = "EU_EXTENSION", form = "linear" },
	{ variant = "oldcore", style = "EU_ORGANIC", form = "clustered" },
	{ variant = "polycentric", style = "NA_GRID", centres = true, form = "sprawling" },
}
-- v8: the weights / upgrade / medium-street levers showed no lasting look difference in v3-v7 (weights and medium
-- ended like the control; upgrade is a one-off growth wave, findings towns.md); the control town the user liked
-- (green gaps) stays. otd_showcase still knows the levers (a later row may bring one back).
L.DENSITY = {
	{ lever = "control", label = "Density: control" },
}
L.DENSITY_V7 = {
	{ lever = "weights", label = "Density: weights" },
	{ lever = "upgrade", label = "Density: upgrade" },
	{ lever = "medium", label = "Density: medium streets" },
	{ lever = "control", label = "Density: control" },
}

--- Items in row order: { key, label, kind = "style" | "vanilla", style, angle (deg; nil = createTowns'
--- default), newTemplates (nil = the year decides), year (style inputs as of that year; nil = the map's),
--- roundabout (the roundabout probe town), row, prio (higher = kept longer), coast }.
--- styles = { {id, label, angle} } in display order (S.STYLES profile entries with their angleRange).
--- opts = { era = bool (map year >= 1940: the era row compares against 1900 = old templates), roundabout = bool
--- (square_roundabouts installed: an EU extension town that gets one roundabout at its frontier) }.
--- Rows of 6: styles 1-5 + Control A; styles 6-9 + the roundabout town (v8: no Control B); the era row (NA grid 1900,
--- EU extension 1900) + Probe C (vanilla towns at initialMajorStreetAngle 0 / 15 / 45 / 90). Only the plain
--- town templates differ by era (town_old_* vs town_new_* from 1940; findings "Town street templates"), so a
--- 1960 town would build exactly like the map-era style towns in 1960+ games: no 1960 column.
--- opts.shapes (default true): the shape row (key SHAPE_<ID>, `shape` = id); opts.density (default true): the
--- density row (key DENS_<LEVER>, `lever`); opts.probes (default true, needs the shape row): the probe row (L.PROBES:
--- `probe`, `twinOf`, `lock`, `fillKind`, `fillStreets`, `fillUpgrade`); opts.metros (default true, needs the shape row
--- toggle too): the metropolis row
--- (L.METROS: key METRO_<VARIANT>, `metro`, `metroCentres`; placed in the metropolis band, L.layout); opts.forms
--- (default true): the form row (L.FORMS: key FORM_<ID>, `form`); opts.probeC (default L.PROBE_C = false). Drop priority: Probe C
--- first, then the probe row, density, shapes, then the controls, era and roundabout towns.
function L.items(styles, opts)
	opts = opts or {}
	local out = {}
	local function add(it)
		out[#out + 1] = it
	end
	local half = math.ceil(#styles / 2)
	for i, st in ipairs(styles) do
		add({ key = st.id, label = st.label, kind = "style", style = st.id, angle = st.angle, row = i <= half and 1 or 2,
			prio = 100 - i, coast = L.COASTAL[st.id] == true })
		if i == half then
			add({ key = "CONTROL_A", label = "Control A", kind = "vanilla", row = 1, prio = 30 })
		end
	end
	if L.CONTROL_B then add({ key = "CONTROL_B", label = "Control B", kind = "vanilla", row = 2, prio = 29 }) end
	if opts.roundabout then
		add({ key = "RB_EU", label = "EU ext roundabout", kind = "style", style = "EU_EXTENSION", angle = 10, roundabout = true,
			row = 2, prio = 45 })
		-- (2026-10-14: the main mod's roundabout town, ot_character / ot_ring: one-way rings at the plan's own new crossings;
		-- verify in game that the ring builds and traffic drives it one way, RB lines)
		add({ key = "RB_TOWN", label = "Roundabout town", kind = "style", style = "EU_EXTENSION", angle = 10,
			charKind = "roundabout_town", row = 2, prio = 44 })
	end
	if opts.era ~= false then
		add({ key = "ERA_NA_1900", label = "NA grid 1900", kind = "style", style = "NA_GRID", angle = 0, year = 1900,
			newTemplates = false, row = 3, prio = 40 })
		add({ key = "ERA_EU_1900", label = "EU extension 1900", kind = "style", style = "EU_EXTENSION", angle = 10, year = 1900,
			newTemplates = false, row = 3, prio = 39 })
	end
	if opts.shapes ~= false then
		for i, id in ipairs(L.SHAPES) do
			add({ key = "SHAPE_" .. id:upper(), label = "Shape: " .. id, kind = "style", style = L.SHAPE_STYLE, shape = id,
				row = 4, prio = 28 - i })
		end
	end
	if opts.density ~= false then
		for i, d in ipairs(L.DENSITY) do
			add({ key = "DENS_" .. d.lever:upper(), label = d.label, kind = "style", style = L.DENSITY_STYLE, lever = d.lever,
				row = 5, prio = 19 - i })
		end
	end
	if opts.probes ~= false and opts.shapes ~= false then
		for i, p in ipairs(L.PROBES) do
			add({ key = p.key, label = p.label, kind = "style", style = p.style or L.SHAPE_STYLE, shape = p.shape, probe = p.probe,
				twinOf = p.twinOf, lock = p.lock, fillKind = p.fill, fillStreets = p.fillStreets, fillUpgrade = p.fillUpgrade,
				row = 6, prio = 14 - i })
		end
	end
	if opts.forms ~= false then
		for i, f in ipairs(L.FORMS) do
			add({ key = "FORM_" .. f:upper(), label = "Form: " .. f, kind = "style", style = L.FORM_STYLE, form = f,
				row = 5, prio = 22 - i })
		end
	end
	if opts.metros ~= false and opts.shapes ~= false then
		for i, m in ipairs(L.METROS) do
			add({ key = "METRO_" .. m.variant:upper(), label = "Metropolis: " .. m.variant, kind = "style", style = m.style,
				metro = m.variant, metroCentres = m.centres == true, form = m.form, row = 7, prio = 25 - i })
		end
	end
	if opts.probeC == true or (opts.probeC == nil and L.PROBE_C) then
		for i, a in ipairs({ 0, 15, 45, 90 }) do
			add({ key = "PROBE_C_" .. a, label = "Vanilla angle " .. a, kind = "vanilla", angle = a, row = 3, prio = 9 - i })
		end
	end
	return out
end

--- Land extent of the island around the terrain box centre: { minX, maxX, minY, maxY, cx, cy } (first wet
--- sample along each half-axis, minus one step), or nil when the centre itself is water.
function L.island(box, water, step)
	step = step or L.STEP
	local cx, cy = (box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2
	if water(cx, cy) then return nil end
	local function scan(dx, dy, limit)
		local d = 0
		while d + step <= limit do
			if water(cx + dx * (d + step), cy + dy * (d + step)) then return d end
			d = d + step
		end
		return d
	end
	return {
		cx = cx, cy = cy,
		maxX = cx + scan(1, 0, box.maxX - cx), minX = cx - scan(-1, 0, cx - box.minX),
		maxY = cy + scan(0, 1, box.maxY - cy), minY = cy - scan(0, -1, cy - box.minY),
	}
end

--- true when the spot and its rings are dry (and inside the box); second result: the first wet offset.
function L.dry(x, y, water, rings)
	for _, r in ipairs(rings or L.RINGS) do
		local n = r == 0 and 1 or 8
		for k = 0, n - 1 do
			local a = k / n * 2 * math.pi
			local px, py = x + r * math.cos(a), y + r * math.sin(a)
			if water(px, py) then return false, string.format("%.0f,%.0f", px, py) end
		end
	end
	return true
end

--- Grid of cols x rows over the box (row 1 at the top = max y), spacing as large as fits (<= target).
local function grid(box, cols, rows, target)
	local w, h = box.maxX - box.minX, box.maxY - box.minY
	local sx = cols > 1 and w / (cols - 1) or math.huge
	local sy = rows > 1 and h / (rows - 1) or math.huge
	local sp = math.min(target, sx, sy)
	if sp == math.huge then sp = target end
	local cx, cy = (box.minX + box.maxX) / 2, (box.minY + box.maxY) / 2
	local cells = {}
	for r = 1, rows do
		for c = 1, cols do
			cells[#cells + 1] = { x = cx + (c - (cols + 1) / 2) * sp, y = cy - (r - (rows + 1) / 2) * sp, row = r, col = c }
		end
	end
	return cells, sp
end

--- Places items on the island. land = L.island(...), water(x, y) -> bool, opts.offset = {dx, dy} (a second run on
--- a map where destroyed towns left streets: the whole grid moves by it). Returns { placed = { {item, x, y,
--- row, col, coast = distance to shore or nil} }, dropped = { {item, why} }, spacing, cols, rows, box }.
function L.layout(items, land, water, opts)
	opts = opts or {}
	local margin = opts.margin or L.MARGIN
	local minSp, target = opts.minSpacing or L.MIN_SPACING, opts.target or L.TARGET_SPACING
	local box = { minX = land.minX + margin, maxX = land.maxX - margin, minY = land.minY + margin, maxY = land.maxY - margin }
	local res = { placed = {}, dropped = {}, box = box }
	local off = opts.offset
	if box.maxX < box.minX or box.maxY < box.minY then
		for _, it in ipairs(items) do res.dropped[#res.dropped + 1] = { item = it, why = "islandTooSmall" } end
		return res
	end
	-- v8 metropolis band at the bottom: the metropolis towns on their slots, the rest on the grid above
	local band = opts.metroBand or L.METRO_BAND
	local metros = {}
	for _, it in ipairs(items) do if it.metro then metros[#metros + 1] = it end end
	if #metros > 0 and #metros <= #L.METRO_SLOTS and band > 0 and (box.maxY - box.minY) > band + 2 * minSp then
		local rest = {}
		for _, it in ipairs(items) do if not it.metro then rest[#rest + 1] = it end end
		local top = { minX = land.minX, maxX = land.maxX, minY = land.minY + band, maxY = land.maxY }
		local o2 = {}
		for k, v in pairs(opts) do o2[k] = v end
		o2.metroBand = 0
		res = L.layout(rest, top, water, o2)
		res.box = box
		res.band = band
		local cx = (box.minX + box.maxX) / 2
		local fx = math.min(1, ((box.maxX - box.minX) / 2) / L.METRO_HALF_W)
		for i, it in ipairs(metros) do
			local sl = L.METRO_SLOTS[i]
			local x, y = cx + sl[1] * fx + (off and off[1] or 0), box.minY + sl[2] + (off and off[2] or 0)
			local okDry, wet = L.dry(x, y, water)
			if okDry then
				res.placed[#res.placed + 1] = { item = it, x = x, y = y, row = (res.rows or 0) + (sl[2] > band / 2 and 1 or 2),
					col = i, metroSlot = i }
			else
				res.dropped[#res.dropped + 1] = { item = it, why = "water:" .. tostring(wet) }
			end
		end
		return res
	end
	-- keep the highest priorities that fit at minSp (items stay in their row order)
	local keep = {}
	for i, it in ipairs(items) do keep[i] = it end
	local cols, rows, sp
	while true do
		local n = #keep
		local maxCols = math.max(1, math.min(opts.maxCols or L.MAX_COLS, math.floor((box.maxX - box.minX) / minSp) + 1))
		cols = math.min(maxCols, n)
		rows = math.ceil(n / math.max(cols, 1))
		local _, s = grid(box, cols, rows, target)
		sp = s
		if n == 0 or (sp >= minSp and (rows - 1) * sp <= (box.maxY - box.minY) + 1e-6) then break end
		local lo, li = math.huge, nil
		for i, it in ipairs(keep) do if it.prio < lo then lo, li = it.prio, i end end
		res.dropped[#res.dropped + 1] = { item = keep[li], why = "space" }
		table.remove(keep, li)
	end
	res.cols, res.rows, res.spacing = cols, rows, sp
	if #keep == 0 then return res end
	-- spare cells for wet spots: the unused cells of the last row
	local cells = grid(box, cols, rows, target)
	if off then
		for _, c in ipairs(cells) do c.x, c.y = c.x + (off[1] or 0), c.y + (off[2] or 0) end
	end
	local spare = {}
	for i = #keep + 1, #cells do spare[#spare + 1] = cells[i] end
	for i, it in ipairs(keep) do
		local c = cells[i]
		local okDry, wet = L.dry(c.x, c.y, water)
		while not okDry and #spare > 0 do
			c = table.remove(spare, 1)
			okDry, wet = L.dry(c.x, c.y, water)
		end
		if okDry then
			res.placed[#res.placed + 1] = { item = it, x = c.x, y = c.y, row = c.row, col = c.col, moved = c ~= cells[i] }
		else
			res.dropped[#res.dropped + 1] = { item = it, why = "water:" .. tostring(wet) }
		end
	end
	-- coastal styles: on an outer grid cell (swapped with the town in the top row's same column when needed),
	-- then moved straight out toward the shore until COAST_D from the water
	for _, p in ipairs(res.placed) do
		if p.item.coast then
			if not (p.row == 1 or p.row == rows or p.col == 1 or p.col == cols) then
				for _, q in ipairs(res.placed) do
					if q.row == 1 and q.col == p.col and not q.item.coast then
						p.x, q.x, p.y, q.y, p.row, q.row, p.col, q.col = q.x, p.x, q.y, p.y, q.row, p.row, q.col, p.col
						p.swapped = q.item.key
						break
					end
				end
			end
			L.toCoast(p, land, water, opts.coastD or L.COAST_D, rows, cols)
		end
	end
	return res
end

--- Moves a placed town toward the nearest shore (of the land-box sides it faces) so the shoreline is `d` m away,
--- measured with water(): walks out until wet, then back d. Sets p.coast = d (or leaves it when no shore is
--- found within the box).
function L.toCoast(p, land, water, d, rows, cols)
	-- only toward sides where the town is on the outer grid ring (never through another town's cell)
	local sides = {}
	local outer = rows == nil
	if outer or p.row == rows then sides[#sides + 1] = { 0, -1, p.y - land.minY } end
	if outer or p.row == 1 then sides[#sides + 1] = { 0, 1, land.maxY - p.y } end
	if outer or p.col == 1 then sides[#sides + 1] = { -1, 0, p.x - land.minX } end
	if outer or p.col == cols then sides[#sides + 1] = { 1, 0, land.maxX - p.x } end
	if #sides == 0 then return end
	table.sort(sides, function(a, b) return a[3] < b[3] end)
	local dx, dy = sides[1][1], sides[1][2]
	local step = L.STEP
	for k = 1, math.ceil((sides[1][3] + 4 * step) / step) do
		local x, y = p.x + dx * k * step, p.y + dy * k * step
		if water(x, y) then
			local back = (k - 1) * step - d
			if back > 0 then
				local nx, ny = p.x + dx * back, p.y + dy * back
				-- the town itself must stay dry within 250 m (a rounded corner can bring the sea closer)
				if L.dry(nx, ny, water, { 0, 250 }) then
					p.x, p.y = nx, ny
					p.coast = d
					p.coastDir = dy < 0 and "south" or (dy > 0 and "north" or (dx < 0 and "west" or "east"))
				end
			end
			return
		end
	end
end

return L
