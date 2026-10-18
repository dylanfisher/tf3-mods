-- Motif framework (ot_motif, phase M0 of plans/square_organic_towns/MOTIFS_BRIEF.md, 2026-10-13): the registry, the
-- migrated derived kinds (crescents, hill road: behaviour unchanged), the seeded per-town pick (0-2, deterministic),
-- the saved frame field `mo` (old saves: none), neighbour diversity for motifs and the dev-forced kind.
-- The drawn kinds arrive with M1-M4; here a test kind ("test_meadow") stands in for them.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
local CR = ug_require(F.DIR .. "ot_crescent.lua")
local DV = ug_require(F.DIR .. "ot_diverse.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local ORG = ug_require(F.DIR .. "ot_grow_organic.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")

local EU = "::/names/europe/europe.names"
local FLAT = T.stats(F.flat, 0, 0, 600, 24)

--- Runs fn with a drawn test kind registered (eligible everywhere with `score`, or by a function), then removes it.
local planned = 0
local function withTestKind(score, fn, extra)
	local kind = { id = "test_meadow", test = true,
		eligible = function(ctx)
			if type(score) == "function" then return score(ctx) end
			return score, "test"
		end,
		plan = function(mp, style, m, env) planned = planned + 1; mp.testMotif = true end }
	for k, v in pairs(extra or {}) do kind[k] = v end
	MO.register(kind)
	local ok, err = pcall(fn, kind)
	MO.unregister("test_meadow")
	assert(ok, err)
end

local function resolve(id, x, y, o)
	o = o or {}
	local inputs = I.build({ townId = id, pos = { x or 0, y or 0 }, capacity = o.cap or 1500, year = o.year or 1900,
		nameList = EU, terrain = o.terrain or FLAT, autoStyle = o.forceStyle == nil, forceStyle = o.forceStyle,
		frame = o.frame, nbrPicks = o.nbrPicks, motif = o.motif, shape = o.shape })
	return ST.resolve(inputs), inputs
end

local function has(list, id)
	for _, m in ipairs(list or {}) do if m.id == id then return m end end
	return nil
end

test("registry: the migrated kinds, save indices append only, register / unregister", function()
	eq(MO.IDS[1], "crescent")
	eq(MO.IDS[2], "hill_road")
	ok(MO.BY_ID.crescent.derived and MO.BY_ID.hill_road.derived, "the migrated kinds are derived")
	local n = #MO.IDS
	withTestKind(1, function()
		eq(MO.IDS[n + 1], "test_meadow")
		eq(MO.INDEX.test_meadow, n + 1)
		eq(MO.KINDS[#MO.KINDS].id, "test_meadow")
	end)
	eq(MO.BY_ID.test_meadow, nil)
	eq(MO.INDEX.test_meadow, n + 1, "the save index stays reserved")
	-- re-registering keeps its index
	withTestKind(1, function() eq(MO.INDEX.test_meadow, n + 1) end)
	ok(not pcall(MO.register, { id = "Bad Id", eligible = function() return 0 end }), "ids are [a-z_]")
end)

test("encode / decode: two motifs in one number, forced and derived ones never saved, junk ignored", function()
	withTestKind(1, function()
		local i = MO.INDEX.test_meadow
		eq(MO.encode({ { id = "test_meadow" } }), i)
		eq(MO.encode({ { id = "test_meadow" }, { id = "crescent" } }), i + MO.SAVE_BASE * 1)
		eq(MO.encode({ { id = "test_meadow", forced = true } }), nil)
		eq(MO.encode({ { id = "crescent", derived = true } }), nil)
		eq(MO.encode({}), nil)
		local d = MO.decode(i + MO.SAVE_BASE * 1)
		eq(#d, 2); eq(d[1], "test_meadow"); eq(d[2], "crescent")
	end)
	eq(MO.decode(nil), nil); eq(MO.decode(0), nil); eq(MO.decode(-3), nil); eq(MO.decode(2.5), nil)
	eq(MO.decode(63), nil, "an unknown index is skipped")
end)

test("crescent (migrated): derived from the style; the master plan exactly as the pre-M0 rule", function()
	F.withGreen(function()
		local st = resolve(7, 0, 0, { forceStyle = "EU_ORGANIC" })
		ok((st.crescents or 0) > 0)
		local m = has(MO.list(st), "crescent")
		ok(m and m.derived, MO.text(MO.list(st)))
		eq(has(st.motifs, "crescent"), nil, "not among the drawn / saved ones")
		-- masterPlan (through the registry) vs the old direct call
		local g = F.vanillaTown(nil, { n = 3 })
		local mp = core.masterPlan(g, st, {}, 8)
		local ext = ORG.extentFor(g, st)
		local ref = ORG.planFor(g, st, { extent = ext + math.max(core.PLAN_MARGIN, ext * 0.5), snapR = 8 })
		CR.apply(ref, st)
		eq(#mp.pieces, #ref.pieces)
		eq(#mp.crescents, #ref.crescents)
		ok(#mp.crescents > 0)
		-- a style without crescents: no crescent, no cut
		local na = resolve(7, 0, 0, { forceStyle = "NA_GRID" })
		eq(has(MO.list(na), "crescent"), nil)
	end)
	-- greens off (most offline tests): no arcs, as before
	local st = resolve(8, 0, 0, { forceStyle = "EU_ORGANIC" })
	local mp = core.masterPlan(F.vanillaTown(nil, { n = 3 }), st, {}, 8)
	eq(mp.crescents, nil)
end)

test("hill road (migrated): derived from a hillside town drawn linear along its contour", function()
	local slope = T.stats(F.plane(0.09, 0), 0, 0, 600, 24)
	local st = resolve(11, 0, 0, { terrain = slope, shape = "linear" })
	ok(st.shape.reason:find("hillside: along the contour", 1, true), st.shape.reason)
	local m = has(MO.list(st), "hill_road")
	ok(m and m.derived, MO.text(MO.list(st)))
	local flat = resolve(11, 0, 0, { shape = "linear" })
	eq(has(MO.list(flat), "hill_road"), nil, "a linear town on flat land has no hill road")
	-- the measure for the MOTIF build line
	local MT = ug_require(F.DIR .. "ot_metrics.lua")
	local SH = ug_require(F.DIR .. "ot_shape.lua")
	local g = OG.new()
	local prev = OG.addNode(g, nil, st.shape.centre[1], st.shape.centre[2], 20)
	for k = 1, 6 do
		local x = st.shape.centre[1] + math.cos(st.shape.axis) * 80 * k
		local y = st.shape.centre[2] + math.sin(st.shape.axis) * 80 * k
		local n = OG.addNode(g, nil, x, y, 20)
		OG.addEdge(g, nil, prev.id, n.id, "small")
		prev = n
	end
	local r = MO.measure(m, { g = g, inc = { edges = {} }, style = st, pts = {}, sampler = F.plane(0.09, 0), MT = MT, SH = SH })
	ok(r and r.total >= 1 and r.text ~= "-", tostring(r and r.text))
end)

test("pick: deterministic per town, 0-2 drawn, none without eligible kinds", function()
	local st = resolve(21, 100, 200)
	eq(#st.motifs, 0, "no drawn kinds registered: no drawn motifs")
	withTestKind(1, function()
		local counts = { [0] = 0, [1] = 0 }
		for id = 1, 200 do
			local a = resolve(id, id * 10, 0)
			local b = resolve(id, id * 10, 0)
			eq(MO.text(a.motifs), MO.text(b.motifs), "same town, same motifs")
			ok(#a.motifs <= 1, "one drawn kind: at most one")
			counts[#a.motifs] = counts[#a.motifs] + 1
		end
		-- slot 1 chance SLOT_P[1] (0.9 since the final-test round; 0.6 before) unless the derived ones fill the slots
		ok(counts[1] > 155 and counts[1] < 195, "drawn " .. counts[1] .. " of 200")
		ok(counts[0] > 5, "none " .. counts[0])
	end)
	withTestKind(0, function()
		for id = 1, 30 do eq(#resolve(id, id * 10, 0).motifs, 0, "score 0: never") end
	end)
end)

test("pick: derived motifs take slots first (at most MO.MAX in all)", function()
	F.withGreen(function()
		withTestKind(1, function()
			for id = 1, 40 do
				local st = resolve(id, id * 10, 0, { forceStyle = "EU_ORGANIC" })
				ok(#MO.list(st) <= MO.MAX, MO.text(MO.list(st)))
			end
		end)
	end)
end)

test("save / load: the drawn motif goes on the frame (mo), a reload keeps it; old frames get none", function()
	withTestKind(1, function()
		local town, st
		for id = 1, 100 do
			local s = resolve(id, id * 10, 0)
			if #s.motifs > 0 then town, st = id, s; break end
		end
		ok(st, "a town that drew the motif")
		local fp = SV.frameParam(town, st, nil, 900)
		eq(fp.mo, MO.INDEX.test_meadow)
		local state = SV.applyFrame(SV.applyInit(nil, { known = {} }), fp)
		state = SV.normalize(state)   -- (the save's round trip)
		local fr = SV.frame(state, town)
		eq(fr.motifs[1], "test_meadow")
		local again = resolve(town, town * 10, 0, { frame = fr })
		eq(#again.motifs, 1)
		ok(again.motifs[1].saved, "from the frame")
		-- an old frame (no mo) never draws
		local old = SV.frame(SV.applyFrame(nil, { town = town, a = 0.1, x = 0, y = 0 }), town)
		eq(old.motifs, nil)
		eq(#resolve(town, town * 10, 0, { frame = old }).motifs, 0, "old save: none")
		-- a town that drew none saves no field
		for id = 1, 100 do
			local s = resolve(id, id * 10, 0)
			if #s.motifs == 0 then eq(SV.frameParam(id, s, nil).mo, nil); break end
		end
	end)
end)

test("diversity: a motif the neighbours have is drawn less often", function()
	withTestKind(1, function()
		local alone, crowded = 0, 0
		for id = 1, 200 do
			if #resolve(id, id * 10, 0).motifs > 0 then alone = alone + 1 end
			local nb = { { town = 9000, dist = 300, motifs = { "test_meadow" } }, { town = 9001, dist = 900, motifs = { "test_meadow" } } }
			local st, inputs = resolve(id, id * 10, 0, { nbrPicks = nb })
			if #st.motifs > 0 then crowded = crowded + 1 end
			ok(DV.penText(inputs):find("motif:test_meadow=", 1, true), DV.penText(inputs))
		end
		ok(crowded < alone * 0.6, string.format("drawn alone %d, next to towns with it %d", alone, crowded))
		local f = DV.factors({ { dist = 0, motifs = { "a", "b" } } }, "motif")
		near(f.a, DV.MOTIF_MIN, 1e-9); near(f.b, DV.MOTIF_MIN, 1e-9)
		-- gather passes saved motifs on
		local g = DV.gather(1, { 0, 0 }, { { 2, 500, 0 } }, function() return { motifs = { "test_meadow" } } end, nil)
		eq(g[1].motifs[1], "test_meadow")
	end)
end)

test("forced (dev): the kind first, not saved; hill road forces the shape linear; plan hooks run", function()
	withTestKind(0, function()
		local st = resolve(31, 0, 0, { motif = "test_meadow" })
		eq(#st.motifs, 1)
		ok(st.motifs[1].forced)
		eq(MO.source(st.motifs[1]), "forced")
		eq(SV.frameParam(31, st, nil).mo, nil, "forced motifs are not saved")
		planned = 0
		local mp = core.masterPlan(F.vanillaTown(nil, { n = 3 }), st, {}, 8)
		ok(mp.testMotif and planned == 1, "the motif's plan hook ran")
	end)
	local hr = resolve(32, 0, 0, { motif = "hill_road" })
	eq(hr.shape.id, "linear")
	ok(has(hr.motifs, "hill_road").forced)
	-- forced crescent on a style without crescents: one crescent meadow
	local cr = resolve(33, 0, 0, { forceStyle = "NA_GRID", motif = "crescent" })
	eq(cr.crescents, 1)
	ok(cr.greens[1] and cr.greens[1][4], "the first reserve is a crescent meadow")
	eq(#MO.list(cr), 1, "the forced record, the derived duplicate left out")
	eq(MO.text(MO.list(cr)):match("^crescent:%d%.%d+:forced$") ~= nil, true, MO.text(MO.list(cr)))
end)

test("an eligible() error never breaks a town (score 0)", function()
	withTestKind(function() error("boom") end, function()
		local st = resolve(41, 0, 0)
		eq(#st.motifs, 0)
	end)
end)

test("R5 fallback: a drawn kind whose plan lays nothing gives its slot to the next eligible kind that does", function()
	local MOm = ug_require(F.DIR .. "ot_motif.lua")
	MOm.register({ id = "zz_none", eligible = function() return 0.9, "t" end,
		plan = function(_mp, _st, m) m.geo, m.planWhy = nil, "flat" end })
	MOm.register({ id = "zz_also", group = "g1", eligible = function() return 0.8, "t" end,
		plan = function(_mp, _st, m) m.geo, m.planWhy = nil, "short" end })
	local styled = 0
	MOm.register({ id = "zz_geo", eligible = function() return 0.5, "t" end,
		style = function() styled = styled + 1 end,
		plan = function(_mp, _st, m) m.geo, m.planWhy = { ok = true }, nil end })
	local style = { motifs = { { id = "zz_none", score = 0.9, why = "t" } },
		_motifCands = { { id = "zz_none", score = 0.9 }, { id = "zz_also", score = 0.8, group = "g1" }, { id = "zz_geo", score = 0.5 } } }
	MOm.applyPlan({}, style, {})
	eq(style.motifs[1].id, "zz_geo", "replaced")
	eq(style.motifs[1].fallbackFrom, "zz_none:flat")
	eq(styled, 1, "its style hook ran")
	local log = style._motifFallbacks
	eq(#log, 2, "zz_also tried first (failed), then zz_geo")
	eq(log[1].ok, false)
	eq(log[2].ok, true)
	-- a forced kind never falls back
	local st2 = { motifs = { { id = "zz_none", forced = true } }, _motifCands = style._motifCands }
	MOm.applyPlan({}, st2, {})
	eq(st2.motifs[1].id, "zz_none")
	-- the cap
	local saved = MOm.FALLBACK_MAX
	MOm.FALLBACK_MAX = 1
	local st3 = { motifs = { { id = "zz_none" } }, _motifCands = style._motifCands }
	MOm.applyPlan({}, st3, {})
	eq(st3.motifs[1].id, "zz_none", "one try only: zz_also failed")
	MOm.FALLBACK_MAX = saved
	for _, id in ipairs({ "zz_none", "zz_also", "zz_geo" }) do MOm.unregister(id) end
end)
