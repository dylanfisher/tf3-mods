-- Name lists from other mods (NEXT_PHASE_BRIEF 72, 2026-10-17): the path's words name the region / country (base
-- lists and the square state mods unchanged), the towns the mod founds on another mod's list are named in its language
-- (the country's classifier, else a guess from the map's names, else unused names of the list's own towns.lua, else
-- the old composed English), the list's own towns are never renamed, and one NAMELIST line per session.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local I = ug_require(F.DIR .. "ot_inputs.lua")
local AN = ug_require(F.DIR .. "ot_angles.lua")
local NM = ug_require(F.DIR .. "ot_names.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

-- the rules before §72 (raw substrings, first match wins), for the "unchanged" checks
local LEGACY = {
	{ "square_names_us_", "US", "usa" }, { "/usa", "US", "usa" }, { "square_names_ca_", "US", "canada" },
	{ "canada", "US", "canada" }, { "oceania", "OCEANIA", "oceania" }, { "germany", "EU", "germany" },
	{ "france", "EU", "france" }, { "england", "EU", "england" }, { "netherlands", "EU", "netherlands" },
	{ "poland", "EU", "poland" }, { "italy", "MED", "italy" }, { "spain", "MED", "spain" },
	{ "portugal", "MED", "portugal" }, { "norway", "NORDIC", "norway" }, { "sweden", "NORDIC", "sweden" },
	{ "russia", "RU", "russia" }, { "japan", "JP", "japan" }, { "korea", "EAST_ASIA", "korea" },
	{ "china", "EAST_ASIA", "china" }, { "asia", "ASIA", "asia" }, { "europe", "EU", "europe" },
}
local function legacy(nameList)
	local s = nameList:lower()
	for _, r in ipairs(LEGACY) do
		if s:find(r[1], 1, true) then return r[2], r[3] end
	end
	return nil, nil
end

local BASE = { "usa", "oceania", "germany", "france", "england", "netherlands", "poland", "italy", "spain", "portugal",
	"norway", "sweden", "russia", "japan", "korea", "china", "asia", "europe" }

local OURS = {
	"square_names_us_texas::/names/square_names_us_texas/us_texas.names",
	"square_names_us_washington::/names/square_names_us_washington/us_washington.names",
	"square_names_us_georgia::/names/square_names_us_georgia/us_georgia.names",
	"square_names_us_new_york::/names/square_names_us_new_york/us_new_york.names",
	"square_names_ca_ontario::/names/x.names", "square_names_us_texas::/names/texas.names",
}

test("detection: every base list and our state mods' lists keep the region and country they had", function()
	for _, b in ipairs(BASE) do
		for _, p in ipairs({ "::/names/" .. b .. "/" .. b .. ".names", "::/names/" .. b .. "/" .. b .. ".names.lua" }) do
			local r, c = I.region(p)
			local lr, lc = legacy(p)
			eq(r, lr, p)
			eq(c, lc, p)
			ok(r ~= nil, p)
		end
	end
	for _, p in ipairs(OURS) do
		local r, c = I.region(p)
		local lr, lc = legacy(p)
		eq(r, lr, p)
		eq(c, lc, p)
	end
	eq((I.region("square_names_us_georgia::/names/square_names_us_georgia/us_georgia.names")), "US", "not the country")
end)

-- path -> region, country (nil: unknown, the climate decides)
local MODDED = {
	-- German lists in common spellings
	{ "german_cities_and_municipalities::/names/german_cities/german_cities.names", "EU", "germany" },
	{ "deutsche_staedte_und_gemeinden::/names/deutschland/deutschland.names", "EU", "germany" },
	{ "dsug5::/names/Deutschland/Deutsch.names", "EU", "germany" },
	{ "deutschestaedte::/names/staedte/staedte.names", "EU", "germany" },
	{ "germancities::/names/gc/gc.names", "EU", "germany" },
	{ "names_de::/names/deutsch-staedte/deutsch-staedte.names", "EU", "germany" },
	{ "oesterreich_namen::/names/at/at.names", "EU", "austria" },
	{ "mod::/names/\195\182sterreich/\195\182sterreich.names", "EU", "austria" },
	{ "schweiz::/names/ch/ch.names", "EU", "switzerland" },
	-- French, English, Dutch, Polish, Italian, Spanish, Portuguese, Nordic, Russian, East Asian
	{ "villes_francaises::/names/francais/francais.names", "EU", "france" },
	{ "french_towns::/names/fr/fr.names", "EU", "france" },
	{ "uk_towns::/names/uk/uk.names", "EU", "uk" },
	{ "british_names::/names/britain/britain.names", "EU", "uk" },
	{ "english_villages::/names/villages/villages.names", "EU", "england" },
	{ "dutch_names::/names/nederland/nederland.names", "EU", "netherlands" },
	{ "polska_miasta::/names/polska/polska.names", "EU", "poland" },
	{ "italia_comuni::/names/italia/italia.names", "MED", "italy" },
	{ "espana::/names/espanol/espanol.names", "MED", "spain" },
	{ "portuguese_towns::/names/pt/pt.names", "MED", "portugal" },
	{ "norge_steder::/names/norge/norge.names", "NORDIC", "norway" },
	{ "sverige::/names/svenska/svenska.names", "NORDIC", "sweden" },
	{ "danske_byer::/names/danmark/danmark.names", "NORDIC", "denmark" },
	{ "russian_towns::/names/rossiya/rossiya.names", "RU", "russia" },
	{ "nippon::/names/nihon/nihon.names", "JP", "japan" },
	{ "korean_cities::/names/kr/kr.names", "EAST_ASIA", "korea" },
	{ "chinese_cities::/names/cn/cn.names", "EAST_ASIA", "china" },
	{ "australian_towns::/names/au/au.names", "OCEANIA", "australia" },
	{ "us_towns::/names/us/us.names", "US", "usa" },
	{ "canadian_towns::/names/ca/ca.names", "US", "canada" },
	-- most specific: a country word over a continent word, the later of two country words
	{ "europe_pack::/names/german/german.names", "EU", "germany" },
	{ "german_names::/names/europe/europe.names", "EU", "germany" },
	{ "german_pack::/names/france/france.names", "EU", "france" },
	{ "asian_pack::/names/japan/japan.names", "JP", "japan" },
	{ "european_towns::/names/eu/eu.names", "EU", "europe" },
	-- false positives guarded: words, not substrings
	{ "arizonaranger_washington_names::/names/washington/washington.names", nil, nil },
	{ "duke_names::/names/dukes/dukes.names", nil, nil },
	{ "campus_towns::/names/campus/campus.names", nil, nil },
	{ "francesca::/names/francesca/francesca.names", nil, nil },
	{ "south_american_towns::/names/sa/sa.names", nil, nil },
	{ "russo::/names/prussian/prussian.names", nil, nil },
	{ "somemod::/names/atlantis.names", nil, nil },
	{ "germ::/names/g/g.names", nil, nil },
}

test("detection: modded lists by their words (German and others), false positives guarded", function()
	for _, c in ipairs(MODDED) do
		local r, country = I.region(c[1])
		eq(r, c[2], c[1])
		eq(country, c[3], c[1])
	end
	eq(I.region(nil), nil)
	eq(I.region(""), nil)
	eq(I.region(42), nil)
	-- the deciding word comes back (log)
	local _, _, w = I.region("dsug::/names/deutschland/deutschland.names")
	eq(w, "deutschland")
	-- path words: lower case, split at non-letters, capped
	local ws = I.pathWords("A_B-c::/names/Dd/e1f.names")
	eq(table.concat(ws, ","), "a,b,c,names,dd,e,f,names")
	eq(#I.pathWords(string.rep("ab_", 500)), I.MAX_WORDS)
end)

test("a German modded list on a dry map: region EU by its name (not MED by the climate), the EU street angle", function()
	local nl = "german_cities_and_municipalities::/names/german_cities/german_cities.names"
	local inp = I.build({ nameList = nl, climate = "::/climates/dry/dry.clima", year = 1960 })
	eq(inp.region, "EU")
	eq(inp.regionSource, "nameList")
	eq(inp.nameRegion, "EU")
	eq(inp.country, "germany")
	local reg, src = AN.region({ nameList = nl, climate = "dry" }, nil)
	eq(reg, "EU")
	eq(src, "nameList")
	eq(AN.angleFor("auto", reg, "dry"), 35)
	-- unknown list on a dry map: still the climate
	local u = I.build({ nameList = "atlantis::/names/atlantis/atlantis.names", climate = "dry", year = 1960 })
	eq(u.region, "MED")
	eq(u.regionSource, "climate")
	eq(u.nameRegion, nil)
end)

---------------------------------------------------------------------------
-- the founded towns' name language

local DE = { "Ulm", "Freiburg", "Neustadt", "Rosenheim", "Bergheim", "Waldkirch", "Schönbach", "Lindau", "Hohenberg",
	"Mühldorf", "Talheim", "Steinbach", "Bruchsal", "Kirchdorf", "Neuburg", "Eichstätt" }
local PL = { "Kraków", "Łódź", "Wrocław", "Poznań", "Gdańsk", "Szczecin", "Bydgoszcz", "Lublin", "Białystok", "Katowice",
	"Gdynia", "Częstochowa", "Radom", "Toruń", "Kielce", "Rzeszów" }
local RU = { "Москва", "Тверь", "Тула", "Курск", "Орёл", "Рязань", "Кострома", "Ярославль", "Владимир", "Иваново",
	"Калуга", "Смоленск", "Брянск", "Липецк", "Тамбов", "Пенза" }
local JA = { "横浜市", "大阪市", "札幌市", "福岡市", "神戸市", "京都市", "さいたま市", "広島市", "仙台市", "千葉市" }

local function driver(nameList, names, o)
	o = o or {}
	local ids = {}
	for i = 1, #names do ids[i] = i end
	local calls = { towns = 0, list = {} }
	local E = { log = function() end, towns = function() calls.towns = calls.towns + 1; return ids end,
		name = function(id) return names[id] end, language = o.lang and function() return o.lang end or nil,
		townListAt = function(p)
			calls.list[#calls.list + 1] = p
			if o.files and o.files[p] then return o.files[p] end
			error("not found: " .. p)
		end,
		townList = function() return { "Basetown" } end }
	if o.noListAt then E.townListAt = nil end
	local d = D.new(E, "[T]")
	d.cfg = { nameList = nameList }
	d.opts = {}
	d.nameRegion = (I.build({ nameList = nameList })).nameRegion
	return d, calls, E
end

test("a modded list naming a country: its classifier (German de, French fr, Russian ru / ru_r by script, ...)", function()
	local cases = {
		{ "german_cities_and_municipalities::/names/german_cities/german_cities.names", DE, "de" },
		{ "villes::/names/francais/francais.names", DE, "fr" },
		{ "russian_towns::/names/russia_ru/x.names", RU, "ru" },
		{ "russian_towns::/names/russia_en/x.names", DE, "ru_r" },
		{ "nippon::/names/nihon/x.names", JA, "ja" },
		{ "nippon::/names/nihon/x.names", { "Tokyo", "Osaka" }, "ja_r" },
		{ "dutch::/names/nl/x.names", DE, "nl" }, { "italia::/names/it/x.names", DE, "it" },
		{ "espana::/names/es/x.names", DE, "es" }, { "portugal_x::/names/pt/x.names", DE, "pt" },
		{ "sverige::/names/se/x.names", DE, "sv" }, { "norge::/names/no/x.names", DE, "nb" },
		{ "uk_towns::/names/uk/x.names", DE, "en" }, { "us_towns::/names/us/x.names", DE, "usa" },
		{ "oesterreich::/names/at/x.names", DE, "de" },
	}
	for _, c in ipairs(cases) do
		local d, calls = driver(c[1], c[2])
		eq(d:nameCls(nil), c[3], c[1])
		eq(d:offshootCls(nil), c[3], c[1])
		local L = d:listLang()
		eq(L.clsSource, "country", c[1])
		eq(L.base, false)
		eq(#calls.list, 0, "no towns.lua read when the country is known")
	end
end)

test("an unknown modded list: a confident guess from the map's names (German de), never a wrong one on Polish", function()
	local d = driver("atlantis::/names/atlantis/atlantis.names", DE)
	eq(d:nameCls(nil), "de")
	eq(d:listLang().clsSource, "guess")
	ok(d:listLang().guess:find("de=", 1, true), d:listLang().guess)
	-- Cyrillic / Japanese script
	eq((driver("atlantis::/names/a/a.names", RU)):nameCls(nil), "ru")
	eq((driver("atlantis::/names/a/a.names", JA)):nameCls(nil), "ja")
	-- too few towns: no guess
	local few = { "Ulm", "Freiburg", "Neustadt" }
	local g, why = NM.guessCls(few)
	eq(g, nil)
	eq(why, "fewTowns")
	-- Polish names: no classifier tags them, no guess
	g, why = NM.guessCls(PL)
	eq(g, nil)
	eq(why, "unsure")
	-- bounded: GUESS_MAX names looked at
	local many = {}
	for i = 1, 5000 do many[i] = DE[(i % #DE) + 1] end
	eq((NM.guessCls(many)), "de")
	eq(NM.scriptShares(many).n, NM.GUESS_MAX)
end)

test("no country, no guess: the modded list's own towns.lua (game language folder first), unused names of it", function()
	local nl = "atlantis_names::/names/miasta/miasta.names"
	local files = { ["atlantis_names::/names/miasta/pl/towns.lua"] = { "Kraków", "Łódź", "Opole", "Zamość" } }
	local d, calls = driver(nl, PL, { lang = "en", files = files })
	eq(d:offshootCls({}), false, "list mode")
	eq(d:nameCls({}), "en", "composed names (budget, orphans) keep the old classifier")
	local L = d:listLang()
	eq(L.clsSource, "list")
	eq(L.listPath, "atlantis_names::/names/miasta/pl/towns.lua")
	eq(calls.list[1], "atlantis_names::/names/miasta/en/towns.lua", "the game language's folder first")
	ok(#calls.list <= NM.MAX_MOD_TRIES)
	local nm = d:offshootListName({}, { ["Kraków"] = true, ["Łódź"] = true }, 3)
	ok(nm == "Opole" or nm == "Zamość", tostring(nm))
	-- a detected country without a classifier (Poland): its folder is tried right after the game language's
	local d2, calls2 = driver("polska::/names/miasta/miasta.names", PL, { lang = "de", files = {} })
	eq(d2:offshootCls({}), "en", "nothing found: the old composed names")
	eq(calls2.list[1], "polska::/names/miasta/de/towns.lua")
	eq(calls2.list[2], "polska::/names/miasta/pl/towns.lua")
	eq(d2:listLang().clsSource, "fallback")
	ok(d2:listLang().why:find("noTownsFile", 1, true), d2:listLang().why)
	eq(#calls2.list, NM.MAX_MOD_TRIES, "capped")
	-- once per session
	d2:offshootCls({})
	d2:nameCls({})
	eq(#calls2.list, NM.MAX_MOD_TRIES)
end)

test("towns.lua paths: only <modId>::/names/<dir>/<file> paths, deduplicated folders, capped", function()
	local p = NM.moddedTownPaths("m_x::/names/dir_1/file.names", "pt_BR", "pl")
	eq(p[1], "m_x::/names/dir_1/pt_BR/towns.lua")
	eq(p[2], "m_x::/names/dir_1/pt/towns.lua")
	eq(p[3], "m_x::/names/dir_1/pl/towns.lua")
	eq(p[4], "m_x::/names/dir_1/en/towns.lua")
	eq(#p, NM.MAX_MOD_TRIES)
	local seen = {}
	for _, x in ipairs(p) do
		ok(not seen[x], "dup " .. x)
		seen[x] = true
	end
	eq(#NM.moddedTownPaths("::/names/europe/europe.names", "en"), 0, "base: none")
	eq(#NM.moddedTownPaths("m::/names/a/b/c.names", "en"), 0, "deeper path: none")
	eq(#NM.moddedTownPaths(nil, "en"), 0)
	for _, x in ipairs(NM.moddedTownPaths("m::/names/a/b.names", "../x")) do ok(not x:find("..", 1, true), x) end
end)

test("an unreadable list (no engine read, garbage): the old composed names, no error", function()
	local d = driver("atlantis::/names/a/a.names", PL, { noListAt = true })
	eq(d:offshootCls({}), "en")
	eq(d:listLang().clsSource, "fallback")
	ok(d:listLang().why:find("noEngine", 1, true))
	-- a US region without a country (cannot come from a path today) still falls back to usa
	local d2 = driver("atlantis::/names/a/a.names", PL, { noListAt = true })
	d2.nameRegion = "US"
	eq(d2:nameCls({}), "usa")
	-- no list at all
	local d3 = driver(nil, DE)
	eq(d3:nameCls({}), "en")
	eq(d3:listLang().why, "noList")
end)

test("base lists: classifiers exactly as before, the list language code never consulted", function()
	local function base(nl, saved)
		local d, calls = driver(nl, DE, { files = {} })
		local a, b = d:nameCls(saved), d:offshootCls(saved)
		eq(#calls.list, 0, nl)
		eq(d:listLang().clsSource, "base")
		return a, b
	end
	local a, b = base("::/names/germany/germany.names", { nd = "de" })
	eq(a, "de")
	eq(b, "de")
	a, b = base("::/names/europe/europe.names", { nd = "fr" })
	eq(a, "fr")
	eq(b, "fr")
	a, b = base("::/names/europe/europe.names", {})
	eq(a, "en")
	a, b = base("::/names/asia/asia.names", {})
	eq(a, "en")
	eq(b, false)
	a, b = base("::/names/oceania/oceania.names", {})
	eq(b, "en")
	a, b = base("::/names/usa/usa.names", {})
	eq(a, "usa")
	a, b = base("::/names/poland/poland.names", { nd = "pl" })
	eq(b, false)
end)

test("the NAMELIST line: once at the driver's start, stable tokens", function()
	local lines = {}
	local nl = "german_cities_and_municipalities::/names/german_cities/german_cities.names"
	local ids = {}
	for i = 1, #DE do ids[i] = i end
	local E = { global = function() return { nameList = nl, climate = "dry" } end,
		modParams = function() return {}, {} end, year = function() return 1960 end, nowUs = function() return 0 end,
		log = function(l) lines[#lines + 1] = l end, towns = function() return ids end,
		name = function(id) return DE[id] end, gameTime = function() return 0 end, sendEvent = function() end,
		townListAt = function() error("no") end }
	local d = D.new(E, "[SQOT]")
	pcall(d.init, d, 0, nil)
	local n, line = 0, nil
	for _, l in ipairs(lines) do
		if l:find("NAMELIST", 1, true) then n, line = n + 1, l end
	end
	eq(n, 1, table.concat(lines, "\n"))
	for _, tok in ipairs({ "list=" .. nl, "base=false", "region=EU", "country=germany", "regionSource=nameList",
		"cls=de", "clsSource=country", "word=german" }) do
		ok(line:find(tok, 1, true), tok .. " in " .. line)
	end
	-- a base list
	lines = {}
	E.global = function() return { nameList = "::/names/europe/europe.names", climate = "temperate" } end
	d = D.new(E, "[SQOT]")
	pcall(d.init, d, 0, nil)
	local got = nil
	for _, l in ipairs(lines) do if l:find("NAMELIST", 1, true) then got = l end end
	ok(got and got:find("base=true", 1, true) and got:find("clsSource=base", 1, true) and got:find("cls=en", 1, true),
		tostring(got))
end)

test("guess accuracy on the real base lists (.cache/game, when there): 16-name maps, no wrong language", function()
	local dirB = here .. "../../.cache/game/base/content/names/"
	local function load(p)
		local ch = loadfile(dirB .. p .. "/towns.lua", "t", {})
		if ch == nil then return nil end
		local okL, l = pcall(ch)
		return okL and type(l) == "table" and l or nil
	end
	local want = { ["germany/de"] = "de", ["europe/de"] = "de", ["england/en"] = "en", ["usa/en"] = "en",
		["sweden/en"] = "sv", ["netherlands/en"] = "nl", ["france/en"] = "fr", ["poland/pl"] = false,
		["china/en"] = false, ["italy/en"] = false, ["spain/en"] = false, ["russia/ru"] = "ru" }
	local FULL = os.getenv("TEST_FULL") ~= nil
	local draws = FULL and 120 or 25
	local seed = 12345
	local function rnd(n)
		seed = (seed * 1103515245 + 12345) % 2147483648
		return 1 + (seed % n)
	end
	local keys = {}
	for k in pairs(want) do keys[#keys + 1] = k end
	table.sort(keys)
	local any = false
	for _, k in ipairs(keys) do
		local list = load(k)
		if list then
			any = true
			local right, wrong, none = 0, 0, 0
			for _ = 1, draws do
				local names = {}
				for i = 1, 16 do names[i] = list[rnd(#list)] end
				local g = NM.guessCls(names)
				if g == nil then none = none + 1
				elseif g == want[k] then right = right + 1
				else wrong = wrong + 1 end
			end
			print(string.format("  %-16s right=%d none=%d wrong=%d", k, right, none, wrong))
			ok(wrong <= math.max(1, math.floor(draws * 0.02)), k .. " wrong " .. wrong)
		end
	end
	if not any then print("  (no .cache/game: skipped)") end
end)

test("offshoot names on a modded list: German words on a German list, the list's names, then composed when used up", function()
	local T = ug_require(F.DIR .. "ot_terrain.lua")
	local function run(nameList, names, files)
		local lines = {}
		local ids, pos = {}, {}
		for i = 1, #names do ids[i] = i; pos[i] = { (i % 4) * 4000, math.floor(i / 4) * 4000 } end
		local sm = T.sampler(function() return 10 end, function() return false end, 0)
		local E = { nowUs = function() return 0 end, towns = function() return ids end,
			boxCentre = function(t) local p = pos[t]; if p then return p[1], p[2] end return nil end,
			name = function(t) return names[t] end, log = function(l) lines[#lines + 1] = l end,
			sampler = function() return sm end, year = function() return 1950 end,
			townListAt = function(p) if files and files[p] then return files[p] end error("nf") end }
		local d = D.new(E, "[T]")
		d.opts = { townNames = "landscape" }
		d.cfg = { climate = "temperate", nameList = nameList }
		d.nameRegion = (I.build({ nameList = nameList })).nameRegion
		local out = {}
		for k = 1, 3 do
			local site = { x = pos[k][1] + 700, y = pos[k][2] + 400, kind = "upper" }
			local nm, src = d:offshootName("district", { style = { seed = k }, sampler = sm }, k, site, pos[k],
				{ saved = {}, seed = k, count = 0, listSeed = k })
			out[#out + 1] = { nm, src }
			if nm then ids[#ids + 1] = #names + 1; names[#names + 1] = nm; pos[#names] = { site.x, site.y } end
		end
		return out, lines
	end
	local de = {}
	for i, n in ipairs(DE) do de[i] = n end
	local out = run("german_cities_and_municipalities::/names/german_cities/german_cities.names", de)
	local parts = {}
	for _, o in ipairs(out) do
		parts[#parts + 1] = tostring(o[1]) .. " [" .. tostring(o[2]) .. "]"
		ok(o[1] ~= nil, "a name")
		for _, en in ipairs({ "Heights", "Upper ", "Little ", " End", "Hill" }) do
			ok(not tostring(o[1]):find(en, 1, true), "no English word: " .. tostring(o[1]))
		end
	end
	print("  German list districts: " .. table.concat(parts, ", "))
	-- list mode: the list's unused names, then (used up) the old composed names, logged once
	local pl = {}
	for i, n in ipairs(PL) do pl[i] = n end
	local files = { ["atlantis::/names/m/en/towns.lua"] = { "Kraków", "Opole" } }
	local out2, lines = run("atlantis::/names/m/m.names", pl, files)
	eq(out2[1][1], "Opole")
	eq(out2[1][2], "list")
	ok(out2[2][1] ~= nil and out2[2][2] ~= "list", "used up: composed " .. tostring(out2[2][1]))
	local n = 0
	for _, l in ipairs(lines) do if l:find("NAMELIST", 1, true) and l:find("event=listUsedUp", 1, true) then n = n + 1 end end
	eq(n, 1)
end)

test("STREETS line with a town's §73 run audit: no error (shadowed `core`), the site survey `wide` untouched", function()
	-- (2026-10-17: Driver:streetsNote's local `core` (the core edge count) shadowed the ot_core module, so
	-- `core.wideAuditText` raised in the assess stage once a town had an audit, and the audit was stored as the town
	-- state's `wide`, the 2 km site survey the site classifier reads; test_demand's EU frontage run built nothing)
	local lines = {}
	local E = { log = function(l) lines[#lines + 1] = l end, nowUs = function() return 0 end }
	local d = D.new(E, "[SQOT]")
	d.opts = {}
	local s = d:townState(7)
	local survey = { survey = true }
	s.wide = survey
	s.wideRuns = { runs = 2, edges = 5, len = 400, short = 1, lone = 0, max = 250, by = { mod = 2 } }
	d.streetsUs = 0
	local okS, err = pcall(d.streetsNote, d, 7, { lots = { edges = 10 } }, { mod = 3, game = 4, core = 3 },
		D.STREETS_EVERY_S * 1e6 + 1)
	ok(okS, tostring(err))
	local got = nil
	for _, l in ipairs(lines) do if l:find("STREETS", 1, true) then got = l end end
	ok(got and got:find("wideRuns=2/5/400", 1, true), tostring(got))
	ok(s.wide == survey, "the site survey stays")
end)
