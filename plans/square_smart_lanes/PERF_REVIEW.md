# square_smart_lanes: performance review

## 2026-10-08: no changes made

Verdict: nothing worth fixing. The hot paths already have throttles and caches (hover cache, refresh every
30 frames, badge cache keyed by ring + connections, segment memos, state polls every 5 or 10 ticks), and
the costs that remain are bounded and infrequent. No mod code changed and there is no revision bump.

### Measured (offline, fake api, Lua 5.4 via lupa; a throwaway probe test, since deleted)
| path | frequency | cost | component reads |
|---|---|---|---|
| tool hover, cached frame (`C.onHover` + `C.step`) | every frame while hovering | ~30 us (incl. amortised 30-frame re-resolve) | ~1.5 |
| `C.resolve` ring node (4-junction probe ring) | new hover target, every 30 frames, click | ~0.33 ms | BE 8, BN 5, BNC 10, segs 4 |
| `C.refresh` (ring or node selected) | every 30 frames with a selection | ~0.32 ms | BNC 10-12 |
| `C.resolve` two-way crossroads node | new hover target | ~0.05 ms | 8 |
| `C.highlight` / `C.nodeViewerSpec` | re-render (version change only) | 7 / 80 us | 4-8 |
| `C.actions` (3x checkEnabledFn per menu step) | every frame, tool open | 0.1 us | 0 |
| worst case: `C.resolve` in a 20x20 one-way grid without rings | new hover target | ~2.4 ms | BE 230, BN 103 (search cap 160 nodes, 600 m bound) |
| worst case: auto job with 160 seeds in that grid (shared world) | once per player build | ~32 ms in one GUI frame | reads cached per job |

### Examined and deliberately not changed
- **Engine `update` / `handleEvent`** (`sl_lanes.script.lua`): `hasEventSubscriptions` per tick, `state:get()`
  every 10 ticks on a state that is nearly always empty, and only `onPostBuildProposal` subscribed. Negligible.
- **GUI `guiUpdate`**: `state:get()` every 5 frames, early return when there are no jobs or verifies. Negligible.
- **Ring search** (`sl_ring.shortestCycle`): Dijkstra with a linear scan of the open set. Capped at 160 nodes
  and pruned by the straight line back to start. On a cached world a full 100-node search costs ~170 us, so a
  heap would save perhaps a third of that in a rare case. Not worth the risk.
- **Job of 160 seeds in a ring-less one-way grid** (~30 ms once per build): pathological (one-way city grids
  are rare in TF3). Highway builds are cheap because the 2x-distance bound limits each search to about 600 m
  (~12 nodes). Spreading seeds over frames would change job timing and add state, so it was left alone.
- **Duplicate `BASE_NODE_CONFIG` reads in `resolve`/`refresh`** (`ringStatuses` runs for both the badge and
  `canInfo`, plus `targetSig`): about 5 extra reads at 2 Hz. Not measurable in practice.
- **Hover sweep over one-way networks**: every new target does a fresh `makeWorld` and search (up to ~2.4 ms in
  the grid worst case). A world cache shared between resolves would serve stale geometry after a build. Left alone.
- **Selector filter `isStreetThing`** and **`Pick.allow`** log limiter: 1-2 component reads or one short string
  per call. Negligible.
- **Crossing Tool arrow patch** (`getActionParams` wrapper): runs when the construction action re-renders
  (construction.tl:4438), not every frame. Negligible.

### In-game check list
Nothing changed, so no new checks. If a stutter is reported: open the tool over a large one-way street grid and
sweep the mouse, then build a large one-way grid with Apply automatically on, and watch the frame time.
