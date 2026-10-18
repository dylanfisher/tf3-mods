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

## 2026-10-11: Phase 7 (step 7): caches and memos, new SQPERF sections

Revision 4 (not uploaded yet); changelog line "Faster: ..." added to its entry.

### Method
Offline micro-benchmarks in the tests (Lua 5.4 via lupa, fake api; printed, asserting only read-count bounds):
`test_script.lua` "perf: a 160-node job ..." (the automatic pass through the real script: build event, one
job frame) and `test_tool.lua` "perf: hovering along a 3 km road", "perf: Shift+click into a 60-junction
selection and its refresh", "perf: refresh of a selected street". Numbers from `uv run tests/run_tests.py -j 1
-k perf mods/square_smart_lanes` (one process; runs vary by about 10-20 %). Reads = component reads of the fake
api: BN = BASE_NODE (plus getNodeStreetSegments), BE = BASE_EDGE (laneConfigs converted), BNC =
BASE_NODE_CONFIG. In game a read costs far more than offline Lua, so the read counts are the better guide.
Profiles with a sampling `debug.sethook` (throwaway, not committed).

### Results (before -> after)
| scenario | before | after |
|---|---|---|
| job, 160 mixed nodes (6 Channelized X, 4 ramp nodes, 8 merge / diverge lines, 7x7 one-way grid) | 14 ms (BN 175, BE 216, BNC 353) | 10.6-11 ms (same reads) |
| job, 160 nodes of an acyclic one-way grid (a full ring search at every node) | 14 ms | 13.6 ms (search-bound) |
| job, 160 Channelized X centres (bypass walks at every node; worst case of the crossing rule) | 59-62 ms (BN 800, BE 1920, BNC 641) | 45-48 ms (same reads; now read-bound) |
| hover along a 2.8 km road (70 segments, 3 frames each) | 0.13 ms / frame (BN 742, BE 735, BNC 42) | 0.04 ms / frame (BN 718, BE 735, BNC 14) |
| hover along a 4 km road (capped street: a resolve per new segment) | 0.57 ms / frame, 100 resolves of 82 BN + 82 BE each | 0.11 ms / frame, 12 BN + 12 BE per resolve |
| Shift+click into a selection of 50-60 junctions (two-way / one-way chain) | 11.8 / 12.0 ms per click (BN 175, BE 181, BNC 171) | 0.6 / 1.5 ms (BN 62-75, BE 10-48, BNC 57) |
| Shift+click, average of clicks 2-50 | 5.8 / 6.2 ms | 0.4 / 0.8 ms |
| refresh of a 60-junction multi selection (every 30 frames) | 0.4 ms, BN 60 + BNC 180 | 0.28 ms, BN 60 + BNC 60 |
| refresh of a 2.8 km ends street | ~2.0 ms (BN 75, BE 74, BNC 6) | 1.0 ms (BN 71, BE 74, BNC 2) |
| refresh of a 10-junction Shift street, two-way / one-way | ~1.0 / ~2.3 ms (BN 32 / 46, BE 37 / 79, BNC 30) | 0.4 / 1.3 ms (BN 12 / 14, BE 32 / 36, BNC 10) |
| existing bench "street resolve (10 crossroads)" | 1.4-1.6 ms | 0.4 ms |
| existing bench "badge refresh" (4-lane ring, uncached / cached) | 1.0 / 0.37 ms | 0.5 / 0.22 ms |

The street refresh "before" was measured with the world memos off and the per-junction caches expiring at
once (the original code path); the other "before" numbers with the original code.

### Hot spots found
1. **Shift+click into a big selection** (earlier review (a)): the multi badge cache key holds the node ids, so
   every Shift+click missed it and planned all junctions again (up to 60 ring checks and 60 Slip.plan, each
   with walks), then the buttons asked for the same statuses again and the signature read every config a third
   time. 12 ms and ~525 reads per click at 60 junctions.
2. **Refresh of a selection** (b): three config reads per junction per refresh (badge, buttons, signature); a
   street's refresh classified every junction again (bypass walks, look-aheads) and searched a ring at every
   one-way junction (d).
3. **Hover along a capped street** (c): every new hovered segment re-walked up to 3 km of plain nodes in a new
   world (82 node + 82 segment reads per segment).
4. **Repeated pure work per world** (f): `Ring.lanesAt` was the top function in every profile (a new table per
   call, called again and again for the same segment and node); `Walk.roadSegs` rebuilt per walk step (bypass
   walks of neighbouring approaches pass the same nodes); `Ring.shortestCycle` ran twice for one-way lane drops
   (`ringThrough` and `classifyDrop`); the tool classified a node twice per pick (street walk, badge).
5. **Job worst case** (e): after the memos, a job of 160 Channelized X centres costs ~45 ms offline in one GUI
   frame and is read-bound (every segment read once: 1920 BASE_EDGE reads); the mixed job ~11 ms; the acyclic
   one-way grid ~14 ms (ring searches, as in the 2026-10-08 review). Not changed further: see open questions.

### Fixes and their invalidation
- **Per-world memo** (`sl_write` `W.makeWorld`: `world.memo`, and `atMemo` on each segment table): results
  derived only from that world's reads, so they are exactly as old as the world (one per job, pick, refresh,
  batch, or the hover world below). `Ring.lanesAt` (per segment and node), `Walk.roadSegs`, `Ring.shortestCycle`
  and `Ring.ringThrough` (per start node), `Slip.classify` (per node; a "no_side" view is not kept, since a later
  call may find the side another node remembered). Fixture worlds in the tests have no memo, so the pure
  modules behave exactly as before there. Callers only read the shared tables (checked: no writes into lane
  lists, views or rings outside their construction). Writes still plan in a world read in their frame.
- **Config reads once per world for display** (`sl_toolcore` `connsIn`): badge, buttons, signature and node
  target read each junction's connections once per world. Never used on a write path (Apply / Reset, batches,
  NodeViewer spec keep `W.currentConns`).
- **Statuses once per world** (`streetStatuses` memo in `world.memo.street`, keyed by the target table): badge
  and buttons of one pick share them.
- **Per-junction status cache** (`C.nodeStatusOf`, `C.nodeStatus`): a non-ring junction's status (smart / model
  / default / skip from its plan) keyed by the node's segment ids + its road connections, reused for at most
  `Core.NODE_STATUS_FRAMES` (300) frames, at most `Core.NODE_STATUS_MAX` (256) entries (cleared when full);
  shared by node picks (`slipBadgeInfo`), streets and multi selections. An entry made for a street junction
  (no ring check) does not serve a multi selection or a node pick, which need "not on a ring". Invalidation: a
  write changes the connections (new key), a rebuilt road changes the segment ids (new key); what the plan sees
  further along the roads (look-aheads, bypasses) shows within 300 frames. Display only: Apply / Reset plan
  every junction again in a fresh world (planStreetNode / planRingGroup / applySlip unchanged).
- **Per-node street-walk cache** (`C.nodeKindOf`, `C.nodeKind`): handled (classify kind "slip") and on-a-ring
  per node, keyed by its segment ids, 300 frames, 256 entries; a failing check is not kept. Used only by the
  street walk (which junctions a street selection holds); Apply re-checks every node (gone, no config, ring,
  classify) in its batch's fresh world.
- **Hover world** (`hoverWorld`, `C.dropHoverWorld`): hover resolves share one world for at most
  `REFRESH_FRAMES` (30) frames (as long as a hover target is reused anyway), dropped at every write callback
  (`scheduleVerify`), every re-read (VERIFY) and when the tool closes. A click (`C.select`), the refresh and every
  write read their own world, so the hover world never reaches a write or the NodeViewer.
- Crash rules 1-3, 9, 13: unchanged paths. Every write still re-reads the world and the node's connections in
  its frame (`sendBatch`, `applySlip`, `C.apply`, the job), `snapFits` checks segments and lanes against that
  world, and the NodeViewer spec reads connections and network edges together at render.

### New SQPERF sections
- Game script, `perfGui` (ctx gui), nested in `job`: `job_ring` (ring search at every job node, ring plans,
  their proposals), `job_classify` (Slip.plan of the other nodes), `job_write` (each `W.sendConfigs`, nested in
  `job_ring` for rings); counter `job_nodes`.
- Tool, `perf` (ctx gui), passed to `Core.new`: `resolve`, `badge`, `refresh`, `multi_add`, `batch`, `nv_spec`
  (only when the spec is built), `highlight`; nested in the script's `hover`, `select`, `step`, `world_render`,
  `apply_node` / `reset`.
Any call over 16 ms logs a slow line even with the debug setting Off; TESTING.md section U lists what to read.

### Also
APPLY lines of nodes with one-way roads that went to the crossing rule carry `via=<slipReason>` (main_bend,
terminal, branch_turn, two_branches_one_direction, far_side_branch, and the new three_two_way /
one_way_square for the two other hand-over paths), right after `case=X`.

### Open questions
- A 160-node job of Channelized X centres takes ~45 ms in one GUI frame offline (read-bound), the mixed job
  ~11 ms. If `job` / `job_classify` slow lines show up in game after big builds, spread the job over frames
  (e.g. 40 nodes per frame, a fresh world and one proposal per chunk, rings planned whole in the chunk that
  finds them). That changes the one-proposal-per-job shape (WRITE / VERIFY lines per chunk), so it was left
  for the in-game numbers.
- The refresh of a selected long ends street still re-walks all of it every 30 frames (~75 node + 75 segment
  reads for 3 km); the walk needs the reads. If `refresh` is slow in game, re-walk only every few refreshes.
- `Core.NODE_STATUS_FRAMES` = 300 is a guess at how long a stale badge after a change further along a road is
  acceptable (about 5 s at 60 fps).

### Review 2026-10-11 (step 7)
- Write paths traced: `C.applySlip`, `C.apply` (ring), `sendBatch` (street / multi, incl. `planRingGroup`) and the
  automatic pass (`processJob`) each build a fresh `W.makeWorld()` and read `W.currentConns` in their frame; no
  write reads the hover world, `connsIn`, `streetStatuses`, `C.nodeStatus` or `C.nodeKind`. Memo tables live in
  `world.memo` / per-segment `atMemo` of one world; the module-level weak tables of `sl_ring` (`lenMemo`,
  `oneWayMemo`) are keyed by segment tables, which every world makes anew. No caller writes into a memoized view,
  ring, lane list or road list (all assignments happen while building them).
- Cache keys of segment ids hold: a street change removes the edge and adds it anew (`api/type.d.tl`
  SimpleProposal: "The same rule applies to streets and edgeobjects"), so a lane change gives new ids.
- Clear-when-full at 256: a street walk longer than 256 nodes (ends mode can pass up to `Street.MAX_NODES` 400)
  clears `C.nodeKind` during the walk, which then costs what it did before the cache, never more. Not changed.
- Added tests: a rebuild inside the hover world's lifetime (node and multi Apply write the new segment id), a
  poisoned status cache never stops Apply, worlds never share memos (test_tool.lua "review step 7"); a world
  memo keeps no "no_side" view (test_slip.lua "review step 7").
- 45 ms job: no cheap safe split exists without changing the write shape: in the worst case nearly all time is
  `job_classify` (the ring check exits early at two-way nodes), and planning in an earlier frame than the write
  would break crash rule 3. Chunking (open question above) remains the fix if `job` slow lines show in game.

## 2026-10-12: the automatic pass spread over frames, cheaper lane writes

Revision 4 (not uploaded yet); changelog line "Smoother: ..." added to its entry.

### Evidence (in game)
Stress Test Lights showcase at 8x game speed, session `2026-10-12_2129_top-up-530609` (`uv run tools/perf_report.py
--last --mod square_smart_lanes $(uv run tools/game_logs.py path 2026-10-12_2129_top-up-530609)`): 147 jobs in
~420 s, most of them 160 nodes with 156 lit crossroads (SUMMARY `cross=156 ... free_turn=~570 kept=ped:~560`,
Free curb turn When safe, Light phases Game default). Per call: `job` avg 96.7 ms / max 237 ms, `job_write` avg
69 ms / max 141 ms, `job_classify` 21 / 79, `job_audit` 7.6 / 18, `job_ring` 4.2 / 17; `gui_update` max 237 ms;
`verify` max 21 ms. Every job was one GUI frame: the stutter the user saw at 8x.

### Where the time went
Offline, a 13 x 13 grid of lit two-way crossroads (the game's six phases, crosswalks = edge ids, When safe), the
same shape as the showcase, profiled with a sampling `debug.sethook` and timers around the write path
(Lua 5.4 via lupa, one process; throwaway tests, not committed): the job took 152 ms in one frame, 85-90 ms of
it in `W.buildEntry` (157 nodes), Slip.plan ~26 ms, the audit ~15 ms.
1. `Rules.remapLocked` (the phase re-pointing) rebuilt three string-keyed maps of the old connections for every
   phase: 6 phases x 2 (plain and relocked) per node, ~36 old connections each, `string.format` keys: the top
   function of the profile (~30 % of the job).
2. `Lights.kerbPhases` (When safe, twice per node: LOCK of the old phases, then SAFE) ran `kerbConflict` per curb
   connection per phase, each a full scan of the connections with string keys; plus `isIndex` per index of every
   phase.
3. `W.buildEntry` read the node's BASE_NODE_CONFIG three times (existence check, old connections, the strategy's
   copy): in game each read converts the whole config (connections, phases, crosswalks).
4. The curb diff in `W.remapLights` scanned the phase lists per curb connection per phase.
In game the native side (config reads, `LaneConnection.new` / `TrafficLightState.new` per entry, the clone of the
light config) is on top; it cannot be measured offline, which is why (3) matters more there than its offline share.

### Fixes (results unchanged)
- `Rules.remapper(old, new, crosswalks)`: the connection matching once per node, then one cheap pass per phase;
  `Rules.remapLocked` is that remapper applied once (same result by construction: last old index per key, all of
  a movement / an incoming segment otherwise).
- `Lights.kerbPhases`: each curb connection's conflict candidates (other approaches' connections into its exit,
  each already classed merge / cross / beside) and the crosswalks that count are worked out once per call
  (`conflictInfo`), the per-phase check only looks at those (`conflictOf`, same order: merge before cross before
  ped); the index check inlined. `L.kerbConflict` keeps its signature (the two helpers).
- `W.buildEntry`: one config read for the check, the old connections and the first strategy try (a failed try still
  reads afresh); BASE_NODE_CONFIG reads of the showcase-shaped job 786 -> 472.
- The curb diff with per-phase sets.
Offline (5 runs, best): `W.buildEntry` 85-90 -> 32-35 ms for 157 nodes; the whole one-frame job 152 -> 89-100 ms.

### Frame budget (`sl_lanes.script.lua` stepJob)
A job now runs in steps over GUI frames, `BUDGET_MS` = 8 ms of `api.type.Clock` time per frame:
- Phases: start (game-zone filter, in that frame's world) -> ring (one job node per step: ring search, and a
  ring found: its plan and its whole proposal in that step) -> slip (one node per step: `Slip.plan` and, for an
  apply node, its entry built at once into the frame's batch with `W.addItem`) -> SUMMARY -> audit (one
  junction per step) -> AUDIT_SUMMARY. A step starts only while the frame's time plus the running average of
  that kind of step (`G.est`) fits; the first step of a frame always runs. At the end of the frame its slip
  entries go out in one proposal (`W.sendBatch`).
- Fresh reads: every frame makes its own `W.makeWorld()`; a node's plan and its entry (config read, phase
  re-pointing, strategy) come from the same frame, so no write carries a read from an earlier frame (the per-world
  memo never spans frames). What carries over is bookkeeping only: the tally, rings done, nodes on a ring (a node
  found on a ring in an earlier frame is left to that ring's proposal; if the ring was bulldozed since, the
  bulldoze's own job handles the nodes), the planned connections the audit compares with, the job's zones
  (snapshot at its start).
- Proposals: each node in exactly one proposal of the job, a ring's junctions always in one proposal (its step),
  slip entries in one proposal per frame that built any. The pending-proposal guards hold: a slip node is in
  `inflight` from its step until its frame's proposal answers (released at once if nothing was sent or the send
  failed); `busyNode` also covers the nodes of the job in progress for callers outside its steps. Ring proposals
  and lights-off proposals hold their nodes in `inflight` the same way (review 2026-10-12), and a due job starts
  only when none of its nodes is held: the next job never reads a node whose previous write (the last frame's slip
  part, a ring, a lights-off: findings roads.md "pending traffic light change ... refused") has not answered.
- One job at a time: build events while a job runs are queued in `pending`; a waiting job that shares a node with
  a newer one takes the newer one's nodes in (up to MAX_SEEDS; SUMMARY `merged=<seq>`; the waiting job's due frame moves to the
  newer one's, so its nodes get their JOB_DELAY too), so a node is never
  planned by two jobs in a row whose first write may not have landed yet. Re-checks (which may send light
  proposals) wait while a job runs, as they did when a job was one frame.
- Lines: identical in content. One WRITE kind=slip per job (nodes in item order, `success` true when every part
  landed), one VERIFY kind=slip (the parts that landed), SUMMARY / AUDIT / AUDIT_SUMMARY / RECHECK as before.
  APPLY lines of slip nodes now come each with its PHASES / SKIP line right after it (they came after all the
  APPLY lines before); the multiset of lines is the same.
- Also over frames: verifies read one node per step (VERIFY line after the last), re-checks one node per step
  (RECHECK lines after the last), lights-off proposals one node per step from a queue (`G.lightsQ`, filled
  when a write answered; drained before any job step, so no job writes while lights it switched off are still
  to go out). They share the frame budget; a verify takes at least one node per frame.
- No Clock (an api without `api.type.Clock`, e.g. offline tests without the fake): no budget, a job runs in one
  frame as before.
- Errors: a failing step ends the job (ERROR `job<seq>`, no SUMMARY, as before); parts already sent stay sent
  and still log their WRITE when they answered (before, nothing had been sent at that point).

### Verified offline
- A before / after comparison (throwaway, not committed: the pre-change modules rebuilt in the scratchpad, both run
  on the same fake games): lit grid When safe (two jobs), lit grid Always + Remove lights, lit grid Light phases =
  Smart Lanes (two jobs), a mixed 154-node job (probe ring, Channelized X, ramp nodes, merge / diverge lines, a
  one-way grid; two jobs), 160 Channelized X centres: the multiset of SQRL lines and every written config
  (connections, phases, preference) identical, without the budget and with it (fake Clock); SUMMARY, AUDIT,
  AUDIT_SUMMARY, WRITE, RECHECK, LIGHTS lines also in the same order.
- `tests/square_smart_lanes/test_frames.lua` (fake Clock with a modelled cost per api call, `fakegame.lua` opts.clock):
  the 160-node lit grid (When safe and Smart Lanes phases) spread over > 10 frames, no frame over 8 + 2 ms of
  modelled time, each node in exactly one proposal, the same lines and configs as in one frame; a node removed and
  a segment replaced between frames (never written / written with the new segment id); build events during a job
  wait and an overlapping waiting job merges (`merged=3`); rings whole in one proposal under a tight budget; a
  failing step; verifies and re-checks within the budget.
- `test_script.lua` now uses the shared fake game `fakegame.lua`; one test runs one frame more (the lights-off pass
  comes the frame after the write answered).

### Estimated in game
The showcase job (~96 ms of work per 160-node job before; the write part now cheaper, how much in game depends on
the native read costs) becomes ~10-12 frames of at most ~8-10 ms each (budget + one step, ~0.5-1.5 ms in game,
+ the frame's proposal of ~10-15 entries); at 60 fps a job is done in ~0.2 s, far below the ~3 s between the
showcase's builds at 8x. To confirm (TESTING.md U, check 1): no `slow=job_step` / `slow=gui_update` lines, `job_frames`
/ jobs ~10-15, `job_write` (ctx gui_job) per job lower than 69 ms.

### Open
- The callback of a lane write still runs `slipFinish` (WRITE line, verify / re-check scheduling): cheap. The
  engine's own cost of applying 10-15 small proposals instead of one big one is not measurable from Lua.
- ~~A frame's slip part is one proposal: one refused entry loses the frame's ~10-15 entries.~~ Done 2026-10-12:
  a refused part with 2+ entries is retried entry by entry (`retryStep`, `G.retryQ`): each node planned again in
  the frame's world and its entry built from that frame's reads, one proposal per entry, each once (a retry is
  never retried; a refused single-entry part is the bad entry itself and is not retried). The nodes stay held
  (`inflight`) from the refusal until their retry is over, so no next job reads them in between; retries run one
  per step within the frame budget, before the job steps (after lights-off). The job's WRITE line waits for the
  retries and adds `retry=<entries queued> retry_ok=<landed>` (`success` still false: a proposal was refused); one
  `RETRY kind=slip job= node= result=landed|refused|same|skip:<reason>|not_built|error` line per entry; the verify
  and re-checks cover the retried nodes that landed; the tally (SUMMARY, already written) is unchanged.
  `test_frames.lua`: one stale entry in a part of 10 -> 9 written, bad refused again, released for the next job;
  with the budget too.
- ~~A slip part or retry whose callback never comes (and `sendCommand` did not throw) kept `agg.pending` /
  `retryPending` above 0 for good: the job's WRITE line, verify, re-checks and lights-off never ran (the node holds
  expired after 600 frames).~~ Done 2026-10-12: every slip part and retry sent is tracked in `G.waits` and given up
  `INFLIGHT_TIMEOUT` (600) frames after its own send (`expireWaits`, at the top of `guiBody`, so it releases the
  nodes before `heldNode`'s own timeout drops their counts; a retry's hold time restarts at its send). One
  `TIMEOUT kind=slip job= parts= retries= entries=` line per job, `RETRY result=timeout` per retry, then the job's
  WRITE line with `timeout=<entries>` (`success=false`) and its verify / re-checks / lights-off for what landed
  (timed-out nodes are not in `expect`, so neither verified nor re-checked, and are left out of the lights-off).
  A callback after the timeout only logs `LATE kind=slip job= nodes= success=` (no release, count, RETRY or WRITE
  again). `test_frames.lua` (fake game `G.lose`): a lost part among several (job 2 on its node waits, then runs;
  VERIFY of the other nodes) and a lost retry, each with a late callback. Light and ring proposals keep only
  `heldNode`'s timeout (their entries do not wait for an aggregate).
- `pending` has no cap: a scripted build stream faster than one job per ~10-15 frames would queue jobs (the engine
  state keeps 3 per 5 GUI frames). Not seen; a player's builds are far slower.
- `BUDGET_MS` = 8 is a guess for 60 fps with the game's own frame work; lower it if `job_step` max stays high.

## 2026-10-17: idle runtime, Automatic light timing Off, cheaper state polls

Revision 9. A player report after rev 8: "a giant stutter fest", with nothing opted in. Code read (no game log):
under Junctions I choose with nothing enrolled the runtime counts no traffic (`startSnap` has no member), so its
own cost was bookkeeping; the polls that copied the whole game-script state (`state:get()`: GUI every 5 frames,
engine every 10 updates) grew with rev 8's saved lists (`auto`, `rlast`, `kept`, `aout`, `alit`: up to tens of
thousands of numbers in a busy save). Changes (PLAN.md "Idle runtime and Automatic light timing Off"): the runtime
idles at `IDLE_FRAMES` = 300 between reads when nothing is enrolled or the mode is Off; the GUI poll copies the
state only when its change stamp moves (`Auto.readStamp`); the engine sweep reads it every 100 updates. Not measured
in game (TESTING.md "IO"); the reporter's log would tell which part was theirs (the build-time job, `job_step`, is
the other candidate: already spread over frames since 2026-10-12).

### 9 ms frames with All lights (rev 8 session `2026-10-17_0057_sqrl-sqsg`)
All lights, 97 junctions enrolled, Light phases Smart Lanes: two 30 s windows had a background frame of ~9 ms
(`auto max=9.171`, `9.103`), while that session's snapshots stayed at their 1 ms budget (`max_frame_ms=1.01`).
Unbudgeted parts in those windows: the new-light look (`NEW_PLANS_PER_FRAME` = 2 plans a frame, 43 builds queued),
2 timing writes, a backlog of 121 heavy steps after a snapshot. The runtime's parts are now SQPERF sections
(`auto_mirror`, `auto_new`, `auto_list`, `auto_snap`, `auto_write`, `auto_looks`, `auto_flush`) so the next such log
names the part; TESTING.md "AP". Then that part gets a clock budget.

### First All lights run with the sections (rev 9, game log 2026-10-17 22:14-22:22Z)
New desert map, welcome Apply with both boxes (MAPPASS 3642 nodes, 696 junctions, 50 frames; one 24 ms frame in its
first slice, `job_step max=24.3`), All lights 97 junctions, `src=octree` (the BASE_NODE_TRAFFIC_LIGHT list
unreadable). Per 30 s window, bg worst frames: `auto_new` up to 7.3 ms (the new-light look), `auto_looks` up to 3.7 ms
(one refresh or decision: HEAVY_BUDGET_S still runs one), `auto_list` 2.4-2.9 ms, `auto_snap` ~1.3 ms (its 1 ms budget),
the rest under 0.5 ms; 194 decisions, all quiet, no write. Fixed: the listing reads within `ALL_BUDGET_S` = 1 ms a
frame (at least one node). Open: `auto_new` and a single heavy step cost more than a frame's budget by themselves.

### Less work with All lights (rev 9, user 2026-10-17)
- **Finding lights:** the periodic listing every 60 game min (`AllMode.LIST_EVERY_S`, was 5): player builds already bring
  their new lights at once (the new-light look), so the repeat is only the safety net for lights no player build
  brought (a town's own streets). Each listed node is first checked for a standing light (one BASE_NODE_TRAFFIC_LIGHT
  read): `W.lightRead` read the node's whole config before that test, so every unlit node of the octree list (3642
  here) cost a full config conversion.
- **Quiet junctions:** a decision that keeps the timing (quiet, fits, small) moves the junction's refresh past its next
  decision, which refreshes it anyway: one light read per decision (10-60 game min) instead of every `REFRESH_S`
  (5 min). A removed approach segment still refreshes it at the next snapshot; an early wake still decides it sooner.
  Snapshots are unchanged (their cost is the one person-list pass, nearly the same for 1 or 100 junctions).
- **New-light look:** `AllMode.NEW_PLANS_PER_FRAME` 2 -> 1.
- **Not changed:** a single refresh or decision (up to 3.7 ms) is still one step. Its cost is the light read (the
  config conversion) and the world build for the corridors; it now runs far less often. Splitting it would change when
  reads and writes happen relative to each other (risk), so it was left as is.
- Tests: test_tool.lua "all lights (runtime): the listing reads within ALL_BUDGET_S ..." (config reads only at lit
  nodes, no second listing within 30 game min), "keep timing adjusted (runtime): a junction decided quiet is read again
  only with its next decision ...". In game: TESTING.md "AP" (`auto_looks` calls per window should drop sharply).

### Many recordings / Re-times: a sample's candidates gathered within the budget (rev 9, game log 2026-10-17 23:33-23:41Z)
17 Record traffic recordings at once: the tool's `record` section peaked at 12.8 and 12.5 ms in two 30 s windows
(3-5 ms in the others). Not the 5 min checkpoint saves (a window full of them peaked at 4.3 ms, the saved list is
small): the shared sampler fetched every target's routed list (one `getSimPersonsMovingForTransportNetwork` call per
junction and segment, ~70-80 here) in the frame a sample started, the one unbudgeted part of `sl_retimer.lua` (the
reads after it were within `BUDGET_S`). Now a `gather` phase fetches them within the same `BUDGET_S`, the clock read
after each call, at least one call a frame; the whole-person-list fallback stays one call. Timed as SQPERF sections
`record_gather` / `retime_gather` (ctx gui). Offline (test_tool.lua "record traffic (tool): many at once gather ..."):
9 recordings at 0.5 ms per call, worst frame 14.5 ms before, within budget + one call after; the same candidates.
In game: TESTING.md "TM" step 5.
Then (game log 23:47-23:52Z, 6 recordings): `record_gather` max 0.75 ms (the gathering fix holds), but `record` still
peaked at 7.3 ms in the frames of the 5 min checkpoints (23:52:05, 23:52:08): each save bumped the saved `tseq`, so the
tool's next `refreshTraffic` converted the whole saved `trec` list (`asTable`) for its own save. Now `recSave` expects
that bump (the game script's `op=traffic` adds 1 when the same `Rec.apply` changed something), so only a change the
tool did not make is read in full. test_tool.lua "record traffic (tool): a checkpoint save does not read ...".

