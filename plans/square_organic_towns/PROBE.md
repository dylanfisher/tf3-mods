# Organic Towns: Phase 1 probe mod (`square_organic_towns_probe`)

DEV mod, never uploaded, English only, `severityRemove: "Warning"`, not cosmetic. Use it on a throwaway save.
Layout copies the Stress Test pattern: a HUD button + window with one button per probe, all commands sent from the
button's `react.onStep` on the Main Thread through a serial queue (`mods/square_stress_test/content/stress/gui/stress_runtime.tl`),
one command in flight. Proposal helpers are copied from `stress_junctions.tl` (`segment`, `z0`, `context`,
`precheck`, `linkProposal`). Every result is one line `[SQOT_PROBE] <id> <ok|fail> key=value ...` in stdout.txt;
every proposal is logged **before** it is sent (crash forensics). `make perf`-style timing via `api.type.Clock`.

Test map: a free game, temperate, 1850 start + one 2000 start; names `usa` and `germany`; one town on flat land, one
on a hillside, one by a river, one on the coast. Speed 8 for "wait N months" steps (findings: speed 8 sticks).

Shared readouts (logged by most probes, helper `townStats(town)`): edges in bbox (octree BASE_EDGE + BASE_EDGE_STREET),
dead ends, buildings (`getTown2BuildingMap`), person capacities, sizeFactors, developmentActive, bbox.

---

### A. What does freezing stop?

- **Question:** Does `makeTownSetDevelopmentActiveCmd(town, false)` stop new streets, new/replaced buildings, or both?
  Does a manual `makeTownUpdateSizeCmd` on a frozen town still run the developer (streets? buildings?)?
- **Method:** pick 2 similar towns T1 (frozen) and T2 (control). A1: freeze T1, `UpdateSize` both ×3 factors over 5
  calls each (as findings.md:460-463), log `townStats` before and 10 s after each call. A2: unfreeze nothing, wait 12
  game months at speed 8, log both again. A3: on T1 (still frozen) record all edge ids + revisions, wait 12 months,
  diff (added/removed/changed edges, building ids and `timeBuilt`).
- **Log:** `[SQOT_PROBE] A1 town=T1 frozen=true call=k edges=a->b buildings=c->d deadEnds=e->f ms=...`, `A3 diff
  edgesAdded= edgesRemoved= edgesChanged= buildingsAdded= buildingsRemoved=`.
- **Reading:** A1 frozen edges +0 but buildings + → freeze stops streets only when the developer is called (best case:
  "Own" mode = freeze + our streets + our UpdateSize). A1 edges + on a frozen town → UpdateSize runs the full developer
  regardless. A3 all zero → frozen = fully static. Compare with T2.

### B. Does the engine fill parcels along script streets added to an existing town?

- **Question:** Do houses appear along town-template streets we build next to an existing town; with development on,
  and frozen + `UpdateSize`? Who owns/pays for them?
- **Method:** next to T2's edge, a 3×2-block grid patch (17 edges, `town_new_small`, `playerOwned` nil), joined at
  one dead end (variant D2 if D passed, else free-standing 10 m away + one joining edge to a dead end). B1: dev on,
  wait 6 months. B2: same on frozen T1, then `UpdateSize` ×3. B3: a patch with `seg.playerOwned` set to the player.
  For each new edge log `PLAYER_OWNED` present, `getParcelData(edge)` (dump type/len), parcels with building.
  Money: player balance before/after; maintenance after 1 year (journal).
- **Log:** `B1 edges=17 owned=0/17 cost=... parcels=N built=M months=6`, `B2 ...`, `B3 owned=17/17 built=...`.
- **Reading:** built/parcels > 30 % on B1 → Guide mode viable. B2 > 0 → Freeze mode viable. B3 built=0 → never set
  `playerOwned`. cost > 0 → offer refund.

### C. Visual effect of the angle knobs

- **Question:** What do `townMajorStreetAngleRange`, `townInitialMajorStreetAngleRange` (global) and
  `TownInfo.majorStreetAngle` / `initialMajorStreetAngle` (per town) actually do? Do baseConfig values set in
  `preRunFn` apply to a **loaded** save?
- **Method:** probe param "Angle range" {0, 15, 45, 90} applied in `preRunFn` to both globals; log
  `api.res.getBaseConfig().townMajorStreetAngleRange` at runtime (new game and loaded save). Create towns on flat
  land in a row (Stress Test `createTowns` → `makeTownCreateCmd`, serial) with per-town `majorStreetAngle` ∈ {0, 30, 45}
  and `initialMajorStreetAngle` ∈ {0, 30}. Grow each ×5 for 3 passes. Per town compute the edge heading histogram
  (headings mod 90°, 10° bins, length-weighted) and the share of curved edges (tangent0 vs tangent1 angle > 5°).
- **Log:** `C global=15 runtime=15 town=C3 angle=30 init=0 hist=[..9 bins..] curved=0.12 edges=...`; screenshots.
- **Reading:** histogram peaks shift with `majorStreetAngle` → per-town axis works (we can align new towns with
  terrain/coast). Spread widens with range → organic knob confirmed. Runtime value ≠ param on a loaded save → angle
  knob only for new games.

### D. Safely extending from an existing town node

- **Question:** Which join leaves a working junction (no red dead-end sign, cars turn into the new street) and never
  crashes, for (D-a) a dead end and (D-b) a node with 2+ edges?
- **Method:** each variant on a fresh target, 1 proposal, `[SQOT_PROBE] D<v> sending ...` before sending, then read the
  node's `BASE_NODE_CONFIG` lane connections and HUD dead-end state 2 s later; drive test: a bus line through it.
  - **D1** plain: new edge references the existing dead-end node id (known: stays blocked; baseline).
  - **D2** replace-node (Stress Test fix, unverified): remove the dead end + its edge, add a new node at the same spot,
    a copy of the edge, our edge.
  - **D3** D1 + rebuild that node's config: `nodeConfigsToRemove = {node}`, `nodeConfigsToAdd = {full config with
    lane connections for all its edges}` (Crossing Tool pattern, findings.md "Junction lane connections").
  - **D4** extend instead of join: remove the dead-end edge E(I→D) and D, add a longer chain from I through D's spot;
    I keeps its other edges, only I's config is re-pointed from E to the new first edge.
  - **D5** T on a segment: split edge E(A–B) at a midpoint M (remove E, add A–M, M–B copies + M + our edge M–X),
    re-point A's and B's configs. M is new, but A and B usually have 2+ edges, so this exercises the re-pointing
    that is suspected in the crash (findings.md:198-207). Run after D2-D4, with a backup save.
  - **D6** coincident node, no id: our network ends at a new node exactly at D's position, `Context.cleanupStreetGraph
    = true` — does the engine merge it?
  - **D7** (D-b) degree-3 node via D2's replace on a crossing node, only after D2-D5 results, in a fresh save with a
    backup; one try.
- **Log:** `D<v> node=n deg=k success= critical= msgs= configLanes=a->b deadEndIcon=true|false busPath=ok|fail`.
- **Reading:** first variant with success, lanes > 0, no icon, bus passes, 3/3 repeats → production join. Any
  crash → findings.md entry and the variant is banned.

### E. Streets on slopes and near water

- **Question:** Is a too-steep or wet street refused, reshaped, or built with odd embankments? What slope do town
  templates allow? Does `isOnWater` see rivers?
- **Method:** log `streetTemplateRep` `maxSlope/maxSlopeShape/maxSlopeBuild/minCurveRadius` for all town templates.
  On the hillside build single 80 m edges at grades 4, 8, 12, 16, 20 % (node z from `getHeightAt`), then the same
  with z forced flat (engine must cut/fill). Near water: edges ending 30, 10, 0 m from the shoreline and one crossing
  20 m of water (`type` NORMAL). Sample `isOnWater` on a 10 m grid across the river and the coast.
- **Log:** `E grade=12 zMode=terrain success= critical= msgs= resultSlope= cutFill=` (from proposal data
  `terrainPreviewHeightModCutFill` size), `E water dist=0 success= msgs=`, `E river isOnWater hits=a/b`.
- **Reading:** gives the hard grade limit for planning, whether to always use terrain z, and the water detection
  method (rivers missed → also treat `getHeightAt < waterLevel + 1` as wet).

### F. Does engine growth later alter script streets? Does locking stop it?

- **Question:** Does the developer upgrade (widen), replace, or extend from our edges; does `roadDevelopmentLocked`
  prevent that while houses still appear along them? Does locking a town's dead-end edges stop its street growth?
- **Method:** on T2 (dev on) build patch P1 (unlocked, ends in 3 dead ends) and P2 (same, every edge
  `seg.comp.roadDevelopmentLocked = true`). Lock all dead-end edges of town T3 by proposal (remove + re-add copies with
  the flag; or `util.proposal` refresh if simpler). Record ids, revisions, `roadTemplate`, lock flag. Grow ×5 over 3
  passes, then wait 24 months. Diff: edges replaced (same spot, new id/template), new edges attached to P1/P2 nodes,
  T3's edge count, buildings along P1/P2. Also check whether an `aiLock = true` field on a test template (probe-only
  copy) loads or is ignored.
- **Log:** `F P1 replaced=a upgraded=b extendedFrom=c built=d`, `F P2 ...`, `F T3 locked=n edges=a->b buildings=c->d`.
- **Reading:** P2 replaced/extended 0 and built > 0 → "Lead" mode. T3 edges ~flat while buildings grow → "Own" mode.
  P1 upgraded only → harmless (Guide keeps widening).

### G. Reading the config dict at runtime

- **Question:** Where can the mod read `climate` / `nameList` / `economy`?
- **Method:** log from `runFn` (settings arg), `preRunFn` (configDict), GS engine `update` (first call), GS `guiUpdate`
  (first call), HUD `onStep` (first call): `api.engine.config.getConfigDict()` fields (pcall), `rawget(_G,
  "SQOT_PROBE_CONFIG")` set by runFn with `rawset`, and the thread name column.
- **Log:** `G ctx=gsUpdate getConfigDict climate=... nameList=... rawGlobal=yes|no`.
- **Reading:** any context with both → style resolution works there; else the runFn global is the channel.

### H. Cost and timing of a ~20-edge proposal

- **Question:** How long do precheck, build, and the callback take for 5/20/40 edges, and do they hitch frames?
- **Method:** flat grid patches of 5, 20, 40 edges: time `makeProposalData` (Clock µs), `sendCommand` → callback ms,
  frame time max over the 2 s after sending (Clock in `onStep`), sim stall (GS update dt jitter). 3 runs each, speed 1
  and 8.
- **Log:** `H edges=20 precheckUs= buildMs= frameMaxMs= cost= success=`.
- **Reading:** sets the increment size cap and whether prechecking every increment is affordable (PLAN.md §7).

### I. Driver context

- **Question:** Does a `.gs.lua` `guiUpdate` run every frame on the Main Thread with working `api.cmd` callbacks, also
  while paused and with no window open? Is it cheaper than a HUD element's `onStep`?
- **Method:** register `guiUpdate` (+ subscribe in `update`, memory note); count calls per second, thread name, send a
  harmless command (`makeTownSetDevelopmentActiveCmd(T2, true)`) with a callback from it; same from HUD `onStep`.
- **Log:** `I ctx=guiUpdate hz= thread= callback=ok|fail paused=hz`.
- **Reading:** guiUpdate ok → production driver without HUD UI.

### J. Parcels, fill level and town extent

- **Question:** What does `parcelSystem.getParcelData(edge)` return; how cheap is a "free parcels" count; does the
  town `BOUNDING_VOLUME` cover its buildings?
- **Method:** for T2: dump `getParcelData` for 3 edges (type, keys, entities); count parcels / built parcels over all
  town edges (timed); compare bbox with min/max of building positions; log `getTownCapacityUsage`,
  `getLandUsePersonCapacities`, `initialLandUseCapacities*sizeFactors`.
- **Log:** `J parcelData type=... sample=...`, `J parcels=N built=M scanUs=`, `J bbox=... buildings=... inside=97%`,
  `J target=... actual=... usage=...`.
- **Reading:** defines the "needs room" test and the snapshot radius.

### K. Density weights

- **Question:** Does `makeTownCustomDistributionWeightsCmd` visibly shift building levels within a few months?
- **Method:** T2: weights res/com/ind = {0,0,0.5,1} vs T4 {1,0.2,0,0}; `UpdateSize` ×2 with `updateAllBuildings =
  true`; log `computeActualTownBuildingCapacityPerType` before/after.
- **Log:** `K town=T2 weights=... actualBefore=... actualAfter=...`.
- **Reading:** level shift → style densities work; also note if `nil` restores the default.

---

Order: G, I, J, E, H (read-only or cheap) → B, C → D (one variant per save, backup first) → A, F, K (long waits).
After the run, add each result to `docs/findings.md` with date and evidence, and update PLAN.md §4 (modes) and §2.3
step 5 (join variant).

---

## How to run (`mods/square_organic_towns_probe`, built 2026-10-11)

Linked into staging (`make link`). Enable **DEV Organic Towns Probe** on a throwaway free game (temperate,
1850 start, name set `usa`; a second game with `germany`/2000 for C). The **OT Probe** button (top-left mod
area) opens the window: tabs Setup / Read / Build / Join / Growth, one button per probe with its instruction,
"Last:" shows the latest result. Every result: `[SQOT_PROBE] <id> ok|fail k=v ...`; every proposal is logged
as `[SQOT_PROBE] <id> sending ...` before it goes out. Waits (A2/A3, B1, B3, F2) set speed 8, survive closing
the window, **not** a reload. Collect everything:

```
grep '\[SQOT_PROBE\]' "<userdata>/crash_dump/stdout.txt"        # all lines
grep '\[SQOT_PROBE\] report' "<userdata>/crash_dump/stdout.txt"  # after Setup > Dump report
```

Order (cheap and safe first, risky last):

1. **Load-time (G, C param):** before loading, set the mod param "Probe C: angle range" (e.g. 45). After load:
   grep `G ok ctx=preRunFn|runFn|gsUpdate|guiUpdate|hudOnStep` and `C ok ctx=preRunFn`. Read tab > **G**.
2. **Setup:** point the camera at towns and click Set T1 (to be frozen), T2 (control, similar size), T3 (lock
   test), T4 (low density).
3. **Read tab:** **I** (after round 1 pause the game, after round 2 close the window; look for `I ... ctx=guiUpdate`),
   **J** (camera at T2), **E templates**, **E isOnWater grid** (once over a river, once over the coast).
4. **Build tab:** **E grades** (hillside), **E water edges** (land near the shore), **H** once at 1x and once at 8x
   (empty flat land, 1.4 km square).
5. **B1**, **B3** (camera near T2), **B2** (camera near T1). The dead end is picked automatically: the slot
   town's free dead end nearest the camera (log `target=.. camDist=.. townDeadEnds=N`; B3 skips B1's). Patch
   placements (rotation 0/±20/±40°, lateral shift, 3x2 → 1x1 blocks, join gap 40/60/80 m) are pre-checked
   until one passes (`cand=k/n rot= size= gap=`); none passes → `no placement rejects=[..]` and a fail, nothing
   built. A failed B2 build unfreezes T1 and skips the UpdateSize steps. B1/B3 log again after 6 months.
   Maintenance cost: check the journal after a year by hand.
6. **C** (Growth tab, a fresh 2000 game): C1 on flat empty land, C2, screenshots of the 6 towns; reload the save
   and run C3 + G to see whether the runtime angle equals the param on a loaded save.
7. **Join tab, one variant per save:** **save a backup first**, camera at a fresh town dead end each time:
   D1, D2, D3, D4, D6. After each: look for the red dead-end sign at the node, drive a bus line through it
   (busPath is manual), reload the backup if it looks broken. Repeat the winner on 3 dead ends.
8. **Risky, last:** backup save, then **D5** (camera on a segment between two junctions), then in a fresh save
   with a backup **D7** (camera at a T junction), one try each. Both need a second click within 8 s.
9. **Long waits:** **A1** then **A2+A3** (12 months); **F1**, then (after D2 passed, backup) **F lock T3 dead ends**
   (confirm click), then **F2** (grow + 24 months); **K** then **K reset**. Unfreeze T1 when done.
10. **Setup > Dump report**, grep the report block, then add each result to `docs/findings.md`.

Simplified vs. the plan above: the HUD dead-end sign and the bus drive test are manual (`deadEndLikely` = 0 lanes
on a node with 2+ edges, `busPath=manual`); B's yearly maintenance is read from the journal by hand; F's
`aiLock` template check is skipped (no TF3 code reads `aiLock`, RESEARCH.md section 2); F locks T3's dead ends
with D2's replace-node pattern (a copy with the flag), so run it only after D2 passed; H's sim stall comes from
the game script's `H ctx=gsUpdate` line (wall time between 60 updates after each build).

| Probe | Status | Key result |
|---|---|---|
| A | not run | |
| B | yes (2026-10-11) | script streets get parcels gradually as the town reaches them (no configs needed), then fill; geometry kept |
| C | not run | |
| D | yes (2026-10-11) | D3 with the engine lane pattern: no sign. Rule: config remove only if it exists |
| E | run (2026-10-11) | slopes ok to 16 % (terrain z), water refused silently |
| F | not run | |
| G | run (2026-10-11) | climate/nameList only in runFn; runFn global visible in GS update + guiUpdate, not HUD |
| H | not run | |
| I | run (2026-10-11) | HUD onStep and GS guiUpdate are different Lua states; callback ~390 ms |
| J | run (2026-10-11) | getSegment2ParcelData ok; town box ≠ extent (use buildings) |
| K | not run | |
