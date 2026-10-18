# Organic Towns naming: review answers (2026-10-14)

Answers to the questions in `NAMING_REVIEW.md`, from a read of the brief, `runs_1729_naming_lines.txt`, the
`ot_placename.lua` header and constants, and the en / usa blocks of `ot_placename_lang.lua`. Read-only review: no code
changed. The fixes listed in the brief as "already being fixed" (NEXT_PHASE_BRIEF §50) are treated as done. Note:
NEXT_PHASE_BRIEF.md has no §50 heading yet; it ends at §49.

## The main suggestion: pick each town's name shape first, for the whole map

Most of what feels forced comes from one design choice. Each town scores stem, generic and affix together, so a frame
wins whenever its fit beats `AFFIX_COST`. On a map with a strong survey, frames fit almost everywhere. Tuning those
costs won't fix it. Split `assign` into two passes:

1. **Choose shapes for the whole map.** Work out how many towns get each shape from the language, climate and era (the
   quotas in Q1). Hand the scarce shapes (frame, whole name, qualifier) to the towns with the strongest claim, strongest
   first. Every other town gets a plain shape.
2. **Fill in the words**, much as `assign` does now, but only within the town's assigned shape.

Most of the answers below plug into this.

## 1. Mix of name shapes

Rough targets from real gazetteers (England's place names, the US's GNIS list, and the German, French and Nordic
equivalents):

| Shape | en | usa | de | fr | it/es/pt | sv/nb | nl |
|---|---|---|---|---|---|---|---|
| Plain compound (Ashford, Swainthorpe) | 70% | 30% | 80% | 50% | 45% | 80% | 75% |
| Single element (Hythe, Combe, Stoke) | 5% | – | 3% | 5% | 10% | 8% | 5% |
| Name + separate generic (Cedar Rapids, Hayes City) | 5% | 35% | – | – | – | – | – |
| Personal name + generic (-ville, -ton, -burg) | inside "plain" | 15% | – | – | – | – | – |
| Joined qualifier (Oberdorf, Norrby, Neustadt) | – | – | 10% | – | – | 8% | 10% |
| Separate qualifier (Upper / Great / Little / North) | 6% | 5% | – | – | – | – | – |
| Frame (-on-X, -sur-X, an der X, di Sopra) | 3% | – | 3% | 15% | 10% | – | 3% |
| Saint form | 2% | 2% | – | 15% | 20% | 2% | – |
| Article form (Le / La X, Los X) | – | – | – | 10% | 10% | – | 5% |
| Whole landmark name (Three Rivers, Middle Fork) | 2% | 8% | 1% | 2% | 2% | – | 2% |
| Railroad or civic (Junction, Station, Center) | 2% | 5% | – | – | – | – | – |

For a 16-town English map, that works out to about 11 plain names, 1 single element, 1 or 2 qualifiers, and at most
1 frame, 1 saint name and 1 whole name. Run 1729 has 11 of 16 framed. German and Nordic qualifiers are joined into one
word, so they count as plain. French is the one language where frames are normal.

## 2. Spending the cues

Yes to a cue budget, but treat two kinds of cue differently:

- **Named features** (Big Sandy, Dun Fell, Blackmere): a strict budget.
  - Each named feature appears in at most 1 town name per ~6 towns along it, and 2 at most.
  - Claim strength = cue weight × how unique the town's claim is (the only mouth, the nearest town to the peak) × town
    size.
  - Process towns in claim order; the strongest claim spends the cue.
- **Feature types** (a confluence, a bay): no budget beyond the generic word budget (`ot_namewords`). A neighbor can
  still say "two rivers meet here" without the river's name: Twyford, or "Forks" in another town's own name.
- **The cheapest way to spend a named feature** is the river's stem with an ordinary generic: Arunford, Dartington,
  Exmouth. That is how real names use rivers. Frames ("-on-Arun", "Port Big Sandy") should be the rare case.
- **Leftover cue claims** can go to stop names or districts (a "Big Sandy" station) instead of a town.

## 3. A settlement history

Yes, and it doesn't need much. Give each town a layer (old, middle or late):

- **Rivers and peaks keep the oldest layer.** In England that is Celtic river names under Saxon or Norse towns. The
  rivers already work this way, and it's realistic.
- **Towns on the map at start: layer by size and site.** Crossings, mouths and market towns are oldest:
  - en: Saxon -ham, -ton and -ley in the core, Norse -by and -thorpe in one area, a few Norman touches (Magna, Bishops,
    St X).
  - usa: early forms (-ton, -ford, Mount X), then -ville, -burg and the personal-name + City / Springs forms.
- **Created towns use the game year:**
  - Works before 1920: Ironbridge-style names and -Works.
  - Railway era: Junction, Station, New X.
  - Districts after 1945: Heights, Park, Estates, Acres.

The best side effect: "Junction" and "Station" move to towns that come later, and stop landing on natural confluences,
which is part of why "Big Sandy Junction" feels forced. Avoid a made-up "Native-derived" layer for US maps: that would
be inventing words for real languages, so keep to English, Spanish and French forms.

## 4. When a qualifier is natural

- **Upper/Lower, Great/Little, North/South, Magna/Parva are twin markers.** Use one only when another town (or a
  district) with the same base is within ~3-6 km. Better still, make twins on purpose: two close towns on one site
  share a base and are told apart by height or river course (Upper / Lower) or by size (Great / Little). One stem then
  covers two towns. This also drops the compass word based on the map side ("East Hornness"). A compass word should be
  relative to the twin or to a named feature, not to the map's edge.
- **-on-X, -upon-X, -under-X go on common bases, not rare ones.** Real examples are Stoke-on-Trent,
  Stratford-upon-Avon, Newton-le-Willows. The base is ordinary, so it needs the frame to tell it apart.
  "Fellhaven-under-Dun" fails because Fellhaven is already distinctive. Rule: a frame only on a base from a "common"
  list (Newton, Sutton, Stoke, Stratford, Norton, Aston...), or when that base is already used on the map. At most 1
  per river.
- **-on-Sea:** a sandy-coast resort from the later layer, once per map.
- **Saint names:** a church or character town, once per map in English (more often in French and the Romance lists,
  per Q1).
- **No bare whole names:** "Narrows" alone never.

## 5. Dialect areas

Use fewer, larger areas with borders that follow the land:

- **2 or 3 areas per map, not 2-6 anchors** (today `REGION_KM` = 14). Draw the borders along the survey's main range or
  main river (the Danelaw border followed rivers and roads).
- **Celtic** on the remote, high or western edge, **Norse** on the coast or in the east, **Saxon** in the core.
- **Inside an area:** about 80% of names in its own dialect, 20% borrowed. Allow real hybrids only near a border
  (Grimston: a Norse personal name + Saxon -ton).
- **Fix word order:** Celtic elements come first (Inver-, Aber-, Llan-, Pen-, Bal-) and never follow a Germanic stem.
  That kills "Invercoed", which is also two Celtic languages in one name.
- **The area sets the feature words too:** Fell, dale, -water and tarn in the Norse area; hill, down and -mere in the
  Saxon one.
- **US areas follow who settled them:** New England English, Mid-Atlantic Dutch/German (-burg, -kill), French (St,
  Bayou), Spanish on dry maps.

## 6. Climate as shape, not just words

Each climate gets its own shape quotas and its own layers, not only vetoes:

- **Tropical:**
  - Mostly separate-word shapes: Port X, Xtown (Georgetown-style), X Bay, X Point, X Cay, Mount Pleasant-type names.
    Plantation-era Estate / Pen / Hall inland.
  - Saint names in the Romance lists.
  - Veto the joined Saxon and Norse forms (-thorpe, -by, -ham) entirely.
  - On an island map, the island's name becomes the shared cue that rivers are elsewhere.
- **Dry:**
  - Water is scarce, so water names get *more* weight where water exists (Springs, Wells, Tank). Rock color stems
    (Red, Painted) and Mesa / Butte.
  - US list: a Spanish layer (San X, Agua X, Los / Las X, Arroyo X).
  - Oceania (English list): Downs, Well, Crossing, Creek, Mount X.
- **Subarctic:**
  - English list: post-and-portage names (Fort X with a personal name, X Landing, X Portage, X Rapids, X Narrows), or
    Highland names (Glen, Strath, Kyle of X).
  - sv/nb lists: vik, fjord and fell forms more often.

## 7. Variety tests

Run them in Lua and in the lab, over many seeds × site presets × climates. Hard gates first, then softer metrics.

**Hard gates:**

- frame share and whole-name share within the Q1 target plus 5 points;
- tokens per name: en averages ≤ 1.4, usa ≤ 1.8, nothing with 4 or more words;
- each named feature in at most 2 town names;
- each stem at most once per 12 towns, twin pairs excepted;
- each name in one dialect, or one of the allowed hybrids;
- at most 2 feature ideas per name (catches "Mytmere-in-the-Vale" and "South Spruce Valley");
- a compass word only on the right side of its twin.

**Soft metrics:**

- **Quiet names:** at least 35% of names with no terrain cue.
- **"Sounds real" score:** a letter n-gram model per language, trained on real gazetteers kept in `tools/` (scoring
  data only, never shipped as names). Its average shouldn't drop between versions. List the bottom 5% for review. The
  same data can also check that no generated name is a real place, which enforces the Landscape-mode rule.
- **Golden runs:** seed `a` on 4-5 presets, with diffs of the names reviewed on every change.

## 8. The name lab

- **Map mode:** generate a whole map's names at once and rate the set ("sounds like one region", 1-5) as well as single
  names.
- **Import game logs:** read the game's `NAME` lines into the lab, so you can rerun the real sites from a game session.
- **Shape A/B:** the same site in two shapes ("Arunmouth" vs "Lower Arunmouth"), pick one. Ratings then feed the shape
  weights directly.
- **Rate by shape:** store the shape with every rating; the Export JSON adds ratings up per shape.
- **Shape mix view:** sliders for the target mix and a live chart of generated vs target vs real gazetteer.
- **Names on a map:** draw the names at their positions, so a cue spent three times (Big Sandy) is visible at a glance.
- **Panels:** the Q7 numbers, plus a per-name "why" breakdown.

## Suggested order

1. Shapes chosen per map, with the quotas (Q1, Q4).
2. The named-feature budget (Q2).
3. Larger dialect areas and the word-order rule (Q5).
4. The Q7 gates as tests.
5. The layers (Q3).
6. Climate shape tables (Q6).
7. The lab changes (Q8).

Steps 1-2 alone would turn run 1729's EU set from 11 framed names of 16 into about 3.
