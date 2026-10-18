-- Organic Towns: gaps between towns (pure; round R3, 2026-10-13). Run 2026-10-13_1945_sqot-dev: towns grew against each
-- other into one mass. New mod streets now stop GAP_MIN..GAP_MAX m (seeded per town pair) short of the halfway line to
-- a neighbouring town's centre (the Voronoi line between the two centres), so open land stays between them.
--
-- Twins (a neighbour within ot_shape TWIN_NEAR, two cores growing together) are exempt in one way only: they meet along
-- their main road, not as a mass, so their main / medium pieces (the link, the ribbon) may go on to the halfway line;
-- their small streets keep the gap. No piece ever goes past the halfway line, and a piece whose points the engine gives
-- to another town (E.closestTown, `owner`) never comes (the game's own town ownership; checked only near the line).
-- Held pieces are counted (PLAN `gapHeld=`); no relaxation (open land elsewhere, or the town waits).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

M.ON = true
M.GAP_MIN = 150      -- m short of the halfway line, seeded per pair
M.GAP_MAX = 300
M.TWIN_NEAR = 1800   -- m (ot_shape TWIN_NEAR): twins' main roads go on to the line
M.FAR = 6000         -- m: neighbours farther than this are ignored (the halfway line is 3 km out)
M.OWNER_BAND = 250   -- m: the engine's town ownership is asked for pieces within this of the gap line
M.OWNER_CELL = 50    -- m: its answers cached per cell
-- (2026-10-14) A Works / district town and its parent (the driver marks the neighbour `waive`): along the corridor
-- between their centres (WAIVE_W m each side) neither the gap nor the halfway line holds a piece, so the parent's
-- streets may go on toward the district and the game fills in between; the engine's ownership still holds.
M.WAIVE_W = 160

--- The gap info for a town: centre {x, y}, neighbours { {x, y} or {dist, dir}, town }, seed; o = { owner =
--- function(x, y) -> true when (x, y) belongs to this town, twinNear }. Returns nil without neighbours in range.
function M.build(centre, neighbours, seed, o)
	if not M.ON or centre == nil then return nil end
	o = o or {}
	local list = {}
	for _, nb in ipairs(neighbours or {}) do
		local x, y = nb.x, nb.y
		if x == nil and nb.dist and nb.dir then
			x, y = centre[1] + math.cos(nb.dir) * nb.dist, centre[2] + math.sin(nb.dir) * nb.dist
		end
		local d = x and G.dist(centre[1], centre[2], x, y) or nil
		if d and d > 1 and d <= M.FAR and d == d then
			local ux, uy = (x - centre[1]) / d, (y - centre[2]) / d
			local a, b = math.min(seed or 1, nb.town or 0), math.max(seed or 1, nb.town or 0)
			local gap = M.GAP_MIN + (M.GAP_MAX - M.GAP_MIN) * rng.unit(a * 7919 + b, "townGap")
			list[#list + 1] = { x = x, y = y, d = d, ux = ux, uy = uy, half = d / 2, gap = math.min(gap, 0.4 * d / 2),
				twin = d <= (o.twinNear or M.TWIN_NEAR), town = nb.town, waive = nb.waive == true or nil }
		end
	end
	if #list == 0 then return nil end
	local cache = {}
	local owner = o.owner
	local function ownerOk(x, y)
		if owner == nil then return true end
		local k = math.floor(x / M.OWNER_CELL) * 100003 + math.floor(y / M.OWNER_CELL)
		local v = cache[k]
		if v == nil then
			local okC, r = pcall(owner, x, y)
			v = not okC or r ~= false
			cache[k] = v
		end
		return v
	end
	return { centre = centre, list = list, ownerOk = ownerOk }
end

--- How far point (x, y) lies past the gap line of neighbour nb (> 0: in the gap or beyond), and past the halfway line.
local function past(gp, nb, x, y)
	local s = (x - gp.centre[1]) * nb.ux + (y - gp.centre[2]) * nb.uy
	return s - (nb.half - nb.gap), s - nb.half
end

--- Is a piece (pts, class) held by a gap? Returns why ("gap" | "half" | "owner") or nil. Bad coordinates count as held.
function M.held(gp, pts, class)
	if gp == nil or pts == nil then return nil end
	local main = class == "main" or class == "medium"
	for _, p in ipairs(pts) do
		local x, y = p[1], p[2]
		if x ~= x or y ~= y or x == nil or y == nil then return "bad" end
		for _, nb in ipairs(gp.list) do
			local g, h = past(gp, nb, x, y)
			local waived = nb.waive and G.pointSegDist(x, y, gp.centre[1], gp.centre[2], nb.x, nb.y) <= M.WAIVE_W
			if h > 0 and not waived then return "half" end
			if g > 0 and not waived and not (nb.twin and main) then return "gap" end
			if g > -M.OWNER_BAND and not gp.ownerOk(x, y) then return "owner" end
		end
	end
	return nil
end

--- `gaps=` text for STYLE: "n:<nearest half>-<its gap>[t]" or "-".
function M.text(gp)
	if gp == nil then return "-" end
	local best = nil
	for _, nb in ipairs(gp.list) do if best == nil or nb.d < best.d then best = nb end end
	local nw = 0
	for _, nb in ipairs(gp.list) do if nb.waive then nw = nw + 1 end end
	return string.format("%d:%.0f-%.0f%s%s", #gp.list, best.half, best.gap, best.twin and "t" or "", nw > 0 and (" waive=" .. nw) or "")
end

return M
