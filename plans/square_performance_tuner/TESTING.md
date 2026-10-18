Status: Phase 1 probe built (2026-10-12), not run in game yet. Runs A-F below answer Q1-Q5 of PLAN.md.

# Testing: Sim Tuner probe (Phase 1)

Mod: `mods/square_sim_tuner_probe/` (DEV, never upload; linked into staging by `make link`). Every line it writes
starts with `[SQSTP]`. After each run: `make logs-grep PAT='\[SQSTP\]'` (add `ARGS='--session last'` for the latest
session, `ARGS='--session last -C 0 --max 400'` for more lines). Paste the output, or just say which run it was.

## Setup

- **Save:** a *copy* of a large save (the bigger the better for Q5; the 109.5k-person save from the Smart Lanes
  tests is ideal) with some bus/tram lines. Runs A-E also work on any small save with 2-3 lines. The probe writes
  nothing into the save, but it changes how often people re-pick destinations while active: use a copy anyway.
- **Mods:** enable "DEV Sim Tuner Probe" when loading the save. Other mods may stay on, but nothing else that sets
  `simPersonDestinationRecomputationProbability` (the Stress Test's "Sim recompute" must be x1).
- **Mod settings** (shown when the mod is enabled):

  | Setting | Values (default **bold**) | What it does |
  |---|---|---|
  | Base recompute probability | 100 / 70 / 40 / **20** / 5 % | value written at load |
  | Set at load via | **preRunFn** / runFn / postRunFn | where it is written (Q1) |
  | Boost after line changes | Off / **On** | 100 % for a while after a line is created, changed or removed (Q4) |
  | Boost length | 15 days / **1 month** / 3 / 6 months / 1 year | in-game days at the default day length |
  | Runtime writer | **GUI** / Game script / Both | which Lua state writes runtime changes (Q2) |
  | Town develop interval | **Unchanged** / 120 / 240 | townDevelopInterval at load (extra A/B) |
  | Animal density | **Unchanged** / 50 % / 10 % | animal.populationDensityMultiplier at load (extra A/B) |
  | Sim step timing | **On** / Off | reads the game's sim step times every second; turn Off if the game crashes right after loading |

- **Button:** "SQSTP p=0.20 auto" in the top-left mod button row. Each click cycles the mode:
  `auto` (base value, boosted after line changes) -> `hold_high` (1.0) -> `hold_low` (base value) -> `auto`.
  The label shows the value the GUI reads back right now.

## What the probe logs

| Line | When | Answers |
|---|---|---|
| `load preRunFn ... p 1->0.2` / `load runFn ... game=... game.config=...` / `load postRunFn ... readback p=...` | at load | Q1: which path wrote, and whether `game.config` exists in TF3 |
| `gs readback first vm=... p=...` | first sim update per Lua state, then every 30 in-game days, and at once on a change (`gs readback changed`) | Q1 + Q2 seen from the simulation side |
| `gui start ...`, `gui readback first ...`, `q1 match=yes/no loaded=... param=...` | first frame of the loaded game | Q1 |
| `mode hold_high`, `switch 0.20->1 state=... why=...` | every change of the wanted value | Q4 |
| `write side=gui ok=... before=... readback=...` / `write side=gui->gs sent=...` + `write side=gs ok=...` | every runtime write | Q2 |
| `gui readback changed 0.20->1.00` | the GUI state sees a new value (e.g. one the game script wrote) | Q2 across states |
| `line created/changed/removed line=... stops=a->b` | line poll (every 3 s real) | Q4 |
| `sample built persons=N sample=400 ms=...` | once, and again if 30 % of the sample is gone | Q3 setup cost |
| `churn pass=k p=... mode=... spanDays=... recomputed=R destChanged=D ratePerPersonDay=... ageDaysMed=... lastRawMin/Max=...` | every 10 in-game days | Q3 |
| `perf pass=k p=... gameDaysPerRealS=... speedup=... bench n=... p50=... p95=... max=...` | every pass | Q5 cost |
| `ridership pass=k riders(line:n@age) ...` | every pass, lines created/changed this session | Q5 benefit |
| `... ERROR ...` | any failure (all calls are in pcall) | |

`recomputed` = sampled persons whose `lastDestinationUpdate` changed since the previous pass; `destChanged` = whose
destinations (home, shop, work) changed. `ageDaysMed` = median days since each sampled person's last recomputation
(only meaningful if `lastRawMax` is in game-time ms, i.e. close to `gameTime`).

## Run A: Q1 set at load (preRunFn), Q2 runtime write from the GUI

1. Defaults (20 %, preRunFn, boost On 1 month, writer GUI). Load the save, let it run 1 min at 1x.
2. Expect `load preRunFn ... p 1->0.2`, `gs readback first ... p=0.2`, `q1 match=yes loaded=0.2`.
3. Click the button once (`hold_high`): `switch 0.20->1`, `write side=gui ok=true ... readback=1`, then within a few
   seconds `gs readback changed ... p=1` (the simulation states see the GUI's write).
4. Click twice more (back to `auto`): `switch 1->0.2`.
5. **Answers:** Q1 = `q1 match`. Q2 (GUI) = `writeOk` / `readback`. Cross-state = whether `gs readback changed` follows.

## Run B: Q1 via runFn and postRunFn

Quit to the main menu between loads (never remove the mod while a save is loaded).
1. Load with "Set at load via" = runFn. Expect `load runFn ... game=table game.config=...` (or `game=nil`) and `q1 match=`.
2. Load with postRunFn. Expect `load postRunFn ... write ok=...` and `q1 match=`.

## Run C: Q2 runtime write from the game script

1. Load with "Runtime writer" = Game script. Click once (`hold_high`).
2. Expect `write side=gui->gs sent=true`, then `write side=gs ok=... vm=...` (one or more simulation states), then
   `gui readback changed 0.20->1.00`. No `write side=gs` line at all = the game script never got the event (check `gs subscribe ok=true` first).
3. Optional: writer = Both.

## Run D: Q3 does the engine honour the value (churn)

1. Defaults, a save with towns of a few thousand people at least. Game speed 4x. Don't touch lines.
2. `auto` mode (= 0.2): wait for 6 `churn` passes (~60 in-game days, ~2-4 min at 4x).
3. Click to `hold_high` (1.0): 6 more passes. Click to `hold_low` (0.2): 6 more.
4. Control: quit, reload with Base = 100 %, 6 passes in `auto`.
5. **Answer:** `ratePerPersonDay` / `recomputed` per pass at 1.0 vs 0.2. A runtime change honoured by the engine shows as
   a step in the rate after the `switch` line; no step while the 100 % load is higher = only load-time works; no
   difference anywhere = the field doesn't drive what `lastDestinationUpdate` measures (then compare `destChanged`).

## Run E: Q4 boost on line change

1. Defaults (boost On, 1 month), `auto` mode, 1x or 2x.
2. Create a new bus line between two stops. Expect `line created line=... stops=-->2`, `switch 0.20->1 state=boost
   why=line_created:...`, and about 1 in-game month later `switch 1->0.2 state=base why=boost_end`.
3. Add a stop to an existing line: `line changed ... stops=2->3` (the boost is extended, no second switch line while
   already at 1.0). Delete a test line: `line removed`.

## Run F: Q5 does it help (cost and ridership)

1. The big save, 4x (or the highest speed that is not smooth), camera parked on one spot, `auto` without line changes.
2. Alternate `hold_high` / `hold_low` every 5 passes, 3 times each. Note what the game's own UI shows (actual speed,
   any frame drops).
3. **Cost:** `perf` lines: `gameDaysPerRealS` (does the sim keep up?) and `bench p50/p95` (sim step time, raw
   units; the first `bench first pull` line shows the buffer) at 1.0 vs 0.2. Note: the first passes after a switch
   mix both values.
4. **Benefit:** create the same kind of new line twice in two loads, once with boost On and once with boost Off
   (Base 20 %), and compare `ridership` riders at equal ages (e.g. @30d, @90d). Also a load at Base 100 % as the
   vanilla reference.

## Results

- Run A (`2026-10-12_2328_sqstp`): `q1 match=yes` via preRunFn; GUI write refused ("cannot write to read only member").
- Run B: skipped; runFn shows `game.config` without the field, postRunFn read-back = 0.2.
- Run C (`2026-10-12_2343_top-up-563524`, after adding the subscribe): game-script write refused, same error.
  Runtime change and the line-change boost (Run E) are impossible; Runs D/F become load-to-load A/B.
- Churn at 20 % (desert save, 400 sampled persons): `recomputed` 2-7 per 10 days, ~0.0005-0.0018 per person-day;
  median `lastDestinationUpdate` age ~410 days. No 100 % baseline yet. Game facts go to `docs/findings/<topic>.md` (+ index line), Phase decisions to PLAN.md.
- Load A/B, desert save, 4x, no input (`2026-10-12_2343_top-up-563524`; the 20 % reading appears twice, identical):

  | Base | windows | re-picked / 400 / 10 d (mean) | step p50 (median) | step p95 (median) | game days / s |
  |---|---|---|---|---|---|
  | 20 % | 7 + 16 | 3.7 | ~58,600 | 73-80k | 1.00 (0.82-0.94 in 3 late windows) |
  | 100 % | 9 | 6.7 | ~69,300 | ~105k | 0.90-1.00 |

  The engine honours the load-time value (about 1.8x re-picks at 100 %, not 5x: other triggers re-pick too).
  Sim step about 18 % cheaper at p50, ~30 % at p95 at 20 %. Step-time units unknown (api.gui.benchMark
  getGameStepTimes). The sim kept up at 4x either way on this map.
- Big save `autosave_Empty 2_2020-03-06` (105,734 people, 0 lines, ~65 days old; session
  `2026-10-12_2343_top-up-563524` at 20 %, the following live session at 100 %): game days/s at 3x 0.53/0.42/0.40
  (20 %) vs 0.40/0.43 (100 %); re-picks per 10 days 45-59 (20 %) vs 52-65 (100 %). No clear difference. Shelved.
