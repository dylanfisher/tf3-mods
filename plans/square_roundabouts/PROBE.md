# square_roundabouts_probe: asking the engine which combos fail

**DEV ONLY. Never upload `square_roundabouts_probe`.** It lives in `mods/square_roundabouts_probe/`
and `make link` puts it in the staging area, so Mod Hub > My Mods will list it: don't publish it.
Markers: modinfo name/summary/description ("DEV ONLY - NOT FOR UPLOAD"), `NOT_FOR_UPLOAD.txt`
in the mod root, and the description.html first paragraph.

## Why
In game some Better Roundabouts combos give "Construction not possible" with nothing useful in
stdout.txt (e.g. town medium/large arms + 6 arms + splitter islands), while the offline junction
model (`tests/square_roundabouts/checks.lua`, `checks.junctions` / `checks.junctionRoom`) passes
them. The probe asks the engine itself, for a grid of param combos, whether each would place and
which error messages it gives, without building anything.

## How it works
- `content/probe/probe.gs.lua` registers a game script with a no-op `updateScript` and a
  `guiUpdateScript` (GUI thread; `docs/wiki/modding/scripting/gamescripts.md` "UI Callbacks").
  Pattern as `mods/square_problem_radar/content/radar/radar.gs.lua` and base
  `gui/hud/cargo_flow.gs.lua`. No events, no game-script state: nothing goes into the savegame.
- `probe.script.lua` (exports via `data()`), on the first `guiUpdate`: reads the mod settings via
  `api.engine.config.getModParams()[modId]` (`api/engine.d.tl:1807`; 1-based indices, as
  `.cache/subscribed/zhenya_doubleclick_to_edit/content/gui/dce.script.lua:75-77` reads them on
  the GUI thread). If "Run the probe" is On it waits "Start delay" seconds (`os.time`), then sets
  up once and evaluates "Combos per update" combos per `guiUpdate` until done. Once per game load.
- `probe_engine.lua` per combo:
  1. `api.type.SimpleProposal.new()` with one `SimpleProposal.ConstructionEntity`
     {fileName, params, transf, name, playerEntity} in `constructionsToAdd`
     (`api/type.d.tl:2827-2860`; built as base `mission/mission_framework/mission_framework_util_entity.tl:98-113`
     and `.cache/game/mods/release/urbangames_campaign_mission_05/content/mission/tasks/drilling/send_vehicle.tl:29-45`,
     including the `Mat4f.new(Vec4f...)` transf).
  2. `api.engine.util.proposal.makeProposalData(sp [, context])` (`api/engine/util.d.tl:925`). The
     Teal declaration says `Proposal`, but the native function takes the `SimpleProposal`:
     `.cache/subscribed/move_it_probe_overpass/content/tools/overpass_probe/overpass_probe.script.tl:325-330`
     ("Build 40408 requires SimpleProposal here"), called from a GUI construction tool
     (`:3748`, `:5381`) to validate before building. Our game is build 40420 (stdout.txt header).
     No `api.cmd.*` call exists anywhere in the probe: nothing is ever sent or built.
  3. Reads `ProposalData.errorState {critical, messages, warnings, infos}`, `collisionInfo`
     (collisionEntities, buildingEntities), `toAddData`, `costs` (`api/type.d.tl:2693-2760`).
     The game's own GUI shows `errorState.messages` for a proposal (base
     `gui/entity_window/bridge_and_tunnel.tl:131-134`, `builtin.ProposalViewer.onCreateProposalData`).
     `ok = not critical and #messages == 0` (the overpass probe's block rule, `overpass_probe.script.tl:375-383`).
  4. If not ok: runs the updateFn alone with `api.engine.util.construction.getConstructionResult(file, -1, params)`
     (`api/engine/util.d.tl:809-814`; -1 = no template, as base
     `gui/construction/construction_react_util.tl:1031` and `construction.tl:3655`) and logs
     `upd=ok|nil|error: ...`, to tell a Lua/updateFn failure from an engine geometry rejection.
  5. Runs `square_roundabouts_geometry.build` (or `_magic.build`) itself via `ug_require` of
     `square_roundabouts::/infrastructure/street_construction/...` and logs the effective radius
     (`effR`), `forced`, splitter `fork` bump, semi-axes `a`/`b`, edge count; Magic: `effSize`, `rs`.
- The construction's resource name is resolved once with `api.res.constructionRep.find`
  (`api/res.d.tl:26-29`), trying `square_roundabouts::/infrastructure/street_construction/square_roundabouts.con`,
  then without the slash, then without the mod prefix; the chosen name is logged (`INFO entry main: ...`).
- Position: mod settings X/Y (default 0,0 = map centre), z = `api.engine.terrain.getHeightAt`
  (`api/engine.d.tl:1725-1745,1811`); logs an ERROR if the point is on water or off the map.
- Params passed: `getGlobalConstructionParams()` (what the builder preview merges in,
  `construction.tl:3668-3672`; its keys are logged once as `INFO global construction params:`),
  then `probe_config.lua` `EXTRA_PARAMS` (empty), then the combo's `sqrb_*` indices, plus
  `seed = 1` if missing (base helpers always set a seed, `mission_framework_util_entity.tl:99-102`).
  The builder's own toolbar params (`height`, `rotation`, underground; `construction_react_util.tl:851-920`)
  are not added: our updateFn ignores them and the transf carries position and rotation (identity).
- The real GUI builder (`action = "ACTION_CONSTRUCTION_BUILDER"`, `construction_react_util.tl:1023`)
  is native code; there is no Lua path that reproduces its red/green check exactly. makeProposalData
  is the closest scriptable equivalent (see Unverified).

Files: `content/probe/` `probe.gs.lua`, `probe.script.lua` (GS glue), `probe_engine.lua` (api calls),
`probe_grid.lua` (grid + line format, pure), `probe_runner.lua` (batching, pure),
`probe_config.lua` (settings, pure), `probe_geom.lua` (geometry correlation, pure).
Tests: `tests/square_roundabouts_probe/` (Phase 5e: subset sizes, new axes == the channel /
interchange .con.lua params, grid candidates, dev params against the real channel / interchange
geometry, every p5 combo sane, the dev pre-1940 construction; search candidates, job counts, dev params against the
real geometry, runner early exit/full grids/skips, T/S lines, dev override check: `test_search.lua`;
grid sizes, axes == the real .con.lua params and
`PARAM_KEYS`, line format round trip, runner batching/errors, mod.json == config, geometry with the
real modules).

## Grid
Edit `grid.SUBSETS` in `content/probe/probe_grid.lua` (blocks of axis -> list of labels or `"*"`;
omitted axes take the .con.lua default). A new subset name must also be added to
`grid.SUBSET_ORDER` and to the `values` of `sqrb_probe_subset` in `mod.json` (a test checks).

| subset | combos | what |
|---|---|---|
| smoke | 20 | defaults, 6 arms + splitter (town s/m/l), road/tram through, tram on, Magic sizes x town s/l; Phase 5e: a hamburger with lights, the Channelized Junction and Roundabout Interchange defaults |
| splitter6 | 432 | the reported failure: 6 arms + splitter on, shape round/2:1, lanes 1/2/4, radius 8/20/40/60, all centres, all arm roads |
| magic | 60 | Magic: 5 sizes x 6 arm roads x 2 directions (island None) |
| main_cw | 216 | clockwise sample: 2 lanes, 20 m, all arms x splitter x centre x arm road, tram off |
| main | 10368 | shape round/2:1 x lanes 1/2/4 x radius 8/20/40/60 x all 6 arm layouts x splitter off/on x centre nothing/road/tram x 6 arm roads x tram off/on; CCW, island None, signals Off |
| all | 10644 | magic, main_cw, then main |

Phase 4 search subsets (jobs, not combos; see "Search runs" below for what each asks):

| subset | jobs | engine calls (max / expected) | runtime at ~40 calls/s |
|---|---|---|---|
| search_quick | 178 | 3,955 / ~560 | ~15-30 s |
| search_magic | 48 | 330 / ~250 | ~10 s |
| search_tram | 318 | 5,712 / ~1,200 | ~30-60 s |
| search_splitter | 76 | 8,208 / 8,208 (full grid) | ~3.5 min |
| search_radius | 6,624 | 125,856 / ~10,000-16,000 | ~4-7 min |
| search_radius_split | 2,880 | 54,720 / ~11,000-15,000 (rules baked in Phase 4b) | ~5-7 min |
| search | 7,066 | 140,106 / ~20,000-26,000 (all but search_radius_split) | ~8-12 min |
| search_magic2 | 12 | 60 / 60 (2-lane Magic satellites: 6 arm roads x 2 directions x 5 sizes) | a few seconds |
| search_magic_sizes | 24 | 120 / 120 (search_magic's sizes + search_magic2) | ~5 s |

Phase 5e subsets (sweeps and searches of the new work): see "Phase 5e runs" below.

"Expected" for the radius searches is estimated from the sweep (`probe_results.csv`): ~90% of
those combos are accepted at their first candidate. The max is only reached if the engine
rejected everything; then stop the run (quit to the menu) and check the dev override check line.

Runtime: unknown until the first run; the PROGRESS lines log combos/s and an ETA. Estimate:
the geometry build costs about 4 ms per combo offline (45 s for all 10644, Lua 5.4) and runs twice
per combo in game (probe + engine updateFn), plus the engine's proposal work (unknown, guess
5-50 ms). So "all" is roughly 3-15 minutes; smoke a few seconds; splitter6 under a minute. With
"Combos per update" 4 the game drops frames but stays responsive; raise it to 8/16 to go faster.

## Steps
1. `make link` (done; the probe and square_roundabouts are both symlinked into staging_area).
2. Start TF3. New game (or Map Editor is not needed): a **flat, empty** map, no towns or industries
   near the centre (e.g. a small map with the flat terrain preset, 0 towns/industries if offered).
   Starting year >= 1940 (both entries have `yearFrom = 1940`; tram tracks need 1925+).
3. In the mod selection enable **Better Roundabouts** and **DEV Roundabouts Probe** (it depends on
   Better Roundabouts, which loads first). Probe settings (cog / mod settings in the mod list):
   - Run the probe: On
   - Subset: **smoke** for the first run (checks the API path), then **all** (or splitter6 / magic / main)
   - Start delay 15 s, Combos per update 4, Position 0/0 (move it if the centre isn't flat or is water)
   - Proposal context: None first; a second run with Player compares the context variant
   - Log placeable combos: On (the parser needs ok rows for failure rates)
4. Load the game and **pause** it. Wait. Watch progress in the in-game console (the key below Esc)
   or with
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered SQRB_PROBE`.
   The run ends with `[SQRB_PROBE] END ...`. Don't build or bulldoze during the run.
5. Quit to the main menu (or keep playing). To run another subset: change the mod setting and
   reload the save, or start a new game; each load runs once.
6. `uv run tools/parse_probe.py` (last run in stdout.txt; `--list` lists runs, `--run N` picks one,
   `--stdout PATH` for a copied log). Writes `plans/square_roundabouts/probe_results.md` and
   `probe_results.csv` (smoke and the Phase 5e subsets: `probe_<subset>.*`, "Phase 5e runs").
   stdout.txt is overwritten on the next game start: parse (or copy it) first.
7. Afterwards disable the probe in the mod list (or delete its staging_area symlink).

## Search runs (Phase 4)

### What they ask
The sweep found whole families that never place (splitter + medium/large arms; Magic with large
arms below vlarge/large; tram line on small rings). The searches ask the engine for the smallest
or most compact layout that does place, using **dev overrides**: extra construction params
`sqrb_dev_*` that `square_roundabouts` reads only when present (never in a menu; `geom.readDev`,
`geom.DEV_KEYS`):

| override | param | meaning |
|---|---|---|
| radius | `sqrb_dev_radius` | exact ring radius (m): no slider, no growth, no tuning floor; built even if the offline model rejects it (`offline=false`) |
| magicSize / magicRadius / magicDistance | `sqrb_dev_magic_size` / `_radius` / `_distance` | Magic: exact size index, satellite radius (m), centre-to-satellite spacing (m; default 3 x centreline + 1, at least 1.7 x) |
| split / fork / spread | `sqrb_dev_split_length` / `sqrb_dev_fork` / `sqrb_dev_spread` | splitter: split node distance (m), fork angle (deg), leg spread at the ring (m) |
| leg | `sqrb_dev_leg` | splitter leg template: 1 one-way xsmall (shipped), 2 one-way small, 3 one-way medium (tram variants with Tram tracks On) |
| neck / neckType | `sqrb_dev_neck` / `sqrb_dev_neck_type` | splitter: a narrower two-way piece (m) between the arm and the split node; road = arm road index (default town/country small of the arm's family) |
| tramStub | `sqrb_dev_tram_stub` | tram line: stub length beyond the ring half width (m; shipped 16) |

Kinds of search job (`probe_grid.lua` `grid.SEARCH`, `grid.candidates`):
- **radius** (search_radius, search_tram CW block, search_radius_split): for each base combo of the
  main grid, the exact radius from the slider value (8/20/40/60) up in 5 m steps (plus 12 m) to
  120 m; **stops at the first accepted radius**. Linear with early exit, not binary: the sweep
  shows failures are not monotonic in the radius (1-lane rings fail at 40 m but not at 20 m), so a
  bisection would report wrong minima. search_radius leaves out splitter + medium/large arms (100%
  fail at any radius; that is the splitter search's job) and splitter with Arms None (same build
  as Off). search_radius_split covers exactly those, and **skips every job whose arm road has no
  splitter rule in the tuning table** (so it costs nothing before a rule is baked).
- **magic_size** (search_magic): every arm road x direction, each size exactly (no growth), all 5.
- **magic_spacing** (search_magic): satellite radius 8/10/12/15/20/25 m x every arm road,
  spacing from 2 x the satellite centreline radius up in 5 m steps; first accepted.
- **splitter** (search_splitter): medium/large arm roads x 3 (T)/4/6 arms x 1/2/4 lanes x exact
  radius 20/40 m (round) plus a 2:1 oval at 30 m; per job the full grid leg {xsmall, small,
  medium} x fork {35, 50, 65 deg} x split {20, 32, 45 m} x spread {6, 11 m} x neck {none, 15 m}
  = 108 candidates, most compact first. Full grid on purpose: a rule must work across layouts,
  lanes and radii, so we need every verdict.
- **tram_stub** (search_tram): tram line through the centre, 4 arms, 1/2/4 lanes, both directions,
  exact radius 10/15/20/25/30 m x stub 6..30 m; all candidates.
- search_tram also has the **clockwise tram line** at 8/20/40/60 m (radius search; the sweep had
  CW only at 20 m).

Cheap smartness: early exit per job; jobs that would duplicate a build are left out; a
search_radius_split job without a rule costs no engine call; geometry that is degenerate (NaN,
an edge under 1 m, a zero tangent; dev overrides can force such layouts) is **never sent** to the
engine (logged as "probe: degenerate geometry, not sent"), since a NaN edge crashes the game.
At the start of every search run the probe asks the engine about the default combo at exactly 20
and 60 m; if both place at the same cost the `sqrb_dev_*` params never reached the updateFn and
the run stops (`ERROR dev override check ... ignores`).

### Steps for you
1. `make link` (both mods are already linked). Same map as the sweep: flat, empty, centre on
   land, year 2020 (the sweep's `year=2020` global).
2. Enable **Better Roundabouts** and **DEV Roundabouts Probe**. Probe settings:
   - Run the probe: **On**
   - Subset: **search_quick** first (about half a minute; checks the dev path end to end)
   - Start delay **15 s**, Combos per update **8** (more calls per frame; the runs are long),
     Position **0 / 0**, Proposal context **None**, Log placeable combos **On**
3. Load, pause, wait for `[SQRB_PROBE] END`. Check in stdout.txt that the line
   `INFO dev override check (...): overrides reach the updateFn` is there. Then
   `uv run tools/parse_probe.py --fresh` (the first search parse; later ones without `--fresh`).
4. Copy the log before the next game start overwrites it:
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_search_quick.log`
5. Then the full run: Subset **search** (about 8-12 min; or the parts in this order:
   search_splitter, search_magic, search_tram, search_radius). Reload the save (or start a new
   game) to run it, wait for END, copy stdout.txt to `plans/square_roundabouts/probe_search.log`,
   and `uv run tools/parse_probe.py` (no `--fresh`: rows accumulate, a re-run of the same job
   replaces its rows). Running the parts separately: parse after each.
6. Send me `plans/square_roundabouts/probe_search.md` (or just say it's done: the CSVs are in
   the repo folder).

## Phase 4b runs (next steps for you)
The tuning table now holds the engine data (PLAN.md "Phase 4b notes"): splitter rules for medium
and large arms (with radius floors), exact engine radii, Magic size floors. Two runs are left.
Same map and settings as before: flat, empty map, centre on land, year 2020; **Combos per update
8**, Start delay 15 s, Position 0 / 0, Proposal context None, Log placeable combos On.

### (a) search_radius_split: the radius splitter + medium/large arms need with the rules
1. `make link` (both mods are already linked; run it again if staging_area was reset).
2. Start TF3, load (or start) the flat test map. Enable **Better Roundabouts** and **DEV
   Roundabouts Probe**. Probe settings: Run the probe **On**, Subset **search_radius_split**, the
   settings above.
3. Load, pause, wait for `[SQRB_PROBE] END` (2,880 jobs, about 11,000-15,000 engine calls, about
   5-7 minutes). Check stdout.txt for `INFO dev override check (...): overrides reach the
   updateFn` and that the END line says `skipped=0` (a skipped job means no rule reached the probe:
   stop and tell me).
4. Copy the log before the next game start overwrites it:
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_search_radius_split.log`
5. `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_search_radius_split.log`
   (no `--fresh`: the rows join the earlier search rows).
6. `uv run tools/gen_roundabouts_tuning.py` (writes the table; the splitter patterns get exact
   radii, the provisional 60 m floors are replaced), then `make test MOD=mods/square_roundabouts`.
   Or just tell me it is done.

### (b) final `all` verification sweep (after (a) is baked in)
1. Same settings, Subset **all** (10,644 combos: magic, main_cw, main; about 5 minutes at ~40/s).
2. Load, pause, wait for `[SQRB_PROBE] END`.
3. `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_all_4b.log`
4. `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_all_4b.log --out-md plans/square_roundabouts/probe_results_4b.md --out-csv plans/square_roundabouts/probe_results_4b.csv`
   (separate files: `probe_results.csv` stays the Phase 3b sweep the verdict replay starts from).
5. `make test MOD=mods/square_roundabouts`: test_engine_verdicts lists every combo the final
   sweep rejected and that still ships as swept (gap category `final`). Expected: none, apart
   from the known gaps (nothing accepted up to 120 m).
6. Disable the probe in the mod list afterwards (never upload it).

### (c) 2-lane Magic: search_magic2 (the "Mini roundabout lanes" param)
The Magic Roundabout's **Mini roundabout lanes** param (`sqrb_magic_lanes`, 1 or 2) is the probe's
Magic `lanes` axis, appended last: replay keys are `g:size,arm,dir,island,lanes` (keys from
earlier runs have 4 values and mean 1 lane; every tool reads both). Every older subset stays at
1 lane. search_magic2 asks the engine, for every arm road and direction, about each of the 5
sizes exactly with 2-lane satellites (12 jobs, 60 engine calls). The generator writes the result
as the magic rows `"armType,direction,2"`; without one, `magic.sizeFloor` uses the 1-lane row.
1. `make link` (both mods linked; Better Roundabouts must be the version with the lanes param).
2. Start TF3, load (or start) the flat test map (same settings as above: flat, empty, centre on
   land, year 2020). Enable **Better Roundabouts** and **DEV Roundabouts Probe**. Probe settings:
   Run the probe **On**, Subset **search_magic2** (last in the list), Start delay 15 s, Combos per
   update 8, Position 0 / 0, Proposal context None, Log placeable combos On.
3. Load, pause, wait for `[SQRB_PROBE] END` (a few seconds). Check stdout.txt for
   `INFO dev override check (...): overrides reach the updateFn`.
4. Copy the log before the next game start overwrites it:
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_search_magic2.log`
5. `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_search_magic2.log`
   (no `--fresh`: the 12 jobs join the earlier search rows; `probe_search.md` "Magic: sizes"
   lists them with lanes 2).
6. `uv run tools/gen_roundabouts_tuning.py --dry-run | grep -A40 "magic = {"` to preview (stdout
   says `magic: N rows (12 for 2-lane satellites)`), then `uv run tools/gen_roundabouts_tuning.py`
   and `make test MOD=mods/square_roundabouts` (test_engine_verdicts replays the 2-lane jobs).
   Or just send me `probe_search_magic2.log` / tell me it is done.

### What I do with the output
1. Read `probe_search.md`: minimal accepted radius per pattern and how it compares to what ships
   (`shipR`), Magic sizes/spacing, the accepted splitter sets per arm road, tram stub lengths, and
   the offline-vs-engine table (how often the offline junction model is wrong each way).
2. `uv run tools/gen_roundabouts_tuning.py` writes
   `mods/square_roundabouts/content/infrastructure/street_construction/square_roundabouts_tuning.lua`
   (exact engine radii, Magic size floors, splitter rules with radius floors; `--dry-run` to
   preview; stdout lists the choices, provisional floors and gaps). Review the splitter choice
   for looks (scoring: `looks()` in the generator).
3. With a splitter rule baked, you run **search_radius_split** once (same settings) and I
   regenerate the table, so splitter + wide arms get their radius floors too (Phase 4b: rules
   baked; "Phase 4b runs" above).
4. Where the engine accepts smaller layouts than the offline model, or rejects ones it accepts,
   retune the offline rules (`geom.plan` thresholds, Magic sizes, tram stub, `TRAM_STUB`) so the
   geometry needs fewer floors; `tests/square_roundabouts/test_engine_verdicts.lua` then replays
   every engine verdict against the shipped geometry (it skips while the table is neutral).
5. A final `all` sweep confirms (expected: no failures except combos with no accepted layout);
   parsed into `probe_results_4b.*` ("Phase 4b runs" (b)).
6. Offline replay of every engine verdict (dev tool, ~17 min):
   `SQRB_REPLAY_OUT=/tmp/replay.csv uv run tests/run_tests.py -k "replay report" mods/square_roundabouts`
   writes one row per engine call with geom.plan's verdict, the Phase 3b and the engine-fitted
   test models (`model3b`, `model4b`) and the junction numbers, to refit `checks.ENGINE`.

## Phase 5e runs (Channelized Junction, hamburger, Roundabout Interchange)

### What they ask
Four entries now (`probe_grid.lua` `grid.ENTRIES`, replay key tag): `main` (`m:`), `magic` (`g:`),
`channel` (`c:`, Channelized Junction, axes in `.con.lua` order: layout, main, side, slips,
splitter, armlen, dir, island) and `interchange` (`x:`, Roundabout Interchange: layout, highway,
level, lanes, radius, cross, slip, armlen, dir, island, then **year**: a pseudo axis, not a menu
param, passed as `params.year` = 1969 (steel bridges) or 2020 (concrete); `ix.bridgeType`). The
main entry got Through the centre's 4th value (`lights` = Road + traffic lights) and a **through**
axis (Through road: same, town_s ... country_l), appended last like Magic's lanes: older 11-value
`m:` keys mean Same as arms (`parse_probe.py` `canon_key`, `verdicts.lua` `MAIN_ORDER`,
`gen_roundabouts_tuning.py` `key_indices`). Every Phase 3-4 subset is unchanged (centre limited
to none/road/tram, through = same).

| subset | combos / jobs | engine calls (max / expected) | runtime at ~20-40 calls/s |
|---|---|---|---|
| p5_channel | 968 combos: layout x main x side x slips x splitter x traffic side (864, islands None); Paved islands on 96 (main town s/l, country l x side town s, country m x near/all slips x splitter x side); arm length 40/60 m (8) | 968 / 968 | ~25-50 s |
| p5_hamburger | 720 combos: Road and Road + traffic lights x 5 through roads other than the arm road x 6 arm layouts x 1/2/4 lanes x slider 8/20 m, arms town small and town large (round, CCW, splitter off) | 720 / 720 | ~20-40 s |
| p5_interchange | 282 combos: layout x highway x level x lanes at the 15 m slider, default cross road (town medium), years 1969 + 2020 (108); cross road town large / country large (108); 120 m slip roads (54); left-hand traffic (6); island Grass and trees (6) | 282 / 282 | ~10-20 s |
| **p5_all** | 1,970 combos: p5_interchange, p5_hamburger, p5_channel | 1,970 / 1,970 | **~1-2 min** |
| p5_channel_search | 144 jobs: layout x main x side x splitter (near-side slips, RHT); grid of chSlipAngle {40, 50} x chCornerGap {7, 4, 1} x chSlipFree {4, 2} (12, shipped first), all tried | 1,728 / 1,728 | ~45-90 s |
| p5_interchange_search | 18 jobs: layout x highway x level (15 m, 2 lanes); grid ixClear {8, 6, 4} x ixGoreRun {30, 20} (two-bridge, 6), x ixGamma {35, 20, 50} (dumbbell, 18), x ixWaistGap {6, 3} (peanut, 36) | 360 / 360 | ~10-20 s |
| p5_hamburger_radius | 360 jobs: p5_hamburger's Road combos as radius searches (exact radius from the slider up to 120 m, first accepted) | 8,280 / ~500-1,500 | ~0.5-1.5 min |
| **p5_search** | 522 jobs: p5_interchange_search, p5_channel_search, p5_hamburger_radius | 10,368 / ~2,600-3,600 | **~2-4 min** |

Runtimes are estimates (Phase 4 runs: ~40 calls/s; the interchange builds bridges and more edges,
so assume it is slower). The PROGRESS lines give the real rate and an ETA.

**Dev overrides** (Phase 5e, read only when present, never in a `.con.lua`; `geom.DEV_KEYS`, read by
`ch.readParams` / `ix.readParams` via `geom.readDev`; `tests/square_roundabouts/test_dev.lua`):

| override | param | meaning (shipped value) |
|---|---|---|
| chSlipAngle | `sqrb_dev_ch_slip_angle` | channel: slip lane angle to the arms, degrees (40) |
| chCornerGap | `sqrb_dev_ch_corner_gap` | channel: slip lane centreline to the kerb corner, beyond 7 m (7) |
| chSlipFree | `sqrb_dev_ch_slip_free` | channel: free arm length before the slip lane's gore (4 m) |
| ixClear | `sqrb_dev_ix_clear` | interchange: plan gap highway kerb <-> non-bridge roads (8 m) |
| ixGamma | `sqrb_dev_ix_gamma` | interchange: dumbbell/peanut slip road angle off the ring normal, degrees (35) |
| ixGoreRun | `sqrb_dev_ix_gore_run` | interchange: shortest level gore along the highway (30 m) |
| ixWaistGap | `sqrb_dev_ix_waist_gap` | interchange: peanut, gap between the waist kerbs at the pinch (6 m) |

New search kind **grid** (`grid.candidates`): the cartesian product of a block's `values`
(`values.order` lists the override names, the first varies slowest), every candidate tried. The
Phase 5e results go into their own files (below); since Phase 5f the tuning generator reads them
(channel rows, through-road radius patterns; PHASE5.md "Phase 5f notes").

New log fields (R and T lines): `setback=main/side` (channel: slip node distances, m) and
`bridge=steel|concrete` (interchange, from the year the probe passed). `effR`/`forced` for the
interchange are its built radius / whether no radius fitted. START also names `channel=` and
`interchange=` (the resolved construction names; `-` = not found, e.g. an older Better
Roundabouts).

**Output files**: `tools/parse_probe.py` names them by subset, so a Phase 5e run never overwrites
the Phase 3-4 data the tuning generator and `test_engine_verdicts` read: the `p5_*` (and `smoke`)
sweeps write `plans/square_roundabouts/probe_<subset>.md` / `.csv`; the searches
`probe_<subset>.md`, `probe_<subset>_jobs.csv`, `probe_<subset>_trials.csv`. The old subsets keep
`probe_results.*` / `probe_search*`. The `--out-*` / `--search-*` / `--trials-csv` flags override.
New report sections: through road x arm layout / centre, channel main x side road per splitter and
slip lanes x traffic side, interchange layout x highway / level and "Bridge type by year" (pairs
that differ only in the year: equal costs on every pair = the engine replaced `params.year`), and
"Grid searches" (acceptance per candidate and per base combo).

### Steps for you
1. `make link` (both mods linked; Better Roundabouts must be revision 3: four menu entries).
2. Start TF3 and load the flat test map from the Phase 4 runs (flat, empty, centre on land, year
   2020, right-hand traffic). Enable **Better Roundabouts** and **DEV Roundabouts Probe**. Probe
   settings: Run the probe **On**, Subset **p5_all**, Start delay **15 s**, Combos per update **8**,
   Position **0 / 0**, Proposal context **None**, Log placeable combos **On**.
3. Load, pause, wait for `[SQRB_PROBE] END` (~1-2 min). Check the START line shows
   `channel=square_roundabouts::/...channel.con` and `interchange=...interchange.con` (not `-`).
4. Copy the log before the next game start overwrites it:
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p5_all.log`
5. Reload with Subset **p5_search** (same settings), wait for END (~2-4 min), check for
   `INFO dev override check (...): overrides reach the updateFn`, then
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p5_search.log`
6. Parse both (or just send me the two logs):
   `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5_all.log` and
   `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5_search.log`
   -> `probe_p5_all.md/.csv`, `probe_p5_search.md`, `probe_p5_search_jobs.csv`, `probe_p5_search_trials.csv`.
7. Optional, if `p5_all` showed failures only in one part: rerun that part alone (`p5_channel`,
   `p5_hamburger`, `p5_interchange`, or the searches `p5_channel_search`, `p5_hamburger_radius`,
   `p5_interchange_search`), copy the log as `probe_<subset>.log`, parse it the same way.
8. Disable the probe afterwards (never upload it).

The probe also holds a dev construction for TESTING.md 11.2 (not part of any subset): **"DEV
Probe: pre-1940 one-way (NOT FOR UPLOAD)"** in the street construction menu (all years) builds
base `entrance_old_one_way` / `entrance_new_one_way` edges as freed streets: a straight road, a
ring, or the ring with four `town_old_small` arms. Files:
`mods/square_roundabouts_probe/content/infrastructure/street_construction/sqrb_probe_old_one_way.*`
(test: `tests/square_roundabouts_probe/test_old_one_way.lua`). Use a throwaway save.

## Phase 5f runs (verification of the tuned geometry, searches for the gaps)

### What they ask
The Phase 5e results are baked in (PHASE5.md "Phase 5f notes"): `gen_roundabouts_tuning.py` now
reads `probe_p5_search_jobs.csv` (and `probe_p5f_search_jobs.csv` once it exists) next to
`probe_search.csv`, and `probe_p5_all.csv` / `probe_p5f_all.csv` as sweeps. Two subsets:

| subset | combos / jobs | engine calls | runtime at ~40-90 calls/s |
|---|---|---|---|
| **p5f_all** | 1,416 combos: Channelized Junction layout x main x side x splitter x slip lanes (near-side, all turns) x traffic side (576); two-bridge interchange with 4 lanes x highway x level x slider 15/40 m x cross road town medium / country large x slip road 120/140 m x year 1969/2020 (96); main entry 2:1 oval, 4 lanes, Y / 5 arms, splitter, town / country large arms, slider 40/45/60 m, centre none / road (24); the p5_hamburger sweep again (720) | 1,416 | **~30-60 s** |
| **p5f_search** | 87 jobs: the 81 channel combos nothing was accepted for (T: side road town large / country large, town medium without splitter; X: main road town medium / large / country large, or side road as for T), grid chSlipAngle {65, 50, 80} x chSlip {2 one-way small, 3 one-way medium, 1 one-way xsmall} (9, the shipped fallback first, all tried); two-bridge 4 lanes x highway x level, grid ixAlphaMax {40, 45, 35, 30} | 753 | **~15-40 s** |

What each checks: p5f_all = does the shipped geometry place now (channel: 40 deg where accepted,
50 deg rows, ch.FALLBACK where nothing was accepted; interchange: 4-lane two-bridge rings with
alpha <= 40 deg; 2:1 splitter ovals split along the ring normal; the 60 hamburger combos p5_all
rejected now build the radius p5_hamburger_radius accepted). p5f_search = which slip lane angle /
template the engine takes where nothing was accepted (next tuning pass: `channel` rows), and the
largest alpha it takes for a 4-lane two-bridge ring.

**New dev overrides** (`geom.DEV_KEYS`, `grid.DEV`; log fields `devChSlip`, `devIxAlphaMax`):

| override | param | meaning (shipped value) |
|---|---|---|
| chSlip | `sqrb_dev_ch_slip` | channel: slip lane template, 1 one-way xsmall, 2 one-way small, 3 one-way medium (tuning row, else 1) |
| ixAlphaMax | `sqrb_dev_ix_alpha_max` | interchange: two-bridge ring, largest slip node angle off the highway axis, degrees (60; 40 with 4 lanes) |

`chSlipAngle` now accepts 20-85 deg (was 20-70). Every p5f_search channel candidate sets both
`chSlipAngle` and `chSlip` (without `chSlip` the tuning row's template would apply).

### Steps for you
1. `make link`; TF3 with the flat test map as before (flat, empty, centre on land, year 2020,
   right-hand traffic); Better Roundabouts (revision 3, this build) + DEV Roundabouts Probe.
   Probe settings: Run the probe **On**, Subset **p5f_all**, Start delay **15 s**, Combos per
   update **8**, Position **0 / 0**, Proposal context **None**, Log placeable combos **On**.
2. Wait for `[SQRB_PROBE] END` (~30-60 s), then
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p5f_all.log`
3. Reload with Subset **p5f_search** (same settings), wait for END (~15-40 s) and the
   `dev override check ... reach the updateFn` line, then copy stdout.txt to
   `plans/square_roundabouts/probe_p5f_search.log`.
4. Parse (or send the logs): `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5f_all.log`
   and the same for `probe_p5f_search.log` -> `probe_p5f_all.md/.csv`, `probe_p5f_search.md`,
   `probe_p5f_search_jobs.csv`, `probe_p5f_search_trials.csv`. Then `uv run tools/gen_roundabouts_tuning.py`
   picks the channel results up (`channel` rows); `make test` replays both files
   (`test_engine_verdicts.lua`). The interchange's `ixAlphaMax` result is applied by hand
   (`ix.ALPHA_MAX_LANES[3]`).
5. Disable the probe afterwards.

## Phase 5g runs (verification of the 5g tuning pass)

### What it asks
Phase 5g (PHASE5.md "Phase 5g notes") baked p5f_search in: the 81 channel combos that shipped
ch.FALLBACK now build one-way xsmall slip lanes at 65 deg (52 combos) or 80 deg (29), and the
4-lane two-bridge ring keeps its slip nodes within 45 deg (was 40) of the highway, so its rings are
smaller (15 m slider: 30 / 45 / 50 m). p5f_search placed each of these once (near-side slip lanes,
right-hand traffic; the interchange at the 15 m slider, town medium cross road, 140 m slip roads,
2020); one subset checks the rest:

| subset | combos | runtime at ~80 combos/s |
|---|---|---|
| **p5g_verify** | 468: the 81 channel combos x slip lanes (near-side, all turns) x traffic side (324); two-bridge interchange with 4 lanes x highway x level x slider 15/40 m x cross road town medium / town large / country large x slip road 120/140 m x year 1969/2020 (144; every key p5_all and p5f_all swept it with) | **~6-10 s** (plus the 15 s start delay) |

### Steps for you
1. `make link`; TF3 with the flat test map as before (flat, empty, centre on land, year 2020,
   right-hand traffic); Better Roundabouts (revision 3, this build) + DEV Roundabouts Probe.
   Probe settings: Run the probe **On**, Subset **p5g_verify**, Start delay **15 s**, Combos per
   update **8**, Position **0 / 0**, Proposal context **None**, Log placeable combos **On**.
2. Wait for `[SQRB_PROBE] END`, then
   `cp ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt plans/square_roundabouts/probe_p5g_verify.log`
3. Parse: `uv run tools/parse_probe.py --stdout plans/square_roundabouts/probe_p5g_verify.log` ->
   `probe_p5g_verify.md/.csv`; `make test MOD=mods/square_roundabouts` replays it
   (`test_engine_verdicts.lua`: gap `interchange` should drop to 0; any refused combo is a problem
   to fix). Disable the probe afterwards.

## Log format
One line per event, all prefixed `[SQRB_PROBE]`:
- `INFO ...` / `ERROR ...`: setup notes (settings, resolved construction names, global params, fallbacks).
- `START subset= total= x= y= z= context= player= main= magic= geometry=`
- `R n= total= entry= <axes> ok= critical= nmsg= msgs="a|b" warnings="" infos="" coll= bld= added= cost= effR= effSize= forced= fork= a= b= rs= setback= bridge= edges= geomErr="" mode= upd="" err="" ms= key=`
  (`-` = not available; axes are labels such as `arm=town_l arms=6 splitter=on`; `key` replays the
  combo: `m:`, `g:`, `c:` or `x:` and the param indices in the axis order of `probe_grid.lua`
  (.con.lua order, appended axes last); `ms` is CPU time via os.clock)
- `T n= total= entry= <axes> kind= fixed="" cand= ncand= label="" devRadius= devMagicSize= ... devTramStub= devChSlipAngle= ... devIxWaistGap= ok= critical= nmsg= msgs="" coll= cost= effR= effSize= offline= forced= fork= rs= setback= bridge= edges= sane= geomErr="" mode= upd="" err="" ms= key=`
  one engine call of a search job (`dev*` = the candidate's overrides, `-` = not set;
  `offline` = the geometry's own plan accepted the exact layout)
- `S n= total= entry= <axes> kind= fixed="" first= ncand= tried= accepted= found= best="" dev*= acceptedList="a|b" rejected="a|b" skipped="" shipR= shipSize= id="" key=`
  one search job (`best` = first accepted candidate; `shipR`/`shipSize` = what ships today)
- `PROGRESS done= total= ok= fail= errors= seconds= perSecond= eta= steps= calls= found= none= skipped=` every 250 engine calls
- `END subset= done= total= ok= fail= errors= seconds= steps= calls= found= none= skipped= top="reason:count|..."`
  (`START` also has `maxCalls=`)

## Unverified (the first smoke run confirms)
1. **makeProposalData accepts a SimpleProposal on the GUI thread in build 40420.** Evidence is a
   community mod on build 40408. If it throws for the first 3 combos, the probe logs
   `ERROR makeProposalData keeps failing (...)` and switches to `mode=result_only` (updateFn only via
   getConstructionResult): that still catches Lua errors and nil results, not engine geometry rejections.
2. **errorState carries the reason for "Construction not possible".** It may only set
   `critical=true` with no message, or the GUI may compute that text itself. The parser groups
   `(critical, no message)` separately. If smoke shows a known-failing combo (6 arms + splitter +
   town_l) as `ok=true`, makeProposalData does not run the same checks as the builder; then try
   "Proposal context: Player" (checkTerrainAlignment, cleanupStreetGraph, gatherBuildings/Fields).
3. **The resource name** of the .con for `fileName` (first candidate expected to work, as the
   official mission mod uses `<modId>::/path.con`). `ERROR entry ...: no construction found` otherwise.
4. **getModParams index base and availability on the GUI thread** (1-based per dce.script.lua). Wrong
   values fall back to the defaults (smoke, On), visible in the `INFO DEV ONLY probe loaded:` line.
5. **getConstructionResult template index -1** (falls back to 0; the result says `ok (template 0)`).
6. **Cross-mod `ug_require` of the square_roundabouts geometry from a game script** (logged as
   `geometry=no` in START plus an ERROR; results are still valid, only effR/effSize are missing).
7. **`os.time` / `os.clock` in the GUI VM** (fallbacks: update count / no ms).
8. **guiUpdate cadence**: unknown; PROGRESS `steps` vs `seconds` shows it.
9. Whether the builder adds params our proposal lacks that matter to the engine (we add globals +
   seed). `EXTRA_PARAMS` in `probe_config.lua` is the place to try e.g. `{ height = 0 }`.

## Tooling notes
- `make validate MOD=mods/square_roundabouts_probe`: passes with two expected warnings (no
  `_metadata/0.png` cover: a dev mod gets none; `NOT_FOR_UPLOAD.txt` is upper case on purpose).
  `make validate` over all mods includes it and does not know it is dev-only. Not changed:
  validate_mod.py could turn a `NOT_FOR_UPLOAD.txt` marker into an error ("not for upload") so a
  pre-upload validate fails loudly; say if you want that.
- `make covers` skips it (no `branding/mods.js` entry), `make link` links it with every mod (no
  exclusion list). The Mod Hub's upload screen has no exclusion: it is on you not to publish it.
- `mod.json`: `severityAdd`/`severityRemove` None, `cosmetic` true, dependency on
  `square_roundabouts` (loadBefore).
