# Problem Radar: performance review (2026-10-08)

Scope: the whole mod as of the uncommitted revision 3 work (snooze, `state.seq` window poll), on top of the
two earlier reviews recorded in PLAN.md (Phase 6, 2026-10-05; Phase 7, 2026-10-07). State shape unchanged
(v6, `snoozed` / `seq` optional). Revision stays 3 (pending, not yet uploaded); no new changelog line,
since revision 3's "skips the work when nothing has changed" line already describes the result.

Verdict: the engine scan and the GUI were already in good shape. Two small fixes in the new revision 3 code;
nothing else worth changing.

## Changes

| Where | Before | After | Gain |
|---|---|---|---|
| `content/radar/gui/radar_hud_model.tl` `model.applyPending` (called by every window poll, 2 per s while open) | walked all listed rows (≤ 300) and snoozed rows looking for a pending id, even with nothing pending | returns the view at once when both pending maps are empty | idle poll: ~7 µs → ~0.1 µs (300 rows, plain Lua 5.x timing in the scratchpad). The idle poll now really is "read `seq`, stop", as the revision 3 comment says. |
| `content/radar/radar_checks.tl` `validSnooze` (runs per snooze in `cleanSnoozed`, i.e. in every `upgradeState`, twice per scan slot = every 0.6 s) | created a `whole` closure per entry | module-level `whole` | ~10 % of a tiny cost (200 snoozes: 44 → 40 µs) and no closure garbage per slot. Zero behaviour change. |

Both are behaviour-preserving (existing tests cover them: `test_snooze.lua` "nothing pending: same view",
"cleanSnoozed returns a clean map itself").

## Examined, not changed

- **Window poll (new `seq` gate):** an unchanged `seq` returns the cached `lastRaw`; `deepEquals`
  short-circuits on identity (`table_util.tl:60`), so an idle poll costs two native field reads.
  A changed `seq` (any `state:set`) does the full read + compare, same as the old 1 s poll did every time.
  Fine at 0.5 s.
- **Fallback when `state_native` is missing** (unverified in game, TESTING.md "Field-level state reads"):
  `readFields` then copies the whole `gs.state`, and the window's seq probe makes that 2 copies per 0.5 s
  instead of 1 per 1 s. Base GUI code uses `state_native` in four places (notification_util, industry,
  town_cargo_util, industry_productivity_util), so the fallback should never run; not worth extra code.
- **Ridge HUD poll** (1 s, 3 small fields): could also gate on `seq`, but it reads ~25 numbers; negligible.
- **Engine `merge` snooze parts:** one copy of the snooze map and one `unsnoozed` list per merge
  (O(stored alerts), only allocated when something is snoozed). Negligible next to the scans' API calls.
- **`checks.snooze` / `unsnooze`:** run once per click (event); the double `upgradeState` and `index` are fine.
- **`alertList` per render:** one `GAME_SPEED` read in a pcall, formatted dates cached (`untilTexts`).
  Runs only on a re-render, not per poll.
- **Snooze handler closures:** cached per row id and pruned to the shown rows, like the row handlers.
- Earlier reviews' "considered, not done" items (caching `state:get()`, packing `useAvg`) still need the
  TESTING.md §7 measurement first; nothing in revision 3 changes that.

## Review notes on the in-progress code (not performance)

- `radar_checks.snooze`: `local was = false` / `if not was then` is dead (always true); harmless.

## In-game check list

- Open the radar window with nothing snoozed and leave it open: no FPS change vs closed (idle poll).
- Snooze a row (Zz): it moves to Snoozed at once and stays there after the next polls; wake it with ×.
- TESTING.md "Field-level state reads": confirm `state_native` works (otherwise the fallback note above applies).

## Commands

`make check MOD=mods/square_problem_radar` (12 files, 0 errors), `make test MOD=mods/square_problem_radar`
(192 passed), `make validate MOD=mods/square_problem_radar` (OK).
