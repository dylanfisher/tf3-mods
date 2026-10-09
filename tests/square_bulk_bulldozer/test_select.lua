-- bb_select: classification (hard rules + filters), selection set with cap, tooltip lines
-- (PLAN Phase 2).

local sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl"

local ME, OTHER, HQ = 1, 2, 500
local CTX = { player = ME, hq = HQ }

local function allOn()
	return { roads = true, tracks = true, stations = true, assets = true,
		townBuildings = true, underground = true }
end
local function allOff()
	return { roads = false, tracks = false, stations = false, assets = false,
		townBuildings = false, underground = false }
end
local function with(base, field, v)
	local f = {}
	for k, x in pairs(base) do f[k] = x end
	f[field] = v
	return f
end

local nextId = 1000
local function edge(t)
	nextId = nextId + 1
	local d = { entity = nextId, isEdge = true, gone = false, owner = ME, parentConstruction = -1,
		isStreet = true, isTunnel = false, industryRoad = false, objects = {} }
	for k, v in pairs(t or {}) do d[k] = v end
	return d
end
local function con(t)
	nextId = nextId + 1
	local d = { entity = nextId, isEdge = false, gone = false, owner = ME, parentConstruction = -1,
		x = 0, y = 0, stations = 0, depots = 0, industries = 0, townBuildings = 0, frozen = 0 }
	for k, v in pairs(t or {}) do d[k] = v end
	return d
end

-- One descriptor per kind, with the filter that governs it.
local KIND_CASES = {
	{ kind = "road", filter = "roads", make = function() return edge() end },
	-- Unowned streets (town roads, roads freed from a street construction) are plain roads too.
	{ kind = "road", filter = "roads", make = function() return edge({ owner = -1 }) end },
	{ kind = "track", filter = "tracks", make = function() return edge({ isStreet = false }) end },
	{ kind = "station", filter = "stations", make = function() return con({ stations = 1, frozen = 4 }) end },
	{ kind = "station", filter = "stations", make = function() return con({ depots = 1, frozen = 2 }) end },
	{ kind = "asset", filter = "assets", make = function() return con() end },
	{ kind = "town_building", filter = "townBuildings", make = function() return con({ owner = -1, townBuildings = 1 }) end },
}

test("defaults match PLAN Filters", function()
	local f = sel.defaultFilters()
	eq(f, { roads = true, tracks = true, stations = false, assets = true,
		townBuildings = false, underground = false })
	eq(#sel.FILTER_KEYS, 6)
	for _, k in ipairs(sel.FILTER_KEYS) do ok(f[k] ~= nil, k) end
end)

test("checkboxOn: 2 = on, 1 = off, else default", function()
	eq(sel.checkboxOn(2, false), true)
	eq(sel.checkboxOn(1, true), false)
	eq(sel.checkboxOn(nil, true), true)
	eq(sel.checkboxOn(7, false), false)
end)

test("every filter × kind: kept only when its own filter is on", function()
	for _, case in ipairs(KIND_CASES) do
		local d = case.make()
		-- Only this filter on → kept.
		local c = sel.classify(d, with(allOff(), case.filter, true), CTX)
		eq(c.kind, case.kind, case.kind .. " kind")
		eq(c.reason, nil, case.kind .. " kept with " .. case.filter)
		eq(c.entity, d.entity)
		-- Every filter but this one on → filtered.
		c = sel.classify(d, with(allOn(), case.filter, false), CTX)
		eq(c.reason, "filtered", case.kind .. " filtered without " .. case.filter)
		-- Every other single filter alone does not keep it.
		for _, other in ipairs(sel.FILTER_KEYS) do
			if other ~= case.filter and other ~= "underground" then
				c = sel.classify(d, with(allOff(), other, true), CTX)
				eq(c.reason, "filtered", case.kind .. " not kept by " .. other)
			end
		end
	end
end)

test("Roads (default on) takes every street regardless of PLAYER_OWNED (user decision 2026-10-07)", function()
	local f = sel.defaultFilters()
	eq(f.roads, true)
	-- ours, unowned (town road), unowned freed from a street construction (no owner, no parent)
	for _, d in ipairs({ edge(), edge({ owner = -1 }), edge({ owner = -1, parentConstruction = -1 }) }) do
		local c = sel.classify(d, f, CTX)
		eq(c.kind, "road"); eq(c.reason, nil)
	end
	-- hard rules still win: another player's street, a construction's street, an industry road
	eq(sel.classify(edge({ owner = OTHER }), f, CTX).reason, "foreign")
	eq(sel.classify(edge({ owner = -1, parentConstruction = 77 }), f, CTX).reason, "part")
	eq(sel.classify(edge({ parentConstruction = 77 }), f, CTX).reason, "part")
	eq(sel.classify(edge({ owner = -1, industryRoad = true }), f, CTX).reason, "industry")
	-- with an unknown player every owned street counts as foreign (fail safe)
	eq(sel.classify(edge({ owner = ME }), f, { player = -1, hq = -1 }).reason, "foreign")
	-- Roads off: no street at all
	eq(sel.classify(edge({ owner = -1 }), with(f, "roads", false), CTX).reason, "filtered")
	eq(sel.classify(edge(), with(f, "roads", false), CTX).reason, "filtered")
end)

test("toolbar sync: paramValue / paramFilters only take certain values", function()
	eq(sel.paramValue(2), true); eq(sel.paramValue(1), false)
	eq(sel.paramValue(0), nil); eq(sel.paramValue(nil), nil); eq(sel.paramValue(3), nil)
	eq(sel.paramFilters({ a = 2, b = 1, c = 0 }, { roads = "a", tracks = "b", assets = "c", stations = "d" }),
		{ roads = true, tracks = false })
	eq(sel.paramFilters(nil, { roads = "a" }), {})
end)

test("toolbar sync: resolveFilters — shown wins, else defaults, conflicts and unknowns are off", function()
	local d = sel.defaultFilters()
	-- Nothing known: the menu shows its defaults.
	local f, unknown = sel.resolveFilters({}, {}, d)
	eq(f, d); eq(unknown, {})
	-- Shown values win, false included (never re-ticked after a remount).
	f = sel.resolveFilters({ roads = false, townBuildings = true }, {}, d)
	eq(f.roads, false); eq(f.townBuildings, true); eq(f.tracks, true)
	-- A toggle seen in some category but nothing shown: the default is no longer certain → off.
	f, unknown = sel.resolveFilters({}, { ["3"] = { roads = false } }, d)
	eq(f.roads, false); eq(unknown, { "roads" })
	f, unknown = sel.resolveFilters({}, { ["3"] = { stations = true } }, d)
	eq(f.stations, false); eq(unknown, { "stations" })
	-- Toggled back to the default in every category: certain again.
	f, unknown = sel.resolveFilters({}, { ["3"] = { roads = true }, ["4"] = { roads = true } }, d)
	eq(f.roads, true); eq(unknown, {})
	-- Never on unless certain: with every toggle conflicting, everything unknown is off.
	f = sel.resolveFilters(nil, { a = { roads = false, tracks = false, assets = false } }, d)
	eq(f.roads, false); eq(f.tracks, false); eq(f.assets, false)
end)

test("bridges count as normal roads/tracks (no special field)", function()
	local c = sel.classify(edge({ isTunnel = false }), sel.defaultFilters(), CTX)
	eq(c.reason, nil)
end)

test("tunnel edges need Underground on top of their kind filter", function()
	for _, mk in ipairs({
		function() return edge({ isTunnel = true }) end,
		function() return edge({ isTunnel = true, owner = -1 }) end,
		function() return edge({ isTunnel = true, isStreet = false }) end,
	}) do
		local d = mk()
		eq(sel.classify(d, with(allOn(), "underground", false), CTX).reason, "underground")
		eq(sel.classify(d, allOn(), CTX).reason, nil)
		-- Underground alone doesn't select a kind that's filtered out.
		eq(sel.classify(d, with(allOff(), "underground", true), CTX).reason, "filtered")
	end
end)

test("hard rule: industries are never kept, whatever the filters", function()
	local c = sel.classify(con({ industries = 1, frozen = 10 }), allOn(), CTX)
	eq(c.kind, "industry"); eq(c.reason, "industry")
	-- An unowned industry construction too.
	c = sel.classify(con({ owner = -1, industries = 2, townBuildings = 1 }), allOn(), CTX)
	eq(c.reason, "industry")
	-- Industry roads (town-style, not frozen) are never kept either.
	c = sel.classify(edge({ owner = -1, industryRoad = true }), allOn(), CTX)
	eq(c.kind, "road"); eq(c.reason, "industry")
end)

test("hard rule: our HQ is never kept", function()
	local d = con({ entity = HQ })
	local c = sel.classify(d, allOn(), CTX)
	eq(c.reason, "hq")
	-- Without a known HQ the same construction is a plain asset.
	eq(sel.classify(d, allOn(), { player = ME, hq = -1 }).reason, nil)
end)

test("hard rule: anything owned by another player", function()
	eq(sel.classify(edge({ owner = OTHER }), allOn(), CTX).reason, "foreign")
	eq(sel.classify(edge({ owner = OTHER, isStreet = false }), allOn(), CTX).reason, "foreign")
	eq(sel.classify(con({ owner = OTHER, stations = 1 }), allOn(), CTX).reason, "foreign")
	eq(sel.classify(con({ owner = OTHER }), allOn(), CTX).reason, "foreign")
	-- With an unknown player (-1) every owned thing is foreign: fail safe.
	eq(sel.classify(edge(), allOn(), { player = -1, hq = -1 }).reason, "foreign")
end)

test("hard rule: construction-owned edges and subconstructions go with their construction", function()
	eq(sel.classify(edge({ parentConstruction = 77 }), allOn(), CTX).reason, "part")
	eq(sel.classify(edge({ parentConstruction = 77, owner = -1 }), allOn(), CTX).reason, "part")
	eq(sel.classify(edge({ parentConstruction = 77, isStreet = false }), allOn(), CTX).reason, "part")
	eq(sel.classify(con({ parentConstruction = 77 }), allOn(), CTX).reason, "part")
	eq(sel.classify(edge({ parentConstruction = 0 }), allOn(), CTX).reason, "part", "entity 0 is valid")
end)

test("hard rule: unowned non-town constructions and unowned tracks", function()
	-- Landmark / mission prop: unowned, no town buildings.
	local c = sel.classify(con({ owner = -1 }), allOn(), CTX)
	eq(c.kind, "other"); eq(c.reason, "not_player")
	-- Unowned construction with a station is not a town building.
	eq(sel.classify(con({ owner = -1, townBuildings = 1, stations = 1 }), allOn(), CTX).reason, "not_player")
	-- Unowned town building with frozen network is not a plain house (overpass rule).
	eq(sel.classify(con({ owner = -1, townBuildings = 1, frozen = 2 }), allOn(), CTX).reason, "not_player")
	eq(sel.classify(edge({ owner = -1, isStreet = false }), allOn(), CTX).reason, "not_player")
end)

test("hard rule: gone entities", function()
	eq(sel.classify(edge({ gone = true }), allOn(), CTX).reason, "gone")
	eq(sel.classify(con({ gone = true }), allOn(), CTX).reason, "gone")
end)

test("hard rules win over filters in a fixed order", function()
	-- Foreign before part, part before industry.
	eq(sel.classify(edge({ owner = OTHER, parentConstruction = 5 }), allOn(), CTX).reason, "foreign")
	eq(sel.classify(edge({ owner = -1, parentConstruction = 5, industryRoad = true }), allOn(), CTX).reason, "part")
	eq(sel.classify(con({ entity = HQ, industries = 1 }), allOn(), CTX).reason, "industry")
end)

test("edge objects ride along and are counted", function()
	local c = sel.classify(edge({ isStreet = false, objects = { 9, 10, 11 } }), allOn(), CTX)
	eq(c.objects, 3)
	eq(sel.classify(con(), allOn(), CTX).objects, 0)
end)

test("stroke: keeps are unique, skips counted once per entity", function()
	local s = sel.newStroke()
	local road = sel.classify(edge(), allOn(), CTX)
	local track = sel.classify(edge({ isStreet = false, objects = { 1, 2 } }), allOn(), CTX)
	local ind = sel.classify(con({ industries = 1 }), allOn(), CTX)
	eq(sel.add(s, road), true)
	eq(sel.add(s, road), false, "same entity again")
	eq(sel.add(s, track), true)
	eq(sel.add(s, ind), false)
	eq(sel.add(s, ind), false)
	eq(sel.count(s), 2)
	eq(s.kindCounts, { road = 1, track = 1 })
	eq(s.reasonCounts, { industry = 1 })
	eq(s.objects, 2)
	eq(sel.entities(s), { road.entity, track.entity })
	eq(sel.add(s, nil), false)
end)

test("stroke: a later keep replaces an earlier skip of the same entity", function()
	local s = sel.newStroke()
	local d = con({ owner = -1, townBuildings = 1 })   -- "Town buildings" is off by default
	sel.add(s, sel.classify(d, sel.defaultFilters(), CTX))
	eq(s.reasonCounts.filtered, 1)
	sel.add(s, sel.classify(d, allOn(), CTX))
	eq(s.reasonCounts.filtered, 0)
	eq(sel.count(s), 1)
	eq(s.skipped[d.entity], nil)
end)

test("stroke cap: 400 keeps, then capped; skips still counted", function()
	eq(sel.STROKE_CAP, 400)
	local s = sel.newStroke()
	for _ = 1, 405 do sel.add(s, sel.classify(edge(), allOn(), CTX)) end
	eq(sel.count(s), 400)
	eq(s.capped, true)
	eq(#sel.entities(s), 400)
	sel.add(s, sel.classify(con({ industries = 1 }), allOn(), CTX))
	eq(s.reasonCounts.industry, 1)
	local lines = sel.describe(s)
	eq(lines[#lines], "Limit of 400 reached")
end)

test("a later stroke adds to the same selection (select, then confirm)", function()
	local s = sel.newStroke()
	sel.add(s, sel.classify(edge({ entity = 501 }), allOn(), CTX))
	sel.add(s, sel.classify(edge({ entity = 502 }), allOn(), CTX))
	-- second stroke over the same spot plus one new edge
	sel.add(s, sel.classify(edge({ entity = 502 }), allOn(), CTX))
	sel.add(s, sel.classify(edge({ entity = 503 }), allOn(), CTX))
	eq(sel.entities(s), { 501, 502, 503 })
	eq(sel.needsConfirmation, nil, "no threshold rule: every selection waits for the button")
end)

test("remove: a Shift stroke takes kept entities back out", function()
	local s = sel.newStroke()
	sel.add(s, sel.classify(edge({ entity = 601 }), allOn(), CTX))
	sel.add(s, sel.classify(edge({ entity = 602, isStreet = false, objects = { 1, 2 } }), allOn(), CTX))
	sel.add(s, sel.classify(con({ entity = 603 }), allOn(), CTX))
	sel.add(s, sel.classify(con({ industries = 1, entity = 604 }), allOn(), CTX))   -- skipped
	eq(sel.remove(s, { 602, 604, 999, 602 }), 1, "only kept entities count, each once")
	eq(sel.entities(s), { 601, 603 })
	eq(s.keep[602], nil)
	eq(s.kindCounts.track, 0)
	eq(s.objects, 0)
	eq(s.skipped[604], "industry", "skip records stay")
	eq(sel.remove(s, {}), 0)
	eq(sel.remove(s, nil), 0)
	-- removed entities can be painted in again
	eq(sel.add(s, sel.classify(edge({ entity = 602 }), allOn(), CTX)), true)
	eq(sel.entities(s), { 601, 603, 602 })
end)

test("remove: dropping below the cap lifts the cap note", function()
	local s = sel.newStroke()
	for i = 1, sel.STROKE_CAP + 1 do sel.add(s, sel.classify(edge({ entity = 10000 + i }), allOn(), CTX)) end
	eq(s.capped, true)
	eq(sel.remove(s, { 10001 }), 1)
	eq(s.capped, false)
	eq(sel.count(s), sel.STROKE_CAP - 1)
end)

test("describe: counts per kind and per skip reason", function()
	local s = sel.newStroke()
	eq(sel.describe(s), { "Nothing selected" })
	sel.add(s, sel.classify(edge(), allOn(), CTX))
	sel.add(s, sel.classify(edge(), allOn(), CTX))
	sel.add(s, sel.classify(edge({ isStreet = false, objects = { 1 } }), allOn(), CTX))
	sel.add(s, sel.classify(con({ owner = -1, townBuildings = 1 }), sel.defaultFilters(), CTX))
	sel.add(s, sel.classify(con({ industries = 1 }), allOn(), CTX))
	sel.add(s, sel.classify(con({ entity = HQ }), allOn(), CTX))
	eq(sel.describe(s), {
		"Selected: 2 roads, 1 tracks (+1 signals/stops)",
		"Skipped: 1 filtered, 1 industry, 1 HQ",
	})
end)

test("constants: origin-only construction hits", function()
	eq(sel.CONSTRUCTION_ORIGIN_ONLY, true)
end)
