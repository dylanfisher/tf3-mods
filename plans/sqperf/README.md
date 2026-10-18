# SQPERF: performance instrumentation for square mods

Cheap timing that ships with the mods, so a stall in a player's (or our own) game log can be pinned
on a mod and a section of it. Motivation: a 16 s main-thread stall at load, between `push() default
tool` and `Game is ready`, that the log could not attribute to any mod.

First user: `mods/square_problem_radar`. The pattern is meant to be rolled out to every `square_*`
mod (checklist below).

## Files

| Path | What |
|---|---|
| `tools/sqperf/sqperf.lua` | **Canonical module** (plain Lua, pre-5.3). Edit only this one. |
| `tools/sqperf/sqperf_types.d.tl` | Teal types template (`__MODID__`, `__PREFIX__` filled per mod) |
| `tools/sqperf_sync.py` | `make sqperf-sync [MOD=mods/<id>] [ARGS=--check]`: copies both into a mod |
| `mods/<id>/content/sqperf/<id>.lua` | The mod's copy (byte-for-byte) |
| `mods/<id>/content/sqperf/<id>_types.d.tl` | Its types: `<Prefix>SqPerf`, `<Prefix>SqPerfInst`, `<Prefix>SqPerfOptions` |
| `mods/<id>/tealdef/sqperf/<id>_types.d.tl` | Editor copy + `require "sqperf.<id>_types"` in `tealdef/<id>_def.d.tl` (only if the mod has `tealdef/`) |
| `tools/perf_report.py` | `make perf [LOG=path] [ARGS='--mod X --last --skip 1']`: report from stdout.txt (`--last`: the most recent load that has SQPERF lines; it says which, and names newer loads without any) |
| `tests/square_problem_radar/test_sqperf.lua` | Module unit tests + micro-benchmark |
| `tests/tools/test_perf_report.py`, `tests/tools/data/sqperf_sample.txt`, `sqperf_last.txt` | Report parser tests (`make test-tools`); `sqperf_last.txt` = a load with SQPERF lines followed by loads without any (the `--last` case) |
| `mods/square_sqperf_probe/` | DEV probe that settled the Clock-on-worker-threads question (never upload) |
| `mods/square_sqperf_all/` | DEV master switch: turns every SQPERF mod's debug log on (never upload; "Master switch") |

Why a copy per mod under `content/sqperf/<modId>.lua`: one mod must never `ug_require` another mod's
file (it may not be enabled, and the upload validator rejects unknown modIds), and content paths of all
loaded mods share one filesystem, so the file name carries the modId. Teal global names are shared by
all mods too, hence the per-mod type prefix (`square_problem_radar` -> `SquareProblemRadar`).
`make validate` fails when a copy drifts from `tools/sqperf/` (`tools/validate_mod.py` calls
`sqperf_sync.check_mod`).

## The three levels

All lines go to `<userdata>/crash_dump/stdout.txt` through `log.message` (works in every Lua state,
docs/findings.md); the log's thread column shows which thread ran the code. `vm=` is a short id of
the Lua state (the module table's address).

1. **Init (always on, above 5 ms).** `inst:phase("init", t0)` at the end of a script's top level logs
   how long loading the file took, including the modules it required after the instrument was made.
   With `first = {...}`, one more line once each listed section finished its first call (the
   lazy-init / first-scan cost; its ms is the sum of those first calls):

       [SQPERF] mod=square_problem_radar ctx=gs vm=3f2a phase=init ms=212.4 timer=clock
       [SQPERF] mod=square_problem_radar ctx=gs vm=3f2a phase=first ms=48.0 scan_lines=40.1 scan_stations=7.9 scan_vehicles=0.0 scan_fleet=0.0

   At most two lines per instrument per load. In a GUI state whose module stays cached across loads
   (not known yet) they appear only on the first load.

   **Threshold.** The game script runs in ~16 simulation Lua states per load (`Sim Pool N`,
   `Simulation Thread`, `Load Game Pool N`), each typically < 1 ms to load, which made ~18 init
   lines per mod per load. So each line (`phase=init`, any other `phase`, and `phase=first`) is
   logged only when its ms is **at least `INIT_LOG_MS` (5)**; `opts.initMs` overrides it per
   instrument (`initMs = 0` logs every one). With level 3 on (the debug param), both lines are
   always logged.

   The level 3 gate of a timed instrument is first read at its first window boundary, i.e. its
   first `stop`, so at `phase("init")` it is not known yet (and `phase=first` is decided inside that
   first `stop`, before its window opens). A line below the threshold therefore reads the gate once
   itself (`getModParams` in pcall; an error, e.g. a state without `api.engine`, counts as Off). At
   most two such reads per instrument per load, and none for lines at or above the threshold.
   Untimed instruments read the gate in `new`; their `phase` ms is always 0, so they log it only
   with level 3 on.

2. **Slow-call watchdog (always on).** Every `stop` compares the call with the threshold; a slow call
   logs at once if that section has not logged in the last 60 s, otherwise it is summarised in the
   next line (on a later call of the section or at the next 30 s window boundary of the instrument):

       [SQPERF] mod=square_problem_radar ctx=gui vm=a1b2 slow=window_render max=41.2 over=3/1200

   `max` = slowest call, `over` = slow calls / all calls of that section since its previous slow line.
   A normal session logs nothing here.

3. **Window summary (opt-in).** With the mod's **Debug: performance log** setting On (mod.json param,
   values `{"Off", "On"}`, so On = index 2), or the DEV master switch `square_sqperf_all` enabled,
   one line per instrument per 30 s:

       [SQPERF] mod=square_problem_radar ctx=gs vm=3f2a win_ms=30004.1 timer=clock mem_kb=5120 | lineQuality n=3 ms=2.104 max=0.900 | scan_lines n=3 ms=4.210 max=1.900 | update n=150 ms=9.800 max=2.000 | stateSet c=2 | toasts c=1

   `n` calls, `ms` total, `max` slowest; `name n=…` without ms = counted only (`hit`); `c=` counters;
   `mem_kb` = `collectgarbage("count")` of that Lua state. Off: no output, and counters and window sums
   are not accumulated. The gate is re-read (`getModParams`, in pcall) at every window boundary.

## Master switch (`mods/square_sqperf_all`, DEV ONLY)

Enabling the DEV mod **DEV SQPERF: all mods** (`square_sqperf_all`, never upload; no scripts, no params,
only a presence file as content) makes every SQPERF mod behave as if its own **Debug: performance
log** were On: level 3 summaries, level 1 lines below the threshold, and every debug-gated log line.

Mechanism: the engine's mod params table (`api.engine.config.getModParams()`, runFn's
`allModParams`) has an entry for every active mod, even one without params (the game log's
"mod params" dump prints `square_roundabouts: { }`, plans/square_roundabouts/probe_p7_hx_search.log).
The gate rule lives once in the module:

```lua
sqperf.debugOn(all, modId, key)   -- all[modId][key or "sqperf_log"] == 2  OR  all.square_sqperf_all ~= nil
sqperf.readParam(modId, key)      -- debugOn(getModParams()) in pcall; any error -> false
```

The instrument's `paramKey` gate uses `readParam`, so `perf.on` follows it. Debug-gated code outside
an instrument calls one of the two, never `params.sqperf_log == 2` directly:

| Mod | Site | Via |
|---|---|---|
| state names (template) | `rename.script.lua` per-rename "renamed" line | `sqperf.debugOn(allParams, MOD_ID)` |
| industry production label | `mod.script.lua` runFn gate (`perfDebug`, custom `gate`) | `sqperf.debugOn(allModParams, MOD_ID)` |
| no factory passengers, smart lanes (PROBE), passenger destinations | verbose lines | `sqperf.readParam` |
| bulk bulldozer, line revert, smart lanes (`debugLog`) | chatty diagnostics | `perf.on` (instrument gate) |

Not verified in game yet: that a param-less mod's entry is in `getModParams()` exactly as in the
dumped table (the dump strongly suggests it). Check once: enable it, set no mod's debug param, and
look for `win_ms=` lines after 30 s.

## Thresholds and constants (module fields)

| Constant | Value | Use |
|---|---|---|
| `GUI_SLOW_MS` | 16 | contexts `gui`, `hud`, `step` (one 60 fps frame) |
| `SIM_SLOW_MS` | 50 | everything else (`gs`, `run`, …) |
| `RATE_MS` | 60000 | at most one slow line per section per minute |
| `WINDOW_MS` | 30000 | level 3 window, also when waiting slow lines are flushed |
| `INIT_LOG_MS` | 5 | level 1: `phase` / `phase=first` lines below it only with level 3 on |

`opts.slowMs` overrides the slow-call threshold per instrument, `opts.initMs` the level 1 one.

## API

```lua
local sqperf = ug_require "<modId>::/sqperf/<modId>.lua"            -- Teal: ... as <Prefix>SqPerf
local perf = sqperf.new({
  mod = "<modId>", ctx = "gs",          -- ctx: gs | gui | hud | step | run | ...
  paramKey = "sqperf_log",              -- level 3 gate (timed instruments only)
  first = { "scan_a", "scan_b" },       -- optional phase=first sections
  -- timed = false                      -- never read a clock (counts only; not needed for threads)
  -- enabled = true / gate = fn         -- fixed or custom level 3 gate
  -- slowMs = 30, initMs = 0             -- slow-call / level 1 threshold overrides
  -- now = fn                           -- timer override (tests)
})
local t0 = perf:start()                 -- at the top of the file, before the other ug_requires
...
perf:phase("init", t0)                  -- at the end of the file
perf:phase("rename", t, "due=%d renamed=%d", due, n)  -- optional detail: string, or pattern + args

local t = perf:start(); work(); perf:stop("section", t)    -- explicit (keeps your own pcall as is)
local f = perf:wrap("section", fn)      -- same args, same returns, errors pass through unrecorded
perf:hit("section")                     -- count a call without any clock read (rarely needed)
perf:count("counter", n)                -- level 3 only; no-op while off
```

`phase` detail: a plain string is appended after one space; a `string.format` pattern with arguments
is formatted only when the line is logged (in pcall: a bad pattern logs the raw pattern). Below the
threshold nothing is built: the pattern is a literal and the arguments travel on the Lua stack
(varargs), so a dropped line allocates nothing (tested: 20 000 dropped calls with GC stopped, < 4 KB).
This replaced the state-names templates' `phaseCounts` / `firstPassLine`, which reached into
`perf.now`, `perf.initMs`, `perf:_debugOn`, `perf.prefix` and `sqperf.emit`. Callers keep argument
work cheap (numbers, `#t`); a `tostring(x)` argument does allocate, so use it only in once-per-state
lines.

Rules for the hot path: section names are string literals or strings built once (a table of
`"scan_" .. group` made at load, never `..` per call). `start/stop/hit/count/wrap` allocate nothing
once a section exists (tested: < 4 KB over 20 000 calls with GC stopped, level 3 off and on).
Sections nest freely (an `update` section includes the `scan_*` sections inside it); the report does
not subtract nested time.

`wrap` has no pcall: if the wrapped function raises, the error object reaches the caller unchanged
and that call is not recorded. Where a mod already pcalls an entry point, time around that pcall
(`t = start(); ok, err = pcall(body); stop(name, t)`), so failing calls count too.

## Timer and threads

Timer: `api.type.Clock.new()` / `:getTime()` (microseconds since the clock was made; tealdef
`api/type.d.tl` "record Clock", no "GUI thread only" note), one per Lua state, created in pcall;
fallback `os.clock()` (process CPU time over all threads on macOS, so it overstates).
`getApplicationTime` is never used (GUI-thread only, hard crash elsewhere).

**Settled (2026-10-10, docs/findings.md "Timers and threads in GUI contexts"):** the probe below made
and read a Clock, read a Clock made in render, and ran a timed SQPERF instrument in every GUI
context without a crash or error: recipe render and `react.onStep` (Main Thread), `react.onStepTimer`
and `hudIconScript` functions and their recipe renders (worker threads `Main Pool N`). On the Main
Thread `getTime` costs 0.07 µs (`os.clock` 1.0 µs), `wrap` adds 0.28 µs per call and `hit` 0.03 µs.

### Where to wrap

- **Time everything**, including HUD icon scripts and onStep / onStepTimer callbacks. `timed = false`
  and `hit` stay in the module (harmless) but are no longer needed for thread safety.
- onStepTimer callbacks and HUD icon scripts run on **worker threads**: never put a GUI-only call
  (`api.gui.*`, `getApplicationTime`) into instrumentation or any code there (memory notes
  `hud-recipes-not-gui-thread`, `react-onstep-worker-thread`; use `react.enqueueJoin` for GUI work).
  `react.onStep` ran on the Main Thread in the probe.
- SQPERF itself only calls `api.type.Clock`, `log.message`, `collectgarbage` and
  `api.engine.config.getModParams` (the level 3 gate, in pcall). `getModParams` off the main thread
  is proven in game: Problem Radar's GS reads it from simulation threads, square_industry_production_label
  reads it in `hudIconFn` on every HUD mount, and the probe's `util.stage()` read it in `hudIconFn`
  (`Main Pool N`) before its `ok` line; the minimap reads it from `react.onStep` (Main Thread).
- **Gate reads in onStepTimer.** The gate is re-read in the `stop` that crosses a 30 s window
  boundary, i.e. in whichever section runs then. Problem Radar's GUI instrument (polls `poll_*`) and
  Industry Flows' (`poll`) share one instrument between renders and the onStepTimer polls, so their
  gate read can now land in an onStepTimer callback (worker thread). That exact call site is not
  probed directly (the probe's onStepTimer instrument used `enabled = false`), but it is the same
  `Main Pool N` worker pool as `hudIconFn`, where `getModParams` is proven, and the read is in pcall.
  The minimap's `perfStep` reads it in onStep (Main Thread). If a crash ever names an onStepTimer
  window boundary, give the poll sections their own instrument with `enabled = false` / a cached
  gate.
- Two instruments in one Lua state share its one Clock.

### Probe (`mods/square_sqperf_probe`, DEV ONLY, never upload)

What it does: a `loadConstruction` modifier gives industries without a HUD icon script the probe's
`hudIconFn` (in memory only), and an invisible plugin in the top-left mod ridge runs `react.onStep`
and `react.onStepTimer` callbacks. In each context it logs `try` before touching a Clock and `ok` after
(at most 3 times per context): a new Clock made and read there, the render's Clock read there, and an
SQPERF timed instrument's start/stop. On the GUI thread (render) it also benchmarks
`Clock:getTime()`, `os.clock()` and the SQPERF wrapper with the real Clock.

Steps:

1. Quit to the main menu (never add or remove staging mods with a save loaded).
2. `make link` (adds `square_sqperf_probe` to the staging area; the other links stay).
3. Load a save or start a game with **DEV SQPERF Probe** enabled. Disable **Industry Production Label**
   for this run (its HUD script is already on every industry, so the probe's would be skipped).
   Setting **Probe contexts** = "HUD icon + onStep" (default).
4. Zoom to an industry so its HUD label shows, wait ~10 s.
5. `grep SQPERF-PROBE "<userdata>/crash_dump/stdout.txt"`. Expected, if all is safe:

       [SQPERF-PROBE] runFn modifier registered probe_stage=1
       [SQPERF-PROBE] ctx=render stage=1
       [SQPERF-PROBE] ctx=render ok n=1 new+read us=1,2 mem_kb=...
       [SQPERF-PROBE] ctx=render bench getTime_us=0.0xx os_clock_us=0.xxx sqperf_wrap_overhead_us=0.xxx sqperf_hit_us=0.0xx n=20000
       [SQPERF-PROBE] ctx=onStep ok n=1 new+read us=... shared_us=... sqperf_ms=0.0010 mem_kb=...
       [SQPERF-PROBE] ctx=onStepTimer ok n=1 ...
       [SQPERF-PROBE] ctx=hudIconFn ok n=1 ...
       [SQPERF-PROBE] ctx=hud_render ok n=1 ...

   Note the thread column of each (`Main Thread` vs `Main Pool N`).
6. If the game crashes: the last `try` line names the context. Re-run with Probe contexts = "HUD icon
   only" or "onStep only" to confirm, and record the result in docs/findings.md.
7. When done: quit to the main menu, disable the probe (or remove its staging link).

Result (2026-10-10): all contexts ok, recorded in docs/findings.md. The Problem Radar and Industry
Flows polls were switched from `hit` to timed start/stop, and the minimap's `perfStep` from an
os.clock timer to the default Clock.

## Problem Radar wiring (first adopter)

GS (`content/radar/radar.script.tl`, ctx `gs`, 50 ms): instrument at the top before the requires,
`phase=init` after the script table; `update` and `event` around the existing pcalls in the entry
points; `scan_<group>` around each scan group (state get, scan, merge, set, notifications), `first` =
the four scan groups; the sub-scans `lineQuality`, `econMoney`, `econUse`, `stuck` via `wrap` at their
pcall sites; counters `stateSet`, `toasts`.

GUI (`content/radar/gui/radar_hud.script.tl`, ctx `gui`, 16 ms): `phase=init` for the module,
`hud_render` (ridge plugin render, `first`), `window_render`, `settings_render`, `click_toggle` timed
via `wrap`; the polls `poll_hud`, `poll_window` (with `poll_window_full` nested for a changed state
seq), `poll_settings` timed with start/stop. They run in onStepTimer callbacks (`engine_react_util.tl`
`useStepStateTimer`, worker threads), where Clock is safe. A recipe's time is its own function only;
its child recipes render separately.

mod.json param `sqperf_log` ("Debug: performance log", Off/On, default Off).

## Rollout checklist (per mod)

1. `make sqperf-sync MOD=mods/<id>`.
2. Add the mod.json param (copy Problem Radar's `sqperf_log` entry; Button, values Off/On, default 0).
3. In each script that runs in its own Lua state (game script, GUI script, HUD icon script, mod
   script): require the copy first thing, `sqperf.new{ mod, ctx, paramKey = "sqperf_log", first = … }`,
   `t0 = perf:start()`, and `perf:phase("init", t0)` at the end of the file.
4. Wrap the hot entry points: game-script `update` / `handleEvent` (around the existing pcall),
   scan or rebuild functions, recipe render functions, click handlers, `runFn` modifiers if heavy.
   GUI-thread contexts use ctx `gui`; simulation / game script `gs`.
5. HUD icon scripts and react `onStep` / `onStepTimer` callbacks: timed like everything else (default
   Clock timer). They run on worker threads (onStepTimer, HUD icon), so no GUI-only call there
   ("Where to wrap").
6. Hot path: no per-call string building for section names; counters via `perf:count`.
7. `make check MOD=…`, `make test MOD=…`, `make validate MOD=…` (validate checks the copy).
8. Changelog entry with the revision bump (e.g. "Performance logging: …", see Problem Radar's).
9. In game: set Debug: performance log On, play 5 min, `make perf`; then Off and confirm a normal
   session logs only init / first lines of 5 ms or more (often none).

## Instrumented mods

`square_problem_radar`, `square_industry_flows`, `square_better_minimap`, `square_bulk_bulldozer`,
`square_smart_lanes`, `square_supply_gaps`, `square_passenger_destinations`,
`square_better_bus_overlay`, `square_industry_production_label`, `square_no_factory_passengers`,
`square_full_refund`, `square_line_revert`, `square_photo_mode`, and the 13 generated `square_names_us_*` mods (their copy
is written by `tools/gen_state_mod.py`; regenerate with `make state-mods`, never hand-edit). DEV:
`square_sqperf_probe` (has the copy), `square_sqperf_all` (master switch, no copy needed).

Intentionally left out (no script runs during play, so nothing to time):

| Mod | Why |
|---|---|
| `square_roundabouts` | construction-only (`updateFn` of construction scripts, run on placement) |
| `square_one_way_roads` | data-only (`.street_template.lua` street types and textures) |
| `square_blank_slate` | data-only (map generator `.gen.lua` / heightmap, run once at map creation) |
| `square_bigger_line_dots` | stylesheet-only (`.css.lua`, own Lua state without `api.engine`) |

`make sqperf-sync MOD=mods/<one of these> ARGS=--check` prints "not using sqperf" and exits 0.

## Overhead

Offline (Lua 5.4 via lupa, `test_sqperf.lua` micro-benchmark, os.clock timer): a wrapped call costs
about 0.9 µs more than a plain call, of which ~0.1 µs is SQPERF's bookkeeping and the rest two
`os.clock()` reads (~0.35-0.4 µs each). `hit` costs ~0.03 µs. In game the timer is `Clock:getTime()`:
0.07 µs per read, `wrap` 0.28 µs per call in total (probe render benchmark, docs/findings.md). At Problem Radar's rates (5 updates/s in the GS,
a few renders/s in the GUI) that is microseconds per second.
