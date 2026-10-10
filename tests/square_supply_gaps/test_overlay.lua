-- sg_overlay: the tick pipeline with gather / catchment stubbed (gather and the model have their own
-- tests). Checks: off by default (the saved flag switches it on, test_saved.lua), off = no work, on = markers for gaps, off clears, no log noise, the
-- paused fallback, errors stay inside the tick, snapshot rows, starved, area labels, towns in view.

local overlay = ug_require "square_supply_gaps::/supply_gaps/sg_overlay.tl"
local gather = ug_require "square_supply_gaps::/supply_gaps/sg_gather.tl"
local cache = ug_require "square_supply_gaps::/supply_gaps/sg_cache.tl"
local markers = ug_require "square_supply_gaps::/supply_gaps/sg_markers.tl"

local PASS, FISH, FOOD = 0, 7, 4
local scope = ug_require "square_supply_gaps::/supply_gaps/sg_scope.tl"
local set, removed, paused, clockT, nowT, setTypes, zero, reads, bmap, bcount, camView

local function fakeApi()
	return {
		gui = {
			mission = {
				setMarkerAtEntity = function(key, e, typ) set[#set + 1] = key; setTypes[key] = typ end,
				removeMarker = function(key) removed[#removed + 1] = key end,
			},
			camera = { getCameraData = function() return { x = 0, y = 0 } end },
		},
		res = { cargoTypeRep = { get = function(c) return { name = c == FISH and "Fish" or ("C" .. c) } end } },
		type = {
			ComponentType = { GAME_SPEED = "GAME_SPEED" },
		},
		engine = {
			util = { getWorld = function() return 1 end },
			getComponent = function(e, ct)
				if ct == "GAME_SPEED" then return { speedup = paused and 0 or 1 } end
			end,
		},
	}
end

-- World: buildings 1 (fish) and 2 (fish, food) in town 100; line 50 carries fish and stops at group 5
-- (station 55), whose catchment holds building 1 only.
local function stubWorld()
	gather.passengerCargo = function() return PASS end
	gather.lines = function()
		return { { entity = 50, carries = { PASS, FISH }, stops = { { stationGroup = 5, unload = true } } } }
	end
	gather.unloadGroups = function() return { 5, 6 } end
	gather.groupStations = function(groups)
		local out = {}
		for _, g in ipairs(groups) do out[g] = { g * 11 } end
		return out
	end
	gather.buildingMap = function() return bcount, bmap end
	local BLD = {
		[1] = { entity = 1, town = 100, landUse = 2, needs = { FISH }, stockList = 1001, pos = { 1, 0, 0 } },
		[2] = { entity = 2, town = 100, landUse = 2, needs = { FOOD, FISH }, stockList = 1002, pos = { 2, 0, 0 } },
		[3] = { entity = 3, town = 100, landUse = 1, needs = {}, stockList = 1003, pos = { 3, 0, 0 } },
		-- Phase 2d: town 200 far east (x = 1000), one unreached fish building
		[5] = { entity = 5, town = 200, landUse = 2, needs = { FISH }, stockList = 1005, pos = { 1000, 0, 0 } },
	}
	gather.buildingBox = function(b)
		local src = BLD[b]
		if src == nil then return nil end
		return { src.pos[1] - 5, src.pos[2] - 5, src.pos[1] + 5, src.pos[2] + 5 }
	end
	gather.townName = function(t) return t == 100 and "Ashby" or (t == 200 and "Brook" or "") end
	-- zero[b] = zeroReads of b (the stock streak gather would compute)
	gather.readBuilding = function(b)
		reads[#reads + 1] = b
		local src = BLD[b]
		if src == nil then return nil, true end
		local r = {}
		for k, v in pairs(src) do r[k] = v end
		r.zeroReads = zero[b] or {}
		return r, true
	end
	cache.engineFetch = function(station)
		if station == 55 then return { 1 } end
		if station == 66 then return { 2 } end
		return {}
	end
end

local function logged(text)
	for _, e in ipairs(log_entries()) do
		if e.msg:find(text, 1, true) then return true end
	end
	return false
end

before_each(function()
	set, removed, paused, clockT, nowT = {}, {}, false, 0, 1000
	setTypes, zero, reads = {}, {}, {}
	bmap, bcount = { [100] = { 1, 2, 3 } }, 3
	set_global("api", fakeApi())
	stubWorld()
	overlay.now = function() return nowT end
	overlay.clock = function() return clockT end
	overlay.shutdown()
	overlay.session.selection = nil
	overlay.session.unlined = false
	overlay.session.starved = true
	-- the Phase 1-2c tests below run on the whole map; Phase 2d tests switch scoping on
	overlay.session.scoped = false
	overlay.PRIORITY_PER_TICK = 800
	camView = { cx = 0, cy = 0, distance = 50, poly = scope.square(0, 0, 50), hits = 4, fallback = false }
	overlay.readCamera = function() return camView end
	overlay.ticks = 0
	clear_logs()
end)

test("off by default (also after shutdown, i.e. the next game): no work until switched on", function()
	eq(overlay.DEFAULT_ON, false)
	eq(overlay.session.on, false)
	overlay.timerTick()
	overlay.tick("timer")
	eq(set, {})
	eq(overlay.ticks, 0)
	overlay.setOn(true)
	overlay.tick("timer")
	eq(set, { "sqsg:2" })
end)

test("off: ticks do nothing", function()
	overlay.setOn(false)
	overlay.ticks = 0
	set = {}
	overlay.timerTick()
	overlay.tick("timer")
	eq(#set, 0)
	eq(overlay.ticks, 0)
end)

test("on: the unreached building gets a marker; reached one does not", function()
	overlay.setOn(true)
	overlay.timerTick()
	eq(set, { "sqsg:2" })
	eq(overlay.gapList, { 2 })
	eq(setTypes["sqsg:2"], "arrow")
	eq(#log_entries(), 0, "no log lines in a normal tick")
end)

test("single cargo selection: building 2 is a gap for food and for fish", function()
	overlay.setOn(true)
	overlay.setSelection(FOOD)
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
	overlay.setSelection(FISH)
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
end)

test("count stops without a line: unlined group 6 reaches building 2", function()
	overlay.setOn(true)
	overlay.setUnlined(true)
	overlay.tick("timer")
	eq(overlay.gapList, {})
end)

test("off clears our markers", function()
	overlay.setOn(true)
	overlay.tick("timer")
	overlay.setOn(false)
	eq(removed, { "sqsg:2" })
	eq(overlay.gapList, nil)
end)

test("shutdown forgets markers without engine calls; the session is back to the default", function()
	overlay.setOn(true)
	overlay.tick("timer")
	overlay.shutdown()
	eq(removed, {})
	eq(overlay.session.on, false)
	eq(overlay.view, nil)
	eq(next(markers.shown), nil)
end)

test("a raising gather call stays inside the tick (ERR logged)", function()
	gather.lines = function() error("kaputt") end
	overlay.setOn(true)
	overlay.tick("timer")
	ok(logged("[SQSG] ERR tick"))
end)

test("paused: the timer keeps ticking -> no onStep ticks", function()
	overlay.setOn(true)
	paused = true
	overlay.stepCheck()
	overlay.timerTick()
	for i = 1, 4 do
		nowT = nowT + 1
		overlay.stepCheck()
	end
	eq(overlay.ticks, 1)
end)

test("paused without timer ticks: onStep ticks after PAUSE_WAIT s, once per second", function()
	overlay.setOn(true)
	paused = true
	overlay.stepCheck()
	for i = 1, 4 do
		nowT = nowT + 1
		overlay.stepCheck()
	end
	ok(overlay.ticks >= 1, "fallback ticked")
	eq(overlay.gapList, { 2 })
end)

test("snapshot: rows sorted by unreached, counts", function()
	overlay.setOn(true)
	overlay.tick("timer")
	local s = overlay.snapshot()
	eq(s.on, true)
	eq(s.gaps, 1)
	eq(s.buildings, 2)
	eq(s.markers, 1)
	eq(s.capped, false)
	eq(s.rows[1].cargo, FOOD)
	eq(s.rows[1].needed - s.rows[1].reached, 1)
	eq(s.rows[2].name, "Fish")
	eq(s.rows[2].reached, 1)
end)

-- starved (Phase 2b) ------------------------------------------------------------------------

test("starved: a reached building with an empty stock gets an exclamation", function()
	zero[1] = { [FISH] = 3 }
	overlay.setOn(true)
	overlay.tick("timer")
	eq(overlay.gapList, { 1, 2 })
	eq(setTypes["sqsg:1"], "exclamation")
	eq(setTypes["sqsg:2"], "arrow")
	local snap = overlay.snapshot()
	eq(snap.unreached, 1)
	eq(snap.starved, 1)
	eq(snap.includeStarved, true)
end)

test("starved: hidden by the checkbox (marker removed), counted in rows", function()
	zero[1] = { [FISH] = 3 }
	overlay.setOn(true)
	overlay.tick("timer")
	overlay.setStarved(false)
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
	eq(removed, { "sqsg:1" })
	local snap = overlay.snapshot()
	eq(snap.starved, 0)
	eq(snap.rows[2].name, "Fish")
	eq(snap.rows[2].starved, 1)
end)

test("starved: below the streak no marker; kind change re-sets the marker type", function()
	zero[1] = { [FISH] = 2 }
	overlay.setOn(true)
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
	-- every building re-read within BUILDING_EVERY ticks; the streak reaches 3
	zero[1] = { [FISH] = 3 }
	for _ = 1, cache.BUILDING_EVERY do overlay.tick("timer") end
	eq(overlay.gapList, { 1, 2 })
	eq(setTypes["sqsg:1"], "exclamation")
	-- building 2 gets food + fish via "Count stops without a line" but its stocks are empty: arrow -> exclamation
	zero[2] = { [FISH] = 3, [FOOD] = 3 }
	overlay.setUnlined(true)
	for _ = 1, cache.BUILDING_EVERY do overlay.tick("timer") end
	eq(setTypes["sqsg:2"], "exclamation")
	local n2 = 0
	for _, k in ipairs(set) do if k == "sqsg:2" then n2 = n2 + 1 end end
	eq(n2, 2) -- set as arrow, removed, set again as exclamation
	eq(removed, { "sqsg:2" })
end)

test("buildings: all read on the first tick, then a round-robin slice; new ids at once; demolished dropped", function()
	overlay.setOn(true)
	overlay.tick("timer")
	eq(#reads, 3)
	reads = {}
	overlay.tick("timer")
	eq(#reads, 1) -- ceil(3 / BUILDING_EVERY)
	bmap, bcount = { [100] = { 2, 3, 4 } }, 3
	reads = {}
	overlay.tick("timer")
	local got4 = false
	for _, b in ipairs(reads) do if b == 4 then got4 = true end end
	ok(got4, "new id 4 read at once")
	eq(overlay.buildings[1], nil)
	eq(overlay.seen[1], nil)
	eq(overlay.gapList, { 2 })
	eq(removed, {})
end)

-- Phase 2c area labels ---------------------------------------------------------------

local areasMod = ug_require "square_supply_gaps::/supply_gaps/sg_areas.tl"

test("labels: on by default; the tick publishes one row per district with the worst cargos", function()
	eq(overlay.session.labels, true)
	overlay.setOn(true)
	overlay.tick("timer")
	local st = overlay.labelStore
	ok(st ~= nil)
	eq(st.shown, 1)
	eq(st.areas, 1)
	local rows = st.byTown[100]
	eq(#rows, 1)
	eq(rows[1].landUse, 2)
	-- building 1 (fish) reached, building 2 (food, fish) not: food 0 %, fish 50 %
	eq(#rows[1].chips, 2)
	eq(rows[1].chips[1].cargo, FOOD)
	eq(rows[1].chips[1].text, "0%")
	eq(rows[1].chips[1].tone, "Poor")
	eq(rows[1].chips[2].text, "50%")
	eq(overlay.snapshot().labelsShown, 1)
end)

test("labels: one cargo selected -> only that cargo's chip", function()
	overlay.setSelection(FISH)
	overlay.setOn(true)
	overlay.tick("timer")
	local chips = overlay.labelStore.byTown[100][1].chips
	eq(#chips, 1)
	eq(chips[1].cargo, FISH)
	eq(chips[1].text, "50%")
end)

test("labels: unticking clears the store; overlay off clears it too", function()
	overlay.setOn(true)
	overlay.tick("timer")
	ok(overlay.labelStore ~= nil)
	overlay.setLabels(false)
	eq(overlay.labelStore, nil)
	overlay.tick("timer")
	eq(overlay.labelStore, nil)
	overlay.setLabels(true)
	overlay.tick("timer")
	ok(overlay.labelStore ~= nil)
	overlay.setOn(false)
	eq(overlay.labelStore, nil)
end)

test("labels: a failing planner drops only the labels; markers still applied", function()
	-- the overlay plans through areas.candidates + areas.nearest (= areas.labels, split for the perf review)
	local origL, origC, origN = areasMod.labels, areasMod.candidates, areasMod.nearest
	areasMod.labels = function() error("boom") end
	areasMod.candidates = function() error("boom") end
	areasMod.nearest = function() error("boom") end
	overlay.setOn(true)
	overlay.tick("timer")
	areasMod.labels, areasMod.candidates, areasMod.nearest = origL, origC, origN
	eq(overlay.labelStore, nil)
	eq(set, { "sqsg:2" })
	ok(logged("[SQSG] ERR labels"))
end)

-- Phase 2d: only towns in view ---------------------------------------------------------

local function lookAt(x)
	camView = { cx = x, cy = 0, distance = 50, poly = scope.square(x, 0, 50), hits = 4, fallback = false }
end

local function has(list, v)
	for _, x in ipairs(list) do if x == v then return true end end
	return false
end

test("scoped: only the town in view is read and counted, and named in the header", function()
	bmap, bcount = { [100] = { 1, 2, 3 }, [200] = { 5 } }, 4
	overlay.session.scoped = true
	overlay.setOn(true)
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
	ok(not has(reads, 5), "town 200 not read")
	local snap = overlay.snapshot()
	eq(snap.scoped, true)
	eq(snap.viewTowns, 1)
	eq(snap.viewText, "Ashby")
	eq(snap.buildings, 2)
	eq(snap.pending, 0)
	-- untick: the whole map, town 200 read at once and counted
	overlay.setScoped(false)
	reads = {}
	overlay.tick("timer")
	ok(has(reads, 5), "town 200 read promptly")
	eq(overlay.gapList, { 2, 5 })
	eq(overlay.snapshot().viewTowns, 2)
	eq(overlay.snapshot().viewText, "")
end)

test("scoped: pan to another town -> read at once; the old town is held, then leaves", function()
	bmap, bcount = { [100] = { 1, 2, 3 }, [200] = { 5 } }, 4
	overlay.session.scoped = true
	overlay.setOn(true)
	overlay.tick("timer")
	lookAt(1000)
	reads = {}
	overlay.tick("timer")
	ok(has(reads, 5), "new town read in the tick it came into view")
	eq(overlay.gapList, { 2, 5 }) -- Ashby held
	eq(overlay.snapshot().viewText, "Brook, Ashby")
	for _ = 1, scope.HOLD_TICKS do overlay.tick("timer") end
	eq(overlay.gapList, { 5 })
	eq(removed, { "sqsg:2" })
	eq(overlay.snapshot().viewText, "Brook")
	-- back to Ashby: its known buildings are due and re-read in the same tick
	lookAt(0)
	reads = {}
	overlay.tick("timer")
	ok(has(reads, 1) and has(reads, 2) and has(reads, 3), "known buildings re-read at once")
	ok(has(overlay.gapList, 2))
end)

test("scoped: a town bigger than PRIORITY_PER_TICK is pending until every building was read once", function()
	overlay.session.scoped = true
	overlay.PRIORITY_PER_TICK = 1
	overlay.setOn(true)
	overlay.tick("timer")
	eq(overlay.gapList, {})
	ok(overlay.snapshot().pending > 0, "pending shown")
	for _ = 1, 3 do overlay.tick("timer") end
	eq(overlay.snapshot().pending, 0)
	eq(overlay.gapList, { 2 })
	-- a new building later doesn't hide the town again (ready is sticky)
	bmap, bcount = { [100] = { 1, 2, 3, 6 } }, 4
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
end)

test("scoped: no town in view -> nothing counted or marked; selected cargo keeps its row", function()
	overlay.session.scoped = true
	lookAt(-5000)
	overlay.setSelection(FISH)
	overlay.setOn(true)
	overlay.tick("timer")
	eq(overlay.gapList, {})
	local snap = overlay.snapshot()
	eq(snap.viewTowns, 0)
	eq(snap.buildings, 0)
	eq(#snap.rows, 1)
	eq(snap.rows[1].cargo, FISH)
	eq(snap.rows[1].needed, 0)
	eq(overlay.labelStore.shown, 0)
end)

test("scoped: area labels only for districts of towns in view", function()
	bmap, bcount = { [100] = { 1, 2, 3 }, [200] = { 5 } }, 4
	overlay.session.scoped = true
	overlay.setOn(true)
	overlay.tick("timer")
	ok(overlay.labelStore.byTown[100] ~= nil)
	eq(overlay.labelStore.byTown[200], nil)
end)

-- perf review (2026-10-09): dirty flags and budgets ----------------------------------------

test("perf: nothing changed -> model, marker plan and labels skipped; same results", function()
	overlay.setOn(true)
	overlay.tick("timer")
	local view, store = overlay.view, overlay.labelStore
	local c0 = overlay.counters.computes
	set = {}
	for _ = 1, 5 do overlay.tick("timer") end
	eq(overlay.counters.computes, c0)
	eq(overlay.counters.skips, 5)
	ok(overlay.view == view and overlay.labelStore == store, "kept")
	eq(overlay.gapList, { 2 })
	eq(set, {})
end)

test("perf: a stock streak below the threshold doesn't recompute; reaching it does; selection does", function()
	overlay.setOn(true)
	overlay.tick("timer")
	local c0 = overlay.counters.computes
	zero[1] = { [FISH] = 1 }
	for _ = 1, cache.BUILDING_EVERY do overlay.tick("timer") end
	eq(overlay.counters.computes, c0)
	zero[1] = { [FISH] = 3 }
	for _ = 1, cache.BUILDING_EVERY do overlay.tick("timer") end
	eq(overlay.counters.computes, c0 + 1)
	eq(overlay.gapList, { 1, 2 })
	overlay.setSelection(FOOD)
	overlay.tick("timer")
	eq(overlay.counters.computes, c0 + 2)
	eq(overlay.gapList, { 2 })
	overlay.session.starved = false -- set directly (not through the setter): still noticed
	overlay.setSelection(nil)
	overlay.tick("timer")
	eq(overlay.gapList, { 2 })
end)

test("perf: a changed catchment or line recomputes", function()
	overlay.setOn(true)
	overlay.tick("timer")
	cache.engineFetch = function(station) if station == 55 then return { 1, 2 } end return {} end
	for _ = 1, 3 do overlay.tick("timer") end
	eq(overlay.view.cargos[FISH].reached, 2) -- building 2 now in range for fish (still a food gap)
	gather.lines = function()
		return { { entity = 50, carries = { PASS, FOOD }, stops = { { stationGroup = 5, unload = true } } } }
	end
	overlay.tick("timer")
	eq(overlay.gapList, { 1, 2 })
end)

test("perf: camera moves with fewer gaps than markers -> no new marker plan; off/on re-sends", function()
	overlay.setOn(true)
	overlay.tick("timer")
	local p0 = overlay.counters.plans
	for i = 1, 3 do
		camView = { cx = i * 10, cy = 0, distance = 50, poly = scope.square(0, 0, 50), hits = 4, fallback = false }
		overlay.tick("timer")
	end
	eq(overlay.counters.plans, p0)
	overlay.setOn(false)
	set = {}
	overlay.setOn(true)
	overlay.tick("timer")
	eq(set, { "sqsg:2" })
end)

test("perf: building reads stop at READ_BUDGET_MS (after READ_MIN); the rest are read next tick", function()
	bmap, bcount = { [100] = { 1, 2, 3 }, [200] = { 5 } }, 4
	overlay.READ_MIN = 1
	-- every clock call advances 4 ms: the 2nd read of a tick is over the 6 ms budget
	overlay.clock = function() clockT = clockT + 0.004 return clockT end
	overlay.setOn(true)
	overlay.tick("timer")
	ok(#reads < 4, "budget cut the reads: " .. #reads)
	ok(overlay.snapshot().pending > 0)
	for _ = 1, 5 do overlay.tick("timer") end
	eq(overlay.snapshot().pending, 0)
	eq(overlay.gapList, { 2, 5 })
	overlay.READ_MIN = 100
end)

test("perf: the box pass is spread over ticks (BOX_PER_TICK); towns come into view as their boxes arrive", function()
	bmap, bcount = { [100] = { 1, 2, 3 }, [200] = { 5 } }, 4
	overlay.session.scoped = true
	local boxReads = 0
	local orig = gather.buildingBox
	gather.buildingBox = function(b) boxReads = boxReads + 1 return orig(b) end
	overlay.BOX_PER_TICK = 2
	lookAt(1000)
	overlay.setOn(true)
	overlay.tick("timer")
	eq(boxReads, 2)
	eq(overlay.snapshot().viewTowns, 0) -- town 200's box (id 5) not read yet
	overlay.tick("timer")
	eq(boxReads, 4)
	eq(overlay.snapshot().viewText, "Brook")
	overlay.tick("timer")
	eq(boxReads, 4) -- pass done: no more reads
	eq(overlay.gapList, { 5 })
	overlay.BOX_PER_TICK = 2000
end)

test("perf: unchanged building map -> no box pass, no demolition pass", function()
	overlay.session.scoped = true
	local boxReads = 0
	local orig = gather.buildingBox
	gather.buildingBox = function(b) boxReads = boxReads + 1 return orig(b) end
	overlay.setOn(true)
	overlay.tick("timer")
	eq(boxReads, 3)
	for _ = 1, 3 do overlay.tick("timer") end
	eq(boxReads, 3)
	bmap = { [100] = { 1, 2, 3, 6 } }
	overlay.tick("timer")
	eq(boxReads, 4)
end)
