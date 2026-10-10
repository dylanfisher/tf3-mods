-- Industry filter (phase 7, plans/square_better_minimap/PLAN.md "Phase 7: industry filter"). PURE: no
-- api.*, unit-tested in tests/square_better_minimap/test_filter.lua. Types: minimap_types.d.tl.
--
-- A type = the industry construction's fileName (read in minimap_hud.script.tl readIndustry like
-- square_industry_flows' gather.typeOf); industries without one form the OTHER_KEY type. The selection
-- is a set of type keys; empty = show all. Name, prettify, grouping and search follow Industry Flows
-- (mods/square_industry_flows/content/industry_flows/flows_model.tl prettifyKey, displayName,
-- groupTypes, search, toggleSelected), copied because mods can't share code.
-- Lua 5.1 safe (the game runs pre-5.3 Lua).

local filter : SquareMinimapFilter = {}

filter.OTHER_KEY = "(other)"

local function trim(s : string) : string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function filter.normKey(raw : string) : string
	if raw == nil or raw == "" then return filter.OTHER_KEY end
	return raw
end

function filter.prettifyKey(key : string) : string
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

function filter.displayName(key : string, localizedName : string) : string
	if localizedName ~= nil then
		local n = trim(localizedName)
		-- An untranslated string id ("INDUSTRIES_FISHING_GROUNDS_NAME") is not a name.
		local rawId = n:find("_", 1, true) ~= nil and n:match("^[%u%d_]+$") ~= nil
		if n ~= "" and not rawId then return n end
	end
	return filter.prettifyKey(key)
end

local function sortedUnique(t : {integer}) : {integer}
	local seen : {integer : boolean} = {}
	local out : {integer} = {}
	for __, v in ipairs(t or {}) do
		if not seen[v] then
			seen[v] = true
			out[#out + 1] = v
		end
	end
	table.sort(out)
	return out
end

-- By name, case-insensitive; the Other type always last.
local function byName(a : SquareMinimapFilterType, b : SquareMinimapFilterType) : boolean
	local ao, bo = a.key == filter.OTHER_KEY, b.key == filter.OTHER_KEY
	if ao ~= bo then return bo end
	local la, lb = a.name:lower(), b.name:lower()
	if la ~= lb then return la < lb end
	return a.key < b.key
end

function filter.groupTypes(industries : {SquareMinimapIndustry}, cargoNames : {integer : string}, otherName : string) : {SquareMinimapFilterType}
	local byKey : {string : SquareMinimapFilterType} = {}
	local types : {SquareMinimapFilterType} = {}
	local names : {string : string} = {}
	for __, ind in ipairs(industries or {}) do
		local key = filter.normKey(ind.typeKey)
		local t = byKey[key]
		if t == nil then
			t = { key = key, name = "", count = 0, inputs = {}, outputs = {}, cargoNames = {} }
			byKey[key] = t
			types[#types + 1] = t
		end
		if names[key] == nil and ind.typeName ~= nil then names[key] = ind.typeName end
		t.count = t.count + 1
		for __, c in ipairs(ind.inputs or {}) do t.inputs[#t.inputs + 1] = c end
		for __, c in ipairs(ind.outputs or {}) do t.outputs[#t.outputs + 1] = c end
	end
	for __, t in ipairs(types) do
		if t.key == filter.OTHER_KEY then
			t.name = otherName or "Other"
		else
			t.name = filter.displayName(t.key, names[t.key])
		end
		t.inputs = sortedUnique(t.inputs)
		t.outputs = sortedUnique(t.outputs)
		for __, cargos in ipairs({ t.inputs, t.outputs }) do
			for __, c in ipairs(cargos) do
				local n = cargoNames ~= nil and cargoNames[c] or nil
				if n ~= nil and n ~= "" then t.cargoNames[#t.cargoNames + 1] = n end
			end
		end
	end
	table.sort(types, byName)
	return types
end

local function contains(s : string, q : string) : boolean
	return s ~= nil and s:lower():find(q, 1, true) ~= nil
end

-- A type matches on its name, its key, or the name of a cargo it consumes or produces ("fuel" finds
-- the oil refinery), as Industry Flows' search.
local function matches(t : SquareMinimapFilterType, q : string) : boolean
	if q == "" or contains(t.name, q) or contains(t.key, q) then return true end
	for __, n in ipairs(t.cargoNames or {}) do
		if contains(n, q) then return true end
	end
	return false
end

function filter.search(types : {SquareMinimapFilterType}, query : string) : {SquareMinimapFilterType}
	local q = trim(query or ""):lower()
	local out : {SquareMinimapFilterType} = {}
	for __, t in ipairs(types or {}) do
		if matches(t, q) then out[#out + 1] = t end
	end
	return out
end

function filter.isEmpty(sel : SquareMinimapFilterSel) : boolean
	for __, v in pairs(sel or {}) do
		if v then return false end
	end
	return true
end

function filter.count(sel : SquareMinimapFilterSel) : integer
	local n = 0
	for __, v in pairs(sel or {}) do
		if v then n = n + 1 end
	end
	return n
end

function filter.isVisible(key : string, sel : SquareMinimapFilterSel) : boolean
	if filter.isEmpty(sel) then return true end
	return sel[filter.normKey(key)] == true
end

local function copySel(sel : SquareMinimapFilterSel) : SquareMinimapFilterSel
	local out : SquareMinimapFilterSel = {}
	for k, v in pairs(sel or {}) do
		if v then out[k] = true end
	end
	return out
end

function filter.toggle(sel : SquareMinimapFilterSel, key : string) : SquareMinimapFilterSel
	local out = copySel(sel)
	key = filter.normKey(key)
	if out[key] then out[key] = nil else out[key] = true end
	return out
end

function filter.shiftClick(sel : SquareMinimapFilterSel, key : string) : SquareMinimapFilterSel, string
	if key ~= nil then
		key = filter.normKey(key)
		local only = filter.count(sel) == 1 and sel[key] == true
		if not only then
			return { [key] = true }, "only"
		end
	end
	return {}, "all"
end

function filter.shownCount(types : {SquareMinimapFilterType}, sel : SquareMinimapFilterSel) : integer, integer
	local shown = 0
	for __, t in ipairs(types or {}) do
		if filter.isVisible(t.key, sel) then shown = shown + 1 end
	end
	return shown, #(types or {})
end

local function sortedKeys(sel : SquareMinimapFilterSel) : {string}
	local keys : {string} = {}
	for k, v in pairs(sel or {}) do
		if v then keys[#keys + 1] = k end
	end
	table.sort(keys)
	return keys
end

function filter.same(a : SquareMinimapFilterSel, b : SquareMinimapFilterSel) : boolean
	return filter.toPrefs(a) == filter.toPrefs(b)
end

function filter.toPrefs(sel : SquareMinimapFilterSel) : string
	return table.concat(sortedKeys(sel), "|")
end

function filter.fromPrefs(raw : any) : SquareMinimapFilterSel
	local sel : SquareMinimapFilterSel = {}
	if type(raw) == "string" then
		for k in (raw as string):gmatch("[^|]+") do
			local key = trim(k)
			if key ~= "" then sel[key] = true end
		end
	elseif type(raw) == "table" then
		for __, k in ipairs(raw as {any}) do
			if type(k) == "string" and trim(k as string) ~= "" then sel[trim(k as string)] = true end
		end
	end
	return sel
end

function filter.describe(sel : SquareMinimapFilterSel) : string
	if filter.isEmpty(sel) then return "all" end
	return table.concat(sortedKeys(sel), ", ")
end

return filter
