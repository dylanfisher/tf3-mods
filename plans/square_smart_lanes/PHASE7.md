# Smart Lanes Phase 7: road-aware merges, lane drops, exit lanes, bulk apply, stress bench

User request 2026-10-11: implement every step in its own subagent, review each step in a separate agent, then a
performance review and fix. Be extra careful about edge cases that could crash the game (see "Crash rules").

Status: Revision 4 of `mods/square_smart_lanes` is NOT uploaded yet. Keep `revision` 4 and add every user-visible
change to the Revision 4 changelog entry in `_metadata/description.html` (and the feature lists above it).
Nothing is committed; never commit. Never run `make modio` or any `op` command.

## Where things are

- Smart Lanes code: `mods/square_smart_lanes/content/smart_lanes/` (Lua 5.2-style, game Lua is pre-5.3).
  - `sl_ring.lua` world model (`world.node(id)`, `world.seg(id)`, lanes `{forward, road, car, tram, walk}`,
    `Ring.lanesAt(seg, node)` -> `{e, incoming, outgoing, busOnly}` connection indices, `Ring.segLength`).
  - `sl_slip.lua` slip-lane junctions: `S.classify` (case A all one-way, case B two-way + one-way branch, case X
    handed to `sl_cross.lua`), `S.pairs(shape, ...)` the lane rule on counts, `S.roadConns`, `S.plan`.
  - `sl_cross.lua` crossroads / T-junctions (also one-way roads meeting two-way ones), game-default model.
  - `sl_rules.lua` conn tables, `connsText`, `mergeTram`, `remapLocked` (traffic light phases), mod params, log line.
  - `sl_write.lua` GUI-thread read/write (`makeWorld`, `currentConns`, `buildEntry` incl. light-phase remap,
    `sendConfigs`, lights).
  - `sl_lanes.script.lua` automatic pass after player builds (engine thread queues jobs, GUI thread processes).
  - `sl_toolcore.lua` + `sl_tool.script.lua` + `sl_pick.lua` the Roads -> Tools -> Smart Lanes tool.
  - `sl_lights.lua` which nodes lose traffic lights.
  - `sl_audit.lua` the junction audit (AUDIT lines, `make audit`; TESTING.md X).
- Tests: `tests/square_smart_lanes/` (`fixtures.lua` builds worlds: `F.build(nodes, segs, mirror)`, lane templates
  `F.TPL`; `test_slip.lua`, `test_cross.lua`, `test_script.lua` fake game for the automatic pass, `test_tool.lua`
  fake game for the tool). Run ONLY `make test MOD=mods/square_smart_lanes` (and `MOD=mods/square_stress_test`
  when that mod is touched). Also `make check MOD=...`, `make validate MOD=...`, `make tooltips MOD=...`,
  `make i18n MOD=mods/square_smart_lanes ARGS='--check --lint-modinfo'`.
- Plan / test docs: `plans/square_smart_lanes/PLAN.md`, `TESTING.md` (add a section per step), this file.
- Stress Test mod: `mods/square_stress_test/` (Teal `.tl`, English only), tests `tests/square_stress_test/`.
- Project rules: `CLAUDE.md` (translations: every new user-visible Smart Lanes string in all 13 languages in
  `strings.json`; tooltips wrapped with `\n` at ~60 columns; log lines stay English).
- Game API docs: `.cache/game/api/tealdef/` (use `rg --no-ignore`), base game code `.cache/game/base/content/`.
- Verified game facts: `docs/findings.md` (read "Junction lane connections" and its traffic light subsection).

## Conventions of the lane rules

- Lanes are listed kerb first (lane 1 = kerb side: right in right-hand traffic). Turn angles are signed, left
  positive. Every rule must keep the invariants the tests check: no two connections of one travel direction cross,
  every incoming road lane has a connection, every outgoing road lane is fed, no U-turns, tram connections kept
  (`Rules.mergeTram`). Both traffic sides (fixtures `mirror = true`).
- The automatic pass only touches nodes of the player's build (`job.nodes`); the tool touches what is selected.
- Every new rule logs through `Rules.line` (`[SQRL] KIND k=v ...`), English.

## Crash rules (from earlier crash dumps and findings; treat each as a hard requirement)

1. Traffic light phases (`trafficLightConfig.states[i].lockedLanes`) are 0-based indices into the node's lane
   connections then crosswalks. Any lane write MUST go through `W.sendConfigs` / `W.buildEntry`, which re-points
   them (`W.remapLights`); never build a node-config entry another way. A node whose phases cannot be re-pointed is
   skipped, never written with stale phases (crash 2026-10-11: VectorMap.h:11 `key >= 0`).
2. Never send `nodeConfigsToRemove` without a matching `nodeConfigsToAdd` entry for that node (deletes the config,
   crashes). Never touch a node without `BASE_NODE_CONFIG` (`buildEntry` returns "no_config").
3. Connections may only name segments that are attached to the node now (re-read in the same frame before writing;
   a stale segment id crashes `StreetShapeFactory.cpp:195 lc.segment1 not found`). Lane indices must be valid for
   that segment at that node (`Ring.lanesAt`). Re-read the world right before a write; never write from a cached
   world older than the current frame's selection.
4. No `api.cmd.sendCommand` inside build events (game-script `handleEvent`); queue and send from `guiUpdate`.
5. No `state:get_native()` / `findPath` in game scripts (gamescript_util.cpp:385 assert).
6. GUI calls only on the GUI thread: React `onStepTimer` / `hudIconScript` run on worker threads; use `onStep`
   (Main Thread). No `getApplicationTime` in HUD recipes.
7. No `rawget` / `rawset` in GUI states (nil there, load crash). Guard with `pcall`.
8. React recipes: every custom recipe returns a `BoxLayout` at its root; `ScrollArea{content = Component{layout =
   ...}}`; never `Component{layout = MyRecipe{}}`; `ImageView` has no `mouseTransparent`.
9. NodeViewer must never be asked for more edges than the node's network has (in-game crash 2026-10-08): build its
   spec only from the node's current connections.
10. Do not add stylesheet rules (`*.css.lua`): the game crashes on load above ~200 mod CSS rules in total.
11. A `.lua` / `.tl` main chunk has at most 200 locals; keep new files small or scope blocks in `do ... end`.
12. Lua is pre-5.3: no `//`, no bit operators, no `utf8`, no `math.tointeger` in `.lua`; `make check` lints.
13. Every new API read is wrapped in `pcall` where the entity may have vanished (a node or segment bulldozed
    between selection and Apply, a job's node gone by the time it is processed). Missing world entries return nil;
    code must treat nil segments / nodes as "skip", never index them.
14. Bounded work: every graph walk has a hard cap (distance and node count), so a pathological network cannot
    hang a frame; per-frame work in the tool stays small (spread bulk writes over frames; one proposal per batch
    of at most ~40 nodes).

## Steps

### Step 1: look-ahead checks for the "ramp keeps its own lane" merge
Current rule (`sl_slip.lua` `S.pairs("merge", T, B, O)`): when `T + B > O and O - B >= 2` the branch keeps its own
kerb lanes and the through lanes fold among themselves. Make it road-aware: a pure helper module (e.g.
`sl_walk.lua`) that follows a road through plain 2-road nodes (with caps: distance ~400 m, ~12 nodes), and in
`S.classify` / the plan decide per merge stream:
- upstream: if the through road had at most `O - B` road lanes in its travel direction within the walk (its kerb
  lane was added nearby), the ramp keeps its lane;
- room: if the through road's distance back to the previous junction (node with 3+ road segments) is under ~80 m,
  keep the give-way merge (no room for through lanes to merge among themselves);
- if the through road carried all T lanes for the whole walk (a real T-lane road), keep the give-way merge,
  unless downstream within the walk the out road's kerb lane leaves at a diverge / turn (ramp traffic wants it);
- downstream: if the out road drops lanes from the kerb side soon after (within ~150 m), keep the give-way merge.
Log the decision (`merge=own_lane|give_way` plus a short `why=`) on the APPLY line. Tests for each branch, both
traffic sides, and the walk caps (a long loop of plain nodes must stop).

### Step 2: plain lane drops and gains (2-road nodes)
Nodes with exactly two road segments where a travel direction's lane count changes (e.g. 3 -> 2, or 2 -> 3) are
"none" today. Add a case (e.g. "D") handled in the automatic pass and by the tool (Apply / badge; Reset needs a
game-default model only if one can be derived; otherwise snapshot Reset like slip nodes). Rule: lanes matched from
the far side, the kerb lane(s) end (fold into the kerb-most continuing lane); gains fed by the kerb lane. Only when
the count actually changes and both segments are road (no bus lanes, tram kept). Do not touch nodes where nothing
changes, and never ring nodes (rings are handled first). Lights: leave them (`Lights.slipNode` false for D).
Translations for any new tool text (e.g. a head line "Lane drop, %s").

### Step 3: exit lanes before off-ramps (diverge counterpart)
Diverge rule (`S.pairs("diverge", N, T, B)`): with `N <= T` the kerb lane feeds the branch AND continues straight.
Mirror the merge rule: when the main road has 3 or more lanes and through traffic keeps at least two lanes, make
the kerb lane exit-only (consistent with the crossroads rule "3+ lanes: kerb lane turns only"); use the Step 1
look-ahead (e.g. keep shared when the through road gains its lanes back right away is irrelevant; keep shared when
the branch has 2+ lanes and N - B < 2). Keep every out lane fed (an unfed through lane is fed by the next lane).
Tests + log fields (`diverge=exit_only|shared`).

### Step 4: tool, click a road to select its junctions
In the Smart Lanes tool, clicking the middle of an ordinary (non-ring) street segment selects every handled
junction along that street (walk both ways through plain 2-road nodes and through junctions while the street
continues straight-ish (|turn| <= 30 deg) with the same lane layout; caps: 60 junctions, 3 km; superseded by Step 4b: plain click = ends only, Shift = 10 junctions / 1 km). Show them in the
overlay (existing highlight path), head "Street: %d junctions" (translated), badge from all of them
(smart / default / custom / partial). Apply writes them all (batches, one proposal per batch, each entry through
`W.sendConfigs`), Reset writes the game-default model where one exists (crossroads), snapshot elsewhere, and skips
(logs) nodes without a model or snapshot. Re-read every node right before writing (crash rule 3); a node that is
gone is skipped.

### Step 5: tool, paint an area (brush) like Bulk Bulldozer
**Cancelled by the user 2026-10-11 ("we don't need the paint brush idea yet"); not implemented.**
Research notes kept for later: junctions in a circle via `api.engine.util.octree.findEntitiesInCircle(Vec2f, r,
BASE_NODE)` (`api/engine/util.d.tl:329`; used by `square_roundabouts_lanes_probe` lanes.script.lua:363 and
`parallel_tracks` parallel_tracks.script.lua:269), pcall-wrapped; one `Slip.plan` per node gives handled + badge;
toolbar: a multi-value Button param for Pick/Brush, a Slider with `numbers` for the radius (values reach the recipe
in the params map of `checkEnabledFn`); Selector: LMB Pressed/Released arrive, RMB only as PressedOutside + Clicked
(Bulk Bulldozer in-game log).
Add a brush mode to the Smart Lanes tool: drag to paint a selection of junctions inside a radius (reuse the ideas,
not the files, of `mods/square_bulk_bulldozer/content/bulk_bulldozer/bb_brush.tl` / `bb_select.tl` /
`bb_gather.tl`: terrain ring under the cursor, strokes add to the selection, Shift removes, right click / Esc
clears; cap 400 junctions). Apply / Reset work on the painted selection like Step 4. Toolbar control to switch
"Pick" / "Brush" and a radius control, translated. Read Bulk Bulldozer's findings in its PLAN / code comments for
the Selector / mouse event quirks. No new CSS rules.

### Step 4b: street pick limited (user decision 2026-10-11, "Ends only, Shift extends")
A plain mid-road click selects only the handled junctions at the clicked segment's two ends (first 3+-road junction
each way, plus handled lane-drop nodes between); Shift+click follows the street further with caps 10 junctions /
1 km. Shift read like Bulk Bulldozer (IA_PRECISION_MODE at the LMB press), fallback = plain click.

### Step 5b: multi-select and the lane view for all of it (user request 2026-10-11; replaces the brush)
- Shift+click a junction adds it to the selection, Shift+click it again removes it; Shift+click a road adds that
  road's junctions (Step 4b's extended walk). A plain click starts a new selection (as now). Right click / Esc
  clears. Cap 60 junctions (log + status when the cap is hit). Rings: Shift+click on a ring junction adds that
  junction (ring node rules, Apply per junction) — or keep rings out and say so; decide and document.
- Target kind "multi": head "%d junctions selected" (translated, plural pair), badge from all (smart / default /
  custom / partial), Apply to junction / Reset act on all through the Step 4 batch job (fresh world per batch,
  snapFits, W.sendConfigs, busyJob), Apply to roundabout greyed.
- Lane view: show the lane connections of EVERY selected junction at once. Research how the tool's NodeViewer
  overlay is built (sl_toolcore nodeViewerSpec, sl_tool.script.lua world layer) and whether the game's NodeViewer
  takes several nodes; if not, draw one NodeViewer per node or the connections as overlay lines. Crash rule 9: each
  node's spec is built only from that node's CURRENT connections in the same frame; never ask for more edges than
  the node's network has; skip nodes that vanished. Bounded: cap the drawn junctions (e.g. 60) and refresh on the
  existing 30-frame cadence, not per frame.
- Hint text: reword Step 4b's Shift hint to cover both (e.g. "Shift+click: add a junction or road"), 13 languages.
- Done 2026-10-11 (TESTING.md section S). Decisions: ring arm junctions join (Apply: `Rules.planRing` seeded with
  the batch's selected junctions of each ring, inside the street batch job; Reset: engine-default model); a street /
  ring that holds the whole selection replaces it (keeps Step 4b's "Shift+click a plain street = follow it"); Shift
  with nothing (handled) selected = a plain pick; unhandled junctions are not added ("Not handled: not added to the
  selection"). Lane view: one NodeViewer (its nodeConfig map takes several nodes, as for rings), streets included,
  spec kept per selection signature for at most REFRESH_FRAMES. The tool's menu description is not a tooltip (the
  info callout wraps it, construction.css.lua textAutoWrap), so it stays one paragraph. Review 2026-10-11: lane view re-rendered once a write is judged (`C.nvHeld`; it stayed
  hidden after a multi Apply in game), the spec cache dropped at every refresh, a failed ring check in a multi batch
  skips the node, the lane status chip lost its "Current lanes: " prefix (user).

### Step 6: Stress Test bench + skip summary
- Smart Lanes: per processed job one `SUMMARY` log line: counts per outcome (`ring=`, `slip=`, `cross=`, `drop=`,
  `same=`, `skip=` and the skip reasons with counts, e.g. `skips=branch_turn:2,ambiguous:1`).
- Stress Test: make the Junction test and the Crossing test able to put traffic on the junctions (research what
  `stress_traffic.tl` / `stress_buslines.tl` already offer: e.g. a toggle that runs the existing traffic generator
  on the built test), and a short in-game summary of what was built. English only. Keep `tealdef/stress/
  stress_types.d.tl` identical to `content/stress/stress_types.d.tl`.

### Step 7: performance review and fixes
Review the automatic pass and the tool for per-frame cost (walks, plans, badge refresh, brush sampling, overlay),
with the SQPERF instrumentation (`plans/sqperf/README.md`); add timing to new sections; fix hot spots; keep tests
green. Write the findings to `plans/square_smart_lanes/PERF_REVIEW.md` (append a Phase 7 section).
- Done 2026-10-11 (PERF_REVIEW.md "Phase 7", TESTING.md section U): per-world memos (lanesAt, roadSegs, ring
  search, classify), config reads once per world for display, a per-junction status cache and a street-walk cache
  (segments + connections / segments, 300 frames), a 30-frame hover world; SQPERF job_ring / job_classify /
  job_write and the tool's resolve / badge / refresh / multi_add / batch / nv_spec / highlight; APPLY `via=`.
  Benchmarks: test_script.lua / test_tool.lua "perf: ...".

Order after the 2026-10-11 changes: 4b (with 6 in parallel), 5b, then 7. Every step gets a separate review agent.

## Review checklist (each review agent)
- Read the step's diff (`git diff` on the touched files; new files in full).
- Crash rules 1-14 against every new code path, especially: nil segments / nodes, lanes indices, stale world,
  phases, remove-without-add, thread, unbounded loops.
- Invariants and both traffic sides covered by tests; tests pass; `make check`, `make validate`, `make tooltips`,
  `make i18n ... --check` clean.
- Translations complete for new strings; docs (description changelog, TESTING section) updated.
- Fix what is wrong directly (small, targeted), rerun the gates, and report what was found and fixed.
