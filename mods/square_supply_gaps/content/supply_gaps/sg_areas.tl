-- Supply Gaps area labels, pure planner (PLAN "Phase 2c"). No api.*, unit-tested offline
-- (tests/square_supply_gaps/test_areas.lua).
--
-- An area is a town district: town x land use, the engine's own district (Gui.SelectionDetails.Town
-- {townEntity, districtType}, api/tealdef/api/gui.d.tl:213-219; TOWN.cargoNeeds per district,
-- api/tealdef/api/engine.d.tl:1294-1295). model.compute fills view.areas with, per cargo, the
-- buildings needing it and the covered ones (reached and, with "Include in-range but empty", not
-- starved). This module picks which areas get a label (nearest the camera, capped) and which chips
-- ("[icon] 73%") each shows. Deterministic: every tie is broken by key / cargo id.
-- Lua 5.1 safe: no integer division operator, math.floor only.

local areas : SupplyGapsAreas = {}

-- At most this many labels (areas nearest the camera centre).
areas.MAX_LABELS = 30
-- "All needed": at most this many chips per area (its worst cargos).
areas.WORST = 3

function areas.pct(covered : integer, needed : integer) : integer
	if needed == nil or needed <= 0 then return 0 end
	-- floor, so an area with one gap left never reads 100 %
	return math.floor((covered or 0) * 100 / needed)
end

function areas.tone(pct : integer) : string
	if pct >= 90 then return "Normal" end
	if pct >= 50 then return "Inferior" end
	return "Poor"
end

local function chip(c : integer, ac : SupplyGapsAreaCargo) : SupplyGapsChip
	local p = areas.pct(ac.covered, ac.needed)
	return { cargo = c, pct = p, needed = ac.needed, covered = ac.covered, tone = areas.tone(p) }
end

function areas.chips(area : SupplyGapsArea, selection : integer, worst : integer) : {SupplyGapsChip}
	local out : {SupplyGapsChip} = {}
	if area == nil or area.cargos == nil then return out end
	if selection ~= nil then
		local ac = area.cargos[selection]
		if ac ~= nil and ac.needed > 0 then out[1] = chip(selection, ac) end
		return out
	end
	local all : {SupplyGapsChip} = {}
	for c, ac in pairs(area.cargos) do
		if ac.needed > 0 then all[#all + 1] = chip(c, ac) end
	end
	if #all == 0 then return out end
	table.sort(all, function(a : SupplyGapsChip, b : SupplyGapsChip) : boolean
		if a.pct ~= b.pct then return a.pct < b.pct end
		if a.needed ~= b.needed then return a.needed > b.needed end
		return a.cargo < b.cargo
	end)
	local n = worst or areas.WORST
	for __, ch in ipairs(all) do
		if ch.pct < 100 and #out < n then out[#out + 1] = ch end
	end
	if #out == 0 then
		-- fully covered: one chip, so the player sees the district is fine
		out[1] = all[1]
	end
	return out
end

--- Every area with chips for `selection`, unsorted and without a distance: what areas.labels picks
--- from. Independent of the camera, so the overlay keeps it while only the camera moves (perf review).
function areas.candidates(list : {integer : SupplyGapsArea}, selection : integer, worst : integer) : {SupplyGapsAreaLabel}
	local items : {SupplyGapsAreaLabel} = {}
	for key, area in pairs(list or {}) do
		local chips = areas.chips(area, selection, worst)
		if #chips > 0 then
			items[#items + 1] = { key = key, town = area.town, landUse = area.landUse, chips = chips, x = area.x, y = area.y }
		end
	end
	return items
end

--- The `cap` candidates nearest the camera (distance, then key), as new label records.
function areas.nearest(candidates : {SupplyGapsAreaLabel}, camera : SupplyGapsCamera, cap : integer) : {SupplyGapsAreaLabel}
	local cx = camera ~= nil and camera[1] or 0
	local cy = camera ~= nil and camera[2] or 0
	local items : {SupplyGapsAreaLabel} = {}
	for __, c in ipairs(candidates or {}) do
		local d = math.huge
		if c.x ~= nil and c.y ~= nil then
			local dx, dy = c.x - cx, c.y - cy
			d = dx * dx + dy * dy
		end
		items[#items + 1] = { key = c.key, town = c.town, landUse = c.landUse, chips = c.chips, dist = d }
	end
	table.sort(items, function(a : SupplyGapsAreaLabel, b : SupplyGapsAreaLabel) : boolean
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.key < b.key
	end)
	local n = cap or areas.MAX_LABELS
	local out : {SupplyGapsAreaLabel} = {}
	for i = 1, math.min(n, #items) do out[i] = items[i] end
	return out
end

function areas.labels(list : {integer : SupplyGapsArea}, selection : integer, camera : SupplyGapsCamera, cap : integer, worst : integer) : {SupplyGapsAreaLabel}
	return areas.nearest(areas.candidates(list, selection, worst), camera, cap)
end

return areas
