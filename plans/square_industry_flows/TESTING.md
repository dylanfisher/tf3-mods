# Industry Flows: in-game test checklist

Phase 3 (full panel). This file is not shipped (it lives in `plans/`). Use a **copy** of a save, or a new free game, with several industry types on the map (fishing grounds, a farm, a forest + saw mill, an oil well + refinery) and, ideally, one or two lines that already deliver cargo (for active arrows). Phase 1 passed in game.

Report back every `[IndustryFlows]` log line, any Lua error, and a screenshot of the panel.

## 1. Setup and log tail

1. Run `make link`, then tick **Industry Flows** in the mod list.
2. Keep the log open in a terminal:
   ```sh
   tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -i "IndustryFlows\|square_industry_flows\|error"
   ```
3. Expect `square_industry_flows loaded` while the game loads.

## 2. Opening the panel

- [ ] Click **Flows** in the top-left mod button ridge: the **Industry Flows** window opens at the left edge. No Lua error.
- [ ] The log shows `[IndustryFlows] industry types: ...` once, as `Name = key xN` per type. **Copy it into the report** (localized names vs keys).
- [ ] Top to bottom: search field (placeholder "Search industries or cargo..."), "Industry types" heading, one row per type on the map (checkbox, name, count at the right edge), the Outputs / Inputs / Potential links checkboxes (all ticked), "Select an industry type to show its cargo flows.", the legend line.
- [ ] Nothing is selected and **no arrows** show.
- [ ] Cargo icons on each type row, between the name and the count: inputs, a small chevron, then outputs (e.g. oil refinery: oil > fuel; a raw producer like an oil well shows only oil). Hovering an icon shows the cargo name. Note whether the chevron is visible and sized sensibly (unverified: `::/gui/builtin/combobox/arrow_right.tga` at 10x10).
- [ ] Layout: the window is about 400 px wide; long names fit or wrap; counts line up at the right; nothing is clipped. Note anything that looks off (the CSS `gravity` / `size` values are unverified).
- [ ] With more than 8 types on the map, the list scrolls (fixed height, about 8 rows) and the mouse wheel scrolls it. Note whether the wheel also zooms the map.

## 3. Search

- [ ] Click the field and type `fish`: the list narrows **as you type** (each keystroke), to the fishing grounds row. No stutter while typing.
- [ ] Case and spaces do not matter (`FISH`, ` fish `). Typing part of the file name works too (e.g. `oil_`).
- [ ] Searching a **cargo** name finds the industries that consume or produce it: `fuel` shows the oil refinery; the crude oil cargo name shows both the oil well and the refinery. Note whether cargo names look localized (not raw ids).
- [ ] A query with no match shows `No industry type matches "xyz".`
- [ ] Clearing the field shows all types again.
- [ ] While typing, map hotkeys do not fire (e.g. typing `f`, `p` or a digit does not toggle layers/pause/speed). Escape in the field: note what happens (cancel or close).

## 4. Selecting types (multi-select)

- [ ] Tick **Fishing grounds**: arrows appear **at once** (no 2 s wait) for every fishing ground; the heading reads "Industry types (1 selected)" and a **Clear** button shows; the summary reads "{n} industries · {links} links · {active} active". The log shows `[IndustryFlows] ::/industries/fishing_grounds/...: N industries, L links (A active), D drawn`.
- [ ] Clicking the **name** (not only the box) also toggles the row.
- [ ] Search `saw`, tick the saw mill: both types' arrows show; input arrows (forest → saw mill) use the "Input" colours, outputs the "Output" colours.
- [ ] Search `farm`: the two earlier selections are hidden by the search but **stay selected** (arrows still drawn); the list shows "+2 selected, not in this list".
- [ ] Untick a type: its arrows go away at once.
- [ ] **Clear** deselects everything: no arrows, the empty-state text returns, the Clear button hides.

## 5. Toggles

- [ ] With fishing grounds + saw mill selected, untick **Outputs**: only supplier arrows remain (forest → saw mill); the counts drop. Tick it again.
- [ ] Untick **Inputs**: only output arrows remain.
- [ ] Untick both: no arrows; summary "… 0 links · 0 active".
- [ ] Untick **Potential links**: only moving (active) arrows remain; with no deliveries yet, none.
- [ ] Each change is immediate.

## 6. Refresh and performance

- [ ] Run at high speed for a minute with a delivering line: when a link starts carrying cargo it turns bright and moving within about 2 s, and the active count rises.
- [ ] Select **several** types (5+, including a common one like farms) and pan/zoom: no stutter every 2 s, no frame drop. If the summary shows "Showing 400 of N (active first)", the cap works. Note the frame rate with and without the panel open.
- [ ] Type in the search field with several types selected: still no stutter, and the arrows **stay drawn** while you type (the panel reuses the same `LayerConfig` userdata across re-renders until the view changes; the base game always builds a fresh one, so this is unverified. If arrows vanish or freeze while typing, drop `layerRef` in `flows_window.script.tl` and call `buildLayerConfig` every render).

Performance pass (2026-10-07):

- [ ] **Action reused across re-renders.** Type in the search field and tick / untick a type that is *already* hidden by the search, so the view stays the same: the arrows stay drawn without a flicker, HUD labels stay put, and hovering an industry still shows its tooltip. (The panel now passes the same action function to `setActionFn` until the view, HUD filter or renderer changes; before, every render re-bound the action.)
- [ ] **Selecting still updates the action.** Tick a new type, untick one, toggle Outputs / Inputs / Potential: the arrows change at once, as before.
- [ ] **HUD filter still honoured.** With the panel open, hide a HUD category (e.g. vehicles) in the HUD Filters layer, come back to the panel: the category stays hidden. If it shows again, the `samePreFilter` compare in `flows_window.script.tl` misses a change.
- [ ] **No poll while shelved.** Select farms, click an industry so its window stacks on top (panel hidden), wait 10 s, close it: the panel and arrows come back, and **within about 2 s** the arrows and summary match the map again (the first tick after unshelving re-reads). Use high speed so active links change meanwhile. Optional: add a temporary `log.message` in `poll()` to confirm no `[IndustryFlows]` reads while the entity window is open.
- [ ] **Screenshot / hidden GUI.** If the GUI can be hidden with the panel open (e.g. screenshot mode), arrows keep updating (the check uses the window's own visibility, not `isVisibleRecursive`).
- [ ] **Cargo icons.** Icons and their tooltips on the type rows look the same as before (now built from a per-cargo cache instead of `makeCargoIcon`).

## 7. Persistence (GUI memory only)

- [ ] With a query, two selected types and Potential off, close the panel (X or the Flows button): arrows disappear.
- [ ] Reopen: the same query, selection and toggles are back, and the arrows return.
- [ ] Open another tool (Statistics) and come back via the Flows button: still restored.
- [ ] Load another save (or reload this one): note whether the choice is kept or reset (either is fine; nothing is stored in the save).

## 8. HUD labels and other windows

- [ ] With the panel open, town names, station and industry labels and vehicle icons still show (phase 3 added the HUD icon config). Hide some HUD categories in the layer HUD filter first: they stay hidden while the panel is open.
- [ ] Hover an industry: tooltip shows. Click it: its window opens **on top**, the Flows window hides, and only that industry's arrows show. Close it: the Flows panel and its arrows come back with the same state.
- [ ] Open Statistics or Finances while the panel is open: the panel closes. Open the panel while Statistics is open: Statistics closes.

## 9. Saves

- [ ] Save, quit to menu, reload: no warning about the mod; the panel works again.
- [ ] Disable the mod and load that save: no warning (severity None/None, nothing is stored).
