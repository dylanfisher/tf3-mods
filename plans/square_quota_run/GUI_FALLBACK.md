# Quota Run: GUI fallback (Phase 3, risk R1)

This note is not shipped (it lives in `plans/`). Use it when the HUD does not appear in the playtest.

## What ships

- `content/quota/gui/quota_hud.res.lua` registers `QuotaRunHudPlugin` as `react-plugin ::MainModButtonAreaExtension`.
- `quota_hud.script.tl` (Phase 4 layout) renders a **compact one-row HUD** in the ridge. In `choosing` it adds a **Pick a card** button, and in `ended` it shows a **Run over** button. Each button opens a centered base dialog window: `game_react_globals.getDefaultWindowApi().addSingletonWindow(dialog_react_util.DialogWindow, {...})` with `closable = false` and `x = y = 0.5`. The card choices show the name, with the description in the tooltip and in the window text. The pattern is `.cache/game/base/content/mission/mission_framework/mission_framework_react.tl:136-164`. The reason for the change: the ridge is a `ScrollArea` with `verticalPolicy = AlwaysOff` (`main_mod_button_area.tl:26-31`), so a tall panel is clipped. `react.lua` has no effect hook, so the window opens only from a click. Clicking outside it closes it, and the HUD button reopens it.
- `quota_config.GUI_INLINE_PICKER = true` restores the old layout: one vertical panel with the HUD, the 3 inline card buttons and the end screen. It may be clipped. Use it if the dialog window fails to open (no window, or `no window container` in the log).
- `quota_hud_model.tl` is the pure view model, tested in `tests/square_quota_run/test_hud_model.lua`.
- `quota_hud.css.lua` is loaded the same way as every base `.css.lua`: stylesheets are a resource type found by file extension (`docs/wiki/modding/general/resourcetypes.md`), and nothing references them by path. Its rules are scoped to `R::QuotaRunHudPlugin`.

**Deviation from PLAN §6 Phase 3:** the plan named `::ModEntryPointExtension`. `game.tl` mounts those plugins inside the `EntryPoints` node with `meta = { class = "invisible" }` (`.cache/game/base/content/gui/main/game.tl:574-586`), and `!invisible` means `visibility = "none"` (`default.css.lua:139-142`). That extension point is for invisible controllers, such as the base `StatisticsEntryPoint` (input actions, events, opening windows), so a HUD mounted there can never be seen. `::MainModButtonAreaExtension` is the visible slot for mods, next to the layer buttons at the top left (`game.tl:529-556`, `main_mod_button_area.tl:7-13`).

## How to tell what failed (in `stdout.txt`)

- `Recipe not found: square_quota_run::/quota/gui/quota_hud.script@QuotaRunHudPlugin` means the script failed to load. Look just above that line for a Teal or Lua error.
- `RegisterPluginRecipe() failed: extensionPoint is required` means the base module was loaded a second time from the mod (a cache miss on `"::/gui/main/main_mod_button_area.tl"`).
- No error and no panel means the plugin mounted but the button ridge is clipping or hiding it. Try Fallback A.
- A visible panel with no styling (no dark background) means the `.css.lua` was not picked up. This is cosmetic only.
- A panel whose card buttons are cut off at the bottom (only with `GUI_INLINE_PICKER = true`) means the ridge's `ScrollArea` limits the height. Switch back to the default dialog, use the console picks below, or use Fallback A.
- `[QuotaRun] no window container; use the console commands` means `getDefaultWindowApi()` returned nil. Try `GUI_INLINE_PICKER = true`, or use the console.
- The window opens but the clicks do nothing: check the log for `pickCard ignored …`. The console pick is the fallback.

## Fallback A: game-bar text (proven extension point)

This uses the same mechanism as the base transported plugin (`.cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/`). It shows compact text only, so picks go through the console (see below).

1. Create `mods/square_quota_run/content/quota/gui/quota_hud_gamebar.script.tl` with the content below. It passed `make check` with 0 errors on 2026-10-03.
2. Replace the whole of `quota_hud.res.lua` with the `.res.lua` below. Keep only one registration, so the panel and the text don't both try to mount.
3. Run `make check MOD=mods/square_quota_run`, then restart the game. Resources load at startup.

`quota_hud.res.lua`:

```lua
function data()
	return {
		type = "react-plugin ::GameBarInfoDisplayExtension",
		data = {
			filePath = "square_quota_run::/quota/gui/quota_hud_gamebar.script@QuotaRunGameBarPlugin",
			order = 10,
		}
	}
end
```

`quota_hud_gamebar.script.tl`:

```teal
-- Quota Run game-bar FALLBACK (compact text only; picks via console). See GUI_FALLBACK.md.
-- Model: .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.script.tl
local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
local game_bar_widgets = ug_require "::/gui/game_bar/game_bar_widgets.tl" as GameBarWidgets

local hud_model = ug_require "square_quota_run::/quota/gui/quota_hud_model.tl" as QuotaRunHudModel

local function getFromEngine() : QuotaRunHudView
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript("square_quota_run::/quota/quota.gs")
	if entity == nil or entity < 0 then return nil end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<QuotaRunState>
	local s = gs and gs.state
	if s == nil or s.active ~= true then return nil end
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return hud_model.build(s, gt and gt.gameTime or nil)
end

local QuotaRunGameBarPlugin = react.RegisterPluginRecipe(game_bar_widgets.GameBarInfoDisplayExtension, "QuotaRunGameBarPlugin", function() : TreeNodeId
	local state = engine_react_util.useStepStateTimer(getFromEngine, 0.5)
	local v = state:old()
	if v == nil then
		return nil
	end
	local str : string
	if v.phase == "ended" then
		str = lang_util.format(_("Run over ({reason}) - cleared {n}"), { reason = v.endReason or "?", n = tostring(v.roundsCleared) })
	else
		str = lang_util.format(_("R{round} {progress}/{quota} {months}mo"), {
			round = tostring(v.round),
			progress = lang_util.formatInt(v.progress),
			quota = lang_util.formatInt(v.quota),
			months = v.monthsLeft and tostring(v.monthsLeft) or "?",
		})
		if v.phase == "choosing" then str = str .. " " .. _("PICK A CARD (console)") end
	end
	return builtin.TextView{ meta = { class = "font-scale-headline" }, text = str }
end)

return { QuotaRunGameBarPlugin = QuotaRunGameBarPlugin }
```

## Fallback B: the plan's original mount point (diagnosis only)

You can change the type to `react-plugin ::ModEntryPointExtension` and the recipe's extension point to `(ug_require "::/gui/main/mod_entry_point.tl" as ModEntryPoint).ModEntryPointExtension`. It should load without errors but show nothing (see above). It is useful only to confirm that mod react-plugins load at all.

## Console commands (in-game Lua console, debug mode)

Picks and the sandbox switch work without any GUI:

```lua
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.pickCard", { index = 1 }))   -- 1, 2 or 3
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.continueSandbox", {}))
```

To see the offer (card ids in `offer`) and the rest of the state:

```lua
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "dump" }))
```

Debug ops work only when `quota_config.DEBUG == true`: `endRound`, `addProgress {n}`, `setMonthsLeft {n}`, `bankrupt`, `offer`, `dump`, plus the dev-panel ops (`passRound`, `failRound`, `skipMonths {n}`, `applyCard {id}`, `addMoney {n}`, `addQuotaPct {n}`, `clearEffects`, `reset`, `forceStart`; see TESTING.md "Dev tools", which also has a one-line `qr(...)` console helper). If the Dev window does not open, set `GUI_INLINE_PICKER = true` for the inline Dev toggle. For example:

```lua
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "addProgress", n = 5000 }))
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "QuotaRun", "QuotaRun.debug", { op = "endRound" }))
```

`endRound` and `setMonthsLeft` only move the deadline. The round ends on the next unpaused update.
