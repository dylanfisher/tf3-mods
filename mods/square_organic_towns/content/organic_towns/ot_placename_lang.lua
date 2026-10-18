-- Organic Towns: generated place names, the morpheme inventories per language (data only; ot_placename parses it).
-- 2026-10-14, user: "skip the european name set and use our own more interesting and very procedural and reactive
-- to environment names" and "the more specific to the terrain the better".
--
-- One table per generator language (en, usa, de, fr, it, es, pt, nl, sv, nb, ja). Each list is a string, one entry
-- per line:
--   spec   (the specific part, a stem)   "Ash ash"  "Brad vale:.6 plain:.5 @saxon"  "alto|alta|alti|alte hill:.6"
--   gen    (the generic part)            "-ford ford river:.5 =cross"  "_Falls river ..."  "Fort_ ..."  "Monte^ ~m"
--   affix  (a frame around the name)     "%s-on-Sea coast sandy:.6"  "Upper_%s slope:.8"  "%s_an_der_%r river"
-- Tokens after the text: a tag (weight 1) or tag:weight (ot_placename.TAGS), @group (a regional dialect, see
-- `areas`), * (rare: striking, kept for character towns), =class (two parts of one class never meet: no
-- "Bridgeford"), +p (a personal-name stem: the -ington / -ingen gens take only these), +c (only with the gens that
-- need it: Celtic prefixes), +j (a romance noun that may follow a joined prefix), +r (Japanese: rendaku on the next
-- part), ~m / ~f / ~mp / ~fp (a romance generic's gender: picks the adjective's form and the article).
-- Name shapes (2026-10-14, NEXT_PHASE_BRIEF 53 Part A, ot_placename.planShapes): +q an affix that is a qualifier
-- (Upper / Little / North ... : twins only, or Upper / Lower on a named river's stem; joined ones like Ober- by the
-- site), +v a railroad / civic affix (Junction, Station, Center), +o a generic that is a name on its own ("Combe",
-- "Hagen", "Torre"). Per language: `shapes` (each shape's share of the map's names; the rest are plain), `areas` (the
-- dialect groups of the core, the coast / east side and the remote edge), `shared` (a group that goes with every
-- area's own: Celtic), `common` (the ordinary bases a frame takes: "Sutton-on-Arun"), `articles` (the article forms
-- by gender: "La Hoya", "Le Val").
-- Gen forms: "-x" suffix joined to the stem ("Ash" + "ford"); "_X" a word after it ("Cedar Falls"); "X_" a word before
-- ("Fort Harris", "Torre Alta"); "X^" a prefix the stem joins in lower case ("Monte" + "alto" = "Montalto"); "X-" a
-- hyphenated prefix ("Pont-Aven"). In texts, "_" is a space. Affix fields: %s the name, %l the name with a lower-case
-- first letter, %r the town's river, %k its lake, %p a saint (the language's `saints`, full forms); from the map survey
-- (2026-10-14, NEXT_PHASE_BRIEF 45, ot_mapshape): %t the river's stem, %m / %M the map's mountain (stem / name: `peaks`,
-- `peakForm`), %b / %B the map's big bay (`bays` or `lakes`, `bayForm`), %D the town's compass side on the map, %E its
-- side of the big lake (`dirs`: North|South|East|West). An affix without %s / %l is the whole name ("%t_Falls falls",
-- "Three_Rivers confluence"), taken only on a strong cue (ot_placename.FULL_MIN) or by a character town. Cue tags:
-- north / south / east / west / central, upper / lower (the river's course; they also fit the slope / foot forms),
-- falls, twin, summit, divide, peak, range, mainvalley, biglake, bigbay, narrows, isthmus.
-- Part B (2026-10-14, NEXT_PHASE_BRIEF 53): +x a part that only meets its own group (and a +x generic's gender agrees:
-- "Agua Fria", "Los Alamos", "Fort Fraser", "Georgetown"), +k an affix only for a character town of a kind; per language
-- `layers` (old / mid / late: the raw gens and affixes each settlement layer prefers, "+p" the personal stems),
-- `climate` (per climate: shapes, words, boost, veto, shared, saints, areas, three, group = "<group>:<share>") and
-- `charForms` (per character kind: raw affixes).
-- Climate words (2026-10-14, NEXT_PHASE_BRIEF 49, ot_climate): entries tagged tropic / arid / boreal (and reef, lagoon,
-- mangrove, dune, mesa, wadi, snow) at the end of each spec / gen list; a climate never takes another's.
-- Literal names first (2026-10-15, NEXT_PHASE_BRIEF 60, ot_placename.RULES "s60"): +u an opaque stem a reader can't
-- read (Myt-, Twy-, Ac-, the Celtic fach / wyn / garth; with +p personal names at most one per 16 towns), +n a national
-- or dialect flavor part (Aber-, Llan-, Kirk-, -by, -thwaite, -beck; de -reuth / -büttel, nl -drecht, sv -tuna ...:
-- only on the map's few flavor towns), +a an adjective stem and +e a generic in front that takes no adjective ("Lake
-- Shady"). The `_X` generics with +w make the multi-word names ("Oak Hill", "High Moor", "Arun Bridge").
-- Japanese entries are "kanji/reading" (gens "kanji/reading/rendaku reading").
-- Plain Lua data, pre-5.3.

local L = {}

---------------------------------------------------------------------------
-- English (england / europe en): Old English, Norse and Celtic elements

L.en = {
	maxCons = 3, dbl = "lstnrdfmpg", dropE = true,
	-- (2026-10-14, NEXT_PHASE_BRIEF 53 Part A, names/review/REVIEW_ANSWERS.md) Name shapes per map: the share of each
	-- shape (ot_placename.planShapes; the rest plain), the dialect areas (2-3 per map, borders along the main valley or
	-- range: core in the middle, coast on the coast / east side, edge on the remote far side), the common bases a frame
	-- takes ("Sutton-on-Arun", never "Fellhaven-under-Dun"), the shared group (no hybrid: Celtic with Gaelic or Welsh)
	shapes = "single:.05 separate:.05 qualifier:.06 frame:.03 saint:.02 whole:.02 civic:.02",
	words = 1.35,             -- words per name on average at most (review Q7: 1.4)
	areas = { core = "saxon", coast = "norse", edge = { "gaelic", "welsh" } },
	shared = "celtic",
	common = "Newton|Sutton|Norton|Weston|Easton|Aston|Milton|Stoke|Stratford|Upton|Charlton|Burton|Kirkby|Ashby|Compton|Preston|Thornton|Langley|Bradley|Kingston",
	-- (2026-10-14, NEXT_PHASE_BRIEF 50 item 3: "Invercoed", Gaelic Inver- with Welsh coed. Two parts of one name come from
	-- one group or a compatible pair: Saxon and Norse blend (Grimston), celtic (Aber, Dun, Tor) goes with Gaelic or Welsh,
	-- Gaelic never meets Welsh, nor a Celtic part a Saxon / Norse one. +f: a stem fragment (Ac, Myt, a personal name);
	-- +w: a generic that wants a whole word before it (-bottom, -edge, -side: "Oakbottom", never "Acbottom"))
	compat = { "saxon:norse" , "celtic:gaelic", "celtic:welsh",
		-- (NEXT_PHASE_BRIEF 53 Part B: the climate's shared groups go with every area; +x keeps their parts together)
		"colonial:saxon", "colonial:norse", "colonial:gaelic", "colonial:welsh", "post:saxon", "post:norse", "post:gaelic",
		"post:welsh" },
	spec = [[
Ash ash
Ac oak @saxon +f +u
Oak oak
Thorn edge:.6 heath:.5
Birk birch @norse +n
Birch birch
Elm elm
Hazel hazel
Hasel hazel @norse +f +u
Alder alder
Aller alder marsh:.4
Willow willow
Withy willow marsh:.4
Sal willow:.6 brook:.3 +f +u
Lind lime
Lin lime:.6 pool:.4 +f +u
Beech beech
Buck beech:.5 forest:.4
Holly holly
Yew yew
Apple apple
Pear apple:.6 field:.3
Box forest:.5
Fern heath:.6 clearing:.4
Broom heath:.7
Gorse heath:.8
Ling heath:.8 moor:.5 @norse +n
Bram heath:.5 edge:.5
Hay edge:.5 field:.4
Wood forest:.8
Holt forest:.7
Hart forest:.6
Brock forest:.5 edge:.3
Fox forest:.3 field:.3
Swin forest:.4 field:.3 @saxon +f +u
Wolf forest:.4 moor:.3
Raven cliff:.4 forest:.3 @norse
Crow edge:.3 any:.4
Earn cliff:.4 hilltop:.4
Brook brook:.8 river:.5 =brook
Myt confluence @saxon =mythe +f +u
Twy confluence:.7 ford:.5 =twy +f +u
Burn brook:.8 =brook @gaelic +n
Beck brook:.8 @norse =brook +n
Mill river:.6 brook:.5 ford:.3
Wel spring =well +f +u
Cold spring:.4 hill:.3 moor:.3
Clear spring:.5 brook:.4
Fleet river:.5 marsh:.4 =brook
Ea river:.6 meadow:.3 +f +u
Mar lake:.6 marsh:.6 mere:.5 +f +u
Mer mere:.7 lake:.5 +f +u
Pol pool:.6 =lake @welsh +n
Salt coast:.6 marsh:.5 fen:.4
Sea coast:.8 =sea
Sand sandy:.8 heath:.3
Shingle sandy:.7 coast:.5 *
Swan river:.5 lake:.5
Otter river:.6
Bever river:.5 marsh:.3
Hern marsh:.5 river:.3 +f +u
Cran marsh:.5 meadow:.3 +f +u
Gos marsh:.4 meadow:.3 +f +u
Eel river:.4 marsh:.4 *
Stan rock ford:.3 =stone +f +u
Stone rock:.7 =stone
Chal rock:.4 hill:.4 @saxon +f +u
Chalk rock:.5 hill:.4 cliff:.4
Flint rock:.6
Clay field:.5 marsh:.3
Cliff cliff =cliff
Cleve cliff:.8 slope:.4 =cliff
Scar cliff:.8 rock:.5 @norse
Crag rock:.8 hilltop:.4 @norse
White cliff:.5 rock:.4 any:.3
Black marsh:.4 moor:.4 any:.3
Red rock:.4 any:.4
Green meadow:.6 field:.4
Brad vale:.6 plain:.5 river:.3
Broad vale:.6 river:.4
Lang ridge:.4 vale:.4 any:.3 @norse
Long ridge:.4 vale:.4 any:.3
High hilltop:.6 hill:.5
Hill hill:.6 =hill
Pen hilltop:.8 headland:.5 @welsh +n
Tor hilltop:.8 rock:.6 @celtic +n
Bryn hill:.7 @welsh +n
Dun hilltop:.8 old:.4 @celtic +n
Ard hill:.6 headland:.4 @gaelic +n
Ros headland:.8 @gaelic +n
Glen valley:.8 combe:.4 @gaelic +n
Strath vale * @gaelic +n
Nant brook:.7 valley:.6 @welsh +n
Rig ridge @norse =hill +n
How hilltop:.6 @norse +n
Fell mountain:.7 moor:.5 @norse
Kirk church @norse =church +n
Church church =church
Monk church:.6 any:.3
Priest church:.5 any:.3
Chip market:.7 @saxon +f +u
Port market:.4 coast:.4
Castle hilltop:.6 old:.5
Bur hilltop:.4 old:.4 @saxon +f +u
Wheat field:.7
Rye field:.6 marsh:.3
Barley field:.6 *
Flax field:.5 marsh:.3
Hemp field:.5
Ship field:.4 moor:.3 @saxon
Shep field:.4 moor:.4
Horn headland:.5 hill:.4
Nor any:.4 +f
Sut any:.4 +f
Wes any:.4 +f +u
Eas any:.3 +f +u
Ken any +p @saxon
Alf any +p @saxon
Wulf any +p @saxon
Ed any +p @saxon
Os any +p @saxon
Wig any +p @saxon
Lud any +p @saxon
Wad any +p @saxon
Wal any +p @saxon
Win any +p @saxon
Bed any +p @saxon
Ab any +p @saxon
Hunt any +p forest:.3 @saxon
Bab any +p @saxon
Pad any +p @saxon
Til any +p @saxon
Kel any +p @saxon
Dod any +p @saxon
Wem any +p @saxon
Grim any +p @norse
Orm any +p @norse
Ulf any +p @norse
Brand any +p @norse
Skeg any +p @norse
Swain any +p @norse
Thur any +p @norse
Ketel any +p @norse
more big:.4 +c @celtic +u
beg small:.6 +c @gaelic +u
duff marsh:.4 moor:.4 +c @gaelic +n
garry rock:.5 river:.3 +c @gaelic +n
lochy lake:.5 river:.3 +c @gaelic +n
bride church:.4 +c @gaelic +n
mory +c @gaelic +u
donan +c @gaelic +u
gowan +c @gaelic +u
fin +c @gaelic +u
roy +c @gaelic +u
carn rock:.5 hilltop:.3 +c @celtic +n
dour river:.5 brook:.4 +c @celtic +n
dewi church:.4 +c @welsh +n
fach small:.6 +c @welsh +u
fawr big:.6 +c @welsh +u
afon river:.5 +c @welsh +n
rhos heath:.5 +c @welsh +n
wyn +c @welsh +u
garth +c @welsh +u
coed forest +c @welsh +n
glas meadow:.5 +c @celtic +n
maen rock:.6 +c @welsh +n
Palm palm:.8 tropic:.6
Coral reef:.8 tropic:.6
Mangrove mangrove tropic:.5
Reef reef tropic:.5
Frangi tropic:.6 any:.3 *
Dry arid:.7 any:.3
Dust arid:.5 plain:.4 *
Sandy dune arid:.4
Snow snow boreal:.4
Frost boreal:.6 any:.3
Ice boreal:.4 lake:.4 *
George any tropic:.5 @colonial +x
Charles any tropic:.5 @colonial +x
James any tropic:.5 @colonial +x
Clarence any tropic:.5 @colonial +x
Frederick any tropic:.5 @colonial +x
Augusta any tropic:.5 @colonial +x
Caroline any tropic:.5 @colonial +x
Pleasant any:.4 hilltop:.3 tropic:.5
Prospect hilltop:.4 any:.3 tropic:.5
Content any:.4 field:.3 tropic:.5
Providence any:.4 tropic:.5
Friendship any:.4 tropic:.5 *
Mackay any boreal:.5 @post +x
Fraser any boreal:.5 @post +x
Munro any boreal:.5 @post +x
Simpson any boreal:.5 @post +x
Hearne any boreal:.5 @post +x
Garry any boreal:.5 @post +x
Douglas any boreal:.5 @post +x
Painted rock:.5 arid:.6 *
Ochre rock:.4 arid:.5 *
New new:.6 any:.4 +60
Middle central:.6 any:.4 vale:.3 +60
Kings market:.4 any:.4 +60
Moor moor heath:.4 =marsh +60
Fen fen marsh:.6 =marsh +60
Marsh marsh fen:.5 =marsh +60
Reed marsh:.6 lake:.4 river:.3 +60
Rush marsh:.5 meadow:.4 brook:.3 +60
Sedge fen:.7 marsh:.6 +60
Heron marsh:.5 river:.4 lake:.3 +60
Gull coast:.6 cliff:.4 +60
Bridge bridge river:.4 =cross +60
Cross ford:.3 market:.4 pass:.3 any:.3 =cross +60
Market market big:.4 +60
Spring spring brook:.4 =well +60
Well spring:.8 =well +60
Mere mere lake:.7 =lake +60
Stony rock:.7 brook:.4 =stone +60
Heath heath moor:.4 =marsh +60
Combe combe valley:.6 =valley +60
Dale vale:.6 valley:.6 =valley +60
Twin confluence:.7 river:.3 lake:.2 +60
]],
	gen = [[
-ford ford river:.5 =cross
-bridge bridge river:.5 =cross
-wath ford:.9 @norse =cross +n
-wade ford:.7 =cross
-mouth mouth coast:.4 =mouth
-combe combe valley:.7 =valley +o
-dale vale:.8 valley:.8 @norse =valley
-den valley:.6 clearing:.4 =valley
-hope combe:.8 valley:.6 =valley +o
-bottom valley:.9 vale:.4 =valley +w
-gill gorge:.8 brook:.6 @norse =valley +n
-cleugh gorge:.7 combe:.5 * =valley +n
-ley clearing:.9 edge:.6 forest:.5 @saxon =wood
-leigh clearing:.8 edge:.5 =wood +o
-hurst forest edge:.5 hilltop:.4 =wood +o
-holt forest:.9 =wood +o
-wood forest =wood +w
-shaw edge:.7 forest:.6 =wood +o
-grove forest:.7 edge:.4 =wood +w
-thwaite clearing @norse =wood +n
-ham meadow:.5 river:.3 plain:.5 any:.3 @saxon
-ton plain:.5 field:.5 any:.5 @saxon
-by plain:.5 field:.4 any:.5 @norse +n
-thorpe field:.6 plain:.5 @norse +o +n
-toft field:.5 any:.3 @norse +n
-wick coast:.4 plain:.4 market:.3 +o
-wich market:.5 coast:.3 marsh:.3
-stead field:.5 any:.3
-stow church:.6 any:.3 =church +o
-well spring =well
-wells spring * =well
-field field plain:.7 clearing:.4
-acre field:.6 *
-mere mere lake:.8 =lake @saxon
-water lake:.8 =lake +w @norse
-pool pool lake:.5 coast:.3 =lake
-tarn tarn lake:.6 =lake @norse
-ness headland spit:.8 =cape +w
-naze headland:.9 * =cape +w
-holme island meadow:.4 river:.3 @norse =isle +o +n
-ey island:.8 marsh:.5 =isle
-cliffe cliff rocky:.5 =cliff
-bury hilltop:.6 old:.5 market:.4
-borough hilltop:.5 market:.5 big:.4
-worth field:.6 any:.4 @saxon
-minster church market:.6 big:.5 * =church
-chester old market:.6 * =fort
-caster old market:.5 @norse * =fort +n
-don hilltop:.8 hill:.8 =hill
-down hill:.7 heath:.4 =hill @saxon
-hill hill =hill +w @saxon
-low hilltop:.7 =hill
-tor hilltop:.8 rock:.8 =hill
-edge slope:.8 ridge:.6 =hill +w
-ridge ridge =hill
-side slope:.7 coast:.3 +w
-brook brook river:.6 =brook
-burn brook river:.6 =brook @gaelic +n
-beck brook river:.6 @norse =brook +n
-bourne brook:.9 spring:.5 river:.5 =brook +o
-fleet river:.6 marsh:.5 mouth:.4 =brook
-marsh marsh =marsh +w
-moor moor heath:.5 =marsh +w
-fen fen =marsh
-heath heath =marsh +w
-wold heath:.5 hill:.5 moor:.3
-haven bay mouth:.5 coast:.8 =sea +w
-port coast:.6 bay:.6 market:.3 =sea +w
-sands sandy coast:.6 =sea +w
-hythe river:.6 coast:.5 +o
-ington any:.5 plain:.4 +p @saxon
-ingham any:.5 meadow:.4 +p @saxon
-ingley clearing:.5 any:.4 +p @saxon
-cott any:.4 edge:.3
-kirk church @norse =church +n
-church church =church
-gate pass:.6 any:.3 @norse
-head spring:.6 combe:.4 headland:.4 +w
-mead meadow =field
-hall any:.3 old:.3 +w
Aber^ mouth confluence:.8 +c @celtic =mouth +n
Inver^ mouth confluence:.9 +c * =mouth @gaelic +n
Pen^ hilltop:.9 headland:.5 +c =hill @welsh +n
Tre^ field:.5 any:.4 +c @welsh +n
Llan^ church +c =church @welsh +n
Kil^ church:.8 +c =church @gaelic +n
Bal^ field:.6 any:.4 +c @gaelic +n
Dun^ hilltop:.9 +c @celtic =hill +n
_Key island:.6 lagoon:.6 tropic:.5 =key +w
_Cay island:.7 tropic:.5 =key +w
_Reef reef tropic:.4 +w
_Lagoon lagoon tropic:.4 +w
_Flats plain:.6 arid:.6
_Wells spring arid:.6
_Pan arid plain:.5 *
-fell mountain:.6 moor:.4 boreal:.4
Port_ coast bay:.7 mouth:.5 tropic:.5 =sea +w
-town any:.5 coast:.3 tropic:.6 @colonial +x
_Bay bay coast:.4 tropic:.4 =sea +w
_Point headland spit:.8 tropic:.4 =cape +w
_Estate field:.6 plain:.5 tropic:.6 +w
_Pen field:.5 plain:.4 tropic:.6 * +w
_Hall any:.3 field:.3 tropic:.6 +w
Mount_ hilltop hill:.7 tropic:.4 arid:.3 =hill +w
_Downs plain:.6 heath:.5 arid:.6 =hill +w
_Crossing ford:.9 bridge:.6 arid:.5 =cross +w
_Creek brook river:.6 arid:.5 =brook +w
Fort_ river:.5 confluence:.4 boreal:.6 @post +x
_Landing river:.8 lake:.5 coast:.4 boreal:.5 +w
_Portage river:.6 lake:.6 boreal:.6 * +w
_Rapids falls:.8 river:.6 boreal:.5 =fall +w
_Narrows narrows lake:.5 river:.4 boreal:.5 +w
Glen^ combe valley:.7 boreal:.3 +c @gaelic =valley +n
Strath^ valley:.8 vale:.6 river:.4 boreal:.3 +c @gaelic =valley +n
Kyle^ narrows:.8 coast:.6 boreal:.3 +c @gaelic +n
_Hill hill hilltop:.6 =hill +w +60
_Heath heath moor:.4 =marsh +w +60
_Moor moor heath:.6 =marsh +w +60
_Green meadow:.6 field:.4 plain:.4 +w +60
_Common heath:.4 meadow:.4 plain:.4 +w +60
_End edge:.4 field:.3 any:.3 +w +60
_Cross market:.5 pass:.4 ford:.3 =cross +w +60
_Bridge bridge river:.6 =cross +w +60
_Wood forest edge:.4 =wood +w +60
_Dale vale valley:.8 =valley +w +60
_Vale vale valley:.6 =valley +w +60
_Water lake:.8 river:.4 =lake +w +60
_Brook brook river:.5 =brook +w +60
_Mill river:.6 brook:.6 =mill +w +60
_Cliff cliff rocky:.6 =cliff +w +60
_Fen fen marsh:.6 =marsh +w +60
_Marsh marsh fen:.5 =marsh +w +60
_Edge slope:.7 ridge:.6 forest:.3 =hill +w +60
_Fell mountain:.8 moor:.5 hilltop:.4 =hill +w +60
_Head spring:.5 combe:.4 headland:.6 +w +60
_Ford ford:.9 river:.4 =cross +w +60
_Sands sandy coast:.6 =sea +w +60
]],
	affix = [[
Upper_%s slope:.8 hilltop:.5 hill:.4 +q
Nether_%s valley:.8 vale:.5 foot:.5 +q
Great_%s big market:.5 +q
Little_%s small +q
Market_%s market big:.6 +q
Long_%s vale:.5 ridge:.4 +q
High_%s hilltop:.7 mountain:.6 +q
Kings_%s character:.6 market:.5 * +q
Bishops_%s church:.7 character:.5 * +q
Abbots_%s church:.6 character:.5 * +q
%s-on-Sea coast sandy:.7 bay:.5
%s-by-the-Sea coast:.8 *
%s-upon-%r river bend:.5
%s-on-%r river:.9
%s-on-%k lake mere
%s-in-the-Vale vale
%s-in-the-Marsh marsh fen
%s-in-the-Forest clearing forest:.7
%s-under-Edge foot slope:.5 *
%s-on-the-Hill hilltop:.8
%s-on-the-Wold heath:.7 hill:.5 *
%s_Magna big:.8 character:.3 * +q
%s_Parva small:.8 * +q
New_%s new +q
Old_%s old:.6 +q
%s_%p character church:.5 *
%p character:.8 church:.6 *
North_%s north +q
South_%s south +q
East_%s east +q
West_%s west +q
Lower_%s lower +q
%s-under-%m peak range:.7 *
%s_Fell summit:.7 peak:.6 *
%s-by-the-Narrows narrows *
%t_Head upper:.8 *
%s_Water_Foot mouth:.6 lower:.6 *
%s_Junction market:.5 plain:.4 * +v
%s_Cove bay coast:.6 * +k
Port_%s coast bay:.6 * +k
%s_Garden_City plain:.5 field:.4 * +k
%s_Isle island * +k
Two_Waters confluence:.9 * +60
]],
	saints = "St Aldhelm|St Cuthbert|St Botolph|St Swithun|St Oswald|St Wilfrid|St Chad|St Brannoc|St Petroc|St Kenelm|St Guthlac|St Edith|St Hilda|St Aidan|St Dunstan|St Alphege|St Werburgh",
	rivers = "Avon|Wye|Teme|Ouse|Dove|Tamar|Exe|Axe|Usk|Lune|Wear|Tees|Aire|Calder|Colne|Dart|Fal|Frome|Kennet|Lugg|Nene|Ure|Swale|Wharfe|Wensum|Yare|Arun|Adur|Brue|Parrett|Tavy|Tone|Leven|Eden|Kent|Glaven|Stour|Test|Itchen|Mole|Wey|Medway|Rother|Cuckmere|Waveney|Alde|Deben|Orwell|Welland|Witham|Ancholme|Derwent|Rye|Nidd|Hodder|Ribble|Wyre|Mersey|Dee|Weaver|Severn|Arrow|Leadon|Monnow|Honddu",
	riverSyl = { "Al|Ar|Bran|Car|Dar|Del|Ew|Gar|Ill|Ken|Lud|Mar|Nid|Ock|Rib|Sev|Tam|Ter|Wen|Win|Yar|Tav|Cal",
		"e|on|ar|ent|an|wy|er|ell|en|ey|ow" },
	lakes = "Wyn|Ash|Hawes|Brant|Ellers|Swan|Hern|Black|Red|Cold|Long|Elter|Ravens|Alder|Thorn|Gris|Crum|Butter|Sil|Rydal",
	lakeGens = "mere|water|tarn",
	-- (the dialect area sets the feature words: -water and tarn in the Norse area, -mere in the Saxon one; a peak
	-- is a Fell in the north, a Down in the core)
	lakeGensBy = { norse = "water|tarn", saxon = "mere" },
	dirs = "North|South|East|West",
	peaks = "Brant|Kinder|Raven|Black|Grey|Cross|Dun|Ingle|Wether|Hob|Rose|Glar|Skid|Helm",
	peakForm = "%s Fell",
	peakFormBy = { saxon = "%s Down", norse = "%s Fell" },
	bays = "Whit|Sand|Gull|Seal|Heron|Robin|Long|Mill|Church|Scar",
	bayForm = "%s Bay",
	works = { works = "Iron|Forge|Steel|Smith|Cinder|Furnace", quarry = "Stone|Slate|Lime|Chalk|Flint", mine = "Coal|Copper|Tin|Lead|Pit",
		mill = "Mill|Weaver|Loom", farm = "Grange|Barn|Corn", brewery = "Malt|Hop", timber = "Saw|Timber|Wood" },
	worksGens = "-ton|-field|-bridge|-dale|-side|-wick|-ley|-worth|-ford|-bury|-by",
	-- (2026-10-14, NEXT_PHASE_BRIEF 53 Part B, review Q3) Settlement layers: the raw gens / affixes each layer's towns
	-- prefer (ot_placename.layers: the oldest, biggest towns, crossings, mouths and market towns old; the small ones
	-- late). Old: Saxon -ham / -ton / -ley in the core, Norse -by / -thorpe in its area, the Celtic prefixes; middle:
	-- the Norman touches (Magna, Kings, Bishops, St X) and the clearings; late: the resorts, havens and New X.
	layers = {
		old = "-ham -ton -ley -leigh -worth -bury -borough -chester -caster -ford -wick -wich -stead -ingham -ington -ingley "
			.. "-by -thorpe -toft -thwaite -holme -ey -don -low -combe -hope -minster -stow -kirk -mouth -wath -wade -dale "
			.. "-beck -burn -hythe Aber^ Inver^ Pen^ Tre^ Llan^ Kil^ Bal^ Dun^",
		mid = "-field -hurst -holt -wood -shaw -grove -well -wells -bridge -hall -cott -gate -mead -acre -den -moor -heath "
			.. "-fen -marsh -church Market_%s Kings_%s Bishops_%s Abbots_%s %s_Magna %s_Parva Great_%s Long_%s %s_%p %p",
		late = "-side -haven -port -sands -edge -hill -bottom -water -pool New_%s %s-on-Sea %s-by-the-Sea %s_Junction",
	},
	-- (NEXT_PHASE_BRIEF 53 Part B, review Q6) Climate shape tables: the climate's shape shares and words per name (they
	-- replace `shapes` / `words`), its forms first (boost: raw gens), the joined Saxon / Norse forms it never takes (veto),
	-- the group it shares with every area (colonial: Georgetown; post: Fort Fraser), its own saints, the areas
	climate = {
		tropical = { shapes = "single:.03 separate:.35 qualifier:.04 frame:.01 saint:.05 whole:.04 civic:.02", words = 1.5,
			boost = "Port_ -town _Bay _Point _Cay _Key _Estate _Pen _Hall Mount_",
			veto = "-thorpe -by -ham -toft -thwaite -wath -beck -gill -holme -caster -kirk -tarn -fell -moor -heath -wold "
				.. "-ingham -ington -ingley -burn -dale -water",
			shared = "colonial", areas = { core = "saxon", coast = "colonial", edge = { "gaelic" } },
			saints = "St Ann|St Mary|St Elizabeth|St Thomas|St Catherine|St James|St Lucy|St Andrew|St George|St Philip" },
		dry = { shapes = "single:.04 separate:.20 qualifier:.05 frame:.02 saint:.01 whole:.04 civic:.03", words = 1.45,
			boost = "_Downs _Crossing _Creek -well _Wells Mount_ _Flats" },
		subarctic = { shapes = "single:.04 separate:.25 qualifier:.05 frame:.02 saint:.01 whole:.04 civic:.02", words = 1.45,
			boost = "Fort_ _Landing _Portage _Rapids _Narrows Glen^ Strath^ Kyle^",
			shared = "post", areas = { core = "saxon", coast = "norse", edge = { "gaelic" } }, three = true },
	},
	-- (NEXT_PHASE_BRIEF 53 Part B: the naming hook for strong characters) A character town of a kind (ot_placename
	-- assign's town.character = "<kind>") takes one of its kind's striking forms (raw affixes)
	charForms = { hilltop = "%s-on-the-Hill High_%s", harbour = "%s_Cove Port_%s", cove = "%s_Cove",
		street = "Long_%s Market_%s", company = "New_%s Port_%s", garden = "%s_Garden_City", island = "%s_Isle",
		market = "Market_%s Kings_%s %s_Magna", church = "%s_%p Bishops_%s Abbots_%s" },
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only) Evocative names (+g, whole names that plainly describe the
	-- site, each on its gate ?tag[:min]: "Two Waters" only at a real confluence), the new character kinds' forms (+k)
	-- and the industry cue forms (+i !family: fish, oil, clay, coal, stone, timber, farm, iron)
	affix61 = [[
Two_Waters confluence:.9 ?confluence +g
Three_Rivers confluence:.9 ?confluence:.9 +g
Watersmeet confluence ?confluence +g
Broadwater lake biglake:.6 ?lake:.8 +g
Lakeside lake mere:.6 ?lake:.8 +g
Seven_Oaks oak ?oak:.6 +g
Ashgrove ash ?ash:.6 +g
Birchwood birch ?birch:.6 +g
The_Willows willow ?willow:.6 +g
Pinewood pine fir:.6 ?pine|fir:.6 +g
Long_Meadow meadow ?meadow:.6 +g
Wide_Fen fen marsh:.6 ?fen|marsh:.7 +g
Saltmarsh marsh coast:.6 ?marsh:.6 ?coast:.5 +g
Windy_Ridge ridge ?ridge:.8 +g
Fell_Foot foot mountain:.5 ?foot:.8 +g
Dale_Head valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
High_Moor moor ?moor:.7 +g
High_Force falls ?falls:.8 +g
Wellspring spring ?spring:.7 +g
Sandy_Point spit headland:.8 sandy:.6 ?sandy:.6 ?spit|headland:.7 +g
Rocky_Bay bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Cliff_End cliff ?cliff:.7 +g
Shingle_Street sandy coast:.6 ?sandy:.6 ?coast:.7 +g
Bridgend bridge ?bridge:.9 +g
Stepping_Stones ford brook:.6 ?ford:.9 ?brook:.6 +g
Ferryside river mouth:.6 ?bridge:.9 ?mouth|bay|coast:.5 +g
Palm_Bay bay palm:.8 tropic:.5 ?palm|tropic:.5 ?bay:.6 +g
Coral_Point headland reef:.8 tropic:.5 ?reef:.5 ?headland|spit:.6 +g
Mangrove_Bay bay mangrove:.8 tropic:.5 ?mangrove:.6 ?bay|coast:.5 +g
%s_Quay river:.5 coast:.4 +k
%s_Street plain:.3 +k
%sville plain:.3 +k
%s_Woods forest +k
Far_%s edge:.3 +k
%s_End edge:.3 +k
%s_Sands sandy coast:.6 +k
Fisherhaven coast:.5 bay:.4 !fish +i
%s_Harbour coast bay:.6 !fish +i
Oil_Springs !oil +i
%s_Wells !oil +i
Brickfield field:.3 !clay +i
Claygate !clay +i
Coalbrook brook:.4 !coal +i
Pithead !coal +i
Stonegate rock:.4 !stone +i
Quarry_Bank slope:.4 !stone +i
Timberley forest:.4 !timber +i
Sawyers_End forest:.3 !timber +i
Barnfield field:.4 !farm +i
%s_Grange field:.4 !farm +i
Ironbridge river:.4 bridge:.4 !iron +i
Furnace_End !iron +i
]],
	charForms61 = { harbour = "%s_Quay Port_%s", street = "Long_%s %s_Street", company = "%sville New_%s",
		market = "Market_%s Kings_%s %s_Magna", forest = "%s-in-the-Forest %s_Woods", secluded = "Far_%s %s_End",
		coastal = "%s_Sands %s-on-Sea %s-by-the-Sea" },
}

---------------------------------------------------------------------------
-- American English (usa): settlers' surnames and nature words with landscape generics

L.usa = {
	maxCons = 3, dbl = "lstnrdfmpg", dropE = true,
	shapes = "separate:.35 personal:.15 qualifier:.05 saint:.02 whole:.08 civic:.05",
	words = 1.65,
	areas = { core = "mid", coast = "east", edge = { "west" } },
	compat = { "east:mid", "mid:west", "spanish:mid", "spanish:east", "spanish:west" },
	spec = [[
Cedar forest:.6 pine:.5 cypress:.4
Elm elm
Oak oak
Pine pine
Maple maple
Willow willow
Birch birch
Aspen poplar:.8 mountain:.3
Cottonwood poplar river:.4 @west
Sycamore maple:.6 river:.3 @east
Hickory forest:.6 oak:.3 @east
Walnut forest:.5
Chestnut forest:.5 beech:.4 @east
Spruce spruce
Hemlock fir:.6 spruce:.4 @east
Laurel forest:.4 edge:.3
Holly holly
Cypress cypress marsh:.4
Palm palm
Magnolia forest:.4 @east
Juniper heath:.5 rock:.3 @west
Sage heath:.6 plain:.4 @west
Beaver river:.6 brook:.4
Elk forest:.4 mountain:.3 @west
Bear forest:.4 mountain:.4
Deer forest:.5 meadow:.3
Eagle cliff:.4 mountain:.4 hilltop:.3
Hawk hilltop:.4 ridge:.3
Fox forest:.3 field:.3
Otter river:.6
Turkey forest:.4 field:.3
Buffalo plain:.7 @mid
Antelope plain:.7 @west *
Heron marsh:.6 lake:.4
Crane marsh:.6
Swan lake:.6
Pelican coast:.7 bay:.4 *
Gull coast:.6
Trout brook:.7 river:.5
Salmon river:.7 mouth:.4
Wolf forest:.4 mountain:.3
Raven cliff:.4 forest:.3
Moose marsh:.4 forest:.4 lake:.3
Clear spring:.5 lake:.5 brook:.4 +a
Rock rock:.8 =rock
Stone rock:.7 =rock
Granite rock mountain:.4
Flint rock:.6
Iron rock:.4 works:.6
Copper rock:.4 works:.5 mountain:.3
Silver mountain:.5 rock:.4
Gold mountain:.4 gorge:.3 brook:.3
Coal works:.5 valley:.3
Salt marsh:.5 coast:.4 spring:.4
Sulphur spring:.8 *
Sand sandy:.8 heath:.3
Red rock:.5 any:.3 +a
White cliff:.5 rock:.4 any:.3 +a
Black marsh:.3 any:.3 +a
Green meadow:.5 any:.3 +a
Blue lake:.4 hill:.4 any:.2 +a
Sweet spring:.5 brook:.3 +a
Spring spring =spring
Cold spring:.5 mountain:.3 +a
Warm spring:.6 +a
Fair any:.4 meadow:.3 +a
Pleasant any:.4 vale:.3 +a
Grand big:.6 market:.4 any:.3 +a
Long vale:.4 any:.3 +a
High hilltop:.6 hill:.4 =hill +a
Sunny slope:.4 any:.3 +a
Shady edge:.5 +a
Clay field:.5 river:.3
Rocky rock:.9 =rock +a
Sandy sandy:.9 +a
Muddy river:.5 marsh:.5 +a
Crystal lake:.6 spring:.5 +a
Mirror lake:.7 * +a
Twin confluence:.5 lake:.3 any:.2 +a
Prairie plain:.8 field:.5 @mid =open
Meadow meadow =open
Harris any +p
Mitchell any +p
Carter any +p
Porter any +p
Walker any +p
Turner any +p
Parker any +p
Hayes any +p
Ellis any +p
Foster any +p
Bennett any +p
Coleman any +p
Warren any +p
Barton any +p
Ward any +p
Fletcher any +p
Dalton any +p
Morgan any +p
Sherman any +p
Bradley any +p
Whitman any +p
Lyman any +p
Marshall any +p
Hollis any +p
Prescott any +p
Winslow any +p
Hadley any +p
Thayer any +p
Barnes any +p
Hale any +p
Garrison any +p
Rutledge any +p
Boone any +p
Harmon any +p
Kendall any +p
Ramsey any +p
Lowell any +p
Burnett any +p
Sinclair any +p
Mercer any +p
Whitaker any +p
Crawford any +p
Granger any +p
Stanton any +p
Tucker any +p
Lambert any +p
Russell any +p
Hampton any +p
Palm palm:.8 tropic:.6
Coral reef:.8 tropic:.6
Mangrove mangrove tropic:.5
Banyan tropic:.6 forest:.4
Coconut tropic:.6 coast:.4
Hibiscus tropic:.5 any:.3 *
Mesa mesa arid:.5
Sage arid:.6 plain:.4
Yucca arid:.7
Juniper arid:.4 hill:.4
Alkali arid:.5 plain:.4 *
Snow snow boreal:.4
Spruce spruce boreal:.4
Tamarack boreal:.6 marsh:.4
Caribou boreal:.6 *
Moose boreal:.5 marsh:.3
Painted rock:.5 arid:.6 *
Vermilion rock:.4 cliff:.4 arid:.5 *
Ochre rock:.4 arid:.5 *
frio|fria spring:.5 arid:.5 @spanish +x
dulce|dulce spring:.6 arid:.5 @spanish +x
seco|seca wadi:.6 arid:.5 @spanish +x
hondo|honda gorge:.5 valley:.4 arid:.5 @spanish +x
colorado|colorada rock:.5 cliff:.4 arid:.5 @spanish +x
blanco|blanca rock:.4 arid:.5 @spanish +x
verde|verde spring:.4 any:.3 arid:.4 @spanish +x
prieto|prieta rock:.4 arid:.5 @spanish +x
Alamos any:.4 arid:.5 ~mp @spanish +x
Pinos pine:.5 arid:.5 ~mp @spanish +x
Robles any:.4 arid:.5 ~mp @spanish +x
Ojos spring:.6 arid:.5 ~mp @spanish +x
Cerritos hill:.5 arid:.5 ~mp @spanish +x
Palomas any:.4 arid:.5 ~fp @spanish +x
Lomas hill:.6 arid:.5 ~fp @spanish +x
Piedras rock:.6 arid:.5 ~fp @spanish +x
Tunas any:.4 arid:.5 ~fp @spanish +x
Lucas church:.3 any:.3 arid:.5 ~s @spanish +x
Ysidro church:.3 any:.3 arid:.5 ~s @spanish +x
Benito church:.3 any:.3 arid:.5 ~s @spanish +x
Felipe church:.3 any:.3 arid:.5 ~s @spanish +x
Mateo church:.3 any:.3 arid:.5 ~s @spanish +x
Ines church:.3 any:.3 arid:.5 ~sf @spanish +x
Rita church:.3 any:.3 arid:.5 ~sf @spanish +x
Lucia church:.3 any:.3 arid:.5 ~sf @spanish +x
Middle central:.6 any:.4 +a +60
Center central:.5 market:.4 any:.3 +a +60
Union any:.4 market:.3 +a +60
Liberty any:.4 +a +60
Stony rock:.8 brook:.3 =rock +a +60
Mill river:.6 brook:.5 works:.3 +60
Ash ash +60
Beech beech +60
Alder alder marsh:.3 +60
Rose any:.3 meadow:.4 edge:.3 +60
Orchard field:.5 apple:.6 +60
]],
	gen = [[
_Falls falls river:.5 gorge:.4 =fall
_Springs spring valley:.3 @west =spring
_Rapids falls:.8 river:.5 brook:.3 =fall
_Creek brook river:.6 @west =brook
_Fork confluence river:.6 @west =fork
_Forks confluence =fork
_Crossing ford:.9 bridge:.7 =cross
_Ferry river:.9 ford:.5 =cross
_Landing river:.8 coast:.5
_Bend bend river:.6
_Junction market:.6 plain:.4 @mid +v
_Harbor bay coast:.8 =sea
_Beach sandy coast:.8 =sea
_Point headland spit:.8 =cape
_Cove bay coast:.6 =sea
_Bay bay =sea
_Island island =isle
_Bluff cliff rocky:.5 =cliff
_Bluffs cliff =cliff
_Heights hilltop hill:.7 =hill
_Hills hill =hill
_Ridge ridge =hill
_Gap pass =pass
_Pass pass @west =pass
_Summit hilltop:.9 mountain:.7 =hill
_Butte hilltop:.8 rock:.7 @west * =hill
_Mesa hilltop:.7 plain:.3 rock:.5 @west * =hill
_Canyon gorge @west =valley
_Gulch gorge:.8 brook:.4 @west * =valley
_Hollow combe valley:.6 @east =valley
_Valley valley vale:.7 =valley
_Glen combe:.7 valley:.6 =valley
_Flats plain:.8 meadow:.5 marsh:.3 @west
_Prairie plain field:.6 @mid =open
_Meadows meadow =open
_Grove forest:.8 edge:.6 =wood
_Woods forest =wood
_Pines pine =wood
_Oaks oak =wood
_Park edge:.5 any:.3
_City market:.7 big:.7 plain:.3 @mid
_Center market:.8 @mid +v
_Mills river:.6 brook:.6 works:.5
_Rock rock cliff:.4 =rock
_Marsh marsh =marsh
_Pond pool @east =lake
-ville any:.5 plain:.4 @mid
-burg any:.5 hilltop:.3 @mid
-ton any:.5 field:.4 @east
-ford ford @east =cross
-field field @east
-dale vale:.8 =valley
-wood forest:.8 =wood
-port coast:.7 bay:.6 =sea
-boro any:.5 market:.3 @east
-view hilltop:.7 slope:.6
-mont hill:.7 =hill
-brook brook =brook
Lake_ lake mere:.6 =lake +e
Fort_ old:.6 river:.4 hilltop:.4 confluence:.3
Port_ coast bay:.7 mouth:.5 =sea
Mount_ mountain hilltop:.8 hill:.6 =hill
Cape_ headland =cape
Glen_ combe:.6 valley:.5 @east =valley +e
_Key island:.6 lagoon:.6 tropic:.5 =key
_Keys island:.7 tropic:.5 =key
_Reef reef tropic:.4
_Lagoon lagoon tropic:.4
_Wash wadi arid:.5
_Mesa mesa arid:.4
_Butte hilltop:.7 arid:.6
_Flats plain:.6 arid:.6
_Wells spring arid:.6
_Arroyo wadi arid:.5 *
_Tank pool:.7 spring:.5 arid:.6 =lake
Agua_ spring:.9 arid:.6 ~f @spanish +x
Arroyo_ wadi:.8 brook:.6 arid:.6 ~m @spanish +x
Los_ any:.4 arid:.6 ~mp @spanish +x
Las_ any:.4 arid:.6 ~fp @spanish +x
San_ church:.4 any:.3 arid:.6 ~s @spanish +x
Santa_ church:.4 any:.3 arid:.6 ~sf @spanish +x
_Portage river:.6 lake:.6 boreal:.6 *
_Narrows narrows lake:.5 river:.4 boreal:.5
-kill brook:.8 river:.5 @east +n +60
_Run brook:.8 river:.3 @east =brook +60
]],
	affix = [[
East_%s east +q
West_%s west +q
North_%s north +q
South_%s south +q
Upper_%s slope:.7 +q
Lower_%s foot:.7 +q
%E_%k biglake
%D_Bend bend dir:.6
%t_Forks confluence
Three_Rivers confluence:.9 *
Twin_Rivers twin
Middle_Fork confluence central
%t_Falls falls
%t_Bend bend
%t_Junction market:.5 plain:.4 +v
Upper_%t upper
Lower_%t lower
Port_%t mouth coast:.6
%m_Gap pass
%m_Summit summit
Summit summit:.9 *
Divide divide
Mount_%m peak
%m_Valley range:.6 valley:.6
%t_Valley mainvalley
%B bigbay
Narrows narrows *
%s_Neck isthmus
New_%s new +q
Old_%s old:.6 +q
Grand_%s big:.6 * +q
Little_%s small:.8 +q
%s_Center market:.7 big:.4 +v
%s_Station new:.4 any:.2 +v
%s_Heights hilltop:.6 hill:.5 * +k
%s_Cove bay coast:.6 * +k
%s_Garden_City plain:.5 field:.4 * +k
%s_Island island * +k
]],
	rivers = "Bear|Elk|Clear|Cedar|Willow|Beaver|Salt|Sweetwater|Cottonwood|Otter|Turkey|Big Sandy|Little Sioux|Pine|Rock|Stone|Bluestone|Laurel|Muddy|Deer|Crooked|Long|Fall|Swift|Wolf|Fox|Mill|Black|White|Red|Green|Spring|Sandy|Hickory|Walnut|Sugar|Honey|Copper|Silver|Iron",
	riverSuffix = " River| Creek",
	lakes = "Clear|Crystal|Mirror|Bear|Elk|Pine|Cedar|Silver|Blue|Swan|Heron|Loon|Moose|Long|Twin|Round|Spirit|Big Stone",
	lakeForm = "%s Lake",
	dirs = "North|South|East|West",
	peaks = "Bald|Eagle|Bear|Elk|Granite|Thunder|Storm|Lookout|Signal|Sentinel|Grizzly|Hawk|Raven|Pilot|Spruce|Iron|Copper|Shadow",
	peakForm = "%s Mountain",
	bays = "Heron|Pelican|Gull|Oyster|Shell|Driftwood|Anchor|Mariner|Osprey|Cormorant|Sandpiper|Kingfisher",
	bayForm = "%s Bay",
	works = { works = "Iron|Forge|Steel|Furnace", quarry = "Granite|Stone|Lime|Marble", mine = "Coal|Copper|Silver|Lead|Zinc",
		mill = "Mill|Cotton", farm = "Grain|Corn|Dairy", brewery = "Barley|Hop", timber = "Lumber|Sawmill|Timber" },
	worksGens = "-ton|-ville|-burg|_City|_Mills|_Junction|_Station|_Works|_Landing|_Hollow",
	-- (NEXT_PHASE_BRIEF 53 Part B, review Q3) early forms (-ton, -ford, Mount X, Fort X), then -ville / -burg and the
	-- personal-name + City / Springs forms (+p: the personal stems), the railroad and resort names late
	layers = {
		old = "-ton -ford -field -boro -mont Mount_ Fort_ _Ferry _Crossing _Landing _Mills Glen_ _Hollow _Creek _Falls "
			.. "Port_ -port Cape_ Old_%s",
		mid = "-ville -burg _City _Springs _Prairie _Flats _Grove _Rapids _Forks _Bend _Valley -dale Grand_%s +p",
		late = "_Junction _Center _Park _Heights -view -wood _Beach _Hills New_%s %s_Station %s_Center %t_Junction",
	},
	-- (review Q6) tropical: Port X, X Bay / Point / Key; dry: the water names, Mesa / Butte, the Spanish layer (San X,
	-- Agua X, Los / Las X, Arroyo X: @spanish, shared with every area on a dry map); subarctic: Fort X, Landing, Portage
	climate = {
		tropical = { shapes = "separate:.40 personal:.10 qualifier:.04 saint:.02 whole:.08 civic:.03",
			boost = "Port_ _Bay _Point _Key _Keys _Cove _Harbor _Beach" },
		dry = { shapes = "separate:.40 personal:.10 qualifier:.04 saint:.02 whole:.08 civic:.05", words = 1.6,
			boost = "_Springs _Wells _Tank _Mesa _Butte _Wash _Flats", shared = "spanish", group = "spanish:.3" },
		subarctic = { shapes = "separate:.40 personal:.12 qualifier:.04 whole:.08 civic:.04",
			boost = "Fort_ _Landing _Portage _Rapids _Narrows" },
	},
	charForms = { hilltop = "%s_Heights", harbour = "%s_Cove", cove = "%s_Cove", street = "Grand_%s",
		company = "New_%s", garden = "%s_Garden_City", island = "%s_Island", market = "%s_Center" },
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Two_Rivers confluence:.9 ?confluence +g
Three_Forks confluence ?confluence:.9 +g
Twin_Lakes lake ?lakes2 +g
Lakeview lake ?lake:.8 +g
Seven_Pines pine ?pine:.6 +g
Oak_Grove oak ?oak:.6 +g
Cedar_Bluff cliff:.6 hilltop:.5 ?cliff|hilltop|ridge:.6 ?forest:.4 +g
Pine_Bluff pine cliff:.6 ?pine:.5 ?cliff|hilltop|ridge:.6 +g
Walnut_Bottom meadow valley:.6 ?meadow:.6 ?river|valley:.6 +g
Big_Meadows meadow ?meadow:.6 +g
Prairie_View plain hilltop:.4 ?plain:.7 +g
Windy_Ridge ridge ?ridge:.8 +g
Windy_Gap pass ?pass:.8 +g
High_Ridge ridge hilltop:.6 ?ridge:.8 +g
Rocky_Point headland rocky:.8 ?rocky:.6 ?headland|spit:.7 +g
Sandy_Hook spit sandy:.8 ?sandy:.6 ?spit:.7 +g
Stony_Point headland rock:.6 ?rock|rocky:.6 ?headland|spit:.7 +g
Bayside bay coast:.6 ?bay:.7 +g
Big_Spring spring ?spring:.7 +g
Cold_Springs spring ?spring:.7 ?mountain|hill|forest:.5 +g
Rock_Falls falls rock:.5 ?falls:.8 +g
Cypress_Swamp marsh cypress:.8 ?marsh:.6 ?cypress:.4 +g
Palm_Point headland palm:.8 tropic:.5 ?palm|tropic:.5 ?headland|spit:.6 +g
Coral_Bay bay reef:.8 tropic:.5 ?reef:.5 ?bay:.6 +g
%s_Landing river:.5 coast:.4 +k
%s_Woods forest +k
Far_%s edge:.3 +k
%s_Beach sandy coast:.6 +k
%sville plain:.3 +k
Fishers_Landing coast:.5 river:.4 !fish +i
%s_Harbor coast bay:.6 !fish +i
Oil_City !oil +i
%s_Wells !oil +i
Claymont !clay +i
Brickton !clay +i
Coaldale valley:.4 !coal +i
Coal_Creek brook:.4 !coal +i
Quarryville !stone +i
Granite_Springs spring:.3 !stone +i
Sawmill_Creek brook:.4 forest:.4 !timber +i
Lumberton forest:.3 !timber +i
Hayfield field:.4 !farm +i
%s_Farms field:.4 !farm +i
Ironton !iron +i
Furnace_Hill hill:.4 !iron +i
]],
	charForms61 = { harbour = "%s_Landing %s_Cove", street = "Grand_%s", company = "%sville New_%s",
		forest = "%s_Woods", secluded = "Far_%s", coastal = "%s_Beach" },
}

---------------------------------------------------------------------------
-- German (germany / europe de)

L.de = {
	maxCons = 4, dbl = "lnrstfmpgk", dropE = true,
	shapes = "single:.03 qualifier:.10 frame:.03 whole:.01",
	areas = { core = "mitte", coast = "nord", edge = { "sued" } },
	common = "Neustadt|Neukirchen|Neuhausen|Kirchheim|Altdorf|Mühlhausen|Hofheim|Steinbach|Lindenau|Burgdorf|Bergheim|Marktheim|Rotenburg|Waldkirch",
	compat = { "nord:mitte", "mitte:sued" },
	spec = [[
Eich oak
Eichen oak
Buch beech
Buchen beech
Birken birch
Birk birch:.8
Linden lime
Lind lime:.8
Erl alder
Erlen alder
Weiden willow
Ahorn maple
Eschen ash
Esch ash:.8
Ulmen elm
Hasel hazel
Tannen fir
Tann fir:.8
Fichten spruce
Kiefern pine
Föhren pine @sued
Lärchen larch
Eiben yew
Apfel apple
Holder elder
Pappel poplar
Espen poplar:.8
Bach brook:.6 =bach
Mühl river:.6 brook:.5
Brunn spring =spring
Born spring:.9 @nord =spring
Quell spring:.8 =spring
Kalten spring:.4 mountain:.3
Sulz spring:.7 marsh:.4 @sued
Salz spring:.5 marsh:.4 works:.3
Lauter brook:.7 spring:.4
Schwarz forest:.5 brook:.3 any:.3
Weiss cliff:.4 rock:.4 any:.3
Rot rock:.4 clearing:.4 any:.3
Grün meadow:.5 any:.3
Brück bridge:.7 =bridge
Fähr ford:.5 river:.6
Steg bridge:.6 brook:.4 =bridge
Wasser river:.5 lake:.4
See lake:.7 =see
Teich pool:.8 =see
Weiher pool:.8 @sued =see
Moor moor:.8 marsh:.6 =moor
Bruch marsh:.8 fen:.6 =moor
Ried marsh:.7 fen:.5 @sued =moor
Fenn fen:.8 @nord =moor
Wiesen meadow
Auen meadow:.6 river:.5
Anger meadow:.6 market:.3
Heide heath =heide
Sand sandy:.7 heath:.5
Kies river:.4 sandy:.4
Strand sandy:.8 coast:.6 @nord
Hafen bay:.8 coast:.7 @nord =hafen
Sund coast:.6 spit:.4 @nord
Deich coast:.5 fen:.5 @nord
Klippen rocky:.8 cliff:.6 @nord *
Berg hill:.8 mountain:.5 =berg
Stein rock:.9 hilltop:.3 =stein
Fels rock cliff:.6 =stein
Hoch hilltop:.7 mountain:.6
Hohen hilltop:.7 hill:.5 =berg
Schön slope:.4 any:.4 vale:.3
Rau rock:.5 moor:.4
Kalk rock:.6
Kreide cliff:.7 rock:.5 @nord *
Schiefer rock:.7 works:.3
Hirsch forest:.5 mountain:.3
Wolfs forest:.5 mountain:.3
Falken cliff:.5 hilltop:.4
Raben cliff:.4 forest:.3
Fuchs forest:.4 edge:.3
Hasen field:.5 meadow:.3
Gems mountain:.8 @sued *
Alm mountain:.8 meadow:.6 @sued
Tal vale:.6 =tal
Kessel combe:.7 valley:.5
Lang vale:.4 ridge:.3 any:.3
Breit vale:.6 river:.3
Krumm bend:.8 river:.4
Kreuz pass:.4 church:.5 market:.3
Kirch church =kirch
Kloster church:.9 old:.5 *
Burg hilltop:.5 old:.5 =burg
Wald forest:.8 =wald
Holz forest:.7 =wald
Busch edge:.6
Hag edge:.6 field:.3
Hof any:.4 field:.3
Mittel any:.4 vale:.3
Ost any:.3
West any:.3
Nord any:.3
Alt old:.6
Neu new:.6
Albers any +p
Ebers any +p
Gerolds any +p
Hildes any +p
Sieg any +p
Ruders any +p
Eggen any +p
Walders any +p
Ottmars any +p
Liebs any +p
Rein any +p
Wal any +p
Wil any +p
Ger any +p
Bert any +p
Volk any +p
Dietz any +p
Gund any +p
Rud any +p
Hein any +p
Wolfrats any +p *
Hammel any +p
Palmen palm tropic:.5
Korallen reef tropic:.5
Dürr arid:.6 any:.3
Sand dune arid:.4
Schnee snow boreal:.4
Frost boreal:.5 any:.3
]],
	gen = [[
-bach brook river:.5 valley:.3 =bach
-beck brook:.9 @nord =bach +n
-born spring @nord =spring +o +n
-brunn spring @sued =spring +o +n
-au meadow:.7 river:.5 island:.4 +o
-furt ford river:.4 =bridge
-brück bridge =bridge
-brücken bridge:.9 river:.5 =bridge
-münde mouth =mund
-gemünd confluence * =mund
-münden confluence:.9 river:.4 =mund
-see lake:.9 mere:.6 =see
-weiher pool:.9 @sued =see
-teich pool:.9 =see
-berg hill hilltop:.5 =berg
-stein rock hilltop:.5 =stein
-fels rock cliff:.7 =stein
-höhe hilltop =berg
-kopf hilltop:.8 mountain:.5 =berg
-eck ridge:.7 slope:.5 @sued =berg
-egg ridge:.7 mountain:.4 @sued =berg +n
-kamm ridge * =berg
-joch pass mountain:.5 @sued * =berg
-sattel pass * =berg
-tal valley vale:.6 =tal
-thal valley @sued =tal
-grund combe:.9 valley:.6 =tal
-klamm gorge @sued * =tal
-halde slope @sued =berg +n
-leiten slope:.9 @sued =berg +n
-feld field plain:.7 =feld
-felde field:.9 @nord =feld
-wies meadow:.8 @sued
-heide heath =heide
-moor moor marsh:.5 =moor
-bruch marsh fen:.7 =moor
-ried marsh:.9 fen:.6 @sued =moor
-fenn fen @nord =moor
-wald forest =wald
-walde forest:.9 @nord =wald
-holz forest:.8 edge:.5 =wald
-hain edge:.8 forest:.6 =wald +o
-hagen edge:.6 field:.4 @nord =wald +o
-rode clearing @mitte =rode +o +n
-roda clearing @mitte =rode +n
-reuth clearing @sued =rode +n
-rath clearing:.9 @mitte =rode +n
-schlag clearing:.8 @sued =rode +n
-loh edge:.7 forest:.6 =wald +o
-hausen any:.6 plain:.4 @mitte +o
-heim any:.6 plain:.5 @sued
-dorf any:.6 field:.4
-ingen any:.7 +p @sued
-ing any:.6 +p @sued
-stedt field:.5 any:.4 @nord +n
-büttel fen:.4 any:.5 @nord * +n
-leben any:.5 field:.4 @mitte * +n
-hofen any:.6 +p @sued
-weiler any:.5 edge:.3 @sued +o +n
-kirchen church =kirch
-zell church:.7 clearing:.4 @sued =kirch +o +n
-münster church market:.6 big:.5 * =kirch
-stadt market:.8 big:.7
-burg hilltop:.7 old:.6 market:.3 =burg
-hafen bay coast:.8 =hafen
-strand sandy @nord
-siel mouth:.8 fen:.5 @nord * =mund +n
-werder island river:.4
-wörth island:.9 river:.5 @sued +n
-ort headland:.8 spit:.6 @nord
-horn headland:.9 hilltop:.4 @nord
-riff reef tropic:.4
-fjell mountain boreal:.4 *
]],
	affix = [[
Bad_%s spring valley:.4 *
Ober%l slope:.8 hilltop:.6 +q
Unter%l foot:.8 valley:.6 +q
Nieder%l foot:.6 vale:.6 marsh:.3 +q
Hohen%l hilltop:.8 * +q
Alt%l old +q
Neu%l new +q
Gross_%s big +q
Klein_%s small +q
Markt_%s market big:.4 @sued +q
%s_an_der_%r river bend:.5
%s_am_%k lake
%s_am_See lake:.8
%s_im_Tal valley:.8 vale:.6 *
%s_am_Berg slope:.8 foot:.5
%s_am_Wald edge:.9 forest:.5
%s_in_der_Heide heath *
%p character:.8 church:.7 *
Norder%l north +q
Süder%l south +q
Oster%l east +q
Wester%l west +q
%s_am_Fall falls *
%s_am_Pass pass:.8 range:.5 *
]],
	saints = "Sankt Wendel|Sankt Goar|Sankt Leon|Sankt Märgen|Sankt Ulrich|Sankt Ingbert|Sankt Veit|Sankt Georgen|Sankt Oswald|Sankt Leonhard|Sankt Blasius|Sankt Martin|Sankt Gangolf|Sankt Kilian",
	rivers = "Lahn|Ilm|Nidda|Wipper|Lauter|Murg|Kinzig|Elz|Glan|Nahe|Sieg|Ohm|Eder|Fulda|Werra|Saale|Unstrut|Wutach|Wiese|Alb|Rems|Fils|Jagst|Tauber|Altmühl|Wörnitz|Vils|Rott|Isen|Ammer|Loisach|Iller|Mindel|Zusam|Paar|Ilz|Naab|Röder|Pulsnitz|Spree|Havel|Dosse|Stepenitz|Ucker|Peene|Trebel|Warnow|Recknitz|Stör|Treene|Eider|Wümme|Hunte|Hase|Vechte|Berkel|Lippe|Ruhr|Wupper|Erft|Ahr|Lieser|Kyll|Prüm|Blies|Queich|Selz|Pfrimm|Schwalm|Efze|Diemel|Nethe|Emmer|Leine|Innerste|Oker|Ilse|Bode|Selke|Wipfra|Gera|Orla|Schwarza",
	riverSyl = { "Al|Er|Il|Lau|Mur|Nid|Wip|Schwal|Glo|Lu|Ro|Ur|Ems|Fil|Kin|Hol|Wern|Strem|Ul",
		"a|e|er|itz|ach|ster|tz|el" },
	lakes = "Eich|Linden|Schwarz|Weiss|Grün|Hirsch|Kalten|Mühl|Klar|Tiefen|Spiegel|Birken|Erlen|Schilf|Rohr|Krebs|Hecht|Forellen",
	lakeGens = "see",
	works = { works = "Eisen|Hütten|Hammer|Schmelz|Stahl", quarry = "Stein|Kalk|Schiefer|Basalt", mine = "Kohl|Erz|Kupfer|Silber|Zinn",
		mill = "Mühl|Weber", farm = "Hof|Korn|Gut", brewery = "Malz|Hopfen", timber = "Säge|Holz" },
	worksGens = "-tal|-feld|-hausen|-dorf|-stadt|-grund|-au|-heim|-berg",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Zweiwasser confluence:.9 ?confluence +g
Dreiflüssen confluence ?confluence:.9 +g
Seeufer lake ?lake:.8 +g
Eichenhain oak ?oak:.6 +g
Birkenhain birch ?birch:.6 +g
Lindenhain lime ?lime:.6 +g
Tannenhöhe fir spruce:.8 ?fir|spruce:.6 +g
Langenwiese meadow ?meadow:.6 +g
Breitenbruch marsh fen:.8 ?marsh|fen:.7 +g
Windeck ridge ?ridge:.8 +g
Bergfuss foot mountain:.5 ?foot:.8 +g
Talende valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Kaltenbrunn spring ?spring:.7 +g
Am_Wasserfall falls ?falls:.8 +g
Sandhaken spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Steinbucht bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Klippenende cliff ?cliff:.7 +g
An_der_Brücke bridge ?bridge:.9 +g
Zur_Furt ford ?ford:.9 ?brook:.6 +g
%shafen river:.5 coast:.4 +k
%s_an_der_Bucht bay coast:.6 +k
Langen%l plain:.3 +k
%s-Siedlung plain:.3 +k
Gartenstadt_%s plain:.4 +k
%swerder island +k
%s_im_Wald forest +k
Hinter%l edge:.3 +k
%s_an_der_See coast +k
%s-Strand sandy coast:.6 +k
Fischerhafen coast:.5 !fish +i
Fischersiel coast:.5 !fish +i
Ölheim !oil +i
Ölquell !oil +i
Ziegelhausen !clay +i
Lehmkuhlen !clay +i
Kohlenbach brook:.4 !coal +i
Schachtheim !coal +i
Steinbruch rock:.4 !stone +i
Bruchhausen !stone +i
Sägmühle river:.4 !timber +i
Holzhausen forest:.4 !timber +i
Meierhof field:.4 !farm +i
Kornhausen field:.4 !farm +i
Eisenhammer river:.3 !iron +i
Hüttental valley:.3 !iron +i
]],
	charForms61 = { hilltop = "Hohen%l %s_am_Berg", harbour = "%shafen", cove = "%s_an_der_Bucht", street = "Langen%l",
		company = "%s-Siedlung Neu%l", garden = "Gartenstadt_%s", island = "%swerder", market = "Markt_%s",
		forest = "%s_im_Wald %s_am_Wald", secluded = "Hinter%l", coastal = "%s_an_der_See %s-Strand" },
}

---------------------------------------------------------------------------
-- French (france / europe fr)

L.fr = {
	maxCons = 3, dbl = "lnrst", dropE = true, pOnly = true, noPhrasePre = true,
	shapes = "single:.05 frame:.15 saint:.15 article:.10 whole:.02 qualifier:.03",
	-- (NEXT_PHASE_BRIEF 53 Part B, review Q6: saint names more often on a tropical map)
	climate = { tropical = { shapes = "single:.05 frame:.08 saint:.25 article:.10 whole:.03 qualifier:.03" } },
	areas = { core = "centre", coast = "nord", edge = { "sud" } },
	articles = { m = "Le", f = "La", mp = "Les", fp = "Les", el = "L'" },
	compat = { "nord:centre", "sud:centre" },
	spec = [[
Beau any:.5 vale:.3 slope:.3
Belle any:.5 vale:.3
Haute hilltop:.6 slope:.4
Bonne any:.4 meadow:.3
Grand big:.6 any:.3
Clair spring:.5 any:.3
Roche rock:.9 =roche
Pierre rock:.7 =roche
Mont hill:.7 =mont
Font spring:.8 =font
Chesn oak:.9 +t
Fresn ash:.9 +t
Aulne alder +t
Saule willow +t
Orme elm +t
Til lime:.7 +t
Boul birch +t
Coudre hazel +t
Fa beech:.8 +t
Pommer apple +t
Pin pine +t
Sapin fir +t
Tremble poplar +t
Verne alder:.8 marsh:.3 +t
Sable sandy
Lande heath
Bruyère heath:.9
Combe combe:.8
Moulin river:.5 brook:.5
Vigne slope:.6 field:.3 @sud
Olive field:.4 slope:.3 @sud
Garrigue heath:.7 rock:.4 @sud *
Causse rock:.6 heath:.5 @sud *
Cap headland:.8
Mer coast:.7
Port bay:.7 coast:.6 =port
Blanche cliff:.5 rock:.4
Rouge rock:.4 any:.3
Verte meadow:.5 forest:.3
Noir forest:.4 any:.3
Neuf new:.7
Vieux old:.7
Aube +p any
Ange +p any
Bou +p any
Cler +p any
Coul +p any
Dam +p any
Fré +p any
Gerv +p any
Hen +p any
Lou +p any
Mau +p any
Oth +p any
Rom +p any
Thi +p any
Vau +p any
Herb +p any
Ger +p any
Bern +p any
Arn +p any
Ber +p any
Savign +p any @sud
Juill +p any @nord
Aurign +p any @sud
Flor +p any @sud
Marsill +p any @sud
Lavern +p any @sud
Cogn +p any
Tourn +p any
Montign +p any
Brign +p any @sud
Chamb +p any
Rouv +p any @nord
brun|brune any:.3 heath:.3
fort|forte hilltop:.5 old:.4
bel|belle vale:.3 any:.4
blanc|blanche cliff:.5 rock:.5
clair|claire spring:.5 lake:.3 any:.3
vert|verte meadow:.5 forest:.3
haut|haute hilltop:.6
aigu|aiguë hilltop:.7 rock:.4
vieux|vieille old:.6
neuf|neuve new:.8
fleuri|fleurie meadow:.6
rond|ronde hilltop:.3 any:.3
bas|basse foot:.5
long|longue vale:.4
doux|douce vale:.3
chaud|chaude spring:.5 slope:.3
froid|froide spring:.4 mountain:.3
boisé|boisée forest:.7
sombre|sombre forest:.4
joli|jolie any:.4
des_Saules willow
des_Aulnes alder
des_Chênes oak
des_Frênes ash
des_Pins pine
des_Sapins fir
des_Bouleaux birch
des_Hêtres beech
de_l'Orme elm
du_Moulin river:.5 brook:.5
de_la_Rivière river =riviere
des_Étangs pool marsh:.3
de_la_Mer coast
des_Dunes sandy coast:.5
des_Rochers rocky rock:.5
de_la_Falaise cliff
de_la_Pointe headland spit:.6
de_l'Île island
du_Marais marsh fen:.6 =marais
des_Landes heath moor:.4
des_Prés meadow
des_Champs field =champ
du_Col pass
de_la_Combe combe =val
du_Val vale =val
de_la_Roche rock =roche
du_Gué ford =pont
des_Sources spring =font
de_la_Vallée valley =val
du_Bois forest =bois
de_la_Clairière clearing
du_Confluent confluence *
de_l'Estuaire mouth *
du_Lac lake mere:.5
de_la_Crête ridge
du_Puy hilltop *
des_Vignes slope:.5 field:.3
Palmiste palm tropic:.5 *
Sec arid:.5 any:.3
Neige snow boreal:.4
]],
	gen = [[
-ville any:.6 plain:.4 @nord
-court any:.5 field:.4 @nord +n
-mont hill hilltop:.6 =mont
-val vale =val +o
-fontaine spring =font +o
-champ field =champ
-champs field:.9 =champ
-bourg old:.6 market:.5 hilltop:.4 +o
-ac any:.7 +p @sud
-y any:.6 +p @nord
-ières any:.5 field:.3 @centre +n
-roche rock =roche +o
-lieu any:.5 church:.3
-mesnil any:.4 field:.4 @nord * +n
-ay forest:.7 edge:.5 +t =grove
-oy forest:.7 edge:.5 +t @nord =grove
-aie forest:.6 edge:.6 +t * =grove
Mont^ hill hilltop:.7 ~m =mont
Val^ vale valley:.8 ~m =val
Roche^ rock cliff:.6 ~f =roche
Font^ spring ~f =font
Fontaine^ spring:.9 ~f * =font
Pont- bridge river:.5 =pont
Port- bay coast:.8 =port
Bois- forest =bois
Mont- hill hilltop:.5 =mont
Gué- ford river:.5 =pont
Fontaine- spring =font
Val- vale valley:.7 =val
Roche- rock cliff:.4 =roche
Moulin- river:.6 brook:.5
Plaine- plain field:.5 *
Anse- bay coast:.6 tropic:.5
Morne- hilltop:.8 tropic:.5
Récif- reef tropic:.4 *
]],
	affix = [[
%s-sur-Mer coast sandy:.6
%s-sur-%r river bend:.4
%s-les-Bains spring *
%s-en-Forêt clearing forest:.7
%s-en-Montagne mountain *
%s-en-Plaine plain field:.5
%s-en-Vallée valley:.9
%s-le-Château hilltop:.6 old:.8 character:.5 *
%s-la-Forêt edge:.8
%s-le-Haut slope:.7 hilltop:.5 +q
%s-le-Bas foot:.7 vale:.5 +q
%s-le-Grand big +q
%s-le-Petit small +q
%s-le-Marais marsh fen:.7
%s-du-Lac lake
%s-la-Côte slope:.5 coast:.4
%s-aux-Bois forest:.8
%s-l'Étang pool marsh:.4
%p character:.8 church:.7 *
Haut-%s upper +q
Bas-%s lower +q
Condé-sur-%r confluence
%s-les-Cascades falls *
%s-du-Col pass:.8 range:.5 *
%s-Nord north:.8 * +q
%s-Sud south:.8 * +q
]],
	saints = "Saint-Aubin|Saint-Brieuc|Saint-Gildas|Saint-Rémy|Saint-Didier|Saint-Florent|Saint-Gervais|Saint-Hilaire|Saint-Léger|Saint-Loup|Saint-Médard|Saint-Ouen|Saint-Prix|Saint-Savin|Saint-Ursin|Saint-Valery|Saint-Yrieix|Sainte-Colombe|Sainte-Foy|Sainte-Marie",
	rivers = "Loue|Orne|Aube|Vire|Risle|Touques|Dives|Sarthe|Indre|Creuse|Allier|Sioule|Dore|Lot|Aveyron|Agout|Orb|Aude|Gers|Drôme|Isère|Ain|Doubs|Saône|Ognon|Meurthe|Aisne|Oise|Somme|Authie|Canche|Lys|Scarpe|Yonne|Cure|Armançon|Loing|Essonne|Eure|Vienne|Charente|Dronne|Vézère|Céou|Dropt|Baïse|Save|Vendée|Sèvre|Mayenne|Huisne|Loir|Cher|Arroux|Bourbince|Seille|Ouche|Tille|Vingeanne|Marne|Ornain|Saulx|Blaise",
	riverSyl = { "Ar|Bré|Dou|Lau|Mau|Or|Ser|Ve|Clai|Ver|Lan|Bel|Sau|Til|Aul",
		"ne|se|re|ve|ance|ette|ouze|on|eille|ize" },
	works = { works = "Forges|Usine|Fonderie|Ateliers", quarry = "Carrières|Pierre", mine = "Mines|Houillères",
		mill = "Moulins|Filature", farm = "Grange|Ferme", brewery = "Brasserie", timber = "Scierie" },
	worksForm = "%w-de-%s|%w-%s",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Les_Deux-Eaux confluence:.9 ?confluence +g
Trois-Rivières confluence ?confluence:.9 +g
Bellevue-sur-Mer coast hilltop:.6 ?coast:.5 ?hilltop|cliff|slope:.5 +g
Bord-du-Lac lake ?lake:.8 +g
La_Chênaie oak ?oak:.6 +g
La_Frênaie ash ?ash:.6 +g
La_Saulaie willow ?willow:.6 +g
La_Pinède pine ?pine:.6 +g
Grand-Pré meadow ?meadow:.6 +g
La_Crête ridge ?ridge:.8 +g
Pied-du-Mont foot mountain:.5 ?foot:.8 +g
Bout-du-Val valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Bellefontaine spring ?spring:.7 +g
Les_Cascades falls ?falls:.8 +g
Pointe-de-Sable spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Baie-des-Rochers bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Les_Falaises cliff ?cliff:.7 +g
Les_Ponts bridge ?bridge:.9 +g
Le_Gué ford ?ford:.9 ?brook:.6 +g
Mont-%s hilltop:.6 +k
Port-%s river:.5 coast:.4 +k
%s-la-Crique bay coast:.6 +k
%s-la-Rue plain:.3 +k
Cité-%s plain:.3 +k
%s-Cité-Jardin plain:.4 +k
%s-en-l'Île island +k
%s-le-Marché market:.5 +k
%s-du-Bout edge:.3 +k
%s-Plage sandy coast:.6 +k
Les_Pêcheries coast:.5 !fish +i
Port-Pêcheur coast:.5 !fish +i
Les_Puits !oil +i
Puits-Pétrole !oil +i
La_Tuilerie !clay +i
Les_Briqueteries !clay +i
Les_Houillères !coal +i
Charbonnières !coal +i
Les_Carrières rock:.4 !stone +i
La_Carrière rock:.4 !stone +i
La_Scierie forest:.4 !timber +i
Les_Scieries forest:.3 !timber +i
La_Grange field:.4 !farm +i
La_Métairie field:.4 !farm +i
Les_Forges river:.3 !iron +i
La_Forge !iron +i
]],
	charForms61 = { hilltop = "Mont-%s %s-le-Château", harbour = "Port-%s", cove = "%s-la-Crique", street = "%s-la-Rue",
		company = "Cité-%s", garden = "%s-Cité-Jardin", island = "%s-en-l'Île", market = "%s-le-Marché",
		forest = "%s-en-Forêt %s-la-Forêt", secluded = "%s-du-Bout", coastal = "%s-sur-Mer %s-Plage" },
}

---------------------------------------------------------------------------
-- Italian (italy / europe it): generic first, the adjective agreeing

L.it = {
	maxCons = 3, dbl = "lnrstcpgfmbdvz", dropE = false, vv = true,
	shapes = "single:.10 frame:.10 saint:.20 article:.10 whole:.02 qualifier:.03",
	climate = { tropical = { shapes = "single:.08 frame:.06 saint:.30 article:.10 whole:.03 qualifier:.03" } },
	articles = { m = "Il", f = "La", mp = "I", fp = "Le", el = "L'" },
	spec = [[
alto|alta hill:.6 hilltop:.4
basso|bassa foot:.5 vale:.3 =inf
bello|bella any:.5 vale:.3
nuovo|nuova new:.7 any:.3
vecchio|vecchia old:.7
franco|franca any:.5
rosso|rossa rock:.4 any:.3
bianco|bianca cliff:.5 rock:.4
nero|nera forest:.4 any:.2
verde|verde meadow:.5 forest:.4
chiaro|chiara spring:.5 lake:.3
fiorito|fiorita meadow:.6
grande|grande big:.6
piccolo|piccola small:.6
lungo|lunga vale:.4 ridge:.3
largo|larga vale:.5
secco|secca heath:.4 plain:.3
fresco|fresca spring:.4 forest:.3
ombroso|ombrosa forest:.5 edge:.4
petroso|petrosa rock:.7
sereno|serena any:.4
ventoso|ventosa ridge:.5 hilltop:.4
dolce|dolce vale:.4 any:.3
freddo|fredda spring:.3 mountain:.4
salso|salsa marsh:.4 coast:.4
oscuro|oscura forest:.5
forte|forte hilltop:.5 old:.3
del_Lupo forest:.4 mountain:.3
del_Cervo forest:.4
del_Falco cliff:.4 hilltop:.3
del_Pino pine
della_Quercia oak
del_Faggio beech
dei_Castagni beech:.4 forest:.5
degli_Olivi field:.4 slope:.3
del_Salice willow
dell'Ontano alder
del_Frassino ash
della_Betulla birch
dell'Abete fir
del_Larice larch
del_Tiglio lime
dell'Acero maple
della_Palma palm
del_Cipresso cypress
del_Noce forest:.4
del_Sasso rock:.8
del_Sole slope:.4 any:.3
del_Vento ridge:.4
del_Rivo brook
della_Vigna slope:.5 field:.3
dei_Pini pine
delle_Querce oak
del_Gufo forest:.4 *
del_Lago lake =lago
della_Fonte spring =fonte
del_Ponte bridge =ponte
del_Guado ford
della_Foce mouth
dei_Due_Fiumi confluence *
della_Palude marsh fen:.5
della_Brughiera heath
del_Colle hill =monte
della_Cima hilltop
del_Passo pass
della_Gola gorge
della_Spiaggia sandy
dello_Scoglio rocky cliff:.5
della_Punta headland spit:.5 =capo
dei_Prati meadow
dei_Campi field
della_Radura clearing
santo|santa church:.6 *
lieto|lieta any:.4
ameno|amena vale:.4 meadow:.3
secco|secca arid:.6
nevoso|nevosa snow boreal:.4
]],
	gen = [[
Monte^ hill hilltop:.6 ~m =monte
Castel^ hilltop:.7 old:.6 ~m =castel
Villa^ any:.5 plain:.5 ~f
Porto^ bay coast:.8 ~m =porto
Pietra^ rock ~f =pietra
Rocca^ rock:.8 hilltop:.7 ~f =pietra +o
Fonte^ spring ~f =fonte
Colle^ hill:.9 slope:.5 ~m =monte +o
Val^ vale valley:.8 ~f =valle
Serra^ ridge ~f =monte
Poggio^ hilltop:.9 ~m =monte +o
Campo^ field plain:.6 ~m
Borgo^ market:.7 old:.5 ~m +o
Torre^ any:.5 hilltop:.3 ~f +o
Acqua^ spring:.8 brook:.5 ~f =fonte
Ponte^ bridge river:.5 ~m =ponte
Bosco^ forest ~m =bosco
Selva^ forest:.9 ~f =bosco +o
Isola^ island ~f
Capo^ headland ~m =capo
Pian^ plain vale:.5 ~m
Prato^ meadow ~m
Lago^ lake ~m =lago
Torre_ any:.5 ~f
Borgo_ market:.6 ~m
Marina_ sandy coast:.8 ~f =porto
Pieve_ church old:.4 ~f
Bagni_ spring ~mp =fonte
Palma_ palm tropic:.6 ~f
Laguna_ lagoon tropic:.4 ~f
]],
	affix = [[
%s_di_Mare coast
Marina_di_%s sandy coast:.7 *
Lido_di_%s sandy *
%s_sul_%r river bend:.4
%s_del_Lago lake
%s_al_Monte foot:.6 slope:.5
%s_in_Valle valley:.8
%s_del_Bosco forest:.8 edge:.5
%s_Superiore slope:.7 =sup +q
%s_Inferiore foot:.7 =inf +q
Borgo_%s any:.2
%s_Paese any:.2
%s_Terme spring
Pieve_di_%s church:.5
%s_Scalo new:.4 +v
%p character:.8 church:.7 *
Bocca_di_%t mouth
%s_Alta upper * +q
%s_Bassa lower * +q
%s_delle_Cascate falls *
%s_al_Passo pass:.8 range:.5 *
]],
	saints = "San Giorgio|Santa Lucia|Sant'Elia|San Martino|Santa Maria|San Vito|San Donato|Santa Croce|San Rocco|Sant'Angelo|San Biagio|San Lorenzo|San Michele|Santa Fiora|San Quirico|Sant'Ilario",
	rivers = "Serio|Oglio|Brembo|Taro|Enza|Panaro|Savio|Metauro|Esino|Tronto|Aterno|Sangro|Biferno|Ofanto|Sele|Liri|Volturno|Ombrone|Serchio|Magra|Vara|Tanaro|Stura|Orco|Sesia|Lambro|Mincio|Chiese|Brenta|Piave|Livenza|Cecina|Cornia|Fiora|Paglia|Chiana|Nera|Velino|Tenna|Aso|Cesano|Musone|Potenza|Chienti|Sinni|Agri|Basento|Bradano|Crati|Neto|Simeto|Salso|Belice",
	riverSyl = { "Bar|Cel|Fer|Lam|Mel|Ser|Tor|Var|Gor|Lin|Pes|Sol",
		"io|ano|ente|one|ino|aro|ello" },
	works = { works = "Officine|Ferriere|Fonderia", quarry = "Cave|Marmi", mine = "Miniere", mill = "Mulini",
		farm = "Cascina|Masseria", brewery = "Birrificio", timber = "Segheria" },
	worksForm = "%w_di_%s|%s_%w",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Dueacque confluence:.9 ?confluence +g
Trefiumi confluence ?confluence:.9 +g
Riva_del_Lago lake ?lake:.8 +g
Querceta oak ?oak:.6 +g
Frassineto ash ?ash:.6 +g
Saliceto willow ?willow:.6 +g
Pineta pine ?pine:.6 +g
Pratolungo meadow ?meadow:.6 +g
Cresta_del_Vento ridge ?ridge:.8 +g
Piedimonte foot mountain:.5 ?foot:.8 +g
Capovalle valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Fontanafredda spring ?spring:.7 +g
Le_Cascate falls ?falls:.8 +g
Punta_Sabbiosa spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Cala_Rocciosa bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Scogliera cliff ?cliff:.7 +g
Pontegrande bridge ?bridge:.9 +g
Il_Guado ford ?ford:.9 ?brook:.6 +g
%s_in_Collina hilltop:.6 +k
Porto_%s river:.5 coast:.4 +k
Cala_%s bay coast:.6 +k
Villaggio_%s plain:.3 +k
%s_Città_Giardino plain:.4 +k
Isola_%s island +k
Mercato_%s market:.5 +k
Fondo_%s edge:.3 +k
Peschiera coast:.5 lake:.4 !fish +i
Marina_dei_Pescatori coast:.5 !fish +i
I_Pozzi !oil +i
Pozzo_Nero !oil +i
Fornace !clay +i
Le_Fornaci !clay +i
Carbonia !coal +i
Miniera !coal +i
Le_Cave rock:.4 !stone +i
Pietrasanta rock:.4 !stone +i
La_Segheria forest:.4 !timber +i
Segheria_Vecchia forest:.3 !timber +i
La_Cascina field:.4 !farm +i
Masseria field:.4 !farm +i
Ferriera river:.3 !iron +i
Le_Ferriere !iron +i
]],
	charForms61 = { hilltop = "%s_in_Collina %s_Alta", harbour = "Porto_%s", cove = "Cala_%s", street = "Borgo_%s",
		company = "Villaggio_%s", garden = "%s_Città_Giardino", island = "Isola_%s", market = "Mercato_%s",
		forest = "%s_del_Bosco", secluded = "Fondo_%s", coastal = "Marina_di_%s Lido_di_%s %s_di_Mare" },
}

---------------------------------------------------------------------------
-- Spanish (spain / europe es)

L.es = {
	maxCons = 3, dbl = "lnrc", dropE = false, vv = true,
	shapes = "single:.10 frame:.10 saint:.20 article:.10 whole:.02 qualifier:.03",
	climate = { tropical = { shapes = "single:.08 frame:.06 saint:.30 article:.10 whole:.03 qualifier:.03" } },
	articles = { m = "El", f = "La", mp = "Los", fp = "Las" },
	spec = [[
alto|alta hill:.6 hilltop:.4
nuevo|nueva new:.7 any:.3
viejo|vieja old:.7
verde|verde meadow:.5 forest:.3
blanco|blanca cliff:.5 rock:.4
rubio|rubia field:.4
llano|llana plain:.8
hermoso|hermosa any:.5
real|real market:.4 character:.3
rojo|roja rock:.4
negro|negra forest:.3 any:.2
claro|clara spring:.5
fresco|fresca spring:.4 forest:.3
seco|seca heath:.5
mayor|mayor big:.7
chico|chica small:.6
largo|larga vale:.4
hondo|honda gorge:.5 valley:.5
frío|fría spring:.3 mountain:.3
dulce|dulce vale:.3
florido|florida meadow:.6
oscuro|oscura forest:.4
franco|franca any:.4
bajo|baja foot:.5 =abajo
luengo|luenga vale:.4 *
salado|salada marsh:.4 coast:.4
pedroso|pedrosa rock:.7
ventoso|ventosa ridge:.5 hilltop:.4
umbrío|umbría forest:.5 edge:.4
soleado|soleada slope:.5
pardo|parda heath:.5
sereno|serena any:.4
bello|bella any:.5 vale:.3
bueno|buena any:.5
santo|santa church:.6 *
del_Pino pine
del_Roble oak
de_la_Encina oak:.7
del_Fresno ash
del_Olmo elm
del_Sauce willow
del_Aliso alder
del_Abedul birch
del_Haya beech
del_Castaño beech:.4 forest:.5
del_Abeto fir
del_Laurel forest:.4
de_la_Palma palm
del_Lobo forest:.4 mountain:.3
del_Toro field:.3
del_Sol slope:.4 any:.3
del_Viento ridge:.4
de_la_Rosa meadow:.3
de_los_Pinos pine
del_Encinar oak
de_la_Fresneda ash
del_Robledo oak
del_Águila cliff:.4 mountain:.4 *
de_la_Peña rock:.8
del_Río river
del_Vado ford
de_la_Fuente spring =fuente
del_Puente bridge
de_las_Dos_Aguas confluence *
de_la_Ribera river:.6 meadow:.5
de_la_Marisma marsh fen:.6
del_Páramo moor heath:.5
del_Cerro hilltop
del_Puerto pass
de_la_Hoz gorge
de_la_Playa sandy
de_las_Rocas rocky
de_la_Punta headland spit:.5 =cabo
de_la_Isla island
de_la_Laguna pool
del_Lago lake
de_los_Prados meadow
de_los_Campos field
de_la_Vega vale meadow:.4
seco|seca arid:.6
nevado|nevada snow boreal:.4
]],
	gen = [[
Villa^ any:.5 plain:.5 ~f
Puerto^ bay coast:.8 ~m =puerto
Monte^ hill hilltop:.6 ~m =monte
Peña^ rock cliff:.5 ~f =pena
Torre^ any:.5 hilltop:.3 ~f +o
Fuente^ spring ~f =fuente
Val^ vale valley:.7 ~m =val
Castro^ hilltop:.7 old:.6 ~m +o
Campo^ field ~m
Sierra_ ridge mountain:.6 ~f =monte
Vega_ meadow vale:.5 river:.3 ~f
Cabo_ headland ~m =cabo
Playa_ sandy ~f =puerto
Isla_ island ~f
Laguna_ pool:.9 lake:.6 marsh:.4 ~f
Puente_ bridge ~m
Cala_ bay rocky:.5 ~f =puerto
Prado_ meadow ~m
Valle_ valley vale:.6 ~m
Cerro_ hilltop hill:.6 ~m
Arroyo_ brook river:.5 ~m
Casas_ any:.5 ~fp
Navas_ vale:.6 plain:.5 ~fp
Hoya_ combe valley:.5 ~f
Llano_ plain ~m
Barranco_ gorge ~m
Ribera_ river:.7 meadow:.5 ~f
Mesa_ hilltop:.6 plain:.4 ~f
Collado_ pass ~m
Soto_ river:.5 forest:.6 ~m +o
Castillo_ hilltop:.6 old:.6 ~m
Molinos_ river:.5 brook:.5 ~mp
Pozo_ spring:.6 ~m +o
Ciudad_ big market:.8 ~f
Villar^ any:.5 field:.3 ~m +o
Nava^ vale:.6 plain:.5 ~f +o
Palmar_ palm tropic:.6 ~m
Cayo_ island:.7 tropic:.5 lagoon:.4 ~m
Laguna_ lagoon tropic:.4 ~f
Manglar_ mangrove tropic:.4 ~m
Rambla_ wadi arid:.5 ~f
Arenal_ dune arid:.4 ~m
Mesa_ mesa arid:.4 ~f
]],
	affix = [[
%s_de_la_Sierra mountain:.8 ridge:.6
%s_del_Río river
%s_de_%r river bend:.4
%s_del_Mar coast
%s_de_la_Vega vale:.8 meadow:.6
%s_del_Monte forest:.5 hill:.5
%s_de_Arriba slope:.7 hilltop:.5 =arriba +q
%s_de_Abajo foot:.7 =abajo +q
%s_del_Campo field:.8 plain:.6
%s_de_la_Laguna pool:.8 marsh:.4
%s_de_los_Pinos pine *
Aldea_de_%s small:.6 any:.2
%s_de_Suso slope:.5 * +q
%s_de_Yuso foot:.5 * +q
%p character:.8 church:.7 *
Juntas_de_%t confluence
Las_Juntas confluence:.9 *
%s_del_Salto falls
%s_del_Puerto pass:.8 range:.5 *
%s_del_Norte north:.8 * +q
%s_del_Sur south:.8 * +q
]],
	saints = "San Martín|Santa Lucía|San Esteban|San Millán|Santa Eulalia|San Vicente|San Román|Santa Cruz|San Ginés|Santo Domingo|San Cristóbal|Santa Olalla|San Pelayo|San Lorenzo|Santa Marina",
	rivers = "Jarama|Henares|Tajuña|Alberche|Tiétar|Alagón|Jerte|Esla|Órbigo|Pisuerga|Arlanza|Arlanzón|Carrión|Cea|Tormes|Huebra|Eresma|Cega|Duratón|Riaza|Jalón|Jiloca|Huerva|Cinca|Segre|Gállego|Arga|Ega|Iregua|Najerilla|Oja|Tirón|Zadorra|Bayas|Deba|Urola|Oria|Bidasoa|Sil|Cabe|Ulla|Tambre|Navia|Narcea|Nalón|Sella|Deva|Besaya|Saja|Asón|Zújar|Genil|Darro|Segura|Mundo|Júcar|Cabriel|Turia|Mijares",
	riverSyl = { "Al|Bar|Cer|Gua|Lor|Mar|Tar|Val|Tor|Ar",
		"ama|ares|ena|uña|era|ón|illa|ero" },
	works = { works = "Fábricas|Fundición|Talleres", quarry = "Canteras", mine = "Minas", mill = "Molinos",
		farm = "Granja|Cortijo", brewery = "Cervecería", timber = "Aserradero" },
	worksForm = "%w_de_%s",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Dos_Aguas confluence:.9 ?confluence +g
Tres_Ríos confluence ?confluence:.9 +g
Orilla_del_Lago lake ?lake:.8 +g
Robledo oak ?oak:.6 +g
Fresneda ash ?ash:.6 +g
Saucedo willow ?willow:.6 +g
El_Pinar pine ?pine:.6 +g
Vega_Larga meadow ?meadow:.6 +g
Cuerda_del_Viento ridge ?ridge:.8 +g
Piedemonte foot mountain:.5 ?foot:.8 +g
Cabeza_del_Valle valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Fuente_Fría spring ?spring:.7 +g
El_Salto_Grande falls ?falls:.8 +g
Punta_Arenas spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Bahía_Rocosa bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Los_Acantilados cliff ?cliff:.7 +g
El_Puente bridge ?bridge:.9 +g
El_Vado ford ?ford:.9 ?brook:.6 +g
Alto_%s hilltop:.6 +k
Puerto_%s river:.5 coast:.4 +k
Cala_%s bay coast:.6 +k
%s_de_la_Calzada plain:.3 +k
Colonia_%s plain:.3 +k
%s_Ciudad_Jardín plain:.4 +k
Isla_%s island +k
%s_del_Mercado market:.5 +k
%s_del_Bosque forest +k
%s_del_Confín edge:.3 +k
%s_de_la_Playa sandy coast:.6 +k
Los_Pescadores coast:.5 !fish +i
Puerto_Pesquero coast:.5 !fish +i
Los_Pozos !oil +i
Pozos_Negros !oil +i
Los_Tejares !clay +i
Las_Ladrilleras !clay +i
Carboneras !coal +i
Las_Minas !coal +i
La_Cantera rock:.4 !stone +i
Pedrera rock:.4 !stone +i
El_Aserradero forest:.4 !timber +i
La_Serrería forest:.3 !timber +i
La_Granja field:.4 !farm +i
El_Cortijo field:.4 !farm +i
La_Ferrería river:.3 !iron +i
Herrería !iron +i
]],
	charForms61 = { hilltop = "Alto_%s", harbour = "Puerto_%s", cove = "Cala_%s", street = "%s_de_la_Calzada",
		company = "Colonia_%s", garden = "%s_Ciudad_Jardín", island = "Isla_%s", market = "%s_del_Mercado",
		forest = "%s_del_Bosque", secluded = "%s_del_Confín", coastal = "%s_del_Mar %s_de_la_Playa" },
}

---------------------------------------------------------------------------
-- Portuguese (portugal)

L.pt = {
	maxCons = 3, dbl = "lnrs", dropE = false, vv = true,
	shapes = "single:.10 frame:.10 saint:.20 article:.10 whole:.02 qualifier:.03",
	climate = { tropical = { shapes = "single:.08 frame:.06 saint:.30 article:.10 whole:.03 qualifier:.03" } },
	articles = { m = "O", f = "A", mp = "Os", fp = "As" },
	spec = [[
alto|alta hill:.6 hilltop:.4
novo|nova new:.7 any:.3
velho|velha old:.7
verde|verde meadow:.5 forest:.3
branco|branca cliff:.5 rock:.4
preto|preta forest:.3 any:.2
grande|grande big:.6
pequeno|pequena small:.6
bom|boa any:.5
belo|bela any:.5 vale:.3
alegre|alegre any:.4
formoso|formosa any:.4 meadow:.3
fundo|funda gorge:.5 valley:.4
seco|seca heath:.5
frio|fria spring:.3 mountain:.3
claro|clara spring:.5
escuro|escura forest:.4
real|real market:.4
maior|maior big:.7
florido|florida meadow:.6
dourado|dourada sandy:.4 field:.3
salgado|salgada marsh:.4 coast:.4
chão|chã plain:.7
do_Pinhal pine
dos_Carvalhos oak
das_Faias beech
dos_Freixos ash
do_Salgueiro willow
dos_Amieiros alder
dos_Castanheiros beech:.4 forest:.5
do_Lobo forest:.4 mountain:.3
do_Sol slope:.4 any:.3
das_Oliveiras field:.4 slope:.3
do_Vento ridge:.4
da_Penha rock:.8
dos_Moinhos river:.5 brook:.4
do_Rio river
do_Vau ford
da_Fonte spring
da_Ponte bridge
dos_Dois_Rios confluence *
da_Foz mouth
do_Paul marsh fen:.6
da_Charneca heath
do_Alto hilltop
da_Portela pass
do_Barranco gorge
da_Areia sandy
das_Rochas rocky
da_Ponta headland spit:.5 =cabo
do_Lago lake
dos_Prados meadow
dos_Campos field
da_Clareira clearing
santo|santa church:.6 *
seco|seca arid:.6
nevado|nevada snow boreal:.4
]],
	gen = [[
Vila_ any:.6 plain:.5 ~f
Porto_ bay coast:.8 ~m =porto
Monte_ hill ~m =monte
Castelo_ hilltop:.7 old:.6 ~m
Fonte_ spring ~f
Ponte_ bridge river:.4 ~f
Serra_ ridge mountain:.6 ~f =monte
Vale_ vale ~m
Campo_ field ~m
Torres_ any:.5 ~fp +o
Ribeira_ river:.8 brook:.5 ~f
Praia_ sandy ~f =porto
Penha_ rock:.9 cliff:.5 ~f +o
Lagoa_ pool:.9 lake:.7 ~f
Póvoa_ any:.5 ~f +o
Barra_ mouth:.9 spit:.5 ~f
Ilha_ island ~f
Cabo_ headland ~m =cabo
Mata_ forest:.8 ~f +o
Souto_ forest:.7 beech:.4 ~m +o
Granja_ field:.6 ~f +o
Prado_ meadow ~m
Palmeiras_ palm tropic:.6 ~fp
Recife_ reef tropic:.5 ~m
Lagoa_ lagoon tropic:.4 ~f
Mangue_ mangrove tropic:.4 ~m
Sertão_ arid:.6 plain:.4 ~m
Areal_ dune arid:.4 ~m
]],
	affix = [[
%s_do_Mar coast
%s_da_Serra mountain:.8 ridge:.6
%s_de_%r river bend:.4
%s_do_Rio river
%s_da_Ribeira brook:.8
%s_do_Campo field:.8
%s_de_Cima slope:.7 +q
%s_de_Baixo foot:.7 +q
%s_da_Barra mouth:.8
Aldeia_de_%s small:.6 any:.2
%s_de_Além any:.2
%p character:.8 church:.7 *
Foz_do_%t mouth
Entre-os-Rios confluence:.9 *
%s_da_Cascata falls *
%s_do_Norte north:.8 * +q
%s_do_Sul south:.8 * +q
]],
	saints = "São Martinho|Santa Luzia|São Pedro|São Mamede|Santa Comba|São Vicente|São Romão|Santa Cruz|São Brás|São Cristóvão|Santa Marinha|São Lourenço|Santa Eulália|São Bento",
	rivers = "Sado|Mondego|Vouga|Cávado|Tâmega|Sousa|Paiva|Côa|Zêzere|Nabão|Alva|Ceira|Dão|Sorraia|Almonda|Alviela|Mira|Arade|Tua|Sabor|Corgo|Neiva|Ave|Este|Leça|Ferreira|Caima|Antuã|Odeleite|Vascão|Degebe|Xarrama|Raia|Seda|Erges|Ponsul|Ocreza",
	riverSyl = { "Al|Bar|Cer|Mon|Sal|Tor|Val|Ver",
		"ega|ado|ira|ena|ão|ela" },
	works = { works = "Fábrica|Fundição|Oficinas", quarry = "Pedreiras", mine = "Minas", mill = "Moinhos",
		farm = "Quinta|Herdade", brewery = "Cervejaria", timber = "Serração" },
	worksForm = "%w_de_%s",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Duas_Águas confluence:.9 ?confluence +g
Três_Rios confluence ?confluence:.9 +g
Beira-Lago lake ?lake:.8 +g
Carvalhal oak ?oak:.6 +g
Freixial ash ?ash:.6 +g
Salgueiral willow ?willow:.6 +g
Pinhal pine ?pine:.6 +g
Prado_Longo meadow ?meadow:.6 +g
Cumeada ridge ?ridge:.8 +g
Pé_do_Monte foot mountain:.5 ?foot:.8 +g
Cabeça_do_Vale valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Fonte_Fria spring ?spring:.7 +g
Cascata_Grande falls ?falls:.8 +g
Ponta_da_Areia spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Baía_das_Pedras bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Arribas cliff ?cliff:.7 +g
Ponte_Velha bridge ?bridge:.9 +g
Vau ford ?ford:.9 ?brook:.6 +g
%s_do_Alto hilltop:.6 +k
Porto_%s river:.5 coast:.4 +k
%s_da_Enseada bay coast:.6 +k
%s_da_Estrada plain:.3 +k
Colónia_%s plain:.3 +k
Jardim_%s plain:.4 +k
Ilha_%s island +k
%s_do_Mercado market:.5 +k
%s_da_Mata forest +k
%s_da_Praia sandy coast:.6 +k
Pescaria coast:.5 !fish +i
Vila_dos_Pescadores coast:.5 !fish +i
Os_Poços !oil +i
Poço_Negro !oil +i
Telheiras !clay +i
Olaria !clay +i
Carvoeiro !coal +i
As_Minas !coal +i
Pedreira rock:.4 !stone +i
Canteiros rock:.4 !stone +i
Serração forest:.4 !timber +i
Serração_Velha forest:.3 !timber +i
Granja field:.4 !farm +i
A_Quinta field:.4 !farm +i
Ferraria river:.3 !iron +i
A_Forja !iron +i
]],
	charForms61 = { hilltop = "%s_do_Alto %s_de_Cima", harbour = "Porto_%s", cove = "%s_da_Enseada", street = "%s_da_Estrada",
		company = "Colónia_%s", garden = "Jardim_%s", island = "Ilha_%s", market = "%s_do_Mercado",
		forest = "%s_da_Mata", secluded = "%s_de_Além", coastal = "%s_do_Mar %s_da_Praia" },
}

---------------------------------------------------------------------------
-- Dutch (netherlands / europe nl)

L.nl = {
	maxCons = 4, dbl = "lnrstk", dropE = false, pOnly = true,
	shapes = "single:.05 qualifier:.10 frame:.03 whole:.02",
	areas = { core = "midden", coast = "noord", edge = { "zuid" } },
	common = "Bergen|Egmond|Alphen|Wijk|Ouderkerk|Nieuwerkerk|Oosterhout|Zandvoort|Heemstede|Velsen",
	compat = {},
	spec = [[
Twee confluence:.7 brook:.4 =twee
Eiken oak
Eik oak:.8
Beuken beech
Berken birch
Linden lime
Elzen alder
Wilgen willow
Iepen elm
Hazel hazel
Dennen pine
Sparren spruce
Hulst holly
Essen ash
Beek brook:.8 =beek
Molen river:.5 brook:.4
Brug bridge:.6 =brug
Veer river:.6 ford:.4
Sluis river:.4 mouth:.5 fen:.3 =sluis
Dam river:.6 mouth:.4 =dam
Dijk fen:.6 coast:.4 =dijk
Zand sandy:.8 heath:.4
Duin sandy coast:.7 =duin
Zee coast:.8
Meer lake:.7 =meer
Ven pool:.8 fen:.5
Veen fen moor:.4 =veen
Broek marsh:.8 fen:.6 =broek
Moer marsh:.7 fen:.6
Riet marsh:.7
Heide heath =heide
Wei meadow
Gras meadow:.5
Klaver meadow:.5
Akker field:.7
Kamp field:.5
Berg hill:.8 =berg
Hoog hilltop:.6
Steen rock:.7
Kerk church =kerk
Klooster church:.9 old:.5 *
Wolfs forest:.4
Vos forest:.3 heath:.3
Hert forest:.5
Zwaan lake:.5
Reiger marsh:.5
Aal river:.4
Groen meadow:.4 any:.3
Wit sandy:.4
Zwart fen:.4 forest:.3
Schoon any:.4
Oost any:.3
West any:.3
Noord any:.3
Zuid any:.3
Ger +p any
Wal +p any
Hil +p any
Bar +p any
Ommel +p any
Harde +p any
Holte +p any
Eme +p any
Palm palm tropic:.5
Koraal reef tropic:.5
Droog arid:.6 any:.3
Sneeuw snow boreal:.4
]],
	gen = [[
-dam river:.8 mouth:.5 =dam
-dijk fen:.7 coast:.5 =dijk
-veen fen moor:.6 =veen +o
-horst edge:.8 forest:.6 hilltop:.3 +o
-wijk any:.6
-broek marsh fen:.6 =broek
-beek brook =beek
-hout forest
-bos forest:.9
-loo clearing:.8 edge:.6 +o +n
-rode clearing
-donk hilltop:.5 marsh:.4 * +o +n
-berg hill =berg
-heuvel hilltop:.9 =berg
-dal valley
-meer lake mere:.8 =meer
-ven pool
-sluis mouth:.7 river:.5 =sluis
-brug bridge =brug
-drecht ford river:.5 +n
-voort ford:.9
-duinen sandy coast:.7 =duin
-haven bay coast:.7
-oord headland:.7 river:.3
-waard island:.7 meadow:.5 river:.4 +n
-weerd island:.7 +n
-kerk church =kerk
-dorp any:.6
-hoven any:.5 +p @zuid
-um any:.6 @noord +n
-ingen any:.6 +p @noord
-werd hilltop:.5 coast:.4 @noord +n
-wolde forest:.7 fen:.3 @noord +n
-veld field heath:.4
-hei heath =heide
-kamp field:.7
-rade clearing:.9 @zuid +n
-lo edge:.7 +n
-gem any:.5 +p @zuid
-zele any:.5 +p @zuid *
-rif reef tropic:.4
-baai bay tropic:.4
]],
	affix = [[
%s_aan_Zee coast sandy:.6
%s_aan_de_%r river bend:.4
%s_aan_het_%k lake
Nieuw-%s new +q
Oud-%s old:.8 +q
Groot-%s big +q
Klein-%s small +q
Hoog-%s hilltop:.8 slope:.5 +q
Neder-%s foot:.5 fen:.5 +q
%p character:.8 church:.7 *
Noord-%s north +q
Zuid-%s south +q
Oost-%s east +q
West-%s west +q
%tmond mouth
Boven-%s upper +q
]],
	saints = "Sint-Oedenrode|Sint Jansklooster|Sint Odulphus|Sint Willebrord|Sint Servaas|Sint Victor|Sint Lambert|Sint Agatha|Sint Hubert|Sint Joost",
	rivers = "Dinkel|Regge|Vecht|Berkel|Linge|Dommel|Aa|Roer|Geul|Niers|Amstel|Gein|Angstel|Hunze|Reest|Boorne|Lauwers|Eem|Grift|Mark|Dintel|Donge|Rotte|Schie|Gouwe|Swalm|Worm|Jeker|Drentse Aa|Oude Rijn",
	riverSyl = { "Dre|Hol|Lin|Ber|Ve|Ro|Gou|Swa",
		"kel|ge|we|nte|ter|der" },
	lakes = "Eiken|Zwanen|Reiger|Riet|Berken|Wit|Zwart|Hoog|Diep|Klein|Groot",
	lakeGens = "meer|plas",
	works = { works = "IJzer|Smelt|Staal", quarry = "Steen|Kalk", mine = "Kolen|Mijn", mill = "Molen|Weef",
		farm = "Hoeve|Graan", brewery = "Brouw|Mout", timber = "Zaag|Hout" },
	worksGens = "-dorp|-wijk|-veld|-dam|-oord|-kamp",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Tweewater confluence:.9 ?confluence +g
Driestromen confluence ?confluence:.9 +g
Meeroever lake ?lake:.8 +g
Eikenhorst oak ?oak:.6 +g
Essenhout ash ?ash:.6 +g
Wilgenhoek willow ?willow:.6 +g
Dennenbos pine fir:.6 ?pine|fir:.6 +g
Langeweide meadow ?meadow:.6 +g
Breedeveen fen marsh:.6 ?fen|marsh:.7 +g
Windrug ridge ?ridge:.8 +g
Bergvoet foot mountain:.5 ?foot:.8 +g
Dalkop valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Koudebron spring ?spring:.7 +g
Zandpunt spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Steenbaai bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Klifrand cliff ?cliff:.7 +g
Bruggehoofd bridge ?bridge:.9 +g
De_Voorde ford ?ford:.9 ?brook:.6 +g
%shaven river:.5 coast:.4 +k
%skreek bay coast:.6 +k
Lange_%s plain:.3 +k
Tuinstad_%s plain:.4 +k
%swaard island +k
%smarkt market:.5 +k
%s_in_het_Bos forest +k
%s-Uithoek edge:.3 +k
%s-Strand sandy coast:.6 +k
Vissershaven coast:.5 !fish +i
Visserskreek coast:.5 !fish +i
Olieveld !oil +i
De_Bronnen !oil +i
Tichelwerk !clay +i
Steenoven !clay +i
De_Mijn !coal +i
Kolenberg !coal +i
Steengroeve rock:.4 !stone +i
De_Groeve rock:.4 !stone +i
Zaagmolen forest:.4 !timber +i
Houtzagerij forest:.3 !timber +i
De_Hoeve field:.4 !farm +i
Hoevedorp field:.4 !farm +i
De_Smidse river:.3 !iron +i
IJzerhut !iron +i
]],
	charForms61 = { hilltop = "Hoog-%s", harbour = "%shaven", cove = "%skreek", street = "Lange_%s", company = "Nieuw-%s",
		garden = "Tuinstad_%s", island = "%swaard", market = "%smarkt",
		forest = "%s_in_het_Bos", secluded = "%s-Uithoek", coastal = "%s_aan_Zee %s-Strand" },
}

---------------------------------------------------------------------------
-- Swedish (sweden / europe sv)

L.sv = {
	maxCons = 4, dbl = "lnrst", dropE = false,
	shapes = "single:.08 qualifier:.08 saint:.02",
	-- (NEXT_PHASE_BRIEF 53 Part B, review Q6: the subarctic map's bays, fjords and fells first)
	climate = { subarctic = { boost = "-vik -fjärd -fjäll -näs" } },
	areas = { core = "mitt", coast = "syd", edge = { "norr" } },
	compat = {},
	spec = [[
Ek oak
Björk birch
Lind lime
Ask ash
Al alder
Asp poplar
Hassel hazel
Alm elm
Bok beech
Gran spruce
Tall pine
Fur pine:.8 @norr
Vide willow
Rönn forest:.5
En heath:.5 forest:.3
Sjö lake:.8 =sjo
Bäck brook:.8 =back
Kvarn river:.6 brook:.5
Fors river:.8 gorge:.4 =fors
Strand sandy:.7 coast:.6
Sand sandy:.8
Vik bay:.8 =vik
Hav coast:.8
Sund coast:.6 spit:.5 =sund
Holm island:.8 =holm
Näs headland:.9 =nas
Mos marsh:.7 =myr
Myr marsh:.9 fen:.6 =myr
Kärr fen:.8 alder:.3 =myr
Ljung heath
Hed heath:.8 plain:.4 =hed
Äng meadow =ang
Åker field =aker
Berg hill:.8 =berg
Sten rock:.8 =sten
Häll rock:.9 hilltop:.3 =sten
Klipp cliff:.8
Ås ridge:.9 =as
Kull hilltop:.8
Dal valley:.6 =dal
Lid slope:.9
Back slope:.8 hill:.5
Hög hilltop:.7
Fjäll mountain @norr
Kall spring:.4 mountain:.3
Käll spring
Varm spring:.5
Svart fen:.3 forest:.3
Vit rock:.3 sandy:.3
Röd rock:.3 clearing:.4
Grön meadow:.5
Lill small:.6
Stor big:.6
Kyrk church =kyrk
Präst church:.6
Kungs character:.5 market:.4
Hammar rock:.6 works:.4
Ulv forest:.5 @norr
Björn forest:.5 mountain:.3
Ren mountain:.5 moor:.4 @norr
Älg forest:.5 marsh:.3
Hjort forest:.5
Örn cliff:.5 mountain:.4
Svan lake:.6
Tors +p any
Gunnars +p any
Karls +p any market:.3
Eriks +p any
Olofs +p any
Arvids +p any
Ingel +p any
Sig +p any
Ragn +p any
Folk +p any
Palm palm tropic:.5
Korall reef tropic:.5
Torr arid:.6 any:.3
Snö snow boreal:.4
]],
	gen = [[
-mot confluence:.9 =mot
-by any:.6 field:.4
-torp field:.6 edge:.3 +o
-sta any:.5 old:.3 * +n
-stad market:.6 any:.4
-vik bay coast:.6 =vik +o
-sund coast:.7 spit:.6 =sund
-näs headland spit:.7 =nas +o
-holm island =holm +o
-ö island:.9 =holm
-strand sandy coast:.6
-hamn bay:.9 coast:.7
-dal valley vale:.7 =dal
-berg hill =berg
-backa slope
-lid slope
-ås ridge =as
-kulla hilltop
-fjäll mountain @norr * =berg
-fors river:.9 gorge:.6 =fors
-å river =back
-bäck brook =back
-sjö lake mere:.6 =sjo
-träsk lake:.8 fen:.5 @norr * =sjo +n
-mossen marsh:.9 =myr
-myra fen:.9 marsh:.6 @norr =myr
-kärr fen =myr
-hed heath plain:.5 =hed
-mo heath:.8 sandy:.5 @norr =hed
-äng meadow =ang
-åker field =aker
-skog forest
-lund edge:.8 forest:.6
-ryd clearing @syd +o +n
-red clearing:.9 @syd +n
-hult edge:.8 forest:.5 @syd +o +n
-boda edge:.5 any:.4 @norr +o +n
-bro bridge
-köping market big:.6 * +n
-tuna old:.6 market:.4 * +n
-hammar rock:.8 slope:.4 =sten
-sten rock =sten
-klint cliff
-udde headland =nas
-fjäll mountain boreal:.5
-rev reef tropic:.4 *
-fjärd bay coast:.6 boreal:.3 =vik
]],
	affix = [[
Övre_%s slope:.8 hilltop:.5 +q
Nedre_%s foot:.8 vale:.5 +q
Stora_%s big +q
Lilla_%s small +q
Gamla_%s old:.8 +q
Nya_%s new +q
%s_kyrkby church:.9 *
Norra_%s north +q
Södra_%s south +q
Östra_%s east +q
Västra_%s west +q
%tfors falls
]],
	rivers = "Ljus|Svart|Klar|Kalix|Skell|Ume|Lögde|Öre|Ljung|Gide|Indal|Ångerman|Faxe|Dal|Göta|Nis|Ät|Visk|Lag|Em|Morrum|Helge|Lyck|Ronne|Säve|Gull|Norr|Sör|Vind|Pite",
	riverSuffix = "ån|älven",
	lakes = "Stor|Mäl|Ljus|Svart|Klar|Björk|Ek|Gran|Sil|Hjälm|Fryk|Vätt|Runn|Ors",
	lakeGens = "sjön",
	works = { works = "Järn|Hytt|Smedje|Stål", quarry = "Sten|Kalk|Marmor", mine = "Gruv|Malm|Koppar|Silver", mill = "Kvarn|Väv",
		farm = "Gård|Korn", brewery = "Bryggar|Malt", timber = "Såg|Timmer" },
	worksGens = "-by|-berg|-fors|-dal|-vik|-torp|-hammar|-backa",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Tvåvatten confluence:.9 ?confluence +g
Treälvarna confluence ?confluence:.9 +g
Sjöstranden lake ?lake:.8 +g
Eklunda oak ?oak:.6 +g
Björkhagen birch ?birch:.6 +g
Tallbacken pine ?pine:.6 +g
Granliden spruce fir:.8 ?spruce|fir:.6 +g
Långängen meadow ?meadow:.6 +g
Mossen marsh fen:.8 ?marsh|fen:.7 +g
Blåsåsen ridge ?ridge:.8 +g
Fjällfoten foot mountain:.5 ?foot:.8 +g
Dalsänden valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Kallkällan spring ?spring:.7 +g
Forsen falls ?falls:.8 +g
Sandudden spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Stenviken bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Klippan cliff ?cliff:.7 +g
Brofästet bridge ?bridge:.9 +g
Vadet ford ?ford:.9 ?brook:.6 +g
%shöjden hilltop:.6 +k
%shamn river:.5 coast:.4 +k
%sviken bay coast:.6 +k
Lång%l plain:.3 +k
%sbruk plain:.3 +k
%s_trädgårdsstad plain:.4 +k
%sön island +k
%s_köping market:.5 +k
%sskogen forest +k
Bortre_%s edge:.3 +k
%sstrand sandy coast:.6 +k
Fiskeläget coast:.5 !fish +i
Fiskhamnen coast:.5 !fish +i
Oljekällan !oil +i
Oljehamnen !oil +i
Tegelbruket !clay +i
Lerbäck !clay +i
Gruvbyn !coal +i
Kolbäck !coal +i
Stenbrottet rock:.4 !stone +i
Brottet rock:.4 !stone +i
Sågverket forest:.4 !timber +i
Sågen forest:.3 !timber +i
Ladugården field:.4 !farm +i
Storgården field:.4 !farm +i
Hyttan river:.3 !iron +i
Bruket !iron +i
]],
	charForms61 = { hilltop = "%shöjden", harbour = "%shamn", cove = "%sviken", street = "Lång%l", company = "%sbruk",
		garden = "%s_trädgårdsstad", island = "%sön", market = "%s_köping",
		forest = "%sskogen", secluded = "Bortre_%s", coastal = "%sstrand" },
}

---------------------------------------------------------------------------
-- Norwegian Bokmål (norway / europe nb)

L.nb = {
	maxCons = 4, dbl = "lnrst", dropE = false,
	shapes = "single:.08 qualifier:.08",
	climate = { subarctic = { boost = "-vik -fjord -fjell -nes" } },
	areas = { core = "midt", coast = "sor", edge = { "nord" } },
	compat = {},
	spec = [[
Eik oak
Bjørk birch
Lind lime
Ask ash
Or alder
Osp poplar
Hassel hazel
Alm elm
Bøk beech
Gran spruce
Furu pine
Vier willow
Rogn forest:.5
Ein heath:.5 forest:.3
Sjø lake:.8 =sjo
Bekk brook:.8 =bekk
Kvern river:.6 brook:.5
Foss river:.8 gorge:.5 =foss
Strand sandy:.7 coast:.6
Sand sandy:.8
Vik bay:.8 =vik
Hav coast:.8
Sund coast:.6 spit:.5 =sund
Holm island:.8 =holm
Nes headland:.9 =nes
Mose marsh:.7 =myr
Myr marsh:.9 fen:.6 =myr
Lyng heath
Hei heath:.8 =hei
Eng meadow =eng
Åker field =aker
Berg hill:.8 =berg
Stein rock:.8 =stein
Hell rock:.9 cliff:.4
Kleiv cliff:.7 pass:.4
Ås ridge:.9 =as
Haug hilltop =haug
Dal valley:.6 =dal
Li slope:.9 =li
Bakke slope:.8 hill:.5
Høg hilltop:.7
Fjell mountain =fjell
Kald spring:.4 mountain:.3
Kilde spring
Svart fen:.3 forest:.3
Kvit rock:.3 sandy:.3
Rød rock:.3 clearing:.4
Grønn meadow:.5
Lille small:.6
Stor big:.6
Kirke church =kirke
Prest church:.6
Konge character:.5 market:.4
Hammer rock:.6 works:.4
Jern works:.5 rock:.3
Ulv forest:.5 @nord
Bjørn forest:.5 mountain:.3
Rein mountain:.5 moor:.4 @nord
Elg forest:.5 marsh:.3
Hjort forest:.5
Ørn cliff:.5 mountain:.4
Svane lake:.6
Tors +p any
Gunnars +p any
Ola +p any
Eiriks +p any
Halvors +p any
Sig +p any
Ragn +p any
Arn +p any
Bjarn +p any
Palme palm tropic:.5
Korall reef tropic:.5
Tørr arid:.6 any:.3
Snø snow boreal:.4
]],
	gen = [[
-mot confluence:.9 =mot
-vik bay coast:.6 =vik +o
-fjord bay coast:.7 =vik
-sund coast:.7 spit:.6 =sund
-nes headland spit:.7 =nes +o
-holm island =holm +o
-øy island =holm
-strand sandy coast:.6
-havn bay:.9 coast:.7
-dal valley vale:.7 =dal
-berg hill =berg
-bakken slope
-li slope =li
-ås ridge =as
-haug hilltop =haug +o
-fjell mountain * =fjell
-foss river:.9 gorge:.6 =foss
-elv river
-bekk brook =bekk
-vatn lake mere:.6 =sjo
-tjern tarn pool:.7 * =sjo +n
-myr fen marsh:.6 =myr
-mo heath:.8 sandy:.5 =hei
-eng meadow =eng
-åker field =aker
-skog forest
-lund edge:.8 forest:.6
-rud clearing @sor +o +n
-bro bridge
-by any:.6 field:.4
-stad market:.6 any:.4
-heim any:.6
-vang meadow:.6 any:.4 +o +n
-seter mountain:.6 meadow:.6 * @nord +o +n
-stein rock =stein
-odden headland spit:.6 =nes
-sand sandy
-hamn bay:.8 @nord
-fjell mountain boreal:.4
-rev reef tropic:.4 *
]],
	affix = [[
Øvre_%s slope:.8 hilltop:.5 +q
Nedre_%s foot:.8 vale:.5 +q
Store_%s big +q
Lille_%s small +q
Gamle_%s old:.8 +q
Nye_%s new +q
Nordre_%s north +q
Søndre_%s south +q
Østre_%s east +q
Vestre_%s west +q
%tfoss falls
%tos mouth
]],
	rivers = "Glom|Lågen|Otta|Drams|Numedals|Bægna|Gaula|Orkla|Namsen|Vefsn|Rana|Målselv|Alta|Tana|Lakse|Sira|Otra|Mandals|Nid|Stjør|Verdals|Surna|Driva|Rauma|Lærdals|Vosso|Etne|Suldals|Bjerka|Beiar",
	riverSuffix = "elva|a",
	lakes = "Mjø|Rand|Tyri|Krøder|Stor|Ljus|Svart|Bjørk|Fem|Selbu|Snåsa|Tunn|Røss|Gjende",
	lakeGens = "vatnet|sjøen",
	works = { works = "Jern|Smie|Stål|Hytte", quarry = "Stein|Kalk|Skifer", mine = "Gruve|Malm|Kobber|Sølv", mill = "Mølle|Vev",
		farm = "Gård|Korn", brewery = "Bryggeri|Malt", timber = "Sag|Tømmer" },
	worksGens = "-by|-berg|-foss|-dal|-vik|-mo|-li|-haug",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
Tovann confluence:.9 ?confluence +g
Treelv confluence ?confluence:.9 +g
Sjøkanten lake ?lake:.8 +g
Eikelund oak ?oak:.6 +g
Bjørkeli birch ?birch:.6 +g
Furuly pine ?pine:.6 +g
Granli spruce fir:.8 ?spruce|fir:.6 +g
Langeng meadow ?meadow:.6 +g
Myra marsh fen:.8 ?marsh|fen:.7 +g
Vindåsen ridge ?ridge:.8 +g
Fjellfoten foot mountain:.5 ?foot:.8 +g
Dalsenden valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
Kaldkilden spring ?spring:.7 +g
Fossen falls ?falls:.8 +g
Sandodden spit sandy:.8 ?sandy:.6 ?spit|headland:.7 +g
Steinvika bay rocky:.8 ?rocky:.6 ?bay:.6 +g
Stupet cliff ?cliff:.7 +g
Brua bridge ?bridge:.9 +g
Vadet ford ?ford:.9 ?brook:.6 +g
%shøgda hilltop:.6 +k
%shamn river:.5 coast:.4 +k
%svika bay coast:.6 +k
Lang%l plain:.3 +k
%sverk plain:.3 +k
%s_hageby plain:.4 +k
%søya island +k
%s_kaupang market:.5 +k
%sskogen forest +k
Ytre_%s edge:.3 +k
%sstranda sandy coast:.6 +k
Fiskeværet coast:.5 !fish +i
Været coast:.5 !fish +i
Oljebyen !oil +i
Oljehamna !oil +i
Teglverket !clay +i
Leirvik !clay +i
Gruvebyen !coal +i
Kolbekken !coal +i
Steinbruddet rock:.4 !stone +i
Bruddet rock:.4 !stone +i
Sagbruket forest:.4 !timber +i
Saga forest:.3 !timber +i
Storgården field:.4 !farm +i
Låvebakken field:.4 !farm +i
Jernverket river:.3 !iron +i
Verket !iron +i
]],
	charForms61 = { hilltop = "%shøgda", harbour = "%shamn", cove = "%svika", street = "Lang%l", company = "%sverk",
		garden = "%s_hageby", island = "%søya", market = "%s_kaupang",
		forest = "%sskogen", secluded = "Ytre_%s", coastal = "%sstranda" },
}

---------------------------------------------------------------------------
-- Japanese (japan ja: kanji; japan en: romanised). Kanji compounds with their readings.

L.ja = {
	script = true,
	shapes = "qualifier:.06 whole:.02",
	spec = [[
白/shira any:.3 cliff:.3 rock:.3
黒/kuro forest:.3 any:.3
赤/aka rock:.4
青/ao lake:.4 hill:.3
高/taka hilltop:.7 mountain:.5
大/ō big:.6
小/ko +r small:.6
中/naka +r any:.5
上/kami slope:.6 hilltop:.4
下/shimo foot:.6
北/kita any:.3
南/minami any:.3
東/higashi any:.3
西/nishi any:.3
長/naga +r vale:.4 ridge:.3
広/hiro vale:.6 plain:.5
深/fuka gorge:.6 forest:.3
古/furu old:.7
本/moto old:.5 any:.3
石/ishi rock:.9
岩/iwa rock cliff:.5
砂/suna sandy
松/matsu pine
杉/sugi fir:.7 spruce:.6 cypress:.5
桜/sakura any:.4 edge:.3 *
梅/ume apple:.5 any:.3
竹/take forest:.5
柳/yanagi willow
栗/kuri forest:.5 beech:.3
楢/nara oak
樫/kashi oak:.8
榎/enoki elm:.7
柏/kashiwa oak:.7
藤/fuji edge:.4
稲/ina field:.8
芦/ashi marsh:.8 fen:.5
蓮/hasu pool:.7
鶴/tsuru marsh:.6 lake:.3 *
亀/kame pool:.4 coast:.3
鹿/shika forest:.5 mountain:.3
熊/kuma mountain:.5 forest:.4
馬/uma meadow:.5 field:.3
鳥/tori forest:.3 marsh:.3
金/kana works:.5 mountain:.3
水/mizu spring:.6 river:.3 =izumi
清/kiyo spring:.7 brook:.5
泉/izumi spring =izumi
滝/taki river:.5 gorge:.6
湯/yu spring:.9 *
霧/kiri mountain:.4 valley:.4 *
雪/yuki mountain:.6 *
風/kaze ridge:.4 hilltop:.3
日/hi slope:.4 any:.3
星/hoshi hilltop:.4 *
朝/asa slope:.3 any:.3
春/haru any:.3 meadow:.3
秋/aki forest:.3 any:.3
宮/miya church character:.4
寺/tera church:.9
城/shiro hilltop:.5 old:.7
船/funa bay:.6 coast:.5 river:.3
塩/shio coast:.5 marsh:.4
海/umi coast:.6
山/yama hill:.6 =yama
川/kawa river:.6 =kawa
椰子/yashi palm tropic:.5
珊瑚/sango reef tropic:.5
砂/suna dune arid:.5
雪/yuki snow boreal:.4
]],
	gen = [[
川合/kawai/gawai confluence:.9 =kawa
山/yama/yama hill =yama
川/kawa/gawa river =kawa
沢/sawa/zawa combe brook:.6 =kawa
谷/tani/dani valley =tani
原/hara/bara plain field:.5 =hara
野/no/no field:.8 plain:.6 heath:.4 =hara
田/ta/da field marsh:.3 =ta
森/mori/mori forest =mori
林/hayashi/bayashi forest:.8 edge:.5 =mori
島/shima/jima island =shima
崎/saki/zaki headland =saki
浜/hama/hama sandy coast:.8 =hama
浦/ura/ura bay coast:.7 =hama
津/tsu/zu bay:.7 mouth:.6 coast:.5
江/e/e bay:.6 mouth:.5
橋/hashi/bashi bridge
瀬/se/ze river:.8 brook:.5 =kawa
池/ike/ike pool =ike
沼/numa/numa marsh:.8 pool:.6 =ike
湖/ko/ko lake =ike
岡/oka/oka hilltop:.9 hill:.6 =yama
峰/mine/mine hilltop:.8 mountain:.7 =yama
岳/take/dake mountain * =yama
峠/tōge/tōge pass * =yama
坂/saka/zaka slope
台/dai/dai hilltop:.7 plain:.4
平/taira/daira plain:.7 hilltop:.4
口/kuchi/guchi mouth:.8 pass:.4
根/ne/ne foot:.7 ridge:.3
戸/to/do any:.5
井/i/i spring:.8 =izumi
泉/izumi/izumi spring =izumi
里/sato/zato any:.6 field:.4
内/uchi/uchi valley:.4 any:.4
窪/kubo/kubo combe:.6 *
磯/iso/iso rocky coast:.6 *
潟/kata/gata fen:.7 pool:.5 coast:.4 *
宮/miya/miya church:.8
寺/tera/dera church:.8
礁/shō/shō reef tropic:.4
]],
	affix = [[
新%s/Shin%l new +q
上%s/Kami%l slope:.8 +q
下%s/Shimo%l foot:.8 +q
北%s/Kita%l north +q
南%s/Minami%l south +q
東%s/Higashi%l east +q
西%s/Nishi%l west +q
落合/Ochiai confluence:.9 *
]],
	riverGens = "川/kawa/gawa",
	works = { works = "鉄/tetsu|工/kō", quarry = "石/ishi", mine = "金/kana|銅/dō", mill = "粉/ko", farm = "稲/ina",
		brewery = "酒/saka", timber = "木/ki" },
	worksGens = "町/machi/machi|野/no/no|田/ta/da|原/hara/bara|浜/hama/hama",
	-- (2026-10-15, NEXT_PHASE_BRIEF 61, the rules "s61" only: evocative names +g, the character kinds' forms +k,
	-- the industry cue forms +i; the notes at L.en)
	affix61 = [[
川合/Kawai confluence:.9 ?confluence +g
三川/Mikawa confluence ?confluence:.9 +g
湖畔/Kohan lake ?lake:.8 +g
樫原/Kashihara oak ?oak:.6 +g
松原/Matsubara pine ?pine:.6 +g
柳原/Yanagihara willow ?willow:.6 +g
長原/Nagahara meadow ?meadow:.6 +g
尾根/One ridge ?ridge:.8 +g
山下/Yamashita foot mountain:.5 ?foot:.8 +g
谷頭/Tanigashira valley combe:.8 ?valley|combe:.6 ?upper|spring|combe:.6 +g
清水/Shimizu spring ?spring:.7 +g
滝本/Takimoto falls ?falls:.8 +g
白浜/Shirahama sandy coast:.6 ?sandy:.6 ?coast:.6 +g
岩浦/Iwaura bay rocky:.8 ?rocky:.6 ?bay:.6 +g
立崖/Tategake cliff ?cliff:.7 +g
橋本/Hashimoto bridge ?bridge:.9 +g
渡瀬/Watase ford ?ford:.9 ?brook:.6 +g
%s台/%sdai hilltop:.6 +k
%s港/%skō river:.5 coast:.4 +k
%s浦/%sura bay coast:.6 +k
%s宿/%sjuku plain:.3 +k
%s園/%sen plain:.4 +k
%s島/%sjima island +k
本%s/Hon%l market:.5 +k
%s森/%smori forest +k
奥%s/Oku%l edge:.3 +k
%s浜/%shama sandy coast:.6 +k
網代/Ajiro coast:.5 !fish +i
漁浦/Gyoura coast:.5 !fish +i
油田/Yuden !oil +i
油井/Yui !oil +i
瓦町/Kawaramachi !clay +i
窯元/Kamamoto !clay +i
炭山/Sumiyama !coal +i
炭坑/Tankō !coal +i
石切/Ishikiri rock:.4 !stone +i
石山/Ishiyama rock:.4 !stone +i
木場/Kiba forest:.4 !timber +i
木挽/Kobiki forest:.3 !timber +i
牧野/Makino field:.4 !farm +i
稲田/Inada field:.4 !farm +i
鉄山/Tetsuyama river:.3 !iron +i
鍛冶屋/Kajiya !iron +i
]],
	charForms61 = { hilltop = "%s台/%sdai", harbour = "%s港/%skō", cove = "%s浦/%sura", street = "%s宿/%sjuku",
		company = "新%s/Shin%l", garden = "%s園/%sen", island = "%s島/%sjima", market = "本%s/Hon%l",
		forest = "%s森/%smori", secluded = "奥%s/Oku%l", coastal = "%s浜/%shama" },
}

---------------------------------------------------------------------------
-- Blocklists: substrings (lower case, ASCII folded) that reject a name in every language; whole words per language;
-- brand words everywhere.

L.BLOCK_SUB = { "fuck", "shit", "cunt", "nigg", "fagg", "slut", "whore", "rape", "wank", "twat", "penis", "vagin", "porn",
	"nazi", "hitler", "anal", "anus", "dick", "cock", "piss", "bitch", "bastard", "boob", "tits", "crap", "jizz", "kkk",
	"isis", "sex", "fick", "arsch", "scheis", "hure", "fotze", "wichs", "pimmel", "titt", "neger", "nutte", "kack",
	"merde", "pute", "putain", "salop", "chier", "nique", "connard", "cazz", "merd", "troia", "puttan", "stronz",
	"minchia", "vaffa", "mierd", "cabron", "joder", "pendej", "verga", "chocho", "porra", "caralh", "buceta", "piroca",
	"viado", "neuk", "kanker", "tering", "klote", "flikker", "fitta", "fitte", "knull", "dritt", "chinko", "manko", "unko",
	"kuso", "polla", "coño", "slet", "schwuchtel", "spast", "rapist" }
L.BLOCK_WORD = { "con", "cul", "bite", "culo", "fica", "figa", "puta", "foda", "cu", "kut", "lul", "pik", "hoer", "hora",
	"hore", "pule", "faen", "fan", "kuk", "skit", "baka", "shine", "homo", "arse", "ass", "tit", "fag", "gay", "kill",
	"dead", "death", "hell", "satan", "devil", "ikea", "nike", "lego", "tesco", "aldi", "lidl", "esso", "shell", "sony",
	"audi", "opel", "fiat", "adidas", "pepsi", "coca", "cola", "google", "amazon", "nokia", "rolex", "gucci", "prada",
	"bosch", "siemens", "volvo", "saab", "skoda", "lada", "tesla", "seat", "mars", "ford", "apple", "montblanc", "bmw",
	"disney", "marlboro", "camel", "toyota", "honda", "nissan", "mazda", "subaru", "suzuki", "yamaha", "canon", "sharp" }
L.BLOCK_CJK = { "死", "殺", "糞", "鬼", "呪", "墓" }

return L
