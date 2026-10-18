-- Organic Towns: names of the offshoot towns the mod creates, Works and residential districts (pure; 2026-10-14,
-- NEXT_PHASE_BRIEF 47 "Satellite and Works name variety").
--
-- User: "industrial satellites seem like they always say 'works' or very often. make sure our satellites have lots of
-- variety too." Evidence (compare/*/data.json extraTowns): "Works" on 7 of 11 Works towns, always "<Parent> <suffix>";
-- residential districts Sands x4, Beach x3, -on-Sea x3, Point / Shores / Bay / Heights x2: nearly always parent + a
-- water word (any water within 170 m made a "shore" site, a river bank too).
--   * Works (M.works): the industry's own type (M.indType over the industry file: steel mill, coal mine, glass works,
--     saw mill ...; 19 families), the site (harbour, station, river, hill) and the map survey's cues (river, valley, coast,
--     falls ...) pick from four patterns per list language:
--       parent    "<Parent> Ironworks", "Zeche <Parent>", "<Parent>-la-Verrerie" (the family's forms, the site's);
--       company   a founder-style standalone name: "Ashworthville", "Port Crossley", "Kolonie Ewald", "Decazeville"-like
--                 "Mercierville", "Gustavsberg", "Colonia Ibarra", "New <Parent>";
--       cue       a site-word compound: "Ironbridge" (river), "Coalbrook", "Furnace Vale" (valley), "Glassport" (water),
--                 "Kalkberg" (hill), "Les Forges-du-Val";
--       generic   "<Parent> Works", "<Parent> Depot", the era's estates and parks (low weight).
--   * Districts (M.district): the site kind's forms ("Upper X", "X Dale", "X Ford" on a river), the compass from the
--     parent ("North X", "X-Nord", "Norra X", 北X), Upper / Lower by height, Little / New, the language's generics
--     (-Green / -End / -Common / -Fields; -Siedlung / -Feld / -Heide ...), never a real list name, and the shore words
--     only where they are true: Sands / -on-Sea / Beach / Strand on a
--     sandy sea shore, Lakeside / Waterside by a lake, never by a river or inland.
--   * Variety: every form has a suffix key ("works", "port+", "ville", "north+"); a name takes the lowest map-wide count
--     of its key first (so each suffix appears once per map until the map runs out), never a key a sibling of the same
--     parent already carries while another is left, then the best fit plus a seeded jitter (deterministic per seed).
--     The map count is read from the names on the map (stateless: the same after a reload).
--   * Lists without a classifier (asia, oceania, china, korea, poland: ot_names has no classes for them) get no
--     composed name at all (the driver gives an unused name of the list instead: no "High Wuhan", "Wenzhou Works").
--   * Eras (2026-10-14, NEXT_PHASE_BRIEF 53 Part B, review Q3: "Created towns use the game year"): a Works before 1920
--     takes the Ironbridge-style compounds (cue class) and "-Works" forms first; the railway era (1840-1945) Junction,
--     Station, Sidings and New X; a district from 1945 Heights, Park, Estates, Acres, Gardens (M.ERAS, M.eraMul).
--   * A leftover named-feature claim of the parent (ot_placename.leftClaim / claimName, "Glavenside"): an `extra` with
--     first = true goes before every other form while its key is unused on the map.
--   * A compass word relates to the parent: "North X" only on the parent's north side (site.dir, M.compass), and never on
--     a parent that already carries a compass or size word ("South Ashby": no "North South Ashby").
--   * Readable (2026-10-15, NEXT_PHASE_BRIEF 60: literal, context-aware names first): the English forms say what is
--     there (Riverside, Meadows, Falls, Watersmeet, Landing) instead of the dialect words (Ings, Holme, Clough, Force,
--     Staithes, Delph); ot_placename.related never builds on an opaque parent stem ("Mytbridge").
-- Names only: a created town is named once; nothing is renamed. Every loop is bounded by the vocabulary tables and the
-- map's names (MAX_NAMES). Plain Lua, pre-5.3.

local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local CL = ug_require "square_organic_towns::/organic_towns/ot_climate.lua"

local M = {}

-- (ot_rng.hash of consecutive numeric seeds steps evenly, 2026-10-14: 0.27 0.26 0.25 ... for seeds 1, 2, 3; hashing the
-- hash's text spreads them)
local function H(...) return rng.hash(tostring(rng.hash(...)) .. "|offname") end
local function U(...) return (H(...) - 1) / 2147483646 end
M.U = U

M.ON = true
M.MAX_NAMES = 4000        -- map names read for the counts at most
M.WORKS_MAX_LEN = 40
M.DISTRICT_MAX_LEN = 32
M.WORKS_STEM = 18         -- parent names longer than this compose Works names from their first word
M.DISTRICT_STEM = 14
M.JITTER = 0.9            -- seeded jitter added to a candidate's weight
M.FOUNDER_TRY = 4         -- founders / roots tried per form
M.UPPER_DZ = 18           -- m above the parent's centre: Upper / High forms
M.LOWER_DZ = -10          -- m below: Lower / Nether forms
-- pattern weights
-- created towns by the game year (NEXT_PHASE_BRIEF 53 Part B): a form with an era's word in its era weighs ERA_K more;
-- kind = "works" | "district" | nil (both); to = before that year, from = from that year; cue: the Works' cue class share x
M.ERA_K = 1.6
M.ERA_CUE = 1.8
M.ERAS = {
	{ kind = "works", to = 1920, words = "works ironworks steelworks foundry forge furnace furnaces colliery pit glassworks", cue = true },
	{ from = 1840, to = 1945, words = "junction station sidings yard yards depot new switch" },
	{ kind = "district", from = 1945, words = "heights park estate estates acres gardens village" },
}
for _, e in ipairs(M.ERAS) do
	e.set = {}
	for w in e.words:gmatch("%S+") do e.set[w] = true end
end
M.W = { fam = 0.95, site = 0.9, generic = 0.3, late = 0.5, company = 0.75, cue = 1.05, root = 0.7,
	kind = 1.0, compass = 0.75, size = 0.55, gen = 0.65, shore = 1.05 }

---------------------------------------------------------------------------
-- industry types (base/content/industries/<id>/<id>.con.lua) -> family

M.IND_TYPES = {
	{ "steel", "iron" }, { "smelter", "iron" }, { "iron_ore", "ore" }, { "coal", "coal" }, { "colliery", "coal" },
	{ "clay", "clay" }, { "brick", "clay" }, { "sand", "sand" }, { "gravel", "sand" }, { "quarry", "stone" },
	{ "cement", "cement" }, { "lime", "cement" }, { "chemical", "chem" }, { "pharma", "chem" }, { "glass", "glass" },
	{ "refinery", "oil" }, { "oil", "oil" }, { "machine", "eng" }, { "tool", "eng" }, { "vehicle", "eng" },
	{ "tire", "eng" }, { "tyre", "eng" }, { "rocket", "eng" }, { "textile", "textile" }, { "weaving", "textile" },
	{ "blanket", "textile" }, { "paper", "paper" }, { "printing", "paper" }, { "saw", "timber" },
	{ "furniture", "timber" }, { "industries/forest", "timber" }, { "forestry", "timber" }, { "lumber", "timber" },
	{ "food", "food" }, { "flour", "food" }, { "brewery", "brewery" }, { "distillery", "brewery" },
	{ "winery", "brewery" }, { "fishing", "fish" }, { "shrimp", "fish" }, { "farm", "farm" }, { "orchard", "farm" },
	{ "ranch", "farm" }, { "plantation", "farm" }, { "mine", "ore" },
}
-- ot_stopname.indKind kinds (a Works site without the file) -> family
M.KIND_FAM = { works = "works", quarry = "stone", mine = "coal", mill = "food", farm = "farm", brewery = "brewery",
	timber = "timber" }
M.FAMILIES = { "iron", "ore", "coal", "stone", "clay", "sand", "cement", "chem", "glass", "oil", "eng", "textile",
	"paper", "timber", "food", "brewery", "farm", "fish", "works" }

--- The industry family of an industry file ("industries/steel_mill/steel_mill.con" -> "iron"), "works" when unknown.
function M.indType(file)
	local s = string.lower(tostring(file or ""))
	if s == "" then return "works" end
	for _, e in ipairs(M.IND_TYPES) do
		if s:find(e[1], 1, true) then return e[2] end
	end
	return "works"
end

---------------------------------------------------------------------------
-- vocabulary per list classifier. Forms: %s the parent's name (or its first word), %l the same with its first letter
-- in lower case (ASCII), %r a root of the industry family, %F a founder. "form@cond" (cond: flags joined by "+":
-- any, water, coast, sea, sandy, lake, river, valley, hill, rail, harbour, forest, falls, bend, confluence, mouth,
-- y1900 / y1950 / y1980 (from that year), fam=a,b (industry families)).

local WORKS = {}
WORKS.en = {
	fam = {
		iron = "%s Ironworks|%s Steelworks|%s Furnaces|%s Forge|%s Foundry|%s Rolling Mills",
		ore = "%s Mines|%s Ironstone Mines|%s Shafts|%s Pits",
		coal = "%s Colliery|%s Pit|%s Main|%s Pithead|%s Collieries",
		stone = "%s Quarry|%s Stone Works|%s Quarries|%s Limeworks|%s Stoneyard",
		clay = "%s Brickworks|%s Brickfields|%s Kilns|%s Tileries|%s Clayworks|%s Potteries",
		sand = "%s Sandpits|%s Gravel Pits|%s Sandworks",
		cement = "%s Cement Works|%s Limeworks|%s Kilns",
		chem = "%s Chemical Works|%s Alkali Works|%s Saltworks|%s Dyeworks",
		glass = "%s Glassworks|%s Glasshouses|%s Bottle Works",
		oil = "%s Refinery|%s Oil Works|%s Tank Farm",
		eng = "%s Engine Works|%s Locomotive Works|%s Wagon Works|%s Tool Works|%s Machine Shops|%s Carriage Works",
		textile = "%s Mills|%s Mill Town|%s Spinning Mills|%s Weaving Sheds|%s Bleachworks",
		paper = "%s Paper Mills|%s Papermills|%s Print Works",
		timber = "%s Sawmills|%s Timber Yard|%s Woodyard|%s Bobbin Mill",
		food = "%s Mills|%s Flour Mills|%s Corn Mill|%s Granary",
		brewery = "%s Maltings|%s Brewery|%s Breweries|%s Distillery",
		farm = "%s Grange|%s Farms|%s Granary|%s Dairy",
		fish = "%s Fish Docks|%s Fishery|%s Smokehouses",
		works = "%s Works|%s Mills|%s Foundry|%s Forge|%s Ironworks|%s Engine Works",
	},
	site = {
		harbour = "%s Docks|%s Wharf|%s Quay|%s Harbour|%s Landing|Port %s",
		rail = "%s Junction|%s Sidings|%s Yard|%s Station|%s Goods Yard",
		river = "%s Wharf|%s Landing|%s Mill Race",
		hill = "%s Pit|%s Quarry|%s Top Pit",
	},
	generic = "%s Works|%s Depot|%s Yard|%s Trading Estate@y1950|%s Industrial Estate@y1950|%s Business Park@y1980",
	roots = { iron = "Iron|Furnace|Forge|Cinder", ore = "Iron|Ore", coal = "Coal|Pit", stone = "Stone|Lime",
		clay = "Brick|Kiln|Tile", sand = "Sand|Gravel", cement = "Lime|Kiln", chem = "Salt|Alkali", glass = "Glass",
		eng = "Engine|Wagon", textile = "Cotton|Spindle|Loom", paper = "Paper", timber = "Saw|Timber", food = "Corn|Mill",
		brewery = "Malt", works = "Iron|Forge|Mill" },
	glue = "%rville@any|%rbridge@river|%rbrook@river|%r Vale@valley|%r End@any|%rport@water|%r Hill@hill|%rhurst@any"
		.. "|%rfield@any|%rley@any",
	founders = "Ashworth|Brackley|Crossley|Darby|Fielden|Garside|Hargreaves|Holroyd|Kenyon|Lister|Marsden|Pilling"
		.. "|Radcliffe|Thornber|Whitworth|Barlow|Crompton|Greenhalgh",
	company = "%Fville@any|%Fby@any|Port %F@coast|New %s@any|%F Garden Village@y1900|%Ftown@any",
}
WORKS.usa = {
	fam = {
		iron = "%s Furnace|%s Iron Works|%s Steel|%s Forge|%s Foundry|%s Rolling Mill",
		ore = "%s Mines|%s Iron Mines|%s Diggings|%s Shaft",
		coal = "%s Mines|%s Colliery|%s Coal Camp|%s Diggings|%s Shaft",
		stone = "%s Quarry|%s Quarries|%s Lime Kilns|%s Stone Works",
		clay = "%s Brickyard|%s Kilns|%s Clay Works|%s Pottery",
		sand = "%s Sand Pits|%s Gravel Pit|%s Sand Works",
		cement = "%s Cement Works|%s Lime Kilns",
		chem = "%s Chemical Works|%s Salt Works|%s Powder Works",
		glass = "%s Glass Works|%s Glasshouse",
		oil = "%s Refinery|%s Oil Field|%s Tank Farm",
		eng = "%s Shops|%s Machine Works|%s Locomotive Works|%s Wagon Works|%s Car Shops",
		textile = "%s Mills|%s Cotton Mills|%s Woolen Mills|%s Mill Village",
		paper = "%s Paper Mill|%s Paper Mills|%s Press",
		timber = "%s Lumber|%s Lumber Mill|%s Sawmill|%s Lumber Camp|%s Mill Camp",
		food = "%s Mills|%s Flour Mill|%s Grist Mill|%s Elevator",
		brewery = "%s Brewery|%s Distillery",
		farm = "%s Farms|%s Ranch|%s Creamery",
		fish = "%s Cannery|%s Fish Camp|%s Landing",
		works = "%s Works|%s Mills|%s Furnace|%s Foundry|%s Shops",
	},
	site = {
		harbour = "Port %s|%s Harbor|%s Landing|%s Wharf|%s Docks",
		rail = "%s Junction|%s Yards|%s Depot|%s Station|%s Siding|%s Switch",
		river = "%s Landing|%s Wharf",
		hill = "%s Mines|%s Diggings|%s Quarry|%s Camp",
	},
	generic = "%s Works|%s Depot|%s Industrial Park@y1950|%s Business Park@y1980",
	roots = { iron = "Iron|Furnace|Steel|Forge", ore = "Iron|Ore", coal = "Coal|Carbon", stone = "Lime|Granite|Marble",
		clay = "Brick|Clay|Kiln", sand = "Sand|Gravel", cement = "Lime|Cement", chem = "Salt|Powder", glass = "Glass",
		oil = "Oil", textile = "Mill|Cotton", paper = "Paper", timber = "Lumber|Saw|Timber", food = "Mill|Grain",
		works = "Iron|Mill|Forge" },
	glue = "%rton@any|%rville@any|%rdale@valley|%r City@any|%rport@water|%rburg@any|%r Hill@hill|%r Creek@river"
		.. "|%r Run@river|%r Valley@valley",
	founders = "Abbott|Bradley|Coleman|Dawson|Ellis|Garrett|Harlan|Jessup|Keller|Lyman|Mercer|Norris|Prentice|Ramsey"
		.. "|Tolliver|Whitaker|Hollister|Bannon",
	company = "%Fville@any|%Fton@any|%Fburg@any|%F City@any|Port %F@coast|New %s@any|%F Furnace@fam=iron,works"
		.. "|%F Mines@fam=coal,ore",
}
WORKS.de = {
	fam = {
		iron = "%s-Hütte|%s-Eisenwerk|%s-Hammer|%s-Stahlwerk|%s-Giesserei|%s-Walzwerk",
		ore = "%s-Grube|%s-Erzschacht|%s-Bergwerk",
		coal = "Zeche %s|%s-Schacht|%s-Grube|%s-Kolonie",
		stone = "%s-Steinbruch|%s-Kalkwerk|%s-Bruch",
		clay = "%s-Ziegelei|%s-Tonwerk|%s-Ziegelhütte",
		sand = "%s-Sandgrube|%s-Kiesgrube",
		cement = "%s-Zementwerk|%s-Kalkofen",
		chem = "%s-Chemiewerk|%s-Saline|%s-Farbwerk",
		glass = "%s-Glashütte|%s-Glaswerk",
		oil = "%s-Raffinerie|%s-Tanklager",
		eng = "%s-Maschinenfabrik|%s-Werk|%s-Werkstätten|%s-Waggonfabrik",
		textile = "%s-Spinnerei|%s-Weberei|%s-Tuchfabrik",
		paper = "%s-Papiermühle|%s-Papierfabrik|%s-Druckerei",
		timber = "%s-Sägewerk|%s-Sägemühle|%s-Holzhof",
		food = "%s-Mühle|%s-Kunstmühle",
		brewery = "%s-Brauerei|%s-Mälzerei|%s-Brennerei",
		farm = "%s-Gut|%s-Vorwerk|%s-Domäne",
		fish = "%s-Fischerei|%s-Räucherei",
		works = "%s-Werk|%s-Hütte|%s-Hammer|%s-Fabrik",
	},
	site = { harbour = "%s-Hafen|Hafen %s|%s-Werft|%s-Kai", rail = "%s-Bahnhof|%s-Güterbahnhof|%s-Rangierbahnhof",
		river = "%s-Werft|%s-Lände", hill = "%s-Grube|%s-Steinbruch" },
	generic = "%s-Werk|%s-Fabrik|%s-Industriegebiet@y1950|%s-Gewerbegebiet@y1950|%s-Gewerbepark@y1980",
	roots = { iron = "Eisen|Hammer|Hütten", ore = "Erz|Eisen", coal = "Kohl|Zechen", stone = "Stein|Kalk",
		clay = "Ziegel|Ton", sand = "Sand|Kies", cement = "Kalk", chem = "Salz", glass = "Glas", paper = "Papier",
		timber = "Säge|Holz", food = "Mühl", works = "Hammer|Hütten|Eisen" },
	glue = "%rhütte@any|%rstadt@any|%rhausen@any|%rbach@river|%rtal@valley|%rberg@hill|%rdorf@any|%rfeld@any"
		.. "|%rhafen@water|%rscheid@hill",
	founders = "Ewald|Hugo|Konrad|Mathias|Carl|Gustav|Albert|Bernhard|Friedrich|Heinrich|Victor|Ludwig",
	company = "Kolonie %F@any|%F-Siedlung@any|Neu-%s@any|%Fshütte@fam=iron,works|Zeche %F@fam=coal|Grube %F@fam=ore,stone,clay"
		.. "|Schacht %F@fam=coal,ore",
}
WORKS.nl = {
	fam = {
		iron = "%s-Hoogovens|%s-IJzergieterij|%s-Smederij|%s-Staalfabriek",
		ore = "%s-Mijn|%s-Ertsmijn", coal = "%s-Mijn|%s-Kolenmijn|Mijn %s",
		stone = "%s-Groeve|%s-Kalkoven|%s-Steengroeve", clay = "%s-Steenfabriek|%s-Pannenbakkerij|%s-Tichelwerk",
		sand = "%s-Zandwinning|%s-Zandgat", cement = "%s-Cementfabriek|%s-Kalkbranderij",
		chem = "%s-Zoutziederij|%s-Chemiefabriek", glass = "%s-Glasfabriek|%s-Glasblazerij", oil = "%s-Raffinaderij",
		eng = "%s-Werkplaatsen|%s-Machinefabriek|%s-Werken", textile = "%s-Spinnerij|%s-Weverij|%s-Textielfabriek",
		paper = "%s-Papiermolen|%s-Papierfabriek|%s-Drukkerij", timber = "%s-Zagerij|%s-Houtzaagmolen",
		food = "%s-Molen|%s-Meelfabriek", brewery = "%s-Brouwerij|%s-Branderij", farm = "%s-Hoeve|%s-Zuivelfabriek",
		fish = "%s-Visafslag|%s-Rokerij", works = "%s-Werken|%s-Fabriek|%s-Gieterij|%s-Smederij",
	},
	site = { harbour = "%s-Haven|Haven %s|%s-Kade|%s-Werf", rail = "%s-Station|%s-Emplacement",
		river = "%s-Werf|%s-Kade", hill = "%s-Mijn|%s-Groeve" },
	generic = "%s-Fabriek|%s-Industrieterrein@y1950|%s-Bedrijvenpark@y1980",
	roots = { iron = "IJzer", coal = "Kolen", stone = "Kalk|Steen", clay = "Klinker|Steen", sand = "Zand", glass = "Glas",
		timber = "Zaag|Hout", food = "Meel", paper = "Papier", chem = "Zout", works = "IJzer" },
	glue = "%rdorp@any|%rhaven@water|%rbrug@river|%rveld@any|%rberg@hill",
	founders = "Dekker|Hendriks|Jansen|Kok|Meijer|Mulder|Smit|Visser|Vos|Willems|Brinkman|Kuipers",
	company = "%Fdorp@any|%Fpark@y1900|Nieuw-%s@any",
}
WORKS.fr = {
	fam = {
		iron = "%s-les-Forges|Les Forges-de-%s|%s-la-Fonderie|%s-les-Aciéries",
		ore = "%s-les-Mines|Les Mines-de-%s|%s-le-Puits", coal = "%s-les-Mines|%s-le-Puits|%s-la-Fosse|%s-le-Charbonnage",
		stone = "%s-les-Carrières|%s-la-Carrière|%s-les-Fours-à-Chaux", clay = "%s-la-Briqueterie|%s-la-Tuilerie|%s-les-Tuileries",
		sand = "%s-les-Sablières|%s-la-Sablière", cement = "%s-la-Cimenterie|%s-les-Fours-à-Chaux",
		chem = "%s-les-Salines|%s-la-Soudière", glass = "%s-la-Verrerie|La Verrerie-de-%s", oil = "%s-la-Raffinerie",
		eng = "%s-les-Ateliers|%s-l'Usine|%s-la-Manufacture", textile = "%s-la-Filature|%s-les-Filatures|%s-la-Manufacture",
		paper = "%s-la-Papeterie|%s-l'Imprimerie", timber = "%s-la-Scierie|%s-les-Scieries",
		food = "%s-les-Moulins|%s-la-Minoterie", brewery = "%s-la-Brasserie|%s-la-Distillerie",
		farm = "%s-la-Ferme|%s-la-Grange|%s-la-Laiterie", fish = "%s-la-Pêcherie|%s-la-Conserverie",
		works = "%s-les-Forges|%s-l'Usine|%s-les-Ateliers|%s-la-Fonderie",
	},
	site = { harbour = "Port-%s|%s-Port|%s-le-Quai|%s-les-Docks|%s-le-Bassin", rail = "%s-Gare|%s-Triage",
		river = "%s-le-Quai|%s-le-Port", hill = "%s-les-Mines|%s-les-Carrières" },
	generic = "%s-l'Usine|Zone industrielle de %s@y1950|Parc d'activités de %s@y1980",
	roots = { iron = "Les Forges|Le Fourneau", ore = "Les Mines|Le Puits", coal = "Les Mines|La Fosse|Le Puits",
		stone = "Les Carrières", clay = "La Tuilerie|La Briqueterie", glass = "La Verrerie", chem = "Les Salines",
		textile = "La Filature", paper = "La Papeterie", timber = "La Scierie", food = "Le Moulin",
		works = "L'Usine|Les Ateliers|Les Forges" },
	glue = "%r-du-Val@valley|%r-du-Port@water|%r-du-Mont@hill|%r-du-Pont@river|%r-Neuves@any",
	founders = "Arnaud|Boucher|Chevalier|Dufour|Garnier|Lambert|Mercier|Perrin|Renaud|Vasseur|Fournier|Rollin",
	company = "%Fville@any|Cité %F@any|%F-les-Mines@fam=coal,ore|Port-%F@coast",
}
WORKS.it = {
	fam = {
		iron = "%s Ferriere|%s Fonderia|%s Acciaierie|%s Altiforni", ore = "%s Miniere|Miniera di %s",
		coal = "%s Miniere|Pozzo %s|Miniera di %s", stone = "%s Cave|Cava di %s|%s Calcare",
		clay = "%s Fornace|%s Fornaci|%s Laterizi", sand = "%s Cave|Sabbionara di %s", cement = "%s Cementeria|%s Fornaci",
		chem = "%s Saline|%s Chimica", glass = "%s Vetreria|%s Vetrerie", oil = "%s Raffineria",
		eng = "%s Officine|%s Officine Meccaniche|%s Cantieri", textile = "%s Filanda|%s Cotonificio|%s Lanificio",
		paper = "%s Cartiera|%s Cartiere", timber = "%s Segheria|%s Segherie", food = "%s Mulini|Mulino di %s|%s Pastificio",
		brewery = "%s Birrificio|%s Distilleria", farm = "%s Cascina|%s Fattoria|%s Tenuta", fish = "%s Tonnara|%s Peschiera",
		works = "%s Officine|%s Industriale|%s Ferriere|%s Fonderia",
	},
	site = { harbour = "Porto %s|Marina di %s|%s Darsena|%s Cantiere", rail = "%s Scalo|%s Smistamento|%s Stazione",
		river = "%s Darsena|Approdo di %s", hill = "%s Miniere|%s Cave" },
	generic = "%s Industriale|%s Zona Industriale@y1950|%s Polo Industriale@y1980",
	roots = { iron = "Le Ferriere", coal = "Le Miniere", ore = "Le Miniere", glass = "Le Vetrerie", textile = "La Filanda",
		paper = "Le Cartiere", food = "I Mulini", works = "Le Officine|Le Ferriere", stone = "Le Cave", chem = "Le Saline" },
	glue = "%r di Sopra@hill|%r del Ponte@river|%r del Porto@water|%r di Valle@valley|%r Nuove@any",
	founders = "Bassi|Colombo|Ferrari|Galli|Lombardi|Marini|Moretti|Rinaldi|Sala|Villa|Bruno|Conti",
	company = "Villaggio %F@any|Borgo %F@any|Porto %F@coast|%s Nuova@any",
}
WORKS.es = {
	fam = {
		iron = "Altos Hornos de %s|Fundición de %s|Ferrería de %s|Herrería de %s", ore = "Minas de %s|Mina de %s",
		coal = "Minas de %s|Pozo de %s|Carbonera de %s", stone = "Canteras de %s|Cantera de %s|Caleras de %s",
		clay = "Tejar de %s|Tejera de %s|Alfares de %s", sand = "Areneros de %s|Graveras de %s",
		cement = "Cementera de %s|Caleras de %s", chem = "Salinas de %s|Química de %s",
		glass = "Vidriera de %s|Cristalería de %s", oil = "Refinería de %s", eng = "Talleres de %s|Fábricas de %s|Maestranza de %s",
		textile = "Hilaturas de %s|Tejidos de %s|Colonia Textil de %s", paper = "Papelera de %s|Molino Papelero de %s",
		timber = "Aserradero de %s|Serrería de %s", food = "Molinos de %s|Harinera de %s",
		brewery = "Cervecera de %s|Destilería de %s", farm = "Granja de %s|Cortijo de %s|Hacienda de %s",
		fish = "Almadraba de %s|Conservera de %s", works = "Fábricas de %s|Talleres de %s|Fundición de %s",
	},
	site = { harbour = "Puerto de %s|El Puerto de %s|Muelle de %s|Astillero de %s|Dársena de %s",
		rail = "Estación de %s|Cargadero de %s|Apeadero de %s", river = "Embarcadero de %s|Muelle de %s",
		hill = "Minas de %s|Canteras de %s" },
	generic = "Fábricas de %s|Polígono de %s@y1950|Parque Empresarial de %s@y1980",
	roots = { iron = "La Fundición|La Ferrería", coal = "Las Minas", ore = "Las Minas", stone = "Las Canteras|La Calera",
		clay = "El Tejar", chem = "Las Salinas", food = "Los Molinos", paper = "La Papelera", glass = "La Vidriera",
		works = "Las Fábricas|La Fundición" },
	glue = "%r de Arriba@hill|%r del Río@river|%r del Puerto@water|%r del Valle@valley|%r Nuevas@any",
	founders = "Aguirre|Bermúdez|Castro|Echeverría|Gallardo|Ibarra|Larrañaga|Mendoza|Navarro|Olano|Quintana|Salazar",
	company = "Colonia %F@any|Villa %F@any|Poblado Minero de %s@fam=coal,ore|Barrio Obrero de %s@any",
}
WORKS.pt = {
	fam = {
		iron = "Fundição de %s|Ferraria de %s|Siderurgia de %s", ore = "Minas de %s|Mina de %s",
		coal = "Minas de %s|Poço de %s", stone = "Pedreiras de %s|Pedreira de %s|Caieiras de %s",
		clay = "Olaria de %s|Telheira de %s|Cerâmica de %s", sand = "Areeiro de %s|Saibreira de %s",
		cement = "Cimenteira de %s|Caieiras de %s", chem = "Salinas de %s|Química de %s", glass = "Vidreira de %s|Vidraria de %s",
		oil = "Refinaria de %s", eng = "Oficinas de %s|Fábrica de %s|Metalúrgica de %s", textile = "Fiação de %s|Tecelagem de %s",
		paper = "Papeleira de %s|Fábrica de Papel de %s", timber = "Serração de %s|Serraria de %s",
		food = "Moinhos de %s|Moagem de %s", brewery = "Cervejaria de %s|Destilaria de %s",
		farm = "Quinta de %s|Herdade de %s|Granja de %s", fish = "Armação de %s|Conserveira de %s",
		works = "Fábrica de %s|Oficinas de %s|Fundição de %s",
	},
	site = { harbour = "Porto de %s|Cais de %s|Estaleiro de %s|Doca de %s", rail = "Estação de %s|Ramal de %s|Apeadeiro de %s",
		river = "Cais de %s|Embarcadouro de %s", hill = "Minas de %s|Pedreiras de %s" },
	generic = "Fábrica de %s|Zona Industrial de %s@y1950|Parque Empresarial de %s@y1980",
	roots = { iron = "A Fundição", coal = "As Minas", ore = "As Minas", stone = "As Pedreiras", clay = "A Olaria",
		chem = "As Salinas", food = "Os Moinhos", glass = "A Vidreira", works = "A Fábrica|A Fundição" },
	glue = "%r de Cima@hill|%r do Rio@river|%r do Porto@water|%r do Vale@valley|%r Nova@any",
	founders = "Almeida|Barros|Cardoso|Duarte|Fonseca|Gouveia|Lobo|Machado|Nogueira|Pinto|Queirós|Teixeira",
	company = "Vila %F@any|Colónia %F@any|Bairro Operário de %s@any",
}
WORKS.sv = {
	fam = {
		iron = "%s bruk|%s hytta|%s järnbruk|%s hammare|%s gjuteri|%s stålverk", ore = "%s gruva|%s gruvor|%s schakt",
		coal = "%s gruva|%s kolgruva", stone = "%s stenbrott|%s kalkbrott|%s kalkbruk", clay = "%s tegelbruk|%s tegelverk",
		sand = "%s grustag|%s sandtag", cement = "%s cementfabrik|%s kalkugn", chem = "%s kemiska verk|%s saltsjuderi",
		glass = "%s glasbruk|%s glashytta", oil = "%s raffinaderi", eng = "%s verkstäder|%s mekaniska|%s verk",
		textile = "%s spinneri|%s väveri|%s fabriker", paper = "%s pappersbruk|%s massabruk",
		timber = "%s såg|%s sågverk|%s ångsåg", food = "%s kvarn|%s kvarnar", brewery = "%s bryggeri|%s bränneri",
		farm = "%s gård|%s säteri|%s mejeri", fish = "%s fiskeläge|%s rökeri", works = "%s bruk|%s verk|%s hytta|%s fabriker",
	},
	site = { harbour = "%s hamn|%s kaj|%s varv|%s lastageplats", rail = "%s station|%s bangård|%s godsbangård",
		river = "%s varv|%s lastplats", hill = "%s gruva|%s stenbrott" },
	generic = "%s verk|%s industriområde@y1950|%s företagspark@y1980",
	roots = { iron = "Järn|Hammar|Hytt", ore = "Gruv|Malm", coal = "Kol", stone = "Kalk|Sten", clay = "Tegel",
		glass = "Glas", timber = "Såg", food = "Kvarn", works = "Bruks|Hammar" },
	glue = "%rby@any|%rfors@river|%rberg@hill|%rdal@valley|%rvik@coast",
	founders = "Gustavs|Fredriks|Carls|Axels|Oskars|Eriks|Johans|Henriks|Sofie|Ulrike|Lovise|Kristine",
	company = "%Fberg@any|%Fvik@coast|%Ffors@river|%Fdal@valley|%Flund@any",
}
WORKS.nb = {
	fam = {
		iron = "%s verk|%s jernverk|%s hytte|%s smie", ore = "%s gruve|%s gruber", coal = "%s kullgruve|%s gruve",
		stone = "%s steinbrudd|%s kalkbrudd", clay = "%s teglverk|%s teglverk", sand = "%s grustak|%s sandtak",
		cement = "%s sementfabrikk|%s kalkovn", chem = "%s kjemiske|%s salpeterverk", glass = "%s glassverk|%s glasshytte",
		oil = "%s raffineri", eng = "%s verksted|%s mekaniske", textile = "%s spinneri|%s veveri|%s fabrikker",
		paper = "%s papirfabrikk|%s tresliperi|%s cellulosefabrikk", timber = "%s sag|%s sagbruk|%s høvleri",
		food = "%s mølle|%s kverner", brewery = "%s bryggeri|%s brenneri", farm = "%s gård|%s meieri",
		fish = "%s fiskevær|%s røykeri", works = "%s verk|%s bruk|%s hytte|%s fabrikker",
	},
	site = { harbour = "%s havn|%s kai|%s verft|%s brygge", rail = "%s stasjon|%s godsterminal|%s sidespor",
		river = "%s brygge", hill = "%s gruve|%s steinbrudd" },
	generic = "%s verk|%s industriområde@y1950|%s næringspark@y1980",
	roots = { iron = "Jern|Hammer", ore = "Malm", coal = "Kull", stone = "Kalk|Stein", clay = "Tegl", glass = "Glass",
		timber = "Sag", food = "Kvern", works = "Verks|Hammer" },
	glue = "%rby@any|%rfoss@river|%rberg@hill|%rdal@valley|%rvik@coast|%rstad@any",
	founders = "Fredriks|Christians|Olavs|Haralds|Henriks|Magnus|Sofie|Karls|Eriks|Johans",
	company = "%Fberg@any|%Fvik@coast|%Ffoss@river|%Fdal@valley|%Fverk@any",
}
WORKS.ja = {
	fam = {
		iron = "%s製鉄所|%s製鉄|%s鉄工所|%s鋳物", ore = "%s鉱山|%s鉱業所", coal = "%s炭鉱|%s炭坑|%s鉱業所",
		stone = "%s石切|%s採石場|%s石灰", clay = "%s煉瓦|%s窯業|%s瓦", sand = "%s砂利|%s砂採場", cement = "%sセメント|%s石灰",
		chem = "%s化学|%s塩田", glass = "%s硝子", oil = "%s製油所", eng = "%s工業|%s工場|%s機械|%s造機",
		textile = "%s紡績|%s製糸|%s織物", paper = "%s製紙", timber = "%s製材|%s木材", food = "%s製粉",
		brewery = "%s醸造|%s酒造", farm = "%s農場|%s牧場", fish = "%s水産", works = "%s工業|%s工場|新%s",
	},
	site = { harbour = "%s港|%s埠頭|%s造船", rail = "%s駅前|%s操車場|%s信号場", river = "%s河岸", hill = "%s鉱山|%s石切" },
	generic = "%s工場|%s工業団地@y1950",
	roots = {}, glue = "", founders = "", company = "",
}
WORKS.ja_r = {
	fam = {
		iron = "%s-seitetsusho|%s-seitetsu|%s-tekkōsho|%s-imono", ore = "%s-kōzan|%s-kōgyōsho", coal = "%s-tankō|%s-kōgyōsho",
		stone = "%s-ishikiri|%s-saisekiba|%s-sekkai", clay = "%s-renga|%s-yōgyō|%s-kawara", sand = "%s-jari",
		cement = "%s-semento|%s-sekkai", chem = "%s-kagaku|%s-enden", glass = "%s-garasu", oil = "%s-seiyusho",
		eng = "%s-kōgyō|%s-kōjō|%s-kikai|%s-zōki", textile = "%s-bōseki|%s-orimono", paper = "%s-seishi",
		timber = "%s-seizai|%s-mokuzai", food = "%s-seifun", brewery = "%s-jōzō|%s-shuzō", farm = "%s-nōjō|%s-bokujō",
		fish = "%s-suisan", works = "%s-kōgyō|%s-kōjō|Shin-%s",
	},
	site = { harbour = "%s-kō|%s-futō|%s-zōsen", rail = "%s-ekimae|%s-sōshajō|%s-shingōjō", river = "%s-kashi",
		hill = "%s-kōzan|%s-ishikiri" },
	generic = "%s-kōjō|%s-kōgyōdanchi@y1950",
	roots = {}, glue = "", founders = "", company = "",
}
WORKS.ru = {
	fam = {
		iron = "%s-Литейный|Завод %s|%s-Заводской", ore = "Рудник %s|%s-Рудничный", coal = "Шахта %s|%s-Шахтёрский|Рудник %s",
		stone = "Карьер %s|%s-Карьерный", clay = "%s-Кирпичный|%s-Гончарный", sand = "Карьер %s|%s-Песчаный",
		cement = "%s-Цементный", chem = "%s-Химический|%s-Соляной", glass = "%s-Стекольный", oil = "%s-Нефтяной",
		eng = "%s-Заводской|Завод %s|%s-Механический", textile = "%s-Фабричный|%s-Ткацкий", paper = "%s-Бумажный",
		timber = "Лесозавод %s|%s-Лесопильный|Леспромхоз %s", food = "%s-Мельничный", brewery = "%s-Пивоваренный",
		farm = "Совхоз %s|Колхоз %s@y1930", fish = "Рыбзавод %s", works = "%s-Заводской|%s-Фабричный|Завод %s",
	},
	site = { harbour = "Порт %s|%s-Пристань|%s-Верфь|Затон %s", rail = "%s-Сортировочная|%s-Товарная|Разъезд %s|Станция %s",
		river = "Затон %s|%s-Пристань", hill = "Рудник %s|%s-Карьерный" },
	generic = "%s-Заводской|Промзона %s@y1950",
	roots = { coal = "Шахтёрск|Горняк|Углегорск", iron = "Металлург|Сталеварск", ore = "Рудный|Рудногорск",
		stone = "Каменск", timber = "Лесозаводск", chem = "Химик", textile = "Текстильщик", works = "Рабочий|Промышленный" },
	glue = "%r@any",
	founders = "", company = "",
}
WORKS.ru_r = {
	fam = {
		iron = "%s-Liteyny|Zavod %s|%s-Zavodskoy", ore = "Rudnik %s|%s-Rudnichny", coal = "Shakhta %s|%s-Shakhtyorsky|Rudnik %s",
		stone = "Karyer %s|%s-Karyerny", clay = "%s-Kirpichny|%s-Goncharny", sand = "Karyer %s|%s-Peschany",
		cement = "%s-Tsementny", chem = "%s-Khimichesky|%s-Solyanoy", glass = "%s-Stekolny", oil = "%s-Neftyanoy",
		eng = "%s-Zavodskoy|Zavod %s|%s-Mekhanichesky", textile = "%s-Fabrichny|%s-Tkatsky", paper = "%s-Bumazhny",
		timber = "Lesozavod %s|%s-Lesopilny|Lespromkhoz %s", food = "%s-Melnichny", brewery = "%s-Pivovarenny",
		farm = "Sovkhoz %s|Kolkhoz %s@y1930", fish = "Rybzavod %s", works = "%s-Zavodskoy|%s-Fabrichny|Zavod %s",
	},
	site = { harbour = "Port %s|%s-Pristan|%s-Verf|Zaton %s", rail = "%s-Sortirovochnaya|%s-Tovarnaya|Razyezd %s|Stantsiya %s",
		river = "Zaton %s|%s-Pristan", hill = "Rudnik %s|%s-Karyerny" },
	generic = "%s-Zavodskoy|Promzona %s@y1950",
	roots = { coal = "Shakhtyorsk|Gornyak|Uglegorsk", iron = "Metallurg|Stalevarsk", ore = "Rudny|Rudnogorsk",
		stone = "Kamensk", timber = "Lesozavodsk", chem = "Khimik", textile = "Tekstilshchik", works = "Rabochy|Promyshlenny" },
	glue = "%r@any",
	founders = "", company = "",
}
M.WORKS = WORKS

local DIST = {}
DIST.en = {
	upper = "Upper %s|%s Heights|High %s|%s Hill|%s Rise|%s Top", lower = "Lower %s|Nether %s|%s Bottom",
	across = "%s Bridge|Over %s|Far %s|%s Ferry", river = "%s Ford|%s Riverside|%s Meadows|%s Mill",
	lead = "%s End|%s Cross|%s Gate|%s Lane End|%s Junction@y1840+b1945", valley = "%s Dale|%s Head|%s Vale|%s Bottom",
	forest = "%s Wood|%s Hurst|%s Chase", compass = { n = "North %s", s = "South %s", e = "East %s", w = "West %s" },
	size = "Little %s|New %s", generic = "%s Green|%s Common|%s Fields|%s Heath|%s Park|%s Grange|%s Moor|%s Croft"
		.. "|%s Estate@y1945|%s Gardens@y1945",
	sea = "%s-on-Sea|%s Sands|%s Strand", rock = "%s Head|%s Ness|%s Cliffs", lake = "%s Waterside|%s Lakeside",
	cue = "%s Falls@falls|%s Watersmeet@confluence|%s Mouth@mouth",
}
DIST.usa = {
	upper = "%s Heights|Upper %s|%s Hills|%s Ridge|%s Summit", lower = "Lower %s|%s Bottoms|%s Flats",
	across = "%s Crossing|%s Ferry|Across %s", river = "%s Ford|%s Landing|%s Bottoms",
	lead = "%s Corners|%s Center|%s Crossroads|%s Station", valley = "%s Hollow|%s Glen|%s Valley|%s Draw",
	forest = "%s Woods|%s Timbers|%s Pines", compass = { n = "North %s", s = "South %s", e = "East %s", w = "West %s" },
	size = "New %s|Little %s", generic = "%s Park|%s Village|%s Acres|%s Grove|%s Meadows|%s Gardens|%s Township|%s Plains"
		.. "|%s Estates@y1945",
	sea = "%s Beach|%s Shores", rock = "%s Point|%s Bluffs", lake = "%s Shores|%s Lakeside",
	cue = "%s Falls@falls|%s Forks@confluence|%s Bend@bend",
}
DIST.de = {
	upper = "Ober%l|%s-Oberstadt|%s-Höhe|%s-Berg", lower = "Unter%l|Nieder%l|%s-Unterstadt",
	across = "Neu-%s|%s-Brückenkopf|%s-Überfahrt", river = "%s-Au|%s-Furt|%s-Werder",
	lead = "%s-Siedlung|%s-Ausbau|%s-Kreuz", valley = "%s-Tal|%s im Grund|%s-Grund", forest = "%s-Waldsiedlung|%s-Hain",
	compass = { n = "%s-Nord", s = "%s-Süd", e = "%s-Ost", w = "%s-West" }, size = "Klein-%s|Neu-%s",
	generic = "%s-Feld|%s-Heide|%s-Anger|%s-Wiese|%s-Gartenstadt|%s-Hof|%s-Kamp|%s-Weiler",
	sea = "%s-Strand|%s an der See", rock = "%s-Klippe|%s-Kap", lake = "%s am See|%s-Seebad",
	cue = "%s-Fall@falls|%s-Zusammenfluss@confluence|%s-Mündung@mouth",
}
DIST.nl = {
	upper = "Hoog-%s|Boven-%s|%s-Berg", lower = "Neder-%s|Beneden-%s", across = "Over-%s|Nieuw-%s|%s-Overkant",
	river = "%s-Veer|%s-Waard|%s-Uiterwaard", lead = "%s-Buiten|%s-Kruis", valley = "%s-Dal", forest = "%s-Bos|%s-Hout",
	compass = { n = "%s-Noord", s = "%s-Zuid", e = "%s-Oost", w = "%s-West" }, size = "Klein-%s|Nieuw-%s",
	generic = "%s-Veld|%s-Heide|%s-Broek|%s-Hof|%s-Akker|%s-Weide|%s-Kamp", sea = "%s aan Zee|%s-Bad",
	rock = "%s-Duin", lake = "%s aan het Meer|%s-Plas", cue = "%s-Mond@mouth",
}
DIST.fr = {
	upper = "%s-le-Haut|Haut-%s|%s-les-Hauts|%s-le-Mont", lower = "Bas-%s|%s-le-Bas", across = "Pont-de-%s|%s-Outre",
	river = "Le Gué-de-%s|%s-le-Gué|%s-la-Rive", lead = "%s-le-Hameau|%s-la-Croix", valley = "Val-de-%s|%s-le-Val",
	forest = "%s-les-Bois|%s-la-Forêt", compass = { n = "%s-Nord", s = "%s-Sud", e = "%s-Est", w = "%s-Ouest" },
	size = "Petit-%s|%s-la-Neuve", generic = "%s-les-Prés|%s-les-Champs|%s-la-Lande|%s-le-Bourg|%s-la-Cité|%s-les-Vignes",
	sea = "%s-sur-Mer|%s-Plage", rock = "%s-la-Pointe|%s-le-Cap", lake = "%s-les-Bains|%s-sur-Lac",
	cue = "%s-le-Saut@falls|%s-le-Confluent@confluence",
}
DIST.it = {
	upper = "%s Alta|%s Superiore|Monte %s", lower = "%s Bassa|%s Inferiore", across = "Ponte di %s|Oltre %s",
	river = "Guado di %s|Riva di %s", lead = "Borgo %s|Casale %s", valley = "Val di %s|Valle di %s",
	forest = "Selva di %s|%s Bosco", compass = { n = "%s Nord", s = "%s Sud", e = "%s Est", w = "%s Ovest" },
	size = "%s Nuova|Villa %s", generic = "Case %s|Campi di %s|Prato di %s|Piano di %s|Colle di %s|%s Giardino",
	sea = "Marina di %s|Lido di %s", rock = "Punta %s|Capo %s", lake = "Riva di %s|%s Lago",
	cue = "Cascata di %s@falls|Confluenza di %s@confluence|Foce di %s@mouth",
}
DIST.es = {
	upper = "%s de Arriba|Alto de %s|Cerro de %s", lower = "%s de Abajo|Bajo de %s", across = "Puente de %s|Allende %s",
	river = "Vado de %s|Ribera de %s|Vega de %s", lead = "Barrio de %s|Caserío de %s", valley = "Valle de %s|Hoya de %s",
	forest = "%s del Monte|Pinar de %s", compass = { n = "%s Norte", s = "%s Sur", e = "%s Este", w = "%s Oeste" },
	size = "Villanueva de %s|%s el Nuevo", generic = "Ensanche de %s|Colonia de %s|Campo de %s|Prado de %s|Los Llanos de %s|Huertas de %s",
	sea = "Playa de %s|%s del Mar", rock = "Punta de %s|Cabo de %s", lake = "%s del Lago|Orilla de %s",
	cue = "Saltos de %s@falls|Juntas de %s@confluence|Desembocadura de %s@mouth",
}
DIST.pt = {
	upper = "%s de Cima|Alto de %s|Monte de %s", lower = "%s de Baixo|Baixa de %s", across = "Ponte de %s|Além-%s",
	river = "Vau de %s|Ribeira de %s|Várzea de %s", lead = "Bairro de %s|Lugar de %s", valley = "Vale de %s|Cova de %s",
	forest = "%s do Mato|Pinhal de %s", compass = { n = "%s Norte", s = "%s Sul", e = "%s Nascente", w = "%s Poente" },
	size = "Vila Nova de %s|%s-a-Nova", generic = "Campo de %s|Quinta de %s|Casal de %s|Prado de %s|Hortas de %s|Courela de %s",
	sea = "Praia de %s|%s do Mar", rock = "Ponta de %s|Cabo de %s", lake = "%s do Lago|Margem de %s",
	cue = "Cascata de %s@falls|Foz de %s@mouth",
}
DIST.sv = {
	upper = "Övre %s|%s backe|%s höjd", lower = "Nedre %s|%s dal", across = "Nya %s|%s bro|%s överfart",
	river = "%s vad|%s färja|%s holme", lead = "%s by|%s kors|%s gärde", valley = "%s dal|%s sänka", forest = "%s skog|%s lund",
	compass = { n = "Norra %s", s = "Södra %s", e = "Östra %s", w = "Västra %s" }, size = "Lilla %s|Nya %s",
	generic = "%s äng|%s hage|%s mo|%s gärde|%s torp|%s åker|%s hed", sea = "%s strand|%s sand", rock = "%s udde|%s klippa",
	lake = "%s sjöstad|%s sjöstrand", cue = "%s fors@falls|%s mynning@mouth",
}
DIST.nb = {
	upper = "Øvre %s|%s haugen|%s høyde", lower = "Nedre %s|%s bunn", across = "Nye %s|%s bru|%s over",
	river = "%s vad|%s ferje|%s holmen", lead = "%s grend|%s kryss|%s jordet", valley = "%s dal|%s botn",
	forest = "%s skog|%s lia", compass = { n = "Nordre %s", s = "Søndre %s", e = "Østre %s", w = "Vestre %s" },
	size = "Lille %s|Nye %s", generic = "%s eng|%s mo|%s hage|%s tun|%s jorde|%s myra|%s heia", sea = "%s strand|%s sand",
	rock = "%s odde|%s nes", lake = "%s sjø|%s sjøkant", cue = "%s foss@falls|%s os@mouth",
}
DIST.ja = {
	upper = "上%s|%s台|%s丘", lower = "下%s|%s下", across = "新%s|%s橋|%s向", river = "%s河原|%s渡", lead = "%s新田|%s辻",
	valley = "%s谷|%s沢", forest = "%s林|%s森", compass = { n = "北%s", s = "南%s", e = "東%s", w = "西%s" },
	size = "小%s|新%s", generic = "%s野|%s原|%s田|%s町|%s団地@y1950|%s里", sea = "%s浜|%s海岸", rock = "%s岬|%s崎",
	lake = "%s湖畔", cue = "%s滝@falls|%s落合@confluence",
}
DIST.ja_r = {
	upper = "Kami-%s|%s-dai|%s-oka", lower = "Shimo-%s|%s-shita", across = "Shin-%s|%s-bashi|%s-mukai",
	river = "%s-gawara|%s-watari", lead = "%s-shinden|%s-tsuji", valley = "%s-dani|%s-sawa", forest = "%s-bayashi|%s-mori",
	compass = { n = "Kita-%s", s = "Minami-%s", e = "Higashi-%s", w = "Nishi-%s" }, size = "Ko-%s|Shin-%s",
	generic = "%s-no|%s-hara|%s-da|%s-machi|%s-danchi@y1950|%s-sato", sea = "%s-hama|%s-kaigan", rock = "%s-misaki|%s-zaki",
	lake = "%s-kohan", cue = "%s-taki@falls|%s-ochiai@confluence",
}
DIST.ru = {
	upper = "%s-Нагорный|%s-Верхний", lower = "%s-Нижний|%s-Подгорный", across = "%s-Заречный|%s-Мостовой",
	river = "%s-Бродовой|%s-Луговой", lead = "Выселки %s|Хутор %s", valley = "%s-Дол|%s-Долинный", forest = "%s-Лесной|%s-Боровой",
	compass = { n = "%s-Северный", s = "%s-Южный", e = "%s-Восточный", w = "%s-Западный" }, size = "%s-Малый|%s-Новый",
	generic = "%s-Полевой|%s-Садовый|Слобода %s|Посёлок %s|%s-Степной", sea = "%s-на-Море", rock = "%s-Мысовой",
	lake = "%s-на-Озере", cue = "",
}
DIST.ru_r = {
	upper = "%s-Nagorny|%s-Verkhny", lower = "%s-Nizhny|%s-Podgorny", across = "%s-Zarechny|%s-Mostovoy",
	river = "%s-Brodovoy|%s-Lugovoy", lead = "Vyselki %s|Khutor %s", valley = "%s-Dol|%s-Dolinny", forest = "%s-Lesnoy|%s-Borovoy",
	compass = { n = "%s-Severny", s = "%s-Yuzhny", e = "%s-Vostochny", w = "%s-Zapadny" }, size = "%s-Maly|%s-Novy",
	generic = "%s-Polevoy|%s-Sadovy|Sloboda %s|Posyolok %s|%s-Stepnoy", sea = "%s-na-More", rock = "%s-Mysovoy",
	lake = "%s-na-Ozere", cue = "",
}
M.DIST = DIST
M.DIST_KINDS = { "upper", "lower", "across", "river", "lead", "valley", "forest", "size", "generic", "sea", "rock", "lake", "cue" }
-- district site kind (ot_district) -> the forms it brings in
M.KIND_SECTIONS = { upper = { "upper" }, across = { "across" }, lead = { "lead" }, valley = { "valley" },
	cross = { "lead" } }   -- (§64: a district by a country crossroads takes the lane end's forms; "open": none)

---------------------------------------------------------------------------
-- helpers

local cache = {}
local function split(s)
	if s == nil or s == "" then return {} end
	if cache[s] then return cache[s] end
	local out = {}
	for part in s:gmatch("[^|]+") do
		local f, c = part:match("^(.-)@(.+)$")
		out[#out + 1] = { f = f or part, cond = c }
	end
	cache[s] = out
	return out
end
M.split = split

--- The classifier's tables, or nil (no classifier: no composed names).
function M.worksOf(cls) return cls and WORKS[cls] or nil end
function M.districtOf(cls) return cls and DIST[cls] or nil end

local UP = { ["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["Å"] = "å", ["Ø"] = "ø", ["Æ"] = "æ", ["É"] = "é", ["È"] = "è" }
local function lower(s)
	s = (tostring(s or ""):gsub("%u", string.lower))
	return (s:gsub("[\195][\128-\159]", function(ch) return UP[ch] or ch end))
end
M.lower = lower

local function trimSep(s) return (s:gsub("^[%s%-']+", ""):gsub("[%s%-']+$", "")) end

--- A form's suffix key: key ("works", "port+", "ville", "north+"), pre, post (the literal text before the first and after
--- the last placeholder), glued (the post / pre touches the placeholder without a blank or hyphen). nil key for a form
--- that is all placeholder.
function M.keyOf(form)
	local pre = form:match("^(.-)%%[slrF]") or ""
	local post = form:match(".*%%[slrF](.*)$") or ""
	local kp, ks = trimSep(pre), trimSep(post)
	if kp == "" and ks == "" then return nil, pre, post end
	local gluedPost = post ~= "" and not post:match("^[%s%-']")
	local gluedPre = pre ~= "" and not pre:match("[%s%-']$")
	-- (a glued part is its own key, "*ville" / "ober*": "Ironworks" is no "<x> Works")
	local key = lower((kp ~= "" and (kp .. (gluedPre and "*" or "+")) or "") .. ((gluedPost and ks ~= "") and "*" or "") .. ks)
	key = key:gsub("%s+", "_")
	return key, pre, post, gluedPre, gluedPost
end

local keyCache = {}
local function keyInfo(form)
	local k = keyCache[form]
	if k == nil then
		local key, pre, post, gp, gs = M.keyOf(form)
		k = { key = key, pre = lower(trimSep(pre)), post = lower(trimSep(post)), gp = gp, gs = gs }
		keyCache[form] = k
	end
	return k
end

local function lastWord(low) return low:match("([^%s%-']+)$") or low end
local function firstWord(low) return low:match("^([^%s%-']+)") or low end

--- Does a map name carry this form's key? (a separate suffix: the name ends with it as whole words; a glued one: the
--- last word ends with it and is longer; prefixes alike.)
function M.hasKey(name, k)
	if type(name) ~= "string" or k.key == nil then return false end
	local low = lower(name)
	if k.post ~= "" then
		if k.gs then
			local w = lastWord(low)
			if not (#w > #k.post + 2 and w:sub(-#k.post) == k.post) then return false end
		else
			if not (#low > #k.post + 1 and low:sub(-#k.post) == k.post) then return false end
			local before = low:sub(-#k.post - 1, -#k.post - 1)
			if not before:match("[%s%-']") then return false end
		end
	end
	if k.pre ~= "" then
		if k.gp then
			local w = firstWord(low)
			if not (#w > #k.pre + 2 and w:sub(1, #k.pre) == k.pre) then return false end
		else
			if not (#low > #k.pre + 1 and low:sub(1, #k.pre) == k.pre) then return false end
			local after = low:sub(#k.pre + 1, #k.pre + 1)
			if not after:match("[%s%-']") then return false end
		end
	end
	return true
end

local function condOk(cond, c)
	if cond == nil or cond == "" then return true end
	for tok in cond:gmatch("[^+]+") do
		local fams = tok:match("^fam=(.+)$")
		local yr = tok:match("^y(%d+)$")
		local before = tok:match("^b(%d+)$")
		if before then
			if not (c.year and c.year < tonumber(before)) then return false end
		elseif fams then
			local hit = false
			for f in fams:gmatch("[^,]+") do if f == c.fam then hit = true end end
			if not hit then return false end
		elseif yr then
			if not (c.year and c.year >= tonumber(yr)) then return false end
		elseif tok ~= "any" and not c[tok] then
			return false
		end
	end
	return true
end
M.condOk = condOk

local function fill(fmt, v)
	local bad = false
	local out = fmt:gsub("%%([slrF])", function(c)
		if c == "s" then return v.s or "" end
		if c == "l" then
			local t = v.s or ""
			local ch = t:sub(1, 1)
			if not ch:match("%u") then bad = true return "" end
			return ch:lower() .. t:sub(2)
		end
		if c == "r" then if v.r == nil then bad = true end return v.r or "" end
		if c == "F" then if v.F == nil then bad = true end return v.F or "" end
		return ""
	end)
	if bad then return nil end
	return out
end
M.fill = fill

-- (2026-10-14, NEXT_PHASE_BRIEF 50: a long name's stem is its first word that names the place, never a modifier:
-- "Great Mytbridge" -> "Mytbridge", not "Great Holme"; "South Cedar Valley" -> "Cedar", not "South Draw")
M.MODIFIERS = {}
for w in ("great little north south east west upper lower nether middle central high new old long market kings bishops "
	.. "abbots port mount lake fort saint st three twin big ober unter nieder neu alt klein gross groß haut bas petit grand "
	.. "grande nord sud ost est ouest norra södra östra västra nordre søndre østre vestre øvre nedre lilla lille nya nye "
	.. "noord zuid oost hoog neder boven nieuw oud san santa santo são alto alta baixo villa vila"):gmatch("%S+") do
	M.MODIFIERS[w] = true
end
local function stemOf(parent, maxLen)
	if type(parent) ~= "string" or parent == "" then return nil end
	if #parent <= maxLen then return parent end
	local n = 0
	for w in parent:gmatch("[^%s%-]+") do
		n = n + 1
		if n > 8 then break end
		if not M.MODIFIERS[lower(w)] and #w >= 3 and #w <= maxLen then return w end
	end
	return nil
end
M.stemOf = stemOf

local function nameList(used)
	local out = {}
	for k, v in pairs(used or {}) do
		local nm = type(k) == "string" and k or (type(v) == "string" and v or nil)
		if nm then out[#out + 1] = nm end
		if #out >= M.MAX_NAMES then break end
	end
	table.sort(out)
	return out
end

--- The site conditions (flags for the forms' conds) from site = { kind, fam, sea, sandy, rocky, lake, river, bay,
--- falls, bend, confluence, mouth, valley, hill, dz, forestEdge, harbour, rail, year, dir }.
function M.conds(site, fam)
	site = site or {}
	local c = { fam = fam or site.fam, year = site.year, climate = site.climate }
	for _, k in ipairs({ "sea", "sandy", "rocky", "lake", "river", "bay", "falls", "bend", "confluence", "mouth", "valley",
		"hill", "harbour", "rail" }) do
		if site[k] then c[k] = true end
	end
	local kind = site.kind
	if kind == "harbour" then c.harbour = true; c.coast = true end
	if kind == "rail" then c.rail = true end
	if kind == "across" then c.river = true end
	if kind == "hill" or kind == "upper" or kind == "quarry" then c.hill = true end
	if kind == "valley" then c.valley = true end
	if site.forestEdge then c.forest = true end
	if tonumber(site.dz) and site.dz >= M.UPPER_DZ then c.hill = true; c.high = true end
	if tonumber(site.dz) and site.dz <= M.LOWER_DZ then c.low = true end
	if c.sea or c.bay then c.coast = true end
	if c.mouth or c.falls or c.confluence then c.river = true end
	if c.coast or c.lake or c.river then c.water = true end
	return c
end

local WATER = nil
local function hasWater(text)
	if WATER == nil then
		local okW, WK = pcall(ug_require, "square_organic_towns::/organic_towns/ot_works.lua")
		WATER = okW and WK.hasWater or function() return false end
	end
	return WATER(text)
end

--- The era factor of form f for a created town of kind ("works" | "district") in year (M.ERAS): ERA_K when a word of the
--- form (its placeholders out) is one of a matching era's words, else 1.
function M.eraMul(f, kind, year)
	if not tonumber(year) or type(f) ~= "string" then return 1 end
	local low = lower((f:gsub("%%%a", " ")))
	for _, e in ipairs(M.ERAS) do
		if (e.kind == nil or e.kind == kind) and (e.from == nil or year >= e.from) and (e.to == nil or year < e.to) then
			for w in low:gmatch("[^%s%-']+") do
				if e.set[w] then return M.ERA_K end
			end
		end
	end
	return 1
end

--- The Works' class shares in year (M.ERAS cue: the Ironbridge-style compounds before 1920).
function M.worksShares(year)
	local out = {}
	for k, v in pairs(M.WORKS_SHARES) do out[k] = v end
	for _, e in ipairs(M.ERAS) do
		if e.cue and tonumber(year) and (e.from == nil or year >= e.from) and (e.to == nil or year < e.to) then
			out.cue = out.cue * M.ERA_CUE
		end
	end
	return out
end

M.CLASS = { parent = "parent", generic = "parent", company = "company", cue = "cue", compass = "compass", shore = "parent",
	real = "real", generated = "generated", feature = "feature" }
M.CLASS_ORDER = { "parent", "company", "cue", "compass", "generated", "real" }
M.WORKS_SHARES = { parent = 0.5, company = 0.25, cue = 0.25, generated = 0.5 }
M.DISTRICT_SHARES = { parent = 0.7, compass = 0.15, cue = 0.15, generated = 0.5 }

-- picks the best candidate: lowest map count of its key, then no sibling with the key, then weight + jitter.
local function choose(cands, names, stem, o)
	local counts, sibs = {}, {}
	local function countOf(k)
		if k.key == nil then return 0, 0 end
		if counts[k.key] == nil then
			local n, sb = 0, 0
			for _, nm in ipairs(names) do
				if M.hasKey(nm, k) then
					n = n + 1
					if stem and nm:find(stem, 1, true) then sb = sb + 1 end
				end
			end
			counts[k.key], sibs[k.key] = n, sb
		end
		return counts[k.key], sibs[k.key]
	end
	-- (the pattern first, seeded by o.shares: { [class] = share }; a class whose best name repeats a suffix more than
	-- another class's best gives way)
	local function bestOf(filter)
		local best, bt, bs, bscore = nil, nil, nil, nil
		for _, c in ipairs(cands) do
			if filter == nil or (M.CLASS[c.pattern] or c.pattern) == filter then
				local n, sb = countOf(c.k)
				local tier = math.min(n, 3)
				local sib = sb > 0 and 1 or 0
				local score = c.w + M.JITTER * U(o.seed or 1, "offname", o.parent or "", c.form, c.name)
				local better = false
				if best == nil then better = true
				elseif tier ~= bt then better = tier < bt
				elseif sib ~= bs then better = sib < bs
				else better = score > bscore end
				if better then best, bt, bs, bscore = c, tier, sib, score end
			end
		end
		if best then best.count = bt; best.sib = bs end
		return best
	end
	-- (a leftover named-feature claim of the parent first, while its key is unused on the map)
	local feat = bestOf("feature")
	if feat and feat.count == 0 then return feat end
	local all = bestOf(nil)
	if all == nil or o.shares == nil then return all end
	local classes, total = {}, 0
	for _, cl in ipairs(M.CLASS_ORDER) do
		local b = (o.shares[cl] or 0) > 0 and bestOf(cl) or nil
		if b and b.count == all.count and b.sib == all.sib then
			classes[#classes + 1] = { cl, o.shares[cl], b }
			total = total + o.shares[cl]
		end
	end
	if total <= 0 then return all end
	local u = U(o.seed or 1, "offclass", o.parent or "") * total
	for _, e in ipairs(classes) do
		u = u - e[2]
		if u < 0 then return e[3] end
	end
	return classes[#classes][3]
end
local function addForms(cands, forms, w, pattern, cond, vars, o, picks)
	for i, e in ipairs(forms) do
		if condOk(e.cond, cond) then
			local tries = { {} }
			if e.f:find("%F", 1, true) then tries = picks.F
			elseif e.f:find("%r", 1, true) then tries = picks.r end
			for j = 1, math.min(#tries, M.FOUNDER_TRY) do
				local v = { s = vars.s, r = tries[j].r, F = tries[j].F }
				local nm = fill(e.f, v)
				if nm and o.accept(nm, e.f) then
					local k = keyInfo(e.f)
					local key = k
					if k.key == nil then key = { key = "=" .. lower(nm), pre = "", post = "" } end
					-- (the game year's era, NEXT_PHASE_BRIEF 53 Part B)
					local ew = w * M.eraMul(e.f, o.kind, cond and cond.year)
					cands[#cands + 1] = { name = nm, form = e.f, w = ew, pattern = pattern, k = key }
					break
				end
			end
		end
	end
end

-- seeded orders of the roots / founders: { {r=...} } / { {F=...} }
-- generated candidates (ot_placename.related / works, the driver's Generated / Landscape names): they compete with the
-- composed forms under the same rules (suffix count, siblings, the acceptor), and pay for every root of theirs
-- (o.okGen: a glued new word with the parent's stem, "Mytsands", repeats the parent's root). extra = { { name, form } }.
M.W.generated = 1.0
M.EXTRA_MAX = 4
local function addExtra(cands, extra, maxLen, used, parent, c, o)
	for i, e in ipairs(extra or {}) do
		if i > M.EXTRA_MAX then break end
		local nm, form = e.name, e.form or "%s"
		if type(nm) == "string" and nm ~= "" and #nm <= maxLen and not used[nm] and nm ~= parent
			and M.shoreOk(nm, c) and not (not c.water and hasWater(nm))
			and not (c.climate and CL.wordMisfit(nm, c.climate, o.cls))
			and (o.okGen == nil or o.okGen(nm)) then
			local k = keyInfo(form)
			if k.key == nil then k = { key = "=" .. lower(nm), pre = "", post = "" } end
			-- (e.first: a leftover feature claim, NEXT_PHASE_BRIEF 53 Part B: before every other form)
			cands[#cands + 1] = { name = nm, form = form, w = M.W.generated, pattern = e.first and "feature" or "generated", k = k }
		end
	end
end

local function seededList(s, seed, salt, field)
	local list = {}
	for _, e in ipairs(split(s)) do list[#list + 1] = e.f end
	local out = {}
	if #list == 0 then return out end
	local start = H(seed or 1, salt) % #list
	for i = 0, #list - 1 do out[#out + 1] = { [field] = list[((start + i) % #list) + 1] } end
	return out
end

-- (2026-10-14, NEXT_PHASE_BRIEF 50 item 1, run 1729: "Mytsands" by a lake) Beach words only on a sandy sea shore, sea
-- words only by the sea, lake words only by a lake, in every name an offshoot takes (composed or generated).
M.BEACH_WORDS = "sands beach strand plage lido playa praia arenal strande strandbad seebad hama kaigan"
M.BEACH_PHRASES = { "on-sea", "by-the-sea", "sur-mer", "an der see", "aan zee", "del mar", "do mar", "na-more", "浜", "海岸" }
M.SEA_WORDS = "sea mer mar zee"
M.LAKE_WORDS = "lake lakes lakeside mere tarn see meer plas lac lago sjö sjön vatn vatnet kohan"
local function wordSet(str)
	local t = {}
	for w in str:gmatch("%S+") do t[#t + 1] = w end
	return t
end
local BEACH, SEA, LAKE = wordSet(M.BEACH_WORDS), wordSet(M.SEA_WORDS), wordSet(M.LAKE_WORDS)
local function hasWordIn(low, list)
	for word in low:gmatch("[^%s%-'%.,/]+") do
		for _, w in ipairs(list) do
			if word == w or (#word >= #w + 3 and word:sub(-#w) == w) then return w end
		end
	end
	return nil
end

--- Does the name's water word agree with the site's conditions (M.conds)? Returns true, or false and the word.
function M.shoreOk(name, c)
	if type(name) ~= "string" then return true end
	c = c or {}
	local low = lower(name)
	local beach = hasWordIn(low, BEACH)
	if beach == nil then
		for _, ph in ipairs(M.BEACH_PHRASES) do if low:find(ph, 1, true) then beach = ph break end end
	end
	if beach and not (c.sea and c.sandy) then return false, beach end
	local sea = nil
	for word in low:gmatch("[^%s%-'%.,/]+") do
		for _, w in ipairs(SEA) do if word == w then sea = w end end
	end
	if sea and not c.sea then return false, sea end
	local lk = hasWordIn(low, LAKE)
	if lk and not c.lake then return false, lk end
	return true
end

local function acceptor(parent, used, maxLen, o, site)
	local wet = hasWater(parent)
	return function(nm, form)
		if #nm > maxLen or used[nm] or nm == parent then return false end
		-- (no triple letters: "Abbottton", %Fton on a founder ending in tt)
		if lower(nm):find("([a-z])%1%1") then return false end
		-- (the parent's own words don't count: "Blackmere Heath" is no lake claim of the district)
		local bare = form and (form:gsub("%%[slrF]", " ")) or nm
		if not M.shoreOk(bare, site) then return false end
		if wet and hasWater((form:gsub("%%[slrF]", " "))) then return false end
		-- (water words only where the site has that water: a shore, a harbour; 2026-10-14 NEXT_PHASE_BRIEF 47)
		if not (site.water) and hasWater((form:gsub("%%[slrF]", " "))) then return false end
		-- (the climate, ot_climate: no Heath / Moor / Oak on a tropical map, no Marsh on a dry one; NEXT_PHASE_BRIEF 49)
		if site.climate and CL.wordMisfit(nm, site.climate, o.cls) then return false end
		if o.ok and not o.ok(nm) then return false end
		return true
	end
end

---------------------------------------------------------------------------
-- Works

--- The Works town's name: cls (the list's classifier; nil: none), parent (its name), site = { kind (ot_works site kind
--- or industry kind), file (the industry file) | fam, sea, lake, river, valley, falls ..., dz, year }, used = { [name] =
--- true } (the map's names), o = { seed, ok = function(name) (the word budget) }. Returns name, info = { pattern =
--- "parent" | "company" | "cue" | "generic", suffix (key), form, fam, count (the key's map count before) } or nil.
function M.works(cls, parent, site, used, o)
	o = o or {}
	used = used or {}
	site = site or {}
	local L = M.worksOf(cls)
	if L == nil or type(parent) ~= "string" or parent == "" then return nil end
	local stem = stemOf(parent, M.WORKS_STEM)
	if stem == nil then return nil end
	local fam = site.fam or (site.file and M.indType(site.file)) or M.KIND_FAM[site.kind or ""] or "works"
	local c = M.conds(site, fam)
	local seed = o.seed or 1
	local cands = {}
	local ao = { accept = acceptor(parent, used, M.WORKS_MAX_LEN, { ok = o.ok, cls = cls }, c), kind = "works" }
	local vars = { s = stem }
	local picks = { r = seededList((L.roots or {})[fam] or (L.roots or {}).works, seed, "offRoot" .. parent .. fam, "r"),
		F = seededList(L.founders, seed, "offFounder" .. parent, "F") }
	addForms(cands, split(L.fam[fam] or L.fam.works), M.W.fam, "parent", c, vars, ao, picks)
	if fam ~= "works" then addForms(cands, split(L.fam.works), M.W.fam * 0.6, "parent", c, vars, ao, picks) end
	for _, sk in ipairs({ "harbour", "rail", "river", "hill" }) do
		local on = (sk == "harbour" and c.harbour) or (sk == "rail" and c.rail) or (sk == "river" and c.river)
			or (sk == "hill" and c.hill and (fam == "coal" or fam == "ore" or fam == "stone" or fam == "works"))
		if on then addForms(cands, split(L.site[sk]), M.W.site, "parent", c, vars, ao, picks) end
	end
	local gen = {}
	for _, e in ipairs(split(L.generic)) do gen[#gen + 1] = e end
	addForms(cands, gen, M.W.generic, "generic", c, vars, ao, picks)
	-- the era's estates a bit more than the plain generics
	for _, cnd in ipairs(cands) do
		if cnd.pattern == "generic" then
			for _, e in ipairs(gen) do if e.f == cnd.form and e.cond then cnd.w = M.W.late end end
		end
	end
	-- compounds of the family's root: with a matching site word a cue name ("Ironbridge" by a river)
	for _, e in ipairs(split(L.glue)) do
		local w = (e.cond == nil or e.cond == "any") and M.W.root or M.W.cue
		addForms(cands, { e }, w, (e.cond == nil or e.cond == "any") and "company" or "cue", c, vars, ao, picks)
	end
	for _, e in ipairs(split(L.company)) do
		local w = (e.cond == nil or e.cond == "any") and M.W.company or M.W.cue * 0.9
		addForms(cands, { e }, w, "company", c, vars, ao, picks)
	end
	addExtra(cands, o.extra, M.WORKS_MAX_LEN, used, parent, c, { okGen = o.okGen or o.ok, cls = cls })
	local best = choose(cands, nameList(used), stem, { seed = seed, parent = parent, shares = M.worksShares(c.year) })
	if best == nil then return nil end
	return best.name, { pattern = best.pattern, suffix = best.k.key, form = best.form, fam = fam, count = best.count }
end

---------------------------------------------------------------------------
-- districts

--- The compass key of (x, y) from (px, py): "n" | "e" | "s" | "w" (y north) or nil.
function M.compass(px, py, x, y)
	if not (tonumber(px) and tonumber(py) and tonumber(x) and tonumber(y)) then return nil end
	local dx, dy = x - px, y - py
	if dx == 0 and dy == 0 then return nil end
	if math.abs(dx) > math.abs(dy) then return dx > 0 and "e" or "w" end
	return dy > 0 and "n" or "s"
end

--- The residential district's name: cls, parent, site = { kind (ot_district site kind), sea, sandy, rocky, lake, river,
--- dz, dir (compass from the parent), forestEdge, falls, confluence, mouth, year }, used, o = { seed, ok }. Never a
--- real list name (2026-10-14, user: "in landscape name mode i'd prefer not to use real existing city names"). Returns
--- name, info = { pattern = "parent" | "compass" | "cue" | "shore" | "generic", suffix, form, count } or nil.
function M.district(cls, parent, site, used, o)
	o = o or {}
	used = used or {}
	site = site or {}
	local L = M.districtOf(cls)
	if L == nil or type(parent) ~= "string" or parent == "" then return nil end
	local stem = stemOf(parent, M.DISTRICT_STEM)
	local c = M.conds(site)
	local seed = o.seed or 1
	local kind = site.kind
	-- the shore kind: by what water it is
	if kind == "shore" then
		if c.sea and c.sandy then c.sandySea = true
		elseif c.sea then c.rockySea = true end
	end
	local cands = {}
	local ao = { accept = acceptor(parent, used, M.DISTRICT_MAX_LEN, { ok = o.ok, cls = cls }, c), kind = "district" }
	-- (a parent that already carries a compass or size word, "South Ashby", "Little Holt": no second one)
	local qualified = M.MODIFIERS[lower(parent:match("^([^%s%-]+)") or "")] == true
	local picks = { r = {}, F = {} }
	if stem then
		local vars = { s = stem }
		local secs = {}
		for _, s in ipairs(M.KIND_SECTIONS[kind or ""] or {}) do secs[s] = M.W.kind end
		if c.high then secs.upper = M.W.kind end
		if c.low then secs.lower = M.W.kind * 0.9 end
		if c.river or kind == "across" then secs.river = M.W.kind * 0.95 end
		if c.valley then secs.valley = M.W.kind end
		if c.forest then secs.forest = M.W.kind * 0.9 end
		if kind == "shore" and c.sandySea then secs.sea = M.W.shore end
		if kind == "shore" and c.rockySea then secs.rock = M.W.shore end
		if kind == "shore" and c.lake and not c.sea then secs.lake = M.W.shore end
		if not qualified then secs.size = M.W.size end
		secs.generic = M.W.gen
		for _, sname in ipairs(M.DIST_KINDS) do
			local w = secs[sname]
			if w and sname ~= "cue" then
				local pat = (sname == "sea" or sname == "lake" or sname == "rock") and "shore"
					or (sname == "generic" or sname == "size") and "generic" or "parent"
				addForms(cands, split(L[sname]), w, pat, c, vars, ao, picks)
			end
		end
		addForms(cands, split(L.cue), M.W.cue, "cue", c, vars, ao, picks)
		local dir = site.dir
		if dir and L.compass and L.compass[dir] and not qualified then
			addForms(cands, split(L.compass[dir]), M.W.compass, "compass", c, vars, ao, picks)
		end
	end
	addExtra(cands, o.extra, M.DISTRICT_MAX_LEN, used, parent, c, { okGen = o.okGen or o.ok, cls = cls })
	local best = choose(cands, nameList(used), stem or parent, { seed = seed, parent = parent, shares = M.DISTRICT_SHARES })
	if best == nil then return nil end
	return best.name, { pattern = best.pattern, suffix = best.k.key, form = best.form, count = best.count }
end

---------------------------------------------------------------------------
-- the map's offshoot suffixes (the NAMES offshoot line) and the parent forms (ot_district.orphanOf)

--- Every parent form ("%s"/"%l" forms) of a classifier: { form }, sorted; which = "works" | "district" | nil (both).
function M.parentForms(cls, which)
	local out, seen = {}, {}
	local function add(s)
		for _, e in ipairs(split(s)) do
			if (e.f:find("%s", 1, true) or e.f:find("%l", 1, true)) and not seen[e.f] then seen[e.f] = true; out[#out + 1] = e.f end
		end
	end
	local W = which ~= "district" and WORKS[cls or ""] or nil
	if W then
		for _, f in ipairs(M.FAMILIES) do add(W.fam[f]) end
		for _, k in ipairs({ "harbour", "rail", "river", "hill" }) do add(W.site[k]) end
		add(W.generic); add(W.company)
	end
	local D = which ~= "works" and DIST[cls or ""] or nil
	if D then
		for _, k in ipairs(M.DIST_KINDS) do add(D[k]) end
		for _, d in ipairs({ "n", "s", "e", "w" }) do if D.compass then add(D.compass[d]) end end
	end
	table.sort(out)
	return out
end

--- "works:1,port+:1" over offshoot names (a list): the keys of the classifier's forms they carry, "-" for none.
function M.usedText(cls, names)
	local keys = {}
	local W, D = WORKS[cls or ""], DIST[cls or ""]
	local forms = {}
	local function add(s) for _, e in ipairs(split(s)) do forms[#forms + 1] = e.f end end
	if W then
		for _, f in ipairs(M.FAMILIES) do add(W.fam[f]) end
		for _, k in ipairs({ "harbour", "rail", "river", "hill" }) do add(W.site[k]) end
		add(W.generic); add(W.glue); add(W.company)
	end
	if D then
		for _, k in ipairs(M.DIST_KINDS) do add(D[k]) end
		for _, d in ipairs({ "n", "s", "e", "w" }) do if D.compass then add(D.compass[d]) end end
	end
	local counted = {}
	for i, nm in ipairs(names or {}) do
		if i > M.MAX_NAMES then break end
		local best = nil
		for _, f in ipairs(forms) do
			local k = keyInfo(f)
			if k.key and M.hasKey(nm, k) and (best == nil or #k.key > #best) then best = k.key end
		end
		if best then counted[best] = (counted[best] or 0) + 1 end
	end
	for k, v in pairs(counted) do keys[#keys + 1] = k .. ":" .. v end
	table.sort(keys)
	return #keys > 0 and table.concat(keys, ",") or "-"
end

---------------------------------------------------------------------------
-- a list without a classifier (asia, oceania, china, korea, poland; 2026-10-14, NEXT_PHASE_BRIEF 48 item 2: "High Wuhan",
-- "Wenzhou Works"): an unused name of the list itself, never English words glued onto its names

M.LIST_MAX = 4000

--- An unused name of list (strings) from a seeded start, or nil when every one is used. used = { [name] = true }, ok =
--- function(name) or nil (the word budget). clean = function(name) -> name (list disambiguators off) or nil.
function M.listName(list, used, seed, ok, clean)
	if type(list) ~= "table" or #list == 0 then return nil end
	used = used or {}
	local n = math.min(#list, M.LIST_MAX)
	local start = H(seed or 1, "offList") % n
	for i = 0, n - 1 do
		local nm = list[((start + i) % n) + 1]
		if clean and type(nm) == "string" then nm = clean(nm) end
		if type(nm) == "string" and nm ~= "" and not used[nm] and (ok == nil or ok(nm)) then return nm end
	end
	return nil
end

---------------------------------------------------------------------------
-- the site's water (a local read, for a map without a survey in memory, e.g. after a reload)

M.READ_DIRS = 16
M.NEAR_R = { 60, 120, 200, 300 }
M.OPEN_R = { 900, 1500 }
M.OPEN_DIRS = 4           -- directions with water at both OPEN_R: open water (sea or a big lake)
M.SEA_R = 3000
M.SEA_DIRS = 3            -- ... and this many still wet at SEA_R: the sea
M.SANDY_SLOPE = 0.05

--- The water at a site: { near (m to the nearest water, or nil), open, sea, lake, river, sandy, rocky }. s = sampler
--- (height, water), o = { isWater = fn(s, x, y), slope = fn(s, x, y), lakeBody (the parent's water is a lake) }.
function M.readWater(s, x, y, o)
	o = o or {}
	local wet = o.isWater
	if s == nil or wet == nil then return {} end
	local out = {}
	local nearA = nil
	for _, r in ipairs(M.NEAR_R) do
		for k = 0, M.READ_DIRS - 1 do
			local a = k * 2 * math.pi / M.READ_DIRS
			if wet(s, x + math.cos(a) * r, y + math.sin(a) * r) then nearA = a break end
		end
		if nearA then out.near = r break end
	end
	local open, far = 0, 0
	for k = 0, M.READ_DIRS - 1 do
		local a = k * 2 * math.pi / M.READ_DIRS
		local all = true
		for _, r in ipairs(M.OPEN_R) do
			if not wet(s, x + math.cos(a) * r, y + math.sin(a) * r) then all = false end
		end
		if all then
			open = open + 1
			if wet(s, x + math.cos(a) * M.SEA_R, y + math.sin(a) * M.SEA_R) then far = far + 1 end
		end
	end
	if out.near then
		if open >= M.OPEN_DIRS then
			if far >= M.SEA_DIRS and not o.lakeBody then out.sea = true else out.lake = true end
		else
			out.river = true
		end
		if (out.sea or out.lake) and o.slope then
			local mx, my = x + math.cos(nearA) * out.near / 2, y + math.sin(nearA) * out.near / 2
			local sl = math.max(o.slope(s, x, y) or 0, o.slope(s, mx, my) or 0)
			if sl <= M.SANDY_SLOPE then out.sandy = true else out.rocky = true end
		end
	end
	out.open = open
	return out
end

return M
