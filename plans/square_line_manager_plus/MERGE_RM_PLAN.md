Status: done 2026-10-11 (implementation and retirement; the in-game checks are open in ../TESTING.md "Line Rate Matcher").

# Merge plan: Line Rate Matcher into Line Manager Plus (research 2026-10-11)

`mods/square_line_rate_matcher` (RM, rev 1, never published) becomes feature `line_rate_matcher` of
`mods/square_line_manager_plus` (LMP, rev 1, not yet published). Requirements: the session's REQUIREMENTS.md. Three
phases, one subagent each: **implementation** (sections 1-9), **cleanup** (section 10), then the in-game checklist.
Paths below: `LMP/` = `mods/square_line_manager_plus/`, `RM/` = `mods/square_line_rate_matcher/`,
`C/` = `LMP/content/line_manager_plus/`.

## Key facts found

- RM = 1 Lua mount script + 5 Teal modules + 1 types `.d.tl` (+ a byte-identical `tealdef/` copy) + 1 css (4 rules) +
  strings.json (91 keys/lang). It has **no SQPERF** (no `content/sqperf/`, no perf calls), so nothing to dedupe there,
  and no section names to keep: new sections are added (section 4).
- RM's own wrappers duplicate LMP's groundwork 1:1: `lineActionDescriptor` = `lmp_capture`, `iconToggleButton` at the
  A+ icon = `lmp_rows`, `selectedCount` = `capture.selectedLineCount`, `shownLine` = `capture.editedLine` (+ the
  `>= 0` check).
- The tracebacks: RM's `context()` runs `params.lineState:old()` (rate_matcher.script.lua:50) on the captured
  commonParams every time the toolbar button steps **and** every 2 s while the RM window is open (`liveRefresh`,
  `fullLoad`, `syncList`, `apply` all call `context()`). The RM window is a default-window-api window that outlives the
  Line Manager, so with the manager closed each re-read hits the expired state.
- `lmp_stats` exposes only formatted text lines (`stats.lines(entity)` → strings) with a 1 s cache; RM needs the raw
  Rate number, fresh, every 2 s and 1 s / 3 s after Apply. **No overlap usable**: RM keeps its own engine reads
  (section 4).
- String collision: only `"Rate"`, identical in all 13 languages. LMP `en` = {}, RM `en` = {}.
- CSS: LMP has 8 rules, RM 4 (3 `a()` calls, one with 2 comma parts; every part counts, findings "Load crash above
  ~200"). The header comment of `rate_matcher.css.lua` saying "FOUR rules" is right.
- Teal defs: `tools/tl_check.py` and `tests/run_tests.py` load every `content/**/*.d.tl` of the mod as a definition
  module (dotted path name, `tools/tealrt.py def_modules`) and put `content/` and `tealdef/` on the module path. The
  `.tl` modules don't `require` the types; the globals come from the def load. `tealdef/` is an editor-only copy
  (`tl_check.stale_tealdef` flags drift); `make teal` (setup_teal.py) uses `tealdef/<modId>_def.d.tl` when it exists.
  LMP has **no** `tealdef/` today; `sqperf_sync.py` adds `tealdef/sqperf/<modId>_types.d.tl` and a require line to the
  `_def` file **only when `tealdef/` exists** (so creating it requires a `make sqperf-sync` run, section 1).
- Test harness: `ug_require "<modId>::/dir/x.tl"` transpiles on demand from the tested mod's `content/` (the test
  folder name = modId); `.tl` modules are type-checked with that mod's `.d.tl` defs. So moved tests only need the
  `square_line_rate_matcher::/rate_matcher/` prefix replaced by `square_line_manager_plus::/line_manager_plus/`.

## 1. Target file layout

Move (git mv the Teal files so history follows; contents edited as listed):

| From `RM/` | To `LMP/` | Edits |
|---|---|---|
| `content/rate_matcher/rate_matcher_model.tl` | `content/line_manager_plus/rate_matcher_model.tl` | header plan path → `plans/square_line_manager_plus/RATE_MATCHER.md` |
| `content/rate_matcher/rate_matcher_engine.tl` | `C/rate_matcher_engine.tl` | require path (line 48); log `"[RateMatcher] model "` (line 617) → `"[LineManagerPlus] rate matcher: model "`; header paths |
| `content/rate_matcher/rate_matcher_view.tl` | `C/rate_matcher_view.tl` | require path (line 25); header path |
| `content/rate_matcher/rate_matcher_commands.tl` | `C/rate_matcher_commands.tl` | log prefix lines 46, 238, 447 → `[LineManagerPlus] rate matcher: `; header path |
| `content/rate_matcher/rate_matcher_window.tl` | `C/rate_matcher_window.tl` | require paths (48-51); `PREFIX` (55) → `"[LineManagerPlus] rate matcher: "`; drop the toolbar button (section 3); perf (section 4); header rewritten (mounted from the Line actions menu, css now in `lmp.css.lua`) |
| `content/rate_matcher/rate_matcher_types.d.tl` | `C/rate_matcher_types.d.tl` | header: module name now `line_manager_plus.rate_matcher_types`, tealdef copy path; remove `SquareRateMatcherButtonParam` and `SquareRateMatcherWindow.ToolbarButton`; add `ICON : string` to `SquareRateMatcherWindow` |
| `content/rate_matcher/rate_matcher.css.lua` | (merged into `C/lmp.css.lua`, section 6) | file deleted |
| `content/rate_matcher/rate_matcher.script.lua` | replaced by **new** `C/rate_matcher.lua` (Lua feature module, section 2) | file deleted |

Require-path rename everywhere (mod code and tests):
`square_line_rate_matcher::/rate_matcher/` → `square_line_manager_plus::/line_manager_plus/`.
Global record names stay `SquareRateMatcher*` (prefixed, no clash with LMP's `SquareLineManagerPlusSqPerf*`).
Window id stays `squarelineratematcher.window` (ours, unique; the tests assert it).

New `tealdef/` for LMP (editor copy, the repo's layout for Teal mods, e.g. `square_better_minimap/tealdef`):
- `LMP/tealdef/line_manager_plus/rate_matcher_types.d.tl` = byte copy of `C/rate_matcher_types.d.tl`.
- `LMP/tealdef/square_line_manager_plus_def.d.tl` = `require "line_manager_plus.rate_matcher_types"`.
- then `make sqperf-sync MOD=mods/square_line_manager_plus`: writes `tealdef/sqperf/square_line_manager_plus_types.d.tl`
  and appends `require "sqperf.square_line_manager_plus_types"` to the `_def` file. `ARGS=--check` must then be clean.
- `make teal` afterwards (optional, refreshes `tlconfig.lua` for VS Code).

Deleted as duplicates (not moved): `RM/content/rate_matcher/rate_matcher_replace.res.lua` (LMP's
`lmp_replace.res.lua` installs everything), `RM/content/square_line_rate_matcher_presence.lua` (LMP has its own
presence file; nothing in the repo requires RM's), `RM/tealdef/` (replaced by the LMP tealdef above), the
`probeActive()` DEV-probe warning in `rate_matcher.script.lua` (LMP shouldn't know about a DEV probe), RM's own
`lineActionDescriptor` / `iconToggleButton` wrappers. No SQPERF copy exists in RM.

## 2. Installing the feature

`C/lmp.script.lua` `FEATURES`, new row **after** `line_actions` (so Duplicate / Reverse register first):

```lua
	{ key = "line_actions", name = "line ops", module = "square_line_manager_plus::/line_manager_plus/line_ops.lua" },
	-- an entry in the Line actions menu; needs line_actions On (rate_matcher.lua checks it)
	{ key = "line_rate_matcher", name = "rate matcher",
		module = "square_line_manager_plus::/line_manager_plus/rate_matcher.lua" },
	{ key = "map_shift_click", ... },
```

`doReplace` already runs each row in its own `pcall(installFeature, ...)` (param check, `ug_require` inside the pcall,
`mod.install(replacementApi, params)`), so a load error in any `rate_matcher_*.tl` costs only this feature
(`status.line_rate_matcher = "failed"`, one `warnOnce`). Add a header bullet:
`"line_rate_matcher" (rate_matcher.lua + rate_matcher_*.tl): "Match line rate" in the Line actions menu opens the Rate
Matcher window`, and drop "Later menu entries (Line Rate Matcher) register with lmp_actions too".

New `C/rate_matcher.lua` (plain Lua, ~90 lines), modelled on `line_ops.lua`'s install:

```lua
local detect  = ug_require "square_line_manager_plus::/line_manager_plus/lmp_detect.lua"
local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
local actions = ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua"
local window  = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_window.tl"
local PREFIX = "[LineManagerPlus] rate matcher: "
-- context(): SquareRateMatcherContext or nil, never touching an expired state (section 5)
-- install(_replacementApi, params):
--   if not detect.paramOn(params, "line_actions") then say("needs the Line actions button (line_actions Off)"); return false end
--   if not actions.install() then return false end
--   window.setContextFn(context)
--   actions.register({ id = "rate_matcher", order = 300, label = "Match line rate", icon = window.ICON, -- i18n: keys label
--     view = function(_ctx) return { enabled = true, tooltip = _("<menu tooltip, section 7>") } end,
--     run = function(ctx) window.open(ctx.line) end })
--   say("installed"); return true
```

Dependency on `line_actions`: chosen so that "Line editor: Line actions button" Off keeps meaning "no button" (its
tooltip and 13 translations stay untouched), like the estimate needs the target line info. Status then reads
`"not installed"` with one log line. (Alternative, not chosen: install the button anyway with only our entry; that
would need the `line_actions` tooltip rewritten in 13 languages.)

`LMP/mod.json` param, inserted right after `line_actions` (same style; `defaultIndex` 1 = On; at runtime the value is
the 1-based index, Off = 1, On = 2, `detect.paramOn` handles it, findings "runFn" / README):

```json
        {
            "key": "line_rate_matcher",
            "name": "Line actions: Match line rate",
            "tooltip": "On: Match line rate in the Line actions menu opens a window that compares the line's Rate with the supply it serves, suggests how many vehicles to add or remove and which model costs least, and on Apply buys, sells or replaces vehicles. Needs \"Line editor: Line actions button\" On. Off: no entry.",
            "uiType": "Button",
            "values": [
                "Off",
                "On"
            ],
            "defaultIndex": 1
        },
```

`LMP/mod.json` incompatibilities: unchanged (no need to list the DEV probe or the retired RM; RM was never published).

## 3. UI entry: `lmp_actions.register` (D1), not an `lmp_rows` button

Decision: a menu entry "Match line rate" (icon `::/gui/line_vehicle_mgmt/icons/stat_load_speed.tga`, RM's toolbar
icon, exported as `window.ICON`) in the Line actions popover, order 300 (after Duplicate 100 / Reverse 200).
Reasons: D1 (user decision 2026-10-10) puts the Rate Matcher in the popover; the toolbar is already
[Undo][Redo][A+][Line actions][paint] and overflows at narrow widths; RM's action is "open a window", a one-shot
click that fits a menu entry; the window itself does everything else. The PLAN.md "Line Rate Matcher slot" note
(lmp_rows injector left of A+) predates D1 and is superseded (section 9 updates it). No strong reason for a button
was found: the only thing lost is the toggle's "checked while the window shows this line" state, and the window has
its own Close; clicking the entry again for the same line brings the window to the front and re-reads (`window.open`
already does that via `isOpenFor`).

Window code changes (`rate_matcher_window.tl`): delete `ButtonView`, `HIDDEN`, `buttonView`, `M.ToolbarButton`
(lines ~1064-1116); export `M.ICON = ICON`; keep `open`, `close`, `isOpenFor`, `setContextFn`, every window recipe,
layout, inline style and behaviour unchanged.

Behaviour differences to accept (note in TESTING): the entry shows only when `lmp_actions.context()` is non-nil, i.e.
exactly one selected, edited, existing and **unprotected** line. RM's button also showed for a protected (mission)
line; that line can no longer open the Rate Matcher (open question 1). Menu closes after the click (`runEntry`), and
the RM window opens via `game_react_globals.getDefaultWindowApi()` as before.

## 4. What LMP code replaces, what of RM stays

| RM code | Replaced by | Notes |
|---|---|---|
| `rate_matcher.script.lua` `lineActionDescriptor` wrapper + `managerParams` | `lmp_capture.install()` (through `actions.install()` → `rows.install()`) + `capture.params()` | identical test (`commonParams.lineManagerStateRef`) |
| `iconToggleButton` wrapper (A+ anchor, `LinePanelActionButtons`) | `lmp_rows` via `lmp_actions` (the Line actions button) | RM no longer touches `makeIconToggleButton` |
| `selectedCount(params)` | `capture.selectedLineCount(params)` | gets an expired guard (section 5) |
| `shownLine(params)` | `capture.editedLine(params)` + keep `type(e) == "number" and e >= 0` | `editedLine` already checks `hasExpired()` |
| `doReplace` / `rate_matcher_replace.res.lua` (order 260) | `lmp.script.lua` FEATURES row + `rate_matcher.install` | |
| `say` / `warnOnce` in the script | local copies in `rate_matcher.lua` with LMP's prefix | as every LMP feature module |
| `ToolbarButton` | `actions.register` entry (section 3) | |
| (no perf) | `lmp_perf` | new sections below |

Stays (RM-specific, no LMP equivalent): `listFn` / `context()` shape (`line`, `protected`, `vehicleFilter`,
`listAdd`, `listRemove`) now inside `rate_matcher.lua`; all of `rate_matcher_model.tl`, `_engine.tl` (raw Rate,
vehicles with value / running / capital, supply walk, timing, model catalogue), `_commands.tl` (clone onto line,
sell, switch, replace window, price report), `_view.tl`, the window module. `lmp_stats` is **not** used: it returns
only formatted strings (Capacity / Utilization / Frequency / Rate) behind a 1 s cache; RM's stats row is Rate /
Vehicles / Per vehicle / Running costs per year from raw numbers (Rate is the only shared quantity, and RM needs it
as a number, uncached). The "clone onto this line" helper is **not** extracted to a shared `lmp_vehicles.lua` (the
slot note's idea): no other LMP feature buys vehicles since Balance was dropped (D8).

SQPERF (`lmp_perf`, one instrument): in `rate_matcher_window.tl` add

```teal
local record LmpPerfModule
	perf : SquareLineManagerPlusSqPerfInst
end
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua" as LmpPerfModule).perf
```

(a local record in the `.tl`, not in `rate_matcher_types.d.tl`: a cross-reference between two `.d.tl` def files
depends on their load order). New sections: `rate_matcher_step` (the content's `useStepState` getter: wrap the
`pcall(stepTick)` with `perf:start()` / `perf:stop`), `rate_matcher_render` (`renderSession`), `rate_matcher_click`
(`apply`, `openReplace`, `M.open`). The menu click itself is already timed as `line_actions`. Update the section
list in `lmp_perf.lua`'s header and README "Install path". Watch the 200-locals limit of the window chunk (+2 locals;
`make check` catches it).

## 5. Expired ReactState fix

Every `:old()` / `:get()` RM makes on captured Line Manager objects (all in `rate_matcher.script.lua`; the `.tl`
files read only their own states):

| Site | Call | Owner | Fix |
|---|---|---|---|
| `:45` `selectedCount` | `params.lineManagerStateRef:get()` | ref from the manager entry point (manager_window.tl:8343, passed at :6341) | `capture.selectedLineCount`, which gets `if capture.expired(ref) then return 0 end` |
| `:50` `shownLine` | `params.lineState:old()` | the manager window's `reactLineState` (:6636) — **the traceback source** | `capture.editedLine(params)` (already guarded) |
| `:77` `context` | `params.gameCtx.filters:get()` | game-level (`gui/main/game.tl:182`), not window-scoped | guard anyway: `local f = params.gameCtx and params.gameCtx.filters; if f and not capture.expired(f) then filters = f:get() end` |
| `:58-67` `listFn` | `params.addOrRemoveVehicleToVehicleList(...)` | closure that runs `creatingNewLineState:old()` and `vehicleManagerRef:get()` of that manager window (manager_window.tl:7000-7008) | build `listAdd` / `listRemove` only when `not capture.expired(params.lineState)`, and re-check at call time inside the returned function (skip silently when expired) |
| window.tl:1021 | `liveState:hasExpired()` | own state | already correct |
| window.tl:1087 | `state:old()` in `ToolbarButton` | own state, rendering | deleted with the button |

Shared hardening in `lmp_capture.lua` (benefits undo / stli / actions too): `selectedLineCount` returns 0 and
`selectedVehicles` returns `{}` when `M.expired(p.lineManagerStateRef)` / `M.expired(p.vehicleManagerStateRef)`.
Header comment: say both refs are checked.

`context()` in `rate_matcher.lua`:

```lua
local function context()
	local p = capture.params()
	if not p then return nil end
	local line = nil
	if capture.selectedLineCount(p) == 1 then
		local e = capture.editedLine(p) -- nil when p.lineState has expired
		if type(e) == "number" and e >= 0 then line = e end
	end
	local filters = nil -- guarded :get() as above
	return { line = line, protected = filters and filters.protectedEntities or nil,
		vehicleFilter = filters and filters.vehicleFilter or nil,
		listAdd = listFn(p, false), listRemove = listFn(p, true) }
end
```

With the manager closed, the open RM window keeps working on its session line (engine reads don't need the
manager); `syncList` already skips when `ctx.line ~= s.line` (nil now).

Tests (in `test_rate_matcher_gui.lua`, section 8):
- "an expired lineState of a closed manager window is never read": open the window for line 1, then replace
  `params.lineState` by `{ hasExpired = function() return true end, old = function() reads = reads + 1; error("old() on an expired state") end }`
  (as test_line_ops.lua:340-355) and `params.addOrRemoveVehicleToVehicleList` by a counter; advance the fake clock past
  2 s and render (live refresh), then Apply a clone and fire its callback, advance 1 s (re-read). Expect `reads == 0`,
  the counter 0, no `warning` log entries, the window still rendering line 1; menu view for the entry → no ctx
  (`actions.menuView().hidden`).
- In `test_groundwork.lua`: `selectedLineCount` = 0 and `selectedVehicles` = {} with expired refs (their `get`
  erroring), as the existing "capture: an expired lineState" test.

## 6. CSS merge

Append to `C/lmp.css.lua` one block, copied from `rate_matcher.css.lua` with its comment condensed (window background
and placement; right-aligned table columns repeating statistics.css.lua:386-391; hidden sort caret):

```lua
	-- Line Rate Matcher window (rate_matcher_window.tl WINDOW_ID): ... 4 rules
	do
		local W = "#squarelineratematcher.window"
		a(W, { gravity = { 0.62, 0.45 }, anchorPoint = { 0.5, 0.5 }, backgroundColor1 = colorDefault.BaseDarkMedium })
		a(W .. " DataTable::HeaderItem !right-aligned, " .. W .. " !right-aligned TextView",
			{ gravity = { -1, -1 }, textAlignment = { 1, 0.5 } })
		a(W .. " DataTable::SortButton::Icon", { visibility = "none" })
	end
```

Scope: every rule is under our own window id (nothing touches base UI or other mods). No rule can go inline (inline
StyleSheets have no gravity / textAlignment / visibility). Rule count: LMP 8 → **12** (+4); repo total unchanged
(RM's 4 leave with RM). Update the top comment of `lmp.css.lua` (it lists what it styles) and the window.tl header
("rate_matcher.css.lua" → "lmp.css.lua").

## 7. Strings, modinfo, description

`strings.json`: merge per language with a script (json load, `dict.update`, write back with the canonical layout:
`make i18n MOD=mods/square_line_manager_plus ARGS=--fix-format`). The only shared key `"Rate"` has identical texts
in all 13 languages; nothing to resolve. 67 + 90 = 157 keys/lang, plus the new keys:
- param name `"Line actions: Match line rate"` (reuse each language's RM translation of "Match line rate" and LMP's
  translation of "Line actions" for the prefix),
- param tooltip (section 2 text),
- menu entry tooltip, e.g. `"Compares the line's Rate with its supply: how many vehicles to add or remove, and which
  model costs least."` (RM's modinfo summaries are close translations to start from).
All 12 non-English languages in the same change; German "ss", CJK full-width punctuation, ko ASCII. Wrap the menu
tooltip literal in `_()` in `rate_matcher.lua`; the label goes through `-- i18n: keys label`.

`_metadata/modinfo.json` (the current summary predates phases 2-5 already):
- `summary` (≤ 100): `"Line Manager additions: undo/redo, line stats when sending vehicles, line actions, rate matching."` (97)
  and the 12 localized summaries rewritten to match (≤ 100 each; names unchanged, all ≤ 32).
- `description` (English, not localized): add "line actions to duplicate or reverse a line, a rate matcher that sizes
  a line's fleet to its supply, and Shift-click on the map" (and keep "Replaces Line Editor Undo").

`_metadata/description.html`:
- Intro paragraph: add "and Match line rate, which sizes a line's fleet to the cargo it serves" to the list.
- New `<h4>Line actions: Match line rate</h4>` after "Line actions: Duplicate and Reverse line": RM's Features bullets
  (Line stats, Supply, Target, Options table, Compare models, Apply, Replace window) with the first bullet rewritten:
  "**Match line rate** in the Line actions menu (needs the Line actions button) opens a window titled with the line's
  name"; RM's "How to use" folded into that bullet; "Nothing is bought or sold until you press Apply."
- Settings list: `<li><strong>Line actions: Match line rate</strong> (On by default; needs the Line actions button On).</li>` after Line actions.
- Notes: add RM's notes (Apply only sends the game's own buy / assign / send-to-depot / replace commands; other
  models' Rates are ≈ estimates; passenger lines get no supply target; trains / multiple units / mixed lines get no
  model comparison; mission vehicles block a switch).
- Changelog: keep `Revision 1 (2026-10-10)`, no bump; extend its sentence with "..., a Line actions button with
  Duplicate line, Reverse line and Match line rate (sizes a line's fleet to its supply), and Shift-click ...".
- Cover tagline `'Undo edits, know where you send'` (branding/mods.js:303): may stay; optional refresh (open question 3).

## 8. Tests

`git mv` into `tests/square_line_manager_plus/` (no name collisions with the 13 existing files):

| From `tests/square_line_rate_matcher/` | To | Changes |
|---|---|---|
| `test_model.lua` | `test_rate_matcher_model.lua` | require prefix; header plan path |
| `test_view.lua` | `test_rate_matcher_view.lua` | require prefix |
| `test_engine.lua` | `test_rate_matcher_engine.lua` | require prefix (lines 11-13); header path |
| `test_gui.lua` | `test_rate_matcher_gui.lua` | see below |

`test_rate_matcher_gui.lua`: keep every window test (fakes, `wa`, `render`, `content`) and swap the mount:
- stubs: add `::/gui/main/popover_react_util.tl` (as test_line_ops.lua) and give `fakeReact` the functions
  `lmp_actions`/`lmp_rows` touch at require/install (`useSelfRef`, `useState`, `onStep`, `onUnmount`,
  `onMouseEvent` already, `RegisterRecipe`); stub `square_line_manager_plus::/line_manager_plus/rate_matcher_engine.tl`
  and `..._commands.tl` with the fakes; `ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher.lua"`,
  `rm.install({}, {})`, then `line_util.makeLineActionDescriptor(params)` to capture (as the old `toolbar()` did).
- replace "mount: our button left of A+ ..." with "install: a Match line rate entry in the Line actions menu; hidden
  for several lines; line_actions Off → not installed": `actions.ids()` contains `rate_matcher`; `actions.menuView()`
  has the entry enabled with the tooltip; `actions.runEntry("rate_matcher")` opens the window titled "WC Logs";
  two selected lines → `menuView().hidden`; `rm.install({}, { line_actions = 1 })` (fresh modules) returns false.
- helper `openWindow()` = `actions.runEntry("rate_matcher")` instead of `toggleOf(toolbar(params)).p.onValueChange(1)`;
  the "reopening for another line" / "close" test calls it for the other line's params.
- add the expired-state test (section 5). `test_groundwork.lua`: the two expired-ref assertions.
- `test_lmp.lua`: add `local RM = ".../rate_matcher.lua"` to the stubbed modules (opts key `rm`), add
  `line_rate_matcher = "installed"` to every full `script.status` table, `line_rate_matcher = 2` / `= 1` to the "all
  On" / "all Off" param tables, and two tests: "rate matcher Off: the others installed; one log line" and "a rate
  matcher install that throws doesn't stop the others". Update its header list of test files.
Run: `make test MOD=mods/square_line_manager_plus` (only this mod).

## 9. Docs

- `plans/square_line_manager_plus/TESTING.md`: new section `## Line Rate Matcher (merged from square_line_rate_matcher,
  2026-10-11)`: setup (Line Manager Plus only; disable the DEV probe `square_line_rate_matcher_probe`, it mounts its
  own "RM" row; test save, Apply buys / sells; log filter `LineManagerPlus` now covers it: `[LineManagerPlus] rate
  matcher: installed`, `open line ...`, `timing line ...`, `price ...`, `clone charged ...`); merge checks (entry in
  the Line actions menu with the clock+box icon; opens the same window; clicking again brings it to front; setting
  Off → no entry, log `rate matcher: off (mod setting)`; line_actions Off → no button, log `rate matcher: needs the
  Line actions button`; protected line → no menu; **no `stack traceback` / `Calling Old() on expired ReactStateWrap`
  with the RM window left open after closing the Line Manager, for a minute**, then reopen the manager: Apply still
  updates the vehicle list); RM's phase 3f table (f1-f4) and the core checklist rows 1-10 (condensed), "Unverified in
  game", and RM's Results list as history. Also add `line_rate_matcher` to "Mod settings" and the SQPERF sections
  list.
- Plan notes moved (git mv), then `plans/square_line_rate_matcher/` is gone:
  `PLAN.md` → `RATE_MATCHER.md` (prepend a line: "Design history of the former square_line_rate_matcher, merged into
  LMP 2026-10-11 (MERGE_RM_PLAN.md); paths below are the old ones"), `PROBE.md` → `RM_PROBE.md`,
  `probe_run1.log` → `rm_probe_run1.log`, `probe_run2.log` → `rm_probe_run2.log` (LMP already has its own
  `probe_run1.log`, hence the prefix). `TESTING.md` is folded (above), not kept.
- `docs/findings.md:785-786`: paths → `plans/square_line_manager_plus/rm_probe_run1.log` and `.../RM_PROBE.md`.
- `plans/square_line_manager_plus/PLAN.md`: line 46 ("belongs to another session") and the "Line Rate Matcher slot"
  note (79-82) → "Merged 2026-10-11 as a Line actions menu entry (D1), not an lmp_rows injector; no shared
  lmp_vehicles.lua (no other buyer since D8). See MERGE_RM_PLAN.md." Lines 86 / 271 "(later Rate Matcher)" → done.
- `README.md`: feature table row (`Line actions: Match line rate` | `line_rate_matcher` | `square_line_rate_matcher`
  (never published, retired) | `rate_matcher.lua` + `rate_matcher_*.tl` (+ `lmp_actions.lua`, `lmp.css.lua`)),
  Install path (lmp_actions "the Line Rate Matcher registers here later" → done; perf sections; log prefix
  `rate matcher: `; tealdef note), Tests paragraph (4 new files).
- Code comments: `lmp_rows.lua:14` drop "Planned: the Line Rate Matcher before undo"; `lmp_actions.lua:3` "the Line
  Rate Matcher later" → "Match line rate, rate_matcher.lua"; `lmp.script.lua:9` (section 2).

## 10. Retirement (cleanup phase; look before deleting)

1. `git rm -r mods/square_line_rate_matcher` (after `ls -R` to confirm only the files listed in section 1 remain:
   `mod.json`, `strings.json`, `_metadata/{0.png,description.html,modinfo.json}`, `content/...`, `tealdef/...`).
2. `git rm -r tests/square_line_rate_matcher` (empty after the moves) and `plans/square_line_rate_matcher` (empty after
   the moves; check first).
3. `branding/mods.js`: delete the `Square.register({ id: 'square_line_rate_matcher', ... })` block (lines ~321-337
   and its blank line). `branding/README.md:80`: delete the "Line Rate Matcher `#8A7FD1`" accent row (accent free
   again). No entry in `branding/shots.js` or `branding/modio_state.json` (checked).
4. `make link`: drops the dangling `square_line_rate_matcher` staging link (tools/link_mods.py removes links into the
   repo whose target is gone). Confirm the output says "unlinked square_line_rate_matcher".
5. Other references (rg over the repo excluding `.cache`, the probe and RM's own folders): only the ones handled in
   sections 9 / 10.3 (`PLAN.md`, `README.md`, `lmp.script.lua`, `lmp_rows.lua`, `lmp_actions.lua`,
   `docs/findings.md`, `branding/*`). No other mod lists `square_line_rate_matcher` as incompatible or depends on it;
   CLAUDE.md doesn't mention it. `mods/square_lmp_probe` comments mention `square_line_rate_matcher_probe` only (fine).
6. Leave `mods/square_line_rate_matcher_probe` untouched. Its pointers to `plans/square_line_rate_matcher/PROBE.md`
   (`NOT_FOR_UPLOAD.txt:8`, `_metadata/description.html:5`, `rmprobe.script.lua:1`) go stale (open question 2).
7. Gate: `make check MOD=mods/square_line_manager_plus`, `make test MOD=...`, `make validate MOD=...`,
   `make i18n MOD=... ARGS='--check --lint-modinfo'`, `make sqperf-sync ARGS=--check`, `make link`. No commit,
   upload, `make modio` or `op`.

## 11. Risks, crash rules, open questions

GUI crash rules for the moved code (make check doesn't catch them): every recipe returns `builtin.BoxLayout` (the
window content and cells already do: `vbox`/`hbox`; keep it when deleting the button); recipes are items, never
`Component{layout = Recipe{}}`; no ScrollArea in RM (if one is added, its content must be a Component); no
`mouseTransparent` on any ImageView (the menu icon is drawn by `makeIconTextButton`); engine reads and commands stay
on the GUI main thread (click, `useStepState` getter = `onStep`), never `useStepStateTimer` / worker threads
(`onStepTimer`); `api.type.Clock` for time; pre-5.3 Lua (Teal targets 5.1; `make check` lints); `.script.lua` exports
via `data()` (no `.script.lua` is added: `rate_matcher.lua` is a plain module returning `M`); module chunk ≤ 200
locals.

Risks:
- `lmp_actions.runEntry` closes the popover after `run`: the RM window is added to the default window API first,
  then the popover removed by its own key; should not affect the RM window (different container key / recipe). Verify
  in game.
- `rate_matcher_window.tl` stays at ~1050 lines; type errors from the moved `d.tl` load order: the types file sorts
  as `line_manager_plus/rate_matcher_types` before `sqperf/...`; it references no sqperf type, so no ordering issue.
- Both LMP (250) and the DEV probe (250) wrap `makeIconToggleButton`; harmless, but the probe row and our menu both
  show; tell the tester to disable the probe.
- LMP's `selectedLineCount` guard changes shared code: run the whole LMP suite.

Open questions (defaults in brackets; the implementation proceeds with the default):
1. Protected (mission) lines lose Match line rate because `lmp_actions.context()` hides the menu for them. [Accept;
   mention in TESTING.]
2. Stale `plans/square_line_rate_matcher/PROBE.md` pointers inside the DEV probe. [Leave the probe untouched as
   required; findings.md carries the new path.]
3. Refresh the LMP cover tagline to cover the new features? [No change.]
4. `line_rate_matcher` requires `line_actions` On (section 2). [Yes; the alternative needs a rewritten `line_actions`
   tooltip.]
