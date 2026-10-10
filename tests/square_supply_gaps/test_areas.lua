-- Phase 2c area labels: model.compute's per-district counts (town x land use), the pure planner
-- sg_areas.tl (percent, tone, chips, nearest-camera cap) and overlay.makeLabelStore.

local model = ug_require "square_supply_gaps::/supply_gaps/sg_model.tl"
local areas = ug_require "square_supply_gaps::/supply_gaps/sg_areas.tl"

local FISH, TOOLS, FOOD, GOODS = 7, 9, 4, 11
local RES, COM, IND = 1, 2, 3

local function bld(b, town, landUse, needs, extra)
	local r = { entity = b, town = town, landUse = landUse, needs = needs, stockList = b + 1000, pos = { b, 0, 0 } }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end

local function blds(...)
	local out = {}
	for _, b in ipairs({ ... }) do out[b.entity] = b end
	return out
end

-- group 5 (station 50) delivers fish, catchment = `reach`
local function world(buildings, reach, extra)
	local w = {
		buildings = buildings,
		groupCargo = { [5] = { [FISH] = true } },
		groupStations = { [5] = { 50 } },
		catchables = { [50] = reach },
	}
	for k, v in pairs(extra or {}) do w[k] = v end
	return w
end

local function area(cargos, x, y, town, landUse)
	local a = { key = model.areaKey(town or 1, landUse or COM), town = town or 1, landUse = landUse or COM,
		cargos = {}, x = x, y = y, positioned = x and 1 or 0 }
	for c, nc in pairs(cargos) do a.cargos[c] = { needed = nc[1], covered = nc[2] } end
	return a
end

-- model.compute: areas --------------------------------------------------------------

test("areas: grouped by town x land use; covered = reached", function()
	local v = model.compute(world(blds(
		bld(1, 100, COM, { FISH }), bld(2, 100, COM, { FISH }), bld(3, 100, COM, { FISH }),
		bld(4, 100, RES, { FISH }), bld(5, 200, COM, { FISH })
	), { 1, 2, 5 }), FISH)
	local com = v.areas[model.areaKey(100, COM)]
	eq(com.cargos[FISH], { needed = 3, covered = 2 })
	eq(com.town, 100)
	eq(com.landUse, COM)
	eq(v.areas[model.areaKey(100, RES)].cargos[FISH], { needed = 1, covered = 0 })
	eq(v.areas[model.areaKey(200, COM)].cargos[FISH], { needed = 1, covered = 1 })
end)

test("areas: unknown land use (0) has no area", function()
	local v = model.compute(world(blds(bld(1, 100, 0, { FISH })), {}), nil)
	eq(model.sortedKeys(v.areas), {})
	eq(v.buildings, 1)
end)

test("areas: starved is not covered while includeStarved, covered when off", function()
	local b = blds(bld(1, 100, COM, { FISH }, { zeroReads = { [FISH] = 3 } }), bld(2, 100, COM, { FISH }))
	local on = model.compute(world(b, { 1, 2 }, { includeStarved = true }), nil)
	eq(on.areas[model.areaKey(100, COM)].cargos[FISH], { needed = 2, covered = 1 })
	local off = model.compute(world(b, { 1, 2 }, { includeStarved = false }), nil)
	eq(off.areas[model.areaKey(100, COM)].cargos[FISH], { needed = 2, covered = 2 })
end)

test("areas: every need counted, independent of the selection", function()
	local b = blds(bld(1, 100, COM, { FOOD, FISH }), bld(2, 100, COM, { FOOD }))
	local v = model.compute(world(b, { 1 }), FISH)
	local a = v.areas[model.areaKey(100, COM)]
	eq(a.cargos[FISH], { needed = 1, covered = 1 })
	eq(a.cargos[FOOD], { needed = 2, covered = 0 })
end)

test("areas: centroid of positioned buildings only", function()
	local b = blds(bld(1, 100, COM, { FISH }, { pos = { 10, 20, 0 } }), bld(2, 100, COM, { FISH }, { pos = { 30, 40, 0 } }),
		bld(3, 100, COM, { FISH }, { pos = false }))
	b[3].pos = nil
	local a = model.compute(world(b, {}), nil).areas[model.areaKey(100, COM)]
	near(a.x, 20)
	near(a.y, 30)
	eq(a.positioned, 2)
end)

test("areas: ANY (stops without a line) covers every cargo", function()
	local w = world(blds(bld(1, 100, IND, { TOOLS, GOODS })), { 1 })
	w.groupCargo = { [5] = { [model.ANY] = true } }
	local a = model.compute(w, nil).areas[model.areaKey(100, IND)]
	eq(a.cargos[TOOLS], { needed = 1, covered = 1 })
	eq(a.cargos[GOODS], { needed = 1, covered = 1 })
end)

-- pct / tone -------------------------------------------------------------------------

test("pct: floor, so one gap never reads 100; needed 0 -> 0", function()
	eq(areas.pct(73, 100), 73)
	eq(areas.pct(199, 200), 99)
	eq(areas.pct(2, 3), 66)
	eq(areas.pct(5, 5), 100)
	eq(areas.pct(0, 0), 0)
	eq(areas.pct(1, nil), 0)
end)

test("tone: >= 90 Normal, >= 50 Inferior, else Poor", function()
	eq(areas.tone(100), "Normal")
	eq(areas.tone(90), "Normal")
	eq(areas.tone(89), "Inferior")
	eq(areas.tone(50), "Inferior")
	eq(areas.tone(49), "Poor")
	eq(areas.tone(0), "Poor")
end)

-- chips ------------------------------------------------------------------------------

test("chips: one cargo selected -> that cargo, even at 100 %", function()
	local a = area({ [FISH] = { 4, 3 }, [FOOD] = { 2, 2 } }, 0, 0)
	eq(areas.chips(a, FISH, 3), { { cargo = FISH, pct = 75, needed = 4, covered = 3, tone = "Inferior" } })
	eq(areas.chips(a, FOOD, 3)[1].pct, 100)
end)

test("chips: selected cargo not needed in the area -> none", function()
	eq(areas.chips(area({ [FISH] = { 4, 3 } }, 0, 0), TOOLS, 3), {})
	eq(areas.chips(nil, FISH, 3), {})
end)

test("chips: All needed -> worst 3 below 100 %, lowest first, ties by more buildings then id", function()
	local a = area({
		[FISH] = { 10, 5 },   -- 50
		[FOOD] = { 4, 2 },    -- 50, fewer buildings
		[TOOLS] = { 10, 1 },  -- 10
		[GOODS] = { 3, 3 },   -- 100: never in the worst list
		[2] = { 10, 8 },      -- 80: 4th, cut
	}, 0, 0)
	local c = areas.chips(a, nil, 3)
	eq(#c, 3)
	eq({ c[1].cargo, c[2].cargo, c[3].cargo }, { TOOLS, FISH, FOOD })
	eq(c[1].tone, "Poor")
end)

test("chips: All needed, equal % and buildings -> lower cargo id first", function()
	local c = areas.chips(area({ [FISH] = { 2, 1 }, [FOOD] = { 2, 1 } }, 0, 0), nil, 3)
	eq({ c[1].cargo, c[2].cargo }, { FOOD, FISH })
end)

test("chips: All needed, everything covered -> one 100 % chip (most-needed cargo)", function()
	local c = areas.chips(area({ [FISH] = { 2, 2 }, [FOOD] = { 5, 5 } }, 0, 0), nil, 3)
	eq(#c, 1)
	eq(c[1].cargo, FOOD)
	eq(c[1].pct, 100)
	eq(c[1].tone, "Normal")
end)

test("chips: worst = 1 keeps one", function()
	eq(#areas.chips(area({ [FISH] = { 2, 1 }, [FOOD] = { 2, 0 } }, 0, 0), nil, 1), 1)
end)

-- labels -----------------------------------------------------------------------------

test("labels: nearest areas to the camera first, capped", function()
	local list = {}
	for i = 1, 5 do
		local a = area({ [FISH] = { 2, 1 } }, i * 100, 0, i, COM)
		list[a.key] = a
	end
	local l = areas.labels(list, FISH, { 310, 0 }, 3, 3)
	eq(#l, 3)
	eq({ l[1].town, l[2].town, l[3].town }, { 3, 4, 2 })
	eq(l[1].landUse, COM)
	eq(l[1].chips[1].pct, 50)
end)

test("labels: areas without the selected cargo skipped; no position sorts last", function()
	local a1 = area({ [FISH] = { 2, 1 } }, nil, nil, 1, RES)
	local a2 = area({ [FOOD] = { 2, 1 } }, 0, 0, 2, RES)
	local a3 = area({ [FISH] = { 2, 2 } }, 500, 0, 3, RES)
	local l = areas.labels({ [a1.key] = a1, [a2.key] = a2, [a3.key] = a3 }, FISH, { 0, 0 }, 30, 3)
	eq(#l, 2)
	eq({ l[1].town, l[2].town }, { 3, 1 })
	eq(l[2].dist, math.huge)
end)

test("labels: equal distance -> key order (deterministic)", function()
	local a = area({ [FISH] = { 1, 0 } }, 0, 0, 7, IND)
	local b = area({ [FISH] = { 1, 0 } }, 0, 0, 7, RES)
	local l = areas.labels({ [a.key] = a, [b.key] = b }, nil, { 0, 0 }, 30, 3)
	eq({ l[1].landUse, l[2].landUse }, { RES, IND })
end)

test("labels: defaults MAX_LABELS 30, WORST 3", function()
	eq(areas.MAX_LABELS, 30)
	eq(areas.WORST, 3)
	local list = {}
	for i = 1, 40 do
		local x = area({ [FISH] = { 1, 0 } }, i, 0, i, COM)
		list[x.key] = x
	end
	eq(#areas.labels(list, nil, { 0, 0 }, nil, nil), 30)
end)

-- overlay.makeLabelStore -------------------------------------------------------------

test("makeLabelStore: rows per town, land use ascending, '73%' text and icon", function()
	set_global("api", {})
	local overlay = ug_require "square_supply_gaps::/supply_gaps/sg_overlay.tl"
	local list = {
		{ key = 1, town = 9, landUse = IND, dist = 0, chips = { { cargo = TOOLS, pct = 10, needed = 10, covered = 1, tone = "Poor" } } },
		{ key = 2, town = 9, landUse = RES, dist = 1, chips = { { cargo = FOOD, pct = 73, needed = 100, covered = 73, tone = "Inferior" } } },
		{ key = 3, town = 8, landUse = COM, dist = 2, chips = { { cargo = FISH, pct = 100, needed = 1, covered = 1, tone = "Normal" } } },
	}
	local st = overlay.makeLabelStore(list, 12, function(c) return "icon" .. c end)
	eq(st.shown, 3)
	eq(st.areas, 12)
	eq(#st.byTown[9], 2)
	eq(st.byTown[9][1].landUse, RES)
	eq(st.byTown[9][1].chips[1], { icon = "icon4", text = "73%", tone = "Inferior", cargo = FOOD })
	eq(st.byTown[9][2].landUse, IND)
	eq(st.byTown[8][1].chips[1].text, "100%")
end)

test("candidates + nearest (perf review split) = labels; candidates carry the centroid, no distance", function()
	local list = {}
	for i = 1, 40 do
		list[i] = { key = i, town = i, landUse = COM, x = (i * 37) % 100, y = (i * 11) % 50, positioned = 1,
			cargos = { [FISH] = { needed = 4, covered = i % 5 }, [FOOD] = { needed = 2, covered = 1 } } }
	end
	list[41] = { key = 41, town = 41, landUse = RES, positioned = 0, cargos = { [FISH] = { needed = 1, covered = 0 } } }
	for _, sel in ipairs({ false, FISH, TOOLS }) do
		local s = sel or nil
		local c = areas.candidates(list, s, 3)
		for _, it in ipairs(c) do eq(it.dist, nil) end
		eq(areas.nearest(c, { 50, 20 }, 30), areas.labels(list, s, { 50, 20 }, 30, 3))
	end
end)
