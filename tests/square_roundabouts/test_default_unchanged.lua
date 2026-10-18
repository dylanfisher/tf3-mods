-- Default behaviour unchanged: without sqrb_dev_* params both updateFns give exactly the result
-- recorded in golden_default.lua. It was written from the Phase 3b code before the Phase 4 dev
-- overrides existed, and re-recorded on purpose in Phase 4b when the engine-tuned table was baked
-- in (its header lists what changed; golden.lua explains how to regenerate it).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local K = geom.PARAM_KEYS

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local G = loadfile(here .. "golden.lua", "t", _ENV)()
local golden = loadfile(here .. "golden_default.lua", "t", _ENV)()

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end
local main = loadData("square_roundabouts.script.lua").updateFn
local magicFn = loadData("square_roundabouts_magic.script.lua").updateFn

local function all()
	local out = {}
	local mg, mo = G.mainGroups(K)
	for _, name in ipairs(mo) do out[#out + 1] = { name, main, mg[name] } end
	local gg, go = G.magicGroups(K)
	for _, name in ipairs(go) do out[#out + 1] = { name, magicFn, gg[name] } end
	return out
end

local write = os.getenv and os.getenv("SQRB_GOLDEN_WRITE")

-- PARTS tests, each a slice of the groups (G.groupSlice: a sample in quick runs, every group with
-- --full), so the runner can shard them; SQRB_GOLDEN_WRITE prints the whole table under part 1.
local PARTS = 6
for part = 1, PARTS do
test(string.format("golden: default builds are unchanged (main + magic), part %d/%d", part, PARTS), function()
	local list = all()
	local slice = {}
	if write then
		if part > 1 then return end
		for i = 1, #list do slice[i] = i end
	else
		slice = G.groupSlice(#list, part, PARTS, 4)
	end
	local lines, bad, builds = {}, {}, 0
	for _, i in ipairs(slice) do
		local g = list[i]
		local h = G.fingerprint(g[2], g[3])
		builds = builds + #g[3]
		lines[#lines + 1] = string.format("\t[%q] = %d,", g[1], h)
		if not write and golden[g[1]] ~= h then bad[#bad + 1] = g[1] end
	end
	if write then
		print("return {\n" .. table.concat(lines, "\n") .. "\n}")
		return
	end
	if part == 1 then
		-- every recorded group is still built
		local names = {}
		for _, g in ipairs(list) do names[g[1]] = true end
		local recorded = 0
		for name in pairs(golden) do
			recorded = recorded + 1
			ok(names[name], "recorded group not built: " .. name)
		end
		eq(recorded, #list, "recorded vs built groups")
	end
	ok(#bad == 0, #bad .. " groups changed: " .. table.concat(bad, "; "))
	print(string.format("    %d of %d groups, %d builds", #slice, #list, builds))
end)
end

test("golden: unrelated and empty dev keys change nothing", function()
	local base = { [K.arms] = 3, [K.splitter] = 2, [K.armType] = 3, [K.centre] = 3 }
	local ref = table.concat(G.serialize(main({}, base)))
	local noisy = {}
	for k, v in pairs(base) do noisy[k] = v end
	noisy.sqrb_dev_unknown = 5
	noisy.sqrb_dev_radius = "not a number"
	noisy.sqrb_dev_fork = -1 -- out of range: ignored
	noisy.height = 0
	eq(table.concat(G.serialize(main({}, noisy))), ref)
end)
