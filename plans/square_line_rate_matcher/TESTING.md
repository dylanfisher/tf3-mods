# Line Rate Matcher: in-game test checklist (phase 3f, GUI)

Mod: `mods/square_line_rate_matcher` (linked into the staging area by `make link`). **Apply buys and sells
vehicles**: use a test save (the probe's WC Logs save is ideal).

## Setup

1. In the game's mod list enable **Line Rate Matcher**. **Disable DEV Line Rate Matcher Probe**
   (`square_line_rate_matcher_probe`): it mounts its own "RM" row in the same place. mod.json marks the two as
   incompatible, so the game should warn when both are on, and the log says
   `[RateMatcher] the DEV probe ... is active too` if you keep both.
2. Keep **Line Editor Undo** (`square_line_revert`) or **Line Manager Plus** on, to test coexistence.
3. Follow the log in a terminal:

   ```
   tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -E 'RateMatcher|LineRevert|ERROR|error'
   ```

   Expect `[RateMatcher] installed (order 260)` at GUI start. New in 3c: on open, `[RateMatcher] timing line ...`
   (the round-trip split the model estimate uses) and `[RateMatcher] price model ...` (every price candidate); after
   a buy `[RateMatcher] clone charged: balance A -> B = X ...`. Afterwards, to save the run:
   `grep RateMatcher ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt > plans/square_line_rate_matcher/gui_run1.log`

## Phase 3f polish (2026-10-11, check these first)

| # | Step | Expect |
|---|---|---|
| f1 | **Right edges** | The stats row's last cell, both tables (incl. the selected row's highlight) and the three panels end at the same right edge; nothing pokes out of a panel (3e: the Running costs cell did, top right) |
| f2 | **Tags** | "suggested" (top table, next to the target box) and "best" are plain light-blue text, the colour of the Line Manager's Balance value; no background; "suggested" not cut off |
| f3 | **Disabled Apply** | After "Bought 1 vehicle for this line." (nothing left to apply) Apply is an outlined button with readable dimmed text, not grey on grey; enabled again it is the filled primary button |
| f4 | Widths | If f1 is off by a constant (e.g. everything 16-48 px short of the panel edge), our assumption that a StyleSheet `size` excludes padding is wrong: tell us roughly how much |

## Phase 3e polish (2026-10-11, check these first)

| # | Step | Expect |
|---|---|---|
| e1 | **No stray bar** | No scrollbar or slider-like artifact in any corner (the tables now have `scrollPolicyVertical = AlwaysOff`). **Both tables show all their rows** (if rows are cut off, the table no longer grows with its rows: tell us) |
| e2 | **Stats row fits** | Cells Rate / Vehicles / Per vehicle / *Running costs per year*, the last one widest; "$182,880" inside its cell, nothing past the panel edge |
| e3 | **Tags** | "suggested" (top table and next to the target box) and "best" (comparison) are the same green tag with dark text; readable, not cut off |
| e4 | **Price** | The column formerly "Buy now" is "Price"; tooltip "Price of the new vehicles / minus what the vehicles leaving the line sell for." |
| e5 | ~~Still open~~ done | clone charged verified (see Results) |

## Phase 3d polish (2026-10-11, check these first)

| # | Step | Expect |
|---|---|---|
| d1 | **Look** | Three rounded panels like the Line Manager's sections (lighter card with a light border): (1) a stats row of four cells *Rate / Vehicles / Per vehicle / Running costs* (title above value, like the Line Manager's Capacity / Utilization / ... row), the supply line(s) and the target row; (2) the selected model's options table; (3) the comparison. Buttons below, outside the panels. Note if the panels show no rounded border (then the inline nine-patch did not take: tell us) |
| d2 | **No sorting** | No "^" caret above the first header and no empty band above the headers. Click each header (twice): the rows keep their order (a second click may flash once while the table is rebuilt) |
| d3 | **Same columns** | Vehicles, ≈ Rate, Buy now, Cost/yr, Cost per unit sit at the same x in both tables; column 2 = Change (top) / Model (bottom). "Vehicles" and "Cost per unit" headers not clipped, "suggested" not clipped |
| d4 | **Target row** | "Target per year", the box, `-`, `+` and "suggested" (or **Suggested: 101**) on one line: buttons as tall as the box, texts on the box's baseline |
| d5 | **Tooltips** | Header tooltips (≈ Rate, Buy now, Cost/yr, Cost per unit), the Cost/yr cells, "best", Running costs, Replace window: wrapped over 2-3 lines, none very long. Apply has no tooltip (the line above it says what it does) |
| d6 | **Rename** (3e: Buy now is now Price) | "Cost per unit" is now "Cost per unit"; "best" still on the cheapest row |
| d7 | **Texture errors** | `grep -c "Texture error" stdout.txt` before / after opening the window a few times: no increase from our window (they also appear in sessions without this mod, on LoadPool threads; the base CSS itself uses `fileName = ""`, builtin.css.lua:1093-1095) |
| d8 | Still open from 3c | Apply a clone once and paste the `[RateMatcher] clone charged: ...` line |

## What the UI should look like (phase 3c, after the second in-game test)

- **Toolbar:** unchanged (the `stat_load_speed` icon left of A+, tooltip "Match line rate").
- **Window** titled with the line name, about 680 px wide, opaque, movable. Top to bottom:
  - **Summary** (one line): "Rate 66/yr · 2 vehicles · 33 each · running $182,880/yr".
  - **Supply** (grey): "Logs in reach: up to 101/yr · measured 112".
  - **Target per year** `[ 101 ]` `[-]` `[+]` and a grey "suggested" (or **Suggested: 101**).
  - (20 px gap) **"Sydfart (current)"** heading (headline font), 6 px, then the **plan table**: the game's own table
    (like the management window's Lines tab): header `☐ | Vehicles | Change | ≈ Rate | Buy now | Cost/yr | Cost per unit |`,
    numbers right-aligned under right-aligned headers, a check box in the first column, the selected row checked and
    highlighted, "suggested" in the last column. Header tooltips explain Buy now / Cost/yr / Cost per unit; the Cost/yr
    cells have a tooltip "Running costs $X/yr + purchase prices spread over the lifespan $Y/yr".
  - (20 px gap) **"Compare models (estimate)"** heading (same font as the one above), 6 px, then the **comparison
    table**: `☐ | Model | Vehicles | ≈ Rate | Buy now | Cost/yr | Cost per unit |`, fleet model first, "best" on the row with
    the lowest Cost per unit (none when they tie).
  - (20 px gap) result message, the grey "what Apply does" line, then **Apply**, **Replace window**, **Close**.

## Checklist

Tick each, note what differs (a screenshot of the window helps most).

| # | Step | Expect |
|---|---|---|
| 1 | Open the Line Manager, select **WC Logs** (2 ships, Rate 66), click our button | Window "WC Logs", target **101** "suggested", plan rows "3 · +1 · 99" (checked, highlighted, "suggested") and "4 · +2 · 132". Log `open line ...`, `timing line ...`, `price model ...`: **paste the timing and price lines** |
| 2 | **Alignment** | Both tables: every header sits exactly over its column; numbers right-aligned and lined up from row to row (also "-1" / "=" / "+1"); the selected row's cells don't shift; both tables span the same width. Note any column whose text is cut off (also with a long model name) |
| 3 | **Select** | Click anywhere on the other plan row (e.g. on its Cost/yr): it becomes checked + highlighted, the Apply line changes. Click its check box: same. Click the checked box again: stays selected. Same in the comparison (selects that model; its rows replace the plan table). Clicking a header may sort the table: note what happens |
| 4 | **Buy now** for "3 · +1" | = the store price of one Sydfart. Open the vehicle store for the line's depot and compare (expected $548,640 = 6 × its $91,440 running cost). Then Apply it and compare with `clone charged: ... = X`: **X is what the game really charged**. If X differs from Buy now (e.g. ≈ $70,484, the old figure), paste both |
| 5 | **Cost/yr / Cost per unit** | Cost/yr = running (the summary's running + the new ship's) + purchase spread over the lifespan (36525 / 1460 = 25.0 years at default calendar speed: ≈ $21,931/yr per Sydfart; more with a slower calendar). The Cost/yr tooltip shows both parts. Cost per unit = Cost/yr ÷ that row's ≈ Rate (unrounded, so a hand check with the shown Rate can be off by ~0.5 %) |
| 6 | **Compare models**: the per rate figures | No longer all equal **if** the timing line has a share at stops > 0: models with a big capacity and slow loading (Sternwheeler: 120 at loadSpeed 10 vs Sydfart 80 at 20) get a lower ≈ Rate per ship and more ships, so a higher Cost per unit; "best" marks the cheapest. If the timing line says `at stops nil`, the estimate is the old capacity × speed one and Cost per unit stays equal (then no "best"): paste the timing line |
| 7 | **Estimate vs reality** (optional) | Switch to another model (Apply), wait ~1-3 s: compare the real Rate (summary) with the ≈ Rate the row promised |
| 8 | **Type a target** `33` (no Enter) | Rows change while typing, the box keeps focus; "1 · -1 · 33", Buy now negative |
| 9 | Apply buy / sell / model switch / Replace window / passenger line / train / mission / reopen / Line Revert / close Line Manager (3b #6-#15) | As in phase 3b: vehicle list follows, Rate updates within ~1-3 s, hints for trains / mission vehicles |
| 10 | **Spacing** | More room above "Compare models" and above the buttons, a little below each heading; both headings look the same |

After the run: `grep -E 'RateMatcher.*(failed|warn)|ERROR' .../stdout.txt` should be empty; any `[RateMatcher] <key>:
... (further failures not logged)` line is a caught error: paste it. Also paste every `timing`, `price` and `charged`
line.

## Unverified in game (watch for these)

- `builtin.DataTable` inside our window: its height with a few rows (default vertical scroll policy, as the base's
  small tables in entity windows), the inline `size` on its meta, fresh row keys per render, sorting by a header click
  (`disableSortKey = true` only drops the key binding?), the CheckBox in a cell, `react.onMouseEvent` Clicked on a cell,
  `react.setStyleClasses("right-aligned", "highlight")`.
- The 2 new rules (`#squarelineratematcher.window DataTable::HeaderItem !right-aligned` and
  `... !right-aligned TextView`, copies of the statistics window's).
- `transportVehicleSystem.getLineCargoInfo(line, cargo)`: sectionTimes vs driveSectionTimes (seconds? per section of
  one round trip?). The estimate depends on them.
- What makeVehicleBuyCmd charges for our clone config (`purchaseTime = now`): store price or part value.
- From 3b: TextInputField.onTyping focus, the vehicle list update, `makeVehicleReplaceCmd` switches, money checks.
  The 2026-10-11 06:49 switch (3 replaced + 3 bought of model 4192) logged `failed 0/6`: probably the all-or-nothing
  money check (note the message the window showed).

## Results

- 2026-10-10 (phase 3, first run): window worked, the purchase worked. Feedback: cluttered layout and
  misaligned option columns; bought vehicles missing from the Line Manager's vehicle list until the line was
  reopened; wanted other models as selectable plans with a cost comparison; target box only updated on focus loss.
  All four addressed in phase 3b (PLAN.md).
- 2026-10-10 (phase 3b): window, typing, clone, sell worked. Feedback: table columns misaligned (header vs rows, rows
  vs rows, selected vs not), spacing, Per rate $2,771 for every model, Buy $548,640 vs the old $70,484. Addressed in
  phase 3c (PLAN.md).
- 2026-10-11 (phase 3c): alignment good, Cost per unit (then "Per rate") differs per model, "best" works (Sydfart best);
  timing `2 sections, section 879.68, drive 773.60, at stops 0.1206, maxFrequency 0.00227`; price: cost.price 548640 =
  getPartPrice(clone part) 548640, getPartPrice(owned) = getDepreciatedValue = 70484, getRunningCost 91440 = metadata.
  Feedback: sort caret / header sorting, clipped "Vehicles", target row alignment, wrapped tooltips, Line Manager look,
  rename Per rate. Addressed in phase 3d.
- 2026-10-11 (phase 3d): feedback: a slider-like artifact top right, the Running costs stats cell overflowing,
  "suggested" / "best" not prominent enough, rename Buy now to Price. Addressed in phase 3e.
- 2026-10-11 (phase 3e): **clone charged verified**: `balance 2062832 -> 1514192 = 548640 for 1 vehicle(s); store price
  each 548640`, so Price = what the buy costs (docs/findings.md "Line Rate, cloning onto a line"). Loading / result
  messages good. Feedback: green tags too strong (and "suggested" cut off in the table), the stats row poking out of
  the first panel (the top-right artifact), disabled Apply illegible. Addressed in phase 3f.
