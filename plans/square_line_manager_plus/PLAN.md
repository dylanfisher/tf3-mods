# Line Manager Plus: plan

Status: rev 5 (2026-10-11) in the working tree, not committed yet (git HEAD has rev 1). Uploaded through the Mod Hub
at least once (`_metadata/mod.io_fileid.txt` exists); `make modio-status` tells which revision is live. The Line Rate
Matcher merge is done (code, tests, retirement); its in-game checks are still open.

GUI-only Line Manager features, each behind its own mod setting (`severity None`, `cosmetic`, nothing saved).
Current design per feature, the install path, Line Editor Undo coexistence and the test files: [README.md](README.md).
In-game checks: [TESTING.md](TESTING.md). Finished phases, the 2026-10-10 feature research and superseded designs:
[HISTORY.md](HISTORY.md) and [history/](history/).

## Shipped

- Rev 1 (2026-10-10): Send to Line info and before/after estimate, Undo/Redo (from Line Editor Undo), Send to Line
  list info block, line list info on hover (feature 3, reworked from the colour dot tooltip), Line actions (Duplicate /
  Reverse line), Match line rate (merged Line Rate Matcher), Map: Shift-click a line (from Passenger Destinations
  rev 5), Map: line info on hover. Plan phases 1-5 done 2026-10-10, user in game 2026-10-11: "looks good"
  (HISTORY.md, "moved from PLAN.md").
- Rev 2 (2026-10-11): the line list's info box closes when its line is deleted or the Line Manager closes.
- Rev 3: Vehicle list: current cargo (`vehicle_list_cargo`, `vehicle_cargo.lua`).
- Rev 4: Vehicle list: vehicle info on hover (`vehicle_list_hover_info`, `vehicle_hover.lua`); wider name column,
  compact load column; settings tooltips wrapped.
- Rev 5: vehicle list columns fit the vehicles (`vehicle_columns.lua`); 25 stylesheet rules instead of 33.
- Dropped: Balance vehicles (feature 5, decision D8, after the probe: [history/PROBE_RESULTS.md](history/PROBE_RESULTS.md));
  the Buy vehicle button (former feature 6).
- Line Rate Matcher merged 2026-10-11 as `line_rate_matcher` ([MERGE_RM_PLAN.md](MERGE_RM_PLAN.md);
  its design history [RATE_MATCHER.md](RATE_MATCHER.md)). Done: the code and tests moved into LMP,
  `mods/square_line_rate_matcher`, `tests/square_line_rate_matcher`, `plans/square_line_rate_matcher` and its
  `branding/mods.js` entry removed.

## Open work

1. In-game checks not yet run: TESTING.md "Open checks".
2. Docs gap: README.md and TESTING.md have no section for the vehicle list features of revs 3-5 (`vehicle_cargo.lua`,
   `vehicle_hover.lua`, `vehicle_columns.lua`; tests `test_vehicle_*.lua`). Until then their module headers are the
   design reference.
3. Commit the rev 2-5 working tree, then release (CLAUDE.md "Releasing updates").
4. DEV probes (never uploaded): `mods/square_lmp_probe` (Balance, dropped) can be unlinked and deleted;
   `mods/square_line_rate_matcher_probe` stays.
5. Comments in mod code, tests and docs/findings still point at plan docs that moved to `history/` (or at PLAN.md
   sections now in HISTORY.md): `rate_matcher_{engine,model,view,window,commands}.tl` (RATE_MATCHER.md),
   `rate_matcher.lua` (MERGE_RM_PLAN.md), `lmp_capture.lua` / `lmp_rows.lua` (PLAN.md "Shared groundwork"),
   `mods/square_lmp_probe` (PROBE.md, PLAN.md "5."), `mods/square_line_rate_matcher_probe`
   (`plans/square_line_rate_matcher/PROBE.md`, now history/RM_PROBE.md), `docs/findings.md` and
   `docs/findings/lines-vehicles.md` (RM_PROBE.md, PROBE_RESULTS.md). Fix with the next code change.

## Next step

Run TESTING.md's open checks in game (Rate Matcher first: Apply buys and sells, use a test save), then commit and
release rev 5.

## User decisions (2026-10-10)

Feature numbers 1-5 are those of the 2026-10-10 research (its Summary table: HISTORY.md, "moved from PLAN.md").

- In scope: features 1-4 above (feature 5 was in scope until the probe; dropped 2026-10-11, see below). **The Buy vehicle button (former feature 6) is dropped entirely**: no phase, param or
  strings.
- **D1** one "Line actions" popover button in the line toolbar (Duplicate / Reverse, and Match line rate since the Rate
  Matcher merge 2026-10-11).
- **D2** the Send to Line list info panel goes to the **right** of the list.
- **D3** Duplicate gets a **new colour**, like a new line (`line_util.makeLineColor`).
- **D4** Reverse **in place** (undoable with our Undo), **keeping stop 1 first**; no "Reverse as copy".
- **D5** Reverse **re-picks terminals** with `getBestLineAssignment`.
- **D6** Balance: **Option A only** (one-shot re-dispatch, no holding). A DEV probe mod runs first; the param defaults
  Off. **Superseded by D8.**
- **D8 (2026-10-11)** Balance is **dropped entirely**: no Balance button, no `line_balance` param or strings, and no
  read-only spacing indicator either. Reason: history/PROBE_RESULTS.md (a re-send can't respace road vehicles, they ignore the
  stop index; the engine already spaces departures at line frequency).
- Style: the info block's dark colour in `lmp.css.lua` (a mix of AccentVeryDark and BaseDark) is approved. New info
  panels reuse that look where sensible.
- Params: each feature's param is added in the phase that implements it (a param for a feature that doesn't exist yet
  must not show in game).
- `mods/square_line_rate_matcher` was merged into LMP 2026-10-11 (MERGE_RM_PLAN.md). The DEV probe
  `mods/square_line_rate_matcher_probe` stays as it is.

## Decisions

All decided 2026-10-10, see "User decisions" at the top: D1 one popover button; D2 right of the list; D3 new colour;
D4 in place, stop 1 first; D5 re-pick terminals; D6 Option A only after a probe (superseded); D7 moot (Buy button
dropped); D8 Balance dropped after the probe (2026-10-11).

## Rules that apply to every phase

- Wrap, never rewrite: read the previous function in `install()`, call it, and pcall our part with a fallback to the
  vanilla result. One log line per failure kind (`[LineManagerPlus] <feature>: ...`).
- Every custom recipe returns `builtin.BoxLayout` at its root. Never `Component{layout = Recipe{}}`; recipes are items.
  No `mouseTransparent` on ImageView.
- GUI-thread-only calls (`api.gui.*`, `getApplicationTime`) only in render/onStep. Use `api.type.Clock` for timing.
- Pre-5.3 Lua (`make check` lints). `.script.lua` exports via `data()`. Module-level locals stay under 200.
- Commands are sent from click handlers (GUI thread). Callbacks only check success and show feedback.
- Stylesheet rules: ≤ 3 new in total, all scoped under our recipe names. Count them before and after.
- Every displayed string goes through `_()` into `strings.json` for all 13 languages in the same phase. One format
  string per sentence, `{name}` placeholders.
