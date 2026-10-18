-- Organic Towns: the map's word budget, tag rarity, landscape cue words and clean list names (pure; 2026-10-14,
-- NEXT_PHASE_BRIEF 45 "Names from the map's shape").
--
-- User (run 2026-10-14_0710_sqot, USA list, Landscape names): "we have too many repeat words in city names. lake,
-- woods, etc. it sounds unrealistic and silly when its like that." 9 of 16 starting towns carried Lake / Forest
-- (Forest Lake, Canyon Lake, Lake Forest, Kendale Lakes, Lake in the Hills, Lauderdale Lakes, Wake Forest, Park Forest,
-- Forest Hills): `lake` read 1.00 on 6 towns, `forest` on 15.
--   * M.WORDS: the generic landscape words per name-list classifier (Lake / Lakes, Forest, Woods, Park, Grove, Hill(s),
--     Heights, Bay, Falls, Creek, River, Valley, Springs ... and each language's equivalents and suffixes: -see, -wald,
--     -berg, -sjön, 湖 ...), each under a family key ("lake", "forest", ...). M.keys(name, cls) -> the keys a name carries.
--   * The budget (M.newBudget / check / add / remove): each key at most about 1 per PER_TOWNS towns on the map (at
--     least 1; SOFT keys twice that: -ford, -bridge, 山, which whole regions are named with) and never twice within
--     NEAR_M (5 km; SOFT keys half that), counting towns, districts, Works and satellites. A derived name (district,
--     Works, satellite) doesn't pay again for the words of its parent's name (skip keys). The log line `NAMES words
--     used= held=` comes from usedText / heldText.
--   * Rarity (M.rarity / applyRarity): a site tag most towns share weighs little (as the species read does): factor 1
--     up to RARE_SHARE of the towns, falling to RARE_MIN for a tag every town reads. Town meta tags (big, small,
--     character ...) and the compass tags are exempt.
--   * Landscape cue words (M.CUES, M.cuesOf): a real list name that says "North", "Upper", "Forks", "Falls", "Bend",
--     "Gap", "Summit", "Mount" ... gets that cue (ot_names prefers such names where the map survey, ot_mapshape, found
--     the matching feature, and avoids them where it didn't).
--   * M.clean: list disambiguators off ("Milford city " in usa/en/towns.lua, "(city)", "(CDP)", trailing blanks).
-- Every loop is bounded by the name's words (MAX_WORDS), the lexicons and the budget's entries (MAX_ENTRIES). Plain
-- Lua, pre-5.3.

local M = {}

M.PER_TOWNS = 8           -- a generic word at most once per this many towns ...
M.NEAR_M = 5000           -- ... and never twice within this distance
M.SOFT_K = 2              -- SOFT keys: twice the count, half the distance
M.MAX_WORDS = 12
M.MAX_ENTRIES = 4000      -- names the budget holds at most
M.RARE_SHARE = 0.2        -- rarity: a tag on up to this share of the towns keeps its full weight ...
M.RARE_MIN = 0.3          -- ... one on every town weighs this much
M.RARE_MIN_W = 0.3        -- a town counts for a tag's share from this weight
M.RARE_MIN_TOWNS = 4      -- fewer towns: no rarity

---------------------------------------------------------------------------
-- strings

local UP = { ["à"] = "À", ["á"] = "Á", ["â"] = "Â", ["ä"] = "Ä", ["å"] = "Å", ["æ"] = "Æ", ["ç"] = "Ç", ["è"] = "È",
	["é"] = "É", ["ê"] = "Ê", ["í"] = "Í", ["ñ"] = "Ñ", ["ó"] = "Ó", ["ô"] = "Ô", ["ö"] = "Ö", ["ø"] = "Ø", ["ú"] = "Ú",
	["ü"] = "Ü", ["ō"] = "Ō", ["ū"] = "Ū", ["î"] = "Î", ["ë"] = "Ë", ["ï"] = "Ï" }
local DOWN = {}
for k, v in pairs(UP) do DOWN[v] = k end
local LOWER = {}
for c = 65, 90 do LOWER[string.char(c)] = string.char(c + 32) end

--- Lower case: ASCII and the Latin-1 / macron capitals (string.lower follows the C locale and breaks UTF-8 bytes).
function M.lower(s)
	s = (tostring(s or ""):gsub("[A-Z]", LOWER))
	return (s:gsub("[\195\197][\128-\191]", function(ch) return DOWN[ch] or ch end))
end

--- A word's singular for counting: a final -s (-es after s / x / ch / sh) off words of 5+ bytes ("forks" -> "fork",
--- "oaks" stays 4: the lexicons list those), never -ss ("moss").
function M.fold(w)
	if type(w) ~= "string" or #w < 5 or w:sub(-1) ~= "s" or w:sub(-2) == "ss" then return w end
	if w:sub(-3) == "xes" or w:sub(-4) == "ches" or w:sub(-4) == "shes" then return w:sub(1, -3) end
	return w:sub(1, -2)
end

local function words(low)
	local out = {}
	for w in low:gmatch("[^ \t%-'%.,/]+") do
		out[#out + 1] = w
		if #out >= M.MAX_WORDS then break end
	end
	return out
end

-- disambiguator words a list may leave behind ("Milford city " is the usa list's "Milford (city)"): only lower case
-- (the "City" of Kansas City is part of the name)
M.DISAMBIG = { city = true, town = true, village = true, borough = true, township = true, CDP = true, cdp = true }

--- The name without a list's disambiguator: "Milford city " -> "Milford", "Salem (city)" -> "Salem", "X (CDP)" -> "X";
--- blanks trimmed. Other names unchanged.
function M.clean(name)
	if type(name) ~= "string" then return name end
	local s = name:gsub("^%s+", ""):gsub("%s+$", "")
	local inner = s:match("^.-%s*%(([^()]*)%)$")
	if inner ~= nil then
		local base = s:match("^(.-)%s*%([^()]*%)$")
		if base and base ~= "" then s = base end
	end
	local base, last = s:match("^(.+)%s+(%S+)$")
	if base and last and M.DISAMBIG[last] and (name:find("%s$") or last == "CDP" or last == "cdp") then s = base end
	s = s:gsub("%s%s+", " ")
	if s == "" then return name end
	return s
end

---------------------------------------------------------------------------
-- the generic landscape words: W(key, how, text): how = "w" (a whole word), "e" (a word ending, 2+ letters before it),
-- "s" (a word start, 2+ letters after it), "h" (the raw name holds it: kanji, Cyrillic)

local function W(key, how, text) return { key, how, text } end

local function set(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e end
	return out
end

M.WORDS = {}
M.WORDS.usa = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "w", "north"), W("south", "w", "south"), W("east", "w", "east"), W("west", "w", "west"), W("north", "s", "north"), W("south", "s", "south"), W("east", "s", "east"), W("west", "s", "west"), W("central", "w", "central"), W("central", "w", "middle"), W("upper", "w", "upper"), W("lower", "w", "lower"),
	W("lake", "w", "lake"), W("lake", "w", "lakes"), W("lake", "s", "lake"), W("forest", "w", "forest"), W("woods", "w", "woods"),
	W("woods", "w", "wood"), W("woods", "e", "wood"), W("woods", "e", "woods"), W("park", "w", "park"),
	W("grove", "w", "grove"), W("grove", "e", "grove"), W("hills", "w", "hill"), W("hills", "w", "hills"),
	W("heights", "w", "heights"), W("bay", "w", "bay"), W("falls", "w", "falls"), W("falls", "w", "rapids"),
	W("creek", "w", "creek"), W("river", "w", "river"), W("valley", "w", "valley"), W("springs", "w", "springs"),
	W("springs", "w", "spring"), W("beach", "w", "beach"), W("harbor", "w", "harbor"), W("harbor", "w", "harbour"),
	W("point", "w", "point"), W("island", "w", "island"), W("island", "w", "isle"), W("ridge", "w", "ridge"),
	W("mount", "w", "mount"), W("mount", "w", "mountain"), W("meadows", "w", "meadows"), W("meadows", "w", "meadow"),
	W("oaks", "w", "oaks"), W("oaks", "w", "oak"), W("pines", "w", "pines"), W("pines", "w", "pine"),
	W("glen", "w", "glen"), W("dale", "w", "dale"), W("dale", "e", "dale"), W("view", "w", "view"), W("view", "e", "view"),
	W("brook", "w", "brook"), W("brook", "e", "brook"), W("canyon", "w", "canyon"), W("bluff", "w", "bluff"),
	W("bluff", "w", "bluffs"), W("rock", "w", "rock"), W("shores", "w", "shore"), W("shores", "w", "shores"),
	W("cove", "w", "cove"), W("hollow", "w", "hollow"), W("marsh", "w", "marsh"), W("prairie", "w", "prairie"),
	W("plains", "w", "plains"), W("fork", "w", "fork"), W("fork", "w", "forks"), W("bend", "w", "bend"),
	W("gap", "w", "gap"), W("summit", "w", "summit"), W("pond", "w", "pond"), W("ford", "e", "ford"),
})
M.WORDS.en = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "s", "north"), W("south", "s", "south"), W("east", "s", "east"), W("west", "s", "west"), W("north", "w", "north"), W("south", "w", "south"), W("east", "w", "east"), W("west", "w", "west"), W("upper", "w", "upper"), W("lower", "w", "lower"), W("lower", "w", "nether"),
	W("lake", "w", "lake"), W("lake", "e", "mere"), W("lake", "w", "mere"), W("lake", "w", "water"), W("lake", "e", "water"),
	W("lake", "e", "tarn"), W("forest", "w", "forest"), W("wood", "w", "wood"), W("wood", "e", "wood"),
	W("wood", "w", "woods"), W("wood", "e", "hurst"), W("wood", "e", "holt"), W("park", "w", "park"),
	W("grove", "e", "grove"), W("grove", "w", "grove"), W("hill", "w", "hill"), W("hill", "e", "hill"),
	W("down", "e", "down"), W("down", "e", "downs"), W("dale", "e", "dale"), W("dale", "w", "dale"),
	W("vale", "w", "vale"), W("combe", "e", "combe"), W("combe", "e", "coombe"), W("bay", "w", "bay"),
	W("sea", "w", "sea"), W("marsh", "e", "marsh"), W("marsh", "w", "marsh"), W("moor", "e", "moor"),
	W("moor", "w", "moor"), W("heath", "e", "heath"), W("heath", "w", "heath"), W("fell", "e", "fell"),
	W("brook", "e", "brook"), W("brook", "e", "beck"), W("brook", "e", "burn"), W("mouth", "e", "mouth"),
	W("ford", "e", "ford"), W("bridge", "e", "bridge"), W("bridge", "w", "bridge"), W("ness", "e", "ness"),
	W("cliff", "e", "cliff"), W("cliff", "s", "cliff"), W("edge", "w", "edge"), W("edge", "e", "edge"),
	W("haven", "e", "haven"), W("vale", "e", "vale"), W("falls", "e", "force"), W("falls", "w", "falls"),
})
M.WORDS.de = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "s", "nord"), W("south", "s", "süd"), W("east", "s", "ost"), W("west", "s", "west"), W("upper", "s", "ober"), W("lower", "s", "unter"), W("lower", "s", "nieder"),
	W("see", "e", "see"), W("see", "w", "see"), W("see", "e", "seen"), W("wald", "e", "wald"), W("wald", "e", "walde"),
	W("wald", "w", "wald"), W("holz", "e", "holz"), W("forst", "e", "forst"), W("berg", "e", "berg"),
	W("berg", "e", "bergen"), W("berg", "w", "berg"), W("tal", "e", "tal"), W("tal", "e", "thal"), W("tal", "w", "tal"),
	W("bach", "e", "bach"), W("brueck", "e", "brück"), W("brueck", "e", "bruck"), W("brueck", "e", "brücken"),
	W("furt", "e", "furt"), W("hafen", "e", "hafen"), W("heide", "e", "heide"), W("heide", "w", "heide"),
	W("moor", "e", "moor"), W("hain", "e", "hain"), W("hoehe", "e", "höhe"), W("brunn", "e", "brunn"),
	W("brunn", "e", "born"), W("insel", "w", "insel"), W("muende", "e", "münde"), W("au", "e", "aue"),
	W("grund", "e", "grund"), W("stein", "e", "stein"), W("bruch", "e", "bruch"),
})
M.WORDS.fr = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "w", "nord"), W("south", "w", "sud"), W("upper", "w", "haut"), W("upper", "w", "haute"), W("lower", "w", "bas"), W("lower", "w", "basse"),
	W("lac", "w", "lac"), W("foret", "w", "forêt"), W("bois", "w", "bois"), W("mont", "w", "mont"), W("mont", "s", "mont"),
	W("val", "w", "val"), W("val", "w", "vallée"), W("mer", "w", "mer"), W("plage", "w", "plage"), W("pont", "w", "pont"),
	W("roche", "w", "roche"), W("roche", "s", "roche"), W("ile", "w", "île"), W("marais", "w", "marais"),
	W("cote", "w", "côte"), W("etang", "w", "étang"), W("port", "w", "port"), W("bains", "w", "bains"),
	W("combe", "w", "combe"), W("plaine", "w", "plaine"), W("montagne", "w", "montagne"),
})
M.WORDS.it = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("upper", "w", "superiore"), W("lower", "w", "inferiore"), W("upper", "w", "alta"), W("lower", "w", "bassa"),
	W("lago", "w", "lago"), W("bosco", "w", "bosco"), W("bosco", "w", "selva"), W("monte", "w", "monte"),
	W("monte", "s", "monte"), W("valle", "w", "valle"), W("valle", "w", "val"), W("mare", "w", "mare"),
	W("ponte", "w", "ponte"), W("colle", "w", "colle"), W("colle", "s", "colle"), W("isola", "w", "isola"),
	W("porto", "w", "porto"), W("marina", "w", "marina"), W("terme", "w", "terme"), W("fiume", "w", "fiume"),
	W("piano", "w", "piano"), W("sasso", "w", "sasso"), W("rocca", "w", "rocca"),
})
M.WORDS.es = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "w", "norte"), W("south", "w", "sur"), W("upper", "w", "arriba"), W("lower", "w", "abajo"),
	W("lago", "w", "lago"), W("lago", "w", "laguna"), W("bosque", "w", "bosque"), W("monte", "w", "monte"),
	W("sierra", "w", "sierra"), W("valle", "w", "valle"), W("mar", "w", "mar"), W("puente", "w", "puente"),
	W("rio", "w", "río"), W("rio", "w", "rio"), W("playa", "w", "playa"), W("isla", "w", "isla"), W("pena", "w", "peña"),
	W("vega", "w", "vega"), W("pinar", "w", "pinar"), W("puerto", "w", "puerto"), W("cabo", "w", "cabo"),
})
M.WORDS.pt = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "w", "norte"), W("south", "w", "sul"), W("upper", "w", "cima"), W("lower", "w", "baixo"),
	W("lagoa", "w", "lagoa"), W("mata", "w", "mata"), W("mata", "w", "bosque"), W("monte", "w", "monte"),
	W("serra", "w", "serra"), W("vale", "w", "vale"), W("mar", "w", "mar"), W("ponte", "w", "ponte"), W("rio", "w", "rio"),
	W("praia", "w", "praia"), W("ilha", "w", "ilha"), W("porto", "w", "porto"), W("pinhal", "w", "pinhal"),
	W("ribeira", "w", "ribeira"), W("penha", "w", "penha"),
})
M.WORDS.nl = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "s", "noord"), W("south", "s", "zuid"), W("east", "s", "oost"), W("west", "s", "west"), W("north", "w", "noord"), W("south", "w", "zuid"), W("east", "w", "oost"), W("west", "w", "west"), W("upper", "s", "boven"), W("lower", "s", "neder"), W("lower", "w", "neder"), W("upper", "w", "boven"),
	W("meer", "e", "meer"), W("meer", "w", "meer"), W("bos", "w", "bos"), W("bos", "e", "bos"), W("bos", "e", "bosch"),
	W("hout", "e", "hout"), W("berg", "e", "berg"), W("dal", "e", "dal"), W("zee", "e", "zee"), W("zee", "w", "zee"),
	W("haven", "e", "haven"), W("veen", "e", "veen"), W("broek", "e", "broek"), W("dijk", "e", "dijk"),
	W("brug", "e", "brug"), W("duin", "e", "duin"), W("duin", "e", "duinen"), W("heide", "e", "heide"),
	W("woud", "e", "woude"), W("woud", "e", "wolde"), W("beek", "e", "beek"), W("horst", "e", "horst"),
})
M.WORDS.sv = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "w", "norra"), W("south", "w", "södra"), W("east", "w", "östra"), W("west", "w", "västra"), W("north", "s", "norr"), W("south", "s", "sör"), W("east", "s", "öster"), W("west", "s", "väster"), W("upper", "w", "övre"), W("lower", "w", "nedre"),
	W("sjo", "e", "sjö"), W("sjo", "e", "sjön"), W("skog", "e", "skog"), W("skog", "e", "skogen"), W("berg", "e", "berg"),
	W("berg", "e", "berget"), W("dal", "e", "dal"), W("dal", "e", "dalen"), W("vik", "e", "vik"), W("vik", "e", "viken"),
	W("as", "e", "ås"), W("as", "e", "åsen"), W("holm", "e", "holm"), W("holm", "e", "holmen"), W("fors", "e", "fors"),
	W("fors", "e", "forsen"), W("alv", "e", "älv"), W("alv", "e", "älven"), W("strand", "e", "strand"),
	W("nas", "e", "näs"), W("lund", "e", "lund"), W("hamn", "e", "hamn"), W("bro", "e", "bro"), W("backa", "e", "backa"),
	W("myr", "e", "myr"), W("hult", "e", "hult"),
})
M.WORDS.nb = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "w", "nordre"), W("south", "w", "søndre"), W("east", "w", "østre"), W("west", "w", "vestre"), W("north", "s", "nord"), W("south", "s", "sør"), W("upper", "w", "øvre"), W("lower", "w", "nedre"),
	W("vatn", "e", "vatn"), W("vatn", "e", "vatnet"), W("vatn", "e", "sjøen"), W("vatn", "e", "vann"),
	W("skog", "e", "skog"), W("skog", "e", "skogen"), W("berg", "e", "berg"), W("berg", "e", "berget"), W("dal", "e", "dal"),
	W("dal", "e", "dalen"), W("vik", "e", "vik"), W("vik", "e", "vika"), W("as", "e", "ås"), W("as", "e", "åsen"),
	W("holm", "e", "holm"), W("holm", "e", "holmen"), W("foss", "e", "foss"), W("elv", "e", "elv"), W("elv", "e", "elva"),
	W("strand", "e", "strand"), W("nes", "e", "nes"), W("havn", "e", "havn"), W("oy", "e", "øy"), W("oy", "e", "øya"),
	W("fjord", "e", "fjord"), W("bro", "e", "bro"), W("myr", "e", "myr"), W("li", "e", "lia"),
})
M.WORDS.ja = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "h", "北"), W("south", "h", "南"), W("east", "h", "東"), W("west", "h", "西"), W("upper", "h", "上"), W("lower", "h", "下"),
	W("lake", "h", "湖"), W("forest", "h", "森"), W("woods", "h", "林"), W("hill", "h", "山"), W("river", "h", "川"),
	W("valley", "h", "谷"), W("beach", "h", "浜"), W("island", "h", "島"), W("cape", "h", "崎"), W("brook", "h", "沢"),
	W("pond", "h", "池"), W("hill2", "h", "岡"), W("bay", "h", "浦"), W("marsh", "h", "沼"), W("field", "h", "野"),
})
M.WORDS.ja_r = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "s", "kita"), W("south", "s", "minami"), W("east", "s", "higashi"), W("west", "s", "nishi"), W("upper", "s", "kami"), W("lower", "s", "shimo"),
	W("lake", "e", "ko"), W("forest", "e", "mori"), W("woods", "e", "bayashi"), W("woods", "e", "hayashi"),
	W("hill", "e", "yama"), W("river", "e", "kawa"), W("river", "e", "gawa"), W("valley", "e", "tani"),
	W("valley", "e", "dani"), W("beach", "e", "hama"), W("island", "e", "shima"), W("island", "e", "jima"),
	W("cape", "e", "saki"), W("cape", "e", "zaki"), W("brook", "e", "sawa"), W("brook", "e", "zawa"),
	W("pond", "e", "ike"), W("hill2", "e", "oka"), W("bay", "e", "ura"), W("marsh", "e", "numa"),
})
M.WORDS.ru = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "h", "Северо"), W("south", "h", "Южно"), W("upper", "h", "Верхн"), W("lower", "h", "Нижн"),
	W("lake", "h", "Озёр"), W("lake", "h", "Озер"), W("lake", "h", "озёр"), W("lake", "h", "озер"),
	W("forest", "h", "Лесн"), W("forest", "h", "лесн"), W("pine", "h", "Бор"), W("hill", "h", "горск"),
	W("hill", "h", "Горн"), W("river", "h", "речн"), W("river", "h", "Речн"), W("sea", "h", "морск"),
	W("sea", "h", "Морск"), W("island", "h", "Остров"), W("valley", "h", "Долин"),
})
M.WORDS.ru_r = set({
	-- (the compass and the river's course count too: "North ..." on every other town is as silly as Lake)
	W("north", "s", "severo"), W("south", "s", "yuzhno"), W("upper", "s", "verkhn"), W("lower", "s", "nizhn"),
	W("lake", "s", "ozer"), W("lake", "s", "ozyor"), W("forest", "s", "lesn"), W("hill", "e", "gorsk"),
	W("river", "s", "rechn"), W("sea", "s", "morsk"), W("island", "s", "ostrov"), W("valley", "s", "dolin"),
})
M.WORDS.nordic = M.WORDS.sv
-- (SOFT: whole regions are named with these; twice the count, half the distance)
M.SOFT = { ford = true, bridge = true, brueck = true, furt = true, bach = true, hill = true, river = true, brook = true,
	berg = true, dal = true, pont = true, ponte = true, puente = true, bro = true, brug = true, dijk = true, hill2 = true,
	field = true, beek = true, stein = true }

-- classifier -> lexicon (sv and nb share Nordic rules in ot_names, each keeps its own words here)
M.WORDS_OF = { en = "en", usa = "usa", de = "de", fr = "fr", it = "it", es = "es", pt = "pt", nl = "nl", sv = "sv",
	nb = "nb", ja = "ja", ja_r = "ja_r", ru = "ru", ru_r = "ru_r" }

local function hits(how, text, raw, ws)
	if how == "h" then return raw:find(text, 1, true) ~= nil end
	local n = #text
	for _, w in ipairs(ws) do
		if how == "w" then
			if w == text then return true end
		elseif how == "e" then
			if #w >= n + 2 and w:sub(-n) == text then return true end
		elseif how == "s" then
			if #w >= n + 2 and w:sub(1, n) == text then return true end
		end
	end
	return false
end

-- words never counted on their own (M.wordKeys): articles, prepositions, saints, size / age modifiers
M.STOP = {}
for w in ("the of on upon in by and at under over de la le les du des del della di da do dos das am an der den die dem "
	.. "aan het op bij saint sankt sint san santa sao st city town new old great little grand nieuw oud neu alt groß gross "
	.. "klein petit grande gran"):gmatch("%S+") do M.STOP[w] = true end
M.STOP["são"] = true
M.WORD_MIN = 4            -- bytes: shorter words aren't counted on their own

--- The other words of a multi-word name as keys "=<word>" (lower case, WORD_MIN+ bytes, not M.STOP, not a lexicon word):
--- with a budget's `words` on (Landscape names: the list's "North Plainfield" / "South Plainfield", "North Salt Lake"),
--- each at most once on the map and never within NEAR_M.
function M.wordKeys(name, cls, lexKeys)
	local out = {}
	if type(name) ~= "string" then return out end
	local low = M.lower(name)
	local ws = words(low)
	if #ws < 2 then return out end
	local lex = M.WORDS[M.WORDS_OF[cls or ""] or ""] or {}
	local seen = {}
	for _, w in ipairs(ws) do
		if #w >= M.WORD_MIN and not M.STOP[w] and not seen[w] then
			local inLex = false
			for _, e in ipairs(lex) do
				if e[2] ~= "h" and hits(e[2], e[3], low, { w }) then inLex = true break end
			end
			if not inLex then
				-- (singular and plural are one word: "Fork" / "Forks", 2026-10-14 NEXT_PHASE_BRIEF 50)
				local f = M.fold(w)
				if not seen[f] then
					seen[f] = true
					out[#out + 1] = "=" .. f
				end
			end
		end
	end
	table.sort(out)
	return out
end

--- The generic word keys of a name for classifier cls: a sorted list of distinct keys ({} for none / no lexicon).
function M.keys(name, cls)
	local lex = M.WORDS[M.WORDS_OF[cls or ""] or ""]
	if lex == nil or type(name) ~= "string" or name == "" then return {} end
	local low = M.lower(name)
	local ws = words(low)
	local seen, out = {}, {}
	for _, e in ipairs(lex) do
		if not seen[e[1]] and hits(e[2], e[3], (e[2] == "h") and name or low, ws) then
			seen[e[1]] = true
			out[#out + 1] = e[1]
		end
	end
	table.sort(out)
	return out
end

---------------------------------------------------------------------------
-- the budget

--- A map's word budget: cls (the lexicon), nTowns (the cap: max(1, ceil(nTowns / PER_TOWNS))), o = { perTowns, near }.
--- (2026-10-14, NEXT_PHASE_BRIEF 50 item 2) Two optional fields extend it: B.extra = function(name) -> keys (ot_placename:
--- the name's roots "^<stem>" and affix patterns "%<family>" / "%!<template>", M.attachExtra), and B.tpos = { {x, y} }
--- (the map's town positions, M.setTowns): then a key is never twice among a town's HOOD nearest towns either ("once
--- per ~8 towns" read locally: two "-under-" names are never neighbours on any map size).
M.HOOD = 7                -- a key's earlier use among the HOOD nearest towns of the new one: refused (SOFT keys: none)
M.ROOT_PER = 12           -- a stem's root ("^myt") at most once per this many towns (2026-10-14, NEXT_PHASE_BRIEF 53 item 4)
M.HOOD_CACHE = 2048
function M.newBudget(cls, nTowns, o)
	o = o or {}
	local n = math.max(1, tonumber(nTowns) or 1)
	local per = o.perTowns or M.PER_TOWNS
	return { cls = cls, cap = math.max(1, math.ceil(n / per)), rootCap = math.max(1, math.ceil(n / M.ROOT_PER)),
		near = o.near or M.NEAR_M, used = {}, pts = {}, held = {},
		entries = 0, heldN = 0, words = o.words == true, extra = nil, tpos = nil, hood = {}, hoodN = 0 }
end

--- The map's town positions for the neighbourhood rule: list = { {x, y} } (at most MAX_ENTRIES).
function M.setTowns(B, list)
	if B == nil then return end
	local t = {}
	for i, p in ipairs(list or {}) do
		if i > M.MAX_ENTRIES then break end
		if tonumber(p[1]) and tonumber(p[2]) then t[#t + 1] = { tonumber(p[1]), tonumber(p[2]) } end
	end
	B.tpos, B.hood, B.hoodN = (#t > M.HOOD) and t or nil, {}, 0
end

--- The squared distance from (x, y) to its HOOD-th nearest other town (0 without positions; cached per position).
function M.hoodR2(B, x, y)
	if B == nil or B.tpos == nil or not (tonumber(x) and tonumber(y)) then return 0 end
	local key = string.format("%.0f:%.0f", x, y)
	local c = B.hood[key]
	if c then return c end
	local d = {}
	for _, p in ipairs(B.tpos) do
		local q = (p[1] - x) ^ 2 + (p[2] - y) ^ 2
		if q > 1 then d[#d + 1] = q end
	end
	table.sort(d)
	c = d[math.min(M.HOOD, #d)] or 0
	if B.hoodN >= M.HOOD_CACHE then B.hood, B.hoodN = {}, 0 end
	B.hood[key], B.hoodN = c, B.hoodN + 1
	return c
end

local function skipSet(skip)
	local s = {}
	for _, k in ipairs(skip or {}) do s[k] = true end
	return s
end

--- Can name go at (x, y)? skip = keys not to count (a parent's words). Returns true, or false and the key that failed and
--- why ("cap" | "near"). A nil budget allows everything.
--- The keys a budget counts for a name: M.keys, plus M.wordKeys with B.words.
function M.budgetKeys(B, name)
	local k = M.keys(name, B.cls)
	if B.words then
		for _, w in ipairs(M.wordKeys(name, B.cls)) do k[#k + 1] = w end
	end
	if B.extra then
		local okX, ex = pcall(B.extra, name)
		if okX and type(ex) == "table" then
			for i, w in ipairs(ex) do
				if i > M.MAX_WORDS then break end
				k[#k + 1] = w
			end
		end
	end
	return k
end

local function capOf(B, k)
	local c = k:sub(1, 1)
	if c == "=" then return 1 end
	-- (a rare affix template: once per map)
	if k:sub(1, 2) == "%!" then return 1 end
	if c == "^" then return B.rootCap or B.cap end
	return B.cap * (M.SOFT[k] and M.SOFT_K or 1)
end

-- the distance a key's earlier use must keep from (x, y), squared: NEAR_M (SOFT: half), or the HOOD-th nearest town's
local function near2(B, k, x, y)
	local soft = M.SOFT[k] and M.SOFT_K or 1
	local n = B.near / soft
	local d2 = n * n
	if soft == 1 then
		local h = M.hoodR2(B, x, y)
		if h > d2 then d2 = h end
	end
	return d2
end

function M.check(B, name, x, y, skip, keys)
	if B == nil then return true end
	local sk = skipSet(skip)
	for _, k in ipairs(keys or M.budgetKeys(B, name)) do
		if not sk[k] then
			if (B.used[k] or 0) >= capOf(B, k) then return false, k, "cap" end
			if tonumber(x) and tonumber(y) and B.pts[k] then
				local d2 = near2(B, k, x, y)
				for _, p in ipairs(B.pts[k]) do
					if p[1] and (p[1] - x) ^ 2 + (p[2] - y) ^ 2 <= d2 then return false, k, "near" end
				end
			end
		end
	end
	return true
end

--- Counts a rejected candidate (the log's held=).
function M.hold(B, key)
	if B == nil or key == nil then return end
	B.held[key] = (B.held[key] or 0) + 1
	B.heldN = B.heldN + 1
end

--- The keys a name at (x, y) may not carry now: { [key] = true } (at their cap, or used within the distance; skip:
--- keys not counted). For ranking the parts before the names are built (ot_placename).
function M.blockedKeys(B, x, y, skip)
	local out = {}
	if B == nil then return out end
	local sk = skipSet(skip)
	for k, n in pairs(B.used) do
		if not sk[k] and n > 0 then
			if n >= capOf(B, k) then out[k] = true
			elseif tonumber(x) and tonumber(y) then
				local d2 = near2(B, k, x, y)
				for _, p in ipairs(B.pts[k] or {}) do
					if p[1] and (p[1] - x) ^ 2 + (p[2] - y) ^ 2 <= d2 then out[k] = true break end
				end
			end
		end
	end
	return out
end

--- check + hold: true when the name may go (keys: the name's M.keys when known).
function M.allow(B, name, x, y, skip, keys)
	local okB, k = M.check(B, name, x, y, skip, keys)
	if not okB then M.hold(B, k) end
	return okB
end

--- Takes name's words at (x, y) (skip: keys not counted; keys: the name's M.keys when known).
function M.add(B, name, x, y, skip, keys)
	if B == nil or B.entries >= M.MAX_ENTRIES then return end
	B.entries = B.entries + 1
	local sk = skipSet(skip)
	for _, k in ipairs(keys or M.budgetKeys(B, name)) do
		if not sk[k] then
			B.used[k] = (B.used[k] or 0) + 1
			B.pts[k] = B.pts[k] or {}
			B.pts[k][#B.pts[k] + 1] = { tonumber(x), tonumber(y) }
		end
	end
end

--- Gives a name's words back (a satellite replacing the name it had taken).
function M.remove(B, name, x, y)
	if B == nil then return end
	for _, k in ipairs(M.budgetKeys(B, name)) do
		if (B.used[k] or 0) > 0 then B.used[k] = B.used[k] - 1 end
		local pts = B.pts[k] or {}
		for i = #pts, 1, -1 do
			if pts[i][1] == tonumber(x) and pts[i][2] == tonumber(y) then table.remove(pts, i) break end
		end
	end
end

local function countText(t, words)
	local ks = {}
	-- (the "=<word>" keys only in held=: used= lists the generic words)
	for k, v in pairs(t or {}) do if v > 0 and (words or k:sub(1, 1) ~= "=") then ks[#ks + 1] = k end end
	table.sort(ks)
	local parts = {}
	for _, k in ipairs(ks) do parts[#parts + 1] = k .. ":" .. t[k] end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- "lake:2,forest:1" (keys in use), "-" for none.
function M.usedText(B) return B and countText(B.used, false) or "-" end
--- "lake:5,=plainfield:1" (candidates the budget turned down), "-" for none.
function M.heldText(B) return B and countText(B.held, true) or "-" end

--- A budget over the names already on a map: list = { { name, x, y } } (towns, districts, Works). For the later
--- namings (districts, Works).
function M.fromNames(cls, list, o)
	o = o or {}
	local B = M.newBudget(cls, #(list or {}), o)
	B.extra = o.extra
	local pos = {}
	for _, e in ipairs(list or {}) do pos[#pos + 1] = { e[2], e[3] } end
	if o.hood ~= false then M.setTowns(B, pos) end
	for _, e in ipairs(list or {}) do M.add(B, e[1], e[2], e[3]) end
	return B
end

---------------------------------------------------------------------------
-- rarity

-- exempt: town meta tags and the compass (a quarter of the map is north by definition)
M.RARE_EXEMPT = { market = true, church = true, big = true, small = true, character = true, district = true,
	works = true, old = true, new = true, any = true, north = true, south = true, east = true, west = true,
	central = true, dir = true, plain = true }

--- Rarity factors over the towns' weight maps ({ { [tag] = w } }): { [tag] = factor } for tags on more than
--- RARE_SHARE of the towns (from RARE_MIN_W): 1 at RARE_SHARE, RARE_MIN on every town. Fewer than RARE_MIN_TOWNS
--- towns: {}.
function M.rarity(maps, exempt)
	exempt = exempt or M.RARE_EXEMPT
	local n = #(maps or {})
	local out = {}
	if n < M.RARE_MIN_TOWNS then return out end
	local count = {}
	for _, w in ipairs(maps) do
		for t, v in pairs(w or {}) do
			if tonumber(v) and v >= M.RARE_MIN_W and not exempt[t] then count[t] = (count[t] or 0) + 1 end
		end
	end
	for t, c in pairs(count) do
		local share = c / n
		if share > M.RARE_SHARE then
			local f = 1 - (share - M.RARE_SHARE) / (1 - M.RARE_SHARE) * (1 - M.RARE_MIN)
			out[t] = math.max(M.RARE_MIN, math.min(1, f))
		end
	end
	return out
end

--- A copy of weights w with the rarity factors applied.
function M.applyRarity(w, f)
	local out = {}
	for t, v in pairs(w or {}) do out[t] = (f and f[t]) and v * f[t] or v end
	return out
end

--- "lake:0.48,forest:0.30" (factors, sorted by tag), "-" for none.
function M.rarityText(f)
	local ks = {}
	for k in pairs(f or {}) do ks[#ks + 1] = k end
	table.sort(ks)
	local parts = {}
	for _, k in ipairs(ks) do parts[#parts + 1] = string.format("%s:%.2f", k, f[k]) end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

---------------------------------------------------------------------------
-- landscape cue words: C(cue, how, text, weight); how as M.WORDS plus "f" (the first word), "l" (the last word of a
-- name of two words or more)

local function C(cue, how, text, w) return { cue, how, text, w or 1 } end

M.CUE_TAGS = { "north", "south", "east", "west", "central", "upper", "lower", "fork", "falls", "bend", "gap", "summit",
	"divide", "peak", "mouth", "narrows", "twin", "bay", "valley" }

M.CUES = {}
M.CUES.usa = {
	C("north", "f", "north"), C("south", "f", "south"), C("east", "f", "east"), C("west", "f", "west"),
	C("north", "s", "north", 0.7), C("south", "s", "south", 0.7), C("east", "s", "east", 0.7), C("west", "s", "west", 0.7),
	C("central", "f", "central"), C("central", "f", "center", 0.8), C("central", "f", "middle", 0.8),
	C("upper", "f", "upper"), C("lower", "f", "lower"), C("fork", "l", "fork"), C("fork", "l", "forks"),
	C("fork", "w", "fork", 0.8), C("fork", "w", "forks", 0.8), C("fork", "l", "junction", 0.5), C("twin", "f", "twin", 0.8),
	C("fork", "w", "rivers", 0.7), C("falls", "l", "falls"), C("falls", "l", "rapids", 0.9), C("bend", "l", "bend"), C("bend", "f", "bend", 0.8),
	C("gap", "l", "gap"), C("gap", "l", "pass", 0.8), C("summit", "w", "summit"), C("divide", "w", "divide"),
	C("peak", "f", "mount"), C("peak", "w", "mountain", 0.8), C("peak", "l", "peak"), C("mouth", "e", "mouth"),
	C("mouth", "l", "inlet", 0.7), C("narrows", "w", "narrows"), C("bay", "l", "bay", 0.6), C("valley", "l", "valley", 0.6),
}
M.CUES.en = {
	C("north", "s", "north"), C("south", "s", "south"), C("east", "s", "east"), C("west", "s", "west"),
	C("north", "f", "north"), C("south", "f", "south"), C("east", "f", "east"), C("west", "f", "west"),
	C("upper", "f", "upper"), C("upper", "f", "over", 0.8), C("upper", "f", "high", 0.6), C("lower", "f", "lower"),
	C("lower", "f", "nether"), C("mouth", "e", "mouth"), C("mouth", "s", "aber", 0.8), C("mouth", "s", "inver", 0.8),
	C("falls", "e", "force", 0.7), C("twin", "s", "twy", 0.7), C("narrows", "w", "narrows"),
	C("fork", "w", "meeting", 0.6), C("summit", "w", "top", 0.6), C("peak", "s", "pen", 0.5),
}
M.CUES.de = {
	C("north", "s", "nord"), C("south", "s", "süd"), C("east", "s", "ost"), C("west", "s", "west"),
	C("north", "s", "norder"), C("south", "s", "süder"), C("east", "s", "oster"), C("west", "s", "wester"),
	C("upper", "s", "ober"), C("upper", "f", "ober"), C("upper", "s", "hoch", 0.6), C("lower", "s", "unter"),
	C("lower", "s", "nieder"), C("lower", "f", "unter"), C("lower", "f", "nieder"), C("mouth", "e", "münde"),
	C("mouth", "e", "mündung"), C("fork", "s", "zwiesel", 0.8), C("summit", "e", "höhe", 0.6), C("gap", "e", "pass", 0.7),
}
M.CUES.fr = {
	C("north", "w", "nord"), C("south", "w", "sud"), C("east", "w", "est", 0.8), C("west", "w", "ouest"),
	C("upper", "w", "haut"), C("upper", "w", "haute"), C("upper", "s", "haut"), C("lower", "w", "bas"),
	C("lower", "w", "basse"), C("mouth", "w", "embouchure"), C("fork", "w", "confluent"), C("fork", "s", "condat", 0.7),
	C("summit", "w", "sommet"), C("gap", "w", "col"),
}
M.CUES.it = {
	C("upper", "w", "superiore"), C("upper", "w", "alto", 0.6), C("lower", "w", "inferiore"), C("lower", "w", "basso", 0.6),
	C("mouth", "w", "foce"), C("fork", "w", "confluenza"), C("north", "w", "nord"), C("south", "w", "sud"),
}
M.CUES.es = {
	C("upper", "w", "arriba"), C("upper", "w", "alto", 0.6), C("lower", "w", "abajo"), C("lower", "w", "bajo", 0.6),
	C("mouth", "w", "desembocadura"), C("north", "w", "norte"), C("south", "w", "sur"),
}
M.CUES.pt = {
	C("upper", "w", "cima"), C("lower", "w", "baixo"), C("mouth", "w", "foz"), C("north", "w", "norte"), C("south", "w", "sul"),
}
M.CUES.nl = {
	C("north", "s", "noord"), C("south", "s", "zuid"), C("east", "s", "oost"), C("west", "s", "west"),
	C("upper", "s", "boven"), C("upper", "s", "hoog", 0.6), C("lower", "s", "neder"), C("lower", "s", "beneden"),
	C("mouth", "e", "mond"), C("mouth", "e", "monde"), C("mouth", "e", "muiden"),
}
M.CUES.sv = {
	C("north", "s", "norr"), C("north", "s", "nord"), C("south", "s", "sör"), C("south", "s", "syd"),
	C("east", "s", "öster"), C("west", "s", "väster"), C("upper", "s", "över"), C("upper", "f", "övre"),
	C("lower", "s", "neder"), C("lower", "f", "nedre"), C("mouth", "e", "os"), C("mouth", "e", "oset"),
	C("falls", "e", "fors"), C("falls", "e", "forsen"),
}
M.CUES.nb = {
	C("north", "s", "nord"), C("south", "s", "sør"), C("east", "s", "øster"), C("east", "s", "aust"), C("west", "s", "vester"),
	C("upper", "s", "øvre"), C("upper", "f", "øvre"), C("lower", "f", "nedre"), C("lower", "s", "nedre"),
	C("mouth", "e", "os"), C("mouth", "e", "oset"), C("falls", "e", "foss"), C("falls", "e", "fossen"),
}
M.CUES.ja = {
	C("north", "h", "北"), C("south", "h", "南"), C("east", "h", "東"), C("west", "h", "西"), C("upper", "h", "上"),
	C("lower", "h", "下"), C("mouth", "h", "口", 0.7), C("fork", "h", "落合"), C("fork", "h", "川合", 0.8),
	C("summit", "h", "峠", 0.7), C("gap", "h", "峠"),
}
M.CUES.ja_r = {
	C("north", "s", "kita"), C("south", "s", "minami"), C("east", "s", "higashi"), C("west", "s", "nishi"),
	C("upper", "s", "kami"), C("lower", "s", "shimo"), C("mouth", "e", "guchi", 0.7), C("mouth", "e", "kuchi", 0.7),
	C("fork", "s", "ochiai"), C("fork", "s", "kawai", 0.8),
}
M.CUES.ru = {
	C("north", "h", "Северо"), C("south", "h", "Южно"), C("upper", "h", "Верхн"), C("lower", "h", "Нижн"),
	C("mouth", "h", "Усть"),
}
M.CUES.ru_r = {
	C("north", "s", "severo"), C("south", "s", "yuzhno"), C("upper", "s", "verkhn"), C("lower", "s", "nizhn"),
	C("mouth", "f", "ust"),
}

--- The cues of a real list name for classifier cls: { [cue] = w } or nil.
function M.cuesOf(name, cls)
	local lex = M.CUES[cls or ""]
	if lex == nil or type(name) ~= "string" or name == "" then return nil end
	local low = M.lower(name)
	local ws = words(low)
	local out = nil
	for _, e in ipairs(lex) do
		local how, hit = e[2], false
		if how == "f" then hit = ws[1] == e[3]
		elseif how == "l" then hit = #ws >= 2 and ws[#ws] == e[3]
		else hit = hits(how, e[3], how == "h" and name or low, ws) end
		if hit then
			out = out or {}
			if (out[e[1]] or 0) < e[4] then out[e[1]] = e[4] end
		end
	end
	return out
end

--- "north:1.00,fork:0.80" (cues in CUE_TAGS order), "-" for none.
function M.cueText(c)
	if c == nil then return "-" end
	local parts = {}
	for _, t in ipairs(M.CUE_TAGS) do if c[t] then parts[#parts + 1] = string.format("%s:%.2f", t, c[t]) end end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

return M
