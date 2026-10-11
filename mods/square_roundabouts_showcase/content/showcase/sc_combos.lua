-- DEV ONLY (never upload): Roundabouts Showcase, entries and combinations. Pure Lua (no api.*).
--
-- An entry model is built GENERICALLY from the construction's own param definitions (runtime:
-- api.res.constructionRep desc.params via sc_engine; offline: the .con.lua data().params), so params
-- added to square_roundabouts later are picked up without changes here:
--   entry = { id, symbol, file, name, script, captureParams,
--             params = { { key, name, n, default, labels = {...} } } }
-- TF3 construction param values are 1-based value indices (docs/wiki/modding/constructions/basics.md
-- "the return values are 1-based"; square_roundabouts_geometry.lua geom.index).
--   combo = { entry = <entry>, values = { 1-based index per param }, params = { key = index }, key = "id:1-2-1" }

local rngMod = ug_require "square_roundabouts_showcase::/showcase/sc_rng.lua"

local combos = {}

local function nonEmptyString(s) return type(s) == "string" and s ~= "" end

--- A model param list from plain param tables { key, name, values = {...}, defaultIndex }.
-- Params without a key or without values are left out.
function combos.paramsFromList(list)
	local out = {}
	for _, p in ipairs(list or {}) do
		local labels = {}
		for i, v in ipairs(p.values or {}) do labels[i] = tostring(v) end
		if nonEmptyString(p.key) and #labels > 0 then
			local d = tonumber(p.defaultIndex) or 1
			if d < 1 or d > #labels or d ~= math.floor(d) then d = 1 end
			out[#out + 1] = { key = p.key, name = tostring(p.name or p.key), n = #labels, default = d, labels = labels }
		end
	end
	return out
end

--- The entry model from an entry config ({id, symbol}) and a .con-like table
-- { description = {name}, params = {...}, updateScript = {fileName, params} } (offline, tests).
function combos.entryFromCon(base, con, file)
	local us = con.updateScript or {}
	return {
		id = base.id,
		symbol = base.symbol or "?",
		file = file or base.file,
		name = con.description and con.description.name or base.id,
		script = us.fileName,
		captureParams = us.params,
		params = combos.paramsFromList(con.params),
	}
end

local function findParam(entry, patterns, wantN)
	for _, pat in ipairs(patterns) do
		for i, p in ipairs(entry.params) do
			if p.key:find(pat, 1, true) and (wantN == nil or p.n == wantN) then return i end
		end
	end
	return nil
end

--- Index of the traffic side / ring direction param (2 values; the second value is the mirror
-- image of the first: square_roundabouts mirrors x -> -x for left-hand traffic / clockwise), or nil.
function combos.mirrorParam(entry)
	return findParam(entry, { "direction", "traffic", "side" }, 2)
end

--- Index of the "colour" param for the mosaic (island surface, else lanes), or nil.
function combos.colourParam(entry)
	return findParam(entry, { "island", "lanes" })
end

-- Visually distinct params, most distinct first (matched against the param keys).
combos.VISUAL = {
	{ "scale", "size", "radius" },
	{ "shape", "layout" },
	{ "arms" },
	{ "lanes" },
	{ "island" },
	{ "level", "highway" },
	{ "slips", "centre" },
}

--- Indices of the visually distinct params, in VISUAL order (each param once).
function combos.visualParams(entry)
	local out, seen = {}, {}
	for _, group in ipairs(combos.VISUAL) do
		for i, p in ipairs(entry.params) do
			if not seen[i] then
				for _, pat in ipairs(group) do
					if p.key:find(pat, 1, true) then
						seen[i] = true
						out[#out + 1] = i
						break
					end
				end
			end
		end
	end
	return out
end

function combos.defaults(entry)
	local v = {}
	for i, p in ipairs(entry.params) do v[i] = p.default end
	return v
end

function combos.make(entry, values)
	local params, parts = {}, {}
	for i, p in ipairs(entry.params) do
		local x = values[i] or p.default
		params[p.key] = x
		parts[i] = tostring(x)
	end
	local copy = {}
	for i = 1, #entry.params do copy[i] = values[i] or entry.params[i].default end
	return { entry = entry, values = copy, params = params, key = entry.id .. ":" .. table.concat(parts, "-") }
end

--- Short readable labels of a combo's non-default values ("Scale=L Island=Grass"), or "defaults".
function combos.describe(combo)
	local parts = {}
	for i, p in ipairs(combo.entry.params) do
		local v = combo.values[i]
		if v ~= p.default then parts[#parts + 1] = (p.name:gsub("%s", "")) .. "=" .. tostring(p.labels[v]):gsub("%s", "_") end
	end
	return #parts > 0 and table.concat(parts, " ") or "defaults"
end

--- The combo with the mirror param flipped (1 <-> 2), or nil if the entry has none.
function combos.mirrorOf(combo)
	local mi = combos.mirrorParam(combo.entry)
	if not mi then return nil end
	local v = {}
	for i, x in ipairs(combo.values) do v[i] = x end
	v[mi] = v[mi] == 1 and 2 or 1
	return combos.make(combo.entry, v)
end

-- Per-entry generators: each returns the entry's value lists in a deterministic order -----------

--- Every combination (first param varies fastest), at most `limit`.
function combos.everyOf(entry, limit)
	local out = {}
	local n = #entry.params
	if n == 0 then return { combos.defaults(entry) } end
	local v = {}
	for i = 1, n do v[i] = 1 end
	while #out < limit do
		local copy = {}
		for i = 1, n do copy[i] = v[i] end
		out[#out + 1] = copy
		local i = 1
		while i <= n do
			v[i] = v[i] + 1
			if v[i] <= entry.params[i].n then break end
			v[i] = 1
			i = i + 1
		end
		if i > n then break end
	end
	return out
end

--- Defaults, then each param's every other value (the rest at their defaults).
function combos.oneAtATimeOf(entry, indices)
	local base = combos.defaults(entry)
	local out = { base }
	local list = indices
	if not list then
		list = {}
		for i = 1, #entry.params do list[i] = i end
	end
	for _, i in ipairs(list) do
		for x = 1, entry.params[i].n do
			if x ~= base[i] then
				local v = {}
				for j, y in ipairs(base) do v[j] = y end
				v[i] = x
				out[#out + 1] = v
			end
		end
	end
	return out
end

--- Showcase: every value of each visually distinct param, the product of the two most distinct
-- ones, the second traffic side of the defaults.
function combos.showcaseOf(entry)
	local vis = combos.visualParams(entry)
	local out = combos.oneAtATimeOf(entry, vis)
	local a, b = vis[1], vis[2]
	if a and b then
		local base = combos.defaults(entry)
		for x = 1, entry.params[a].n do
			for y = 1, entry.params[b].n do
				local v = {}
				for j, z in ipairs(base) do v[j] = z end
				v[a], v[b] = x, y
				out[#out + 1] = v
			end
		end
	end
	local mi = combos.mirrorParam(entry)
	if mi then
		local v = combos.defaults(entry)
		v[mi] = v[mi] == 1 and 2 or 1
		out[#out + 1] = v
	end
	return out
end

--- Merges per-entry value lists round-robin (entry 1's first, entry 2's first, ...), dropping
-- duplicates, at most cap combos.
function combos.roundRobin(entries, lists, cap)
	local out, seen = {}, {}
	local i = 1
	local more = true
	while more and #out < cap do
		more = false
		for ei, entry in ipairs(entries) do
			local v = lists[ei][i]
			if v then
				more = true
				local c = combos.make(entry, v)
				if not seen[c.key] then
					seen[c.key] = true
					out[#out + 1] = c
					if #out >= cap then break end
				end
			end
		end
		i = i + 1
	end
	return out
end

--- Random sample: distinct combos, entries in turn, seeded.
function combos.randomOf(entries, cap, seed)
	local r = rngMod.new(seed)
	local out, seen = {}, {}
	local total = 0
	for _, e in ipairs(entries) do total = total + combos.countOf(e) end
	local want = math.min(cap, total)
	local attempts = 0
	while #out < want and attempts < want * 50 do
		attempts = attempts + 1
		local entry = entries[(attempts - 1) % #entries + 1]
		local v = {}
		for i, p in ipairs(entry.params) do v[i] = r:int(1, p.n) end
		local c = combos.make(entry, v)
		if not seen[c.key] then
			seen[c.key] = true
			out[#out + 1] = c
		end
	end
	return out
end

--- Number of combinations of an entry (capped at 1e9 so it stays exact).
function combos.countOf(entry)
	local n = 1
	for _, p in ipairs(entry.params) do
		n = n * p.n
		if n > 1e9 then return 1e9 end
	end
	return n
end

--- The combos of a run. mode = "showcase" | "every" | "one" | "random"; cap = max count.
function combos.enumerate(entries, mode, cap, seed, hardCap)
	cap = math.max(1, math.min(cap or 250, hardCap or 5000))
	if #entries == 0 then return {} end
	if mode == "random" then return combos.randomOf(entries, cap, seed) end
	local lists = {}
	for i, e in ipairs(entries) do
		if mode == "every" then
			lists[i] = combos.everyOf(e, cap)
		elseif mode == "one" then
			lists[i] = combos.oneAtATimeOf(e)
		else
			lists[i] = combos.showcaseOf(e)
		end
	end
	return combos.roundRobin(entries, lists, cap)
end

return combos
