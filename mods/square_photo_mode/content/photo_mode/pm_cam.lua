-- Photo Mode camera logic, the pure part (no api calls): framing per subject kind, shot presets, the smooth
-- move (glide) between two views, orbit, "did the player move the camera" check, bookmark list operations,
-- random picks from cached lists, the tour's subject order. Shared by gui/pm_driver.lua, gui/pm_world.lua and
-- the offline tests (tests/square_photo_mode/test_cam.lua). Plain Lua, pre-5.3.
--
-- A view is a plain table { x, y, d, a, p }: the camera centre (x, y), distance (m), angle and pitch (radians),
-- the fields of api.gui.camera.getCameraData() / setCameraData(Vec5f{x, y, distance, angle, pitch})
-- (api/tealdef/api/gui.d.tl:430-438; Vec5f fields x, y, z, w, q). Pitch is the angle down from the horizon:
-- 1.45 looks almost straight down (square_organic_towns_dev's top-down view, read back in game 2026-10-12).
-- Planned views of the camera moves may carry `g`, a reference ground height for the centre: the eye then sits
-- d * sin(p) above g, not above the terrain (pm_flight.lua "Eye space", round 7).

local C = {}

C.PI = math.pi
-- atan2 on every Lua: the game's (pre-5.3) has math.atan2, Lua 5.3+ (the offline tests) only math.atan(y, x).
C.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
C.TWO_PI = 2 * math.pi

-- The steepest pitch Photo Mode ever sends (round 7): Bird's eye at 1.45 inverted the player's WASD keys
-- (user report 2026-10-13, session 2026-10-13_0733_bench-s3-683079: four bird shots at 1.450 with the angle
-- kept, the player turning the camera between them). Our angle and pitch were what we meant (read back the same,
-- below pi / 2), so the game's own camera handles a pitch that close to straight down differently. Round 8
-- blamed a constant offset (1.45 + 0.23 past straight down); round 9's fitted camera model (pm_flight "The game's
-- camera model", findings map-camera.md) blends the pitch towards straight down and never passes it (1.45 at
-- 900 m shows about 1.50), so the cause is open again (a tilt limit of the game's own keyboard pan, inferred).
-- 1.30 (round 8, was 1.35) stays; TESTING.md R4 / U10 / V8 check it.
C.PITCH_MAX = 1.30

-- Distances the camera reaches without easing back (the vanilla zoom-out limit is ~4137 m:
-- docs/findings/map-camera.md "Camera zoom limit"); a glide's mid-way rise stays below MAX_DIST.
C.MIN_DIST = 8
C.MAX_DIST = 3500
-- The farthest a horizon view goes (Camera tab "Horizon" / "High horizon", the Aerials "Horizon" look): just
-- below the measured vanilla zoom-out limit (~4137 m at pitch 0.95; whether it depends on the pitch is unknown,
-- TESTING.md G16). A horizon view that would need more is clamped here and its pitch raised to keep the height.
C.ZOOM_LIMIT = 4000

-- Framing per subject kind: distance (m) and pitch (radians, 0.26-0.52 = 15-30 degrees down). Angle: random.
C.FRAMING = {
	person = { d = 22, p = 0.26 },
	road = { d = 40, p = 0.30 },
	tram = { d = 45, p = 0.30 },
	train = { d = 120, p = 0.30 },
	plane = { d = 150, p = 0.30 },
	ship = { d = 150, p = 0.30 },
	vehicle = { d = 60, p = 0.30 },
	station = { d = 250, p = 0.45 },
	industry = { d = 350, p = 0.45 },
	town = { d = 900, p = 0.52 },
	place = { d = 120, p = 0.26 }, -- a random point anywhere on the map (pm_world "place")
}

-- Shot presets around the current camera centre (angle kept). No roll: Vec5f has no roll, so no Dutch angle.
C.SHOTS = {
	eye = { d = 25, p = 0.04 },
	low = { d = 60, p = 0.12 },
	drone = { d = 350, p = 0.60 },
	-- 1.30, not 1.45 (round 7: "when I press bird's eye the WASD controls are inverted"; see PITCH_MAX)
	bird = { d = 900, p = 1.30 },
}
C.SHOT_ORDER = { "eye", "low", "drone", "bird" }
-- Horizon shots (user feedback 2026-10-13: "higher up but looking across the horizon"): an eye height h (m) and a
-- nearly level pitch p; the distance is h / sin(p) (a long one), the centre pushed ahead along the heading so
-- the eye stays above the current centre. Past C.ZOOM_LIMIT the distance is clamped and the pitch raised
-- (horizonFrame).
C.HORIZON_SHOTS = {
	horizon = { h = 250, p = 0.075 },     -- ~4.3 degrees: d ~3330 m
	highhorizon = { h = 800, p = 0.10 },  -- wants d ~8000 m: clamped to the zoom limit, p ~0.20
}
C.HORIZON_ORDER = { "horizon", "highhorizon" }

-- The tour's glide between two places (smoothstep ease-in-out, rising on long hops: glideBump; with the drift
-- on, the end points move: pm_flight.lua).
C.GLIDE_SECONDS = 4.5
C.ORBIT_RAD_PER_S = C.TWO_PI / 60 -- one full turn a minute
C.TOUR_SECONDS = { 5, 10, 20 }
C.TOUR_DEFAULT = 2 -- index into TOUR_SECONDS: 10 s
-- Saved views per savegame: 50 x { id, name (<= NAME_MAX characters), 5 numbers } is a few kB of GUI save data.
C.BOOKMARK_CAP = 50
C.NAME_MAX = 40
-- A flying aircraft (more than this above the ground) is followed instead of framed from the ground.
C.AIRBORNE_M = 40

-- Tour sources (checkboxes, several at once; round 3, 2026-10-13): random subjects, random places, saved views
-- (list order, a loop), the photographer's shots. The tour takes the ticked ones in turn, one per hop
-- (tourNextSource); at least one stays ticked (toggleSet). Each subject source cycles its own kinds.
C.TOUR_SOURCES = { "random", "places", "views", "shots" }
C.SOURCE_KINDS = {
	random = { "train", "town", "road", "station", "plane", "ship", "industry", "person" },
	places = { "place" },
	-- "saved": one of the player's saved views at random (round 8, user: "if you save a shot, that should count
	-- in the interesting shots pool"), one kind among the shots like any other
	shots = { "bridge", "viewpoint", "departure", "skyline", "rush", "tunnel", "water", "passing", "approach", "saved" },
}
C.DEFAULT_SOURCES = { random = true, places = true, views = false, shots = true }

-- Aerials (Aerials mode and the flights of Mixed): how long the drone flies over one area before it moves on to
-- a new one (Aerials) or back to the hops (Mixed), and what its waypoints are picked from (pm_world
-- flightCandidates). At least one subject stays ticked.
C.LEG_SECONDS = { 30, 60, 120, 300 }
C.LEG_DEFAULT = 2 -- 1 min
C.FLIGHT_SUBJECTS = { "towns", "landscape", "water", "rivers", "rail", "poi" }
C.DEFAULT_FLIGHT_SUBJECTS = { towns = true, landscape = true, water = true, rivers = true, rail = true, poi = true }

--- A copy of a set of ticked keys (sources or flight subjects).
function C.copySet(t)
	local o = {}
	for k, v in pairs(t or {}) do o[k] = v == true end
	return o
end

--- The ticked keys of `set`, in the order of `order`.
function C.ticked(set, order)
	local out = {}
	for __, k in ipairs(order) do if set ~= nil and set[k] == true then out[#out + 1] = k end end
	return out
end

--- Ticks / unticks `key` of `set` (a key of `order`). Refused (false, set unchanged) when it would leave no key
--- ticked, or for an unknown key.
function C.toggleSet(set, order, key, on)
	local known = false
	for __, k in ipairs(order) do if k == key then known = true end end
	if not known then return false end
	if not on then
		local n = 0
		for __, k in ipairs(order) do if k ~= key and set[k] == true then n = n + 1 end end
		if n == 0 then return false end
	end
	set[key] = on == true
	return true
end

--- The source of the next hop: the ticked source after `cur` (in TOUR_SOURCES order, wrapping), skipping the
--- keys in `skip` (sources that had nothing this hop). nil when none is left.
function C.tourNextSource(sources, cur, skip)
	local list = C.ticked(sources, C.TOUR_SOURCES)
	local n = #list
	if n == 0 then return nil end
	local start = 0
	for i, k in ipairs(list) do if k == cur then start = i end end
	for step = 1, n do
		local k = list[((start + step - 1) % n) + 1]
		if not (skip and skip[k]) then return k end
	end
	return nil
end

--- True when the saved views are the only ticked source (the tour then plays them in list order, no flights).
function C.viewsOnly(sources)
	local list = C.ticked(sources, C.TOUR_SOURCES)
	return #list == 1 and list[1] == "views"
end

--- Seconds of a flight leg for a choice index (anything else = the default).
function C.legSeconds(choice)
	return C.LEG_SECONDS[choice] or C.LEG_SECONDS[C.LEG_DEFAULT]
end

--- Water under a sampled point: "river" when it is narrow (land on both sides along one axis at `r` m), "water"
--- (sea, lake, coast) otherwise, nil on land. isWater(x, y) -> boolean. At most 5 calls.
function C.waterKind(isWater, x, y, r)
	if not isWater(x, y) then return nil end
	r = r or 150
	if (not isWater(x + r, y) and not isWater(x - r, y)) or (not isWater(x, y + r) and not isWater(x, y - r)) then
		return "river"
	end
	return "water"
end

-- "Anything": the subject kinds a random pick of any kind tries, with weights (weightedOrder). Kinds with nothing
-- on the map are skipped by the picker, so the weights share out among the kinds that exist. The scans of the
-- photographer's shots share one 35 ms budget per click (pm_world), so after the first scan kind the others
-- read almost nothing and the plain kinds follow.
C.ANY_KINDS = {
	{ "train", 3 }, { "road", 2.5 }, { "ship", 1.5 }, { "plane", 1 }, { "station", 1.5 }, { "town", 1.5 },
	{ "industry", 1 }, { "person", 1 }, { "place", 2 },
	{ "bridge", 1.2 }, { "viewpoint", 1 }, { "departure", 0.8 }, { "skyline", 0.8 }, { "rush", 0.8 },
	{ "tunnel", 0.6 }, { "water", 0.6 }, { "passing", 0.5 }, { "approach", 0.6 },
	-- round 8: the player's saved views, as strong as the best shots (none saved: skipped like any empty kind)
	{ "saved", 1.2 },
}

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
C.finite = finite

--- Angle wrapped into (-pi, pi]; 0 for NaN or an infinite angle (fmod would give NaN).
function C.wrapAngle(a)
	if not finite(a) then return 0 end
	local r = math.fmod(a + C.PI, C.TWO_PI)
	if r <= 0 then r = r + C.TWO_PI end
	return r - C.PI
end

--- Shortest signed difference b - a between two angles, in (-pi, pi].
function C.angleDiff(a, b)
	return C.wrapAngle(b - a)
end

--- v within lo..hi; NaN gives lo (every comparison with NaN is false, so it would pass through).
local function clamp(v, lo, hi)
	if v ~= v then return lo end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
C.clamp = clamp

--- The framing view of a subject of `kind` at (x, y); rand01 (0..1) picks the angle.
function C.frame(kind, x, y, rand01)
	local f = C.FRAMING[kind] or C.FRAMING.vehicle
	return { x = x, y = y, d = f.d, a = C.wrapAngle((rand01 or 0) * C.TWO_PI), p = f.p }
end

-- Tour framing of a random subject, by default between Eye level (25 m, 0.04 rad) and a bit wider than Low angle
-- (60 m, 0.12): up to 90 m and 0.20 rad. The tour's range options (tourRange) replace these bounds. `at` places
-- each kind in that range (0 = closest, 1 = widest); a random spread of +-SPREAD/2 around it varies the hops.
C.TOUR_FRAME = { dMin = 25, dMax = 90, pMin = 0.04, pMax = 0.20, spread = 0.3 }
C.TOUR_FRAME_AT = {
	person = 0.0, road = 0.2, tram = 0.25, vehicle = 0.3, train = 0.55, ship = 0.6, plane = 0.6,
	place = 0.7, station = 0.8, industry = 0.9, town = 1.0,
}

--- The tour's view of a subject of `kind` at (x, y), inside `range` ({ dMin, dMax, pMin, pMax }, default
--- C.TOUR_FRAME; distance geometric in the range, pitch linear); rnd: a function giving 0..1 (three draws:
--- distance, pitch, angle).
function C.tourFrame(kind, x, y, rnd, range)
	local f = C.TOUR_FRAME
	local r = range or f
	local at = C.TOUR_FRAME_AT[kind] or C.TOUR_FRAME_AT.vehicle
	local function spread() return clamp(at + (rnd() - 0.5) * f.spread, 0, 1) end
	local td, tp = spread(), spread()
	return {
		x = x, y = y,
		d = r.dMin * math.exp(math.log(r.dMax / r.dMin) * td),
		a = C.wrapAngle(rnd() * C.TWO_PI),
		p = r.pMin + (r.pMax - r.pMin) * tp,
	}
end

---------------------------------------------------------------------------
-- Tour options: camera range (view height and distance as preset steps) and modes (presets).

-- The steps of the range rows (1-based choice indices; the defaults = rev 1's tour framing).
-- "Horizon" (pitchTo 4, user feedback 2026-10-13): the highest view stays nearly level; with Closest 1000 m and
-- Farthest 3500 m the tour then flies high and looks across the landscape (eye 40-300 m up).
C.RANGE = {
	pitchFrom = { 0.04, 0.12, 0.45 },     -- Eye level, Low angle, Drone
	pitchTo = { 0.20, 0.70, 1.30, 0.09 }, -- Low angle (a bit wider), Drone, Bird's eye (= the shot), Horizon
	distFrom = { 25, 60, 150, 1000 },     -- m
	distTo = { 90, 350, 900, 3500 },      -- m
}
C.RANGE_DEFAULT = { pf = 1, pt = 1, df = 1, dt = 1 }

--- A valid choice index 1..n (anything else: def).
local function choice(v, n, def)
	v = tonumber(v)
	if v == nil or v ~= v or v < 1 or v > n then return def end
	return math.floor(v)
end

--- The tour's camera range { dMin, dMax, pMin, pMax } for range choices sel ({ pf, pt, df, dt }); invalid
--- indices fall back to the defaults, a "from" above its "to" swaps, and everything stays inside C.SAFE.
function C.tourRange(sel)
	sel = type(sel) == "table" and sel or C.RANGE_DEFAULT
	local R, D = C.RANGE, C.RANGE_DEFAULT
	local pMin = R.pitchFrom[choice(sel.pf, #R.pitchFrom, D.pf)]
	local pMax = R.pitchTo[choice(sel.pt, #R.pitchTo, D.pt)]
	local dMin = R.distFrom[choice(sel.df, #R.distFrom, D.df)]
	local dMax = R.distTo[choice(sel.dt, #R.distTo, D.dt)]
	if pMin > pMax then pMin, pMax = pMax, pMin end
	if dMin > dMax then dMin, dMax = dMax, dMin end
	pMin, pMax = clamp(pMin, C.SAFE.pMin, C.SAFE.pMax), clamp(pMax, C.SAFE.pMin, C.SAFE.pMax)
	dMin, dMax = clamp(dMin, C.SAFE.dMin, C.MAX_DIST), clamp(dMax, C.SAFE.dMin, C.MAX_DIST)
	return { dMin = dMin, dMax = dMax, pMin = pMin, pMax = pMax }
end

-- Tour modes (presets): "ground" (hops at the ground range: rev 1's tour), "aerial" (a continuous drone flight,
-- pm_flight.lua), "mixed" (hops over a wider range with a flight leg every MIXED_FLIGHT_EVERY hops). Each sets
-- the range choices when picked; the player may change the range afterwards.
-- "place" (round 6): the camera centre at the start, toured from many angles within an area (pm_place.lua); its
-- pitch rows run from eye level to drone, its distances follow the area, not the distance rows.
-- "wander" (round 7): no cuts at all; the camera drifts around the place in the middle of the view for as long
-- as the tour runs (pm_flight.lua "Wander"), within the pitch rows and the Area.
C.TOUR_MODES = { "ground", "aerial", "mixed", "place", "wander" }
-- Round 13 (user: "Aerials should be the default mode"): the Tour tab starts in Aerials.
C.TOUR_MODE_DEFAULT = "aerial"
C.PRESETS = {
	ground = { pf = 1, pt = 1, df = 1, dt = 1 },
	aerial = { pf = 2, pt = 2, df = 2, dt = 2 },
	mixed = { pf = 1, pt = 2, df = 1, dt = 2 },
	place = { pf = 1, pt = 2, df = 1, dt = 1 },
	wander = { pf = 1, pt = 2, df = 1, dt = 1 },
}
C.MIXED_FLIGHT_EVERY = 3

--- The range choices of a mode's preset (a copy), the ground preset for an unknown mode.
function C.preset(mode)
	local p = C.PRESETS[mode] or C.PRESETS.ground
	return { pf = p.pf, pt = p.pt, df = p.df, dt = p.dt }
end

--- What a mode's tour does at hop number n (1-based): "flight" or "hop".
function C.hopKind(mode, n)
	if mode == "aerial" then return "flight" end
	if mode == "mixed" and n > 1 and (n - 1) % C.MIXED_FLIGHT_EVERY == 0 then return "flight" end
	return "hop"
end

---------------------------------------------------------------------------
-- The camera angle and the direction it looks. getCameraData's `angle` and the world heading the camera looks
-- along (eye -> centre) differ by a constant the driver measures in game (getEye / getCenter); until then it is
-- assumed 0. Framings name the look heading (pm_shots.lua); angleFor turns it into the camera angle.

function C.angleFor(look, offset)
	return C.wrapAngle((tonumber(look) or 0) - (tonumber(offset) or 0))
end

function C.lookOf(a, offset)
	return C.wrapAngle((tonumber(a) or 0) + (tonumber(offset) or 0))
end

--- The look offset measured from the camera's angle `a` and its eye and centre positions (the horizontal
--- eye -> centre direction); nil when they are too close (looking straight down) or not finite.
function C.measureLookOffset(a, ex, ey, cx, cy)
	local dx, dy = (cx or 0) - (ex or 0), (cy or 0) - (ey or 0)
	if not (finite(a) and finite(dx) and finite(dy)) or dx * dx + dy * dy < 1 then return nil end
	return C.wrapAngle(C.atan2(dy, dx) - a)
end

--- The eye's ground position of view v (x, y), given the look offset.
function C.eyeXY(v, offset)
	local look = C.lookOf(v.a, offset)
	local h = v.d * math.cos(v.p)
	return v.x - math.cos(look) * h, v.y - math.sin(look) * h
end

--- A pitch at least as steep as p that keeps the eye `margin` m above the ground under it: the eye sits
--- d * sin(p) above the centre's ground gCentre, the ground under the eye is gEye. Capped at 1.2 rad.
function C.clearPitch(d, p, gCentre, gEye, margin)
	if not (finite(d) and finite(p) and finite(gCentre) and finite(gEye)) or d <= 0 then return p end
	local need = gEye - gCentre + (margin or 10)
	if d * math.sin(p) >= need then return p end
	return math.max(p, math.min(1.2, math.asin(clamp(need / d, -1, 1))))
end

--- A random point inside bounds ({ minX, minY, maxX, maxY }) shrunk by `inset` (fraction a side); rnd 0..1.
function C.randomPoint(bounds, rnd, inset)
	if bounds == nil then return nil end
	inset = clamp(tonumber(inset) or 0, 0, 0.45)
	local w, h = bounds[3] - bounds[1], bounds[4] - bounds[2]
	return bounds[1] + w * (inset + (1 - 2 * inset) * rnd()), bounds[2] + h * (inset + (1 - 2 * inset) * rnd())
end

--- A shot preset around the current view: same centre and angle, the preset's distance and pitch.
function C.shot(cur, key)
	local s = C.SHOTS[key]
	if s == nil or cur == nil then return nil end
	return { x = cur.x, y = cur.y, d = s.d, a = cur.a, p = s.p }
end

--- The distance and pitch of a view whose eye is `h` m above its centre at pitch `p` (d = h / sin p), within
--- maxD (default C.ZOOM_LIMIT): past it the distance is maxD and the pitch asin(h / maxD), so the height is kept.
--- Returns d, p, clamped (true when the zoom limit changed it).
function C.horizonFrame(h, p, maxD)
	maxD = tonumber(maxD) or C.ZOOM_LIMIT
	h = clamp(tonumber(h) or 0, 1, maxD * 0.9)
	p = clamp(tonumber(p) or 0.1, 0.01, 1.2)
	local d = h / math.sin(p)
	if d <= maxD then return d, p, false end
	return maxD, math.asin(h / maxD), true
end

--- A horizon shot from the current view `cur`: the eye stays above cur's centre at h m (plus the ground
--- difference gDiff = ground under the eye - ground under the new centre, default 0), looking along cur's
--- heading (look offset `off`), the new centre d * cos(p) ahead. Returns the view, clamped (zoom limit) and
--- the distance wanted before the clamp. nil for an unknown key or no current view.
function C.horizonShot(cur, key, off, gDiff)
	local s = C.HORIZON_SHOTS[key]
	if s == nil or cur == nil then return nil end
	local h = s.h + (tonumber(gDiff) or 0)
	local want = math.max(1, h) / math.sin(s.p)
	local d, p, clamped = C.horizonFrame(h, s.p)
	local look = C.lookOf(cur.a, off)
	local ahead = d * math.cos(p)
	return { x = cur.x + math.cos(look) * ahead, y = cur.y + math.sin(look) * ahead, d = d, a = cur.a, p = p },
		clamped, want
end

-- Round 14 (user: "when toggling between shots, it would be nice if it always brought back to the same place. e.g.
-- I go to Eye level, then High horizon, then Eye level, and it's not where I started"): every shot preset is
-- framed from one ANCHOR (the centre and angle of the view the first shot started from), not from the current
-- view. Before, each shot took the current centre, and the horizon shots push their centre ahead along the
-- heading (C.horizonShot), so the next shot started from that pushed-ahead point: a new place every switch. The
-- anchor is kept while the camera still shows the view the last shot sent (centre within SHOT_ANCHOR_TOL, same
-- angle: a zoom or tilt of the player's keeps it), and taken anew when the player moved or turned the camera, or
-- after a jump, a tour, an orbit, a wander or a follow (the driver resets it).
C.SHOT_ANCHOR_TOL = { xy = 2, rel = 0.005, a = 0.01 }

--- The shot anchor for the shot about to be framed: `st` = { anchor = { x, y, a }, sent = { x, y, a } } (the
--- driver's state, nil = none), `cur` the view read now. Returns the anchor and why ("kept", "first", "camera
--- moved", "camera turned", or st.reset's reason). Never raises on nil / NaN (a broken read takes a new anchor
--- from cur; nil when cur itself is unusable).
function C.shotAnchor(st, cur)
	if cur == nil or not (finite(cur.x) and finite(cur.y) and finite(cur.a)) then return nil, "no view" end
	local fresh = { x = cur.x, y = cur.y, a = cur.a }
	if st == nil or st.anchor == nil or st.sent == nil then
		return fresh, (st ~= nil and st.reset) or "first"
	end
	local s, tol = st.sent, C.SHOT_ANCHOR_TOL
	if not (finite(s.x) and finite(s.y) and finite(s.a)) then return fresh, "no shot sent" end
	local dx, dy = cur.x - s.x, cur.y - s.y
	local lim = tol.xy + tol.rel * (finite(cur.d) and math.max(0, cur.d) or 0)
	if dx * dx + dy * dy > lim * lim then return fresh, "camera moved" end
	if math.abs(C.angleDiff(s.a, cur.a)) > tol.a then return fresh, "camera turned" end
	return st.anchor, "kept"
end

--- Smoothstep ease-in-out, t clamped to 0..1.
function C.ease(t)
	t = clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

--- Round 11: the quintic smootherstep, t clamped to 0..1: zero speed AND zero acceleration change at both ends,
--- so a glide between two MOVING end points (an Aerials flight) hands over with no jerk.
function C.ease5(t)
	t = clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

--- How far the camera rises mid-way through a glide: a third of the ground distance travelled, at most up to
--- MAX_DIST above the higher end. Short hops don't rise.
function C.glideBump(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	local travel = math.sqrt(dx * dx + dy * dy)
	local room = C.MAX_DIST - math.max(from.d, to.d)
	if room <= 0 then return 0 end
	return clamp(travel / 3, 0, room)
end

--- The view a fraction t (0..1, eased here) along a glide from `from` to `to`. Centre and pitch move linearly,
--- the distance geometrically (zooming feels even) plus a rise of `bump` m that peaks half-way, the angle the
--- short way round. `out` (optional, not `from` / `to`): a table to write into instead of a new one (the
--- driver's per-frame scratch view). quintic: the smootherstep (C.ease5) instead of the smoothstep.
function C.lerpView(from, to, t, bump, out, quintic)
	local e = quintic and C.ease5(t) or C.ease(t)
	local d0, d1 = math.max(from.d, C.MIN_DIST), math.max(to.d, C.MIN_DIST)
	local v = out or {}
	v.x = from.x + (to.x - from.x) * e
	v.y = from.y + (to.y - from.y) * e
	v.d = d0 * math.exp(math.log(d1 / d0) * e) + (bump or 0) * math.sin(C.PI * e)
	v.a = C.wrapAngle(from.a + C.angleDiff(from.a, to.a) * e)
	v.p = from.p + (to.p - from.p) * e
	-- the reference ground (eye space, pm_flight.lua): the eye's height follows it, never the terrain under the
	-- centre; nil when either end has none
	if from.g ~= nil and to.g ~= nil then v.g = from.g + (to.g - from.g) * e else v.g = nil end
	return v
end

-- What setCameraData is ever given (cam.safeView): distance and pitch ranges and a map bound for when the
-- terrain's bounding box is unknown. setCameraData has no documented limits (api/tealdef/api/gui.d.tl:436-438);
-- the camera eases back from distances past its zoom limit (docs/findings/map-camera.md "Camera zoom limit",
-- 20000 m tested), so a far bookmark is fine, but 0, negative, NaN or huge values are never sent.
C.SAFE = {
	dMin = 1, dMax = 20000,
	pMin = 0, pMax = C.PITCH_MAX, -- near straight down inverted the game's keys (PITCH_MAX); below the horizon never
	xyMax = 1e6, -- |x|, |y| without known map bounds
}

--- The five numbers to give setCameraData for view `v`: x, y clamped into `bounds` ({ minX, minY, maxX, maxY },
--- optional), distance and pitch into C.SAFE, the angle wrapped, every -0 made +0. nil when a field is missing
--- or not finite (NaN, inf): such a view is never sent. Returns numbers, not a table (called every frame).
function C.safeView(v, bounds)
	if v == nil then return nil end
	local x, y, d, a, p = v.x, v.y, v.d, v.a, v.p
	if not (finite(x) and finite(y) and finite(d) and finite(a) and finite(p)) then return nil end
	local S = C.SAFE
	if bounds ~= nil then
		x, y = clamp(x, bounds[1], bounds[3]), clamp(y, bounds[2], bounds[4])
	else
		x, y = clamp(x, -S.xyMax, S.xyMax), clamp(y, -S.xyMax, S.xyMax)
	end
	-- x + 0 turns -0 into +0 (docs/findings/roads.md "Negative zero": the engine kept -0 elsewhere)
	return x + 0, y + 0, clamp(d, S.dMin, S.dMax) + 0, C.wrapAngle(a) + 0, clamp(p, S.pMin, S.pMax) + 0
end

--- Map bounds { minX, minY, maxX, maxY } from a terrain bounding box (api.engine.terrain.getBoundingBox(): Box2f
--- min / max), or nil when it is unusable (missing, not finite, empty).
function C.boundsOf(bb)
	local ok, b = pcall(function()
		local t = { bb.min.x, bb.min.y, bb.max.x, bb.max.y }
		for i = 1, 4 do if not finite(t[i]) then return nil end end
		if t[3] <= t[1] or t[4] <= t[2] then return nil end
		return t
	end)
	return ok and b or nil
end

-- Aerials look (user feedback 2026-10-13): "down" (the drone looks at the path ahead, as before) or "horizon"
-- (it looks far ahead along its heading, nearly level: pm_flight.horizonView). Round 13: "high" (pm_flight.HIGH:
-- about 1 km up, the look-at point 1.6 km+ out, where the game keeps its centre at sea level whatever the ground,
-- so nothing under the look can jolt the eye; findings map-camera.md "Tour eye jolts from the game's centre").
C.AERIAL_LOOKS = { "down", "horizon", "high" }
-- Round 15 (user, session 2026-10-14_0658_session: "High should be default, but I like the other options"): the
-- Look a fresh session starts with. High is the one look the game's centre can't jolt (both 0633 High tours:
-- spikes=0, d2 max 0.35-0.51 m); Down and Horizon stay as options.
C.AERIAL_LOOK_DEFAULT = "high"

-- Mouse look during a flight (user feedback 2026-10-13): the player's turn / tilt / zoom is kept as an offset
-- on top of the flight's view instead of stopping the tour; only a pan stops it. LOOK_EPS: the smallest change
-- taken as input (the camera reads back what we set, so anything above rounding is the player).
C.LOOK_EPS = { a = 0.0005, p = 0.0005, dRel = 0.001 }

--- The player's input between the view we set last and the one read now, during a flight: pan (true, the tour
--- stops) when the centre moved more than MOVE_TOL.xy (or 2 % of the distance) without a zoom (a zoom towards the
--- cursor moves the centre too, so the centre is ignored in a zooming frame); else the turn (rad), tilt (rad)
--- and zoom (log of the distance ratio) to add to the look offset, 0 below LOOK_EPS. Never raises on nil / NaN.
function C.flightInput(last, cur)
	if last == nil or cur == nil then return false, 0, 0, 0 end
	if not (finite(cur.x) and finite(cur.y) and finite(cur.d) and finite(cur.a) and finite(cur.p)) then
		return false, 0, 0, 0
	end
	local e = C.LOOK_EPS
	local dz = 0
	if cur.d > 0 and last.d > 0 and math.abs(cur.d - last.d) > e.dRel * last.d then dz = math.log(cur.d / last.d) end
	if dz == 0 then
		local dx, dy = cur.x - last.x, cur.y - last.y
		local tol = math.max(C.MOVE_TOL.xy, 0.02 * last.d)
		if dx * dx + dy * dy > tol * tol then return true, 0, 0, 0 end
	end
	local da = C.angleDiff(last.a, cur.a)
	if math.abs(da) <= e.a then da = 0 end
	local dp = cur.p - last.p
	if math.abs(dp) <= e.p then dp = 0 end
	return false, da, dp, dz
end

-- Tolerances for "the player moved the camera" (between our last setCameraData and the next frame's read).
C.MOVE_TOL = { xy = 5, dRel = 0.03, a = 0.03, p = 0.03 }

--- True (and the reason) when `cur` differs from the view we set last more than the tolerances: the player
--- panned, zoomed, turned or tilted. ignoreCenter: the camera follows an entity, so its centre moves by itself.
function C.userMoved(last, cur, ignoreCenter)
	if last == nil or cur == nil then return false, nil end
	local tol = C.MOVE_TOL
	if not ignoreCenter then
		local dx, dy = cur.x - last.x, cur.y - last.y
		if dx * dx + dy * dy > tol.xy * tol.xy then return true, "pan" end
	end
	if math.abs(cur.d - last.d) > tol.dRel * math.max(last.d, 1) then return true, "zoom" end
	if math.abs(C.angleDiff(last.a, cur.a)) > tol.a then return true, "turn" end
	if math.abs(cur.p - last.p) > tol.p then return true, "tilt" end
	return false, nil
end

--- The orbit's next view: the current view turned by speed * dt (dt in seconds, capped so a hitch can't jump).
--- `out` (optional, may be `cur`): a table to write into instead of a new one.
function C.orbitStep(cur, dt, speed, out)
	dt = clamp(tonumber(dt) or 0, 0, 0.1)
	local v = out or {}
	v.x, v.y, v.d, v.p = cur.x, cur.y, cur.d, cur.p
	v.a = C.wrapAngle(cur.a + (speed or C.ORBIT_RAD_PER_S) * dt)
	return v
end

--- Keys of `weighted` ({ { key, weight }, ... }) in a random order where heavier keys tend to come first
--- (weighted sampling without replacement); keys with a weight <= 0 (or not a number) are left out.
function C.weightedOrder(weighted, rnd)
	local pool = {}
	for __, kw in ipairs(weighted or {}) do
		local w = tonumber(kw[2])
		if w ~= nil and w > 0 and w == w and w ~= math.huge then pool[#pool + 1] = { kw[1], w } end
	end
	local out = {}
	while #pool > 0 do
		local total = 0
		for __, kw in ipairs(pool) do total = total + kw[2] end
		local r = rnd() * total
		local pick = #pool
		for i, kw in ipairs(pool) do
			r = r - kw[2]
			if r < 0 then pick = i break end
		end
		out[#out + 1] = pool[pick][1]
		table.remove(pool, pick)
	end
	return out
end

--- A small deterministic random generator (no math.randomseed: the GUI Lua state may be shared). Returns a
--- function giving numbers in [0, 1).
function C.newRng(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if s == 0 then s = 1 end
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

--- A random item of `list` (1..#list) that `accept` (optional) takes, trying at most maxTries random slots.
--- Returns the item (nil when none was accepted) and the number of tries.
function C.pickRandom(list, rnd, accept, maxTries)
	local n = list and #list or 0
	if n == 0 then return nil, 0 end
	maxTries = maxTries or 1
	for i = 1, maxTries do
		local item = list[math.floor(rnd() * n) + 1]
		if item ~= nil and (accept == nil or accept(item)) then return item, i end
	end
	return nil, maxTries
end

--- A time-budgeted walk over a list of n items that continues where the previous call stopped: visits the
--- 1-based indices start+1 .. n, then 1 .. start (start 0-based, taken modulo n), until visit(i) returns true
--- (found, stop) or over() returns true (budget spent; checked after each visit, so at least one item is
--- visited). Returns the 0-based start for the next call (just after the last visited item) and the number of
--- items visited. A full round returns `start` itself.
function C.budgetedWalk(n, start, visit, over)
	if n == nil or n <= 0 then return 0, 0 end
	start = math.floor(start or 0) % n
	for k = 0, n - 1 do
		local i = (start + k) % n + 1
		if visit(i) or (over ~= nil and over()) then return i % n, k + 1 end
	end
	return start, n
end

--- The item with the highest score(item) (nil scores skipped), and that score.
function C.maxBy(list, score)
	local best, bestScore = nil, nil
	for __, item in ipairs(list or {}) do
		local s = score(item)
		if s ~= nil and (bestScore == nil or s > bestScore) then best, bestScore = item, s end
	end
	return best, bestScore
end

--- True when a point at height z is more than AIRBORNE_M above the ground height.
function C.isAirborne(z, ground)
	if z == nil or ground == nil then return false end
	return z - ground > C.AIRBORNE_M
end

--- The tour's next index after `idx` in a list of n (wraps).
function C.tourNext(idx, n)
	if n == nil or n <= 0 then return nil end
	return ((idx or 0) % n) + 1
end

--- The tour interval in seconds for a choice index (1-based into TOUR_SECONDS; anything else = the default).
function C.tourSeconds(choice)
	return C.TOUR_SECONDS[choice] or C.TOUR_SECONDS[C.TOUR_DEFAULT]
end

---------------------------------------------------------------------------
-- Bookmarks: a list of { id, name, x, y, d, a, p } in the player's order (the saved-views tour plays it in that
-- order). id: a growing number, never reused, shown as "View <id>" while name is nil (name: set by a rename,
-- cleanName). At most BOOKMARK_CAP, stored per savegame as GUI save data { v = 1, views = list }
-- (gui/pm_window.lua).

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

--- A view name as typed: ASCII control characters (line breaks, tabs) become spaces, runs of spaces one,
--- trimmed, cut to NAME_MAX characters (UTF-8 aware: never inside a character). nil for an empty name or a
--- non-string (the view then shows its default "View <id>"). Byte by byte on purpose: the pattern classes %c /
--- %s follow the C locale and in a Latin-1 one match UTF-8 continuation bytes (0x85, 0x97, 0xA0).
function C.cleanName(s)
	if type(s) ~= "string" then return nil end
	local out, chars, pendingSpace = {}, 0, false
	for i = 1, #s do
		local b = s:byte(i)
		if b <= 32 or b == 127 then
			pendingSpace = #out > 0
		else
			local lead = b < 128 or b >= 192 -- not a UTF-8 continuation byte: a new character starts
			if lead then
				local need = pendingSpace and 2 or 1
				if chars + need > C.NAME_MAX then break end
				if pendingSpace then
					out[#out + 1] = " "
					chars = chars + 1
				end
				chars = chars + 1
				pendingSpace = false
			end
			out[#out + 1] = string.char(b)
		end
	end
	if #out == 0 then return nil end
	return table.concat(out)
end

--- A clean copy of saved bookmark data (anything malformed is dropped, as are repeated ids; at most
--- BOOKMARK_CAP, the first ones; names through cleanName).
function C.readBookmarks(data)
	local out = {}
	local seen = {}
	local ok = pcall(function()
		if type(data) ~= "table" or type(data.views) ~= "table" then return end
		for __, b in ipairs(data.views) do
			if #out >= C.BOOKMARK_CAP then break end
			if type(b) == "table" then
				local id, x, y, d, a, p = num(b.id), num(b.x), num(b.y), num(b.d), num(b.a), num(b.p)
				if id and x and y and d and a and p then
					id = math.floor(id)
					if not seen[id] then
						seen[id] = true
						out[#out + 1] = { id = id, name = C.cleanName(b.name), x = x, y = y, d = d, a = a, p = p }
					end
				end
			end
		end
	end)
	if not ok then return {} end
	return out
end

local function copyBookmark(b)
	return { id = b.id, name = b.name, x = b.x, y = b.y, d = b.d, a = b.a, p = b.p }
end

--- The save data table for a bookmark list.
function C.bookmarkData(list)
	local views = {}
	for i, b in ipairs(list) do views[i] = copyBookmark(b) end
	return { v = 1, views = views }
end

--- A new list with `view` appended under the next id; the list itself when it is full (second result false).
function C.addBookmark(list, view)
	if #list >= C.BOOKMARK_CAP or view == nil then return list, false end
	local nextId = 1
	for __, b in ipairs(list) do if b.id >= nextId then nextId = b.id + 1 end end
	local out = {}
	for i, b in ipairs(list) do out[i] = b end
	out[#out + 1] = { id = nextId, x = view.x, y = view.y, d = view.d, a = view.a, p = view.p }
	return out, true
end

--- A new list without the bookmark `id`.
function C.removeBookmark(list, id)
	local out = {}
	for __, b in ipairs(list) do if b.id ~= id then out[#out + 1] = b end end
	return out
end

--- The bookmark with `id` and its index, or nil.
function C.findBookmark(list, id)
	for i, b in ipairs(list) do if b.id == id then return b, i end end
	return nil, nil
end

--- A new list with bookmark `id` moved by delta places (-1 up, +1 down), clamped to the list ends. Second
--- result: true when the order changed.
function C.moveBookmark(list, id, delta)
	local __, i = C.findBookmark(list, id)
	if i == nil then return list, false end
	local j = math.max(1, math.min(#list, i + math.floor(tonumber(delta) or 0)))
	if j == i then return list, false end
	local out = {}
	for k, b in ipairs(list) do out[k] = b end
	local b = table.remove(out, i)
	table.insert(out, j, b)
	return out, true
end

--- A new list with bookmark `id` renamed (cleanName; an empty name goes back to the default). Second result:
--- true when the name changed.
function C.renameBookmark(list, id, name)
	local __, i = C.findBookmark(list, id)
	if i == nil then return list, false end
	local clean = C.cleanName(name)
	if clean == list[i].name then return list, false end
	local out = {}
	for k, b in ipairs(list) do out[k] = b end
	local renamed = copyBookmark(list[i])
	renamed.name = clean
	out[i] = renamed
	return out, true
end

--- "x,y,d,a,p" for log lines.
function C.viewText(v)
	if v == nil then return "-" end
	return string.format("%.0f,%.0f,%.0f,%.3f,%.3f", v.x, v.y, v.d, v.a, v.p)
end

return C
