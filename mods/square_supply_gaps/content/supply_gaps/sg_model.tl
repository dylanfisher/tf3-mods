-- Supply Gaps model (PLAN "Model"). PURE: no api.*, no base modules, so it is unit-tested offline
-- (tests/square_supply_gaps/test_model.lua). sg_gather.tl reads the engine into plain records
-- (sg_types.d.tl); sg_cache.tl keeps the catchables; this module decides which town buildings are gaps.
--
-- Rules (plans/square_supply_gaps/PLAN.md "Decisions"):
--   * needs c:     the building has an InputStock of c (passengers skipped by gather)
--   * delivers c:  a line whose stopConfig.load has c at some stop delivers c at each of its stops
--                  whose terminal unloads cargo (Terminal.cargoUnload ~= false)
--   * reached:     the building is a catchable of a station of a delivering group (in game the
--                  catchables are the TOWN_BUILDING entities, never their stockList)
--   * starved:     reached for c, but the building's input stock of c was 0 on the last
--                  STARVED_READS reads (Phase 2b; the stock count the building window shows as
--                  "{count}/{capacity}"). The streak keeps a building that just consumed its last unit
--                  between two deliveries from flickering in and out.
--   * area:        town x land use (the engine's district); per cargo: needed / covered (reached and,
--                  with includeStarved, not starved). Labels: sg_areas.tl (Phase 2c)
--   * gap:         "All needed" (selection nil): any need unreached, or (includeStarved) starved;
--                  one cargo: that need unreached / starved. Kind UNREACHED wins over STARVED.
-- Every loop over a map runs in sorted key order, so results never depend on `pairs` order.
-- Lua 5.1 safe (the game runs pre-5.3 Lua): no integer division, math.type or utf8.

local model : SupplyGapsModel = {}

-- groupCargo key meaning "delivers every cargo" ("Count stops without a line"). Cargo ids are >= 0.
model.ANY = -1

-- Cap on mission markers (PLAN "Rendering, track A").
model.MAX_MARKERS = 300

model.UNREACHED = "unreached"
model.STARVED = "starved"
-- 3 reads at the 10 s building cadence: empty for ~20 s straight before a starved marker shows.
model.STARVED_READS = 3
local STREAK_CAP <const> = 1000

function model.zeroStreak(prev : integer, count : integer) : integer
	if count == nil then return prev end
	if count > 0 then return 0 end
	return math.min((prev or 0) + 1, STREAK_CAP)
end

function model.areaKey(town : integer, landUse : integer) : integer
	return (town or -1) * 4 + (landUse or 0)
end

function model.sortedKeys(t : {integer : any}) : {integer}
	local out : {integer} = {}
	if t == nil then return out end
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

function model.scopeOrder(buildings : {integer : SupplyGapsBuilding}, towns : {integer : boolean}) : {integer}
	local out : {integer} = {}
	for __, b in ipairs(model.sortedKeys(buildings)) do
		if towns == nil or towns[buildings[b].town or -1] then out[#out + 1] = b end
	end
	return out
end

local function list<T>(t : {T}) : {T}
	return t or {}
end

--- Two reads of one building give the same compute() / markerPlan() result: same town, land use,
--- needs, position, and per need the same starved flag (zeroReads >= starvedReads). Stock counts and
--- streaks below the threshold don't matter. Lets the overlay skip compute when nothing changed.
function model.sameBuilding(a : SupplyGapsBuilding, b : SupplyGapsBuilding, starvedReads? : integer) : boolean
	if a == nil or b == nil then return a == b end
	if a.town ~= b.town or a.landUse ~= b.landUse then return false end
	local pa, pb = a.pos, b.pos
	if pa ~= pb then
		if pa == nil or pb == nil or pa[1] ~= pb[1] or pa[2] ~= pb[2] then return false end
	end
	local na, nb = list(a.needs), list(b.needs)
	if #na ~= #nb then return false end
	local k = starvedReads or model.STARVED_READS
	local za, zb = a.zeroReads or {}, b.zeroReads or {}
	for i = 1, #na do
		local c = na[i]
		if c ~= nb[i] then return false end
		if ((za[c] or 0) >= k) ~= ((zb[c] or 0) >= k) then return false end
	end
	return true
end

function model.deliveringGroups(lines : {SupplyGapsLine}, passenger : integer) : {integer : {integer : boolean}}
	local groupCargo : {integer : {integer : boolean}} = {}
	for __, line in ipairs(list(lines)) do
		local carries : {integer} = {}
		for __, c in ipairs(list(line.carries)) do
			if c ~= passenger and c >= 0 then carries[#carries + 1] = c end
		end
		if #carries > 0 then
			for __, stop in ipairs(list(line.stops)) do
				if stop.unload ~= false and stop.stationGroup ~= nil and stop.stationGroup >= 0 then
					local set = groupCargo[stop.stationGroup]
					if set == nil then
						set = {}
						groupCargo[stop.stationGroup] = set
					end
					for __, c in ipairs(carries) do set[c] = true end
				end
			end
		end
	end
	return groupCargo
end

function model.addUnlinedGroups(groupCargo : {integer : {integer : boolean}}, unloadGroups : {integer}) : {integer : {integer : boolean}}
	groupCargo = groupCargo or {}
	for __, g in ipairs(list(unloadGroups)) do
		local set = groupCargo[g]
		if set == nil then
			set = {}
			groupCargo[g] = set
		end
		set[model.ANY] = true
	end
	return groupCargo
end

function model.compute(world : SupplyGapsWorld, selection : integer) : SupplyGapsView
	local buildings = world.buildings or {}
	local catchables = world.catchables or {}
	local groupStations = world.groupStations or {}
	local order = world.order or model.sortedKeys(buildings)
	local includeStarved = world.includeStarved == true
	local starvedReads = world.starvedReads or model.STARVED_READS

	-- reached[b] = cargo set (ANY key included) of every delivering group reaching b.
	local reached : {integer : {integer : boolean}} = {}
	for __, g in ipairs(model.sortedKeys(world.groupCargo)) do
		local cargoSet = world.groupCargo[g]
		for __, station in ipairs(list(groupStations[g])) do
			for __, b in ipairs(list(catchables[station])) do
				if buildings[b] ~= nil then
					local set = reached[b]
					if set == nil then
						set = {}
						reached[b] = set
					end
					for c in pairs(cargoSet) do set[c] = true end
				end
			end
		end
	end

	local view : SupplyGapsView = { cargos = {}, gaps = {}, starved = {}, kind = {}, gapList = {}, total = 0,
		unreachedTotal = 0, starvedTotal = 0, buildings = 0, areas = {} }
	for __, b in ipairs(order) do
		local bld = buildings[b]
		local needs = bld ~= nil and list(bld.needs) or {}
		if #needs > 0 then
			view.buildings = view.buildings + 1
			local set = reached[b] or {}
			local any = set[model.ANY] == true
			local zero = bld.zeroReads or {}
			local missing : {integer} = {}
			local empty : {integer} = {}
			-- Phase 2c: the building's district (town x land use); unknown land use has no district.
			local area : SupplyGapsArea = nil
			local lu = bld.landUse or 0
			if lu >= 1 and lu <= 3 then
				local key = model.areaKey(bld.town, lu)
				area = view.areas[key]
				if area == nil then
					area = { key = key, town = bld.town or -1, landUse = lu, cargos = {}, positioned = 0 }
					view.areas[key] = area
				end
				local pos = bld.pos
				if pos ~= nil and pos[1] ~= nil and pos[2] ~= nil then
					-- running mean, so no separate sums are kept
					local n = area.positioned + 1
					area.x = (area.x or 0) + (pos[1] - (area.x or 0)) / n
					area.y = (area.y or 0) + (pos[2] - (area.y or 0)) / n
					area.positioned = n
				end
			end
			for __, c in ipairs(needs) do
				local cc = view.cargos[c]
				if cc == nil then
					cc = { needed = 0, reached = 0, starved = 0, towns = {} }
					view.cargos[c] = cc
				end
				local tc = cc.towns[bld.town or -1]
				if tc == nil then
					tc = { needed = 0, reached = 0, starved = 0 }
					cc.towns[bld.town or -1] = tc
				end
				cc.needed = cc.needed + 1
				tc.needed = tc.needed + 1
				local covered = false
				if any or set[c] then
					cc.reached = cc.reached + 1
					tc.reached = tc.reached + 1
					covered = true
					if (zero[c] or 0) >= starvedReads then
						cc.starved = cc.starved + 1
						tc.starved = tc.starved + 1
						empty[#empty + 1] = c
						-- starved counts as not covered only while starved gaps are shown
						if includeStarved then covered = false end
					end
				else
					missing[#missing + 1] = c
				end
				if area ~= nil then
					local ac = area.cargos[c]
					if ac == nil then
						ac = { needed = 0, covered = 0 }
						area.cargos[c] = ac
					end
					ac.needed = ac.needed + 1
					if covered then ac.covered = ac.covered + 1 end
				end
			end
			local isUnreached, isStarved = false, false
			if selection == nil then
				isUnreached = #missing > 0
				isStarved = #empty > 0
			else
				for __, c in ipairs(missing) do
					if c == selection then isUnreached = true end
				end
				for __, c in ipairs(empty) do
					if c == selection then isStarved = true end
				end
			end
			if isUnreached or (includeStarved and isStarved) then
				table.sort(missing)
				table.sort(empty)
				view.gaps[b] = missing
				view.starved[b] = empty
				view.gapList[#view.gapList + 1] = b
				if isUnreached then
					view.kind[b] = model.UNREACHED
					view.unreachedTotal = view.unreachedTotal + 1
				else
					view.kind[b] = model.STARVED
					view.starvedTotal = view.starvedTotal + 1
				end
			end
		end
	end
	view.total = #view.gapList
	return view
end

--- k-th smallest value of `a` (1-based; a is reordered). Iterative quickselect, middle pivot.
local function kth(a : {number}, k : integer) : number
	local lo, hi = 1, #a
	while lo < hi do
		local pivot = a[math.floor((lo + hi) / 2)]
		local i, j = lo, hi
		while i <= j do
			while a[i] < pivot do i = i + 1 end
			while a[j] > pivot do j = j - 1 end
			if i <= j then
				a[i], a[j] = a[j], a[i]
				i, j = i + 1, j - 1
			end
		end
		if k <= j then
			hi = j
		elseif k >= i then
			lo = i
		else
			return a[k]
		end
	end
	return a[k]
end

function model.markerPlan(gapList : {integer}, buildings : {integer : SupplyGapsBuilding}, camera : SupplyGapsCamera, cap : integer) : {integer}
	buildings = buildings or {}
	local cx = camera ~= nil and camera[1] or 0
	local cy = camera ~= nil and camera[2] or 0
	local n = cap or model.MAX_MARKERS
	local dist : {integer : number} = {}
	local items : {integer} = {}
	local ds : {number} = {}
	for __, b in ipairs(list(gapList)) do
		local bld = buildings[b]
		local pos = bld ~= nil and bld.pos or nil
		local d : number
		if pos ~= nil then
			local dx, dy = pos[1] - cx, pos[2] - cy
			d = dx * dx + dy * dy
		else
			d = math.huge
		end
		dist[b] = d
		items[#items + 1] = b
		ds[#ds + 1] = d
	end
	-- Many more gaps than markers (perf review): keep only those within the n-th smallest distance
	-- (ties included) before sorting, so the sort is O(n log n) instead of over every gap. Same result.
	if n >= 1 and #items > 2 * n then
		local thr = kth(ds, n)
		local near : {integer} = {}
		for __, b in ipairs(items) do
			if dist[b] <= thr then near[#near + 1] = b end
		end
		items = near
	end
	table.sort(items, function(a : integer, b : integer) : boolean
		if dist[a] ~= dist[b] then return dist[a] < dist[b] end
		return a < b
	end)
	local out : {integer} = {}
	for i = 1, math.min(n, #items) do out[i] = items[i] end
	return out
end

function model.diff(prev : {integer : boolean}, next : {integer}) : SupplyGapsDiff
	prev = prev or {}
	local nextSet : {integer : boolean} = {}
	local add : {integer} = {}
	for __, e in ipairs(list(next)) do
		if not nextSet[e] then
			nextSet[e] = true
			if not prev[e] then add[#add + 1] = e end
		end
	end
	local remove : {integer} = {}
	for __, e in ipairs(model.sortedKeys(prev)) do
		if prev[e] and not nextSet[e] then remove[#remove + 1] = e end
	end
	table.sort(add)
	return { add = add, remove = remove }
end

return model
