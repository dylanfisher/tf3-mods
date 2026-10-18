-- Photo Mode: the "This place" tour, the pure part (no api calls; plans/square_photo_mode/PLAN.md "Rev 1 feedback
-- round 6" 2). The place is the camera centre when the tour starts; the tour stays around it until stopped:
-- one shot per hop from many angles within a short distance.
--
--   heading   the circle is cut into SECTORS slices; each round visits every slice once in a shuffled order
--             (a new round never starts with the slice the last one ended on or its neighbours), a random
--             offset inside the slice. So the camera goes all the way around, in a random-ish order.
--   pitch     inside the tour's pitch rows (range.pMin .. range.pMax, eye level to drone by default): each
--             round cycles a shuffled order of three bands (low / middle / high third of the range).
--   distance  a place point: max(25, 0.2 r) .. 1.2 r; a nearby subject: max(15, 0.08 r) .. max(45, 0.5 r);
--             geometric (more close shots than far ones), within cam.SAFE / cam.MAX_DIST.
--   target    a nearby subject (vehicle, person, building, station within the radius, pm_world.nearby) for
--             about SUBJECT_SHARE of the shots when there are any, else a random point within PLACE_SPREAD r of
--             the place (uniform over the disc).
-- Plain Lua, pre-5.3. Offline tests: tests/square_photo_mode/test_place.lua.

local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"

local P = {}

-- "Area" choices (radius in m): Small, Medium, Large. Default Medium.
P.AREAS = { 80, 250, 600 }
P.AREA_DEFAULT = 2
P.SECTORS = 8
P.SUBJECT_SHARE = 0.5
P.PLACE_SPREAD = 0.6 -- random place points lie within this share of the radius
P.SUBJECT_SLACK = 1.3 -- a moving subject may have left the radius a little since the list was made
P.REFRESH_HOPS = 6 -- the nearby subjects are looked up again every this many hops (vehicles move)

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clamp(v, lo, hi)
	if v ~= v then return lo end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

--- The radius of an "Area" choice (1-based; anything else: the default).
function P.radius(choice)
	choice = tonumber(choice)
	if choice == nil or choice ~= choice or choice < 1 or choice > #P.AREAS then choice = P.AREA_DEFAULT end
	return P.AREAS[math.floor(choice)]
end

--- 1..n in a random order (Fisher-Yates with rnd 0..1).
local function shuffled(n, rnd)
	local t = {}
	for i = 1, n do t[i] = i end
	for i = n, 2, -1 do
		local j = math.min(i, math.floor(rnd() * i) + 1)
		t[i], t[j] = t[j], t[i]
	end
	return t
end
P.shuffled = shuffled

--- True when sectors a and b (1..n) are the same or neighbours on the circle.
local function near(a, b, n)
	if a == nil or b == nil then return false end
	local d = math.abs(a - b) % n
	return d <= 1 or d >= n - 1
end

--- A new plan for the place (x, y) with radius r; nil when the centre or radius isn't finite.
function P.newPlan(x, y, r, rnd)
	if not (finite(x) and finite(y) and finite(r)) or r <= 0 then return nil end
	return { x = x, y = y, r = r, order = shuffled(P.SECTORS, rnd), i = 0, bands = shuffled(3, rnd), bi = 0,
		last = nil, n = 0, si = 0 }
end

--- The next heading slice (1..SECTORS): every slice once per round; a new round avoids the last slice and its
--- neighbours as its first one (up to 8 reshuffles, then whatever came).
function P.nextSector(plan, rnd)
	plan.i = plan.i + 1
	if plan.i > #plan.order then
		local order = shuffled(P.SECTORS, rnd)
		for __ = 1, 8 do
			if not near(order[1], plan.last, P.SECTORS) then break end
			order = shuffled(P.SECTORS, rnd)
		end
		plan.order = order
		plan.i = 1
	end
	plan.last = plan.order[plan.i]
	return plan.last
end

--- The next pitch band (1 low, 2 middle, 3 high third of the range), a shuffled order per three shots.
function P.nextBand(plan, rnd)
	plan.bi = plan.bi + 1
	if plan.bi > #plan.bands then
		plan.bands = shuffled(3, rnd)
		plan.bi = 1
	end
	return plan.bands[plan.bi]
end

--- True when (x, y) lies within `slack` (default 1) times the plan's radius from the place.
function P.inside(plan, x, y, slack)
	if not (finite(x) and finite(y)) then return false end
	local dx, dy = x - plan.x, y - plan.y
	local lim = plan.r * (slack or 1)
	return dx * dx + dy * dy <= lim * lim
end

--- A random point within PLACE_SPREAD of the radius around the place (uniform over the disc).
function P.placePoint(plan, rnd)
	local rr = plan.r * P.PLACE_SPREAD * math.sqrt(rnd())
	local t = rnd() * cam.TWO_PI
	return plan.x + rr * math.cos(t), plan.y + rr * math.sin(t)
end

--- The distance range of a shot: a nearby subject is framed closer than a place point.
function P.distRange(r, isSubject)
	if isSubject then return math.max(15, 0.08 * r), math.max(45, 0.5 * r) end
	return math.max(25, 0.2 * r), math.max(40, 1.2 * r)
end

--- The target of the next shot: one of `subjects` ({ x, y, ... }, positions refreshed by the caller) inside the
--- radius (with SUBJECT_SLACK) for about SUBJECT_SHARE of the shots, else nil (a place point). Subjects are
--- taken in a shuffled order, so each comes up before any repeats.
function P.pickSubject(plan, subjects, rnd)
	local n = type(subjects) == "table" and #subjects or 0
	if n == 0 or rnd() >= P.SUBJECT_SHARE then return nil end
	if plan.subjectOrder == nil or #plan.subjectOrder ~= n or plan.si >= n then
		plan.subjectOrder = shuffled(n, rnd)
		plan.si = 0
	end
	for __ = 1, n do
		plan.si = plan.si + 1
		if plan.si > n then break end
		local s = subjects[plan.subjectOrder[plan.si]]
		if s ~= nil and P.inside(plan, s.x, s.y, P.SUBJECT_SLACK) then return s end
	end
	return nil
end

--- The next shot of the plan: a view { x, y, d, a, p } (the centre on the target, the angle from the next
--- heading slice, pitch inside range.pMin .. pMax from the next band, distance from distRange), plus the target
--- (nil for a place point). range: cam.tourRange(...) (pMin, pMax used).
function P.shot(plan, range, rnd, target)
	local sector = P.nextSector(plan, rnd)
	local band = P.nextBand(plan, rnd)
	plan.n = plan.n + 1
	local tx, ty
	if target ~= nil and finite(target.x) and finite(target.y) then
		tx, ty = target.x, target.y
	else
		target = nil
		tx, ty = P.placePoint(plan, rnd)
	end
	local slice = cam.TWO_PI / P.SECTORS
	local a = cam.wrapAngle((sector - 1 + 0.2 + 0.6 * rnd()) * slice)
	local pMin = finite(range and range.pMin) and range.pMin or cam.TOUR_FRAME.pMin
	local pMax = finite(range and range.pMax) and range.pMax or cam.TOUR_FRAME.pMax
	if pMin > pMax then pMin, pMax = pMax, pMin end
	local p = pMin + (pMax - pMin) * ((band - 1) + rnd()) / 3
	local dMin, dMax = P.distRange(plan.r, target ~= nil)
	local d = dMin * math.exp(math.log(dMax / dMin) * rnd())
	d = clamp(d, cam.SAFE.dMin, cam.MAX_DIST)
	p = clamp(p, cam.SAFE.pMin, cam.SAFE.pMax)
	return { x = tx, y = ty, d = d, a = a, p = p }, target
end

return P
