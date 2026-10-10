-- Supply Gaps "Only towns in view" (PLAN "Phase 2d"). PURE: no api.*, unit-tested offline
-- (tests/square_supply_gaps/test_scope.lua). sg_overlay.tl reads the camera on the GUI thread and the
-- building bounding boxes, this module decides which towns are in view.
--
-- In-view rule:
--   * view footprint = the four screen corners projected onto the horizontal plane at the terrain
--     height under the camera centre (screen2World at depth 0 and 1 per corner, gui.d.tl:483-487),
--     each capped at CAP_FACTOR x camera distance from the centre (corners at or above the horizon).
--     Same projection as square_better_minimap's camera box (minimap_geom.tl groundPoint, shipped).
--     Fallback when the camera read fails: a square of +- distance around the centre.
--   * town extent = the 2D bounding box of its town buildings' BOUNDING_VOLUME boxes (the TOWN
--     record has no position or extent, engine.d.tl:1285-1302), so a town whose centre is off screen
--     but whose buildings are visible still counts, at every zoom and tilt.
--   * a town ENTERS the view when its box overlaps the footprint (separating-axis test of a convex
--     polygon against a box). It LEAVES only when it is farther than an exit margin
--     (EXIT_FACTOR x distance, at least EXIT_MIN m) AND has not overlapped for HOLD_TICKS ticks, so
--     towns at the edge don't flip in and out while panning or zooming.
-- Deterministic: towns in ascending id order, distance ties by id. Lua 5.1 safe.

local scope : SupplyGapsScope = {}

scope.CAP_FACTOR = 4.0
scope.MIN_DIST = 50.0
scope.EXIT_FACTOR = 0.25
scope.EXIT_MIN = 100.0
scope.HOLD_TICKS = 3
scope.NAMES_SHOWN = 3

function scope.newState() : SupplyGapsScopeState
	return { inView = {}, lastIn = {} }
end

--- Where the ray from n (near) towards f (far) meets the plane z = planeZ, at most maxDist from
--- (cx, cy). A ray at or above the horizon goes maxDist past the centre along its ground direction.
--- Returns x, y and whether the plane was hit. (Port of square_better_minimap geom.groundPoint.)
function scope.groundPoint(nx : number, ny : number, nz : number, fx : number, fy : number, fz : number,
		planeZ : number, cx : number, cy : number, maxDist : number) : number, number, boolean
	local dx, dy, dz = fx - nx, fy - ny, fz - nz
	local px, py : number, number
	local hit = false
	if nz <= planeZ then
		px, py, hit = nx, ny, true
	elseif dz < -1e-9 then
		local t = (planeZ - nz) / dz
		px, py, hit = nx + t * dx, ny + t * dy, true
	else
		local len = math.sqrt(dx * dx + dy * dy)
		if len < 1e-9 then return cx, cy, false end
		local reach = math.sqrt((nx - cx) ^ 2 + (ny - cy) ^ 2) + maxDist
		px, py = nx + dx / len * reach, ny + dy / len * reach
	end
	local ox, oy = px - cx, py - cy
	local d = math.sqrt(ox * ox + oy * oy)
	if maxDist ~= nil and maxDist > 0 and d > maxDist then
		px, py = cx + ox / d * maxDist, cy + oy / d * maxDist
	end
	return px, py, hit
end

local function d2(a : {number}, b : {number}) : number
	return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2
end

function scope.footprint(rays : {{{number}}}, eye : {number}, planeZ : number, cx : number, cy : number, maxDist : number) : {number}, integer
	local poly : {number} = {}
	local hits = 0
	for i = 1, #rays do
		local r = rays[i]
		local nearP, farP = r[1], r[2]
		if nearP == nil then nearP = eye end
		if farP ~= nil and nearP ~= nil and eye ~= nil and d2(farP, eye) < d2(nearP, eye) then nearP, farP = farP, nearP end
		local gx, gy : number, number
		local hit = false
		if nearP == nil or farP == nil or d2(nearP, farP) < 1e-6 then
			gx, gy = cx, cy
		else
			gx, gy, hit = scope.groundPoint(nearP[1], nearP[2], nearP[3], farP[1], farP[2], farP[3], planeZ, cx, cy, maxDist)
		end
		if hit then hits = hits + 1 end
		poly[#poly + 1] = gx
		poly[#poly + 1] = gy
	end
	return poly, hits
end

function scope.square(cx : number, cy : number, half : number) : {number}
	return { cx - half, cy - half, cx + half, cy - half, cx + half, cy + half, cx - half, cy + half }
end

local function project(poly : {number}, ax : number, ay : number) : number, number
	local lo, hi = math.huge, -math.huge
	for i = 1, #poly - 1, 2 do
		local p = poly[i] * ax + poly[i + 1] * ay
		if p < lo then lo = p end
		if p > hi then hi = p end
	end
	return lo, hi
end

function scope.intersects(poly : {number}, box : SupplyGapsBox, margin : number) : boolean
	if poly == nil or #poly < 2 or box == nil or box[1] == nil then return false end
	local m = margin or 0
	local x0, y0, x1, y1 = box[1] - m, box[2] - m, box[3] + m, box[4] + m
	local corners : {number} = { x0, y0, x1, y0, x1, y1, x0, y1 }
	-- axes of the box
	local lo, hi = project(poly, 1, 0)
	if hi < x0 or lo > x1 then return false end
	lo, hi = project(poly, 0, 1)
	if hi < y0 or lo > y1 then return false end
	-- edge normals of the polygon (degenerate edges skipped)
	local n = math.floor(#poly / 2)
	for i = 1, n do
		local j = i % n + 1
		local ex, ey = poly[2 * j - 1] - poly[2 * i - 1], poly[2 * j] - poly[2 * i]
		if ex * ex + ey * ey > 1e-9 then
			local ax, ay = -ey, ex
			local plo, phi = project(poly, ax, ay)
			local blo, bhi = project(corners, ax, ay)
			if phi < blo or plo > bhi then return false end
		end
	end
	return true
end

function scope.townBoxes(ids : {integer}, townOf : {integer}, boxes : {integer : SupplyGapsBox}) : {integer : SupplyGapsBox}
	local out : {integer : SupplyGapsBox} = {}
	for i = 1, #(ids or {}) do
		local bb = boxes[ids[i]]
		local t = townOf[i]
		if bb ~= nil and bb[1] ~= nil and t ~= nil then
			local tb = out[t]
			if tb == nil then
				out[t] = { bb[1], bb[2], bb[3], bb[4] }
			else
				if bb[1] < tb[1] then tb[1] = bb[1] end
				if bb[2] < tb[2] then tb[2] = bb[2] end
				if bb[3] > tb[3] then tb[3] = bb[3] end
				if bb[4] > tb[4] then tb[4] = bb[4] end
			end
		end
	end
	return out
end

function scope.select(townBoxes : {integer : SupplyGapsBox}, cam : SupplyGapsCameraView, state : SupplyGapsScopeState, tick : integer) : {integer : boolean}, boolean
	local towns : {integer} = {}
	for t in pairs(townBoxes or {}) do towns[#towns + 1] = t end
	table.sort(towns)
	local dist = math.max(cam.distance or 0, scope.MIN_DIST)
	local exitMargin = math.max(scope.EXIT_FACTOR * dist, scope.EXIT_MIN)
	local nextIn : {integer : boolean} = {}
	local nextLast : {integer : integer} = {}
	for __, t in ipairs(towns) do
		local box = townBoxes[t]
		if scope.intersects(cam.poly, box, 0) then
			nextIn[t] = true
			nextLast[t] = tick
		elseif state.inView[t] then
			local last = state.lastIn[t]
			local held = last ~= nil and tick - last < scope.HOLD_TICKS
			if held or scope.intersects(cam.poly, box, exitMargin) then
				nextIn[t] = true
				nextLast[t] = last
			end
		end
	end
	local changed = false
	for t in pairs(nextIn) do
		if not state.inView[t] then changed = true end
	end
	for t in pairs(state.inView) do
		if not nextIn[t] then changed = true end
	end
	state.inView, state.lastIn = nextIn, nextLast
	return nextIn, changed
end

function scope.byDistance(towns : {integer : boolean}, townBoxes : {integer : SupplyGapsBox}, cx : number, cy : number) : {integer}
	local out : {integer} = {}
	local dist : {integer : number} = {}
	for t in pairs(towns or {}) do
		local b = townBoxes ~= nil and townBoxes[t] or nil
		if b ~= nil and b[1] ~= nil then
			local x, y = 0.5 * (b[1] + b[3]), 0.5 * (b[2] + b[4])
			dist[t] = (x - cx) ^ 2 + (y - cy) ^ 2
		else
			dist[t] = math.huge
		end
		out[#out + 1] = t
	end
	table.sort(out, function(a : integer, b : integer) : boolean
		if dist[a] ~= dist[b] then return dist[a] < dist[b] end
		return a < b
	end)
	return out
end

function scope.namesText(names : {string}, shown : integer) : string
	local n = #(names or {})
	local k = math.min(n, shown or scope.NAMES_SHOWN)
	local parts : {string} = {}
	for i = 1, k do parts[i] = names[i] end
	local s = table.concat(parts, ", ")
	if n > k then s = s .. " +" .. tostring(n - k) end
	return s
end

return scope
