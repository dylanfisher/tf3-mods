-- Photo Mode: the photographer's shots, the pure part (no api calls): scoring and framing of the "Interesting"
-- subjects (train on a bridge, crossing water, trains passing, tunnel portal, landing / take-off, busy street,
-- skyline, viewpoint, train at a platform, oldest / fastest / longest vehicle). Detection (the budgeted scans
-- that read the engine) lives in gui/pm_world.lua; the driver turns a framing into a camera view
-- (gui/pm_driver.lua). Offline tests: tests/square_photo_mode/test_shots.lua. Plain Lua, pre-5.3.
--
-- A framing is a plain table { x, y, d, p, look }: the camera centre on the ground (x, y), distance d (m),
-- pitch p (radians down from the horizon) and `look`, the world heading the camera looks along (radians,
-- atan2(dy, dx) of the eye -> centre direction). The camera's own `angle` field relates to `look` by a constant
-- offset the driver measures in game (getEye / getCenter, pm_driver "look calibration"), so these framings
-- never guess the engine's angle convention. The eye sits at centre - (cos look, sin look) * d * cos p, at
-- d * sin p above the centre's ground.
--
-- PLAN: plans/square_photo_mode/PLAN.md "Interesting shots".

local SH = {}

local PI = math.pi
-- the game's Lua has math.atan2; Lua 5.3+ (offline tests) only math.atan(y, x)
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local TWO_PI = 2 * math.pi

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
SH.finite = finite

local function clamp(v, lo, hi)
	if v ~= v then return lo end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end
SH.clamp = clamp

local function wrap(a)
	if not finite(a) then return 0 end
	local r = math.fmod(a + PI, TWO_PI)
	if r <= 0 then r = r + TWO_PI end
	return r - PI
end
SH.wrap = wrap

--- Heading (radians) of the vector (dx, dy); 0 for a zero vector.
function SH.heading(dx, dy)
	if not finite(dx) or not finite(dy) or (dx == 0 and dy == 0) then return 0 end
	return atan2(dy, dx)
end

--- Pitch for an eye `h` m above the centre's ground at distance d: asin(h / d), within lo .. hi.
function SH.pitchFor(h, d, lo, hi)
	if not finite(h) or not finite(d) or d <= 0 then return lo end
	return clamp(math.asin(clamp(h / d, -1, 1)), lo, hi)
end

-- The tuning of every shot (distances in m, pitches in radians). One table, so a game test can tune it in one place.
SH.T = {
	bridge = { dMin = 90, dMax = 400, dPerH = 2.5, eyeFrac = 0.4, eyeMin = 3, pMin = 0.02, pMax = 0.25, great = 40 },
	water = { d = 160, eyeFrac = 0.3, eyeMin = 12, pMin = 0.04, pMax = 0.2 },
	passing = { maxSep = 150, minSpeed = 3, dMin = 90, dMax = 300, dPerSep = 1.3, dAdd = 70, p = 0.12 },
	tunnel = { maxDist = 250, out = 25, d = 80, p = 0.12, yaw = 0.35 },
	approach = { hMin = 15, hMax = 400, dAhead = 5, aheadMin = 150, aheadMax = 600, d = 140, p = 0.03 },
	rush = { cell = 150, minCount = 4, d = 90, p = 0.08, yaw = 0.2 },
	skyline = { r = 1100, dirs = 16, hAbove = 25, pMin = 0.02, pMax = 0.1, maxRise = 30 },
	viewpoint = { radii = { 700, 1200 }, dirs = 12, minRise = 40, hAbove = 30, waterBonus = 20, towns = 4 },
	departure = { maxSpeed = 0.5, dBase = 50, dPerPart = 6, dMin = 60, dMax = 180, p = 0.10, yaw = 0.25, departBonus = 10 },
	oldest = { dScale = 0.8, p = 0.12, yaw = 0.4 },
	fastest = { p = 0.08, yaw = 0.5 },
	longest = { dBase = 60, dPerPart = 8, dMin = 90, dMax = 320, p = 0.14, yaw = 0.3 },
}

---------------------------------------------------------------------------
-- Scores (higher = better; nil = not this shot)

--- Train on a bridge: the deck height above the terrain under it counts most, a little for any bridge.
--- Returns the score and true when the bridge is high enough to stop the scan at once.
function SH.bridgeScore(height)
	if not finite(height) then return nil end
	local h = math.max(0, height)
	return 1 + h, h >= SH.T.bridge.great
end

--- A vehicle on a bridge over water: any such bridge, higher ones a little better.
function SH.waterScore(onBridge, onWater, height)
	if not onBridge or not onWater then return nil end
	return 1 + math.max(0, tonumber(height) or 0) / 100
end

--- Tunnel portal: edge types of the edge a train is on and of its neighbour on the path, and the train's
--- distance to the portal between them. nil unless exactly one of the two is a tunnel and the train is near.
--- outside: the train is on the open edge (entering or just out), worth more than one still inside.
function SH.tunnelScore(curTunnel, nbTunnel, dist, outside)
	if curTunnel == nbTunnel or not finite(dist) then return nil end
	if dist > SH.T.tunnel.maxDist then return nil end
	return (outside and 2 or 1) + (SH.T.tunnel.maxDist - dist) / SH.T.tunnel.maxDist
end

--- Landing / take-off: flight state rank (3 take-off or landing, 2 approach, else nil) and the height above the
--- ground (lower is better, within hMin .. hMax).
function SH.approachScore(rank, height)
	local t = SH.T.approach
	if rank == nil or rank < 2 or not finite(height) or height < t.hMin or height > t.hMax then return nil end
	return rank + (t.hMax - height) / t.hMax
end

--- Train at a platform: standing (speed below maxSpeed) and loading / unloading / departing; longer trains and
--- departing ones first.
function SH.departureScore(speed, loading, departing, parts)
	if not loading or not finite(speed) or speed > SH.T.departure.maxSpeed then return nil end
	return (tonumber(parts) or 1) + (departing and SH.T.departure.departBonus or 0)
end

--- Oldest vehicle: the model's first year (0 / missing = unknown, skipped). Higher score = older.
function SH.oldestScore(year)
	if not finite(year) or year <= 0 then return nil end
	return -year
end

---------------------------------------------------------------------------
-- Pair and cluster searches over points { x, y, ... } (no api; the scan collects the points)

--- The closest pair of points within maxDist (grid bins of maxDist, so not quadratic). Returns a, b, distance
--- or nil. `accept(a, b)` (optional) can refuse a pair (the same vehicle).
function SH.closestPair(points, maxDist, accept)
	if points == nil or #points < 2 or not finite(maxDist) or maxDist <= 0 then return nil end
	local cells = {}
	local function key(cx, cy) return cx .. ":" .. cy end
	for i, pt in ipairs(points) do
		if finite(pt.x) and finite(pt.y) then
			local k = key(math.floor(pt.x / maxDist), math.floor(pt.y / maxDist))
			local c = cells[k]
			if c == nil then c = {} cells[k] = c end
			c[#c + 1] = i
		end
	end
	local bestA, bestB, bestD = nil, nil, nil
	for i, pt in ipairs(points) do
		if finite(pt.x) and finite(pt.y) then
			local cx, cy = math.floor(pt.x / maxDist), math.floor(pt.y / maxDist)
			for ox = -1, 1 do
				for oy = -1, 1 do
					local c = cells[key(cx + ox, cy + oy)]
					if c ~= nil then
						for __, j in ipairs(c) do
							if j > i then
								local q = points[j]
								local dx, dy = q.x - pt.x, q.y - pt.y
								local d = math.sqrt(dx * dx + dy * dy)
								if d <= maxDist and (bestD == nil or d < bestD) and (accept == nil or accept(pt, q)) then
									bestA, bestB, bestD = pt, q, d
								end
							end
						end
					end
				end
			end
		end
	end
	if bestA == nil then return nil end
	return bestA, bestB, bestD
end

--- The grid cell (size `cell` m) holding the most points: its points (a list), their mean x, y and count.
--- Two grids, the second shifted by half a cell, so a cluster on a cell border is not split. nil when no cell
--- has minCount points.
function SH.densestCell(points, cell, minCount)
	if points == nil or not finite(cell) or cell <= 0 then return nil end
	local best = nil
	for __, shift in ipairs({ 0, cell / 2 }) do
		local cells, order = {}, {}
		for __, pt in ipairs(points) do
			if finite(pt.x) and finite(pt.y) then
				local k = math.floor((pt.x + shift) / cell) .. ":" .. math.floor((pt.y + shift) / cell)
				local c = cells[k]
				if c == nil then c = {} cells[k] = c order[#order + 1] = k end
				c[#c + 1] = pt
			end
		end
		for __, k in ipairs(order) do
			if best == nil or #cells[k] > #best then best = cells[k] end
		end
	end
	if best == nil or #best < (minCount or 1) then return nil end
	local sx, sy = 0, 0
	for __, pt in ipairs(best) do sx, sy = sx + pt.x, sy + pt.y end
	return best, sx / #best, sy / #best, #best
end

--- The main direction (radians, in (-pi/2, pi/2]) of a set of points (principal axis of their spread): a street
--- full of vehicles lies along it. 0 for fewer than two distinct points.
function SH.mainAxis(points)
	local n = points and #points or 0
	if n < 2 then return 0 end
	local mx, my = 0, 0
	for __, pt in ipairs(points) do mx, my = mx + pt.x, my + pt.y end
	mx, my = mx / n, my / n
	local sxx, syy, sxy = 0, 0, 0
	for __, pt in ipairs(points) do
		local dx, dy = pt.x - mx, pt.y - my
		sxx, syy, sxy = sxx + dx * dx, syy + dy * dy, sxy + dx * dy
	end
	if sxx + syy == 0 then return 0 end
	return 0.5 * atan2(2 * sxy, sxx - syy)
end

--- Skyline: the best of `samples` ({ dir, water, rise }: the direction from the town to a point on a ring, water
--- there, its ground minus the town's). Water first, then a point not much higher than the town (a low view);
--- nil when none is usable.
function SH.pickSkyline(samples)
	local best, bestScore = nil, nil
	for __, s in ipairs(samples or {}) do
		if finite(s.dir) and finite(s.rise) then
			local score = (s.water and 2 or 0) + (s.rise <= SH.T.skyline.maxRise and 1 or 0) - math.abs(s.rise) / 1000
			if bestScore == nil or score > bestScore then best, bestScore = s, score end
		end
	end
	return best
end

--- Viewpoint: the sample ({ x, y, rise, water, town }) with the highest rise above its town (plus a bonus when
--- water lies between), nil when none rises at least minRise.
function SH.pickViewpoint(samples)
	local t = SH.T.viewpoint
	local best, bestScore = nil, nil
	for __, s in ipairs(samples or {}) do
		if finite(s.rise) and s.rise >= t.minRise then
			local score = s.rise + (s.water and t.waterBonus or 0)
			if bestScore == nil or score > bestScore then best, bestScore = s, score end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Framings (each returns { x, y, d, p, look } or nil)

local function framing(x, y, d, p, look)
	if not (finite(x) and finite(y) and finite(d) and finite(p) and finite(look)) then return nil end
	return { x = x, y = y, d = d, p = p, look = wrap(look) }
end
SH.framing = framing

--- Side-on to a track heading, from one side or the other (side: 1 or -1), turned `yaw` towards the front.
local function sideLook(heading, side, yaw)
	return heading + (side < 0 and -1 or 1) * (PI / 2) - (side < 0 and -1 or 1) * (yaw or 0)
end
SH.sideLook = sideLook

--- Train on a bridge: side-on, from below or level with the deck (the eye at eyeFrac of the deck height above
--- the ground under the train), further away for higher bridges. height: deck above the ground.
function SH.frameBridge(x, y, heading, height, side)
	local t = SH.T.bridge
	local h = math.max(0, tonumber(height) or 0)
	local d = clamp(t.dMin + t.dPerH * h, t.dMin, t.dMax)
	local p = SH.pitchFor(math.max(t.eyeMin, t.eyeFrac * h), d, t.pMin, t.pMax)
	return framing(x, y, d, p, sideLook(heading, side, 0))
end

--- Crossing water: side-on, low over the water.
function SH.frameWater(x, y, heading, height, side)
	local t = SH.T.water
	local eye = math.max(t.eyeMin, t.eyeFrac * math.max(0, tonumber(height) or 0))
	return framing(x, y, t.d, SH.pitchFor(eye, t.d, t.pMin, t.pMax), sideLook(heading, side, 0))
end

--- Two trains passing: centred between them, side-on to the first one's heading, wide enough for both.
function SH.framePassing(a, b, heading, side)
	local t = SH.T.passing
	local dx, dy = b.x - a.x, b.y - a.y
	local sep = math.sqrt(dx * dx + dy * dy)
	local d = clamp(sep * t.dPerSep + t.dAdd, t.dMin, t.dMax)
	return framing((a.x + b.x) / 2, (a.y + b.y) / 2, d, t.p, sideLook(heading, side, 0))
end

--- Tunnel portal at (px, py); (ox, oy): a point on the open track outside it. The camera stands outside, along
--- the track, looking into the portal at three-quarter angle (side: which way).
function SH.frameTunnel(px, py, ox, oy, side)
	local t = SH.T.tunnel
	local dx, dy = ox - px, oy - py
	local len = math.sqrt(dx * dx + dy * dy)
	if not finite(len) or len <= 0 then return nil end
	local ux, uy = dx / len, dy / len
	local inward = SH.heading(-ux, -uy) -- outside -> portal
	return framing(px + ux * t.out, py + uy * t.out, t.d, t.p, inward + (side < 0 and -1 or 1) * t.yaw)
end

--- Landing / take-off: the camera on the ground ahead of the aircraft, looking back along its path, so it
--- passes overhead. (vx, vy): its horizontal velocity.
function SH.frameApproach(x, y, vx, vy)
	local t = SH.T.approach
	local speed = math.sqrt((vx or 0) ^ 2 + (vy or 0) ^ 2)
	if not finite(speed) or speed < 1 then return nil end
	local ux, uy = vx / speed, vy / speed
	local ahead = clamp(speed * t.dAhead, t.aheadMin, t.aheadMax)
	return framing(x + ux * ahead, y + uy * ahead, t.d, t.p, SH.heading(-ux, -uy))
end

--- Busy street: low, down the street (its main axis), a little off the axis.
function SH.frameRush(mx, my, axis, flip)
	local t = SH.T.rush
	return framing(mx, my, t.d, t.p, axis + (flip and PI or 0) + t.yaw)
end

--- Skyline: the town centre seen from the ring point in direction `dir` (from the town), radius r, the eye
--- hAbove m above that point's ground (rise: its ground minus the town's).
function SH.frameSkyline(tx, ty, dir, rise)
	local t = SH.T.skyline
	local eye = (tonumber(rise) or 0) + t.hAbove
	return framing(tx, ty, t.r, clamp(atan2(eye, t.r), t.pMin, t.pMax), dir + PI)
end

--- Viewpoint: from the high point (hx, hy), rise m above the town at (tx, ty), looking down at the town.
function SH.frameViewpoint(tx, ty, hx, hy, rise)
	local t = SH.T.viewpoint
	local dx, dy = tx - hx, ty - hy
	local L = math.sqrt(dx * dx + dy * dy)
	if not finite(L) or L <= 0 then return nil end
	local eye = math.max(0, tonumber(rise) or 0) + t.hAbove
	return framing(tx, ty, math.sqrt(L * L + eye * eye), atan2(eye, L), SH.heading(dx, dy))
end

--- Train at a platform: along the platform (the track heading), a little to the side, wider for long trains.
function SH.frameDeparture(x, y, heading, parts, side)
	local t = SH.T.departure
	local d = clamp(t.dBase + t.dPerPart * (tonumber(parts) or 1), t.dMin, t.dMax)
	return framing(x, y, d, t.p, heading + (side < 0 and -1 or 1) * t.yaw)
end

--- A vehicle seen three-quarter side-on at a given distance (oldest, longest).
function SH.frameVehicle(x, y, heading, d, p, yaw, side)
	return framing(x, y, d, p, sideLook(heading, side, yaw))
end

--- Longest train: side-on, the distance grows with the number of parts.
function SH.frameLongest(x, y, heading, parts, side)
	local t = SH.T.longest
	local d = clamp(t.dBase + t.dPerPart * (tonumber(parts) or 1), t.dMin, t.dMax)
	return SH.frameVehicle(x, y, heading, d, t.p, t.yaw, side)
end

--- Fastest vehicle: low, ahead of it at an angle, so it comes towards the camera (the driver follows it).
function SH.frameFastest(x, y, heading, d, side)
	local t = SH.T.fastest
	return framing(x, y, d, t.p, heading + PI + (side < 0 and -1 or 1) * t.yaw)
end

return SH
