# TF3 Mod Hub

A workspace for building Transport Fever 3 mods, with local copies of the official documentation and game files that you can grep.

## Setup

Requirements: macOS, the game installed through Steam, and [uv](https://docs.astral.sh/uv/).

```sh
cp .hub.env.example .hub.env   # optional: set TF3_AUTHOR, or override paths
make docs                      # mirror the wiki and extract game files
make teal                      # optional: VS Code Teal autocompletion
```

## Making a mod

```sh
make new-mod ID=yourname_coolmod NAME='Cool Mod' ARGS='--script --tag "Script Mod"'
make link        # symlink into the game's staging_area
# Edit mods/yourname_coolmod/, then test in game (Mod Hub > My Mods) or the Model Editor
make validate
```

Publish from inside the game: **Mod Hub → My Mods → Upload**.

## Keeping docs current

`make docs` rebuilds everything from scratch:

| Target | Source | Output |
|---|---|---|
| `docs-wiki` | wiki.transportfever3.com `modding:*` pages | `docs/wiki/` (Markdown, committed), `_media/` and `.cache/wiki-examples/` (gitignored) |
| `docs-game` | the local game install (`api/`, `base/`, `mods/`) | `.cache/game/` (gitignored), `docs/game/INDEX.md` and `MANIFEST.txt` (committed) |

Run `git diff docs/` after a sync to see what changed upstream or in a game update. Claude Code users can ask the `tf3-docs-syncer` agent to run the sync and summarize the changes.

## Claude Code agents

| Agent | Use it for |
|---|---|
| `tf3-docs-researcher` | "How do I … in TF3?" Answers from the local docs and game files, with citations |
| `tf3-docs-syncer` | Re-syncing the docs and summarizing what changed |
| `tf3-mod-scaffolder` | Creating a new mod that follows the wiki's structure rules |
| `tf3-mod-validator` | Pre-upload review: runs `make validate` and checks against the guidelines |
