# Better Minimap: in-game test checklist (phase 2: window polish)

## P3. Industry icons (phase 3)

Run after section 0 passes (or together with it). Report every `[Minimap]` line.

- [ ] On open, besides `map gen N (...)`, one line `industries gen N: M markers, icons A from product + B from input, C fallback; D without position, E failed; read in X ms` and one `industry markers gen N: K drawn (WxH px picture, S px icons)`. Paste both; M should equal the industry count of the save, D and E should be 0, and K = M.
- [ ] The preview's generic gold factory markers are **gone**; town markers are still there.
- [ ] Each industry shows a small cargo icon on a dark tile (coal mine = coal, farm = its crop, refinery = its first product, ...), sitting **exactly where the industry is** (pan the camera onto two or three industries and compare with the red dot / click-to-jump). Report any offset (all shifted the same way? only large icons? only near the edges?).
- [ ] Toggle S/L: icons are 12 / 18 px and stay on their industries (`industry markers gen N` logged again per size).
- [ ] Hover an icon: tooltip with the industry name? (Uncertain: it may not show because the marker containers are mouse-transparent; report.) Click on an icon still jumps the camera there.
- [ ] Moving the camera does **not** log new `industry markers` lines (markers only change with a rebuild). Found or bulldoze an industry: a `game changed` rebuild, and the icon appears/disappears.
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

Stored in the game settings (`AppConfig.mainMenuState["square_better_minimap"]`), not the save. Log: `settings: loaded ...` once per load, `settings: saved ...` about 1 s after a change.

- [ ] Position (fixed after the first test: the Window's own getPosition returned 0,0-0,0, so `pos (none)` was saved). On open: `position: none saved, default anchor 1.0000,0.1200` (or `restore anchor ...`), then within ~0.5 s `position: frame offset dx,dy (requested anchor ...)`. Drag it: `position: saved content (...) -> anchor x,y`. Report the offset line and any `position: ignored` / `moved before the frame offset` lines.
- [ ] Default spot (no remembered position) is still the top right below the top bar, like before (CSS gravity was replaced by initialX/Y).
- [ ] Open the minimap, pin it, drag it somewhere, set size M, untick Ind. Within ~1 s: one `settings: saved pos ..., pinned=true, size=2, industries=false, open=true` (one line per drag, not per frame).
- [ ] Save, then load that save (or another): `settings: loaded ...` with the same values, `settings: re-opening the pinned minimap`, and the window is back at the same place, pinned, size M, industries off.
- [ ] Quit the game completely and start it again, load a save: same as above (checks that `saveAppConfig` really wrote it to disk).
- [ ] Close the pinned minimap with the Map button, load again: it stays closed, but opens at the remembered place with the Map button.
- [ ] Unpinned + open, then load: it does **not** re-open by itself (only pinned windows do).
- [ ] Any `[Minimap] load settings failed` / `save settings failed` warning? (Would mean the settings API isn't usable from in-game GUI scripts.)
- [ ] Change a game setting in Settings afterwards (e.g. volume) and confirm the minimap position still survives a reload (nothing overwrote the key).

## 6. Rebuilds (no timer, change-driven)

- [ ] With nothing happening, no new `map gen` lines appear (checked every 2 s; a growing town can legitimately trigger one now and then).
- [ ] Tick **Assets**: immediately `option: assets=true` and `map gen N (assets on, assets=true): ... built in X ms`, and the picture changes (trees). Untick: rebuilds again without assets. **Report both build times.**
- [ ] **Refresh** forces `map gen N (manual, ...)`.
- [ ] Terraform a patch: within ~2 s `map gen N (game changed, ...)` and the picture updates.
- [ ] Found a new industry (or remove one with the bulldozer): within ~2 s a `game changed` rebuild and the icon appears/disappears.
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
