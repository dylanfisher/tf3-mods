# Quota Run: API research notes

The tf3-docs-researcher agent produced these notes on 2026-10-03. They are the factual basis for `PLAN.md`. Items marked **UNVERIFIED** must be confirmed in-game before we rely on them.

Shorthand: `API` = `.cache/game/api/tealdef`, `BT` = `.cache/game/base/tealdef`, `BC` = `.cache/game/base/content`, `MOD` = `.cache/game/mods/release`, `WIKI` = `docs/wiki/modding`.

## 1. Entry points and game script registration

- `mod.json` run hooks (`preRunScript`/`runScript`/`postRunScript`, `{ "fileName": "<modId>::/mod.script@fn" }`) only matter for config tweaks. **The game script is discovered by file extension.** Any `content/**/*.gs.lua` is loaded (`WIKI/general/resourcetypes.md:35`, `MOD/urbangames_campaign_mission_01/content/init/init.gs.lua`). It is not referenced from `mod.json`.
- `.gs.lua` format: `BC/mission/mission.gs.lua`, `BC/game_mechanics/subventions/subventions.gs.lua`.
  ```lua
  function data()
    return {
      updateScript      = { fileName = "<modId>::/quota/quota.script@update" },
      handleEventScript = { fileName = "<modId>::/quota/quota.script@handleEvent" },
      -- also: postUpdateScript, guiUpdateScript, guiHandleEventScript; each may carry params = {...}
    }
  end
  ```
- The script module (`.script.tl` or `.script.lua`) returns a table of those functions. Types are in `BT/scripts/gamescript.d.tl`: `GameScript<T>` (:55), `GameScriptWithGui<S,G>` (:61), and `GameScriptState<T>` (:40) with `get/set/hasEventSubscriptions/subscribeToEvent/...`.
- Signatures:
  - `update(userParams, state, dt)`. `dt == 0.0` means paused, so bail out.
  - `handleEvent(userParams, state, src, id, name, param)`.
  - `guiUpdate(userParams, stateReadOnly, guiState)`.
- Examples:
  - `MOD/urbangames_campaign_mission_08/content/mission/rocket/rocket.script.tl:62-90` (subscribe plus update).
  - `BC/game_mechanics/subventions/subventions.script.tl` (update around :243, handleEvent around :368).
- TF2-era wiki pages (`WIKI/scripting/gamescripts.md`, `basics.md`, `userinterface.md`) are WIP. TF3 uses `state:get()/state:set()`, not save/load callbacks.

## 2. Per-savegame scope (do not touch existing games)

- Mods are chosen per game at creation or load (`WIKI/general/modscripts.md:13`). The save stores its `modDescs`.
- A player can add a mod to an existing save. Use `"severityAdd": "Critical"` and `"severityRemove": "Critical"` (`WIKI/general/moddefinition.md:43,59-65`) to warn on that path.
- **Gate:** activate a run only when `handleEvent` receives `id == "" and name == "initNewGame"` (and possibly `initNewGameFromMap`). Treat `state.active == nil` as inert. Base examples: `BC/vehicle/vehicle_modifier.script.tl:60`, `BC/game_mechanics/notifications/notifications.script.tl:686-700`, `BC/game_mechanics/company/company.script.tl:379-392`. **UNVERIFIED:**
  - that `initNewGame` fires for every free game start
  - what `handleLegacy` does for a mod newly added to an old save
- **Avoid** anything global:
  - `api.util.setAppConfig/saveAppConfig` (`API/api/util.d.tl:247,264`)
  - writing files
  - module-level Lua variables holding run state, which persist across loads in one session
  - Keep all state in `state:set()`. `api.gui.game.setGuiSaveData` is probably per-save. It is UNVERIFIED, so avoid it.
- Game script state is very likely saved with the game (base subventions rely on it). This is UNVERIFIED in prose.

## 3. Game time

- `api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)` returns `GameTime`, with fields `gameTime`, `tickCount`, `updateCount`, ... (`API/api/engine.d.tl:425-438`).
- `api.engine.util.getCalendarDate(gameTime.gameTime)` returns `Date{year,month,day}` (`API/api/engine/util.d.tl:1030`). Example: `MOD/urbangames_campaign_mission_02/content/mission/tasks/everything/everything.tl:57-59`. `api.engine.util.getYear()` (:1033).
- Calendar speed is configurable, so don't do raw tick arithmetic. Track rollover by storing the last seen `year`/`month` in state.

## 4. Money

- Player: `api.engine.util.getPlayer()` (`API/api/engine/util.d.tl:1023`).
- Balance: `api.engine.util.finance.getPlayersBalance(player)` (:861). It returns **nil when money is infinite**.
- Add or deduct money with a journal booking (negative amount deducts). Pattern from `MOD/urbangames_campaign_mission_08/content/mission/mission_story.tl:~1012` and `BC/game_mechanics/subventions/subvention_util.tl:127-134`:
  ```lua
  local entry = api.type.JournalEntry.new()
  entry.amount = 1000000            -- negative deducts
  entry.time = -1
  entry.category.type = api.type.JournalEntry.Type.OTHER
  api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
  ```
- There is no bankruptcy mechanic, so we define our own. Loans exist (`BC/game_mechanics/finance/loan.script.tl`), and `Engine.Component.Account{balance, loan}` is at `API/api/engine/engine.d.tl:22-29`. Company value: `api.engine.util.headquarters.getCompaniesValue()` (:901).
- Income since a time: `api.engine.util.finance.calcIncomeSince(time, player)` (:866). Interval balance: `calculateBalance({player}, start, end, maintenanceIncomeOnly)` (:848). Whether these are income-only or net is UNVERIFIED.

## 5. Quota metrics

- **Cargo:** `api.engine.util.headquarters.getTransportedData()` returns `{passengersTransported, cargoTransported}` (`API/api/engine/util.d.tl:898`, `API/api/type.d.tl:150-153`). It's used by the game bar (`BC/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.script.tl`). That it is cumulative is UNVERIFIED. Snapshot it at round start and diff.
- Event alternative: subscribe to `"OnToArriveAtDestination"` and handle `id == "SimCargoSystem"`, where `param.entities` is `{{cargoEntity,{target...}}}`. For passengers: `"OnCompletedLineUsage"`, `id == "SimPersonSystem"` (`BC/game_mechanics/arrival_tracker/arrivaltracker.script.tl:70-125`).
- Logbook: `api.engine.util.logbook.getLogValueMostRecent(player, "itemsTransported"..cargoTypeId)` (`API/api/engine/util.d.tl:261-281`).
- Towns: `town_util.getTownCapacityUsages(town).residential.capacity`, plus rating getters (`BC/mission/tasks/town_size/town_size_task_util.tl:9`, `BC/mission/tasks/town_rating/town_rating.tl:15-35`).

## 6. Entity iteration

- `api.engine.forEachEntityWithComponent(fn, api.type.ComponentType.TRANSPORT_VEHICLE)` (`API/api/engine.d.tl:1704`). Example: `BC/mission/tasks/vehicle_util/vehicle_modifier.tl:45-55`.
- `api.engine.getEntitiesWithComponent(ComponentType, {requireOwnedByPlayer = player})` (:1713).
- Industries and towns: `ComponentType.INDUSTRY` / `ComponentType.TOWN`. Industry stock list: `Engine.Component.Industry.stockList`.
- Read our own state from anywhere (including the GUI):
  ```lua
  api.engine.getComponent(api.engine.system.gameScriptSystem.getEntityForGameScript("<modId>::/quota/quota.gs"), api.type.ComponentType.GAME_SCRIPT).state
  ```
  Example: `MOD/urbangames_campaign_mission_08/content/mission/mission_story.tl:891-893`.

## 7. Commands and modifiers

- `api.cmd.sendCommand(cmd, cb?)`. In the sim thread (game script) it runs immediately. From the GUI it runs on the next sim step (`API/api/cmd.d.tl:1-9,598`).
- GUI to sim: `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "pickCard", {index=i}))` (`BC/game_mechanics/subventions/subventions_gui.tl:157`). The game script must call `state:subscribeToEvent("pickCard")` and check `id == "QuotaRun"`.
- **Vehicle modifiers:** don't call `makeVehicleSetModifiersCmd` directly. The base `BC/vehicle/vehicle_modifier.gs.lua` owns those fields and would overwrite them. Use its event instead:
  ```lua
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "VehicleModifier", "ChangeModifier",
      { entity = e, id = "<modId>_card_X", modifications = { TopSpeed = 1.2 } }))
  ```
  The keys are TopSpeed, Noise, Pollution and Comfort, and they combine additively as `(v-1)`. Apply to new vehicles as they appear by tracking known entities (`BC/mission/tasks/vehicle_util/vehicle_modifier.tl:44-71`).
- **Industry productivity:** `makeStockListSetModifiersCmd(industry, mods)` with `mods.productivity` (`API/api/cmd.d.tl:810`, `BC/industries/industry_workers.script.tl:9-13`). The base worker-boost script resets it, so re-assert periodically.

## 8. GUI

- **HUD and overlay:** a React plugin registered by a `.res.lua` under `content/`:
  ```lua
  function data() return { type = "react-plugin ::ModEntryPointExtension",
    data = { filePath = "<modId>::/quota/gui/quota_hud.script@QuotaHudPlugin", priority = 0 } } end
  ```
  - Recipe: `react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "QuotaHudPlugin", function() ... end)`, with `ug_require "::/gui/main/mod_entry_point.tl"`.
  - It renders at the game UI root as a floating child (`BC/gui/main/game.tl:83-92`).
  - Template: `BC/gui/game_bar/game_bar_display_earnings_plugin/` (`.res.lua`, `.script.tl`, `.css.lua`).
  - Data polling: `engine_react_util.useStepStateTimer(fn)` / `useStepState`.
  - **UNVERIFIED for mods.** No mod example exists. Fallback: `react-plugin ::GameBarInfoDisplayExtension`, which puts a widget in the top bar.
- **Dialog:** `BC/gui/menu/dialog_react_util.tl` `DialogWindow` (choices with onClick). Example: `BC/gui/main/pause_menu.tl:15-45`.
  - It needs a window API: `ug_require "::/gui/main/game_react_globals.tl"` with `getDefaultWindowApi()`. This is UNVERIFIED for mods.
  - **Safer:** render the card choices inline inside our own plugin tree with `builtin.Button{ content = builtin.TextView{...}, onClick = ... }`.
- `_("text")` for UI strings. Money formatting: `api.util.formatMoney(n)`.

## 9. Notifications

- Send from the game script:
  ```lua
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "Notifications", "add",
      { type = "<modId>::/quota/quota_notification.script", params = {...}, autoDismissDuration = 60000 }))
  ```
- A custom type needs two files: `quota_notification.res.lua` (`type = "notification"`, `data = { guiType = "Achievement"|"Info"|"Caution"|"Problem"|"Opportunity", label = _("Quota Run"), initiallyIgnoredType = false }`) and `quota_notification.script.tl` returning `{ useDataState = function() return { title, description, icon } end }`. Template: `MOD/urbangames_campaign_mission_05/content/mission/tasks/lasse/`.

## 10. Ending a run

- `MissionEndWindowContent` only works inside a mission, so don't reuse it.
- Pause with `api.cmd.makeGameSetSpeedCmd(0)` (`BC/mission/guide_system/guide_system_react.tl:150`). Read the current speed from `ComponentType.GAME_SPEED`.speedup.
- No verified "quit to main menu" API exists. Offer "continue in sandbox" instead.

## 11. Localization

- Nothing is required. `_("English")` falls back to the key. An optional `strings.json` can sit at the mod root. Whether `_()` works in the sim thread is UNVERIFIED, so build user-facing text in the GUI and notification scripts.

## 12. Teal

- The game compiles `.tl` at load (it bundles `BC/base/tl.lua`, Teal 0.24.1+dev), so there is no build step.
- `ug_require` paths:
  - `"::/x.tl"`: base game
  - `"<modId>::/x.tl"`: our mod
  - `"/x.tl"`: current mod
  - `"rel.tl"`: relative
  - `../` is not allowed.
- Custom module types go in `.d.tl` files placed next to the module.

## 13. Logging and debugging

- `debugPrint(x)`. Also `log.message/warning/error` (`BT/scripts/log.d.tl`).
- Log file: `~/Library/Application Support/Steam/userdata/<steamid>/3493540/local/crash_dump/stdout.txt`.
- Debug mode is already on, which enables the in-game Lua console. Fire events from it with `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "debug", {...}))`.
