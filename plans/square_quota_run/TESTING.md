# Quota Run: playtest script (Phase 4)

This file is not shipped (it lives in `plans/`). It walks through the first playtest and lists what to report back. Read [`GUI_FALLBACK.md`](GUI_FALLBACK.md) if the HUD doesn't show.

The build under test is `revision 1` with `DEBUG = true` (debug console ops and the in-game **Dev** panel on) and `GUI_INLINE_PICKER = false` (compact HUD plus a dialog window).

To test a feature without playing the whole loop, jump to [Dev tools](#dev-tools) below.

## 0. Setup

1. `make link` has already been run by the coordinator. It only adds a symlink `staging_area/square_quota_run -> mods/square_quota_run`. Nothing changes until the mod is ticked for a game.
2. Turn on debug mode (Settings → Advanced, or `debugMode = true` in `settings.lua`). You need it for the console (`docs/wiki/modding/tools/ingame.md`, "Console").
3. Open the console with the key below ESC (`` ` ``, `§` or `^`, depending on the keyboard layout). Type a line of Lua and press Enter.
4. Keep the log open in a terminal:
   ```sh
   tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered QuotaRun
   ```
   After a session: `grep -n QuotaRun ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt`. Also check for Teal or Lua errors that mention `square_quota_run`: `grep -n -i "square_quota_run\|error" .../stdout.txt | head -50`.

## 1. An existing save must load unchanged (do this first)

1. Load an existing save **without** adding the mod. Nothing should change.
2. (Optional, stronger.) Add Quota Run to an existing save through the save's mod list. The game should warn you (`severityAdd = Critical`). Load it anyway.
   - Expected: no `[QuotaRun] activated` line. The log may show `[QuotaRun] inert: added to an existing savegame`, or nothing at all. With `DEBUG = true` (this build) the ridge shows only `Quota Run: inert` and a **Dev** button (so Force start is reachable, see [Dev tools](#dev-tools)); don't press Force start here. With `DEBUG = false` there is no HUD at all.
   - Afterwards, **don't save** over that game, or save it under another name.

## 2. New free game

1. Start a **new free game** (not a campaign mission or tutorial) with Quota Run ticked in the mod list. Any map is fine. Also try one custom-map start (`initNewGameFromMap`) if you can.
2. Expected log:
   ```
   [QuotaRun] activated: gameTime=… monthDuration=… seed=…
   [QuotaRun] round 1 started: quota=2500 endTime=…
   [QuotaRun] notify roundStart {months=36, quota=2500, round=1}
   ```
   On a custom map you may also see `[QuotaRun] re-initialising the run on initNewGameFromMap` followed by a second `activated` line. That is intended (it re-sends the round-1 notification that the base may wipe on that event).
3. HUD: a compact one-line panel in the top-left button ridge, next to the layer buttons. It reads `Quota Run R1: 0 / 2,500 - 36 mo left` and has a small progress bar. Hovering it lists the picked cards, once there are any.
4. A "Round 1 started" notification should pop up. If it is missing, the HUD is still the source of truth. Report it.

## 3. Console commands (exact strings)

All of these are QuotaRun events. The debug ops only work while `DEBUG = true`.

```lua
-- state dump (offer ids, progress, fx) -> log line "[QuotaRun] dump: {…}"
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "dump" }))
-- add progress
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "addProgress", n = 5000 }))
-- move the deadline to now (the round ends on the next UNPAUSED frame)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "endRound" }))
-- set months left
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "setMonthsLeft", n = 2 }))
-- red months = 5 (the next month tick with a negative balance ends the run)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "bankrupt" }))
-- force a card offer now (phase -> choosing, pauses)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "offer" }))
-- pick card 1, 2 or 3 (works without any GUI)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.pickCard", { index = 1 }))
-- after a run ends
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.continueSandbox", {}))
```

`endRound`, `setMonthsLeft` and `bankrupt` only change numbers. The transition happens on the next unpaused frame, so unpause if nothing happens. The dev-panel ops below (`passRound`, `failRound`, `skipMonths`) act immediately, even while paused.

## Dev tools

Everything here needs `DEBUG = true` in `content/quota/quota_config.tl` (the playtest build). With `DEBUG = false` none of it exists: no Dev button, the debug ops are ignored, and an inert save is never touched.

### Dev panel (in game)

The HUD in the top-left ridge gets a small **Dev** button. It also shows on a save **without** a run (`Quota Run: inert` + Dev) and after a run in sandbox, so you can always reach **Force start** and **Reset run**. It does not show in the map editor or in a save whose run was turned off by a mission/tutorial start.

**Dev** opens a centered, movable window, **Quota Run - Dev**. It stays open while you click (close it with its close button). The top line is a live status: `phase  R<round>  progress/quota  mo=<months left>  red=<red>/<limit>  cleared=<n>  fx: veh TopSpeed=1.15 x<vehicles> | ind <industries>`. Buttons (each sends one `QuotaRun.debug` event):

| Group | Buttons (op) |
|---|---|
| Round | Pass round (`passRound`), Fail round (`failRound`), +25% quota (`addQuotaPct 25`), +100% quota (`addQuotaPct 100`), Skip 1 month (`skipMonths 1`), Skip 6 months (`skipMonths 6`), Force offer (`offer`) |
| Cards | one button per card in `quota_cards.tl` (`applyCard <id>`), description in the tooltip |
| Money | +$10M / -$10M (`addMoney`), Bankrupt: red months (`bankrupt`) |
| Run | Clear effects (`clearEffects`), Reset run (`reset`), Force start (`forceStart`, only enabled on an inert save), Dump state to log (`dump`) |

With `GUI_INLINE_PICKER = true` the same buttons render inline in the ridge panel under a **Dev** toggle (may be clipped; the console helper below always works).

What the ops do (PLAN §4.2):

- `passRound`: progress becomes at least the quota and the round is judged **now**: reward, `choosing`, pause, offer. The next round starts now.
- `failRound`: progress 0, judged now: `ended` (quota), effects cleared, pause.
- `skipMonths {n}` (1..240): as if n months passed. The round's time anchors move back n months and the catch-up runs now: n month ticks, each using your **current** balance (in the red: red months +n, bankruptcy can end the run; in the black: red months reset), and the round ends if its deadline falls inside the skipped span. No deliveries are counted for skipped months, and money and the calendar don't move. Works in `running`/`choosing`.
- `applyCard {id}`: applies any card exactly like a pick (cash, quota, deadline, vehicle and industry effects), without using or closing an offer and without resuming. It is added to the picked list like a real pick; the log line says `debug applyCard <id> (no offer used)`. Works in `running`/`choosing`.
- `addMoney {n}`: books `n` (negative = cost) like a card's cash. Any active phase.
- `addQuotaPct {n}`: progress += n% of the current quota.
- `clearEffects`: removes our vehicle and industry modifiers; phase, quota and reward multipliers stay.
- `reset`: clears effects, resumes if we paused, then starts a fresh run (round 1, new seed) at the current date. Any active phase, including `ended`/`sandbox`.
- `forceStart`: see "existing network save" below.
- `dump`: logs the state (on an inert save: `dump (inert): …`).

Invalid ops or parameters are logged as warnings (`debug … ignored: …`) and change nothing.

### Console helper (paste once)

In the console (debug mode, key below ESC), paste this once:

```lua
qr = function(op, n, id) api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", {op=op, n=n, id=id})) end
```

Then e.g. `qr("passRound")`, `qr("skipMonths", 6)`, `qr("applyCard", nil, "overdrive")`, `qr("addMoney", -10000000)`, `qr("forceStart")`, `qr("dump")`. Card ids: `venture hostile_loan express overdrive luxury boomtown industrial_policy lean_year extension crunch austerity gamble`. The `qr` global lives in the console's Lua environment, so you may need to paste it again after loading another save or restarting the game.

### The game's own debug window

With debug mode on, **AltGr + D** opens the Debug Tool Window (`docs/wiki/modding/tools/ingame.md`, "Debug Tool Window"). Its **Simulation options** raise the simulation speed up to 32x (normal maximum 4x), which is the fastest way to let real months pass with real deliveries. AltGr is the right Alt key on US layouts. On a Mac keyboard it is probably the **right Option** key; this is unverified.

### Quick test recipes

- **Test a card in 30 seconds:** new free game → **Dev** → click the card (for example **Overdrive**) → check the log for `debug applyCard overdrive` and `vehicleMods rev=… sent=N`, and the status line for `fx: veh TopSpeed=1.30…`. Open a vehicle window to see the speed. **Clear effects** removes it again (`clearEffects: vehicles=N …`, status `fx: no effects` after the capped clear finishes on unpaused frames).
- **Test the pick screen:** **Pass round** → game pauses, HUD shows **Pick a card** → pick one in the window.
- **Test the fail screen:** **Fail round** → game pauses, HUD shows **Run over** → open it → **Continue as sandbox**. Then **Reset run** (the Dev button stays in sandbox) to start over without a new game.
- **Test bankruptcy:** **-$10M** until the balance is negative (or take no loan and spend) → **Bankrupt: red months** → **Skip 1 month** → run over, reason bankrupt. For the warning instead: with a negative balance, **Skip 1 month** three times → `bankruptWarn` notification at 3 red months.
- **Test on an existing network save via forceStart:** use a **copy** of the save (save it under a new name first, or copy the save file). Add Quota Run to that save's mod list (the game warns, `severityAdd = Critical`), load it. The HUD shows `Quota Run: inert` and **Dev**. **Dev → Force start**. Expect the warning `!!! FORCE START (debug) !!! activating Quota Run on an inert save that the mod was ADDED TO (existing savegame)`, then the normal `activated` / `round 1 started` lines. From then on the save has a run: **never save over the original**. Force start is refused (logged) in campaign missions, in a save whose run was turned off by a mission/tutorial start, and in the map editor. Without pressing it, the save stays unchanged: in a DEBUG build the script only subscribes to the `QuotaRun.debug` event (no state is written); release builds (`DEBUG = false`) don't even do that.

## v2 probes (P1–P7)

These answer the open engine questions in PLAN §9.9 before the v2 engine features are built. They need `DEBUG = true` and an **active run** (start a new free game, or Force start on a copy). On an inert save they're refused (`debug <op> ignored: no run in this save (inert)`). With `DEBUG = false` they're rejected like every other debug op (`debug ignored: DEBUG is off`). Bad parameters log `debug <op> ignored: missing or invalid n … (allowed lo..hi)` and change nothing.

The adapter handles probes (`quota.script.tl`), and the logic never sees them. Probe bookkeeping lives in `state.probe`, which shows up in `dump`.

**P3 and P4 change the save for good. Run them only on a throwaway save.**

```lua
-- P1: return {[0] = 1.5} from OnCalcTicketPrice (n = multiplier x 100, 0..1000). n = 0 turns it off.
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "incomeProbe", n = 150 }))
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "incomeProbe", n = 0 }))
-- P2: log every resolved fact field for the next n delivered entities (1..200)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "factsProbe", n = 20 }))
-- P3: move the CALENDAR n years ahead (1..100). NOT REVERSIBLE.
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "jumpYears", n = 10 }))
-- P4: start an n-month closure countdown on one closable industry (1..240 months)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "closeIndustry", n = 2 }))
-- P6: log the TOWN component of town #n (by entity id; n optional, default 1)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "townProbe" }))
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "townProbe", n = 2 }))
-- P7: logged automatically at activation; also after every dump
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "dump" }))
```

With the console helper: `qr("incomeProbe", 150)`, `qr("incomeProbe", 0)`, `qr("factsProbe", 20)`, `qr("jumpYears", 10)`, `qr("closeIndustry", 2)`, `qr("townProbe")`, `qr("dump")`.

### P1: how do two `OnCalcTicketPrice` handlers combine?

1. Turning the probe on logs the base company multiplier: `P1 incomeProbe ON: returning {[0] = 1.5} … base company ticketPriceMultiplier=<x>`. `nil` means the company has no ticket bonus yet, or its script state couldn't be read.
2. Pick one simple line, for example a single truck line moving one cargo between two fixed stops. Before the probe, note the income per trip over 2–3 trips (line or vehicle window, or the finance window).
3. `incomeProbe 150`, then watch 2–3 more trips on the same line. The log shows the first 10 events: `P1 OnCalcTicketPrice from TransportVehicleSystem: entries=<k> first={basePrice=…, distance=…, lineEntity=…, simEntity=…, stockListEntity=…, vehicleEntity=…} -> returning [0]=1.5 (<left> more logged)`. Passengers show `from SimEntityAtVehicleSystem` (with no `stockListEntity`).
4. Also try `incomeProbe 50`, then `incomeProbe 0`. Expect `P1 incomeProbe OFF (unsubscribed from OnCalcTicketPrice)`, and income should go back to normal.
5. **Report:**
   - income per trip before the probe, with ×1.5, with ×0.5 and after OFF, plus the company multiplier `c`. With our multiplier `m`: income × c·m means the handlers **multiply**, × m means **last wins** (ours), and × c means **first wins** (the base);
   - 2–3 of the `P1 OnCalcTicketPrice` lines (for `basePrice` and the entry count);
   - any hitch while the probe was on (the handler runs on every ticket event).
6. The probe survives save/load (`handleLegacy` re-subscribes it). Turn it off before you go on playing.

### P2: do cargo `pickupPoints` carry `line` and `carrier` at arrival time?

1. Run a few cargo lines (truck and train if possible) and a bus line, then `factsProbe 20`.
2. Each delivered entity logs one line: `P2 fact {cargoType=…, carrier="RAIL", fromTown=…, kind="cargo", line=…, toTown=…} (entry table, <left> left)`. A field that can't be resolved is left out. Passenger facts never have `cargoType`, `line` or `carrier`.
3. **Report:** 5–10 cargo lines and 5 passenger lines, and answer these:
   - Do cargo facts have `line` and `carrier`, and does the carrier match the vehicle type?
   - Is `toTown` set for cargo delivered to a town, and missing for cargo delivered to an industry?
   - Is `fromTown` ever set for cargo? It is only set when the source is a town building.
   - Do passenger facts have both towns, and do they differ on an inter-city line?
   - Does every line say `entry table`? Anything else means the engine's event entries aren't plain tables, and the facts come out empty.
4. The probe doesn't change scoring: the logic still gets only the fields that its current rule needs.

### P3: what does `makeGameSetDateCmd` do mid-game?

Use a **throwaway save**. First note the date, balance, loan amount, a few vehicle ages and the vehicle purchase list. Then run `jumpYears 10`.
- Expect the warning `!!! P3 jumpYears 10 (debug) !!! NOT REVERSIBLE: setting the calendar from <y-m-d> to <y+10-m-d>`, then `P3 jumpYears: date before=… after=… gameTime=…`. If `after` still shows the old date, the change applies a frame later; check the game bar.
- **Report:**
  - the date in the game bar;
  - whether the run's months left changed (it shouldn't: the run counts game time, not the calendar);
  - vehicle ages, and whether vehicles now show as old;
  - whether new vehicle models unlocked;
  - prices and maintenance (inflation);
  - loan amount and interest;
  - any errors in the log.

### P4: does a forced closure countdown stick?

Use a **throwaway save**. Run `closeIndustry 2`. The probe only picks industries that the base closure logic can close: with output, no depots, not manual and not player-owned.
- Expect `!!! P4 closeIndustry (debug) !!! industry <e> "<name>" (<k> candidates): despawn time <old> -> <t> (now <now> + 2 months), reads back <t>. …`. The time is **game time** (the clock `GAME_TIME.gameTime` uses), as in the base.
- The pick is deterministic (the run's RNG). Running it again picks another industry, because each run advances the RNG.
- From the base code we expect a **busy** industry to lose the countdown almost at once: the base resets it to 0 on its next update if the industry shipped or consumed recently. An **idle** industry should close at `<t>`.
- **Report:**
  - the industry name, and whether you serve it;
  - whether its window shows a closure warning;
  - whether it still exists after 2 months (use the Debug window speed-up). Ideally test once on a served industry and once on an idle one.

### P6: can we read a town's development-active flag?

Run `townProbe`, then `townProbe` with `n = 2` and so on.
- Expect `P6 townProbe 1/<towns>: {capacityScalingFactor=…, developmentActive=true, entity=…, initialLandUseCapacities=…, name="…", noise=…, pollution=…, sizeFactors=…}`.
- **Report:**
  - whether `developmentActive` is present and a boolean, and its value for a normal growing town;
  - whether list fields show as `{…}` or as `userdata: …`;
  - whether `name` matches the town.

If the game's UI or debug tools can freeze a town, freeze one and probe it again to see the flag flip.

### P7: does `getModParams()["square_quota_run"]` work at runtime?

At activation (new game or Force start), expect `P7 modParams["square_quota_run"] (activation): <value>`. The same line follows every `dump`, on an inert save too.
- **Report:** the exact value. The mod has no `params` yet, so `nil` or `{}` are both plausible. `nil` means our mod's params aren't exposed this way.

### Boss rounds, quickly

v2.1 bosses:
- `inspector`: all vehicles TopSpeed ×0.75;
- `cargo_baron`: rule `freight_only`;
- `transit_commissioner`: rule `commuter_rush`;
- `monopolist`: rule `specialist` (needs cargo delivered last round);
- `mayor`: rule `local_hero` (needs town deliveries last round).

Rules: `freight_only commuter_rush local_hero specialist rail_day long_haul`. An `id` of `""` or `"none"` clears.

```lua
-- make the round in progress a boss round right now
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "setBoss", id = "inspector" }))
-- announce the boss for the next round, then pass this round to reach it
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "setNextBoss", id = "cargo_baron" }))
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "passRound" }))
-- set or clear only a scoring rule for this round
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "setRule", id = "rail_day" }))
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "setRule", id = "none" }))
```

Helper form: `qr("setBoss", nil, "inspector")`, `qr("setNextBoss", nil, "cargo_baron")`, `qr("passRound")`, `qr("setRule", nil, "rail_day")`.

- **Fastest:** `setBoss inspector`. Expect `debug setBoss inspector: round=… quota=…` and `vehicleMods rev=… {TopSpeed=0.75…}`. Vehicles slow down, and the HUD shows the boss. `setBoss` with `id = ""` ends it, and the speed comes back.
- **Real flow:**
  1. Get to round 2 (`passRound` from round 1, then pick), then `setNextBoss cargo_baron`. The HUD shows the next boss. `setNextBoss` is refused with a warning unless the next round is a boss round (rounds 3, 6, 9, ...).
  2. `passRound`, then pick a card. The next round starts as the boss round, and its `roundStart` notification names the boss.
  3. Only cargo counts now. Check with `factsProbe 5` and `dump`: `progress` should grow only on cargo deliveries.
- `monopolist` and `mayor` (and `setRule specialist` / `local_hero`) need deliveries in the **previous** round. Play a round with deliveries, `passRound`, then set them. Otherwise expect `… has no … target in lastTally`.
- **Report:**
  - whether the HUD and the notification show the boss;
  - whether the rule visibly changes what counts (progress per delivery);
  - whether the Inspector slowdown applies, and whether it is removed when the boss round ends (`vehicleMods` lines);
  - whether clearing a boss round pays the boss reward multiplier.

## 4. MVP checklist (PLAN §6 Phase 4)

| # | Do | Expect |
|---|---|---|
| 1 | Start a new free game | HUD with a round-1 quota (`R1: 0 / 2,500`) |
| 2 | `addProgress n=5000`, then `endRound`, then unpause | Game pauses. Log shows `round 1 cleared … reward=2000000`, `cash 2000000`, `phase running -> choosing`, `paused (savedSpeed=…)`. HUD shows `R2 … (provisional)` and a **Pick a card** button. Clicking it opens a centered window with 3 cards (name on the button, description in the text and the tooltip). |
| 3 | Pick a card: **Venture Capital** (cash), or **Express Timetables** / **Overdrive** (speed) | Window closes, game resumes at the earlier speed, log shows `picked <id>` and `phase choosing -> running`. Cash: the balance jumps (`cash 8000000` in round 2). Speed: `vehicleMods rev=1 {TopSpeed=1.15} sent=N` (N = your vehicle count, at most 200 per frame and then `(capped, continuing next frames)`); vehicles visibly faster; the vehicle window's top speed should change. |
| 4 | `endRound` again with progress below quota, unpause | `round 2 failed`, `phase … -> ended`, `clearEffects: vehicles=N industries=M`, pause. HUD shows **Run over**. Its window lists the reason, rounds cleared, total moved and a **Continue as sandbox** button. Clicking it should resume the game, hide the HUD and log `phase ended -> sandbox`. |

Also try `bankrupt` with a negative balance (take loans and spend, or pick Austerity or Industrial Policy). Expect `bankruptWarn` at 3 red months, and the run to end on the next month tick after `bankrupt`.

Then save, quit to the menu, and reload the save. Expect the HUD to come back with the same numbers, no new `activated` line, and the speed boost (if picked) still active.

## 5. GUI fallbacks

- The picker window doesn't open, or it is broken: set `GUI_INLINE_PICKER = true` in `content/quota/quota_config.tl` and restart the game. That gives the old inline panel in the ridge, which may be clipped at the bottom. Picks also always work from the console (section 3).
- Nothing renders at all: see `GUI_FALLBACK.md` (game-bar text fallback, Fallback A).

## 6. What to report for each open risk (PLAN §7)

| Risk | Report |
|---|---|
| R1 GUI plugin renders | Does the compact HUD show in the ridge? Is it clipped? Does the **Pick a card** window open centered with 3 buttons? Can a click outside close it, and does the HUD button reopen it? Any `Recipe not found` or `RegisterPluginRecipe` lines? Screenshot please. |
| R2 init events | The exact `[QuotaRun]` lines at game start, for a normal map and a custom map. Did a custom-map start log `inert: added to an existing savegame`? That would mean maps count as existing saves. |
| R4 metric | The monthly `month N: … progress=X/Y statsDelta=Z` lines for a few months. Does `progress` grow plausibly? How does it compare to `statsDelta`? Roughly how many units per month does your network move (for quota calibration)? |
| R5 events while paused | After a pick made while paused, does the window close and the game resume immediately, or only after you unpause? |
| R7/R11 industry composition | After Boomtown or Industrial Policy, the line `industryMods probe: stockList <e> PERSON_CAPACITY=<true/false> baseBoosted=…`. If it says `false`, our boost doesn't compose with the base worker boost. Also check whether the industry window shows a productivity change. |
| R11 Teal defs in game | Any Teal error mentioning `QuotaRun…` types or `quota_types.d.tl` in `stdout.txt`. |
| R12 mod removal | Not part of this test. Don't remove the mod from a save with an active run. |
| R13 player vehicles | Does `vehicleMods … sent=N` match your vehicle count? `sent=0` with vehicles present means the `requireOwnedByPlayer` filter excludes the player's fleet. |
| Perf | Any hitch when a speed card is picked with a large fleet (it should be spread over frames, 200 events per frame), or at run end (`clearEffects`). |
| Missions (safety) | Optional: start a campaign mission with the mod enabled. Expect either no `[QuotaRun]` lines, `inert: … in a mission`, or `deactivated: initMission`, and **no** HUD. |
| Map editor (safety) | Optional: open the map editor with the mod enabled. Expect `inert: … in the map editor` or nothing, and no HUD. |

## 7. Expected log lines (reference)

`activated`, `round N started`, `notify <key> {…}`, `month N: round=… progress=…/… statsDelta=… balance=… redMonths=… phase=…`, `round N cleared: … reward=…`, `cash <amount>`, `phase <a> -> <b> (<why>)`, `paused (savedSpeed=…)`, `resumed at speed …` / `resume skipped: …`, `picked <id>: …`, `vehicleMods rev=… sent=…`, `industryMods count=… chosen=… sent=…`, `industryMods probe: …`, `clearEffects: vehicles=… industries=…`, `run over: reason=…`, `deactivated: initMission|initTutorial`, `re-initialising the run on initNewGameFromMap`, `inert: …`. Rejected events log as warnings (`pickCard ignored …`).
