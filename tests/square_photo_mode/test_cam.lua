-- pm_cam.lua (Photo Mode, pure): framing, shot presets, glide interpolation, orbit, "player moved the camera",
-- random picks, tour order, bookmark list operations.

local cam

before_each(function()
	reset_modules()
	cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
end)

local function view(x, y, d, a, p) return { x = x, y = y, d = d, a = a, p = p } end

test("wrapAngle keeps angles in (-pi, pi]", function()
	near(cam.wrapAngle(0), 0)
	near(cam.wrapAngle(cam.PI), cam.PI)
	near(cam.wrapAngle(-cam.PI), cam.PI)
	near(cam.wrapAngle(3 * cam.PI / 2), -cam.PI / 2)
	near(cam.wrapAngle(-5 * cam.PI / 2), -cam.PI / 2)
	near(cam.angleDiff(3.0, -3.0), 2 * cam.PI - 6.0, 1e-9, "short way across pi")
end)

test("frame uses the kind's distance and pitch and a random angle", function()
	local v = cam.frame("train", 100, 200, 0.25)
	eq(v.x, 100); eq(v.y, 200)
	eq(v.d, 120); eq(v.p, 0.30)
	near(v.a, cam.wrapAngle(cam.TWO_PI * 0.25))
	eq(cam.frame("town", 0, 0, 0).d, 900)
	eq(cam.frame("person", 0, 0, 0).d, 22)
	eq(cam.frame("nonsense", 0, 0, 0).d, cam.FRAMING.vehicle.d, "unknown kind: vehicle framing")
	for kind, f in pairs(cam.FRAMING) do
		ok(f.p >= 0.26 and f.p <= 0.52, kind .. " pitch 15-30 degrees")
	end
end)

test("shot keeps centre and angle", function()
	local cur = view(5, 6, 700, 1.2, 0.8)
	eq(cam.shot(cur, "eye"), view(5, 6, 25, 1.2, 0.04))
	eq(cam.shot(cur, "bird"), view(5, 6, 900, 1.2, 1.30))
	ok(cam.SHOTS.bird.p <= cam.PITCH_MAX and cam.SAFE.pMax <= cam.PITCH_MAX, "never as steep as the 1.45 that inverted the keys")
	eq(cam.shot(cur, "dutch"), nil)
	eq(cam.shot(nil, "eye"), nil)
end)

test("lerpView ends exactly at both views and eases", function()
	local a, b = view(0, 0, 100, 3.0, 0.3), view(1000, 0, 400, -3.0, 0.5)
	local s, e = cam.lerpView(a, b, 0, 0), cam.lerpView(a, b, 1, 0)
	near(s.x, 0); near(s.d, 100); near(s.a, 3.0)
	near(e.x, 1000); near(e.d, 400); near(e.a, -3.0); near(e.p, 0.5)
	local mid = cam.lerpView(a, b, 0.5, 0)
	near(mid.x, 500)
	near(mid.d, 200, 1e-6, "geometric mean half-way")
	ok(math.abs(mid.a) > 3.0, "angle goes the short way through pi")
	near(cam.lerpView(a, b, 0.1, 0).x, 1000 * 0.028, 1e-6, "smoothstep(0.1)")
	near(cam.lerpView(a, b, 2, 0).x, 1000, 1e-9, "t clamped")
end)

test("glide rises mid-way, within the zoom limit", function()
	local a, b = view(0, 0, 900, 0, 0.5), view(6000, 0, 120, 0, 0.3)
	local bump = cam.glideBump(a, b)
	eq(bump, 2000)
	local mid = cam.lerpView(a, b, 0.5, bump)
	ok(mid.d > 2000 and mid.d <= cam.MAX_DIST, "rises: " .. mid.d)
	eq(cam.glideBump(view(0, 0, 100, 0, 0), view(30, 0, 100, 0, 0)), 10, "short hop: small rise")
	eq(cam.glideBump(view(0, 0, 3600, 0, 0), view(9000, 0, 100, 0, 0)), 0, "no room above")
	near(cam.lerpView(a, b, 1, bump).d, 120, 1e-6, "no rise at the end")
end)

test("userMoved detects pan, zoom, turn, tilt and ignores the follow camera's centre", function()
	local last = view(0, 0, 100, 0.5, 0.3)
	eq(cam.userMoved(last, view(1, 1, 101, 0.51, 0.31)), false)
	local m, why = cam.userMoved(last, view(20, 0, 100, 0.5, 0.3))
	eq(m, true); eq(why, "pan")
	eq(cam.userMoved(last, view(20, 0, 100, 0.5, 0.3), true), false, "following: centre moves by itself")
	eq(select(2, cam.userMoved(last, view(0, 0, 150, 0.5, 0.3))), "zoom")
	eq(select(2, cam.userMoved(last, view(0, 0, 100, 0.9, 0.3))), "turn")
	eq(select(2, cam.userMoved(last, view(0, 0, 100, 0.5, 0.6))), "tilt")
	eq(cam.userMoved(nil, last), false)
	eq(cam.userMoved(view(0, 0, 100, cam.PI - 0.01, 0.3), view(0, 0, 100, -cam.PI + 0.01, 0.3)), false, "wrap")
end)

test("orbitStep turns only the angle and caps a hitch", function()
	local cur = view(1, 2, 300, 0, 0.4)
	local v = cam.orbitStep(cur, 1, 0.5)
	eq(v.x, 1); eq(v.d, 300); eq(v.p, 0.4)
	near(v.a, 0.05, 1e-9, "dt capped to 0.1 s")
	near(cam.orbitStep(cur, 0.016).a, cam.ORBIT_RAD_PER_S * 0.016)
end)

test("newRng is deterministic and in [0, 1)", function()
	local r1, r2 = cam.newRng(42), cam.newRng(42)
	for __ = 1, 200 do
		local a = r1()
		eq(a, r2())
		ok(a >= 0 and a < 1)
	end
	ok(cam.newRng(0)() >= 0, "seed 0 works")
end)

test("pickRandom honours accept and the try limit", function()
	local rnd = cam.newRng(7)
	eq(select(1, cam.pickRandom({}, rnd)), nil)
	local it = cam.pickRandom({ 1, 2, 3, 4 }, rnd, function(v) return v == 3 end, 200)
	eq(it, 3)
	local none, tries = cam.pickRandom({ 1, 2 }, rnd, function() return false end, 5)
	eq(none, nil); eq(tries, 5)
	local seen = {}
	for __ = 1, 100 do seen[cam.pickRandom({ "a", "b", "c" }, rnd)] = true end
	eq(seen, { a = true, b = true, c = true }, "every item reachable")
end)

test("maxBy, airborne, tour order and interval", function()
	local best, s = cam.maxBy({ { n = 2 }, { n = 9 }, { n = nil }, { n = 4 } }, function(t) return t.n end)
	eq(best.n, 9); eq(s, 9)
	eq(cam.maxBy({}, function() return 1 end), nil)
	eq(cam.isAirborne(160, 100), true)
	eq(cam.isAirborne(120, 100), false)
	eq(cam.isAirborne(nil, 100), false)
	eq(cam.tourNext(0, 3), 1); eq(cam.tourNext(3, 3), 1); eq(cam.tourNext(nil, 3), 1)
	eq(cam.tourSeconds(1), 5); eq(cam.tourSeconds(3), 20); eq(cam.tourSeconds(9), 10)
end)

test("bookmarks: add with growing ids, cap, remove, find", function()
	local list = {}
	local added
	for i = 1, cam.BOOKMARK_CAP do
		list, added = cam.addBookmark(list, view(i, 0, 100, 0, 0.3))
		eq(added, true)
	end
	eq(#list, cam.BOOKMARK_CAP)
	local same
	same, added = cam.addBookmark(list, view(0, 0, 1, 0, 0))
	eq(added, false); eq(same, list)
	list = cam.removeBookmark(list, 3)
	eq(#list, cam.BOOKMARK_CAP - 1)
	eq(cam.findBookmark(list, 3), nil)
	eq(cam.findBookmark(list, 4).x, 4)
	list = cam.addBookmark(list, view(99, 0, 100, 0, 0.3))
	eq(list[#list].id, cam.BOOKMARK_CAP + 1, "ids never reused")
end)

test("bookmarks: save data round trip and malformed data", function()
	local list = cam.addBookmark({}, view(1.5, -2, 300, 0.1, 0.4))
	local back = cam.readBookmarks(cam.bookmarkData(list))
	eq(back, { { id = 1, x = 1.5, y = -2, d = 300, a = 0.1, p = 0.4 } })
	eq(cam.readBookmarks(nil), {})
	eq(cam.readBookmarks("junk"), {})
	eq(cam.readBookmarks({ views = { { id = 1, x = "a" }, 5, { id = 2, x = 0, y = 0, d = 0 / 0, a = 0, p = 0 } } }), {})
	local many = { views = {} }
	for i = 1, cam.BOOKMARK_CAP + 10 do many.views[i] = { id = i, x = 0, y = 0, d = 1, a = 0, p = 0 } end
	eq(#cam.readBookmarks(many), cam.BOOKMARK_CAP)
end)

test("lerpView and orbitStep write into a scratch table when given one", function()
	local a, b = view(0, 0, 100, 0, 0.2), view(1000, 0, 400, 1, 0.6)
	local buf = {}
	local v = cam.lerpView(a, b, 0.3, 50, buf)
	eq(v, buf, "same table back")
	local fresh = cam.lerpView(a, b, 0.3, 50)
	for __, k in ipairs({ "x", "y", "d", "a", "p" }) do near(buf[k], fresh[k], 1e-12, k) end
	local cur = view(5, 6, 300, 0.1, 0.4)
	local o = cam.orbitStep(cur, 0.016, nil, buf)
	eq(o, buf)
	near(o.a, cam.orbitStep(cur, 0.016).a, 1e-12)
	eq(o.x, 5); eq(o.d, 300)
	local same = cam.orbitStep(cur, 0.016, nil, cur)
	eq(same, cur, "in place")
	near(cur.a, 0.1 + cam.ORBIT_RAD_PER_S * 0.016, 1e-12)
end)

test("budgetedWalk continues where the last call stopped and wraps", function()
	local seen = {}
	local function visit(i) seen[#seen + 1] = i return false end
	local budget = 0
	local function over() budget = budget - 1 return budget <= 0 end
	-- 3 items per call (over() is asked after each visit) on a list of 7, starting at 0-based 5
	budget = 3
	local nextStart, read = cam.budgetedWalk(7, 5, visit, over)
	eq(read, 3); eq(nextStart, 1)
	eq(table.concat(seen, ","), "6,7,1")
	seen = {}
	budget = 3
	nextStart, read = cam.budgetedWalk(7, nextStart, visit, over)
	eq(table.concat(seen, ","), "2,3,4"); eq(nextStart, 4)
	-- found: stops at once, the next call starts after the hit
	seen = {}
	nextStart, read = cam.budgetedWalk(7, 4, function(i) seen[#seen + 1] = i return i == 6 end, nil)
	eq(table.concat(seen, ","), "5,6"); eq(read, 2); eq(nextStart, 6)
	-- a full round without a stop returns the same start; at least one item even with the budget spent
	seen = {}
	nextStart, read = cam.budgetedWalk(4, 2, visit, function() return false end)
	eq(read, 4); eq(nextStart, 2); eq(table.concat(seen, ","), "3,4,1,2")
	nextStart, read = cam.budgetedWalk(4, 0, function() return false end, function() return true end)
	eq(read, 1); eq(nextStart, 1)
	-- a start past a shrunken list, and an empty list
	seen = {}
	cam.budgetedWalk(3, 10, visit, function() return true end)
	eq(seen[1], 2, "10 % 3 = 1 -> item 2")
	eq(select(2, cam.budgetedWalk(0, 3, visit, nil)), 0)
end)

-- Crash safety: what setCameraData is ever given (plans/square_photo_mode/PLAN.md "Crash safety")

test("safeView rejects non-finite views and clamps the rest", function()
	local nan, inf = 0 / 0, math.huge
	eq(cam.safeView(nil), nil)
	eq(cam.safeView(view(nan, 0, 100, 0, 0.5)), nil)
	eq(cam.safeView(view(0, inf, 100, 0, 0.5)), nil)
	eq(cam.safeView(view(0, 0, -inf, 0, 0.5)), nil)
	eq(cam.safeView(view(0, 0, 100, nan, 0.5)), nil)
	eq(cam.safeView(view(0, 0, 100, 0, nil)), nil)
	local x, y, d, a, p = cam.safeView(view(10, 20, 0, 7, 3))
	eq(x, 10); eq(y, 20)
	eq(d, cam.SAFE.dMin, "distance 0 raised")
	near(a, cam.wrapAngle(7))
	eq(p, cam.SAFE.pMax, "pitch past straight down")
	x, y, d, a, p = cam.safeView(view(1e9, -1e9, 1e9, 0, -1))
	eq(x, cam.SAFE.xyMax); eq(y, -cam.SAFE.xyMax); eq(d, cam.SAFE.dMax); eq(p, cam.SAFE.pMin)
	x, y = cam.safeView(view(-500, 9000, 100, 0, 0.5), { -100, -200, 4000, 5000 })
	eq(x, -100); eq(y, 5000)
end)

test("safeView turns -0 into +0", function()
	local x, y, d, a, p = cam.safeView(view(-0.0, -0.0, 100, -0.0, 0.5))
	eq(1 / x, math.huge); eq(1 / y, math.huge); eq(1 / a, math.huge)
end)

test("NaN, infinite and zero inputs never reach a view as NaN", function()
	local nan = 0 / 0
	eq(cam.wrapAngle(nan), 0)
	eq(cam.wrapAngle(math.huge), 0)
	eq(cam.clamp(nan, 0, 1), 0)
	eq(cam.ease(nan), 0)
	local o = cam.orbitStep(view(0, 0, 100, 1, 0.5), nan)
	eq(o.a, 1, "NaN dt: no turn")
	o = cam.orbitStep(view(0, 0, 100, 1, 0.5), 0)
	eq(o.a, 1, "dt 0: no turn")
	-- a glide between views at distance 0 or with dt 0 stays finite
	local g = cam.lerpView(view(0, 0, 0, 0, 0.3), view(100, 0, 0, 1, 0.3), 0.5, 0)
	ok(cam.safeView(g) ~= nil, "finite: " .. cam.viewText(g))
	g = cam.lerpView(view(0, 0, 100, 0, 0.3), view(0, 0, 100, 0, 0.3), 0, cam.glideBump(view(0, 0, 100, 0, 0), view(0, 0, 100, 0, 0)))
	ok(cam.safeView(g) ~= nil)
	-- a NaN from the camera read is caught by safeView, not sent
	g = cam.lerpView(view(nan, 0, 100, 0, 0.3), view(100, 0, 100, 1, 0.3), 0.5, 0)
	eq(cam.safeView(g), nil)
end)

test("boundsOf reads a terrain box and rejects broken ones", function()
	eq(cam.boundsOf({ min = { x = -4000, y = -3000 }, max = { x = 4000, y = 3000 } }), { -4000, -3000, 4000, 3000 })
	eq(cam.boundsOf(nil), nil)
	eq(cam.boundsOf({ min = { x = 0, y = 0 }, max = { x = 0, y = 10 } }), nil, "empty")
	eq(cam.boundsOf({ min = { x = 0 / 0, y = 0 }, max = { x = 1, y = 1 } }), nil)
end)

test("readBookmarks drops non-finite and odd entries from any data shape", function()
	local nan = 0 / 0
	eq(cam.readBookmarks(nil), {})
	eq(cam.readBookmarks("x"), {})
	eq(cam.readBookmarks({ views = "x" }), {})
	eq(cam.readBookmarks({ views = { 5, "a", { id = 1, x = nan, y = 0, d = 1, a = 0, p = 0 },
		{ id = 2, x = 1, y = 2, d = math.huge, a = 0, p = 0 }, { id = 3, x = 1, y = 2, d = 3, a = 0, p = 0.5 } } }),
		{ { id = 3, x = 1, y = 2, d = 3, a = 0, p = 0.5 } })
	local raising = setmetatable({}, { __index = function() error("bad") end })
	eq(cam.readBookmarks(raising), {})
end)

-- Rev 1 feedback (2026-10-13): saved views table, tour framing, Ken Burns drift, "Anything"

local function seq(...)
	local vals, i = { ... }, 0
	return function() i = i % #vals + 1 return vals[i] end
end

test("cleanName: trims, folds control characters, cuts at NAME_MAX characters (UTF-8), empty = nil", function()
	eq(cam.cleanName("  Harbour   at dusk \n"), "Harbour at dusk")
	eq(cam.cleanName("a\tb\r\nc"), "a b c")
	eq(cam.cleanName("   "), nil)
	eq(cam.cleanName(""), nil)
	eq(cam.cleanName(nil), nil)
	eq(cam.cleanName(42), nil)
	eq(#cam.cleanName(string.rep("x", 100)), cam.NAME_MAX)
	-- 2-byte characters: 40 of them, 80 bytes, never cut inside one
	local long = string.rep("\195\164", 60) -- "ae" umlaut x 60
	local cut = cam.cleanName(long)
	eq(#cut, cam.NAME_MAX * 2)
	eq(cam.cleanName(string.rep("x", cam.NAME_MAX - 1) .. " \195\164\195\164"), string.rep("x", cam.NAME_MAX - 1),
		"a trailing space left by the cut is trimmed")
	-- CJK: 3-byte characters
	eq(#cam.cleanName(string.rep("\230\151\165", 50)), cam.NAME_MAX * 3)
end)

test("bookmarks: rename, default name, move up / down = the tour order", function()
	local list = {}
	for i = 1, 4 do list = cam.addBookmark(list, view(i, 0, 100, 0, 0.3)) end
	eq(list[1].name, nil, "default name until renamed")
	local renamed, changed = cam.renameBookmark(list, 2, "  Bridge  ")
	eq(changed, true); eq(renamed[2].name, "Bridge"); eq(list[2].name, nil, "the old list is untouched")
	local same
	same, changed = cam.renameBookmark(renamed, 2, "Bridge")
	eq(changed, false); eq(same, renamed)
	local back = cam.renameBookmark(renamed, 2, "")
	eq(back[2].name, nil, "an empty name goes back to the default")
	eq(select(2, cam.renameBookmark(list, 99, "x")), false, "unknown id")
	local moved
	moved, changed = cam.moveBookmark(renamed, 3, -1)
	eq(changed, true)
	local ids = {}
	for i, b in ipairs(moved) do ids[i] = b.id end
	eq(ids, { 1, 3, 2, 4 })
	eq(select(2, cam.moveBookmark(moved, 1, -1)), false, "first can't move up")
	eq(select(2, cam.moveBookmark(moved, 4, 1)), false, "last can't move down")
	moved = cam.moveBookmark(moved, 1, 1)
	ids = {}
	for i, b in ipairs(moved) do ids[i] = b.id end
	eq(ids, { 3, 1, 2, 4 })
	-- the order and names survive the save data round trip
	local read = cam.readBookmarks(cam.bookmarkData(moved))
	ids = {}
	for i, b in ipairs(read) do ids[i] = b.id end
	eq(ids, { 3, 1, 2, 4 })
	eq(read[3].name, "Bridge")
end)

test("readBookmarks: names validated, repeated ids dropped, cap 50", function()
	eq(cam.BOOKMARK_CAP, 50)
	local data = { views = {
		{ id = 1, name = "  A\nB ", x = 0, y = 0, d = 1, a = 0, p = 0 },
		{ id = 1, name = "dup", x = 5, y = 0, d = 1, a = 0, p = 0 },
		{ id = 2, name = { "table" }, x = 0, y = 0, d = 1, a = 0, p = 0 },
		{ id = 3, name = string.rep("y", 500), x = 0, y = 0, d = 1, a = 0, p = 0 },
	} }
	local out = cam.readBookmarks(data)
	eq(#out, 3)
	eq(out[1].name, "A B"); eq(out[1].x, 0)
	eq(out[2].id, 2); eq(out[2].name, nil)
	eq(#out[3].name, cam.NAME_MAX)
end)

test("tourFrame: always between eye level and a bit wider than low angle", function()
	local f = cam.TOUR_FRAME
	ok(f.dMin >= cam.SHOTS.eye.d - 1e-9 and f.pMin >= cam.SHOTS.eye.p - 1e-9, "not closer than eye level")
	ok(f.dMax < cam.SHOTS.drone.d and f.pMax < cam.SHOTS.drone.p, "never drone height")
	ok(f.dMax > cam.SHOTS.low.d and f.pMax > cam.SHOTS.low.p, "a bit wider than low angle")
	local rnd = cam.newRng(7)
	for kind in pairs(cam.FRAMING) do
		for __ = 1, 50 do
			local v = cam.tourFrame(kind, 10, 20, rnd)
			eq(v.x, 10); eq(v.y, 20)
			ok(v.d >= f.dMin - 1e-9 and v.d <= f.dMax + 1e-9, kind .. " d " .. v.d)
			ok(v.p >= f.pMin - 1e-9 and v.p <= f.pMax + 1e-9, kind .. " p " .. v.p)
		end
	end
	-- extremes of the random draws stay inside too; a person sits closer than a town
	ok(cam.tourFrame("person", 0, 0, seq(0.5)).d < cam.tourFrame("town", 0, 0, seq(0.5)).d)
	local lo, hi = cam.tourFrame("person", 0, 0, seq(0)), cam.tourFrame("town", 0, 0, seq(0.999))
	near(lo.d, f.dMin); near(lo.p, f.pMin)
	ok(hi.d <= f.dMax + 1e-9)
	ok(cam.tourFrame("nonsense", 0, 0, seq(0.5)).d > 0, "unknown kind framed like a vehicle")
end)

test("weightedOrder: every positive key once, heavier keys first more often", function()
	local rnd = cam.newRng(11)
	local firsts = {}
	for __ = 1, 2000 do
		local order = cam.weightedOrder({ { "a", 3 }, { "b", 1 }, { "c", 0 }, { "d", -1 }, { "e", 0 / 0 } }, rnd)
		eq(#order, 2)
		ok((order[1] == "a" and order[2] == "b") or (order[1] == "b" and order[2] == "a"))
		firsts[order[1]] = (firsts[order[1]] or 0) + 1
	end
	ok(firsts.a > 1300 and firsts.a < 1700, "a first ~75 %: " .. tostring(firsts.a))
	eq(cam.weightedOrder(nil, rnd), {})
	local all = cam.weightedOrder(cam.ANY_KINDS, rnd)
	eq(#all, #cam.ANY_KINDS)
end)

-- Rev 1 feedback round 2 (2026-10-13): tour range, presets, look offset, terrain clearance, random places

test("tourRange: defaults = the rev 1 framing; from above to swaps; bad indices fall back; inside SAFE", function()
	local r = cam.tourRange(nil)
	eq(r, { dMin = 25, dMax = 90, pMin = 0.04, pMax = 0.20 })
	eq(cam.tourRange(cam.RANGE_DEFAULT), r)
	local wide = cam.tourRange({ pf = 3, pt = 3, df = 3, dt = 3 })
	eq(wide.pMin, 0.45); eq(wide.pMax, 1.30); eq(wide.dMin, 150); eq(wide.dMax, 900)
	-- Drone from, Low angle (0.20) to: swapped so min <= max
	local sw = cam.tourRange({ pf = 3, pt = 1, df = 3, dt = 1 })
	ok(sw.pMin <= sw.pMax and sw.dMin <= sw.dMax, "swapped")
	eq(sw.pMin, 0.20); eq(sw.pMax, 0.45); eq(sw.dMin, 90); eq(sw.dMax, 150)
	local bad = cam.tourRange({ pf = 0, pt = 9, df = 0 / 0, dt = "x" })
	eq(bad, r, "invalid choices: the defaults")
	for pf = 1, 3 do for pt = 1, 3 do for df = 1, 3 do for dt = 1, 3 do
		local q = cam.tourRange({ pf = pf, pt = pt, df = df, dt = dt })
		ok(q.pMin >= cam.SAFE.pMin and q.pMax <= cam.SAFE.pMax and q.dMin >= cam.SAFE.dMin and q.dMax <= cam.MAX_DIST)
		-- every view framed in it passes safeView unchanged in d / p
		local v = cam.tourFrame("train", 0, 0, cam.newRng(pf * 27 + pt * 9 + df * 3 + dt), q)
		local __, __, d, __, p = cam.safeView(v)
		near(d, v.d); near(p, v.p)
		ok(v.d >= q.dMin - 1e-9 and v.d <= q.dMax + 1e-9 and v.p >= q.pMin - 1e-9 and v.p <= q.pMax + 1e-9)
	end end end end
end)

test("presets set the range; modes decide hop or flight", function()
	eq(cam.tourRange(cam.preset("ground")), cam.tourRange(nil), "Ground level = the rev 1 tour")
	local mixed = cam.tourRange(cam.preset("mixed"))
	ok(mixed.dMax > 90 and mixed.pMax > 0.2, "Mixed reaches drone height")
	eq(cam.preset("nonsense"), cam.preset("ground"))
	local p = cam.preset("aerial")
	p.pf = 3
	eq(cam.preset("aerial").pf, 2, "a copy")
	for n = 1, 10 do eq(cam.hopKind("ground", n), "hop") eq(cam.hopKind("aerial", n), "flight") end
	local kinds = {}
	for n = 1, 7 do kinds[n] = cam.hopKind("mixed", n) end
	eq(kinds, { "hop", "hop", "hop", "flight", "hop", "hop", "flight" })
end)

test("look offset: measured from eye and centre, angleFor inverts lookOf", function()
	-- a camera whose look heading is its angle + pi/2
	local a = 0.3
	local look = a + math.pi / 2
	local ex, ey = 0, 0
	local cx, cy = math.cos(look) * 100, math.sin(look) * 100
	near(cam.measureLookOffset(a, ex, ey, cx, cy), math.pi / 2)
	eq(cam.measureLookOffset(a, 5, 5, 5.2, 5.2), nil, "straight down: unusable")
	eq(cam.measureLookOffset(0 / 0, 0, 0, 10, 0), nil)
	for __, off in ipairs({ 0, math.pi / 2, math.pi, -1.0 }) do
		near(cam.lookOf(cam.angleFor(1.2, off), off), 1.2)
	end
	-- the eye stands behind the centre along the look heading
	local v = { x = 100, y = 0, d = 50, a = 0, p = 0 }
	local x, y = cam.eyeXY(v, 0)
	near(x, 50); near(y, 0)
	x, y = cam.eyeXY(v, math.pi / 2)
	near(x, 100); near(y, -50)
end)

test("clearPitch raises a low view over a hill, never lowers it", function()
	near(cam.clearPitch(100, 0.05, 0, 0, 10), math.asin(0.1), 1e-9, "flat: up to the margin")
	eq(cam.clearPitch(100, 0.5, 0, 0, 10), 0.5, "high enough already")
	local p = cam.clearPitch(100, 0.05, 0, 40, 10)
	near(100 * math.sin(p), 50, 1e-6, "eye 10 m over a 40 m hill")
	ok(cam.clearPitch(100, 0.05, 0, 500, 10) <= 1.2, "capped")
	eq(cam.clearPitch(0 / 0, 0.3, 0, 0), 0.3)
end)

test("randomPoint stays inside the bounds, inset from the edges", function()
	local rnd = cam.newRng(11)
	local b = { -1000, -500, 3000, 1500 }
	for __ = 1, 500 do
		local x, y = cam.randomPoint(b, rnd, 0.08)
		ok(x >= -1000 + 4000 * 0.08 - 1e-6 and x <= 3000 - 4000 * 0.08 + 1e-6, "x " .. x)
		ok(y >= -500 + 2000 * 0.08 - 1e-6 and y <= 1500 - 2000 * 0.08 + 1e-6, "y " .. y)
	end
	eq(cam.randomPoint(nil, rnd), nil)
end)

test("the tour and Anything include random places and the photographer's shots", function()
	local has = {}
	for __, kinds in pairs(cam.SOURCE_KINDS) do for __, k in ipairs(kinds) do has[k] = true end end
	for __, k in ipairs({ "place", "bridge", "viewpoint", "departure", "skyline", "rush", "tunnel", "water", "passing", "approach" }) do
		ok(has[k], "tour has " .. k)
	end
	local any = {}
	for __, kw in ipairs(cam.ANY_KINDS) do any[kw[1]] = kw[2] end
	ok(any.place and any.place > 0, "Anything has random places")
	ok(any.bridge and any.viewpoint, "Anything has the strong shots")
	ok(any.saved and any.saved > 0, "round 8: Anything has the saved views")
	local inShots = false
	for __, k in ipairs(cam.SOURCE_KINDS.shots) do if k == "saved" then inShots = true end end
	ok(inShots, "round 8: the tour's interesting shots include the saved views")
end)

-- Round 3 (2026-10-13): tour sources and the flights' options

test("tour sources: ticked in order, in turn, skipping empty ones; the last one stays ticked", function()
	local src = cam.copySet(cam.DEFAULT_SOURCES)
	eq(cam.ticked(src, cam.TOUR_SOURCES), { "random", "places", "shots" })
	eq(cam.tourNextSource(src, nil), "random")
	eq(cam.tourNextSource(src, "random"), "places")
	eq(cam.tourNextSource(src, "shots"), "random", "wraps")
	eq(cam.tourNextSource(src, "places", { shots = true }), "random", "a source with nothing skipped")
	eq(cam.tourNextSource(src, "random", { random = true, places = true, shots = true }), nil)
	ok(cam.toggleSet(src, cam.TOUR_SOURCES, "views", true))
	ok(cam.toggleSet(src, cam.TOUR_SOURCES, "random", false))
	ok(cam.toggleSet(src, cam.TOUR_SOURCES, "places", false))
	ok(cam.toggleSet(src, cam.TOUR_SOURCES, "shots", false))
	eq(cam.viewsOnly(src), true)
	eq(cam.toggleSet(src, cam.TOUR_SOURCES, "views", false), false, "refused")
	eq(src.views, true)
	eq(cam.toggleSet(src, cam.TOUR_SOURCES, "nonsense", true), false)
	eq(cam.viewsOnly(cam.DEFAULT_SOURCES), false)
end)

test("flight legs and subjects", function()
	eq(cam.legSeconds(1), 30); eq(cam.legSeconds(4), 300); eq(cam.legSeconds(99), 60)
	local fs = cam.copySet(cam.DEFAULT_FLIGHT_SUBJECTS)
	eq(#cam.ticked(fs, cam.FLIGHT_SUBJECTS), 6)
	for __, k in ipairs({ "towns", "landscape", "water", "rivers", "rail" }) do ok(cam.toggleSet(fs, cam.FLIGHT_SUBJECTS, k, false)) end
	eq(cam.toggleSet(fs, cam.FLIGHT_SUBJECTS, "poi", false), false)
end)

test("waterKind: land, wide water, a narrow river (either axis)", function()
	local calls = 0
	local function w(f) return function(x, y) calls = calls + 1 return f(x, y) end end
	eq(cam.waterKind(w(function() return false end), 0, 0, 150), nil)
	eq(calls, 1, "one call on land")
	eq(cam.waterKind(w(function() return true end), 0, 0, 150), "water")
	eq(cam.waterKind(w(function(x) return math.abs(x) < 100 end), 0, 0, 150), "river", "north-south river")
	eq(cam.waterKind(w(function(x, y) return math.abs(y) < 100 end), 0, 0, 150), "river", "east-west river")
	eq(cam.waterKind(w(function(x) return x < 100 end), 0, 0, 150), "water", "a coast is not a river")
end)

-- Horizon shots and range (user feedback 2026-10-13: "higher up but looking across the horizon")

test("horizonFrame: d = h / sin p within the zoom limit; past it clamped, pitch raised, height kept", function()
	local d, p, clamped = cam.horizonFrame(250, 0.075)
	near(d * math.sin(p), 250, 1e-6); eq(clamped, false); ok(d <= cam.ZOOM_LIMIT)
	d, p, clamped = cam.horizonFrame(800, 0.10)
	eq(clamped, true); eq(d, cam.ZOOM_LIMIT)
	near(d * math.sin(p), 800, 1e-6, "height kept"); ok(p > 0.10 and p < 0.25, "a bit steeper: " .. p)
	d, p = cam.horizonFrame(0 / 0, 0 / 0)
	ok(d == d and p == p, "finite on NaN")
end)

test("horizonShot: the eye stays above the current centre, the centre pushed ahead along the heading", function()
	local cur = { x = 100, y = 200, d = 500, a = 0.3, p = 0.6 }
	for __, key in ipairs(cam.HORIZON_ORDER) do
		local v, clamped, want = cam.horizonShot(cur, key, 0.5, 0)
		local ex, ey = cam.eyeXY(v, 0.5)
		near(ex, 100, 1e-6); near(ey, 200, 1e-6)
		near(v.d * math.sin(v.p), cam.HORIZON_SHOTS[key].h, 1e-6)
		eq(v.a, cur.a, "direction kept")
		ok(v.p < 0.25, key .. " nearly level: " .. v.p)
		ok(want >= v.d, "wanted distance logged")
		ok(cam.safeView(v) ~= nil)
		if key == "highhorizon" then eq(clamped, true) end
	end
	-- higher ground under the eye: the eye rises with it
	local v = cam.horizonShot(cur, "horizon", 0, 100)
	near(v.d * math.sin(v.p), 350, 1e-6)
	eq(cam.horizonShot(nil, "horizon"), nil); eq(cam.horizonShot(cur, "nope"), nil)
end)

test("tour range: Horizon + far distances fly high and look level", function()
	local r = cam.tourRange({ pf = 1, pt = 4, df = 4, dt = 4 })
	eq(r.pMax, 0.09); eq(r.dMin, 1000); eq(r.dMax, 3500)
	for i = 1, 30 do
		local v = cam.tourFrame("town", 0, 0, cam.newRng(i), r)
		ok(v.p <= 0.09 + 1e-9 and v.d >= 1000 - 1e-9, "level and far")
		ok(v.d * math.sin(v.p) >= 35, "high: " .. v.d * math.sin(v.p))
	end
	for pf = 1, 3 do for pt = 1, 4 do for df = 1, 4 do for dt = 1, 4 do
		local q = cam.tourRange({ pf = pf, pt = pt, df = df, dt = dt })
		ok(q.pMin <= q.pMax and q.dMin <= q.dMax and q.dMax <= cam.MAX_DIST)
	end end end end
end)

test("flightInput: turn / tilt / zoom are look input, a pan stops; a zooming frame ignores the centre", function()
	local last = { x = 0, y = 0, d = 500, a = 0, p = 0.3 }
	local pan, da, dp, dz = cam.flightInput(last, { x = 0, y = 0, d = 500, a = 0.05, p = 0.32 })
	eq(pan, false); near(da, 0.05, 1e-9); near(dp, 0.02, 1e-9); eq(dz, 0)
	pan = cam.flightInput(last, { x = 40, y = 0, d = 500, a = 0, p = 0.3 })
	eq(pan, true, "pan")
	pan, da, dp, dz = cam.flightInput(last, { x = 40, y = 0, d = 600, a = 0, p = 0.3 })
	eq(pan, false, "zoom towards the cursor moves the centre: not a pan"); near(dz, math.log(1.2), 1e-9)
	pan, da, dp, dz = cam.flightInput(last, { x = 0.1, y = 0, d = 500.1, a = 0.0001, p = 0.3 })
	eq(pan, false); eq(da, 0); eq(dp, 0); eq(dz, 0)
	pan, da = cam.flightInput(last, { x = 0 / 0, y = 0, d = 500, a = 0, p = 0.3 })
	eq(pan, false); eq(da, 0)
	eq(cam.flightInput(nil, last), false)
end)
