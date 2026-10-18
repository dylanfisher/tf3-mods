-- ot_rng (hash RNG) and ot_inputs (region / climate / era / size from raw game data).

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local I = ug_require "square_organic_towns::/organic_towns/ot_inputs.lua"

---------------------------------------------------------------------------
-- ot_rng

test("hash: deterministic, in range, order and sign sensitive", function()
	eq(rng.hash(1, 2, 3), rng.hash(1, 2, 3))
	ok(rng.hash(1, 2, 3) ~= rng.hash(3, 2, 1))
	ok(rng.hash(5) ~= rng.hash(-5))
	ok(rng.hash("a") ~= rng.hash("b"))
	ok(rng.hash(1e12) ~= rng.hash(1e12 + 65536))
	for i = 1, 200 do
		local h = rng.hash(i, "x")
		ok(h >= 1 and h <= 2147483646, "range")
		eq(h, math.floor(h))
	end
end)

test("hash: floors numbers, booleans and nil are distinct", function()
	eq(rng.hash(3.7), rng.hash(3))
	ok(rng.hash(true) ~= rng.hash(false))
	ok(rng.hash(nil) ~= rng.hash(true))
end)

test("seed: per town, stable; a bucket gives another stream", function()
	eq(rng.seed(12, 100.4, -50.2), rng.seed(12, 100, -51))   -- floored to metres
	ok(rng.seed(12, 100, -50) ~= rng.seed(13, 100, -50))
	ok(rng.seed(12, 100, -50) ~= rng.seed(12, 100, -50, 0))
	ok(rng.seed(12, 100, -50, 1) ~= rng.seed(12, 100, -50, 2))
end)

test("generator: same seed same sequence, values in [0, 1)", function()
	local a, b = rng.new(42), rng.new(42)
	local sum = 0
	for _ = 1, 2000 do
		local x = a:next()
		eq(x, b:next())
		ok(x >= 0 and x < 1)
		sum = sum + x
	end
	near(sum / 2000, 0.5, 0.03, "mean")
	ok(rng.new(43):next() ~= rng.new(42):next())
end)

test("generator: known first values (Park-Miller 48271, exact in doubles)", function()
	local r = rng.new(1)
	r:next()
	eq(r.s, 48271)
	r:next()
	eq(r.s, 182605794)   -- 48271^2 mod (2^31 - 1)
end)

test("generator: int, range, chance, normal, pick, fork", function()
	local r = rng.new(7)
	local seen = {}
	for _ = 1, 500 do
		local v = r:int(3, 6)
		ok(v >= 3 and v <= 6 and v == math.floor(v))
		seen[v] = true
		local f = r:range(-2, 2)
		ok(f >= -2 and f < 2)
		local n = r:normal()
		ok(n >= -3 and n <= 3)
	end
	ok(seen[3] and seen[4] and seen[5] and seen[6], "all ints hit")
	local hits = 0
	for _ = 1, 1000 do if r:chance(0.25) then hits = hits + 1 end end
	ok(hits > 180 and hits < 320, "chance ~25 %")
	eq(r:pick({}), nil)
	eq(r:pick({ "only" }), "only")
	local s = r.s
	local f1, f2 = r:fork("a"), r:fork("a")
	eq(r.s, s, "fork does not advance")
	eq(f1:next(), f2:next())
	ok(r:fork("a"):next() ~= r:fork("b"):next())
end)

test("unit: stateless lookups in [0, 1)", function()
	eq(rng.unit(1, "u", 3), rng.unit(1, "u", 3))
	for i = -50, 50 do
		local u = rng.unit(9, "line", i)
		ok(u >= 0 and u < 1)
	end
end)

---------------------------------------------------------------------------
-- ot_inputs

test("region: every base name set and the square US sets", function()
	local cases = {
		{ "::/names/usa/usa.names", "US", "usa" },
		{ "square_names_us_texas::/names/texas.names", "US", "usa" },
		{ "::/names/oceania/oceania.names", "OCEANIA" },
		{ "::/names/germany/germany.names", "EU" }, { "::/names/france/france.names", "EU" },
		{ "::/names/england/england.names", "EU" }, { "::/names/netherlands/netherlands.names", "EU" },
		{ "::/names/poland/poland.names", "EU" }, { "::/names/europe/europe.names", "EU", "europe" },
		{ "::/names/italy/italy.names", "MED" }, { "::/names/spain/spain.names", "MED", "spain" },
		{ "::/names/portugal/portugal.names", "MED" },
		{ "::/names/norway/norway.names", "NORDIC" }, { "::/names/sweden/sweden.names", "NORDIC" },
		{ "::/names/russia/russia.names", "RU" },
		{ "::/names/japan/japan.names", "JP" },
		{ "::/names/korea/korea.names", "EAST_ASIA" }, { "::/names/china/china.names", "EAST_ASIA" },
		{ "::/names/asia/asia.names", "ASIA", "asia" },
	}
	for _, c in ipairs(cases) do
		local r, country = I.region(c[1])
		eq(r, c[2], c[1])
		if c[3] then eq(country, c[3], c[1]) end
	end
	eq(I.region(nil), nil)
	eq(I.region(""), nil)
	eq(I.region("somemod::/names/atlantis.names"), nil)
end)

test("climate: ids and paths, default temperate", function()
	eq(I.climate("dry"), "dry")
	eq(I.climate("::/climates/subarctic/subarctic.clima.lua"), "subarctic")
	eq(I.climate("TROPICAL"), "tropical")
	eq(I.climate(nil), "temperate")
	eq(I.climate("martian"), "temperate")
end)

test("era bands and template switch", function()
	eq(I.era(1800), 1)
	eq(I.era(1849), 1)
	eq(I.era(1850), 2)
	eq(I.era(1919), 2)
	eq(I.era(1920), 3)
	eq(I.era(1950), 4)
	eq(I.era(1979), 4)
	eq(I.era(1980), 5)
	eq(I.era(2100), 5)
	eq(I.era(nil), 4)
	eq(I.newTemplates(1939), false)
	eq(I.newTemplates(1940), true)
end)

test("size tiers", function()
	eq(I.sizeTier(0), 1)
	eq(I.sizeTier(499), 1)
	eq(I.sizeTier(500), 2)
	eq(I.sizeTier(1999), 2)
	eq(I.sizeTier(2000), 3)
	eq(I.sizeTier(6000), 4)
	eq(I.sizeTier(nil), 1)
end)

test("build: region falls back to the climate, then EU", function()
	local a = I.build({ nameList = "x::/names/unknown.names", climate = "subarctic" })
	eq(a.region, "NORDIC")
	eq(a.regionSource, "climate")
	eq(I.build({ climate = "dry" }).region, "MED")
	eq(I.build({}).region, "EU")
	local b = I.build({ nameList = "::/names/japan/japan.names", year = 1985, capacity = 2500, pos = { 10, 20 } })
	eq(b.region, "JP")
	eq(b.regionSource, "nameList")
	eq(b.era, 5)
	eq(b.tier, 3)
	eq(b.pos, { 10, 20 })
	eq(b.newTemplates, true)
	eq(I.build({ pos = { x = 3, y = 4 } }).pos, { 3, 4 })
end)
