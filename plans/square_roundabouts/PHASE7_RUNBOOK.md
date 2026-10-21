# Phase 7 runbook (for the remaining 7d / 7e / 7f agents)

Status: done 2026-10-09 (revision 4 released). The tool tips (fast iteration, -0 check, debugging refusals) still apply; `PLAN.md` "Working on the code" lists the commands.

Short, practical tips. Later phase reviews update this file. Last review: after 7e2 (2026-10-09).

## Where the time went
- 7a 800 s, 7b 1,154 s, 7c 427 s, 7d 566 s, 7e offline 684 s, 7c2 936 s (earlier fixes folded in below).
- 7c3 963 s, no debug loop: tools 365 s, model ~600 s (no gap over 31 s). Only sink: the full suite ran 3
  times (42 + 53 + 56 s = 150 s), once mid-phase after a label edit and twice at the end. Fixed: `make gate`
  (below) runs check + validate + test once per mod. Mid-phase use `-f` files only.
- 7e2 739 s, no debug loop, 1 failed command (csplit on hx-dump output). Tools 233 s: gate 65 s, one
  4-file test run 29 s. The cause search was hand-written python over 1080 dumped keys: now `make probe-split`.

## Next steps, in order
1. **User run p7_hx_scale_verify** (220 calls; INTERCHANGES.md "Phase 7e2 notes"): probe-report, then
   "7e after the user's probe run" below. 7c3 in-game checks (TESTING.md section 16) record in "Phase 7e notes".
2. **7f release** (section below).
- Done: 7d2 subsets `p7_hx_scale` (1224) + `p7_presets` (88); 7e2 found p7_hx_scale's 190 Large refusals =
  highway end |x| > ~481 m (462.5 m hw_over), capped by `hx.MAX_REACH`.

## Open question (later, not blocking 7f)
- Is the ~481 m reach a per-construction limit or a map-area effect at the probe's 0/0 position? Cheap check:
  rerun the refused keys (`make probe-split ... --near xmax` lists them) at a far-off position or with the
  origin offset. Same refusals = per-construction limit; placed = map edge, and `hx.MAX_REACH` may be lifted.

## The three entries (since 7c3; INTERCHANGES.md "Phase 7c3 notes")
- `square_roundabouts_highway_<parclo|parclo2|diamond>.con.lua`; the Layout row (`hx.LAYOUT_KEY`, not a probe
  axis) picks the type from `captureParams.types`; the probe sends it via `engine:paramsFor`. Scale scales the
  footprint (hx.SCALES, TERM_GAPS, DIAMOND_RAMP_MINS); Small = 7c2's Small exactly.
- Released entries: no sliders; Radius rows are presets on new keys (`geom.RADIUS_PRESET_KEY`,
  `ix.RADIUS_PRESET_KEY`), old keys stay the full-range index for tests / goldens / probe. Icons carry the
  mod badge (`with_badge`); "md5 unchanged" now means unchanged since 7c3.
- One shared highway updateFn: after a geometry change run `-f highway -f entries_unchanged_highway` and check
  `git diff tests/square_roundabouts/golden_entries.lua` touches only the intended `highway t<N>` groups.
- Probe key order (`h:` keys, CSV): type, highway, level, cross, scale, ramp, armlen, dir, year. If Large
  refuses, `hx-dump` the Medium key (5th value 2) before changing constants.

## Fast iteration
- Refusal pattern over a whole sweep: `make probe-split LOG=plans/square_roundabouts/probe_<run>.log` (2 s):
  per feature (reach, radial, longest edge / ramp, grade) placed max vs refused min, best threshold and errors,
  overall and per level. `ARGS=--uncap` for runs before the 7e2 cap; `--near xmax` lists the borderline keys.
- `make test MOD=mods/square_roundabouts ARGS="-f highway"` (3 s quick, 12 s `--full`). `-f` picks files
  (repeatable), `-k TEXT` a test-name substring. Quick (default) samples every sweep (`checks.sampled`) and
  golden group; `ARGS=--full` checks every case (make gate-full does). Cheap (< 3 s): ramps, base_interchanges,
  tuning, script, dev, replay_report. `-f short_edges` 3 s quick, 33 s full. Label / tooltip edits:
  `-f entries -f highway`.
- **Refused highway combo:** `make hx-dump KEY='<refused> <placed neighbour>'` (0.7 s; `DEV='sqrb_dev_x=1'`):
  R, dx, xm, frame, every edge (bridge, tags, lengths; `<15` marks short edges).
- Golden re-record (deliberate default-geometry change only):
  `SQRB_GOLDEN_WRITE=1 make test MOD=mods/square_roundabouts ARGS="-f entries_unchanged_highway -j 1"`.
- Edits: a python `edit(p, pairs)` with `assert s.count(a) == 1` worked well (7c3: no failed edits).

## -0 (negative zero) check
- `make test MOD=mods/square_roundabouts ARGS="-f negative_zero"` (4 s, quick and `--full` alike: every 7th
  build; SQRB_FULL=1 every build, ~20 s).
  Game-accurate (pre-5.3 doubles): `TEALRT_LUA=52 make test ... ARGS="-f negative_zero"` (only this file is
  5.2-clean). KNOWN counts for both are in the test. Never hand-write a scan.
- Released entries at 0°: only the Channelized Junction (layout 2, left-hand side-road tangents `(-0, -y)`),
  released since rev 1; left as it is: probe p7_presets (2026-10-09, at the builder's exact 0° transform)
  placed all 6 X left-hand combos, so this world `-0` in a tangent's x did no harm (`docs/findings/roads.md`
  "Negative zero"; `test_negative_zero.lua` KNOWN). Highway output: 0 raw -0 (`hx.positiveZeros`).
  (Updated 2026-10-14; was "harm unproven, pending the user's check".)

## Debugging in-game refusals (7e fix-up retro: 2 h 47 min, 13 rounds)
- **The UI is ground truth: bisect there first** with TEMPORARY DEV params in the `.con.lua`; halve the layout
  each round. Diff every number of a W line against the probe, sign of zero included (`%.17g` / `%a`).
- Don't trust a replay inside `builder.proposalCreate`, or probe settings changed in a loaded save.

## 7e after the user's probe run
1. Copy `crash_dump/stdout.txt` to `plans/square_roundabouts/probe_p7_<run>.log`, `make probe-report
   LOGS=...` (0.2 s), read the digest first. New CSVs go in `V.HX_FILES_7C2` (verdicts.lua).
2. `-f engine_verdicts -k highway`; refusals: hx-dump, change one constant (`hx.TERM_GAPS`, `hx.BRIDGE_PIECE`,
   `ramps.CLEAR`, `ramps.GORE_RUN`; gore stays <= 40 m GORE_MAX), `-f highway -f ramps` (~10 s).
3. New engine facts -> docs/findings.md with the date.

## 7f: release (revision 4; checklist in INTERCHANGES.md "7f: release", update it to 3 entries)
- Remove any 7e fix-up diagnostics the checklist names if still present (none found after 7c3).
- `mod.json` revision 4. description.html: one Settings section for the 3 highway entries (Layout, Scale ...),
  intro / Notes count the menu entries as they are now. Changelog `<h4>Revision 4 (date)</h4>` first (`<h2>`
  only for "Changelog"): New: Parclo, Parclo two quadrants and Diamond highway interchanges; Changed: size
  settings are button rows, menu icons carry the mod badge, **menu choices for radius reset once** (Radius
  rows moved to presets: the menu opens on Medium 20 m; placed roads unaffected; *shipped instead: every size
  row starts at its smallest, XS 10 m, user 2026-10-09; noted 2026-10-14*); Fixed: -0 values in new
  geometry; Channelized Junction -0 only if the user's check confirms it. modinfo summary <= 100 chars.
- Gallery: mod.io is append-only. Append `Square.slides` after "Mix and match" in `branding/shots.js`
  (10.png, 11.png ...); never edit 1-9 (slide 5 says "Four menu entries"). `make shots`; `git status`
  must show 1-9.png unchanged. Previews from the user's `shots/18-*` via
  `tools/render_preview_square_roundabouts.py`. Then the `tf3-mod-validator` agent. No SQRB_FULL needed.

## Pitfalls
- Copy edit anchors from `sed -n` output, never retype indentation. `make test` without MOD runs ~30 mods.
- Wall times vary +-20 % (game often running). No clean-HEAD worktree baseline: the probe CSVs under `plans/square_roundabouts/` are untracked, so `test_engine_verdicts` and a junctions test fail there; baseline with `--no-cache` before editing instead.
- A parallel agent may edit the probe / tests: end with a `grep` for removed names.

## Gate (run once, at the end)
- `make gate MOD=mods/square_roundabouts MOD2=mods/square_roundabouts_probe`: check, validate and
  quick test per mod (tests of 8 s or more deferred; `make gate-full`, ~70 s, runs `--full` before a release), one line each plus any FAIL. 7c3 end state: 206 + 61 passed (2026-10-13: 320). Drop MOD2 if the probe is untouched.
