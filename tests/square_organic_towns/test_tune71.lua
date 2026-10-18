-- §71 (2026-10-16; run 2026-10-16_0405_sqot): small woods don't count for the steer lock's face rules (ot_forest
-- woodSizes / bigWoodAt; ot_lockpol.facing, ot_glock valves and tips; `smallWood=`), and no curled hook dead ends
-- (ot_knot.hook + ot_select M.HOOK; `hookHeld=`, relaxed only when the increment would be empty).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local FO = ug_require(F.DIR .. "ot_forest.lua")
local SK = ug_require(F.DIR .. "ot_skeleton.lua")
local LP = ug_require(F.DIR .. "ot_lockpol.lua")
local GL = ug_require(F.DIR .. "ot_glock.lua")
local KN = ug_require(F.DIR .. "ot_knot.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")

-- a copse: 2 x 2 cells (1 ha) east of the town at x 300..400; a wood: 6 x 6 cells (9 ha) there
local function box(x0, x1, y0, y1)
	return FO.fromFunction(0, 0, function(x, y) return (x > x0 and x < x1 and y > y0 and y < y1) and 200 or 0 end, 1500, 50)
end
local copse = function() return box(300, 400, -50, 50) end
local wood = function() return box(300, 600, -150, 150) end

test("wood sizes: a copse is small, a wood big, a border patch big; the size counts only dense cells", function()
	eq(FO.woodMinCells({ cell = 50 }), 7)
	local c = copse()
	ok(FO.cover(c, 350, 0) >= SK.DENSE, "the copse is dense")
	ok(not FO.bigWoodAt(c, 325, 25), "a copse of 1 ha does not count")
	local w = wood()
	ok(FO.bigWoodAt(w, 450, 0), "a wood of 9 ha counts")
	ok(not FO.bigWoodAt(w, 100, 0), "open land")
	-- (touching the grid's border: its size beyond unknown: big)
	local edge = box(1400, 2000, -40, 40)
	ok(FO.bigWoodAt(edge, 1475, 0))
	-- near: within r of a big cell
	ok(FO.bigWoodNear(w, 250, 0, 60)); ok(not FO.bigWoodNear(w, 150, 0, 60)); ok(not FO.bigWoodNear(c, 250, 0, 60))
	ok(FO.bigWoodBy(w, { 100, 0 }, { 200, 0 }, 60, false, true, 80), "the tip probe reaches the wood")
	ok(not FO.bigWoodBy(w, { 100, 0 }, { 200, 0 }, 60, false, false, 80))
	-- cached per cover table; a fully wooded grid (one border patch) terminates
	ok(FO.woodSizes(w) == FO.woodSizes(w))
	local all = FO.fromFunction(0, 0, function() return 200 end, 400, 50)
	eq(FO.woodSizes(all)[1], math.huge)
	eq(next(FO.woodSizes(nil)), nil)
end)

test("face rules: a copse ahead no longer faces forest (smallWood), a wood does; off: as §70", function()
	-- a street ending at (220, 0) heading east: the probe 120 m on lies in the copse
	local f, why = LP.facing(220, 0, 1, 0, { fg = copse() })
	eq(f, nil); eq(why, "smallWood")
	eq((LP.facing(220, 0, 1, 0, { fg = wood() })), "forest")
	eq(select(2, LP.facing(-220, 0, -1, 0, { fg = copse() })), nil, "open land: nothing skipped")
	LP.SMALL_WOOD = false
	eq((LP.facing(220, 0, 1, 0, { fg = copse() })), "forest")
	LP.SMALL_WOOD = true
	-- decide: the third value; a rim street toward the copse locked only as rim / out, not as a face
	local ol = LP.roundOutline(0, 0, 200)
	local lock, w, sm = LP.decide({ p0 = { 120, 0 }, p1 = { 220, 0 } }, { outline = ol, mat = 1, ctx = { fg = copse() } })
	ok(w ~= "face:forest", w); ok(sm == true)
	lock, w, sm = LP.decide({ p0 = { 120, 0 }, p1 = { 220, 0 } }, { outline = ol, mat = 1, ctx = { fg = wood() } })
	eq(w, "face:forest"); ok(lock); ok(not sm)
	-- game streets: the rim street toward the copse stays open and is counted; the cache keeps it
	local c = { outline = ol, mat = 1, ctx = { fg = copse() }, faceCache = {}, small = 0 }
	local ed = { id = 5, p0 = { 150, 0 }, p1 = { 220, 0 } }
	eq(LP.gameLock(ed, c), nil)
	eq(c.small, 1)
	eq(LP.gameLock(ed, c), nil)
	eq(c.small, 2, "from the cache too")
	local c2 = { outline = ol, mat = 1, ctx = { fg = wood() }, faceCache = {}, small = 0 }
	eq(LP.gameLock(ed, c2), "face:forest"); eq(c2.small, 0)
end)

test("tips and valves: a copse by the tip no longer rejects it (counted); a wood does", function()
	-- a locked branch east, its dead end at (420, 0); the copse 40 m north-east of the tip; the wood beyond it
	local edges = { { key = "b1", node0 = 5, node1 = -1, p0 = { 300, 0 }, p1 = { 420, 0 } } }
	local cg = box(430, 530, 20, 120)
	local picks, rej, small = GL.pickTips(edges, { b1 = "out" }, { fg = cg }, 0, 0, 300, {}, 2)
	eq(#picks, 1, "picked by the copse"); eq(small, 1)
	local wg = box(430, 800, 20, 400)
	picks, rej = GL.pickTips(edges, { b1 = "out" }, { fg = wg }, 0, 0, 300, {}, 2)
	eq(#picks, 0); eq(rej.forest, 1)
	GL.SMALL_WOOD = false
	picks, rej = GL.pickTips(edges, { b1 = "out" }, { fg = cg }, 0, 0, 300, {}, 2)
	GL.SMALL_WOOD = true
	eq(#picks, 0, "off: the copse rejects it (§70)")
	-- a valve anchor heading into a copse is no longer rejected; into a wood it is
	local vc = { cx = 0, cy = 0, extR = 300, fg = copse(), small = 0 }
	ok(GL.valveScore(230, 0, true, vc) ~= nil); eq(vc.small, 1)
	eq(select(2, GL.valveScore(230, 0, true, { cx = 0, cy = 0, extR = 300, fg = wood() })), "forest")
end)

test("steerKeys: faces skipped as small woods counted on the job (BUILT smallWood=)", function()
	local edges = { { key = "s1", node0 = 5, node1 = -1, p0 = { 120, 0 }, p1 = { 220, 0 } } }
	local job = { inc = { edges = edges }, style = {}, ext = { cx = 0, cy = 0, r = 200 },
		steerC = { outline = LP.roundOutline(0, 0, 200), cx = 0, cy = 0, mat = 1, ctx = { fg = copse() } } }
	D.steerKeys(job)
	eq(job.steerSmall, 1)
	ok(job.steerTally["face:forest"] == nil)
	job.steerC.ctx.fg = wood()
	D.steerKeys(job)
	eq(job.steerSmall, 0); eq(job.steerTally["face:forest"], 1)
end)

-- hooks
test("hook geometry: a curl turns over HOOK_DEG, an S and a straight street don't; an end back by its own street", function()
	local lim = KN.limits({ block = { len = 60, depth = 45 } })
	eq(lim.hookR, 45)
	-- a P curl: out east, round 270 deg on a 40 m radius
	local P = { { 0, 0 }, { 100, 0 } }
	for k = 1, 12 do
		local a = -math.pi / 2 + k * math.rad(22.5)
		P[#P + 1] = { 100 + 40 * math.cos(a), 40 + 40 * math.sin(a) }
	end
	ok(math.abs(KN.winding(P)) > math.rad(200), "winding " .. math.deg(KN.winding(P)))
	eq(KN.hook(P, {}, lim), "turn")
	-- an S: two 60 deg turns back to its heading
	local S = { { 0, 0 }, { 60, 0 }, { 110, 87 }, { 170, 87 }, { 230, 87 } }
	near(KN.winding(S), 0, 1e-9)
	eq(KN.hook(S, {}, lim), nil)
	eq(KN.hook({ { 0, 0 }, { 300, 0 } }, {}, lim), nil)
	-- back toward the street it left (turning only 90 deg): out at 45 deg, along, then down to 30 m off it
	local roots = { { { 0, 0 }, { -300, 0 } }, { { 0, 0 }, { 300, 0 } } }
	eq(KN.hook({ { 0, 0 }, { 60, 60 }, { 160, 60 }, { 190, 30 } }, roots, lim), "back")
	-- ... a block away (60 m) it is fine; so is a short one (under HOOK_ARC_K x hookR of chain)
	eq(KN.hook({ { 0, 0 }, { 60, 90 }, { 160, 90 }, { 190, 60 } }, roots, lim), nil)
	eq(KN.hook({ { 0, 0 }, { 30, 60 }, { 60, 30 } }, roots, lim), nil)
	-- an end running beside the street (not toward it) is the knot rule's parallel case, not a hook
	eq(KN.hook({ { 0, 0 }, { 0, 40 }, { 130, 40 } }, roots, lim), nil)
	-- the joint of two pieces a few cm apart makes no turn
	near(KN.winding({ { 0, 0 }, { 100, 0 }, { 100.01, -0.01 }, { 200, 0 } }), 0, 1e-6)
	-- loop caps: a NaN polyline and an empty one
	eq(KN.hook({ { 0, 0 }, { 0 / 0, 0 } }, {}, lim), nil)
	eq(KN.hook({}, {}, lim), nil)
end)

-- a town street: 1 (0, 0) - 2 (150, 0) - 3 (300, 0), and 2 - 4 (150, -100)
local function street()
	return OG.fromSnapshot({ nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 150, y = 0 }, { id = 3, x = 300, y = 0 },
		{ id = 4, x = 150, y = -100 } },
		edges = { { id = 11, node0 = 1, node1 = 2 }, { id = 12, node0 = 2, node1 = 3 }, { id = 13, node0 = 2, node1 = 4 } } })
end

local function run(g, mp, lim, styleId)
	local style = F.style({ forceStyle = styleId or "EU_ORGANIC" })
	style.centre = { 150, 0 }
	style.block = { len = 100, depth = 60 }
	local st, rep = SEL.select(g, mp, style, { join = "any", joinR = 60, maxEdges = 12, limits = lim,
		terrain = F.flat, leadDepth = false })
	local out = {}
	for _, s in ipairs(st) do out[s.key] = true end
	return out, rep
end

local CURL = { { 300, 0 }, { 400, 0 }, { 450, 50 }, { 410, 110 }, { 350, 80 } }

test("hook rule: a curled dead end waits, a straight one comes; alone it gives way; other towns and climbing motifs free", function()
	local mp = { junctions = { N3 = { 300, 0 }, C = { 350, 80 }, N4 = { 150, -100 }, S = { 150, -250 } },
		pieces = {
			{ key = "curl", a = "N3", b = "C", pts = CURL, class = "small" },
			{ key = "on", a = "N4", b = "S", pts = { { 150, -100 }, { 150, -250 } }, class = "small" } } }
	local st, rep = run(street(), mp, { steer = true })
	ok(st.on, "the straight piece comes")
	ok(not st.curl, "the curl waits")
	ok(rep.hookHeld >= 1 and (rep.hookWhy.turn or 0) >= 1, "held " .. tostring(rep.hookHeld))
	ok(not rep.hookRelax)
	ok(rep.hookPass, "the select ran again without the curl (its budget to other pieces)")
	local plain = run(street(), mp, nil)
	ok(plain.curl, "other towns: as before")
	-- alone: it gives way rather than an empty increment
	local st2, rep2 = run(street(), { junctions = mp.junctions, pieces = { mp.pieces[1] } }, { steer = true })
	ok(st2.curl); ok(rep2.hookRelax)
	-- a climbing motif's street turns back by design
	local mp3 = { junctions = mp.junctions, pieces = { { key = "curl", a = "N3", b = "C", pts = CURL, class = "small",
		motif = "switchbacks" }, mp.pieces[2] } }
	local st3, rep3 = run(street(), mp3, { steer = true })
	ok(st3.curl); eq(rep3.hookHeld, 0)
	-- grid growers exempt (M.HOOK_GRID): their acute V spurs close into blocks later
	local st5, rep5 = run(street(), mp, { steer = true }, "NA_GRID")
	ok(st5.curl, "NA grid: as before"); eq(rep5.hookHeld, 0)
	-- off
	SEL.HOOK = false
	local st4 = run(street(), mp, { steer = true })
	SEL.HOOK = true
	ok(st4.curl, "M.HOOK off")
end)

test("hook rule: the dead-end street behind the piece counts (an existing curve), and pieces chosen before it", function()
	-- the street 1 - 2 - 3 runs on curving north: 3 - 5 (350, 80); a piece from 5 back west turns it past 120 deg
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = 0, y = 0 }, { id = 2, x = 150, y = 0 }, { id = 3, x = 300, y = 0 },
		{ id = 4, x = 150, y = -100 }, { id = 5, x = 350, y = 80 } },
		edges = { { id = 11, node0 = 1, node1 = 2 }, { id = 12, node0 = 2, node1 = 3 }, { id = 13, node0 = 2, node1 = 4 },
			{ id = 14, node0 = 3, node1 = 5 } } })
	local mp = { junctions = { N5 = { 350, 80 }, W = { 250, 110 }, N4 = { 150, -100 }, S = { 150, -250 } },
		pieces = {
			{ key = "back", a = "N5", b = "W", pts = { { 350, 80 }, { 250, 110 } }, class = "small" },
			{ key = "on", a = "N4", b = "S", pts = { { 150, -100 }, { 150, -250 } }, class = "small" } } }
	local st, rep = run(g, mp, { steer = true })
	ok(st.on); ok(not st.back, "the street behind it curls: held")
	eq(rep.hookWhy.turn, 1)
	-- the same piece off a junction (no chain behind it): free
	local mp2 = { junctions = { N2 = { 150, 0 }, W = { 50, 110 }, N4 = mp.junctions.N4, S = mp.junctions.S },
		pieces = { { key = "back", a = "N2", b = "W", pts = { { 150, 0 }, { 50, 110 } }, class = "small" }, mp.pieces[2] } }
	local st2 = run(g, mp2, { steer = true })
	ok(st2.back)
	-- two pieces of one increment: on from 3 east, then curling back: the second waits
	local mp3 = { junctions = { N3 = { 300, 0 }, E = { 420, 0 }, B = { 330, 70 }, N4 = mp.junctions.N4, S = mp.junctions.S },
		pieces = {
			{ key = "e1", a = "N3", b = "E", pts = { { 300, 0 }, { 420, 0 } }, class = "small" },
			{ key = "e2", a = "E", b = "B", pts = { { 420, 0 }, { 460, 60 }, { 330, 70 } }, class = "small" },
			mp.pieces[2] } }
	local st3, rep3 = run(street(), mp3, { steer = true })
	ok(st3.e1, "the first comes"); ok(not st3.e2, "the curl back waits"); ok(rep3.hookHeld >= 1)
end)

test("hook rule: a U that closes a block within the increment is no hook (tested once the increment is chosen)", function()
	-- off the dead end 3: north, west, then down to node 2: a block above the street 2 - 3
	local mp = { junctions = { N3 = { 300, 0 }, A = { 300, 100 }, B = { 150, 100 }, N2 = { 150, 0 } },
		pieces = {
			{ key = "u1", a = "N3", b = "A", pts = { { 300, 0 }, { 300, 100 } }, class = "small" },
			{ key = "u2", a = "A", b = "B", pts = { { 300, 100 }, { 150, 100 } }, class = "small" },
			{ key = "u3", a = "B", b = "N2", pts = { { 150, 100 }, { 150, 0 } }, class = "small" } } }
	local st, rep = run(street(), mp, { steer = true })
	ok(st.u1 and st.u2 and st.u3, "the block closes: " .. tostring(st.u1) .. tostring(st.u2) .. tostring(st.u3))
	eq(rep.hookHeld, 0)
	-- without its closing side the U is a hook: u2 left out (u1 stays)
	local st2, rep2 = run(street(), { junctions = mp.junctions, pieces = { mp.pieces[1], mp.pieces[2] } }, { steer = true })
	ok(st2.u1 and not st2.u2, tostring(st2.u1) .. tostring(st2.u2)); eq(rep2.hookHeld, 1)
end)
