-- Showcase v8 round (2026-10-12, NEXT_PHASE_BRIEF 15): arm towns keep extending as houses arrive (the v7 linear
-- regression), town forms (ot_form: the same style spreads differently per town), the metropolis variants with a
-- form, lattice-first superblocks / NA grids on a game-made core, the orientation metric.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local MET = ug_require(F.DIR .. "ot_metro.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")

--- houses in game (Showcase v7 linear town: 167 after step 1, 878 after step 10), filled from the core outward
local function houses(k) return 150 + 75 * k end

--- n increments of 18 edges from a round core, houses arriving after each (F.markBuilt: as the driver's snapshot
--- sees them). Empty increments don't stop the town (the houses keep coming, as in game). Returns graph, style.
local function grow(raw, n, town)
	local r = { forceStyle = "EU_EXTENSION", townId = town, year = 2020 }
	for k, v in pairs(raw) do r[k] = v end
	local style, stats = F.style(r, F.flat)
	local g = F.roundCore(OG.new(), { angle = 0.3 * town })
	F.markBuilt(g, houses(0))
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
		if #inc.edges > 0 then OG.apply(g, inc, k) end
		F.markBuilt(g, houses(k))
	end
	return g, style
end

local TOWNS = { 1, 7, 13, 21 }

local function meanFor(raw, n)
	local se, he, worst = 0, 0, 0
	for _, town in ipairs(TOWNS) do
		local g, style = grow(raw, n, town)
		se = se + MT.graph(g, 0, 0).elong / #TOWNS
		he = he + F.houses(g, houses(n)).elong / #TOWNS
		for _, x in ipairs(SEL.armGaps(g, style) or {}) do worst = math.max(worst, x.street - x.housed) end
	end
	return se, he, worst
end

test("arm towns keep extending once the stretch behind is housed (Showcase v7: the linear town grew round)", function()
	local blk = 110
	for _, shape in ipairs({ "linear", "ridge" }) do
		local se, he, worst = meanFor({ shape = shape }, 10)
		print(string.format("      %-7s streets elong %.2f, houses elong %.2f, worst arm gap %.0f m", shape, se, he, worst))
		ok(se >= 2.5, shape .. " streets elong " .. se)
		ok(he >= 1.8, shape .. " houses elong " .. he)
		-- no empty ladders: the streets run at most the fill lead + its relaxation (+ one edge) past the last house
		ok(worst <= (SEL.ARM_FILL_LEAD + SEL.ARM_FILL_RELAX) * blk + 100, shape .. " worst gap " .. worst)
	end
	-- the v7 behaviour (the envelope widened whenever the fill rule held the arms back): round
	local saved = SEL.ARM_STRONG_HOLD
	SEL.ARM_STRONG_HOLD = false
	local ok0, se0 = pcall(meanFor, { shape = "linear" }, 10)
	SEL.ARM_STRONG_HOLD = saved
	assert(ok0, se0)
	print(string.format("      linear without the hold (v7): streets elong %.2f", se0))
	ok(se0 < 1.6, "v7 reproduced: " .. se0)
end)

test("forms: forced, saved with the frame, legacy frames without one, site-picked shapes decide, seeded draws vary", function()
	F.withForms(function()
		-- forced (dev)
		local p = F.style({ forceStyle = "JP_DENSE", townId = 3, form = "sprawling" })
		eq(p.form.id, "sprawling")
		local base = F.style({ forceStyle = "JP_DENSE", townId = 3, form = "clustered" })
		near(p.block.len / base.block.len, FM.DEF.sprawling.block / FM.DEF.clustered.block, 1e-9, "sprawling: larger blocks")
		ok(#p.greens >= FM.DEF.sprawling.greensMin, "sprawling leaves meadows")
		eq(#base.greens, 0, "clustered fills every block")
		eq(base.shape.id, "compact")
		local lin = F.style({ forceStyle = "JP_DENSE", townId = 3, form = "linear" })
		eq(lin.shape.id, "linear"); eq(lin.shape.reach, 1)
		ok(lin.shape.reason:find("form:", 1, true), lin.shape.reason)
		local rad = F.style({ forceStyle = "EU_EXTENSION", townId = 3, form = "radiating" })
		eq(rad.shape.id, "cross"); eq(rad.shape.reach, 1)
		-- saved: the frame carries the form index; a frame without one (older saves) gets no form at all
		local fp = SV.frameParam(5, lin, nil, 900)
		eq(fp.f, FM.INDEX.linear)
		local st = SV.applyFrame(SV.applyInit(nil, { known = {} }), fp)
		local fr = SV.frame(st, 5)
		eq(fr.form, "linear")
		local again = F.style({ forceStyle = "JP_DENSE", townId = 3, frame = fr })
		eq(again.form.id, "linear"); eq(again.form.why, "saved")
		eq(again.shape.id, "linear")
		local legacy = SV.frame(SV.normalize({ v = 1, known = {}, frames = { ["5"] = { a = 0, x = 1, y = 2, s = 1 } } }), 5)
		eq(legacy.form, nil)
		local old = F.style({ forceStyle = "JP_DENSE", townId = 3, frame = legacy })
		eq(old.form, nil, "a legacy frame: no form, the town grows as before")
		eq(old.block.len, ST.profile("JP_DENSE").block.len)
		-- dev-forced shape (shape row): no form
		eq(F.style({ forceStyle = "EU_EXTENSION", townId = 3, shape = "fan" }).form, nil)
		-- a valley picks a linear shape from the site: the form follows it
		local valley = F.style({ forceStyle = "EU_EXTENSION", townId = 3, nameList = "::/names/europe/europe.names" }, F.valley(0.4))
		if valley.shape.id == "linear" and valley.shape.reason:find("valley", 1, true) then
			eq(valley.form.id, "linear"); ok(valley.form.why:find("shape:", 1, true))
		end
		-- seeded draws: the same style varies between towns
		local seen, n = {}, 0
		for id = 1, 40 do
			local q = F.style({ forceStyle = "JP_DENSE", townId = id, pos = { id * 113, id * 7 } })
			if q.form then
				seen[q.form.id] = (seen[q.form.id] or 0) + 1
				n = n + 1
				eq(F.style({ forceStyle = "JP_DENSE", townId = id, pos = { id * 113, id * 7 } }).form.id, q.form.id, "deterministic")
			end
		end
		local kinds = 0
		for _ in pairs(seen) do kinds = kinds + 1 end
		print(string.format("      JP dense, 40 towns: %d forms (%s)", kinds, (function()
			local t = {}
			for k, v in pairs(seen) do t[#t + 1] = k .. "=" .. v end
			table.sort(t)
			return table.concat(t, " ")
		end)()))
		eq(n, 40)
		ok(kinds >= 3, "at least three forms")
		ok((seen.clustered or 0) > (seen.linear or 0), "JP dense mostly clustered, rarely linear")
	end)
	-- forms off (the other tests): nothing changes
	eq(F.style({ forceStyle = "JP_DENSE", townId = 3 }).form, nil)
end)

test("form row: JP dense clustered vs radiating vs sprawling vs linear grow distinctly", function()
	F.withForms(function()
		local m = {}
		for _, form in ipairs({ "clustered", "radiating", "sprawling", "linear" }) do
			local acc = { elong = 0, arms = 0, len = 0, blk = 0 }
			for _, town in ipairs({ 1, 7 }) do
				local g, style = grow({ forceStyle = "JP_DENSE", form = form }, 10, town)
				local mm = MT.graph(g, 0, 0)
				acc.elong, acc.arms = acc.elong + mm.elong / 2, acc.arms + mm.arms / 2
				acc.blk = style.block.len
			end
			m[form] = acc
			print(string.format("      JP dense %-10s elong %.2f arms %.1f block %.0f", form, acc.elong, acc.arms, acc.blk))
		end
		ok(m.linear.elong >= m.clustered.elong + 0.3, "linear longer than clustered")
		ok(m.sprawling.blk > m.clustered.blk * 1.3, "sprawling looser")
		ok(m.clustered.elong <= 1.4, "clustered compact")
	end)
end)

test("metropolis with a form: radial + radiating grows fingers on its spokes, grid + linear stays linear", function()
	F.withForms(function()
		local b = F.style({ forceStyle = "EU_EXTENSION", townId = 4, year = 2000, capacity = 6000, form = "radiating",
			nameList = "::/names/europe/europe.names" })
		local s = MET.apply(b, { variant = "radial" }, { cap = 6000 })
		eq(s.shape.id, "fingers")
		eq(#s.shape.arms, s.radial.spokes, "one finger per spoke")
		eq(s.shape.reach, 1)
		eq(s.metro.form, "radiating")
		local c = MET.apply(F.style({ forceStyle = "EU_EXTENSION", townId = 4, year = 2000, form = "clustered",
			nameList = "::/names/europe/europe.names" }), { variant = "radial" }, { cap = 6000 })
		eq(c.shape.id, "compact")
		local gl = MET.apply(F.style({ forceStyle = "NA_GRID", townId = 4, year = 2000, form = "linear" }), { variant = "grid" }, { cap = 6000 })
		eq(gl.shape.id, "linear"); eq(#gl.shape.arms, 2)
		local g0 = MET.apply(F.style({ forceStyle = "NA_GRID", townId = 4, year = 2000 }), { variant = "grid" }, { cap = 6000 })
		eq(g0.shape.id, "compact")
	end)
end)

test("lattice first: superblock and NA grid lay out their arterial frame on a game-made core", function()
	local function wideShare(styleId, lattice)
		local style, stats = F.style({ forceStyle = styleId, townId = 5, year = 2020 }, F.flat)
		local keep = style.lattice
		if not lattice then style.lattice = nil end
		local g = F.roundCore(OG.new(), { angle = 0.12 })
		local mix = nil
		for k = 1, 10 do
			local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
			if #inc.edges == 0 then break end
			mix = core.addMix(mix, inc.mix)
			OG.apply(g, inc, k)
		end
		style.lattice = keep
		return mix and (mix.large + mix.medium) / math.max(1, mix.total) or 0, mix and mix.total or 0
	end
	for _, id in ipairs({ "SUPERBLOCK", "NA_GRID" }) do
		local w1, l1 = wideShare(id, true)
		local w0, l0 = wideShare(id, false)
		print(string.format("      %-10s wide share %.0f %% (%.0f m) with the lattice first, %.0f %% (%.0f m) without", id, 100 * w1, l1, 100 * w0, l0))
		-- (a game-made core: v7's superblock grew 6-12 edges per increment, mostly small loops at the edge)
		ok(w1 >= w0, id .. " frame first: " .. w1 .. " vs " .. w0)
		ok(l1 > l0 * 1.3, id .. " grows more: " .. l1 .. " vs " .. l0)
	end
end)

test("orientation metric: a grid is orthogonal, spokes and rings read radial / ring", function()
	local g = OG.new()
	local ids = {}
	for i = -4, 4 do
		for j = -4, 4 do ids[i .. ":" .. j] = OG.addNode(g, nil, i * 100, j * 100, 0).id end
	end
	for i = -4, 4 do
		for j = -4, 4 do
			if i < 4 then OG.addEdge(g, nil, ids[i .. ":" .. j], ids[(i + 1) .. ":" .. j], {}) end
			if j < 4 then OG.addEdge(g, nil, ids[i .. ":" .. j], ids[i .. ":" .. (j + 1)], {}) end
		end
	end
	local o = MT.orientation(g, 0, 0)
	ok(o.orth > 0.95, "grid orth " .. o.orth)
	-- spokes and rings
	local r = OG.new()
	local c = OG.addNode(r, nil, 0, 0, 0).id
	local ring = {}
	for k = 0, 23 do
		local a = k * math.pi / 12
		ring[k] = {}
		for ri, rr in ipairs({ 200, 400, 600 }) do ring[k][ri] = OG.addNode(r, nil, rr * math.cos(a), rr * math.sin(a), 0).id end
	end
	for k = 0, 23 do
		OG.addEdge(r, nil, c, ring[k][1], {})
		OG.addEdge(r, nil, ring[k][1], ring[k][2], {})
		OG.addEdge(r, nil, ring[k][2], ring[k][3], {})
		for ri = 1, 3 do OG.addEdge(r, nil, ring[k][ri], ring[(k + 1) % 24][ri], {}) end
	end
	local q = MT.orientation(r, 0, 0)
	ok(q.spokes > 0.9, "radial city spokes " .. q.spokes)
	ok(q.radial > 0.5 and q.ring > 0.3, MT.orientText(q))
	ok(o.spokes < q.spokes, "a grid reads less radial")
end)
