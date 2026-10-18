# Plans: layout per mod

`plans/<modId>/` holds design, research and test notes (never shipped). Agents read these before working on a
mod, so the docs they read first stay short and current; history moves out instead of piling up.

- `PLAN.md`: what the mod does now, its design, the open work and the next step. Starts with a `Status:` line
  (revision, released or not, date). Finished phases shrink to a line or two here; their detail lives in
  `HISTORY.md`.
- `TESTING.md`: the in-game checks that are still open, plus the standing regression checklist. A check that
  passed and has no regression value moves to `HISTORY.md` with its result.
- `HISTORY.md`: finished phases, past run logs and result tables, superseded designs, moved **verbatim**
  (newest first, dated). Read it only to learn why something is the way it is.
- Other docs (research, probes, briefs, phase plans) start with a one-line `Status:` (current / done YYYY-MM-DD
  / superseded by X). Finished ones may move to `history/`; `PLAN.md` links whatever is still relevant.
- Raw in-game evidence lives in the log archive (`.cache/logs/`, `make logs-grep`): cite the session name
  (e.g. `2026-10-12_0629_showcase-747943`) instead of pasting long log excerpts.
- Facts about the game itself (not this mod) go to `docs/findings/` (index: `docs/findings.md`).
