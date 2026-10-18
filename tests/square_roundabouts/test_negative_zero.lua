-- No tangent in any entry's construction result that stays -0 in world space (docs/findings.md "Negative zero in construction
-- geometry"; PHASE7_RUNBOOK.md "Debugging in-game refusals"). The UI builder's 0-degree transf
-- keeps a -0 tangent in world space and the engine then refuses the whole layout ("Construction
-- Not Possible") at exactly Rotation 0; the probe's +0 identity transf and the goldens (G.serialize
-- prints -0 as 0) both hide it. Shipped params, each entry's real updateFn.
-- KNOWN: entries whose released output still has -0 (count over the sweep): the test fails if the
-- count grows or the entry becomes clean (then drop it from KNOWN). Fix = normalise like
-- square_roundabouts_highway.lua hx.positiveZeros.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local magic = ug_require(DIR .. "square_roundabouts_magic.lua")
local channel = ug_require(DIR .. "square_roundabouts_channel.lua")
local interchange = ug_require(DIR .. "square_roundabouts_interchange.lua")
local highway = ug_require(DIR .. "square_roundabouts_highway.lua")

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local checks = loadfile(here .. "checks.lua", "t", _ENV)()
local G = loadfile(here .. "golden.lua", "t", _ENV)()

local function loadData(file)
	ug_require(DIR .. file)
	return data()
end

local function groupsSweep(groups, order)
	return function(fn)
		for _, name in ipairs(order) do
			for _, p in ipairs(groups[name]) do fn(p) end
		end
	end
end

-- Every 7th build of each sweep (test_finite's --full stride), quick and --full alike (a few s);
-- SQRB_FULL=1 checks every build.
local STRIDE = (os.getenv and os.getenv("SQRB_FULL")) and 1 or 7

-- Released entries with world -0 tangents, left as they are. channel: layout 2 with left-hand
-- traffic, side-road tangents (-0, -y) -> world x -0. Engine-checked (probe p7_presets, 2026-10-09,
-- at the builder's exact 0-degree transf): all 6 X left-hand combos placed, so a world -0 in a
-- tangent's x did not refuse; the refused highway case had -0 in y (docs/findings.md "Negative
-- zero"). Which components matter is unclear: new geometry still normalises (hx.positiveZeros).
-- Lua 5.4 integers hide part of it: `-x` of an integer 0 stays +0 here but is -0 in the game's
-- pre-5.3 Lua (doubles only). `TEALRT_LUA=52 make test ... ARGS="-f negative_zero"` gives the game's count
-- (layout 2 left-hand: every build); the default 5.4 run under-reports.
local LUA52 = _VERSION == "Lua 5.2"
local KNOWN = { channel = STRIDE == 1 and (LUA52 and 1728 or 1152) or (LUA52 and 247 or 164) }

local ENTRIES = {
	{ name = "main", script = "square_roundabouts.script.lua", sweep = groupsSweep(G.mainGroups(geom.PARAM_KEYS)) },
	{ name = "magic", script = "square_roundabouts_magic.script.lua", sweep = groupsSweep(G.magicGroups(magic.PARAM_KEYS)) },
	{ name = "channel", script = "square_roundabouts_channel.script.lua", sweep = function(fn) G.channelSweep(channel, geom, fn) end },
	{ name = "interchange", script = "square_roundabouts_interchange.script.lua", sweep = function(fn) G.interchangeSweep(interchange, 1969, fn) end },
	{ name = "highway", script = "square_roundabouts_highway.script.lua", sweep = function(fn) G.highwaySweep(highway, 1969, fn) end },
}

for _, entry in ipairs(ENTRIES) do
	test(entry.name .. ": no tangent that stays -0 under the builder's 0-degree transf (UI refusal)", function()
		local updateFn = loadData(entry.script).updateFn
		local builds, bad, total, rawBuilds, first = 0, 0, 0, 0, nil
		local seen = 0
		entry.sweep(function(p)
			seen = seen + 1
			if (seen - 1) % STRIDE ~= 0 then return end
			builds = builds + 1
			local problems, n, raw = checks.negativeZeros(updateFn({}, p))
			if raw > 0 then rawBuilds = rawBuilds + 1 end
			if n > 0 then
				bad, total = bad + 1, total + n
				if not first then
					local keys = {}
					for k, v in pairs(p) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
					table.sort(keys)
					first = table.concat(keys, " ") .. ": " .. table.concat(problems, "; ", 1, math.min(3, n))
				end
			end
		end)
		print(string.format("    %d builds, %d with a world -0 tangent at 0 deg (%d edges), %d with any raw -0%s",
			builds, bad, total, rawBuilds, first and ("; first: " .. first) or ""))
		ok(builds > 0)
		eq(bad, KNOWN[entry.name] or 0, entry.name .. " builds with a world -0 tangent" .. (first and (" (first: " .. first .. ")") or ""))
	end)
end

test("negativeZeros: (+x, -0) and (-0, -y) tangents stay -0 in world space; (-x, -0), z = -0 and +0 do not", function()
	local z = 0.0
	local n0 = -z
	local function count(p, t)
		local _, n, raw = checks.negativeZeros({ edgeLists = { { params = { type = "x" }, edges = { { p, t } } } } })
		return n .. "/" .. raw
	end
	eq(count({ 0, 0, 0 }, { 5, 0, 0 }), "0/0")
	eq(count({ n0, 0, 0 }, { 5, 0, n0 }), "0/2")
	eq(count({ 0, 0, 0 }, { 5, n0, 0 }), "1/1") -- the Phase 7e SE on-ramp: world y = (-0)(+x) + (-0)
	eq(count({ 0, 0, 0 }, { -5, n0, 0 }), "0/1") -- world y = (-0)(-x) + (-0) = +0
	eq(count({ 0, 0, 0 }, { n0, -5, 0 }), "1/1") -- world x = (-0) - (-0)(-y) = -0
end)
