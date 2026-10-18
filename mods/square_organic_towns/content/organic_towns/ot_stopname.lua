-- Organic Towns: unique, geographically relevant stop names (pure; 2026-10-13, run 2026-10-13_2113_sqot-dev).
--
-- User: "Are these bus stop names final? It seems like it's working, but there's only a pool of a few, so there's tons
-- of duplicates, which shouldn't happen. We need to be able to generate unique geographically relevant names." (32 test
-- stops: The Grove x6, Highfield Road x6, High Street x6, Green Lane x4, Esplanade x4.) The first version (ot_names
-- STOP) took the first unused name of a short per-theme list, unique per town only.
--
-- Now a stop's name is composed from what its spot offers, in the name list's language, and is unique on the whole map
-- (the driver passes every station group name on the map as `used`; a name is never given twice while any combination
-- of the stop's candidates is left):
--   * specific part (M.groups): the neighbour town the street heads toward ("Ferryhill Road", a stop past the town's
--     inner part whose bearing from the centre points at a town within TOWARD_MAX_M), works / quarries / farms within
--     IND_R ("Works Road", "Quarry Lane"), the trees of the town's forest read (species from the tree models' file
--     names, M.species; climate defaults without a read; willow / alder first by the water), the theme's own features
--     (mill / bridge / ford / weir on a river, harbour / anchor / pier on the shore, church / market / king near the
--     centre, prospect / beacon on a hill ...), the compass toward the stop from the centre ("North Road"), height
--     ("Upper ..." / "Top ..."), and the town's own name ("Haslemere Quay"; rivers and lakes have no readable names);
--   * generic part per theme (M.LANG[cls].gens): hill Hill / Rise / View / Heights / Brow / Crest / Ridge / Bank /
--     Overlook; shore Esplanade / Parade / Quay / Strand / Wharf ...; river Street / Lane / Road / Walk (+ Riverside,
--     Mill Lane ...); forest Grove / Copse / Wood / Chase / Glade; valley Dale / Bottom / Combe / Vale; centre Street /
--     Place / Square; outskirts Lane / Close / Drive / Way / Fields / End;
--   * per list language: en, usa (Dr / Ave / Rd / Overlook / Heights / Bayshore), de (compounds -weg / -strasse /
--     -höhe, "Am ..."), nl, sv, nb (compounds, "Norra ..."), fr / it / es / pt (generic + "de la ..." phrase, gendered
--     height adjective), ja / ja_r (concatenation), ru / ru_r (gendered adjective + noun).
--   * (2026-10-13, run 2026-10-13_2240_sqot-dev) the industry theme first for a stop within IND_R of an industry: the
--     industry's own short name ("Crop Farm Gate"), then its type's words ("Works Road", "Quarry Lane", "Brewery
--     Lane", "Foundry Street"; M.indKind: works / quarry / mine / farm / mill / brewery / timber); old field / farm
--     names (`fields`: "Longacre Lane", "Cowleaze Road"), landmarks (`marks`: "Chapel Street", "Smithy Lane"), a lake
--     shore's own words (`lake`), Old / New / Little / Great pairs (en);
--   * (2026-10-14, NEXT_PHASE_BRIEF 46) the bridge theme before every other for a stop on a bridge edge or just off
--     its end (M.bridgeCue, M.BRIDGE: "Avon Bridge", "Haslemere Bridge", "Old Bridge", "Bridge End", "Lahnbrücke" ...);
--   * (2026-10-14, NEXT_PHASE_BRIEF 49 "stop names' climate fit") the climate fit: site.climate (ot_climate.key, with
--     subarctic) drops the tree species the climate vetoes (M.treesFor) and every candidate with a word the climate
--     rules out (ot_climate.wordMisfit: no Oak / Birch / Pine on a tropical map, no Marsh / Fen / Meadow on a dry one,
--     no Palm in the subarctic); site.noLake (the map survey: no lake within LAKE_NEAR_M) drops the lake words
--     (ot_climate.lakeMisfit: no "Lakeside" on a map without lakes). The proper names in a candidate (the town, the
--     neighbour, the river / lake, the industry) are not checked, and the bridge names never (M.fits);
-- Order (2026-10-13, run 2240: every stop took a real list name, which the game hands to new stops too: "The Grove"
-- twice): the composed names of every theme first (by relevance, site-specific parts first, a seeded jitter per stop so
-- neighbouring stops of one theme vary), then the stand-alone names, then the real street names of the list holding
-- the theme's keys (ot_names.stopCandidates), each only while unused on the map. No fallback themes: no unique fitting
-- name leaves the game's (`why=noUnique`). New stations beside an industry: M.stationName ("<Town> Works", "<Industry>
-- Halt").
--
-- Names only (strings on station groups); nothing saved. Every loop is bounded by the data tables and MAX_CAND.
-- Plain Lua, pre-5.3.

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local NM = ug_require "square_organic_towns::/organic_towns/ot_names.lua"
local CL = ug_require "square_organic_towns::/organic_towns/ot_climate.lua"

local M = {}

M.ON = true
M.MAX_CAND = 4000        -- candidates per stop at most
M.MAX_LEN = 48           -- bytes
M.TOWARD_DEG = 32        -- a neighbour town within this of the stop's bearing from the centre ...
M.TOWARD_MAX_M = 8000    -- ... and this near: the street heads toward it
M.TOWARD_MIN_M = 250     -- ... only for stops this far out at least (and TOWARD_MIN_F x the town's radius)
M.TOWARD_MIN_F = 0.35
M.COMPASS_MIN_M = 250    -- compass words only this far from the centre
M.IND_R = 350            -- m: an industry this near names the stop ("Works Road")
M.HIGH_DZ = 12           -- m above the centre (or STOP_CREST_DZ above the ring): "Upper ..."
M.JITTER = 2.0           -- seeded rank jitter per stop and name
M.MOD_RANK = 6           -- the size / age modifiers' names ("Old ...", "Малая ...") come this much later

---------------------------------------------------------------------------
-- tree species from the tree models (base/content/assets/vegetation/trees/<id>/<id>.mdl, 2026-10-13); the generic
-- broadleaf / conifer models don't say the species: a fixed spread by their number

M.SPECIES_PATTERNS = {
	{ "shgl_oak", "oak" }, { "hzl_", "hazel" }, { "eldrbr", "elder" }, { "apple", "apple" }, { "lmbrd_ppl", "poplar" },
	{ "mt_mpl", "maple" }, { "sgr_mpl", "maple" }, { "eu_lnd", "lime" }, { "sct_pn", "pine" }, { "brsc_pn", "pine" },
	{ "plm", "palm" }, { "aca_", "acacia" }, { "lmn_tr", "lemon" }, { "swamp_tree", "cypress" }, { "willow", "willow" },
}
M.BROADLEAF = { "oak", "ash", "beech", "elm", "birch", "oak", "beech", "ash" }
M.CONIFER = { "pine", "fir", "spruce", "larch", "pine", "fir" }

--- The species id of a tree model file name (or nil: shrubs, cacti, unknown).
function M.species(file)
	local s = string.lower(tostring(file or ""))
	if s == "" then return nil end
	for _, p in ipairs(M.SPECIES_PATTERNS) do
		if s:find(p[1], 1, true) then return p[2] end
	end
	local b = s:match("brleaf_(%d+)")
	if b then return M.BROADLEAF[(tonumber(b) - 1) % #M.BROADLEAF + 1] end
	local c = s:match("confr_(%d+)")
	if c then return M.CONIFER[(tonumber(c) - 1) % #M.CONIFER + 1] end
	return nil
end

M.CLIMATE_TREES = {
	temperate = { "oak", "ash", "beech", "birch", "hazel", "elm", "pine", "lime" },
	dry = { "pine", "olive", "cypress", "oak", "almond", "lemon" },
	tropical = { "palm", "acacia", "lemon", "cypress" },
	subarctic = { "spruce", "pine", "birch", "larch", "fir", "alder", "willow" },
	ja = { "pine", "cedar", "cherry", "maple", "oak", "willow" },
}
M.WATER_TREES = { "willow", "alder", "poplar" }

--- The climate key of a climate path ("::/climates/dry/dry.clima" -> "dry"; tropical, subarctic), temperate by
--- default (ot_climate.key).
function M.climateKey(path)
	return CL.key(path)
end

--- Does climate key ck rule out tree species sp? (its tag veto, or its English word: no oak on a tropical map, no
--- willow on a dry one, no palm / lemon in the subarctic)
function M.treeMisfit(sp, ck)
	return CL.vetoTag(ck, sp) or CL.wordMisfit(sp, ck, "en") ~= nil
end

--- Ranked species for a stop: the town's read (tally { [species] = trees }, biggest first) or the climate's defaults;
--- the water trees first by the water; species the climate rules out left out (M.treeMisfit). Returns { species, ... }
--- (distinct, at most 8).
function M.treesFor(tally, climate, wet, cls)
	local out, seen = {}, {}
	local ck = M.climateKey(climate)
	local function add(sp)
		if sp and not seen[sp] and #out < 8 and not M.treeMisfit(sp, ck) then seen[sp] = true; out[#out + 1] = sp end
	end
	if wet then for _, sp in ipairs(M.WATER_TREES) do add(sp) end end
	local list = {}
	for sp, n in pairs(tally or {}) do if type(n) == "number" and n > 0 then list[#list + 1] = { sp, n } end end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return a[1] < b[1]
	end)
	for _, e in ipairs(list) do add(e[1]) end
	local key = (cls == "ja" or cls == "ja_r") and "ja" or ck
	for _, sp in ipairs(M.CLIMATE_TREES[key] or M.CLIMATE_TREES.temperate) do add(sp) end
	-- (a ja list on a tropical / subarctic map: its own defaults may all be ruled out, the climate's then)
	if #out == 0 then for _, sp in ipairs(M.CLIMATE_TREES[ck] or {}) do add(sp) end end
	return out
end

--- The kind of an industry file name near a stop (the industry theme's words, M.LANG[cls].ind): "quarry" | "mine" |
--- "farm" | "timber" | "mill" | "brewery" | "works". (2026-10-13: steel mills are works, "Foundry Street", not "Mill Road")
function M.indKind(file)
	local s = string.lower(tostring(file or ""))
	local function has(k) return s:find(k, 1, true) ~= nil end
	if has("coal_mine") or has("iron_ore") or has("mine") or has("colliery") then return "mine" end
	if has("quarry") or has("_pit") or has("clay") or has("gravel") then return "quarry" end
	if has("brewery") or has("distillery") or has("winery") or has("malt") then return "brewery" end
	if has("industries/forest") or has("forestry") or has("lumber") or has("saw") then return "timber" end
	if has("farm") or has("orchard") or has("ranch") or has("fishing") or has("plantation") then return "farm" end
	if has("steel") or has("smelter") then return "works" end
	if has("mill") or has("food") then return "mill" end
	return "works"
end

--- The industry's own name without its town's ("Budleigh Salterton Crop Farm" -> "Crop Farm"): the longest town
--- name of towns (a list) that prefixes it; nil when nothing is left or it is long (> 24 bytes).
function M.indShort(name, towns)
	if type(name) ~= "string" or name == "" then return nil end
	local best = 0
	for _, t in ipairs(towns or {}) do
		if type(t) == "string" and #t > best and #name > #t + 1 and name:sub(1, #t + 1) == t .. " " then best = #t end
	end
	local rest = best > 0 and name:sub(best + 2) or name
	if rest == "" or #rest > 24 then return nil end
	return rest
end

--- The compass key toward (x, y) from (cx, cy): "n" | "e" | "s" | "w" (x east, y north).
function M.compass(cx, cy, x, y)
	local dx, dy = x - cx, y - cy
	if math.abs(dx) >= math.abs(dy) then return dx >= 0 and "e" or "w" end
	return dy >= 0 and "n" or "s"
end

---------------------------------------------------------------------------
-- language data. join: "space" (spec gen), "compound" (stem .. suffix for "-x" gens, "spec gen" otherwise; sep words
-- (compass / height in sv / nb) stand apart with the gen's indefinite form), "romance" (gen .. " " .. phrase; height
-- = the gen's gendered adjective), "adj" (ru: the spec's gendered adjective .. " " .. gen), "concat" (ja).

M.LANG = {}

M.LANG.en = { join = "space", own = true,
	gens = {
		station = { "Road", "Street", "Approach", "Terrace", "Yard", "Lane", "Square" },
		shore = { "Esplanade", "Parade", "Quay", "Strand", "Wharf", "Road", "Lane", "Walk", "Terrace", "Promenade" },
		river = { "Street", "Lane", "Road", "Walk", "Row", "Close" },
		hill = { "Hill", "Rise", "View", "Heights", "Brow", "Crest", "Ridge", "Bank", "Overlook" },
		valley = { "Dale", "Bottom", "Combe", "Vale", "Hollow", "Dene" },
		forest = { "Grove", "Copse", "Wood", "Chase", "Glade", "Spinney", "Coppice", "Walk" },
		centre = { "Street", "Place", "Square", "Row", "Lane", "Yard", "Walk" },
		outskirts = { "Lane", "Close", "Drive", "Way", "Fields", "End", "Road", "Gardens" } },
	solos = {
		station = { "Station Road", "Station Approach", "Railway Street" },
		shore = { "The Esplanade", "The Strand", "The Quay", "Marine Parade", "Seafront", "Shore Road", "Sea Lane" },
		river = { "Riverside", "Waterside", "Bridge Street", "Mill Lane", "The Ford", "Weir Road" },
		hill = { "Hill Road", "The Heights", "Hillside", "Hilltop", "The Rise" },
		valley = { "Vale Road", "Dale Road", "Bottom Lane", "Valley Road" },
		forest = { "Woodland Way", "Wood Lane", "The Grove", "The Copse", "The Chase", "Forest Road" },
		centre = { "High Street", "Market Place", "The Square", "Market Square", "Church Street", "The Shambles" },
		outskirts = { "Green Lane", "The Green", "Field Lane", "Meadow Way" } },
	specs = {
		station = { "Station", "Railway", "Junction", "Goods", "Sidings", "Signal", "Platform" },
		shore = { "Harbour", "Sea", "Bay", "Beach", "Anchor", "Pier", "Marine", "Coastguard", "Shore", "Lighthouse" },
		river = { "Mill", "Bridge", "Ford", "Weir", "Ferry", "Lock", "River", "Water", "Kingfisher" },
		hill = { "Prospect", "Beacon", "Windmill", "Castle", "Church", "Summit", "Highfield", "Lookout" },
		valley = { "Mill", "Brook", "Spring", "Ford", "Well" },
		forest = { "Fox", "Deer", "Keeper's", "Hunter's", "Badger", "Owl" },
		centre = { "Market", "Church", "Chapel", "King", "Queen", "Castle", "Crown", "Union", "Abbey", "Bank", "Guildhall", "Cross" },
		outskirts = { "Farm", "Meadow", "Green", "Orchard", "Common", "Barn", "Field", "Windmill", "Pound", "Hedge" } },
	tree = { oak = "Oak", ash = "Ash", beech = "Beech", hazel = "Hazel", birch = "Birch", pine = "Pine", elm = "Elm",
		willow = "Willow", lime = "Lime", poplar = "Poplar", maple = "Maple", fir = "Fir", spruce = "Spruce", larch = "Larch",
		alder = "Alder", chestnut = "Chestnut", apple = "Apple", olive = "Olive", cypress = "Cypress", palm = "Palm",
		acacia = "Acacia", elder = "Elder", lemon = "Lemon", cedar = "Cedar", cherry = "Cherry", almond = "Almond" },
	ind = { works = { "Works", "Foundry", "Forge" }, quarry = { "Quarry", "Pit" }, farm = { "Farm", "Dairy" }, mill = { "Mill" } },
	compass = { n = "North", e = "East", s = "South", w = "West" },
	high = { "Upper", "Top" },
	mods = { "Old", "New" },
	toward = function(t) return { t .. " Road", t .. " Lane", "Old " .. t .. " Road" } end,
}

M.LANG.usa = { join = "space", own = true,
	gens = {
		station = { "St", "Ave", "Rd", "Plaza", "Way" },
		shore = { "Dr", "Blvd", "Rd", "Ave", "Way", "Walk", "Pkwy" },
		river = { "St", "Rd", "Dr", "Ave", "Ln", "Way" },
		hill = { "Heights", "Overlook", "Ridge", "Hill", "View", "Summit", "Crest", "Bluff", "Knoll" },
		valley = { "Hollow", "Glen", "Run", "Valley Rd", "Bottom Rd" },
		forest = { "Woods", "Grove", "Trail", "Ln", "Dr", "Ct" },
		centre = { "St", "Ave", "Plaza", "Sq", "Blvd" },
		outskirts = { "Rd", "Ln", "Dr", "Ct", "Way", "Pl", "Trail", "Pike" } },
	solos = {
		station = { "Depot Street", "Railroad Avenue", "Station Street" },
		shore = { "Bayshore Drive", "Harbor Drive", "Shore Road", "Beach Boulevard", "Waterfront Drive", "Lakeshore Drive" },
		river = { "Riverside Drive", "Mill Street", "Bridge Street", "River Road" },
		hill = { "Overlook Drive", "Summit Avenue", "Ridge Road", "Highland Avenue", "Hilltop Road" },
		valley = { "Valley Road", "Hollow Road", "Spring Street" },
		forest = { "Woodland Avenue", "Forest Drive", "Timber Lane" },
		centre = { "Main Street", "Center Street", "Market Street", "Broadway", "Courthouse Square" },
		outskirts = { "Country Road", "Farm Road", "Prairie Lane", "County Line Road", "Sunset Drive" } },
	specs = {
		station = { "Depot", "Railroad", "Station", "Junction", "Freight", "Signal", "Rail" },
		shore = { "Bayshore", "Harbor", "Lakeshore", "Beach", "Bay", "Dock", "Lighthouse", "Marina", "Pier", "Ocean" },
		river = { "River", "Mill", "Bridge", "Ferry", "Ford", "Dam", "Falls", "Creek", "Landing" },
		hill = { "Highland", "Summit", "Ridge", "Prospect", "Sunrise", "Vista", "Eagle", "Hilltop" },
		valley = { "Spring", "Creek", "Mill", "Brook", "Meadow" },
		forest = { "Timber", "Deer", "Fox", "Hickory", "Woodland", "Ranger" },
		centre = { "Main", "Center", "Market", "Court", "Church", "Union", "Liberty", "Franklin", "Washington", "Lincoln",
			"Jefferson", "Commerce" },
		outskirts = { "Farm", "Ranch", "Prairie", "Meadow", "Orchard", "Sunset", "County Line", "Barn", "Field", "Mill" } },
	tree = { oak = "Oak", ash = "Ash", beech = "Beech", hazel = "Hazel", birch = "Birch", pine = "Pine", elm = "Elm",
		willow = "Willow", lime = "Linden", poplar = "Poplar", maple = "Maple", fir = "Fir", spruce = "Spruce", larch = "Tamarack",
		alder = "Alder", chestnut = "Chestnut", apple = "Apple", olive = "Olive", cypress = "Cypress", palm = "Palm",
		acacia = "Acacia", elder = "Elder", lemon = "Lemon", cedar = "Cedar", cherry = "Cherry", almond = "Almond" },
	ind = { works = { "Foundry", "Factory", "Mill" }, quarry = { "Quarry", "Mine" }, farm = { "Farm", "Ranch", "Dairy" }, mill = { "Mill" } },
	compass = { n = "North", e = "East", s = "South", w = "West" },
	high = { "Upper", "High" },
	mods = { "Old", "New" },
	toward = function(t) return { t .. " Rd", t .. " Pike", "Old " .. t .. " Rd" } end,
}

-- German adjective of a town name ("Ulm" -> "Ulmer", "Tübingen" -> "Tübinger", "Halle" -> "Haller"); multi-word: nil
local function deAdj(t)
	if t:find("[%s%-]") then return nil end
	if t:sub(-5) == "ingen" then return t:sub(1, -3) .. "er" end
	if t:sub(-1) == "e" then return t .. "r" end
	return t .. "er"
end

M.LANG.de = { join = "compound",
	gens = {
		station = { "-strasse", "-platz", "-weg", "-allee", "-gasse", "-ring" },
		shore = { "-weg", "-strasse", "-promenade", "-damm", "-kai", "-ufer" },
		river = { "-weg", "-strasse", "-gasse", "-steg", "-ufer", "-graben" },
		hill = { "-höhe", "-berg", "-hang", "-blick", "-steig", "-ring" },
		valley = { "-tal", "-grund", "-aue", "-weg", "-wiese" },
		forest = { "-weg", "-hain", "-pfad", "-allee", "-steig", "-schlag" },
		centre = { "-strasse", "-platz", "-gasse", "-markt", "-hof" },
		outskirts = { "-weg", "-feld", "-acker", "-ring", "-gasse", "-strasse", "-wiese" } },
	solos = {
		station = { "Bahnhofstrasse", "Am Bahnhof", "Bahnhofplatz" },
		shore = { "Strandpromenade", "Am Kai", "Hafenstrasse", "Strandweg", "Seestrasse", "Uferstrasse" },
		river = { "Brückenstrasse", "Mühlenweg", "Am Fluss", "Uferweg", "An der Furt" },
		hill = { "Bergstrasse", "Am Hang", "Höhenweg", "Auf der Höhe", "Bergweg", "Am Berg" },
		valley = { "Talstrasse", "Im Grund", "Talweg", "In der Aue" },
		forest = { "Waldweg", "Waldstrasse", "Am Waldrand", "Im Wald", "Forstweg" },
		centre = { "Hauptstrasse", "Marktplatz", "Marktstrasse", "Kirchplatz", "Am Markt", "Kirchgasse" },
		outskirts = { "Feldweg", "Wiesenweg", "Grüner Weg", "Am Anger", "Ackerweg" } },
	specs = {
		station = { "Bahnhof", "Bahn", "Gleis", "Güter", "Post", "Signal" },
		shore = { "Hafen", "Strand", "See", "Kai", "Mole", "Leuchtturm", "Dünen", "Fischer" },
		river = { "Mühlen", "Brücken", "Furt", "Fähr", "Wehr", "Schleusen", "Fluss", "Wasser", "Bach" },
		hill = { "Burg", "Schloss", "Kirch", "Aussichts", "Sonnen", "Wind", "Höhen", "Berg" },
		valley = { "Mühl", "Bach", "Quell", "Wiesen", "Brunnen" },
		forest = { "Wald", "Forst", "Jäger", "Fuchs", "Hirsch", "Reh" },
		centre = { "Markt", "Kirch", "Schloss", "Rathaus", "Post", "Brunnen", "Kloster", "Dom" },
		outskirts = { "Feld", "Hof", "Wiesen", "Anger", "Mühlen", "Garten", "Heide", "Moor", "Acker" } },
	tree = { oak = "Eichen", ash = "Eschen", beech = "Buchen", hazel = "Hasel", birch = "Birken", pine = "Kiefern",
		elm = "Ulmen", willow = "Weiden", lime = "Linden", poplar = "Pappel", maple = "Ahorn", fir = "Tannen",
		spruce = "Fichten", larch = "Lärchen", alder = "Erlen", chestnut = "Kastanien", apple = "Apfel", olive = "Oliven",
		cypress = "Zypressen", palm = "Palmen", acacia = "Akazien", elder = "Holunder", lemon = "Zitronen", cedar = "Zedern",
		cherry = "Kirsch", almond = "Mandel" },
	ind = { works = { "Hütten", "Werk", "Fabrik" }, quarry = { "Steinbruch", "Gruben" }, farm = { "Hof", "Gutshof" }, mill = { "Mühlen" } },
	compass = { n = "Nord", e = "Ost", s = "Süd", w = "West" },
	high = { "Hoch", "Ober" },
	toward = function(t)
		local a = deAdj(t)
		if a then return { a .. " Strasse", a .. " Weg", "Alte " .. a .. " Strasse" } end
		return { "Strasse nach " .. t, "Weg nach " .. t }
	end,
}

M.LANG.nl = { join = "compound",
	gens = {
		station = { "-straat", "-weg", "-plein", "-laan", "-pad" },
		shore = { "-weg", "-kade", "-dijk", "-boulevard", "-straat", "-pad" },
		river = { "-weg", "-straat", "-kade", "-pad", "-steeg" },
		hill = { "-berg", "-heuvel", "-weg", "-laan", "-hoogte" },
		valley = { "-dal", "-weg", "-laan", "-beemd" },
		forest = { "-laan", "-dreef", "-pad", "-weg", "-hof", "-bos" },
		centre = { "-straat", "-plein", "-steeg", "-markt", "-hof" },
		outskirts = { "-weg", "-laan", "-veld", "-akker", "-kamp", "-hof", "-erf" } },
	solos = {
		station = { "Stationsweg", "Stationsstraat", "Spoorstraat", "Stationsplein" },
		shore = { "Strandweg", "Havenstraat", "Boulevard", "Kade", "Dijkweg", "Zeedijk" },
		river = { "Brugstraat", "Molenweg", "Rivierweg", "Waterkant", "Veerweg" },
		hill = { "Heuvelweg", "Bergweg", "Hoogstraat", "Op de Berg" },
		valley = { "Dalweg", "In het Dal" },
		forest = { "Bosweg", "Boslaan", "Bosrand", "Bospad" },
		centre = { "Markt", "Kerkstraat", "Dorpsstraat", "Hoofdstraat", "Kerkplein", "Brink" },
		outskirts = { "Veldweg", "Weideweg", "Polderweg", "Akkerweg", "Kampweg" } },
	specs = {
		station = { "Stations", "Spoor", "Rails", "Perron", "Sein" },
		shore = { "Haven", "Strand", "Zee", "Duin", "Vuurtoren", "Vissers", "Pier" },
		river = { "Molen", "Brug", "Veer", "Sluis", "Rivier", "Water" },
		hill = { "Heuvel", "Uitzicht", "Zonne", "Wind", "Kasteel", "Berg" },
		valley = { "Molen", "Beek", "Bron", "Weide" },
		forest = { "Bos", "Hout", "Jagers", "Vossen", "Herten" },
		centre = { "Kerk", "Markt", "Dorps", "Kasteel", "Raadhuis", "Post", "Hoofd" },
		outskirts = { "Hoeve", "Weide", "Akker", "Polder", "Boomgaard", "Veld", "Molen", "Heide" } },
	tree = { oak = "Eiken", ash = "Essen", beech = "Beuken", hazel = "Hazelaar", birch = "Berken", pine = "Dennen",
		elm = "Iepen", willow = "Wilgen", lime = "Linden", poplar = "Populieren", maple = "Esdoorn", fir = "Sparren",
		spruce = "Fijnspar", larch = "Lariks", alder = "Elzen", chestnut = "Kastanje", apple = "Appel", olive = "Olijf",
		cypress = "Cipres", palm = "Palm", acacia = "Acacia", elder = "Vlier", lemon = "Citroen", cedar = "Ceder",
		cherry = "Kersen", almond = "Amandel" },
	ind = { works = { "Fabrieks", "Werf", "Smederij" }, quarry = { "Groeve" }, farm = { "Hoeve", "Boerderij" }, mill = { "Molen" } },
	compass = { n = "Noord", e = "Oost", s = "Zuid", w = "West" },
	high = { "Hoog", "Boven" },
	toward = function(t)
		if t:find("%s") then return { "Weg naar " .. t } end
		return { t .. "seweg", t .. "sestraat", "Oude " .. t .. "seweg" }
	end,
}

local function scand(t, suffix)
	-- "Stockholm" -> "Stockholmsvägen", "Uppsala" -> "Uppsalavägen", "Mjölby" -> "Mjölbyvägen" (vowel or s: no linking s)
	local last = t:sub(-1)
	if last:match("[aeiouyAEIOUYs]") or t:find("[\195][\165\164\182\184\166]$") then return t .. suffix end
	return t .. "s" .. suffix
end

M.LANG.sv = { join = "compound",
	gens = {
		station = { "-gatan", "-vägen", "-torget", "-allén" },
		shore = { "-vägen", "-gatan", "-kajen", "-promenaden", "-bryggan", "-stranden" },
		river = { "-gatan", "-vägen", "-gränd", "-stigen" },
		hill = { "-backen", "-höjden", "-åsen", "-liden", "-vägen", "-berget" },
		valley = { "-dalen", "-vägen", "-ängen", "-sänkan" },
		forest = { "-lunden", "-vägen", "-stigen", "-skogen", "-hagen", "-dungen" },
		centre = { "-gatan", "-torget", "-gränd", "-platsen" },
		outskirts = { "-vägen", "-stigen", "-gärdet", "-ängen", "-hagen", "-gränd" } },
	solos = {
		station = { "Stationsvägen", "Stationsgatan", "Järnvägsgatan" },
		shore = { "Strandvägen", "Hamngatan", "Kajen", "Sjövägen", "Strandpromenaden" },
		river = { "Brogatan", "Kvarnvägen", "Älvvägen", "Strömgatan" },
		hill = { "Backen", "Åsvägen", "Bergsgatan", "Utsiktsvägen" },
		valley = { "Dalvägen", "Dalgatan" },
		forest = { "Skogsvägen", "Skogsgatan", "Lunden" },
		centre = { "Storgatan", "Torget", "Kyrkogatan", "Stora torget" },
		outskirts = { "Ängsvägen", "Åkervägen", "Gärdesvägen" } },
	specs = {
		station = { "Stations", "Järnvägs", "Bangårds", "Spår", "Signal" },
		shore = { "Hamn", "Strand", "Sjö", "Fyr", "Fiskar", "Brygg", "Sand" },
		river = { "Kvarn", "Bro", "Ström", "Fors", "Älv", "Damm", "Färje" },
		hill = { "Berg", "Utsikts", "Sol", "Vind", "Klint", "Slotts" },
		valley = { "Bäck", "Källe", "Kvarn", "Äng" },
		forest = { "Skogs", "Jägar", "Hjort", "Älg" },
		centre = { "Kyrko", "Torg", "Stor", "Slotts", "Rådhus", "Post", "Kungs", "Drottning" },
		outskirts = { "Gårds", "Ängs", "Åker", "Gärdes", "Hag", "Ladu", "Mosse" } },
	tree = { oak = "Ek", ash = "Ask", beech = "Bok", hazel = "Hassel", birch = "Björk", pine = "Tall", elm = "Alm",
		willow = "Pil", lime = "Lind", poplar = "Poppel", maple = "Lönn", fir = "Gran", spruce = "Gran", larch = "Lärk",
		alder = "Al", chestnut = "Kastanj", apple = "Äppel", olive = "Oliv", cypress = "Cypress", palm = "Palm",
		acacia = "Akacia", elder = "Fläder", lemon = "Citron", cedar = "Ceder", cherry = "Körsbärs", almond = "Mandel" },
	ind = { works = { "Bruks", "Verkstads", "Smedje" }, quarry = { "Brotts", "Gruv" }, farm = { "Gårds" }, mill = { "Kvarn" } },
	compass = { n = "Norra", e = "Östra", s = "Södra", w = "Västra" },
	sepCompass = true,
	high = { "Övre", "Höga" },
	sepHigh = true,
	toward = function(t)
		if t:find("%s") then return { "Vägen till " .. t } end
		return { scand(t, "vägen"), scand(t, "gatan"), "Gamla " .. scand(t, "vägen") }
	end,
}

M.LANG.nb = { join = "compound",
	gens = {
		station = { "-gata", "-veien", "-plassen" },
		shore = { "-veien", "-gata", "-kaia", "-brygga", "-stranda" },
		river = { "-gata", "-veien", "-stien", "-smuget" },
		hill = { "-bakken", "-haugen", "-lia", "-åsen", "-veien", "-toppen" },
		valley = { "-dalen", "-veien", "-enga" },
		forest = { "-lunden", "-veien", "-stien", "-skogen", "-holtet" },
		centre = { "-gata", "-torget", "-plassen", "-smuget" },
		outskirts = { "-veien", "-stien", "-jordet", "-enga", "-tunet" } },
	-- (a separate compass / height word takes the indefinite form: "Nordre gate", "Øvre vei")
	indef = { ["-veien"] = "vei", ["-gata"] = "gate", ["-stien"] = "sti", ["-bakken"] = "bakke", ["-plassen"] = "plass",
		["-torget"] = "torg", ["-kaia"] = "kai", ["-brygga"] = "brygge", ["-stranda"] = "strand", ["-smuget"] = "smug",
		["-haugen"] = "haug", ["-lia"] = "li", ["-åsen"] = "ås", ["-toppen"] = "topp", ["-dalen"] = "dal", ["-enga"] = "eng",
		["-lunden"] = "lund", ["-skogen"] = "skog", ["-holtet"] = "holt", ["-jordet"] = "jorde", ["-tunet"] = "tun" },
	solos = {
		station = { "Stasjonsveien", "Jernbanegata", "Stasjonsgata" },
		shore = { "Strandveien", "Havnegata", "Kaiveien", "Brygga", "Sjøgata" },
		river = { "Brugata", "Elveveien", "Møllevegen", "Fossveien" },
		hill = { "Bakken", "Åsveien", "Bergveien", "Utsikten" },
		valley = { "Dalveien" },
		forest = { "Skogveien", "Granveien", "Lunden" },
		centre = { "Storgata", "Torget", "Kirkegata", "Torggata" },
		outskirts = { "Engveien", "Åkerveien", "Gårdsveien" } },
	specs = {
		station = { "Stasjons", "Jernbane", "Spor", "Signal", "Perrong" },
		shore = { "Havne", "Strand", "Sjø", "Fyr", "Fisker", "Brygge", "Sand" },
		river = { "Mølle", "Bru", "Foss", "Elve", "Ferje", "Kvern" },
		hill = { "Berg", "Utsikts", "Sol", "Vind", "Varde", "Slotts" },
		valley = { "Bekke", "Kilde", "Mølle", "Eng" },
		forest = { "Skog", "Jeger", "Hjorte", "Elg", "Rev" },
		centre = { "Kirke", "Torg", "Stor", "Slotts", "Rådhus", "Post", "Konge", "Dronning" },
		outskirts = { "Gårds", "Eng", "Åker", "Jorde", "Låve", "Myr", "Hage" } },
	tree = { oak = "Eike", ash = "Aske", beech = "Bøke", hazel = "Hassel", birch = "Bjørke", pine = "Furu", elm = "Alm",
		willow = "Selje", lime = "Linde", poplar = "Poppel", maple = "Lønne", fir = "Edelgran", spruce = "Gran",
		larch = "Lerke", alder = "Older", chestnut = "Kastanje", apple = "Eple", olive = "Oliven", cypress = "Sypress",
		palm = "Palme", acacia = "Akasie", elder = "Hyll", lemon = "Sitron", cedar = "Seder", cherry = "Kirsebær", almond = "Mandel" },
	ind = { works = { "Verks", "Smie", "Fabrikk" }, quarry = { "Brudd", "Gruve" }, farm = { "Gårds" }, mill = { "Mølle" } },
	compass = { n = "Nordre", e = "Østre", s = "Søndre", w = "Vestre" },
	sepCompass = true,
	high = { "Øvre", "Høye" },
	sepHigh = true,
	toward = function(t)
		if t:find("%s") then return { "Veien til " .. t } end
		return { scand(t, "veien"), scand(t, "gata"), "Gamle " .. scand(t, "veien") }
	end,
}

-- French "de X" / "d'X"
local function frDe(t)
	if t:match("^[AEIOUYHaeiouyh]") or t:find("^\195[\137\136\138]") then return "d'" .. t end
	return "de " .. t
end

M.LANG.fr = { join = "romance",
	gens = {
		station = { { "Rue", "f" }, { "Avenue", "f" }, { "Place", "f" }, { "Boulevard", "m" }, { "Impasse", "f" } },
		shore = { { "Quai", "m" }, { "Promenade", "f" }, { "Boulevard", "m" }, { "Rue", "f" }, { "Esplanade", "f" }, { "Chemin", "m" } },
		river = { { "Quai", "m" }, { "Rue", "f" }, { "Chemin", "m" }, { "Passage", "m" }, { "Ruelle", "f" } },
		hill = { { "Côte", "f" }, { "Montée", "f" }, { "Chemin", "m" }, { "Rue", "f" }, { "Sentier", "m" }, { "Belvédère", "m" } },
		valley = { { "Chemin", "m" }, { "Rue", "f" }, { "Sentier", "m" }, { "Allée", "f" } },
		forest = { { "Allée", "f" }, { "Chemin", "m" }, { "Sentier", "m" }, { "Route", "f" }, { "Rue", "f" } },
		centre = { { "Rue", "f" }, { "Place", "f" }, { "Passage", "m" }, { "Cours", "m" } },
		outskirts = { { "Chemin", "m" }, { "Impasse", "f" }, { "Allée", "f" }, { "Clos", "m" }, { "Rue", "f" }, { "Route", "f" } } },
	solos = {
		station = { "Rue de la Gare", "Avenue de la Gare", "Place de la Gare" },
		shore = { "Quai du Port", "Boulevard de la Mer", "Promenade de la Plage", "Rue du Port", "Front de Mer" },
		river = { "Quai de la Rivière", "Rue du Pont", "Rue du Moulin", "Chemin du Gué" },
		hill = { "Rue des Hauts", "Rue du Coteau", "Chemin du Belvédère", "Montée du Château" },
		valley = { "Rue du Vallon", "Chemin du Val" },
		forest = { "Chemin du Bois", "Rue de la Forêt", "Allée des Chênes" },
		centre = { "Grand-Rue", "Place du Marché", "Rue du Marché", "Place de l'Église", "Rue de l'Église" },
		outskirts = { "Chemin des Champs", "Rue des Prés" } },
	specs = {
		station = { "de la Gare", "du Chemin de Fer", "des Rails", "du Dépôt", "des Cheminots", "du Viaduc" },
		shore = { "du Port", "de la Mer", "de la Plage", "du Phare", "des Pêcheurs", "de la Jetée", "des Dunes", "des Mouettes" },
		river = { "du Moulin", "du Pont", "du Gué", "de l'Écluse", "du Lavoir", "de la Rivière", "du Bac", "des Berges" },
		hill = { "du Belvédère", "des Hauts", "du Coteau", "de la Colline", "du Château", "du Calvaire", "des Vignes", "du Moulin à Vent" },
		valley = { "du Vallon", "de la Vallée", "du Val", "de la Source", "du Ruisseau" },
		forest = { "du Bois", "de la Forêt", "des Bois", "de la Clairière", "des Chasseurs" },
		centre = { "du Marché", "de l'Église", "de la Mairie", "du Château", "de la Poste", "des Halles", "de la Fontaine", "de la République" },
		outskirts = { "des Champs", "des Prés", "du Verger", "de la Croix", "des Haies", "de la Ferme", "des Vignes", "du Pré" } },
	tree = { oak = "des Chênes", ash = "des Frênes", beech = "des Hêtres", hazel = "des Noisetiers", birch = "des Bouleaux",
		pine = "des Pins", elm = "des Ormes", willow = "des Saules", lime = "des Tilleuls", poplar = "des Peupliers",
		maple = "des Érables", fir = "des Sapins", spruce = "des Épicéas", larch = "des Mélèzes", alder = "des Aulnes",
		chestnut = "des Châtaigniers", apple = "des Pommiers", olive = "des Oliviers", cypress = "des Cyprès",
		palm = "des Palmiers", acacia = "des Acacias", elder = "des Sureaux", lemon = "des Citronniers", cedar = "des Cèdres",
		cherry = "des Cerisiers", almond = "des Amandiers" },
	ind = { works = { "de l'Usine", "des Forges" }, quarry = { "de la Carrière", "de la Mine" }, farm = { "de la Ferme" }, mill = { "du Moulin" } },
	compass = { n = "du Nord", e = "de l'Est", s = "du Sud", w = "de l'Ouest" },
	high = { f = "Haute", m = "Haut" },
	own = frDe,
	toward = function(t) return { "Route " .. frDe(t), "Chemin " .. frDe(t), "Avenue " .. frDe(t) } end,
}

M.LANG.it = { join = "romance",
	gens = {
		station = { { "Via", "f" }, { "Viale", "m" }, { "Piazza", "f" }, { "Piazzale", "m" }, { "Largo", "m" }, { "Vicolo", "m" } },
		shore = { { "Lungomare", "m" }, { "Via", "f" }, { "Viale", "m" }, { "Passeggiata", "f" }, { "Molo", "m" } },
		river = { { "Via", "f" }, { "Lungofiume", "m" }, { "Vicolo", "m" }, { "Strada", "f" }, { "Riva", "f" } },
		hill = { { "Salita", "f" }, { "Via", "f" }, { "Strada", "f" }, { "Viale", "m" }, { "Scalinata", "f" } },
		valley = { { "Via", "f" }, { "Strada", "f" }, { "Viottolo", "m" }, { "Vicolo", "m" } },
		forest = { { "Viale", "m" }, { "Via", "f" }, { "Sentiero", "m" }, { "Strada", "f" }, { "Viottolo", "m" } },
		centre = { { "Via", "f" }, { "Piazza", "f" }, { "Vicolo", "m" }, { "Corso", "m" }, { "Largo", "m" } },
		outskirts = { { "Via", "f" }, { "Strada", "f" }, { "Vicolo", "m" }, { "Contrada", "f" }, { "Viottolo", "m" }, { "Traversa", "f" } } },
	solos = {
		station = { "Via della Stazione", "Viale della Stazione", "Piazza della Stazione" },
		shore = { "Lungomare", "Via del Porto", "Via della Marina" },
		river = { "Lungofiume", "Via del Ponte", "Via del Mulino" },
		hill = { "Via del Colle", "Via Belvedere", "Via Panoramica" },
		valley = { "Via della Valle" },
		forest = { "Via del Bosco", "Via della Pineta" },
		centre = { "Corso Italia", "Piazza del Mercato", "Via Roma", "Piazza del Duomo" },
		outskirts = { "Via dei Campi", "Via dei Prati" } },
	specs = {
		station = { "della Stazione", "della Ferrovia", "dei Binari", "dei Ferrovieri", "del Deposito" },
		shore = { "del Porto", "della Marina", "del Faro", "dei Pescatori", "della Spiaggia", "degli Scogli", "del Mare" },
		river = { "del Ponte", "del Mulino", "del Guado", "della Chiusa", "del Fiume", "dei Lavatoi" },
		hill = { "del Colle", "della Collina", "del Belvedere", "del Castello", "della Rocca", "delle Vigne", "del Monte" },
		valley = { "della Valle", "del Vallone", "della Fonte", "del Torrente" },
		forest = { "del Bosco", "della Pineta", "della Selva", "dei Cacciatori" },
		centre = { "del Mercato", "della Chiesa", "del Duomo", "del Castello", "del Municipio", "della Fontana", "della Posta", "del Popolo" },
		outskirts = { "dei Campi", "dei Prati", "delle Vigne", "dell'Orto", "della Cascina", "del Mulino" } },
	tree = { oak = "delle Querce", ash = "dei Frassini", beech = "dei Faggi", hazel = "dei Noccioli", birch = "delle Betulle",
		pine = "dei Pini", elm = "degli Olmi", willow = "dei Salici", lime = "dei Tigli", poplar = "dei Pioppi",
		maple = "degli Aceri", fir = "degli Abeti", spruce = "degli Abeti Rossi", larch = "dei Larici", alder = "degli Ontani",
		chestnut = "dei Castagni", apple = "dei Meli", olive = "degli Ulivi", cypress = "dei Cipressi", palm = "delle Palme",
		acacia = "delle Acacie", elder = "dei Sambuchi", lemon = "dei Limoni", cedar = "dei Cedri", cherry = "dei Ciliegi",
		almond = "dei Mandorli" },
	ind = { works = { "delle Officine", "della Fabbrica", "della Fornace" }, quarry = { "della Cava", "della Miniera" },
		farm = { "della Cascina", "della Fattoria" }, mill = { "del Mulino" } },
	-- (Italian compass street names are adjectives after the noun: "Via Orientale")
	compass = { n = "Settentrionale", e = "Orientale", s = "Meridionale", w = "Occidentale" },
	high = { f = "Alta", m = "Alto" },
	own = function(t) return "di " .. t end,
	toward = function(t) return { "Via " .. t, "Strada per " .. t, "Viale " .. t } end,
}

M.LANG.es = { join = "romance",
	gens = {
		station = { { "Calle", "f" }, { "Avenida", "f" }, { "Plaza", "f" }, { "Paseo", "m" }, { "Travesía", "f" }, { "Callejón", "m" } },
		shore = { { "Paseo", "m" }, { "Calle", "f" }, { "Avenida", "f" }, { "Muelle", "m" }, { "Rambla", "f" } },
		river = { { "Calle", "f" }, { "Paseo", "m" }, { "Camino", "m" }, { "Ribera", "f" } },
		hill = { { "Cuesta", "f" }, { "Calle", "f" }, { "Camino", "m" }, { "Subida", "f" }, { "Mirador", "m" } },
		valley = { { "Camino", "m" }, { "Calle", "f" }, { "Senda", "f" }, { "Travesía", "f" } },
		forest = { { "Camino", "m" }, { "Calle", "f" }, { "Senda", "f" }, { "Paseo", "m" }, { "Vereda", "f" } },
		centre = { { "Calle", "f" }, { "Plaza", "f" }, { "Callejón", "m" }, { "Travesía", "f" } },
		outskirts = { { "Camino", "m" }, { "Calle", "f" }, { "Travesía", "f" }, { "Callejón", "m" }, { "Senda", "f" } } },
	solos = {
		station = { "Calle de la Estación", "Avenida de la Estación" },
		shore = { "Paseo Marítimo", "Calle del Puerto", "Avenida del Mar" },
		river = { "Calle del Río", "Calle del Puente", "Calle del Molino" },
		hill = { "Calle del Cerro", "Calle Mirador", "Camino del Alto" },
		valley = { "Calle del Valle" },
		forest = { "Calle del Bosque", "Camino del Pinar" },
		centre = { "Calle Mayor", "Plaza Mayor", "Calle del Mercado", "Plaza de la Iglesia" },
		outskirts = { "Camino de los Campos", "Calle de las Eras" } },
	specs = {
		station = { "de la Estación", "del Ferrocarril", "de las Vías", "de los Ferroviarios", "del Andén" },
		shore = { "del Puerto", "del Mar", "de la Playa", "del Faro", "de los Pescadores", "de la Lonja", "de las Dunas" },
		river = { "del Río", "del Puente", "del Molino", "del Vado", "de la Presa", "de la Acequia", "de la Ribera" },
		hill = { "del Cerro", "del Mirador", "de la Loma", "del Alto", "del Castillo", "de la Atalaya", "de las Viñas" },
		valley = { "del Valle", "de la Vega", "de la Fuente", "del Arroyo", "de la Cañada" },
		forest = { "del Bosque", "del Pinar", "del Monte", "de los Cazadores", "de la Dehesa" },
		centre = { "del Mercado", "de la Iglesia", "del Ayuntamiento", "del Castillo", "de la Fuente", "de la Constitución",
			"del Correo", "de la Catedral" },
		outskirts = { "de las Eras", "de los Campos", "de las Huertas", "del Prado", "de la Viña", "del Cortijo", "de la Era" } },
	tree = { oak = "de los Robles", ash = "de los Fresnos", beech = "de las Hayas", hazel = "de los Avellanos",
		birch = "de los Abedules", pine = "de los Pinos", elm = "de los Olmos", willow = "de los Sauces", lime = "de los Tilos",
		poplar = "de los Álamos", maple = "de los Arces", fir = "de los Abetos", spruce = "de las Píceas", larch = "de los Alerces",
		alder = "de los Alisos", chestnut = "de los Castaños", apple = "de los Manzanos", olive = "de los Olivos",
		cypress = "de los Cipreses", palm = "de las Palmeras", acacia = "de las Acacias", elder = "de los Saúcos",
		lemon = "de los Limoneros", cedar = "de los Cedros", cherry = "de los Cerezos", almond = "de los Almendros" },
	ind = { works = { "de la Fábrica", "de la Fundición" }, quarry = { "de la Cantera", "de la Mina" },
		farm = { "de la Granja", "del Cortijo" }, mill = { "del Molino" } },
	compass = { n = "del Norte", e = "del Este", s = "del Sur", w = "del Oeste" },
	high = { f = "Alta", m = "Alto" },
	own = function(t) return "de " .. t end,
	toward = function(t) return { "Camino de " .. t, "Carretera de " .. t, "Avenida de " .. t } end,
}

M.LANG.pt = { join = "romance",
	gens = {
		station = { { "Rua", "f" }, { "Avenida", "f" }, { "Largo", "m" }, { "Praça", "f" }, { "Travessa", "f" }, { "Beco", "m" } },
		shore = { { "Avenida", "f" }, { "Rua", "f" }, { "Cais", "m" }, { "Passeio", "m" } },
		river = { { "Rua", "f" }, { "Travessa", "f" }, { "Caminho", "m" }, { "Cais", "m" } },
		hill = { { "Calçada", "f" }, { "Rua", "f" }, { "Travessa", "f" }, { "Caminho", "m" }, { "Miradouro", "m" } },
		valley = { { "Caminho", "m" }, { "Rua", "f" }, { "Travessa", "f" }, { "Vereda", "f" } },
		forest = { { "Caminho", "m" }, { "Rua", "f" }, { "Alameda", "f" }, { "Vereda", "f" } },
		centre = { { "Rua", "f" }, { "Praça", "f" }, { "Largo", "m" }, { "Travessa", "f" }, { "Beco", "m" } },
		outskirts = { { "Caminho", "m" }, { "Rua", "f" }, { "Travessa", "f" }, { "Estrada", "f" }, { "Azinhaga", "f" } } },
	solos = {
		station = { "Rua da Estação", "Avenida da Estação" },
		shore = { "Avenida Marginal", "Rua do Porto", "Avenida da Praia" },
		river = { "Rua do Rio", "Rua da Ponte", "Rua do Moinho" },
		hill = { "Rua do Alto", "Rua da Encosta", "Miradouro" },
		valley = { "Rua do Vale" },
		forest = { "Rua do Bosque", "Rua do Pinhal" },
		centre = { "Rua Direita", "Rua do Mercado", "Praça da República", "Largo da Igreja" },
		outskirts = { "Rua dos Campos", "Caminho Rural" } },
	specs = {
		station = { "da Estação", "do Caminho de Ferro", "da Linha", "dos Ferroviários", "do Apeadeiro" },
		shore = { "do Porto", "do Mar", "da Praia", "do Farol", "dos Pescadores", "da Lota", "das Dunas" },
		river = { "do Rio", "da Ponte", "do Moinho", "do Vau", "da Azenha", "da Levada", "da Ribeira" },
		hill = { "do Alto", "da Encosta", "do Miradouro", "da Colina", "do Castelo", "das Vinhas", "do Outeiro" },
		valley = { "do Vale", "da Várzea", "da Fonte", "do Ribeiro" },
		forest = { "do Bosque", "do Pinhal", "da Mata", "dos Caçadores", "da Tapada" },
		centre = { "do Mercado", "da Igreja", "da Câmara", "do Castelo", "do Chafariz", "da República", "do Correio", "da Sé" },
		outskirts = { "dos Campos", "das Hortas", "do Prado", "das Vinhas", "da Quinta", "da Eira", "do Casal" } },
	tree = { oak = "dos Carvalhos", ash = "dos Freixos", beech = "das Faias", hazel = "das Aveleiras", birch = "das Bétulas",
		pine = "dos Pinheiros", elm = "dos Ulmeiros", willow = "dos Salgueiros", lime = "das Tílias", poplar = "dos Choupos",
		maple = "dos Bordos", fir = "dos Abetos", spruce = "das Píceas", larch = "dos Lariços", alder = "dos Amieiros",
		chestnut = "dos Castanheiros", apple = "das Macieiras", olive = "das Oliveiras", cypress = "dos Ciprestes",
		palm = "das Palmeiras", acacia = "das Acácias", elder = "dos Sabugueiros", lemon = "dos Limoeiros", cedar = "dos Cedros",
		cherry = "das Cerejeiras", almond = "das Amendoeiras" },
	ind = { works = { "da Fábrica", "da Fundição" }, quarry = { "da Pedreira", "da Mina" }, farm = { "da Quinta", "do Monte" }, mill = { "do Moinho" } },
	compass = { n = "do Norte", e = "do Nascente", s = "do Sul", w = "do Poente" },
	high = { f = "Alta", m = "Alto" },
	own = function(t) return "de " .. t end,
	toward = function(t) return { "Estrada de " .. t, "Rua de " .. t, "Caminho de " .. t } end,
}

M.LANG.ja = { join = "concat", own = true,
	gens = {
		station = { "前通り", "通り", "口" },
		shore = { "浜通り", "港通り", "海岸通り", "浦", "浜" },
		river = { "川端", "河原", "橋通り", "通り", "渡し" },
		hill = { "坂", "台", "ヶ丘", "山手", "峠" },
		valley = { "谷", "沢", "窪" },
		forest = { "森", "林", "並木", "通り" },
		centre = { "本町", "中央通り", "大通り", "町", "通り" },
		outskirts = { "田", "野", "原", "新田", "通り", "町" } },
	solos = {
		station = { "駅前通り", "駅前" }, shore = { "海岸通り", "港通り", "浜通り" }, river = { "川端通り", "橋通り" },
		hill = { "坂通り", "台町通り", "山手通り" }, valley = { "谷町通り", "沢通り" }, forest = { "森通り", "松並木通り" },
		centre = { "本町通り", "中央通り", "大手通り" }, outskirts = { "田園通り" } },
	specs = {
		station = { "駅", "駅南", "駅北", "駅東", "駅西" },
		shore = { "港", "浜", "海", "磯", "灯台", "漁師" },
		river = { "川", "橋", "渡", "水車" },
		hill = { "見晴", "日向", "風", "城", "高" },
		valley = { "沢", "谷", "清水", "泉" },
		forest = { "森", "林", "鎮守" },
		centre = { "本", "中", "元", "仲", "大手", "銀座" },
		outskirts = { "新", "若葉", "緑", "野", "原", "田" } },
	tree = { pine = "松", cedar = "杉", cherry = "桜", maple = "楓", oak = "樫", beech = "橅", birch = "白樺", willow = "柳",
		chestnut = "栗", cypress = "檜", palm = "椰子", elm = "楡", fir = "樅", larch = "落葉松", hazel = "榛",
		poplar = "ポプラ", acacia = "アカシア", olive = "オリーブ" },
	ind = { works = { "工場", "製鉄" }, quarry = { "石切" }, farm = { "牧場" }, mill = { "水車" } },
	compass = { n = "北", e = "東", s = "南", w = "西" },
	high = { "上", "高" },
	toward = function(t) return { t .. "街道", t .. "道" } end,
}

M.LANG.ja_r = { join = "concat",
	gens = {
		station = { "mae-dōri", "-dōri", "guchi" },
		shore = { "hama-dōri", "minato-dōri", "kaigan-dōri", "ura", "hama" },
		river = { "kawabata", "gawara", "bashi-dōri", "-dōri" },
		hill = { "zaka", "dai", "gaoka", "yamate" },
		valley = { "dani", "sawa" },
		forest = { "mori", "bayashi", "namiki", "-dōri" },
		centre = { "honmachi", "chūō-dōri", "ōdōri", "machi", "-dōri" },
		outskirts = { "da", "no", "hara", "shinden", "-dōri", "machi" } },
	solos = {
		station = { "Ekimae-dōri" }, shore = { "Kaigan-dōri", "Minato-dōri" }, river = { "Kawabata-dōri", "Hashi-dōri" },
		hill = { "Saka-dōri", "Yamate-dōri" }, valley = { "Tani-dōri" }, forest = { "Mori-dōri", "Matsu-dōri" },
		centre = { "Honmachi-dōri", "Chūō-dōri", "Ōte-dōri" }, outskirts = { "Den'en-dōri" } },
	specs = {
		station = { "Eki", "Ekinan", "Ekikita" },
		shore = { "Minato", "Hama", "Umi", "Iso", "Tōdai" },
		river = { "Kawa", "Hashi", "Watashi", "Suisha" },
		hill = { "Miharashi", "Hinata", "Kaze", "Shiro", "Taka" },
		valley = { "Sawa", "Tani", "Shimizu", "Izumi" },
		forest = { "Mori", "Hayashi", "Chinju" },
		centre = { "Hon", "Naka", "Moto", "Ōte", "Ginza" },
		outskirts = { "Shin", "Wakaba", "Midori", "No", "Hara" } },
	tree = { pine = "Matsu", cedar = "Sugi", cherry = "Sakura", maple = "Kaede", oak = "Kashi", beech = "Buna",
		birch = "Shirakaba", willow = "Yanagi", chestnut = "Kuri", cypress = "Hinoki", palm = "Yashi", elm = "Nire", fir = "Momi",
		larch = "Karamatsu", hazel = "Hashibami", poplar = "Popura", acacia = "Akashia", olive = "Orību" },
	ind = { works = { "Kōjō" }, quarry = { "Ishikiri" }, farm = { "Bokujō" }, mill = { "Suisha" } },
	compass = { n = "Kita", e = "Higashi", s = "Minami", w = "Nishi" },
	high = { "Kami", "Taka" },
	own = function(t) return t .. "-" end,
	toward = function(t) return { t .. " Kaidō", t .. "-michi" } end,
}

-- Russian accusative of a town name after "на" (feminine -а / -я: -у / -ю; the rest unchanged)
local function ruAcc(t)
	if t:sub(-2) == "а" then return t:sub(1, -3) .. "у" end
	if t:sub(-2) == "я" then return t:sub(1, -3) .. "ю" end
	return t
end
local function A(f, m) return { f = f, m = m } end

M.LANG.ru = { join = "adj",
	gens = {
		station = { { "улица", "f" }, { "площадь", "f" }, { "переулок", "m" }, { "проезд", "m" }, { "тупик", "m" }, { "аллея", "f" } },
		shore = { { "улица", "f" }, { "набережная", "f" }, { "бульвар", "m" }, { "проезд", "m" }, { "аллея", "f" } },
		river = { { "улица", "f" }, { "набережная", "f" }, { "переулок", "m" }, { "проезд", "m" } },
		hill = { { "улица", "f" }, { "переулок", "m" }, { "проезд", "m" }, { "тупик", "m" }, { "спуск", "m" } },
		valley = { { "улица", "f" }, { "переулок", "m" }, { "проезд", "m" }, { "тупик", "m" } },
		forest = { { "улица", "f" }, { "аллея", "f" }, { "просека", "f" }, { "переулок", "m" }, { "проезд", "m" } },
		centre = { { "улица", "f" }, { "площадь", "f" }, { "переулок", "m" }, { "бульвар", "m" } },
		outskirts = { { "улица", "f" }, { "переулок", "m" }, { "проезд", "m" }, { "тупик", "m" } } },
	solos = {
		station = { "Вокзальная улица", "Привокзальная площадь" },
		shore = { "Набережная улица", "Морская улица", "Портовая улица" },
		river = { "Речная улица", "Мостовая улица", "Мельничная улица" },
		hill = { "Нагорная улица", "Горная улица" },
		valley = { "Долинная улица" },
		forest = { "Лесная улица", "Сосновая улица" },
		centre = { "Центральная улица", "Рыночная площадь", "Соборная площадь" },
		outskirts = { "Полевая улица", "Садовая улица" } },
	specs = {
		station = { A("Вокзальная", "Вокзальный"), A("Железнодорожная", "Железнодорожный"), A("Станционная", "Станционный"),
			A("Привокзальная", "Привокзальный") },
		shore = { A("Морская", "Морской"), A("Портовая", "Портовый"), A("Береговая", "Береговой"), A("Приморская", "Приморский"),
			A("Рыбацкая", "Рыбацкий"), A("Маячная", "Маячный"), A("Пляжная", "Пляжный") },
		river = { A("Речная", "Речной"), A("Мельничная", "Мельничный"), A("Мостовая", "Мостовой"), A("Заречная", "Заречный"),
			A("Паромная", "Паромный"), A("Плотинная", "Плотинный") },
		hill = { A("Нагорная", "Нагорный"), A("Горная", "Горный"), A("Солнечная", "Солнечный"), A("Высокая", "Высокий"),
			A("Холмистая", "Холмистый"), A("Крутая", "Крутой") },
		valley = { A("Долинная", "Долинный"), A("Овражная", "Овражный"), A("Ключевая", "Ключевой"), A("Родниковая", "Родниковый") },
		forest = { A("Лесная", "Лесной"), A("Боровая", "Боровой"), A("Охотничья", "Охотничий") },
		centre = { A("Центральная", "Центральный"), A("Соборная", "Соборный"), A("Торговая", "Торговый"), A("Почтовая", "Почтовый"),
			A("Красная", "Красный"), A("Церковная", "Церковный") },
		outskirts = { A("Полевая", "Полевой"), A("Луговая", "Луговой"), A("Садовая", "Садовый"), A("Огородная", "Огородный"),
			A("Дачная", "Дачный"), A("Степная", "Степной") } },
	tree = { oak = A("Дубовая", "Дубовый"), ash = A("Ясеневая", "Ясеневый"), beech = A("Буковая", "Буковый"),
		hazel = A("Ореховая", "Ореховый"), birch = A("Берёзовая", "Берёзовый"), pine = A("Сосновая", "Сосновый"),
		elm = A("Вязовая", "Вязовый"), willow = A("Ивовая", "Ивовый"), lime = A("Липовая", "Липовый"),
		poplar = A("Тополиная", "Тополиный"), maple = A("Кленовая", "Кленовый"), fir = A("Пихтовая", "Пихтовый"),
		spruce = A("Еловая", "Еловый"), larch = A("Лиственничная", "Лиственничный"), alder = A("Ольховая", "Ольховый"),
		chestnut = A("Каштановая", "Каштановый"), apple = A("Яблоневая", "Яблоневый"), olive = A("Оливковая", "Оливковый"),
		cypress = A("Кипарисовая", "Кипарисовый"), palm = A("Пальмовая", "Пальмовый"), acacia = A("Акациевая", "Акациевый"),
		elder = A("Бузиновая", "Бузиновый"), lemon = A("Лимонная", "Лимонный"), cedar = A("Кедровая", "Кедровый"),
		cherry = A("Вишнёвая", "Вишнёвый"), almond = A("Миндальная", "Миндальный") },
	ind = { works = { A("Заводская", "Заводской"), A("Фабричная", "Фабричный") }, quarry = { A("Карьерная", "Карьерный") },
		farm = { A("Хуторская", "Хуторской") }, mill = { A("Мельничная", "Мельничный") } },
	compass = { n = A("Северная", "Северный"), e = A("Восточная", "Восточный"), s = A("Южная", "Южный"), w = A("Западная", "Западный") },
	high = { A("Верхняя", "Верхний") },
	-- ("Большая Садовая улица", "Малый Лесной переулок": Russian street names pair by size and age)
	mods = { A("Большая", "Большой"), A("Малая", "Малый"), A("Новая", "Новый"), A("Старая", "Старый") },
	toward = function(t) return { "Дорога на " .. ruAcc(t) } end,
}

M.LANG.ru_r = { join = "adj",
	gens = {
		station = { { "ulitsa", "f" }, { "ploshchad", "f" }, { "pereulok", "m" }, { "proyezd", "m" }, { "tupik", "m" }, { "alleya", "f" } },
		shore = { { "ulitsa", "f" }, { "naberezhnaya", "f" }, { "bulvar", "m" }, { "proyezd", "m" }, { "alleya", "f" } },
		river = { { "ulitsa", "f" }, { "naberezhnaya", "f" }, { "pereulok", "m" }, { "proyezd", "m" } },
		hill = { { "ulitsa", "f" }, { "pereulok", "m" }, { "proyezd", "m" }, { "tupik", "m" }, { "spusk", "m" } },
		valley = { { "ulitsa", "f" }, { "pereulok", "m" }, { "proyezd", "m" }, { "tupik", "m" } },
		forest = { { "ulitsa", "f" }, { "alleya", "f" }, { "proseka", "f" }, { "pereulok", "m" }, { "proyezd", "m" } },
		centre = { { "ulitsa", "f" }, { "ploshchad", "f" }, { "pereulok", "m" }, { "bulvar", "m" } },
		outskirts = { { "ulitsa", "f" }, { "pereulok", "m" }, { "proyezd", "m" }, { "tupik", "m" } } },
	solos = {
		station = { "Vokzalnaya ulitsa", "Privokzalnaya ploshchad" },
		shore = { "Naberezhnaya ulitsa", "Morskaya ulitsa", "Portovaya ulitsa" },
		river = { "Rechnaya ulitsa", "Mostovaya ulitsa", "Melnichnaya ulitsa" },
		hill = { "Nagornaya ulitsa", "Gornaya ulitsa" },
		valley = { "Dolinnaya ulitsa" },
		forest = { "Lesnaya ulitsa", "Sosnovaya ulitsa" },
		centre = { "Tsentralnaya ulitsa", "Rynochnaya ploshchad", "Sobornaya ploshchad" },
		outskirts = { "Polevaya ulitsa", "Sadovaya ulitsa" } },
	specs = {
		station = { A("Vokzalnaya", "Vokzalny"), A("Zheleznodorozhnaya", "Zheleznodorozhny"), A("Stantsionnaya", "Stantsionny") },
		shore = { A("Morskaya", "Morskoy"), A("Portovaya", "Portovy"), A("Beregovaya", "Beregovoy"), A("Primorskaya", "Primorsky"),
			A("Rybatskaya", "Rybatsky"), A("Plyazhnaya", "Plyazhny") },
		river = { A("Rechnaya", "Rechnoy"), A("Melnichnaya", "Melnichny"), A("Mostovaya", "Mostovoy"), A("Zarechnaya", "Zarechny"),
			A("Paromnaya", "Paromny") },
		hill = { A("Nagornaya", "Nagorny"), A("Gornaya", "Gorny"), A("Solnechnaya", "Solnechny"), A("Vysokaya", "Vysoky"),
			A("Krutaya", "Krutoy") },
		valley = { A("Dolinnaya", "Dolinny"), A("Ovrazhnaya", "Ovrazhny"), A("Klyuchevaya", "Klyuchevoy"), A("Rodnikovaya", "Rodnikovy") },
		forest = { A("Lesnaya", "Lesnoy"), A("Borovaya", "Borovoy"), A("Okhotnichya", "Okhotnichy") },
		centre = { A("Tsentralnaya", "Tsentralny"), A("Sobornaya", "Soborny"), A("Torgovaya", "Torgovy"), A("Pochtovaya", "Pochtovy"),
			A("Krasnaya", "Krasny"), A("Tserkovnaya", "Tserkovny") },
		outskirts = { A("Polevaya", "Polevoy"), A("Lugovaya", "Lugovoy"), A("Sadovaya", "Sadovy"), A("Ogorodnaya", "Ogorodny"),
			A("Dachnaya", "Dachny"), A("Stepnaya", "Stepnoy") } },
	tree = { oak = A("Dubovaya", "Dubovy"), ash = A("Yasenevaya", "Yasenevy"), beech = A("Bukovaya", "Bukovy"),
		hazel = A("Orekhovaya", "Orekhovy"), birch = A("Beryozovaya", "Beryozovy"), pine = A("Sosnovaya", "Sosnovy"),
		elm = A("Vyazovaya", "Vyazovy"), willow = A("Ivovaya", "Ivovy"), lime = A("Lipovaya", "Lipovy"),
		poplar = A("Topolinaya", "Topoliny"), maple = A("Klenovaya", "Klenovy"), fir = A("Pikhtovaya", "Pikhtovy"),
		spruce = A("Yelovaya", "Yelovy"), larch = A("Listvennichnaya", "Listvennichny"), alder = A("Olkhovaya", "Olkhovy"),
		chestnut = A("Kashtanovaya", "Kashtanovy"), apple = A("Yablonevaya", "Yablonevy"), olive = A("Olivkovaya", "Olivkovy"),
		cypress = A("Kiparisovaya", "Kiparisovy"), palm = A("Palmovaya", "Palmovy"), acacia = A("Akatsiyevaya", "Akatsiyevy"),
		elder = A("Buzinovaya", "Buzinovy"), lemon = A("Limonnaya", "Limonny"), cedar = A("Kedrovaya", "Kedrovy"),
		cherry = A("Vishnyovaya", "Vishnyovy"), almond = A("Mindalnaya", "Mindalny") },
	ind = { works = { A("Zavodskaya", "Zavodskoy"), A("Fabrichnaya", "Fabrichny") }, quarry = { A("Karyernaya", "Karyerny") },
		farm = { A("Khutorskaya", "Khutorskoy") }, mill = { A("Melnichnaya", "Melnichny") } },
	compass = { n = A("Severnaya", "Severny"), e = A("Vostochnaya", "Vostochny"), s = A("Yuzhnaya", "Yuzhny"), w = A("Zapadnaya", "Zapadny") },
	high = { A("Verkhnyaya", "Verkhny") },
	mods = { A("Bolshaya", "Bolshoy"), A("Malaya", "Maly"), A("Novaya", "Novy"), A("Staraya", "Stary") },
	toward = function(t) return { "Doroga na " .. t } end,
}

---------------------------------------------------------------------------
-- richer parts (2026-10-13, run 2026-10-13_2240_sqot-dev: every stop took a real list name, "The Grove" twice): per
-- language the industry theme's generics and words by industry type (M.indKind), old field / farm names (`fields`),
-- landmarks (`marks`), lake words (`lake`, the shore theme at a lake), the industry's own name (`indName`, where the
-- grammar allows it without knowing the name's gender). Compound languages: stems; Romance: "de ..." phrases; ru:
-- gendered adjectives; ja: kanji / romanised stems.

local function set(cls, t)
	local L = M.LANG[cls]
	L.gens.industry = t.gi
	L.ind = t.ind
	L.fields, L.marks, L.lake, L.indName = t.fields, t.marks, t.lake, t.indName
	if t.mods then L.mods = t.mods end
end

set("en", {
	gi = { "Road", "Lane", "Street", "Yard", "Row", "Way", "Terrace", "Gate" },
	ind = { works = { "Works", "Foundry", "Forge", "Factory" }, quarry = { "Quarry", "Pit", "Stone" },
		mine = { "Colliery", "Pithead", "Mine", "Pit" }, farm = { "Farm", "Dairy", "Grange" }, mill = { "Mill", "Millrace" },
		brewery = { "Brewery", "Maltings", "Brewhouse" }, timber = { "Sawpit", "Timber", "Woodyard" } },
	fields = { "Longacre", "Broadfield", "Ten Acre", "Six Acre", "Longmead", "Cowleaze", "Oxleaze", "Rushmead",
		"Coldharbour", "Hollybush", "Furzefield", "Starveacre", "Stonecroft", "Bramblefield", "Middlefield", "Lammas",
		"Sheepcote", "Hayfield", "Dovecote", "Pightle", "Linchet", "Butts" },
	marks = { "Chapel", "School", "Smithy", "Inn", "Tollgate", "Pound", "Well", "Manor", "Lodge", "Vicarage", "Kiln",
		"Ropewalk", "Almshouse", "Pump" },
	lake = { "Lake", "Mere", "Lakeside", "Reed", "Boathouse" },
	indName = function(n) return { n .. " Gate", n .. " Road" } end,
	mods = { "Old", "New", "Little", "Great" },
})
set("usa", {
	gi = { "St", "Rd", "Ave", "Way", "Dr", "Ln" },
	ind = { works = { "Foundry", "Factory", "Works", "Mill" }, quarry = { "Quarry", "Stone", "Gravel" },
		mine = { "Mine", "Colliery", "Shaft" }, farm = { "Farm", "Ranch", "Dairy", "Homestead" }, mill = { "Mill", "Millrace" },
		brewery = { "Brewery", "Malt" }, timber = { "Lumber", "Sawmill", "Timber" } },
	fields = { "Homestead", "Cornfield", "Wheatfield", "Haymeadow", "Longmeadow", "Clover", "Sunflower", "Pasture",
		"Quail Run", "Meadowlark", "Bluestem", "Cottonwood", "Fox Run", "Deer Run", "Settlers", "Pioneer", "Wagon Wheel",
		"Split Rail" },
	marks = { "Schoolhouse", "Chapel", "Tavern", "Courthouse", "Post Office", "Grange", "Blacksmith", "Bell", "Lodge",
		"Toll", "Water Tower", "Fairground" },
	lake = { "Lake", "Lakeview", "Lakeside", "Cove", "Boathouse" },
	indName = function(n) return { n .. " Gate", n .. " Rd" } end,
	mods = { "Old", "New", "Little" },
})
set("de", {
	gi = { "-strasse", "-weg", "-gasse", "-platz", "-ring" },
	ind = { works = { "Hütten", "Werk", "Fabrik", "Giesserei" }, quarry = { "Steinbruch", "Gruben", "Kies" },
		mine = { "Zechen", "Schacht", "Bergwerks", "Stollen" }, farm = { "Hof", "Gutshof", "Meierei" }, mill = { "Mühlen" },
		brewery = { "Brauerei", "Brauhaus", "Mälzerei" }, timber = { "Sägewerk", "Holz", "Säge" } },
	fields = { "Langacker", "Breitenfeld", "Kreuzacker", "Heide", "Anger", "Brühl", "Espen", "Hufen", "Lehen", "Gewann",
		"Flur", "Klee", "Hafer", "Roggen", "Flachs", "Bienen", "Schäfer", "Rosen" },
	marks = { "Kapellen", "Schul", "Schmiede", "Krug", "Zoll", "Brunnen", "Pfarr", "Gut", "Forsthaus", "Ziegel", "Linden",
		"Kreuz", "Post" },
	lake = { "See", "Seeufer", "Schilf", "Bootshaus" },
})
set("nl", {
	gi = { "-straat", "-weg", "-laan", "-pad", "-kade" },
	ind = { works = { "Fabrieks", "Werf", "Smederij", "IJzer" }, quarry = { "Groeve", "Steen", "Zand" },
		mine = { "Mijn", "Schacht", "Kolen" }, farm = { "Hoeve", "Boerderij", "Zuivel" }, mill = { "Molen" },
		brewery = { "Brouwerij", "Brouwers", "Mout" }, timber = { "Zaagmolen", "Hout", "Timmer" } },
	fields = { "Akker", "Kamp", "Esch", "Brink", "Heide", "Kouter", "Made", "Hooiland", "Klaver", "Vlas", "Rogge", "Haver",
		"Tarwe", "Bijen", "Schapen", "Gors", "Weide" },
	marks = { "Kapel", "School", "Smids", "Herberg", "Tol", "Put", "Pastorie", "Kasteel", "Kerk", "Pomp", "Veer",
		"Steenoven" },
	lake = { "Meer", "Plas", "Riet" },
})
set("sv", {
	gi = { "-gatan", "-vägen", "-gränd", "-backen" },
	ind = { works = { "Bruks", "Verkstads", "Smedje", "Hytt" }, quarry = { "Brotts", "Sten", "Grus" },
		mine = { "Gruv", "Schakt", "Kol" }, farm = { "Gårds", "Mejeri" }, mill = { "Kvarn" },
		brewery = { "Bryggeri", "Brygghus", "Malt" }, timber = { "Såg", "Timmer", "Virkes" } },
	fields = { "Åker", "Gärdes", "Tegs", "Vret", "Hag", "Ängs", "Klöver", "Råg", "Havre", "Lin", "Bi", "Fårhus", "Ladu",
		"Lund", "Hed", "Mosse" },
	marks = { "Kapell", "Skol", "Smedje", "Krog", "Tull", "Brunns", "Präst", "Herrgårds", "Kyrk", "Post", "Tegelbruks" },
	lake = { "Sjö", "Vass", "Båthus" },
})
set("nb", {
	gi = { "-gata", "-veien", "-bakken", "-stien" },
	ind = { works = { "Verks", "Smie", "Fabrikk", "Hytte" }, quarry = { "Brudd", "Stein", "Grus" },
		mine = { "Gruve", "Sjakt", "Kull" }, farm = { "Gårds", "Meieri" }, mill = { "Mølle" },
		brewery = { "Bryggeri", "Brygger", "Malt" }, timber = { "Sag", "Tømmer", "Planke" } },
	fields = { "Åker", "Jorde", "Teig", "Eng", "Hage", "Kløver", "Rug", "Havre", "Lin", "Bie", "Seter", "Låve", "Lund",
		"Hei", "Myr", "Bø" },
	marks = { "Kapell", "Skole", "Smie", "Kro", "Toll", "Brønn", "Prest", "Herregårds", "Kirke", "Post", "Tegl" },
	lake = { "Vann", "Sjø", "Siv" },
})
set("fr", {
	gi = { { "Rue", "f" }, { "Chemin", "m" }, { "Avenue", "f" }, { "Allée", "f" }, { "Impasse", "f" } },
	ind = { works = { "de l'Usine", "des Forges", "de la Fonderie", "des Ateliers" },
		quarry = { "de la Carrière", "des Carriers", "de la Sablière" },
		mine = { "de la Mine", "du Puits", "des Mineurs", "du Carreau" }, farm = { "de la Ferme", "de la Métairie", "de la Laiterie" },
		mill = { "du Moulin" }, brewery = { "de la Brasserie", "des Brasseurs", "de la Malterie" },
		timber = { "de la Scierie", "des Bûcherons", "du Bois" } },
	fields = { "des Grands Champs", "du Long Champ", "des Prés", "de la Pâture", "des Sept Arpents", "des Noues",
		"de la Bergerie", "des Ruches", "du Pigeonnier", "des Blés", "des Avoines", "du Seigle", "du Lin", "des Trèfles",
		"de la Garenne", "des Friches", "du Clos", "des Vergers" },
	marks = { "de l'École", "de la Chapelle", "de la Forge", "de l'Auberge", "du Péage", "du Puits", "du Presbytère",
		"du Manoir", "de la Croix", "du Lavoir", "de la Tuilerie", "du Four", "de la Poste" },
	lake = { "du Lac", "de l'Étang", "des Roseaux" },
})
set("it", {
	gi = { { "Via", "f" }, { "Strada", "f" }, { "Viale", "m" }, { "Vicolo", "m" }, { "Largo", "m" } },
	ind = { works = { "delle Officine", "della Fabbrica", "della Fornace", "della Fonderia" },
		quarry = { "della Cava", "dei Cavatori", "della Ghiaia" }, mine = { "della Miniera", "del Pozzo", "dei Minatori" },
		farm = { "della Cascina", "della Fattoria", "del Caseificio" }, mill = { "del Mulino" },
		brewery = { "della Birreria", "dei Birrai", "del Malto" }, timber = { "della Segheria", "dei Boscaioli", "del Legname" } },
	fields = { "dei Campi Lunghi", "del Campo Grande", "dei Prati", "del Pascolo", "delle Vigne", "degli Orti", "del Fienile",
		"delle Api", "della Colombaia", "del Grano", "dell'Orzo", "del Lino", "dei Trifogli", "della Brughiera", "del Podere",
		"del Frutteto" },
	marks = { "della Scuola", "della Cappella", "della Fucina", "dell'Osteria", "del Dazio", "del Pozzo", "della Canonica",
		"della Villa", "della Croce", "del Lavatoio", "della Torre", "del Forno" },
	lake = { "del Lago", "dello Stagno", "delle Canne" },
})
set("es", {
	gi = { { "Calle", "f" }, { "Camino", "m" }, { "Avenida", "f" }, { "Travesía", "f" }, { "Paseo", "m" } },
	ind = { works = { "de la Fábrica", "de la Fundición", "de los Talleres", "de la Herrería" },
		quarry = { "de la Cantera", "de los Canteros", "de la Gravera" }, mine = { "de la Mina", "del Pozo", "de los Mineros" },
		farm = { "de la Granja", "del Cortijo", "de la Lechería" }, mill = { "del Molino" },
		brewery = { "de la Cervecería", "de los Cerveceros", "de la Maltería" },
		timber = { "del Aserradero", "de los Leñadores", "de la Madera" } },
	fields = { "de las Eras Largas", "del Campo Grande", "de los Prados", "del Pasto", "de las Viñas Viejas", "de los Huertos",
		"del Pajar", "de las Colmenas", "del Palomar", "del Trigo", "de la Cebada", "del Lino", "de los Tréboles", "del Brezal",
		"de la Dehesa Vieja", "del Olivar" },
	marks = { "de la Escuela", "de la Ermita", "de la Fragua", "de la Posada", "del Portazgo", "del Pozo", "de la Casa Rectoral",
		"del Palacio", "de la Cruz", "del Lavadero", "de la Torre", "del Horno" },
	lake = { "del Lago", "de la Laguna", "de los Juncos" },
})
set("pt", {
	gi = { { "Rua", "f" }, { "Travessa", "f" }, { "Caminho", "m" }, { "Largo", "m" }, { "Estrada", "f" } },
	ind = { works = { "da Fábrica", "da Fundição", "das Oficinas", "da Forja" },
		quarry = { "da Pedreira", "dos Canteiros", "do Areeiro" }, mine = { "da Mina", "do Poço", "dos Mineiros" },
		farm = { "da Quinta", "do Monte", "da Leitaria" }, mill = { "do Moinho" },
		brewery = { "da Cervejaria", "dos Cervejeiros", "da Maltaria" }, timber = { "da Serração", "dos Lenhadores", "da Madeira" } },
	fields = { "das Courelas", "do Campo Grande", "dos Lameiros", "do Pasto", "das Vinhas Velhas", "dos Quintais",
		"do Palheiro", "das Colmeias", "do Pombal", "do Trigo", "da Cevada", "do Linho", "dos Trevos", "da Charneca",
		"do Casal Velho", "do Olival" },
	marks = { "da Escola", "da Capela", "da Ferraria", "da Estalagem", "da Portagem", "do Poço", "da Residência Paroquial",
		"do Solar", "do Cruzeiro", "do Lavadouro", "da Torre", "do Forno" },
	lake = { "do Lago", "da Lagoa", "dos Juncos" },
})
set("ja", {
	gi = { "通り", "前", "町", "道" },
	ind = { works = { "工場", "製鉄", "鋳物" }, quarry = { "石切", "採石", "砂利" }, mine = { "鉱山", "炭坑", "坑口" },
		farm = { "牧場", "農場" }, mill = { "水車", "製粉" }, brewery = { "酒蔵", "醸造" }, timber = { "製材", "木場" } },
	fields = { "新田", "上田", "中田", "下田", "長田", "大畑", "小畑", "麦", "稲", "桑", "茶畑", "梅", "萩", "葦", "菜の花" },
	marks = { "学校", "寺", "神社", "宿", "関", "井戸", "鍛冶", "市場", "番所", "庄屋", "郵便局" },
	lake = { "湖", "池", "葦" },
	indName = function(n) return { n .. "前", n .. "通り" } end,
})
set("ja_r", {
	gi = { "-dōri", "mae", "machi", "michi" },
	ind = { works = { "Kōjō", "Seitetsu", "Imono" }, quarry = { "Ishikiri", "Saiseki", "Jari" },
		mine = { "Kōzan", "Tankō", "Kōguchi" }, farm = { "Bokujō", "Nōjō" }, mill = { "Suisha", "Seifun" },
		brewery = { "Sakagura", "Jōzō" }, timber = { "Seizai", "Kiba" } },
	fields = { "Shinden", "Kamida", "Nakada", "Shimoda", "Nagata", "Ōhata", "Kobata", "Mugi", "Ine", "Kuwa", "Chabatake",
		"Ume", "Hagi", "Ashi", "Nanohana" },
	marks = { "Gakkō", "Tera", "Jinja", "Shuku", "Seki", "Ido", "Kaji", "Ichiba", "Bansho", "Shōya", "Yūbinkyoku" },
	lake = { "Mizuumi", "Ike", "Ashi" },
	indName = function(n) return { n .. "-mae", n .. "-dōri" } end,
})
set("ru", {
	gi = { { "улица", "f" }, { "переулок", "m" }, { "проезд", "m" }, { "тупик", "m" } },
	ind = { works = { A("Заводская", "Заводской"), A("Фабричная", "Фабричный"), A("Литейная", "Литейный"), A("Кузнечная", "Кузнечный") },
		quarry = { A("Карьерная", "Карьерный"), A("Каменная", "Каменный"), A("Песчаная", "Песчаный") },
		mine = { A("Шахтёрская", "Шахтёрский"), A("Рудничная", "Рудничный"), A("Угольная", "Угольный") },
		farm = { A("Хуторская", "Хуторской"), A("Молочная", "Молочный"), A("Совхозная", "Совхозный") },
		mill = { A("Мельничная", "Мельничный") }, brewery = { A("Пивоваренная", "Пивоваренный"), A("Солодовая", "Солодовый") },
		timber = { A("Лесопильная", "Лесопильный"), A("Дровяная", "Дровяной") } },
	fields = { A("Ржаная", "Ржаной"), A("Овсяная", "Овсяный"), A("Пшеничная", "Пшеничный"), A("Льняная", "Льняной"),
		A("Сенная", "Сенной"), A("Конная", "Конный"), A("Пастушья", "Пастуший"), A("Пасечная", "Пасечный"), A("Озимая", "Озимый"),
		A("Покосная", "Покосный"), A("Клеверная", "Клеверный"), A("Гречишная", "Гречишный"), A("Выгонная", "Выгонный"),
		A("Хлебная", "Хлебный") },
	marks = { A("Школьная", "Школьный"), A("Часовенная", "Часовенный"), A("Трактирная", "Трактирный"), A("Почтовая", "Почтовый"),
		A("Колодезная", "Колодезный"), A("Поповская", "Поповский"), A("Барская", "Барский"), A("Ямская", "Ямской"),
		A("Монастырская", "Монастырский"), A("Кирпичная", "Кирпичный") },
	lake = { A("Озёрная", "Озёрный"), A("Прудовая", "Прудовый"), A("Камышовая", "Камышовый") },
})
set("ru_r", {
	gi = { { "ulitsa", "f" }, { "pereulok", "m" }, { "proyezd", "m" }, { "tupik", "m" } },
	ind = { works = { A("Zavodskaya", "Zavodskoy"), A("Fabrichnaya", "Fabrichny"), A("Liteynaya", "Liteyny"), A("Kuznechnaya", "Kuznechny") },
		quarry = { A("Karyernaya", "Karyerny"), A("Kamennaya", "Kamenny"), A("Peschanaya", "Peschany") },
		mine = { A("Shakhtyorskaya", "Shakhtyorsky"), A("Rudnichnaya", "Rudnichny"), A("Ugolnaya", "Ugolny") },
		farm = { A("Khutorskaya", "Khutorskoy"), A("Molochnaya", "Molochny"), A("Sovkhoznaya", "Sovkhozny") },
		mill = { A("Melnichnaya", "Melnichny") }, brewery = { A("Pivovarennaya", "Pivovarenny"), A("Solodovaya", "Solodovy") },
		timber = { A("Lesopilnaya", "Lesopilny"), A("Drovyanaya", "Drovyanoy") } },
	fields = { A("Rzhanaya", "Rzhanoy"), A("Ovsyanaya", "Ovsyany"), A("Pshenichnaya", "Pshenichny"), A("Lnyanaya", "Lnyanoy"),
		A("Sennaya", "Sennoy"), A("Konnaya", "Konny"), A("Pastushya", "Pastushy"), A("Pasechnaya", "Pasechny"), A("Ozimaya", "Ozimy"),
		A("Pokosnaya", "Pokosny"), A("Klevernaya", "Kleverny"), A("Grechishnaya", "Grechishny"), A("Vygonnaya", "Vygonny"),
		A("Khlebnaya", "Khlebny") },
	marks = { A("Shkolnaya", "Shkolny"), A("Chasovennaya", "Chasovenny"), A("Traktirnaya", "Traktirny"), A("Pochtovaya", "Pochtovy"),
		A("Kolodeznaya", "Kolodezny"), A("Popovskaya", "Popovsky"), A("Barskaya", "Barsky"), A("Yamskaya", "Yamskoy"),
		A("Monastyrskaya", "Monastyrsky"), A("Kirpichnaya", "Kirpichny") },
	lake = { A("Ozyornaya", "Ozyorny"), A("Prudovaya", "Prudovy"), A("Kamyshovaya", "Kamyshovy") },
})

---------------------------------------------------------------------------
-- 2026-10-14 (run 2026-10-13_2355_sqot: 42 stops renamed, 0 duplicates, but "Old Henley-in-Arden Road" too long and
-- "Bay Quay" clumsy; user: "more stop names would be great"): a length cap in characters, town names cut to a word,
-- pairs that say the same thing twice left out, more parts per theme and language.

M.MAX_CHARS = 28          -- characters (UTF-8) a stop name may have at most
M.TOWN_WORD = 12          -- town names longer than this: their first word (3-12 characters), else none

--- Characters of a UTF-8 string (continuation bytes not counted).
function M.chars(s)
	local _, n = tostring(s or ""):gsub("[^\128-\191]", "")
	return n
end

--- The part of a town name a stop name may use: the name (<= TOWN_WORD characters), its first word, or nil.
function M.townWord(t)
	if type(t) ~= "string" or t == "" then return nil end
	if M.chars(t) <= M.TOWN_WORD then return t end
	local w = t:match("^([^%s%-]+)")
	if w and M.chars(w) >= 3 and M.chars(w) <= M.TOWN_WORD then return w end
	return nil
end

-- spec words that already name the generic's kind of place (en / usa; "Bay Quay", "Pier Wharf", "Sea Strand")
local WATER_EDGE = { Quay = true, Wharf = true, Strand = true, Esplanade = true, Promenade = true, Parade = true,
	Beach = true, Pier = true, Harbour = true, Harbor = true, Bay = true, Shore = true, Bayshore = true, Lakeshore = true,
	Marina = true, Dock = true, Sands = true, Cove = true, Waterfront = true }
local HILL_WORDS = { Hill = true, Rise = true, Heights = true, Brow = true, Crest = true, Ridge = true, Summit = true,
	Hilltop = true, Knoll = true, Bluff = true, Overlook = true, Lookout = true, Vista = true, Prospect = true, View = true }
local VALLEY_WORDS = { Dale = true, Vale = true, Combe = true, Hollow = true, Dene = true, Glen = true, Valley = true,
	Bottom = true }
M.BAD_PAIRS = { en = true, usa = true }

--- true when spec word w and generic gen name the same kind of place (a clumsy pair) in classifier cls.
function M.badPair(cls, w, gen)
	if not M.BAD_PAIRS[cls or ""] or type(w) ~= "string" then return false end
	local g = type(gen) == "table" and gen[1] or gen
	if type(g) ~= "string" then return false end
	local lw = w:match("(%S+)$") or w
	for _, set in ipairs({ WATER_EDGE, HILL_WORDS, VALLEY_WORDS }) do
		if set[lw] and set[g] then return true end
	end
	return false
end

-- more parts per theme and language (appended to M.LANG[cls].specs / gens)
M.MORE = {
	en = { specs = {
		shore = { "Saltings", "Boatyard", "Seaview", "Shingle", "Fisherman's", "Netmakers", "Ferry", "Tide" },
		river = { "Wharf", "Osier", "Meadow", "Island", "Watermill", "Towpath", "Eel", "Otter", "Swan" },
		hill = { "Gallows", "Barrow", "Tor", "Cairn", "Belvedere", "Skyline", "Clifftop", "Larks" },
		valley = { "Watercress", "Millpond", "Coldwell", "Sheepwash", "Holloway", "Ashdown" },
		forest = { "Bluebell", "Woodcutters", "Charcoal", "Ranger's", "Wren", "Thrush", "Pheasant", "Acorn" },
		centre = { "Corn Exchange", "Town Hall", "Bridewell", "Priory", "Tithe", "Guild", "Butter", "Fleece", "Swan" },
		outskirts = { "Brickfield", "Withy", "Paddock", "Hopfield", "Copyhold", "Allotment", "Nursery", "Lavender" },
		station = { "Engine", "Wagon", "Coal", "Parcel", "Viaduct" } },
		gens = { shore = { "Row", "Steps", "Drive" }, river = { "Mews", "Reach", "Meadows" }, hill = { "Top", "Climb", "Edge" },
			valley = { "Lane", "Way", "Meadows" }, forest = { "Ride", "Lane", "Close", "Rise" },
			centre = { "Court", "Passage", "Arcade" }, outskirts = { "Crescent", "Avenue", "Green", "Mews" } } },
	usa = { specs = {
		shore = { "Seaside", "Sandpiper", "Pelican", "Gull", "Breakers", "Tidewater", "Clipper" },
		river = { "Riverview", "Willow", "Heron", "Rapids", "Flatboat", "Levee", "Canal" },
		hill = { "Mountain", "Skyline", "Panorama", "Bellevue", "Crestview", "Hawk" },
		forest = { "Pine Hill", "Cedar", "Timberline", "Elk", "Bear", "Owl" },
		centre = { "Grand", "State", "Union", "Elm", "Maple", "Central", "City Hall" },
		outskirts = { "Harvest", "Prairie View", "Windmill", "Silo", "Stagecoach", "Orchard" } },
		gens = { outskirts = { "Blvd", "Cir", "Ter" }, centre = { "Pl", "Ter" }, forest = { "Run", "Pass" } } },
	de = { specs = {
		shore = { "Möwen", "Segler", "Lotsen", "Bernstein", "Reet", "Kutter" },
		river = { "Weiden", "Auen", "Flösser", "Gerber", "Insel", "Kahn" },
		hill = { "Wein", "Rebberg", "Linden", "Kapellen", "Warte", "Gipfel" },
		forest = { "Eichen", "Buchen", "Köhler", "Specht", "Eulen", "Dachs" },
		centre = { "Rats", "Zunft", "Kloster", "Stadt", "Kaufmanns", "Linden" },
		outskirts = { "Ziegel", "Obst", "Garten", "Weiher", "Hopfen", "Scheunen" } },
		gens = { outskirts = { "-pfad", "-anger" }, centre = { "-steg" }, hill = { "-kamm" } } },
	nl = { specs = {
		shore = { "Duin", "Zeemans", "Strand", "Visschers" }, river = { "Wilgen", "Sluis", "Veer", "Molen" },
		centre = { "Kerk", "Markt", "Raadhuis", "Gilde" }, outskirts = { "Boomgaard", "Weide", "Polder", "Akker" } } },
	fr = { specs = {
		shore = { "des Mouettes", "des Goélands", "du Large", "des Sables", "des Marins" },
		river = { "des Saules", "de l'Île", "des Tanneurs", "des Mariniers" },
		hill = { "des Vignes", "du Mont", "de la Butte", "des Roches" },
		centre = { "des Tanneurs", "du Puits", "de la Halle", "des Arts" },
		outskirts = { "des Lilas", "des Roses", "du Moulin", "des Tuileries", "des Jardins" } } },
	it = { specs = {
		shore = { "dei Pescatori", "del Faro", "della Marina", "dei Gabbiani" }, river = { "del Mulino", "dei Salici" },
		centre = { "del Duomo", "della Fontana", "dei Mercanti" }, outskirts = { "degli Orti", "dei Vigneti", "delle Rose" } } },
	es = { specs = {
		shore = { "de los Pescadores", "del Faro", "de la Playa" }, river = { "del Molino", "de los Sauces" },
		centre = { "de la Fuente", "del Mercado", "de la Iglesia" }, outskirts = { "de las Huertas", "de los Olivos" } } },
	pt = { specs = {
		shore = { "dos Pescadores", "do Farol", "da Praia" }, river = { "do Moinho", "dos Salgueiros" },
		centre = { "da Fonte", "do Mercado", "da Igreja" }, outskirts = { "das Hortas", "dos Olivais" } } },
	sv = { specs = { shore = { "Fiskar", "Båt", "Brygg" }, forest = { "Tall", "Gran", "Björk" }, centre = { "Kyrk", "Torg", "Råd" } } },
	nb = { specs = { shore = { "Fisker", "Båt", "Brygge" }, forest = { "Furu", "Gran", "Bjørk" }, centre = { "Kirke", "Torg" } } },
}
for cls, more in pairs(M.MORE) do
	local L = M.LANG[cls]
	if L then
		for part, byTheme in pairs(more) do
			L[part] = L[part] or {}
			for th, words in pairs(byTheme) do
				local list = L[part][th]
				if list then
					local have = {}
					for _, w in ipairs(list) do have[type(w) == "table" and w[1] or w] = true end
					for _, w in ipairs(words) do
						-- (romance generics carry a gender: the extra generics are left to the lists with plain words)
						if not have[w] and (part == "specs" or type(list[1]) ~= "table") then list[#list + 1] = w end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Bridge stops (2026-10-14, NEXT_PHASE_BRIEF 46; user: "if a bus stop is on a bridge, we could use that as a big
-- cue"): a stop on a bridge edge (its street edge's BaseEdge `type` BRIDGE, ot_engine.stopBridge; a stop within
-- BRIDGE_ON_M of a bridge edge when the stop's own edge can't be read) takes the bridge theme before every other:
-- "<River> Bridge" (the generated river name nearby), "<Town> Bridge", "Old Bridge" / "New Bridge" (the older form
-- first before BRIDGE_OLD_YEAR), "Bridge Street" ...; a stop off the bridge, within BRIDGE_END_M of a bridge edge's
-- end, "Bridge End" / "An der Brücke" / "Tête de Pont" ... Per list language; unique map-wide as every stop name,
-- the word-variety rule among the bridge names; none left: the stop's other themes.

M.BRIDGE_ON = true
M.BRIDGE_ON_M = 6         -- m: a stop this near a bridge edge is on it (when the stop's own edge read fails)
M.BRIDGE_END_M = 60       -- m: a stop off the bridge this near a bridge edge's end: "Bridge End"
M.BRIDGE_OLD_YEAR = 1900  -- game year before which "Old Bridge" comes before "New Bridge"
M.BRIDGE_MAX_EDGES = 200  -- bridge chords looked at per stop

local function deBr(t) local a = deAdj(t); return a and (a .. " Brücke") or nil end
local function noSpace(f) return function(t) if t:find("%s") then return nil end return f(t) end end

-- forms per classifier: river (%r: the river's name), town (%t: the town's word), old, new, street, ["end"] (a stop
-- just off the bridge). A string with %r / %t, or a function(word) returning the name or nil.
M.BRIDGE = {
	en = { river = { "%r Bridge" }, town = { "%t Bridge" }, old = { "Old Bridge" }, new = { "New Bridge" },
		street = { "Bridge Street", "Bridge Road", "Bridge Lane", "Bridge Approach" },
		["end"] = { "Bridge End", "Bridgefoot", "%r Bridge End", "Bridge Foot" } },
	usa = { river = { "%r Bridge", "%r River Bridge" }, town = { "%t Bridge" }, old = { "Old Bridge" }, new = { "New Bridge" },
		street = { "Bridge St", "Bridge Rd", "Bridge Ave" },
		["end"] = { "Bridge End", "Bridge Plaza", "Bridge Landing", "Bridge Approach" } },
	de = { river = { noSpace(function(r) return r .. "brücke" end) }, town = { deBr }, old = { "Alte Brücke" },
		new = { "Neue Brücke" }, street = { "Brückenstrasse", "Brückenweg", "Brückenplatz", "Brückengasse" },
		["end"] = { "An der Brücke", "Am Brückenkopf", "Brückenkopf", "Vor der Brücke" } },
	nl = { river = { noSpace(function(r) return r .. "brug" end) }, town = { noSpace(function(t) return t .. "brug" end) },
		old = { "Oude Brug" }, new = { "Nieuwe Brug" }, street = { "Brugstraat", "Brugweg", "Bruglaan" },
		["end"] = { "Bij de Brug", "Brughoofd", "Bruggenhoofd" } },
	sv = { river = { noSpace(function(r) return r .. "bron" end) }, town = { noSpace(function(t) return scand(t, "bron") end) },
		old = { "Gamla bron" }, new = { "Nya bron" }, street = { "Brogatan", "Brovägen", "Brogränd" },
		["end"] = { "Vid bron", "Brofästet", "Brobacken" } },
	nb = { river = { noSpace(function(r) return r .. "brua" end) }, town = { noSpace(function(t) return scand(t, "brua") end) },
		old = { "Gamlebrua" }, new = { "Nybrua" }, street = { "Brugata", "Bruveien", "Brubakken" },
		["end"] = { "Ved brua", "Brufestet", "Bruhaugen" } },
	fr = { river = { function(r) return "Pont " .. frDe(r) end }, town = { function(t) return "Pont " .. frDe(t) end },
		old = { "Vieux Pont" }, new = { "Pont Neuf" }, street = { "Rue du Pont", "Quai du Pont", "Place du Pont" },
		["end"] = { "Tête de Pont", "Bout du Pont", "Au Pont" } },
	it = { river = { "Ponte %r" }, town = { "Ponte di %t" }, old = { "Ponte Vecchio" }, new = { "Ponte Nuovo" },
		street = { "Via del Ponte", "Piazza del Ponte", "Largo del Ponte" },
		["end"] = { "Capo di Ponte", "Testa del Ponte", "Al Ponte" } },
	es = { river = { "Puente de %r" }, town = { "Puente de %t" }, old = { "Puente Viejo" }, new = { "Puente Nuevo" },
		street = { "Calle del Puente", "Plaza del Puente", "Paseo del Puente" },
		["end"] = { "Cabeza del Puente", "Junto al Puente", "Al Puente" } },
	pt = { river = { "Ponte de %r" }, town = { "Ponte de %t" }, old = { "Ponte Velha" }, new = { "Ponte Nova" },
		street = { "Rua da Ponte", "Largo da Ponte", "Travessa da Ponte" },
		["end"] = { "Cabeça da Ponte", "Junto à Ponte", "Pé da Ponte" } },
	ja = { river = { "%r橋", "%r大橋" }, town = { "%t大橋", "%t橋" }, old = { "旧橋" }, new = { "新橋" },
		street = { "大橋", "橋通り", "橋前" }, ["end"] = { "橋詰", "橋本", "橋口" } },
	ja_r = { river = { "%r-bashi", "%r Ōhashi" }, town = { "%t Ōhashi", "%t-bashi" }, old = { "Kyūbashi" }, new = { "Shinbashi" },
		street = { "Ōhashi", "Hashi-dōri", "Hashi-mae" }, ["end"] = { "Hashizume", "Hashimoto", "Hashiguchi" } },
	ru = { river = { function(r) return "Мост через " .. ruAcc(r) end }, town = { function(t) return "Мост на " .. ruAcc(t) end },
		old = { "Старый мост" }, new = { "Новый мост" },
		street = { "Мостовая улица", "Мостовой переулок", "Мостовой проезд", "Мостовая площадь" },
		["end"] = { "У моста", "Предмостная площадь", "Предмостная улица" } },
	ru_r = { river = { "Most cherez %r" }, town = { "Most na %t" }, old = { "Stary most" }, new = { "Novy most" },
		street = { "Mostovaya ulitsa", "Mostovoy pereulok", "Mostovoy proyezd", "Mostovaya ploshchad" },
		["end"] = { "U mosta", "Predmostnaya ploshchad", "Predmostnaya ulitsa" } },
}

-- distance from (x, y) to segment a-b
local function segDist(x, y, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = 0
	if l2 > 1e-9 then t = math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / l2)) end
	local px, py = ax + dx * t, ay + dy * t
	return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
end

--- The bridge cue of a stop at (x, y) from info (ot_engine.stopBridge: { read = the stop's own edge was found, on =
--- that edge is a bridge, bridges = { { x0, y0, x1, y1, ends = { {x, y}, {x, y} } } } (bridge edges around, as chords) }
--- or nil). Returns "on" | "end" | nil and how: "edge" (the stop's edge is a bridge), "near" (no edge read, within
--- BRIDGE_ON_M of a bridge edge), "end" (off the bridge, within BRIDGE_END_M of a bridge end).
function M.bridgeCue(info, x, y)
	if not M.BRIDGE_ON or type(info) ~= "table" or not tonumber(x) or not tonumber(y) then return nil, nil end
	if info.read and info.on then return "on", "edge" end
	local dOn, dEnd = math.huge, math.huge
	for i, b in ipairs(info.bridges or {}) do
		if i > M.BRIDGE_MAX_EDGES then break end
		if tonumber(b[1]) and tonumber(b[2]) and tonumber(b[3]) and tonumber(b[4]) then
			local d = segDist(x, y, b[1], b[2], b[3], b[4])
			if d == d and d < dOn then dOn = d end
		end
		for _, p in ipairs(b.ends or {}) do
			if tonumber(p[1]) and tonumber(p[2]) then
				local d = math.sqrt((x - p[1]) ^ 2 + (y - p[2]) ^ 2)
				if d == d and d < dEnd then dEnd = d end
			end
		end
	end
	if not info.read and dOn <= M.BRIDGE_ON_M then return "on", "near" end
	if dEnd <= M.BRIDGE_END_M then return "end", "end" end
	return nil, nil
end

local function bfill(f, v)
	if type(f) == "function" then
		if v == nil then return nil end
		local ok, n = pcall(f, v)
		return ok and type(n) == "string" and n or nil
	end
	if type(f) ~= "string" then return nil end
	if f:find("%r", 1, true) or f:find("%t", 1, true) then
		if v == nil then return nil end
		return (f:gsub("%%[rt]", function() return v end))
	end
	return f
end

--- The bridge names of a stop, in order: { { name, form } }; site.bridge = "on" | "end", site.riverName (the river's
--- name or nil), site.town, site.year (game year or nil). cls without bridge forms: {}.
function M.bridgeNames(cls, site)
	local B = M.BRIDGE[cls or ""]
	local out = {}
	if B == nil or site == nil or (site.bridge ~= "on" and site.bridge ~= "end") then return out end
	local function put(list, form, v)
		for _, f in ipairs(list or {}) do
			local n = bfill(f, v)
			if n then out[#out + 1] = { n, form } end
		end
	end
	local river = type(site.riverName) == "string" and site.riverName ~= "" and site.riverName or nil
	if river and M.chars(river) > M.TOWN_WORD then river = M.townWord(river) end
	if site.bridge == "end" then
		put(B["end"], "end", river)
		put(B.street, "street")
		return out
	end
	local early = tonumber(site.year) ~= nil and site.year < M.BRIDGE_OLD_YEAR
	put(B.river, "river", river)
	put(B.town, "town", M.townWord(site.town))
	put(early and B.old or B.new, early and "old" or "new")
	put(early and B.new or B.old, early and "new" or "old")
	put(B.street, "street")
	return out
end

M.THEMES = { "bridge", "industry", "station", "shore", "river", "hill", "valley", "forest", "centre", "outskirts" }

---------------------------------------------------------------------------
-- composing

local function genWord(gen) return type(gen) == "table" and gen[1] or gen end

-- one name from a spec word w (or table) and a generic gen of language L; sep = the spec stands apart (compound
-- languages' compass / height words); nil when the pair doesn't make a name
local function compose(L, w, gen, sep)
	local j = L.join
	if j == "space" then
		if type(w) ~= "string" then return nil end
		local g = genWord(gen)
		local lastW, firstG = w:match("(%S+)$"), g:match("^(%S+)")
		if lastW == firstG or w == g then return nil end
		return w .. " " .. g
	elseif j == "compound" then
		if type(w) ~= "string" then return nil end
		local g = genWord(gen)
		if sep then
			local word = (L.indef and L.indef[g]) or (g:sub(1, 1) == "-" and g:sub(2)) or g
			return w .. " " .. word
		end
		if g:sub(1, 1) == "-" then
			local suf = g:sub(2)
			-- (no "Bergberg": the stem already ends in the suffix)
			if NM.lower(w):sub(-#suf) == suf then return nil end
			return w .. suf
		end
		return w .. " " .. g
	elseif j == "romance" then
		if type(gen) ~= "table" then return nil end
		if type(w) == "table" then
			local adj = w[gen[2]]
			return adj and (gen[1] .. " " .. adj) or nil
		end
		return gen[1] .. " " .. w
	elseif j == "adj" then
		if type(gen) ~= "table" or type(w) ~= "table" then return nil end
		local adj = w[gen[2]]
		return adj and (adj .. " " .. gen[1]) or nil
	elseif j == "concat" then
		if type(w) ~= "string" then return nil end
		local g = genWord(gen)
		if w == g then return nil end
		-- (romanised: "Matsu" .. "zaka" -> "Matsuzaka"; "-dōri" keeps its hyphen; an own town "Ōgaki-" .. "-dōri" one)
		if w:sub(-1) == "-" and g:sub(1, 1) == "-" then return w .. g:sub(2) end
		return w .. g
	end
	return nil
end
M.compose = compose

--- The spec groups of theme th for a stop site (ranked: { kind, words, rank, sep }); see the header for what each kind
--- reads. site = { toward = town name or nil, ind = kind or nil, trees = { species }, compass = "n"|..., high = bool,
--- town = own name, waterName = the generated name of the river / lake beside it or nil, claimName = the town's
--- leftover named-feature claim (ot_placename.leftClaim) or nil }.
function M.groups(L, th, site)
	local out = {}
	local function add(kind, words, rank, sep)
		if words and #words > 0 then out[#out + 1] = { kind = kind, words = words, rank = rank, sep = sep } end
	end
	local out_ = th == "outskirts"
	-- the industry theme: the works' own words first ("Works Road", "Quarry Lane"); beside it in any theme later
	if site.ind and L.ind and L.ind[site.ind] then
		add("ind", L.ind[site.ind], (th == "industry" and -2) or ((out_ or th == "station") and -1) or 3)
	end
	if th == "industry" then
		if site.compass and L.compass and L.compass[site.compass] then add("compass", { L.compass[site.compass] }, 4, L.sepCompass) end
		local tw = M.townWord(site.town)
		if tw and L.own then add("own", { type(L.own) == "function" and L.own(tw) or tw }, 5) end
		return out
	end
	-- (trees grow everywhere: every theme, the forest's first, the station's and the shore's last)
	local treeRank = ({ forest = 0, valley = 1, river = 1.5, hill = 2, outskirts = 2.5, centre = 6, station = 6, shore = 5 })[th]
	if treeRank and L.tree then
		local words = {}
		for _, s in ipairs(site.trees or {}) do
			local w = L.tree[s]
			if w then words[#words + 1] = w end
		end
		add("tree", words, treeRank)
	end
	-- (generated names, 2026-10-14: the named river / lake beside the stop first: "Avon Street", "Lahnweg")
	if site.waterName and (th == "river" or th == "shore") then
		local w = site.waterName
		if L.join == "romance" and type(L.own) == "function" then w = L.own(w) end
		add("water", { w }, -0.5)
	end
	-- (NEXT_PHASE_BRIEF 53 Part B: the town's leftover named-feature claim, a river / lake its name doesn't carry, before
	-- the theme's generic words: "Glaven Lane"; the driver sets it while no stop name carries it)
	if site.claimName and th ~= "industry" then
		local w = site.claimName
		if L.join == "romance" and type(L.own) == "function" then w = L.own(w) end
		add("claim", { w }, 0.4)
	end
	-- (a lake shore: the lake's words before the sea's)
	if th == "shore" and site.lake and L.lake then add("lake", L.lake, 0) end
	add("theme", L.specs and L.specs[th], th == "forest" and 1.5 or ((th == "shore" and site.lake) and 2.5 or 0.5))
	if site.compass and L.compass and L.compass[site.compass] then
		add("compass", { L.compass[site.compass] }, out_ and 1 or 5, L.sepCompass)
	end
	if site.high and L.high then
		if L.join == "romance" then
			add("high", { L.high }, th == "hill" and 1.5 or 4)
		else
			add("high", L.high, th == "hill" and 1.5 or 4, L.sepHigh)
		end
	end
	-- old field / farm names (the outskirts' first) and landmarks (the centre's first): many stops, few duplicates
	if L.fields then add("field", L.fields, (out_ and 2) or ((th == "valley" or th == "hill") and 4) or 5.5) end
	if L.marks then add("mark", L.marks, ((th == "centre" or th == "station") and 2) or 5) end
	local tw = M.townWord(site.town)
	if tw and L.own then
		local w = type(L.own) == "function" and L.own(tw) or tw
		add("own", { w }, (th == "shore" or th == "river" or th == "hill" or th == "valley" or th == "forest") and 7 or 8)
	end
	return out
end

-- climate fit (2026-10-14, NEXT_PHASE_BRIEF 49)
M.LAKE_NEAR_M = 1500      -- m: the driver's survey read (ot_mapshape.waterNear): no lake this near -> site.noLake
M.MAX_PROPER = 6          -- proper names blanked out of a candidate before the word checks

local function blank(name, proper)
	local s = name
	for i, p in ipairs(proper) do
		if i > M.MAX_PROPER then break end
		local a, b = s:find(p, 1, true)
		if a then s = s:sub(1, a - 1) .. " " .. s:sub(b + 1) end
	end
	return s
end

--- Does candidate name fit the stop's site? Returns nil when it does, else "climate:<word>" (ot_climate.wordMisfit,
--- site.climate) or "lake:<word>" (ot_climate.lakeMisfit, site.noLake). kind: the candidate's kind (bridge names are
--- never checked); proper: the site's proper names (town, neighbour, water, river, industry), not checked.
function M.fits(cls, name, kind, site, proper)
	if site == nil or type(name) ~= "string" then return nil end
	if type(kind) == "string" and kind:sub(1, 7) == "bridge:" then return nil end
	local ck = site.climate
	if ck == nil and not site.noLake then return nil end
	local s = blank(name, proper or {})
	if ck then
		local w = CL.wordMisfit(s, ck, cls)
		if w then return "climate:" .. w end
	end
	if site.noLake and site.lake ~= true then
		local w = CL.lakeMisfit(s, cls)
		if w then return "lake:" .. w end
	end
	return nil
end

--- The ordered candidates of a stop: { { name, theme, kind = "real"|"solo"|"toward"|<group kind>, gen } }. cls = the
--- name list's classifier (ot_names.classOf), themes = ot_names.stopThemes(site) (ranked), site (M.groups plus seed),
--- streets = the list's streets.lua (real names first), cache (per cls / theme real names).
function M.candidates(cls, themes, site, streets, cache)
	local L = M.LANG[cls or ""]
	local out, seen = {}, {}
	local drop = { climate = 0, lake = 0 }
	if L == nil then return out, drop end
	site = site or {}
	local seed = site.seed or 1
	-- (climate fit: the site's proper names stay out of the word checks, longest first)
	local proper = {}
	for _, p in ipairs({ site.town, site.toward, site.waterName, site.riverName, site.indName, site.claimName }) do
		if type(p) == "string" and p ~= "" then proper[#proper + 1] = p end
	end
	table.sort(proper, function(a, b) if #a ~= #b then return #a > #b end return a < b end)
	local function add(name, th, kind, gen, spec)
		if #out >= M.MAX_CAND then return end
		if type(name) == "string" and name ~= "" and #name <= M.MAX_LEN and M.chars(name) <= M.MAX_CHARS and not seen[name] then
			seen[name] = true
			local why = M.fits(cls, name, kind, site, proper)
			if why then
				local k = why:match("^(%a+)")
				drop[k] = (drop[k] or 0) + 1
				return
			end
			out[#out + 1] = { name = name, theme = th, kind = kind, gen = gen, spec = spec }
		end
	end
	local solos, reals = {}, {}
	-- (2026-10-14, run 2026-10-13_2355_sqot "Old Henley-in-Arden Road": a long town name gives its first word or nothing)
	local tw = M.townWord(site.toward)
	local toward = (tw and L.toward) and L.toward(tw) or nil
	for _, th in ipairs(themes or {}) do
		-- (bridge stops, 2026-10-14: the bridge's own names, nothing composed)
		if th == "bridge" then
			for _, b in ipairs(M.bridgeNames(cls, site)) do add(b[1], th, "bridge:" .. b[2], b[2]) end
		end
		-- the industry's own name ("Crop Farm Gate") leads the industry theme
		if th == "industry" and site.indName and L.indName then
			for _, n in ipairs(L.indName(site.indName)) do add(n, th, "indName", "indName") end
		end
		-- the street toward a neighbour town: first for the outskirts (and a facing stop of any theme, after its theme)
		if toward and th == "outskirts" then for _, n in ipairs(toward) do add(n, th, "toward", "toward") end end
		local tmp = {}
		for _, grp in ipairs(M.groups(L, th, site)) do
			for si, w in ipairs(grp.words) do
				for ki, gen in ipairs((L.gens and L.gens[th]) or {}) do
					local nm = (not M.badPair(cls, w, gen)) and compose(L, w, gen, grp.sep) or nil
					if nm then
						local rank = grp.rank + si * 0.3 + ki * 0.25 + M.JITTER * rng.unit(seed, nm)
						tmp[#tmp + 1] = { nm, grp.kind, genWord(gen), rank, type(w) == "string" and w or nil }
						-- (size / age pairs, later: "Old Mill Lane", "Малая Лесная улица")
						if L.mods and (grp.kind == "theme" or grp.kind == "tree" or grp.kind == "field" or grp.kind == "mark") then
							for mi, m in ipairs(L.mods) do
								local mn
								if type(m) == "table" then
									mn = type(gen) == "table" and m[gen[2]] and (m[gen[2]] .. " " .. nm) or nil
								else
									mn = m .. " " .. nm
								end
								if mn then tmp[#tmp + 1] = { mn, grp.kind, genWord(gen), rank + M.MOD_RANK + mi * 0.5, type(w) == "string" and w or nil } end
							end
						end
					end
				end
			end
		end
		table.sort(tmp, function(a, b)
			if a[4] ~= b[4] then return a[4] < b[4] end
			return a[1] < b[1]
		end)
		for _, c in ipairs(tmp) do add(c[1], th, c[2], c[3], c[5]) end
		if toward and th ~= "outskirts" and th ~= "industry" and th ~= "bridge" then for _, n in ipairs(toward) do add(n, th, "toward", "toward") end end
		for _, n in ipairs((L.solos and L.solos[th]) or {}) do solos[#solos + 1] = { n, th } end
		local real
		local key = tostring(cls) .. ":" .. th
		if cache then real = cache[key] end
		if real == nil then
			real = {}
			local th0 = NM.STOP[cls] and NM.STOP[cls][th]
			if th0 and type(streets) == "table" then
				for _, n in ipairs(NM.stopCandidates(cls, th, streets)) do real[#real + 1] = n end
			end
			if cache then cache[key] = real end
		end
		for _, n in ipairs(real) do reals[#reals + 1] = { n, th } end
	end
	-- (run 2026-10-13_2240_sqot-dev: every stop took a real list name, which the game hands out to new stops too, "The
	-- Grove" twice. Now the composed names come first; the stand-alone and real names only when none is left, each once
	-- on the map: `used` holds every name the map has)
	for _, e in ipairs(solos) do add(e[1], e[2], "solo", e[1]) end
	for _, e in ipairs(reals) do add(e[1], e[2], "real", "-") end
	return out, drop
end

--- The stop's name: its first candidate not in `used` (every station group name on the map, read live, plus the names
--- sent and not yet applied). The themes are the spot's (the industry theme first when an industry is near); no
--- fallback themes: nothing unique and fitting -> nil (the stop keeps the game's name, `why=noUnique`). Returns name,
--- theme, info = { kind, gen, left (unused candidates after this one), total } or nil, nil, info.
function M.themesFor(themes, site)
	local th2, seen = {}, {}
	-- (a stop on or just off a bridge: the bridge theme first, before an industry beside it)
	if site and (site.bridge == "on" or site.bridge == "end") then th2[1], seen.bridge = "bridge", true end
	if site and site.ind then th2[#th2 + 1], seen.industry = "industry", true end
	local n0 = #th2
	for _, t in ipairs(themes or {}) do if not seen[t] then seen[t] = true; th2[#th2 + 1] = t end end
	-- (a spot without a theme of its own: the outskirts' names, as the residential street it is)
	if #th2 == n0 then th2[#th2 + 1] = "outskirts" end
	return th2
end

-- (2026-10-14, NEXT_PHASE_BRIEF 45: stop names vary their suffixes: among the first VARY_N unused candidates, each use of
-- a candidate's last word by a name on the map already moves it VARY_RANK places down: "Mill Lane" after two "... Road")
M.VARY_N = 6
M.VARY_RANK = 2
M.MAX_USED = 4000         -- map names looked at for the last words

local function lastWord(name)
	local w = tostring(name or ""):match("([^%s%-]+)%s*$")
	return w and NM.lower(w) or ""
end

function M.pick(cls, themes, site, streets, used, cache)
	used = used or {}
	local c, drop = M.candidates(cls, M.themesFor(themes, site), site, streets, cache)
	local first, left = {}, 0
	-- (bridge stops: while a bridge name is left, the variety window holds only bridge names: the bridge stays the cue)
	local onlyTheme = nil
	for _, e in ipairs(c) do
		if not used[e.name] then
			if left == 0 and e.theme == "bridge" then onlyTheme = "bridge" end
			if #first < M.VARY_N and (onlyTheme == nil or e.theme == onlyTheme) then first[#first + 1] = e end
			left = left + 1
		end
	end
	if #first == 0 then return nil, nil, { total = #c, left = 0, drop = drop } end
	local pick = first[1]
	if #first > 1 then
		local counts, n = {}, 0
		for nm in pairs(used) do
			n = n + 1
			if n > M.MAX_USED then break end
			if type(nm) == "string" then
				local w = lastWord(nm)
				counts[w] = (counts[w] or 0) + 1
			end
		end
		-- (over MAX_USED names the count would depend on the table's order: no variation then)
		if n <= M.MAX_USED then
			local bestS = math.huge
			for i, e in ipairs(first) do
				local sc = i + M.VARY_RANK * (counts[lastWord(e.name)] or 0)
				if sc < bestS then pick, bestS = e, sc end
			end
		end
	end
	return pick.name, pick.theme, { kind = pick.kind, gen = pick.gen, left = left - 1, total = #c, drop = drop }
end

---------------------------------------------------------------------------
-- New player stations next to an industry (2026-10-13, user: "stations next to a factory should use the factory naming
-- as a cue"): a new rail / harbour / bus station within STATION_IND_R of an industry and nearer to it than to its town's
-- centre gets "<Town> Works" / "<Town> Quarry" / "<Town> Docks" (by the industry's kind; a harbour station Docks first)
-- or "<Industry> Halt" (the industry's own short name); same rules as the stops (new player builds, never a renamed
-- one, unique map-wide; else the game's name).
M.STATION_IND_R = 400
M.STATION = {
	en = { works = "%s Works", quarry = "%s Quarry", mine = "%s Colliery", farm = "%s Farm", mill = "%s Mills",
		brewery = "%s Brewery", timber = "%s Sawmills", docks = "%s Docks", halt = "%s Halt" },
	usa = { works = "%s Works", quarry = "%s Quarry", mine = "%s Mine", farm = "%s Farm", mill = "%s Mills",
		brewery = "%s Brewery", timber = "%s Lumber Yard", docks = "%s Harbor", halt = "%s Station" },
	de = { works = "%s-Werk", quarry = "%s-Steinbruch", mine = "%s-Zeche", farm = "%s-Gut", mill = "%s-Mühle",
		brewery = "%s-Brauerei", timber = "%s-Sägewerk", docks = "%s-Hafen", halt = "Haltepunkt %s" },
	nl = { works = "%s-Fabriek", quarry = "%s-Groeve", mine = "%s-Mijn", farm = "%s-Hoeve", mill = "%s-Molen",
		brewery = "%s-Brouwerij", timber = "%s-Zagerij", docks = "%s-Haven", halt = "Halte %s" },
	sv = { works = "%s bruk", quarry = "%s stenbrott", mine = "%s gruva", farm = "%s gård", mill = "%s kvarn",
		brewery = "%s bryggeri", timber = "%s såg", docks = "%s hamn", halt = "%s hållplats" },
	nb = { works = "%s verk", quarry = "%s steinbrudd", mine = "%s gruve", farm = "%s gård", mill = "%s mølle",
		brewery = "%s bryggeri", timber = "%s sag", docks = "%s havn", halt = "%s holdeplass" },
	fr = { works = "%s-Usine", quarry = "%s-Carrière", mine = "%s-Mine", farm = "%s-Ferme", mill = "%s-Moulin",
		brewery = "%s-Brasserie", timber = "%s-Scierie", docks = "%s-Port", halt = "Halte %s" },
	it = { works = "%s Officine", quarry = "%s Cava", mine = "%s Miniera", farm = "%s Fattoria", mill = "%s Mulino",
		brewery = "%s Birreria", timber = "%s Segheria", docks = "%s Porto", halt = "Fermata %s" },
	es = { works = "%s-Fábrica", quarry = "%s-Cantera", mine = "%s-Mina", farm = "%s-Granja", mill = "%s-Molino",
		brewery = "%s-Cervecera", timber = "%s-Aserradero", docks = "%s-Puerto", halt = "Apeadero %s" },
	pt = { works = "%s-Fábrica", quarry = "%s-Pedreira", mine = "%s-Mina", farm = "%s-Quinta", mill = "%s-Moinho",
		brewery = "%s-Cervejaria", timber = "%s-Serração", docks = "%s-Cais", halt = "Apeadeiro %s" },
	ja = { works = "%s工場前", quarry = "%s採石場", mine = "%s鉱山", farm = "%s牧場", mill = "%s製粉所",
		brewery = "%s酒造", timber = "%s製材所", docks = "%s港", halt = "%s前" },
	ja_r = { works = "%s Kōjō-mae", quarry = "%s Saisekijō", mine = "%s Kōzan", farm = "%s Bokujō", mill = "%s Seifunjo",
		brewery = "%s Shuzō", timber = "%s Seizaijo", docks = "%s-kō", halt = "%s-mae" },
	ru = { works = "%s-Заводская", quarry = "%s-Карьер", mine = "%s-Шахта", farm = "%s-Хутор", mill = "%s-Мельница",
		brewery = "%s-Пивзавод", timber = "%s-Лесозавод", docks = "%s-Порт", halt = "Платформа %s" },
	ru_r = { works = "%s-Zavodskaya", quarry = "%s-Karyer", mine = "%s-Shakhta", farm = "%s-Khutor", mill = "%s-Melnitsa",
		brewery = "%s-Pivzavod", timber = "%s-Lesozavod", docks = "%s-Port", halt = "Platforma %s" },
}

local function fill(fmt, t) return (fmt:gsub("%%s", function() return t end)) end

--- A new station's name beside an industry: cls, town (its name), ind (M.indKind), indName (short, or nil), harbour
--- (bool: a harbour station: Docks first), used ({ [name] = true }). Returns name, form ("docks" | <ind> | "halt") or nil.
function M.stationName(cls, town, ind, indName, harbour, used)
	local L = M.STATION[cls or ""] or M.STATION.en
	used = used or {}
	local order = {}
	if harbour then order[#order + 1] = { "docks", town } end
	if ind and L[ind] then order[#order + 1] = { ind, town } end
	if indName then order[#order + 1] = { "halt", indName } end
	if not harbour then order[#order + 1] = { "docks", nil } end
	for _, o in ipairs(order) do
		if o[2] and type(o[2]) == "string" and o[2] ~= "" then
			local n = fill(L[o[1]], o[2])
			if #n <= M.MAX_LEN and not used[n] then return n, o[1] end
		end
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- Street sections (2026-10-14, user: "if possible, it would be cool if stops along the same section of street are smart
-- enough to know, and could use descriptions and variations off that, like Bay Quay North, Old Bay Quay etc."): a
-- section is the chain of street edges through the stop that continues through nodes deflecting less than
-- SECTION_DEG (M.section, on the street graph around the stop, SECTION_MAX m each way); a stop's base is the nearest
-- named base on that chain within SECTION_MAX m of it. The first named stop on a
-- section is its base (the driver saves { name, x, y, height }, ot_saved `sb`); a later stop on the same section
-- (within SECTION_ON m of the chain) takes a variant of the base's name (M.variants): the compass from the base
-- ("Bay Quay North"), higher / lower ("Upper Bay Quay"), nearer the centre / farther out ("Old" / "New Bay Quay"),
-- the spot's landmark ("Bay Quay (Chapel)"), per list language (de Nord / Ober- / Alt-, fr Nord / (Haut) / (Ancien),
-- ja 北 / 上 / 旧 ...). Unique map-wide as every stop name; no variant left: the normal pick.

local OGs = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local Gs = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

M.SECTION_DEG = 35
M.SECTION_MAX = 1200
M.SECTION_SNAP = 40       -- m: the stop's edge at most this far
M.SECTION_ON = 30         -- m: a base this near the chain lies on the section
M.SECTION_STEPS = 80      -- edges followed at most
M.VAR_ALONG = 120         -- m along the section from the base: a compass variant
M.VAR_DZ = 8              -- m higher / lower than the base: Upper / Lower
M.VAR_CORE = 100          -- m nearer the centre / farther out than the base: Old / New
M.VAR_FAR = 400           -- m along from the base: its far end ("Bay Road End", "Am Mühlenweg", "Rue X Prolongée")
M.BASE_CAP = 300          -- bases kept (the saved list, ot_saved `sb`)

local function chordHeading(g, e, from)
	local a, b = g.nodeById[from], g.nodeById[OGs.other(e, from)]
	return Gs.atan2(b.y - a.y, b.x - a.x)
end

--- The section through the street edge nearest (x, y) in graph g: { pts = { {x, y} } (ordered), key (the lowest edge
--- id), len, edges } or nil (no edge within SECTION_SNAP).
function M.section(g, x, y)
	if g == nil or g.edges == nil then return nil end
	local best, bd = nil, M.SECTION_SNAP
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if a and b then
			local d = Gs.pointSegDist(x, y, a.x, a.y, b.x, b.y)
			if d < bd then best, bd = e, d end
		end
	end
	if best == nil then return nil end
	local len = Gs.dist(g.nodeById[best.n0].x, g.nodeById[best.n0].y, g.nodeById[best.n1].x, g.nodeById[best.n1].y)
	local used = { [best.id] = true }
	local key, steps = best.id, 0
	-- (each way up to SECTION_MAX: a base counts when it lies within SECTION_MAX along the chain, M.findBase)
	local half = M.SECTION_MAX
	local function walk(e, from)
		-- from: the node we left; returns the node ids beyond, in order (each way at most half the length left)
		local out = {}
		local cur, node = e, OGs.other(e, from)
		local wl = 0
		while steps < M.SECTION_STEPS and wl < half do
			steps = steps + 1
			out[#out + 1] = node
			local h = chordHeading(g, cur, OGs.other(cur, node)) -- (the travel heading into node)
			local nxt, nd = nil, math.rad(M.SECTION_DEG)
			for _, id in ipairs(g.adj[node] or {}) do
				local c = g.edgeById[id]
				if c and not used[id] then
					local dv = math.abs(Gs.angleDiff(h, chordHeading(g, c, node)))
					if dv < nd then nxt, nd = c, dv end
				end
			end
			if nxt == nil then break end
			used[nxt.id] = true
			if nxt.id < key then key = nxt.id end
			local p, q = g.nodeById[node], g.nodeById[OGs.other(nxt, node)]
			local dl = Gs.dist(p.x, p.y, q.x, q.y)
			len, wl = len + dl, wl + dl
			cur, node = nxt, OGs.other(nxt, node)
		end
		return out
	end
	local fwd = walk(best, best.n0)
	local back = walk(best, best.n1)
	local ids = {}
	for i = #back, 1, -1 do ids[#ids + 1] = back[i] end
	ids[#ids + 1] = best.n0
	ids[#ids + 1] = best.n1
	for _, n in ipairs(fwd) do ids[#ids + 1] = n end
	-- (back = walk from n0 away from n1, reversed; n0 / n1 repeat at the joins and are dropped once)
	local pts = {}
	for _, n in ipairs(ids) do
		local nd = g.nodeById[n]
		if nd and not (pts[#pts] and pts[#pts][3] == n) then pts[#pts + 1] = { nd.x, nd.y, n } end
	end
	return { pts = pts, key = key, len = len, edges = steps + 1 }
end

--- (along, off) of point (x, y) on polyline pts: m along from its start, m off it.
function M.project(pts, x, y)
	local bestD, bestS, acc = math.huge, 0, 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local L = Gs.dist(a[1], a[2], b[1], b[2])
		local d, t = Gs.pointSegDist(x, y, a[1], a[2], b[1], b[2])
		if d < bestD then bestD, bestS = d, acc + (t or 0) * L end
		acc = acc + L
	end
	return bestS, bestD
end

--- The base on section sec for a stop at (x, y): bases = { { b = name, x, y, h } }. Returns base, along distance from
--- it (m) or nil. A base at the stop's own spot (< 15 m: the same stop renamed) doesn't count.
function M.findBase(sec, bases, x, y)
	if sec == nil or #sec.pts < 2 then return nil end
	local sNew = M.project(sec.pts, x, y)
	local best, bestA = nil, math.huge
	for _, b in ipairs(bases or {}) do
		if type(b.b) == "string" and tonumber(b.x) and tonumber(b.y) and Gs.dist(b.x, b.y, x, y) >= 15 then
			local sb, off = M.project(sec.pts, b.x, b.y)
			if off <= M.SECTION_ON then
				local a = math.abs(sNew - sb)
				if a <= M.SECTION_MAX and a < bestA then best, bestA = b, a end
			end
		end
	end
	return best, best and bestA or nil
end

-- variant forms per classifier: "%b" = the base name, "%c" = the compass word, "%m" = the landmark word
M.VARIANT = {
	en = { far = "%b End", compass = { n = "North", s = "South", e = "East", w = "West" }, c = "%b %c", up = "Upper %b", down = "Lower %b",
		old = "Old %b", new = "New %b", mark = "%b (%m)" },
	usa = { far = "%b Ext", compass = { n = "North", s = "South", e = "East", w = "West" }, c = "%c %b", up = "Upper %b", down = "Lower %b",
		old = "Old %b", new = "New %b", mark = "%b (%m)" },
	de = { far = "Am %b", compass = { n = "Nord", s = "Süd", e = "Ost", w = "West" }, c = "%b %c", up = "Ober-%b", down = "Unter-%b",
		old = "Alt-%b", new = "Neu-%b" },
	nl = { far = "%b-Eind", compass = { n = "Noord", s = "Zuid", e = "Oost", w = "West" }, c = "%b-%c", up = "Boven-%b", down = "Beneden-%b",
		old = "Oud-%b", new = "Nieuw-%b" },
	sv = { far = "Bortre %b", compass = { n = "Norra", s = "Södra", e = "Östra", w = "Västra" }, c = "%c %b", up = "Övre %b", down = "Nedre %b",
		old = "Gamla %b", new = "Nya %b" },
	nb = { far = "Ytre %b", compass = { n = "Nordre", s = "Søndre", e = "Østre", w = "Vestre" }, c = "%c %b", up = "Øvre %b", down = "Nedre %b",
		old = "Gamle %b", new = "Nye %b" },
	fr = { far = "%b Prolongée", compass = { n = "Nord", s = "Sud", e = "Est", w = "Ouest" }, c = "%b %c", up = "%b (Haut)", down = "%b (Bas)",
		old = "%b (Ancien)", new = "%b (Nouveau)", mark = "%b (%m)" },
	it = { far = "%b (Fondo)", compass = { n = "Nord", s = "Sud", e = "Est", w = "Ovest" }, c = "%b %c", up = "%b (Alta)", down = "%b (Bassa)",
		old = "%b (Vecchia)", new = "%b (Nuova)", mark = "%b (%m)" },
	es = { far = "%b (Final)", compass = { n = "Norte", s = "Sur", e = "Este", w = "Oeste" }, c = "%b %c", up = "%b (Alta)", down = "%b (Baja)",
		old = "%b (Vieja)", new = "%b (Nueva)", mark = "%b (%m)" },
	pt = { far = "%b (Final)", compass = { n = "Norte", s = "Sul", e = "Leste", w = "Oeste" }, c = "%b %c", up = "%b (Alta)", down = "%b (Baixa)",
		old = "%b (Velha)", new = "%b (Nova)", mark = "%b (%m)" },
	ja = { far = "%b奥", compass = { n = "北", s = "南", e = "東", w = "西" }, c = "%b%c", up = "上%b", down = "下%b", old = "旧%b", new = "新%b",
		mark = "%b（%m）" },
	ja_r = { far = "%b-oku", compass = { n = "Kita", s = "Minami", e = "Higashi", w = "Nishi" }, c = "%b-%c", up = "Kami-%b", down = "Shimo-%b",
		old = "Kyū-%b", new = "Shin-%b", mark = "%b (%m)" },
	ru = { far = "%b (конец)", compass = { n = "север", s = "юг", e = "восток", w = "запад" }, c = "%b (%c)", up = "%b (верх)", down = "%b (низ)",
		old = "%b (старая)", new = "%b (новая)" },
	ru_r = { far = "%b (konets)", compass = { n = "sever", s = "yug", e = "vostok", w = "zapad" }, c = "%b (%c)", up = "%b (verkh)",
		down = "%b (niz)", old = "%b (staraya)", new = "%b (novaya)" },
}

local function vfill(fmt, b, c, m)
	if fmt == nil then return nil end
	local out = fmt:gsub("%%b", function() return b end)
	if c then out = out:gsub("%%c", function() return c end) elseif out:find("%c", 1, true) then return nil end
	if m then out = out:gsub("%%m", function() return m end) elseif out:find("%m", 1, true) then return nil end
	return out
end

--- The landmark word of a candidate spec for a variant (romance phrases without their article: "de la Fontaine" ->
--- "Fontaine"); nil when the language makes no such variant or the word is in the base already.
function M.markWord(cls, spec, base)
	if type(spec) ~= "string" or (M.VARIANT[cls or ""] or {}).mark == nil then return nil end
	local w = spec
	for _ = 1, 3 do
		local nw = w:gsub("^[%l]+%s+", ""):gsub("^[ld]'", "")
		if nw == w then break end
		w = nw
	end
	if w == "" or (type(base) == "string" and base:find(w, 1, true)) then return nil end
	return w
end

--- The variants of base name b for a later stop on its section, in order: o = { dir = "n"|"e"|"s"|"w" (from the base),
--- along (m), dz (m, the stop's height - the base's), core (m: the stop's distance from the centre - the base's; < 0
--- nearer), mark (a landmark word or nil) }. Returns { { name, how } } (each at most MAX_CHARS characters).
function M.variants(cls, b, o)
	local V = M.VARIANT[cls or ""] or M.VARIANT.en
	local out, seen = {}, {}
	local function add(nm, how)
		if nm and not seen[nm] and nm ~= b and M.chars(nm) <= M.MAX_CHARS then
			seen[nm] = true
			out[#out + 1] = { nm, how }
		end
	end
	local cw = (o.along or 0) >= M.VAR_ALONG and o.dir and V.compass[o.dir] or nil
	local hz = (o.dz or 0) >= M.VAR_DZ and "up" or ((o.dz or 0) <= -M.VAR_DZ and "down" or nil)
	local age = (o.core or 0) <= -M.VAR_CORE and "old" or ((o.core or 0) >= M.VAR_CORE and "new" or nil)
	if cw then add(vfill(V.c, b, cw), "compass") end
	if hz then add(vfill(V[hz], b), hz) end
	if age then add(vfill(V[age], b), age) end
	if o.mark and V.mark then add(vfill(V.mark, b, nil, o.mark), "mark") end
	if (o.along or 0) >= M.VAR_FAR and V.far then add(vfill(V.far, b), "far") end
	-- combinations: the compass with the height / age / landmark
	if cw and hz then add(vfill(V[hz], vfill(V.c, b, cw)), "compass+" .. hz) end
	if cw and age then add(vfill(V[age], vfill(V.c, b, cw)), "compass+" .. age) end
	if cw and o.mark and V.mark then add(vfill(V.mark, vfill(V.c, b, cw), nil, o.mark), "compass+mark") end
	if hz and age then add(vfill(V[age], vfill(V[hz], b)), hz .. "+" .. age) end
	if cw and (o.along or 0) >= M.VAR_FAR and V.far then add(vfill(V.far, vfill(V.c, b, cw)), "compass+far") end
	-- (no compass for a stop near the base: the other directions' words are no help; the age words by side)
	if not cw and o.dir and (o.along or 0) >= 40 then add(vfill(V.c, b, V.compass[o.dir]), "compassNear") end
	return out
end

--- The first variant not in used: name, how; or nil.
function M.sectionName(cls, b, o, used)
	for _, v in ipairs(M.variants(cls, b, o)) do
		if not (used and used[v[1]]) then return v[1], v[2] end
	end
	return nil
end

return M
