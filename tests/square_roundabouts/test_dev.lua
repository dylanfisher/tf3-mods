-- Phase 4 dev overrides (geom.readDev, sqrb_dev_* params): read only when present, never in a
-- menu; each one changes exactly its part of the layout. The probe passes them to the engine.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local S = geom.shapes
local K = geom.PARAM_KEYS
local D = geom.DEV_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()

local function params(over, dev)
	local p = {}
	for k, v in pairs(over or {}) do p[K[k]] = v end
	for k, v in pairs(dev or {}) do p[D[k]] = v end
	return p
end
local function build(over, dev) return geom.build(geom.readParams(params(over, dev))) end
local function buildMagic(over, dev)
	local p = {}
	for k, v in pairs(over or {}) do p[magic.PARAM_KEYS[k]] = v end
	for k, v in pairs(dev or {}) do p[D[k]] = v end
	return magic.build(magic.readParams(p))
end
local function roleLists(b, role)
	local out = {}
	for _, l in ipairs(b.lists) do if l.role == role then out[#out + 1] = l end end
	return out
end
local function clean(b, what)
	checks.report(checks.tags(b.lists), what .. " tags")
end

test("readDev: nil without dev keys; numbers in range only", function()
	eq(geom.readDev({}), nil)
	eq(geom.readDev({ sqrb_radius = 3, height = 1 }), nil)
	eq(geom.readDev({ [D.radius] = 25, [D.fork] = "40" }), { radius = 25, fork = 40 })
	eq(geom.readDev({ [D.radius] = 1, [D.leg] = 1.5, [D.neckType] = 9, [D.fork] = 0 / 0 }), nil)
	for name, key in pairs(D) do
		ok(key:sub(1, 9) == "sqrb_dev_", key)
		ok(geom.DEV_RANGES[name], name .. " has a range")
	end
	eq(geom.readParams({}).dev, nil)
end)

test("no .con.lua param uses a dev key", function()
	for _, file in ipairs({ "square_roundabouts.con.lua", "square_roundabouts_magic.con.lua",
		"square_roundabouts_channel.con.lua", "square_roundabouts_interchange.con.lua" }) do
		ug_require(DIR .. file)
		for _, p in ipairs(data().params) do ok(p.key:find("dev", 1, true) == nil, file .. ": " .. p.key) end
	end
end)

test("dev radius: exactly that radius, no growth, no floor; offline tells what the model says", function()
	local b = build({ splitter = 2, armType = 3 }, { radius = 20 }) -- ships 30 m (test_geom: TESTING.md 9.3.4)
	eq(b.radius, 20)
	eq(b.b, 20 + geom.RING_OFFSET[2])
	eq(b.offline, false)
	eq(b.forced, true)
	clean(b, "forced 20 m")
	local d = build({}, { radius = 20 })
	eq(d.offline, true)
	eq(d.forced, nil)
	eq(build({}).offline, nil)
	for _, r in ipairs({ 3, 8, 13, 47.5, 120, 200 }) do
		local x = build({ shape = 5, lanes = 1, arms = 5 }, { radius = r })
		eq(x.radius, r)
		near(x.b, r + geom.RING_OFFSET[1], 1e-9)
		near(x.a, 2 * r + geom.RING_OFFSET[1], 1e-9)
		eq(x.mini, r < geom.MINI_RADIUS_BELOW)
	end
end)

test("dev splitter: split distance, fork, spread and leg template", function()
	local base = { splitter = 2, armType = 2 }
	local d = build(base, { radius = 40 })
	local x = build(base, { radius = 40, split = 40, fork = 55, spread = 9, leg = 3 })
	eq(#x.legs, #d.legs)
	local leg, legD = x.legs[1], d.legs[1]
	local u = S.norm(legD.split) -- arm 1 points east on a round ring
	-- from the shipped split distance (town medium: the engine-tuned rule's, Phase 4b)
	near(S.dist(leg.split, legD.split), 40 - geom.splitParams(d.spec).split, 1e-6, "split node moves out")
	near(S.dot(leg.split, u), x.a + x.halfWidth + 40, 1e-6)
	-- fork: the entry leg leaves the split node at 55 degrees from the inward axis
	local t = S.norm(leg.entry.t0)
	near(math.deg(math.acos(-S.dot(t, u))), 55, 1e-6)
	eq(roleLists(x, "legs")[1].template, geom.DEV_LEGS[3].entry.template)
	eq(roleLists(x, "legs")[1].halfWidth, 12)
	local sp = geom.splitParams(x.spec)
	near(sp.spread, 9, 1e-9)
	-- tram on: the leg's tram variant
	local tr = build({ splitter = 2, armType = 2, tram = 2 }, { radius = 40, leg = 3 })
	eq(roleLists(tr, "legs")[1].template, geom.DEV_LEGS[3].tram.template)
	local tr1 = build({ splitter = 2, armType = 2, tram = 2 }, { radius = 40, leg = 2 })
	eq(roleLists(tr1, "legs")[1].template, geom.LEG_TRAM.template)
	clean(x, "dev splitter")
end)

test("dev neck: a narrower two-way piece between the split node and the arm", function()
	for _, case in ipairs({ { armType = 3, neckType = 1 }, { armType = 6, neckType = 4 }, { armType = 2, neckType = 1 } }) do
		local b = build({ splitter = 2, armType = case.armType }, { radius = 40, neck = 15 })
		local necks = roleLists(b, "neck")
		eq(#necks, 1)
		eq(necks[1].template, geom.ARM_TEMPLATES[case.neckType])
		eq(#necks[1].edges, #b.legs)
		for _, leg in ipairs(b.legs) do
			local neck, arm
			for _, e in ipairs(necks[1].edges) do if e.arm == leg.arm then neck = e end end
			for _, e in ipairs(b.arms.edges) do if e.arm == leg.arm then arm = e end end
			eq(neck.tag0, leg.entry.tag0, "neck starts at the split node")
			eq(neck.p0, leg.split)
			near(checks.edgeLength(neck), 15, 1e-6)
			eq(arm.tag0, neck.tag1, "arm starts at the neck's end")
			near(checks.edgeLength(arm), geom.ARM_LENGTH, 1e-6)
		end
		clean(b, "neck")
	end
	local t = build({ splitter = 2, armType = 3 }, { radius = 40, neck = 10, neckType = 2 })
	eq(roleLists(t, "neck")[1].template, geom.ARM_TEMPLATES[2])
	local tram = build({ splitter = 2, armType = 3, tram = 2 }, { radius = 40, neck = 10 })
	eq(roleLists(tram, "neck")[1].template, geom.ARM_TRAM[1].template)
	eq(#roleLists(build({ splitter = 2, armType = 3 }, { radius = 40, neck = 0 }), "neck"), 0)
	-- the split node's junction check uses the neck's width (narrower: never stricter)
	local spec = geom.readParams(params({ splitter = 2, armType = 3 }, { neck = 15 }))
	eq(geom.forkRoadHalfWidth(spec, geom.splitParams(spec)), geom.ARM_HALF_WIDTH[1])
end)

test("dev tram stub: stub length of the tram line through the centre", function()
	local function stubLen(b)
		for _, l in ipairs(roleLists(b, "through")) do
			if l.template ~= geom.TRAM_THROUGH.template and #l.edges == 2 then return checks.edgeLength(l.edges[1]) end
		end
	end
	local d = build({ centre = 3 }, { radius = 40 })
	near(stubLen(d), d.halfWidth + geom.TRAM_STUB, 1e-6)
	local x = build({ centre = 3 }, { radius = 40, tramStub = 8 })
	near(stubLen(x), x.halfWidth + 8, 1e-6)
	clean(x, "tram stub")
end)

test("dev magic: exact size, satellite radius, spacing; no growth", function()
	local d = buildMagic({ armType = 3, size = 1 })
	ok(d.size >= 4, "ships at least Large for town large")
	eq(d.offline, nil)
	local x = buildMagic({ armType = 3, size = 1 }, { magicSize = 1 })
	eq(x.size, 1)
	eq(x.offline, false)
	near(x.rs, magic.SIZES[1].radius + geom.RING_OFFSET[1], 1e-9)
	near(x.distance, magic.SIZES[1].distance, 1e-9)
	local r = buildMagic({}, { magicRadius = 25 })
	near(r.rs, 30, 1e-9)
	near(r.distance, 91, 1e-9) -- 3 x 30 + 1
	eq(r.mini, false)
	local s = buildMagic({}, { magicRadius = 12, magicDistance = 45 })
	near(s.distance, 45, 1e-9)
	eq(s.mini, true)
	-- spacing is kept above DEV_MIN_SPACING x the satellite centreline radius
	local c = buildMagic({}, { magicRadius = 20, magicDistance = 10 })
	near(c.distance, magic.DEV_MIN_SPACING * 25, 1e-9)
	for _, b in ipairs({ x, r, s, c }) do clean(b, "magic dev") end
	eq(buildMagic({}, { radius = 30 }).size, magic.DEFAULT_SIZE, "main-entry dev keys do nothing here")
end)

-- Phase 5e: Channelized Junction / Roundabout Interchange tunables (the probe's p5_*_search subsets)
test("dev channel / interchange: absent = shipped build; each override changes its part only", function()
	local ch = ug_require(DIR .. "square_roundabouts_channel.lua")
	local ix = ug_require(DIR .. "square_roundabouts_interchange.lua")
	local function chBuild(over, dev)
		local p = {}
		for k, v in pairs(over or {}) do p[ch.PARAM_KEYS[k]] = v end
		for k, v in pairs(dev or {}) do p[D[k]] = v end
		return ch.build(ch.readParams(p))
	end
	local function ixBuild(over, dev)
		local p = {}
		for k, v in pairs(over or {}) do p[ix.PARAM_KEYS[k]] = v end
		for k, v in pairs(dev or {}) do p[D[k]] = v end
		return ix.build(ix.readParams(p))
	end
	eq(ch.readParams({}).dev, nil)
	eq(ix.readParams({}).dev, nil)
	-- the shipped values as overrides build the same layout (X, town small main road: the engine
	-- accepted 40 deg one-way xsmall slip lanes, no tuning row)
	local c0 = chBuild({ layout = 2, main = 1, splitter = 2 })
	eq(ch.tuningRow(c0.spec), nil)
	eq(chBuild({ layout = 2, main = 1, splitter = 2 }, { chSlipAngle = 40, chCornerGap = ch.CORNER_GAP, chSlipFree = ch.SLIP_FREE, chSlip = 1 }).setback, c0.setback)
	-- a smaller free length / corner gap pulls the slip nodes in; a steeper angle shortens the gore
	-- (without splitter islands the island room rule sets the set-backs: free length and corner gap
	-- together pull the slip nodes in; the angle moves them either way)
	local c1 = chBuild({ layout = 2, main = 1 })
	local g = chBuild({ layout = 2, main = 1 }, { chCornerGap = 0 })
	ok(g.setback.main < c1.setback.main and g.setback.side < c1.setback.side, "chCornerGap")
	local f = chBuild({ layout = 2, main = 1 }, { chCornerGap = 0, chSlipFree = 0 })
	ok(f.setback.main < g.setback.main and f.setback.side < g.setback.side, "chSlipFree")
	local a = chBuild({ layout = 2, main = 1 }, { chSlipAngle = 50 })
	ok(a.setback.main ~= c1.setback.main, "chSlipAngle")
	-- Phase 5f: the slip lane template
	local w = chBuild({ layout = 2, main = 1 }, { chSlip = 3 })
	eq(w.slipRoad.template, ch.SLIP_TEMPLATES[3].template, "chSlip")
	ok(w.setback.main > c1.setback.main, "chSlip: a wider slip lane, a longer gore")
	-- dev overrides win over a tuning row (X, town medium main road: 65 deg one-way xsmall since
	-- Phase 5g, was none -> ch.FALLBACK)
	local fb = chBuild({ layout = 2 })
	eq(fb.slipSource, "engine"); eq(fb.slipAngle, 65)
	local dv = chBuild({ layout = 2 }, { chSlipAngle = 40, chSlip = 1 })
	eq(dv.slipAngle, 40); eq(dv.slipRoad.template, ch.SLIP.template)
	for _, b in ipairs({ f, g, a, w, dv }) do clean(b, "channel dev") end
	eq(chBuild({}, { radius = 30, ixClear = 2 }).setback, chBuild({}).setback, "other entries' dev keys do nothing here")

	local x0 = ixBuild({ layout = 2 })
	local x1 = ixBuild({ layout = 2 }, { ixClear = ix.CLEAR, ixGamma = 35, ixGoreRun = ix.GORE_RUN, ixWaistGap = ix.WAIST_GAP })
	eq(x1.D, x0.D); eq(x1.radius, x0.radius); eq(#x1.ramps, #x0.ramps)
	ok(ixBuild({ layout = 2 }, { ixClear = 4 }).D < x0.D, "ixClear")
	local gm = ixBuild({ layout = 2 }, { ixGamma = 20 })
	local differs = false
	for i, e in ipairs(x0.ramps) do
		local o = gm.ramps[i]
		for _, v in ipairs({ "t0", "t1" }) do
			if math.abs(o[v][1] - e[v][1]) > 1e-6 or math.abs(o[v][2] - e[v][2]) > 1e-6 then differs = true end
		end
	end
	ok(differs, "ixGamma")
	local small = ixBuild({ highway = 1 })
	local gr = ixBuild({ highway = 1 }, { ixGoreRun = 20 })
	ok(gr.ramps[1] ~= nil)
	local function goreLen(b)
		for _, e in ipairs(b.ramps) do if e.part == "gore" then return math.abs(e.p1[1] - e.p0[1]) end end
	end
	ok(goreLen(gr) < goreLen(small), "ixGoreRun")
	-- Phase 5f: the two-bridge ring's largest slip node angle (4 lanes ship 45 deg, Phase 5g)
	local tb = ixBuild({ lanes = 2 })
	local tb40 = ixBuild({ lanes = 2 }, { ixAlphaMax = 40 })
	ok(tb40.alpha <= 40 * math.pi / 180 + 1e-9 and tb40.radius > tb.radius, "ixAlphaMax")
	eq(ixBuild({ lanes = 3 }, { ixAlphaMax = 45 }).radius, ixBuild({ lanes = 3 }).radius, "4 lanes: 45 deg shipped")
	local p0 = ixBuild({ layout = 3 })
	ok(ixBuild({ layout = 3 }, { ixWaistGap = 2 }).beta < p0.beta, "ixWaistGap")
	eq(ixBuild({ layout = 3 }, { radius = 40, chSlipAngle = 30 }).D, p0.D, "other entries' dev keys do nothing here")
end)
