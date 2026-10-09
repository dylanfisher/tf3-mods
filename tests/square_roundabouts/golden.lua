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

return G
