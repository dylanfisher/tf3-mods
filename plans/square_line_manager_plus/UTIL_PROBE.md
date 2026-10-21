Status: run in game 2026-10-18 (live session); results below; feature built (`lmp_util_avg.lua`).

# Average Utilization probe (mods/square_lmp_util_probe)

DEV ONLY, never upload. Read-only (no commands, nothing saved). Answers three questions for the planned Line Manager
Plus feature "average Utilization over the last 12 game months", shown right-aligned in a muted blue inside the
Utilization cell of the Line Manager's bottom statistics row (Capacity | Utilization | Frequency | Rate | Balance).
Every log line starts with `[LMPUTILPROBE]`; the thread is in the log line prefix (`Main Thread` / `Main Pool N`).

Background (game files): the row is the file-local recipe `LineStatisticDetails`
(`base/content/gui/line_vehicle_mgmt/manager_window.tl:3830`, used at `:4319` with `showHeader = false` and in
`LineStatisticDetailsEntry` `:4132` for multi-select). The Utilization value is
`makeValueText(api.util.toStringPercentPrecision(coverageState:old(), 0))` (`:3957-3970`), a `builtin.TextView` of class
`font-scale-body, details-value`, built after the coverage getter is passed to `engine_react_util.useStepStateTimer`
and before the frequency one. No base history of load/capacity exists (findings lines-vehicles "Line Rate is carried
volume"), so the mod must sample.

## What each part tests

### Q1: hooking the Utilization cell (all four on at once; each guarded, failures are logged)

| Tag | Technique | Scope of the patch | Visible sign |
|---|---|---|---|
| **T1** | Find the recipe's function via `debug.getupvalue(react.GetRecipeName)` → react.lua's local `recipeFnToRecipeName`, take its id (`react.GetRecipeId`), and wrap `_react.recipes[id]` (the render function, `react.lua:261`; `_react` is a global, `base/init.lua:41`). During that render only, `builtin.TextView` is swapped so the `%` details-value TextView gets a marker beside it, then restored. Fallback id: `react.getCurrentRecipeId()` seen by T3 (late install). | that recipe's render | `T1` in the blue marker |
| **T2** | With the same function object, `replacementApi.ReplaceRecipe(fn, replacement)` in doReplace (order 270). The replacement is a recipe rendering `react.CallOriginalRecipe(fn, params)` plus a small "T2 replace ok, line N" line under the row. Fallback without debug: `_react.recipeReplace[id]` / `_react.originalRecipeFn[id]` set late from T3's id. Proves function access and whole-row wrapping; it cannot reach inside a cell. | that recipe only | grey/blue "T2 ..." line under the row |
| **T3** | Wrap the module field `engine_react_util.useStepStateTimer`. Inside `LineStatisticDetails` (`react.getCurrentRecipeName()`), the coverage getter (strict: the closure with an upvalue named `statistics_react_util`; loose if names are stripped) arms a one-shot `builtin.TextView` swap that fires on the next details-value TextView and is dropped at the next `useStepStateTimer` call. The line comes from the getter's `params` upvalue. | permanent: one module function; builtin swap only between two calls | `T3` in the blue marker |
| **T4** | Last resort, data point only: replace `api.util.toStringPercentPrecision`, appending ` T4` when called inside `LineStatisticDetails`. A global function wrapper: never for production. | every percent format in the game | ` T4` after the vanilla value |

The marker reads `<tags> avg NN% nK` (mean of the probe's own samples for that line, K samples) or `<tags> now NN%`
before the first sample. No global builtin widget wrapper is installed; T1/T3 swap `builtin.TextView` only for the
moment the row renders.

Log lines: `Q1 env`, `Q1 find LineStatisticDetails fn: FOUND|NOT FOUND (scanned N recipes, M named ...)`,
`Q1 install T1|T2|T3|T4 OK|FAILED ...`, `Q1 FIRST <counter> line N` (first time each hook fires), `Q1 T3 mode`,
`Q1 T3 getter upvalues ...`, `Q1 MARKER rendered by T1+T3 line N value NN%`, and every 10 s while the row is
rendered: `Q1 rates window=10s T1render= T2create= T2render= T3call= T3arm= T3miss= swapMatch= T4=
builtinTextViewSwappedNow= lines=` (calls per 10 s = renders/s x 10; `builtinTextViewSwappedNow` should be false).

### Q2: always-mounted sampler host

Two empty plugins, each registering `react.onStep` and `react.onStepTimer(fn, 1.0)`:

- **ridge**: `react-plugin ::MainModButtonAreaExtension` (top-left mod button ridge, `main_mod_button_area.tl:7`).
- **entry**: `react-plugin ::ModEntryPointExtension` (game UI root floating layer, `game.tl:83-90`).

Log: `Q2 mount host=...`, `Q2 FIRST host=... cb=onStep|onStepTimer` (thread in the prefix), then every 10 s (60 s after
5 min) `Q2 beat host= cb= calls= total= speedup= gameTime= lmSeenAgoS=`. `lmSeenAgoS` = seconds since a Q1 hook last
fired (Line Manager row rendered), so beats with a large value show the host running with the window closed;
`speedup=0` beats show whether it runs while paused (and `calls=0` gaps would show it stops).

### Q3: cost of a utilization pass

The ridge host's `onStepTimer` (worker thread) samples every player line
(`lineSystem.getLinesForPlayer` + `api.engine.util.line.getLineCapacityUsages(line, false)`, sum of used / sum of
capacity) 5 s after load, then every 10 s, 12 passes (~2 min), timed with `api.type.Clock`. Passes 1 and 12 are
repeated once from the ridge `onStep` (Main Thread). After that logging stops; a silent pass every 30 s keeps the
marker's averages. Loops capped (5000 lines, 200 cargo entries).

Log: `Q3 sample line= capsEntries= used= capacity= util=` (once), `Q3 pass=worker#N|main#N lines= ok= errors= totalUs=
listUs= maxUsPerLine= (line N) avgUsPerLine= allUtil= speedup= gameTime= lmSeenAgoS=`, `Q3 done`, `Q3 ERROR ...`.

## Run (one session)

1. `make link` (done). Start the game, enable **DEV LMP Utilization Probe** together with **Line Manager Plus**. Load a
   save with a few lines (ideally 20+, mixed bus and cargo).
2. Unpause at 1x. Within the first 2 minutes:
   - Open the Line Manager, select **one** line, look at the bottom row's Utilization cell: note what you see (blue
     `T1+T3 ...` marker beside the value? ` T4` after the value? a "T2 ..." line under the row? layout broken?).
     A screenshot helps.
   - Select a second line, then shift/ctrl-select two lines (multi-select shows one row per line: check the
     marker there too).
   - Close the Line Manager.
3. Wait about 2 minutes with the window closed (game running).
4. Pause the game for about 30 seconds, then unpause.
5. Reopen the Line Manager on a line: the marker should now read `avg NN% nK`.
6. Quit to the menu (or keep the game open) and read the results:
   `make logs-grep PAT='LMPUTILPROBE' ARGS='--session live'`
   and check for thread errors:
   `make logs-grep PAT='GUI thread|LMPUTILPROBE.*ERROR' ARGS='--session live'`

Expected (not yet verified): T1 depends on the C++ side reading `_react.recipes[id]` at each render (it is a plain
Lua table, so likely); T2 should install (same pattern as the campaign's HudIconMasterGame); T3 should work (module
field looked up at call time, as Line Manager Plus's wrappers); T4 depends on `api.util` being writable. Q2: onStep
on the Main Thread, onStepTimer on Main Pool N (findings gui.md "Timers and threads").

## Results

Verified facts moved to `docs/findings/gui.md` "Decorating a cell inside a file-local base recipe; GUI hosts keep
ticking while paused" (index line in `docs/findings.md`).

- Session: live session 2026-10-18, build 40422, 49 player lines, speed 4 (not yet archived when written; it starts
  after `2026-10-18_1848_session`). `Q1 env debug=false _react=table`.
- Q1 T1: installed late from T3's recipe id (321; the upvalue scan needs `debug`: NOT FOUND). Rendered (`T1render`
  = `swapMatch`). Relies on `_react.recipes` internals: not used.
- Q1 T2: installed late through `_react.recipeReplace[321]`; `T2create` / `T2render` counted. Internals: not used.
- Q1 T3: works, loose mode (no `debug`, so every call armed). `Q1 MARKER rendered by T3 line nil value 100%`: the
  marker landed in the Utilization cell with `T3miss=0`, single and multi-select, but T3 alone has no line (the
  marker's line came from T1). `builtinTextViewSwappedNow=true` at every report: in loose mode the arm of a render's
  last call stays until the next render (harmless pass-through, but the feature arms only for the coverage getter
  and also restores from its host tick).
- Q1 T4: FAILED, `toStringPercentPrecision is table`.
- Q1 render rate: 3-98 renders per 10 s with the window open (`T3call` = 4 x renders), lines 115683, 101721, 85280.
- Q2 ridge and entry: `onStep` (Main Thread) ~280-890 calls / 10 s, `onStepTimer` 10-12 / 10 s; both with the
  Line Manager closed (`lmSeenAgoS` up to 64) and both while paused: speedup 0, gameTime frozen at 49651000, same
  call rates (log lines ~2756-2794).
- Q3 worker pass cost: 49 lines, 470-772 us per pass, 9.5-15.7 us per line, max 106 us for one line.
- Q3 main pass cost: 449 us (pass 1) and 724 us (pass 12).
- Thread errors: none (`Q2 ERROR` / `Q3 ERROR` absent).
- Layout notes: the probe's marker (`T1+T3 avg NN% nK`, body size) overflowed into the Frequency cell; the cell is
  0.22 x 456 = ~100 px (`line_vehicle_mgmt.css.lua:1617-1632`, padding 3 each side). The feature shows a shorter
  text in the annotation size.

## Feature built from this (2026-10-18)

`mods/square_line_manager_plus/content/line_manager_plus/lmp_util_avg.lua` (+ `lmp_util_host.res.lua` /
`lmp_util_host.script.lua`), tests `tests/square_line_manager_plus/test_lmp_util_avg.lua`:
- Hook: T3, armed only for the coverage getter. Without `debug` the getter's line is found by calling each
  `useStepStateTimer` getter of `LineStatisticDetails` once while the wrapped
  `statistics_react_util.calculateCargoColumnDataForLine` records its argument (only the coverage getter calls it).
- Host: one `::ModEntryPointExtension` plugin, `onStepTimer(tick, 1.0)`. A pass starts when the game time moved on by a
  quarter calendar month (`api.util.getMonthDuration(millisPerDay)`, default month when frozen), at most 100 lines
  per tick, 5000 per pass; per-line ring of 52 samples; lines not listed in a pass are dropped.
- Display: `avg 87%` / `avg ~87%` (class `font-scale-annotation, positive`, inline padding 2 top / 4 left) right of
  the base value in a horizontal BoxLayout; tooltip "over the last 12 months" or "since the game was loaded (N of 12
  months so far)".
