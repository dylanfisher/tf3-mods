-- Golden fingerprints of the default build (no dev overrides, the shipped tuning table), loaded
-- with loadfile like checks.lua. test_default_unchanged.lua compares every group against
-- golden_default.lua, written from the Phase 3b code BEFORE the Phase 4 dev overrides existed and
-- re-recorded on purpose in Phase 4b (engine data baked in): so the shipped behaviour changes only
-- when a change is meant to.
--
-- Regenerate only on purpose (a deliberate geometry change):
--   SQRB_GOLDEN_WRITE=1 uv run tests/run_tests.py -k golden mods/square_roundabouts
-- prints the new table; paste it into golden_default.lua.

local G = {}

local function fmt(v)
	if type(v) == "number" then
		local s = string.format("%.4f", v)
		if s == "-0.0000" then s = "0.0000" end
		return s
	end
	return tostring(v)
end

--- Deterministic text of any value (sorted keys, numbers rounded to 1e-4).
function G.serialize(v, out)
	out = out or {}
	if type(v) ~= "table" then
		out[#out + 1] = fmt(v)
		return out
	end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) < type(b)
	end)
	out[#out + 1] = "{"
	for _, k in ipairs(keys) do
		out[#out + 1] = tostring(k) .. "="
		G.serialize(v[k], out)
		out[#out + 1] = ","
	end
	out[#out + 1] = "}"
	return out
end

--- Polynomial string hash (mod 2^31 - 1, plain arithmetic: no bit ops).
function G.hash(s, h)
	h = h or 7
	local M = 2147483647
	for i = 1, #s do
		h = (h * 131 + s:byte(i)) % M
	end
	return h
end

--- The main-entry param grid of the fingerprint, as groups: name -> list of param tables.
-- Product of shape {round, 1.5, 2}, lanes, radius {8, 20, 60}, arms {T, Y, 5, none},
-- splitter, centre, arm road {town s, town l, country m}, tram; direction and island alternate.
function G.mainGroups(K)
	local groups, order = {}, {}
	local n = 0
	for _, arms in ipairs({ 1, 2, 4, 6 }) do
		for splitter = 1, 2 do
			for centre = 1, 3 do
				for tram = 1, 2 do
					local name = string.format("main a%d s%d c%d t%d", arms, splitter, centre, tram)
					local list = {}
					for _, shape in ipairs({ 1, 3, 5 }) do
						for lanes = 1, 3 do
							for _, radius in ipairs({ 1, 5, 13 }) do
								for _, armType in ipairs({ 1, 3, 5 }) do
									n = n + 1
									list[#list + 1] = {
										[K.shape] = shape, [K.lanes] = lanes, [K.radius] = radius, [K.arms] = arms,
										[K.splitter] = splitter, [K.centre] = centre, [K.armType] = armType, [K.tram] = tram,
										[K.direction] = n % 2 + 1, [K.island] = (n % 5) + 1, [K.signals] = (n % 3 == 0) and 2 or 1,
									}
								end
							end
						end
					end
					groups[name] = list
					order[#order + 1] = name
				end
			end
		end
	end
	return groups, order
end

--- Magic: every size x arm road x direction, island alternating.
function G.magicGroups(K)
	local groups, order = {}, {}
	for size = 1, 5 do
		local name = "magic size" .. size
		local list = {}
		for armType = 1, 6 do
			for dir = 1, 2 do
				list[#list + 1] = { sqrb_magic_size = size, [K.armType] = armType, [K.direction] = dir, [K.island] = (armType + dir) % 5 + 1 }
			end
		end
		groups[name] = list
		order[#order + 1] = name
	end
	return groups, order
end

--- Fingerprint of a list of params through an updateFn.
function G.fingerprint(updateFn, list)
	local h = 7
	for _, p in ipairs(list) do
		h = G.hash(table.concat(G.serialize(updateFn({}, p))), h)
	end
	return h
end

--- Like G.serialize, but numbers exact ("%.17g": every bit, -0 kept): a refactor that changes a
-- last bit shows up (INTERCHANGES.md Phase 7a).
function G.serializeExact(v, out)
	out = out or {}
	if type(v) ~= "table" then
		out[#out + 1] = type(v) == "number" and string.format("%.17g", v) or tostring(v)
		return out
	end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) < type(b)
	end)
	out[#out + 1] = "{"
	for _, k in ipairs(keys) do
		out[#out + 1] = tostring(k) .. "="
		G.serializeExact(v[k], out)
		out[#out + 1] = ","
	end
	out[#out + 1] = "}"
	return out
end

--- Rounded and exact fingerprints of a list of params through an updateFn (one build each).
function G.fingerprints(updateFn, list)
	local h, hx = 7, 7
	for _, p in ipairs(list) do
		local res = updateFn({}, p)
		h = G.hash(table.concat(G.serialize(res)), h)
		hx = G.hash(table.concat(G.serializeExact(res)), hx)
	end
	return h, hx
end

local function range(n) local t = {}; for i = 1, n do t[i] = i end; return t end
G.range = range

--- Calls fn(params) for the cartesian product of the value lists in grid (keys are param keys,
-- visited in sorted key order; fn gets a fresh copy).
function G.each(grid, fn)
	local keys = {}
	for k in pairs(grid) do keys[#keys + 1] = k end
	table.sort(keys)
	local function rec(i, p)
		if i > #keys then
			local copy = {}
			for k, v in pairs(p) do copy[k] = v end
			return fn(copy)
		end
		for _, v in ipairs(grid[keys[i]]) do
			p[keys[i]] = v
			rec(i + 1, p)
		end
	end
	rec(1, {})
end

--- Channelized junction shipped sweep (test_short_edges.lua): every value of every param
-- (Islands None / Paved: Grass has the same roads). ch = square_roundabouts_channel.lua.
function G.channelSweep(ch, geom, fn)
	local CK = ch.PARAM_KEYS
	G.each({
		[CK.layout] = { 1, 2 }, [CK.main] = range(#geom.ARM_TEMPLATES), [CK.side] = range(#geom.ARM_TEMPLATES),
		[CK.slips] = { 1, 2, 3 }, [CK.splitter] = { 1, 2 }, [CK.armLength] = range(#ch.ARM_LENGTHS),
		[CK.direction] = { 1, 2 }, [CK.island] = { 1, 3 },
	}, fn)
end

--- Roundabout interchange shipped sweep (test_short_edges.lua): every layout x highway x level x
-- lanes x traffic side, the extreme radii, four cross roads, the shortest and longest slip roads,
-- Centre island None / Fountain; params.year = year (nil: no year key). ix = square_roundabouts_interchange.lua.
function G.interchangeSweep(ix, year, fn)
	local IK = ix.PARAM_KEYS
	G.each({
		[IK.layout] = { 1, 2, 3 }, [IK.highway] = range(#ix.HIGHWAYS), [IK.level] = { 1, 2 },
		[IK.lanes] = { 1, 2, 3 }, [IK.direction] = { 1, 2 }, [IK.radius] = { 1, #ix.RADII },
		[IK.cross] = { 1, 3, 4, 6 }, [IK.slipLength] = { 1, #ix.SLIP_LENGTHS },
		[IK.armLength] = { 1 }, [IK.island] = { 1, 4 },
	}, function(p)
		p.year = year
		fn(p)
	end)
end

--- Highway Interchange shipped sweep (test_short_edges.lua; INTERCHANGES.md Phase 7b): every type x
-- highway x level x traffic side x Size, four cross roads (town small / large, country small /
-- large), the shortest and longest ramp length; params.year = year (nil: no year key).
-- hx = square_roundabouts_highway.lua.
function G.highwaySweep(hx, year, fn)
	local HK = hx.PARAM_KEYS
	G.each({
		[HK.type] = range(#hx.TYPES), [HK.highway] = { 1, 2, 3 }, [HK.level] = { 1, 2 }, [HK.direction] = { 1, 2 },
		[HK.size] = range(#hx.LOOP_RADII), [HK.cross] = { 1, 3, 4, 6 }, [HK.rampLength] = { 1, #hx.RAMP_EXTRAS },
		[HK.armLength] = { 1 },
	}, function(p)
		p.year = year
		fn(p)
	end)
end

--- Golden groups of one entry over its shipped sweep: "channel" (layout x main road),
-- "interchange" (layout x highway x level x year 1969 / none) or "highway" (type x highway x level x
-- year 1969 / none). mod = that entry's geometry module.
function G.entryGroups(entry, mod, geom)
	local groups, order = {}, {}
	local function put(name, p)
		if not groups[name] then groups[name] = {}; order[#order + 1] = name end
		local l = groups[name]
		l[#l + 1] = p
	end
	local K = mod.PARAM_KEYS
	if entry == "channel" then
		G.channelSweep(mod, geom, function(p)
			put(string.format("channel l%d m%d", p[K.layout], p[K.main]), p)
		end)
	elseif entry == "highway" then
		for _, year in ipairs({ 1969, false }) do
			G.highwaySweep(mod, year or nil, function(p)
				put(string.format("highway t%d h%d v%d y%s", p[K.type], p[K.highway], p[K.level], year or "none"), p)
			end)
		end
	else
		for _, year in ipairs({ 1969, false }) do
			G.interchangeSweep(mod, year or nil, function(p)
				put(string.format("interchange l%d h%d v%d y%s", p[K.layout], p[K.highway], p[K.level], year or "none"), p)
			end)
		end
	end
	return groups, order
end

--- Registers the golden test of one entry (test_entries_unchanged_<entry>.lua): every group's
-- rounded and exact fingerprint equals golden_entries.lua, and every recorded group of the entry
-- is still swept. SQRB_GOLDEN_WRITE=1 prints the lines instead.
function G.entryTest(entry, mod, geom, updateFn, golden, parts)
	-- `parts` tests (default 3), each a contiguous slice of the groups, so the runner can shard
	-- them; SQRB_GOLDEN_WRITE prints each slice's lines under its test, in order
	parts = parts or 3
	local write = os.getenv and os.getenv("SQRB_GOLDEN_WRITE")
	for part = 1, parts do
		test(string.format("entries golden: %s builds unchanged (rounded and exact), part %d/%d", entry, part, parts), function()
			local groups, order = G.entryGroups(entry, mod, geom)
			local per = math.ceil(#order / parts)
			local first, last = (part - 1) * per + 1, math.min(#order, part * per)
			local lines, bad, builds = {}, {}, 0
			for i = first, last do
				local name = order[i]
				local h, hx = G.fingerprints(updateFn, groups[name])
				builds = builds + #groups[name]
				lines[#lines + 1] = string.format("\t[%q] = { %d, %d },", name, h, hx)
				local g = golden[name]
				if not write then
					if not g or g[1] ~= h then bad[#bad + 1] = name .. " (rounded)"
					elseif g[2] ~= hx then bad[#bad + 1] = name .. " (exact)" end
				end
			end
			if write then
				print(table.concat(lines, "\n"))
				return
			end
			if part == 1 then
				local recorded = 0
				for name in pairs(golden) do
					if name:sub(1, #entry + 1) == entry .. " " then
						recorded = recorded + 1
						ok(groups[name] ~= nil, "recorded group not swept: " .. name)
					end
				end
				eq(recorded, #order, "recorded vs swept groups")
			end
			ok(#bad == 0, #bad .. " groups changed: " .. table.concat(bad, "; "))
			print(string.format("    groups %d-%d of %d, %d builds", first, last, #order, builds))
		end)
	end
end

return G
