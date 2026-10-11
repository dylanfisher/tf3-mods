-- DEV ONLY (never upload): Roundabouts Showcase, ASCII preview of a layout for the log. Pure Lua.
-- Each placement fills its rotated box's cells with its entry symbol (lowercase = a kaleidoscope
-- mirror image); "+" marks the layout centre, "." empty ground. North (world +y) is up.

local preview = {}

--- Lines of the preview (cols x rows characters, aspect kept with cells twice as tall as wide).
function preview.render(placements, cx, cy, cols, rows)
	cols, rows = cols or 96, rows or 48
	if #placements == 0 then return { "(nothing placed)" } end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	local function corners(p)
		local a = math.rad(p.rot)
		local c, s = math.cos(a), math.sin(a)
		local hw, hh = p.fp.w / 2, p.fp.h / 2
		local out = {}
		for _, k in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
			local lx, ly = k[1] * hw, k[2] * hh
			out[#out + 1] = { p.x + c * lx - s * ly, p.y + s * lx + c * ly }
		end
		return out
	end
	for _, p in ipairs(placements) do
		for _, q in ipairs(corners(p)) do
			minX, maxX = math.min(minX, q[1]), math.max(maxX, q[1])
			minY, maxY = math.min(minY, q[2]), math.max(maxY, q[2])
		end
	end
	local spanX, spanY = maxX - minX, maxY - minY
	-- metres per character: cells are about twice as tall as wide
	local mpc = math.max(spanX / cols, spanY / (rows * 2), 1)
	local W = math.max(1, math.min(cols, math.ceil(spanX / mpc)))
	local H = math.max(1, math.min(rows, math.ceil(spanY / (mpc * 2))))
	local grid = {}
	for r = 1, H do
		grid[r] = {}
		for c = 1, W do grid[r][c] = "." end
	end
	local function cell(x, y)
		local c = math.floor((x - minX) / mpc) + 1
		local r = math.floor((maxY - y) / (mpc * 2)) + 1
		return math.max(1, math.min(W, c)), math.max(1, math.min(H, r))
	end
	for _, p in ipairs(placements) do
		local sym = p.item and p.item.symbol or "#"
		if p.mirrored then sym = sym:lower() end
		local a = math.rad(p.rot)
		local co, si = math.cos(a), math.sin(a)
		local hw, hh = p.fp.w / 2, p.fp.h / 2
		-- every cell whose centre lies inside the rotated box, and at least the centre cell
		local q = corners(p)
		local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
		for _, v in ipairs(q) do
			x0, x1 = math.min(x0, v[1]), math.max(x1, v[1])
			y0, y1 = math.min(y0, v[2]), math.max(y1, v[2])
		end
		local c0, r1 = cell(x0, y0)
		local c1, r0 = cell(x1, y1)
		for r = r0, r1 do
			for c = c0, c1 do
				local wx = minX + (c - 0.5) * mpc
				local wy = maxY - (r - 0.5) * mpc * 2
				local dx, dy = wx - p.x, wy - p.y
				local lx, ly = co * dx + si * dy, -si * dx + co * dy
				if math.abs(lx) <= hw and math.abs(ly) <= hh then grid[r][c] = sym end
			end
		end
		local cc, cr = cell(p.x, p.y)
		grid[cr][cc] = sym
	end
	if cx and cy and cx >= minX and cx <= maxX and cy >= minY and cy <= maxY then
		local cc, cr = cell(cx, cy)
		grid[cr][cc] = "+"
	end
	local lines = {}
	for r = 1, H do lines[r] = table.concat(grid[r]) end
	lines[#lines + 1] = string.format("(%d x %d chars, %.0f m per char across, x %.0f..%.0f, y %.0f..%.0f)",
		W, H, mpc, minX, maxX, minY, maxY)
	return lines
end

return preview
