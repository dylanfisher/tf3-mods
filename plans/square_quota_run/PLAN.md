# Quota Run: a roguelike loop for Transport Fever 3

| | |
|---|---|
| Mod ID | `square_quota_run` |
| Display name | Quota Run |
| Mod folder | `mods/square_quota_run/` |
| Plan folder | `plans/square_quota_run/` (this folder; never shipped) |
| Research | [`RESEARCH.md`](RESEARCH.md), plus the source citations added in review (§8). Where they disagree, this plan wins. |
| Status | Phases 1–4 done offline (2026-10-03); in-game dev panel added (§8 item 17). Roguelike v2.1 + the §9.9 playtest probes done offline (§8 item 18): check, test and validate are green. Next: playtest ([`TESTING.md`](TESTING.md), incl. "v2 probes"). Balance tooling: [`SIMULATOR.md`](SIMULATOR.md). |

Citation shorthand (same as RESEARCH.md): `API` = `.cache/game/api/tealdef`, `BT` = `.cache/game/base/tealdef`, `BC` = `.cache/game/base/content`, `MOD` = `.cache/game/mods/release`, `WIKI` = `docs/wiki/modding`.

## 1. Pitch

Quota Run turns a normal free game into a run. Every **round** (24 in-game months by default) the company must move an escalating **quota** of goods and passengers. When a round ends, the game pauses and the player **drafts 1 of 3 cards**. Cards are boons, or boons tied to a curse, and they reshape the economy: faster fleets, booming industries, cash injections, a lower or higher quota, more time. If you miss a quota or stay in the red too long, the **run ends**. An end screen shows the score (rounds survived and total units moved). The player can then keep playing the map as a normal sandbox.

Design pillars:

1. **Pressure.** The quota always grows faster than a lazy network, so you have to expand or optimise.
2. **Meaningful choices.** Cards trade short-term relief for long-term pain, or the reverse.
3. **Every run is different.** Random map, random card offers, synergies.
4. **Zero collateral.** The mod does nothing in any game that didn't start a run with it enabled.

## 2. Hard rules (non-negotiable)

1. **Don't touch existing games.**
   - The game script stays inert unless its own state has `active == true`. In inert mode `update` returns after one `state:get()` nil/flag check, `handleEvent` ignores everything except the activation events below, and the script **never subscribes to any event**.
   - Activation happens only in `handleEvent` with `id == ""` and `name == "initNewGame"` or `name == "initNewGameFromMap"`, and only when all of these hold:
     - `state:get()` is nil or has no `active` field (idempotent: a second init event is ignored);
     - `not api.engine.util.hasStartedAsMission()` (`API/api/engine/util.d.tl:1036`; base uses the same guard in `BC/game_mechanics/company/company_growth.script.tl:77`);
     - our own `GAME_SCRIPT` component has `addedToExistingSavegame ~= true` (`API/api/engine.d.tl:401-412`). Belt and braces: an old save never receives `initNewGame`, it receives `handleLegacy`.
   - `initMission`, `initTutorial` and `handleLegacy` never activate. `handleLegacy` on an **active** save only re-subscribes (see §4.2). Phase 4: `initMission`/`initTutorial` on an **active** run deactivate it (§4.6), and nothing activates in the map editor.
   - `mod.json` sets `severityAdd` and `severityRemove` to `"Critical"` (`WIKI/general/moddefinition.md:43-65`), so the game warns before anyone adds the mod to, or removes it from, a save. `cosmetic` stays false (it changes the simulation).
2. **No global side effects.**
   - Never call `api.util.setAppConfig`/`saveAppConfig`, never write files, never use `io.*`/`os.*`, and never touch `settings.lua`.
   - Never modify base-game files or `api.res` resources. This mod needs no `runFn`/`postRunFn`.
   - Global Teal type names declared in our `.d.tl` files are shared by every loaded mod, so every global record is prefixed `QuotaRun` (e.g. `QuotaRunState`).
3. **All run state lives in `GameScriptState`** (`state:get()/set()`). Module-level variables may only hold constants and caches that can be rebuilt; they leak across loads in one session (cf. the `isInitialized` module flag in `BC/game_mechanics/arrival_tracker/arrivaltracker.script.tl:67`).
4. **Cooperate with base systems.**
   - Vehicle modifiers go through the base `VehicleModifier` / `ChangeModifier` event, never through raw `makeVehicleSetModifiersCmd` (§6 Phase 2).
   - Industry productivity changes compose with the base worker-boost logic as specified in §6 Phase 2.
5. **The game never sees the plan or tests.** `plans/` and `tests/` live outside `mods/`, so only `mods/square_quota_run/` is symlinked and uploaded.
6. **Never launch or drive the game from automation, and never edit anything under the game install or userdata.** The one exception is the hub's own `make link`, which adds a symlink to `staging_area`. A linked mod does nothing until the user ticks it for a new game. Tools may *read* the install (e.g. `tl.lua`) but prefer the extracted copy in `.cache/game/`.

## 3. Game loop

```
 New free game (mod enabled)
        │ initNewGame / initNewGameFromMap (not a mission)
        ▼
 ┌─────────────┐  each update: progress, month tick (bankruptcy), effect scans
 │   RUNNING   │◄───────────────────────────────────────────────┐
 └─────┬───────┘                                                 │
       │ gameTime ≥ roundEndTime                                 │
       ▼                                                         │
  progress ≥ quota? ──no──► ┌─────────┐ "Continue as sandbox"    │
       │ yes                │  ENDED  │──────────► SANDBOX (inert, HUD hidden)
       ▼                    └─────────┘  (effects removed on entering ENDED)
  pay reward, start round r+1 immediately (clock running),
  draw offer, pause game
       ▼
 ┌─────────────┐ player picks 1 of 3 cards (game paused; may unpause, clock runs)
 │  CHOOSING   │─ apply card to the round that just started, restore speed ─┘
 └─────────────┘
```

**Why the next round starts immediately:** the player can always unpause from the game bar while the picker is open. If the round clock stopped during `choosing`, unpausing would be free time. So round r+1 begins at the deadline (baseline snapshot and `roundStartTime` taken then), `choosing` is only a pending pick, and the picked card applies to the round already in progress (its quota and length are recomputed). The HUD marks the quota "provisional" until the pick.

### 3.1 Rules (defaults; all live in `quota_config.tl`)

| Rule | Default |
|---|---|
| Time base | **Game time, not the calendar.** A "month" is `api.util.getDefaultMonthDuration()` game-time units (`API/api/util.d.tl:114-116`), compared against `GAME_TIME.gameTime` (`API/api/engine.d.tl:424-438`). Reason: calendar speed is player-configurable down to 0 (`BC/gui/game_bar/game_bar_widgets.tl:351`, factors 0.0–4.0); a frozen calendar would never end a round, and fast calendars would shrink rounds. Simulation pace (vehicles, production) runs on game time, so this is also the fair measure. The HUD shows "months left" in these default months. |
| Round length | 24 default months (`ROUND_MONTHS`). Round 1: 36 (`FIRST_ROUND_MONTHS`). Stored as absolute `roundStartTime`/`roundEndTime`. |
| Quota metric | Units delivered this round, counted by our own event counter: `+#param.entities` for `id == "SimCargoSystem", name == "OnToArriveAtDestination"` (cargo) and `id == "SimPersonSystem", name == "OnCompletedLineUsage"` (passenger line trips). Same events and param shapes as `BC/game_mechanics/arrival_tracker/arrivaltracker.script.tl:115-125` and `BC/game_mechanics/achievements/achievements.script.tl:221-225`. Diagnostic only: log the Δ of `getTransportedData()` (`API/api/engine/util.d.tl:896-898`) monthly so the playtest can compare. `quota_config.METRIC` (`"events"`/`"stats"`) switches the source if events turn out wrong. |
| Cargo weight | `CARGO_WEIGHT = 1`, `PASSENGER_WEIGHT = 1` (config). Passenger trips are far more numerous than cargo units in most networks; tune after the first playtest. |
| Quota formula | `quota(r) = max(1, round(BASE_QUOTA * GROWTH^(r-1) * quotaMultAll * quotaMultRound))`, `BASE_QUOTA = 2500`, `GROWTH = 1.6`. Placeholder numbers: Phase 1 logs monthly delivered counts so the playtest can calibrate. |
| Round reward | Cash = `round(REWARD_BASE * r * rewardMult)`, `REWARD_BASE = 2_000_000`, plus `+50%` if progress ≥ 150% of quota. Journal entry, type `OTHER`. |
| Bankruptcy | At each month tick (every `getDefaultMonthDuration()` of game time since run start), if balance is not nil and `balance < 0`, `redMonths += 1`; else `redMonths = 0`. `redMonths >= 6` ends the run (`endReason = "bankrupt"`). Loans are allowed and are the intended escape hatch: the base loan system caps borrowing (`BC/game_mechanics/finance/loan.script.tl`), so a failing company still goes under. If balance is nil (infinite money, `API/api/engine/util.d.tl:857-861`) the check is skipped and the HUD shows "∞". |
| Score | Rounds cleared, plus total units across all rounds. |

### 3.2 Cards (MVP set: 12)

Effect kinds, chosen to keep the engine surface small. "Round" below always means **the round that just started** (see §3).

| kind | Effect | Mechanism |
|---|---|---|
| `cash` | ± money now, `amount * r` | `makeJournalBookAssetCmd`, type `OTHER` (`MOD/urbangames_campaign_mission_08/content/mission/mission_story.tl:1012-1020`) |
| `quotaMultRound` | Multiplies this round's quota (recomputed on pick) | state |
| `quotaMultAll` | Multiplies this and all future quotas | state |
| `roundMonths` | ± months on this round (`roundEndTime` moves; never earlier than now + 3 months) | state |
| `vehicleMod` | Run-wide TopSpeed/Comfort/Pollution/Noise multiplier, aggregated as `1 + Σ(v-1)` (same rule as the base, `BC/vehicle/vehicle_modifier.script.tl:3-23`) | `ChangeModifier` event with our single id, all player vehicles including future ones |
| `industryProd` | Productivity multiplier on N random industries, or all of them; multiple cards on one industry multiply | `makeStockListSetModifiersCmd`, composed with the base worker boost |
| `rewardMult` | Multiplies future round rewards | state |

| id | Name | Effects |
|---|---|---|
| `venture` | Venture Capital | cash +$4M × round |
| `hostile_loan` | Hostile Loan | cash +$12M × round; quotaMultRound ×1.3 |
| `express` | Express Timetables | vehicleMod TopSpeed 1.15 |
| `overdrive` | Overdrive | vehicleMod TopSpeed 1.30, Pollution 2.0, Noise 1.5 |
| `luxury` | Luxury Fleet | vehicleMod Comfort 1.30 |
| `boomtown` | Boomtown | industryProd ×1.5 on 3 random industries |
| `industrial_policy` | Industrial Policy | industryProd ×1.15 on all industries; cash −$3M × round |
| `lean_year` | Lean Year | quotaMultRound ×0.8 |
| `extension` | Deadline Extension | roundMonths +6 |
| `crunch` | Crunch Time | roundMonths −6; rewardMult ×1.5 |
| `austerity` | Austerity | cash −$5M × round; quotaMultAll ×0.85 |
| `gamble` | Double or Nothing | quotaMultRound ×1.5; rewardMult ×2 |

Balance notes:
- `vehicleMod` stacks additively and is uncapped in the MVP; cap each key at `VEHICLE_MOD_CAP = 2.0` in config to stop runaway TopSpeed (base engine behaviour at very high scales is untested).
- `industryProd` values are always ≥ 1.0 in the MVP. Values < 1.0 would confuse the base worker script's `> 1.0` boosted test (`BC/industries/industry_workers.script.tl:8`); don't add productivity curses without revisiting §6 Phase 2.
- A cash curse may push the balance negative; that only starts the 6-month red counter, never ends the run immediately.

Offers: 3 distinct cards, drawn from a deterministic LCG whose state is stored in `rngSeed`. Initial seed: `gameTime` at activation mixed with a constant (no `math.random`, which base code reseeds, see `BC/industries/industry_productivity_util.tl:70`). Save-scumming the pick screen gives the same offer.

## 4. Architecture

```
mods/square_quota_run/
  mod.json                          severityAdd/Remove = Critical, cosmetic false, no run hooks
  _metadata/modinfo.json            name, summary, tags ("Script Mod" + one gameplay tag from WIKI/general/modtags.md)
  tealdef/                          editor-only (Phase 4, official layout as MOD/urbangames_campaign_mission_08/tealdef):
    square_quota_run_def.d.tl  require "quota.quota_types"
    quota/quota_types.d.tl          byte-identical copy of content/quota/quota_types.d.tl (tl_check flags drift)
  strings.json                      optional; en only for MVP
  content/quota/
    quota.gs.lua                    updateScript + handleEventScript -> quota.script@update / @handleEvent
    quota.script.tl                 sim thread: thin adapter (engine reads, event routing, intent execution)
    quota_logic.tl                  PURE logic: state machine, quota math, RNG, offers, card resolution.
                                    No `api.*`, no `ug_require` of game modules -> unit-testable offline.
    quota_cards.tl                  card definitions (data only)
    quota_config.tl                 tunables (incl. DEBUG, METRIC, weights, caps)
    quota_effects.tl                engine side effects: cash, pause/resume, vehicle mods, industry mods, notify
    quota_types.d.tl                ALL global records, prefixed QuotaRun* (state, intents, inputs, cards, module interfaces; §4.5)
    gui/
      quota_hud.res.lua             type = "react-plugin ::MainModButtonAreaExtension" (Phase 3 deviation, §8 item 15)
      quota_hud.script.tl           compact HUD; picker + end screen in a dialog window (Phase 4, §4.6)
      quota_hud_model.tl            pure view model (Phase 3)
      quota_hud.css.lua             styles
    notify/
      quota_notification.res.lua    type = "notification" (basename MUST match the .script, see below)
      quota_notification.script.tl  NotificationType: useDataState(params) -> {title, description, icon}
tools/tl_check.py                   offline Teal type-check (lupa + the game's tl.lua, patched in memory)
tests/run_tests.py                  offline test runner (lupa; transpiles .tl, runs tests)
tests/square_quota_run/        unit tests for quota_logic
```

Path rules (verified):
- `ug_require "/x.tl"` resolves against the **current mod's** content root; base files use it for base modules because they *are* the base (`BC/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.script.tl:1-6`). A mod must write `ug_require "::/gui/main/react.lua"` etc. for base modules, and `"/quota/quota_logic.tl"` (or `"square_quota_run::/quota/quota_logic.tl"`) for its own.
- Game-script name for `getEntityForGameScript`: `"square_quota_run::/quota/quota.gs"` (mod pattern: `MOD/urbangames_campaign_mission_08/content/mission/mission_story.tl:891`, file `content/mission/rocket/rocket.gs.lua`; base pattern `"::/industries/industry_workers.gs"`, `BC/industries/industry_productivity_util.tl:6`).
- Notification type string: `"square_quota_run::/quota/notify/quota_notification.script"`. The notification system finds the `.res` by replacing `.script` with `.res` (`BC/game_mechanics/notifications/notification_util.tl:13-21`), so both files must share the basename and folder.

### 4.1 State contract (`QuotaRunState`, stored via `state:set`)

Frozen at the end of Phase 1 in `quota_types.d.tl`. Phases 2 and 3 may only *read* it (Phase 2 may add fields under `fx`, which Phase 1 declares).

```teal
global record QuotaRunState
  version: integer            -- schema version, starts at 1
  active: boolean             -- nil = inert (existing saves); true for the whole run, incl. ended/sandbox
  phase: string               -- "running" | "choosing" | "ended" | "sandbox"
  rngSeed: integer            -- LCG state
  round: integer              -- 1-based, the round in progress
  roundsCleared: integer
  runStartTime: integer       -- gameTime at activation
  roundStartTime: integer     -- gameTime
  roundEndTime: integer       -- gameTime deadline
  nextMonthTick: integer      -- gameTime of next bankruptcy/month tick
  quota: integer              -- current round's quota (recomputed on pick)
  progress: integer           -- weighted units delivered this round (event counter)
  statsBaseline: integer      -- getTransportedData() sum at round start (diagnostic / METRIC="stats")
  totalTransported: integer   -- across completed rounds
  redMonths: integer
  quotaMultAll: number
  quotaMultRound: number      -- reset to 1.0 at each round start
  rewardMult: number
  offer: {string}             -- 3 card ids while phase == "choosing", else nil
  picked: {string}            -- history of card ids, in order
  endReason: string           -- "quota" | "bankrupt" (nil while running)
  lastReward: integer
  savedSpeed: integer         -- GAME_SPEED.speedup before our pause (0 => restore as 1)
  fx: QuotaRunFxState         -- owned by quota_effects (Phase 2)
end

global record QuotaRunFxState
  vehicleMods: {string: number}          -- aggregated TopSpeed/Comfort/Pollution/Noise, absent = 1.0
  vehicleModsRev: integer                -- bumped whenever vehicleMods changes
  vehicleApplied: {integer: integer}     -- vehicle entity -> vehicleModsRev last sent
  industryMods: {integer: number}        -- stock-list entity -> our multiplier (>= 1.0)
  nextScanTime: integer                  -- gameTime of next vehicle/industry scan
end
```

Integer-keyed maps are safe in `GameScriptState`: base scripts store entity-keyed maps the same way (`BT/vehicle/vehicle_modifier.d.tl:15-17` `modificationMap : {Engine.Entity : ...}`, `BC/industries/industry_workers.script.tl:37,108` `industriesState[entity]`). Values must be plain data (numbers, strings, booleans, nested tables); no functions or userdata.

The GUI reads state with:
```lua
local e = api.engine.system.gameScriptSystem.getEntityForGameScript("square_quota_run::/quota/quota.gs")
local gs = e and api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)  -- Engine.Component.GameScript<QuotaRunState>
local s = gs and gs.state                                                           -- nil-safe at every step
```
(pattern: `BC/gui/hud/greenification_display.script.tl:89-91`).

### 4.2 Event contract (GUI or console → sim)

All events: `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", <name>, param))` (`API/api/cmd.d.tl:788`). Names are namespaced like the base's `"company.lockPermits"` (`BC/game_mechanics/company/company.script.tl:385-386`) so other mods' generic names can't collide. The sim subscribes to each name **on activation**, and on `handleLegacy` when `state.active` (call `subscribeToNoEvents()` first, then re-subscribe, as `BC/game_mechanics/subventions/subventions.script.tl:381-383` does). It always also checks `id == "QuotaRun"`.

| name | param | Valid in phase | Effect |
|---|---|---|---|
| `QuotaRun.pickCard` | `{index: integer}` (1-3) | `choosing` | apply `offer[index]`, phase → `running`, resume speed |
| `QuotaRun.continueSandbox` | `{}` | `ended` | phase → `sandbox`, resume speed |
| `QuotaRun.debug` | `{op: string, n?: integer, id?: string}` | any active, `DEBUG == true` only (`forceStart`/`dump` also inert, see below) | see the debug-op table below |

**Debug ops** (`QuotaRun.debug`, all gated by `quota_config.DEBUG`; invalid ops or parameters are logged as warnings and change nothing). Sent by the console or the in-game dev panel (§4.6).

| op | param | phases | effect |
|---|---|---|---|
| `endRound` | | active | `roundEndTime = now`; judged on the next unpaused `update` |
| `addProgress` | `n` | active | `progress = max(0, progress + n)` |
| `addQuotaPct` | `n` (−1000..1000, ≠0) | active | `progress += round(quota · n / 100)` (dev panel +25% / +100%) |
| `setMonthsLeft` | `n` | active | `roundEndTime = now + n months`; judged on the next unpaused `update` |
| `bankrupt` | | active | `redMonths = BANKRUPT_MONTHS - 1`: the next red month tick ends the run |
| `offer` | | running/choosing | draw an offer, phase → `choosing`, pause |
| `passRound` | | running/choosing | `progress = max(progress, quota)`, `roundEndTime = now`, judged **now** (reward, `choosing`, pause; next round starts now; a pending offer is forfeited) |
| `failRound` | | running/choosing | `progress = 0`, judged now → `ended` (quota), clearEffects, pause |
| `skipMonths` | `n` (1..240) | running/choosing | `runStartTime`, `roundStartTime`, `roundEndTime`, `nextMonthTick` all move back n months, then `tick(now, balance)` runs now: n month ticks with the **current** balance (red: `redMonths += n`, bankruptcy possible; black: reset), and the round is judged if its deadline falls inside the span (month first on ties; a failed round stops the catch-up). No deliveries for the skipped months; money and the calendar don't move. |
| `applyCard` | `id` | running/choosing | the same `applyCard` resolution as `pickCard`, without an offer: phase, offer and speed untouched; appended to `picked` like a real pick (log: `debug applyCard <id> (no offer used)`) |
| `addMoney` | `n` (±1e12, ≠0) | active | `cash` intent of `n` |
| `clearEffects` | | active | `clearEffects` intent; phase and quota/reward multipliers stay |
| `reset` | | active | new state from `activate(now, seed = oldSeed + now)`; the old `fx`/`savedSpeed` ride along so the leading `clearEffects` (+ `resume` if the old phase was `choosing`/`ended`) undo the old run's engine effects |
| `forceStart` | | **inert only** (adapter) | activate even if `addedToExistingSavegame`; refused in the map editor, in a mission (`hasStartedAsMission`), on a deactivated state (`active == false`), and by the logic on an active run (use `reset`). Logs a loud warning. |
| `dump` | | active or inert | log the state (v2: plus a `dump v2:` line and, adapter-side, the mod params, P7) |
| `setRule` | `id` | active | v2: set the round's scoring rule (draws its target); `""`/`"none"` clears; quota recomputed |
| `setBoss` | `id` | active | v2: make the round in progress a boss round now (rule + temporary vehicle mods); `""` clears |
| `setNextBoss` | `id` | active | v2: announce this boss for the next round (refused unless round+1 is a boss round); `""` clears |
| `incomeProbe` | `n` (mult×100, 0 = off) | active, adapter | v2 P1: return `{[0] = n/100}` from `OnCalcTicketPrice`, log the first 10 params |
| `factsProbe` | `n` | active, adapter | v2 P2: log the resolved facts of the next n deliveries |
| `jumpYears` | `n` | active, adapter | v2 P3: `makeGameSetDateCmd` +n years (irreversible) |
| `closeIndustry` | `n` months | active, adapter | v2 P4: closure countdown on one closable industry |
| `townProbe` | | active, adapter | v2 P6: log one town's `TOWN` component |

Engine events the sim subscribes to when active: `OnToArriveAtDestination`, `OnCompletedLineUsage` (metric). Invalid events (wrong phase, bad index) are logged and ignored, never error.

### 4.3 Effect-intent contract (logic → adapter)

`quota_logic` never calls the engine. Every logic entry point has the shape
`fn(state: QuotaRunState, input: <record>) : QuotaRunState, {QuotaRunIntent}` and the adapter (`quota.script.tl`) executes the intents in order via `quota_effects`.

```teal
global record QuotaRunIntent
  kind: string   -- "cash" | "pause" | "resume" | "notify" | "vehicleMods" | "industryMods" | "clearEffects" | "log"
  amount: integer            -- cash
  key: string                -- notify: "roundStart" | "roundCleared" | "halfway" | "bankruptWarn" | "runOver"
  params: {string: any}      -- notify params (numbers/strings only; text is built in the notification script)
  industryCount: integer     -- industryMods: N random (nil = all)
  mult: number               -- industryMods multiplier
  message: string            -- log
end
```

Logic inputs (frozen in Phase 1): `activate{gameTime, seed}`, `tick{gameTime, balance (nil = infinite), statsTotal}`, `delivered{units}`, `pickCard{index, gameTime}`, `continueSandbox{}`, `debug{op, n, gameTime}`. `vehicleMods` intents carry no payload: the adapter reads the new aggregate from `state.fx.vehicleMods` (logic updates it and bumps `vehicleModsRev`). For `industryMods`, choosing *which* industries needs the engine, so the logic emits the intent and `quota_effects` picks entities with the state LCG and writes `fx.industryMods`.

Phase 1 ships `quota_effects` as stubs that execute `cash`, `pause`, `resume`, `log` for real and only log the rest; Phase 2 replaces the stubs without touching the intent format.

### 4.5 Phase 1 contract additions (frozen)

Everything below is in `content/quota/quota_types.d.tl`. Phases 2 and 3 code against it as is.

- **One definition file.** Every `QuotaRun*` record (state, intents, inputs, cards, and the module interfaces `QuotaRunConfig`, `QuotaRunCards`, `QuotaRunLogicModule`/`QuotaRunLogic`, `QuotaRunEffects`) lives in `quota_types.d.tl`. There are no per-module `.d.tl` files. Reason: the records depend on each other, the offline checker loads `.d.tl` files in alphabetical order, and the game's load order is unknown. Splitting them failed with "unknown type".
- **State fields added:** `monthDuration: integer` is `getDefaultMonthDuration()` at activation, so the logic stays engine-free and the GUI can compute months left as `(roundEndTime - gameTime) / monthDuration`. `halfwayWarned: boolean` means the halfway notify was already emitted this round. `totalTransported` also includes the final (failed) round's progress once the run ends, so the end screen can show it directly.
- **Intent field added:** `level: string` on `log` intents, either `"message"` (the default) or `"warning"`. Rejected events log as warnings.
- **Input records:**
  - `QuotaRunActivateInput{gameTime, seed, monthDuration, statsTotal?}`
  - `QuotaRunTickInput{gameTime, balance?, statsTotal?}`
  - `QuotaRunDeliveredInput{units, kind}`, where `kind` is `"cargo"` or `"passenger"` and selects the weight
  - `QuotaRunPickInput{index, gameTime}`
  - `QuotaRunContinueInput{}`
  - `QuotaRunDebugInput{op, n?, gameTime}`
- **Card records:** `QuotaRunCard{id, name, description, effects}` and `QuotaRunCardEffect{kind, amount?, mult?, months?, mods?, count?}`. A `cash` amount is per round number. `name` and `description` are plain English, and the GUI wraps them in `_()`. The draw order depends on the order of `cards.list`, so append new cards at the end.
- **Logic is a factory:** `(ug_require "/quota/quota_logic.tl" as QuotaRunLogicModule).new(config, cards) : QuotaRunLogic`. `quota_logic.tl` therefore contains no `ug_require` at all, which satisfies the Phase 1 grep. Entry points are `activate`, `tick`, `delivered`, `pickCard`, `continueSandbox` and `debug`, each `fn(state, input) : state, {intent}`; the state is mutated in place and returned. Pure helpers: `isActive`, `computeQuota(state, round)`, `computeReward(state, round, progress, quota)`, `mixSeed`, `rngNext(state, n) : 1..n` (advances `state.rngSeed`; Phase 2 uses it to pick industries), `drawOffer`, `monthsLeft(state, gameTime)` and `dump`. The LCG is Park–Miller (`seed * 48271 % (2^31-1)`), which is exact with both integers and doubles.
- **Effects interface (`QuotaRunEffects`):**
  - `run(state, intents)` dispatches in order.
  - `onUpdate(state, gameTime) : boolean` is called every unpaused frame while the phase is `running`/`choosing`, and returns true if it changed `state`. It is the hook for the Phase 2 periodic scans.
  - There is one handler per kind: `cash`, `pause`, `resume`, `notify`, `vehicleMods`, `industryMods`, `clearEffects` and `log`, each `(state, intent)`.
  - `pause` saves `GAME_SPEED.speedup` into `savedSpeed` only if it is > 0, so a second pause keeps the earlier value.
  - `resume` restores the speed only if the game is still paused, and always resets `savedSpeed` to 0.
- **Subscriptions follow the phase.** After `subscribeToNoEvents()`, the three `QuotaRun.*` events are always subscribed. `OnToArriveAtDestination`/`OnCompletedLineUsage` are subscribed only in `running`/`choosing`. This is redone on activation, on every phase change, and on `handleLegacy` when active.
- **Behaviour details fixed in Phase 1:**
  - Month ticks and round ends that elapsed since the last update are processed in time order, with the month tick first on ties.
  - If a deadline passes while still `choosing`, the round is judged normally, and on a pass the pending offer is replaced (forfeited, logged).
  - A `roundMonths` cut never extends the round: `new = max(end + Δ, min(end, now + 3 months))`.
  - `debug endRound`/`setMonthsLeft` only move `roundEndTime`; the transition happens on the next unpaused `update`.
  - `debug bankrupt` sets `redMonths = BANKRUPT_MONTHS - 1`.
  - `debug offer` only works in `running`/`choosing`.
  - `update` reads balance and stats, and calls `tick`, only when a month tick, the deadline or the halfway point is due (or every frame with `METRIC = "stats"`).

### 4.6 Phase 2–4 contract additions

- **Phase 2:** `QuotaRunNotificationParams` (in `quota_types.d.tl`) types the notification `params`: `key` plus the intent's params.
- **Phase 3:** `QuotaRunHudCard`, `QuotaRunHudView` and `QuotaRunHudModel` are appended to `quota_types.d.tl`.
- **Phase 4 config:**
  - `VEHICLE_SENDS_PER_FRAME = 200` caps `ChangeModifier` events per scan or clear call.
  - `GUI_INLINE_PICKER = false` selects the GUI layout.
- **Phase 4 lifecycle (adapter):**
  - `initMission`/`initTutorial` on an **active** state: `clearEffects`, then `resume` if the phase was `choosing`/`ended`, then `subscribeToNoEvents()` and `state:set({version, active = false})`. This state is inert and "already decided", so it never activates again. On an inert state these events write nothing.
  - `initNewGameFromMap` on an **active** state re-initialises the run fresh, but only after the gates (map editor, mission, `addedToExistingSavegame`) pass. This also re-sends the round-1 `roundStart` notification, which the base notification script may wipe on that event (`BC/game_mechanics/notifications/notifications.script.tl:695-699`). A state with `active = false` is never revived.
  - New activation gate: never in the map editor, `api.engine.config.getModParams()[""]["isMapEditor"]` (`BC/game_mechanics/company/company_growth.script.tl:74`, `API/api/engine.d.tl:1807`).
- **Phase 4 effects:**
  - `scanVehicles` and `clearVehicles` send at most `VEHICLE_SENDS_PER_FRAME` events per call. When capped, `fx.nextScanTime` is set due (`0` from an intent, `now` from `onUpdate`), so the work continues on the next unpaused frame.
  - `clearEffects` empties `fx.vehicleMods` and bumps the rev, so a continuation only ever removes our entry.
  - `update` also calls `effects.onUpdate` in `ended`/`sandbox` while `fx.vehicleApplied` is non-empty. Otherwise those phases stay a single `get()`.
  - Industries are still reset in one go: one direct command each, with no event fan-out.
- **Phase 4 perf decision:** no `state:get_native()`. It is declared (`BT/scripts/gamescript.d.tl:43`) but used nowhere in base or official mods. `update` does one `get()` per frame and `set()` only on change, as the base `vehicle_modifier`/`arrivaltracker` scripts do. Deliveries do one `get()`/`set()` per event, like `arrivaltracker.script.tl:112-131`. Buffering them in module state would break rule 2.3.
- **Dev panel (2026-10-03), DEBUG only:**
  - `QuotaRunDebugInput` gained `id` (applyCard), `balance` (skipMonths month ticks) and `statsTotal` (stats baseline for passRound/skipMonths/reset). The adapter fills them from the event param (`id` only if it is a string, `n` only if integral) and the engine.
  - New ops: see the debug-op table in §4.2. All go through the existing `QuotaRun.debug` event.
  - **Inert escape hatch (rule 2.1 exception, explicit and user-triggered).** With `DEBUG == true` only: `update` on an *undecided* inert state (nil, or no `active`) subscribes to `QuotaRun.debug` once (`if not state:hasEventSubscriptions()`, the base pattern in `BC/industries/industry_workers.script.tl:19-20`). It writes no state and subscribes to nothing else. `handleEvent` on an inert state accepts only `QuotaRun.debug`: `forceStart` (gates: not map editor, not `hasStartedAsMission()`, not `active == false`; `addedToExistingSavegame` is deliberately bypassed; loud warning) and `dump` (read-only log). Every other op logs a warning. A deactivated state (`active == false`) never subscribes. With `DEBUG == false` the inert path is byte-for-byte the old one: no subscription, no write, no log (test: `test_adapter.lua`, "release (DEBUG = false): an existing save is never touched"). Note: the subscription itself may be stored in a DEBUG-build save; it is harmless and dropped by `subscribeToNoEvents()` on activation.
  - **HUD model:** with `DEBUG == true`, `build` returns a `phase = "inert"` view for a nil/undecided state and a `phase = "sandbox"` view, both carrying only `debug`/`fxSummary` and zeroed numbers, so the **Dev** button stays reachable. In-play views get `debug = true` and `fxSummary`. With `DEBUG == false` the views are unchanged (`debug`/`fxSummary` nil, inert/sandbox nil; `test_hud_model.lua` runs its old tests with `DEBUG = false`).
  - **GUI:** a custom window `QuotaRunDevWindow` (a `react.RegisterWrapperRecipe` around `builtin.Window`, like `BC/gui/menu/main_page.tl:44-63`) with a polling content recipe `QuotaRunDevPanel`, not `DialogWindow`: DialogWindow buttons always call `onClose` first and lay out in one row (`BC/gui/menu/dialog_react_util.tl:89-93,103-116`), so it could neither stay open nor group buttons. `GUI_INLINE_PICKER = true` renders the same rows inline under a Dev toggle (`react.useState`).

### 4.4 Threading and pausing

- **Sim thread** (`quota.script.tl`): the only place that mutates state or sends engine commands. Commands here run immediately (`API/api/cmd.d.tl:1-9`). Sending `makeGameSetSpeedCmd` from a game script is base practice (`BC/game_mechanics/company/company.script.tl:403`).
- **GUI thread** (`quota_hud.script.tl`, `quota_notification.script.tl`): read-only. The HUD polls with `engine_react_util.useStepStateTimer(getFromEngine, interval?, equalsFn?)` (`BT/gui/main/engine_react_util.d.tl:20-24`; default interval 0.5 s, default equality `table_util.deepEquals`, `BC/gui/main/engine_react_util.tl:126-145`). `getFromEngine` must return a small, fresh table (copy the fields the HUD needs) so deep-equals is cheap. The GUI only sends `QuotaRun.*` events.
- **Pausing:** at round end the sim stores `GAME_SPEED.speedup` (`API/api/engine.d.tl:415-422`) in `savedSpeed`, then sends `makeGameSetSpeedCmd(0)`. `pickCard`/`continueSandbox` restore `savedSpeed`, or 1 if it was 0, **only if the game is still paused** (if the player already unpaused, leave their speed alone).
- While paused, `update` is called with `dt == 0` (the base checks for it, e.g. `BC/industries/industry_workers.script.tl:22`), and the simulation still ticks once per frame (`GameTime.tickCount`, `API/api/engine.d.tl:434-435`), so GUI events are processed while paused. Our `update` returns early when `dt == 0`; all paused-time transitions are event-driven in `handleEvent`.

## 5. Offline verification strategy

We can't run the game from automation, so we catch everything we can before the user tests.

1. **`tools/tl_check.py` + `make check MOD=…`. Feasibility proven in review** (§8): a PEP 723 script (`dependencies = ["lupa"]`) that:
   - uses `from lupa.lua54 import LuaRuntime` explicitly (the default `lupa` runtime is Lua 5.5, which differs from the game);
   - reads `.cache/game/base/content/base/tl.lua` (Teal `0.24.1+dev`, line 1; fall back to `<install>/base/content/base/tl.lua` via `hubconfig.game_install()`), and **patches it in memory, never on disk**, because Urban Games stubbed out module search (`UG_BEGIN_PATCH` at `tl.lua:6910` and `:6927`, and an early `return invalid` in `require_module` at `:6951-6957`). Two text replacements: delete the `else return a_type(w, "invalid", {}), false` branch in `require_module`, and un-comment the `io.open` lines in `search_for`. Assert each replacement matched exactly once so a game update that changes `tl.lua` fails loudly;
   - defines a stub `log` global (`log.error/warning/message` no-ops) before loading `tl.lua`;
   - sets `package.path` to `.cache/game/api/tealdef/?.lua;.cache/game/base/tealdef/?.lua;.cache/game/vscode-template/?.lua;mods/<id>/content/?.lua` and calls `tl.init_env(false, false, nil, {"all_def", <each mod .d.tl as a dotted module name>})` (`all_def.tl` is `require "api_def"; require "content_def"`, `.cache/game/vscode-template/all_def.tl`);
   - runs `tl.check_string(src, env, path)` on every `.tl` (not `.d.tl`) in the mod and prints `syntax_errors` + `type_errors` as `path:line: msg`; exit 1 on any error.
   In review, this exact setup type-checked `BC/vehicle/vehicle_modifier.script.tl`, `BC/industries/industry_workers.script.tl`, the transported game-bar plugin and `MOD/.../rocket/rocket.script.tl` with 0 errors, and reported all 3 planted errors in a broken file. `.lua` files (`*.gs.lua`, `*.res.lua`, `*.css.lua`) get a `load()` syntax check only.
2. **Unit tests for `quota_logic.tl`.** `tests/run_tests.py` reuses the same patched compiler: `tl.gen` (or `tl.process_string` + `tl.generate`) each `.tl` under `mods/<id>/content/quota/` that the tests need, installs a fake `ug_require` that maps `"/quota/x.tl"` to the transpiled module, and runs `tests/<modId>/test_*.lua` with a tiny assert harness. Cover:
   - quota formula incl. multipliers and the `max(1, …)` floor
   - activation is idempotent; no activation input → state untouched (inert)
   - round end on `gameTime ≥ roundEndTime`; pass → next round started immediately + `choosing` + offer + `pause` intent; fail → `ended` + `clearEffects` intent
   - bankruptcy counter: increments, resets, ends at 6, skipped when balance nil
   - card resolution for every effect kind, incl. `roundMonths` floor (now + 3 months) and `VEHICLE_MOD_CAP`
   - deterministic RNG; offers have 3 distinct ids; same seed → same offer
   - every event rejected in every wrong phase; bad `index` rejected
   - debug ops ignored when `DEBUG == false`
3. **`make validate MOD=mods/square_quota_run`** and a `tf3-mod-validator` review.
4. **A cross-check review** of every engine call against a cited source, with a final grep confirming no forbidden APIs (rule 2).

## 6. Phases

Each phase ends with its acceptance checks green. **Phases 2 and 3 run in parallel** once Phase 1 has frozen `quota_types.d.tl` (§4.1, §4.3) and the event names (§4.2). Phase 2 owns `quota_effects.tl` and `notify/`; Phase 3 owns `gui/`. Neither edits `quota_logic.tl`, `quota.script.tl` or `quota_types.d.tl`; if one needs a contract change, it stops and reports instead.

### Phase 0: Scaffold and tooling

- `make new-mod ID=square_quota_run NAME='Quota Run'` (no `--script`; we need no `mod.json` run hooks). Then fix `mod.json`/`modinfo.json`: severities Critical, `cosmetic: false`, summary, description, tags from `WIKI/general/modtags.md` (`Script Mod`, line 73, plus at most two more).
- Write `tools/tl_check.py` exactly as §5.1 and a `make check MOD=…` target.
- Write `tests/run_tests.py` (§5.2) and a `make test MOD=…` target.
- Add `plans/` and `tests/` to the `CLAUDE.md` layout (one line each), plus `make check` / `make test` under Commands.

**Accepted when:**
- `make check` passes on `BC/vehicle/vehicle_modifier.script.tl` (pass a file or dir argument for this) and fails, with line numbers, on a planted broken `.tl` in the scratchpad;
- `make test MOD=mods/square_quota_run` runs one trivial `.tl` module + test green;
- `make validate MOD=mods/square_quota_run` is green.

### Phase 1: Core simulation (logic + sim adapter)

**Status: done (2026-10-03).** `make check` and `make test` green (79 tests). `quota_types.d.tl` is frozen, including the additions listed in §4.5. See §8 item 14.

- `quota_types.d.tl` (all records in §4.1/§4.3, `QuotaRun*` prefixed), `quota_config.tl`, `quota_cards.tl`, `quota_logic.tl` (pure, signatures per §4.3).
- `quota.gs.lua` + `quota.script.tl`:
  - activation gating exactly per rule 2.1;
  - inert fast path (`update`: `local s = state:get(); if not s or not s.active then return end`);
  - subscriptions on activation and on `handleLegacy` when active (§4.2);
  - `update` (skip when `dt == 0`): read `GAME_TIME.gameTime`, feed `tick` to logic (logic handles round end and month ticks, and must catch up correctly if several month ticks elapsed since the last call);
  - `handleEvent`: route metric events to `delivered{units}`, `QuotaRun.*` to the logic;
  - read balance via `api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())`;
  - `quota_effects` stubs per §4.3 (real cash, pause, resume, log).
- Debug ops behind `quota_config.DEBUG` (default `true` until Phase 4).
- `log.message("[QuotaRun] …")` at activation, every phase transition, every month tick (progress, statsΔ, balance, redMonths) so playtests can be read from `stdout.txt`.
- Unit tests per §5.2.

**Accepted when:** `make check` and `make test` are green; there is at least one test per row of the §4.2 table and per transition in §3; `rg 'api\.|ug_require' content/quota/quota_logic.tl content/quota/quota_cards.tl content/quota/quota_config.tl` finds nothing; `quota_types.d.tl` is committed and announced as frozen.

### Phase 2: Effects and notifications (parallel with Phase 3)

- **Cash**: journal booking per §3.2 citation.
- **Vehicle mods** (verified against `BC/vehicle/vehicle_modifier.script.tl`):
  - The base script is a base-game game script present in every game; it subscribes to `ChangeModifier` on `initNewGame` (`:60-64`), so our mod needs no subscription for it.
  - Param shape `VehicleModifierChanger{entity, id, modifications: {Modification: number}}` (`BT/vehicle/vehicle_modifier.d.tl:3-13`); keys `TopSpeed|Noise|Pollution|Comfort`.
  - Same `id` **replaces** that id's entry (`:107`); identical resends are dropped by `deepEquals` (`:89-91`). Different ids add as `1 + Σ(v-1)` (`:3-23`). So use **one id**, `"square_quota_run"`, with our aggregate.
  - **Removal:** send `modifications = {}` (`:84-101`).
  - The base does **not** discover new vehicles; it only acts on the entity in each event, and drops entries for deleted entities (`:34-51`). So every `fx.nextScanTime` (every 1/4 default month) enumerate `api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE, {requireOwnedByPlayer = player})` (`API/api/engine.d.tl:1710-1713`) and send `ChangeModifier` for vehicles whose `vehicleApplied[e] ~= vehicleModsRev`; drop `vehicleApplied` entries for entities that no longer exist. A `vehicleMods` intent triggers an immediate scan; otherwise the periodic scan does the work.
  - `clearEffects`: send `modifications = {}` for every entity in `vehicleApplied`, then empty it.
- **Industry mods** (verified against `BC/industries/industry_workers.script.tl` and `BC/industries/industry_productivity_util.tl`):
  - The target entity is the **stock-list entity** `industry.stockList` from each `INDUSTRY` component (`API/api/engine.d.tl:441-445`); that is the entity whose `STOCK_LIST.modifiers.productivity` the base reads and writes (`industry_productivity_util.tl:50-56`, `industry_workers.script.tl:6-14`). `StockList.Modifiers` has only `productivity` (`API/api/engine.d.tl:1190-1196`).
  - There is no composition hook. The base sets productivity to either `getPersonCapacityPotentialBoost(e)` (1.5–2.5, `:58-72`) or `1.0`, and only when its visitor list changes and its view of "boosted" (`productivity > 1.0`) disagrees with the worker count (`industry_workers.script.tl:6-14`).
  - Composition rule: at every scan, for each `e` in `fx.industryMods`, `desired = (industry_productivity_util.isIndustryWorkersBoosted(e) and industry_productivity_util.getPersonCapacityPotentialBoost(e) or 1.0) * ours`; if `|current − desired| > 0.001`, send `makeStockListSetModifiersCmd(e, mods)` with `mods = api.type.StockList.Modifiers.new(); mods.productivity = desired`. Use `ug_require "::/industries/industry_productivity_util.tl"` so the boost math stays the base's. Trade-off: when the base resets an unboosted industry to 1.0, our multiplier is missing until the next scan (≤ 1/4 month). Document this in a code comment.
  - `clearEffects`: set each `e` back to the base value (`desired` with `ours = 1`), then empty `fx.industryMods`.
  - Skip entities that no longer exist or lack `STOCK_LIST`.
- **Notifications:** `quota_notification.res.lua` modelled on `BC/game_mechanics/company/company_notification_rank_up.res.lua` (`guiType`, `label`, `initiallyIgnoredType = false`) and `.script.tl` modelled on `company_notification_rank_up.script.tl` (`NotificationType<P>`, `useDataState(params)`; `BT/game_mechanics/notifications/notifications.d.tl:45-58`). Send with `makeScriptingSendEventCmd("", "Notifications", "add", {type = <§4 type string>, params = {key=…, …}, autoDismissDuration = …})` (`BC/game_mechanics/company/company_growth.script.tl:100-105`). Keys: `roundStart` (quota, months), `roundCleared` (reward), `halfway` (progress < 50% at 50% of time, once per round), `bankruptWarn` (`redMonths == 3`), `runOver` (reason, rounds). Text via `_()` + `lang_util.format` (`ug_require "::/scripts/lang_util.tl"`, `BT/scripts/lang_util.d.tl:4-5`) and `api.util.formatMoney` (`API/api/util.d.tl:58`) inside `useDataState`.
- Replace the Phase 1 stubs.

**Status: done (2026-10-03).** Added `QuotaRunNotificationParams` to `quota_types.d.tl` (§4.6). Tests: `test_effects.lua` and `test_effects_notify.lua`.

**Accepted when:** check and test green; every engine call has a `-- src: <file>:<line>` comment; a unit test (with a fake `api` table) covers the vehicle-scan bookkeeping (`vehicleApplied` rev logic, cleanup of dead entities) and the industry `desired` formula; `rg makeVehicleSetModifiersCmd mods/square_quota_run` finds nothing.

### Phase 3: GUI (parallel with Phase 2)

**Status: done (2026-10-03), with a deviation.** The plugin registers at `::MainModButtonAreaExtension`, not `::ModEntryPointExtension`. `game.tl` mounts ModEntryPoint plugins inside the `EntryPoints` node with `meta.class = "invisible"` (`BC/gui/main/game.tl:574-586`; `!invisible` is `visibility = "none"`, `BC/gui/main/default.css.lua:139-142`), so a HUD there can never be seen. MainModButtonArea is the visible mod slot in the top-left ridge (`game.tl:529-556`). Phase 4 then reworked the layout (§4.6). The text below is the original plan.

Model file-for-file on **`BC/gui/game_bar/game_bar_display_transported_plugin/`** (`.res.lua`, `.script.tl`, `.css.lua`): the smallest complete base plugin that polls engine state and renders text. No base or official-mod plugin targets `ModEntryPointExtension`; ours is the first, which is the main GUI risk (R1).

- `quota_hud.res.lua`:
  ```lua
  function data() return { type = "react-plugin ::ModEntryPointExtension",
    data = { filePath = "square_quota_run::/quota/gui/quota_hud.script@QuotaRunHudPlugin", order = 0 } } end
  ```
  The extension point id is exactly `"::ModEntryPointExtension"`: `BC/gui/main/mod_entry_point.tl:5` registers `getOwningModId() .. "::" .. "ModEntryPointExtension"` from the base (empty mod id), and `react.getPlugins` looks up resources of type `"react-plugin " .. id` (`BC/gui/main/react.lua:67-77,92-117`). `getPlugins` reads `desc.filePath`, `desc.order` and `desc.condition`; the base files' `priority` key is ignored, so use `order`.
- `quota_hud.script.tl`:
  - `local react = ug_require "::/gui/main/react.lua" as React`, `builtin = ug_require "::/gui/main/builtin.lua" as Builtin`, `engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil`, `mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl" as ModEntryPoint`, `lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil`.
  - `local QuotaRunHudPlugin = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "QuotaRunHudPlugin", function() : TreeNodeId … end)` and `return { QuotaRunHudPlugin = QuotaRunHudPlugin }` (the `@QuotaRunHudPlugin` in `filePath` names this key). The recipe takes no params (`ExtensionPoint0`, `BT/gui/main/mod_entry_point.d.tl:3-5`) and returns a `TreeNodeId` or `nil` (nil = render nothing; the transported plugin does this, `:24-26`).
  - Hooks first, unconditionally (React rules): `useStepStateTimer` with a `getFromEngine` that returns `nil` when the script entity/state is missing or `not active` or `phase == "sandbox"`, else a flat table of the fields shown. Then `if state:old() == nil then return nil end`.
  - Widgets: `builtin.BoxLayout{orientation = builtin.type.Orientation.Vertical, children = {...}}`, `builtin.TextView{text = …, meta = {class = "font-scale-body"}}`, `builtin.Button{content = builtin.TextView{…}, onClick = function() api.cmd.sendCommand(…) end}` (pattern: `BC/game_mechanics/subventions/subventions_gui.tl:139-158`). Types in `BT/scripts/builtin.d.tl`.
  - The plugin is placed by `game.tl` as `FloatingLayoutChild{h = 0, v = 0}` in the game UI root (`BC/gui/main/game.tl:72-94`), i.e. top-left, sized to content. **Keep the root sized to content**: a full-screen root would sit over the map and could swallow mouse input (the root `FloatingLayout` is not marked mouse-transparent). Offset from the game bar via CSS (`margin`/`gravity` on `R::QuotaRunHudPlugin`), modelled on the transported plugin's `.css.lua`.
- **HUD** (compact panel, top-left below the game bar): round, months left, progress / quota (bar + numbers; "provisional" while choosing), red-month warning, picked card names.
- **Card picker** (`phase == "choosing"`): inside the same panel, 3 buttons (name + description each) that send `QuotaRun.pickCard {index}`. Not dismissible. Centering is optional polish; top-left under the HUD is acceptable for MVP.
- **End screen** (`phase == "ended"`): reason, rounds cleared, total moved, cards taken, "Continue as sandbox" button (`QuotaRun.continueSandbox`).
- Card names/descriptions come from `quota_cards.tl` (shared, data-only) and are wrapped in `_()` in the GUI.
- **Fallback** (document in code comments and TESTING.md): if nothing renders, switch the `.res.lua` type to `react-plugin ::GameBarInfoDisplayExtension` (proven path, same recipe registered with `game_bar_widgets.GameBarInfoDisplayExtension` from `ug_require "::/gui/game_bar/game_bar_widgets.tl"`), showing a compact text only; picks then go through console commands, listed verbatim in TESTING.md.

**Accepted when:** check green; the three files mirror the cited base plugin's structure; a grep shows every `ug_require` of a base module starts with `"::/"`; the recipe returns `nil` for every non-active state.

### Phase 4: Integration, review, playtest readiness

**Status: done offline (2026-10-03).** Two reviews' findings were fixed (§8 item 16). `TESTING.md` was written, the forbidden-API grep is clean, and `DEBUG` stays `true` for the playtest. Remaining: the playtest itself.

**Release checklist (before the first upload, and for every update):**
1. `quota_config.DEBUG = false` (debug ops off). Keep `GUI_INLINE_PICKER` at whatever the playtest proved works.
2. Add `_metadata/0.png`, a 1920×1080 cover image. Today it is the only `make validate` warning.
3. Bump `revision` in `mod.json` for every update.
4. Recopy `content/quota/quota_types.d.tl` to `tealdef/quota/quota_types.d.tl` if it changed (`make check` flags drift).
5. Run `make check`, `make test` and `make validate MOD=mods/square_quota_run` (all green), then rerun the grep below.

- `tf3-mod-validator` review, then fix findings.
- Full read-through for rule violations (§2). Grep for `setAppConfig`, `saveAppConfig`, `io%.`, `os%.`, `math.randomseed`, raw `makeVehicleSetModifiersCmd`, and module-level mutable state.
- Decide `DEBUG` for the first playtest build (keep `true`, it's needed for the forced-end checks below) and add a release checklist item to flip it to `false` before upload.
- Write `plans/square_quota_run/TESTING.md`, the playtest script:
  - how to enable the mod for a **new** game only, and the check that an existing save loads unchanged (no HUD, no `[QuotaRun] activated` log line);
  - what to look for in the HUD;
  - console debug commands (exact strings) to fast-forward (`endRound`, `addProgress`, `bankrupt`, `dump`);
  - where the log lives and which `[QuotaRun]` lines to expect;
  - what to report back for each open item in §7.
- `make link`. It only adds a symlink; nothing changes until the mod is ticked in a new game.

**MVP is done when** the user can start a new free game with Quota Run enabled and see:
1. the HUD with a round-1 quota
2. a forced round end via the console that shows 3 cards
3. a pick that applies (cash or speed visible)
4. a forced failure that shows the end screen

Existing saves must load unchanged.

### Later (post-MVP, not in scope now)

The roguelike redesign that covers most of this list is proposed in §9 (Roguelike v2).

- Mod parameters (difficulty, round length) via `params` in `mod.json`.
- More metrics per round (profit, town growth, specific cargo).
- More cards (30+), rarities, synergies, curses-only "events" mid-round, productivity curses (needs §6 Phase 2 rework).
- Score history (blocked: there is no persistent cross-save storage; RESEARCH §2).
- Localization (de).
- Starting "characters" (start-money and era presets via `preRunFn`).

## 7. Risks and unverified items (validate in first playtest)

| # | Item | Status | Fallback |
|---|---|---|---|
| R1 | Mod react-plugin renders (now `MainModButtonAreaExtension` + dialog window, §4.6) | **Open.** Phase 3 moved the mount point (§8 item 15) and Phase 4 moved the picker into a base `DialogWindow` (ridge clipping). `GUI_INLINE_PICKER` restores the inline layout. Original note: Mechanism verified (id `"::ModEntryPointExtension"`, `BC/gui/main/mod_entry_point.tl:5`; lookup `BC/gui/main/react.lua:92-117`; render `BC/gui/main/game.tl:83-90`), and mods do ship `.res.lua` generic resources (`MOD/urbangames_campaign_mission_05/content/mission/tasks/lasse/lasse_notification.res.lua`), but no mod example of a react-plugin exists. | `GameBarInfoDisplayExtension` + console picks |
| R2 | `initNewGame` reaches a mod game script on free-game start | **Mostly resolved.** These are engine system events delivered without subscription to every game script; official mods' game scripts receive `initMission` the same way (`MOD/urbangames_campaign_mission_01/content/init/init.script.tl:14`). Custom maps send `initNewGameFromMap` (`BC/game_mechanics/notifications/notifications.script.tl:695`); we accept both, and an active run re-initialises on `initNewGameFromMap` (§4.6). Confirm with the activation log line. New open point: whether a custom-map start reports `addedToExistingSavegame = true` for a mod the map didn't have (that would keep the run inert on custom maps). | None needed beyond accepting both events |
| R3 | `GameScriptState` persists across save/load | **Resolved by base reliance.** Base scripts keep long-lived state only in `state:set` and migrate it on `handleLegacy` (`BC/game_mechanics/subventions/subventions.script.tl:381-386`, `BC/game_mechanics/notifications/notifications.script.tl:700-708`). | — |
| R4 | Quota metric semantics | **Mitigated.** Primary metric is our event counter (known semantics, `arrivaltracker.script.tl:115-125`). `getTransportedData` cumulativeness stays unverified and is only logged. | `METRIC = "stats"` |
| R5 | `handleEvent` fires while paused | **Likely resolved.** Sim ticks once per frame while paused (`API/api/engine.d.tl:434-435`) and `update` is called with `dt == 0` (`BC/industries/industry_workers.script.tl:22`). Design no longer depends on it: the round clock keeps running after round end. | Picks processed after unpause; acceptable |
| R6 | `ChangeModifier` same-id semantics | **Resolved:** same id replaces (`BC/vehicle/vehicle_modifier.script.tl:107`), `{}` removes (`:84-101`). | — |
| R7 | Industry productivity clobbered by base | **Resolved in design:** base resets only on visitor changes (`BC/industries/industry_workers.script.tl:6-14`); we re-assert `baseValue × ours` each scan using the base's own util. Residual: ≤ 1/4-month gaps. | Shorter scan interval |
| R8 | Integer-keyed tables in state serialize | **Resolved:** base stores entity-keyed maps in state (`BT/vehicle/vehicle_modifier.d.tl:16`, `BC/industries/industry_workers.script.tl:108`). | — |
| R9 | `_()` unavailable in sim thread | Unverified; designed around (all text built in GUI/notification scripts). | — |
| R10 | Calendar speed 0 or changed mid-run | **Resolved in design:** rounds use game time, not calendar dates (§3.1). | — |
| R11 | Offline Teal checking | **Resolved:** proven in review with the game's `tl.lua` patched in memory (§5.1). Residual: the in-game loader may resolve mod `.d.tl` globals differently; confirm `quota_types.d.tl` types load in the first playtest (look for Teal errors in `stdout.txt`). | Inline the records into each module as `local record`s and pass plain tables |
| R12 | Mod removed from an active save | Base `vehicle_modifier` state keeps our id's entries, so speed boosts persist after removal. Accepted; `severityRemove = Critical` warns. TESTING.md tells the player to finish or end the run first. | — |
| R14 | Mission start fires `initNewGame` before `initMission` (`BC/mission/mission_sim.script.tl:830-845`) | **Mitigated (Phase 4):** `hasStartedAsMission()` gate, plus deactivation on `initMission`/`initTutorial` (§4.6). | — |
| R15 | `ChangeModifier` fan-out is O(N²) (the base copies its state per event) | **Mitigated (Phase 4):** at most `VEHICLE_SENDS_PER_FRAME` per frame, continued across frames, including after the run ends (§4.6). | Lower the cap |
| R16 | Industry composition needs `PERSON_CAPACITY` on the stock-list entity | Unverified. The playtest log line `industryMods probe: … PERSON_CAPACITY=…` answers it. | Look up the person-capacity entity separately |
| R13 | Player vehicles only | `requireOwnedByPlayer` filter (`API/api/engine.d.tl:1710-1713`); base `BC/landmarks/landmarks.script.tl:208-236` iterates all vehicles, so verify the filter doesn't exclude the player's own fleet in the playtest. | Use `forEachEntityWithComponent` without filter |

## 8. Review log

Review on 2026-10-03, against the extracted game files in `.cache/game/`.

1. **Gating (§2.1).** Was "only on `initNewGame`, `initNewGameFromMap` decided in Phase 1". Now: accept both, require `not hasStartedAsMission()` and `addedToExistingSavegame ~= true`, idempotent, and no subscriptions while inert. Why: the base distinguishes `initNewGame`/`initNewGameFromMap`/`initMission`/`initTutorial`/`handleLegacy` (`company.script.tl:379-392`, `mission_sim.script.tl:831-851`). A mod enabled for a campaign start must stay inert, and the `GameScript` component exposes `addedToExistingSavegame` for free.
2. **Time base (§3.1).** Was calendar month rollovers via `getCalendarDate`. Now game time with `getDefaultMonthDuration()`. Why: calendar speed can be 0 (`game_bar_widgets.tl:351`), which would freeze rounds forever, and it also makes round length depend on a player setting.
3. **Choosing does not stop the clock (§3, §3.2).** Was "pause, then start the next round on pick". Players can unpause from the game bar, which made the pick screen free building time. The next round now starts at the deadline; "next round" cards became "this round" cards (`quotaMult` → `quotaMultRound`), and resume only restores speed if the game is still paused.
4. **Quota metric (§3.1, R4).** Primary is now the event counter, and `getTransportedData` is diagnostic only. Why: the event semantics are visible in base code, while cumulativeness of the stats is not.
5. **Vehicle modifier facts (§6 Phase 2, R6).** Same-id replaces, `{}` removes, no new-vehicle discovery, no subscription needed. Switched to a single id plus a revision-tracked scan, and a cap. The RESEARCH suggestion of a "per-card id" fallback is no longer needed.
6. **Industry composition (§6 Phase 2, R7).** Target is `industry.stockList`. There is no hook, so we use an explicit `desired = baseBoostOrOne × ours` formula with the base util, and productivity multipliers stay ≥ 1.0 because the base treats `> 1.0` as "boosted".
7. **GUI plugin (§6 Phase 3).** Confirmed the id `::ModEntryPointExtension` and the recipe contract (`RegisterPluginRecipe`, the returned table key named in `filePath`, `nil` = nothing). Fixed `priority` → `order` (`react.lua:109`). Mods must use `"::/"` for base `ug_require`s. The model file is now the *transported* game-bar plugin (it polls engine state), not the earnings one. Added the mouse-blocking caution.
8. **Notification path (§4).** Fixed the type string to include `notify/` and documented the `.script` → `.res` basename rule (`notification_util.tl:13`).
9. **Events (§4.2).** Names are now namespaced `QuotaRun.*`. Added the re-subscribe rule on `handleLegacy`, and debug ops that work with game time.
10. **Contracts (§4.1, §4.3).** Replaced `lastYear/lastMonth`/`baselineTransported` with game-time fields, moved effect bookkeeping under `fx` (owned by Phase 2), and added an explicit intent record and logic input list so Phases 2 and 3 can run in parallel. Added the global-name prefix rule.
11. **Tooling (§5, R11).** Proved `lupa` + the game's `tl.lua` works, but only with `lupa.lua54`, a `log` stub, and two in-memory patches that undo Urban Games' stubbed module search. Without them `init_env` fails with "could not predefine module 'all_def'".
12. **Balance.** Added a vehicle-mod cap, a `roundMonths` floor, a quota floor, cargo/passenger weights, and a note on loans as the intended bankruptcy escape. Seeded the RNG from game time instead of `math.random`, which base code reseeds.
13. **Phases.** Acceptance criteria are now concrete commands and greps. Added file ownership per phase and a "stop and report" rule for contract changes.
14. **Phase 1 implemented (2026-10-03).**
    - **Files** (all in `content/quota/`): `quota_types.d.tl`, `quota_config.tl`, `quota_cards.tl` (12 cards), `quota_logic.tl`, `quota_effects.tl` (stubs), `quota.script.tl` and `quota.gs.lua`. The Phase 0 placeholder (`quota_version.tl`/`.d.tl`) and `test_smoke.lua` were removed.
    - **Tests:** `tests/square_quota_run/test_logic_core.lua`, `test_logic_rounds.lua`, `test_logic_events.lua` and `test_adapter.lua`, 79 in total. `test_adapter.lua` uses a fake `api` and `GameScriptState`. Mutation spot checks confirmed the tests catch a broken resume guard and a broken `addedToExistingSavegame` gate.
    - **Deviations from §4:** all recorded in §4.5.
      - One `.d.tl` instead of one per module, because of definition load order.
      - `quota_logic` is a factory with injected config and cards, so the literal acceptance grep (`ug_require`) holds.
      - New fields: `monthDuration` and `halfwayWarned` on the state, `level` on intents, and `kind` (plus optional `statsTotal`) on the inputs.
    - **Activation gate (rule 2.1)** is as written:
      - `id == ""` and `initNewGame`/`initNewGameFromMap`;
      - the state is nil or has no `active`;
      - `not api.engine.util.hasStartedAsMission()` (`API/api/engine/util.d.tl:1034-1036`);
      - our `GAME_SCRIPT` component, found via `getEntityForGameScript("square_quota_run::/quota/quota.gs")`, has `addedToExistingSavegame ~= true` (`API/api/engine.d.tl:401-412`, lookup pattern `BC/game_mechanics/company/company_util.tl:284-285`). A missing entity (nil or < 0) does not block activation.
    - **Lua target (corrected in §8 item 18):** ~~the game's `tl.lua` defaults to `gen_target = "5.3"`, so `//` and `math.tointeger` are safe.~~ Wrong: `math.tointeger` is nil in game and crashed the first playtest. The in-game runtime is pre-5.3 and `tl.init_env` picks target `"5.1"` there (`BC/base/tl.lua:13593-13603`), so `//`/bitwise operators in `.tl` are rewritten and safe, but 5.3-only library calls (`math.tointeger`, `math.type`, `math.ult`, `utf8.*`, `string.pack`, `table.move`) are not. `make check` now lints them.
    - **Open for the playtest:**
      - (a) The in-game loader must accept the single mod `.d.tl` (R11).
      - (b) It is unverified whether `state:get()` returns nil or `{}` on a fresh script; both are handled.
      - (c) It is unverified whether integer fields come back as floats after a save/load round trip. Only cosmetic in log strings; table indexing normalises.
15. **Phases 2 and 3 implemented (2026-10-03).**
    - Phase 2 added `QuotaRunNotificationParams` (§4.6).
    - Phase 3 mounted the HUD at `::MainModButtonAreaExtension` instead of `::ModEntryPointExtension`, because `game.tl` mounts ModEntryPoint plugins inside an invisible `EntryPoints` node (`BC/gui/main/game.tl:574-586`). Details are in `GUI_FALLBACK.md`.
16. **Phase 4 fixes (2026-10-03),** from two independent reviews. All are covered by tests (125 in total):
    1. Missions and tutorials: deactivate an active run on `initMission`/`initTutorial` (R14).
    2. Map editor: never activate there. `initNewGameFromMap` re-initialises an active run once the gates pass.
    3. Perf: capped `ChangeModifier` sends in scans and in `clearEffects`, continued across frames, also in `ended`/`sandbox` (R15).
    4. Perf: `get_native` skipped (no base usage). We kept the base-style one `get()` per frame plus `set()` on change only, and documented the choice in `quota.script.tl` (§4.6).
    5. GUI: compact ridge HUD plus a centered dialog for the picker and end screen, with `GUI_INLINE_PICKER` as the fallback.
    6. Added the `PERSON_CAPACITY` probe log line (R16).
    7. The round-1 notification is re-sent on `initNewGameFromMap` (folded into fix 2).
    8. Documented that "all industries" cards snapshot the industries that exist when the card is picked (MVP).
    9. `DEBUG` stays `true`; a release checklist was added (§6 Phase 4).
    10. Added `tealdef/` parity with the official mods. `tl_check` loads only the `content/` definitions, so the copy can't cause duplicate declarations; it errors when the copy drifts. `make teal` now adds `mods/<id>/tealdef` and a generated `.cache/teal/hub_all_def.d.tl` that requires each `<modId>_def`.
    - Forbidden-API grep clean in `mods/square_quota_run`: `setAppConfig`, `saveAppConfig`, `io.`, `os.`, `math.randomseed`, `math.random`, `makeVehicleSetModifiersCmd`. Module-level locals are constants or module tables only. Note: the base util we call, `industry_productivity_util.getPersonCapacityPotentialBoost`, reseeds `math.random` itself (`BC/industries/industry_productivity_util.tl:70`). That is base behaviour and the reason our RNG is our own LCG.
17. **Dev panel and debug ops (2026-10-03).** Goal: test any feature in game without playing the loop. Details in §4.2 (debug-op table) and §4.6 ("Dev panel"); usage and recipes in `TESTING.md` → "Dev tools".
    - New `QuotaRun.debug` ops: `passRound`, `failRound`, `skipMonths {n}`, `applyCard {id}`, `addMoney {n}`, `addQuotaPct {n}`, `clearEffects`, `reset`, `forceStart`. Existing ops unchanged.
    - Decisions: `passRound`/`failRound`/`skipMonths` judge **immediately** (no unpaused frame needed), reusing `finishRound`/`tick`. `skipMonths` shifts all time anchors back and replays the month ticks with the current balance. `applyCard` reuses the pick's card resolution and records the card in `picked` without a marker (the log marks it). `reset` carries the old `fx` into the new state so `clearEffects` can undo the engine effects.
    - Rule 2.1 exception, debug-only: an undecided inert save subscribes to `QuotaRun.debug` while `DEBUG == true` so `forceStart` can be reached; nothing is written unless forceStart is pressed. Release builds are unchanged (tests).
    - GUI: custom `builtin.Window` (stays open, grouped rows, live status) instead of `DialogWindow`; inline variant under `GUI_INLINE_PICKER`.
    - Tests: 163 in total (`test_logic_debug.lua` new; DEBUG gating, inert-save and forceStart-gate cases added to `test_adapter.lua`; `test_hud_model.lua` now runs the release cases with `DEBUG = false`). `make check`, `make test`, `make validate` green; forbidden-API grep clean.
    - **Unverified in game (item 17):** the dev window renders and stays open (custom Window outside the dialog pattern; recipe names `QuotaRunDevWindow`/`QuotaRunDevPanel` must not collide), the window CSS (`R::QuotaRunDevPanel`) applies, `meta.enabled` greys out buttons, the inert-save HUD appears (it depends on the GUI seeing our GAME_SCRIPT entity on an existing save), `update` runs on an inert existing save so the debug subscription happens, the console `qr` global persists between console lines, and AltGr = right Option on macOS.
18. **Roguelike v2.1 + playtest probes (2026-10-03).** Built against one contract change, written first and then frozen (`quota_types.d.tl`, all fields marked "v2"; `QuotaRunState.version = 2`), so that logic, adapter and GUI could be built in parallel.
    - **Lua runtime correction:** see the corrected note in item 14. `tools/tl_check.py` now transpiles `.tl` the way the game does (target 5.1, compat optional) and lints the output and plain `.lua` files for 5.3-only constructs; `--allow-lua53` skips. Offline tests still run Teal's 5.3 output on Lua 5.4, so they exercise slightly different code than the game.
    - **Logic (§9.3, §9.4):**
      - new data modules `quota_rules.tl` (6 rules) and `quota_bosses.tl` (`inspector`, `cargo_baron`, `transit_commissioner`, `monopolist`, `mayor`);
      - 3 round-modifier cards appended (`freight_contract`, `rush_hour`, `local_hero_card`), with new effect kinds `rule` and `rewardMultRound`;
      - `new(config, cards, rules?, bosses?)`: nil rules and bosses keep the exact MVP behaviour, including the RNG sequence;
      - `migrate` (v1→v2), `weight`, `factsNeeded`; per-round tallies (`tally`/`lastTally`); rule targets are drawn from last round's tally, weighted by units, with sorted, floor-normalised keys;
      - a boss every `BOSS_EVERY = 3` rounds, announced one round ahead (`nextBoss`) and paying `BOSS_REWARD_MULT = 2.0` (a v2.1 stand-in for charter points). `fx.vehicleMods` = card aggregate ⊕ boss mods, clamped to [0.1, cap];
      - new debug ops `setRule`, `setBoss`, `setNextBoss`.
    - **Logic deviations:**
      - specialist uses ×10 vs ×1, the same ratio as ×5 vs ×0.5 but with integer weights, because the state has no field for a fractional remainder; it is also cargo-only;
      - the rule `quotaMult` values are reasoned placeholders (freight_only 0.3, commuter_rush 1.8, local_hero 1.0, specialist 0.45, rail_day 0.1, long_haul 1.3); the working is in `quota_rules.tl`;
      - `RANDOM_RULE_FROM_ROUND = 0` (off, §9.3 (c));
      - the defeated-boss history on the end screen is skipped (it needs state history).
    - **Adapter:**
      - delivery facts resolved per entity only while `factsNeeded` is non-nil (cargo type, last pickup point's line/carrier, towns per `arrivaltracker`);
      - `migrate` on `handleLegacy`;
      - probe ops P1 `incomeProbe`, P2 `factsProbe`, P3 `jumpYears`, P4 `closeIndustry`, P6 `townProbe`, and P7 (mod params logged at activation and on dump). All are DEBUG-gated and stored in `state.probe`. The P1 `OnCalcTicketPrice` subscription follows `probe.incomeMult`.
      - Cost: `TALLY_FACTS = true` means every delivery now costs about 3–4 component reads per entity (MVP: none). Watch perf in the playtest; set it to false to fall back.
    - **Engine facts found:**
      - `OnCalcTicketPrice` is also handled by `towns.script.tl:396` and `town_growth.script.tl:620`;
      - the carrier enum is `api.type["enum"].Carrier` (`API/api/type.d.tl:403-419`);
      - `Town.developmentActive` exists (`API/api/engine.d.tl:1285-1302`, polarity unclear), which answers the first half of P6;
      - the rust_belt caveat is in §9.4.
    - **GUI:** the ridge HUD shows a "BOSS: name" or rule tag and "Next: boss"; the tooltip, picker dialog, inline picker and roundStart notification describe the rule, the boss and the next boss. The rule target (town or cargo name) is displayed as well.
    - **Integration review:** no serious bugs. Fixed: `setNextBoss` is refused unless round+1 is a boss round, and debug `clearEffects` also empties `cardVehicleMods`, so a later recompute can't re-send cleared mods. Known and accepted: P1 does a full `state:get()` per ticket event while it is on (debug only, keep probes short; this matters for the v2.4 income hook); P4 advances `rngSeed`; cargo `fromTown` is usually nil, so `long_haul` mostly boosts passengers.
    - **Tests:** 247 (`test_logic_v2.lua`, `test_adapter_v2.lua` new). `make check`, `make test`, `make validate` and `make sim ARGS=--selftest` are green; the forbidden-API grep is clean.
    - **Unverified in game:** everything in TESTING.md "v2 probes", plus: handleEvent return values reach the engine (P1), the HUD tags fit the ridge, and the per-delivery fact cost.

## 9. Roguelike v2 (proposal, 2026-10-03)

**Status: v2.1 and the §9.9 probe ops implemented offline (§8 item 18); v2.2+ still proposals.** The probes need the playtest before v2.3/v2.4 start. Citations use the §1 shorthand. "Verified" means read in the extracted game files, not tested in game.

### 9.1 Why

The MVP loop works, but the cards make the game easier or harder without changing **how** you play:

- **Every run plays the same.** Any unit counts, and passenger trips far outnumber cargo, so busing the biggest town is always the best strategy.
- **Cards are stat sliders.** Speed, quota and cash all make the same build stronger. Nothing makes you build differently, and no two cards combine into something new.
- **Cash snowballs.** After a few rounds money stops mattering, so cash rewards and cash curses lose their bite.
- **Nothing happens for 24 months.** There's nothing to react to between picks.

v2 pillars, added to §1:

5. **Every round asks for a different network.** Scoring rules change what counts.
6. **Telegraphed threats.** Bosses and events are announced ahead of time, so you plan around them instead of just absorbing them.
7. **Builds.** Tags, rarities and set bonuses make picks combine.
8. **A currency that doesn't snowball.** Charter points are spent in a shop, separate from cash.

### 9.2 Systems overview

| # | System | What changes for the player | Engine surface | Effort |
|---|---|---|---|---|
| S1 | Scoring rules | Each round has a rule for what counts (cargo only, one town, one cargo type, ...) | none new: delivery events, resolved further (§9.3) | low (mostly pure logic) |
| S2 | Bosses | Every 3rd round is a boss with a hard rule, announced one round ahead | vehicle stop, ticket income, town sensitivity, industry closure | medium |
| S3 | Mid-round events | A two-option popup once per round | the same levers plus cash | medium (GUI) |
| S4 | Passives ("relics") | Permanent cards that bend rules: income split, carrier bias, clean air, ... | ticket income hook, per-carrier vehicle mods, town events | medium |
| S5 | Charter points + shop | A second currency: reroll, banish, extra pick, skip boss | none | low |
| S6 | Tags, rarities, synergies | Set bonuses at 3 of a tag; rare and legendary cards | none | low |
| S7 | Starting characters | A drop-down in the mod settings when you start a game | `preRunFn`/`postRunFn` config | medium (collateral rules, §9.7) |
| S8 | Contracts (experimental) | The quota becomes a base-game subsidy | `Subvention/*` events | high |

### 9.3 S1: scoring rules

A round has one `rule` (none = MVP behaviour). The rule is a pure weight function `weight(rule, fact) -> number` in `quota_logic`, and progress is `Σ units × weight`.

**Delivery facts.** The adapter resolves each delivered entity into a plain record and passes it to `delivered`. The logic stays engine-free.

| Fact | Cargo (`OnToArriveAtDestination`) | Passenger (`OnCompletedLineUsage`) |
|---|---|---|
| `kind` | `"cargo"` | `"passenger"` |
| `cargoType` | `SIM_CARGO.cargoType` (`API/api/engine.d.tl:~966`) | n/a |
| `toTown` | target → town via construction/town building (`BC/game_mechanics/arrival_tracker/arrivaltracker.script.tl:3-15,49-52`) | `person2goal` (same file `:17-20`) |
| `fromTown` / source | `SIM_CARGO.sourceEntity` (`:56-58`) | `person2source` (`:22-35`) |
| `line`, `carrier` | last entry of `SIM_CARGO.pickupPoints` (`API/api/engine.d.tl:949-972`: `vehicle`, `line`, `carrier`) | n/a for MVP (a person has no pickup history; leave nil) |

Perf: this costs a few `getComponent` calls per entity, which is the same work the base arrival tracker does per filter. Resolve facts only while the current rule needs them (`rule.needs = {"toTown", ...}`). Otherwise keep the MVP fast path.

Rules (data in a new `quota_rules.tl`, same style as `quota_cards.tl`):

| id | Name | Weight | Notes |
|---|---|---|---|
| `freight_only` | Freight Only | cargo ×3, passenger 0 | breaks the bus-spam strategy |
| `commuter_rush` | Commuter Rush | passenger ×2, cargo 0 | |
| `local_hero` | Local Hero | ×4 if `toTown == target`, else 0 | target = a random town, picked when the rule is drawn |
| `specialist` | Specialist | ×5 for one cargo type, others ×0.5 | the type is picked from cargo types delivered last round, so the rule is always achievable |
| `rail_day` | Iron Horse | ×2 if `carrier == RAIL`, road 0, others ×1 | cargo only (no passenger carrier fact) |
| `long_haul` | Long Haul | ×3 if `fromTown ~= toTown` and both are towns | |

How a rule is set: the quota is calibrated against the rule's expected units (`rule.quotaMult`, e.g. Freight Only ×0.25 because cargo volumes are lower). Rules come from (a) bosses, (b) round-modifier cards, (c) from round 4 onwards, a random rule on every non-boss round, shown in the offer screen. Default: (a)+(b) only for v2.1, then turn on (c) after the playtest.

### 9.4 S2: bosses

Every `BOSS_EVERY = 3` rounds. The boss is drawn when the previous round starts, and the HUD shows "Next: <boss>" for the whole round before it. Clearing a boss round pays double charter points (§9.6) and offers one **rare-or-better** card.

| id | Boss | Effect during the boss round | Lever | Undo |
|---|---|---|---|---|
| `strike` | The Strike | the 3 lines with the most vehicles stop for the first 3 months | `makeVehicleSetStoppedByUserCmd(v, true)` (`API/api/cmd.d.tl:936`); vehicles found via `TRANSPORT_VEHICLE.line`, `.userStopped` (`API/api/engine.d.tl:~1468-1474`) | restart only vehicles in `fx.stoppedVehicles` that are still `userStopped`. Never restart vehicles the player stopped. |
| `recession` | Recession | all ticket income ×0.6 | `OnCalcTicketPrice` handler return (§9.5) | state only |
| `inspector` | The Inspector | all vehicles TopSpeed ×0.75 | existing `vehicleMod` path (`1+Σ(v-1)` with the run's boons) | existing |
| `hostile_mayor` | Hostile Mayor | the town that received the most units last round gets noise and pollution sensitivity ×4 | `Towns/setTownRatingSensitivity {townEntity, rating, sensitivity}` (`BC/game_mechanics/towns/towns.script.tl:351-366`); scalar, 0 = off, read by `town_util.getRatingSensitivity` (`BC/game_mechanics/towns/town_util.tl:81-90`) | `Towns/resetTownRatingSensitivity {townEntity}` (`towns.script.tl:340-348`). It clears **all** of that town's overrides, so re-send any S4 overrides afterwards (§9.5 `clean_air`). |
| `rust_belt` | Rust Belt | 4 industries that supplied you last round start a 12-month closure countdown | `makeIndustrySetDespawnTimeCmd(e, now + 12 months)` (`API/api/cmd.d.tl:724`) | the base clears it when the industry is no longer a closure candidate (`BC/game_mechanics/industries/industries.script.tl:96-102`). That turns the boss into "keep them busy", which works with the base rather than against it. **Probe P4.** v2.1 finding: the base resets a non-candidate's countdown on effectively every update, and only industries with output, no depots, not manual and not player-owned are candidates (`:62-69,96-99,105-110`); the despawn time is game time (`:51-52,94-95`). So a forced countdown on a busy industry likely vanishes at once; P4 decides whether this boss is viable. |
| `zoning_freeze` | Zoning Freeze | no town grows this round | `makeTownSetDevelopmentActiveCmd(town, false)` (`API/api/cmd.d.tl:856`) | set `true` again only for towns in `fx.frozenTowns`. **Probe P6:** read the prior state so towns the player froze stay frozen. |

### 9.5 S4: passives and the income hook

**Income hook.** The base `company_growth` game script handles `OnCalcTicketPrice` from `TransportVehicleSystem` (cargo) and `SimEntityAtVehicleSystem` (passengers), and **returns** `{[0] = mult}` from `handleEvent` (`BC/game_mechanics/company/company_growth.script.tl:121,159-173`). Other base scripts return per-entry multipliers (`BC/game_mechanics/subventions/deliver_cargo/deliver_cargo.script.tl:452-475`, per research, not re-read). v2 adds:

- `state.incomeMult = {cargo, passenger}`: the product of passives, boss and events. Subscribe to `OnCalcTicketPrice` only while either value ≠ 1, to keep the per-ticket cost at zero otherwise.
- The handler does one `state:get()` and returns `{[0] = m}`. It never calls `set()`.
- **Probe P1 (blocking for S4 income cards and `recession`):** how two handlers' returns combine (multiply, last wins, first wins). If they don't multiply, fold the base company multiplier into ours (read `companyState[player].ticketPriceMultiplier` from the `company_growth` script state) or drop the income cards.

Passive cards (permanent; tags in brackets):

| id | Name | Rarity | Effect | Lever / status |
|---|---|---|---|---|
| `toll_baron` | Toll Baron [Greed, Cargo] | rare | cargo income ×1.5, passenger income ×0.6 | income hook, P1 |
| `people_mover` | People Mover [Passenger] | uncommon | passenger income ×1.3; this round's quota ×1.2 | income hook, P1 |
| `rail_baron` | Rail Baron [Rail] | rare | rail TopSpeed ×1.3, road TopSpeed ×0.8 | per-carrier `vehicleMods` via `TRANSPORT_VEHICLE.carrier`; scan sends per-vehicle values (one id, value depends on carrier) |
| `trucker` | Open Road [Road] | uncommon | road TopSpeed ×1.25 and Comfort ×1.2 | as above |
| `clean_air` | Clean Air Act [Green] | uncommon | pollution sensitivity 0 in every town for the run (towns ignore pollution) | `setTownRatingSensitivity`, re-sent each scan for new towns and after a `hostile_mayor` reset |
| `quiet_hours` | Quiet Hours [Green] | uncommon | noise sensitivity 0 in every town | as above |
| `boomtown_fever` | Boomtown Fever [Passenger] | rare | at each round start every town you serve gains 25% of a level | `Towns/addExperiencePercentage {townEntity, amount, source}` (`BC/game_mechanics/towns/town_growth.script.tl:591-608`) |
| `time_machine` | Time Machine [Era] | legendary | the calendar jumps +25 years now; reward ×1.5 | `makeGameSetDateCmd` (`API/api/cmd.d.tl:703`; used by `BC/mission/calendar.lua:23`). **Probe P3**: effect on existing vehicles, inflation and loan amounts. Not reversible. |
| `flagship` | Flagship [Greed] | legendary | the line with the most deliveries last round earns ×2.5, all others ×0.85 | per-line income needs the per-entry return form (P1) plus `line` from pickup points (§9.3); cargo only |

Round-modifier cards (this round only; they set `rule` from §9.3):

| id | Name | Effect |
|---|---|---|
| `freight_contract` | Freight Contract [Cargo] | rule `freight_only`; reward ×1.5 |
| `rush_hour` | Rush Hour [Passenger] | rule `commuter_rush`; reward ×1.3 |
| `local_hero_card` | Hometown Hero | rule `local_hero`; quota ×0.8 |

Boon-plus-curse cards that use the new levers:

| id | Name | Effect |
|---|---|---|
| `union_deal` | Union Deal [Greed] | +$8M × round; a random line strikes for 2 months, starting at a random point in this round |
| `liquidation` | Liquidation Sale [Greed] | +$6M × round; 2 random served industries start a closure countdown |
| `zoning_deal` | Zoning Deal | this round's quota ×0.8; no town grows this round |
| `grease` | Grease the Wheels | +$5M × round; your best town loses reputation (`Towns/decreaseReputation`, `towns.script.tl:308-337`) |
| `junk_bonds` | Junk Bonds [Greed] | +$20M × round now; −$2.5M × round every month for 12 months (needs scheduled cash, §9.8) |

### 9.6 S5–S6: charter points, shop, tags, rarities

- **Charter points:** +1 per round cleared, +1 for ≥150% of quota, ×2 on boss rounds. They never convert to cash.
- **Shop** (on the offer screen, pure logic): reroll the offer (1), banish one card from the pool for the run (2), see a 4th card (3), +6 months this round (2), skip the next boss (5, once per run).
- **Rarity weights:** common 60, uncommon 30, rare 10. Legendary only from boss rewards. Draw = weighted LCG over the non-banished pool, still deterministic from `rngSeed`.
- **Tags:** Rail, Road, Cargo, Passenger, Green, Greed, Era. Holding 3 cards of one tag gives a set bonus:
  - **Green ×3:** noise and pollution sensitivity 0 everywhere, and reward ×1.2.
  - **Greed ×3:** cash effects +50%.
  - **Cargo ×3:** cargo weight ×1.5.
  - **Passenger ×3:** passenger weight ×1.25.
  - **Rail ×3 / Road ×3:** that carrier's TopSpeed ×1.15.
- The offer and end screens show tags. The HUD shows active set bonuses.

### 9.7 S3, S7, S8

**S3, mid-round events.** One per round at a random time between 30% and 70% of the round. The game pauses and a two-option dialog appears, reusing the picker window (`GUI_INLINE_PICKER` both ways). Events never end the run directly. Starter set:

| Event | Option A | Option B |
|---|---|---|
| Strike threat | pay $3M × round | a random line stops for 1 month |
| Gold rush | a random mine produces ×3 for 6 months, and its nearest town loses reputation | ignore |
| Investor | +$5M × round | this round's quota −10% |
| Festival | fireworks in your best town (`fireworks/startFireworkForTown`, `BC/game_mechanics/fun_elements/fireworks.script.tl:149`) and it gains reputation | +1 charter point |

Time-limited effects (e.g. ×3 for 6 months) need the scheduled effects in §9.8. Productivity stays ≥ 1.0 (§3.2 balance note).

**S7, starting characters.** A `params` drop-down (`character`) in `mod.json`. A `preRunFn` scales `baseConfig` (costs, income, loans), and a `postRunFn` edits script configs: permit keys, `company_growth_config`, town sensitivities. These are the same mechanisms the base game uses for difficulty (`BC/base/mod.script.tl:185-253,676-738`). Drafts:
- **Classic:** no changes (default).
- **Hauler:** cargo income ×1.5, passenger income ×0.5.
- **Tycoon:** loan limit ×2, interest ×1.5, maintenance ×1.5.
- **Frontier:** fewer, smaller towns.
- **Bureaucrat:** half the permits, and the shop is 1 point cheaper.

**Collateral conflict with rule 2.1:** run hooks apply to **every** game the mod is enabled in, including an existing save it was added to and a mission, and they can't see our game-script state. So:
- only **Classic** may ever be the default;
- the game script logs the character, and the end screen shows it;
- `TESTING.md` must say that a non-Classic character changes the economy even when no run activates;
- this needs an explicit amendment to rule 2.2 ("needs no `runFn`") before S7 starts.

The new-game screen only offers 50–150% for these settings; values outside that range are untested (P5).

**S8, contracts (experimental, last).** Replace the unit quota on some rounds with base-game subsidies:
- spawn them with `Subvention/subventionSpawn {name, specific}` (`BC/game_mechanics/subventions/subventions.script.tl:21,465-472`);
- judge on `Subvention/OnCompleted` / `OnFailed` (`:188,329,547`).

The base game owns the tracking, UI and penalties (failure costs town reputation). Risk: subsidy deadlines and our round clock disagree. Prototype it with the dev panel before designing it in detail.

### 9.8 Contract changes (bump `QuotaRunState.version` to 2)

Every change below is a §4.1/§4.3/§4.5 contract change, so it needs the "stop and report" review of §6. Proposed shape:

- **State:**
  - `rule: string?`, `ruleTarget: integer?`
  - `boss: string?`, `nextBoss: string?`
  - `charter: integer`, `banished: {string}`
  - `incomeMult: {string: number}`
  - `scheduled: {QuotaRunScheduled}`: `{at: integer, intent: QuotaRunIntent}`, run by `tick` in time order with month ticks
  - `event: {id, options}?` while an event is pending
- **fx:** `stoppedVehicles: {integer: boolean}`, `frozenTowns: {integer: boolean}`, `townSensitivity: {integer: {string: number}}`, `closures: {integer: integer}`
- **Inputs:**
  - `QuotaRunDeliveredInput` gains `facts: {QuotaRunDeliveryFact}?` (§9.3). When facts are nil, use the MVP path.
  - New `QuotaRunShopInput{item, arg?}` and `QuotaRunEventChoiceInput{index}`.
- **Intents:**
  - `stopLines{count | lines}` / `startStopped`
  - `townDevelopment{active}`
  - `townSensitivity{rating, value, towns?}` / `townSensitivityReset`
  - `industryClosure{count, months}`
  - `townExperience{pct}`
  - `calendarJump{years}`
  - `fireworks`
  - `subventionSpawn`
  - `clearEffects` undoes every new fx map.
- **Events:** `QuotaRun.shop`, `QuotaRun.eventChoice`. The `OnCalcTicketPrice` subscription follows `incomeMult` (§9.5).
- **Migration:** `handleLegacy` on a v1 state fills defaults. No v1 saves exist outside playtests, but keep the path tested.
- **Cards:** `QuotaRunCard` gains `tags: {string}`, `rarity: string`. The new effect kinds are `rule`, `incomeMult`, `carrierMod`, `townSensitivity`, `townExperience`, `strike`, `closure`, `townFreeze`, `calendarJump`, `charter`, `scheduledCash`. Append to `cards.list` only: the §4.5 draw-order rule still applies until the weighted draw replaces it, and then it can be relaxed.

### 9.9 Playtest probes (add to `TESTING.md` before v2 starts)

| # | Question | How |
|---|---|---|
| P1 | How do two `OnCalcTicketPrice` handlers combine? | debug op `incomeProbe {mult}`: subscribe, return `{[0]=mult}`, compare the ticket income per unit before and after, with the company multiplier known |
| P2 | Do cargo `pickupPoints` carry `line`/`carrier` at arrival time? | log the facts for the first 20 deliveries |
| P3 | What does `makeGameSetDateCmd` do mid-game (vehicles, inflation, loans, aging)? | debug op `jumpYears {n}` on a throwaway save |
| P4 | Does a forced closure countdown stick on a busy industry, an idle one, or neither? | debug op `closeIndustry`, then watch both cases for 2 months |
| P5 | Do config scales outside 50–150% work (S7)? | a throwaway `preRunFn` build with passenger income 0.2 |
| P6 | Can we read a town's development-active flag? | grep `API` for the `TOWN` component, then log it |
| P7 | Does `getModParams()["square_quota_run"]` work at runtime? | log it at activation |

### 9.10 Phasing

Each step is shippable on its own and keeps `make check`/`make test`/`make validate` green.

1. **v2.1 rules + bosses (logic):**
   - delivery facts, `quota_rules.tl`, boss scheduling and HUD "Next boss";
   - bosses that need no new engine surface first: `inspector`, plus rule-only bosses;
   - the round-modifier cards.
2. **v2.2 shop + tags + rarities:** pure logic and GUI.
3. **v2.3 engine bosses:** `strike`, `hostile_mayor`, `zoning_freeze`, `rust_belt` (after P4/P6), with undo bookkeeping and tests on a fake `api`.
4. **v2.4 income hook + passives** (after P1/P2): `toll_baron`, `people_mover`, `recession`, carrier mods, `clean_air`/`quiet_hours`, `boomtown_fever`.
5. **v2.5 scheduled effects + mid-round events.**
6. **v2.6 characters** (after P5/P7 and the rule-2.2 amendment).
7. **v2.7 experiments:** `time_machine` (P3), `flagship`, contracts (S8).
