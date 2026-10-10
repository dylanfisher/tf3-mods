-- minimap_filter: industry types, search, selection rules, prefs (phase 7; pure, no api.*).

local filter = ug_require "square_better_minimap::/minimap/minimap_filter.tl"

local function ind(entity, typeKey, typeName, inputs, outputs)
	return { entity = entity, x = 0, y = 0, icon = "i", typeKey = typeKey, typeName = typeName,
		inputs = inputs or {}, outputs = outputs or {} }
end

local function keys(sel)
	local out = {}
	for k, v in pairs(sel) do if v then out[#out + 1] = k end end
	table.sort(out)
	return table.concat(out, ",")
end

local CARGO = { [1] = "Grain", [2] = "Food", [3] = "Crude oil", [4] = "Fuel" }

local INDS = {
	ind(10, "industry/crop_farm.con", "Crop farm", {}, { 1 }),
	ind(11, "industry/crop_farm.con", "Crop farm", {}, { 1 }),
	ind(12, "industry/food_processing_plant.con", "Food processing plant", { 1 }, { 2 }),
	ind(13, "industry/oil_refinery.con", nil, { 3 }, { 4 }),
	ind(14, "", nil),
	ind(15, nil, nil),
}

test("normKey maps unknown types to OTHER_KEY", function()
	eq(filter.normKey(""), filter.OTHER_KEY)
	eq(filter.normKey(nil), filter.OTHER_KEY)
	eq(filter.normKey("a.con"), "a.con")
end)

test("prettifyKey and displayName as Industry Flows", function()
	eq(filter.prettifyKey("::/industry/oil_refinery.con"), "Oil Refinery")
	eq(filter.prettifyKey("mod::/x/coal-mine.con"), "Coal Mine")
	eq(filter.prettifyKey(""), "")
	eq(filter.displayName("industry/oil_refinery.con", "Raffinerie"), "Raffinerie")
	eq(filter.displayName("industry/oil_refinery.con", "INDUSTRIES_OIL_REFINERY_NAME"), "Oil Refinery")
	eq(filter.displayName("industry/oil_refinery.con", "  "), "Oil Refinery")
	eq(filter.displayName("industry/oil_refinery.con", nil), "Oil Refinery")
end)

test("groupTypes counts per type, unions cargos, sorts by name with Other last", function()
	local types = filter.groupTypes(INDS, CARGO, "Other")
	eq(#types, 4)
	eq(types[1].name, "Crop farm"); eq(types[1].count, 2)
	eq(table.concat(types[1].outputs, ","), "1")
	eq(types[2].name, "Food processing plant")
	eq(table.concat(types[2].inputs, ","), "1"); eq(table.concat(types[2].outputs, ","), "2")
	eq(types[3].name, "Oil Refinery") -- no localized name: prettified key
	eq(table.concat(types[3].cargoNames, ","), "Crude oil,Fuel")
	eq(types[4].key, filter.OTHER_KEY); eq(types[4].name, "Other"); eq(types[4].count, 2)
end)

test("groupTypes copes with nil lists and names", function()
	eq(#filter.groupTypes(nil, nil, nil), 0)
	local t = filter.groupTypes({ ind(1, "x.con", nil, nil, nil) }, nil, nil)
	eq(#t, 1); eq(t[1].name, "X"); eq(#t[1].inputs, 0)
end)

test("search matches name, key and cargo names, case-insensitive", function()
	local types = filter.groupTypes(INDS, CARGO, "Other")
	eq(#filter.search(types, ""), 4)
	eq(#filter.search(types, "   "), 4)
	eq(filter.search(types, "FARM")[1].name, "Crop farm")
	eq(filter.search(types, "fuel")[1].name, "Oil Refinery") -- cargo name
	eq(filter.search(types, "refinery.con")[1].name, "Oil Refinery") -- key
	eq(#filter.search(types, "grain"), 2) -- farm (output) and food plant (input)
	eq(#filter.search(types, "nothing"), 0)
end)

test("empty selection shows all; otherwise only selected types", function()
	ok(filter.isEmpty({})); ok(filter.isEmpty(nil)); ok(filter.isEmpty({ a = false }))
	ok(filter.isVisible("a", {}))
	ok(filter.isVisible("a", { a = true }))
	ok(not filter.isVisible("b", { a = true }))
	ok(filter.isVisible("", { [filter.OTHER_KEY] = true }))
	eq(filter.count({ a = true, b = true, c = false }), 2)
end)

test("toggle returns a new selection", function()
	local s0 = {}
	local s1 = filter.toggle(s0, "a")
	eq(keys(s0), ""); eq(keys(s1), "a")
	local s2 = filter.toggle(s1, "b")
	eq(keys(s2), "a,b")
	eq(keys(filter.toggle(s2, "a")), "b")
	eq(keys(filter.toggle({}, "")), filter.OTHER_KEY)
end)

test("shiftClick: marker -> only its type; again or empty spot -> all", function()
	local sel, action = filter.shiftClick({}, "a")
	eq(keys(sel), "a"); eq(action, "only")
	sel, action = filter.shiftClick(sel, "a")
	eq(keys(sel), ""); eq(action, "all")
	sel, action = filter.shiftClick({ a = true, b = true }, "a")
	eq(keys(sel), "a"); eq(action, "only") -- not exactly {a}: narrow to a
	sel, action = filter.shiftClick({ b = true }, "a")
	eq(keys(sel), "a"); eq(action, "only")
	sel, action = filter.shiftClick({ a = true }, nil)
	eq(keys(sel), ""); eq(action, "all")
	sel, action = filter.shiftClick({}, nil)
	eq(keys(sel), ""); eq(action, "all")
end)

test("shownCount counts types on the map; selected keys not on the map count nothing", function()
	local types = filter.groupTypes(INDS, CARGO, "Other")
	local shown, total = filter.shownCount(types, {})
	eq(shown, 4); eq(total, 4)
	shown, total = filter.shownCount(types, { ["industry/crop_farm.con"] = true, ["gone.con"] = true })
	eq(shown, 1); eq(total, 4)
	shown = filter.shownCount(types, { ["gone.con"] = true })
	eq(shown, 0)
end)

test("prefs round trip", function()
	local sel = { ["b.con"] = true, ["a.con"] = true, ["c.con"] = false }
	eq(filter.toPrefs(sel), "a.con|b.con")
	eq(keys(filter.fromPrefs("a.con|b.con")), "a.con,b.con")
	eq(filter.toPrefs({}), "")
	eq(keys(filter.fromPrefs("")), "")
	eq(keys(filter.fromPrefs("||a.con| |")), "a.con")
	eq(keys(filter.fromPrefs({ "a.con", 5, "" })), "a.con")
	eq(keys(filter.fromPrefs(42)), "")
	eq(keys(filter.fromPrefs(nil)), "")
	ok(filter.same({ a = true }, { a = true, b = false }))
	ok(not filter.same({ a = true }, {}))
end)

test("describe for the log", function()
	eq(filter.describe({}), "all")
	eq(filter.describe({ b = true, a = true }), "a, b")
end)
