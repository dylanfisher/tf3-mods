-- Organic Towns: neighbour diversity (pure). 2026-10-13, user: "Can we make sure we try not to have the same town style
-- near another town?" and, refined: "It's less important to break towns up by JP, Nordic, American, old Europe etc., and
-- more important to just have character variation of towns and have them respond to their terrain and surroundings."
--
-- So the diversity sits mainly on the town's FORM and SHAPE (clustered, radiating, sprawling, linear, wide, fingers;
-- compact, cross, lens, ...) and only lightly on the regional style id: when a town's style (ot_site), shape (ot_shape)
-- and form (ot_form) are drawn, the ids its neighbours already use (within RADIUS: a saved frame, or a town picked
-- earlier this session with a lower town id, so a fresh map's picks are reproducible) weigh less, closer = stronger:
--   factor(id) = prod over neighbours using id of (1 - (1 - MIN) x closeness), closeness = 1 - (dist / RADIUS)^2,
--   at least FLOOR.
-- It stays a preference: the terrain's evidence (ot_shape site candidates: valley, ridge, river, coast, hillside) is
-- never down-weighted, character towns and the shore form are not touched, a saved town never changes, and a style
-- only ever loses a little weight (STYLE_MIN), so no foreign regional style is pushed in to differ.

local M = {}

M.ON = true
M.RADIUS = 5000      -- m: neighbours this close count
M.FORM_MIN = 0.25    -- a form the nearest neighbour uses, at distance 0, weighs x this (fading to 1 at RADIUS)
M.SHAPE_MIN = 0.35   -- the same for a shape (its style / road / neighbour part, never the terrain's)
M.STYLE_MIN = 0.85   -- regional style ids: weak (the region's home style must stay home)
M.FLOOR = 0.15       -- forms / shapes: product of all neighbours at least this
M.STYLE_FLOOR = 0.7  -- styles: at least this
M.MOTIF_MIN = 0.3    -- motifs (ot_motif, 2026-10-13 M0): a drawn motif the nearest neighbour has, at distance 0

-- the shape a form implies (sprawling: none, its own seeded field)
M.FORM_SHAPE = { clustered = "compact", radiating = "cross", linear = "linear", wide = "lens", fingers = "fingers",
	shore = "shore" }

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

function M.closeness(d)
	-- (quadratic: a town 2.5 km away still counts 0.75; offline, linear fading left neighbours too alike)
	local q = (tonumber(d) or math.huge) / M.RADIUS
	return clamp(1 - q * q, 0, 1)
end

--- Factors { [id] = x } for the ids under `key` ("style" | "form" | "shape" | "motif") in nbrs = { {dist, style, form,
--- shape, motifs = { id, ... }} }. min / floor: the strength (defaults per key). Ids no neighbour uses are absent (x1).
function M.factors(nbrs, key)
	local out = {}
	if not M.ON or type(nbrs) ~= "table" then return out end
	local min = key == "style" and M.STYLE_MIN or (key == "shape" and M.SHAPE_MIN
		or (key == "motif" and M.MOTIF_MIN or M.FORM_MIN))
	local floor = key == "style" and M.STYLE_FLOOR or M.FLOOR
	for _, n in ipairs(nbrs) do
		local ids
		if key == "motif" then ids = type(n.motifs) == "table" and n.motifs or {}
		else
			local id = n[key]
			if key == "shape" and id == nil and n.form then id = M.FORM_SHAPE[n.form] end
			ids = { id }
		end
		local c = M.closeness(n.dist)
		for _, id in ipairs(ids) do
			if c > 0 then out[id] = (out[id] or 1) * (1 - (1 - min) * c) end
		end
	end
	for id, f in pairs(out) do out[id] = math.max(floor, f) end
	return out
end

--- "id=x,id=x" (sorted) or "-" for a factors table.
function M.text(f)
	local ids = {}
	for id in pairs(f or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do parts[#parts + 1] = string.format("%s=%.2f", id, f[id]) end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- STYLE field `nbr`: "<count>/<styles nearby>" e.g. "3/EU_ORGANIC:clustered,EU_EXTENSION:linear".
function M.nbrText(nbrs)
	if type(nbrs) ~= "table" or #nbrs == 0 then return "0/-" end
	local parts = {}
	for _, n in ipairs(nbrs) do
		parts[#parts + 1] = string.format("%s:%s@%.0f", tostring(n.style or "-"), tostring(n.form or n.shape or "-"),
			tonumber(n.dist) or 0)
	end
	return #nbrs .. "/" .. table.concat(parts, ",")
end

--- Records a picker's applied factors on inputs.div (the driver logs them as STYLE divPen=).
function M.note(inputs, key, f)
	if type(inputs) ~= "table" or next(f or {}) == nil then return end
	inputs.div = inputs.div or {}
	inputs.div[key] = M.text(f)
end

--- STYLE field `divPen`: "style:<..>;shape:<..>;form:<..>;motif:<..>" or "-".
function M.penText(inputs)
	local d = type(inputs) == "table" and inputs.div or nil
	if d == nil then return "-" end
	local parts = {}
	for _, k in ipairs({ "style", "shape", "form", "motif" }) do
		if d[k] then parts[#parts + 1] = k .. ":" .. d[k] end
	end
	return #parts > 0 and table.concat(parts, ";") or "-"
end

--- The neighbour picks for town `t` at `pos` (pure; the driver supplies the sources): cands = { {town, x, y} };
--- savedOf(id) -> { style, form, shape, motifs } or nil (a saved frame: always counts); pickedOf(id) -> the same or nil (picked
--- this session: counts only for a lower town id, so the order on a fresh map is fixed). Nearest first.
function M.gather(t, pos, cands, savedOf, pickedOf)
	local out = {}
	if not M.ON then return out end
	for _, c in ipairs(cands or {}) do
		local id = c[1]
		if id ~= t then
			local d = math.sqrt((c[2] - pos[1]) ^ 2 + (c[3] - pos[2]) ^ 2)
			if d > 1 and d <= M.RADIUS then
				local p = savedOf and savedOf(id) or nil
				if p == nil and pickedOf and type(id) == "number" and type(t) == "number" and id < t then p = pickedOf(id) end
				if p and (p.style or p.form or p.shape or (p.motifs and #p.motifs > 0)) then
					out[#out + 1] = { town = id, dist = d, style = p.style, form = p.form, shape = p.shape, motifs = p.motifs }
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.town < b.town
	end)
	return out
end

return M
