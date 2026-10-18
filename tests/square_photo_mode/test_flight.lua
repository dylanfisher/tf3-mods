-- pm_flight.lua (Photo Mode, pure): speed ramps, velocity-continuous hops with the Ken Burns drift, the hold
-- timer, the Aerials flight path (waypoints inside the map, smooth headings, terrain clearance).

local F, cam

before_each(function()
	reset_modules()
	cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
end)

local function view(x, y, d, a, p) return { x = x, y = y, d = d, a = a, p = p } end

local function vel(fn, t, h)
	h = h or 1e-4
	return (fn(t + h) - fn(t - h)) / (2 * h)
end

test("ramps: speed continuous from 0 to 1 (in) and 1 to 0 (out), ramp / 2 covered", function()
	local R = 2
	eq(F.rampIn(0, R), 0); eq(F.rampIn(-1, R), 0)
	near(F.rampIn(R, R), R / 2)
	near(F.rampIn(R + 3, R), R / 2 + 3)
	near(vel(function(t) return F.rampIn(t, R) end, 1e-3), 0, 1e-2, "starts at rest")
	near(vel(function(t) return F.rampIn(t, R) end, R), 1, 1e-3, "full speed at the end of the ramp")
	near(F.rampOut(R, R), R / 2)
	near(F.rampOut(10, R), R / 2, 1e-12, "stopped after the ramp")
	near(vel(function(t) return F.rampOut(t, R) end, 1e-3), 1, 1e-2, "starts at full speed")
	near(vel(function(t) return F.rampOut(t, R) end, R), 0, 1e-3, "ends at rest")
	-- monotonic
	local prev = -1
	for i = 0, 40 do
		local v = F.rampIn(i * 0.1, R)
		ok(v >= prev) prev = v
	end
end)

--- The view of a hop at tau as plain numbers (a copy).
local function at(hop, tau, lo, hi)
	local v = F.hopView(hop, tau, {}, lo, hi)
	return v
end

local function comp(hop, key, lo, hi)
	return function(t)
		local v = at(hop, t, lo, hi)
		if key == "a" then return v.a end
		return v[key]
	end
end

test("hop: the glide flows into the drift and out of it without a velocity jump", function()
	local rnd = cam.newRng(4)
	local A = { base = view(0, 0, 60, 0.3, 0.1), rates = F.kbRates(rnd, 1, 0), s0 = 12 }
	local B = { base = view(800, 300, 80, 1.2, 0.15), rates = F.kbRates(rnd, 1, 0) }
	local G, H = 4.5, 10
	local hop = F.newHop(A, B, G, H, 0)
	-- start: position and velocity of the leaving drift
	local startV = F.kbView(A.base, A.rates, A.s0, {})
	local v0 = at(hop, 0)
	near(v0.x, startV.x, 1e-9); near(v0.d, startV.d, 1e-9)
	for __, key in ipairs({ "x", "y", "d", "p" }) do
		-- just after the start (the smoothstep's slope grows linearly: 800 m x 6t/G^2 would show at 1 ms)
		local glide = vel(comp(hop, key), 1e-6, 1e-7)
		local drift = vel(function(s) return F.kbView(A.base, A.rates, s, {})[key] end, A.s0)
		near(glide, drift, 1e-2 * math.max(1, math.abs(drift)), "start velocity " .. key)
	end
	-- arrival: the glide ends on the moving target with the target's own velocity
	for __, key in ipairs({ "x", "y", "d", "p" }) do
		local before = vel(comp(hop, key), G - 1e-6, 1e-7)
		local after = vel(comp(hop, key), G + 1e-6, 1e-7)
		near(before, after, 1e-2 * math.max(1, math.abs(after)), "arrival velocity " .. key)
	end
	-- during the hold the drift keeps moving at a steady pace
	local h1, h2 = at(hop, G + 2), at(hop, G + 6)
	ok(math.abs(h2.x - h1.x) + math.abs(h2.d - h1.d) > 0, "drifting in the hold")
	-- the next hop starts from the drift where this one ends
	local leave = F.leaving(hop, G + H)
	eq(leave.base, B.base)
	near(leave.s0, F.driftIn(G + H, G))
	local nxt = F.newHop(leave, view(0, 0, 50, 0, 0.1), G, H, 0)
	local endV = at(hop, G + H)
	local startN = at(nxt, 0)
	near(startN.x, endV.x, 1e-9); near(startN.d, endV.d, 1e-9); near(startN.a, endV.a, 1e-9)
end)

test("round 11: a hop between two moving ends (flights) leaves and lands with their velocity, no acceleration step", function()
	-- two drones flying along +x at 30 m/s, 3 km apart; the hop blends with the smootherstep in eye space
	local function drone(x0)
		local e = view(x0, 0, 400, 0, 0.4)
		e.g = 10
		e.viewAt = function(tau, out)
			out.x, out.y, out.d, out.a, out.p, out.g = x0 + 30 * tau, 0, 400, 0, 0.4, 10
			return out
		end
		return e
	end
	local hop = F.newHop(drone(0), drone(3000), 4.5, 0, 0, true)
	eq(hop.elev, true, "an eye-space hop")
	local function x(t) return F.hopView(hop, t, {}).x end
	near(vel(x, 1e-3), 30, 0.05, "leaves at the first drone's speed")
	near(vel(x, 4.5 - 1e-3), 30, 0.05, "lands at the second drone's speed")
	local function acc(t, h) return (x(t + h) - 2 * x(t) + x(t - h)) / (h * h) end
	ok(math.abs(acc(0.002, 1e-3)) < 20, "about no acceleration at the start (a smoothstep: ~890): " .. acc(0.002, 1e-3))
	ok(math.abs(acc(4.498, 1e-3)) < 20, "nor at the end: " .. acc(4.498, 1e-3))
	-- a static end of an eye-space hop is converted exactly: the same eye as in the game's pitch
	local st = view(100, 50, 300, 0.3, 0.5)
	st.g = 20
	local h2 = F.newHop(st, drone(3000), 4.5, 0, 0, true)
	local v0 = F.hopView(h2, 0, {}, nil, nil, 0.01)
	local ex, ey, ez = F.poseOf(st, 0, true, 0.01)
	local fx, fy, fz = F.poseOf(v0, 0, false, 0.01)
	near(fx, ex, 1e-6) near(fy, ey, 1e-6) near(fz, ez, 1e-6)
end)

test("hop without the drift: an eased glide from rest to rest, then a still hold", function()
	local hop = F.newHop(view(0, 0, 60, 0, 0.1), view(1000, 0, 60, 0, 0.1), 4, 5, 0)
	near(vel(comp(hop, "x"), 1e-6, 1e-7), 0, 1e-2, "starts at rest")
	near(vel(comp(hop, "x"), 4 - 1e-6, 1e-7), 0, 1e-2, "arrives at rest")
	near(at(hop, 4).x, 1000)
	near(at(hop, 8).x, 1000, 1e-12, "a still hold")
	eq(F.leaving(hop, 9).x, 1000, "a static view to leave from")
end)

test("the drift ramps in only in the glide's last RAMP_S seconds", function()
	eq(F.driftIn(0, 4.5), 0)
	eq(F.driftIn(4.5 - F.RAMP_S - 0.1, 4.5), 0)
	ok(F.driftIn(4.5, 4.5) > 0)
	near(F.driftIn(4.5 + 3, 4.5), F.RAMP_S / 2 + 3)
	-- a glide shorter than the ramp: the ramp takes the whole glide
	ok(F.driftIn(1, 1) > 0)
end)

test("drift pitch stays within the tour's range, a base outside it is not pulled in", function()
	local r = { da = 0, dp = 0.05, side = 0, zoom = 0, off = 0 }
	local v = F.kbView(view(0, 0, 50, 0, 0.18), r, 10, {}, 0.04, 0.20)
	ok(v.p <= 0.20 + 1e-12)
	r.dp = -0.05
	v = F.kbView(view(0, 0, 50, 0, 0.02), r, 10, {}, 0.04, 0.20)
	ok(v.p >= F.KB.pMin - 1e-12 and v.p <= 0.02 + 1e-12, "a low shot stays where it was framed")
end)

test("kbRates: a main move per shot, a random pace from the old speed up, every move used; half around saved views", function()
	local rnd = cam.newRng(9)
	local K = F.KB
	local mains, speeds = {}, { lo = 9, hi = 0 }
	for __ = 1, 400 do
		local r = F.kbRates(rnd, 1, 0)
		mains[r.move] = (mains[r.move] or 0) + 1
		ok(r.speed >= K.speedMin - 1e-12 and r.speed <= K.speedMax + 1e-12, "pace " .. r.speed)
		speeds.lo, speeds.hi = math.min(speeds.lo, r.speed), math.max(speeds.hi, r.speed)
		local f = r.speed / K.refS + 1e-12
		ok(math.abs(r.da) <= K.orbit * f and math.abs(r.zoom) <= K.push * f and math.abs(r.side) <= K.truck * f
			and math.abs(r.rise) <= K.pedestal * f, "within the amounts at its pace")
		ok(math.abs(r.dp) <= (K.tilt + K.tiltFollow * K.pedestal) * f)
		-- the main move at its full amount, the others small
		local full = { push = math.abs(r.zoom) / K.push, truck = math.abs(r.side) / K.truck,
			pedestal = math.abs(r.rise) / K.pedestal, orbit = math.abs(r.da) / K.orbit }
		if full[r.move] ~= nil then near(full[r.move] * K.refS / r.speed, 1, 1e-9, r.move .. " at full amount") end
		for k, v in pairs(full) do
			if k ~= r.move then ok(v * K.refS / r.speed <= K.minor + 1e-9, k .. " minor") end
		end
		local h = F.kbRates(rnd, 0.5, 0)
		ok(math.abs(h.da) <= K.orbit * K.speedMax * 0.5 / K.refS + 1e-12)
	end
	for __, mw in ipairs(F.KB_MOVES) do ok((mains[mw[1]] or 0) > 10, "main move " .. mw[1] .. " used") end
	ok((mains.orbit or 0) < (mains.push or 0) and (mains.orbit or 0) < (mains.pedestal or 0), "not mostly orbit")
	ok(speeds.lo < 1.2 and speeds.hi > 2.3, "the pace varies: " .. speeds.lo .. "-" .. speeds.hi)
	-- looking along +x (look offset pi/2 from angle -pi/2): the slide moves across, along y
	local r = { da = 0, dp = 0, side = 0.01, zoom = 0, off = math.pi / 2 }
	local v = F.kbView(view(0, 0, 100, -math.pi / 2, 0.1), r, 10, {})
	near(v.x, 0, 1e-9); near(math.abs(v.y), 10, 1e-9)
	-- pedestal: the reference ground (and with it the eye) rises; the pose's eye moves straight up
	local base = { x = 0, y = 0, d = 100, a = 0, p = 0.3, g = 50 }
	local up = F.kbView(base, { rise = 0.01, off = 0 }, 10, {})
	near(up.g, 60, 1e-9)
	local ex0, ey0, ez0 = F.poseOf(base, 0)
	local ex1, ey1, ez1 = F.poseOf(up, 0)
	near(ex1, ex0, 1e-9); near(ey1, ey0, 1e-9); near(ez1 - ez0, 10, 1e-9)
end)

test("pathPoint: through the waypoints with a continuous heading", function()
	local path = { { x = 0, y = 0 }, { x = 2000, y = 0 }, { x = 4000, y = 1500 }, { x = 6000, y = 1500 } }
	local x, y = F.pathPoint(path, 0)
	near(x, 0); near(y, 0)
	x, y = F.pathPoint(path, 2000)
	near(x, 2000, 1e-6); near(y, 0, 1e-6)
	local prevH = nil
	local maxJump = 0
	for s = 0, F.pathLength(path), 25 do
		local __, __, hx, hy = F.pathPoint(path, s)
		near(hx * hx + hy * hy, 1, 1e-9, "unit heading")
		local h = cam.atan2(hy, hx)
		if prevH ~= nil then maxJump = math.max(maxJump, math.abs(cam.angleDiff(prevH, h))) end
		prevH = h
	end
	ok(maxJump < 0.05, "smooth heading changes: " .. maxJump)
	local ex, ey = F.pathPoint(path, 1e9)
	near(ex, 6000, 1e-6); near(ey, 1500, 1e-6)
	eq(F.pathPoint({}, 0), nil)
end)

test("nextWaypoint: inside the inner bounds, gentle turns, a made-up point when nothing fits", function()
	local rnd = cam.newRng(21)
	local bounds = { -8000, -8000, 8000, 8000 }
	local ib = F.inner(bounds)
	local last = { x = 0, y = 0 }
	local heading = 0
	for __ = 1, 200 do
		local wp = F.nextWaypoint(last, heading, {}, bounds, rnd)
		ok(wp.x >= ib[1] - 1e-6 and wp.x <= ib[3] + 1e-6 and wp.y >= ib[2] - 1e-6 and wp.y <= ib[4] + 1e-6,
			"inside: " .. wp.x .. "," .. wp.y)
		local h = cam.atan2(wp.y - last.y, wp.x - last.x)
		heading, last = h, wp
	end
	-- a candidate behind the drone is not taken; one ahead is
	local wp = F.nextWaypoint({ x = 0, y = 0 }, 0, { { x = -3000, y = 0, w = 10 }, { x = 2500, y = 300, w = 1, why = "town" } },
		bounds, rnd)
	eq(wp.why, "town")
	-- a candidate outside the map is never taken
	wp = F.nextWaypoint({ x = 0, y = 0 }, 0, { { x = 7900, y = 0, w = 10, why = "edge" } }, bounds, rnd)
	ok(wp.why ~= "edge")
	-- near the edge, heading out: turned back inside
	wp = F.nextWaypoint({ x = 6000, y = 0 }, 0, {}, bounds, rnd)
	ok(wp.x <= ib[3] + 1e-6)
end)

test("droneView: the eye above the ground, looking at the path ahead", function()
	local v = F.droneView(0, 0, 400, 0, 220, 0, {})
	near(v.x, 400); near(v.y, 0)
	near(v.d * math.sin(v.p), 220, 1e-6, "eye height above the centre")
	near(v.a, 0, 1e-12, "looking along +x")
	ok(v.p >= F.FLY.pMin and v.p <= F.FLY.pMax)
	local w = F.droneView(0, 0, 400, 0, 220, math.pi / 2, {})
	near(w.a, -math.pi / 2, 1e-12, "the look offset turns into the camera angle")
	ok(cam.safeView(v) ~= nil)
	-- the altitude varies slowly around FLY.alt
	for t = 0, 200, 5 do
		local a = F.altitude(t, 0.3)
		ok(a >= F.FLY.alt - F.FLY.altAmp - 1e-9 and a <= F.FLY.alt + F.FLY.altAmp + 1e-9)
	end
	near(F.smoothTo(0, 10, 1e9, 1), 10, 1e-9)
	near(F.smoothTo(0, 10, 0, 1), 0)
	eq(F.smoothTo(nil, 5, 0.1, 1), 5)
end)

-- Mouse look and the horizon look (user feedback 2026-10-13)

test("lookStep: input accumulates and is clamped; it decays to 0 only after the player let go", function()
	local l = F.newLook()
	for __ = 1, 50 do F.lookStep(l, 0.1, 0.1, 0.1, 0.016, true) end
	near(l.p, F.LOOK.pMax, 1e-9, "tilt clamped"); near(l.z, F.LOOK.zMax, 1e-9, "zoom clamped")
	ok(math.abs(l.a) <= math.pi, "angle wrapped")
	local a0 = l.a
	F.lookStep(l, 0, 0, 0, 0.1, true)
	eq(l.a, a0, "no decay right after the input")
	for __ = 1, 6 do F.lookStep(l, 0, 0, 0, 0.1, true) end -- idle 0.7 s
	ok(math.abs(l.a) < math.abs(a0), "decaying")
	for __ = 1, 60 do F.lookStep(l, 0, 0, 0, 0.1, true) end -- ~6 s more
	ok(math.abs(l.p) < 0.06 * F.LOOK.pMax, "mostly back after ~5 s: " .. l.p)
	local k = F.newLook()
	F.lookStep(k, 0.4, 0, 0, 0.016, false)
	for __ = 1, 200 do F.lookStep(k, 0, 0, 0, 0.1, false) end
	near(k.a, 0.4, 1e-9, "decay off: the offset stays")
	F.lookStep(k, 0 / 0, 1, 1, 0.1, true)
	ok(k.a == k.a and k.p == k.p, "NaN input ignored")
end)

test("applyLook: offsets on the view, the eye never below the minimum height", function()
	local v = F.applyLook(view(0, 0, 400, 0.2, 0.3), { a = 0.5, p = -0.25, z = math.log(0.5) }, 100)
	near(v.a, 0.7, 1e-9); near(v.d, 200, 1e-9)
	ok(v.d * math.sin(v.p) >= 100 - 1e-6, "raised to keep the eye up: " .. v.p)
	local w = F.applyLook(view(0, 0, 400, 0.2, 0.3), F.newLook())
	near(w.p, 0.3, 1e-12); near(w.d, 400, 1e-9)
	local big = F.applyLook(view(0, 0, 3500, 0, 0.1), { a = 0, p = 0, z = 1 })
	ok(big.d <= cam.ZOOM_LIMIT, "within the zoom limit")
end)

test("horizon look: the centre far ahead, nearly level, inside the zoom limit", function()
	for _, h in ipairs({ 100, 300, 500, 900 }) do
		local L = F.horizonAhead(h)
		local v = F.droneView(0, 0, L, 0, h, 0, nil, F.HORIZON.pMin)
		ok(v.d <= cam.ZOOM_LIMIT + 1e-6, "d " .. v.d)
		ok(v.p <= 0.25, "nearly level at " .. h .. " m: " .. v.p)
		near(v.d * math.sin(v.p), h, 1e-6, "eye height kept")
	end
end)

-- Eye space (round 7): the eye follows the plan, not the terrain under the look-at point

local function bumpy(x, y)
	return 25 * math.sin(x / 31) + 18 * math.cos(y / 17) + 4 * math.sin((x + y) / 9)
end

--- Hills of 0-300 m with small bumps (the Aerials' country): long views over crests.
local function hilly(x, y)
	return math.max(-5, 130 + 90 * math.sin(x / 700) + 60 * math.cos(y / 530) + 25 * math.sin(x / 90 + y / 130)
		+ bumpy(x, y) * 0.4)
end

--- The game's placement of a sent view (the camera model): the centre 4 m over the ground there, the eye at the
--- model's elevation for the pitch and distance sent.
local function engineEye(v, ground, off)
	return F.eyeOf(v, ground(v.x, v.y), off)
end

test("solveEye: on bumpy ground the eye lands where planned, smooth frame to frame, while the centre's ground jumps", function()
	local st = F.newEye()
	local calls = 0
	local function ground(x, y) calls = calls + 1 return bumpy(x, y) end
	local off = math.pi -- the game's look offset (look heading = camera angle + pi)
	local dt = 1 / 60
	local ez, cg, naive = {}, {}, {}
	local maxErr, maxPitchErr = 0, 0
	local lastP, dpMax, reads, bad = nil, 0, 0, 0
	local N = 3600 -- 60 s, the eye 670 m along a straight, slowly sinking line
	for i = 0, N do
		local t = i / N
		local px, py, pz = 600 * t, 300 * t, 150 - 20 * t
		-- an elevation the game can show at this distance (round 9: k(600 m) ~ 0.33, so at least ~0.52)
		local h, p = 0.4 + 0.2 * t, 0.6
		calls = 0
		local v = F.solveEye(st, px, py, pz, h, p, nil, 60, ground, off, i == 0 and 0 or dt, {})
		ok(calls <= 2 + 2 * F.EYE.maxIters, "height reads per frame: " .. calls)
		reads = reads + calls
		local look = F.gameElev(v.p, v.d) -- the look's elevation (the game looks at its centre)
		if math.abs(look - p) > 0.01 then bad = bad + 1 end
		ok(cam.safeView(v) ~= nil, "finite")
		local ex, ey, z = engineEye(v, bumpy, off)
		maxErr = math.max(maxErr, math.abs(ex - px), math.abs(ey - py), math.abs(z - st.ez))
		eq(st.ez, pz, "no clearance lift needed this high up")
		maxPitchErr = math.max(maxPitchErr, math.abs(look - p))
		if lastP then dpMax = math.max(dpMax, math.abs(look - lastP)) end
		lastP = look
		ez[#ez + 1] = z
		cg[#cg + 1] = bumpy(v.x, v.y)
		-- the old way: the planned view sent as is, its centre where the plan's look meets z = 0
		local L = (pz - 0) / math.tan(p)
		local nx, ny = px + math.cos(h) * L, py + math.sin(h) * L
		naive[#naive + 1] = bumpy(nx, ny) + (L / math.cos(p)) * math.sin(p)
	end
	ok(maxErr < 1e-6, "the eye exactly where planned: " .. maxErr)
	-- round 9: where the meeting point jumps (a crest) the centre slides there over EYE.blendS, the look leaving
	-- the plan for that second (the eye stays exact). Round 14 (the Down look's "glitchy tilt", session
	-- 2026-10-14_0633_session: the look jolts sat in blended frames): blendS 0.5 -> 1.0 s, the look's largest
	-- step a frame 0.0110 -> 0.0062 rad here, the frames off the plan 59 -> 126 of 3601
	ok(dpMax < 0.008, "the look changes smoothly: at most " .. dpMax .. " rad from frame to frame (" .. maxPitchErr .. " off at most)")
	ok(bad <= 0.04 * N, "off by more than 0.01 rad only while a crest's jump is blended: " .. bad)
	ok(reads / (N + 1) <= 1 + F.EYE.iters + 0.1, "about 4 height reads a frame: " .. reads / (N + 1))
	local function jerk(list)
		local m = 0
		for i = 2, #list - 1 do m = math.max(m, math.abs(list[i + 1] - 2 * list[i] + list[i - 1])) end
		return m
	end
	local function step(list)
		local m = 0
		for i = 2, #list do m = math.max(m, math.abs(list[i] - list[i - 1])) end
		return m
	end
	ok(step(ez) < 0.01 and jerk(ez) < 1e-6, "eye height smooth: step " .. step(ez) .. " jerk " .. jerk(ez))
	ok(step(cg) > 0.3, "while the ground under the centre jumps: " .. step(cg))
	ok(step(naive) > 30 * step(ez), "the old placement bobbed with it: " .. step(naive))
end)

test("solveEye: the clearance lifts the eye before a hill ahead, smoothly, and lets it down slowly", function()
	local function hill(x, y) return x > 400 and x < 600 and 80 or 0 end
	local function ground(x, y) return hill(x, y) end
	local st = F.newEye()
	local dt = 1 / 60
	local zs, liftAt = {}, nil
	for i = 0, 90 * 60 do
		local x = 10 * i * dt -- 10 m/s along +x, planned 30 m above the flat ground
		F.solveEye(st, x, 0, 30, 0, 0.3, nil, 30, ground, 0, i == 0 and 0 or dt, {})
		zs[#zs + 1] = st.ez
		if liftAt == nil and st.ez > 31 then liftAt = x end
		ok(st.ez >= hill(x, 0) + F.EYE.clearMin - 1e-9, "never below the ground under the eye at " .. x)
	end
	ok(liftAt ~= nil and liftAt < 400, "rising before the hill: " .. tostring(liftAt))
	local m = 0
	for i = 2, #zs do m = math.max(m, zs[i] - zs[i - 1]) end
	ok(m < 3, "no pop: the biggest rise in one frame " .. m)
	ok(zs[#zs] < 32, "settled back down after the hill: " .. zs[#zs])
end)

test("solveEye: a nearly level look: the flattest the game can show, the eye kept; the centre on the map", function()
	local st = F.newEye()
	-- round 9: 0.02 is flatter than the game shows that far out: the flattest it can (pitch 0 sent), eye kept
	local v = F.solveEye(st, 0, 0, 300, 0, 0.02, nil, 300, function() return 0 end, 0, 0, {})
	ok(v.d <= cam.ZOOM_LIMIT, "within the zoom limit: " .. v.d)
	local ex, ey, ez = F.eyeOf(v, 0, 0)
	near(ex, 0, 0.05); near(ey, 0, 0.05); near(ez, 300, 0.05, "the eye kept")
	ok(v.p >= 0 and v.p < 0.2, "about the flattest pitch: " .. v.p)
	-- and inside the map: the centre stays within maxL along the ray
	st = F.newEye()
	st.maxL = F.rayInside({ -1000, -1000, 1000, 1000 }, 0, 0, 0)
	near(st.maxL, 1000, 1e-9)
	v = F.solveEye(st, 0, 0, 300, 0, 0.02, nil, 300, function() return 0 end, 0, 0, {})
	ok(v.x <= 1000 + 1e-6, "centre on the map: " .. v.x)
	eq(F.rayInside(nil, 0, 0, 0), math.huge)
	eq(F.rayInside({ 0, 0, 10, 10 }, 50, 50, 0), math.huge, "an eye off the map keeps nothing")
	near(F.rayInside({ -10, -10, 10, 10 }, 0, 0, math.pi / 4), 10 * math.sqrt(2), 1e-9)
end)

test("solveEye: unreadable heights, NaN input and a straight-down look stay finite", function()
	local st = F.newEye()
	local v = F.solveEye(st, 0, 0, 100, 0, 0.5, nil, 50, function() return nil end, 0, 0.016, {})
	ok(cam.safeView(v) ~= nil)
	v = F.solveEye(F.newEye(), 0, 0, 100, 0, 1.5, nil, 50, function() return 0 end, 0, 0.016, {})
	ok(cam.safeView(v) ~= nil and v.p <= cam.SAFE.pMax + 1e-9)
	v = F.solveEye(F.newEye(), 0, 0, 100, 0, 0 / 0, 0 / 0, 0 / 0, function() return 0 end, 0, 0 / 0, {})
	ok(cam.safeView(v) ~= nil, "NaN pitch / hint / dt")
	-- poseOf and viewOfPose are inverse
	local plan = { x = 100, y = 50, d = 300, a = 1, p = 0.4, g = 20 }
	local ex, ey, ez, h, p = F.poseOf(plan, 0.5)
	local back = F.viewOfPose(ex, ey, ez, h, p, 300, 0.5, {})
	for __, k in ipairs({ "x", "y", "d", "a", "p", "g" }) do near(back[k], plan[k], 1e-9, k) end
end)

test("wander: around the place in x and y, in and out (not an orbit), slow, never through the middle", function()
	local w = F.newWander(1000, 2000, 250, 30, 0.1, 0.5, cam.newRng(3), 0)
	local minX, maxX, minY, maxY, minR, maxR = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
	local px, py = F.wanderEye(w, 0)
	local maxV = 0
	for i = 1, 6000 do
		local t = i * 0.05
		local x, y = F.wanderEye(w, t)
		local r = math.sqrt((x - 1000) ^ 2 + (y - 2000) ^ 2)
		minR, maxR = math.min(minR, r), math.max(maxR, r)
		minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
		maxV = math.max(maxV, math.sqrt((x - px) ^ 2 + (y - py) ^ 2) / 0.05)
		px, py = x, y
	end
	ok(maxX - minX > 250 and maxY - minY > 250, "moves in both x and y")
	ok(minR >= 250 * F.WANDER.rMin - 1e-6 and maxR <= 250 * F.WANDER.rMax + 1e-6, "inside the area, never the middle")
	ok(maxR - minR > 0.2 * 250, "in and out, not a circle: " .. minR .. "-" .. maxR)
	ok(maxV < 0.08 * 250, "slow: " .. maxV .. " m/s")
	-- the start bearing: the eye begins on the side it was
	local w2 = F.newWander(0, 0, 100, 0, 0.1, 0.5, cam.newRng(8), math.pi / 2)
	local sx, sy = F.wanderEye(w2, 0)
	near(cam.atan2(sy, sx), math.pi / 2, 1e-9)
end)

test("wander: the look eases between targets, the pitch inside the range, every view finite", function()
	local w = F.newWander(0, 0, 250, 0, 0.1, 0.5, cam.newRng(4), 0)
	local rnd = cam.newRng(11)
	local dt = 1 / 30
	local lastH, maxTurn = nil, 0
	local nextAt = 0
	for i = 0, 30 * 120 do
		local t = i * dt
		if t >= nextAt then
			F.wanderSetTarget(w, t, (rnd() - 0.5) * 300, (rnd() - 0.5) * 300, rnd() * 40)
			nextAt = t + F.WANDER.lookS
		end
		local v = F.wanderView(w, t, i == 0 and 0 or dt, 0, {})
		ok(cam.safeView(v) ~= nil, "finite")
		ok(v.p >= 0.01 - 1e-9 and v.p <= F.EYE.elevMax + 1e-9)
		if lastH ~= nil then maxTurn = math.max(maxTurn, math.abs(cam.angleDiff(lastH, w.h))) end
		lastH = w.h
	end
	ok(maxTurn < 0.05, "the heading turns smoothly: at most " .. maxTurn .. " rad a frame")
	local r, lo, hi = F.wanderAround({ x = 0, y = 0, d = 400, a = 0, p = 0.5 })
	near(r, 400 * math.cos(0.5), 1e-9); near(lo, 0.38, 1e-9); near(hi, 0.62, 1e-9)
	r = F.wanderAround({ x = 0, y = 0, d = 20, a = 0, p = 0.04 })
	eq(r, F.WANDER.manualMinR)
end)

-- Round 9 / 10: the game's camera model (refitted in round 10 to sessions 2026-10-13_1755_session and
-- 2026-10-13_1915_session), its residual loop, smoothness

-- Distinct samples of both sessions (cam trace + eye check lines): distance and pitch read, the elevation of
-- getEye over getCenter.
local SAMPLES = {
	{ 25.0, 0.040, 0.238 }, { 26.6, 0.078, 0.273 }, { 30.2, 0.433, 0.584 }, { 31.2, 0.259, 0.436 },
	{ 33.3, 0.670, 0.794 }, { 37.2, 0.219, 0.407 }, { 41.8, 0.145, 0.349 }, { 41.8, 0.264, 0.451 },
	{ 42.3, 0.008, 0.231 }, { 44.3, 0.355, 0.530 }, { 48.8, 0.090, 0.306 }, { 61.4, 0.644, 0.794 },
	{ 64.3, 0.140, 0.361 }, { 69.5, 0.625, 0.783 }, { 72.1, 0.658, 0.813 }, { 83.3, 0.159, 0.390 },
	{ 86.1, 0.025, 0.278 }, { 126.2, 0.434, 0.649 }, { 129.7, 0.476, 0.687 }, { 161.9, 0.452, 0.680 },
	{ 195.1, 0.351, 0.608 }, { 324.4, 0.138, 0.471 }, { 361.3, 0.598, 0.868 }, { 369.9, 0.316, 0.634 },
	{ 393.0, 0.612, 0.888 }, { 399.9, 0.452, 0.755 }, { 406.1, 0.247, 0.585 }, { 780.3, 0.059, 0.506 },
	{ 809.7, 0.000, 0.463 }, { 823.4, 0.477, 0.858 }, { 932.3, 0.441, 0.844 }, { 987.6, 0.137, 0.603 },
	{ 994.9, 0.419, 0.835 }, { 1087.2, 0.388, 0.821 }, { 1204.4, 0.347, 0.802 }, { 1324.0, 0.305, 0.780 },
	{ 1442.8, 0.262, 0.757 }, { 1551.0, 0.222, 0.734 }, { 1673.6, 0.175, 0.707 }, { 1725.0, 0.155, 0.694 },
}
-- Session 2026-10-13_1915_session, a glide out from 1725 m: distance, getHeightAt under the centre, getCenter's z.
local CENTRES = {
	{ 780.3, 54.3, 58.3 }, { 852.6, 38.4, 41.7 }, { 932.3, 38.4, 38.8 }, { 993.6, 61.3, 54.0 }, { 1053.8, 38.4, 30.9 },
	{ 1114.6, 38.4, 26.1 }, { 1204.4, 38.4, 18.7 }, { 1264.7, 38.4, 14.1 }, { 1355.0, 38.4, 8.3 },
	{ 1442.8, 38.4, 4.7 }, { 1524.7, 38.4, 4.0 }, { 1673.6, 38.4, 4.0 },
}

--- Round 9's model, to compare: k = 0.0768 + 0.0102 sqrt(d) times (pi/2 - p), no lift, the centre always on the
--- terrain, the residual within 0.12, no last-resort bisection, no steepest-pitch bound.
local function round9(fn)
	local save = { F.camK, F.centreKeep, F.pitchMaxAt, F.CAM.resMax, F.EYE.guardIters }
	F.camK = function(d) return cam.clamp(0.0768 + 0.0102 * math.sqrt(math.max(0, tonumber(d) or 0)), 0, 0.8), 0 end
	F.centreKeep = function() return 1 end
	F.pitchMaxAt = function() return 10 end
	F.CAM.resMax, F.EYE.guardIters = 0.12, 0
	local r = table.pack(pcall(fn))
	F.camK, F.centreKeep, F.pitchMaxAt, F.CAM.resMax, F.EYE.guardIters = save[1], save[2], save[3], save[4], save[5]
	assert(r[1], r[2])
	return table.unpack(r, 2, r.n)
end

test("camera model: fits both sessions (d 25-1725 m); pitchFor inverts gameElev; the centre lowered far out", function()
	local function fit()
		local sq, worst = 0, 0
		for __, c in ipairs(SAMPLES) do
			local r = F.gameElev(c[2], c[1]) - c[3]
			sq = sq + r * r
			worst = math.max(worst, math.abs(r))
		end
		return math.sqrt(sq / #SAMPLES), worst
	end
	local rms, worst = fit()
	ok(rms < 0.003 and worst < 0.006, "residual rms " .. rms .. " max " .. worst)
	local rms9, worst9 = round9(fit)
	ok(rms9 > 5 * rms and worst9 > 0.03, "round 9's model: rms " .. rms9 .. " max " .. worst9)
	for __, d in ipairs({ 20, 100, 400, 1500, 4000 }) do
		for __, e in ipairs({ 0.5, 0.9, 1.3 }) do
			near(F.gameElev(F.pitchFor(e, d, 0.02), d, 0.02), e, 1e-12, "inverse at " .. d)
		end
		ok(F.gameElev(0, d) > 0.1, "never level")
		near(F.gameElev(F.pitchMaxAt(d), d), F.CAM.elevSafe, 1e-12, "the steepest pitch sent stays short of straight down")
	end
	-- round 7's Bird's eye: 1.45 at 900 m put the eye past straight down (the inverted WASD keys); 1.30 doesn't
	ok(F.gameElev(1.45, 900) > math.pi / 2, "1.45 at 900 m: past straight down " .. F.gameElev(1.45, 900))
	ok(F.gameElev(1.30, 900) < math.pi / 2, "1.30 at 900 m below it " .. F.gameElev(1.30, 900))
	-- the centre: 4 m over the ground near, the water level far out
	eq(F.centreZ(10), 14); eq(F.centreZ(-1), 4, "over water: the water level + 4")
	for __, c in ipairs(CENTRES) do
		near(F.centreZ(c[2], c[1]), c[3], 0.6, "the centre at " .. c[1] .. " m")
	end
	eq(F.centreZ(100, 700), 104); eq(F.centreZ(100, 2000), 4)
	-- an elevation view and the game's view of it put the eye in the same place (near and far)
	for __, d in ipairs({ 150, 1100 }) do
		local gv = { x = 10, y = 20, d = d, a = 0.3, p = 0.4, g = 30 }
		local ev = F.elevView(gv, 0.01)
		local ax, ay, az = F.poseOf(gv, 0, true, 0.01)
		local bx, by, bz = F.poseOf(ev, 0, false)
		near(ax, bx, 1e-9); near(ay, by, 1e-9); near(az, bz, 1e-9)
		local back = F.gameView(ev, 0.01)
		near(back.p, gv.p, 1e-9); near(back.g, gv.g, 1e-6)
	end
end)

test("pitchSample: the game's eye-centre elevation less the pitch set; refused when the camera doesn't match", function()
	local cur = { x = 100, y = 50, d = 200, p = 0.1 }
	local e = 0.1 + 0.27
	local L = 200 * math.cos(e)
	local ex, ey, ez = 100 - L, 50, 10 + 200 * math.sin(e)
	local s = F.pitchSample(cur, ex, ey, ez, 100, 50, 10)
	ok(math.abs(s - 0.27) < 1e-9, tostring(s))
	near(F.resSample(cur, s), 0.1 + 0.27 - F.gameElev(0.1, 200), 1e-12, "the residual: less the model's offset")
	eq(F.resSample(cur, nil), nil)
	local r, why = F.pitchSample(cur, ex - 100, ey, ez, 100, 50, 10)
	eq(r, nil); eq(why, "distance")
	r, why = F.pitchSample(cur, ex, ey + 40, ez, 100, 90, 10)
	eq(r, nil); eq(why, "centre")
	r, why = F.pitchSample(cur, 0 / 0, ey, ez, 100, 50, 10)
	eq(r, nil); eq(why, "eye")
	r, why = F.pitchSample(nil, ex, ey, ez, 100, 50, 10)
	eq(r, nil)
end)

test("resUpdate: starts at 0, follows slowly and smoothly, clamped; nil or dt 0 keeps it", function()
	local C = F.CAM
	eq(F.resUpdate(nil, nil, nil, 0.016), 0)
	eq(F.resUpdate(nil, nil, 0.03, 0), 0, "dt 0: no change")
	local r, v = F.resUpdate(0, 0, 0.03, 1 / 60)
	ok(r > 0 and r < 1e-4, "starts moving gently: " .. r)
	local prevV, maxDv = 0, 0
	r, v = 0, 0
	for __ = 1, 60 * 30 do
		r, v = F.resUpdate(r, v, 0.03, 1 / 60)
		maxDv = math.max(maxDv, math.abs(v - prevV))
		prevV = v
	end
	near(r, 0.03, 1e-3, "settles on a steady residual")
	ok(maxDv < 1e-3, "its rate changes smoothly: " .. maxDv)
	r, v = 0, 0
	for __ = 1, 60 * 60 do r, v = F.resUpdate(r, v, 5, 1 / 60) end
	ok(r <= C.resMax + 1e-12 and r > C.resMax - 1e-3, "clamped: " .. r)
	-- a residual that flips with the terrain every few frames barely moves it
	r, v = 0, 0
	local m = 0
	for i = 1, 600 do
		r, v = F.resUpdate(r, v, (math.floor(i / 3) % 2 == 0) and 0.08 or -0.08, 1 / 60)
		m = math.max(m, math.abs(r))
	end
	ok(m < 0.01, "terrain-frequency noise filtered: " .. m)
end)

test("solveEye with the camera model: the game's eye exact on bumpy ground; the pitch sent never below 0", function()
	local maxErr, minP, maxCalls = 0, math.huge, 0
	for __, p in ipairs({ 0.35, 0.6, 0.9, 1.3 }) do
		local st = F.newEye(0.01)
		for i = 0, 200 do
			local ex, ey, ez = i * 3, 40, bumpy(i * 3, 40) + 4 + 40
			local v = F.solveEye(st, ex, ey, ez, 0, p, 100, 40, bumpy, 0, 0.05, {})
			local gx, gy, gz = F.eyeOf(v, bumpy(v.x, v.y), 0, 0.01)
			maxErr = math.max(maxErr, math.abs(gx - st.ex), math.abs(gy - st.ey), math.abs(gz - st.ez))
			minP = math.min(minP, v.p)
			maxCalls = math.max(maxCalls, st.calls)
		end
	end
	ok(maxErr < 1e-6, "eye exact: " .. maxErr)
	ok(minP >= 0, "pitch sent >= 0: " .. minP)
	ok(maxCalls <= 2 + 2 * F.EYE.maxIters + F.EYE.guardIters, "height reads: " .. maxCalls)
	-- a look flatter than the game can show: the flattest it can, the eye still where planned
	local st = F.newEye(0)
	for i = 0, 100 do
		local v = F.solveEye(st, i * 3, 40, 80, 0, 0.05, 300, 80, bumpy, 0, 0.05, {})
		ok(v.p >= 0, "pitch >= 0")
		local gx, gy, gz = F.eyeOf(v, bumpy(v.x, v.y), 0, 0)
		ok(math.abs(gz - st.ez) < 0.5 and math.abs(gx - st.ex) < 0.5, "eye kept: " .. gz - st.ez)
	end
	-- far out (the centre lowered to the water level): still exact, a too-flat look steepened, never sent at 0
	st = F.newEye(0)
	local far = 0
	for i = 0, 200 do
		local ex, ey, ez = i * 20, 0, 900
		local v = F.solveEye(st, ex, ey, ez, 0, 0.3, 2000, 800, hilly, 0, 0.05, {})
		local gx, gy, gz = F.eyeOf(v, hilly(v.x, v.y), 0, 0)
		far = math.max(far, math.abs(gx - ex), math.abs(gz - st.ez))
		ok(v.p <= F.pitchMaxAt(v.d) + 1e-9, "never past the steepest")
	end
	ok(far < 1e-6, "far out, eye exact: " .. far)
end)

test("smoothness metric: a steady glide is quiet, a bump shows as a jerk spike, a cut is not motion", function()
	local m = F.newSmooth()
	for i = 0, 300 do
		local t = i / 60
		local e = cam.ease(t / 5)
		F.smoothAdd(m, 500 * e, 0, 100, i == 0 and 0 or 1 / 60)
	end
	local d2, d2r, acc, jmax = F.smoothStats(m)
	ok(d2 < 0.05 and jmax < 1, "smooth: d2 " .. d2 .. " jerk " .. jmax)
	F.smoothAdd(m, 500, 0, 101, 1 / 60) -- a 1 m bump
	F.smoothAdd(m, 500, 0, 100, 1 / 60)
	local d2b, __, __, jb, __, n, worst = F.smoothStats(m)
	ok(d2b > 0.9 and jb > 1000, "the bump: d2 " .. d2b .. " jerk " .. jb)
	eq(worst, n, "worst at the last frame")
	F.smoothAdd(m, 0, 0, 0, 2) -- a hitch restarts the chain, no spike counted
	eq(select(1, F.smoothStats(m)), d2b)
	-- round 10: a cut (a jump of the camera to another place) restarts the chain too and is counted, not measured
	local c = F.newSmooth()
	for i = 0, 60 do F.smoothAdd(c, i, 0, 100, i == 0 and 0 or 1 / 60) end
	F.smoothAdd(c, 5000, 0, 100, 1 / 60) -- 5 km in a frame: no camera flies that
	for i = 1, 60 do F.smoothAdd(c, 5000 + i, 0, 100, 1 / 60) end
	local cd2, __, __, __, __, __, __, cv = F.smoothStats(c)
	ok(cd2 < 1e-6 and cv < 100, "the cut is not motion: d2 " .. cd2 .. " speed " .. cv)
	eq(c.cuts, 1, "counted")
	F.smoothCut(c) -- the driver's own cut (a jump it makes)
	F.smoothAdd(c, 0, 0, 0, 1 / 60)
	F.smoothAdd(c, 1, 0, 0, 1 / 60)
	eq(select(1, F.smoothStats(c)), cd2, "after smoothCut the chain starts again")
	eq(c.cuts, 2)
end)

--- The game's TRUE camera for the replays (round 10's fit written out, so it stays the truth when a test swaps
--- the solver's model for round 9's), plus off(d, p): how far the game is off the fit (rad).
local function trueGame(off)
	local function smooth(u) u = math.max(0, math.min(1, u)) return u * u * (3 - 2 * u) end
	local function elev(p, d)
		return p + (0.07092 + 0.01624 * math.log(d)) * (math.pi / 2 - p) + 0.44961 * d / (d + 1185) + (off and off(d, p) or 0)
	end
	local function centre(g, d) return 4 + math.max(g, 0) * smooth((1500 - d) / 700) end
	return elev, centre
end

--- Replays a move on a synthetic game: each frame the plan's pose, the solver, the game's eye (trueGame); the
--- residual measured from it and corrected (F.resUpdate) as the driver does. Returns the eye's worst second
--- difference less the plan's own (m), the worst eye error (m) once settled (after 20 s), the getHeightAt reads
--- per frame (mean, max) and the worst frame's details.
local function replay(planFn, gamePitch, frames, off, terrain)
	terrain = terrain or bumpy
	local elev, centre = trueGame(off)
	local dt = 1 / 60
	local st = F.newEye(0)
	local res, resV = 0, 0
	local real, plan = {}, {}
	local errMax, reads, readMax = 0, 0, 0
	local function game(v)
		local h = cam.lookOf(v.a, 0)
		local e = elev(v.p, v.d)
		local L = v.d * math.cos(e)
		return v.x - math.cos(h) * L, v.y - math.sin(h) * L, centre(terrain(v.x, v.y), v.d) + v.d * math.sin(e), e
	end
	local calls = 0
	local function ground(x, y) calls = calls + 1 return terrain(x, y) end
	local out = {}
	for i = 0, frames do
		local pv = planFn(i * dt, i == 0 and 0 or dt)
		local ex, ey, ez, h, p, L = F.poseOf(pv, 0, gamePitch, res)
		st.res = res
		calls = 0
		local v = F.solveEye(st, ex, ey, ez, h, p, L, ez - (pv.g or 0), ground, 0, i == 0 and 0 or dt, out)
		local x, y, d, a, pp = cam.safeView(v)
		v = { x = x, y = y, d = d, a = a, p = pp }
		reads, readMax = reads + calls, math.max(readMax, calls)
		local gx, gy, gz, e = game(v)
		real[#real + 1] = { gx, gy, gz, v.d, v.p, st.err, calls, e }
		plan[#plan + 1] = { st.ex, st.ey, st.ez }
		if i > 60 * 20 then errMax = math.max(errMax, math.abs(gz - st.ez), math.abs(gx - st.ex), math.abs(gy - st.ey)) end
		res, resV = F.resUpdate(res, resV, F.resSample(v, e - v.p), i == 0 and 0 or dt)
	end
	local function d2(list, k)
		local a, b, c = list[k - 1], list[k], list[k + 1]
		return math.sqrt((c[1] - 2 * b[1] + a[1]) ^ 2 + (c[2] - 2 * b[2] + a[2]) ^ 2 + (c[3] - 2 * b[3] + a[3]) ^ 2)
	end
	local worst, info = 0, ""
	for k = 5, #real - 1 do -- (a move starts from the current view: frame 0 of this synthetic plan may not converge)
		local w = d2(real, k) - d2(plan, k)
		if w > worst then
			worst = w
			local a, b, c = real[k - 1], real[k], real[k + 1]
			info = string.format(" [f=%d d %.1f %.1f %.1f p %.3f %.3f %.3f calls %d %d %d dz %.2f %.2f %.2f]", k, a[4], b[4],
				c[4], a[5], b[5], c[5], a[7], b[7], c[7], a[3] - plan[k - 1][3], b[3] - plan[k][3], c[3] - plan[k + 1][3])
		end
	end
	return worst, errMax, reads / (frames + 1), readMax, info
end

-- the game a little off the fit (the fit's residual: rms 0.0013 rad, max 0.004; here up to 0.005)
local function offSmall(d, p) return 0.003 + 0.002 * math.sin(d / 400) end

--- A fresh wander plan (pitch range lo .. hi, radius r) over the terrain: a planFn for replay.
local function wanderPlan(lo, hi, r, terrain)
	terrain = terrain or bumpy
	local w = F.newWander(0, 0, r or 300, terrain(0, 0), lo, hi, cam.newRng(5), 0)
	local rnd = cam.newRng(9)
	local nextAt = 0
	local buf = {}
	return function(t, dt)
		if t >= nextAt then
			local x, y = (rnd() - 0.5) * 1.3 * (r or 300), (rnd() - 0.5) * 1.3 * (r or 300)
			F.wanderSetTarget(w, t, x, y, terrain(x, y))
			nextAt = t + F.WANDER.lookS
		end
		return F.wanderView(w, t, dt, 0, buf)
	end
end

test("replay: a Wander over bumpy terrain with the game a bit off the fit: the game's eye as smooth as the plan", function()
	-- the tour's angle rows: high, middle and eye level (game pitches)
	for __, r in ipairs({ { 0.45, 0.8 }, { 0.1, 0.35 }, { 0.04, 0.2 } }) do
		local what = string.format("pitch %.2f-%.2f: ", r[1], r[2])
		local worst, err, mean, mx, info = replay(wanderPlan(r[1], r[2]), false, 60 * 90, offSmall)
		ok(worst < 0.25, what .. "the eye's second difference at most the plan's + " .. worst .. " m a frame" .. info)
		ok(err < 3, what .. "settled within " .. err .. " m of the plan")
		ok(mean <= 4.2 and mx <= 2 + 2 * F.EYE.maxIters + F.EYE.guardIters, what .. "height reads a frame: " .. mean .. " (max " .. mx .. ")")
		local exact = replay(wanderPlan(r[1], r[2]), false, 60 * 90, nil)
		ok(exact < 1e-3, what .. "the game exactly as the fit: exactly as smooth as the plan: " .. exact)
	end
end)

test("replay: the session's large Wander (r 800 m, eye level, hills): smooth now, round 9's model jerked", function()
	-- session 2026-10-13_1915_session: the manual Wander at r=800, pitch 0.04-0.12 (d 780-1000 m): d2 max 14.8 m,
	-- rms 1.07 m in the game
	local worst, err, __, __, info = replay(wanderPlan(0.04, 0.12, 800, hilly), false, 60 * 60, offSmall, hilly)
	ok(worst < 0.5, "now: the eye's second difference at most the plan's + " .. worst .. " m a frame" .. info)
	local w9 = round9(function() return replay(wanderPlan(0.04, 0.12, 800, hilly), false, 60 * 60, offSmall, hilly) end)
	ok(w9 > 4 * worst and w9 > 1, "round 9's model on the same replay: " .. w9 .. " m (now " .. worst .. ")")
end)

test("replay: a tour glide and a Ken Burns hold over bumpy terrain: the game's eye as smooth as the plan", function()
	local function planFn2()
		local from = { x = 0, y = 0, d = 300, a = 0.2, p = 0.5, g = bumpy(0, 0) }
		local to = { x = 900, y = 400, d = 120, a = 1.4, p = 0.25, g = bumpy(900, 400) }
		local rates = F.kbRates(cam.newRng(3), 1, 0)
		local hop = F.newHop(from, { base = to, rates = rates }, cam.GLIDE_SECONDS, 20, cam.glideBump(from, to))
		local buf = {}
		return function(t) return F.hopView(hop, t, buf, 0, 1.2) end
	end
	local worst, err, __, __, info = replay(planFn2(), true, 60 * 25, offSmall)
	-- a glide moves hundreds of m/s at 300-800 m: half a metre is below 0.002 rad
	ok(worst < 0.5, "the eye's second difference at most the plan's + " .. worst .. " m a frame" .. info)
	ok(err < 2.5, "settled within " .. err .. " m")
end)

--- The Aerials' glide to a new area (session 2026-10-13_1915_session: 4.3 and 4.7 km, the glide's rise ~1.5 km,
--- d up to ~2000 m in the game's pitch): a planFn.
local function newAreaGlide(G)
	local from = { x = -600, y = 1400, d = 500, a = -1.44, p = 0.01, g = hilly(-600, 1400) }
	local to = { x = -500, y = -2870, d = 520, a = 2.0, p = 0.05, g = hilly(-500, -2870) }
	local hop = F.newHop(from, to, G or cam.GLIDE_SECONDS, 0, cam.glideBump(from, to))
	local buf = {}
	return function(t) return F.hopView(hop, t, buf) end
end

--- An Aerials flight leg: the eye 32 m/s along a gentle curve at 220 +- 70 m over the smoothed hills, looking at
--- the ground 420 m ahead (pm_driver flightView): an elevation plan.
local function flightPlan()
	local path = { { x = 0, y = 0 }, { x = 1500, y = 300 }, { x = 3000, y = -200 }, { x = 4500, y = 600 } }
	local fl = { ge = nil, gc = nil }
	local buf = {}
	return function(t, dt)
		local dist = F.FLY.speed * F.rampIn(t, F.FLIGHT_RAMP_S)
		local ex, ey, hx, hy = F.pathPoint(path, dist)
		local ge = hilly(ex + hx * F.FLY.groundAhead, ey + hy * F.FLY.groundAhead)
		fl.ge = (dt and dt > 0) and F.smoothTo(fl.ge, ge, dt, F.FLY.smooth) or (fl.ge or ge)
		local ez = fl.ge + F.altitude(t, 0.2)
		local cx, cy = F.pathPoint(path, dist + F.FLY.lookAhead)
		local gc = hilly(cx, cy)
		fl.gc = (dt and dt > 0) and F.smoothTo(fl.gc, gc, dt, F.FLY.smooth) or (fl.gc or gc)
		local L = math.max(1, math.sqrt((cx - ex) ^ 2 + (cy - ey) ^ 2))
		local p = cam.clamp(cam.atan2(ez - fl.gc, L), F.FLY.pMin, F.FLY.pMax)
		return F.viewOfPose(ex, ey, ez, cam.atan2(cy - ey, cx - ex), p, L / math.cos(p), 0, buf)
	end
end

test("replay: the Aerials (a new-area glide over 4 km, a flight leg over hills): smooth now, round 9 jerked", function()
	local worst, __, __, mx, info = replay(newAreaGlide(), true, math.floor(60 * cam.GLIDE_SECONDS), offSmall, hilly)
	local w9, __, __, __, info9 = round9(function()
		return replay(newAreaGlide(), true, math.floor(60 * cam.GLIDE_SECONDS), offSmall, hilly)
	end)
	print(string.format("new-area glide: now %.3f m%s; round 9 %.3f m%s", worst, info, w9, info9))
	ok(worst < 2, "new-area glide (up to ~2 km/s): the eye's second difference at most the plan's + " .. worst .. " m" .. info)
	ok(mx <= 2 + 2 * F.EYE.maxIters + F.EYE.guardIters, "height reads: " .. mx)
	ok(w9 > 3 * worst, "round 9 on the same glide: " .. w9 .. info9)
	local fw, ferr, __, __, finfo = replay(flightPlan(), false, 60 * 30, offSmall, hilly)
	local fw9, __, __, __, finfo9 = round9(function() return replay(flightPlan(), false, 60 * 30, offSmall, hilly) end)
	print(string.format("flight leg: now %.3f m%s; round 9 %.3f m%s", fw, finfo, fw9, finfo9))
	ok(fw < 0.3, "flight leg: the eye's second difference at most the plan's + " .. fw .. " m" .. finfo)
	ok(ferr < 4, "flight leg settled within " .. ferr .. " m")
	ok(fw9 > 3 * fw, "round 9 on the same flight: " .. fw9 .. finfo9)
end)

-- Round 13: the smooth camera (round 10) and its click glide (round 12) are removed (PLAN.md "Round 13").

test("round 13: replay of the 0434 session's eye spikes 4-5: an uneven frame time is no spike once the eye's step is paired with its frame's dt", function()
	-- "eye spike 4/12 (glide) f=105 d2=3.02" and "5/12 f=106 d2=3.66" (session 2026-10-14_0434_session): the
	-- plans #101-#105 sent, each with the dt of its frame (#104 a 31 ms frame among 15 ms ones). The game's eye
	-- read at frame f shows plan #(f-1) (+ a constant 0.7 m model offset: the spike lines' model eye = the plan of
	-- the frame before). The plain second difference of those eyes spikes at the long frame although the eye is
	-- exactly on its timed path; paired with the dt the step was planned for it doesn't.
	local plan = {
		{ -1295.6, 482.5, 876.4, 0.0159 }, { -1293.9, 485.2, 875.0, 0.0151 }, { -1292.3, 487.7, 873.7, 0.0148 },
		{ -1289.3, 492.5, 871.2, 0.0312 }, { -1288.0, 494.5, 870.1, 0.0141 },
	}
	local m = F.newSmooth()
	local maxD2, maxRaw = 0, 0
	for i = 1, #plan do
		local p = plan[i]
		F.smoothAdd(m, p[1], p[2] + 0.7, p[3] + 0.3, p[4])
		if m.lastD2 ~= nil then
			maxD2 = math.max(maxD2, m.lastD2)
			maxRaw = math.max(maxRaw, m.lastD2Raw)
		end
	end
	ok(maxRaw > 2.5, "the plain second difference spikes like the game's report: " .. maxRaw)
	ok(maxD2 < 0.6, "paired with each step's own dt: " .. maxD2 .. " m (the log's 0.1 m rounding)")
	-- the same eyes paired with the NEXT frame's dt (round 12's metric, the eye read one frame later than sent)
	local m2 = F.newSmooth()
	local max2 = 0
	for i = 1, #plan do
		local p = plan[i]
		F.smoothAdd(m2, p[1], p[2], p[3], plan[i + 1] and plan[i + 1][4] or 0.0153)
		if m2.lastD2 ~= nil then max2 = math.max(max2, m2.lastD2) end
	end
	ok(max2 > 2 * maxD2, "a dt one frame off reads the long frame as a jolt: " .. max2)
	-- even frames: both measures agree
	local m3 = F.newSmooth()
	for i = 0, 10 do F.smoothAdd(m3, i * i * 0.01, 0, 0, 1 / 60) end
	near(m3.lastD2, m3.lastD2Raw, 1e-9)
end)

test("round 12: smoothness: this frame's d2 and the look's second difference (a steady turn is smooth, a jolt is not)", function()
	local m = F.newSmooth()
	-- a steady turn at constant speed: the look's d2 tiny
	for i = 0, 30 do
		local a = i * 0.01
		F.smoothAdd(m, i, 0, 100, 1 / 60, i + 100 * math.cos(a), 100 * math.sin(a), 0)
	end
	ok(m.lastD2 ~= nil and m.lastD2 < 1e-9, "constant velocity: d2 0")
	ok(m.lookMax < 2e-4, "a steady turn: " .. m.lookMax)
	-- one frame looking 0.1 rad off
	F.smoothAdd(m, 31, 0, 100, 1 / 60, 31 + 100 * math.cos(0.41), 100 * math.sin(0.41), 0)
	ok(m.lookMax > 0.05, "the jolt shows: " .. m.lookMax)
	local __, __, __, __, __, __, __, __, lookMax, lookWorst = F.smoothStats(m)
	eq(lookMax, m.lookMax); eq(lookWorst, 32)
	-- no centre: the eye alone, nothing raises
	F.smoothAdd(m, 32, 0, 100, 1 / 60)
	eq(m.lookD2, nil)
end)

test("round 12: over ridges the solver keeps the game's eye on the plan (the camera model as the game): no spike from it", function()
	-- a 32 m/s drone 50-170 m over 80 m ridges, looking flatter than the game can show there (the second search
	-- and the guard at work): with the fitted model as the game, the eye never leaves the plan by a metre, so
	-- the session's 25-56 m eye spikes (2026-10-14_0229) are not the solver's; the "eye spike" report tells
	for _, wl in ipairs({ 60, 120, 300 }) do
		local function ground(x, y) return 150 + 80 * math.sin(x / wl) end
		local st = F.newEye(0)
		local out, worst, d2max, prev, prev2 = {}, 0, 0, nil, nil
		for i = 0, 600 do
			local v = F.solveEye(st, i * 32 / 60, 0, 320, 0, 0.05, 400, 170, ground, 0, i == 0 and 0 or 1 / 60, out)
			local gx, gy, gz = F.eyeOf(v, ground(v.x, v.y), 0)
			worst = math.max(worst, math.sqrt((gx - st.ex) ^ 2 + (gy - st.ey) ^ 2 + (gz - st.ez) ^ 2))
			if prev and prev2 then
				d2max = math.max(d2max, math.sqrt((gx - 2 * prev[1] + prev2[1]) ^ 2 + (gy - 2 * prev[2] + prev2[2]) ^ 2
					+ (gz - 2 * prev[3] + prev2[3]) ^ 2))
			end
			prev2, prev = prev, { gx, gy, gz }
		end
		ok(worst < 1, "ridges every " .. wl .. " m: eye off the plan by " .. worst)
		ok(d2max < 0.5, "ridges every " .. wl .. " m: eye d2 " .. d2max)
	end
end)

-- Round 13b: the Aerials tour of session 2026-10-14_0606_session (`tour on mode=aerial` 06:08:12, the glide up
-- from a road vehicle at -29,985 d=40): "eye spike" reports 1-4 at frames 66-70, the solver ring #62-#69. Each
-- line: dt, plan eye, view sent (x, y, d, angle, pitch), getHeightAt under its centre (g). The camera's look
-- heading = angle + 3.142 (`look calibrated`). The game's centre for the views #65 / #66 / #68 / #69 read 3.0 /
-- 2.8 / 0.0 / 0.0 m above the model's (getHeightAt + 4); #67's was not read (frame 68 reported nothing): 2.2 m
-- from frame 69's d2 (|0 - 2 o67 + 2.8| = 1.62).
local TOUR_0606 = {
	{ 0.0188, -11.3, 944.8, 71.3, -45.8, 1046.5, 119.3, -1.244, 0.207, 15.4, 0 },
	{ 0.0189, -11.1, 944.5, 72.6, -46.3, 1048.6, 122.1, -1.245, 0.205, 15.5, 0 },
	{ 0.0185, -10.9, 944.2, 73.9, -46.4, 1049.5, 123.2, -1.245, 0.201, 16.6, 0 },
	{ 0.0206, -10.6, 943.9, 75.3, -47.2, 1052.4, 126.9, -1.246, 0.198, 16.5, 3.0 },
	{ 0.0184, -10.4, 943.7, 76.6, -47.3, 1053.4, 128.2, -1.247, 0.196, 17.3, 2.8 },
	{ 0.0171, -10.2, 943.4, 77.8, -47.4, 1054.3, 129.5, -1.247, 0.193, 18.2, 2.2 },
	{ 0.0182, -10.0, 943.1, 79.1, -47.5, 1055.2, 130.8, -1.248, 0.191, 19.1, 0 },
	{ 0.0182, -9.7, 942.9, 80.5, -47.6, 1056.2, 132.2, -1.248, 0.189, 20.0, 0 },
}
local OFF_0606 = 3.142

test("round 13b: replay of the 0606 session's tour spikes 1-4: the sent views put the eye on the plan; the game's centre 3 m off for three frames jolted it", function()
	-- (b) the sent views stepped unevenly (centre +2.1, +0.9, +2.9, +1.0 m; distance +2.8, +1.1, +3.7, +1.3 m: the
	-- look meeting a slope that steepens), yet the camera model puts every one of them on its planned eye
	local mModel, mGame = F.newSmooth(), F.newSmooth()
	local worstPlan, gameD2 = 0, {}
	for i, r in ipairs(TOUR_0606) do
		local v = view(r[5], r[6], r[7], r[8], r[9])
		local x, y, z = F.eyeOf(v, r[10], OFF_0606)
		worstPlan = math.max(worstPlan, math.sqrt((x - r[2]) ^ 2 + (y - r[3]) ^ 2 + (z - r[4]) ^ 2))
		F.smoothAdd(mModel, x, y, z, r[1])
		-- (a) the game: the same eye lifted by its centre's offset (the spike lines: eye and centre both ~3 m up)
		F.smoothAdd(mGame, x, y, z + r[11], r[1])
		gameD2[i] = mGame.lastD2
	end
	ok(worstPlan < 0.35, "every sent view's model eye on its plan (the log's rounding): " .. worstPlan)
	ok(mModel.d2Max < 0.4, "the planned eye path is smooth: d2 " .. mModel.d2Max)
	-- the game's eye reproduces the reports: 2.87 (#65), 3.04 (#66), < 1.5 (#67), 1.62 (#68), 2.27 (#69)
	near(gameD2[4], 2.87, 0.45); near(gameD2[5], 3.04, 0.45); ok(gameD2[6] < 1.5, "frame 68: " .. gameD2[6])
	near(gameD2[7], 1.62, 0.45); near(gameD2[8], 2.27, 0.45)
	-- (c) correcting with the offset read (it shows the view sent the frame BEFORE): the eye then carries
	-- o(i) - o(i-1), and the jolt doubles (6.2 m against 3.2 m)
	local mFb = F.newSmooth()
	for i, r in ipairs(TOUR_0606) do
		local x, y, z = F.eyeOf(view(r[5], r[6], r[7], r[8], r[9]), r[10], OFF_0606)
		local prev = i > 1 and TOUR_0606[i - 1][11] or 0
		F.smoothAdd(mFb, x, y, z + r[11] - prev, r[1])
	end
	print(string.format("0606 replay: plan %.2f m off, model eye d2 %.2f, game %.2f / %.2f / %.2f / %.2f / %.2f, feedback %.2f",
		worstPlan, mModel.d2Max, gameD2[4], gameD2[5], gameD2[6], gameD2[7], gameD2[8], mFb.d2Max))
	ok(mFb.d2Max > 1.6 * mGame.d2Max, "feedback a frame late: " .. mFb.d2Max .. " vs " .. mGame.d2Max)
end)

test("round 13b: the High look over the 0606 ground and its 3 m jolt: the game's centre stays at sea level, the eye smooth; the Drone look jolts", function()
	-- the logged ground along the centre's path (g by y), flat below, rising 0.9 m / m above; the jolt: 2.2-3.0 m
	-- more under the centre for y 1051-1054.8 (what the game showed; getHeightAt doesn't)
	local prof = { { 1040, 15.4 }, { 1048.6, 15.5 }, { 1049.5, 16.6 }, { 1052.4, 16.5 }, { 1053.4, 17.3 },
		{ 1054.3, 18.2 }, { 1055.2, 19.1 }, { 1056.2, 20.0 }, { 1100, 59.6 } }
	local function ground(x, y)
		if y <= prof[1][1] then return prof[1][2] end
		for i = 2, #prof do
			if y <= prof[i][1] then
				local a, b = prof[i - 1], prof[i]
				return a[2] + (b[2] - a[2]) * (y - a[1]) / (b[1] - a[1])
			end
		end
		return prof[#prof][2]
	end
	local function jolt(x, y)
		if x < -70 or x > -25 or y < 1051 or y > 1054.8 then return 0 end
		return y < 1053.9 and 3.0 or 2.2
	end
	-- the game: its centre over getHeightAt + jolt (lowered with the distance like the ground: inferred)
	local function run(pose, frames)
		local st, out = F.newEye(0), {}
		local m = F.newSmooth()
		local dMin, czMax, czMin, joltSeen = math.huge, -math.huge, math.huge, false
		for i = 0, frames do
			local dt = i == 0 and 0 or 1 / 60
			local ex, ey, ez, h, e, hPlan = pose(i / 60)
			local v = F.solveEye(st, ex, ey, ez, h, e, nil, hPlan, ground, 0, dt, out)
			local j = jolt(v.x, v.y)
			if j > 0 then joltSeen = true end
			local gx, gy, gz = F.eyeOf(v, ground(v.x, v.y) + j, 0)
			local cz = F.centreZ(ground(v.x, v.y) + j, v.d)
			czMax, czMin = math.max(czMax, cz), math.min(czMin, cz)
			dMin = math.min(dMin, v.d)
			F.smoothAdd(m, gx, gy, gz, dt)
		end
		return m.d2Max, dMin, czMin, czMax, joltSeen
	end
	-- the Drone look as logged: the eye climbing ~70 m/s from #65's plan, the look (heading, elevation) of #65
	local r = TOUR_0606[4]
	local h = cam.lookOf(r[8], OFF_0606)
	local e = F.gameElev(r[9], r[7])
	local function drone(t)
		local tt = t - 0.3
		return r[2] + 13 * tt, r[3] - 16 * tt, r[4] + 70 * tt, h, e, r[4] + 70 * tt - r[10]
	end
	local dD2, dDmin, __, __, dSeen = run(drone, 36)
	ok(dSeen, "the Drone's look-at point crossed the jolt")
	ok(dD2 > 2.5, "the Drone look jolts by the game's centre: d2 " .. dD2 .. " m (the log: 2.87-3.04)")
	-- the High look flying over the same place (its look-at point 1.3 km ahead crosses the jolt): the eye on
	-- the sea-level centre's ray, 1.6 km+ out
	local H = F.HIGH
	local ez0, d0 = F.highPose(15, 0, 0)
	local Lc = d0 * math.cos(H.elev)
	local hx, hy = math.cos(h), math.sin(h)
	local function high(t)
		-- the eye at 32 m/s along the look heading; its look-at point from 20 m before the logged centre on
		local ez = F.highPose(15, t, 0)
		local s = -20 + 32 * t
		return -47.2 + hx * (s - Lc), 1052.4 + hy * (s - Lc), ez, h, H.elev, ez - F.CAM.lift
	end
	local hD2, hDmin, czMin, czMax, hSeen = run(high, 120)
	print(string.format("0606 replay: Drone d2 %.2f m (d >= %.0f), High d2 %.3f m (d >= %.0f, eye %.0f m up)",
		dD2, dDmin, hD2, hDmin, ez0))
	ok(hSeen, "the High look's centre crossed the jolt too")
	ok(hDmin >= H.dMin - 1, "High: the look-at point at least " .. H.dMin .. " m out: " .. hDmin)
	near(czMin, F.CAM.lift, 1e-9); near(czMax, F.CAM.lift, 1e-9, "the game's centre at sea level throughout")
	ok(hD2 < 0.5, "High: eye d2 " .. hD2 .. " m over the jolt (Drone " .. dD2 .. ")")
	ok(ez0 > 900 and ez0 < 1150, "about 1 km up: " .. ez0)
end)

test("round 13b: highPose: the sea-level centre's ray, never closer than dMin, lifted over high ground", function()
	local H, C = F.HIGH, F.CAM
	for t = 0, 140, 3.5 do
		local ez, d = F.highPose(100, t, 0.3)
		ok(d >= H.dMin, "distance " .. d)
		near(ez, C.lift + d * math.sin(H.elev), 1e-9, "on the ray to the sea-level centre")
		-- the game can show that elevation at that distance with a pitch >= 0
		ok(F.pitchFor(H.elev, d) > 0.03, "showable: pitch " .. F.pitchFor(H.elev, d))
		ok(F.centreKeep(d) == 0, "the game's centre keeps no ground at " .. d)
	end
	local ez, d = F.highPose(1200, 0, 0)
	ok(ez >= 1200 + H.clear - 1e-9, "over a 1200 m mountain: " .. ez)
	near(ez, C.lift + d * math.sin(H.elev), 1e-9)
	ok(d <= cam.ZOOM_LIMIT, "still within the zoom limit: " .. d)
	ok(F.pitchFor(H.elev, d) > 0, "showable there too: " .. F.pitchFor(H.elev, d))
end)

-- Round 14: the 10 eye spike reports of session 2026-10-14_0633_session (two Aerials tours with the High look,
-- then Down): { report, d2, raw, eye z, model eye z, centre z, model centre z, read-sent dx, g of the 4 frames }.
local SPIKES_0633 = {
	{ 1, 2.24, 32.22, 1726.0, 1728.5, 4.0, 4.0, 0.0, { 144.9, 197.3, 191.7, 128.8 } },
	{ 2, 3.67, 3.43, 1008.4, 1008.3, 4.0, 4.0, 3.4, { 7.3, 7.3, 7.3, 7.3 } },
	{ 3, 4.78, 4.79, 294.4, 288.2, 99.9, 93.9, 0.0, { 101.8, 99.3, 97.2, 89.9 } },
	{ 4, 5.46, 13.42, 215.7, 207.4, 12.4, 4.0, 0.0, { -8.2, -13.3, -17.0, -12.5 } },
	{ 5, 1.51, 1.45, 652.5, 651.2, 7.5, 7.5, 0.0, { 8.0, 8.9, 11.5, 11.5 } },
	{ 6, 3.43, 3.41, 265.1, 261.8, 26.9, 23.5, 0.0, { 29.4, 27.5, 25.7, 19.5 } },
	{ 7, 1.75, 3.69, 627.2, 626.3, 197.2, 195.6, 0.0, { 204.8, 206.2, 207.0, 194.0 } },
	{ 8, 1.61, 1.59, 292.1, 290.5, 146.7, 145.1, 0.0, { 143.9, 143.3, 142.3, 141.1 } },
	{ 9, 1.61, 1.62, 310.3, 307.6, 139.2, 136.6, 0.0, { 134.4, 133.4, 132.8, 132.6 } },
	{ 10, 4.00, 4.02, 364.0, 360.1, 144.0, 140.0, 0.0, { 141.7, 141.3, 140.7, 136.0 } },
}

test("round 14: the 0633 spike reports, classified: the game's centre off the model moves the eye by as much; a pan; a long frame; a model residual", function()
	local kinds = {}
	for __, r in ipairs(SPIKES_0633) do
		local n, d2, raw, ez, mz, cz, mcz, rs, g = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
		local eyeOff, centreOff = ez - mz, cz - mcz
		local kind
		if math.abs(rs) > 1 then
			kind = "input" -- the view read differs from the one sent: the player's pan (the tour ended on it)
		elseif raw > 3 * d2 then
			kind = "frame time" -- the plain second difference only (a long frame)
		elseif math.abs(centreOff) > 1 then
			kind = "centre"
			-- (report 7 at d 846 m: 0.9 of 1.6 m; the rest within 0.4 m)
			near(eyeOff, centreOff, 0.75, "report " .. n .. ": the eye lifted with the game's centre")
		else
			kind = "residual"
			ok(math.abs(eyeOff) < 1.5, "report " .. n .. ": the eye 1-1.5 m off at 1.6 km (the model's residual)")
		end
		kinds[n] = kind
	end
	eq(kinds, { "frame time", "input", "centre", "centre", "residual", "centre", "centre", "centre", "centre",
		"centre" })
	-- report 4 (a long frame too: raw 13.4 m): its centre sat 8.4 m above the water rule (g -12.5: a river, the
	-- model's max(g, 0) + 4 = 4.0; the game 12.4): the eye 8.3 m up
	near(SPIKES_0633[4][4] - SPIKES_0633[4][5], SPIKES_0633[4][6] - SPIKES_0633[4][7], 0.2)
	-- the Down reports with the centre off: on ground falling under the centre (a terrace / cut edge: up to 13 m
	-- in one frame) or sloping steadily (8, 9), always ABOVE the model: never a lower centre
	for __, i in ipairs({ 3, 6, 7, 8, 9, 10 }) do
		local r = SPIKES_0633[i]
		ok(r[6] - r[7] > 1.5, "above the model: report " .. i)
		ok(r[9][1] - r[9][4] > 1.5, "the ground under the centre falling over the 4 frames: report " .. i)
	end
end)

---------------------------------------------------------------------------
-- Round 16: Aerials keeps its view on the map (user screenshot: the void past the map edge) and avoids the areas
-- it showed lately ("Now Aerials always shows the same place")

test("round 16: the inner bounds keep the look's edge margin (at most 30 % of the map a side, never less than the inset)", function()
	local b = { -8000, -8000, 8000, 8000 }
	eq(F.inner(b), { -8000 + 16000 * 0.12, -8000 + 16000 * 0.12, 8000 - 16000 * 0.12, 8000 - 16000 * 0.12 }, "no margin: the inset")
	local ib = F.inner(b, F.viewMargin("high"))
	eq(ib, { -5500, -5500, 5500, 5500 }, "High: 2.5 km from every edge")
	eq(F.inner(b, F.viewMargin("down")), F.inner(b), "Down's 900 m is under the 12 % inset here")
	eq(F.viewMargin("nonsense"), F.VIEW_MARGIN.down)
	local small = F.inner({ 0, 0, 4000, 6000 }, 2500)
	eq(small, { 1200, 1800, 2800, 4200 }, "a small map keeps 40 % in the middle")
	eq(F.inner(b, 0 / 0), F.inner(b), "NaN margin: none")
	-- every waypoint of a long flight keeps the margin
	local rnd = cam.newRng(5)
	local last, heading = { x = 5000, y = 0 }, 0
	for __ = 1, 100 do
		local wp = F.nextWaypoint(last, heading, {}, b, rnd, F.viewMargin("high"))
		ok(wp.x >= -5500 - 1e-6 and wp.x <= 5500 + 1e-6 and wp.y >= -5500 - 1e-6 and wp.y <= 5500 + 1e-6,
			"inside the margin: " .. wp.x .. "," .. wp.y)
		heading, last = cam.atan2(wp.y - last.y, wp.x - last.x), wp
	end
end)

test("round 16: the recent areas: a ring of 16, near = within 1.5 km; waypoints near one weigh a third", function()
	eq(F.nearRecent(0, 0), false)
	F.rememberArea(1000, 1000)
	ok(F.nearRecent(1000, 2400))
	ok(not F.nearRecent(1000, 2600))
	eq(F.recentCount(), 1)
	F.rememberArea(0 / 0, 0)
	eq(F.recentCount(), 1, "NaN ignored")
	for i = 1, 16 do F.rememberArea(10000 * i, 0) end
	eq(F.recentCount(), 16, "a ring")
	ok(not F.nearRecent(1000, 1000), "the oldest forgotten")
	F.clearRecent()
	eq(F.recentCount(), 0)
	-- two candidates ahead, the heavier one shown lately: the other wins most of the time
	F.rememberArea(2500, 0)
	local rnd = cam.newRng(9)
	local fresh = 0
	for __ = 1, 50 do
		local wp = F.nextWaypoint({ x = 0, y = 0 }, 0, { { x = 2500, y = 0, w = 1.5, why = "old" },
			{ x = 2400, y = 1800, w = 1, why = "new" } }, { -8000, -8000, 8000, 8000 }, rnd)
		if wp.why == "new" then fresh = fresh + 1 end
	end
	ok(fresh >= 30, "the fresh one: " .. fresh .. " of 50")
end)
