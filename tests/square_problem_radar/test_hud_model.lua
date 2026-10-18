-- radar_hud_model: the pure view model behind the ridge badge / compact panel and the window.
-- Fake alerts only. Shape: radar_types.d.tl ProblemRadarAlert (v2: language-neutral codes).

local model = ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl"

local function alert(id, tab, tier, firstSeen, extra)
	local a = { id = id, kind = "test_kind", tab = tab, tier = tier, entity = 100, label = "L " .. id,
		code = "C " .. id, firstSeen = firstSeen }
	for k, v in pairs(extra or {}) do a[k] = v end
	return a
end

local function state(alerts, settings)
	return { version = 2, settings = settings or { hudMode = "badge" }, alerts = alerts or {} }
end

local function ids(rows)
	local out = {}
	for i, r in ipairs(rows) do out[i] = r.id end
	return out
end

-- empty state ----------------------------------------------------------------

test("nil / {} / fresh state give the empty view", function()
	for _, s in ipairs({ false, true, "fresh" }) do
		local st = (s == false and nil) or (s == true and {}) or state()
		local v = model.build(st)
		eq(v.total, 0)
		eq(v.hidden, 0)
		eq(v.hiddenByTab, { all = 0, vehicles = 0, lines = 0, stations = 0, fleet = 0, economy = 0, snoozed = 0 })
		eq(v.worstTier, 0)
		eq(v.tierCounts, { 0, 0, 0 })
		eq(v.tabCounts, { all = 0, vehicles = 0, lines = 0, stations = 0, fleet = 0, economy = 0, snoozed = 0 })
		eq(v.rows, {})
		eq(v.hudMode, "badge")
		eq(v.badgeLabel, "Radar")
		eq(v.badgeText, "Radar ● 0")
		eq(v.compactText, "0 crit · 0 warn · 0 info")
	end
end)

test("TABS lists the alert tabs in display order", function()
	eq(model.TABS, { "all", "vehicles", "lines", "stations", "fleet", "economy" })
end)

-- counting -------------------------------------------------------------------

test("tier and tab counts", function()
	local v = model.build(state({
		alert("a", "vehicles", 1, 10),
		alert("b", "vehicles", 2, 10),
		alert("c", "lines", 1, 10),
		alert("d", "stations", 3, 10),
		alert("e", "fleet", 3, 10),
		alert("f", "fleet", 3, 10),
	}))
	eq(v.total, 6)
	eq(v.tierCounts, { 2, 1, 3 })
	eq(v.tabCounts, { all = 6, vehicles = 2, lines = 1, stations = 1, fleet = 2, economy = 0, snoozed = 0 })
	eq(v.badgeText, "Radar ● 6")
	eq(v.compactText, "2 crit · 1 warn · 3 info")
end)

test("unknown tab counts in All only; malformed alerts are skipped", function()
	local v = model.build(state({
		alert("a", "bogus", 2, 1),
		alert("bad-tier-0", "lines", 0, 1),
		alert("bad-tier-4", "lines", 4, 1),
		alert("bad-tier-str", "lines", "1", 1),
		"not a table",
		42,
	}))
	eq(v.total, 1)
	eq(v.tabCounts, { all = 1, vehicles = 0, lines = 0, stations = 0, fleet = 0, economy = 0, snoozed = 0 })
	eq(ids(v.rows), { "a" })
end)

test("non-table alerts field gives the empty view", function()
	local s = state()
	s.alerts = "oops"
	eq(model.build(s).total, 0)
end)

-- worst tier ------------------------------------------------------------------

test("worst tier is the lowest tier number present", function()
	eq(model.build(state({ alert("a", "fleet", 3, 1) })).worstTier, 3)
	eq(model.build(state({ alert("a", "fleet", 3, 1), alert("b", "lines", 2, 1) })).worstTier, 2)
	eq(model.build(state({ alert("a", "fleet", 3, 1), alert("b", "lines", 1, 1), alert("c", "lines", 2, 1) })).worstTier, 1)
end)

-- sorting -------------------------------------------------------------------

test("rows sort by tier, then firstSeen (oldest first), then id", function()
	local v = model.build(state({
		alert("info-old", "fleet", 3, 5),
		alert("crit-new", "lines", 1, 50),
		alert("warn", "vehicles", 2, 1),
		alert("crit-old", "vehicles", 1, 20),
		alert("crit-tie-b", "lines", 1, 30),
		alert("crit-tie-a", "lines", 1, 30),
	}))
	eq(ids(v.rows), { "crit-old", "crit-tie-a", "crit-tie-b", "crit-new", "warn", "info-old" })
end)

test("rowsForTab filters in view order; 'all' returns every row", function()
	local v = model.build(state({
		alert("l2", "lines", 2, 1),
		alert("v1", "vehicles", 1, 1),
		alert("l1", "lines", 1, 9),
	}))
	eq(ids(model.rowsForTab(v, "all")), { "v1", "l1", "l2" })
	eq(ids(model.rowsForTab(v, "lines")), { "l1", "l2" })
	eq(ids(model.rowsForTab(v, "fleet")), {})
	eq(model.rowsForTab(nil, "all"), {})
end)

-- row sanitising ------------------------------------------------------------------

test("rows: floats from a save become integers; missing strings become ''", function()
	local v = model.build(state({
		{ id = "x", tab = "vehicles", tier = 1.0, entity = 12.0, entity2 = 13.0, firstSeen = 7.0 },
		{ id = "y", tab = "vehicles", tier = 2 },
	}))
	local r = v.rows[1]
	eq(math.type(r.tier), "integer")
	eq(math.type(r.entity), "integer")
	eq(r.entity, 12)
	eq(r.entity2, 13)
	eq(r.firstSeen, 7)
	eq(r.label, "#12", "missing name falls back to the entity id")
	eq(r.detail, "")
	eq(r.kind, "")
	eq(r.kindLabel, "")
	eq(r.typeLabel, "")
	eq(r.context, "")
	eq(r.metric, "")
	eq(r.pos, nil)
	eq(v.rows[2].label, "", "no entity, no name")
end)

-- texts -------------------------------------------------------------------------

test("rows: kind/type labels, context, metric and the translated detail", function()
	local v = model.build(state({
		{ id = "veh_nopath:5", kind = "veh_nopath", tab = "vehicles", tier = 1, entity = 5, etype = "Train",
			label = "IC 1", context = "R2 Northern", code = "NoPathElectric", arg = "NoElectric", metric = "x", firstSeen = 1 },
	}))
	local r = v.rows[1]
	eq(r.kindLabel, "No path")
	eq(r.typeLabel, "Train")
	eq(r.label, "IC 1")
	eq(r.context, "R2 Northern")
	eq(r.metric, "x")
	eq(r.detail, "No Electrified Path: Missing electric tracks.")
end)

test("detailText covers every Phase 2 kind (base wording where it exists)", function()
	local d = model.detailText
	eq(d("veh_blocked", "Blocked", "Train 2"), "Blocking each other with Train 2")
	eq(d("veh_blocked", "Blocked", nil), "Trains Are Blocking Each Other")
	eq(d("veh_nopath", "NoPathShip", nil), "No Path for Big Ships")
	eq(d("veh_nopath", "NoPath", "NoSmallShip"), "No path: No path for big ships.")
	eq(d("veh_nopath", "NoPath", "SomethingNew"), "No path", "unknown reason adds nothing")
	eq(d("line_broken", "NO_PATH", "Catenary"), "Could Not Connect Stations: Missing catenaries")
	eq(d("line_broken", "ZERO_OR_ONE_STATION", nil), "Line Contains Too Few Stations")
	eq(d("line_broken", "WEIRD", nil), "Unknown Line Issue Occured")
	eq(d("line_no_vehicles", "NoVehicles", "3"), "No vehicles on this line (3 stops)")
	eq(d("line_cargo_issue", "NowhereToUnload", "Coal"), "Cargo cannot be unloaded anywhere: Coal")
	eq(d("line_cargo_issue", "LineCargoConfig", nil), "The line isn't configured to load any cargo.")
	eq(d("line_cargo_not_unloaded", "RoundTrip", "3|42", "3 veh · 42"), "42 cargo of 3 vehicles rode a full round trip without being unloaded")
	eq(d("line_cargo_not_unloaded", "RoundTrip", "1|7"), "7 cargo of 1 vehicle rode a full round trip without being unloaded")
	eq(d("line_cargo_not_unloaded", "RoundTrip", nil), "Cargo rides a full round trip without being unloaded")
	eq(d("line_cargo_not_unloaded", "RoundTrip", "x|y"), "Cargo rides a full round trip without being unloaded")
	eq(d("station_overcrowded", "Overcrowded", nil), "Overcrowded, passengers will be leaving")
	eq(d("station_useless", "CargoTypeLoadUseless", nil), "Configured Cargo Type Cannot Be Loaded at Stop")
	eq(d("fleet_worn", "Worn", nil), "Vehicle Condition Is Not Good")
	eq(d("future_kind", "Code", nil), "Code")
end)

test("detailText: Phase 3 kinds", function()
	local d = model.detailText
	eq(d("veh_stuck", "WATER", "Harbour West", "12m"), "Standing 12m, next stop Harbour West")
	eq(d("veh_stuck", "ROAD", nil, "3m"), "Standing 3m")
	eq(d("veh_stuck", "ROAD", nil, nil), "Vehicle Has Been Stuck for a While")
	eq(d("train_blocked_by", "BlockedBy", "IC 2", "5m"), "Waiting behind IC 2")
	eq(d("train_blocked_by", "BlockedBy", nil, nil), "Waiting behind another train")
	eq(d("train_blocked_by", "WaitingForPath", "Central", "6m"), "Waiting for Free Path, next stop Central")
	eq(d("fleet_old", "Old", "23/20"), "Age 23/20 y, past its lifespan")
	eq(d("fleet_old", "Old", nil), "Past its lifespan")
	eq(d("fleet_idle_depot", "InDepot", "45"), "In depot for 45 days")
	eq(d("fleet_idle_depot", "InDepot", nil), "In Depot")
end)

test("rows: Phase 3 alerts get labels, entity2 and the metric-aware detail", function()
	local v = model.build(state({
		{ id = "train_blocked_by:3", kind = "train_blocked_by", tab = "vehicles", tier = 2, entity = 4, entity2 = 3.0,
			etype = "Train", label = "RE 4", context = "R1", code = "BlockedBy", arg = "IC 3", metric = "20m +2", firstSeen = 1 },
		{ id = "veh_stuck:9", kind = "veh_stuck", tab = "vehicles", tier = 1, entity = 9, etype = "Ship",
			label = "Ferry", context = "Coast", code = "WATER", metric = "12m", firstSeen = 2 },
		{ id = "fleet_old:5", kind = "fleet_old", tab = "fleet", tier = 3, entity = 5, code = "Old", arg = "23/20", metric = "115%", firstSeen = 3 },
		{ id = "fleet_idle_depot:6", kind = "fleet_idle_depot", tab = "fleet", tier = 3, entity = 6, code = "InDepot", arg = "31", metric = "31d", firstSeen = 4 },
	}))
	eq(v.tabCounts.vehicles, 2)
	eq(v.tabCounts.fleet, 2)
	local m = {}
	for _, r in ipairs(v.rows) do m[r.id] = r end
	eq(m["train_blocked_by:3"].kindLabel, "Waiting")
	eq(m["train_blocked_by:3"].entity2, 3)
	eq(m["train_blocked_by:3"].detail, "Waiting behind IC 3")
	eq(m["veh_stuck:9"].kindLabel, "Stuck")
	eq(m["veh_stuck:9"].detail, "Standing 12m")
	eq(m["fleet_old:5"].kindLabel, "Old")
	eq(m["fleet_idle_depot:6"].kindLabel, "Idle")
	eq(m["fleet_idle_depot:6"].detail, "In depot for 31 days")
end)

-- cap / hidden alerts -------------------------------------------------------------

test("kindCounts above the stored rows count as hidden, per tab and tier", function()
	local s = state({
		{ id = "line_broken:1", kind = "line_broken", tab = "lines", tier = 1, entity = 1, firstSeen = 1 },
		{ id = "fleet_worn:2", kind = "fleet_worn", tab = "fleet", tier = 3, entity = 2, firstSeen = 1 },
	})
	s.total = 6
	s.kindCounts = { line_broken = 1, fleet_worn = 4.0, station_overcrowded = 1, unknown_kind = 9 }
	local v = model.build(s)
	eq(v.total, 6)
	eq(v.hidden, 4)
	eq(v.hiddenByTab, { all = 4, vehicles = 0, lines = 0, stations = 1, fleet = 3, economy = 0, snoozed = 0 })
	eq(v.tabCounts, { all = 6, vehicles = 0, lines = 1, stations = 1, fleet = 4, economy = 0, snoozed = 0 })
	eq(v.tierCounts, { 1, 1, 4 })
	eq(v.badgeText, "Radar ● 6")
	eq(#v.rows, 2)
end)

test("rows: pos kept only as three numbers; missing firstSeen sorts as 0", function()
	local v = model.build(state({
		alert("p", "lines", 1, 5, { pos = { 1, 2, 3 } }),
		alert("bad", "lines", 1, nil, { pos = { 1, "2", 3 } }),
	}))
	eq(ids(v.rows), { "bad", "p" })
	eq(v.rows[1].pos, nil)
	eq(v.rows[1].firstSeen, 0)
	eq(v.rows[2].pos, { 1, 2, 3 })
end)

test("view is fresh each call and never aliases the state", function()
	local s = state({ alert("a", "lines", 1, 1, { pos = { 1, 2, 3 } }) })
	local a, b = model.build(s), model.build(s)
	eq(a, b)
	ok(a ~= b)
	ok(a.rows[1] ~= s.alerts[1])
	ok(a.rows[1].pos ~= s.alerts[1].pos)
end)

-- hud mode ----------------------------------------------------------------------

test("hudMode: compact kept, anything else defaults to badge", function()
	eq(model.build(state({}, { hudMode = "compact" })).hudMode, "compact")
	eq(model.build(state({}, { hudMode = "giant" })).hudMode, "badge")
	eq(model.build(state({}, "nope")).hudMode, "badge")
	local s = state()
	s.settings = nil
	eq(model.build(s).hudMode, "badge")
end)

test("detailText: Phase 4 line-quality kinds (packed args, seconds as m:ss)", function()
	local d = model.detailText
	eq(d("line_overloaded", "Overloaded", "3|420|Central", "2.8×"), "Stop 3 'Central': 420 waiting, ~2.8× capacity per trip")
	eq(d("line_overloaded", "Overloaded", "3|420|A|B", "2.8×"), "Stop 3 'A|B': 420 waiting, ~2.8× capacity per trip", "a '|' in the name")
	eq(d("line_overloaded", "Overloaded", "garbage", "2.8×"), "More waiting than the line can carry")
	eq(d("line_underused", "Underused", "10", "8%"), "10 vehicles running mostly empty (8% used)")
	eq(d("line_underused", "Underused", nil, nil), "Vehicles running mostly empty")
	eq(d("line_bunching", "Clump", "3|5|40|150", "3/5"), "3 of 5 within 0:40 · target 2:30")
	eq(d("line_bunching", "Gap", "430|150", "2.9×"), "Gap 7:10 vs target 2:30")
	eq(d("line_bunching", "Gap", "x|150", nil), "Vehicles bunched or unevenly spaced")
	eq(d("line_bunching", "Clump", nil, nil), "Vehicles bunched or unevenly spaced")
end)

test("rows: Phase 4 alerts land in the Lines tab with their labels", function()
	local v = model.build(state({
		{ id = "line_bunching:7", kind = "line_bunching", tab = "lines", tier = 2, entity = 7, etype = "Line",
			label = "Bus 14", code = "Clump", arg = "3|5|40|150", metric = "3/5", firstSeen = 1 },
		{ id = "line_underused:8", kind = "line_underused", tab = "lines", tier = 3, entity = 8, etype = "Line",
			label = "Tram 2", code = "Underused", arg = "6", metric = "7%", firstSeen = 2 },
		{ id = "line_overloaded:9", kind = "line_overloaded", tab = "lines", tier = 2, entity = 9, etype = "Line",
			label = "R1", code = "Overloaded", arg = "1|900|Main", metric = "3.0×", firstSeen = 3 },
	}))
	eq(v.tabCounts.lines, 3)
	eq(v.tierCounts, { 0, 2, 1 })
	local r = model.rowsForTab(v, "lines")
	eq(r[1].kindLabel, "Bunching")
	eq(r[1].typeLabel, "Line")
	eq(r[1].detail, "3 of 5 within 0:40 · target 2:30")
	eq(r[2].kindLabel, "Over capacity")
	eq(r[2].metric, "3.0×")
	eq(r[3].kindLabel, "Underused")
end)

-- Phase 5 ------------------------------------------------------------------------

local ICONS = "::/game_mechanics/notifications/gui/icons/"

test("Phase 5: view carries the normalised settings (Settings tab)", function()
	local v = model.build(state({}, { hudMode = "compact", wornPct = 30, notify = { veh_stuck = "off" } }))
	eq(v.settings.hudMode, "compact")
	eq(v.settings.wornPct, 30)
	eq(v.settings.notify.veh_stuck, "off")
	eq(v.settings.notify.line_no_vehicles, "notify", "missing kinds default")
	eq(model.build(nil).settings.notifyPaused, false)
end)

test("Phase 5: kind and tier labels", function()
	eq(model.kindLabel("veh_stuck"), "Stuck")
	eq(model.kindLabel("line_bunching"), "Bunching")
	eq(model.kindLabel("line_cargo_not_unloaded"), "Not unloaded")
	eq(model.kindLabel("nope"), "nope")
	eq(model.tierLabel(1), "Critical")
	eq(model.tierLabel(2), "Warning")
	eq(model.tierLabel(3), "Info")
	eq(model.tierLabel(9), "Info")
end)

test("Phase 5: notification text = kind label + entity, detail (+ context), icon by kind", function()
	local title, desc, icon = model.notificationText({ kind = "veh_stuck", tier = 1, etype = "Bus", label = "Bus 14 #2",
		context = "Line 14", code = "ROAD", arg = "Central", metric = "12m", entity = 5 })
	eq(title, "Stuck: Bus 14 #2")
	eq(desc, "Standing 12m, next stop Central (Line 14)")
	eq(icon, ICONS .. "stuck_vehicle.tga")
	local t2, d2, i2 = model.notificationText({ kind = "line_broken", tier = 1.0, label = "", entity = 77, code = "NO_PATH", arg = "Catenary" })
	eq(t2, "Line broken: #77")
	eq(d2, "Could Not Connect Stations: Missing catenaries")
	eq(i2, ICONS .. "line_minus_x.tga")
	local t6, d6, i6 = model.notificationText({ kind = "line_cargo_not_unloaded", tier = 2, etype = "Line", label = "Coal",
		entity = 7, code = "RoundTrip", arg = "2|42", metric = "2 veh · 42" })
	eq(t6, "Not unloaded: Coal")
	eq(d6, "42 cargo of 2 vehicles rode a full round trip without being unloaded")
	eq(i6, ICONS .. "line_cargo_minus_unload.tga")
	local _, _, i3 = model.notificationText({ kind = "veh_nopath", tier = 1, etype = "Ship", label = "S" })
	eq(i3, ICONS .. "relation_ship_minus.tga")
	local _, _, i4 = model.notificationText({ kind = "fleet_worn", tier = 3, etype = "Train", label = "T" })
	eq(i4, ICONS .. "relation_train_repair.tga")
	local _, _, i5 = model.notificationText({ kind = "fleet_worn", tier = 3, etype = "", label = "T" })
	eq(i5, ICONS .. "relation_bus_repair.tga", "unknown vehicle type falls back")
	local _, _, i6 = model.notificationText({ kind = "station_overcrowded", tier = 2, label = "S" })
	eq(i6, ICONS .. "terminal_full.tga")
end)

test("Phase 5: summary toast and garbage params give the generic text, never an error", function()
	local t, d, i = model.notificationText({ more = 4.0 })
	eq(t, "Problem Radar")
	eq(d, "+4 more new problems. Open the radar from the button ridge to see them.")
	eq(i, ICONS .. "line_minus_x.tga")
	for _, p in ipairs({ false, "x", {}, { kind = 3 } }) do
		local tt, dd, ii = model.notificationText(p ~= false and p or nil)
		eq(tt, "Problem Radar")
		ok(type(dd) == "string" and type(ii) == "string")
	end
	local t2 = model.notificationText({ kind = "veh_stuck", tier = "x" })
	eq(t2, "Stuck")
end)

-- Phase 6 -------------------------------------------------------------------------

local checks6 = ug_require "square_problem_radar::/radar/radar_checks.tl"

local function kalert(kind, key, firstSeen)
	local k = checks6.KINDS[kind]
	return { id = kind .. ":" .. key, kind = kind, tab = k.tab, tier = k.tier, entity = tonumber(key) or 1, etype = "Bus",
		label = "L" .. key, context = "", code = "ROAD", firstSeen = firstSeen or 0, metric = "4m" }
end

test("Phase 6: counts view from kindCounts only (no rows, no texts)", function()
	local c = model.counts({ veh_stuck = 2, fleet_worn = 3.0, line_bunching = 1, bogus = 5, line_broken = "x", veh_nopath = 0 }, "compact")
	eq(c, { hudMode = "compact", total = 6, tierCounts = { 2, 1, 3 }, worstTier = 1 })
	eq(model.counts(nil, nil), { hudMode = "badge", total = 0, tierCounts = { 0, 0, 0 }, worstTier = 0 })
	eq(model.counts("junk", 7).hudMode, "badge")
	eq(model.compactText({ 2, 1, 3 }), "2 crit · 1 warn · 3 info")
end)

test("Phase 6: buildRaw has the counts but no translated texts; decorate fills them like build", function()
	local s = { alerts = { kalert("veh_stuck", "5") }, kindCounts = { veh_stuck = 1 } }
	local raw = model.buildRaw(s)
	local full = model.build(s)
	eq(raw.tabCounts, full.tabCounts)
	eq(raw.rows[1].detail, "")
	eq(raw.rows[1].kindLabel, "")
	eq(raw.compactText, "")
	model.decorate(raw.rows[1])
	eq(raw.rows[1], full.rows[1])
end)

test("Phase 6: visibleRows renders at most 100 rows of a tab; the rest is counted as more", function()
	eq(model.MAX_RENDERED_ROWS, 100)
	local alerts = {}
	for i = 1, 150 do alerts[#alerts + 1] = kalert("veh_stuck", tostring(i), i) end
	for i = 1, 5 do alerts[#alerts + 1] = kalert("fleet_worn", tostring(1000 + i), i) end
	local view = model.buildRaw({ alerts = alerts, kindCounts = { veh_stuck = 160, fleet_worn = 5 } })
	local rows, more = model.visibleRows(view, "vehicles")
	eq(#rows, 100)
	eq(more, 50 + 10, "50 not rendered + 10 over the stored cap")
	ok(rows[1].detail ~= "", "rendered rows are decorated")
	eq(view.rows[120].detail, "", "rows not rendered stay plain")
	local fleet, fmore = model.visibleRows(view, "fleet")
	eq(#fleet, 5)
	eq(fmore, 0)
	local some, smore = model.visibleRows(view, "all", 3)
	eq(#some, 3)
	eq(smore, 152 + 10)
	local none, nmore = model.visibleRows(nil, "all")
	eq(#none, 0)
	eq(nmore, 0)
end)

test("Phase 6: visibleRows leaves the view's rows plain, so an unchanged poll deepEquals the shown view", function()
	local alerts = { kalert("veh_stuck", "1", 1), kalert("fleet_worn", "2", 2) }
	local state = { alerts = alerts, kindCounts = { veh_stuck = 1, fleet_worn = 1 } }
	local view = model.buildRaw(state)
	local rows = model.visibleRows(view, "all")
	ok(rows[1].detail ~= "", "rendered rows are decorated")
	eq(view.rows[1].detail, "", "the view's row is not")
	eq(view.rows[1].kindLabel, "")
	eq(model.buildRaw(state), view, "the next poll's view equals the rendered one (no re-render)")
end)

test("Phase 6: trackRevisions remembers each listed entity's revision; sameRevision spots reuse", function()
	local view = model.buildRaw({ alerts = { kalert("veh_stuck", "1"), kalert("veh_stuck", "2"), kalert("veh_stuck", "3") } })
	local lookups = 0
	local current = { [1] = 10, [2] = 20 }
	local function revOf(e) lookups = lookups + 1 return current[e] end
	local revs = model.trackRevisions({ ["veh_stuck:1"] = 9, ["gone:1"] = 5 }, view.rows, revOf)
	eq(revs, { ["veh_stuck:1"] = 9, ["veh_stuck:2"] = 20 }, "known kept, new looked up, gone dropped, 3 has none")
	eq(lookups, 2)
	ok(model.sameRevision(9, 9))
	eq(model.sameRevision(9, 10), false, "created after the row was listed: a reused id")
	ok(model.sameRevision(nil, 10), "unknown counts as the same")
	ok(model.sameRevision(9, nil))
end)

-- window position ------------------------------------------------------------

test("windowAnchor: content rect + frame offset, kept on screen; invalid rects give nil", function()
	local x, y = model.windowAnchor(0.2, 0.3, 0.6, 0.6, 0.2, 0.1, 0.08)
	eq({ x, y }, { 0.2 + 0.2, 0.3 + 0.1 }, "on screen: unchanged + offset")
	x, y = model.windowAnchor(0.8, 0.0, 1.2, 0.3, 0.2, 0.1, 0.08)
	eq({ x, y }, { 0.6 + 0.2, 0.08 + 0.1 }, "past the right edge and above minTop: pulled back")
	x, y = model.windowAnchor(-0.25, 0.875, 0.25, 1.125, 0, 0, 0.08)
	eq({ x, y }, { 0, 0.75 }, "past the left and bottom edges")
	eq({ model.windowAnchor(0, 0, 0, 0, 0, 0, 0.08) }, {}, "not laid out yet")
	eq({ model.windowAnchor(0 / 0, 0, 0.5, 0.5, 0, 0, 0.08) }, {}, "NaN")
	eq({ model.windowAnchor(0.1, 0.1, 0.5, 0.5, nil, 0, 0.08) }, {}, "no offset")
	eq({ model.windowAnchor(3, 3, 3.5, 3.5, 0, 0, 0.08) }, {}, "far off screen")
end)

test("readWindowPos: fractions in 0..1 only", function()
	eq({ model.readWindowPos({ x = 0.5, y = 0.25 }) }, { 0.5, 0.25 })
	eq({ model.readWindowPos(nil) }, {})
	eq({ model.readWindowPos("x") }, {})
	eq({ model.readWindowPos({ x = 0.5 }) }, {})
	eq({ model.readWindowPos({ x = 1.5, y = 0.2 }) }, {})
	eq({ model.readWindowPos({ x = 0 / 0, y = 0.2 }) }, {})
	eq({ model.readWindowPos({ x = "0.5", y = 0.2 }) }, {})
end)

-- translations ---------------------------------------------------------------

test("metricText: the engine's unit letters go through _() templates; other metrics unchanged", function()
	eq(model.metricText("veh_stuck", "12m"), "12m")
	eq(model.metricText("veh_stuck", "1h05m"), "1h05m")
	eq(model.metricText("train_blocked_by", "20m +2"), "20m +2")
	eq(model.metricText("train_blocked_by", "1h05m +2"), "1h05m +2")
	eq(model.metricText("fleet_idle_depot", "31d"), "31d")
	eq(model.metricText("line_cargo_not_unloaded", "3 veh · 42"), "3 veh · 42")
	eq(model.metricText("line_overloaded", "2.8×"), "2.8×")
	eq(model.metricText("fleet_worn", "40%"), "40%")
	eq(model.metricText("veh_stuck", ""), "")
	eq(model.metricText("veh_stuck", nil), nil)
end)

test("translated templates: units, joins and parentheses come from _(), names stay as they are", function()
	local fake = {
		["{m}m"] = "{m} мин", ["{h}h{m}m"] = "{h} ч {m} мин", ["{n}d"] = "{n} дн.",
		["{n} veh · {cargo}"] = "{n} ТС · {cargo}",
		["{text}, next stop {stop}"] = "{text}, след. {stop}",
		["Standing {time}"] = "Стоит {time}",
		["{text}: {reason}"] = "{text} - {reason}",
		["{kind}: {name}"] = "[{kind}] {name}",
		["{text} ({context})"] = "{text} <{context}>",
	}
	local real = _
	_ = function(s) return fake[s] or s end
	local okRun, err = pcall(function()
		eq(model.metricText("veh_stuck", "1h05m"), "1 ч 05 мин")
		eq(model.metricText("train_blocked_by", "20m +2"), "20 мин +2")
		eq(model.metricText("fleet_idle_depot", "31d"), "31 дн.")
		eq(model.metricText("line_cargo_not_unloaded", "3 veh · 42"), "3 ТС · 42")
		eq(model.detailText("veh_stuck", "ROAD", "Central", "12m"), "Стоит 12 мин, след. Central")
		eq(model.detailText("veh_nopath", "NoPathElectric", "NoElectric"), "No Electrified Path - Missing electric tracks.")
		local title, desc = model.notificationText({ kind = "veh_stuck", tier = 1, label = "Bus 14", code = "ROAD",
			metric = "3m", context = "Line 14" })
		eq(title, "[Stuck] Bus 14")
		eq(desc, "Стоит 3 мин <Line 14>")
	end)
	_ = real
	if not okRun then error(err, 0) end
end)

test("wrapTooltip: lines of at most the width, CJK double, no line starts with closing punctuation", function()
	eq(model.wrapTooltip("Losing money: a big loss is at least, of all lines' vehicle costs (3× = very big)", 40),
		"Losing money: a big loss is at least, of\nall lines' vehicle costs (3× = very big)")
	eq(model.wrapTooltip("short", 60), "short")
	eq(model.wrapTooltip("a\nb c", 1), "a\nb\nc")
	eq(model.wrapTooltip(nil, 60), nil)
	-- a word longer than the width stays whole
	eq(model.wrapTooltip("abcdefgh ij", 4), "abcdefgh\nij")
	-- CJK: 2 columns each, breaks between characters; the 。 sticks to the character before it (both
	-- move to the next line rather than the 。 starting one)
	local w = model.wrapTooltip("警告警告警告。警告", 12)
	eq(w, "警告警告警\n告。警告")
	for line in (w .. "\n"):gmatch("(.-)\n") do ok(line:sub(1, 3) ~= "。") end
	-- mixed: Latin words and CJK
	eq(model.wrapTooltip("Zz で警告をスヌーズする期間", 10), "Zz で警告\nをスヌーズ\nする期間")
end)
