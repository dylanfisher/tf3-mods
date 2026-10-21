-- Far-out streets after an extent jump (§75 follow-up, 2026-10-20; PLAN.md 6.2 "Far-out streets after an extent jump"):
-- the main body of a town's houses (ot_assess.body: CHECK rBody= / r50= / out= / outFar=, logging only) and the frame
-- tip cap (ot_wedge.tipCap: a frame tip beyond the main body's reach + TIP_LEAD_M is dropped; FRAME tipCut= / maxTipR=).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local A = ug_require(F.DIR .. "ot_assess.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local WG = ug_require(F.DIR .. "ot_wedge.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

--- A block of houses: nx x ny points spaced `step` m from (x0, y0).
local function block(pts, x0, y0, nx, ny, step)
	for i = 0, nx - 1 do
		for j = 0, ny - 1 do pts[#pts + 1] = { x0 + i * step, y0 + j * step } end
	end
	return pts
end

test("body: an outlying group 700 m out is not the body; r jumps, rBody and r50 stay", function()
	eq(A.body({}), nil)
	local pts = block({}, -200, -200, 17, 17, 25)        -- 289 houses, a 400 m square
	local b0 = A.body(pts)
	eq(b0.out, 0)
	eq(b0.groups, 0)
	eq(b0.farN, nil)
	-- + 15 % of the houses in a group ~800 m east (a gap of 600 m)
	block(pts, 750, -50, 8, 6, 25)                       -- 48 houses
	local ext = A.extent(pts)
	local b = A.body(pts)
	eq(b.bodyN, 289)
	eq(b.out, 48)
	eq(b.groups, 1)
	eq(b.farN, 48)
	ok(math.abs(b.rBody - b0.rBody) < 1, string.format("rBody %.0f vs %.0f", b.rBody, b0.rBody))
	ok(ext.r > 1.8 * b.rBody, string.format("the extent jumps: r %.0f, rBody %.0f", ext.r, b.rBody))
	ok(b.r50 < 0.6 * ext.r, string.format("r50 %.0f", b.r50))
	ok(b.farD > 800 and b.farD < 900, "far group distance " .. b.farD)
	ok(b.farDeg < 5 or b.farDeg > 355, "heading east " .. b.farDeg)
	-- text fields
	local rB, r50, out, far = A.bodyFields(b, #pts)
	eq(out, "48/1")
	ok(far:find("^48@8%d%d/%d+$") ~= nil, far)
	ok(tonumber(rB) ~= nil and tonumber(r50) ~= nil)
	eq(select(3, A.bodyFields(nil)), "-")
end)

test("body: gaps under 200 m join the body (a gappy ribbon stays one), wider ones split; the largest group is the body", function()
	-- a ribbon 2 km long, houses every 25 m, with 150 m gaps every 400 m
	local pts = {}
	local x = 0
	for seg = 1, 5 do
		for i = 0, 15 do pts[#pts + 1] = { x + i * 25, 0 } end
		x = x + 15 * 25 + 150
	end
	local b = A.body(pts)
	eq(b.out, 0, "150 m gaps bridged")
	eq(b.groups, 0)
	-- the same with 350 m gaps: five groups, the body one of them
	pts, x = {}, 0
	for seg = 1, 5 do
		for i = 0, (seg == 3 and 30 or 15) do pts[#pts + 1] = { x + i * 25, 0 } end
		x = x + (seg == 3 and 30 or 15) * 25 + 350
	end
	b = A.body(pts)
	eq(b.groups, 4)
	eq(b.bodyN, 31, "the largest group (the third) is the body")
	eq(b.out, #pts - 31)
	-- a twin pair of equal groups: the one nearer the mean of all houses
	pts = block({}, 0, 0, 4, 4, 25)
	block(pts, 600, 0, 4, 4, 25)
	block(pts, 590, 300, 1, 1, 25)
	b = A.body(pts)
	eq(b.bodyN, 16)
	ok(b.bx > 300, "the group nearer the mean")
	-- weights: one point standing for 50 houses
	b = A.body({ { 0, 0, 50 }, { 25, 0, 1 }, { 900, 0, 3 } })
	eq(b.bodyN, 51)
	eq(b.out, 3)
end)

test("body: caps (points read at most BODY_PTS_MAX, every cell visited once) and a centre's reach", function()
	local saved = A.BODY_PTS_MAX
	A.BODY_PTS_MAX = 500
	local pts = block({}, 0, 0, 60, 60, 10)                -- 3600 houses
	local b = A.body(pts)
	ok(b.n <= 500, "read " .. b.n)
	eq(b.out, 0)
	local _, _, out = A.bodyFields(b, #pts)
	eq(out, "0/0")
	A.BODY_PTS_MAX = saved
	-- every point its own cell, far apart: one group each, no endless loop
	pts = {}
	for i = 1, 300 do pts[i] = { i * 1000, (i % 7) * 1000 } end
	b = A.body(pts)
	eq(b.groups, 299)
	-- reach from a centre: the body's farthest house
	b = A.body(block({}, 0, 0, 5, 1, 25), { cx = -100, cy = 0 })
	near(b.reachC, 200, 1e-6)
end)

-- A town for the frame: the round test core with houses on every street, its dead ends free (as test_bigform's frame
-- test); `cluster`: + an outlying comb of the game's streets with houses `d` m out mid-wedge.
local function town(form, townId, cluster)
	local style
	F.withForms(function()
		style = F.style({ forceStyle = "EU_ORGANIC", townId = townId, year = 1920, form = form,
			nameList = "::/names/europe/europe.names" }, F.flat)
	end)
	style.wedges = true
	local g = F.roundCore(OG.new(), { angle = 0.3 * townId })
	for _, e in ipairs(g.edges) do e.game, e.built = true, 2 end
	g.hasBuilt = true
	local tips = {}
	if cluster then
		local sh = style.shape
		local arms = {}
		for _, a in ipairs(sh.arms or { sh.axis }) do arms[#arms + 1] = a % (2 * math.pi) end
		table.sort(arms)
		local h = #arms >= 2 and (arms[1] + arms[2]) / 2 or arms[1] + math.pi / 2
		local ux, uy, vx, vy = math.cos(h), math.sin(h), -math.sin(h), math.cos(h)
		local cx, cy = sh.centre[1], sh.centre[2]
		local prev
		for i = 0, 3 do
			local a = cluster + i * 80
			local nd = OG.addNode(g, nil, cx + a * ux, cy + a * uy, 20)
			if prev then local e = OG.addEdge(g, nil, prev.id, nd.id, "small"); e.game, e.built = true, 6 end
			if i == 1 or i == 3 then
				for _, sg in ipairs({ -1, 1 }) do
					local n2 = OG.addNode(g, nil, cx + a * ux + sg * 80 * vx, cy + a * uy + sg * 80 * vy, 20)
					local e = OG.addEdge(g, nil, nd.id, n2.id, "small")
					e.game, e.built = true, 6
					tips[#tips + 1] = n2
				end
			end
			prev = nd
		end
	end
	return g, style, tips
end

local function farthest(inc, sh)
	local m = 0
	for _, e in ipairs(inc and inc.edges or {}) do
		for _, p in ipairs({ e.p0, e.p1 }) do
			if p then m = math.max(m, math.sqrt((p[1] - sh.centre[1]) ^ 2 + (p[2] - sh.centre[2]) ^ 2)) end
		end
	end
	return m
end

local function framed(g, style, cap)
	local was = WG.TIP_CAP
	WG.TIP_CAP = cap
	local inc, why, info = core.frameIncrement(g, style, { terrain = F.flat })
	WG.TIP_CAP = was
	return inc, why, info
end

test("frame tip cap: an outlying group's tips (an inflated r) are cut, the town's own tips stay", function()
	for _, c in ipairs({ { "fingers", 13 }, { "linear", 15 } }) do
		local g, style, tips = town(c[1], c[2], 900)
		local sh = style.shape
		local inc0, _, i0 = framed(g, style, false)
		ok(inc0 ~= nil and farthest(inc0, sh) > 850, c[1] .. ": without the cap the frame reaches the group "
			.. farthest(inc0, sh))
		eq(i0.tipCap, nil)
		local inc1, why1, i1 = framed(g, style, true)
		ok(i1.tipCap ~= nil and i1.tipCap < 850, "cap " .. tostring(i1.tipCap))
		ok(i1.tipCut >= #tips, c[1] .. ": the group's tips cut " .. i1.tipCut)
		ok(i1.cutMaxR > i1.tipCap and i1.maxTipR <= i1.tipCap, "cut beyond, kept within")
		ok(i1.bodyOut > 0, "houses outside the body " .. tostring(i1.bodyOut))
		ok(inc1 ~= nil, c[1] .. ": the town's own frame still comes: " .. tostring(why1))
		ok(farthest(inc1, sh) <= i1.tipCap, "no frame street beyond the cap")
		-- the same town without the group: the cap drops nothing and the frame is the same
		local gN, styleN = town(c[1], c[2], nil)
		local incA, _, iA = framed(gN, styleN, false)
		local incB, _, iB = framed(gN, styleN, true)
		eq(iB.tipCut, 0)
		eq(iB.bodyOut, 0)
		eq(#incB.edges, #incA.edges)
		eq(iB.maxTipR, iA.maxTipR)
	end
	-- the driver's FRAME fields
	eq(D.tipCapText({ tipCap = 812.4 }), "812")
	eq(D.tipCapText({}), "-")
	eq(D.tipCutText({ tipCut = 5, cutMaxR = 1064.2 }), "5@1064")
	eq(D.tipCutText({ tipCut = 0 }), "0")
end)

test("frame tip cap: normal towns keep every frame (cap on = cap off, no tip cut) over their growth", function()
	-- (the offline measure, PLAN §75: test_bigform / test_spread towns, 0 of 145 / 146 frames changed; here a few
	-- forms over a short growth with every street housed, as the round core above)
	for _, c in ipairs({ { "fingers", 13 }, { "linear", 15 }, { "radiating", 21 }, { "linear", 7 } }) do
		local g, style = town(c[1], c[2], nil)
		local nInc = 0
		for k = 1, 4 do
			local inc = core.planIncrement(g, style, { terrain = F.flat, join = "deadEnd", maxEdges = 24 })
			if #inc.edges > 0 then OG.apply(g, inc, k) end
			for _, e in ipairs(g.edges) do e.built = e.built or 0; if e.built == 0 then e.built = 2 end end
			local incA, whyA, iA = framed(g, style, false)
			local incB, whyB, iB = framed(g, style, true)
			eq(whyB, whyA)
			eq(iB.tipCut or 0, 0, c[1] .. " step " .. k)
			eq(incB and #incB.edges or 0, incA and #incA.edges or 0)
			if incB then nInc = nInc + 1 end
		end
		ok(nInc >= 1, c[1] .. ": frames came " .. nInc)
	end
end)
