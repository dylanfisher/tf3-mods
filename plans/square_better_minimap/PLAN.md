# Better Minimap (`square_better_minimap`): plan

An always-available minimap for TF3: terrain overview of the current save, a box showing the camera view, and click-to-jump. Built only on the game's own API (no code from other minimap mods).

**Status (2026-10-07):** phase 1 verified in game; phase 2 in game: camera box follows, pin toggles, S/M/L works. Fix round implemented (pinned ESC, position on reopen, portrait fit, camera footprint projection), awaiting TESTING.md section 0. Phase 3 (industry cargo icons, GameMap without industries) implemented, offline checks green, awaiting TESTING.md section P3.

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
5. **Later** — raw-pixel network layer (if risk 2 resolves), filter toggles (rail/road/water/air), vehicle dots.
