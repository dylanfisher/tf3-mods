# square_roundabouts Phase 5: interchanges, hamburger, channelized junction, earlier unlock

Plan written 2026-10-08. Background: `candidates.md` (ranking), `types.md`, `PLAN.md` (Phases 1-4b:
read "Decisions", "Phase 3 notes", "Phase 3b" root cause, "Phase 4/4b" before touching geometry).

## Scope (user decision, 2026-10-08)
1. **Roundabout interchange** (new menu entry) with layouts **Two-bridge ring**, **Dumbbell**, **Peanut**.
2. **Hamburger / through-about**: extend "Through the centre" on the main entry.
3. **Channelized junction** (new menu entry): T/X junction with slip lanes and triangle islands.
4. **Quick wins**: unlock earlier where the road templates allow it; a test that no edge is
   shorter than ~1 m.
Turbo stays out (PLAN.md "Turbo: deferred").

## Standing rules (unchanged from earlier phases)
- Base-game road templates only. Every node freed, `snapNodes = {}`, pure updateFn, no game API.
- No `checkEnabledScript` (PLAN.md Phase 2a). Every param must do something for every value of the
  others, or follow the accepted precedent (Arm road with Arms None).
- Param keys prefixed `sqrb_`. New params default to values that keep existing builds unchanged:
  `tests/square_roundabouts/test_default_unchanged.lua` must pass without re-recording goldens for
  the main entry and Magic. Re-record only if a change is intentional, and say why in the notes.
- Geometry in pure modules with offline tests; `square_roundabouts_result.lua` maps any geometry
  result to the construction result. New entries reuse it.
- Lua must stay pre-5.3 (`make check`).
- `make check`, `make test`, `make validate MOD=mods/square_roundabouts` pass at the end of every phase.
- Write notes for each phase into this file (section "Phase 5x notes"), same style as PLAN.md:
  decisions, file:line evidence, what's unverified and goes to TESTING.md.

## Phase 5a: research spikes + quick wins
Research (cite files; `.cache/game/...`):
1. **Year gating.** `ScriptParam` has `yearFrom`/`yearTo` (`api/tealdef/api/type.d.tl` ~2986);
   base `diamond_interchange.con.lua` sets them per param. Does a param outside its years
   disappear from the menu, and can two params share a key (one per era)? Does the updateFn get
   the current year in any form? Is there a per-value year?
2. **Pre-1940 one-way.** Every one-way base template is `*_new_*` (1940). Old templates
   (`town_old_*`, `country_old_*`) start at year 0. Is there any base way to make an edge one-way
   without a one-way template: edgeList params, a one-way edge object (`EdgeObject.oneWay`,
   `type.d.tl` ~2775; TF2 had one-way sign edge objects), lane modifiers, or a construction
   result field? Check base content, wiki and `.cache/subscribed/`.
3. **Template years**: list yearFrom/yearTo for every template the mod uses or will use
   (ring, arms, legs, tram, highway, ramps).
4. **Grade separation**: how base `street_constructions.script.lua` (diamond ~line 200-450,
   `addCurvedRamp`) builds bridges: `edgeType = "BRIDGE"`, `edgeTypeName`, z heights, clearance,
   ramp gradients, ramp templates, tags between levels, terrain alignment. Same for tunnels
   (`edgeType = "TUNNEL"`). These are the patterns for 5d.
5. **Signals**: has TESTING.md 7.4 been answered (which field works)? If not, 5c uses the existing
   experimental signal mechanism unchanged and adds TESTING items.

Quick wins (implement):
- **Earlier unlock.** Set each entry's `availability.yearFrom` to the earliest year its templates
  allow. If spike 2 finds a pre-1940 one-way mechanism, add an old-era path (old templates, gated by
  year as spike 1 allows) and unlock from there; if not, keep the main and Magic entries at 1940 and
  document why. The interchange needs highways (1940); the base interchanges unlock 1960, ours may
  unlock 1940. The channelized junction without one-way slip lanes would work with old two-way roads:
  decide in 5b from spike 2.
- **Short-edge test** (`tests/square_roundabouts/test_short_edges.lua`): over the shipped-param sweep of
  every entry (main, Magic, and the new ones as they land), no edge has a chord or Hermite length
  under 1 m, and no two untagged nodes lie within 0.5 m of each other. Helper in `checks.lua` so the
  new entries reuse it.

## Phase 5b: Channelized junction (new entry)
Files: `square_roundabouts_channel.con.lua`, `.script.lua`, `square_roundabouts_channel.lua` (pure
geometry), menu icon `square_roundabouts_channel@2x.tga` (extend `tools/render_icon_square_roundabouts.py`).
Display name "Channelized Junction". Category `street_constructions`.
**5a result:** unlock 1940 like the other entries (`availability.yearFrom = 1940`). The old two-way
roads (`town_old_*`, `country_old_*`, years 0-1940) would carry the main and side road, but slip
lanes need a one-way template and the only pre-1940 one is the unverified station entrance
template (Phase 5a notes, spike 2); two-way slip lanes defeat the point. Add an old era later for
all entries at once if TESTING.md 11.2 confirms that template. Add the entry to
`test_short_edges.lua` `ENTRIES` (short edges + yearFrom check) and its templates to
`checks.YEAR_FROM` if new.

Params (in UI order; defaults first):
- Layout: T, X (`sqrb_ch_layout`)
- Main road / Side road: same template list as Arm road (`sqrb_ch_main`, `sqrb_ch_side`)
- Slip lanes: Near-side corners / All turns off the main road / None — near-side = right turns for
  right-hand traffic (left for left-hand). One-way bypass from the approach arm to the next arm,
  curved (Hermite), template `town_new_one_way_xsmall` (or the leg template the splitter uses).
- Side-road splitter islands: Off / On (reuse the splitter leg code from the main entry; the split
  node feeds the junction node instead of the ring).
- Arm length, Direction (traffic side), Islands (None / Grass / Paved; triangle islands between
  slip lane and corner, outline/fill as the splitter triangles).
Geometry: central junction node with straight two-way arms; slip lanes start and end on the arms
far enough out that the engine-fitted junction model (`checks.engineModel`: free length >= 2.5 m,
kerb corners) passes at both ends. Tune the set-back per main/side template offline; probe in 5e.
Tests: `test_channel.lua` (tags, lengths, overlaps, engine model, short edges, traffic side mirror).

## Phase 5c: Hamburger / through-about (main entry)
- New value on `sqrb_centre`: "Road + traffic lights" (after "Road"). Same geometry as "Road";
  adds signals on the ring at the two nodes where the through road crosses it (both the through
  road's and the ring's entries), using the same field(s) as `sqrb_signals`.
  **5a result:** TESTING.md 7.4 is still unanswered, so this uses the existing experimental
  mechanism unchanged (both `trafficLightYes` and `trafficLightNodePreference`), the value's
  tooltip says so, and TESTING.md 11.6 / the 5e checklist covers it.
- New param "Through road" (`sqrb_through_road`): "Same as arms" (default, current behaviour) plus
  the arm-road template list, so a larger road can cut through a smaller ring. Applies to Road and
  Road + traffic lights (no effect with Nothing / Tram line: accepted precedent). Ring growth rule
  already handles through hw (PLAN.md "Ring growth rule"); the tuning table has no data for other
  through roads, so those combos use `geom.plan` and are listed as a gap in `verdicts.lua V.GAPS`.
- Tests: extend `test_types.lua`; golden default unchanged.

## Phase 5d: Roundabout interchange (new entry)
Files: `square_roundabouts_interchange.con.lua`, `.script.lua`, `square_roundabouts_interchange.lua`
(pure), icon. Display name "Roundabout Interchange". Model the bridge/ramp mechanics on base
`diamond_interchange` (spike 4).
**5a results (Phase 5a notes, spike 4, read before starting):** unlock **1940** (highway and slip
templates from 1940; base interchanges 1960). Bridge `edgeTypeName` by `params.year`:
`steel.bridge` (1940) before 1970, `concrete.bridge` (the base interchanges' bridge, 1970) from
1970 and when `year` is missing (tests); TESTING.md 11.4. "Ring over highway" = the diamond pattern
(highway at z 0, ring/cross road on bridges at 8 m, ramps rise 0 -> 8 m). "Highway over ring" =
the diverging-diamond pattern (highway on normal edges + bridge at 8 m, ring at 0) or the T /
trumpet pattern (highway lowered to -1..-3 m in a cut, bridges at 4-5 m); no base construction
builds road tunnels with portals, so no `TUNNEL`. Offline limits from the base geometry: vertical
separation >= 7 m between a bridge deck and a road it crosses (base 6-8 m), ramp gradient average
<= 10.5 % and Hermite peak <= 15 % (base diamond worst: 10.5 % / 15.2 %), bridge ends at full
height. `checks.overlaps` is 2D: give it a skip for edge pairs that cross with >= 7 m between
their heights; `checks.shortEdges` is already 3D. Add the entry to `test_short_edges.lua` and the
bridge names are already in `checks.YEAR_FROM`.

Params:
- Layout (`sqrb_ix_layout`): Two-bridge ring (one ring over the highway on two bridges),
  Dumbbell (two rings either side, joined by a two-way bridge), Peanut (one one-way loop with two
  lobes; the waist is two opposite one-way bridges).
- Highway (`sqrb_ix_highway`): base highway templates (small / medium / large); built as two one-way
  carriageways like the base interchanges.
- Level (`sqrb_ix_level`): Ring over highway (bridges) / Highway over ring (highway on a bridge, ring
  at grade). If the second doubles the work, ship only the first and note it.
- Ring lanes, Radius (Two-bridge: radius must clear the highway width + margins; grow the ring
  per the PLAN.md growth rule), Cross road (two-way arms on the axis across the highway),
  Arm length, Direction, Centre island (Two-bridge: island in two halves either side of the highway,
  as the through-road halves), Slip road length.
- Slip roads: four one-way ramps between highway carriageways and the ring(s), merging/diverging at
  shallow angles like the base diamond; ramps carry the height change.
Constraint checks offline: clearance under bridges, ramp gradient within the base diamond's values,
engine junction model at every node, no overlaps between levels except where bridged, short edges.
Tests: `test_interchange.lua` (all layouts × highways × levels × directions).

## Phase 5e: probe, docs, release prep
- Extend `mods/square_roundabouts_probe` (still DEV ONLY) with search subsets for the new entries
  and the hamburger through-road combos; document in PROBE.md how to run them. Do not run the game.
- TESTING.md: in-game checklist sections for 5a-5d (incl. pre-1940 unlock if any, hamburger lights,
  ramp heights, peanut direction, slip lanes per traffic side).
- `_metadata/description.html`: features + Changelog entry for revision 3; modinfo summary/description;
  bump `mod.json` revision to 3.
- `make check`, `make test`, `make validate MOD=mods/square_roundabouts`.
- Gallery slides: not now (need in-game captures).

## Handoff to the user (after 5e)
1. Run the probe subsets in game, send the logs; then a tuning pass (gen_roundabouts_tuning) for
   the new entries.
2. In-game test against TESTING.md; fix-ups as Phase 5f.

## Phase 5a notes (2026-10-08)
Sources: `.cache/game/...` (paths below drop that prefix: `api/` = `api/tealdef/api/`, `base/` =
`base/content/`, `sc.lua` = `base/infrastructure/street_construction/street_constructions.script.lua`),
`docs/wiki/modding/constructions/basics.md` (`basics.md`). Gradients computed from the base
geometry with the base helpers re-implemented (Hermite sampled, 400 steps).

### Spike 1: year gating
- **A param outside its years is not in the menu and not in the updateFn's params.**
  `ScriptParam.yearFrom/yearTo` (`api/type.d.tl:2986-2988`; wiki `basics.md:123-124`). The params
  panel keeps only params with `(yearFrom == 0 or yearFrom <= year) and (yearTo == 0 or yearTo > year)`
  (`base/gui/construction/construction.tl:1748`), re-filters when the year changes (`onStep`,
  1912-1919), and sends values only for those indices (`getParamsForValidIndices` 1516-1525). So the
  updateFn must default a missing key, as base does (`base/stations/rail/modular_station/modular_station.script.lua:110`
  `if not params.trackType then params.trackType = 1 end`).
- **Two params may share a key, one per era.** Base does it: `param_util.makeTrackTypeDefaultParam`
  (1930-1980) / `makeTrackTypeHighSpeedParam` (1980-), `makeTramTrackDefaultParam` (0-1910) /
  `makeTramTrackElectricParam` (1910-) (`base/scripts/construction/param_util.tl:7-31, 61-81`),
  both listed in `modular_station.con.lua:46-47` and `modular_terminal.con.lua:189-190`. The panel
  maps key -> visible index (`construction.tl:1760`), so ranges must not overlap. Our test
  "duplicate key" in `test_script.lua` would need an era exception if this is ever used.
- **The updateFn gets the year: `params.year`.** Wiki: templates (`templates.md:44`) and assets
  (`types.md:380`) "year is the current year". Base construction updateFns read it:
  `modular_station.script.lua:117`, `modular_terminal.script.lua:1357`, `modules.script.lua:149`
  (picks `entrance_old_one_way` before 1920, `entrance_new_one_way` after); `airport.script.lua:217`
  guards `if not params.year then params.year = 0 end`, so it can be missing. Unverified for street
  constructions and on re-runs (TESTING.md 11.3).
- **No per-value year.** `ScriptParam.values` is `{string}` with no year (`api/type.d.tl:2948-3000`);
  only menu icons have per-year variants (`IconWithAvailability`, `base/gui/construction/construction_menu.d.tl:196-200`).

### Spike 2: pre-1940 one-way
- **No one-way road template in the street menu before 1940.** Every `town_new_one_way_*` and
  `highway_new_*` template has `yearFrom = 1940`; `town_old_*`/`country_old_*` are two-way
  (spike 3).
- **One candidate: the street station's entrance template.**
  `base/infrastructure/street/constructions/entrance_old_one_way.street_template.lua` (yearFrom 0,
  yearTo 0; sidewalk 3 m, one forward car lane 5 m, sidewalk 3 m = 11 m, half width 5.5; 8.33 m/s =
  30 km/h; `town_old.street` style; no `menuCategory`) and `entrance_new_one_way` (same, new style).
  The modular street station builds them as owned, non-freed entrance stubs
  (`base/stations/street/modular_street_station/modules.script.lua:143-157`). `initiallyLocked` is
  only the lock tool's initial state (`api/type.d.tl:5483`), not a menu lock. Whether it works as a
  freed street is unknown (TESTING.md 11.2).
- **No one-way mechanism without a one-way template.** Construction edgeLists have no direction
  field (`base/scripts/construction/construction_util_serialized.d.tl:143-154`: edgeType,
  edgeTypeName, type, edges, snapNodes, freeNodes, trafficLightYes/No, tag2nodes, alignTerrain;
  wiki `basics.md:630-698` adds only tramTrackType, trafficLightNodePreference, noise).
  `edgeObjects` take only `edge`, `param`, `left`, `model` (`basics.md:700-736`).
  `EdgeObject.oneWay` (`api/type.d.tl:2775`) belongs to `SimpleStreetProposal` (game-script
  proposals, not construction results), and the one-way edge objects in base are rail/airport path
  signals (`base/infrastructure/signal/signal_path_a.con.lua:51`,
  `base/assets/stations/air/signs/sign.script.lua:8` -> `ONE_WAY_PATH_SIGNAL`). Construction
  `laneLists[].forwardOnly` (`construction_util_serialized.d.tl:156-165`) are lanes inside a
  construction, not streets. Nothing in `.cache/wiki-examples/` or `.cache/subscribed/` uses
  anything else (rg "oneWay|ONE_WAY": only proposal-based tools).
- **Decision: main and Magic stay at 1940** (comments in both `.con.lua`). The entrance template
  is not a "real" mechanism until TESTING.md 11.2 passes: never used as a freed street in base,
  one lane only (no 2/4-lane ring, no 2-lane Magic minis, legs would drop from 2 lanes to 1),
  30 km/h, every engine-tuned radius in `square_roundabouts_tuning.lua` is for the 1940 templates
  (a 5.5 m half-width ring has no engine data), and an updateFn that switches on `params.year` could
  change a placed island when it re-runs (TESTING.md 11.3). If 11.2 and 11.3 pass, an old era for
  every entry at once is a follow-up (Phase 5f candidate): old arms are geometry-neutral (town_old /
  country_old have the same widths as town_new / country_new: 16/24/32 and 14/22/30 m), the
  ring/legs become `entrance_old_one_way` (1 lane), Ring lanes gets `yearFrom = 1940` (hidden, so
  the updateFn defaults it to 1 before 1940), a probe subset for the pre-1940 layouts.
- Not taken: unlocking with new-era templates before 1940. Base content suggests construction
  content years are not enforced (the interchanges unlock 1960 but build `concrete.bridge`, 1970),
  but modern highways in 1900 break the era look and are unverified.

### Spike 3: template years (`availability` in each file under `base/infrastructure/`)
| template / type | yearFrom | yearTo | used by |
|---|---|---|---|
| `highway/highway_new_small` (9 m, 1 lane one-way) | 1940 | - | 1-lane ring, Magic minis, base slip roads |
| `highway/highway_new_medium` (18 m) / `_large` (23 m) | 1940 | - | 5d highway |
| `town/town_new_one_way_xsmall` / `_small` / `_medium` (+ `_tram_electrified`) | 1940 | - | ring 2/4 lanes, legs |
| `town/town_new_small/medium/large` (+ `_tram_electrified`) | 1940 | - | arms, Magic links, through road |
| `country/country_new_small/medium/large` | 1940 | - | arms |
| `tram/tram_new` | 1925 | - | tram line middle |
| `town/town_old_small/medium/large/xsmall`, `country/country_old_*` | 0 | 1940 | old era only |
| `town/town_old_*_tram` / `_tram_electrified` | 0 / 1910 | 1910 / 1940 | old era only |
| `tram/tram_old` / `tram_old_electrified` | 0 / 1910 | 1910 / 1925 | old era only |
| `constructions/entrance_old_one_way` / `entrance_new_one_way` | 0 | - | candidate (spike 2) |
| `bridge/stone` (road+rail, 90 km/h, pillars 12-48 m) | 0 | - | old era bridges |
| `bridge/steel` (road+rail, 140 km/h, pillars 70-90 m) | 1940 | - | 5d before 1970 |
| `bridge/concrete` (road+rail, 280 km/h, pillars 60-84 m; base interchanges) | 1970 | - | 5d from 1970 |
| `bridge/trestle` | 0 | 1970 | rail only |
| `tunnel/tunnel_a_car` / `tunnel_b_car` (road) | 1900 / 1970 | - | not planned |
Base street constructions: roundabout and all five interchanges unlock 1960 (`*.con.lua`
availability). So: main and Magic 1940 (latest template 1940), channelized junction 1940, interchange
1940. `checks.YEAR_FROM` holds this table for the tests.

### Spike 4: grade separation in base `sc.lua`
Helpers (`base/scripts/construction/street_util_serialized.tl`): `addStraightEdge` (tangent = p1 - p0,
18-28), `addRamp` (horizontal tangents of length |p1 - p0| at both ends: an S-curve in z, flat at
both nodes, 30-43), `addEdgeAutoTangents` (normalised t0/t1 scaled by `calcScale(dist, angle)`,
52-68; a z component in t0/t1 sets the end slope), `freeAllNodes`. `addCurvedRamp` (`sc.lua:20-32`):
`pI = mid(p0, p1) + diam * (t0 - t1)` with tangent `dir = normalise(p1 - p0)` and `dir.z = +-0.1`;
two auto-tangent edges p0 -> pI -> p1; the upper half goes into the bridge list (rising: second
half is BRIDGE). `addCloverleafRamp` (34-74): exact Hermite midpoint split, the upper half BRIDGE.
- **Bridge lists.** A separate edgeList per template with `edgeType = "BRIDGE"`,
  `edgeTypeName = "/infrastructure/bridge/concrete.bridge"`, `snapNodes = {}`, all nodes free
  (`sc.lua:404-422` diamond, 584-591 / 613-622 DDI, 815-824 T, 983-992 trumpet). Wiki
  `basics.md:681-682`. Base also sets `edgeTypeName` on a normal list (no `edgeType`: harmless,
  `sc.lua:425-433`). Bridge decks are flat in the diamond, T and trumpet; sloped bridge halves in
  the cloverleaf (4 -> 8 m) and DDI (4 -> 8 m). Junctions on a bridge are fine: the DDI joins its
  ramps to the bridged highway at 8 m (`"ew-east"`, `"we-west"`, 545-572).
- **Heights (relative to the construction origin):** diamond `bridgeHeight = 8` (`sc.lua:331`):
  highway at z 0, the cross road (one two-way `country_new_medium`) at 8 m over its whole length:
  bridge from y = -firstY to +firstY (90-120 m, `sc.lua:360`), approaches at 8 m on normal edges
  (the `viaduct` param that would bring them down to 0 is commented out in the con, so
  `z[3] = 8`, `sc.lua:337`). DDI (455-458): highway at 8 m (normal edges + bridge), cross roads at 0.
  T interchange (699-707): main highway lowered to -3 m in a cut (normal edges, no TUNNEL),
  flyovers at 4 m and 10 m. Trumpet (854-862): main highway at -1 m, flyover at 5 m.
- **Clearance (deck z minus the z of the road crossed):** diamond 8 m, DDI 8 m, T 7 m (4 over -3)
  and 6 m (bridge over bridge, 10 over 4), trumpet 6 m (5 over -1). The concrete deck models reach
  2.4 m below the deck (`base/infrastructure/bridge/concrete.bridge.lua` `c_6_rep_*` bboxes), so
  the free height is 3.6-5.6 m. Use >= 7 m (8 m preferred, like the diamond).
- **Ramp gradients** (base geometry, all scales and lane options): diamond slip roads 0 -> 8 m over
  76-106 m: average 7.6-10.5 %, peak 10.9-15.2 % (flat end tangents, so peak ~ 1.45 x average). T
  interchange approaches 0 -> 4 m 4.8-5.6 % / 8.4 %, 0 -> 10 m 8.5-10.2 % / 15.3 %, its descents
  10 -> 0 m over 71-83 m reach 12-14 % / 21 % (the steepest in base). Trumpet 0 -> 5 m 6.0-6.8 % /
  10.2 %. Cloverleaf curved ramps 4 m per half, 5 % average, 10.3 % peak at the 0.1 tangent. DDI
  ramps 14.1 % at the node with tangent (1, 1, 0.2). Highway dip to -3 m: 3-3.8 %. Target for 5d:
  average <= 10 %, peak <= 15 %.
- **Ramp templates and joins.** Slip roads are `highway_new_small` (one-way, 9 m). They join the
  highway carriageway at a node **4 m to the side** of the carriageway node (`entranceExitOffset =
  laneWidth - 1`, `sc.lua:333`) with the **same tag** and a tangent parallel to the highway
  (`(1, 0, 0)`), so they merge/diverge tangentially (tag merge of non-coincident nodes,
  `basics.md:687`). The diamond's highway is `highway_new_large` (3 lanes) outside the ramps and
  `types[streetType]` (2 or 3 lanes) between them, shifted by `threeLaneOffset = 2.5` m
  (`sc.lua:339, 344-351`): the extra lane is the exit/entry lane. Ramp tops join the cross road at
  the bridge's end node (tag `"sn-south"` / `"sn-north"`, both slips of a side at one node,
  arriving/leaving perpendicular, `sc.lua:366-373`): a 4-way junction at 8 m on the abutment. The
  T/trumpet join bridge and approach lists through shared **untagged** nodes at the same position
  (`c1`, `c2`, 762-785); untagged + tagged at one position do not merge (`basics.md:687`). Levels
  are not otherwise "tagged": edges of different heights just cross with no shared node.
- **Carriageways.** Two one-way carriageways, centres at +-(halfWidth + streetDist / 2) with
  `streetDist = 12` m: diamond/DDI always +-13.5 m (halfWidth 7.5, `sc.lua:293-298, 449-453`),
  T/trumpet +-11 m (2 lanes) or +-13.5 m (3 lanes) (`sc.lua:684-693, 839-848`).
- **Terrain.** No base interchange sets `alignTerrain`, `terrainAlignmentLists` or ground faces
  (`result.groundFaces = {}`); normal edges above or below z 0 are left to the engine (embankment
  or floating: TESTING.md 11.5). `alignTerrain = true` exists (`basics.md:695`,
  `construction_util_serialized.d.tl:153`).
- **Params passed:** base updateFns use only `streetType`, `scale` (and the commented-out
  `viaduct`); `captureParams` empty. No year, no bridge choice.
- **Tunnels.** No base street construction builds a road tunnel. The only `edgeType = "TUNNEL"` in
  base constructions: the underground tram station's 10 m stubs at z -18 with
  `tunnel_b_car.tunnel` (`base/stations/street/underground_station/underground_station.script.lua:353-356`,
  via `constructionutil.addEdges` copying `params.edgeType/edgeTypeName` to the list,
  `base/scripts/construction/constructionutil.lua:69-71`). Portals at grade are not shown anywhere
  -> 5d uses bridges and cuts only.

### Spike 5: signals
TESTING.md 7.4 has no result yet (no notes in PLAN/TESTING/probe files); no base or mod file uses
`trafficLightYes` or `trafficLightNodePreference` (rg over `.cache`). 5c keeps the experimental
mechanism unchanged; TESTING.md 11.6 added.

### Implemented
- **Earlier unlock:** no change in year (spike 2 decision); both `.con.lua` say why. Channelized
  junction and interchange: 1940 (sections 5b / 5d updated).
- **`checks.shortEdges(res, minLen, minGap, stats)`** in `tests/square_roundabouts/checks.lua`: on
  the construction result (any entry), chord and Hermite length >= 1 m per edge, no two distinct
  nodes (position + tag) within 0.5 m in 3D unless they share a tag. **`checks.YEAR_FROM`** (spike 3
  table) and **`checks.latestYear(res)`**: the latest yearFrom over a result's templates and
  bridge/tunnel types; an unknown name fails.
- **`tests/square_roundabouts/test_short_edges.lua`:** per entry in `ENTRIES` (main, Magic; new
  entries add a sweep there): every build of the shipped-param sweep passes `shortEdges`, and
  `availability.yearFrom` equals the latest template year over the sweep. Main: the golden grid
  (2,592) plus every radius x 4/6 arms x round/2:1 x lanes x splitter x through x 3 other arm
  roads, clockwise (4,104): 6,696 builds, shortest edge 12.1 m, closest distinct nodes 12.1 m.
  Magic: every value of every param (600 builds): 10.7 m / 10.7 m. Plus a synthetic test of the
  helper. 31 s (runs in parallel with test_types, 101 s).
- Defaults unchanged: no geometry change; `test_default_unchanged` passes without re-recording.

### Unverified (TESTING.md section 11)
11.1 unlock unchanged, 11.2 entrance one-way as a freed street, 11.3 `params.year` in street
constructions and on re-runs, 11.4 bridge type years in constructions, 11.5 elevated plain edges
and terrain, 11.6 signals (7.4) still open.

### Plan changes for 5b-5d
- **5b:** no pre-1940 unlock (slip lanes need a one-way template); 1940. Old era for all entries
  is a follow-up only if TESTING.md 11.2/11.3 pass.
- **5c:** unchanged; signals stay experimental (7.4 open).
- **5d:** unlock 1940 (not 1960); bridge type by `params.year` (steel < 1970, concrete otherwise);
  no tunnels ("Highway over ring" = highway on bridge/embankment at 8 m, or ring over a highway
  lowered into a cut); offline limits: >= 7 m vertical separation at crossings, ramp average
  <= 10 % / peak <= 15 %; 3D-aware overlap skip; slip roads merge tangentially at a node 4 m to
  the side of the carriageway node with a shared tag, as the base diamond.

## Phase 5b notes (2026-10-08)
New menu entry "Channelized Junction" (`street_constructions`, order 3012, yearFrom 1940).
Files (`content/infrastructure/street_construction/`): `square_roundabouts_channel.lua` (pure
geometry), `square_roundabouts_channel.con.lua`, `square_roundabouts_channel.script.lua` (3 lines,
via `square_roundabouts_result.lua` unchanged), `square_roundabouts_channel@2x.tga` (icon, from
`tools/render_icon_square_roundabouts.py`; the two existing icons re-render byte-identical).
`previewIcon` reuses the main entry's `square_roundabouts_preview.tga` until there is a capture (5e).

### Params (UI order, defaults first)
| key | UI | values |
|---|---|---|
| `sqrb_ch_layout` | Button | T, X |
| `sqrb_ch_main` | ComboBox | arm road list, default Town medium |
| `sqrb_ch_side` | ComboBox | arm road list, default Town small |
| `sqrb_ch_slips` | Button | Near-side corners, All turns off the main road, None |
| `sqrb_ch_splitter` | Button | Off, On ("Side-road splitter islands") |
| `sqrb_ch_arm_length` | Slider | 30, 40, 50, 60 m (beyond each arm's outermost node) |
| `sqrb_direction` | Button | Right-hand traffic, Left-hand traffic ("Traffic side"; shared key, same indices as the roundabouts' Direction) |
| `sqrb_ch_island` | Button | None, Grass, Paved (own key: `sqrb_island` has 5 values) |
- Arm length is in because the plan lists it, although Phase 3b removed it from the roundabouts on
  the user's request; it is the easiest param to drop in 5f if the user does not want it (min 30 m,
  so every value passes the engine model).
- No-effect combinations (accepted precedent, Arm road with Arms None): Islands and Traffic side
  with Slip lanes None and splitter Off; Traffic side with "All turns off the main road" and splitter
  Off (that slip set is symmetric).

### Geometry (`square_roundabouts_channel.lua`)
- Frame: main road along x through the centre node `sqrb_ch_centre`, side road north (+ south for X).
  Built for right-hand traffic, then mirrored in x for left-hand (`ch.mirror`): edges keep their
  driving direction, outlines re-CCW, box rotation pi - rot. The side road stays north.
- Arms: straight two-way edges inner node -> slip node -> end. Inner node: the centre; with splitter
  islands the main arms start at the leg nodes (x = +-d) joined by a middle edge, the side arms at the
  split node.
- **Slip lanes** (`town_new_one_way_xsmall`, `geom.LEG`): one per corner in the chosen set
  (right-hand frame, arms 1 E, 2 N, 3 W, 4 S): near-side T = E->N, N->W; X adds W->S, S->E;
  all turns off the main road T = E->N, W->N; X adds W->S, E->S. One Hermite edge (`S.curveEdge`)
  from the slip node on arm a to the one on arm b, leaving arm a towards the centre turned
  `SLIP_ANGLE` = 40 deg towards arm b and joining arm b heading out, 40 deg off its axis
  (`ch.slipEdge`). Every arm a slip lane touches has one slip node (shared by two slip lanes on X /
  the T side arm), so no node has two slip lanes on one side.
- **Set-backs** (`ch.setbacks`, slip node distance from the centre; the same for every layout, slip
  set, arm length and traffic side, tested):
  1. junction room: start + `SLIP_FREE` (4 m) + gore(hw), gore = (hw + 7 cos 40) / tan 40 + 7 sin 40
     (the kerb corner of a straight slip lane beside an arm of half width hw: 19.2 m for hw 7 ...
     30.0 m for hw 16). start = the crossing road's half width; with splitter islands the leg node +
     a leg half width (main), the split node + a leg half width (side).
  2. one-way bend: each set-back >= the other x tan(40 + 2 deg), so the chord lies between the end
     headings. Without it the far side node (splitter) gave an S-bend whose gore overlapped the side
     arm for 31-38 m.
  3. island room: the slip centreline keeps `CORNER_GAP` (7 m) + 7 m from the corner of the two
     roads' kerbs (and the slip and leg bands 7 m apart with splitters, NE leg), both set-backs grown by
     the same amount (bisection, rounded up to 0.5 m). Without this rule 40 deg slip lanes are nearly
     straight diagonals that leave no island (rule 1 alone: kerb 1 m from the corner).
  Results (main / side set-back, m): no splitter 35.7 / 35.7 (country small both) to 54.5 / 54.5
  (town large both), e.g. default town medium + town small 42.2 / 41.4. With splitter islands 58.3 /
  64.7 (country small main, town medium side) to 84.6 / 94.0 (town large both): the side slip node
  sits beyond the split node plus a gore, so the junction gets about 1.5-1.8x larger (tooltip says so).
  Angles tried offline: 30 and 35 deg need bigger set-backs (gore 28-42 m) and still overlapped
  (gore stretch 40-48 m) with splitters; 40 deg passes everything.
- **Splitter islands**: the roundabout's engine-tuned splitter set for the side road
  (`geom.splitParams({armType = side, lanes = 2})`: town/country small 26 m / 40 deg / xsmall legs,
  medium 20 m / 65 deg (town) or 50 deg (country) / one-way small, large 32 m / 50 deg / one-way
  medium). Legs (`geom.legCurves`, shared) from the split node to two main-road nodes at +-(leg half
  width + spread), reaching the main road 5 deg off its normal; entry leg on the inbound driver's
  traffic side. Decision: the plan's "the split node feeds the junction node" is built as two leg
  nodes on the main road (as the ring's X/E nodes), not two legs into the one centre node: that would
  make two edges between the same two nodes (unknown to the engine) with a 2x fork-angle junction.
  On X both side roads share the two leg nodes (4-way nodes). Country medium side roads gave splitter
  triangles of 8-15 m^2 (none with a town large main road): the split node moves out 2 m at a time
  until the triangle is >= 15 m^2 (`SPLIT_TRIANGLE_MIN`, max +12 m): +2 m, +4 m on large main roads;
  checked whatever the Islands param, so the roads never depend on it.
- **Islands** (None / Grass / Paved, no models): a corner island per slip lane, between arm a's
  kerb, the slip lane's kerb, arm b's kerb and (splitter) the leg's kerb, each + `ISLAND_MARGIN`,
  built with the new `S.chainPolygon` (kerb chains cut at their crossings) and `S.offsetPolyline`;
  a BOX collider per corner island (`S.boxFrom` on the kerb side, all corners checked inside) so no
  town building spawns there. Splitter triangles via `geom.legTriangle` (shared). Smallest island
  over the sweep 15 m^2, typical 20-38 m^2.
- Build time offline: 1.0 ms default, 1.8 ms worst (X, splitter, islands, large roads).

### Shared code (existing builds byte-identical; `test_default_unchanged` passes without re-recording)
- `geom.legEdges` -> `geom.legCurves(u, un, split, fork, xPos, ePos, sigma, tags)` (same arithmetic).
- `geom.splitterIsland` -> `geom.legTriangle(leg, legHalf, sigma, clear)` with the ellipse test as
  `clear` (same short-circuit order).
- New: `S.offsetPolyline`, `S.chainPolygon`; `checks.overlaps` takes a per-pair junction limit
  function (numbers as before).

### Offline checks (`tests/square_roundabouts/test_channel.lua`, 9 tests; `test_short_edges.lua`)
- Every layout x main x side x slips x splitter (432): tags, edges >= 10 m, `checks.engineModel`
  (smallest free length 7.3 m: the splitter middle edge), `checks.overlaps` and island clearance.
  Overlaps use the default junction limit except slip lane pairs: a 40 deg gore keeps the bands
  overlapping for (hwA + hwB + 0.5) / sin 40 m (up to 36.5 m for large roads), bounded separately by
  the engine model.
- Traffic side: left-hand = mirror of right-hand for all 432 (edges, tags, islands, colliders); near-side
  slip lanes turn right (RHT) / left (LHT), leave from the inbound lanes and join the outbound lanes;
  entry legs on the traffic side; "all turns" slips always main -> side.
- Islands: one face per slip lane and splitter, >= 15 m^2, base textures, colliders inside, and the
  Islands param never moves a road. Set-backs independent of layout / slips / arm length / traffic side.
- Arm length per value; con params (keys, order, defaults = readParams, no checkEnabledScript),
  updateFn (all nodes free, no snap nodes, only updateFn exported).
- `test_short_edges.lua` ENTRIES: every value of every param (Islands None / Paved), 6,912 builds:
  shortest edge 26.0 m, closest distinct nodes 26.0 m; templates all 1940 = yearFrom. No new
  templates (`checks.YEAR_FROM` unchanged).

### Unverified (TESTING.md section 12)
Everything engine-side: the 40 deg gores (the engine model was fitted on roundabouts, never on a slip
lane beside an arm), slip lanes ending on a node shared with another slip lane, legs joining a straight
main road (engine-tuned on rings only), 4-way leg nodes on X, the big splitter + slip layouts, box
colliders on corner islands, the town-road slip template on country roads. Probe subset in 5e.

### Affects 5c-5e
- 5e probe: a channel subset (main x side x splitter, T and X, near-side; SLIP_ANGLE / CORNER_GAP /
  SLIP_FREE as dev overrides would let a search shrink the set-backs, none exist yet).
- 5e description/changelog: new entry; preview image still the roundabout's.
- `checks.overlaps` function limit is available for 5d (3D skip still to add).

## Phase 5c notes (2026-10-08)
Hamburger / through-about on the main entry. Files: `square_roundabouts_geometry.lua`,
`square_roundabouts.con.lua`; tests `test_through.lua` (new), `verdicts.lua`,
`test_engine_verdicts.lua`, `test_short_edges.lua`, `test_script.lua`. `square_roundabouts_result.lua`
unchanged (it already maps `signalYes` / `signalPref` of any list).

### Params (UI order)
| key | UI | values |
|---|---|---|
| `sqrb_centre` | Button | Nothing, Road, Tram line, **Road + traffic lights** (appended: index 4, indices 1-3 unchanged; per-value tooltips, the 4th says experimental) |
| `sqrb_through_road` (new, right after Through the centre) | ComboBox | **Same as arms** (default, `geom.THROUGH_SAME`), then the arm road list (2 = town small ... 7 = country large) |
- `readParams`: `spec.centre` up to 4; `spec.throughRoad` (raw index) and `spec.throughType` (arm road
  index: the arm road for Same as arms). Foreign values fall back to Nothing / Same as arms.
- Through road has no effect with Nothing or Tram line (accepted precedent, tested: identical results).
  Choosing the arm road explicitly = Same as arms (identical result, tested on a golden sample).

### Behaviour
- **Road + traffic lights** = the Road geometry exactly (lists, island, radius: tested over every
  layout/lanes/shape/direction/splitter/tram), plus `geom.throughSignals`: the first axis node via
  `trafficLightYes`, the second via `trafficLightNodePreference`, each on the ring list (both ring
  entries of the node, as sqrb_signals) and on the through road's list (its end entry). Decision:
  split the two fields across the two crossings like the Traffic lights param, so the in-game test also
  answers 7.4; once 7.4 is answered both crossings use the working field. With Traffic lights =
  Entries too, a crossing node already listed on the ring (either field) is not added again (no node in
  both fields on one list; tested). The axis arms' own lists get nothing.
- `geom.patternKey` maps centre 4 to 2 (same geometry, so Road's engine data applies). Assumption: the
  lights do not change whether the engine accepts the layout (TESTING.md 13.1).
- **Through road**: template `ARM_TEMPLATES[throughType]`, `ARM_TRAM[throughType]` with Tram tracks On
  (country: same template + `tramTrackType = "ELECTRIC"`, as arms). The axis arms keep the arm road.
  `geom.throughHalfWidth` returns the through road's half width, so the existing ring growth rule
  (strip clearance, `THROUGH_JUNCTION`, junction room spokes in `geom.plan`) and the island halves use
  it with no other change. Example (4 town small arms, 2 lanes, slider 8 m): through town small 10 m,
  medium 20 m, large 25 m, country small 8 m, medium 15 m, large 25 m; slider 20 m: 20 / 20 / 25 /
  20 / 20 / 25 m; 40 m: no growth.
- **Engine data**: none for a through road other than the arms (`geom.throughOwnRoad`). Then
  `geom.engineRadius` returns the pattern's radius as a floor (source `"through"`, not exact): the
  offline model must accept it, else the ring grows from above it (`built.floor`). Splitter floors
  were already unverified with a through road. `verdicts.lua`: new gap category `through` (V.GAPS) and
  `V.through(geom)` listing every probed Road pattern x 5 other through roads x {Road, Road + lights}
  (800 gaps; a problem if one still claims an exact engine radius); `V.judge` never judges a
  through-own-road build, so the tests check it with the engine-fitted model.
- Existing builds unchanged: `test_default_unchanged` passes without re-recording; no tuning change.

### Offline checks (`test_through.lua`, 10 tests, ~120 s; runs in parallel with test_types / test_junctions)
- Signals on the right nodes / lists / fields, result indices (both ring entries, through end 0 / 1).
- Through templates for every centre (Road, lights) x arm road x through road x tram.
- Sweep (2,160 builds: round / 2:1, 1/2/4 lanes, every layout, slider 8 / 20 m, splitter, arms town
  small / large / country medium x the 5 other through roads): no forced plan, fits `geom.plan` at the
  built radius (or a pending splitter floor, judged as before), minimal growth, every ring node off the
  axis clear of the through strip by the through road's half width; tags, lengths; engine-fitted model
  at slider 8 m; overlaps on a smaller grid; tram tracks and clockwise: engine model. 751 of 2,160 grow
  beyond the same layout with the arm road through; 286 start from an engine floor.
- **Overlap limit**: through/ring pairs may share a junction stretch of up to 40 m (default 30 m). The
  30 m limit was already exceeded by same-as-arms town-large through roads on 2:1 ovals (29-36 m;
  never covered by the old tests: test_types' overlap grids had no wide road through), and the engine
  accepted every one of those in the Phase 3b sweep (e.g. `m:5,3,1,1,1,2,3,1` at 45 m: 36.0 m). 40 m
  covers every through road on the grid (24 of 192 sampled builds exceed 30 m, none 40 m).
- Island halves: clear of the through road by its half width + margin and reaching it within 0.5 m,
  colliders and models inside, `islandClear`; halves shrink for a wider through road.
- At slider 60 m, 24 sweep builds are forced (2:1, 4 lanes, Y / 5 arms, large arms, splitter): the same
  combos are forced with the arm road through (pre-existing, not from 5c: the old "fits without
  fallback" tests only start from 8 m). Tested: a through road never forces a plan the arm road would
  not. Candidate for 5f (or the 4b known gap "nothing accepted up to 120 m").
- `test_short_edges.lua` main sweep + 1,080 Road + lights x through road builds (7,776 total): shortest
  edge 12.1 m, closest nodes 12.1 m; all templates 1940.

### Unverified (TESTING.md section 13)
Lights at the crossings (7.4 still open), lights + Entries together, larger through roads through
small rings (engine never saw them), tram through roads of another size, priority at a 4-way crossing
with a much wider road.

### Affects 5d/5e
- 5e probe: `probe_grid.lua` has no `sqrb_through_road` axis and no centre value 4; add a subset
  (Road through x 5 other through roads x layouts x lanes, small sliders) and feed it to the
  tuning generator (`patternKey` would need the through road, or a separate table part). Until then
  these combos are V.GAPS `through`.
- 5e description/changelog: "Road + traffic lights" and "Through road" params.
- `checks.overlaps` function limit is used for the through/ring 40 m allowance (`overlapLimit` in
  test_through.lua); 5d can reuse the pattern.

## Phase 5d notes (2026-10-08)
New menu entry "Roundabout Interchange" (`street_constructions`, order 3013, yearFrom 1940).
Files (`content/infrastructure/street_construction/`): `square_roundabouts_interchange.lua` (pure
geometry), `square_roundabouts_interchange.con.lua`, `square_roundabouts_interchange.script.lua`
(3 lines via `square_roundabouts_result.lua`), `square_roundabouts_interchange@2x.tga` (icon from
`tools/render_icon_square_roundabouts.py`; the three existing icons re-render byte-identical).
`previewIcon` reuses the main entry's preview until there is a capture (5e).
**Both levels shipped**: "Highway over ring" is the same plan geometry with the heights swapped and
the highway bridged instead of the ring roads, so it did not double the work.

### Params (UI order, defaults first)
| key | UI | values |
|---|---|---|
| `sqrb_ix_layout` | Button | Two-bridge ring, Dumbbell, Peanut |
| `sqrb_ix_highway` | Button | Small, **Medium**, Large (`highway_new_small/medium/large`, half width 4.5 / 9 / 11.5 m) |
| `sqrb_ix_level` | Button | Ring over highway, Highway over ring |
| `sqrb_lanes` | Button | 1, **2**, 4 (shared key: same values and templates as the main entry's Ring lanes) |
| `sqrb_ix_radius` | Slider | 15, **20**, 25 ... 60 m (inside the ring road; a minimum, grows up to 120 m) |
| `sqrb_ix_cross` | ComboBox | arm road list, default Town medium (arms; the dumbbell's link) |
| `sqrb_ix_slip_length` | Slider | 120, **140**, 160, 180 m (along the highway, ring node to carriageway node) |
| `sqrb_ix_arm_length` | Slider | **30**, 40, 50, 60 m (cross road beyond the ring's outer kerb; highway beyond the outer slip nodes) |
| `sqrb_direction` | Button | Right-hand traffic, Left-hand traffic ("Traffic side"; shared key, same indices) |
| `sqrb_island` | ComboBox | None, Grass, Grass and trees, Fountain, Paved (shared key, same values as the main entry) |
- `readParams` also reads `params.year` (spike 1) for the bridge type: `steel.bridge` before 1970,
  `concrete.bridge` from 1970 and when the year is missing (`ix.bridgeType`).
- Accepted no-effect values (precedent): Radius below the two-bridge ring's smallest span builds that
  span (25-40 m, see below; "a minimum", tooltip says so); Centre island None adds nothing. Every
  other value of every param changes the build for every layout (tested).

### Geometry (`square_roundabouts_interchange.lua`)
Built for right-hand traffic, mirrored in x for left-hand traffic (new shared `geom.mirrorX`, which
`ch.mirror` now calls: same arithmetic, test_channel's mirror test passes unchanged). Highway along
x, cross road along y.
- **Cross-section** (`ix.frame`): carriageways at y = -+c, c = highway half width + `MEDIAN`/2 = 2 m
  (4 m kerb to kerb: the base diamond's large highway, centres +-13.5 m); south = eastbound. Corridor
  = c + half width. `CLEAR` = 8 m: plan gap between the highway kerb and any upper-level road that is
  not a bridge (embankment toe), and between a lower-level road and the highway bridge's end.
- **Heights**: `HEIGHT` = 8 m (base diamond). Ring over highway: highway z 0, every ring-level road
  (rings, link, waist, arms) at 8 m; the edges over the highway are bridges. Highway over ring:
  rings at 0, highway at 8 m with one bridge edge per carriageway from -xb to +xb, xb = the largest
  |x| at which a ring-level road comes within CLEAR of the corridor, + CLEAR (rounded up; 21 m
  dumbbell, 28-47 m peanut, 43-71 m two-bridge). Arms end at their level (8 m for ring over: like the
  base diamond's cross road, `sc.lua:337`). All non-ramp edges level with flat tangents; bridges at
  full height at both ends.
- **Two-bridge ring**: one circle around the origin; slip nodes = bridge ends at +-alpha off the
  highway axis, sin alpha = max(yClear / (rc - ring hw), (yClear + ramp hw) / rc) (ring band and
  the arriving slip road clear the corridor by CLEAR at the node), alpha <= `ALPHA_MAX` 60 deg (else
  the ring grows), a plain mid node over the highway when 2 alpha > 90 deg. Arms at 90 / 270 deg.
  Slip roads join parallel to the highway (gamma = alpha). Smallest radius from the 15 m slider: 25 m
  (small highway; 30 m with 1 lane and town large), 35 m (medium), 40 m (large); alpha 47-58 deg.
- **Dumbbell**: rings at (0, +-D), D = yClear + ring hw + rc (each ring's kerb CLEAR from the
  corridor); nodes at 0 / 90 / 180 / 270 deg (slip, arm / link, slip, link / arm). Two-way link
  (cross road template) straight between the rings' facing nodes, a bridge for ring over. Slip roads
  at the rings' east/west nodes, joining along the inward normal turned `GAMMA` = 35 deg towards the
  circulation (towards the highway). Radius stays at the slider (15 m; 20 m for 1 lane + town large).
- **Peanut**: lobes (circles, rc) at (0, +-D); waist nodes at 270 +- beta (north lobe), y = yw =
  yClear + ring hw; the waist = two one-way Hermite edges (west southwards, east northwards) with the
  lobes' tangents at both ends (length 2 yw), so they pinch towards the axis by yw cos(beta) / 2;
  beta = the smallest from 30 deg in 1 deg steps keeping `WAIST_GAP` = 6 m between the waist kerbs at
  the pinch (50-67 deg). D = yw + rc cos(beta). Lobe arcs are open (no closing edge); slip roads at
  the lobes' east/west nodes like the dumbbell (first try at the waist nodes, gamma 0: the slip roads
  ran back over the carriageway's band at 7 m height, rejected). Radius 15 m, 20 m for some 4-lane /
  large combos.
- **Slip roads** (`ix.rampEdges`, `highway_new_small`): two edges each. Gore: level with the highway
  from the carriageway node's tag at `MERGE_OFFSET` 4 m outside it, parallel (the base diamond's merge,
  `sc.lua:333, 366-373`), out to a plain node G where the slip road is `GORE_GAP` 1 m clear of the
  carriageway band, max(`GORE_RUN` 30 m, 2.5 x lateral) along the highway (gore 25-31 m; base
  25.8-37.5 m). Climb: G (parallel) to the ring node (`ix.slipDir`), all of the 8 m. Decision: one
  Hermite edge per slip road (the base pattern) was up to 5 m (two-bridge, dumbbell) and 7.8 m
  (peanut) up while still inside the carriageway band (base: 1.6-3.1 m); the level gore fixes that.
  Off-ramps leave before the junction, on-ramps join after it (driving direction).
- **Ring growth** (`ix.plan`/`ix.fit`): slider radius, then the larger slider values and
  `GROW_RADII` 70-120 m, the first where the layout exists (alpha / beta) and every ring arc keeps
  `geom.JUNCTION_PLAN` 5 m free (geom.kerbCut with arms / link / slip roads as spokes, slip roads as
  curves) and a chord >= MIN_EDGE, corners behind <= 1 m (arms) / 5.8 m (slip roads). Never forced
  over the shipped params (tested).
- **Islands** (`ix.islands`): two-bridge: `geom.islands` with the highway corridor as the "through
  road" (halves, box colliders, centre model, bushes); dumbbell: `geom.islands` per ring, translated;
  peanut: each lobe's inner outline cut at the waist node line, box collider and models as the halves.
  Islands are ground faces at terrain level (under a ring at 8 m for ring over).
- **Footprint** (radius 15 m slider, 30 m arms): 377-402 m along the highway; across 129-186 m
  (two-bridge), 196-278 m (dumbbell), 182-267 m (peanut). Build 1.4 ms offline.

### Shared code (existing builds unchanged; `test_default_unchanged`, `test_channel`, `test_through` pass without re-recording)
- `square_roundabouts_result.lua`: copies `edgeType` / `edgeTypeName` of a list when present (no
  existing list has them).
- `S.mirrorX`, `geom.mirrorX` (from `ch.mirror`; also mirrors island models, none in the channel).
- `tests/.../checks.lua`: edge records carry `bridge`; `checks.overlaps` also treats a shared **tag**
  as a shared end (tag-merged slip roads; existing tags are at one position, so no change) and
  measures footprints in plan (`dist2`: identical at z 0, needed for elevated roads);
  new `checks.levelSkip(minSep, margin, stats)`.

### Offline checks (`tests/square_roundabouts/test_interchange.lua`, 10 tests, ~50 s; `test_short_edges.lua`)
- Every layout x highway x level x traffic side x lanes x cross road town small / large, country
  small / large (432 builds): no forced plan; tags (slip roads snapped onto their carriageway node);
  edges >= 10 m; `checks.engineModel` at every node (smallest free length 5.2 m; the tag-merged
  carriageway nodes are not modelled: base-diamond pattern, checked by the gore test instead);
  heights (levels flat, bridges at 8 m, slip roads climb the full 8 m with flat ends); gradients:
  average <= 9.1 %, peak <= 13.7 % at the 120 m slip length (<= 7.4 % / 11.1 % at 140 m); merge: 4 m
  outside, parallel, same tag; gore <= 40 m; on the widest / narrowest cross roads `checks.overlaps`
  with `levelSkip(7)` (every crossing >= 8 m apart, the upper edge a bridge; at least two crossings
  per build) and `islandClear`.
- Radius / slip / arm length sample (160 builds), radius growth minimal, LHT = mirror (and rings
  clockwise, carriageways on the left), slip road directions / quadrants, every param changes the
  build, islands (two per build, clear of the corridor, colliders / models inside), con params (keys,
  order, defaults = readParams, no checkEnabledScript), updateFn (all nodes free, one bridge list,
  steel 1940-1969 / concrete 1970+ / concrete without a year).
- `test_short_edges.lua` ENTRIES: 3,456 builds with `params.year = 1969`: shortest edge 11.4 m,
  closest distinct nodes 11.4 m; latest template year 1940 = yearFrom (without a year the bridges are
  concrete, 1970, as the base interchanges, which unlock 1960 with them).

### Unverified (TESTING.md section 14)
Everything engine-side: bridges built from a construction with ring junctions on their ends
(two-bridge, peanut waist), a two-way link bridge between two ring nodes, the 8 m ring-level
roads on plain edges (embankments; 11.5), the level gore edge + plain node G (instead of the base's
single ramp edge), CLEAR 8 m next to the highway, the steel bridge for road spans of 40-140 m,
`params.year` in a street construction (11.3) and whether the bridge type flips when an old build
re-runs after 1970, the island faces under a ring at 8 m, junction model never fitted on slip roads.

### Affects 5e
- Probe subset: layouts x highways x levels x lanes (default cross road, radius 15 m), plus town large
  / country large cross roads and 120 m slip roads; dev overrides that would help a search: `CLEAR`,
  `GAMMA`, `GORE_RUN`, `WAIST_GAP` (none exist yet).
- Description / changelog: new entry with both levels; preview image still the roundabout's.

## Phase 5e notes (2026-10-08)
Probe subsets, dev overrides, in-game checklist, release text. No game run (no data yet), no
tuning change (`gen_roundabouts_tuning.py --dry-run` writes the table byte-identical).

### Probe (`mods/square_roundabouts_probe`, DEV ONLY; markers unchanged, description mentions the new parts)
- **Entries** (`probe_grid.lua`): `channel` (`c:`) and `interchange` (`x:`) with axes in `.con.lua`
  order; the interchange has a pseudo axis **year** (1969 / 2020, passed as `params.year`: steel /
  concrete bridges; `axis.values` maps index -> value, `axis.pseudo` = not a menu param). Main:
  centre label `lights` (value 4) and a **through** axis appended last (an 11-value key = Same as
  arms, the Magic-lanes precedent). Phase 3-4 subsets are unchanged: their `centre = "*"` became
  `CENTRES` (none/road/tram), tested (no lights, through = 1).
- **Subsets** (combos/jobs, max engine calls, estimate at ~20-40 calls/s): `p5_channel` 968 (~25-50 s),
  `p5_hamburger` 720 (~20-40 s), `p5_interchange` 282 (~10-20 s), `p5_all` = the three, 1,970
  (~1-2 min); `p5_channel_search` 144 jobs / 1,728 calls (~45-90 s), `p5_interchange_search` 18 /
  360 (~10-20 s), `p5_hamburger_radius` 360 jobs / max 8,280, expected ~500-1,500 (~0.5-1.5 min),
  `p5_search` = the three, 522 jobs (~2-4 min). Smoke gained 3 combos (hamburger + lights, channel
  and interchange defaults): 20. Details and what each covers: PROBE.md "Phase 5e runs".
- **Search kind `grid`**: cartesian product of dev values, shipped values first, every candidate.
- **Dev overrides** (named in the 5b/5d notes, cheap: one `tuned()` lookup each; read only when
  present via `geom.readDev`, never in a `.con.lua`): `chSlipAngle`, `chCornerGap`, `chSlipFree`
  (`square_roundabouts_channel.lua`: `ch.slipAngle(spec)`, `ch.gore(hw, angle)`,
  `ch.slipEdge(..., angle)`, `ch.setbacks`), `ixClear`, `ixGamma`, `ixGoreRun`, `ixWaistGap`
  (`square_roundabouts_interchange.lua`: `f.clear` in `ix.frame` and `highwayBridgeHalf`, gamma and
  waist gap in `ix.layout`, gore run in `ix.rampEdges`). Without them every build is unchanged
  (`test_default_unchanged`, `test_channel`, `test_interchange`, `test_short_edges` pass without
  re-recording). New test in `test_dev.lua` (absent = shipped; each override moves its part; other
  entries' dev keys do nothing; no `.con.lua` of the four entries uses a dev key). Note: without
  splitter islands the channel set-backs are set by the island room rule, so `chSlipFree` alone
  does not move them (only with a smaller `chCornerGap`); the grid search covers the combinations.
- **Geometry correlation** (`probe_geom.lua`): channel `setback=main/side`, interchange
  `effR`/`forced`/`bridge`; R and T lines got `setback=` and `bridge=` fields; START names
  `channel=` / `interchange=`; the engine resolves all four constructions (`grid.ENTRY_ORDER`).
- **Dev construction for TESTING.md 11.2** (the 5a notes asked for "a probe build"): "DEV Probe:
  pre-1940 one-way (NOT FOR UPLOAD)" (`content/infrastructure/street_construction/sqrb_probe_old_one_way.*`,
  all years, order 3099): straight / ring / ring + four `town_old_small` arms built from
  `entrance_old_one_way` or `entrance_new_one_way`, every node freed, via
  `square_roundabouts_result.lua`. Unverified in game (that is the question).
- **parse_probe.py**: AXES for the new entries (`entry` and `key` columns as before), the through
  axis, `canon_key` for 11-value main keys, report sections per new entry (pivots, "Bridge type by
  year": equal costs on every 1969/2020 pair = the year did not reach the updateFn), "Grid
  searches". **Output names by subset**: smoke and every `p5_*` run write `probe_<subset>.*`
  (searches `_jobs.csv` / `_trials.csv`), so they can never overwrite `probe_results.csv` /
  `probe_search*.csv` that the tuning generator and `test_engine_verdicts` read (before, a smoke
  parse overwrote `probe_results.csv`). Checked on synthetic logs from the real runner (p5_all,
  p5_search).
- **Key compatibility**: `gen_roundabouts_tuning.py` `key_indices` maps a 12-value main key with
  Same as arms to the 11-value pattern and skips other through roads / Road + traffic lights (tag
  `m-through`); `verdicts.lua` `MAIN_ORDER` gained `throughRoad`, so a re-run of an old subset
  replays correctly.
- Tests (`tests/square_roundabouts_probe/`, 44): subset sizes, axes == the four `.con.lua`s
  (main: in order with the through road last; pseudo year skipped), grid candidates and bounds,
  dev params reach the real channel / interchange geometry and every candidate is sane, every
  `p5_all` combo sane (interchange never forced, bridge by year), log lines of the new entries,
  the dev construction (params, result, templates exist in the base game).

### TESTING.md
New "Phase 5 walkthrough" header (probe first; which save for which item: 1930s, 1965, 2020);
11.1 covers all four entries; 11.2 now a concrete test with the dev construction; 11.3 / 11.4
point to the probe's year check and 14.3; 11.6 points to 13.2. 12: probe pointer, 12.6 slip lanes
per traffic side (both sides spelled out). 13: probe pointer, 13.2 records the 7.4 answer per
crossing. 14: probe pointer, new 14.4 ramp heights and 14.6 peanut direction, 14.3 bridge type
flip with save/reload, renumbered 14.5-14.12. No duplicates with sections 7-10.

### Release text (revision 3)
`mod.json` revision 3; `description.html`: intro names the four entries, features for hamburger
roundabouts / Channelized Junction / Roundabout Interchange, settings for Through the centre (Road +
traffic lights), Through road, and the two new entries, a note that the new entries are less
engine-checked, "four construction menu entries", Changelog "Revision 3 (2026-10-08)" first;
`modinfo.json` summary (96 chars) and description. `make validate` OK. Cover tagline "Round, oval
or Magic Roundabout" is 31 characters (fits); name unchanged, no re-render. Hover previews of the
new entries are still the roundabout's; gallery slides need in-game captures (not now).

### Results
`make check` square_roundabouts 15 files / probe 10 files, 0 errors; `make test`
square_roundabouts 127 passed (~111 s), probe 44 passed; `make validate` square_roundabouts OK,
probe the two expected warnings (no cover, upper-case NOT_FOR_UPLOAD.txt).

### Handoff
1. **Probe sweep** (`p5_all`, ~1-2 min): `make link`; TF3, the flat test map (flat, empty, centre on
   land, year 2020, right-hand traffic); enable Better Roundabouts (revision 3) + DEV Roundabouts
   Probe; settings: Run the probe On, Subset **p5_all**, Start delay 15 s, Combos per update 8,
   Position 0 / 0, Proposal context None, Log placeable combos On. Load, pause, wait for
   `[SQRB_PROBE] END`; START must show `channel=` and `interchange=` names (not `-`). Copy
   `.../crash_dump/stdout.txt` to `plans/square_roundabouts/probe_p5_all.log`.
2. **Probe searches** (`p5_search`, ~2-4 min): reload with Subset **p5_search**, same settings; wait
   for END and the `dev override check ... reach the updateFn` line; copy stdout.txt to
   `plans/square_roundabouts/probe_p5_search.log`.
3. Send back the two logs `probe_p5_all.log` and `probe_p5_search.log` (or parse them:
   `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5_all.log`, same for
   `probe_p5_search.log`), then disable the probe. Next: a tuning pass for the new entries
   (channel set-backs, interchange clearances, hamburger floors: `geom.patternKey` needs the through
   road first) and fixes for anything refused, as Phase 5f.
4. **In game, TESTING.md**: "Phase 5 walkthrough", then 11 (11.1-11.2 in a 1930s save with the
   dev construction "DEV Probe: pre-1940 one-way"; 11.3-11.5), 12 (Channelized Junction, 12.6 in a
   right- and a left-hand traffic save), 13 (13.2 answers 7.4 in a 1950+ save), 14 (14.3 bridge flip
   from a 1965 save, 14.4 ramp heights, 14.6 peanut direction, 14.10 islands).

## Phase 5f notes (2026-10-08)
Engine tuning from the Phase 5e probe runs (`probe_p5_all.*`: 1,970 combos, 654 refused, all
"Construction Not Possible", updateFn fine; `probe_p5_search.*`, run 2 of the log: 522 jobs) and
fix-ups. Counts "before / after" are the engine verdicts replayed against the shipped geometry
(`tests/square_roundabouts/test_engine_verdicts.lua`); "after" = ships a layout the engine accepted.
No revision bump (revision 3 is unpublished); the changelog entry gained the oval line.

### 1. Hamburger / main entry (through road patterns)
- **Pattern key**: `geom.patternKey` appends the through road's arm road index as a ninth field when
  it differs from the arm road (`geom.throughOwnRoad`); `geom.basePatternKey` is the old 8-field key.
  `geom.radiusFloor` looks up the spec's own pattern first, else (another through road) the arm-road
  pattern's cell, and returns whether the cell is its own; `geom.engineRadius` returns source
  `"through"` (a floor, as in 5c) only for the second case. Same as arms / the arm road chosen
  explicitly / a tram line: unchanged 8-field key.
- **Generator** (`tools/gen_roundabouts_tuning.py`): `--jobs` / `--sweep` take several files (defaults:
  `probe_search.csv` + `probe_p5_search_jobs.csv` + `probe_p5f_search_jobs.csv`; `probe_results.csv` +
  `probe_p5_all.csv` + `probe_p5f_all.csv`; missing files skipped). `key_indices` keeps 12-value keys
  with another through road and maps Road + traffic lights to Road; `pattern_of` adds the ninth field;
  clockwise inference finds the direction field by position. With only the Phase 4 files the table is
  byte-identical apart from the header comment (checked). New cells: 18 searched through patterns
  (+18 clockwise copies, `inferred`), from the 30 refused jobs: 12 where the engine needed more than
  shipped (e.g. 1 lane, Y, town large arms, Through road town medium: 30 -> 35 m; 1 lane, Arms None,
  town large arms, town small through: 10 -> 20 m; 4 lanes, Y / 6 arms, town large arms, town medium
  through: 25 -> 30 m) and 18 where p5_all refused the shipped radius and the search accepted a
  smaller one (e.g. 4 lanes, Y, town small arms, country small through: 15 -> 12 m; 4 lanes, Y, town
  small arms, town medium through: 25 -> 20 m). Patterns 755 (was 719), inferred 348 (was 330).
- **Replay**: p5_all main **660 / 720 -> 720 / 720** (the 60 refused combos = 30 jobs x Road / Road +
  lights now ship the found radius, exactly the layout the probe sent; the 660 accepted ones are
  unchanged: no cell changed for them). `V.GAPS.through` **800 -> 720**: 40 searched combos are no
  longer gaps, 40 clockwise copies of them moved to `cw`. The remaining 720 are patterns the search
  did not cover (splitter, ovals, tram tracks, other arm roads, sliders above 20 m).
- **verdicts.lua**: `V.canonical` (lights -> Road, Same-as-arms 12-value -> 11-value, Arms None ->
  splitter off), `V.patternOf` (= geom.patternKey of a key), `V.searchedPatterns`, `V.through(geom,
  jobs)`; `V.judge` judges through-road builds by their own pattern (no blanket exclusion);
  `V.loadAll` concatenates the Phase 4, 5e and (when present) 5f files; test_types / test_junctions /
  test_through / test_engine_verdicts use it.
- **Pre-existing forced plan (5c)**: 2:1, 4 lanes, Y / 5 arms, large arms, splitter islands: the
  rule's radial split ran a leg along the ring on the long flank (`LEG_HUG`) at every radius, scale
  invariant, so no ring size helped; built forced at 60 m from sliders 45-60 m and at the 40 m floor
  with the offline model rejecting it below. No engine data for it (no oval splitter searches with
  large arms). Fix: `geom.choosePlan`'s last offline fallback (after forkBump, before the floor)
  retries with `spec.splitNormal`: splitter arms leave along the ring normal like plain arms
  (`geom.splitAxis`; `solveSide` scans for the first crossing then, the lateral offset is not
  monotonic there). Fits at every radius 40-120 m; 1-2 lane rings and round rings never use it
  (tested). Probe check: `p5f_all` (24 combos). Still forced (pre-existing, not in the brief): 2:1,
  1 lane, T / 4 arms, large arms, splitter, sliders 45-60 m (64 builds over both tram and traffic
  side values; the legs cannot meet a 1-lane ring steeply enough on the tight oval end).
- **Golden re-recorded on purpose**: 12 groups (main, Y / 5 arms, splitter on), 36 of 3,888 main
  builds: exactly the splitNormal builds (12 were forced at 60 m, 24 the 40 m floor). Magic and
  every other group unchanged.

### 2. Interchange: two-bridge ring with 4 lanes
- Data: all 30 refused p5_all interchange combos are two-bridge + 4 lanes (every highway, level,
  cross road, slip length, year); 1 and 2 lanes and every dumbbell / peanut placed.
- Offline geometry (4 lanes vs 2): the junction model is fine (free >= 14.6 m, nothing behind), the
  bridges are not the cause (Highway over ring has no ring bridges and fails the same; peanut waist
  bridges with the 4-lane template place). The difference is the slip node: slip roads join parallel
  to the highway, i.e. 90 - alpha off the ring's tangent: 2 lanes 36-43 deg (accepted), 4 lanes
  32-38 deg (alpha 52-58 deg, refused); the dumbbell's 4-lane slip roads join at 55 deg (accepted).
  The channel data shows the same: a slip on a 3-lane-per-direction arm is refused at 40 deg and
  accepted at 50 deg (below), and the roundabouts' splitter search needed wider forks / more leg
  lanes on wider arms. The 4-lane one-way ring has 4 lanes, the widest road in the set.
- Fix: `ix.ALPHA_MAX_LANES = {60, 60, 40}` deg (`ix.alphaMax`; dev override `ixAlphaMax`): with 4
  lanes the slip nodes stay within 40 deg of the highway axis (joins >= 50 deg), so the ring grows:
  15 m slider -> 35 / 45 / 55 m for small / medium / large highways (was 25 / 35 / 40 m). 1-2 lanes
  unchanged (no other build changed: test_interchange, test_short_edges pass unchanged).
- Replay: **252 / 282 -> 252 / 282 verified + 30 changed, unverified** (gap `interchange`; each now
  ships another radius than the refused one, tested). Probe: `p5f_search` grid ixAlphaMax {40, 45, 35,
  30} (6 jobs, 24 calls), `p5f_all` 96 shipped combos.

### 3. Channelized Junction
- **Diagnosis** (every p5_all row and p5_channel_search trial rebuilt offline with its dev values):
  traffic side, islands and arm length never changed a verdict (all 480 / 96 / 4 pairs agree), nor
  near-side vs all-turns slip lanes (336 pairs agree); corner gap and free length changed nothing.
  The kerb-cut lengths do not separate the verdicts (accepted up to 31 m, refused from 15 m). What
  does: lanes per direction of the arm at a slip node, whether the node carries one slip lane or two
  (T: the main road's nodes carry one, the side road's two; X: every node two), and the angle:
  | slip node | 1 lane / dir (town / country small) | 2 lanes (country medium) | 2 lanes (town medium) | 3 lanes (large) |
  |---|---|---|---|---|
  | one slip lane (T main road) | 40 deg | 40 deg | 40 deg | 50 deg (40 refused) |
  | two slip lanes | 40 deg | 50 deg (40 refused) | 50 deg only with side-road splitter islands | nothing up to 50 deg |
  The roundabouts' splitter search (an arm forking into two one-way roads, PLAN.md Phase 4b) shows the
  same: town medium arms needed 65 deg with 2-lane legs (xsmall / small), large arms only placed with
  4-lane legs (one-way medium), at 35-65 deg; country medium took 50 deg. The slip template (one-way
  xsmall) has 2 lanes.
- **Shipped**: tuning table part `channel["layout,main,side,splitter"]` (generator `channel_table`, from
  the grid jobs with the shipped corner gap / free length; narrowest template first, then the smallest
  angle): **39 rows `angle = 50`** (engine-accepted), **81 rows `none`**, no row for the 24 combos
  accepted at 40 deg. `ch.slipRule(spec)` -> angle, template, source; `ch.slipAngle` / `ch.slipRoad`
  (dev `chSlipAngle`, new `chSlip` win); `ch.gore`, the set-backs, the corner islands and the slips
  list use the template's half width. The one-way-bend factor stays `tan(a + 2 deg)` up to 50 deg (the
  layouts the engine judged; above 45 deg it only scales both set-backs up) and is `tan(90 - a + 2)`
  above. **Fallback for `none` rows** (`ch.FALLBACK`, unverified, picked from the splitter analogy):
  by the most lanes per direction of a road with shared slip nodes (T: the side road; X: both):
  2 lanes -> one-way small slip lanes at 65 deg, 3 lanes -> one-way medium (24 m) at 50 deg. Every
  param still does something (no param is dropped). Past 45 deg a slip lane bends slightly towards
  its corner between its two 50 / 65 deg ends (test_channel's turn test now checks the turn at both
  ends and from arm to arm instead of the slip lane's own curvature).
- Replay: p5_all channel **404 / 968 -> 608 / 968** shipping a layout the engine accepted (the 204
  refused combos of the 39 rows now build exactly the accepted 50 deg trial layout: set-backs, legs
  and template compared), **360 combos (81 base rows) ship the fallback**: gap `channel`. Accepted
  combos are unchanged (set-backs compared with the sweep). The default (T, town medium + town small)
  is unchanged (40 deg).
- **Probe** `p5f_search`: the 81 base combos x chSlipAngle {65, 50, 80} x chSlip {2, 3, 1} (9 each,
  the fallback first, 729 calls); `p5f_all`: every layout x main x side x splitter x both slip sets x
  both traffic sides (576). After the run the generator turns accepted candidates into rows (a `none`
  row becomes `{angle, slip}`).

### Probe (`mods/square_roundabouts_probe`, DEV ONLY)
- Dev keys `chSlip` (1-3) and `ixAlphaMax` (20-70 deg) in `geom.DEV_KEYS` and `grid.DEV` /
  `DEV_ORDER` (log fields `devChSlip`, `devIxAlphaMax`); `chSlipAngle` range 20-85 deg.
- Subsets (mod.json values appended, tooltip updated): **`p5f_all`** 1,416 combos (channel 576,
  4-lane two-bridge 96, 2:1 splitter ovals 24, p5_hamburger again 720; ~30-60 s at the 89 combos/s
  p5_all ran at) and **`p5f_search`** 87 jobs / 753 engine calls (~15-40 s). PROBE.md "Phase 5f runs".
- Tests: subset sizes, coverage, candidates (both dev values on every channel candidate), every
  p5f_all combo builds sane geometry (test_geom), the through-axis test now skips every `p5*` subset.

### Tests and checks
- New: test_tuning (through patterns: own cell, floor fallback, source; channel rows: engine / none /
  no row, fallback per lanes), test_interchange (4-lane alpha <= 40 deg, 35 / 45 / 55 m), test_types
  (2:1 splitter ovals split along the ring normal, never forced; round rings never), test_dev
  (`chSlip`, `ixAlphaMax`, dev values win over a tuning row; the channel dev test moved to a combo
  without a row), verdicts `V.channel` / `V.interchange` (+ gap categories `channel`, `interchange`).
- Updated: test_channel (turns, set-backs now depend on the layout only through the engine data),
  test_through (exact engine radii only from the through road's own pattern; engine-judged builds skip
  the offline strip check: the engine accepted e.g. 12 m rings with 4 lanes and country small through;
  0 forced at 60 m now), golden (above).
- `make check` (15 + 10 files, 0 errors), `make test` square_roundabouts 131 passed, probe 46 passed,
  `make validate` OK (probe: the two expected warnings).
- Known gaps now (test_engine_verdicts): channel 360, interchange 30, through 720, cw 71, splitter
  2,446, provisional 400, none 6.

### Handoff
1. **Probe `p5f_all`** (~30-60 s) then **`p5f_search`** (~15-40 s), same map and settings as the
   Phase 5e runs (PROBE.md "Phase 5f runs": Run On, Start delay 15 s, Combos per update 8, Position
   0 / 0, Proposal context None, Log placeable combos On). Copy stdout.txt after each to
   `plans/square_roundabouts/probe_p5f_all.log` / `probe_p5f_search.log` (or parse them:
   `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5f_all.log`, same for the
   search). Then a short tuning pass: `uv run tools/gen_roundabouts_tuning.py` (channel rows from the
   search), `ix.ALPHA_MAX_LANES[3]` from the ixAlphaMax result by hand, `make test` replays both.
2. **In game** (TESTING.md section 15): the 50 deg slip lanes and the fallback slip lanes (looks:
   65 deg lanes bow towards the corner, one-way medium lanes are 24 m wide), the larger 4-lane
   two-bridge rings, a 2:1 oval with 4 lanes / large arms / splitter / Y arms, two hamburger combos.

## Phase 5g notes (2026-10-08)
Bakes in the Phase 5f probe runs: `probe_p5f_all.*` (run 3 of the log: 1,416 / 1,416 placed, so
every 5f layout, including ch.FALLBACK, the 40 deg 4-lane two-bridge rings, the 24 split-normal
ovals and the hamburger sweep, is engine-verified) and `probe_p5f_search.*` (run 4: 87 jobs, every
job found an accepted candidate; 753 calls, 174 rejected). No revision bump (3 is unpublished).

### Tuning decisions
- **Channel** (`uv run tools/gen_roundabouts_tuning.py`, default inputs = Phase 4 + p5 + p5f job
  and sweep files; generator logic unchanged: narrowest slip template first, then the smallest
  accepted angle). Offline set-backs of every p5f_search candidate (main / side slip node distance)
  rank the candidates the same way per template: one-way xsmall < small < medium, and above 50 deg
  a steeper angle sets back less (shorter gore, the bend factor uses 90 - a). Accepted per combo:
  80 deg xsmall 81 / 81, 65 deg small and medium 81 / 81, 65 deg xsmall 52 / 81 (refused on large
  side roads with splitter islands and most 3-lane shared nodes), 50 deg small 17 / 81, 50 deg
  medium 81 / 81, 50 deg xsmall 0 / 81. Result: the 81 `none` rows became **52 rows `angle = 65`**
  and **29 rows `angle = 80`**, all one-way xsmall (no `slip` field); no `none` row is left. Both
  are strictly more compact than the p5f_all-verified fallback they replace: 65 deg xsmall vs 65 deg
  small -1.1 to -1.6 m per set-back (17 combos), vs 50 deg medium -12 to -53 m main / -7 to -19 m
  side (35); 80 deg xsmall vs 50 deg medium -21 to -72 m / -15 to -22 m (29). 80 deg xsmall would
  set back another 2-6 m where 65 deg was accepted; kept 65 deg there (the brief's preference for
  the smaller angle, and a slip lane that still looks like one). The 39 `angle = 50` rows and the 24
  combos without a row (40 deg) are unchanged. ch.FALLBACK stays in the code (only used by a table
  regenerated without p5f_search). Table: 120 channel rows; radius / magic / splitter parts
  byte-identical (only the header's source line names the p5f jobs file).
- **Interchange**: p5f_search accepted ixAlphaMax 30 / 35 / 40 / 45 for all 6 highway x level
  combos (2 lanes per side ring, 15 m slider, town medium cross road, 140 m slip roads, 2020). The
  ring at 45 deg is the smallest: small / medium / large 30 / 45 / 50 m (40 deg: 35 / 45 / 55; 35:
  35 / 50 / 60; 30: 40 / 60 / 70). **`ix.ALPHA_MAX_LANES[3]` = 45 deg** (was 40). The two-bridge
  ring's slip nodes follow from the radius alone (alpha = asin(clearance / radius)), so the cap
  only sets the smallest radius; 1-2 lane rings unchanged. p5_all refused the 4-lane ring at alpha
  52-58 deg, so 45 deg keeps a 7 deg margin. Not tried: 50 deg.

### Replay (`test_engine_verdicts.lua`, verdicts.lua)
- `V.channel`: an accepted sweep row may now ship other set-backs than swept when the shipped
  layout is one an accepted search trial built on that combo (the p5f_all fallback rows replaced by
  the p5f_search winners); otherwise unchanged.
- `V.interchange(geom, ix, sweep, trials)`: a combo is verified when it ships its swept radius
  (accepted row) or a radius an accepted sweep row or search trial of the same key placed (trials
  only with ixAlphaMax as their dev value); shipping a refused radius is a problem; anything else is
  gap `interchange`. New synthetic test. `V.FILES.sweep` and the generator's `--sweep` default gain
  `probe_p5g_verify.csv` (skipped while missing).
- **Gap counts** (before = 5f code with the p5f files loaded / after):
  channel **360 -> 0**, interchange **30 -> 62**, through 720 -> 720, cw 71 -> 71, splitter
  2,446 -> 2,446, provisional 400 -> 400, none 6 -> 6. Interchange grew on purpose: 44 p5f_all
  rows placed at 40 deg now ship a smaller ring no sweep placed (large highway 55 -> 50 m at both
  sliders: 30; small highway 35 -> 30 m at the 15 m slider: 14; the 4 rows on p5f_search's own
  keys are verified), and 18 p5_all refusals ship 30 / 50 m (small / large) or 45 m (medium, town
  large cross road) on keys no accepted row covers (the other 12 are covered by p5f_search or by
  p5f_all's 45 m medium rings). Medium rings did not change (45 m at 40 and 45 deg). With 40 deg
  the gap would have been 6. All 102 swept 4-lane two-bridge keys are in `p5g_verify`; after that
  run the gap should be 0.
- No golden re-recorded: the goldens cover the main / Magic entries only (test_default_unchanged
  passes unchanged).

### Code, tests
- `square_roundabouts_tuning.lua` (generated), `square_roundabouts_interchange.lua`
  (ALPHA_MAX_LANES, comment), `square_roundabouts_channel.lua` (FALLBACK comment only).
- Tests: test_interchange (alpha <= 45 deg with 4 lanes, rings 30 / 45 / 50 m), test_dev (45 deg
  shipped; the dev-wins check now on an `engine` 65 deg row), test_channel ("wider roads, larger
  set-backs" compared at the same slip lanes: a town large side road now gets 65 deg and sets back
  less than a town small one at 40 deg), test_tuning (no `none` row, all xsmall, angles 50 / 65 /
  80), test_engine_verdicts (synthetic interchange replay).
- Probe: subset **`p5g_verify`** (468 combos; mod.json value + tooltip; PROBE.md "Phase 5g runs");
  probe tests: size / keys / coverage (exactly the p5f_search channel bases), sane geometry.
- `description.html`: the Slip lanes setting no longer promises wider slip lanes on wide roads
  ("Wider roads get slip lanes at a steeper angle."); changelog unchanged (the Channelized
  Junction and the interchange are new in revision 3, no revision 3 line describes the slip lane
  template or ring sizes). TESTING.md: walkthrough pointer, section 15 items 2 and 3 rewritten.
- `make check` 15 + 10 files, 0 errors; `make test` square_roundabouts 132 passed, probe 47 passed;
  `make validate` square_roundabouts OK.

### Handoff
1. **Probe `p5g_verify`** is needed (the 65 / 80 deg xsmall slip lanes were placed by p5f_search only
   with near-side slip lanes and right-hand traffic; the 45 deg rings only at one cross road / slip
   length / year). Settings as before: `make link`, flat test map (2020, right-hand traffic),
   Better Roundabouts + DEV Roundabouts Probe; Run On, Subset **p5g_verify**, Start delay 15 s,
   Combos per update 8, Position 0 / 0, Proposal context None, Log placeable combos On. 468 combos,
   **~6-10 s** after the 15 s delay. Copy stdout.txt to `plans/square_roundabouts/probe_p5g_verify.log`,
   parse (`uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5g_verify.log`),
   `make test MOD=mods/square_roundabouts`: gap `interchange` should read 0 and no problem. A refused
   channel combo -> drop its row to the next candidate (80 deg xsmall, accepted 81 / 81); a refused
   ring -> back to 40 deg for that highway. Disable the probe afterwards.
2. **In game**, TESTING.md "Phase 5 walkthrough", then section 15 (15.2: 65 and 80 deg slip lanes,
   do vehicles use the 80 deg ones without crawling; 15.3: 4-lane two-bridge rings 30 / 45 / 50 m,
   both levels and bridge types), plus sections 11-14 as listed in the 5e handoff.

## Phase 5 result (2026-10-08)
- `p5g_verify` (log `probe_p5g_verify.log`): 468/468 placed, 0 fails; `make test` 132 passed with the data replayed.
- User in-game test (TESTING.md Phase 5 walkthrough, sections 11-15): all good.
- Release state: revision 3, ready for upload via Mod Hub. The "Through the centre" slide (published
  3.png) was removed and slides renumbered (now 1-10): before uploading, delete gallery media 3-6 on
  mod.io, otherwise mod.io keeps the old 3-6 and only adds 7-10.
  Never upload `square_roundabouts_probe`.

## Channelized Junction Scale (revision 6, 2026-10-10)
User request: every entry has a size control called Scale, a button row like the Magic Roundabout's
(no slider). Better Roundabouts' and the Roundabout Interchange's Radius rows and the Magic
Roundabout's Size row are renamed Scale (display name and texts only; keys, values and defaults
unchanged, so saved settings and placed roads are unaffected). The Channelized Junction had no size
control and gets one:
- Param `sqrb_ch_scale` (`ch.PARAM_KEYS.scale`), Button row XS / S / M / L / XL (size codes, the same
  in every language), right after Layout, default XS. `ch.SCALES = { 1, 1.25, 1.5, 2, 2.5 }`.
- `ch.setbacks`: after the three minimum rules ("Set-backs" in Phase 5b notes: junction room, one-way
  bend, island room), both set-backs are multiplied by the factor and each rounded up to
  `SETBACK_STEP` (0.5 m). XS skips the step, so it is byte-identical to revision 5 (golden tests
  unchanged). Same proportions, so the one-way bend chord moves by the rounding only (< 0.5 deg,
  tested; CHORD_MARGIN is 2 deg); every node only moves further out, so the splitter rule (side node
  beyond the split node) and island room still hold. Slip angle and template (`ch.slipRule`, the
  engine-tuned table) do not depend on the scale; arm length still runs beyond the slip node.
- Default town medium + town small set-backs (main / side, m): XS 42.2 / 41.4, S 53.0 / 52.0,
  M 63.5 / 62.5, L 84.5 / 83.0, XL 105.5 / 104.0.
- Tests: `test_channel.lua` "Scale S..XL" (every layout x road pair x slips x splitter, Islands Grass:
  set-backs = XS x factor rounded up, tags, edge lengths, engine model, overlaps, islands clear and
  not smaller than at XS, chord, splitter, arm length; mirror, Islands-independent roads and no world
  -0 beyond XS's, per scale); `test_short_edges.lua` channel sweep extended by S-XL;
  `test_menu_labels.lua` every entry's size row is named Scale.
- **Not engine-probed:** only XS is what `p5_all` / `p5f_search` / `p5g_verify` placed. S-XL keep the
  accepted angle and template with longer straight-ish slip lanes, which should only be easier, but
  no probe has run them (TESTING.md 12.11).

