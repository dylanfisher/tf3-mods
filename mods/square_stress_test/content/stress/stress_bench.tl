-- Stress Test bench (plans/square_stress_test/BENCH.md): the pure part. A bench "sheet" is a list of tests
-- (a junction variant, its twins, its sets, which arms get a town); bench.plan packs every test's sets onto one
-- map (point clearances, not circles: BENCH.md "Layout") and returns a SquareStressShowcaseLayout, so the shared
-- Showcase build (gui/stress_junctions.tl buildRun) builds it with its towns, entries, links, zones and growth.
-- No api use: unit-tested offline (tests/square_stress_test/test_bench.lua).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic

local bench : SquareStressBench = {
	VERSION = 1,               -- the presets' version (BENCH_START spec=<sheet>@<VERSION>): results pool only within one
	STEP = 100.0,              -- m: the packer's raster step
	LINK_TOWN = 625.0,         -- m: a link (junction -> its town) at least this far from another group's town centre
	LINK_JUNCTION = 400.0,     -- m: a link at least another group's junction reach + this from its centre
	LINK_LINK = 100.0,         -- m: two links of different groups at least this far apart (and never crossing)
	BUCKET = 2000.0,           -- m: the placed groups' lookup grid
	SIZE = 2,                  -- TOWN_SIZES index of every bench town (Medium)
	POP = 400,                 -- people per town (growFactorForCap)
	PERSONS_PER_TOWN = 400,    -- sim persons per town (runs 5-6)
	DRIVER_SHARE = 0.36,       -- drivers of them at a time (run 6: 9920 of 27569)
	BUILD_S_PER_TOWN = 5.0,    -- s of build per town (runs 5-6: 4.6-5.3 s)
}

---------------------------------------------------------------------------
-- Twins and variants

local LIGHTS_AB = logic.LIGHTS_AB
-- the twin modes the bench builds (zone ab names; the letter is the zone id's: stress_flow TWIN_LETTER)
bench.AB = {
	sl = LIGHTS_AB[1],
	game = LIGHTS_AB[2],
	sl_lock = LIGHTS_AB[4],
	-- Smart Lanes lanes with the game's lights left standing at rings and slip / ramp nodes (BENCH.md SL-1)
	sl_keeplights = { ab = "sl_keeplights", twin = "f", label = "Keep lights",
		note = "Smart Lanes lanes, lights at rings and ramps left as the game made them" } as SquareStressShowcaseAb,
}

local function variant(id : string, label : string, file : string, kind : string, fixed : {string : number}) : SquareStressShowcaseType
	return { id = id, label = label, file = file, kind = kind, fixed = fixed, ranges = {}, short = label }
end

-- square_roundabouts' param indices (their .con.lua value lists; tests check the labels): arm / main / side roads
-- 1-6 = Town small, medium, large, Country small, medium, large; sqrb_arms 3 = "4"; sqrb_signals 1 = Off (the
-- game's AUTO decides); sqrb_ix_highway 2 = M (highway_new_medium: 2 lanes a carriageway); sqrb_ix_cross 6 = Country large.
bench.VARIANTS = {
	rb4 = variant("bench_rb4", "RB4 2L", "square_roundabouts.con", "rb", { sqrb_shape = 1, sqrb_centre = 1, sqrb_lanes = 2,
		sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1, sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1, sqrb_arm_type = 5 }),
	cht = variant("bench_cht", "Channel T", "square_roundabouts_channel.con", "rb", { sqrb_ch_layout = 1, sqrb_ch_scale = 1,
		sqrb_ch_main = 5, sqrb_ch_side = 5, sqrb_ch_slips = 1, sqrb_ch_splitter = 1, sqrb_ch_arm_length = 1, sqrb_ch_island = 1 }),
	dia = variant("bench_dia", "Diamond S", "square_roundabouts_highway_diamond.con", "ix", { sqrb_ix_highway = 2, sqrb_hx_level = 1,
		sqrb_hx_scale = 1, sqrb_hx_ramp = 1, sqrb_hx_arm_length = 1, sqrb_ix_cross = 6 }),
	-- stress_crossing shape 4 (Straight): the west arm Country large (3 + 3), the east arm (main2 6 = ROADS[5]) Country medium (2 + 2)
	drop = variant("bench_drop", "Lane drop 3-2", logic.SHOWCASE_PLAIN_FILE, "plain", { sqst_x_shape = 4, sqst_x_main = 6,
		sqst_x_main2 = 6, sqst_x_side = 5, sqst_x_angle = 1, sqst_x_lights = 1 }),
}

local function test(t : SquareStressBenchTest) : SquareStressBenchTest
	t.linkLanes = t.linkLanes or 0
	return t
end

local function lit(i : integer) : SquareStressShowcaseType
	return logic.LIGHTS_SHAPES[i]
end

-- The sheets (BENCH.md "The first bench", 16 km maps). Tests in priority order: a test that does not fit whole
-- loses its last sets, the later ones fill what is left.
bench.SHEETS = {
	-- version 2 (2026-10-13): the lane drop test is gone (its game default already equals Smart Lanes' rule: Smart Lanes
	-- logged "same" at every drop centre of session 2026-10-13_0610_session; no other lane drop is known to differ), its
	-- room to roundabout sets: 11, the most a 16 km map holds
	{ id = "bench_s1", key = "s1", title = "Bench sheet 1: roundabouts", version = 2, minKm = 16, slLights = true,
		tests = {
			test({ id = "rb4", title = "Roundabout, 2-lane ring, 4 country medium arms", variants = { bench.VARIANTS.rb4 },
				towns = { "N", "E", "S", "W" }, twins = { "game", "sl", "sl_keeplights" }, compare = { { "sl", "game" }, { "sl", "sl_keeplights" } },
				sets = 11 }),
		} },
	{ id = "bench_s2", key = "s2", title = "Bench sheet 2: slip lanes and interchanges", version = 1, minKm = 16, slLights = true,
		tests = {
			test({ id = "cht", title = "Channelized T, near-side slip lanes, country medium", variants = { bench.VARIANTS.cht },
				towns = { "E", "N", "W" }, twins = { "game", "sl", "sl_keeplights" }, compare = { { "sl", "game" }, { "sl", "sl_keeplights" } },
				sets = 9 }),
			-- towns W, E (highway) and N (cross road): every ramp and both terminals carry traffic; the S arm stays a stub
			test({ id = "dia", title = "Diamond S, 2-lane highway, country large cross road", variants = { bench.VARIANTS.dia },
				towns = { "E", "N", "W" }, twins = { "game", "sl" }, compare = { { "sl", "game" } }, sets = 6, pairLanes = 4 }),
		} },
	{ id = "bench_s3", key = "s3", title = "Bench sheet 3: lit crossroads and T-junctions", version = 1, minKm = 16, slLights = false,
		tests = {
			test({ id = "lt22", title = "Lit T, 2 lanes each way", variants = { lit(4) }, towns = { "E", "N", "W" },
				twins = { "sl", "game", "sl_lock" }, compare = { { "sl", "game" }, { "sl", "sl_lock" } }, sets = 9, litYes = true }),
			test({ id = "lx", title = "Lit crossroads 2x2 / 3x3 / 3x2 in turn", variants = { lit(1), lit(2), lit(3) },
				towns = { "N", "E", "S", "W" }, twins = { "sl", "game", "sl_lock" }, compare = { { "sl", "game" }, { "sl", "sl_lock" } },
				sets = 3, litYes = true }),
		} },
} as {SquareStressBenchSheet}

--- The sheet of a key ("s1") or id ("bench_s1"); nil when none.
function bench.sheet(key : string) : SquareStressBenchSheet
	for _, s in ipairs(bench.SHEETS) do
		if s.key == key or s.id == key then return s end
	end
	return nil
end

---------------------------------------------------------------------------
-- Footprints

local type Foot = SquareStressBenchFoot
local type Shape = SquareStressBenchShape

local function townClear() : number
	return logic.TOWN_SIZES[bench.SIZE].spacing * logic.SHOWCASE_TOWN_R + logic.SHOWCASE_GAP
end

--- The shape of variant v with towns on the arms whose compass point is in sides (rotation 0, towns on the axes
--- at one distance: showcaseTownDists, the farthest, rounded up, as the Lights showcase's square layout). nil and
--- why when an arm with a town is not on an axis or a side has no arm.
function bench.shape(v : SquareStressShowcaseType, sides : {string}) : Shape, string
	local params : {string : number} = {}
	for k, x in pairs(v.fixed) do params[k] = x end
	local case_ : SquareStressJunctionCase = { id = v.id, label = v.label, file = v.file, params = params }
	local arms = logic.showcaseArms(case_)
	if arms == nil then return nil, "unknown arms" end
	local want : {string : boolean} = {}
	for _, s in ipairs(sides) do want[s] = true end
	local sh : Shape = { case_ = case_, reach = logic.showcaseReach(case_), degs = {}, offsets = {}, sides = {} }
	for _, d in ipairs(arms) do
		local side = logic.compassOf(d)
		if want[side] then
			if logic.axisUnit(d) == nil then return nil, string.format("arm %g deg is not on an axis", d) end
			sh.degs[#sh.degs + 1] = d
			sh.sides[#sh.sides + 1] = side
			want[side] = nil
		end
	end
	for s in pairs(want) do return nil, "no arm " .. s end
	local spacings : {number} = {}
	for i = 1, #sh.degs do spacings[i] = logic.TOWN_SIZES[bench.SIZE].spacing end
	local far = 0.0
	for _, d in ipairs(logic.showcaseTownDists(sh.reach, sh.degs, spacings, logic.SHOWCASE_TOWN_R)) do far = math.max(far, d) end
	sh.dist = math.ceil(far) + 0.0
	for i, d in ipairs(sh.degs) do
		local u = logic.axisUnit(d)
		sh.offsets[i] = { sh.dist * u[1] + 0.0, sh.dist * u[2] + 0.0 }
	end
	sh.sig = string.format("%s|%s", v.id, table.concat(sh.sides, ","))
	return sh, nil
end

local function footAt(sh : Shape, x : number, y : number) : Foot
	local f : Foot = { jx = x, jy = y, reach = sh.reach, towns = {}, x0 = x - sh.reach, x1 = x + sh.reach, y0 = y - sh.reach, y1 = y + sh.reach }
	for i, o in ipairs(sh.offsets) do
		local tx, ty = x + o[1], y + o[2]
		f.towns[i] = { tx, ty }
		f.x0, f.x1 = math.min(f.x0, tx), math.max(f.x1, tx)
		f.y0, f.y1 = math.min(f.y0, ty), math.max(f.y1, ty)
	end
	return f
end

local function segDist(px : number, py : number, ax : number, ay : number, bx : number, by : number) : number
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = 0.0
	if l2 > 0 then t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) end
	local qx, qy = ax + t * dx - px, ay + t * dy - py
	return math.sqrt(qx * qx + qy * qy)
end

local function orient(ax : number, ay : number, bx : number, by : number, cx : number, cy : number) : number
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
end

local function crosses(a : {number}, b : {number}, c : {number}, d : {number}) : boolean
	return orient(a[1], a[2], b[1], b[2], c[1], c[2]) * orient(a[1], a[2], b[1], b[2], d[1], d[2]) < 0
		and orient(c[1], c[2], d[1], d[2], a[1], a[2]) * orient(c[1], c[2], d[1], d[2], b[1], b[2]) < 0
end

--- Whether two groups' footprints clear each other (BENCH.md "Layout": town to town, junction to town, link to
--- town, link to junction, link to link).
function bench.clear(f : Foot, g : Foot) : boolean
	local tc = townClear()
	local tt = 2 * tc
	local function one(p : Foot, q : Foot) : boolean
		local pj = { p.jx, p.jy }
		for _, t in ipairs(p.towns) do
			for _, u in ipairs(q.towns) do
				if (t[1] - u[1]) ^ 2 + (t[2] - u[2]) ^ 2 < tt * tt then return false end
			end
			local rj = q.reach + tc
			if (t[1] - q.jx) ^ 2 + (t[2] - q.jy) ^ 2 < rj * rj then return false end
			-- p's link to t against q's towns and junction
			for _, u in ipairs(q.towns) do
				if segDist(u[1], u[2], p.jx, p.jy, t[1], t[2]) < bench.LINK_TOWN then return false end
			end
			if segDist(q.jx, q.jy, p.jx, p.jy, t[1], t[2]) < q.reach + bench.LINK_JUNCTION then return false end
			for _, u in ipairs(q.towns) do
				local qj = { q.jx, q.jy }
				if crosses(pj, t, qj, u) then return false end
				local d = math.min(segDist(pj[1], pj[2], qj[1], qj[2], u[1], u[2]), segDist(t[1], t[2], qj[1], qj[2], u[1], u[2]),
					segDist(qj[1], qj[2], pj[1], pj[2], t[1], t[2]), segDist(u[1], u[2], pj[1], pj[2], t[1], t[2]))
				if d < bench.LINK_LINK then return false end
			end
		end
		return true
	end
	return one(f, g) and one(g, f)
end

---------------------------------------------------------------------------
-- The packer

local record Packer
	left : number
	right : number
	bottom : number
	top : number
	placed : {Foot}
	buckets : {integer : {integer}}
	cursor : {string : {number}}   -- shape signature -> the {x, y} of its last spot (every spot before it is taken for it)
end

local function bucketKey(cx : integer, cy : integer) : integer
	return (cx + 5000) * 10007 + (cy + 5000)
end

local function margin() : number
	return 2 * townClear() + 100
end

local function addFoot(pk : Packer, f : Foot)
	pk.placed[#pk.placed + 1] = f
	local m = margin()
	local c = bench.BUCKET
	for cx = math.floor((f.x0 - m) / c), math.floor((f.x1 + m) / c) do
		for cy = math.floor((f.y0 - m) / c), math.floor((f.y1 + m) / c) do
			local k = bucketKey(cx, cy)
			local b = pk.buckets[k]
			if b == nil then b = {} pk.buckets[k] = b end
			b[#b + 1] = #pk.placed
		end
	end
end

local function fits(pk : Packer, f : Foot, extra : {Foot}) : boolean
	for _, t in ipairs(f.towns) do
		if t[1] < pk.left or t[1] > pk.right or t[2] < pk.bottom or t[2] > pk.top then return false end
	end
	if f.jx - f.reach < pk.left or f.jx + f.reach > pk.right or f.jy - f.reach < pk.bottom or f.jy + f.reach > pk.top then return false end
	local c = bench.BUCKET
	local seen : {integer : boolean} = {}
	for cx = math.floor(f.x0 / c), math.floor(f.x1 / c) do
		for cy = math.floor(f.y0 / c), math.floor(f.y1 / c) do
			for _, i in ipairs(pk.buckets[bucketKey(cx, cy)] or {}) do
				if not seen[i] then
					seen[i] = true
					if not bench.clear(f, pk.placed[i]) then return false end
				end
			end
		end
	end
	for _, g in ipairs(extra) do
		if not bench.clear(f, g) then return false end
	end
	return true
end

--- The first spot (rows top to bottom, STEP apart, left to right) for shape sh, from its cursor on.
local function findSpot(pk : Packer, sh : Shape, extra : {Foot}) : Foot
	local cur = pk.cursor[sh.sig]
	local y = cur ~= nil and cur[2] or pk.top
	local x = cur ~= nil and cur[1] or pk.left
	while y >= pk.bottom do
		while x <= pk.right do
			local f = footAt(sh, x, y)
			if fits(pk, f, extra) then
				pk.cursor[sh.sig] = { x, y }
				return f
			end
			x = x + bench.STEP
		end
		x = pk.left
		y = y - bench.STEP
	end
	pk.cursor[sh.sig] = { pk.right + 1, pk.bottom - 1 }
	return nil
end

--- The bench layout of a sheet on a w x h map (offsets from the map centre, town centres and junctions at least
--- `mapMargin` inside): every test in turn, each set whole or not at all (a set that does not fit ends its test;
--- later tests fill what is left), each set's twins one after another in the order rotated by the set (so every
--- twin mode is placed first equally often). Groups and towns as showcaseLayout makes them (Lights showcase names:
--- "<mode> <set> <side>"), with the bench fields (test, variant, litYes, linkLanes, pairLanes). The plan's per-test
--- counts and the estimates come with it.
local memoKey : string = nil
local memoPlan : SquareStressBenchPlan = nil

local function planKey(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet, seed : integer) : string
	-- no seed: the layout does not depend on it (only its seed field, set on every call)
	local parts : {string} = { sheet.id, tostring(w), tostring(h), tostring(mapMargin), tostring(bench.STEP) }
	for _, t in ipairs(sheet.tests) do parts[#parts + 1] = t.id .. ":" .. tostring(t.sets) .. ":" .. tostring(#t.variants) end
	return table.concat(parts, "|")
end

function bench.plan(w : number, h : number, mapMargin : number, sheet : SquareStressBenchSheet, seed? : integer) : SquareStressBenchPlan
	-- the same sheet on the same map again (the window's plan line, then the build): the last plan (it takes ~1 s)
	local key = planKey(w, h, mapMargin, sheet, seed)
	if key == memoKey and memoPlan ~= nil then
		memoPlan.layout.seed = seed or 0
		return memoPlan
	end
	local out : SquareStressBenchPlan = { sheet = sheet, tests = {}, groups = 0, towns = 0, cut = {}, problems = {},
		layout = { seed = seed or 0, towns = {}, groups = {}, square = true, idPrefix = sheet.key } }
	local pk : Packer = { left = -w / 2 + mapMargin, right = w / 2 - mapMargin, bottom = -h / 2 + mapMargin, top = h / 2 - mapMargin,
		placed = {}, buckets = {}, cursor = {} }
	local L = out.layout
	local set = 0
	for _, t in ipairs(sheet.tests) do
		local tp : SquareStressBenchTestPlan = { test = t, wanted = t.sets, sets = 0, groups = 0, towns = 0 }
		out.tests[#out.tests + 1] = tp
		local shapes : {Shape} = {}
		for i, v in ipairs(t.variants) do
			local sh, why = bench.shape(v, t.towns)
			if sh == nil then out.problems[#out.problems + 1] = string.format("%s variant %d: %s", t.id, i, why) else shapes[i] = sh end
		end
		local modes : {SquareStressShowcaseAb} = {}
		for i, ab in ipairs(t.twins) do modes[i] = bench.AB[ab] end
		for k = 1, (#shapes == #t.variants and #shapes > 0) and t.sets or 0 do
			local vi = (k - 1) % #t.variants + 1
			local sh, v = shapes[vi], t.variants[vi]
			local feet : {Foot} = {}
			local order : {integer} = {}
			local saved : {string : {number}} = {}
			for sig, c in pairs(pk.cursor) do saved[sig] = c end
			local n = #modes
			for j = 1, n do order[j] = (j - 1 + k - 1) % n + 1 end
			local ok = true
			for j = 1, n do
				local f = findSpot(pk, sh, feet)
				if f == nil then ok = false break end
				feet[j] = f
			end
			if not ok then
				pk.cursor = saved
				out.cut[#out.cut + 1] = string.format("%s: %d of %d sets", t.id, tp.sets, t.sets)
				break
			end
			set = set + 1
			tp.sets = tp.sets + 1
			for j = 1, n do
				local f = feet[j]
				addFoot(pk, f)
				local m = modes[order[j]]
				local g : SquareStressShowcaseGroup = { name = string.format("Group %d%s", set, m.twin), kind = v.kind, slot = t.id,
					place = { case_ = sh.case_, x = f.jx + 0.0, y = f.jy + 0.0, angle = 0.0, reach = sh.reach, lightsOff = false },
					towns = {}, oneWay = {}, R = sh.dist + townClear(), set = set, twin = m.twin, ab = m.ab, test = t.id, variant = v.label,
					litYes = t.litYes == true, linkLanes = t.linkLanes, pairLanes = t.pairLanes }
				for i, tw in ipairs(f.towns) do
					local ti = #L.towns + 1
					L.towns[ti] = { x = tw[1] + 0.0, y = tw[2] + 0.0, row = 1, col = ti, size = bench.SIZE,
						name = logic.showcaseTownName(v, m, set, sh.sides[i], true) }
					g.towns[i] = ti
				end
				L.groups[#L.groups + 1] = g
				tp.groups = tp.groups + 1
				tp.towns = tp.towns + #f.towns
			end
		end
		out.groups = out.groups + tp.groups
		out.towns = out.towns + tp.towns
	end
	out.persons = out.towns * bench.PERSONS_PER_TOWN
	out.drivers = math.floor(out.persons * bench.DRIVER_SHARE)
	out.buildMin = math.floor(out.towns * bench.BUILD_S_PER_TOWN / 6 + 0.5) / 10
	memoKey, memoPlan = key, out
	return out
end

---------------------------------------------------------------------------
-- The build spec and the log lines

--- The modes of a sheet (every test's twins, each once, in first-use order).
function bench.modes(sheet : SquareStressBenchSheet) : {SquareStressShowcaseAb}
	local out : {SquareStressShowcaseAb} = {}
	local seen : {string : boolean} = {}
	for _, t in ipairs(sheet.tests) do
		for _, ab in ipairs(t.twins) do
			if not seen[ab] then
				seen[ab] = true
				out[#out + 1] = bench.AB[ab]
			end
		end
	end
	return out
end

--- The zone ab names a sheet needs from Smart Lanes beyond game and sl.
function bench.needs(sheet : SquareStressBenchSheet) : {string}
	local out : {string} = {}
	for _, m in ipairs(bench.modes(sheet)) do
		if m.ab ~= "game" and m.ab ~= "sl" then out[#out + 1] = m.ab end
	end
	return out
end

--- The Showcase spec of a sheet: the Lights showcase's town, entry, lock and growth settings, one kind slot per
--- test (its variants as types), every link at its arm's own lanes (BENCH.md "A confound in runs 5 and 6"), and
--- layoutFn giving the bench layout for the map.
function bench.spec(sheet : SquareStressBenchSheet) : SquareStressShowcaseSpec
	local kinds : {string} = {}
	local types : {string : {SquareStressShowcaseType}} = {}
	local kindLog : {string : string} = {}
	local kindWords : {string : string} = {}
	for _, t in ipairs(sheet.tests) do
		kinds[#kinds + 1] = t.id
		types[t.id] = t.variants
		kindLog[t.id] = t.id
		kindWords[t.id] = t.title
	end
	return {
		id = sheet.id, title = sheet.title, kinds = kinds, types = types, kindLog = kindLog, kindWords = kindWords,
		modes = bench.modes(sheet), size = bench.SIZE, misses = 1, litOnly = false,
		growFactor = logic.LIGHTS_GROW_FACTOR, growTarget = bench.POP, growPasses = 1, lockStreets = true, denseWeights = logic.DENSE_WEIGHTS,
		square = true, noBusLines = true, modeNames = true, entries = true, linkLanes = nil, bench = true,
		layoutFn = function(w : number, h : number, mapMargin : number, seed : integer) : SquareStressShowcaseLayout
			return bench.plan(w, h, mapMargin, sheet, seed).layout
		end,
	} as SquareStressShowcaseSpec
end

local function pairsText(list : {{string}}) : string
	local parts : {string} = {}
	for i, p in ipairs(list or {}) do parts[i] = p[1] .. ":" .. p[2] end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- "[SQST] BENCH_TEST sheet= id= ..." (BENCH.md "Log contract additions"), one per test.
function bench.testLine(sheet : SquareStressBenchSheet, tp : SquareStressBenchTestPlan) : string
	local t = tp.test
	local labels : {string} = {}
	for i, v in ipairs(t.variants) do labels[i] = (v.label:gsub("[%s,]+", "_")) end
	return string.format("[SQST] BENCH_TEST sheet=%s id=%s title=%s kind=%s variants=%s twins=%s compare=%s sets=%d/%d groups=%d towns=%d towns_per_twin=%d pop=%d lights=%s",
		sheet.key, t.id, (t.title:gsub("%s+", "_")), t.variants[1] ~= nil and t.variants[1].kind or "-", table.concat(labels, ","),
		table.concat(t.twins, ","), pairsText(t.compare), tp.sets, tp.wanted, tp.groups, tp.towns, #t.towns, bench.POP,
		t.litYes and "yes" or "game")
end

--- The window's plan line: "39 junctions, 132 towns (~53k people), about 11 min to build; 16.0 km map: everything fits".
function bench.planText(p : SquareStressBenchPlan, w : number, h : number) : string
	local cut = #p.cut > 0 and ("; cut: " .. table.concat(p.cut, ", ")) or ": everything fits"
	return string.format("%d junctions, %d towns (~%dk people), about %g min to build; %.1f x %.1f km map%s", p.groups, p.towns,
		math.floor(p.persons / 1000 + 0.5), p.buildMin, w / 1000, h / 1000, cut)
end

---------------------------------------------------------------------------
-- The run (gui/stress_bench_run.tl's pure helpers)

bench.YEAR = 1950            -- the game's automatic traffic lights start this year (traffic_light_config.res.lua)
bench.WARMUP_S = 180         -- game s before the record (flow_report drops --warmup 180 per zone anyway)
bench.RECORD_S = 1200        -- game s recorded (20 game minutes)
bench.INTERVAL = 1           -- the traffic log's interval index: 10 game s (positional thru: every car seen on its approach)
bench.SPEED = 2              -- the game speed while recording (a sweep of ~25k drivers fits a 10 s interval at 2x)
bench.SL_KEYS = { auto = "sqrl_auto", lights = "sqrl_lights", freeTurn = "sqrl_free_turn", phases = "sqrl_light_phases" }

--- Smart Lanes' settings from its raw mod params (1-based option indices; anything else its default, as its own
--- sl_rules.fromModParams): auto / lights booleans, freeTurn "off" | "safe" | "always", phases "game" | "sl".
function bench.slSettings(raw : {string : any}) : SquareStressBenchSl
	local function pick(key : string, n : integer, default : integer) : integer
		local i = tonumber(raw ~= nil and raw[key] or nil)
		if i == nil or i < 1 or i > n or i ~= math.floor(i) then return default end
		return math.floor(i)
	end
	return {
		auto = pick(bench.SL_KEYS.auto, 2, 1) == 1,
		lights = pick(bench.SL_KEYS.lights, 2, 1) == 1,
		freeTurn = ({ "off", "safe", "always" })[pick(bench.SL_KEYS.freeTurn, 3, 3)],
		phases = ({ "game", "sl" })[pick(bench.SL_KEYS.phases, 2, 1)],
	}
end

--- What stops a sheet from running (empty: nothing). info: the preflight's reads.
function bench.problems(sheet : SquareStressBenchSheet, info : SquareStressBenchInfo) : {string}
	local out : {string} = {}
	if info.busy ~= nil then out[#out + 1] = "A test is still queued or running (" .. info.busy .. "). Wait for it to finish." end
	if info.paused then out[#out + 1] = "The game is paused: unpause it (any speed) and press again." end
	if info.plan == nil or info.plan.groups == 0 then
		out[#out + 1] = string.format("Nothing fits this map (%.1f x %.1f km). The bench needs a %g km map.", (info.w or 0) / 1000,
			(info.h or 0) / 1000, sheet.minKm)
	end
	if info.needsRb and not info.rbOk then
		out[#out + 1] = "Roundabouts & Interchanges is not enabled (this sheet builds its roundabouts / interchanges)."
	end
	if not info.slPresent then
		out[#out + 1] = "Smart Lanes is not enabled: the twins would all be the game's."
	else
		local sl = info.sl
		if sl ~= nil and not sl.auto then out[#out + 1] = "Smart Lanes' \"Apply automatically\" is Off: turn it On (mod settings)." end
		if sl ~= nil and sheet.slLights and not sl.lights then
			out[#out + 1] = "Smart Lanes' \"No lights at roundabouts and ramps\" is Off: this sheet compares it On against kept lights; turn it On."
		end
		local missing : {string} = {}
		local have : {string : boolean} = {}
		for _, m in ipairs(info.slModes or {}) do have[m] = true end
		for _, m in ipairs(bench.needs(sheet)) do
			if info.slModes == nil or not have[m] then missing[#missing + 1] = m end
		end
		if #missing > 0 then
			out[#out + 1] = string.format("This Smart Lanes does not know the zone mode%s %s (update Smart Lanes)%s.", #missing == 1 and "" or "s",
				table.concat(missing, ", "), info.slModes == nil and ": it reported no modes" or "")
		end
	end
	return out
end

--- "[SQST] BENCH_START sheet= spec= seed= map= tests= groups= towns= year= sl_auto= sl_lights= sl_free_turn= sl_phases= sl_modes="
function bench.startLine(sheet : SquareStressBenchSheet, info : SquareStressBenchInfo, seed : integer) : string
	local sl = info.sl or {} as SquareStressBenchSl
	local p = info.plan
	return string.format("[SQST] BENCH_START sheet=%s spec=%s@%d seed=%d map=%.0fx%.0f tests=%d groups=%d towns=%d year=%s sl_auto=%s sl_lights=%s sl_free_turn=%s sl_phases=%s sl_modes=%s warmup_s=%d record_s=%d interval_s=%d speed=%d",
		sheet.key, sheet.id, sheet.version, seed, info.w or 0, info.h or 0, #sheet.tests, p ~= nil and p.groups or 0, p ~= nil and p.towns or 0,
		info.year ~= nil and tostring(info.year) or "?", sl.auto and "on" or "off", sl.lights and "on" or "off", sl.freeTurn or "-",
		sl.phases or "-", info.slModes ~= nil and table.concat(info.slModes, ",") or "-", bench.WARMUP_S, bench.RECORD_S, 10, bench.SPEED)
end

return bench
