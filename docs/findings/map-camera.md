# Findings: Map, terrain and camera

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Camera zoom limit (2026-10-09)

Found with the probe `square_zoom_probe` (log lines `[ZPROBE]`, game stdout.txt). `BaseConfig` has no camera
distance field, so the GUI camera API is the only route past the zoom-out limit.

- **`api.gui.camera.setCameraData` accepts a distance past the limit, but the camera eases back.** Vanilla max
  distance about 4137 m (pitch 0.95). Setting 20000 read back 20000 immediately, then 18834 (frame 1), 17793 (2),
  16301 (5), 8210 (30), and the vanilla max after about a second. x1.5 and x3 behaved the same.
- **`setManualCamera(center, distance)` and `focusPosition(pos, distance)` don't change the distance** (read-back
  ratio 1.00, both calls from a button `onClick`).
- **The far plane follows the camera distance automatically**: `getNearFar()` went 7200 → 17549 at 18.8 km and
  back to 7200 near the limit. A pushed camera doesn't need a larger `viewNearFar` in `baseConfig.settings`.
- **Construction template entries reach `getActionParams` without `menuCategory`** (2026-10-09,
  `square_better_bus_overlay`): `construction_react_util.tl:1074-1097` builds template definitions with
  `menuCategory = template.menuCategory`, but the definition passed to the `getActionParams` wrapper had
  `menuCategory == nil` for the street station (log `menu=nil … modular_terminal.con template=0`). Read it from the
  resource instead: `api.res.constructionRep.findAndGet(definition.resName).constructionTemplates_native:at(
  definition.constructionTemplate + 1).menuCategory` (template index is zero based). Its `categories` /
  `filterCategories` are native vectors: `ipairs` sees nothing, use `:size()` / `:at(i)`.
- **Recolouring a stop's HUD pin** (2026-10-09, `square_better_bus_overlay`): `builtin.UseDefaultHudIcon` is engine-drawn,
  takes no colour, and no stylesheet reaches it. Wrapping the `builtin.UseDefaultHudIcon` module field (checked by
  `react.getCurrentRecipeName() == "HudStationWithLineStops"`) and returning a copy works: the mask
  `::/gui/hud/icons/hud_background.tga` in an ImageView (Stretch) tinted by CSS `color` at **29x38 UI px**, with
  `::/gui/hud/icons/vehicle_bus_front_32.tga` at 20x20 stacked on top (two full-size FloatingLayoutChild layers,
  padding 5/4/13/5), matches the vanilla pin in the Lines window. As a nine-patch background at the mask's natural
  40x52 it came out ~40 % too big. Line dots and terminal numbers stay the base ones.
- **Station HUD icons switch from group to per-terminal when zoomed in** (2026-10-09, `square_better_bus_overlay`):
  a hud icon master is called with `param.index == -1` (one icon per station group) from afar, but close to the camera
  with `index >= 0`, one icon per terminal (in the Lines window these carry the terminal number,
  `manager_hud_util.tl:546-557`). A replacement that checked only `index == -1` showed when zoomed out and vanished
  zoomed in; handle both.
- **A HUD tag next to the stop icon gets stretched** (2026-10-09): `!hud-icon-main > BoxLayout` (gravity {-1, 0},
  `gui_react_util.css.lua:54-57`) stretches a tag placed beside `UseDefaultHudIcon` in a horizontal BoxLayout to the
  icon's height. Replace the icon with the tag inside `BoxLayout{ class = "station-icon-layout" }` instead, as
  free play does (`hud_icon_toolbox.tl:112-142`).
- **The camera controller eases toward its own hidden target distance, which mods can't set.** After a push, the
  camera eased back to the last scroll-wheel distance (2771 m, below the 4137 m max), not to the limit. Re-applying
  the distance every `react.onStep` (via `react.enqueueJoin`) held it on average, but the controller had already
  pulled it back 4–16% before each reset, so the view visibly jittered. "Continuous Zoom" (`zoomPrecise`) was
  tried and didn't stop the ease-back. No camera limit exists in the API, `BaseConfig` or `settings.lua`.
  **Result: a "zoom out further" mod isn't feasible with the current API; idea scrapped.**

## Mod terrain generators for base climates (2026-10-09)

Found with `square_blank_slate` rev 1 (user's game test, 2026-10-09; screenshots in `plans/square_blank_slate/shots/`).

- **A mod `.gen.lua` joins a base climate's generator list** with an absolute climate id:
  `climate = "::/climates/temperate/temperate.clima"` (the base files' relative `"temperate.clima"` would resolve inside
  the mod). Its tree's `climate` field uses the same form. No `_content.json` or other registration is needed: the file
  sits in `content/<dir>/` and `nodeTree` names the tree without folder or extension. It showed up as a "Generator"
  option in New Game, with an empty Terrain section because `params = { }`.
- **A heightmap PNG works as the whole terrain.** A `texture_map` node with `minHeight`/`maxHeight` `constant_number`
  inputs and `tex = "<modId>::/<dir>/<file>.png"` (16-bit grayscale, 1024 px) feeding `height_map_output` gave the exact
  shape, stretched over the map. Sea level is 0 m, so anything below 0 is water.
- **No trees or rocks:** an `assets_output` whose `assets` and `forest` inputs are a constant 0 `constant_map`, with
  mappings that only use other values, placed nothing. A minimal tree (`biome0` = 1, `biome1..4` and `forest_mask` = 0,
  a `Biomes` `output_biomes` of 0) ran fine on temperate with green grass ground and a sandy shore.
- **Towns and industries still appear** in New Game (25 towns, 9 industries on Medium): the menu's own sampler places
  them after the generator, whatever the tree outputs. The Map Editor's Generate heightmap turns them off.

## Map editor: Generate Heightmap leaves terrain entity revisions unchanged (verified in game 2026-10-10)

- `api.engine.terrain.getTerrainEntityRevisions()` returns the same revisions before and after the map editor's
  Generate Heightmap → **Generate** (`makeWorldReplaceTerrainCmd`, `base/content/gui/map_editor/map_editor.tl:796`),
  although the whole terrain is replaced. The editor's own `useAutoUpdater` (map_editor.tl:298-345) compares exactly
  that, so a mod copying its change check misses a new heightmap.
- Detect it by sampling `api.engine.terrain.getBaseHeightAt` on a coarse grid (square_better_minimap: 9x9 points over
  `getBoundingBox()`, every 2 s). Base height excludes construction alignments, so placing stations does not trigger it.
- Mod GUI plugins in `::MainModButtonAreaExtension` mount in the map editor too (`gui/main/game.tl:554` mounts the
  area unconditionally); a plugin that should hide there checks `api.gui.game.isMapEditor()`.
- Evidence: stdout.txt, two Generates at 23:10:07 and 23:10:26 ("Map is ready"), each followed by
  `[Minimap] map gen N (changed: heights, ...)` and no `terrain` in the changed list; before the height grid there
  was no rebuild at all (23:08:40).

## Graphics settings from a mod: `api.util.setAppConfig` (verified in game 2026-10-12)

Found with the DEV probe `mods/square_photo_quality_probe` (steps and open runs:
`plans/square_photo_quality_probe/TESTING.md`). Sessions `2026-10-12_2333_sqpq`, `2026-10-13_0040_sqpq`.

- **A mod GUI script can read and change the graphics settings mid-game.** From a `::MainModButtonAreaExtension`
  plugin (Main Thread): `local cfg = api.type.AppConfig.new(api.util.getAppConfig())`, set keys by name,
  `api.util.setAppConfig(cfg, false)`. The graphics keys are not in the `AppConfig` record of `type.d.tl`; the
  settings page writes them by name (`base/content/gui/menu/settings_page.tl:866-990`): `textureQuality`,
  `terrainTextureQuality` (0-2), `numMSAASamples` (1/2/4/8), `useSsao` (bool), `ssrQuality`, `shadowQuality`,
  `geometryQuality`, `terrainQuality`, `grassQuality` (0-2), `resolutionScale` (0.5-1.0), `vsync`. All of them apply at
  once in game; `app.getSupportedMSAASampleCounts()` works in the GUI state (`{1,2,4,8}` on the Mac test machine).
- **The switch stalls about 1.2-1.3 s** with textures included: `setAppConfig ms=1182.5` (Low-ish -> boosted) and
  `ms=1327.3` (back), one frame of ~1.2-1.4 s each, and the player saw the hitch. A texture-quality change alone
  from the settings page also gave a ~1.1 s frame (`2026-10-12_2333_sqpq`), so the texture reload is most of it
  (no-texture switch not measured yet). With no value changed the call takes 0.2 ms.
- **Cost seen on 2560x1440, Apple GPU:** frame time ~18 ms at the player's low settings, ~40 ms boosted (Very High
  preset, 8x MSAA, 100 % resolution scale), back to ~19 ms after restoring. While lowering settings by hand, MSAA
  8x -> 2x plus SSAO off took ~16 ms -> ~10 ms; texture quality changed no steady frame time (rough: settings menu
  open, camera not fixed).
- **`setAppConfig` values get saved by the game.** `setAppConfig` itself does not save (`util.d.tl:261`), but a session
  boosted with the probe's restore turned off and then quit started the next session with the boosted values
  (`start config ... numMSAASamples=8`, a count no preset uses; user report, the boosted session's log was lost).
  The settings page also shows and keeps the values a mod set (user report). A mod that changes graphics settings
  temporarily must restore them on every exit path. Quitting to the main menu runs no `react.onUnmount` (see
  `findings/gui.md` "Quitting runs no react.onUnmount"), so the boost stayed on in the main menu (user report,
  `2026-10-13_0040_sqpq`). Restoring on the `openPauseMenu` event works (Esc, menu button, Cmd+Q; `2026-10-13_0053_session`), and the player
  found their own values in the main menu afterwards.
- **Every settings save is logged** as `Saved settings to settings.lua` (Save Pool thread): once at every game start
  and on every `api.util.saveAppConfig()`, from the settings page or any mod (Better Minimap saves its window prefs
  this way). So while a boost is on, another mod can save it at any moment; a next-load safety net is needed
  besides the pause-menu restore (probe: marker in `AppConfig.mainMenuState`, run C2 in TESTING.md).
- **Changing render-buffer settings at runtime crashes (from the game logs 2026-10-13, cause inferred,
  strong).** A mod may change at runtime only the settings that reload images or screen effects: `textureQuality`,
  `terrainTextureQuality`, `useSsao`, `ssrQuality`, `numMSAASamples`, `resolutionScale`. Never `shadowQuality`,
  `geometryQuality`, `terrainQuality` or `grassQuality` (they rebuild meshes / render buffers): leave the player's
  values alone, also in a snapshot / restore / next-load repair. Both kinds crash only now and then, so a few
  clean switches prove nothing. Seen on the Mac test machine only; not tested whether the base settings page's
  own change of these keys mid-game crashes the same way.
  - **`shadowQuality`: 4 crashes (MoltenVK, after "Could not invert matrix").** Shadow quality changes the shadow
    cascades (`Shadow map change size: (2048x2048) ... cascades = 2` vs `(4096x4096) ... cascades = 3`). Every
    crash came right after a `setAppConfig` that changed `shadowQuality` (0 -> 2): 3x WARNING `Could not invert
    matrix`, then a native crash in the same second; the first minidump's crashing thread was the render thread
    in `libMoltenVK.dylib mvkCmdBeginRenderPass` (EXC_BAD_ACCESS).
    - `2026-10-13_0342_sqot`, `2026-10-13_0356_top-up-779299`: Photo Mode's one-call switch of every key
      (`numMSAASamples` 1 -> 8, textures, shadows ...), `ms=1507.3` / `ms=1435.0` returned, then the warnings and
      the crash ~0.1 s later; 13-21 min into a session. The window-before-switch hypothesis didn't hold (crash 2
      had the switch first).
    - `2026-10-13_0522_sqrl-sqsg-crash` (desert save, camera looking almost straight down) and
      `2026-10-13_0524_sqrl-sqsg-crash` (another save): the 5-stage switch, one `setAppConfig` per stage, 3
      frames apart. Stages 1-3 (textures 823-1220 ms, detail, SSAO / reflections) passed; `hq stage 4/5
      keys=shadowQuality ms=0.2`, then the 3 warnings and the crash in the same second.
    - `2026-10-13_0418_session`: the 5-stage switch worked 4 of 4 and every one-call restore (which also put
      `shadowQuality` back) was followed by 2x `Could not invert matrix` without a crash. Every
      `Could not invert matrix` in the archive so far followed a call that changed `shadowQuality`; ~30 other
      switches with shadows (DEV probe one-call switches, fresh sessions) did not crash.
  - **`geometryQuality` / `terrainQuality` / `grassQuality`: 1 crash (fatal assert in the static mesh
    buffers).** `2026-10-13_0558_session-crash` (only Photo Mode enabled, "New Game - desert", the `_0522` save:
    `SaveGame Complexity estimatedMb=4581`, 1015 vehicles): `hq stage 1/4 keys=textureQuality,
    terrainTextureQuality ms=1710.1` passed, `hq stage 2/4 keys=geometryQuality,terrainQuality,grassQuality
    ms=1.1`, then in the same second `StaticBuffer.cpp:743: Render: Assertion 'it !=
    typeData.material2offsetAndCount.end()' failed` on several Main Pool threads, crash. No "Could not invert
    matrix" first. The same keys had changed without a crash 9 times as their own stage (`_0418`, `_0522` on
    this very save, `_0524`, `_0525`), 2 times as a restore stage (`_0525`) and in ~30 one-call switches (DEV
    probe, `_0418` restores). Not tied to save size as far as seen: the clean switches ran on saves of
    estimatedMb=8233 as well.
  - **The safe set never crashed**: textures / terrain textures changed in 12 switch or restore stages of their
    own (`_0418` 4, `_0522` 1, `_0524` 1, `_0525` 3 + 2 restores, `_0558` 1), SSAO / SSR in 11 (9 + 2), MSAA
    in 9 (7 + 2), and all of them in ~30 one-call switches; no crash, assert or "Could not invert matrix"
    followed any of these calls (the crashes above came after a later call that changed a render-buffer key).
    Verified 2026-10-13 (session `2026-10-13_0610_session`, the same desert save that crashed in 0558): the safe
    set switched on 3 times and restored twice in 3 stages each, `resolutionScale` 0.6 -> 1.0 and back included,
    with no crash, assert or "Could not invert matrix". Textures are the whole stall (1.1-1.6 s per direction).
  - Photo Mode's High graphics mode raises only the safe set (3 stages: textures; SSAO / reflections; MSAA /
    resolution scale); old markers that hold the other keys are accepted, those values never written. The DEV
    probe's boost (`mods/square_photo_quality_probe`, `sqpq_common.lua` `BOOST`) is the safe set too.

## The staged graphics switch: where the time goes (from the game log 2026-10-13)

Photo Mode's staged switch (`plans/square_photo_mode/PLAN.md` "Highest graphics: the staged switch"), session
`2026-10-13_0418_session` (~20 min into the session, 4 on / off cycles, no crash):

- **The texture stage is the whole stall**: stage 1 (`textureQuality`, `terrainTextureQuality`) took 911-1095 ms
  every time; geometry / terrain / grass 0.5-8 ms, SSAO / reflections 0.3-6 ms, shadows 0.2 ms (the shadow map
  resize shows in the log as `Shadow map change size` on the Main Launcher thread), MSAA 24-33 ms.
- **The one-call restores' `Could not invert matrix`** came from their `shadowQuality` change (see above), not
  from the one-call order as first assumed. Photo Mode still restores in stages (reverse order: anti-aliasing
  first, textures last; the pause-menu restore stays one call, a quit may follow at once), now without shadows,
  geometry, terrain and grass ("Changing render-buffer settings at runtime crashes").

## Geometry tiers (draw distance, LOD scaling): writes stick, no visible effect (in game 2026-10-13)

DEV probe `mods/square_photo_quality_probe`, sessions `2026-10-13_0100_session`, `2026-10-13_0109_sqpq`.
`preRunFn` can replace `baseConfig.settings` with a new `api.type.BaseConfig.Settings` whose
`geometryQualityOptions` (6 tiers: low, medium, high, camera tool, cockpit, camera tool preview;
`base/content/base/mod.script.tl:146-154`) carry other values: `postRunFn` and the in-game GUI read them back
(e.g. `camtool=far40000/lod20.00`, `camtool_preview=lod20.00`). But the player saw no difference: camera tool
LOD 5 -> 20 and far 22.5 -> 40 km (free camera-tool view and keyframe playback), preview tier LOD 1 -> 20, all on
a desert map that fits inside 22.5 km and on a sub-arctic save. Cause unknown (the renderer may read the tiers
elsewhere or only at start-up, or the models' own LOD ranges cap it). Don't build a feature on these tiers
without a new, measured test.

## Screenshots: `takeScreenshot(scale)` is a resolution multiplier, never includes the UI (verified in game 2026-10-13)

DEV probe `square_photo_quality_probe` T1, session `2026-10-13_0339_sqpq`, 2560x1440 viewport, PNGs measured with
`sips`. Requests 1, 2, 3, 4 (3 s apart), then 1, 2, 4 (the last right after a stall), then 2 with the UI hidden;
files in order: 5120x2880 (24 MB), 7680x4320 (52 MB), 10240x5760 (89 MB), 2560x1440 (6 MB), 5120x2880, 5120x2880.
So the image is viewport x `scale`: **4 works** (10240x5760 at 2560x1440). The first request of the session wrote no
file (known), and a request made right after another big shot was dropped too. A scale 4 shot took ~9 s from file
name to `Screenshot: wrote` (encoding an 89 MB PNG); the frame stalls meanwhile. **The UI is never in the image**:
a plain shot with the game bar, windows and the probe window open came out exactly like the "UI hidden" shot (3D
view only). A mod needs no hide-UI step for clean screenshots.

## Hiding the game UI from a mod (verified from the game log 2026-10-13)

Same session, T2. `api.gui.byId.setVisible("react.game-ui-root", false)` hides the game UI root (game bar
included: `menu.gamebar` recursive visibility false) and it **stays hidden** until set back (5 s, restored by the
timer). `setVisibilityByClass("react.game-ui-root", false)` hid it for one frame; 1 s later the game had shown it
again. `setVisibilityByClass` on `menu.gamebar` + `menu.gamebar.bottom` (idOnly) hid only the bottom bar (the main
bar came back within 1 s). `api.gui.camera.toggleFreeCamera()` also hides the UI root, but a second toggle does not
bring it back: `leaveFollowCameraCockpit()` does (the base free-cam tool does the same, `free_cam_options.tl:44-46`).
A plugin's `react.onStep` keeps running while the UI root is hidden in every variant, so a timer or key check can
restore it. What the player saw per variant was not reported.

## Full-screen overlay window crashed (2026-10-13)

Same session, T3: opening a `react.RegisterWrapperRecipe(..., builtin.Window, ...)` whose render first called
`react.setMouseTransparent(true)` and then returned a compact, title-less `builtin.Window` (transparent inline
style, content 2560x1440) crashed the game: `ERROR expectedRecipeId=39, expectedName=Window`, then the fatal
`Wrapper recipe must return child (react.lua:282)`. Better Minimap's Window wrapper (no `setMouseTransparent`)
works, so the hook call inside the wrapper is the likely cause (inferred, not isolated). Never call react hooks
such as `setMouseTransparent` in a Window wrapper's render. The rule-of-thirds grid was dropped from Photo Mode.
