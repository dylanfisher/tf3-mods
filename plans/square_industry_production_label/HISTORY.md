# Industry Production Label: history

Status: archive. Text moved verbatim out of `PLAN.md` and `TESTING.md`, newest first. Read only to learn why something is the way it is.

## 2026-10-12: moved from PLAN.md (finished phases, resolved risks, superseded decisions)

From the top-level sections:

## Phases

1. **Build.** Scaffold the mod (`make new-mod`), then add the modifier, recipe, CSS and pure helpers (a format function plus "pick output cargos from a stock list table") with tests in `tests/square_industry_production_label/`. Done when `make check`, `make test` and `make validate` pass for the mod.
2. **Review.** Run the validator agent plus a code review of the phase 1 diff, then fix the findings.
3. **In-game test.** Follow `TESTING.md` (user).

From "Open risks" (resolved: TESTING §1 confirmed the hook 2026-10-06):

- Whether a `loadConstruction`-modifier-set `hudIconScript` is honoured. This is unverified until tested in game, and the fallback is listed above.

From "Pickup rate pill" > "Open risks" (resolved in game 2026-10-07, TESTING §7):

- `getStationCatchables` entity == label `params.entity` (else every lookup misses: no pickup pill anywhere). The debug lookup lines show it.
- Fishing grounds / oil platform built-in terminals: whether catchables or the construction fallback find the industry.
- `stopIndex` base (0 assumed; mismatches are logged and handled by the fallback scan).
- Rate scale: `calcLineStationThroughput` is per year like the production numbers? Compare in game.

From "Options (2026-10-07)" > "Decisions" (rows superseded by "Settings read live"):

| Topic | Decision |
|---|---|
| Where read | **Superseded 2026-10-07 by "Settings read live (2026-10-07)".** Was: once per game load in `runFn(configDict, allModParams)` (`content/mod.script.lua`; `modscripts.md` "runScript"), the only place it is sure to be current: `runFn` runs on every load, the HUD's module state survives loads. Not `api.engine.config.getModParams()` (`api/tealdef/api/engine.d.tl:1806-1807`) in the HUD: it is not marked GUI-thread only and better_minimap uses it in GUI code, but a read-once cache there would keep the previous game's choice after loading another save, and reading it per call is wasted work. |
| Transport to the HUD | **Superseded 2026-10-07 by "Settings read live (2026-10-07)".** Was: as the hudIconScript's ScriptRef `params` (`{showProduction, showPickup}` booleans): HudIconMasterGame passes `customRecipe.params` to `hudIconFn` as `captureParams` (`base/content/gui/main/hud_icon_toolbox.tl:353-356`; `ScriptRef.params`, `api/tealdef/api/type.d.tl:1388-1389`; `constructions/basics.md` "HUD Icon Script"). Base passes booleans the same way (`industries/oil_platform/oil_platform.con.lua:153-156` `snappingWater = true`). No engine read, no thread question. `model.options(captureParams)` treats `false` and `0` as off, anything else (incl. a missing table) as on. |

From "Options (2026-10-07)" (obsolete risk):

### Open risks

- *(Obsolete since "Settings read live (2026-10-07)": the params now only carry `kind`.)* ScriptRef `params` survive the construction converter as a Lua table with booleans (base relies on it for `updateScript` / `formatValueScript`, but not seen for `hudIconScript` in base). If they were dropped, both pills would simply stay on (the default); "both off" still works because it registers nothing. TESTING §8.

From "Settings read live (2026-10-07)" (the bug report and cause behind the change):

**Bug (user report, revision 3 unreleased):** switching "Show warehouse rates" Off in the mod settings and loading the game did not remove the warehouse pills. The industry toggles were built the same way, and the TESTING §8 existing-save checks had never been ticked.

**Cause (hypothesis, not confirmed):** the settings were read in `runFn` and baked into the construction resources by the `loadConstruction` modifier, either as the `hudIconScript` ScriptRef params (`{showProduction, showPickup}`) or by not setting the script at all (warehouse off, both industry pills off). The game apparently does not re-run construction loading (or reuses the loaded construction resources) when only the mod params change, so the previous choice stays in the resources. Whatever the exact cause, baking settings into resources is fragile.

## 2026-10-12: moved from TESTING.md (passed or obsolete checks)

From "1. The hook works at all":

- [x] Industries show an extra pill next to or below the output stock pill (`🐟 300`). Confirmed 2026-10-06: it sits below. Now expected: `[factory icon] <n>`.
  - If **nothing** shows, the `loadConstruction` modifier's `hudIconScript` is probably ignored. Next step is the PLAN fallback: in `postRunScript`, `api.res.constructionRep.getAsTable/setAsTable` for each `isIndustry` construction.
  - If the log shows a script-resolution error for `square_industry_production_label::/production_label/production_label.script@hudIconFn`, try `square_industry_production_label::production_label/production_label.script@hudIconFn` (no leading slash) in `content/mod.script.lua`.

From "7. Pickup rate pill" (passed 2026-10-07):

- [x] **Catchables identity.** Confirmed 2026-10-07: cement-type plant shows `[factory] 137` / pickup `195`; log `hit {15=195}`. Industries served by a cargo line show a second pill `[line manager icon] <n>` below the production pill. If **no** industry ever shows it and the lookup lines all say `miss` while "industries with pickup" > 0, the catchables entity is not the label entity (PLAN "Open risks").
- [x] **Fishing grounds / oil platform** (user confirmed 2026-10-07) (built-in SHIP terminals): a ship line loading fish there shows the pill. Note whether "fallback stations" is > 0.
- [x] **stopIndex base:** confirmed 0-based 2026-10-07 (`0 stopIndex mismatches`). the build line shows `0 stopIndex mismatches`. If it is about the number of stops, the map's index is 1-based (harmless, the fallback scan handles it, but report it).
- [x] **Rate vs production scale:** pill equals the line window's Rate (user confirmed 2026-10-07). the pill equals the line window's "Rate" of the one line serving the industry (open the line window). With two lines loading the same cargo there, it is the sum. Compare with production: both per year? (A fishing ground producing 79 with a line of rate 112 should read "79 / 112".)
- [x] **Updates:** (adding a vehicle, user confirmed 2026-10-07) add a vehicle or a new line: the pill changes within ~15-17 s. **Paused:** edit a line while paused: nothing changes until you unpause (by design).
- [x] Afterwards: set `pickup.DEBUG = false`. Done 2026-10-07.

From "8. Mod settings" (obsolete since "Settings read live"):

- [ ] If an option seems ignored (e.g. pickup off still shows the pickup pill) while the log line says `pickup off`, the ScriptRef params did not reach `hudIconFn` (PLAN "Options" open risk): report it. *(Obsolete since PLAN "Settings read live (2026-10-07)"; see the checks below.)*
