-- ot_placename (generated names, 2026-10-14; NEXT_PHASE_BRIEF 42): the inventories, 1000 names per language (unique,
-- no blocklist hit, length limits, never a real list name), tags -> fitting morphemes, rivers shared along a river,
-- determinism per seed, the phonotactic rules, site tags from the reads, districts / Works, the saved water names, the
-- setting's indices; printed for the report: inventory sizes, 20 samples per language with their tags, distinct parts
-- on 16- and 50-town maps.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local PN = ug_require(F.DIR .. "ot_placename.lua")
local PA = ug_require(F.DIR .. "ot_params.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local FINE = { "river", "confluence", "mouth", "ford", "bridge", "bend", "spring", "brook", "lake", "tarn", "mere", "pool",
	"coast", "sandy", "rocky", "cliff", "bay", "headland", "spit", "island", "hilltop", "slope", "ridge", "pass", "foot",
	"mountain", "valley", "vale", "gorge", "combe", "rock", "marsh", "fen", "moor", "heath", "forest", "clearing", "edge",
	"oak", "ash", "beech", "birch", "pine", "fir", "alder", "willow", "plain", "field", "meadow" }

local function sorted(w)
	local t = {}
	for k in pairs(w) do t[#t + 1] = k end
	table.sort(t)
	return table.concat(t, "+")
end

-- n towns over a square of side km, each with two or three seeded fine tags
local function randomTowns(n, seed, km)
	local towns = {}
	for i = 1, n do
		local w = {}
		w[FINE[rng.hash(seed, "a", i) % #FINE + 1]] = 1
		w[FINE[rng.hash(seed, "b", i) % #FINE + 1]] = 0.7
		if rng.unit(seed, "c", i) < 0.4 then w[FINE[rng.hash(seed, "c3", i) % #FINE + 1]] = 0.5 end
		local ranked = {}
		for t, v in pairs(w) do ranked[#ranked + 1] = { t, v * (PN.SPEC[t] or 1) } end
		table.sort(ranked, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
		towns[i] = { id = i, name = "Town" .. i, x = rng.unit(seed, "x", i) * km * 1000, y = rng.unit(seed, "y", i) * km * 1000,
			w = w, ranked = ranked, character = rng.unit(seed, "ch", i) < 0.06, cap = 300 + rng.hash(seed, "cap", i) % 3000,
			river = w.river ~= nil or w.confluence ~= nil or w.ford ~= nil or w.bridge ~= nil, axis = rng.unit(seed, "ax", i) * math.pi,
			lake = w.lake ~= nil or w.tarn ~= nil or w.mere ~= nil }
	end
	return towns
end

test("inventories: every language parses with known tags only; sizes (printed)", function()
	eq(#PN.BAD, 0, "unknown tags: " .. table.concat(PN.BAD, ","))
	for _, lang in ipairs(PN.LANGS) do
		local L = PN.lang(lang)
		ok(L, lang)
		local valid = 0
		for _, s in ipairs(L.specs) do
			for _, g in ipairs(L.gens) do
				local b = PN.join(L, s, g)
				if b and PN.wellFormed(L, b) and not PN.blocked(b) then valid = valid + 1 end
			end
		end
		-- stems per tag group (a stem counts for each group one of its own tags falls in)
		local groups = { water = 0, coast = 0, relief = 0, wet = 0, trees = 0, open = 0, other = 0 }
		local G = { river = "water", mouth = "water", ford = "water", bridge = "water", bend = "water", confluence = "water",
			spring = "water", brook = "water", lake = "water", mere = "water", pool = "water", tarn = "water",
			coast = "coast", sandy = "coast", rocky = "coast", cliff = "coast", bay = "coast", headland = "coast", spit = "coast",
			island = "coast", marsh = "wet", fen = "wet", moor = "wet", heath = "wet", plain = "open", field = "open", meadow = "open",
			forest = "trees", edge = "trees", clearing = "trees" }
		for _, t in ipairs({ "hill", "hilltop", "slope", "ridge", "pass", "foot", "mountain", "valley", "vale", "gorge", "combe", "rock" }) do G[t] = "relief" end
		for _, s in ipairs(PN.SPECIES) do G[s] = "trees" end
		for _, s in ipairs(L.specs) do
			local seen = {}
			for _, p in ipairs(s.tl) do
				local g = G[p[1]] or "other"
				if not seen[g] then seen[g] = true; groups[g] = groups[g] + 1 end
			end
		end
		print(string.format("%-5s stems %3d  generics %2d  affixes %2d  stem+generic names %5d  x affixes ~%6d  | stems: water %d coast %d relief %d wet %d trees %d open %d other %d",
			lang, #L.specs, #L.gens, #L.affixes, valid, valid * (1 + #L.affixes), groups.water, groups.coast, groups.relief,
			groups.wet, groups.trees, groups.open, groups.other))
		ok(#L.specs >= 23, lang .. " stems")
		ok(#L.gens >= 18, lang .. " generics")
		ok(valid >= 600, lang .. " combinations " .. valid)
	end
end)

-- (one test per language, 2026-10-14: the twelve took 78 s together; quick mode names 300 towns, TEST_FULL 1000)
local NAMES_N = os.getenv("TEST_FULL") and 1000 or 300
for _, lang in ipairs(PN.LANGS) do
test(NAMES_N .. " names, " .. lang .. ": unique, none blocked, within the length limits, never a real list name", function()
	local real = { ["ashford"] = true, ["cedar falls"] = true, ["eichbach"] = true, ["montalto"] = true, ["villanueva"] = true }
	do
		local towns = randomTowns(NAMES_N, 11, 120 * math.sqrt(NAMES_N / 1000))
		local res, st = PN.assign(towns, { lang = lang, seed = 99, real = real })
		ok(res, lang)
		local seen, seenL = {}, {}
		local named = 0
		for _, r in ipairs(res) do
			if r.new ~= r.old then
				named = named + 1
				ok(not seen[r.new], lang .. " duplicate " .. r.new)
				ok(not seenL[PN.lowerAll(r.new)], lang .. " duplicate (case) " .. r.new)
				seen[r.new], seenL[PN.lowerAll(r.new)] = true, true
				ok(not PN.blocked(r.new), lang .. " blocked " .. r.new)
				ok(not real[PN.lowerAll(r.new)], lang .. " real " .. r.new)
				local lim = PN.MAX_FULL + (lang == "ja" and 1 or 0)
				ok(PN.chars(r.new) <= lim, lang .. " too long " .. r.new)
				if r.info and r.info.base then
					ok(PN.chars(r.info.base) <= (lang == "ja" and PN.MAX_KANJI or PN.MAX_BASE), lang .. " base " .. r.info.base)
					ok(not PN.lowerAll(r.info.base):find("([a-z])%1%1"), lang .. " triple " .. r.info.base)
				end
			end
		end
		ok(named >= NAMES_N * 0.99, lang .. " named " .. named .. " of " .. NAMES_N)
		print(string.format("%-5s %d towns: %d named, %d rivers, %d lakes, %d twins", lang, NAMES_N, named, st.rivers, st.lakes,
			st.shapes and st.shapes.twins or 0))
	end
end)
end

test("tags map to fitting morphemes: a one-feature site gets a part of that feature (or its family)", function()
	for _, lang in ipairs(PN.LANGS) do
		local hits, exact, total, miss = 0, 0, 0, {}
		for i, tag in ipairs(FINE) do
			local ranked = { { tag, 1 } }
			-- (the morphemes alone, without the map's shape plan of NEXT_PHASE_BRIEF 53: a plain name has no frame)
			local res = PN.assign({ { id = i, name = "T", x = 0, y = 0, w = { [tag] = 1 }, ranked = ranked } }, { lang = lang, seed = 5 + i, sat = false,
				shapes = false })
			local info = res[1].info
			total = total + 1
			local fam = PN.family(tag)
			local got, gotExact = false, false
			for _, e in ipairs({ info and info.sE, info and info.gE, info and info.aE }) do
				if e then
					for _, p in ipairs(e.tl) do
						if p[1] == tag then gotExact, got = true, true end
						if PN.family(p[1]) == fam then got = true end
					end
				end
			end
			if got then hits = hits + 1 else miss[#miss + 1] = tag .. "=" .. res[1].new end
			if gotExact then exact = exact + 1 end
		end
		print(string.format("%-5s %d/%d sites fit by family, %d exact; misses: %s", lang, hits, total, exact, table.concat(miss, " ")))
		ok(hits >= math.floor(total * 0.85), lang .. " family fit " .. hits .. "/" .. total)
	end
end)

test("towns on one river share its name; a town off the river's line has another (or none)", function()
	for _, lang in ipairs({ "en", "de", "fr", "usa" }) do
		local towns = {}
		for i = 1, 4 do
			towns[i] = { id = i, name = "T" .. i, x = (i - 1) * 3500, y = 0, w = { river = 1, ford = 0.6 }, ranked = { { "river", 0.9 } },
				river = true, axis = 0.05 }
		end
		towns[5] = { id = 5, name = "T5", x = 3500, y = 5000, w = { river = 1 }, ranked = { { "river", 0.9 } }, river = true, axis = 0 }
		towns[6] = { id = 6, name = "T6", x = 20000, y = 20000, w = { lake = 1 }, ranked = { { "lake", 1 } }, lake = true }
		local res, st = PN.assign(towns, { lang = lang, seed = 3 })
		ok(res[1].river, lang .. " river named")
		for i = 2, 4 do eq(res[i].river, res[1].river, lang .. " shared river") end
		ok(res[5].river ~= res[1].river, lang .. " the town off the line: another river")
		ok(#st.waters >= 5, lang .. " waters for the save")
		print(string.format("%-5s river %s: %s / %s / %s / %s; off the line: %s (%s); lake %s: %s", lang, res[1].river,
			res[1].new, res[2].new, res[3].new, res[4].new, res[5].new, tostring(res[5].river), tostring(res[6].lake), res[6].new))
	end
end)

test("deterministic per seed; another seed gives other names", function()
	local towns = randomTowns(40, 21, 40)
	local a = PN.assign(towns, { lang = "en", seed = 7 })
	local b = PN.assign(towns, { lang = "en", seed = 7 })
	local c = PN.assign(towns, { lang = "en", seed = 8 })
	local diff = 0
	for i = 1, #towns do
		eq(a[i].new, b[i].new)
		if a[i].new ~= c[i].new then diff = diff + 1 end
	end
	ok(diff >= 20, "another seed: " .. diff .. " of 40 differ")
end)

test("phonotactics: no triple letters, no doubled junction letters a language avoids, elision, no two parts of a class", function()
	local L = PN.lang("en")
	local function spec(t, extra) local e = { text = t, tl = {}, flags = extra or {}, kind = "stem" } return e end
	local function gen(t, form, cls) return { text = t, form = form or "suf", tl = {}, flags = {}, cls = cls } end
	eq(PN.join(L, spec("Hill"), gen("ley")), nil)
	eq(PN.join(L, spec("Ash"), gen("ham")), nil)
	eq(PN.join(L, spec("Ash"), gen("ford")), "Ashford")
	eq(PN.join(L, spec("Stone"), gen("ey")), "Stoney")
	local b = spec("Brook"); b.cls = "brook"
	eq(PN.join(L, b, gen("brook", "suf", "brook")), nil)
	eq(PN.join(L, spec("Ford"), gen("ford")), nil)
	local it = PN.lang("it")
	local alto = { text = "alto", forms = { "alto", "alta" }, kind = "adj", tl = {}, flags = {} }
	eq(PN.join(it, alto, { text = "Monte", form = "pre", gender = "m", tl = {}, flags = {} }), "Montalto")
	eq(PN.join(it, alto, { text = "Villa", form = "pre", gender = "f", tl = {}, flags = {} }), "Villalta")
	eq(PN.join(PN.lang("pt"), alto, { text = "Vila", form = "before", gender = "f", tl = {}, flags = {} }), "Vila Alta")
	ok(PN.wellFormed(L, "Ashford"))
	ok(not PN.wellFormed(L, "Thornhurstwoodleigh"))
end)

test("blocklist: offensive and brand strings, case-insensitive, substrings and whole words", function()
	ok(PN.blocked("Shitbury"))
	ok(PN.blocked("Fuckley"))
	ok(PN.blocked("Ford Crossing"))
	ok(PN.blocked("Lower IKEA"))
	ok(PN.blocked("Merdingen"))
	ok(PN.blocked("死川"))
	ok(not PN.blocked("Ashford"))
	ok(not PN.blocked("Fordham"))
	ok(not PN.blocked("Montalto"))
end)

test("site tags: confluence, mouth, tarn, gorge, pass, spit, species from the reads", function()
	local w, ranked = PN.siteTags({ feat = { river = 1 }, stats = { water = { kind = "river" } }, read = { arms = 3, width = 50 } })
	eq(ranked[1][1], "confluence")
	w = PN.siteTags({ feat = { river = 1, coast = 0.5 }, stats = { water = { kind = "river" } }, wide = { water = 0.3 }, read = { arms = 1 } })
	ok(w.mouth)
	w, ranked = PN.siteTags({ feat = { body = "lake", coast = 0.8 }, stats = {}, read = { alt = 320 } })
	ok(w.tarn and w.lake and not w.coast)
	eq(ranked[1][1], "tarn")
	w, ranked = PN.siteTags({ feat = { rough = 0.6 }, stats = { meanSlope = 0.08, p95Slope = 0.35, dirRelief = { valley = true, contrast = 60 } } })
	ok(w.gorge and w.valley)
	eq(ranked[1][1], "gorge")
	w = PN.siteTags({ feat = {}, stats = {}, read = { pass = true, relH = 0 } })
	ok(w.pass)
	w = PN.siteTags({ feat = { coast = 0.6 }, stats = { spit = { x = 1 } } })
	ok(w.spit and w.headland)
	w = PN.siteTags({ feat = {}, stats = {}, forestShare = 0.4, species = { oak = 300, pine = 50, birch = 120 } })
	ok(w.oak and w.birch and w.clearing and not w.pine)
end)

test("read: water arms and the ring on a synthetic site (a river through, a confluence, a pass)", function()
	-- a river along y = 0 (60 m wide)
	local s = T.sampler(function() return 50 end, function(x, y) return math.abs(y) < 30 end, 0)
	local r = PN.read(s, 0, 0)
	eq(r.arms, 2)
	-- three rivers meeting at the centre
	s = T.sampler(function() return 50 end, function(x, y)
		return (math.abs(y) < 30 and x < 0) or (math.abs(x) < 30 and y > 0) or (math.abs(x) < 30 and y < 0)
	end, 0)
	eq(PN.read(s, 0, 0).arms, 3)
	-- a saddle: high east / west, low north / south
	s = T.sampler(function(x, y) return 100 + 0.04 * math.abs(x) - 0.03 * math.abs(y) end, function() return false end, 0)
	ok(PN.read(s, 0, 0).pass)
end)

test("districts and Works: the parent's stem with a fitting generic; industrial names", function()
	local nm = PN.related("en", "Ashford", "upper", { Ashford = true }, { seed = 1 })
	ok(nm and nm:sub(1, 3) == "Ash" and nm ~= "Ashford", tostring(nm))
	local nm2 = PN.related("de", "Eichbach", "valley", {}, { seed = 1 })
	ok(nm2 and nm2:sub(1, 4) == "Eich", tostring(nm2))
	eq(PN.related("it", "Montalto", "upper", {}, { seed = 1 }), nil)
	local w = PN.works("en", "Ashford", "mine", "plain", {}, { seed = 2 })
	ok(w and (w:find("Coal") or w:find("Copper") or w:find("Tin") or w:find("Lead") or w:find("Pit")), tostring(w))
	local wf = PN.works("fr", "Beauville", "works", "plain", {}, { seed = 2 })
	ok(wf and wf:find("Beauville", 1, true), tostring(wf))
	print("district / works: " .. nm .. ", " .. nm2 .. ", " .. w .. ", " .. wf .. ", " .. tostring(PN.works("ja_r", "Matsuyama", "mine", "hill", {}, {})))
end)

test("saved: the water names go with the done flag, normalised and capped", function()
	local s = SV.applyNames({ v = 1, frames = {} }, { done = 1, nd = "en", rv = { { n = "Avon", x = 10.4, y = 20, k = "r" },
		{ n = "Wynmere", s = "Wyn", x = 1, y = 2, k = "l" }, { n = 5, x = 1, y = 1, k = "r" }, { n = "Bad", x = 1, y = 1, k = "z" } } })
	eq(#SV.waters(s), 2)
	eq(SV.waters(s)[1].x, 10)
	eq(SV.waters(s)[2].s, "Wyn")
	local many = {}
	for i = 1, 50 do many[i] = { n = "R" .. i, x = i, y = i, k = "r" } end
	eq(#SV.waters(SV.applyNames({ v = 1, frames = {} }, { done = 1, rv = many })), SV.WATER_CAP)
	eq(SV.waters(SV.normalize({ v = 1, frames = {} })), nil)
end)

test("setting: the indices stay stable (1 Landscape, 2 Game; a saved 3, the removed Generated names, reads as Landscape) and match mod.json", function()
	eq(PA.parse({ town_names = 1 }).townNames, "landscape")
	eq(PA.parse({ town_names = 2 }).townNames, "game")
	eq(PA.parse({ town_names = 3 }).townNames, "landscape")
	eq(PA.parse({}).townNames, "landscape")
	eq(PA.parse({ town_names = 4 }).townNames, "landscape")
	local f = io.open(here .. "../../mods/square_organic_towns/mod.json", "r")
	ok(f, "mod.json")
	local txt = f:read("*a")
	f:close()
	ok(txt:find('"key": "town_names"', 1, true))
	ok(txt:find('"Landscape names",%s*"Game names"%s*%]'), "mod.json value order (Generated names removed 2026-10-15)")
end)

test("unsupported lists fall back: no generator for the Russian, Chinese, Korean, Asian, Oceanian and Polish lists", function()
	for _, cls in ipairs({ "ru", "ru_r" }) do eq(PN.langOf(cls), nil) end
	eq(PN.langOf(nil), nil)
	eq(PN.langOf("en"), "en")
	eq(PN.langOf("ja_r"), "ja_r")
end)

-- realistic sites for the report (what siteTags gives for typical towns)
local SITES = {
	{ "confluence", { river = 1, confluence = 1, ford = 0.6, bridge = 0.6, meadow = 0.6 } },
	{ "river mouth", { river = 1, mouth = 1, coast = 0.5, sandy = 0.6 } },
	{ "ford, alders", { river = 1, ford = 0.9, brook = 0.9, forest = 0.5, edge = 0.7, alder = 0.8 } },
	{ "river bend", { river = 1, bend = 0.9, bridge = 0.6, field = 0.5 } },
	{ "spring", { river = 1, spring = 0.8, combe = 0.7, valley = 0.8 } },
	{ "tarn", { lake = 1, tarn = 1, mountain = 0.7 } },
	{ "mere", { lake = 1, mere = 0.9, marsh = 0.6 } },
	{ "sandy bay", { coast = 1, sandy = 0.8, bay = 0.8 } },
	{ "cliff coast", { coast = 1, cliff = 0.9, rocky = 0.8 } },
	{ "spit", { coast = 0.8, spit = 1, headland = 0.7 } },
	{ "island", { coast = 1, island = 1 } },
	{ "hilltop, oaks", { hill = 0.6, hilltop = 0.9, forest = 0.4, edge = 0.7, oak = 0.8 } },
	{ "ridge", { ridge = 1, hill = 0.8 } },
	{ "pass", { pass = 1, mountain = 0.6 } },
	{ "foot of a mountain", { foot = 0.9, mountain = 0.6, field = 0.4 } },
	{ "gorge", { valley = 1, gorge = 1, rock = 0.6 } },
	{ "wide vale", { valley = 0.5, vale = 0.8, meadow = 0.7, river = 1 } },
	{ "fen", { marsh = 0.8, fen = 0.9, river = 1 } },
	{ "moor", { moor = 0.8, heath = 0.5 } },
	{ "pine clearing", { forest = 1, clearing = 0.9, pine = 0.9 } },
	{ "birch edge", { forest = 0.6, edge = 0.7, birch = 0.8, field = 0.5 } },
	{ "plain, market", { plain = 0.9, field = 0.7, market = 0.8, big = 0.8 } },
}

test("samples per language (printed for the report: name [stem+generic+affix] site)", function()
	for _, lang in ipairs(PN.LANGS) do
		local towns = {}
		for i, sx in ipairs(SITES) do
			local ranked = {}
			for t, v in pairs(sx[2]) do ranked[#ranked + 1] = { t, v * (PN.SPEC[t] or 1) } end
			table.sort(ranked, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
			towns[i] = { id = i, name = "T" .. i, x = (i % 5) * 9000, y = math.floor(i / 5) * 9000, w = sx[2], ranked = ranked,
				character = i == 12, river = sx[2].river ~= nil, axis = 0, lake = sx[2].lake ~= nil }
		end
		local res = PN.assign(towns, { lang = lang, seed = 2026 })
		local out = {}
		for i, r in ipairs(res) do out[#out + 1] = string.format("%s [%s] (%s)", r.new, PN.partsText(r.info), SITES[i][1]) end
		print(lang .. ":\n    " .. table.concat(out, "\n    "))
	end
end)

test("distinct parts on 16- and 50-town maps (printed; mean of 5 seeds)", function()
	for _, lang in ipairs(PN.LANGS) do
		local line = {}
		for _, n in ipairs({ 16, 50 }) do
			local gs, ss, aff, rep = 0, 0, 0, 0
			for sd = 1, 5 do
				local res = PN.assign(randomTowns(n, 100 + sd, n == 16 and 40 or 80), { lang = lang, seed = sd })
				local g, s, a = {}, {}, 0
				local ng, ns = 0, 0
				local maxG = 0
				for _, r in ipairs(res) do
					if r.info then
						if not g[r.info.gen] then ng = ng + 1 end
						g[r.info.gen] = (g[r.info.gen] or 0) + 1
						if g[r.info.gen] > maxG then maxG = g[r.info.gen] end
						if not s[r.info.spec] then ns = ns + 1 end
						s[r.info.spec] = true
						if r.info.affix then a = a + 1 end
					end
				end
				gs, ss, aff, rep = gs + ng, ss + ns, aff + a, rep + maxG
			end
			line[#line + 1] = string.format("%d towns: %.1f generics, %.1f stems, %.1f affixed, most-used generic x%.1f", n, gs / 5,
				ss / 5, aff / 5, rep / 5)
		end
		print(string.format("%-5s %s", lang, table.concat(line, " | ")))
	end
end)
