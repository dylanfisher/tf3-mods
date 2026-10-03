# TF3 Mod Hub

Workspace for developing Transport Fever 3 mods. Each mod lives in `mods/<modId>/` and is symlinked into the game's staging area for live testing. Local, greppable copies of the official docs and game files back all research.

## Layout

```
mods/<modId>/            one folder per mod (folder name == modId)
docs/wiki/               TF3 wiki modding manual as Markdown (generated, committed)
  INDEX.md               every page with its section headings: start here
  _media/                images + attachment zips (generated, gitignored)
docs/game/               INDEX.md + MANIFEST.txt of extracted game files (generated, committed)
.cache/game/             text resources extracted from the game install (gitignored)
.cache/wiki-examples/    text files from the wiki's example/template mod zips (gitignored)
tools/                   sync + mod tooling (Python, run via `uv run` / make)
.claude/agents/          tf3-docs-researcher, tf3-docs-syncer, tf3-mod-scaffolder, tf3-mod-validator
```

## Commands

- `make docs`: regenerate all local docs (`docs-wiki` takes ~1 min, `docs-game` ~5 s). Each run rebuilds from scratch.
- `make new-mod ID=author_modname NAME='Display Name' ARGS='--script --tag "Script Mod"'`
- `make link` / `make unlink`: symlink `mods/*` into `staging_area`.
- `make validate [MOD=mods/<id>]`: pre-flight checks against wiki rules.
- `make teal`: write `tlconfig.lua` for VS Code Teal autocompletion.

If `.cache/` is missing (fresh clone), run `make docs` before researching.

Paths auto-detect for macOS Steam. Override them in `.hub.env` (see `.hub.env.example`).

## Researching TF3 modding

Never answer from memory. TF3 differs from TF2 in important ways. Search the local sources in this order:

1. `docs/wiki/INDEX.md`, then `grep -rn <term> docs/wiki/modding` for concepts, file formats and rules.
2. `.cache/game/api/tealdef/` and `.cache/game/base/tealdef/` (`*.d.tl`) for the scripting API, with doc comments. This is the same source the online `wiki.transportfever3.com/script-doc/` pages are generated from, and it matches the installed build. A script-doc URL `script-doc/api/res.html` maps to `.cache/game/api/tealdef/api/res.d.tl`.
3. `.cache/game/base/content/` for how the base game actually does something (real `.mdl`, `.mtl`, `.con.lua`, `.script.tl`). Use `docs/game/MANIFEST.txt` to find files by name.
4. `.cache/game/mods/release/` (official Urban Games mods) and `.cache/wiki-examples/` for complete mod examples.

Use `rg` (or `grep -r`) on these paths. `.cache` is gitignored, so pass `--no-ignore` or `-uu` to `rg`.

## TF3-specific facts worth remembering

- `modId` allows only `[a-z0-9_]`. TF3 dropped TF2's `_1` major-version suffix.
- Metadata is `mod.json` plus `_metadata/modinfo.json`. TF2's `mod.lua` does not apply. Some wiki example zips are TF2-era and still use `mod.lua`.
- Script functions are referenced as `<modId>::<file>@<fn>` (e.g. `mod.script@runFn`), and the file lives in `content/`. Scripts are Teal (`.tl`) or Lua.
- Some wiki pages carry a "Wip: not yet adapted for TF3" banner, and some text still says "Transport Fever 2". Treat those pages with caution and confirm against game files.
- Upload: Mod Hub → My Mods publishes from the staging area to mod.io and validates on upload. Bump `revision` with every update.

## Conventions

- Don't edit generated files (`docs/wiki/**`, `docs/game/**`) by hand. Change the sync tool and rerun it.
- After `make docs`, `git diff --stat docs/` shows what changed upstream or in a game update.
- Mods follow `docs/wiki/modding/general/guidelines.md`: no whitespace or special characters in names, lowercase preferred, UTF-8 without BOM, DDS textures with mipmaps, WAV at 16-bit/48 kHz, at most 500 MB.
