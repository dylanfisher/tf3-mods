-- Motifs on real-world terrain values (final-test round 2026-10-13, session 2026-10-13_0856_sqot-dev: on a hilly coastal
-- EU map at 1900 only 2 of 16 towns drew a motif: the eligibility had been calibrated on steep synthetic fixtures (grades
-- 0.06-0.09) while the real towns read grade 0.01-0.05, water 250-575 m from the centre, no country roads on that map). Sites
-- modelled on the logged values (with virtual roads toward a neighbour, ot_roads.virtual); most towns there should get
-- at least one fitting drawn motif (target 60-80 %; offline ~90 % with the virtual-road ribbons and greens).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
local PT = ug_require(F.DIR .. "ot_motif_point.lua")
local RDS = ug_require(F.DIR .. "ot_roads.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")

local EU = "::/names/europe/europe.names"

-- gentle undulation on top of a site (real terrain is never a plane)
local function bumpy(fn)
	return function(x, y) return fn(x, y) + 3 * math.sin(x / 170) * math.cos(y / 210) end
end

local SITES = {
	-- a hillside like most of the map's towns: grade ~0.03, range ~40 m in the 600 m disc
	hillside = T.sampler(bumpy(function(x, y) return 60 + 0.03 * x end)),
	-- Wirksworth: grade 0.048, range ~100 m
	steepish = T.sampler(bumpy(function(x, y) return 60 + 0.048 * x + 0.01 * y end)),
	-- Stratford: mountain foothills, grade ~0.06 rising to a mountain
	foothills = T.sampler(bumpy(function(x, y) return 40 + 0.04 * x + 0.00006 * math.max(0, x) ^ 2 end)),
	-- a soft valley: both sides ~10-15 m higher at 150-450 m
	valley = T.sampler(bumpy(function(x, y) return 20 + 0.00012 * y * y + 0.004 * x end)),
	-- a lake / sea shore 450 m from the centre, the land falling 2.5 % toward it
	coast450 = T.sampler(function(x, y)
		if x > 450 then return -3 end
		return 2 + (450 - x) * 0.025 + 2 * math.sin(y / 150)
	end),
	-- a bay 520 m out
	bay = T.sampler(function(x, y)
		local d = math.sqrt((x - 870) ^ 2 + y * y)
		if x > 870 or d < 350 then return -3 end
		return 2 + math.min(d - 350, 870 - x) * 0.02
	end),
	-- a coast with a spit (Southborough)
	spit = T.sampler(function(x, y)
		if x <= 350 then return 2 + (350 - x) * 0.012 end
		if math.abs(y + 0.2 * (x - 350)) <= 120 and x <= 1200 then return 3 end
		return -3
	end),
}

local function resolve(sampler, o)
	local stats = T.stats(sampler, 0, 0, 600, 24)
	stats.spit = PT.findSpit(sampler, 0, 0)
	local roads = RDS.virtual(0, 0, o.radius or 200, { sampler = sampler, seed = o.id,
		neighbours = { { dir = (o.id * 1.7) % (2 * math.pi), dist = 3500 } } })
	local inputs = I.build({ townId = o.id, pos = { 0, 0 }, capacity = o.cap or 600, year = 1900, nameList = EU,
		terrain = stats, autoStyle = true, radius = o.radius or 200, roads = roads })
	return ST.resolve(inputs), stats
end

test("hilly coastal EU sites at 1900: most towns draw a fitting motif (at least 60 %), the site's own kind among them", function()
	F.withReliefMotifs(function() F.withTownMotifs(function()
		local total, with = 0, 0
		local rows = {}
		local names = {}
		for name in pairs(SITES) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local n, kinds = 0, {}
			for id = 1, 30 do
				local st = resolve(SITES[name], { id = id * 7 + #name })
				local drawn = 0
				for _, m in ipairs(st.motifs) do
					drawn = drawn + 1
					kinds[m.id] = (kinds[m.id] or 0) + 1
				end
				if drawn > 0 then n = n + 1 end
			end
			total, with = total + 30, with + n
			local ks = {}
			for k, c in pairs(kinds) do ks[#ks + 1] = k .. "=" .. c end
			table.sort(ks)
			rows[#rows + 1] = string.format("      %-10s %2d/30 with a drawn motif: %s", name, n, table.concat(ks, " "))
		end
		for _, r in ipairs(rows) do print(r) end
		local share = with / total
		print(string.format("      all terrain sites: %.0f %% with a drawn motif", 100 * share))
		ok(share >= 0.6, "terrain sites with a drawn motif: " .. share)
		-- per site: the terrain kind is among the picks
		local function picks(name, kind)
			local c = 0
			for id = 1, 30 do
				local st = resolve(SITES[name], { id = id * 7 + #name })
				for _, m in ipairs(st.motifs) do if m.id == kind then c = c + 1 end end
			end
			return c
		end
		ok(picks("hillside", "hill_climb") >= 5, "hillside: hill climbs")
		ok(picks("spit", "peninsula_tip") >= 5, "spit: peninsula tips")
		ok(picks("valley", "valley_fishbone") + picks("valley", "hill_climb") >= 5, "valley: fishbone / climb")
		-- the elig line's text: every drawn kind with its score and why
		local st = resolve(SITES.hillside, { id = 3 })
		ok(type(st._motifElig) == "string" and st._motifElig:find("hill_climb:", 1, true), tostring(st._motifElig))
		ok(MO.terrainText(T.stats(SITES.hillside, 0, 0, 600, 24), nil):find("grade=0.0", 1, true))
	end) end)
end)

test("plan slicing (final test: PLAN us=431633 in 3 slices): the master plan yields between its parts and motifs", function()
	local core = ug_require(F.DIR .. "ot_core.lua")
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	F.withReliefMotifs(function()
		local sampler = SITES.spit
		local st, stats = resolve(sampler, { id = 5 })
		st.motifs = { { id = "peninsula_tip", score = 1, why = "test" }, { id = "hill_climb", score = 1, why = "test" } }
		MO.applyStyle(st, { terrain = stats })
		local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
		local n = 0
		local mp = core.masterPlan(g, st, { terrain = sampler, stats = stats, yield = function() n = n + 1 end }, 8)
		ok(mp and #mp.pieces > 0, "plan")
		ok(n >= 3, "yields " .. n)
		-- inside a coroutine (the driver's slice) the plan resumes to the same result
		local st2 = resolve(sampler, { id = 5 })
		st2.motifs = st.motifs
		MO.applyStyle(st2, { terrain = stats })
		local co = coroutine.create(function()
			return core.masterPlan(g, st2, { terrain = sampler, stats = stats, yield = coroutine.yield }, 8)
		end)
		local res, steps = nil, 0
		while true do
			local okC, r = coroutine.resume(co)
			ok(okC, tostring(r))
			steps = steps + 1
			if coroutine.status(co) == "dead" then res = r; break end
		end
		ok(steps >= 3 and res and #res.pieces == #mp.pieces, "resumed: " .. steps .. " steps, " .. (res and #res.pieces or 0) .. " pieces")
	end)
end)
