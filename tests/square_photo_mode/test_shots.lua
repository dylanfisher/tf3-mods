-- pm_shots.lua (Photo Mode, pure): scoring and framing of the photographer's shots (rev 1 feedback round 2,
-- item 10). Framings name a look heading; the eye sits at centre - look * d * cos(p), d * sin(p) above the
-- centre's ground.

local shots, cam

before_each(function()
	reset_modules()
	shots = ug_require "square_photo_mode::/photo_mode/pm_shots.lua"
	cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
end)

local PI = math.pi

local function eye(f)
	local h = f.d * math.cos(f.p)
	return f.x - math.cos(f.look) * h, f.y - math.sin(f.look) * h, f.d * math.sin(f.p)
end

local function safe(f)
	ok(f ~= nil, "framed")
	local x = cam.safeView({ x = f.x, y = f.y, d = f.d, a = f.look, p = f.p })
	ok(x ~= nil, "finite")
	ok(f.d >= 1 and f.d <= cam.MAX_DIST, "distance " .. f.d)
	ok(f.p >= 0 and f.p < PI / 2, "pitch " .. f.p)
end

--- The angle between the look heading and a track heading, folded into 0..pi/2 (0 = along, pi/2 = side-on).
local function across(look, heading)
	local d = math.abs(cam.angleDiff(heading, look))
	if d > PI / 2 then d = PI - d end
	return d
end

test("bridge: higher decks score higher and a great one stops the scan", function()
	local low, lowGreat = shots.bridgeScore(5)
	local high, highGreat = shots.bridgeScore(60)
	ok(high > low)
	eq(lowGreat, false); eq(highGreat, true)
	ok(shots.bridgeScore(-3) ~= nil, "a bridge under the terrain read still counts as a bridge")
	eq(shots.bridgeScore(0 / 0), nil)
end)

test("bridge framing: side-on, the eye below the deck, wider for high bridges", function()
	for __, h in ipairs({ 0, 10, 40, 120 }) do
		for __, side in ipairs({ 1, -1 }) do
			local f = shots.frameBridge(100, 200, 0.7, h, side)
			safe(f)
			near(across(f.look, 0.7), PI / 2, 1e-9, "side-on")
			local __, __, eyeH = eye(f)
			if h > 10 then ok(eyeH < h, "eye below the deck at h=" .. h) end
			ok(f.p <= shots.T.bridge.pMax + 1e-9)
		end
	end
	ok(shots.frameBridge(0, 0, 0, 100, 1).d > shots.frameBridge(0, 0, 0, 5, 1).d)
end)

test("water and departure / longest / oldest framings face the track as intended", function()
	local f = shots.frameWater(0, 0, 1.0, 20, 1)
	safe(f)
	near(across(f.look, 1.0), PI / 2, 1e-9)
	local d = shots.frameDeparture(0, 0, 1.0, 8, -1)
	safe(d)
	ok(across(d.look, 1.0) < 0.5, "along the platform")
	ok(shots.frameDeparture(0, 0, 0, 20, 1).d > shots.frameDeparture(0, 0, 0, 2, 1).d, "long trains wider")
	local l = shots.frameLongest(0, 0, 0.2, 12, 1)
	safe(l)
	ok(across(l.look, 0.2) > 1.0, "mostly side-on")
	local o = shots.frameVehicle(0, 0, 0.2, 40, 0.12, 0.4, 1)
	safe(o)
end)

test("tunnel: scored only at a tunnel / open boundary near the portal; framed from outside", function()
	eq(shots.tunnelScore(true, true, 10, true), nil, "both tunnel")
	eq(shots.tunnelScore(false, false, 10, true), nil, "no tunnel")
	eq(shots.tunnelScore(false, true, 1000, true), nil, "too far from the portal")
	ok(shots.tunnelScore(false, true, 20, true) > shots.tunnelScore(true, false, 20, false), "outside first")
	ok(shots.tunnelScore(false, true, 10, true) > shots.tunnelScore(false, true, 200, true), "nearer first")
	-- portal at the origin, the open track towards +x
	local f = shots.frameTunnel(0, 0, 300, 0, 1)
	safe(f)
	local ex = eye(f)
	ok(ex > 0, "the eye stands outside, on the open side")
	ok(math.abs(cam.angleDiff(PI, f.look)) <= shots.T.tunnel.yaw + 1e-9, "looking into the portal")
	eq(shots.frameTunnel(0, 0, 0, 0, 1), nil, "no direction: no framing")
end)

test("approach: low aircraft in landing / take-off first; the camera ahead, looking back", function()
	eq(shots.approachScore(nil, 50), nil)
	eq(shots.approachScore(1, 50), nil, "taxiing")
	eq(shots.approachScore(3, 2), nil, "on the ground")
	eq(shots.approachScore(3, 900), nil, "cruising")
	ok(shots.approachScore(3, 50) > shots.approachScore(2, 50))
	ok(shots.approachScore(3, 50) > shots.approachScore(3, 300))
	local f = shots.frameApproach(0, 0, 70, 0) -- flying towards +x at 70 m/s
	safe(f)
	ok(f.x > 0, "the centre ahead of the aircraft")
	near(math.abs(cam.angleDiff(PI, f.look)), 0, 1e-9, "looking back along its path")
	local ex = eye(f)
	ok(ex > f.x, "the eye further ahead still")
	eq(shots.frameApproach(0, 0, 0, 0), nil, "no speed: no direction")
end)

test("closestPair finds the nearest pair within the distance, grid-binned", function()
	local pts = { { x = 0, y = 0, e = 1 }, { x = 1000, y = 0, e = 2 }, { x = 1100, y = 30, e = 3 }, { x = 5000, y = 0, e = 4 },
		{ x = 1040, y = 10, e = 5 } }
	local a, b, d = shots.closestPair(pts, 150)
	ok((a.e == 2 and b.e == 5) or (a.e == 5 and b.e == 2), "2 and 5")
	near(d, math.sqrt(40 * 40 + 10 * 10))
	eq(shots.closestPair({ { x = 0, y = 0 }, { x = 500, y = 0 } }, 150), nil, "too far apart")
	eq(shots.closestPair({ { x = 0, y = 0 } }, 150), nil)
	-- across a cell border
	local c, e2 = shots.closestPair({ { x = 149, y = 0, e = 1 }, { x = 151, y = 0, e = 2 } }, 150)
	ok(c ~= nil and e2 ~= nil)
	-- the same vehicle twice is refused
	eq(shots.closestPair({ { x = 0, y = 0, e = 1 }, { x = 1, y = 0, e = 1 } }, 150, function(p, q) return p.e ~= q.e end), nil)
	local f = shots.framePassing(pts[2], pts[5], 0, 1)
	safe(f)
	near(f.x, 1020); near(f.y, 5)
	-- many points: no error, a result
	local many = {}
	for i = 1, 400 do many[i] = { x = (i * 37) % 5000, y = (i * 91) % 5000, e = i } end
	ok(shots.closestPair(many, 150) ~= nil)
end)

test("densestCell and mainAxis: the busiest street and its direction", function()
	local pts = {}
	for i = 1, 8 do pts[#pts + 1] = { x = 910 + i * 12, y = 1810 + i * 12 } end -- a diagonal street
	pts[#pts + 1] = { x = 0, y = 0 }
	pts[#pts + 1] = { x = 5000, y = 10 }
	local cell, mx, my, n = shots.densestCell(pts, 150, 4)
	eq(n, 8)
	ok(mx > 900 and my > 1800)
	near(math.abs(shots.mainAxis(cell)), PI / 4, 1e-6, "diagonal")
	eq(shots.densestCell({ { x = 0, y = 0 } }, 150, 4), nil, "not busy enough")
	eq(shots.mainAxis({ { x = 1, y = 1 } }), 0)
	local f = shots.frameRush(mx, my, PI / 4, false)
	safe(f)
	ok(f.p < 0.15, "low")
end)

test("skyline prefers water, then a low ring point; viewpoint the highest rise", function()
	local best = shots.pickSkyline({ { dir = 0, water = false, rise = 0 }, { dir = 1, water = true, rise = 5 },
		{ dir = 2, water = false, rise = 200 } })
	eq(best.dir, 1)
	best = shots.pickSkyline({ { dir = 0, water = false, rise = 150 }, { dir = 2, water = false, rise = 10 } })
	eq(best.dir, 2)
	eq(shots.pickSkyline({}), nil)
	local f = shots.frameSkyline(0, 0, 0.5, 10)
	safe(f)
	near(cam.angleDiff(0.5 + PI, f.look), 0, 1e-9, "looking from the ring point at the town")
	local ex, ey = eye(f)
	near(cam.atan2(ey, ex), 0.5, 1e-6, "the eye out at the ring point's direction")
	local v = shots.pickViewpoint({ { rise = 30 }, { rise = 90, x = 1 }, { rise = 80, water = true, x = 2 } })
	eq(v.x, 2, "water between: a bonus")
	eq(shots.pickViewpoint({ { rise = 10 } }), nil, "not high enough")
	local g = shots.frameViewpoint(0, 0, 1000, 0, 120)
	safe(g)
	local gx, __, gh = eye(g)
	near(gx, 1000, 1e-6, "the eye over the hill")
	near(gh, 120 + shots.T.viewpoint.hAbove, 1e-6, "above the hilltop")
	eq(shots.frameViewpoint(0, 0, 0, 0, 10), nil)
end)

test("departure, oldest scores", function()
	eq(shots.departureScore(5, true, false, 8), nil, "moving")
	eq(shots.departureScore(0, false, false, 8), nil, "not at a platform")
	ok(shots.departureScore(0, true, true, 4) > shots.departureScore(0, true, false, 8), "departing first")
	ok(shots.oldestScore(1850) > shots.oldestScore(1990))
	eq(shots.oldestScore(0), nil, "unknown year")
end)

test("fastest: the camera ahead, the vehicle coming towards it", function()
	local f = shots.frameFastest(0, 0, 0, 60, 1)
	safe(f)
	local ex = eye(f)
	ok(ex > 0, "the eye ahead of the vehicle (it moves towards +x)")
end)
