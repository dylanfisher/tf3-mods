# Problem Radar (`square_problem_radar`): plan

A problem radar for TF3. It packs every current problem in your transport network into one dense, sortable window. When nothing is wrong, it stays quiet.

Status: revision 7 (2026-10-10) is the latest Changelog entry; the mod is published on mod.io (id 6433425; `make modio-status` tells whether rev 7 is live). Committed since, not released: the window remembers its position (`98d8406`, 2026-10-11), with no `revision` bump or Changelog entry yet. Docs tidied 2026-10-12: finished phase detail is in `HISTORY.md`.

## Shipped

Changelog: `mods/square_problem_radar/_metadata/description.html`.

- **Rev 1 (2026-10-07):** phases 1-6 below (game-flag and inferred alerts, line quality, notifications, Settings tab, review fixes) plus smoothing.
- **Rev 2 (2026-10-07):** phase 7, the Economy tab (`line_unprofitable`, `line_low_use`; state v6).
- **Rev 3 (2026-10-08):** snooze (Zz button, Snoozed tab, `state.snoozed`) and the `state.seq` window poll. Perf review: `history/PERF_REVIEW.md`.
- **Rev 4 (2026-10-10):** SQPERF debug log, the ridge button toggles the window, shared bookkeeping in `state.rt` across the simulation Lua states (`PERF_VMS.md`).
- **Rev 5 (2026-10-10):** all 13 languages; long details and alert names wrap in Settings.
- **Rev 6 (2026-10-10):** fleet window with Upgrade buttons that open the game's Replace Vehicles window (`FLEET_UPGRADE.md`); ages in calendar years.
- **Rev 7 (2026-10-10):** stylesheet rules 79 to 48 (inline styles in `radar_inline.tl`; revert with `git apply -R plans/square_problem_radar/inline_styles.patch`).
- **Inline step 2 (2026-10-14, unreleased, after a 20-mod set crashed at ~209 rules):** 48 to 38 own rules (+ the shared
  4 layer window rules): fixed-width cells as inline `size`, text margins as padding, the row buttons' padding and the
  compact panel (`radar_inline.tl` TEXT_LAYOUT, `rowButton`, `compact`; `tests/square_problem_radar/test_inline.lua`).
  Same look intended; check in game (TESTING.md "Inline step 2"). Revert this step only:
  `git apply -R plans/square_problem_radar/inline_styles_2.patch`.
- **Native fleet window (2026-10-14, rev 10):** the fleet window redesigned with base patterns and no new
  rule: base entity-window cards set inline (card_surface / card_contour nine-patch, Timetables tints) with headings
  above them, both top cards top-aligned (base `vertical-spacer`), a model table with one-line headers (meaning in
  tooltips), the Timetables zebra, per-row Upgrade buttons only with more than one model group, one row of base
  `primary` / `secondary` buttons, the hint in their tooltips. Fleet window rules 15 to 4 (own rules 38 to 27, total
  42 to 31). Check in game (TESTING.md "Native fleet window"). Revert:
  `git apply -R plans/square_problem_radar/fleet_window_native.patch`.
- **Native main window (2026-10-14, rev 10):** the radar window in the fleet window's style, no new rule:
  the alert list in one native card with zebra rows (row = fixed-width Component holding the Button row, not
  `builtin.List`: its inner buttons would bubble), the "↑ Upg" column only on lists with fleet rows, the context (line,
  depot) as a second line under the name (name 280 px, 200 with the Upg column; was 170 + an often empty 125 px
  column), empty tabs show the base `content_card.makeInfoHint` at the top in the same ScrollArea (footer stays at
  the bottom), the footer with a line above it; Settings: top-aligned columns (base `vertical-spacer`), a card per
  section with its heading above, labels 300 px, inline spin box width, range and default on two lines, base
  `secondary` buttons. Rules 27 to 17 own (total 31 to 21). Round 1 passed in game (2026-10-14); round 2 (same day,
  from its screenshots): name and detail cells wrap at 296 px with one shared rule (an inline size doesn't clip: a
  long name ran into the detail), the type joins the context line, "↑ Upg" / "→" at the row's end, settings cells
  in fixed-width boxes (spin boxes in one line), the range on one line in a 190 px box, short labels with the full
  explanation in a wrapped tooltip (`hud_model.wrapTooltip`). Still 21 rules. Check round 2 (TESTING.md §0c).
  Revert both rounds: `git apply -R plans/square_problem_radar/main_window_native.patch`.
- **Unreleased:** window position saved in `AppConfig.mainMenuState` (CSS `gravity` dropped so `initialX/Y` applies).

## Open work

1. **Next step:** release the window-position change: bump `revision` to 8, add a Changelog entry, upload (CLAUDE.md "Releasing updates").
2. The in-game checklist `TESTING.md` was never run end to end: most items are open. Most useful first: §13 (fleet window re-checks), §12 (Lua states), §7 (large save, incl. the `state:get` / `state:set` cost), §10 (API questions), §14 (snooze).
3. Threshold tuning on real saves (the Phase 4 defaults are first guesses).
4. Behaviour changes waiting for the owner's OK: `PERF_VMS.md` "Design options" (real-time cadence at higher game speeds, a sliced worn check).
5. Perf ideas parked until the §7 measurement: caching `state:get`, packing `memory.useAvg` (HISTORY.md, Phase 6 and Phase 7 "Considered, not done").

## Decisions (interview, 2026-10-04)

| Topic | Decision |
|---|---|
| Core goal | Problem radar: alerts first, quiet when healthy. Not a general stats dashboard. |
| Presence | HUD setting chooses between **(a)** an always-on compact HUD panel or **(b)** a small badge (e.g. `● 3`) that expands into the full window. |
| Base-game alerts | **Aggregate + add.** List problems the game already flags *and* our own checks. Send our own notifications only for problems the game doesn't announce itself. |
| Notify level | Configurable per alert type: `off` / `passive` (listed only) / `notify` (toast when it first appears). |
| Stuck rule | Smart defaults: game flags (`Blocked`, `NoPath*`) count immediately; otherwise not moving for X game-minutes while en route and away from a stop. Excludes user-stopped vehicles and ships queueing at a harbour. One adjustable threshold per carrier. |
| Line checks | Broken / no path, capacity mismatch, bunching / gaps. (Unprofitable: **not** wanted.) **2026-10-07: reversed** by the user: lines that consistently lose money over the last year, or run at very low utilisation over about a year, are flagged in a new Economy tab; bigger losses / lower use = higher tier (Phase 7). |
| Extra checks | Overcrowded stations, old / worn vehicles, idle in depot (incl. lines with no vehicles). |
| Layout | Tabs: **All** (sorted by severity) · **Vehicles** · **Lines** · **Stations** · **Fleet** · **Economy** (Phase 7) · **Settings**. Each tab label carries its count. |
| Severity | 3 tiers, colour-coded. The badge/HUD shows the worst tier. |
| Row action | Jump camera + open the game's own entity window. (No snooze, quick fixes or inline breakdown in v1.) |
| Settings | In-window **Settings** tab, saved per savegame. |

## Alert catalogue

| ID | Tab | Tier | Source | Base game already notifies? |
|---|---|---|---|---|
| `veh_blocked` | Vehicles | Critical | `getVehicleProblems()`: `Blocked` | yes (vehicle warning) |
| `veh_nopath` | Vehicles | Critical | `getVehicleProblems()`: `NoPath*` (ship-specific `NoPathShip`), `getNoPathVehicles()`, reason via `getFailedPathReason` | yes |
| `veh_stuck` | Vehicles | Critical | inferred: speed 0 ≥ threshold, `EN_ROUTE`, not `userStopped`, not approaching a station | partly (5 min, all carriers) |
| `train_blocked_by` | Vehicles | Warning | `landVehicleMoveSystem.getBlockedTrains()` (blocked → blocker pair, both clickable) | no |
| `line_broken` | Lines | Critical | `getLineProblems()` / `getProblemLines()`: `NO_PATH`, `ZERO_OR_ONE_STATION`, `INCOMPATIBLE_STATIONS`, `DOUBLE_STATIONS`, `BAD_ALTERNATIVE_TERMINAL`; path-break position from `PathProblemLocation` | yes (line warning) |
| `line_no_vehicles` | Lines | Critical | `#getLineVehicles(line) == 0` with ≥ 2 stops | partly |
| `line_cargo_issue` | Lines | Warning | `getLinesIssues()`: nowhere to load/unload, vehicle useless | yes |
| `line_cargo_not_unloaded` | Lines | Warning | `simEntityAtVehicleSystem.getVehiclesWithRoundTripCount()` (vehicle → cargo count), grouped per owned line via the scan's `getLineVehicles` lists; one row per line, metric `N veh · cargo` | yes (`cargo_rtc_warning` "Cargo Not Unloaded", per vehicle, initially ignored: HUD/LVM icons only) |
| `line_overloaded` | Lines | Warning | waiting at the worst line stop (`getLineStopSimEntitiesCount`) ÷ one vehicle's capacity (`getLineCapacityUsages` ÷ vehicles), sustained | no |
| `line_underused` | Lines | Info | `getLineCapacityUsages()` used/capacity (the base "Utilization") below threshold, sustained | no |
| `line_bunching` | Lines | Warning | headways from `lineStopDepartures` vs the base line "Frequency" interval (`1 / getMaxFrequency`), sustained (our metric) | no |
| `station_overcrowded` | Stations | Warning | `calculateStationGroupCargo(sg, -1).overflow > 0` | yes |
| `station_useless` | Stations | Info | `getLineStationProblems()` | yes |
| `fleet_worn` | Fleet | Info | `getVehicleMaintenanceState(v) ≤ threshold` | yes (≤ 0.2) |
| `fleet_old` | Fleet | Info | age > lifespan (`vehicle_util.getAge` pattern) | no |
| `fleet_idle_depot` | Fleet | Info | `IN_DEPOT` with `daysInDepot ≥ N` | no |
| `line_unprofitable` | Economy | Info → Critical (cost coverage + size of the loss vs all lines' costs) | `finance.calculateBalance({line}, …)`: 12-month balance < 0 and ≥ 3 of 4 quarters < 0 (Phase 7) | no |
| `line_low_use` | Economy | Info → Critical (by average) | our time-weighted yearly average of `getLineCapacityUsages` used/capacity (Phase 7) | no |

"Base game already notifies? = yes" means the default for our toast is `passive`, so it doesn't duplicate the game. Every other row defaults to `notify` for Critical, `passive` otherwise.

## Architecture

```
content/radar/
  radar.gs.lua             registers update/handleEvent
  radar.script.tl          engine side: staggered scans, stuck timers, settings, notifications
  radar_checks.tl          pure check functions (input: plain tables → output: alerts). Unit-tested.
  radar_types.d.tl         Alert, Settings, ScanSnapshot types
  gui/
    radar_hud.res.lua      react-plugin ::MainModButtonAreaExtension
    radar_hud.script.tl    HUD/badge + window recipe (TabWidget + DataTable per tab)
    radar_hud_model.tl     view model: sorting, counts, worst tier, row formatting. Unit-tested.
    radar_hud.css.lua      tier colours, density
  notify/
    radar_notification.res.lua / .script.tl
tests/square_problem_radar/test_checks.lua, test_hud_model.lua
```

- **Engine script (`update`)** owns anything that needs memory across ticks:
  - per-vehicle "first seen stopped" time, for `veh_stuck`;
  - the "alert first seen" set, so a toast fires only once per new alert;
  - line-quality sustain timers and the rotating line cursor (Phase 4);
  - settings.

  It staggers the work across ticks like the base notifications script (slice by `tickCount % 4`) and writes a compact alert list into game-script state.
- **GUI** reads that state via `getEntityForGameScript` + `GAME_SCRIPT` component with `useStepStateTimer(…, 1.0)`. It never scans the world itself. Settings changes go back as `makeScriptingSendEventCmd` events.
- **Row click**: `api.gui.camera.focusEntity(e)` + `fireReactEvent("selectEntity", {entity = e, stack = true})`. For path problems, `focusPosition(pos)` goes to the break location instead.
- Patterns come from an earlier mod in this workspace (ridge plugin, singleton window, notification type, model/test split) and the base game sources cited in each file.
- Files added since the phases: `radar_notify.tl`, `radar_settings.tl` (engine side), `gui/radar_fleet.tl` + `gui/radar_fleet_model.tl` (rev 6 fleet window), `gui/radar_inline.tl` (rev 7 inline styles), `sqperf/` (rev 4 debug log).

## Alert row format (dense)

```
●  STUCK      Ship  "Harbour Ferry 3"   Line 7 Coastal   12m standing   NoSmallShip @ waterway
●  NO PATH    Line  "R2 Northern"       stop 4→5        missing catenary
◐  BUNCHING   Line  "Bus 14"            3 of 5 vehicles within 40 s   target 2:30
○  WORN       Bus   "Bus 14 #2"         18% condition    age 21/20 y
```
Columns: tier · type · entity (clickable) · context (line/stop) · key metric · detail. Sortable; default sort is tier, then age of alert.
(Original sketch. As built since the native main window, 2026-10-14: Zz · dot · tier · kind · name with "type ·
context" on a second line · detail (wraps) · metric · [↑ Upg] [→]; sorted by tier, not user-sortable.)

## Design facts that still constrain code

Short versions; the full reasoning is in `HISTORY.md` under the phase named.

- **Read-only toward the simulation.** The mod sends only `ProblemRadar.*` events and base `Notifications`/`add`; replacing vehicles goes through the game's own Replace window. That keeps `mod.json` at `cosmetic: true`, `severityAdd: None`, `severityRemove: Warning` (see the last item under "Open questions").
- **State v6** (`radar_checks.STATE_VERSION`, lazy `upgradeState` from v1-v5). Optional parts: `pending` (smoothing), `snoozed`, `seq`, `rt`. `state:set` runs only on a change; bookkeeping-only writes do not bump `seq`, so the window does not re-read for them.
- **Several simulation Lua states.** Each tick runs `update` in one of ~14 Lua states, so module-level values are per state. Values whose divergence changes results live in `state.rt` (`PERF_VMS.md` "Fix"; test `test_multistate.lua`).
- **Own stuck timer**, not `MOVE_PATH.dyn.timeStanding` (Phase 3). Timers younger than 30 s game time stay out of `memory` (`PERSIST_TIMER_AFTER_MS`, Phase 6), so stops at lights do not rewrite the save.
- **Failure isolation:** every scan and sub-scan runs in its own `pcall`; previous rows are carried until `FAIL_DROP_AFTER` (10) failures in a row (Phase 6).
- **Toast budget:** at most 3 toasts plus one summary per 2 game-minutes, because the base notification history keeps only 100 entries (Phase 6).
- **GUI cost:** only the selected tab renders, at most 100 rows; polls read single fields through `state_native`; the poll compares undecorated views (decorating the polled view made every poll re-render, Phase 6).
- **Stale ids:** a click selects an entity only while its creation revision is unchanged. `getRevision(e).num[1]` is the creation revision, not a change counter (Phases 4 and 6).
- **Economy:** `calculateBalance` on the line entity works on the sim thread (verified 2026-10-07); severity combines cost coverage with the loss's share of all lines' vehicle costs; each line's money is re-checked at most once a game month; `line_low_use` is a time-weighted yearly average saved once a game month (Phase 7).

## Smoothing (anti-flicker, 2026-10-05)

**Status: implemented; offline tests pass (`test_checks.lua` "smoothing:", `test_settings.lua` smoothSec, `test_notify.lua` "smoothing:"); needs in-game verification (TESTING.md §3 "Smoothing").**

Problem: a full scan cycle takes ~2.4 s, so kinds without their own hysteresis (e.g. `station_overcrowded`, whose `overflow` flag toggles) came and went several times within seconds. Fix: one generic layer for **every** kind, in `radar_checks.merge` (the function that merges a scan group's fresh alerts into the state). Kinds with their own sustain / hysteresis keep it unchanged (line-quality timers + `HOLD_FRACTION`, `fleet_worn` +10 points, `veh_stuck` / `train_blocked_by` minute thresholds); smoothing comes on top.

- **Setting** `smoothSec` (`radar_settings.NUMBERS`, unit `"s"`, game seconds = `GAME_TIME.gameTime` / 1000, default **30**, range 0-600; **0 = off**, the previous behaviour). Settings tab: right column, first group "General" ("Smoothing: problems must persist / linger (game seconds)").
- **Appear:** a newly detected id goes into `state.pending` (not listed, not counted, not notified) with `firstSeen` = first detection. It is listed once it is detected at a scan ≥ `smoothSec` after that. A miss records `missedAt` (first undetected scan); a detection clears it; the entry is dropped only when missed for longer than the window. So a flag that toggles every scan still matures; a single blip never shows.
- **Clear:** a listed id that is not detected stays listed with its last data and `missedAt` set; detected again it just continues (`firstSeen` unchanged); missed for longer than the window it is removed.
- **firstSeen = listed time.** A pending entry that matures is listed with `firstSeen = now`. So the row's age, the sort order and `radar_notify.MIN_AGE_MS` all count from when the row became visible, and a toast never comes before its row (`line_no_vehicles` toasts ~30 s + 2 min after the line first lacks vehicles). radar_notify only sees `state.alerts`, so lingering rows neither clear nor re-toast.
- **Carried rows** (`alert.carried`, transient, stripped by merge, never saved): rows a scan keeps without re-checking them, i.e. the line-quality `keep` (lines not measured this pass), Phase 7's `line_unprofitable` keep (lines whose money was not re-checked), `fleet_old` `keepOld` (vehicles outside this pass's age slice) and `carryOver` after a failed (sub-)scan. They are no news: they neither clear a miss nor start or mature a pending entry. The engine passes listed **and pending** rows into these keeps (`listedAndPending` in `radar.script.tl`), so a pending line-quality or `fleet_old` entry survives a rotation longer than the window and matures when re-measured. Failure isolation still works: carried rows stay as before; a lingering row still clears after the window; the drop after `FAIL_DROP_AFTER` failures is a merge with no alerts, so those rows go after one more window.
- **Priming:** while `primeAll` is set (mod just added to a save, or a pre-v5 state), each group's first scan calls merge with `instant = true`: everything already there is listed at once (and marked notified silently, as before). Kinds switched to **Off** go at once (no linger, pending dropped).
- **Over the stored cap** (300): rows counted but not stored have no data to linger with and look new when re-detected. For a kind with such rows (`kindCounts[k]` > stored rows of k) new ids are listed at once (no count flicker), and its unstored rows still clear without lingering. Best effort, only with > 300 problems.
- **Paused game:** game time stands still, so nothing matures or clears while paused (smoothing holds); with `smoothSec = 0` it behaves as before.
- **State (still v5, lazy):** `state.pending : {ProblemRadarAlert}` (optional; `nil` when empty, so older saves are already valid), capped at `radar_checks.MAX_PENDING_ALERTS` = 200 (oldest first detection kept; a newer one just starts its window later); `alert.missedAt` (optional) on listed and pending rows. `upgradeState` copies `pending` when it is a table and never marks its absence as a change; merge sanitises entries (non-table / non-string id / unknown or off kind dropped). Alerts listed in an older save stay listed (they are in `alerts`, never made pending). Settings saved without `smoothSec` normalise to 30 (saved once, the usual `radar_settings.same` path). `merge` reports `changed` for pending transitions too, so `state:set` runs on transitions only (an unchanged pending entry does not rewrite the state).

## Phases (summary)

All detail moved to `HISTORY.md` ("2026-10-12: moved from PLAN.md").

1. Skeleton + UI proof: done, verified in game 2026-10-05.
2. Game-flag alerts (`veh_blocked`, `veh_nopath`, `line_broken`, `line_no_vehicles`, `line_cargo_issue`, `station_overcrowded`, `station_useless`, `fleet_worn`): shipped in rev 1.
3. Inferred alerts (`veh_stuck`, `train_blocked_by`, `fleet_old`, `fleet_idle_depot`): shipped in rev 1.
4. Line-quality metrics (`line_overloaded`, `line_underused`, `line_bunching`): shipped in rev 1; thresholds untuned.
5. Notifications + Settings tab: shipped in rev 1.
6. Review fixes, perf review, upload prep: shipped in rev 1.
7. Economy tab: shipped in rev 2, partly verified in game 2026-10-07.

## Open questions / needs in-game testing

- Custom hotkey: no mod mechanism for new `IA_*` input actions found. v1 uses the ridge button only.
- Does the ridge slot render the HUD without clipping? (Same unverified risk as the quota mod; see `plans/square_quota_run/GUI_FALLBACK.md`.) If it clips, fallback: badge in ridge, compact panel as a pinned `Window`.
- `MovePath.blocked` / `dyn.timeStanding` are unused by base code; Phase 3 uses its own timer instead (see Phase 3). Still to confirm in game: ship harbour-queue exclusion (`approachingStation`, `shipState.waitingDist` / `clearToLand`), aircraft `waitingDistance`, and whether `getVehiclesWithState` and `getBlockedTrains` behave as documented.
- Phase 4 thresholds (overload 3×, underused 10%, clump 20%, gap 300%, sustain 10 min): first guesses, tune on real saves (TESTING.md Phase 4).
- Phase 4 units: `lineStopDepartures` assumed gameTime ms per stop; `getMaxFrequency` interval assumed game seconds; `getLineStopSimEntitiesCount` for cargo (doc says SimPersons). Sim-thread availability of `getLineCapacityUsages` / `getMaxFrequency` / `simEntityAtTerminalSystem` (base GUI-only so far). `autoDeparture` meaning.
- Scan cost on a big network (target: under 1 ms average per tick), now including Phase 7's `calculateBalance` calls.
- Phase 7: **verified in game 2026-10-07** (screenshots `shots/04-economy.jpg`, `05-all-economy.jpg`, Dec 1992 save): `calculateBalance` works on the sim thread, the line entity's account holds costs (negative 12-month balances listed), and the `maintenanceType` split gives tiered rows (Critical / Warning by coverage; a small loss with poor coverage ranked above a large one, which led to the combined severity rule in Phase 7). Still open: the coin-stack icon at notification size, `line_low_use` after half a year of tracking. TESTING.md §11.
- `mod.json` now uses `severityAdd: None`, `severityRemove: Warning` and `cosmetic: true` (user requirement 2026-10-04: the mod must not affect existing games; it is read-only toward the simulation). Re-check all three before upload: confirm in game that adding/removing gives no warning or error and that achievements stay enabled. If a later phase sends anything other than `ProblemRadar.*` events and notifications, `cosmetic` must go back to `false`. Phase 5 sends `Notifications`/`add` only; research (Phase 5 above) found no reason to change `mod.json`.
