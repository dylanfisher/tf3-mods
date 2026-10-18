# Organic Towns naming: review brief (2026-10-14)

For a reviewer (human or agent) to read the current naming results and suggest how to get **more variation and less
forced-sounding names**, without losing what works. Read-only review: suggest designs, don't change code.

## What the player wants (the user's words)

- "i love the big geography cues from the overall map" (keep these).
- "our names should all be heavily influenced from the region (tropical, subarctic, etc.) otherwise the naming falls apart"
- "in landscape name mode i'd prefer not to use real existing city names, and instead all generated names from region and
  geography cues and similar"
- "we have too many repeat words in city names. lake, woods, etc. it sounds unrealistic and silly"
- "make sure names don't sound silly - like lake in the hills on a tropical map where its all islands"
- "the more specific to the terrain the better"
- On created towns: "industrial satellites seem like they always say 'works' … make sure our satellites have lots of
  variety too"; "i see multiple sand suffixes, which we want to avoid too many duplicates"
- The ask for this review: "suggest how to build out for more variation and less forced feeling names".

## How names are made today (short)

The mod is `mods/square_organic_towns` (Transport Fever 3). Code is in `content/organic_towns/`.

- **`ot_mapshape.lua`: the map survey.** It runs once per map, on a grid of 128 m cells, in about 0.5 s.
  - It reads rivers as a network: forks, mouths, bends, falls, and the upper / lower course.
  - It finds the sea and lakes, the biggest lake, peaks, the main range and the main valley.
  - It finds bays, capes, narrows and isthmuses.
  - `townCues` gives each town cue tags with weights, the river it sits on, and its compass side on the map.
- **`ot_placename.lua`: town names.** For each town:
  - `read` takes extra samples around the town: water arms on a 450 m ring, the ring's water share, relief and altitude.
  - `siteTags` turns those reads into fine tags with specificity: confluence above river, tarn above lake, gorge above valley.
  - `assign` scores pairs of a **stem** (specific part) and a **generic** from the language inventory, plus an
    optional **affix** frame ("Upper %s", "%s-under-%m", "%s-on-%k") or a **whole-name** form ("Middle Fork",
    "%t Junction"). The score adds:
    - the fit of each part;
    - a bonus when stem and generic name two different features;
    - regional dialect anchors (Norse / Saxon areas);
    - use penalties for parts already on the map;
    - jitter.

  Rivers and lakes get names, which the towns along them share.
- **`ot_placename_lang.lua`: the per-language inventories.** Stems and generics carry tags, weights and dialect groups;
  affixes and whole names carry templates. 11 languages: en, usa, de, fr, it, es, pt, nl, sv, nb, ja.
- **`ot_namewords.lua`: the map-wide word budget.** A generic word appears at most about once per 8 towns and never
  twice within 5 km. Tags are weighted by how rare they are on the map.
- **`ot_climate.lua`: climate vetoes and climate words.** Tropical maps get no oak or pine and do get palm, coral and
  key; dry maps get no marsh; subarctic maps get no palm. There is also a finished-name word check.
- **`ot_offname.lua`: created towns.** Works (industrial satellites) and districts are named from the parent, a
  company-town pattern, a site word or a generic, with a map-wide suffix count.
- **`ot_stopname.lua`: stop names.** They are composed separately (not in scope here, except that they share the
  vocabulary).

Settings: "Town and stop names" = Landscape names (the default; it now runs the generator) / Game names. Lists without a
generator language (asia, china, korea, poland, russia) keep the game's names.

Playground: `plans/square_organic_towns/names/index.html` (the name lab). It is a JS port of the generator with site
presets, editable inventories, ratings and an Export JSON; `check_port.js` checks that it matches the Lua.

## The two runs

Both runs are on the same map: seed `a`, temperate, 1900. The survey found 4 rivers, 11 forks, 11 mouths, 3 falls,
7 lakes, sea, 8 peaks, 1 range, a main valley, 11 bays, 10 capes, 2 narrows and 2 isthmuses. Session
`2026-10-14_1729_add-money-100m`: load 3 is the European list, load 4 the USA list. Every naming line from both runs is
in `runs_1729_naming_lines.txt` beside this file. Tour screenshots per town are on the comparison pages:
- `compare/2026-10-14_a/` (run `mod-1729`);
- `compare/2026-10-14_a-usa/` (run `mod-1729-usa`).

The same town id has the same site in both runs, so the two columns compare one site named twice.

| Town id | Site (feature, top cues) | European list (en) | Parts | USA list | Parts |
|---|---|---|---|---|---|
| 60255 | bay, peak, main valley, lower course, south | Fellhaven-under-Dun | Fell+haven + `%s-under-%m` | Mount Spruce | whole `Mount %m` |
| 60256 | river bend, confluence, peak, central | Twywath-under-Dun | Twy+wath + `%s-under-%m` | Middle Fork | whole |
| 60257 | mere in a vale, confluence, mouth, west | Mytmere-in-the-Vale | Myt+mere + `%s-in-the-Vale` | Stone Forks | whole `%t Forks` |
| 60258 | river mouth, bend, lower course, west | Lower Arunmouth | Arun+mouth + `Lower %s` | Port Big Sandy | whole `Port %t` |
| 60259 | lake / mere, ash, forest edge, east | Little Merwood | Mer+wood + `Little %s` | Lake Prairie | Prairie+Lake |
| 60260 | field, plain, main valley | Swainthorpe | Swain+thorpe | Buffaloburg | Buffalo+burg |
| 60261 | bay, lake (Blackmere / Long Lake), oak | Oakhaven-on-Blackmere | Oak+haven + `%s-on-%k` | Big Sandy Valley | whole `%t Valley` |
| 60262 | church, market, big, character town | Ashkirk St Brannoc | Ash+kirk + `%s St %p` | North Antelope City | Antelope+City + `North %s` |
| 60263 | spit, headland, rocky coast, big lake, narrows, east | East Hornness | Horn+ness + `East %s` | Narrows | whole |
| 60264 | confluence, north, main valley | North Mytdale | Myt+dale + `North %s` | Big Sandy Junction | whole `%t Junction` |
| 60265 | vale, ash, south-east | Strathfield | Strath+field | South Spruce Valley | Spruce+Valley + `South %s` |
| 60266 | oak forest, east | Edgrove | Ed+grove | Hayeswood | Hayes+wood |
| 60267 | mere, vale, forest edge, east | South Marshaw | Mar+shaw + `South %s` | East Crystaldale | Crystal+dale + `East %s` |
| 60268 | ash forest, edge, north-east | Ulfhurst | Ulf+hurst | Winslow Woods | Winslow+Woods |
| 60269 | oak forest, vale | Acbottom | Ac+bottom | Pleasant Oaks | Pleasant+Oaks |
| 60270 | hill foot, clearing, character town, deep forest, confluence | Invercoed-under-Edge | coed+Inver + `%s-under-Edge` | Three Rivers | whole |

The survey named a mountain ("Dun Fell" / "Spruce Mountain"), rivers (Arun, Dart, Dove / Big Sandy, Stone Creek,
Deer Creek) and lakes (Blackmere, Redwater, Ellersmere, Rydalmere, Brantmere / Spirit, Twin, Long, Swan, Loon Lake).

**Created towns (Works = industrial satellite, district = residential satellite):**

| Run | Name | Kind | How it was named |
|---|---|---|---|
| EU | Ashworthby | Works | company-town pattern (`*by`) |
| EU | East Hornness Engine Works | Works | parent + industry word |
| EU | Mytsands, Norsands, Strathsands | district | **old generator path** (`pattern=-`), all `-sands`; Mytsands sits by a lake |
| EU | Acbottom Holme, South Marshaw Ford | district | parent + generic |
| USA | Ironport | Works | site cue (`*port`) |
| USA | Forge Landing | Works | old generator path (`pattern=-`) |
| USA | Stone Beach | district | old generator path |
| USA | Big Bottoms | district | parent + generic |
| USA | Pleasant Oaks Acres | district | parent + generic |

## What works (keep)

1. **Big geography cues from the map survey.** The user loves these. Middle Fork, Three Rivers, Stone Forks and Big
   Sandy Junction sit on real confluences. Lower Arunmouth sits at the real mouth of the river Arun. Fellhaven- and
   Twywath-under-Dun sit below the map's highest peak, named Dun Fell. Oakhaven-on-Blackmere sits on a lake the survey
   named. East Hornness is on the east side of the map, on a spit.
2. **Shared named features** make the map feel like one place: one river name across its towns, one mountain, named
   lakes.
3. **Whole-name forms** (USA: Middle Fork, Three Rivers, Narrows, Port X) read the most natural. They break the
   "stem + generic" template.
4. **Some plain compounds sound real:** Swainthorpe, Ulfhurst, Strathfield, Hayeswood, Winslow Woods, Pleasant Oaks.
5. **Climate and survey checks work offline.** Earlier runs on a tropical island map named towns "Lake in the Hills"
   and "Canyon Lake" from the game's real list; the generator now refuses lake words without a lake and temperate trees
   in the tropics. The `misfit=` lists in the NAMES words lines show the vetoes.

## What feels forced or repetitive

1. **Too many names are framed.**
   - EU: 11 of 16 town names carry an affix (Lower, Little, North, South, East, St, -under-, -in-the-, -on-).
   - USA: 11 of 16 are whole forms or framed (Mount, North, South, East, Port, Junction, Valley, Forks, Narrows).

   Only 5 per run are plain: Swainthorpe, Strathfield, Edgrove, Ulfhurst, Acbottom; Lake Prairie, Buffaloburg,
   Hayeswood, Winslow Woods, Pleasant Oaks.

   Real gazetteers are mostly plain one-word or two-part names. Qualifiers like "Upper", "North" or "-under-X" are
   uncommon and usually mark a town that has a plain twin. Here the frame often names a fact the site has (the town is
   in the south) rather than something people would name a town after.
2. **The same cue is spent many times.**
   - "-under-Dun" twice, plus "-under-Edge";
   - Big Sandy in 3 whole names (Port Big Sandy, Big Sandy Valley, Big Sandy Junction), plus Big Bottoms on it;
   - compass words on 3 EU towns (plus "Lower") and 3 USA towns.

   A strong cue becomes noise when every town near it uses it.
3. **Roots repeat**, because the budget counts generic words, not stems or affix patterns:
   - EU: "Myt" 3 times (Mytmere, North Mytdale, Mytsands), "haven" twice;
   - USA: Spruce twice, Valley twice, Fork / Forks twice.
4. **Mixed dialects and wrong order inside one name:**
   - "Invercoed" joins Gaelic Inver- and Welsh coed, in reversed order;
   - "Acbottom" (Ac- for oak, plus bottom) reads clumsily;
   - "Edgrove";
   - "Twywath" (Twy- for two, plus Norse wath for ford) is plausible but odd next to "-under-Dun".
5. **Generics stack on the same idea:** "Mytmere-in-the-Vale" (mere + vale), "South Spruce Valley" (compass + tree +
   valley), "North Antelope City". There are often three tokens where real names use one or two.
6. **Bare whole names:** "Narrows" alone reads unfinished.
7. **Created towns still bypass the budget in two paths** (`pattern=-` above): three -sands districts on one map, and
   Stone Beach and Forge Landing. Being fixed now (NEXT_PHASE_BRIEF §50).
8. **Few quiet names.** Real regions are mostly unremarkable names (personal-name stems, -ton, -ham, -ville, -burg)
   with a few landmark names among them. Here almost every town is "about" its terrain, so the terrain names lose their
   weight.

Already being fixed (§50, not yet in game):
- one naming path for all created towns, with a map-wide suffix count;
- a budget on stems and affix patterns;
- one dialect per name;
- at most one whole name per river, plus one other town along it;
- a qualifier for bare whole names;
- the character quota bug.

The reviewer can treat those as done and look past them.

## Questions for the reviewer

1. **Mix of name shapes.** What should the mix of shapes per region look like? Plain one-word, two-part compound,
   compound + qualifier, whole landmark name, personal name + generic, and so on. Can you give a target distribution
   per region (English, US, German, French, Nordic …)? Real gazetteers (England's, the US's) can be the reference.
2. **Spending the cues.** How should a map spend its big geography cues? One proposal is a cue budget: each named
   feature (a river, a peak, a lake, a bay) is spent at most once or twice per map, by the town with the strongest
   claim. Its neighbours get quiet names or a different cue.
3. **A settlement history.** Would a naming history make names feel less forced? For example, older towns get old
   forms (Norse -by, Saxon -ham), towns founded later get later forms (-ville, "New X", railway names like Junction or
   Station), and created towns get era-fitting names.
4. **Qualifiers.** When is a qualifier like Upper, North or -under-X natural? Rules such as "only when a plain twin
   with the same stem exists nearby" or "only for the second town on the same river".
5. **Dialect areas.** How should dialect areas shape a map? Today there are 2-6 anchors (Norse / Saxon / Celtic in
   English). Should a map have fewer, larger areas, with clearer borders?
6. **Climate.** Beyond vetoes, how can climate change the shape of names, not just swap words?
   - tropical: colonial-era forms such as "Port …", saint names and plantation names;
   - dry: Spanish-derived forms on US dry maps, wells and springs;
   - subarctic: fell, -vik and -fjord forms.
7. **Variety tests.** Which tests or metrics would catch "forced" names offline? Ideas:
   - share of framed names;
   - tokens per name;
   - repeated roots per map;
   - a share of quiet names;
   - an n-gram "sounds real" score against real gazetteers.
8. **The name lab.** Any changes to the lab (`names/index.html`) that would let the user rate shapes, not just single
   names?

## Constraints for any proposal

- Names are composed from the region's language and the map: no real place names from the game's lists in Landscape
  mode.
- The climate and the map survey must agree with every word (no lake words without a lake, no oaks on tropical
  islands).
- Deterministic per map seed; unique on the map; names only. Names are given once, at first sight of a town, and never
  rename a town in an existing save.
- Every user-visible setting text in 13 languages. Town names themselves are in the name list's language.
- The game's Lua runs on the main thread, so heavy reads go into budgeted slices. The survey takes about 0.5 s;
  assigning names to 16 towns takes about 10 ms.
- The name lab's JS port must stay in step with the Lua.

## Files to read

- This brief and `runs_1729_naming_lines.txt` (every NAME / NAMES / DISTRICT / WORKS naming line from both runs).
- `plans/square_organic_towns/NEXT_PHASE_BRIEF.md` §42 (generated names), §45 (map shape), §47 (created-town names),
  §49 (climate-led), §50 (fixes in flight).
- `plans/square_organic_towns/PLAN.md` 6.3 "Generated names", "Names from the map's shape", "Plausible, climate-led
  names".
- `plans/square_organic_towns/HISTORY.md` "seed `a` on five maps": the real-list runs before the generator, with the
  silly tropical names.
- Code: `mods/square_organic_towns/content/organic_towns/`:
  - `ot_placename.lua` (header lines 1-80 describe the design);
  - `ot_placename_lang.lua` (the inventories: look at the en and usa blocks);
  - `ot_namewords.lua`;
  - `ot_mapshape.lua`;
  - `ot_climate.lua`;
  - `ot_offname.lua`.

## Update: the §50 fixes landed (offline, not yet in game)

The fixes listed under "Already being fixed" are now in the code: one naming path for created towns, a budget on roots
and affix patterns with a 7-nearest-towns rule, one dialect per name, at most two towns per named feature (one whole
form), and a qualifier on bare whole names. Offline samples for the same 16 sites (seed 1; NEXT_PHASE_BRIEF §50):

- **EU, temperate**
  - Towns: Lower Brynhaven, Mytbridge-under-Skid, Abercuckmere-on-Rydalwater, West Acmouth, Ashmere, Wheatbottom,
    Woodport, Ashminster St Brannoc, East Oakness, North Twyley, South Bradwood, Acworth, Mershaw-in-the-Vale, Osholt,
    Hartden, Abercoed-under-Edge
  - Districts: Abercuckmere Lakeside, Acworth Strand, North Twyley Hill, South Bradwood Dale, Mytbridge Ings, Ashminster Cross
  - Works: East Oakness Tool Works, Mytbridge Steelworks, Acworth Harbour
- **US, temperate**
  - Towns: Mount Signal, Middle Fork, Port Pine, West Turkey Bend, Lake Laurel, Prairie Canyon, Crystal Cove, North
    Antelope Woods, East Oak Point, Turkey Valley, South Cedar Valley, Hickoryfield, Mirrordale, Ellis Grove, Long Oaks,
    Three Rivers
  - Districts: Port Pine Lakeside, Hickoryfield Beach, Turkey Valley Heights, Cedar Hollow, Middle Fork Crossing,
    Antelope Corners
  - Works: East Oak Point Car Shops, Furnaceton, Millport
- **US, tropical:** the temperate set with Port Rock, East Swan Point, South Palm Valley, Magnoliafield and Longwood
  instead, and Works Hollisterburg and Magnoliafield Fish Camp.

The structural points under "What feels forced" still hold:
- framed names still dominate: 10 of 16 EU and about 11 of 16 US;
- three-word stacks remain (North Antelope Woods, South Cedar Valley, Abercuckmere-on-Rydalwater);
- quiet names are still rare.

The questions above stand.
