-- Structure = Embankment (sqrb_structure = 1, the default; square_roundabouts_result.lua "Structure")
-- builds exactly what every entry built before the param existed: each golden group, with
-- sqrb_structure = 1 added to every param table, gives the recorded fingerprints (golden_default.lua:
-- main + Magic, rounded; golden_entries.lua: Channelized Junction, Roundabout Interchange, Highway
-- Interchanges, rounded and exact). Without the key the test_default_unchanged / test_entries_unchanged_*
-- files already check it. Quick runs compare a sample of the groups (G.groupSlice), --full every group.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local result = ug_require(DIR .. "square_roundabouts_result.lua")
local K = geom.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local G = loadfile(here .. "golden.lua", "t", _ENV)()
local goldenDefault = loadfile(here .. "golden_default.lua", "t", _ENV)()
local goldenEntries = loadfile(here .. "golden_entries.lua", "t", _ENV)()

local function updateFnOf(file)
	ug_require(DIR .. file)
	local fn = data().updateFn
	-- every build with Structure = Embankment
	return function(c, p)
		local q = {}
		for k, v in pairs(p) do q[k] = v end
		q[result.STRUCTURE_KEY] = result.STRUCTURE_EMBANKMENT
		return fn(c, q)
	end
end

local main = updateFnOf("square_roundabouts.script.lua")
local magicFn = updateFnOf("square_roundabouts_magic.script.lua")
local ENTRIES = {
	channel = { mod = ug_require(DIR .. "square_roundabouts_channel.lua"), fn = updateFnOf("square_roundabouts_channel.script.lua") },
	interchange = { mod = ug_require(DIR .. "square_roundabouts_interchange.lua"), fn = updateFnOf("square_roundabouts_interchange.script.lua") },
	highway = { mod = ug_require(DIR .. "square_roundabouts_highway.lua"), fn = updateFnOf("square_roundabouts_highway.script.lua") },
}

local STRIDE = 8

local function defaultGroups()
	local out = {}
	local mg, mo = G.mainGroups(K)
	for _, name in ipairs(mo) do out[#out + 1] = { name, main, mg[name] } end
	local gg, go = G.magicGroups(K)
	for _, name in ipairs(go) do out[#out + 1] = { name, magicFn, gg[name] } end
	return out
end

-- more parts with --full so each test stays well under 8 s (the runner shards by test)
local FULL = os.getenv and os.getenv("TEST_FULL") and true or false
local PARTS = FULL and 8 or 3
for part = 1, PARTS do
	test(string.format("Embankment = golden: main + magic, part %d/%d", part, PARTS), function()
		local list = defaultGroups()
		local bad, builds = {}, 0
		local slice = G.groupSlice(#list, part, PARTS, STRIDE)
		for _, i in ipairs(slice) do
			local g = list[i]
			builds = builds + #g[3]
			if goldenDefault[g[1]] ~= G.fingerprint(g[2], g[3]) then bad[#bad + 1] = g[1] end
		end
		ok(#bad == 0, #bad .. " groups changed: " .. table.concat(bad, "; "))
		print(string.format("    %d groups, %d builds", #slice, builds))
	end)
end

for _, entry in ipairs({ "channel", "interchange", "highway" }) do
	local e = ENTRIES[entry]
	for part = 1, PARTS do
		test(string.format("Embankment = golden: %s, part %d/%d", entry, part, PARTS), function()
			local groups, order = G.entryGroups(entry, e.mod, geom)
			local bad, builds = {}, 0
			local slice = G.groupSlice(#order, part, PARTS, STRIDE)
			for _, i in ipairs(slice) do
				local name = order[i]
				local h, hx = G.fingerprints(e.fn, groups[name])
				builds = builds + #groups[name]
				local g = goldenEntries[name]
				if not g or g[1] ~= h then bad[#bad + 1] = name .. " (rounded)"
				elseif g[2] ~= hx then bad[#bad + 1] = name .. " (exact)" end
			end
			ok(#bad == 0, #bad .. " groups changed: " .. table.concat(bad, "; "))
			print(string.format("    %d groups, %d builds", #slice, builds))
		end)
	end
end
