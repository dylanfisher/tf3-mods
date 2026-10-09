-- Industry Flows model (PLAN phase 2). PURE: no api.*, no base modules, so it is unit-tested offline
-- (tests/square_industry_flows/test_model.lua). flows_gather.tl reads the engine into plain records
-- (IndustryFlowsWorld, industry_flows_types.d.tl); this module groups and searches industry types,
-- keeps the selection set and builds the arrow links for every industry of the selected types.
--
-- Link rules are the base industry window's (.cache/game/base/content/gui/entity_window/industry/
-- industry.tl:195-247), re-implemented so the counterpart lists are built once per poll instead of
-- once per selected industry:
--   * inputs:  every industry with an OutputStock of a cargo the selected one consumes
--              (industry_util.forEachMatchingStocklist, InputStock; industry_util.tl:603-647)
--   * outputs: every industry with an InputStock of a cargo the selected one produces (OutputStock)
--   * towns:   per town, its first need the selected industry produces
--              (town_util.forEachMatchingStocklist, town_util.tl:1883-1909)
--   * active:  flowCount(from, to, cargo, toTown) > 0 (cargo_util.getCargoFlowCount, cargo_util.tl:976-986)
-- Lua 5.1 safe (the game runs pre-5.3 Lua): no integer division, math.type or utf8.

local model : IndustryFlowsModel = {}

-- Cap on rendered arrows. Active links are kept first.
model.MAX_LINKS = 400

local function list<T>(t : {T}) : {T}
	return t or {}
end

local function trim(s : string) : string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Sorted copy of an integer list without duplicates.
local function sortedUnique(t : {integer}) : {integer}
	local seen : {integer : boolean} = {}
	local out : {integer} = {}
	for __, v in ipairs(list(t)) do
		if not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	table.sort(out)
	return out
end

function model.prettifyKey(key : string) : string
	if key == nil or key == "" then return "" end
	-- Last path segment ("::/industries/farm/farm.con" -> "farm.con"), then drop the extension(s).
	local base = key:match("([^/:]+)$") or key
	base = base:match("^([^%.]*)") or base
	base = trim((base:gsub("[_%-]+", " "):gsub("%s+", " ")))
	if base == "" then return key end
	return (base:gsub("(%S)(%S*)", function(first : string, rest : string) : string
		return first:upper() .. rest
	end))
end

function model.displayName(key : string, localizedName : string) : string
	if localizedName ~= nil then
		local n = trim(localizedName)
		-- An untranslated string id ("INDUSTRIES_FISHING_GROUNDS_NAME") is not a name.
		local rawId = n:find("_", 1, true) ~= nil and n:match("^[%u%d_]+$") ~= nil
		if n ~= "" and not rawId then return n end
	end
	return model.prettifyKey(key)
end

local function byName(a : IndustryFlowsType, b : IndustryFlowsType) : boolean
	local la, lb = a.name:lower(), b.name:lower()
	if la ~= lb then return la < lb end
	return a.key < b.key
end

function model.groupTypes(world : IndustryFlowsWorld) : {IndustryFlowsType}
	local byKey : {string : IndustryFlowsType} = {}
	local types : {IndustryFlowsType} = {}
	local names = world and world.typeNames or {}
	local cargoNames = world and world.cargoNames or {}
	for __, ind in ipairs(list(world and world.industries)) do
		local key = ind.typeKey
		if key ~= nil and key ~= "" then
			local t = byKey[key]
			if t == nil then
				t = { key = key, name = model.displayName(key, names[key]), count = 0, entities = {}, inputs = {}, outputs = {}, cargoNames = {} }
				byKey[key] = t
				types[#types + 1] = t
			end
			t.count = t.count + 1
			t.entities[#t.entities + 1] = ind.entity
			-- Collected with duplicates here; sortedUnique below makes the union.
			for __, c in ipairs(list(ind.inputs)) do t.inputs[#t.inputs + 1] = c end
			for __, c in ipairs(list(ind.outputs)) do t.outputs[#t.outputs + 1] = c end
		end
	end
	for __, t in ipairs(types) do
		table.sort(t.entities)
		t.inputs = sortedUnique(t.inputs)
		t.outputs = sortedUnique(t.outputs)
		for __, cargos in ipairs({ t.inputs, t.outputs }) do
			for __, c in ipairs(cargos) do
				local n = cargoNames[c]
				if n ~= nil and n ~= "" then t.cargoNames[#t.cargoNames + 1] = n end
			end
		end
	end
	table.sort(types, byName)
	return types
end

local function contains(s : string, q : string) : boolean
	return s:lower():find(q, 1, true) ~= nil
end

-- A type matches on its name, its key, or the name of a cargo it consumes or produces ("fuel" finds
-- the oil refinery).
local function matches(t : IndustryFlowsType, q : string) : boolean
	if q == "" or contains(t.name, q) or contains(t.key, q) then return true end
	for __, n in ipairs(list(t.cargoNames)) do
		if contains(n, q) then return true end
	end
	return false
end

function model.search(types : {IndustryFlowsType}, query : string) : {IndustryFlowsType}
	local q = trim(query or ""):lower()
	local out : {IndustryFlowsType} = {}
	for __, t in ipairs(list(types)) do
		if matches(t, q) then out[#out + 1] = t end
	end
	table.sort(out, byName)
	return out
end

function model.newSelection(keys? : {string}) : {string : boolean}
	local sel : {string : boolean} = {}
	for __, k in ipairs(list(keys)) do sel[k] = true end
	return sel
end

function model.toggleSelected(selection : {string : boolean}, key : string) : {string : boolean}
	local sel : {string : boolean} = {}
	for k, v in pairs(selection or {}) do
		if v then sel[k] = true end
	end
	if sel[key] then sel[key] = nil else sel[key] = true end
	return sel
end

local function hasSelection(selection : {string : boolean}) : boolean
	for __, v in pairs(selection or {}) do
		if v then return true end
	end
	return false
end

function model.selectedKeys(selection : {string : boolean}) : {string}
	local keys : {string} = {}
	for k, v in pairs(selection or {}) do
		if v then keys[#keys + 1] = k end
	end
	table.sort(keys)
	return keys
end

function model.defaultToggles() : IndustryFlowsToggles
	return { inputs = true, outputs = true, potential = true }
end

local function copyToggles(toggles : IndustryFlowsToggles) : IndustryFlowsToggles
	local t = toggles or model.defaultToggles()
	return { inputs = t.inputs, outputs = t.outputs, potential = t.potential }
end

function model.withToggle(toggles : IndustryFlowsToggles, name : string, on : boolean) : IndustryFlowsToggles
	local out = copyToggles(toggles)
	if name == "inputs" then
		out.inputs = on
	elseif name == "outputs" then
		out.outputs = on
	elseif name == "potential" then
		out.potential = on
	end
	return out
end

---------------------------------------------------------------------------
-- Panel (phase 3): session state, type list rows, summary inputs.

function model.newPanelState() : IndustryFlowsPanelState
	return { query = "", selection = model.newSelection(), toggles = model.defaultToggles() }
end

function model.copyPanelState(state : IndustryFlowsPanelState) : IndustryFlowsPanelState
	if state == nil then return model.newPanelState() end
	return {
		query = state.query or "",
		selection = model.newSelection(model.selectedKeys(state.selection)),
		toggles = copyToggles(state.toggles),
	}
end

function model.typeList(types : {IndustryFlowsType}, query : string, selection : {string : boolean}) : IndustryFlowsTypeList
	local keys = model.selectedKeys(selection)
	local sel = model.newSelection(keys)
	local out : IndustryFlowsTypeList = { rows = {}, selectedCount = #keys, hiddenSelected = 0 }
	local shownSelected = 0
	for __, t in ipairs(model.search(types, query)) do
		local selected = sel[t.key] == true
		if selected then shownSelected = shownSelected + 1 end
		out.rows[#out.rows + 1] = {
			key = t.key, name = t.name, count = t.count, inputs = t.inputs, outputs = t.outputs, selected = selected,
		}
	end
	out.hiddenSelected = #keys - shownSelected
	return out
end

function model.summary(view : IndustryFlowsView, selection : {string : boolean}) : IndustryFlowsSummary
	local s : IndustryFlowsSummary = { state = "empty", industries = 0, total = 0, active = 0, drawn = 0, capped = false }
	if not hasSelection(selection) then return s end
	if view == nil then
		s.state = "loading"
		return s
	end
	s.industries = view.industries or 0
	if s.industries == 0 then
		s.state = "none"
		return s
	end
	s.state = "links"
	s.total = view.total or 0
	s.active = view.active or 0
	s.drawn = view.drawn or 0
	s.capped = s.drawn < s.total
	return s
end

-- Active first, then a stable total order (from, to, cargo is unique after de-duplication), so an
-- unchanged map gives an equal view and useStepStateTimer does not re-render.
local function linkOrder(a : IndustryFlowsLink, b : IndustryFlowsLink) : boolean
	if a.active ~= b.active then return a.active end
	if a.fromEntity ~= b.fromEntity then return a.fromEntity < b.fromEntity end
	if a.toEntity ~= b.toEntity then return a.toEntity < b.toEntity end
	return a.cargo < b.cargo
end

local function byEntity(a : IndustryFlowsIndustry, b : IndustryFlowsIndustry) : boolean
	return a.entity < b.entity
end

local function townByEntity(a : IndustryFlowsTown, b : IndustryFlowsTown) : boolean
	return a.entity < b.entity
end

local function hasPos(p : {number}) : boolean
	return p ~= nil and p[1] ~= nil and p[2] ~= nil and p[3] ~= nil
end

function model.buildView(world : IndustryFlowsWorld, selection : {string : boolean}, toggles : IndustryFlowsToggles, flowCount : IndustryFlowsFlowCountFn) : IndustryFlowsView
	local view : IndustryFlowsView = {
		typeKeys = model.selectedKeys(selection), industries = 0, links = {}, total = 0, active = 0, drawn = 0,
	}
	if #view.typeKeys == 0 or world == nil then return view end
	toggles = toggles or model.defaultToggles()
	local sel = model.newSelection(view.typeKeys)

	-- One pass: selected industries, positions, and who has an input / output stock of each cargo.
	local industries : {IndustryFlowsIndustry} = {}
	for __, ind in ipairs(list(world.industries)) do industries[#industries + 1] = ind end
	table.sort(industries, byEntity)
	local selected : {IndustryFlowsIndustry} = {}
	local positions : {integer : {number}} = {}
	local withInputStock : {integer : {integer}} = {}   -- cargo -> industries that accept it
	local withOutputStock : {integer : {integer}} = {}  -- cargo -> industries that produce it
	for __, ind in ipairs(industries) do
		if ind.typeKey ~= nil and ind.typeKey ~= "" and sel[ind.typeKey] then
			selected[#selected + 1] = ind
		end
		positions[ind.entity] = ind.pos
		for __, c in ipairs(sortedUnique(ind.inputStocks)) do
			local l = withInputStock[c] or {}
			l[#l + 1] = ind.entity
			withInputStock[c] = l
		end
		for __, c in ipairs(sortedUnique(ind.outputStocks)) do
			local l = withOutputStock[c] or {}
			l[#l + 1] = ind.entity
			withOutputStock[c] = l
		end
	end
	view.industries = #selected
	if #selected == 0 or not (toggles.inputs or toggles.outputs) then return view end

	local towns : {IndustryFlowsTown} = {}
	if toggles.outputs then
		for __, t in ipairs(list(world.towns)) do
			towns[#towns + 1] = t
			positions[t.entity] = t.pos
		end
		table.sort(towns, townByEntity)
	end

	local links : {IndustryFlowsLink} = {}
	local seen : {string : boolean} = {}
	local function add(from : integer, to : integer, cargo : integer, input : boolean, toTown : boolean)
		if from == to then return end
		-- Two selected industries can see the same link (one as output, one as input): keep the first.
		local key = tostring(from) .. ">" .. tostring(to) .. ":" .. tostring(cargo)
		if seen[key] then return end
		seen[key] = true
		local pf, pt = positions[from], positions[to]
		if not hasPos(pf) or not hasPos(pt) then return end
		local count = flowCount and flowCount(from, to, cargo, toTown) or 0
		local active = count ~= nil and count > 0
		if not active and not toggles.potential then return end
		links[#links + 1] = {
			fromEntity = from, toEntity = to,
			from = { pf[1], pf[2], pf[3] }, to = { pt[1], pt[2], pt[3] },
			cargo = cargo, input = input, toTown = toTown, active = active,
		}
	end

	for __, s in ipairs(selected) do
		if toggles.inputs then
			for __, c in ipairs(sortedUnique(s.inputs)) do
				for __, supplier in ipairs(withOutputStock[c] or {}) do
					add(supplier, s.entity, c, true, false)
				end
			end
		end
		if toggles.outputs then
			local outputs = sortedUnique(s.outputs)
			local produces : {integer : boolean} = {}
			for __, c in ipairs(outputs) do
				produces[c] = true
				for __, consumer in ipairs(withInputStock[c] or {}) do
					add(s.entity, consumer, c, false, false)
				end
			end
			for __, town in ipairs(towns) do
				for __, c in ipairs(list(town.needs)) do
					if produces[c] then
						add(s.entity, town.entity, c, false, true)
						break
					end
				end
			end
		end
	end

	table.sort(links, linkOrder)
	view.total = #links
	for __, l in ipairs(links) do
		if l.active then view.active = view.active + 1 end
		if #view.links < model.MAX_LINKS then view.links[#view.links + 1] = l end
	end
	view.drawn = #view.links
	return view
end

return model
