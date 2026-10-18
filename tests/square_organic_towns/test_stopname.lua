-- ot_stopname (unique, geographically relevant stop names, 2026-10-13): 500 stops across a map in every list language
-- give no duplicate and stay on theme; the specific parts (toward a neighbour, trees, works, compass, height, the own
-- town) and each language's grammar; tree species from model names; the driver names stops uniquely map-wide.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local SN = ug_require(F.DIR .. "ot_stopname.lua")
local NM = ug_require(F.DIR .. "ot_names.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local NAMES_DIR = here .. "../../.cache/game/base/content/names/"
local function loadList(path, dir, file)
	local chunk = loadfile(NAMES_DIR .. path .. "/" .. dir .. "/" .. (file or "streets.lua"), "t", {})
	if chunk == nil then return nil end
	local okL, list = pcall(chunk)
	if okL and type(list) == "table" then return list end
	return nil
end

local TOWNS = { "Ferryhill", "Haslemere", "Skegness", "Brentwood", "Ellesmere", "Windermere", "Sandhurst", "Verwood",
	"Ringwood", "Ampthill", "Fleetwood", "Darley", "Whitehill", "Budleigh", "Henley", "Ormskirk", "Kirkham", "Syston",
	"Hitchin", "Tisbury", "Stotfold", "Redruth", "Rushden", "Alsager", "Billingham" }
local SPECIES = { "oak", "ash", "beech", "birch", "pine", "willow", "hazel", "elm", "spruce", "palm" }
local INDS = { "works", "quarry", "farm", "mill" }

-- a random stop spot: the ot_names.stopThemes site plus the ot_stopname parts
local function randomSite(i, townName)
	local u = function(k) return rng.unit(i, k) end
	local site = {
		station = u("st") < 0.12 and 80 + 100 * u("st2") or nil,
		wet = u("wet") < 0.15 and "shore" or (u("wet") < 0.3 and "river" or nil),
		dz = (u("dz") - 0.3) * 40, ring = (u("ring") - 0.5) * 30, valleyTown = u("vt") < 0.2,
		forest = u("fo") < 0.3 and 0.6 + 0.4 * u("fo2") or 0.1,
		dist = 50 + 1500 * u("dist"), radius = 600,
	}
	site.seed = i * 7919
	site.town = townName
	site.high = site.dz >= SN.HIGH_DZ
	-- (the driver's list: the town's read, biggest first, then the climate's defaults; willow / alder by the water)
	local tally = {}
	for k = 1, 3 do tally[SPECIES[1 + math.floor(u("tr" .. k) * #SPECIES)]] = 10 * k end
	site.trees = SN.treesFor(tally, "::/climates/temperate/temperate.clima", site.wet ~= nil, "en")
	if site.dist >= SN.COMPASS_MIN_M then site.compass = ({ "n", "e", "s", "w" })[1 + math.floor(u("cp") * 4)] end
	if site.dist >= 400 and u("tw") < 0.4 then site.toward = TOWNS[1 + math.floor(u("tw2") * #TOWNS)] end
	if u("ind") < 0.12 then site.ind = INDS[1 + math.floor(u("ind2") * #INDS)] end
	return site
end

local function genSet(L, th)
	local set = {}
	for _, g in ipairs((L.gens and L.gens[th]) or {}) do set[type(g) == "table" and g[1] or g] = true end
	return set
end

local LISTS = { en = { "europe", "en" }, usa = { "usa", "en" }, de = { "europe", "de" }, fr = { "europe", "fr" },
	it = { "europe", "it" }, es = { "europe", "es" }, nl = { "europe", "nl" }, sv = { "europe", "sv" }, nb = { "europe", "nb" },
	ru = { "europe", "ru" }, ja = { "japan", "ja" }, ja_r = { "japan", "en" }, pt = { "portugal", "en" }, ru_r = { "russia", "en" } }

test("500 stops across a map: no duplicate, every stop named, on theme (every list language)", function()
	local langs = {}
	for cls in pairs(SN.LANG) do langs[#langs + 1] = cls end
	table.sort(langs)
	for _, cls in ipairs(langs) do
		local L = SN.LANG[cls]
		local lst = LISTS[cls]
		local streets = lst and loadList(lst[1], lst[2]) or nil
		local used, cache = {}, {}
		local named, allUsed, kinds, offTheme = 0, 0, {}, {}
		local minLeft = math.huge
		local fallback = 0
		for i = 1, 500 do
			local town = TOWNS[1 + (i % #TOWNS)]
			local site = randomSite(i, town)
			local themes = SN.themesFor(NM.stopThemes(site), site)
			local name, th, info = SN.pick(cls, themes, site, streets, used, cache)
			if name == nil then
				allUsed = allUsed + 1
				print("      " .. cls .. ": no unique name for themes " .. table.concat(themes, ",") .. " total " .. tostring(info and info.total))
			else
				ok(not used[name], cls .. ": duplicate " .. name)
				used[name] = true
				named = named + 1
				kinds[info.kind] = (kinds[info.kind] or 0) + 1
				if info.left < minLeft then minLeft = info.left end
				local onTheme = false
				for _, t in ipairs(themes) do if t == th then onTheme = true end end
				-- (the fallback themes: counted, a stop of a dry theme)
				if not onTheme and (th == "outskirts" or th == "centre") then
					onTheme, fallback = true, fallback + 1
				end
				if info.kind ~= "real" and info.kind ~= "solo" and info.kind ~= "toward" and info.kind ~= "indName" then
					onTheme = onTheme and genSet(L, th)[info.gen] == true
				end
				if not onTheme then offTheme[#offTheme + 1] = name .. "@" .. tostring(th) end
				ok(#name <= SN.MAX_LEN, name)
				ok(SN.chars(name) <= SN.MAX_CHARS, cls .. ": long " .. name)
			end
		end
		eq(allUsed, 0, cls .. ": stops left with the game's name")
		eq(#offTheme, 0, cls .. ": off theme " .. table.concat(offTheme, ", "))
		local kt = {}
		for k, v in pairs(kinds) do kt[#kt + 1] = k .. ":" .. v end
		table.sort(kt)
		ok(fallback <= 50, cls .. ": fallback names " .. fallback)
		print(string.format("%s: %d named, kinds %s, min left %d, fallback %d", cls, named, table.concat(kt, " "), minLeft, fallback))
	end
end)

test("specific parts: toward a neighbour, trees, works, compass, height, the own town (en)", function()
	local function first(site, themes, used)
		return SN.pick("en", themes, site, nil, used or {}, nil)
	end
	-- a stop facing Ferryhill on the outskirts: "Ferryhill Road" first
	local n, th, info = first({ seed = 1, toward = "Ferryhill", dist = 900, town = "Haslemere" }, { "outskirts" })
	eq(n, "Ferryhill Road"); eq(th, "outskirts"); eq(info.kind, "toward")
	-- forest of beech: a beech name among the first composed ones (after the stand-alone names)
	local c = SN.candidates("en", { "forest" }, { seed = 5, trees = { "beech" }, town = "Haslemere" })
	local firstComposed = nil
	for _, e in ipairs(c) do if e.kind ~= "solo" and e.kind ~= "real" then firstComposed = e break end end
	ok(firstComposed and firstComposed.name:find("^Beech "), firstComposed and firstComposed.name)
	-- the own town on the shore ("Haslemere Quay") is a candidate; works near the outskirts first after toward
	local shore = SN.candidates("en", { "shore" }, { seed = 2, town = "Haslemere" })
	local has = false
	for _, e in ipairs(shore) do if e.name == "Haslemere Quay" then has = true end end
	ok(has, "Haslemere Quay")
	n, th, info = first({ seed = 3, ind = "quarry", dist = 900 }, { "outskirts" }, { ["Green Lane"] = true, ["The Green"] = true,
		["Field Lane"] = true, ["Meadow Way"] = true })
	ok(n:find("^Quarry ") or n:find("^Pit "), n)
	-- compass and height
	c = SN.candidates("en", { "hill" }, { seed = 4, compass = "n", high = true })
	local north, upper = false, false
	for _, e in ipairs(c) do
		if e.name:find("^North ") then north = true end
		if e.name:find("^Upper ") or e.name:find("^Top ") then upper = true end
	end
	ok(north and upper)
	-- willow first by the water
	local tr = SN.treesFor({ oak = 50, pine = 20 }, "::/climates/temperate/temperate.clima", true, "en")
	eq(tr[1], "willow"); eq(tr[4], "oak"); eq(tr[5], "pine")
	tr = SN.treesFor(nil, "::/climates/dry/dry.clima", false, "en")
	eq(tr[1], "pine"); eq(tr[2], "olive")
	tr = SN.treesFor(nil, nil, false, "ja")
	eq(tr[2], "cedar")
end)

test("grammar per language: compounds, Romance phrases, gendered adjectives, concatenation", function()
	local function names(cls, th, site)
		local set = {}
		for _, e in ipairs(SN.candidates(cls, { th }, site)) do set[e.name] = true end
		return set
	end
	local de = names("de", "forest", { seed = 1, trees = { "oak" }, compass = "n" })
	ok(de["Eichenweg"] and de["Eichenhain"] and de["Nordweg"], "de compounds")
	ok(not names("de", "hill", { seed = 1 })["Bergberg"], "no Bergberg")
	local deOut = names("de", "outskirts", { seed = 1, toward = "Ulm" })
	ok(deOut["Ulmer Strasse"], "Ulmer Strasse")
	ok(names("de", "outskirts", { seed = 1, toward = "Bad Ems" })["Strasse nach Bad Ems"])
	local fr = names("fr", "forest", { seed = 1, trees = { "oak" } })
	ok(fr["Allée des Chênes"] and fr["Chemin des Chênes"], "fr phrase")
	local frHill = names("fr", "hill", { seed = 1, high = true })
	ok(frHill["Rue Haute"] and frHill["Chemin Haut"], "fr gendered height")
	ok(names("fr", "outskirts", { seed = 1, toward = "Orléans" })["Route d'Orléans"], "fr elision")
	local ru = names("ru", "forest", { seed = 1, trees = { "pine" } })
	ok(ru["Сосновая улица"] and ru["Сосновый переулок"], "ru agreement")
	ok(not ru["Сосновый улица"], "ru: no wrong gender")
	ok(names("ru", "outskirts", { seed = 1, toward = "Москва" })["Дорога на Москву"], "ru accusative")
	local sv = names("sv", "outskirts", { seed = 1, compass = "n", trees = { "oak" } })
	ok(sv["Norra vägen"] and sv["Ekvägen"], "sv")
	ok(names("sv", "outskirts", { seed = 1, toward = "Stockholm" })["Stockholmsvägen"])
	ok(names("sv", "outskirts", { seed = 1, toward = "Uppsala" })["Uppsalavägen"])
	local nb = names("nb", "outskirts", { seed = 1, compass = "n" })
	ok(nb["Nordre vei"], "nb indefinite after a compass word")
	local ja = names("ja", "hill", { seed = 1, trees = { "cherry" } })
	ok(ja["桜ヶ丘"] and ja["桜坂"], "ja")
	local jr = names("ja_r", "hill", { seed = 1, trees = { "cherry" } })
	ok(jr["Sakuragaoka"] and jr["Sakurazaka"], "ja_r")
	local it = names("it", "outskirts", { seed = 1, toward = "Firenze", compass = "e" })
	ok(it["Via Firenze"] and it["Via Orientale"], "it")
	local usa = names("usa", "hill", { seed = 1, trees = { "oak" } })
	ok(usa["Oak Heights"] and usa["Oak Overlook"], "usa")
end)

test("tree species from the base tree model names", function()
	eq(SN.species("vegetation/trees/shgl_oak_01/shgl_oak_01.mdl"), "oak")
	eq(SN.species("vegetation/trees/brleaf_03/brleaf_03.mdl"), "beech")
	eq(SN.species("vegetation/trees/confr_02/confr_02_boost.mdl"), "fir")
	eq(SN.species("vegetation/trees/plm_01/plm_01.mdl"), "palm")
	eq(SN.species("vegetation/trees/cts_01/cts_01.mdl"), nil)
	eq(SN.indKind("industry/clay_pit.con"), "quarry")
	eq(SN.indKind("industry/farm.con"), "farm")
	eq(SN.indKind("industry/steel_mill.con"), "works")
	eq(SN.indKind("industries/saw_mill/saw_mill.con"), "timber")
	eq(SN.indKind("industries/paper_mill/paper_mill.con"), "mill")
	eq(SN.indKind("industries/coal_mine/coal_mine.con"), "mine")
	eq(SN.indKind("industries/brewery/brewery.con"), "brewery")
	eq(SN.indKind("industries/forest/forest.con"), "timber")
	eq(SN.indShort("Budleigh Salterton Crop Farm", { "Budleigh", "Budleigh Salterton" }), "Crop Farm")
	eq(SN.indShort("Crop Farm", { "Budleigh" }), "Crop Farm")
	eq(SN.indKind("industry/oil_refinery.con"), "works")
	eq(SN.compass(0, 0, 0, 500), "n")
	eq(SN.compass(0, 0, -500, 100), "w")
end)

test("the run's 32 test stops (2026-10-13_2113): all distinct with the map-wide used set", function()
	-- (theme, dist, forest) of the run's STOPNAME lines: 6 x hill, 6 x forest, 6 x centre, 4 x shore, 6 x outskirts ...
	local spots = {}
	for i = 1, 6 do spots[#spots + 1] = { dz = 25, dist = 800, forest = 0.6 } end
	for i = 1, 6 do spots[#spots + 1] = { dist = 500, forest = 0.8 } end
	for i = 1, 6 do spots[#spots + 1] = { dist = 190 } end
	for i = 1, 4 do spots[#spots + 1] = { wet = "shore", dist = 600 } end
	for i = 1, 10 do spots[#spots + 1] = { dist = 900 } end
	local used, names = {}, {}
	local streets = loadList("europe", "en")
	for i, sp in ipairs(spots) do
		sp.seed, sp.town = i, TOWNS[1 + i % 6]
		local th = NM.stopThemes(sp)
		if #th == 0 then th = { "outskirts" } end
		local n = SN.pick("en", th, sp, streets, used, {})
		ok(n and not used[n], tostring(n))
		used[n] = true
		names[#names + 1] = n
	end
	print(table.concat(names, "; "))
end)

test("300 stops on one map mixed with game-named stops (streets.lua): 0 duplicates, composed names first", function()
	-- the game names every new stop with the next streets.lua name not in use (docs/findings/roads.md); 6 of 10 are
	-- player stops the mod renames against the whole map (used = every name on it, read live), the rest keep the game's
	for _, cls in ipairs({ "en", "de", "fr", "ja", "ru" }) do
		local lst = LISTS[cls]
		local streets = loadList(lst[1], lst[2]) or {}
		local map, cache, gi = {}, {}, 1
		local kinds, kept, ours = {}, 0, 0
		local function gameName()
			while gi <= #streets and map[streets[gi]] do gi = gi + 1 end
			local n = streets[gi] or ("Stop " .. gi)
			gi = gi + 1
			return n
		end
		local names = {}
		for i = 1, 300 do
			local g = gameName()
			map[g] = true
			names[i] = g
			if rng.unit(i, "player") < 0.6 then
				ours = ours + 1
				local site = randomSite(i + 7000, TOWNS[1 + (i % 6)])
				local name, _, info = SN.pick(cls, NM.stopThemes(site), site, streets, map, cache)
				if name == nil then
					kept = kept + 1
				else
					map[g] = nil
					map[name] = true
					names[i] = name
					kinds[info.kind] = (kinds[info.kind] or 0) + 1
				end
			end
		end
		local seen, dup = {}, 0
		for _, n in ipairs(names) do
			if seen[n] then dup = dup + 1 end
			seen[n] = true
		end
		eq(dup, 0, cls .. ": duplicates")
		ok(kept <= 3, cls .. ": stops left with the game's name " .. kept)
		ok((kinds.real or 0) + (kinds.solo or 0) <= 0.05 * ours, cls .. ": real / stand-alone names " .. ((kinds.real or 0) + (kinds.solo or 0)))
		local kt = {}
		for k, v in pairs(kinds) do kt[#kt + 1] = k .. ":" .. v end
		table.sort(kt)
		print(string.format("      %s: %d ours, kept %d, kinds %s", cls, ours, kept, table.concat(kt, " ")))
	end
end)

test("industry theme: a stop beside works / a quarry / a farm takes the industry's words, its own name first", function()
	local n, th, info = SN.pick("en", { "outskirts" }, { seed = 3, ind = "works", indName = "Steel Mill", dist = 900 }, nil, {})
	eq(th, "industry"); eq(n, "Steel Mill Gate"); eq(info.kind, "indName")
	n = SN.pick("en", { "outskirts" }, { seed = 3, ind = "works", indName = "Steel Mill" }, nil, { ["Steel Mill Gate"] = true, ["Steel Mill Road"] = true })
	ok(n:find("Works") or n:find("Foundry") or n:find("Forge") or n:find("Factory"), n)
	for kind, words in pairs({ quarry = "Quarry", farm = "Farm", mill = "Mill", brewery = "Brewery" }) do
		local c = SN.candidates("en", SN.themesFor({}, { ind = kind }), { seed = 9, ind = kind })
		local hit = false
		for i = 1, 6 do if c[i] and c[i].name:find(words) then hit = true end end
		ok(hit, kind .. ": " .. (c[1] and c[1].name or "-"))
	end
	-- every list language has the industry words for every kind
	for cls, L in pairs(SN.LANG) do
		for _, k in ipairs({ "works", "quarry", "mine", "farm", "mill", "brewery", "timber" }) do
			ok(L.ind and L.ind[k] and #L.ind[k] > 0, cls .. " ind " .. k)
		end
		ok(L.gens.industry and #L.gens.industry > 0 and L.fields and L.marks and L.lake, cls .. " parts")
		ok(SN.STATION[cls] ~= nil, cls .. " station names")
	end
	-- a lake shore: the lake's words, not the sea's
	local c = SN.candidates("en", { "shore" }, { seed = 2, lake = true })
	ok(c[1].name:find("Lake") or c[1].name:find("Mere") or c[1].name:find("Reed") or c[1].name:find("Boathouse"), c[1].name)
end)

test("stations beside an industry: <Town> Works / Docks, <Industry> Halt, unique", function()
	eq(SN.stationName("en", "Haslemere", "quarry", "Clay Pit", false, {}), "Haslemere Quarry")
	eq(SN.stationName("en", "Haslemere", "works", nil, true, {}), "Haslemere Docks")
	eq(SN.stationName("en", "Haslemere", "quarry", "Clay Pit", false, { ["Haslemere Quarry"] = true }), "Clay Pit Halt")
	eq(SN.stationName("de", "Ulm", "mine", nil, false, {}), "Ulm-Zeche")
	eq(SN.stationName("fr", "Lyon", "farm", "Ferme", false, { ["Lyon-Ferme"] = true }), "Halte Ferme")
	eq(SN.stationName("en", "A", "farm", nil, false, { ["A Farm"] = true, ["A Docks"] = true }), nil)
end)

local OG = ug_require(F.DIR .. "ot_graph.lua")

-- a long street along y = 0 from x = -900 to 900 (edges of 100 m), a cross street at x = 0, a bend at x = 900
local function street()
	local g = OG.new()
	for i = 0, 18 do OG.addNode(g, 100 + i, -900 + i * 100, 0, 0, true) end
	for i = 0, 17 do OG.addEdge(g, 300 + i, 100 + i, 101 + i, "small", true) end
	OG.addNode(g, 200, 0, 300, 0, true)
	OG.addEdge(g, 400, 109, 200, "small", true)
	OG.addNode(g, 201, 900, 400, 0, true)
	OG.addEdge(g, 401, 118, 201, "small", true)   -- (a 90 deg turn: the section ends there)
	return g
end

test("sections: the chain through the stop's edge, straight on through junctions, not round a corner", function()
	local g = street()
	local sec = SN.section(g, 250, 5)
	ok(sec ~= nil, "a section")
	ok(sec.len >= 1700 and sec.len <= 1900, "len " .. sec.len)
	for _, p in ipairs(sec.pts) do ok(math.abs(p[2]) < 1e-6, "along the street, not up the cross street") end
	local sc = SN.section(g, 5, 150)
	ok(sc and sc.len <= 320, "the cross street alone")
	eq(SN.section(g, 0, 2000), nil, "no edge near")
end)

test("6 stops along one street: one base plus variants, all unique and short; a reloaded base is found", function()
	local g = street()
	for _, cls in ipairs({ "en", "usa", "de", "fr", "nl", "sv", "it", "es", "pt", "ja", "ja_r", "ru" }) do
		local used, bases = {}, {}
		local xs = { -500, -300, -100, 100, 300, 600 }
		local hs = { 20, 22, 30, 21, 12, 25 }
		local names = {}
		for i, x in ipairs(xs) do
			local sec = SN.section(g, x, 4)
			local base, along = SN.findBase(sec, bases, x, 4)
			local name, how
			if base then
				name, how = SN.sectionName(cls, base.b, { dir = SN.compass(base.x, base.y, x, 4), along = along,
					dz = hs[i] - base.h, core = math.abs(x) - math.abs(base.x), mark = i == 6 and "Chapel" or nil }, used)
			else
				name, how = (cls == "ja" and "港通り" or "Bay Road"), "base"
				bases[#bases + 1] = { b = name, x = x, y = 4, h = hs[i] }
			end
			ok(name ~= nil, cls .. ": stop " .. i .. " named")
			ok(not used[name], cls .. ": duplicate " .. tostring(name) .. " at " .. i .. " sec " .. tostring(sec and sec.len) .. " base " .. tostring(base))
			ok(SN.chars(name) <= SN.MAX_CHARS, name)
			used[name] = true
			names[#names + 1] = name .. "<" .. how .. ">"
		end
		eq(#bases, 1, cls .. ": one base")
		print("      " .. cls .. ": " .. table.concat(names, " | "))
	end
	-- a stop on the cross street: not on the section
	local sec = SN.section(g, 5, 200)
	eq(SN.findBase(sec, { { b = "Bay Road", x = -500, y = 4, h = 20 } }, 5, 200), nil)
end)

test("oddities: no long town words, no clumsy pairs (Bay Quay), every name at most 28 characters", function()
	eq(SN.townWord("Henley-in-Arden"), "Henley")
	eq(SN.townWord("Swanscombe and Greenhithe"), "Swanscombe")
	eq(SN.townWord("Ely"), "Ely")
	ok(SN.badPair("en", "Bay", "Quay"))
	ok(SN.badPair("en", "Pier", "Wharf"))
	ok(not SN.badPair("en", "Mill", "Lane"))
	local site = { toward = "Henley-in-Arden", town = "Swanscombe and Greenhithe", seed = 3, wet = "shore", dist = 900 }
	local themes = SN.themesFor({ "shore", "outskirts" }, site)
	for _, c in ipairs(SN.candidates("en", themes, site, nil, {})) do
		ok(not c.name:find("Arden", 1, true) and not c.name:find("Greenhithe", 1, true), c.name)
		ok(c.name ~= "Bay Quay" and c.name ~= "Pier Wharf", c.name)
		ok(SN.chars(c.name) <= SN.MAX_CHARS, c.name)
	end
end)

---------------------------------------------------------------------------
-- Bridge stops (2026-10-14, NEXT_PHASE_BRIEF 46): a stop on a bridge edge takes the bridge's names first

-- a bridge edge along x from (0, 0) to (120, 0), as ot_engine.stopBridge gives it (two chords)
local function bridgeInfo(read, on)
	local ends = { { 0, 0 }, { 120, 0 } }
	return { read = read, on = on, bridges = { { 0, 0, 60, 0, ends = ends, id = 7 }, { 60, 0, 120, 0, ends = ends, id = 7 } } }
end

test("bridge cue: the stop's own edge a bridge, near one when the edge read fails, just off the end, none", function()
	eq(SN.bridgeCue(bridgeInfo(true, true), 60, 3), "on")
	eq(select(2, SN.bridgeCue(bridgeInfo(true, true), 60, 3)), "edge")
	-- the stop's edge read and not a bridge: never "on", however near (a street beside / under it)
	eq(SN.bridgeCue(bridgeInfo(true, false), 60, 3), nil)
	-- the stop's edge not found: within BRIDGE_ON_M of a bridge edge counts
	local c, how = SN.bridgeCue(bridgeInfo(false, false), 60, SN.BRIDGE_ON_M - 1)
	eq(c, "on"); eq(how, "near")
	eq(SN.bridgeCue(bridgeInfo(false, false), 60, 30), nil, "beside the span, not on it, not at an end")
	-- off the bridge, near an end: Bridge End
	eq(SN.bridgeCue(bridgeInfo(true, false), 150, 2), "end")
	eq(SN.bridgeCue(bridgeInfo(false, false), -40, 5), "end")
	eq(SN.bridgeCue(bridgeInfo(true, false), 120 + SN.BRIDGE_END_M + 10, 0), nil)
	-- nothing read, garbage, NaN: no cue, no error
	eq(SN.bridgeCue(nil, 0, 0), nil)
	eq(SN.bridgeCue({ bridges = { { "a" }, { 0 / 0, 0, 1, 1, ends = { { 0 / 0, 0 } } } } }, 0, 0), nil)
	eq(SN.bridgeCue(bridgeInfo(false, false), 0 / 0, 0), nil)
end)

local function bridgeSite(i, cue, river, year)
	local s = randomSite(i, "Haslemere")
	s.bridge, s.riverName, s.year = cue, river, year
	return s
end

test("bridge stops: <River> Bridge, <Town> Bridge, Old / New Bridge by era, Bridge End; every list language", function()
	for cls in pairs(LISTS) do
		local nm, th, info = SN.pick(cls, NM.stopThemes(bridgeSite(1, "on", "Avon", 1880)), bridgeSite(1, "on", "Avon", 1880), nil, {})
		ok(nm ~= nil, cls .. ": named")
		eq(th, "bridge", cls .. ": the bridge theme first (" .. tostring(nm) .. ")")
		ok(info.kind:find("^bridge:"), cls .. " " .. tostring(info.kind))
		local e, the = SN.pick(cls, {}, bridgeSite(2, "end", "Avon", 1950), nil, {})
		eq(the, "bridge", cls .. ": the bridge end " .. tostring(e))
		eq(select(3, SN.pick(cls, {}, bridgeSite(2, "end", nil, 1950), nil, {})).gen, "end", cls)
		-- none twice (on the bridge, and just off it)
		for _, cue in ipairs({ "on", "end" }) do
			local seen = {}
			for _, b in ipairs(SN.bridgeNames(cls, bridgeSite(3, cue, "Avon", 1880))) do
				ok(not seen[b[1]], cls .. " twice: " .. b[1]); seen[b[1]] = true
			end
		end
		ok(SN.BRIDGE[cls] ~= nil, cls .. " has bridge forms")
	end
	local en = SN.bridgeNames("en", bridgeSite(1, "on", "Avon", 1880))
	eq(en[1][1], "Avon Bridge")
	eq(en[2][1], "Haslemere Bridge")
	eq(en[3][1], "Old Bridge", "the older form first before BRIDGE_OLD_YEAR")
	eq(SN.bridgeNames("en", bridgeSite(1, "on", "Avon", 1960))[3][1], "New Bridge")
	eq(SN.bridgeNames("en", bridgeSite(1, "on", nil, 1960))[1][1], "Haslemere Bridge", "no river name: the town's")
	eq(SN.bridgeNames("en", bridgeSite(1, "end", "Avon"))[1][1], "Bridge End")
	eq(SN.bridgeNames("de", bridgeSite(1, "on", "Lahn", 1880))[1][1], "Lahnbrücke")
	eq(SN.bridgeNames("de", bridgeSite(1, "end"))[1][1], "An der Brücke")
	eq(SN.bridgeNames("fr", bridgeSite(1, "on", "Orne"))[1][1], "Pont d'Orne")
	eq(SN.bridgeNames("ja", bridgeSite(1, "on", "多摩"))[1][1], "多摩橋")
	eq(SN.bridgeNames("ru", bridgeSite(1, "on", "Волга"))[1][1], "Мост через Волгу")
	eq(#SN.bridgeNames("en", bridgeSite(1, nil, "Avon")), 0, "no cue: no bridge names")
end)

test("bridge stops: two (and twenty) on the map get different names; the bridge stays the cue while names are left", function()
	for cls in pairs(LISTS) do
		local used, names = {}, {}
		for i = 1, 20 do
			local s = bridgeSite(10 + i, i % 3 == 0 and "end" or "on", "Avon", 1900)
			local nm, th = SN.pick(cls, NM.stopThemes(s), s, nil, used)
			ok(nm ~= nil, cls .. " " .. i)
			ok(not used[nm], cls .. ": duplicate " .. tostring(nm))
			used[nm] = true
			names[#names + 1] = nm
			if i <= 2 then eq(th, "bridge", cls .. " stop " .. i .. ": " .. tostring(nm)) end
		end
		ok(names[1] ~= names[2], cls .. ": " .. names[1] .. " / " .. names[2])
	end
end)

test("bridge stops: a stop not on a bridge keeps its name; the cue off changes nothing", function()
	for cls in pairs(LISTS) do
		for i = 1, 40 do
			local s = randomSite(100 + i, "Haslemere")
			local a = SN.pick(cls, NM.stopThemes(s), s, nil, {})
			s.bridge = SN.bridgeCue(bridgeInfo(true, false), 60, 500)
			eq(s.bridge, nil)
			eq(SN.pick(cls, NM.stopThemes(s), s, nil, {}), a, cls .. " " .. i)
		end
	end
end)

-- the driver: stopName with a fake engine (a stop on a bridge, beside one, and a failing edge read)
local D = ug_require(F.DIR .. "ot_driver.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

local function driverStop(stopBridge, x, y)
	local logs, named = {}, {}
	local E = { nowUs = function() return 0 end, year = function() return 1880 end,
		name = function(e) if e == 1 then return "Haslemere" end return e == 500 and "Game Stop" or nil end,
		stationGroup = function() return 500 end, groupStations = function() return { 42 } end,
		stationTown = function() return 1 end,
		sampler = function() return T.sampler(function() return 5 end, function() return false end, 0) end,
		stopBridge = stopBridge, log = function(l) logs[#logs + 1] = l end,
		setName = function(g, n, cb) named[g] = n; if cb then cb(true) end end, sendEvent = function() end }
	local d = D.new(E, "[T]")
	d.debug = function(_, what, f)
		local parts = { what }
		for _, kv in ipairs(f) do parts[#parts + 1] = tostring(kv[1]) .. "=" .. tostring(kv[2]) end
		logs[#logs + 1] = table.concat(parts, " ")
	end
	d.cfg = {}
	d.phase = "run"
	d.namesWaters = { { k = "r", x = 0, y = 0, s = "Avon" } }
	local st = d:townState(1)
	st.stats, st.pos, st.extR = { water = { kind = "river" } }, { 0, 0 }, 600
	local c = { on = true, cls = "en", streets = nil }
	local okR, err = pcall(d.stopName, d, { st = 42, g = 500, n = "Game Stop", x = x or 60, y = y or 2 }, c, { [42] = true }, 0)
	ok(okR, tostring(err))
	return named[500], logs
end

test("driver: a stop on a bridge edge gets a bridge name and bridge=1 on its STOPNAME line; a failing read falls back", function()
	local nm, logs = driverStop(function() return bridgeInfo(true, true) end)
	eq(nm, "Avon Bridge", table.concat(logs, " | "))
	local line = logs[#logs]
	ok(line:find("STOPNAME", 1, true) and line:find("bridge=1", 1, true) and line:find("bridgeRead=edge", 1, true), line)
	ok(line:find("river=Avon", 1, true), line)
	-- just off the bridge's end
	local nmE, logsE = driverStop(function() return bridgeInfo(true, false) end, 130, 2)
	eq(nmE, "Bridge End", table.concat(logsE, " | "))
	ok(logsE[#logsE]:find("bridge=end", 1, true), logsE[#logsE])
	-- the stop's edge not found, the stop over the bridge edge: on it all the same
	local nmN, logsN = driverStop(function() return bridgeInfo(false, false) end)
	eq(nmN, "Avon Bridge")
	ok(logsN[#logsN]:find("bridgeRead=near", 1, true), logsN[#logsN])
	-- the read throws: the stop's normal name, bridge=0 bridgeRead=fail, no error
	local plain = driverStop(nil, 300, 300)
	local nmF, logsF = driverStop(function() error("boom") end, 300, 300)
	eq(nmF, plain, "the same name as without the read")
	ok(nmF ~= nil and not nmF:find("Bridge", 1, true), tostring(nmF))
	ok(logsF[#logsF]:find("bridge=0", 1, true) and logsF[#logsF]:find("bridgeRead=fail", 1, true), logsF[#logsF])
	-- a stop not on a bridge (its edge read, no bridge near): bridge=0, its normal name
	local nmP, logsP = driverStop(function() return { read = true, on = false, bridges = {} } end, 300, 300)
	eq(nmP, plain)
	ok(logsP[#logsP]:find("bridge=0 bridgeRead=edge", 1, true), logsP[#logsP])
end)

-- climate fit (2026-10-14, NEXT_PHASE_BRIEF 49 "stop names' climate fit"; ot_climate)
local CL = ug_require(F.DIR .. "ot_climate.lua")
local CLIMA = { tropical = "::/climates/tropical/tropical.clima", dry = "::/climates/dry/dry.clima",
	subarctic = "::/climates/subarctic/subarctic.clima", temperate = "::/climates/temperate/temperate.clima" }

-- a random spot on a map of climate ck: the town's read holds temperate trees too (the generic models' spread)
local function climateSite(i, ck, cls)
	local s = randomSite(i, "Haslemere")
	local tally = { oak = 30, birch = 20, pine = 15, palm = 10, beech = 5 }
	s.trees = SN.treesFor(tally, CLIMA[ck], s.wet ~= nil, cls)
	s.climate = SN.climateKey(CLIMA[ck])
	-- (more outskirts / forest / shore spots: the meadow, tree and lake words live there)
	if i % 3 == 0 then s.dist, s.forest = 1400, 0.9 end
	if i % 5 == 0 then s.wet = "shore" end
	return s
end

local function strip(nm, s)
	local out = nm
	for _, p in ipairs({ s.town, s.toward }) do
		if p then
			local a, b = out:find(p, 1, true)
			if a then out = out:sub(1, a - 1) .. " " .. out:sub(b + 1) end
		end
	end
	return out
end

test("climate key: subarctic too; trees the climate rules out are left out of a stop's species", function()
	eq(SN.climateKey(CLIMA.subarctic), "subarctic")
	eq(SN.climateKey(CLIMA.tropical), "tropical")
	eq(SN.climateKey(CLIMA.dry), "dry")
	eq(SN.climateKey(nil), "temperate")
	local tally = { oak = 30, birch = 20, pine = 15, palm = 10, willow = 5 }
	local t = table.concat(SN.treesFor(tally, CLIMA.tropical, true, "en"), ",")
	ok(not t:find("oak") and not t:find("birch") and not t:find("pine"), "tropical: " .. t)
	ok(t:find("palm", 1, true) ~= nil, "tropical keeps palm: " .. t)
	local d = table.concat(SN.treesFor(tally, CLIMA.dry, true, "en"), ",")
	ok(not d:find("willow") and not d:find("birch"), "dry: " .. d)
	local s = table.concat(SN.treesFor(tally, CLIMA.subarctic, false, "en"), ",")
	ok(not s:find("palm") and s:find("birch", 1, true), "subarctic: " .. s)
	ok(#SN.treesFor({}, CLIMA.tropical, false, "ja") > 0, "a ja list on a tropical map still has trees")
	-- "First Street" is no fir, "Alderman Road" no alder
	eq(CL.wordMisfit("First Street", "tropical", "usa"), nil)
	eq(CL.wordMisfit("Alderman Road", "dry", "en"), nil)
	eq(CL.wordMisfit("Oak Lane", "tropical", "en"), "oak")
end)

local FULL = os.getenv("TEST_FULL") ~= nil
local function climateFit(ck)
	local W = { tropical = { "oak", "birch", "pine", "beech", "spruce", "larch", "maple", "fir", "elm", "hazel" },
		dry = { "marsh", "fen", "meadow", "moss", "bog", "mere", "swamp" }, subarctic = { "palm", "coral", "lagoon", "lemon", "olive" } }
	do
		local bad, n, total = {}, 0, 0
		for cls in pairs(LISTS) do
			local used = {}
			local L = SN.LANG[cls]
			-- this language's own words for the trees the climate rules out
			local treeWords = {}
			for _, sp in ipairs(W[ck]) do
				if L.tree and type(L.tree[sp]) == "string" then treeWords[#treeWords + 1] = L.tree[sp] end
			end
			for i = 1, (FULL and 80 or 40) do
				local s = climateSite(i, ck, cls)
				local nm, _, info = SN.pick(cls, NM.stopThemes(s), s, nil, used)
				if nm then
					used[nm] = true
					total = total + 1
					local core = strip(nm, s)
					local w = CL.wordMisfit(core, ck, cls)
					if w then bad[#bad + 1] = cls .. ":" .. nm .. "(" .. w .. ")" end
					for _, tw in ipairs(treeWords) do
						if cls ~= "ja" and core:find(tw, 1, true) then bad[#bad + 1] = cls .. ":" .. nm .. "[" .. tw .. "]" end
					end
					-- English words in an English name, whole words: no "Oak", "Marsh", "Meadow", "Palm"
					if cls == "en" or cls == "usa" then
						for word in core:lower():gmatch("%a+") do
							for _, x in ipairs(W[ck]) do if word == x or word == x .. "s" then bad[#bad + 1] = nm end end
						end
					end
					n = n + ((info.drop and (info.drop.climate or 0) > 0) and 1 or 0)
				end
			end
		end
		print(string.format("      %-9s %d stops, %d with climate-dropped candidates, misfits %d", ck, total, n, #bad))
		eq(#bad, 0, ck .. ": " .. table.concat(bad, " | "))
		if ck ~= "subarctic" then ok(n > 0, ck .. ": the filter dropped candidates") end
	end
end

test("a tropical stop never draws a temperate tree (every list language)", function() climateFit("tropical") end)
test("a dry stop never draws marsh / fen / meadow (every list language)", function() climateFit("dry") end)
test("a subarctic stop never draws a palm (every list language)", function() climateFit("subarctic") end)

test("the survey's water read: no lake words without a lake near; with a lake the shore keeps them", function()
	for cls in pairs(LISTS) do
		local withLake, used = 0, {}
		for i = 1, 60 do
			local s = randomSite(500 + i, "Haslemere")
			s.wet, s.lake = "shore", true
			local nm = SN.pick(cls, { "shore" }, s, nil, used)
			if nm then used[nm] = true; if CL.lakeMisfit(strip(nm, s), cls) then withLake = withLake + 1 end end
		end
		ok(withLake > 0, cls .. ": a lake shore keeps its lake words")
		local bad = {}
		used = {}
		for i = 1, 60 do
			local s = randomSite(500 + i, "Haslemere")
			s.wet, s.lake, s.noLake = "shore", false, true
			local nm = SN.pick(cls, { "shore" }, s, nil, used)
			if nm then
				used[nm] = true
				local w = CL.lakeMisfit(strip(nm, s), cls)
				if w then bad[#bad + 1] = nm .. "(" .. w .. ")" end
			end
		end
		eq(#bad, 0, cls .. " (no lake): " .. table.concat(bad, " | "))
	end
	-- an English sea shore: no Lakeshore Drive
	local s = randomSite(3, "Haslemere")
	s.wet, s.noLake = "shore", true
	for _, c in ipairs((SN.candidates("usa", { "shore" }, s, nil, {}))) do
		ok(not c.name:find("Lake", 1, true), c.name)
	end
end)

test("bridge stops unchanged by the climate fit; map-wide uniqueness kept", function()
	for cls in pairs(LISTS) do
		for i = 1, 6 do
			local s = bridgeSite(20 + i, i % 2 == 0 and "end" or "on", "Oakburn", 1880)
			local a, at = SN.pick(cls, NM.stopThemes(s), s, nil, {})
			s.climate, s.noLake = "tropical", true
			local b, bt = SN.pick(cls, NM.stopThemes(s), s, nil, {})
			eq(b, a, cls .. " " .. i)
			eq(bt, at)
		end
		-- 60 tropical stops on one map: no duplicate
		local used = {}
		for i = 1, 60 do
			local s = climateSite(1000 + i, "tropical", cls)
			local nm = SN.pick(cls, NM.stopThemes(s), s, nil, used)
			if nm then
				ok(not used[nm], cls .. ": duplicate " .. nm)
				used[nm] = true
			end
		end
	end
end)

test("driver: a tropical stop by a 'lake' the survey doesn't know: lakeFix, no lake words, climate on the line", function()
	local logs, named = {}, {}
	local E = { nowUs = function() return 0 end, year = function() return 1930 end,
		name = function(e) if e == 1 then return "Haslemere" end return e == 500 and "Game Stop" or nil end,
		stationGroup = function() return 500 end, groupStations = function() return { 42 } end,
		stationTown = function() return 1 end,
		sampler = function() return T.sampler(function() return 5 end, function(x) return x > 40 end, 0) end,
		log = function(l) logs[#logs + 1] = l end,
		setName = function(g, n, cb) named[g] = n; if cb then cb(true) end end, sendEvent = function() end }
	local d = D.new(E, "[T]")
	d.cfg = { climate = CLIMA.tropical }
	d.phase = "run"
	-- the map survey: no water body anywhere (a 20 x 20 grid of 200 m cells)
	d.mapShape = { cells = {}, bl = {}, bc = {}, rl = {}, cs = 200, x0 = -2000, y0 = -2000, nx = 20, ny = 20 }
	local st = d:townState(1)
	st.stats, st.pos, st.extR = { water = { kind = "coast", body = "lake" } }, { 0, 0 }, 600
	st.species = { oak = 40, birch = 10 }
	local c = { on = true, cls = "en", streets = nil }
	local okR, err = pcall(d.stopName, d, { st = 42, g = 500, n = "Game Stop", x = 30, y = 2 }, c, { [42] = true }, 0)
	ok(okR, tostring(err))
	local nm = named[500]
	ok(nm ~= nil, table.concat(logs, " | "))
	eq(CL.lakeMisfit(nm, "en"), nil, nm)
	eq(CL.wordMisfit(nm:gsub("Haslemere", ""), "tropical", "en"), nil, nm)
	local line = logs[#logs]
	ok(line:find("climate=tropical", 1, true) and line:find("noLake=true", 1, true) and line:find("lakeFix=noLake", 1, true)
		and line:find("misfit=climate:", 1, true), line)
end)
