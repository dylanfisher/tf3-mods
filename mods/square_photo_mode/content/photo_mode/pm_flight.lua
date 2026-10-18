-- Photo Mode: the tour's motion, the pure part (no api calls). Shared by gui/pm_driver.lua and the offline
-- tests (tests/square_photo_mode/test_flight.lua). Plain Lua, pre-5.3. PLAN: plans/square_photo_mode/PLAN.md
-- "Tour motion (rev 1 feedback round 2)".
--
--   hop     a glide from one place to the next, then a hold. With the Ken Burns drift on, the drift runs as a
--           steady motion (rates per second, KB_RATES) whose speed ramps in during the glide's last RAMP_S
--           seconds and ramps out during the next glide's first RAMP_S seconds: the glide interpolates between
--           two MOVING end points (the old place still drifting out, the new one drifting in), so the camera's
--           velocity is continuous at both ends of the glide (the smoothstep's zero end slopes leave exactly the
--           end points' own velocities). The hold timer starts on arrival (glide over), not at the hop start.
--   flight  "Aerials": a drone flight along a Catmull-Rom spline through waypoints (smooth heading changes),
--           at a steady speed that ramps in from rest. The eye flies at an altitude above the terrain under it and
--           looks at a point further along the path. Round 11: the glide into a flight already moves with it (the
--           flight's clock starts with the glide) and a leg no longer ramps out to rest: the next glide leaves the
--           still flying drone (moving hop ends, F.newHop), so the speed never drops between legs.
--
-- Views are { x, y, d, a, p } as in pm_cam.lua; the drift rates and flight produce views through pm_cam helpers.

local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"

local F = {}

local finite, clamp = cam.finite, cam.clamp

-- Ramp time of the drift's speed (in and out) and of a flight's speed.
F.RAMP_S = 2.0
-- Round 11: the flight's ramp runs during the glide onto it (the drone's clock starts with the glide), as long as
-- the glide: the camera lands on the drone as it reaches cruise (was 6 s from rest after the glide had stopped).
F.FLIGHT_RAMP_S = cam.GLIDE_SECONDS

---------------------------------------------------------------------------
-- Speed ramps: distance travelled at unit top speed when the speed follows a smoothstep from 0 to 1 over
-- `ramp` seconds (rampIn) or from 1 to 0 (rampOut). Both are C1 (the speed is continuous) and reach ramp / 2
-- at the end of the ramp; rampIn then grows by 1 per second.

function F.rampIn(t, ramp)
	t = tonumber(t) or 0
	if t <= 0 then return 0 end
	if not finite(ramp) or ramp <= 0 then return t end
	if t >= ramp then return ramp / 2 + (t - ramp) end
	local u = t / ramp
	return ramp * (u * u * u - u * u * u * u / 2)
end

function F.rampOut(t, ramp)
	t = tonumber(t) or 0
	if t <= 0 then return 0 end
	if not finite(ramp) or ramp <= 0 then return 0 end
	if t >= ramp then return ramp / 2 end
	local u = t / ramp
	return t - ramp * (u * u * u - u * u * u * u / 2)
end

---------------------------------------------------------------------------
-- Ken Burns drift as rates (round 7, user feedback 2026-10-13: "random speed per shot with more variance",
-- "moves on the vertical axis too, not mostly orbit"). Each shot draws one main move and small amounts of the
-- others, a random sign each, and a pace of KB.speedMin .. KB.speedMax times the base amounts (the round 2 pace is
-- the slowest end):
--   push      dolly in or out along the look (zoom: log distance per s; the centre stays)
--   truck     slide sideways across the look (side: fraction of the distance per s)
--   pedestal  the eye rises or falls (rise: fraction of the distance per s on the view's reference ground `g`, so
--             the eye moves straight up), with a little tilt that keeps the subject in frame (KB.tiltFollow)
--   orbit     a slight turn around the centre (da: rad/s)
--   tilt      the pitch drifts (dp: rad/s; the eye swings on its arc around the centre)
-- The amounts are totals over REF_S seconds at pace 1. Planned in view space with a reference ground (pm_cam's
-- view + g), so the eye path never follows the terrain under the centre ("Eye space" below).

F.KB = {
	push = math.log(1.12), truck = 0.15, pedestal = 0.12, orbit = 0.08, tilt = 0.05, -- per refS at pace 1
	refS = 10, pMin = 0.02, minor = 0.35, speedMin = 1.0, speedMax = 2.5, tiltFollow = 0.6,
}
-- How often each move is the main one (weights).
F.KB_MOVES = { { "push", 0.28 }, { "truck", 0.24 }, { "pedestal", 0.26 }, { "orbit", 0.11 }, { "tilt", 0.11 } }

--- Random drift rates for one shot (rnd: 0..1 function; 12 draws); scale shrinks them (saved views: 0.5).
--- Returns { da (rad/s), dp (rad/s), side (fraction of the distance per s), zoom (log distance per s), rise
--- (fraction of the distance per s), off (the look offset, pm_cam.angleFor: the slide goes across the view),
--- move (the main move), speed (the pace) }.
function F.kbRates(rnd, scale, off)
	local k = F.KB
	scale = clamp(tonumber(scale) or 1, 0, 1)
	local total = 0
	for __, mw in ipairs(F.KB_MOVES) do total = total + mw[2] end
	local r, main = rnd() * total, F.KB_MOVES[#F.KB_MOVES][1]
	for __, mw in ipairs(F.KB_MOVES) do
		r = r - mw[2]
		if r < 0 then main = mw[1] break end
	end
	local speed = k.speedMin + (k.speedMax - k.speedMin) * rnd()
	local f = speed * scale / k.refS
	local function amount(move)
		local w = move == main and 1 or k.minor * rnd()
		return (rnd() < 0.5 and -1 or 1) * w * k[move] * f
	end
	local rise = amount("pedestal")
	return {
		zoom = amount("push"),
		side = amount("truck"),
		rise = rise,
		da = amount("orbit"),
		dp = amount("tilt") + k.tiltFollow * rise,
		off = tonumber(off) or 0,
		move = main,
		speed = speed,
	}
end

--- The view after s seconds (of drift at full speed) around `base`. Linear in s, so a ramped s gives a ramped
--- velocity. The pitch stays within KB.pMin .. SAFE.pMax and within the base's range bounds (lo, hi optional).
--- The reference ground g (base.g) rises with the pedestal move.
function F.kbView(base, r, s, out, lo, hi)
	local v = out or {}
	s = tonumber(s) or 0
	if r == nil or s == 0 then
		v.x, v.y, v.d, v.a, v.p, v.g = base.x, base.y, base.d, base.a, base.p, base.g
		return v
	end
	-- sideways: across the direction the camera looks (look = angle + r.off, the measured look offset)
	local off = (r.side or 0) * base.d * s
	local look = base.a + (r.off or 0)
	v.x = base.x - math.sin(look) * off
	v.y = base.y + math.cos(look) * off
	v.d = base.d * math.exp((r.zoom or 0) * s)
	v.a = cam.wrapAngle(base.a + (r.da or 0) * s)
	-- never outside the range, but a base already outside it (a photographer's shot) is not pulled in
	local pLo = math.min(base.p, math.max(F.KB.pMin, lo or 0))
	local pHi = math.max(base.p, math.min(cam.SAFE.pMax, hi or cam.SAFE.pMax))
	v.p = clamp(base.p + (r.dp or 0) * s, pLo, pHi)
	v.g = base.g ~= nil and base.g + (r.rise or 0) * base.d * s or nil
	return v
end

---------------------------------------------------------------------------
-- Hops

--- A hop from `from` (a static view, or { base, rates, s0 } still drifting out: s0 = its drift seconds when
--- the hop began) to `to` ({ base, rates } or a static view), gliding G seconds, then holding H seconds.
--- rates nil = no drift (Ken Burns off). bump: the glide's mid-way rise (pm_cam.glideBump).
--- Round 11: an end may also be a moving view of its own, { viewAt = function(tau, out) -> view or nil, plus the
--- static x, y, d, a, p, g of its start } (an Aerials flight: the driver evaluates it, the hop only blends), and
--- quintic = true glides with the smootherstep (pm_cam.ease5): the camera leaves and arrives with the end points'
--- own velocity and no jump in acceleration (user, round 11: "ease in and out of the aerial speed so it doesn't
--- slow down between"). A hop with a moving end runs in eye space (elev = true): its views are eye-centre
--- elevations (a flight's own), the other end converted exactly (F.elevView: the same eye), so the hand-over to
--- or from the flight sends the very eye the flight does (the game's-pitch form of a flight view, F.gameView, is
--- only "about" the same eye: a pitch below 0 is kept at 0; a ~10 m step in the round 11 test).
function F.newHop(from, to, G, H, bump, quintic)
	local elev = (from ~= nil and from.viewAt ~= nil) or (to ~= nil and to.viewAt ~= nil)
	return { from = from, to = to, G = G, H = H, bump = bump or 0, arrivedAt = nil, quintic = quintic == true,
		elev = elev }
end

local fromBuf, toBuf = {}, {}

--- The drift seconds of the arriving place at time tau (s) after the hop began: 0 until RAMP_S before the end of
--- the glide, then ramping in.
function F.driftIn(tau, G)
	local R = math.min(F.RAMP_S, G)
	return F.rampIn(tau - (G - R), R)
end

--- The drift seconds of the place being left, tau s after the hop began: its s0 plus a ramp out.
function F.driftOut(s0, tau, G)
	local R = math.min(F.RAMP_S, G)
	return (s0 or 0) + F.rampOut(tau, R)
end

local function endView(e, s, out, lo, hi)
	if e.base ~= nil then return F.kbView(e.base, e.rates, s, out, lo, hi) end
	out.x, out.y, out.d, out.a, out.p, out.g = e.x, e.y, e.d, e.a, e.p, e.g
	return out
end

--- A view in the game's pitch over terrain g turned in place into its eye-centre elevation over the centre
--- height (exactly F.elevView: the same eye).
local function elevInPlace(v, res)
	v.p, v.g = F.gameElev(v.p, v.d, res), F.centreZ(v.g or 0, v.d)
	return v
end

--- The view tau seconds after the hop began, written into `out`. Before G: the glide between the moving end
--- points; after: the arriving place's drift. lo / hi: pitch bounds of the drift (the tour's range). An eye-space
--- hop (hop.elev, round 11) gives elevation views (res: the camera model's residual for the conversion).
function F.hopView(hop, tau, out, lo, hi, res)
	out = out or {}
	tau = math.max(0, tonumber(tau) or 0)
	local G = hop.G
	local to = hop.to.viewAt ~= nil and hop.to.viewAt(tau, toBuf) or nil
	if to == nil then
		to = endView(hop.to, F.driftIn(tau, G), toBuf, lo, hi)
		if hop.elev then elevInPlace(to, res) end
	end
	if tau >= G then
		out.x, out.y, out.d, out.a, out.p, out.g = to.x, to.y, to.d, to.a, to.p, to.g
		return out
	end
	local from = hop.from.viewAt ~= nil and hop.from.viewAt(tau, fromBuf) or nil
	if from == nil then
		from = endView(hop.from, F.driftOut(hop.from.s0, tau, G), fromBuf, lo, hi)
		if hop.elev then elevInPlace(from, res) end
	end
	return cam.lerpView(from, to, tau / G, hop.bump, out, hop.quintic)
end

--- The drift state the next hop starts from, when this hop ends at tau: { base, rates, s0 }; a static view when
--- the arriving place has no drift.
function F.leaving(hop, tau)
	local to = hop.to
	if to.base == nil then return to end
	return { base = to.base, rates = to.rates, s0 = F.driftIn(tau, hop.G) }
end

---------------------------------------------------------------------------
-- Flight (Aerials)

F.FLY = {
	speed = 32,          -- m/s (about 115 km/h), a slow drone
	alt = 220,           -- m above the terrain under the eye, on average
	altAmp = 70,         -- slow altitude change, +- m
	altPeriod = 70,      -- s
	lookAhead = 420,     -- m along the path to the point the camera looks at
	pMin = 0.12, pMax = 0.9,
	legMin = 1500, legMax = 4000, -- m between waypoints
	maxTurn = 1.2,       -- rad: waypoints needing a sharper turn are avoided
	inset = 0.12,        -- fraction of the map kept free at each edge
	smooth = 1.5,        -- s: time constant of the height smoothing
	groundAhead = 150,   -- m: the altitude follows the ground this far ahead of the eye (climbs before a hill)
	leg = 30,            -- s: a Mixed tour's flight leg
}

local function cr(a, b, c, d, t, t2, t3)
	return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
end

local function dcr(a, b, c, d, t, t2)
	return 0.5 * ((-a + c) + 2 * (2 * a - 5 * b + 4 * c - d) * t + 3 * (-a + 3 * b - 3 * c + d) * t2)
end

--- Catmull-Rom point and tangent at t (0..1) between p1 and p2 (p0, p3 the neighbours). No allocation (runs
--- every frame of a flight).
function F.catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return cr(p0.x, p1.x, p2.x, p3.x, t, t2, t3), cr(p0.y, p1.y, p2.y, p3.y, t, t2, t3),
		dcr(p0.x, p1.x, p2.x, p3.x, t, t2), dcr(p0.y, p1.y, p2.y, p3.y, t, t2)
end

--- The point `dist` m along the waypoint path { {x, y}, ... } (segment lengths approximated by chords; the
--- ends repeat their own point as the outer neighbour). Returns x, y, unit heading hx, hy and the segment index;
--- past the end: the last point and the last heading (and the index #path).
function F.pathPoint(path, dist)
	local n = path and #path or 0
	if n == 0 then return nil end
	if n == 1 then return path[1].x, path[1].y, 1, 0, 1 end
	dist = math.max(0, tonumber(dist) or 0)
	for i = 1, n - 1 do
		local a, b = path[i], path[i + 1]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		if dist <= len or i == n - 1 then
			local t = len > 0 and clamp(dist / len, 0, 1) or 1
			local x, y, tx, ty = F.catmull(path[math.max(1, i - 1)], a, b, path[math.min(n, i + 2)], t)
			local tl = math.sqrt(tx * tx + ty * ty)
			if tl <= 1e-9 then tx, ty, tl = b.x - a.x, b.y - a.y, len end
			if tl <= 0 then tx, ty, tl = 1, 0, 1 end
			return x, y, tx / tl, ty / tl, i
		end
		dist = dist - len
	end
end

--- Total chord length of a path.
function F.pathLength(path)
	local s = 0
	for i = 1, (path and #path or 0) - 1 do
		s = s + math.sqrt((path[i + 1].x - path[i].x) ^ 2 + (path[i + 1].y - path[i].y) ^ 2)
	end
	return s
end

-- Round 16 (user screenshot: an Aerials view at the map edge looking out over the void past the terrain): a
-- drone's path keeps this far (m) from every edge, by look: the eye looks ahead along the path and the picture
-- reaches well past the point it looks at (High: the look-at point ~1.6 km out, the frame's top near the
-- horizon; Down: ~0.4 km ahead, steeper). At most VIEW_SHARE of the map's width / height each side, so a small
-- map keeps a middle to fly in (its edge may then show far off); never less than FLY.inset.
F.VIEW_MARGIN = { high = 2500, horizon = 2500, down = 900 }
F.VIEW_SHARE = 0.3

--- The edge margin (m) of an Aerials look (pm_cam aerial looks; unknown: Down's).
function F.viewMargin(look)
	return F.VIEW_MARGIN[look] or F.VIEW_MARGIN.down
end

--- Map bounds shrunk at each side by FLY.inset of the map or, larger, `margin` m (at most VIEW_SHARE of the map)
--- ({ minX, minY, maxX, maxY }), or nil.
function F.inner(bounds, margin)
	if bounds == nil then return nil end
	local w, h = bounds[3] - bounds[1], bounds[4] - bounds[2]
	local i = F.FLY.inset
	local m = math.max(0, tonumber(margin) or 0)
	if m ~= m then m = 0 end
	local mx = math.max(w * i, math.min(m, w * F.VIEW_SHARE))
	local my = math.max(h * i, math.min(m, h * F.VIEW_SHARE))
	return { bounds[1] + mx, bounds[2] + my, bounds[3] - mx, bounds[4] - my }
end

-- Round 16 (user: "Now Aerials always shows the same place"): the areas Aerials showed lately (new areas,
-- waypoints, the cutscene flights' middles), kept for the game session (this module's state in the GUI Lua
-- state): candidates near one of them are picked less (the tour) or skipped while others exist (the cutscene).
F.RECENT = { n = 16, r = 1500 }
local recentAreas, recentNext = {}, 1

--- Remembers (x, y) as a recently shown area (a ring of RECENT.n).
function F.rememberArea(x, y)
	if not (finite(x) and finite(y)) then return end
	recentAreas[recentNext] = { x = x, y = y }
	recentNext = recentNext % F.RECENT.n + 1
end

--- True when (x, y) lies within r (default RECENT.r) of a recently shown area.
function F.nearRecent(x, y, r)
	if not (finite(x) and finite(y)) then return false end
	r = tonumber(r) or F.RECENT.r
	for __, a in pairs(recentAreas) do
		if (a.x - x) ^ 2 + (a.y - y) ^ 2 <= r * r then return true end
	end
	return false
end

--- How many areas are remembered (for the log).
function F.recentCount()
	local n = 0
	for __ in pairs(recentAreas) do n = n + 1 end
	return n
end

--- Forgets them (a new game).
function F.clearRecent()
	recentAreas, recentNext = {}, 1
end

local function inside(b, x, y)
	return b == nil or (x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4])
end
F.inside = inside

--- The next waypoint after `last` flying along `heading`: the best candidate ({ x, y, w = weight }) within
--- legMin .. legMax and a turn below maxTurn inside the inner map bounds, weighted by w and by a gentle turn;
--- else a made-up point legMid ahead, turned by a random +-0.5 rad, turned towards the map centre until it is
--- inside the bounds. Always returns a point inside the inner bounds (when bounds are known). Round 16: margin:
--- the look's edge margin (F.inner; F.viewMargin); a candidate near a recently shown area weighs a third.
function F.nextWaypoint(last, heading, candidates, bounds, rnd, margin)
	local fly = F.FLY
	local ib = F.inner(bounds, margin)
	local best, bestScore = nil, nil
	for __, c in ipairs(candidates or {}) do
		if finite(c.x) and finite(c.y) and inside(ib, c.x, c.y) then
			local dx, dy = c.x - last.x, c.y - last.y
			local dist = math.sqrt(dx * dx + dy * dy)
			local turn = math.abs(cam.angleDiff(heading, cam.atan2(dy, dx)))
			if dist >= fly.legMin and dist <= fly.legMax and turn <= fly.maxTurn then
				local score = (tonumber(c.w) or 1) * (1 - turn / (fly.maxTurn * 1.5)) * (0.5 + rnd())
					* (F.nearRecent(c.x, c.y) and 0.33 or 1)
				if bestScore == nil or score > bestScore then best, bestScore = c, score end
			end
		end
	end
	if best ~= nil then return { x = best.x, y = best.y, why = best.why } end
	local legMid = (fly.legMin + fly.legMax) / 2
	local h = heading + (rnd() - 0.5)
	local cx = ib and (ib[1] + ib[3]) / 2 or last.x
	local cy = ib and (ib[2] + ib[4]) / 2 or last.y
	for __ = 1, 16 do
		local x, y = last.x + math.cos(h) * legMid, last.y + math.sin(h) * legMid
		if inside(ib, x, y) then return { x = x, y = y, why = "ahead" } end
		-- turn a step towards the map centre
		local toC = cam.atan2(cy - last.y, cx - last.x)
		h = h + clamp(cam.angleDiff(h, toC), -0.4, 0.4)
	end
	-- still outside (a tiny map): the clamped point
	return { x = clamp(last.x + math.cos(h) * legMid, ib[1], ib[3]), y = clamp(last.y + math.sin(h) * legMid, ib[2], ib[4]),
		why = "clamped" }
end

--- Target altitude above the terrain at flight time t (s): a slow sine around FLY.alt.
function F.altitude(t, phase)
	local fly = F.FLY
	return fly.alt + fly.altAmp * math.sin(2 * math.pi * ((tonumber(t) or 0) / fly.altPeriod + (phase or 0)))
end

--- The camera view of a drone with its eye at (ex, ey), `h` m above the ground under the centre, looking at the
--- ground point (cx, cy): distance and pitch from the horizontal and vertical offsets; `lookOffset` turns the
--- world heading into the camera angle (pm_cam.angleFor). pMin: the lowest pitch (default FLY.pMin). Returns a
--- new view or writes `out`.
function F.droneView(ex, ey, cx, cy, h, lookOffset, out, pMin)
	local fly = F.FLY
	local dx, dy = cx - ex, cy - ey
	local L = math.max(1, math.sqrt(dx * dx + dy * dy))
	local p = clamp(cam.atan2(h, L), pMin or fly.pMin, fly.pMax)
	local v = out or {}
	v.x, v.y = cx, cy
	v.d = math.sqrt(L * L + h * h)
	v.a = cam.angleFor(cam.atan2(dy, dx), lookOffset)
	v.p = p
	return v
end

---------------------------------------------------------------------------
-- Horizon look (Aerials "Look: Horizon", user feedback 2026-10-13): the drone looks far ahead along its own
-- heading, nearly level, instead of down at the path. The centre is HORIZON.pitch below the horizontal from the
-- eye, so it lies h / tan(pitch) ahead; the distance stays within cam.ZOOM_LIMIT (a shorter look-ahead, the
-- pitch rising a little, as cam.horizonFrame).

F.HORIZON = { alt = 300, pitch = 0.07, pMin = 0.02 }

--- How far ahead (m, horizontal) the horizon look's centre lies for an eye h m above it.
function F.horizonAhead(h)
	-- 3 % below the limit: the height is smoothed after the centre is placed, so the distance may grow a little
	local d = cam.horizonFrame(h, F.HORIZON.pitch, cam.ZOOM_LIMIT * 0.97)
	local hh = clamp(tonumber(h) or 0, 1, cam.ZOOM_LIMIT * 0.9)
	return math.sqrt(math.max(1, d * d - hh * hh))
end

---------------------------------------------------------------------------
-- High look (round 13, user: "still jumps as we move up terrain"; session 2026-10-14_0606_session, findings
-- map-camera.md "Tour eye jolts from the game's centre"): the game's centre sat 2.2-3.0 m above getHeightAt + 4
-- for three frames of an Aerials tour (something under the look-at point that the height query doesn't show), and
-- the eye, which the game places from that centre, jumped with it. No script can see such a thing before the game
-- does (the eye read shows the view a frame late), so below 800 m out every one of them steps the eye by its
-- height. From 1500 m out the game keeps its centre at the water level whatever the ground (findings: "The centre
-- is lowered to the water level far out", 120 trace frames). The High look flies there: the look-at point at
-- least HIGH.dMin m from the eye, which the game's flattest look at that distance (e >= 0.56 rad) puts about
-- 0.9-1 km above the sea, looking ~37 degrees down at the land 1.3 km ahead. The eye height is the sea's plus
-- d sin(elev), lifted only where the ground under the eye comes within HIGH.clear of it.

F.HIGH = {
	d = 1700,        -- m: eye -> look-at point (the sea-level centre), on average ...
	dAmp = 80,       -- ... breathing +- this (the altitude's slow sine, FLY.altPeriod)
	dMin = 1600,     -- m: never closer (the game's centre keeps no ground from 1500 m out)
	elev = 0.64,     -- rad: the look's elevation (the flattest the game shows at 1.6-1.9 km is ~0.56-0.59)
	clear = 300,     -- m: the eye at least this above the ground ahead of it (a map with high mountains)
}

--- The High look's eye height and eye-centre distance at flight time t over the smoothed ground ge (m): the
--- eye on the sea-level centre's ray at HIGH.elev, HIGH.d +- dAmp away, raised (and the distance with it) where
--- the ground under it comes within HIGH.clear.
function F.highPose(ge, t, phase)
	local H, C = F.HIGH, F.CAM
	local s = math.sin(2 * math.pi * ((tonumber(t) or 0) / F.FLY.altPeriod + (phase or 0)))
	local d = math.max(H.dMin, H.d + H.dAmp * s)
	local base = C.lift + C.water
	local ez = math.max(base + d * math.sin(H.elev), (tonumber(ge) or 0) + H.clear)
	d = math.max(d, (ez - base) / math.sin(H.elev))
	return ez, d
end

---------------------------------------------------------------------------
-- Mouse look during a flight (user feedback 2026-10-13): the player's turn / tilt / zoom (pm_cam.flightInput)
-- accumulates into an offset { a, p, z } on top of the flight's own view: a (rad) wrapped, p (rad) and z (log
-- distance) clamped. With "Look returns to the path" on, the offset decays to 0 once the player has stopped for
-- LOOK.idle s, over about LOOK.decay s (exponential, ~95 % gone).

F.LOOK = { pMax = 0.9, zMin = -0.7, zMax = 1.0, idle = 0.6, decay = 5.0 }

--- A fresh look offset.
function F.newLook()
	return { a = 0, p = 0, z = 0, idle = 0 }
end

--- Adds one frame's input (da, dp, dz) to the look offset `l` (changed in place and returned) and lets it decay
--- when `decay` is on and the player has been idle LOOK.idle s. dt in seconds (capped at 0.1).
function F.lookStep(l, da, dp, dz, dt, decay)
	local k = F.LOOK
	l = l or F.newLook()
	dt = clamp(tonumber(dt) or 0, 0, 0.1)
	da, dp, dz = tonumber(da) or 0, tonumber(dp) or 0, tonumber(dz) or 0
	if not (finite(da) and finite(dp) and finite(dz)) then da, dp, dz = 0, 0, 0 end
	if da ~= 0 or dp ~= 0 or dz ~= 0 then
		l.idle = 0
		l.a = cam.wrapAngle(l.a + da)
		l.p = clamp(l.p + dp, -k.pMax, k.pMax)
		l.z = clamp(l.z + dz, k.zMin, k.zMax)
	else
		l.idle = (l.idle or 0) + dt
		if decay and l.idle >= k.idle then
			-- exp(-3) ~ 5 % left after LOOK.decay seconds
			local f = math.exp(-3 * dt / k.decay)
			l.a, l.p, l.z = l.a * f, l.p * f, l.z * f
			if math.abs(l.a) < 1e-4 and math.abs(l.p) < 1e-4 and math.abs(l.z) < 1e-4 then l.a, l.p, l.z = 0, 0, 0 end
		end
	end
	return l
end

--- Applies the look offset `l` to view v (in place): angle + l.a, pitch + l.p (within 0.02 .. PITCH_MAX), distance x
--- exp(l.z). minEyeH (optional): the eye's lowest height above the view's centre (the ground under the eye plus a
--- margin); the pitch is raised to keep it.
function F.applyLook(v, l, minEyeH)
	if v == nil or l == nil then return v end
	v.a = cam.wrapAngle(v.a + (l.a or 0))
	v.p = clamp(v.p + (l.p or 0), 0.02, cam.PITCH_MAX)
	v.d = clamp(v.d * math.exp(l.z or 0), cam.MIN_DIST, cam.ZOOM_LIMIT)
	if finite(minEyeH) and v.d * math.sin(v.p) < minEyeH then
		v.p = clamp(math.asin(clamp(minEyeH / v.d, -1, 1)), v.p, cam.PITCH_MAX)
	end
	return v
end

--- Low-pass step of a value towards a target (time constant tc seconds, dt seconds).
function F.smoothTo(cur, target, dt, tc)
	if not finite(cur) then return target end
	if not finite(target) then return cur end
	local k = 1 - math.exp(-math.max(0, tonumber(dt) or 0) / math.max(1e-3, tc or 1))
	return cur + (target - cur) * k
end

---------------------------------------------------------------------------
-- Eye space (round 7, user feedback 2026-10-13: "the height maps really mess up the experience, it's not
-- smooth", pans "stuttery because it follows the terrain map"). setCameraData places the camera around a
-- centre on the terrain, so a centre sliding over uneven ground made the eye bob with every bump under the
-- look-at point. Every automated move is planned as an eye pose (eye x, y, z and a look heading and elevation)
-- that never depends on the terrain under the centre:
--   * planned views carry a reference ground g (pm_cam view + g). g comes from the ends of a move (one
--     getHeightAt per hop end, never per frame) and is interpolated between them, so the eye path is as smooth
--     as the plan. A view in the game's pitch (a framing, a saved view, a Ken Burns drift) has its eye where the
--     game would put it on that ground (F.poseOf gamePitch: the camera model below); an elevation view (wander,
--     flights, F.viewOfPose) has its eye at g + d * sin(p);
--   * each frame F.solveEye turns the pose into the view to send: it walks the look ray from the eye to where it
--     meets the game's centre surface (F.centreZ of getHeightAt: EYE.iters reads, a step that would be exact on
--     flat ground, then secant steps, warm-started from the last frame) and makes that the centre. The distance
--     comes from the eye and that centre; the pitch sent is the one the camera model turns into that elevation
--     at that distance (F.pitchFor, no lag): the eye lands where planned whatever the distance the terrain
--     gives; only the look direction carries the search's small leftover;
--   * the eye keeps a clearance above the ground EYE.aheadS seconds ahead of it (one getHeightAt), smoothed:
--     it rises quickly before a hill and settles slowly after it, instead of popping;
--   * a nearly level look that meets no ground within the zoom limit takes the centre at the limit: the pitch
--     becomes the one that reaches the ground there (a little steeper; it changes only as the far ground does).
-- Per frame: 1 + EYE.iters = 4 getHeightAt, fewer once the look is exact, up to 1 + EYE.maxIters = 7 in the frame a
-- crest stops hiding the ground behind it; round 9: + 1 while a jump of the meeting point is blended (EYE.jumpAbs),
-- and in a rare frame a second search (a look flatter than the game can show there): at most 2 + 2 * maxIters = 14
-- (flights 1-2 more for their own altitude and look point).

F.EYE = {
	iters = 3,            -- getHeightAt along the look ray per frame, usually ...
	maxIters = 6,         -- ... up to this many while the look is still more than errOk off (a crest passed)
	errOk = 0.003,        -- rad
	clearMax = 12,        -- m: the eye's clearance above the ground ahead, at most ...
	clearShare = 0.8,     -- ... and at most this share of the planned height (eye-level shots stay low)
	clearMin = 0.8,       -- m: the hard floor
	aheadS = 1.5,         -- s: the clearance looks this far ahead along the eye's motion
	aheadMax = 250,       -- m
	riseTc = 0.5, fallTc = 2.5, -- s: the clearance lift rises fast and settles slowly
	minH = 1,             -- m: the eye at least this above the centre it looks at
	maxD = cam.ZOOM_LIMIT * 0.97,
	-- A sample of the game's camera (F.pitchSample) counts only when the game's eye-centre distance is within
	-- dTol (share) + 2 m of the distance set and its centre within cTol (share of the distance) + 3 m of the
	-- centre set. The pitch sent stays >= sendMin; the eye-centre elevation <= elevMax (below straight down).
	dTol = 0.15, cTol = 0.1, sendMin = 0, elevMax = 1.48,
	-- Round 9: a jump of the look's meeting point (a crest starts or stops hiding the ground behind it) by more
	-- than jumpAbs m + jumpRel of the distance is blended over blendS seconds (the centre slides there instead
	-- of jumping): any error of the camera model is d * (its elevation error), so a jump of d would step the
	-- eye; blended, it moves smoothly, and the look leaves the plan a little for that half second.
	jumpAbs = 2, jumpRel = 0.02, blendS = 1.0, blendShrink = 0.8,
	-- round 10: the reads of the last-resort bisection when no showable centre was found (rare frames)
	guardIters = 6,
	-- the distance behind the flattest-look bound: the plan's, times this (ground a little lower than planned)
	lowMargin = 1.15,
}

---------------------------------------------------------------------------
-- The game's camera model (round 9, refitted in round 10 to the traces and eye checks of sessions
-- 2026-10-13_1755_session and 2026-10-13_1915_session, d 25-1725 m; docs/findings/map-camera.md "The game's
-- camera model"). For setCameraData(x, y, d, angle, p):
--   centre  getCenter = (x, y, CAM.lift + max(ground, water) * S(d)): 4.0 m above getHeightAt up to 800 m out;
--           farther out the game lowers the centre to the water level, S(d) a smoothstep from 1 at CAM.flatNear
--           (800 m) to 0 at CAM.flatFar (1500 m) (round 10, 120 trace frames: rms 0.19 m);
--   eye     d from that centre (exact), in the look's vertical plane, at the elevation
--           e = p + k1(d) (pi/2 - p) + k2(d), k1 = CAM.ka + CAM.kb ln d, k2 = CAM.kc d / (d + CAM.kd): the pitch
--           blended towards straight down plus a lift that grows with the distance and saturates (k2 < 0.45).
--           106 distinct samples: rms 0.0013 rad, max 0.0041 (round 9's k = 0.0768 + 0.0102 sqrt(d) (pi/2 - p):
--           rms 0.018, max 0.043, and off by 0.03 at 800-1000 m depending on the pitch: the flights' jerk).
--           The camera looks at the centre (it shows at the screen middle).
--   A pitch can put the eye past straight down (e > pi/2: at 900 m p 1.45 gives 1.67, the inverted WASD keys of
--   round 7), so no view is sent with e above CAM.elevSafe (F.pitchMaxAt).
--   The solver sends the pitch for the elevation wanted at this frame's distance (F.pitchFor). Only the model's
--   small residual is measured from the game (F.resSample) and corrected slowly (F.resUpdate, within
--   +-CAM.resMax); the driver starts it from 0 for every move, as a residual measured at another distance says
--   little about this one.

F.CAM = {
	lift = 4.0, water = 0, flatNear = 800, flatFar = 1500,
	ka = 0.07092, kb = 0.01624, kc = 0.44961, kd = 1185, dMin = 5, dMax = 4500,
	resTc = 3.0, resMax = 0.04,
	elevSafe = 1.50,
}
local HALF_PI = math.pi / 2

local function camD(d)
	local C = F.CAM
	d = tonumber(d) or 0
	if not finite(d) then d = C.dMin end
	return clamp(d, C.dMin, C.dMax)
end

--- How much of the terrain height the game's centre keeps at distance d (1 near, 0 far: the water level).
function F.centreKeep(d)
	local C = F.CAM
	if d == nil then return 1 end
	d = tonumber(d) or 0
	local u = (C.flatFar - d) / (C.flatFar - C.flatNear)
	return cam.ease(u)
end

--- The game's centre height over ground g (getHeightAt there) at distance d (nil: near).
function F.centreZ(g, d)
	local C = F.CAM
	return C.lift + math.max(tonumber(g) or 0, C.water) * F.centreKeep(d)
end

--- The pitch blend k1 and the lift k2 (rad) at distance d.
function F.camK(d)
	local C = F.CAM
	d = camD(d)
	return C.ka + C.kb * math.log(d), C.kc * d / (d + C.kd)
end

--- The eye-centre elevation the game shows for pitch p at distance d (res: the measured residual, nil = 0).
function F.gameElev(p, d, res)
	local k1, k2 = F.camK(d)
	return p + k1 * (HALF_PI - p) + k2 + (tonumber(res) or 0)
end

--- The pitch to send for the eye-centre elevation e at distance d (the inverse of F.gameElev; may be < 0 when e
--- is flatter than the game can show at that distance).
function F.pitchFor(e, d, res)
	local k1, k2 = F.camK(d)
	return (e - (tonumber(res) or 0) - k2 - k1 * HALF_PI) / (1 - k1)
end

--- The steepest pitch to send at distance d: the eye at most CAM.elevSafe (just short of straight down; past it
--- the game's keyboard pan turns around).
function F.pitchMaxAt(d, res)
	return F.pitchFor(F.CAM.elevSafe, d, res)
end

--- A fresh solver state (one per move; kept from frame to frame: warm start, lift, last eye, last distance).
--- res: the camera model's residual to correct (rad, nil = 0).
function F.newEye(res)
	return { L = nil, lift = 0, ex = nil, ey = nil, ez = nil, calls = 0, res = res }
end

--- One sample of the game's own camera: the elevation of getEye over getCenter minus the pitch read
--- (cur: getCameraData as a view { x, y, d, p }). nil (and why) when the game's camera doesn't match the data
--- (a different distance or centre: still easing, the free camera, a follow), or nothing is finite.
function F.pitchSample(cur, ex, ey, ez, cx, cy, cz)
	local E = F.EYE
	if cur == nil or not (finite(cur.x) and finite(cur.y) and finite(cur.d) and finite(cur.p)) then return nil, "view" end
	if not (finite(ex) and finite(ey) and finite(ez) and finite(cx) and finite(cy) and finite(cz)) then return nil, "eye" end
	local dx, dy, dz = ex - cx, ey - cy, ez - cz
	local L = math.sqrt(dx * dx + dy * dy)
	local dist = math.sqrt(L * L + dz * dz)
	if math.abs(dist - cur.d) > E.dTol * cur.d + 2 then return nil, "distance" end
	local ox, oy = cx - cur.x, cy - cur.y
	if math.sqrt(ox * ox + oy * oy) > E.cTol * cur.d + 3 then return nil, "centre" end
	if L < 0.5 then return nil, "vertical" end
	return cam.atan2(dz, L) - cur.p
end

--- The model's residual in a sample (the offset measured less the model's at the distance and pitch read).
function F.resSample(cur, sample)
	if not finite(sample) or cur == nil or not finite(cur.p) then return nil end
	return sample - (F.gameElev(cur.p, cur.d) - cur.p)
end

--- The residual estimate after a sample: a critically damped follower (time scale CAM.resTc; it starts and stops
--- moving smoothly, so the correction itself never steps the eye), the sample clamped to +-CAM.resMax. res, vel:
--- the estimate and its rate (nil: 0); dt: seconds since the last update (<= 0 or no sample: unchanged).
--- Returns res, vel.
function F.resUpdate(res, vel, sample, dt)
	local C = F.CAM
	if not finite(res) then res = 0 end
	if not finite(vel) then vel = 0 end
	dt = tonumber(dt) or 0
	if not finite(sample) or not finite(dt) or dt <= 0 then return res, vel end
	local target = clamp(sample, -C.resMax, C.resMax)
	local w = 2 / C.resTc
	-- exact step of x'' = w^2 (target - x) - 2 w x' over dt
	local x0 = res - target
	local ewt = math.exp(-w * dt)
	local c2 = vel + w * x0
	local x = (x0 + c2 * dt) * ewt
	vel = (c2 - w * (x0 + c2 * dt)) * ewt
	return clamp(target + x, -C.resMax, C.resMax), vel
end

--- The eye pose of a planned view v ({ x, y, d, a, p, g }; g nil = 0) with the look offset `off`: eye x, y, z,
--- look heading, elevation and the horizontal distance to the planned centre (a start for the search).
--- gamePitch: v is in the game's pitch over the terrain g (a framing, a saved view, a drift): the eye where the
--- game would put it (the camera model, with the residual res); else v.p is the elevation and g the reference
--- under the centre (F.viewOfPose). Numbers, no table (every frame).
function F.poseOf(v, off, gamePitch, res)
	local h = cam.lookOf(v.a, off)
	local p, z0 = v.p, v.g or 0
	if gamePitch then
		p = F.gameElev(v.p, v.d, res)
		z0 = F.centreZ(z0, v.d)
	end
	local L = v.d * math.cos(p)
	return v.x - math.cos(h) * L, v.y - math.sin(h) * L, z0 + v.d * math.sin(p), h, p, L
end

--- The planned view (with its reference ground g) of an eye pose: the centre `d` m along the look (any d gives
--- the same pose; pick one that reads well when a glide interpolates it). Writes `out`. An elevation view.
function F.viewOfPose(ex, ey, ez, h, p, d, off, out)
	local v = out or {}
	d = math.max(1, tonumber(d) or 1)
	local L = d * math.cos(p)
	v.x, v.y = ex + math.cos(h) * L, ey + math.sin(h) * L
	v.d, v.p, v.a = d, p, cam.angleFor(h, off)
	v.g = ez - d * math.sin(p)
	return v
end

--- A view in the game's pitch over terrain g as an elevation view (the same eye): the wander's start.
function F.elevView(v, res)
	return { x = v.x, y = v.y, d = v.d, a = v.a, p = F.gameElev(v.p, v.d, res), g = F.centreZ(v.g or 0, v.d) }
end

--- An elevation view as a view in the game's pitch over terrain (about the same eye; a pitch below 0 is kept at
--- 0): a flight's first view as the end of the glide up, which runs in the game's pitch from the current view.
function F.gameView(v, res)
	-- the terrain under the centre that gives this centre height at this distance (any, where the game keeps none)
	local keep = F.centreKeep(v.d)
	local g = (v.g or 0) - F.CAM.lift
	if keep > 0.01 then g = g / keep end
	return { x = v.x, y = v.y, d = v.d, a = v.a, p = math.max(0, F.pitchFor(v.p, v.d, res)), g = g }
end

--- The view to send for the eye pose (ex, ey, ez, look heading h, elevation p): see "Eye space" above. Lhint: a
--- start for the search (the planned centre's horizontal distance), used when the state has none; hPlan: the
--- planned height above the reference ground (the clearance is at most EYE.clearShare of it); ground(x, y) ->
--- height or nil; off: the look offset; dt: seconds since the last frame (0 / nil: no smoothing). Writes `out`;
--- st.calls = getHeightAt calls this frame, st.ez = the eye height used (after the clearance lift), st.err = the
--- look's leftover (rad), st.gC = the ground under the centre, st.d = the distance sent.
function F.solveEye(st, ex, ey, ez, h, p, Lhint, hPlan, ground, off, dt, out)
	local E, C = F.EYE, F.CAM
	local v = out or {}
	dt = tonumber(dt) or 0
	if not finite(dt) or dt < 0 then dt = 0 end
	local calls = 0
	-- the game's centre height over ground g, L m (horizontal) along the look from this eye: near, terrain + lift;
	-- far, lowered to the water level (F.centreKeep of the eye-centre distance, a few fixed-point steps)
	local function surf(g, L)
		local z = F.centreZ(g)
		if F.centreKeep(math.sqrt(L * L + (ez - C.lift) ^ 2)) >= 1 then return z end -- near: no iteration
		for __ = 1, 4 do z = F.centreZ(g, math.sqrt(L * L + (ez - z) ^ 2)) end
		return z
	end
	-- clearance above the ground (or water) where the eye will be aheadS seconds from now
	local ax, ay = ex, ey
	if st.ex ~= nil and dt > 0 then
		local vx, vy = (ex - st.ex) / dt * E.aheadS, (ey - st.ey) / dt * E.aheadS
		local len = math.sqrt(vx * vx + vy * vy)
		if finite(len) then
			if len > E.aheadMax then vx, vy = vx * E.aheadMax / len, vy * E.aheadMax / len end
			ax, ay = ex + vx, ey + vy
		end
	end
	local gA = ground(ax, ay)
	calls = calls + 1
	if finite(gA) then gA = math.max(gA, C.water) end
	local clear = clamp(E.clearShare * (finite(hPlan) and hPlan or E.clearMax), E.clearMin, E.clearMax)
	local want = finite(gA) and math.max(0, gA + clear - ez) or 0
	if st.ex == nil then
		st.lift, st.hold = want, 0
	elseif dt > 0 then
		if want >= (st.lift or 0) then
			st.hold = 0
			st.lift = F.smoothTo(st.lift or 0, want, dt, E.riseTc)
		else
			-- the ground ahead dropped: stay up until the eye has passed where it was high (aheadS), then settle
			st.hold = (st.hold or 0) + dt
			if st.hold > E.aheadS then st.lift = F.smoothTo(st.lift or 0, want, dt, E.fallTc) end
		end
	end
	-- the hard floor only for an eye at rest (then the sample is under it); a moving eye rose aheadS seconds early
	if finite(gA) and ax == ex and ay == ey then st.lift = math.max(st.lift or 0, gA + E.clearMin - ez) end
	ez = ez + (st.lift or 0)
	-- The look's elevation: at least what the game can show (pitch >= 0) at about the distance the look will
	-- meet the ground, at most what it shows for SAFE.pMax and elevMax. That distance comes from the PLAN (the
	-- eye's height over its reference ground, hPlan, plus EYE.lowMargin for ground lower than that), never from
	-- the terrain the look meets: the bound is as smooth as the plan, so a look the game can't show as flat as
	-- planned is steepened smoothly (round 9: the terrain's distance made it jump at crests). A look that still
	-- comes out flatter than the game can show where it met the ground is searched once more (below).
	local res = finite(st.res) and st.res or 0
	local pIn = finite(p) and p or 0.3
	local dEst
	if finite(hPlan) and hPlan > 1 then
		local e = clamp(pIn, 0.02, 1.45)
		for __ = 1, 3 do
			dEst = math.min(E.maxD, hPlan / math.sin(e) * E.lowMargin)
			e = math.max(pIn, F.gameElev(E.sendMin, dEst, res) + 0.005)
			e = clamp(e, 0.02, 1.45)
		end
	else
		dEst = finite(st.d) and st.d or 200
	end
	local pLo = math.max(0.005, F.gameElev(E.sendMin, dEst, res) + 0.005)
	local pHi = math.max(pLo, math.min(F.gameElev(cam.SAFE.pMax, dEst, res), E.elevMax, F.CAM.elevSafe - 0.02))
	p = clamp(pIn, pLo, pHi)
	local ch, sh = math.cos(h), math.sin(h)
	-- the start: where last frame's search stood, along this frame's ray (a point on the ground stays put while
	-- the eye moves), else the plan's own centre
	local Lstart = nil
	if st.nx ~= nil then Lstart = (st.nx - ex) * ch + (st.ny - ey) * sh end
	if not finite(Lstart) or Lstart <= 0 then Lstart = Lhint end
	-- Every point read gives an exact eye; the centre is the one whose elevation from the eye is closest to p.
	-- The surface is the game's centre height (F.centreZ). Steps (f = ray height - surface: > 0 the meeting
	-- point lies farther): regula falsi once a point above and one below the surface bracket a meeting point;
	-- else secant, but only in the direction f points to (a ray passing just over a crest would otherwise turn
	-- back to the crest), else the step that would be exact on flat ground. A search that hasn't met the surface
	-- goes on from where it stopped in the next frame.
	local function search(pp, L, maxIters)
		local tp, cp = math.tan(pp), math.cos(pp)
		local Lmin = math.max(0.5, cam.MIN_DIST * cp)
		-- within the zoom limit, and (st.maxL, F.rayInside) inside the map: setCameraData's centre is clamped there
		local Lmax = math.max(Lmin, math.min(E.maxD * cp, tonumber(st.maxL) or math.huge))
		if not finite(L) then L = (ez - (finite(gA) and F.centreZ(gA) or 0)) / tp end
		if not finite(L) then L = Lmin end
		L = clamp(L, Lmin, Lmax)
		local L0, f0 = nil, nil
		local La, fa, Lb, fb = nil, nil, nil, nil
		local bestL, bestS, bestG, bestErr = nil, nil, nil, math.huge
		local nextL = nil
		for i = 1, maxIters do
			local g = ground(ex + ch * L, ey + sh * L)
			calls = calls + 1
			local s
			if finite(g) then s = surf(g, L) else s = ez - L * tp g = s - C.lift end -- unreadable: on the ray
			local err = math.abs(cam.atan2(math.max(E.minH, ez - s), L) - pp)
			if err < bestErr then bestL, bestS, bestG, bestErr = L, s, g, err end
			if err < 1e-5 or (i >= E.iters and bestErr < E.errOk) then nextL = L break end
			local f = ez - L * tp - s
			if f > 0 then La, fa = L, f else Lb, fb = L, f end
			local Ln
			if La ~= nil and Lb ~= nil then
				Ln = La - fa * (Lb - La) / (fb - fa)
			else
				local sec = nil
				if L0 ~= nil and math.abs(f - f0) > 1e-6 and math.abs(L - L0) > 1e-9 then sec = L - f * (L - L0) / (f - f0) end
				if sec ~= nil and ((f > 0 and sec > L) or (f < 0 and sec < L)) then Ln = sec else Ln = L + f / tp end
			end
			if not finite(Ln) then Ln = L end
			Ln = clamp(Ln, math.max(Lmin, L * 0.25), math.min(Lmax, L * 4 + 50))
			L0, f0 = L, f
			L = Ln
			nextL = Ln
		end
		return bestL, bestS, bestG, bestErr, nextL or bestL
	end
	local bestL, bestS, bestG, bestErr, nextL = search(p, Lstart, E.maxIters)
	local H = math.max(E.minH, ez - bestS)
	local d = math.sqrt(bestL * bestL + H * H)
	local pSend = F.pitchFor(cam.atan2(H, bestL), d, res)
	if pSend < E.sendMin - 1e-4 then
		-- flatter than the game shows at this distance (the estimate was too far, or the search hasn't met the
		-- surface yet): once more, at the flattest it can show there if that is steeper
		local p2 = math.min(pHi, math.max(p, F.gameElev(E.sendMin, d, res) + 0.005))
		do
			local L2, S2, G2, err2, n2 = search(p2, bestL, E.maxIters)
			bestL, bestS, bestG, bestErr, nextL = L2, S2, G2, err2, n2
			H = math.max(E.minH, ez - bestS)
			d = math.sqrt(bestL * bestL + H * H)
			pSend = F.pitchFor(cam.atan2(H, bestL), d, res)
		end
	end
	if pSend < E.sendMin - 1e-4 then
		-- still flatter than the game can show (round 10: a search that never met the surface, e.g. far out near
		-- the zoom limit): sending pitch 0 would lift the eye by d x the gap (up to hundreds of metres for a
		-- frame). Instead the centre comes closer along the look, to the farthest point the game can show from
		-- this eye (bisection): the eye stays, the look steepens for those frames.
		local lo, hi = math.max(0.5, cam.MIN_DIST * math.cos(p)), bestL
		local found = nil
		for __ = 1, E.guardIters do
			local Lm = 0.5 * (lo + hi)
			local g = ground(ex + math.cos(h) * Lm, ey + math.sin(h) * Lm)
			calls = calls + 1
			local sM = finite(g) and surf(g, Lm) or (finite(gA) and F.centreZ(gA) or C.lift)
			local HM = math.max(E.minH, ez - sM)
			local dM = math.sqrt(Lm * Lm + HM * HM)
			local pM = F.pitchFor(cam.atan2(HM, Lm), dM, res)
			if pM >= E.sendMin then
				lo = Lm
				found = { Lm, sM, finite(g) and g or sM - C.lift, HM, dM, pM }
			else
				hi = Lm
			end
		end
		if found ~= nil then
			bestL, bestS, bestG, H, d, pSend = found[1], found[2], found[3], found[4], found[5], found[6]
			nextL = bestL
		end
		st.guarded = (st.guarded or 0) + 1
	end
	-- A jump of the meeting point (its distance along the look against the last two frames' carried on: the
	-- meeting point slides smoothly while the look sweeps the ground, even fast): blended from where last frame's
	-- centre stood, eased out over blendS (see EYE.jumpAbs)
	local Ls = bestL
	if st.hL1 ~= nil and st.hL0 ~= nil and dt > 0 then
		local Lhit = 2 * st.hL1 - st.hL0
		if finite(Lhit) and math.abs(bestL - Lhit) > E.jumpAbs + E.jumpRel * bestL then
			local Lsent = (st.sx - ex) * ch + (st.sy - ey) * sh
			if finite(Lsent) and Lsent > 0 then st.blend, st.blendT = Lsent - bestL, 0 end
		end
	end
	if st.blend ~= nil then
		st.blendT = st.blendT + dt
		local u = st.blendT / E.blendS
		if u >= 1 or dt <= 0 then
			st.blend = nil
		else
			local tp, cp = math.tan(p), math.cos(p)
			local Lmin = math.max(0.5, cam.MIN_DIST * cp)
			local Lmax = math.max(Lmin, math.min(E.maxD * cp, tonumber(st.maxL) or math.huge))
			-- the blended point; one the game can't show from this eye (too flat or too steep) is pulled
			-- towards the meeting point (blendShrink), twice at most, then the blend ends there
			local o = st.blend * (1 - cam.ease(u))
			local done = false
			for __ = 1, 3 do
				local Lt = clamp(bestL + o, Lmin, Lmax)
				local g = ground(ex + ch * Lt, ey + sh * Lt)
				calls = calls + 1
				local sT, gT
				if finite(g) then sT, gT = surf(g, Lt), g else sT = ez - Lt * tp gT = sT - C.lift end
				local H2 = math.max(E.minH, ez - sT)
				local d2 = math.sqrt(Lt * Lt + H2 * H2)
				local p2 = F.pitchFor(cam.atan2(H2, Lt), d2, res)
				if p2 >= E.sendMin and p2 <= math.min(cam.SAFE.pMax, F.pitchMaxAt(d2, res)) then
					Ls, bestS, bestG, H, d, pSend = Lt, sT, gT, H2, d2, p2
					st.blend = o / math.max(1e-6, 1 - cam.ease(u))
					done = true
					break
				end
				o = o * E.blendShrink
			end
			if not done then st.blend = nil end
		end
	end
	-- distance from the eye to the chosen centre (the eye is exact), and the pitch the camera model turns into
	-- that elevation at that distance
	v.x, v.y = ex + ch * Ls, ey + sh * Ls
	v.d = d
	v.p = clamp(pSend, E.sendMin, math.max(E.sendMin, math.min(cam.SAFE.pMax, F.pitchMaxAt(d, res))))
	v.a = cam.angleFor(h, off)
	st.L, st.ex, st.ey, st.ez, st.calls, st.err, st.gC, st.d = Ls, ex, ey, ez, calls, bestErr, bestG, v.d
	st.nx, st.ny = ex + ch * nextL, ey + sh * nextL
	st.hL0, st.hL1 = st.hL1, bestL
	st.sx, st.sy = v.x, v.y
	return v
end

--- How far (m, horizontal) the ray from (ex, ey) along heading h stays inside bounds ({ minX, minY, maxX, maxY }):
--- huge without bounds or from an eye outside them (nothing to keep), at least 1.
function F.rayInside(b, ex, ey, h)
	if b == nil or not (finite(ex) and finite(ey) and finite(h)) then return math.huge end
	if ex < b[1] or ex > b[3] or ey < b[2] or ey > b[4] then return math.huge end
	local ch, sh = math.cos(h), math.sin(h)
	local L = math.huge
	if ch > 1e-9 then L = math.min(L, (b[3] - ex) / ch) elseif ch < -1e-9 then L = math.min(L, (b[1] - ex) / ch) end
	if sh > 1e-9 then L = math.min(L, (b[4] - ey) / sh) elseif sh < -1e-9 then L = math.min(L, (b[2] - ey) / sh) end
	return math.max(1, L)
end

--- The eye of a sent view as the game places it (the camera model: the centre F.centreZ(g) over the ground g
--- under it, the eye at elevation F.gameElev(p, d, res)), as numbers.
function F.eyeOf(v, g, off, res)
	local h = cam.lookOf(v.a, off)
	local e = F.gameElev(v.p, v.d, res)
	local L = v.d * math.cos(e)
	return v.x - math.cos(h) * L, v.y - math.sin(h) * L, F.centreZ(g, v.d) + v.d * math.sin(e)
end

---------------------------------------------------------------------------
-- Smoothness metric (round 9): the game's eye (getEye) frame by frame during a move. d2 = |E(i) - 2 E(i-1) +
-- E(i-2)| (m, the second difference; round 13: taken at the frames' own times, |v(i) - v(i-1)| x the mean frame
-- time, so an uneven frame time alone is no spike), acc = the change of velocity per second (m/s^2, frame times differ),
-- jerk = how much acc changes from one frame to the next (m/s^2): terrain bumps or a lagging correction show
-- up as jerk spikes, a smooth glide's ease as a low, steady acc. A frame gap over gapS restarts the chain (a
-- hitch, not the camera). Round 10: so does a cut (F.smoothCut from the driver, or an eye faster than cutSpeed:
-- no glide of ours comes near it; the session's 4.7 km new-area glides peaked at ~2.3 km/s), counted in `cuts`
-- instead of measured (session 2026-10-13_1915_session's tour total: "speed max 48443 m/s").

F.SMOOTH = { gapS = 0.25, cutSpeed = 8000 }

function F.newSmooth()
	return { n = 0, frames = 0, d2Max = 0, d2Sum = 0, accMax = 0, jerkMax = 0, jerkSum = 0, nJerk = 0, nD2 = 0,
		worst = 0, vMax = 0, cuts = 0, lookMax = 0, lookWorst = 0 }
end

--- A cut: the next frame starts a new chain (not measured as motion).
function F.smoothCut(m)
	if m == nil then return end
	m.cuts = (m.cuts or 0) + 1
	m.px, m.vx, m.ax = nil, nil, nil
	m.cutNext = true
end

--- Round 12: the look direction's second difference (rad, about the turn's change per frame) from the unit
--- look vectors of three frames; m.lu1 / m.lu2 the last two. cx, cy, cz: the game's centre (nil: not measured).
local function lookAdd(m, x, y, z, cx, cy, cz)
	m.lookD2 = nil
	if not (finite(cx) and finite(cy) and finite(cz)) then m.lu1, m.lu2 = nil, nil return end
	local lx, ly, lz = cx - x, cy - y, cz - z
	local n = math.sqrt(lx * lx + ly * ly + lz * lz)
	if n < 1e-6 then m.lu1, m.lu2 = nil, nil return end
	local u = { lx / n, ly / n, lz / n }
	local a, b = m.lu1, m.lu2
	if a ~= nil and b ~= nil then
		local d = math.sqrt((u[1] - 2 * a[1] + b[1]) ^ 2 + (u[2] - 2 * a[2] + b[2]) ^ 2 + (u[3] - 2 * a[3] + b[3]) ^ 2)
		m.lookD2 = d
		if d > m.lookMax then m.lookMax, m.lookWorst = d, m.frames end
	end
	m.lu2, m.lu1 = a, u
end

--- Adds one frame's eye (x, y, z) dt seconds after the last one; round 12: and the game's centre (cx, cy, cz,
--- optional) for the look's smoothness. m.lastD2 / m.lookD2: this frame's values (nil: not measured).
function F.smoothAdd(m, x, y, z, dt, cx, cy, cz)
	m.lastD2, m.lastD2Raw = nil, nil
	if not (finite(x) and finite(y) and finite(z)) then return end
	dt = tonumber(dt) or 0
	m.frames = m.frames + 1
	m.cutNext = nil
	if not finite(dt) or dt <= 0 or dt > F.SMOOTH.gapS or m.px == nil then
		m.px, m.py, m.pz, m.vx, m.ax = x, y, z, nil, nil
		m.lu1, m.lu2 = nil, nil
		lookAdd(m, x, y, z, cx, cy, cz)
		return
	end
	local vx, vy, vz = (x - m.px) / dt, (y - m.py) / dt, (z - m.pz) / dt
	if vx * vx + vy * vy + vz * vz > F.SMOOTH.cutSpeed ^ 2 then
		m.cuts = (m.cuts or 0) + 1
		m.px, m.py, m.pz, m.vx, m.ax = x, y, z, nil, nil
		m.lu1, m.lu2 = nil, nil
		lookAdd(m, x, y, z, cx, cy, cz)
		return
	end
	lookAdd(m, x, y, z, cx, cy, cz)
	m.vMax = math.max(m.vMax, math.sqrt(vx * vx + vy * vy + vz * vz))
	if m.vx ~= nil then
		-- round 13: d2 at the frames' own times (|v - v_prev| x the mean frame time): the plain second difference
		-- of positions also grows with an uneven frame time (session 2026-10-14_0434_session: 7 of 12 "eye spike"
		-- reports were a 21-31 ms frame among 15 ms ones, the eye exactly on its timed path); for even frames both
		-- are the same. The plain one stays as m.lastD2Raw (the spike report shows both).
		local tm = 0.5 * (dt + m.dt)
		local d2 = math.sqrt((vx - m.vx) ^ 2 + (vy - m.vy) ^ 2 + (vz - m.vz) ^ 2) * tm
		m.lastD2 = d2
		m.lastD2Raw = math.sqrt((x - 2 * m.px + m.qx) ^ 2 + (y - 2 * m.py + m.qy) ^ 2 + (z - 2 * m.pz + m.qz) ^ 2)
		m.nD2 = m.nD2 + 1
		m.d2Sum = m.d2Sum + d2 * d2
		if d2 > m.d2Max then m.d2Max, m.worst = d2, m.frames end
		local ax, ay, az = (vx - m.vx) / tm, (vy - m.vy) / tm, (vz - m.vz) / tm
		m.accMax = math.max(m.accMax, math.sqrt(ax * ax + ay * ay + az * az))
		if m.ax ~= nil then
			local j = math.sqrt((ax - m.ax) ^ 2 + (ay - m.ay) ^ 2 + (az - m.az) ^ 2)
			m.nJerk = m.nJerk + 1
			m.jerkSum = m.jerkSum + j * j
			m.jerkMax = math.max(m.jerkMax, j)
		end
		m.ax, m.ay, m.az = ax, ay, az
	end
	m.qx, m.qy, m.qz = m.px, m.py, m.pz
	m.px, m.py, m.pz = x, y, z
	m.vx, m.vy, m.vz = vx, vy, vz
	m.dt = dt
end

--- d2 max, d2 rms (m), acc max, jerk max, jerk rms (m/s^2), frames, the worst d2's frame, the top speed (m/s),
--- round 12: the look's d2 max (rad) and its frame.
function F.smoothStats(m)
	local d2rms = m.nD2 > 0 and math.sqrt(m.d2Sum / m.nD2) or 0
	local jrms = m.nJerk > 0 and math.sqrt(m.jerkSum / m.nJerk) or 0
	return m.d2Max, d2rms, m.accMax, m.jerkMax, jrms, m.frames, m.worst, m.vMax, m.lookMax or 0, m.lookWorst or 0
end

-- Round 13: the smooth camera (round 10: the normal camera eased after the player's controls; round 12: its
-- click-to-glide) is removed: the game draws each key step before a mod can ease it (findings map-camera.md
-- "Smooth camera: the game draws a key's step before a mod can correct it"), so it stayed jerky
-- (plans/square_photo_mode/PLAN.md "Round 13").

---------------------------------------------------------------------------
-- Wander (round 7, user feedback 2026-10-13: "constantly slowly moving around a place in both x and y, not just
-- orbiting, like the This place tour but continuous with no cuts"). A camera move (Camera tab, next to Orbit:
-- around the middle of the view at its current scale) and a tour mode (the Area and the angle rows).
--   eye     polar around the place: the bearing turns slowly one way (one turn in WANDER.turnS) and meanders
--           (+-WANDER.meander rad), the radius breathes between rMin and rMax of the area: it goes in and out
--           as well as around, never through the middle;
--   height  the pitch towards the target swings slowly inside the angle range (round 9: the game's pitch, turned
--           into the elevation the game shows at that distance); the eye height follows from it
--   target  the look wanders between points of interest (nearby subjects, points of the area), a new one every
--           WANDER.lookS seconds, eased over WANDER.blendS; heading and pitch smoothed (headTc, pitchTc)
-- Everything goes through F.solveEye: the eye path never follows the terrain under the look-at point.

F.WANDER = {
	turnS = 360, meander = 0.35, meanderS = 90, rMin = 0.55, rMax = 1.05, breatheS = 80, breathe2S = 41,
	pitchS = 67, lookS = 10, blendS = 6, headTc = 1.2, pitchTc = 1.5, maxH = 1200, minL = 0.3,
	-- the manual move: the area from the current view's ground distance, the pitch +-pSpan around it
	manualMinR = 60, manualMaxR = 800, pSpan = 0.12, pLo = 0.04, pHi = 1.2,
}

--- A new wander around (x, y) (radius r, the place's ground g) within pitch pMin .. pMax. eyeBearing (optional):
--- where the eye starts around the place (the current eye: the glide in is short). rnd: 0..1 function.
function F.newWander(x, y, r, g, pMin, pMax, rnd, eyeBearing)
	local W = F.WANDER
	if not (finite(x) and finite(y) and finite(r)) or r <= 0 then return nil end
	pMin, pMax = tonumber(pMin) or 0.04, tonumber(pMax) or 0.7
	if pMin > pMax then pMin, pMax = pMax, pMin end
	local ph = {}
	for i = 1, 4 do ph[i] = rnd() * cam.TWO_PI end
	local w = { x = x, y = y, r = r, g = finite(g) and g or 0, pMin = pMin, pMax = pMax, ph = ph,
		dir = rnd() < 0.5 and -1 or 1, th0 = 0, n = 0 }
	-- the bearing at t = 0 is the current eye's
	local b = finite(eyeBearing) and eyeBearing or rnd() * cam.TWO_PI
	w.th0 = b - W.meander * math.sin(ph[1])
	w.tgt = { x = x, y = y, g = w.g }
	w.prev = { x = x, y = y, g = w.g }
	w.blend0 = -1e9
	return w
end

--- The eye's ground position at wander time t (s).
function F.wanderEye(w, t)
	local W = F.WANDER
	local th = w.th0 + w.dir * cam.TWO_PI * t / W.turnS + W.meander * math.sin(cam.TWO_PI * t / W.meanderS + w.ph[1])
	local u = 0.5 + 0.35 * math.sin(cam.TWO_PI * t / W.breatheS + w.ph[2]) + 0.15 * math.sin(cam.TWO_PI * t / W.breathe2S + w.ph[3])
	local R = w.r * (W.rMin + (W.rMax - W.rMin) * u)
	return w.x + R * math.cos(th), w.y + R * math.sin(th)
end

--- The target being looked at at time t: eased from the previous one to the current one.
function F.wanderTarget(w, t)
	local e = cam.ease((t - w.blend0) / F.WANDER.blendS)
	local a, b = w.prev, w.tgt
	return a.x + (b.x - a.x) * e, a.y + (b.y - a.y) * e, a.g + (b.g - a.g) * e
end

--- A new target (x, y, its ground g) from time t on; the look eases over from wherever it is now.
function F.wanderSetTarget(w, t, x, y, g)
	local px, py, pg = F.wanderTarget(w, t)
	w.prev = { x = px, y = py, g = pg }
	w.tgt = { x = x, y = y, g = finite(g) and g or pg }
	w.blend0 = t
	w.n = w.n + 1
end

--- The planned view (with its reference ground) at wander time t; dt: seconds since the last frame (0 / nil: no
--- smoothing). Writes `out`. Call once per frame (it smooths the look).
function F.wanderView(w, t, dt, off, out)
	local W = F.WANDER
	local ex, ey = F.wanderEye(w, t)
	local tx, ty, tg = F.wanderTarget(w, t)
	local dx, dy = tx - ex, ty - ey
	local L = math.sqrt(dx * dx + dy * dy)
	-- the pitch towards the target swings inside the angle range; round 9: the range is in the game's pitch (as
	-- the tour's angle rows and the manual wander's current view), so the eye goes where the game shows that
	-- pitch at this distance (the camera model): the look stays one the game can show (a flatter one jumped
	-- with the terrain's distance)
	local pw = w.pMin + (w.pMax - w.pMin) * (0.5 + 0.5 * math.sin(cam.TWO_PI * t / W.pitchS + w.ph[4]))
	local Lm = math.max(L, W.minL * w.r)
	local e = pw
	for __ = 1, 3 do e = F.gameElev(pw, Lm / math.cos(clamp(e, 0, 1.45))) end
	local H = math.min(W.maxH, Lm * math.tan(clamp(e, 0, 1.45)))
	local ez = tg + F.CAM.lift + H
	local hDes = L > 1 and cam.atan2(dy, dx) or (w.h or 0)
	local pDes = clamp(cam.atan2(H, math.max(L, 1)), 0.01, F.EYE.elevMax)
	dt = tonumber(dt) or 0
	if w.h == nil or not finite(dt) or dt <= 0 then
		w.h = w.h or hDes
		w.p = w.p or pDes
	else
		w.h = cam.wrapAngle(w.h + cam.angleDiff(w.h, hDes) * (1 - math.exp(-dt / W.headTc)))
		w.p = F.smoothTo(w.p, pDes, dt, W.pitchTc)
	end
	return F.viewOfPose(ex, ey, ez, w.h, w.p, math.sqrt(L * L + H * H), off, out)
end

--- The manual Wander's area and pitch range around the current view v: radius from its ground distance, the
--- pitch +-pSpan around its own. Returns r, pMin, pMax.
function F.wanderAround(v)
	local W = F.WANDER
	local r = clamp(v.d * math.cos(v.p), W.manualMinR, W.manualMaxR)
	local pMin = clamp(v.p - W.pSpan, W.pLo, W.pHi)
	local pMax = clamp(v.p + W.pSpan, W.pLo, W.pHi)
	return r, pMin, pMax
end

return F
