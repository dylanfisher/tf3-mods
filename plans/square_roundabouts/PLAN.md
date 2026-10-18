# square_roundabouts: plan

Status: revision 7 released (code 2026-10-12, b160f53; Hub upload 2026-10-14 05:29Z, session `2026-10-14_0502_sqot`; the live modfile 8324961 matches `mods/square_roundabouts/` file for file, including the dev-only ring mid override below). A Nodes between arms param was added and removed again before that upload (2026-10-14). Display name "Roundabouts & Interchanges", seven menu entries.

Read this file and `TESTING.md` first. Finished phases, run logs and superseded designs are in `HISTORY.md` (moved verbatim from this file and `TESTING.md`), in the finished phase docs `PHASE5.md`, `INTERCHANGES.md`, `PHASE6.md`, `PHASE7_RUNBOOK.md` (they stay in this folder because mod code and tests cite them) and in `history/` (research, types, perf review). The DEV engine probe's manual is `PROBE.md`. Code comments that cite `PLAN.md "Phase N notes"` (Phases 1 to 4b) now mean `HISTORY.md`.

## Goal
A configurable roundabout construction ("Roundabouts") that replaces nothing in the base game.
Placing it stamps a ring, approach arms and optionally a centre island. Like the vanilla
roundabout, it then dissolves into ordinary, editable roads.

## Decisions (user, 2026-10-07)
- **Editable, not reconfigurable.** Every node goes in `freeNodes`, `snapNodes = {}`, no
  `postConstructionModifiable`. The vanilla pattern (`street_constructions.script.lua:632`).
- **Base-game road templates only.** No custom `.street_template.lua` or `.street.lua`. The ring
  uses the vanilla one-way set (`highway_new_small`, `town_new_one_way_small`,
  `town_new_one_way_medium`). Arms use base two-way town/country templates. This rules out a
  3-lane ring.
- modId `square_roundabouts`, display name "Roundabouts" (renamed "Roundabouts & Interchanges" in revision 4,
  2026-10-09; the main menu entry keeps "Better Roundabouts").

## What ships
Changelog: `mods/square_roundabouts/_metadata/description.html`.
- rev 1-2 (2026-10-07): Better Roundabouts (round or oval, 1/2/4 ring lanes, up to six arms, splitter
  islands, road or tram line through the centre, centre islands, tram tracks, experimental traffic
  lights) and Magic Roundabout.
- rev 3 (2026-10-08): Channelized Junction, Roundabout Interchange (two-bridge ring, dumbbell,
  peanut), hamburger through roads, engine-tuned geometry for every entry.
- rev 4 (2026-10-09): Parclo, Parclo two quadrants, Diamond; mod renamed; every slider became a
  button row; settings in the left toolbar; menu icon badge.
- rev 5 (2026-10-10): translations into all 13 game languages.
- rev 6 (2026-10-10): Channelized Junction Scale XS-XL; every size row is called Scale.
- rev 7 (2026-10-12, uploaded 2026-10-14): small 1-lane ovals with wide plain arms grow until the arms fit
  (`geom.ARM_BEHIND_PLAN`, `geom.radiusSearched`, `tests/square_roundabouts/test_oval_arm_room.lua`;
  found by the Stress Test Showcase, `plans/square_stress_test/SHOWCASE.md` finding E).

Code: `mods/square_roundabouts/content/infrastructure/street_construction/`. Each entry is a
`.con.lua` (params), a pure geometry module and a three-line `.script.lua`; `square_roundabouts_result.lua`
maps any geometry to the construction result.

| entry | con / geometry | tests (`tests/square_roundabouts/`) | design notes |
|---|---|---|---|
| Better Roundabouts | `square_roundabouts.con.lua` / `_geometry.lua`, `_shapes.lua`, `_tuning.lua` | test_geometry, test_types, test_junctions, test_through, test_oval_arm_room, test_default_unchanged | `HISTORY.md` Phases 1-4b, `PHASE5.md` 5c |
| Magic Roundabout | `_magic.con.lua` / `_magic.lua` | test_magic | `HISTORY.md` "Phase 3 notes", "Phase 3b notes" |
| Channelized Junction | `_channel.con.lua` / `_channel.lua` | test_channel, test_entries_unchanged_channel | `PHASE5.md` 5b, "Channelized Junction Scale" |
| Roundabout Interchange | `_interchange.con.lua` / `_interchange.lua`, `_ramps.lua` | test_interchange, test_entries_unchanged_interchange | `PHASE5.md` 5d, 5f, 5g |
| Parclo, Parclo two quadrants, Diamond | `_highway_{parclo,parclo2,diamond}.con.lua`, `_highway_menu.lua` / `_highway.lua`, `_ramps.lua` | test_highway, test_ramps, test_entries_unchanged_highway, test_base_interchanges | `INTERCHANGES.md` |

Shared tests: test_short_edges, test_negative_zero, test_menu_labels, test_engine_verdicts (+ `verdicts.lua`),
test_tuning, test_dev, `checks.lua` (junction and overlap models), goldens `golden_default.lua` /
`golden_entries.lua`.

## Design facts that still constrain the code
Detail and evidence in `HISTORY.md` or the named doc, under the named section.
- Base road templates only, every node in `freeNodes`, `snapNodes = {}`: placed builds dissolve into
  ordinary streets ("Decisions" above).
- updateFns are pure (no game API, no saved state); geometry modules are pure and unit-tested offline.
- No `checkEnabledScript` anywhere: "Disabled" does not re-render until the menu reopens, "Hidden"
  breaks the info panel of hovered base constructions. So every param must mean something for every
  value of the others (`HISTORY.md` "Phase 2a notes", "Every param meaningful").
- Param keys start `sqrb_`. Saved menu settings keep their meaning: never reorder or renumber values.
  Radius rows are presets on their own keys (`geom.RADIUS_PRESET_KEY`, `ix.RADIUS_PRESET_KEY`); the
  old keys stay the full-range index used by tests, goldens and the probe.
- Base resources from a mod need the `::/` prefix.
- The size (Scale / Radius) is a minimum: `geom.choosePlan` / `geom.plan` grow the ring until the
  offline junction rules fit. The engine table `square_roundabouts_tuning.lua` (generated by
  `tools/gen_roundabouts_tuning.py` from the probe CSVs here; never edit by hand) sets exact engine
  radii and floors where the probe searched. `geom.plan` stays as it was searched on probed patterns,
  so rev 7's arm rule applies only outside them (`geom.radiusSearched`: round and 2:1 rings).
- The engine shapes junctions from the curbs, invisible to scripts. Offline model fitted to ~33,000
  engine verdicts: `checks.engineModel` (free edge length >= 2.5 m, a plain arm's curb corner <= 1 m
  behind its node) (`HISTORY.md` "Phase 3b notes", "Phase 4b notes").
- Tram line through the centre: 16 m tram road stubs, a tram-only middle only from 21 m
  (`geom.TRAM_MIDDLE_MIN`); `tram_new` must not join the ring node (crash, "Phase 3 fixes").
- No `-0` in geometry (`hx.positiveZeros`, `test_negative_zero.lua`; `docs/findings.md` "Negative zero").
- Highway entries: ends within `hx.MAX_REACH` (about 481 m, 462.5 m with the highway on top) of the
  centre, or the game refuses the build (`INTERCHANGES.md` "Phase 7e2 notes").
- Goldens change only on purpose (`SQRB_GOLDEN_WRITE=1`); a geometry change must leave every other
  entry byte-identical.
- DEV mods `square_roundabouts_probe` and `square_roundabouts_lanes_probe` are never uploaded.

## Phases (all done)
- 1-4b (2026-10-07, revisions 1-2): core build, in-game fixes, Magic Roundabout, splitter islands,
  through road, tram, signals, junction model, engine probe and tuning table. `HISTORY.md` "Phase 1
  notes" to "Phase 4b notes".
- 5 (2026-10-08, revision 3): Channelized Junction, hamburger, Roundabout Interchange, engine tuning
  5e-5g: `PHASE5.md`.
- 6: lane connections at ring junctions became the mod `square_smart_lanes`: `PHASE6.md`.
- 7 (2026-10-09, revision 4): highway interchanges: `INTERCHANGES.md`, `PHASE7_RUNBOOK.md`.
- Revision 5 translations, revision 6 Channelized Junction Scale (`PHASE5.md` last section).
- Perf review 2026-10-08: nothing worth changing (`history/PERF_REVIEW.md`).

## Open work
1. **Revision 7 in-game check** (`TESTING.md` "Open checks" 1): revision 7 is live (released without it);
   no result recorded yet.
2. **Open in-game checks** (`TESTING.md` "Open checks"): traffic lights field (7.4, decides a highway
   signals param), Channelized Junction Scale S-XL (12.11, never probed), highway editing and removal
   (16C), loop speeds (16B).
3. **Engine data gaps** (`tests/square_roundabouts/verdicts.lua` `V.GAPS`): `search_radius_split` and
   the Phase 4b final `all` sweep never ran (`PROBE.md` "Phase 4b runs"), so splitter rules on layouts
   the splitter search did not probe and the provisional 60 m floors (large arms, 5-6 arms, 1-2 lanes)
   are unverified; the 1.25-1.75:1 ovals were never radius-searched (rev 7 grows them offline); 2:1
   oval, 4 lanes, 6 arms, splitter, town small from 60 m: nothing placed up to 120 m.
4. **Open question:** is the ~481 m highway reach a per-construction limit or a map-edge effect at the
   probe's 0 / 0 position (`PHASE7_RUNBOOK.md` "Open question")?
5. **Backlog:** more highway types (`INTERCHANGES.md` "Later phases": cloverleaf, trumpet,
   highway junction); SPUI and Turbo (`candidates.md`; Turbo deferred, `HISTORY.md` "Turbo: deferred");
   hover previews of the Channelized Junction and Roundabout Interchange are still the main entry's,
   the three highway previews are drawn placeholders.

## Nodes between arms: removed again (2026-10-14)
A menu param "Nodes between arms" (On by default, 2-lane rings) existed briefly in the unreleased rev 7: placed from the
menu, the game joined the nodes away on XS-M rings (16-24 m pieces), also with a 4 degree corner at them
(docs/findings/roads.md "Menu placements join short ring pieces"). User decision: Smart Lanes adds the mid nodes itself
(square_smart_lanes PLAN.md "Smart Lanes adds the mid nodes"); the param, its corner, its strings and its changelog line
are gone, the con params are as in HEAD (keys and order unchanged). Only the dev override below stays (the bench).

## Ring mid nodes (dev) (2026-10-14; ran in game: Stress Test Sheet 4 v3, mids=4 on every twin)
Dev override `sqrb_dev_ring_mid = n` (1-3; geom.DEV_KEYS.ringMid, read only when present, in no menu): every ring gap
between two different arms gets at least n + 1 edges (`geom.ringParams` minPieces), i.e. n plain ring nodes evenly
between neighbouring arms, always (the ring grows when they need room: the bench's 4-lane ring with 2 per gap, 10 -> 20 m); the two legs of one splitter arm stay one edge apart. Main
Roundabout entry only (geom.plan); the plan's checks run on the split edges as on any ring (MIN_EDGE, JUNCTION_PLAN).
Without the key every ring is byte for byte as before (golden tests). User: the Stress Test bench Sheet 4 v3 ring
`bench_rb2tm` (2 lanes, XS, 4 Town small arms: radius 10 m as without the override, 8 edges of 14.5 m chord), where
Smart Lanes' `sl_rsplit` writes its lane change at those nodes (square_smart_lanes PLAN.md "Mid-node spiral").
Tests: `tests/square_roundabouts/test_ring_mid.lua`. In-game check: square_stress_test TESTING.md 6Y (`BENCH_TWIN ...
geometry=ok ... mids=4`). Players get mid nodes from Smart Lanes (above).

## Working on the code
From `PHASE7_RUNBOOK.md`, still valid:
- `make test MOD=mods/square_roundabouts ARGS="-f <file> -k <text>"` while iterating. Three tiers:
  quick (default, ~15 s): sweeps check a sample (`checks.sampled`: every n-th case, every param value,
  the defaults; golden tests a sample of groups); `ARGS=--full` (TEST_FULL, what `make gate` runs,
  ~60 s): every case; `SQRB_FULL=1`: also the exhaustive test_finite / negative_zero sweeps. Once at the
  end: `make gate MOD=mods/square_roundabouts` (check, validate, full test; add
  `MOD2=mods/square_roundabouts_probe` when the probe changed).
- `make hx-dump KEY='...'` (one highway build's edges), `make probe-report LOGS=...`,
  `make probe-split LOG=...` (refusal patterns of a probe run).
- In-game refusal: bisect in the UI first; diff every number against the probe, sign of zero included.

## Save safety
Construction only: no game script, no saved state, no base overrides. After placement the result
is ordinary streets (plus the island construction, if the engine keeps one). `severityAdd: None`.
`severityRemove: Warning`, because removing the mod could orphan placed island constructions.
Confirm against `moddefinition.md` when scaffolding.
