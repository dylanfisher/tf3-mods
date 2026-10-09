# square_roundabouts: in-game tests

Setup: `make link`, enable the mod, start a free game (year 1940 or later) or load a save. Watch
stdout.txt (`~/Library/Application Support/Steam/userdata/<id>/3493540/local/crash_dump/stdout.txt`)
for errors mentioning `square_roundabouts`.

Where it is: road construction menu (`street_constructions`), next to the base "Roundabout"
(order 3010; "Magic Roundabout" at 3011). It has its own menu icon (Phase 2a); the hover preview image is still the base
roundabout's (placeholder).

## 0. Loads, menu entry, params
1. The entry "Better Roundabouts" appears in the street constructions menu from 1940 (base one:
   1960).
   - If missing: the `.con.lua` was not discovered, or `ug_require` of the geometry module from
     the con file failed (look for `square_roundabouts_geometry` in stdout).
2. **Phase 2a: own menu icon.** The thumbnail shows an oval ring with a green, tree-covered island,
   beige sidewalks and three arms (T layout). It must be clearly different from the vanilla
   Roundabout's icon (plain grey ring, four diagonal arms) and sharp, with a transparent
   background (no black or white box around it). Hovering shows the base roundabout's preview
   image (expected for now).
   - If the thumbnail is blank or missing: the relative `icon = "square_roundabouts.tga"` did not
     resolve to `square_roundabouts@2x.tga` next to the `.con.lua`; note the stdout error.
3. **Phase 2a: params.** The panel shows: Shape, Ring lanes, Radius, Arms, Arm road,
   Direction, Centre island (Phase 3b: no Arm length any more, arms are always 30 m). No param
   is ever greyed out (all checkEnabledScript removed).
   - Shape slider: Round, Oval 1.25 : 1, Oval 1.50 : 1, Oval 1.75 : 1, Oval 2.00 : 1. Moving it
     changes the preview immediately between a circle and ovals.
   - Radius slider: 8, 10, 12, 15, 20 ... 60 m. The preview follows at once.
   - Arms = None: Arm road stays active but has no effect (nothing to build).
   - Regression check: with our construction selected, hover the vanilla Roundabout and the
     interchanges in the menu. No "Required key not found, key='type'".
4. **Phase 2a: Centre island default None.** Fresh game (or after a restart), open the menu: Centre
   island shows "None" and the preview has no island.

## 1. Default placement (Round, 2 lanes, 20 m, 4 arms, no island)
1. Hover over open flat ground: a preview of the ring and four arms (no island) follows the
   cursor. Rotate with the construction rotation keys (constructOpt1/2, the same keys as for any
   construction).
   - The ring looks round (no kinks at the arm junctions or at the 90-degree nodes).
2. Place it. Expected: no error, cost roughly that of the roads (construction cost is 0 like the
   base roundabout; note what is actually charged).
3. **Spike 1 (dissolves into streets)**: click a ring segment: it opens as an ordinary street, not
   a construction. Upgrade one ring segment with the street upgrade tool, bulldoze one arm on its
   own, drag a new road from an arm end. All must work like on hand-built roads.
4. **Spike 2 (tags merge)**: every arm joins the ring at a real junction (junction markings, no
   overlapping duplicate node). Build a road from two arm ends to a town and a bus line through
   the roundabout: the bus enters, drives round and exits.
5. Direction: cars on the ring drive anticlockwise (seen from above).
6. **Spike 6 (priority)**: watch cars entering under traffic. Do ring vehicles keep priority, or
   do entering cars force their way in / is there a deadlock? Note what you see; this decides
   whether phase 4 (a precedence script) is needed.
7. With nothing but streets placed (island None), check that no empty construction can be
   clicked where the island would be.

## 2. Island
Choose Centre island = Grass for 1 and 2.
1. The grass island fills the middle with a gap of about 1 m to the ring's inner kerb; no grass
   on the carriageway.
2. Click the island: what is it? Expected: a construction entity ("Better Roundabouts") holding only the
   island. Bulldozing it must leave the roads intact.
3. Island = None (the default) was covered in 1.7.
4. Grass and trees at radius 60: a tree in the centre, a ring of trees and a ring of bushes, all
   inside the island. Fountain at 20 m: base fountain in the middle on paving. Paved: paving with
   a soft edge.
5. Build a town next to it and let it grow: no town building ever spawns on the island (the
   cylinder collider). If buildings do spawn there, the collider is ignored or the wrong shape.
6. Placing on a slope: the island follows the ground (no terrain alignment); the roads slope as
   usual. Note any z-fighting or floating grass.

## 3. Types and sizes
1. Mini: Radius 10 m (any radius below 15 m), 1 lane, island Grass and trees: tight ring, paved
   island instead of trees (same for Fountain). At 15 m the trees appear. Trucks and buses can
   drive round (turning at a tiny radius). Note the smallest size that works.
2. Shape Oval 2.00 : 1, 5 arms: an ellipse stretched along the construction's x axis; arms leave
   square to the ring (Phase 3b: along the ring's normal, so on the flanks they no longer point
   exactly away from the centre; splitter arms stay radial); no kinks. Also try Oval 2.00 : 1 at 8 m with 4 lanes.
3. Ring lanes 1 / 2 / 4: highway_new_small / town_new_one_way_small / town_new_one_way_medium, as
   the base roundabout.
4. Arms 3 (T): arms east, north, west. 3 (Y): north, south-west, south-east. 5 and 6 evenly spaced.
   None: just the ring.
5. Every Arm road (town and country, small to large) builds. Phase 3b: wide arms on a small ring
   make the ring grow (e.g. 1 lane, 8 m, Town large: 20 m with 3 (T) arms); with small arms on a
   2-lane ring from 15 m it never grows. Note any combination that still fails.
6. Clockwise: cars drive clockwise. Check in a left-hand-traffic game too, if the game has that
   setting, that one-way lanes and markings look right.

## 4. Placing over and next to existing roads
1. **Spike 3**: place it so an existing road runs through the ring centre, then so an arm end
   lands on an existing road end. Expected one of: auto-split and connect, or a collision error.
   Note which, and whether the arm ends snap (they are free nodes, not snap nodes).

## 5. Save safety
1. **Add to a save**: enable the mod on an existing save (no warning dialog: severityAdd None),
   load, place two roundabouts (one with island, one without), save, reload: both unchanged.
2. **Remove from a save**: disable the mod, load that save. Expected: the warning dialog
   (severityRemove Warning). After loading, both roundabouts' roads are still there and drivable.
   Note what happened to the island: kept as an orphaned construction, removed, or an error.
   If the save fails to load, raise severityRemove to Critical and document it.
3. Re-enable the mod and load: nothing changes or duplicates.

## 6. Spikes not exercised by this build
- **Spike 4** (mod `.street_template.lua` discovery, 3-lane no-sidewalk ring): out of scope; the
  user decided on base templates only.
- **Spike 5** (`trafficLightYes`/`trafficLightNo` from tealdef vs `trafficLightNodePreference`
  from the wiki): now exercised by the Phase 3 "Traffic lights" param, see section 7.4.

## 7. Phase 3 types (main entry)
Params panel (0.3) now also shows: Splitter islands, Through the centre, Tram tracks, Traffic
lights. All default to off/Nothing, so the default build must look exactly as before. No param is
ever greyed out. Check the hover regression of 0.3 again (hover base Roundabout / interchanges).

### 7.1 Splitter islands
1. Default (4 arms, 20 m, 2 lanes), Splitter On, Centre island Grass. Expected: each arm splits
   26 m beyond the ring into two one-way roads (town one-way, extra small) that join the ring
   about 13 m to either side of the arm; a small grass triangle (about 6 m wide at the ring)
   between them; the two-way arm continues outwards. The radius stays 20 m.
2. Drive: a bus line through the roundabout. Inbound traffic uses the right-hand leg (seen from
   the arrival direction), joins the ring anticlockwise and leaves by the next arm's left-hand
   leg. No vehicle drives the wrong way on a leg (one-way arrows point into the ring on the entry
   leg, out on the exit leg).
3. **Spike: 2 one-way + 1 two-way at one node.** At the split node, junction markings and lanes
   look sane, cars turn from the two-way arm onto the entry leg and from the exit leg onto it.
   Note any "too sharp angle" / collision error (legs fork at +-40 degrees).
4. Clockwise: everything mirrored (entry on the left of an inbound driver), no wrong-way traffic.
5. Ring growth: Arms 6, Radius 20 m, Splitter On: the ring is visibly bigger (35 m). Radius 8 m
   with 4 arms grows to 20 m (2 lanes) / 25 m (1 lane). Toggling Splitter Off restores the chosen
   radius. Oval 2.00 : 1 with 3 (Y) arms also builds (it grows until the legs fit).
6. Centre island None: no triangles. Fountain/Paved: paved triangles. Triangles have no collider:
   note whether town buildings or trees ever appear on them (not expected, they are tiny).
7. Arms run 30 m past the split node (56 m from the ring's outer edge).
8. The legs are ordinary one-way streets afterwards: bulldoze one leg, upgrade one, reconnect.

### 7.2 Through the centre
1. 4 arms, 40 m, Through = Road, island Grass and trees: a straight road east-west across the
   centre continuing the two arms; two grass half islands with a tree each; cars can go straight
   across. **Spike: priority**: who yields where the through road meets the ring (4-way node)?
   Note deadlocks.
2. 3 (Y) and 5 arms: the through road runs north-south and an extra arm appears due south. Arms
   None: two arms east and west appear with the through road.
3. Tram line (Phase 3b): tracks only along the straight line: the two axis arms (town tram
   roads), 16 m tram road stubs at the ring and a tram-only track (tram, new) between them. The
   ring itself has no tracks (tram turns onto the tight one-way ring made the game refuse the
   build: "transition not valid ... StreetGeometry::Crossing"). Build a tram line from the east
   arm to the west arm; the tram crosses the ring straight through the centre. See 9.1.
4. Small ring (8 m, 2 lanes, 4 arms) with Road through: the ring grows to 10 m; with 6 arms and a large
   arm road it grows further. No road overlaps the ring.
5. Town growth next to it: no buildings on either half island (two box colliders).
6. With splitters on: the two axis arms have no legs (they join the ring directly), the other
   arms do.

### 7.3 Tram tracks
Phase 4: no longer experimental. The engine probe (`probe_results.md`, 10,644 combos) shows Tram
tracks On fails no more often than Off (35% vs 34%, the same patterns), so tram on the ring is not
what made builds fail. The menu value is now plain "On".
1. Tram tracks On, 2 lanes, Town small arms: the ring is the base "one-way small, tram
   electrified" road, arms "small, tram electrified", catenary everywhere. A tram line from one
   arm to any other works.
2. 4 lanes: "one-way medium, tram electrified".
3. **Spike: tramTrackType on non-tram templates.** 1 lane (highway small ring) and Country arms
   have no tram variant: they get `tramTrackType = "ELECTRIC"`. Check whether those roads show
   tracks and catenary and whether a tram can drive them. If not, note it: the fallback is to
   map the 1-lane tram ring to the 2-lane tram template and country arms to town tram arms.
4. With Splitter On: legs are "one-way small, tram electrified" (tram on the outer lane).

### 7.4 Traffic lights (experimental, spike 5)
Use a year from 1950 (lights exist from then). 4 arms, Traffic lights = Entries (experimental).
Arms are numbered by the layout order: 4 arms = 1 east, 2 north, 3 west, 4 south (T: east, north,
west; Y: north, south-west, south-east; 5: north first, then anticlockwise; 6: east first).
- Arms 1 and 3 (odd) ask through `trafficLightYes` (tealdef field).
- Arms 2 and 4 (even) ask through `trafficLightNodePreference = {{node, "YES"}}` (wiki field).
Note which ring entry junctions get traffic lights:
- odd only -> `trafficLightYes` works; even only -> `trafficLightNodePreference` works; both ->
  both work (keep the tealdef one); neither -> neither works (remove the param, suggest the
  game's traffic-light tool in the description).
- With Splitter On the light should be where the entry leg joins the ring.
- Also check the load log for an "unknown key"/field error naming either field.

## 8. Magic Roundabout (separate menu entry)
1. "Magic Roundabout" appears next to Better Roundabouts with its own icon (five small rings around
   a green island with trees). Params: Size, Arm road, Direction, Centre island only.
2. Default (Size Medium): five 1-lane mini roundabouts (radius 12 m) on a circle, joined by
   two-way town roads forming the central ring, one 30 m arm each; about 150 m across plus the
   arms. No error on flat ground. Size and large arm roads: see 9.3.
3. Drive: cars from one arm reach every other arm, going round either way (the inner lane of the
   central ring runs against the minis' direction, as in Swindon). Watch for deadlocks at the
   minis.
4. Clockwise: the minis turn clockwise.
5. Centre island Grass and trees: a grass island with trees inside the central ring, dented around
   the minis; each mini gets a paved island (Size Compact to Medium) or grass with trees (Size
   Large and Very large, 15 / 20 m minis). Town buildings stay off all of them.

## 9. Phase 3b retests (2026-10-07 fixes)
Background: PLAN.md "Phase 3b notes". The offline junction model says a junction must leave every
edge at least 4.5 m of its length and no kerb corner may lie more than 6 m behind a road's node.
Both thresholds come from the first in-game results; these checks confirm or move them.

### 9.1 Tram line through the centre (ring without tracks)
1. 4 arms, 40 m, 2 lanes, Through = Tram line, Tram tracks Off: does it place? Expected: yes.
   The ring is plain one-way road; east and west arms are "small, tram electrified" town roads
   (for Town small arms) or the arm road with tracks; tram stubs and the tram-only line cross.
2. Drive a tram line east arm -> west arm: the tram goes straight across the 4-way ring nodes.
3. Same with 3 (Y) arms (axis north-south) and with Arms None.
4. Through = Road + Tram tracks On is covered by 9.2 (tram on the ring).

### 9.2 Tram tracks On (tram on the ring): does it place at all?
Answered by the engine probe (Phase 4): yes, as often as Tram tracks Off (`probe_results.md`), so
the param is no longer experimental. The checks below stay as an in-game confirmation.
1. **Through Nothing + Tram tracks On, 2 lanes, Round, Radius 30 m (and 40 m), 4 arms, Town small
   arms: does it place?** Expected after the first test: probably "Construction not possible".
   Note the stdout lines (`transition not valid ... Crossing`?).
2. If it fails: try 4 lanes (one-way medium tram ring) and 1 lane (highway small +
   tramTrackType) at 40 m. If every variant fails, the param gets removed (or limited to the
   arms) in the next phase.
3. If it places: run 7.3 and Through = Road + Tram tracks On (4-way ring nodes with tram).

### 9.3 Size and large arm roads
1. Magic Roundabout, Arm road Town large: Size Compact, Small, Medium all build the Large layout
   (15 m minis, about 171 m across plus the 30 m arms); Large and Very large build as chosen. Expected: places
   without "Construction not possible". (Phase 4b: the engine only takes Very large; see 10.4.)
2. Magic, Country large at Size Medium: stays Medium (12 m minis, now with the in-between ring
   node moved away from the arm). Places? (Phase 4b: grows to Large; see 10.4.) This is the tightest Magic layout we ship: 5 m left on
   the mini's edge next to the arm (it failed with 1.6 m before).
3. Magic, every Size with Town small: five visibly different sizes, Compact (8 m minis, 40 m out)
   to Very large (20 m minis, 76 m out).
4. (Superseded by 10.1-10.2: the engine rejected every medium/large splitter of this phase.)
   Better Roundabouts, Splitter islands On, Town large arms, default 4 arms 20 m: the ring grows to
   30 m; the legs fork at about +-72 degrees and meet the ring further apart. Places? Country large:
   ring 25 m, fork about +-64 degrees. Town medium / small: unchanged (20 m ring, 40 degree fork).
5. (Superseded by 10.2.) Splitter islands with Town large on 3 (T), 5 and 6 arms, 1 and 4 lanes: places? Expected ring
   sizes: T 30 m (1 lane) / 25 m (4 lanes), 5 arms 40 / 35 m, 6 arms 50 / 40 m.
6. Mini ring (8 m, 1 lane, 4 arms) with Town medium arms: grows to 12 m (junction room). Town small:
   stays 8 m. 3 (T), 1 lane, 8 m, Town large: 20 m.
7. The widest combinations grow past the slider's 60 m (up to 100 m): e.g. Town large, splitter
   islands, 5 arms, 1 lane, Road through: 70 m. Places? Looks sensible?
8. Splitter islands with medium/large arms on a small (8 m) or long oval (2:1) ring: if no
   radius fits, the legs fork wider and spread further apart (up to +-80 degrees). Check one,
   e.g. Town medium, 3 (Y), 4 lanes, Oval 2.00 : 1, 8 m: places, legs look sane?

## 10. Phase 4b: engine-tuned geometry (PLAN.md "Phase 4b notes")
The probe asked the engine (makeProposalData) about 33,000 layouts; the shipped geometry now
follows its answers. These checks confirm that the in-game builder agrees with the probe.

### 10.1 Splitter islands with medium arms
1. Default (Round, 2 lanes, 20 m, 4 arms), Splitter On, Town medium: the ring stays 20 m; the
   arms split 20 m beyond the ring into one-way **small** roads (not extra small) that fork at
   about +-65 degrees. Places without "Construction not possible"? Country medium: same ring, fork
   about +-50 degrees.
2. Same with 1 lane: the ring grows to 40 m. With 6 arms (2 or 4 lanes): 40 m.
3. Drive a bus line through one arm: entry and exit legs work as in 7.1.2.

### 10.2 Splitter islands with large arms
1. Default 4 arms, 20 m, Splitter On, Town large: the ring grows to 40 m; the split is 32 m out,
   legs are one-way **medium** roads forking at about +-50 degrees. Places? Country large: same.
2. 6 arms, 2 lanes, Town large, 20 m: the ring grows to 60 m (a provisional size: the engine
   placed no 6-arm large splitter at 40 m on 1-2 lanes; the next probe run finds the real one).
   Places? Note if it does not.
3. 4 lanes, 6 arms, Town large: 40 m. Places?

### 10.3 Ring sizes the engine asked for
1. 1 lane, Round, 40 m, 6 arms (or 3 (Y)), Town small, no splitter: the ring builds at 45 m (the
   engine rejects 40 m for every arm road). Places?
2. 2 lanes, Round, 60 m, 5 arms: 65 m. 2 lanes, 20 m, Through the centre = Tram line: 30 m.
3. Default build (Round, 2 lanes, 20 m, 4 arms, Town small, nothing else): unchanged, 20 m.

### 10.4 Magic Roundabout
1. Town large: every Size builds Very large (20 m minis). Country large: Compact to Large build
   Large, Very large as chosen. Places?
2. Town / country medium and small: as before (every size as chosen; medium from Small).

### 10.5 Tram line on a small ring
1. 1 lane, 25 m (and 4 lanes, 25 m), 4 arms, Through = Tram line: the tram road runs all the way
   across (no tram-only middle; the engine rejected middles under 21 m). Places?
2. 2 lanes, 30 m: stubs of 16 m and a tram-only middle in between. Places?

## Phase 5 walkthrough (revision 3, sections 11-15)
Run the probe first (PROBE.md "Phase 5e runs": `p5_all`, then `p5_search`, done; "Phase 5f
runs": `p5f_all`, `p5f_search`, done; then "Phase 5g runs": `p5g_verify`): it tells which
combinations of the new entries the engine refuses, so the in-game pass below can focus on looks,
traffic and the questions the probe cannot answer. Then, in order:
- a **1930s save** (or a new game starting 1930): 11.1, 11.2;
- a **1965 save** (a new game starting 1965 is fine): 13.2 (lights from 1950), 14.3 (steel bridges,
  then play past 1970), 11.3;
- a **2020 flat map** (the probe map): 12, 13, 14 (concrete bridges), 11.5.
Write each answer under its item (OK / what you saw); 7.4 gets its answer from 13.2.

## 11. Phase 5a: unverified research results (PHASE5.md "Phase 5a notes")
The open questions the Phase 5 entries (and a possible old-era path) depend on.
1. **Unlock year unchanged.** Better Roundabouts, Magic Roundabout, Channelized Junction and
   Roundabout Interchange all appear from 1940, not before (a 1939 save: absent; 1940: present).
2. **Pre-1940 one-way template** (decides whether an old-era path for every entry is worth it,
   PHASE5.md "Phase 5a notes", spike 2). Base `constructions/entrance_old_one_way.street_template`
   (yearFrom 0, one 5 m car lane, 30 km/h; the modular street station's entrance before 1920) is
   the only one-way template before 1940; base never builds it as a *freed* edge. Test it with the
   probe's dev construction (enable **DEV Roundabouts Probe** with "Run the probe" **Off**; use a
   throwaway save, the probe is never uploaded): in a 1930 save, street construction menu, last entry
   **"DEV Probe: pre-1940 one-way (NOT FOR UPLOAD)"**, params Layout (Straight / Ring / Ring + old
   arms, default the last) and One-way template (entrance_old_one_way / entrance_new_one_way).
   1. Each layout places (or the exact error text).
   2. The placed edges are ordinary streets: one-way arrows in the street layer, the ring runs
      counterclockwise, the arms (town old small) are two-way; bulldoze one ring edge, upgrade an
      arm with the street tool.
   3. Traffic: a bus or truck line through the "Ring + old arms" roundabout drives the ring one way
      only and enters/leaves from every arm.
   4. Look: 1 lane, sidewalks both sides, old-town style; acceptable as a pre-1940 roundabout ring?
   5. The same with entrance_new_one_way (the post-1920 variant) in the same save.
3. **`params.year` in a street construction's updateFn** (the interchange picks its bridge from it).
   The probe's `p5_interchange` passes year 1969 and 2020 explicitly; its report section "Bridge
   type by year" says whether the two cost differently (the year reached the updateFn). In game
   (14.3): is it the current year, and does a placed interchange keep its bridges when the updateFn
   re-runs (save load, hovering the construction) after 1970?
4. **Bridge years in constructions.** Base interchanges unlock 1960 but build
   `concrete.bridge` (yearFrom 1970). Does `steel.bridge` (1940) work as a construction edgeType, and
   does the interchange place with concrete bridges before 1970 (only when the year does not reach
   the updateFn: then 14.3 shows concrete in 1965)?
5. **Elevated plain edges.** The base diamond builds its cross road's approaches as normal edges
   8 m above the construction origin (no `edgeType`, no `alignTerrain`). Place the base Diamond
   Interchange on flat ground: earth embankments under them, or floating? (Decides whether 5d
   needs `alignTerrain = true` or terrain alignment faces on its ramps.)
6. **Traffic lights (7.4) still open:** answered by 13.2 (and 13.3); write the result under 7.4.

## 12. Phase 5b: Channelized Junction (PHASE5.md "Phase 5b notes")
New menu entry under street constructions, own icon (T junction with two curved slip lanes and
green triangles); the hover preview is still the roundabout's (expected). Probe: `p5_channel`
(every layout x road pair x slip lanes x splitter x traffic side); in game, start from the combos
it refused (if any) and the items below.
1. **Menu.** Present from 1940 (absent in 1939), name "Channelized Junction", params in this order:
   Layout, Main road, Side road, Slip lanes, Side-road splitter islands, Arm length, Traffic side,
   Islands. Tooltips readable.
2. **Default** (T, town medium main, town small side, near-side slip lanes, no splitter, 30 m, RHT,
   no islands): places on flat ground; two one-way slip lanes (one-way arrows in the street layer):
   east arm -> side road and side road -> west arm; vehicles use them for right turns.
3. **Every road pair, tightest cases** (the engine model was fitted on roundabouts only): T and X with
   main/side town large + town large, country large + town small, town small + country large, near-side
   and all turns. Note any "Construction not possible" with the combination.
4. **Splitter islands On** (with slip lanes Near-side and None): side road splits into one-way legs
   reaching the main road at two nodes; X: both side roads share those two nodes (4-way). Check
   medium and large side roads (legs one-way small / medium) and country medium (longer split).
   Size: the junction is much larger with slip lanes (slip node 65-94 m up the side road).
5. **All turns off the main road**: T: both slip lanes run from the main road into the side road
   (the far one crosses the oncoming lanes at its slip node); X: four.
6. **Slip lanes per traffic side.** Right-hand (right-hand traffic save): near-side slip lanes are the
   right turns (east arm -> side road, side road -> west arm), splitter entry legs on the right of an
   inbound driver. Left-hand (a left-hand traffic save, Traffic side Left-hand): everything mirrored
   east-west; near-side slip lanes are the left turns (west arm -> side road, side road -> east arm),
   entry legs on the left. In both, vehicles drive the slip lanes the right way (one-way arrows) and
   leave from the inbound lanes. Also: Traffic side not matching the save's traffic side still places
   (vehicles then use the slip lanes as the far turns).
7. **Islands Grass / Paved**: a triangle in each slip lane corner and one between splitter legs, no
   gaps or overlaps with the kerbs; no town buildings appear on corner islands (box colliders); the
   island stays when the slip lane is bulldozed (same as the roundabout islands).
8. **Arm length** 30 / 60 m: the roads run that far beyond the slip nodes.
9. **Look**: slip lanes leave and join at 40 deg (gore length acceptable?), the town one-way xsmall
   slip template on country roads (sidewalks) looks acceptable.
10. **Editing after placement**: slip lanes, legs and arms are ordinary streets (bulldoze one slip lane,
   upgrade the main road, connect the arm ends).

## 13. Phase 5c: hamburger / through road (PHASE5.md "Phase 5c notes")
Probe: `p5_hamburger` (Road and Road + traffic lights x 5 other through roads x every layout and
lane count, sliders 8 / 20 m, town small and town large arms): any refusal there is a missing
engine floor (the ring would need to grow more), to be fixed by a tuning pass from
`p5_hamburger_radius`.
1. **Menu.** Through the centre has four values: Nothing, Road, Tram line, Road + traffic lights
   (hover tooltips per value). A new ComboBox "Through road" follows it: Same as arms, then the six
   arm roads. Saves/presets with Road or Tram line still show the same value.
2. **Road + traffic lights: answers 7.4** (year 1950 or later; 4 arms, 40 m, town small): same roads
   and island as "Road". The east crossing asks via `trafficLightYes`, the west one via
   `trafficLightNodePreference` (same split as 7.4). Record: lights at the east crossing only ->
   `trafficLightYes` works; west only -> `trafficLightNodePreference`; both / none. Check stdout.txt
   for a field error. Before 1950 (1940s save): no lights expected, still places.
3. **Lights + Traffic lights = Entries** together: places; lights at the entries and the crossings,
   no error.
4. **Larger through roads** (no engine data): 4 arms town small, 2 lanes, slider 8 m with Through
   road Town large (ring 25 m) and Country medium (15 m); slider 20 m with Town large (25 m). 2:1
   oval, 1 lane, T, Town large through (35 m). Note any "Construction not possible"; the road through
   should cross straight, the two half islands sit beside it.
5. **Narrower through road** than the arms (town large arms, Through road Town small): places, the
   axis arms stay town large and the through road narrows at the ring nodes.
6. **Tram tracks On** with Through road Town medium: the through road is "medium, tram electrified";
   a tram crosses straight.
7. **Priority**: who yields at the crossing node of a 6-lane through road and a 1-lane ring (7.2.1)?
   Note deadlocks.

## 14. Phase 5d: Roundabout Interchange (PHASE5.md "Phase 5d notes")
New menu entry under street constructions, own icon (ring over a highway with four slip roads);
the hover preview is still the roundabout's (expected). Probe: `p5_interchange` (every layout x
highway x level x lanes at the 15 m slider, both bridge types, wide cross roads, 120 m slip roads,
left-hand, islands); `p5_interchange_search` asks whether smaller clearances would place.
1. **Menu.** Present from 1940 (absent in 1939), name "Roundabout Interchange", params in this order:
   Layout, Highway, Level, Ring lanes, Radius, Cross road, Slip road length, Arm length, Traffic side,
   Centre island. Tooltips readable.
2. **Default** (Two-bridge ring, medium highway, ring over highway, 2 lanes, 20 m -> builds 35 m,
   town medium cross road, 140 m slip roads, 30 m arms, RHT, no island) on flat ground: places; the
   ring is 8 m up, on bridges over the highway on both sides, the rest of the ring and the arms on
   embankments (or floating?); four slip roads leave/join the carriageways beside the node (one-way
   arrows right), level for ~30 m, then climb. Vehicles: highway -> ring -> cross road and back.
3. **Bridge type flip** (11.3, 11.4): in a 1965 save the bridges are steel (`steel.bridge`); in 2020
   concrete. Place one in 1965, play (or skip) past 1970, then save + reload and hover it: do the
   existing bridges stay steel? Re-place it after 1970: concrete.
4. **Ramp heights**: Ring over highway: every slip road is level with its carriageway for the first
   ~25-30 m (the gore, beside the highway), then climbs the full 8 m to the ring node; it arrives
   level (no kink at the ring or at the carriageway). Highway over ring: the slip roads climb from
   the ring at 0 m to the highway at 8 m the same way. No slip road clips through the highway bridge
   or a ring bridge; bridge ends sit at full height (8 m).
5. **Dumbbell** and **Peanut**, each level: the link bridge (two-way) / the two waist bridges
   (one-way, opposite directions, pinched) over the highway; Highway over ring: the highway on one
   bridge per carriageway over the ring roads, the rest on embankment at 8 m.
6. **Peanut direction**: right-hand traffic: the loop runs as one circuit, each lobe counterclockwise,
   the west waist bridge southbound and the east one northbound (follow a car round: it never
   meets oncoming traffic on the waist). Left-hand: mirrored (lobes clockwise, west waist northbound).
   Slip roads join the lobes in the circulating direction.
7. **Every highway size and ring lanes**, tightest cases: large highway + 4-lane ring + town large
   cross road, small highway + 1-lane ring + country large. Note "Construction not possible"
   with the combination.
8. **Slip road length 120 m**: gradient acceptable (avg <= 9 %, peak 13.7 %); trucks get up.
9. **Traffic side Left-hand**: everything mirrored; carriageways on the left, rings clockwise, the
   slip roads still leave before and join after the junction.
10. **Islands**: Centre island Grass and trees / Fountain: two-bridge halves either side of the highway, one
   island per dumbbell ring / peanut lobe (cut flat at the waist); no buildings spawn there; with Ring
   over highway the islands stay at ground level inside a ring 8 m up (looks acceptable?).
11. **Terrain** (11.5): on uneven ground, the 8 m roads on plain edges and the bridge ends (embankments,
   floating roads, terrain cuts?).
12. **Editing after placement**: slip roads, rings, bridges and arms are ordinary streets; connect
    the arm ends (8 m up for ring over) and the highway ends.

## 15. Phase 5f / 5g: engine tuning (PHASE5.md "Phase 5f notes", "Phase 5g notes")
Probe first: `p5g_verify` (PROBE.md "Phase 5g runs"). Known gaps until it has run
(`tests/square_roundabouts/verdicts.lua` V.GAPS): `interchange` (4-lane two-bridge rings at the
Phase 5g radii no sweep placed yet). `channel` is empty since Phase 5g (no combo ships ch.FALLBACK).
1. **Channelized Junction, 50 deg slip lanes** (accepted by the probe; e.g. T, main town large +
   side town small; X, main country medium + side country medium): places; the slip lanes leave and
   join at 50 deg and bow slightly towards the corner (the slip lane itself turns a little the other
   way). Look acceptable?
2. **Channelized Junction, steep slip lanes** (Phase 5g, from p5f_search; one-way xsmall slip lanes
   everywhere): **65 deg** e.g. T, main town medium + side town medium (no splitter), or X, main
   town medium + side town small; **80 deg** e.g. T, side town large with splitter islands, or X,
   main town large + side town large. Places? Vehicles use them (an 80 deg slip lane is almost a
   right-angle turn: do vehicles slow down a lot)? Look acceptable (65 / 80 deg slip lanes bow
   towards the corner; small triangle islands)?
3. **Roundabout Interchange, two-bridge ring with 4 lanes** (Phase 5g: slip nodes within 45 deg of
   the highway): small / medium / large highway at the 15 m slider build 30 / 45 / 50 m rings
   (Phase 5f: 35 / 45 / 55 m; revision 2 era: 25 / 35 / 40 m, all refused); the slip roads join the
   ring at 45 deg or more. Places, both levels, both bridge types? Traffic flows?
4. **2:1 oval, 4 lanes, large arms, splitter islands, Y or 5 arms** (Better Roundabouts): the split
   nodes sit square to the ring's edge on the long flank (no longer radial). Places at 40 and 60 m?
5. **Hamburger** (engine-accepted now): e.g. 4 lanes, Y, town small arms, Through road Town medium,
   slider 8 m: builds 20 m (was 25 m, refused); 1 lane, Y, town large arms, Through road Town medium:
   35 m (was 30 m, refused). Places.

## Phase 6a lane probe (PHASE6.md; DEV ONLY mod `square_roundabouts_lanes_probe`, never upload)
Goal: one round that answers PHASE6.md Q1-Q3. The probe only logs, except in part B.

Setup:
1. `make link` (links `mods/square_roundabouts_lanes_probe` too). Watch the log in a terminal:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered "SQRB-LANES"`
2. New free game (year 1990 or later, so every template and traffic lights exist), mods enabled:
   **Better Roundabouts** and **DEV Roundabouts Lane Probe**, probe setting "Write experiment" =
   **Off**. Flat open area away from towns. After a few seconds of unpaused play stdout must show
   `[SQRB-LANES] INFO msg=DEV_ONLY_lane_probe_subscribed` and `..._gui_loaded`.

A. Read-only (write Off). Unpause between placements; wait about 3 s after each (look for a `SCAN` line).
1. Better Roundabouts, defaults (Round, 2 lanes, 20 m, 4 arms, Town small).
2. Better Roundabouts, 2 lanes, 4 arms, **Arm road Town medium** (2-lane arms).
3. Better Roundabouts, **4 lanes**, 4 arms, Town medium.
4. Better Roundabouts, **1 lane**, 3 (T) arms, Town small.
5. Better Roundabouts, 2 lanes, **Splitter islands On**, Town small.
6. Better Roundabouts, 2 lanes, **Through the centre: Road**.
7. Magic Roundabout, defaults.
8. Channelized Junction, defaults (T, near-side slips).
9. Roundabout Interchange, defaults (two-bridge ring, ring over highway).
10. The vanilla **Roundabout** (base menu), defaults: baseline for the engine's own connections.
11. Crossing Tool: open the vanilla Crossing Tool on one arm node of roundabout 2 (2-lane ring,
    medium arm). Note what it shows: which ring lane has arrows into the arm, which arm lanes go to
    which ring lane (a screenshot helps). Then change one arrow (remove the inner ring lane's exit)
    and apply. Write down the node position (hover) or take a screenshot; the probe logs the tool's
    build as `BUILD ... ncfgAdd=1` plus `NCFG`/`NCFG_CONN` lines.
12. Build any short road somewhere else (triggers one more `BUILD`).

B. Write experiment. Save, quit to the menu, set the probe's "Write experiment" = **On**, load the save.
1. Place Better Roundabouts 2 lanes, 4 arms, Town medium. After about 3 s stdout shows `WRITE k=1 ...
   lane0=<n> mode=set_true` and `WRITE_RESULT k=1 ... success=true|false`. Open the Crossing Tool on
   that node (position: the `NODE` line with the same `node=` id, or the arm node nearest the
   roundabout's east side; screenshot if unsure): does the removed lane's arrow into the arm
   disappear, and was it the **inner** or the **outer** ring lane?
2. Place a 4-lane ring with Town medium arms (write k=2, `mode=keep`: userModified not set).
   Same check in the Crossing Tool.
3. Wait at least 60 s unpaused (`PERSIST ... reason=time60s same=true|false`).
4. Edit near written node 1: build a short road onto the end of the arm at that node, then bulldoze
   the outermost arm segment and rebuild it (each logs `PERSIST ... reason=build<N>`). Then use the
   Crossing Tool on the written node and press apply without changing anything.
5. Place a 1-lane ring: expect `WRITE ... status=no_candidate` (nothing changed).
6. Watch the traffic for a minute on roundabout B1 if any town traffic reaches it (optional).

Send back:
- every `[SQRB-LANES]` line:
  `grep -a "SQRB-LANES" ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt > plans/square_roundabouts/probe_lanes.log`
  (no `tools/parse_probe.py` support: the lines are `key=value` and read directly),
- what the Crossing Tool showed in A11, B1, B2 (screenshots welcome), and which ring lane lost its exit,
- any `ERROR` lines, crash or freeze.
When done: set the probe off in the mod list or `make unlink` (never upload this mod).

## Things only checkable in game
- Hermite tangents: the ring uses the exact circle handle 4·tan(θ/4)·r (vanilla's quarter value
  r·4·(√2−1)); the ring should look as round as the base roundabout.
- Whether `subconstructions` plus fully freed edgeLists works (the base roundabout has no
  subconstruction at all, only empty top-level `models`/`groundFaces`).
- Whether a `CYLINDER` collider with different x/y half extents is an elliptic cylinder (Oval).
- `::/infrastructure/street_construction/roundabout.tga` as the menu icon from a mod.
- Whether BOX colliders (through-road half islands) and several ground faces in one
  subconstruction (triangles, halves, magic satellites) behave like the single-cylinder island.
- Whether the island subconstruction is created when it only holds splitter triangles.
