# TF3 Mod Hub

Workspace for developing Transport Fever 3 mods. Each mod lives in `mods/<modId>/` and is symlinked into the game's staging area for live testing. Local, greppable copies of the official docs and game files back all research.

## Layout

```
mods/<modId>/            one folder per mod (folder name == modId)
docs/wiki/               TF3 wiki modding manual as Markdown (generated, committed)
  INDEX.md               every page with its section headings: start here
  _media/                images + attachment zips (generated, gitignored)
docs/game/               INDEX.md + MANIFEST.txt of extracted game files (generated, committed)
docs/findings.md         in-game verified facts that override the wiki (hand-written)
.cache/game/             text resources extracted from the game install (gitignored)
.cache/wiki-examples/    text files from the wiki's example/template mod zips (gitignored)
.cache/subscribed/       copies of your subscribed mod.io mods + INDEX.md (gitignored, `make subscribed`)
tools/                   sync + mod tooling (Python, run via `uv run` / make)
plans/<modId>/           design plans and research per mod (never shipped)
tests/<modId>/           offline unit tests for mod scripts (test_*.lua/.tl), run by tests/run_tests.py
branding/                "square" cover house style: cover.js (renderer), mods.js (per-mod entries), index.html (gallery)
.claude/agents/          tf3-docs-researcher, tf3-docs-syncer, tf3-mod-scaffolder, tf3-mod-validator
```

## Commands

- `make docs`: regenerate all local docs (`docs-wiki` takes ~1 min, `docs-game` ~5 s). Each run rebuilds from scratch.
- `make subscribed`: copy the mod.io mods you're subscribed to into `.cache/subscribed/<modId>/` (reference only; never link them into staging, since a staging copy overrides the subscribed one).
- `make new-mod ID=square_modname NAME='Display Name' ARGS='--script --tag "Script Mod"'`
- `make link` / `make unlink`: symlink `mods/*` into `staging_area`.
- `make validate [MOD=mods/<id>]`: pre-flight checks against wiki rules.
- `make check [MOD=mods/<id>|PATHS='file/dir ...'] [ARGS=--allow-lua53]`: offline Teal type-check, Lua syntax-check and pre-5.3 lint (Lua 5.3+ constructs fail; the flag skips the lint) with the game's tl.lua.
- `make test [MOD=mods/<id>] [ARGS="-k TEXT -j N"]`: run `tests/<modId>/test_*` against the mod's transpiled modules, one process per test file in parallel (harness docs in `tests/run_tests.py`). `SQRB_FULL=1 make test MOD=mods/square_roundabouts` also runs the exhaustive roundabout sweep (a few minutes longer).
- `make covers [MOD=mods/<id>] [ARGS=--no-text]`: render the house-style cover to `mods/<id>/_metadata/0.png` with headless Chrome.
- `make shots [MOD=mods/<id>]`: render gallery slides (`_metadata/1.png`, `2.png`, …) from the captures in `plans/<id>/shots/`, as defined in `branding/shots.js`.
- `make teal`: write `tlconfig.lua` for VS Code Teal autocompletion.

If `.cache/` is missing (fresh clone), run `make docs` before researching.

Paths auto-detect for macOS Steam. Override them in `.hub.env` (see `.hub.env.example`).

## Researching TF3 modding

Never answer from memory. TF3 differs from TF2 in important ways. Read `docs/findings.md` first (facts verified in game; they override the wiki), then search the local sources in this order:

1. `docs/wiki/INDEX.md`, then `grep -rn <term> docs/wiki/modding` for concepts, file formats and rules.
2. `.cache/game/api/tealdef/` and `.cache/game/base/tealdef/` (`*.d.tl`) for the scripting API, with doc comments. This is the same source the online `wiki.transportfever3.com/script-doc/` pages are generated from, and it matches the installed build. A script-doc URL `script-doc/api/res.html` maps to `.cache/game/api/tealdef/api/res.d.tl`.
3. `.cache/game/base/content/` for how the base game actually does something (real `.mdl`, `.mtl`, `.con.lua`, `.script.tl`). Use `docs/game/MANIFEST.txt` to find files by name.
4. `.cache/game/mods/release/` (official Urban Games mods), `.cache/wiki-examples/` and `.cache/subscribed/` (community mods) for complete mod examples.

Use `rg` (or `grep -r`) on these paths. `.cache` is gitignored, so pass `--no-ignore` or `-uu` to `rg`.

## TF3-specific facts worth remembering

- `modId` allows only `[a-z0-9_]`. TF3 dropped TF2's `_1` major-version suffix.
- Metadata is `mod.json` plus `_metadata/modinfo.json`. TF2's `mod.lua` does not apply. Some wiki example zips are TF2-era and still use `mod.lua`.
- Script functions are referenced as `<modId>::<file>@<fn>` (e.g. `mod.script@runFn`), and the file lives in `content/`. Scripts are Teal (`.tl`) or Lua.
- Some wiki pages carry a "Wip: not yet adapted for TF3" banner, and some text still says "Transport Fever 2". Treat those pages with caution and confirm against game files.
- Script functions take `captureParams` first: `runFn(captureParams, settings, allModParams)`; the wiki omits it. Param values are 1-based option indices. See `docs/findings.md`.
- A mod.json param can't change a stylesheet: `.css.lua` only has `api.gui`/`api.type`, runs in its own Lua state, and no channel from the scripts reaches it (6 tried). Ship variant mods for style options. See `docs/findings.md`.
- Upload: Mod Hub → My Mods publishes from the staging area to mod.io and validates on upload. Bump `revision` with every update.

## Conventions

- All mods are published as **square**: modId `square_<modname>`, `authors: [{"name": "square", "role": "CREATOR"}]` in modinfo. Never use the owner's real name in IDs, metadata or covers.
- Don't edit generated files (`docs/wiki/**`, `docs/game/**`) by hand. Change the sync tool and rerun it.
- When a game test contradicts or fills a gap in the docs, add it to `docs/findings.md` with the date and evidence.
- After `make docs`, `git diff --stat docs/` shows what changed upstream or in a game update.
- Every mod has a `_metadata/description.html` with a **Changelog** section (newest revision first). Add an entry with every `revision` bump. Headings: `<h2>` only for the Changelog title, `<h4>` for everything else (sections and revision entries). Format and template: `branding/README.md` "Mod description".
- Mods follow `docs/wiki/modding/general/guidelines.md`: no whitespace or special characters in names, lowercase preferred, UTF-8 without BOM, DDS textures with mipmaps, WAV at 16-bit/48 kHz, at most 500 MB.

## Mod covers (square house style)

Every mod gets a `_metadata/0.png` cover in the shared **Diagonal Split** look: family teal on the left with title and tagline, a dark field on the right with a flat pictogram in the mod's accent colour, and no creator logo. The full rules are in `branding/README.md`. Read it before drawing a pictogram.

- New mod: add a `Square.register({...})` entry to `branding/mods.js` (id, name matching modinfo, tagline of 32 characters or fewer, an accent distinct from the existing ones, and a pictogram built from the shared CSS classes and helpers). Preview it in `branding/index.html`, then run `make covers MOD=mods/<id>`.
- Changing the look (palette, layout) happens only in `branding/cover.js`, followed by `make covers` for all mods. Don't hand-edit a single `0.png` or fork the style per mod.
- After a mod is renamed, update its `name` in `mods.js` and re-render.
- Gallery slides: drop full-screen captures into `plans/<id>/shots/` (named `NN-slug.jpg`), add a `Square.slides(...)` entry to `branding/shots.js` with crops of just the relevant part, then `make shots MOD=mods/<id>`. See `branding/README.md`.

