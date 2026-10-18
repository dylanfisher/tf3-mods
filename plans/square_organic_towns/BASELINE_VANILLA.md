# Organic Towns vs vanilla: baseline comparison

Dated 2026-10-13 (run 23:55-00:25Z, local 16:55-17:25). Session `.cache/logs/2026-10-13_2355_sqot.log.gz`.
Mod rev 1, dev mod rev 1, the same build in both runs. This is the first vanilla baseline. Later runs are compared
against these numbers (the rerun recipe is at the end).

## The two runs

The session holds three map loads. Split at each `Init game took` / `[SQOT] INIT` / `SAVE event=init`:

| | **Mod run** (log lines 1-6571) | (abandoned load, 6572-7312) | **Vanilla run** (7313-end) |
|---|---|---|---|
| Load | new map, `Init game took 31.6 s`, seed text `6zZXvhJg4n` | new map, mod on, no SIMGROW, reloaded | new map, `Init game took 52.6 s` (seed not logged) |
| `INIT` | `on=true actOn=new` | `on=true` | `on=false reason=param actOn=off` |
| Params | `act_on=2` (New towns only), `town_names=1` (Landscape names) | same | `act_on=1` (Off), `town_names=2` (Game names) |
| Other params (both) | `style=1` Automatic, `town_layout=2` Organic, `lookahead=2`, `debug_log=2` On, `test_grow=1` Off (param removed in rev 3), `start_angle=1` Automatic, `starting_town_size=1` Game size, `industry_streets=2` Game default | | |
| Map | EU name list, temperate, 16 towns, centres within +-7.4 km (same size class); profile `EU_ORGANIC` | | same name list, climate, 16 towns, same extent |
| SIMGROW start | `seed=1 limit=40 bias=true even=true medium=4 fast=12 buildings=2285` | | `seed=1 limit=40 ... medium=5 fast=11 buildings=2595`, dev `MAIN visible=true phase=off off=param` |
| SIMGROW stop | `steps=639 fills=157 rounds=10 roundBuilds=242 buildings=2285->22162 s=290 sPerYear=7.3` | | `steps=640 fills=160 rounds=0 buildings=2595->17543 s=223 sPerYear=5.6`, every round `why=mainOff` |
| Tour | 18 shots (16 towns + 2 Works) | | 16 shots |

**Caveat: the vanilla run is not the pure base game.** Organic Towns' preRunFn ran on both loads and wrote the EU
town street angle range (`[SQOT] ANGLE choice=auto region=EU angle=0/0->35`, log line 7168 for the vanilla load):
"Vanilla town street angles: Automatic" applies even with "Act on: Off". The base default is 0 deg
(`base/content/base/mod.script.tl:110-111`), which on Blank Slate gave a strict rectilinear grid (findings
towns.md "Probe C"). So this baseline is "the game's own growth at the mod's 35 deg EU angle". Both runs had the same
angle, so the difference measured here is Organic Towns' growth driver alone. The base game's 0 deg look was not measured: see
"Rerun" for a true-vanilla variant. `TOWNSIZE applied=false` and `INDSTREETS makeInitialStreets=true->true` in both
(no change).

The two maps differ, so towns are compared as distributions and by similar site (coast vs coast, hill vs hill).

## Metrics (16 towns each; median [quartiles] (min-max))

From the dev mod's `ALLTOWN` lines after the 40 years and `SIMGROW town` / `SIMGROW final`. In the mod run the two
Works towns (44 / 36 buildings) are excluded. A main town's measure includes its satellite hamlets (they belong to
the town): they push the mod's `r` and spread up a little.

| Metric | Vanilla | Organic Towns | Diff |
|---|---|---|---|
| Buildings at start (sum) | 160 [119-199] (63-309), 2595 | 152 [99-182] (63-239), 2285 | |
| Buildings after 40 y (sum) | 919 [806-1300] (522-3298), **17543** | 1279 [1161-1485] (748-2345), **22162** | +39 % per town |
| Building growth | x6.8 total; per town 6.6 [5.4-7.4] | x9.7 total; per town 9.5 [7.3-13.8] | +43 % |
| Persons (residents + jobs) start -> end | 10399 -> **82055 (x7.89)** | 8779 -> **70602 (x8.04)** | the same growth |
| Share of SIMGROW target reached | 0.975 (min 0.972) | 0.976 (min 0.967) | the same |
| Capacity per town (`capacity=`) | 4269 [3638-5883] (2363-16150) | 3877 [3295-5342] (2442-8395) | |
| Persons per building (`pb=`) | **4.56** [4.51-4.67] (4.27-4.90) | **3.01** [2.78-3.39] (2.52-3.96) | -34 % |
| Radius `r` (m, 90 % quantile of building distances) | 585 [555-664] (401-1228) | 696 [674-998] (510-1106) | +19 % |
| `r` / sqrt(buildings) | 17.8 [17.4-20.2] | 19.3 [18.6-21.8] | +8 % (looser) |
| Density `dens=` (buildings / ha in the r disc) | 10.1 [8.2-10.6] (7.0-11.9) | 8.6 [7.8-9.4] (3.3-10.7) | -15 % |
| Spread ratio (1 = full disc) | 1.19 [1.18-1.33] (1.11-1.68) | 1.28 [1.18-1.48] (1.09-1.66) | |
| Beyond 1.5 Req (% of buildings) | 2.5 [1-6] (0-16) | 4.5 [3-13] (0-20) | |
| Towns with ratio >= 1.4 / beyond >= 10 % / lobes >= 2 | 2 / 1 / 1 | 4 / 4 / 2 | |
| Street edges (sum) | 284 [224-396] (161-858), 5207 | 383 [311-486] (206-638), 6489 | |
| Edges per 100 buildings | 30.7 [30.0-31.1] | 28.3 [27.6-33.3] | the same |
| Edges per 1000 persons (sums) | **63** | **92** | +45 % |
| `orient` orth / radial / ring | 0.25 / 0.18 / 0.15 | 0.30 / 0.21 / 0.17 | slightly more aligned |
| Nearest gap to another town (m, d - r1 - r2) | 2438 [2290-2889] (1717-3747) | 2215 [1756-2625] (1414-3202) | none < 200 m in either |
| Sim run time for 40 y | 223 s (5.6 s / y) | 290 s (7.3 s / y) | +67 s = the 10 build rounds (69 s) |

Mod-run only (the main mod logs nothing in the vanilla run):

- **Empty streets** (last PLAN `emptyLen=` length / edges): 5437 m (3170-9341) per town, **23 % of the edges**
  (16-32 %), 4.0 m per building. Last CHECK: free lots 54 % (51-58 %) of all lots.
- **Who built the streets:** 1986 edges in 325 `BUILT` builds (head start + 10 build rounds) of ~5700 new edges
  (753 at START): the mod ~35 %, the game ~65 %.
- **Forest:** 86 `FOREST` reads; ALLTOWN `forest=` share 0.10-0.48 at the start, mode hug 12 / clear 4; PLAN
  `forestCut` (the mod's own new streets in forest) per-town mean 0.00-0.43; `FORESTLANE` 3 built.
- **Satellites** 14 seeded and built (`SATELLITE built`), 2 `noSite`, 1 refused for an industry zone; **Works** 2
  created (Haslemere Works 44 buildings, Chorleywood Works 36), **neither linked** (`event=link outcome=dropped
  why=notJoined` / `none why=crossing|obstacle`); **bridges** 2 planned (Windermere span 156 m, Haslemere 116 m), both
  refused at precheck (`Construction_Not_Possible`; `Collision` x8 with streets): **0 built**; **districts** none
  (`METRO on=false why=small|site`, every ALLTOWN `metro=-`); character towns 2 (Chipping Campden, Fleetwood, meadows
  3 each); upward doses `ups=` 0-1 per town; FRAME 59 built.
- **Per-frame costs** (`us=` of one slice): CHECK median 7.6 ms, p90 21, max 85; PLAN per slice median 5.5 ms, max
  21 (one PLAN up to 608 ms over 27 slices); FOREST max 57 ms; SATELLITE max 51; DIAGSUM max 86. No `WARN` / `ERROR`
  in either run.

## Findings per aspect

1. **Growth.** The same population growth (x8.0 vs x7.9, both 97.5 % of the SIMGROW target): towns reach the same
   *size in people*. But Organic Towns' towns hold it in **39 % more buildings** at 3.0 instead of 4.6 persons per
   building, on 45 % more street per resident. The game fills the extra frontage the mod lays with more small
   buildings instead of raising density (inferred). Vanilla's biggest town (Framlingham 3298 buildings, 16150
   persons) has no counterpart in the mod run: the mod's spread is narrower (748-2345).
2. **Form.**
   - *Radius:* +19 % median (696 vs 585 m), +8 % after scaling by sqrt(buildings): the mod's towns are slightly looser.
   - *Elongation / spread:* modestly higher (ratio 1.28 vs 1.19, beyond 4.5 vs 2.5 %, 4 vs 2 towns >= 1.4). Vanilla
     makes round blobs in open country (Wem, Henley-on-Thames, Chagford, Torpoint, Wigton) and elongates only where
     water bounds it (Nelson 1.49 on a river bank, Bungay 1.68 at a lake head). The mod's elongated towns: Kirkby
     Lonsdale 1.66 (ribbon lane + fingers), Skegness 1.58 (peninsula), Bexhill-on-Sea 1.56, Haslemere 1.48 (lake).
   - *Terrain:* vanilla at 35 deg already follows shores and river banks (Framlingham, Nelson, Erith, Harrogate) and
     stops at mountain slopes (Bromyard, Dawley). The mod adds a shore ribbon beyond the core (Ellesmere's separate
     shore strip, Haslemere wrapping both sides of its bay) and contour-linear hill towns (Coleshill), but at a
     glance waterside and hillside towns look alike in both runs.
   - *Compactness:* vanilla is denser (10.1 vs 8.6 buildings / ha). Close up its centres show rows of terraces and
     bigger blocks on concentric ring streets. The mod's centres are detached houses with tree-filled gardens.
   - *Green gaps / meadows:* both have small meadows inside. The mod's forest pockets inside town (Fleetwood, Coleshill,
     Chorleywood) and wedges are more frequent; vanilla Framlingham also keeps a central meadow.
3. **Forest.** No tree read in the vanilla run (the main mod is off). In the shots vanilla towns abut forest patches
   with no cleared ring around them, and forest pockets survive inside some (Wigton, Stanhope). The mod's towns look
   the same at the edge. The mod's forest rule shows mainly as forest pockets and edges kept inside the town (hug
   mode). Its `forestCut` covers only its own ~35 % of the streets. Judging the game's own forest clearing needs a tree
   read in the vanilla run (suggestion 3).
4. **Streets.**
   - *Empty streets / stubs:* the mod run has 23 % unhoused edges (no vanilla number). In the shots vanilla's empty streets
     are short curved dead-end "whiskers" all round the edge. The mod's are fewer but **long straight lanes with a
     T at the end**, highly visible (Chipping Campden W, Ampthill SE, Chorleywood NNW, Henley-in-Arden NE, Fleetwood
     E grid stubs, Swanscombe S).
   - *Street per building:* the same (0.28 vs 0.31 edges per building). Per resident, the mod has +45 %.
   - *Curvature / grid:* both organic and curved (same 35 deg angle). The mod's are slightly more aligned (orth 0.30 vs
     0.25) with straight ribbon lanes; vanilla's look concentric (ring + radial).
   - *Wide streets:* none visible in either at 1800 m (PLAN `hier=wide0` almost everywhere).
5. **Industry.** No vanilla town in these shots had an industry close enough to judge. The industries in view
   (Gainsborough's farm, Tottenham's and Wigton's) lie outside the towns. Mod: Henley-in-Arden's farm stays clear
   (zone 422 m) but a lane points at it. Kirkby Lonsdale's farm at the north tip has the town's streets reaching it
   (`zones=1:371`, `zoneHeld=4`). Haslemere's industry on the east shore has houses beside it. Inconclusive. The
   earlier finding still stands: the game's own growth surrounds a farm (towns.md, Budleigh Salterton).
6. **Towns touching.** Neither run. Nearest gaps 1.4-3.2 km (mod) vs 1.7-3.7 km (vanilla). The map generator sets
   the spacing. The mod's satellites at 0.55-1.2 km and Works at 0.8 km fill part of the gap, but no town merged.
7. **Bridges, satellites, Works, districts (mod only).** 14 satellites built (visible: Heywood's NE lobe, Swanscombe's
   S grid, Ellesmere's shore hamlet). 2 Works created, both unconnected to their parent. **0 bridges**, both refused.
   No districts. Vanilla, in contrast, has a **town-street bridge over the river at Gainsborough** with a small
   cluster on the far bank (`img_23`; whether it came from map generation or growth is unknown).
8. **Performance.** Vanilla's sim ran 223 s, the mod's 290 s (+30 %), the difference being exactly the build rounds
   (4.0-9.1 s each, the sim waits for them). Neither run logs frame times. The mod's single slices reach 50-86 ms
   (CHECK, FOREST, SATELLITE, DIAGSUM), visible hitches. Vanilla has no script cost. The post-sim stall before the tour
   is in both (first-shot `settleMs` 2.5 / 2.0 s mod vs 2.1 / 1.6 s vanilla).
9. **Visual verdict.** At a glance the difference is **noticeable in open-country towns, not at the waterside or on
   hills**. About half the mod towns look clearly un-vanilla (Kirkby Lonsdale, Heywood, Ampthill, Chorleywood,
   Henley-in-Arden, Swanscombe, Chipping Campden, High Wycombe's lobes). The rest (Ellesmere, Windermere, Coleshill,
   Fleetwood, Bexhill, Darley Dale) would pass for vanilla. Part of what marks a mod town is negative: long empty
   straight lanes and sparser houses.

## Shot pairs (files in `~/Library/Application Support/Steam/userdata/65263351/3493540/local/screenshots/`)

Mod tour: `2026-10-13_17-04-32_img_0.png` ... `17-05-21_img_17.png`, SHOT n = k is `img_(k-1)` (the primer wrote no
file). Vanilla tour: `2026-10-13_17-24-43_img_18.png` (the primer: an overview) ... `17-25-29_img_34.png`, SHOT
n = k is `img_(k+18)`. Downscaled copies: `/Users/dylanfisher/.claude/jobs/7da85430/tmp/cmp/` (`mod_*`, `van_*`,
`zoom_*`; scratch, not kept).

Mod: img_0 High Wycombe, 1 Haslemere, 2 Ellesmere, 3 Coleshill, 4 Skegness, 5 Chipping Campden, 6 Windermere,
7 Fleetwood, 8 Heywood, 9 Ampthill, 10 Kirkby Lonsdale, 11 Bexhill-on-Sea, 12 Darley Dale, 13 Chorleywood,
14 Swanscombe and Greenhithe, 15 Henley-in-Arden, 16 Haslemere Works, 17 Chorleywood Works.
Vanilla: img_19 Framlingham, 20 Tottenham, 21 Wigton, 22 Henley-on-Thames, 23 Gainsborough, 24 Dawley, 25 Wem,
26 Bromyard and Winslow, 27 Evesham, 28 Bungay, 29 Nelson, 30 Stanhope, 31 Chagford, 32 Torpoint, 33 Erith,
34 Harrogate.

| Site | Mod (`2026-10-13_...png`) | Vanilla (`2026-10-13_...png`) | Verdict |
|---|---|---|---|
| Open country | `17-05-00_img_10` Kirkby Lonsdale (ribbon lane, fingers, farm) | `17-25-02_img_25` Wem (round blob, whiskers) | **clearest difference** |
| Open country, mid size | `17-04-54_img_8` Heywood (arm + satellite lobe) | `17-24-53_img_22` Henley-on-Thames (round) | clear |
| Open country, compact | `17-04-51_img_7` Fleetwood (forest pockets, grid stubs) | `17-25-20_img_31` Chagford, `17-25-23_img_32` Torpoint | small; mod sparser |
| Hill + forest edge | `17-05-09_img_13` Chorleywood (straight lanes into forest), `17-04-57_img_9` Ampthill | `17-24-59_img_24` Dawley | visible (the lanes) |
| Mountain foot | `17-04-40_img_3` Coleshill | `17-25-05_img_26` Bromyard and Winslow | none: both stop at the slope |
| Lake shore | `17-04-35_img_1` Haslemere (both sides of the bay) | `17-25-17_img_30` Stanhope | small |
| Lake / sea shore, big | `17-04-37_img_2` Ellesmere | `17-24-46_img_19` Framlingham | **none: vanilla follows the coast as well** |
| River bank | `17-04-48_img_6` Windermere | `17-25-14_img_29` Nelson | none (Nelson is more elongated) |
| Coast / peninsula | `17-04-42_img_4` Skegness | `17-25-26_img_33` Erith | small |
| River crossing | (no mod bridge built) | `17-24-56_img_23` Gainsborough (town-street bridge) | vanilla better |
| Centre, close up | crop of `17-04-54_img_8` Heywood | crop of `17-24-53_img_22` Henley-on-Thames | vanilla denser, terraces |
| Empty lanes | `17-04-45_img_5` Chipping Campden (W), `17-05-15_img_15` Henley-in-Arden (NE, toward the farm) | short whiskers: `17-24-51_img_21` Wigton | vanilla better |

## Better, no difference, worse

**The mod clearly does better:**
- Open-country towns get a shape (ribbon lanes, fingers, lobes, satellites) instead of the round blob with a whisker
  fringe: spread 1.28 vs 1.19, 4 vs 2 towns elongated.
- Forest pockets and wedges kept inside towns. Shore ribbons that run on past the core.

**No visible difference:**
- Waterside towns (lake, sea, river) and mountain-foot towns: vanilla at 35 deg already follows shores and stops at
  slopes.
- Population growth and the gaps between towns. Street length per building.
- Curvature (both use the same angle range).

**Vanilla looks better:**
- Density and centres: 4.6 vs 3.0 persons per building, 10.1 vs 8.6 buildings / ha. Vanilla centres have terraces and
  blocks, the mod's stay detached houses.
- Empty streets: vanilla's empty stubs are short curved whiskers. The mod's are long straight empty lanes with
  T ends, the most visible artefact.
- River crossings: vanilla grew across a river (Gainsborough). The mod's bridges are all refused.
- Run time: +30 % sim time, single slices up to 86 ms.

## Rerun (to compare a later build against this baseline)

Since 2026-10-14 late the same-seed page is rebuilt by a script: `uv run plans/square_organic_towns/compare/build_compare.py
--a <session>:<load> --b <session>:<load>` (usage in its header and TESTING.md "Fresh run after the comparison round").


1. Mods: `square_organic_towns` + `square_organic_towns_dev` (make link). Quit TF3 fully after code changes.
2. **Mod map:** a NEW map, European, the same size as here (16 towns, centres within +-7.4 km), 1900. Organic
   Towns: Act on **New towns only**, Town and stop names **Landscape names**, Debug log **On**, the rest default.
   Wait for `HEAD done`, then OT Dev Simulate: Seed 1, Every town grows on, Tour on, screenshots on, **Quick: 40
   years**. Wait for `SIMGROW stop` and `TOUR done`.
3. **Vanilla map:** a NEW map, same settings. Organic Towns: Act on **Off**, Town and stop names **Game names**. For
   the same angle as here, leave "Vanilla town street angles" on Automatic. For the true base game also set it to
   **Game default** (then `[SQOT] ANGLE` must not say `0->35`): run both variants if the base look is in question.
   Same Simulate steps. Expect `INIT on=false reason=param` and SIMGROW rounds `why=mainOff`.
4. Split the log at each `Init game took` (one map per part). Per part: `grep 'SQOT_DEV\] \(ALLTOWN\|SIMGROW
   \(start\|stop\|final\|town\)\|SHOT\)'`. Medians as above: buildings, `pb=`, `r=`, `dens=`, `spread=`, `edges=`,
   `orient=`, persons and target from the last `SIMGROW town year=40` lines, nearest gap from ALLTOWN `x= y= r=`.
   Mod only: last PLAN `emptyLen=`, last CHECK `free= built=`, `BUILT edges=`, `us=` per tag.
5. Shots: pair `SHOT n=` with the `Screenshot: wrote` line just before it (the write is logged before the SHOT line;
   the primer may or may not write a file), or `uv run tools/ot_shots.py --log <part>`. Downscale with
   `sips -Z 1400 -s format jpeg`. Compare similar sites as in the table above.
6. Add the new numbers as a column to the metrics table (dated, with the session name) rather than a new doc.

## Same-seed comparison 2026-10-14 (seed U8Qxgisp4I, true vanilla)

Session `.cache/logs/2026-10-14_0119_sqot.log.gz` (one game session, two loads of the same seed). Files, shots and an
interactive page (side by side / slider, filters, arrow keys): `compare/2026-10-14_U8Qxgisp4I/` (`index.html`,
`data.json`, `mod/NN-<town>.jpg`, `vanilla/NN-<town>.jpg`; the same NN = the same town).

### Settings

| | **Mod run** (log lines 1-4814) | **True vanilla** (4815-end) |
|---|---|---|
| Load | 01:20:12Z, `Init game took 30.7 s`, seed text `U8Qxgisp4I` | 01:29:25Z, `Init game took 24.2 s`, same seed text |
| Organic Towns | `INIT on=true actOn=new`, `ANGLE ... angle=0/0->35`, `town_names=1` (Landscape: 16 towns + 14 industries renamed) | `PRERUN actOn=off writes=none angle=0`, `INIT on=false reason=param`, `start_angle=5`, `town_names=2`: **nothing written, base 0° angle** |
| SIMGROW | 01:21:33-01:24:56Z, `seed=1 limit=40 bias even medium=4 fast=12`, buildings 1702 -> 15665, **203 s** (5.1 s / y), 155 fills, 10 build rounds (160 builds) | 01:30:03-01:31:36Z, same start line, buildings 1320 -> 6547, **93 s** (2.3 s / y), 160 fills, 0 rounds |
| Tour | 26 shots (16 towns + 7 districts + 3 Works), no primer file | 16 shots + primer (`img_26`) |

Pairing: the same town entity ids 61028-61043 at the same positions in both runs (ALLTOWN `x= y=` equal); the mod's
`NAME old= new=` lines give the vanilla name. Mod / vanilla: 01 Ellesmere / Maryport, 02 Winchcombe / Settle,
03 Haslemere / Yarm, 04 Ellesmere Port / Chesham, 05 High Wycombe / Hemsworth, 06 Windermere / Bexley, 07 Darley Dale /
Westerham, 08 Stratford-upon-Avon / Beckenham, 09 Penkridge / Chertsey, 10 Henley-in-Arden / Leyburn, 11 Blackwater
and Hawley / Bradford-on-Avon, 12 Whitehill / Silsden, 13 Telscombe / Long Sutton, 14 Ringwood / Cinderford,
15 Heywood / Withernsea, 16 Tickhill / Ilminster. Shots: mod `2026-10-13_18-24-59_img_0` ... `18-26-11_img_25`
(SHOT n = k is `img_(k-1)`), vanilla `18-31-39_img_27` ... `18-32-22_img_42` (SHOT n = k is `img_(k+26)`); the
camera position and heading are the same per pair, so the slider overlays them exactly.

### The building gap (15665 vs 6547) and whether the comparison is fair

- Both runs reached their SIMGROW persons target: year 40 `cap=48820/49994` (98 %) vs `42429/42969` (99 %). At the
  start both had the same people (year 1 `cap=6316/6529` vs `6354/6529`).
- Almost all growth is the Fast fill (every 4th year): between fills buildings rise by ~20 a year in both runs. At the
  fill years vanilla stood at 95-99 % of target, the mod at 87-98 % (it lags more, not less). Before each fill both dip
  to 73-94 % alike. **Vanilla did not fail to keep up**; its sim was shorter because it had less to place (6547
  bigger buildings, fill years 5-8 s) and no build rounds (the mod's fill years 12-24 s, of which rounds 3-8 s).
- Decomposition: buildings x2.39 = persons x1.15 x persons per building 1 / 0.48 (**3.1 vs 6.5** persons per
  building over the map; per town median 2.93 vs 6.37). So ~85 % of the gap (in log terms) is building size, ~15 %
  is more people.
- The extra people are the mod's dose fill, by design (`ot_driver` `FILL_EXTRA` 0.15 per dose, `FILL_CAP` 1.3x
  base; set to 0 in NEXT_PHASE_BRIEF 39, `capsBoost=0`): 7 towns ended with initial capacities x1.14-1.30 (Windermere 661 -> 824, Darley Dale 484 -> 627, Telscombe
  485 -> 631; sum 6529 -> 7222), and target = initial x factor (and SIMGROW's experience grows with the size). Towns
  with no effective dose (Ellesmere, Winchcombe, High Wycombe, Heywood) end with the same people in both runs
  (within 0.5 %) and still have x1.4-2.9 the buildings.
- Head start: at SIMGROW start the mod already had 1702 buildings for the same people as vanilla's 1320 (+29 %).
  (Corrected 2026-10-14 late: not the HEAD rounds. Their `HEAD ... round=1` lines, measured before each town's first
  script street, show the same counts, and the head start built 151 edges in all: the map generator at the 35° angle made
  the towns with more, smaller buildings; findings towns.md.)
- **Verdict: fair for form, streets and people per building**; for town size in people the mod is +15 % by its own
  dose rule, so per-person ratios (street per person, persons / ha) are the honest size-independent comparison.

### Metrics (16 towns; median [quartiles] or sum; from ALLTOWN after year 40 and SIMGROW town lines)

| Metric | Organic Towns | True vanilla (0°) | Mod / vanilla |
|---|---|---|---|
| Buildings start / end (sum) | 1702 / **15665** | 1320 / **6547** | x1.29 / x2.39 |
| Buildings per town | 999 [672-1308] (352-1573) | 413 [288-501] (162-693) | x2.42 |
| Building growth per town | x9.25 [8.7-9.9] | x5.04 [4.2-5.6] | |
| Persons end (sum of SIMGROW persons) | 48709 | 41963 | x1.16 |
| Persons per building `pb` | **2.93** [2.71-3.45] | **6.37** [5.49-7.47] | x0.46 |
| Radius `r` (m) | 554 [446-709] | 399 [359-470] | x1.39 |
| `r` / sqrt(buildings) | 17.7 [16.5-20.5] | 20.9 [19.2-21.9] | x0.85 (more compact per building) |
| Buildings / ha `dens` | 10.2 [7.6-11.6] | 7.3 [6.6-8.6] | x1.40 |
| Persons / ha (r disc) | 29.4 [22.9-33.7] | 51.7 [37.9-56.5] | x0.57 |
| Spread ratio | 1.19 [1.08-1.30] (1.03-1.41) | 1.19 [1.13-1.23] (1.08-1.61) | the same |
| Beyond 1.5 Req (%) | 2.5 [0-6.5] (0-10) | 2.0 [1-2] (0-7) | |
| Towns spread >= 1.3 | 4 (Windermere 1.38, Stratford 1.32, Whitehill 1.41, Ringwood 1.32) | 1 (Chertsey 1.61, a stray cluster up the hill) | |
| Street edges (sum) | 5021 | 1988 | x2.53 |
| Street length (sum) | 348 km | 162 km | x2.15 |
| Street m per person | 7.6 [6.0-8.8] | 3.8 [3.5-4.3] | x2.0 |
| Street m per building | 22.6 | 25.2 | x0.90 |
| Empty street length (sum) / share of length | 79.8 km / 22.6 % [17.7-28.6] | 31.1 km / 19.7 % [15.4-23.3] | |
| Empty edges (% of edges) | 24.2 [18.7-31.6] | 20.0 [15.7-24.1] | |
| Dead ends (sum) / per km street | 507 / 1.64 | 252 / 1.59 | the same per km |
| Free lots (% of lots) | 57.8 [55.3-61.7] | 51.9 [49.3-55.9] | |
| `orient` orth / radial / ring (median) | 0.27 / 0.21 / 0.18 | **0.74** / 0.22 / 0.14 | grid vs organic |
| Sim time for 40 y | 203 s (5.1 s / y) | 93 s (2.3 s / y) | x2.2 |

Mod only: satellites 8 built (Darley Dale, Windermere, Winchcombe, Henley-in-Arden, Stratford, Heywood, Ringwood,
Ellesmere), 4 `noSite`, 2 dropped; districts 9 created (Winchcombe Heath, Penkridge Sands, Ringwood Bay,
Tickhill-on-Sea, Windermere Sands, High Heywood, Ellesmere Port-on-Sea before the tour; Ellesmere Heath and Upper High
Wycombe during it), 2 linked (Penkridge Sands, High Heywood); Works 3 created and linked (Haslemere, Ringwood,
Heywood); bridges 1 built (Haslemere, stone, span 128 m), 1 refused (Windermere, `Construction_Not_Possible`);
coastal picks 2 (Whitehill, Penkridge); character towns Darley Dale, Telscombe, Blackwater, Whitehill; forest share
(FOREST reads, first -> last) 0.13-0.33 -> 0.13-0.26; the mod built 1103 of 5021 edges (22 %) in 198 builds. The 10
extra towns hold 669 buildings outside the 16-town numbers. Industries enclosed: not logged in vanilla (`CHECK
ind=` is mod only); in the shots no industry sits inside a town in either run (Tickhill / Ilminster's farm is across
the river in both).

### Findings per aspect

1. **Street pattern is the whole visual story.** True vanilla at 0° builds a rectilinear grid in all 16 towns
   (`orient` orth 0.74; diamond grids where the country road enters diagonally: Westerham, Leyburn, Withernsea), bent
   only along coasts (Beckenham, Chertsey). Every mod town is curved and organic (orth 0.27). Unlike the 35° baseline
   above, where half the towns looked alike, here all 16 pairs differ at a glance. Most of that is the mod's EU 35°
   angle range; the growth driver adds the shape on top.
2. **Size in people: the same where no dose ran**, +15 % overall by the dose rule (above).
3. **Buildings: x2.4, small houses.** 3.1 vs 6.5 persons per building; vanilla's grid blocks are filled with
   terraces and bigger buildings (persons / ha 52 vs 29), the mod's are detached houses with gardens. In buildings / ha
   the mod is denser (10.2 vs 7.3) because its buildings are small.
4. **Streets: double per person.** 7.6 vs 3.8 m of street per person, 2.5x the edges. Empty share only a little higher
   (22.6 vs 19.7 % of length): **vanilla also leaves a fifth of its street length unhoused** (first vanilla number:
   the earlier baseline had none). Dead ends per km street the same (1.6). The mod's empties are still the visible
   long straight lanes with a T end (Ellesmere S, Winchcombe W, Windermere SW, Henley-in-Arden S parallel to the
   country road, Stratford S into the forest).
5. **Form.** Median spread the same (1.19); the mod has 4 towns >= 1.3, all water-led (bay, peninsula, shore
   ribbon); vanilla's one (Chertsey) is a stray cluster. Per building the mod is more compact (r / sqrt(B) 17.7 vs 20.9),
   but the towns are 39 % wider. Waterside: both follow shores; the mod wraps bays (Windermere, Ringwood) and fills the
   peninsula tip (Stratford) where vanilla leaves meadow. Hills: the mod climbs contours (Tickhill, Penkridge),
   vanilla stays on the flat.
6. **Forest.** No tree read in vanilla. In the shots both stop at the same forest patches; neither clears a ring.
   The mod pushes a few lanes into forest edges (Winchcombe E, Stratford S); its FOREST share fell 0.00-0.09 per town.
7. **Bridges / districts / Works.** One mod bridge built (Haslemere's lane over the river SE), visible. Districts and
   Works read as part of the parent town in the shots (they touch it), not as separate places.
8. **Performance.** 203 vs 93 s of sim time: the mod's fills place 2.4x the buildings, plus the build rounds.

### Pairs (verdict per town; all 16 differ in street pattern)

| NN | Mod | Vanilla | Verdict | |
|---|---|---|---|---|
| 01 | Ellesmere | Maryport | clear | shore grid vs curves, same footprint; empty lane S (satellite link) |
| 02 | Winchcombe | Settle | **clear** | square grid vs round organic town, 2.6x buildings, empty lane W |
| 03 | Haslemere | Yarm | clear | grid cross vs organic + lane and stone bridge over the river |
| 04 | Ellesmere Port | Chesham | similar footprint | small compact towns; grid stubs on the mod's S fringe |
| 05 | High Wycombe | Hemsworth | clear | blocks vs ring-and-radial with an inner meadow |
| 06 | Windermere | Bexley | **clear** | grid on the bay vs a town wrapping the bay and the coast E, 2.8x |
| 07 | Darley Dale | Westerham | **clear** | diamond grid vs organic star with fingers |
| 08 | Stratford-upon-Avon | Beckenham | similar footprint | both follow the peninsula; the mod fills the W tip |
| 09 | Penkridge | Chertsey | similar footprint | both on the shore flat; the mod climbs N |
| 10 | Henley-in-Arden | Leyburn | clear | diamond grid vs round organic town, empty lane S |
| 11 | Blackwater and Hawley | Bradford-on-Avon | similar footprint | small coastal towns, the mod with a coast lane |
| 12 | Whitehill | Silsden | clear | grid at the bay head vs shore ribbon with loops (coastal) |
| 13 | Telscombe | Long Sutton | clear | grid vs dense organic town, 3.3x |
| 14 | Ringwood | Cinderford | clear | grid vs organic town to the lake shore (Ringwood Bay) |
| 15 | Heywood | Withernsea | clear | diamond grid vs organic town + Works and hamlet SE |
| 16 | Tickhill | Ilminster | clear | grid vs contour streets up the hill + river-bank strip |

### Better, the same, worse

- **Mod better:** organic, terrain-led street pattern in every town (vs a grid at 0°); shore wrapping, contour hill
  streets, peninsula fill; one working river bridge; satellites / districts / Works give places a fringe.
- **The same:** spread (median 1.19), dead ends per km, the empty-street share within 3 points, forest edges kept.
- **Vanilla better:** density and building size (6.4 vs 2.9 persons per building, 52 vs 29 persons / ha), half the
  street per person, no long straight empty lanes, 2.2x faster sim.

### Caveats

- The mod's +15 % people is its dose rule; compare per person. The 10 extra towns are outside SIMGROW (and so got no
  simulated growth beyond what the game gave them).
- The visual gap mixes two levers: the mod's EU angle (0 -> 35°) and its growth driver. The 2026-10-13 baseline above
  isolates the driver at 35°; this one is the user-facing difference against the true base game.
- One seed, one SIMGROW seed; Fast fill (forced) does almost all of the growth in both runs, not the game's natural pace.
- The 2 late districts (Ellesmere Heath, Upper High Wycombe) were created during the tour: not in ALLTOWN, not shot.
- `DISTRICT ... event=created` lines name the wrong district when several creations are in flight (Winchcombe's
  "created" reports 128852 Penkridge Sands; Windermere's, Ringwood's and Tickhill's report 147514 Heywood Works), and the
  following link step then fails `why=far`: 4 of the 7 pre-tour districts stayed unlinked for that reason
  (Ellesmere Port-on-Sea, created in year ~37, logged no link attempt). A driver bug, see the next-phase note in
  TESTING.md.

## Density-round run 2026-10-14 0302 (seed U8Qxgisp4I, third run on the comparison seed)

Session `.cache/logs/2026-10-14_0302_sqot-sqrl.log.gz`, **load 2** (load 1 is an earlier map of the session). Build:
NEXT_PHASE_BRIEF 39 (frontage brake `freeK x pbK`, level weights `LEVELS`, no capacity boost, curved satellite lanes).
Page: `compare/2026-10-14_U8Qxgisp4I/index.html` now holds all three runs ("Mod 0119 (before density round)", "Vanilla
0119 (true vanilla)", "Mod 0302 (density round)"; pick any two as A / B for side by side or the slider, or "All runs";
shots `mod-0302/NN-<town>.jpg`). Rebuilt with `build_compare.py --add 2026-10-14_0302:2 --label ... --dir mod-0302`.

### Settings

- Load 03:06:56Z, `Init game took 23.5 s`, seed text `U8Qxgisp4I`, `ANGLE ... angle=0/0->35`, `INIT on=true actOn=new`,
  INIT `capsBoost=0`; the 0119 mod run's parameters (Landscape names, Satellite towns On).
- SIMGROW 03:07:43-03:10:38Z, the same start line as 0119 (`seed=1 limit=40 bias even medium=4 fast=12`); stop
  `rounds=10 roundBuilds=17 buildings=1701->7939 s=175 sPerYear=4.4`; year 40 `cap=41954/42969(98%)`.
- Tour 03:10:41-03:11:24Z, 16 shots `2026-10-13_20-10-41_img_0` ... `20-11-24_img_15` (local time), SHOT n = k is
  `img_(k-1)`; no district or Works, so no extra shots.
- Pairing: town ids 61028-61043 at the same positions and with the same Landscape names as 0119 (ALLTOWN `x= y=`); the
  tour cameras match 0119's except Stratford-upon-Avon (n=1, `fallback=true`, camera 411 m north) and Telscombe in the
  0119 mod run (2030 m instead of 1800): the slider is exact for the other 14.

### Three-way metrics (16 towns; median [quartiles] or sum)

| Metric | Mod 0119 | Mod 0302 | Vanilla 0119 |
|---|---|---|---|
| Buildings start / end (sum) | 1702 / 15665 | 1701 / **7939** | 1320 / 6547 |
| Buildings per town | 999 [693-1277] | 455 [249-711] | 413 [297-494] |
| Persons end (sum) | 48709 | **41963** | 41963 |
| Persons per building `pb` | 2.94 [2.73-3.37] | **6.33** [5.54-6.71] | 6.37 [5.62-7.45] |
| Free lots (%) | 57.8 | 59.6 [56.3-62.2] | 51.9 |
| Street length (km, sum) / per person (m) | 348 / 7.58 | 186 / 3.99 | 162 / 3.78 |
| Empty street (km, sum) / share of length | 79.8 / 22.6 % | 42.2 / 22.6 % | 31.1 / 19.7 % |
| Radius r (m) | 554 [455-676] | 380 [279-463] | 399 [363-464] |
| Persons / ha (r disc) | 29.4 | **63.5** | 51.7 |
| Spread | 1.19 [1.09-1.28] | **1.13** [1.08-1.17] | 1.20 [1.14-1.23] |
| Towns with spread >= 1.3 / beyond 1.5 Req (%) | 4 / 2.5 | 1 (Penkridge 1.39) / 0.0 | 1 / 2.0 |
| Grid share (orient orth) | 0.27 | 0.31 | 0.74 |
| Mod-built share of the edges | 24 % (1183 edges: head 151 + demand 1032, 198 builds) | **11 %** (288: head 166 + demand 122, 55 builds) | - |
| CHECK outcomes | demand 332, open 116, ahead 69 | **free 235**, demand 44 | - |
| Satellites / districts / Works | 8 / 9 / 3 | **3 / 0 / 0** | - |
| Bridges built / coastal picks | 1 / 2 | 0 / 2 | - |
| Level weights set / cleared | - | 16 / 4 (the clears after the tour) | - |
| Residential levels 1/2/3/4 (actual, median) | (not logged) | 24/76/0/0 | (not logged) |
| Sim time | 203 s | 175 s | 93 s |

Per town (buildings 0119 / 0302 / vanilla; pb; mod-built share of edges 0119 / 0302): the four towns the mod still
built in (Stratford-upon-Avon 1342 / 1033 / 693, pb 3.81, 20 %; Penkridge 1054 / 877 / 504, 3.06, 17 %; Telscombe
1573 / 770 / 483, 4.52, 22 %; Winchcombe 1262 / 821 / 477, 4.21, 10 %) stayed big and sparse; the other twelve came out
at vanilla's size and density (Ellesmere 703 / 466 / 490, pb 6.26 vs 6.23; Ellesmere Port 352 / 119 / 162 with 0 mod
edges; Tickhill 751 / 237 / 301, 2 %). Full table: the page's data.json.

### Findings

1. **The variation is lower, and the brake is why.** The mod built almost nothing after the head start: 122 demand
   edges in 20 builds against 1032 in 170 (the head start was the same, 166 vs 151 edges). 235 of 279 CHECKs answered
   `why=free` (`freeK=0.12`, the floor, at 60-70 % free lots, and `pbK` 0.5-0.67 even at vanilla density: it counted
   persons per **built lot**, and a building spans 2-3 lots). So the game grew the towns from their head-start seeds:
   compact and round (spread 1.13, nothing beyond 1.5 Req, one town >= 1.3 against four), denser in the centre (63.5
   persons / ha against 29.4, r 380 against 554 m), still not a grid (orth 0.31: the 35° angle and the head start).
   That is the user's "less variation ... more buildings in the centre".
2. **Density reached vanilla's** (6.33 vs 6.37 persons per building, 3.99 vs 3.78 m of street per person) with exactly
   vanilla's people (41963 both: no capacity boost). Free lots stayed at 59.6 %: the game's own towns at the 35° angle
   keep ~60 % free (Ellesmere Port 76 %, Blackwater 69 % with 0-5 % mod streets), so FREE_AIM 0.5 (vanilla's 0° grid)
   could never be met.
3. **LEVELS did not make buildings bigger.** All 16 towns got weights at 150-210 buildings in their first years (k 0.25-
   0.75); actual level 3-4 capacity stayed **0 %** in every town although the weighted target asked up to 57 %: the
   game has level 3 town buildings only from 1950 and level 4 from 1990 (era folders, findings towns.md), so before 1950
   the weights can only tilt level 1 -> 2 (level 2 share 65-82 %, no control run to compare). The density came from the
   brake (the game filling its own lots), not from LEVELS. The 4 clears (pb >= 5.5) came after the tour. Unexplained:
   the four biggest towns read custom weights like `0.0327/0.0846/0/0` at the end, not the ones the mod sent.
4. **Only 3 satellites, 0 districts, 0 Works: the brake, then the size gates; not the quotas.** Every satellite /
   Works / district decision runs at a **demand build**, and there were 20 (against 170); 5 towns reached a satellite
   decision (seeded Winchcombe and Stratford-upon-Avon, the Penkridge hamlet; Telscombe and High Wycombe `rare`), 4
   reached a district decision (`forest` 2, `noSite`, `character`), 4 a Works decision (`rare` 3, `character`). The
   gates count buildings (district / Works 300, satellite 250), and a vanilla-dense town has half the buildings for the
   same people: 5 of 16 towns stayed under 300 buildings all 40 years. The quotas (districts 4, Works 2) never bound.
5. **Not worse:** the empty share of street length the same as 0119 (22.6 %), the straight-run guard cut 2 edges, no
   long straight lanes in the shots; the curved satellite lanes (Winchcombe, Stratford) look like country lanes.

### Verdict

The density round over-corrected: it made the mod's towns vanilla towns with an organic seed. The retune (PLAN.md 6.3
"Round after the 0302 run", NEXT_PHASE_BRIEF 40) keeps the young town's branching (no brake below ~1800 persons), phases
the brake and the level weights in up to ~3600 persons, fixes the per-lot pbK, and gives satellites, districts and
Works their own turns and a size in persons.

## Retune run 2026-10-14 0502 (seed Z2tNDhy0Ht, not the comparison seed)

Session `.cache/logs/2026-10-14_0502_sqot.log.gz`, load 1 (05:14:56Z, `Init game took 31.0 s`). Build: NEXT_PHASE_BRIEF 40
(maturity retune) + 41 (Quick at pace 0, early fills, inflight 24). The map was made with seed text **Z2tNDhy0Ht**, not
`U8Qxgisp4I`: no town pairs with the 0119 / 0302 runs, so only map-level medians compare (and this map is bigger: 2552
start buildings against 1701, a year-40 SIMGROW target of 100272 persons against 42969). Page (single run):
`compare/2026-10-14_Z2tNDhy0Ht/index.html` (gallery of the 16 towns + the 7 created ones, per-town metrics), built with the
new `build_compare.py --single 2026-10-14_0502_sqot:1 --shot-px 1600 --shot-q 50`. Shots `2026-10-13_22-20-01_img_0` ...
`22-21-05_img_22` (local time; SHOT n = k is `img_(k-1)`). No crash, 0 `SQOT ERROR/WARN`; the `Error` lines are mod.io
(`[File] GetMediaInternal` x21, one `[Http] 500`), the PDX SDK and three base-game GUI tracebacks
(`selector_react_util.tl(103)`, "Ignoring Set() on expired ReactRefWrap"): none are the mod's.

### Speed (Quick 40 years: 231 s, expected 95-110 s)

- 30 quiet years 21.8 s (0.5-1.3 s each, rising with town size) + 10 fill years 209.6 s. In the fill years: fillS 197.8
  s, roundS 181.1 s (overlapping: fillEarly 133 of 142 fills), sizesS 6.9 s, frames 35. Two rounds hit `why=time`
  (years 8 and 32).
- The fill forced ~1640-2370 buildings per fill year at 63-104 (median ~90) buildings / s; 18170 buildings in all (0302:
  6238, 0119: 13963). Per 1000 buildings added: **12.7 s** (0119 14.5 s, 0302 28 s). So the 95-110 s estimate held only
  for 0302's brake-sized growth; this run is no slower per building, it had 3x the buildings to place.
- Builds inside the rounds took **1.6 s median, p90 7.5 s** (0119 / 0302: 0.34 s / 0.36 s): they share the frames with
  the early fill. A round is a per-town serial chain (build -> dose fill -> CHECK -> build, ~2-3 s a step; Ellesmere
  6/6 in four rounds), so roundS 15-21 s against 0119's 3-8 s; hidden under the fill, which is longer.
- Year 8 (22.7 s, `why=time`): one batch of 4 builds took 12.8 s while the Bexhill-on-Sea_End district was being
  created (6.6 s) and two `FILL kind=upward ... timeouts=3 concurrent=true` timed out; Bexhill-on-Sea and Chipping
  Campden then stalled (`SIMGROW stall why=off`) and were reactivated.
- The run started 71 s after the load, before `HEAD done`: 6 towns' head round 1 ran between the sim's years (1 inside a
  round window), rounds 2-3 of all towns after the stop, 8 head builds during the tour (High Wycombe and Kirkby Lonsdale
  after their shots).

### Retune metrics (16 towns; median [quartiles]; the earlier runs on U8Qxgisp4I, map level only)

| Metric | Mod 0119 | Mod 0302 | Mod 0502 (this run) |
|---|---|---|---|
| Buildings start / end (sum) | 1702 / 15665 | 1701 / 7939 | 2552 / 20722 |
| Persons per building `pb` | 2.94 [2.73-3.37] | 6.33 [5.54-6.71] | **3.08** [2.84-3.33] |
| Free lots (%) | 57.8 | 59.6 | 55.5 [52.8-58.8] |
| Spread / towns >= 1.3 | 1.19 / 4 | 1.12 / 1 | **1.24** [1.19-1.32] / **5** |
| Persons / ha (r disc) | 29.4 | 63.5 | 25.6 |
| Street m per person | 7.58 | 3.99 | 7.06 |
| Empty share of street length | 22.6 % | 22.6 % | 22.9 % |
| Mod-built share of the edges | 24 % | 11 % | **22 %** (head 116 + demand 1288 edges; 24 + 192 builds) |
| CHECK outcomes | demand 332, open 116, ahead 69 | free 235, demand 44 | demand 340, ahead 34, open 32, **free 0** |
| Round builds / demand builds in years 1-20 | 160 / - | 17 / - | 189 / 116 |
| Satellites / districts / Works | 8 / 9 / 3 | 3 / 0 / 0 | 10 seeds (+2 grow builds) / 5 / 2 |
| Level weights set | - | 16 | **0** |
| Residential level 2 share (capacity) | - | 76 % | 28 % [11-39] |
| Bridges built / coastal picks | 1 / 2 | 0 / 2 | 3 (1 failed) / 2 |

### Findings

1. **Young towns branch out again (worked).** All 226 CHECKs under 1800 persons read `mat=0.00 demK=1.00`; no
   `why=free` at all; 116 demand builds in the first 20 simulated years (aim >= 100); the mod's share of the edges back at
   0119's level. The towns read like 0119's: organic, branching, with arms and shore wraps.
2. **Grown towns did not build up (did not work).** Maturity phased in as designed (mat 0.5 at 2700-3500 persons on 9
   towns, 1.0 on 8 by the end; demK down to 0.19-0.70), but the density stayed at 0119's: pb 3.08, only Chipping
   Campden (pb 5.27) built up. Three reasons: (a) **LEVELS never ran**: `skip=young` while young, then `skip=player` on all 8
   grown towns, because every original town carries custom level weights (ALLTOWN `lvl ... c:0.26/0.11/0/0`) that the
   mod never sent (`ours=0`); the mod-created towns read `c:-`. The engine (or the sim's fills) sets them; levelDecide
   treats any non-nil `custom` as the player's. (b) The `why=free` hold never fired: in `ot_assess.needsRoom` it applies
   only when the demand is under DEMAND_MIN_EDGES, and the grown towns always had demand (fast SIMGROW growth); their
   free lots (49-68 %) were mostly under the 0.60 hold line anyway. (c) demK only halves the demand (freeK 0.55-0.90,
   pbK 0.6-1.0 at the end), so the grown towns kept getting streets (19-41 `why=demand` CHECKs each).
3. **Satellites, districts and Works are back.** 10 seeds (Burgess Hill and Bexhill-on-Sea `hamletFallback`, Henley-in-
   Arden at a crossroads, 7 `seeded`) + 2 grow builds. Districts: Chipping Sands, Bexhill-on-Sea End, Windermere Green,
   Ellesmere Cross, Birchwood Bay (5 suffixes, but all `kind=shore`: the only kind offered on this lake map); Works:
   Kirkby Lonsdale Quarry, Heywood Sawmills. Links: 4 of 5 districts and both Works linked (388-1059 m); Chipping
   Sands `why=back` (its parent grew into it; its shot shows no separate place, nor does Bexhill-on-Sea End's). Forest
   gate held (forest 0.03-0.16); identity `how=name+pos` 7 / 7, 7 distinct ids. Not founded: district forest 6,
   noSite 2, rare 3, character 2; Works rare 11, character 2 (`small` gone).
4. **0 offshoot turns, as designed:** a turn runs only for a town whose CHECK needs no streets (`not m.needs`), and every
   CHECK here needed some; all decisions ran at demand builds. No `OFFSHOOT` line at all (no hold either).
5. **Stops:** none on the map (`STATIONS stations=0` throughout): nothing to check. **Bridges** 3 built (Windermere 140
   m, High Wycombe 144 m, Budleigh Salterton 156 m; Windermere's first try 112 m failed with no message); **coastal**
   Bexhill-on-Sea 0.77, High Wycombe 0.72; **lead lanes** 3 built (Skegness, Tickhill ribbons, Haslemere hamlet), 13
   `rare`; **forest lanes** 30 checks (wooded 50, joined 19, line 12, tip 11, short 7, freed / marked 0), `forestHeld`
   in 95 PLAN lines.
6. **Shots.** Best: Bexhill-on-Sea (wraps the bay, satellite across the water), Windermere (river and lake, bridge,
   Windermere Green on the peninsula), Chipping Campden (the one dense grown town, between lake and river), Birchwood
   with Birchwood Bay, Darley Dale around its lake. Weakest: Skegness, Haslemere, Budleigh Salterton and Henley-in-Arden
   (tangled meshes with empty loops at the edge; Haslemere 48 % and Henley 46 % mod edges). Odd: empty satellite
   skeletons (Ellesmere Port's "H" 800 m west, Henley-in-Arden's crossroads one), High Wycombe's bridge ending at an
   empty cross on the far bank, Budleigh Salterton's straight bridge lane north.

### Next

- LEVELS: tell the engine's own custom weights from a player's (remember `ours`, or compare with the defaults / the
  values at the first read on a new map), and probe when `custom` appears (per SIMGROW chunk: `levelInfo.custom`).
- Grown towns: a real hold for mature towns (e.g. FREE_AIM by maturity, or demK down to ~0.2 at mat 1) so they fill
  their lots before new streets; re-check pb on the comparison seed.
- Sim speed: estimate Quick as ~0.7 s x 30 + buildings added / 90 (~225 s on this map); skip dose / upward fills during
  SIMGROW rounds, at most 3 builds per town per round, and gate Quick on `HEAD done` (or hold HEAD for the run).
- Rerun on `U8Qxgisp4I` to put this build on the three-run page (`build_compare.py --add`).

## Seed a run 2026-10-14 0613 (seed text `a`, generated names, not the comparison seed)

Session `.cache/logs/2026-10-14_0613_sqot.log.gz`, load 1 (06:15:41Z, `Init game took 28.5 s`). Same build as 0502
(NEXT_PHASE_BRIEF 40-43: maturity retune, Quick at pace 0, generated names, deep forest towns). Settings: Act on New
towns only, Town and stop names **Generated names**, Satellite towns On, angle Automatic (`ANGLE ... 0/0->35`), Debug
log On. A new map with seed text **`a`**, Europe list, 1900; no vanilla run on it yet, so only map-level medians compare
with 0502 (`Z2tNDhy0Ht`). This map is smaller: 2027 start buildings (0502: 2552), year-40 target 45603 persons
(100272). Page (single run): `compare/2026-10-14_a/index.html`, built with `build_compare.py --single
2026-10-14_0613_sqot:1 --label 'Mod 0613 (seed a, generated names)' --dir mod --shot-px 1600 --shot-q 50` (16 towns + 7
created; 6.0 MB; checked in headless Chrome at 1400 px and in a 390 px frame: the tables scroll inside their box). Shots
`2026-10-13_23-20-23_img_0` ... `23-21-26_img_22` (local time; SHOT n = k is `img_(k-1)`). No crash, 0 `SQOT
ERROR/WARN`; the only `Error` lines are the PDX SDK and a mod.io image.

### Speed (Quick 40 years: 182 s; estimate 0.7 x 30 + 13550 / 90 = 172 s, +6 %)

- 30 quiet years 20.3 s (0.4-1.2 s each) + 10 fill years 161.6 s (fillS 7.9-18.4, fillEarly 139 of 147 fills, roundS
  9-18 s, sizesS 0.5-0.8 s). 13,550 buildings added: 84 buildings / s in the fill years, **13.4 s per 1000 buildings**
  (0502 12.7 s). No round hit `why=time` (0502: two). The estimate formula holds.
- Again not gated on `HEAD done`: HEAD rounds 2-3 of all towns ran after `SIMGROW stop`, during and after the tour
  (Ashness-under-Edge's head round 2 built 12 edges at 06:21:09, after its shot at 06:20:23).

### Metrics (16 towns; median [quartiles]; map level only)

| Metric | Mod 0502 (Z2tNDhy0Ht) | Mod 0613 (a, this run) |
|---|---|---|
| Buildings start / end (sum) | 2552 / 20722 | 2027 / 15577 |
| Persons end (sum) / vs SIMGROW target | 97637 / 69 % | 44523 / 98 % |
| Persons per building `pb` | 3.08 [2.84-3.33] | **2.92** [2.74-3.07] |
| Free lots (%) | 55.5 [52.8-58.8] | 53.7 [51.9-57.3] |
| Spread / towns >= 1.3 | 1.24 [1.19-1.32] / 5 | 1.21 [1.13-1.32] / **5** (Acmere-in-the-Vale 1.80, Haywater 1.42, Thornby 1.39, Market Birkwath 1.36, Ashness-under-Edge 1.31) |
| Persons / ha (r disc) | 25.6 | 25.5 |
| Street m per person | 7.06 | 7.57 |
| Empty share of street length | 22.9 % | 20.9 % |
| Mod-built share of the edges (map / town median) | 22 % / 26.9 | **32 % / 34.7** (head 180 + demand 1424 edges; 28 + 232 builds) |
| CHECK outcomes | demand 340, ahead 34, open 32, free 0 | demand 356, ahead 50, open 20, **free 0** |
| Round builds / demand builds in years 1-20 | 189 / 116 | **226 / 136** |
| Satellites / districts / Works (linked) | 10 + 2 grow / 5 (4) / 2 (2) | 12 + 1 grow / 5 (**1**) / 2 (**0**) |
| Level weights set | 0 | 0 |
| Residential level 2 share (capacity) | 28 % [11-39] | 11 % [1-34] |
| Bridges built / coastal picks | 3 (1 failed) / 2 | 4 (1 failed) / 1 |

### Findings

1. **Young towns branch out (worked again).** All 296 CHECKs at `mat=0.00` read `demK=1.00`; 136 demand builds in the
   first 20 years (aim >= 100); the mod's share of the edges 32 %, higher than 0502 (22 %) and 0119 (24 %).
2. **Grown towns still don't build up.** Maturity phased in: mat 1.0 on Haywater, Market Birkwath, Mershaw-on-Ellerswater,
   Ashness-under-Edge (3600-4500 persons), 0.5-0.92 on Ketelholt, Ashdale St Brannoc, Upper Oakholme, Thornby; end demK
   0.41-0.64 (0502: 0.19-0.70). Yet 41 of the 42 CHECKs at mat >= 0.5 were `why=demand` and `why=free` never fired. The 8
   grown towns end **less dense** than the 8 young ones: pb 2.82 against 2.95, level 2 6.5 % against 16 %, mod share 27
   % against 40 %. Same causes as 0502: (a) LEVELS `skip=player` on all 8 grown towns (`ours=0`; the young 16 lines
   `skip=young`); (b) no hold while demand is high; (c) demK only halves demand.
   New detail on the custom weights: they differ per town (level 1 0.08-0.33, level 2 0-0.26, levels 3-4 0). The `w:`
   row equals `u:` x `c:` normalised, and the actual mix `a:` follows `w:`. Haywater `c:0.247/0.004` gives `w:98/2` and
   `a:99/1`; Thurgrove `c:0.077/0.081` gives `w:48/52` and `a:56/44`. So the engine's own per-town weights hold most
   grown towns at level 1. Thornby, Glenley, Little Skeghurst and Acmere get a level-2 weight of 0 and 0 % level 2.
3. **Offshoots.** 12 satellite seeds (8 `seeded`, 3 `hamlet:hamletFallback`: Mershaw, Wooddale, Ketelholt; 1 `hamlet`
   at a crossroads: Strathwood). One grow build (Wooddale, 3 edges). Two grow tries had nothing to build (Market
   Birkwath, Ketelholt). Not founded: 4 `rare`.
   - **Districts (5):** Merhaven (Mershaw, `src=generated`, shore), Upper Oakholme Heights (`composed`, kind=upper),
     Holtbottom Strand (`composed`, shore), Thursands (Thurgrove, `generated`, shore), Brockmere End (`composed`,
     shore). **Works (2):** Market Birkwath Works (`composed`), Smithby (Haywater, `generated`). Generated names on 3 of
     the 7.
   - **Links (regressed): 1 of 7 linked** (Holtbottom Strand, 1385 m; 0502: 6 of 7). Merhaven, Brockmere End and both
     Works failed with `why=back`: the route left a dead end backwards, `fails=back:43-63` of 90 routes. Upper Oakholme
     Heights and Thursands failed with `why=crossing`. Each had one try (`tries=1`) and no later retry in the log.
     Merhaven is still reached over Mershaw's new 128 m bridge. Brockmere End and Market Birkwath Works touch their
     parent (no separate place in the shot); Upper Oakholme Heights, Thursands and Smithby stand alone with no street
     to their parent.
   - **Forest gate held:** forest 0.00-0.19 on all 7. Not founded: district rare 5, character 2, forest 2; Works rare 8,
     character 2. **Identity:** `how=name+pos` 7 / 7, 7 distinct ids.
   - **0 `OFFSHOOT` lines:** every CHECK needed streets, as in 0502.
4. **Bridges, coastal, lanes, stops.**
   - **Bridges:** 4 built, all stone: Mershaw-on-Ellerswater 128 m (deck 4.3), Upper Oakholme 108 m (deck 11), Thurgrove
     128 m (deck 11), Ketelholt 108 m (deck 4.2). Upper Oakholme's first try (112 m, deck 11) failed with empty
     messages and `ProposalData error: Place on Land` (game finding below). Market Birkwath was refused 3x
     (`obstacle`, then `noSite`). 13 towns `noRiver` / `noCrossing`.
   - **Coastal pick:** Upper Oakholme 0.61; no other town reached `min=0.45` (Haywater 0.41).
   - **Lead lanes:** 6 built (hamlet: Ashdale St Brannoc, Little Skeghurst; ribbon: Thornby, Glenley, Acmere-in-the-Vale,
     Wooddale); 10 `rare`.
   - **Forest lanes:** 60 checks (wooded 130, joined 58, line 24, tip 17, short 22, freed / marked 0: none built).
     `forestHeld` > 0 in 99 PLAN lines.
   - **Stops:** none on the map (`STATIONS stations=0` throughout), so no STOPNAME line.
5. **No deep forest town**, and none could be picked on this map. The forest share of every growth ring (150-900 m)
   stayed under `DEEP_SHARE` 0.45: 15 `notDeep why=share:ring=`, and one `why=style:JP_DENSE` (Haywater, ring 0.24
   anyway). The style / tier / era / character factors never came into play, since the share check runs first after
   style.
   - **Most wooded:** Ashness-under-Edge 0.37 (share 0.35), Holtbottom 0.32, Market Birkwath 0.28, Brockmere 0.28,
     Thurgrove 0.27. Median ~0.22, lowest Mershaw-on-Ellerswater 0.14.
   - **Why so low:** a 50 m cell counts as forest at cover >= 0.5, i.e. about 24 trees / ha. The wooded cells' median
     density read only 16-36 trees / ha (p90 56-68), and the woods here are patchy.
   - **Visually:** Holtbottom, Market Birkwath and Little Skeghurst sit among woods that look 35-45 % wooded, yet read
     0.19-0.32.
   - **Fixes:** a rank-based pick (the map's 1-2 most wooded towns above ~0.30) or DEEP_SHARE ~0.33 would make this map
     pick Ashness-under-Edge and Holtbottom. Else test deep towns with the dev "Force deep forest".
6. **Generated names** (`NAMES mode=generated gen=en rivers=1 lakes=6 renamed=16 ok=31`; 15 industries renamed with
   the new town names). Every `NAME town=` line (old -> new, feature, the top tags, dialect), with a verdict from the
   shot:

   | Old | New | Feature | Top tags | Dialect | Verdict |
   |---|---|---|---|---|---|
   | Chudleigh | Haywater | lake | lake 1.00, ash 0.72, edge 0.70, forest, hill, oak | mixed | ok: town between a wide river and a cliffy lake. The river was read as `coast:lake` (no river tag) |
   | Dalton Town with Newton | Market Birkwath | river | bend 1.08, river 0.90, bridge 0.90, ash, forest, edge | norse | good: river bend below a confluence (River Dove) |
   | Axbridge | Mershaw-on-Ellerswater | edge | mere 1.08, lake 1.00, ash, vale 0.77, edge, oak | mixed | good: on a lake arm. `vale` is wrong (range 32 m) |
   | Cullompton | Ketelholt | forest | lake 1.00, ash, oak, edge, forest 0.68, small | norse | ok: wooded, on an inlet at the map edge |
   | Rowley Regis | Acmere-in-the-Vale | mere | ash 1.20, mere 1.08, lake 1.00, vale 0.77, edge, forest | norse | half: between two lakes, but flat (range 3 m): no vale. Its lake "Branttarn" is a tarn at altitude 2 |
   | South Molton | Wooddale | vale | ash 1.13, vale 0.77, edge, valley 0.50, forest, oak | norse | wrong: open flat plain (open 0.66, range 3 m), not a dale |
   | New Milton | Thornby | any | lake 1.00, oak 0.83, edge, ash, small, forest | norse | ok: lake shore; the name doesn't use the lake |
   | Wokingham | Ashdale St Brannoc | vale | ash 1.20, character, vale 0.77, edge, market, big | norse | wrong: flat plain (range 3 m), no dale. Character suffix fine |
   | Kirkby Stephen | Upper Oakholme | island | island 1.60, spit 1.50, ash, headland 0.98, slope, rocky | norse | half: a headland / peninsula, not an island. `holme` fits; "Upper" at altitude 2 doesn't |
   | Alfreton | Thurgrove | forest | ash 0.90, edge, forest 0.58, oak, small, hill 0.31 | norse | half: grove ok; two rivers 300-400 m either side missed (`water=0`), no river name |
   | Leatherhead | Strathwood | forest | ash 1.18, vale 0.77, edge, forest 0.51, valley 0.50, oak | mixed | weak: flat plain by a river 1 km off; "strath" (broad valley) is a stretch |
   | Horncastle | Glenley | edge | oak, vale 0.77, ash, edge, forest, valley 0.50 | mixed | wrong: flat coastal plain, no glen |
   | Holsworthy | Brockmere | mere | mere 1.08, lake 1.00, ash, vale 0.77, edge, forest 0.65 | mixed | good: on a lake bay |
   | Faringdon | Little Skeghurst | forest | ash 1.20, edge, forest 0.49, small, hill 0.33, field | norse | ok: at the foot of a wooded hill |
   | Dartford | Holtbottom | valley | ash, forest 0.83, vale 0.77, edge, oak, valley 0.50 | mixed | half: wooded (holt) yes; flat, not a valley bottom |
   | Harrogate | Ashness-under-Edge | spit | spit 1.50, foot 1.17, ash, clearing 1.08, character, headland 0.98 | mixed | wrong: no water in the disc (`water=0`). The spit comes from the wide pass, 1.6 km out (`spit=1600/200/300`). "under Edge" (foot 1.17) fits the hill |

   Tags that misfire:
   - **`edge:0.70` on all 16:** any forest share from 0.08 to 0.35 puts it. It is a weak always-on tag.
   - **`ash` on all 16, top species everywhere** (ash 0.6-1.2, from the temperate climate's mix): three names start with
     Ash-.
   - **`vale:0.77` on 8 towns** from `floor >= 0.6 and wide.sd >= 15`. The wide survey's height spread is 15-38 m on
     every town here (distant hills), so flat towns get dale / glen / strath / bottom / vale names: Wooddale, Ashdale,
     Glenley, Strathwood, Holtbottom, Acmere-in-the-Vale.
   - **`spit` from the wide pass** with no water near the town (Ashness).
   - **`island`** for a peninsula (Upper Oakholme, STYLE `island=1`).
   - **`tarn`** in a lake name at altitude 2 (Branttarn); **"Upper" / "Heights"** on flat land.
   - **`lake:1.00` on 6 towns is right:** all six (Haywater, Mershaw, Ketelholt, Acmere, Thornby, Brockmere) sit at a real
     lake or inlet. But Haywater's and Thurgrove's rivers went unread, so `rivers=1` on a map with at least three.
7. **Shots.**
   - **Best:**
     - Upper Oakholme: fills a headland, with a bridge and a peninsula-tip spine.
     - Mershaw-on-Ellerswater: on a lake arm, with Merhaven across its new bridge on the peninsula.
     - Haywater: a long river-bank town wrapping a cliffy lake bay.
     - Brockmere: on the lake bay.
     - Market Birkwath: a river bend, with its satellite across the river.
     - Thornby: a lake-shore ribbon.
     - Holtbottom with Holtbottom Strand: a separate linked hamlet on an inlet.
   - **Weakest:**
     - Acmere-in-the-Vale: small (448 buildings), spread 1.80 from an empty ribbon lead lane.
     - Strathwood: 385 buildings, a gridded EU_EXTENSION block with stubs.
     - Ashdale St Brannoc and Little Skeghurst: empty zig-zag lanes and loops at the edge.
     - Brockmere's south edge: a ladder of empty streets.
   - **Odd:**
     - Empty "H" satellite skeletons with few or no houses: Thornby (two), Thurgrove, Little Skeghurst, Mershaw, Wooddale
       and Holtbottom.
     - Mershaw's straight zig-zag lanes to the south-east.
     - Upper Oakholme Heights, Thursands and Smithby stand unlinked. Thursands sits in a river fork and reads well as a
       place.
     - Market Birkwath Works and Smithby are housing clusters with no industry.
     - Shot 1 (Ashness-under-Edge) used the fallback camera (`fallback=true`), 925 m north of the town centre: the town
       sits at the bottom edge of the frame.
     - Haywater is styled JP_DENSE on a European map (site style from coast 0.74 + rough 0.57); it looks fine.

### Next

- **Grown towns:**
  - LEVELS: stop reading the engine's own per-town custom weights as the player's (remember `ours`, or the first
    read on a new map).
  - Probe when `custom` appears and whether it changes per SIMGROW chunk.
  - A real hold for mat >= 0.5 (demK ~0.2 at mat 1 or FREE_AIM by maturity). Grown towns here ended less dense than
    young ones.
- **Offshoot links:** retry (tries > 1, later turns), and let a route start from a dead end's side or the parent's
  nearest edge, not only straight off the dead end (`why=back` on 4 of 6 failures).
- **Satellite seeds that stay empty:** grow or fill them, or seed only where the parent's growth will reach.
- **Deep forest:** a rank-based pick or a lower share (0.33) so a temperate map gets 1-2 deep towns; or calibrate cover
  (24 trees / ha for a forest cell is above the median wooded cell here).
- **Name tags:**
  - Weight species by rarity on the map (not raw count).
  - Drop or weaken the always-on `edge`.
  - Gate `vale` / `valley` on the town's own relief (range / grade), not the wide survey's height spread.
  - `spit` only with water in the disc or ring.
  - `island` only when the land is enclosed (not a peninsula).
  - `tarn` only at altitude; "Upper" / "Heights" only above the surroundings.
  - Read wide rivers along a town as rivers (Haywater), and rivers within ~400 m (Thurgrove).
- **Quick:** gate on `HEAD done` (third run with HEAD rounds during the tour).
- **Tour:** check the fallback camera's aim.

## Seed a: true vanilla baseline 2026-10-14 0640

### Runs

| Run | Session | Settings | Growth | Time |
|---|---|---|---|---|
| Vanilla | `.cache/logs/2026-10-14_0640_sqrl-sqsg.log.gz`, load 2 | `PRERUN actOn=off writes=none angle=0`, Game names, Quick 40 years | buildings 1473 -> 7071 | s=79 |
| Mod | `2026-10-14_0613_sqot`, load 1 | generated names, the maturity retune | buildings 2027 -> 15577 | s=182 |

The vanilla run's session prefix also matches the short archive `-2`, so pass the full path to build_compare.py.

Page: `compare/2026-10-14_a/index.html` (two runs, towns paired by entity id).

### Medians across the 16 towns

| | Mod | Vanilla |
|---|---|---|
| Persons at year 40 (the same target) | 2828 | 2828 |
| Buildings | 920 | 431 |
| Persons per building | 2.92 | 6.47 |
| Persons / ha | 25.5 | 52.7 |
| Radius | 544 m | 398 m |
| Spread | 1.21 | 1.16 |
| Street per person | 7.6 m | 3.8 m |
| Empty street length | 20.9 % | 18.9 % |
| Free lots | 53.7 % | 49.1 % |
| Grid share | 0.27 | 0.78 |
| Dead ends per km | 1.57 | 1.49 |

### Reading
- **The same pattern as the U8Qxgisp4I same-seed comparison:** the same people, but the mod spreads them over twice the buildings and twice the street. The mod is organic (grid share 0.27 against vanilla's 0° grid at 0.78) and about 37 % wider.
- **Empty streets and dead ends** are close to vanilla.
- **Density in grown towns** is still the open gap (NEXT_PHASE_BRIEF §44 fix round).
