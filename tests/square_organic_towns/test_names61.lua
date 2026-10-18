-- Evocative environment names, every character town's kind, the industry as a cue (2026-10-15, NEXT_PHASE_BRIEF 61;
-- evidence `.cache/logs/2026-10-15_0429_sqot-sqrl.log.gz`, seed a, europe, 1950: Seachurch Cove, Bridgeham-under-Dun,
-- Two Waters, Lower Arunmouth ...). User: "i like two waters name a lot. anything that is kind of obviously part of the
-- environment is neat", "if character names don't already factor into city name that would be cool, too" and "city
-- name could potentially take into account what type of industry they are".
--   * evocative names (shape "evoc": Two Waters, Seven Oaks, Windy Ridge, Sandy Point) only where their gate holds on
--     the town's own reading; about 15-25 % of the towns; never repeated;
--   * every character town of a kind carries its kind's form (the strong kinds, deep forest, the secluded towns, the
--     coastal hugger), in every generator language;
--   * the industry cue (shape "industry") only near an industry of that family (within PN.IND_R), at most
--     PN.IND_PER16 per 16 towns, one per family;
--   * the s53 / s60 rules never take the s61 lines;
--   * the 0429 sites (europe) and the 1729 sites (usa) replayed, before (s60) and after (s61), with districts and
--     Works (printed).
-- Quick mode samples 3 seeds per preset; TEST_FULL 10.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local NMAP = loadfile(here .. "namemaps.lua", "t", _ENV)()
local PN = ug_require(F.DIR .. "ot_placename.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local FULL = os.getenv("TEST_FULL") ~= nil
local SEEDS = {}
for s = 1, FULL and 10 or 3 do SEEDS[#SEEDS + 1] = s * 37 + 11 end

local LANGS = { "en", "usa", "de", "fr", "it", "es", "pt", "nl", "sv", "nb", "ja", "ja_r" }
local KINDS = { "hilltop", "harbour", "cove", "street", "company", "garden", "island", "market", "forest", "secluded",
	"coastal" }
local FAMS = { "fish", "oil", "clay", "coal", "stone", "timber", "farm", "iron" }
-- (the industry families a site kind's industry may be: fishing on the coast, oil on the coast or plain ...)
local SITE_FAMS = { coast = { "fish", "oil" }, cliff = { "fish", "stone" }, spit = { "fish" }, island = { "fish" },
	mouth = { "fish", "iron" }, plain = { "farm", "clay" }, edge = { "timber", "farm" }, forest = { "timber" },
	hill = { "coal", "stone" }, pass = { "stone", "coal" }, moor = { "coal" }, gorge = { "stone" }, river = { "iron", "clay" },
	marsh = { "clay" }, vale = { "farm" }, lake = { "fish" } }

local function parseW(s)
	local w = {}
	for k, v in s:gmatch("([%a_]+):([%d%.]+)") do w[k] = tonumber(v) end
	return w
end

-- a synthetic map with industries: about 40 % of the towns have one, at 200-2600 m (beyond PN.IND_R: no cue)
local function withIndustry(towns, seed)
	for i, t in ipairs(towns) do
		if rng.unit(seed, "hasInd", i) < 0.4 then
			local kind = nil
			for k, v in pairs(NMAP.SITES) do
				local w = NMAP.tags(v)
				local same = true
				for tag in pairs(w) do if t.w[tag] == nil and tag ~= "character" then same = false break end end
				if same and SITE_FAMS[k] then kind = kind or k end
			end
			local fams = SITE_FAMS[kind or "plain"] or { "farm" }
			t.ind = { fam = fams[rng.hash(seed, "fam", i) % #fams + 1], d = 200 + rng.unit(seed, "indD", i) * 2400 }
		end
	end
	return towns
end

local function wrawOf(t) return PN.withCues(t.w, t.cue) end

local function inSet(set, raw) return set ~= nil and raw ~= nil and set[raw] == true end

---------------------------------------------------------------------------
-- the inventories

test("every generator language: evocative names with gates, every kind's forms, every industry family", function()
	ok(#PN.BAD == 0, "unknown tags in the inventories: " .. table.concat(PN.BAD, " "))
	for _, lang in ipairs(LANGS) do
		local L = PN.lang(lang)
		local evoc, fams, byRaw = 0, {}, {}
		for _, a in ipairs(L.affixes) do
			byRaw[a.raw or ""] = a
			if a.flags.g then
				evoc = evoc + 1
				eq(a.shape, "evoc", lang .. " " .. a.text .. ": the evoc shape")
				ok(type(a.gate) == "table" and #a.gate > 0, lang .. " " .. a.text .. ": a gate")
				ok(a.bare == nil and not a.hasS, lang .. " " .. a.text .. ": a whole name")
				ok(a.flags["61"], lang .. " " .. a.text .. ": +61")
			end
			if a.flags.i then
				fams[a.fam or "-"] = (fams[a.fam or "-"] or 0) + 1
				eq(a.shape, "industry", lang .. " " .. a.text .. ": the industry shape")
			end
		end
		ok(evoc >= 15, lang .. " evocative names: " .. evoc)
		for _, f in ipairs(FAMS) do ok((fams[f] or 0) >= 2, lang .. " industry family " .. f .. ": " .. (fams[f] or 0)) end
		for _, k in ipairs(KINDS) do
			local set = L.charForms61[k]
			ok(set ~= nil and next(set) ~= nil, lang .. " forms of kind " .. k)
			for raw in pairs(set or {}) do ok(byRaw[raw] ~= nil, lang .. " " .. k .. ": the form " .. raw .. " is an affix") end
		end
	end
	-- (the s60 tables stay: en / usa base charForms only, the other languages none)
	ok(next(PN.lang("de").charForms) == nil and PN.lang("en").charForms.forest == nil, "base charForms unchanged")
end)

test("gates: an evocative name only where the reading holds it", function()
	local L = PN.lang("en")
	local function a(text) for _, x in ipairs(L.affixes) do if x.text == text and x.flags.g then return x end end end
	ok(PN.gateOk(a("Two Waters"), { confluence = 1, river = 1 }), "Two Waters at a confluence")
	ok(not PN.gateOk(a("Two Waters"), { river = 1, bridge = 0.6 }), "no Two Waters on a plain river")
	ok(not PN.gateOk(a("Two Waters"), { confluence = 0.3 }), "no Two Waters on a weak reading")
	ok(PN.gateOk(a("Sandy Point"), { sandy = 0.8, spit = 1 }) and PN.gateOk(a("Sandy Point"), { sandy = 0.8, headland = 0.9 }),
		"Sandy Point: sand and a spit or headland")
	ok(not PN.gateOk(a("Sandy Point"), { sandy = 0.8, coast = 1 }), "no Sandy Point without a point")
	ok(not PN.gateOk(a("Seven Oaks"), { forest = 1, ash = 0.9 }), "no Seven Oaks in an ash wood")
	ok(PN.gateOk(a("Bridgend"), { river = 1, bridge = 0.9 }) and not PN.gateOk(a("Bridgend"), { river = 1, bridge = 0.6 }),
		"Bridgend only at a wide river's bridge")
	local U = PN.lang("usa")
	local tl
	for _, x in ipairs(U.affixes) do if x.text == "Twin Lakes" then tl = x end end
	ok(PN.gateOk(tl, { lake = 1 }, { lakes = 2 }) and not PN.gateOk(tl, { lake = 1 }, { lakes = 1 }), "Twin Lakes: two lakes near")
	eq(PN.gateText(a("Two Waters"), { confluence = 1 }), "confluence:1.00")
end)

---------------------------------------------------------------------------
-- the maps

local function sweep(lang, presets, climate)
	local agg = { n = 0, evoc = 0, ind = 0, charN = 0, charCue = 0, maps = 0, evocMaps = 0 }
	for pi, preset in ipairs(presets) do
		for si, seed in ipairs(SEEDS) do
			local n = (si + pi) % 2 == 0 and 16 or 24
			local towns = withIndustry(NMAP.makeMap(seed + pi * 1000, preset, n, climate or "temperate"), seed)
			-- (a strong kind and the s61 kinds on the map: deep forest, a secluded town, the coastal hugger)
			-- (on every other map: the s61 kinds as well, deep forest, a secluded town, the coastal hugger; the driver
			-- has 2-5 such towns per 16)
			towns[3].character = KINDS[(seed + pi) % 8 + 1]
			if si % 2 == 1 then
				towns[9].character = "secluded"
				towns[5].character = "forest"
				towns[7].character = "coastal"
			end
			local res, st = PN.assign(towns, { lang = lang, seed = seed, climate = climate })
			local label = string.format("%s %s/%d/%d", lang, preset, seed, n)
			local seen, perFam, nInd, nEv = {}, {}, 0, 0
			for i, r in ipairs(res) do
				local inf = r.info or {}
				ok(not seen[r.new], label .. ": " .. r.new .. " twice")
				seen[r.new] = true
				if inf.shape == "evoc" then
					nEv = nEv + 1
					ok(PN.gateOk(inf.aE, wrawOf(towns[i]), towns[i].facts), label .. " " .. r.new .. ": its gate on " ..
						PN.rankedText(PN.rankOf(wrawOf(towns[i])), 6))
				end
				if inf.shape == "industry" then
					nInd = nInd + 1
					local ind = towns[i].ind
					ok(ind ~= nil and ind.d <= PN.IND_R and inf.aE.fam == ind.fam, label .. " " .. r.new .. ": its industry near")
					ok(not perFam[inf.aE.fam], label .. " industry family " .. tostring(inf.aE.fam) .. " twice")
					perFam[inf.aE.fam] = true
					eq(inf.ind, ind.fam, label .. " info.ind")
				end
				local k = towns[i].character
				if type(k) == "string" then
					agg.charN = agg.charN + 1
					local set = PN.lang(lang).charForms61[k]
					local hit = inf.shape == "character" and inSet(set, inf.aE and inf.aE.raw)
					ok(hit, label .. " " .. k .. ": " .. r.new .. " carries its kind")
					if hit then agg.charCue = agg.charCue + 1 end
				end
			end
			ok(nInd <= math.max(1, math.floor(n * PN.IND_PER16 / 16 + 0.5)), label .. " industry names " .. nInd)
			ok(nEv <= math.floor(n * PN.EVOC_MAX), label .. " evocative names " .. nEv)
			eq(st.shapes.evoc, nEv, label .. " st.shapes.evoc")
			eq(st.shapes.indCue, nInd, label .. " st.shapes.indCue")
			agg.n, agg.evoc, agg.ind, agg.maps = agg.n + n, agg.evoc + nEv, agg.ind + nInd, agg.maps + 1
			if nEv > 0 then agg.evocMaps = agg.evocMaps + 1 end
		end
	end
	print(string.format("  %-4s %d maps, %d towns: evocative %.0f %% (on %d maps), industry %.2f / 16, characters %d / %d with their kind",
		lang, agg.maps, agg.n, 100 * agg.evoc / agg.n, agg.evocMaps, 16 * agg.ind / agg.n, agg.charCue, agg.charN))
	return agg
end

for _, lang in ipairs(LANGS) do
	test("§61 maps, " .. lang .. ": evocative on their gates (15-25 %), every character kind, industry near only, no repeats", function()
		local a = sweep(lang, NMAP.PRESET_ORDER)
		local sh = a.evoc / a.n
		-- (these maps carry four character towns and the industries on every other map: they take the strongest sites,
		-- so the share is lower here than on the plain maps below)
		ok(sh >= 0.09 and sh <= 0.25, string.format("%s evocative share %.2f", lang, sh))
		ok(16 * a.ind / a.n <= PN.IND_PER16 and a.ind > 0, string.format("%s industry names %.2f per 16", lang, 16 * a.ind / a.n))
		eq(a.charCue, a.charN, lang .. " every character town carries its kind")
	end)
end

test("evocative share 14-25 % on maps with the usual two character towns (every language)", function()
	for _, lang in ipairs(LANGS) do
		local n, ev = 0, 0
		for pi, preset in ipairs(NMAP.PRESET_ORDER) do
			for _, seed in ipairs(SEEDS) do
				local towns = NMAP.makeMap(seed + pi * 1000, preset, 16, "temperate")
				local _, st = PN.assign(towns, { lang = lang, seed = seed })
				n, ev = n + 16, ev + (st.shapes.evoc or 0)
			end
		end
		print(string.format("  %-4s evocative %.0f %% of %d towns", lang, 100 * ev / n, n))
		ok(ev / n >= 0.14 and ev / n <= 0.25, string.format("%s evocative share %.2f", lang, ev / n))
	end
end)

test("the industry cue: none without an industry near, none beyond IND_R, none on a family without forms", function()
	for _, seed in ipairs(SEEDS) do
		local towns = NMAP.makeMap(seed, "valley", 16, "temperate")
		for i, t in ipairs(towns) do t.ind = { fam = "oil", d = PN.IND_R + 100 + i } end
		towns[4].ind = { fam = "chem", d = 300 }
		local res = PN.assign(towns, { lang = "en", seed = seed })
		for _, r in ipairs(res) do ok(r.info.shape ~= "industry", "no industry name: " .. r.new) end
		towns[4].ind = { fam = "oil", d = 300 }
		res = PN.assign(towns, { lang = "en", seed = seed })
		eq(res[4].info.shape, "industry", "the one oil town near its well: " .. res[4].new)
	end
end)

test("the s53 and s60 rules never take the s61 lines; deep forest / coastal are no character towns there", function()
	for _, rules in ipairs({ "s53", "s60" }) do
		for _, seed in ipairs(SEEDS) do
			local towns = withIndustry(NMAP.makeMap(seed, "coast", 16, "temperate"), seed)
			towns[5].character, towns[7].character, towns[9].character = "forest", "coastal", "secluded"
			local res, st = PN.assign(towns, { lang = "en", seed = seed, rules = rules })
			for i, r in ipairs(res) do
				local inf = r.info or {}
				ok(inf.shape ~= "evoc" and inf.shape ~= "industry", rules .. ": " .. r.new)
				ok(not (inf.aE and inf.aE.flags["61"]), rules .. " an s61 line: " .. r.new)
				if i == 5 or i == 7 or i == 9 then ok(inf.shape ~= "character", rules .. " kind " .. towns[i].character .. ": " .. r.new) end
			end
			eq(st.shapes.rules, rules)
		end
	end
end)

---------------------------------------------------------------------------
-- the replays

-- run 0429 (seed a, europe, temperate, 1950; the 0341 map): id, x, y, tags, cues, survey river (Arun 1, Dart 2, Dove 3),
-- own lake, cap, altitude, kind (strong, the driver's s61 kinds: forest, secluded, coastal), the industry near (the
-- run's industry renames: the town each one was named after, at an assumed 900 m), the game's s60 name
local R0429 = {
	{ 60255, -2012, -2748, "lake:1.00,character:1.00,forest:0.54,hill:0.51,small:0.48,new:0.42", "peak:1.00,bay:1.00,mainvalley:0.90,lower:0.85,range:0.80,south:0.43", 1, false, 397, 1, "cove", nil, "Seachurch Cove" },
	{ 60256, -1696, 44, "bend:1.08,river:0.90,bridge:0.90,forest:0.76,market:0.64,big:0.64", "confluence:1.00,peak:1.00,mainvalley:0.90,central:0.80,range:0.80", 1, false, 907, 1, nil, nil, "Bridgeham-under-Dun" },
	{ 60257, -5500, -5320, "mere:1.08,lake:1.00,character:1.00,vale:0.77,valley:0.50,new:0.42", "confluence:1.00,mouth:1.00,west:0.72,south:0.70,upper:0.70", 2, true, 560, 3, "secluded", "clay", "Two Waters" },
	{ 60258, -7256, 4896, "bend:1.08,lake:1.00,river:0.90,bridge:0.90,oak:0.77,forest:0.68", "mouth:1.00,west:0.90,bend:0.90,mainvalley:0.90,lower:0.87,north:0.66", 1, false, 392, 1, nil, "timber", "Lower Arunmouth" },
	{ 60259, 2804, 144, "ash:1.09,mere:1.08,lake:1.00,edge:0.70,forest:0.59,small:0.48", "east:0.44", nil, true, 258, 2, nil, nil, "Shaw" },
	{ 60260, 364, 2640, "forest:0.49,new:0.42,field:0.42,plain:0.39", "mainvalley:0.90,north:0.42", nil, false, 535, 1, nil, "timber", "Wheatden" },
	{ 60261, -3968, 2568, "lake:1.00,oak:0.82,edge:0.70,small:0.48,new:0.42,forest:0.41", "bay:1.00,mainvalley:0.90,west:0.56,north:0.41", 1, true, 357, 1, nil, "fish", "Oakhaven" },
	{ 60262, 1436, 6640, "ash:1.20,character:1.00,market:0.64,big:0.64,forest:0.58,field:0.42", "mainvalley:0.90,north:0.84", nil, false, 709, 1, "garden", nil, "Ashminster Garden City" },
	{ 60263, 4340, 3204, "spit:1.50,headland:1.26,rocky:0.77,coast:0.54,oak:0.48,new:0.42", "biglake:1.00,narrows:1.00,east:0.60,north:0.48", nil, true, 644, 2, "coastal", "oil", "Hornness" },
	{ 60264, -2412, 7324, "edge:0.70,forest:0.58,small:0.48,new:0.42,hill:0.31,field:0.18", "confluence:1.00,north:0.91,mainvalley:0.90", 1, false, 316, 3, nil, "farm", "Abercoed" },
	{ 60265, 4280, -6416, "ash:0.94,vale:0.77,forest:0.53,valley:0.50,small:0.48,new:0.42", "south:0.81,east:0.59", 3, false, 284, 1, nil, nil, "Upper Doveley" },
	{ 60266, 7124, -616, "oak:0.78,forest:0.59,small:0.48,new:0.42,field:0.20", "east:0.89", nil, false, 257, 2, nil, nil, "Monkton" },
	{ 60267, 5516, -3240, "mere:1.08,lake:1.00,vale:0.77,edge:0.70,forest:0.64,valley:0.50", "east:0.72,south:0.48", nil, true, 446, 1, nil, "oil", "Meregrove-on-Brantmere" },
	{ 60268, 5004, 6388, "ash:0.97,edge:0.70,small:0.48,forest:0.48,new:0.42,hill:0.33", "north:0.81,east:0.67", nil, false, 340, 1, nil, "oil", "New Wood" },
	{ 60269, 1780, -3508, "forest:0.80,vale:0.77,oak:0.64,valley:0.50,new:0.42,field:0.30", "south:0.51", nil, false, 469, 1, nil, "farm", "Norfield" },
	{ 60270, 724, -6788, "foot:1.17,clearing:1.08,character:1.00,forest:0.90,hill:0.51,new:0.42", "confluence:1.00,mouth:1.00,south:0.85,lower:0.76", 3, false, 418, 1, "forest", "fish", "Doveley" },
}

-- run 1729 load 4 (seed a, usa list, temperate; test_names60 R1729) with the s61 kinds and industries as above
local R1729 = {
	{ 60255, -2400, -2600, "lake:1,forest:.54,hill:.51,small:.48", "peak:1,bay:1,mainvalley:.9,lower:.85,range:.8,south:.43", 1, false, nil, nil, "harbour" },
	{ 60256, -1147, 626, "bend:1,river:.9,bridge:.9,forest:.75,market:.64,big:.64", "confluence:1,peak:1,mainvalley:.9,central:.8,range:.8", 1, false },
	{ 60257, -6277, -5509, "mere:1,lake:1,vale:.77,valley:.5,forest:.32,field:.16", "confluence:1,mouth:1,west:.72,south:.7,upper:.7", 2, true, nil, nil, "secluded", "clay" },
	{ 60258, -6771, 5532, "bend:1,lake:1,river:.9,bridge:.9,oak:.77,forest:.68", "mouth:1,west:.9,bend:.9,mainvalley:.9,lower:.87,north:.66", 1, false, nil, nil, nil, "timber" },
	{ 60259, 6200, -6600, "ash:1,mere:1,lake:1,edge:.7,forest:.59,small:.48", "east:.44", nil, true },
	{ 60260, -157, 2251, "forest:.49,field:.42,plain:.4", "mainvalley:.9,north:.42", nil, false, nil, nil, nil, "timber" },
	{ 60261, -3787, 1789, "lake:1,oak:.83,edge:.7,small:.48,forest:.41,field:.18", "bay:1,mainvalley:.9,west:.56,north:.41", 1, true, nil, nil, nil, "fish" },
	{ 60262, 436, 6618, "ash:1,character:1,market:.64,big:.64,forest:.57,field:.42", "mainvalley:.9,north:.84", nil, false, nil, nil, "garden" },
	{ 60263, 4438, 3998, "spit:1,headland:1,rocky:.77,coast:.54,oak:.48,forest:.38", "biglake:1,narrows:1,east:.6,north:.48", nil, true, nil, nil, "coastal", "oil" },
	{ 60264, -2898, 6688, "edge:.7,forest:.58,small:.48,hill:.31,field:.18", "confluence:1,north:.91,mainvalley:.9", 1, false, nil, nil, nil, "farm" },
	{ 60265, 3454, -5706, "ash:.93,vale:.77,forest:.51,valley:.5,small:.48,field:.37", "south:.81,east:.59", 3, false },
	{ 60266, 6668, -153, "oak:.79,forest:.58,small:.48,field:.2", "east:.89", nil, false, nil, nil, nil, "coal" },
	{ 60267, 4945, -3426, "mere:1,lake:1,vale:.77,edge:.7,forest:.65,valley:.5", "east:.72,south:.48", nil, true, nil, nil, nil, "oil" },
	{ 60268, 5426, 5893, "ash:.97,edge:.7,forest:.49,small:.48,hill:.33,field:.15", "north:.81,east:.67", nil, false },
	{ 60269, 2218, -2609, "forest:.83,vale:.77,oak:.63,valley:.5,field:.3,plain:.23", "south:.51", nil, false, nil, nil, nil, "farm" },
	{ 60270, 682, -5989, "foot:1,clearing:1,character:1,forest:.9,hill:.51,church:.32", "confluence:1,mouth:1,south:.85,lower:.76", 3, false, nil, nil, "forest", "fish" },
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
			river = r[6] ~= nil, lake = r[7], ind = r[11] and { fam = r[11], d = 900 } or nil }
	end
	return towns
end

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

local function namesOf(res)
	local out = {}
	for _, r in ipairs(res) do out[#out + 1] = r.new end
	return table.concat(out, ", ")
end

local function sample(label, lang, towns, seed)
	for _, rules in ipairs({ "s60", "s61" }) do
		local res, st = PN.assign(towns, { lang = lang, seed = seed, climate = "temperate", year = 1950, rules = rules })
		print(string.format("  %s %s %s: %s", label, lang, rules == "s60" and "before (s60)" or "after (s61) ", namesOf(res)))
		local sh = st.shapes
		print(string.format("        evoc %d, charCue %d/%d, indCue %d, multi %d, quiet %d", sh.evoc or 0, sh.charCue or 0,
			sh.charN or 0, sh.indCue or 0, sh.multi or 0, sh.quiet or 0))
		if rules == "s61" then
			local off = offshoots(lang, towns, res, seed)
			print("        districts: " .. table.concat(off.districts, ", "))
			print("        Works: " .. table.concat(off.works, ", "))
			local seen = {}
			for i, r in ipairs(res) do
				ok(not seen[r.new], label .. " " .. r.new .. " twice")
				seen[r.new] = true
				local k = towns[i].character
				if type(k) == "string" then
					ok(r.info.shape == "character", label .. " " .. k .. ": " .. r.new .. " carries its kind")
				end
			end
			ok((sh.evoc or 0) >= 2 and (sh.evoc or 0) <= 4, label .. " evocative names " .. tostring(sh.evoc))
			ok((sh.indCue or 0) >= 1 and (sh.indCue or 0) <= 2, label .. " industry names " .. tostring(sh.indCue))
		end
	end
end

test("replay of run 0429 (europe, seed a) and the 1729 sites (usa): before (s60) / after (s61), districts and Works (printed)", function()
	local old = {}
	for _, r in ipairs(R0429) do old[#old + 1] = r[12] end
	print("  0429 in game (s60): " .. table.concat(old, ", "))
	sample("0429", "en", replayTowns(R0429), 1)
	sample("1729", "usa", replayTowns(R1729), 1)
end)

test("de and fr synthetic maps with the s61 kinds and industries: 16 towns before / after (printed)", function()
	for _, lang in ipairs({ "de", "fr" }) do
		local towns = withIndustry(NMAP.makeMap(1041, "valley", 16, "temperate"), 3)
		towns[5].character, towns[7].character, towns[9].character = "forest", "coastal", "secluded"
		for _, rules in ipairs({ "s60", "s61" }) do
			local res, st = PN.assign(towns, { lang = lang, seed = 7, climate = "temperate", year = 1950, rules = rules })
			print(string.format("  valley map %s %s: %s", lang, rules, namesOf(res)))
			print(string.format("        evoc %d, charCue %d/%d, indCue %d", st.shapes.evoc or 0, st.shapes.charCue or 0,
				st.shapes.charN or 0, st.shapes.indCue or 0))
		end
	end
end)

test("driver: the naming phase's s61 kinds: deep forest (at most DEEP_MAX, the plan's pick follows), secluded, coastal", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local FO = ug_require(F.DIR .. "ot_forest.lua")
	local E = { nowUs = function() return 0 end, log = function() end, year = function() return 1950 end,
		towns = function() return { 1, 2, 3, 4, 5, 6, 7 } end, boxCentre = function(t) return t * 3000, 0 end,
		name = function(t) return "T" .. t end }
	local d = D.new(E, "[T]")
	function d:charKindOf(t) return t == 1 and "hilltop" or nil end
	function d:coastalOf(t) return t == 6 and { coastal = true } or nil end
	local oldSite = FO.deepSite
	FO.deepSite = function(fg) return fg.deep == true, fg.ring or 0.5, 6 end
	local towns = {}
	for i = 1, 7 do
		towns[i] = { id = i, character = false }
		d:townState(i).forest = { done = true, deep = i >= 2 and i <= 5, ring = 0.4 + i * 0.05 }
	end
	towns[1].character = "hilltop"
	towns[7].character = true
	local okR, err = pcall(d.namesKinds, d, towns, 0)
	FO.deepSite = oldSite
	ok(okR, tostring(err))
	eq(towns[1].character, "hilltop", "a strong kind stays")
	local deep = 0
	for i = 2, 5 do
		if towns[i].character == "forest" then
			deep = deep + 1
			eq(d:townState(i).nameDeep, true, "named deep: the plan's pick follows")
		else
			eq(d:townState(i).nameDeep, false, "named otherwise: never deep this session")
		end
	end
	ok(deep >= 1 and deep <= FO.DEEP_MAX, "deep forest towns " .. deep)
	eq(towns[6].character, "coastal", "the coastal hugger")
	eq(towns[7].character, "secluded", "a secluded character town")
	-- the plan's deep pick follows the name: named skips the draw, named otherwise never deep
	local fg = { done = true }
	local d1, w1 = FO.deepPick(fg, nil, { named = false })
	eq(d1, false)
	ok(w1 == "noStyle" or tostring(w1):find("names"), tostring(w1))
end)
