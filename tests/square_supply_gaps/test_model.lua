-- sg_model: the pure gap model (PLAN "Model"). Fake worlds only. Shapes: sg_types.d.tl.

local model = ug_require "square_supply_gaps::/supply_gaps/sg_model.tl"

local PASS, FISH, TOOLS, FOOD, GOODS = 0, 7, 9, 4, 11
local RES, COM, IND = 1, 2, 3

-- building: entity b, stockList b + 1000, town, needs, landUse, pos
local function bld(b, town, needs, extra)
	local r = { entity = b, town = town or 1, landUse = COM, needs = needs, stockList = b + 1000, pos = { b, 0, 0 } }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local function buildings(...)
	local out = {}
	for _, b in ipairs({ ... }) do out[b.entity] = b end
	return out
end

local function line(entity, carries, stops)
	local s = {}
	for i, st in ipairs(stops) do
		if type(st) == "number" then s[i] = { stationGroup = st, unload = true } else s[i] = st end
	end
	return { entity = entity, carries = carries, stops = s }
end

-- world: group g has station g * 10; catchables per station
local function world(blds, groupCargo, catch)
	local gs, cs = {}, {}
	for g in pairs(groupCargo) do gs[g] = { g * 10 } end
	for g, list in pairs(catch or {}) do cs[g * 10] = list end
	return { buildings = blds, groupCargo = groupCargo, groupStations = gs, catchables = cs }
end

-- deliveringGroups ----------------------------------------------------------------

test("deliveringGroups: a line carrying c delivers c at every unloading stop", function()
	local g = model.deliveringGroups({ line(1, { FISH }, { 100, 200 }) }, PASS)
	eq(g, { [100] = { [FISH] = true }, [200] = { [FISH] = true } })
end)

test("deliveringGroups: passengers ignored, passenger-only lines deliver nothing", function()
	local g = model.deliveringGroups({
		line(1, { PASS }, { 100 }),
		line(2, { PASS, TOOLS }, { 200 }),
	}, PASS)
	eq(g, { [200] = { [TOOLS] = true } })
end)

test("deliveringGroups: cargoUnload=false stop ignored", function()
	local g = model.deliveringGroups({
		line(1, { FISH }, { { stationGroup = 100, unload = false }, 200 }),
	}, PASS)
	eq(g, { [200] = { [FISH] = true } })
end)

test("deliveringGroups: lines merge per group; nil unload counts as unloading", function()
	local g = model.deliveringGroups({
		line(1, { FISH }, { 100 }),
		line(2, { TOOLS, FOOD }, { { stationGroup = 100 } }),
		line(3, {}, { 300 }),
	}, PASS)
	eq(g, { [100] = { [FISH] = true, [TOOLS] = true, [FOOD] = true } })
end)

test("deliveringGroups: nil / empty input and negative groups", function()
	eq(model.deliveringGroups(nil, PASS), {})
	eq(model.deliveringGroups({ line(1, { FISH }, { -1 }) }, PASS), {})
end)

test("addUnlinedGroups: listed groups deliver ANY, existing cargos kept", function()
	local g = model.addUnlinedGroups({ [100] = { [FISH] = true } }, { 100, 200 })
	eq(g, { [100] = { [FISH] = true, [model.ANY] = true }, [200] = { [model.ANY] = true } })
	eq(model.addUnlinedGroups(nil, { 5 }), { [5] = { [model.ANY] = true } })
end)

-- compute ---------------------------------------------------------------------------

test("compute: needs come from the building's needs list (stock list)", function()
	local w = world(buildings(bld(1, 1, { FISH, TOOLS }), bld(2, 1, {})), {}, {})
	local v = model.compute(w, nil)
	eq(v.buildings, 1)
	eq(v.cargos[FISH], { needed = 1, reached = 0, starved = 0, towns = { [1] = { needed = 1, reached = 0, starved = 0 } } })
	eq(v.gaps, { [1] = { FISH, TOOLS } })
	eq(v.gapList, { 1 })
	eq(v.total, 1)
end)

test("compute: residential buildings with needs count like any other", function()
	local w = world(buildings(bld(1, 1, { FOOD }, { landUse = RES }), bld(2, 1, { FOOD }, { landUse = IND })),
		{ [100] = { [FOOD] = true } }, { [100] = { 2 } })
	local v = model.compute(w, nil)
	eq(v.gapList, { 1 })
	eq(v.cargos[FOOD].needed, 2)
	eq(v.cargos[FOOD].reached, 1)
end)

test("compute: catchable = building entity reaches it", function()
	local w = world(buildings(bld(1, 1, { FISH })), { [100] = { [FISH] = true } }, { [100] = { 1 } })
	local v = model.compute(w, nil)
	eq(v.total, 0)
end)

test("compute: a stockList catchable does not count (in game catchables are buildings)", function()
	local w = world(buildings(bld(1, 1, { FISH })), { [100] = { [FISH] = true } }, { [100] = { 1001 } })
	eq(model.compute(w, nil).gapList, { 1 })
end)

test("compute: a group delivering another cargo does not reach the need", function()
	local w = world(buildings(bld(1, 1, { FISH })), { [100] = { [TOOLS] = true } }, { [100] = { 1 } })
	eq(model.compute(w, nil).gapList, { 1 })
end)

test("compute: unrelated catchables (industries, other entities) ignored", function()
	local w = world(buildings(bld(1, 1, { FISH })), { [100] = { [FISH] = true } }, { [100] = { 555, 9999 } })
	eq(model.compute(w, nil).gapList, { 1 })
end)

test("compute: All needed = any unreached need; single cargo = that need", function()
	local blds = buildings(
		bld(1, 1, { FISH, TOOLS }), -- fish reached, tools not
		bld(2, 1, { FISH }),        -- fish not reached
		bld(3, 1, { TOOLS }),       -- tools not reached
		bld(4, 1, { FISH }))        -- reached
	local w = world(blds, { [100] = { [FISH] = true } }, { [100] = { 1, 4 } })
	eq(model.compute(w, nil).gapList, { 1, 2, 3 })
	eq(model.compute(w, nil).gaps[1], { TOOLS })
	eq(model.compute(w, FISH).gapList, { 2 })
	eq(model.compute(w, TOOLS).gapList, { 1, 3 })
	eq(model.compute(w, GOODS).gapList, {})
end)

test("compute: ANY group reaches every need", function()
	local w = world(buildings(bld(1, 1, { FISH, TOOLS }), bld(2, 1, { FOOD })),
		{ [100] = { [model.ANY] = true } }, { [100] = { 1 } })
	local v = model.compute(w, nil)
	eq(v.gapList, { 2 })
	eq(v.cargos[FISH].reached, 1)
	eq(v.cargos[TOOLS].reached, 1)
end)

test("compute: union of every station of a group", function()
	local w = world(buildings(bld(1, 1, { FISH }), bld(2, 1, { FISH })), { [100] = { [FISH] = true } }, {})
	w.groupStations[100] = { 1000, 1001 }
	w.catchables = { [1000] = { 1 }, [1001] = { 2002 } } -- 2002: nothing
	eq(model.compute(w, nil).gapList, { 2 })
	w.catchables[1001] = { 2 }
	eq(model.compute(w, nil).gapList, {})
end)

test("compute: per-town counts", function()
	local w = world(buildings(bld(1, 1, { FISH }), bld(2, 2, { FISH }), bld(3, 2, { FISH })),
		{ [100] = { [FISH] = true } }, { [100] = { 3 } })
	local v = model.compute(w, FISH)
	eq(v.cargos[FISH].towns, { [1] = { needed = 1, reached = 0, starved = 0 }, [2] = { needed = 2, reached = 1, starved = 0 } })
end)

test("compute: groups without stations or catchables, empty world", function()
	local w = { buildings = buildings(bld(1, 1, { FISH })), groupCargo = { [100] = { [FISH] = true } } }
	eq(model.compute(w, nil).gapList, { 1 })
	local v = model.compute({}, nil)
	eq(v.total, 0)
	eq(v.buildings, 0)
end)

test("compute: deterministic regardless of insertion order", function()
	local a, b = {}, {}
	for i = 1, 50 do a[i] = bld(i, i % 3, { FISH }) end
	for i = 50, 1, -1 do b[#b + 1] = bld(i, i % 3, { FISH }) end
	local v1 = model.compute(world(buildings(table.unpack(a)), { [100] = { [FISH] = true } }, { [100] = { 3, 9, 27 } }), nil)
	local v2 = model.compute(world(buildings(table.unpack(b)), { [100] = { [FISH] = true } }, { [100] = { 27, 9, 3 } }), nil)
	eq(v1.gapList, v2.gapList)
	eq(#v1.gapList, 47)
	for i = 2, #v1.gapList do ok(v1.gapList[i - 1] < v1.gapList[i]) end
end)

-- starved (Phase 2b) -----------------------------------------------------------------

-- Buildings 1..3 need fish (+ 3 needs food); group 100 delivers fish and food and reaches 1 and 3.
local function starvedWorld(z1, z2, z3, include)
	local w = world(buildings(
		bld(1, 1, { FISH }, { zeroReads = { [FISH] = z1 } }),
		bld(2, 1, { FISH }, { zeroReads = { [FISH] = z2 } }),
		bld(3, 1, { FISH, FOOD }, { zeroReads = { [FISH] = z3, [FOOD] = 0 } })),
		{ [100] = { [FISH] = true, [FOOD] = true } }, { [100] = { 1, 3 } })
	w.includeStarved = include ~= false
	return w
end

test("zeroStreak: +1 on empty, 0 on stock, unchanged on a failed read", function()
	eq(model.zeroStreak(nil, 0), 1)
	eq(model.zeroStreak(2, 0), 3)
	eq(model.zeroStreak(5, 3), 0)
	eq(model.zeroStreak(4, nil), 4)
	eq(model.zeroStreak(nil, nil), nil)
	eq(model.zeroStreak(1000, 0), 1000) -- capped
end)

test("starved: reached + empty for STARVED_READS reads; unreached wins; kinds and totals", function()
	local N = model.STARVED_READS
	local v = model.compute(starvedWorld(N, N, N - 1), nil)
	eq(v.gapList, { 1, 2 })
	eq(v.kind, { [1] = model.STARVED, [2] = model.UNREACHED })
	eq(v.starved[1], { FISH })
	eq(v.gaps[1], {})
	eq(v.gaps[2], { FISH })
	eq(v.unreachedTotal, 1)
	eq(v.starvedTotal, 1)
	eq(v.total, 2)
	eq(v.cargos[FISH], { needed = 3, reached = 2, starved = 1, towns = { [1] = { needed = 3, reached = 2, starved = 1 } } })
	eq(v.cargos[FOOD].starved, 0)
end)

test("starved: an empty read below the streak is not starved (no flicker)", function()
	local v = model.compute(starvedWorld(1, 0, 2), nil)
	eq(v.gapList, { 2 })
	eq(v.cargos[FISH].starved, 0)
end)

test("starved: hidden when includeStarved is off, still counted per cargo", function()
	local N = model.STARVED_READS
	local v = model.compute(starvedWorld(N, 0, N, false), nil)
	eq(v.gapList, { 2 })
	eq(v.starvedTotal, 0)
	eq(v.cargos[FISH].starved, 2)
end)

test("starved: single-cargo selection only looks at that cargo", function()
	local N = model.STARVED_READS
	local w = starvedWorld(0, 0, N)
	eq(model.compute(w, FISH).kind, { [2] = model.UNREACHED, [3] = model.STARVED })
	eq(model.compute(w, FOOD).gapList, {})
end)

test("starved: ANY ('Count stops without a line') reaches, so empty stocks there are starved", function()
	local N = model.STARVED_READS
	local w = world(buildings(bld(1, 1, { GOODS }, { zeroReads = { [GOODS] = N } })), { [100] = { [model.ANY] = true } }, { [100] = { 1 } })
	w.includeStarved = true
	eq(model.compute(w, nil).kind, { [1] = model.STARVED })
end)

test("starved: no zeroReads (never read) is never starved", function()
	local w = world(buildings(bld(1, 1, { FISH })), { [100] = { [FISH] = true } }, { [100] = { 1 } })
	w.includeStarved = true
	eq(model.compute(w, nil).gapList, {})
end)

test("compute: a caller-supplied order is used as given", function()
	local w = world(buildings(bld(1, 1, { FISH }), bld(2, 1, { FISH })), {}, {})
	w.order = { 2 }
	eq(model.compute(w, nil).gapList, { 2 })
end)

-- markerPlan / diff -------------------------------------------------------------------

test("markerPlan: nearest first, cap respected", function()
	local blds = buildings(bld(1, 1, { FISH }), bld(5, 1, { FISH }), bld(9, 1, { FISH }), bld(20, 1, { FISH }))
	eq(model.markerPlan({ 1, 5, 9, 20 }, blds, { 8, 0 }, 2), { 9, 5 })
	eq(model.markerPlan({ 1, 5, 9, 20 }, blds, { 8, 0 }, 10), { 9, 5, 1, 20 })
end)

test("markerPlan: ties broken by entity id, no position last", function()
	local blds = buildings(bld(3, 1, { FISH }, { pos = { 2, 0, 0 } }), bld(1, 1, { FISH }, { pos = { -2, 0, 0 } }),
		bld(2, 1, { FISH }, { pos = nil }), bld(4, 1, { FISH }, { pos = { 0, 2, 0 } }))
	blds[2].pos = nil
	eq(model.markerPlan({ 4, 3, 2, 1 }, blds, { 0, 0 }, 10), { 1, 3, 4, 2 })
end)

test("markerPlan: default cap MAX_MARKERS, nil camera = origin", function()
	local blds, gaps = {}, {}
	for i = 1, model.MAX_MARKERS + 20 do
		blds[i] = bld(i, 1, { FISH })
		gaps[i] = i
	end
	local plan = model.markerPlan(gaps, blds, nil, nil)
	eq(#plan, model.MAX_MARKERS)
	eq(plan[1], 1)
	eq(plan[#plan], model.MAX_MARKERS)
end)

test("diff: add new, remove gone, keep shared", function()
	local d = model.diff({ [1] = true, [2] = true, [3] = true }, { 4, 2, 3, 5 })
	eq(d, { add = { 4, 5 }, remove = { 1 } })
end)

test("diff: from nothing and to nothing", function()
	eq(model.diff(nil, { 2, 1 }), { add = { 1, 2 }, remove = {} })
	eq(model.diff({ [7] = true, [3] = true }, {}), { add = {}, remove = { 3, 7 } })
	eq(model.diff({}, { 1, 1 }), { add = { 1 }, remove = {} })
end)

test("sortedKeys", function()
	eq(model.sortedKeys({ [5] = 1, [2] = 1, [9] = 1 }), { 2, 5, 9 })
	eq(model.sortedKeys(nil), {})
end)

-- Phase 2d: scopeOrder (only towns in view) ------------------------------------------

test("scopeOrder: sorted ids of buildings in the listed towns; nil = every building", function()
	local blds = buildings(bld(3, 100, { FISH }), bld(1, 200, { FISH }), bld(2, 100, { FOOD }), bld(4, 300, { FISH }))
	eq(model.scopeOrder(blds, { [100] = true }), { 2, 3 })
	eq(model.scopeOrder(blds, { [100] = true, [300] = true }), { 2, 3, 4 })
	eq(model.scopeOrder(blds, {}), {})
	eq(model.scopeOrder(blds, nil), { 1, 2, 3, 4 })
end)

test("compute with a scoped order: counts, gaps and areas cover only the towns in view", function()
	local blds = buildings(bld(1, 100, { FISH }), bld(2, 100, { FISH, FOOD }), bld(3, 200, { FISH }), bld(4, 200, { GOODS }))
	local w = world(blds, { [5] = { [FISH] = true } }, { [5] = { 1, 3 } })
	w.order = model.scopeOrder(blds, { [100] = true })
	local v = model.compute(w, nil)
	eq(v.buildings, 2)
	eq(v.gapList, { 2 })
	eq(v.cargos[FISH].needed, 2)
	eq(v.cargos[FISH].reached, 1)
	eq(v.cargos[GOODS], nil)
	eq(model.sortedKeys(v.cargos[FISH].towns), { 100 })
	eq(model.sortedKeys(v.areas), { model.areaKey(100, COM) })
	-- the whole map
	w.order = model.scopeOrder(blds, nil)
	local all = model.compute(w, nil)
	eq(all.buildings, 4)
	eq(all.gapList, { 2, 4 })
	eq(all.cargos[FISH].needed, 3)
end)

-- perf review (2026-10-09) ------------------------------------------------------------------

local function naivePlan(gapList, blds, camera, cap)
	local dist, items = {}, {}
	for _, b in ipairs(gapList) do
		local p = blds[b] and blds[b].pos
		dist[b] = p and ((p[1] - camera[1]) ^ 2 + (p[2] - camera[2]) ^ 2) or math.huge
		items[#items + 1] = b
	end
	table.sort(items, function(a, b) if dist[a] ~= dist[b] then return dist[a] < dist[b] end return a < b end)
	local out = {}
	for i = 1, math.min(cap, #items) do out[i] = items[i] end
	return out
end

test("markerPlan: many more gaps than the cap (quickselect path) = full sort, ties and no position included", function()
	local seed = 7
	local function r(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n
	end
	for round = 1, 20 do
		local blds, gaps = {}, {}
		local n = 50 + r(400)
		for i = 1, n do
			local b = 1000 + r(5000)
			if blds[b] == nil then
				-- coarse grid: many equal distances
				blds[b] = bld(b, 1, { FISH }, { pos = (r(10) == 0) and nil or { r(20) * 10, r(20) * 10, 0 } })
				gaps[#gaps + 1] = b
			end
		end
		local cap = 1 + r(40)
		local cam = { r(200), r(200) }
		eq(model.markerPlan(gaps, blds, cam, cap), naivePlan(gaps, blds, cam, cap), "round " .. round)
	end
end)

test("sameBuilding: stock counts and short streaks ignored; needs, town, land use, position, starved flag count", function()
	local a = bld(1, 1, { FISH, TOOLS }, { stock = { [FISH] = 3, [TOOLS] = 0 }, zeroReads = { [FISH] = 0, [TOOLS] = 1 } })
	local b = bld(1, 1, { FISH, TOOLS }, { stock = { [FISH] = 1, [TOOLS] = 0 }, zeroReads = { [FISH] = 0, [TOOLS] = 2 } })
	ok(model.sameBuilding(a, b))
	b.zeroReads[TOOLS] = 3 -- starved now
	ok(not model.sameBuilding(a, b))
	a.zeroReads[TOOLS] = 7 -- both starved
	ok(model.sameBuilding(a, b))
	ok(not model.sameBuilding(a, bld(1, 1, { FISH }, { zeroReads = {} })))
	ok(not model.sameBuilding(a, bld(1, 2, { FISH, TOOLS }, { zeroReads = { [TOOLS] = 3 } })))
	ok(not model.sameBuilding(a, bld(1, 1, { FISH, TOOLS }, { landUse = RES, zeroReads = { [TOOLS] = 3 } })))
	ok(not model.sameBuilding(a, bld(1, 1, { FISH, TOOLS }, { pos = { 9, 9, 0 }, zeroReads = { [TOOLS] = 3 } })))
	ok(model.sameBuilding(nil, nil))
	ok(not model.sameBuilding(a, nil))
	ok(model.sameBuilding(a, b, 8)) -- threshold 8: neither 7 nor 3 is starved
end)
