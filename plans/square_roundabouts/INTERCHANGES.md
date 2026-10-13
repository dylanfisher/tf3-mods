# square_roundabouts Phase 7: Highway Interchange (parclo, diamond and later types)

Status: done 2026-10-09 (Phase 7a-7f, revision 4 released). "Later phases (v1.5 / v2+)" is unstarted backlog, linked from `PLAN.md`.

Plan written 2026-10-09. Planning only: nothing in `mods/square_roundabouts` changes with this file.
Background: `PLAN.md` (Phases 1-4b, "Decisions"), `PHASE5.md` (Phase 5a spike 4 "grade separation in
base sc.lua", Phase 5d/5f/5g notes = the Roundabout Interchange, the closest precedent), `PROBE.md`
(engine probe, search kinds, dev overrides), `TESTING.md` sections 11 and 14-15, `PERF_REVIEW.md`.
Lane routing moved to the separate mod `square_smart_lanes` (PHASE6.md, `plans/square_smart_lanes/PLAN.md`).
"sc.lua" below = `.cache/game/base/content/infrastructure/street_construction/street_constructions.script.lua`;
"ix.lua" = `mods/square_roundabouts/content/infrastructure/street_construction/square_roundabouts_interchange.lua`.

## Goal
User: "add an interchange builder with common highway interchanges, including parclo". The mod is now
called "Roundabouts & Interchanges" (`_metadata/modinfo.json`). Add a menu entry that stamps a
highway-to-road interchange (diamond and the partial cloverleaf family first) from base-game templates,
dissolving into ordinary editable roads like every other entry, and lay out the path to the larger
types (trumpet, cloverleaf, turbine...) without painting ourselves into a corner.

## Standing rules (unchanged, PHASE5.md "Standing rules")
- Base-game templates only; every node freed, `snapNodes = {}`; pure updateFn (no `api.*`); no
  `checkEnabledScript` (PLAN.md Phase 2a: "Disabled" does not refresh, "Hidden" breaks hovered base
  constructions); return only result tables built by `square_roundabouts_result.lua`.
- Params: keys prefixed `sqrb_`, 1-based option indices (`geom.index`, `square_roundabouts_geometry.lua:221-225`),
  every param does something for every value of the others (or follows the accepted no-effect
  precedent, tooltip says so), values are only ever appended, defaults = `readParams` fallbacks (tested).
- Construction-only mod: no game script, no GUI script, `severityAdd: None` (description "runs no
  scripts while you play" stays true).
- Lua pre-5.3 (`make check`). `make check`, `make test`, `make validate MOD=mods/square_roundabouts`
  pass at the end of every phase. Notes per phase go into this file ("Phase 7x notes").
- **Existing entries byte-identical**: Better Roundabouts, Magic Roundabout, Channelized Junction and
  Roundabout Interchange build exactly what they build today for every param set (section 6).

## Research summary (verified in files)
| fact | source |
|---|---|
| The base game already ships Diamond, Diverging diamond, Cloverleaf, T and Trumpet interchanges (all highway templates, 2 or 3 lanes, 3 scales, `yearFrom 1960`, concrete bridges only, right-hand traffic only, no parclo) | `base/content/infrastructure/street_construction/*_interchange.con.lua:19`; updateFns sc.lua:78, 288, 444, 679, 834 |
| Base cloverleaf loops = `addCurvedRamp` with `cloverDiam = 40`: two auto-tangent edges p0 -> pI -> p1, pI = mid + 40 (t0 - t1), mid tangent z = +-0.1, the upper half on a BRIDGE list (4 -> 8 m) | sc.lua:20-32, 106, 155-167 |
| Base cloverleaf loop numbers (computed offline from sc.lua with `street_util_serialized.calcScale`, all 6 lane/scale variants): smallest curve radius **24.4-31.1 m**, loop length 153-169 m, peak grade 10.1-10.3 %, weave between loop entry and loop exit on the same carriageway **74-124 m** | sc.lua:84-114, 155-167; `.cache/game/base/content/scripts/construction/street_util_serialized.tl:5-16, 55-71` |
| Base cloverleaf adds an **auxiliary lane** in the weave: the 2-lane highway becomes the 3-lane template between loop entry and exit, shifted 2.5 m outwards (`ledges2`, `threeLaneOffset = -2.5`) | sc.lua:114-128 |
| Base diamond: the outer lane drops into the ramp (3-lane template outside the ramps, 2-lane between them, shifted 2.5 m to the median); ramps join a carriageway node 4 m to the side with the same tag (`entranceExitOffset = laneWidth - 1`); both ramps of a side meet the cross road at one node at the bridge end, arriving/leaving along +-x (a 4-way junction at 8 m) | sc.lua:333, 339-351, 360, 366-375 |
| Base heights: diamond/cloverleaf upper level 8 m (`bridgeHeight`), approaches stay at 8 m on plain edges; T: highway in a -3 m cut, flyovers 4 and 10 m (bridge over bridge, 6 m apart); trumpet: -1 m cut, flyover 5 m. No base street construction builds a road tunnel | sc.lua:104, 140-147, 331, 699-707, 854-862; PHASE5.md spike 4 |
| Ramp template `highway_new_small` (one-way, 1 lane, 27.78 m/s, half width 4.5 m), highways `highway_new_small/medium/large` (1/2/3 lanes, half width 4.5/9/11.5 m), all `yearFrom 1940`; `_barriers` variants of all three exist (same lanes, `defaultEdgeDecorations` barrier_b, `yearFrom 1940`) | `base/content/infrastructure/street/highway/highway_new_small.street_template.lua:3-56`; `highway_new_*_barriers.street_template.lua:4, 12-15`; ix.lua:37-47 |
| Street templates set no `maxSlope`/`speedCoeffs`/`minCurveRadius` (engine defaults apply; their values are not in any script file); the fields exist on `StreetTemplate` and are readable at runtime through `api.res.streetTemplateRep` | `highway_new_small.street_template.lua` (none of the fields); `api/tealdef/api/type.d.tl:5471, 5513-5531`; `api/tealdef/api/res.d.tl:147`; wiki `infrastructure/tracksstreets.md:126, 192-194` (curve formula and min radius documented for tracks only) |
| Bridges: `steel.bridge` 1940+, pillars every 70-90 m, abutment 5 m; `concrete.bridge` 1970+, pillars 60-84 m, abutment 4 m, deck models 2.4 m below the deck | `base/content/infrastructure/bridge/steel.bridge.lua:243, 259-267`; `concrete.bridge.lua:162, 176-185`; PHASE5.md spike 4 |
| A construction cannot set lane connections (no node-config field in the result); routing is the engine default, or Smart Lanes after placement (gore nodes = its "case A", all one-way) | PHASE6.md research row "Constructions cannot set lane connections"; docs/findings.md "Junction lane connections"; `plans/square_smart_lanes/PLAN.md` Phase 4 (lines ~315-340) |
| Our Roundabout Interchange (ix) pattern is engine-verified: 2-edge slip roads (level gore + climb), tag-merged 4 m beside the carriageway node, ring/cross road on 8 m plain edges, bridges only over the carriageways, steel/concrete by `params.year`, LHT by `geom.mirrorX`. p5_all: 252/282 placed (the 30 refusals were all 4-lane two-bridge rings, fixed by `ALPHA_MAX_LANES`); p5g_verify 468/468; user in-game test "all good" | PHASE5.md "Phase 5d notes", "Phase 5f notes" 2, "Phase 5 result"; `probe_p5_all.md:162` |
| Junction placement failures are about join angles and road widths at shared nodes, not curvature: channel slip lanes at 40 deg refused on 3-lane arms, accepted at 50-80 deg; 4-lane ring slip joins refused at 32-38 deg, accepted >= 45 deg | PHASE5.md "Phase 5f notes" 2-3, "Phase 5g notes" |
| Offline engine-fitted junction model: free length >= 2.5 m, kerb corner <= 1 m (arms) / 6 m (legs) behind its node; shipping plan margin `geom.JUNCTION_PLAN` = 5 m | `tests/square_roundabouts/checks.lua:576-579`; `square_roundabouts_geometry.lua:210-216` |

## 1. Catalogue of interchange types

### Parclo naming (worked out on our frame, right-hand traffic)
Frame as ix.lua: highway along x, eastbound (EB) carriageway on the south (y < 0), westbound (WB) on
the north, cross road along y (x = 0). Quadrants SW, SE (beside EB) and NW, NE (beside WB). A ramp in a
quadrant can only connect the cross road with the carriageway beside it, and:
- **SW** (EB approach side): an off-ramp must be a **diagonal** (it leaves before the cross road and
  climbs to it); an on-ramp there must be a **loop** (it joins EB before the cross road, so it turns
  about 270 deg: cross road southbound -> west -> north -> east).
- **SE** (EB beyond side): an off-ramp must be a **loop**, an on-ramp a **diagonal**.
- NE / NW are the same for WB (approach side NE, beyond side NW).

So the classic names map onto **quadrant kinds**: an *A quadrant* (loop in Advance of the cross road)
= diagonal off + loop on; a *B quadrant* (loop Beyond the cross road) = loop off + diagonal on.

| type | quadrants | ramps (loops) | per carriageway, in driving order | cross road terminals |
|---|---|---|---|---|
| Diamond | SW off, SE on, NE off, NW on | 4 (0) | off, on | 2 (one per side, 4-way) |
| Parclo **A4** | SW A, SE on, NE A, NW on | 6 (2) | off, loop on, on | left turns only out of the exit ramps |
| Parclo **B4** | SW off, SE B, NE off, NW B | 6 (2) | off, loop off, on | left turns only onto the entry ramps |
| Parclo **A2** | SW A, NE A | 4 (2) | off, loop on | 2, all movements through them |
| Parclo **B2** | SE B, NW B | 4 (2) | loop off, on | 2 |
| Parclo **AB2** | SW A, NW B (one side of the cross road) | 4 (2) | EB: off, loop on; WB: loop off, on | 2, both on the west half |
| Cloverleaf to a road | SW A, SE B, NE A, NW B | 8 (4) | off, loop on, **weave**, loop off, on | 4 |

Every 2-quadrant type is symmetric under a 180 deg rotation (A2: SW+NE; B2: SE+NW; AB2: SW+NW ~
NE+SE), so the player's construction rotation covers every placement: **no quadrant param is needed**.
A mirror across the cross road is not a variant (it would reverse the one-way carriageways).
No parclo type has a weave on the highway: A types give off then on, B types off then off or on then
on; only the 4-loop cloverleaf weaves. (Unverified against an external reference: the A/B naming
above is derived from the geometry, which is unambiguous; only the labels could be swapped. Check
one diagram before writing the tooltip.)

### Feasibility per type
"Levels" counts road levels; heights as ix (`HEIGHT` 8 m, ix.lua:61). Footprints are estimates for a
medium highway, town medium cross road, 30 m arms (Phase 7b computes them).

| type | levels / bridges | loop radius vs limits | weaving | footprint (along x across) | reuse of ix code | verdict |
|---|---|---|---|---|---|---|
| Diamond (incl. tight urban = smallest Size) | 2 / 1 cross-road bridge (or 2 highway bridges for "highway over road") | none | none | ~340 x 150 m | carriageways, gores, slip edges, bridge half, bridge type, LHT mirror: all | **v1** (cheap; the base diamond's terminal pattern, sc.lua:366-375) |
| Parclo A4 / B4 | 2 / 1 (2) | loops 25-60 m centreline; base loops 24-31 m place (sc.lua:155-167) | none | ~400 x 300 m | as diamond + new loop builder | **v1** |
| Parclo A2 / B2 / AB2 | 2 / 1 (2) | same | none | ~400 x 300 m (two quadrants empty) | same generator, other quadrant table | **v1** (free once A4/B4 exist) |
| Cloverleaf to a road (4 loops) | 2 / 1 (2) | same | loop on -> loop off on each carriageway, under the bridge, ~2R + bridge long | ~400 x 300 m | same generator | **v1.5**: same code, but a weave; ship with an auxiliary lane (base `ledges2` pattern) or after the in-game test shows AI copes |
| Trumpet (3-way; stem = road or highway) | 2 / 1 stem bridge over the through highway, one ramp crosses under or over it | 1 loop | none | ~350 x 250 m | carriageways, gores, loop builder; new: one-sided cross road, ramp-over-highway bridge | **v2** (also a natural Type value: stem = Cross road, no arm on the far side) |
| SPUI (single-point urban) | 2 / 1 wide bridge carrying a 6-road node | none | none | ~300 x 120 m | diamond with both terminals merged | **later, spike first**: one node with 4 one-way ramps + 2 two-way arms on a bridge; nothing in base or our probes has 6 roads at a node (ring nodes have 4, base diamond terminals 4) |
| Diverging diamond | 2 / 1-2; cross road carriageways swap sides on the bridge | none | none | ~300 x 400 m | diamond | **later**: vanilla has it (sc.lua:444-630); ours would only add LHT, era bridges, sizes |
| Full cloverleaf highway-to-highway, with or without C-D roads | 2 / 1 (+ C-D roads beside both highways) | 4 loops | without C-D: on the mainline (base 74-124 m with aux lane); with C-D: on the C-D road | ~500 x 500 m (base: ~500 m) | gores, loops; new: second highway instead of a cross road, C-D gores | **v2, second entry** ("Highway Junction"); vanilla already has the plain cloverleaf, our value is C-D roads, sizes, LHT |
| Turbine / whirlpool | 2-3 / 4 long curved ramps each crossing a carriageway or another ramp (bridge over bridge) | ramps ~100-150 m radius | none | ~600 x 600 m | gores; new: long multi-edge curved ramps with grade profiles, bridges over bridges | **later** |
| Directional / stack (4-level) | 4 (0 / 8 / 16 / 24 m) / many, bridges over bridges over bridges | flyovers ~150 m radius | none | ~700 x 700 m | gores only | **out of scope** for now: 24 m rises need >= 240 m at 10 %, pillar placement through lower levels unverified (bridge pillars every 60-90 m, `concrete.bridge.lua:180-182`) |

**Recommendation for v1**: Diamond and the five parclos (A4, B4, A2, B2, AB2) in one new entry,
both levels, three highway sizes, left-hand traffic. Cloverleaf-to-a-road is a cheap follow-up value
of the same Type param once the weave is checked in game (v1.5). Trumpet next (v2), then a second
entry for highway-to-highway junctions (cloverleaf with C-D roads, turbine). SPUI and stack stay out
until a spike shows the engine accepts them.

## 2. Menu and UX

### Recommendation: one new entry "Highway Interchange" with a Type param
- The v1 types share every param except one (loop radius vs terminal spacing), so one entry with a
  **Type** ComboBox keeps the menu at five entries (Better Roundabouts 3010, Magic 3011, Channelized
  3012, Roundabout Interchange 3013, **Highway Interchange 3014**; orders from the four `.con.lua`
  `menuCategory`).
- The type-specific dimension becomes one **Size** param whose meaning depends on the type (parclo:
  loop radius; diamond: terminal distance), so no value of any param is dead for any type: no
  `checkEnabledScript` needed (PLAN.md Phase 2a).
- One entry per type was considered and rejected for v1: six near-identical entries with identical
  param lists, 6+ menu icons and previews, six `.con.lua` files to keep in sync. The precedent for a
  separate entry is a *different param set* (Magic, Channelized, Roundabout Interchange); that will
  apply to the highway-to-highway junctions (no cross road, a second highway), so they get the
  second entry later.

### Params (UI order; defaults bold)
| key | UI | values | notes |
|---|---|---|---|
| `sqrb_hx_type` (new) | ComboBox | **Parclo A4**, Parclo B4, Parclo A2, Parclo B2, Parclo AB2, Diamond | append-only list (v1.5 adds Cloverleaf, v2 Trumpet at the end); tooltip names the quadrants in words ("A4: loops before the bridge are on-ramps; exits are straight") |
| `sqrb_ix_highway` (shared with ix) | Button | Small, **Medium**, Large | same values, same `ix.HIGHWAYS` templates, so sharing the key is safe (ix shares `sqrb_lanes` / `sqrb_direction` / `sqrb_island` with the main entry the same way, ix.lua:116-128) |
| `sqrb_hx_level` (new) | Button | **Road over highway**, Highway over road | own key: the labels differ from ix's "Ring over highway"; same index meaning (1 = upper cross level, the base diamond pattern) |
| `sqrb_ix_cross` (shared) | ComboBox | the six arm roads, **Town, medium** | same list as ix / Arm road (`geom.ARM_TEMPLATES`) |
| `sqrb_hx_size` (new) | Slider | Compact, **Standard**, Large, Very large | parclo loop radius (centreline) **25 / 35 / 45 / 60 m** (25 m = base cloverleaf's tightest); diamond: terminals 0 / 15 / 30 / 50 m beyond the bridge ends (Compact = tight urban diamond). A minimum, like Radius: grows if the layout does not fit. Values tuned by the probe (7e) |
| `sqrb_hx_ramp_length` (new) | Slider | **Shortest**, +20, +40, +60 m (7c; planned 120, **140**, 160, 180 m) | extra length over the type's shortest ramp (parclo: the wrapped diagonal's minimum, 155-272 m; diamond: 120 m), measured along the highway from the cross road axis to the diagonal ramps' carriageway node. Phase 7c notes |
| `sqrb_ix_arm_length` (shared) | Slider | **30**, 40, 50, 60 m | cross road beyond the outer terminals, highway beyond the outermost gores (ix meaning) |
| `sqrb_direction` (shared) | Button | **Right-hand traffic**, Left-hand traffic | as ix: everything mirrored in x |

Later params (each appended, default = today's build): `sqrb_hx_barriers` Off/On (`_barriers`
highway templates; unverified that barrier decorations leave gores drivable), `sqrb_hx_landscape`
None/Grass/Grass and trees (ground faces + colliders inside loops and between ramps, reusing
`geom.face` / island colliders; base interchanges have none, `result.groundFaces = {}`, sc.lua:282),
`sqrb_hx_signals` (only after TESTING.md 7.4 is answered: which of `trafficLightYes` /
`trafficLightNodePreference` works; today unanswered).
Not a param: bridge type (by `params.year` via `ix.bridgeType`, ix.lua:155-158), availability 1940
(highway, ramp templates and steel bridge, PHASE5.md 5a spike 3).

Conventions to keep (tested in 7c, as test_interchange's ".con.lua" test): keys/order/defaults equal
`hx.readParams` fallbacks; foreign or out-of-range values fall back (`geom.index`); `params.year`
read; no dev key in the `.con.lua`; `updateScript = "square_roundabouts_highway.script@updateFn"`,
`icon`/`previewIcon` relative names, `availability.yearFrom = 1940` (checked by test_short_edges).

## 3. Geometry approach

### Module split (same pattern as ix: pure geometry -> result mapping -> 3-line script)
| file | role |
|---|---|
| `square_roundabouts_ramps.lua` (new, shared, pure) | highway cross-section frame, carriageway edge builder with arbitrary gore nodes, gore + slip edges, loop arcs, vertical profiles, highway/cross-road bridge extents, bridge type, list helper. Extracted from ix.lua (below) plus the new loop/profile code |
| `square_roundabouts_highway.lua` (new, pure) | `hx.readParams`, `hx.plan` (fit/growth), `hx.build`: quadrant table per type -> ramps, terminals, cross road, carriageways; returns `{lists, ramps, terminals, ...}` in the `geom.build` output format, so `square_roundabouts_result.lua` maps it unchanged (it already copies `edgeType`/`edgeTypeName`, result.lua:31-32) |
| `square_roundabouts_highway.con.lua`, `.script.lua`, `square_roundabouts_highway@2x.tga`, `..._preview@2x.tga` | menu entry; script = `result.build(hx.build(hx.readParams(params)))` |
| `square_roundabouts_interchange.lua` | unchanged behaviour; its frame / gore / carriageway / bridge code now calls `ramps.*` and keeps `ix.*` aliases (`ix.HIGHWAYS`, `ix.HEIGHT`, `ix.CLEAR`, `ix.bridgeType`, `ix.rampEdges`, ...) because test_interchange, test_dev and the probe's `probe_geom.lua:119-143` use them |

### Shared helpers to extract from ix.lua (output must stay byte-identical)
| ix.lua today | becomes | note |
|---|---|---|
| constants `HIGHWAYS`, `DEFAULT_HIGHWAY`, `RAMP`, `MEDIAN`, `MERGE_OFFSET`, `GORE_GAP`, `GORE_RUN`, `GORE_SLOPE`, `HEIGHT`, `BRIDGE_*`, `CONCRETE_FROM`, `CLEAR` (:37-70) | `ramps.*`, re-exported as `ix.X = ramps.X` | same tables (not copies), so a test that mutates nothing sees the same values |
| `ix.bridgeType` (:155-158) | `ramps.bridgeType` | alias |
| local `tuned` (:161-165) | stays local in each module | the dev key names differ per entry (`ixClear` vs `hxClear`); shared helpers take plain numbers, never a spec |
| highway part of `ix.frame` (:176-191: `highway`, `hwH`, `c`, `corr`, `hwRamp`, `clear`, `yClear`) | `ramps.frame(highwayIndex, clear)`; `ix.frame` adds `hwR`, `offset`, `hwX` | identical arithmetic order (`c = halfWidth + MEDIAN / 2`, `corr = c + hwH`, `yClear = corr + clear`) |
| gore part of `ix.rampEdges` (:309-333: `m`, `g`, tag, `before`, `run`) | `ramps.gore(f, cw, io, xm, goreRun, tagPrefix)` -> `{m, g, head, tag, before}`; `ramps.slipEdges(gore, endPos, endDir, endTag)` -> the two edges in driving order | `ix.rampEdges` = `ramps.slipEdges(ramps.gore(lay.f, cw, io, lay.xm, run, "sqrb_ix_"), {n.pos[1], n.pos[2], zRing}, ix.slipDir(...), n.tag)`; same `S.curveEdge` calls in the same order |
| `highwayBridgeHalf` (:416-429) | `ramps.highwayBridgeHalf(f, edges)` | unchanged code |
| carriageway loop in `ix.build` (:515-540) | `ramps.carriageways(f, cwNodes, zHw, tagPrefix)` where `cwNodes[cw]` = sorted x positions with tags and a bridged flag per segment | ix passes exactly `{-xm-L, -xm, (-xb, xb,) xm, xm+L}` and its tags; edges come out in the same order (south first, north reversed) |
| local `list` (:407-412) | `ramps.list` | |
| `geom.mirrorX` (geometry.lua:1515-1536), `S.curveEdge` / `S.straightEdge` / `S.hermite` (shapes.lua:48-72), `geom.hermiteScale` (geometry.lua:231) | used as they are | already shared |

**Safety net first (Phase 7a)**: today's goldens cover only the main and Magic entries
(`tests/square_roundabouts/test_default_unchanged.lua:21-28`). Before touching ix.lua, record
fingerprints of the Channelized Junction and Roundabout Interchange over their full shipped sweeps
(the `channelSweep` / `interchangeSweep` grids of `test_short_edges.lua:83-110`, with and without
`params.year`) into a new `tests/square_roundabouts/golden_entries.lua`, plus an **exact** variant
(numbers as `%.17g` instead of `golden.lua`'s 1e-4 rounding) so a refactor that changes a last bit
shows up. The extraction lands only when both pass without re-recording.

### Frame and quadrant model (`square_roundabouts_highway.lua`)
- Right-hand frame of ix.lua (highway along x, EB south, z up), built once, mirrored with
  `geom.mirrorX` for left-hand traffic (keeps edge directions, ix.lua:575).
- Type -> quadrant table `{SW, SE, NE, NW}` of kinds `none | off | on | A | B` (table in section 1).
- One canonical builder for the **SW quadrant** (kinds `off`, `on`-loop, `A`); the other quadrants
  come from two symmetries: rotation by 180 deg (SW <-> NE, SE <-> NW: EB <-> WB) and
  **mirror-x + reverse every edge** (SW <-> SE: maps "diagonal off" to "diagonal on" and "loop on" to
  "loop off", keeping EB eastbound). B = mirror-reverse(A). This keeps one geometry per ramp shape
  and makes the four quadrants exact images (tested).

### Diagonal ramps (reuse of the ix slip road)
`ramps.gore` + `ramps.slipEdges` exactly as ix: level gore from the tagged carriageway node 4 m
beside it (`MERGE_OFFSET`), parallel, `GORE_RUN` 30 m (or 2.5 x lateral) out to node G 1 m clear of
the carriageway band, then one climb edge to the terminal. Terminal join: perpendicular to the cross
road (the base diamond's ramps arrive along +-x, sc.lua:366-375; ix's dumbbell joins at 35 deg off
the normal were accepted too). In A/B quadrants the diagonal runs **outside** the loop: its gore is
upstream (A) / downstream (B) of the loop's gore and it meets the cross road at the outer terminal.

### Loops (new: `ramps.loop`)
Canonical SW loop-on, from the cross road down to EB:
1. **Terminal stub**: straight, from the inner terminal node T_i = (0, -yTi) leaving the cross road
   westwards at angle psi to it (psi = 90 deg = perpendicular in v1; dev override `hxLoopJoin`), length
   >= `geom.MIN_EDGE` (10 m).
2. **Arc**: a circle of centreline radius R (Size) tangent to the stub and to the gore line
   y = -y_g (y_g = c + hwH + hwRamp + GORE_GAP, the lateral position where a slip road clears its
   carriageway, ix.lua:318-321); clockwise for right-hand traffic (stub heading west -> north ->
   east); sweep 180 deg + (90 deg - psi). Split into the fewest Hermite edges of <= 90 deg
   (`geom.MAX_EDGE_ANGLE`, the ring rule) with circle handles `geom.hermiteScale(theta) * R`
   (geometry.lua:231; base uses up to 135 deg per edge, sc.lua:20-32, so 90 deg is conservative).
3. **Gore**: the level gore edge of `ramps.gore` (same merge rule as the diagonals), from the arc's
   top heading east to the tagged carriageway node.
With psi = 90 deg the terminal sits at yTi = y_g + 2R (medium highway: 75.5 / 95.5 / 115.5 / 145.5 m
for R 25 / 35 / 45 / 60). The loop's east-most point keeps `CLEAR` (8 m) plus half widths from the
cross road's 8 m embankment; the merge node lies under the cross-road bridge span or west of it
(the bridge covers |y| < yb = corr + CLEAR, and y_g < yb for every highway).

### Terminals and the cross road
- Cross road: two-way, at the upper level for "Road over highway" (z 8, bridge from -yb to +yb, plain
  8 m edges beyond, as the base diamond/cloverleaf: sc.lua:140-147, 360) or at 0 with the highway on
  two bridges for "Highway over road" (ix's `highwayBridgeHalf` rule, ix.lua:416-429, with the cross
  road as the only lower road near the corridor).
- Per side of the highway, up to two terminal nodes on the cross road: **outer** T_o (diagonals: a
  4-way node when the opposite quadrant also has a diagonal, the base diamond's terminal) and **inner**
  T_i (loops, 3-way). yTo = yTi + `TERM_GAP` (first guess 30 m: both junctions keep
  `geom.JUNCTION_PLAN` 5 m free between them under `geom.kerbCut`; dev override `hxTermGap`).
  Diamond: only T_o, at yb + Size distance (Compact = at the bridge end: tight diamond).
- Arms: the cross road beyond T_o by Arm length (as ix arms, ix.lua:494-497).

### Grade separation and vertical profiles
- Two levels only in v1: 0 and `HEIGHT` 8 m (ix.lua:61; base diamond/cloverleaf 8 m). No ramp crosses
  another road: every v1 crossing is the cross road over (or under) the two carriageways, so
  `checks.levelSkip(7)` (checks.lua:228-257) only ever sees those pairs; anything else is a 2D overlap
  failure.
- Diagonals: ix profile (level gore, one climb edge with flat ends: S-curve in z).
- Loops: the climb spans the stub and the arc. z by arc length s with a smoothstep profile
  z(s) = H (3u^2 - 2u^3), u = s / S (flat at the terminal and at G; peak grade = 1.5 x average);
  intermediate nodes get z(s_i) and a tangent z-slope z'(s_i) (base `addCurvedRamp` already uses a
  non-flat mid tangent, z = +-0.1, sc.lua:24-27). Limits (PHASE5.md 5a, from base geometry): average
  <= 10 %, peak <= 15 % -> climb length >= 80 m for 8 m. R = 25 m with a 10 m stub gives 25 pi + 10 =
  88.5 m (avg 9.0 %, peak 13.6 %): passes; the fit rule lengthens the stub otherwise.
- Bridges at full height at both ends; deck clearance 8 m over the highway (free height ~5.6 m with
  concrete decks 2.4 m deep, PHASE5.md 5a).
- Terrain: as ix (plain 8 m edges on engine embankments, no `alignTerrain`; TESTING.md 11.5 and 14.11
  passed in the Phase 5 walkthrough).

### Merges and diverges on the one-way carriageways
- Each carriageway gets one tagged node per gore, sorted along the driving direction, with straight
  plain edges between (`ramps.carriageways`). Consecutive gores keep >= `GORE_RUN` + `MIN_EDGE`
  between their nodes (A4 EB: diagonal off at -xm, loop on just west of the bridge, diagonal on at
  +xm). Bridged segments for "Highway over road" as ix.
- v1 keeps one carriageway template throughout (as ix). Later option, base-proven: an auxiliary lane
  between two gores by switching to the next wider template with a 2.5 m outward shift (base
  cloverleaf weave, sc.lua:114-128) or a lane drop at the exit (base diamond, sc.lua:339-351); needed
  for Cloverleaf-to-a-road (v1.5) and impossible for the large highway (no 4-lane highway template).

### Lane connections
Constructions cannot write node configs (PHASE6.md), so the engine generates them at every new node.
Gore nodes (carriageway in, carriageway out, 1-lane ramp, all one-way) are the ix pattern, which the
user's in-game test passed (TESTING.md 14.2 "highway -> ring -> cross road and back"); Smart Lanes
handles them as its "case A" (lanes matched kerb first). Terminals are two-way cross road + one-way
ramps, the base diamond's junction; the engine default allows every legal turn (one-way ramps rule out
wrong-way entries). Nothing to build; description.html's Smart Lanes paragraph gets one sentence on
gores. Unverified: whether the engine offers a U-turn at a 4-way terminal (TESTING item).

### Fit and growth (`hx.plan`)
Like `ix.plan` (ix.lua:389-405): Size and Ramp length are minimums. Try the chosen Size, then the
next ones and a few `GROW` steps (loop R 70 / 80 m, terminal distance +10 m steps), and for each the
smallest ramp length from the slider up that fits: every junction keeps `JUNCTION_PLAN` free and
corners behind within limits (`geom.kerbCut` at terminals, the gore rule at carriageway nodes), loop vs
diagonal clearance >= `geom.LEG_CLEARANCE` + half widths, climb lengths meet the gradient limits,
loop east-most point clears the cross road embankment by `CLEAR`, consecutive gores spaced. Never
forced for shipped params (tested); a forced plan is flagged `built.forced` as in ix.

## 4. Engine risks and open questions
Unverified unless a source is given. "Probe" = `mods/square_roundabouts_probe` (DEV ONLY) via
`makeProposalData` (PROBE.md "How it works"); "search" = its `grid` search kind with dev overrides
(PROBE.md "Phase 5e runs").

| # | risk / question | evidence so far | mitigation | how verified |
|---|---|---|---|---|
| R1 | Placement check refuses terminals where a ramp meets the cross road (two ramp nodes close together, wide cross roads) | the only refusals in Phase 5 were join angles at shared nodes on wide roads (PHASE5.md 5f 2-3); perpendicular joins and 4-way base-diamond terminals are accepted in base | perpendicular joins (psi 90 deg), inner/outer terminal gap `TERM_GAP` checked with the engine-fitted model; dev overrides `hxTermGap`, `hxLoopJoin`, `hxClear` | probe sweep `p7_hx_all` + grid search `p7_hx_search` over those overrides for every refused base combo; bake the winners into a `hx` part of the tuning table (7e) |
| R2 | Loops too tight for the engine | base loops 24.4-31.1 m place (computed above); our 1-lane rings place from 8 m (`highway_new_small` ring, PLAN.md Phase 3) | smallest Size = 25 m (base minimum), search `hxLoopRadius` 20-30 m to learn the real floor | probe |
| R3 | Loops read as too tight to the AI (crawling, congestion) | curve speed for streets is engine-internal (`speedCoeffs` unset on highway templates; tracksstreets.md:192 documents the formula for tracks) | default Standard (35 m); probe logs `api.res.streetTemplateRep` fields (`speedCoeffs`, `maxSlope`, `maxSlopeShape`, `minCurveRadius`, type.d.tl:5513-5531) of `highway_new_small` once at start (an `INFO` line, read only); in game: watch a truck on a 25 m and a 60 m loop | probe INFO line + TESTING 16.6 |
| R4 | Slopes: loop climbs or diagonals over the engine's street slope limit | ix ramps (avg <= 9.1 %, peak <= 13.7 %) placed; base peaks up to 21 % (T descents, PHASE5.md 5a) | offline gradient check (avg <= 10 %, peak <= 15 %) in the fit rule and tests; the probe INFO line above gives the real `maxSlope` | test_highway + probe |
| R5 | Edge collisions between ramps in one quadrant (loop vs diagonal) | none in base parclo (base has none); 2D overlaps already modelled (`checks.overlaps`) | plan clearance rule; `checks.overlaps` with `levelSkip(7)` in tests must report only cross-road/carriageway crossings | tests; probe `coll=` field |
| R6 | Minimum edge length / closely spaced nodes (stubs, gores, carriageway pieces) | `checks.shortEdges` >= 1 m and node gap 0.5 m pass for all entries (PHASE5.md 5a); our own floor `MIN_EDGE` 10 m | stubs and carriageway pieces >= `MIN_EDGE`; add the entry to `test_short_edges.lua` ENTRIES | tests |
| R7 | Bridge over a bridge | not needed in v1 (no ramp crosses anything); base T: 10 m over 4 m flyover (sc.lua:706-707, 765) | v1 avoids it by construction (asserted in tests: the only grade-separated pairs are cross road x carriageway) | test; v2 trumpet/turbine need a probe |
| R8 | Pillars of the cross-road bridge landing in the median or a carriageway | bridge spans 2 yb = 38 / 56 / 66 m (small / medium / large highway, yb = corr + CLEAR); pillars every 60-90 m (`steel.bridge.lua:265-267`, `concrete.bridge.lua:180-182`); ix bridges of 40-140 m placed | keep the bridge one edge from -yb to +yb (ix does the same) | probe (both years) + in game |
| R9 | Gores too close together on one carriageway (A4/B4: two gores on the same side within ~100 m) | ix has one gore per carriageway end; base diamond 2 per carriageway, cloverleaf 3 | spacing rule above; search `hxGoreRun` | probe |
| R10 | The loop's level gore runs under the cross-road bridge (A4 loop merges just west of it) | ix gores run beside a carriageway under ring bridges (two-bridge ring) and placed | `levelSkip` treats it as a crossing only if 8 m apart and the upper edge is a bridge; else the merge node moves west of the bridge's plan footprint + CLEAR | tests + probe |
| R11 | "Highway over road": the 8 m highway on plain edges with four gores and loops descending from it | ix "Highway over ring" placed for every layout (p5_all) | same bridge-half rule | probe level axis |
| R12 | Footprint / bbox: ~400 x 300 m, ~60-80 edges | base cloverleaf ~500 m wide; ix up to 402 m | none needed; watch the probe's `ms=` and the updateFn time (target < 5 ms, PERF_REVIEW.md) | probe + offline timing |
| R13 | Barrier templates (later param) block traffic at gores | unknown | ship later, probe first | probe + in game |
| R14 | A/B naming swapped vs the textbook | derived from geometry above | check one reference diagram before the tooltip text (7c) | review |

Probe reuse: add an `hx` entry to `probe_grid.lua` `grid.ENTRIES` / `ENTRY_ORDER` (key tag `h:`,
axes in `.con.lua` order plus the pseudo axis **year** 1969 / 2020 as for `x:`), `geomInfo.highway`
in `probe_geom.lua` (effective size, ramp length, forced, bridge, terminal distances), `parse_probe.py`
AXES and a report section, `verdicts.lua` `V.hx` and gap category `hx`, `gen_roundabouts_tuning.py`
`hx_table` writing a new `hx` part only (the existing parts must stay byte-identical: test). Dev keys
`hxClear`, `hxGoreRun`, `hxTermGap`, `hxLoopJoin`, `hxLoopRadius`, `hxRampX` in `geom.DEV_KEYS` /
`DEV_RANGES` (geometry.lua:365-410): read only when present, never in a `.con.lua` (test_dev).

## 5. Phases
Each phase runs in its own subagent (memory: "Phases run in subagents"), reads this file, writes its
notes into it ("Phase 7x notes": decisions, file:line evidence, unverified -> TESTING.md), and ends
with `make check`, `make test MOD=mods/square_roundabouts` (plus the probe's tests when it changed) and
`make validate MOD=mods/square_roundabouts`. No revision bump before 7f.

### 7a: safety net + shared extraction (no behaviour change)
- `tests/square_roundabouts/golden_entries.lua` + `test_entries_unchanged.lua`: channel and
  interchange fingerprints (rounded and exact) over their shipped sweeps, **recorded on the current
  code before any edit** (`SQRB_GOLDEN_WRITE=1`, as `golden.lua` explains).
- `square_roundabouts_ramps.lua` with the helpers of section 3; ix.lua delegates and keeps its aliases.
- Gate: `test_default_unchanged`, `test_entries_unchanged`, `test_interchange`, `test_channel`,
  `test_short_edges`, `test_dev`, `test_engine_verdicts` and the probe's tests pass **without
  re-recording anything**. Unit tests for the new helpers (`test_ramps.lua`: gore/slip edges equal
  ix's on a sample, carriageways for arbitrary gore lists, bridge half).
- Also: compute the base interchanges' loop/terminal numbers offline into the notes (a small Lua test
  helper, no shipped code), and confirm the A/B naming (R14).

### 7b: pure geometry (`square_roundabouts_highway.lua`, no menu entry yet)
- `hx.readParams`, quadrant tables, `ramps.loop`, profiles, terminals, cross road, `hx.plan`, `hx.build`.
- `tests/square_roundabouts/test_highway.lua` (pattern of `test_interchange.lua`):
  every type x highway x level x traffic side x Size x cross road {town small, town large, country
  small, country large} at both ramp-length extremes: no forced plan; tags (every ramp snapped on its
  carriageway or terminal node; every gore 4 m beside, parallel, same tag); edges >= `MIN_EDGE`;
  `checks.engineModel` at every terminal; heights (levels flat, bridges at 8 m, ramps climb the whole
  8 m with flat ends); gradients avg <= 10 % / peak <= 15 %; loop radius = Size (or grown); loop sweep
  and direction (right turns for RHT); order of gores per carriageway per type (A: off then on; B: off
  then off ...); quadrant symmetry (SE = mirror-reverse of SW, NE = rotated SW, exact to 1e-9);
  `checks.overlaps` with `levelSkip(7)` and exactly the cross road x carriageway crossings;
  LHT = mirror; every param changes the build (Size and Ramp length above the minimum); ramps per
  type (4 / 6 / 8 counts, loops 0 / 2); year -> bridge type.
- `test_short_edges.lua` ENTRIES gains a `highwaySweep` (with `params.year = 1969`); `checks.YEAR_FROM`
  already lists every template used.
- Timing: the sweep's mean / max updateFn time in the notes (< 5 ms target).

### 7c: menu entry, icon, in-game checklist
- `square_roundabouts_highway.con.lua` (params of section 2, order 3014, yearFrom 1940, tooltips with
  `\n` lines <= ~60 chars), `.script.lua` (3 lines), icon `square_roundabouts_highway@2x.tga` from
  `tools/render_icon_square_roundabouts.py` (a parclo A4 top view in the house icon style; the four
  existing icons must re-render byte-identical), `previewIcon` = the interchange's preview until a
  capture exists.
- test_highway ".con.lua" test (keys, order, defaults = readParams, no checkEnabledScript, no dev
  keys, script exports only updateFn, all nodes free, bridge list by year).
- TESTING.md **section 16** (below). Optional first look by the user before the probe: place the
  default (Parclo A4) and Diamond in a 2020 save.

### 7d: probe extension (DEV ONLY; the user runs it)
- `hx` entry, dev keys, `geomInfo.highway`, subsets: **`p7_hx_all`** (every type x highway x level x
  Size x {town medium, town large, country large} x year {1969, 2020} at ramp length 140, plus ramp
  120 and LHT samples: ~900 combos, ~20-40 s at the p5_all rate) and **`p7_hx_search`** (one job per
  type x highway x level at Size Compact: grid `hxTermGap` {30, 20, 40} x `hxLoopJoin` {90, 75, 60} x
  `hxClear` {8, 6}; and `hxLoopRadius` {20, 22.5, 25, 30} on the parclos), `smoke` gains the hx default.
  Probe tests (`tests/square_roundabouts_probe/`): subset sizes, axes == `.con.lua`, dev params reach
  the real geometry, every combo sane, log fields.
- PROBE.md "Phase 7 runs": steps as the Phase 5e runs (flat map, 2020, RHT, Run On, Start delay 15 s,
  Combos per update 8, Position 0/0, context None, Log placeable On); copy stdout.txt to
  `plans/square_roundabouts/probe_p7_hx_all.log` / `probe_p7_hx_search.log`; parse with
  `uv run tools/parse_probe.py --stdout ...`. The INFO line with the `highway_new_small` template
  limits (R3/R4) goes into docs/findings.md with the date.

### 7e: tuning pass, verification, in-game test
- From the probe data: `hx` tuning part (terminal gap / loop join / clear per type x highway x level
  where the shipped geometry was refused, the generator's narrowest-first rule), Size values
  confirmed or moved (the slider values are labels, so moving 25 -> 30 m is free before release),
  `V.hx` replay in `test_engine_verdicts.lua` (every refused combo ships a layout the engine accepted
  or is a documented gap), subset **`p7_verify`** for whatever the pass changed (user run, as
  p5g_verify).
- User in-game test: TESTING.md section 16; fix-ups as "Phase 7e notes".

### 7f: release (revision 4)
- **Remove the Phase 7e fix-up diagnostics first:** `square_roundabouts_hx_variants.lua` and its hook in `hx.build`
  plus the dev key `hxVariant` and the TEMPORARY menu param "DEV ramps" (`hx.TMP_KEYS`; regenerate the probe copy con after), keeping only the variant that ships as plain geometry; `square_roundabouts_fingerprint.lua`, its `fp.report` call in
  `square_roundabouts_highway.script.lua` and the fingerprint test in test_highway.lua (the probe's copy
  con / `fpLocal` stay in the DEV probe, but drop its ug_require of the fingerprint module too). The dev key
  `hxTagJoints` may stay (DEV-only) or ship as the default if the fix-up decides so.
- `mod.json` `revision` 4.
- `_metadata/description.html`: intro names five entries; Features bullet "Highway Interchange";
  `<h4>Settings: Highway Interchange</h4>` with every param and default; Notes: "five construction
  menu entries", the Highway Interchange in the "less engine-checked" note if 7e left gaps; Smart Lanes
  paragraph mentions slip road gores; **Changelog** `<h4>Revision 4 (date)</h4>` first, e.g. "New:
  Highway Interchange menu entry: diamond and partial cloverleaf (parclo A4, B4, A2, B2, AB2)
  interchanges between a highway and a road, road over highway or highway over road, three highway
  sizes, four sizes, right- or left-hand traffic; steel bridges before 1970, concrete after." plus
  "Changed: nothing else; every roundabout, junction and roundabout interchange builds exactly as in
  revision 3." Headings per CLAUDE.md (`<h2>` only for Changelog, `<h4>` otherwise).
- `modinfo.json`: summary (<= 100 chars), e.g. "Roundabouts, Magic Roundabout, channelized
  junctions, parclo, diamond and roundabout interchanges." (98 chars); description adds the Highway
  Interchange sentence.
- Branding: hover preview `square_roundabouts_highway_preview@2x.tga` from an in-game capture via
  `tools/render_preview_square_roundabouts.py` (capture `shots/18-parclo-*.jpg`); gallery: **append**
  slides 10+ in `branding/shots.js` ("Highway interchanges: diamond and parclo", a menu/settings inset)
  and `make shots MOD=mods/square_roundabouts` (mod.io galleries are append-only: memory
  "mod.io gallery is append-only"; never renumber 1-9). Cover: name and tagline "Rings, junctions,
  interchanges" (`branding/mods.js:102`) still fit; no re-render unless the user wants a parclo glyph.
- `make validate`, then the `tf3-mod-validator` agent before upload.

### Later phases (v1.5 / v2+), each with its own probe round
- 7g: Type **Cloverleaf** (4 loops to a road) with an auxiliary weave lane (base sc.lua:114-128);
  `sqrb_hx_landscape`, `sqrb_hx_barriers`.
- 8: Type **Trumpet** (stem = cross road, one loop, one ramp bridge over or under the through
  highway: first ramp-over-highway bridge, a probe question).
- 9: second entry **Highway Junction** (highway to highway): cloverleaf with or without C-D roads,
  then turbine. Stack, SPUI, diverging diamond only after a spike.

### TESTING.md section 16 (to add in 7c; checklist)
1. Menu: "Highway Interchange" from 1940 (absent in 1939), params in the order of section 2, tooltips readable.
2. Default (Parclo A4, medium highway, road over highway, town medium cross road, Standard, 140 m, 30 m, RHT) on
   flat ground in 2020: places; the cross road 8 m up on one concrete bridge; two loops (SW and NE),
   four diagonals; every gore leaves/joins 4 m beside the carriageway, level for ~30 m.
3. Each type once (B4, A2, B2, AB2, Diamond): the ramps sit in the quadrants of section 1; follow one
   car per movement (highway -> cross road both ways, cross road -> highway both directions).
4. Highway over road, each type: highway on two bridges over the cross road, loops descend from it.
5. Sizes: Compact (25 m loops, tight diamond) and Very large (60 m); Ramp length 120 m: gradients look
   acceptable, trucks climb.
6. Loop speed: a truck on a 25 m and a 60 m loop (R3): crawling? Note the speed shown on the vehicle.
7. Left-hand traffic: mirrored, loops turn left, gores still before/after the cross road correctly.
8. 1965 save: steel bridges; 2020: concrete (as 14.3).
9. Terminals: no U-turn offered at a 4-way terminal; lights can be added with the game's tool.
10. Editing after placement: everything is ordinary roads; connect the arm and highway ends.
11. Removal of the mod from a save with a Highway Interchange: roads stay (Warning severity unchanged).

## 6. Save compatibility
- New entry only: a new `.con.lua` with new file names and new keys (`sqrb_hx_*`); shared keys only
  where the values and meaning are identical (`sqrb_ix_highway`, `sqrb_ix_cross`, `sqrb_ix_arm_length`,
  `sqrb_direction`). Placed constructions dissolve into streets (every node freed), so a save stores
  roads, not params; still, the existing entries' param lists, keys, value orders and defaults do not
  change (builder settings and any re-run of an updateFn see the same indices).
- Output of the four existing entries is unchanged for every param set: golden fingerprints for main
  + Magic (`golden_default.lua`) and, from 7a, Channelized + Roundabout Interchange
  (`golden_entries.lua`, rounded and exact) pass **without re-recording** at the end of every phase;
  the tuning table's existing parts stay byte-identical (generator test); new dev keys change nothing
  when absent (test_dev, test_default_unchanged "unrelated dev keys").
- `severityAdd: None`, `severityRemove: Warning` unchanged (islands of the other entries; the new entry
  adds no subconstruction in v1). No game or GUI script.

## Phase 7a notes (2026-10-09)

**Done (no shipped behaviour change; no revision bump, description.html untouched).**
- Safety net first, recorded on the unchanged code: `tests/square_roundabouts/golden_entries.lua` (48 groups,
  `{rounded, exact}` per group) checked by `test_entries_unchanged_channel.lua` (12 groups = layout x main
  road, 6,912 builds) and `test_entries_unchanged_interchange.lua` (36 groups = layout x highway x level x
  year {1969, none}, 2 x 3,456 builds). Two files instead of the planned single `test_entries_unchanged.lua`
  so the runner runs them in parallel (~30 s and ~42 s; one file took 73 s). Both passed, then the
  extraction landed and both still pass **without re-recording**; `golden_default.lua` untouched.
- `golden.lua` gained `G.serializeExact` (`%.17g`, `-0` kept), `G.fingerprints` (one build, both
  hashes), `G.each`, `G.range`, `G.channelSweep`, `G.interchangeSweep(ix, year, fn)`, `G.entryGroups`,
  `G.entryTest`. `test_short_edges.lua` now takes the channel / interchange grids from there (same grids,
  so the goldens and the short-edge sweep can't drift apart). Checked: perturbing `GORE_GAP` by 1e-12
  fails all 36 interchange groups on the exact hash only (the rounded one stays equal), then reverted.
- `square_roundabouts_ramps.lua` (new, pure): the section-3 constants, `bridgeType`,
  `frame(highwayIndex, clear)`, `gore(f, cw, io, xm, goreRun, tagPrefix, z)` ->
  `{m, g, head, tag, before, io}`, `slipEdges(gore, endPos, endDir, endTag)`, `highwayBridgeHalf(f, edges)`,
  `carriageways(f, cwNodes, z)`, `list`. ix.lua delegates: constants re-exported as the same tables
  (`ix.HIGHWAYS = ramps.HIGHWAYS`, ...), `ix.bridgeType = ramps.bridgeType`, `ix.frame` = `ramps.frame` +
  `hwR` / `offset` / `hwX`, `ix.rampEdges` = gore + slipEdges (still returns `edges, tag`), carriageway loop ->
  `ramps.carriageways`. `tuned` stays local in ix (dev keys `ixClear`, `ixGoreRun` resolved before the call).
- `tests/square_roundabouts/test_ramps.lua`: aliases are the same tables; frame numbers; gore nodes / tags /
  run (GORE_SLOPE wins on the large highway); gore + slipEdges equal a verbatim copy of the pre-7a
  `ix.rampEdges` for every layout x highway x level (72 slip roads); slipEdges orientation; carriageways
  for arbitrary gore lists (bridged segment index counts from the west on both carriageways); bridge half;
  list.
- `tests/square_roundabouts/test_base_interchanges.lua` (reference only, skipped without `.cache`): runs the
  base `updateFnCloverleafInterchange` / `updateFnDiamondInterchange` with a small vec3 /
  street_util_serialized port and prints:

| base | loop min radius | loop length | peak / avg grade | weave (EB) |
|---|---|---|---|---|
| cloverleaf 2-lane S / M / L | 24.4 / 30.9 / 28.2 m | 153 / 159 / 167 m | 10.1-10.3 % / 4.7-5.2 % | 74 / 94 / 114 m |
| cloverleaf 3-lane S / M / L | 26.0 / 31.1 / 27.3 m | 154 / 161 / 169 m | same | 84 / 104 / 124 m |

  Diamond (2-lane / 3-lane, S / M / L): terminal (both ramps of a side + cross road) at |y| 45-55 / 50-60 m
  = the cross road bridge's end (bridge 90-120 m long, much longer than our `2 yb` of 38-66 m); ramp
  carriageway node at |x| 70-90 / 75-95 m, 4.0 m outside the carriageway centre; ramps 77-106 m, peak grade
  10.9-15.2 %, average 7.6-10.5 % (2-lane small is the steepest: 15.2 % peak). These confirm the research
  table's numbers (its loop-numbers and diamond rows).
- R14 (A/B naming) confirmed: Wikipedia "Partial cloverleaf interchange", Naming: A = the two ramps meet the
  freeway *ahead* of the crossing road, B = *beyond*; "in A2 the loop ramps serve as on-ramps and the
  directional ramps as off-ramps; in B2 the roles are reversed"; A4 = exit, loop on-ramp, directional on-ramp.
  Matches section 1. AB2 appears there only as "parclo AB2 or folded diamond" (both quadrants on one side of
  the crossing road), consistent with our AB2.

**Deviations.** Golden test split into two files (speed, above). `ramps.gore` takes a 7th argument `z` (the
plan's signature had no height; m and g sit at the carriageway height) and stores `io`, so `slipEdges`
needs no `io` argument. `ramps.carriageways` takes `cwNodes[cw] = {xs, tags, bridged}` (tags already
prefixed; `false` = untagged), so no `tagPrefix` argument. Channel goldens use the shipped grid's Islands
{None, Paved} only (as test_short_edges; Grass has the same roads).

**For 7b.** `ramps.gore` puts G towards the junction (`m[1] - before * run`); a loop gore needs the same, the
loop's arc starts at G heading along `head`. `slipEdges` shares the G and head tables between the two edges
(as before; `geom.mirrorX` makes copies, so sharing is safe). `carriageways` counts `bridged[seg]` from
the west for both carriageways. Pre-existing, not 7a: `make test MOD=mods/square_roundabouts_probe` has 1
failure on clean HEAD too ("main axes match square_roundabouts.con.lua": axis 6 expects `sqrb_arm_type`,
gets `sqrb_centre`): the probe's main axis order lags the main `.con.lua`; fix in 7d with the probe work.
Gate timings: `make test MOD=mods/square_roundabouts` 143 passed in 126.8 s wall (slowest file
test_through 126 s; the new golden files 30 s / 43 s run alongside); check 0.5 s; validate OK.

## Phase 7b notes (2026-10-09)

**Done (no menu entry, no revision bump, description.html untouched; existing goldens pass unchanged).**
- `square_roundabouts_highway.lua` (new, pure): `hx.readParams`, `hx.frame`, `hx.layout`, `hx.quadrant`
  (canonical SW kinds "off" / "A"), `hx.place` (SE / NW = mirror-x + reverse every edge, NE / NW = rotation),
  `hx.fits`, `hx.plan`, `hx.build`. Quadrant table `hx.TYPES` (A4, B4, A2, B2, AB2, Diamond = Type indices 1-6),
  `hx.CANONICAL`, `hx.MIRRORED`, `hx.ROTATED`.
- `square_roundabouts_ramps.lua`, additions only (ix does not call them): `goreEdge(gore)` (= slipEdges' gore edge),
  `arcEdges(centre, r, a0, sweep, from?, to?)` (fewest <= 90 deg circle edges, `geom.hermiteScale` handles),
  `profile(edges, z0, z1)` (smoothstep by plan length, tangent z = slope x plan tangent length), `gradient(edges)`
  -> plan, avg, peak, `loop(gore, r, termTag, zTerm)` (stub + clockwise half circle + gore, canonical SW loop-on).
- Tests: `test_highway.lua` (15 tests: one sweep test per type so the runner shards them, 384 builds each =
  every highway x level x side x Size x cross {1, 3, 4, 6} x ramp length {120, 180}; no forced plan, Size kept, tags
  snapped, edges >= MIN_EDGE, engine model (both traffic sides since the 7b review), heights, bridges
  at 8 m, every ramp one terminal end + one carriageway end, continuous position and 3D tangent along each ramp,
  climbs the full 8 m with flat ends, gradients, loop radius = R and sweep = -pi (right turns; +pi left-hand),
  gore merge rule, overlaps + `levelSkip(7)` on 96 builds per type (right-hand, cross 3 / 4, every Size); gore order per carriageway per type both sides
  and levels; quadrant symmetry exact to 1e-9; LHT = mirror; every param changes the build; plan minimums;
  `fits` rejects a short diamond ramp; a never-fitting dev spec is flagged `forced`). `test_ramps.lua` +4 tests
  for the new helpers. `test_short_edges.lua` gains the `highway` entry (`G.highwaySweep` in golden.lua, 2,304
  builds, year 1969): shortest edge 10.0 m, closest nodes 10.0 m, latest yearFrom 1940.
- Sweep numbers: parclo diagonals avg <= 5.2 %, peak <= 7.3 % (shortest climb 153 m); loops avg <= 6.5 %, peak
  <= 9.7 % (shortest 124 m); diamond ramps avg <= 9.1 %, peak <= 13.7 % (shortest 88 m, ix-like); smallest free
  length 10.0 m (parclo) / 13.0 m (diamond; 25.5 m was the overlap subset only); separation at crossings 8.0 m. `hx.build` mean 1.1-1.3 ms (parclo),
  0.34 ms (diamond), max ~15 ms (first calls / GC; target < 5 ms met on the mean). No shipped param grows the Size
  or the diamond's ramp length.

**Geometry as built (right-hand frame, SW; everything else by symmetry).**
- Parclo: loop centre (-dx, -(yg + R)), yg = corr + hwRamp + GORE_GAP; yTi = yg + 2R, yTo = yTi + TERM_GAP (30).
  dx = ceil(max(MIN_EDGE, R + hwRamp + hwX + clear, run + xCross [+ MIN_EDGE highway over])), xCross =
  ceil(hwX + clear) (= the highway bridge half, tested): the loop band keeps `clear` from the cross road band and the
  loop's merge node (|x| = dx - run) is never under the cross road bridge (R10 resolved by construction).
- **Deviation: the A-quadrant diagonal is not one climb edge.** A single Hermite S from G to T_o cannot wrap a circle
  (it cuts the loop for every shipped ramp length). It is: gore (ramps.gore, as ix), a level straight 1 m beside the
  carriageway band when the ramp length is above the minimum, a quarter turn right of radius R, a 90 deg arc
  concentric with the loop (Ro = R + TERM_GAP, so loop and diagonal kerbs are 21 m apart everywhere), then a straight
  east (length dx) into T_o; the height change runs over quarter + arc + straight (`ramps.profile`).
  Consequence: **the parclo minimum ramp length is xmMin = dx + Ro + R + run = 155-272 m**, above the slider's
  120-180 m except with 25 m loops; ramp length never lands in (xmMin, xmMin + MIN_EDGE) (that would leave a level
  straight under 10 m). Footprint: default A4 440 x 311 m (arms included), largest (60 m loops, large highway,
  town large) 603 x 421 m (R12's estimate was ~400 x 300).
- Plain diagonals ("off" / "on", diamond and the 4-quadrant parclos' straight ramps): exactly ix's slip road
  (`ramps.gore` + `ramps.slipEdges`), arriving / leaving T_o along +-x.
- Diamond: yTo = yClear + hwRamp + distance (0 / 15 / 30 / 50): the ramp band clears the highway by `clear` at the
  terminal (plan said "yb + Size"; the extra hwRamp keeps the CLEAR rule). The cross road bridge ends at yClear, or at
  T_o when that would leave an edge under MIN_EDGE (Compact: the base diamond's terminal-at-bridge-end).
- Lists: roles `highway`, `cross` (between the outer terminals; the middle edge is the bridge for "Road over"), `arms`
  (beyond T_o), `ramps`. Tags: terminals `sqrb_hx_x{s,n}_{o,i}`, cross bridge ends `sqrb_hx_x{s,n}_b`, gores
  `sqrb_hx_<quad>_{d,l}`, highway bridge ends `sqrb_hx_{s,n}_{bw,be}`.
- Other deviations: psi (loop join angle) is fixed at 90 deg and there is no ramp-x override (`hxLoopJoin`, `hxRampX`
  not implemented). `hx` reads `hxClear`, `hxGoreRun`, `hxTermGap`, `hxLoopRadius` from `spec.dev`, but they are
  **not** in `geom.DEV_KEYS` yet (7d adds them with ranges; test_dev untouched). The plan's "exactly the cross road x
  carriageway crossings" is tested as "only cross road / arms x highway pairs, at least 2": `levelSkip`'s disc test also
  counts a carriageway edge ending at a loop merge node 8 m beyond the cross road band, and the compact
  highway-over diamond's arms.

**Open questions for the probe (7d).** Loops of 25 m on `highway_new_small` (R2); TERM_GAP 30 m (R1; search
`hxTermGap` 15-40); the loop merge node only `clear` (8 m) beyond the cross road band (dx - run = xCross on wide cross
roads, road over and highway over); the compact diamond's 4-way terminal at the bridge end; the wrapped diagonal's
level straight 1 m beside the carriageway band (long ramp lengths); footprint up to 603 m and ~35-40 edges (R12);
AI behaviour on 25 m loops (R3).

**For 7c.** Script: `result.build(hx.build(hx.readParams(params)))` (module
`square_roundabouts_highway.lua`, returns the `geom.build` list format with `edgeType` / `edgeTypeName` on bridge
lists). `.con.lua` params in this order, keys from `hx.PARAM_KEYS`: type `sqrb_hx_type` (6: A4, B4, A2, B2, AB2,
Diamond = `hx.TYPES[i].name`), highway `sqrb_ix_highway` (3), level `sqrb_hx_level` (2: Road over highway, Highway
over road), cross `sqrb_ix_cross` (6, `geom.ARM_TEMPLATES` labels as ix), size `sqrb_hx_size` (4: Compact, Standard,
Large, Very large = `hx.LOOP_RADII` / `hx.TERMINAL_DISTANCES`), ramp length `sqrb_hx_ramp_length` (4:
`hx.RAMP_LENGTHS`), arm length `sqrb_ix_arm_length` (4: `hx.ARM_LENGTHS` = `ix.ARM_LENGTHS`), direction
`sqrb_direction` (2). Defaults = readParams fallbacks: 1, 2, 1, 2, 2, 2, 1, 1. `availability.yearFrom = 1940`. Then
switch the `highway` entry of `test_short_edges.lua` ENTRIES from its inline `updateFn` / `yearFrom` to `con` /
`script`. Tooltips: Size means loop radius (parclo) or terminal distance (diamond); ramp length is a minimum that
parclos with loops over 25 m always exceed (decide whether to say so or re-define it for parclos).

## Phase 7c notes (2026-10-09)

**Done (no revision bump, description.html untouched; the four existing entries' goldens pass without re-recording,
their four icons and previews byte-identical).**
- `square_roundabouts_highway.con.lua` (new): "Highway Interchange", menu order 3014, `yearFrom 1940`, params in
  section 2's order with the keys of `hx.PARAM_KEYS`, defaults = `hx.readParams` fallbacks, no
  `checkEnabledScript`, no dev keys, tooltip lines <= 62 chars. `square_roundabouts_highway.script.lua` (new): exports
  only `updateFn` = `result.build(hx.build(hx.readParams(params)))`. The existing `square_roundabouts_result.lua`
  maps hx's lists unchanged (no extension needed).
- Icon `square_roundabouts_highway@2x.tga` (240x150, 32-bit BGRA, as the others) and hover preview
  `square_roundabouts_highway_preview@2x.tga` (720x405, 24-bit BGR, as the captured previews), both from
  `tools/render_icon_square_roundabouts.py` (`render_highway`): the default parclo A4 drawn from its real edges
  (`HIGHWAY_EDGES`, dumped from `hx.build(hx.readParams({}))`). The preview is a placeholder until an in-game capture
  exists (then move it to `render_preview_square_roundabouts.py`). The tool re-rendered the four existing icons
  byte-identical (no git diff).
- Tests: test_highway gains the ".con.lua" test (name, icon, preview, script, order 3014, yearFrom, keys `sqrb_hx_`
  or shared, UI order, value counts, shared keys = the Roundabout Interchange's values, defaults = readParams, no
  dev key, no checkEnabledScript, tooltip line lengths, script exports only updateFn, every node free, one bridge
  list for both levels, steel / concrete by year); the "every param changes the build" test now checks every
  param value for every type at the defaults and at the largest layout, plus ramp length = shortest + extra exactly
  for every type x Size x value. test_short_edges' `highway` entry now loads the `.con.lua` / `.script.lua`
  (2,304 builds, latest yearFrom 1940, shortest edge 10.0 m).
- TESTING.md section 16 (the checklist below with the new Ramp length values).

**Ramp length decision.** The 7b slider (absolute 120-180 m, a minimum) was dead for every parclo with loops over
25 m: the wrapped A-quadrant diagonal needs 155-272 m. The slider is now **extra length over the type's shortest
ramp**: values Shortest, +20, +40, +60 m (`hx.RAMP_EXTRAS`), default **Shortest**. Shortest = the layout minimum
`xmMin` for parclos (unchanged geometry, so the default A4 is still 440 x 311 m and the parclo default builds what
7b built) and `hx.DIAMOND_RAMP_MIN` = 120 m for the diamond (its geometric minimum, 60 m, is far too steep), so the
diamond's four values build exactly 7b's 120 / 140 / 160 / 180 m (its default moves from 140 to 120 m; 7b sweep:
avg <= 9.1 %, peak <= 13.7 %, inside the base diamond's 7.6-10.5 % avg). `hx.rampStart(spec, f, size)` gives the
plan's start; the plan still grows it in 10 m steps if a layout does not fit (never for shipped params, tested).
On a parclo the extra length is a level stretch 1 m beside the carriageway band before the wrapped diagonal turns
(more room to leave / join), and it lengthens the straight diagonals' climb; on the diamond it flattens the ramps.
The key stays `sqrb_hx_ramp_length` (never shipped). Built output gains `xmMin`. Footprint: default 440 x 311 m;
largest at Shortest / 30 m arms 603 x 421 m; everything at maximum (60 m loops, large highway, town large, +60 m,
60 m arms) 783 x 481 m.

**Deviations.** Own hover preview (placeholder drawn from the geometry) instead of reusing the interchange's capture,
which shows a roundabout. Ramp length redefined (above). TESTING.md 16 item 2 / 5 use the new values.

**Quick optional in-game first look (2020 save, flat ground).** 1) The menu entry after Roundabout Interchange,
its icon and the preview on hover, the eight params and tooltips. 2) Place the default (Parclo A4): it places, the
cross road on one concrete bridge, two loops (SW / NE), the two loop-quadrant exits wrap around their loops.
3) Diamond with defaults (120 m ramps): places, climbs look acceptable. 4) Parclo A4 with Ramp length +60 m: the
exits leave the highway 60 m earlier. 5) Drive a few vehicles through (an exit, a loop on-ramp): do trucks crawl on
the 35 m loops? Anything refused or odd: note type, params and the error, and send it before the probe (7d).

**Gate timings (this Mac, game running).** `make check` 0.8 s (20 files, 0 errors); `make validate` 0.05 s OK;
`make test MOD=mods/square_roundabouts` 174 passed, 0 failed in 45.9 s wall; `make test
MOD=mods/square_roundabouts_probe` 46 passed, 1 failed (the known "main axes match" failure, 7d) in 10.6 s.

## Phase 7d notes (2026-10-09)

**Done (DEV ONLY probe extended; no revision bump of either mod; the shipped geometry is unchanged: the
existing goldens and `test_entries_unchanged` pass without re-recording).**
- Known probe failure fixed: test_grid "main axes match square_roundabouts.con.lua" (`main axis 6: expected
  sqrb_arm_type, got sqrb_centre`). Cause: the `.con.lua` shows "Arm road" above "Through the centre" (menu
  order), while `grid.MAIN_AXES` is in **replay key order**, which is frozen: every recorded `m:` key
  (`probe_*.csv`, `gen_roundabouts_tuning.py` `MAIN_ORDER`, `verdicts.lua` `MAIN_ORDER`) has the centre before
  the arm road. Reordering the axes would have broken every old key, so the test was wrong, not the grid:
  it now matches main axes to the `.con.lua` by key and checks the order against the generator's `MAIN_ORDER`
  (+ through road).
- Main mod (only edit): `geom.DEV_KEYS` / `DEV_RANGES` gain `hxClear` {0, 30}, `hxGoreRun` {5, 120},
  `hxTermGap` {10, 80}, `hxLoopRadius` {10, 120} (`sqrb_dev_hx_*`); comment in `hx.readParams`. test_dev:
  "dev highway" (shipped values as overrides = shipped build, each key changes only its part, the diamond
  ignores the loop keys, hx and ix ignore each other's keys) and the highway `.con.lua` in "no dev key".
- Probe: entry `highway` (tag `h:`, `grid.HIGHWAY_AXES` in `.con.lua` order + pseudo axis year), `grid.DEV` /
  `DEV_ORDER` + the four keys, subsets **p7_hx_all** (912 combos) and **p7_hx_search** (66 jobs, 504 calls;
  PROBE.md "Phase 7 runs"), `smoke` + the highway default; `geomInfo.highway` (effSize, effR, xm, term =
  `yTi/yTo`, bridge, forced, edges; new R/T fields `xm`, `term`); START field `highway=`; one INFO line per
  highway street template at setup (R3/R4: maxSlope, maxSlopeShape, maxSlopeBuild, minCurveRadius,
  minCurveRadiusBuild, speedCoeffs, lane speeds; `engine.describeTemplate`, read only, pcall per field).
  `mod.json` subset list + tooltip (appended, older indices unchanged). `tools/parse_probe.py`: highway AXES /
  GEOM columns, report section (type x highway / level / size / cross road, bridge type by year), dev fields,
  a `fixed` column in the grid search table when jobs carry one (the loop radius jobs).
- Deviations from the plan: no `hxLoopJoin` / `hxRampX` (not implemented in hx, 7b); the parclo search adds
  `hxGoreRun` {30, 20} (R9); the loop radius search is its own job per base combo (`fixed` hxTermGap = 30, so
  its job id differs from the gap search's); the sweep uses the shortest ramps (7c redefined Ramp length)
  plus +60 m at the defaults. `verdicts.lua` `V.hx` and `gen_roundabouts_tuning.py` `hx_table` are 7e's (they
  need the results).
- Tests (probe 47 -> 54): highway axes vs `.con.lua` + hx tables (shared keys = the interchange's labels),
  default key `h:1,2,1,2,2,1,1,1,2`, p7_hx_all size / coverage, every p7_hx_all combo sane + unforced + no
  growth + bridge by year, p7_hx_search jobs / candidates / call bound, every candidate reaches `hx` exactly
  (`readDev` round trip, frame.clear / goreRun, Ro - R, R) and stays sane, the shipped candidate = the shipped
  build, the highway R/T line fields, the template INFO line with a stubbed `api.res.streetTemplateRep`.
  parse_probe.py checked on a synthetic log (both subsets).

**Run instructions for the user (details: PROBE.md "Phase 7 runs").**
1. `make link`. TF3, the flat test map (flat, empty, centre on land, **year 2020**, right-hand traffic).
   Enable Better Roundabouts (this build) + DEV Roundabouts Probe. Probe settings: Run the probe **On**,
   Subset **p7_hx_all**, Start delay **15 s**, Combos per update **8**, Position **0 / 0**, Proposal context
   **None**, Log placeable combos **On**.
2. Load, pause, wait for `[SQRB_PROBE] END subset=p7_hx_all` (~20-60 s after the delay; PROGRESS lines give
   the ETA). The START line must show `highway=square_roundabouts::/...highway.con`.
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p7_hx_all.log`
3. Reload with Subset **p7_hx_search** (same settings); wait for END (~10-30 s) and
   `INFO dev override check (...): overrides reach the updateFn`;
   `cp ... stdout.txt plans/square_roundabouts/probe_p7_hx_search.log`.
4. Send back the two `.log` files (or say they are in `plans/square_roundabouts/`). Anything odd (a crash,
   an ERROR line, END missing): the last 50 `[SQRB_PROBE]` lines of stdout.txt.
5. Disable the probe afterwards.

**Turning the logs into reports (7e, or the user).**
- One command for both: `make probe-report` (writes everything below and prints a refusal digest).
- `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p7_hx_all.log` ->
  `probe_p7_hx_all.md` / `.csv`.
- `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p7_hx_search.log --fresh` ->
  `probe_p7_hx_search.md`, `probe_p7_hx_search_jobs.csv`, `probe_p7_hx_search_trials.csv`.
- `grep "street template" plans/square_roundabouts/probe_p7_hx_all.log` -> the R3/R4 template limits for
  docs/findings.md (with the date).
- If a log holds more than one run: `--list`, then `--run N`.

**Unverified (the run tells).** That `api.res.streetTemplateRep.get` returns the documented fields on the GUI
thread (else the INFO line shows `-`; harmless); the real rate (estimated from the Roundabout Interchange's
~20 ms per call); the devCheck only proves `sqrb_dev_*` reach the main entry's updateFn: the highway path is the
same (`hx.readParams` -> `geom.readDev`), and different costs between a search's candidates confirm it.

**Gate timings (this Mac).** `make check` 0.6 s (main, 20 files) / 0.8 s (probe, 11 files), 0 errors;
`make validate MOD=mods/square_roundabouts` 0.06 s OK; `make test MOD=mods/square_roundabouts` 175 passed,
0 failed in 44.7 s; `make test MOD=mods/square_roundabouts_probe` 54 passed, 0 failed in 10.5 s.

## Phase 7e notes (2026-10-09)

**Offline part done (no revision bump, description.html untouched; the four older entries' goldens and
icons unchanged; the default Highway Interchange build unchanged, so its icon and preview are byte-identical).**

**Cause.** p7_hx_all: 847 / 912 placed; all 65 refusals "Construction Not Possible", exactly the parclos on the
**large highway, highway over road, Size Compact / Standard** (25 / 35 m loops), every cross road, both years,
+60 m ramps too. The search could not rescue them because none of its candidates moved the one dimension
that differs: the plain carriageway piece between each loop's carriageway (merge) node and the highway
bridge's end. dx (the loop's stub) is `max(R + hwRamp + hwX + clear, run + xCross + MIN_EDGE)`; for small
loops the second term wins, so the merge node sits MIN_EDGE beyond the bridge end. On the large highway the
gore run is 32.5 m (GORE_SLOPE x lateral, above GORE_RUN), dx = ceil(62.5) = 63, so the piece is **10.5 m**;
45 m loops have dx = 70 (the first term), piece **17.5 m**, and placed; 60 m loops 32.5 m, placed. Small and
medium highways place with 10 m. hxClear (moves bridge and node together), hxGoreRun (below the large
highway's 32.5 m run: no effect), hxTermGap and hxLoopRadius 20-30 m (dx stays at the second term) all left
the piece at ~10.5 m: hence 0 accepted in the 10 large / hw_over jobs. (The engine evidently needs more
free carriageway between a junction node and a bridge end on the 23 m wide large highway.)

**Fix (geometric, not a growth rule).** `hx.BRIDGE_PIECE = { 10, 10, 17.5 }` (per highway; `f.bridgePiece`
in `hx.frame`): for "Highway over road" the loop merge node keeps that piece to the bridge end (dx rule and the
`fits` gore check). Small / medium stay at MIN_EDGE (unchanged builds); on the large highway 25 / 35 m loops
get dx = 70, so the carriageway, loop merge nodes and bridge ends within 40 m of the cross road are exactly
the placed 45 m loop's (tested), while the user's Size is kept (a growth rule, Size -> 45 m, would have shipped
a placed layout but ignored Compact / Standard). Cost: the large-highway hw_over parclo grows 7 m per side
(xm 175.5 -> 182.5 at Compact). No `hx` tuning-table part: one rule per highway, nothing per combo, so
`gen_roundabouts_tuning.py` is unchanged (the existing tuning parts are untouched).

**Evidence / tests.**
- test_highway: "highway over road: loop carriageway nodes keep hx.BRIDGE_PIECE" (every parclo x highway x
  cross {1, 3, 4, 6} x Size: piece >= BRIDGE_PIECE, small / medium unchanged at 10 m; large 25 / 35 m: dx and
  the near-bridge carriageway = the 45 m layout, Size kept).
- Highway golden: none existed (7c/7d only swept it in test_short_edges), so 7e records one:
  `test_entries_unchanged_highway.lua` (4 parts), groups "highway t<type> h<highway> v<level> y1969/none" over
  `G.highwaySweep` (72 groups, 4,608 builds, ~10 s) in golden_entries.lua. Recorded with the fix reverted
  first: exactly the 10 groups t1-5 h3 v2 (both years) differ, nothing else; the channel / interchange lines
  are byte-identical.
- Engine replay: `V.hx` (verdicts.lua) + test_engine_verdicts "(highway)": every p7_hx_all row (plus
  `probe_p7_verify.csv` once it exists) rebuilt; layouts compared by the probe's fields (effSize, xm, yTi/yTo).
  Today: 0 problems, 65 known gaps `hx` (the refused combos now ship an unprobed layout; p7_verify closes
  them, or turns a refusal into a test failure). A synthetic test keeps it honest.
- Street template limits and the bridge-end finding: docs/findings.md (2026-10-09).

**Loop size decision (R3): defaults unchanged (Standard 35 m, Compact 25 m).** The INFO lines give
`minCurveRadius = 44`, `minCurveRadiusBuild = 60` for all three highway templates, but per the wiki
(tracksstreets.md) those are the drag tool's limits (snapping / dragging), not a placement limit (every 25 m
loop placed) and not a speed: `speedCoeffs` is empty, so street curve speed is engine-internal and unknown.
The base game's own cloverleaf loops are 24-31 m. Moving Standard to 45 m (>= 44) would push the terminals 20 m
further out and lengthen every ramp ~30 m, on a guess. Open for the in-game test (TESTING.md 16.6): truck speed on 25 / 35 /
60 m loops; if 35 m crawls and 45 m does not, move Standard to 45 m (the slider values are labels: free before
release; the default build, golden and icon then change on purpose). New 16.10 question: can the player edit a
loop under 44 m afterwards?

**p7_verify (user run; PROBE.md "Phase 7e: p7_verify").** 160 combos, ~5-15 s: parclos x large highway x
highway over road x Compact / Standard x 6 cross roads x 1969 / 2020 (120), +20 / +40 / +60 m ramps (30),
left-hand traffic (10); covers all 65 refused combos (tested). Steps: `make link`; TF3 flat test map, 2020, RHT;
Better Roundabouts + DEV Roundabouts Probe; probe Subset **p7_verify**, other settings as p7_hx_all (On, 15 s,
8 per update, 0 / 0, context None, log placeable On); wait for `END subset=p7_verify`;
`cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p7_verify.log`;
`make probe-report` (now picks up every p7 log present); `make test MOD=mods/square_roundabouts ARGS="-f
engine_verdicts -k highway"`: the 65 `hx` gaps should vanish. If some still refuse: the bridge piece needs
more than 17.5 m only at Compact (unlikely: identical near-bridge geometry) or the loop itself is the problem;
then a growth rule Size -> Large for that case is the fallback.

**Remaining open items for the in-game test.** TESTING.md 16.4 (large highway, highway over road, Compact
places), 16.6 (loop speed, R3; decides Standard 35 vs 45 m), 16.10 (editing loops under 44 m), and the rest of
section 16 as before.

**Gate timings (this Mac).** `make check` 0.5 s (main, 20 files) / 0.5 s (probe, 11 files), 0 errors;
`make validate MOD=mods/square_roundabouts` 0.05 s OK; `make test MOD=mods/square_roundabouts` 182 passed, 0
failed in 45.2 s; `SQRB_FULL=1 make test MOD=mods/square_roundabouts` 182 passed, 0 failed in 162 s;
`make test MOD=mods/square_roundabouts_probe` 55 passed, 0 failed in 10.9 s.

## Phase 7e fix-up: placement in game (2026-10-09)

**Report.** In game the Highway Interchange parclo sometimes shows a red "Construction Not Possible" (no other
reason, whole layout red, no Lua error) on ground that looks flat, and places elsewhere. Pinned case: Parclo B4,
Highway Small, Road over highway, Cross road Country large, Compact, Shortest ramps, 30 m arms, 2020, Height 0.0,
open grass with a few trees: **refused at Rotation 0, placed at Rotation 350 on the same spot** ($1,225,432).

**Offline findings (no cause proven; no change to the main mod).**
- **Not the geometry, not a 7d / 7e regression.** That exact combo (`h:2,1,1,6,1,1,1,1,2`) placed in p7_hx_all
  (world 0 / 0, identity transf, context None, cost 1,167,500). The 7e highway golden was recorded with the fix
  reverted and differed only in the large-highway / highway-over-road groups, so this combo and the default
  (medium) parclo build exactly what 7c / 7d built; 7d added only dev keys (tested: shipped values = shipped build).
  `highway.lua` / `ramps.lua` are untracked, so the goldens are the only history.
- **Not a node-merge float issue.** Checked on the built edgeLists (`result.build`) of the B4 combo, the default
  parclo and the diamond: no two nodes closer than 5 cm without being exactly equal, no tagged / untagged node
  at the same spot (basics.md: those don't merge), no two different tags at one spot. The only offset joins are
  the intended same-tag slip-road merges, 4 m apart (`ramps.MERGE_OFFSET`, the base diamond's
  entranceExitOffset).
- **Terrain handling is the base game's.** Base cloverleaf / diamond (`street_constructions.script.lua`) also
  emit absolute heights (0 / 8 m) in the construction frame, all nodes free, `groundFaces = {}`, `models = {}`, no
  `terrainAlignmentLists`; the highway entry's result has the same shape (`square_roundabouts_result.lua`, no
  island). The base cloverleaf is about as large (about 500 m). So "uneven flat ground" alone should not
  differ from the base entries; the cross road and arms stand at 8 m to their free ends (yTo + arm = 126.5 m
  out), as in the base layouts.
- **Rotation 0 vs 350 on the same spot** changes only the world orientation: the 0 degree footprint covers
  other ground and objects (the 193 m highway ends move about 33 m sideways at 350) and its edges are axis
  aligned. Axis alignment alone does not refuse it (the probe placed it at 0 degrees, and the base and Roundabout
  Interchange entries default to 0). Left: (a) the player context's checks (terrain alignment, street-graph
  cleanup, buildings / fields), which no probe run has ever used (every log: `context=none`), (c) something on the
  0 degree footprint only, or an axis-aligned quirk at that world position.
- `errorState.messages` in every probe log: only "Construction Not Possible" (street-graph rejection, 33,897 rows)
  and "Collision" (530). A terrain or collision cause would usually show its own message or highlight, so the
  run below logs collision ids and the terrain under every node as well.

**Probe extension (DEV ONLY `square_roundabouts_probe`; PROBE.md "Phase 7e fix-up: p7_spot").**
- New setting **Position** (`sqrb_probe_pos`): X / Y (as before), **Camera centre**
  (`api.gui.camera.getCameraData`, gui.d.tl:434, GUI thread as the probe already is) or Mouse
  (`api.gui.mouse.getTerrainPosition`, gui.d.tl:262); read once at start, both logged in an INFO line.
- New subset **p7_spot** (106 calls, ~5-10 s): the B4 combo above, the default parclo (A4) and the diamond, each at
  rotations 0, 0.5, 1, 10, 90, 180, 350 degrees x contexts none / player (player only, as the bridge window) /
  terrain (player + checkTerrainAlignment) / full (all four flags, the old "Player"), plus origin shifts (0.5, 0.5),
  (20, 0), (0, 20) m at 0 degrees (none, full); control: the Roundabout Interchange default at 0 / 350, none / full.
  R lines gain `rot ctx dx dy`; one **D line** per call: origin, messages, collision ids classified
  (`-3:new` = an entity of the proposal itself, else street / edge / node / con(file) / townbuilding / field /
  models ...; `entityExists` first), building ids, auto removals, the proposal's terrain cut / fill, and the
  terrain under every node: `terrMin/terrMax` (terrain relative to the origin), `fillMax` / `cutMax` (node above /
  below terrain), `offMap`, `water`.
- Tests (probe 55 -> 58): p7_spot size / places / labels / R fields, other subsets without places; geomInfo.nodes /
  toWorld; evaluate with a place under a stubbed api (transf at 90 degrees, terrain context flags, D line fields,
  camera position). `tools/parse_probe.py` reads a p7_spot log (rot / ctx / dx / dy columns; D lines are read
  with grep).

**Reading the run (next agent).** Per key, ok over rot x ctx:
- fails only with `terrain` / `full` -> the terrain-alignment check: D `terrMin/terrMax`, `cut/fill`; then compare
  with the base cloverleaf at the same spot, and consider `terrainAlignmentLists` / lower embankments.
- fails at 0 / 90 / 180 in every context, places at 0.5 / 1 / 10 / 350 -> an axis-aligned quirk at that world
  position (then try a tiny internal rotation of the layout, or nudge the axis-aligned straight edges).
- fails at 0 but places with the 20 m shifts, or `collIds` shows existing entities -> something on that
  footprint (D lists it).
- the Roundabout Interchange control fails too -> the spot, not this entry.

**Gallery images.** `_metadata/1.png`-`9.png` (9.png new) were re-rendered at 12:47:05-13 local time by
another main session (ffe923b3, 19:46:43Z / 19:47:04Z): `make shots MOD=mods/square_roundabouts` after the user
asked to "make this slide the first one in both mods (the where to find it)". No Phase 7 agent did it. Left as
they are. Note for 7f: mod.io galleries are append-only, so moving the "Find it" slide to 1.png only shows on
mod.io if the old media are deleted there first (the runbook's "1-9.png unchanged" check no longer holds).

**Gates.** `make check` 0 errors (main 20 files, probe 11); `make validate MOD=mods/square_roundabouts` OK;
`make test MOD=mods/square_roundabouts` 198 passed, 0 failed (37 s; main mod unchanged, goldens untouched);
`make test MOD=mods/square_roundabouts_probe` 58 passed, 0 failed (9 s).

**Fix-up round 2 (2026-10-09): p7_spot did not reproduce the UI.** The coordinator's run at the user's spot
(camera 411.20 / -514.26, z 0.99; `plans/square_roundabouts/probe_p7_spot.log`, last START block) placed all
106 calls: B4 / A4 / diamond at 0, 0.5, 1, 10, 90, 180, 350 degrees in all four contexts, the shifts, and
the control. Costs match the UI's (B4 at 350: probe 1,222,186 with context none, UI $1,225,432), so it was the
right spot; terrain under the nodes is within -0.4 / +1.8 m of the origin, no collisions. In the UI the same B4 is
red at 0 and green at 350. So the cause is in what the GUI builder (native `ACTION_CONSTRUCTION_BUILDER`,
`construction_react_util.tl:1023`) does beyond makeProposalData(SimpleProposal): it passes its own params
(`height`, `rotation`, underground; `makeConstructionBuilderParams`, `construction_react_util.tl:851-922`), its own
transf (cursor point, not the camera centre), and possibly snapping (`ConstructionDesc.snapping`, read by
undo_tf3_test's DEPOT038 diagnosis) or other checks. Lua cannot see inside the builder, but its
`builder.proposalCreate` event carries the real Proposal + ProposalData (TF3 use: undo_tf3_test). The probe now
logs it (W lines) and replays it with the UI's params / only ours, contexts none / full, plus p7_spot2 (B4 at 0
degrees, 0-8 m origin shifts in 0.5 m steps). PROBE.md "Phase 7e fix-up: p7_spot2 and the construction tool
watcher" has the run and how to read it. Also seen: the run's mouse point (-247 / -574) was 660 m from the
camera centre, so "the spot" for the UI is wherever the cursor was. Gates: check 0 errors (both), validate OK,
main 198 / 198, probe 61 / 61.

**Fix-up round 3 (2026-10-09): the UI proposal reproduces; it is the default A4 and the spot.**
`plans/square_roundabouts/probe_p7_spot2.log`: p7_spot2 placed 578 / 578 (B4 small at 316.53 / -433.04, 0-8 m
shifts). The watcher logged 36 `builder.proposalCreate` events, all identity rotation, all refused ("Construction
Not Possible", critical, coll 0, 38 added segments), and all four replays of the same proposal through
makeProposalData also refused it. So **our own path reproduces the UI**; the builder adds nothing that matters.
- **Params decode to the default Parclo A4, not an off-by-one.** Construction params reach the updateFn
  **1-based**, as the base game reads them (`street_constructions.script.lua`: roundabout
  `captureParams.radii[params.radius]`; cloverleaf `streetType == 1` = the first value, 2 lanes) and as all five
  entries read them (`geom.index`). UI params `sqrb_hx_type=1, sqrb_ix_highway=2, sqrb_hx_level=1, sqrb_ix_cross=2,
  sqrb_hx_size=2, sqrb_hx_ramp_length=1, sqrb_ix_arm_length=1, sqrb_direction=1` = A4, medium, road over highway,
  `ROADS[2]`, Standard, Shortest, 30 m, right-hand traffic = probe key `h:1,2,1,2,2,1,1,1,2` exactly (the probe
  builds the same table: `grid.combo` puts the 1-based index under the same keys). `seed` (0 in the UI, 1 in the
  probe) is read by nothing in the mod. **No earlier probe result is invalid.** The user hovered the default in
  this run, not the B4 of the screenshot.
- **Position-dependent:** the default A4 placed at 411.20 / -514.26 in p7_spot (every rotation and context) but is
  refused everywhere the user hovered, about 100-250 m west / north (x 168-341, y -372 to -593, z 0.6-1.9 m),
  where B4 small places. No collision entity, so terrain or an engine geometry check against the ground.
  Not found offline.
- **Probe round 3:** at the first refused UI proposal the watcher queues a **bisect at that exact transf**
  (`grid.BISECT`, 180 calls, logged as `START subset=bisect`, R + D lines with `rot0`): every type x highway x
  level x Size, the default's cross roads / ramp lengths / arm lengths, the default at 90 / 180 / 270 / 350 / 0.5
  degrees and with the origin at -1 / +0.5 / +1 / +2 / +4 m (`dz`), context full, the interchange control. D lines
  carry the terrain under every node. New subset **p7_watch** (2 calls) starts the watcher without a long sweep.
  Reading: refused only for the medium / large highway or only with loops of some Size -> a layout part vs the
  ground; places with `dz` > 0 but not at 0 -> the terrain (a node or edge under the ground: compare D
  `cutMax` / `terrMax` with the placed rotation); refused for everything incl. the control -> the spot.
- Gates: check 0 errors (both), validate OK, main 198 / 198, probe 62 / 62.

**Fix-up round 4 (2026-10-09): refused only while the construction tool is active.**
`probe_p7_bisect.log`: 106 W events (default A4), all refused with all four replays refused; after Esc the bisect
at the first refused spot (248.76 / -560.21, z 2.15, rot 0) placed 167 / 167, including the identical proposal.
So the refusal depends on transient state while the tool is open, not on terrain or position.
- **(b) our updateFn keeps state: ruled out offline** (scratch harness through `ModRunner`, the default A4 params as
  the UI sends them): no table in the result is reachable from the hx / ramps / geom / result / interchange module
  tables, a second build is identical (serialised to `%.17g`), mutating every number / string of the earlier results
  in place and building other entries (B4, left-hand traffic, the Roundabout Interchange) in between changes
  nothing, and the params table is not modified.
- **Probe round 4 (watcher triage):** for the first three refused and the first placed UI proposal, while the tool is
  active, one **X** line: the same proposal again (`same`, `same2`), moved 3000 m and 600 m in x (`far3000`,
  `far600`), B4 small, the Roundabout Interchange and the main roundabout defaults at the same spot, and the base
  game's cloverleaf there (`cloverleaf`, resource name tried as `infrastructure/street_construction/cloverleaf_interchange.con`
  and with `::/` or `/`; `cloverFile` shows the one found).
  Reading: far placed but same refused -> something at the spot that exists only while the tool is open (its
  preview of the previous frame: hypothesis a); far refused too -> every proposal fails while the tool is active
  (c, a global tool state or budget); the cloverleaf refused too -> the engine / tool, not this mod; only ours
  refused while the small ones place -> overlap with the preview scales with the footprint.
- Gates: check 0 errors (both), validate OK, main 198 / 198, probe 62 / 62.

**Fix-up round 5 (2026-10-09): round 4's "tool active" reading was wrong; only the UI's own proposal is refused.**
`probe_p7_triage.log` + the full stdout.txt timeline: W n=26-31 (23:26:24-25) were logged *while* the bisect
ran (23:26:23-26), so the tool was open during the bisect, and it placed 167 / 167, including the identical
default A4 at the UI's spot and z (596.12 / -777.41 / 1.25). What failed were only the replays made *inside* the
builder's `guiHandleEvent` callback: there a nested makeProposalData of the same .con fails anywhere (same,
same2, far3000, far600, b4small), while other files (Roundabout Interchange, main roundabout, base cloverleaf) place.
That is a reentrancy artifact of the probe, not game state (round 4 triage is now off: `engine.TRIAGE_MAX = 0`).
So: the identical SimpleProposal (file, params, transf) places from guiUpdate, and the builder's proposal is
refused. Difference found so far: the UI street proposal has **38 added segments / 35 nodes**, our build emits
**35 edges / 32 nodes** (tag-merged; checked offline for the default A4 and B4 small). That is three extra
node + segment pairs, i.e. three edges split by the builder. Offline, our edges cross in plan only at the
two intended grade separations (highway under the cross road bridge, dz 8 m), so the splits are not our own
at-grade crossings. Also checked offline: the two .con.lua files share the same shape (same fields,
uiTypes, shared `sqrb_ix_*` keys, defaults), and the updateFn keeps no state (round 4).
- **Probe round 5:** for the first two refused and the first placed UI proposals, **G lines** list the UI's added
  segments / nodes in construction coordinates (inverse of the UI transf) that match none of our edges / nodes
  (`kind=ui`, with type / typeIndex / node ids / tangents), and our edges missing from the UI proposal
  (`kind=ours`, role:ramp:part). A **Y line**, from the next guiUpdate (outside the event): the UI's own
  Proposal (`proposal:clone()`) and our SimpleProposal through makeProposalData, contexts none / full.
  Reading: uiProposal fails and ours places -> the builder's changes (the G lines say which edges it splits
  and where) cause it; both place -> the builder rejects for a reason outside the proposal data.
- Gates: check 0 errors (both), validate OK, main 198 / 198, probe 63 / 63.

**Fix-up round 6 (2026-10-09): the builder merges our level ramp joints; seed 0 vs 1 is the one pass / fail split.**
`probe_p7_diff.log` (24 hovers, all refused). G lines: the UI street proposal (38 segments / 35 nodes vs our 35 / 32)
has our **untagged degree-2 ramp joints at ground level** merged and the edges re-split elsewhere: sw_l / ne_l
loop + level gore (joint +-60 / +-25.5, z 0) -> one curve split at +-78.23 / +-30.62 (z 0.26); sw_d / ne_d gore +
climb (joint +-160 / +-25.5) -> split at +-141.77 / +-30.62; nw_d climb + gore -> 5 pieces. The joints above
ground (loop / stub / climb, z > 0) and the tagged nodes are kept; the carriageway nodes at y = +-13 are the
engine's midpoint of our tagged pair (+-11 carriageway / +-15 slip road), as intended. The level gore beside the
carriageway is lost, which fits a "Construction Not Possible". The Y replay of the UI's Proposal object raised
(makeProposalData takes only a SimpleProposal; removed), and **our SimpleProposal with the UI's params, from
guiUpdate, was refused too**, while every probe proposal so far placed, including the round 4 bisect at a UI's
exact spot and z. Their only difference: **`seed`** (the builder sends 0; `engine:paramsFor` adds 1 when missing).
Nothing in the mod reads `seed` (grep), so the engine's own processing (the merge?) depends on it.
- The Roundabout Interchange also has untagged ground-level degree-2 joints (gore + climb at +-137.66 / +-25.5) and
  places in game; the highway entry's differ in being the level gore between a loop / long climb and the merge
  node, so a merge there changes the shape more. Not proven which merges matter.
- **Candidate fix (DEV key, not shipped): `sqrb_dev_hx_tag_joints = 1` (`hx.tagJoints`)**: a unique tag
  `sqrb_hx_j<n>` on every untagged node where exactly two ramp edges meet (14 on a parclo, 4 on the diamond); positions,
  tangents and order unchanged (test_dev; offline: identical result apart from the tags for A4, B4 small, LHT,
  diamond, large highway over road). Shipping it changes the highway golden on purpose (tags), so it waits for
  the run below.
- **Probe round 6:** Y line (from guiUpdate, tool open) = our SimpleProposal at the UI's transf and params:
  `ours` / `oursFull` (UI seed), `seed1` / `seed1Full`, `tagged` / `taggedFull` (UI seed + tagged joints).
  Subset **p7_seed** (492 calls, camera centre): the default A4 and B4 small at seed 0 / 1 x context none / full
  and seed 0 tagged x none / full; every p7_verify combo at seed 0 full, seed 0 full tagged, seed 1 full.
  Reading: seed 0 refused and seed 1 placed -> the seed triggers it (confirmed without the tool); tagged seed 0
  placed everywhere -> ship tags (make `hx.tagJoints` the default, re-record only the highway golden); tagged
  still refused -> make the geometry merge-proof instead (no level joint: one gore + climb edge, or tag + a
  tangent kink).
- Gates: check 0 errors (both), validate OK, main 198 / 198 (goldens unchanged), probe 64 / 64.

**Fix-up round 7 (2026-10-09): seed ruled out; probe replays during hovering are not evidence.**
`probe_p7_seed.log`: p7_seed placed 492 / 492, seed 0 without tags included, so **seed is not the trigger**
(round 6's hypothesis withdrawn). The UI's 34 hovers were refused; the Y replays (next frame) were refused too.
**Timeline correction:** both logs do show the bisect overlapping the hover session (triage log: W at
23:26:24-25 during the bisect 23:26:23-26; seed log: W at 23:51:04 and :08 around the bisect :04-:07). But the
seed log also has **Y n=2, a refused replay of the same file in the same second the bisect started**. So "the
tool is open" alone does not decide it, and round 5's "only the UI's proposal is refused" was too strong. The
reading that fits every log: **while the builder is working on a proposal of a .con (the mouse moving), any
other makeProposalData of that same file fails** (in the event, the next frame, 3000 m away), other files pass,
and once the builder is idle or closed it passes (the bisect, the sweeps). If so, no replay during hovering
tells us anything about the user's bug, which is only the UI's own refusal. The G lines (merged / re-split
ground-level joints in the UI's street proposal) remain the one concrete difference of the UI's proposal.
- **Probe round 7** (one run answers all three):
  1. **DEV copy** `sqrb_probe_highway_copy.con` (probe mod, generated from the original: identical params,
     availability and updateFn via the main modules; only name, icons, order 3098 and script path differ;
     test_geom keeps it identical). Y `copy` = the UI's params / transf through the copy.
  2. **The Roundabout Interchange in the watcher:** W / G / Y for its UI proposals too (diff against the ix build),
     with `other` = the highway default in the same frame. If the ix's own replays also fail while its tool is
     busy, the per-file failure is normal engine behaviour.
  3. **Each Y twice:** pass 1 (next frame) and pass 2 (about 2 s later, tool idle if the mouse is still), plus
     `probeParams` (the sweep-style params of the same layout) in the same frame. W adds toAddData, removable
     modules and terrain-mod counts (errorState has no other fields: critical / messages / warnings / infos).
  Reading: copy places + ours refused in the same frame -> per-file state (the busy builder); pass 2 places ->
  momentary; the ix's replays refused while its tool is busy too -> normal, so look only at the UI's own
  proposal (its G lines: compare the ix's merged joints with the highway's).
- Gates: check 0 errors (main 20 files, probe 13), validate OK, main 198 / 198 (goldens unchanged), probe 65 / 65.

**Fix-up round 8 (2026-10-09): the highway entry (and its copy) is refused whenever any construction tool is open.**
`probe_p7_copy.log`: highway tool open -> Y ours / oursFull / probeParams / copy / tagged refused on both passes
(next frame and ~2 s later, mouse still), `other` (Roundabout Interchange) placed; Roundabout Interchange tool open
-> its UI proposals placed (10 / 10), its replays placed, `other` (the highway default) refused; no tool -> 167 / 167.
So not per-file builder state: something about the highway build fails while a tool is open. Offline checks (no fix found):
- **State in shared modules (1): none.** One module instance, the real modules, every type x level x direction x
  highway (144 builds) + the interchange + the main entry interleaved: no global written, no undefined global read
  (sandbox `__index` hook); earlier: no result table reachable from module tables, mutation of earlier results and
  interleaved builds leave the next build identical.
- **Order (2): none.** `pairs()` in highway.lua (fits: kinds / chains) only feeds order-independent checks (any
  failure returns false); the sorts (spans, ys, stops, carriageway nodes) have distinct keys for every shipped layout.
- **Globals (3): none read** besides ipairs, pairs, pcall, setmetatable, tonumber, tostring and math.abs / asin / ceil /
  cos / floor / fmod / huge / max / min / pi / sin / sqrt / tan, table.concat / sort.
- **In-game fingerprint (TEMPORARY, remove before release, 7f):** `square_roundabouts_fingerprint.lua`; the highway
  updateFn (and the probe's copy) prints `[SQRB_FP] <label> state=<Lua state id> call=<n> lua= jit= params=... spec=...
  size= xm= lists= edges= tags= tagHash= coordHash= const=` when the text changes (at most 40 lines per Lua state);
  the watcher's W lines add `fpLocal` (the same text built in the probe's state from the UI's params). Reading: a
  different coordHash / tagHash / const / params between the builder's state and the probe's -> the output differs
  by state (then the line says what: params, layout, constants); identical -> our result is the same, so the
  refusal is in the engine's processing of this layout while a tool is open (then the merged ground-level joints
  are the lead: make the layout merge-proof).
- Gates: check 0 errors (main 21 files, probe 13), validate OK, main 199 / 199 (goldens unchanged), probe 65 / 65.

**Fix-up round 9 (2026-10-09): our output is identical in every state; geometry variants to find what the engine dislikes.**
`probe_p7_fp.log`: every `[SQRB_FP]` line for the default params is identical across Lua states and calls (tagHash
1403029998, coordHash 1007231985, const 1983064322, 35 edges, 36 tags) and matches the watcher's `fpLocal`; the UI
params add `constructOpt56=0, constructOpt78=0, state={..}`, which the updateFn ignores. So the engine treats the same
result differently while any construction tool is open (the Roundabout Interchange's included).
- **Offline structure, highway vs Roundabout Interchange vs base:** junctions: the highway's two outer terminals are
  degree-4 (two-way cross road + two one-way `highway_new_small` ramps, straight through), the Roundabout Interchange has
  only degree-3 junctions; but the base diamond has the same two degree-4 terminals (`sn-north` / `sn-south`), so not
  unique. Untagged degree-2 joints at ground level: highway 6 (A4), Roundabout Interchange 4, base cloverleaf has
  degree-2 joints too. Shortest edge 30 m (A4) / 19.5 m (diamond) / 29.3 m (ix); |tangent| / chord 1.00-1.17 in both;
  no edge over 10 % grade; nearest nodes 22 m (A4) / 13 m (B4 small). Nothing decisive offline.
- **Variants (TEMPORARY, `square_roundabouts_hx_variants.lua`, dev key `sqrb_dev_hx_variant` 1-9, one change each,
  applied to the built lists before mirroring):** 1 tag every untagged degree-2 ramp joint; 2 a 3 degree plan kink
  at each level joint (highway height); 3 lift each level joint 0.1 m; 4 merge the two edges at each level joint
  into one; 5 slip-road node on the carriageway node itself (no 4 m merge offset); 6 split each degree-4 terminal:
  the second ramp joins the cross road 15 m further out (two degree-3 junctions); 7 no loop ramps; 8 no ramps;
  9 no cross road arms (7-9 diagnostic). test_dev: all build, finite, edges >= 1 m, each changes the result.
- **Probe round 9:** the first builder event (any square_roundabouts tool) queues a **variant sweep** at its transf:
  `variantsA` at once (tool open) and `variantsB` once no builder event came for 8 s (tool closed): default A4, B4
  small, diamond, A4 highway over road, B4 large highway over road, each at variants 0-9, plus the Roundabout
  Interchange control (51 calls each). R lines carry `variant`. The bisect is off (`engine.BISECT`).
  Reading: pass A shows which variants place while a tool is open (pass B should be all ok): 8 ok but 7 not ->
  the loops; 6 ok -> the degree-4 terminals; 1-4 ok -> the level joints (pick the least intrusive); 5 ok -> the
  merge offset; 9 ok -> the arms' free ends; nothing ok, not even 8 -> highway + cross road alone (bridge, carriageway
  tags).
- Gates: check 0 errors (main 22 files, probe 13), validate OK, main 200 / 200 (goldens unchanged), probe 67 / 67.

**Fix-up round 10 (2026-10-09): test the fixes in the real tool.** `probe_p7_variants.log`: pass A (Roundabout
Interchange tool open) and pass B both placed 49 / 51; only variant 4 (merged level joints) failed, with a Collision
(12 on A4, 8 on B4 small). Variant 0 placed with a tool open, contradicting the copy run, so the probe cannot
reproduce the UI refusal on demand; probing stops here. Two TEMPORARY menu params on the Highway Interchange
(last, not translated; remove before release, 7f): **DEV joint fix** (`sqrb_hx_tmp_fix`: Off, 1 tag joints, 2 kink
3 deg, 3 lift 0.1 m, 5 slip node on carriageway, 6 split terminals; variant 4 left out, it collides) and **DEV parts**
(`sqrb_hx_tmp_parts`: All, No loops, No ramps, No arms), both through `square_roundabouts_hx_variants.lua`
(`hx.TMP_KEYS`, `hx.TMP_FIX_VARIANTS`, `hx.TMP_PARTS_VARIANTS`). Defaults Off / All = the shipped build (goldens
unchanged); the probe's copy con regenerated. Gates: check 0 errors, validate OK, main 201 / 201, probe 67 / 67.

**Fix-up round 11 (2026-10-09): the ramps trigger it.** The user's UI test (probe off, red spot at 0 deg): of DEV joint
fix and DEV parts only **"No ramps"** turned the layout green (corrected from "No arms"); every joint fix, No loops
and No arms stayed red. The two params are replaced by one TEMPORARY param **DEV ramps** (`sqrb_hx_tmp_ramps`,
`hx.TMP_RAMPS_VARIANTS`, variants in `square_roundabouts_hx_variants.lua`, dev key range 0-19): Off; diagnostics
Only loops (10), Only off-ramps (11), Only on-ramps (12), Only SW quadrant (13), No gores (14: ramps end short of
the carriageway), No terminal edges (15: short of the cross road); candidate fixes FIX town one-way ramps (16:
`town_new_one_way_small` instead of `highway_new_small`), FIX split long climbs (17: every non-gore edge over 60 m
in two exact Hermite halves), FIX terminal angle 10 deg (18), FIX gore angle 5 deg (19); and No ramps (control, 8).
Note: the Roundabout Interchange's slip roads use the same `highway_new_small` template, so 16 tests the template
anyway. test_dev: every value maps, builds finite, edges >= 1 m, changes the result (A4, B4 small, diamond, LHT).
Defaults keep the shipped build (goldens unchanged); the probe's copy con regenerated.
Gates: check 0 errors, validate OK, main 201 / 201, probe 67 / 67.

**Fix-up round 12 (2026-10-09): the on-ramp diagonals' merges.** UI (probe off, failing spot, 0 deg): green for Only
loops, Only off-ramps, Only SW quadrant, No gores, No ramps; red for Off, Only on-ramps, No terminal edges, Town one-way
ramps, Split long climbs, Terminal angle 10, Gore angle 5. In A4 the on-ramps are the loops sw_l / ne_l and the
diagonals se_d / nw_d; loops alone place, so the diagonal on-ramps (with their gores) are implicated. Offline:
edge directions are right (se_d gore (160, -25.5) -> (190, -15) with the eastbound carriageway, nw_d mirrored;
carriageways in driving order; merge tangents parallel to the carriageway). What sets se_d / nw_d apart: they merge
**30 m (the Arm length) before the highway's free end** (loop on-ramps merge mid-highway); B4 and the diamond have
the same. But the Roundabout Interchange's on-slips also merge 30 m before its free ends and place, so unproven;
the existing **Arm length 60 m** is a direct UI check. DEV ramps values now (variants 20-27): Only SE on-ramp, Only
NW on-ramp, SE + NW, south on-ramps (SW loop + SE), FIX highway ends +30 m, FIX merge node 6 m out, FIX split
carriageway 15 m after each on-ramp merge, FIX on-ramp gore +15 m, and the controls Only off-ramps / Only on-ramps /
No ramps. Gates: check 0 errors, validate OK, main 202 / 202, probe 67 / 67.

**Fix-up round 13 (2026-10-09): cause found offline, a negative zero on the SE on-ramp; fixed.** UI: green for Only NW
on-ramp, Only off-ramps, No ramps; red for Only SE on-ramp, SE + NW, south on-ramps, only on-ramps and all four
merge fixes. So **se_d alone** triggers it while its 180-degree twin nw_d places. Edge-by-edge `%.17g` dump: the two
are exact point mirrors, but **se_d's tangents are (+x, -0, -0)** (climb and gore; made by mirroring / negating the
canonical quadrant), nw_d's (-x, +0, -0); no other ramp of any layout has (+x, -0), and the Roundabout
Interchange's are all +0. The construction tool's transf at rotation 0 is `1/-0/0/0/0/1/...` (W lines), i.e.
(cos, sin) = (1, -0): world y = sin * x + cos * y = (-0)(+x) + (-0) = **-0 for se_d only** (nw_d: (-0)(-x) + 0 = +0;
ne_d's (-x, -0): +0). Any other rotation, and the probe's transf (built with +0 sin), give +0, which explains every
earlier "probe places, UI refuses", "a few degrees fixes it" and the position independence. The engine evidently
treats a -0 direction component differently (a sign test, e.g. which side the slip road joins).
- **Fix (shipped, default build):** `hx.positiveZeros(built.lists)` at the end of `hx.build` (after the left-hand
  mirror, which negates x and makes new -0s): every zero coordinate of positions and tangents becomes +0.0. Only the
  highway entry: the Roundabout Interchange and the other entries stay byte-identical. Highway golden: the exact
  fingerprints of all 72 groups re-recorded (sign of zero only), the rounded ones and every other entry's lines
  unchanged. test_highway: no -0 in any type x highway x level x direction x Size, and (-0) * x + y never -0.
- **To confirm in the UI:** DEV ramps value **"UNDO -0 fix (old build)"** (variant 28) rebuilds the old output;
  Off (= the fix) should be green and UNDO red at the failing spot, rotation 0. Then docs/findings.md (verified),
  and 7f removes the DEV ramps param, the variants module, the fingerprint and the probe copy.
- Gates: check 0 errors, validate OK, main 203 / 203, probe 67 / 67. (SQRB_FULL not run: sign-of-zero only.)

## Phase 7c2 notes (2026-10-09)

**One menu entry per type, button rows, DEV diagnostics removed (no revision bump, description.html untouched; the
four released entries' goldens, icons and previews unchanged).** User requests: one item per type instead of a Type
dropdown, only the settings that apply, every setting a row of buttons like the base interchanges ("Lanes [2][3]",
"Scale [Small][Medium][Large]"), and a Scale whose Large is clearly larger than 7c's Very large.
- **Entries:** `square_roundabouts_highway_<id>.con.lua` for `parclo_a4`, `parclo_b4`, `parclo_a2`, `parclo_b2`,
  `parclo_ab2`, `diamond` (names "Parclo A4" ... "Diamond"), each a 3-line wrapper around
  `square_roundabouts_highway_menu.lua` `menu.data(hx.TYPE_*, _)`. Menu orders next to the base interchanges: the
  parclos 6002-6006 (after the base cloverleaf 6000 and diverging diamond 6001), the Diamond 7001 (after the base
  diamond 7000). One shared updateFn (`square_roundabouts_highway.script@updateFn`); the entry's `updateScript.params
  = {type = t}` arrives as `captureParams` (as the base roundabout's `radii`), `hx.specFor(captureParams, params)`
  fixes the type; without it (tests, goldens, the probe's params) `sqrb_hx_type` from params still works. The old
  single entry (`square_roundabouts_highway.con.lua`, its icon and preview) is deleted: the probe does not need it.
- **Params (all six, same keys):** Highway [Small][Medium][Large] (`sqrb_ix_highway`, shared), Level [Road over]
  [Highway over] (`sqrb_hx_level`), Cross road (ComboBox, six roads, `sqrb_ix_cross`, shared; the base has no
  dropdown, a 6-button row would not fit), **Scale** [Small][Medium][Large] (`sqrb_hx_scale`, new key), Ramp
  length [Short][Medium][Long] (`sqrb_hx_ramp`, new), Arm length [30 m][45 m][60 m] (`sqrb_hx_arm_length`, new;
  no longer shared with the Roundabout Interchange's 4-value key), Traffic side [Right-hand][Left-hand]
  (`sqrb_direction`, shared). Buttons: `uiType "Button"`, `displayMode "Horizontal"` (base param_util.tl). No Type,
  no dev or TMP param. No param was dead for any type (the 7c test "every param changes the build" still passes
  for all six), so none dropped; the Scale and Ramp length tooltips are per type (loop radius / terminal distance;
  "over the shortest that wraps around the loop" / "120, 150 or 180 m"). New keys because the values changed meaning
  (nothing released, no save impact).
- **Values:** Scale = loop radius **25 / 45 / 80 m** (grow 90, 100) and diamond terminal distance **0 / 30 / 80 m**
  (grow 90, 100); Small = 7c's Compact, Medium = 7c's Large, Large beyond 7c's Very large (60 / 50 m). Default
  **Medium** (7c's default was 35 m loops; 45 m is the loop the engine placed on the large highway, Phase 7e).
  Ramp length +0 / 30 / 60 m (`hx.RAMP_EXTRAS`), Arm length 30 / 45 / 60 m. Offline: every type x highway x level x
  side x Scale x 4 cross roads x Short / Long passes the fit, gradient (diagonals avg <= 5.2 %, loops <= 6.5 %,
  diamond <= 9.1 % / peak 13.7 %), junction, overlap and short-edge checks with no Scale growth, and no `-0` in any
  build. 80 m parclo at Long ramps: xm 391.5 m, yTo 220.5 m. Footprints: default parclo about 500 x 350 m, default
  diamond 300 x 185 m, largest parclo about 900 x 560 m. **Not yet engine-probed: Scale Large (80 m loops, 80 m
  terminals), the 45 m arms, +30 m ramps;** p7_hx_all / p7_verify with the new values cover them (7d/7e style run).
- **Removed (fix-up diagnostics, 7f checklist item 1 done):** the DEV ramps param (`hx.TMP_KEYS`,
  `TMP_RAMPS_VARIANTS`, `spec.tmpRamps`), `square_roundabouts_hx_variants.lua` and its hook in `hx.build`, the dev keys
  `hxVariant` and `hxTagJoints` with `hx.tagJoints` (only the probe's p7_seed / watcher used them),
  `square_roundabouts_fingerprint.lua` and the `[SQRB_FP]` print, their tests. Kept: `hx.positiveZeros` (now with a
  direct unit test) and the -0 sweep test; the tuning dev keys hxClear / hxGoreRun / hxTermGap / hxLoopRadius (the
  probe's p7_hx_search uses them).
- **Icons:** `tools/render_icon_square_roundabouts.py` renders 6 icons + 6 placeholder previews from each entry's
  live default build (`dump_square_roundabouts_highway.lua` prints a `T <type>` block per type; the scale fits the
  ramps to the canvas). The four older icons are byte-identical (md5 before / after).
- **Tests:** test_highway: a ".con.lua x 6" test (names, own icons, orders, captureParams type, buttons with
  `displayMode "Horizontal"`, <= 3 short labels, Cross road the only ComboBox, no Type / dev / tmp key, Scale
  tooltip per type, defaults = readParams), `hx.specFor`, retired 7c keys ignored, value counts; sweeps over the
  three Scale values. Highway golden re-recorded (all 72 groups; channel / interchange lines untouched).
  verdicts.lua: the pre-7c2 probe CSVs (p7_hx_all, p7_verify) replay with their keys translated by value
  (`V.hxParams(hx, key, true)`: 25 / 45 m loops, 0 / 30 m terminals, +0 / 60 m ramps, 30 / 60 m arms map; rows with
  retired values are skipped); new runs go in `V.HX_FILES_7C2`.
- **`-0` scan of every entry's output (shipped sweeps of test_short_edges / golden.lua, updateFn results, every
  number of the result):** highway (all six types) 0 of 3,456 builds. Released entries (not changed, user decides):
  no `-0` in any edge **y** (position or tangent), which is the coordinate that broke the highway at rotation 0.
  Found: main 7,288 / 7,776 builds: ring tangents `t.x = -0` (right-hand, ring templates, 1 / 2 / 4 lanes, tram too)
  and `t.z = -0` (left-hand, every ring and the splitter's xsmall one-way); island model / collider `transf[5]`.
  Magic 540 / 600: `t.z = -0` (left-hand, ring templates); island `transf[5]`. Channelized 3,472 / 6,912: left-hand
  only, side road `p.x` and `t.x = -0` (every side road template, the axis x = 0 mirrored) and the slip lanes'
  (`town_new_one_way_xsmall`) `p.x = -0`; island collider `transf[5]`, a few ground-face points' x. Roundabout
  Interchange 4,064 / 6,912: right-hand dumbbell / peanut ring tangents `t.x = -0` (ring templates); island
  model / collider `transf[5]` and, left-hand, `transf[13]` (translation x). At rotation 0 world x = x - (-0) * y keeps
  a `-0` x only where y < 0; whether the engine cares about x / z as it did about y is unknown (these entries
  have placed in game since revision 1-3).
- **Probe (DEV ONLY `square_roundabouts_probe`):** highway axes keep their order and keys format (`h:` replay keys,
  type still the first value); size -> `sqrb_hx_scale` small / medium / large, ramp -> `sqrb_hx_ramp` 0 / 30 / 60,
  armlen -> `sqrb_hx_arm_length` 30 / 45 / 60; `engine:fileFor(combo)` sends each combo to its type's
  `square_roundabouts_highway_<id>.con`; probe_geom builds through `hx.specFor`. Removed: the construction tool
  watcher and its event subscription (update / guiHandleEvent; it was on whenever "Run the probe" was), triage,
  diff, deferred replays, bisect, variant sweeps, the highway copy con, the seed / tag / variant / dz place fields,
  subsets p7_watch and p7_seed. Sizes now: p7_hx_all 696 combos, p7_verify 150, p7_hx_search 66 jobs / 504 calls;
  p7_spot / p7_spot2 kept. PROBE.md's Phase 7e fix-up rounds describe the removed watcher (history only).
- Gates: `make check` main 26 files / probe 11 files, 0 errors (0.9 / 0.7 s); `make validate` OK (0.06 s);
  `make test` main 205 / 205 (45 s), probe 61 / 61 (11 s). SQRB_FULL not run (the roundabout geometry is unchanged).

## Phase 7c3 notes (2026-10-09)

**Fewer menu items, a Scale you can see, a mod badge, no sliders (no revision bump, description.html
untouched).** User feedback after testing 7c2's six items in game, plus a follow-up request (size settings
as button rows on the released entries too).
- **Menu: three highway entries.** A and B are mirrors, so they are a setting now:
  `square_roundabouts_highway_parclo.con.lua` "Parclo" (order 6002, Layout [A][B] = A4 / B4),
  `..._parclo2.con.lua` "Parclo, two quadrants" (6003, Layout [A][B][AB] = A2 / B2 / AB2),
  `..._diamond.con.lua` "Diamond" (7001, no Layout row). Each is `menu.data("<id>", _)`. The Layout row
  comes first (key `hx.LAYOUT_KEY = "sqrb_hx_layout"`, not in `hx.PARAM_KEYS`: no probe axis); the entry's
  `updateScript.params = {types = {...}}` arrives as captureParams and `hx.specFor` picks
  `types[layout]`; without the Layout key it keeps params' `sqrb_hx_type` when that is one of the entry's
  types (the probe), else the first; 7c2's `captureParams.type` still works. Removed: the five
  `square_roundabouts_highway_parclo_<a4|b4|a2|b2|ab2>` .con.lua files, icons and previews.
- **Scale = footprint** (user: "Scale often makes no visible difference"; 7c2's diamond kept its 120 m
  ramps at every Scale, its terminals moved only 30-80 m). `hx.SCALES = {1, 1.6, 2.5}`: per Scale index
  the parclo terminal / loop-to-diagonal gap `hx.TERM_GAPS = {30, 48, 75}` and a shortest ramp of at least
  SCALES x the Small layout's xmMin (`hx.rampStart`); diamond terminals `hx.TERMINAL_DISTANCES = {0, 40, 100}`
  (grow 110 / 120) and ramps `hx.DIAMOND_RAMP_MINS = {120, 192, 300}`. Loop radii stay 25 / 45 / 80 m. The
  Scale index rides in the frame (`hx.frame(spec, scale)`, `f.scale`); growth past Large keeps Large's
  numbers. **Small builds exactly 7c2's Small.** The gore run stays 30 m: 48 / 75 m gores (tried) make the
  ramp / carriageway junction stretch longer than the overlap check's 40 m (GORE_MAX). Ramp footprints
  (medium highway, road over, Short): parclo 320 x 211 / 512 x 327 / 830 x 521 m, diamond 240 x 65 /
  384 x 145 / 600 x 265 m; ratio >= 1.45 / 2.2 in both directions for every type x highway x level x cross
  road x ramp length (new test "Scale: Small / Medium / Large footprints differ clearly"). Largest: about
  1048 x 531 m of ramps (large highway, highway over, country large, Long). Every offline check passes with
  no growth (fit, gradient, junction, overlap, short-edge, -0: `negative_zero` 5.4 and `TEALRT_LUA=52`).
  Scale tooltips name the footprint; the diamond's Ramp length tooltip is now "+0 / 30 / 60 m over the
  Scale's". **Not engine-probed: Medium and Large (the default Medium changed: 48 m gap, 256 m ramps on
  the medium highway).** 7c's diamond 30 m terminal rows no longer map in verdicts.lua (retired value).
- **Mod badge** on every 240x150 menu icon (`with_badge` in `tools/render_icon_square_roundabouts.py`):
  a 30 px family-teal (#2FA48F) rounded square with a dark outline and an accent (#E8833A) ring, top-right,
  5 px margin. The four released icons change on purpose (cosmetic); hover previews have no badge. `--png
  x.png` also writes `x_menu_row.png` (all seven icons side by side on the menu grey).
- **No sliders on the released entries** (user: size settings as button rows like the interchanges').
  Same key and indices, only `uiType "Button"`, `displayMode "Horizontal"` and shorter labels: main Shape
  [Round][1.25:1][1.5:1][1.75:1][2:1], Magic Size [Compact][Small][Medium][Large][Huge] ("Very large" ->
  "Huge"; radii in the tooltip), Channelized Arm length [30 m]..[60 m], Interchange Slip road length
  [120 m]..[180 m] and Arm length [30 m]..[60 m]. **Radius presets on new keys**: main `sqrb_radius_size`
  [Mini][Small][Medium][Large][Huge] = `geom.RADII` indices {2, 4, 5, 8, 13} (10 / 15 / 20 / 35 / 60 m,
  default Medium = 20 m); Interchange `sqrb_ix_radius_size` [Small][Medium][Large][Huge] = `ix.RADII`
  indices {1, 2, 4, 7} (15 / 20 / 30 / 45 m, default Medium). readParams: the preset key when present,
  else the full-range index key (`sqrb_radius` / `sqrb_ix_radius`: tests, goldens, the probe's replay
  keys), else the default, so a preset builds exactly what its radius built (same radiusIndex, same
  growth). **No golden dropped: every released golden group is byte-identical**; only the highway golden
  was re-recorded (72 groups). Radii no longer in the menu: main 8, 12, 25, 30, 40, 45, 50, 55 m;
  Interchange 25, 35, 40, 50, 55, 60 m (still built when the ring grows). Every row: <= 5 buttons, <= 30
  characters (tested); the widest base row seen is the interchanges' 3-button Scale.
- **Saves / menu state (for 7f's changelog):** the two Radius rows use new keys, so a player's last
  radius pick on the old slider is not carried over: the menu opens on Medium (20 m). Shape, Magic Size and
  the length rows keep the saved choice. Placed roads are unaffected (every node is freed; no updateFn re-run).
- **Probe (DEV ONLY):** `grid.MAIN_AXES` / `INTERCHANGE_AXES` radius axes keep the full-range key and
  labels (replay keys and `gen_roundabouts_tuning.py` MAIN_ORDER unchanged) and gain
  `menu = {key, presets}`; test_grid's checkAxes matches those against the .con.lua's preset row.
  Highway: `ENTRIES.highway.files` per type -> parclo / parclo / parclo2 x 3 / diamond, `layoutKey` +
  `layouts = {1, 2, 1, 2, 3, nil}`, sent by `engine:paramsFor` so the game picks the same type.
- **Tooltip popup on every setting click (research only, nothing changed):** base game behaviour, in
  `base/content/gui/construction/construction.tl`: `changeParam` (l.1874-1877) fires
  `constructionOpenCalloutFromParams` for params with the default location, the info callout (name,
  description, previewIcon, cost; l.3521-3560) opens with delay 0 (0.5 s on hover, l.3925) and closes
  after ~2 s (l.3846-3849). The base interchanges behave the same. Options: (a) `location = "Toolbar"` on a
  param (base `param_util.tl:107`, `assetbuilderutil.lua:54`) fires `constructionSetSuppressCallout`
  instead, but moves the param out of the settings panel into the left toolbar: safe, changes the UI, only
  for one or two params; (b) drop `previewIcon` / shorten `description`: a smaller popup (`no-image` class,
  `construction.css.lua:490-500`), still 2 s: safe but loses the preview; (c) no `.css.lua` delay /
  visibility property, no `api.gui` toggle; overriding construction.tl is risky (large, breaks on updates).
  Recommendation: accept it (as the base items), or try (a) on one row in a DEV test if the user wants.
- Gates: `make check` main 23 files / probe 11 files, 0 errors (0.5 / 0.5 s); `make validate` OK (0.04 s);
  `make test` main 206 / 206 (44.5 s), probe 61 / 61 (10.3 s); `TEALRT_LUA=52 -f negative_zero` 6 / 6.
  SQRB_FULL not run (roundabout geometry unchanged).

## Phase 7d2 notes (2026-10-09)

**Probe only (DEV ONLY `square_roundabouts_probe`; the shipped mod is untouched, no revision bump).** Two
subsets, appended to `grid.SUBSET_ORDER` and the probe's `mod.json` Subset list (older indices unchanged):
- **p7_hx_scale** (1224 engine calls, no search): the 7c3 Scale on the three highway entries.
  (1) every type (= every Layout button: Parclo A4 / B4, Parclo two quadrants A2 / B2 / AB2, Diamond) x Scale
  Small / Medium / Large x highway S / M / L x level x cross road {town medium, country large} x traffic side
  x year {1969 steel, 2020 concrete}, shortest ramps, 30 m arms, at the builder's exact 0 degree transf
  (`engine.BUILDER_ZERO`, sin = -0): 864. (2) the extremes at Scale Large, country large, 2020, both sides:
  +60 m ramps x 30 / 60 m arms and 60 m arms at the shortest ramps: 216. (3) rotations 90 and 180 (a place,
  context none, `grid.HX_SCALE_ROTS`) on the medium highway, town medium, 2020, every type x level x Scale x
  side: 144 (R / D lines carry `rot`; `parse_probe.py --summary` now prints a `rot` fail-rate row, `-` = 0
  degrees). Position stays the setting (not the camera: only `p7_spot*` switch).
- **p7_presets** (88 calls): the released entries' 7c3 button rows at 0 degrees, both traffic sides. A new
  block flag `menu = true` also sends each radius axis's preset key (`sqrb_radius_size` /
  `sqrb_ix_radius_size`, the button index; `grid.addMenuKeys`) as the menu does, next to the full-range key
  (same replay key; readParams takes the preset). Main: radius 10 / 15 / 20 / 35 / 60 m x lanes x direction
  (30); Roundabout Interchange: 15 / 20 / 30 / 45 m x layout x side (24); Channelized Junction: layout x slip
  lanes x splitter x side (24; includes the 6 **X left-hand** combos, the open -0 case, PHASE7_RUNBOOK
  "-0 check"); Magic: every Size x direction (10).
- Offline: every p7_hx_scale combo is sane, unforced, no growth at all three Scales; every preset key builds
  the full-range index's radius. Tests: probe 61 -> 65 (test_grid sizes / coverage / ids / layouts, presets;
  test_geom; test_search paramsFor + positionSource).
- `make probe-report` (no LOGS) now also parses `probe_p7_hx_scale.log` and `probe_p7_presets.log` when
  present -> `probe_p7_hx_scale.md/.csv`, `probe_p7_presets.md/.csv` + a console digest.
- **Run time estimate**: p7_hx_all ran 912 calls in 14 s (~65 calls/s at Combos per update 8); Large builds
  are bigger, so p7_hx_scale **~20-60 s**, p7_presets **~2-5 s** (after the 15 s delay).

**User run steps.**
1. `make link`. TF3: the flat test map (flat, empty, centre on land, year 2020; game traffic side does not
   matter: the probe sets the build's side per combo). Enable Better Roundabouts (this build) + DEV
   Roundabouts Probe. Probe settings (set before loading; check the START line): Run the probe **On**,
   Subset **p7_hx_scale**, Start delay **15 s**, Combos per update **8**, Position X / Y **0 / 0**, Position
   **X / Y**, Proposal context **None**, Log placeable combos **On**.
2. Load, pause, wait for `[SQRB_PROBE] END subset=p7_hx_scale` (~20-60 s after the delay; PROGRESS lines give
   the ETA). `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p7_hx_scale.log`
3. Quit to the menu, set Subset **p7_presets** (rest unchanged), load, wait for `END subset=p7_presets`
   (~2-5 s); `cp ... stdout.txt plans/square_roundabouts/probe_p7_presets.log`.
4. `make probe-report` (0.2 s): reports go to `plans/square_roundabouts/probe_p7_hx_scale.md/.csv` and
   `probe_p7_presets.md/.csv`; read the digest (per-axis fail rates incl. `size`, `dir`, `rot`). The
   Channelized Junction X left-hand rows answer the -0 question (refused at 0 degrees = -0 harm confirmed).
   Anything odd (crash, ERROR line, END missing): the last 50 `[SQRB_PROBE]` lines of stdout.txt.
5. Disable the probe afterwards.

## Phase 7e2 notes (2026-10-09)

**p7_hx_scale (user run): 1034 / 1224 placed; p7_presets 88 / 88.** Diamond 204 / 204, every Scale Small /
Medium placed, rotations 90 / 180 0 refusals. All 190 refusals are Scale **Large** parclos (each layout 38).
No revision bump, description.html untouched, released goldens and icons unchanged.

**Cause: how far the build reaches from its origin, nothing else.** `make hx-dump` over all 1080 0-degree keys
(1.6 s for all), then one feature per build against the verdict: the furthest edge end along x (highway end =
outermost gore xm + Arm length, the highway stubs use the Arm length too) **separates all 1080 exactly**:
placed <= 481.25 m, refused >= 486.25 m. Per level: "Road over" placed up to 481.25 m (Large, large highway,
60 m arms), "Highway over road" (highway end 8 m up on an embankment) up to 462.5 m, refused from 486.25 m.
Nothing else separates: longest single edge (placed up to 557 m, refused from 466 m), longest ramp, steepest grade
(<= 9.9 % placed, 3.5 % refused), |y| reach (325 m placed, 281 m refused). The suspected causes (steep or long
ramps, loop / arm collisions, the country large road at the terminals, 2020 concrete bridges, a short highway
piece at a bridge end) don't fit: the 190 split into three groups that all just pass ~485 m: (1) large
highway x highway over road x Scale Large (xm 456.25 + 30 = 486.25 / 493.75, both cross roads, both years:
the "cross country_l / year 2020" skew is only because the extremes block ran on country large 2020);
(2) Long ramps at Large (xm + 60 >= 497.5, every highway / level); (3) highway over road with 60 m arms at
Large (432.5 + 60 = 492.5). Messages are mixed (Not Possible / Too Much Incline / Collision with coll = 1,
bld = 0), so they are not a guide here. Only one position (0 / 0) was probed, so whether this is a
per-construction limit or the test map's buildable area is open (docs/findings.md, 2026-10-09).

**Fix: `hx.MAX_REACH = { 481.25, 462.5 }` (per level, the largest reaches that placed).**
`hx.rampStart` caps the ramp length at MAX_REACH[level] - Arm length (never below the layout minimum
xmMin, never inside (xmMin, xmMin + MIN_EDGE)); `hx.fits` rejects a layout with `hx.reach(lay)`
(max(xm, yTo) + Arm length) beyond it ("reach"), so growth cannot cross it either. Loops keep 80 m (no Size
growth, no forced plan anywhere). Result: exactly the 190 refused keys build a different (shorter) layout;
**every placed key, at every Scale, builds byte-identically** (hx-dump diff over all 1080 keys), the diamond
never reaches the cap. Cost: at Scale Large the Ramp length buttons collapse where capped (e.g. large
highway, highway over road: Short / Medium / Long all xm 432.5 at 30 m arms); the parclo Ramp length tooltip
says so. Scale Large stays clearly larger than Medium (tested: > Medium + 50 m wide where capped).

**Tests (offline checks that would have caught it).**
- test_highway "reach: every build's edges within hx.MAX_REACH" (new): all 5832 type x highway x level x 6
  cross roads x Scale x Ramp x Arm builds: |x|, |y| of every edge end <= MAX_REACH[level], hx.reach = the
  furthest end, never forced, only Scale Large reaches the cap (1130 at the cap, including the ones that
  placed exactly there).
- "every param changes the build": a ramp length capped by the reach may build the same as the next.
  "Scale footprints": 70 of 288 groups capped at Large; those check Large > Medium + 50 m.
- Highway golden re-recorded: exactly the 60 parclo groups (t1-5, every h / v / year) changed, diamond 12
  unchanged (checked by re-running with the cap disabled: 0 diffs). Other goldens untouched.
- `V.HX_FILES_7C2 = { probe_p7_hx_scale.csv, probe_p7_hx_scale_verify.csv }`: engine_verdicts (highway) now
  replays p7_hx_scale: 0 problems, gaps `hx` 180 -> 370 (the 190 refused keys now ship an unprobed layout;
  the verify run closes them). With the cap disabled the test fails (190 problems), so it guards the fix.
- -0: `negative_zero` and `TEALRT_LUA=52 -f negative_zero` pass (highway 0 raw -0).

**p7_presets (user run, 88 / 88).** Channelized Junction X left-hand (world `-0` in a side-road tangent's x at
the builder's 0-degree transf) placed: recorded in docs/findings.md "Negative zero" and the KNOWN comment of
test_negative_zero.lua (the refused highway case had -0 in y; still normalise new geometry). No geometry change.

**Probe (DEV ONLY): subset `p7_hx_scale_verify` (220 calls, ~10 s)**, last in SUBSET_ORDER / mod.json:
the 190 refused combos (large highway x highway over x Large x 2 cross roads x both sides x both years: 40;
Long ramps x 30 / 60 m arms x every highway x level, country large, 2020, both sides: 120; highway over with
60 m arms: 30) + 30 capped / never probed (town medium, +30 m ramps, 45 m arms, right-hand, 2020, every
highway x level). Tests: test_grid (size, unique keys, covers all 190 refused keys of the CSV), test_geom
(sane, unforced, no growth, within MAX_REACH). Makefile PROBE_LOGS picks up `probe_p7_hx_scale_verify.log`.

**User run steps.** `make link`; TF3 flat test map as before (centre on land, 2020); Better Roundabouts +
DEV Roundabouts Probe; Subset **p7_hx_scale_verify**, rest as p7_hx_scale (On, 15 s, 8 per update, 0 / 0,
Position X / Y, context None, Log placeable On). Wait for `END subset=p7_hx_scale_verify`;
`cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p7_hx_scale_verify.log`;
`make probe-report`; `make test MOD=mods/square_roundabouts ARGS="-f engine_verdicts -k highway"`: the 190
`hx` gaps should go (370 -> 180). If some still refuse: hx-dump them; if they all reach exactly 462.5 /
481.25 m, lower MAX_REACH by 10 m (the limit may be radial: highway ends sit 6.5-13.5 m off the axis).
Optional discriminator (not in the subset): place one capped combo with the origin shifted 30 m along x
(p7_spot-style place) — refused means a map / area limit, placed means a per-construction one.

**Gate:** `make gate MOD=mods/square_roundabouts MOD2=mods/square_roundabouts_probe` (60 s): check 23 / 11
files 0 errors, validate OK, tests 207 / 207 and 67 / 67.

## Phase 7f notes (2026-10-09)

**Release prep, revision 4 (not committed, not uploaded).** Probe runs passed (p7_hx_scale_verify 220 / 220,
p7_presets 88 / 88). The user's in-game traffic test (TESTING.md section 16) is still pending: the description
claims nothing about traffic behaviour on the new entries.
- `mod.json` revision 3 -> 4.
- `description.html`: intro names the three highway entries; Features bullets Parclo, Parclo two quadrants,
  Diamond plus a shared one; "Any size" -> "Five sizes" (the main Radius presets); Magic "Very large" -> "Huge";
  every former slider described as its button values (Shape, both Radius rows, Channelized Arm length, Interchange
  Slip road / Arm length); new `<h4>Settings: Parclo, Parclo two quadrants and Diamond</h4>` (Layout, Highway,
  Level, Cross road, Scale, Ramp length incl. the Scale Large cap, Arm length, Traffic side; defaults from
  `square_roundabouts_highway_menu.lua` / `hx.DEFAULT_*`). Notes: where the seven entries sit, 1940 (base
  interchanges 1960), the menu badge, "less thoroughly checked" note now covers the highway entries, "seven
  construction menu entries", "runs no scripts" kept (construction updateFns only). Changelog `Revision 4
  (2026-10-09)` first: New highway entries; Changed: mod renamed (menu entry keeps "Better Roundabouts"), sliders
  -> buttons, Radius choice reset once to Medium 20 m (placed roads unaffected), Very large -> Huge, menu badge,
  everything else builds as in revision 3. No "Fixed" line: the -0 normalisation only touches new geometry, and the
  Channelized X left-hand -0 placed in p7_presets (no harm, nothing to fix).
- `modinfo.json`: summary 98 chars ("Roundabouts, Magic Roundabout, channelized junctions, parclo, diamond and
  roundabout interchanges."); description adds the highway interchange sentence (548 chars).
- Gallery: no new captures in `plans/square_roundabouts/shots/` (latest 17). Slides 1-9 untouched, `branding/shots.js`
  unchanged, `make shots` not run. **Captures needed** (full-screen, 4K like the others), then append slides 10+
  after "Mix and match":
  - `18-parclo-overview.jpg`: a placed Parclo (A, Medium, road over), oblique, cars on it if possible. Also the
    source for the Parclo hover preview (`tools/render_preview_square_roundabouts.py`).
  - `19-parclo2-overview.jpg`: a placed Parclo, two quadrants (AB or A), oblique.
  - `20-diamond-overview.jpg`: a placed Diamond, highway over road, oblique.
  - `21-menu-highway-hover.jpg`: road construction menu on the interchanges, hovering Parclo (badged icons next to
    the base cloverleaf / diamond, hover preview visible).
  - `22-settings-highway.jpg`: the Parclo settings panel with all button rows (Layout ... Traffic side).
  Suggested slides: "Highway interchanges" (18 + inset 21), "Parclo or diamond" (19 / 20), "Buttons, not
  sliders" (22). The three highway hover previews are still the rendered placeholders from 7c3.
- Hygiene: no print / fingerprint / TMP / variant code in `content/` (grep). `geom.DEV_KEYS` present: the pre-7a
  keys plus hxClear / hxGoreRun / hxTermGap / hxLoopRadius (added in 7b/7e, kept on purpose in 7c2 for
  p7_hx_search); none is a menu param, all inert unless a caller sends the key. Probe: modinfo "DEV ONLY - NOT FOR
  UPLOAD" + `NOT_FOR_UPLOAD.txt` present (its dependency displayName still says "Better Roundabouts": DEV only,
  harmless). No uppercase / whitespace file names, no BOM, 19 MB.
- Cover: `0.png` already shows "Roundabouts & Interchanges" / "Rings, junctions, interchanges" (re-rendered
  earlier today), so no `make covers`. Tagline proposal (not applied): "Rings, junctions, highway ramps" (31).
- Gates: `make gate MOD=mods/square_roundabouts MOD2=mods/square_roundabouts_probe` (57 s): check 23 / 11 files
  0 errors, validate OK (probe: lowercase warning on NOT_FOR_UPLOAD.txt, intended), tests 207 / 207 and 67 / 67.
  `SQRB_FULL=1 make test MOD=mods/square_roundabouts`: 207 / 207 (133 s).
- Before upload: TESTING.md section 16 (user), the captures above + `make shots`, then the Mod Hub update.

### Phase 7f decisions (user, 2026-10-09)
- No per-interchange gallery captures for revision 4 (18-22 dropped); the highway hover previews stay the
  drawn ones from the icon tool.
- Tagline stays "Rings, junctions, interchanges"; the cover isn't re-rendered.
- Traffic test: user ran traffic on the placed entries, "looks fine" (TESTING.md 16B); loop speeds not measured.
