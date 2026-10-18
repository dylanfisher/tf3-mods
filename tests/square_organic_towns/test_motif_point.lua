-- The peninsula tip motif (ot_motif_point, final-test round 2026-10-13; the user loved Southborough's "small group of
-- houses at the tip of a coastal peninsula"): the spit found from the terrain, eligibility, the spine out along the spit
-- with a cluster of lanes at its tip after simulated increments (join "deadEnd" as in game), the rules (no crossings,
-- no water, grades, configs for every new node), and the registry (append-only save index 18, locked).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
local PT = ug_require(F.DIR .. "ot_motif_point.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local EU = "::/names/europe/europe.names"

local function has(list, id) for _, m in ipairs(list or {}) do if m.id == id then return m end end end

--- A coast at x = coast (sea east of it) with a spit along +x (half width `half`, tip at x = tipX, round end), land
--- rising gently inland (1 %), the spit 3 m above the sea.
local function peninsula(o)
	o = o or {}
	local coast, half, tipX = o.coast or 300, o.half or 110, o.tipX or 1150
	local dir = o.dir or 0
	local c, s = math.cos(dir), math.sin(dir)
	return T.sampler(function(x0, y0)
		local x, y = x0 * c + y0 * s, -x0 * s + y0 * c
		if x <= coast then return 2 + (coast - x) * 0.01 end
		if math.abs(y) <= half and x <= tipX then return 3 end
		if x > tipX and G.dist(x, y, tipX, 0) <= half then return 3 end
		return -3
	end)
end

local function resolve(sampler, o)
	o = o or {}
	local stats = T.stats(sampler, 0, 0, 600, 24)
	stats.spit = PT.findSpit(sampler, 0, 0)   -- (the driver's terrain stage)
	local inputs = I.build({ townId = o.id or 5, pos = { 0, 0 }, capacity = o.cap or 1500, year = o.year or 1905,
		nameList = EU, terrain = stats, forceStyle = o.style or "EU_ORGANIC", motif = o.motif, radius = o.radius or 160 })
	return ST.resolve(inputs), stats, inputs
end

local function ctxOf(st, stats, inputs)
	return { style = st, terrain = stats, inputs = inputs, tier = 2, year = 1905 }
end

local function motifEdges(incs, prefix)
	local n, list = 0, {}
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			if type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then n = n + 1; list[#list + 1] = e end
		end
	end
	return n, list
end

test("registry: peninsula_tip appended (save index 18), drawn, group point, locked", function()
	eq(MO.IDS[18], "peninsula_tip")
	eq(MO.INDEX.peninsula_tip, 18)
	local k = MO.BY_ID.peninsula_tip
	ok(k and not k.derived and k.group == "point" and k.lock and k.plan and k.measure and k.dose)
	eq(MO.LOCK_PREFIX.peninsula_tip, "mpt")
	local v = MO.encode({ { id = "peninsula_tip" } })
	eq(MO.decode(v)[1], "peninsula_tip")
end)

test("findSpit: the narrow land with water on both sides, its tip; none on a plain coast or dry land", function()
	local sp = PT.findSpit(peninsula(), 0, 0)
	ok(sp ~= nil, "a spit")
	print(string.format("      spit %s base=%.0f", PT.text(sp), sp.base))
	ok(G.angleDiff(sp.dir, 0) <= math.rad(12), "toward +x: " .. math.deg(sp.dir))
	ok(sp.tip >= 1050 and sp.tip <= 1300, "tip " .. sp.tip)
	ok(sp.neck >= 500, "neck " .. sp.neck)
	ok(sp.width <= 320, "width " .. sp.width .. " (probes every 50 m)")
	-- turned 120 deg
	local sp2 = PT.findSpit(peninsula({ dir = math.rad(120) }), 0, 0)
	ok(sp2 and G.angleDiff(sp2.dir, math.rad(120)) <= math.rad(12), "turned")
	eq(PT.findSpit(F.coast(300), 0, 0), nil, "a straight coast: no spit")
	eq(PT.findSpit(F.flat, 0, 0), nil, "dry land: no spit")
	-- (R5 2026-10-13: a wide peninsula (800 m, Alsager) is found by the wide pass and flagged; wider still is none)
	local wide = PT.findSpit(peninsula({ half = 400 }), 0, 0)
	ok(wide ~= nil and wide.wide == true, "a wide peninsula: the wide pass")
	ok(PT.text(wide):find("w$"), PT.text(wide))
	ok(not sp.wide, "a narrow spit stays narrow")
	eq(PT.findSpit(peninsula({ half = 700 }), 0, 0), nil, "a broad headland is no spit")
end)

test("eligibility: a spit beyond the houses; none when the town covers it, on a plain coast, for a metropolis", function()
	local st, stats, inputs = resolve(peninsula())
	local s, why = MO.BY_ID.peninsula_tip.eligible(ctxOf(st, stats, inputs))
	print("      peninsula: " .. tostring(s) .. " " .. tostring(why))
	ok(s >= 0.6, "eligible: " .. tostring(why))
	local st2, stats2, in2 = resolve(F.coast(300))
	local s2, why2 = MO.BY_ID.peninsula_tip.eligible(ctxOf(st2, stats2, in2))
	eq(s2, 0, "plain coast: " .. tostring(why2))
	local st3, stats3, in3 = resolve(peninsula(), { radius = 1200 })
	local s3, why3 = MO.BY_ID.peninsula_tip.eligible(ctxOf(st3, stats3, in3))
	eq(s3, 0, "reached: " .. tostring(why3))
	ok(tostring(why3):find("reached", 1, true), why3)
	st.metro = { id = "grid" }
	eq(MO.BY_ID.peninsula_tip.eligible(ctxOf(st, stats, inputs)), 0, "metropolis")
	-- drawn often on such a site (a terrain motif: the town builds with its environment)
	local n = 0
	for id = 1, 60 do
		local a = resolve(peninsula(), { id = id })
		if has(a.motifs, "peninsula_tip") then n = n + 1 end
	end
	print(string.format("      peninsula towns with the tip motif: %d of 60", n))
	ok(n >= 20, "drawn " .. n)
end)

test("growth: one street out along the spit, a cluster of lanes at its tip, the neck kept to it; the rules", function()
	local sampler = peninsula()
	local st, stats = resolve(sampler, { motif = "peninsula_tip" })
	local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
	local incs = core.simulate(g, st, { terrain = sampler, stats = stats, join = "deadEnd" }, 30)
	local m = has(MO.list(st), "peninsula_tip")
	ok(m and m.geo, "planned: " .. tostring(m and m.planWhy))
	local geo = m.geo
	local e = geo.line[#geo.line]
	print(string.format("      spine %.0f m to (%.0f, %.0f), %d lanes, stop=%s", geo.ix.len, e[1], e[2], #geo.lanes,
		tostring(geo.stop)))
	ok(e[1] >= 950 and math.abs(e[2]) <= 60, "spine to near the tip, mid-spit")
	ok(#geo.lanes >= 2, "tip cluster lanes " .. #geo.lanes)
	-- the spine stays on the spit's middle, never on water
	for _, p in ipairs(G.resample(geo.line, 20)) do
		ok(not T.isWater(sampler, p[1], p[2]), "spine on land")
		if p[1] > 450 then ok(math.abs(p[2]) <= 50, "mid-spit " .. p[2]) end
	end
	local mp = core.masterPlan(g, st, { terrain = sampler, stats = stats }, 8)
	-- the plan's own streets keep off the spit beyond the core: nothing built on the neck but the motif's
	for _, inc in ipairs(incs) do
		for _, ed in ipairs(inc.edges) do
			local mx, my = (ed.p0[1] + ed.p1[1]) / 2, (ed.p0[2] + ed.p1[2]) / 2
			if mx > 500 then ok(type(ed.key) == "string" and ed.key:sub(1, 3) == "mpt", "other street on the neck " .. tostring(ed.key)) end
		end
	end
	local n = motifEdges(incs, "mpt")
	local r = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = {}, sampler = sampler, MT = MT, SH = SH, mp = mp })
	print(string.format("      built: %d mpt edges; %s", n, r and r.text or "-"))
	ok(n >= 6, "built " .. n)
	ok(r and r.reach >= 600, "spine built out " .. tostring(r and r.reach))
	-- rules
	local e1 = F.crossingPair(g)
	ok(e1 == nil, "no crossing edges")
	ok(F.minAngle(g) >= 15, "min angle " .. F.minAngle(g))
	for _, inc in ipairs(incs) do
		for _, ed in ipairs(inc.edges) do
			ok(not T.wetAlong(sampler, { { ed.p0[1], ed.p0[2] }, { ed.p1[1], ed.p1[2] } }, 0), "edge on water " .. tostring(ed.key))
			ok(T.grade(sampler, ed.p0[1], ed.p0[2], ed.p1[1], ed.p1[2]) <= st.maxSlope + 0.01, "steep " .. tostring(ed.key))
		end
	end
	-- every new node has a config (the crash rule), lanes valid
	local g2 = F.vanillaTown(nil, { n = 4, spacing = 80 })
	local specs = 0
	for k = 1, 30 do
		local inc = core.planIncrement(g2, st, { terrain = sampler, stats = stats, join = "deadEnd" })
		if #inc.edges == 0 then break end
		local inf = { nodes = {}, sources = {}, fallback = 902 }
		for _, jn in ipairs(inc.joins) do
			local edges = {}
			for _, eid in ipairs(g2.adj[jn.node] or {}) do edges[#edges + 1] = eid end
			inf.nodes[jn.node] = { hasConfig = true, edges = edges, lanes = 4, src = edges[1] or 902,
				template = "::/infrastructure/street/town/town_new_small.street_template" }
		end
		local spec, err = PR.build(inc, inf)
		ok(spec ~= nil, tostring(err))
		if spec then
			specs = specs + 1
			local cfg = {}
			for _, cc in ipairs(spec.cfgAdd) do cfg[cc.node] = true end
			for _, nd in ipairs(spec.nodes) do ok(cfg[nd.entity], "node without a config") end
			ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
		end
		OG.apply(g2, inc, k)
	end
	ok(specs >= 6, specs .. " specs")
	-- the motif's streets are locked; the dose goes beside them
	local inc
	for _, x in ipairs(incs) do if motifEdges({ x }, "mpt") > 0 then inc = x; break end end
	local keys, nk = D.lockKeys({ style = st, inc = inc })
	ok(keys and nk >= 1, "locked")
	local pts = MO.dose(st, inc.edges, 20, 4)
	ok(#pts >= 1, "dose beside the spine")
end)
