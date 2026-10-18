-- Organic Towns: tree-lined town entries (pure; later-ideas phase, 2026-10-13).
--
-- User idea (MOTIFS_BRIEF "Other ideas"): "country road character (curvier approaches, tree-lined entries)".
-- Research (PLAN.md 6.3 "Later ideas", docs/findings/towns.md "Tree-lined town street templates"):
-- * The country roads themselves stay untouched: the mod never joins, crosses or rebuilds a country-road node or edge
--   (findings towns.md "Joining a script street to a country-road node": every verified join is on a town dead end; a
--   road node's config is never rewritten). Curving or restyling an existing country road would mean removing and
--   re-adding the game's edges with their junction configs: not safe, skipped.
-- * Town side: the base game has tree-lined town streets: `town_{old,new}_{small,medium,large}_trees.street_template`,
--   identical to the plain templates (same laneConfigs, streetStyle, speeds) except `defaultEdgeDecorations` (the
--   `alley.edge` tree row on both sides, preventParcels = false: houses still come) and not `simBuildable` (towns never
--   build them, players do; a script may: the mod's one-way rings use non-simBuildable country templates). So the mod's
--   own new streets along a country road's first stretch out of town (beside it, parallel, within BESIDE m and LEN m of
--   where it leaves the town: ribbon streets, frontage streets, the avenue out) and its wide streets right at the entry
--   (within AT m) go out with the trees variant of their template, the decorations set from the template's defaults (as
--   the base track builder does: edgeDecorationRep.find of each default). A street continuing from a tree-lined dead end
--   gets the plain template and no decorations.
-- * Per town a seeded share (P by style; metropolis P_METRO): not every town lines its approaches.
-- Safety: plain base templates and decorations only (removing the mod leaves ordinary tree-lined town streets); the
-- lanes are those of the plain template (ot_proposal lane rules unchanged); a refused pre-check with tree-lined edges
-- is re-sent once without them, and after MAX_REFUSED such refusals in a session the trees are off for the session.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

M.ON = true
M.P = { EU_ORGANIC = 0.55, EU_EXTENSION = 0.65, MED_HILL = 0.35, MED_ENSANCHE = 0.5, NA_GRID = 0.35, NA_SUBURB = 0.6,
	NORDIC = 0.3, JP_DENSE = 0.2, SUPERBLOCK = 0.5 }
M.P_DEFAULT = 0.4
M.P_METRO = 0.8
M.LEN = 320          -- m along the road from where it leaves the town
M.BESIDE = 70        -- m: a street this near the road's line ...
M.PARALLEL = math.rad(30)   -- ... and within this of its direction is "along the approach"
M.AT = 110           -- m: a main / medium street this near the entry point is the entry itself
M.MIN_LEN = 25       -- m: shorter edges stay plain
M.VIRTUAL_IN = 60    -- m: a virtual road's entry starts this far inside the houses' extent (ot_roads.virtual)
M.MAX_REFUSED = 2    -- pre-checks refused with tree-lined edges before the trees are off for the session
M.SIZES = { small = true, medium = true, large = true }   -- sizes with a `_trees` variant (no xsmall)

--- The `_trees` variant of a town template path, or nil (no variant for that size, already one, not a town street).
function M.treesPath(path)
	if type(path) ~= "string" or path:find("_trees", 1, true) then return nil end
	local head, size = path:match("^(.*town_%a+_)(%a+)%.street_template$")
	if head == nil or not M.SIZES[size] then return nil end
	return head .. size .. "_trees.street_template"
end

--- The plain template of a `_trees` path (or the path itself).
function M.plainPath(path)
	if type(path) ~= "string" then return path end
	return (path:gsub("_trees%.street_template$", ".street_template"))
end

--- true for a `_trees` template path.
function M.isTrees(path)
	return type(path) == "string" and path:find("_trees%.street_template$") ~= nil
end

--- Does town style lining its entries? Seeded per town (rng "entryTrees"). Returns on, p.
function M.on(style)
	if not M.ON or style == nil then return false, 0 end
	local p = style.metro and M.P_METRO or (M.P[style.id or ""] or M.P_DEFAULT)
	return rng.decide(style.drawV, style.seed or 1, "entryTrees") < p, p
end

local function polyProject(pts, x, y)
	-- distance from (x, y) to the polyline, the arc length there and the segment direction
	local best, bs, bdx, bdy = math.huge, 0, 1, 0
	local s = 0
	for i = 2, #pts do
		local ax, ay, bx, by = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
		local dx, dy = bx - ax, by - ay
		local l2 = dx * dx + dy * dy
		local l = math.sqrt(l2)
		local t = l2 > 0 and G.clamp(((x - ax) * dx + (y - ay) * dy) / l2, 0, 1) or 0
		local px, py = ax + dx * t, ay + dy * t
		local d = G.dist(px, py, x, y)
		if d < best then best, bs, bdx, bdy = d, s + t * l, dx, dy end
		s = s + l
	end
	return best, bs, bdx, bdy
end

--- Arc length along pts where it first lies at least d from (cx, cy), or nil.
function M.arcAt(pts, cx, cy, d)
	local acc = 0
	if G.dist(cx, cy, pts[1][1], pts[1][2]) >= d then return 0 end
	for i = 2, #pts do
		local l = G.dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
		if G.dist(cx, cy, pts[i][1], pts[i][2]) >= d then return acc + l end
		acc = acc + l
	end
	return nil
end

--- Is edge e (p0, p1, class) a town entry street of roads (ot_roads.trace)? Along a road's first LEN m (beside it within
--- BESIDE, parallel within PARALLEL), or a main / medium street within AT of a road's entry point.
function M.isEntry(roads, e, centre, r)
	local ax, ay, bx, by = e.p0[1], e.p0[2], e.p1[1], e.p1[2]
	local l = G.dist(ax, ay, bx, by)
	if l < M.MIN_LEN then return false end
	local mx, my = (ax + bx) / 2, (ay + by) / 2
	for _, rd in ipairs((roads and roads.roads) or {}) do
		local pts = rd.pts
		if pts and #pts >= 2 then
			local d, s, dx, dy = polyProject(pts, mx, my)
			-- (a virtual road, ot_roads.virtual, starts at the centre: its entry is where it leaves the houses' extent r,
			-- the first LEN m from VIRTUAL_IN m inside it)
			local s0 = 0
			if rd.virtual and centre and r then
				s0 = M.arcAt(pts, centre[1], centre[2], math.max(0, r - M.VIRTUAL_IN))
				if s0 == nil then s0 = math.huge end
			end
			if s >= s0 and s - s0 <= M.LEN and d <= M.BESIDE then
				local ld = math.sqrt(dx * dx + dy * dy)
				if ld > 0 then
					local c = math.abs(((bx - ax) * dx + (by - ay) * dy) / (l * ld))
					if c >= math.cos(M.PARALLEL) then return true end
				end
			end
			if (e.class == "main" or e.class == "medium") and not rd.virtual and G.dist(pts[1][1], pts[1][2], mx, my) <= M.AT then
				return true
			end
		end
	end
	return false
end

--- Marks the increment's tree-lined entry edges (e.trees = true; inc.trees = count, nil when none). style.roads is the
--- town's country roads; ok(path) -> true when the `_trees` template of the edge's template exists (nil: assumed).
--- Bridge edges never. Returns the count.
function M.mark(inc, style, ok)
	inc.trees = nil
	local on = M.on(style)
	if not on or style.roads == nil or #(style.roads.roads or {}) == 0 then return 0 end
	local n = 0
	for _, e in ipairs(inc.edges or {}) do
		e.trees = nil
		local tp = M.treesPath(e.template)
		if tp and not e.bridge and (ok == nil or ok(tp)) and M.isEntry(style.roads, e, style.centre, style.radius) then
			e.trees = true
			n = n + 1
		end
	end
	if n > 0 then inc.trees = n end
	return n
end

--- Clears every tree flag of inc (a refused pre-check is re-sent without them). Returns how many there were.
function M.strip(inc)
	local n = 0
	for _, e in ipairs(inc.edges or {}) do
		if e.trees then e.trees = nil; n = n + 1 end
	end
	inc.trees = nil
	return n
end

return M
