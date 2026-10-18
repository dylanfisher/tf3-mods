-- Organic Towns: the climate fit of names (pure; 2026-10-14, NEXT_PHASE_BRIEF 49 "Plausible, climate-led generated
-- names").
--
-- User (run 2026-10-14_0814_sqot loads 4 and 6, tropical island maps): "make sure names don't sound silly - like lake in
-- the hills on a tropical map where its all islands" and "our names should all be heavily influenced from the region
-- (tropical, subarctic, etc.) otherwise the naming falls apart". So the climate is an input of every naming step:
--   * M.key: the map's climate ("::/climates/tropical/tropical.clima" -> "tropical"; dry, subarctic, temperate).
--   * M.VETO_TAGS: generator tags (ot_placename) a climate never takes: a tropical map no oak / birch / pine / heath /
--     moor, a dry one no marsh / fen / meadow, a subarctic one no palm. Tags of another climate (tropic / arid / boreal)
--     too.
--   * M.SITE: tags the climate adds to every town's site (the generator's tropical / dry / subarctic words: palm, coral,
--     mangrove, reef, lagoon, key; sand, mesa, wadi; fell, birch, snow).
--   * M.wordMisfit(name, climate): a whole-word check of a finished name for the words a climate rules out, per
--     language (Oak / Birch / Pine / Snow on a tropical map, Marsh / Fen / Moss on a dry one, Palm in the subarctic):
--     the composed offshoot names (ot_offname) and the generator's affixes and finished names.
-- Every loop is bounded by the word lists and the name's words (MAX_WORDS). Plain Lua, pre-5.3.

local M = {}

M.MAX_WORDS = 12
M.EXTRA = 9               -- bytes a name word may run past a listed word ("Eichstetten", "Birchwood")
M.CLIMATES = { "temperate", "tropical", "dry", "subarctic" }

--- The climate key of a climate path ("::/climates/dry/dry.clima" -> "dry"), "temperate" by default.
function M.key(path)
	local s = string.lower(tostring(path or ""))
	if s:find("tropic", 1, true) then return "tropical" end
	if s:find("subarctic", 1, true) or s:find("arctic", 1, true) or s:find("boreal", 1, true) then return "subarctic" end
	if s:find("dry", 1, true) or s:find("arid", 1, true) or s:find("desert", 1, true) then return "dry" end
	return "temperate"
end

local function set(s)
	local t = {}
	for w in s:gmatch("%S+") do t[w] = true end
	return t
end

-- generator tags a climate never takes (an entry claiming one of them at weight >= VETO_MIN is not used)
M.VETO_MIN = 0.3
M.VETO_TAGS = {
	temperate = set("tropic arid mangrove reef lagoon mesa wadi palm"),
	tropical = set("oak ash beech birch elm lime maple hazel alder poplar pine fir spruce larch yew holly apple elder heath moor boreal arid snow mesa wadi tarn"),
	dry = set("marsh fen mere pool meadow moor heath tropic boreal mangrove snow alder willow beech birch spruce larch"),
	subarctic = set("palm cypress tropic arid mangrove reef lagoon coral mesa wadi apple"),
}

-- tags a climate adds to every town's site weights (ot_placename.siteTags: some only beside the right feature)
M.SITE = {
	tropical = { tropic = 1, palm = 0.6 },
	dry = { arid = 1 },
	subarctic = { boreal = 1, birch = 0.5, pine = 0.5 },
	temperate = {},
}

-- words of finished names a climate rules out, per language family (lower case; a word that is, or starts with, one)
local W = {}
W.tropical = {
	en = "oak birch birk pine maple cedar elm fir spruce larch aspen cottonwood holly yew beech hazel alder snow frost ice winter heath moor fell tarn",
	de = "eich eiche buch buche birk birke tann tanne fichte kiefer föhre linde ahorn erle schnee eis heide moor",
	fr = "chêne chesnay hêtre fau bouleau sapin érable tilleul neige glace bruyère lande",
	it = "quercia rovere faggio betulla abete larice acero tiglio neve ghiaccio brughiera",
	es = "roble haya abedul abeto arce tilo nieve hielo brezo páramo",
	pt = "carvalho faia vidoeiro abeto ácer tília neve gelo urze",
	nl = "eik eiken beuk berk spar linde esdoorn sneeuw heide veen",
	sv = "björk gran tall lind lönn snö mosse",
	nb = "eik bjørk gran furu lind lønn snø myr",
	ja = "松 杉 樺 楓 雪 氷",
}
W.dry = {
	en = "marsh fen moss bog mere meadow meadows mire swamp wetland moor heath",
	de = "moor sumpf bruch ried fenn wiese aue",
	fr = "marais marécage tourbière prairie",
	it = "palude acquitrino prato",
	es = "marisma pantano ciénaga prado",
	pt = "pântano paul lameiro prado",
	nl = "moeras veen broek weide",
	sv = "kärr myr mosse äng",
	nb = "myr myra mose eng",
	ja = "沼 湿",
}
W.subarctic = {
	en = "palm palms coral mangrove lagoon cay reef orange lemon olive cypress",
	de = "palme palmen koralle lagune",
	fr = "palmier palmeraie corail lagune",
	it = "palma palme corallo laguna",
	es = "palma palmar coral laguna",
	pt = "palmeira coral laguna",
	nl = "palm koraal lagune",
	sv = "palm korall lagun",
	nb = "palme korall lagune",
	ja = "椰子 珊瑚",
}
W.temperate = {
	en = "palm palms coral mangrove lagoon cay reef mesa wadi",
	de = "palme palmen koralle",
	fr = "palmier corail",
	it = "palma corallo",
	es = "palmar coral",
	pt = "palmeira coral",
	nl = "palm koraal",
	sv = "palm korall",
	nb = "palme korall",
	ja = "椰子 珊瑚",
}
M.WORDS = W
M.LANG_OF = { en = "en", usa = "en", de = "de", fr = "fr", it = "it", es = "es", pt = "pt", nl = "nl", sv = "sv", nb = "nb",
	ja = "ja", ja_r = "en", ru = "en", ru_r = "en" }

-- name words that start with a listed word without meaning it ("First Street" is no fir, "Alderman Road" no alder,
-- "Icehouse" stays a building): never a misfit (2026-10-14, stop names)
M.NOT_WORDS = set("first firth alderman aldermans iceland pineapple")

local cache = {}
local function wordsOf(climate, lang)
	local key = (climate or "") .. "|" .. (lang or "")
	if cache[key] then return cache[key] end
	local list = {}
	local t = W[climate or ""]
	if t then
		for w in (t[lang] or ""):gmatch("%S+") do list[#list + 1] = w end
		-- (English words go everywhere: a Latin-script list may borrow them)
		if lang ~= "en" and lang ~= "ja" then for w in (t.en or ""):gmatch("%S+") do list[#list + 1] = w end end
	end
	cache[key] = list
	return list
end

local LOW = { ["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["Å"] = "å", ["Ø"] = "ø", ["Æ"] = "æ", ["É"] = "é", ["È"] = "è",
	["Ê"] = "ê", ["Á"] = "á", ["Í"] = "í", ["Ó"] = "ó", ["Ú"] = "ú", ["Ç"] = "ç" }
local function lower(s)
	s = (tostring(s or ""):gsub("[A-Z]", string.lower))   -- (ASCII only: a locale %u would fold UTF-8 lead bytes)
	return (s:gsub("[\195][\128-\159]", function(ch) return LOW[ch] or ch end))
end

--- The first word of name a climate rules out for list classifier cls, or nil. A name word matches a listed word when
--- it is that word or starts with it and is at most EXTRA bytes longer ("Oakley", "Birchwood", "Eichstedt"); kanji by
--- substring.
function M.wordMisfit(name, climate, cls)
	if type(name) ~= "string" or name == "" or climate == nil then return nil end
	local lang = M.LANG_OF[cls or ""] or "en"
	local list = wordsOf(climate, lang)
	if #list == 0 then return nil end
	if lang == "ja" then
		for _, w in ipairs(list) do if name:find(w, 1, true) then return w end end
		return nil
	end
	local low = lower(name)
	local n = 0
	for word in low:gmatch("[^%s%-'%.,/]+") do
		n = n + 1
		if n > M.MAX_WORDS then break end
		if not M.NOT_WORDS[word] then
			for _, w in ipairs(list) do
				if word == w or (#word > #w and #word <= #w + M.EXTRA and word:sub(1, #w) == w) then return w end
			end
		end
	end
	return nil
end

-- lake words of finished stop names (2026-10-14, NEXT_PHASE_BRIEF 49 "stop names' climate fit": no "Lakeside" on a
-- map without lakes): per language family, matched like M.WORDS; ru / ja by substring (no case folding there)
M.LAKE_WORDS = {
	en = "lake lakes lakeside lakeview lakeshore lakefront mere tarn loch",
	de = "see seeufer seeblick weiher",
	fr = "lac étang",
	it = "lago stagno",
	es = "lago",
	pt = "lago",
	nl = "meer plas",
	sv = "sjö sjön",
	nb = "vann",
	ja = "湖 池 Mizuumi Ike",
	ru = "Озёр озёр Озер озер Пруд пруд Ozyor ozyor Prud prud",
}
M.LAKE_LANG = { en = "en", usa = "en", de = "de", fr = "fr", it = "it", es = "es", pt = "pt", nl = "nl", sv = "sv",
	nb = "nb", ja = "ja", ja_r = "ja", ru = "ru", ru_r = "ru" }
M.SUBSTRING = { ja = true, ru = true }

local lakeCache = {}

--- The first lake word of name for list classifier cls, or nil (a word that is, or starts with, a listed one; ja / ru
--- by substring).
function M.lakeMisfit(name, cls)
	if type(name) ~= "string" or name == "" then return nil end
	local lang = M.LAKE_LANG[cls or ""] or "en"
	local list = lakeCache[lang]
	if list == nil then
		list = {}
		for w in (M.LAKE_WORDS[lang] or ""):gmatch("%S+") do list[#list + 1] = w end
		if lang ~= "en" and not M.SUBSTRING[lang] then
			for w in M.LAKE_WORDS.en:gmatch("%S+") do list[#list + 1] = w end
		end
		lakeCache[lang] = list
	end
	if M.SUBSTRING[lang] then
		for _, w in ipairs(list) do if name:find(w, 1, true) then return w end end
		return nil
	end
	local low = lower(name)
	local n = 0
	for word in low:gmatch("[^%s%-'%.,/]+") do
		n = n + 1
		if n > M.MAX_WORDS then break end
		if not M.NOT_WORDS[word] then
			for _, w in ipairs(list) do
				if word == w or (#word > #w and #word <= #w + M.EXTRA and word:sub(1, #w) == w) then return w end
			end
		end
	end
	return nil
end

--- Does the climate veto tag t?
function M.vetoTag(climate, t)
	local v = M.VETO_TAGS[climate or ""]
	return v ~= nil and v[t] == true
end

return M
