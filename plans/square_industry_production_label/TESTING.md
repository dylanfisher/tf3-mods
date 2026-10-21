# Industry Production Label: in-game test checklist

Status: open checks for revisions 1-6 plus the standing regression list (§3-§6). Passed checks are in `HISTORY.md`.

Phase 3 of `PLAN.md` (phases now in `HISTORY.md`). Setup: `make link`, start TF3, enable **Industry Production Label** in the mod list, then load or start a game. Afterwards, check the game log for `square_industry_production_label` errors.

## 1. The hook works at all (biggest risk)

- [ ] Note where the pill sits. `HudIconMasterGame` puts children in a `BoxLayout` with no explicit orientation (`hud_icon_toolbox.tl:369`), so the pill may land **below** the stock pill rather than beside it. Record which, and add a screenshot. If it's below and that looks wrong, decide in phase 2 whether CSS on our own recipe can fix it. Do not restyle the base master layout.
- [ ] Industries **without** an output (none in base, but check any input-only modded ones) show no extra pill and no empty frame.

## 2. Glyph (resolved: no glyph)

The first in-game test showed `▲` as `?`: the HUD font has no such glyph (the CJK fallback does not help there). The prefix is gone (`model.PREFIX = ""`); the pill is marked as capacity by the base industry icon (`model.CAPACITY_ICON`).

- [ ] The pill shows the factory icon and a bare number, no `?` or box anywhere.
- [ ] The factory icon reads as "industry production", not as something else. If not, swap `model.CAPACITY_ICON` (one constant).

## 3. Value matches the industry window (capacity)

- [ ] Open an industry window. The pill number equals the window's **Production** number (tooltip "Production"; headline font for raw producers, small font next to "Current Production" for processors) for each output, **not** "Current Production". It updates within ~2 s when it changes (for example after a boost or an expansion).
- [ ] Fresh game, fishing ground with full stock (300/300), not served: the pill shows `34` (the same as the window).
- [ ] A raw producer (coal mine, forest, fishing grounds) and a processor (steel mill, food factory) both match.
- [ ] Multi-output industry (if any in the current economy): each entry shows its cargo icon after the factory icon (enabled from 2 outputs, `model.ICON_MIN_OUTPUTS` in `production_label_model.tl`), and the order and numbers match the window.
- [ ] Large numbers use the game's thousands separator (`lang_util.formatInt`).

## 3b. Producing vs idle style

Both states have white text; only the background colour differs (PLAN "Format").

- [ ] **Producing** (served raw producer, or a processor with input): dark green pill, white text. Clearly different from the blue stock pill above it.
- [ ] **Idle** (processor with no input; freshly placed industry): neutral dark (black, semi-transparent) pill, white text, number still shown.
- [ ] Both are as easy to read as the stock pill, in daylight and at night.
- [ ] If both states look the same dark colour, the scoped background selector lost to base `!hud-icon-background`. Check `R::HudIconMasterGame R::ProductionLabelHudIcon BoxLayout!production-label-producing !hud-icon-background` in `production_label.css.lua`.
- [ ] Raw producer with a **full stock and no transport**: note whether it shows idle or producing. That depends on whether the engine's `produceFrequency` drops to 0 then (PLAN "Open risks"). If it stays "producing", decide whether that's acceptable or whether to add a stock-full check.
- [ ] The state switches within ~2 s after you start or stop serving an industry. Note how long `produceFrequency` takes to react, since it may be averaged over time.

## 4. Styling

- [ ] Our pill has the **same height, icon size and text size** as the stock pill (26x26 icon, `font-scale-annotation`).
- [ ] Multi-output industry (if any): each pill shows the factory icon and then the cargo icon, with a small gap between them.
- [ ] Spacing between our pill and the stock pill looks like the spacing between stock entries.
- [ ] Zoom out until the stock numbers disappear (`hud-lod-far`). Our pill disappears completely, icon included, both producing and idle (no empty background box).
- [ ] Hovering or clicking the industry label still works as before (our recipe is mouse-transparent).

## 5. Compatibility and save safety

- [ ] Add the mod to an existing save: no warning beyond the normal mod-change notice, and labels appear.
- [ ] Save, disable the mod, reload: the save loads, the labels are gone, and there are no errors in the log.
- [ ] Campaign/mission industries (official mods also set `isIndustry`) get the label too.
- [ ] Any construction that already has its own `hudIconScript` (landmarks, HQ, pollution cleanup facility) is unchanged. Those aren't industries anyway.
- [ ] Achievements are still possible (`cosmetic: true`), as shown in the mod list.

## 6. Performance

- [ ] On a large map with many industries visible, there's no noticeable FPS drop or periodic stutter compared with the mod disabled. Each label runs `getIndustryProductionData` per output every 2 s (`REFRESH_INTERVAL`; base `onStepTimer` jitters by default, so labels shouldn't all fire on the same frame). If it stutters, raise `REFRESH_INTERVAL`.

## 7. Pickup rate pill (2026-10-07, PLAN "Pickup rate pill")

`pickup.DEBUG` is `true` in `content/production_label/production_label_pickup.tl` for this test. After loading a save with a few cargo lines, copy these log lines (search `square_industry_production_label: pickup`):

- `pickup cache built in <ms> ms: <n> station groups, <n> lines, <n> cargo stops, <n> industries with pickup, <n> stopIndex mismatches, <n> fallback stations` (once).
- `pickup lookup <entity>: hit {...}` or `miss` (first 5 labels).

Checks:

- [ ] A line that only **unloads** at a station near the industry (cargo config without the output cargo, or a station only delivering inputs) adds nothing.
- [ ] A line stopping **twice** at the same station group (or at two terminals of it) counts once.
- [ ] **Mixed cargo:** a line loading two cargos at the group adds its full rate to each (known over-count, PLAN). Just note it.
- [ ] **No lines:** an unserved industry shows no pickup pill and no empty box.
- [ ] Zoom out (`hud-lod-far`): the pickup pill disappears with the production pill.
- [ ] **Performance:** 2026-10-07 small save: 2.0 ms for 35 station groups / 19 lines; the HUD runs on `Main Pool N` worker threads and the cache is shared across them. note the build ms on a large save; no periodic stutter every 15 s. If it stutters, raise `pickup.REFRESH_INTERVAL`.

## 8. Mod settings (2026-10-07, PLAN "Options")

The mod selection (new game, or "load game" → mods) shows two settings for the mod, both **On** by default: "Show production" and "Show line pickup rate". The log line after loading says which are on: `loadConstruction modifier registered (settings at load: production on, pickup on, warehouse on)` (older wording before the live-settings fix: `(production on, pickup on)`).

- [ ] **Default:** a new game with the settings untouched shows both pills (production, and pickup under it where a line serves the industry).
- [ ] **Pickup off** (new game): only the production pills; no pickup pill anywhere, even at a served industry. Log: `(production on, pickup off)`, and no `pickup` warnings.
- [ ] **Production off** (new game): only the pickup pills, under the stock pill; unserved industries show just the stock pill. Multi-output industries still show the cargo icon on the pickup pill. Log: `(production off, pickup on)`.
- [ ] **Both off** (new game): no extra pill at all, the industry label looks like vanilla. Log: `(settings at load: production off, pickup off, …)`; the modifier is still registered, `hudIconFn` returns an empty layout.
- [ ] **Existing save:** load a save that used the mod with both on, switch pickup off in the mod settings, load: production only. Save, switch it back on, load again: both pills. No warning about changed mods beyond the normal notice, no log errors.
- [ ] **Existing save, both off then on:** the labels come back after re-enabling (the modifier is registered per load).

**Settings read live (PLAN "Settings read live (2026-10-07)").** The settings are now read in the HUD from `getModParams()` each time a label is built, not baked into the constructions. The log line now reads `loadConstruction modifier registered (settings at load: production on, pickup on, warehouse on)` and is printed even with everything off (the modifier is always registered).

- [ ] **Toggle in an existing save without restarting the game → change applies:** with a save loaded, go back to the main menu, load the same save, switch one setting (e.g. Show line pickup rate Off) in its mod settings, load: the change applies (pickup pills gone). Repeat for Show production and Show warehouse rates, and switch each back On the same way.
- [ ] **No crash / no warning on load:** the HUD reads `getModParams()` off the GUI thread (PLAN open risk). Loading a save with industries on screen must not crash, and the log must have no `could not read the mod settings, showing all pills` warning. If that warning appears, every pill shows whatever the settings say: report it with the error text.
- [ ] Log hint: the `settings at load:` part of the log line shows what `runFn` saw. If it says `off` for a setting but its pills still show (or the reverse), the HUD read different values: report both.

## 9. Warehouse rates (2026-10-07, PLAN "Warehouse rates (2026-10-07)")

Mod settings now show a third option, **Show warehouse rates** (default On). Log after loading: `loadConstruction modifier registered (production on, pickup on, warehouse on)`.

- [ ] **Label appears:** a warehouse with cargo going in and out (an existing save with an active warehouse is easiest) shows, under the vanilla stock pill, an incoming row (box + down arrow icon, cargo icon, number, blue-grey pill) and below it an outgoing row (box + up arrow, cargo icon, number, dark red pill). If **no** warehouse ever shows it while industries do, detection failed (PLAN open risk "fileName format"): report the warehouse's construction file name if you can find it.
- [ ] **All five warehouse types / eras** (bulk, liquid, flatbed, goods, universal) get the label.
- [ ] **Numbers:** open the warehouse window → Statistics. Per cargo, incoming + outgoing pills summed over cargos should be in the same order of magnitude as the chart's latest Incoming / Outgoing values (the chart sums all cargos). Note if the label is ~0 while the chart shows traffic (wrong log name or entity).
- [ ] **Which cargos:** only cargos that moved show; busiest first; a cargo that only comes in shows `0` in the outgoing row. A fresh, unserved warehouse shows no extra pill and no empty box.
- [ ] **Universal warehouse with many cargos:** at most 6 pairs; the label width is acceptable.
- [ ] **Colours / icons:** the incoming pill is clearly different from the blue stock pill above it; the in/out icons read as "in" and "out". White text readable day and night.
- [ ] **Updates:** start a new line delivering to the warehouse; numbers grow within a few seconds of game time (the log is per year, so it ramps up gradually).
- [ ] **Far zoom:** the warehouse pills disappear with the stock numbers.
- [ ] **Toggle off** (Show warehouse rates = Off, load): warehouse labels look vanilla; industry pills unchanged. Log `(settings at load: …, warehouse off)`.
- [ ] **Toggle in an existing save without restarting the game → change applies** (the reported bug): load a save with warehouse pills showing, back to the main menu, load it again with Show warehouse rates = Off: warehouse pills gone. Again with On: they come back. Log `(settings at load: …, warehouse off)` then `on`.
- [ ] **Industries unaffected:** production and pickup pills on industries look and behave as before (§3, §7).
- [ ] **All three off:** no extra pill anywhere. Log `loadConstruction modifier registered (settings at load: production off, pickup off, warehouse off)` (since PLAN "Settings read live", the modifier is always registered).
- [ ] **Only warehouses on** (production and pickup Off): industries vanilla, warehouses labelled.
- [ ] **Existing save:** add the mod (or update from revision 2) to an existing save with warehouses: loads without warnings beyond the normal notice, warehouse labels appear. Save, remove the mod, reload: no errors, labels gone.
- [ ] **Performance:** a save with several busy warehouses: no stutter compared with the mod disabled.
- [ ] Log: no `no warehouse label for entity` warnings.

## 10. Show only while holding Shift (2026-10-19, PLAN "Show only while holding Shift (2026-10-19)")

Mod settings show a fourth option, **Show only while holding Shift** (default On). Log after loading:
`show only while holding Shift: on`.

- [x] **Default On:** a busy area shows only the vanilla stock pills. Holding Shift on the map shows every
  label's pills at once (within ~0.1 s); releasing hides them.
- [x] **Selected:** click an industry: its window opens and its pills stay while the window is open, Shift or
  not; closing the window hides them. Same for a warehouse. Log `window entity X -> construction Y` once.
- [ ] Two windows open (industry + warehouse): both keep their pills; closing one leaves the other's.
- [ ] **Other tools:** Shift while building (road / track / construction menu), in the line manager or with a
  layer open: no pills.
- [ ] **Passenger Destinations / Line Manager Plus active:** Shift hover arrows and Shift-click still work;
  the pills show at the same time and don't vanish while the arrows show.
- [ ] No gap or empty card in the industry / warehouse window from our invisible plugin.
- [ ] **Off:** every label shows its pills all the time, as before.
- [x] No Lua errors in the log (the hover version's `hasExpired` error is gone with the selector hook).
  Verified 2026-10-20 (live session ~04:30Z, user: "looks good"): Shift and selected work, no Lua errors,
  `window entity 193532 -> construction 142962`.
- [ ] **Performance:** with Shift up, SQPERF `read_industry` / `read_warehouse` only for open windows.
