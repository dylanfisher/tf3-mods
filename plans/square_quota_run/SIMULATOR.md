# Quota Run: offline simulator

`tools/quota_sim.py` plays a whole Quota Run in milliseconds, without the game. Use it to balance the placeholder numbers in `quota_config.tl` and `quota_cards.tl`, and to exercise the round, pick and bankruptcy loop.

It lives in `tools/` next to `tl_check.py`, because it is a CLI dev tool, not a pass/fail test. `tests/run_tests.py` only collects `tests/<modId>/test_*` files. The simulator reuses `tools/tealrt.py`, which loads the game's Teal compiler and its patches.

## What it runs

The simulator transpiles the real `quota_config.tl`, `quota_cards.tl`, `quota_rules.tl`, `quota_bosses.tl` and `quota_logic.tl` from `mods/square_quota_run/content/quota/`. It type-checks them against the mod's `.d.tl` files and builds `QuotaRunLogicModule.new(config, cards, rules, bosses)`, so simulated runs include v2.1 bosses (every `BOSS_EVERY` rounds) and the round-modifier cards. It calls only the stable entry points: `activate`, `tick`, `delivered`, `pickCard` and `continueSandbox`, plus the pure helper `factsNeeded`. Debug ops are never used. If a module doesn't compile, the simulator stops and prints the Teal errors.

Each run works like this:

1. `activate` is called at gameTime 0, with `seed = --seed` and a synthetic month of 1200 game-time units.
2. The clock advances in `--step` months (weekly by default). A step never crosses a round deadline or a month tick, so every delivery counts toward the correct round.
3. Every step sends the step's deliveries as `delivered` calls, split into `cargo` and `passenger`. While `factsNeeded` is non-nil (always, with `TALLY_FACTS = true`), batches of up to 500 units go as delivery facts that carry only `kind`; bigger batches use the `units` path, which gives the same weights for kind-only facts. Income is added to the balance, then `tick` is called with that balance.
4. Intents are applied to the balance and the world:
   - `cash` changes the balance.
   - `industryMods` raises cargo production.
   - `vehicleMods` takes effect through `state.fx.vehicleMods.TopSpeed`.
   - `clearEffects` resets everything.
5. In the `choosing` phase, the card is picked instantly at the deadline. In the game, the game pauses while the picker is open.
6. When the phase is `ended`, `continueSandbox` is called. The selftest checks that the phase becomes `sandbox`.

## Usage

```sh
make sim ARGS='--rate 150 --rate-growth 0'      # or: uv run tools/quota_sim.py ...
make sim ARGS='--help'
make sim ARGS='--selftest'                        # built-in checks against the real logic
```

| Option | Meaning (default) |
|---|---|
| `--set KEY=VALUE` | Override a `quota_config` field before `new()`. Repeatable. Values parse as bool, int, float or string. Unknown keys are rejected. |
| `--rate`, `--rate-growth` | Deliveries per month at run start (100), plus deliveries/month added each month (4). |
| `--balance`, `--infinite-money` | Starting balance (5M). `--infinite-money` passes `balance = nil`, which skips the bankruptcy check. |
| `--income`, `--income-growth` | Net income per month at start (300k), plus income/month added each month (5k). |
| `--speed-elasticity` | Delivery gain per TopSpeed gain (0.7). |
| `--prod-elasticity`, `--cargo-share`, `--industries` | Crude `industryProd` model (0.7, 0.5, 20). |
| `--noise` | Per-step uniform noise on deliveries, e.g. `0.2` for ±20%, seeded (0). |
| `--step`, `--max-months` | Tick step in months (0.25), and a cap on run length (1200; the run ends with `limit`). |
| `--strategy first\|random\|greedy` | Card pick strategy (`greedy`). |
| `--picks a,b,...` | The i-th pick takes the i-th id. If that card isn't in the offer (offers come from the logic's RNG), the simulator uses `--strategy` for that pick and marks it with `*`. When the list runs out, `--strategy` takes over. |
| `--seed`, `--runs N` | Seed `S`. With `--runs`, seeds S..S+N-1 run and only aggregate stats are printed. |
| `--json`, `--verbose` | Machine-readable output, and every intent/log line (a single run prints them; with `--json` they go in `log`). |

A single run prints one row per round: round, boss/rule (the boss at round start and the scoring rule after the pick), months, quota (after the pick), delivered, result (`pass`, `FAIL`, `bankrupt`, `limit`), reward, balance at round end, the offer shown at round start, and the pick that applied to that round. A summary line follows.

`--runs` prints the distribution of rounds cleared (mean, median, p10, p90 and a histogram), end reasons, mean months, mean total delivered and how often each card was picked.

## Example questions

```sh
# How many rounds does a steady 150 deliveries/month network survive?
make sim ARGS='--rate 150 --rate-growth 0'
make sim ARGS='--rate 150 --rate-growth 0 --runs 200 --strategy random'

# Compare GROWTH 1.4 vs 1.6 (noise makes the seeds differ more)
make sim ARGS='--runs 200 --noise 0.2 --set GROWTH=1.4'
make sim ARGS='--runs 200 --noise 0.2 --set GROWTH=1.6'

# Does the bankruptcy rule trigger with negative income?
make sim ARGS='--income -500000 --income-growth 0 --balance 1000000 --rate 200 --verbose'

# Script a pick order
make sim ARGS='--picks extension,lean_year,austerity --strategy first'
```

## The greedy strategy

The greedy strategy projects the round that just started for each offered card. It computes deliveries (current progress plus the world model up to the possibly moved deadline, with the card's speed and production effects) divided by the quota (with the card's multipliers).

- **Behind** (projected ratio below 1.15 with no card): it picks the card with the highest ratio.
- **Ahead:** it picks by value, so the ratio must stay at 1.15 or above. Value counts permanent reward multipliers, permanent quota cuts, speed and production gains, and cash scaled by the round reward. It penalizes cash costs the balance can't cover.

The weights are rough, and the strategy is meant as a decent player, not an optimal one.

## Model assumptions and limits

- **It tests logic and balance, not engine integration.** Nothing here checks the adapter (`quota.script.tl`), `quota_effects`, the GUI, events, journal entries, pausing or save/load. `make test` and the playtest (`TESTING.md`) cover those.
- **Deliveries are a linear trend times effect factors.** The real network's growth comes from player investment, which is not modelled: rewards and income don't buy more deliveries. Calibrate `--rate`/`--rate-growth` from the playtest's monthly `[QuotaRun] month N: progress=...` log lines.
- **Speed and production effects are crude.** Speed uses a single elasticity on all deliveries. Production uses one elasticity on the cargo share; `boomtown` (3 random industries) counts as 3/`--industries` of the full effect. Comfort, pollution and noise do nothing here.
- **Money:** income is a linear trend, and only `cash` intents change it otherwise. There are no loans, so a negative balance just accumulates red months (the real escape hatch is the base loan system).
- **Picks happen at the deadline with zero delay.** In the game, the clock keeps running while the picker is open and the player has unpaused.
- **Scoring rules are under-modelled (v2.1).** Facts carry only `kind`, never `cargoType`, `toTown`, `fromTown` or `carrier`. So rules score through their kind weights only: `freight_only` and `commuter_rush` are modelled, but `local_hero` and `specialist` can never be drawn (no tally, so no target: those bosses are replaced and `local_hero_card` is never offered), `rail_day` counts every cargo unit as an unknown carrier (×1), and `long_haul` counts everything ×1. The rules' `quotaMult` assumes a cargo share of about 10% (`quota_rules.tl`); the sim's default `--cargo-share 0.5` makes `freight_only` far easier than intended, so use `--cargo-share 0.1` when judging rule balance. The greedy strategy values rule cards by their kind weights and quotaMult only.
- **METRIC = "stats" is not modelled.** Ticks pass no `statsTotal`, so use the default `METRIC = "events"`.
- `MONTH` is a synthetic 1200 units. Only ratios matter to the logic, so its value doesn't change any result.
- **Determinism:** the card offers come from the logic's own LCG, seeded by `--seed` through `activate`. Random picks and noise use Python's `random.Random(seed)`, so the same arguments give the same output.

## Balance notes from the first runs (current defaults: BASE_QUOTA 2500, GROWTH 1.6)

- Round 1 needs about 70 deliveries per month, steady (2500 over 36 months). The selftest checks that 73/month passes and 66/month fails.
- The required monthly rate grows 1.6× per round: about 167, 267, 427, 683, 1092 and 1748 per month for rounds 2 to 7. Steady networks clear 1 round at 70/month, 2 at 150 to 170, 3 at 300, 5 at 700, and about 7 at 1500/month.
- A linearly growing network falls behind the exponential quota within a few rounds. 100 + 4/month clears about 5 rounds with greedy picks (about 4.2 with random picks). Doubling the growth adds about 2 rounds: 2/month clears 3.3, 8/month clears 7.1 and 16/month clears 9.2.
- Changing GROWTH from 1.6 to 1.4 raises the mean from about 5.1 to about 8.6 rounds cleared (greedy, ±20% noise, 200 seeds).
- The card picks are worth about one round: greedy averages 5.1 and random 4.2 at the defaults.
- With positive income, bankruptcy never triggers. Round rewards (2M × r) are small next to a typical income, so the money cards matter mostly through their quota and deadline side effects.
