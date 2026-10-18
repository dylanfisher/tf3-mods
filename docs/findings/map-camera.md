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
  values alone, also in a snapshot / restore / next-load repair. Update 2026-10-14: geometry / terrain / grass
  passed one key per call (below); shadows crashed even alone. Both kinds crash only now and then, so a few
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
  - Photo Mode's High graphics mode raises the safe set (3 stages: textures; SSAO / reflections; MSAA /
    resolution scale) and, since round 19 (2026-10-14), geometry, terrain and grass in a stage each; never shadows
    (an old marker's shadow value is accepted and never written). The DEV
    probe's boost (`mods/square_photo_quality_probe`, `sqpq_common.lua` `BOOST`) is the safe set too.
  - Retest one key at a time (round 18, DEV only, never uploaded; removed in round 20 once High graphics mode took
    geometry / terrain / grass): `square_photo_mode_dev`
    `photo_mode_dev/pm_risky.lua` added "DEV: risky graphics" to Photo Mode's Settings tab, one checkbox per key,
    each change a `setAppConfig` of that key alone with a `[PhotoMode] DEV risky <key>: setting a -> b ALONE` line
    right before and `... done` right after, so a crash log names the key (Photo Mode TESTING.md R18-1).
    Result 2026-10-14 (`2026-10-14_2019_r18-test-risky`, desert save, only Photo Mode + DEV): `grassQuality`,
    `terrainQuality` and `geometryQuality` 1 -> 2 alone, each switched on / off / on again, all `done ms=0.0`, no
    assert, no crash; then `shadowQuality` 0 -> 2 alone logged `done ms=0.0` and the game crashed natively
    (minidump) at once, the 5th shadow crash. So shadows crash even alone; geometry / terrain / grass passed alone
    (their one crash, `_0558`, was the three in one call). Photo Mode's High graphics mode now raises these three,
    one key per stage after the safe set (round 19); still "now and then" until many more switches pass.

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

**Update (session `2026-10-14_0055_session`, Photo Mode): `takeScreenshot` blocks until the file is written.** The
game's `Screenshot: wrote ...` line comes BEFORE the line Photo Mode logs right after the call returns, for every
scale. The game freezes meanwhile: 4x (10240x5760 at 2560x1440) from file name 17-59-26 to `wrote` at :37, ~11 s,
with two `Thread did not respond to ping. Possible hang detected!`; 2x ~3 s (18-01-57 to 01:02:00); 1x under a
second (SQPERF `camera_step max=663 ms` for the primer + 1x). So a status set in the same frame never shows before
the freeze (no frame is drawn between), and a cooldown counted from the first tick after the call already starts
after the freeze. Photo Mode round 11 announces the freeze first and shoots ANNOUNCE_MS later (pm_shutter).

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

**Update 2026-10-16: the inline style is the likely cause.** Smart Lanes' welcome window (a Window wrapper, no hook
call) crashed the same way as soon as it got `meta = { styleSheet = styleutil.makeStyle{ anchorPoint = {0.5, 0.5} } }`
plus `initialX/Y = 0.5` (session `2026-10-16_1844_sqrl-sqsg`: `WELCOME op=show`, then `ERROR expectedRecipeId=39,
expectedName=Window` and the fatal `m_data->activeNodeIds[id]` while transforming the WindowContainer); the same window
without them opened fine in `2026-10-16_1815_sqrl-sqsg-crash`. Both crashes share an inline `meta.styleSheet` on the
`builtin.Window`. Never give a Window an inline style: place it with a `.css.lua` rule on its id (`anchorPoint` +
`initialX/Y`, Better Minimap / Problem Radar) or a base window class.

## The free camera ignores setCameraData (inferred from three game logs 2026-10-13, strong)

Photo Mode round 6 pushed the base `FreeCamTool` for a tour and probed whether `setCameraData` still drives the
view (`pm_cammode.matches`: the `getCameraData` read-back, then `getCenter` on the set centre and `getEye` at the
set distance from it). Session `2026-10-13_0733_bench-s3-683079`: `camera mode: on (tour)`, then in the same
second `camera mode: setCameraData ignored -> fallback hidden UI (set d=120 read d=120)`, two probe frames.

- The read-back equalled the view set, so `getCameraData` reports (and `setCameraData` sets) the normal camera's
  data while the free camera is active; the check that failed was `getEye` / `getCenter`.
- The view set in those frames was still the pre-tour view (the tour's first glide starts at rest), which a
  camera left where it was would have matched. So `getEye` / `getCenter` reported a camera with a geometry of
  its own: **inferred, the free camera is a separate camera that `setCameraData` doesn't move**. The API has no
  setter for it (`api/tealdef/api/gui.d.tl` camera: `setCameraData`, `setManualCamera`, `focusPosition`,
  `followEntity`; `getEye` / `getCenter` are read-only), so a mod can't fly the free camera.
- Not yet seen: the eye / centre values themselves. Photo Mode round 7 logs every counted probe frame in full
  (`camera mode: probe frame N (waited W) set= read= eye= centre= |eye-centre|= match=`, counted only once our
  view has moved away from the entry view) and keeps camera mode for tours off by default
  (`plans/square_photo_mode/TESTING.md` R6 settles it).
- Seen (session `2026-10-13_0856_sqot-dev`, 2 probe frames, round 7): `set=-3488.9,252.9,124.9,2.921,0.310`
  read back exactly; `eye=-3586.4,274.7,69.6 centre=-3502.1,256.7,18.8 |eye-centre|=100.0`, identical in both
  frames while the view set moved. The heading eye -> centre matched the angle (+ pi), but the eye-centre
  distance was exactly 100 (set 125) and the centre 14 m off the one set: a camera of its own (a free camera's
  "centre" a fixed 100 m ahead of its eye), which strengthens the inference.
- Seen again (session `2026-10-13_1755_session`, round 8, 2 probe frames 21 frames after the push):
  `set=-419.0,-591.8,42.2,2.562,0.007` then `-419.0,-591.7,42.3,2.560,0.008`, read back exactly; `eye=-454.2,-570.8,18.0
  centre=-371.5,-622.5,-4.0 |eye-centre|=100.0` in both frames. Same picture: its own camera, 100 m between its eye
  and "centre". Photo Mode round 9 removed camera mode from tours (the footer's Camera mode button, a manual free
  look, stays).

## Bird's eye at pitch 1.45 inverted the keyboard pan (user report 2026-10-13, cause inferred)

Session `2026-10-13_0733_bench-s3-683079`: Photo Mode's Bird's eye shot `setCameraData(x, y, 900, angle, 1.45)`
with the angle kept from the current view (`shot bird view=...,0.246,1.450`; the next read of the camera showed
the same angle). The user: "when I press bird's eye the WASD controls are inverted". Normal views (pitch up to
1.2 from Photo Mode, the player's own) pan the right way.

- Our values were as meant: 1.45 rad is below the vertical (pi / 2) and the angle had no 180° turn, so the game's
  camera itself handles a pitch that close to straight down differently (inferred: past its own tilt limit).
- Photo Mode round 7 caps every pitch it sends at 1.35 (`cam.PITCH_MAX`) and shoots Bird's eye at 1.30; whether
  1.30 pans the right way and what the game's own steepest tilt is are open (`plans/square_photo_mode/TESTING.md`
  R4: a saved view at the steepest mouse tilt logs it).
- Round 8 explained it with a constant pitch offset (1.45 + ~0.23 past straight down). The camera model fitted in
  round 9 ("The game's camera model" below) contradicted that (its form never passed straight down).
- **Round 10's refit explains it again (inferred, strong):** the elevation has a distance-dependent lift on top of
  the blend, so 1.45 at 900 m gives an eye elevation of 1.67 rad, past straight down (pi / 2 = 1.571); 1.30 gives
  1.54. Photo Mode now caps every pitch it sends at the one whose elevation is 1.50 at that distance
  (`pm_flight.pitchMaxAt`; Bird's eye at 900 m becomes ~1.25). The player's own steepest tilt is still unmeasured.

## The camera centre sits on the terrain: moving it bobs the eye (user report 2026-10-13; corrected rounds 8 and 9)

`setCameraData(x, y, d, angle, pitch)` places the eye around a centre on the ground, so a camera move that slides
the centre over uneven ground lifts and drops the eye with every bump under the look-at point. The user on Photo
Mode's tours (session `2026-10-13_0733_bench-s3-683079`): "the height maps really mess up the experience, it's not
smooth", pans "stuttery because it follows the terrain map".

- Fix in Photo Mode round 7 (`pm_flight.lua` "Eye space"): plan the eye, not the centre; each frame walk the look
  ray to `api.engine.terrain.getHeightAt`'s ground and send that point as the centre with the distance and
  pitch from the eye to it (3-7 `getHeightAt` a frame).
- **Round 7 assumed the eye sits `d * sin(pitch)` above the centre's ground. The eye checks of session
  `2026-10-13_0856_sqot-dev` contradict that**: the game's eye was 14-76 m (one 549 m) above the eye planned
  that way. See the next entry: the eye sits on a steeper line than the pitch set. Whether the centre's height
  is exactly `getHeightAt` there (water, bridges) is still open (the round 8 trace logs `getCenter` and our
  ground, `g=`).
- **Answered by session `2026-10-13_1755_session`: the centre sits 4.0 m above `getHeightAt`** (11 of 12 eye checks
  and every one of the 56 trace frames that read it; see "The game's camera model").

## The game's eye sits steeper than the pitch set (eye checks 2026-10-13; superseded by "The game's camera model")

Round 9 (session `2026-10-13_1755_session`): the offset is not constant; it depends on the distance and the pitch,
and the centre is 4 m above the ground. The fitted model is the next entry. Kept for the history of the evidence.


Session `2026-10-13_0856_sqot-dev` (Photo Mode round 7, `[PhotoMode] eye check` lines: the eye planned with
`eye = centre ground + d (cos pitch, sin pitch)` against `api.gui.camera.getEye()`; the view set was not logged,
so the centre is reconstructed from the look ray and the logged look targets / hop views):

| case | planned eye | getEye | what fits |
|---|---|---|---|
| hop (viewpoint), `to=-1984,-9864,1207,1.571,0.104` | -1981.9,-8643.2,126.1 | -1982.6,-8844.1,675.4 | same distance (1213 / 1211 m), pitch 0.10 -> 0.59 |
| hop (passing), `to=...,163,-2.552,0.120` | 3510.5,-6765.4,23.1 | 3519.5,-6759.2,71.1 | distance 160 / 162, pitch 0.12 -> 0.43 |
| wander (pitch 0.04-0.20, looking at a building) | -710.9,-7349.9,14.5 | -718.1,-7362.6,90.5 | distance ~255, pitch ~0.04 -> 0.34 |
| wander (pitch 1.18-1.20, after a Bird's eye) | -740.0,1860.2,913.2 | -796.2,1658.3,971.1 | distance 969 / 970, pitch ~1.19 -> 1.42 |

- In every case `getEye` lay **in the vertical plane of the look** (the horizontal shift from the planned eye
  pointed along the look heading, within ~0.05 rad), **toward the centre and up**, and where the centre could be
  reconstructed, **at the distance set from it**: the game turned the eye up around the centre. The steeper
  line was about 0.22-0.34 rad above the pitch set (the viewpoint hop 0.49, its centre the least certain). The
  six wander and hop lines without a reconstructed centre fit the same picture (dz 14-76 m, the shift along the
  look). `getCameraData` reads back exactly what was set (the probe frames of the same session).
- **Inferred: the eye-centre elevation is the pitch set plus an offset of ~0.25 rad** (not a minimum: a pitch
  of 1.19 also came out ~0.23 steeper). It also explains "Bird's eye at pitch 1.45 inverted the keyboard pan":
  1.45 + ~0.23 is past straight above the centre (pi / 2), so the camera looked back over the top. What the
  offset is (a fixed tilt of the look-at point below the screen middle, a zoom-dependent tilt, ...) and whether
  it depends on the distance or pitch is open.
- Photo Mode round 8: measures the offset live (`pm_flight.pitchSample`: the elevation of `getEye` over
  `getCenter` minus `getCameraData`'s pitch, refused when the game's distance or centre doesn't match the data;
  smoothed over 2 s; the first sample of a session from the camera as it stands, logged `pitch offset measured`)
  and compensates it in the eye-space solver (sends `elevation - offset`, the look at least `offset` steep, since
  the game takes no pitch below 0). A per-frame trace (`cam trace f=N read= eye= centre= hat= plan= set= g=
  sample= off= scr=`) logs the first 40 frames of the session's first two moves (every move with "Debug:
  performance log" On); `scr=` is where `getCenter` shows on the screen (0.5,0.5 = the middle), which tells
  whether the screen middle looks along the pitch or at the centre. `plans/square_photo_mode/TESTING.md` U8-U10.

## The game's camera model (session 2026-10-13_1755_session: centre lift verified, tilt fitted; refitted 2026-10-13 with 2026-10-13_1915_session, see the end)

Photo Mode round 8 logged 80 `cam trace` lines (56 with `getEye` / `getCenter` read) and 12 `eye check` lines
(`make logs-grep PAT='cam trace|eye check' ARGS='--session 2026-10-13_1755'`). Each line has the view read back
(`getCameraData`), `getEye`, `getCenter` and our `getHeightAt` under the centre (`g=`).

- **Centre: `getCenter` = (x, y, getHeightAt + 4.0)** (verified): 10.3 vs 6.3, 196.0 vs 192.0, 194.2 vs 190.2, 176.4
  vs 172.4, 87.4 vs 83.4, 98.1 vs 94.1, ... in every check on land; x, y exactly the ones set. Over water 4.0 at
  ground -1.0: the water level (0) + 4 (one check, inferred; the terrain record has a `waterLevel`, assumed 0).
- **Eye: at the distance set from that centre, in the look's vertical plane** (verified: |eye - centre| = d within
  0.2 m in all 12 checks; the heading eye -> centre is the angle set within 0.003 rad); `world2Screen(getCenter)`
  is the screen middle (0.500, 0.500 in every traced frame): the camera looks at its centre.
- **Elevation of the eye over the centre: e = p + k(d) (pi/2 - p), k(d) = 0.0768 + 0.0102 sqrt(d)** (fitted): the
  pitch set is blended towards straight down, more the farther out. Least squares over the 12 checks and every
  6th trace frame (22 points, d 30-400 m, p 0-0.67): residual rms 0.0036 rad, max 0.011. Candidates compared (rms /
  max, rad): a constant offset (round 8's model) 0.054 / 0.100; offset a + b sqrt(d) without p 0.024 / 0.061;
  (a + b d^c) cos p 0.013 / 0.028; (a + b d^c) cos^2 p 0.0085 / 0.017; (a + b d) (pi/2 - p) 0.0068 / 0.018;
  (a + b ln d) (P - p) with P free 0.0072 / 0.017; **(a + b sqrt d) (pi/2 - p) 0.0036 / 0.011** (a free "straight down"
  of 1.7 instead of pi/2 gives 0.0030 / 0.008, not worth the odd constant). k: 0.14 at 40 m, 0.21 at 160 m, 0.28 at
  400 m; extrapolated, 0.38 at 900 m (Bird's eye), 0.73 at the 4 km zoom limit (unchecked: Photo Mode measures
  the residual live). Within one move the trace's sample stayed constant to 0.001 (0.203 over d 41.8-45.4, p
  0.145-0.168; 0.221-0.222 over p 0.005-0.025), as the model says for such small changes.
- Not a minimum height above the terrain under the eye (`getHeightAboveTerrain`, `hat=`, varied 9-16 m in the
  trace while the model held) and not a near-plane effect (the base camera tool's near plane is 4 m,
  `base/mod.script.tl`, but the eye-centre distance is the one set). The game files hold no camera curve (the
  camera controller is native; nothing in `base/content` or the API defines a zoom-dependent tilt).
- Consequences: (1) no pitch >= 0 shows an elevation below `k(d) pi/2` (0.22 rad at 40 m, 0.40 at 300 m): a level
  look at the horizon is impossible, flatter looks only close to the centre; (2) to put the eye at elevation e,
  send `p = (e - k(d) pi/2) / (1 - k(d))` with the distance of that frame: a solver whose distance changes with
  the terrain under the look (crests) must apply the model per frame. Round 8 smoothed one measured offset over
  2 s, so the eye jumped and lagged whenever the distance changed: the jerky Wander and glides the user saw.
- `getEye` read nothing (`eye=-,-,-`) for the first 24 trace frames of the session only because Photo Mode's camera
  mode probe was running (the driver skipped its samples while probing), not a game limitation.
- Photo Mode round 9 (`pm_flight.lua` "The game's camera model"): the solver sends the pitch for the elevation
  wanted at each frame's distance, measures only the model's residual from `getEye` / `getCenter` (a slow,
  critically damped follower), blends jumps of the look's meeting point over 0.5 s, and logs `eye smoothness`
  lines (TESTING.md V2-V5).

### Refit with distances up to 1725 m (session 2026-10-13_1915_session, 2026-10-13)

Round 9's fit only covered d 30-400 m. Session `2026-10-13_1915_session` traced Wanders at 780-1000 m, a glide in
from 1725 m and flights at 320-410 m (220 `cam trace`, 9 `eye check` lines; with `2026-10-13_1755_session` 106
distinct samples, d 25-1725 m, p 0-0.67). Its first sample already disagreed: `camera model: first sample offset
+0.463 rad, model +0.577, residual -0.114 (d=810 p=0.000)`, and the residual depended on the pitch at one distance
(d 800-1000: +0.027 at p 0.06, -0.032 at p 0.45). Fit script: least squares over the deduplicated samples.

- **Elevation (fitted): e = p + k1(d) (pi/2 - p) + k2(d), k1 = 0.07092 + 0.01624 ln d, k2 = 0.44961 d / (d +
  1185)**: rms 0.0013 rad, max 0.0041. Compared (rms / max): round 9's (a + b sqrt d)(pi/2 - p) 0.018 / 0.043;
  (a + b ln d)(pi/2 - p) 0.023 / 0.050; bounded or saturating k(d) alone (a hill, 1 - exp) 0.015 / 0.034; any of
  those with a free "straight down" P instead of pi/2 0.0056 / 0.025; (a + b ln d)(pi/2 - p) + c ln(1 + d/d1)
  0.0010 / 0.0041 (unbounded; the bounded k2 above chosen, the same within the data). So besides blending the pitch
  towards straight down, the game lifts the eye by an amount that grows with the distance and saturates (k2 < 0.45
  rad); at 800-1000 m that lift is most of the offset, nearly independent of the pitch. Extrapolated past 1725 m
  (the zoom limit is ~4137 m): unchecked.
- **A steep pitch far out passes straight down**: e(1.45, 900 m) = 1.67, e(1.30, 4000 m) = 1.70 (inferred from the
  fit; see "Bird's eye at pitch 1.45 inverted the keyboard pan").
- **The centre is lowered to the water level far out (verified, 120 trace frames)**: getCenter's z = 4 +
  max(getHeightAt, 0) x S(d), S a smoothstep from 1 at d <= 800 m to 0 at d >= 1500 m (fitted ends 800.3 / 1499.8;
  rms 0.19 m). The glide in from 1725 m: centre z 4.0 over ground 38.4 down to d 1499, then 4.2, 4.7, 5.7 ... 42.2 at
  823 m; a Wander at 980-1000 m: 54.8 over 61.8 (S 0.82). Not a time lag: the centre follows the distance set in the
  same frame. Round 9 assumed terrain + 4 at every distance, so far views put the eye too high or too low by up to the
  terrain height.
- What it did to Photo Mode's moves (offline replays with this fit as the game, `tests/square_photo_mode/test_flight.lua`):
  round 9's solver on a 4.3 km new-area glide (d up to ~1600 m) left the eye ~300 m below the plan with a 26 m
  second-difference spike (the game: 25.7 m, `eye smoothness (flight) ... worst f=63`); on a flight leg 0.74 m; on an
  r = 800 m eye-level Wander over hills several metres. With the refit and the centre surface: 0.02 m, 0.006 m and
  under 0.5 m. Whether the session's single 1 km spike (`eye smoothness (tour): d2 max=1016.704`, leg 3's new-area
  glide) came from a frame sent at pitch 0 although the look was flatter than the game can show (the eye then jumps
  up by d x the gap) is inferred; Photo Mode round 10 never sends such a frame (a last-resort bisection brings the
  centre closer along the look instead) and counts those frames (`guarded=` in the smoothness lines).


### Single-frame eye spikes during tours (session 2026-10-14_0229_sqrl-sqst, cause open)

- Photo Mode's eye smoothness lines (getEye per frame) of an Aerials tour: a flight leg `d2 max=24.912 m ...
  speed max=789 m/s worst f=394` although the drone flies 32 m/s, and the next leg's new-area glide `d2 max=56.314
  ... speed max=3407 m/s worst f=84` (its smootherstep peaks near 1.9 x distance / duration, ~1.3 km/s for its
  3.2 km). So single frames put the eye tens of metres off its path and back.
- Every frame that was traced (the first 40 of each tour) and both eye checks matched the camera model: residual
  -0.000, planned vs engine eye dz -0.22 / 0.05 / 0.11 m (d 216-469 m). The spikes fell in untraced frames.
- Offline, with the fitted model as the game, the eye-space solver keeps the eye within 1 m of the plan over 80 m
  ridges, including frames where the look is flatter than the game shows (test_flight "round 12: over ridges").
  Inferred: in those frames the game itself placed the eye off the model (its centre height, a clamp of its own,
  the frame order). Photo Mode round 12 logs an `eye spike` report (the frame's eye against the model's eye for the
  view read, the game's centre against the model's centre height, the solver state of the frames before):
  `plans/square_photo_mode/TESTING.md` CA5.
- **Update 2026-10-14 (session `2026-10-14_0434_session`, 12 `eye spike` reports, all in the smooth camera's
  click glides; the session's budget of 12 was spent before the two tours): no frame where the game left the
  camera model.** In every report the engine eye sat 0.7 m from the model's eye for the view read (a constant
  offset over the whole glide), the game's centre z equalled the model's to 0.1 m, nothing was clamped, guarded,
  blended or lifted. Two kinds:
  - 7 of 12 (d2 1.6-3.7 m) followed a long frame: the frame before the spike took 20-31 ms among 14-17 ms ones
    (spike 4: dt 0.0159, 0.0151, 0.0148, **0.0312**, 0.0141). The eye moved exactly along its timed path (the plan
    advanced 5.7 m in the 31 ms frame, 2.6-3.5 m in the others; ~200 m/s each), so the plain per-frame second
    difference spiked although the motion was smooth in time: a metric artefact. Paired with each step's own
    frame time the same frames give 0.2-0.5 m (the log's 0.1 m rounding). A long frame is still a visible hitch
    (the game's frame time), not something a camera path can fix.
  - 5 of 12 (d2 3.1-11.2 m, one glide at 04:37:01): the distance read back differed from the one sent the frame
    before by +3.8, +3.9, +10.4, +3.8, +0.2 m (x, y, angle, pitch exact). Only in the smooth camera's glide, which
    passed the wheel straight through; the glide ended by camera input (tilt) 30 frames later. Inferred: the
    player's wheel (the game eases a wheel step towards its own target distance, "Camera zoom limit") during the
    glide. Tours' traced frames never showed a read-back that differed from the view sent.
  - The moves' large `d2 max` values in the `eye smoothness` lines sat in the frames where the player's own input
    ended the move: the Aerials tour's `d2 max=32.0 m worst f=1731` of 1733 frames (`tour off (camera moved: pan)`),
    glides `ended by the camera input` at their worst frame (26.5 m at f=115, 11.8 m at f=58).
  - **The eye read in a plugin's `onStep` shows the view set the frame BEFORE** (verified, all 12 reports): each
    report's model eye for the view read equals the eye planned and sent in the previous frame (`model=` of spike 5
    = `plan=` of ring entry #105). A smoothness measure must pair the eye's step with the frame time it was planned
    for (the previous frame's dt), not the current one.
  - Photo Mode round 13: d2 at the frames' own times, the player's look input cuts the chain, at most 4 reports a
    move (16 a session), a look jolt over 0.05 rad reports too (the "This place" tour's hops had `look d2 max`
    0.060 / 0.079 rad at f=56 / f=16, unexplained: no report was left). The tours' own spikes of round 12 (0229
    session) stay unexplained: whether they were long frames and the player's input too is unknown (their worst
    frames f=394 / f=84 were not at a move's end).

### Tour eye jolts from the game's centre (session 2026-10-14_0606_session, 2026-10-14)

User: "I'm in Aerials now, still jumps as we move up terrain and sometimes when the camera shifts." The Aerials
tour at 06:08:12 (glide up from a road vehicle at -29,985, d 40) logged 4 `eye spike` reports, frames 66-70 (d2
2.87, 3.04, 1.62, 2.27 m at d 127-132 m), then nothing more (the per-move cap of 4); its `eye smoothness` line:
4083 frames, d2 max 30.1 m at f=1573 with look d2 0.048 rad, rms 0.77 m (a smooth flight leg: 0.07, session
`2026-10-14_0055_session`).

- **The game's centre left `getHeightAt + 4` for three frames (verified, the 4 reports)**: views #65 / #66 / #68 /
  #69 (centre y 1052.4 / 1053.4 / 1055.2 / 1056.2 on one slope) read centre z 23.5 / 24.1 / 23.1 / 24.0 against
  the model's 20.5 / 21.3 / 23.1 / 24.0: +3.0, +2.8, 0, 0 m (#67 not read; +2.2 m from frame 69's d2). The engine
  eye was off by the same (78.5 vs 75.3, 79.6 vs 76.6), at the distance and elevation set: the game kept its camera
  model and only its centre height changed. Under those centres the ground rose 0.9 m / m (getHeightAt 16.5 -> 20.0);
  the game's centre z minus 4 read 19.5, 20.1, (20.4), 19.1, 20.0: something ~3 m above the height map for ~4.5 m of
  the centre's path that merges into the slope above (inferred: a road or rail embankment / bridge deck, a
  vehicle, or a different terrain interpolation; nothing in the API tells the camera's centre surface apart from
  getHeightAt). In the 558 traced frames and 32 eye checks of all archived sessions the centre matched getHeightAt
  + 4 within 0.5 m, so such places are rare and local.
- **The sent views were not the cause (verified offline)**: they stepped unevenly (centre +2.1, +0.9, +2.9, +1.0 m,
  distance +2.8, +1.1, +3.7, +1.3 m: the look meeting a steepening slope), but the camera model puts each one on its
  planned eye within 0.13 m (the log's rounding) and the planned path's d2 is 0.21 m. Adding the measured centre
  offsets to those eyes reproduces the reports: 2.86 / 3.08 / 0.39 / 1.51 / 2.25 m against 2.87 / 3.04 / (below 1.5)
  / 1.62 / 2.27 (`tests/square_photo_mode/test_flight.lua` "round 13b: replay of the 0606 session").
- **A correction from the centre read can't help**: the read shows the view sent the frame before, so a frame-late
  correction leaves o(i) - o(i-1) on the eye and doubles the jolt (6.26 m against 3.2 m in the replay). A slow
  follower would only add a drift after each step. Below 800 m out every such place steps the eye by its height.
- **From 1500 m out the eye can't jolt**: the centre's z is the water level + 4 there whatever the ground ("The
  centre is lowered to the water level far out"), so a camera whose look-at point stays 1.6 km+ out has no
  coupling to the ground at all (inferred that the extra 3 m is lowered the same way as the terrain). The game's
  flattest look at 1.6-1.9 km is e ~0.56-0.59 rad, so such a camera flies about 0.9-1.1 km above the sea looking
  ~37 degrees down (within the ~4.1 km zoom limit). Photo Mode round 13b: the Aerials "High" look
  (`pm_flight.HIGH`); the replay over the logged ground and offsets: Drone d2 3.0 m, High 0.000 m.
- Open: the tour's d2 30 m at f=1573 (no report left). Photo Mode round 13b reports one line per jolt (the next
  30 frames later), up to 8 a move and 24 a session, and counts every spike frame (`spikes=` in the smoothness
  lines).
- **Session `2026-10-14_0633_session` (Aerials, Look Down, 4 legs; Look High, 2 tours)**: the High tours had no jolt
  of the game's (`spikes=0`, d2 max 0.35-0.51 m; their two reports were a long frame and the player's pan). Of the
  8 Down reports, 6 were the game's centre ABOVE the model by 1.6-8.4 m with the eye lifted by the same (within 0.4
  m; 0.9 of 1.6 at d 846 m), never below; one a model residual (eye 1.3 m off at ~1.6 km, centre exact). Each of the
  6 sat where `getHeightAt` under the centre fell steeply in the frames before (-7.3, -6.2, -13.0, -4.7 m in a
  single frame of 5-20 m of the centre's path: terrace or cut edges; two on a steady slope) or over a river (g
  -12.5 under water: the model's `max(g, 0) + 4` = 4.0, the game 12.4). The user saw "jerks before a big hill,
  over a factory, glitchy tilt over a river and a mountain": in 5 of the 6 the look's meeting point had just
  jumped (the solver's blend), so the tilt and the eye jolt come from the same places. Candidates for the surface
  the game uses there (to verify, Photo Mode round 14's `centre fit` lines): the terrain's base height
  (`api.engine.terrain.getBaseHeightAt`, "without terrain alignments", 4 m resolution: the cuts and terraces of
  roads, tracks and industries are alignments), and a river's own water level (`WaterMesh.waterLevel` per tile).
  Replay: `tests/square_photo_mode/test_flight.lua` "round 14: the 0633 spike reports, classified".

## `app.startGame2` from a running map editor crashes the load (verified in game 2026-10-13)

- A mod GUI plugin in the map editor called `app.startGame2(map, seed, date, tod, clouds, true, mods, configDict,
  modParams)` with a blank 20 x 160 tile map built like the menu's `createMap`
  (`gui/menu/new_game_or_map_settings_page.tl:79-102`). The call returned without error (`[SQMF] startGame2 ok`),
  the new game began loading without the old one being stopped (no "Game is stopped" line; "Seed text", "Active
  mods", "Map seed text", "Debug mode is active"), then a native crash (minidump) in the same second. Sessions
  `2026-10-13_2030_sqmf` and `2026-10-13_2035_sqmf` (same result twice).
- `app.stopGame()` right before it in the same call doesn't help: `stopGame ok`, `startGame2 ok`, no "Game is
  stopped" line, the same crash at "Debug mode is active" (session `2026-10-13_2037_sqmf`, 20:44Z). The stop is
  deferred; the load still starts over the running game.
- The base game calls `startGame2` only from the main menu, with no game running. Not yet ruled out: that the
  Lua-built blank map itself crashes the load (a control with a menu-sized map is open,
  `plans/square_map_format_probe/TESTING.md`).

## Smooth camera: the game draws a key's step before a mod can correct it (from the game log 2026-10-14, inferred, strong)

User report (Photo Mode round 10's smooth camera, session `2026-10-14_0055_session`): "jumps when first pressing a
direction, then smooths out". The `smooth trace` lines (read = `getCameraData` in the plugin's `onStep`, sent =
the view set last frame, step = read - sent, set = this frame's view) for the first key press (f=19-25, d = 799):

| f | read x, y | sent | step | set |
|---|---|---|---|---|
| 20 | -672, -744 | -672, -744 | 0 | -672, -744 |
| 21 | -657, -710 | -672, -744 | 14.8, 34.0 | -672, -743 |
| 22 | -654, -703 | -672, -743 | 17.3, 39.7 | -670, -740 |
| 23 | -653, -701 | -670, -740 | 16.9, 38.9 | -668, -734 |
| 25 | -646, -685 | -664, -725 | 17.4, 39.9 | -658, -711 |

- `read = sent + step` exactly: each frame the game adds the key's step to the view the mod set the frame before;
  no step goes on after the key is let go (f=52: step 0) and the step has no ramp of its own (37, 43, 42, 38 m: the
  game's keyboard pan at `keyboardCameraSpeedGame` 0.5 is about 1.2 x the distance per second).
- The `set` column is smooth (1, 3, 6, 9, 14 m), the `read` column is what the player described: a 37 m jump, then
  7, 2, 2, 15 m. So the frame the game draws is the read one (the game's step on the last frame's view), drawn
  before the mod's `onStep` sets its own: shown_n = sent_(n-1) + step_n. Inferred from the numbers and the report
  (no API tells the draw order).
- Consequence: the first frame of a key press always shows the game's whole step (one frame of normal camera
  speed), whatever the mod sends; a follower that eases from rest then makes it look like a jump and a stall. No mod
  code runs between the game's input and that frame (react.onStep only; no input action or key state is readable,
  gui.md "What camera input a mod can read"). Only a smaller game step would ease it: the keyboard camera speed
  (AppConfig `keyboardCameraSpeedGame`, 0..1, slider of the settings page's Keyboard tab, `settings_page.tl:653`;
  set by name like the graphics keys, untried) lowered while the smooth camera runs, with the mod scaling the steps
  back up. Open: whether a runtime change applies at once, its speed curve, and telling a key's step from a mouse
  drag's (only the keys would be slowed). Offline model: `tests/square_photo_mode/test_flight.lua` "round 11:
  smooth camera start" (removed with the feature in round 13).
- Photo Mode removed its smooth camera in round 13 (user, session `2026-10-14_0434_session`: "still jerky, we might
  have to give up on it"): the lever above couldn't be kept out of the settings file (PLAN.md "Round 12 camera"),
  and a click-to-glide on the normal camera doesn't remove the key jump.

## The Advanced Camera Tool: native keyframed camera paths (read from the game files and the binary 2026-10-14, untested)

- Settings > Advanced > "Enable Advanced Camera Tool" (AppConfig `cameraTool`, `settings_page.tl:1219`, "This tool
  can be used to create complex renderings") adds an "Advanced Camera" toggle next to the game bar's free camera
  button (`game_bar.tl:1125-1308`, `game_bar_widgets.tl:112-147`): it only shows / hides the native window
  `cameraManagerWindow` (`api.gui.byId.setVisible`) and listens for `stoppedCameraManagerAction`. The window is C++
  (`UI::CameraManager`, `Game/UI/Components/CameraManager.cpp` in the binary's strings); it stays visible
  (transparent) while the UI is hidden (`game.css.lua:19`: `CGameUI!hide-ui #cameraManagerWindow`).
- Key commands (the player's `settings_keys_v3.lua`): `camToolAddKeyframe` (Insert), `camToolClearKeyframes`
  (Home), `camToolPlayPause` (Space), `camToolStop` (Backspace), `camToolStartRecording` / `camToolCapture`
  (Return), `camToolLoad` / `camToolSave` / `camToolPlay` / `camToolPause` / `camToolPlayStop` (unbound). Its own
  keyboard speed: `keyboardCameraSpeed.cameraTool` (settings.lua). Icons: add above / below, edit, play, pause,
  stop, record, reset, resolution, fps, game speed, focal length, lat/long, load, save, detach (`gui/camera_tool/`).
- Its keys use the same structure as cutscenes (binary strings `m_data->keyFrames.camera`, `.fades`,
  `.environmentParams`, as the cutscene keyframe files' `camera` / `fades` / `environmentParams`); the userdata
  folder has `keyframes/` and `recordings/` next to `screenshots/` (empty for this player: never used). Inferred:
  the tool saves its paths as keyframe files there, and records frames to `recordings/`.
- What it means for a mod (inferred): a terrain-free camera path the engine plays (no setCameraData, no terrain
  under a centre), the game's own playback. A mod can show the window (`setVisible("cameraManagerWindow", true)`,
  as the base toggle) but has no API to add keys or press play; with `io` in the GUI state (unknown) it could write a
  keyframe file to `keyframes/` for the player to load. Photo Mode TESTING.md CB4 has the player try it by hand.

## No camera a mod can steer besides the normal one and a cutscene (binary strings + API 2026-10-14)

Photo Mode round 15 (user: "Is there no way to move the camera programmatically while in free camera mode?"):

- The Lua functions the game registers on `api.gui.camera` (the binary's registration strings, in order, between
  `getFrameTime01` and `letVehicleHorn`): `setManualCamera`, `getCameraData`, `setCameraData`,
  `getHeightAboveTerrain`, `getFollowEntity`, `followEntity`, `focusEntity`, `focusPosition`,
  `isFreeCameraMouseAttached`, `toggleFreeCameraMouseAttachment`, `enterFollowCameraCockpit`,
  `leaveFollowCameraCockpit`, `toggleFreeCamera`, `takeScreenshot`, `world2Screen`, `screen2World`, `getEye`,
  `getCenter`, `getNearFar`, `traceToTerrain`: the tealdef's list (`api/tealdef/api/gui.d.tl` Camera), nothing
  hidden. The free camera is the native follow action without an entity (`FollowAction.cpp`, `action-follow`,
  `!IsFreeCamera()`); its only Lua handles are the toggle and the mouse attachment. `setCameraData` drives the
  normal camera only (three sessions: "The free camera ignores setCameraData").
- The Advanced Camera Tool (`CameraManager`, `camTool*` key commands) has no Lua functions; its keys are the
  cutscene structure, played by the same `CameraAction` as `api.gui.mission.playCutscene`.
- So a mod has exactly two cameras: the normal one (`setCameraData`: centre on the terrain, the game's camera
  model) and a cutscene (static keyframe files; entity attachments the only runtime input). Photo Mode round 15
  tries the cutscene as a tour (environment.md "Cutscenes from a mod", the attachment chain).

## The keyboard pan scales with the camera's distance: far, flat views pan fast (inferred 2026-10-14)

- Measured (session `2026-10-14_0434_session`, "Smooth camera" above): the keyboard pan moves about 1.2 x the
  camera's distance per second (keyboard speed 0.5), from the first to the last input frame.
- A view far from its look-at point with a flat look (a horizon shot clamped at d 4000 with the eye ~800 m up, a
  Wander at d ~500 with the eye 100-200 m up, an Aerials Down leg at d ~500, eye ~220 m up) pans several times
  faster than the game's own camera at that eye height, whose camera model steepens the look at large distances.
  Likely the "hyper sensitive" camera the Photo Mode player reported after tours and shots (rounds 13 and 15; no
  setting or input state changed, no camera write of Photo Mode's after a move ended in
  `2026-10-14_0658_session`). Inferred: Photo Mode round 15 logs a `hand-back` line (d, eye height, d / height,
  pan speed) at every move end and shot; TESTING.md CD5 checks whether a zoom in (the wheel) makes it go away.
- 2026-10-14 (round 16): the user still saw the fast camera after the round 15 build, but that session's log is
  lost (`2026-10-14_0733_session` was archived at 07:38 while the game ran on to ~07:53; the next start overwrote
  `stdout.txt`), so no `hand-back` line was read and the cause stays inferred. Photo Mode now eases a far / flat
  hand-back in (its PLAN.md "Round 16 camera" item 5); whether the report goes away is its TESTING.md CE5.

## Past the map edge the game draws no terrain: the sky's gradient fills the void (user screenshot 2026-10-14)

- A Photo Mode Aerials view near the map edge (most likely its round 15 DEV cutscene flight, the DEV mod was on in
  `2026-10-14_0733_session`: 250 m up, 20 degrees down, `fovY` 0.8, keys planned only 150 m inside
  `api.engine.terrain.getBoundingBox()`; the run's log is lost) showed the terrain ending
  in a straight edge with the sky's gradient (purple / orange in a dusk look) below the horizon beyond it. So a
  camera that must not show the edge has to keep the ground its picture reaches on the map, not only its eye:
  at 20 degrees down with `fovY` 0.8 the frame's top is about at the horizon, so the edge shows from kilometres
  away (haze softens it). Photo Mode round 16 keeps the ground 2.5 km out across the frame's width on the map
  (at most 30 % of the map's smaller side; `pm_cutscene` `viewInside`) and keeps tour waypoints 2.5 km (High,
  Horizon) / 0.9 km (Down) inside (`pm_flight` `inner`). Seen in the screenshot; the geometry inferred.

## `focusPosition` ignores the height (dev console, verified in game 2026-10-14)

User's dev-console test (live log, 18:5x UTC, session after `2026-10-14_0842_session`):
`focusPosition(Vec3f(c.x + 500, c.y, c.z + 300), 600)` moved the camera 500 m east, but `getCenter` read
z 177.19 over ground 173.19 afterwards: the look point is put back on `getHeightAt + 4` like every other normal
camera setter, so `focusPosition` gives no terrain-free centre. Also seen: the console's `print` output goes to
`stdout.txt`, not to the console window (an earlier `spawn ok=` print never showed in the console either).

## The free camera does not follow an entity (dev console, verified in game 2026-10-14)

User's console test: `followEntity(V, true)` on a random transport vehicle, then `toggleFreeCamera()` in the same
line: the free camera started where the follow had put the view and did not follow the vehicle. With the earlier
results (the free camera ignores `setCameraData`, three sessions; no free-camera setter in the binary, round 15),
no API moves or attaches the free camera. Also: the dev console can't take input while the free camera is on, so
console tests of the free camera have to start it from the same line.
