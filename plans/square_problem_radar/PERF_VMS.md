# Problem Radar: the game script across simulation Lua states (2026-10-10)

Status: research done and the `state.rt` fix shipped (revision 4, 2026-10-10). Current reference for the multi-state model; "Design options" and the tick-model probe are open, not decided.

Question: SQPERF showed Problem Radar's game script (`content/radar/radar.script.tl`) logging `phase=init` and
`phase=first` in ~14 Lua states per load ("Sim Pool 1..11", "Simulation Thread", "Load Game Pool 2"). Does every
state scan every slot, and can the scans be cut to once per period?

**Verdict: no. The scans already run once per slot globally. Each `update` call goes to one Lua state from a
pool, and every slot is scanned exactly once. The ~14 `first` lines are each state's first ordinary scan,
not extra scans.** No code change. The cost (21.7 ms/s in the desert run) comes from the tick-based cadence
(one group every 3 updates) at the game speed that was played. The options below would change that cadence,
which is a behaviour decision.

Log used: `stdout.txt` of 2026-10-10, load 1 "New Game - desert" (250 lines, 1015 vehicles), log lines 532-1534,
and load 3 "sub-arctic". The aggregates below come from the radar's `win_ms` lines in those ranges.

## How TF3 runs a game script

### One task per game script per tick, run in a pool of Lua states

- Engine (strings in the `TransportFever3` binary, build 604 saves): `ecs::GameScriptSystem::Update(Engine*,
  INodeList*, float)` enqueues a lambda bound to an `int&` index on a `ThreadPool`, returning a
  `JoiningFuture`, so it is a parallel-for over the game-script entities, joined before the tick ends.
  `game_script_util::Update(ScriptRep, GameScriptRep, Engine&, Entity, ResName, float, PreUpdateData&)` runs once
  per entity (= per `.gs.lua`). The Lua states are made by `InitLuaStatesHACK(ScriptRep, ResName, ThreadPool&)`,
  which enqueues one init per pool thread. A `GetLuaStateProvider` also exists. The source paths are
  `src/Game/ecs/GameScriptSystem.cpp` and `src/Game/scripting/GameScriptNotificationHelper.cpp`.
- So each pool thread has its own Lua state that loads every game script. That accounts for the 12-15
  `phase=init` lines per load: 11 `Sim Pool`, `Load Game Pool 2` (load and lifecycle events) and `Simulation
  Thread`, plus states made later. Desert: VM `47f740` was first initialised at 05:46:04, after "Game is ready".
- A state is not tied to one thread. VM `fe4340` logged `init` on Sim Pool 8 and `first` on Sim Pool 7 (load 3).
- `postUpdate(userParams, state, dt, updateResult)` (`base/tealdef/scripts/gamescript.d.tl:55-58`) is the
  engine's split between the parallel `update` and a later apply step. Base scripts that change the world from a
  tick use it (`industries.script.tl:160` removes industries in `postUpdate`; `company.script.tl:337`,
  `fun_elements`, `fireworks`, `mission_sim.script.tl:613`).

### Evidence that `update` is called once per tick, in one state

| Observation (desert, 185 s, 75 windows) | If every state ran every tick | Observed |
|---|---|---|
| `update n` per state per 30 s window | equal in all states (= ticks per window) | 36-50 per state, scattered like a random split of ~555 calls over 14 states (sd ≈ 6) |
| `first` lines (each state's first scan of all 4 groups) | all within one cycle (~1-3 s) | spread over 18 s (05:46:07 → 05:46:25). Each state got ~1/14 of the ~6 slot scans/s, so it needed ~8 scans to cover all 4 groups (coupon collector) |
| `state initialised (handleLegacy)` (old save, first upgrade) | once per state with a stale copy | once (line 780, Load Game Pool 2). The other states saw the upgraded state |
| scans / updates | 1/3 | 1061 / 3192 = 1/3.01 (load 3: 461 / 1347 = 1/2.92) |

The base game relies on the same model. `industries.script.tl:54-56,132` seeds `math.random` with `updateCount`
and sends `makeIndustrySetDespawnTimeCmd` / extension build proposals from `update`. `towns.script.tl:100`,
`company.script.tl:279`, `emissions.script.tl:38` and `notifications.script.tl:48` slice their work by
`updateCount`. None of them guards against a second state running the same tick, which would duplicate their
commands. Problem Radar slices the same way (`radar.script.tl:1543-1546`: `tick % SLOT_SPACING`, slot from
`tick // spacing`), so each slot tick, and therefore each scan, happens once.

What the table cannot rule out is k states running the same tick (k ≈ 3.6 at a 5/s base tick). The binary's
parallel-for-per-entity structure and the base scripts above make that very unlikely. The probe below settles it.

### State, saves and events

- **State is engine-side, shared by all states.** `GameScriptState` lives in the `ecs::component::GameScript`
  component (binary: `ReplicaCompVec<GameScript>`, `GameScriptStateNotificationHelper` with `stateTables`).
  `state:get()` returns a copy into the calling Lua state and `state:set()` writes it back, so a write from any
  state is what the next tick in any other state reads, and what the save stores. Evidence: the single
  `state initialised` line above, and the GUI's `state.seq` poll seeing every scan's alerts.
- **Module-level Lua values are per state.** Nothing syncs them. In Problem Radar these are transient by design
  (`radar.script.tl:103-158`), but each state has its own copy: `lineCursor`/`econCursor`/`econCheckedAt`,
  `liveStopped`/`liveBlocked*`, `failCount`, the toast `budget`, `primeAll`/`primeSeen`, `carrierCache`,
  `fallbackLists`, `oldRevs`, `subscribedThisLoad` (see "Side effects" below).
- **Events go to one state per event, from a subset of the pool.** Desert: 7 of the 14 states got
  `handleEvent` calls (~33/s in total, 151-182 per state per window, which fits a random split). The other 7 got
  none in any window. These are not Problem Radar's 4 GUI events (only a few clicks happened), so the engine
  delivers other events to the handler too. Each costs 0.001 ms (total 0.012 ms/s). Which events those are is
  not known and does not matter for performance.
- **No API names the authoritative state or the thread.** `api.engine` has no thread or VM id and
  `GameScriptState` has only `get`/`set`/subscriptions (`gamescript.d.tl:40-49`). None is needed: there is no
  "authoritative VM", because state is shared and each tick runs once.

### The Auto Assign Terminals note (`plans/square_opt_zhenya_auto_assign_terminals/FORK.md`)

Its "sweeps ~1.7×/s instead of once per 2 s" is not a per-VM effect. Upstream's timer is
`local clock = os and os.clock` (`aat.script.lua:632`), which is process CPU time over all threads on macOS
(plans/sqperf/README.md "Timer"). With 3-4 busy cores it runs 3-4× faster than wall time, so a 2 s interval is
~0.5-0.6 s of real time, i.e. ~1.7 sweeps/s. The shared `s.lastClock` check (`aat.script.lua:1286`) already
stops a second state from sweeping inside the interval. The fix there is a wall clock (`api.type.Clock`, as
the fork's `wallClock` already does for its budget), not a VM gate.

## Where Problem Radar's cost really comes from

Desert, level 3: `update` 17.3 calls/s, 21.7 ms/s; `scan_fleet` avg 5.8 ms (max 28.7), `scan_lines` 4.6,
`scan_vehicles` / `scan_stations` ~2.3; 1.42 scans/s per group = updates / 12 (one slot every 3 updates, 4 groups).

- The cadence counts ticks, so scans per real second follow the tick rate. ~17-18 updates/s in two different
  saves fits 4× speed with a 5/s base tick (`radar.script.tl:72` assumes "0.2 s of real time at any game speed";
  the probe below checks it). At 1× the same work would be ~5.4 ms/s.
- No work is repeated per state at any measurable level. Per-state lazy caches (`lifespanCache`, `carrierCache`)
  refill once per state, a few hundred cheap reads each. The `first` ms (9-13) is the normal scan cost.
- `econCheckedAt` per state means that with many lines every lines pass hits the `ECON_MAX_LINES` = 4 cap in
  every state, the same as with one state at 250 lines (the cap already binds). `econMoney` costs 0.16 ms/s.
  Sharing it would not lower the cost, only make the rotation less redundant.

## Design options (not implemented; each changes behaviour)

1. **Real-time cadence at higher speeds.** Scale `SLOT_SPACING` by `GAME_SPEED.speedup` (e.g. `3 * max(1, speedup)`),
   so a full cycle stays ~2.4 s of real time at 2×/4×. Expected: at 4×, ~21.7 → ~5.5 ms/s. Visible effect: in game
   time the radar refreshes 4× less often at 4×. Smoothing (`smoothSec`) and sustain timers are game-time based,
   so they would land in coarser steps (~10 game s instead of ~2.4). The fleet_old slices and line-quality /
   economy rotations would take 4× more game time. Needs the owner's OK.
2. **Cheaper `scan_fleet`** (the largest share, 5.8 ms per pass). Every fleet pass reads ownership and
   `getVehicleMaintenanceState` for every vehicle (`radar.script.tl:1210-1233`). Slicing the worn check like the
   age check (`AGE_SLICES`) would cut it ~8× but delay `fleet_worn` rows by up to 8 cycles (~19 s at 1×). This
   is a separate review with its own TESTING step.
3. **Shared transient bookkeeping** (cursors, `econCheckedAt`, toast budget, priming, young timers, fail counts)
   in state with lazy init. It saves no CPU and adds `state:set` traffic. It is a correctness topic (next
   section), not a performance one.

## Side effects of per-state module values (correctness, not performance)

Found during this research. Not verified in game; listed so a later phase can decide.

- **Priming:** `requestPrime` sets `primeAll` only in the state that first saw a fresh state. The `notifyStep`
  slot usually runs in another state, where `primeAll` is false. When the mod is added to a save, rows that
  pass smoothing there can be toasted instead of marked silently. The budget (`applyBudget`) still caps
  them, but per state (below).
- **Toast budget** (`budget`, `radar.script.tl:132`): one window per state, so the effective cap is up to
  ~14× the designed one.
- **Young stuck/blocked timers** (`liveStopped`/`liveBlocked*`, `radar.script.tl:147-150`): a timer under 30 s
  (`PERSIST_TIMER_AFTER_MS`) lives only in the state that started it. The next vehicles pass usually runs
  elsewhere and starts the timer again, so `veh_stuck` / `train_blocked_by` can need a little longer than their
  threshold. This is small next to the default minute-scale thresholds.
- **`failCount` / `FAIL_DROP_AFTER`:** counted per state, so a group that keeps failing is dropped only after
  ~14× more failed passes.
- **Line-quality / economy cursors:** each state rotates on its own from the lowest line id after a load, so
  lines are measured in an irregular order. The number measured per pass is unchanged.

## Probe to settle the tick model (next phase, if wanted)

Add two level 3 counters to the `gs` instrument in `doUpdate`, both no-ops while the debug log is off:
`perf:count("ticks", d)`, where `d = updateCount - lastUpdateCount` of this state (module-local; only while
running, 0 < d < 10000), and `perf:count("gameMs", math.floor(dt * 1000))`. Then in one 30 s window
(all states' lines with the same timestamp ± 10 s):

- one call per tick: `Σ update n` over states ≈ `ticks` of any one state (all states report ≈ the same `ticks`);
- k states per tick: `Σ update n` ≈ k × `ticks`;
- `ticks / 30` is the tick rate and `gameMs / (n × 1000)` is `dt`. Compare 1× and 4× to see whether the tick rate
  or `dt` scales with speed.

## Fix: shared bookkeeping in `state.rt` (2026-10-10)

Every module-level value of the game script was audited (`radar.script.tl`; `radar_checks.tl`, `radar_notify.tl`,
`radar_settings.tl` hold only constants and the module tables). Values whose divergence changed results now live in
the optional `state.rt` (`ProblemRadarRuntime`, `radar_checks.cleanRuntime` / `packRuntime` / `sameRuntime`), read
from the `state:get` each slot already does and written with the slot's `state:set` only when they changed:

| Value (before) | Now | Writes |
|---|---|---|
| `primeAll` / `primeKinds` / `primeSeen` | `rt.prime` (set by `ensureInitialised`, `scanGroupBody`, `handleSettings`; also when a settings event is the first write of a pre-v5 state) | while priming only (one cycle) |
| toast `budget` | `rt.budget`, stored only when a toast / summary was sent or `pending` moved | with toasts (already a write) |
| `failCount` | `rt.fails` (zero = absent) | on failures only |
| `lineCursor` | `rt.lineCursor` | lines passes when > 8 lines (cursor moves) |
| `econCursor` | `rt.econCursor`; `rt.econGen` / `rt.econOff` make "Off" drop every Lua state's `econCheckedAt` | lines passes with money checks; Off/On toggles |
| `liveStopped` / `liveBlocked*` / `liveAt` | `rt.young` (only the < 30 s part; `memory` keeps the rest) | vehicles passes where young timers come or go |
| `ineligibleSince` | `rt.ineligible` | when a mark is added or expires |
| `liveUse` samples (saved monthly) | `memory.useAvg` written after every pass that took a sample (cadence 1 ms); `liveUse` stays a float cache, used only while still the newest | lines passes with samples |

Kept per Lua state (cost only): `mapEditorCache`, `warned` (log once per state), `lifespanCache`, `carrierCache`,
`econCheckedAt` (the shared cursor keeps the rotation; a line may be re-checked by several states, still ≤ 4 per
pass), `econNetworkCost/At` (each ≤ a game month old), `liveUse` (cache of `memory.useAvg`), `oldRevs` (a reused id
is re-decided by its age slice within 8 fleet passes, inside the smoothing window), `fallbackLists/Age`,
`subscribedThisLoad` (idempotent re-subscribe per state).

Writes that only touch bookkeeping (`memory`, notify maps, `rt`) no longer bump `state.seq`, so the window's poll
does not re-read for them. SQPERF: new sections `state_get` / `state_set` and counter `stateSetQuiet` (`stateSet`
still counts every write). Trade-off: about one quiet write per lines pass (> 8 lines or line_low_use on) and per
vehicles pass with standing vehicles, i.e. up to 2 of every 4 slots on a busy network, where a slot used to write
mostly on alert changes. Old saves: `rt` is optional (nil = all defaults), garbage is sanitised; an older build
drops it (upgradeState rebuilds the state from known fields).

Tests: `tests/square_problem_radar/test_multistate.lua` (14 module instances, one shared fake state, random state
per tick). Against the pre-fix script 8 of its 9 behaviour tests fail; the "add the mod" priming case passes
there too, because with default settings the only notify kind already present (line_no_vehicles) waits 2 minutes
(MIN_AGE), long enough for the one priming state to mark its rows. The v4-upgrade and switch-to-Notify cases show it.
