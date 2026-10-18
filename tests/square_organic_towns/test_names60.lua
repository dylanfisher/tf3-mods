-- Literal, context-aware names first, a little national flavor (2026-10-15, NEXT_PHASE_BRIEF 60; evidence
-- `.cache/logs/2026-10-15_0341_sqot.log.gz`, seed a, europe, 1950: Mytham, Shaw, Padfield, Kelington, Edton, Wemmead,
-- Trefach, Abercoed). User: "maybe we just really push the simple context aware naming and then just a little
-- nationality mixed in" and "descriptive names and multi word names that help make it clear its context-aware".
--   * at least about 80 % of town names carry a readable site word that matches the town's tags or cues (PN.siteWord);
--   * opaque stems (+p personal names, +u morphemes) at most 1 per 16 towns;
--   * quiet names (no terrain word; saint names are flavor) at most about 10 %;
--   * national / dialect flavor (+n) 1-3 per 16 towns;
--   * en / usa: 40-60 % multi-word names ("Oak Hill", "Mill Creek"), never more than 3 words;
--   * every generator language follows the rule; the s53 rules (the lab's comparison) still give the review's names;
--   * the 0341 sites (europe) and the 1729 sites (usa) replayed, before (s53) and after (s60), with districts and Works;
--     de and fr synthetic maps (printed: NAME_SAMPLES-free, always).
-- Quick mode samples 3 seeds per climate and preset; TEST_FULL 12.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local NMAP = loadfile(here .. "namemaps.lua", "t", _ENV)()
local PN = ug_require(F.DIR .. "ot_placename.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

local FULL = os.getenv("TEST_FULL") ~= nil
local SEEDS = {}
for s = 1, FULL and 12 or 3 do SEEDS[#SEEDS + 1] = s * 41 + 3 end

local function parseW(s)
	local w = {}
	for k, v in s:gmatch("([%a_]+):([%d%.]+)") do w[k] = tonumber(v) end
	return w
end

-- run 0341 (seed a, europe, temperate, 1950): id, x, y, tags, cues, survey river (Arun 1, Dart 2, Dove 3), own lake,
-- cap, altitude, character kind, the game's old name
local R0341 = {
	{ 60255, -2012, -2748, "lake:1.00,character:1.00,forest:0.54,hill:0.51,small:0.48,new:0.42", "peak:1.00,bay:1.00,mainvalley:0.90,lower:0.85,range:0.80,south:0.43", 1, false, 397, 1, "cove" },
	{ 60256, -1696, 44, "bend:1.08,river:0.90,bridge:0.90,forest:0.76,market:0.64,big:0.64", "confluence:1.00,peak:1.00,mainvalley:0.90,central:0.80,range:0.80", 1, false, 907, 1 },
	{ 60257, -5500, -5320, "mere:1.08,lake:1.00,character:1.00,vale:0.77,valley:0.50,new:0.42", "confluence:1.00,mouth:1.00,west:0.72,south:0.70,upper:0.70", 2, true, 560, 3 },
	{ 60258, -7256, 4896, "bend:1.08,lake:1.00,river:0.90,bridge:0.90,oak:0.77,forest:0.68", "mouth:1.00,west:0.90,bend:0.90,mainvalley:0.90,lower:0.87,north:0.66", 1, false, 392, 1 },
	{ 60259, 2804, 144, "ash:1.09,mere:1.08,lake:1.00,edge:0.70,forest:0.59,small:0.48", "east:0.44", nil, true, 258, 2 },
	{ 60260, 364, 2640, "forest:0.49,new:0.42,field:0.42,plain:0.39", "mainvalley:0.90,north:0.42", nil, false, 535, 1 },
	{ 60261, -3968, 2568, "lake:1.00,oak:0.82,edge:0.70,small:0.48,new:0.42,forest:0.41", "bay:1.00,mainvalley:0.90,west:0.56,north:0.41", 1, true, 357, 1 },
	{ 60262, 1436, 6640, "ash:1.20,character:1.00,market:0.64,big:0.64,forest:0.58,field:0.42", "mainvalley:0.90,north:0.84", nil, false, 709, 1, "garden" },
	{ 60263, 4340, 3204, "spit:1.50,headland:1.26,rocky:0.77,coast:0.54,oak:0.48,new:0.42", "biglake:1.00,narrows:1.00,east:0.60,north:0.48", nil, true, 644, 2 },
	{ 60264, -2412, 7324, "edge:0.70,forest:0.58,small:0.48,new:0.42,hill:0.31,field:0.18", "confluence:1.00,north:0.91,mainvalley:0.90", 1, false, 316, 3 },
	{ 60265, 4280, -6416, "ash:0.94,vale:0.77,forest:0.53,valley:0.50,small:0.48,new:0.42", "south:0.81,east:0.59", 3, false, 284, 1 },
	{ 60266, 7124, -616, "oak:0.78,forest:0.59,small:0.48,new:0.42,field:0.20", "east:0.89", nil, false, 257, 2 },
	{ 60267, 5516, -3240, "mere:1.08,lake:1.00,vale:0.77,edge:0.70,forest:0.64,valley:0.50", "east:0.72,south:0.48", nil, true, 446, 1 },
	{ 60268, 5004, 6388, "ash:0.97,edge:0.70,small:0.48,forest:0.48,new:0.42,hill:0.33", "north:0.81,east:0.67", nil, false, 340, 1 },
	{ 60269, 1780, -3508, "forest:0.80,vale:0.77,oak:0.64,valley:0.50,new:0.42,field:0.30", "south:0.51", nil, false, 469, 1 },
	{ 60270, 724, -6788, "foot:1.17,clearing:1.08,character:1.00,forest:0.90,hill:0.51,new:0.42", "confluence:1.00,mouth:1.00,south:0.85,lower:0.76", 3, false, 418, 1 },
}
-- (the game's names in that run: the s53 rules' names, for the report)
local OLD0341 = "Brynchurch Cove, Mytham, Dart Head, Lower Aberarun, Shaw, Padfield, Oakhaven, Ashminster Garden City, Hornness, "
	.. "Abercoed, Kelington, Edton, Winmere, Trefach, Wemmead, Milton-under-Edge"

-- run 1729 load 4 (seed a, usa list, temperate; the same map as load 3): id, x, y, tags, cues, river, lake (test_namefix)
local R1729 = {
	{ 60255, -2400, -2600, "lake:1,forest:.54,hill:.51,small:.48", "peak:1,bay:1,mainvalley:.9,lower:.85,range:.8,south:.43", 1, false },
	{ 60256, -1147, 626, "bend:1,river:.9,bridge:.9,forest:.75,market:.64,big:.64", "confluence:1,peak:1,mainvalley:.9,central:.8,range:.8", 1, false },
	{ 60257, -6277, -5509, "mere:1,lake:1,vale:.77,valley:.5,forest:.32,field:.16", "confluence:1,mouth:1,west:.72,south:.7,upper:.7", 2, true },
	{ 60258, -6771, 5532, "bend:1,lake:1,river:.9,bridge:.9,oak:.77,forest:.68", "mouth:1,west:.9,bend:.9,mainvalley:.9,lower:.87,north:.66", 1, false },
	{ 60259, 6200, -6600, "ash:1,mere:1,lake:1,edge:.7,forest:.59,small:.48", "east:.44", nil, true },
	{ 60260, -157, 2251, "forest:.49,field:.42,plain:.4", "mainvalley:.9,north:.42", nil, false },
	{ 60261, -3787, 1789, "lake:1,oak:.83,edge:.7,small:.48,forest:.41,field:.18", "bay:1,mainvalley:.9,west:.56,north:.41", 1, true },
	{ 60262, 436, 6618, "ash:1,character:1,market:.64,big:.64,forest:.57,field:.42", "mainvalley:.9,north:.84", nil, false },
	{ 60263, 4438, 3998, "spit:1,headland:1,rocky:.77,coast:.54,oak:.48,forest:.38", "biglake:1,narrows:1,east:.6,north:.48", nil, true },
	{ 60264, -2898, 6688, "edge:.7,forest:.58,small:.48,hill:.31,field:.18", "confluence:1,north:.91,mainvalley:.9", 1, false },
	{ 60265, 3454, -5706, "ash:.93,vale:.77,forest:.51,valley:.5,small:.48,field:.37", "south:.81,east:.59", 3, false },
	{ 60266, 6668, -153, "oak:.79,forest:.58,small:.48,field:.2", "east:.89", nil, false },
	{ 60267, 4945, -3426, "mere:1,lake:1,vale:.77,edge:.7,forest:.65,valley:.5", "east:.72,south:.48", nil, true },
	{ 60268, 5426, 5893, "ash:.97,edge:.7,forest:.49,small:.48,hill:.33,field:.15", "north:.81,east:.67", nil, false },
	{ 60269, 2218, -2609, "forest:.83,vale:.77,oak:.63,valley:.5,field:.3,plain:.23", "south:.51", nil, false },
	{ 60270, 682, -5989, "foot:1,clearing:1,character:1,forest:.9,hill:.51,church:.32", "confluence:1,mouth:1,south:.85,lower:.76", 3, false },
}

local function replayTowns(R)
	local towns = {}
	for i, r in ipairs(R) do
		local w = parseW(r[4])
		local cw = parseW(r[5])
		local dir = nil
		for _, d in ipairs({ "north", "south", "east", "west" }) do if (cw[d] or 0) >= 0.6 then dir = dir or d end end
		local ch = r[10] or ((w.character or 0) > 0)
		towns[i] = { id = r[1], name = "T" .. r[1], x = r[2], y = r[3], w = w, ranked = PN.rankOf(w), cap = r[8] or (300 + 40 * i),
			alt = r[9], character = ch, cue = { w = cw, river = r[6], dir = dir, lake = cw.biglake and true or nil },
			river = r[6] ~= nil, lake = r[7] }
	end
	return towns
end

-- the §60 numbers of one finished map
local function metrics(towns, res)
	local m = { n = #res, desc = 0, opaque = 0, flavor = 0, quiet = 0, multi = 0, maxTok = 0, misses = {} }
	for i, r in ipairs(res) do
		local inf = r.info or {}
		local site = PN.siteWord(inf, PN.withCues(towns[i].w, towns[i].cue))
		if site then m.desc = m.desc + 1 else m.misses[#m.misses + 1] = r.new end
		if inf.opaque then m.opaque = m.opaque + 1 end
		if inf.flavor then m.flavor = m.flavor + 1 end
		if inf.quiet and inf.shape ~= "saint" then m.quiet = m.quiet + 1 end
		local k = PN.tokens(r.new)
		if k >= 2 then m.multi = m.multi + 1 end
		if k > m.maxTok then m.maxTok = k end
	end
	return m
end

local function mText(m)
	return string.format("site word %d/%d (%.0f %%), multi-word %d (%.0f %%), opaque %d, flavor %d, quiet %d", m.desc, m.n,
		100 * m.desc / m.n, m.multi, 100 * m.multi / m.n, m.opaque, m.flavor, m.quiet)
end

local function namesOf(res)
	local out = {}
	for _, r in ipairs(res) do out[#out + 1] = r.new end
	return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- the gates over many synthetic maps

local function sweep(lang, climates)
	local agg = { maps = 0, n = 0, desc = 0, multi = 0, quiet = 0, opaque = 0, flavor = 0, flavorMaps = 0 }
	local worst = 1
	for _, climate in ipairs(climates) do
		for pi, preset in ipairs(NMAP.PRESET_ORDER) do
			for si, seed in ipairs(SEEDS) do
				local n = (si + pi) % 2 == 0 and 16 or 24
				local towns = NMAP.makeMap(seed + pi * 1000, preset, n, climate)
				local res = PN.assign(towns, { lang = lang, seed = seed, climate = climate })
				local m = metrics(towns, res)
				local label = string.format("%s %s/%s/%d/%d", lang, preset, climate, seed, n)
				ok(m.opaque <= math.max(1, math.floor(n / PN.OPAQUE_PER)), label .. " opaque " .. m.opaque .. ": " .. namesOf(res))
				ok(m.flavor <= math.floor(n * PN.FLAVOR_MAX / 16 + 0.5), label .. " flavor " .. m.flavor)
				ok(m.maxTok <= 3, label .. " a name of " .. m.maxTok .. " words")
				ok(m.desc / n >= 0.55, string.format("%s site words %d/%d: %s", label, m.desc, n, table.concat(m.misses, ", ")))
				worst = math.min(worst, m.desc / n)
				agg.maps, agg.n = agg.maps + 1, agg.n + n
				agg.desc, agg.multi, agg.quiet = agg.desc + m.desc, agg.multi + m.multi, agg.quiet + m.quiet
				agg.opaque, agg.flavor = agg.opaque + m.opaque, agg.flavor + m.flavor
				if m.flavor > 0 then agg.flavorMaps = agg.flavorMaps + 1 end
			end
		end
	end
	agg.worst = worst
	print(string.format("  %-4s %d maps, %d towns: site word %.0f %% (worst map %.0f %%), multi-word %.0f %%, quiet %.0f %%, "
		.. "opaque %.2f / 16, flavor %.2f / 16 (on %d maps)", lang, agg.maps, agg.n, 100 * agg.desc / agg.n, 100 * worst,
		100 * agg.multi / agg.n, 100 * agg.quiet / agg.n, 16 * agg.opaque / agg.n, 16 * agg.flavor / agg.n, agg.flavorMaps))
	return agg
end

-- (one test per language and climate: each stays under ~8 s in full mode; the 80 % and 40-60 % targets on temperate
-- maps, a few points less on the other climates, whose own words are fewer)
for _, lang in ipairs({ "en", "usa" }) do
	for _, climate in ipairs(NMAP.CLIMATES) do
		local tmp = climate == "temperate"
		test("§60 gates, " .. lang .. " " .. climate .. ": site words >= " .. (tmp and 80 or 75) .. " %, multi-word 40-60 %, quiet ~10 %, "
			.. "opaque <= 1 / 16, flavor <= 3 / 16", function()
			local a = sweep(lang, { climate })
			ok(a.desc / a.n >= (tmp and 0.8 or 0.75), string.format("%s %s site-word share %.2f", lang, climate, a.desc / a.n))
			local lo, hi = tmp and 0.4 or 0.38, tmp and 0.6 or 0.65
			ok(a.multi / a.n >= lo and a.multi / a.n <= hi, string.format("%s %s multi-word share %.2f", lang, climate, a.multi / a.n))
			ok(a.quiet / a.n <= PN.QUIET_SHARE + 0.05, string.format("%s %s quiet share %.2f", lang, climate, a.quiet / a.n))
			if lang == "en" and climate ~= "tropical" then
				local f = 16 * a.flavor / a.n
				ok(f >= 1 and f <= 3, string.format("en %s flavor %.2f per 16 towns", climate, f))
			end
		end)
	end
end

for _, lang in ipairs({ "de", "fr", "it", "es", "pt", "nl", "sv", "nb", "ja", "ja_r" }) do
	test("§60 gates, " .. lang .. ": site words >= 80 %, quiet, opaque, flavor caps (temperate, tropical)", function()
		local a = sweep(lang, { "temperate", "tropical" })
		ok(a.desc / a.n >= 0.8, string.format("%s site-word share %.2f", lang, a.desc / a.n))
		ok(a.quiet / a.n <= PN.QUIET_SHARE + 0.05, string.format("%s quiet share %.2f", lang, a.quiet / a.n))
		if PN.lang(lang).hasFlavor then ok(16 * a.flavor / a.n <= 3, lang .. " flavor per 16 towns") end
	end)
end

test("the s53 rules (the lab's comparison) keep the review's names: about 40 % quiet, personal stems allowed", function()
	local towns = replayTowns(R0341)
	local res = PN.assign(towns, { lang = "en", seed = 1, climate = "temperate", rules = "s53" })
	local m = metrics(towns, res)
	ok(m.quiet >= 4, "s53 quiet names: " .. m.quiet)
	local res2 = PN.assign(towns, { lang = "en", seed = 1, climate = "temperate" })
	local m2 = metrics(towns, res2)
	ok(m2.desc > m.desc and m2.opaque <= 1, string.format("s60 more site words (%d vs %d), opaque %d", m2.desc, m.desc, m2.opaque))
end)

test("opaque and flavor parts: Myt-, Pad-, Trefach opaque; Aber-, -by, -thwaite flavor; readable words neither", function()
	local L = PN.lang("en")
	local function e(list, text)
		for _, x in ipairs(list) do if (x.k or x.text) == text then return x end end
	end
	ok(PN.opaque(e(L.specs, "Myt")) and PN.opaque(e(L.specs, "Pad")) and PN.opaque(e(L.specs, "fach")), "opaque stems")
	ok(PN.flavorPart(e(L.gens, "Aber")) and PN.flavorPart(e(L.gens, "by")) and PN.flavorPart(e(L.gens, "thwaite")), "flavor gens")
	ok(not PN.opaque(e(L.specs, "Oak")) and not PN.flavorPart(e(L.gens, "ford")) and not PN.flavorPart(e(L.gens, "water")), "readable")
	-- a site word: Oakbridge at an oak-wood crossing; Padfield on a field site is no site word (an opaque stem, a weak field)
	local info = { sE = e(L.specs, "Oak"), gE = e(L.gens, "bridge") }
	ok(PN.siteWord(info, { oak = 0.8, river = 1, bridge = 0.8 }), "Oakbridge reads its site")
	ok(not PN.siteWord({ sE = e(L.specs, "Pad"), gE = e(L.gens, "ton") }, { field = 0.4, plain = 0.4 }), "Padton reads nothing")
	-- the US adjective rule: no "Lake Shady"
	local U = PN.lang("usa")
	ok(e(U.gens, "Lake") and e(U.gens, "Lake").flags.e and e(U.specs, "Shady").flags.a, "Lake_ +e, Shady +a")
end)

---------------------------------------------------------------------------
-- the replays and samples

local function fakeDriver(names, pos, ids, list)
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local function wet(x, y) return x > 8000 or (x + 7800) ^ 2 + (y + 5509) ^ 2 < 2200 ^ 2 end
	local sm = T.sampler(function(x, y) return wet(x, y) and 4 or 10 + math.max(0, -y) * 0.002 end, wet, 0)
	local E = { nowUs = function() return 0 end, towns = function() return ids end,
		boxCentre = function(t) local p = pos[t]; if p then return p[1], p[2] end return nil end,
		name = function(t) return names[t] end, log = function() end, sampler = function() return sm end,
		year = function() return 1950 end }
	local d = D.new(E, "[T]")
	d.opts = { townNames = "landscape" }
	d.cfg = { climate = "::/climates/temperate/temperate.clima", nameList = list }
	d.region = list and list:find("usa") and "US" or nil
	d.nameRegion = d.region
	return d, E
end

-- 6 districts (shore, upper, valley, across, lead, clearing) and 3 Works (machine factory, steel mill by rail, fishing
-- harbour) at the first towns of the replay
local DKINDS = { "upper", "valley", "across", "lead", "shore", "clearing" }
local WKINDS = { { "plain", "industries/machine_factory/machine_factory.con" }, { "rail", "industries/steel_mill/steel_mill.con" },
	{ "harbour", "industries/fishing/fishing.con" } }

local function offshoots(lang, towns, res, seed)
	local names, pos, ids = {}, {}, {}
	for i, r in ipairs(res) do names[r.id] = r.new; pos[r.id] = { towns[i].x, towns[i].y }; ids[#ids + 1] = r.id end
	local list = lang == "usa" and "::/names/usa/towns.names.lua" or nil
	local d, E = fakeDriver(names, pos, ids, list)
	local out = { districts = {}, works = {} }
	local nid = 900000
	for k, kind in ipairs(DKINDS) do
		local t = towns[k * 2]
		local site = { x = t.x + 700, y = t.y + 400, kind = kind }
		local nm = d:offshootName("district", { style = { seed = seed + k }, sampler = E.sampler() }, t.id, site, pos[t.id],
			{ saved = {}, seed = seed + k, count = 0, listSeed = seed + k })
		out.districts[#out.districts + 1] = tostring(nm)
		if nm then nid = nid + 1; ids[#ids + 1] = nid; names[nid], pos[nid] = nm, { site.x, site.y } end
	end
	for k, wk in ipairs(WKINDS) do
		local t = towns[k * 3 + 1]
		local site = { x = t.x - 900, y = t.y + 300, kind = wk[1], industry = { file = wk[2] }, ind = "works" }
		local nm = d:offshootName("works", { style = { seed = seed + 50 + k }, sampler = E.sampler() }, t.id, site, pos[t.id],
			{ saved = {}, seed = seed + 50 + k, listSeed = seed + k })
		out.works[#out.works + 1] = tostring(nm)
		if nm then nid = nid + 1; ids[#ids + 1] = nid; names[nid], pos[nid] = nm, { site.x, site.y } end
	end
	return out
end

local function sample(label, lang, towns, o)
	for _, rules in ipairs({ "s53", "s60" }) do
		local res, st = PN.assign(towns, { lang = lang, seed = o.seed or 1, climate = "temperate", year = 1950, rules = rules })
		local m = metrics(towns, res)
		print(string.format("  %s %s %s: %s", label, lang, rules == "s53" and "before (s53)" or "after (s60) ", namesOf(res)))
		print("        " .. mText(m))
		if rules == "s60" then
			if o.offshoots then
				local off = offshoots(lang, towns, res, o.seed or 1)
				print("        districts: " .. table.concat(off.districts, ", "))
				print("        Works: " .. table.concat(off.works, ", "))
			end
			ok(m.desc / m.n >= 0.75, label .. " site words " .. m.desc .. ": " .. table.concat(m.misses, ", "))
			ok(m.opaque <= 1, label .. " opaque " .. m.opaque)
		end
	end
end

test("replay of run 0341 (europe, seed a) and the 1729 sites (usa): before / after, districts and Works (printed)", function()
	print("  0341 in game (s53): " .. OLD0341)
	sample("0341", "en", replayTowns(R0341), { seed = 1, offshoots = true })
	sample("1729", "usa", replayTowns(R1729), { seed = 1, offshoots = true })
	sample("1729", "en", replayTowns(R1729), { seed = 1 })
end)

test("de and fr synthetic maps: 16 towns before / after (printed)", function()
	for _, lang in ipairs({ "de", "fr" }) do
		sample("valley map", lang, NMAP.makeMap(1041, "valley", 16, "temperate"), { seed = 7 })
		sample("coast map", lang, NMAP.makeMap(2083, "coast", 16, "temperate"), { seed = 7 })
	end
end)
