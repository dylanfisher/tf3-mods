-- Plausible, climate-led names (ot_climate, ot_placename, NEXT_PHASE_BRIEF 49, 2026-10-14): the climate vetoes words
-- (no oak / birch / pine / heath on a tropical map, no marsh on a dry one, no palm in the subarctic) and brings its own
-- (palm, coral, key, reef, lagoon; mesa, wash, wells; snow, fell), the town's tags agree with the map survey (no lake word
-- on an island map without lakes), Landscape names never hand out a real list name. Replays of run 2026-10-14_0814_sqot
-- loads 4 (usa, tropical island map) and 6 (europe, same map).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local CL = ug_require(F.DIR .. "ot_climate.lua")
local PN = ug_require(F.DIR .. "ot_placename.lua")
local OFF = ug_require(F.DIR .. "ot_offname.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local DT = ug_require(F.DIR .. "ot_district.lua")

local function tags(s)
	local w = {}
	for t, v in s:gmatch("([%a_]+):([%d%.]+)") do w[t] = tonumber(v) end
	return w
end

-- run 0814 load 4 (usa list, tropical island map): the NAME lines' tags and cues (estuary -> mouth)
local LOAD4 = {
	{ "coast:1.00,headland:0.90,forest:0.73,hill:0.50", "south:0.91,west:0.89" },
	{ "coast:1.00,island:1.00,forest:0.95,headland:0.90,valley:0.60", "bay:1.00,headland:1.00,narrows:1.00,isthmus:1.00,north:0.50" },
	{ "coast:1.00,island:1.00,headland:0.90,forest:0.53,hill:0.48", "bay:1.00,headland:1.00,west:0.90" },
	{ "coast:1.00,island:1.00,headland:0.90,valley:0.60,forest:0.60", "bay:1.00,bigbay:1.00,headland:1.00,north:0.88" },
	{ "coast:1.00,island:1.00,hill:0.90,forest:0.78,headland:0.70", "peak:1.00,bay:1.00,isthmus:1.00,south:0.61" },
	{ "coast:1.00,forest:0.63,headland:0.50,hill:0.31", "bay:1.00,north:0.87,east:0.55" },
	{ "lake:1.00,coast:0.80,hill:0.71,forest:0.55,headland:0.50", "bay:1.00,east:0.82,north:0.72" },
	{ "coast:1.00,headland:0.90,market:0.80,forest:0.76,valley:0.60", "bay:1.00,headland:1.00,west:0.64" },
	{ "lake:1.00,coast:0.80,forest:0.69,valley:0.60,headland:0.50", "bay:1.00,south:0.90" },
	{ "coast:1.00,island:1.00,headland:0.90,forest:0.62,valley:0.60", "bay:1.00,headland:1.00,narrows:1.00,east:0.67" },
	{ "coast:1.00,island:1.00,forest:1.00,headland:0.90,hill:0.53", "bay:1.00" },
	{ "coast:1.00,headland:0.90,forest:0.62,valley:0.60", "bay:1.00,headland:1.00,north:0.66" },
	{ "mouth:0.90,coast:0.80,forest:0.64,hill:0.53,headland:0.50", "mouth:1.00,bay:1.00,east:0.54,south:0.48" },
	{ "coast:1.00,forest:0.94,headland:0.90,hill:0.36,oak:0.6", "bay:1.00,headland:1.00,west:0.62" },
	{ "coast:1.00,island:1.00,headland:0.90,market:0.80,forest:0.77", "bay:1.00,headland:1.00,narrows:1.00,central:0.80" },
	{ "forest:0.62,coast:0.50,headland:0.50,birch:0.5", "central:0.80" },
}

-- the towns of a replay through the driver's steps: the climate's site tags, the survey agreement, the generator
local function replay(lang, climate, list, wn, seed)
	local towns = {}
	local mis = {}
	for i, e in ipairs(list) do
		local raw = tags(e[1])
		-- (the climate's tags as siteTags adds them, on the read's tags)
		local w = {}
		for k, v in pairs(raw) do w[k] = v end
		for t, v in pairs(CL.SITE[climate] or {}) do w[t] = math.max(w[t] or 0, v) end
		if climate == "tropical" and (w.coast or 0) > 0 then w.reef = 0.5 end
		if climate == "tropical" and (w.bay or w.island) then w.lagoon = 0.8 end
		for t in pairs(w) do if CL.vetoTag(climate, t) then w[t] = nil end end
		for _, m in ipairs(PN.agreeSurvey(w, wn)) do mis[#mis + 1] = m end
		local cw = tags(e[2] or "")
		towns[#towns + 1] = { id = i, name = "Town" .. i, x = (i % 4) * 9000, y = math.floor(i / 4) * 9000, w = w,
			cap = 400, cue = { w = cw }, lake = (w.lake or 0) > 0 }
	end
	local res, st = PN.assign(towns, { lang = lang, seed = seed or 7, real = {}, climate = climate })
	return res, st, mis
end

test("climate key: tropical, dry, subarctic, temperate by default", function()
	eq(CL.key("::/climates/tropical/tropical.clima"), "tropical")
	eq(CL.key("::/climates/dry/dry.clima"), "dry")
	eq(CL.key("::/climates/subarctic/subarctic.clima"), "subarctic")
	eq(CL.key("::/climates/temperate/temperate.clima"), "temperate")
	eq(CL.key(nil), "temperate")
	eq(PN.climateKey("::/climates/tropical/tropical.clima"), "tropical")
end)

test("word fit: Oak / Birch / Pine / Heath on a tropical map, Marsh / Fen on a dry one, Palm in the subarctic", function()
	eq(CL.wordMisfit("Oakley Heights", "tropical", "usa"), "oak")
	eq(CL.wordMisfit("Cottonwood Heights", "tropical", "usa"), "cottonwood")
	eq(CL.wordMisfit("Birchwood", "tropical", "en"), "birch")
	eq(CL.wordMisfit("Eichstetten", "tropical", "de"), "eich")
	eq(CL.wordMisfit("Palm Key", "tropical", "usa"), nil)
	eq(CL.wordMisfit("Marshfield", "dry", "en"), "marsh")
	eq(CL.wordMisfit("Palm Springs", "subarctic", "usa"), "palm")
	eq(CL.wordMisfit("Coral Bay", "temperate", "en"), "coral")
	eq(CL.wordMisfit("Ashford", "tropical", "en"), nil)
	eq(CL.wordMisfit("松本", "tropical", "ja"), "松")
end)

test("survey agreement: no lake word on a map whose survey has no lake (run 0814 load 4: Lake in the Hills, Canyon Lake)", function()
	local w = tags("lake:1.00,coast:0.80,hill:0.71")
	local m = PN.agreeSurvey(w, { sea = true, lake = false })
	eq(w.lake, nil)
	ok(w.bay and w.bay > 0 and w.coast >= 0.8, "a sea inlet is coast / bay")
	eq(m[1], "lake:sea")
	local w2 = tags("lake:1.00")
	eq(#PN.agreeSurvey(w2, { sea = false, lake = true }), 0, "a real lake stays")
	eq(w2.lake, 1)
	eq(#PN.agreeSurvey(tags("lake:1.00"), nil), 0, "no survey: unchanged")
end)

local function noWord(nm, list)
	local l = nm:lower()
	for _, w in ipairs(list) do if l:find(w, 1, true) then return false, w end end
	return true
end

test("replays of run 0814 loads 4 (usa) and 6 (europe), tropical island map: no lake, canyon or temperate tree words, island words", function()
	for _, lang in ipairs({ "usa", "en" }) do
		local res, st, mis = replay(lang, "tropical", LOAD4, { sea = true, lake = false })
		ok(#mis >= 2, lang .. " survey misfits " .. #mis)
		local names, trop = {}, 0
		for _, r in ipairs(res) do
			ok(r.new ~= nil, lang .. " named")
			if r.new then
				names[#names + 1] = r.new
				local okW, w = noWord(r.new, { "lake", "canyon", "cottonwood", "oak", "birch", "pine", "maple", "cedar", "elm",
					"heath", "moor", "snow", "hollywood", "mere", "tarn" })
				ok(okW, lang .. " " .. r.new .. " (" .. tostring(w) .. ")")
				eq(CL.wordMisfit(r.new, "tropical", lang), nil, r.new)
				local l = r.new:lower()
				if l:find("palm") or l:find("coral") or l:find("key") or l:find("cay") or l:find("reef") or l:find("lagoon")
					or l:find("mangrove") or l:find("banyan") or l:find("coconut") or l:find("hibiscus") or l:find("frangi") then
					trop = trop + 1
				end
			end
		end
		ok(trop >= 2, lang .. " tropical words on " .. trop .. " of 16: " .. table.concat(names, ", "))
		print(lang .. " tropical (load replay): " .. table.concat(names, ", "))
		print("  misfit=" .. PN.misfitText(st.misfit))
	end
end)

local SITES = {
	"river:1,ford:0.6,forest:0.5", "coast:1,sandy:0.8,bay:0.6", "hill:0.8,hilltop:0.7", "valley:1,vale:0.6",
	"forest:0.9,clearing:0.8", "plain:0.8,field:0.6", "mountain:0.8,hilltop:0.6", "marsh:0.8,fen:0.7",
	"lake:1", "coast:1,headland:0.9,rocky:0.7", "heath:0.6,plain:0.5", "river:1,confluence:1",
}

test("every generator language x every climate: 12 towns named, no word the climate rules out", function()
	for _, lang in ipairs(PN.LANGS) do
		for _, climate in ipairs(CL.CLIMATES) do
			local list = {}
			for _, s in ipairs(SITES) do list[#list + 1] = { s, "" } end
			local res = replay(lang, climate, list, nil, 11)
			ok(res ~= nil, lang .. " " .. climate)
			local n, names = 0, {}
			for _, r in ipairs(res or {}) do
				if r.new then
					n = n + 1
					names[#names + 1] = r.new
					local bad = CL.wordMisfit(r.new, climate, lang)
					ok(bad == nil, lang .. " " .. climate .. ": " .. r.new .. " (" .. tostring(bad) .. ")")
				end
			end
			ok(n >= 11, lang .. " " .. climate .. " named " .. n)
			if lang == "en" or lang == "usa" or lang == "de" then print(lang .. " " .. climate .. ": " .. table.concat(names, ", ")) end
		end
	end
end)

test("offshoot names follow the climate: no Heath / Moor / Wood forms on a tropical map", function()
	for seed = 1, 20 do
		local nm = DT.name("en", "Penkridge", "lead", {}, { seed = seed, site = { climate = "tropical", forestEdge = true } })
		eq(CL.wordMisfit(nm, "tropical", "en"), nil, nm)
		local w = WK.name("en", "Penkridge", "plain", {}, { seed = seed, site = { climate = "dry" } })
		eq(CL.wordMisfit(w, "dry", "en"), nil, w)
	end
end)

test("oceania speaks the English generator; asia none", function()
	eq(PN.listLang("oceania"), "en")
	eq(PN.listLang("asia"), nil)
	eq(PN.langOf("en"), "en")
end)
