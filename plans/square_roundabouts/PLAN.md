# square_roundabouts: plan

Research and API sources: `research.md` (same folder).

## Goal
A configurable roundabout construction ("Roundabouts") that replaces nothing in the base game.
Placing it stamps a ring, approach arms and optionally a centre island. Like the vanilla
roundabout, it then dissolves into ordinary, editable roads.

## Decisions (user, 2026-10-07)
- **Editable, not reconfigurable.** Every node goes in `freeNodes`, `snapNodes = {}`, no
  `postConstructionModifiable`. The vanilla pattern (`street_constructions.script.lua:632`).
- **Base-game road templates only.** No custom `.street_template.lua` or `.street.lua`. The ring
  uses the vanilla one-way set (`highway_new_small`, `town_new_one_way_small`,
  `town_new_one_way_medium`). Arms use base two-way town/country templates. This rules out a
  3-lane ring.
- modId `square_roundabouts`, display name "Roundabouts".

## Design
- `content/.../roundabouts.con.lua`: params + `updateScript` → a `.script.lua` updateFn.
  Find where a mod's construction lives and how a mod-relative `updateScript.fileName` resolves.
  The base file is at `content/infrastructure/street_construction/`.
- Pure geometry in a separate Lua module, unit-tested offline. It works from params to a list of
  `{edgeList spec}` plus island specs, with no game API. The updateFn only maps that output to
  the result table.
- Ring: a closed Hermite ring with nodes at every arm angle, plus extra nodes so that no edge
  spans more than 90°. Handles use `addEdgeAutoTangents`, or the exact circle handle
  `(4/3)·tan(θ/4)·r` per edge. Ellipse for Oval. Direction CCW (right-hand traffic) or CW.
- Arms: one edgeList per arm street template, radial straight edges from the ring node outwards.
  The arm end node and the ring node share a string tag so they merge. Each arm end is a loose
  free node that the player connects.
- Island (optional): `subconstructions[1]` with a grass/paving `groundFace` and models (trees,
  fountain), plus a collider so that no town buildings spawn on it. Inner radius = ring radius
  minus half the road width minus a margin.
- updateFn is pure: no game API, no network access, and arm angles come from params.

## Params (MVP)
| key | UI | values |
| --- | --- | --- |
| `rbType` | Button | Standard, Mini, Oval |
| `lanes` | Button | 1, 2, 4 (vanilla templates) |
| `radius` | Slider | Standard 15–60 m; Mini maps to a small set (e.g. 8–14 m) |
| `ovalRatio` | Slider | 1.25–2.0 (Oval only; `checkEnabledScript` if it works, otherwise ignored) |
| `arms` | Button | 3 (T), 3 (Y), 4, 5, 6, 0 |
| `armType` | ComboBox | town small/medium/large, country small/medium/large (new era) |
| `armLength` | Slider | 10–60 m |
| `direction` | Button | Anticlockwise (right-hand), Clockwise (left-hand) |
| `island` | IconButton/Button | None, Grass, Grass + trees, Fountain, Paved |
| rotation | `paramsutil.makeRotationParam` if usable, else a `rotation` slider (0–345°) |

Availability from 1940 (the one-way templates exist from 1940). Menu category `street_constructions`.

## Phases
1. **Core build (MVP).** Scaffold, geometry module + tests, con.lua + updateFn, description.html,
   cover, TESTING.md with the in-game checklist (including the spike questions in research.md
   §Phase 0). Done when `make check`, `make test` and `make validate` all pass for the mod.
2. **In-game test** (the user) → fix-ups.
3. **More types:** splitter islands on arms, Dumbbell, Turbo (concentric single-lane one-way
   rings), raised ring on bridges over a through road.
4. **Optional:** a priority-fix game-script tool, only if phase 2 shows that ring traffic yields
   badly.
5. **Interchanges, hamburger, channelized junction, earlier unlock:** see `PHASE5.md`.
6. **Lane connections at ring junctions** (turbo-like lane discipline assigned after placement;
   6a probe, 6b implement, 6c in-game test): see `PHASE6.md`.

## Save safety
Construction only: no game script, no saved state, no base overrides. After placement the result
is ordinary streets (plus the island construction, if the engine keeps one). `severityAdd: None`.
`severityRemove: Warning`, because removing the mod could orphan placed island constructions.
Confirm against `moddefinition.md` when scaffolding.

## Phase 1 notes (2026-10-07)
- Files: `content/infrastructure/street_construction/square_roundabouts.con.lua`, `.script.lua`
  (updateFn + checkEnabled fns, exported via `data()`) and `square_roundabouts_geometry.lua` (pure).
  Unique file names, so nothing shadows a base file at the same relative path. `updateScript`
  uses the relative form `square_roundabouts.script@updateFn` (as the base roundabout and the
  official mission_07 park); `checkEnabledScript` uses `square_roundabouts::/…script@fn`
  (format confirmed by base `assetbuilderutil.lua`, which returns "Enabled"/"Hidden"). Revision 1 fix: ours return only "Enabled"/"Disabled", because "Hidden" breaks the info panel of hovered base constructions (base `construction.tl` ~1519 vs ~1588).
- Base resources from a mod need `::/` (a bare `/…` is absolute in the *mod*,
  `resourcetypes.md:84-88`), so every template, model and gtex path is `::/…`.
- Param keys are prefixed `sqrb_` (wiki tip against foreign preselected values). Radius is split
  into `sqrb_radius` (15–60) and `sqrb_mini_radius` (8/10/12/14) with checkEnabledScript.
- Handle: the Hermite tangent is `4·tan(θ/4)·r` (= 3 × the Bézier control distance
  `(4/3)·tan(θ/4)·r`; vanilla's `r·4·(√2−1)` at θ = 90°). Ellipse edges use the affine image:
  `4·tan(Δt/4)·(−a sin t, b cos t)`.
- No rotation param: `makeRotationParam` is for X/Y tilt (`constructOpt56/78`); Z rotation is
  the construction builder's own `constructOpt1/2` (`gui/main/internal.css.lua:1016-1017`).
- Arm length is measured from the ring's outer road edge (the edge starts on the ring centreline
  node it shares a tag with).
- Island: `subconstructions[1]` (tag 1) only when an island is chosen; with no island the result
  is the base roundabout's shape (`models = {}`, `groundFaces = {}`). The outline is the true
  inner offset of the centreline (half road width + 1 m); the collider is an ellipse shrunk to fit
  inside it; `terrainAlignmentLists = {{type = "EQUAL", faces = {}}}` (no terrain change, as base
  assetbuilderutil with alignment off). Mini turns Trees/Fountain into Paved.
- Menu icon: placeholder, the base roundabout's `::/infrastructure/street_construction/roundabout.tga`.
- Cost 0 like vanilla; whether street costs are charged is a test item.

## Phase 2a notes (2026-10-07, after the first in-game test)
User feedback: everything works, except: (1) island default should be None, (2) toggling Type
did not update the greyed-out params until the menu was reopened, (3) rename, (4) own menu icon.

- **Display name "Better Roundabouts"** (con `description.name`, modinfo, description.html,
  `branding/mods.js`, cover re-rendered). modId and file names unchanged (`square_roundabouts`).
- **Centre island defaults to None** (`defaultIndex = 1`; `readParams` fallback `ISLAND_NONE`).
- **checkEnabledScript removed; params restructured.** Root cause of the stale greyed-out state,
  from base `gui/construction/construction.tl`:
  - Evaluation is fine: `changeParam` (1866) stores the new value in `refCurrentParams` and then
    calls `updateDisabledParams` (1890), which runs every param's `checkEnabledFn` on
    `getAllParams()` (1584-1597; values come from `refCurrentParams` via `getCurrentValues`), and
    the heartbeat `onStep` calls it again (1922). If the result changed it toggles
    `disabledParamsState` to re-render.
  - Rendering is where it breaks: a "Disabled" result only flips `meta.enabled` on the existing
    `ConstructionParam` recipe child (2054-2061); that child's own params (`refParams`, `index`,
    `bottomBar`, `gameContext`) never change, so the existing node is kept and the new enabled
    state shows only when the window is rebuilt (menu reopened). "Hidden" works live because it
    adds/removes children (2055; also 1363-1368), which is why the only base construction that
    uses `checkEnabledScript` (`scripts/construction/assetbuilderutil.script.lua:29-31`) returns
    "Hidden". "Disabled" in base is used only by the built-in street/builder toolbar params
    (`construction_react_util.tl` 891, 1855, ...), not by any construction definition. The engine
    side of the reconciliation is not visible in script; this is inferred from the code plus the
    test result. "Hidden" is off limits (it breaks hovered base constructions, Phase 1 notes), and
    no definition- or param-level field forces a rebuild (`ScriptParam` in
    `api/tealdef/api/type.d.tl` ~2960-3000 has nothing of the kind), so there is no fix on our side.
  - Alternative chosen: no conditional params at all. Type (Standard/Mini/Oval) + Radius +
    Mini radius + Oval stretch became **Shape** (Slider: Round, Oval 1.25/1.50/1.75/2.00 : 1) and
    one **Radius** (Slider: 8, 10, 12, 15, 20 ... 60 m). "Mini" is now just a radius below 15 m
    (`geom.MINI_RADIUS_BELOW`): the island stays flat (trees/fountain become paving), as before.
    For an oval the radius is the narrow side (unchanged maths: b = radius, a = radius × ratio).
    Arm road / Arm length stay active with Arms = None (they simply have no effect).
    Keys: `sqrb_type`, `sqrb_mini_radius`, `sqrb_oval_ratio` → `sqrb_shape` (unpublished, so no
    saved-params compatibility to keep). Phase 3 types can extend the Shape list as long as every
    param stays meaningful for them, or use separate menu entries.
- **Own menu icon**: `content/infrastructure/street_construction/square_roundabouts@2x.tga`,
  referenced relatively as `icon = "square_roundabouts.tga"` (as base `roundabout.tga` →
  `roundabout@2x.tga` in base `infrastructure/street_construction.zip`). Format copied from the
  base icon: 240×150, uncompressed 32-bit BGRA TGA, bottom-left origin, transparent background
  (`docs/wiki/modding/constructions/basics.md:52`). Look: oval ring, green island with trees,
  beige sidewalks, T layout, base asphalt palette. Regenerate with
  `uv run tools/render_icon_square_roundabouts.py [--png preview.png]` (Pillow, seeded, byte-for-byte
  reproducible). `previewIcon` (720×405 hover image, `basics.md:53`) is still the base
  roundabout's; replace it with an in-game capture later (24-bit TGA, 720×405, as
  `roundabout_preview@2x.tga`).

## Phase 3 notes (2026-10-07, new types)
Design input: `types.md`. Still base templates only, every node freed, pure updateFn, no
checkEnabledScript anywhere.

### Files
- `square_roundabouts_shapes.lua` (new): pure vector, Hermite, ellipse and polygon helpers
  (clip, box fit, point-in-polygon with clearance, polyline intersection).
- `square_roundabouts_geometry.lua`: ring planning (`plan`/`choosePlan`), arms incl. the through
  axis (`armsFor`), splitter legs, through road, tram/signal flags, islands. Output is now a list
  of edge lists (`built.lists`, roles `ring`/`arms`/`legs`/`through`, one per template) and an
  island `{faces = {{outline, fill, stroke}}, colliders = {{type, x, y, rot, hx, hy, hz}}, models}`;
  `built.ring` and `built.arms` stay as views for the Phase 1 tests.
- `square_roundabouts_result.lua` (new): maps any geometry result to the construction result
  (shared by both menu entries). `square_roundabouts.script.lua` is now three lines.
- `square_roundabouts_magic.lua`, `square_roundabouts_magic.con.lua`,
  `square_roundabouts_magic.script.lua`, `square_roundabouts_magic@2x.tga` (new menu entry).
- Tests: `tests/square_roundabouts/test_types.lua`, `test_magic.lua`, shared `checks.lua`
  (tags, edge lengths, footprint overlaps, island clearance).

### Main entry params (in UI order)
Shape, Ring lanes, Radius, Arms, **Splitter islands** (`sqrb_splitter` Off/On), **Through the
centre** (`sqrb_centre` Nothing/Road/Tram line), Arm road, Arm length, **Tram tracks**
(`sqrb_tram` Off/On), Direction, Centre island, **Traffic lights** (`sqrb_signals` Off/Entries
(experimental)). Defaults: all new ones off, so the default build is unchanged.

### Ring growth rule (one rule for all new features)
The radius slider is a minimum. `choosePlan` uses the chosen radius, or the smallest larger slider
radius at which the ring fits; without splitter or through road every config fits at its own
radius (tested over every shape/lanes/layout/radius/arm road), so Phase 2 behaviour is unchanged.
Fit (`geom.plan`):
- every ring edge chord >= 10 m;
- each splitter arm: both leg nodes exist (lateral offset leg half width + 6 m reachable) and are
  ring neighbours; each leg meets the ring within 60 deg of its normal and so steeply that its
  square end stays inside the ring road (asin(ring hw / leg hw)), driving with the circulation;
- leg node next to another arm's node: chord >= sum of half widths + 2 m;
- through road: every ring node off its axis is >= through hw + widest road at that node + 2 m
  from the through road.
A ring that grows from below 15 m stops being "mini" (trees allowed). Example: 4 arms at 20 m keep
20 m with splitters; 5 arms grow to 30 m, 6 arms to 35 m (2 lanes); an 8 m ring with splitters
grows to 20 m (2 lanes) or 25 m (1 lane); a road through an 8 m, 4-arm ring grows to 10 m.
If nothing fits up to 60 m, a forced plan is built (never happens for the shipped params; tested).
Rejected alternative: falling back to "no splitter" on small rings would make the param do nothing
for those values.

### Splitter islands
Per arm (not the through-axis arms): split node S on the arm axis 26 m beyond the ring's outer
edge; exit node X and entry node E on the ring where the ring is leg hw + 6 m off the axis
(entry on the right of an inbound driver: angle phi + delta for anticlockwise, phi - delta for
clockwise). One-way legs X->S and S->E (`town_new_one_way_xsmall`, 14 m; with tram tracks
`town_new_one_way_small_tram_electrified`, 16 m), forking at +-40 deg at S and reaching the ring
nearly parallel to the ring normal at the arm (5 deg towards the traffic). The two-way arm runs
from S and reaches max(arm length, 26 + 10 m) beyond the ring's outer edge. Legs were tuned
numerically for a clear triangle at every radius (about 27-30 m^2, base about 6 m).
Triangle island: between the legs' inner kerbs (+1 m) and the ring's outer kerb (+1.5 m), only
when Centre island is not None, same surface as the centre (trees -> grass, fountain -> paving),
no collider and no models (too small; no town building fits). Decision: "Centre island = None"
means no landscaping at all, as in the base roundabout.
Through-axis arms never get legs: the through road must meet the arm at a single ring node.

### Through the centre (road or tram line)
Axis = the first opposite pair of the layout (T, 4, 6: east-west). A layout without an opposite
pair gets one extra arm opposite its first arm (Y and 5: an arm due south, through road
north-south); Arms None gets two arms east and west. So the param always builds a usable through
route. One straight two-way edge between the two axis ring nodes (each then has 4 edges): Road =
the arm road (tram variant with Tram tracks on), Tram line = `tram/tram_new` (11 m). Island:
the inner outline is clipped into two halves beside a strip of through hw + 1 m; each half gets a
BOX collider (largest box by sampling, sides along the axis) and its own centre tree/fountain if
it fits; bushes only where they keep clear of the half's edge. Halves under 8 m^2 are dropped.

### Tram
Tram tracks On: ring, every arm, legs and a through road use tram-capable templates; Tram line
through (tracks Off): ring + the two axis arms only (so the tram can turn onto the ring as well as
cross). Templates: `town_new_one_way_{small,medium}_tram_electrified` (2/4-lane ring),
`town_new_{small,medium,large}_tram_electrified` (town arms). No base tram variant exists for the
1-lane ring (`highway_new_small`) or country roads: same template plus edgeList
`params.tramTrackType = "ELECTRIC"` (documented in basics.md "Edge Lists", used by base
`tram_depot.script.lua:183` and `modular_street_station/modules.script.lua:110`). Unverified for
a highway/country template: TESTING.md "Tram".

### Signals (experimental)
On the ring edgeList, at each arm's entry node (E with splitter, else the arm node): odd arms via
`trafficLightYes = {node indices}` (tealdef `construction_util_serialized.d.tl:150`), even arms
via `trafficLightNodePreference = {{index, "YES"}}` (wiki `basics.md:690`). Both entries of the
merged node are listed. TESTING.md tells which arms to look at; remove the dead field afterwards
(or the whole param if neither works). Lights exist from 1950; before that nothing is expected.

### Magic Roundabout (own menu entry)
Separate `.con.lua` because none of the ring params (shape, lanes, radius, arms, splitter,
centre, tram) applies. Params: Arm road, Arm length, Direction, Centre island (same keys as the
main entry). Geometry: 5 satellites (1-lane ring, `highway_new_small`, radius 12 m -> centreline
17 m) with centres on a circle of 52 m, joined by two-way `town_new_small` arcs of that circle;
one arm per satellite. Deviation from types.md: no separate one-way central ring with one-way
in/out pairs. Swindon has none either: the links are two-way, so the inner lane of the central
ring runs against the satellites (contraflow) and the outer lane with them; a separate ring would
duplicate that path, add ten junctions and push the footprint to ~200 m. Footprint now about
150 m + 2 x arm length. Islands: a centre island inside the link ring, dented around the
satellites (star outline, cylinder collider, trees/fountain allowed), plus a flat island per
satellite (mini rule). Overlap tests pass for every arm road, length and direction.
Icon: `tools/render_icon_square_roundabouts.py` now writes both icons.

### Turbo: deferred
A turbo roundabout needs lane-level separation inside the ring (spiral lane dividers, lanes that
must not change). With base templates the only way is separate single-lane one-way rings with
tag-merged spiral offsets >= 9 m apart: at every entry a node must split into inner and outer
edges, giving 3-4 nodes per arm, ring edges well under 10 m on anything but very large rings, and
junctions that AI vehicles treat as plain merges (no lane discipline, so no capacity gain, the
point of a turbo). It would not be recognisable from above either (wide gaps between parallel
rings instead of painted dividers). Revisit only with a custom template (excluded by the base-
templates decision) or if Phase 3's splitter legs show the engine handles such short merges well.

### Every param meaningful (no checkEnabledScript)
Splitter, Through and Tram change the build for every shape, lanes, radius and layout; with
Arms None, Splitter islands and Traffic lights have no effect unless a through road adds arms
(same accepted precedent as Arm road / Arm length with Arms None, Phase 2a).

## Phase 3 fixes (2026-10-07, in-game test)
- Tooltips wrapped with `\n` (base tooltips use it, `gui/main/cargo_react_util.tl:147`), lines ≤ ~60 chars.
- Crash with "Tram line" through the centre: `transition_util.cpp:128 CompCurveHandleDistance`,
  "Assertion (angle)>=0, -nan" after many "transition not valid … StreetGeometry::Crossing". The
  offline result was finite; the only difference from "Road" was `tram_new` joining the ring node
  (tram ring + tram arm + tram-only edge). Fix: 12 m stubs (beyond the ring half width) of
  `town_new_small_tram_electrified` join the ring; `tram_new` runs between them (straight
  2-edge nodes). Short axes use the stub road all the way. Regression: `test_finite.lua`.
- Through road clearance now also samples the ring between nodes (flat oval sides ran inside the
  through strip); the ring grows instead.

## Phase 3b notes (2026-10-07, second in-game test)
In-game findings: (1) "Through the centre = Tram line" and "Road + Tram tracks On" fail with
"Construction not possible" and many "transition not valid ... StreetGeometry::Crossing"; road
through without trams works. (2) Remove Arm length; Size matters. (3) Magic Roundabout with
Town/Country large arms always fails; small and medium work. (4) Splitter islands fail with large
arms. The large-arm failures logged nothing in stdout.txt.

### Tram
- Tram line through the centre puts tracks only on the straight axis (axis arms, 16 m town tram
  stubs, `tram_new` between them); the ring stays plain (`ringTram = spec.tram == TRAM_ON`, main
  session). Hypothesis: tram turning transitions onto the tight one-way ring are rejected.
- Tram tracks On (tram on the ring) is likely not placeable: the param stays, marked experimental
  in its tooltip and value ("On (experimental)"); TESTING.md 9.2 decides its fate.
- Tram stubs grew from 12 to 16 m beyond the ring half width: on a tight oval end (1 lane, 8 m,
  2:1) the ring junction took 12.1 m of the 16.5 m stub.

### Root cause of (3) and (4): junctions that eat whole edges
The engine shapes a junction from the kerbs of neighbouring roads; scripts can't see it. Offline
model (`tests/square_roundabouts/checks.lua` `checks.junctions`): at every node, sort the roads
by angle; each neighbouring pair meets at a kerb corner, the crossing of their facing kerbs (each
kerb is the road's offset curve, extended straight behind the node). Each road is cut back to its
farthest corner; free length = edge length minus the cut-backs at both ends. "Behind" = how far a
corner lies behind a road's own node (a narrow road running along the extended kerb of a much
wider one). Results for the old layouts (default params):

| case | in game | free length (worst edge) | corner behind node |
| --- | --- | --- | --- |
| Magic, town small / country small | works | 8.3 / 8.6 m (mini ring edge next to the arm) | 0 |
| Magic, town medium / country medium | works | 4.7 / 5.6 m | 0 |
| Magic, town large / country large | fails | **0.5 / 1.6 m** | 2.6 / 1.6 m |
| Splitter, small / medium arms | works | 6.8 m (ring), legs 15.6 m | 0 / 5.7 m (town medium) |
| Splitter, town large / country large | fails | ring 6.8 m, legs 7.3 / 10.1 m | **15.6 / 12.7 m** |

- Magic: a 1-lane mini ring (centreline 17 m, outer kerb 21.5 m) with the arm node at 0 deg and the
  link nodes at about +-99 deg had its in-between nodes at +-49.7 deg: 14.7 m edges next to the arm.
  A 32 m arm's kerb line (lateral 16 m) meets the mini's outer kerb at asin(16 / 21.5) = 48 deg:
  14.3 m of the 14.7 m edge are junction. Country large (30 m): 44 deg, 13.1 m. Medium (24 m):
  34 deg, 10.1 m, leaving 4.7 m.
- Splitter: the legs left the split node at +-40 deg. A 32 m arm's kerb line meets the legs' outer
  kerbs 15.6 m behind the split node (the leg runs alongside the arm's extended kerb), and the
  legs lose 20.1 m (country large 17.3 m) to that junction, against 11.9 m for small and medium.
  Also the arm beyond the split was only 10 m long (default arm length 20 m: max(20, 36) - 26).
- Calibration: free length >= `geom.JUNCTION_FREE` = 4.5 m (just below the smallest working
  value, 4.7 m; failures at <= 1.6 m) and corner behind <= `checks.BEHIND_MAX` = 6 m (works at
  5.7 m, fails at >= 12.7 m). Together these classify every in-game result; test_junctions.lua
  "calibration" replays the old layouts to keep the model honest. The real engine rule is
  unknown; both thresholds are a fit to five data points, so TESTING.md 9 re-checks the tightest
  shipped cases.

### Fixes
- **No Arm length param** (`sqrb_arm_length` gone from both entries): arms are `geom.ARM_LENGTH`
  = 30 m beyond the ring's outer road edge, beyond the split node with splitter islands, and
  beyond the mini's outer edge on the Magic Roundabout. 30 m is the old default range's middle
  and gives the splitter arm 30 m instead of 10 m.
- **Width-aware splitter** (`geom.legShape`): for arms wider than medium (half width above
  `LEG_WIDE_FROM` = 12 m) the fork grows by 8 deg and the leg spread at the ring by 1.25 m per
  metre: town large +-72 deg / 11 m, country large +-64 deg / 9.75 m. Small and medium keep the
  tested 40 deg / 6 m. Worst corner behind node: 4.6 m (town large), 4.9 m (country large); the
  ring grows (4 arms at 20 m: 30 m for town large, 25 m for country large). Rejected: a narrower
  transition road between the arm and the split (changes the chosen road type).
- **Junction room in the ring plan** (`geom.plan` -> `geom.ringFree`, `geom.kerbCut`): every ring
  edge must keep `geom.JUNCTION_PLAN` = 5 m (a margin over the 4.5 m test threshold) outside the
  junctions at its ends, for every arm, leg (using its real curve) and through road. The cut is
  where the ring's kerb crosses the facing kerb of the road (signed, so a leg crossing the ring
  obliquely on a tight oval end counts the whole way across). Plus: the nearer start corners of
  neighbouring roads keep LEG_CLEARANCE from each other's band (wide plain arms on small rings
  overlapped each other, the Phase 1/2 test exemption `legacySkip` is gone). The ring grows as
  before (radius slider = minimum). This now also applies without splitter/through road: wide
  arms on small rings grow (e.g. 8 m, 1 lane, 4 arms: town medium -> 12 m, 3 (T) town large -> 20 m); small town
  arms on a 2-lane ring from 15 m never grow (tested). Analytic plan vs full model: equal to
  0.01 m on the cases compared.
- **Plain arms leave along the ring normal** (`geom.armDir`; radial on a round ring, so round
  layouts are unchanged). Radial arms on a 2:1 oval's flank met the ring up to 35 deg off square
  and a large arm's kerb corner lay 7-9 m behind its node at any ring size. Splitter arms stay
  radial (the split node and fork were tuned and tested that way; the normal broke the leg fit on
  long ovals).
- More plan rules from the full sweep: no kerb corner more than `BEHIND_PLAN` = 5 m behind a
  road's node; a leg is out of the ring road's band beyond `LEG_HUG` = 28 m along it; the through
  road's strip check allows a junction of max(25 m, through hw + ring hw + 4 m) (a 6-lane road
  through a 4-lane ring could never meet 25 m); the ring may grow past the slider to
  `GROW_RADII` = 70 / 80 / 90 / 100 m (103 of 6480 swept combinations at the 8 m start, mostly
  wide arms with splitters on 5-6 arms or long ovals).
- Split node in the plan too (`geom.splitBehind`): the wide arm's kerb corner at the split node
  may lie at most BEHIND_PLAN = 5.8 m behind it (town medium's tested 5.7 m passes). On small or
  long oval rings the legs bend to reach the ring's flank and the corner moves back; if no radius
  fits, the fork opens by 8 deg (max 80 deg) and the legs spread 2 m further per step (up to 4
  steps, `forkBump`; 198 of 6480 combinations, never the default 20 m / 4 arms for any road).
  That is the "nearest working layout" mapping: the splitter param still builds splitters, just
  wider ones. No combination falls back to a forced plan any more (tested over every arm road,
  layout, lanes, 3 shapes, tram, centre, splitter; before Phase 3b only Town small was tested and
  169 wide-arm combinations were forced).
- Cost: a splitter build takes about 10 ms offline (25 ms for the worst: 8 m start, 6 large arms),
  plain builds 0.3 ms, Magic 0.1 ms.
- **Magic Roundabout: Size param** (`sqrb_magic_size`, slider, 5 steps, default 3 = the old
  layout): mini radius 8 / 10 / 12 / 15 / 20 m, centre distance 40 / 46 / 52 / 61 / 76 m (about
  3 x the mini's centreline radius). Minis from 15 m are no longer "mini": trees/fountain allowed
  on their islands. The in-between nodes next to the arm are placed so both edges keep the same
  free length (the arm side loses more), within MIN_EDGE .. 90 deg. Growth rule as the main ring:
  the chosen size is a minimum; `magic.layout` rejects a size if a mini edge or link keeps less
  than JUNCTION_PLAN, or neighbouring arms come closer than LEG_CLEARANCE. Result: town large
  needs Size 4 (Compact..Medium build Large), town medium and country medium need Size 2, country
  large fits Size 3 (5.1 m free), small arms fit every size.
- Main entry: the Radius tooltip now says it is the size and that the ring grows to fit.

### New offline checks (tests/square_roundabouts/test_junctions.lua)
- `checks.junctionRoom(lists, JUNCTION_FREE)`: free length per edge and corner-behind per road,
  over every Magic size x arm road x direction, splitter x every arm road x layouts x lanes x
  radii x shapes, plain/through/tram-line x every arm road.
- Calibration test: the old Magic and splitter layouts fail exactly for town/country large.
- Every combination fits without the forced fallback (sweep).
- Overlap checks allow a junction stretch of max(30 m, 1.2 x the sum of the half widths), now
  include town large and run without exemptions; Magic sizes grow only as far
  as needed (every smaller size rejected).

## Branding (2026-10-07, revision 1)
- Hover previews: `square_roundabouts_preview@2x.tga` and `square_roundabouts_magic_preview@2x.tga`
  (720x405, uncompressed 24-bit, bottom-left origin, TGA 2.0 footer: same header as base
  `roundabout_preview@2x.tga`), referenced as `previewIcon = "<name>_preview.tga"`. 16:9 crops of
  `shots/01-overview.jpg` and `shots/03-magic-closeup.jpg`; regenerate with
  `uv run tools/render_preview_square_roundabouts.py [--png DIR]`.
- Gallery: 4 slides in `branding/shots.js` (unpublished, so numbering is still free).
- Cover: Magic Roundabout pictogram, tagline "Round, oval or Magic Roundabout".

## Phase 4 notes (2026-10-07, engine-tuned geometry: mechanism, no data baked yet)
Engine sweep (`probe_results.md`, 10,644 combos via makeProposalData; only "Construction Not
Possible" / "Collision", updateFn always fine): splitter + medium/large arms 100% fail at every
radius; Magic town large only at vlarge, country large from large; tram line fails often at
8-20 m, fine at 40-60 m; ~10% scattered fails without splitter/tram line, not monotonic in the
radius (1-lane rings fail at 40 m, not at 20 m); Tram tracks On no worse than Off. Goal: tune the
geometry against the engine instead of the offline junction model.

- **Tram tracks no longer experimental**: tooltip and value ("On"), description.html, TESTING.md 7.3/9.2.
- **Dev overrides** (`geom.readDev`, `geom.DEV_KEYS`, ranges `geom.DEV_RANGES`): `sqrb_dev_*`
  params read only when present, never in a .con.lua. Exact ring radius (`geom.devPlan`: no
  growth, no floor, forced plan if the offline model rejects it; `built.offline`), Magic size /
  satellite radius / spacing (`magic.devLayout`), splitter split distance / fork / spread / leg
  template (`geom.DEV_LEGS`: one-way xsmall, small, medium + tram variants) / neck (a two-way
  piece of the family's small road between the arm and the split node, role "neck"), tram stub.
- **Splitter parameters in one place**: `geom.splitParams(spec)` = shipped defaults, then the
  tuning rule, then the dev overrides (plan, legEdges, build and the triangle islands all use it).
  With a neck the split-node junction check uses the neck's width.
- **Tuning table** `square_roundabouts_tuning.lua`, generated by `tools/gen_roundabouts_tuning.py`
  from `probe_search.csv` / `probe_search_trials.csv` (parse_probe.py). Currently **neutral**
  (`--empty`). `geom.radiusFloor` (per pattern "shape,lanes,arms,splitter,centre,armType,tram,
  direction" and probed slider radius: the floor `choosePlan` starts from, still subject to
  `geom.plan`), `magic.sizeFloor`, `geom.splitterRule` ("arm,lanes" before "arm").
- **Default unchanged, proven**: `tests/square_roundabouts/golden_default.lua` holds fingerprints
  of 53 groups (2,592 main + 60 Magic builds, every feature) written from the Phase 3b code before
  any Phase 4 change; `test_default_unchanged.lua` compares. New tests: `test_dev.lua`,
  `test_tuning.lua`, `test_engine_verdicts.lua` (+ `verdicts.lua`: replays engine verdicts once the
  table has data; skips while neutral; synthetic tests keep the replay honest).
- **Probe search subsets** (PROBE.md "Search runs"): radius (linear, early exit), Magic size /
  spacing, splitter grid (108 candidates, most compact first), tram stub, CW tram line; T/S log
  lines; dev override check at the start; degenerate geometry never sent.

## Phase 4b notes (2026-10-07, engine data baked in)
Input: the full `search` run (`probe_search.md/.csv`, `probe_search_trials.csv`: 7,066 jobs,
22,504 engine calls) and the Phase 3b `all` sweep (`probe_results.csv`, 10,644 combos).
`square_roundabouts_tuning.lua` (version 2) is generated from them by `tools/gen_roundabouts_tuning.py`.

### Engine radius (`radius` part, `geom.radiusFloor` / `geom.engineRadius` / `geom.choosePlan`)
- Cell `radius[pattern][r0]` = the smallest radius the engine accepted searching from slider
  radius r0 (every slider radius in between was tried and rejected). It applies to sliders from
  r0 up to that radius, and the ring is built at **exactly** that radius, even where the offline
  model rejects it (`built.engine = "radius"`, `built.offline = false`): the layout is identical to
  the one the probe sent (test_tuning "shipped table"). 0 = the offline growth rule.
- Written (generator) where the engine needs more than shipped (509 jobs), where the sweep
  rejected the shipped radius and the search accepted a smaller one (108 jobs: e.g. 1 lane, 8 m,
  T, tram line, town large: 25 m rejected, 20 m accepted), and always for splitter-rule patterns
  (search_radius_split, pending). Not written where the engine accepted the shipped radius or a
  smaller one (6,292 jobs): rings are not shrunk (safety first; the sweep verified them).
- Arms None with splitter islands builds no legs: it uses the splitter-off pattern
  (`geom.patternKey`).
- Clockwise was only searched for the tram line; its 288 minima equal the anticlockwise ones, so
  the 330 unsearched clockwise patterns copy the anticlockwise cells (`inferred`): there they are a
  floor the offline model must accept (else the ring grows on), not an exact radius.
- Not monotonic and not explained by any junction rule: 1-lane round rings with Y or 6 arms fail
  at 40 m for every arm road (45 m works), 2/4-lane rings with 5 arms at 60 m (65 m), 2:1 ovals
  with Y arms at 20/40/60 m. Only the engine table handles these; unprobed slider radii (10-15,
  25-35, 45-55 m) keep the offline growth.
- Known gap: 2:1 oval, 4 lanes, 6 arms, splitter, town small from 60 m (3 jobs: through none,
  road, tram): nothing accepted up to 120 m (40 m works from 40 m, but the slider is a minimum).

### Splitter rules (`splitter` part, `geom.splitParams` / `geom.splitFloor`)
Per arm road one parameter set for every ring, chosen by the generator from the full 108-candidate
grid (score: looks, plus 0.5 per metre the ring grows over the most compact accepted set; a set
that fails where another works scores +100):

| arm road | split | fork | spread | legs | floor 1 lane | floor 2 lanes | floor 4 lanes |
|---|---|---|---|---|---|---|---|
| town medium | 20 m | 65 deg | 6 m | one-way small | 40 m (all) | 20 m (T, Y, 4), 40 m (5, 6) | 20 m (T, Y, 4), 40 m (5, 6) |
| country medium | 20 m | 50 deg | 6 m | one-way small | 40 m (all) | 20 m (T, Y, 4), 40 m (5, 6) | 20 m (T, Y, 4), 40 m (5, 6) |
| town / country large | 32 m | 50 deg | 6 m | one-way medium | 40 m (T, Y, 4), 60 m* (5, 6) | 40 m (T, Y, 4), 60 m* (5, 6) | 40 m (all) |

- Town medium needs 65 deg: nothing with a 50 deg fork and no neck placed on 2-lane rings at 20 m
  (country medium, 1 m narrower, does). Necks (a small two-way piece before the split) work for
  medium arms but change the road type, so they score last; with large arms they never placed.
- Each set was accepted at its floor and every probed radius above it, for every probed layout
  (T, 4, 6 on round rings, 20 and 40 m; 2:1 oval 2 lanes 4 arms at 30 m). Y takes the T floor and
  5 arms the 6-arm floor. `verified` lists the layouts the engine accepted: there (round, no
  through road, no tram tracks, anticlockwise) the floor is exact even where the offline model
  objects; elsewhere it is a floor the offline model must accept (`built.engine = "floor"`, or the
  ring grows on).
- *Large arms with 5-6 arms on 1-2 lane rings: nothing placed at 40 m (4 lanes did). Floor 60 m is
  **provisional** (unverified) until search_radius_split finds the real radius. Rejected
  alternative: dropping the splitter on those arms (the param would do nothing there).
- Small arms keep the Phase 3 splitter (xsmall legs, 40 deg), which the engine accepts.

### Tram line (`geom.TRAM_MIDDLE_MIN`)
search_tram (240 calls) follows one rule: with 16 m stubs (or longer) the tram-only middle places
from 21 m and never at 10-20 m; the tram road all the way always places; shorter stubs never place
with a middle. So the stub stays 16 m (`TRAM_STUB`) and the middle is built only from 21 m
(was `MIN_EDGE` = 10 m); shorter axes get the tram road all the way. This only changes layouts
the engine rejected (49 of the golden builds). Radius cells for tram patterns were searched with
the old rule; at their radius the layout is unchanged (test_engine_verdicts compares).

### Magic
Size floors (search_magic): town large only at Very large (5), country large from Large (4);
other roads accept every size. The engine also accepts smaller sizes than shipped for medium arms
(Compact): not shrunk. Spacings (magic_spacing): the shipped spacing is above the engine minimum at
every satellite radius (e.g. 52 m vs 40 m at 12 m satellites): unchanged.

### Offline model retuned (`tests/square_roundabouts/checks.lua` `checks.engineModel`)
Replayed every engine verdict offline (`test_replay_report.lua`, 32,704 calls: trials as the probe
built them, the sweep with the Phase 3b geometry) and fitted thresholds:

| offline model | agrees | model ok, engine rejects | model rejects, engine ok |
|---|---|---|---|
| geom.plan (shipping plan) | 74.9% | 5,958 | 2,257 |
| Phase 3b test model (free 4.5 m, behind 6 m) | 71.9% | 8,385 | 804 |
| engine-fitted model (Phase 4b) | 91.7% | 2,678 | 26 |

Engine-fitted: free length >= 2.5 m (engine took 2.0 m), plain arm kerb corner <= 1 m behind its
node (legs 6 m), tram stub >= 16 m and middle >= 21 m, neck at most 4.5 m narrower than the arm
and legs at most 2.5 m wider than the neck. The remaining disagreements are mostly the
ring-level failures above (not junction geometry) and splitter fork/spread combos.
- Tests on shipped builds use the engine-fitted model (test_junctions `room`, overlaps in
  test_junctions / test_types), except builds the engine judges (`verdicts.lua` `V.judge`: an exact
  engine radius, a radius the engine accepted for the pattern, or a pending engine floor). In the
  test sweeps every other shipped build passes it.
- `geom.plan` (shipping) is unchanged on purpose: its growth still decides the unprobed slider
  radii, and changing it would also move probed radii away from the verified layouts.
- test_engine_verdicts: every rejected combo of the searches and the sweep now ships the layout
  the engine accepted (radius and rule, compared as built), or falls in a documented gap
  (`verdicts.lua` `V.GAPS`): splitter rule on unprobed layouts / shapes / through road / tram /
  clockwise (pending search_radius_split), provisional floors, clockwise copied from
  anticlockwise, nothing accepted up to 120 m. A sample of 883 trials checks the fitted model
  (>= 88% agreement, <= 1% false alarms).
- Of the 3,628 combos the Phase 3b sweep rejected, 752 now ship exactly a layout the engine
  accepted; the rest are gaps: 2,446 splitter rule on a layout the splitter search did not probe and
  396 provisional floors (both pending search_radius_split), 31 clockwise (anticlockwise radius
  used), 3 nothing accepted up to 120 m. All 512 shipped radii the radius search saw rejected now
  ship the found radius (3 none found). An unverified floor the offline model rejects at every
  radius (36 combos in the test sweep: large-arm rules on 2:1 ovals) is built at the floor for the
  engine to judge, instead of the forced 60 m fallback.

### Default behaviour
Without engine data (neutral table) the geometry is the Phase 3b one except the tram middle rule.
Golden fingerprints re-recorded on purpose (`golden_default.lua`): of 3,888 main builds 1,181
change (972 splitter rule for medium/large arms, 144 larger engine radius incl. 59 inferred
clockwise, 16 smaller engine radius where the shipped one was rejected, 49 tram middle), 37 of 48
groups; Magic 14 of 60 (large arms). The default build (Round, 2 lanes, 20 m, 4 town small arms)
is unchanged.
