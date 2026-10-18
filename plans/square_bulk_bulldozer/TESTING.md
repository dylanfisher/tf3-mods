# Bulk Bulldozer: in-game test checklist

One ordered checklist for the whole mod (from PLAN.md "In-game test checklist"). Not shipped. Work top to bottom; later sections assume the earlier ones passed. Use a **copy** of a save.

Status: rev 4 released. Every check below is still unticked (see PLAN.md "Open work"); the dated notes about
the 2026-10-07 builds moved to `HISTORY.md`. Since rev 3 the `mouse ...` log lines appear only with the mod
setting "Debug: performance log" On.

Report back every `[BulkBulldozer]` log line (or a representative excerpt), plus the answers marked **Q**.

## 0. Setup and log tail

1. `make link` (already done for Phase 1), then tick **Bulk Bulldozer** in the mod list and load a save copy.
2. Keep the log open:
   ```sh
   tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -i "BulkBulldozer\|square_bulk_bulldozer\|error"
   ```

Log lines the Phase 1 build writes:

| Line | When |
|---|---|
| `[BulkBulldozer] tool activated; getCurrentParams {bulk_bulldozer_bulldoze=1, bulk_bulldozer_radius=20, …}` | the tool becomes active (after selecting the entry) |
| `[BulkBulldozer] highlight mode both (engine tint … + red lines …); hover effect only on highlighted objects` | right after `tool activated`: which highlight path is active (`bb_highlight.MODE`) |
| `[BulkBulldozer] highlight: 20 entities, overlay 64 line pieces + 2 construction circles (last render)` | LMB released with a selection |
| `[BulkBulldozer] highlight overlay capped at 1600 pieces (…)` | a selection too big for the overlay budget (once per selection) |
| `[BulkBulldozer] highlight overlay failed: …` | should never appear; report it |
| `[BulkBulldozer] tool deactivated` | another entry, menu closed, ESC |
| `[BulkBulldozer] radius event: 50 -> r = 50 (getCurrentParams {...})` | radius slider moved |
| `[BulkBulldozer] bulldoze button: 52 selected` / `bulldoze button: nothing selected` | **Bulldoze** clicked |
| `[BulkBulldozer] selection cleared (clear button): N selected, nothing removed` / `clear button: nothing selected` | **Clear** clicked |
| `[BulkBulldozer] mouse Pressed button=0 handled=false -> return true (phase painting)` | every press/release/wheel/click event the Selector receives |
| `[BulkBulldozer] mouse Moved x37 (with LMB held: 20, handled: 0)` | summary of Moved events, at most every 0.5 s |
| `[BulkBulldozer] filters {roads, tracks, assets}` | on activation: the filters read back from `getCurrentParams` (it returned `{}` in the first test, so these are the recipe's defaults or the last toggles) |
| `[BulkBulldozer] filter event: roads = false -> {...}` | a filter CheckBox toggled |
| `[BulkBulldozer] right click (Clicked): moved 3 px -> clear` | RMB released with a selection: cleared (then `selection cleared (right click)`) |
| `[BulkBulldozer] right click (Clicked): moved 120 px > 16 (camera drag), selection kept` | RMB drag: kept. If a plain click lands here, report the px value |
| `[BulkBulldozer] right click (Clicked): nothing selected` | RMB released with nothing selected |
| `[BulkBulldozer] selection cleared (tool closed / tool switched): N selected, nothing removed` | the selection dropped because the tool was left; the reason names the detector |
| `[BulkBulldozer] filters (toolbar shown / toggle / activated) {roads, tracks, assets}` | the filters the tool uses changed to match the toolbar |
| `[BulkBulldozer] filters (…) {…} -- unknown, treated as off: stations` | a filter whose shown value isn't known: OFF to be safe (report it) |
| `[BulkBulldozer] world layer unmounted` / `world layer mounted again` | another tool took the world while ours stayed selected |
| `[BulkBulldozer] tool closed while bulldozing (…)` | the tool was left during a commit (the commands already sent still run) |
| `[BulkBulldozer] stroke (waiting for Bulldoze): 12 selected, cost $3,000, 9 samples, worst 0.8 ms — Selected: … / Skipped: …` | LMB released (samples and worst time count the whole selection, all strokes) |
| `[BulkBulldozer] stroke (nothing selected): 0 selected, …` | LMB released with nothing selected |
| `[BulkBulldozer] slow sample: 6.2 ms (r = 200 m, 812 edges, 95 constructions in query)` | a sample over 4 ms, at most once a second |
| `[BulkBulldozer] sample failed: …` | a Lua error inside a sample (should never appear; report it) |
| `[BulkBulldozer] commit: 52 selected, … cost …` | the selection goes to bb_commit (after the button) |
| `[BulkBulldozer] commit: 40 edges, 12 constructions, mode two-step, preflight cost $12,000 (raw 12000), balance 5000000, critical false, errors [], preflight 3.1 ms` | preflight; **raw** is the engine's `costs` value (sign matters) |
| `[BulkBulldozer] cmd 1 (constructions): 0 edges, 12 constructions, 0 nodes, 0 objects -> ok` | every command, with the game's messages on failure |
| `[BulkBulldozer] cmd 2 (edges): 40 edges, 0 constructions -> FAILED: <message>` | a failed batch; halves follow |
| `[BulkBulldozer] hard-rule recheck (before send) dropped 1` | an entity changed between selection and sending (expected rarely) |
| `[BulkBulldozer] commit done: removed 51 of 52, skipped 1 (<reason>: 1), 4 commands, 35 ms` | summary of every commit |
| `[BulkBulldozer] selection cleared (right click / Esc / back / tool closed): N selected, nothing removed` | the selection dropped |
| `[BulkBulldozer] slow preview: 25.0 ms for 300 objects` | a makeProposalData preview over 20 ms |
| `[BulkBulldozer] commit: no final callback after 20 s, giving up waiting` | should never appear; report it |

## 1. Mounting (P1)

- [ ] Road → Tools and Rail → Tools show "Bulk Bulldozer" at the head of the list with its (placeholder) icon: dashed orange circle over a road.
- [ ] Selecting it shows the toolbar, top to bottom: **Radius** slider (5 m … 200 m, default 20 m), a separator line, **[Bulldoze] [Clear]** side by side in one row, a grey **status chip** reading `Nothing selected` / `Paint with the left mouse button`, a separator, then the six filter CheckBoxes (Roads first).
  - **Q:** are both button labels fully visible (not clipped), and roughly centred?
  - **Q:** is the status chip readable (dark text on light grey)? Does any line get cut at the right edge? (Lines are clipped to 36 characters with `...`; say if that is too short or too long.)
  - **Q:** does the chip update live while you hover and paint (see §3)? If it stays at `Nothing selected` while the selection grows, report it (the chip recipe may not be getting updates).
  - **Q (Roads):** there are now **six** filters, the first is **Roads**, ticked on first open (no "Your roads" / "Town roads" any more).
  - [ ] **Toolbar = filters (safety).** Untick Roads, then: switch to another entry and back; close and reopen the menu; open the tool in Rail → Tools (Roads ticked there) and back to Road → Tools. Each time, hover a road: it must be highlighted **only if the Roads box is ticked** in the toolbar you see (tooltip `Skipped: 1 filtered` otherwise). Copy the `filters (…)` lines. A ticked box that selects nothing is a safe miss (report it); an unticked box that selects is a bug (report at once).
- [ ] Log shows `tool activated; getCurrentParams {...}`. **Q:** copy the line. Is `bulk_bulldozer_radius` **20** (metres) or **4** (an index)? Move the slider to 50 m, close and reopen the tool: what does the line say then, and does the ring keep 50 m?
- [ ] Switching to another entry or closing the menu removes the ring (log: `tool deactivated`).
- [ ] ESC closes the construction menu.
- [ ] No Lua error in the log.

## 2. Brush + mouse (P1)

- [ ] The ring (white) follows the cursor and hugs hills and valleys. **Q:** is it visible through hills / under bridges, and does it look too thin or too thick at 5 m and at 200 m?
- [ ] The ring resizes 5 → 200 m with the slider, without lag.
- [ ] The tooltip near the cursor starts with `r = 20 m`; while hovering, its line `octree at r: N edges · M constructions` gives the raw octree counts for exactly the brush radius and changes as you move. **Q:** does the `·` render (not `?`)?
- [ ] Click LMB: the ring turns red while the button is held, amber after release if something was selected (the selection stays shown; right-click returns to white). Log shows `mouse Pressed button=0 …` and `mouse Released button=0 …`. **Q:** copy both lines (the `handled=` values matter).
- [ ] **Q:** Hold LMB and drag over open terrain. Does the **camera move** (pan or rotate)? The build returns `true` on LMB Pressed, so this tests whether that stops it.
- [ ] **Q:** During that drag, does the log show `mouse Moved xN (with LMB held: K, …)` with K > 0? (K = 0 means Moved does not arrive while LMB is held.)
- [ ] **Q:** Release LMB after the drag: does `mouse Released button=0` still arrive, and does the ring turn amber?
- [ ] **Q:** Scroll the wheel and click RMB/MMB once each: copy the `mouse Wheel …` / `button=2` / `button=1` lines (or note that none appear). Does zoom still work?
- [ ] **Q (octree hit semantics):** set a 5 m brush and read the `octree at r:` line (raw octree, not the selection).
  - Hover the middle of a long straight track or road edge (well away from its ends and its centre point). Does `edges` count it (≥ 1)?
  - Hover a big station away from its centre. Does `constructions` count it?
  - Hover open terrain right next to a long edge (inside its bounding box, not on it). Is it counted?
- [ ] (A click or release only **selects**; nothing is removed until **Bulldoze** is pressed. Clear or right-click clears.)

## 3. Selection (P2)

What the build does: the toolbar has six filter CheckBoxes after the status chip (**Roads** ✔ (every street that is yours or unowned), **Tracks** ✔, **Stations & depots** ✘, **Other assets** ✔, **Town buildings** ✘, **Underground** ✘). While you hover with nothing selected, the objects the brush would take are highlighted, the chip reads `Nothing selected` / `Brush: 3 roads · 1 track` and the tooltip `r = 20 m` / `Skipped: 4 filtered, 1 industry`. Hold LMB and drag: the ring turns red, the selection grows and the chip counts it (`12 selected · $3,000` / `8 roads · 3 tracks · 1 asset`; more than three kinds end in `...`). Release: the ring turns amber, the selection stays highlighted, the chip keeps the count and the tooltip says `Right-click clears the selection`. Another stroke adds to it. Nothing is removed until the button is pressed.

Rules to check against: edges are hit when their centre line comes within the circle; constructions only when their **origin** (centre point) is inside it. Never selected: industries and the roads that go with them, the HQ, anything of another player, unowned constructions that aren't plain town buildings (landmarks, mission props), edges and nodes that belong to a station or other construction.

In a town, a station area and an industry area, paint without pressing the button (right-click clears).

- [ ] Highlights follow the filters (toggle each one; the preview updates right away). Look and colours: §3a.
- [ ] **Q:** after closing and reopening the tool, the log line `filters {...}` matches the CheckBoxes shown (if it doesn't, copy the `getCurrentParams` line: CheckBox values may be 0-based there).
- [ ] Industry parts, its roads, the HQ and other players' or mission objects are never highlighted (tooltip lists them under `industry` / `HQ` / `other player` / `not yours`).
- [ ] With **Roads** on: your roads, town roads and the roads left over after removing a roundabout (or another street construction) are all highlighted. Roads of a station or industry, and other companies' roads, never (tooltip `part of a construction` / `industry` / `other player`). With Roads off: no street at all.
- [ ] Tunnels only with "Underground" (tooltip `underground` otherwise).
- [ ] Station access roads that belong to the station are not highlighted separately (`part of a construction`).
- [ ] Your stations and depots only with "Stations & depots" (hover the station's centre).
- [ ] A long straight track: a 5 m brush on its middle (away from both ends) highlights it. **Q:** if not, report the §2 octree answers; `EDGE_MARGIN` (100 m) needs raising.
- [ ] A big station: it is selected only when the circle covers its centre point. **Q:** is that acceptable, or should touching any part select it?
- [ ] Release, then paint a second stroke elsewhere: the first selection stays and the second **adds** to it (count grows, both areas highlighted). A plain click (no drag) adds what is under the circle.
- [ ] The 400 cap message (`Limit of 400 reached`) appears with a 200 m brush dragged across a city, or after several strokes that add up to 400.
- [ ] Right-click (a short click, no drag) clears the whole selection (waiting, or while painting). Log: `right click (Clicked): moved N px -> clear` then `selection cleared (right click)`. **Q:** copy the `right click` line. If nothing is logged on RMB, copy every `mouse … button=2` line.
- [ ] Hold RMB and drag (camera): the selection stays (`… camera drag, selection kept`). **Q:** does an RMB drag move the camera at all in a construction tool? Report the px values of a normal click and of a drag if they get confused.
- [ ] Changing a filter while a selection waits keeps the selection; the next stroke uses the new filters.
- [ ] **Q:** any `slow sample` lines with a 200 m brush in the densest city? Copy the worst one.
- [ ] Nothing is removed by hovering, by releasing a stroke, or by a selection cleared with a right-click.

## 3a. Selection highlight (fix 2026-10-07)

Constants in `content/bulk_bulldozer/bb_highlight.tl`: `MODE` (`"both"` default, `"engine"`, `"lines"`), `HOVER_ONLY_HIGHLIGHTED` (true), `MAX_SEGMENTS` (1600). The log line `highlight mode …` on activation names the active one.

- [ ] Hover with nothing selected over a few of your roads: they show a **light coral** tint/outline and thin coral lines along them (the preview). Nothing else under the cursor gets the old **white** hover outline. **Q:** is the coral preview visible, and clearly lighter than the red below?
- [ ] Paint a stroke over roads, tracks and an asset, release: every selected edge has a **red line** along it, every selected construction a **red circle** at its centre, and **Q:** do the objects themselves also get a red tint/outline from the engine? Report separately for roads, tracks, assets/stations, town buildings (with "Town buildings" on).
- [ ] With a selection waiting, move the brush over unselected objects: they get **no** highlight (only the ring shows where the brush is); selected ones stay red.
- [ ] **Q:** do the red lines follow bridges (deck height) and hills, and do they show through buildings/terrain (they ignore depth)? Too thick/thin?
- [ ] **Q:** with the filter-restricted hover, do LMB painting, RMB clear and clicks on objects still work as before (no entity window opens on a click)? If anything broke, set `HOVER_ONLY_HIGHLIGHTED = false` and retest.
- [ ] A big selection (200 m brush over a city, toward the 400 cap): still smooth while moving the cursor? Any `highlight overlay capped` line?
- [ ] After **Bulldoze** or **Clear**: all red lines, circles and tints are gone.
- [ ] **If the engine tint looks wrong or covers too much** (e.g. a whole station solid red): set `MODE = "lines"` (lines and circles only, engine effect transparent as before). **If the lines are redundant** because the engine tint is clear on every kind: `MODE = "engine"`. Report which looked best.
- [ ] **If the red lines disappear after the first move of the cursor** (cached overlay edges reused across renders), report it: the overlay then needs rebuilding on every render.

## 4. Commit (P3)

What the build does: on **Bulldoze** the selection is previewed again with `makeProposalData` (cost + errors), money-checked, re-checked against the hard rules on fresh reads, then sent with `ignoreErrors = false, playerInitiated = true, doDust = true`. A failing command is halved and retried down to single objects (at most 48 commands per stroke); what still fails is skipped and named. The status chip shows `N selected · cost` while painting and waiting, `Bulldozing N...` while it runs, then the result for 3 s (`Bulldozed 51 · 1 skipped` / `<reason>`, or `Nothing bulldozed` / `<why>`).

- [ ] **Q (button):** select a few own roads, press **Bulldoze**: removed in one go, with dust. Log: `bulldoze button: N selected`, one `cmd` line per kind and `commit done: removed N of N`. Then select again and press the button a **second** time: does it fire again (log line again)? If the second press does nothing, report it (PLAN Risks has the fallback).
- [ ] Press **Bulldoze** with nothing selected: chip `Nothing selected` / `Paint over objects first` for 3 s, log `bulldoze button: nothing selected`.
- [ ] Press **Clear** with a selection: highlight and amber ring gone, chip back to `Nothing selected`, log `selection cleared (clear button)`, nothing removed. Press it again: log `clear button: nothing selected`.
- [ ] **Q (cost sign):** copy the `commit: … preflight cost … (raw …)` line. Is raw positive or negative for a removal? Does the money drop by about that amount (finance window), and is it booked under bulldoze/construction in the journal?
- [ ] **Q (refund):** build a short road, bulldoze it with the brush within 60 s: is ~75 % refunded (as with the base bulldozer)?
- [ ] **Q (free bulldozer?):** if no money moves at all, say so (PLAN Risks: then we book the cost ourselves).
- [ ] Tracks with signals: removed together with their signals (no leftover signal, no error later). Keep the game running 5 min afterwards: **no** delayed crash.
- [ ] **Q (orphan nodes):** after removing the middle of a road and a dead-end stub, are loose nodes left (click the former junction / end spot with the base bulldozer)? Two-step mode lets the engine build the edge removal, so this answers whether it cleans nodes itself.
- [ ] A track with a train on it (or a road with a bus stopped on it) inside a larger stroke: that edge is skipped and named in the result line (`… skipped: <game message>`); the rest of the stroke is removed. Copy the `cmd … FAILED: …` lines and count the commands.
- [ ] A station (with "Stations & depots" on, then the button): it is removed together with its own access edges; its lines lose the stop. **Q:** was it highlighted at all before (Phase 2 flagged ownership; now read from the station group / depot when the construction has no owner)?
- [ ] **Combined proposal (flip the flag):** set `commit.COMBINED_PROPOSAL = true` in `bb_commit.tl`, reload, and repeat: small road selection, track with signals, road + an asset in one stroke, the dead-end stub. **Q:** does it work, and are orphan nodes gone? Any delayed crash? Then set it back unless it was clearly better.

## 5. Guards (P3)

- [ ] Every selection waits for the button, whatever its size or content (no threshold rule any more); the ring stays amber.
- [ ] RMB clears it (log `selection cleared (right click)`); nothing is removed. RMB with nothing selected leaves the tool open (log `right click (Clicked): nothing selected`). **Q:** does RMB with nothing selected do anything else (close the menu)?
- [ ] ESC while painting (LMB still held) or while a selection waits clears it (`selection cleared (Esc)` or `(back)`) and does **not** close the menu. ESC with nothing selected still closes the menu. **Q:** which log line appears, and did the menu stay open?
- [ ] **Closing clears (user feedback 2026-10-07).** With a selection waiting, try each and reopen the tool after it: it must start empty (no highlight, chip `Nothing selected`), and nothing is removed. Copy the `selection cleared (…)` line of each (the reason shows which detector caught it):
  - [ ] pick another entry in Road → Tools;
  - [ ] close the construction window (X or Esc twice);
  - [ ] switch to another menu tab or the base Bulldozer, build/remove something, come back;
  - [ ] switch from Road → Tools to Rail → Tools (the same tool in the other category).
  - [ ] leave the tool open with a selection, pause the game, and switch to another app for 10 s: the selection must still be there on return.
  - **Q:** if any of them still shows the old selection on return, say which, and copy the log lines from that moment.
- [ ] With money below the preview cost: `Nothing bulldozed: not enough money`, nothing removed. (Only works if the cost sign is positive; see §4.)
- [ ] While `Bulldozing...` shows, clicks and the button do nothing and no second commit starts (`bulldoze button: a commit is already running`).

## 6. Locks (P3)

In a campaign mission save with a non-bulldozable object:

- [ ] the object is refused, not removed (it shows up as skipped with the game's message);
- [ ] the result is recorded (decides the mission-disable fallback). Copy the `cmd … FAILED` line.

## 7. Perf (P4)

- [ ] A 200 m brush dragged over the densest city stays smooth.
- [ ] Log the worst sample time (target < 2 ms).

Moved from `PERF_REVIEW.md` (rev 2 changes, 2026-10-08):

### In-game check list (rev 2 perf review)

- [ ] Hover a 200 m brush across the densest city: `slow sample` lines (> 4 ms) are fewer / lower than before;
      no visible stutter every ~100 ms while moving.
- [ ] Paint a long stroke up to the 400 cap over a town with a 100-200 m brush: the red overlay grows
      smoothly, no hitch per sample; release → overlay turns to the selection colour once.
- [ ] Selection results unchanged: industry access roads still `Skipped: industry`, other players' objects
      `other player`, station roads `part of a construction`, your stations selected with Stations & depots on.
- [ ] Bulldoze: the commit log line counts and costs look as before.

## 8. Save safety (P4)

- [ ] Add the mod to an existing save: no warning; the tool works.
- [ ] Remove it: no warning; the save loads and nothing changed apart from what was bulldozed.
- [ ] Achievements: note whether they are disabled (expected with `cosmetic: false`).
