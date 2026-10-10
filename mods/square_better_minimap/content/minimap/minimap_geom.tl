-- Minimap geometry: world <-> minimap fraction <-> widget pixels. Pure (no api.*), unit-tested in
-- tests/square_better_minimap/test_geom.lua. Types: minimap_types.d.tl. Also the industry marker helpers
-- (phase 3: icon choice, pixel layout).
-- World extent: api.engine.terrain.getBoundingBox() (.cache/game/api/tealdef/api/engine.d.tl:1754),
-- camera centre: api.gui.camera.getCameraData() {x, y, distance, angle, pitch} (gui.d.tl:430-433).
-- The MapPreviewComp picture orientation is not documented; phase 1 matched it in game with
-- DEFAULT_ORIENT (flipY). The window always uses it; the other orientations stay for the tests.

local geom : SquareMinimapGeom = {}

geom.DEFAULT_ORIENT = { flipX = false, flipY = true, swapXY = false }

function geom.clamp(v : number, lo : number, hi : number) : number
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function geom.boxFromBounds(minX : number, minY : number, maxX : number, maxY : number) : SquareMinimapBox
	if maxX < minX then minX, maxX = maxX, minX end
	if maxY < minY then minY, maxY = maxY, minY end
	-- Degenerate extent: give it 1 m so the divisions below stay finite.
	if maxX - minX < 1 then maxX = minX + 1 end
	if maxY - minY < 1 then maxY = minY + 1 end
	return { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
end

function geom.widgetSize(box : SquareMinimapBox, longSide : integer, orient : SquareMinimapOrient) : integer, integer
	local w = box.maxX - box.minX
	local h = box.maxY - box.minY
	if orient ~= nil and orient.swapXY then w, h = h, w end
	if w >= h then
		return longSide, math.max(1, math.floor(longSide * h / w + 0.5))
	end
	return math.max(1, math.floor(longSide * w / h + 0.5)), longSide
end

function geom.worldToFrac(x : number, y : number, box : SquareMinimapBox, orient : SquareMinimapOrient) : number, number
	local u = (x - box.minX) / (box.maxX - box.minX)
	local v = (y - box.minY) / (box.maxY - box.minY)
	local o = orient or geom.DEFAULT_ORIENT
	if o.swapXY then u, v = v, u end
	if o.flipX then u = 1 - u end
	if o.flipY then v = 1 - v end
	return u, v
end

function geom.fracToWorld(fx : number, fy : number, box : SquareMinimapBox, orient : SquareMinimapOrient) : number, number
	local o = orient or geom.DEFAULT_ORIENT
	local u, v = fx, fy
	if o.flipX then u = 1 - u end
	if o.flipY then v = 1 - v end
	if o.swapXY then u, v = v, u end
	return box.minX + u * (box.maxX - box.minX), box.minY + v * (box.maxY - box.minY)
end

function geom.childGravity(frac : number, parentPx : number, childPx : number) : number
	-- A FloatingLayoutChild with gravity g sits at g * (parent - child) (company.tl:91-93 centres
	-- with 0.5, finances_cargo_lifetime.tl:65-67 right-aligns with 1.0), so solve
	-- g * (P - c) = frac * P - c / 2.
	local free = parentPx - childPx
	if free <= 0 then return 0.5 end
	return geom.clamp((frac * parentPx - childPx / 2) / free, 0, 1)
end

function geom.rectFromPoints(pts : {number}) : SquareMinimapRect
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for i = 1, #pts - 1, 2 do
		local fx, fy = pts[i], pts[i + 1]
		if fx < x0 then x0 = fx end
		if fx > x1 then x1 = fx end
		if fy < y0 then y0 = fy end
		if fy > y1 then y1 = fy end
	end
	if x0 > x1 then return { x0 = 0, y0 = 0, x1 = 0, y1 = 0 } end
	return {
		x0 = geom.clamp(x0, 0, 1), y0 = geom.clamp(y0, 0, 1),
		x1 = geom.clamp(x1, 0, 1), y1 = geom.clamp(y1, 0, 1),
	}
end

function geom.rectAround(cx : number, cy : number, halfSide : number, box : SquareMinimapBox, orient : SquareMinimapOrient) : SquareMinimapRect
	local ax, ay = geom.worldToFrac(cx - halfSide, cy - halfSide, box, orient)
	local bx, by = geom.worldToFrac(cx + halfSide, cy + halfSide, box, orient)
	return geom.rectFromPoints({ ax, ay, bx, by })
end

function geom.eventToFrac(ex : number, ey : number, p0x : number, p0y : number, p1x : number, p1y : number, screenW : number, screenH : number) : number, number, boolean
	local normalised = false
	-- content_card.tl:186 compares getPosition(0.5, 0).x with 0.5, which suggests normalised
	-- screen coordinates; mouse events carry pixels (builtin.lua:629-631 builds a Vec2i from them).
	if p1x <= 1.5 and p1y <= 1.5 and (ex > 1.5 or ey > 1.5) and screenW ~= nil and screenW > 0 and screenH ~= nil and screenH > 0 then
		ex = ex / screenW
		ey = ey / screenH
		normalised = true
	end
	local w = p1x - p0x
	local h = p1y - p0y
	if w == 0 or h == 0 then return 0.5, 0.5, normalised end
	return (ex - p0x) / w, (ey - p0y) / h, normalised
end

function geom.camPx(rect : SquareMinimapRect, cx : number, cy : number, w : integer, h : integer, minPx : integer) : SquareMinimapCamPx
	local function px(v : number) : integer return math.floor(v + 0.5) end
	return {
		-- Centred on the camera's look-at point, not on the footprint bounds: with a pitched camera
		-- the far side of the footprint is much wider, which pushed the look-at point low in the box.
		boxCX = px(cx * w),
		boxCY = px(cy * h),
		boxW = math.max(minPx, px((rect.x1 - rect.x0) * w)),
		boxH = math.max(minPx, px((rect.y1 - rect.y0) * h)),
		dotX = px(geom.clamp(cx, 0, 1) * w),
		dotY = px(geom.clamp(cy, 0, 1) * h),
	}
end

--- Box given by centre/size in picture pixels, clipped to the picture: left, top, width, height.
function geom.clipBox(cx : integer, cy : integer, w : integer, h : integer, pw : integer, ph : integer) : integer, integer, integer, integer
	local l = math.max(0, cx - w // 2)
	local t = math.max(0, cy - h // 2)
	local r = math.min(pw, cx - w // 2 + w)
	local b = math.min(ph, cy - h // 2 + h)
	return l, t, math.max(0, r - l), math.max(0, b - t)
end

-- math.atan2 is in the game's Lua (base: scripts/vec3.tl:88); the offline tests run a Lua 5.3+
-- that only has the two-argument math.atan.
local atan2 = math.atan2 or math.atan

function geom.headingDegrees(hx : number, hy : number) : integer
	-- Picture pixels, y down: up (0, -1) = 0, right (1, 0) = 90. Whole degrees, so the arrow only
	-- re-renders on a visible turn.
	if hx == nil or hy == nil then return nil end
	if hx * hx + hy * hy < 1e-18 then return nil end
	local deg = math.floor(math.deg(atan2(hx, -hy)) + 0.5) % 360
	return deg
end

function geom.sameCamPx(a : SquareMinimapCamPx, b : SquareMinimapCamPx) : boolean
	if a == nil or b == nil then return a == b end
	if not (a.boxCX == b.boxCX and a.boxCY == b.boxCY and a.boxW == b.boxW and a.boxH == b.boxH
		and a.dotX == b.dotX and a.dotY == b.dotY) then
		return false
	end
	return a.arrowDeg == b.arrowDeg
end

function geom.pictureSize(box : SquareMinimapBox, longSide : integer, minW : integer, maxLong : integer, orient : SquareMinimapOrient, floorW ?: integer, absMaxLong ?: integer) : integer, integer
	local w, h = geom.widgetSize(box, longSide, orient)
	local aspect = h / w
	-- Widen to the minimum width (the window can't get narrower than its title bar / control row,
	-- so a narrower picture leaves an empty band), then cap the long side: the cap always wins, or
	-- extreme portrait strips (1:5) grow taller than the screen. Those keep a narrow band instead.
	if minW ~= nil and w < minW then
		w = minW
	end
	h = math.max(1, math.floor(w * aspect + 0.5))
	if maxLong ~= nil and maxLong > 0 and math.max(w, h) > maxLong then
		if w >= h then
			w = maxLong
			h = math.max(1, math.floor(maxLong * aspect + 0.5))
		else
			h = maxLong
			w = math.max(1, math.floor(maxLong / aspect + 0.5))
		end
	end
	-- The window can't get narrower than floorW (frame + control row), so a narrower picture leaves
	-- a band beside it. The floor beats maxLong (a 1:3 strip at S grows taller instead), but not
	-- absMaxLong (the screen limit): only strips beyond that keep a band.
	if floorW ~= nil and w < floorW then
		w = floorW
		h = math.max(1, math.floor(w * aspect + 0.5))
		if absMaxLong ~= nil and absMaxLong > 0 and h > absMaxLong then
			h = absMaxLong
			w = math.max(1, math.floor(absMaxLong / aspect + 0.5))
		end
	end
	return w, h
end

function geom.groundPoint(nx : number, ny : number, nz : number, fx : number, fy : number, fz : number,
		planeZ : number, cx : number, cy : number, maxDist : number) : number, number, boolean
	local dx, dy, dz = fx - nx, fy - ny, fz - nz
	local px, py : number, number
	local hit = false
	if nz <= planeZ then
		-- Ray starts at or below the plane (camera under the centre's ground level): use its start.
		px, py, hit = nx, ny, true
	elseif dz < -1e-9 then
		local t = (planeZ - nz) / dz
		px, py, hit = nx + t * dx, ny + t * dy, true
	else
		-- Points at or above the horizon: go maxDist past the centre along the ray's ground direction.
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

function geom.normalizeScreenPos(x : number, y : number, screenW : number, screenH : number) : number, number
	-- getPosition() returned 0..1 screen fractions for widgets in phase 1; accept pixels too.
	if (x > 1.5 or y > 1.5) and screenW ~= nil and screenW > 0 and screenH ~= nil and screenH > 0 then
		return x / screenW, y / screenH
	end
	return x, y
end

function geom.windowAnchor(left : number, top : number, right : number, bottom : number, minTop : number) : number, number
	-- NaN / inf / empty / far off-screen (hidden or unmounted window) -> nil.
	local function ok(v : number) : boolean return v == v and v > -0.5 and v < 1.5 end
	if not (ok(left) and ok(top) and ok(right) and ok(bottom)) then return nil, nil end
	local w, h = right - left, bottom - top
	if w <= 0.001 or h <= 0.001 or w > 1 or h > 1 then return nil, nil end
	-- Top-right corner (CSS anchorPoint {1, 0}), kept fully on screen and below the top bar.
	local x = geom.clamp(right, w, 1)
	local y = geom.clamp(top, minTop or 0, math.max(minTop or 0, 1 - h))
	return x, y
end

function geom.readPrefs(raw : any, nSizes : integer, minTop : number) : SquareMinimapPrefs
	local p : SquareMinimapPrefs = {}
	if type(raw) ~= "table" then return p end
	local t = raw as {string : any}
	local function frac(v : any) : number
		if type(v) ~= "number" then return nil end
		local n = v as number
		if n ~= n or n < 0 or n > 1 then return nil end
		return n
	end
	local function bool(v : any) : boolean
		if type(v) == "boolean" then return v as boolean end
		return nil
	end
	local x, y = frac(t.posX), frac(t.posY)
	if x ~= nil and y ~= nil and x > 0 then
		p.posX = x
		p.posY = geom.clamp(y, minTop or 0, 1)
	end
	local s = t.sizeIdx
	if type(s) == "number" and math.floor(s as number) == s and (s as number) >= 1 and (s as number) <= (nSizes or 0) then
		p.sizeIdx = math.floor(s as number)
	end
	p.pinned = bool(t.pinned)
	p.showIndustries = bool(t.showIndustries)
	p.showNet = bool(t.showNet)
	p.hiVis = bool(t.hiVis)
	p.open = bool(t.open)
	-- Industry filter (phase 7): kept as the stored string; minimap_filter.fromPrefs parses it.
	if type(t.filterTypes) == "string" then p.filterTypes = t.filterTypes as string end
	return p
end

function geom.round(v : number, decimals : integer) : number
	local m = 10 ^ decimals
	return math.floor(v * m + 0.5) / m
end

local function firstPath(list : {string}) : string
	if list == nil then return nil end
	for __, p in ipairs(list) do
		if p ~= nil and p ~= "" then return p end
	end
	return nil
end

function geom.pickIcon(outputs : {string}, inputs : {string}, fallback : string) : string, string
	-- The base game marks an industry with its cargo icons (HUD: CargoInputOutputIndicator,
	-- entity_window_hud.tl:142-160; industry window: ProductionIconWithBubble with
	-- cargo_util.getCargoIconById, industry_react_util.tl:323-325). The product says most.
	local p = firstPath(outputs)
	if p ~= nil then return p, "output" end
	p = firstPath(inputs)
	if p ~= nil then return p, "input" end
	return fallback, "fallback"
end

function geom.markerLayout(items : {SquareMinimapIndustry}, box : SquareMinimapBox, orient : SquareMinimapOrient,
		w : integer, h : integer, size : integer) : {SquareMinimapMarkerPx}
	local out : {SquareMinimapMarkerPx} = {}
	if items == nil or w <= 0 or h <= 0 then return out end
	local function place(frac : number, px : integer) : integer
		local v = math.floor(frac * px - size / 2 + 0.5)
		return math.max(0, math.min(math.max(0, px - size), v))
	end
	for __, it in ipairs(items) do
		if it.x ~= nil and it.y ~= nil then
			local fx, fy = geom.worldToFrac(it.x, it.y, box, orient)
			if fx >= 0 and fx <= 1 and fy >= 0 and fy <= 1 then
				local left, top = place(fx, w), place(fy, h)
				out[#out + 1] = {
					key = string.format("ind_%d_%d_%d", it.entity, left, top),
					entity = it.entity,
					left = left,
					top = top,
					icon = it.icon,
					name = it.name,
					typeKey = it.typeKey,
				}
			end
		end
	end
	table.sort(out, function(a : SquareMinimapMarkerPx, b : SquareMinimapMarkerPx) : boolean
		if a.top ~= b.top then return a.top < b.top end
		if a.left ~= b.left then return a.left < b.left end
		return a.entity < b.entity
	end)
	return out
end

function geom.hitMarker(markers : {SquareMinimapMarkerPx}, x : number, y : number, size : integer, tol : number,
		visible ?: function(SquareMinimapMarkerPx) : boolean) : SquareMinimapMarkerPx
	if markers == nil or x == nil or y == nil then return nil end
	local t = tol or 0
	local half = size / 2
	local best : SquareMinimapMarkerPx = nil
	local bestD = math.huge
	for __, m in ipairs(markers) do
		if x >= m.left - t and x <= m.left + size + t and y >= m.top - t and y <= m.top + size + t
			and (visible == nil or visible(m)) then
			local dx, dy = x - (m.left + half), y - (m.top + half)
			local d = dx * dx + dy * dy
			-- <= : on a tie the later marker wins (drawn on top, markerLayout order).
			if d <= bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

function geom.controlRows(w : integer, ids : {string}, widths : {string : integer}, spacing : integer, pad : integer) : {{string}}
	local rows : {{string}} = {}
	local row : {string} = {}
	local used = pad
	for __, id in ipairs(ids) do
		local cw = widths[id] or 0
		local need = #row == 0 and cw or spacing + cw
		if #row > 0 and used + need > w then
			rows[#rows + 1] = row
			row, used = {}, pad
			need = cw
		end
		row[#row + 1] = id
		used = used + need
	end
	if #row > 0 then rows[#rows + 1] = row end
	return rows
end

-- Control width estimate (translations, revision 6): fitted to the 2026-10-10 screenshot, where
-- "Ind" (3 letters) took ~47 px and "Filter" (6) ~68 px: 26 px box + gap, ~7 px per letter.
local CONTROL_BASE_PX <const> = 26
local CONTROL_UNIT_PX <const> = 7

function geom.textUnits(s : string) : integer
	local n = 0
	local i, len = 1, #s
	while i <= len do
		local b = s:byte(i)
		if b < 0x80 then
			n, i = n + 1, i + 1
		elseif b >= 0xF0 then
			n, i = n + 2, i + 4
		elseif b >= 0xE0 then
			-- U+3000 and up (lead byte 0xE3+): CJK punctuation, kana, ideographs, Hangul, full-width forms.
			n, i = n + (b >= 0xE3 and 2 or 1), i + 3
		elseif b >= 0xC0 then
			n, i = n + 1, i + 2
		else
			i = i + 1 -- stray continuation byte
		end
	end
	return n
end

function geom.controlWidth(label : string) : integer
	return CONTROL_BASE_PX + CONTROL_UNIT_PX * geom.textUnits(label or "")
end

--- Byte length of one UTF-8 character from its lead byte, and its units (textUnits).
local function charAt(b : integer) : integer, integer
	if b < 0x80 then return 1, 1 end
	if b >= 0xF0 then return 4, 2 end
	if b >= 0xE0 then return 3, (b >= 0xE3 and 2 or 1) end
	if b >= 0xC0 then return 2, 1 end
	return 1, 0
end

function geom.fitText(s : string, maxUnits : integer) : string, boolean
	if geom.textUnits(s) <= maxUnits then return s, false end
	local budget = maxUnits - 3 -- room for "..."
	local i, used = 1, 0
	while i <= #s do
		local n, u = charAt(s:byte(i))
		if used + u > budget then break end
		i, used = i + n, used + u
	end
	return (s:sub(1, i - 1):gsub(" +$", "")) .. "...", true -- " +$", not "%s": %s can match a UTF-8 byte (0xA0)
end

return geom
