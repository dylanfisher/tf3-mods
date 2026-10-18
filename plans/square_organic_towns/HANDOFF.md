# Organic Towns: handoff (2026-10-11)

State after Phase 1 (probe) and Phase 2 (pure core). Read with PLAN.md, PROBE.md (status table) and
docs/findings.md sections "Organic Towns probe, first run" and following bullets (all dated 2026-10-11).

## What is proven in game

- **Region/climate:** only `runFn(captureParams, configDict, …)` gets `climate`/`nameList`; store them in a global
  there. That global is visible in game-script `update` and `guiUpdate`, **not** in GUI plugin/HUD states.
  `getConfigDict()` at runtime lacks them. baseConfig set in `preRunFn` reads back at runtime.
- **Lua states:** GUI plugin `react.onStep` and game-script `guiUpdate` (Main Thread, ~110 Hz) are different states.
  Commands from onStep get callbacks after ~300–400 ms.
- **Street proposals** (`SimpleProposal` + `makeWorldBuildProposalCmd`, `town_new_small` components copied from a
  town edge): z following terrain builds up to ~16 % terrain; the engine cuts/fills. Streets touching water are
  refused **silently** (pre-check ok, build `success=false`, no message): avoid water with `isOnWater` yourself.
  Town street templates: `maxSlopeBuild` 0.2, `minCurveRadiusBuild` 60 m; only plain variants are `simBuildable`.
  18-edge proposals: ~70–380 ms, cost 300–500k. Pre-checks (`makeProposalData`) ~1–3 ms: try many candidates.
- **Joining a town dead end (D3):** plain join (new edge references the dead-end node) **plus** a node config in the
  engine pattern: for every ordered pair of different segments at the node, `A.1 > B.2` withRoad (lane indices are
  node-relative; no sidewalk entries). Put the node in `nodeConfigsToRemove` **only if it has a BASE_NODE_CONFIG**.
  Result: no red dead-end sign. Plain join alone = blocked (sign). Removing a town edge (D4) demolishes its houses
  (776k). Coincident node + cleanup (D6) refused.
- **Adoption:** script streets start with **no parcels** (not in `getSegment2ParcelData`) and no node configs. The
  town adopts them **gradually** once its network/development reaches them: parcels appear edge by edge (no configs
  needed), houses follow demand. Growth kept the script geometry, and the engine's own new streets continued the
  grid lines. A patch behind a blocked joint was adopted only after the town reached it another way.
- **Forcing growth for tests:** `makeTownUpdateSizeCmd(town, sizeFactors × k, true)`, repeated passes.
- **Parcels/extent:** `getSegment2ParcelData()` (no arg) + `getParcel2BuildingMap()` + `PARCEL.streetSegment`.
  The town entity's bounding box is not its extent (28 % of buildings inside): use building positions.

## Crash traps (all in findings.md and memory)

- `parcelSystem.getParcelData(edge)`: native crash. Never call it.
- `nodeConfigsToRemove` on a node without BASE_NODE_CONFIG (every script-made node): assert, crash.
- `rawget`/`rawset` are nil in GUI and game-script states: load crash / endless "Expected table" loop.
- A running game keeps old Lua modules: quit TF3 fully after code changes.

## Open (not blocking Phase 3)

- Probe A (what freezing stops), H (timing at scale), K (density weights), C visuals (angle knobs),
  F lock test (`roadDevelopmentLocked`), whether configs on every new node speed adoption (probe toggle exists).

## Phase 2 preview issues to fix first

NA grid minor streets wobble (organic jitter applied to grids); outer EU/MED blocks too small/jagged (needs a
minimum block size from parcel depth: lots are 8 m cells, up to 4 deep); too many dead-end stubs.

## Phase 3 (2026-10-11, offline)

NA-grid MVP built and linked: PLAN.md 6.2, in-game checklist TESTING.md. The Phase 2 preview issues above are
fixed (PLAN.md 6.2). Next: the user's in-game run, then findings.md entries from its `[SQOT]` log.

## After the first in-game run (2026-10-11)

All 16 fresh towns logged `needsRoom=false`: the trigger is rewritten around open frontage (PLAN.md 6.2 "Trigger").
New DEV mod `square_organic_towns_dev` (never upload; TESTING.md "Dev tools"): inspector, Grow now, city types,
fast-forward, dry run with markers, undo, pause/debug hooks (`ot_hooks`). Unverified in game: the HUD <-> game
script events (`fireGuiScriptEvent` / `fireReactEvent`), the cross-mod `ug_require`, whether the dev game script
shares the main driver's Lua state, undo's removal proposal, the markers, and joining our own config-less dead ends.

## EU organic refusals fixed offline (2026-10-11)

In game NA grid built via Grow now, every EU organic increment was refused (`Construction_Not_Possible`). Offline
cause: curved edges of 3-60 m radius (templates: 44 m final proposal, 60 m player tool); fixed in the planner
(smooth plan lines with exact tangents, edges >= 70 m, `ot_check`), PLAN.md 6.2 "Curves". New dev tools: per-edge
diagnosis (`DIAG`/`DIAGSUM`) and the "Build as player" toggle for the BaseNodeConfig crash bisect (TESTING.md
"Curved styles, per-edge diagnosis and the player test"). Builds currently charge the player (context has it).

## Irregular growth + showcase (2026-10-11, offline)

The planner now grows towns unevenly per style (seeded sector preference, ribbons along main streets, hotspots,
coast lean; PLAN.md 6.2 "Irregular growth", metrics table, `ot_metrics`). The dev mod has **Showcase: build all**
for a Blank Slate map (16 labelled towns: every style, era town, controls, Probe C angles; grown unattended,
Stop/resume, Next/Previous town camera): TESTING.md "Showcase". Unverified in game: createTowns from the dev game
script's guiUpdate, TownInfo angle units, the camera calls (distance easing, top-down pitch), curved styles
building, adoption between increments (Join own dead ends may be needed).

## Showcase v2 (2026-10-11, offline)

From the first showcase log and screenshots: lane assertion fixed and validated before sending, collisions drop
the failing edges instead of halving, DIAG works (message text has spaces), narrower templates, leads capped,
batched rounds, era row (1900), adoption numbers (mod / vanilla edges, houses on mod streets), Results table, Auto
tour + screenshots, Reset showcase, Fill / Freeze probes, roundabout probe with square_roundabouts' geometry.
PLAN.md 6.2 "Showcase v2" + "Roundabouts", TESTING.md "Showcase v2". Unverified in game: all of it.

## After the settled showcase (2026-10-11, late, offline)

Roundabout configs on every new node (one-way ring pattern derived, behind a dev toggle), planner self-collision
checks and junction-star diagnosis, look rules (no zig-zag chains / lassos), town shape archetypes (`ot_shape`,
PLAN.md 6.3), Showcase v3 (shape and density rows, settle, tour fix, Node dump), and the main-mod setting
"Vanilla town street angles" (preRunFn reads the region from its pairs-list config dict). NEXT_PHASE_BRIEF 6-7,
TESTING.md "Showcase v3". Unverified in game: all of it.

## Site styles, hierarchy, shapes, refusals (2026-10-12, offline)

Each town's style from its site (`ot_site`, main mod Automatic on every map), street hierarchy by era (wide only on
through routes), stronger shapes + growth front + corner rule, sliced planning, junction footprint rule and dev
`DIAGJOINT`; dev showcase v4 (settle by years / plateau, wider tour camera, upgrade once). PLAN.md 6.2 "Site
styles, hierarchy, stronger shapes, refusals", NEXT_PHASE_BRIEF 10, TESTING.md "Showcase v4". Unverified in game:
all of it.
