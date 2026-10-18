---
name: sq-opt-forks
description: Local "SQ Opt" forks of other authors' mods (mods/square_opt_*): make fork-new, FORK.md checklist, fork-status/merge, the private backup repo (.forks-git, forks-save/forks-push), measuring changes. Use when creating, updating, merging or backing up a fork.
---

# Forks of other authors' mods (SQ Opt)

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
