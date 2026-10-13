# TF3 Mod Hub

Workspace for developing Transport Fever 3 mods. Each mod lives in `mods/<modId>/` and is symlinked into the game's staging area for live testing. Local, greppable copies of the official docs and game files back all research.

## Layout

```
mods/<modId>/            one folder per mod (folder name == modId)
docs/wiki/               TF3 wiki modding manual as Markdown (generated, committed)
  INDEX.md               every page with its section headings: start here
  _media/                images + attachment zips (generated, gitignored)
docs/game/               INDEX.md + MANIFEST.txt of extracted game files (generated, committed)
docs/findings.md         index of in-game verified facts that override the wiki (one line per finding)
docs/findings/           the findings themselves, one file per topic (hand-written)
docs/ui-guide.md         how our mods' windows, buttons and controls look: spacing, widgets, footer (hand-written)
.cache/game/             text resources extracted from the game install (gitignored)
.cache/wiki-examples/    text files from the wiki's example/template mod zips (gitignored)
.cache/subscribed/       copies of your subscribed mod.io mods + INDEX.md (gitignored, `make subscribed`)
tools/                   sync + mod tooling (Python, run via `uv run` / make)
mods/square_opt_<id>/    local "SQ Opt" forks of other authors' mods (gitignored, never uploaded)
forks/<forkId>/          fork upstream snapshots and merge workspace (gitignored)
.forks-git/              git dir of the private fork backup repo (same working tree; see "Forks")
plans/<modId>/           design plans and research per mod (never shipped)
tests/<modId>/           offline unit tests for mod scripts (test_*.lua/.tl), run by tests/run_tests.py
branding/                "square" cover house style: cover.js (renderer), mods.js (per-mod entries), index.html + states/forks/dev/options.html (gallery pages)
.claude/agents/          tf3-docs-researcher, tf3-docs-syncer, tf3-mod-scaffolder, tf3-mod-validator, tf3-fork-merger
```

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
- `make check [MOD=mods/<id>|PATHS='file/dir ...'] [ARGS=--allow-lua53]`: offline Teal type-check, Lua syntax-check and pre-5.3 lint (Lua 5.3+ constructs fail; the flag skips the lint) with the game's tl.lua.
- `make test [MOD=mods/<id>] [ARGS="-f FILE -k TEXT -j N"]`: run `tests/<modId>/test_*` against the mod's transpiled modules in parallel processes; slow files are split into shards using the per-test times of earlier runs (`.cache/test_timings.json`). `-f` picks test files by name, `-k` tests by name (harness docs in `tests/run_tests.py`). `SQRB_FULL=1 make test MOD=mods/square_roundabouts` also runs the exhaustive roundabout sweep (a few minutes longer). While developing a mod, run only that mod's tests (`MOD=mods/<id>`); never the full suite or another mod's tests unless its code was touched.
- `make covers [MOD=mods/<id>] [ARGS=--no-text]`: render the house-style cover to `mods/<id>/_metadata/0.png` with headless Chrome.
- `make shots [MOD=mods/<id>]`: render gallery slides (`_metadata/1-<hash>.png`, `2-<hash>.png`, …, named by content hash so a Hub upload keeps mod.io's gallery intact; at most 10 per mod, more fail the Hub upload with mod.io error 13003) from the captures in `plans/<id>/shots/`, as defined in `branding/shots.js`.
- `make modio [MOD=mods/<id>] [ARGS='--diff --apply --only text,tags,logo,gallery --force --prune-tags']`: compare each published mod's mod.io profile (name, summary, description, tags, `0.png` logo, `1.png`… gallery) with the repo and, with `--apply`, update it through the mod.io API. Dry run by default. Needs `MODIO_TOKEN` in `.hub.env`. Never touches the modfile (the Mod Hub cooks it and writes the metadata the game reads). Sync state lives in `branding/modio_state.json`. `MODIO_TOKEN` is a 1Password `op://` reference, so **never run `make modio` or any `op` command yourself**: ask the user to run it (`! make modio ...`) and paste the output; they approve the 1Password prompt.
- `make modio-status [MOD=mods/<id>] [ARGS=--verbose]`: download each published mod's live modfile (cached in `.cache/modio/modfiles/`) and compare it with `mods/<id>/`: live vs local `revision` and the changed files, i.e. which mods need a Hub update and which changed without a revision bump. `_metadata` images and texts are profile changes (`make modio`), listed only with `--verbose`. Same token rule as `make modio`.
- `make teal`: write `tlconfig.lua` for VS Code Teal autocompletion.
- `make sqperf-sync [MOD=mods/<id>] [ARGS=--check]`: copy the SQPERF module `tools/sqperf/` into every mod that uses it (MOD: add it there); `--check` only reports drift. See `plans/sqperf/README.md`.
- `make perf [LOG=path] [ARGS='--mod X --last --skip 1']`: per-mod report of the `[SQPERF]` lines in the latest `stdout.txt` (`--last`: the most recent load that has SQPERF lines). Enable the DEV mod `mods/square_sqperf_all` (never upload) to turn every SQPERF mod's debug log on at once.
- `make audit [LOG=path] [ARGS='--last --src auto|tool|pick --top 5']`: Smart Lanes junction audit report from the latest `stdout.txt`: the `[SQRL] AUDIT` lines grouped by finding (squeeze, shared, across, ramp_ramp, u_turn, unfed, dead, bypassed_turn, weave, lights), the worst junctions per finding with case / shape / detail, `AUDIT_SUMMARY` totals and skip reasons. Run it after the Stress Test's Junction test and Crossing test. See `plans/square_smart_lanes/TESTING.md` "X".
- `make flow [LOG=path] [ARGS='--last --warmup 180 --worse-pct 10 --min-samples 5 --ignore-reason entry']`: traffic flow A/B report from the Stress Test traffic log (`[SQST] FLOW_*` lines): the Showcase twins compared pairwise (`sl` / `sl_phases` vs `game`, same `pair=`) and pooled per kind / type (speed, % standing, stand time, queue; sign test across pairs), pairs with `match=no` (unless `--ignore-reason` lists all its reasons) or a missing twin excluded, zones worse than game, FLOW_ALL trend, buses, towns; `[SQRL] TOGGLE` blocks as a fallback. Contract: `plans/square_stress_test/FLOW.md`.
- `make bench [LOG=session] [ARGS='--record --warmup 180']`: Stress Test bench report for the last bench sheet run (default `LOG=last-bench`): per test and comparison Δ km/h, wins / losses, sign / Holm / Wilcoxon p, standing, throughput, a per-twin mode check from Smart Lanes' `zid=` lines, sampler health; writes a draft RESULTS.md entry to `.cache/bench/<session>.md`. `--record` (only after `BENCH_DONE ok=yes`) appends the pairs to `plans/square_smart_lanes/bench_ledger.json` and the entry to `plans/square_smart_lanes/RESULTS.md`. Design: `plans/square_stress_test/BENCH.md`.
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

## TF3-specific facts worth remembering

- `modId` allows only `[a-z0-9_]`. TF3 dropped TF2's `_1` major-version suffix.
- Metadata is `mod.json` plus `_metadata/modinfo.json`. TF2's `mod.lua` does not apply. Some wiki example zips are TF2-era and still use `mod.lua`.
- Script functions are referenced as `<modId>::<file>@<fn>` (e.g. `mod.script@runFn`), and the file lives in `content/`. Scripts are Teal (`.tl`) or Lua.
- Some wiki pages carry a "Wip: not yet adapted for TF3" banner, and some text still says "Transport Fever 2". Treat those pages with caution and confirm against game files.
- Script functions take `captureParams` first: `runFn(captureParams, settings, allModParams)`; the wiki omits it. Param values are 1-based option indices. See `docs/findings.md`.
- Top-bar buttons (`::MainModButtonAreaExtension`): a base `builtin.ToggleButton` with our white 24 px icon, 8 px padding (the base default: a 40 px tile like the layers button), no inline colour, pressed while the mod's window is open, plus the mod.json param `hudButtonStyle` (Text / Icon, default Icon). See `plans/ui_style/PLAN.md`.
- GUI work follows `docs/ui-guide.md` (narrow windows, consistent gaps, nothing touching, checkboxes for on/off, real buttons for actions). Update the guide when a rule changes.
- Rows of items that may overflow (checkboxes, buttons) go in `builtin.FlowLayout{ children = ... }`, which wraps to the window width; never split rows by a fixed count. See `docs/findings.md`.
- A mod.json param can't change a stylesheet: `.css.lua` only has `api.gui`/`api.type`, runs in its own Lua state, and no channel from the scripts reaches it (6 tried). Ship variant mods for style options. See `docs/findings.md`.
- Construction geometry must never contain `-0` (mirroring code makes it): at exactly 0° rotation the builder's transform keeps it and the layout is silently refused ("Construction Not Possible", fine at 1°). Normalise zeros to `+0` before returning from `updateFn`. Script probes can't reproduce it. See `docs/findings.md` "Negative zero".
- Upload: Mod Hub → My Mods publishes from the staging area to mod.io and validates on upload. Bump `revision` with every update. Text, tags, logo and gallery changes that need no new modfile go through `make modio` instead (mod.io API; Steam auth isn't usable outside the game, so it uses a mod.io personal access token). Step by step: "Releasing updates" below.

## Conventions

- All mods are published as **square**: modId `square_<modname>`, `authors: [{"name": "square", "role": "CREATOR"}]` in modinfo. Never use the owner's real name in IDs, metadata or covers.
- When the docs and the code disagree (CLAUDE.md, a plan, a finding, a README vs what the mods actually do or the game shows), fix the out-of-date side in the same change and say so in the report; never just pick one silently. Subagents report such discrepancies so the main session fixes them.
- Don't edit generated files (`docs/wiki/**`, `docs/game/**`) by hand. Change the sync tool and rerun it.
- When a game test contradicts or fills a gap in the docs, add it to the matching `docs/findings/<topic>.md` with the date and evidence (a `.cache/logs` session name), plus its line in the `docs/findings.md` index. Game facts go there, not into agent memory.
- Plan docs follow `plans/README.md`: `PLAN.md` / `TESTING.md` hold the current state and open work; finished phases and run logs move verbatim to `HISTORY.md`.
- After `make docs`, `git diff --stat docs/` shows what changed upstream or in a game update.
- Every mod has a `_metadata/description.html` with a **Changelog** section (newest revision first). Add an entry with every `revision` bump. Headings: `<h2>` only for the Changelog title, `<h4>` for everything else (sections and revision entries). Format and template: `branding/README.md` "Mod description".
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
- Style: match the game's own wording where it has a term (`base/strings/<lang>/LC_MESSAGES/base.mo`). German writes
  "ss", never "ß" (the game does: "Strasse"). ja/zh use full-width punctuation (`、`/`，` `：` `（）`), ko ASCII.
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

The user runs every `make modio*` command (1Password prompt); Claude asks for the pasted output.

1. **Before:** `make modio-status` lists which mods differ from their live upload. "Needs a Hub update": ready.
   "Changed, revision not bumped": bump `revision` in `mod.json` and add a Changelog entry to `description.html` first.
2. **Upload** those mods in game: Mod Hub → My Mods. The upload dialog has a one-line **Changelog** field: for every
   mod about to be uploaded, give the user a ready-to-paste line (plain text, about 150 characters at most, no
   markup) summarising every Changelog entry in `description.html` newer than the live revision (`make modio-status`
   shows it), e.g. "Rev 3: the vehicle list shows each vehicle's current cargo and load."
3. **After:** `make modio ARGS=--diff` should say "in sync" (`--verify` also compares the slide bytes). The Hub
   sends the description and keeps slides named `N-<hash>.png` intact, but an older stale description or `N.png`
   slides need `make modio ARGS=--apply`. `make modio-status` should now say "Up to date". A fresh upload shows as
   "Uploaded, waiting for mod.io" until mod.io's scan makes it live. See `docs/findings.md` "Mod Hub uploads and the
   mod.io gallery".

Changes to slides, the cover or the description alone need no Hub upload: just `make modio ARGS=--apply`.

## Forks of other authors' mods (SQ Opt)

To improve someone else's mod locally (e.g. performance) and keep taking the author's updates:

- `make subscribed`, then `make fork-new UP=<upstreamModId>`. This creates `mods/square_opt_<upstreamModId>/`, display name
  `SQ Opt: <original name>` (32 chars max), revision 1, marked incompatible with the original, plus a fork-orange cover entry in
  `branding/mods.js` (render with `make covers MOD=mods/<forkId>`; `branding/README.md` "Local forks"). In game, enable
  the fork and disable the original.
- The fork keeps upstream's file layout and changes as few lines as possible: every extra changed line is a future merge
  conflict. Mark changed code `-- optimized:` and list each change, with its reason, in `plans/<forkId>/FORK.md`. That file
  is the merge checklist.
- Updates: `make subscribed` + `make fork-status`. For UPDATE AVAILABLE, use the `tf3-fork-merger` agent: three-way merge
  against the upstream snapshot in `forks/<forkId>/base/`, conflict resolution, a FORK.md check, `make fork-finish`.
- Third-party code stays out of this repo. `mods/square_opt_*`, `forks/`, `plans/*/original/` and `mods/square_aat_perftest/`
  are gitignored, and only `plans/<forkId>/` notes are committed. Never upload a fork to mod.io; send improvements to the author.
- Those paths are backed up in a separate **private** repo (`git@github.com:dylanfisher/tf3-mods-private.git`): its git dir
  is `.forks-git/` (gitignored here), its working tree is this directory (`core.worktree = ..`), and it tracks only
  those paths. Plain `git` commands still mean the main repo; pass `--git-dir=.forks-git` for the backup. Save with
  `make forks-save [MSG='...']` (adds with `-f`, since the main `.gitignore` ignores those paths; a new kind of
  third-party path goes into `FORK_PATHS` in the Makefile), then `make forks-push`. Only when the user asks.
- Measuring a change: build a DEV harness with both implementations behind a param and identical timers.
  `mods/square_aat_perftest` with `plans/zhenya_auto_assign_terminals/PERFTEST.md` and `perf_report.py` is the example.

## Mod covers (square house style)

Every mod gets a `_metadata/0.png` cover in the shared **Diagonal Split** look: family teal on the left with title and tagline, a dark field on the right with a flat pictogram in the mod's accent colour, and no creator logo. The full rules are in `branding/README.md`. Read it before drawing a pictogram.

- New mod: add a `Square.register({...})` entry to `branding/mods.js` (id, name matching modinfo, tagline of up to 4 lines (about 32 characters wraps by itself; longer needs `\n` breaks, see `branding/README.md`), an accent distinct from the existing ones, and a pictogram built from the shared CSS classes and helpers). Preview it in `branding/index.html`, then run `make covers MOD=mods/<id>`.
- Changing the look (palette, layout) happens only in `branding/cover.js`, followed by `make covers` for all mods. Don't hand-edit a single `0.png` or fork the style per mod.
- After a mod is renamed, update its `name` in `mods.js` and re-render.
- Gallery slides: drop full-screen captures into `plans/<id>/shots/` (named `NN-slug.jpg`), add a `Square.slides(...)` entry to `branding/shots.js` with crops of just the relevant part, then `make shots MOD=mods/<id>`. See `branding/README.md`.

