# Smart Lanes: history

Superseded designs and finished phases, moved verbatim (newest first). Current state: PLAN.md, RETIME_PLAN.md.

## 2026-10-15: "Keep timing adjusted" step B's shared sampler (superseded by RETIME_PLAN.md "Step B v4: queue snapshots")

User decision 2026-10-15: automatic timing is low importance; no sampling every few seconds, no continuous windows.
The shared 180 s measuring windows below were replaced by occasional queue snapshots. Moved from RETIME_PLAN.md
"Step B" verbatim; the in-game checks KA / KA v3 (never run in that form beyond Light plans A/B run 2) moved from
TESTING.md verbatim (replaced by TESTING.md "KA v4").

### Scheduler and shared sampler (`sl_autoretime.lua`, stepped by `sl_bg.script.lua`)
- Every frame, cheapest first: the mirror (aseq every 30 frames, the list only when it changed); the zones (zseq every
  120 frames); one `sl_auto` zone look or one slice of "enroll all"; then the window.
- **A window** takes the due junctions (earliest first), at most `capNext` (<= `WINDOW_MAX` = 8), **one per frame**
  (forming: build check, resolve / re-attach / prune, light read, adopt check), then measures them together for 180 game
  s (samples every 3 s; 5 s since v3, below) and plans them one per frame.
- **One sweep per sample** serves every member: candidates = the routed lists of every member node and its segments
  (deduplicated) plus the drivers ahead of any member at the last sample, capped at 12000; each driver is placed once
  (far-skip as step A v2, by the distance to the nearest member), its path read once (`R.pathAtMulti`, 8 elements each
  way) and attributed to **every member on it**: ahead -> tracked for that junction (queued when within 150 m of it and
  standing), behind after being ahead -> one pass of that junction's movement. So a driver through two enrolled
  junctions counts at both (test "one shared sweep serves both").
- **Budget**: `BUDGET_S` = 1.5 ms of clock per frame for the whole sampler, checked every 8 candidates; a sample that
  does not fit in its 3 s spacing delays the next one, and the next window takes fewer members (`capNext` = members x
  3 s / mean sample time; +1 per window that kept up). While the tool's own Re-time measures, the sampler pauses (one
  sampler at a time; the window moves on by the gap, `gaps=`).
- **Plan** (per member, `R.plan` with `maxCycleStep` = 20): the result as Re-time's, but the cycle moves at most 20 s
  per write (below). Hysteresis as step A (max(3 s, 15 %)).
- **Guards before a write** (else `op=skip reason=`, retried after 2 min, interval kept): the phases and lanes read at
  the end equal those at the window's start (`changed:phases|changed:lanes`); no proposal of the tool pending and not
  the manual Re-time's junction (`busy`, `C.autoBusy`); the player not building within 300 m (`building`); no write of
  ours there within the current interval (`interval`). The write is `W.retimeLights(..., "auto")` (durations only,
  the phases' signature re-checked) and logs `LIGHTS src=auto ... to=retime action=auto [zid=]`.
- **Intervals** (`Auto.nextEvery`): a write -> 5 game min; fits or too little traffic -> 10, 20, 40, 60 min (cap);
  refused -> 10 min; skipped -> 2 min (`Auto.RETRY_S`), interval unchanged. A new entry is due at once.
- **The player builds nearby**: the background plugin hears the base construction menu's `constructionMenuActive`
  event (construction.tl:5060-5080, fired with `react.fireEvent`, heard by any recipe) and, while it is open with another
  tool than Smart Lanes' own (the tool's step counter did not move), reads the cursor's terrain position every frame
  (`R.setBuild`). A junction within 300 m of it, or of where it was in the last 30 game s, is skipped. Unverified in game:
  that the event reaches the plugin (TESTING.md KA 7). The bulldozer is not the construction menu: not covered.
- **Adopt**: the runtime keeps per junction the phases' structure (count, locked lanes, skips) and durations last
  seen, and the durations it wrote. A check that finds another structure, or durations that are neither, logs `op=adopt
  reason=phases|durations old= new=` and takes them as the base: only lengths are written from then on, never the
  structure (the movement-to-phase map is rebuilt every check). Our own write is no hand edit (re-read in its callback).
- **"Re-time" at an enrolled junction**: `op=now`, the junction is due at once (`areq`; the runtime of the same Lua
  state also directly).
- Lua state: the runtime lives in the plugin's state (`g.auto`); the tool reaches it when they share a state (unverified,
  TESTING.md RT 9). If not: the tool's status falls back to the saved bookkeeping, `C.autoBusy` / the manual pause are
  not seen (two samplers may run at once, 1.5 ms each), everything else goes through the saved state. If the plugin did
  not run at all, `T.new(...).step` can be called from the game script's `guiUpdate` instead (it needs only `api`).

### Per-frame cost (estimate from the user's step A run, before run 2; run 2 measured it: "Sampler cost v3" below)
- The user's run: 104429 path reads + ~5 calls per candidate, `busy_ms=7229` over 60 samples, ~8.9k engine calls per
  sample: ~13.5 us per call. After step A v2 ~3.4-3.9k calls per sample for that junction (~1425 candidates, ~315
  near): ~50 ms of work per sample per such busy junction.
- Idle (nothing due): one state read every 30 frames, a scan of <= 256 records every 30 frames: well under 0.05 ms
  per frame. Forming / planning: one junction per frame, a light read, a plan, maybe a write: ~0.2-1 ms in that frame.
- Measuring: at most 1.5 ms per frame, whatever the number of junctions. A window of k such junctions needs ~k x 50 ms
  per sample = ~33 k frames at 1.5 ms; at 60 fps the 3 s spacing holds ~180 frames, so about 5 busy junctions per window
  keep the spacing (`capNext` finds it; quieter junctions cost less). Lighter junctions share drivers (one read for
  all).
- **18 enrolled** (a Light plans A/B run's twins): about 4 windows of ~5, 4 x ~3.3 min = ~13 min for a full round, so
  every junction can be checked every 5 min after a write only while few are due; the sampler runs ~1.5 ms per frame
  during windows (~9 % of a 60 fps frame) and is idle between them once the intervals back off.
- **100 enrolled** (a whole town): ~20 windows, ~65 min per round when all are due: the sampler runs continuously at
  1.5 ms per frame, and the effective interval is ~1 h (the cap) whatever the back-off says. A later option: a lower
  budget or fewer samples per window for long rounds.

### Settle delay (run 2: the first window measured during the build)
Run 2 enrolled the four sl_auto twins at 05:13:00, the window started at 05:13:01 while the showcase was still linking
roads (until 05:14:12), and all four ended `changed:lanes`. Now a new entry (no check yet), and one whose last window was
thrown away for `changed:lanes|phases`, is measured only once its lanes and phases (the light's phases signature and the
connections text) stood unchanged `SETTLE_S` = 60 game s, looked at every 15 game s (one light read): `AUTORETIME
op=settle reason=new|changed_again wait_s=60` when the clock (re)starts. After a `changed:` skip the clock starts at the
window's end read, so the retry 2 min later goes ahead at once when nothing moved since.

### Sampler cost v3 (run 2's 17 windows; coordinator's measurements, 2026-10-15)
Measured: 4-junction windows 7.6-8.7 s busy over ~4400 frames (~1.9 ms per frame, over the 1.5 ms budget: the clock was
checked every 8 candidates, and 8 near drivers are ~200 engine calls), 1-junction windows 1.2-4.3 s; `cand_mean`
3.5-3.9k, `near_mean` ~800, `calls_per_sample` ~18k, of which `reads` (path elements) ~12.8k: ~16 per near driver.
And one `SQPERF ctx=bg slow=auto max=249.0` frame.
- **The 249 ms frame**: at 05:14:12 the Stress Test replaced segments 306823 (g3v) and 297327 (g4v) while the first window
  measured them; the next sample asked their routed lists and the engine asserted twice (`Engine.h:323
  GetComponentDataIndex`, Main Thread, the two entity ids), logging a trace each time, the only two such lines in the
  session. Now every sample first reads each member's node / segment (`BASE_NODE` / `BASE_EDGE`, pcall'd); a missing one
  marks the member gone (`op=member_gone entity=`), it is not asked again and its window ends `changed:lanes`.
- **Budget overshoot**: the clock is checked after every 8 candidates or 6 engine calls, whichever first (`CHECK_CALLS`):
  a frame ends at most one driver (~25 calls) past the budget. `window_end max_frame_ms=` logs the longest. (test:
  0.2 ms per call, 1.5 ms budget: 1.80 ms vs 4.20 ms before.)
- **Path reads of tracked drivers** (`R.pathAtTrack`): a driver ahead at the last sample keeps the indices its junctions
  were found at; while its path has the same length and each still holds its junction (one read each) only the elements
  that came within 8 ahead are read (usually 1-2), and the at-vehicle checks are skipped (it drove its car 5 s ago).
  A re-route (other length or junction moved) falls back to the full read. `window_end inc=` counts the incremental
  reads. Fixture (21-element paths, 4 new cars per 3 s each ahead for 3 samples, 6 standing): reads 25.8k -> 9.7k,
  calls per sample 547 -> 273, the same 228 passes.
- **Samples every 5 s** (`EVERY_S`, was 3): a pass needs the driver seen ahead once within 200 m, which 5 s still
  guarantees below 40 m/s (the far-skip's bound already); 36 samples per window (minSamples 20). Fixture: the same 228
  passes at 5 s (sampled every 6 s there) as at 3 s, calls per window 16.1k -> 8.4k. The manual Re-time keeps 3 s.
- Not built: candidates from an octree / position query around each junction instead of the routed lists (no verified
  API for persons by position; the routed lists are already deduplicated across segments and junctions, and the far
  ones cost at most one position read, `far_skipped=`).

Estimated sampler cost per frame (60 fps; before: run 2's measured work per sample, ~8.5 us per engine call; after:
~0.48 x the calls per sample (path reads x 0.37, tracked drivers 3 calls instead of 5) and 5 s spacing; busy 1-junction
= g5v's ~73 ms per sample before, 4 junctions ~150 ms, 8 = 2 x 4):

| junctions | before 1x | before 4x | after 1x | after 4x |
|---|---|---|---|---|
| 1 (busy) | 0.41 ms mean (samples 3 s / 180 frames) | 1.5-1.9 ms (budget-bound, ~1.6 needed) | 0.12 ms | 0.47 ms |
| 4 | 0.83 ms mean, frames up to ~1.9 | 1.9 ms every frame, a sample ~5 game s (late) | 0.24 ms | 0.96 ms |
| 8 | 1.9 ms every frame (budget-bound) | 1.9 ms, a sample ~11 game s: ~17 samples, capNext ~2 | 0.48 ms | 1.5 ms (budget-bound), a sample ~6.4 game s, capNext ~6 |

The longest frame after: ~1.5 ms + one driver (~0.2 ms). To be measured in game: `busy_ms`, `max_frame_ms`,
`calls_per_sample`, `inc`, SQPERF `auto`.

### KA. Keep timing adjusted: automatic re-timing per junction (rev 8 step B; PLAN.md "Keep timing adjusted", RETIME_PLAN.md "Step B"; 2026-10-14; the runtime ran in game in the Light plans A/B run 2 (2026-10-15, RESULTS.md), the steps below not yet)
Setup: as RT (a town with steady car traffic, a lit crossroads with one clearly busier road). Game speed 1x-4x. Read
back with `make logs-grep PAT='AUTORETIME|action=auto' ARGS='--session live'` (and SQPERF with "Debug: performance
log" On: section `auto`, ctx `bg`). Steps 1-4 at one junction, 5-8 the runtime's conditions, 9 the whole map.
1. **The box.** Select the lit crossroads: a third row under Lights only | Re-time with the checkbox "Keep timing
   adjusted" (unchecked; fits in de / ru on its own row, a separator line above it as between the other rows). An unlit
   junction, a roundabout, a street: no third row. Tick it: `AUTORETIME op=enroll node=<n> pos=<x,y> src=tool total=1`,
   result "Timing kept adjusted at this junction", the status line "Timing kept adjusted: waiting for its first check"
   (then "...: measuring traffic (12 of 180 s)" within a second or two).
2. **Per junction, and it unchecks.** Select another lit junction: the box unchecked there (**the first time in a
   session the box may show unchecked at an enrolled junction until you click it once**: a click then sets what you
   clicked, so click it again if needed; afterwards it follows every selection). Back at the first one: checked. Untick:
   `op=unenroll ... src=tool total=0`, "Timing no longer adjusted at this junction"; select elsewhere and back:
   unchecked. Tick again for the next steps. **Report** whether the box ever showed the wrong state after the first
   click, and whether it could always be unticked.
3. **The first window, tool closed.** Close the tool right after ticking. Wait ~4 game min. Expected:
   (since v3 first `op=settle reason=new wait_s=60`, the window ~60 game s later)
   `op=window_start n=1 nodes=<n> window_s=180 every_s=5 enrolled=1`, then `op=window_end ... samples=~36
   src=routed ... busy_ms= frames= sample_s=`, `op=plan ... result=write|fits|small_sample ... cycle=<old>><new>
   cycle_wanted= stepped=0|1 greens= ... every=0`, for a write `op=write ... sent=1 ... every=300`, `op=write ... at=cb
   success=true` and `LIGHTS src=auto node=<n> to=retime ... action=auto`. **Answers:** the background plugin runs the
   runtime with the tool closed (or never opened: try once right after loading a save with an enrolled junction, the tool
   not opened: `window_start` within ~2 game min); `sample_s` well under 5 (the samples keep their spacing); the
   cycle moves by at most 20 s (`stepped=1` when Webster wants more).
4. **Back-off and the status.** Leave it running ~30 game min. Expected: writes 5 game min apart while the plan still
   changes (`every=300`), then `result=fits` with `every=` 300 -> 600, the next check 10 min later, then 20 min.
   Open the tool and select the junction: "Timing kept adjusted: last check 3 min ago, next in 7 min" and the last
   result's two lines ("Measured ...", "Cycle ..." / "Already fits ..."). Reload the save: the next check comes when
   the saved interval says (no immediate re-measure of everything), the box state survives.
5. **Re-time there.** Press Re-time at the enrolled junction: result "Re-time: checking this junction in the next
   measurement", `AUTORETIME op=now`, a `window_start` with it within ~1 s (no RETIME op=start: one sampler).
6. **Hand edit adopted.** Change a green's seconds in the Crossing window (or press Lights only). At the next check
   (press Re-time to make it now): `op=adopt reason=durations|phases old= new=`; the following write keeps your phases'
   lanes and skips (Crossing window), only lengths differ.
7. **Building nearby.** Open the road builder with the cursor next to the junction (within 300 m) while a check is
   due (press Re-time there, then switch to the road builder): `op=skip reason=building retry_s=120`; with the cursor far
   away (or the menu closed): no skip. **Answers:** the base `constructionMenuActive` event reaches the plugin (no skip
   ever: it doesn't; note it in docs/findings/gui.md).
8. **Re-attach / prune.** Rebuild the junction (bulldoze one arm and build it again, or upgrade a road through it):
   at its next check `op=reattach old=<id> new=<id>` when the node id changed (else nothing), or `op=prune
   reason=no_light|gone` when no lit node stands there any more (and `op=unenroll ... src=prune`).
9. **Whole map: every lit junction** (the Stress Test's switch; until it has a button, the console):
   `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", { op = "all", run = "ka9" }))`
   Expected: `AUTORETIME op=enroll_all phase=request run=ka9 src=stress`, within a few frames `op=enroll_all phase=done
   run=ka9 src=component nodes=<lit> lit= already= sent= capped=` (`src=octree` means the light component could not be
   listed: note it in docs/findings/roads.md) and one `op=enroll ... src=all` per junction. Then windows of several
   junctions (`window_start n=` up to 8, fewer when samples run long: `sample_s` > 5 lowers the next `n`). Let it run
   >= 60 game min at 1x-2x. **Answers:** frame time (SQPERF `auto` mean / max; `window_end busy_ms` / `frames`, expected
   <= ~1.5 ms per measuring frame), the stutter (none expected), how long a full round takes (time between two checks of
   the same junction), and traffic: the twins' or the town's throughput before / after (`make flow ARGS='--last'`).
   Stop it: `... { op = "clear", run = "ka9" }` -> `op=unenroll all=1 n=<count> run=ka9`.
10. **Save safety.** Save with enrolled junctions, remove the mod (or start without it), load: no error, the junctions
   keep their last written phases. Re-add the mod and load that save: note whether the list is back (the box checked,
   checks resume) or gone (the game drops a removed mod's game-script state: then it starts empty, also fine).
11. Report: the AUTORETIME lines of one junction over ~30 min, the SQPERF `auto` line, and for step 9 the
   `enroll_all` lines and a `window_end` line.

### KA v3. Cycle rule v3, damping, settle delay, cheaper sampler (2026-10-15, offline only; RETIME_PLAN.md "Cycle rule v3 and damping", "Settle delay", "Sampler cost v3")
Built after Light plans A/B run 2 (RESULTS.md). The next Stress Test "Build light plans A/B" (same setup: 2x2 X and 3x3 X
x 3 sets, balanced and unbalanced, twins game / sl_phases / sl_auto, >= 60 game min at 4x), then `make flow
LOG=<session>` and `make logs-grep PAT='AUTORETIME' ARGS='--session <name>'`. What it should show:
1. **No first window during the build**: one `op=settle reason=new wait_s=60` per sl_auto junction at enrollment, maybe
   `reason=changed_again` while the showcase still links roads, and no `op=skip reason=changed:lanes` on the first
   windows (run 2: all four). `window_start` after the build's last `[SQST] ... linked` line.
2. **Balanced saturated twins** (2x2 and 3x3 balanced): the first plan `cycle_reason=unconfirmed` (the cycle held, the
   next check 5 min later), then `cycle_reason=balanced` with the cycle at most 75 s (`cycle_wanted=120`); `share=`
   0.50-0.62, `balanced=1`. Against the axis plan: throughput as run 2 (+0-2 %) **with queues no longer longer** (run 2:
   2x2 183 vs 144, 3x3 148 vs 116); ideally shorter than at 120 s and close to the axis plan's. If queues still grow:
   lower `balancedCycle` toward the axis plan's 52-62 s.
3. **Unbalanced twins**: the 3x3 unbalanced gain kept (run 2: 46.5 vs 23.4 km/h, queue 10 vs 31); the 2x2 unbalanced
   (queues every window) still walks to 120 s, one window later than run 2. **No flip-flop**: per junction the cycle
   changes direction at most once over the run (run 2: g2v four times, g6v twice); `load_s=` present from the second
   plan on.
4. **Cost**: `window_end` `max_frame_ms` <= ~1.7 (run 2: frames ~1.9 ms mean in 4-junction windows), `busy_ms` per
   4-junction window ~2.5-3.5 s (run 2: 7.6-8.7 s), `calls_per_sample` ~8-9k for 4 junctions (run 2: ~18k), `inc=` most
   of the near reads, `samples=~36`, `sample_s` < 5; no `SQPERF ctx=bg slow=auto` line, and `op=member_gone` (not an
   engine assertion) if a road is rebuilt during a window. The passes per window stay at run 2's level for the same
   traffic (`total=` 300-490 per junction).
5. Report: `make flow` table rows (auto vs axis, settled), the plan lines of the balanced twins and of the twin that
   flip-flopped in run 2, the `window_end` lines.
