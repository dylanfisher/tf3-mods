-- ot_names (landscape names, 2026-10-13): base list detection, language folder, name classifier per language (also on
-- the real base lists when .cache/game is there), town tags, the assignment (unique, deterministic, best fit, plain,
-- notDrawn, caps), satellites, industry prefix renames, the saved flag / stop queue, stop themes and picks, and the
-- driver's names phase and stop naming against a fake engine.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local NM = ug_require(F.DIR .. "ot_names.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

local NAMES_DIR = here .. "../../.cache/game/base/content/names/"

local function loadList(path, dir, file)
	local chunk = loadfile(NAMES_DIR .. path .. "/" .. dir .. "/" .. (file or "towns.lua"), "t", {})
	if chunk == nil then return nil end
	local ok, list = pcall(chunk)
	if ok and type(list) == "table" then return list end
	return nil
end

local function pool(list, cls)
	local p = NM.newPool(list, cls)
	NM.classifyStep(p)
	return p
end

local function has(tags, tag) return tags ~= nil and (tags[tag] or 0) >= NM.MIN_TAG end

test("basePath: base lists only, another mod's set and unknown paths are skipped", function()
	eq(NM.basePath("::/names/europe/europe.names"), "europe")
	eq(NM.basePath("::/names/usa/usa.names"), "usa")
	local p, why = NM.basePath("square_names_us_texas::/names/usa/usa.names")
	eq(p, nil)
	eq(why, "notBase")
	p, why = NM.basePath("::/names/atlantis/atlantis.names")
	eq(why, "unknownList")
	p, why = NM.basePath(nil)
	eq(why, "noList")
end)

test("pickDir: the game language's folder when the towns are in it, else the best match, else none", function()
	eq(NM.dirForLang("europe", "de"), "de")
	eq(NM.dirForLang("europe", "pt_BR"), "en")
	eq(NM.dirForLang("portugal", "pt_BR"), "pt_pt")
	eq(NM.dirForLang("europe", "en_US"), "en")
	local d, src = NM.pickDir("europe", "de", { de = 10, en = 0 }, 10)
	eq(d, "de"); eq(src, "lang")
	d, src = NM.pickDir("europe", "en", { de = 9, en = 1 }, 10)
	eq(d, "de"); eq(src, "match")
	d, src = NM.pickDir("europe", nil, { de = 2, en = 1 }, 10)
	eq(d, nil); eq(src, "noListMatch")
	eq(NM.langDirs("europe")[1], "en")
	eq(#NM.langDirs("europe"), 10)
	eq(NM.classOf("france", "en"), "fr")
	eq(NM.classOf("china", "en"), nil)
end)

test("classify: endings and prefixes per language", function()
	local function tags(n, cls) return NM.classify(n, cls) end
	ok(has(tags("Bournemouth", "en"), "estuary"))
	ok(has(tags("Oxford", "en"), "ford"))
	ok(has(tags("Stalybridge", "en"), "bridge") and not has(tags("Stalybridge", "en"), "hill"))
	ok(has(tags("Henley-on-Thames", "en"), "river") and has(tags("Henley-on-Thames", "en"), "forest"))
	ok(has(tags("Westcliff-on-Sea", "en"), "coast") and not has(tags("Westcliff-on-Sea", "en"), "river"))
	ok(has(tags("Skegness", "en"), "headland"))
	ok(has(tags("Windermere", "en"), "lake"))
	ok(has(tags("Rochdale", "en"), "valley"))
	ok(has(tags("Market Deeping", "en"), "market"))
	ok(has(tags("Axminster", "en"), "market"))
	ok(not has(tags("Henley", "en"), "island"), "-ley is no -ey island")
	eq(tags("Bacup", "en"), nil)
	ok(has(tags("Colorado Springs", "usa"), "valley"))
	ok(has(tags("Daytona Beach", "usa"), "coast"))
	ok(has(tags("Lake Charles", "usa"), "lake"))
	ok(has(tags("Mount Vernon", "usa"), "hill"))
	ok(has(tags("Zweibrücken", "de"), "bridge"), "umlaut endings (ASCII-only lower case)")
	ok(has(tags("Erfurt", "de"), "ford"))
	ok(has(tags("Wuppertal", "de"), "valley"))
	ok(has(tags("Bremerhaven", "de"), "coast"))
	ok(has(tags("Warnemünde", "de"), "estuary"))
	ok(has(tags("Krakow am See", "de"), "lake"))
	ok(has(tags("Boulogne-sur-Mer", "fr"), "coast") and not has(tags("Boulogne-sur-Mer", "fr"), "river"))
	ok(has(tags("Châlons-sur-Marne", "fr"), "river"))
	ok(has(tags("Pont-Audemer", "fr"), "bridge"))
	ok(has(tags("Montpellier", "fr"), "hill"))
	ok(has(tags("Porto Recanati", "it"), "coast"))
	ok(has(tags("Montecreto", "it"), "hill"))
	ok(has(tags("Lloret de Mar", "es"), "coast"))
	ok(has(tags("Aranda de Duero", "es"), "river"))
	ok(has(tags("Zaandam", "nl"), "river"))
	ok(has(tags("Hoogeveen", "nl"), "marsh"))
	ok(has(tags("Larvik", "nb"), "coast"))
	ok(has(tags("Leirfjord", "nb"), "coast"))
	ok(has(tags("Hyltebruk", "sv"), nil) == false)
	ok(has(tags("Lidköping", "sv"), "market"))
	ok(has(tags("Yokohama", "ja_r"), "coast"))
	ok(has(tags("Hiroshima", "ja_r"), "island"))
	ok(has(tags("川口市", "ja"), "river") and has(tags("川口市", "ja"), "estuary"))
	ok(has(tags("富士市", "ja"), "plain") == false)
	ok(has(tags("Белогорск", "ru"), "hill"))
	ok(has(tags("Заозёрный", "ru"), "lake"))
	ok(has(tags("Ust-Ilimsk", "ru_r"), "estuary"))
	eq(NM.classify("Changchun", nil), nil)
	eq(NM.lower("ZWEIBRÜCKEN"), "zweibrÜcken")
end)

test("real base lists: usable lists and their tag counts (fixtures: .cache/game/base/content/names)", function()
	local want = { { "europe", "en", true }, { "england", "en", true }, { "europe", "de", true }, { "germany", "de", true },
		{ "europe", "fr", true }, { "france", "en", true }, { "italy", "en", true }, { "spain", "en", true },
		{ "netherlands", "en", true }, { "norway", "en", true }, { "sweden", "en", true }, { "usa", "en", true },
		{ "japan", "en", true }, { "japan", "ja", true }, { "europe", "ru", true }, { "portugal", "pt_pt", false },
		{ "russia", "ru", false } }
	local seen = 0
	for _, w in ipairs(want) do
		local list = loadList(w[1], w[2])
		if list then
			seen = seen + 1
			local p = pool(list, NM.classOf(w[1], w[2]))
			local u = NM.usable(p)
			eq(u, w[3], w[1] .. "/" .. w[2])
			print(string.format("%-12s %-5s pool %4d tagged %4d  %s", w[1], w[2], #p.names, p.tagged, NM.countsText(p)))
		end
	end
	if seen == 0 then print("no .cache/game names: skipped") end
	-- lists without a classifier: noTags
	eq(NM.classOf("china", "zh_CN"), nil)
	eq(NM.classOf("korea", "ko"), nil)
	eq(NM.classOf("oceania", "en"), nil)
	eq(NM.classOf("poland", "pl"), nil)
end)

-- a pool of English names, a few per tag
local EN = { "Taunton", "Bilston", "Norton", "Seaford", "Whitehaven", "Newhaven", "Bournemouth", "Exmouth", "Oxford",
	"Stafford", "Stockbridge", "Tonbridge", "Wimbledon", "Haslemere", "Windermere", "Rochdale", "Ilfracombe", "Henley",
	"Bexley", "Lyndhurst", "Skegness", "Sheerness", "Radcliffe", "Clifton", "Market Deeping", "Axminster", "Wakefield",
	"Driffield", "Felton", "Potton", "Hetton", "Filton", "Surbiton", "Holme", "Chertsey", "Holbeach", "Carlton",
	"Southsea", "Withernsea", "Burnham", "Bacup", "Frome", "Jarrow", "Elland", "Crowle", "Halesowen", "Pershore",
	"Liskeard", "Stonehouse", "Shepshed", "Thornaby-on-Tees", "Ambleside", "Ashby" }

local function enPool() return pool(EN, "en") end

local function town(id, name, w, o)
	o = o or {}
	local ranked = {}
	for _, t in ipairs(NM.TAGS) do if w[t] then ranked[#ranked + 1] = { t, w[t] } end end
	table.sort(ranked, function(a, b) return a[2] > b[2] end)
	return { id = id, name = name, x = o.x or id * 3000, y = o.y or 0, cap = o.cap or 1000, ranked = ranked, weights = w,
		character = o.character }
end

test("assign: best fit per site, game names kept when they fit or nothing fits better", function()
	local p = enPool()
	local towns = {
		town(1, "Taunton", { coast = 1 }),
		town(2, "Bilston", { river = 1, ford = 0.8, bridge = 0.8 }),
		town(3, "Norton", { hill = 1 }),
		town(4, "Seaford", { plain = 0.9 }),
		town(5, "Felton", { plain = 0.9 }),
		town(6, "Whitehaven", { coast = 1 }),
	}
	-- (the word budget, test_nameshape, would allow one "-haven" per 8 towns: off here)
	local res, st = NM.assign(towns, p, { seed = 7, budget = false })
	local by = {}
	for _, r in ipairs(res) do by[r.id] = r end
	ok(has(NM.classify(by[1].new, "en"), "coast"), "coast town -> " .. by[1].new)
	ok(by[1].match:sub(1, 4) == "tag:")
	local t2 = NM.classify(by[2].new, "en")
	ok(has(t2, "ford") or has(t2, "bridge") or has(t2, "river"), "river town -> " .. by[2].new)
	ok(has(NM.classify(by[3].new, "en"), "hill"), "hill town -> " .. by[3].new)
	-- Seaford on a dry plain contradicts (coast + ford): a plain name instead
	ok(by[4].new ~= "Seaford" and NM.score(NM.classify(by[4].new, "en"), towns[4].weights) >= 0, "plain town -> " .. by[4].new)
	eq(by[5].new, "Felton"); eq(by[5].match, "kept")
	eq(by[6].new, "Whitehaven", "a fitting game name stays")
	-- unique
	local seen = {}
	for _, r in ipairs(res) do
		ok(not seen[r.new], "unique " .. r.new)
		seen[r.new] = true
	end
	ok(st.renamed >= 4)
	-- deterministic
	local res2 = NM.assign(towns, p, { seed = 7, budget = false })
	for i, r in ipairs(res) do eq(res2[i].new, r.new) end
end)

test("assign: names already on the map are never taken; player-renamed towns stay (notDrawn)", function()
	local p = enPool()
	local towns = { town(1, "Taunton", { coast = 1 }), town(2, "My Town", { coast = 1 }) }
	-- every coast name but one is reserved (other towns / names on the map)
	local reserved = { Whitehaven = true, Newhaven = true, Bournemouth = true, Exmouth = true, Southsea = true, Withernsea = true,
		Skegness = true }
	local res = NM.assign(towns, p, { seed = 1, reserved = reserved })
	eq(res[2].match, "notDrawn"); eq(res[2].new, "My Town")
	ok(not reserved[res[1].new], res[1].new)
end)

test("assign: rarest tags first, character towns before them; caps on towns and candidates", function()
	local p = enPool()
	-- two coast towns, one island town with a single island name in the pool... the island town goes first
	local towns = { town(1, "Taunton", { lake = 1 }), town(2, "Norton", { lake = 1 }), town(3, "Felton", { lake = 1 },
		{ character = true }) }
	local res = NM.assign(towns, p, { seed = 3, budget = false })
	ok(has(NM.classify(res[3].new, "en"), "lake"), "the character town gets a lake name: " .. res[3].new)
	local lakes = 0
	for _, r in ipairs(res) do if has(NM.classify(r.new, "en"), "lake") then lakes = lakes + 1 end end
	eq(lakes, 2, "only two lake names in the pool")
	-- caps
	local old = NM.MAX_TOWNS
	NM.MAX_TOWNS = 5
	local many = {}
	for i = 1, 9 do many[i] = town(i, EN[i], { coast = 1 }) end
	local r2 = NM.assign(many, p, { seed = 1 })
	NM.MAX_TOWNS = old
	eq(#r2, 5)
	local oldC = NM.MAX_CAND
	NM.MAX_CAND = 1
	local r3 = NM.assign({ town(1, "Taunton", { coast = 1 }) }, p, { seed = 1 })
	NM.MAX_CAND = oldC
	ok(r3[1].new ~= nil)
end)

test("satellites: a small town beside a much bigger one gets the composed name when unique", function()
	local p = enPool()
	local oldP = NM.SAT_P
	NM.SAT_P = 1
	local towns = { town(1, "Frome", {}, { x = 0, y = 0, cap = 5000 }), town(2, "Felton", {}, { x = 900, y = 0, cap = 400 }),
		town(3, "Potton", {}, { x = 10000, y = 0, cap = 400 }) }
	local res, st = NM.assign(towns, p, { seed = 5 })
	NM.SAT_P = oldP
	eq(res[2].match, "satellite")
	ok(res[2].new:find("Frome", 1, true) ~= nil, res[2].new)
	eq(res[2].parent, 1)
	eq(res[3].new, "Potton")
	eq(st.satellite, 1)
	-- composition rules
	eq(NM.compose("Bad Tölz", "de", 1), nil, "multi-word parents are not composed")
	eq(NM.compose("Frome", "ru", 1), nil, "no template")
	ok(NM.compose("Lund", "sv", 1) == "Lilla Lund")
	ok(NM.compose("川口市", "ja", 1) == "新川口市")
	-- a composed name already on the map: no satellite
	NM.SAT_P = 1
	local tpl = NM.SAT.en
	NM.SAT.en = { "Little %s" }
	local res2 = NM.assign(towns, p, { seed = 5, reserved = { ["Little Frome"] = true } })
	NM.SAT.en = tpl
	NM.SAT_P = oldP
	ok(res2[2].match ~= "satellite")
end)

test("townTags: coast, river, hill, island, forest, plain, big", function()
	local function ranked(info)
		local r, w = NM.townTags(info)
		return r, w
	end
	local _, w = ranked({ feat = { coast = 0.9, body = "sea", river = 0, open = 0.2 }, stats = { water = { kind = "coast" } } })
	ok((w.coast or 0) >= 0.9)
	_, w = ranked({ feat = { river = 1 }, stats = { water = { kind = "river" } }, wide = { water = 0.2 } })
	ok(w.river == 1 and w.ford and w.bridge and w.estuary, "river with wide water: estuary too")
	_, w = ranked({ feat = { rough = 0.8 }, stats = { meanSlope = 0.1, relief = { grade = 0.09 } } })
	ok((w.hill or 0) >= 0.8)
	_, w = ranked({ feat = { island = true, coast = 0.6, body = "sea" } })
	ok(w.island == 1)
	_, w = ranked({ forestShare = 0.4 })
	ok((w.forest or 0) >= 0.9)
	_, w = ranked({ feat = { open = 0.9 } })
	ok((w.plain or 0) >= 0.9 and w.coast == nil)
	_, w = ranked({ feat = { open = 0.2 }, big = true })
	ok(w.market == 0.8)
	local r = ranked({ feat = { coast = 0.9, body = "sea", rough = 0.5, open = 0.3, island = true }, stats = { spit = {} },
		forestShare = 0.5 })
	ok(#r <= NM.MAX_TOWN_TAGS)
	ok(r[1][2] >= r[#r][2])
	local big = NM.bigTowns({ { id = 1, cap = 100 }, { id = 2, cap = 120 }, { id = 3, cap = 900 }, { id = 4, cap = 3000 } })
	ok(big[4] and not big[1])
end)

test("industries: '<old town> <type>' follows the new name; the longest town name decides", function()
	local inds = { { id = 1, name = "Bury Crop Farm" }, { id = 2, name = "Bury St Edmunds Saw Mill" },
		{ id = 3, name = "Oxford Coal Mine" }, { id = 4, name = "Buryton Farm" }, { id = 5, name = "Bury" } }
	local out = NM.industryRenames(inds, { Bury = "Exmouth", Oxford = "Oxford" }, { "Bury", "Bury St Edmunds", "Oxford" })
	eq(#out, 1)
	eq(out[1].id, 1)
	eq(out[1].new, "Exmouth Crop Farm")
	local old = NM.MAX_INDUSTRIES
	NM.MAX_INDUSTRIES = 0
	eq(#NM.industryRenames(inds, { Bury = "Exmouth" }, { "Bury" }), 0)
	NM.MAX_INDUSTRIES = old
end)

test("saved: names flag and folder, stop queue add / drop, capped", function()
	local s, ch = SV.applyNames(nil, { done = 1, nd = "de" })
	ok(ch); eq(s.nm, 1); eq(s.nd, "de")
	ok(SV.namesDone(s))
	local s2, ch2 = SV.applyNames(s, { done = 1, nd = "en" })
	ok(not ch2); eq(s2.nd, "de")
	-- the init event after the names flag keeps it
	local s3 = SV.applyInit(s, { known = {}, fresh = true })
	eq(s3.nm, 1)
	local found = {}
	for i = 1, SV.STOP_CAP + 10 do found[i] = { st = i, g = 100 + i, n = "High Street", x = 1, y = 2 } end
	local q = SV.addStops(nil, found, 50)
	eq(#q.sq, SV.STOP_CAP)
	local q2, chq = SV.addStops(q, { { st = 1 } }, 60)
	ok(not chq)
	local q3 = SV.applyStopsDone(q2, { done = { 1, 2, 3 } })
	eq(#q3.sq, SV.STOP_CAP - 3)
	eq(#SV.stopQueue(q3), SV.STOP_CAP - 3)
	eq(#SV.stopQueue(nil), 0)
end)

test("stop themes and names: spot -> themes -> a real list name first, unique in the town", function()
	local th = NM.stopThemes({ station = 120, wet = "shore", dz = 20, dist = 100, forest = 0.8 })
	eq(th[1], "station"); eq(th[2], "shore"); eq(th[3], "hill")
	eq(th[#th], "centre")
	th = NM.stopThemes({ dist = 900, ring = -12, valleyTown = true })
	eq(th[1], "valley"); eq(th[2], "outskirts")
	eq(#NM.stopThemes({ dist = 400 }), 0)
	local streets = { "High Street", "Mill Lane", "Station Road", "Park Road", "The Grove" }
	local n, t = NM.pickStop("en", { "river" }, streets, {})
	eq(n, "Mill Lane"); eq(t, "river")
	n = NM.pickStop("en", { "river" }, streets, { ["Mill Lane"] = true })
	eq(n, "Bridge Street")
	n, t = NM.pickStop("en", { "hill", "centre" }, streets, {})
	eq(t, "hill")
	n = NM.pickStop("de", { "valley" }, { "Talstrasse", "Bergstrasse" }, {})
	eq(n, "Talstrasse")
	n = NM.pickStop("ja", { "station" }, { "駅前通り" }, {})
	eq(n, "駅前通り")
	eq(NM.pickStop("ko", { "hill" }, {}, {}), nil)
	local real = loadList("europe", "en", "streets.lua")
	if real then
		local c = NM.stopCandidates("en", "centre", real)
		eq(c[1], "High Street")
		ok(#c <= NM.MAX_STOP_CAND)
	end
end)

---------------------------------------------------------------------------
-- the driver against a fake engine

local LIST = { "Taunton", "Bilston", "Norton", "Seaford", "Whitehaven", "Newhaven", "Bournemouth", "Exmouth", "Oxford",
	"Stafford", "Stockbridge", "Tonbridge", "Wimbledon", "Haslemere", "Windermere", "Rochdale", "Ilfracombe", "Henley",
	"Bexley", "Lyndhurst", "Skegness", "Sheerness", "Radcliffe", "Clifton", "Market Deeping", "Axminster", "Wakefield",
	"Driffield", "Felton", "Potton", "Hetton", "Filton", "Surbiton", "Southsea", "Withernsea", "Huntingdon", "Abingdon",
	"Swindon", "Croydon", "Chertsey" }

-- towns: 1 coast (sea east of x = 250), 2 river (a band along y = 0 near x = 6000), 3 hill (12 % slope), 4 dry plain
local POS = { [1] = { 0, 0 }, [2] = { 6000, 0 }, [3] = { 0, 6000 }, [4] = { 6000, 6000 } }
local START = { [1] = "Taunton", [2] = "Bilston", [3] = "Norton", [4] = "Seaford" }

local function fakeEngine(o)
	o = o or {}
	local E = { t = 0, logs = {}, events = {}, renames = {}, names = {} }
	for id, n in pairs(START) do E.names[id] = n end
	E.names[901] = "Taunton Crop Farm"
	E.names[902] = "Seaford Coal Mine"
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return { nameList = o.nameList or "::/names/europe/europe.names", climate = "temperate" } end
	end
	function E.modParams() return o.params or { act_on = 3, debug_log = 2 }, {} end
	function E.gameTime() return o.gameTime or 1000 end
	function E.year() return 1950 end
	function E.towns() return { 1, 2, 3, 4 } end
	function E.name(e) return E.names[e] or ("?" .. tostring(e)) end
	function E.boxCentre(t) local p = POS[t] if p then return p[1], p[2] end return nil end
	function E.townCaps(_t) return { target = 1000, actual = 900 } end
	function E.sendEvent(id, name, param) E.events[#E.events + 1] = { id = id, name = name, param = param } end
	function E.sampler()
		return T.sampler(function(x, y)
			if y > 3000 and x < 3000 then return 0.12 * x + 100 end
			return 10
		end, function(x, y)
			if x > 250 and x < 2500 and y < 3000 and y > -3000 then return true end
			if x > 4000 and x < 8000 and math.abs(y) < 30 then return true end
			return false
		end, 0)
	end
	function E.townList(path, dir)
		E.loaded = (E.loaded or 0) + 1
		if dir == "en" then return LIST end
		return { "Berlin", "Ulm" }
	end
	function E.language() return o.lang, "test" end
	function E.setName(e, name, cb)
		E.renames[#E.renames + 1] = { e, name }
		if not o.noApply then E.names[e] = name end
		cb(true)
	end
	function E.industryNames() return { { id = 901, name = E.names[901] }, { id = 902, name = E.names[902] } } end
	-- stops
	E.groups = o.groups or {}
	function E.stationGroup(st) return E.groups[st] end
	function E.groupStations(g)
		local out = {}
		for st, gg in pairs(E.groups) do if gg == g then out[#out + 1] = st end end
		return out
	end
	function E.stationTown(_st) return o.stopTown or 1 end
	function E.townStopNames(_t, _skip) return o.usedStops or {} end
	function E.streetList() return { "High Street", "Mill Lane", "Station Road", "The Grove", "Church Street" } end
	function E.osTime() return o.osTime or 100 end
	return E
end

local function run(E, ticks, saved, stop)
	local oldHead = D.HEAD
	D.HEAD = false
	local d = D.new(E)
	for _ = 1, ticks do
		E.t = E.t + 20000
		d:tick(E.t, saved)
		if stop and stop(E) then break end
	end
	D.HEAD = oldHead
	return d
end

local function findLog(E, pat)
	for _, l in ipairs(E.logs) do if l:find(pat) then return l end end
	return nil
end

local function namesDone(E) return findLog(E, "%[SQOT%] NAMES on=true") ~= nil end

test("driver: a new map on a base list renames the towns once, uniquely, and their industries", function()
	local E = fakeEngine({ lang = "en" })
	run(E, 3000, nil, namesDone)
	local l = findLog(E, "%[SQOT%] NAMES on=true")
	ok(l, "summary line")
	ok(l:find("why=ok"), l)
	ok(l:find("list=europe") and l:find("lang=en") and l:find("langSource=lang"), l)
	-- the done flag (with the folder) went out before the renames
	local ev = nil
	for _, e in ipairs(E.events) do if e.name == SV.EV_NAMES then ev = e end end
	ok(ev and ev.param.done == 1 and ev.param.nd == "en")
	local seen = {}
	for t = 1, 4 do
		ok(not seen[E.names[t]], "unique " .. E.names[t])
		seen[E.names[t]] = true
	end
	ok(E.names[4] ~= "Seaford", "the dry plain town lost its sea name: " .. E.names[4])
	-- (2026-10-14, NEXT_PHASE_BRIEF 49: Landscape names are generated too, never a name of the game's list)
	for t = 1, 4 do for _, n in ipairs(LIST) do ok(E.names[t] ~= n, "not a list name: " .. n) end end
	ok(l:find("gen=en"), l)
	ok(findLog(E, "%[SQOT%] NAME town=1"), "per-town debug line")
	-- industries named after a renamed town follow it
	if E.names[1] ~= "Taunton" then eq(E.names[901], E.names[1] .. " Crop Farm") end
	eq(E.names[902], E.names[4] .. " Coal Mine")
	print(string.format("assigned: %s / %s / %s / %s", E.names[1], E.names[2], E.names[3], E.names[4]))
end)

test("driver: names skip another mod's list, an old save, a done map and the Game names setting", function()
	local E = fakeEngine({ nameList = "square_names_us_texas::/names/usa/usa.names" })
	run(E, 50)
	ok(findLog(E, "NAMES on=false why=notBase"))
	eq(#E.renames, 0)
	E = fakeEngine({ gameTime = 10 * SV.FRESH_GAME_TIME })
	run(E, 50)
	ok(findLog(E, "NAMES on=false why=notNewMap"))
	E = fakeEngine({})
	run(E, 50, { v = 1, frames = {}, nm = 1 })
	ok(findLog(E, "NAMES on=false why=done"))
	E = fakeEngine({ params = { act_on = 3, town_names = 2 } })
	run(E, 50)
	ok(findLog(E, "NAMES on=false why=setting"))
	eq(#E.renames, 0)
end)

test("driver: a town renamed meanwhile is left alone; the language folder falls back to the town names' match", function()
	local E = fakeEngine({ lang = "de" })
	-- (the player renames town 2 right after the assignment)
	local orig = E.sendEvent
	E.sendEvent = function(id, name, param)
		if name == SV.EV_NAMES then E.names[2] = "Playerton" end
		return orig(id, name, param)
	end
	run(E, 3000, nil, namesDone)
	local l = findLog(E, "NAMES on=true")
	ok(l and l:find("lang=en") and l:find("langSource=match"), l)
	eq(E.names[2], "Playerton")
end)

test("driver: a queued Road Stop gets a stop name from its spot; renamed / joined groups stay", function()
	-- stop 50 (group 500) by the river at town 2, stop 51 (group 501) renamed by the player, stop 52 joined group 502
	local E = fakeEngine({ groups = { [50] = 500, [51] = 501, [52] = 502, [53] = 502 }, stopTown = 2, osTime = 100 })
	E.names[500], E.names[501], E.names[502] = "Park Road", "My Stop", "Church Street"
	local saved = { v = 1, frames = {}, nm = 1, nd = "en", sq = {
		{ st = 50, g = 500, n = "Park Road", x = 6000, y = 50, t = 90 },
		{ st = 51, g = 501, n = "Kings Road", x = 6000, y = 50, t = 90 },
		{ st = 52, g = 502, n = "Church Street", x = 6000, y = 50, t = 90 } } }
	run(E, 200, saved)
	local l = findLog(E, "%[SQOT%] STOPNAME group=500")
	ok(l, "stop line: " .. table.concat(E.logs, "\n"))
	ok(l:find("tags=river") and l:find("new=Mill_Lane"), l)
	eq(E.names[500], "Mill Lane")
	eq(E.names[501], "My Stop")
	eq(E.names[502], "Church Street")
	ok(findLog(E, "STOPNAME group=501 station=51 old=My_Stop new=%- why=renamed"), table.concat(E.logs, "\n"))
	ok(findLog(E, "why=joined"))
	-- the queue is drained by "stops" events
	local done = {}
	for _, e in ipairs(E.events) do
		if e.name == SV.EV_STOPS then for _, st in ipairs(e.param.done) do done[st] = true end end
	end
	ok(done[50] and done[51] and done[52])
end)

test("driver: stop names off on another mod's list (queue drained, no rename)", function()
	local E = fakeEngine({ nameList = "square_names_us_texas::/names/usa/usa.names", groups = { [50] = 500 } })
	E.names[500] = "Park Road"
	local saved = { v = 1, frames = {}, sq = { { st = 50, g = 500, n = "Park Road", x = 6000, y = 50, t = 90 } } }
	run(E, 100, saved)
	ok(findLog(E, "STOPNAME on=false why=notBase"))
	eq(E.names[500], "Park Road")
	local drained = false
	for _, e in ipairs(E.events) do if e.name == SV.EV_STOPS then drained = true end end
	ok(drained)
end)

test("sample map: real lists, one town per site kind (printed for the report), unique", function()
	local sites = {
		{ "coast", { coast = 1 } }, { "estuary", { river = 1, ford = 0.8, bridge = 0.8, estuary = 0.9 } },
		{ "river", { river = 1, ford = 0.8, bridge = 0.8 } }, { "lake", { lake = 1 } }, { "hill", { hill = 0.9 } },
		{ "valley", { valley = 1, hill = 0.4 } }, { "forest", { forest = 0.8 } }, { "island", { island = 1, coast = 0.8 } },
		{ "headland", { headland = 0.9, coast = 0.7 } }, { "cliff", { cliff = 0.8, coast = 0.6 } },
		{ "marsh", { marsh = 0.8, plain = 0.6 } }, { "plain", { plain = 0.9 } }, { "big", { market = 0.8, plain = 0.5 } },
	}
	for _, L in ipairs({ { "europe", "en" }, { "europe", "de" }, { "usa", "en" }, { "france", "en" }, { "japan", "ja" } }) do
		local list = loadList(L[1], L[2])
		if list then
			local cls = NM.classOf(L[1], L[2])
			local p = pool(list, cls)
			local towns = {}
			for i, sk in ipairs(sites) do
				-- (the game's draw: every 37th name)
				towns[i] = town(i, list[(i * 37) % #list + 1], sk[2])
			end
			local res = NM.assign(towns, p, { seed = NM.mapSeed(towns) })
			local parts, seen = {}, {}
			for i, r in ipairs(res) do
				ok(not seen[r.new], r.new)
				seen[r.new] = true
				parts[#parts + 1] = string.format("%s: %s -> %s (%s)", sites[i][1], r.old, r.new, r.match)
			end
			print(L[1] .. "/" .. L[2] .. ": " .. table.concat(parts, "; "))
		end
	end
end)

test("driver: dev-built stops (addDevStops) are named too, without a saved-queue event; capped", function()
	local E = fakeEngine({ groups = { [60] = 600 }, stopTown = 2, osTime = 100 })
	E.names[600] = "Park Road"
	local oldHead = D.HEAD
	D.HEAD = false
	local d = D.new(E)
	local saved = { v = 1, frames = {}, nm = 1, nd = "en" }
	for _ = 1, 5 do E.t = E.t + 20000; d:tick(E.t, saved) end
	eq(d:addDevStops({ { st = 60, g = 600, n = "Park Road", x = 6000, y = 50 } }), 1)
	E.osTime = function() return 200 end
	for _ = 1, 200 do E.t = E.t + 20000; d:tick(E.t, saved) end
	D.HEAD = oldHead
	eq(E.names[600], "Mill Lane")
	ok(findLog(E, "STOPNAME group=600 station=60 town=2 old=Park_Road new=Mill_Lane dev=true"))
	for _, e in ipairs(E.events) do ok(e.name ~= SV.EV_STOPS, "no stops event for dev stops") end
	local many = {}
	for i = 1, SV.STOP_CAP + 5 do many[i] = { st = 1000 + i } end
	eq(d:addDevStops(many), SV.STOP_CAP)
end)

test("driver: stop names are unique on the whole map; a stop named after its industry keeps that name", function()
	-- stops 70 / 71 by the river in two towns (the fake engine answers town 2 for both: the map-wide read must still
	-- keep them apart), stop 72's group carries an industry's name ("Taunton Crop Farm")
	local E = fakeEngine({ groups = { [70] = 700, [71] = 701, [72] = 702 }, stopTown = 2, osTime = 100 })
	E.names[700], E.names[701], E.names[702] = "Park Road", "Kings Road", "Taunton Crop Farm"
	function E.mapStopNames()
		local out = {}
		for _, g in ipairs({ 700, 701, 702 }) do out[E.names[g]] = true end
		return out
	end
	E.townStopNames = function() return {} end   -- (the old per-town read would let a duplicate through)
	local saved = { v = 1, frames = {}, nm = 1, nd = "en", sq = {
		{ st = 70, g = 700, n = "Park Road", x = 6000, y = 50, t = 90 },
		{ st = 71, g = 701, n = "Kings Road", x = 6000, y = 50, t = 90 },
		{ st = 72, g = 702, n = "Taunton Crop Farm", x = 6000, y = 50, t = 90 } } }
	run(E, 300, saved)
	ok(E.names[700] ~= "Park Road" and E.names[701] ~= "Kings Road", table.concat(E.logs, "\n"))
	ok(E.names[700] ~= E.names[701], E.names[700] .. " / " .. E.names[701])
	eq(E.names[702], "Taunton Crop Farm")
	ok(findLog(E, "STOPNAME group=702 .*why=industry"), table.concat(E.logs, "\n"))
	local l = findLog(E, "%[SQOT%] STOPNAME group=701")
	ok(l and l:find("uniq=%d+/%d+") and l:find("kind="), l)
end)

test("driver: the stop names' used set is read live (a stop the game names after the last read counts)", function()
	-- run 2026-10-13_2240_sqot-dev: a 60 s cache missed a stop the game had just named "The Grove"; another stop was
	-- renamed to it 38 s later
	local E = fakeEngine({ groups = { [80] = 800, [81] = 801 } })
	E.names[800], E.names[801] = "Park Road", "Kings Road"
	local list = { 800, 801 }
	local reads = 0
	function E.stationGroups() return list end
	local name0 = E.name
	function E.name(e) reads = reads + 1; return name0(e) end
	local d = D.new(E)
	local used = d:stopUsed(1, 800, 1e6, {})
	ok(used["Park Road"] and used["Kings Road"])
	-- a new stop the game named 10 s later: in the next read, without a full re-read of the others
	list[#list + 1] = 802
	E.names[802] = "The Grove"
	local r0 = reads
	used = d:stopUsed(1, 800, 11e6, {})
	ok(used["The Grove"], "the new group's name")
	ok(reads - r0 <= 2, "only the new group and the stop's own were read: " .. (reads - r0))
	-- names sent and not yet applied count too; a rename we sent updates the cache
	d.stopGiven = { ["Oak Lane"] = true }
	used = d:stopUsed(1, 800, 12e6, {})
	ok(used["Oak Lane"])
	-- every STOP_USED_S the whole map again (a player's rename elsewhere)
	E.names[801] = "Station Approach"
	used = d:stopUsed(1, 800, 12e6 + D.STOP_USED_S * 1e6 + 1, {})
	ok(used["Station Approach"] and not used["Kings Road"])
end)

test("driver: a new rail station beside an industry gets <Town> Quarry; one in town keeps the game's name", function()
	local E = fakeEngine({ groups = { [90] = 950, [91] = 951 }, stopTown = 2, osTime = 100 })
	E.names[950], E.names[951], E.names[905] = "Station Road", "Kings Road", "Taunton Clay Pit"
	local tx, ty = E.boxCentre(2)
	function E.industries() return { { tx + 400, ty, file = "industries/clay_pit/clay_pit.con", e = 905 } } end
	local saved = { v = 1, frames = {}, nm = 1, nd = "en", sq = {
		{ st = 90, g = 950, n = "Station Road", x = tx + 320, y = ty + 30, t = 90, k = "rail" },
		{ st = 91, g = 951, n = "Kings Road", x = tx, y = ty, t = 90, k = "rail" } } }
	run(E, 300, saved)
	local town = E.names[2]
	eq(E.names[950], town .. " Quarry", table.concat(E.logs, "\n"))
	eq(E.names[951], "Kings Road", "a station in town keeps its name")
	ok(findLog(E, "STOPNAME group=951 .*why=noIndustry") or findLog(E, "STOPNAME group=951 .*why=nearerTown"), table.concat(E.logs, "\n"))
	ok(findLog(E, "%[SQOT%] STOPNAME group=950 .*kind=station:rail"))
end)

---------------------------------------------------------------------------
-- Generated names (ot_placename, 2026-10-14; setting value 3)

local PN = ug_require(F.DIR .. "ot_placename.lua")

test("driver: a saved Generated names value (3, removed 2026-10-15) names like Landscape: every drawn town a generated name once, industries follow, waters saved", function()
	local E = fakeEngine({ lang = "en", params = { act_on = 3, debug_log = 2, town_names = 3 } })
	run(E, 3000, nil, namesDone)
	local l = findLog(E, "%[SQOT%] NAMES on=true")
	ok(l, "summary line")
	ok(l:find("why=ok") and l:find("mode=landscape") and l:find("gen=en") and l:find("fallback=%-"), l)
	local ev = nil
	for _, e in ipairs(E.events) do if e.name == SV.EV_NAMES then ev = e end end
	ok(ev and ev.param.done == 1 and ev.param.nd == "en", "done flag")
	-- (2026-10-17, the town window card: each renamed town's name origin goes with the done flag)
	local CARD = ug_require(F.DIR .. "ot_card.lua")
	ok(type(ev.param.no) == "table" and #ev.param.no >= 1 and #ev.param.no <= 4, "origins sent")
	for _, o in ipairs(ev.param.no) do
		ok(SV.originOk(o.o) and CARD.originText(CARD.originOf(o.o)), "a sentence for " .. tostring(o.o))
	end
	ok(findLog(E, "%[SQOT%] CARD event=origins towns=%d+ of=4"), "origins line")
	local seen = {}
	for t = 1, 4 do
		ok(not seen[E.names[t]], "unique " .. E.names[t])
		seen[E.names[t]] = true
		ok(E.names[t] ~= START[t], "renamed " .. START[t])
		-- never a name of the game's list
		for _, n in ipairs(LIST) do ok(E.names[t] ~= n, "not a list name: " .. n) end
	end
	ok(findLog(E, "%[SQOT%] NAME town=1 .*src=generated .*parts="), "per-town line")
	eq(E.names[902], E.names[4] .. " Coal Mine")
	print(string.format("generated: %s / %s / %s / %s", E.names[1], E.names[2], E.names[3], E.names[4]))
	-- a reload never names again
	local E2 = fakeEngine({ lang = "en", params = { act_on = 3, town_names = 3 } })
	run(E2, 50, { v = 1, frames = {}, nm = 1 })
	ok(findLog(E2, "NAMES on=false why=done"))
end)

test("driver: a list without a generator keeps the game's names (NAMES on=false why=noGenerator / untaggedList), the survey still runs", function()
	-- (2026-10-14, NEXT_PHASE_BRIEF 48 items 1 and 5, 49: no real list names handed out, no English words on Asian names)
	for _, mode in ipairs({ 1, 3 }) do
		local E = fakeEngine({ nameList = "::/names/russia/russia.names", lang = "en", params = { act_on = 3, debug_log = 2, town_names = mode } })
		run(E, 3000, nil, function(e) return findLog(e, "%[SQOT%] NAMES on=") ~= nil end)
		local l = findLog(E, "%[SQOT%] NAMES on=false")
		ok(l and l:find("why=noGenerator"), tostring(l))
		eq(#E.renames, 0)
		ok(findLog(E, "%[SQOT%] NAMES survey"), "the survey ran")
		local A = fakeEngine({ nameList = "::/names/asia/asia.names", lang = "en", params = { act_on = 3, debug_log = 2, town_names = mode } })
		run(A, 3000, nil, function(e) return findLog(e, "%[SQOT%] NAMES on=") ~= nil end)
		local la = findLog(A, "%[SQOT%] NAMES on=false")
		ok(la and la:find("why=untaggedList") and la:find("list=asia"), tostring(la))
		eq(#A.renames, 0)
	end
end)

test("driver: stop names stay on with Generated names and use a saved river name beside the stop", function()
	local E = fakeEngine({ groups = { [50] = 500 }, stopTown = 2, osTime = 100, params = { act_on = 3, debug_log = 2, town_names = 3 } })
	E.names[500] = "Park Road"
	local saved = { v = 1, frames = {}, nm = 1, nd = "en", rv = { { n = "Wenwy", x = 6000, y = 0, k = "r" } },
		sq = { { st = 50, g = 500, n = "Park Road", x = 6000, y = 50, t = 90 } } }
	run(E, 200, saved)
	local l = findLog(E, "%[SQOT%] STOPNAME group=500")
	ok(l and l:find("tags=river"), tostring(l))
	ok(E.names[500]:find("Wenwy", 1, true), "river stop name: " .. E.names[500])
end)
