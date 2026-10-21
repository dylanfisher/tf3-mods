# Better Minimap: in-game test checklist (phase 2: window polish)

## P7. Industry filter (phase 7, revision 5)

Report every `[Minimap] filter` / `filter window` / `settings:` line, any Lua error or warning with `[Minimap]`, and
(with "Debug: performance log" On) the SQPERF sections `markers_render`, `marker_icons_render` (counts
`marker_icons_built` / `marker_icons_reused`: built must stay low while hovering), `preview_render` (count
`preview_reused`: toggles and filter changes should reuse; the map must still show and update after a rebuild), `hover_hit`, `shift_poll`, `click_filter`,
`filter_render`, counts `hover_changes`, `shift_changes`.
- [ ] **Hover mute**: Ind on, hold Shift, move over an industry icon: every icon of another type fades (map and network
      unchanged, no dark overlay); the hovered type's icons stay bright. Move to another type: the bright type follows. Shift over the empty map: nothing faded. No
      flicker of the terrain, network or camera box (only the icons change; `industry markers gen N: ... drawn` must
      **not** repeat while hovering, and no `preview ready` / `net: on` line).
- [ ] **Shift without moving the mouse**: rest the pointer on an icon, press Shift: the others fade at once; release
      Shift: all back to normal. Same when Shift is held first and the pointer comes to rest on the icon.
- [ ] **Shift+click on an icon**: only that type stays (`filter: shift+click on <file>.con -> <file>.con (1 of N
      types on the map shown)`); the camera does **not** jump. Shift+click the same icon again, or an empty spot:
      all icons back (`... -> all`). Shift+click an icon of another type while filtered: switches to that type.
- [ ] **Plain click** (no Shift) still jumps the camera, also on an icon and while a filter is active. With Ind off,
      Shift+click jumps like a plain click (no filter change).
- [ ] Does Shift+click on the minimap trigger anything else in the game (the base uses Shift as "precision mode")?
- [ ] **Filter** checkbox appears right after Ind only while Ind is on; it is ticked exactly while the filter window is
      open (closing the window with its X unticks it). Tooltip "Filter active: showing N of M ..." while filtered.
- [ ] **Viz** appears only while Net is on (switch Net off: Viz goes away, the row re-packs).
- [ ] **Filter window**: Ticking Filter opens a small window "Industry filter" next to the minimap (left of it, or right when the
      minimap is at the left edge: is the placement sensible? `filter window opened at anchor x,y`). Search field
      (try a type name and a cargo, e.g. "fuel"), checkbox rows with cargo icons (inputs > outputs) and counts, a
      scroll bar when more than 8 types match, "Show all". Unticking Filter closes it. X closes it and unticks Filter. Movable.
- [ ] **Sync**: ticking types in the window filters the map at once; Shift+click on the map updates the checkboxes
      while the window is open; "Show all" clears both.
- [ ] Switching Ind off closes the filter window (`filter window closed (Ind off)`); hiding the minimap (Map button, X,
      ESC) closes it too; opening the minimap again does **not** reopen it.
- [ ] **Persistence**: set a filter, wait 1 s (`settings: saved ... filter=<keys>`), save the game and load
      it: `settings: loaded ... filter=<keys>` and the same types shown. "Show all" saves `filter=all`.
- [ ] **Narrow picture control row**: on a portrait map or with the minimap at S on a 1:2+ map, the row must not clip:
      rows are packed greedily by estimated widths (`CONTROL_W`: 47 px per 3-letter checkbox, Filter 68, spacing 6,
      padding 8): all four on one row from ~235 px, "Ind Filter Net" / "Viz" below that, "Ind Filter" / "Net Viz"
      below ~182 px. Report any clipped label or a row much wider than its controls (then adjust CONTROL_W).
- [ ] Faded look readable? (alpha 0.25 tint, tile 0.2, `minimap-industry-muted`): too faint or too strong? No icon
      flashes when the hovered type changes (the setVisible layer swap flashed: reverted).
- [ ] Hover, release Shift, set a filter, hover again: the faded layer follows the filter (no faded icons of
      filtered-out types).
- [ ] No errors or `[Minimap] ... failed` warnings in stdout.txt during all of the above.

## P6b. Header size button (2026-10-10): done

Title hidden, own magnifier (24 UI px) readable in the header. Right-aligning it next to the pin failed twice (CSS
stretch, explicit root width); per the user it stays at the left end of the header. Recheck only that the X still
shows when unpinned.

## P6. Network layer (phase 6, revision 5)

Report every `[Minimap] net` line and any `[SQPERF]` lines (set "Debug: performance log" On for this round).
**Round 1 result (2026-10-09):** colours RGBA and transparency OK; squares at the bottom-left and the network mirrored
top-to-bottom against the town markers -> `NET_FLIP_ROWS = true`, `NET_CALIBRATE = false` (docs/findings.md "ImageView
raw pixel data"). Round 2: skip Calibration, start at "Drawing and alignment" (town grids must sit on their town icons).
**Round 2 result (2026-10-09, 4.4k edges / 4k buildings):** street-system fallback in use (BASE_EDGE can't be listed;
the attempt is now skipped). First build: list ~4 ms, read 21-31 ms, raster 7-10 ms, encode 7-13 ms, sliced over 20-29
frames (0.2-0.5 s wall). Updates (+1 edge, +/-1-2 buildings) show within one 5 s scan, encode ~8-10 ms over ~8 frames.
Off/on releases and rebuilds cleanly. Rare SQPERF slow lines (1 per 15-240 calls, 19-38 ms) for net_list/net_encode,
like rev_read's: likely GC pauses, not steady cost. `net_render` (table hand-off) never logged as slow.
Still open: alignment after the row flip, frame rate on a big map with the perf log On.

**Round 3 (2026-10-09): magnifier, Hi-vis, toggle stutter.** Perf log On. Report every `[Minimap] net` / `option:`
line and the SQPERF sections `net_grid`, `net_handoff`, `net_encode`, `net_render`, counts `net_on_cold`,
`net_on_cached`, `net_recolor`.
- [ ] Size button shows a **magnifier icon** (light, ~14 px, no "S"/"L" text), tooltip "Toggle the map size: small /
      large", click still switches S <-> L (`option: size=...`). A pink/empty square or a missing icon = the base
      texture `::/gui/line_vehicle_mgmt/icons/inspector.tga` didn't load: report it.
- [ ] First Net on: one `net: image hand-off: params userdata, checked (...)` line (or `... Lua table ... (reason)`:
      paste it; the layer still works then, as before). Any engine `ImageView ... invalid pixel size` line or a
      placeholder image instead of roads: report at once.
- [ ] **Hi-vis** checkbox next to Net, greyed out while Net is off. Tick it with Net on: `option: hivis=true`,
      `net: palette hi-vis (encode; ...)`, then `net: palette hi-vis drawn: encode X ms, hand-off Y ms over N frames`
      within a fraction of a second. **No** `first build` / `update` line, no list/read. Colours: streets yellow,
      tracks magenta, town buildings orange, all opaque; tunnels dashed. Do they stand out on grass, desert, water?
      Untick: back to the normal colours the same way.
- [ ] Hi-vis is remembered across a load (`settings: loaded ... hivis=true`); with Net off ticking it does nothing.
- [ ] **Toggle off/on within 60 s**: off logs `net: off (toggled off): image vN + E edges, B buildings kept for 60 s`;
      on logs `net: on (cached image vN, X s old, off for Y s) ... incremental rescan in 0.5 s, no first build`. The
      network is there **at once**, no visible stutter, **no** `net: first build` (an `update` line only if
      something changed meanwhile). Flick it several times quickly: still smooth?
- [ ] Tick Hi-vis while Net is off (within 60 s), then Net on: cached image appears, then switches colour after the
      rescan (one `update` line, no first build).
- [ ] **Off for more than 60 s**: `net: released (off for 60 s): ...` about a minute after switching off (nothing else
      logged while off). Net on again: `net: on (cold): ...` + a new first build (the old stutter, if any, is
      expected only here).
- [ ] Off costs nothing: with Net off, no `net_*` sections in the SQPERF summaries except `guard` as before; frame rate
      the same as before revision 5.
- [ ] S/L with Net on: picture back at the new size at once, no `first build`/`update`, `net_render` max small
      (it no longer copies the 0.5-1 M entry table when the hand-off is `params userdata`).

**P6 perf run (2026-10-09 network layer perf changes + 2026-10-10 strips; PERF_REVIEW.md "Network layer (2026-10-09)"
and "Strips (2026-10-10)")**
Run 1 (2026-10-10) lasted ~25 s, so no SQPERF summary was printed: they come **every 30 s**. Run **at least 3 minutes**.
- [ ] Quit to the main menu, `make link`. Enable **Better Minimap** and the DEV mod **DEV SQPERF: all mods**.
- [ ] Load "New Game - desert". Open the minimap with **Net** on and leave it open **at least 3 minutes** (watch for
      several `[SQPERF]` summary lines). Pan the camera around (also across the map), and toggle **Net**, **Hi-vis**
      and **S/L** a few times each (and **Ind** once or twice). Let the game run at speed so towns grow.
- [ ] First Net on: `net: on (cold): image 512x512 px in 8 strips ...`, `net: image hand-off: params userdata, checked
      (one Lua -> C++ copy per changed strip of 64 rows: X ms for strip 1 ...)`: X should be ~1 ms (was 8.2 for the
      whole image). `net: first build took ... hand-off Y ms (params, 8 strips) ...`.
- [ ] `net: update N: ... buildings +1 ... (K bands), hand-off Z ms (S strips)`: S is 1 (or 2 when an item crosses a
      strip edge) and Z ~1 ms per strip. After a Net off/on within 60 s, an update re-encodes only its strip(s):
      `(8 bands)` per changed strip, not 64.
- [ ] Hi-vis switch: `net: palette ... drawn: ... hand-off ... (8 strips) over N frames`; the colours switch all at
      once (never half the map in the old palette for more than a blink).
- [ ] **Seams:** look closely at the picture at both S and L: no gap, no 1 px line, no offset where strips meet (at
      1/8, 2/8, ... of the picture height for a square map). Roads crossing a seam stay continuous.
- [ ] The picture must stay visible through Ind/Hi-vis/S-L toggles and new roads/buildings must still appear.
- [ ] Clicks/drags on the map still work where the network is drawn (the strips are mouse-transparent).
- [ ] Quit to the main menu, then `make perf ARGS='--last --mod square_better_minimap'`. Paste the report and fill the
      "Run 2" table in PERF_REVIEW.md (`net_handoff` per strip, `net_strips_handed`, `net_publish`, `net_render`,
      `net_render_strip`, `net_render_img`, `net_render_reused`, `net_render_built`, `net_list_*`, `net_flatten`,
      `net_encode`, `net_bands`, `net_scan_empty`, and any `slow=` lines). Goal: no step section max over ~4 ms,
      `net_render` max under 2 ms.

**Calibration (first)**
- [ ] Open the minimap, tick **Net** (log: `option: net=true`, then `net: on: image WxH px (RGBA), ...`). Within a few
      seconds: `net: edges listed with getEntitiesWithComponent(BASE_EDGE)` **or** `net: BASE_EDGE can't be listed (...);
      using the street system's node maps`, then two `net: first build ...` lines. Paste all of them.
- [ ] Top-left corner of the map: four small squares. Report their colours left to right and which corner they are in.
      Expected: **red, green, blue, half-transparent white, top-left**. Red/blue swapped -> NET_ORDER "BGRA"; at the
      bottom-left -> NET_FLIP_ROWS; anything else (all black, grey, garbage) -> report with a screenshot.
- [ ] Off the roads the map shows through (transparent background)? If the whole picture turns black or a colour,
      alpha isn't honoured: report it.
- [ ] Any `ImageView Cannot use image data with invalid pixel size` line in the log (engine, not `[Minimap]`), or
      a placeholder/pink image instead of roads: report it.

**Drawing and alignment**
- [ ] Streets light (near white), tracks dark, town buildings muted grey-brown under the roads; tunnels dashed.
- [ ] Roads line up with the terrain picture and the industry icons (an industry's access road ends at its icon).
      Jump the camera onto a junction or station and compare with the camera dot. Any offset or mirroring?
- [ ] Industry icons and the camera box are drawn **above** the network.

**Updates**
- [ ] Build a road (or track) somewhere visible: within ~5-10 s a `net: update 1: edges +N -0 ...` line and the
      road appears. Bulldoze it: `edges +0 -N` and it disappears without leaving pixels (a crossing road stays drawn).
- [ ] Let a town grow at high speed: occasional `buildings +a -b` updates; the frame rate stays smooth.
- [ ] With nothing happening: no `net: update` lines (passes without changes are silent).

**Performance**
- [ ] Big map (many towns, long networks): open with Net on. Any hitch? Report the `first build` timing line (list,
      diff, read, raster, encode, frames, wall) and the SQPERF `net_list`, `net_read`, `net_raster`, `net_encode`,
      `net_render` sections (`make perf`).
- [ ] Frame rate with Net on vs off (window open, game running at top speed).
- [ ] Toggle **S/L** with Net on: the network re-appears at the new size at once, **no** new `net: first build` or
      `net: update` line (S/L never re-rasterises; only `net_render` runs again).

**Off = no cost**
- [ ] Untick Net: `option: net=false` and `net: released (toggled off): ...`. Afterwards **no** `net:` lines and no
      `net_*` sections in the next SQPERF summaries.
- [ ] Net on, close the window with Map: no `net` work while hidden; after 60 s `net: released (window hidden for 60
      s)`. Re-open: `net: on` + a new first build.
- [ ] Reload the save with Net on: it is remembered (`settings: loaded ... net=true`) and builds again when the window opens.

**Save safety**
- [ ] Save, quit to menu, reload: no `[Minimap]` errors. Remove the mod and load that save: loads fine. Add the mod
      to an old save: works (Net off until ticked).

## P3. Industry icons (phase 3)

Run after section 0 passes (or together with it). Report every `[Minimap]` line.

- [ ] On open, besides `map gen N (...)`, one line `industries gen N: M markers, icons A from product + B from input, C fallback; D without position, E failed; read in X ms` and one `industry markers gen N: K drawn (WxH px picture, S px icons)`. Paste both; M should equal the industry count of the save, D and E should be 0, and K = M.
- [ ] The preview's generic gold factory markers are **gone**; town markers are still there.
- [ ] Each industry shows a small cargo icon on a dark tile (coal mine = coal, farm = its crop, refinery = its first product, ...), sitting **exactly where the industry is** (pan the camera onto two or three industries and compare with the red dot / click-to-jump). Report any offset (all shifted the same way? only large icons? only near the edges?).
- [ ] Toggle S/L: icons are 12 / 18 px and stay on their industries (`industry markers gen N` logged again per size).
- [ ] Hover an icon: tooltip with the industry name? (Uncertain: it may not show because the marker containers are mouse-transparent; report.) Click on an icon still jumps the camera there.
- [ ] Moving the camera does **not** log new `industry markers` lines (markers only change with a rebuild). Found or bulldoze an industry: a `changed: industries` rebuild, and the icon appears/disappears.
- [ ] Any `industry cargo failed`, `industry read failed`, `cargo icon failed` or `marker layout failed` warning: paste it. Any icon drawn as an empty/pink square: say which industry.
- [ ] Frame rate with the window open on a big map (many industries) vs closed.

## 0. Fix round (2026-10-07): ESC when pinned, position, fit, camera box

Run this first; the full phase 2 list below still applies. Report every `[Minimap]` line.

**Camera box (footprint now a ray/plane projection, not traceToTerrain)**
- [ ] On open: one `first camera footprint: ... eye (...), centre (...), plane z ..., rect x a..b y c..d` line plus four `corner N ... -> ground (...) hit|capped` lines. Paste them all.
- [ ] Pan far left/right/up/down and click-jump to the corners of the map: the orange box moves **with** the red dot every time, and the dot stays inside the box.
- [ ] Zoom out: the box grows; tilt to the horizon: the far corners are `capped` (box at most ~4x the camera distance from the dot) instead of covering the whole map.

**ESC**
- [ ] Unpinned: ESC (window focused or not) closes it; log `window hidden (closed)`. One click on **Map** shows it again (`window shown again`).
- [ ] Pin it: the **X disappears** (pinned = not closable; close with the Map button or unpin first). ESC with and without focus: the window stays and the pause menu opens. Report if a `close request while pinned ignored` or `pinned window was hidden by something else (ESC?); shown again` line appears (that means the fallback did the work; does the window flicker?).
- [ ] Unpin: the X is back and ESC closes it again.

**Position**
- [ ] Drag the window somewhere (log: `position: saved raw (...)-(...) screen WxH -> anchor x,y`). Close with X or Map, reopen with Map: it is **exactly where you left it** (same size and pin state). Report the `position:` lines; `position: ignored` lines mean the raw values looked invalid.
- [ ] First open after loading a save: right side below the top bar (`position: none saved, CSS default`).

**Fit (portrait 1:2 save)**
- [ ] Toggle S/L: `option: size=S (180x360 px)`, `L (360x720)`. No empty band right of (or below) the picture at any size.
- [ ] Portrait strip (1:3 or narrower) at S: `size=S (121x360 px)`, the picture fills the window edge to edge, the controls sit on two rows ("Ind Net" / "Viz"), nothing clipped, and `fit:` reports no `EMPTY BAND` (if it does, report N: FLOOR_W gets raised). 1:2 at S keeps one row. Hover Viz: "High visibility: ...". 
- [ ] Mod setting **Top bar button** = Icon: the top-left button is a folded-map icon on a dark tile, same size as the data layers button; `setting: hudButtonStyle=icon (raw 2)`. Text (default): the "Map" text button as before.
- [ ] A `fit: picture ... extra width ... (~N UI px)` line appears per size; report N. If it says `EMPTY BAND`, report the size and N (MIN_WIDTHS in the script gets raised).
- [ ] Landscape/square save if you have one: S/L are 200/560 on the long side, no bands.

Phase 1 (spike) is done; its results are in PLAN.md. This round checks the polished window. This file is not shipped (it lives in `plans/`). Use a **copy** of a save and report every `[Minimap]` log line plus any Lua error near one.

## 1. Setup and log tail

1. The mod is already linked; tick **Minimap** in the mod list. It is GUI-only: no game script, no commands, nothing saved.
2. Keep the log open in a terminal:
   ```sh
   tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -i "Minimap\|square_better_minimap\|error"
   ```

## 2. Window and size

- [ ] Click **Map**: the "Map" window opens at the top right. The picture fills the window (no empty border, no status text line); under it one thin row: **Assets**, **Refresh**, and a size button showing **S** (the default size).
- [ ] Hover **Refresh**: the tooltip shows "N towns, M industries, built in X ms".
- [ ] Click the size button: **S → L → S**. The picture is 200 / 560 px on its long side (portrait maps: widened, see section 0), keeps the map's aspect (this save: 1:2 portrait), and the window shrinks/grows with it. Log: `option: size=...`. The camera box follows the new size within a moment.
- [ ] Expected lines on open: `map gen N (open, assets=false): ...` and `preview ready gen N (WxH px): ...`.

## 3. Camera box (the phase 1 bug)

- [ ] The orange box and red dot are visible right after opening; **no** `readCamView failed` / `API is currently restricted` warning in the log. One line `first camera footprint: viewport WxH, n/4 corners hit terrain` appears.
- [ ] Box and dot sit where the camera is: pan to a recognisable coast/corner and compare.
- [ ] Pan east/west/north/south: the box moves the same way on the picture (east = right, north = up). **If it moves mirrored**, report which axis: left/right mirrored = "flipX", up/down mirrored = "flipY off", moving sideways when you pan north = "swapXY".
- [ ] Zoom in/out: the box shrinks/grows. Rotate the camera: the box changes shape (it is the axis-aligned bounds of the view, so it widens at 45°). Tilt to the horizon: the box falls back to a square around the dot.
- [ ] The box updates smoothly (~10 per second) and the frame rate does not drop noticeably with the window open.

- [ ] View direction arrow: a small yellow block arrow (with a shaft) at the box centre points where the camera looks.
      Rotate the camera a full turn: the arrow follows and points to the box's far (wide) side.
      Look straight down: it points to the screen's top. If it turns the wrong way (e.g. points
      right when looking left), flip `ARROW_ROT_SIGN`. Also report if it is white (tint not applied)
      or off-centre while turning.
- [ ] Setting: in the mod selection (load a save -> mods), Better Minimap shows "View direction
      arrow" On/Off, default On. Set Off and load: no arrow, box still moves; log line
      `setting: showArrow=false (raw 2)`. Set On again: arrow is back (`raw 1`).
- [ ] Portrait map (1:5): picture stays fully on screen at S/L, controls row visible.

## 4. Click-to-jump

- [ ] Click a spot on the picture: the camera jumps there, keeping zoom/angle/tilt. No `click` log lines any more (only a `click failed` warning if something breaks).

## 5. Pin and position

The title bar now has a pin toggle. Pinned = the window stays until you close it; unpinned = ESC closes it when the window has focus (like an unpinned vehicle/station window). Moving the window pins it automatically (same as base game windows). Log: `option: pinned=true|false`.

- [ ] Unpinned: click inside the window, press **ESC**: the window closes. The **Map** button then opens it again on the first click.
- [ ] Pin it. Press **ESC** (with and without the window focused): the window stays; the pause menu still opens when nothing else handles ESC.
- [ ] Pinned: open other windows (a station, a vehicle, the line manager), switch tools (build roads, bulldoze, terraform), click empty terrain: the minimap stays open.
- [ ] Drag the window to another spot: the pin turns on by itself.
- [ ] Close it with **X** (or the **Map** button), reopen: it comes back **pinned** and at **the same place**, with the same size and Assets setting. Report if it comes back at the top right instead (position restore did not work) or if the pin is off.
- [ ] Unpinned window: does anything else close it (other windows, tool switches)? It should not; report if it does.

## 5b. Remembered settings (revision 3)

Stored in the savegame's GUI save data (`api.gui.game.getGuiSaveData("square_better_minimap")`), per savegame (earlier revisions used the game settings, which mod.io's upload check rejects). Log: `settings: loaded ...` once per load, `settings: saved ...` about 1 s after a change.

- [ ] Position (fixed after the first test: the Window's own getPosition returned 0,0-0,0, so `pos (none)` was saved). On open: `position: none saved, default anchor 1.0000,0.1200` (or `restore anchor ...`), then within ~0.5 s `position: frame offset dx,dy (requested anchor ...)`. Drag it: `position: saved content (...) -> anchor x,y`. Report the offset line and any `position: ignored` / `moved before the frame offset` lines.
- [ ] Default spot (no remembered position) is still the top right below the top bar, like before (CSS gravity was replaced by initialX/Y).
- [ ] Open the minimap, pin it, drag it somewhere, set size M, untick Ind. Within ~1 s: one `settings: saved pos ..., pinned=true, size=2, industries=false, open=true` (one line per drag, not per frame).
- [ ] Save, then load that save (or another): `settings: loaded ...` with the same values, `settings: re-opening the pinned minimap`, and the window is back at the same place, pinned, size M, industries off.
- [ ] Change the settings, save the game, quit the game completely and start it again, load that save: same as above (checks that the GUI save data goes into the savegame).
- [ ] Load a different savegame (or start a new game): it has its own settings (defaults if it never stored any).
- [ ] Close the pinned minimap with the Map button, load again: it stays closed, but opens at the remembered place with the Map button.
- [ ] Unpinned + open, then load: it does **not** re-open by itself (only pinned windows do).
- [ ] Any `[Minimap] load settings failed` / `save settings failed` warning? (Would mean the settings API isn't usable from in-game GUI scripts.)
- [ ] With Photo Mode active too (its bookmarks also use the GUI save data), add a bookmark, save, load: both the minimap settings and the bookmark survive (each mod has its own key).

## 6. Rebuilds (no timer, change-driven)

- [ ] With nothing happening, no new `map gen` lines appear (checked every 2 s; a growing town can legitimately trigger one now and then).
- [ ] Tick **Assets**: immediately `option: assets=true` and `map gen N (assets on, assets=true): ... built in X ms`, and the picture changes (trees). Untick: rebuilds again without assets. **Report both build times.**
- [ ] **Refresh** forces `map gen N (manual, ...)`.
- [ ] Terraform a patch: within ~2 s `map gen N (changed: terrain, ...)` and the picture updates.
- [ ] Found a new industry (or remove one with the bulldozer): within ~2 s a `changed: industries` rebuild and the icon appears/disappears.
- [ ] Does any rebuild cause a visible hitch? Report how long.

## 7. Save safety

- [ ] Save, quit to menu, reload: no `[Minimap]` errors; the button is back.
- [ ] Remove the mod and load that save: it loads (mod.json `severityRemove: Warning` only warns).
- [ ] Add the mod to an older save that never had it: works as in step 2.

## What to report back

1. Camera box: visible? aligned? mirrored (which flag)? arrow direction right? any `failed` warnings?
2. Pin: ESC / other windows / tools with pin on and off; does reopen restore pinned + position?
3. Size toggle and fit (any empty space or clipping, at S/L).
4. Assets toggle and game-change rebuilds: did they fire, build times, hitches.
5. Every `[Minimap] ... failed:` warning or Lua error.

## Map editor (rev 7)

- [ ] The Map button shows in the editor's top-left bar; the window opens.
- [ ] Generate Heightmap → Generate: within ~2 s after "Map is ready", `map gen N (changed: heights...)` and the new terrain.
- [ ] Resize the map: `changed: bounds...`; picture, camera box and click-to-jump match the new size.
- [ ] Generate towns / place an industry: `changed: towns` / `changed: industries`.
