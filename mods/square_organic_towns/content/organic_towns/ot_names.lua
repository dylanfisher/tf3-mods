-- Organic Towns: landscape names (pure; 2026-10-13, the user-approved "middle option").
--
-- On a NEW map each town gets a REAL name from the game's own active name list, chosen to fit its site, instead of the
-- game's random draw. The game's name script (base/content/names/names.script.lua townsNameScriptFn) draws `num` names
-- at random from a flat list `::/names/<path>/<lang>/towns.lua` (the `.names.lua` file's `languages` table picks the
-- folder by the game language, else `fallback`); the engine only gets strings, no terrain. So the mod re-reads that same
-- list, classifies each name by its endings / prefixes in the list's language into site tags (M.RULES), reads each
-- town's site from what the driver already surveys (ot_terrain stats, ot_site features, the forest grid, character
-- towns, size: M.townTags) and gives every town the best-fitting unused name (M.assign): rarest tags first, unique on the
-- map, deterministic per map, plain names for plain towns (a town keeps its game name when nothing fits better or it
-- already fits), a random draw from the same list as the last resort. The one place names are composed: a small town
-- right next to a much bigger one may get the bigger town's name with a list-language prefix / suffix ("Little X",
-- "Klein X", M.SAT) when that name is unique and the town found no landscape fit. Industries named "<Town> <type>" by
-- the generator follow their town's new name (M.industryRenames).
--
-- Only the base game's 18 lists (M.LISTS, verified from base/content/names/*/*.names.lua 2026-10-13); any other name
-- set (e.g. the square_names_us_* state mods) or unknown path: nothing (M.basePath). Lists whose names carry no
-- readable endings (Chinese, Korean, Asian, Oceanian, Polish) have no classifier (why=noTags), and a list whose tagged
-- share stays under USABLE_SHARE is left alone too.
--
-- Names from the map's shape (2026-10-14, NEXT_PHASE_BRIEF 45; ot_namewords, ot_mapshape): the town tags are weighed
-- by their rarity on the map (a tag most towns read is no cue), every pick keeps to the map's word budget (a generic
-- word such as Lake / Forest / -see at most once per 8 towns, never twice within 5 km), names whose words say a map
-- cue ("North ...", "Upper ...", "... Forks", "... Falls", "Mount ...") score where the survey found it and cost where
-- it didn't (M.cueScore), and list disambiguators go (ot_namewords.clean: "Milford city " -> "Milford").
--
-- Save-safe: no `.names.lua` shipped, names are plain strings on the entities; removing the mod changes nothing.
-- Every loop is capped (MAX_* constants). Plain Lua, pre-5.3 (no integer division, no bit ops, no goto).

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local NW = ug_require "square_organic_towns::/organic_towns/ot_namewords.lua"

local M = {}

M.ON = true
M.TAGS = { "estuary", "ford", "bridge", "river", "coast", "lake", "valley", "hill", "cliff", "headland", "island",
	"forest", "marsh", "market", "plain" }
M.TAG_INDEX = {}
for i, t in ipairs(M.TAGS) do M.TAG_INDEX[t] = i end

M.MAX_POOL = 20000        -- names read from one list at most
M.MAX_TOWNS = 2000        -- towns assigned at most
M.MAX_CAND = 300          -- candidates looked at per town and tag (bucket walk)
M.MAX_WALK = 1200         -- names looked at for a plain / random pick
M.MAX_INDUSTRIES = 4000   -- industries checked for a town-name prefix
M.MAX_WORDS = 12          -- words of a name looked at
M.MIN_STEM = 2            -- "end" / "start" rules: at least this many letters beside the matched part
M.USABLE_SHARE = 0.05     -- a list needs this share of tagged (non-plain) names ...
M.USABLE_MIN = 20         -- ... and at least this many, else why=noTags
M.MIN_TAG = 0.3           -- a town tag this strong is looked for
M.MIN_MATCH = 0.3         -- a candidate must score this much to replace the game's name
M.KEEP_EPS = 0.1          -- the game's own name stays when it scores within this of the best candidate
M.KEEP_TOL = 0.25         -- ... and a game name that contradicts the site less than this still stays (weak tags: -burg)
M.RARE_COUNT = 30        -- a tag with at most this many names in the pool is rare: a match on it scores RARE_BONUS more
M.RARE_BONUS = 0.5
M.TOWN_TAG_MIN = 0.2      -- town tags under this are dropped (and count as "absent" for contradictions)
M.MAX_TOWN_TAGS = 5
-- a name tag the town lacks costs its strength x this (water names on a dry site cost most; plain never)
M.CONTRA = { estuary = 1, ford = 0.8, bridge = 0.8, river = 0.8, coast = 1, lake = 1, island = 1, headland = 1,
	cliff = 0.8, hill = 0.6, valley = 0.5, marsh = 0.5, forest = 0.3, market = 0.1, plain = 0 }
-- satellites / twins: a town this close to one SAT_RATIO x its size (target capacity) or bigger, seeded SAT_P
M.SAT_NEAR = 1800
M.SAT_RATIO = 2.5
M.SAT_P = 0.6
M.SAT_MAX_PARENT_LEN = 16 -- parent names longer than this (bytes) or with a space / hyphen are not composed
M.MAX_NAME_LEN = 40       -- bytes
M.BIG_CAP = 2500          -- a town this big (target capacity) also counts as a market / plain town
M.BIG_SHARE = 0.1         -- ... and the map's biggest tenth (at least the biggest town) with 1.5 x the median

---------------------------------------------------------------------------
-- The base lists: path -> { langs = the .names.lua townNamesScript `languages` table, cls = folder -> classifier id }

M.LISTS = {
	europe = { langs = { de = "de", en = "en", es = "es", fr = "fr", it = "it", ko = "ko", nb = "nb", nl = "nl", ru = "ru",
		sv = "sv", fallback = "en" }, cls = { en = "en", de = "de", fr = "fr", it = "it", es = "es", nl = "nl", sv = "sv",
		nb = "nb", ru = "ru" } },
	england = { langs = { en = "en", fallback = "en" }, cls = { en = "en" } },
	france = { langs = { en = "en", fallback = "en" }, cls = { en = "fr" } },
	germany = { langs = { de = "de", en = "en", fallback = "en" }, cls = { de = "de", en = "de" } },
	italy = { langs = { en = "en", fallback = "en" }, cls = { en = "it" } },
	spain = { langs = { en = "en", fallback = "en" }, cls = { en = "es" } },
	portugal = { langs = { en = "en", pt_BR = "pt_pt", fallback = "en" }, cls = { en = "pt", pt_pt = "pt" } },
	netherlands = { langs = { en = "en", fallback = "en" }, cls = { en = "nl" } },
	norway = { langs = { en = "en", fallback = "en" }, cls = { en = "nb" } },
	sweden = { langs = { en = "en", fallback = "en" }, cls = { en = "sv" } },
	usa = { langs = { en = "en", fallback = "en" }, cls = { en = "usa" } },
	japan = { langs = { en = "en", ja = "ja", fallback = "en" }, cls = { en = "ja_r", ja = "ja" } },
	russia = { langs = { en = "en", ru = "ru", de = "de", fallback = "en" }, cls = { en = "ru_r", ru = "ru", de = "ru_r" } },
	poland = { langs = { de = "de", en = "en", pl = "pl", fallback = "en" }, cls = {} },
	china = { langs = { de = "de", en = "en", zh_CN = "zh_CN", zh_TW = "zh_TW", fallback = "en" }, cls = {} },
	korea = { langs = { en = "en", ko = "ko", fallback = "en" }, cls = {} },
	asia = { langs = { en = "en", fallback = "en" }, cls = {} },
	oceania = { langs = { en = "en", fallback = "en" }, cls = {} },
}

--- The base list path of a save's nameList ("::/names/europe/europe.names" -> "europe"), or nil and why
--- ("noList" | "notBase" (another mod's set) | "unknownList").
function M.basePath(nameList)
	if type(nameList) ~= "string" or nameList == "" then return nil, "noList" end
	local p = nameList:match("^::/names/([%w_]+)/[%w_]+%.names$") or nameList:match("^::/names/([%w_]+)/[%w_]+%.names%.lua$")
	if p == nil then
		if nameList:match("^[^:]+::") then return nil, "notBase" end
		return nil, "unknownList"
	end
	if M.LISTS[p] == nil then return nil, "unknownList" end
	return p, nil
end

--- The list's language folders (distinct, sorted; the fallback first).
function M.langDirs(path)
	local L = M.LISTS[path]
	if L == nil then return {} end
	local seen, out = {}, {}
	local fb = L.langs.fallback
	if fb then
		seen[fb] = true
		out[1] = fb
	end
	local rest = {}
	for k, v in pairs(L.langs) do
		if k ~= "fallback" and not seen[v] then
			seen[v] = true
			rest[#rest + 1] = v
		end
	end
	table.sort(rest)
	for _, v in ipairs(rest) do out[#out + 1] = v end
	return out
end

--- The folder names.script.lua picks for a game language code: languages[lang] or languages.fallback (also tried: the
--- code's first two letters, "en_US" -> "en").
function M.dirForLang(path, lang)
	local L = M.LISTS[path]
	if L == nil then return nil end
	if type(lang) == "string" then
		if L.langs[lang] then return L.langs[lang] end
		local two = lang:sub(1, 2)
		if L.langs[two] then return L.langs[two] end
	end
	return L.langs.fallback
end

--- The folder in use: the game language's folder when the map's town names are in it (at least half of them), else the
--- folder holding the most of them (at least half), else nil. matches = { [dir] = n towns found in it }, nTowns.
--- Returns dir, source ("lang" | "match" | "only") or nil, why.
function M.pickDir(path, lang, matches, nTowns)
	local dirs = M.langDirs(path)
	if #dirs == 0 then return nil, "unknownList" end
	nTowns = tonumber(nTowns) or 0
	local need = math.max(1, math.ceil(nTowns * 0.5))
	if nTowns == 0 then return M.dirForLang(path, lang), "noTowns" end
	local want = M.dirForLang(path, lang)
	if want and (matches[want] or 0) >= need then return want, (#dirs == 1) and "only" or "lang" end
	local best, bn = nil, -1
	for _, d in ipairs(dirs) do
		local n = matches[d] or 0
		if n > bn then best, bn = d, n end
	end
	if best and bn >= need then return best, "match" end
	return nil, "noListMatch"
end

--- The classifier of a list folder (nil: no readable endings).
function M.classOf(path, dir)
	local L = M.LISTS[path]
	if L == nil then return nil end
	return L.cls[dir]
end

---------------------------------------------------------------------------
-- Name rules per classifier. Each rule { how, text, { tag = strength }, veto = { ... } }:
--   end    a word of the name (split at spaces, hyphens, apostrophes; ASCII lower case) ends with text, MIN_STEM letters
--          beside it            start  a word starts with text (MIN_STEM letters beside it)
--   word   a word is text       first / last  the first / last word is text (last: names of two words or more)
--   seq    the lower-case name contains text      has  the raw name contains text (Cyrillic, kanji)
-- veto: a matching word (end / start / word) or the name (seq / has) that contains any of these strings doesn't count.
-- A name's tags: the strongest strength per tag over its rules. Unmatched names are plain.

local function R(how, text, tags, veto) return { how, text, tags, veto = veto } end

local RU = {}

RU.en = {
	-- estuary / river mouth
	R("end", "mouth", { estuary = 1, coast = 0.3 }), R("start", "inver", { estuary = 0.9 }), R("start", "aber", { estuary = 0.9 }),
	-- crossings and rivers
	R("end", "ford", { ford = 1, river = 0.4 }), R("word", "ford", { ford = 1 }),
	R("seq", "bridge", { bridge = 1, river = 0.4 }), R("start", "bridg", { bridge = 0.9 }), R("word", "brigg", { bridge = 0.8 }),
	R("seq", "-on-", { river = 0.9 }, { "on-sea" }), R("seq", " on ", { river = 0.8 }, { " on sea" }),
	R("seq", "upon", { river = 0.9 }), R("seq", "-under-", { river = 0.5, hill = 0.4 }),
	R("end", "burn", { river = 0.7 }), R("end", "brook", { river = 0.7 }), R("end", "bourne", { river = 0.7 }),
	R("end", "borne", { river = 0.6 }), R("end", "water", { river = 0.5, lake = 0.5 }), R("end", "fleet", { river = 0.6, marsh = 0.4 }),
	-- coast / sea / port
	R("seq", "on-sea", { coast = 1 }), R("seq", "on sea", { coast = 1 }), R("seq", "by-the-sea", { coast = 1 }),
	R("start", "sea", { coast = 0.9 }), R("word", "sea", { coast = 1 }), R("end", "haven", { coast = 1 }),
	R("word", "haven", { coast = 1 }), R("start", "port", { coast = 0.8 }), R("end", "port", { coast = 0.5 }),
	R("end", "sands", { coast = 0.8 }), R("word", "sands", { coast = 0.8 }), R("word", "bay", { coast = 1 }),
	R("word", "beach", { coast = 1 }), R("end", "pool", { coast = 0.5, lake = 0.5 }), R("end", "quay", { coast = 0.8 }),
	R("end", "cove", { coast = 0.8 }),
	-- lake
	R("end", "mere", { lake = 1 }), R("word", "lake", { lake = 1 }), R("word", "lakes", { lake = 1 }), R("end", "tarn", { lake = 0.8 }),
	-- valley
	R("end", "combe", { valley = 1 }), R("end", "coombe", { valley = 1 }), R("end", "comb", { valley = 0.8 }),
	R("end", "dale", { valley = 1 }), R("word", "dale", { valley = 1 }), R("end", "dal", { valley = 0.6 }),
	R("word", "vale", { valley = 1 }), R("start", "glen", { valley = 0.8 }), R("end", "dean", { valley = 0.8 }),
	R("word", "dean", { valley = 0.8 }), R("end", "den", { valley = 0.5, forest = 0.4 }), R("end", "hope", { valley = 0.6 }),
	R("end", "bottom", { valley = 0.8 }), R("end", "slade", { valley = 0.6 }), R("end", "clough", { valley = 0.7 }),
	-- hill / mountain
	R("end", "don", { hill = 0.8 }), R("end", "hill", { hill = 1 }), R("word", "hill", { hill = 1 }),
	R("end", "down", { hill = 0.8 }), R("end", "downs", { hill = 0.8 }), R("end", "low", { hill = 0.6 }),
	R("end", "law", { hill = 0.6 }), R("start", "tor", { hill = 0.5 }), R("end", "tor", { hill = 0.7 }),
	R("end", "ridge", { hill = 0.9 }, { "bridge" }), R("start", "pen", { hill = 0.5, headland = 0.3 }),
	R("start", "mount", { hill = 1 }), R("word", "mount", { hill = 1 }), R("word", "high", { hill = 0.5 }),
	R("word", "upper", { hill = 0.4 }), R("end", "edge", { hill = 0.6 }), R("end", "crest", { hill = 0.8 }),
	R("end", "barrow", { hill = 0.4 }), R("end", "fell", { hill = 0.8 }), R("end", "pike", { hill = 0.7 }),
	-- cliff
	R("seq", "cliff", { cliff = 1 }), R("start", "clif", { cliff = 0.8 }), R("start", "cleve", { cliff = 0.8 }),
	R("end", "cleeve", { cliff = 0.8 }), R("start", "clive", { cliff = 0.6 }), R("word", "rock", { cliff = 0.7 }),
	R("end", "scar", { cliff = 0.7 }), R("end", "crag", { cliff = 0.8 }),
	-- headland / cape
	R("end", "ness", { headland = 1, coast = 0.3 }), R("end", "naze", { headland = 1 }), R("end", "head", { headland = 0.6 }),
	R("word", "point", { headland = 1 }), R("end", "nab", { headland = 0.6 }),
	-- island
	R("end", "holme", { island = 0.8, river = 0.3 }), R("end", "holm", { island = 0.8 }), R("word", "isle", { island = 1 }),
	R("word", "island", { island = 1 }), R("start", "isle", { island = 0.8 }),
	R("end", "ey", { island = 0.5, marsh = 0.5 }, { "ley", "rey", "bbey" }), R("end", "sea", { coast = 0.9 }), R("word", "eye", { island = 0.6, marsh = 0.4 }),
	-- forest / clearing
	R("end", "ley", { forest = 0.9 }), R("end", "leigh", { forest = 0.9 }), R("word", "leigh", { forest = 0.9 }),
	R("end", "lee", { forest = 0.7 }), R("end", "lea", { forest = 0.6 }), R("end", "hurst", { forest = 1 }),
	R("end", "wood", { forest = 1 }), R("word", "wood", { forest = 1 }), R("start", "wood", { forest = 0.6 }), R("end", "holt", { forest = 0.9 }),
	R("end", "shaw", { forest = 0.8 }), R("end", "grove", { forest = 0.8 }), R("end", "thwaite", { forest = 0.8 }),
	R("word", "forest", { forest = 1 }), R("word", "chase", { forest = 0.8 }), R("start", "oak", { forest = 0.5 }),
	R("end", "hay", { forest = 0.4 }), R("end", "hey", { forest = 0.4 }),
	-- marsh / moor
	R("end", "marsh", { marsh = 1 }), R("word", "marsh", { marsh = 1 }), R("end", "moor", { marsh = 0.8, hill = 0.3 }),
	R("word", "moor", { marsh = 0.8 }), R("start", "moor", { marsh = 0.6 }), R("end", "fen", { marsh = 0.8 }),
	R("word", "fen", { marsh = 0.8 }), R("end", "carr", { marsh = 0.7 }), R("end", "moss", { marsh = 0.8 }),
	R("end", "wash", { marsh = 0.7 }), R("end", "mire", { marsh = 0.8 }),
	-- market / town
	R("first", "market", { market = 1 }), R("end", "market", { market = 1 }), R("first", "chipping", { market = 1 }),
	R("end", "minster", { market = 0.8 }), R("end", "borough", { market = 0.6 }), R("end", "brough", { market = 0.5 }),
	R("end", "bury", { market = 0.5 }), R("first", "bishop", { market = 0.5 }), R("start", "king", { market = 0.5 }),
	R("end", "chester", { market = 0.6 }), R("end", "caster", { market = 0.6 }), R("end", "cester", { market = 0.6 }),
	-- plain
	R("end", "field", { plain = 0.8 }), R("end", "heath", { plain = 0.7 }), R("end", "ton", { plain = 0.5 }),
	R("end", "ham", { plain = 0.5 }), R("end", "by", { plain = 0.5 }), R("end", "thorpe", { plain = 0.5 }),
	R("end", "thorp", { plain = 0.5 }), R("end", "worth", { plain = 0.5 }), R("end", "wick", { plain = 0.4 }),
	R("end", "wich", { plain = 0.4 }), R("end", "stow", { plain = 0.4 }),
}

RU.usa = {
	R("last", "falls", { river = 1, valley = 0.5 }), R("last", "springs", { valley = 0.8 }), R("last", "heights", { hill = 1 }),
	R("first", "lake", { lake = 1 }), R("last", "lake", { lake = 1 }), R("start", "lake", { lake = 0.8 }),
	R("last", "lakes", { lake = 1 }), R("word", "bay", { coast = 1 }), R("start", "bay", { coast = 0.8 }),
	R("first", "port", { coast = 1 }), R("start", "port", { coast = 0.7 }), R("end", "port", { coast = 0.6 }),
	R("first", "fort", { market = 0.6, river = 0.3 }), R("first", "mount", { hill = 1 }), R("start", "mount", { hill = 0.8 }),
	R("word", "mountain", { hill = 1 }), R("last", "beach", { coast = 1 }), R("last", "valley", { valley = 1 }),
	R("first", "valley", { valley = 1 }), R("start", "glen", { valley = 0.8 }), R("end", "dale", { valley = 0.8 }),
	R("word", "canyon", { valley = 1 }), R("word", "gorge", { valley = 0.9 }),
	R("last", "hills", { hill = 0.9 }), R("last", "hill", { hill = 0.9 }), R("start", "hill", { hill = 0.7 }),
	R("last", "ridge", { hill = 0.9 }), R("start", "crest", { hill = 0.7 }), R("word", "summit", { hill = 1 }),
	R("start", "highland", { hill = 0.8 }), R("word", "mesa", { hill = 0.8 }),
	R("last", "bluff", { cliff = 1 }), R("last", "bluffs", { cliff = 1 }), R("seq", "cliff", { cliff = 0.9 }),
	R("word", "rock", { cliff = 0.6 }),
	R("last", "point", { headland = 1 }), R("first", "point", { headland = 0.8 }), R("first", "cape", { headland = 1 }),
	R("word", "island", { island = 1 }), R("word", "isle", { island = 1 }), R("word", "key", { island = 0.8 }),
	R("last", "grove", { forest = 0.9 }), R("word", "forest", { forest = 1 }), R("end", "wood", { forest = 0.9 }),
	R("last", "woods", { forest = 1 }), R("start", "oak", { forest = 0.6 }), R("start", "pine", { forest = 0.7 }),
	R("start", "cedar", { forest = 0.6 }), R("start", "elm", { forest = 0.5 }), R("start", "maple", { forest = 0.5 }),
	R("last", "harbor", { coast = 1 }), R("last", "harbour", { coast = 1 }), R("last", "haven", { coast = 0.7 }),
	R("word", "sound", { coast = 0.8 }), R("last", "shores", { coast = 0.7, lake = 0.6 }), R("last", "shore", { coast = 0.7, lake = 0.5 }),
	R("last", "inlet", { estuary = 0.9 }), R("end", "mouth", { estuary = 0.9 }),
	R("end", "ford", { ford = 1 }), R("word", "ferry", { ford = 0.8, river = 0.6 }), R("seq", "bridge", { bridge = 1 }),
	R("last", "fork", { river = 0.8 }), R("last", "forks", { river = 0.9 }), R("last", "creek", { river = 0.9 }), R("first", "river", { river = 1 }), R("start", "river", { river = 0.9 }),
	R("last", "rapids", { river = 1 }), R("end", "brook", { river = 0.6 }), R("end", "water", { lake = 0.6, river = 0.4 }),
	R("word", "marsh", { marsh = 1 }), R("word", "swamp", { marsh = 1 }), R("word", "bayou", { marsh = 0.9, river = 0.5 }),
	R("last", "junction", { market = 0.7 }), R("last", "center", { market = 0.6 }), R("last", "city", { market = 0.6 }),
	R("last", "plains", { plain = 1 }), R("word", "prairie", { plain = 1 }), R("last", "meadows", { plain = 0.8 }),
	R("end", "field", { plain = 0.7 }), R("end", "ville", { plain = 0.6 }), R("end", "burg", { plain = 0.4 }),
	R("end", "ton", { plain = 0.4 }), R("last", "park", { plain = 0.4 }),
}

RU.de = {
	R("end", "münde", { estuary = 1, coast = 0.4 }), R("end", "mündung", { estuary = 1 }),
	R("end", "furt", { ford = 1, river = 0.5 }), R("end", "furth", { ford = 1 }), R("end", "fürth", { ford = 0.8 }),
	R("end", "brück", { bridge = 1, river = 0.4 }), R("end", "brücken", { bridge = 1 }), R("word", "brück", { bridge = 1 }),
	R("end", "bruck", { bridge = 0.9 }), R("end", "brugg", { bridge = 0.9 }), R("start", "brück", { bridge = 0.8 }),
	R("end", "bach", { river = 0.7, valley = 0.5 }), R("end", "beck", { river = 0.6 }), R("end", "ach", { river = 0.5 }),
	R("end", "au", { river = 0.6, marsh = 0.4 }), R("end", "aue", { river = 0.6 }),
	R("seq", " am ", { river = 0.7 }, { " am see" }), R("seq", " an der ", { river = 0.8 }), R("seq", " a. d. ", { river = 0.7 }),
	R("end", "hafen", { coast = 1 }), R("word", "hafen", { coast = 1 }), R("end", "haven", { coast = 1 }),
	R("end", "siel", { coast = 0.8, marsh = 0.4 }), R("end", "strand", { coast = 0.9 }), R("seq", "seebad", { coast = 1 }),
	R("end", "deich", { coast = 0.6, marsh = 0.6 }), R("end", "sund", { coast = 0.8 }),
	R("end", "see", { lake = 1 }), R("seq", "am see", { lake = 1 }), R("end", "seen", { lake = 1 }),
	R("end", "weiher", { lake = 0.7 }), R("end", "teich", { lake = 0.6 }),
	R("end", "tal", { valley = 1 }), R("end", "thal", { valley = 1 }), R("end", "grund", { valley = 0.8 }),
	R("first", "bad", { valley = 0.6 }), R("end", "born", { valley = 0.4 }), R("end", "brunn", { valley = 0.4 }),
	R("end", "bronn", { valley = 0.4 }),
	R("end", "berg", { hill = 1 }), R("end", "bergen", { hill = 0.8 }), R("start", "berg", { hill = 0.6 }),
	R("end", "höhe", { hill = 1 }), R("end", "kopf", { hill = 0.8 }), R("end", "bühl", { hill = 0.8 }),
	R("end", "egg", { hill = 0.6 }), R("end", "burg", { hill = 0.2, market = 0.3 }),
	R("end", "stein", { cliff = 0.9, hill = 0.3 }), R("start", "stein", { cliff = 0.5 }), R("end", "fels", { cliff = 1 }),
	R("end", "felsen", { cliff = 1 }), R("end", "wand", { cliff = 0.7 }),
	R("end", "horn", { headland = 0.6 }),
	R("end", "werder", { island = 1, river = 0.4 }), R("end", "wörth", { island = 0.9, river = 0.4 }),
	R("end", "wert", { island = 0.6 }), R("end", "ooge", { island = 1 }), R("end", "oog", { island = 1 }),
	R("word", "insel", { island = 1 }),
	R("end", "wald", { forest = 1 }), R("end", "walde", { forest = 1 }), R("end", "holz", { forest = 0.9 }),
	R("end", "hain", { forest = 0.8 }), R("end", "forst", { forest = 1 }), R("end", "rode", { forest = 0.8 }),
	R("end", "roda", { forest = 0.8 }), R("end", "rod", { forest = 0.6 }), R("end", "reuth", { forest = 0.8 }),
	R("end", "reut", { forest = 0.7 }), R("end", "rath", { forest = 0.6 }), R("end", "schwand", { forest = 0.7 }),
	R("end", "schlag", { forest = 0.6 }), R("end", "loh", { forest = 0.7 }), R("end", "lohe", { forest = 0.7 }),
	R("end", "busch", { forest = 0.8 }), R("end", "hagen", { forest = 0.4 }), R("end", "eichen", { forest = 0.6 }),
	R("start", "eich", { forest = 0.5 }), R("end", "linden", { forest = 0.5 }), R("end", "buch", { forest = 0.6 }),
	R("end", "tann", { forest = 0.7 }), R("end", "hardt", { forest = 0.8 }), R("end", "hart", { forest = 0.6 }),
	R("end", "moor", { marsh = 1 }), R("end", "bruch", { marsh = 0.9 }), R("end", "ried", { marsh = 0.8 }),
	R("end", "fenn", { marsh = 0.9 }), R("end", "venn", { marsh = 0.9 }), R("end", "broich", { marsh = 0.7 }),
	R("end", "horst", { marsh = 0.4, forest = 0.4 }),
	R("first", "markt", { market = 1 }), R("end", "markt", { market = 1 }), R("end", "münster", { market = 0.8 }), R("end", "stadt", { market = 0.6 }),
	R("end", "hausen", { plain = 0.7 }), R("end", "heim", { plain = 0.6 }), R("end", "dorf", { plain = 0.6 }),
	R("end", "ingen", { plain = 0.5 }), R("end", "feld", { plain = 0.8 }), R("end", "felde", { plain = 0.8 }),
	R("end", "leben", { plain = 0.5 }), R("end", "stedt", { plain = 0.5 }), R("end", "weiler", { plain = 0.5 }),
	R("end", "hofen", { plain = 0.5 }), R("end", "heide", { plain = 0.7 }),
}

RU.fr = {
	R("seq", "-sur-mer", { coast = 1 }), R("seq", " sur mer", { coast = 1 }), R("word", "plage", { coast = 1 }),
	R("first", "port", { coast = 1 }), R("word", "port", { coast = 0.8 }), R("word", "mer", { coast = 0.8 }),
	R("seq", "-les-bains", { valley = 0.7 }), R("word", "bains", { valley = 0.7 }),
	R("first", "pont", { bridge = 1, river = 0.4 }), R("word", "pont", { bridge = 1 }), R("start", "pont", { bridge = 0.6 }),
	R("word", "ponts", { bridge = 1 }), R("first", "gué", { ford = 1 }), R("word", "gué", { ford = 1 }),
	R("seq", "-sur-", { river = 0.9 }, { "-sur-mer" }), R("seq", " sur ", { river = 0.8 }, { " sur mer" }),
	R("seq", "-lès-", { river = 0.3 }),
	R("first", "mont", { hill = 1 }), R("word", "mont", { hill = 1 }), R("start", "mont", { hill = 0.8 }),
	R("end", "mont", { hill = 0.7 }), R("word", "puy", { hill = 0.9 }), R("word", "côte", { hill = 0.5, coast = 0.5 }),
	R("word", "roche", { cliff = 1 }), R("start", "roche", { cliff = 0.8 }), R("end", "roche", { cliff = 0.8 }),
	R("word", "falaise", { cliff = 1 }), R("word", "cap", { headland = 1 }), R("first", "pointe", { headland = 1 }),
	R("word", "bec", { headland = 0.6 }),
	R("word", "forêt", { forest = 1 }), R("word", "bois", { forest = 1 }), R("start", "bois", { forest = 0.8 }),
	R("word", "vallée", { valley = 1 }), R("first", "val", { valley = 1 }), R("word", "val", { valley = 1 }),
	R("word", "vaux", { valley = 0.8 }), R("word", "combe", { valley = 0.8 }),
	R("word", "lac", { lake = 1 }), R("word", "étang", { lake = 0.8 }), R("word", "étangs", { lake = 0.8, marsh = 0.4 }),
	R("word", "île", { island = 1 }), R("word", "isle", { island = 0.9 }), R("seq", "l'isle", { island = 0.9 }),
	R("seq", "l'île", { island = 1 }),
	R("word", "marais", { marsh = 1 }),
	R("word", "marché", { market = 1 }), R("word", "bourg", { market = 0.6 }), R("start", "bourg", { market = 0.5 }),
	R("end", "ville", { plain = 0.6 }), R("word", "champs", { plain = 0.8 }), R("word", "plaine", { plain = 1 }),
	R("end", "court", { plain = 0.4 }),
}

RU.it = {
	R("first", "porto", { coast = 1 }), R("start", "porto", { coast = 0.9 }), R("word", "porto", { coast = 0.9 }),
	R("first", "marina", { coast = 1 }), R("seq", "di mare", { coast = 1 }), R("seq", "al mare", { coast = 1 }),
	R("seq", "a mare", { coast = 1 }), R("word", "mare", { coast = 0.8 }), R("word", "lido", { coast = 0.9 }),
	R("word", "riva", { lake = 0.6, coast = 0.4 }),
	R("first", "monte", { hill = 1 }), R("start", "monte", { hill = 0.9 }), R("start", "mont", { hill = 0.7 }),
	R("end", "monte", { hill = 0.8 }), R("first", "castel", { hill = 0.7 }), R("start", "castel", { hill = 0.6 }),
	R("first", "castello", { hill = 0.7 }), R("first", "colle", { hill = 0.9 }), R("start", "colle", { hill = 0.8 }),
	R("start", "colli", { hill = 0.8 }), R("start", "poggio", { hill = 0.9 }), R("start", "serra", { hill = 0.8 }),
	R("first", "rocca", { cliff = 0.8, hill = 0.5 }), R("start", "rocca", { cliff = 0.7, hill = 0.4 }),
	R("first", "sasso", { cliff = 0.9 }), R("start", "sasso", { cliff = 0.8 }), R("first", "pietra", { cliff = 0.8 }),
	R("start", "pietra", { cliff = 0.7 }),
	R("first", "valle", { valley = 1 }), R("start", "valle", { valley = 0.8 }), R("first", "val", { valley = 0.9 }),
	R("word", "valle", { valley = 1 }), R("word", "terme", { valley = 0.7 }), R("first", "bagni", { valley = 0.7 }),
	R("first", "ponte", { bridge = 1 }), R("start", "ponte", { bridge = 0.8 }), R("word", "ponte", { bridge = 1 }),
	R("word", "guado", { ford = 1 }), R("word", "fiume", { river = 1 }), R("seq", " sul ", { river = 0.8 }),
	R("seq", " sull'", { river = 0.8 }), R("word", "foce", { estuary = 1 }),
	R("word", "lago", { lake = 1 }), R("start", "lago", { lake = 0.8 }),
	R("first", "isola", { island = 1 }), R("word", "isola", { island = 1 }), R("seq", "d'ischia", { island = 0.9 }),
	R("first", "bosco", { forest = 1 }), R("start", "bosco", { forest = 0.8 }), R("word", "selva", { forest = 1 }),
	R("start", "selva", { forest = 0.8 }),
	R("first", "capo", { headland = 1 }), R("first", "punta", { headland = 1 }),
	R("word", "palude", { marsh = 1 }), R("word", "padule", { marsh = 1 }),
	R("first", "borgo", { market = 0.7 }), R("start", "borgo", { market = 0.6 }), R("word", "mercato", { market = 1 }),
	R("first", "piano", { plain = 1 }), R("start", "pian", { plain = 0.8 }), R("word", "piana", { plain = 0.8 }),
	R("word", "campagna", { plain = 0.8 }), R("start", "campo", { plain = 0.7 }), R("start", "villa", { plain = 0.5 }),
}

RU.es = {
	R("first", "puerto", { coast = 1 }), R("word", "puerto", { coast = 1 }), R("seq", "del mar", { coast = 1 }),
	R("seq", "de mar", { coast = 1 }), R("word", "mar", { coast = 0.8 }), R("word", "playa", { coast = 1 }),
	R("word", "platja", { coast = 1 }), R("first", "port", { coast = 0.8 }),
	R("word", "monte", { hill = 0.9 }), R("start", "mont", { hill = 0.6 }), R("word", "sierra", { hill = 1 }),
	R("word", "serra", { hill = 0.9 }), R("word", "castillo", { hill = 0.6 }), R("start", "castell", { hill = 0.6 }),
	R("start", "alcal", { hill = 0.5 }),
	R("word", "peña", { cliff = 0.9 }), R("start", "peña", { cliff = 0.8 }), R("word", "roca", { cliff = 0.8 }),
	R("word", "valle", { valley = 1 }), R("word", "val", { valley = 0.8 }), R("word", "vall", { valley = 0.9 }),
	R("start", "vall", { valley = 0.6 }), R("word", "caldas", { valley = 0.7 }), R("word", "caldes", { valley = 0.7 }),
	R("word", "puente", { bridge = 1 }), R("word", "pont", { bridge = 0.9 }), R("word", "ponte", { bridge = 0.9 }),
	R("word", "vado", { ford = 1 }),
	R("seq", "del río", { river = 1 }), R("seq", "del rio", { river = 1 }), R("seq", "de duero", { river = 0.9 }),
	R("seq", "de ebro", { river = 0.9 }), R("seq", "de tajo", { river = 0.9 }), R("seq", "de llobregat", { river = 0.9 }),
	R("word", "río", { river = 0.9 }), R("word", "riba", { river = 0.6 }), R("word", "ribera", { river = 0.8 }),
	R("word", "isla", { island = 1 }), R("word", "illa", { island = 1 }),
	R("word", "lago", { lake = 1 }), R("word", "laguna", { lake = 0.8, marsh = 0.5 }),
	R("word", "cabo", { headland = 1 }), R("word", "punta", { headland = 1 }),
	R("word", "bosque", { forest = 1 }), R("word", "selva", { forest = 0.9 }), R("word", "pinar", { forest = 0.9 }),
	R("word", "robledo", { forest = 0.8 }),
	R("word", "marisma", { marsh = 1 }), R("word", "mercado", { market = 1 }),
	R("word", "campo", { plain = 0.9 }), R("word", "campos", { plain = 0.9 }), R("word", "llano", { plain = 0.9 }),
	R("word", "vega", { plain = 0.6, river = 0.4 }), R("word", "villa", { plain = 0.5 }), R("start", "vila", { plain = 0.4 }),
}

RU.pt = {
	R("first", "porto", { coast = 1 }), R("word", "porto", { coast = 0.9 }), R("word", "foz", { estuary = 1 }),
	R("word", "praia", { coast = 1 }), R("word", "mar", { coast = 0.8 }), R("word", "ponte", { bridge = 1 }),
	R("word", "monte", { hill = 1 }), R("start", "monte", { hill = 0.8 }), R("word", "serra", { hill = 1 }),
	R("word", "castelo", { hill = 0.7 }), R("word", "vale", { valley = 1 }), R("word", "caldas", { valley = 0.7 }),
	R("word", "ilha", { island = 1 }), R("word", "lagoa", { lake = 1 }), R("word", "rio", { river = 0.9 }),
	R("word", "penha", { cliff = 0.9 }), R("word", "pena", { cliff = 0.6 }), R("word", "cabo", { headland = 1 }),
	R("word", "mata", { forest = 0.8 }), R("word", "pinhal", { forest = 1 }), R("word", "bosque", { forest = 1 }),
	R("word", "campo", { plain = 0.9 }), R("word", "vila", { plain = 0.4 }), R("word", "póvoa", { plain = 0.5 }),
}

RU.nl = {
	R("end", "dam", { river = 0.9 }), R("end", "dijk", { marsh = 0.6, coast = 0.5 }), R("end", "dyk", { marsh = 0.6, coast = 0.5 }),
	R("end", "veen", { marsh = 1 }), R("end", "haven", { coast = 1 }), R("word", "haven", { coast = 1 }),
	R("end", "wolde", { forest = 0.8 }), R("end", "woude", { forest = 0.8 }), R("end", "wold", { forest = 0.7 }),
	R("end", "brug", { bridge = 1 }), R("end", "brugge", { bridge = 1 }), R("end", "hout", { forest = 1 }),
	R("end", "holt", { forest = 0.9 }), R("end", "horst", { forest = 0.8 }), R("end", "loo", { forest = 0.7 }),
	R("end", "lo", { forest = 0.5 }), R("end", "rode", { forest = 0.7 }),
	R("end", "berg", { hill = 1 }), R("end", "heuvel", { hill = 1 }), R("end", "meer", { lake = 1 }),
	R("end", "zee", { coast = 1 }), R("seq", "aan zee", { coast = 1 }), R("end", "sluis", { coast = 0.6, river = 0.5 }),
	R("end", "duin", { coast = 0.9 }), R("end", "duinen", { coast = 0.9 }), R("end", "zand", { coast = 0.4, plain = 0.3 }),
	R("end", "mond", { estuary = 1 }), R("end", "monde", { estuary = 1 }), R("end", "muiden", { estuary = 1 }),
	R("end", "trecht", { ford = 1 }), R("end", "tricht", { ford = 1 }), R("end", "drecht", { ford = 1 }),
	R("end", "broek", { marsh = 0.9 }), R("end", "ven", { marsh = 0.7 }),
	R("end", "waard", { island = 0.7, marsh = 0.5 }), R("end", "weerd", { island = 0.6 }), R("end", "ward", { island = 0.5 }),
	R("end", "beek", { river = 0.7 }), R("start", "maas", { river = 0.7 }), R("start", "rijn", { river = 0.7 }),
	R("seq", "aan de ", { river = 0.8 }), R("seq", "aan den ", { river = 0.8 }), R("seq", "aan het ", { river = 0.6 }),
	R("end", "dal", { valley = 0.9 }),
	R("end", "markt", { market = 0.8 }),
	R("end", "wijk", { plain = 0.5 }), R("end", "kerk", { plain = 0.4 }), R("end", "dorp", { plain = 0.6 }),
	R("end", "veld", { plain = 0.8 }), R("end", "heide", { plain = 0.7 }), R("end", "oord", { plain = 0.4 }),
}

-- Swedish and Norwegian (one rule set: both spellings)
RU.nordic = {
	R("end", "vik", { coast = 1 }), R("end", "viken", { coast = 1 }), R("end", "vika", { coast = 1 }),
	R("end", "fjord", { coast = 1 }), R("end", "fjorden", { coast = 1 }), R("end", "sund", { coast = 0.9 }),
	R("end", "sundet", { coast = 0.9 }), R("end", "strand", { coast = 0.9 }), R("end", "stranden", { coast = 0.9 }),
	R("end", "hamn", { coast = 1 }), R("end", "havn", { coast = 1 }), R("end", "haven", { coast = 1 }),
	R("end", "kil", { coast = 0.6 }), R("end", "os", { estuary = 0.6 }), R("end", "oset", { estuary = 0.8 }),
	R("end", "dal", { valley = 1 }), R("end", "dalen", { valley = 1 }),
	R("end", "berg", { hill = 1 }), R("end", "berget", { hill = 1 }), R("end", "backe", { hill = 0.8 }),
	R("end", "backen", { hill = 0.8 }), R("end", "bakken", { hill = 0.8 }), R("end", "ås", { hill = 0.9 }),
	R("end", "åsen", { hill = 0.9 }), R("end", "fjäll", { hill = 1 }), R("end", "fjell", { hill = 1 }),
	R("end", "klint", { cliff = 0.9 }), R("end", "klev", { cliff = 0.7 }), R("end", "stup", { cliff = 0.8 }),
	R("end", "näs", { headland = 1 }), R("end", "nes", { headland = 1 }), R("end", "næs", { headland = 1 }),
	R("end", "udde", { headland = 1 }), R("end", "odde", { headland = 1 }),
	R("end", "holm", { island = 1 }), R("end", "holmen", { island = 1 }), R("end", "ö", { island = 0.9 }),
	R("end", "ön", { island = 0.9 }), R("end", "øy", { island = 0.9 }), R("end", "øya", { island = 0.9 }),
	R("end", "öy", { island = 0.9 }), R("end", "ø", { island = 0.8 }),
	R("end", "skog", { forest = 1 }), R("end", "skogen", { forest = 1 }), R("end", "rud", { forest = 0.7 }),
	R("end", "ryd", { forest = 0.7 }), R("end", "red", { forest = 0.6 }), R("end", "hult", { forest = 0.8 }),
	R("end", "lund", { forest = 0.7 }), R("end", "torp", { forest = 0.5, plain = 0.4 }),
	R("end", "sjö", { lake = 1 }), R("end", "sjön", { lake = 1 }), R("end", "vatn", { lake = 1 }),
	R("end", "vattnet", { lake = 1 }), R("end", "vann", { lake = 0.9 }), R("end", "träsk", { lake = 0.8, marsh = 0.5 }),
	R("end", "älv", { river = 1 }), R("end", "elv", { river = 1 }), R("end", "elva", { river = 1 }),
	R("end", "ån", { river = 0.8 }), R("end", "å", { river = 0.6 }), R("end", "bäck", { river = 0.7 }),
	R("end", "bäcken", { river = 0.7 }), R("end", "bekk", { river = 0.7 }), R("end", "fors", { river = 0.9, valley = 0.4 }),
	R("end", "forsen", { river = 0.9, valley = 0.4 }), R("end", "foss", { river = 0.9 }), R("end", "sele", { river = 0.6 }),
	R("end", "bro", { bridge = 1 }), R("end", "broen", { bridge = 1 }),
	R("end", "myr", { marsh = 1 }), R("end", "myra", { marsh = 1 }), R("end", "mossen", { marsh = 0.9 }),
	R("end", "mosse", { marsh = 0.9 }), R("end", "kärr", { marsh = 0.8 }),
	R("end", "köping", { market = 1 }), R("end", "kjøping", { market = 1 }), R("end", "stad", { market = 0.4 }),
	R("end", "by", { plain = 0.6 }), R("end", "byn", { plain = 0.6 }), R("end", "mark", { plain = 0.6, forest = 0.3 }),
	R("end", "vall", { plain = 0.6 }), R("end", "mo", { plain = 0.5 }), R("end", "moen", { plain = 0.5 }),
	R("end", "heim", { plain = 0.5 }), R("end", "hed", { plain = 0.6 }), R("end", "heden", { plain = 0.6 }),
}

-- Japanese, romanised (japan/en: "Sapporo", "Tokorozawa")
RU.ja_r = {
	R("end", "yama", { hill = 1 }), R("end", "kawa", { river = 1 }), R("end", "gawa", { river = 1 }),
	R("end", "hama", { coast = 1 }), R("end", "shima", { island = 1 }), R("end", "jima", { island = 1 }),
	R("end", "saki", { headland = 1 }), R("end", "zaki", { headland = 1 }), R("end", "sawa", { valley = 0.7, marsh = 0.5 }),
	R("end", "zawa", { valley = 0.7, marsh = 0.5 }), R("end", "mori", { forest = 1 }), R("end", "matsu", { forest = 0.6 }),
	R("end", "tani", { valley = 1 }), R("end", "dani", { valley = 1 }), R("end", "ya", { valley = 0.4 }),
	R("end", "oka", { hill = 0.8 }), R("end", "mine", { hill = 0.8 }), R("end", "iwa", { cliff = 0.8 }),
	R("end", "ishi", { cliff = 0.4 }), R("end", "ura", { coast = 0.8 }), R("end", "tsu", { coast = 0.7 }),
	R("end", "zu", { coast = 0.5 }), R("end", "ike", { lake = 0.8 }), R("end", "numa", { marsh = 0.9, lake = 0.4 }),
	R("end", "hashi", { bridge = 1 }), R("end", "bashi", { bridge = 1 }), R("end", "se", { river = 0.5 }),
	R("end", "kuchi", { estuary = 0.8 }), R("end", "guchi", { estuary = 0.8 }), R("end", "ichi", { market = 0.7 }),
	R("end", "ta", { plain = 0.7 }), R("end", "da", { plain = 0.7 }), R("end", "no", { plain = 0.6 }),
	R("end", "hara", { plain = 0.8 }), R("end", "bara", { plain = 0.8 }), R("end", "wara", { plain = 0.8 }),
	R("end", "maki", { plain = 0.5 }),
}

-- Japanese, kanji (japan/ja: "川口市"; the trailing 市 / 町 / 村 / 区 is stripped first)
RU.ja = {
	R("has", "山", { hill = 1 }), R("has", "川", { river = 1 }), R("has", "河", { river = 0.9 }), R("has", "浜", { coast = 1 }),
	R("has", "島", { island = 1 }), R("has", "崎", { headland = 1 }), R("has", "沢", { valley = 0.7, marsh = 0.5 }),
	R("has", "森", { forest = 1 }), R("has", "林", { forest = 0.8 }), R("has", "松", { forest = 0.6 }),
	R("has", "谷", { valley = 1 }), R("has", "岡", { hill = 0.8 }), R("has", "丘", { hill = 0.9 }), R("has", "峰", { hill = 0.9 }),
	R("has", "坂", { hill = 0.7 }), R("has", "台", { hill = 0.6 }), R("has", "岩", { cliff = 0.8 }),
	R("has", "浦", { coast = 0.9 }), R("has", "津", { coast = 0.8 }), R("has", "港", { coast = 1 }), R("has", "海", { coast = 1 }),
	R("has", "江", { coast = 0.5, estuary = 0.4 }), R("has", "口", { estuary = 0.7 }), R("has", "池", { lake = 0.8 }),
	R("has", "湖", { lake = 1 }), R("has", "沼", { marsh = 0.9, lake = 0.4 }), R("has", "橋", { bridge = 1 }),
	R("has", "瀬", { river = 0.6 }), R("has", "田", { plain = 0.7 }), R("has", "野", { plain = 0.7 }),
	R("has", "原", { plain = 0.8 }), R("has", "平", { plain = 0.6 }),
}

-- Russian, Cyrillic (europe/ru, russia/ru): no case folding in Lua, so the capitalised forms are listed too
RU.ru = {
	R("has", "Усть", { estuary = 1 }), R("has", "устье", { estuary = 1 }),
	R("has", "горск", { hill = 1 }), R("has", "Горно", { hill = 1 }), R("has", "горн", { hill = 0.8 }),
	R("has", "Гора", { hill = 0.9 }), R("has", "холм", { hill = 0.9 }), R("has", "Холм", { hill = 0.9 }),
	R("has", "озёр", { lake = 1 }), R("has", "озер", { lake = 1 }), R("has", "Озёр", { lake = 1 }), R("has", "Озер", { lake = 1 }),
	R("has", "речен", { river = 1 }), R("has", "речн", { river = 0.9 }), R("has", "Речиц", { river = 0.8 }),
	R("has", "Заречн", { river = 1 }),
	R("has", "морск", { coast = 1 }), R("has", "Морск", { coast = 1 }), R("has", "Примор", { coast = 1 }),
	R("has", "Лесн", { forest = 1 }), R("has", "лесн", { forest = 0.9 }), R("has", "Лесо", { forest = 0.9 }),
	R("has", "Сосн", { forest = 0.9 }), R("has", "Берёз", { forest = 0.7 }), R("has", "Берез", { forest = 0.7 }),
	R("has", "Дубр", { forest = 0.8 }), R("word", "Бор", { forest = 1 }), R("has", "Боров", { forest = 0.8 }),
	R("has", "Остров", { island = 1 }), R("has", "Долин", { valley = 1 }),
	R("has", "Мост", { bridge = 1 }), R("has", "мост", { bridge = 0.9 }), R("has", "Брод", { ford = 1 }), R("has", "брод", { ford = 0.9 }),
	R("has", "Болот", { marsh = 1 }), R("has", "Камен", { cliff = 0.9 }), R("has", "камен", { cliff = 0.8 }),
	R("has", "Скал", { cliff = 0.9 }), R("has", "Мыс", { headland = 1 }),
	R("has", "Торж", { market = 1 }), R("has", "Посад", { market = 0.9 }), R("has", "Полян", { plain = 0.7 }),
}

-- Russian, romanised (russia/en "Ust-Ilimsk", russia/de "Gorno-Altajsk")
RU.ru_r = {
	R("first", "ust", { estuary = 1 }), R("seq", "gorsk", { hill = 1 }), R("start", "gorno", { hill = 1 }),
	R("start", "kholm", { hill = 0.9 }), R("seq", "ozersk", { lake = 1 }), R("seq", "ozyorsk", { lake = 1 }),
	R("seq", "ozyorn", { lake = 1 }), R("seq", "ozern", { lake = 1 }), R("seq", "osjor", { lake = 1 }),
	R("seq", "rechensk", { river = 1 }), R("seq", "rechn", { river = 0.9 }), R("start", "zarech", { river = 1 }),
	R("seq", "retschen", { river = 1 }), R("seq", "morsk", { coast = 1 }), R("start", "primor", { coast = 1 }),
	R("start", "lesno", { forest = 1 }), R("start", "lesoz", { forest = 0.9 }), R("start", "sosno", { forest = 0.9 }),
	R("start", "berez", { forest = 0.7 }), R("word", "bor", { forest = 1 }), R("start", "borovi", { forest = 0.8 }),
	R("start", "ostrov", { island = 1 }), R("start", "dolin", { valley = 1 }), R("seq", "kamensk", { cliff = 0.9 }),
	R("start", "kamen", { cliff = 0.7 }), R("start", "most", { bridge = 1 }), R("start", "brod", { ford = 1 }),
	R("start", "boloto", { marsh = 1 }), R("start", "torzh", { market = 1 }), R("word", "posad", { market = 0.9 }),
}

M.RULES = RU
-- classifier id -> rule set
M.RULESET = { en = "en", usa = "usa", de = "de", fr = "fr", it = "it", es = "es", pt = "pt", nl = "nl", sv = "nordic",
	nb = "nordic", ja_r = "ja_r", ja = "ja", ru = "ru", ru_r = "ru_r" }

-- composed satellite names per classifier ("%s" = the parent's name)
M.SAT = { en = { "Little %s", "Nether %s", "%s End" }, de = { "Klein %s", "%s-Dorf" }, fr = { "Petit-%s", "%s-le-Petit" },
	nl = { "Klein %s" }, sv = { "Lilla %s" }, nb = { "Lille %s" }, it = { "%s Piccolo" }, es = { "%s el Chico" },
	usa = { "East %s", "%s Junction" }, ja = { "新%s" }, ja_r = { "Shin-%s" } }

local JA_SUFFIX = { "市", "町", "村", "区" }

-- ASCII-only lower case: string.lower follows the C locale, and a UTF-8 locale folds single bytes of multi-byte
-- letters (macOS: 0xC3 -> 0xE3), which breaks "ü" (seen offline 2026-10-13)
local LOWER = {}
for c = 65, 90 do LOWER[string.char(c)] = string.char(c + 32) end
function M.lower(s)
	return (s:gsub("[A-Z]", LOWER))
end

local function words(lower)
	local out = {}
	for w in lower:gmatch("[^%s%-']+") do
		out[#out + 1] = w
		if #out >= M.MAX_WORDS then break end
	end
	return out
end

local function vetoed(s, veto)
	if veto == nil then return false end
	for _, v in ipairs(veto) do
		if s:find(v, 1, true) then return true end
	end
	return false
end

local function ruleHits(rule, raw, lower, ws)
	local how, t = rule[1], rule[2]
	local n = #t
	if how == "seq" then
		return lower:find(t, 1, true) ~= nil and not vetoed(lower, rule.veto)
	elseif how == "has" then
		return raw:find(t, 1, true) ~= nil and not vetoed(raw, rule.veto)
	elseif how == "first" then
		return ws[1] == t
	elseif how == "last" then
		return #ws >= 2 and ws[#ws] == t
	end
	for _, w in ipairs(ws) do
		local hit = false
		if how == "end" then hit = #w >= n + M.MIN_STEM and w:sub(-n) == t
		elseif how == "start" then hit = #w >= n + M.MIN_STEM and w:sub(1, n) == t
		elseif how == "word" then hit = w == t end
		if hit and not vetoed(w, rule.veto) then return true end
	end
	return false
end

--- The site tags of a name for classifier `cls`: { [tag] = strength } or nil (plain: no rule matched / no classifier).
function M.classify(name, cls)
	local set = cls and M.RULESET[cls] and M.RULES[M.RULESET[cls]] or nil
	if set == nil or type(name) ~= "string" or name == "" then return nil end
	local raw = name
	if cls == "ja" then
		for _, s in ipairs(JA_SUFFIX) do
			if #raw > #s and raw:sub(-#s) == s then
				raw = raw:sub(1, #raw - #s)
				break
			end
		end
	end
	local lower = M.lower(raw)
	local ws = words(lower)
	local tags = nil
	for _, rule in ipairs(set) do
		if ruleHits(rule, raw, lower, ws) then
			tags = tags or {}
			for tag, w in pairs(rule[3]) do
				if (tags[tag] or 0) < w then tags[tag] = w end
			end
		end
	end
	return tags
end

--- "coast:1.00,river:0.40" (tags in M.TAGS order), "-" for none.
function M.tagText(tags)
	if tags == nil then return "-" end
	local parts = {}
	for _, t in ipairs(M.TAGS) do
		if tags[t] then parts[#parts + 1] = string.format("%s:%.2f", t, tags[t]) end
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

---------------------------------------------------------------------------
-- Pool: one list classified (sliced: M.classifyStep)

--- A new pool from a list of names (strings; others and duplicates dropped; at most MAX_POOL).
function M.newPool(list, cls)
	local p = { names = {}, index = {}, tags = {}, cls = cls, cursor = 1, done = false }
	if type(list) == "table" then
		for i = 1, math.min(#list, M.MAX_POOL) do
			local n = list[i]
			if type(n) == "string" and n ~= "" and p.index[n] == nil then
				p.names[#p.names + 1] = n
				p.index[n] = #p.names
			end
		end
	end
	return p
end

--- Classifies up to `count` more names (all when nil). Returns true when the whole pool is done (buckets built).
function M.classifyStep(p, count)
	local last = #p.names
	if count ~= nil then last = math.min(last, p.cursor + math.max(1, count) - 1) end
	p.cues = p.cues or {}
	for i = p.cursor, last do
		p.tags[i] = M.classify(p.names[i], p.cls)
		p.cues[i] = NW.cuesOf(p.names[i], p.cls)
	end
	p.cursor = last + 1
	if p.cursor <= #p.names then return false end
	if not p.done then M.buildBuckets(p) end
	return true
end

--- Tag buckets (tag -> name indices, list order), counts, the plain list (no tags, or only plain / market).
function M.buildBuckets(p)
	p.buckets, p.counts, p.plainList = {}, {}, {}
	p.tagged = 0
	for _, t in ipairs(M.TAGS) do
		p.buckets[t] = {}
		p.counts[t] = 0
	end
	for i = 1, #p.names do
		local tg = p.tags[i]
		local real = false
		if tg then
			for t, w in pairs(tg) do
				if w >= M.MIN_TAG then
					local b = p.buckets[t]
					b[#b + 1] = i
					p.counts[t] = p.counts[t] + 1
				end
				if t ~= "plain" and t ~= "market" then real = true end
			end
		end
		if real then p.tagged = p.tagged + 1 else p.plainList[#p.plainList + 1] = i end
	end
	-- cue buckets (2026-10-14): names saying a map cue ("North ...", "... Forks"), list order
	p.cueBuckets, p.cueCounts = {}, {}
	for _, c in ipairs(NW.CUE_TAGS) do p.cueBuckets[c], p.cueCounts[c] = {}, 0 end
	for i = 1, #p.names do
		for c, v in pairs((p.cues and p.cues[i]) or {}) do
			if v >= M.MIN_TAG and p.cueBuckets[c] then
				local b = p.cueBuckets[c]
				b[#b + 1] = i
				p.cueCounts[c] = p.cueCounts[c] + 1
			end
		end
	end
	for _, c in ipairs(NW.CUE_TAGS) do table.sort(p.cueBuckets[c]) end
	-- (bucket order: list order; pairs() above only adds within one name, so each bucket is ascending)
	for _, t in ipairs(M.TAGS) do table.sort(p.buckets[t]) end
	p.done = true
	return p
end

--- Is the pool worth using? true, or false and why ("noTags").
function M.usable(p)
	local n = #p.names
	if n == 0 then return false, "emptyList" end
	if (p.tagged or 0) < M.USABLE_MIN or (p.tagged or 0) < M.USABLE_SHARE * n then return false, "noTags" end
	return true, nil
end

--- NAMES field `tags`: "coast:12,river:40,..." (tags in M.TAGS order with at least one name).
function M.countsText(p)
	local parts = {}
	for _, t in ipairs(M.TAGS) do
		local c = p.counts and p.counts[t] or 0
		if c > 0 then parts[#parts + 1] = t .. ":" .. c end
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

---------------------------------------------------------------------------
-- Town tags from the site

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

--- A town's site tags. info = { feat = ot_site.features, stats = ot_terrain.stats, wide = ot_terrain.wide, forestShare
--- (0..1 or nil), big = bool }. Returns ranked { {tag, w}, ... } (w >= TOWN_TAG_MIN, at most MAX_TOWN_TAGS) and the
--- weight map { [tag] = w }.
function M.townTags(info)
	info = info or {}
	local f = info.feat or {}
	local st = info.stats or {}
	local wide = info.wide or {}
	local w = {}
	local function put(t, v) if v and v > (w[t] or 0) then w[t] = math.min(1, v) end end
	local water = st.water
	local wetWide = wide.water or 0
	local river = (f.river or 0) > 0 or (water ~= nil and water.kind == "river")
	if river then
		put("river", 1)
		put("ford", 0.8)
		put("bridge", 0.8)
		if wetWide >= 0.12 or (f.coast or 0) >= 0.3 then
			put("estuary", 0.9)
			put("coast", 0.5)
		end
	end
	local c = f.coast or 0
	local body = f.body
	if c > 0 then
		if body == "lake" then put("lake", math.max(c, 0.5))
		elseif body == "pond" then put("lake", 0.5)
		else put("coast", c) end
	elseif water and water.kind == "coast" and body == "pond" then
		put("lake", 0.5)
	end
	if (f.shore or 0) > 0 then
		if body == "lake" then put("lake", 1) else put("coast", 1) end
	end
	if f.island then put("island", 1) end
	if st.spit then put("headland", 0.9) end
	if c >= 0.3 and (wide.waterDirs or 0) >= 7 and not f.island then put("headland", 0.5) end
	local cl = st.cliff
	if cl and tonumber(cl.h) and tonumber(cl.d) and cl.h >= 6 and cl.d <= 700 then put("cliff", clamp((cl.h - 4) / 14, 0.3, 1)) end
	local rough = f.rough or 0
	if rough >= 0.3 then put("hill", rough) end
	local dr = st.dirRelief
	local slope = st.meanSlope or 0
	if dr and dr.ridge and slope > 0.02 then put("hill", 0.9) end
	local rel = st.relief
	if rel and tonumber(rel.grade) and rel.grade >= 0.03 then put("hill", clamp(rel.grade / 0.08, 0.3, 0.8)) end
	if dr and dr.valley and slope > 0.02 then put("valley", 1) end
	if (f.floor or 0) >= 0.6 and (wide.sd or 0) >= 15 then put("valley", 0.6) end
	local fs = tonumber(info.forestShare)
	if fs and fs >= 0.08 then put("forest", clamp((fs - 0.04) / 0.3, 0.3, 1)) end
	if (f.floor or 0) >= 0.85 and slope < 0.012 and (river or (wetWide >= 0.05 and wetWide <= 0.6)) then
		put("marsh", (wide.range or 99) < 15 and 0.8 or 0.6)
	end
	if (f.open or 0) > 0 then put("plain", f.open) end
	if info.big then
		put("market", 0.8)
		put("plain", 0.5)
	end
	-- (2026-10-14: the map survey's cues, ot_mapshape.townCues, in the classifier's coarse tags)
	local cw = type(info.cue) == "table" and info.cue.w or nil
	if cw then
		for t, list in pairs(M.CUE_COARSE) do
			for _, e in ipairs(list) do if cw[e[1]] then put(t, cw[e[1]] * e[2]) end end
		end
	end
	local ranked = {}
	for _, t in ipairs(M.TAGS) do
		if (w[t] or 0) >= M.TOWN_TAG_MIN then ranked[#ranked + 1] = { t, w[t] } else w[t] = nil end
	end
	table.sort(ranked, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return M.TAG_INDEX[a[1]] < M.TAG_INDEX[b[1]]
	end)
	while #ranked > M.MAX_TOWN_TAGS do
		local r = table.remove(ranked)
		w[r[1]] = nil
	end
	return ranked, w
end

-- survey cue tag -> coarse tag (weight factor)
M.CUE_COARSE = { river = { { "confluence", 0.9 }, { "falls", 0.8 }, { "bend", 0.6 }, { "twin", 0.8 } },
	estuary = { { "mouth", 0.9 } }, lake = { { "biglake", 1 } }, hill = { { "peak", 0.9 }, { "summit", 0.9 },
	{ "divide", 0.8 }, { "range", 0.6 } }, valley = { { "mainvalley", 0.7 } }, coast = { { "bay", 0.8 }, { "bigbay", 0.9 },
	{ "narrows", 0.7 } }, headland = { { "headland", 0.9 }, { "isthmus", 0.7 } } }

--- A town's cues in ot_namewords' cue terms from the survey's (ot_mapshape.townCues): { [cue] = w } or nil.
function M.townCueTags(cue)
	local w = type(cue) == "table" and cue.w or nil
	if w == nil then return nil end
	local out = {}
	local function put(c, v) if v and v > (out[c] or 0) then out[c] = v end end
	for _, c in ipairs({ "north", "south", "east", "west", "central", "upper", "lower", "falls", "bend", "summit", "divide",
		"peak", "mouth", "narrows", "twin" }) do put(c, w[c]) end
	put("fork", w.confluence)
	put("bay", w.bay); put("bay", w.bigbay)
	put("valley", w.mainvalley)
	put("gap", (w.range and w.summit) and 0.5 or nil)
	return out
end

M.CUE_K = 0.8             -- a name cue the town has: + strength x weight x this x CUE_W (default 1)
-- (the specific river / relief cues count more than the compass: "Grand Forks" at the fork beats any river name; a
-- compass word is a preference among fitting names, not a reason of its own to rename a town)
M.CUE_W = { fork = 1.6, falls = 1.6, mouth = 1.4, bend = 1.4, gap = 1.4, summit = 1.3, divide = 1.6, peak = 1.4,
	narrows = 1.6, twin = 1.4, central = 0.3, north = 0.45, south = 0.45, east = 0.45, west = 0.45, upper = 0.7,
	lower = 0.7 }
-- a name cue the town lacks costs its strength x this (the survey ran)
M.CUE_CONTRA = { north = 0.8, south = 0.8, east = 0.8, west = 0.8, central = 0.4, upper = 0.4, lower = 0.4, fork = 0.6,
	falls = 0.6, bend = 0.6, gap = 0.6, summit = 0.5, divide = 0.6, peak = 0.6, mouth = 0.6, narrows = 0.6, twin = 0.5,
	bay = 0.2, valley = 0.2 }

--- The cue part of a name's score: nameCues (ot_namewords.cuesOf), townCues (M.townCueTags) or nil (no survey: 0).
function M.cueScore(nameCues, townCues)
	if nameCues == nil or townCues == nil then return 0 end
	local s = 0
	for _, c in ipairs(NW.CUE_TAGS) do
		local v = nameCues[c]
		if v then
			local tc = townCues[c]
			if tc then s = s + M.CUE_K * (M.CUE_W[c] or 1) * v * tc else s = s - (M.CUE_CONTRA[c] or 0.5) * v end
		end
	end
	return s
end

--- "coast:0.80,hill:0.50" from a ranked list, "-" when empty.
function M.rankedText(ranked)
	local parts = {}
	for i, r in ipairs(ranked or {}) do parts[i] = string.format("%s:%.2f", r[1], r[2]) end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- How well name tags fit a town's tag weights: matched strength x weight, minus CONTRA x strength for each name tag the
--- town lacks (a match on a rare tag of the pool, `counts`, scores RARE_BONUS more). nil tags (a plain name): 0.
function M.score(nameTags, weights, counts)
	if nameTags == nil then return 0 end
	local s = 0
	for _, t in ipairs(M.TAGS) do
		local wn = nameTags[t]
		if wn then
			local wt = weights[t]
			if wt then
				local rare = counts and t ~= "plain" and t ~= "market" and (counts[t] or 0) > 0 and counts[t] <= M.RARE_COUNT
				s = s + wn * wt * (rare and (1 + M.RARE_BONUS) or 1)
			else s = s - wn * (M.CONTRA[t] or 0.5) end
		end
	end
	return s
end

---------------------------------------------------------------------------
-- Assignment

--- The composed satellite name of `parent` for classifier cls and seed, or nil (no template, a long or multi-word
--- parent name).
function M.compose(parent, cls, seed)
	local tpl = M.SAT[cls or ""]
	if tpl == nil or type(parent) ~= "string" or parent == "" then return nil end
	if #parent > M.SAT_MAX_PARENT_LEN or parent:find("[%s%-]") then return nil end
	local i = 1 + math.floor(rng.unit(seed or 1, "satTpl", parent) * #tpl)
	if i > #tpl then i = #tpl end
	local out = string.format(tpl[i], parent)
	if #out > M.MAX_NAME_LEN then return nil end
	return out
end

local function walk(list, start, maxN, fn)
	local n = #list
	if n == 0 then return nil end
	for k = 0, math.min(n, maxN) - 1 do
		local i = list[((start + k) % n) + 1]
		if fn(i) then return i end
	end
	return nil
end

--- Which towns are big (market / plain names fit): target capacity >= BIG_CAP, or among the map's biggest BIG_SHARE
--- (at least one) and 1.5 x the median. towns = { {id, cap} }. Returns { [id] = true }.
function M.bigTowns(towns)
	local caps = {}
	for _, t in ipairs(towns) do caps[#caps + 1] = tonumber(t.cap) or 0 end
	table.sort(caps)
	local out = {}
	if #caps == 0 then return out end
	local med = caps[math.max(1, math.floor((#caps + 1) / 2))]
	local k = math.max(1, math.floor(#caps * M.BIG_SHARE + 0.5))
	local cut = caps[#caps - k + 1]
	for _, t in ipairs(towns) do
		local c = tonumber(t.cap) or 0
		if c >= M.BIG_CAP or (c >= cut and c >= 1.5 * med and c > 0) then out[t.id] = true end
	end
	return out
end

--- Gives every town a name. towns = { { id, name (current), x, y, cap, ranked, weights, character, cues (M.townCueTags or
--- nil) } } (at most MAX_TOWNS looked at); p = a classified pool; o = { seed, reserved = { [name] = true } (other names
--- to avoid), sat = false to skip composed names, budget = false (no word budget), rarity = false }. Returns results (one
--- per town, input order: { id, old, new, match, score, tags }) and stats { renamed, kept, plain, random, satellite,
--- notDrawn, none, clean, budget (ot_namewords), rarity }.
--- match: "tag:<tag>" / "cue:<cue>" (a landscape fit), "kept" (the game's name fits as well), "clean" (the game's name
--- without its list disambiguator), "plain" (a plain name for a site its game name contradicted), "random" (any unused
--- name, last resort), "satellite" (composed), "notDrawn" (its name is not from this list: player-renamed or done),
--- "none" (nothing left).
function M.assign(towns, p, o)
	o = o or {}
	local seed = tonumber(o.seed) or 1
	local used = {}
	for n in pairs(o.reserved or {}) do used[n] = true end
	local list = {}
	for i = 1, math.min(#towns, M.MAX_TOWNS) do
		local t = towns[i]
		list[#list + 1] = t
		if type(t.name) == "string" then used[t.name] = true end
	end
	-- (Landscape names: list names repeat whole words too, "North Plainfield" / "South Plainfield": words on)
	local B = (o.budget ~= false) and NW.newBudget(p.cls, #list, { words = true }) or nil
	-- (2026-10-14: a tag most towns read weighs little)
	local wmaps = {}
	for i, t in ipairs(list) do wmaps[i] = t.weights or {} end
	local rar = (o.rarity ~= false) and NW.rarity(wmaps) or {}
	local res, byId = {}, {}
	for i, t in ipairs(list) do
		res[i] = { id = t.id, old = t.name, new = t.name, match = "kept", score = 0, tags = t.ranked }
		byId[t.id] = res[i]
	end
	local stats = { renamed = 0, kept = 0, plain = 0, random = 0, satellite = 0, notDrawn = 0, none = 0, fit = 0, clean = 0 }
	-- the names that stay (not from this list): their words count first
	for _, t in ipairs(list) do
		if p.index[t.name or ""] == nil and type(t.name) == "string" then NW.add(B, t.name, t.x, t.y) end
	end
	-- order: character towns first, then by the rarity of the best tag the pool has names for, then id
	local order = {}
	for i, t in ipairs(list) do
		local rare = math.huge
		for _, r in ipairs(t.ranked or {}) do
			if r[2] >= M.MIN_TAG then
				local c = p.counts and p.counts[r[1]] or 0
				if c > 0 and c < rare then rare = c end
			end
		end
		order[#order + 1] = { i = i, ch = t.character and 0 or 1, rare = rare, id = tonumber(t.id) or 0 }
	end
	table.sort(order, function(a, b)
		if a.ch ~= b.ch then return a.ch < b.ch end
		if a.rare ~= b.rare then return a.rare < b.rare end
		return a.id < b.id
	end)
	-- (per pool name: its clean form and its words, read once: the walks look at up to MAX_CAND names per tag and town)
	local dispC, keyC = {}, {}
	local function disp(idx)
		local d = dispC[idx]
		if d == nil then d = NW.clean(p.names[idx]); dispC[idx] = d end
		return d
	end
	local function keysOf(idx)
		local k = keyC[idx]
		if k == nil then k = B and NW.budgetKeys(B, disp(idx)) or {}; keyC[idx] = k end
		return k
	end
	local function free(idx, t)
		local n = p.names[idx]
		if used[n] or used[disp(idx)] then return false end
		return NW.allow(B, disp(idx), t.x, t.y, nil, keysOf(idx))
	end
	local function take(r, idx, match, sc, t)
		local n = p.names[idx]
		local d = disp(idx)
		used[n], used[d] = true, true
		r.new, r.match, r.score = d, match, sc
		NW.add(B, d, t.x, t.y, nil, keysOf(idx))
	end
	local function scoreOf(idx, wts, t)
		return M.score(p.tags[idx], wts, p.counts) + M.cueScore(p.cues and p.cues[idx], t.cues)
	end
	for _, od in ipairs(order) do
		local t, r = list[od.i], res[od.i]
		local wts = NW.applyRarity(t.weights or {}, rar)
		local curIdx = p.index[t.name or ""]
		if curIdx == nil then
			r.match = "notDrawn"
		else
			local curScore = scoreOf(curIdx, wts, t)
			r.score = curScore
			local curName = disp(curIdx)
			local curOk = NW.check(B, curName, t.x, t.y)
			local best, bestS, bestTag = nil, -math.huge, nil
			local function walkBucket(b, label)
				if b == nil or #b == 0 then return end
				local start = rng.hash(seed, "names", t.id, label) % #b
				local n = math.min(#b, M.MAX_CAND)
				for k = 0, n - 1 do
					local idx = b[((start + k) % #b) + 1]
					if idx ~= curIdx and free(idx, t) then
						local sc = scoreOf(idx, wts, t) + rng.unit(seed, "jit", t.id, idx) * 0.01
						if sc > bestS then best, bestS, bestTag = idx, sc, label end
					end
				end
			end
			for _, rt in ipairs(t.ranked or {}) do
				local tag = rt[1]
				local tw = wts[tag] or rt[2]
				-- (plain / market are no landscape fit: a town whose game name doesn't contradict its site keeps it)
				if tw >= M.MIN_TAG and tag ~= "plain" and tag ~= "market" then walkBucket(p.buckets[tag], "tag:" .. tag) end
			end
			-- names that carry the town's map cues ("North ...", "... Forks")
			for _, c in ipairs(NW.CUE_TAGS) do
				if t.cues and (t.cues[c] or 0) >= M.MIN_TAG and p.cueBuckets then walkBucket(p.cueBuckets[c], "cue:" .. c) end
			end
			if best and bestS >= M.MIN_MATCH and (bestS > curScore + M.KEEP_EPS or not curOk) then
				take(r, best, bestTag, bestS, t)
			elseif curScore >= -M.KEEP_TOL and curOk then
				r.match = curName ~= t.name and "clean" or "kept"
				r.new = curName
				used[curName] = true
				NW.add(B, curName, t.x, t.y)
			else
				-- the game's name contradicts the site (or breaks the word budget): a plain name that doesn't, else any
				-- unused one
				local start = rng.hash(seed, "plain", t.id)
				local idx = walk(p.plainList or {}, start, M.MAX_WALK, function(i)
					return free(i, t) and M.score(p.tags[i], wts) >= 0 and M.cueScore(p.cues and p.cues[i], t.cues) >= 0
				end)
				if idx then take(r, idx, "plain", M.score(p.tags[idx], wts), t)
				else
					local all = {}
					for i = 1, math.min(#p.names, M.MAX_WALK) do all[i] = (start + i) % #p.names + 1 end
					idx = walk(all, 0, M.MAX_WALK, function(i) return free(i, t) end)
					if idx then take(r, idx, "random", M.score(p.tags[idx], wts), t)
					elseif curOk or not used[curName] then
						r.match, r.new = "kept", curName
						NW.add(B, curName, t.x, t.y)
					else r.match = "none" end
				end
			end
		end
	end
	-- satellites / twins: a small town next to a much bigger one, without a landscape fit of its own
	if o.sat ~= false then
		local parents = {}
		for i, t in ipairs(list) do
			local r = res[i]
			if not t.character and (r.match == "kept" or r.match == "clean" or r.match == "plain" or r.match == "random") and tonumber(t.x) then
				local best, bd = nil, M.SAT_NEAR
				for j, q in ipairs(list) do
					if j ~= i and tonumber(q.x) and (tonumber(q.cap) or 0) >= M.SAT_RATIO * math.max(1, tonumber(t.cap) or 0) then
						local d = math.sqrt((q.x - t.x) ^ 2 + (q.y - t.y) ^ 2)
						if d <= bd then best, bd = j, d end
					end
				end
				if best and not parents[best] and res[best].match ~= "satellite" and res[best].match ~= "notDrawn"
					and rng.unit(seed, "sat", t.id) < M.SAT_P then
					local nm = M.compose(res[best].new, p.cls, seed)
					-- (the satellite pays only for the words its parent's name doesn't carry)
					local pk = B and NW.budgetKeys(B, res[best].new) or {}
					if nm and not used[nm] and NW.allow(B, nm, t.x, t.y, pk) then
						used[nm] = true
						parents[best] = true
						NW.remove(B, r.new, t.x, t.y)
						NW.add(B, nm, t.x, t.y, pk)
						r.new, r.match, r.parent = nm, "satellite", list[best].id
					end
				end
			end
		end
	end
	for _, r in ipairs(res) do
		if r.match == "notDrawn" then stats.notDrawn = stats.notDrawn + 1
		elseif r.match == "none" then stats.none = stats.none + 1
		elseif r.new == r.old then stats.kept = stats.kept + 1
		else
			stats.renamed = stats.renamed + 1
			if r.match == "plain" then stats.plain = stats.plain + 1
			elseif r.match == "random" then stats.random = stats.random + 1
			elseif r.match == "satellite" then stats.satellite = stats.satellite + 1
			elseif r.match == "clean" or r.match == "kept" then stats.clean = stats.clean + 1
			else stats.fit = stats.fit + 1 end
		end
	end
	stats.budget, stats.rarity = B, rar
	return res, stats
end

--- Real names the assignment left unused, per landscape tag (district towns, ot_district, 2026-10-14): { [tag] = {
--- names } }, at most perTag (default 6) per tag, a seeded start in each bucket; used = { [name] = true } (every name
--- given or kept on the map).
M.RESERVE_TAGS = { "hill", "cliff", "coast", "headland", "lake", "bridge", "ford", "river", "valley", "forest" }
function M.reserve(p, used, seed, perTag)
	local out = {}
	if type(p) ~= "table" or p.buckets == nil then return out end
	perTag = perTag or 6
	used = used or {}
	for _, tag in ipairs(M.RESERVE_TAGS) do
		local b = p.buckets[tag]
		if b and #b > 0 then
			local list = {}
			local start = rng.hash(seed or 1, "reserve", tag) % #b
			for k = 0, math.min(#b, M.MAX_CAND) - 1 do
				local nm = NW.clean(p.names[b[((start + k) % #b) + 1]])
				if type(nm) == "string" and not used[nm] then
					list[#list + 1] = nm
					if #list >= perTag then break end
				end
			end
			out[tag] = list
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Industries: "<Town> <type>" follows the town's new name

--- The industry renames for town renames `renames` ({ [old] = new }). inds = { {id, name} } (at most MAX_INDUSTRIES);
--- townNames = every town's name before the renames (the longest town name that prefixes an industry's name decides:
--- "Bury St Edmunds Farm" belongs to "Bury St Edmunds", not to "Bury"). Returns { {id, old, new} }.
function M.industryRenames(inds, renames, townNames)
	local out = {}
	if type(inds) ~= "table" then return out end
	local names = {}
	for _, n in ipairs(townNames or {}) do if type(n) == "string" and n ~= "" then names[#names + 1] = n end end
	for k in pairs(renames or {}) do names[#names + 1] = k end
	for i = 1, math.min(#inds, M.MAX_INDUSTRIES) do
		local e = inds[i]
		local nm = e and e.name
		if type(nm) == "string" then
			local bestN = nil
			local bestLen = 0
			for _, tn in ipairs(names) do
				-- (2026-10-14: also the town name without its trailing blank, "Milford city " -> "Milford city Crop Farm")
				local tt = tn:gsub("%s+$", "")
				for _, cand in ipairs({ tn, tt }) do
					if #cand > 0 and #nm > #cand + 1 and nm:sub(1, #cand + 1) == cand .. " " and #cand > bestLen then
						bestN, bestLen = tn, #cand
					end
				end
			end
			local new = bestN and renames[bestN]
			if new and new ~= bestN then
				local rest = nm:sub(bestLen + 1):gsub("^%s+", " ")
				out[#out + 1] = { id = e.id, old = nm, new = new .. rest }
			end
		end
	end
	return out
end

--- The map seed for the assignment: from every town's id and position (rounded), order-independent.
function M.mapSeed(towns)
	local s = 0
	for i = 1, math.min(#towns, M.MAX_TOWNS) do
		local t = towns[i]
		s = (s + rng.hash("nameSeed", tonumber(t.id) or 0, math.floor(tonumber(t.x) or 0), math.floor(tonumber(t.y) or 0))) % 2147483647
	end
	return rng.hash("mapNames", s)
end

---------------------------------------------------------------------------
-- Landscape stop names (2026-10-13, follow-up). Streets have no names in TF3: a street name only shows as the default
-- name of a new Road Stop's station group (the next unused name of the list's streets.lua, whatever the street; docs/
-- findings/roads.md "Street names and Road Stops"). A new player Road Stop in a town gets a street-style name that fits
-- its spot instead: M.stopThemes ranks the spot's themes, M.pickStop takes the first unused name of the best theme, real
-- names from the list's own streets.lua that carry the theme's keywords first (M.STOP[cls][theme].keys, plain substring
-- of the lower-case name), then the theme's own names (M.STOP[cls][theme].names). Nothing fits / no theme: the game's
-- name stays.

M.STOP_THEMES = { "station", "shore", "river", "hill", "valley", "forest", "centre", "outskirts" }
M.STOP_STATION_M = 200    -- a rail station this close: the station forecourt
M.STOP_CENTRE_M = 220     -- this close to the town centre (or a quarter of its radius): the centre
M.STOP_OUT_F = 0.85       -- beyond this x the town's radius (and 600 m): the outskirts
M.STOP_OUT_M = 600
M.STOP_HILL_DZ = 12       -- m above the town centre: high ground ...
M.STOP_CREST_DZ = 8       -- ... or this much above its 200 m ring (a crest)
M.STOP_LOW_DZ = 10        -- m below the ring in a valley town: the valley floor
M.STOP_FOREST = 0.5       -- forest cover at the stop
M.MAX_STOP_CAND = 64

local function T(keys, names) return { keys = keys, names = names } end

M.STOP = {
	en = {
		station = T({ "station", "railway" }, { "Station Road", "Station Street", "Railway Street", "Station Approach" }),
		shore = T({ "quay", "harbour", "esplanade", "marine", "beach", "shore", "sea" }, { "Esplanade", "Marine Parade",
			"Harbour Road", "The Quay", "Seafront", "Beach Road", "Shore Road" }),
		river = T({ "bridge", "river", "mill", "water" }, { "Bridge Street", "Riverside", "Mill Lane", "River Road", "Waterside" }),
		hill = T({ "hill", "ridge", "rise", "heights", "highfield" }, { "Hill Road", "Overlook", "The Heights", "Highlands",
			"Ridge Road", "Summit Road", "Hillside" }),
		valley = T({ "dale", "vale", "valley", "bottom" }, { "Dale Road", "Vale Road", "Valley Road", "Bottom Lane" }),
		forest = T({ "wood", "grove", "forest" }, { "Woodland Way", "Forest Road", "Wood Lane", "Grove Road" }),
		centre = T({ "high street", "market", "main street" }, { "High Street", "Market Street", "Market Place", "Main Street" }),
		outskirts = T({ "green lane", "field", "meadow", "farm", "the green" }, { "Green Lane", "Field Lane", "Meadow Way",
			"Farm Road" }),
	},
	usa = {
		station = T({ "depot", "station", "railroad" }, { "Depot Street", "Station Street", "Railroad Avenue" }),
		shore = T({ "lake", "bay", "shore", "harbor", "beach" }, { "Bayshore Drive", "Harbor Drive", "Beach Boulevard",
			"Shore Road", "Waterfront Drive" }),
		river = T({ "river", "mill", "bridge" }, { "River Street", "Mill Street", "Bridge Street", "Riverside Drive" }),
		hill = T({ "hill", "ridge", "highland", "view", "summit", "overlook" }, { "Hill Street", "Overlook Drive",
			"Ridge Road", "Summit Avenue", "Heights Road" }),
		valley = T({ "valley", "spring" }, { "Valley Street", "Spring Street", "Hollow Road" }),
		forest = T({ "wood", "forest", "pine", "oak", "cedar", "spruce" }, { "Woodland Street", "Forest Street", "Pine Street" }),
		centre = T({ "main", "center", "central", "broadway" }, { "Main Street", "Center Street", "Market Street" }),
		outskirts = T({ "meadow", "sunset" }, { "Meadow Street", "Country Road", "Farm Road", "Prairie Lane" }),
	},
	de = {
		station = T({ "bahnhof" }, { "Bahnhofstrasse", "Am Bahnhof", "Bahnhofplatz" }),
		shore = T({ "strand", "hafen", "ufer", "seestr" }, { "Strandweg", "Hafenstrasse", "Am Kai", "Uferstrasse", "Seestrasse",
			"Strandpromenade" }),
		river = T({ "brücke", "brücken", "mühl", "bach", "fluss" }, { "Brückenstrasse", "Mühlenweg", "Am Fluss", "Uferweg" }),
		hill = T({ "berg", "höhe", "hang" }, { "Bergstrasse", "Am Hang", "Höhenweg", "Auf der Höhe", "Bergweg" }),
		valley = T({ "talstr", "talweg", "grund" }, { "Talstrasse", "Im Grund", "Talweg" }),
		forest = T({ "wald", "tannen", "buchen", "kiefern", "eichen" }, { "Waldweg", "Waldstrasse", "Am Waldrand" }),
		centre = T({ "markt", "haupt", "kirchplatz" }, { "Marktplatz", "Hauptstrasse", "Marktstrasse" }),
		outskirts = T({ "feld", "wiesen", "heide", "grüner" }, { "Feldweg", "Wiesenweg", "Grüner Weg" }),
	},
	fr = {
		station = T({ "gare" }, { "Rue de la Gare", "Avenue de la Gare", "Place de la Gare" }),
		shore = T({ "du port", "de la mer", "plage", "quai" }, { "Quai du Port", "Boulevard de la Mer", "Promenade de la Plage",
			"Rue du Port" }),
		river = T({ "pont", "moulin", "rivière" }, { "Quai de la Rivière", "Rue du Pont", "Rue du Moulin" }),
		hill = T({ "coteau", "belvédère", "hauts" }, { "Rue des Hauts", "Rue du Coteau", "Chemin du Belvédère", "Montée du Château" }),
		valley = T({ "vallon", "vallée" }, { "Rue du Vallon", "Chemin du Val" }),
		forest = T({ "bois", "forêt", "chênes" }, { "Chemin du Bois", "Rue de la Forêt", "Allée des Chênes" }),
		centre = T({ "grande rue", "grand-rue", "marché", "église" }, { "Grand-Rue", "Place du Marché", "Rue du Marché" }),
		outskirts = T({ "champs", "prés" }, { "Chemin des Champs", "Rue des Prés" }),
	},
	nl = {
		station = T({ "station", "spoor" }, { "Stationsweg", "Stationsstraat", "Spoorstraat" }),
		shore = T({ "strand", "haven", "kade", "dijk" }, { "Strandweg", "Havenstraat", "Kade", "Dijkweg" }),
		river = T({ "brug", "molen", "rivier" }, { "Brugstraat", "Molenweg", "Rivierweg", "Waterkant" }),
		hill = T({ "heuvel", "berg" }, { "Heuvelweg", "Bergweg", "Hoogstraat" }),
		valley = T({ "dal" }, { "Dalweg" }),
		forest = T({ "bos", "hout" }, { "Bosweg", "Boslaan", "Bosrand" }),
		centre = T({ "markt", "kerk", "dorps", "hoofd" }, { "Markt", "Kerkstraat", "Dorpsstraat" }),
		outskirts = T({ "veld", "weide", "polder" }, { "Veldweg", "Weideweg", "Polderweg" }),
	},
	sv = {
		station = T({ "station", "järnväg" }, { "Stationsvägen", "Stationsgatan", "Järnvägsgatan" }),
		shore = T({ "strand", "hamn", "kaj", "sjö" }, { "Strandvägen", "Hamngatan", "Kajen", "Sjövägen" }),
		river = T({ "brogatan", "kvarn", "älv" }, { "Brogatan", "Kvarnvägen", "Älvvägen" }),
		hill = T({ "backe", "åsväg", "bergsg", "höjd", "utsikt" }, { "Backen", "Åsvägen", "Bergsgatan", "Utsiktsvägen" }),
		valley = T({ "dalv", "dalg" }, { "Dalvägen", "Dalgatan" }),
		forest = T({ "skog", "granv", "tallv" }, { "Skogsvägen", "Skogsgatan", "Granvägen" }),
		centre = T({ "storgatan", "torg", "kyrk" }, { "Storgatan", "Torget", "Kyrkogatan" }),
		outskirts = T({ "äng", "åker", "gärde" }, { "Ängsvägen", "Åkervägen", "Gärdesvägen" }),
	},
	nb = {
		station = T({ "stasjon", "jernbane" }, { "Stasjonsveien", "Jernbanegata" }),
		shore = T({ "strand", "havn", "kai", "sjø", "brygg" }, { "Strandveien", "Havnegata", "Kaiveien", "Brygga" }),
		river = T({ "brugata", "elve", "mølle" }, { "Brugata", "Elveveien", "Møllevegen" }),
		hill = T({ "bakke", "åsv", "bergv", "utsikt" }, { "Bakken", "Åsveien", "Bergveien", "Utsikten" }),
		valley = T({ "dalv" }, { "Dalveien" }),
		forest = T({ "skog", "granv" }, { "Skogveien", "Granveien" }),
		centre = T({ "storgata", "torg", "kirke" }, { "Storgata", "Torget", "Kirkegata" }),
		outskirts = T({ "engv", "åker" }, { "Engveien", "Åkerveien" }),
	},
	it = {
		station = T({ "stazione" }, { "Via della Stazione", "Viale della Stazione", "Piazza della Stazione" }),
		shore = T({ "porto", "lungomare", "marina", "spiaggia" }, { "Lungomare", "Via del Porto", "Via della Marina" }),
		river = T({ "ponte", "mulino", "fiume" }, { "Lungofiume", "Via del Ponte", "Via del Mulino" }),
		hill = T({ "colle", "belvedere", "collina" }, { "Via del Colle", "Via Belvedere", "Via Panoramica" }),
		valley = T({ "valle" }, { "Via della Valle" }),
		forest = T({ "bosco", "pineta" }, { "Via del Bosco", "Via della Pineta" }),
		centre = T({ "corso", "mercato", "duomo" }, { "Corso Italia", "Piazza del Mercato", "Via Roma" }),
		outskirts = T({ "campi", "prati" }, { "Via dei Campi", "Via dei Prati" }),
	},
	es = {
		station = T({ "estación" }, { "Calle de la Estación", "Avenida de la Estación" }),
		shore = T({ "puerto", "del mar", "playa", "marítimo" }, { "Paseo Marítimo", "Calle del Puerto", "Avenida del Mar" }),
		river = T({ "río", "puente", "molino" }, { "Calle del Río", "Calle del Puente", "Calle del Molino" }),
		hill = T({ "cerro", "mirador", "loma" }, { "Calle del Cerro", "Calle Mirador", "Camino del Alto" }),
		valley = T({ "valle" }, { "Calle del Valle" }),
		forest = T({ "bosque", "pinar" }, { "Calle del Bosque", "Camino del Pinar" }),
		centre = T({ "mayor", "mercado" }, { "Calle Mayor", "Plaza Mayor", "Calle del Mercado" }),
		outskirts = T({ "campo", "eras" }, { "Camino de los Campos", "Calle de las Eras" }),
	},
	pt = {
		station = T({ "estação" }, { "Rua da Estação", "Avenida da Estação" }),
		shore = T({ "porto", "praia", "marginal", "cais" }, { "Avenida Marginal", "Rua do Porto", "Avenida da Praia" }),
		river = T({ "rio", "ponte", "moinho" }, { "Rua do Rio", "Rua da Ponte", "Rua do Moinho" }),
		hill = T({ "alto", "encosta", "miradouro" }, { "Rua do Alto", "Rua da Encosta", "Miradouro" }),
		valley = T({ "vale" }, { "Rua do Vale" }),
		forest = T({ "bosque", "pinhal" }, { "Rua do Bosque", "Rua do Pinhal" }),
		centre = T({ "direita", "mercado" }, { "Rua Direita", "Rua do Mercado", "Praça da República" }),
		outskirts = T({ "campos" }, { "Rua dos Campos", "Caminho Rural" }),
	},
	ja = {
		station = T({ "駅" }, { "駅前通り", "駅前" }), shore = T({ "海", "港", "浜" }, { "海岸通り", "港通り", "浜通り" }),
		river = T({ "川", "橋", "河" }, { "川端通り", "橋通り" }), hill = T({ "坂", "台", "山手" }, { "坂通り", "台町通り", "山手通り" }),
		valley = T({ "谷", "沢" }, { "谷町通り", "沢通り" }), forest = T({ "森", "松", "林" }, { "森通り", "松並木通り" }),
		centre = T({ "本町", "中央", "大手" }, { "本町通り", "中央通り", "大手通り" }), outskirts = T({ "田園", "野" }, { "田園通り" }),
	},
	ja_r = {
		station = T({ "eki" }, { "Ekimae-dōri" }), shore = T({ "kaigan", "minato", "hama" }, { "Kaigan-dōri", "Minato-dōri" }),
		river = T({ "kawa", "hashi" }, { "Kawabata-dōri", "Hashi-dōri" }), hill = T({ "saka", "yamate", "zaka" }, { "Saka-dōri", "Yamate-dōri" }),
		valley = T({ "tani" }, { "Tani-dōri" }), forest = T({ "mori", "matsu" }, { "Mori-dōri", "Matsu-dōri" }),
		centre = T({ "honmachi", "chūō", "ōte" }, { "Honmachi-dōri", "Chūō-dōri", "Ōte-dōri" }), outskirts = T({ "den'en" }, { "Den'en-dōri" }),
	},
	ru = {
		station = T({ "Вокзал", "вокзал" }, { "Вокзальная улица", "Привокзальная площадь" }),
		shore = T({ "Набережн", "Морск", "Портов" }, { "Набережная улица", "Морская улица", "Портовая улица" }),
		river = T({ "Речн", "Мост", "Мельнич" }, { "Речная улица", "Мостовая улица", "Мельничная улица" }),
		hill = T({ "Горн", "Нагорн" }, { "Нагорная улица", "Горная улица" }),
		valley = T({ "Долин" }, { "Долинная улица" }), forest = T({ "Лесн", "Соснов" }, { "Лесная улица", "Сосновая улица" }),
		centre = T({ "Центральн", "Рыночн" }, { "Центральная улица", "Рыночная площадь" }),
		outskirts = T({ "Полев", "Садов" }, { "Полевая улица", "Садовая улица" }),
	},
}

--- A stop's themes from its spot, ranked (the first that applies is the best). site = { station = m to the nearest rail
--- station or nil, wet = "shore" | "river" | nil (water beside the stop), dz = m above the town centre, ring = m above
--- its 200 m ring, valleyTown = bool, forest = cover 0..1 or nil, dist = m from the town centre, radius = the town's
--- radius (m) or nil }. Returns { theme, ... } (may be empty).
function M.stopThemes(site)
	site = site or {}
	local out = {}
	local function add(t) out[#out + 1] = t end
	if tonumber(site.station) and site.station <= M.STOP_STATION_M then add("station") end
	if site.wet == "shore" then add("shore") elseif site.wet == "river" then add("river") end
	local dz, ring = tonumber(site.dz) or 0, tonumber(site.ring) or 0
	if dz >= M.STOP_HILL_DZ or ring >= M.STOP_CREST_DZ then add("hill") end
	if site.valleyTown and ring <= -M.STOP_LOW_DZ then add("valley") end
	if tonumber(site.forest) and site.forest >= M.STOP_FOREST then add("forest") end
	local d = tonumber(site.dist)
	local r = tonumber(site.radius) or 0
	if d and d <= math.max(M.STOP_CENTRE_M, r * 0.25) then add("centre")
	elseif d and d >= math.max(M.STOP_OUT_M, r * M.STOP_OUT_F) then add("outskirts") end
	return out
end

--- The candidates of a theme for classifier cls: the street list's names holding a key (list order), then the theme's own
--- names; distinct, at most MAX_STOP_CAND. streets = the list's streets.lua (or nil).
function M.stopCandidates(cls, theme, streets)
	local th = M.STOP[cls or ""] and M.STOP[cls][theme]
	if th == nil then return {} end
	local out, seen = {}, {}
	local function add(n)
		if type(n) == "string" then n = n:gsub("^%s+", ""):gsub("%s+$", "") end
		if type(n) == "string" and n ~= "" and not seen[n] and #out < M.MAX_STOP_CAND then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	if type(streets) == "table" then
		for i = 1, math.min(#streets, M.MAX_POOL) do
			local n = streets[i]
			if type(n) == "string" then
				local low = M.lower(n)
				for _, k in ipairs(th.keys) do
					if low:find(k, 1, true) or n:find(k, 1, true) then add(n) break end
				end
			end
		end
	end
	for _, n in ipairs(th.names) do add(n) end
	return out
end

--- The stop name: the first candidate of the best theme not used in its town (a seeded start within the list's own names
--- would scatter them; list order keeps the real names first). used = { [name] = true }. Returns name, theme or nil.
function M.pickStop(cls, themes, streets, used, cache)
	used = used or {}
	for _, th in ipairs(themes or {}) do
		local key = tostring(cls) .. ":" .. th
		local c = cache and cache[key]
		if c == nil then
			c = M.stopCandidates(cls, th, streets)
			if cache then cache[key] = c end
		end
		for _, n in ipairs(c) do
			if not used[n] then return n, th end
		end
	end
	return nil, nil
end

return M
