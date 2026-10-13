# Findings: Mod scripts, params, stylesheets and Lua limits

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Mod params, script functions and stylesheets

Found 2026-10-08 while trying to give `square_bigger_line_dots` a "Dot size" setting (game build 40420).
**Result: a mod.json param cannot change a stylesheet (`.css.lua`).** For size or style options, ship
separate variant mods instead.

### Script function signatures

- The script functions get a `captureParams` argument **first**. The wiki
  (`docs/wiki/modding/general/modscripts.md`) leaves it out:
  - `runFn(captureParams, settings, allModParams)`: base `base/base_mod.lua:8`
  - `preRunFn(captureParams, configDict, allModParams, baseConfig)`: base `base/mod.script.tl:16`
  - `postRunFn(captureParams, configDict, allModParams)`: base `base/mod.script.tl:257`
- With the wiki's two-argument `runFn(configDict, allModParams)`, the second argument is really the
  config dict (keys `climate`, `economy`, `nameList`), so `allModParams[modId]` is nil and every option
  silently falls back to its default.
- `allModParams[modId].<key>` is the **1-based index** of the chosen value, even when the param has
  `numbers` (the game log showed `dotSize = 4` for the 4th of `[12.0, 16.0, 20.0, 24.0]`).
- `runFn` runs in about 50 Lua states per game load (every worker thread: "Load Game Pool", "Sim Pool",
  "Main Thread", …). Globals it sets stay in each of those states.
- `postRunFn` runs once ("Load Game Pool 1"), about 2 s before the GUI resources and stylesheets are built.

### Stylesheets (`*.css.lua`)

- Stylesheets are rebuilt on **every game load**, on the Main Thread, after `runFn` and `postRunFn`.
  So timing is not the problem; access is.
- The stylesheet's `api` has **only `gui` and `type`**. `api.engine` and `api.res` are nil, so
  `api.engine.config.getModParams()` fails there.
- Its sandbox is minimal: `rawget` is nil. `pcall`, `type`, `tostring`, `ipairs`, `pairs`, `table.concat`,
  `require` and `log.message` work.
- Any Lua error in `data()` makes the game drop **the whole stylesheet** ("Failed to load style sheet",
  `StyleSheetRep.cpp`, in `crash_dump/error.json`) and the base styles come back. Keep risky reads in `pcall`.
- Globals set by `runFn` are not visible (`nil`): the stylesheet is built in a separate Lua state.
- `addModifier("loadStyleSheet", fn)` registers without error (the category exists in base
  `base/mod.lua:128`), but the modifier is **never called**, not even for base stylesheets.

### GUI resources (`*.gres.lua`, `gui_res_overwrite`)

- A stylesheet can read a mod's own `gui_res` resource:
  `api.gui.genericRep.get(api.gui.genericRep.find("<modId>::/path/file.gres")).data` works (the name
  has no `.lua`).
- The mod's `.gres.lua` `data()` and a `gui_res_overwrite` script (`docs/wiki/modding/misc/soundeffects.md`)
  run on the Main Thread just before the stylesheets, in the same GUI-only state: no `api.engine`, no
  `runFn` globals. So they can't read mod params either.
- In `postRunFn`, `api.res.genericRep.add(name, res, true)` works (it returns an id), but `api.res.genericRep`
  is a **separate repository** from `api.gui.genericRep`. The stylesheet can't see it, and `api.res.genericRep.find`
  doesn't find `gui_res` resources.

### Channels tried, all failed

| Channel | Why it fails |
|---|---|
| `getModParams()` inside the `.css.lua` | `api.engine` is nil there |
| `loadStyleSheet` modifier in `runFn` | never called |
| global from `runFn`, read in the `.css.lua` | separate Lua state, `nil` |
| global from `runFn`, read in a `.gres.lua`, then the `.css.lua` reads the gres | `.gres.lua` is in the GUI state too, `nil` |
| `gui_res_overwrite` script calls `getModParams()`, then `setData` | no `api.engine` |
| `postRunFn` writes or adds a generic resource | `api.res` repository, not visible to `api.gui` |

Not tried: writing a file from `runFn` and reading it in the stylesheet (needs `io` in both sandboxes),
and patching base GUI modules from a GUI script (the dots are built by a local function in
`gui/line_vehicle_mgmt/manager_hud_util.tl`).

### Debugging tips

- `log.message` from any of these contexts lands in `<userdata>/crash_dump/stdout.txt`. Prefix messages
  with the modId and `grep` for them. The thread column shows which Lua state ran the code.
- The engine logs each load's mod params ("mod params: … dotSize = 4") after "Loading config from file".
- `crash_dump/error.json` holds the most recent caught Lua error with file, line and stack trace.
- **Removing a staging mod while a save is loaded crashes the game** (2026-10-09): deleting
  `square_quota_run` (its staging symlink went with it) while in game, even though the save didn't use
  it, crashed on the next staging rescan (`LocalModHubBackend::UpdateLocalInstallations`, "Mod got
  locally deleted in restricted mod management mode", then Assertion `inAddMods && "cannot remove mods
  in game"`). Edits to files in existing mods are fine. Quit to the main menu (or close the game) before
  `make unlink`, deleting a mod folder, or switching to a git branch that lacks a mod.
- **Adding a staging mod while the game runs is fine** (2026-10-09): `make link` added
  `square_opt_zhenya_auto_assign_terminals` with the game open; stdout showed "new ModHubMod was installed and
  will be added to filesystem …" and no assertion. Whether a save was loaded at the time isn't known.

### Game-script event subscriptions are saved (2026-10-08)

- `GameScriptState` subscriptions (`subscribeToEvent`) persist in the savegame. A script that subscribes
  only `if not state:hasEventSubscriptions()` never picks up an event added in a later mod revision when
  an existing save is loaded: the new GUI events are silently dropped (no error, the handler never runs).
  Evidence: square_problem_radar rev 3 added `ProblemRadar.snooze`; on a rev 2 save the click did
  nothing and stdout.txt had no handler log line. Fix: re-run the full subscribe (`subscribeToNoEvents`
  + every `subscribeToEvent`) once per load, tracked by a module-local flag.

## 200 locals per function, also in a `.tl` file's main chunk (2026-10-10)

- A `.tl` script whose top level declares more than 200 `local`s fails to load in game with "too many local variables
  (limit is 200) in main function", and a GUI plugin in it takes the whole UI down ("Script component root failed",
  crash dump). Teal's type check passes such a file; `make check` now also compiles the generated Lua and reports it
  (`generated Lua: too many local variables ...`).
- Evidence: `square_better_minimap` `minimap_hud.script.tl` with 213 top-level locals crashed on load at 17:33:15Z
  (`MinimapHudPlugin`). Fix: group constants and helpers into tables.

## Translations: `strings.json` and `_()` (research 2026-10-10, in-game checks pending)

From game files and published mods, not yet tested in game. Replace each "pending" line with the in-game result.

**Verified in game (2026-10-10, square_better_minimap rev 6 from the staging area, game language Russian):**
`_()` in a GUI react script (HUD plugin recipes, a Window's content, CheckBox labels, a TextInputField
placeholder, Button text) shows the mod's `strings.json` `ru` text: "Пром / Фильтр / Сеть / Ярко", "Карта",
"Фильтр предприятий", "Показаны все типы". Cyrillic renders in all of them. Industry names from the game arrive
in Russian (and are longer: "Лесозаготовительное предприятие", so rows sized for English names clip; cut them
to fit). The Mod Hub "My Mods" page for that staging mod still showed the English name "Better Minimap" with the
`localization.ru` block present. Pending: whether the mod browser / mod list for subscribed mods uses it.

- `_` is a global (`api/tealdef/main.d.tl:9`, `global _ : function(string) : string`), implemented in
  `base/content/base/mod.lua:154-184`. It translates immediately only where the engine sets `_getTextNow`;
  everywhere else it returns the key unchanged and the engine translates the string when it displays it
  (resource files: `.con.lua` name/description/params, road and street `.lua`, `.names.lua`). So in resource
  files `_()` must wrap the whole displayed string: never `string.format`, concatenate or compare its result.
  GUI scripts translate immediately: the base game does `string.format(_("%.0f%%"), v)`
  (`base/content/gui/menu/settings_page.tl:88`), and community GUI scripts with a `ru` strings.json use `_()`
  the same way (zhenya_auto_assign_terminals `aat_eow.script.lua:73-80`).
- Used in published mods in: GUI `.script.lua/.tl` and the plain `.lua` modules they load, `.css.lua`
  (move_it `move_it.css.lua:20`), `.con.lua` (incl. param name/tooltip/values), `.names.lua`, `.clima.lua`,
  `.eco.lua`, `.mu.lua`, `.module.lua`, base-game HUD scripts. **Never seen** in a game script (`.gs.lua`)
  or in mod.script `runFn`. Pending: does `_()` translate there, and in `hudIconScript`?
- `strings.json` language keys are the short codes `en ru de fr es it nl pl pt_BR ja ko zh_CN zh_TW`
  (exactly the game's 13 locales in `base/content/locale/*.lang.lua`; community mods use the same keys).
  Fallback (wiki): language, then `en`, then the key itself. Pending: whether `pt_BR`/`zh_TW` fall back to
  `pt`/`zh` (irrelevant as long as every mod ships all 13 keys).
- mod.json param `name`, `tooltip` and each `values` entry are looked up in strings.json
  (zhenya_doubleclick_to_edit uses id keys, the wiki's param-filter example plain English text).
- `modinfo.json` `localization.<lang>.{name,summary,description}`: name ≤ 32 chars, summary ≤ 100, no line
  breaks. The wiki warns the Hub concatenates the languages into the uploaded mod.io description; we
  localize only `name` and `summary` (description.html stays English). `tools/modio_sync.py` ignores
  `localization`. A Hub upload with a `localization` block (name + summary only) did not concatenate anything:
  Blank Slate rev 3's mod.io description matched `description.html` exactly (2026-10-10, see "Mod Hub uploads
  and the mod.io gallery").
- Fonts: every locale has a Noto Sans CJK `unicodeFontMap` fallback, so Cyrillic and CJK should render in GUI
  text. Pending: CJK and Cyrillic in HUD (`hudIconScript`) text, whose font lacks some glyphs (▲).
- Named placeholders: the game's own convention is `{name}` plus `lang_util.format(s, {name = v})`
  (`base/tealdef/scripts/lang_util.d.tl:5`); plurals exist (`nGetText`) but no strings.json plural form is
  documented, so we avoid them.
- Pending: whether `strings.json` changes in the staging area apply live or need a game restart.

## Load crash above ~200 mod stylesheet rules (verified in game 2026-10-10)

A crash on the first frame after loading (always right after "Collect Lua Garbage"; main thread, uncaught
std::string exception; frames #8 `100016a50`, #10 `10003d16c` = libc++ string init with a garbage length, #11
`102fbe0cc` = `Component::ComputeStyles` under a recursive `Component::Validate` from `CCore::Step`) is a game bug
that depends on the **total number of stylesheet rules from all active mods**. A computed style keeps a raw pointer
(the `animationName` string at StyleSheet+0x1c8) into rule storage that has since moved or been freed.
Evidence: bisect of 15 square mods (191 rules) + zhenya mods on a large save sorted exactly by the mod rule total
(196 loads, 208/211/213/217 crash); our 15 mods + a DEV mod with only 40 inert rules
(`mods/square_css_volume_probe`, no scripts) crashed without any other mod; a UI Overhaul-only new game crashed
with the same stack on 2026-10-07. Base game ≈ 5,970 rules (comma-separated selectors count once per part),
so the limit is near 6,170 in total. Not every load crashes near the limit (the freed memory has to be reused).
Consequences: keep our stylesheets small (every selector part is a rule, so merging selectors with commas
doesn't help); count with the scratch rule counter idea (run each `.css.lua` `data()` with a stub
`stylesheetutil.makeAdder`). Reported to Urban Games: plans/bugreports/2026-10-10-load-crash-gui-tree.md.
Fix on our side (2026-10-10): trimmed our mods from 191 to 134 rules (Radar 79→62, Minimap 33→22, Supply Gaps
26→18, Industry Flows 17→13, Production Label 17→7, Line Revert 12→5); the user's full set of 20 mods
(≈190 rules) then loaded. Square preset + Easy Terminal (185) loaded too, so moving values into inline
styles (Minimap) did not bring the crash back at that level. Whether inline styles count toward the limit at
all is NOT tested: mods/square_inline_style_probe (60 inline styles, no CSS) exists but was not run.

2026-10-12 (session `2026-10-12_1732_sqrl-sqsg`, dumps `5589a32c…_0.dmp` and `735bcbd1…_2.dmp`, build 40420):
- **`celmi_timetables` alone has 187 rules.** With our 15 mods (147) plus zhenya's (56) the user's set was 382 rules.
  It loaded three times in one game session, then crashed on a later load at 18:16Z: the exact frames
  8/10/11 stack right after "Collect Lua Garbage". With Timetables on, there's almost no room for any other styled mod.
- **The crash can also follow a mod switch in the same game session, at a low rule count.** After those 382-rule loads,
  the mods were switched to a 6-mod set (48 rules) and "Empty 2" started: crash during the first frame, inside
  `102fbe0cc` itself (EXC_BAD_ACCESS at frame #0 instead of the string exception). This fits the dangling pointer into freed rule
  storage. Restart the game after switching away from a large mod set before trusting a crash as new.
- Again 2026-10-13 (session `2026-10-13_0018_top-up-598153`, dump `ac132955…_0.dmp`): a load with a larger set at
  00:37:59Z, then a switch to Timetables + Better Minimap only (≈187 + ≈25 rules) and the "sub-arctic - line manager
  test" save: frames 8/10/11 crash right after "Collect Lua Garbage" at 00:39:35Z. The earlier non-fatal
  `Invalid extension (.dds, .tga, .hdr and .png supported)` from `construction.css.lua` at game stop also appears in
  sessions that don't crash (2026-10-10, 2026-10-13_0037): unrelated.
- Rule counter: run each `.css.lua` `data()` in lupa with a stub `stylesheetutil.makeAdder` that counts the
  comma-separated selector parts, and everything else stubbed by a catch-all metatable (about 40 lines of Python).
Problem Radar rev 6 ships with 14 rules moved inline (62 → 48); if a load crash shows up with Radar active,
revert that step with `git apply -R plans/square_problem_radar/inline_styles.patch` (back to the 62-rule
version that loaded with the full 20-mod set).
Reconfirmed 2026-10-11 22:25: the same stack (frame 0 in `102fbe0cc`, 4 s after "Collect Lua Garbage") with a
20-mod set at exactly **208** mod rules, after Line Manager Plus grew 34 → 37 (3 vehicle list column widths).
Trimmed back to 33 (cargo badge width classes 7 → 5, sized to the widths that can occur) = 204 for that set.
A rule counter that runs each `.css.lua` `data()` with a stub `makeAdder` (via lupa) counts per comma part.

2026-10-12 (sessions `13ca8116` / archived 2026-10-12_1833, build 40420): **inert rules alone are enough.**
`mods/square_css_rule_crash_repro` (400 rules matching no component, no scripts) as the only mod from game start:
a new temperate game loaded, then loading the large sub-arctic save in the same session crashed right after
"Enter Game Asynchronously" with EXC_BAD_ACCESS at frame 0 in `102fbe0cc` (+1152). A fresh small new game alone can
survive. Reconfirmed in session `c9a75c9c` (fresh start, the large save as the first load): the original
frames 8/10/11 string-exception stack. Control (`99052c78`): the same save with only urbangames_no_costs (no CSS)
loads. Shared with Urban Games as plans/bugreports/square_css_rule_crash_repro.zip.

## Mod description rendering in game (verified in game 2026-10-11)

The in-game Mod Hub detail view (My Mods → a staging mod) renders `_metadata/description.html` with fewer tags than
mod.io. Screenshot of Line Editor Undo with a `<p><strong>DEPRECATED:</strong> <em>…</em></p><hr><p>…</p>` opening:

- `<p>`, `<strong>`, `<h4>` and `<ul>`/`<li>` render (`<h4>` as a plain heading line).
- `<em>` is ignored: the text shows upright.
- Whitespace between two adjacent tags is dropped: `</strong> <em>` showed as "DEPRECATED:Line". Plain text after
  `</strong>` keeps its leading space ("Undo button</strong> (a curved…" is fine).
- `<hr>` draws no line in game, at most a gap, although the wiki lists horizontal lines as supported
  (`docs/wiki/modding/general/guidelines.md:189-196`). mod.io draws it.
- Links (`<a href>`): not tested in game yet. The wiki's list doesn't include them, and console players can't open
  URLs in game (`moddefinition.md:194`), so a description must read fine without the link.

## Mod settings tooltips not seen in game (user report 2026-10-11)

The user reports that the mod.json param tooltips do not show for them in the mod list (where they pick a mod's
settings when loading a game). Not investigated (platform, UI scale, hover delay unknown). Until it is: every
param, its options, default and effect also go into `_metadata/description.html` "Settings" (done for
square_stress_test and square_smart_lanes rev 4), which the in-game mod detail view shows.

## `rawget` is nil in GUI script states (2026-10-11)

`square_organic_towns_probe` crashed at load (Lua error "attempt to call global 'rawget' (a nil value)", context
`react::recipeFn GameUIRoot`, from a module required by a GUI plugin `otp_hud.script@OtpHudPlugin`). The GUI Lua state
has no `rawget` (and presumably no `rawset`), and neither do game-script states (`otp_gs.script@update`, "Sim Pool N",
same error; a game script whose chunk throws then logs "Expected table at path: game …script" every tick, an endless
error loop). Mod/name scripts do have it (the State Names mods use `rawget` in
`mod.script.lua`, `names.script.lua` and `sn_shared.lua`). In shared modules read an optional global with
`pcall(function() return _G[k] end)` instead. `make check` does not catch it. A fixed file is not picked up by a
running game (the old module stayed loaded after the edit): quit the game fully.

## In-game Lua is pre-5.3 (crash 2026-10-03)

`math.tointeger` is nil in game. The engine transpiles Teal for target 5.1 (`bit32` exists, base `.tl` uses
`1 << n`; `tl.lua:13593-13603`): in `.tl`, `//` and bitwise ops are fine (they become `math.floor` / `bit32.*`),
but 5.3-only library calls crash (`math.tointeger`, `math.type`, `math.ult`, `utf8.*`, `string.pack`,
`table.move`), and plain `.lua` must not use `//` or bitwise operators. Offline tests run Teal's 5.3 output on Lua
5.4, so they exercise different code. `make check` lints this (`ARGS=--allow-lua53` to skip).

## mod.json param `numbers` must be doubles (2026-10-08)

`params[].numbers` must be decimal literals (`60.0`, not `60`). An integer fails with "Value is not a double"
(JsonConverterContext.h) and the mod silently disappears from the mod list; the only trace is "Failed to parse
mod.json (mod will be skipped)" in stdout.txt (square_full_refund). `make validate` checks it. When a mod "doesn't
show up", grep stdout.txt for "Failed to parse mod.json" first.

## runFn: call addModifier every time (2026-10-06)

`runFn` must call `addModifier(...)` unconditionally on every call. A file-level "register once" flag made
square_industry_production_label's `loadConstruction` modifier silently stop applying on later loads: the game
rebuilds its modifier table per load but the script stays cached. Base `base_mod.lua` and the official mods never
guard; make the modifier itself idempotent instead.

## Removing a staging mod while a save is loaded crashes (2026-10-09)

Deleting a mod folder or symlink from `staging_area` while a save is loaded crashes on the next staging rescan:
"Mod got locally deleted in restricted mod management mode", then Assertion `inAddMods && "cannot remove mods in
game"`, even when the save doesn't use that mod. Before deleting a mod, `make unlink` or checking out a branch that
lacks a mod, the user must quit to the main menu. Check the crash_dump json `errorInfo.message` before blaming mod
code.

## BaseConfig: set in preRunFn, read-only at runtime (2026-10-12)

Probe `square_sim_tuner_probe` Run A (session `2026-10-12_2328_sqstp`, build 40420, `[SQSTP]` lines).

- `preRunFn` writing its 4th argument (baseConfig) works: `simPersonDestinationRecomputationProbability` 1 -> 0.2
  is read back as 0.2 by `api.res.getBaseConfig()` in `postRunFn`, in every simulation game-script state and in the
  GUI state (`q1 match=yes`). Values come back as float32 (`0.20000000298023`).
- `runFn` runs in ~50 states and has `game` and `game.config` tables, but `game.config.<field>` is nil there:
  the wiki's `game.config.<property> = ...` in runFn is TF2-era. Use `preRunFn` (as the base game and
  `urbangames_no_costs` do).
- Writing a field on `api.res.getBaseConfig()` from a GUI script at runtime fails:
  `cannot write to read only member 'simPersonDestinationRecomputationProbability'`, value unchanged.
- The same write from a game script's `handleEvent` on the Simulation thread fails with the same error (Run C,
  session `2026-10-12_2343_top-up-563524`). BaseConfig is load-time only: a lever that must change during play
  needs another mechanism. (The game script's handleEvent only fired after `subscribeToEvent("write")`.)
