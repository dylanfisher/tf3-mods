# TF3 Mod Hub

Workspace for developing Transport Fever 3 mods. Each mod lives in `mods/<modId>/` and is symlinked into the game's staging area for live testing. Local, greppable copies of the official docs and game files back all research.

## Commands

- `make docs`: regenerate all local docs (`docs-wiki` takes ~1 min, `docs-game` ~5 s). Each run rebuilds from scratch.
- `make subscribed`: copy the mod.io mods you're subscribed to into `.cache/subscribed/<modId>/` (reference only; never link them into staging, since a staging copy overrides the subscribed one).
- `make new-mod ID=square_modname NAME='Display Name' ARGS='--script --tag "Script Mod"'`
- `make fork-new UP=<upstreamModId>`, `make fork-status`, `make fork-merge FORK=<forkId>`, `make fork-finish FORK=…`, `make fork-abort FORK=…`: local forks of subscribed mods (see "Forks of other authors' mods").
- `make forks-save [MSG='...']`, `make forks-push`: commit / push the fork paths to the private backup repo (`.forks-git/`).
- `make link` / `make unlink`: symlink `mods/*` into `staging_area`.
- `make validate [MOD=mods/<id>]`: pre-flight checks against wiki rules.
- `make i18n [MOD=mods/<id>] [ARGS='--check --lint-modinfo | -v | --missing ru | --fix-format']`: translation report: every `_("...")` key and mod.json param text vs each language in `strings.json`, placeholder mismatches, untranslatable `_()` calls and sentence building, untranslated literals (`-- i18n: keys` / `-- i18n: ignore` markers in `tools/i18n.py`). `--missing LANG` prints the keys a language lacks, `--fix-format` writes the canonical layout. See "Translations".
- `make tooltips [MOD=mods/<id>] [ARGS=--fix]`: tooltip lines wider than 70 columns (translations 90, CJK counted double) in mod.json params, code literals (`tooltip = "..."`, `setTooltip(...)`) and their strings.json translations. `--fix` re-wraps mod.json param tooltips and their translations (re-keyed). `make validate` shows the first few. See "Tooltips".
- `make css-rules [MODS='id id ...']`: mod stylesheet rule count for a set of active mods (default: every mod in `mods/`; ids are looked up in `mods/` and `.cache/subscribed/`). Shared leader-marker blocks count once, as in game. The game crashes on load above ~205 (exit 1 above that). Run it before and after any GUI change.
- `make check [MOD=mods/<id>|PATHS='file/dir ...'] [ARGS=--allow-lua53]`: offline Teal type-check, Lua syntax-check and pre-5.3 lint (Lua 5.3+ constructs fail; the flag skips the lint) with the game's tl.lua.
- `make test MOD=mods/<id> [ARGS="-f FILE -k TEXT --full --no-cache -j N"]`: run `tests/<modId>/test_*` against the mod's transpiled modules. Quick mode by default: sweeps sample their cases, and a test whose recorded time is 8 s or more (a no-split file: 30 s in all) is deferred to `--full` (`defer N slow tests` lines; `-k` still runs it). `--full` (what `make gate-full` runs) checks every case and runs every test; `SQRB_FULL=1` adds the exhaustive roundabout sweep. Result cache: a test file whose last run passed and read nothing that changed since (files, env vars) is not run again and shows on the mod's `cached:` line (`--no-cache` runs it). Workers are sized to the recorded work; slow files are split into shards by the per-test times of earlier runs (`.cache/test_timings.json`). `-f` picks test files by name, `-k` tests by name (harness docs in `tests/run_tests.py`). Without `MOD=` it refuses (`--all` runs every mod: never needed for one mod's work). A `note:` line means files re-ran only because another mod's files changed.
- `make gate MOD=mods/<id> [MOD2=...]`: check, validate and quick test, one summary line each (end of a phase). `make gate-full`: the same with `--full` (before a Hub upload).
- `make covers [MOD=mods/<id>] [ARGS=--no-text]`: render the house-style cover to `mods/<id>/_metadata/0.png` with headless Chrome.
- `make shots [MOD=mods/<id>]`: render gallery slides (`_metadata/1-<hash>.png`, `2-<hash>.png`, …, named by content hash so a Hub upload keeps mod.io's gallery intact; at most 9 per mod: 10 two-digit names came out of order on mod.io after a Hub upload, 19+ fail it with mod.io error 13003) from the captures in `plans/<id>/shots/`, as defined in `branding/shots.js`.
- `make modio [MOD=mods/<id>] [ARGS='--diff --apply --only text,tags,logo,gallery --force --prune-tags']`: compare each published mod's mod.io profile (name, summary, description, tags, `0.png` logo, `1.png`… gallery) with the repo and, with `--apply`, update it through the mod.io API. Dry run by default. Needs `MODIO_TOKEN` in `.hub.env`. Never touches the modfile (the Mod Hub cooks it and writes the metadata the game reads). Sync state lives in `branding/modio_state.json`. `MODIO_TOKEN` is a 1Password `op://` reference, so **never run `make modio` or any `op` command yourself**: ask the user to run it (`! make modio ...`) and paste the output; they approve the 1Password prompt.
- `make more-from [MOD=mods/<id>] [ARGS='--published --refresh --check']`: write the "More from square" section (logo tiles per group, then a one-line Towns & Streets list) into a mod's `description.html`, before the Changelog. Groups: `branding/more_from.json`; order and logo files: `branding/modio_profiles.json`, re-read from our mod.io profile page with `--refresh` (headless Chrome, no token). `--published` does every mod on the profile; State Names descriptions get it from `gen_state_mod.py` too. A newly published mod must be added to a group. See `branding/README.md` "Mod description".
- `make modio-status [MOD=mods/<id>] [ARGS='--verbose --all']`: download each published mod's live modfile (cached in `.cache/modio/modfiles/`) and compare it with `mods/<id>/`: live vs local `revision` and the changed files, i.e. which mods need a Hub update and which changed without a revision bump. `_metadata` images and texts are profile changes (`make modio`), listed only with `--verbose`. Towns & Streets and Blank Slate are skipped unless named with `MOD=` or `--all` is given. Same token rule as `make modio`.
- `make site-dev` / `make site-media` / `make site-build` / `make site-deploy`: mod microsites (`site/`, tf3.dylanfisher.com): one landing + research pages per mod, one shared design. Deploy is outward-facing: the user runs it. Working on a mod's page: the `mod-sites` skill.
- `make teal`: write `tlconfig.lua` for VS Code Teal autocompletion.
- `make sqperf-sync [MOD=mods/<id>] [ARGS=--check]`: copy the SQPERF module `tools/sqperf/` into every mod that uses it (MOD: add it there); `--check` only reports drift. See `plans/sqperf/README.md`.
- `uv run tools/gen_photo_looks.py [--check]`: regenerate Photo Mode's 1076 look environments (4 climates x sky x haze x water layers, 4.5 MB) (`mods/square_photo_mode/content/environments/`) from the base climates' env files plus the per-layer deltas; `--check` only reports drift (run it after a game update). See `plans/square_photo_mode/LOOKS.md`.
- `uv run tools/gen_lens_keyframes.py [--check]`: regenerate Photo Mode's 1131 Lens cutscene keyframe files (`mods/square_photo_mode/content/mission/keyframes/en/sqpm_lens*.lua`) from `content/photo_mode/pm_lensdef.lua`; `--check` only reports drift (run it after changing pm_lensdef).
- `make perf` / `make audit` / `make flow` / `make bench`: SQPERF, Smart Lanes junction audit, Stress Test flow A/B and bench reports over game logs. Flags and contracts: the `stress-test-reports` skill.
- `make logs [ARGS='--tag NAME']`, `make logs-list [ARGS='--tag X --crash -v']`, `make logs-grep PAT='regex' [ARGS='--session NAME -C 2']`: archive of past game logs in `.cache/logs/` (`INDEX.md`: one line per session, newest first). The game overwrites `stdout.txt` at every start; every session's log, crash logs included, is archived automatically (SessionStart hook, and `make perf` / `make audit` / `make flow`). `LOG=` / `--session` take a session name or prefix, `last`, `last-crash`, `last-<tag or Stress Test action>` (`last-showcase`, `last-sqrl`), a seed or `live`. Flags: `uv run tools/game_logs.py -h`.

If `.cache/` is missing (fresh clone), run `make docs` before researching.

Paths auto-detect for macOS Steam. Override them in `.hub.env` (see `.hub.env.example`).

## Researching TF3 modding

Before asking the user to re-run the game for evidence, check the archived sessions: `.cache/logs/INDEX.md`, then `make logs-grep`. A session start lists newly archived game sessions (crashes included): look at those first.

Never answer from memory. TF3 differs from TF2 in important ways. Read the `docs/findings.md` index first (facts verified in game; they override the wiki) and open the topic files it points to, then search the local sources in this order:

1. `docs/wiki/INDEX.md`, then `grep -rn <term> docs/wiki/modding` for concepts, file formats and rules.
2. `.cache/game/api/tealdef/` and `.cache/game/base/tealdef/` (`*.d.tl`) for the scripting API, with doc comments. This is the same source the online `wiki.transportfever3.com/script-doc/` pages are generated from, and it matches the installed build. A script-doc URL `script-doc/api/res.html` maps to `.cache/game/api/tealdef/api/res.d.tl`.
3. `.cache/game/base/content/` for how the base game actually does something (real `.mdl`, `.mtl`, `.con.lua`, `.script.tl`). Use `docs/game/MANIFEST.txt` to find files by name.
4. `.cache/game/mods/release/` (official Urban Games mods), `.cache/wiki-examples/` and `.cache/subscribed/` (community mods) for complete mod examples.
   `celmi_timetables` (Timetables) is featured by Urban Games and passed their review: the reference for a native-looking GUI (top-bar ToggleButton, tabs, cards, rows). Our adoption: `plans/ui_style/PLAN.md`.

Use `rg` (or `grep -r`) on these paths. `.cache` is gitignored, so pass `--no-ignore` or `-uu` to `rg`.

**Testing a question in the game, cheapest first.** When the docs can't settle how an API call behaves (does it work, what does it return, which argument form), suggest the first step that can answer it, in this order:

1. **Console (the key below Esc):** it runs Lua live, so a function can be tried in seconds instead of building a test mod each time. Lead the answer with a ready-to-paste one-liner. How to write one, the good first tries and what it can't do: `docs/console.md`. Subagents end their report with the snippet.
2. **A DEV/probe mod**, only when the console can't do it: event handlers, anything over many ticks, stylesheets, load-time code (`runFn`, modifiers), GUI layout.

After a console run, read its `print` output from the live log yourself (`make logs-grep PAT='...' ARGS='--session live'`) instead of asking for a paste, then record the result in `docs/findings/<topic>.md`.

## TF3-specific facts worth remembering

- `modId` allows only `[a-z0-9_]`. TF3 dropped TF2's `_1` major-version suffix.
- Metadata is `mod.json` plus `_metadata/modinfo.json`. TF2's `mod.lua` does not apply. Some wiki example zips are TF2-era and still use `mod.lua`.
- Script functions are referenced as `<modId>::<file>@<fn>` (e.g. `mod.script@runFn`), and the file lives in `content/`. Scripts are Teal (`.tl`) or Lua.
- Some wiki pages carry a "Wip: not yet adapted for TF3" banner, and some text still says "Transport Fever 2". Treat those pages with caution and confirm against game files.
- Script functions take `captureParams` first: `runFn(captureParams, settings, allModParams)`; the wiki omits it. Param values are 1-based option indices. See `docs/findings.md`.
- Top-bar buttons (`::MainModButtonAreaExtension`): a base `builtin.ToggleButton` with our white 24 px icon, 8 px padding (the base default: a 40 px tile like the layers button), no inline colour, pressed while the mod's window is open, plus the mod.json param `hudButtonStyle` (Text / Icon, default Icon). See `plans/ui_style/PLAN.md`.
- **Mod data goes in GUI save data:** `api.gui.game.setGuiSaveData(modId, table)` / `getGuiSaveData(modId)` (per savegame, one table per mod, one writer merges its parts). Never `api.util.saveAppConfig()` or a mod key in `AppConfig.mainMenuState`: the upload review rejected Line Manager Plus and Photo Mode for it (2026-10-20). `make validate` errors on `saveAppConfig` anywhere in a mod's scripts, comments included. See `docs/findings/publishing.md`.
- Mod scripts run on the game thread: a loop that never ends freezes the game until its watchdog kills it ("Possible hang detected", no Lua error). Every `while` / `repeat` loop, recursion and graph walk over game data (nodes, edges, trees, towns) gets a hard iteration cap and a visited set where it can revisit, plus a guard against zero, negative or NaN steps. Hitting the cap ends the work with a log reason (the step is skipped, never retried in a loop). Large per-tick work gets a time or slice budget. Add a test for the capped case.
- **Console (PS5) ships its own base GUI scripts:** Window fields (`closable`) and base helper functions (`content_card.makeInfoHint`) that exist on PC can be missing, and either reloads the UI. Every Window goes through `platformWindow`; every render-time base `::/gui/...` helper is inlined or type-checked with a `builtin.*` fallback; windows follow the guarded controller pattern. See `docs/ui-guide.md` "Windows" and `docs/findings/gui.md`.
- GUI work follows `docs/ui-guide.md` (narrow windows, consistent gaps, nothing touching, checkboxes for on/off, real buttons for actions). Update the guide when a rule changes.
- **Default entities first in every UI design:** reuse what the base game uses (base `builtin.*` widgets, base recipes, base classes, base looks such as the entity-window card set inline) before inventing a look; our own style or class only when the game has none, and never at the cost of new stylesheet rules (rule cap). Timetables shows the native look; copy its patterns, not its rules.
- Status / description text in a construction-menu tool's toolbar ("Nothing selected", selection, results) uses the shared tool info style: a disabled one-value Button param in the group `sq-tool-info`, styled by the shared 4-rule "TOOL INFO STYLE" block that only the first active tool adds (`sl_tool.css.lua`, `bulk_bulldozer.css.lua`, marker `content/square_tool_info/`), never a bare grey button and never a per-mod copy of the rules (rule cap). See `docs/ui-guide.md` "Construction toolbar".
- Rows of items that may overflow (checkboxes, buttons) go in `builtin.FlowLayout{ children = ... }`, which wraps to the window width; never split rows by a fixed count. See `docs/findings.md`.
- A mod.json param can't change a stylesheet: `.css.lua` only has `api.gui`/`api.type`, runs in its own Lua state, and no channel from the scripts reaches it (6 tried). Ship variant mods for style options. See `docs/findings.md`.
- Construction geometry must never contain `-0` (mirroring code makes it): at exactly 0° rotation the builder's transform keeps it and the layout is silently refused ("Construction Not Possible", fine at 1°). Normalize zeros to `+0` before returning from `updateFn`. Script probes can't reproduce it. See `docs/findings.md` "Negative zero".
- Upload: Mod Hub → My Mods publishes from the staging area to mod.io and validates on upload. Bump `revision` with every update. **The live revision comes only from `make modio-status`** (the user runs it): git says nothing about what is published, since uploads go from the staging area, often before a commit. Ask for its output before choosing a revision number, adding a Changelog entry to a revision, or writing a Hub changelog line; never infer it from git or game logs. Text, tags, logo and gallery changes that need no new modfile go through `make modio` instead (mod.io API; Steam auth isn't usable outside the game, so it uses a mod.io personal access token). Step by step: the `release-mods` skill.

## Conventions

- All mods are published as **square**: modId `square_<modname>`, `authors: [{"name": "square", "role": "CREATOR"}]` in modinfo. Never use the owner's real name in IDs, metadata or covers.
- **American English** for all English text: UI strings, descriptions, plans, findings and docs ("curb", "center", "color", "meter", "neighboring", not "kerb", "centre", "colour", "metre", "neighbouring"). Changing an English UI string changes its translation key: re-key every language. Code identifiers and log tokens keep their names (tools parse the logs).
- When the docs and the code disagree (CLAUDE.md, a plan, a finding, a README vs what the mods actually do or the game shows), fix the out-of-date side in the same change and say so in the report; never just pick one silently. Subagents report such discrepancies so the main session fixes them.
- Don't edit generated files (`docs/wiki/**`, `docs/game/**`) by hand. Change the sync tool and rerun it.
- When a game test contradicts or fills a gap in the docs, add it to the matching `docs/findings/<topic>.md` with the date and evidence (a `.cache/logs` session name), plus its line in the `docs/findings.md` index. Game facts go there, not into agent memory.
- Plan docs follow `plans/README.md`: `PLAN.md` / `TESTING.md` hold the current state and open work; finished phases and run logs move verbatim to `HISTORY.md`.
- After `make docs`, `git diff --stat docs/` shows what changed upstream or in a game update.
- Public mod text (`description.html`, modinfo, Changelog, Hub one-liners, slides) never mentions debug tools: no console commands, log tags or test steps (`branding/README.md` "Mod description"); those stay in `docs/console.md` and `plans/`.
- Every mod has a `_metadata/description.html` with a **Changelog** section (newest revision first). Add an entry with every `revision` bump. Headings: `<h2>` only for the Changelog title, `<h4>` for everything else (sections and revision entries). Format and template: `branding/README.md` "Mod description".
- **Detecting another of our mods:** every mod ships a side-effect-free `content/<modId>_presence.lua` returning `{ modId = "<modId>" }`; another mod tells whether it is active in the current game with `pcall(ug_require, "<modId>::/<modId>_presence.lua")`. `make validate` warns when the marker is missing.
- **Tests:** run only the tests of the mod being worked on (`make test MOD=mods/<id>`, plus `-f`/`-k` to narrow while iterating). Never run the full suite, including in subagents and before reporting. Another mod's tests are run only when its own files were edited (a mod and its DEV companion, such as `square_organic_towns` + `square_organic_towns_dev`, count as one when both are touched). A change to shared code (e.g. `tools/sqperf/`, the test harness) is the one exception: even then, run only the mods that use it, and only when the change alters behaviour (a State Names template change: one state's tests plus `make test-tools`). Otherwise leave them: their tests run the next time that mod is worked on.
- **Two gate tiers:** iterate with `-f`/`-k` in quick mode; run `make gate MOD=mods/<id>` (check, validate, quick test) once at the end of a piece of work or phase, not `make test` and then the gate. `make gate-full` (every case, slow tests included) runs once per release, before the Hub upload (`release-mods` skill), or when a change targets a slow test or a full-only sweep (then `-k` / `-f ... ARGS=--full` while iterating). A subagent puts the gate's summary lines in its report. The orchestrator does not re-run tests a subagent reported green: it reads the report. It runs them only when it edited the mod's files itself afterwards, and then the cache re-runs only the affected test files. Trust `cached`; use `--no-cache` only for timing runs.
- **Writing tests:** a sweep over parameter combinations samples in quick mode and checks every case when `os.getenv("TEST_FULL")` is set (idiom: `STRIDE = FULL and 1 or 7`, still hitting every value of every param, the defaults and the extremes). Keep each test under ~8 s in full mode (split per entry or scale) so the runner can shard it. Read data files through `loadfile`/`dofile`/`io.open` and env vars through `os.getenv`, which the result cache tracks; a test that writes a file inside the repo is never cached (temp files outside it are fine).
- Mods follow `docs/wiki/modding/general/guidelines.md`: no whitespace or special characters in names, lowercase preferred, UTF-8 without BOM, DDS textures with mipmaps, WAV at 16-bit/48 kHz, at most 500 MB.

## Translations

Every published mod supports all 13 game languages (`base/content/locale/*.lang.lua`): en (source and fallback),
ru, de, fr, es, it, nl, pl, pt_BR, ja, ko, zh_CN, zh_TW. **New mods ship translated, and every new or changed
user-visible string goes into every language in the same change.** DEV/probe mods and SQ Opt forks are exempt.
Mechanics and open in-game checks: `docs/findings.md` "Translations".

- `strings.json` in the mod root: `{ "en": {...}, "ru": {...}, ... }`. Keys are the English text itself
  (`_("Filter")`, mod.json `"name": "View direction arrow"`); `en` holds only id-style keys (square_one_way_roads'
  `SQUARE_OWR_*`). Changing an English string changes its key: update every language.
- Wrap every displayed literal in `_()`: labels, tooltips, titles, status texts, construction/road names, and
  mod.json param `name`/`tooltip`/`values`. One format string per sentence (`string.format(_("%d of %d buildings"), a, b)`),
  never `_("of") .. n`. Placeholders keep the same set and order in every language; use `{name}` placeholders when
  translations need another order.
- Format, concatenate or compare `_()` results only in GUI/HUD script code. In resource files (`.con.lua`, road
  `.lua`, `.names.lua`) `_()` returns the key and the engine translates at display time. Never save or compare a
  translated string.
- Stays English: log lines (`[Minimap]`, SQPERF), ids, `description.html` (mod.io has one description per mod),
  and names the game supplies (industries, cargo, towns, lines, vehicles), which arrive localized.
- `_metadata/modinfo.json` gets `"localization": { "<lang>": { "name", "summary" } }` for the 12 other languages
  (name ≤ 32, summary ≤ 100). No localized `description`: the Hub would concatenate it into the mod.io description.
- Style: match the game's own wording where it has a term (`base/strings/<lang>/LC_MESSAGES/base.mo` in the Steam install; not copied into `.cache/game`). German writes
  real umlauts ("Städte", never "Staedte") and "ss", never "ß", as the game does ("Strasse"; its de base.mo has
  ~6400 umlauts and 2 "ß"). ja/zh use full-width punctuation (`、`/`，` `：` `（）`), ko ASCII.
  Shared texts (On/Off, "Debug: performance log" and its SQPERF tooltip) reuse an existing mod's wording.
- Layouts must fit longer text (de/ru/fr ~40% longer, CJK glyphs wide): size from the translated string, or wrap.
- Translations are AI-written. Native-speaker corrections from players are welcome: apply them to `strings.json`.
- Gate: `make i18n MOD=mods/<id> ARGS='--check --lint-modinfo'`. `make validate` warns about missing translations.
- State Names mods: translations live in the generator (`tools/gen_state_mod.py`, `templates/state_names/`).

## Tooltips

The game shows a tooltip as one line per `\n` and never wraps it, so a long tooltip becomes one very wide box.
Every tooltip (mod.json param `tooltip`, `meta = { tooltip = ... }`, `setTooltip`, construction param tooltips)
breaks its text with `\n` into lines of about 60 characters, at most 70 (translations at most 90 columns; CJK
characters count double; never start a ja/zh line with closing punctuation such as `、` or `。`). Break at sentence
or clause ends where possible. Tooltips built at runtime from variables are wrapped in code (e.g.
`square_stress_test` `stress_logic.wrapText`). Changing an English tooltip changes its translation key: re-break
every language too (`make tooltips MOD=mods/<id> ARGS=--fix` does mod.json params and their translations). Gate:
`make tooltips MOD=mods/<id>` shows 0 long lines (`make validate` warns).

## Releasing updates

The user runs every `make modio*` command (1Password prompt); Claude asks for the pasted output. A Hub changelog one-liner always starts with "Revision N: " (the new revision). Checklist (modio-status, Changelog entry, "More from square" refresh, Hub upload, Changelog line, sync): the `release-mods` skill.

## Forks of other authors' mods (SQ Opt)

Workflow (fork-new, FORK.md, merging, backup repo, measuring): the `sq-opt-forks` skill. Always:

- Third-party code stays out of this repo. `mods/square_opt_*`, `forks/`, `plans/*/original/` and `mods/square_aat_perftest/`
  are gitignored, and only `plans/<forkId>/` notes are committed. Never upload a fork to mod.io; send improvements to the author.
- The fork backup repo (`.forks-git/`, private): plain `git` commands mean the main repo. `make forks-save` / `make forks-push` only when the user asks.

## Mod covers (square house style)

Every mod gets a `_metadata/0.png` cover in the shared house style, rendered from `branding/` (never hand-edit a `0.png`). New mod, rename, look change or gallery slides: the `mod-covers` skill and `branding/README.md`.
