-- flows_model: the pure model behind the Industry Flows panel (PLAN phase 2).
-- Fake worlds only. Shapes: industry_flows_types.d.tl (IndustryFlowsWorld, IndustryFlowsView).

local model = ug_require "square_industry_flows::/industry_flows/flows_model.tl"

local FISH = "::/industries/fishing_grounds/fishing_grounds.con"
local FARM = "::/industries/farm/farm.con"
local MILL = "::/industries/saw_mill/saw_mill.con"
local FOREST = "::/industries/forest/forest.con"
local FOOD = "::/industries/food_plant/food_plant.con"

-- cargo ids
local FISHC, GRAIN, LOGS, PLANKS, FOODC = 1, 2, 3, 4, 5

local function ind(entity, key, extra)
	local i = { entity = entity, typeKey = key, pos = { entity, entity * 2, 10 },
		inputs = {}, outputs = {}, inputStocks = {}, outputStocks = {} }
	for k, v in pairs(extra or {}) do i[k] = v end
	return i
end

local function producer(entity, key, cargo)
	return ind(entity, key, { outputs = { cargo }, outputStocks = { cargo } })
end

local function consumer(entity, key, cargoIn, cargoOut)
	return ind(entity, key, { inputs = { cargoIn }, inputStocks = { cargoIn },
		outputs = cargoOut and { cargoOut } or {}, outputStocks = cargoOut and { cargoOut } or {} })
end

local function world(industries, towns, names, cargoNames)
	return { industries = industries, towns = towns or {}, typeNames = names or {}, cargoNames = cargoNames or {} }
end

-- flowCount fake: links listed in `active` ("from>to:cargo") have flow.
local function flows(active, calls)
	local set = {}
	for _, k in ipairs(active or {}) do set[k] = true end
	return function(from, to, cargo, toTown)
		if calls then calls[#calls + 1] = { from, to, cargo, toTown } end
		return set[from .. ">" .. to .. ":" .. cargo] and 3 or 0
	end
end

local function keys(view)
	local out = {}
	for i, l in ipairs(view.links) do out[i] = l.fromEntity .. ">" .. l.toEntity .. ":" .. l.cargo end
	return out
end

local function typeKeys(types)
	local out = {}
	for i, t in ipairs(types) do out[i] = t.key end
	return out
end

local ALL = { inputs = true, outputs = true, potential = true }

-- names ----------------------------------------------------------------------

test("prettifyKey: folder name, extension dropped, words capitalized", function()
	eq(model.prettifyKey(FISH), "Fishing Grounds")
	eq(model.prettifyKey("::/industries/oil_refinery/oil_refinery.con"), "Oil Refinery")
	eq(model.prettifyKey("industries/farm/farm.con"), "Farm")
	eq(model.prettifyKey("my-mod_thing.con"), "My Mod Thing")
	eq(model.prettifyKey(""), "")
	eq(model.prettifyKey(nil), "")
end)

test("displayName: localized name wins, raw ids and blanks fall back", function()
	eq(model.displayName(FISH, "Fischgründe"), "Fischgründe")
	eq(model.displayName(FISH, "  Fishing grounds "), "Fishing grounds")
	eq(model.displayName(FISH, nil), "Fishing Grounds")
	eq(model.displayName(FISH, ""), "Fishing Grounds")
	eq(model.displayName(FISH, "   "), "Fishing Grounds")
	eq(model.displayName(FISH, "INDUSTRIES_FISHING_GROUNDS_NAME"), "Fishing Grounds")
	-- an all-caps word without underscore is a real name
	eq(model.displayName("::/x/ufo/ufo.con", "UFO"), "UFO")
end)

-- grouping ---------------------------------------------------------------------

test("groupTypes: counts, sorted entities, sorted by name, unknown key skipped", function()
	local w = world({
		ind(30, FISH), ind(10, FISH), ind(20, FARM), ind(5, ""), ind(40, MILL), ind(11, FISH),
	}, nil, { [FARM] = "Farm", [MILL] = "Sawmill" })
	local types = model.groupTypes(w)
	eq(typeKeys(types), { FARM, FISH, MILL })
	eq(types[1], { key = FARM, name = "Farm", count = 1, entities = { 20 }, inputs = {}, outputs = {}, cargoNames = {} })
	eq(types[2], { key = FISH, name = "Fishing Grounds", count = 3, entities = { 10, 11, 30 }, inputs = {}, outputs = {}, cargoNames = {} })
	eq(types[3].name, "Sawmill")
end)

test("groupTypes: inputs / outputs are the sorted union over the type's industries", function()
	local types = model.groupTypes(world({
		ind(1, MILL, { inputs = { LOGS }, outputs = { PLANKS } }),
		ind(2, MILL, { inputs = { LOGS, GRAIN, LOGS }, outputs = { PLANKS } }),
		ind(3, FOOD, { inputs = { FISHC }, outputs = {} }),
	}, nil, { [MILL] = "Sawmill", [FOOD] = "Food" }))
	eq(types[1].key, FOOD)
	eq(types[1].inputs, { FISHC })
	eq(types[1].outputs, {})
	eq(types[2].inputs, { GRAIN, LOGS })
	eq(types[2].outputs, { PLANKS })
end)

test("groupTypes: cargoNames lists input then output names, unknown ones left out", function()
	local types = model.groupTypes(world({ consumer(1, MILL, LOGS, PLANKS), producer(2, FOREST, LOGS) },
		nil, { [MILL] = "Sawmill", [FOREST] = "Forest" }, { [LOGS] = "Logs", [PLANKS] = "" }))
	eq(types[1].cargoNames, { "Logs" })            -- Forest: output logs
	eq(types[2].cargoNames, { "Logs" })            -- Sawmill: planks has no usable name
end)

test("search: matches input and output cargo names", function()
	local REFINERY, WELL = "::/industries/oil_refinery/oil_refinery.con", "::/industries/oil_well/oil_well.con"
	local OIL, FUEL = 6, 7
	local types = model.groupTypes(world({ consumer(1, REFINERY, OIL, FUEL), producer(2, WELL, OIL), ind(3, FARM) },
		nil, { [REFINERY] = "Oil refinery", [WELL] = "Oil well", [FARM] = "Farm" }, { [OIL] = "Crude oil", [FUEL] = "Fuel" }))
	eq(typeKeys(model.search(types, "fuel")), { REFINERY })
	eq(typeKeys(model.search(types, "CRUDE")), { REFINERY, WELL })
	eq(typeKeys(model.search(types, "farm")), { FARM })
end)

test("typeList: rows carry the type's input and output cargos", function()
	local types = model.groupTypes(world({ consumer(1, MILL, LOGS, PLANKS) }, nil, { [MILL] = "Sawmill" }))
	local row = model.typeList(types, "", model.newSelection()).rows[1]
	eq(row.inputs, { LOGS })
	eq(row.outputs, { PLANKS })
end)

test("groupTypes: case-insensitive name order, key breaks ties; empty world", function()
	local a, b = "::/b/b.con", "::/a/a.con"
	local types = model.groupTypes(world({ ind(1, a), ind(2, b), ind(3, FOREST) },
		nil, { [a] = "same", [b] = "Same", [FOREST] = "alpha" }))
	eq(typeKeys(types), { FOREST, b, a })
	eq(model.groupTypes(world({})), {})
	eq(model.groupTypes(nil), {})
end)

-- search -----------------------------------------------------------------------

local function sampleTypes()
	return model.groupTypes(world({
		ind(1, FISH), ind(2, FISH), ind(3, FARM), ind(4, MILL), ind(5, FOREST),
	}, nil, { [FISH] = "Fischgründe", [FARM] = "Farm", [MILL] = "Sawmill", [FOREST] = "Forest" }))
end

test("search: empty, blank or nil query returns all, sorted by name with counts", function()
	local types = sampleTypes()
	eq(typeKeys(model.search(types, "")), { FARM, FISH, FOREST, MILL })
	eq(typeKeys(model.search(types, "   ")), { FARM, FISH, FOREST, MILL })
	eq(typeKeys(model.search(types, nil)), { FARM, FISH, FOREST, MILL })
	eq(model.search(types, "")[2].count, 2)
end)

test("search: matches the key as well as the localized name", function()
	local types = sampleTypes()
	-- "fish" is not in "Fischgründe" but is in the key fishing_grounds
	eq(typeKeys(model.search(types, "fish")), { FISH })
	-- "fisch" is only in the localized name
	eq(typeKeys(model.search(types, "fisch")), { FISH })
	-- "saw" matches the key saw_mill and the name Sawmill once
	eq(typeKeys(model.search(types, "saw")), { MILL })
end)

test("search: case-insensitive, trimmed, plain (no patterns)", function()
	local types = sampleTypes()
	eq(typeKeys(model.search(types, "  FiSh ")), { FISH })
	eq(typeKeys(model.search(types, "F")), { FARM, FISH, FOREST })
	eq(typeKeys(model.search(types, "fo")), { FOREST })
	eq(model.search(types, "%a"), {})
	eq(model.search(types, "zzz"), {})
	eq(model.search(nil, "x"), {})
end)

test("search: a 'Fish...' localized name and a fishing key both match 'fish'", function()
	local other = "::/mods/x/fish_farm.con"
	local types = model.groupTypes(world({ ind(1, FISH), ind(2, other), ind(3, FARM) },
		nil, { [FISH] = "Fishing grounds", [other] = "Aquaculture", [FARM] = "Fishery farm" }))
	eq(typeKeys(model.search(types, "fish")), { other, FARM, FISH })  -- Aquaculture, Fishery farm, Fishing grounds
end)

-- selection --------------------------------------------------------------------

test("selection: newSelection, toggleSelected (immutable), selectedKeys sorted", function()
	local s0 = model.newSelection()
	eq(s0, {})
	local s1 = model.toggleSelected(s0, FISH)
	eq(s0, {}, "input set unchanged")
	eq(s1, { [FISH] = true })
	local s2 = model.toggleSelected(s1, FARM)
	eq(model.selectedKeys(s2), { FARM, FISH })
	local s3 = model.toggleSelected(s2, FISH)
	eq(s3, { [FARM] = true })
	eq(s2, { [FISH] = true, [FARM] = true })
	eq(model.selectedKeys(model.newSelection({ MILL, FISH, MILL })), { FISH, MILL })
	eq(model.selectedKeys({ [FISH] = false, [FARM] = true }), { FARM })
	eq(model.selectedKeys(nil), {})
end)

test("defaultToggles: all on, fresh table each call", function()
	local t = model.defaultToggles()
	eq(t, ALL)
	t.inputs = false
	eq(model.defaultToggles(), ALL)
end)

-- links ------------------------------------------------------------------------

-- forest(1) -> logs -> mill(2) -> planks -> town(100, needs planks); mill2(3) also takes logs.
-- fish(10, 11) -> fish -> food(20) -> food -> town(100) / town(101)
local function chain()
	return world({
		producer(1, FOREST, LOGS),
		consumer(2, MILL, LOGS, PLANKS),
		consumer(3, MILL, LOGS, PLANKS),
		producer(10, FISH, FISHC),
		producer(11, FISH, FISHC),
		consumer(20, FOOD, FISHC, FOODC),
		ind(30, FARM, { outputs = { GRAIN }, outputStocks = { GRAIN } }),
	}, {
		{ entity = 100, pos = { 0, 0, 0 }, needs = { FOODC, PLANKS } },
		{ entity = 101, pos = { 1, 1, 0 }, needs = { PLANKS } },
		{ entity = 102, pos = { 2, 2, 0 }, needs = { GRAIN + 100 } },
	})
end

test("buildView: nothing selected or nil world gives the empty view", function()
	local empty = { typeKeys = {}, industries = 0, links = {}, total = 0, active = 0, drawn = 0 }
	eq(model.buildView(chain(), {}, ALL, flows()), empty)
	eq(model.buildView(chain(), nil, ALL, flows()), empty)
	local v = model.buildView(nil, model.newSelection({ FISH }), ALL, flows())
	eq(v.typeKeys, { FISH })
	eq(v.industries, 0)
end)

test("buildView: selected type with no industries on the map", function()
	local v = model.buildView(chain(), model.newSelection({ "::/nope.con" }), ALL, flows())
	eq(v, { typeKeys = { "::/nope.con" }, industries = 0, links = {}, total = 0, active = 0, drawn = 0 })
end)

test("buildView: outputs of every industry of the type, industry and town consumers", function()
	local v = model.buildView(chain(), model.newSelection({ FISH }), ALL, flows())
	eq(v.industries, 2)
	eq(keys(v), { "10>20:1", "11>20:1" })
	local l = v.links[1]
	eq(l, { fromEntity = 10, toEntity = 20, from = { 10, 20, 10 }, to = { 20, 40, 10 }, cargo = FISHC,
		input = false, toTown = false, active = false })
	-- food plant: input from both fish grounds, output to the town that needs food first
	local f = model.buildView(chain(), model.newSelection({ FOOD }), ALL, flows())
	eq(keys(f), { "10>20:1", "11>20:1", "20>100:5" })
	eq(f.links[1].input, true)
	eq(f.links[3].toTown, true)
	eq(f.links[3].input, false)
	eq(f.links[3].to, { 0, 0, 0 })
end)

test("buildView: one link per town (its first need the industry produces)", function()
	local w = chain()
	w.industries[#w.industries + 1] = ind(40, "::/multi.con", { outputs = { PLANKS, FOODC }, outputStocks = { PLANKS, FOODC } })
	local v = model.buildView(w, model.newSelection({ "::/multi.con" }), { inputs = false, outputs = true, potential = true }, flows())
	-- town 100 needs FOOD first, town 101 PLANKS; town 102 nothing
	eq(keys(v), { "40>100:5", "40>101:4" })
end)

test("buildView: Inputs / Outputs toggles", function()
	local sel = model.newSelection({ MILL })
	local both = model.buildView(chain(), sel, ALL, flows())
	eq(keys(both), { "1>2:3", "1>3:3", "2>100:4", "2>101:4", "3>100:4", "3>101:4" })
	local inputs = model.buildView(chain(), sel, { inputs = true, outputs = false, potential = true }, flows())
	eq(keys(inputs), { "1>2:3", "1>3:3" })
	for _, l in ipairs(inputs.links) do eq(l.input, true) end
	local outputs = model.buildView(chain(), sel, { inputs = false, outputs = true, potential = true }, flows())
	eq(keys(outputs), { "2>100:4", "2>101:4", "3>100:4", "3>101:4" })
	for _, l in ipairs(outputs.links) do eq(l.input, false) end
	local none = model.buildView(chain(), sel, { inputs = false, outputs = false, potential = true }, flows())
	eq(none.industries, 2)
	eq(none.links, {})
	eq(none.total, 0)
end)

test("buildView: Potential off keeps only active links; counts follow", function()
	local sel = model.newSelection({ MILL })
	local f = flows({ "1>3:3", "2>101:4" })
	local on = model.buildView(chain(), sel, ALL, f)
	eq(on.total, 6)
	eq(on.active, 2)
	eq(on.drawn, 6)
	local off = model.buildView(chain(), sel, { inputs = true, outputs = true, potential = false }, f)
	eq(keys(off), { "1>3:3", "2>101:4" })
	eq(off.total, 2)
	eq(off.active, 2)
	eq(off.drawn, 2)
	for _, l in ipairs(off.links) do eq(l.active, true) end
end)

test("buildView: flowCount gets (from, to, cargo, toTown); nil or 0 = potential", function()
	local calls = {}
	model.buildView(chain(), model.newSelection({ FOOD }), { inputs = false, outputs = true, potential = true }, flows({}, calls))
	eq(calls, { { 20, 100, FOODC, true } })
	local v = model.buildView(chain(), model.newSelection({ FISH }), ALL, function() return nil end)
	eq(v.active, 0)
	eq(v.total, 2)
end)

test("buildView: active links first, then by from, to, cargo", function()
	local sel = model.newSelection({ MILL })
	local v = model.buildView(chain(), sel, ALL, flows({ "3>101:4", "1>3:3", "3>100:4" }))
	eq(keys(v), { "1>3:3", "3>100:4", "3>101:4", "1>2:3", "2>100:4", "2>101:4" })
	eq(v.active, 3)
end)

test("buildView: order does not depend on input order", function()
	local w1, w2 = chain(), chain()
	local rev = {}
	for i = #w2.industries, 1, -1 do rev[#rev + 1] = w2.industries[i] end
	w2.industries = rev
	w2.towns = { w2.towns[3], w2.towns[1], w2.towns[2] }
	local sel = model.newSelection({ MILL, FISH, FOOD })
	eq(model.buildView(w1, sel, ALL, flows({ "2>100:4" })), model.buildView(w2, sel, ALL, flows({ "2>100:4" })))
end)

test("buildView: de-dup when two selected types see the same link", function()
	-- forest(1) -> mill(2): output of FOREST and input of MILL
	local sel = model.newSelection({ FOREST, MILL })
	local v = model.buildView(chain(), sel, ALL, flows())
	eq(keys(v), { "1>2:3", "1>3:3", "2>100:4", "2>101:4", "3>100:4", "3>101:4" })
	eq(v.industries, 3)
	eq(v.total, 6)
end)

test("buildView: duplicate cargo entries and multiple rules give one link", function()
	local w = world({
		ind(1, FOREST, { outputs = { LOGS, LOGS }, outputStocks = { LOGS, LOGS } }),
		ind(2, MILL, { inputs = { LOGS, LOGS }, inputStocks = { LOGS, LOGS } }),
	})
	local v = model.buildView(w, model.newSelection({ FOREST, MILL }), ALL, flows())
	eq(keys(v), { "1>2:3" })
end)

test("buildView: no self links; links without positions are dropped", function()
	local w = world({
		ind(1, MILL, { inputs = { LOGS }, inputStocks = { LOGS }, outputs = { LOGS }, outputStocks = { LOGS } }),
		ind(2, FOREST, { outputs = { LOGS }, outputStocks = { LOGS }, pos = false }),
		ind(3, FOREST, { outputs = { LOGS }, outputStocks = { LOGS }, pos = { 1, 2 } }),
		ind(4, FOREST, { outputs = { LOGS }, outputStocks = { LOGS } }),
	}, { { entity = 100, needs = { LOGS } } })
	for _, i in ipairs(w.industries) do if i.pos == false then i.pos = nil end end
	local calls = {}
	local v = model.buildView(w, model.newSelection({ MILL }), ALL, flows({}, calls))
	eq(keys(v), { "4>1:3" })
	eq(#calls, 1, "flowCount only for drawable links")
end)

test("buildView: links copy positions (no shared tables with the world)", function()
	local w = chain()
	local v = model.buildView(w, model.newSelection({ FISH }), ALL, flows())
	v.links[1].from[1] = 999
	eq(w.industries[4].pos, { 10, 20, 10 })
end)

test("buildView: cap at MAX_LINKS keeps active first; total/active count all", function()
	eq(model.MAX_LINKS, 400)
	-- one producer, 450 consumers; consumers 401..450 (entity 1401..1450) are active
	local industries = { producer(1, FISH, FISHC) }
	local active = {}
	for i = 1, 450 do
		industries[#industries + 1] = consumer(1000 + i, FOOD, FISHC)
		if i > 400 then active[#active + 1] = "1>" .. (1000 + i) .. ":1" end
	end
	local v = model.buildView(world(industries), model.newSelection({ FISH }), ALL, flows(active))
	eq(v.total, 450)
	eq(v.active, 50)
	eq(v.drawn, 400)
	eq(#v.links, 400)
	eq(v.links[1].toEntity, 1401)
	eq(v.links[50].toEntity, 1450)
	eq(v.links[51].toEntity, 1001)
	eq(v.links[400].toEntity, 1350)
	for i = 1, 50 do eq(v.links[i].active, true) end
end)

test("buildView: the view is plain data (deepEquals-friendly)", function()
	local v1 = model.buildView(chain(), model.newSelection({ MILL }), ALL, flows({ "1>2:3" }))
	local v2 = model.buildView(chain(), model.newSelection({ MILL }), ALL, flows({ "1>2:3" }))
	eq(v1, v2)
	ok(v1 ~= v2)
end)

-- panel (phase 3) -----------------------------------------------------------

local function panelTypes()
	return model.groupTypes(world({
		producer(1, FISH, FISHC), producer(2, FISH, FISHC), producer(3, FARM, GRAIN),
		consumer(4, FOOD, FISHC, FOODC), producer(5, FOREST, LOGS),
	}, {}, { [FISH] = "Fishing grounds", [FARM] = "Farm", [FOOD] = "Food processing plant", [FOREST] = "Forest" }))
end

local function rowKeys(list)
	local out = {}
	for i, r in ipairs(list.rows) do out[i] = r.key .. (r.selected and "*" or "") .. " x" .. r.count end
	return out
end

test("withToggle: copies and sets one field, ignores unknown names", function()
	local t = model.defaultToggles()
	local t2 = model.withToggle(t, "potential", false)
	eq(t2, { inputs = true, outputs = true, potential = false })
	eq(t, ALL, "input unchanged")
	eq(model.withToggle(t2, "inputs", false), { inputs = false, outputs = true, potential = false })
	eq(model.withToggle(t2, "outputs", false), { inputs = true, outputs = false, potential = false })
	eq(model.withToggle(t2, "bogus", true), t2)
	ok(model.withToggle(t2, "bogus", true) ~= t2, "always a copy")
	eq(model.withToggle(nil, "inputs", false), { inputs = false, outputs = true, potential = true })
end)

test("newPanelState: nothing selected, empty query, default toggles", function()
	local s = model.newPanelState()
	eq(s.query, "")
	eq(model.selectedKeys(s.selection), {})
	eq(s.toggles, ALL)
end)

test("copyPanelState: deep copy that drops false entries; nil gives a new state", function()
	local s = { query = "fi", selection = { [FISH] = true, [FARM] = false }, toggles = { inputs = false, outputs = true, potential = true } }
	local c = model.copyPanelState(s)
	eq(c, { query = "fi", selection = { [FISH] = true }, toggles = { inputs = false, outputs = true, potential = true } })
	ok(c.selection ~= s.selection and c.toggles ~= s.toggles)
	c.selection[MILL] = true
	eq(s.selection[MILL], nil)
	eq(model.copyPanelState(nil), model.newPanelState())
end)

test("typeList: all types for an empty query, sorted by name, with counts", function()
	local l = model.typeList(panelTypes(), "", model.newSelection())
	eq(rowKeys(l), { FARM .. " x1", FISH .. " x2", FOOD .. " x1", FOREST .. " x1" })
	eq(l.rows[2].name, "Fishing grounds")
	eq(l.selectedCount, 0)
	eq(l.hiddenSelected, 0)
end)

test("typeList: search filters rows; selected rows are marked", function()
	local sel = model.newSelection({ FISH })
	local l = model.typeList(panelTypes(), "  FIS ", sel)
	eq(rowKeys(l), { FISH .. "* x2" })
	eq(l.selectedCount, 1)
	eq(l.hiddenSelected, 0)
end)

test("typeList: selections filtered out by the search stay selected and are counted", function()
	local sel = model.newSelection({ FISH, FOREST })
	local l = model.typeList(panelTypes(), "farm", sel)
	eq(rowKeys(l), { FARM .. " x1" })
	eq(l.selectedCount, 2)
	eq(l.hiddenSelected, 2)
	eq(model.selectedKeys(sel), { FISH, FOREST }, "selection untouched")
end)

test("typeList: a selected type no longer on the map counts as hidden", function()
	local sel = model.newSelection({ MILL, FISH })
	local l = model.typeList(panelTypes(), "", sel)
	eq(#l.rows, 4)
	eq(l.selectedCount, 2)
	eq(l.hiddenSelected, 1)
end)

test("typeList: no match gives no rows; nil types are fine", function()
	eq(model.typeList(panelTypes(), "zzz", model.newSelection()).rows, {})
	eq(model.typeList(nil, "", model.newSelection({ FISH })), { rows = {}, selectedCount = 1, hiddenSelected = 1 })
end)

test("toggleSelected: multi-select across searches, then clear", function()
	local sel = model.toggleSelected(model.newSelection(), FISH)
	sel = model.toggleSelected(sel, FARM)
	eq(model.selectedKeys(sel), { FARM, FISH })
	sel = model.toggleSelected(sel, FISH)
	eq(model.selectedKeys(sel), { FARM })
	eq(model.selectedKeys(model.newSelection()), {}, "Clear = a new empty selection")
end)

test("summary: empty, loading, none and links states", function()
	local none = model.newSelection()
	local fish = model.newSelection({ FISH })
	eq(model.summary(nil, none).state, "empty")
	eq(model.summary({ typeKeys = {}, industries = 0, links = {}, total = 0, active = 0, drawn = 0 }, none).state, "empty")
	eq(model.summary(nil, fish).state, "loading")
	eq(model.summary({ typeKeys = { FISH }, industries = 0, links = {}, total = 0, active = 0, drawn = 0 }, fish).state, "none")
	local v = model.buildView(chain(), model.newSelection({ MILL }), ALL, flows({ "1>2:3" }))
	eq(model.summary(v, model.newSelection({ MILL })), {
		state = "links", industries = v.industries, total = v.total, active = v.active, drawn = v.drawn, capped = false,
	})
end)

test("summary: capped when more links than MAX_LINKS", function()
	local industries = { producer(1, FISH, FISHC) }
	for i = 1, 410 do industries[#industries + 1] = consumer(1000 + i, FOOD, FISHC) end
	local v = model.buildView(world(industries), model.newSelection({ FISH }), ALL, flows())
	local s = model.summary(v, model.newSelection({ FISH }))
	eq(s, { state = "links", industries = 1, total = 410, active = 0, drawn = 400, capped = true })
end)
