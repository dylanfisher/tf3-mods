# Better Minimap (`square_better_minimap`): plan

An always-available minimap for TF3: terrain overview of the current save, a box showing the camera view, and click-to-jump. Built only on the game's own API (no code from other minimap mods).

**Status (2026-10-10):** revision 5 verified in game and committed: Phase 6 network layer (Net toggle; streets, tracks and town buildings as 8 raw-pixel ImageView strips; Hi-vis palette; cached across Net off/on for 60 s), magnifier size button in the window header (no title), SQPERF instrumentation, new camera arrow. Perf runs 2-4 in PERF_REVIEW.md: every network section within budget except the three single engine list calls (max 1-4.7 ms, once per 5-30 s scan). Not yet uploaded. Earlier phases: see the history below.

<details><summary>Previous status line</summary>

Status (2026-10-07):** phase 1 verified in game; phase 2 in game: camera box follows, pin toggles, S/M/L works. Fix round implemented (pinned ESC, position on reopen, portrait fit, camera footprint projection), awaiting TESTING.md section 0. Phase 3 (industry cargo icons, GameMap without industries) implemented, offline checks green, awaiting TESTING.md section P3. **Phase 6 (2026-10-09, revision 5):** network layer (Net toggle: streets, tracks, town buildings as a raw-pixel image) implemented, offline checks green (`test_net.lua`), first in-game round: draws, RGBA + transparency OK, rows are bottom-up (fixed with NET_FLIP_ROWS, calibration off); round 2: street-system listing, updates and off/on work, first build ~0.2-0.5 s sliced. **Round 3 implemented (2026-10-09), awaiting TESTING.md P6 "Round 3":** magnifier size button (base `inspector` icon), Hi-vis palette (re-encode only), Net off parks the caches for 60 s (instant re-enable, released from the guard tick), image handed to the engine once per version via an ImageView params userdata, encode buffer reused. **Round 4 perf (2026-10-09) + strips (2026-10-10) implemented, awaiting TESTING.md P6 "P6 perf run"** (PERF_REVIEW.md "Network layer").

</details>

## Findings (research, 2026-10-06)

| Need | API | Source |
|---|---|---|
| Terrain picture with towns/industries | `builtin.MapPreviewComp{ inputMap / initialMap = GameMap, mapColoring, showBiomesColors, ... }` | `.cache/game/base/tealdef/scripts/builtin.d.tl:1459` |
| Current save as a `GameMap` | `api.engine.terrain.makeMapFromGame(withHeightmap, withTowns, withIndustries, withAssets)` | `.cache/game/api/tealdef/api/engine.d.tl:1762` |
| Precedent: live game → preview | map editor: `makeMapFromGame` → `MapPreviewComp`, refresh only when `getTerrainEntityRevisions()`/towns change (`react.onStep` + deepEquals) | `.cache/game/base/content/gui/map_editor/map_editor.tl:300-345`, `:2670` |
| Map extent | `api.engine.terrain.getBoundingBox()` | engine.d.tl UtilTerrain |
| Camera read/write | `api.gui.camera.getCameraData()` → Vec5f {cx, cy, distance, angle, pitch}; `setCameraData`, `focusPosition`, `setManualCamera`; `getSize`, `screen2World` for the view footprint | `.cache/game/api/tealdef/api/gui.d.tl:426-506` |
| Overlays | `builtin.AbsoluteLayout` / `AbsoluteLayoutChild` (pixel-positioned children); `ImageView{ data / data_native, size }` raw pixels (format unknown) | builtin.d.tl:666, :799 |
| Fallback terrain | `getHeightAt`, `isOnWater` sampling | engine.d.tl UtilTerrain |

## Risks

1. `MapPreviewComp` was built for menus/map editor: may be slow, need a GameMap with heightmap each refresh, or misbehave in a small in-game window.
2. `ImageView.data` pixel format is undocumented (base game only passes screenshot `image_native`). Needed for a drawn network layer.
3. Refresh cost: terrain only on revision change; camera box per frame is cheap.

## Phase 1 results (in game, 2026-10-07)

- `MapPreviewComp` + `makeMapFromGame` renders the save as-is (terrain, water, town + industry icons) in all three modes (keep / streets / none); no generation. Build ~12 ms, ~70 ms with assets; `onReady` ~35 ms after mount.
- Camera box never drew: `useStepStateTimer`'s getter runs on a worker ("Main Pool 7") where `api.gui.camera.*` throws "API is currently restricted". Camera reads must run on the main thread (the first-footprint read from the content recipe worked).
- Mouse events reach the canvas; `getPosition` returns 0..1 screen fractions, events are pixels (2560x1440); click-to-jump worked.
- Crash fixed: `builtin.Component{ layout = CustomRecipe{} }` → "Item of Component must be a layout". Recipes go straight into `FloatingLayoutChild.item`.
- Window API: `builtin.Window{ pinnable, pinned, onPinned, compact, initialX/Y, movable }` (builtin.d.tl:1186).

## Phases

1. **Spike** — scaffold the mod; a toggleable in-game window (HUD button) showing `MapPreviewComp` fed by `makeMapFromGame`; camera box overlay following the view; click on map → jump camera. Logs timings (`[Minimap]`). Goal: answer risk 1 in game.
2. **Window polish** — camera box on the main thread; pinnable window (`pinnable`/`onPinned`, pinned state + position kept for the session); map fills the window (compact window, sensible size, maybe S/M/L); drop the phase-1 debug controls (Flip X/Y, Swap, mode, Traced box: fixed orientation = flipY, mode = keep, always traced); option changes that need a rebuild (Assets) rebuild automatically; no periodic timer — keep the change-driven rebuild (terrain revisions, towns, + industry count).
3. **Resource icons** — the preview draws every industry with one CSS class (`MapPreviewComp::IndustryMarker`, base builtin.css.lua:1917), so build the GameMap with `withIndustries = false` and draw our own industry markers in the overlay with the icon of each industry's product/type. Position markers with the sized-container trick (FloatingLayoutChild h=0,v=0 → container sized left+w × top+h → child at h=1,v=1); fractional gravity mispositions larger children in game.
4. **v1** — resizable/toggleable corner window, town + industry markers, station dots coloured per line, settings persisted. Must not impact existing saves (GUI-only, no game-state writes).
5. **Later** — ~~raw-pixel network layer~~ (phase 6 below), filter toggles (rail/road/water/air), vehicle dots.
6. **Network layer** — see "Phase 6" below.

## Phase 6: network layer (2026-10-09, revision 5)

User request: "a toggle in the minimap that draws the actual roads, cities, etc. onto the map; every so often it
checks and draws the real game state. It must be performant, and have no impact if toggled off."

### Design

- **Toggle**: a **Net** checkbox in the control row (Ind, Net, S/L), default off, remembered with the other prefs
  (`showNet` in `AppConfig.mainMenuState`). A checkbox rather than a button: it is an on/off state like Ind next to it.
- **Off = no cost**: the layer recipe `MinimapNetLayer` is mounted only while Net is on, so off means no onStep, no
  timer, no engine read, no ImageView. Unmounting the window or an error drops every cache (`netRelease`); toggling off parks them for 60 s (round 3, below).
  While on but hidden, nothing is read (looked at once a second); after 60 s hidden the caches are dropped as well
  (re-opening rebuilds). The brief said "release when hidden": the 60 s grace avoids a full rebuild every time
  the player flicks the Map button. Map editor: the HUD button doesn't exist there, so the layer can't mount.
- **Data** (main thread, `react.onStep`; never `onStepTimer`):
  - Edges: `getEntitiesWithComponent(BASE_EDGE)`. docs/findings.md shows that listing `BASE_EDGE_STREET` throws
    "Cannot loop over this component type", so if `BASE_EDGE` throws too, the fallback is
    `streetSystem.getNode2StreetEdgeMap()` + `getNode2TrackEdgeMap()` (system.d.tl:302-304, which also give the
    kind; each edge appears at both nodes, and the diff de-duplicates). The `net:` log says which one ran.
    Per new edge: `BASE_EDGE` (positions, tangents, type) and, in component mode, `BASE_EDGE_STREET` presence (street, else
    track; as bb_gather.tl / sl_toolcore.lua do). `BaseEdgeType.TUNNEL` is drawn dashed.
  - Town buildings: `townBuildingSystem.getTown2BuildingMap()` + `BOUNDING_VOLUME` bbox (as sg_gather.tl), drawn as
    filled rects in a muted colour under the roads. Stations are not drawn separately (their tracks are edges).
  - Every 5 s (`net.scanInterval`: at least 500x the list time, max 60 s) both lists are re-read and diffed against
    the caches (`net.diffStep`, resumable); only new ids are read. A failed list call skips the scan, so nothing is
    removed on an API error.
- **Time slicing**: only the two list calls are unsliced (one per frame). Diff, removals, reads, rasterising and
  encoding run in chunks under a **2 ms/frame** budget (`api.type.Clock`). The image is swapped only when a pass
  completes and something changed.
- **Raster**: a counting grid. Each pixel holds towns + streets x 4096 + tracks x 4096^2, colour = top layer.
  Removing an item subtracts the same pixels again (deterministic rasteriser), so there is never a full redraw.
  Curves: cubic Hermite from position/tangent, segment count from the Bezier control polygon in pixels (1 when
  flat, about 3 px per segment, at most 32), then Bresenham.
- **Image**: **512 px on the long side** at any S/L (Stretch-scaled to the picture), so S/L re-mounts the ImageView
  without rasterising again. Same world -> picture mapping as the industry markers (`geom.worldToFrac` with
  `ORIENT`; `net.toPx` is tested against it). It sits over the preview, under the industry icons, keyed like the
  markers (gen + width), with a new key per image version.
- **Perf instrumentation**: perfStep `net_list`, `net_diff`, `net_read`, `net_raster`, `net_encode`, count
  `net_publish`; perf (gui) `net_render`. That last one includes the table -> C++ copy, because `react.lua`
  `makeUserdata` assigns `data` inside `builtin.ImageView{}`. Log: `[Minimap] net: on ...`, `net: first build ...`
  (2 lines), `net: update N ...` (first 5 per state), `net: released (...)`.
- Offline bench (Lua 5.4, lupa; scratch test, not kept): 512x512 grid 1.8 ms; 50k random short edges sampled
  80 ms, rasterised 36 ms; full encode 15 ms (1 M bytes). The Lua side of a 50k-edge first build is about 65 frames at 2 ms.
  In-game engine read costs are unknown.

### Pixel format evidence (risk 2)

- The base game only feeds `image_native` from a `GameScreenshot` (savegame_react_util.tl:85-95).
- Game binary (build of 2026-10-06, `strings` + `objdump -d` of `TransportFever3`):
  - `BuiltinImageView.cpp`: "ImageView Cannot use image data with invalid pixel size (only 3 or 4 is
    supported)" + "pixelSize={}". The code at 0x103205c38 computes `(vector end - begin) / (size.x * size.y)` and accepts
    only 3 or 4. Otherwise it logs (line 103) and sets a default image via the same setter as `path`: **no throw, no
    over-read**. So a wrong length shows a placeholder and an error line, not a crash.
  - Its typeinfo strings sit as `params::ImageView`, `UserdataValue<VectorWrapper<unsigned char>>`,
    `UserdataValue<params::ImageView>`, so the data vector is **bytes** (one Lua integer = one byte). Packed
    one-int-per-pixel formats are out (pixel size 1).
- Chosen: **4 bytes per pixel, RGBA, first row = top** (`NET_ORDER = "RGBA"`, `NET_FLIP_ROWS = false`). Channel order
  and row order are not provable from the binary. `NET_CALIBRATE = true` (temporary) paints red, green, blue and 50%
  white squares, left to right, at the top-left. Red/blue swapped -> `"BGRA"`; squares at the bottom-left ->
  `NET_FLIP_ROWS = true`; alpha ignored (black background) -> report it (the layer would need another approach).
  Set `NET_CALIBRATE = false` once confirmed.

### Risks / open in game

1. Whether `getEntitiesWithComponent(BASE_EDGE)` lists (else the street system fallback; both handled).
2. Channel/row order and whether alpha is honoured (calibration patch).
3. Cost of the engine-side copy of a ~0.5-1 M entry table per image (`net_render`) and of the two list calls on a
   big map (`net_list`; the scan interval stretches automatically).
4. Memory: about 1 M Lua values per image plus the grid (~0.26 M) while Net is on, freed when off.
5. A one-frame gap when the image is swapped (new key): it may flicker.

### Round 3: toggle stutter, Hi-vis, magnifier (2026-10-09)

- **What ran unsliced on Net on (round 2 code):** toggling off called `netRelease`, dropping the grid (0.13-0.26 M
  numbers), the encode table (0.5-1 M numbers, 8-16 MB as Lua values) and ~8.5 k item tables at once. Toggling on
  then rebuilt everything: grid allocation (0.7-1.7 ms), two list calls (~2 ms each, one per frame), 20-29 sliced
  frames, an encode table grown from empty by doubling (its last rehash copies 0.26-0.5 M entries in one step: the
  rare 38 ms `net_encode` slow line fits), and on publish the render's `builtin.ImageView{ data = table }`, which
  makes react.lua `makeUserdata` copy the whole table into C++ (`userdata[key] = value`, react.lua:182) on every
  render of the layer, outside our step budget. The released 10-20 MB plus the new allocations also drive the
  incremental GC of the shared GUI Lua state hard for the next frames. A visible stutter + redraw is consistent with
  this mix; the round 3 log fields split it (`net_grid`, `net_handoff`, `net_on_cold` vs `net_on_cached`).
- **Fixes:** Net off parks the state (image, grid, items; the Lua encode buffer is dropped) for 60 s, so a re-enable
  renders the cached image at once and only rescans (after 0.5 s). Released by the plugin's guard tick (one
  comparison per 0.25 s) or when the window unmounts. Images go to the engine through one
  `api.gui.react.params.builtin.ImageView` userdata (the class react.lua makeUserdata uses), filled once per image;
  renders pass the userdata, which makeUserdata copies in C++ (`class.new(ud)`), and the encode buffer is reused
  (no new table per update). The first image checks that path (copy keeps size + byte count via `data_native`),
  else it falls back to the table.
- **data_native:** no `Vector<integer>` constructor reaches Lua (type.d.tl:29-37 declares the generic record but no
  global; the base game only passes engine-made `image_native` vectors), so the params userdata is the reusable
  native container instead.
- **Memory while parked:** grid + ~8.5 k items (a few MB of Lua) + the C++ image (0.5-1 MB); with the table
  fallback also the image table (8-16 MB). Freed 60 s after switching off.
- **Hi-vis:** `net.COLORS_HIVIS` (orange buildings, yellow streets, magenta tracks, all opaque). The grid holds layer
  counts, so a switch is an encode-only pass (`net.recolorAction`); no outline (it would need a neighbour pass,
  ~2-3x the encode).
- **Magnifier:** the base GUI has no zoom/search icon in use; `gui.zip` holds
  `gui/line_vehicle_mgmt/icons/inspector@2x.tga` (120x120 greyscale magnifier mask), loaded by the plain name like
  `symbol_speed.tga` from the same folder (vehicle_eow.script.tl:535).

### Round 4: network layer performance (2026-10-09)

From the user's SQPERF run (net_render 6.6 ms per render, net_list up to 11 ms, rare 6 ms encode/read steps); details,
numbers and the in-game checklist in PERF_REVIEW.md "Network layer (2026-10-09)". In short: the scheduler moved into the
pure, tested `minimap_netscan.tl`; the layer render returns its old node while the image version and size are unchanged
(`react.findOldChildByLocalKey`); the three list calls run in three frames with the maps flattened in slices; scans back
off to 30 s while nothing changes; updates re-encode only changed 8-row bands; the hand-off has a frame of its own; no
closure per drawn item. Output is byte-identical (golden test computed with the pre-change code).

**In-game run 1 after round 4 (2026-10-10):** toggle cache and palette re-encode work; first build 405 ms over 27
frames; but the image hand-off took 7.9-8.2 ms in ONE frame for every image change (even `buildings +1`), and an
update after Net off/on re-encoded all 64 bands (the parked state drops the buffer). **Strips (2026-10-10,
implemented, awaiting TESTING.md "P6 perf run"):** the image is shown as 64-row strips (8 at 512x512), each its own
ImageView + buffer + params userdata; only strips with changed bands are re-encoded and handed off, one strip
(~1 ms) per frame, then published together (one version bump, staged/spare userdata per strip, so no half-old
picture); strip nodes are reused per strip version (`MinimapNetStrip` recipe + `findOldChildByLocalKey`). After a
park only the strips that change get a new buffer (encoded whole). Details: PERF_REVIEW.md "Strips (2026-10-10)".
